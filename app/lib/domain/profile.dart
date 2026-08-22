/// SCR-05（設定・プロフィール）が扱う値と、その検証。
///
/// UI にも Supabase にも依存しない。`BuildContext` も `SupabaseClient` も
/// 受け取らない。ここに置いたものは全て単体テストの対象（NFR-QUAL-01）。
///
/// 正本は `FEAT-06_初期設定.md`。列と CHECK 制約は `01_DB物理設計.md §1.1`。
library;

/// 目標トレーニング回数（月）の既定＝12（RULE-007。週3回想定）。
///
/// ⚠️ **DB は `null` のまま。既定を出すのはアプリ側だけ**（W-06 の判断）。
///
/// 設計（FEAT-06 §4.2）はトリガ側の SQL を既定値の正本としているが、
/// 実際のトリガ `handle_new_user` は `name` しか入れない。
/// DB を直すにはマイグレーションが要り、W-06 の範囲（`app/` 配下のみ）を超える。
/// そこで「**DB は `null`／表示は 12**」という差を受け入れ、読むときに [Profile]
/// が 12 を補う。
///
/// **FEAT-05（ダッシュボード）も同じ既定を使うこと。** 「今月のトレーニング
/// N / 12 回」の分母がこの値である。片方だけ `null` を素通しすると、
/// 同じ利用者に別の分母が出る。
const kDefaultTargetTrainingCount = 12;

/// 体重の下限(kg)。DB の `CHECK (weight_kg > 0)` より厳しい（FEAT-06 §3.3 `[仮]`）。
///
/// 入力ミスの検知が目的であって、業務上の根拠は無い。
const kMinWeightKg = 20.0;

/// 体重の上限(kg)。桁の誤入力を捕まえるための値（FEAT-06 §3.3 `[仮]`）。
const kMaxWeightKg = 300.0;

/// 目標トレーニング回数の上限。1日1回・月最大31日という想定（FEAT-06 §3.3 `[仮]`）。
const kMaxTargetTrainingCount = 31;

/// 表示名の上限文字数（FEAT-06 §3.3 `[仮]`）。
const kMaxNameLength = 50;

/// `users` の本人1行。
///
/// 列名は snake_case のまま扱う（`06_DB設計規約.md` の物理命名規約）。
/// Dart 側でキャメルケースへ直すのは、このクラスの中だけにする。
class Profile {
  const Profile({
    required this.id,
    required this.name,
    required this.targetTrainingCount,
    required this.weightKg,
  });

  /// `users.id`（uuid）。`auth.users.id` と同値（ADR-0005 案A）。
  final String id;

  /// 表示名。`users.name` は NOT NULL のため空にならない。
  final String name;

  /// 目標トレーニング回数（月）。
  ///
  /// **DB が `null` でもここには [kDefaultTargetTrainingCount] が入る。**
  /// 画面は「未設定」を見ない。
  final int targetTrainingCount;

  /// 体重(kg)。`null` は**未設定**であって 0 ではない。
  ///
  /// 体重は推測してはならない値のため、既定を置かない（FEAT-06 §4.2）。
  final double? weightKg;

  /// 体重が未設定か。SCR-05 の誘導表示（FEAT-06 §7）の判定に使う。
  bool get isWeightUnset => weightKg == null;

  /// PostgREST が返す1行から作る。
  factory Profile.fromJson(Map<String, dynamic> json) => Profile(
    id: json['id'] as String,
    name: (json['name'] as String? ?? '').trim(),
    // ここが「DB は null・表示は 12」の変換点（上の [kDefaultTargetTrainingCount]）。
    targetTrainingCount:
        _asInt(json['target_training_count']) ?? kDefaultTargetTrainingCount,
    weightKg: _asDouble(json['weight_kg']),
  );
}

