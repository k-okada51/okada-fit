-- マスタ系テーブル
-- 正本: docs/02_設計/50_詳細設計/01_DB物理設計.md §1.2〜§1.6
--
-- gyms / training_machines / foods は共通マスタで user_id を持たない（2026-08-08 確定）。
-- 器具↔種目は machine_menus による多対多（2026-08-08 改訂）。

CREATE TABLE public.gyms (
  id         bigint      GENERATED ALWAYS AS IDENTITY,
  name       text        NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT gyms_pkey PRIMARY KEY (id)
);

COMMENT ON TABLE public.gyms IS 'ジム（共通マスタ）。器具や入館履歴が残るジムは削除できない';

CREATE TABLE public.training_menus (
  id         bigint      GENERATED ALWAYS AS IDENTITY,
  user_id    uuid        NOT NULL,
  name       text        NOT NULL,
  body_part  text        NOT NULL,
  how_to     text        NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT training_menus_pkey PRIMARY KEY (id),
  CONSTRAINT fk_training_menus_users FOREIGN KEY (user_id)
    REFERENCES public.users (id) ON DELETE CASCADE,
  CONSTRAINT ck_training_menus_body_part
    CHECK (body_part IN ('胸', '背中', '脚', '肩', '腕'))
);

COMMENT ON TABLE public.training_menus IS '種目マスタ。履歴のある種目は物理削除できない（ADR-0006）';

CREATE TABLE public.training_machines (
  id         bigint      GENERATED ALWAYS AS IDENTITY,
  gym_id     bigint      NOT NULL,
  name       text        NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT training_machines_pkey PRIMARY KEY (id),
  CONSTRAINT fk_training_machines_gyms FOREIGN KEY (gym_id)
    REFERENCES public.gyms (id) ON DELETE NO ACTION
);

COMMENT ON TABLE public.training_machines IS '器具マスタ（共通マスタ）。対応種目は machine_menus が持つ';

CREATE TABLE public.foods (
  id             bigint      GENERATED ALWAYS AS IDENTITY,
  name           text        NOT NULL,
  protein_amount float       NOT NULL,
  created_at     timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT foods_pkey PRIMARY KEY (id),
  CONSTRAINT ck_foods_protein_amount CHECK (protein_amount >= 0)
);

COMMENT ON TABLE public.foods IS '食品マスタ（共通マスタ）。protein_amount は1食分あたりのg（ADR-0012）';
COMMENT ON COLUMN public.foods.name IS '正規化後の文字列。正規化は Flutter 側で行う（FEAT-10）';

-- 同名の食品の二重登録を DB 側で防ぐ（ADR-0007）。import_foods の ON CONFLICT 先でもある
CREATE UNIQUE INDEX uq_foods_name ON public.foods (name);

CREATE TABLE public.machine_menus (
  id         bigint      GENERATED ALWAYS AS IDENTITY,
  machine_id bigint      NOT NULL,
  menu_id    bigint      NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT machine_menus_pkey PRIMARY KEY (id),
  CONSTRAINT fk_machine_menus_training_machines FOREIGN KEY (machine_id)
    REFERENCES public.training_machines (id) ON DELETE CASCADE,
  CONSTRAINT fk_machine_menus_training_menus FOREIGN KEY (menu_id)
    REFERENCES public.training_menus (id) ON DELETE CASCADE
);

COMMENT ON TABLE public.machine_menus IS '器具×種目の多対多。器具の部位は本表を介して training_menus.body_part から導く';

CREATE UNIQUE INDEX uq_mm_machine_menu ON public.machine_menus (machine_id, menu_id);
-- 部位→種目→器具の絞り込み（FEAT-02）で使う
CREATE INDEX ix_mm_menu ON public.machine_menus (menu_id);
