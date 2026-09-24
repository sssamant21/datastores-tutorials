\set ON_ERROR_STOP on

/*
 Part 6.11 — Monitoring, Alerting, and Capacity Signals
 Lab: ha-observability-check.sql
 Classification: SAFE-READ

 Purpose:
   Collect PostgreSQL-side HA observability evidence without changing state.

 This lab DOES NOT:
   - create/drop replication slots
   - modify PostgreSQL settings
   - expose primary_conninfo
   - pause/resume replay
   - promote a standby
   - terminate sessions
   - modify application data

 External telemetry is still required for filesystem capacity, storage latency,
 CPU/memory pressure, network health, cloud-volume limits, load balancers,
 and application reconnect readiness.
*/

\pset pager off
\timing off

\echo '======================================================================'
\echo '6.11 - Monitoring, Alerting, and Capacity Signals'
\echo 'Classification: SAFE-READ'
\echo '======================================================================'

\echo ''
\echo '[1/9] Node identity and recovery role'

SELECT
    current_database() AS database_name,
    current_user AS current_user,
    inet_server_addr() AS server_addr,
    inet_server_port() AS server_port,
    current_setting('server_version') AS server_version,
    current_setting('cluster_name', true) AS cluster_name,
    pg_is_in_recovery() AS is_in_recovery;

\echo ''
\echo '[2/9] Direct WAL sender state'
\echo 'INFO: pg_stat_replication shows directly connected replication clients.'

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
FROM pg_stat_replication
ORDER BY application_name, client_addr, pid;

\echo ''
\echo '[3/9] WAL receiver state'
\echo 'INFO: A primary normally has no WAL receiver.'
\echo 'INFO: A standby can temporarily have no receiver during non-streaming recovery.'

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
FROM pg_stat_wal_receiver;

\echo ''
\echo '[4/9] Standby receive/replay progress'

SELECT
    pg_is_in_recovery() AS is_in_recovery,
    CASE WHEN pg_is_in_recovery()
         THEN pg_last_wal_receive_lsn() END AS last_receive_lsn,
    CASE WHEN pg_is_in_recovery()
         THEN pg_last_wal_replay_lsn() END AS last_replay_lsn,
    CASE WHEN pg_is_in_recovery()
         THEN pg_last_xact_replay_timestamp() END AS last_replay_timestamp,
    CASE
        WHEN pg_is_in_recovery()
         AND pg_last_wal_receive_lsn() IS NOT NULL
         AND pg_last_wal_replay_lsn() IS NOT NULL
        THEN pg_wal_lsn_diff(
            pg_last_wal_receive_lsn(),
            pg_last_wal_replay_lsn()
        )
    END AS receive_to_replay_bytes;

\echo ''
\echo '[5/9] Replication slots and WAL-retention evidence'

SELECT
    slot_name,
    slot_type,
    active,
    active_pid,
    restart_lsn,
    wal_status,
    safe_wal_size,
    inactive_since,
    invalidation_reason,
    CASE
        WHEN restart_lsn IS NOT NULL
        THEN pg_wal_lsn_diff(pg_current_wal_lsn(), restart_lsn)
    END AS current_to_restart_bytes,
    CASE
        WHEN wal_status = 'lost' THEN 'CRITICAL'
        WHEN wal_status = 'unreserved' THEN 'WARNING'
        WHEN wal_status = 'extended' THEN 'INFO'
        WHEN wal_status = 'reserved' THEN 'PASS'
        ELSE 'UNKNOWN'
    END AS local_status
FROM pg_replication_slots
ORDER BY slot_name;

\echo ''
\echo '[6/9] Standby recovery conflict counters'
\echo 'INFO: These are cumulative counters. Monitor deltas/rates externally.'

SELECT
    datid,
    datname,
    confl_tablespace,
    confl_lock,
    confl_snapshot,
    confl_bufferpin,
    confl_deadlock,
    confl_active_logicalslot
FROM pg_stat_database_conflicts
ORDER BY datname;

