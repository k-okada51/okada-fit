-- meal_logs.user_id に DEFAULT auth.uid() を置く
-- 正本: docs/02_設計/50_詳細設計/08_機能別詳細設計/FEAT-08_食事撮影タンパク質計算.md §3.3
--
-- 設計は「user_id はクライアントから送らない」としつつ、DEFAULT を使うか否かを
-- `[仮]` のまま残していた。W-12（食事撮影）で決める必要が出たので DEFAULT を置く。
--
-- 置く理由。端末が自分の uuid を知っていなければ INSERT できない、という
-- 依存を作らないため。RLS の WITH CHECK (user_id = auth.uid()) は残るので、
-- 他人の uuid を送っても弾かれる。DEFAULT は「送らなくてよい」を保証するだけで、
-- 防御を肩代わりするものではない。
--
-- 他の履歴表（training_sessions など）には入れない。W-12 の範囲に閉じる。

ALTER TABLE public.meal_logs
  ALTER COLUMN user_id SET DEFAULT auth.uid();

COMMENT ON COLUMN public.meal_logs.user_id IS
  '本人の uuid。DEFAULT auth.uid() のため端末から送らない。防御は RLS の WITH CHECK';
