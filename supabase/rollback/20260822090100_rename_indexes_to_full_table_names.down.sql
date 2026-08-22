-- 20260822090100_rename_indexes_to_full_table_names.sql の取り消し

ALTER INDEX public.ix_machine_menus_menu                    RENAME TO ix_mm_menu;
ALTER INDEX public.uq_machine_menus_machine_menu            RENAME TO uq_mm_machine_menu;
ALTER INDEX public.uq_training_session_details_session_menu RENAME TO uq_tsd_session_menu;
ALTER INDEX public.ix_training_sessions_user_date           RENAME TO ix_train_sessions_user_date;
