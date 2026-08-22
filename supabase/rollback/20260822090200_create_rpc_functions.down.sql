-- 20260822090200_create_rpc_functions.sql の取り消し
-- 引数の型まで指定して落とす（同名のオーバーロードを誤って消さないため）

DROP FUNCTION IF EXISTS public.import_foods(jsonb);
DROP FUNCTION IF EXISTS public.get_protein_remaining(date);
DROP FUNCTION IF EXISTS public.get_dashboard(text, date, date, date, date, date);
DROP FUNCTION IF EXISTS public.create_training_session(date, bigint[], boolean[]);
DROP FUNCTION IF EXISTS public.delete_machine(bigint);
DROP FUNCTION IF EXISTS public.update_machine(bigint, bigint, text, bigint[]);
DROP FUNCTION IF EXISTS public.create_machine(bigint, text, bigint[]);
