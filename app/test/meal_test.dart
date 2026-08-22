import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:okada_fit/domain/meal_image.dart';
import 'package:okada_fit/domain/meal_nutrition.dart';

/// 食事撮影（W-12・FEAT-08）の単体テスト。
///
/// ネットワークも Supabase も使わない。**課金は一切発生しない。**
///
/// 確かめたいのは2点。
///
/// | # | 内容 |
/// |---|---|
/// | 1 | **課金を伴う送信より前に、壊れた写真を落とせているか**（§3.4） |
/// | 2 | **保存行に料理名が混ざっていないか**（ADR-0003） |
void main() {
  /// 先頭に本物のマジックバイトを置いた、指定バイト長のダミー画像。
  Uint8List fakeImage(String kind, [int bytes = kMinImageBytes]) {
    const heads = {
      'jpeg': [0xFF, 0xD8, 0xFF],
      'png': [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A],
      'webp': [0x52, 0x49, 0x46, 0x46, 0, 0, 0, 0, 0x57, 0x45, 0x42, 0x50],
    };
    final buffer = Uint8List(bytes);
    buffer.setAll(0, heads[kind]!);
    return buffer;
  }

  group('写真の検証（送信前・FEAT-08 §3.4）', () {
    test('1. 3形式の正常系は通る', () {
      expect(validateImageInput(fakeImage('jpeg'), 'image/jpeg'), isNull);
      expect(validateImageInput(fakeImage('png'), 'image/png'), isNull);
      expect(validateImageInput(fakeImage('webp'), 'image/webp'), isNull);
    });

    test('2. 申告と実体が食い違うものを落とす（ERR-MEAL-002）', () {
      // 中身は PNG なのに JPEG と申告している。
      // **申告だけを信じると通ってしまい、課金してから Gemini 側で落ちる。**
      expect(validateImageInput(fakeImage('png'), 'image/jpeg')?.code, 'ERR-MEAL-002');
      expect(validateImageInput(fakeImage('webp'), 'image/png')?.code, 'ERR-MEAL-002');

      // どの形式でもないバイト列。
      final junk = Uint8List(kMinImageBytes)..setAll(0, [0, 1, 2, 3]);
      expect(validateImageInput(junk, 'image/jpeg')?.code, 'ERR-MEAL-002');
    });

    test('3. 許可外の MIME を落とす（ERR-MEAL-002）', () {
      expect(validateImageInput(fakeImage('jpeg'), 'image/gif')?.code, 'ERR-MEAL-002');
      expect(validateImageInput(fakeImage('jpeg'), 'image/heic')?.code, 'ERR-MEAL-002');
      expect(validateImageInput(fakeImage('jpeg'), '')?.code, 'ERR-MEAL-002');
    });

    test('4. 下限・上限の境界（ERR-MEAL-001 / 003）', () {
      expect(
        validateImageInput(fakeImage('jpeg', kMinImageBytes - 1), 'image/jpeg')?.code,
        'ERR-MEAL-001',
      );
      expect(validateImageInput(fakeImage('jpeg', kMinImageBytes), 'image/jpeg'), isNull);
      expect(validateImageInput(fakeImage('jpeg', kMaxImageBytes), 'image/jpeg'), isNull);
      expect(
        validateImageInput(fakeImage('jpeg', kMaxImageBytes + 1), 'image/jpeg')?.code,
        'ERR-MEAL-003',
      );
      expect(validateImageInput(Uint8List(0), 'image/jpeg')?.code, 'ERR-MEAL-001');
    });

    test('5. Edge Function 側と同じ規則になっている', () {
      // `supabase/functions/analyze-meal/schema.ts` の値と一致させる。
      // ずれると、端末で通ったものが関数で落ちる（または逆）。
      expect(kMinImageBytes, 1024);
      expect(kMaxImageBytes, 1048576);
      expect(kAllowedImageMimeTypes, ['image/jpeg', 'image/png', 'image/webp']);
    });

    test('6. マジックバイトの判別は短いバイト列で落ちない', () {
      expect(sniffImageMimeType(Uint8List(0)), isNull);
      expect(sniffImageMimeType(Uint8List.fromList([0xFF, 0xD8])), isNull);
      // RIFF だけあって WEBP が無いもの（AVI など）は WebP ではない。
      final riff = Uint8List(12)..setAll(0, [0x52, 0x49, 0x46, 0x46]);
      expect(sniffImageMimeType(riff), isNull);
    });
  });

  group('base64 のデコード後バイト長（§4 decodedLength）', () {
    test('7. 全体をデコードせずに長さを求める', () {
      // "abc" -> "YWJj"（パディング無し）
      expect(decodedBase64Length('YWJj'), 3);
      // "ab" -> "YWI="（パディング1）
      expect(decodedBase64Length('YWI='), 2);
      // "a" -> "YQ=="（パディング2）
      expect(decodedBase64Length('YQ=='), 1);
    });

    test('8. データURL の前置きと改行を無視する', () {
      expect(decodedBase64Length('data:image/jpeg;base64,YWJj'), 3);
      expect(decodedBase64Length('YWJ\nj'), 3);
    });
  });

  group('MIME の推測', () {
    test('9. 拡張子から引く。分からなければ null', () {
      expect(mimeTypeFromPath('/tmp/IMG_0001.JPG'), 'image/jpeg');
      expect(mimeTypeFromPath('/tmp/a.jpeg'), 'image/jpeg');
      expect(mimeTypeFromPath('/tmp/a.png'), 'image/png');
      expect(mimeTypeFromPath('/tmp/a.webp'), 'image/webp');
      // HEIC は許可していない。推測せず null にして送らせない。
      expect(mimeTypeFromPath('/tmp/a.heic'), isNull);
      expect(mimeTypeFromPath('/tmp/a'), isNull);
    });
  });

  group('応答の読み取り', () {
    test('10. numeric が文字列で返っても double になる（ADR-0022）', () {
      final n = MealNutrition.fromJson({
        'food_name': '牛丼',
        'dish_names': ['牛丼', '味噌汁'],
        'calories_kcal': '733.4',
        'protein_g': 22.9,
        'sugar_g': '104.1',
        'fat_g': 25,
      });
      expect(n.caloriesKcal, 733.4);
      expect(n.proteinG, 22.9);
      expect(n.sugarG, 104.1);
      expect(n.fatG, 25.0);
    });

    test('11. 料理名は空要素を落としてトリムする', () {
      final n = MealNutrition.fromJson({
        'food_name': '  牛丼  ',
        'dish_names': ['牛丼', '', '  ', ' 味噌汁 ', 5],
        'calories_kcal': 1,
        'protein_g': 1,
        'sugar_g': 1,
        'fat_g': 1,
      });
      expect(n.foodName, '牛丼');
      expect(n.dishNames, ['牛丼', '味噌汁']);
    });
  });

  group('保存行の組み立て（§4 toMealLogRow）', () {
    final nutrition = MealNutrition.fromJson({
      'food_name': '牛丼',
      'dish_names': ['牛丼'],
      'calories_kcal': 733.4,
      'protein_g': 22.9,
      'sugar_g': 104.1,
      'fat_g': 25.0,
    });

    test('12. 料理名を保存しない（ADR-0003）', () {
      final row = nutrition.toMealLogRow(eatenAt: DateTime(2026, 8, 22, 12, 5));
      // **写真も料理名も残さないのが ADR-0003 の決めである。**
      // ここに food_name が混ざると、決定が静かに破られる。
      expect(row.containsKey('food_name'), isFalse);
      expect(row.containsKey('dish_names'), isFalse);
      expect(row.keys.toSet(), {
        'calories_kcal',
        'protein_g',
        'sugar_g',
        'fat_g',
        'eaten_date',
        'eaten_time',
      });
    });

    test('13. user_id を送らない（列 DEFAULT auth.uid() が入れる）', () {
      final row = nutrition.toMealLogRow(eatenAt: DateTime(2026, 8, 22, 12, 5));
      expect(row.containsKey('user_id'), isFalse);
    });

    test('14. 日付は端末のタイムゾーンで決める（ADR-0014）', () {
      // サーバの CURRENT_DATE（UTC）に任せると、深夜の記録が前日になる。
      final row = nutrition.toMealLogRow(eatenAt: DateTime(2026, 8, 22, 0, 5));
      expect(row['eaten_date'], '2026-08-22');
      expect(row['eaten_time'], '00:05');

      final row2 = nutrition.toMealLogRow(eatenAt: DateTime(2026, 1, 2, 9, 8));
      expect(row2['eaten_date'], '2026-01-02');
      expect(row2['eaten_time'], '09:08');
    });
  });

  group('Atwater 整合（§4）', () {
    MealNutrition make(double kcal, double p, double s, double f) =>
        MealNutrition(
          foodName: '',
          dishNames: const [],
          caloriesKcal: kcal,
          proteinG: p,
          sugarG: s,
          fatG: f,
        );

    test('15. 係数どおりに乖離を出す', () {
      // 4*20 + 4*30 + 9*10 = 290
      final consistent = make(290, 20, 30, 10);
      expect(atwaterDeviation(consistent), 0);
      expect(isAtwaterInconsistent(consistent), isFalse);

      // |580 - 290| / 290 = 1.0
      expect(atwaterDeviation(make(580, 20, 30, 10)), closeTo(1.0, 1e-9));
    });

    test('16. 閾値 0.40 を超えたときだけ注意を出す', () {
      // 290 * 1.4 = 406 → ちょうど 0.40。**超えていないので出さない。**
      expect(isAtwaterInconsistent(make(406, 20, 30, 10)), isFalse);
      expect(isAtwaterInconsistent(make(407, 20, 30, 10)), isTrue);
      expect(kAtwaterWarnThreshold, 0.40);
    });

    test('17. 全部0でも0除算にならない', () {
      // 分母は max(est, 1)。落ちないことが要件。
      expect(atwaterDeviation(make(0, 0, 0, 0)), 0);
      expect(atwaterDeviation(make(5, 0, 0, 0)), 5);
    });
  });
}
