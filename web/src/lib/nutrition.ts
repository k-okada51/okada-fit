import { z } from 'zod';

// 食事画像→栄養価の構造化出力スキーマ（PoC・ADR-0001 で実証済み）
export const nutritionSchema = z.object({
  food_name: z.string().describe('写真全体の料理・商品の推定名称（日本語・総称）'),
  dish_names: z
    .array(z.string())
    .describe('写真に写っている個々の料理名のリスト。単品なら1件'),
  calories_kcal: z.number().describe('写真の食事1人前のカロリー(kcal)'),
  protein_g: z.number().describe('タンパク質(g)'),
  sugar_g: z.number().describe('糖質(g)。食物繊維を除いた炭水化物量'),
  fat_g: z.number().describe('脂質(g)'),
});

export type Nutrition = z.infer<typeof nutritionSchema>;

// 既定モデル（ADR-0001/DEC-D02）
export const MEAL_VISION_MODEL = 'google/gemini-3.5-flash';

export const MEAL_PROMPT =
  'この写真は食事です。写っている食品1人前の栄養成分を、見た目・種類・量から推定してください。';
