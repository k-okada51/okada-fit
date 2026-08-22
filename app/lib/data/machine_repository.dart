import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/supabase.dart';
import '../domain/machine.dart';
import 'error_mapper.dart';

/// 更新・削除の対象が見つからない（ERR-MACHINE-006）。
///
/// **例外では検知できない。** PostgREST も RPC も対象が無いことを例外にせず、
/// 空配列・`null` を返す（FEAT-01 §3.2 の「重要な挙動差」）。
/// 戻り値を見て判定し、画面はこの文言を出す。
const errMachineNotFound = AppFailure(
  code: 'ERR-MACHINE-006',
  message: '対象の器具が見つかりませんでした。一覧を読み直してください。',
  retryable: false,
);

/// 器具・種目・ジムの読み書き（FEAT-01）。
///
/// **器具の書き込みだけ RPC。** `training_machines` と `machine_menus` の
/// 2テーブルに書くため、原子性を関数の中に閉じる（§2.1）。
/// 参照と、種目・ジムの登録は PostgREST 直接（§3.1）。
///
/// **`machine_menus` を直接書かない**（§8 の判断）。INSERT を2回並べると
/// 途中で失敗したときに「種目が1件も紐づかない器具」が残る。
///
/// UI を知らない。`BuildContext` を受け取らない。
/// 例外は写像せずそのまま上へ投げる。利用者向け文言への変換は
/// `data/error_mapper.dart`（W-05）の担当で、呼ぶのは画面側。
/// `profile_repository.dart` と同じ約束にしてある。
class MachineRepository {
  /// [client] を渡さない場合は初期化済みの共有クライアントを使う。
  /// テストから差し替えられるよう引数に開けてある。
  MachineRepository({SupabaseClient? client}) : _client = client ?? supabase;

  final SupabaseClient _client;

  /// 器具1件の埋め込み select（§3.2 の EMB）。
  ///
  /// **器具は部位列を持たない。** 部位は `machine_menus` → `training_menus` を
  /// 辿ってしか取れない（3ホップ・§5.3）。
  /// 経路上の全段に `!inner` が要る。外部結合のままだと親行が残る。
  static const _machineColumns =
      'id, name, created_at, gym_id, gyms!inner ( name ), '
      'machine_menus!inner ( menu_id, training_menus!inner ( name, body_part ) )';

  /// 種目の列（C-05）。
  static const _menuColumns = 'id, name, body_part, how_to';

  /// ジムの列（C-09）。
  static const _gymColumns = 'id, name';

  /// ジムの一覧（C-09）。
  ///
  /// `gyms` は共通マスタで、RLS は `TO authenticated USING (true)`（ADR-0005）。
  /// **`user_id` を条件に書かない。** そもそも所有者列が無い。
  Future<List<Gym>> fetchGyms() async {
    final rows = await _client
        .from('gyms')
        .select(_gymColumns)
        // postgrest-dart の `order` は既定が降順。昇順は明示する。
        .order('name', ascending: true);
    return rows.map(Gym.fromJson).toList();
  }

  /// ジムを1件登録する（C-10）。
  ///
  /// 器具登録の画面を離れずに作るための入口である（§7・2026-08-22 確定）。
  /// **RPC には含めない。** 器具の登録とは別トランザクションになる。
  Future<Gym> createGym(String name) async {
    final row = await _client
        .from('gyms')
        .insert(buildGymInsert(name))
        .select(_gymColumns)
        .single();
    return Gym.fromJson(row);
  }

  /// 種目の一覧（C-05）。
  ///
  /// `training_menus` は本人のみ（RLS `user_id = auth.uid()`）。
  /// **ここに `user_id` の条件を書かない。** RLS が絞る（ADR-0005）。
  Future<List<TrainingMenu>> fetchMenus() async {
    final rows = await _client
        .from('training_menus')
        .select(_menuColumns)
        .order('body_part', ascending: true)
        .order('name', ascending: true);
    return rows.map(TrainingMenu.fromJson).toList();
  }

  /// 種目を1件登録する（C-06）。
  ///
  /// ジムと同じく器具登録の画面のダイアログから呼ぶ（§7）。
  ///
  /// ⚠️ **受容したリスク**（2026-08-22 確定・§10 #1）:
  /// 種目を作った直後に器具登録が失敗すると、**種目だけが残る**。
  /// 2呼び出し＝2トランザクションだからである。
  /// 実害は小さい。残った種目は次回の登録でそのまま選べる。孤児にはならない。
  ///
  /// [howTo] は空でよい（ADR-0021）。空欄は `null` で入る。
  Future<TrainingMenu> createMenu({
    required String name,
    required BodyPart bodyPart,
    String? howTo,
  }) async {
    // `training_menus.user_id` は NOT NULL で既定値が無い（設計 §3.3 との差は
    // `domain/machine.dart` の [buildMenuInsert] に記した）。
    final userId = _client.auth.currentUser?.id;
    if (userId == null) {
      // 未サインインならこの画面に到達しない。来たら実装の誤りである。
      throw StateError('サインインしていません');
    }

    final row = await _client
        .from('training_menus')
        .insert(
          buildMenuInsert(
            userId: userId,
            name: name,
            bodyPart: bodyPart,
            howTo: howTo,
          ),
        )
        .select(_menuColumns)
        .single();
    return TrainingMenu.fromJson(row);
  }

