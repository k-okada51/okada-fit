import 'package:flutter/material.dart';

import 'design_tokens.dart';

/// アプリのテーマ（ADR-0024 §2）。
///
/// **`ColorScheme.fromSeed` を使わない。** 種色から生成すると、
/// デザインの実測値（`#12d9a0` など）が別の色に置き換わってしまう。
/// トークンを1つずつ流し込む（ADR-0024 §2 の「`seedColor: Colors.teal` は捨てる」）。
///
/// ADR-0024 が決めていない役割（`error` など）は Material の既定に任せる。
/// **足りない色を自分で発明しない。** デザインに現れたら改めてトークンへ足す。

/// ダークのテーマ。**既定はこちら**（ADR-0024 §3）。
ThemeData buildDarkTheme() => _buildTheme(Brightness.dark);

/// ライトのテーマ。
ThemeData buildLightTheme() => _buildTheme(Brightness.light);

ThemeData _buildTheme(Brightness brightness) {
  final t = DesignTokens.of(brightness);
  final isDark = brightness == Brightness.dark;

  // 既定の組から出発し、ADR-0024 が決めた役割だけ上書きする。
  final base = isDark ? const ColorScheme.dark() : const ColorScheme.light();
  final scheme = base.copyWith(
    primary: t.accent,
    onPrimary: t.ctaFg,
    secondary: t.accent,
    onSecondary: t.ctaFg,
    surface: t.pageBg,
    onSurface: t.textColor,
    // カードの面。ダークは半透明で、地色に重ねて出す前提である。
    surfaceContainer: t.surface,
    surfaceContainerHighest: t.hoverSurface,
    outline: t.hairline,
    outlineVariant: t.hairline,
  );

  final textTheme = (isDark ? Typography.material2021().white : Typography.material2021().black)
      .apply(bodyColor: t.textColor, displayColor: t.textColor);

  return ThemeData(
    useMaterial3: true,
    brightness: brightness,
    colorScheme: scheme,
    scaffoldBackgroundColor: t.pageBg,
    textTheme: textTheme,
    // ヘッダはデザイン側で自前に描く。`AppBar` を使う既存画面のために地色だけ合わせる。
    appBarTheme: AppBarTheme(
      backgroundColor: t.pageBg,
      foregroundColor: t.textColor,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
    ),
    dividerTheme: DividerThemeData(color: t.hairline, thickness: 1, space: 1),
    // デザインの Toast に寄せる。角丸11px・浮かせる。
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(Dimens.radiusInput),
      ),
      // 半透明の `surface` だと地色が透けて読めない。ナビと同じ濃さを使う。
      backgroundColor: t.navBg,
      contentTextStyle: TextStyle(color: t.textColor, fontSize: 14),
      actionTextColor: t.accent,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: t.inputBg,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(Dimens.radiusInput),
        borderSide: BorderSide(color: t.hairline),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(Dimens.radiusInput),
        borderSide: BorderSide(color: t.hairline),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(Dimens.radiusInput),
        borderSide: BorderSide(color: t.accent),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        // ダークの CTA はグラデーションだが、`ButtonStyle` は単色しか取れない。
        // グラデーションが要る場所は `DesignTokens.ctaGradient` を自分で描く。
        backgroundColor: t.accent,
        foregroundColor: t.ctaFg,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Dimens.radiusCta),
        ),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: t.accent,
        side: BorderSide(color: t.hairline),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Dimens.radiusInput),
        ),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(foregroundColor: t.accent),
    ),
    cardTheme: CardThemeData(
      color: t.surface,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(Dimens.radiusCard),
        side: BorderSide(color: t.hairline),
      ),
    ),
    listTileTheme: ListTileThemeData(iconColor: t.textColor),
    progressIndicatorTheme: ProgressIndicatorThemeData(color: t.accent),
  );
}

/// 数字を等幅で出すための書体設定。
///
/// デザインの `font-variant-numeric: tabular-nums` に当たる。
/// **数値が毎秒書き換わる場所に必ず付ける。** 付けないと桁ごとに幅が変わり、
/// 数字が左右に踊る。
///
/// 使い方は `copyWith` ではなく `merge` にする。呼び出し側の書体を消さない。
/// ```dart
/// style: const TextStyle(fontSize: 32).merge(kTabularFigures)
/// ```
const TextStyle kTabularFigures = TextStyle(
  fontFeatures: [FontFeature.tabularFigures()],
);
