/*
===============================================================================
Part 5.8 — Point-in-Time Recovery (PITR)
Canonical Acceptance Artifact

[TUTORIAL-ACCEPTANCE — SAFE-READ]
Target: PostgreSQL 18

Purpose:
  Inspect bounded PostgreSQL-visible identity, WAL, archive, replication, and
  recovery context relevant to PITR readiness without performing recovery.

PROHIBITED:
  - recovery.signal / standby.signal mutation
  - recovery configuration mutation
  - restore_command execution
  - pg_create_restore_point()
  - pg_wal_replay_pause() / pg_wal_replay_resume()
  - pg_promote()
  - pg_switch_wal()
  - CHECKPOINT
  - pg_resetwal / pg_archivecleanup
  - WAL deletion
  - backup/restore execution
  - service restart
  - filesystem mutation
  - session termination
  - automatic remediation

Interpretation:
  SAFE-READ != PITR-VALIDATED
===============================================================================
*/

\echo '======================================================================'
\echo 'Part 5.8 — PITR Readiness'
\echo '[TUTORIAL-ACCEPTANCE — SAFE-READ]'
\echo '======================================================================'

\echo '1. Execution context'
SELECT current_database() AS database_name,
       session_user,
       current_user,
       current_setting('server_version') AS server_version,
       current_setting('server_version_num') AS server_version_num,
       pg_is_in_recovery() AS is_in_recovery;

\echo '2. PostgreSQL system identity'
SELECT system_identifier,
       pg_control_version,
       catalog_version_no
FROM pg_control_system();

\echo '3. Selected control/checkpoint evidence'
SELECT checkpoint_lsn,
       redo_lsn,
       redo_wal_file,
       timeline_id,
       prev_timeline_id,
       full_page_writes,
       next_xid,
       next_oid,
       checkpoint_time
FROM pg_control_checkpoint();

\echo '4. Recovery/archive-related settings — command values suppressed'
SELECT name, setting, unit, source
FROM pg_settings
WHERE name IN (
    'wal_level',
    'archive_mode',
    'archive_timeout',
    'wal_keep_size',
    'max_wal_size',
    'max_replication_slots',
    'max_slot_wal_keep_size',
    'hot_standby'
)
ORDER BY name;

\echo '5. Archive mechanism presence — raw values intentionally hidden'
SELECT
    current_setting('archive_mode') AS archive_mode,
    (NULLIF(current_setting('archive_command'), '') IS NOT NULL)
        AS archive_command_configured,
    (NULLIF(current_setting('archive_library'), '') IS NOT NULL)
        AS archive_library_configured;

\echo '6. Archiver evidence'
SELECT archived_count,
       last_archived_wal,
       last_archived_time,
       failed_count,
       last_failed_wal,
       last_failed_time,
       stats_reset
FROM pg_stat_archiver;

\echo '7. WAL statistics'
SELECT wal_records,
       wal_fpi,
       wal_bytes,
       wal_buffers_full,
       stats_reset
FROM pg_stat_wal;

\echo '8. Current/replay WAL position'
SELECT
    pg_is_in_recovery() AS is_in_recovery,
    CASE WHEN pg_is_in_recovery()
         THEN NULL ELSE pg_current_wal_lsn() END AS primary_current_wal_lsn,
    CASE WHEN pg_is_in_recovery()
         THEN pg_last_wal_receive_lsn() ELSE NULL END AS standby_receive_lsn,
    CASE WHEN pg_is_in_recovery()
         THEN pg_last_wal_replay_lsn() ELSE NULL END AS standby_replay_lsn,
    CASE WHEN pg_is_in_recovery()
         THEN pg_last_xact_replay_timestamp() ELSE NULL END
         AS last_replayed_transaction_timestamp;

\echo '9. Tablespace inventory'
SELECT spcname AS tablespace_name,
       pg_tablespace_location(oid) AS tablespace_location
FROM pg_tablespace
ORDER BY spcname;

\echo '10. Database inventory and logical size'
SELECT datname AS database_name,
       pg_size_pretty(pg_database_size(datname)) AS database_size
FROM pg_database
WHERE datallowconn
ORDER BY pg_database_size(datname) DESC;

\echo '11. Replication slots that may affect WAL retention'
SELECT slot_name,
       slot_type,
       database,
       active,
       restart_lsn,
       wal_status,
       safe_wal_size
FROM pg_replication_slots
ORDER BY slot_name;

\echo '12. Replication state'
SELECT application_name,
       client_addr,
       state,
       sent_lsn,
       write_lsn,
       flush_lsn,
       replay_lsn,
       sync_state
FROM pg_stat_replication
ORDER BY application_name, client_addr;

\echo '13. PITR evidence boundary'
SELECT
    'SAFE-READ only. This artifact does not verify backup integrity, required '
    'WAL continuity, restore_command behavior, recovery target correctness, '
    'target inclusion semantics, timeline correctness, successful replay, '
    'database/application recovery, safe cutover, or RPO/RTO.'
    AS interpretation;

\echo '14. External recovery validation still required'
SELECT *
FROM (VALUES
    ('physical backup identity and integrity'),
    ('required WAL availability, integrity, and continuity'),
    ('recovery target evidence'),
    ('target timezone and inclusion semantics'),
    ('timeline selection/history'),
    ('recovery configuration and WAL retrieval'),
    ('isolated PITR execution'),
    ('target attainment'),
    ('database validation'),
    ('application/business validation'),
    ('write fencing and cutover'),
    ('measured RPO/RTO')
) AS required_external_validation(item);

\echo '======================================================================'
\echo 'PITR readiness inspection complete. No state was modified.'
\echo 'SAFE-READ != PITR-VALIDATED'
\echo '======================================================================'