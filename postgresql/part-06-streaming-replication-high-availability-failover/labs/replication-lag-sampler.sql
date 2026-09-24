-- Part 6.6 — Measure Replication Lag Correctly
-- Target: PostgreSQL 18
-- Classification: [SAFE-READ]
-- MUTATIONS: NONE
-- CLEANUP: NONE
-- One invocation = one timestamped observation.
-- NULL is not zero. Negative distances are not hidden with ABS().
-- Lag fields are acknowledgment-delay evidence, not catch-up timers.
\set ON_ERROR_STOP on

\if :{?sample_id}
\else
  \set sample_id 'unspecified'
\endif

\echo '=== Part 6.6 — Replication Lag Sample / SAFE-READ ==='

\echo '[1] Sample identity and observed role'
SELECT
    :'sample_id' AS sample_id,
    clock_timestamp() AS observed_at,
    current_database() AS database_name,
    inet_server_addr() AS server_address,
    inet_server_port() AS server_port,
    current_setting('server_version') AS server_version,
    pg_is_in_recovery() AS in_recovery,
    CASE WHEN pg_is_in_recovery() THEN 'STANDBY' ELSE 'PRIMARY' END AS observed_role;

\echo '[2] Primary-side sender-stage distances'
SELECT
    :'sample_id' AS sample_id,
    clock_timestamp() AS observed_at,
    r.application_name,
    r.state,
    CASE WHEN pg_is_in_recovery() THEN NULL::pg_lsn ELSE pg_current_wal_lsn() END AS current_wal_lsn,
    r.sent_lsn, r.write_lsn, r.flush_lsn, r.replay_lsn,
    CASE WHEN pg_is_in_recovery() OR r.sent_lsn IS NULL THEN NULL
         ELSE pg_wal_lsn_diff(pg_current_wal_lsn(), r.sent_lsn) END AS current_to_sent_bytes,
    CASE WHEN r.sent_lsn IS NULL OR r.write_lsn IS NULL THEN NULL
         ELSE pg_wal_lsn_diff(r.sent_lsn, r.write_lsn) END AS sent_to_write_bytes,
    CASE WHEN r.sent_lsn IS NULL OR r.flush_lsn IS NULL THEN NULL
         ELSE pg_wal_lsn_diff(r.sent_lsn, r.flush_lsn) END AS sent_to_flush_bytes,
    CASE WHEN r.sent_lsn IS NULL OR r.replay_lsn IS NULL THEN NULL
         ELSE pg_wal_lsn_diff(r.sent_lsn, r.replay_lsn) END AS sent_to_replay_bytes,
    CASE WHEN pg_is_in_recovery() OR r.replay_lsn IS NULL THEN NULL
         ELSE pg_wal_lsn_diff(pg_current_wal_lsn(), r.replay_lsn) END AS current_to_replay_bytes,
    r.write_lag, r.flush_lag, r.replay_lag, r.sync_state, r.reply_time
FROM pg_stat_replication AS r
ORDER BY r.application_name;

\echo '[3] Standby-side receive/replay backlog'
SELECT
    :'sample_id' AS sample_id,
    clock_timestamp() AS observed_at,
    pg_is_in_recovery() AS in_recovery,
    pg_last_wal_receive_lsn() AS receive_lsn,
    pg_last_wal_replay_lsn() AS replay_lsn,
    CASE
      WHEN pg_last_wal_receive_lsn() IS NULL OR pg_last_wal_replay_lsn() IS NULL THEN NULL
      ELSE pg_wal_lsn_diff(pg_last_wal_receive_lsn(), pg_last_wal_replay_lsn())
    END AS receive_to_replay_bytes,
    pg_last_xact_replay_timestamp() AS last_replayed_xact_time,
    CASE
      WHEN pg_last_xact_replay_timestamp() IS NULL THEN NULL
      ELSE clock_timestamp() - pg_last_xact_replay_timestamp()
    END AS last_replayed_xact_age_context_only;

\echo '[4] Interpretation guardrails'
SELECT * FROM (VALUES
 ('BYTE DISTANCE','Not automatically RPO, data loss, or catch-up ETA'),
 ('ACK DELAY','write_lag/flush_lag/replay_lag are supporting acknowledgment-delay evidence'),
 ('TIMESTAMP','last_replayed_xact_age_context_only is not universal replication lag'),
 ('NULL','NULL is not converted to zero'),
 ('NEGATIVE','Unexpected negative distance is contradictory; do not ABS() it'),
 ('TREND','Use repeated timestamped samples before declaring backlog direction'),
 ('POLICY','PASS/FAIL requires approved thresholds and observation window'),
 ('SAFETY','Unexpected role/topology or suspected multiple writers requires STOP')
) AS guidance(category, interpretation);

\echo 'One SAFE-READ sample complete. Cleanup: NONE.'
