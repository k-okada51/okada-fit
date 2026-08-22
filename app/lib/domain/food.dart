/// 食品マスタ（`foods`）が扱う値と、その検証。
///
/// UI にも Supabase にも依存しない。`BuildContext` も `SupabaseClient` も
/// 受け取らない。ここに置いたものは全て単体テストの対象（NFR-QUAL-01）。
///
/// 正本は `FEAT-10_食事マスタCSVインポート.md`。列と制約は `01_DB物理設計.md §1.5`。
///
/// **検証規則の正本はこのファイル1本にする。** CSV 取込（§3.4）も一覧の編集（§7）も
/// ここの [checkFoodName] ／ [checkProteinAmount] を通す。規則が2本に割れると、
/// 取込では通る値が編集では弾かれる（またはその逆）ことが起きる。
library;

/// `name` の上限文字数（FEAT-10 §3.3 `[仮]`）。**正規化後**の長さで数える。
const kMaxFoodNameLength = 100;

/// `protein_amount` の下限(g)。DB の `CHECK (protein_amount >= 0)` と同じ規則。
const kMinProteinAmount = 0.0;

/// `protein_amount` の上限(g)（FEAT-10 §3.4 `[仮]`）。
///
/// DB に上限の CHECK は無い。桁の誤入力を捕まえるためのアプリ側の規則である。
/// `numeric(6,1)` の最大 `99999.9` には十分収まる。
const kMaxProteinAmount = 1000.0;

/// `foods` の1行。
///
/// 列名は snake_case のまま扱う（`06_DB設計規約.md` の物理命名規約）。
/// Dart 側でキャメルケースへ直すのは、このクラスの中だけにする。
class Food {
  const Food({
    required this.id,
    required this.name,
    required this.proteinAmount,
  });

  /// `foods.id`（bigint・`GENERATED ALWAYS AS IDENTITY`）。
  final int id;

  /// 食品名。**保存されているのは正規化後の文字列**（§4-5・DB物理設計 §1.5）。
  final String name;

  /// タンパク質量(g)。**1食分あたり**であって 100g あたりではない（ADR-0012）。
  final double proteinAmount;

  /// PostgREST が返す1行から作る。
  factory Food.fromJson(Map<String, dynamic> json) => Food(
    id: _asInt(json['id']) ?? 0,
    name: (json['name'] as String? ?? ''),
    proteinAmount: _asDouble(json['protein_amount']) ?? 0.0,
  );
}

/// `numeric` を `double` へ直す（ADR-0022）。
///
/// PostgreSQL の `numeric` はドライバによって文字列で返ることがある。
/// どちらで来ても同じ結果になるようにしておく。
double? _asDouble(Object? value) {
  if (value == null) return null;
  if (value is num) return value.toDouble();
  if (value is String) return double.tryParse(value);
  return null;
}

/// `int` を取り出す。`bigint` も `numeric` と同じ理由で文字列で来うる。
int? _asInt(Object? value) {
  if (value == null) return null;
  if (value is int) return value;
  if (value is num) return value.toInt();
  if (value is String) return int.tryParse(value);
  return null;
}

/// 行が妥当でない理由（FEAT-10 §3.4 の `reason_code`）。
///
/// **コードと文言をここで1対にする。** CSV の取込はエラー一覧に [code] を出し、
/// 編集ダイアログは入力欄に [message] を出す。判定そのものは同じ関数を通る。
enum FoodReason {
  /// 列数が2でない。CSV 取込だけで起きる。
  columnCountMismatch('COLUMN_COUNT_MISMATCH', '列は name と protein_amount の2つにしてください。'),

  /// `name` が空（正規化後で判定）。
  emptyName('EMPTY_NAME', '食品名を入力してください。'),

  /// `name` が長すぎる（正規化後で判定）。
  nameTooLong(
    'NAME_TOO_LONG',
    '食品名は$kMaxFoodNameLength文字以内で入力してください。',
  ),

  /// 同一ファイル内で `name` が重複。CSV 取込だけで起きる。
  ///
  /// **既存マスタとの重複はこれではない。** そちらはエラーにせず DB がスキップする（§3.2）。
  duplicateName('DUPLICATE_NAME', 'ファイルの中で食品名が重複しています。'),

