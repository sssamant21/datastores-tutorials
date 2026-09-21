/*
===============================================================================
Part 5.6 — WAL Fundamentals for Backup and Recovery
Canonical Acceptance Artifact

[TUTORIAL-ACCEPTANCE — SAFE-READ]
Target: PostgreSQL 18

Purpose:
  Inspect bounded WAL, checkpoint, archiving, replication, and slot metadata
  relevant to backup/recovery readiness without changing PostgreSQL state.

This artifact DOES NOT:
  - execute CHECKPOINT;
  - call pg_switch_wal();
  - execute pg_resetwal;
  - create, drop, or advance replication slots;
  - start or stop backup operations;
  - alter archive configuration;
  - alter durability/WAL/checkpoint settings;
  - modify roles or replication configuration;
  - access/delete WAL files;
  - perform filesystem operations;
  - perform automatic remediation.

Interpretation:
  SAFE-READ != WAL-RECOVERY-VALIDATED
===============================================================================
*/

\echo '======================================================================'
\echo 'Part 5.6 — WAL Recovery Readiness'
\echo '[TUTORIAL-ACCEPTANCE — SAFE-READ]'
\echo '======================================================================'

\echo '1. Execution context'
SELECT current_database() AS database_name,
       session_user,
       current_user,
       current_setting('server_version') AS server_version,
       current_setting('server_version_num') AS server_version_num,
       pg_is_in_recovery() AS is_in_recovery;

\echo '2. WAL/checkpoint/archive settings'
SELECT name, setting, unit, source
FROM pg_settings
WHERE name IN (
    'wal_level',
    'wal_segment_size',
    'wal_buffers',
    'wal_compression',
    'full_page_writes',
    'wal_keep_size',
    'max_wal_size',
    'min_wal_size',
    'checkpoint_timeout',
    'checkpoint_completion_target',
    'archive_mode',
    'max_wal_senders',
    'max_replication_slots',
    'max_slot_wal_keep_size'
)
ORDER BY name;

\echo '3. Archive mechanism presence — values intentionally not exposed'
SELECT
    current_setting('archive_mode') AS archive_mode,
    (NULLIF(current_setting('archive_command'), '') IS NOT NULL)
        AS archive_command_configured,
    (NULLIF(current_setting('archive_library'), '') IS NOT NULL)
        AS archive_library_configured;

\echo '4. WAL statistics'
SELECT
    wal_records,
    wal_fpi,
    wal_bytes,
    wal_buffers_full,
    wal_write,
    wal_sync,
    wal_write_time,
    wal_sync_time,
    stats_reset
FROM pg_stat_wal;

\echo '5. Archiver statistics'
SELECT
    archived_count,
    last_archived_wal,
    last_archived_time,
    failed_count,
    last_failed_wal,
    last_failed_time,
    stats_reset
FROM pg_stat_archiver;

\echo '6. PostgreSQL 18 checkpointer statistics'
SELECT
    num_timed,
    num_requested,
    num_done,
    restartpoints_timed,
    restartpoints_req,
    restartpoints_done,
    write_time,
    sync_time,
    buffers_written,
    slru_written,
    stats_reset
FROM pg_stat_checkpointer;

\echo '7. Replication slots'
SELECT
    slot_name,
    slot_type,
    database,
    active,
    temporary,
    restart_lsn,
    confirmed_flush_lsn,
    wal_status,
    safe_wal_size
FROM pg_replication_slots
ORDER BY slot_name;

\echo '8. WAL sender/replica state'
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
    sync_state
FROM pg_stat_replication
ORDER BY pid;

\echo '9. Current/replay WAL position'
SELECT
    pg_is_in_recovery() AS is_in_recovery,
    CASE
        WHEN pg_is_in_recovery() THEN NULL
        ELSE pg_current_wal_lsn()
    END AS primary_current_wal_lsn,
    CASE
        WHEN pg_is_in_recovery() THEN pg_last_wal_replay_lsn()
        ELSE NULL
    END AS standby_replay_lsn;

\echo '10. Interpretation boundary'
SELECT
    'SAFE-READ only. This does not prove WAL archive durability, filesystem '
    'capacity, backup completeness, PITR capability, required-WAL continuity, '
    'or successful database/application recovery.' AS interpretation;

\echo '======================================================================'
\echo 'WAL recovery-readiness inspection complete. No state was modified.'
\echo 'SAFE-READ != WAL-RECOVERY-VALIDATED'
\echo '======================================================================'
