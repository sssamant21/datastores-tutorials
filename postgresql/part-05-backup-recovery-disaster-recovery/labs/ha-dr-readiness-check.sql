/*
===============================================================================
Part 5.13 — High Availability vs Backup vs Disaster Recovery
Canonical Acceptance Artifact

[TUTORIAL-ACCEPTANCE — SAFE-READ]
Target: PostgreSQL 18

Purpose:
  Collect PostgreSQL-visible evidence relevant to HA, backup, and DR readiness.

This artifact DOES NOT:
  - promote a standby;
  - pause/resume WAL replay;
  - create/drop/advance replication slots;
  - change synchronous replication;
  - force CHECKPOINT or WAL switch;
  - create restore points;
  - change archive/backup configuration;
  - run backup/restore;
  - modify application data;
  - alter external HA/failover tooling.

Successful execution is evidence collection only. It does not prove failover,
backup recovery, DR, RPO, RTO, or failback readiness.
===============================================================================
*/

\set ON_ERROR_STOP on

\echo '======================================================================'
\echo 'Part 5.13 — HA / Backup / DR Readiness Evidence — SAFE-READ'
\echo '======================================================================'

-- 1. Server identity
\echo ''
\echo '[1/10] Server identity'

SELECT
    current_database() AS connected_database,
    current_user AS current_user_name,
    version() AS server_version,
    current_setting('server_version_num') AS server_version_num,
    pg_postmaster_start_time() AS postmaster_start_time,
    current_timestamp AS observed_at;

-- 2. Recovery role/state
\echo ''
\echo '[2/10] Primary / standby recovery state'

SELECT
    pg_catalog.pg_is_in_recovery() AS is_in_recovery,
    CASE
        WHEN pg_catalog.pg_is_in_recovery()
            THEN pg_catalog.pg_last_wal_receive_lsn()
        ELSE NULL
    END AS last_wal_receive_lsn,
    CASE
        WHEN pg_catalog.pg_is_in_recovery()
            THEN pg_catalog.pg_last_wal_replay_lsn()
        ELSE NULL
    END AS last_wal_replay_lsn,
    CASE
        WHEN pg_catalog.pg_is_in_recovery()
            THEN pg_catalog.pg_last_xact_replay_timestamp()
        ELSE NULL
    END AS last_replayed_transaction_timestamp,
    current_timestamp AS observed_at;

-- 3. HA/replication configuration
\echo ''
\echo '[3/10] HA / replication configuration'

SELECT
    name,
    CASE
        WHEN name = 'primary_conninfo'
            THEN CASE WHEN setting <> '' THEN '<configured>' ELSE '<not configured>' END
        ELSE setting
    END AS setting_evidence,
    unit,
    source,
    pending_restart
FROM pg_catalog.pg_settings
WHERE name IN (
    'wal_level',
    'max_wal_senders',
    'max_replication_slots',
    'synchronous_standby_names',
    'synchronous_commit',
    'wal_keep_size',
    'max_slot_wal_keep_size',
    'idle_replication_slot_timeout',
    'hot_standby',
    'primary_conninfo',
    'primary_slot_name'
)
ORDER BY name;

\echo ''
\echo 'SECURITY: full primary_conninfo is intentionally suppressed.'

-- 4. Primary-side replication sessions
\echo ''
\echo '[4/10] Primary-side replication sessions'

SELECT
    pid,
    usename,
    application_name,
    client_addr,
    state,
    sent_lsn,
    write_lsn,
    flush_lsn,
    replay_lsn,
    write_lag,
    flush_lag,
    replay_lag,
    sync_priority,
    sync_state,
    reply_time
FROM pg_catalog.pg_stat_replication
ORDER BY application_name, pid;

\echo ''
\echo 'Zero rows require interpretation against the expected architecture; this lab does not declare topology failure.'

-- 5. Standby WAL receiver evidence
\echo ''
\echo '[5/10] Standby WAL receiver evidence'

