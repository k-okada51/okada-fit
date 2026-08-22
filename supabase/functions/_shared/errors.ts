// Edge Function 共通のエラー契約（`02_API設計.md §5.1`）。
//
// Edge Function が返す形は3フィールドで固定する。
//
//   { "error_code": "ERR-…", "message": "利用者向け日本語", "retryable": true }
//
// Flutter 側は `FunctionException` の本文をそのまま採用する。写像しない。
//
// **利用者向けメッセージに技術詳細を書かない**（§5.1）。SQLSTATE・例外文言・
// モデルID が該当する。原因は `logJson` でログにだけ残す。

/// 利用者に返すエラー。`throw` して `toResponse` で受ける。
///
/// `cause` はログ専用である。応答には出さない。
export class AppError extends Error {
  constructor(
    readonly errorCode: string,
    readonly status: number,
    /// 利用者向けの日本語。技術詳細を含めない。
    readonly userMessage: string,
    readonly retryable: boolean,
    /// ログにだけ出す原因。スタックや外部APIの生応答など。
    readonly detail?: unknown,
  ) {
    super(`${errorCode}: ${userMessage}`);
    this.name = 'AppError';
  }

  toResponse(): Response {
    return jsonResponse(this.status, {
      error_code: this.errorCode,
      message: this.userMessage,
      retryable: this.retryable,
    });
  }
}

export function jsonResponse(status: number, body: unknown): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { 'content-type': 'application/json; charset=utf-8' },
  });
}

/// 想定外の例外を最後に受ける。
///
/// **素の例外を利用者に見せない。** メッセージにファイルパスや内部構造が
/// 混ざりうるため、`ERR-AI-FAIL` に畳んで詳細はログへ送る。
export function toErrorResponse(error: unknown, correlationId: string): Response {
  if (error instanceof AppError) {
    logJson({
      level: error.status >= 500 ? 'error' : 'warn',
      event: 'error',
      correlation_id: correlationId,
      error_code: error.errorCode,
      detail: summarize(error.detail),
    });
    return error.toResponse();
  }

  logJson({
    level: 'error',
    event: 'unhandled',
    correlation_id: correlationId,
    detail: summarize(error),
  });
  return jsonResponse(500, {
    error_code: 'ERR-AI-FAIL',
    message: '解析に失敗しました。写真を撮り直してください。',
    retryable: false,
  });
}

/// ログの1行。**1行1JSON**（`05_ログ設計.md`）。
///
/// ⚠️ **画像・base64・画像を復元しうるデータを渡さないこと**（ADR-0003）。
/// 渡してよいのはバイト長などのメタ情報だけである。
export function logJson(fields: Record<string, unknown>): void {
  console.log(JSON.stringify({ service: 'okada-fit-fn', ...fields }));
}

/// ログに載せる形へ縮める。長い生応答をそのまま流さない。
function summarize(value: unknown): string {
  if (value === undefined || value === null) return '';
  const text = value instanceof Error
    ? `${value.name}: ${value.message}`
    : typeof value === 'string'
    ? value
    : JSON.stringify(value);
  // 1行が長すぎるとログ側で切られ、かえって読めなくなる。
  return text.length > 600 ? `${text.slice(0, 600)}…` : text;
}

/// リクエストを1本追跡するためのID（`10_GeminiAPI連携.md` の手順①）。
export function newCorrelationId(): string {
  return crypto.randomUUID();
}

/// 呼び出した本人の uuid を取り出す。監査ログの `actor` になる。
///
/// **署名は検証しない。** Supabase が `verify_jwt` で検証済みのものだけが
/// ここへ届く。二重に検証しても得るものが無い。
/// 取り出せなければ `unknown` にする。監査ログのために処理を止めない。
export function actorFromAuthHeader(header: string | null): string {
  try {
    const token = (header ?? '').replace(/^Bearer\s+/i, '');
    const payload = token.split('.')[1];
    if (!payload) return 'unknown';
    const json = atob(payload.replace(/-/g, '+').replace(/_/g, '/'));
    return (JSON.parse(json).sub as string | undefined) ?? 'unknown';
  } catch {
    return 'unknown';
  }
}
