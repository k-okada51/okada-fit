/// SCR-03（トレーニング記録）が扱う値と、その検証。
///
/// UI にも Supabase にも依存しない。`BuildContext` も `SupabaseClient` も
/// 受け取らない。ここに置いたものは全て単体テストの対象（NFR-QUAL-01）。
///
/// 正本は `FEAT-04_トレーニング記録.md`。列と制約は `01_DB物理設計.md §1.6`。
/// RPC `create_training_session` の定義は同 §3.6。
///
/// **記録するのは実施の有無だけである**（ADR-0008・2026-08-22 再確認）。
/// 回数・重量・実施時間・強度は持たない。列も作らず、引数にも入れない。
///
/// ⚠️ **設計との差**: FEAT-04 §8 は未来日判定を `domain/date_util.dart` へ、
/// 入館記録を `data/gym_visit_repository.dart` へ分けると定める。W-16 では
/// 日付ユーティリティも入館記録も本ファイル1本に置く `[仮]`。
/// 使うのが FEAT-04 だけのうちは分ける利点が無い。他 FEAT が使い始めたら出す。
library;

/// 明細の入力1件（RPC へ渡す前の形）。
///
/// **`order`（実施順）の列は持たない**（ADR-0021）。順序は
/// [buildCreateTrainingSessionParams] へ渡す並びそのものが表す。
/// FEAT-03 の提案結果（W-15）もこの型でそのまま受けられる。
/// `reason` は渡さないし保存もしない。
class TrainingDetailInput {
  const TrainingDetailInput(this.menuId, {this.isDone = false});

  /// `training_session_details.menu_id`（bigint）。本人の `training_menus` の行。
  final int menuId;

  /// 実行済か。**既定は false**（ST-01 `not_done`・§4.1 の T01）。
  final bool isDone;
}

/// 明細の重複を除く（§4.3 `normalizeTrainingDetails`）。
///
/// `uq_tsd_session_menu`（`training_session_details(session_id, menu_id)`）と
/// 整合させる。重複したまま RPC へ渡すと `23505` になり、セッション行ごと巻き戻る。
///
/// 並びは最初に出た順を保つ。実施順を配列の並びで表すため、ここで並べ替えない。
///
/// ⚠️ **設計との差**: §4.3 は重複時に例外を投げると書くが、ここは黙って除く。
/// **入力の検証エラーを例外にしない**（W-05 の約束）。利用者への通知が要る場面は
/// [validateSelectedMenus] が担う。`machine.dart` の `normalizeMenuIds` と同じ扱い。
List<TrainingDetailInput> normalizeTrainingDetails(
  Iterable<TrainingDetailInput> details,
) {
  final seen = <int>{};
  final result = <TrainingDetailInput>[];
  for (final detail in details) {
    // `Set.add` は初出のとき true を返す。2件目以降は捨てる。
    if (seen.add(detail.menuId)) result.add(detail);
  }
  return result;
}

/// `create_training_session`（T01）の引数を作る。
///
/// **キーは関数の引数名そのまま**（`p_` 接頭辞・snake_case・`06_DB設計規約.md §5`）。
/// 1文字でも違うと PostgREST が関数を見つけられず `PGRST202` になる。
/// 適用済みの実物は
/// `create_training_session(p_performed_date date, p_menu_ids bigint[], p_is_done boolean[])`。
///
/// **`p_menu_ids` と `p_is_done` は同順・同要素数**である。関数本体が
/// `unnest(p_menu_ids, p_is_done)` で1行ずつ組にするため、ずれると別の種目に
/// 実行済が付く。2つの配列を同じ [normalizeTrainingDetails] の結果から作ることで、
/// ずれが起きない形にしてある。
///
/// `p_user_id` は無い。本人は RPC 内の `auth.uid()` が解決する（ADR-0005）。
/// 回数・重量の引数も無い（ADR-0008）。
Map<String, dynamic> buildCreateTrainingSessionParams({
  required DateTime performedDate,
  required Iterable<TrainingDetailInput> details,
}) {
  final normalized = normalizeTrainingDetails(details);
  return {
    'p_performed_date': formatDateOnly(performedDate),
    'p_menu_ids': normalized.map((detail) => detail.menuId).toList(),
    'p_is_done': normalized.map((detail) => detail.isDone).toList(),
  };
}

