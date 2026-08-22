// Gemini API（EXT-01）の呼び出しと、失敗の写像。
//
// 正本は `03_外部連携IF/10_GeminiAPI連携.md §1` と `02_API設計.md §5.3`。
// `analyze-meal`（FEAT-08）と `generate-menu`（FEAT-03）の両方から使う。
//
// **SDK は使わない。** Deno の `fetch` で直接呼ぶ（ADR-0011）。
// **REST の JSON は snake_case。** `inline_data`・`response_mime_type` と書く。

import { AppError, logJson } from './errors.ts';

const GEMINI_ENDPOINT = 'https://generativelanguage.googleapis.com/v1beta/models';

/// 応答を待つ上限。20秒の目標（NFR-PERF-04）に2秒の余裕を残す。
///
/// ## 実測（2026-08-22・`gemini-3.7-flash`・画像33KB・thinkingLevel=medium）
///
/// | 回 | 所要 |
/// |---|---|
/// | 1回目 | **18秒を超えて中断**（`ERR-AI-TIMEOUT`） |
/// | 2回目 | 5.9秒 |
///
/// ⚠️ **18秒で足りない回がある。** ばらつきが大きく、2回のうち1回が超えた。
/// それでも 18 秒を維持するのは、NFR-PERF-04（≤20秒）が上限だからである。
/// 伸ばすと NFR に反し、待たされた末に失敗する体験も変わらない。
///
/// 頻発するようなら、上げるのは待ち時間ではなく `thinkingLevel` を下げる側で
/// 調整する（ADR-0018 の残課題）。
export const GEMINI_TIMEOUT_MS = 18_000;

/// 思考量。**値は確定**（ADR-0018）。`high` は使わない。
///
/// ⚠️ **置き場所は ADR-0018 の記述と違う。**
///
/// ADR-0018 は `generationConfig.thinking_level` としていたが、`:generateContent`
/// はそのフィールドを知らない（実測・2026-08-22）。
///
/// ```text
/// Unknown name "thinking_level" at 'generation_config': Cannot find field.
/// ```
///
/// 公式ドキュメントの `generation_config.thinking_level` という例は
/// **`/v1beta/interactions`（別エンドポイント）のもの**である。本PJが使う
/// `:generateContent` では `thinkingConfig` の下に入る。
export const THINKING_LEVEL = 'medium';

export interface GeminiPart {
  text?: string;
  // deno-lint-ignore camelcase
  inline_data?: { mime_type: string; data: string };
}

export interface GeminiCallInput {
  parts: GeminiPart[];
  /// `generationConfig.response_schema` に載せる JSON Schema。
  responseSchema: unknown;
  correlationId: string;
  /// 役割・制約の指示。省略すると付けない（FEAT-08 は使わない）。
  systemInstruction?: string;
  /// 応答を待つ上限。省略すると [GEMINI_TIMEOUT_MS]。
  ///
  /// 機能ごとに NFR が違う。FEAT-08 は ≤20秒、FEAT-03 は ≤15秒。
  timeoutMs?: number;
}

export interface GeminiCallResult {
  /// `candidates[0].content.parts[0].text` を `JSON.parse` したもの。
  data: unknown;
  /// ログ用。`usageMetadata` の実測はモデル既定値の見直しに使う（ADR-0025）。
  usage: unknown;
  finishReason: unknown;
  elapsedMs: number;
}