  /// `protein_amount` が空。
  proteinEmpty('PROTEIN_EMPTY', 'タンパク質量を入力してください。'),

  /// `protein_amount` が半角10進数でない。全角数字・桁区切り・単位付きを含む。
  proteinNotNumber('PROTEIN_NOT_NUMBER', 'タンパク質量は半角数字で入力してください。'),

  /// `protein_amount` が負数。DB の `CHECK (protein_amount >= 0)` と同じ規則。
  proteinNegative('PROTEIN_NEGATIVE', 'タンパク質量は0以上で入力してください。'),

  /// `protein_amount` が上限超え（[kMaxProteinAmount]）。
  proteinTooLarge('PROTEIN_TOO_LARGE', 'タンパク質量は1000以下で入力してください。');

  const FoodReason(this.code, this.message);

  /// 設計 §3.4 の `reason_code`。エラー一覧の突き合わせに使う。
  final String code;

  /// 利用者向け日本語。技術詳細を含めない（`07_実装共通設計パターン.md §1`）。
  final String message;
}

/// 全角英数字と半角の差（`Ａ`＝U+FF21 と `A`＝U+0041 の距離）。
const _fullWidthOffset = 0xFEE0;

/// 連続する空白の判別。`\s` は全角スペース（U+3000）も含む。
final _whitespaceRun = RegExp(r'\s+');

/// 半角10進数の判別（FEAT-10 §3.4）。
///
/// Dart の `\d` は既定で `[0-9]` だけを指す。全角数字は通らない。
final _decimalNumber = RegExp(r'^-?\d+(\.\d+)?$');

/// `name` を正規化する（§4-5）。**正規化後の文字列をそのまま保存する**（案i）。
///
/// | # | 処理 | 例 |
/// |---|---|---|
/// | 1 | 前後の空白を除去（半角・全角） | `　鶏むね肉 ` → `鶏むね肉` |
/// | 2 | 全角英数字を半角へ | `ＭＣＴオイル` → `MCTオイル` |
/// | 3 | 英字を小文字へ | `Whey` → `whey` |
/// | 4 | 連続する空白を1つへ | `鶏  むね肉` → `鶏 むね肉` |
///
/// 適用順は 1→4。2 で全角スペースは半角にならないため、1 と 4 が全角スペースも見る。
/// Dart の `String.trim` と `RegExp` の `\s` はどちらも U+3000 を空白として扱う。
///
/// **カタカナ・ひらがなの表記ゆれは吸収しない**（§4-5）。`鶏むね肉` と `鶏ムネ肉` は
/// 別行として両方入る。別物を同一視する事故を避けるための線引きである（§10-14）。
///
/// ⚠️ **設計との差**: TC-FEAT10-17 は `ＭＣＴオイル` の取込結果を `MCTオイル` と
/// 書いているが、手順3（英字を小文字へ）を通すと `mctオイル` になる。
/// 手順の記述（§4-5・§3.3・DB物理設計 §1.5）が3か所で「小文字化」と揃っているため、
/// **手順どおり小文字化する側を採った。**
String normalizeFoodName(String raw) {
  // 1. 前後の空白を除去。全角スペースもここで落ちる。
  var text = raw.trim();

  // 2. 全角英数字を半角へ。全角スペース（U+3000）はこの範囲に入らない。
  final buffer = StringBuffer();
  for (final unit in text.codeUnits) {
    final isFullWidthDigit = unit >= 0xFF10 && unit <= 0xFF19; // ０-９
    final isFullWidthUpper = unit >= 0xFF21 && unit <= 0xFF3A; // Ａ-Ｚ
    final isFullWidthLower = unit >= 0xFF41 && unit <= 0xFF5A; // ａ-ｚ
    buffer.writeCharCode(
      isFullWidthDigit || isFullWidthUpper || isFullWidthLower
          ? unit - _fullWidthOffset
          : unit,
    );
  }
  text = buffer.toString();

  // 3. 英字を小文字へ。カタカナ・漢字は変わらない。
  text = text.toLowerCase();

  // 4. 連続する空白を1つへ。タブ・改行も空白として畳む。
  return text.replaceAll(_whitespaceRun, ' ');
}

