import 'package:flutter/material.dart';

import '../data/dashboard_repository.dart';
import '../domain/dashboard.dart';
import 'error_snack_bar.dart';
import 'theme/app_theme.dart';
import 'theme/design_tokens.dart';
import 'widgets/surface_card.dart';

/// SCR-01 ダッシュボード（FEAT-05）。下部ナビの「ダッシュボード」。
///
/// **記録を振り返る画面である。** ホームではない（ADR-0024）。
/// 原本は Claude Design の `SCR-01 Dashboard.dc.html`。
///
/// ## 期間切替（日/週/月）を持たない
///
/// 設計の `p_period` は `[仮]` である（FEAT-05 §3・§10-7）。「日」を選ぶと
/// ヒートマップが1マスしか出ず、振り返りにならない。デザインどおり
/// **月固定＋ ←/→ で前後の月**にした。RPC は `p_range_start`/`p_range_end` を
/// 受けるので、サーバ側の変更は要らない。
///
/// ## デザインに従わない箇所
///
/// | デザイン | ここでの実装 | 根拠 |
/// |---|---|---|
/// | 平均タンパク質 | **出さない** | ADR-0024 §4 #8・FEAT-05 §10 #5 |
/// | P目標を達成した日 | **出さない** | RPC が日別のタンパク質合計を返さない |
///
/// **「週あたりのジム」は出す。** 目標は月次のまま（RULE-007）で、これは月の
/// 実績を週へ割った表示指標である。2つ目の目標ではない（2026-08-23 決定）。
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

  /// 見ている月。既定は当月。**当日は動かさない**（ゲージは常に当日）。
  late DateTime _viewedMonth = DateTime(_nowValue.year, _nowValue.month, 1);

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
      final data = await _repository.fetch(
        _nowValue,
        DashboardPeriod.month,
        viewedMonth: _viewedMonth,
      );
      if (!mounted) return;
      setState(() => _data = data);
    } catch (error) {
      if (!mounted) return;
      showError(context, error, onRetry: _load);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _shift(int delta) {
    if (_isLoading) return;
    final next = shiftMonth(_viewedMonth, delta);
    // 未来は見せない。データが存在しえない月を出しても意味が無い。
    if (delta > 0 && !canGoForward(_viewedMonth, _nowValue)) return;
    setState(() => _viewedMonth = next);
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
                'ダッシュボード',
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
                      _buildCalendar(t, data),
                      const SizedBox(height: 18),
                      if (data != null) _buildStats(t, data),
                    ],
                  ),
                ),
        ),
      ],
    );
  }

  /// 月のカレンダー。デザインの最上段のカード。
  ///
  /// **返るのは塗る日だけ**（§3）。マスは月の日数から自分で作り、
  /// 1日の曜日ぶんだけ先頭に空きを置いて曜日列を合わせる。
  Widget _buildCalendar(DesignTokens t, Dashboard? data) {
    final done = data?.doneDates ?? const <String>{};
    final names = {
      for (final day in data?.heatmap ?? const []) day.date: day.menuNames,
    };
    final first = _viewedMonth;
    final total = daysInMonth(first);
    // `DateTime.weekday` は 月=1…日=7。日曜始まりの表に合わせて 7 を 0 に畳む。
    final leading = first.weekday % 7;

    return SurfaceCard(
      radius: Dimens.radiusCard,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: 14,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '${first.month}月のジム記録',
                  style: TextStyle(
                    color: t.textColor,
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              _ArrowButton(
                symbol: '←',
                onTap: _isLoading ? null : () => _shift(-1),
              ),
              const SizedBox(width: 8),
              _ArrowButton(
                symbol: '→',
                // 当月より先へは進ませない。
                onTap: _isLoading || !canGoForward(_viewedMonth, _nowValue)
                    ? null
                    : () => _shift(1),
              ),
            ],
          ),
          Row(
            children: [
              for (final label in const ['日', '月', '火', '水', '木', '金', '土'])
                Expanded(
                  child: Center(
                    child: Text(
                      label,
                      style: TextStyle(
                        color: t.textColor.withValues(alpha: 0.55),
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
            ],
          ),
          GridView.count(
            crossAxisCount: 7,
            mainAxisSpacing: 6,
            crossAxisSpacing: 6,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            children: [
              // 1日の曜日まで空ける。
              for (var i = 0; i < leading; i++) const SizedBox.shrink(),
              for (var day = 1; day <= total; day++)
                _DayCell(
                  day: day,
                  isDone: done.contains(
                    formatDate(DateTime(first.year, first.month, day)),
                  ),
                  menuNames:
                      names[formatDate(
                        DateTime(first.year, first.month, day),
                      )] ??
                      const [],
                ),
            ],
          ),
          Row(
            spacing: 16,
            children: [
              _Legend(color: t.fill, label: 'ジムに行った'),
              _Legend(color: t.ringTrack, label: '行っていない'),
            ],
          ),
        ],
      ),
    );
  }

  /// 統計カード。デザインの2×2。**2枚は作らない**（クラスのコメント参照）。
  Widget _buildStats(DesignTokens t, Dashboard data) {
    // **`IntrinsicHeight` で高さを揃える。**
    //
    // `CrossAxisAlignment.stretch` だけだと落ちる。`ListView` の中の `Row` は
    // 縦の制約が無限で、伸ばす先が決まらないためである
    // （`Null check operator used on a null value`・2026-08-23 実機で発生）。
    //
    // `IntrinsicHeight` が先に高いほうの子を測り、有限の高さを与える。
    // 子が2枚の小さなカードなので、余分な測定の負荷は問題にならない。
    return IntrinsicHeight(
      child: Row(
        spacing: 12,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: _StatCard(
              label: 'ジムに行った日数',
              value: '${data.doneDays}',
              unit: '日',
            ),
          ),
          Expanded(
            child: _StatCard(
              label: '週あたりのジム',
              // 月の実績を週へ割った**表示指標**。目標は月次のまま（RULE-007）。
              value: _formatRate(
                weeklyGymRate(data.doneDays, daysInMonth(_viewedMonth)),
              ),
              unit: '回',
              // 月次の目標も併記する。どちらが目標かを取り違えさせない。
              note: '今月の目標 ${data.targetCount}回',
            ),
          ),
        ],
      ),
    );
  }

  static String _formatRate(double value) => value == value.roundToDouble()
      ? value.toStringAsFixed(0)
      : value.toStringAsFixed(1);
}

