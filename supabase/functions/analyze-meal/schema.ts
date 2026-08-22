// `analyze-meal`（FEAT-08）の入出力契約。
//
// 正本は `08_機能別詳細設計/FEAT-08_食事撮影タンパク質計算.md §3.2`・`§3.4`。
// **I/O を持たない。** ここに置いたものは全て `validate_test.ts` から呼べる。

/// `generationConfig.response_schema` に載せる JSON Schema。
///
/// PoC 実測の基線スキーマ（ADR-0001）。**フィールド名は snake_case。**
/// description は Gemini への指示そのものなので、実測時の文言から変えない。
export const MEAL_NUTRITION_RESPONSE_SCHEMA = {
  type: 'object',
  properties: {
    food_name: {
      type: 'string',
      description: '写真全体の料理・商品の推定名称（日本語、総称）',
    },
    dish_names: {
      type: 'array',
      items: { type: 'string' },
      description: '写真に写る個々の料理名。単品なら1件、複数なら全て列挙',
    },
    calories_kcal: {
      type: 'number',
      description: '写真に写っている食事全体(1人前)のカロリー (kcal)',
    },
    protein_g: { type: 'number', description: 'タンパク質 (g)' },
    sugar_g: {
      type: 'number',
      description: '糖質 (g)。食物繊維を除いた炭水化物量',
    },
    fat_g: { type: 'number', description: '脂質 (g)' },
  },
  required: [
    'food_name',
    'dish_names',
    'calories_kcal',
    'protein_g',
    'sugar_g',
    'fat_g',
  ],
} as const;

/// 検証を通った栄養推定。呼び出し元へそのまま返す形。
export interface MealNutrition {
  // deno-lint-ignore camelcase
  food_name: string;
  // deno-lint-ignore camelcase
  dish_names: string[];
  // deno-lint-ignore camelcase
  calories_kcal: number;
  // deno-lint-ignore camelcase
  protein_g: number;
  // deno-lint-ignore camelcase
  sugar_g: number;
  // deno-lint-ignore camelcase
  fat_g: number;
}

/// 許可する MIME（FEAT-08 §3.4 `[仮]`）。
export const ALLOWED_MIME_TYPES = ['image/jpeg', 'image/png', 'image/webp'] as const;

/// 画像バイト長の下限（FEAT-08 §3.4 `[仮]`）。
///
/// 1KB を切る画像は、撮影の失敗か送信の欠損である。課金の前に落とす。
export const MIN_IMAGE_BYTES = 1_024;

/// 画像バイト長の上限（FEAT-08 §3.4 `[仮]`）。
///
/// 端末側で長辺1024pxへ縮小する（ADR-0003）。実測は最大 303KB で、その約3倍。
/// 通常ここへは到達しない。到達したら端末側リサイズの不具合である。
export const MAX_IMAGE_BYTES = 1_048_576;

/// AI出力の妥当域（FEAT-08 §3.4 `[仮]`）。
///
/// 型が合っていても業務上ありえない値は落とす。ERR-AI-SCHEMA とは別物で、
/// **こちらは 422（ERR-MEAL-005）**。原因が「型」ではなく「値」だからである。
export const NUTRITION_RANGES = {
  calories_kcal: { min: 0, max: 5_000 },
  protein_g: { min: 0, max: 500 },
  sugar_g: { min: 0, max: 1_000 },
  fat_g: { min: 0, max: 500 },
} as const;

/// `dish_names` の上限件数。基線スキーマの zod 定義に合わせる。
export const MAX_DISH_NAMES = 20;
