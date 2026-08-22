-- RPC 関数 7本
-- 正本: docs/02_設計/50_詳細設計/01_DB物理設計.md §3.6
-- 契約: 各 docs/02_設計/50_詳細設計/08_機能別詳細設計/FEAT-*.md
--
-- 共通の約束:
--   実行権限   全7本 SECURITY INVOKER。RLS を迂回しない
--   引数       user_id を取らない。本人は auth.uid() が解決する（ADR-0005）
--   引数名     p_ 接頭辞・snake_case
--   栄養値     numeric(6,1)（ADR-0022）
--   日付       引数で受け取る。関数内で CURRENT_DATE を使わない（ADR-0014）
--   算出       行わない。素の値だけ返す。calc_target_protein_g は作らない
--   独自エラー PTxyz の SQLSTATE。xyz がそのまま HTTP ステータスになる

-- ---------------------------------------------------------------------------
-- 1. create_machine（FEAT-01 C-01）
--    training_machines ＋ machine_menus を1トランザクションで書く
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.create_machine(
  p_gym_id   bigint,
  p_name     text,
  p_menu_ids bigint[]
)
RETURNS bigint
LANGUAGE plpgsql
SECURITY INVOKER
AS $$
DECLARE v_machine_id bigint;
BEGIN
  -- 種目0件の器具を作らせない（FEAT-01 §3.5）
  IF p_menu_ids IS NULL OR array_length(p_menu_ids, 1) IS NULL THEN
    RAISE EXCEPTION 'ERR-MACHINE-003';
    -- [仮] SQLSTATE は既定の P0001。独自コード（PTxyz）にするかは FEAT-01 §10 #12 で未決
  END IF;

  INSERT INTO training_machines (gym_id, name)
  VALUES (p_gym_id, p_name)
  RETURNING id INTO v_machine_id;

  INSERT INTO machine_menus (machine_id, menu_id)
  SELECT v_machine_id, t.menu_id
  FROM unnest(p_menu_ids) AS t(menu_id);

  RETURN v_machine_id;   -- 例外発生時は関数全体がロールバック
END;
$$;

COMMENT ON FUNCTION public.create_machine IS
  '器具登録（FEAT-01 C-01）。器具1行と紐づけ複数行を1トランザクションで作る';

-- ---------------------------------------------------------------------------
-- 2. update_machine（FEAT-01 C-03）
--    紐づけは差分計算せず全置換する
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.update_machine(
  p_machine_id bigint,
  p_gym_id     bigint,
  p_name       text,
  p_menu_ids   bigint[]
)
RETURNS bigint
LANGUAGE plpgsql
SECURITY INVOKER
AS $$
DECLARE v_machine_id bigint;
BEGIN
  IF p_menu_ids IS NULL OR array_length(p_menu_ids, 1) IS NULL THEN
    RAISE EXCEPTION 'ERR-MACHINE-003';   -- [仮] SQLSTATE は create_machine と同じ扱い
  END IF;

  UPDATE training_machines
     SET gym_id = p_gym_id, name = p_name
   WHERE id = p_machine_id
  RETURNING id INTO v_machine_id;

  IF v_machine_id IS NULL THEN
    RETURN NULL;   -- 不在・RLS で不可視。呼び出し側が ERR-MACHINE-006 に写像する
  END IF;

  DELETE FROM machine_menus WHERE machine_id = p_machine_id;
  INSERT INTO machine_menus (machine_id, menu_id)
  SELECT p_machine_id, t.menu_id
  FROM unnest(p_menu_ids) AS t(menu_id);

  RETURN v_machine_id;
END;
$$;

COMMENT ON FUNCTION public.update_machine IS
  '器具更新（FEAT-01 C-03）。紐づけは全置換。対象が無ければ null を返す';

-- ---------------------------------------------------------------------------
-- 3. delete_machine（FEAT-01 C-04）
--    子行の DELETE は書かない。担保は FK の ON DELETE CASCADE に一本化する
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.delete_machine(p_machine_id bigint)
RETURNS bigint
LANGUAGE plpgsql
SECURITY INVOKER
AS $$
DECLARE v_machine_id bigint;
BEGIN
  DELETE FROM training_machines
   WHERE id = p_machine_id
  RETURNING id INTO v_machine_id;

  RETURN v_machine_id;   -- 不在・RLS で不可視は null
END;
$$;

COMMENT ON FUNCTION public.delete_machine IS
  '器具削除（FEAT-01 C-04）。中間行は FK の ON DELETE CASCADE で消える';