/// `gym_visits` への INSERT 値（§3.3）。
///
/// **キーは DB の列名そのまま**（snake_case）。
///
/// ⚠️ **設計との差**: §3.3 の例は `user_id` を送らないが、適用済みの DDL では
/// `gym_visits.user_id` が NOT NULL で既定値を持たない
/// （`20260808045256_create_history_tables.sql`）。送らないと `23502` になるため
/// [userId] を受け取ってここで入れる。`machine.dart` の `buildMenuInsert` と同じ。
/// **他人の行は作れない。** RLS の `WITH CHECK (user_id = auth.uid())` が弾く。
///
/// [visitTime] は任意。空欄は空文字ではなく `null` を入れる（`visit_time` は null 許容）。
Map<String, dynamic> buildGymVisitInsert({
  required String userId,
  required int gymId,
  required DateTime visitDate,
  String? visitTime,
}) {
  final time = (visitTime ?? '').trim();
  return {
    'user_id': userId,
    'gym_id': gymId,
    'visit_date': formatDateOnly(visitDate),
    'visit_time': time.isEmpty ? null : time,
  };
}

/// `DateTime` を ISO 8601 の日付（`YYYY-MM-DD`）にする。
///
/// **`toIso8601String()` を使わない。** 時刻が付き、UTC の `DateTime` だと
/// 日付そのものがずれる。日付は端末のローカル日付で解決する（ADR-0014）。
String formatDateOnly(DateTime date) =>
    '${date.year.toString().padLeft(4, '0')}-'
    '${date.month.toString().padLeft(2, '0')}-'
    '${date.day.toString().padLeft(2, '0')}';

/// `HH:MM` の文字列にする。`visit_time` へそのまま渡せる形。
String formatTimeOfDay(int hour, int minute) =>
    '${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}';

/// `date` 列の文字列を `DateTime` にする。時刻は持たない。
///
/// 読めない値は `null`。DB の型が `date` である限り起きない。
DateTime? parseDateOnly(String? raw) {
  if (raw == null) return null;
  // `2026-08-22` も `2026-08-22T00:00:00` も同じ日付として読む。
  final parsed = DateTime.tryParse(raw);
  if (parsed == null) return null;
  return DateTime(parsed.year, parsed.month, parsed.day);
}

/// 未来日か（§4.3 `isFutureDate`）。
///
/// **時刻を見ない。** 年月日だけで比べる。同じ日は未来ではない。
/// 基準は端末のローカル日付（ADR-0014）。サーバの `CURRENT_DATE` は使わない。
bool isFutureDate(DateTime target, DateTime today) {
  final targetDay = DateTime(target.year, target.month, target.day);
  final baseDay = DateTime(today.year, today.month, today.day);
  return targetDay.isAfter(baseDay);
}

/// 実施日の検証（ERR-TRAINING-001）。エラー文言 or `null` を返す。
///
/// `BuildContext` を取らないため、テストから直接呼べる。
String? validatePerformedDate(DateTime? performedDate, DateTime today) {
  if (performedDate == null) return '実施日を選んでください。';
  if (isFutureDate(performedDate, today)) return '実施日に未来の日付は選べません。';
  return null;
}

