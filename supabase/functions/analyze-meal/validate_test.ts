// `analyze-meal` の純関数の単体テスト（NFR-QUAL-01）。
//
// ネットワークも Gemini も使わない。**課金は一切発生しない。**
//
// 確かめたいのは1点。**課金を伴う Gemini 呼び出しより前に、壊れた入力を
// 落とせているか**（FEAT-08 §3.4）。落とし損ねると、無駄な課金が発生する。
//
//   deno test supabase/functions/

import { assertEquals, assertThrows } from 'jsr:@std/assert@1';

import { AppError, requireUserId } from '../_shared/errors.ts';
import { mapGeminiHttpError } from '../_shared/gemini.ts';
import { MAX_IMAGE_BYTES, MIN_IMAGE_BYTES } from './schema.ts';
import {
  assertNutritionInRange,
  decodeBase64,
  parseAnalyzeMealRequest,
  parseMealNutrition,
  round1,
  roundNutrition,
  sniffMimeType,
} from './validate.ts';

/// 先頭に本物のマグレンジックバイトを置いた、指定バイト長のダミー画像。
function fakeImage(kind: 'jpeg' | 'png' | 'webp', bytes = MIN_IMAGE_BYTES): Uint8Array {
  const head: Record<string, number[]> = {
    jpeg: [0xff, 0xd8, 0xff],
    png: [0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a],
    // "RIFF" + 長さ4バイト + "WEBP"
    webp: [0x52, 0x49, 0x46, 0x46, 0, 0, 0, 0, 0x57, 0x45, 0x42, 0x50],
  };
  const buffer = new Uint8Array(bytes);
  buffer.set(head[kind]);
  return buffer;
}

function toBase64(bytes: Uint8Array): string {
  // **一括で展開しない。** `String.fromCharCode(...bytes)` は 1MB の配列で
  // 引数の上限を超え `RangeError` になる。上限の境界値を試すテストが必要なので、
  // ここは必ず分割して積む。
  let binary = '';
  const chunk = 8_192;
  for (let i = 0; i < bytes.length; i += chunk) {
    binary += String.fromCharCode(...bytes.subarray(i, i + chunk));
  }
  return btoa(binary);
}

function body(kind: 'jpeg' | 'png' | 'webp', mimeType: string, bytes?: number) {
  return { image_base64: toBase64(fakeImage(kind, bytes)), mime_type: mimeType };
}

/// 投げられた `AppError` の `errorCode` を取り出す。
function codeOf(fn: () => unknown): string {
  const error = assertThrows(fn, AppError);
  return (error as AppError).errorCode;
}

Deno.test('画像の検証 — 正常系は通る', () => {
  for (const [kind, mime] of [
    ['jpeg', 'image/jpeg'],
    ['png', 'image/png'],
    ['webp', 'image/webp'],
  ] as const) {
    const parsed = parseAnalyzeMealRequest(body(kind, mime));
    assertEquals(parsed.mimeType, mime);
    assertEquals(parsed.bytes.length, MIN_IMAGE_BYTES);
  }
});

Deno.test('ERR-MEAL-001 — 空・非文字列・base64 として壊れている', () => {
  assertEquals(codeOf(() => parseAnalyzeMealRequest({})), 'ERR-MEAL-001');
  assertEquals(codeOf(() => parseAnalyzeMealRequest(null)), 'ERR-MEAL-001');
  assertEquals(
    codeOf(() => parseAnalyzeMealRequest({ image_base64: '', mime_type: 'image/jpeg' })),
    'ERR-MEAL-001',
  );
  assertEquals(
    codeOf(() => parseAnalyzeMealRequest({ image_base64: 123, mime_type: 'image/jpeg' })),
    'ERR-MEAL-001',
  );
  assertEquals(
    codeOf(() =>
      parseAnalyzeMealRequest({ image_base64: '!!!not base64!!!', mime_type: 'image/jpeg' })
    ),
    'ERR-MEAL-001',
  );
});

