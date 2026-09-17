/*
 * Part 2.11 — Logging and Error Reporting Configuration
 * [TUTORIAL-ACCEPTANCE — SAFE-READ]
 * Target: PostgreSQL 18
 *
 * No DDL / DML
 * No SET / ALTER SYSTEM
 * No pg_reload_conf()
 * No intentional SQL errors
 * No statistics reset
 * No log rotation
 * No filesystem operations
 * No restart
 * No other-session SQL text inspection
 */

\echo '=== Part 2.11 — Logging and Error Reporting — SAFE-READ ==='

\echo ''
\echo '--- Server identity ---'
SELECT
    current_database() AS database_name,
    current_user AS current_user,
    version() AS server_version;

\echo ''
\echo '--- Logging configuration ---'
SELECT
    name,
    setting,
    unit,
    context,
    source,
    pending_restart
FROM pg_settings
WHERE name IN (
    'log_destination',
    'logging_collector',
    'log_directory',
    'log_filename',
    'log_file_mode',
    'log_rotation_age',
    'log_rotation_size',
    'log_truncate_on_rotation',
    'log_min_messages',
    'log_min_error_statement',
    'log_min_duration_statement',
    'log_min_duration_sample',
    'log_statement',
    'log_duration',
    'log_connections',
    'log_disconnections',
    'log_error_verbosity',
    'log_line_prefix',
    'log_lock_waits',
    'log_lock_failures',
    'deadlock_timeout',
    'log_temp_files',
    'log_autovacuum_min_duration',
    'log_checkpoints',
    'log_recovery_conflict_waits',
    'log_parameter_max_length',
    'log_parameter_max_length_on_error',
    'log_statement_sample_rate',
    'log_transaction_sample_rate'
)
ORDER BY name;

\echo ''
\echo '--- Current session identity (no SQL text) ---'
SELECT
    pid,
    usename,
    datname,
    application_name,
    client_addr,
    state,
    backend_start,
    state_change
FROM pg_stat_activity
WHERE pid = pg_backend_pid();

\echo ''
\echo '=== SAFE-READ COMPLETE: no PostgreSQL state was intentionally changed ==='
