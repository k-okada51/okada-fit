-- RLS の分離検証（W-03）
-- 正本: docs/02_設計/60_テスト設計/01_テスト戦略.md §2「RLS のテスト」
--
-- RLS は本PJで唯一の防御線である。anon キーはアプリに埋め込まれ公開されるため、
-- ポリシーの記述漏れがそのまま情報漏えいになる。
--
-- 2人目のアカウントは作らない。auth.uid() を SQL で差し替えて検証する。
-- RLS は request.jwt.claims の sub を読むだけで、署名検証は PostgREST の手前で終わっている。
--
-- 【重要】必ず全体を BEGIN 〜 ROLLBACK で囲むこと。囲んである限り本番DBで実行してよい。
--         最後まで走っても途中で FAIL しても、テストデータは1件も残らない。
--         囲みを外すと本番にテストデータが残る。ROLLBACK を COMMIT に書き換えない。
-- 【注意】psql の変数（:'name'）は $$ の中で展開されない。UUID と ID は直書きする。
--
-- 実行（本番・リモートDB。supabase/.db-url は接続文字列）:
--   psql "$(cat supabase/.db-url)" -v ON_ERROR_STOP=1 -f supabase/tests/rls_isolation.sql
--
-- 実行（ローカルの supabase start 環境）:
--   docker exec -i supabase_db_okada-fit \
--     psql -U postgres -d postgres -v ON_ERROR_STOP=1 < supabase/tests/rls_isolation.sql
--
-- 期待: PASS が12個（PASS[0]〜PASS[11]）出て ROLLBACK で終わる。
--       FAIL が出たらポリシーに漏れがある。PASS が12個に満たなくても漏れである。

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

-- 履歴4表ぶんの A の行。FK の順に作る（gyms → gym_visits、training_sessions → 明細）。
-- id は bigint の IDENTITY で採番されるが、$$ の中から参照したいので
-- OVERRIDING SYSTEM VALUE で 900001 に固定する（psql 変数は $$ の中で使えないため）。
INSERT INTO gyms (id, name) OVERRIDING SYSTEM VALUE
VALUES (900001, 'RLS検証用ジム');

INSERT INTO gym_visits (user_id, gym_id, visit_date, visit_time)
VALUES ('11111111-1111-1111-1111-111111111111', 900001, DATE '2026-01-01', TIME '09:00');

INSERT INTO training_sessions (id, user_id, performed_date) OVERRIDING SYSTEM VALUE
VALUES (900001, '11111111-1111-1111-1111-111111111111', DATE '2026-01-01');

-- 明細は A のセッションに A の種目をぶら下げる（親経由区分の検証対象）
INSERT INTO training_session_details (session_id, menu_id, is_done)
VALUES (900001,
        (SELECT id FROM training_menus
          WHERE user_id = '11111111-1111-1111-1111-111111111111'
            AND name = 'A専用ベンチプレス'),
        true);

-- 栄養4項目は numeric(6,1)（ADR-0022）。float ではない
INSERT INTO meal_logs (user_id, calories_kcal, protein_g, sugar_g, fat_g, eaten_date, eaten_time)
VALUES ('11111111-1111-1111-1111-111111111111', 650.5, 32.5, 70.5, 20.5, DATE '2026-01-01', TIME '12:30');

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

-- [8] 本人のみ区分: gym_visits（入館履歴）
--     SELECT で見えない・UPDATE 0件・DELETE 0件・他人の user_id では INSERT できない
DO $$
DECLARE n int;
BEGIN
  SELECT count(*) INTO n FROM gym_visits
   WHERE user_id = '11111111-1111-1111-1111-111111111111';
  IF n <> 0 THEN RAISE EXCEPTION 'FAIL[8]: 他人の gym_visits が % 件見えた', n; END IF;

  WITH u AS (UPDATE gym_visits SET visit_date = DATE '2000-01-01'
              WHERE user_id = '11111111-1111-1111-1111-111111111111' RETURNING 1)
  SELECT count(*) INTO n FROM u;
  IF n <> 0 THEN RAISE EXCEPTION 'FAIL[8]: 他人の gym_visits を % 件更新できた', n; END IF;

  WITH d AS (DELETE FROM gym_visits
              WHERE user_id = '11111111-1111-1111-1111-111111111111' RETURNING 1)
  SELECT count(*) INTO n FROM d;
  IF n <> 0 THEN RAISE EXCEPTION 'FAIL[8]: 他人の gym_visits を % 件削除できた', n; END IF;

  BEGIN
    INSERT INTO gym_visits (user_id, gym_id, visit_date)
    VALUES ('11111111-1111-1111-1111-111111111111', 900001, DATE '2026-01-02');
    RAISE EXCEPTION 'FAIL[8]: 他人の user_id で gym_visits を作れた';
  EXCEPTION WHEN insufficient_privilege THEN
    RAISE NOTICE 'PASS[8] gym_visits: 他人の行は見えず・更新も削除もできず・他人の user_id では作れない';
  END;
END $$;

