-- PostgreSQL Part 6.15
-- Production HA Readiness and Acceptance
-- Classification: SAFE-READ
--
-- PURPOSE
--   Collect PostgreSQL HA evidence without changing database or recovery state.
--
-- SAFETY
--   This file intentionally contains observational SELECT statements only.
--   It does not print primary_conninfo or pg_stat_wal_receiver.conninfo.
--
-- EXECUTION MODEL
--   Run the UNIVERSAL sections on each HA node.
--   Run PRIMARY-ORIENTED sections where the node is expected/confirmed primary.
--   Run STANDBY-ORIENTED and STANDBY-ONLY sections where the node is
--   expected/confirmed standby.
--   CONDITIONAL sections apply only when the feature is part of the design.
--
-- IMPORTANT
--   Interpret results against the documented expected architecture and
--   environment-specific RPO/RTO/capacity policies. This script deliberately
--   does not invent universal PASS/FAIL thresholds.

\echo '==================================================================='
\echo '01 — [UNIVERSAL] EXECUTION CONTEXT'
\echo '==================================================================='

SELECT
    clock_timestamp() AS observed_at,
    current_database() AS database_name,
    current_user AS executed_by,
    inet_server_addr() AS server_address,
    inet_server_port() AS server_port,
    current_setting('server_version') AS server_version,
    pg_is_in_recovery() AS in_recovery;

\echo '==================================================================='
\echo '02 — [UNIVERSAL] ROLE'
\echo 'false = primary; true = standby/recovery'
\echo '==================================================================='

SELECT
    pg_is_in_recovery() AS in_recovery,
    CASE
        WHEN pg_is_in_recovery() THEN 'STANDBY/RECOVERY'
        ELSE 'PRIMARY'
    END AS observed_role;

\echo '==================================================================='
\echo '03 — [UNIVERSAL] HA / WAL CONFIGURATION'
\echo 'No secret-bearing connection strings are selected.'
\echo '==================================================================='

SELECT
    name,
    setting,
    unit,
    source
FROM pg_settings
WHERE name IN (
    'wal_level',
    'max_wal_senders',
    'max_replication_slots',
    'wal_keep_size',
    'max_slot_wal_keep_size',
    'archive_mode',
    'full_page_writes',
    'synchronous_standby_names',
    'synchronous_commit',
    'hot_standby',
    'hot_standby_feedback',
    'max_standby_archive_delay',
    'max_standby_streaming_delay',
    'sync_replication_slots',
    'synchronized_standby_slots',
    'primary_slot_name'
)
ORDER BY name;

\echo '==================================================================='
\echo '04 — [PRIMARY-ORIENTED] DOWNSTREAM REPLICATION'
\echo 'Zero rows can be normal on a standby; interpret using the node role.'
\echo '==================================================================='

SELECT
    application_name,
    client_addr,
    state,
    sent_lsn,
    write_lsn,
    flush_lsn,
    replay_lsn,
    sync_state,
    reply_time
FROM pg_stat_replication
ORDER BY application_name, client_addr;

\echo '==================================================================='
\echo '05 — [STANDBY-ORIENTED] WAL RECEIVER'
\echo 'Credential-bearing conninfo is intentionally excluded.'
\echo '==================================================================='

SELECT
    status,
    receive_start_lsn,
    written_lsn,
    flushed_lsn,
    last_msg_send_time,
    last_msg_receipt_time,
    latest_end_lsn,
    latest_end_time,
    slot_name,
    sender_host,
    sender_port
FROM pg_stat_wal_receiver;

\echo '==================================================================='
\echo '06 — [STANDBY-ORIENTED] RECEIVE / REPLAY'
\echo 'On a primary these recovery-information values may be NULL.'
\echo '==================================================================='

SELECT
    pg_last_wal_receive_lsn() AS receive_lsn,
    pg_last_wal_replay_lsn() AS replay_lsn,
    pg_last_xact_replay_timestamp() AS last_replay_timestamp;

\echo '==================================================================='
\echo '07 — [STANDBY-ONLY] WAL REPLAY PAUSE STATE'
\echo 'Run the following SELECT only after Section 02 confirms in_recovery=true.'
\echo 'Expected normal state: not paused'
\echo '==================================================================='

-- STANDBY-ONLY:
-- SELECT pg_get_wal_replay_pause_state() AS replay_pause_state;

\echo '==================================================================='
\echo '08 — [UNIVERSAL] REPLICATION SLOTS'
\echo 'Interpret inactive slots and safe_wal_size contextually.'
\echo '==================================================================='

