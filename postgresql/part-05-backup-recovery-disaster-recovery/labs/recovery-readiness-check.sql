/*
===============================================================================
Part 5.14 — Production Backup/Recovery Runbook and Recovery Readiness
Canonical Acceptance Artifact

[TUTORIAL-ACCEPTANCE — SAFE-READ]
Target: PostgreSQL 18

Purpose:
  Collect PostgreSQL-visible evidence that can support a production recovery
  readiness review.

IMPORTANT:
  Successful execution does NOT prove that a backup exists, a restore works,
  PITR works, RPO/RTO are met, DR is ready, or an application can recover.

This artifact performs no backup, restore, promotion, configuration change,
WAL switch, checkpoint, slot mutation, retention change, or data modification.

SAFE-READ does not mean PUBLIC-SAFE. Protect captured operational evidence.
===============================================================================
*/

\set ON_ERROR_STOP on

\echo '======================================================================'
\echo 'Part 5.14 — Production Recovery Readiness Evidence — SAFE-READ'
\echo '======================================================================'

-- 1. Server identity
\echo ''
\echo '[1/11] Server identity'

SELECT
    current_database() AS connected_database,
    current_user AS current_user_name,
    version() AS server_version,
    current_setting('server_version_num') AS server_version_num,
    pg_postmaster_start_time() AS postmaster_start_time,
    current_timestamp AS observed_at;

-- 2. Recovery state
\echo ''
\echo '[2/11] Recovery state'

SELECT
    pg_catalog.pg_is_in_recovery() AS is_in_recovery,
    CASE WHEN pg_catalog.pg_is_in_recovery()
         THEN pg_catalog.pg_last_wal_receive_lsn() END AS last_wal_receive_lsn,
    CASE WHEN pg_catalog.pg_is_in_recovery()
         THEN pg_catalog.pg_last_wal_replay_lsn() END AS last_wal_replay_lsn,
    CASE WHEN pg_catalog.pg_is_in_recovery()
         THEN pg_catalog.pg_last_xact_replay_timestamp() END
         AS last_xact_replay_timestamp,
    current_timestamp AS observed_at;

-- 3. Database inventory
\echo ''
\echo '[3/11] Database inventory'

SELECT
    datname,
    pg_catalog.pg_size_pretty(pg_catalog.pg_database_size(datname)) AS database_size,
    datallowconn,
    datistemplate
FROM pg_catalog.pg_database
ORDER BY datname;

\echo 'NOTE: size collection is read-only but can still carry I/O/metadata cost.'

-- 4. Recovery/WAL settings
\echo ''
\echo '[4/11] Recovery / WAL settings'

SELECT
    name,
    CASE
        WHEN name IN ('archive_command', 'archive_library', 'primary_conninfo')
            THEN CASE WHEN setting <> '' THEN '<configured>' ELSE '<not configured>' END
        ELSE setting
    END AS setting_evidence,
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
    'max_wal_senders',
    'max_replication_slots',
    'max_slot_wal_keep_size',
    'idle_replication_slot_timeout',
    'hot_standby',
    'synchronous_commit',
    'synchronous_standby_names',
    'primary_conninfo',
    'primary_slot_name'
)
ORDER BY name;

\echo 'Sensitive command/connection strings are intentionally suppressed.'

-- 5. Archiver statistics
\echo ''
\echo '[5/11] Archiver statistics'

SELECT
    archived_count,
    failed_count,
    last_archived_wal,
    last_archived_time,
    last_failed_wal,
    last_failed_time,
    stats_reset
FROM pg_catalog.pg_stat_archiver;

\echo 'Counters are cumulative since stats_reset; interpret with baseline continuity.'
\echo 'Archive statistics do not prove remote WAL completeness or PITR.'

-- 6. Replication state
\echo ''
\echo '[6/11] Primary-side replication state'

SELECT
    pid,
    usename,
    application_name,
    CASE WHEN client_addr IS NULL THEN '<not exposed>' ELSE '<present>' END AS client_addr_evidence,
    state,
    sent_lsn,
    write_lsn,
    flush_lsn,
    replay_lsn,
    write_lag,
    flush_lag,
    replay_lag,
    sync_state,
    reply_time
FROM pg_catalog.pg_stat_replication
ORDER BY application_name, pid;

\echo 'Detailed client network addresses are intentionally suppressed; topology evidence remains sensitive.'
\echo 'Zero rows require interpretation against the expected architecture.'

