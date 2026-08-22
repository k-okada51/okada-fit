import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../data/dashboard_repository.dart';
import '../domain/dashboard.dart';
import '../domain/nutrition.dart';
import 'error_snack_bar.dart';
import 'theme/app_theme.dart';
import 'theme/design_tokens.dart';
import 'widgets/surface_card.dart';

/// SCR-01 ダッシュボード（FEAT-05）。下部ナビの「ダッシュボード」。
///
/// **記録を振り返る画面である。** ホームではない（ADR-0024）。
///
/// | 出すもの | 由来 |
/// |---|---|
/// | 摂取ゲージ | `weight_kg` と `intake_g` から Dart が算出（FEAT-07） |
/// | 今月の実施回数 | `training_count`。**期間切替に依存しない**（§3） |
/// | ヒートマップ | `heatmap`。**返るのは塗る日だけ** |
///
/// 体重が未設定なら**ゲージを描かず案内に差し替える**（FEAT-07 §7）。
/// エラーにしない。ヒートマップと回数は通常どおり出す（NFR-AVAIL-05）。
class DashboardPage extends StatefulWidget {
  const DashboardPage({super.key, this.repository, this.now});

  final DashboardRepository? repository;

  /// 「いま」。省略時は端末時刻（ADR-0014）。
  final DateTime Function()? now;

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
  late final _repository = widget.repository ?? DashboardRepository();

  DashboardPeriod _period = DashboardPeriod.month;
  Dashboard? _data;
  bool _isLoading = true;

