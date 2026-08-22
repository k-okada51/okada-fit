import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/supabase.dart';
import '../domain/training_session.dart';
import 'error_mapper.dart';

/// 対象の明細・セッションが見つからない（ERR-TRAINING-004）。
///
/// **例外では検知できない。** PostgREST は対象が無いことを例外にせず空配列を返す
/// （FEAT-04 §4.2）。戻り値を見て判定し、画面はこの文言を出す。
///
/// 他人の行（RLS で不可視）も同じ扱いにする。存在の有無を漏らさないためである。
const errTrainingNotFound = AppFailure(
  code: 'ERR-TRAINING-004',
  message: '対象の記録が見つかりませんでした。画面を読み直してください。',
  retryable: false,
);

/// 許可されていない遷移を要求した（ERR-TRAINING-006）。
///
/// ST-02 → ST-01（チェックの取り消し）は許可遷移に無い（§4.1・§10 #3 が未決）。
const errTrainingReverseTransition = AppFailure(
  code: 'ERR-TRAINING-006',
  message: 'チェックの取り消しには対応していません。',
  retryable: false,
);

/// トレーニング記録と入館記録の読み書き（FEAT-04）。
///
/// **操作は3つで、方式が3つとも違う。**
///
/// | 操作 | 遷移 | 方式 |
/// |---|---|---|
/// | セッション＋明細の登録 | T01 | RPC `create_training_session` |
/// | 実行済のトグル | T02 | PostgREST の条件付き update（状態ガードつき） |
/// | 入館記録 | なし | PostgREST の insert（`gym_visits`） |
///
/// 登録だけ RPC なのは、`training_sessions` と `training_session_details` の
/// 2テーブルに書くためである。PostgREST はリクエストをまたぐトランザクションを
/// 張れない。原子性を関数の中に閉じる（§5.1・ADR-0010）。
///
/// 入館記録は**別トランザクション**である（§2.4）。片方の失敗が他方を巻き戻さない。
///
/// **種目・ジムの一覧はここに置かない。** `MachineRepository`（W-08）が持っている
/// ものをそのまま使う。同じ SELECT を2か所に書くと、片方だけ直したときにずれる。
///
/// UI を知らない。`BuildContext` を受け取らない。
/// 例外は写像せずそのまま上へ投げる。利用者向け文言への変換は
/// `data/error_mapper.dart`（W-05）の担当で、呼ぶのは画面側。
class TrainingRepository {
  /// [client] を渡さない場合は初期化済みの共有クライアントを使う。
  /// テストから差し替えられるよう引数に開けてある。
  TrainingRepository({SupabaseClient? client}) : _client = client ?? supabase;

  final SupabaseClient _client;

  /// セッション1件の埋め込み select。
  ///
  /// 明細は `uq_tsd_session_menu` の先頭列が `session_id` のため、専用INDEXなしで
  /// 取れる（§5.3）。種目名はさらに1段たどる。
  ///
  /// **回数・重量の列は取らない。そもそも無い**（ADR-0008）。
  static const _sessionColumns =
      'id, performed_date, '
      'training_session_details ( id, menu_id, is_done, training_menus ( name ) )';

  /// 指定日のセッションを読む。
  ///
  /// **`user_id` を条件に書かない。** RLS が本人行に絞る（ADR-0005）。
  ///
  /// ⚠️ 戻りが `List` なのは、同一日に複数セッションを作れるためである
  /// （日付の UNIQUE 制約が無い・§10 #2 が未決）。1件に決め打つと、2件目ができた
  /// ときに黙って片方が消えたように見える。
  Future<List<TrainingSession>> fetchSessions(DateTime performedDate) async {
    final rows = await _client
        .from('training_sessions')
        .select(_sessionColumns)
        .eq('performed_date', formatDateOnly(performedDate))
        // postgrest-dart の `order` は既定が降順。昇順は明示する。
        .order('id', ascending: true);
    return rows.map(TrainingSession.fromJson).toList();
  }

  /// セッション1件を読み直す。登録・トグルの直後に表示用の形で取る。
  Future<TrainingSession> fetchSession(int sessionId) async {
    final row = await _client
        .from('training_sessions')
        .select(_sessionColumns)
        .eq('id', sessionId)
        .single();
    return TrainingSession.fromJson(row);
  }