-- ---------------------------------------------------------------------------
-- 4. create_training_session（FEAT-04 T01）
--    セッション1行と明細 n 行を1トランザクションで作る（ST-01 で作成）
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.create_training_session(
  p_performed_date date,
  p_menu_ids       bigint[],
  p_is_done        boolean[]
)
RETURNS bigint
LANGUAGE plpgsql
SECURITY INVOKER
AS $$
DECLARE v_session_id bigint;
BEGIN
  -- 所有者検証: 本人の training_menus に無いIDが混ざっていたら中断（ERR-TRAINING-003）
  IF (SELECT count(*) FROM training_menus m WHERE m.id = ANY(p_menu_ids)) <> array_length(p_menu_ids, 1) THEN
    RAISE EXCEPTION 'ERR-TRAINING-003';
  END IF;

  INSERT INTO training_sessions (user_id, performed_date)
  VALUES (auth.uid(), p_performed_date)
  RETURNING id INTO v_session_id;

  INSERT INTO training_session_details (session_id, menu_id, is_done)
  SELECT v_session_id, t.menu_id, t.is_done
  FROM unnest(p_menu_ids, p_is_done) AS t(menu_id, is_done);
  -- uq_training_session_details_session_menu が重複を拒否する

  RETURN v_session_id;   -- 例外発生時は関数全体がロールバック
END;
$$;

COMMENT ON FUNCTION public.create_training_session IS
  'トレーニング記録（FEAT-04 T01）。セッションと明細を1トランザクションで作る';

-- ---------------------------------------------------------------------------
-- 5. get_dashboard（FEAT-05）
--    当日のゲージ素値・今月の実施日数・表示範囲のヒートマップを1往復で返す
--    target_g・rate_pct は返さない。算出は Dart（ADR-0016）
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.get_dashboard(
  p_period      text default 'month',
  p_today       date default null,
  p_range_start date default null,
  p_range_end   date default null,
  p_month_start date default null,
  p_month_end   date default null
)
RETURNS json
LANGUAGE plpgsql
STABLE
SECURITY INVOKER
SET search_path = public
AS $$
declare
  v_user_id uuid;
  v_weight  numeric(6,1);
  v_target  int;
  v_intake  numeric(6,1);
  v_done    int;
  v_heatmap json;
begin
  -- (1) 引数検証 → ERR-DASHBOARD-001
  if p_period is null or p_period not in ('day', 'week', 'month') then
    raise exception 'ERR-DASHBOARD-001' using errcode = 'PT400';
  end if;
  if p_range_start > p_range_end or p_month_start > p_month_end then
    raise exception 'ERR-DASHBOARD-001' using errcode = 'PT400';
  end if;

  -- (2) 本人の users 行を解決 → 無ければ ERR-DASHBOARD-002
  select u.id into v_user_id from users u where u.id = auth.uid();
  if not found then
    raise exception 'ERR-DASHBOARD-002' using errcode = 'PT409';
  end if;

  -- (3) ゲージの素値（体重・目標回数・当日の摂取合計）
  select g.weight_kg, g.target_training_count, g.intake_g
    into v_weight, v_target, v_intake
    from (
      SELECT u.weight_kg,
             u.target_training_count,
             COALESCE(SUM(m.protein_g), 0)::numeric(6,1) AS intake_g
      FROM users u
      LEFT JOIN meal_logs m
             ON m.user_id = u.id
            AND m.eaten_date = p_today
      WHERE u.id = v_user_id
      GROUP BY u.id, u.weight_kg, u.target_training_count
    ) g;

  -- (4) 実施日の集約を CTE に1本化し、ヒートマップと今月の実施日数の両方を取る
  with done_dates as (
    SELECT s.performed_date AS date,
           COALESCE(
             array_agg(DISTINCT mn.name ORDER BY mn.name) FILTER (WHERE d.is_done),
             ARRAY[]::text[]
           ) AS menu_names
    FROM training_sessions s
    LEFT JOIN training_session_details d ON d.session_id = s.id
    LEFT JOIN training_menus          mn ON mn.id = d.menu_id
    WHERE s.user_id = v_user_id
      AND s.performed_date BETWEEN least(p_range_start, p_month_start)
                               AND greatest(p_range_end, p_month_end)
    GROUP BY s.performed_date
    HAVING bool_or(d.is_done)   -- 塗る条件: is_done が1件以上 true の日だけ
  )
  select
    coalesce(
      (select json_agg(
                json_build_object('date', x.date, 'done', true, 'menu_names', x.menu_names)
                order by x.date)
         from done_dates x
        where x.date between p_range_start and p_range_end),
      '[]'::json),
    (select count(*) from done_dates x
      where x.date between p_month_start and p_month_end)
    into v_heatmap, v_done;

  return json_build_object(
    'protein_gauge',
      case when v_weight is null then null   -- 体重未設定はエラーにしない
           else json_build_object('weight_kg', v_weight, 'intake_g', v_intake)
      end,
    'training_count', json_build_object('done_days', v_done, 'target', v_target),
    'heatmap',        v_heatmap
  );