  DateTime get _nowValue => (widget.now ?? DateTime.now)();

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _isLoading = true);
    try {
      final data = await _repository.fetch(_nowValue, _period);
      if (!mounted) return;
      setState(() => _data = data);
    } catch (error) {
      if (!mounted) return;
      showError(context, error, onRetry: _load);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _changePeriod(DashboardPeriod period) {
    if (_period == period || _isLoading) return;
    setState(() => _period = period);
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final data = _data;

    return Column(
      children: [
        SizedBox(
          height: Dimens.headerHeight,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                '記録を振り返る',
                style: TextStyle(
                  color: t.textColor,
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
        ),
        Expanded(
          child: data == null && _isLoading
              ? const Center(child: CircularProgressIndicator())
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(20, 4, 20, 28),
                    children: [
                      if (data != null) ...[
                        _buildGauge(t, data),
                        const SizedBox(height: 18),
                        _buildTrainingCount(t, data),
                        const SizedBox(height: 18),
                      ],
                      _buildPeriodSwitch(t),
                      const SizedBox(height: 12),
                      if (data != null) _buildHeatmap(t, data),
                    ],
                  ),
                ),
        ),
      ],
    );
  }

  /// 摂取ゲージ。**式は書かない**（FEAT-07 §4.5 案(b)）。
  Widget _buildGauge(DesignTokens t, Dashboard data) {
    final target = data.proteinTarget;

    if (target is! ProteinTargetOk) {
      // 未設定・不正値。**エラーにしない**（FEAT-07 §4.3）。
      return SurfaceCard(
        radius: Dimens.radiusCard,
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          spacing: 8,
          children: [
            Text(
              '今日のタンパク質',
              style: TextStyle(
                color: t.textColor.withValues(alpha: 0.75),
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
            Text(
              target is ProteinTargetUnset
                  ? '体重を登録すると目標が表示されます。'
                  : '体重の値を確認してください。目標を計算できません。',
              style: TextStyle(color: t.textColor, fontSize: 14),
            ),
          ],
        ),
      );
    }

    final pct = data.ratePct ?? 0;

    return SurfaceCard(
      radius: Dimens.radiusCard,
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: 10,
        children: [
          Text(
            '今日のタンパク質',
            style: TextStyle(
              color: t.textColor.withValues(alpha: 0.75),
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            spacing: 4,
            children: [
              Text(
                // 表示は整数 g（FEAT-07 §4.2）。丸めは UI 層の担当。
                '${data.intakeG.round()}',
                style: const TextStyle(fontSize: 32, fontWeight: FontWeight.w800, height: 1)
                    .merge(kTabularFigures)
                    .copyWith(color: t.textColor),
              ),
              Text(
                '/ ${target.targetG.round()}g',
                style: TextStyle(
                  color: t.textColor.withValues(alpha: 0.7),
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Spacer(),
              Text(
                '$pct%',
                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800)
                    .merge(kTabularFigures)
                    .copyWith(color: t.accent),
              ),
            ],
          ),
          _Bar(progress: pct / 100),
        ],
      ),
    );
  }

  /// 今月のトレーニング。**期間切替に依存しない**（§3）。
  Widget _buildTrainingCount(DesignTokens t, Dashboard data) {
    final pct = data.trainingRatePct;

    return SurfaceCard(
      radius: Dimens.radiusCard,
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: 10,
        children: [
          Text(
            '今月のトレーニング',
            style: TextStyle(
              color: t.textColor.withValues(alpha: 0.75),
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            spacing: 4,
            children: [
              Text(
                '${data.doneDays}',
                style: const TextStyle(fontSize: 32, fontWeight: FontWeight.w800, height: 1)
                    .merge(kTabularFigures)
                    .copyWith(color: t.textColor),
              ),
              Text(
                '/ ${data.targetCount}回',
                style: TextStyle(
                  color: t.textColor.withValues(alpha: 0.7),
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Spacer(),
              if (pct != null)
                Text(
                  '$pct%',
                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800)
                      .merge(kTabularFigures)
                      .copyWith(color: t.accent),
                ),
            ],
          ),
          if (pct != null) _Bar(progress: pct / 100),
        ],
      ),
    );
  }

  Widget _buildPeriodSwitch(DesignTokens t) {
    return Row(
      spacing: 8,
      children: [
        for (final period in DashboardPeriod.values)
          Expanded(
            child: Material(
              color: Colors.transparent,
              child: Ink(
                decoration: BoxDecoration(
                  color: _period == period ? t.ctaSoft : Colors.transparent,
                  borderRadius: BorderRadius.circular(Dimens.radiusInput),
                  border: Border.all(
                    color: _period == period ? t.accentBorder : t.hairline,
                  ),
                ),
                child: InkWell(
                  // 読込中は切り替えさせない（FEAT-07 §7 の「読込中は非活性」）。
                  onTap: _isLoading ? null : () => _changePeriod(period),
                  borderRadius: BorderRadius.circular(Dimens.radiusInput),
                  child: SizedBox(
                    height: 38,
                    child: Center(
                      child: Text(
                        period.label,
                        style: TextStyle(
                          color: _period == period
                              ? t.accent
                              : t.textColor.withValues(alpha: 0.6),
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }

  /// ヒートマップ。**返るのは塗る日だけ**なので、マスは範囲から自分で作る。
  Widget _buildHeatmap(DesignTokens t, Dashboard data) {
    final range = buildDashboardRange(_nowValue, _period);
    final days = datesIn(
      DateTime.parse(range.rangeStart),
      DateTime.parse(range.rangeEnd),
    );
    final done = data.doneDates;
    final names = {for (final day in data.heatmap) day.date: day.menuNames};

    return SurfaceCard(
      radius: Dimens.radiusCard,
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: 12,
        children: [
          Text(
            'ジムに行った日',
            style: TextStyle(
              color: t.textColor.withValues(alpha: 0.75),
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final day in days)
                Tooltip(
                  message: done.contains(formatDate(day))
                      ? '${day.month}/${day.day}: ${(names[formatDate(day)] ?? const []).join('・')}'
                      : '${day.month}/${day.day}',
                  child: Container(
                    width: 26,
                    height: 26,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: done.contains(formatDate(day)) ? t.fill : t.ringTrack,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      '${day.day}',
                      style: const TextStyle(fontSize: 9, fontWeight: FontWeight.w700)
                          .merge(kTabularFigures)
                          .copyWith(
                            color: done.contains(formatDate(day))
                                ? t.ctaFg
                                : t.textColor.withValues(alpha: 0.45),
                          ),
                    ),
                  ),
                ),
            ],
          ),
          if (data.heatmap.isEmpty)
            Text(
              'この期間の記録はありません。',
              style: TextStyle(
                color: t.textColor.withValues(alpha: 0.5),
                fontSize: 11,
              ),
            ),
        ],
      ),
    );
  }
}

/// 達成率のバー。円グラフは SCR-00 が持っているので、ここは横棒にする。
class _Bar extends StatelessWidget {
  const _Bar({required this.progress});

  final double progress;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;

    return ClipRRect(
      borderRadius: BorderRadius.circular(Dimens.radiusChip),
      child: SizedBox(
        height: 8,
        child: Stack(
          children: [
            Positioned.fill(child: ColoredBox(color: t.ringTrack)),
            FractionallySizedBox(
              // 100%で頭打ち。負にもしない。
              widthFactor: math.min(1, math.max(0, progress)),
              child: ColoredBox(color: t.fill),
            ),
          ],
        ),
      ),
    );
  }
}
