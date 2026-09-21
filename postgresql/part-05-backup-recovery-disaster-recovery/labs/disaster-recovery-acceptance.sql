/*
===============================================================================
Part 5.15 — Integrated Project: Design, Validate, and Rehearse a Recovery Strategy
Canonical Acceptance Artifact

[TUTORIAL-ACCEPTANCE — SAFE-READ]
[SENSITIVE OPERATIONAL EVIDENCE]
Target: PostgreSQL 18

Purpose:
  Collect PostgreSQL-visible evidence for the integrated Part 5 recovery
  assessment. External backup, restore, DR, application, RPO/RTO, IAM/KMS,
  capacity, and rehearsal evidence must be evaluated separately.

NO state-changing recovery action is performed by this artifact.
SAFE-READ does not mean PUBLIC-SAFE.
===============================================================================
*/

\set ON_ERROR_STOP on

\echo '======================================================================'
\echo 'Part 5.15 — Integrated Disaster-Recovery Acceptance Evidence'
\echo '[TUTORIAL-ACCEPTANCE — SAFE-READ]'
\echo '[SENSITIVE OPERATIONAL EVIDENCE]'
\echo '======================================================================'

-- 1. Identity and observation baseline
\echo ''
\echo '[1/12] Identity and observation baseline'
SELECT
    current_database() AS connected_database,
    current_user AS current_user_name,
    current_setting('server_version') AS server_version,
    current_setting('server_version_num') AS server_version_num,
    pg_postmaster_start_time() AS postmaster_start_time,
    current_timestamp AS observed_at;

-- 2. Recovery role/state
\echo ''
\echo '[2/12] Recovery role/state'
SELECT
    pg_catalog.pg_is_in_recovery() AS is_in_recovery,
    CASE WHEN pg_catalog.pg_is_in_recovery()
         THEN pg_catalog.pg_last_wal_receive_lsn() END AS last_wal_receive_lsn,
    CASE WHEN pg_catalog.pg_is_in_recovery()
         THEN pg_catalog.pg_last_wal_replay_lsn() END AS last_wal_replay_lsn,
    CASE WHEN pg_catalog.pg_is_in_recovery()
         THEN pg_catalog.pg_last_xact_replay_timestamp() END AS last_replayed_xact_timestamp,
    current_timestamp AS observed_at;

\echo 'Received WAL is not necessarily replayed WAL.'
\echo 'Last replayed transaction timestamp is not a universal real-time lag metric.'

-- 3. Database inventory
\echo ''
\echo '[3/12] Database inventory'
SELECT
    datname,
    datallowconn,
    datistemplate,
    pg_catalog.pg_size_pretty(pg_catalog.pg_database_size(datname)) AS database_size
FROM pg_catalog.pg_database
ORDER BY datname;

\echo 'Read-only size collection can still have operational cost on large systems.'

-- 4. Recovery-relevant configuration
\echo ''
\echo '[4/12] Recovery-relevant configuration'
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

\echo 'Sensitive command/connection values are intentionally suppressed.'
\echo 'Configuration evidence does not prove recoverability.'

-- 5. Archiver evidence
\echo ''
\echo '[5/12] Archiver statistics'
SELECT
    archived_count,
    failed_count,
    last_archived_wal,
    last_archived_time,
    last_failed_wal,
    last_failed_time,
    stats_reset
FROM pg_catalog.pg_stat_archiver;

\echo 'Counters are cumulative relative to stats_reset.'
\echo 'Archiver activity does not prove remote WAL completeness or PITR.'

-- 6. WAL statistics
\echo ''
\echo '[6/12] WAL statistics baseline'
SELECT
    wal_records,
    wal_fpi,
    wal_bytes,
    pg_catalog.pg_size_pretty(wal_bytes) AS wal_bytes_pretty,
    stats_reset,
    current_timestamp AS observed_at
FROM pg_catalog.pg_stat_wal;

