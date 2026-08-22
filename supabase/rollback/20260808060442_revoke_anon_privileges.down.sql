-- down: 20260808060442_revoke_anon_privileges.sql
-- 適用: psql で手動（移行設計 §3.3 規約5）
--
-- ⚠️ 剥奪前の状態は環境で違った（クラウド=全DML付き / ローカル=REFERENCES,TRIGGER,TRUNCATE のみ）。
--    ここでは「Supabase の旧既定＝自動公開」の状態に戻す。
--    設計（NFR-SEC-01）に反する状態なので、切戻し以外の目的で流さないこと。

GRANT SELECT, INSERT, UPDATE, DELETE, REFERENCES, TRIGGER, TRUNCATE ON TABLE
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
TO anon;