Deno.test('ERR-MEAL-001 — 下限 1KB 未満を落とす', () => {
  assertEquals(
    codeOf(() => parseAnalyzeMealRequest(body('jpeg', 'image/jpeg', MIN_IMAGE_BYTES - 1))),
    'ERR-MEAL-001',
  );
  // 境界そのものは通す。
  assertEquals(
    parseAnalyzeMealRequest(body('jpeg', 'image/jpeg', MIN_IMAGE_BYTES)).bytes.length,
    MIN_IMAGE_BYTES,
  );
});

Deno.test('ERR-MEAL-003 — 上限 1MB 超を落とす', () => {
  assertEquals(
    codeOf(() => parseAnalyzeMealRequest(body('jpeg', 'image/jpeg', MAX_IMAGE_BYTES + 1))),
    'ERR-MEAL-003',
  );
  assertEquals(
    parseAnalyzeMealRequest(body('jpeg', 'image/jpeg', MAX_IMAGE_BYTES)).bytes.length,
    MAX_IMAGE_BYTES,
  );
});

Deno.test('ERR-MEAL-002 — 申告 MIME が許可外', () => {
  assertEquals(codeOf(() => parseAnalyzeMealRequest(body('jpeg', 'image/gif'))), 'ERR-MEAL-002');
  assertEquals(codeOf(() => parseAnalyzeMealRequest(body('jpeg', 'application/pdf'))), 'ERR-MEAL-002');
  assertEquals(
    codeOf(() => parseAnalyzeMealRequest({ image_base64: 'AAAA', mime_type: '' })),
    'ERR-MEAL-002',
  );
});

Deno.test('ERR-MEAL-002 — 申告と実体が食い違う（マジックバイト照合）', () => {
  // 中身は PNG なのに JPEG と申告している。申告だけを信じると通ってしまう。
  assertEquals(codeOf(() => parseAnalyzeMealRequest(body('png', 'image/jpeg'))), 'ERR-MEAL-002');
  assertEquals(codeOf(() => parseAnalyzeMealRequest(body('webp', 'image/png'))), 'ERR-MEAL-002');
});

Deno.test('ERR-MEAL-002 — どの形式でもないバイト列', () => {
  const junk = new Uint8Array(MIN_IMAGE_BYTES);
  junk.set([0x00, 0x01, 0x02, 0x03]);
  assertEquals(
    codeOf(() =>
      parseAnalyzeMealRequest({ image_base64: toBase64(junk), mime_type: 'image/jpeg' })
    ),
    'ERR-MEAL-002',
  );
});

Deno.test('sniffMimeType — 短すぎるバイト列で落ちない', () => {
  assertEquals(sniffMimeType(new Uint8Array(0)), null);
  assertEquals(sniffMimeType(new Uint8Array([0xff, 0xd8])), null);
  // RIFF だけあって WEBP が無いものは WebP ではない（AVI などが該当する）。
  const riff = new Uint8Array(12);
  riff.set([0x52, 0x49, 0x46, 0x46]);
  assertEquals(sniffMimeType(riff), null);
});

Deno.test('decodeBase64 — データURL の前置きが付いていても読める', () => {
  const bytes = fakeImage('jpeg');
  const plain = decodeBase64(toBase64(bytes));
  const dataUrl = decodeBase64(`data:image/jpeg;base64,${toBase64(bytes)}`);
  assertEquals(plain.length, dataUrl.length);
  assertEquals(plain[0], 0xff);
  assertEquals(dataUrl[0], 0xff);
});

const validAi = {
  food_name: '牛丼',
  dish_names: ['牛丼', '味噌汁'],
  calories_kcal: 733.4,
  protein_g: 22.9,
  sugar_g: 104.1,
  fat_g: 25.0,
};

Deno.test('AI応答の型検証 — 正常系', () => {
  const parsed = parseMealNutrition(validAi);
  assertEquals(parsed.food_name, '牛丼');
  assertEquals(parsed.dish_names.length, 2);
  assertEquals(parsed.protein_g, 22.9);
});

