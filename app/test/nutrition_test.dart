// FEAT-07 必要タンパク質量算出（W-07）の単体テスト。
//
// **ネットワークを使わない。** Supabase の初期化もモックもしない。
// 純関数を呼び、戻り値だけを見る。
//
// FEAT-07 は DB にもネットワークにも依存しない。テスト戦略（`01_テスト戦略.md`）の
// L1（最も厚くテストする層）にあたり、本機能ではテストが主役である。
//
// 番号は FEAT-07 §9 の TC-ID に対応させる。
// 本ファイルで扱わないものは次の4本。いずれも純関数の単体テストの範囲外。
//
// | TC-ID | 内容 | 扱い |
// |---|---|---|
// | TC-FEAT07-09 | `app/lib/**` に係数リテラルが無いこと | 静的検査。他作業のファイルを走査するため別立て |
// | TC-FEAT07-10 | 2つの RPC 間の一致 | 実 DB が要る |
// | TC-FEAT07-11 | 表示丸め（整数 g） | ウィジェットテスト |
// | TC-FEAT07-13 | `supabase/migrations/**` に式が無いこと | 静的検査 |

import 'package:flutter_test/flutter_test.dart';

import 'package:okada_fit/domain/nutrition.dart';

/// 算出できたことを確かめ、`ProteinTargetOk` として取り出す。
ProteinTargetOk expectOk(double? weightKg) {
  final result = calcTargetProteinG(weightKg);
  expect(result, isA<ProteinTargetOk>(), reason: '算出できるはずの入力: $weightKg');
  return result as ProteinTargetOk;
}

/// 不正値として弾かれたことを確かめる（ERR-PROFILE-021 の側）。
void expectInvalid(double? weightKg, {required String reason}) {
  final result = calcTargetProteinG(weightKg);
  expect(result, isA<ProteinTargetInvalid>(), reason: reason);
}

