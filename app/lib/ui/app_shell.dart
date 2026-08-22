import 'package:flutter/material.dart';

import '../data/auth_repository.dart';
import 'home_page.dart';
import 'meal_capture_page.dart';
import 'theme/design_tokens.dart';
import 'training_record_page.dart';

/// 全画面の共通の枠（ADR-0024 §1）。
///
/// 持つのは2つだけ。**幅の制約**と**下部ナビ**である。
/// 画面の中身は各タブが持つ。ここに業務のロジックを置かない。
///
/// | 要素 | 値 | 出典 |
/// |---|---|---|
/// | 幅 | `max-width:430px`・中央寄せ・左右に罫線 | ADR-0024 §2 |
/// | ナビ | 4タブ・高さ56・アイコン21・ラベル10/700 | ADR-0024 §1 |
///
/// **設定・器具登録・食品マスタはタブに置かない**（ADR-0024 §1）。
/// 毎日使うものだけを1タップの位置に置く。
class AppShell extends StatefulWidget {
  const AppShell({super.key, required this.authRepository});

  final AuthRepository authRepository;

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  /// 表示中のタブ。0＝ホーム。
  int _index = 0;

  /// 一度でも開いたタブ。**開くまで中身を作らない。**
  ///
  /// `IndexedStack` は子を全部作る。素直に並べると、起動しただけで
  /// 筋トレタブが種目一覧を読みに行く。開いてから作り、以後は状態を保つ。
  final Set<int> _visited = {0};

  void _select(int index) {
    if (_index == index) return;
    setState(() {
      _index = index;
      _visited.add(index);
    });
  }

