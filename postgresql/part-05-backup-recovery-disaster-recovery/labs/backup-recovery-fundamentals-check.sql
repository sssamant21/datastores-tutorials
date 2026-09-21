/*
===============================================================================
Part 5.1 — Backup and Recovery Fundamentals
Canonical Acceptance Artifact

[TUTORIAL-ACCEPTANCE — SAFE-READ]

Target: PostgreSQL 18

Purpose:
  Collect bounded PostgreSQL server-side evidence relevant to backup and
  recovery readiness without changing PostgreSQL state.

This artifact CAN provide evidence about:
  - execution context and server version;
  - recovery state;
  - selected WAL/archive settings visible to the current role;
  - archive statistics;
  - WAL position;
  - replication-slot retention state;
  - database sizes;
  - tablespace inventory.

This artifact CANNOT prove:
  - that an external/off-host backup exists;
  - that a backup is complete or restorable;
  - that required archived WAL exists outside PostgreSQL;
  - that a backup manifest has passed verification;
  - that a restore/PITR will succeed;
  - that PostgreSQL/application validation will pass after recovery;
  - that approved RPO or RTO can be achieved.

Safety:
  - No backup is started.
  - No restore/PITR is started.
  - No CHECKPOINT is forced.
  - No replication slot is created, dropped, or advanced.
  - No WAL/archive file is deleted or copied.
  - No configuration is changed.
  - No session is terminated.
  - No filesystem backup is read.
  - No password, token, key, or other secret is intentionally inspected.
  - No automatic remediation is performed.

Interpretation:
  SAFE-READ != RECOVERY-READY
===============================================================================
*/

\echo '======================================================================'
\echo 'Part 5.1 — Backup and Recovery Fundamentals'
\echo '[TUTORIAL-ACCEPTANCE — SAFE-READ]'
\echo '======================================================================'

\echo '1. Execution context and PostgreSQL version'
SELECT
    current_database() AS database_name,
    session_user,
    current_user,
    current_setting('server_version') AS server_version,
    current_setting('server_version_num') AS server_version_num,
    pg_is_in_recovery() AS is_in_recovery;

\echo '2. Selected WAL, archive, checkpoint, and slot-retention settings'
SELECT
    name,
    setting,
    unit,
    source,
    pending_restart
FROM pg_settings
WHERE name IN (
    'wal_level',
    'archive_mode',
    'archive_command',
    'archive_library',
    'max_wal_size',
    'min_wal_size',
    'wal_keep_size',
    'max_slot_wal_keep_size',
    'checkpoint_timeout',
    'checkpoint_completion_target'
)
ORDER BY name;

\echo '3. Archive statistics'
SELECT
    archived_count,
    last_archived_wal,
    last_archived_time,
    failed_count,
    last_failed_wal,
    last_failed_time,
    stats_reset
FROM pg_stat_archiver;

\echo '4. Current WAL/replay position evidence'
SELECT
    pg_is_in_recovery() AS is_in_recovery,
    CASE
        WHEN pg_is_in_recovery() THEN NULL
        ELSE pg_current_wal_lsn()
    END AS current_wal_lsn,
    CASE
        WHEN pg_is_in_recovery() THEN pg_last_wal_receive_lsn()
        ELSE NULL
    END AS last_received_wal_lsn,
    CASE
        WHEN pg_is_in_recovery() THEN pg_last_wal_replay_lsn()
        ELSE NULL
    END AS last_replayed_wal_lsn;

\echo '5. Replication-slot WAL-retention evidence'
SELECT
    slot_name,
    slot_type,
    database,
    active,
    restart_lsn,
    confirmed_flush_lsn,
    wal_status,
    safe_wal_size,
    inactive_since,
    conflicting,
    invalidation_reason
FROM pg_replication_slots
ORDER BY slot_name;

\echo '6. Database inventory and logical size'
SELECT
    d.datname,
    pg_get_userbyid(d.datdba) AS owner_name,
    d.datallowconn,
    pg_size_pretty(pg_database_size(d.datname)) AS database_size
FROM pg_database AS d
ORDER BY pg_database_size(d.datname) DESC, d.datname;

\echo '7. Tablespace inventory'
SELECT
    spcname,
    pg_get_userbyid(spcowner) AS owner_name
FROM pg_tablespace
ORDER BY spcname;

\echo '8. Canonical interpretation boundary'
SELECT
    'Configuration and catalog evidence do not prove that a backup exists, '
    'that required WAL is protected externally, that the backup is valid, '
    'that restore/PITR will succeed, or that approved RPO/RTO can be met. '
    'Validate those claims using backup-platform evidence, integrity checks, '
    'and isolated recovery rehearsals.' AS interpretation;

\echo '9. Recovery evidence hierarchy'
SELECT *
FROM (
    VALUES
      (1, 'Configuration exists'),
      (2, 'Backup job succeeded'),
      (3, 'Recovery artifact exists'),
      (4, 'Artifact integrity validated'),
      (5, 'Restore/recovery completed'),
      (6, 'PostgreSQL validation passed'),
      (7, 'Application validation passed'),
      (8, 'Measured recovery satisfied approved RPO/RTO')
) AS evidence(level_no, evidence_level)
ORDER BY level_no;

\echo '======================================================================'
\echo 'Acceptance inspection complete. PostgreSQL state was not modified.'
\echo 'SAFE-READ != RECOVERY-READY'
\echo '======================================================================'