void main() {
  group('calcTargetProteinG', () {
    test('TC-FEAT07-01. 通常の体重（整数kg）は体重の2倍になる', () {
      final ok = expectOk(70.0);

      // **期待値を直書きする。** ここだけは `70 * proteinGPerKg` と書かない。
      // 定数を使って書くと、係数が 3.0 に変わってもテストが一緒に動いて
      // 通ってしまう。RULE-001 を外から釘付けにするのがこの表の役目である。
      expect(ok.targetG, 140.0);

      // 根拠表示（SCR-05 の「◯kg × 2g」）用に、入力と係数が同梱される。
      expect(ok.weightKg, 70.0);
      expect(ok.coefficient, 2.0);

      // ゴールデン値表（§9）。(体重kg, 必要量g)。
      const golden = <(double, double)>[
        (45.0, 90.0),
        (50.0, 100.0),
        (68.0, 136.0),
        (82.0, 164.0),
      ];
      for (final (weightKg, expected) in golden) {
        expect(expectOk(weightKg).targetG, expected, reason: '${weightKg}kg');
      }
    });

    test('TC-FEAT07-02. 小数を含む体重も小数第1位まで正しく出る', () {
      // 体重は numeric(6,1)（ADR-0022）。小数第1位までが入力の最大精度である。
      const golden = <(double, double)>[
        (62.5, 125.0),
        (70.1, 140.2),
        (58.3, 116.6),
        (99.9, 199.8),
      ];
      for (final (weightKg, expected) in golden) {
        expect(expectOk(weightKg).targetG, expected, reason: '${weightKg}kg');
      }

      // 第2位以下が残らない。もう一度丸めても値が動かないことで確かめる。
      for (final (weightKg, _) in golden) {
        final targetG = expectOk(weightKg).targetG;
        expect(roundProteinG(targetG), targetG, reason: '${weightKg}kg');
      }
    });

    test('TC-FEAT07-03. 体重が未設定（null）なら Unset。例外を投げない', () {
      // 体重未設定は初回利用で必ず通る**正常な業務状態**である（§4.3）。
      // 例外にすると FEAT-05・FEAT-09 が初回ログイン直後に一律で失敗する。
      expect(() => calcTargetProteinG(null), returnsNormally);

      final result = calcTargetProteinG(null);
      expect(result, isA<ProteinTargetUnset>());

      // 不正値（ERR-PROFILE-021）と取り違えない。写像先が別のため。
      expect(result, isNot(isA<ProteinTargetInvalid>()));
      expect(result, isNot(isA<ProteinTargetOk>()));
    });

    test('TC-FEAT07-04. キー欠落から来た null も TC-03 と同じ結果になる', () {
      // リポジトリ層の正規化（§3.0）。PostgREST の JSON は数値が `num` で返るため
      // `(map['weight_kg'] as num?)?.toDouble()` を通してから渡す。
      // 列を選択しなかった場合・キーが欠落した場合は null になる。
      double? normalize(Map<String, dynamic> row) =>
          (row['weight_kg'] as num?)?.toDouble();

      expect(calcTargetProteinG(normalize({})), isA<ProteinTargetUnset>());
      expect(
        calcTargetProteinG(normalize({'weight_kg': null})),
        isA<ProteinTargetUnset>(),
      );

      // 値があるときは `num`（int で返ることもある）を double にして渡す。
      expect(calcTargetProteinG(normalize({'weight_kg': 70})), isA<ProteinTargetOk>());
      expect(expectOk(normalize({'weight_kg': 70})).targetG, 140.0);
    });

    test('TC-FEAT07-05. 体重 0 は不正値', () {
      // `users.weight_kg` の CHECK(>0) と同値の判定。
      expectInvalid(0.0, reason: '0 は CHECK(>0) 違反であり未設定ではない');

      final result = calcTargetProteinG(0.0) as ProteinTargetInvalid;
      // 弾いた値をログに残せること（§6）。
      expect(result.weightKg, 0.0);
    });

    test('TC-FEAT07-06. 負の体重は不正値', () {
      expectInvalid(-0.1, reason: '負値は CHECK(>0) 違反');
      expectInvalid(-70.0, reason: '負値は CHECK(>0) 違反');

      final result = calcTargetProteinG(-70.0) as ProteinTargetInvalid;
      expect(result.weightKg, -70.0);
    });

    test('TC-FEAT07-07. NaN・±Infinity は不正値', () {
      // **CHECK(>0) を通過し得るため必須**（§3.1）。
      // `NaN <= 0` は false であり、比較だけでは弾けない。
      expectInvalid(double.nan, reason: 'NaN は比較では弾けない');
      expectInvalid(double.infinity, reason: 'Infinity で目標値を作らせない');
      expectInvalid(double.negativeInfinity, reason: '-Infinity も同じ');
    });

    test('TC-FEAT07-08. 純関数である（同一入力なら常に同一出力）', () {
      final a = expectOk(62.5);
      final b = expectOk(62.5);

      expect(a.targetG, b.targetG);
      expect(a.weightKg, b.weightKg);
      expect(a.coefficient, b.coefficient);

      // 別の入力を挟んでも結果が変わらない。呼び出し順に依存しない。
      calcTargetProteinG(999.9);
      calcTargetProteinG(null);
      calcTargetProteinG(double.nan);
      expect(expectOk(62.5).targetG, a.targetG);
    });

    test('TC-FEAT07-12. 単位の取り違えは関数では検出できない', () {
      // kg のつもりで g 相当の値（1000倍）を渡しても、そのまま算出される。
      // §10 #3 の指摘（`weight_kg` も `target_g` も同じ `double`）の裏付け。
      // 検出は本関数の責務ではない。上限判定は FEAT-06 が持つ（§3.1）。
      final ok = expectOk(70000.0);
      expect(ok.targetG, 140000.0);
    });

    test('境界値. 0 に近い正の値でも算出する', () {
      // §4.3 B6。業務的な下限判定は FEAT-06 の責務であり、ここでは弾かない。
      expect(expectOk(0.1).targetG, 0.2);
      expect(expectOk(0.05).targetG, 0.1);

      // 丸めの結果 0.0 になる入力。**不正値ではない。**
      // 「未設定」「不正値」と区別できることが要点である。
      final tiny = expectOk(0.02);
      expect(tiny.targetG, 0.0);
      expect(tiny.weightKg, 0.02);

      final minimum = expectOk(double.minPositive);
      expect(minimum.targetG, 0.0);
    });

    test('境界値. 現実的な上限付近でも算出する', () {
      // `users.weight_kg` は numeric(6,1)（ADR-0022）。格納できる最大は 99999.9。
      expect(expectOk(999.9).targetG, 1999.8);
      expect(expectOk(99999.9).targetG, 199999.8);
    });

    test('境界値. 桁あふれでも例外を投げない（`[仮]`・設計に記述なし）', () {
      // `double.maxFinite` は有限だが、2倍すると Infinity になる。
      // 丸めに渡すと `UnsupportedError` が飛ぶため、手前で不正値にしている。
      // §4.3 の「例外を投げない」を守るための扱い。
      expect(() => calcTargetProteinG(double.maxFinite), returnsNormally);
      expectInvalid(double.maxFinite, reason: '積が Infinity になる入力');
    });
  });

  group('RULE-001 の係数', () {
    test('係数は 2.0（RULE-001・DEC-B06）', () {
      // 「体重 × 2g」がこの1行で読み取れる。式の正本は Dart のこの定数だけで、
      // SQL 側には置かない（§4.5 案(b)）。
      expect(proteinGPerKg, 2.0);
    });

    test('必要量 ＝ 体重 × 係数 の形になっている', () {
      // 上のテストが係数の値を釘付けにしているので、ここは**式の形**だけを見る。
      // リテラルの 2 は書かない（§4.1 の規律をテスト側でも守る）。
      for (final weightKg in <double>[45.0, 62.5, 70.0, 99.9]) {
        final ok = expectOk(weightKg);
        expect(ok.targetG, roundProteinG(weightKg * proteinGPerKg));
        expect(ok.coefficient, proteinGPerKg);
      }
    });
  });

  group('roundProteinG', () {
    test('TC-FEAT07-14. 半端値は half away from zero に丸める', () {
      // Dart の `double.round()` の丸め方向（§4.2）。
      expect(roundProteinG(140.25), 140.3);
      expect(roundProteinG(0.25), 0.3);
      expect(roundProteinG(2.75), 2.8);

      // 絶対値の大きいほうへ丸めるため、負値は下向きになる。
      expect(roundProteinG(-140.25), -140.3);
    });

    test('小数第1位で丸める', () {
      expect(roundProteinG(140.24), 140.2);
      expect(roundProteinG(140.26), 140.3);
      expect(roundProteinG(0.04), 0.0);
      expect(roundProteinG(0.06), 0.1);

      // すでに小数第1位までの値は動かさない（べき等）。
      for (final value in <double>[0.0, 0.1, 140.2, 199999.8]) {
        expect(roundProteinG(value), value, reason: '$value');
      }
    });
  });

  group('1食あたりの目安（`SCR-05 設定.dc.html`）', () {
    test('目標を kMealsPerDay で割る', () {
      expect(kMealsPerDay, 4, reason: 'デザインの「1食あたりの目安（4食）」');
      expect(proteinPerMealG(140.0), 35.0);
      expect(proteinPerMealG(125.0), 31.3, reason: '31.25 を小数第1位へ');
      expect(proteinPerMealG(0.0), 0.0);
    });

    test('丸めは roundProteinG と同じ規則（小数第1位・half away from zero）', () {
      // 130 / 4 = 32.5 → そのまま。126 / 4 = 31.5 → そのまま。
      expect(proteinPerMealG(130.0), 32.5);
      // 125.4 / 4 = 31.35 → 31.4（絶対値の大きいほうへ）。
      expect(proteinPerMealG(125.4), 31.4);
    });

    test('目標の丸め後の値を割る（画面の2つの数字が同じ元値から出る）', () {
      // SCR-05 は calcTargetProteinG の targetG をそのまま渡す。
      final target = calcTargetProteinG(62.5) as ProteinTargetOk;
      expect(target.targetG, 125.0);
      expect(proteinPerMealG(target.targetG), 31.3);
    });
  });
}
