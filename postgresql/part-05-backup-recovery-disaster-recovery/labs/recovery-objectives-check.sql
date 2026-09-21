/*
===============================================================================
Part 5.12 — RPO, RTO, Retention, and Backup Capacity Planning
Hands-On Lab / Draft Acceptance Artifact

[TUTORIAL-ACCEPTANCE — SAFE-READ]

Target: PostgreSQL 18

Purpose:
  Collect PostgreSQL-visible evidence useful for recovery-objective and
  backup-capacity planning.

IMPORTANT:
  RPO, RTO, retention, backup repository capacity, and restore capacity
  cannot be proven by this SQL artifact alone.

This artifact DOES NOT:
  - create/delete backups;
  - delete archived WAL;
  - execute pg_dump/pg_basebackup/pg_restore;
  - reset PostgreSQL statistics;
  - force a WAL switch;
  - execute CHECKPOINT;
  - create/drop/advance replication slots;
  - create restore points;
  - change archive configuration;
  - change retention policy;
  - change PostgreSQL configuration.

Run this artifact at multiple timestamps if WAL-rate deltas are required.
Before calculating a rate, confirm pg_stat_wal.stats_reset is identical across
both samples. If the baseline changed, the rate is UNKNOWN and that interval
must be discarded. Do not reset statistics merely to simplify rate measurement.
Missing/inaccessible evidence is UNKNOWN, not zero.
===============================================================================
*/

\set ON_ERROR_STOP on

\echo '======================================================================'
\echo 'Part 5.12 — Recovery Objectives / Capacity Evidence — SAFE-READ'
\echo '======================================================================'

-- ---------------------------------------------------------------------------
-- 1. Server identity
-- ---------------------------------------------------------------------------

\echo ''
\echo '[1/10] Server identity'

SELECT
    current_database() AS connected_database,
    current_user AS current_user_name,
    version() AS server_version,
    current_setting('server_version_num') AS server_version_num,
    pg_postmaster_start_time() AS postmaster_start_time,
    current_timestamp AS observed_at;

-- ---------------------------------------------------------------------------
-- 2. Database-size inventory
-- ---------------------------------------------------------------------------

\echo ''
\echo '[2/10] Database-size inventory'

SELECT
    d.datname,
    pg_catalog.pg_get_userbyid(d.datdba) AS owner,
    d.datallowconn,
    pg_catalog.pg_database_size(d.datname) AS size_bytes,
    pg_catalog.pg_size_pretty(
        pg_catalog.pg_database_size(d.datname)
    ) AS size_pretty
FROM pg_catalog.pg_database AS d
WHERE d.datallowconn
ORDER BY pg_catalog.pg_database_size(d.datname) DESC;

-- ---------------------------------------------------------------------------
-- 3. Aggregate database-size evidence
-- ---------------------------------------------------------------------------

\echo ''
\echo '[3/10] Aggregate database-size evidence'

SELECT
    count(*) FILTER (WHERE datallowconn) AS connectable_database_count,
    sum(pg_catalog.pg_database_size(datname))
        FILTER (WHERE datallowconn) AS summed_database_bytes,
    pg_catalog.pg_size_pretty(
        sum(pg_catalog.pg_database_size(datname))
            FILTER (WHERE datallowconn)
    ) AS summed_database_pretty
FROM pg_catalog.pg_database;

\echo ''
\echo 'NOTE: Summed database size is planning evidence, not physical/compressed'
\echo 'backup artifact size. Measure real backup artifacts separately.'

-- ---------------------------------------------------------------------------
-- 4. WAL-generation cumulative statistics
-- ---------------------------------------------------------------------------

\echo ''
\echo '[4/10] WAL-generation cumulative statistics'

SELECT
    wal_records,
    wal_fpi,
    wal_bytes,
    pg_catalog.pg_size_pretty(wal_bytes) AS wal_bytes_pretty,
    stats_reset,
    current_timestamp AS observed_at
FROM pg_catalog.pg_stat_wal;

\echo ''
\echo 'IMPORTANT: wal_bytes is cumulative since stats_reset.'
\echo 'Calculate WAL rate only from two samples with the SAME stats_reset baseline.'
\echo 'Do not interpret wal_bytes directly as daily WAL generation.'
\echo 'If stats_reset changed between samples, discard the interval as UNKNOWN.'

-- ---------------------------------------------------------------------------
-- 5. WAL archiver evidence
-- ---------------------------------------------------------------------------

\echo ''
\echo '[5/10] WAL archiver evidence'

SELECT
    archived_count,
    failed_count,
    last_archived_wal,
    last_archived_time,
    last_failed_wal,
    last_failed_time,
    stats_reset
FROM pg_catalog.pg_stat_archiver;

\echo ''
\echo 'NOTE: pg_stat_archiver activity does not prove remote WAL completeness,'
\echo 'readability, retention, or successful PITR.'

-- ---------------------------------------------------------------------------
-- 6. Recovery / WAL configuration evidence
-- ---------------------------------------------------------------------------

\echo ''
\echo '[6/10] Recovery / WAL configuration evidence'

SELECT
    name,
    setting,
    unit,
    source,
    pending_restart
FROM pg_catalog.pg_settings
WHERE name IN (
    'wal_level',
    'archive_mode',
    'archive_command',
    'archive_library',
    'wal_keep_size',
    'max_slot_wal_keep_size',
    'idle_replication_slot_timeout',
    'max_replication_slots',
    'max_wal_size',
    'min_wal_size'
)
ORDER BY name;

\echo ''
\echo 'SECURITY NOTE: Review evidence handling if archive_command contains'
\echo 'environment-sensitive command text.'

