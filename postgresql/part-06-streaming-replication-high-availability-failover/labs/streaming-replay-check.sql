-- Part 6.5 — Verify Streaming and WAL Replay
-- Target: PostgreSQL 18
-- Classification: [SAFE-READ]
-- MUTATIONS: NONE
-- CLEANUP: NONE
--
-- Run independently against each expected node and correlate with approved topology.
-- conninfo is intentionally excluded.
-- Idle/unchanged LSNs are not automatic failure or lag.
\set ON_ERROR_STOP on

\echo '============================================================'
\echo 'Part 6.5 — Streaming and WAL Replay Evidence'
\echo 'SAFE-READ / PostgreSQL 18'
\echo '============================================================'

\echo '[1] Server and observed role'
SELECT
    current_database() AS database_name,
    inet_server_addr() AS server_address,
    inet_server_port() AS server_port,
    current_setting('server_version') AS server_version,
    pg_is_in_recovery() AS in_recovery,
    CASE WHEN pg_is_in_recovery() THEN 'STANDBY' ELSE 'PRIMARY' END AS observed_role,
    clock_timestamp() AS observed_at;

\echo '[2] Primary-side WAL sender evidence'
SELECT
    application_name,
    client_addr,
    client_port,
    backend_start,
    state,
    sent_lsn,
    write_lsn,
    flush_lsn,
    replay_lsn,
    sync_priority,
    sync_state,
    reply_time
FROM pg_stat_replication
ORDER BY application_name, client_addr NULLS LAST;

\echo '[3] Standby-side WAL receiver evidence — conninfo excluded'
SELECT
    status,
    receive_start_lsn,
    receive_start_tli,
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

\echo '[4] Standby receive/replay evidence'
SELECT
    pg_is_in_recovery() AS in_recovery,
    pg_last_wal_receive_lsn() AS last_receive_lsn,
    pg_last_wal_replay_lsn() AS last_replay_lsn,
    pg_last_xact_replay_timestamp() AS last_replayed_xact_time,
    clock_timestamp() AS observed_at;

\echo '[5] Interpretation reminders'
SELECT *
FROM (VALUES
 ('ROLE','Expected standby with in_recovery=false','FAIL / STOP'),
 ('ROLE','Expected primary with in_recovery=true','FAIL'),
 ('SENDER','No sender where a direct standby is expected','FAIL/UNKNOWN — confirm topology'),
 ('RECEIVER','No receiver on expected streaming standby','FAIL/UNKNOWN — investigate'),
 ('LSN','Receive/replay LSN unchanged on idle system','INSUFFICIENT EVIDENCE — do not call lag'),
 ('TIME','Old replay transaction timestamp on idle system','NOT AUTOMATIC LAG'),
 ('ACCESS','Required evidence inaccessible','UNKNOWN'),
 ('TOPOLOGY','Upstream/timeline conflicts with approved topology','CONTRADICTORY — investigate'),
 ('SAFETY','More than one writable authority suspected','STOP — use fencing/incident procedure')
) AS g(category, observation, interpretation);

\echo 'SAFE-READ evidence collection complete.'
\echo 'Detailed quantitative lag analysis belongs to Part 6.6.'
\echo 'Cleanup: NONE'