\echo 'WAL-rate comparisons require a compatible stats_reset baseline.'

-- 7. Replication evidence
\echo ''
\echo '[7/12] Primary-side replication evidence'
SELECT
    application_name,
    CASE WHEN client_addr IS NULL THEN '<not exposed>' ELSE '<present>' END
        AS client_addr_evidence,
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
ORDER BY application_name;

\echo 'Zero rows must be interpreted against the expected architecture.'
\echo 'Lag fields are runtime evidence, not direct business RPO measurements.'

-- 8. WAL receiver evidence
\echo ''
\echo '[8/12] Standby WAL receiver evidence'
SELECT
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
    CASE WHEN sender_host IS NULL THEN '<not exposed>' ELSE '<present>' END
        AS sender_host_evidence,
    sender_port
FROM pg_catalog.pg_stat_wal_receiver;

\echo 'Zero rows require interpretation with pg_is_in_recovery() and expected topology.'

-- 9. Replication slots
\echo ''
\echo '[9/12] Replication-slot evidence'
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

\echo 'Inactive does not mean abandoned.'
\echo 'No slot is created, advanced, or dropped by this artifact.'

-- 10. Tablespaces and extensions
\echo ''
\echo '[10/12] Recovery dependency inventory'

SELECT
    'tablespace' AS dependency_type,
    spcname AS dependency_name,
    CASE
        WHEN pg_catalog.pg_tablespace_location(oid) = '' THEN '<built-in/default>'
        ELSE '<external/non-default>'
    END AS detail
FROM pg_catalog.pg_tablespace

UNION ALL

SELECT
    'extension',
    e.extname,
    e.extversion
FROM pg_catalog.pg_extension AS e
ORDER BY dependency_type, dependency_name;

\echo 'Full tablespace paths are intentionally suppressed.'
\echo 'Extension catalog entries do not prove required binaries/packages exist on a recovery host.'

-- 11. Compact PostgreSQL-visible summary
\echo ''
\echo '[11/12] Compact PostgreSQL-visible summary'
WITH role_state AS (
    SELECT pg_catalog.pg_is_in_recovery() AS is_in_recovery
),
dbs AS (
    SELECT count(*) FILTER (WHERE datallowconn AND NOT datistemplate)
        AS connectable_database_count
    FROM pg_catalog.pg_database
),
repl AS (
    SELECT
        count(*) AS sender_count,
        count(*) FILTER (WHERE state = 'streaming') AS streaming_sender_count,
        count(*) FILTER (WHERE sync_state IN ('sync', 'quorum'))
            AS synchronous_sender_count
    FROM pg_catalog.pg_stat_replication
),
recv AS (
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
    dbs.connectable_database_count,
    repl.sender_count,
    repl.streaming_sender_count,
    repl.synchronous_sender_count,
    recv.receiver_count,
    recv.streaming_receiver_count,
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
CROSS JOIN recv
CROSS JOIN slots
CROSS JOIN arch;

-- 12. Acceptance boundary
\echo ''
\echo '[12/12] Acceptance boundary'
\echo ''
\echo 'PostgreSQL-visible evidence collection is complete.'
\echo ''
\echo 'This artifact DOES NOT prove:'
\echo '  * external backup artifacts exist or are readable;'
\echo '  * backup manifests are valid;'
\echo '  * required WAL/timeline history is complete;'
\echo '  * PITR has succeeded;'
\echo '  * an isolated restore has succeeded;'
\echo '  * application recovery has succeeded;'
\echo '  * RPO or RTO has been achieved;'
\echo '  * alternate DR infrastructure is usable;'
\echo '  * IAM/KMS/secrets are available during disaster;'
\echo '  * failover or failback has been rehearsed.'
\echo ''
\echo 'Missing, stale, or inaccessible required evidence = UNKNOWN.'
\echo 'SAFE-READ SQL PASS != RECOVERY READY.'
\echo '======================================================================'