/// 種目の選択の検証（ERR-TRAINING-002・§3.4）。
///
/// 0件のまま RPC を呼ぶと、明細0件のセッションが作られる。
/// **そこへ到達させない。** 画面は [記録する] を非活性にし、ここで文言を出す。
///
/// 重複は `uq_tsd_session_menu` 違反（`23505`）になる。選択UIは `Set<int>` の
/// ため構造的に起きないが、手組みの呼び出しに対する防御として残す。
///
/// ⚠️ **設計との差**: §3.4 は「違反時 ERR-TRAINING-002」とだけ書く。ここは文言 or
/// `null` を返す。**入力の検証エラーを例外にしない**（W-05 の約束・`machine.dart` と同じ）。
String? validateSelectedMenus(Iterable<int> menuIds) {
  final list = menuIds.toList();
  if (list.isEmpty) return '種目を1件以上選んでください。';
  // `p_menu_ids` の要素は正の整数（§3.4）。
  if (list.any((id) => id <= 0)) return '種目の指定が正しくありません。';
  if (list.toSet().length < list.length) return '同じ種目は1回だけ選べます。';
  return null;
}

/// 許可された遷移かの検証（ERR-TRAINING-006・§4.1）。
///
/// 許可遷移は T02（ST-01 → ST-02）だけである。**逆遷移は実装しない**（§10 #3 が未決）。
/// `Checkbox` は取り消しを期待させる形をしているため、要求が来たときの文言をここに置く。
String? validateDoneTransition({required bool nextIsDone}) {
  if (!nextIsDone) return 'チェックの取り消しには対応していません。';
  return null;
}

/// 入館日の検証（ERR-TRAINING-008・§3.3）。
String? validateVisitDate(DateTime? visitDate, DateTime today) {
  if (visitDate == null) return '入館日を選んでください。';
  if (isFutureDate(visitDate, today)) return '入館日に未来の日付は選べません。';
  return null;
}

/// `HH:MM` または `HH:MM:SS`（§3.3）。24時以降・60分以降は通さない。
final _visitTimePattern = RegExp(r'^([01]\d|2[0-3]):[0-5]\d(:[0-5]\d)?$');

/// 入館時刻の検証（ERR-TRAINING-008・§3.3）。
///
/// **空欄は正常。** `visit_time` は任意で null を許す。
String? validateVisitTime(String? input) {
  final text = (input ?? '').trim();
  if (text.isEmpty) return null;
  if (!_visitTimePattern.hasMatch(text)) return '入館時刻の形式が正しくありません。';
  return null;
}

/// 実行済トグル（T02）の結果（§4.2・§4.3 `resolveToggleResult`）。
enum TrainingToggleResult {
  /// 返却1行。ST-01 → ST-02 が成立した。
  transitioned,

  /// 返却0行だが行はある。**既に ST-02＝冪等成功**。二重反映は起きていない。
  alreadyDone,

  /// 返却0行で行も無い。他人の行（RLS で不可視）を含む。ERR-TRAINING-004。
  notFound;

  /// 利用者にとって成功か。[notFound] だけが失敗である。
  bool get isSuccess => this != TrainingToggleResult.notFound;
}

/// 条件付き update の返却行数から結果を決める（§4.2 の3分岐）。
///
/// 副作用を持たない。判定だけをここへ寄せ、通信は
/// `data/training_repository.dart` に置く。
///
/// | [updatedRowCount] | [exists] | 結果 |
/// |---|---|---|
/// | 1以上 | — | [TrainingToggleResult.transitioned] |
/// | 0 | true | [TrainingToggleResult.alreadyDone] |
/// | 0 | false | [TrainingToggleResult.notFound] |
///
/// [exists] は「`is_done` の条件を外した select に行があったか」である。
/// 行数が1以上のときは存在確認そのものが不要なので、[exists] を見ない。
TrainingToggleResult resolveToggleResult({
  required int updatedRowCount,
  required bool exists,
}) {
  if (updatedRowCount > 0) return TrainingToggleResult.transitioned;
  if (exists) return TrainingToggleResult.alreadyDone;
  return TrainingToggleResult.notFound;
}

/// `training_session_details` の1行。種目名を同梱した形（埋め込み select）。
///
/// **回数・重量の列は無い**（ADR-0008）。持っているのは実施有無だけである。
class TrainingSessionDetail {
  const TrainingSessionDetail({
    required this.id,
    required this.menuId,
    required this.isDone,
    required this.menuName,
  });

