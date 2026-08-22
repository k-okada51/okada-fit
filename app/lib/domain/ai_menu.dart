/// AI が組んだ今日のメニュー（FEAT-03・ADR-0021）。
///
/// **AI が返すのは `menu_id`・実施順・理由だけ。** 種目名もやり方も返らない。
/// 名前は `training_menus` から `menu_id` で引く（§3.1）。
///
/// UI にも Supabase にも依存しない。全て単体テストの対象。
library;

/// 提案1件。
class AiMenu {
  const AiMenu({
    required this.menuId,
    required this.order,
    required this.reason,
  });

  final int menuId;

  /// 実施順。`1..N` の連番。Edge Function 側で検証済み（ERR-MENU-007）。
  final int order;

  /// この順にした理由。
  final String reason;

  factory AiMenu.fromJson(Map<String, dynamic> json) => AiMenu(
    menuId: (json['menu_id'] as num).toInt(),
    order: (json['order'] as num).toInt(),
    reason: (json['reason'] as String? ?? '').trim(),
  );
}

/// 応答全体。
///
/// **保存しない。** 画面の状態としてだけ持ち、画面を離れれば消える（§5・§7）。
class AiMenuPlan {
  const AiMenuPlan(this.menus);

  final List<AiMenu> menus;

  factory AiMenuPlan.fromJson(Map<String, dynamic> json) => AiMenuPlan([
    for (final row in (json['menus'] as List? ?? const []))
      AiMenu.fromJson(Map<String, dynamic>.from(row as Map)),
  ]);

  bool get isEmpty => menus.isEmpty;
}

/// 提案に種目名を付けた行。画面に出す形。
class ResolvedAiMenu {
  const ResolvedAiMenu({
    required this.menuId,
    required this.order,
    required this.reason,
    required this.name,
    required this.howTo,
  });

  final int menuId;
  final int order;
  final String reason;

  /// `training_menus.name` から引いた種目名。
  final String name;

  /// `training_menus.how_to`。空を許容する（ADR-0021）。
  final String? howTo;
}

/// 提案に種目名を紐づける（§3.1「Flutter が `menu_id` で引く」）。
///
/// **名前が引けない `menu_id` は落とす。** Edge Function 側で集合との照合を
/// しているので通常は起きない（ERR-MENU-007）。それでも落とすのは、
/// 名前の無い行を画面に出さないためである。
///
/// 並びは `order` 昇順。応答も昇順で来るが、ここでも保証する。
List<ResolvedAiMenu> resolveAiMenus(
  AiMenuPlan plan,
  Map<int, ({String name, String? howTo})> menuById,
) {
  final resolved = <ResolvedAiMenu>[];
  for (final menu in plan.menus) {
    final found = menuById[menu.menuId];
    if (found == null) continue;
    resolved.add(
      ResolvedAiMenu(
        menuId: menu.menuId,
        order: menu.order,
        reason: menu.reason,
        name: found.name,
        howTo: found.howTo,
      ),
    );
  }
  resolved.sort((a, b) => a.order.compareTo(b.order));
  return resolved;
}
