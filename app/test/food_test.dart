import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:okada_fit/domain/csv_import.dart';
import 'package:okada_fit/domain/food.dart';

/// 食品マスタの1件編集・削除（W-10・FEAT-10 §7）の単体テスト。
///
/// ネットワークを使わない。見るのは `domain/food.dart` の純関数だけである。
///
/// 確かめたいのは1点。**取込と編集が同じ規則を通っているか。**
/// 規則が2本に割れると、CSVでは入る値が編集では弾かれる（またはその逆）ことが起きる。
void main() {
  group('食品名の検証（ERR-FOOD-003）', () {
    test('空・空白のみを弾く（foods.name は NOT NULL）', () {
      expect(validateFoodNameInput(''), isNotNull);
      expect(validateFoodNameInput('   '), isNotNull);
      expect(validateFoodNameInput('　'), isNotNull, reason: '全角スペースのみ');
      expect(validateFoodNameInput('\t\n'), isNotNull);
      expect(validateFoodNameInput(null), isNotNull);

      expect(validateFoodNameInput('鶏むね肉'), isNull);
      // 前後の空白は正規化で落ちる。落ちた結果で判定する。
      expect(validateFoodNameInput('  鶏むね肉  '), isNull);
    });

    test('上限は正規化後の長さで数える', () {
      final ok = 'あ' * kMaxFoodNameLength;
      expect(validateFoodNameInput(ok), isNull);
      expect(validateFoodNameInput('あ' * (kMaxFoodNameLength + 1)), isNotNull);
      // 空白を足しても正規化で落ちるため、上限には効かない。
      expect(validateFoodNameInput('  $ok  '), isNull);
    });

    test('判定は checkFoodName の1本（正規化済みの値を受ける）', () {
      // 入力欄用の関数は「正規化 → checkFoodName」の合成でしかない。
      expect(checkFoodName(normalizeFoodName('  ')), FoodReason.emptyName);
      expect(
        checkFoodName(normalizeFoodName('あ' * 101)),
        FoodReason.nameTooLong,
      );
      expect(checkFoodName(normalizeFoodName(' 卵 ')), isNull);
    });
  });

  group('タンパク質量の検証（ERR-FOOD-004）', () {
    test('負数を弾く（DB の CHECK (protein_amount >= 0) と同じ規則）', () {
      expect(validateProteinAmountInput('-0.1'), isNotNull);
      expect(validateProteinAmountInput('-1'), isNotNull);

      // 0 は通る。DB も `>= 0` を許す。
      expect(validateProteinAmountInput('0'), isNull);
      expect(validateProteinAmountInput('25.0'), isNull);
      expect(validateProteinAmountInput('1000'), isNull, reason: '境界は通す');
      expect(validateProteinAmountInput('1000.1'), isNotNull);
    });

    test('数値でない文字列を弾く', () {
      expect(validateProteinAmountInput(''), isNotNull);
      expect(validateProteinAmountInput('abc'), isNotNull);
      expect(validateProteinAmountInput('25g'), isNotNull);
      expect(validateProteinAmountInput('２５'), isNotNull, reason: '全角数字');
      expect(validateProteinAmountInput('NaN'), isNotNull);
      expect(validateProteinAmountInput('Infinity'), isNotNull);
      expect(validateProteinAmountInput(null), isNotNull);
    });

    test('送る値は小数第1位に丸める（ADR-0022・numeric(6,1)）', () {
      // DB 側が丸めるのと同じ丸めをしてから送る。
      // 「保存した値」と「送った値」がずれないようにするため。
      expect(parseProteinAmount('20.55'), 20.6);
      expect(parseProteinAmount('20.54'), 20.5);
      expect(parseProteinAmount('25'), 25.0);
      // 検証を通らない文字列は null。画面が先に弾いている。
      expect(parseProteinAmount('abc'), isNull);
      expect(parseProteinAmount(''), isNull);
    });
  });

  group('取込と編集で規則が割れていないこと（§7）', () {
    test('同じ値に対して同じ判定になる', () {
      // 編集ダイアログが弾く値は、CSV取込でも同じ理由で弾かれること。
      const cases = <String, FoodReason>{
        '': FoodReason.proteinEmpty,
        'abc': FoodReason.proteinNotNumber,
        '２５': FoodReason.proteinNotNumber,
        '-1': FoodReason.proteinNegative,
        '1000.1': FoodReason.proteinTooLarge,
      };
      cases.forEach((input, expected) {
        // 編集ダイアログの経路。
        expect(checkProteinAmount(input), expected, reason: '編集: $input');
        // CSV取込の経路。同じ関数を通っていることを、結果の一致で示す。
        final result = prepareFoodsCsv(
          _utf8('name,protein_amount\n卵,"$input"\n'),
        );
        expect(result.errors.single.reason, expected, reason: '取込: $input');
      });
    });

    test('name の正規化も取込と編集で同じ', () {
      const raw = '　ＭＣＴ  オイル ';
      final result = prepareFoodsCsv(_utf8('name,protein_amount\n$raw,14.0\n'));
      // 取込で保存される名前と、編集で送る名前が一致すること。
      expect(
        result.rows.single.name,
        buildFoodUpdate(name: raw, proteinAmount: '14.0')['name'],
      );
    });
  });

  group('編集で送る patch（§7）', () {
    test('キーは DB の列名そのまま。正規化と丸めを通してある', () {
      final patch = buildFoodUpdate(name: '  Ｗｈｅｙ  ', proteinAmount: '20.55');
      expect(patch, {'name': 'whey', 'protein_amount': 20.6});
      // ここに無い列を出さないため、未知列は構造的に起きない。
      expect(patch.keys.toSet(), {'name', 'protein_amount'});
    });

    test('検証を通らない値では patch を作らない', () {
      // 画面が先に弾いているが、リポジトリまで抜けたら例外で止める。
      expect(
        () => buildFoodUpdate(name: '   ', proteinAmount: '20.0'),
        throwsArgumentError,
      );
      expect(
        () => buildFoodUpdate(name: '卵', proteinAmount: '-1'),
        throwsArgumentError,
      );
    });
  });

  group('Food の組み立て', () {
    test('numeric が文字列で返っても double になる（ADR-0022）', () {
      // PostgreSQL の numeric・bigint はドライバによって文字列で返ることがある。
      final food = Food.fromJson(const {
        'id': '12',
        'name': '鶏むね肉',
        'protein_amount': '25.0',
      });
      expect(food.id, 12);
      expect(food.name, '鶏むね肉');
      expect(food.proteinAmount, 25.0);

      final numeric = Food.fromJson(const {
        'id': 12,
        'name': '鶏むね肉',
        'protein_amount': 25.0,
      });
      expect(numeric.proteinAmount, 25.0);
    });
  });
}

/// UTF-8 のバイト列にする。`prepareFoodsCsv` は `Uint8List` を受ける。
Uint8List _utf8(String text) => Uint8List.fromList(utf8.encode(text));
