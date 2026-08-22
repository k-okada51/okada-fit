// FEAT-07 必要タンパク質量算出。RULE-001（必要量 ＝ 体重 × 2g）の実体。
//
// **I/O を持たない。** Supabase も Flutter も import しない（§10 #8）。
// import が増えると単体テストが実行環境に依存し、TDD の起点という
// 位置づけが崩れる。
//
// 式はこの1ファイルにだけ置く。**SQL 側には書かない**（§4.5 案(b)・2026-08-08 確定）。
// RPC は `weight_kg` を素のまま返す。得られるものは2つ。
//
// | メリット | 内容 |
// |---|---|
// | 式が1か所 | 丸めの違いで画面ごとに数字がずれない |
// | プレビュー | SCR-05 で体重を変えると通信せずに目標値が出る |

/// RULE-001 の係数（g / kg / 日）。DEC-B06 により 2.0 固定。
///
/// **式中にリテラル `2` を書かない。** 係数が変わったときの探索範囲を
/// この1行に閉じ込めるため（§4.1・§10 #1）。
///
/// 環境変数化・DB列化は**しない**。要件上は固定値である。設定値にすると
/// 「いつの設定で計算された目標値か」という別問題を誘発する（§4.1）。
///
/// ⚠️ 名前は `[仮]`。設計（§3.0）の表記は `PROTEIN_G_PER_KG` だが、lint
/// `constant_identifier_names` に反する。設計自身が「名前の表記はどちらでも
/// よい」としているため lowerCamelCase を採った。本質はリテラルを散らさない規律。
const double proteinGPerKg = 2.0;

/// タンパク質量(g)の内部丸め。小数第1位・四捨五入（§4.2）。
///
/// Dart の `double.round()` は half away from zero（絶対値の大きいほうへ丸める）。
/// 切り上げ・切り捨ては目標を過大／過小に見せるため使わない。
///
/// 係数が 2.0 の間、この丸めが結果を変えることはない。2 の冪の乗算は
/// IEEE 754 で丸め誤差を生じないため（§4.2）。**それでも省略しない。**
/// 前提は係数が 2.0 以外になった瞬間に失われる。
///
/// FEAT-09 の残量丸めからも呼ぶ（§8）。丸め規則を機能間で一致させるため。
///
/// **表示丸め（整数 g）はここでやらない。** UI 層の担当である（§4.2）。
///
/// ⚠️ `[仮]`: 非有限値（NaN・±Infinity）を渡してはならない。`double.round()`
/// が `UnsupportedError` を投げる。事前判定は呼び出し側の責務とする
/// （設計に記述が無い）。[calcTargetProteinG] は渡す前に必ず判定している。
double roundProteinG(double value) => (value * 10).round() / 10;

/// 1日を何食に割るか。
///
/// ⚠️ **設計書に無い。デザインにしかない概念である。** `SCR-05 設定.dc.html` の
/// 「1食あたりの目安（4食）」＝ `Math.round(goal / 4)` から採った。
/// ADR-0024 §5 A が「デザインが正しく、実装が漏れている」とした箇所にあたる。
///
/// **食事スロットを持つという意味ではない。** `meal_logs` に時間帯の列は無く、
/// 記録側は何も分類しない（ADR-0024 の ⚠️ はそちらの話である）。
/// ここは目標値を4で割って見せるだけで、DB にも RPC にも影響しない。
const int kMealsPerDay = 4;

/// 1食あたりの目安(g)。目標を [kMealsPerDay] で割る。
///
/// 丸めは [roundProteinG] に合わせる（小数第1位）。**表示丸め（整数 g）は
/// UI 層の担当**である（§4.2）。ここでは整数にしない。
///
/// 入力には [ProteinTargetOk.targetG] を渡す。丸め済みの値を割るため、
/// 「目標 ◯g・1食 ◯g」の2つが同じ元値から出ていることが保証される。
double proteinPerMealG(double targetG) =>
    roundProteinG(targetG / kMealsPerDay);

/// [calcTargetProteinG] の結果（§3.0）。
///
/// `double?` 単独にしない。`null` では「未設定（FEAT-06 未実施＝正常）」と
/// 「不正値（データ不整合）」を区別できず、ERR-PROFILE-020 と ERR-PROFILE-021 を
/// 出し分けられないため。
///
/// `sealed` にすると `switch` の網羅性をコンパイラが検査する。
/// 分岐の書き漏れがコンパイルエラーになる。
sealed class ProteinTarget {
  const ProteinTarget();
}