  /// セッションと明細を登録する（T01）。RPC 1回＝1トランザクション。
  ///
  /// [details] は1件以上・重複なし。呼ぶ前に `validateSelectedMenus` で止めること。
  /// 重複は [buildCreateTrainingSessionParams] が除くが、0件は除けない。
  ///
  /// **並び順が実施順である**（ADR-0021）。列としては持たない。
  /// 本人でない `menu_id` が混じると関数が `ERR-TRAINING-003` を投げ、全ロールバックする。
  ///
  /// 戻りは表示用に読み直したセッション1件。RPC が返すのは `session_id` だけで、
  /// 明細と種目名を出すには埋め込み select が要る。
  Future<TrainingSession> createSession({
    required DateTime performedDate,
    required Iterable<TrainingDetailInput> details,
  }) async {
    final result = await _client.rpc<dynamic>(
      'create_training_session',
      params: buildCreateTrainingSessionParams(
        performedDate: performedDate,
        details: details,
      ),
    );
    final sessionId = _asId(result);
    if (sessionId == null) {
      // `create_training_session` は必ず id を返す。null は関数定義の食い違いである。
      throw StateError('create_training_session が session_id を返しませんでした');
    }
    return fetchSession(sessionId);
  }

  /// 明細を実行済にする（T02・ST-01 → ST-02）。
  ///
  /// **`.eq('is_done', false)` が状態ガードである**（§4.2）。WHERE に埋めることで、
  /// 遷移の判定と更新が同じ1文＝同じ行ロックの中で起きる。事前 select で判定すると、
  /// 判定と更新の間に割り込む余地が残る。
  ///
  /// **`is_done = false` への逆遷移は用意しない**（§4.1・§10 #3 が未決）。
  /// 引数で向きを受け取らないのは、呼び間違いを型で防ぐためである。
  ///
  /// 判定は返却行数で行う。0行のときだけ、`is_done` の条件を外した select を
  /// 1回だけ足して「既に ST-02」と「行が無い」を切り分ける。
  Future<TrainingToggleResult> markDone({
    required int detailId,
    required int sessionId,
  }) async {
    final updated = await _client
        .from('training_session_details')
        .update({'is_done': true})
        .eq('id', detailId)
        .eq('session_id', sessionId)
        // ← 状態ガード。これが無いと ST-02 の行にも update が当たり、
        //    二重反映かどうかを返却行数で見分けられなくなる。
        .eq('is_done', false)
        .select('id, is_done');

    if (updated.isNotEmpty) {
      return resolveToggleResult(updatedRowCount: updated.length, exists: true);
    }

    // 返却0行。**ここで諦めない。** 冪等成功（既に ST-02）と不在の区別が付かない。
    final existing = await _client
        .from('training_session_details')
        .select('id, is_done')
        .eq('id', detailId)
        .eq('session_id', sessionId);
    return resolveToggleResult(
      updatedRowCount: 0,
      exists: existing.isNotEmpty,
    );
  }

  /// 入館記録を1件作る（`gym_visits` の insert）。
  ///
  /// **トレーニング記録とは別トランザクションである**（§2.4）。
  /// ここが失敗しても、直前に作ったセッションは巻き戻らない。逆も同じ。
  /// FK も相互参照も無い。
  ///
  /// [visitTime] は任意。空欄なら `null` が入る。
  /// `gyms` に無い [gymId] は FK 違反（`23503`）になる（ERR-TRAINING-007）。
  Future<void> addGymVisit({
    required int gymId,
    required DateTime visitDate,
    String? visitTime,
  }) async {
    // `gym_visits.user_id` は NOT NULL で既定値が無い（設計 §3.3 との差は
    // `domain/training_session.dart` の [buildGymVisitInsert] に記した）。
    final userId = _client.auth.currentUser?.id;
    if (userId == null) {
      // 未サインインならこの画面に到達しない。来たら実装の誤りである。
      throw StateError('サインインしていません');
    }

    await _client
        .from('gym_visits')
        .insert(
          buildGymVisitInsert(
            userId: userId,
            gymId: gymId,
            visitDate: visitDate,
            visitTime: visitTime,
          ),
        );
  }
}

/// RPC が返す `bigint` を `int` にする。
int? _asId(Object? value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  if (value is String) return int.tryParse(value);
  return null;
}
