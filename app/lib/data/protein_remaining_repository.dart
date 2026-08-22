import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/supabase.dart';
import '../domain/protein_remaining.dart';

/// RPC `get_protein_remaining` の呼び出し（FEAT-09 §3）。
///
/// **RPC は素の値しか返さない。** 目標・残量・提示食品は
/// `domain/protein_remaining.dart` が計算する（§4・2026-08-08 確定）。
///
/// UI を知らない。例外はそのまま上へ投げる。
class ProteinRemainingRepository {
  ProteinRemainingRepository({SupabaseClient? client})
      : _client = client ?? supabase;

  final SupabaseClient _client;

  /// 当日の残量の材料を取る。
  ///
  /// **`p_target_date` は端末のタイムゾーンで決めて渡す**（ADR-0014）。
  /// RPC 内で `CURRENT_DATE` を呼ばない約束にしてある。
  ///
  /// **キャッシュしない。** SCR-04 で記録した直後は必ず呼び直す。
  /// 古い残量を出すと、記録したのに減っていないように見える（§3）。
  Future<ProteinRemainingSource> fetch(DateTime now) async {
    final json = await _client.rpc(
      'get_protein_remaining',
      params: {'p_target_date': todayOnDevice(now)},
    );
    return ProteinRemainingSource.fromJson(Map<String, dynamic>.from(json as Map));
  }
}
