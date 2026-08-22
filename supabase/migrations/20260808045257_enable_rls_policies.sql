-- RLS の有効化とポリシー
-- 正本: docs/02_設計/50_詳細設計/01_DB物理設計.md §3.4（ADR-0005・DEC-D03）
--
-- 前提3点:
--   有効化 … 全10表で ENABLE ROW LEVEL SECURITY を必ず入れる
--   本人ID … auth.uid()（uuid）。users.id と各 user_id が uuid なので直接比較できる
--   ロール … TO authenticated を明示する。anon には権限を与えない（NFR-SEC-01）
--
-- RLS が唯一の防御線である。Flutter が PostgREST を直接叩くため、
-- サーバ側ハンドラでの二重チェックが存在しない（07_実装共通設計パターン.md §1）。

-- ============================================================
-- 区分1: 本人のみ
-- ============================================================

ALTER TABLE public.users ENABLE ROW LEVEL SECURITY;
CREATE POLICY p_users_self ON public.users
  FOR ALL TO authenticated
  USING (id = auth.uid()) WITH CHECK (id = auth.uid());

ALTER TABLE public.training_menus ENABLE ROW LEVEL SECURITY;
CREATE POLICY p_training_menus_self ON public.training_menus
  FOR ALL TO authenticated
  USING (user_id = auth.uid()) WITH CHECK (user_id = auth.uid());

ALTER TABLE public.gym_visits ENABLE ROW LEVEL SECURITY;
CREATE POLICY p_gym_visits_self ON public.gym_visits
  FOR ALL TO authenticated
  USING (user_id = auth.uid()) WITH CHECK (user_id = auth.uid());

ALTER TABLE public.training_sessions ENABLE ROW LEVEL SECURITY;
CREATE POLICY p_training_sessions_self ON public.training_sessions
  FOR ALL TO authenticated
  USING (user_id = auth.uid()) WITH CHECK (user_id = auth.uid());

ALTER TABLE public.meal_logs ENABLE ROW LEVEL SECURITY;
CREATE POLICY p_meal_logs_self ON public.meal_logs
  FOR ALL TO authenticated
  USING (user_id = auth.uid()) WITH CHECK (user_id = auth.uid());

-- ============================================================
-- 区分2: 共通マスタ
--   認証済みなら誰でも読み書きできる。単一ユーザー運用では実害が無いが、
--   Phase2 のマルチユーザー化（NFR-SCALE-01）で書き込みを絞る必要がある。
-- ============================================================

ALTER TABLE public.gyms ENABLE ROW LEVEL SECURITY;
CREATE POLICY p_gyms_shared ON public.gyms
  FOR ALL TO authenticated
  USING (true) WITH CHECK (true);

ALTER TABLE public.training_machines ENABLE ROW LEVEL SECURITY;
CREATE POLICY p_training_machines_shared ON public.training_machines
  FOR ALL TO authenticated
  USING (true) WITH CHECK (true);

ALTER TABLE public.foods ENABLE ROW LEVEL SECURITY;
CREATE POLICY p_foods_shared ON public.foods
  FOR ALL TO authenticated
  USING (true) WITH CHECK (true);

-- ============================================================
-- 区分3: 親経由
-- ============================================================

ALTER TABLE public.machine_menus ENABLE ROW LEVEL SECURITY;
CREATE POLICY p_machine_menus_self ON public.machine_menus
  FOR ALL TO authenticated
  USING (EXISTS (SELECT 1 FROM public.training_menus m
                 WHERE m.id = machine_menus.menu_id AND m.user_id = auth.uid()))
  WITH CHECK (EXISTS (SELECT 1 FROM public.training_menus m
                      WHERE m.id = machine_menus.menu_id AND m.user_id = auth.uid()));

ALTER TABLE public.training_session_details ENABLE ROW LEVEL SECURITY;
CREATE POLICY p_training_session_details_self ON public.training_session_details
  FOR ALL TO authenticated
  USING (EXISTS (SELECT 1 FROM public.training_sessions s
                 WHERE s.id = training_session_details.session_id AND s.user_id = auth.uid()))
  WITH CHECK (EXISTS (SELECT 1 FROM public.training_sessions s
                      WHERE s.id = training_session_details.session_id AND s.user_id = auth.uid()));
