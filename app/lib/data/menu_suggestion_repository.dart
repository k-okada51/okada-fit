import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/supabase.dart';
import '../domain/ai_menu.dart';
import '../domain/machine.dart';

/// Edge Function `generate-menu` の呼び出し（FEAT-03 §3.1）。
///
/// **Gemini を端末から直接呼ばない**（NFR-SEC-02・ADR-0011）。
///
/// UI を知らない。例外はそのまま上へ投げる。`FunctionException` は
/// `data/error_mapper.dart` が共通契約として読む。
class MenuSuggestionRepository {
  MenuSuggestionRepository({SupabaseClient? client}) : _client = client ?? supabase;

  final SupabaseClient _client;

  static const _functionName = 'generate-menu';

  /// 今日のメニューを組ませる。
  ///
  /// **自動リトライはしない。** 再送は EXT-01 への二重課金になる（§1）。
  ///
  /// 器具が0件のときは**呼ばないこと**。AI に渡す情報が無く、課金だけが
  /// 発生する（FEAT-02 §10 #1）。呼び出し側で導線を止める。
  Future<AiMenuPlan> generate({
    required BodyPart bodyPart,
    required List<int> machineIds,
  }) async {
    final response = await _client.functions.invoke(
      _functionName,
      body: {'body_part': bodyPart.label, 'machine_ids': machineIds},
    );

    final data = response.data;
    if (data is! Map) {
      throw FunctionException(
        status: response.status,
        details: data,
        reasonPhrase: 'generate-menu の応答が Map ではありません',
      );
    }
    return AiMenuPlan.fromJson(Map<String, dynamic>.from(data));
  }
}