/// Gemini を1往復呼び、構造化出力を取り出す。
///
/// **自動リトライはしない**（従量課金のため・`02_API設計.md §1`）。
/// 429 `rate_limit_exceeded` の1回だけの再試行は呼び出し側の判断に委ねる。
export async function callGemini(input: GeminiCallInput): Promise<GeminiCallResult> {
  const apiKey = Deno.env.get('GEMINI_API_KEY');
  const model = Deno.env.get('GEMINI_MODEL');

  // 設定漏れをここで止める。未設定のまま呼ぶと 401 が返り、
  // 「キーが無効」と「キーが未設定」の区別がつかなくなる。
  if (!apiKey || !model) {
    throw new AppError(
      'ERR-AI-FAIL',
      500,
      '解析に失敗しました。写真を撮り直してください。',
      false,
      `GEMINI_API_KEY/GEMINI_MODEL 未設定（key=${!!apiKey} model=${!!model}）`,
    );
  }

  const startedAt = performance.now();
  let response: Response;
  try {
    response = await fetch(`${GEMINI_ENDPOINT}/${model}:generateContent`, {
      method: 'POST',
      headers: {
        'content-type': 'application/json',
        // 環境変数のみ。コードにも端末にも置かない（NFR-SEC-02）。
        'x-goog-api-key': apiKey,
      },
      body: JSON.stringify({
        contents: [{ role: 'user', parts: input.parts }],
        // 付けないときはキーごと出さない。空の指示を送らない。
        ...(input.systemInstruction === undefined
          ? {}
          : { systemInstruction: { parts: [{ text: input.systemInstruction }] } }),
        generationConfig: {
          response_mime_type: 'application/json',
          response_schema: input.responseSchema,
          // `thinkingBudget`（旧）とは併用しない。併用すると 400 になる。
          thinkingConfig: { thinkingLevel: THINKING_LEVEL },
        },
      }),
      signal: AbortSignal.timeout(input.timeoutMs ?? GEMINI_TIMEOUT_MS),
    });
  } catch (error) {
    // 中断（タイムアウト）と接続断をまとめて 504 にする。
    // どちらも「時間内に解析できなかった」であり、利用者の取れる手は同じ。
    throw new AppError(
      'ERR-AI-TIMEOUT',
      504,
      '時間内に解析できませんでした。もう一度お試しください。',
      false,
      error,
    );
  }

  const elapsedMs = Math.round(performance.now() - startedAt);
  const bodyText = await response.text();

  if (!response.ok) throw mapGeminiHttpError(response.status, bodyText);

  let envelope: GeminiEnvelope;
  try {
    envelope = JSON.parse(bodyText) as GeminiEnvelope;
  } catch (error) {
    throw new AppError('ERR-AI-SCHEMA', 502, kUnreadable, false, error);
  }

  const text = envelope.candidates?.[0]?.content?.parts?.[0]?.text;
  if (typeof text !== 'string') {
    // 構造化出力が空で返る事例がある（FEAT-08 §10 #18）。
    // 呼び出し自体は 200 なので ERR-AI-SCHEMA（502）で扱う。
    throw new AppError('ERR-AI-SCHEMA', 502, kUnreadable, false, {
      reason: 'parts[0].text が無い',
      finishReason: envelope.candidates?.[0]?.finishReason,
      promptFeedback: envelope.promptFeedback,
    });
  }

  let data: unknown;
  try {
    data = JSON.parse(text);
  } catch (error) {
    throw new AppError('ERR-AI-SCHEMA', 502, kUnreadable, false, error);
  }

  logJson({
    level: 'info',
    event: 'gemini_ok',
    correlation_id: input.correlationId,
    model,
    elapsed_ms: elapsedMs,
    // ADR-0025 のクローズ条件。実際の消費トークン数を記録する。
    usage: envelope.usageMetadata,
    finish_reason: envelope.candidates?.[0]?.finishReason,
  });

  return {
    data,
    usage: envelope.usageMetadata,
    finishReason: envelope.candidates?.[0]?.finishReason,
    elapsedMs,
  };
}

const kUnreadable = 'うまく読み取れませんでした。写真を撮り直してください。';

interface GeminiEnvelope {
  candidates?: Array<{
    content?: { parts?: Array<{ text?: string }> };
    finishReason?: string;
  }>;
  usageMetadata?: unknown;
  promptFeedback?: unknown;
}

/// Gemini の HTTP 失敗を本PJの ERR へ写す（`02_API設計.md §5.3`）。
///
/// **HTTP ステータスだけで判定しない。** 429 は2種類あり `retryable` が逆になる。
/// `error.status` を見ずに畳むと、日次クォータ切れをバックオフで叩き続ける。
///
/// 純関数にしてあるのでテストから直接呼べる。
export function mapGeminiHttpError(status: number, bodyText: string): AppError {
  const errorStatus = readErrorStatus(bodyText);

  // 400 は2種類。課金無効だけを 402 に分ける（ADR-0011）。
  if (status === 400 && errorStatus === 'failed_precondition') {
    return new AppError(
      'ERR-AI-CREDIT',
      402,
      'AI機能を一時的に利用できません。時間をおいてお試しください。',
      false,
      bodyText,
    );
  }

  if (status === 429) {
    // 日次クォータは当日回復しない。再試行を促さない。
    if (errorStatus === 'quota_exceeded') {
      return new AppError(
        'ERR-AI-QUOTA',
        429,
        '本日の利用上限に達しました。明日以降にお試しください。',
        false,
        bodyText,
      );
    }
    return new AppError(
      'ERR-AI-RATE',
      429,
      '混み合っています。少し待ってからお試しください。',
      true,
      bodyText,
    );
  }

  if (status === 504 || errorStatus === 'deadline_exceeded') {
    return new AppError(
      'ERR-AI-TIMEOUT',
      504,
      '時間内に解析できませんでした。もう一度お試しください。',
      false,
      bodyText,
    );
  }

  // 401/403（キー無効・権限なし）・404（モデル不明）・500/503（API障害）・
  // その他の 400。いずれも利用者にできることは同じなので1つに畳む。
  return new AppError(
    'ERR-AI-FAIL',
    500,
    '解析に失敗しました。写真を撮り直してください。',
    false,
    `http=${status} status=${errorStatus ?? '-'} body=${bodyText}`,
  );
}

/// 応答本文から `error.status` を取り出す。読めなければ `null`。
function readErrorStatus(bodyText: string): string | null {
  try {
    const parsed = JSON.parse(bodyText) as { error?: { status?: unknown } };
    const status = parsed.error?.status;
    return typeof status === 'string' ? status.toLowerCase() : null;
  } catch {
    return null;
  }
}
