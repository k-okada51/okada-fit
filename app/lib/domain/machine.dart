/// SCR-02（器具登録）が扱う値と、その検証。
///
/// UI にも Supabase にも依存しない。`BuildContext` も `SupabaseClient` も
/// 受け取らない。ここに置いたものは全て単体テストの対象（NFR-QUAL-01）。
///
/// 正本は `FEAT-01_器具登録.md`。列と CHECK 制約は `01_DB物理設計.md §1.2〜§1.6`。
/// RPC 3本の定義は同 §3.6。
library;

/// 器具名の上限文字数（FEAT-01 §3.2 `[仮]`）。
///
/// ⚠️ **DB の型は `text` で無制限**。長さを担保できるのはアプリ側だけである
/// （§3.5 の補足）。JWT を持つ利用者は PostgREST を直接叩けるため、
/// ここでの上限は防御ではなく体験のためのものになる。
const kMaxMachineNameLength = 100;

/// 種目名の上限文字数（FEAT-01 §3.3 `[仮]`）。
const kMaxMenuNameLength = 100;

/// ジム名の上限文字数（FEAT-01 §3.4 `[仮]`）。
const kMaxGymNameLength = 100;

/// やり方メモの上限文字数（FEAT-01 §3.3 `[仮]`）。
const kMaxHowToLength = 1000;

/// 部位タグ（RULE-003）。
///
/// **値の正本はDB側**であり、アプリ側で値を増やさない（§4 L-02）。
/// [label] は `training_menus` の CHECK 制約
/// `ck_training_menus_body_part CHECK (body_part IN ('胸','背中','脚','肩','腕'))`
/// と一字一句そろえる。
///
/// **宣言順が RULE-003 の並び**（胸/背中/脚/肩/腕）である。表示順・一覧の並びは
/// この順に揃える（§4 L-01・§5.6）。
enum BodyPart {
  chest('胸'),
  back('背中'),
  leg('脚'),
  shoulder('肩'),
  arm('腕');

  const BodyPart(this.label);

  /// DB に入る文字列。
  final String label;
}

/// 部位の文字列を [BodyPart] へ直す（§4 L-02）。5値以外は `null`。
///
/// **trim しない。** DB の CHECK も trim しないため、ここで空白を落とすと
/// アプリが通した値を DB が弾く、という食い違いが生まれる。
BodyPart? parseBodyPart(String? raw) {
  if (raw == null) return null;
  for (final part in BodyPart.values) {
    if (part.label == raw) return part;
  }
  return null;
}

/// `gyms` の1行。
class Gym {
  const Gym({required this.id, required this.name});

  /// PostgREST が返す1行から作る。
  factory Gym.fromJson(Map<String, dynamic> json) =>
      Gym(id: _asInt(json['id'])!, name: (json['name'] as String? ?? '').trim());

  /// `gyms.id`（bigint）。
  final int id;

  /// ジム名。`gyms.name` は NOT NULL のため空にならない。
  final String name;
}

/// `training_menus` の1行。**部位タグ（RULE-003）の保持主体**である。
class TrainingMenu {
  const TrainingMenu({
    required this.id,
    required this.name,
    required this.bodyPart,
    this.howTo,
  });

  /// PostgREST が返す1行から作る。
  ///
  /// [bodyPart] が5値以外なら [FormatException] を投げる。DB の CHECK が
  /// 効いている限り起きない。起きたら制約が外れている＝実装の誤りである。
  factory TrainingMenu.fromJson(Map<String, dynamic> json) {
    final raw = json['body_part'] as String?;
    final bodyPart = parseBodyPart(raw);
    if (bodyPart == null) {
      throw FormatException('body_part が RULE-003 の5値ではありません', raw);
    }
    return TrainingMenu(
      id: _asInt(json['id'])!,
      name: (json['name'] as String? ?? '').trim(),
      bodyPart: bodyPart,
      howTo: json['how_to'] as String?,
    );
  }

  /// `training_menus.id`（bigint）。
  final int id;

  /// 種目名。
  final String name;

  /// 部位（RULE-003）。器具の部位はこの値からしか導けない（§4 L-01）。
  final BodyPart bodyPart;

  /// やり方メモ。**空を許容する**（ADR-0021）。
  ///
  /// ⚠️ 器具一覧の埋め込み select（§3.2 の EMB）はこの列を取らない。
  /// [TrainingMachine.menus] 経由で得た種目では常に `null` になる。
  final String? howTo;
}

/// `training_machines` の1行。ジム名と対応種目を同梱した形（§3.2 の EMB）。
class TrainingMachine {
  const TrainingMachine({
    required this.id,
    required this.name,
    required this.gymId,
    required this.gymName,
    required this.menus,
  });

