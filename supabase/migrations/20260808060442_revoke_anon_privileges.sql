-- anon から public スキーマの表権限を剥奪する
--
-- 「anon には権限を与えない」（NFR-SEC-01・01_DB物理設計.md §3.4 の前提3）を
-- 表権限のレベルでも成立させる。
--
-- 経緯: 2026-08-01 作成のクラウドプロジェクトには旧来の自動公開設定が効いており、
-- anon に SELECT/INSERT/UPDATE/DELETE が付いていた（2026-08-08 実測）。
-- RLS ポリシーが TO authenticated のみのため行は見えないが、
-- 本PJは RLS が唯一の防御線である（07_実装共通設計パターン.md §1）。
-- 表権限を残すと、RLS の設定漏れがそのまま全開放になる。
--
-- サインアップ・ログインは auth スキーマ（GoTrue）を通るため、
-- anon から public の表権限を落としても認証系には影響しない。

REVOKE ALL ON TABLE
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
FROM anon;
