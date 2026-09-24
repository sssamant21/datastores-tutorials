\set ON_ERROR_STOP on

/*
 Part 6.10 — Cascading Replication and Topology
 Lab: cascade-topology-check.sql

 Classification: SAFE-READ / OBSERVATION-ONLY

 Purpose:
   Collect local PostgreSQL runtime evidence that can be correlated across
   nodes to validate a direct or cascading physical-replication topology.

 Safety:
   - no DDL
   - no DML
   - no slot creation/drop
   - no replication configuration changes
   - no replay pause/resume
   - no promotion
   - no backend termination

 Important:
   One node cannot prove an entire multi-hop topology.
   Run this lab on every relevant PostgreSQL node and correlate the output.
*/

\pset pager off
\timing off

\echo '======================================================================'
\echo '6.10 - Cascading Replication and Topology'
\echo 'SAFE-READ topology evidence'
\echo '======================================================================'

\echo ''
\echo '[1/7] Node identity and recovery role'

SELECT
    current_database() AS database_name,
    current_user AS current_user,
    inet_server_addr() AS server_addr,
    inet_server_port() AS server_port,
    pg_is_in_recovery() AS is_in_recovery,
    current_setting('cluster_name', true) AS cluster_name,
    version() AS postgres_version;

\echo ''
\echo '[2/7] Immediate upstream WAL receiver'
\echo 'INFO: A primary normally returns zero rows.'
\echo 'INFO: A standby not currently streaming can also return zero rows.'

SELECT
    pid,
    status,
    receive_start_lsn,
    written_lsn,
    flushed_lsn,
    latest_end_lsn,
    latest_end_time,
    slot_name,
    sender_host,
    sender_port,
    conninfo
FROM pg_stat_wal_receiver;

\echo ''
\echo '[3/7] Direct downstream WAL senders'
\echo 'INFO: Only directly connected downstream replicas appear here.'

SELECT
    pid,
    usename,
    application_name,
    client_addr,
    client_hostname,
    client_port,
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
\echo '[4/7] Local receive/replay position'
\echo 'INFO: Receive/replay functions are meaningful for nodes in recovery.'

SELECT
    pg_is_in_recovery() AS is_in_recovery,
    CASE
        WHEN pg_is_in_recovery() THEN pg_last_wal_receive_lsn()
    END AS last_receive_lsn,
    CASE
        WHEN pg_is_in_recovery() THEN pg_last_wal_replay_lsn()
    END AS last_replay_lsn,
    CASE
        WHEN pg_is_in_recovery() THEN pg_last_xact_replay_timestamp()
    END AS last_replay_timestamp,
    CASE
        WHEN pg_is_in_recovery()
         AND pg_last_wal_receive_lsn() IS NOT NULL
         AND pg_last_wal_replay_lsn() IS NOT NULL
        THEN pg_size_pretty(
            pg_wal_lsn_diff(
                pg_last_wal_receive_lsn(),
                pg_last_wal_replay_lsn()
            )::bigint
        )
    END AS receive_to_replay_distance;

\echo ''
\echo '[5/7] Physical replication slots on this node'
\echo 'INFO: Interpret each slot relative to this server and its direct consumers.'

SELECT
    slot_name,
    slot_type,
    active,
    active_pid,
    restart_lsn,
    wal_status,
    safe_wal_size,
    inactive_since,
    invalidation_reason
FROM pg_replication_slots
WHERE slot_type = 'physical'
ORDER BY slot_name;

\echo ''
\echo '[6/7] Local topology classification'
\echo 'INFO: Classification is local evidence only, not proof of the full topology.'

WITH node AS (
    SELECT pg_is_in_recovery() AS in_recovery
),
receiver AS (
    SELECT count(*) AS receiver_count
    FROM pg_stat_wal_receiver
),
senders AS (
    SELECT count(*) AS sender_count
    FROM pg_stat_replication
)
SELECT
    CASE
        WHEN NOT node.in_recovery
             THEN 'PRIMARY'
        WHEN node.in_recovery
             AND receiver.receiver_count > 0
             AND senders.sender_count > 0
             THEN 'CASCADING STANDBY'
        WHEN node.in_recovery
             AND receiver.receiver_count > 0
             AND senders.sender_count = 0
             THEN 'LEAF STANDBY'
        WHEN node.in_recovery
             AND receiver.receiver_count = 0
             THEN 'UNKNOWN'
        ELSE 'UNKNOWN'
    END AS local_topology_class,
    node.in_recovery,
    receiver.receiver_count,
    senders.sender_count,
    CASE
        WHEN node.in_recovery AND receiver.receiver_count = 0
            THEN 'WARNING: standby has no active WAL receiver; inspect archive/recovery/connection state'
        WHEN node.in_recovery AND receiver.receiver_count > 0
             AND senders.sender_count > 0
            THEN 'PASS: local evidence is consistent with an intermediate cascading standby'
        WHEN node.in_recovery AND receiver.receiver_count > 0
             AND senders.sender_count = 0
            THEN 'INFO: local evidence is consistent with a leaf streaming standby'
        WHEN NOT node.in_recovery
            THEN 'INFO: node is not in recovery; inspect direct downstream senders separately'
        ELSE 'UNKNOWN: insufficient local evidence'
    END AS interpretation
FROM node
CROSS JOIN receiver
CROSS JOIN senders;

\echo ''
\echo '[7/7] Replication-related configuration evidence'

SELECT
    name,
    setting,
    unit,
    source,
    pending_restart
FROM pg_settings
WHERE name IN (
    'max_wal_senders',
    'max_replication_slots',
    'hot_standby',
    'hot_standby_feedback',
    'primary_conninfo',
    'primary_slot_name',
    'recovery_target_timeline',
    'recovery_min_apply_delay',
    'synchronous_standby_names',
    'wal_level'
)
ORDER BY name;

\echo ''
\echo '======================================================================'
\echo 'Interpretation'
\echo '======================================================================'
\echo 'PASS    : local runtime evidence supports the expected relationship.'
\echo 'INFO    : healthy local role may legitimately have no upstream/downstream.'
\echo 'WARNING : expected relationship may be absent or streaming is not active.'
\echo 'UNKNOWN : local evidence is insufficient; inspect adjacent nodes.'
\echo ''
\echo 'Run this same file on each relevant node and correlate:'
\echo '  pg_stat_wal_receiver -> immediate streaming upstream'
\echo '  pg_stat_replication  -> directly connected downstream replicas'
\echo ''
\echo 'Do not infer the complete cascade from one server.'
\echo 'No replication state was modified by this lab.'
\echo '======================================================================'
