import 'package:flutter_test/flutter_test.dart';

import 'package:okada_fit/domain/training_session.dart';

/// トレーニング記録（W-16・FEAT-04）の単体テスト。
///
/// ネットワークを使わない。Supabase の初期化もしない。
/// 見るのは `domain/training_session.dart` の純関数だけである。
///
/// 確かめたいのは3点。
/// 1. **RPC の2配列がずれていないか。** `p_menu_ids` と `p_is_done` は
///    関数本体の `unnest(p_menu_ids, p_is_done)` で1行ずつ組にされる。
///    順序か件数がずれると、別の種目に実行済が付く。
/// 2. **DB の制約と同じ規則を、送信前に Dart 側でも弾けているか。**
///    `uq_tsd_session_menu` も未来日も、DB へ到達させない。
/// 3. **状態ガードの判定が正しいか**（§4.2）。返却行数の 1／0 と存在確認の
///    組み合わせで、遷移成立・冪等成功・不在の3つに分かれる。
///
/// **回数・重量は出てこない。** そもそも列も引数も無い（ADR-0008）。
void main() {
  group('1. p_menu_ids と p_is_done が同順・同要素数（TC-FEAT04-01）', () {
    test('入力の並びのまま、2配列が同じ長さで作られる', () {
      final params = buildCreateTrainingSessionParams(
        performedDate: DateTime(2026, 8, 22),
        details: const [
          TrainingDetailInput(11),
          TrainingDetailInput(12, isDone: true),
          TrainingDetailInput(13),
        ],
      );

      final menuIds = params['p_menu_ids'] as List<dynamic>;
      final isDone = params['p_is_done'] as List<dynamic>;

      // 件数が同じ。ずれると unnest が NULL で埋め、意図しない行が入る。
      expect(menuIds.length, isDone.length);
      expect(menuIds.length, 3);

      // 並びも同じ。**実施順は配列の並びで表す**（ADR-0021）。
      expect(menuIds, const [11, 12, 13]);
      expect(isDone, const [false, true, false]);
    });

    test('既定は false（ST-01 で登録する・§4.1 の T01）', () {
      final params = buildCreateTrainingSessionParams(
        performedDate: DateTime(2026, 8, 22),
        details: const [TrainingDetailInput(11), TrainingDetailInput(12)],
      );
      expect(params['p_is_done'], const [false, false]);
    });

    test('重複を除いても2配列は同じ長さを保つ', () {
      // 除いた側だけ短くなると、そこから先の組がまるごとずれる。
      final params = buildCreateTrainingSessionParams(
        performedDate: DateTime(2026, 8, 22),
        details: const [
          TrainingDetailInput(11),
          TrainingDetailInput(12, isDone: true),
          TrainingDetailInput(11, isDone: true),
          TrainingDetailInput(13),
        ],
      );
      expect(params['p_menu_ids'], const [11, 12, 13]);
      expect(params['p_is_done'], const [false, true, false]);
    });
  });

  group('2. menu_id の重複を除く（uq_tsd_session_menu・TC-FEAT04-04）', () {
    test('重複を除く。残るのは最初に出たほう', () {
      // 重複したまま渡すと `23505` になり、セッション行ごと巻き戻る。
      final normalized = normalizeTrainingDetails(const [
        TrainingDetailInput(11),
        TrainingDetailInput(12, isDone: true),
        // 2件目の 11 は捨てられる。isDone も最初のほう（false）が残る。
        TrainingDetailInput(11, isDone: true),
        TrainingDetailInput(12),
      ]);

      expect(normalized.map((detail) => detail.menuId).toList(), const [11, 12]);
      expect(normalized.map((detail) => detail.isDone).toList(), const [
        false,
        true,
      ]);
    });

    test('重複が無ければ並びも件数もそのまま', () {
      final normalized = normalizeTrainingDetails(const [
        TrainingDetailInput(3),
        TrainingDetailInput(1),
        TrainingDetailInput(2),
      ]);
      // 並べ替えない。並びが実施順であるため（ADR-0021）。
      expect(normalized.map((detail) => detail.menuId).toList(), const [3, 1, 2]);
    });

    test('検証側も重複を弾く（手組みの呼び出しに対する防御）', () {
      expect(validateSelectedMenus(const [11, 11]), isNotNull);
      expect(validateSelectedMenus(const [11, 12, 11]), isNotNull);

      // 画面の選択は `Set<int>` のため、UI からは構造的に起きない。
      final selected = <int>{}..addAll(const [11, 12, 11]);
      expect(validateSelectedMenus(selected), isNull);
    });
  });

  group('3. 種目0件を弾く（ERR-TRAINING-002・TC-FEAT04-03）', () {
    test('0件は通さない。1件以上なら通る', () {
      // 0件のまま RPC を呼ぶと、明細0件のセッションが残る。そこへ到達させない。
      expect(validateSelectedMenus(const <int>[]), isNotNull);
      expect(validateSelectedMenus(const <int>{}), isNotNull);

      expect(validateSelectedMenus(const [11]), isNull);
      // 件数の上限は設けない。
      expect(validateSelectedMenus(const [11, 12, 13]), isNull);
    });

    test('要素は正の整数（§3.4）', () {
      expect(validateSelectedMenus(const [0]), isNotNull);
      expect(validateSelectedMenus(const [-1]), isNotNull);
      expect(validateSelectedMenus(const [11, 0]), isNotNull);
    });
  });

  group('4. 未来日を弾く（ERR-TRAINING-001・TC-FEAT04-06）', () {
    final today = DateTime(2026, 8, 22);

    test('当日は通る。翌日以降は弾く（§3.4「未来日不可」）', () {
      // 規則は「未来日不可」。**当日は未来ではない**ので通す。
      expect(validatePerformedDate(DateTime(2026, 8, 22), today), isNull);
      expect(validatePerformedDate(DateTime(2026, 8, 21), today), isNull);
      expect(validatePerformedDate(DateTime(2025, 12, 31), today), isNull);

      expect(validatePerformedDate(DateTime(2026, 8, 23), today), isNotNull);
      expect(validatePerformedDate(DateTime(2026, 9, 1), today), isNotNull);
      expect(validatePerformedDate(DateTime(2027, 1, 1), today), isNotNull);

      // 未選択も弾く（必須・§3.4）。
      expect(validatePerformedDate(null, today), isNotNull);
    });

    test('時刻は見ない。同じ日の 23:59 は未来ではない', () {
      // 端末のローカル日付だけで比べる（ADR-0014）。
      expect(isFutureDate(DateTime(2026, 8, 22, 23, 59), today), isFalse);
      expect(isFutureDate(DateTime(2026, 8, 22), DateTime(2026, 8, 22, 23, 59)),
          isFalse);
      // 日が変われば未来。
      expect(isFutureDate(DateTime(2026, 8, 23, 0, 0), today), isTrue);
    });

    test('日付は YYYY-MM-DD で送る（toIso8601String を使わない）', () {
      // 時刻が付くと date 列への流し込みで解釈が揺れる。0埋めも要る。
      expect(formatDateOnly(DateTime(2026, 8, 22)), '2026-08-22');
      expect(formatDateOnly(DateTime(2026, 1, 5)), '2026-01-05');
      expect(formatDateOnly(DateTime(2026, 12, 31, 23, 59)), '2026-12-31');
    });
  });

  group('5. RPC の引数キーが p_ 接頭辞で正しい（TC-FEAT04-01）', () {
    test('create_training_session の3引数だけを作る', () {
      final params = buildCreateTrainingSessionParams(
        performedDate: DateTime(2026, 8, 22),
        details: const [TrainingDetailInput(11)],
      );

      // 適用済みの実物は
      // create_training_session(p_performed_date date, p_menu_ids bigint[], p_is_done boolean[])。
      // キーが1文字でも違うと PostgREST が関数を見つけられない（PGRST202）。
      expect(params.keys.toSet(), {
        'p_performed_date',
        'p_menu_ids',
        'p_is_done',
      });
      expect(params['p_performed_date'], '2026-08-22');

      // 本人は RPC 内の auth.uid() が解決する。user_id を送らない（ADR-0005）。
      expect(params.containsKey('p_user_id'), isFalse);
      // 回数・重量は記録しない（ADR-0008）。引数にも入れない。
      expect(params.containsKey('p_reps'), isFalse);
      expect(params.containsKey('p_sets'), isFalse);
      expect(params.containsKey('p_weight_kg'), isFalse);
      // 実施順は配列の並びで表す。列も引数も持たない（ADR-0021）。
      expect(params.containsKey('p_order'), isFalse);
      // FEAT-03 の reason は渡さないし保存もしない（ADR-0021）。
      expect(params.containsKey('p_reason'), isFalse);
    });
  });

  group('6. 状態ガードの判定（§4.2・TC-FEAT04-07/08/10）', () {
    test('返却1行 → 遷移成立（ST-01 → ST-02）', () {
      // `.eq(is_done, false)` を通った行が1行返った。T02 が成立している。
      expect(
        resolveToggleResult(updatedRowCount: 1, exists: true),
        TrainingToggleResult.transitioned,
      );
      // 行数が1以上なら存在確認は不要。exists は見ない。
      expect(
        resolveToggleResult(updatedRowCount: 1, exists: false),
        TrainingToggleResult.transitioned,
      );
    });

    test('返却0行＋存在あり → 冪等成功（二重反映なし）', () {
      // 既に ST-02 だっただけ。DB は無変更で、エラーにもしない。
      expect(
        resolveToggleResult(updatedRowCount: 0, exists: true),
        TrainingToggleResult.alreadyDone,
      );
      expect(
        resolveToggleResult(updatedRowCount: 0, exists: true).isSuccess,
        isTrue,
      );
    });

    test('返却0行＋存在なし → ERR-TRAINING-004', () {
      // 他人の行（RLS で不可視）もここへ来る。存在の有無を漏らさない。
      expect(
        resolveToggleResult(updatedRowCount: 0, exists: false),
        TrainingToggleResult.notFound,
      );
      expect(
        resolveToggleResult(updatedRowCount: 0, exists: false).isSuccess,
        isFalse,
      );
    });

    test('逆遷移（is_done=false）は受理しない（ERR-TRAINING-006・§4.1）', () {
      // 許可遷移は T02（ST-01 → ST-02）だけ。取り消しは実装しない（§10 #3 が未決）。
      expect(validateDoneTransition(nextIsDone: true), isNull);
      expect(validateDoneTransition(nextIsDone: false), isNotNull);
    });
  });

  group('7. 入館記録の日付・時刻の検証（ERR-TRAINING-008・§3.3）', () {
    final today = DateTime(2026, 8, 22);

    test('入館日は未来不可。当日は通る', () {
      expect(validateVisitDate(DateTime(2026, 8, 22), today), isNull);
      expect(validateVisitDate(DateTime(2026, 8, 21), today), isNull);
      expect(validateVisitDate(DateTime(2026, 8, 23), today), isNotNull);
      expect(validateVisitDate(null, today), isNotNull);
    });

    test('入館時刻は HH:MM か HH:MM:SS。空欄は正常', () {
      // 任意項目。未入力は null で入る（visit_time は null 許容）。
      expect(validateVisitTime(null), isNull);
      expect(validateVisitTime(''), isNull);
      expect(validateVisitTime('   '), isNull);

      expect(validateVisitTime('09:30'), isNull);
      expect(validateVisitTime('00:00'), isNull);
      expect(validateVisitTime('23:59'), isNull);
      expect(validateVisitTime('09:30:15'), isNull);

      // 形式違い・範囲外。
      expect(validateVisitTime('24:00'), isNotNull);
      expect(validateVisitTime('9:30'), isNotNull);
      expect(validateVisitTime('09:60'), isNotNull);
      expect(validateVisitTime('0930'), isNotNull);
      expect(validateVisitTime('09:30:60'), isNotNull);
      expect(validateVisitTime('午前9時30分'), isNotNull);
    });

    test('時刻は0埋めして組み立てる', () {
      expect(formatTimeOfDay(9, 5), '09:05');
      expect(formatTimeOfDay(23, 59), '23:59');
      expect(formatTimeOfDay(0, 0), '00:00');
      // 組み立てた値は必ず検証を通る。
      expect(validateVisitTime(formatTimeOfDay(9, 5)), isNull);
    });

    test('gym_visits への INSERT は列名そのまま。未入力の時刻は null', () {
      final values = buildGymVisitInsert(
        userId: '00000000-0000-4000-8000-000000000001',
        gymId: 3,
        visitDate: DateTime(2026, 8, 22),
        visitTime: '  09:30  ',
      );
      // ⚠️ 設計 §3.3 の例は user_id を送らないが、適用済みの DDL は
      // NOT NULL で既定値が無い。送らないと 23502 になる。
      expect(values.keys.toSet(), {
        'user_id',
        'gym_id',
        'visit_date',
        'visit_time',
      });
      expect(values['gym_id'], 3);
      expect(values['visit_date'], '2026-08-22');
      expect(values['visit_time'], '09:30');

      final blank = buildGymVisitInsert(
        userId: '00000000-0000-4000-8000-000000000001',
        gymId: 3,
        visitDate: DateTime(2026, 8, 22),
        visitTime: '   ',
      );
      // 空文字ではなく null を入れる。
      expect(blank['visit_time'], isNull);
    });
  });

  group('読み取り側の組み立て（埋め込み select）', () {
    test('明細と種目名を平坦化する。回数・重量の列は無い', () {
      final session = TrainingSession.fromJson(const {
        'id': 7,
        'performed_date': '2026-08-22',
        'training_session_details': [
          {
            'id': 71,
            'menu_id': 11,
            'is_done': true,
            'training_menus': {'name': 'ラットプルダウン'},
          },
          {
            'id': 72,
            'menu_id': 12,
            'is_done': false,
            'training_menus': {'name': 'ベンチプレス'},
          },
        ],
      });

      expect(session.id, 7);
      expect(session.performedDate, DateTime(2026, 8, 22));
      expect(session.details.length, 2);
      expect(session.details.first.menuName, 'ラットプルダウン');
      // ヒートマップは1件以上 true の日を塗る（FEAT-05）。
      expect(session.doneCount, 1);
    });

    test('明細の差し替えは対象1件だけ（楽観更新）', () {
      final session = TrainingSession.fromJson(const {
        'id': 7,
        'performed_date': '2026-08-22',
        'training_session_details': [
          {'id': 71, 'menu_id': 11, 'is_done': false},
          {'id': 72, 'menu_id': 12, 'is_done': false},
        ],
      });

      final updated = session.withDetail(session.details.first.markedDone());
      expect(updated.details[0].isDone, isTrue);
      expect(updated.details[1].isDone, isFalse, reason: '他の行は触らない');
      // 元のインスタンスは変わらない。巻き戻しに使えるようにしてある。
      expect(session.details[0].isDone, isFalse);
    });

    test('同日の登録済み menu_id を集める（候補から外すため）', () {
      final sessions = [
        TrainingSession.fromJson(const {
          'id': 7,
          'performed_date': '2026-08-22',
          'training_session_details': [
            {'id': 71, 'menu_id': 11, 'is_done': false},
          ],
        }),
        TrainingSession.fromJson(const {
          'id': 8,
          'performed_date': '2026-08-22',
          'training_session_details': [
            {'id': 81, 'menu_id': 12, 'is_done': true},
          ],
        }),
      ];
      // 同一日に複数セッションを作れる（§10 #2 が未決）。全部まとめて見る。
      expect(recordedMenuIds(sessions), {11, 12});
    });

    test('date 文字列は日付だけに落とす', () {
      expect(parseDateOnly('2026-08-22'), DateTime(2026, 8, 22));
      expect(parseDateOnly('2026-08-22T10:30:00'), DateTime(2026, 8, 22));
      expect(parseDateOnly('not-a-date'), isNull);
      expect(parseDateOnly(null), isNull);
    });
  });
}
