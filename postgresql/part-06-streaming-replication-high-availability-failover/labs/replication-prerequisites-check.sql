/*
Part 6.2 Lab — Replication Prerequisites Check

Target: PostgreSQL 18
Classification: TUTORIAL-ACCEPTANCE — SAFE-READ
Status: Canonical Acceptance Artifact — Pending Repository Validation

Purpose
-------
Collect PostgreSQL-side evidence before a physical streaming-replication
change. This script performs no writes and makes no configuration changes.

PASS / FAIL / UNKNOWN
---------------------
PASS    = current database evidence supports the requirement.
FAIL    = current database evidence proves the requirement is not satisfied.
UNKNOWN = the evidence needed to decide is external, missing, or requires
          architecture-specific demand information.

Safety
------
This script MUST NOT:
  - run ALTER SYSTEM;
  - create/drop replication slots;
  - create/alter roles;
  - edit pg_hba.conf or TLS;
  - reload/restart PostgreSQL;
  - run pg_basebackup;
  - call pg_promote();
  - build or promote a standby.

Run with psql:
  psql -X -v ON_ERROR_STOP=1 -d postgres -f labs/replication-prerequisites-check.sql
*/

\pset pager off
\set QUIET 1

\echo '============================================================'
\echo 'Part 6.2 — Replication Prerequisites Check'
\echo 'SAFE-READ: no database changes are performed'
\echo '============================================================'

\echo ''
\echo '--- 1. Instance identity and current role ---'
SELECT
    current_database() AS database_name,
    current_user AS connected_user,
    inet_server_addr() AS server_address,
    inet_server_port() AS server_port,
    pg_is_in_recovery() AS is_in_recovery,
    CASE
        WHEN pg_is_in_recovery() THEN 'STANDBY/RECOVERY'
        ELSE 'PRIMARY/CANDIDATE-SENDER'
    END AS observed_role;

\echo ''
\echo 'Decision: verify this identity against the approved change record.'
\echo 'A SQL result alone does not prove environment or host ownership.'

\echo ''
\echo '--- 2. PostgreSQL version evidence ---'
SELECT
    current_setting('server_version') AS server_version,
    current_setting('server_version_num') AS server_version_num,
    version() AS build_string;

SELECT
    CASE
        WHEN current_setting('server_version_num')::integer >= 180000
         AND current_setting('server_version_num')::integer < 190000
            THEN 'PASS'
        ELSE 'FAIL'
    END AS pg18_tutorial_target_result,
    'This lab targets PostgreSQL major version 18; separately compare the proposed peer.' AS evidence_note;

\echo ''
\echo '--- 3. Core WAL / sender / slot configuration ---'
SELECT
    name,
    setting,
    unit,
    context,
    source,
    pending_restart
FROM pg_settings
WHERE name IN (
    'wal_level',
    'max_wal_senders',
    'max_replication_slots',
    'wal_keep_size',
    'max_slot_wal_keep_size',
    'archive_mode',
    'archive_command',
    'archive_library',
    'max_connections',
    'superuser_reserved_connections',
    'hot_standby'
)
ORDER BY name;

\echo ''
\echo '--- 4. Physical-streaming WAL-level gate ---'
SELECT
    current_setting('wal_level') AS wal_level,
    CASE current_setting('wal_level')
        WHEN 'replica' THEN 'PASS'
        WHEN 'logical' THEN 'PASS'
        ELSE 'FAIL'
    END AS result,
    CASE current_setting('wal_level')
        WHEN 'replica' THEN 'Suitable for physical streaming replication.'
        WHEN 'logical' THEN 'Suitable for physical streaming; confirm logical level is intentional.'
        ELSE 'wal_level must be replica or higher for physical streaming replication.'
    END AS evidence_note;

\echo ''
\echo '--- 5. WAL sender configured capacity ---'
WITH s AS (
    SELECT current_setting('max_wal_senders')::integer AS configured
),
a AS (
    SELECT count(*)::integer AS active_walsenders
    FROM pg_stat_replication
)
SELECT
    s.configured AS max_wal_senders,
    a.active_walsenders,
    s.configured - a.active_walsenders AS currently_unoccupied_sender_capacity,
    CASE
        WHEN s.configured = 0 THEN 'FAIL'
        ELSE 'UNKNOWN'
    END AS result,
    CASE
        WHEN s.configured = 0
            THEN 'Streaming replication is disabled by sender capacity.'
        ELSE 'Compare configured/occupied capacity with planned standbys, base backups, and reserve.'
    END AS evidence_note
FROM s CROSS JOIN a;

\echo ''
\echo '--- 6. Existing WAL sender activity (inventory only) ---'
SELECT
    pid,
    application_name,
    client_addr,
    state,
    sync_state
