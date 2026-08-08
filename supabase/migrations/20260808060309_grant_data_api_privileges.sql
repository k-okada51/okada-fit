-- Data API ロールへのテーブル権限付与
--
-- RLS ポリシー（20260808045257）だけでは PostgREST から触れない。
-- RLS は「どの行を見せるか」を絞る仕組みで、テーブルに触れてよいかは
-- GRANT が決める。両方そろって初めてアクセスできる。
--
-- 以前の Supabase は public スキーマの新規テーブルを anon/authenticated へ
-- 自動公開していたが、現在の既定は非公開。明示的な GRANT が要る
-- （config.toml の [api] のコメント参照。自動公開の設定自体が 2026-10-30 に廃止される）。
--
-- anon には何も与えない（NFR-SEC-01・01_DB物理設計.md §3.4 の前提3）。
-- 行の絞り込みは RLS が担うため、ここでは表単位の DML を一括で許可する。

GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE
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
TO authenticated;
