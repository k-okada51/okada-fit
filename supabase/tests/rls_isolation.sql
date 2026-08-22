-- RLS の分離検証（W-03）
-- 正本: docs/02_設計/60_テスト設計/01_テスト戦略.md §2「RLS のテスト」
--
-- RLS は本PJで唯一の防御線である。anon キーはアプリに埋め込まれ公開されるため、
-- ポリシーの記述漏れがそのまま情報漏えいになる。
--
-- 2人目のアカウントは作らない。auth.uid() を SQL で差し替えて検証する。
-- RLS は request.jwt.claims の sub を読むだけで、署名検証は PostgREST の手前で終わっている。
--
-- 【重要】本番DBでは絶対に実行しない。ローカルの supabase start 環境だけで行う。
-- 【注意】psql の変数（:'name'）は $$ の中で展開されない。UUID は直書きする。
--
-- 実行:
--   docker exec -i supabase_db_okada-fit \
--     psql -U postgres -d postgres -v ON_ERROR_STOP=1 < supabase/tests/rls_isolation.sql
--
-- 期待: PASS が7つ出て ROLLBACK で終わる。FAIL が出たらポリシーに漏れがある。

BEGIN;

-- ---------------------------------------------------------------------------
-- 準備: 利用者A・利用者B を作る（postgres ロールなので RLS を素通りする）
--   A = 11111111-1111-1111-1111-111111111111
--   B = 22222222-2222-2222-2222-222222222222
-- auth.users への INSERT でトリガ handle_new_user が public.users を作る
-- ---------------------------------------------------------------------------
INSERT INTO auth.users (id, email, raw_user_meta_data)
VALUES ('11111111-1111-1111-1111-111111111111', 'a@example.test', '{"name":"利用者A"}'::jsonb),
       ('22222222-2222-2222-2222-222222222222', 'b@example.test', '{"name":"利用者B"}'::jsonb)
ON CONFLICT (id) DO NOTHING;

INSERT INTO training_menus (user_id, name, body_part, how_to)
VALUES ('11111111-1111-1111-1111-111111111111', 'A専用ベンチプレス', '胸', 'Aだけのやり方');

-- ---------------------------------------------------------------------------
-- 検証: 利用者B として振る舞う
--   SET LOCAL ROLE が無いと postgres のまま RLS を素通りする（最頻の誤り）
-- ---------------------------------------------------------------------------
SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claims = '{"sub":"22222222-2222-2222-2222-222222222222","role":"authenticated"}';

DO $$
BEGIN
  IF auth.uid() <> '22222222-2222-2222-2222-222222222222'::uuid THEN
    RAISE EXCEPTION 'FAIL[0]: auth.uid() の差し替えが効いていない（実際=%）', auth.uid();
  END IF;
  RAISE NOTICE 'PASS[0] auth.uid() が利用者B になっている';
END $$;

-- [1] 本人のみ区分: 他人の種目が見えないこと
DO $$
DECLARE n int;
BEGIN
  SELECT count(*) INTO n FROM training_menus WHERE name = 'A専用ベンチプレス';
  IF n <> 0 THEN RAISE EXCEPTION 'FAIL[1]: 他人の training_menus が % 件見えた', n; END IF;
  RAISE NOTICE 'PASS[1] training_menus: 他人の行は見えない';
END $$;

-- [2] 本人のみ区分: 他人の行を UPDATE できないこと
DO $$
DECLARE n int;
BEGIN
  WITH u AS (UPDATE training_menus SET name = '乗っ取り' WHERE name = 'A専用ベンチプレス' RETURNING 1)
  SELECT count(*) INTO n FROM u;
  IF n <> 0 THEN RAISE EXCEPTION 'FAIL[2]: 他人の行を % 件更新できた', n; END IF;
  RAISE NOTICE 'PASS[2] training_menus: 他人の行は更新できない';
END $$;

-- [3] 本人のみ区分: 他人の行を DELETE できないこと
DO $$
DECLARE n int;
BEGIN
  WITH d AS (DELETE FROM training_menus WHERE name = 'A専用ベンチプレス' RETURNING 1)
  SELECT count(*) INTO n FROM d;
  IF n <> 0 THEN RAISE EXCEPTION 'FAIL[3]: 他人の行を % 件削除できた', n; END IF;
  RAISE NOTICE 'PASS[3] training_menus: 他人の行は削除できない';
END $$;

-- [4] 本人のみ区分: 他人になりすまして INSERT できないこと（WITH CHECK）
DO $$
BEGIN
  BEGIN
    INSERT INTO training_menus (user_id, name, body_part)
    VALUES ('11111111-1111-1111-1111-111111111111', 'なりすまし', '胸');
    RAISE EXCEPTION 'FAIL[4]: 他人の user_id で INSERT できた';
  EXCEPTION WHEN insufficient_privilege THEN
    RAISE NOTICE 'PASS[4] training_menus: 他人の user_id では INSERT できない';
  END;
END $$;

-- [5] 本人のみ区分: users も同じ規則であること
DO $$
DECLARE n int;
BEGIN
  SELECT count(*) INTO n FROM users WHERE id = '11111111-1111-1111-1111-111111111111';
  IF n <> 0 THEN RAISE EXCEPTION 'FAIL[5]: 他人の users 行が見えた'; END IF;
  RAISE NOTICE 'PASS[5] users: 他人の行は見えない';
END $$;

-- [6] 親経由区分: 他人の種目にぶら下がる machine_menus が見えないこと
DO $$
DECLARE n int;
BEGIN
  SELECT count(*) INTO n FROM machine_menus mm
    JOIN training_menus m ON m.id = mm.menu_id
   WHERE m.user_id = '11111111-1111-1111-1111-111111111111';
  IF n <> 0 THEN RAISE EXCEPTION 'FAIL[6]: 他人の machine_menus が % 件見えた', n; END IF;
  RAISE NOTICE 'PASS[6] machine_menus: 親経由でも他人の行は見えない';
END $$;

-- [7] 共通マスタ区分: gyms / training_machines / foods は「読める」のが正
DO $$
BEGIN
  PERFORM 1 FROM gyms              LIMIT 1;
  PERFORM 1 FROM training_machines LIMIT 1;
  PERFORM 1 FROM foods             LIMIT 1;
  RAISE NOTICE 'PASS[7] 共通マスタ3表: 認証済みなら読める（遮断されないのが正）';
END $$;

ROLLBACK;   -- テストデータを残さない
