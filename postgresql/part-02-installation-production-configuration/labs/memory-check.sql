/*
 * Part 2.12 — Memory Configuration and Resource Management
 * [TUTORIAL-ACCEPTANCE — SAFE-READ]
 * Target: PostgreSQL 18
 *
 * No DDL / DML
 * No SET / ALTER SYSTEM
 * No pg_reload_conf()
 * No pg_stat_reset()
 * No EXPLAIN ANALYZE
 * No VACUUM / CREATE INDEX
 * No memory-context log dump
 * No filesystem operations
 * No restart
 */

\echo '=== Part 2.12 — Memory Configuration and Resource Management — SAFE-READ ==='

\echo ''
\echo '--- Server identity ---'
SELECT
    current_database() AS database_name,
    current_user AS current_user,
    version() AS server_version;

\echo ''
\echo '--- Memory and resource configuration ---'
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
    'vacuum_buffer_usage_limit',
    'temp_buffers',
    'effective_cache_size',
    'huge_pages',
    'huge_pages_status',
    'huge_page_size',
    'max_connections',
    'autovacuum_max_workers',
    'max_worker_processes',
    'max_parallel_workers',
    'max_parallel_workers_per_gather',
    'max_parallel_maintenance_workers'
)
ORDER BY name;

\echo ''
\echo '--- Current client backend state ---'
SELECT
    state,
    COUNT(*) AS sessions
FROM pg_stat_activity
WHERE backend_type = 'client backend'
GROUP BY state
ORDER BY state;

\echo ''
\echo '--- Current database temporary-file and parallel-worker statistics ---'
SELECT
    datname,
    temp_files,
    temp_bytes,
    parallel_workers_to_launch,
    parallel_workers_launched
FROM pg_stat_database
WHERE datname = current_database();

\echo ''
\echo '=== SAFE-READ COMPLETE: no PostgreSQL state was intentionally changed ==='
