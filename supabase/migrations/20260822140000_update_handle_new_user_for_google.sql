-- サインアップ時の name の解決を Google OAuth に合わせる
-- 正本: docs/意思決定_ADR/0023-auth-method-google-oauth.md
--       docs/02_設計/50_詳細設計/01_DB物理設計.md §3.1
--
-- 認証は Google ログイン（OAuth）に確定した（ADR-0023）。
-- Google は表示名を raw_user_meta_data の full_name に入れる。
-- プロバイダによって name / email しか無い場合もあるため順に落とす。
--
-- users.name は NOT NULL のため、最後に空文字でフォールバックする。
-- 表示名は FEAT-06（初期設定）で上書きできる。ここで入るのは初期値にすぎない。

CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER          -- auth.users を読むために要る（唯一の DEFINER・§3.6）
SET search_path = public
AS $$
BEGIN
  INSERT INTO public.users (id, name)
  VALUES (
    NEW.id,
    COALESCE(
      NEW.raw_user_meta_data ->> 'full_name',   -- Google が入れるキー
      NEW.raw_user_meta_data ->> 'name',        -- 他プロバイダ・手動作成
      NEW.raw_user_meta_data ->> 'email',       -- 表示名が無い場合
      ''                                        -- users.name は NOT NULL
    )
  );
  RETURN NEW;
END;
$$;

COMMENT ON FUNCTION public.handle_new_user IS
  'サインアップ時に public.users を作る（ADR-0005）。name は Google の full_name を優先する（ADR-0023）';
