import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// ダーク／ライトの選択を保持し、端末に保存する（ADR-0024 §3）。
///
/// **既定はダーク。** 一度も選んでいない端末はダークで起動する。
///
/// 状態管理のパッケージは入れない。持つ値が `ThemeMode` 1つしかなく、
/// `ChangeNotifier` で足りるため（FEAT-06 §7 と同じ判断）。
///
/// ⚠️ **切替の UI はまだ無い。** 置き場所は SCR-05（設定）に1つだけと
/// 決まっている（ADR-0024 §3）が、SCR-05 は本作業の対象外である。
/// TODO(ADR-0024): SCR-05 にトグルを足し、[setThemeMode] を呼ぶ。
class ThemeController extends ChangeNotifier {
  /// 保存先のキー。
  ///
  /// 値は `ThemeMode.name`（`dark` / `light` / `system`）をそのまま書く。
  /// 添字で持つと `ThemeMode` の並びが変わった瞬間に意味がずれる。
  static const String _prefsKey = 'theme_mode';

  /// 既定（ADR-0024 §3）。端末の設定には従わない。
  static const ThemeMode defaultThemeMode = ThemeMode.dark;

  ThemeMode _themeMode = defaultThemeMode;

  /// いま選ばれている表示モード。
  ThemeMode get themeMode => _themeMode;

  /// 保存済みの選択を読み込む。**`runApp` の前に1回だけ呼ぶ。**
  ///
  /// 起動後に読むと、ダークで一瞬描いてからライトへ切り替わる。
  ///
  /// 読めなかったときは既定のまま黙って進む。表示の好みが1つ戻るだけで、
  /// 業務上の損失が無いため、利用者にエラーを見せない。
  Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getString(_prefsKey);
      if (saved == null) return;
      _themeMode = ThemeMode.values.firstWhere(
        (mode) => mode.name == saved,
        // 知らない文字列が入っていたら既定へ戻す。落とさない。
        orElse: () => defaultThemeMode,
      );
      notifyListeners();
    } catch (error, stackTrace) {
      debugPrintStack(
        label: 'ThemeController.load: $error',
        stackTrace: stackTrace,
      );
    }
  }

  /// 表示モードを変えて保存する。
  ///
  /// 画面へは先に反映する。保存の完了を待たせない。
  Future<void> setThemeMode(ThemeMode mode) async {
    if (_themeMode == mode) return;
    _themeMode = mode;
    notifyListeners();

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefsKey, mode.name);
    } catch (error, stackTrace) {
      // 保存に失敗しても今回の表示は変わっている。次回起動で戻るだけ。
      debugPrintStack(
        label: 'ThemeController.save: $error',
        stackTrace: stackTrace,
      );
    }
  }
}

/// [ThemeController] をウィジェット木に配る。
///
/// 画面ごとに引数で持ち回らないための仕組み。設定画面は木の深いところに
/// あり、間の画面は表示モードに関心が無い。通り道に引数を足すのは無駄である。
///
/// `InheritedNotifier` を使うと、値の変化に応じて依存側だけが作り直される。
class ThemeScope extends InheritedNotifier<ThemeController> {
  const ThemeScope({
    super.key,
    required ThemeController controller,
    required super.child,
  }) : super(notifier: controller);

  /// 直近の [ThemeController] を取る。木の上に無ければ例外になる。
  ///
  /// 見つからないのは配線の誤りである。`null` を返して静かに壊れるより、
  /// その場で落ちたほうが原因に早く辿り着ける。
  static ThemeController of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<ThemeScope>();
    assert(scope != null, 'ThemeScope が木の上に無い（main.dart の配線を確認）');
    return scope!.notifier!;
  }
}
