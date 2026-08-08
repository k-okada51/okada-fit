-- down: 20260808060309_grant_data_api_privileges.sql
-- 適用: psql で手動（移行設計 §3.3 規約5）

REVOKE SELECT, INSERT, UPDATE, DELETE ON TABLE
  public.users,
  public.gyms,
  public.training_menus,
  public.training_machines,
  public.foods,
  public.machine_menus,
  public.gym_visits,
  public.training_sessions,
  public.training_session_details,
  public.meal_logs
FROM authenticated;
