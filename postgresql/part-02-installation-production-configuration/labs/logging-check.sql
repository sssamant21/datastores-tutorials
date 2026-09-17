-- Part 2.12
-- [TUTORIAL-ACCEPTANCE — SAFE-READ]
\set ON_ERROR_STOP on
\pset pager off

SELECT current_setting('server_version') AS server_version;

SELECT name, setting, unit, context, source, pending_restart
FROM pg_settings
WHERE name IN (
 'logging_collector','log_destination','log_directory','log_filename',
 'log_rotation_age','log_rotation_size','log_truncate_on_rotation',
 'log_min_messages','log_min_error_statement','log_min_duration_statement',
 'log_connections','log_disconnections','log_checkpoints','log_lock_waits',
 'log_lock_failures','log_temp_files','log_autovacuum_min_duration',
 'log_error_verbosity','log_line_prefix','compute_query_id','track_activities',
 'track_counts','track_io_timing','track_wal_io_timing'
)
ORDER BY name;

SELECT datname, numbackends, xact_commit, xact_rollback,
       blks_read, blks_hit, temp_files, temp_bytes, deadlocks
FROM pg_stat_database
WHERE datname IS NOT NULL
ORDER BY datname;