SELECT
    pid,
    status,
    receive_start_lsn,
    written_lsn,
    flushed_lsn,
    received_tli,
    last_msg_send_time,
    last_msg_receipt_time,
    latest_end_lsn,
    latest_end_time,
    slot_name,
    sender_host,
    sender_port
FROM pg_catalog.pg_stat_wal_receiver;

\echo ''
\echo 'Interpret zero rows with pg_is_in_recovery() and the expected architecture.'

-- 6. Replication slots
\echo ''
\echo '[6/10] Replication-slot evidence'

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

-- 7. WAL/archive configuration
\echo ''
\echo '[7/10] WAL / archive configuration'

SELECT
    name,
    CASE
        WHEN name IN ('archive_command', 'archive_library')
            THEN CASE WHEN setting <> '' THEN '<configured>' ELSE '<not configured>' END
        ELSE setting
    END AS setting_evidence,
    unit,
    source,
    pending_restart
FROM pg_catalog.pg_settings
WHERE name IN (
    'archive_mode',
    'archive_command',
    'archive_library',
    'wal_level',
    'wal_keep_size',
    'max_slot_wal_keep_size'
)
ORDER BY name;

\echo ''
\echo 'SECURITY: full archive_command/archive_library values are intentionally suppressed.'

-- 8. Archiver statistics
\echo ''
\echo '[8/10] Archiver statistics'

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
\echo 'Archiver statistics do not prove remote archive completeness or PITR.'

-- 9. WAL-generation statistics
\echo ''
\echo '[9/10] WAL-generation statistics'

SELECT
    wal_records,
    wal_fpi,
    wal_bytes,
    pg_catalog.pg_size_pretty(wal_bytes) AS wal_bytes_pretty,
    stats_reset,
    current_timestamp AS observed_at
FROM pg_catalog.pg_stat_wal;

\echo ''
\echo 'wal_bytes is cumulative since stats_reset; it is not a direct WAL rate.'

-- 10. Compact evidence summary
\echo ''
\echo '[10/10] Compact HA / backup / DR evidence summary'

WITH role_state AS (
    SELECT pg_catalog.pg_is_in_recovery() AS is_in_recovery
),
senders AS (
    SELECT
        count(*) AS sender_count,
        count(*) FILTER (WHERE state = 'streaming') AS streaming_sender_count,
        count(*) FILTER (WHERE sync_state IN ('sync', 'quorum')) AS synchronous_sender_count
    FROM pg_catalog.pg_stat_replication
),
receiver AS (
    SELECT
        count(*) AS receiver_count,
        count(*) FILTER (WHERE status = 'streaming') AS streaming_receiver_count
    FROM pg_catalog.pg_stat_wal_receiver
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
archiver AS (
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
    senders.sender_count,
    senders.streaming_sender_count,
    senders.synchronous_sender_count,
    receiver.receiver_count,
    receiver.streaming_receiver_count,
    slots.slot_count,
    slots.active_slot_count,
    slots.inactive_slot_count,
    slots.slot_attention_count,
    archiver.archived_count,
    archiver.failed_count,
    archiver.last_archived_time,
    archiver.last_failed_time,
    archiver.stats_reset AS archiver_stats_reset,
    current_timestamp AS observed_at
FROM role_state
CROSS JOIN senders
CROSS JOIN receiver
CROSS JOIN slots
CROSS JOIN archiver;

\echo ''
\echo '======================================================================'
\echo 'SAFE-READ HA / backup / DR evidence collection complete.'
\echo 'SAFE-READ does not mean PUBLIC-SAFE; protect captured topology evidence.'
\echo ''
\echo 'This artifact does NOT prove:'
\echo '  * HA failover readiness;'
\echo '  * backup integrity or recoverability;'
\echo '  * DR readiness;'
\echo '  * achieved RPO/RTO;'
\echo '  * PITR success;'
\echo '  * application recovery;'
\echo '  * failback readiness.'
\echo ''
\echo 'Use controlled failover, restore, and DR rehearsals plus external'
\echo 'infrastructure/application evidence for those acceptance decisions.'
\echo '======================================================================'
