/*
 * Part 2.8 — Memory and Resource Configuration
 * [TUTORIAL-ACCEPTANCE — SAFE-READ]
 *
 * Target: PostgreSQL 18
 *
 * Purpose:
 *   Capture a read-only resource/configuration snapshot for Part 2.8.
 *
 * Safety:
 *   - No DDL
 *   - No DML
 *   - No SET / ALTER SYSTEM
 *   - No configuration reload/restart
 *   - No session termination
 *   - No OS/kernel changes
 *
 * Notes:
 *   pg_stat_database.temp_files/temp_bytes are cumulative statistics.
 *   Compare values across a defined observation window when investigating
 *   temporary-I/O behavior.
 */

\echo '=== Part 2.8: Memory and Resource Configuration — SAFE-READ ==='

\echo ''
\echo '--- Server identity ---'
SELECT
    current_database() AS database_name,
    current_user       AS current_user,
    version()          AS server_version;

\echo ''
\echo '--- Memory and resource settings ---'
SELECT
    name,
    setting,
    unit,
    context,
    source
FROM pg_settings
WHERE name IN (
    'shared_buffers',
    'work_mem',
    'maintenance_work_mem',
    'autovacuum_work_mem',
    'temp_buffers',
    'effective_cache_size',
    'wal_buffers',
    'hash_mem_multiplier',
    'vacuum_buffer_usage_limit',
    'huge_pages',
    'huge_page_size',
    'huge_pages_status',
    'max_connections',
    'max_worker_processes',
    'max_parallel_workers',
    'max_parallel_workers_per_gather'
)
ORDER BY name;

\echo ''
\echo '--- Connection state summary ---'
SELECT
    state,
    count(*) AS connections
FROM pg_stat_activity
GROUP BY state
ORDER BY connections DESC, state NULLS LAST;

\echo ''
\echo '--- Application/session summary ---'
SELECT
    COALESCE(NULLIF(application_name, ''), '<unset>') AS application_name,
    state,
    count(*) AS connections
FROM pg_stat_activity
WHERE pid <> pg_backend_pid()
GROUP BY
    COALESCE(NULLIF(application_name, ''), '<unset>'),
    state
ORDER BY connections DESC, application_name, state NULLS LAST;

\echo ''
\echo '--- Database temporary-I/O counters (cumulative) ---'
SELECT
    datname,
    temp_files,
    temp_bytes,
    pg_size_pretty(temp_bytes) AS temp_written
FROM pg_stat_database
WHERE datname = current_database();

\echo ''
\echo '--- Parallel-worker configuration ---'
SELECT
    name,
    setting,
    unit,
    context,
    source
FROM pg_settings
WHERE name IN (
    'max_worker_processes',
    'max_parallel_workers',
    'max_parallel_workers_per_gather'
)
ORDER BY name;

\echo ''
\echo '=== SAFE-READ COMPLETE: no PostgreSQL state was intentionally changed ==='
