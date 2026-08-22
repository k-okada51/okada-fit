import 'dart:convert';
import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/supabase.dart';
import '../domain/meal_nutrition.dart';

/// Edge Function `analyze-meal` の呼び出し（FEAT-08 §3.1）。
///
/// **Gemini を端末から直接呼ばない。** APIキーは Edge Function の環境変数に
/// しか無い（NFR-SEC-02・ADR-0011）。
///
/// UI を知らない。例外は写像せずそのまま上へ投げる。`FunctionException` は
/// `data/error_mapper.dart` が共通契約（`error_code`/`message`/`retryable`）
/// として読む。
class MealAnalyzeRepository {
  MealAnalyzeRepository({SupabaseClient? client}) : _client = client ?? supabase;

  final SupabaseClient _client;

  static const _functionName = 'analyze-meal';

  /// 写真を送り、栄養4項目を受け取る。
  ///
  /// **画像は端末外へ1回だけ出る。** 保存はどこにもしない（ADR-0003）。
  /// Storage を経由せず直接 POST する（§1・実測で 400KB 規模のため）。
  ///
  /// 自動リトライはしない。再送は EXT-01 への二重課金になる。
  /// 再試行は利用者の明示操作でのみ起きる（`02_API設計.md §1`）。
  Future<MealNutrition> analyze(Uint8List bytes, String mimeType) async {
    final response = await _client.functions.invoke(
      _functionName,
      body: {
        // 受け取った側は**この base64 をそのまま** `inline_data` に載せる。
        // 途中で再エンコードしない約束にしてある（§3.2）。
        'image_base64': base64Encode(bytes),
        'mime_type': mimeType,
      },
    );

    final data = response.data;
    if (data is! Map) {
      // 200 なのに形が違う。関数側の契約違反なので、そのまま上げて
      // `error_mapper` の「その他」へ落とす。握りつぶさない。
      throw FunctionException(
        status: response.status,
        details: data,
        reasonPhrase: 'analyze-meal の応答が Map ではありません',
      );
    }
    return MealNutrition.fromJson(Map<String, dynamic>.from(data));
  }
}