-- ---------------------------------------------------------------------------
-- 7. Replication-slot retention evidence
-- ---------------------------------------------------------------------------

\echo ''
\echo '[7/10] Replication-slot retention evidence'

WITH wal_position AS (
    SELECT
        CASE
            WHEN pg_catalog.pg_is_in_recovery()
                THEN pg_catalog.pg_last_wal_replay_lsn()
            ELSE pg_catalog.pg_current_wal_lsn()
        END AS observed_lsn
)
SELECT
    s.slot_name,
    s.slot_type,
    s.database,
    s.active,
    s.inactive_since,
    s.restart_lsn,
    s.confirmed_flush_lsn,
    s.wal_status,
    s.safe_wal_size,
    s.invalidation_reason,
    CASE
        WHEN s.restart_lsn IS NULL OR w.observed_lsn IS NULL THEN NULL
        ELSE pg_catalog.pg_wal_lsn_diff(w.observed_lsn, s.restart_lsn)
    END AS approximate_retained_wal_bytes,
    CASE
        WHEN s.restart_lsn IS NULL OR w.observed_lsn IS NULL THEN NULL
        ELSE pg_catalog.pg_size_pretty(
            pg_catalog.pg_wal_lsn_diff(w.observed_lsn, s.restart_lsn)
        )
    END AS approximate_retained_wal_pretty
FROM pg_catalog.pg_replication_slots AS s
CROSS JOIN wal_position AS w
ORDER BY approximate_retained_wal_bytes DESC NULLS LAST, s.slot_name;

\echo ''
\echo 'NOTE: LSN distance is retention-pressure evidence, not exact filesystem'
\echo 'space attributable exclusively to a slot.'

-- ---------------------------------------------------------------------------
-- 8. Tablespace inventory and database-visible size
-- ---------------------------------------------------------------------------

\echo ''
\echo '[8/10] Tablespace inventory'

SELECT
    t.spcname,
    pg_catalog.pg_get_userbyid(t.spcowner) AS owner,
    pg_catalog.pg_tablespace_location(t.oid) AS location,
    pg_catalog.pg_tablespace_size(t.oid) AS size_bytes,
    pg_catalog.pg_size_pretty(
        pg_catalog.pg_tablespace_size(t.oid)
    ) AS size_pretty
FROM pg_catalog.pg_tablespace AS t
ORDER BY pg_catalog.pg_tablespace_size(t.oid) DESC;

\echo ''
\echo 'Treat tablespace locations as potentially environment-sensitive evidence.'

-- ---------------------------------------------------------------------------
-- 9. Recovery-state evidence
-- ---------------------------------------------------------------------------

\echo ''
\echo '[9/10] Recovery-state evidence'

SELECT
    pg_catalog.pg_is_in_recovery() AS is_in_recovery,
    CASE
        WHEN pg_catalog.pg_is_in_recovery()
            THEN pg_catalog.pg_last_wal_replay_lsn()
        ELSE pg_catalog.pg_current_wal_lsn()
    END AS observed_wal_position,
    CASE
        WHEN pg_catalog.pg_is_in_recovery()
            THEN pg_catalog.pg_last_xact_replay_timestamp()
        ELSE NULL
    END AS last_replayed_transaction_timestamp,
    current_timestamp AS observed_at;

-- ---------------------------------------------------------------------------
-- 10. Compact planning summary
-- ---------------------------------------------------------------------------

\echo ''
\echo '[10/10] Compact planning summary'

WITH db AS (
    SELECT
        count(*) FILTER (WHERE datallowconn) AS database_count,
        sum(pg_catalog.pg_database_size(datname))
            FILTER (WHERE datallowconn) AS database_bytes
    FROM pg_catalog.pg_database
),
slots AS (
    SELECT
        count(*) AS slot_count,
        count(*) FILTER (WHERE NOT active) AS inactive_slot_count,
        count(*) FILTER (
            WHERE wal_status IN ('unreserved', 'lost')
               OR invalidation_reason IS NOT NULL
        ) AS slot_risk_count
    FROM pg_catalog.pg_replication_slots
),
wal AS (
    SELECT wal_bytes, stats_reset
    FROM pg_catalog.pg_stat_wal
),
archiver AS (
    SELECT
        archived_count,
        failed_count,
        last_archived_time,
        last_failed_time
    FROM pg_catalog.pg_stat_archiver
)
SELECT
    db.database_count,
    db.database_bytes,
    pg_catalog.pg_size_pretty(db.database_bytes) AS database_size_pretty,
    wal.wal_bytes AS cumulative_wal_bytes,
    pg_catalog.pg_size_pretty(wal.wal_bytes) AS cumulative_wal_pretty,
    wal.stats_reset AS wal_stats_reset,
    slots.slot_count,
    slots.inactive_slot_count,
    slots.slot_risk_count,
    archiver.archived_count,
    archiver.failed_count,
    archiver.last_archived_time,
    archiver.last_failed_time,
    current_timestamp AS observed_at
FROM db
CROSS JOIN slots
CROSS JOIN wal
CROSS JOIN archiver;

\echo ''
\echo '======================================================================'
\echo 'SAFE-READ recovery-capacity evidence collection complete.'
\echo ''
\echo 'This artifact does NOT prove:'
\echo '  * business RPO compliance;'
\echo '  * business RTO compliance;'
\echo '  * backup retention compliance;'
\echo '  * backup repository capacity;'
\echo '  * remote WAL completeness;'
\echo '  * backup integrity;'
\echo '  * PITR success;'
\echo '  * restore throughput or restore capacity.'
\echo ''
\echo 'Combine this evidence with backup-platform metrics, storage telemetry,'
\echo 'business recovery requirements, and recurring isolated restore tests.'
\echo '======================================================================'
