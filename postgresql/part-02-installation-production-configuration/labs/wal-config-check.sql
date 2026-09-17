-- Part 2.11
-- [TUTORIAL-ACCEPTANCE — SAFE-READ]
\set ON_ERROR_STOP on
\pset pager off

SELECT current_setting('server_version') AS server_version;

SELECT name, setting, unit, context, source, pending_restart
FROM pg_settings
WHERE name IN (
 'wal_level','wal_buffers','wal_compression','wal_sync_method',
 'synchronous_commit','fsync','full_page_writes',
 'checkpoint_timeout','checkpoint_completion_target',
 'max_wal_size','min_wal_size','archive_mode','max_wal_senders',
 'bgwriter_delay','bgwriter_lru_maxpages','bgwriter_lru_multiplier',
 'bgwriter_flush_after'
)
ORDER BY name;

SELECT * FROM pg_stat_checkpointer;
SELECT * FROM pg_stat_bgwriter;
SELECT * FROM pg_stat_wal;