  /// 埋め込み select の入れ子を平坦化して作る（§3.2）。
  ///
  /// 旧構成にあったトップレベルの `gym_name` `menu_name` `body_part` は無い。
  /// ジムは入れ子 `gyms`、種目は**配列** `machine_menus` から取る。
  factory TrainingMachine.fromJson(Map<String, dynamic> json) {
    final gym = json['gyms'];
    // 埋め込みは to-one なら Map で返る。念のため List で来た場合も先頭を見る。
    final gymRow = gym is List
        ? (gym.isEmpty ? null : gym.first as Map<String, dynamic>)
        : gym as Map<String, dynamic>?;

    final links = json['machine_menus'] as List<dynamic>? ?? const [];
    final menus = <TrainingMenu>[];
    for (final link in links) {
      final row = link as Map<String, dynamic>;
      final menu = row['training_menus'] as Map<String, dynamic>?;
      if (menu == null) continue;
      menus.add(
        TrainingMenu.fromJson({
          // 種目の id は中間テーブル側の `menu_id` にある（EMB の形）。
          'id': row['menu_id'],
          'name': menu['name'],
          'body_part': menu['body_part'],
          // EMB は `how_to` を取らない。ここでは常に null になる。
          'how_to': menu['how_to'],
        }),
      );
    }

    return TrainingMachine(
      id: _asInt(json['id'])!,
      name: (json['name'] as String? ?? '').trim(),
      gymId: _asInt(json['gym_id'])!,
      gymName: (gymRow?['name'] as String? ?? '').trim(),
      menus: menus,
    );
  }

  /// `training_machines.id`（bigint）。
  final int id;

  /// 器具名。
  final String name;

  /// 設置ジムの id。
  final int gymId;

  /// 設置ジムの名前（入れ子 `gyms.name` の平坦化）。
  final String gymName;

  /// 紐づく種目。**1件以上**である（§3.5 で種目0件の器具を作らせない）。
  final List<TrainingMenu> menus;

  /// 器具の部位（§4 L-01）。重複を除き RULE-003 の並びで返す。
  List<BodyPart> get bodyParts => resolveBodyParts(menus);
}

/// 器具の部位を導く（§4 L-01・RULE-003・**本機能の中核**）。
///
/// 器具は部位列を持たない。`machine_menus` → `training_menus.body_part` を
/// 辿って導く。同じ部位の種目が2件紐づいていても部位は1件に畳む
/// （器具が一覧で2回出ないようにするため・§4）。
///
/// ⚠️ **設計との差**: FEAT-01 §4 L-01 の戻りは `Set<BodyPart>` だが、ここでは
/// `List<BodyPart>` を返す。同 §4 が「`Set` の反復順に依存させない」と定めており、
/// 並びを戻り値の約束にしたほうが守りやすいためである。中身は重複を除いた集合で
/// あることに変わりはない。
List<BodyPart> resolveBodyParts(Iterable<TrainingMenu> menus) {
  final found = menus.map((menu) => menu.bodyPart).toSet();
  // `BodyPart.values` の宣言順＝RULE-003 の並び。
  return BodyPart.values.where(found.contains).toList();
}

/// 名称の正規化（§4 L-03）。**重複判定と比較にだけ使う。**
///
/// **保存する値は正規化前の原文**である。表示は利用者の入力どおりにする。
///
/// ⚠️ **設計との差**: L-03 は `NFKC → trim → 連続空白の畳み込み` と定めるが、
/// Dart に NFKC は標準で無く、W-08 では依存を増やさない。**NFKC は行わない** `[仮]`。
/// 全角と半角の差（`ラット` と `ﾗｯﾄ`）は吸収されない。
/// 英字の大文字小文字を畳むかも未定のまま（FEAT-01 §10 #8）。
String normalizeName(String raw) => raw.trim().replaceAll(RegExp(r'\s+'), ' ');

/// 器具を登録できる状態か（§4 L-04）。
///
/// ジムか種目が1件も無いと器具は作れない。`gym_id` は NOT NULL FK であり、
/// 種目は1件以上要る。取得済みの一覧件数だけで判定する。
bool canRegisterMachine(int gymCount, int menuCount) =>
    gymCount > 0 && menuCount > 0;

/// 選んだ種目IDから重複を除く（§4 L-05）。
///
/// `uq_mm_machine_menu`（`machine_menus(machine_id, menu_id)`）と整合させる。
/// 重複したまま RPC へ渡すと `23505` になり、器具行ごと巻き戻る。
///
/// 並びは最初に出た順を保つ（Dart の `Set` は挿入順を保つ）。
List<int> normalizeMenuIds(Iterable<int> ids) => ids.toSet().toList();