Deno.test('ERR-AI-SCHEMA — 欠落・型違い', () => {
  for (const patch of [
    { food_name: undefined },
    { food_name: 123 },
    { dish_names: '牛丼' },
    { dish_names: ['牛丼', 5] },
    { calories_kcal: '733' },
    { protein_g: undefined },
    { fat_g: null },
  ]) {
    assertEquals(
      codeOf(() => parseMealNutrition({ ...validAi, ...patch })),
      'ERR-AI-SCHEMA',
      `patch=${JSON.stringify(patch)}`,
    );
  }
  assertEquals(codeOf(() => parseMealNutrition(null)), 'ERR-AI-SCHEMA');
});

Deno.test('ERR-AI-SCHEMA — NaN と Infinity は typeof を抜けるので個別に弾く', () => {
  // `typeof NaN === 'number'` である。型判定だけでは通ってしまう。
  assertEquals(codeOf(() => parseMealNutrition({ ...validAi, protein_g: NaN })), 'ERR-AI-SCHEMA');
  assertEquals(
    codeOf(() => parseMealNutrition({ ...validAi, calories_kcal: Infinity })),
    'ERR-AI-SCHEMA',
  );
  assertEquals(
    codeOf(() => parseMealNutrition({ ...validAi, fat_g: -Infinity })),
    'ERR-AI-SCHEMA',
  );
});

Deno.test('ERR-AI-SCHEMA — dish_names の件数上限', () => {
  const many = Array.from({ length: 21 }, (_, i) => `料理${i}`);
  assertEquals(codeOf(() => parseMealNutrition({ ...validAi, dish_names: many })), 'ERR-AI-SCHEMA');
  // 20件ちょうどは通す。
  assertEquals(parseMealNutrition({ ...validAi, dish_names: many.slice(0, 20) }).dish_names.length, 20);
});

Deno.test('ERR-MEAL-005 — 型は合っているが値が業務上ありえない', () => {
  // 型エラー（502）とは別物。**422 で返す**。
  for (const patch of [
    { calories_kcal: -1 },
    { calories_kcal: 5001 },
    { protein_g: -0.1 },
    { protein_g: 501 },
    { sugar_g: 1001 },
    { fat_g: 501 },
  ]) {
    assertEquals(
      codeOf(() => assertNutritionInRange({ ...validAi, ...patch })),
      'ERR-MEAL-005',
      `patch=${JSON.stringify(patch)}`,
    );
  }
});

Deno.test('ERR-MEAL-005 — 境界は通す', () => {
  assertNutritionInRange({ ...validAi, calories_kcal: 0, protein_g: 0, sugar_g: 0, fat_g: 0 });
  assertNutritionInRange({
    ...validAi,
    calories_kcal: 5000,
    protein_g: 500,
    sugar_g: 1000,
    fat_g: 500,
  });
});

Deno.test('丸め — 小数第1位（ADR-0022 の numeric(6,1) に合わせる）', () => {
  assertEquals(round1(22.94), 22.9);
  assertEquals(round1(22.95), 23.0);
  assertEquals(round1(0.04), 0);
  const rounded = roundNutrition({ ...validAi, protein_g: 22.9499, fat_g: 25.06 });
  assertEquals(rounded.protein_g, 22.9);
  assertEquals(rounded.fat_g, 25.1);
  // 文字列項目は触らない。
  assertEquals(rounded.food_name, '牛丼');
});

Deno.test('Gemini の失敗の写像 — 429 は error.status で2つに割れる', () => {
  // **ここを取り違えると、日次クォータ切れをバックオフで叩き続ける。**
  const rate = mapGeminiHttpError(429, JSON.stringify({ error: { status: 'RATE_LIMIT_EXCEEDED' } }));
  assertEquals(rate.errorCode, 'ERR-AI-RATE');
  assertEquals(rate.retryable, true);

  const quota = mapGeminiHttpError(429, JSON.stringify({ error: { status: 'QUOTA_EXCEEDED' } }));
  assertEquals(quota.errorCode, 'ERR-AI-QUOTA');
  assertEquals(quota.retryable, false);

  // `error.status` が読めない 429 は、安全側（再試行可）に倒す。
  assertEquals(mapGeminiHttpError(429, 'not json').errorCode, 'ERR-AI-RATE');
});