end;
$$;

COMMENT ON FUNCTION public.get_dashboard IS
  'ダッシュボード集計（FEAT-05）。素の値のみ返す。target_g・rate_pct は Dart が算出する';

-- ---------------------------------------------------------------------------
-- 6. get_protein_remaining（FEAT-09）
--    体重・当日の摂取合計・食品候補行を素のまま返す
--    target_g・remaining_g は返さない。算出は Dart（ADR-0016）
--    実装の合否: abs() / limit / round() / * 2.0 が1つも現れないこと
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.get_protein_remaining(
  p_target_date date
)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY INVOKER
SET search_path = public
AS $$
declare
  v_weight numeric(6,1);
  v_intake numeric(6,1);
  v_result jsonb;
begin
  -- 体重＋当日のタンパク質摂取合計。対象日は p_target_date のみで絞る（ADR-0014）
  -- 合計は protein_g の単純 SUM。係数を掛ける列は持たない（ADR-0013）
  select u.weight_kg, coalesce(sum(m.protein_g), 0)
    into v_weight, v_intake
    from users u
    left join meal_logs m
      on  m.user_id    = u.id
      and m.eaten_date = p_target_date
   where u.id = auth.uid()
   group by u.weight_kg;

  -- 候補行はそのまま返す。並べ替えも件数の切り出しもしない
  select jsonb_build_object(
           'weight_kg', v_weight,
           'intake_g',  v_intake,
           'foods_candidates', coalesce(s.arr, '[]'::jsonb)
         )
    into v_result
    from (
      select jsonb_agg(
               jsonb_build_object(
                 'id',             f.id,
                 'food_name',      f.name,
                 'protein_amount', f.protein_amount)
               order by f.id asc
             ) as arr
        from foods f
    ) s;

  return v_result;
end;
$$;

COMMENT ON FUNCTION public.get_protein_remaining IS
  'タンパク質残量の素値（FEAT-09）。残量と候補の選定は Dart が行う';

-- ---------------------------------------------------------------------------
-- 7. import_foods（FEAT-10）
--    検証済み・正規化済みの行を一括 INSERT する。既存と同名の行はスキップする
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.import_foods(p_rows jsonb)
RETURNS TABLE (inserted_count bigint, skipped_count bigint)
LANGUAGE plpgsql
SECURITY INVOKER
AS $$
declare v_total bigint; v_inserted bigint;
begin
  select count(*) into v_total from jsonb_array_elements(p_rows);
  with i as (
    insert into foods (name, protein_amount)
    select r.name, r.protein_amount
      from jsonb_to_recordset(p_rows) as r(name text, protein_amount numeric(6,1))
    on conflict (name) do nothing
    returning 1
  ) select count(*) into v_inserted from i;
  -- skipped は「送った件数 − 入った件数」。do nothing は既存行を返さないため
  return query select v_inserted, v_total - v_inserted;
end $$;

COMMENT ON FUNCTION public.import_foods IS
  '食事マスタ取込（FEAT-10）。追加＋重複スキップ。既存値は上書きしない';

-- ---------------------------------------------------------------------------
-- 実行権限
-- anon には渡さない。認証済みのみ（NFR-SEC-01）
-- ---------------------------------------------------------------------------
REVOKE EXECUTE ON FUNCTION
  public.create_machine(bigint, text, bigint[]),
  public.update_machine(bigint, bigint, text, bigint[]),
  public.delete_machine(bigint),
  public.create_training_session(date, bigint[], boolean[]),
  public.get_dashboard(text, date, date, date, date, date),
  public.get_protein_remaining(date),
  public.import_foods(jsonb)
FROM PUBLIC, anon;

GRANT EXECUTE ON FUNCTION
  public.create_machine(bigint, text, bigint[]),
  public.update_machine(bigint, bigint, text, bigint[]),
  public.delete_machine(bigint),
  public.create_training_session(date, bigint[], boolean[]),
  public.get_dashboard(text, date, date, date, date, date),
  public.get_protein_remaining(date),
  public.import_foods(jsonb)
TO authenticated;
