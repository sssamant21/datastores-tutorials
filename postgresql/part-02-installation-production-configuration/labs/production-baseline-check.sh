#!/usr/bin/env bash
# Part 2.14 — Production Configuration Baseline and Validation
# [TUTORIAL-ACCEPTANCE — SAFE-READ]
# Target: PostgreSQL 18
#
# This script intentionally performs PostgreSQL read-only inspection.
# It does NOT:
#   - edit configuration files
#   - run ALTER SYSTEM
#   - reload or restart PostgreSQL
#   - modify pg_hba.conf / pg_ident.conf
#   - change roles/passwords/TLS/firewalls
#   - terminate sessions
#   - reset statistics
#   - execute DDL or DML
#
# Authentication should use normal libpq mechanisms such as .pgpass,
# PGPASSFILE, a secret manager wrapper, or another approved method.
# Do not hard-code passwords in this file.

set -euo pipefail

command -v psql >/dev/null 2>&1 || {
  echo "ERROR: psql is required but was not found in PATH." >&2
  exit 1
}

PSQL=(psql -X -v ON_ERROR_STOP=1 --no-psqlrc)

echo "=== Part 2.14 — Production Configuration Baseline — SAFE-READ ==="
echo

"${PSQL[@]}" <<'SQL'
\pset pager off

\echo '--- Server identity ---'
SELECT
    current_database() AS database_name,
    current_user AS current_user,
    version() AS server_version,
    pg_postmaster_start_time() AS postmaster_start_time;

\echo ''
\echo '--- Configuration locations ---'
SELECT
    name,
    setting
FROM pg_settings
WHERE name IN (
    'data_directory',
    'config_file',
    'hba_file',
    'ident_file'
)
ORDER BY name;

\echo ''
\echo '--- Pending restart ---'
SELECT
    name,
    setting,
    unit,
    context,
    source,
    pending_restart
FROM pg_settings
WHERE pending_restart
ORDER BY name;

\echo ''
\echo '--- Core memory and resource baseline ---'
SELECT
    name,
    setting,
    unit,
    context,
    source,
    pending_restart
FROM pg_settings
WHERE name IN (
    'shared_buffers',
    'work_mem',
    'hash_mem_multiplier',
    'maintenance_work_mem',
    'autovacuum_work_mem',
    'temp_buffers',
    'effective_cache_size',
    'huge_pages',
    'max_worker_processes',
    'max_parallel_workers',
    'max_parallel_workers_per_gather',
    'io_method',
    'io_workers',
    'io_max_concurrency'
)
ORDER BY name;

\echo ''
\echo '--- Connection, network, and timeout baseline ---'
SELECT
    name,
    setting,
    unit,
    context,
    source,
    pending_restart
FROM pg_settings
WHERE name IN (
    'listen_addresses',
    'port',
    'ssl',
    'max_connections',
    'reserved_connections',
    'superuser_reserved_connections',
    'authentication_timeout',
    'statement_timeout',
    'lock_timeout',
    'transaction_timeout',
    'idle_in_transaction_session_timeout',
    'idle_session_timeout',
    'client_connection_check_interval'
)
ORDER BY name;

\echo ''
\echo '--- Client sessions by state ---'
SELECT
    state,
    COUNT(*) AS sessions
FROM pg_stat_activity
WHERE backend_type = 'client backend'
GROUP BY state
ORDER BY state;

\echo ''
\echo '--- WAL and checkpoint baseline (command text redacted) ---'
SELECT
    name,
    CASE
        WHEN name IN ('archive_command', 'archive_library')
            THEN CASE WHEN setting = '' THEN '<empty>' ELSE '<configured>' END
        ELSE setting
    END AS setting,
    unit,
    context,
    source,
    pending_restart
FROM pg_settings
WHERE name IN (
    'wal_level',
    'wal_buffers',
    'wal_compression',
    'checkpoint_timeout',
    'checkpoint_completion_target',
    'max_wal_size',
    'min_wal_size',
    'archive_mode',
    'archive_command',
    'archive_library',
    'max_wal_senders',
    'bgwriter_delay',
    'bgwriter_lru_maxpages',
    'bgwriter_lru_multiplier'
)
ORDER BY name;

\echo ''
\echo '--- Logging and diagnostic baseline ---'
SELECT
    name,
    setting,
    unit,
    context,
    source,
    pending_restart
FROM pg_settings
WHERE name IN (
    'logging_collector',
    'log_destination',
    'log_min_messages',
    'log_min_error_statement',
    'log_connections',
    'log_disconnections',
    'log_checkpoints',
    'log_lock_waits',
    'log_lock_failures',
    'log_temp_files',
    'log_autovacuum_min_duration',
    'log_error_verbosity'
)
ORDER BY name;

\echo ''
\echo '--- Configuration-file errors (privilege dependent) ---'
\echo 'If permission is denied here, run this section only with an approved role.'
SELECT
    sourcefile,
    sourceline,
    name,
    applied,
    error
FROM pg_file_settings
WHERE error IS NOT NULL
ORDER BY seqno;

\echo ''
\echo '--- Authentication-file parse errors (privilege dependent) ---'
\echo 'Rule details are intentionally not printed by this generic acceptance artifact.'
SELECT
    rule_number,
    error
FROM pg_hba_file_rules
WHERE error IS NOT NULL
ORDER BY rule_number;

\echo ''
\echo '=== SAFE-READ COMPLETE: no PostgreSQL state was intentionally changed ==='
SQL