SELECT
    slot_name,
    slot_type,
    database,
    active,
    active_pid,
    restart_lsn,
    confirmed_flush_lsn,
    wal_status,
    safe_wal_size,
    inactive_since,
    invalidation_reason,
    failover,
    synced
FROM pg_replication_slots
ORDER BY slot_name;

\echo '==================================================================='
\echo '09 — [CONDITIONAL] LOGICAL / FAILOVER SLOT EVIDENCE'
\echo 'Use when logical replication/failover slots are part of the design.'
\echo '==================================================================='

SELECT
    slot_name,
    database,
    active,
    confirmed_flush_lsn,
    wal_status,
    safe_wal_size,
    invalidation_reason,
    failover,
    synced
FROM pg_replication_slots
WHERE slot_type = 'logical'
ORDER BY slot_name;

\echo '==================================================================='
\echo '10 — [STANDBY-ORIENTED] RECOVERY CONFLICT COUNTERS'
\echo 'Counters are accumulated evidence, not instantaneous failure state.'
\echo '==================================================================='

SELECT
    datname,
    confl_tablespace,
    confl_lock,
    confl_snapshot,
    confl_bufferpin,
    confl_deadlock,
    confl_active_logicalslot
FROM pg_stat_database_conflicts
ORDER BY datname;

\echo '==================================================================='
\echo '11 — [STANDBY-ORIENTED] CONFLICT POLICY SETTINGS'
\echo '==================================================================='

SELECT
    name,
    setting,
    unit,
    source
FROM pg_settings
WHERE name IN (
    'hot_standby',
    'hot_standby_feedback',
    'max_standby_archive_delay',
    'max_standby_streaming_delay'
)
ORDER BY name;

\echo '==================================================================='
\echo '12 — [UNIVERSAL] ARCHIVE STATISTICS'
\echo 'Interpret counters together with timestamps and current progression.'
\echo '==================================================================='

SELECT
    archived_count,
    last_archived_wal,
    last_archived_time,
    failed_count,
    last_failed_wal,
    last_failed_time,
    stats_reset
FROM pg_stat_archiver;

\echo '==================================================================='
\echo '13 — [UNIVERSAL] CONNECTION CAPACITY'
\echo 'No universal utilization threshold is assumed.'
\echo '==================================================================='

SELECT
    state,
    count(*) AS connections
FROM pg_stat_activity
GROUP BY state
ORDER BY state NULLS LAST;

SELECT
    name,
    setting,
    unit,
    source
FROM pg_settings
WHERE name IN (
    'max_connections',
    'superuser_reserved_connections'
)
ORDER BY name;

\echo '==================================================================='
\echo '14 — [UNIVERSAL] WAL SENDER / SLOT CAPACITY'
\echo 'Compare configured capacity with intended topology and tooling.'
\echo '==================================================================='

SELECT
    name,
    setting,
    unit,
    source
FROM pg_settings
WHERE name IN (
    'max_wal_senders',
    'max_replication_slots'
)
ORDER BY name;

SELECT
    count(*) AS configured_replication_slots,
    count(*) FILTER (WHERE active) AS active_replication_slots,
    count(*) FILTER (WHERE slot_type = 'physical') AS physical_slots,
    count(*) FILTER (WHERE slot_type = 'logical') AS logical_slots,
    count(*) FILTER (WHERE invalidation_reason IS NOT NULL) AS invalidated_slots
FROM pg_replication_slots;

\echo '==================================================================='
\echo '15 — [UNIVERSAL] EVIDENCE SUMMARY'
\echo 'This is factual evidence, not an automatic production PASS/FAIL.'
\echo '==================================================================='

SELECT
    clock_timestamp() AS observed_at,
    inet_server_addr() AS server_address,
    inet_server_port() AS server_port,
    CASE
        WHEN pg_is_in_recovery() THEN 'STANDBY/RECOVERY'
        ELSE 'PRIMARY'
    END AS observed_role,
    current_setting('server_version') AS server_version,
    (SELECT count(*) FROM pg_stat_replication) AS downstream_replication_rows,
    (SELECT count(*) FROM pg_stat_wal_receiver) AS wal_receiver_rows,
    (SELECT count(*) FROM pg_replication_slots) AS replication_slots,
    (SELECT count(*) FROM pg_replication_slots
       WHERE invalidation_reason IS NOT NULL) AS invalidated_slots;

\echo '==================================================================='
\echo 'SAFE-READ COLLECTION COMPLETE'
\echo 'Correlate this output with platform storage, monitoring, backup,'
\echo '6.12 switchover, 6.13 failover/fencing, and 6.14 rejoin evidence.'
\echo '==================================================================='
