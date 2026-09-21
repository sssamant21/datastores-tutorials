/*
===============================================================================
Part 5.14 — Production Backup/Recovery Runbook and Recovery Readiness
Canonical Acceptance Artifact
[TUTORIAL-ACCEPTANCE — SAFE-READ]
Target: PostgreSQL 18
===============================================================================
*/
\set ON_ERROR_STOP on
\echo 'Part 5.14 — Production Recovery Readiness Evidence — SAFE-READ'

-- 1. Identity
SELECT current_database() AS connected_database, current_user AS current_user_name,
       version() AS server_version, current_setting('server_version_num') AS server_version_num,
       pg_postmaster_start_time() AS postmaster_start_time, current_timestamp AS observed_at;

-- 2. Recovery state. Received WAL is not necessarily replayed WAL.
SELECT pg_is_in_recovery() AS is_in_recovery,
       CASE WHEN pg_is_in_recovery() THEN pg_last_wal_receive_lsn() END AS last_wal_receive_lsn,
       CASE WHEN pg_is_in_recovery() THEN pg_last_wal_replay_lsn() END AS last_wal_replay_lsn,
       CASE WHEN pg_is_in_recovery() THEN pg_last_xact_replay_timestamp() END AS last_xact_replay_timestamp,
       current_timestamp AS observed_at;
\echo 'last_xact_replay_timestamp is not a universal real-time lag metric.'

-- 3. Database inventory. Read-only size collection can still carry operational cost.
SELECT datname, pg_size_pretty(pg_database_size(datname)) AS database_size, datallowconn, datistemplate
FROM pg_database ORDER BY datname;

-- 4. Recovery/WAL configuration; sensitive command/connection strings suppressed.
SELECT name,
       CASE WHEN name IN ('archive_command','archive_library','primary_conninfo')
            THEN CASE WHEN setting <> '' THEN '<configured>' ELSE '<not configured>' END
            ELSE setting END AS setting_evidence,
       unit, source, pending_restart
FROM pg_settings
WHERE name IN ('wal_level','archive_mode','archive_command','archive_library','wal_keep_size',
 'max_wal_senders','max_replication_slots','max_slot_wal_keep_size','idle_replication_slot_timeout',
 'hot_standby','synchronous_commit','synchronous_standby_names','primary_conninfo','primary_slot_name')
ORDER BY name;

-- 5. Archiver evidence. Counters are cumulative since stats_reset.
SELECT archived_count, failed_count, last_archived_wal, last_archived_time,
       last_failed_wal, last_failed_time, stats_reset
FROM pg_stat_archiver;
\echo 'Archive statistics do not prove remote WAL completeness or PITR.'

-- 6. Replication evidence. Full client network addresses intentionally suppressed.
SELECT pid, usename, application_name,
       CASE WHEN client_addr IS NULL THEN '<not exposed>' ELSE '<present>' END AS client_addr_evidence,
       state, sent_lsn, write_lsn, flush_lsn, replay_lsn,
       write_lag, flush_lag, replay_lag, sync_state, reply_time
FROM pg_stat_replication ORDER BY application_name, pid;
\echo 'Zero rows require interpretation against the expected architecture.'

-- 7. PostgreSQL 18 slot evidence. Inactive does not automatically mean abandoned.
SELECT slot_name, slot_type, database, active, inactive_since, restart_lsn,
       confirmed_flush_lsn, wal_status, safe_wal_size, invalidation_reason, failover, synced
FROM pg_replication_slots ORDER BY slot_name;
\echo 'max_slot_wal_keep_size=-1 means UNBOUNDED SLOT WAL RETENTION; not automatically failure.'

-- 8. Tablespaces. Full filesystem paths intentionally suppressed.
SELECT spcname,
       CASE WHEN pg_tablespace_location(oid) = '' THEN '<built-in/default>'
            ELSE '<external/non-default>' END AS location_evidence
FROM pg_tablespace ORDER BY spcname;

-- 9. Extension catalog inventory; target hosts also require compatible software/libraries.
SELECT e.extname, e.extversion, n.nspname AS schema_name
FROM pg_extension e JOIN pg_namespace n ON n.oid=e.extnamespace
ORDER BY e.extname;

-- 10. WAL statistics baseline.
SELECT wal_records, wal_fpi, wal_bytes, pg_size_pretty(wal_bytes) AS wal_bytes_pretty,
       stats_reset AS wal_stats_reset, current_timestamp AS observed_at
FROM pg_stat_wal;
\echo 'Do not calculate WAL-rate deltas across different stats_reset baselines.'

-- 11. Compact PostgreSQL-visible summary; no universal topology PASS/FAIL is inferred.
WITH role_state AS (SELECT pg_is_in_recovery() AS is_in_recovery),
dbs AS (SELECT count(*) FILTER (WHERE datallowconn AND NOT datistemplate) AS connectable_databases FROM pg_database),
repl AS (SELECT count(*) AS sender_count, count(*) FILTER (WHERE state='streaming') AS streaming_sender_count FROM pg_stat_replication),
slots AS (SELECT count(*) AS slot_count, count(*) FILTER (WHERE active) AS active_slot_count,
                 count(*) FILTER (WHERE NOT active) AS inactive_slot_count,
                 count(*) FILTER (WHERE wal_status IN ('unreserved','lost') OR invalidation_reason IS NOT NULL) AS slot_attention_count
          FROM pg_replication_slots),
arch AS (SELECT archived_count, failed_count, last_archived_time, last_failed_time, stats_reset FROM pg_stat_archiver)
SELECT role_state.is_in_recovery, dbs.connectable_databases, repl.sender_count, repl.streaming_sender_count,
       slots.slot_count, slots.active_slot_count, slots.inactive_slot_count, slots.slot_attention_count,
       arch.archived_count, arch.failed_count, arch.last_archived_time, arch.last_failed_time,
       arch.stats_reset AS archiver_stats_reset, current_timestamp AS observed_at
FROM role_state CROSS JOIN dbs CROSS JOIN repl CROSS JOIN slots CROSS JOIN arch;

\echo 'SAFE-READ collection complete. SAFE-READ does not mean PUBLIC-SAFE.'
\echo 'This does NOT prove external backup existence/readability, manifest integrity, WAL/timeline completeness,'
\echo 'KMS access, restore/PITR, application acceptance, RPO/RTO, DR, or failover readiness.'
\echo 'Missing required external evidence = UNKNOWN, not PASS.'