\echo ''
\echo '[7/9] HA configuration and capacity context'
\echo 'INFO: Values are evidence, not universal PASS/FAIL thresholds.'

SELECT
    name,
    setting,
    unit,
    source,
    pending_restart
FROM pg_settings
WHERE name IN (
    'wal_level',
    'max_wal_senders',
    'max_replication_slots',
    'wal_keep_size',
    'max_slot_wal_keep_size',
    'wal_receiver_timeout',
    'wal_receiver_status_interval',
    'hot_standby',
    'hot_standby_feedback',
    'synchronous_standby_names',
    'max_connections'
)
ORDER BY name;

\echo ''
\echo '[8/9] Database-visible headroom indicators'

WITH settings AS (
    SELECT
        current_setting('max_wal_senders')::integer AS max_wal_senders,
        current_setting('max_replication_slots')::integer AS max_replication_slots
),
usage AS (
    SELECT
        (SELECT count(*) FROM pg_stat_replication) AS active_wal_senders,
        (SELECT count(*) FROM pg_replication_slots) AS existing_slots
)
SELECT
    settings.max_wal_senders,
    usage.active_wal_senders,
    settings.max_wal_senders - usage.active_wal_senders AS observed_sender_headroom,
    settings.max_replication_slots,
    usage.existing_slots,
    settings.max_replication_slots - usage.existing_slots AS slot_headroom
FROM settings
CROSS JOIN usage;

\echo ''
\echo '[9/9] Local evidence summary'

WITH role_state AS (
    SELECT pg_is_in_recovery() AS in_recovery
),
receiver_state AS (
    SELECT count(*) AS receivers
    FROM pg_stat_wal_receiver
),
sender_state AS (
    SELECT count(*) AS senders
    FROM pg_stat_replication
),
slot_state AS (
    SELECT
        count(*) FILTER (WHERE wal_status = 'lost') AS lost_slots,
        count(*) FILTER (WHERE wal_status = 'unreserved') AS unreserved_slots
    FROM pg_replication_slots
)
SELECT
    CASE
        WHEN slot_state.lost_slots > 0 THEN 'CRITICAL'
        WHEN slot_state.unreserved_slots > 0 THEN 'WARNING'
        WHEN role_state.in_recovery AND receiver_state.receivers = 0 THEN 'UNKNOWN'
        ELSE 'INFO'
    END AS local_classification,
    role_state.in_recovery,
    receiver_state.receivers AS wal_receivers,
    sender_state.senders AS direct_wal_senders,
    slot_state.lost_slots,
    slot_state.unreserved_slots,
    CASE
        WHEN slot_state.lost_slots > 0
            THEN 'One or more replication slots have wal_status=lost.'
        WHEN slot_state.unreserved_slots > 0
            THEN 'One or more slots have wal_status=unreserved; investigate WAL retention.'
        WHEN role_state.in_recovery AND receiver_state.receivers = 0
            THEN 'Standby has no active WAL receiver. Validate expected recovery/streaming design.'
        ELSE
            'No critical conclusion from this one-time SQL sample; correlate trends and external telemetry.'
    END AS interpretation
FROM role_state
CROSS JOIN receiver_state
CROSS JOIN sender_state
CROSS JOIN slot_state;

\echo ''
\echo '======================================================================'
\echo 'External monitoring still required'
\echo '======================================================================'
\echo '- pg_wal/filesystem utilization and free capacity'
\echo '- storage latency, throughput, queueing, and errors'
\echo '- host CPU saturation and memory pressure'
\echo '- network latency, packet loss, resets, routing, DNS'
\echo '- cloud volume/service limits'
\echo '- load-balancer readiness'
\echo '- application reconnect/failover readiness'
\echo ''
\echo 'Classification model: PASS / INFO / WARNING / CRITICAL / UNKNOWN'
\echo 'Prefer UNKNOWN over unsupported health conclusions.'
\echo 'No PostgreSQL state was modified by this lab.'
\echo '======================================================================'
