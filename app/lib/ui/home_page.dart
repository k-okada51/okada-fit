import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../data/auth_repository.dart';
import '../data/profile_repository.dart';
import '../domain/nutrition.dart';
import '../domain/profile.dart';
import 'error_snack_bar.dart';
import 'food_list_page.dart';
import 'machine_list_page.dart';
import 'profile_page.dart';
import 'theme/app_theme.dart';
import 'theme/design_tokens.dart';

/// SCR-00 トップ（ADR-0024）。
///
/// **本ADRで初めて設計に載る画面である。** 設計書は SCR-01〜05 しか定義していない。
/// 原本は Claude Design の `SCR-00 トップ.dc.html`。
///
/// デザインにあって**作らないもの**が3つある。設計に無いか、決定と食い違うため。
///
/// | 作らないもの | 理由 |
/// |---|---|
/// | 1食ペース目安（朝/昼/夜/間食） | **食事スロットの概念が無い。** `meal_logs` に列が無い（ADR-0024 ⚠️） |
/// | 今週のトレーニング（7日） | **`target_training_count` は月次**（RULE-007）。週次にするか未決（同 ⚠️） |
/// | 不足分の食材 | FEAT-09（W-13）の担当。未実装 |
///
/// 下部ナビと CTA の枠は [AppShell] が持つ。ここは中身だけを描く。
class HomePage extends StatefulWidget {
  const HomePage({
    super.key,
    required this.authRepository,
    required this.onOpenDashboard,
    this.profileRepository,
    this.today,
  });

  final AuthRepository authRepository;

  /// 「記録を振り返る」を押したとき。行き先は SCR-01（ダッシュボードのタブ）。
  final VoidCallback onOpenDashboard;

  /// テストから差し替えられるよう開けてある。省略時は共有クライアントを使う。
  final ProfileRepository? profileRepository;

  /// テストから「今日」を固定するために開けてある。省略時は端末の現在日。
  final DateTime? today;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  late final ProfileRepository _profileRepository =
      widget.profileRepository ?? ProfileRepository();

  /// 読み込み済みの行。`null` の間は読込中か、読込に失敗している。
  Profile? _profile;

  bool _isLoading = true;

  /// 二重タップ防止。
  bool _isSigningOut = false;

  /// ⚠️ **ダミーである。実データではない。**
  ///
  /// 今日の摂取量は FEAT-05 の RPC `get_dashboard` から取る。繋ぐのは W-17。
  /// 値はデザインの既定（朝22＋昼38＋夜0＋間食21）をそのまま使っている。
  ///
  /// TODO(W-17): `get_dashboard` の応答に差し替える。
  static const double _dummyIntakeG = 81;

  @override
  void initState() {
    super.initState();
    _load();
  }

  /// 体重を読む。**目標値の唯一の入力**である（RULE-001）。
  Future<void> _load() async {
    setState(() => _isLoading = true);
    try {
      final profile = await _profileRepository.fetchProfile();
      if (!mounted) return;
      setState(() => _profile = profile);
    } catch (error) {
      if (!mounted) return;
      // 写像は error_mapper（W-05）に任せる。ここで例外を分類しない。
      showError(context, error, onRetry: _load);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _signOut() async {
    if (_isSigningOut) return;
    setState(() => _isSigningOut = true);
    try {
      await widget.authRepository.signOut();
      // 画面の切り替えは AuthGate が `onAuthStateChange` を受けて行う。
      // ここで Navigator を触らない。
    } catch (error, stackTrace) {
      debugPrintStack(label: 'signOut: $error', stackTrace: stackTrace);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('サインアウトできませんでした。時間をおいて試してください。')),
      );
    } finally {
      if (mounted) setState(() => _isSigningOut = false);
    }
  }

