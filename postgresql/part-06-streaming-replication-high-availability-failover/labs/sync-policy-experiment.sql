\set ON_ERROR_STOP on

/*
  PostgreSQL Part 6.7
  Asynchronous and Synchronous Replication Policy
  Locked lab: sync-policy-experiment.sql

  SAFETY:
  - Read-only evidence collection.
  - Does not ALTER SYSTEM.
  - Does not change synchronous_standby_names.
  - Does not stop/restart PostgreSQL.
  - Does not terminate replication sessions.
  - Does not intentionally create blocking synchronous commits.

  Recommended:
      psql -X -f labs/sync-policy-experiment.sql
*/

\echo '======================================================================'
\echo '6.7 - Asynchronous and Synchronous Replication Policy'
\echo 'SAFE-READ evidence collection'
\echo '======================================================================'

\echo ''
\echo '[1/8] Server identity and execution context'

SELECT
    current_database() AS database_name,
    current_user AS current_user,
    inet_server_addr() AS server_address,
    inet_server_port() AS server_port,
    version() AS postgres_version;

\echo ''
\echo '[2/8] Primary/standby role'

SELECT
    pg_is_in_recovery() AS is_in_recovery,
    CASE
        WHEN pg_is_in_recovery()
            THEN 'STANDBY: primary-side pg_stat_replication evidence is not expected here'
        ELSE 'PRIMARY: inspect connected WAL sender sessions below'
    END AS interpretation;

\echo ''
\echo '[3/8] Active replication policy settings'

SELECT
    name,
    setting,
    source,
    pending_restart
FROM pg_settings
WHERE name IN (
    'synchronous_commit',
    'synchronous_standby_names'
)
ORDER BY name;

\echo ''
\echo '[4/8] Connected replication sessions'

SELECT
    pid,
    application_name,
    client_addr,
    state,
    sent_lsn,
    write_lsn,
    flush_lsn,
    replay_lsn,
    sync_priority,
    sync_state,
    write_lag,
    flush_lag,
    replay_lag
FROM pg_stat_replication
ORDER BY application_name, pid;

\echo ''
\echo '[5/8] Synchronous-state summary'

SELECT
    sync_state,
    count(*) AS standby_count
FROM pg_stat_replication
GROUP BY sync_state
ORDER BY sync_state;

\echo ''
\echo '[6/8] Policy evidence classification'

WITH server_role AS (
    SELECT pg_is_in_recovery() AS in_recovery
),
replication AS (
    SELECT
        count(*) AS total,
        count(*) FILTER (WHERE state = 'streaming') AS streaming,
        count(*) FILTER (WHERE sync_state = 'async') AS async_count,
        count(*) FILTER (WHERE sync_state = 'potential') AS potential_count,
        count(*) FILTER (WHERE sync_state = 'sync') AS sync_count,
        count(*) FILTER (WHERE sync_state = 'quorum') AS quorum_count
    FROM pg_stat_replication
)
SELECT
    CASE
        WHEN s.in_recovery THEN
            'INFO'
        WHEN r.total = 0 THEN
            'WARNING'
        WHEN r.sync_count > 0 THEN
            'SYNC'
        WHEN r.quorum_count > 0 THEN
            'QUORUM'
        WHEN r.potential_count > 0 THEN
            'POTENTIAL'
        WHEN r.async_count > 0 THEN
            'ASYNC'
        ELSE
            'UNKNOWN'
    END AS observed_class,
    CASE
        WHEN s.in_recovery THEN
            'Connected server is a standby; evaluate upstream policy from the primary.'
        WHEN r.total = 0 THEN
            'No connected pg_stat_replication sessions were observed on this primary.'
        WHEN r.sync_count > 0 THEN
            'At least one priority synchronous standby is currently observed.'
        WHEN r.quorum_count > 0 THEN
            'At least one quorum synchronous standby candidate is currently observed.'
        WHEN r.potential_count > 0 THEN
            'Potential synchronous candidate(s) observed; inspect full policy and current sync standby.'
        WHEN r.async_count > 0 THEN
            'Connected replication is observed, but the reported standby state is asynchronous.'
        ELSE
            'Replication sessions exist but do not match expected synchronous-state classifications.'
    END AS interpretation,
    r.total AS replication_sessions,
    r.streaming AS streaming_sessions,
    r.async_count,
    r.potential_count,
    r.sync_count,
    r.quorum_count
FROM server_role s
CROSS JOIN replication r;

\echo ''
\echo '[7/8] WAL position evidence'

SELECT
    application_name,
    state,
    sync_state,
    sent_lsn,
    write_lsn,
    flush_lsn,
    replay_lsn,
    CASE
        WHEN sent_lsn IS NOT NULL AND write_lsn IS NOT NULL
            THEN pg_wal_lsn_diff(sent_lsn, write_lsn)
        ELSE NULL
    END AS sent_minus_write_bytes,
    CASE
        WHEN sent_lsn IS NOT NULL AND flush_lsn IS NOT NULL
            THEN pg_wal_lsn_diff(sent_lsn, flush_lsn)
        ELSE NULL
    END AS sent_minus_flush_bytes,
    CASE
        WHEN sent_lsn IS NOT NULL AND replay_lsn IS NOT NULL
            THEN pg_wal_lsn_diff(sent_lsn, replay_lsn)
        ELSE NULL
    END AS sent_minus_replay_bytes
FROM pg_stat_replication
ORDER BY application_name, pid;

\echo ''
\echo '[8/8] Operator reminders'

SELECT
    'Streaming does not imply synchronous commit protection.' AS reminder
UNION ALL
SELECT
    'synchronous_standby_names selects synchronous standby policy; synchronous_commit controls transaction acknowledgement behavior.'
UNION ALL
SELECT
    'NULL write_lag/flush_lag/replay_lag is not automatically a failure; interpret lag with workload activity and WAL positions.'
UNION ALL
SELECT
    'Do not test standby-loss behavior in production without an approved change plan, bounded timeout strategy, monitoring, and rollback.'
UNION ALL
SELECT
    'Compare observed evidence with the documented RPO/RTO and replication policy before declaring PASS.';

\echo ''
\echo '======================================================================'
\echo '6.7 SAFE-READ lab complete'
\echo 'No replication configuration was changed.'
\echo '======================================================================'