/// `numeric` を `double` へ直す。**変換はこの1か所に集約する**（ADR-0022）。
///
/// PostgreSQL の `numeric` はドライバによって文字列で返ることがある。
/// どちらで来ても同じ結果になるようにしておく。
double? _asDouble(Object? value) {
  if (value == null) return null;
  if (value is num) return value.toDouble();
  if (value is String) return double.tryParse(value);
  return null;
}

/// `int` を取り出す。`numeric` と同じ理由で文字列も受ける。
int? _asInt(Object? value) {
  if (value == null) return null;
  if (value is int) return value;
  if (value is num) return value.toInt();
  if (value is String) return int.tryParse(value);
  return null;
}

/// 部分更新の1フィールド。**不在／null／値**の3状態を持つ（FEAT-06 §4.3）。
///
/// Dart の `null` だけでは「変更しない」と「未設定に戻す」を区別できない。
/// 体重は `null` に戻せる必要があるため、区別できる形にしてある。
class FieldPatch<T> {
  /// 変更しない。`patch` にキーを出さない。
  const FieldPatch.absent() : isPresent = false, value = null;

  /// この値にする。`null` を渡せば「未設定に戻す」。
  const FieldPatch.of(this.value) : isPresent = true;

  /// 値が指定されたか。`false` なら `patch` に出さない。
  final bool isPresent;

  /// 指定された値。[isPresent] が `false` のときは意味を持たない。
  final T? value;
}

/// `users` への更新指示。指定しなかった列は変更しない。
class ProfileUpdate {
  const ProfileUpdate({
    this.name = const FieldPatch<String>.absent(),
    this.targetTrainingCount = const FieldPatch<int>.absent(),
    this.weightKg = const FieldPatch<double>.absent(),
  });

  /// 表示名。`users.name` は NOT NULL のため `null` は送らない。
  final FieldPatch<String> name;

  /// 目標トレーニング回数（月）。
  final FieldPatch<int> targetTrainingCount;

  /// 体重(kg)。`FieldPatch.of(null)` で未設定に戻す。
  final FieldPatch<double> weightKg;
}

/// 更新指示から PostgREST へ送る `patch` を作る（FEAT-06 §4.3）。
///
/// **キーは DB の列名そのまま**（snake_case）。ここで3列以外を出さないため、
/// 未知列（ERR-VALIDATION-001）は構造的に起きない。
///
/// 返り値が空の `Map` なら「変更が無い」。呼び出し側で更新をやめること。
Map<String, dynamic> buildProfileUpdate(ProfileUpdate input) {
  final patch = <String, dynamic>{};

  if (input.name.isPresent) {
    final name = (input.name.value ?? '').trim();
    // `users.name` は NOT NULL。空は送らない。
    // ここへ来る前に [validateName] が弾いている（保険）。
    if (name.isNotEmpty) patch['name'] = name;
  }

  if (input.targetTrainingCount.isPresent) {
    patch['target_training_count'] = input.targetTrainingCount.value;
  }

  if (input.weightKg.isPresent) {
    final weight = input.weightKg.value;
    // 送る前に丸める。DB が `numeric(6,1)` で丸めるのと同じ結果にして、
    // 「保存した値」と「送った値」がずれないようにする（ADR-0022）。
    patch['weight_kg'] = weight == null ? null : roundToOneDecimal(weight);
  }

  return patch;
}

/// 小数第1位に丸める（ADR-0022・`numeric(6,1)`）。
///
/// DB 側は丸めて保存する。アプリ側で拒否せず、同じ丸めをしてから送る。
///
/// ⚠️ **設計との差**: FEAT-06 §3.3 は「小数第2位以降は丸めずに拒否」
/// （ERR-PROFILE-001・TC-FEAT06-05）としている。W-06 は **ADR-0022 側に寄せた**。
/// 拒否しても DB は丸めて受けるため、拒否は利用者に手間を課すだけになる。
double roundToOneDecimal(double value) =>
    double.parse(value.toStringAsFixed(1));

