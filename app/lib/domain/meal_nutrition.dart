/// 食事1回分の栄養推定（FEAT-08）。
///
/// UI にも Supabase にも依存しない。ここに置いたものは全て単体テストの対象
/// （NFR-QUAL-01）。正本は `FEAT-08_食事撮影タンパク質計算.md §3.2`・`§4`。
library;

/// Edge Function `analyze-meal` が返す1件。
///
/// **値は AI 出力のまま。利用者は修正できない**（ADR-0015）。
/// 丸め（小数第1位・ADR-0022）は Edge Function 側で済んでいる。
/// ここで丸め直すと、画面に出す値と関数が返した値がずれる余地を作る。
class MealNutrition {
  const MealNutrition({
    required this.foodName,
    required this.dishNames,
    required this.caloriesKcal,
    required this.proteinG,
    required this.sugarG,
    required this.fatG,
  });

  /// 写真全体の推定名称。**保存しない**（ADR-0003・§4 の `toMealLogRow`）。
  final String foodName;

  /// 写真に写る個々の料理名。こちらも保存しない。表示のためだけに持つ。
  final List<String> dishNames;

  final double caloriesKcal;

  /// 本機能の主目的。ADR-0001 の実測 MAPE は 10.5%（外食）。
  final double proteinG;

  final double sugarG;

  /// ⚠️ **既知の弱点。** 外食の MAPE は 32.7%（§4）。揚げ油・ドレッシングなど
  /// 見えない油を拾えない。画面では注記を添える（§7）。
  final double fatG;

  factory MealNutrition.fromJson(Map<String, dynamic> json) => MealNutrition(
    foodName: (json['food_name'] as String? ?? '').trim(),
    dishNames: [
      for (final name in (json['dish_names'] as List? ?? const []))
        if (name is String && name.trim().isNotEmpty) name.trim(),
    ],
    caloriesKcal: _asDouble(json['calories_kcal']),
    proteinG: _asDouble(json['protein_g']),
    sugarG: _asDouble(json['sugar_g']),
    fatG: _asDouble(json['fat_g']),
  );

  /// `meal_logs` へ送る形（§4 `toMealLogRow`）。
  ///
  /// **栄養4項目と日時だけを写す。** `food_name`・`dish_names` は写さない。
  /// 料理名を保持しないのは ADR-0003 の決めである。
  ///
  /// `user_id` も送らない。列 DEFAULT `auth.uid()` が入れる。
  Map<String, dynamic> toMealLogRow({
    required DateTime eatenAt,
  }) => {
    'calories_kcal': caloriesKcal,
    'protein_g': proteinG,
    'sugar_g': sugarG,
    'fat_g': fatG,
    // 端末のタイムゾーンで当日を決める（ADR-0014）。サーバ時刻を使わない。
    // Supabase は UTC なので `CURRENT_DATE` に任せると日付がずれる。
    'eaten_date': _formatDate(eatenAt),
    'eaten_time': _formatTime(eatenAt),
  };
}

/// `numeric` は JSON で文字列になりうる。受け口を1か所に集約する（ADR-0022）。
double _asDouble(Object? value) {
  if (value is num) return value.toDouble();
  if (value is String) return double.tryParse(value) ?? 0;
  return 0;
}

/// `YYYY-MM-DD`。`toIso8601String` は時刻まで付くので使わない。
String _formatDate(DateTime at) =>
    '${at.year.toString().padLeft(4, '0')}-'
    '${at.month.toString().padLeft(2, '0')}-'
    '${at.day.toString().padLeft(2, '0')}';

/// `HH:mm`。列は `time` 型。秒は持たない。
String _formatTime(DateTime at) =>
    '${at.hour.toString().padLeft(2, '0')}:${at.minute.toString().padLeft(2, '0')}';

/// Atwater 係数（kcal/g）。エネルギー換算の一般値。
const double kAtwaterProtein = 4;
const double kAtwaterSugar = 4;
const double kAtwaterFat = 9;

/// 注意を出す乖離の閾値（§4 `[仮]`）。
///
/// **超えても保存はブロックしない。** AI 推定は本来ずれる。機械的に拒否すると
/// 誤検知のほうが多くなる。出すのは注意書きだけである。
const double kAtwaterWarnThreshold = 0.40;

/// 栄養値の内部整合の目安（§4 `atwaterDeviation`）。
///
/// ```text
/// est = 4*protein_g + 4*sugar_g + 9*fat_g
/// dev = |calories_kcal - est| / max(est, 1)
/// ```
///
/// 分母に `max(est, 1)` を置くのは、`est` が 0 のときに 0 除算になるため。
double atwaterDeviation(MealNutrition n) {
  final est =
      kAtwaterProtein * n.proteinG +
      kAtwaterSugar * n.sugarG +
      kAtwaterFat * n.fatG;
  final denominator = est < 1 ? 1.0 : est;
  return (n.caloriesKcal - est).abs() / denominator;
}

/// 注意書きを出すか（§7 の「Atwater 乖離時は警告色の Card」）。
bool isAtwaterInconsistent(MealNutrition n) =>
    atwaterDeviation(n) > kAtwaterWarnThreshold;
