-- users とサインアップ時のトリガ
-- 正本: docs/02_設計/50_詳細設計/01_DB物理設計.md §1.1・§3.1（ADR-0005 案A）
--
-- id は採番しない。auth.users.id の値をそのまま入れる。
-- これにより RLS を `id = auth.uid()` の最短形で書ける（§3.4）。

CREATE TABLE public.users (
  id                    uuid        NOT NULL,
  name                  text        NOT NULL,
  target_training_count int         NULL,
  weight_kg             float       NULL,
  created_at            timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT users_pkey PRIMARY KEY (id),
  CONSTRAINT fk_users_auth_users FOREIGN KEY (id)
    REFERENCES auth.users (id) ON DELETE CASCADE,
  CONSTRAINT ck_users_target_training_count CHECK (target_training_count >= 0),
  CONSTRAINT ck_users_weight_kg CHECK (weight_kg > 0)
);

COMMENT ON TABLE public.users IS 'ユーザー。auth.users と1対1。体重は現在値1点のみ（ADR-0009）';

-- サインアップ時に users 行を作る（FEAT-06）。
-- SECURITY DEFINER のため search_path を固定する（未固定だと検索パス乗っ取りの余地が残る）。
CREATE FUNCTION public.handle_new_user()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  -- name の既定値は [仮]。サインアップ画面の入力項目（FEAT-06）で確定する
  INSERT INTO public.users (id, name)
  VALUES (NEW.id, COALESCE(NEW.raw_user_meta_data ->> 'name', ''));
  RETURN NEW;
END;
$$;

CREATE TRIGGER on_auth_user_created
AFTER INSERT ON auth.users
FOR EACH ROW EXECUTE FUNCTION public.handle_new_user();
