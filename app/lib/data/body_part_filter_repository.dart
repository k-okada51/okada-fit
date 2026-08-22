/// 部位で器具を絞り込む（FEAT-02）。
///
/// **AI を使わない**（RULE-004）。部位タグの等値一致だけで決まる処理である。
/// スコアリングも優先度も持たない。
///
/// 経路は**3ホップ**。`training_menus` → `machine_menus` → `training_machines`。
/// 器具は部位列を持たない。部位を持つのは種目だけである（RULE-003）。
///
/// **起点は種目（`training_menus`）**。W-08 の `machine_repository.dart` は
/// 器具を起点にするが、本機能は部位の条件を起点に置く（FEAT-02 §3 の起点比較）。
/// 引き換えに**同じ器具が種目の件数だけ返る**。畳み込みが要る（§5）。
///
/// UI を知らない。`BuildContext` を受け取らない。
/// 例外は写像せずそのまま上へ投げる。利用者向け文言への変換は
/// `data/error_mapper.dart`（W-05）の担当で、呼ぶのは画面側。
library;

import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/supabase.dart';
import '../domain/machine.dart';
import 'error_mapper.dart';

/// 部位が RULE-003 の5値でない（ERR-MACHINE-020）。
///
/// **呼び出す前に検出する。** 往復を発生させない（§6）。
const errBodyPartNotAllowed = AppFailure(
  code: 'ERR-MACHINE-020',
  message: '部位を選び直してください。',
  retryable: false,
);

/// ジムの指定が正の整数でない（ERR-MACHINE-022）。
const errGymIdNotAllowed = AppFailure(
  code: 'ERR-MACHINE-022',
  message: 'ジムを選び直してください。',
  retryable: false,
);

/// 絞り込みの条件。**検証を通ったものだけが存在できる形**にしてある。
///
/// 生成できたときだけ PostgREST を呼ぶ。5値以外の部位や不正な `gymId` では
/// 生成できず、呼び出しがそもそも発行されない（§2 ①・TC-FEAT02-05）。
class MachineFilter {
  const MachineFilter._({this.bodyPart, this.gymId});

  /// 生の値から作る。**作れないときは `null`**（＝呼び出しを発行しない）。
  ///
  /// [bodyPartLabel] が `null` のときは部位で絞らない。FEAT-01 の一覧用途と
  /// 共用するための入口である（§4）。`null` 以外は5値と一致しないと作れない。
  ///
  /// ⚠️ **設計との差**: FEAT-02 §3.1 は「前後空白トリム後に一致」と定めるが、
  /// 判定は W-08 の [parseBodyPart] に任せる。**trim しない。**
  /// アプリ側とDB側で判定がずれないことを優先した（`domain/machine.dart` の理由）。
  ///
  /// [gymId] は `null`（絞らない）か 1 以上の整数（§3.1）。
  static MachineFilter? tryCreate({String? bodyPartLabel, int? gymId}) {
    if (gymId != null && gymId < 1) return null;
    if (bodyPartLabel == null) return MachineFilter._(gymId: gymId);
    final bodyPart = parseBodyPart(bodyPartLabel);
    if (bodyPart == null) return null;
    return MachineFilter._(bodyPart: bodyPart, gymId: gymId);
  }

  /// 絞り込む部位（RULE-003）。**単一選択。** `null` は絞り込みなし。
  final BodyPart? bodyPart;

  /// 絞り込むジム。`null` は絞り込みなし（ジムが1件のときの既定・§7）。
  final int? gymId;

  /// 埋め込み select（§3）。**3ホップを1往復で取る。**
  ///
  /// 器具ごとに種目やジムを引き直す N+1 を作らない（NFR-PERF-02）。
  static const _columns =
      'id, name, body_part, '
      'machine_menus ( training_machines ( id, name, gym_id, gyms ( id, name ) ) )';

  /// ジムで絞るときの埋め込み select（§3）。
  ///
  /// **`!inner` を2段とも付ける。** 落とすと器具が0台の種目行が残り、
  /// ジムの条件が効かない行が混ざる。
  static const _columnsByGym =
      'id, name, body_part, '
      'machine_menus!inner ( training_machines!inner ( id, name, gym_id, gyms ( id, name ) ) )';

  /// この条件で発行する select。ジム指定の有無で `!inner` が変わる。
  String get select => gymId == null ? _columns : _columnsByGym;
}