-- [9] 本人のみ区分: training_sessions（実施履歴の親）
DO $$
DECLARE n int;
BEGIN
  SELECT count(*) INTO n FROM training_sessions
   WHERE user_id = '11111111-1111-1111-1111-111111111111';
  IF n <> 0 THEN RAISE EXCEPTION 'FAIL[9]: 他人の training_sessions が % 件見えた', n; END IF;

  WITH u AS (UPDATE training_sessions SET performed_date = DATE '2000-01-01'
              WHERE user_id = '11111111-1111-1111-1111-111111111111' RETURNING 1)
  SELECT count(*) INTO n FROM u;
  IF n <> 0 THEN RAISE EXCEPTION 'FAIL[9]: 他人の training_sessions を % 件更新できた', n; END IF;

  WITH d AS (DELETE FROM training_sessions
              WHERE user_id = '11111111-1111-1111-1111-111111111111' RETURNING 1)
  SELECT count(*) INTO n FROM d;
  IF n <> 0 THEN RAISE EXCEPTION 'FAIL[9]: 他人の training_sessions を % 件削除できた', n; END IF;

  BEGIN
    INSERT INTO training_sessions (user_id, performed_date)
    VALUES ('11111111-1111-1111-1111-111111111111', DATE '2026-01-02');
    RAISE EXCEPTION 'FAIL[9]: 他人の user_id で training_sessions を作れた';
  EXCEPTION WHEN insufficient_privilege THEN
    RAISE NOTICE 'PASS[9] training_sessions: 他人の行は見えず・更新も削除もできず・他人の user_id では作れない';
  END;
END $$;

-- [10] 本人のみ区分: meal_logs（食事履歴）
--      本PJで最もプライベートなデータ。漏れると何をいつ食べたかが他人に見える
DO $$
DECLARE n int;
BEGIN
  SELECT count(*) INTO n FROM meal_logs
   WHERE user_id = '11111111-1111-1111-1111-111111111111';
  IF n <> 0 THEN RAISE EXCEPTION 'FAIL[10]: 他人の meal_logs が % 件見えた', n; END IF;

  WITH u AS (UPDATE meal_logs SET calories_kcal = 9999.9
              WHERE user_id = '11111111-1111-1111-1111-111111111111' RETURNING 1)
  SELECT count(*) INTO n FROM u;
  IF n <> 0 THEN RAISE EXCEPTION 'FAIL[10]: 他人の meal_logs を % 件更新できた', n; END IF;

  WITH d AS (DELETE FROM meal_logs
              WHERE user_id = '11111111-1111-1111-1111-111111111111' RETURNING 1)
  SELECT count(*) INTO n FROM d;
  IF n <> 0 THEN RAISE EXCEPTION 'FAIL[10]: 他人の meal_logs を % 件削除できた', n; END IF;

  -- 集計経由でも漏れないこと。SUM は行が見えなければ NULL になる
  SELECT count(*) INTO n FROM (
    SELECT sum(protein_g) AS s FROM meal_logs
     WHERE user_id = '11111111-1111-1111-1111-111111111111'
  ) t WHERE t.s IS NOT NULL;
  IF n <> 0 THEN RAISE EXCEPTION 'FAIL[10]: 他人の meal_logs が集計経由で読めた'; END IF;

  BEGIN
    INSERT INTO meal_logs (user_id, calories_kcal, protein_g, sugar_g, fat_g, eaten_date)
    VALUES ('11111111-1111-1111-1111-111111111111', 100.0, 10.0, 10.0, 10.0, DATE '2026-01-02');
    RAISE EXCEPTION 'FAIL[10]: 他人の user_id で meal_logs を作れた';
  EXCEPTION WHEN insufficient_privilege THEN
    RAISE NOTICE 'PASS[10] meal_logs: 他人の行は見えず（集計経由でも）・更新も削除もできず・他人の user_id では作れない';
  END;
END $$;

-- [11] 親経由区分: training_session_details（実施履歴の明細）
--      本表は user_id を持たない。本人性は session_id → training_sessions.user_id で判定される
DO $$
DECLARE n int; b_menu_id bigint;
BEGIN
  SELECT count(*) INTO n FROM training_session_details WHERE session_id = 900001;
  IF n <> 0 THEN RAISE EXCEPTION 'FAIL[11]: 他人のセッションの明細が % 件見えた', n; END IF;

  -- 親を JOIN しても見えないこと（親の行自体が見えないので 0 件が正）
  SELECT count(*) INTO n FROM training_session_details d
    JOIN training_sessions s ON s.id = d.session_id
   WHERE s.user_id = '11111111-1111-1111-1111-111111111111';
  IF n <> 0 THEN RAISE EXCEPTION 'FAIL[11]: 他人の明細が親経由で % 件見えた', n; END IF;

  WITH u AS (UPDATE training_session_details SET is_done = false
              WHERE session_id = 900001 RETURNING 1)
  SELECT count(*) INTO n FROM u;
  IF n <> 0 THEN RAISE EXCEPTION 'FAIL[11]: 他人の明細を % 件更新できた', n; END IF;

  WITH d AS (DELETE FROM training_session_details WHERE session_id = 900001 RETURNING 1)
  SELECT count(*) INTO n FROM d;
  IF n <> 0 THEN RAISE EXCEPTION 'FAIL[11]: 他人の明細を % 件削除できた', n; END IF;

  -- B 自身の種目であっても、A のセッションにはぶら下げられないこと（WITH CHECK）
  INSERT INTO training_menus (user_id, name, body_part)
  VALUES ('22222222-2222-2222-2222-222222222222', 'B専用スクワット', '脚')
  RETURNING id INTO b_menu_id;

  BEGIN
    INSERT INTO training_session_details (session_id, menu_id)
    VALUES (900001, b_menu_id);
    RAISE EXCEPTION 'FAIL[11]: 他人のセッションに明細を作れた';
  EXCEPTION WHEN insufficient_privilege THEN
    RAISE NOTICE 'PASS[11] training_session_details: 親経由でも他人の明細は見えず・書けない';
  END;
END $$;

ROLLBACK;   -- テストデータを残さない