/// カレンダーの1マス。
class _DayCell extends StatelessWidget {
  const _DayCell({
    required this.day,
    required this.isDone,
    required this.menuNames,
  });

  final int day;
  final bool isDone;
  final List<String> menuNames;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;

    return Tooltip(
      message: isDone && menuNames.isNotEmpty ? menuNames.join('・') : '$day日',
      child: Container(
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: isDone ? t.fill : t.ringTrack,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Text(
          '$day',
          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)
              .merge(kTabularFigures)
              .copyWith(
                color: isDone ? t.ctaFg : t.textColor.withValues(alpha: 0.5),
              ),
        ),
      ),
    );
  }
}

/// 前月・翌月のボタン。デザインの `←` `→`。
class _ArrowButton extends StatelessWidget {
  const _ArrowButton({required this.symbol, required this.onTap});

  final String symbol;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final radius = BorderRadius.circular(Dimens.radiusInput);
    final enabled = onTap != null;

    return Material(
      color: Colors.transparent,
      child: Ink(
        decoration: BoxDecoration(
          borderRadius: radius,
          border: Border.all(color: t.hairline),
        ),
        child: InkWell(
          onTap: onTap,
          borderRadius: radius,
          child: SizedBox(
            width: 40,
            height: 34,
            child: Center(
              child: Text(
                symbol,
                style: TextStyle(
                  color: t.textColor.withValues(alpha: enabled ? 0.8 : 0.25),
                  fontSize: 15,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 凡例。
class _Legend extends StatelessWidget {
  const _Legend({required this.color, required this.label});

  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;

    return Row(
      mainAxisSize: MainAxisSize.min,
      spacing: 6,
      children: [
        Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(3),
          ),
        ),
        Text(
          label,
          style: TextStyle(
            color: t.textColor.withValues(alpha: 0.65),
            fontSize: 11,
          ),
        ),
      ],
    );
  }
}

/// 統計カード。デザインの下段。
class _StatCard extends StatelessWidget {
  const _StatCard({
    required this.label,
    required this.value,
    required this.unit,
    this.note,
  });

  final String label;
  final String value;
  final String unit;

  /// 数値の下の小さな補足。
  final String? note;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final note = this.note;

    return SurfaceCard(
      radius: Dimens.radiusCard,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: 6,
        children: [
          Text(
            label,
            style: TextStyle(
              color: t.textColor.withValues(alpha: 0.72),
              fontSize: 11,
            ),
          ),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            spacing: 3,
            children: [
              Text(
                value,
                style: const TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.w800,
                  height: 1,
                ).merge(kTabularFigures).copyWith(color: t.textColor),
              ),
              Text(
                unit,
                style: TextStyle(
                  color: t.textColor.withValues(alpha: 0.7),
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          if (note != null)
            Text(
              note,
              style: TextStyle(
                color: t.textColor.withValues(alpha: 0.5),
                fontSize: 10,
              ),
            ),
        ],
      ),
    );
  }
}
