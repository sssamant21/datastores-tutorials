-- ============================================================
-- PostgreSQL Part 7.1 - Storage Architecture Fundamentals
-- File: storage-architecture-check.sql
-- Target: PostgreSQL 18
-- Classification: SAFE-READ
--
-- NO DDL, DML, CHECKPOINT, VACUUM, statistics reset,
-- configuration/tablespace/filesystem/WAL changes, or termination.
-- ============================================================

\set ON_ERROR_STOP on

\echo '=== 1. Execution context ==='
SELECT clock_timestamp() AS observed_at,
       version() AS postgres_version,
       current_database() AS database_name,
       current_user AS session_user,
       pg_is_in_recovery() AS is_in_recovery;

\echo '=== 2. Core storage configuration ==='
SELECT current_setting('data_directory') AS data_directory,
       current_setting('block_size')::bigint AS block_size_bytes,
       pg_size_pretty(current_setting('block_size')::bigint) AS block_size_pretty;

\echo '=== 3. Tablespaces ==='
SELECT oid AS tablespace_oid,
       spcname AS tablespace_name,
       pg_tablespace_location(oid) AS tablespace_location
FROM pg_tablespace
ORDER BY spcname;

\echo '=== 4. Current database size ==='
SELECT current_database() AS database_name,
       pg_database_size(current_database()) AS database_size_bytes,
       pg_size_pretty(pg_database_size(current_database())) AS database_size_pretty;

\echo '=== 5. Largest user tables by total size ==='
SELECT n.nspname AS schema_name,
       c.relname AS relation_name,
       c.relkind,
       pg_relation_size(c.oid) AS main_fork_bytes,
       pg_size_pretty(pg_relation_size(c.oid)) AS main_fork_pretty,
       pg_table_size(c.oid) AS table_bytes,
       pg_size_pretty(pg_table_size(c.oid)) AS table_pretty,
       pg_indexes_size(c.oid) AS indexes_bytes,
       pg_size_pretty(pg_indexes_size(c.oid)) AS indexes_pretty,
       pg_total_relation_size(c.oid) AS total_bytes,
       pg_size_pretty(pg_total_relation_size(c.oid)) AS total_pretty
FROM pg_class AS c
JOIN pg_namespace AS n ON n.oid = c.relnamespace
WHERE c.relkind IN ('r','m','p')
  AND n.nspname NOT IN ('pg_catalog','information_schema')
  AND n.nspname !~ '^pg_toast'
ORDER BY pg_total_relation_size(c.oid) DESC
LIMIT 20;

\echo '=== 6. PostgreSQL-managed relation paths ==='
\echo 'Returned paths are relative to the cluster data directory.'
SELECT n.nspname AS schema_name,
       c.relname AS relation_name,
       c.relkind,
       pg_relation_filepath(c.oid) AS relation_filepath,
       c.relpages AS catalog_relpages_estimate
FROM pg_class AS c
JOIN pg_namespace AS n ON n.oid = c.relnamespace
WHERE c.relkind IN ('r','m')
  AND n.nspname NOT IN ('pg_catalog','information_schema')
  AND n.nspname !~ '^pg_toast'
  AND pg_relation_filepath(c.oid) IS NOT NULL
ORDER BY pg_total_relation_size(c.oid) DESC
LIMIT 20;

\echo 'NOTE: relpages is an estimate, not an exact live filesystem block count.'

\echo '=== 7. Fork sizes for largest user relations ==='
WITH largest AS (
    SELECT c.oid, n.nspname, c.relname,
           pg_total_relation_size(c.oid) AS total_bytes
    FROM pg_class AS c
    JOIN pg_namespace AS n ON n.oid = c.relnamespace
    WHERE c.relkind IN ('r','m')
      AND n.nspname NOT IN ('pg_catalog','information_schema')
      AND n.nspname !~ '^pg_toast'
    ORDER BY pg_total_relation_size(c.oid) DESC
    LIMIT 10
)
SELECT nspname AS schema_name,
       relname AS relation_name,
       pg_relation_size(oid,'main') AS main_bytes,
       pg_relation_size(oid,'fsm') AS fsm_bytes,
       pg_relation_size(oid,'vm') AS vm_bytes,
       total_bytes,
       pg_size_pretty(total_bytes) AS total_pretty
FROM largest
ORDER BY total_bytes DESC;

\echo '=== 8. Page/block interpretation ==='
WITH settings AS (
    SELECT current_setting('block_size')::bigint AS block_size
),
largest AS (
    SELECT c.oid, n.nspname, c.relname,
           pg_relation_size(c.oid,'main') AS main_bytes
    FROM pg_class AS c
    JOIN pg_namespace AS n ON n.oid = c.relnamespace
    WHERE c.relkind IN ('r','m')
      AND n.nspname NOT IN ('pg_catalog','information_schema')
      AND n.nspname !~ '^pg_toast'
    ORDER BY pg_relation_size(c.oid,'main') DESC
    LIMIT 10
)
SELECT l.nspname AS schema_name,
       l.relname AS relation_name,
       s.block_size AS block_size_bytes,
       l.main_bytes,
       CASE WHEN s.block_size > 0
            THEN l.main_bytes / s.block_size
       END AS main_fork_blocks
FROM largest AS l
CROSS JOIN settings AS s
ORDER BY l.main_bytes DESC;

\echo '=== 9. WAL position / recovery-state evidence ==='
SELECT pg_is_in_recovery() AS is_in_recovery,
       CASE
           WHEN pg_is_in_recovery() THEN NULL
           ELSE pg_current_wal_lsn()
       END AS current_primary_wal_lsn,
       CASE
           WHEN pg_is_in_recovery()
               THEN 'NOT APPLICABLE: server is in recovery'
           ELSE 'OBSERVED: primary-side current WAL LSN'
       END AS evidence_status;

\echo '=== 10. PostgreSQL 18 WAL statistics ==='
SELECT wal_records,
       wal_fpi,
       wal_bytes,
       wal_buffers_full,
       wal_write,
       wal_sync,
       wal_write_time,
       wal_sync_time,
       stats_reset
FROM pg_stat_wal;

\echo '=== 11. PostgreSQL 18 checkpointer statistics ==='
SELECT num_timed,
       num_requested,
       num_done,
       restartpoints_timed,
       restartpoints_req,
       restartpoints_done,
       write_time,
       sync_time,
       buffers_written,
       stats_reset
FROM pg_stat_checkpointer;

\echo '=== 12. Evidence interpretation ==='
SELECT clock_timestamp() AS completed_at,
       'OBSERVED'::text AS lab_execution_status,
       'Unavailable evidence remains UNKNOWN; review each section independently.'::text
           AS interpretation;

\echo '=== Part 7.1 SAFE-READ evidence collection complete ==='
\echo 'WAL != heap storage'
\echo 'WAL flush != dirty-page flush'
\echo 'COMMIT != CHECKPOINT'
\echo 'CHECKPOINT != backup'
\echo 'database size != required filesystem capacity'
\echo 'missing evidence != healthy'