/// 絞り込みの結果（§3 の封筒）。
///
/// 配列を直に返さない。要求した部位を一緒に返すことで、部位を素早く切り替えた
/// ときの取り違えを画面側で検出できる（§7 の世代カウンタ）。
class MachineListResult {
  const MachineListResult({
    required this.bodyPart,
    required this.gymId,
    required this.machines,
  });

  /// 要求した部位のエコーバック（未指定時 `null`）。
  final BodyPart? bodyPart;

  /// 要求したジムのエコーバック（未指定時 `null`）。
  final int? gymId;

  /// 器具の一覧。**重複除去と整列を済ませてある。**
  final List<TrainingMachine> machines;

  /// 件数（重複除去後）。**0 は正常**である（§10 #1）。
  ///
  /// ⚠️ **設計との差**: §3 は `total` を格納フィールドとするが、ここでは
  /// 導出値にした。[machines] と食い違う余地を残さないため。
  int get total => machines.length;

  /// 器具が1件も無いか。0件分岐の判定はこの1箇所に寄せる（§7）。
  bool get isEmpty => machines.isEmpty;

  /// FEAT-03 に渡す `machine_ids` の供給源（§1 #4）。
  List<int> get machineIds => machines.map((machine) => machine.id).toList();
}

/// 部位での器具の絞り込み（FEAT-02）。
class BodyPartFilterRepository {
  /// [client] を渡さない場合は初期化済みの共有クライアントを使う。
  BodyPartFilterRepository({SupabaseClient? client})
    : _client = client ?? supabase;

  final SupabaseClient _client;

  /// 部位（と任意でジム）に一致する器具を返す（§3）。
  ///
  /// 往復は**1回**。埋め込み select が種目・中間・器具・ジムを一度に返す。
  ///
  /// **`user_id` を条件に書かない。** 起点の `training_menus` と中間の
  /// `machine_menus` の RLS が本人行に絞る（ADR-0005・§5）。
  ///
  /// 0件は例外にしない。`total: 0` の [MachineListResult] を返す（§10 #1）。
  Future<MachineListResult> findMachines(MachineFilter filter) async {
    var query = _client.from('training_menus').select(filter.select);

    final bodyPart = filter.bodyPart;
    if (bodyPart != null) {
      // 絞り込みは等値一致だけ（RULE-004）。DB に入っている値は日本語である。
      query = query.eq('body_part', bodyPart.label);
    }
    final gymId = filter.gymId;
    if (gymId != null) {
      // 埋め込み側へのフィルタ。中間テーブルを挟むぶん経路が伸びる（§3）。
      query = query.eq('machine_menus.training_machines.gym_id', gymId);
    }

    // postgrest-dart の `order` は既定が降順。昇順は明示する。
    // なお最終的な並びは Dart 側で決める（[sortFilteredMachines]）。
    final rows = await query.order('name', ascending: true);

    return MachineListResult(
      bodyPart: filter.bodyPart,
      gymId: filter.gymId,
      machines: sortFilteredMachines(groupMachines(rows)),
    );
  }
}

/// 応答を器具単位に畳む（§4・§5「`DISTINCT` が要る理由」）。**本機能の中核。**
///
/// 起点が `training_menus` のため、1台の器具は紐づく種目の件数だけ現れる。
/// 例えばケーブルマシンが「ラットプルダウン」「シーテッドロー」に紐づくと、
/// 部位「背中」で引いたとき**同じ器具が2行**返る。
///
/// **埋め込み select 自体は `DISTINCT` を持たない。** SQL の
/// `SELECT DISTINCT`（§5 (1)）に相当する仕事をここで行う。
///
/// ⚠️ 畳み忘れても**例外は出ない。同じ器具が並ぶだけ**である（§10 #10）。
/// 気付きにくいため単体テストで押さえる（TC-FEAT02-14）。
///
/// 畳み込みのキーは `training_machines.id`。**名前で畳まない**（§4）。
/// 同名の別マシンが同じジムに2台ある運用を潰さないためである。
List<TrainingMachine> groupMachines(List<dynamic> rows) {
  // 器具ID → 器具の生行。最初に見つけた行を採る（どの種目から辿っても同じ器具）。
  final machineRows = <int, Map<String, dynamic>>{};
  // 器具ID → その器具で引っかかった種目。**畳んだ後も種目は全部残す。**
  final menusByMachine = <int, List<TrainingMenu>>{};
  // 器具ID → 積んだ種目ID。同じ器具×同じ種目を二重に積まない
  // （`uq_mm_machine_menu` と同じ規則）。
  final seenMenuIds = <int, Set<int>>{};

  for (final raw in rows) {
    final row = raw as Map<String, dynamic>;
    // 種目は行そのもの。`TrainingMenu.fromJson` が期待する形と一致する。
    // 5値以外なら `FormatException`（DB の CHECK が外れている＝実装の誤り）。
    final menu = TrainingMenu.fromJson(row);

    final links = row['machine_menus'] as List<dynamic>? ?? const [];
    for (final link in links) {
      final machineRow = _asRow(
        (link as Map<String, dynamic>)['training_machines'],
      );
      // 器具の無い中間行は捨てる。`!inner` を付けない経路では起こりうる。
      if (machineRow == null) continue;
      final machineId = _asInt(machineRow['id']);
      if (machineId == null) continue;

      machineRows[machineId] ??= machineRow;
      if (!seenMenuIds.putIfAbsent(machineId, () => <int>{}).add(menu.id)) {
        continue;
      }
      menusByMachine.putIfAbsent(machineId, () => <TrainingMenu>[]).add(menu);
    }
  }

  return [
    for (final entry in machineRows.entries)
      TrainingMachine(
        id: entry.key,
        name: (entry.value['name'] as String? ?? '').trim(),
        // `gym_id` は NOT NULL FK。欠けるのは select の書き間違いだけである。
        gymId: _asInt(entry.value['gym_id'])!,
        gymName: _gymName(entry.value['gyms']),
        menus: sortMenus(menusByMachine[entry.key] ?? const []),
      ),
  ];
}