/// `name` の検証（§3.4）。妥当なら `null`、そうでなければ理由を返す。
///
/// **引数は正規化済みの文字列である。** [normalizeFoodName] をここで呼ばない。
/// 二重適用を避けるため、正規化は呼び出し側で1回だけ行う（§8）。
FoodReason? checkFoodName(String normalizedName) {
  if (normalizedName.isEmpty) return FoodReason.emptyName;
  // 数え方は UTF-16 の符号単位。絵文字は2以上に数えるが、
  // 上限そのものが入力ミス検知用の `[仮]` 値のため厳密さを求めない。
  if (normalizedName.length > kMaxFoodNameLength) return FoodReason.nameTooLong;
  return null;
}

/// `protein_amount` の検証（§3.4）。妥当なら `null`、そうでなければ理由を返す。
///
/// 受けるのは CSV のセルや入力欄の**文字列そのまま**。前後の空白は落として見る。
/// Excel 由来のセルに空白が混じることがあり、それを型エラーにする理由が無い。
///
/// 小数第2位以下は弾かない。`numeric(6,1)` が丸めるのは仕様であり、
/// 桁数エラーにしないと設計が決めている（§3.4）。
FoodReason? checkProteinAmount(String raw) {
  final text = raw.trim();
  if (text.isEmpty) return FoodReason.proteinEmpty;

  // 半角10進数だけを通す。全角数字・桁区切りカンマ・`20g` はここで落ちる。
  if (!_decimalNumber.hasMatch(text)) return FoodReason.proteinNotNumber;

  final value = double.tryParse(text);
  // 正規表現を通れば必ず数値になるが、桁あふれの `Infinity` だけは残る。
  if (value == null || !value.isFinite) return FoodReason.proteinNotNumber;

  // 下限0は DB の `CHECK (protein_amount >= 0)` と同じ規則。
  if (value < kMinProteinAmount) return FoodReason.proteinNegative;
  if (value > kMaxProteinAmount) return FoodReason.proteinTooLarge;
  return null;
}

/// `protein_amount` の入力文字列を、DB へ送る値へ直す。
///
/// 検証を通っていない文字列を渡すと `null` が返る。
/// 送る前に小数第1位へ丸める。DB の `numeric(6,1)` と同じ丸めをしておき、
/// 「保存した値」と「送った値」がずれないようにする（ADR-0022）。
double? parseProteinAmount(String? input) {
  final text = (input ?? '').trim();
  if (checkProteinAmount(text) != null) return null;
  final value = double.parse(text);
  return _roundToOneDecimal(value);
}

/// 小数第1位に丸める（ADR-0022・`numeric(6,1)`）。
double _roundToOneDecimal(double value) =>
    double.parse(value.toStringAsFixed(1));

/// 食品名の入力欄用の検証。エラー文言 or `null` を返す（ERR-FOOD-003）。
///
/// `TextFormField.validator` にそのまま渡せる形にしてある。
/// **入力欄は原文を受け取るため、ここで正規化してから [checkFoodName] を呼ぶ。**
/// CSV 取込側は正規化済みの値を渡すので、判定そのものは同じ関数を通る。
String? validateFoodNameInput(String? input) =>
    checkFoodName(normalizeFoodName(input ?? ''))?.message;

/// タンパク質量の入力欄用の検証。エラー文言 or `null` を返す（ERR-FOOD-004）。
String? validateProteinAmountInput(String? input) =>
    checkProteinAmount(input ?? '')?.message;

/// 1件編集で PostgREST へ送る `patch` を作る（§7）。
///
/// **キーは DB の列名そのまま**（snake_case）。2列とも NOT NULL のため常に両方送る。
/// 保存されるのは**正規化後**の `name` である。取込と保存値の作り方を揃えてある。
///
/// 検証を通っていない値を渡すと [ArgumentError] になる。画面側で先に弾くこと。
Map<String, dynamic> buildFoodUpdate({
  required String name,
  required String proteinAmount,
}) {
  final normalized = normalizeFoodName(name);
  final reason = checkFoodName(normalized);
  if (reason != null) {
    throw ArgumentError.value(name, 'name', reason.code);
  }
  final amount = parseProteinAmount(proteinAmount);
  if (amount == null) {
    throw ArgumentError.value(
      proteinAmount,
      'proteinAmount',
      checkProteinAmount(proteinAmount)?.code,
    );
  }
  return {'name': normalized, 'protein_amount': amount};
}
