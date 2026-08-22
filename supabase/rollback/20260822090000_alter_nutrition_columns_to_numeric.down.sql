-- 20260822090000_alter_nutrition_columns_to_numeric.sql の取り消し
-- 注意: numeric → float に戻すと丸め誤差が復活する。値そのものは失われない。

ALTER TABLE public.meal_logs
  ALTER COLUMN calories_kcal TYPE float USING calories_kcal::float,
  ALTER COLUMN protein_g     TYPE float USING protein_g::float,
  ALTER COLUMN sugar_g       TYPE float USING sugar_g::float,
  ALTER COLUMN fat_g         TYPE float USING fat_g::float;

ALTER TABLE public.foods
  ALTER COLUMN protein_amount TYPE float USING protein_amount::float;

ALTER TABLE public.users
  ALTER COLUMN weight_kg TYPE float USING weight_kg::float;
