-- okada-fit スキーマ（設計 50_DB物理設計 / ADR-0004 準拠）
-- Supabase の SQL Editor にそのまま貼り付けて実行する。
-- 前提: Supabase Auth（auth.users）。各テーブルは user_id で本人分離し RLS で保護する。

-- ============================================================
-- 1. マスタ系
-- ============================================================

create table if not exists public.gyms (
  id          bigint generated always as identity primary key,
  user_id     uuid not null references auth.users(id) on delete cascade,
  name        text not null,                       -- ジム名
  created_at  timestamptz not null default now()
);

create table if not exists public.training_menus (
  id          bigint generated always as identity primary key,
  user_id     uuid not null references auth.users(id) on delete cascade,
  name        text not null,                       -- 種目名
  body_part   text not null check (body_part in ('胸','背中','脚','肩','腕')),  -- DEC-B04
  how_to      text,                                -- やり方メモ
  created_at  timestamptz not null default now()
);

create table if not exists public.training_machines (
  id          bigint generated always as identity primary key,
  user_id     uuid not null references auth.users(id) on delete cascade,
  gym_id      bigint not null references public.gyms(id) on delete cascade,
  menu_id     bigint references public.training_menus(id) on delete set null,
  name        text not null,                       -- マシン名
  created_at  timestamptz not null default now()
);

create table if not exists public.foods (
  id              bigint generated always as identity primary key,
  user_id         uuid not null references auth.users(id) on delete cascade,
  name            text not null,                   -- 食品名
  protein_amount  double precision not null check (protein_amount >= 0),  -- タンパク質量(g)
  created_at      timestamptz not null default now()
);

-- プロフィール（1ユーザー1行。auth.users.id を主キーに）
create table if not exists public.profiles (
  user_id                uuid primary key references auth.users(id) on delete cascade,
  weight_kg              double precision check (weight_kg > 0),      -- 体重
  target_training_count  int check (target_training_count >= 0),      -- 週の目標トレ回数
  created_at             timestamptz not null default now(),
  updated_at             timestamptz not null default now()
);

-- ============================================================
-- 2. 履歴系
-- ============================================================

create table if not exists public.gym_visits (
  id          bigint generated always as identity primary key,
  user_id     uuid not null references auth.users(id) on delete cascade,
  gym_id      bigint references public.gyms(id) on delete set null,
  visit_date  date not null,                       -- 入館日
  visit_time  time,                                -- 入館時刻
  created_at  timestamptz not null default now()
);

create table if not exists public.training_sessions (
  id              bigint generated always as identity primary key,
  user_id         uuid not null references auth.users(id) on delete cascade,
  performed_date  date not null,                   -- 実施日（ヒートマップの集計元）
  created_at      timestamptz not null default now()
);

create table if not exists public.training_session_details (
  id          bigint generated always as identity primary key,
  session_id  bigint not null references public.training_sessions(id) on delete cascade,
  menu_id     bigint not null references public.training_menus(id) on delete cascade,
  is_done     boolean not null default false,      -- 実行済フラグ
  created_at  timestamptz not null default now(),
  unique (session_id, menu_id)                     -- 同一トレで同一種目の重複防止
);

-- 食事記録（写真は保存しない・ADR-0003。栄養4項目のみ）
create table if not exists public.meal_logs (
  id             bigint generated always as identity primary key,
  user_id        uuid not null references auth.users(id) on delete cascade,
  calories_kcal  double precision not null check (calories_kcal >= 0),
  protein_g      double precision not null check (protein_g >= 0),
  sugar_g        double precision not null check (sugar_g >= 0),
  fat_g          double precision not null check (fat_g >= 0),
  eaten_date     date not null,                    -- 摂取日
  eaten_time     time,                             -- 摂取時刻
  created_at     timestamptz not null default now()
);

-- ============================================================
-- 3. インデックス（ダッシュボード表示・NFR-PERF-01）
-- ============================================================
create index if not exists ix_gym_visits_user_date       on public.gym_visits(user_id, visit_date);
create index if not exists ix_train_sessions_user_date    on public.training_sessions(user_id, performed_date);
create index if not exists ix_meal_logs_user_date         on public.meal_logs(user_id, eaten_date);

-- ============================================================
-- 4. RLS（本人行のみ・ADR-0004 / DEC-D03）
--    全テーブルで user_id = auth.uid() の行だけ読み書き可。
-- ============================================================
do $$
declare t text;
begin
  foreach t in array array[
    'gyms','training_menus','training_machines','foods',
    'gym_visits','training_sessions','meal_logs'
  ]
  loop
    execute format('alter table public.%I enable row level security;', t);
    execute format($p$
      create policy %1$s_own on public.%1$I
      for all using (user_id = auth.uid()) with check (user_id = auth.uid());
    $p$, t);
  end loop;
end $$;

-- profiles（主キーが user_id）
alter table public.profiles enable row level security;
create policy profiles_own on public.profiles
  for all using (user_id = auth.uid()) with check (user_id = auth.uid());

-- training_session_details（user_id を持たず session 経由で本人判定）
alter table public.training_session_details enable row level security;
create policy tsd_own on public.training_session_details
  for all using (
    exists (select 1 from public.training_sessions s
            where s.id = session_id and s.user_id = auth.uid())
  ) with check (
    exists (select 1 from public.training_sessions s
            where s.id = session_id and s.user_id = auth.uid())
  );

-- ============================================================
-- 5. 新規ユーザー登録時に profiles を自動作成（任意・便利）
-- ============================================================
create or replace function public.handle_new_user()
returns trigger language plpgsql security definer as $$
begin
  insert into public.profiles (user_id) values (new.id)
  on conflict (user_id) do nothing;
  return new;
end $$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();