/// 算出できた（B6・B7）。
///
/// `weightKg` と `coefficient` を同梱する理由は、SCR-05 の根拠表示
/// （「◯kg × 2g」）を再計算せずに描けるようにするため（§3.0）。
final class ProteinTargetOk extends ProteinTarget {
  const ProteinTargetOk({
    required this.targetG,
    required this.weightKg,
    required this.coefficient,
  });

  /// 1日の必要タンパク質量(g)。小数第1位まで（[roundProteinG] 適用済み）。
  ///
  /// FEAT-05 の `rate_pct`・FEAT-09 の `remaining_g` は、丸め**後**のこの値を
  /// 入力に使う。丸め前後が混在すると画面ごとに表示値がずれる（§4.2）。
  final double targetG;

  /// 算出に使った体重(kg)。入力をそのまま持つ。
  final double weightKg;

  /// 算出に使った係数。現状は常に [proteinGPerKg]。
  ///
  /// 将来 DEC-B06 が変わっても戻り値の形を変えずに済ませるために持つ（§10 #1）。
  final double coefficient;

  @override
  String toString() =>
      'ProteinTargetOk(targetG: $targetG, weightKg: $weightKg, '
      'coefficient: $coefficient)';
}

/// 体重が未設定（B1・B2）。FEAT-06 未実施。**業務上は正常な状態**である。
///
/// 呼び出し側は ERR-PROFILE-020 へ写像し、SCR-05 へ誘導する。
/// エラー画面にはしない。ヒートマップ・記録機能は通常どおり動かす
/// （NFR-AVAIL-05 の縮退方針）。
final class ProteinTargetUnset extends ProteinTarget {
  const ProteinTargetUnset();

  @override
  String toString() => 'ProteinTargetUnset()';
}

/// 体重が不正値（B3〜B5）。0以下・非有限。**データ不整合**である。
///
/// 呼び出し側は ERR-PROFILE-021 へ写像し、`weightKg` を error でログに残す。
/// 利用者向け文言に数値そのものは出さない（§6）。
final class ProteinTargetInvalid extends ProteinTarget {
  const ProteinTargetInvalid(this.weightKg);

  /// 弾いた体重の値。ログ用。
  final double weightKg;

  @override
  String toString() => 'ProteinTargetInvalid($weightKg)';
}

/// RULE-001: 1日の必要タンパク質量を算出する（§4.1）。
///
/// ```text
/// target_g [g/日] = round1( weight_kg [kg] × proteinGPerKg [g/kg/日] )
/// ```
///
/// 入力は **kg**、出力は **g**。kg→g の意味変換が起きる唯一の地点（§3.0）。
/// 単位を取り違えても型検査は通らず、本関数でも検出できない（§10 #3）。
///
/// DB にもネットワークにも依存しない純関数。同一入力に対し常に同一出力を返し、
/// 呼び出し順・時刻に依存しない。
///
/// **例外を投げない**（§4.3）。体重未設定は初回利用で必ず通る正常な業務状態であり、
/// 例外にすると FEAT-05・FEAT-09 が初回ログイン直後に一律で失敗する。
/// 呼び出し側は `try/catch` を書かなくてよい。
///
/// 上限チェックは行わない。入力上限は FEAT-06 の責務である（§3.1）。
ProteinTarget calcTargetProteinG(double? weightKg) {
  // B1・B2: 未設定。列を選択しなかった場合・キーが欠落した場合も、
  // リポジトリ層が `(map['weight_kg'] as num?)?.toDouble()` で null に
  // 正規化するためここへ来る。Dart に `undefined` は無い。
  if (weightKg == null) return const ProteinTargetUnset();

  // B5 を先に見る。`NaN <= 0` は false のため、比較だけでは弾けない。
  // 列は numeric(6,1)（ADR-0022）で Infinity を格納できないが、
  // Dart 側（SCR-05 の入力の数値化など）で非有限値が作られ得る。
  //
  // B3・B4: 0 と負値。`users.weight_kg` の CHECK(>0) と同値。
  if (!weightKg.isFinite || weightKg <= 0) {
    return ProteinTargetInvalid(weightKg);
  }

  final raw = weightKg * proteinGPerKg;

  // ⚠️ `[仮]`: 桁あふれ。設計に記述が無い。
  // `double.maxFinite` 近傍の入力では積が Infinity になり、[roundProteinG] が
  // `UnsupportedError` を投げてしまう。§4.3 の「例外を投げない」を守るため、
  // 不正値として返す。
  // `users.weight_kg` は numeric(6,1) なので DB 経由では起きない。
  // SCR-05 の入力欄に巨大な値が打たれた場合にだけ通る経路である。
  if (!raw.isFinite) return ProteinTargetInvalid(weightKg);

  return ProteinTargetOk(
    targetG: roundProteinG(raw),
    weightKg: weightKg,
    coefficient: proteinGPerKg,
  );
}
