import 'package:flutter/material.dart';

/// 配色トークン（ADR-0024 §2）。
///
/// **値は Claude Design の実測値をそのまま持つ。** 1文字も変えない。
/// 色をここ以外に書かない。画面に直接 `Color(0xFF...)` を置くと、
/// ダーク・ライトのどちらか一方だけ直る事故が起きる。
///
/// ダークが既定である（ADR-0024 §3）。
///
/// 取り出し方は [DesignTokensX.tokens] を使う。
/// ```dart
/// final t = context.tokens;
/// ```
@immutable
class DesignTokens {
  const DesignTokens({
    required this.accent,
    required this.fill,
    required this.pageBg,
    required this.textColor,
    required this.surface,
    required this.hoverSurface,
    required this.hairline,
    required this.navBg,
    required this.inputBg,
    required this.ctaGradient,
    required this.ctaColor,
    required this.ctaFg,
    required this.ctaSoft,
    required this.warn,
    required this.ringTrack,
    required this.accentBorder,
    required this.switchTrackOff,
  });

  /// アクセント色。選択中のタブ・強調文字に使う。
  final Color accent;

  /// 塗り。リングの進捗など「面」に使う。ADR-0024 では accent と同値。
  ///
  /// **同値でも別の名前で持つ。** デザインが `accent` と `fill` を
  /// 別プロパティにしているためで、片方だけ変わる余地を残す。
  final Color fill;

  /// 画面の地色。
  final Color pageBg;

  /// 本文の色。
  final Color textColor;

  /// カードの背景。**ダークは半透明**である。地色に重ねて使う。
  final Color surface;

  /// 押せる面に触れたときの背景。
  final Color hoverSurface;

  /// 罫線。1px の細い線にだけ使う。
  final Color hairline;

  /// 下部ナビの背景。**地色よりわずかに濃い半透明**である。
  final Color navBg;

  /// 入力欄の背景。
  final Color inputBg;

  /// CTA の背景（グラデーション）。**ダークだけ**。ライトは `null`。
  ///
  /// `linear-gradient(180deg,#1ae8ad,#0fb686)` を上から下への [LinearGradient]
  /// に直したもの。CSS の `180deg` は「上端から下端へ」を指す。
  final Gradient? ctaGradient;

  /// CTA の背景（単色）。**ライトだけ**。ダークは `null`。
  ///
  /// [ctaGradient] と併せて `BoxDecoration` に渡す。両方渡してよい。
  /// `BoxDecoration` は `gradient` があるとき `color` を無視する。
  final Color? ctaColor;

  /// CTA の文字色。
  final Color ctaFg;

  /// CTA を薄く敷いた面。枠線だけのボタンの背景に使う。
  final Color ctaSoft;

  /// 注意。未達・未入力を示す。エラーではない。
  final Color warn;

  /// リングの軌道（未達部分）。
  ///
  /// ⚠️ ADR-0024 §2 の表に無い。**`SCR-00 トップ.dc.html` の `ringTrack`** から採った。
  /// リングを描くのに要るが、他の用途には広げない。
  final Color ringTrack;

  /// アクセント色の罫線。[ctaSoft] を敷いた面の縁に使う。
  ///
  /// ⚠️ ADR-0024 §2 の表に無い。**`SCR-05 設定.dc.html` の `accentBorder`** から
  /// 採った。SCR-05 のタンパク質目標カードの縁がこれである。
  final Color accentBorder;

  /// トグルスイッチの軌道（OFF のとき）。ON のときは [fill] を使う。
  ///
  /// ⚠️ ADR-0024 §2 の表に無い。**`SCR-05 設定.dc.html` の `switchBg`** から
  /// 採った。デザインは `dark ? fill : rgba(15,23,42,0.22)` の1行しか持たない。
  ///
  /// ダーク側の値はデザインに**無い**。ダークモードのトグルは OFF になった時点で
  /// ライトのトークンに切り替わるため、ダークの OFF 面が画面に出ることがない。
  /// 別のトグルが増えたときのために置いてあるだけの値である。
  final Color switchTrackOff;

