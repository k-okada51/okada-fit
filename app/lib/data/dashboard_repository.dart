import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/supabase.dart';
import '../domain/dashboard.dart';

/// RPC `get_dashboard` の呼び出し（FEAT-05 §3）。
///
/// **RPC は素の値しか返さない。** 目標値・達成率は
/// `domain/dashboard.dart` が FEAT-07 の純関数を使って出す。
///
/// UI を知らない。例外はそのまま上へ投げる。
class DashboardRepository {
  DashboardRepository({SupabaseClient? client}) : _client = client ?? supabase;

  final SupabaseClient _client;

  /// ダッシュボードの材料を取る。
  ///
  /// **キャッシュしない**（§3）。当日値が変わるため、開くたびに集計し直す。
  ///
  /// 日付は端末のタイムゾーンで解決して渡す（案A・2026-08-08 確定）。
  Future<Dashboard> fetch(
    DateTime now,
    DashboardPeriod period, {
    DateTime? viewedMonth,
  }) async {
    final json = await _client.rpc(
      'get_dashboard',
      params: buildDashboardRange(now, period, viewedMonth: viewedMonth)
          .toParams(period),
    );
    return Dashboard.fromJson(Map<String, dynamic>.from(json as Map));
  }
}
