import 'package:flutter_test/flutter_test.dart';

import 'package:okada_fit/domain/profile.dart';

/// 初期設定（W-06・FEAT-06）の単体テスト。
///
/// ネットワークを使わない。Supabase の初期化もしない。
/// 見るのは `domain/profile.dart` の純関数だけである。
///
/// 確かめたいのは1点。**DB の CHECK 制約と同じ規則を、送信前に Dart 側でも
/// 弾けているか。** DB は最後の防波堤であって、そこへ到達させない。
void main() {
  group('体重の検証（ERR-PROFILE-001）', () {
    test('1. 0 と負数を弾く（DB の CHECK (weight_kg > 0) と同じ規則）', () {
      // DB は `> 0` しか見ない。アプリ側の下限20.0がそれを含む形で弾く。
      expect(validateWeightKg('0'), isNotNull);
      expect(validateWeightKg('0.0'), isNotNull);
      expect(validateWeightKg('-1'), isNotNull);
      expect(validateWeightKg('-62.5'), isNotNull);

      // 範囲内は通る。境界の20.0／300.0も通す（TC-FEAT06-04）。
      expect(validateWeightKg('20.0'), isNull);
      expect(validateWeightKg('62.5'), isNull);
      expect(validateWeightKg('300.0'), isNull);

      // 範囲外は弾く（TC-FEAT06-05）。
      expect(validateWeightKg('19.9'), isNotNull);
      expect(validateWeightKg('300.1'), isNotNull);
    });

    test('2. 小数第2位は第1位に丸められる（ADR-0022・numeric(6,1)）', () {
      // DB の列は `numeric(6,1)`。第2位以降は保存時に丸められる。
      // アプリ側で同じ丸めをしてから送り、「送った値」と「保存された値」を揃える。
      expect(roundToOneDecimal(62.56), 62.6);
      expect(roundToOneDecimal(62.34), 62.3);
      expect(roundToOneDecimal(80.99), 81.0);

      // 入力欄の文字列から作る経路でも同じ結果になる。
      expect(parseWeightKg('62.56'), 62.6);
      expect(parseWeightKg('62.34'), 62.3);

      // patch にも丸めた値が乗る。
      final patch = buildProfileUpdate(
        const ProfileUpdate(weightKg: FieldPatch<double>.of(62.56)),
      );
      expect(patch, {'weight_kg': 62.6});

      // 丸めた結果で範囲を判定する。19.96 は 20.0 になるので通る。
      expect(validateWeightKg('19.96'), isNull);
    });

    test('7. 数値でない文字列を弾く', () {
      expect(validateWeightKg('abc'), isNotNull);
      expect(validateWeightKg('62.5kg'), isNotNull);
      expect(validateWeightKg('６２'), isNotNull, reason: '全角数字は数値にしない');
      // `double.tryParse` はこの2つを通す。範囲判定が効かないため個別に落とす。
      expect(validateWeightKg('NaN'), isNotNull);
      expect(validateWeightKg('Infinity'), isNotNull);
    });
  });

  group('表示名の検証（ERR-PROFILE-003）', () {
    test('3. 空・空白のみを弾く（users.name は NOT NULL）', () {
      expect(validateName(''), isNotNull);
      expect(validateName('   '), isNotNull);
      expect(validateName('\t\n'), isNotNull);
      expect(validateName(null), isNotNull);

      expect(validateName('岡田'), isNull);
      // 前後の空白はトリムして数える。
      expect(validateName('  岡田  '), isNull);

      // 上限（TC-FEAT06-08）。
      expect(validateName('あ' * kMaxNameLength), isNull);
      expect(validateName('あ' * (kMaxNameLength + 1)), isNotNull);
    });

    test('3b. 空の表示名は patch に出さない（NOT NULL を破らない）', () {
      final patch = buildProfileUpdate(
        const ProfileUpdate(name: FieldPatch<String>.of('   ')),
      );
      expect(patch.containsKey('name'), isFalse);

      // 値があるときはトリムして出す。
      final trimmed = buildProfileUpdate(
        const ProfileUpdate(name: FieldPatch<String>.of('  岡田  ')),
      );
      expect(trimmed, {'name': '岡田'});
    });
  });

  group('目標トレーニング回数の検証（ERR-PROFILE-002）', () {
    test('4. 負数を弾く（DB の CHECK (target_training_count >= 0) と同じ規則）', () {
      expect(validateTargetTrainingCount('-1'), isNotNull);
      expect(validateTargetTrainingCount('-12'), isNotNull);

      // 0 は「目標を置かない」。DB も `>= 0` を許すため弾かない（TC-FEAT06-06）。
      expect(validateTargetTrainingCount('0'), isNull);
      expect(validateTargetTrainingCount('12'), isNull);
      expect(validateTargetTrainingCount('$kMaxTargetTrainingCount'), isNull);

      // 上限超え・小数・文字列（TC-FEAT06-07）。
      expect(validateTargetTrainingCount('${kMaxTargetTrainingCount + 1}'), isNotNull);
      expect(validateTargetTrainingCount('12.5'), isNotNull);
      expect(validateTargetTrainingCount('じゅうに'), isNotNull);
    });
  });

  group('Profile の組み立て', () {
    test('5. 体重が null のままでも作れる（未設定は正常）', () {
      final profile = Profile.fromJson(const {
        'id': '00000000-0000-4000-8000-000000000001',
        'name': '岡田',
        'target_training_count': 12,
        'weight_kg': null,
      });

      // 体重は推測してはならない値。0 で埋めない（FEAT-06 §4.2）。
      expect(profile.weightKg, isNull);
      expect(profile.isWeightUnset, isTrue);
      expect(profile.name, '岡田');

      // 空欄は「未設定」として扱う。0 にしない。
      expect(validateWeightKg(''), isNull, reason: '未設定は検証を通る');
      expect(parseWeightKg(''), isNull);

      // 未設定へ戻す更新も送れる（FEAT-06 §4.3）。
      final patch = buildProfileUpdate(
        const ProfileUpdate(weightKg: FieldPatch<double>.of(null)),
      );
      expect(patch, {'weight_kg': null});
      expect(patch.containsKey('weight_kg'), isTrue, reason: 'キーごと消さない');
    });

    test('6. 目標回数が null のとき既定12として読める（RULE-007）', () {
      // トリガ `handle_new_user` は name しか入れない。DB は null のままである。
      // 既定を出すのはアプリ側（W-06 の判断）。
      final profile = Profile.fromJson(const {
        'id': '00000000-0000-4000-8000-000000000001',
        'name': '岡田',
        'target_training_count': null,
        'weight_kg': null,
      });

      expect(profile.targetTrainingCount, 12);
      expect(profile.targetTrainingCount, kDefaultTargetTrainingCount);

      // 値が入っていればそれを使う。既定で上書きしない。
      final explicit = Profile.fromJson(const {
        'id': '00000000-0000-4000-8000-000000000001',
        'name': '岡田',
        'target_training_count': 0,
        'weight_kg': null,
      });
      expect(explicit.targetTrainingCount, 0, reason: '0 を未設定と取り違えない');
    });

    test('6b. numeric が文字列で返っても double になる（ADR-0022）', () {
      // PostgreSQL の numeric はドライバによって文字列で返ることがある。
      // 変換は Profile.fromJson の1か所に集約してある。
      final asString = Profile.fromJson(const {
        'id': '00000000-0000-4000-8000-000000000001',
        'name': '岡田',
        'target_training_count': '12',
        'weight_kg': '62.5',
      });
      expect(asString.weightKg, 62.5);
      expect(asString.targetTrainingCount, 12);
    });
  });

  group('部分更新の patch（FEAT-06 §4.3）', () {
    test('指定しなかった列はキーごと出ない', () {
      final patch = buildProfileUpdate(
        const ProfileUpdate(targetTrainingCount: FieldPatch<int>.of(20)),
      );
      expect(patch, {'target_training_count': 20});
      expect(patch.containsKey('name'), isFalse);
      expect(patch.containsKey('weight_kg'), isFalse);
    });

    test('何も指定しなければ空になる（呼び出し側が更新をやめる）', () {
      expect(buildProfileUpdate(const ProfileUpdate()), isEmpty);
    });

    test('キーは DB の列名そのまま（snake_case）', () {
      final patch = buildProfileUpdate(
        const ProfileUpdate(
          name: FieldPatch<String>.of('岡田'),
          targetTrainingCount: FieldPatch<int>.of(12),
          weightKg: FieldPatch<double>.of(62.5),
        ),
      );
      // ここに無い列を出さないため、未知列（ERR-VALIDATION-001）は起きない。
      expect(patch.keys.toSet(), {'name', 'target_training_count', 'weight_kg'});
    });
  });
}
