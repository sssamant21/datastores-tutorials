/*
===============================================================================
Part 5.7 — Continuous WAL Archiving and Archive Operations
Canonical Acceptance Artifact

[TUTORIAL-ACCEPTANCE — SAFE-READ]
Target: PostgreSQL 18

Purpose:
  Inspect bounded PostgreSQL-visible WAL archive configuration and operational
  evidence without changing PostgreSQL, WAL, archive destinations, or files.

This artifact DOES NOT:
  - call pg_switch_wal();
  - execute CHECKPOINT;
  - execute pg_resetwal or pg_archivecleanup;
  - change archive_mode/archive_command/archive_library/archive_timeout;
  - expose raw archive_command or archive_library values;
  - mutate archive destinations;
  - create/drop/advance replication slots;
  - delete WAL;
  - inspect or mutate the filesystem;
  - start backup/recovery/PITR;
  - expose credentials;
  - perform automatic remediation.

Interpretation:
  SAFE-READ != WAL-ARCHIVE-VALIDATED
===============================================================================
*/

\echo '======================================================================'
\echo 'Part 5.7 — WAL Archive Readiness'
\echo '[TUTORIAL-ACCEPTANCE — SAFE-READ]'
\echo '======================================================================'

\echo '1. Execution context'
SELECT current_database() AS database_name,
       session_user,
       current_user,
       current_setting('server_version') AS server_version,
       current_setting('server_version_num') AS server_version_num,
       pg_is_in_recovery() AS is_in_recovery;

\echo '2. Archive configuration presence — sensitive values intentionally suppressed'
SELECT
    current_setting('archive_mode') AS archive_mode,
    current_setting('archive_timeout') AS archive_timeout,
    (NULLIF(current_setting('archive_command'), '') IS NOT NULL)
        AS archive_command_configured,
    (NULLIF(current_setting('archive_library'), '') IS NOT NULL)
        AS archive_library_configured;

\echo '3. Selected WAL and retention settings'
SELECT name, setting, unit, source
FROM pg_settings
WHERE name IN (
    'wal_level',
    'wal_segment_size',
    'archive_mode',
    'archive_timeout',
    'wal_keep_size',
    'max_wal_size',
    'min_wal_size',
    'max_replication_slots',
    'max_slot_wal_keep_size'
)
ORDER BY name;

\echo '4. Archiver statistics'
SELECT
    archived_count,
    last_archived_wal,
    last_archived_time,
    failed_count,
    last_failed_wal,
    last_failed_time,
    stats_reset
FROM pg_stat_archiver;

\echo '5. WAL generation statistics'
SELECT
    wal_records,
    wal_fpi,
    wal_bytes,
    wal_buffers_full,
    stats_reset
FROM pg_stat_wal;

\echo '6. Replication slots that may independently retain WAL'
SELECT
    slot_name,
    slot_type,
    database,
    active,
    restart_lsn,
    wal_status,
    safe_wal_size
FROM pg_replication_slots
ORDER BY slot_name;

\echo '7. Replication state'
SELECT
    application_name,
    client_addr,
    state,
    sent_lsn,
    write_lsn,
    flush_lsn,
    replay_lsn,
    sync_state
FROM pg_stat_replication
ORDER BY application_name, client_addr;

\echo '8. Current WAL position when executed on a primary'
SELECT
    pg_is_in_recovery() AS is_in_recovery,
    CASE
        WHEN pg_is_in_recovery() THEN NULL
        ELSE pg_current_wal_lsn()
    END AS primary_current_wal_lsn;

\echo '9. Archive mechanism consistency indicator'
SELECT
    CASE
        WHEN NULLIF(current_setting('archive_command'), '') IS NOT NULL
         AND NULLIF(current_setting('archive_library'), '') IS NOT NULL
            THEN 'REVIEW: both archive mechanisms appear configured'
        WHEN NULLIF(current_setting('archive_command'), '') IS NOT NULL
            THEN 'archive_command configured'
        WHEN NULLIF(current_setting('archive_library'), '') IS NOT NULL
            THEN 'archive_library configured'
        ELSE 'no archive mechanism value detected'
    END AS archive_mechanism_observation;

\echo '10. Recovery evidence boundary'
SELECT
    'PostgreSQL statistics provide archive activity/failure evidence only. '
    'This SAFE-READ artifact does not verify destination durability, object '
    'integrity, required-WAL continuity, retention correctness, retrieval, '
    'PITR, database recovery, application recovery, or RPO/RTO.'
    AS interpretation;

\echo '11. External validation still required'
SELECT *
FROM (VALUES
    ('archive destination availability and capacity'),
    ('expected archived-object existence'),
    ('archived-object integrity'),
    ('required WAL continuity'),
    ('retention against base-backup dependencies'),
    ('archive retrieval'),
    ('isolated recovery/PITR rehearsal'),
    ('database validation'),
    ('application validation'),
    ('measured RPO/RTO')
) AS required_external_validation(item);

\echo '======================================================================'
\echo 'WAL archive readiness inspection complete. No state was modified.'
\echo 'SAFE-READ != WAL-ARCHIVE-VALIDATED'
\echo '======================================================================'