  /// タブの中身を作る。
  ///
  /// SCR-04（P記録）と SCR-01（ダッシュボード）は未実装である。
  /// **押しても落ちない**よう、案内だけを出す。
  Widget _buildTab(int index) {
    switch (index) {
      case 0:
        return HomePage(
          authRepository: widget.authRepository,
          // 「記録を振り返る」は SCR-01。タブを切り替えるだけにする。
          // push で重ねると、下部ナビの選択位置と画面がずれる。
          onOpenDashboard: () => _select(3),
        );
      case 1:
        return const MealCapturePage();
      case 2:
        return const TrainingRecordPage();
      default:
        return const _ComingSoon(
          title: 'ダッシュボード',
          note: 'SCR-01 Dashboard（FEAT-05）。W-17 で作る。',
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;

    return Scaffold(
      backgroundColor: t.pageBg,
      body: Center(
        child: ConstrainedBox(
          // 430px を超えたら中央に寄せ、左右に罫線を引く（ADR-0024 §2）。
          constraints: const BoxConstraints(
            maxWidth: Dimens.maxContentWidth,
          ),
          child: DecoratedBox(
            decoration: BoxDecoration(
              border: Border.symmetric(
                vertical: BorderSide(color: t.hairline),
              ),
            ),
            child: Column(
              children: [
                Expanded(
                  child: IndexedStack(
                    index: _index,
                    children: [
                      for (var i = 0; i < 4; i++)
                        _visited.contains(i)
                            ? _buildTab(i)
                            : const SizedBox.shrink(),
                    ],
                  ),
                ),
                _buildBottomBar(t),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// 下部の固定領域。CTA と下部ナビをひとまとめにする。
  ///
  /// デザインでは1つの `position:sticky` な箱で、上端にだけ罫線が入る
  /// （`SCR-00 トップ.dc.html`）。罫線を2本にしないため、CTA もここへ入れる。
  Widget _buildBottomBar(DesignTokens t) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: t.navBg,
        border: Border(top: BorderSide(color: t.hairline)),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // CTA はホームにしか無い（SCR-00）。他のタブでは出さない。
            if (_index == 0)
              HomeRecordCta(
                // 記録先は SCR-04（P記録タブ）。
                onPressed: () => _select(1),
              ),
            _buildNav(t),
          ],
        ),
      ),
    );
  }

  Widget _buildNav(DesignTokens t) {
    return SizedBox(
      height: Dimens.navHeight,
      child: Row(
        children: [
          _NavItem(
            icon: NavIcon.home,
            label: 'ホーム',
            selected: _index == 0,
            onTap: () => _select(0),
          ),
          _NavItem(
            icon: NavIcon.meal,
            label: 'P記録',
            selected: _index == 1,
            onTap: () => _select(1),
          ),
          _NavItem(
            icon: NavIcon.training,
            label: '筋トレ',
            selected: _index == 2,
            onTap: () => _select(2),
          ),
          _NavItem(
            icon: NavIcon.dashboard,
            label: 'ダッシュボード',
            selected: _index == 3,
            onTap: () => _select(3),
          ),
        ],
      ),
    );
  }
}

/// 下部ナビの1タブ。
///
/// 4つを等幅に割る（デザインは `grid-template-columns:repeat(4,1fr)`）。
class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final NavIcon icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    // 選択中はアクセント色で不透明。非選択は本文色を .7 まで薄める（ADR-0024 §1）。
    final color = selected ? t.accent : t.textColor;
    final opacity = selected ? 1.0 : Dimens.navInactiveOpacity;

    return Expanded(
      child: InkWell(
        onTap: onTap,
        child: Opacity(
          opacity: opacity,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            // デザインのアイコンとラベルの間隔は 5px。
            spacing: 5,
            children: [
              CustomPaint(
                size: const Size.square(Dimens.navIconSize),
                painter: NavIconPainter(icon: icon, color: color),
              ),
              Text(
                label,
                style: TextStyle(
                  color: color,
                  fontSize: Dimens.navLabelSize,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 下部ナビのアイコンの種類。
enum NavIcon { home, meal, training, dashboard }

/// 下部ナビのアイコンを描く。
///
/// **`Icons` では代用しない。** `SCR-00 トップ.dc.html` の SVG パスをそのまま
/// 写している。Material のアイコンは線幅も形も別物で、並べると浮く。
///
/// パスは 24×24 の座標系で書かれている。`size` に合わせて縮小して描く
/// （実寸は 21px＝[Dimens.navIconSize]）。
class NavIconPainter extends CustomPainter {
  const NavIconPainter({required this.icon, required this.color});

  final NavIcon icon;
  final Color color;

  /// デザインの `viewBox="0 0 24 24"`。
  static const double _viewBox = 24;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..color = color
      // ホームだけ線が太い（デザインの `stroke-width`）。
      ..strokeWidth = icon == NavIcon.home ? 2.4 : 1.9
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..isAntiAlias = true;

    canvas.save();
    canvas.scale(size.width / _viewBox, size.height / _viewBox);
    canvas.drawPath(_path(), paint);
    canvas.restore();
  }

  Path _path() {
    final path = Path();
    switch (icon) {
      // 家。`M3.5 10.5 12 3.5l8.5 7` `M6 9.8V20h12V9.8` `M10 20v-5.5h4V20`
      case NavIcon.home:
        path
          ..moveTo(3.5, 10.5)
          ..lineTo(12, 3.5)
          ..lineTo(20.5, 10.5)
          ..moveTo(6, 9.8)
          ..lineTo(6, 20)
          ..lineTo(18, 20)
          ..lineTo(18, 9.8)
          ..moveTo(10, 20)
          ..lineTo(10, 14.5)
          ..lineTo(14, 14.5)
          ..lineTo(14, 20);
      // カメラ。`M3.5 8.8h3.2l1.6-2.3h7.4l1.6 2.3h3.2V19.5H3.5z` ＋ 中央の円。
      case NavIcon.meal:
        path
          ..moveTo(3.5, 8.8)
          ..lineTo(6.7, 8.8)
          ..lineTo(8.3, 6.5)
          ..lineTo(15.7, 6.5)
          ..lineTo(17.3, 8.8)
          ..lineTo(20.5, 8.8)
          ..lineTo(20.5, 19.5)
          ..lineTo(3.5, 19.5)
          ..close()
          ..addOval(
            Rect.fromCircle(center: const Offset(12, 14), radius: 3.1),
          );
      // ダンベル。5本の直線。
      case NavIcon.training:
        path
          ..moveTo(3, 9.5)
          ..lineTo(3, 14.5)
          ..moveTo(6.2, 7)
          ..lineTo(6.2, 17)
          ..moveTo(17.8, 7)
          ..lineTo(17.8, 17)
          ..moveTo(21, 9.5)
          ..lineTo(21, 14.5)
          ..moveTo(6.2, 12)
          ..lineTo(17.8, 12);
      // 棒グラフ。4本の縦線。
      case NavIcon.dashboard:
        path
          ..moveTo(4, 20)
          ..lineTo(4, 12.5)
          ..moveTo(9.3, 20)
          ..lineTo(9.3, 6.5)
          ..moveTo(14.7, 20)
          ..lineTo(14.7, 15.5)
          ..moveTo(20, 20)
          ..lineTo(20, 9);
    }
    return path;
  }

  @override
  bool shouldRepaint(NavIconPainter oldDelegate) =>
      oldDelegate.icon != icon || oldDelegate.color != color;
}

/// 未実装のタブに出す案内。
///
/// **押しても落ちないこと**が目的である。空白を出さない。
class _ComingSoon extends StatelessWidget {
  const _ComingSoon({required this.title, required this.note});

  final String title;

  /// どの画面が、どの作業で入るか。実装の進み具合を実機で分かるようにする。
  final String note;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;

    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          spacing: 8,
          children: [
            Text(
              title,
              style: TextStyle(
                color: t.textColor,
                fontSize: 15,
                fontWeight: FontWeight.w700,
              ),
            ),
            Text(
              '準備中',
              style: TextStyle(
                color: t.accent,
                fontSize: 13,
                fontWeight: FontWeight.w700,
              ),
            ),
            Text(
              note,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: t.textColor.withValues(alpha: 0.6),
                fontSize: 11,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