Deno.test('Gemini の失敗の写像 — 400 は課金無効だけを 402 に分ける', () => {
  const credit = mapGeminiHttpError(400, JSON.stringify({ error: { status: 'FAILED_PRECONDITION' } }));
  assertEquals(credit.errorCode, 'ERR-AI-CREDIT');
  assertEquals(credit.status, 402);

  // 同じ 400 でも他は ERR-AI-FAIL。
  assertEquals(
    mapGeminiHttpError(400, JSON.stringify({ error: { status: 'INVALID_REQUEST' } })).errorCode,
    'ERR-AI-FAIL',
  );
});

Deno.test('Gemini の失敗の写像 — その他', () => {
  assertEquals(mapGeminiHttpError(401, '{}').errorCode, 'ERR-AI-FAIL');
  assertEquals(mapGeminiHttpError(403, '{}').errorCode, 'ERR-AI-FAIL');
  assertEquals(mapGeminiHttpError(404, '{}').errorCode, 'ERR-AI-FAIL');
  assertEquals(mapGeminiHttpError(500, '{}').errorCode, 'ERR-AI-FAIL');
  assertEquals(mapGeminiHttpError(503, '{}').errorCode, 'ERR-AI-FAIL');
  assertEquals(mapGeminiHttpError(504, '{}').errorCode, 'ERR-AI-TIMEOUT');
  assertEquals(
    mapGeminiHttpError(500, JSON.stringify({ error: { status: 'DEADLINE_EXCEEDED' } })).errorCode,
    'ERR-AI-TIMEOUT',
  );
});

Deno.test('利用者向けメッセージに技術詳細を出さない（02_API設計.md §5.1）', () => {
  const error = mapGeminiHttpError(500, 'Internal error at /srv/gemini/handler.go:42');
  // 原因はログ用の detail にだけ入る。
  assertEquals(error.userMessage.includes('handler.go'), false);
  assertEquals(error.userMessage.includes('500'), false);
});

// --- 認証（ERR-AUTH-001） ---
//
// **Supabase の verify_jwt は publishable key を通す。** ログインしていなくても
// 関数を呼べてしまう。課金を伴う関数なので、ここで塞げているかを確かめる。

/// `sub` と `role` だけを持つ最小の JWT（署名は検証されないのでダミーでよい）。
function fakeJwt(claims: Record<string, unknown>): string {
  const b64 = (o: unknown) =>
    btoa(JSON.stringify(o)).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
  return `${b64({ alg: 'HS256', typ: 'JWT' })}.${b64(claims)}.signature`;
}

Deno.test('requireUserId — ログイン済みなら uuid を返す', () => {
  const token = fakeJwt({ sub: '11111111-2222-3333-4444-555555555555', role: 'authenticated' });
  assertEquals(requireUserId(`Bearer ${token}`), '11111111-2222-3333-4444-555555555555');
});

Deno.test('ERR-AUTH-001 — publishable key・匿名・欠落を弾く', () => {
  // publishable key は JWT ですらない。
  assertEquals(codeOf(() => requireUserId('Bearer sb_publishable_xxxxxxxx')), 'ERR-AUTH-001');
  // 匿名セッションの JWT。`sub` があっても role が違えば通さない。
  assertEquals(
    codeOf(() => requireUserId(`Bearer ${fakeJwt({ sub: 'x', role: 'anon' })}`)),
    'ERR-AUTH-001',
  );
  // role は合っていても sub が無いものは通さない。
  assertEquals(
    codeOf(() => requireUserId(`Bearer ${fakeJwt({ role: 'authenticated' })}`)),
    'ERR-AUTH-001',
  );
  assertEquals(codeOf(() => requireUserId(null)), 'ERR-AUTH-001');
  assertEquals(codeOf(() => requireUserId('')), 'ERR-AUTH-001');
  assertEquals(codeOf(() => requireUserId('Bearer not.a.jwt')), 'ERR-AUTH-001');
});