  /// PostgREST が返す1行から作る。
  ///
  /// 種目名は入れ子 `training_menus` から取る。埋め込みが無ければ空文字になる。
  factory TrainingSessionDetail.fromJson(Map<String, dynamic> json) {
    final menu = json['training_menus'];
    // 埋め込みは to-one なら Map で返る。念のため List で来た場合も先頭を見る。
    final menuRow = menu is List
        ? (menu.isEmpty ? null : menu.first as Map<String, dynamic>)
        : menu as Map<String, dynamic>?;
    return TrainingSessionDetail(
      id: _asInt(json['id']) ?? 0,
      menuId: _asInt(json['menu_id']) ?? 0,
      // `is_done` は NOT NULL DEFAULT false。null は来ない。
      isDone: json['is_done'] == true,
      menuName: (menuRow?['name'] as String? ?? '').trim(),
    );
  }

  /// `training_session_details.id`（bigint）。T02 の update 条件になる。
  final int id;

  /// 種目の id。
  final int menuId;

  /// 実行済か。ST-01 `not_done` / ST-02 `done`。**本PJで唯一の永続状態**である。
  final bool isDone;

  /// 種目名（入れ子 `training_menus.name` の平坦化）。
  final String menuName;

  /// 実行済にしたコピーを作る。楽観更新（§7）で使う。
  TrainingSessionDetail markedDone() => TrainingSessionDetail(
    id: id,
    menuId: menuId,
    isDone: true,
    menuName: menuName,
  );
}

/// `training_sessions` の1行。明細を同梱した形（埋め込み select）。
class TrainingSession {
  const TrainingSession({
    required this.id,
    required this.performedDate,
    required this.details,
  });

  /// PostgREST が返す1行から作る。
  factory TrainingSession.fromJson(Map<String, dynamic> json) {
    final rows = json['training_session_details'] as List<dynamic>? ?? const [];
    return TrainingSession(
      id: _asInt(json['id']) ?? 0,
      // `performed_date` は NOT NULL。読めない値は epoch に倒さず例外にしたいが、
      // ここで throw すると一覧全体が落ちる。日付だけ既定値に倒す。
      performedDate:
          parseDateOnly(json['performed_date'] as String?) ?? DateTime(1970),
      details: rows
          .map((row) => TrainingSessionDetail.fromJson(row as Map<String, dynamic>))
          .toList(),
    );
  }

  /// `training_sessions.id`（bigint）。
  final int id;

  /// 実施日。時刻は持たない。
  final DateTime performedDate;

  /// 明細。**1件以上**である（種目0件では記録させない）。
  final List<TrainingSessionDetail> details;

  /// 実行済の件数。FEAT-05 のヒートマップは1件以上 true の日を塗る。
  int get doneCount => details.where((detail) => detail.isDone).length;

  /// 明細を1件差し替えたコピーを作る。楽観更新（§7）で使う。
  TrainingSession withDetail(TrainingSessionDetail replaced) => TrainingSession(
    id: id,
    performedDate: performedDate,
    details: [
      for (final detail in details)
        detail.id == replaced.id ? replaced : detail,
    ],
  );
}

/// この日に既に登録済みの `menu_id`。
///
/// 同じ種目を同じセッションへ2回入れると `uq_tsd_session_menu` に当たる。
/// 選択リストから外すために使う。
///
/// ⚠️ 同一日に複数セッションを作れる（§10 #2 が未決）。同じ日の別セッションへなら
/// 同じ種目を入れられてしまう。ここでは**同日の全セッション**を見て候補から外す `[仮]`。
Set<int> recordedMenuIds(Iterable<TrainingSession> sessions) => {
  for (final session in sessions)
    for (final detail in session.details) detail.menuId,
};

/// `bigint` を `int` へ直す。
///
/// PostgreSQL の `bigint` はドライバによって文字列で返ることがある。
/// どちらで来ても同じ結果になるようにしておく（`machine.dart` の `_asInt` と同じ）。
int? _asInt(Object? value) {
  if (value == null) return null;
  if (value is int) return value;
  if (value is num) return value.toInt();
  if (value is String) return int.tryParse(value);
  return null;
}
