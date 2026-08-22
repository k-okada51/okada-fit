import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/supabase.dart';
import '../domain/meal_nutrition.dart';

/// `meal_logs` の書き込みと当日分の読み出し（FEAT-08 §3.3）。
///
/// **PostgREST を直接叩く。** RPC を挟まない。
///
/// UI を知らない。例外はそのまま上へ投げる。
class MealLogRepository {
  MealLogRepository({SupabaseClient? client}) : _client = client ?? supabase;

  final SupabaseClient _client;

  /// 1食分を記録する。
  ///
  /// **`user_id` を送らない。** 列 DEFAULT `auth.uid()` が入れる
  /// （マイグレーション `20260822100000`）。他人の値を送っても RLS の
  /// `WITH CHECK (user_id = auth.uid())` が弾く。
  ///
  /// **冪等ではない。** 連投すると2行入る（2026-08-22 決定・UI抑止のみ）。
  /// 二重登録の防止は画面側でボタンを無効化して行う。
  Future<int> insert(MealNutrition nutrition, {required DateTime eatenAt}) async {
    final row = await _client
        .from('meal_logs')
        .insert(nutrition.toMealLogRow(eatenAt: eatenAt))
        .select('id')
        .single();
    return (row['id'] as num).toInt();
  }

  /// 当日の記録を新しい順に読む（SCR-04 の当日一覧・§7）。
  ///
  /// 日付は**端末のタイムゾーンで決めた当日**を渡す（ADR-0014）。
  /// サーバの `CURRENT_DATE` に任せると UTC で切られて夜間にずれる。
  ///
  /// 行を本人に絞るのは RLS。ここに `user_id` の条件を書かない。
  Future<List<MealLogEntry>> fetchByDate(DateTime date) async {
    final rows = await _client
        .from('meal_logs')
        .select('id, calories_kcal, protein_g, sugar_g, fat_g, eaten_time')
        .eq('eaten_date', _formatDate(date))
        // 時刻は null 可。null を最後に回す。
        .order('eaten_time', ascending: false, nullsFirst: false)
        .order('id', ascending: false);

    return [
      for (final row in rows) MealLogEntry.fromJson(Map<String, dynamic>.from(row)),
    ];
  }
}

/// 当日一覧の1行。
class MealLogEntry {
  const MealLogEntry({
    required this.id,
    required this.caloriesKcal,
    required this.proteinG,
    required this.sugarG,
    required this.fatG,
    required this.eatenTime,
  });

  final int id;
  final double caloriesKcal;
  final double proteinG;
  final double sugarG;
  final double fatG;

  /// `HH:mm`。列は null 可。
  final String? eatenTime;

  factory MealLogEntry.fromJson(Map<String, dynamic> json) => MealLogEntry(
    id: (json['id'] as num).toInt(),
    caloriesKcal: _asDouble(json['calories_kcal']),
    proteinG: _asDouble(json['protein_g']),
    sugarG: _asDouble(json['sugar_g']),
    fatG: _asDouble(json['fat_g']),
    // `time` は `HH:MM:SS` で返る。表示は分までなので先頭5文字を採る。
    eatenTime: switch (json['eaten_time']) {
      final String v when v.length >= 5 => v.substring(0, 5),
      final String v => v,
      _ => null,
    },
  );
}

/// `numeric` は JSON で文字列になりうる（ADR-0022）。
double _asDouble(Object? value) {
  if (value is num) return value.toDouble();
  if (value is String) return double.tryParse(value) ?? 0;
  return 0;
}

String _formatDate(DateTime at) =>
    '${at.year.toString().padLeft(4, '0')}-'
    '${at.month.toString().padLeft(2, '0')}-'
    '${at.day.toString().padLeft(2, '0')}';
