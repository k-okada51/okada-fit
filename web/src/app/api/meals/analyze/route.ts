import { NextRequest, NextResponse } from 'next/server';
import { generateObject, NoObjectGeneratedError } from 'ai';
import { nutritionSchema, MEAL_VISION_MODEL, MEAL_PROMPT } from '@/lib/nutrition';

// POST /api/meals/analyze
// 食事画像 → AI Gateway(Gemini 3.5 Flash) → 栄養価(構造化出力)。
// 画像はモデルに送るのみで保存しない（ADR-0003）。サーバー側でキーを秘匿（NFR-SEC-02）。
export const runtime = 'nodejs';
export const maxDuration = 30; // AI応答の上限（NFR-PERF-04）

export async function POST(req: NextRequest) {
  if (!process.env.AI_GATEWAY_API_KEY) {
    return NextResponse.json({ error_code: 'ERR-AI-CONFIG', message: 'AIの設定が未完了です', retryable: false }, { status: 500 });
  }

  let bytes: Buffer;
  let mediaType = 'image/jpeg';
  try {
    const form = await req.formData();
    const file = form.get('image');
    if (!(file instanceof File)) {
      return NextResponse.json({ error_code: 'ERR-VALIDATION-001', message: '画像が送信されていません', retryable: false }, { status: 400 });
    }
    mediaType = file.type || 'image/jpeg';
    bytes = Buffer.from(await file.arrayBuffer());
  } catch {
    return NextResponse.json({ error_code: 'ERR-VALIDATION-001', message: '画像を読み取れませんでした', retryable: false }, { status: 400 });
  }

  try {
    const result = await generateObject({
      model: MEAL_VISION_MODEL,
      schema: nutritionSchema,
      messages: [
        {
          role: 'user',
          content: [
            { type: 'text', text: MEAL_PROMPT },
            { type: 'file', mediaType, data: bytes },
          ],
        },
      ],
      providerOptions: { google: { thinkingConfig: { thinkingLevel: 'high' } } },
      abortSignal: AbortSignal.timeout(28_000),
    });
    return NextResponse.json(result.object);
  } catch (err) {
    const status = (err as { statusCode?: number })?.statusCode;
    if (NoObjectGeneratedError.isInstance(err)) {
      return NextResponse.json({ error_code: 'ERR-AI-FAIL', message: '料理を判別できませんでした。撮り直してください。', retryable: false }, { status: 422 });
    }
    if (status === 402) {
      return NextResponse.json({ error_code: 'ERR-AI-CREDIT', message: 'AIの利用枠が不足しています', retryable: false }, { status: 402 });
    }
    if (status === 429) {
      return NextResponse.json({ error_code: 'ERR-AI-RATE', message: '混み合っています。少し待って再試行してください', retryable: true }, { status: 429 });
    }
    return NextResponse.json({ error_code: 'ERR-AI-FAIL', message: '解析に失敗しました', retryable: false }, { status: 502 });
  }
}
