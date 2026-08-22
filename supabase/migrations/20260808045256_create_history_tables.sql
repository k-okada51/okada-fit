-- 履歴系テーブル
-- 正本: docs/02_設計/50_詳細設計/01_DB物理設計.md §2.1〜§2.4
--
-- 業務日付は date（TZを持たない）。端末TZでアプリが決めて渡す（ADR-0014）。
-- サーバ側で CURRENT_DATE を使わない。

CREATE TABLE public.gym_visits (
  id         bigint      GENERATED ALWAYS AS IDENTITY,
  user_id    uuid        NOT NULL,
  gym_id     bigint      NOT NULL,
  visit_date date        NOT NULL,
  visit_time time        NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT gym_visits_pkey PRIMARY KEY (id),
  CONSTRAINT fk_gym_visits_users FOREIGN KEY (user_id)
    REFERENCES public.users (id) ON DELETE CASCADE,
  CONSTRAINT fk_gym_visits_gyms FOREIGN KEY (gym_id)
    REFERENCES public.gyms (id) ON DELETE NO ACTION
);

CREATE INDEX ix_gym_visits_user_date ON public.gym_visits (user_id, visit_date);

CREATE TABLE public.training_sessions (
  id             bigint      GENERATED ALWAYS AS IDENTITY,
  user_id        uuid        NOT NULL,
  performed_date date        NOT NULL,
  created_at     timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT training_sessions_pkey PRIMARY KEY (id),
  CONSTRAINT fk_training_sessions_users FOREIGN KEY (user_id)
    REFERENCES public.users (id) ON DELETE CASCADE
);

COMMENT ON TABLE public.training_sessions IS '種目は本表に持たず training_session_details 側で保持する';

CREATE INDEX ix_train_sessions_user_date ON public.training_sessions (user_id, performed_date);

CREATE TABLE public.training_session_details (
  id         bigint      GENERATED ALWAYS AS IDENTITY,
  session_id bigint      NOT NULL,
  menu_id    bigint      NOT NULL,
  is_done    boolean     NOT NULL DEFAULT false,
  created_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT training_session_details_pkey PRIMARY KEY (id),
  CONSTRAINT fk_training_session_details_training_sessions FOREIGN KEY (session_id)
    REFERENCES public.training_sessions (id) ON DELETE CASCADE,
  -- NO ACTION が「履歴のある種目は削除できない」を DB 側で担保する（ADR-0006）
  CONSTRAINT fk_training_session_details_training_menus FOREIGN KEY (menu_id)
    REFERENCES public.training_menus (id) ON DELETE NO ACTION
);

COMMENT ON TABLE public.training_session_details IS '実施有無（is_done）だけを持つ。回数・重量の列は無い（ADR-0008）';

CREATE UNIQUE INDEX uq_tsd_session_menu ON public.training_session_details (session_id, menu_id);

CREATE TABLE public.meal_logs (
  id            bigint      GENERATED ALWAYS AS IDENTITY,
  user_id       uuid        NOT NULL,
  calories_kcal float       NOT NULL,
  protein_g     float       NOT NULL,
  sugar_g       float       NOT NULL,
  fat_g         float       NOT NULL,
  eaten_date    date        NOT NULL,
  eaten_time    time        NULL,
  created_at    timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT meal_logs_pkey PRIMARY KEY (id),
  CONSTRAINT fk_meal_logs_users FOREIGN KEY (user_id)
    REFERENCES public.users (id) ON DELETE CASCADE,
  CONSTRAINT ck_meal_logs_nutrients CHECK (
    calories_kcal >= 0 AND protein_g >= 0 AND sugar_g >= 0 AND fat_g >= 0
  )
);

COMMENT ON TABLE public.meal_logs IS '食事写真・料理名は保持しない（ADR-0003）。摂取数の列も持たない（ADR-0013）';

CREATE INDEX ix_meal_logs_user_date ON public.meal_logs (user_id, eaten_date);
