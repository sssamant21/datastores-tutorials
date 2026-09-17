-- ============================================================================
-- Part 3.1 — Database Administration Fundamentals
-- File: labs/database-admin-check.sql
-- Classification: [TUTORIAL-ACCEPTANCE — SAFE-READ]
-- Target: PostgreSQL 18
--
-- SAFETY CONTRACT
--
-- This script intentionally performs observational queries only.
--
-- IMPORTANT:
--   * SAFE-READ does not mean zero operational cost.
--   * Some observations may require additional privileges.
--   * Permission failures are not automatically PostgreSQL health failures.
--
-- This script must not:
--   * create, alter, or drop database objects;
--   * modify application data;
--   * terminate or cancel sessions;
--   * reset PostgreSQL statistics;
--   * reload or modify configuration;
--   * invoke maintenance operations;
--   * change roles or privileges.
-- ============================================================================

\set ON_ERROR_STOP on
\pset pager off

\echo '======================================================================'
\echo 'Part 3.1 — Database Administration Fundamentals'
\echo '[TUTORIAL-ACCEPTANCE — SAFE-READ]'
\echo '======================================================================'

\echo ''
\echo 'CHECK 1 — Session and server identity'
SELECT
    current_database()  AS database_name,
    current_user        AS current_user,
    session_user        AS session_user,
    inet_server_addr()  AS server_address,
    inet_server_port()  AS server_port,
    pg_is_in_recovery() AS in_recovery;

\echo ''
\echo 'CHECK 2 — PostgreSQL version'
SELECT version();

\echo ''
\echo 'CHECK 3 — Database inventory'
SELECT
    d.oid,
    d.datname,
    pg_get_userbyid(d.datdba) AS owner,
    d.datallowconn,
    d.datconnlimit,
    d.datistemplate
FROM pg_database AS d
ORDER BY d.datname;

\echo ''
\echo 'CHECK 4 — Database ownership'
SELECT
    d.datname,
    pg_get_userbyid(d.datdba) AS owner
FROM pg_database AS d
ORDER BY d.datname;

\echo ''
\echo 'CHECK 5 — Database connection policy'
SELECT
    d.datname,
    d.datallowconn,
    d.datconnlimit
FROM pg_database AS d
ORDER BY d.datname;

\echo ''
\echo 'CHECK 6 — Template databases'
SELECT
    d.datname,
    d.datistemplate,
    d.datallowconn
FROM pg_database AS d
WHERE d.datistemplate
   OR d.datname IN ('template0', 'template1')
ORDER BY d.datname;

\echo ''
\echo 'CHECK 7 — Current database size'
SELECT
    current_database() AS database_name,
    pg_database_size(current_database()) AS size_bytes,
    pg_size_pretty(pg_database_size(current_database())) AS size_pretty;

\echo ''
\echo 'CHECK 8 — Sizes of connectable databases'
\echo 'NOTE: another database size may require CONNECT or pg_read_all_stats.'
SELECT
    d.datname,
    pg_database_size(d.datname) AS size_bytes,
    pg_size_pretty(pg_database_size(d.datname)) AS size_pretty
FROM pg_database AS d
WHERE d.datallowconn
ORDER BY pg_database_size(d.datname) DESC NULLS LAST,
         d.datname;

\echo ''
\echo 'CHECK 9 — Current database connection counts'
\echo 'NOTE: numbackends means connected backends, not executing queries.'
SELECT
    s.datname,
    s.numbackends
FROM pg_stat_database AS s
WHERE s.datname IS NOT NULL
ORDER BY s.numbackends DESC,
         s.datname;

\echo ''
\echo 'CHECK 10 — Cumulative transaction statistics'
SELECT
    s.datname,
    s.xact_commit,
    s.xact_rollback
FROM pg_stat_database AS s
WHERE s.datname IS NOT NULL
ORDER BY s.datname;

\echo ''
\echo 'CHECK 11 — Cumulative block statistics'
SELECT
    s.datname,
    s.blks_read,
    s.blks_hit
FROM pg_stat_database AS s
WHERE s.datname IS NOT NULL
ORDER BY s.datname;

\echo ''
\echo 'CHECK 12 — Cumulative tuple activity'
SELECT
    s.datname,
    s.tup_returned,
    s.tup_fetched,
    s.tup_inserted,
    s.tup_updated,
    s.tup_deleted
FROM pg_stat_database AS s
WHERE s.datname IS NOT NULL
ORDER BY s.datname;

\echo ''
\echo 'CHECK 13 — Statistics reset timestamps'
SELECT
    s.datname,
    s.stats_reset
FROM pg_stat_database AS s
WHERE s.datname IS NOT NULL
ORDER BY s.datname;

\echo ''
\echo 'CHECK 14 — Acceptance safety confirmation'
SELECT
    current_database() IS NOT NULL AS database_detected,
    current_user IS NOT NULL AS user_detected,
    EXISTS (
        SELECT 1
        FROM pg_database
        WHERE datname = current_database()
    ) AS current_database_cataloged;

\echo ''
\echo '======================================================================'
\echo 'SAFE-READ LAB COMPLETE'
\echo 'No database objects or application data were intentionally modified.'
\echo '======================================================================'
