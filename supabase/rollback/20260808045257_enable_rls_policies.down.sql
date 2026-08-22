-- down: 20260808045257_enable_rls_policies.sql
-- 適用: psql で手動（Supabase CLI は down 適用のコマンドを持たない・移行設計 §3.3 規約5）

DROP POLICY IF EXISTS p_training_session_details_self ON public.training_session_details;
ALTER TABLE public.training_session_details DISABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS p_machine_menus_self ON public.machine_menus;
ALTER TABLE public.machine_menus DISABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS p_foods_shared ON public.foods;
ALTER TABLE public.foods DISABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS p_training_machines_shared ON public.training_machines;
ALTER TABLE public.training_machines DISABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS p_gyms_shared ON public.gyms;
ALTER TABLE public.gyms DISABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS p_meal_logs_self ON public.meal_logs;
ALTER TABLE public.meal_logs DISABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS p_training_sessions_self ON public.training_sessions;
ALTER TABLE public.training_sessions DISABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS p_gym_visits_self ON public.gym_visits;
ALTER TABLE public.gym_visits DISABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS p_training_menus_self ON public.training_menus;
ALTER TABLE public.training_menus DISABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS p_users_self ON public.users;
ALTER TABLE public.users DISABLE ROW LEVEL SECURITY;
