import 'package:flutter/material.dart';

import '../data/error_mapper.dart';
import '../data/machine_repository.dart';
import '../data/menu_suggestion_repository.dart';
import '../domain/ai_menu.dart';
import '../domain/machine.dart';
import 'error_snack_bar.dart';
import 'theme/app_theme.dart';
import 'theme/design_tokens.dart';
import 'widgets/surface_card.dart';

/// SCR-03 今日のメニュー提案（FEAT-03）。
///
/// 前段（FEAT-02・[BodyPartFilterPage]）で選んだ部位と器具を受け取る。
///
/// ## AI に何をさせていないか（ADR-0021）
///
/// **種目名はここで DB から引いている。** AI が返すのは `menu_id` と実施順
/// だけで、名前もやり方も返らない。存在しない種目が出ようがない。
///
/// ## 提案は保存しない（§5）
///
/// 画面の状態としてだけ持つ。戻れば消える。**選んだ種目をそのまま記録へ回す**
/// のは W-16（FEAT-04）の担当で、`menu_id` がそのまま明細になる。
class MenuSuggestionPage extends StatefulWidget {
  const MenuSuggestionPage({
    super.key,
    required this.bodyPart,
    required this.machines,
    this.repository,
    this.machineRepository,
  });

  final BodyPart bodyPart;

  /// 前段で選んだ器具。**0件では開かない**（呼び出し側で止める）。
  final List<TrainingMachine> machines;

  final MenuSuggestionRepository? repository;
  final MachineRepository? machineRepository;

  @override
  State<MenuSuggestionPage> createState() => _MenuSuggestionPageState();
}

class _MenuSuggestionPageState extends State<MenuSuggestionPage> {
  late final _repository = widget.repository ?? MenuSuggestionRepository();
  late final _machines = widget.machineRepository ?? MachineRepository();

  List<ResolvedAiMenu>? _plan;
  String? _error;
  bool _isGenerating = false;

  /// 生成する。**押されたときだけ呼ぶ。** 自動で走らせない（従量課金）。
  Future<void> _generate() async {
    if (_isGenerating) return;
    // 器具0件で呼ぶと、選ぶものが無いまま課金だけが出る（FEAT-02 §10 #1）。
    if (widget.machines.isEmpty) return;

    setState(() {
      _isGenerating = true;
      _error = null;
    });
    try {
      // 種目名は AI からではなく DB から引く（ADR-0021）。
      // 生成と並行して取る。どちらも相手の結果を必要としない。
      final results = await Future.wait([
        _repository.generate(
          bodyPart: widget.bodyPart,
          machineIds: [for (final m in widget.machines) m.id],
        ),
        _machines.fetchMenus(),
      ]);
      final plan = results[0] as AiMenuPlan;
      final menus = results[1] as List<TrainingMenu>;

      if (!mounted) return;
      setState(() {
        _plan = resolveAiMenus(plan, {
          for (final menu in menus) menu.id: (name: menu.name, howTo: menu.howTo),
        });
      });
    } catch (error) {
      if (!mounted) return;
      final failure = mapError(error);
      // **自動で再送しない。** 再試行は利用者が押したときだけ。
      setState(() => _error = failure.message);
      showAppFailure(context, failure);
    } finally {
      if (mounted) setState(() => _isGenerating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;

    return Scaffold(
      backgroundColor: t.pageBg,
      appBar: AppBar(title: const Text('今日のメニュー')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: Dimens.maxContentWidth),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 28),
            children: [
              _buildInput(t),
              const SizedBox(height: 18),
              if (_error != null) ...[
                _buildError(t, _error!),
                const SizedBox(height: 18),
              ],
              if (_plan != null) _buildPlan(t, _plan!),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildInput(DesignTokens t) {
    return SurfaceCard(
      radius: Dimens.radiusCard,
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: 12,
        children: [
          Text(
            '${widget.bodyPart.label}・器具${widget.machines.length}台',
            style: TextStyle(
              color: t.textColor,
              fontSize: 15,
              fontWeight: FontWeight.w800,
            ),
          ),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final machine in widget.machines)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: t.hoverSurface,
                    borderRadius: BorderRadius.circular(Dimens.radiusChip),
                    border: Border.all(color: t.hairline),
                  ),
                  child: Text(
                    machine.name,
                    style: TextStyle(color: t.textColor, fontSize: 11),
                  ),
                ),
            ],
          ),
          Text(
            '登録済みの種目の中からだけ選びます。新しい種目は作りません。',
            style: TextStyle(
              color: t.textColor.withValues(alpha: 0.6),
              fontSize: 11,
            ),
          ),
          const SizedBox(height: 2),
          SizedBox(
            height: 52,
            child: Ink(
              decoration: BoxDecoration(
                gradient: _isGenerating ? null : t.ctaGradient,
                color: _isGenerating ? t.hoverSurface : t.ctaColor,
                borderRadius: BorderRadius.circular(Dimens.radiusCta),
              ),
              child: InkWell(
                onTap: _isGenerating ? null : _generate,
                borderRadius: BorderRadius.circular(Dimens.radiusCta),
                child: Center(
                  child: _isGenerating
                      ? SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: t.textColor,
                          ),
                        )
                      : Text(
                          _plan == null ? 'メニューを組む' : '組み直す',
                          style: TextStyle(
                            color: t.ctaFg,
                            fontSize: 17,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                ),
              ),
            ),
          ),
          if (_isGenerating)
            Text(
              '考えています。15秒ほどかかることがあります。',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: t.textColor.withValues(alpha: 0.72),
                fontSize: 11,
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildError(DesignTokens t, String message) => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: t.warn.withValues(alpha: 0.10),
      borderRadius: BorderRadius.circular(Dimens.radiusCta),
      border: Border.all(color: t.warn.withValues(alpha: 0.45)),
    ),
    child: Text(message, style: TextStyle(color: t.textColor, fontSize: 12)),
  );

  Widget _buildPlan(DesignTokens t, List<ResolvedAiMenu> plan) {
    if (plan.isEmpty) {
      return _buildError(t, '提案できる種目がありませんでした。器具を選び直してください。');
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: 10,
      children: [
        Text(
          'この順で進めます',
          style: TextStyle(
            color: t.textColor.withValues(alpha: 0.72),
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
        for (final menu in plan)
          SurfaceCard(
            radius: Dimens.radiusCta,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              spacing: 12,
              children: [
                // 実施順。AI が付けた `order` をそのまま出す。
                Text(
                  '${menu.order}',
                  style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)
                      .merge(kTabularFigures)
                      .copyWith(color: t.accent),
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    spacing: 4,
                    children: [
                      // **名前は DB から引いたもの。** AI は返していない。
                      Text(
                        menu.name,
                        style: TextStyle(
                          color: t.textColor,
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      Text(
                        menu.reason,
                        style: TextStyle(
                          color: t.textColor.withValues(alpha: 0.72),
                          fontSize: 11,
                        ),
                      ),
                      // やり方は空を許容する（ADR-0021）。無ければ出さない。
                      if ((menu.howTo ?? '').isNotEmpty)
                        Text(
                          menu.howTo!,
                          style: TextStyle(
                            color: t.textColor.withValues(alpha: 0.55),
                            fontSize: 10,
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        const SizedBox(height: 6),
        Text(
          '記録は「トレーニング」から行います。この提案は保存されません。',
          style: TextStyle(
            color: t.textColor.withValues(alpha: 0.5),
            fontSize: 11,
          ),
        ),
      ],
    );
  }
}