  void _open(Widget page) {
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => page));
  }

  /// 設定（SCR-05）を開いて、戻ったら体重を読み直す。
  ///
  /// 体重が変われば目標値も変わる。戻った画面に古い数字を残さない。
  Future<void> _openSettings() async {
    await Navigator.of(
      context,
    ).push(MaterialPageRoute<void>(builder: (_) => const ProfilePage()));
    if (!mounted) return;
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _buildHeader(),
        Expanded(
          child: _isLoading
              ? const Center(child: CircularProgressIndicator())
              : _buildBody(),
        ),
      ],
    );
  }

  /// ヘッダ。左に日付、右に歯車（SCR-05 へ）。
  ///
  /// デザインは右上に配色の切替ボタンも置いているが、**それはモックを見比べる
  /// ためのものと解釈する**（ADR-0024 §3）。切替は SCR-05 に1つだけ置く。
  ///
  /// デザインの `padding:22px 20px 0` は高さを [Dimens.headerHeight] に揃えた。
  Widget _buildHeader() {
    final t = context.tokens;
    final today = widget.today ?? DateTime.now();

    return SizedBox(
      height: Dimens.headerHeight,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: Row(
          children: [
            Expanded(
              child: Text(
                _formatToday(today),
                style: TextStyle(
                  color: t.textColor.withValues(alpha: 0.6),
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            _SquareIconButton(
              // デザインの `⚙` の代用。字形は違うが役割は同じ。
              icon: Icons.settings_outlined,
              tooltip: '設定',
              onTap: _openSettings,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBody() {
    return ListView(
      // デザインの `main` の `padding:18px 20px 28px`。
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 28),
      children: [
        _buildProteinCard(),
        const SizedBox(height: 18),
        _buildLookBackCard(),
        const SizedBox(height: 18),
        _buildTemporaryMenu(),
      ],
    );
  }

  /// タンパク質リング。デザインの最上段のカード。
  ///
  /// 目標値だけが実データである。**摂取量は [_dummyIntakeG]（ダミー）。**
  Widget _buildProteinCard() {
    final target = calcTargetProteinG(_profile?.weightKg);

    switch (target) {
      case ProteinTargetOk(:final targetG):
        return _ProteinRingCard(intakeG: _dummyIntakeG, goalG: targetG);
      case ProteinTargetUnset():
        // FEAT-06 未実施。**業務上は正常**である。エラーにしない。
        return _NoGoalCard(
          message: '体重を登録すると、1日の目標タンパク質量が出ます。',
          onOpenSettings: _openSettings,
        );
      case ProteinTargetInvalid(:final weightKg):
        // データ不整合。数値そのものは利用者に見せない（FEAT-07 §6）。
        debugPrint('ProteinTargetInvalid: weightKg=$weightKg');
        return _NoGoalCard(
          message: '体重の値を確認してください。目標を計算できません。',
          onOpenSettings: _openSettings,
        );
    }
  }

  /// 「記録を振り返る」。行き先は SCR-01（FEAT-05）。
  ///
  /// **SCR-01 は未実装である。** 押すとダッシュボードのタブへ移り、案内が出る。
  Widget _buildLookBackCard() {
    final t = context.tokens;

    return _SurfaceCard(
      radius: Dimens.radiusCta,
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
      onTap: widget.onOpenDashboard,
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              spacing: 3,
              children: [
                Text(
                  '記録を振り返る',
                  style: TextStyle(
                    color: t.textColor,
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  'ジムに行った日のカレンダー・集計・履歴',
                  style: TextStyle(
                    color: t.textColor.withValues(alpha: 0.72),
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
          Text(
            '→',
            style: TextStyle(
              color: t.textColor.withValues(alpha: 0.55),
              fontSize: 16,
            ),
          ),
        ],
      ),
    );
  }

  /// ⚠️ **暫定の入口。デザインには無い。**
  ///
  /// 置き場所は SCR-05（設定）が正しい（ADR-0024 §1 の「設定・器具登録・食品
  /// マスタはタブに置かない。歯車 → SCR-05 → 各画面へ辿る」）。
  /// ただし SCR-05 は本作業の対象外で、`profile_page.dart` を触れない。
  /// 消すと実装済みの2画面が実機から辿れなくなるため、当面ここに置く。
  ///
  /// サインアウトも同じ理由で残す。`home_placeholder.dart` から引き継いだ。
  ///
  /// TODO(ADR-0024): SCR-05 へ移し、このブロックごと消す。
  Widget _buildTemporaryMenu() {
    final t = context.tokens;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: 8,
      children: [
        Text(
          '（暫定）設定画面ができるまでの入口',
          style: TextStyle(
            color: t.textColor.withValues(alpha: 0.5),
            fontSize: 11,
            fontWeight: FontWeight.w600,
          ),
        ),
        _SurfaceCard(
          radius: Dimens.radiusCta,
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
          onTap: () => _open(const MachineListPage()),
          child: _RowLabel(text: '器具・種目の登録', note: 'FEAT-01 / SCR-02'),
        ),
        _SurfaceCard(
          radius: Dimens.radiusCta,
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
          onTap: () => _open(const FoodListPage()),
          child: _RowLabel(text: '食品マスタ', note: 'FEAT-10 / 一覧・編集・CSV取込'),
        ),
        const SizedBox(height: 4),
        OutlinedButton(
          onPressed: _isSigningOut ? null : _signOut,
          child: const Text('サインアウト'),
        ),
      ],
    );
  }
}

/// SCR-00 の CTA。「タンパク質を記録する」。
///
/// **下部ナビの直上に固定する。** 置くのは [AppShell]（デザインでは CTA と
/// ナビが1つの `position:sticky` な箱に入っているため）。
///
/// ダークの背景はグラデーションである（ADR-0024 §2 の `ctaBg`）。
/// `FilledButton` は単色しか取れないので、自分で `Ink` を敷く。
class HomeRecordCta extends StatelessWidget {
  const HomeRecordCta({super.key, required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;

    return Padding(
      // デザインの `padding:12px 20px 6px`。
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 6),
      child: SizedBox(
        height: 54,
        child: Ink(
          decoration: BoxDecoration(
            // ライトは単色、ダークはグラデーション。両方渡してよい。
            // `BoxDecoration` は gradient があれば color を無視する。
            gradient: t.ctaGradient,
            color: t.ctaColor,
            borderRadius: BorderRadius.circular(Dimens.radiusCta),
          ),
          child: InkWell(
            onTap: onPressed,
            borderRadius: BorderRadius.circular(Dimens.radiusCta),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              spacing: 9,
              children: [
                Text(
                  '＋',
                  style: TextStyle(
                    color: t.ctaFg,
                    fontSize: 19,
                    height: 1,
                  ),
                ),
                Text(
                  'タンパク質を記録する',
                  style: TextStyle(
                    color: t.ctaFg,
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// タンパク質リングのカード。
///
/// 左に円グラフ（中央に `{intake}g` と `{pct}%`）、右に `{intake} / {goal}g` と残量。
class _ProteinRingCard extends StatelessWidget {
  const _ProteinRingCard({required this.intakeG, required this.goalG});

  /// 今日の摂取量(g)。**いまはダミー**（呼び出し側を参照）。
  final double intakeG;

  /// 1日の目標(g)。RULE-001（体重×2g）の結果。
  final double goalG;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;

    // 目標を超えても円は満タンで止める（デザインの `Math.min(1, ...)`）。
    final progress = goalG <= 0 ? 0.0 : math.min(1.0, intakeG / goalG);
    final remaining = math.max(0.0, goalG - intakeG);
    final isDone = remaining <= 0;

    return _SurfaceCard(
      radius: Dimens.radiusCard,
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 20),
      child: Row(
        spacing: 20,
        children: [
          SizedBox.square(
            dimension: 104,
            child: Stack(
              alignment: Alignment.center,
              children: [
                Positioned.fill(
                  child: CustomPaint(
                    painter: _RingPainter(
                      progress: progress,
                      track: t.ringTrack,
                      fill: t.fill,
                    ),
                  ),
                ),
                Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.baseline,
                      textBaseline: TextBaseline.alphabetic,
                      children: [
                        Text(
                          _formatG(intakeG),
                          style: const TextStyle(
                            fontSize: 26,
                            fontWeight: FontWeight.w800,
                            height: 1,
                            letterSpacing: -1.04, // 26px × -0.04em
                          ).merge(kTabularFigures).copyWith(color: t.textColor),
                        ),
                        Text(
                          'g',
                          style: TextStyle(
                            color: t.textColor.withValues(alpha: 0.75),
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                    Text(
                      '${(progress * 100).round()}%',
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ).merge(kTabularFigures).copyWith(
                        color: t.textColor.withValues(alpha: 0.72),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              spacing: 7,
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
                  spacing: 2,
                  children: [
                    Text(
                      _formatG(intakeG),
                      style: const TextStyle(
                        fontSize: 32,
                        fontWeight: FontWeight.w800,
                        height: 1,
                        letterSpacing: -1.28, // 32px × -0.04em
                      ).merge(kTabularFigures).copyWith(color: t.textColor),
                    ),
                    Text(
                      '/ ${_formatG(goalG)}g',
                      style: TextStyle(
                        color: t.textColor.withValues(alpha: 0.7),
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
                Text(
                  isDone ? '目標達成' : '残り ${_formatG(remaining)}g',
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ).merge(kTabularFigures).copyWith(color: t.accent),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// リングを描く。デザインの SVG（`r=44`・`stroke-width=12`・104×104）と同寸。
class _RingPainter extends CustomPainter {
  const _RingPainter({
    required this.progress,
    required this.track,
    required this.fill,
  });

  /// 0.0〜1.0。
  final double progress;

  /// 未達部分の色。
  final Color track;

  /// 達成部分の色。
  final Color fill;

  /// デザインの半径と線幅。104×104 の中に描く前提。
  static const double _radius = 44;
  static const double _strokeWidth = 12;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    // 104 以外の大きさで置かれても比率を保つ。
    final scale = size.shortestSide / 104;
    final radius = _radius * scale;
    final rect = Rect.fromCircle(center: center, radius: radius);

    final base = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = _strokeWidth * scale
      ..isAntiAlias = true;

    canvas.drawCircle(center, radius, base..color = track);

    if (progress <= 0) return;
    canvas.drawArc(
      rect,
      // デザインの `rotate(-90 52 52)`。12時から時計回りに伸ばす。
      -math.pi / 2,
      2 * math.pi * progress,
      false,
      base
        ..color = fill
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(_RingPainter oldDelegate) =>
      oldDelegate.progress != progress ||
      oldDelegate.track != track ||
      oldDelegate.fill != fill;
}

/// 目標が出せないときのカード。体重が未設定・不正のときに出す。
///
/// **エラー画面にしない**（FEAT-07 §4.3）。他の機能は通常どおり使える。
class _NoGoalCard extends StatelessWidget {
  const _NoGoalCard({required this.message, required this.onOpenSettings});

  final String message;
  final VoidCallback onOpenSettings;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;

    return _SurfaceCard(
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
          Text(
            message,
            style: TextStyle(color: t.textColor, fontSize: 14),
          ),
          OutlinedButton(
            onPressed: onOpenSettings,
            child: const Text('設定を開く'),
          ),
        ],
      ),
    );
  }
}

/// デザインの「面」。`background:surface` ＋ `border:1px solid hairline`。
///
/// 角丸だけがカード（16）と行（14）で違うので引数に開けてある。
class _SurfaceCard extends StatelessWidget {
  const _SurfaceCard({
    required this.radius,
    required this.padding,
    required this.child,
    this.onTap,
  });

  final double radius;
  final EdgeInsets padding;
  final Widget child;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final borderRadius = BorderRadius.circular(radius);

    return Material(
      // `surface` はダークだと半透明である。地色を透かすため色は Ink 側に置かない。
      color: Colors.transparent,
      child: Ink(
        decoration: BoxDecoration(
          color: t.surface,
          borderRadius: borderRadius,
          border: Border.all(color: t.hairline),
        ),
        child: InkWell(
          onTap: onTap,
          borderRadius: borderRadius,
          child: Padding(padding: padding, child: child),
        ),
      ),
    );
  }
}

/// 暫定メニューの1行。見出しと補足。
class _RowLabel extends StatelessWidget {
  const _RowLabel({required this.text, required this.note});

  final String text;
  final String note;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;

    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            spacing: 3,
            children: [
              Text(
                text,
                style: TextStyle(
                  color: t.textColor,
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                ),
              ),
              Text(
                note,
                style: TextStyle(
                  color: t.textColor.withValues(alpha: 0.72),
                  fontSize: 11,
                ),
              ),
            ],
          ),
        ),
        Text(
          '→',
          style: TextStyle(
            color: t.textColor.withValues(alpha: 0.55),
            fontSize: 16,
          ),
        ),
      ],
    );
  }
}

/// ヘッダの正方形ボタン。デザインの `32×32`・角丸9・罫線1px。
class _SquareIconButton extends StatelessWidget {
  const _SquareIconButton({
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final borderRadius = BorderRadius.circular(9);

    return Tooltip(
      message: tooltip,
      child: Material(
        color: Colors.transparent,
        child: Ink(
          decoration: BoxDecoration(
            borderRadius: borderRadius,
            border: Border.all(color: t.hairline),
          ),
          child: InkWell(
            onTap: onTap,
            borderRadius: borderRadius,
            child: SizedBox.square(
              dimension: 32,
              child: Icon(icon, size: 16, color: t.textColor),
            ),
          ),
        ),
      ),
    );
  }
}

/// 日付ラベル。デザインの `${月}月${日}日（${曜日}）`。
String _formatToday(DateTime date) {
  // `DateTime.weekday` は 月=1 … 日=7。7 を 0 に畳んで「日月火…」の添字にする。
  const names = '日月火水木金土';
  return '${date.month}月${date.day}日（${names[date.weekday % 7]}）';
}

/// 表示用のタンパク質量。**整数 g に丸める。**
///
/// `domain/nutrition.dart` は小数第1位まで持つ。表示の丸めは UI 層の担当で
/// あると同ファイルが明記している（FEAT-07 §4.2）。
String _formatG(double value) => value.round().toString();
