import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/supabase.dart';
import '../domain/csv_import.dart';
import '../domain/food.dart';

/// `import_foods` の戻り値（FEAT-10 §3.2）。
///
/// `inserted_count + skipped_count` は送った行数と一致する。
/// 突き合わせれば取りこぼしを検知できる。
class ImportFoodsResult {
  const ImportFoodsResult({
    required this.insertedCount,
    required this.skippedCount,
  });

  /// 新しく入った件数。
  final int insertedCount;

  /// **既存と同名だったためスキップした件数。** エラーではない（§3.2）。
  final int skippedCount;

  /// RPC の応答から作る。
  ///
  /// `RETURNS TABLE` の関数なので PostgREST は**要素1つの配列**で返す。
  /// 実装差でオブジェクトが直に来ることもあるため、どちらでも読めるようにする。
  factory ImportFoodsResult.fromRpc(dynamic data) {
    final row = data is List
        ? (data.isEmpty ? const <String, dynamic>{} : data.first)
        : data;
    if (row is! Map) return const ImportFoodsResult(insertedCount: 0, skippedCount: 0);
    return ImportFoodsResult(
      insertedCount: _asInt(row['inserted_count']),
      skippedCount: _asInt(row['skipped_count']),
    );
  }
}

/// `bigint` を `int` へ直す。桁が大きいと文字列で返ることがある。
int _asInt(Object? value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  if (value is String) return int.tryParse(value) ?? 0;
  return 0;
}

/// 食品マスタ `foods` の読み書き（FEAT-10）。
///
/// 取込は RPC 1本、一覧・編集・削除は PostgREST 直接という**2経路**になる。
/// 取込だけ RPC なのは、件数の内訳（取込／スキップ）を1往復で返せるのが
/// DB関数だけだからである（§5）。編集・削除のために RPC を増やさない（§7）。
///
/// UI を知らない。`BuildContext` を受け取らない。
/// 例外は写像せずそのまま上へ投げる。利用者向け文言への変換は
/// `data/error_mapper.dart`（W-05）の担当で、呼ぶのは画面側。
/// `profile_repository.dart` と同じ約束にしてある。
class FoodRepository {
  /// [client] を渡さない場合は初期化済みの共有クライアントを使う。
  /// テストから差し替えられるよう引数に開けてある。
  FoodRepository({SupabaseClient? client}) : _client = client ?? supabase;

  final SupabaseClient _client;

  /// 扱う列。`foods` は3列しか無いので全部取る。
  static const _columns = 'id, name, protein_amount';

  /// 食品マスタを全件読む。並びは `name` の昇順（§7）。
  ///
  /// **`user_id` を条件に書かない。** `foods` は共通マスタで、RLS は
  /// `TO authenticated USING (true)`（`01_DB物理設計.md §3.4`）。
  /// 所有者による絞り込みが存在しないため、絞る条件そのものが無い。
  Future<List<Food>> fetchFoods() async {
    final rows = await _client.from('foods').select(_columns).order('name');
    return rows.map(Food.fromJson).toList();
  }

  /// 検証済みの行を一括で取り込む（§3.2・§5）。
  ///
  /// **往復は1回だけ。** 1行1 INSERT にすると数百往復になり、
  /// NFR-PERF-05（≤5秒）を満たせない（§10-5）。
  ///
  /// 方式は `ON CONFLICT (name) DO NOTHING`（ADR-0007）。
  /// 既存と同名の行は `protein_amount` が違っても**上書きしない**。
  ///
  /// 関数内で失敗すると自動ROLLBACKされ**1件も入らない**（ERR-FOOD-007）。
  /// 部分コミットは起きない。
  ///
  /// [rows] が空のときは呼ばない。空配列を送っても DB は何もせず、
  /// 往復だけが無駄になる。判断は呼び出し側（画面）で行う。
  Future<ImportFoodsResult> importFoods(List<FoodRow> rows) async {
    if (rows.isEmpty) {
      throw ArgumentError.value(rows, 'rows', '取り込む行がありません');
    }
    final data = await _client.rpc<dynamic>(
      'import_foods',
      params: {'p_rows': rows.map((row) => row.toJson()).toList()},
    );
    return ImportFoodsResult.fromRpc(data);
  }

  /// 食品を1件直す（§7）。更新後の行を返す。
  ///
  /// **PostgREST 直接で更新する。RPC は増やさない。**
  /// `name` は正規化してから送る（[buildFoodUpdate]）。取込と保存値の作り方を揃え、
  /// 一覧から直した行だけ正規化されていない、という状態を作らないため。
  ///
  /// 改名した先が既存と重なると `PostgrestException(23505)` が上がる
  /// （`uq_foods_name` 違反・ERR-FOOD-006）。写像は `error_mapper.dart` が持つ。
  Future<Food> updateFood(
    int id, {
    required String name,
    required String proteinAmount,
  }) async {
    final patch = buildFoodUpdate(name: name, proteinAmount: proteinAmount);
    final row = await _client
        .from('foods')
        .update(patch)
        .eq('id', id)
        // 更新した行をそのまま受け取る。正規化と丸めの結果を画面へ返すため。
        .select(_columns)
        .single();
    return Food.fromJson(row);
  }

  /// 食品を1件消す（§7）。
  ///
  /// **消しても過去の `meal_logs` は消えない。** `meal_logs` は栄養値を実体で
  /// 持ち、`foods` を参照しない（ADR-0013）。FK も張っていない（§4-3）。
  /// したがって削除で過去の記録が壊れることは無い。
  ///
  /// 影響するのは FEAT-09 の不足分提示（RULE-005）の候補だけである。
  Future<void> deleteFood(int id) async {
    await _client.from('foods').delete().eq('id', id);
  }
}
