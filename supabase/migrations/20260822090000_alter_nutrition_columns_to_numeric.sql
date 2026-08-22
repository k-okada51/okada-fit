-- 栄養値・体重を float から numeric(6,1) へ変更
-- 正本: docs/意思決定_ADR/0022-numeric-instead-of-float.md
--       docs/02_設計/50_詳細設計/01_DB物理設計.md §1.1・§1.5・§2.4
--
-- float は 0.1 + 0.2 = 0.30000000000000004 の誤差を出す。
-- FEAT-09 は残量が 0 かどうかで表示を変えるため、誤差が分岐に効く。
-- 精度は小数第1位まで。栄養表示の慣習に合わせた。
--
-- CHECK 制約・NULL 可否は変更しない。既存値は小数第1位に丸められる。

ALTER TABLE public.users
  ALTER COLUMN weight_kg TYPE numeric(6,1) USING weight_kg::numeric(6,1);

ALTER TABLE public.foods
  ALTER COLUMN protein_amount TYPE numeric(6,1) USING protein_amount::numeric(6,1);

ALTER TABLE public.meal_logs
  ALTER COLUMN calories_kcal TYPE numeric(6,1) USING calories_kcal::numeric(6,1),
  ALTER COLUMN protein_g     TYPE numeric(6,1) USING protein_g::numeric(6,1),
  ALTER COLUMN sugar_g       TYPE numeric(6,1) USING sugar_g::numeric(6,1),
  ALTER COLUMN fat_g         TYPE numeric(6,1) USING fat_g::numeric(6,1);