/// 制御文字（NUL・改行・タブ等）。
///
/// **器具名だけが明示的に禁じている**（§3.5）。種目名・ジム名の規則には
/// 書かれていないため、そちらには掛けない。設計に無い制限を足さない。
final _controlChars = RegExp(r'[\x00-\x1F\x7F]');

/// 器具名の検証（ERR-MACHINE-001）。エラー文言 or `null` を返す。
///
/// `TextFormField.validator` にそのまま渡せる形にしてある。
/// `BuildContext` を取らないため、テストから直接呼べる。
String? validateMachineName(String? input) {
  final text = (input ?? '').trim();
  // 空・空白のみは不可。`training_machines.name` が NOT NULL であることと揃える。
  if (text.isEmpty) return '器具名を入力してください。';
  // 数え方は UTF-16 の符号単位。絵文字は2以上に数えるが、
  // 上限そのものが `[仮]` 値のため厳密さを求めない（`profile.dart` と同じ）。
  if (text.length > kMaxMachineNameLength) {
    return '器具名は$kMaxMachineNameLength文字以内で入力してください。';
  }
  if (_controlChars.hasMatch(text)) {
    return '器具名に使えない文字が含まれています。';
  }
  return null;
}

/// ジムの選択の検証（ERR-MACHINE-002）。
///
/// `DropdownButtonFormField<int>.validator` にそのまま渡せる。
String? validateGymSelection(int? gymId) {
  if (gymId == null) return 'ジムを選んでください。';
  return null;
}

/// 種目の選択の検証（ERR-MACHINE-003 / ERR-MACHINE-016・§4 L-05）。
///
/// 0件は `create_machine` が `RAISE EXCEPTION 'ERR-MACHINE-003'` で拒否する。
/// **そこへ到達させない。** 画面は [登録] を非活性にし、ここで文言を出す。
///
/// 重複は `uq_mm_machine_menu` 違反（`23505`）になる。選択UIは `Set<int>` の
/// ため構造的に起きないが、手組みの呼び出しに対する防御として残す。
///
/// ⚠️ **設計との差**: FEAT-01 §4 L-05 は `throw` と書くが、ここは文言 or `null`
/// を返す。**入力の検証エラーを例外にしない**（W-05 の約束・`profile.dart` と同じ）。
String? validateMenuSelection(Iterable<int> ids) {
  final list = ids.toList();
  if (list.isEmpty) return '種目を1件以上選んでください。';
  if (list.toSet().length < list.length) return '同じ種目は1回だけ選べます。';
  return null;
}

/// 種目名の検証（ERR-MACHINE-008）。
String? validateMenuName(String? input) {
  final text = (input ?? '').trim();
  if (text.isEmpty) return '種目名を入力してください。';
  if (text.length > kMaxMenuNameLength) {
    return '種目名は$kMaxMenuNameLength文字以内で入力してください。';
  }
  return null;
}

/// 部位の検証（ERR-MACHINE-009・§4 L-02）。
///
/// DB の CHECK（`23514`）と同じ規則をアプリ側でも弾く。
/// 画面は `SegmentedButton` で5値しか選べないが、値の判定はここに集約する。
String? validateBodyPart(String? input) {
  if (input == null || input.isEmpty) return '部位を選んでください。';
  if (parseBodyPart(input) == null) return '部位を選んでください。';
  return null;
}

/// やり方メモの検証（ERR-MACHINE-010）。
///
/// **空欄は正常。** 必須にしない（ADR-0021・§3.3）。
/// 空のままだと FEAT-03 の説明が空欄になるが、それを許容する決定である。
String? validateHowTo(String? input) {
  final text = (input ?? '').trim();
  if (text.isEmpty) return null;
  if (text.length > kMaxHowToLength) {
    return 'やり方は$kMaxHowToLength文字以内で入力してください。';
  }
  return null;
}

/// ジム名の検証（ERR-MACHINE-014）。
String? validateGymName(String? input) {
  final text = (input ?? '').trim();
  if (text.isEmpty) return 'ジム名を入力してください。';
  if (text.length > kMaxGymNameLength) {
    return 'ジム名は$kMaxGymNameLength文字以内で入力してください。';
  }
  return null;
}