FROM pg_stat_replication
ORDER BY pid;

\echo ''
\echo 'Do not interpret this section as a replication-lag acceptance test.'
\echo 'Detailed streaming/replay validation belongs to 6.5; lag interpretation belongs to 6.6.'

\echo ''
\echo '--- 7. Replication slot capacity (conditional prerequisite) ---'
WITH c AS (
    SELECT
        current_setting('max_replication_slots')::integer AS configured,
        count(*)::integer AS existing_slots
    FROM pg_replication_slots
)
SELECT
    configured AS max_replication_slots,
    existing_slots,
    configured - existing_slots AS currently_unoccupied_slot_capacity,
    'UNKNOWN' AS result,
    'PASS/FAIL depends on whether slots are planned and how many additional slots the approved topology requires.' AS evidence_note
FROM c;

\echo ''
\echo '--- 8. Existing replication slots (inventory only) ---'
SELECT
    slot_name,
    slot_type,
    active,
    database,
    wal_status
FROM pg_replication_slots
ORDER BY slot_name;

\echo ''
\echo 'Detailed slot retention and invalidation analysis belongs to Part 6.8.'

\echo ''
\echo '--- 9. Connection context ---'
WITH c AS (
    SELECT count(*)::integer AS current_sessions
    FROM pg_stat_activity
)
SELECT
    current_setting('max_connections')::integer AS max_connections,
    current_setting('superuser_reserved_connections')::integer AS superuser_reserved_connections,
    c.current_sessions,
    'UNKNOWN' AS result,
    'Current sessions are evidence, not a forecast. Validate workload headroom separately.' AS evidence_note
FROM c;

\echo ''
\echo '--- 10. Archive / retention inventory ---'
SELECT
    name,
    setting,
    unit,
    context,
    source,
    pending_restart
FROM pg_settings
WHERE name IN (
    'archive_mode',
    'archive_command',
    'archive_library',
    'wal_keep_size',
    'max_slot_wal_keep_size'
)
ORDER BY name;

\echo ''
\echo 'These settings are architecture evidence, not universal streaming-replication requirements.'

\echo ''
\echo '--- 11. Tablespace inventory ---'
SELECT
    spcname AS tablespace_name,
    pg_tablespace_location(oid) AS configured_location,
    CASE
        WHEN pg_tablespace_location(oid) = '' THEN 'DEFAULT/INTERNAL'
        ELSE 'EXTERNAL PATH — validate matching standby path/mount'
    END AS assessment
FROM pg_tablespace
ORDER BY spcname;

\echo ''
\echo 'Destination mount existence, free space, and performance require external evidence.'

\echo ''
\echo '--- 12. Configuration source / restart evidence ---'
SELECT
    name,
    setting,
    unit,
    context,
    source,
    sourcefile,
    sourceline,
    pending_restart
FROM pg_settings
WHERE name IN (
    'wal_level',
    'max_wal_senders',
    'max_replication_slots',
    'wal_keep_size',
    'max_slot_wal_keep_size',
    'archive_mode',
    'archive_command',
    'archive_library',
    'max_connections',
    'superuser_reserved_connections',
    'hot_standby'
)
ORDER BY name;

\echo ''
\echo 'Redact filesystem/configuration details from evidence when local policy requires it.'

\echo ''
\echo '--- 13. PostgreSQL-side gate summary ---'
WITH g AS (
    SELECT
        current_setting('wal_level') IN ('replica','logical') AS wal_level_ok,
        current_setting('max_wal_senders')::integer > 0 AS sender_enabled
)
SELECT
    CASE WHEN wal_level_ok THEN 'PASS' ELSE 'FAIL' END AS wal_level_gate,
    CASE WHEN sender_enabled THEN 'UNKNOWN' ELSE 'FAIL' END AS sender_capacity_gate,
    'UNKNOWN' AS peer_version_compatibility,
    'UNKNOWN' AS standby_storage_capacity,
    'UNKNOWN' AS network_reachability,
    'UNKNOWN' AS dns_validation,
    'UNKNOWN' AS time_synchronization,
    'UNKNOWN' AS failure_domain_validation,
    'UNKNOWN' AS backup_recovery_readiness,
    'UNKNOWN' AS change_approval_and_ownership
FROM g;

\echo ''
\echo '============================================================'
\echo 'FINAL DECISION RULE'
\echo 'Do not proceed while any safety-critical prerequisite is FAIL'
\echo 'or UNKNOWN. Resolve external evidence outside this SQL script.'
\echo '============================================================'
\echo ''
\echo 'Cleanup required: NONE (SAFE-READ).'
