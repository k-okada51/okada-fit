-- 20260822140000_update_handle_new_user_for_google.sql の取り消し
-- 直前の定義（name のみ参照）へ戻す

CREATE OR REPLACE FUNCTION public.handle_new_user()
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
