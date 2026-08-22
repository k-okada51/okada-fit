import 'package:flutter/material.dart';

import '../theme/design_tokens.dart';

/// デザインの「面」。`background:surface` ＋ `border:1px solid hairline`。
///
/// SCR-00・SCR-05 のカードと行がこれである。**色を直接書かない**ための入れ物で、
/// 角丸だけがカード（[Dimens.radiusCard]）と行（[Dimens.radiusCta]）で違うため
/// 引数に開けてある。
///
/// [onTap] を渡さなければ押せない面になる。`InkWell` は残るが波紋は出ない。
class SurfaceCard extends StatelessWidget {
  const SurfaceCard({
    super.key,
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

/// 押せる1行。左に見出しと補足、右に矢印。
///
/// `SCR-05 設定.dc.html` の「器具の登録・管理」がこれである
/// （`padding:16px`・`radius:16`・右端に `›`）。
class SettingsRow extends StatelessWidget {
  const SettingsRow({
    super.key,
    required this.title,
    required this.note,
    required this.onTap,
  });

  final String title;

  /// 見出しの下の1行。何ができる画面かを書く。
  final String note;

  /// `null` なら押せない。処理中の行を沈めるのに使う。
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    // 押せない行は文字ごと沈める。矢印だけ薄いと故障に見える。
    final dim = onTap == null ? 0.4 : 1.0;

    return SurfaceCard(
      radius: Dimens.radiusCard,
      padding: const EdgeInsets.all(16),
      onTap: onTap,
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              spacing: 3,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    color: t.textColor.withValues(alpha: dim),
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  note,
                  style: TextStyle(
                    color: t.textColor.withValues(alpha: 0.72 * dim),
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
          Text(
            '›',
            style: TextStyle(
              color: t.textColor.withValues(alpha: 0.58 * dim),
              fontSize: 16,
            ),
          ),
        ],
      ),
    );
  }
}