/// `create_machine`（C-01）の引数を作る。
///
/// **キーは関数の引数名そのまま**（`p_` 接頭辞・snake_case・`06_DB設計規約.md §5`）。
/// 1文字でも違うと PostgREST が関数を見つけられず `PGRST202` になる。
/// 適用済みの実物は `create_machine(p_gym_id bigint, p_name text, p_menu_ids bigint[])`。
///
/// `p_menu_ids` は重複を除いてから渡す（[normalizeMenuIds]）。
/// 空のまま渡すと関数が `ERR-MACHINE-003` を投げる。呼ぶ前に
/// [validateMenuSelection] で止めること。
Map<String, dynamic> buildCreateMachineParams({
  required int gymId,
  required String name,
  required Iterable<int> menuIds,
}) => {
  'p_gym_id': gymId,
  // 保存するのは原文（前後の空白だけ落とす）。正規化名は送らない（§4 L-03）。
  'p_name': name.trim(),
  'p_menu_ids': normalizeMenuIds(menuIds),
};

/// `update_machine`（C-03）の引数を作る。
///
/// 引数は `create_machine` に `p_machine_id` が加わった形である。
/// 紐づけは**全置換**なので、残したい種目もすべて [menuIds] に入れる（§5.7）。
Map<String, dynamic> buildUpdateMachineParams({
  required int machineId,
  required int gymId,
  required String name,
  required Iterable<int> menuIds,
}) => {
  'p_machine_id': machineId,
  ...buildCreateMachineParams(gymId: gymId, name: name, menuIds: menuIds),
};

/// `delete_machine`（C-04）の引数を作る。
///
/// `machine_menus` の子行は FK の `ON DELETE CASCADE` で消える。
/// アプリから子行を消さない（§10 #15）。
Map<String, dynamic> buildDeleteMachineParams(int machineId) => {
  'p_machine_id': machineId,
};

/// `training_menus` への INSERT 値（C-06）。
///
/// **キーは DB の列名そのまま**（snake_case）。
///
/// ⚠️ **設計との差**: FEAT-01 §3.3 は `user_id` を「アプリから送らない」と定める
/// が、適用済みの DDL では `training_menus.user_id` が NOT NULL で既定値を持たない
/// （`20260808045254_create_master_tables.sql`）。送らないと `23502` になるため、
/// [userId] を受け取ってここで入れる。
/// **他人の行は作れない。** RLS の `WITH CHECK (user_id = auth.uid())` が弾く。
/// DB 側に `DEFAULT auth.uid()` を入れれば送らずに済む `[仮]`。
Map<String, dynamic> buildMenuInsert({
  required String userId,
  required String name,
  required BodyPart bodyPart,
  String? howTo,
}) {
  final memo = (howTo ?? '').trim();
  return {
    'user_id': userId,
    'name': name.trim(),
    'body_part': bodyPart.label,
    // 空欄は「未入力」。空文字ではなく null を入れる（`how_to` は null 許容）。
    'how_to': memo.isEmpty ? null : memo,
  };
}

/// `gyms` への INSERT 値（C-10）。
///
/// `gyms` は共通マスタで所有者列を持たない（ADR-0005）。送るのは名前だけ。
Map<String, dynamic> buildGymInsert(String name) => {'name': name.trim()};

/// 一覧の並び（§5.6）。ジム名 → 部位 → 器具名。
///
/// PostgREST の `order` は親テーブルの列でしか並べられず、この並びを表現できない。
/// **Dart 側で並べる** `[仮]`。全件取得が前提になるため、件数が増えたら
/// ビュー化を検討する（§10 #11）。
///
/// 器具の部位は集合になる。並びに使う代表値は、RULE-003 の並びで最も先に来る
/// ものとする `[仮]`（§7.3）。
List<TrainingMachine> sortMachines(Iterable<TrainingMachine> machines) {
  final sorted = machines.toList();
  sorted.sort((a, b) {
    final byGym = a.gymName.compareTo(b.gymName);
    if (byGym != 0) return byGym;
    final byPart = _primaryBodyPartIndex(a).compareTo(_primaryBodyPartIndex(b));
    if (byPart != 0) return byPart;
    return a.name.compareTo(b.name);
  });
  return sorted;
}

/// 並びに使う代表部位の位置。部位を持たない器具は末尾へ送る。
int _primaryBodyPartIndex(TrainingMachine machine) {
  final parts = machine.bodyParts;
  // `bodyParts` は RULE-003 の並びなので、先頭が最も先に来る部位である。
  return parts.isEmpty ? BodyPart.values.length : parts.first.index;
}

/// `bigint` を `int` へ直す。
///
/// PostgreSQL の `bigint` はドライバによって文字列で返ることがある。
/// どちらで来ても同じ結果になるようにしておく（`profile.dart` の `_asInt` と同じ）。
int? _asInt(Object? value) {
  if (value == null) return null;
  if (value is int) return value;
  if (value is num) return value.toInt();
  if (value is String) return int.tryParse(value);
  return null;
}