/// 器具の並び（§4）。ジム名 → 器具名 → id の昇順。
///
/// PostgREST の `order` は DB の照合順序（`lc_collate`）に依存し、環境差が出る。
/// **畳み込みの後に Dart 側で並べ直して決定性を担保する**（TC-FEAT02-09）。
/// 最後に id を見るのは、同じジムに同名の器具があっても順序を揺らさないため。
///
/// ⚠️ W-08 の `sortMachines`（`domain/machine.dart`）とは**別の並び**である。
/// 向こうは「ジム名 → 部位 → 器具名」（FEAT-01 §5.6）。こちらは器具が複数の
/// 種目を持つ前提で FEAT-02 §4 が定める並びに従う。混同を避けるため名前を分けた。
///
/// ⚠️ `String.compareTo` は UTF-16 の符号単位の比較で、日本語の読み順にはならない
/// `[仮]`（§4）。順序が安定していれば要件は満たすと評価する。
List<TrainingMachine> sortFilteredMachines(Iterable<TrainingMachine> machines) {
  final sorted = machines.toList();
  sorted.sort((a, b) {
    final byGym = a.gymName.compareTo(b.gymName);
    if (byGym != 0) return byGym;
    final byName = a.name.compareTo(b.name);
    if (byName != 0) return byName;
    return a.id.compareTo(b.id);
  });
  return sorted;
}

/// 器具の中の種目の並び（§4）。RULE-003 の部位順 → 種目名 → id の昇順。
///
/// 取得順に依存させない。`BodyPart` の宣言順が RULE-003 の並びである。
List<TrainingMenu> sortMenus(Iterable<TrainingMenu> menus) {
  final sorted = menus.toList();
  sorted.sort((a, b) {
    final byPart = a.bodyPart.index.compareTo(b.bodyPart.index);
    if (byPart != 0) return byPart;
    final byName = a.name.compareTo(b.name);
    if (byName != 0) return byName;
    return a.id.compareTo(b.id);
  });
  return sorted;
}

/// 埋め込みの to-one を1行として取り出す。
///
/// PostgREST は to-one を Map で返す。関係の推定によっては List で来るため、
/// W-08 の `gyms` と同じ用心をここでも行う。
Map<String, dynamic>? _asRow(Object? value) {
  if (value is Map<String, dynamic>) return value;
  if (value is List) {
    return value.isEmpty ? null : value.first as Map<String, dynamic>;
  }
  return null;
}

/// 入れ子の `gyms` からジム名を取る。
String _gymName(Object? value) =>
    (_asRow(value)?['name'] as String? ?? '').trim();

/// `bigint` を `int` へ直す。
///
/// PostgreSQL の `bigint` はドライバによって文字列で返ることがある。
/// `domain/machine.dart` にも同じ非公開関数がある。**共有しない。**
/// 既存ファイルへ手を入れずに済ませるための重複である `[仮]`。
int? _asInt(Object? value) {
  if (value == null) return null;
  if (value is int) return value;
  if (value is num) return value.toInt();
  if (value is String) return int.tryParse(value);
  return null;
}
