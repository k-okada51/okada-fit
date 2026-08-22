-- down: 20260808045254_create_master_tables.sql
-- 適用: psql で手動（移行設計 §3.3 規約5）
--
-- 依存の逆順に落とす。INDEX はテーブルと一緒に消えるため個別の DROP は要らない。
-- ⚠️ 履歴系（20260808045256）を先に落としていないと FK 依存で失敗する。

DROP TABLE IF EXISTS public.machine_menus;
DROP TABLE IF EXISTS public.foods;
DROP TABLE IF EXISTS public.training_machines;
DROP TABLE IF EXISTS public.training_menus;
DROP TABLE IF EXISTS public.gyms;
