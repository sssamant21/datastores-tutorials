/*
===============================================================================
Part 5.10 — Replication Slots, WAL Retention, and Disk-Risk Management
Hands-On Lab / Draft Acceptance Artifact

[TUTORIAL-ACCEPTANCE — SAFE-READ]

Target: PostgreSQL 18

Purpose:
  Inspect PostgreSQL-visible replication-slot and WAL-retention evidence
  without creating, advancing, invalidating, or dropping replication slots
  and without forcing WAL activity or checkpoints.

Safety boundary:
  READ ONLY.

This artifact DOES NOT:
  - create or drop replication slots;
  - call pg_replication_slot_advance();
  - change configuration;
  - execute CHECKPOINT;
  - force a WAL switch;
  - generate synthetic WAL;
  - modify archive configuration;
  - inspect or delete filesystem files;
  - repair or restart replication consumers;
  - perform automatic remediation.

Operational warning:
  SAFE-READ != ZERO OPERATIONAL COST.
  Catalog/statistics queries and LSN calculations are lightweight, but run
  production diagnostics according to local operational policy.

Acceptance boundary:
  SAFE-READ != SLOT-HEALTH-VALIDATED
  SAFE-READ != DISK-CAPACITY-VALIDATED
  SAFE-READ != REPLICATION-RECOVERABILITY-VALIDATED
===============================================================================
*/

\set ON_ERROR_STOP on

\echo '======================================================================'
\echo 'Part 5.10 — WAL Retention / Replication Slot SAFE-READ Check'
\echo '======================================================================'

-- ---------------------------------------------------------------------------
-- 1. Server identity and execution context
-- ---------------------------------------------------------------------------

\echo ''
\echo '[1/10] Server identity and execution context'

SELECT
    current_database() AS database_name,
    current_user AS current_user_name,
    version() AS server_version,
    pg_is_in_recovery() AS is_in_recovery,
    current_timestamp AS observed_at;

-- ---------------------------------------------------------------------------
-- 2. WAL-retention configuration
-- ---------------------------------------------------------------------------

\echo ''
\echo '[2/10] WAL-retention configuration'

SELECT
    name,
    setting,
    unit,
    source,
    pending_restart
FROM pg_catalog.pg_settings
WHERE name IN (
    'wal_level',
    'max_wal_size',
    'min_wal_size',
    'wal_keep_size',
    'max_replication_slots',
    'max_slot_wal_keep_size',
    'idle_replication_slot_timeout',
    'archive_mode',
    'archive_command',
    'archive_library'
)
ORDER BY name;

SELECT
    CASE
        WHEN setting = '-1' THEN 'UNBOUNDED SLOT WAL RETENTION'
        ELSE 'BOUNDED BY max_slot_wal_keep_size'
    END AS slot_wal_retention_classification,
    setting,
    unit
FROM pg_catalog.pg_settings
WHERE name = 'max_slot_wal_keep_size';

\echo ''
\echo 'Interpretation: UNBOUNDED is an exposure classification, not an'
\echo 'automatic configuration failure.'
\echo 'Interpretation: max_slot_wal_keep_size = -1 means slot WAL retention is'
\echo 'not bounded by that setting. This is not proof of an unsafe system;'
\echo 'capacity, WAL rate, consumer health, and operational controls matter.'

-- ---------------------------------------------------------------------------
-- 3. Replication-slot inventory
-- ---------------------------------------------------------------------------

\echo ''
\echo '[3/10] Replication-slot inventory'

SELECT
    slot_name,
    slot_type,
    database,
    plugin,
    temporary,
    active,
    active_pid,
    restart_lsn,
    confirmed_flush_lsn,
    wal_status,
    safe_wal_size,
    inactive_since,
    conflicting,
    invalidation_reason,
    failover,
    synced
FROM pg_catalog.pg_replication_slots
ORDER BY slot_type, slot_name;

-- ---------------------------------------------------------------------------
-- 4. Inactive slots requiring ownership/consumer investigation
-- ---------------------------------------------------------------------------

\echo ''
\echo '[4/10] Inactive-slot evidence'

SELECT
    slot_name,
    slot_type,
    database,
    temporary,
    active,
    inactive_since,
    CASE
        WHEN inactive_since IS NULL THEN NULL
        ELSE current_timestamp - inactive_since
    END AS inactive_for,
    restart_lsn,
    wal_status,
    safe_wal_size,
    invalidation_reason
FROM pg_catalog.pg_replication_slots
WHERE NOT active
ORDER BY inactive_since NULLS LAST, slot_name;

\echo ''
\echo 'WARNING: inactive does not mean abandoned.'
\echo 'Do not drop a slot without verified ownership, consumer state, impact,'
\echo 'recovery/reinitialization plan, and approval.'

-- ---------------------------------------------------------------------------
-- 5. Slot WAL-retention estimate
-- ---------------------------------------------------------------------------

\echo ''
\echo '[5/10] Slot WAL-retention estimate'

WITH wal_position AS (
    SELECT
        CASE
            WHEN pg_is_in_recovery()
                THEN pg_last_wal_replay_lsn()
            ELSE pg_current_wal_lsn()
        END AS observed_lsn
)
SELECT
    s.slot_name,
    s.slot_type,
    s.active,
    s.restart_lsn,
    w.observed_lsn,
    CASE
        WHEN s.restart_lsn IS NULL OR w.observed_lsn IS NULL THEN NULL
        ELSE pg_wal_lsn_diff(w.observed_lsn, s.restart_lsn)
    END AS retained_wal_bytes,
    CASE
        WHEN s.restart_lsn IS NULL OR w.observed_lsn IS NULL THEN NULL
        ELSE pg_size_pretty(
            pg_wal_lsn_diff(w.observed_lsn, s.restart_lsn)
        )
    END AS retained_wal_pretty,
    s.wal_status,
    s.safe_wal_size,
    CASE
        WHEN s.safe_wal_size IS NULL THEN NULL
        ELSE pg_size_pretty(s.safe_wal_size)
    END AS safe_wal_pretty