-- 7. Replication slots
\echo ''
\echo '[7/11] Replication-slot evidence'

SELECT
    slot_name,
    slot_type,
    database,
    active,
    inactive_since,
    restart_lsn,
    confirmed_flush_lsn,
    wal_status,
    safe_wal_size,
    invalidation_reason,
    failover,
    synced
FROM pg_catalog.pg_replication_slots
ORDER BY slot_name;

\echo 'Inactive does not automatically mean abandoned. No slot is changed by this lab.'

-- 8. Tablespaces
\echo ''
\echo '[8/11] Tablespace inventory'

SELECT
    spcname,
    CASE
        WHEN pg_catalog.pg_tablespace_location(oid) = '' THEN '<built-in/default>'
        ELSE '<external/non-default>'
    END AS location_evidence
FROM pg_catalog.pg_tablespace
ORDER BY spcname;

\echo 'Full tablespace paths are intentionally suppressed; recovery planning must separately protect detailed storage mappings.'

-- 9. Extensions
\echo ''
\echo '[9/11] Extension inventory'

SELECT
    e.extname,
    e.extversion,
    n.nspname AS schema_name
FROM pg_catalog.pg_extension AS e
JOIN pg_catalog.pg_namespace AS n
  ON n.oid = e.extnamespace
ORDER BY e.extname;

-- 10. Statistics baselines
\echo ''
\echo '[10/11] WAL/statistics baselines'

SELECT
    wal_records,
    wal_fpi,
    wal_bytes,
    pg_catalog.pg_size_pretty(wal_bytes) AS wal_bytes_pretty,
    stats_reset AS wal_stats_reset,
    current_timestamp AS observed_at
FROM pg_catalog.pg_stat_wal;

\echo 'Do not calculate WAL-rate deltas across different stats_reset baselines.'

-- 11. Compact readiness summary
\echo ''
\echo '[11/11] Compact PostgreSQL-visible readiness summary'

WITH role_state AS (
    SELECT pg_catalog.pg_is_in_recovery() AS is_in_recovery
),
dbs AS (
    SELECT
        count(*) FILTER (WHERE datallowconn AND NOT datistemplate) AS connectable_databases
    FROM pg_catalog.pg_database
),
repl AS (
    SELECT
        count(*) AS replication_sender_count,
        count(*) FILTER (WHERE state = 'streaming') AS streaming_sender_count
    FROM pg_catalog.pg_stat_replication
),
slots AS (
    SELECT
        count(*) AS slot_count,
        count(*) FILTER (WHERE active) AS active_slot_count,
        count(*) FILTER (WHERE NOT active) AS inactive_slot_count,
        count(*) FILTER (
            WHERE wal_status IN ('unreserved', 'lost')
               OR invalidation_reason IS NOT NULL
        ) AS slot_attention_count
    FROM pg_catalog.pg_replication_slots
),
arch AS (
    SELECT
        archived_count,
        failed_count,
        last_archived_time,
        last_failed_time,
        stats_reset
    FROM pg_catalog.pg_stat_archiver
)
SELECT
    role_state.is_in_recovery,
    dbs.connectable_databases,
    repl.replication_sender_count,
    repl.streaming_sender_count,
    slots.slot_count,
    slots.active_slot_count,
    slots.inactive_slot_count,
    slots.slot_attention_count,
    arch.archived_count,
    arch.failed_count,
    arch.last_archived_time,
    arch.last_failed_time,
    arch.stats_reset AS archiver_stats_reset,
    current_timestamp AS observed_at
FROM role_state
CROSS JOIN dbs
CROSS JOIN repl
CROSS JOIN slots
CROSS JOIN arch;

\echo ''
\echo '======================================================================'
\echo 'SAFE-READ recovery-readiness evidence collection complete.'
\echo ''
\echo 'This SQL does NOT validate:'
\echo '  * existence/readability of external backup artifacts;'
\echo '  * backup manifest integrity;'
\echo '  * required WAL archive completeness;'
\echo '  * timeline-history availability;'
\echo '  * encryption/KMS access;'
\echo '  * restore/PITR execution;'
\echo '  * application acceptance;'
\echo '  * RPO/RTO achievement;'
\echo '  * DR infrastructure or failover readiness.'
\echo ''
\echo 'Missing external evidence must be recorded as UNKNOWN, not PASS.'
\echo '======================================================================'
