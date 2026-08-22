-- INDEX・制約名からテーブル名の略称を外す
-- 正本: docs/02_設計/50_詳細設計/06_DB設計規約.md（2026-08-08 確定）
--
-- 規約は ix_<テーブル名>_<列の要約> / uq_<テーブル名>_<列の要約> / ck_<テーブル名>_<意味>。
-- 略し方（先頭2語か頭字語か）の合意コストが高く、テーブルが増えるたびに揺れが再生産される。
-- 略さないほうが機械的で迷わない。DDL の書き換えだけで済み、データ移行は伴わない。
--
-- 長さの上限に当たる場合だけ略す。PostgreSQL の識別子は63バイトまでで、本PJの10表では当たらない。

ALTER INDEX public.ix_train_sessions_user_date
  RENAME TO ix_training_sessions_user_date;

ALTER INDEX public.uq_tsd_session_menu
  RENAME TO uq_training_session_details_session_menu;

ALTER INDEX public.uq_mm_machine_menu
  RENAME TO uq_machine_menus_machine_menu;

ALTER INDEX public.ix_mm_menu
  RENAME TO ix_machine_menus_menu;