  /// 器具の一覧（C-02）。
  ///
  /// [gymId] はジムでの絞り込み。親テーブルの列なので `!inner` は要らない。
  /// [bodyPart] は部位での絞り込み（RULE-004）。埋め込み列を条件にする。
  /// 部位で絞ると、器具に紐づく種目のうち**一致した分だけ**が配列に残る。
  ///
  /// 並びは Dart 側で行う（§5.6）。PostgREST の `order` では
  /// 「ジム名 → 部位 → 器具名」を表現できない。
  Future<List<TrainingMachine>> fetchMachines({
    int? gymId,
    BodyPart? bodyPart,
  }) async {
    var query = _client.from('training_machines').select(_machineColumns);
    if (gymId != null) {
      query = query.eq('gym_id', gymId);
    }
    if (bodyPart != null) {
      query = query.eq('machine_menus.training_menus.body_part', bodyPart.label);
    }
    final rows = await query;
    return sortMachines(rows.map(TrainingMachine.fromJson));
  }

  /// 器具を1件読み直す（C-11）。登録・更新の直後に表示用の形で取る。
  Future<TrainingMachine> fetchMachine(int machineId) async {
    final row = await _client
        .from('training_machines')
        .select(_machineColumns)
        .eq('id', machineId)
        .single();
    return TrainingMachine.fromJson(row);
  }

  /// 器具を登録する（C-01）。RPC 1回＝1トランザクション。
  ///
  /// [menuIds] は1件以上。空だと関数が `ERR-MACHINE-003` を投げる。
  /// 呼ぶ前に `validateMenuSelection` で止めること。
  ///
  /// 戻りは表示用に読み直した器具1件（§2.2）。RPC が返すのは `machine_id` だけで、
  /// 一覧と同じ形にするには埋め込み select が要る。
  Future<TrainingMachine> createMachine({
    required int gymId,
    required String name,
    required Iterable<int> menuIds,
  }) async {
    final result = await _client.rpc<dynamic>(
      'create_machine',
      params: buildCreateMachineParams(
        gymId: gymId,
        name: name,
        menuIds: menuIds,
      ),
    );
    final machineId = _asMachineId(result);
    if (machineId == null) {
      // `create_machine` は必ず id を返す。null は関数定義の食い違いである。
      throw StateError('create_machine が machine_id を返しませんでした');
    }
    return fetchMachine(machineId);
  }

  /// 器具を更新する（C-03）。紐づけは**全置換**である（§5.7）。
  ///
  /// 残したい種目も [menuIds] に入れる。差分は計算しない。
  ///
  /// **対象が無いと `null` を返す。例外ではない。**
  /// RLS で不可視な場合も同じ。呼び出し側は [errMachineNotFound] を出す。
  Future<TrainingMachine?> updateMachine({
    required int machineId,
    required int gymId,
    required String name,
    required Iterable<int> menuIds,
  }) async {
    final result = await _client.rpc<dynamic>(
      'update_machine',
      params: buildUpdateMachineParams(
        machineId: machineId,
        gymId: gymId,
        name: name,
        menuIds: menuIds,
      ),
    );
    final updatedId = _asMachineId(result);
    if (updatedId == null) return null;
    return fetchMachine(updatedId);
  }

  /// 器具を削除する（C-04）。`machine_menus` の子行は FK の CASCADE で消える。
  ///
  /// **対象が無いと `false` を返す。例外ではない**（RPC の戻りが `null`）。
  /// 判定を書き忘れると「消えたように見えて消えていない」不具合になる（§6.1）。
  Future<bool> deleteMachine(int machineId) async {
    final result = await _client.rpc<dynamic>(
      'delete_machine',
      params: buildDeleteMachineParams(machineId),
    );
    return _asMachineId(result) != null;
  }
}

/// RPC が返す `bigint` を `int` にする。
///
/// `null` は「対象が無い」を意味する（§3.2）。0件を例外にしない挙動のため、
/// ここが唯一の判定点になる。
int? _asMachineId(Object? value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  if (value is String) return int.tryParse(value);
  return null;
}
