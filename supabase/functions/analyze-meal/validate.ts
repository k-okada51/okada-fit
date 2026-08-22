// `analyze-meal` の検証。**純関数だけを置く**（`validate_test.ts` の対象）。
//
// `fetch` も `Deno.env` も触らない。ここが空振りしないことを単体テストで確かめる。
//
// 検証は2か所で行う（FEAT-08 §3.4）。端末側（Flutter）と、ここ。
// **課金を伴う Gemini 呼び出しより前に必ず落とす。**

import { AppError } from '../_shared/errors.ts';
import {
  ALLOWED_MIME_TYPES,
  MAX_DISH_NAMES,
  MAX_IMAGE_BYTES,
  MealNutrition,
  MIN_IMAGE_BYTES,
  NUTRITION_RANGES,
} from './schema.ts';

/// 端末から届く本文。
export interface AnalyzeMealRequest {
  imageBase64: string;
  mimeType: string;
  /// デコード後のバイト列。長さの検証とマジックバイトの照合に使う。
  bytes: Uint8Array;
}

/// 本文を読み、画像として妥当かを見る（ERR-MEAL-001/002/003）。
///
/// 返すのは検証済みの入力である。**呼び出し側で再検証しなくてよい。**
export function parseAnalyzeMealRequest(body: unknown): AnalyzeMealRequest {
  const record = (body ?? {}) as Record<string, unknown>;
  const imageBase64 = record.image_base64;
  const mimeType = record.mime_type;

  if (typeof imageBase64 !== 'string' || imageBase64.length === 0) {
    throw badImage('image_base64 が無い、または文字列でない');
  }
  if (typeof mimeType !== 'string' || mimeType.length === 0) {
    throw unsupportedMime('mime_type が無い、または文字列でない');
  }

  // 申告値をまず見る。ここで落ちればデコードの費用すら払わない。
  if (!(ALLOWED_MIME_TYPES as readonly string[]).includes(mimeType)) {
    throw unsupportedMime(`申告 mime_type=${mimeType}`);
  }

  let bytes: Uint8Array;
  try {
    bytes = decodeBase64(imageBase64);
  } catch (error) {
    throw badImage(`base64 として読めない: ${error}`);
  }

  // 下限より先に上限を見る。巨大な画像は端末側リサイズの不具合を示すので、
  // 「壊れている」ではなく「大きすぎる」と伝えたい。
  if (bytes.length > MAX_IMAGE_BYTES) {
    throw new AppError(
      'ERR-MEAL-003',
      413,
      '写真のサイズが大きすぎます。撮り直してください。',
      false,
      `bytes=${bytes.length}`,
    );
  }
  if (bytes.length < MIN_IMAGE_BYTES) {
    throw badImage(`bytes=${bytes.length}（下限 ${MIN_IMAGE_BYTES} 未満）`);
  }

  // **申告値とマジックバイトの両方**で見る（FEAT-08 §3.4）。
  // 拡張子や申告だけを信じると、別形式を渡されて Gemini 側で落ちる。
  const actual = sniffMimeType(bytes);
  if (actual === null) {
    throw unsupportedMime('マジックバイトが JPEG/PNG/WebP のいずれでもない');
  }
  if (actual !== mimeType) {
    throw unsupportedMime(`申告=${mimeType} 実体=${actual}`);
  }

  return { imageBase64, mimeType, bytes };
}

/// 先頭バイトから実際の形式を見る。判別できなければ `null`。
///
/// 見るのは3種だけ（[ALLOWED_MIME_TYPES]）。汎用の判別器は要らない。
export function sniffMimeType(bytes: Uint8Array): string | null {
  // JPEG: FF D8 FF
  if (bytes.length >= 3 && bytes[0] === 0xff && bytes[1] === 0xd8 && bytes[2] === 0xff) {
    return 'image/jpeg';
  }
  // PNG: 89 50 4E 47 0D 0A 1A 0A
  const png = [0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a];
  if (bytes.length >= 8 && png.every((b, i) => bytes[i] === b)) {
    return 'image/png';
  }
  // WebP: "RIFF" ....（4バイトの長さ）.... "WEBP"
  if (
    bytes.length >= 12 &&
    ascii(bytes, 0, 4) === 'RIFF' &&
    ascii(bytes, 8, 12) === 'WEBP'
  ) {
    return 'image/webp';
  }
  return null;
}

