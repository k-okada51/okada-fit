/// タンパク質の残量と、不足分を補う食品の提示（FEAT-09）。
///
/// **算出はすべてここで行う**（§4・2026-08-08 確定）。RPC は `weight_kg`・
/// `intake_g`・候補の母集合を素のまま返すだけで、計算はしない。
///
/// UI にも Supabase にも依存しない。全て単体テストの対象（NFR-QUAL-01）。
library;

import 'nutrition.dart';

/// 提示する食品の件数（§4 L4 `[仮]`）。
///
/// SCR-01 のカード内に折り返さず収まる件数として決めた値。業務上の根拠は無い。
const int kSuggestedFoodCount = 3;

/// RPC `get_protein_remaining` が返す候補1件。
///
/// `protein_amount` は **1食分あたり**のタンパク質量（ADR-0012）。
/// 100g あたりでも1個あたりでもない。残量と同じ尺度なので換算せずに比べられる。
class FoodCandidate {
  const FoodCandidate({
    required this.id,
    required this.foodName,
    required this.proteinAmount,
  });

  final int id;
  final String foodName;
  final double proteinAmount;

  factory FoodCandidate.fromJson(Map<String, dynamic> json) => FoodCandidate(
    id: (json['id'] as num).toInt(),
    foodName: (json['food_name'] as String? ?? '').trim(),
    proteinAmount: _asDouble(json['protein_amount']),
  );
}

/// RPC の戻り値そのまま。**計算済みの値は含まれない。**
class ProteinRemainingSource {
  const ProteinRemainingSource({
    required this.weightKg,
    required this.intakeG,
    required this.candidates,
  });

  /// `users.weight_kg`。未設定は `null`（業務上は正常）。
  final double? weightKg;

  /// 当日の `SUM(meal_logs.protein_g)`。記録なしは 0。
  final double intakeG;

  /// RULE-005 の母集合。並べ替えられていない（`id` 昇順）。
  final List<FoodCandidate> candidates;

  factory ProteinRemainingSource.fromJson(Map<String, dynamic> json) =>
      ProteinRemainingSource(
        weightKg: json['weight_kg'] == null ? null : _asDouble(json['weight_kg']),
        intakeG: _asDouble(json['intake_g']),
        candidates: [
          for (final row in (json['foods_candidates'] as List? ?? const []))
            FoodCandidate.fromJson(Map<String, dynamic>.from(row as Map)),
        ],
      );
}

/// 画面に出す形。**ウィジェットで再計算しない**（§4 L5）。
sealed class ProteinRemaining {
  const ProteinRemaining();
}

/// 体重が未設定。ERR-PROFILE-020 へ写す（FEAT-07 §6）。
///
/// **エラーではない。** FEAT-06 未実施という正常な業務状態である。
final class ProteinRemainingUnset extends ProteinRemaining {
  const ProteinRemainingUnset();
}

/// 体重が不正値。ERR-PROFILE-021 へ写す。データ不整合。
final class ProteinRemainingInvalid extends ProteinRemaining {
  const ProteinRemainingInvalid(this.weightKg);
  final double weightKg;
}

/// 算出できた。
final class ProteinRemainingOk extends ProteinRemaining {
  const ProteinRemainingOk({
    required this.targetG,
    required this.intakeG,
    required this.remainingG,
    required this.suggestions,
  });

  /// 1日の目標(g)。RULE-001。
  final double targetG;

  /// 当日の摂取量(g)。
  final double intakeG;

  /// 残量(g)。**0未満にならない**（RULE-002 の0クランプ）。
  final double remainingG;

  /// 不足分を補う食品（最大 [kSuggestedFoodCount] 件）。
  ///
  /// 達成済み（`remainingG <= 0`）なら空になる。
  final List<FoodCandidate> suggestions;

  /// 目標を超えた分。**表示するかは画面の判断**。
  ///
  /// `remainingG` は0で止めるため、超過量はここから取る（§4 L3）。
  double get excessG => intakeG > targetG ? roundProteinG(intakeG - targetG) : 0;

  bool get isAchieved => remainingG <= 0;
}

/// RPC の戻り値から画面に出す形を作る（§4 L3〜L5）。
///
/// 体重の判定は [calcTargetProteinG] に委ねる。**同じ判定を2か所に書かない**
/// （FEAT-07 §4.5 案(b)）。
ProteinRemaining computeProteinRemaining(ProteinRemainingSource source) {
  final target = calcTargetProteinG(source.weightKg);

  switch (target) {
    case ProteinTargetUnset():
      return const ProteinRemainingUnset();
    case ProteinTargetInvalid(:final weightKg):
      return ProteinRemainingInvalid(weightKg);
    case ProteinTargetOk(:final targetG):
      // L5: 丸めは最後に1回だけ。**丸める前の差を丸める。**
      // 丸め済みどうしを引くと、表示値どうしの引き算と 0.1g ずれうる。
      final rawRemaining = targetG - source.intakeG;
      final remainingG = rawRemaining <= 0 ? 0.0 : roundProteinG(rawRemaining);

      return ProteinRemainingOk(
        targetG: targetG,
        intakeG: roundProteinG(source.intakeG),
        remainingG: remainingG,
        suggestions: selectFoods(source.candidates, remainingG),
      );
  }
}

/// 不足分を補う食品を選ぶ（§4 L4・RULE-005）。
///
/// **単品N件方式。** 組み合わせで残量をぴったり埋める探索（部分和）はしない。
/// 提示するのは「これ1つでどれだけ埋まるか」であって、献立ではない。
///
/// 並びは3段。同値でも順序が決まるようにしてある。
///
/// | # | 規則 | 意図 |
/// |---|---|---|
/// | ① | `abs(protein_amount − remaining)` 昇順 | 残量に近いものを先に |
/// | ② | `protein_amount` 降順 | 同差なら多い方を |
/// | ③ | `id` 昇順 | それでも同値なら決定性を担保 |
List<FoodCandidate> selectFoods(
  List<FoodCandidate> candidates,
  double remainingG,
) {
  // 達成済みなら選ばない。**空配列を返す**（L4）。
  if (remainingG <= 0) return const [];

  // 0g の行は候補にしない。補えないものを勧めても意味が無い。
  final pool = [
    for (final food in candidates)
      if (food.proteinAmount > 0) food,
  ];

  pool.sort((a, b) {
    final diff = (a.proteinAmount - remainingG)
        .abs()
        .compareTo((b.proteinAmount - remainingG).abs());
    if (diff != 0) return diff;
    final amount = b.proteinAmount.compareTo(a.proteinAmount);
    if (amount != 0) return amount;
    return a.id.compareTo(b.id);
  });

  return pool.take(kSuggestedFoodCount).toList(growable: false);
}

/// 端末のタイムゾーンの当日（§4 L1・ADR-0014）。
///
/// **サーバ時刻を使わない。** Supabase は UTC なので `CURRENT_DATE` に任せると
/// 深夜の記録が前日に集計される。
String todayOnDevice(DateTime now) =>
    '${now.year.toString().padLeft(4, '0')}-'
    '${now.month.toString().padLeft(2, '0')}-'
    '${now.day.toString().padLeft(2, '0')}';

double _asDouble(Object? value) {
  if (value is num) return value.toDouble();
  if (value is String) return double.tryParse(value) ?? 0;
  return 0;
}
