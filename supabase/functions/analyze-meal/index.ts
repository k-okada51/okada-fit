// `analyze-meal` — FEAT-08 食事写真 → 栄養4項目（EXT-01）。
//
// 正本は `08_機能別詳細設計/FEAT-08_食事撮影タンパク質計算.md`。
//
// ## 4ステップ（`10_GeminiAPI連携.md` の処理の流れ）
//
// | # | 手順 | ここでの実装 |
// |---|---|---|
// | ① | 認証・入力検証 | JWT は Supabase が検証済み。本文は `parseAnalyzeMealRequest` |
// | ② | 入力組立 | 受領した base64 を**そのまま** `inline_data` に載せる |
// | ③ | 推論 | `callGemini`。構造化出力で受ける |
// | ④ | 応答整形 | 型 → 妥当域 → 丸め の順に通して 200 |
//
// ## 画像は保持しない（ADR-0003）
//
// **変数に持つだけである。** ハンドラを抜ければ破棄される。削除処理は要らない。
// Storage にも DB にもログにも書かない。ログに出してよいのはバイト長だけ。

import {
  AppError,
  jsonResponse,
  logJson,
  newCorrelationId,
  requireUserId,
  toErrorResponse,
} from '../_shared/errors.ts';
import { callGemini } from '../_shared/gemini.ts';
import { MEAL_ANALYZE_PROMPT } from './prompt.ts';
import { MEAL_NUTRITION_RESPONSE_SCHEMA } from './schema.ts';
import {
  assertNutritionInRange,
  parseAnalyzeMealRequest,
  parseMealNutrition,
  roundNutrition,
} from './validate.ts';

Deno.serve(async (req: Request) => {
  const correlationId = newCorrelationId();

  try {
    if (req.method !== 'POST') {
      throw new AppError(
        'ERR-VALIDATION-001',
        400,
        '不正なリクエストです。',
        false,
        `method=${req.method}`,
      );
    }

    // ① ログイン済みでなければここで止める（ERR-AUTH-001）。
    //    **本文を読むより先に見る。** 匿名の呼び出しに本文を読ませる理由が無い。
    const actor = requireUserId(req.headers.get('authorization'));

    // 本文を読む。JSON として壊れていても ERR-MEAL-001 に畳む。
    //    利用者から見れば「写真を送れなかった」であり、原因の区別に意味が無い。
    let body: unknown;
    try {
      body = await req.json();
    } catch (error) {
      throw new AppError(
        'ERR-MEAL-001',
        400,
        '写真を読み取れませんでした。選び直してください。',
        false,
        error,
      );
    }

    const input = parseAnalyzeMealRequest(body);

    // 監査ログ。**外部送信の前に**1件記録する（NFR-SEC-AUDIT-01）。
    // 送信後に書くと、送信直後に落ちた場合に記録が残らない。
    logJson({
      level: 'info',
      event: 'external_send',
      action: '外部送信',
      target: 'EXT-01',
      actor,
      occurred_at: new Date().toISOString(),
      correlation_id: correlationId,
      model: Deno.env.get('GEMINI_MODEL') ?? '-',
      // ADR-0003: 画像そのものは出さない。バイト長だけがメタ情報として許される。
      image_bytes: input.bytes.length,
      mime_type: input.mimeType,
      result: 'sending',
    });

    // ②③ 受領した base64 をそのまま渡す。再エンコードもディスク書き出しもしない。
    const { data, elapsedMs } = await callGemini({
      parts: [
        { text: MEAL_ANALYZE_PROMPT },
        { inline_data: { mime_type: input.mimeType, data: input.imageBase64 } },
      ],
      responseSchema: MEAL_NUTRITION_RESPONSE_SCHEMA,
      correlationId,
    });

    // ④ 型 → 妥当域 → 丸め。順序に意味がある。
    //    型が合わないものに範囲判定をかけても、原因が混ざるだけである。
    const nutrition = roundNutrition(
      (() => {
        const parsed = parseMealNutrition(data);
        assertNutritionInRange(parsed);
        return parsed;
      })(),
    );

    logJson({
      level: 'info',
      event: 'analyze_meal_ok',
      correlation_id: correlationId,
      actor,
      elapsed_ms: elapsedMs,
      // 推定結果は個人情報ではないので残す。写真の内容を復元はできない。
      protein_g: nutrition.protein_g,
    });

    return jsonResponse(200, nutrition);
  } catch (error) {
    return toErrorResponse(error, correlationId);
  }
});
