\set ON_ERROR_STOP on

/*
  PostgreSQL Part 6.8
  Replication Slots, WAL Retention, and Standby Safety
  Locked lab: slot-retention-risk-check.sql

  SAFE-READ:
  - Does not create replication slots.
  - Does not drop replication slots.
  - Does not ALTER SYSTEM.
  - Does not restart PostgreSQL.
  - Does not terminate replication sessions.
  - Does not manipulate WAL.
  - Does not intentionally disconnect a standby.

  Recommended:
      psql -X -f labs/slot-retention-risk-check.sql
*/

\echo '======================================================================'
\echo '6.8 - Replication Slots, WAL Retention, and Standby Safety'
\echo 'SAFE-READ evidence collection'
\echo '======================================================================'

\echo ''
\echo '[1/9] Server identity and execution context'

SELECT
    current_database() AS database_name,
    current_user AS current_user,
    inet_server_addr() AS server_address,
    inet_server_port() AS server_port,
    version() AS postgres_version;

\echo ''
\echo '[2/9] Primary/standby role'

SELECT
    pg_is_in_recovery() AS is_in_recovery,
    CASE
        WHEN pg_is_in_recovery()
            THEN 'STANDBY: interpret primary-side slot evidence carefully'
        ELSE 'PRIMARY: replication-slot retention evidence can be evaluated here'
    END AS interpretation;

\echo ''
\echo '[3/9] WAL and slot retention configuration'

SELECT
    name,
    setting,
    unit,
    source,
    pending_restart
FROM pg_settings
WHERE name IN (
    'wal_level',
    'wal_keep_size',
    'max_slot_wal_keep_size',
    'idle_replication_slot_timeout'
)
ORDER BY name;

\echo ''
\echo '[4/9] Replication slot inventory'

SELECT
    slot_name,
    slot_type,
    database,
    active,
    active_pid,
    inactive_since,
    restart_lsn,
    wal_status,
    safe_wal_size,
    invalidation_reason
FROM pg_replication_slots
ORDER BY slot_type, slot_name;

\echo ''
\echo '[5/9] Physical replication slots'

SELECT
    slot_name,
    active,
    active_pid,
    inactive_since,
    restart_lsn,
    wal_status,
    safe_wal_size,
    invalidation_reason
FROM pg_replication_slots
WHERE slot_type = 'physical'
ORDER BY slot_name;

\echo ''
\echo '[6/9] WAL-distance evidence for physical slots'

SELECT
    slot_name,
    active,
    restart_lsn,
    CASE
        WHEN NOT pg_is_in_recovery()
             AND restart_lsn IS NOT NULL
            THEN pg_wal_lsn_diff(pg_current_wal_lsn(), restart_lsn)
        ELSE NULL
    END AS wal_distance_bytes,
    CASE
        WHEN NOT pg_is_in_recovery()
             AND restart_lsn IS NOT NULL
            THEN pg_size_pretty(
                pg_wal_lsn_diff(pg_current_wal_lsn(), restart_lsn)
            )
        ELSE NULL
    END AS wal_distance_pretty,
    wal_status,
    safe_wal_size
FROM pg_replication_slots
WHERE slot_type = 'physical'
ORDER BY slot_name;

\echo ''
\echo '[7/9] Slot-risk classification'

WITH settings AS (
    SELECT
        current_setting('max_slot_wal_keep_size') AS max_slot_wal_keep_size
),
slots AS (
    SELECT
        slot_name,
        slot_type,
        active,
        inactive_since,
        restart_lsn,
        wal_status,
        safe_wal_size,
        invalidation_reason
    FROM pg_replication_slots
    WHERE slot_type = 'physical'
)
SELECT
    s.slot_name,
    CASE
        WHEN s.invalidation_reason IS NOT NULL
             OR s.wal_status = 'lost'
            THEN 'CRITICAL'
        WHEN s.wal_status = 'unreserved'
            THEN 'WARNING'
        WHEN NOT s.active
            THEN 'WARNING'
        WHEN s.wal_status IN ('reserved', 'extended')
            THEN 'PASS'
        ELSE 'UNKNOWN'
    END AS observed_class,
    CASE
        WHEN s.invalidation_reason IS NOT NULL THEN
            'Slot is invalidated; preserve evidence and evaluate consumer recovery or rebuild.'
        WHEN s.wal_status = 'lost' THEN
            'Required WAL has been lost for this slot; the slot is no longer usable for normal continuation.'
        WHEN s.wal_status = 'unreserved' THEN
            'Required WAL is not safely reserved; investigate retention limits and consumer health promptly.'
        WHEN NOT s.active THEN
            'Slot is inactive. Determine whether this is expected maintenance, temporary disconnection, failure, or abandonment.'
        WHEN s.wal_status = 'extended' THEN
            'Slot is active/valid and WAL retention extends beyond ordinary reservation; monitor capacity and consumer progress.'
        WHEN s.wal_status = 'reserved' THEN
            'Slot is active/valid with required WAL currently reserved; continue normal monitoring.'
        ELSE
            'Slot state requires operator interpretation.'
    END AS interpretation,
    s.active,
    s.inactive_since,
    s.restart_lsn,
    s.wal_status,
    s.safe_wal_size,
    s.invalidation_reason,
    cfg.max_slot_wal_keep_size
FROM slots s
CROSS JOIN settings cfg
ORDER BY
    CASE
        WHEN s.invalidation_reason IS NOT NULL OR s.wal_status = 'lost' THEN 1
        WHEN s.wal_status = 'unreserved' THEN 2
        WHEN NOT s.active THEN 3
        WHEN s.wal_status IN ('reserved', 'extended') THEN 4
        ELSE 5
    END,
    s.slot_name;

\echo ''
\echo '[8/9] Slot summary'

SELECT
    count(*) AS total_slots,
    count(*) FILTER (WHERE slot_type = 'physical') AS physical_slots,
    count(*) FILTER (WHERE slot_type = 'logical') AS logical_slots,
    count(*) FILTER (WHERE active) AS active_slots,
    count(*) FILTER (WHERE NOT active) AS inactive_slots,
    count(*) FILTER (WHERE wal_status = 'unreserved') AS unreserved_slots,
    count(*) FILTER (
        WHERE wal_status = 'lost'
           OR invalidation_reason IS NOT NULL
    ) AS critical_or_invalidated_slots
FROM pg_replication_slots;

\echo ''
\echo '[9/9] Operator reminders'

SELECT
    'An inactive replication slot is not automatically abandoned or failed.' AS reminder
UNION ALL
SELECT
    'restart_lsn WAL distance is evidence of WAL-position retention; it is not exact slot-attributable filesystem usage.'
UNION ALL
SELECT
    'safe_wal_size NULL is not automatically failure; interpret it with wal_status and max_slot_wal_keep_size.'
UNION ALL
SELECT
    'wal_status=unreserved requires investigation; wal_status=lost indicates the slot is no longer usable for normal continuation.'
UNION ALL
SELECT
    'Do not drop a replication slot until its consumer, ownership, recoverability, storage urgency, and authorization are known.'
UNION ALL
SELECT
    'Compare slot evidence with WAL generation rate, pg_wal capacity, standby health, maintenance windows, and documented recovery policy.';

\echo ''
\echo '======================================================================'
\echo '6.8 SAFE-READ lab complete'
\echo 'No replication slots or PostgreSQL configuration were changed.'
\echo '======================================================================'