/// 表示名の検証（ERR-PROFILE-003）。エラー文言 or `null` を返す。
///
/// `TextFormField.validator` にそのまま渡せる形にしてある。
/// `BuildContext` を取らないため、テストから直接呼べる。
String? validateName(String? input) {
  final text = (input ?? '').trim();
  // 空・空白のみは不可。`users.name` が NOT NULL であることと揃える。
  if (text.isEmpty) return '表示名を入力してください。';
  // 数え方は UTF-16 の符号単位。絵文字は2以上に数えるが、
  // 上限そのものが入力ミス検知用の `[仮]` 値のため厳密さを求めない。
  if (text.length > kMaxNameLength) {
    return '表示名は$kMaxNameLength文字以内で入力してください。';
  }
  return null;
}

/// 目標トレーニング回数の検証（ERR-PROFILE-002）。エラー文言 or `null` を返す。
///
/// 空欄は「未設定」で正常。読むときに [kDefaultTargetTrainingCount] が補う。
String? validateTargetTrainingCount(String? input) {
  final text = (input ?? '').trim();
  if (text.isEmpty) return null;
  // 小数・数字でない文字列は `null` になる。どちらも整数ではない。
  final value = int.tryParse(text);
  if (value == null) return '目標回数は整数で入力してください。';
  // 下限0は DB の `CHECK (target_training_count >= 0)` と同じ規則。
  // 0＝「目標を置かない」であり、拒否しない。
  if (value < 0 || value > kMaxTargetTrainingCount) {
    return '目標回数は0〜$kMaxTargetTrainingCount回で入力してください。';
  }
  return null;
}

/// 体重の検証（ERR-PROFILE-001）。エラー文言 or `null` を返す。
///
/// **空欄は「未設定」で正常。** 体重は推測してはならない値のため、
/// 入れていないことを異常にしない。
String? validateWeightKg(String? input) {
  final text = (input ?? '').trim();
  if (text.isEmpty) return null;

  final value = double.tryParse(text);
  // `Infinity` `NaN` も `double.tryParse` は通す。範囲判定が効かないため先に落とす。
  if (value == null || !value.isFinite) return '体重は数字で入力してください。';

  // 0以下は DB の `CHECK (weight_kg > 0)` に触れる。下限20.0がそれを含む。
  if (value < kMinWeightKg || value > kMaxWeightKg) {
    return '体重は${kMinWeightKg.toStringAsFixed(1)}〜'
        '${kMaxWeightKg.toStringAsFixed(1)}kgで入力してください。';
  }

  // 小数第2位以降は**丸めずに拒否する**（FEAT-06 §3.3）。
  //
  // DB の `numeric(6,1)` は送れば黙って丸める（ADR-0022）。
  // だからこそアプリで弾く。62.55 を黙って 62.6 にすると、
  // 利用者は 62.55 で保存されたと思い込む。
  // 入力を勝手に書き換えないための規則である。
  if (roundToOneDecimal(value) != value) {
    return '体重は0.1kg刻みで入力してください。';
  }
  return null;
}

/// 体重の入力欄の文字列を、DB へ送る値へ直す。
///
/// 空欄は「未設定」を意味する `null`。小数第1位に丸める（ADR-0022）。
/// 数値に読めない文字列も `null` になるが、そこへ来る前に
/// [validateWeightKg] が弾いている。
double? parseWeightKg(String? input) {
  final text = (input ?? '').trim();
  if (text.isEmpty) return null;
  final value = double.tryParse(text);
  if (value == null || !value.isFinite) return null;
  return roundToOneDecimal(value);
}

/// 目標回数の入力欄の文字列を、DB へ送る値へ直す。
///
/// 空欄は `null`（未設定）。読むときに [kDefaultTargetTrainingCount] が補う。
int? parseTargetTrainingCount(String? input) {
  final text = (input ?? '').trim();
  if (text.isEmpty) return null;
  return int.tryParse(text);
}