  /// ダーク。**こちらが既定**（ADR-0024 §3）。
  static const DesignTokens dark = DesignTokens(
    accent: Color(0xFF12D9A0),
    fill: Color(0xFF12D9A0),
    pageBg: Color(0xFF0D1117),
    textColor: Color(0xFFE9EDF0),
    surface: Color.fromRGBO(255, 255, 255, 0.045),
    hoverSurface: Color.fromRGBO(255, 255, 255, 0.08),
    hairline: Color.fromRGBO(255, 255, 255, 0.10),
    navBg: Color.fromRGBO(13, 17, 23, 0.94),
    inputBg: Color.fromRGBO(255, 255, 255, 0.05),
    ctaGradient: LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [Color(0xFF1AE8AD), Color(0xFF0FB686)],
    ),
    ctaColor: null,
    ctaFg: Color(0xFF06231A),
    ctaSoft: Color.fromRGBO(18, 217, 160, 0.09),
    warn: Color(0xFFF5A623),
    ringTrack: Color.fromRGBO(255, 255, 255, 0.08),
    accentBorder: Color.fromRGBO(18, 217, 160, 0.35),
    switchTrackOff: Color.fromRGBO(255, 255, 255, 0.14),
  );

  /// ライト。
  static const DesignTokens light = DesignTokens(
    accent: Color(0xFF047857),
    fill: Color(0xFF047857),
    pageBg: Color(0xFFF1F5F9),
    textColor: Color(0xFF0F172A),
    surface: Color(0xFFFFFFFF),
    hoverSurface: Color(0xFFE9EEF4),
    hairline: Color(0xFFE2E8F0),
    navBg: Color.fromRGBO(248, 250, 252, 0.95),
    inputBg: Color(0xFFFFFFFF),
    ctaGradient: null,
    ctaColor: Color(0xFF047857),
    ctaFg: Color(0xFFFFFFFF),
    ctaSoft: Color.fromRGBO(4, 120, 87, 0.08),
    warn: Color(0xFFB45309),
    ringTrack: Color.fromRGBO(15, 23, 42, 0.09),
    accentBorder: Color.fromRGBO(4, 120, 87, 0.35),
    switchTrackOff: Color.fromRGBO(15, 23, 42, 0.22),
  );

  /// 明暗から対応する組を返す。
  static DesignTokens of(Brightness brightness) =>
      brightness == Brightness.dark ? dark : light;
}

/// 画面から `context.tokens` で取り出すための拡張。
///
/// `Theme.of(context).brightness` を見て組を決める。テーマの切替に追従する。
extension DesignTokensX on BuildContext {
  DesignTokens get tokens => DesignTokens.of(Theme.of(this).brightness);
}

/// 寸法トークン（ADR-0024 §1・`SCR-00 トップ.dc.html`）。
///
/// **画面に生の数値を置かない。** 余白のように1画面でしか使わない値は例外とし、
/// ここには「全画面で揃っていないと崩れるもの」だけを置く。
abstract final class Dimens {
  /// 画面の最大幅。これを超えたら中央寄せし、左右に罫線を引く（ADR-0024 §2）。
  static const double maxContentWidth = 430;

  /// ヘッダの高さ。
  static const double headerHeight = 56;

  /// 下部ナビの高さ（ADR-0024 §1）。
  static const double navHeight = 56;

  /// 下部ナビのアイコンの一辺（ADR-0024 §1）。
  static const double navIconSize = 21;

  /// 下部ナビのラベルの文字サイズ（ADR-0024 §1）。
  static const double navLabelSize = 10;

  /// 非選択のタブの不透明度（ADR-0024 §1）。
  static const double navInactiveOpacity = .7;

  /// カードの角丸。
  static const double radiusCard = 16;

  /// CTA の角丸。
  static const double radiusCta = 14;

  /// 入力欄・トーストの角丸。
  static const double radiusInput = 11;

  /// チップの角丸。実質の全円。
  static const double radiusChip = 999;
}
