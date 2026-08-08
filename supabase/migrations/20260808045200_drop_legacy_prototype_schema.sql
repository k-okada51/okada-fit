-- 旧プロトタイプ（Next.js 期）のスキーマを撤去する
--
-- 経緯: 2026-08-01 に web/supabase/schema.sql をダッシュボードから手で適用したもので、
--       マイグレーション履歴に載っていない。その後 2026-08-08 に A群スキーマが確定し
--       （ADR-0005 ほか）、5テーブルが構造レベルで変わったため作り直す。
--
-- 主な相違:
--   profiles          → users（id が PK・name NOT NULL）
--   gyms / training_machines / foods は共通マスタ化（user_id を廃止）
--   training_machines.menu_id → machine_menus による多対多
--   RLS は3区分（本人 / 共通マスタ / 親経由）へ
--
-- 適用時点で実データは無いことを確認済み（table-stats の推定行数が全表0）。

-- 旧トリガと関数を先に落とす（auth スキーマ側に残ると新トリガと衝突する）
DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
DROP FUNCTION IF EXISTS public.handle_new_user();

-- 依存の逆順に落とす。ポリシーとINDEXはテーブルと一緒に消える
DROP TABLE IF EXISTS public.meal_logs CASCADE;
DROP TABLE IF EXISTS public.training_session_details CASCADE;
DROP TABLE IF EXISTS public.training_sessions CASCADE;
DROP TABLE IF EXISTS public.gym_visits CASCADE;
DROP TABLE IF EXISTS public.machine_menus CASCADE;
DROP TABLE IF EXISTS public.foods CASCADE;
DROP TABLE IF EXISTS public.training_machines CASCADE;
DROP TABLE IF EXISTS public.training_menus CASCADE;
DROP TABLE IF EXISTS public.gyms CASCADE;
DROP TABLE IF EXISTS public.profiles CASCADE;
DROP TABLE IF EXISTS public.users CASCADE;
