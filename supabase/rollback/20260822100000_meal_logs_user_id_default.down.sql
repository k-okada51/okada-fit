-- 20260822100000_meal_logs_user_id_default.sql の取り消し
--
-- DEFAULT を外すだけ。既存行の user_id は動かさない。

ALTER TABLE public.meal_logs
  ALTER COLUMN user_id DROP DEFAULT;

COMMENT ON COLUMN public.meal_logs.user_id IS NULL;
