-- down: 20260808045256_create_history_tables.sql
-- 適用: psql で手動（移行設計 §3.3 規約5）
--
-- ⚠️ テーブルを落とすため、格納済みの履歴は失われる。
--    データが入った後の切戻しはバックアップからの復元が要る（移行設計 §5）。

DROP TABLE IF EXISTS public.meal_logs;
DROP TABLE IF EXISTS public.training_session_details;
DROP TABLE IF EXISTS public.training_sessions;
DROP TABLE IF EXISTS public.gym_visits;
