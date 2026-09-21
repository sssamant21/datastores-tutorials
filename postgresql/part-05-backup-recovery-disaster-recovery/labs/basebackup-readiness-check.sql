/*
===============================================================================
Part 5.5 — Physical Backup Architecture and pg_basebackup
Canonical Acceptance Artifact

[TUTORIAL-ACCEPTANCE — SAFE-READ]
Target: PostgreSQL 18

Purpose:
  Inspect bounded PostgreSQL metadata/settings relevant to physical base-backup
  readiness without initiating or modifying backup/recovery state.

This artifact DOES NOT:
  - execute pg_basebackup, pg_combinebackup, or pg_verifybackup;
  - call backup start/stop functions;
  - create/drop/modify replication slots;
  - force WAL switches or checkpoints;
  - alter configuration, roles, privileges, or pg_hba.conf;
  - inspect authentication-secret material;
  - access or modify filesystem backup artifacts;
  - perform automatic remediation.

Interpretation:
  SAFE-READ != PHYSICAL-BACKUP-VALIDATED
===============================================================================
*/

\echo '======================================================================'
\echo 'Part 5.5 — Physical Base Backup Readiness'
\echo '[TUTORIAL-ACCEPTANCE — SAFE-READ]'
\echo '======================================================================'

\echo '1. Execution context'
SELECT current_database() AS database_name,
       session_user,
       current_user,
       current_setting('server_version') AS server_version,
       current_setting('server_version_num') AS server_version_num,
       pg_is_in_recovery() AS is_in_recovery;

\echo '2. WAL and physical-backup related settings'
SELECT name, setting, unit, source
FROM pg_settings
WHERE name IN (
    'wal_level',
    'max_wal_senders',
    'max_replication_slots',
    'wal_keep_size',
    'max_slot_wal_keep_size',
    'archive_mode',
    'archive_command',
    'archive_library'
)
ORDER BY name;

\echo '3. Current WAL position — primary only'
SELECT CASE
           WHEN pg_is_in_recovery() THEN NULL
           ELSE pg_current_wal_lsn()
       END AS current_wal_lsn,
       pg_is_in_recovery() AS is_in_recovery;

\echo '4. Tablespace metadata'
SELECT t.spcname,
       pg_get_userbyid(t.spcowner) AS owner_name
FROM pg_tablespace AS t
ORDER BY t.spcname;

\echo '5. Database size inventory'
SELECT d.datname,
       d.datallowconn,
       d.datistemplate,
       pg_size_pretty(pg_database_size(d.datname)) AS database_size,
       pg_database_size(d.datname) AS database_bytes
FROM pg_database AS d
ORDER BY pg_database_size(d.datname) DESC, d.datname;

\echo '6. Replication-capable role inventory — no credentials'
SELECT r.rolname,
       r.rolsuper,
       r.rolreplication,
       r.rolcanlogin
FROM pg_roles AS r
WHERE r.rolsuper OR r.rolreplication
ORDER BY r.rolname;

\echo '7. Replication slot inventory'
SELECT slot_name,
       slot_type,
       database,
       active,
       temporary,
       restart_lsn,
       confirmed_flush_lsn
FROM pg_replication_slots
ORDER BY slot_name;

\echo '8. Current WAL sender activity'
SELECT pid,
       usename,
       application_name,
       client_addr,
       state,
       sync_state
FROM pg_stat_replication
ORDER BY pid;

\echo '9. Active base-backup progress'
SELECT pid,
       phase,
       backup_total,
       backup_streamed,
       tablespaces_total,
       tablespaces_streamed
FROM pg_stat_progress_basebackup
ORDER BY pid;

\echo '10. Summed database-size indicator'
SELECT pg_size_pretty(sum(pg_database_size(datname))) AS summed_database_size,
       sum(pg_database_size(datname)) AS summed_database_bytes
FROM pg_database;

\echo '11. Interpretation boundary'
SELECT
    'SAFE-READ only. This does not execute a backup, validate network/'
    'authentication, inspect destination capacity, prove WAL availability, '
    'verify backup artifacts/manifests, reconstruct an incremental chain, '
    'or demonstrate physical/application recovery.' AS interpretation;

\echo '======================================================================'
\echo 'Physical-backup readiness inspection complete. No backup was started.'
\echo 'SAFE-READ != PHYSICAL-BACKUP-VALIDATED'
\echo '======================================================================'