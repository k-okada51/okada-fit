import 'package:flutter_test/flutter_test.dart';

import 'package:okada_fit/domain/protein_remaining.dart';

/// タンパク質残量と不足分提示（W-13・FEAT-09）の単体テスト。
///
/// **算出はすべて Dart 側にある**（§4・2026-08-08 確定）。RPC は素の値しか
/// 返さないので、ここが落ちれば画面の数字が全部おかしくなる。
void main() {
  ProteinRemainingSource source({
    double? weightKg = 60,
    double intakeG = 0,
    List<(int, String, double)> candidates = const [],
  }) => ProteinRemainingSource.fromJson({
    'weight_kg': weightKg,
    'intake_g': intakeG,
    'foods_candidates': [
      for (final (id, name, amount) in candidates)
        {'id': id, 'food_name': name, 'protein_amount': amount},
    ],
  });

  group('残量の算出（§4 L3・RULE-002）', () {
    test('1. 残量＝目標−摂取。体重60kg なら目標120g', () {
      final r = computeProteinRemaining(source(intakeG: 50)) as ProteinRemainingOk;
      expect(r.targetG, 120);
      expect(r.intakeG, 50);
      expect(r.remainingG, 70);
      expect(r.isAchieved, isFalse);
    });

    test('2. 過剰摂取でも 0 で止める（0クランプ）', () {
      // **負値を出さない。** 「あと −30g」は意味を成さない。
      final r = computeProteinRemaining(source(intakeG: 150)) as ProteinRemainingOk;
      expect(r.remainingG, 0);
      expect(r.isAchieved, isTrue);
      // 超過量は要るなら別に取れる（§4 L3）。
      expect(r.excessG, 30);
    });

    test('3. ちょうど達成は 0・超過は 0', () {
      final exact = computeProteinRemaining(source(intakeG: 120)) as ProteinRemainingOk;
      expect(exact.remainingG, 0);
      expect(exact.isAchieved, isTrue);
      expect(exact.excessG, 0);
    });

    test('4. 記録が無ければ摂取0＝残量は目標そのもの', () {
      final r = computeProteinRemaining(source()) as ProteinRemainingOk;
      expect(r.intakeG, 0);
      expect(r.remainingG, 120);
    });

    test('5. 丸めは最後に1回だけ（§4 L5）', () {
      // 体重 62.55 は DB に入らないが、numeric(6,1) の 62.5 で確かめる。
      // 目標 125.0 − 摂取 22.33 = 102.67 → 102.7。
      // **丸め済みどうしを引くと 125.0 − 22.3 = 102.7 で今回は一致するが、
      // 一致しない組み合わせがある。** 丸める前の差を丸める規則を固定する。
      final r = computeProteinRemaining(
        source(weightKg: 62.5, intakeG: 22.33),
      ) as ProteinRemainingOk;
      expect(r.targetG, 125.0);
      expect(r.remainingG, 102.7);
    });

    test('5b. 丸め済みどうしの引き算とずれる例', () {
      // 目標 120.0 − 摂取 22.25 = 97.75 → 97.8（half away from zero）。
      // 摂取を先に丸めると 22.3 で、120.0 − 22.3 = 97.7 になり 0.1g ずれる。
      final r = computeProteinRemaining(source(intakeG: 22.25)) as ProteinRemainingOk;
      expect(r.remainingG, 97.8, reason: '丸める前の差を丸めること');
      expect(r.intakeG, 22.3, reason: '表示用の摂取量は丸める');
    });
  });

  group('体重の状態（FEAT-07 に委ねる）', () {
    test('6. 未設定は正常な状態として扱う（ERR-PROFILE-020）', () {
      // **エラーにしない。** FEAT-06 未実施は初回利用で必ず通る。
      expect(
        computeProteinRemaining(source(weightKg: null)),
        isA<ProteinRemainingUnset>(),
      );
    });

    test('7. 0以下・非有限は不正値（ERR-PROFILE-021）', () {
      expect(computeProteinRemaining(source(weightKg: 0)), isA<ProteinRemainingInvalid>());
      expect(computeProteinRemaining(source(weightKg: -1)), isA<ProteinRemainingInvalid>());
    });

    test('8. 判定を二重に書いていない（FEAT-07 と同じ結果になる）', () {
      // 体重の判定は calcTargetProteinG が正本。ここで独自に境界を持たない。
      expect(computeProteinRemaining(source(weightKg: 0.1)), isA<ProteinRemainingOk>());
    });
  });

  group('不足分を補う食品の選定（§4 L4・RULE-005）', () {
    const pool = [
      (1, 'ゆで卵', 6.5),
      (2, 'ささみ', 23.0),
      (3, 'プロテイン', 20.0),
      (4, '納豆', 8.3),
      (5, '水', 0.0),
      (6, '鶏むね', 23.0),
    ];

    test('9. 残量に近い順・同差なら多い順・さらに同値なら id 昇順', () {
      // 残量 20 のとき: |20-20|=0 プロテイン → |23-20|=3 ささみと鶏むね
      // → ささみ(id2) が先（同差・同量なので id 昇順）。
      final picked = selectFoods(
        [for (final (i, n, a) in pool) FoodCandidate(id: i, foodName: n, proteinAmount: a)],
        20,
      );
      expect(picked.map((f) => f.foodName).toList(), ['プロテイン', 'ささみ', '鶏むね']);
    });

    test('10. 0g の食品は候補にしない', () {
      final picked = selectFoods(
        [for (final (i, n, a) in pool) FoodCandidate(id: i, foodName: n, proteinAmount: a)],
        100,
      );
      // 補えないものを勧めても意味が無い。
      expect(picked.any((f) => f.foodName == '水'), isFalse);
    });

    test('11. 達成済み（残量0以下）なら空にする', () {
      final all = [
        for (final (i, n, a) in pool) FoodCandidate(id: i, foodName: n, proteinAmount: a),
      ];
      expect(selectFoods(all, 0), isEmpty);
      expect(selectFoods(all, -5), isEmpty);
    });

    test('12. 件数は3件まで', () {
      final all = [
        for (final (i, n, a) in pool) FoodCandidate(id: i, foodName: n, proteinAmount: a),
      ];
      expect(selectFoods(all, 15).length, kSuggestedFoodCount);
      expect(kSuggestedFoodCount, 3);
    });

    test('13. 母集合が空でも落ちない', () {
      expect(selectFoods(const [], 50), isEmpty);
    });

    test('14. 並びは決定的（同じ入力なら同じ順序）', () {
      final all = [
        for (final (i, n, a) in pool) FoodCandidate(id: i, foodName: n, proteinAmount: a),
      ];
      final first = selectFoods(all, 21).map((f) => f.id).toList();
      final second = selectFoods(all.reversed.toList(), 21).map((f) => f.id).toList();
      // 入力の順序が違っても結果が変わらない＝id まで見て決めている。
      expect(first, second);
    });

    test('15. 達成済みなら computeProteinRemaining も提示しない', () {
      final r = computeProteinRemaining(
        source(intakeG: 200, candidates: pool),
      ) as ProteinRemainingOk;
      expect(r.suggestions, isEmpty);
    });
  });

  group('集計対象日（§4 L1・ADR-0014）', () {
    test('16. 端末のタイムゾーンの当日を YYYY-MM-DD で渡す', () {
      // **サーバの CURRENT_DATE を使わない。** Supabase は UTC のため、
      // 深夜の記録が前日に集計されてしまう。
      expect(todayOnDevice(DateTime(2026, 8, 22, 0, 5)), '2026-08-22');
      expect(todayOnDevice(DateTime(2026, 1, 2, 23, 59)), '2026-01-02');
    });
  });

  group('応答の読み取り', () {
    test('17. numeric が文字列で返っても double になる（ADR-0022）', () {
      final s = ProteinRemainingSource.fromJson({
        'weight_kg': '62.5',
        'intake_g': '22.3',
        'foods_candidates': [
          {'id': 1, 'food_name': ' ゆで卵 ', 'protein_amount': '6.5'},
        ],
      });
      expect(s.weightKg, 62.5);
      expect(s.intakeG, 22.3);
      expect(s.candidates.single.foodName, 'ゆで卵');
      expect(s.candidates.single.proteinAmount, 6.5);
    });

    test('18. weight_kg が null でも読める', () {
      final s = ProteinRemainingSource.fromJson({
        'weight_kg': null,
        'intake_g': 0,
        'foods_candidates': [],
      });
      expect(s.weightKg, isNull);
      expect(s.candidates, isEmpty);
    });
  });
}