/// AI の応答が契約どおりかを見る（ERR-AI-SCHEMA・502）。
///
/// **型だけを見る。** 値の妥当域は [assertNutritionInRange] が別に見る。
/// 分けるのは ERR-ID と HTTP が違うためで、混ぜると原因が追えなくなる。
///
/// | 何が違うか | ERR-ID | HTTP |
/// |---|---|---|
/// | 型・欠落 | `ERR-AI-SCHEMA` | 502 |
/// | 値が業務上ありえない | `ERR-MEAL-005` | 422 |
export function parseMealNutrition(data: unknown): MealNutrition {
  const record = (data ?? {}) as Record<string, unknown>;

  const foodName = record.food_name;
  if (typeof foodName !== 'string') throw schemaError('food_name が文字列でない');

  const dishNames = record.dish_names;
  if (!Array.isArray(dishNames) || dishNames.some((v) => typeof v !== 'string')) {
    throw schemaError('dish_names が文字列配列でない');
  }
  if (dishNames.length > MAX_DISH_NAMES) {
    throw schemaError(`dish_names が ${dishNames.length} 件（上限 ${MAX_DISH_NAMES}）`);
  }

  const numbers: Record<string, number> = {};
  for (const key of ['calories_kcal', 'protein_g', 'sugar_g', 'fat_g'] as const) {
    const value = record[key];
    // `NaN`・`Infinity` は `typeof` が number なので通ってしまう。個別に弾く。
    if (typeof value !== 'number' || !Number.isFinite(value)) {
      throw schemaError(`${key} が有限の数値でない`);
    }
    numbers[key] = value;
  }

  return {
    food_name: foodName,
    dish_names: dishNames as string[],
    calories_kcal: numbers.calories_kcal,
    protein_g: numbers.protein_g,
    sugar_g: numbers.sugar_g,
    fat_g: numbers.fat_g,
  };
}

/// 値が業務上ありえる範囲かを見る（ERR-MEAL-005・422）。
export function assertNutritionInRange(nutrition: MealNutrition): void {
  for (const [key, range] of Object.entries(NUTRITION_RANGES)) {
    const value = nutrition[key as keyof typeof NUTRITION_RANGES];
    if (value < range.min || value > range.max) {
      throw new AppError(
        'ERR-MEAL-005',
        422,
        'うまく読み取れませんでした。写真を撮り直してください。',
        false,
        `${key}=${value}（許容 ${range.min}〜${range.max}）`,
      );
    }
  }
}

/// 栄養4項目を小数第1位に丸める（ADR-0022・`numeric(6,1)`）。
///
/// **Edge Function 側で丸める。** Gemini は任意の小数を返しうる。
/// ここで丸めておけば、画面に出る値と `meal_logs` に入る値が必ず一致する。
/// Flutter は受け取った値をそのまま保存する（FEAT-08 §3.3）。
export function roundNutrition(nutrition: MealNutrition): MealNutrition {
  return {
    ...nutrition,
    calories_kcal: round1(nutrition.calories_kcal),
    protein_g: round1(nutrition.protein_g),
    sugar_g: round1(nutrition.sugar_g),
    fat_g: round1(nutrition.fat_g),
  };
}

/// 小数第1位・四捨五入。Dart 側の `roundProteinG` と同じ規則にする。
export function round1(value: number): number {
  return Math.round(value * 10) / 10;
}

/// base64 を復号する。`atob` は不正な入力で例外を投げる。
export function decodeBase64(input: string): Uint8Array {
  // データURL（`data:image/jpeg;base64,...`）で来ても受けられるようにする。
  // 端末側は素の base64 を送る約束だが、前置きが付く事故は起きやすい。
  const body = input.includes(',') ? input.slice(input.indexOf(',') + 1) : input;
  const binary = atob(body);
  const bytes = new Uint8Array(binary.length);
  for (let i = 0; i < binary.length; i++) bytes[i] = binary.charCodeAt(i);
  return bytes;
}

function ascii(bytes: Uint8Array, start: number, end: number): string {
  return String.fromCharCode(...bytes.subarray(start, end));
}

function badImage(detail: string): AppError {
  return new AppError(
    'ERR-MEAL-001',
    400,
    '写真を読み取れませんでした。選び直してください。',
    false,
    detail,
  );
}

function unsupportedMime(detail: string): AppError {
  return new AppError(
    'ERR-MEAL-002',
    415,
    'JPEG・PNG・WebP の写真を選んでください。',
    false,
    detail,
  );
}

function schemaError(detail: string): AppError {
  return new AppError(
    'ERR-AI-SCHEMA',
    502,
    'うまく読み取れませんでした。写真を撮り直してください。',
    false,
    detail,
  );
}
