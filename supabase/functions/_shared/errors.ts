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

/// 呼び出した本人の uuid を返す。ログインしていなければ 401 で止める。
///
/// ## なぜ要るか
///
/// **Supabase の `verify_jwt` は publishable key を通す。** つまりログインして
/// いなくても関数を呼べる。そのキーはアプリのバイナリに埋まっている。
///
/// レート制限は実装しない決定である（ADR-0016）。キーが漏れた場合、
/// **日次クォータを使い切られるまで止める手段が無い**。課金を伴う関数で
/// 匿名呼び出しを許す理由が無いため、ここで塞ぐ。
///
/// 設計も `ERR-AUTH-001`（401）を定義している（FEAT-08 §6）。
///
/// ## 署名は検証しない
///
/// Supabase が `verify_jwt` で検証済みのものだけが届く。ここで見るのは
/// **「本人のトークンか、それとも匿名のキーか」**の区別だけである。
/// 二重に署名検証しても得るものが無い。
///
/// 純関数なのでテストから直接呼べる。
export function requireUserId(header: string | null): string {
  const claims = readJwtClaims(header);

  // publishable key（`sb_publishable_...`）は JWT ですらないのでここで落ちる。
  // 匿名セッションの JWT は `role: 'anon'` で届くため、これも通さない。
  if (!claims || claims.role !== 'authenticated' || !claims.sub) {
    throw new AppError(
      'ERR-AUTH-001',
      401,
      'ログインし直してください。',
      false,
      `role=${claims?.role ?? '-'} sub=${claims?.sub ? 'あり' : 'なし'}`,
    );
  }
  return claims.sub;
}

interface JwtClaims {
  sub?: string;
  role?: string;
}

/// JWT のペイロードを読む。JWT でなければ `null`。
function readJwtClaims(header: string | null): JwtClaims | null {
  try {
    const token = (header ?? '').replace(/^Bearer\s+/i, '');
    const payload = token.split('.')[1];
    if (!payload) return null;
    // base64url を base64 へ直す。`atob` は `-` `_` を受け付けない。
    const base64 = payload.replace(/-/g, '+').replace(/_/g, '/');
    return JSON.parse(atob(base64)) as JwtClaims;
  } catch {
    return null;
  }
}