FROM pg_catalog.pg_replication_slots AS s
CROSS JOIN wal_position AS w
ORDER BY retained_wal_bytes DESC NULLS LAST, s.slot_name;

\echo ''
\echo 'NOTE: retained_wal_bytes is an LSN-distance estimate.'
\echo 'It is not a measurement of filesystem bytes attributable only to a slot.'

-- ---------------------------------------------------------------------------
-- 6. Slots with WAL availability or invalidation concerns
-- ---------------------------------------------------------------------------

\echo ''
\echo '[6/10] WAL availability / invalidation concerns'

SELECT
    slot_name,
    slot_type,
    active,
    inactive_since,
    restart_lsn,
    wal_status,
    safe_wal_size,
    invalidation_reason
FROM pg_catalog.pg_replication_slots
WHERE wal_status IN ('extended', 'unreserved', 'lost')
   OR invalidation_reason IS NOT NULL
ORDER BY
    CASE wal_status
        WHEN 'lost' THEN 1
        WHEN 'unreserved' THEN 2
        WHEN 'extended' THEN 3
        ELSE 4
    END,
    slot_name;

\echo ''
\echo 'Interpretation:'
\echo '  extended   -> WAL beyond normal max_wal_size behavior is retained.'
\echo '  unreserved -> required WAL is no longer guaranteed to remain retained;'
\echo '                this state can return to reserved/extended if conditions permit.'
\echo '  lost       -> slot is no longer usable; recovery/reinitialization may be needed.'
\echo ''
\echo 'Known invalidation reasons include:'
\echo '  wal_removed            -> required WAL was removed.'
\echo '  rows_removed           -> required rows were removed.'
\echo '  wal_level_insufficient -> WAL level became insufficient.'
\echo '  idle_timeout           -> configured idle-slot timeout invalidated the slot.'
\echo 'Always correlate with consumer health, ownership, topology, and configuration.'

-- ---------------------------------------------------------------------------
-- 7. Logical-slot cleanup horizons
-- ---------------------------------------------------------------------------

\echo ''
\echo '[7/10] Logical-slot cleanup horizons'

SELECT
    slot_name,
    database,
    plugin,
    active,
    xmin,
    catalog_xmin,
    restart_lsn,
    confirmed_flush_lsn,
    inactive_since,
    wal_status,
    invalidation_reason
FROM pg_catalog.pg_replication_slots
WHERE slot_type = 'logical'
ORDER BY slot_name;

\echo ''
\echo 'Logical slots can create both WAL-retention and cleanup-horizon risk.'
\echo 'Assess xmin/catalog_xmin using the wider vacuum/bloat monitoring model.'

-- ---------------------------------------------------------------------------
-- 8. Correlation with active WAL sender sessions
-- ---------------------------------------------------------------------------

\echo ''
\echo '[8/10] Slot-to-WAL-sender correlation'

SELECT
    s.slot_name,
    s.slot_type,
    s.active,
    s.active_pid,
    r.application_name,
    r.client_addr,
    r.state,
    r.sent_lsn,
    r.write_lsn,
    r.flush_lsn,
    r.replay_lsn,
    r.sync_state
FROM pg_catalog.pg_replication_slots AS s
LEFT JOIN pg_catalog.pg_stat_replication AS r
    ON r.pid = s.active_pid
ORDER BY s.slot_name;

-- ---------------------------------------------------------------------------
-- 9. WAL archive evidence
-- ---------------------------------------------------------------------------

\echo ''
\echo '[9/10] WAL archive statistics'

SELECT
    archived_count,
    failed_count,
    last_archived_wal,
    last_archived_time,
    last_failed_wal,
    last_failed_time,
    stats_reset
FROM pg_catalog.pg_stat_archiver;

\echo ''
\echo 'Archive statistics are independent evidence.'
\echo 'A healthy archive does not by itself prove a slot or consumer is healthy.'

-- ---------------------------------------------------------------------------
-- 10. Summary counters
-- ---------------------------------------------------------------------------

\echo ''
\echo '[10/10] Summary counters'

SELECT
    count(*) AS total_slots,
    count(*) FILTER (WHERE slot_type = 'physical') AS physical_slots,
    count(*) FILTER (WHERE slot_type = 'logical') AS logical_slots,
    count(*) FILTER (WHERE active) AS active_slots,
    count(*) FILTER (WHERE NOT active) AS inactive_slots,
    count(*) FILTER (WHERE wal_status = 'extended') AS extended_slots,
    count(*) FILTER (WHERE wal_status = 'unreserved') AS unreserved_slots,
    count(*) FILTER (WHERE wal_status = 'lost') AS lost_slots,
    count(*) FILTER (WHERE invalidation_reason IS NOT NULL) AS invalidated_slots
FROM pg_catalog.pg_replication_slots;

\echo ''
\echo '======================================================================'
\echo 'SAFE-READ inspection complete.'
\echo ''
\echo 'This artifact does not prove:'
\echo '  * sufficient pg_wal filesystem capacity;'
\echo '  * healthy downstream consumers;'
\echo '  * successful archive retrieval;'
\echo '  * safe slot deletion/advancement;'
\echo '  * replication recoverability.'
\echo ''
\echo 'Never delete files manually from pg_wal.'
\echo 'Never drop or advance a slot solely because it is inactive or retaining WAL.'
\echo '======================================================================'
