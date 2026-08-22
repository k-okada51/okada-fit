import 'package:flutter_test/flutter_test.dart';

import 'package:okada_fit/domain/ai_menu.dart';

/// メニュー提案（W-15・FEAT-03）の単体テスト。
///
/// **AI が返すのは `menu_id`・実施順・理由だけ**（ADR-0021）。
/// 種目名は `training_menus` から引く。ここはその紐づけを確かめる。
void main() {
  const menuById = <int, ({String name, String? howTo})>{
    1: (name: 'ベンチプレス', howTo: '肩甲骨を寄せる'),
    2: (name: 'チェストプレス', howTo: null),
    3: (name: 'ダンベルフライ', howTo: ''),
  };

  AiMenuPlan plan(List<(int, int, String)> rows) => AiMenuPlan.fromJson({
    'menus': [
      for (final (id, order, reason) in rows)
        {'menu_id': id, 'order': order, 'reason': reason},
    ],
  });

  group('応答の読み取り', () {
    test('1. menu_id・order・reason を読む', () {
      final p = plan([(1, 1, ' 大きな筋群を先に '), (2, 2, '仕上げ')]);
      expect(p.menus.length, 2);
      expect(p.menus.first.menuId, 1);
      expect(p.menus.first.reason, '大きな筋群を先に');
    });

    test('2. menus が無くても落ちない', () {
      expect(AiMenuPlan.fromJson(const {}).isEmpty, isTrue);
    });
  });

  group('種目名の紐づけ（§3.1）', () {
    test('3. menu_id から名前とやり方を引く', () {
      final resolved = resolveAiMenus(plan([(1, 1, 'a'), (2, 2, 'b')]), menuById);
      expect(resolved.map((m) => m.name).toList(), ['ベンチプレス', 'チェストプレス']);
      expect(resolved.first.howTo, '肩甲骨を寄せる');
      // how_to は空を許容する（ADR-0021）。null のままにする。
      expect(resolved[1].howTo, isNull);
    });

    test('4. order 昇順に並べ替える', () {
      final resolved = resolveAiMenus(plan([(3, 3, 'c'), (1, 1, 'a'), (2, 2, 'b')]), menuById);
      expect(resolved.map((m) => m.order).toList(), [1, 2, 3]);
      expect(resolved.map((m) => m.menuId).toList(), [1, 2, 3]);
    });

    test('5. 名前を引けない menu_id は落とす', () {
      // Edge Function 側の照合（ERR-MENU-007）を抜けてくることは通常無い。
      // **それでも落とす。** 名前の無い行を画面に出さないため。
      final resolved = resolveAiMenus(plan([(1, 1, 'a'), (99, 2, 'b')]), menuById);
      expect(resolved.length, 1);
      expect(resolved.single.menuId, 1);
    });

    test('6. 空の提案でも落ちない', () {
      expect(resolveAiMenus(plan(const []), menuById), isEmpty);
      expect(resolveAiMenus(plan([(1, 1, 'a')]), const {}), isEmpty);
    });
  });
}
