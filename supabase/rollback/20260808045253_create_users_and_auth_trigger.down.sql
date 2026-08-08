-- down: 20260808045253_create_users_and_auth_trigger.sql
-- 適用: psql で手動（移行設計 §3.3 規約5）
--
-- ⚠️ トリガは auth スキーマ側にある。消し忘れるとサインアップが
--    「users が無いのに INSERT する」状態で壊れたまま残る（移行設計 §3.3 規約9）。

DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
DROP FUNCTION IF EXISTS public.handle_new_user();
DROP TABLE IF EXISTS public.users;
