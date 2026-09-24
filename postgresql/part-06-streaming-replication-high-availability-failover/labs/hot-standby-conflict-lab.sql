\set ON_ERROR_STOP on

/*
 PostgreSQL Part 6.9 — Standbys and Conflict Management
 Locked lab: hot-standby-conflict-lab.sql
 Classification: LAB-WRITE

 Dedicated lab primary + physical standby only.

 This script defaults to OBSERVE mode. Writable actions must be explicitly
 requested with:
   -v lab_role=primary -v lab_action=setup
   -v lab_role=primary -v lab_action=mutate
   -v lab_role=primary -v lab_action=cleanup

 Standby evidence:
   -v lab_role=standby

 Only schema pg_ha_conflict_lab is created/modified.
*/

\if :{?lab_role}
\else
  \set lab_role observe
\endif

\if :{?lab_action}
\else
  \set lab_action observe
\endif

\echo '======================================================================'
\echo '6.9 - Hot Standby Conflict Lab'
\echo 'LAB-WRITE'
\echo 'Role  :' :lab_role
\echo 'Action:' :lab_action
\echo '======================================================================'

\echo '[1/7] Server identity and role'
SELECT current_database() AS database_name,
       current_user AS current_user,
       inet_server_addr() AS server_address,
       inet_server_port() AS server_port,
       pg_is_in_recovery() AS is_in_recovery,
       version() AS postgres_version;

\echo '[2/7] Relevant settings'
SELECT name, setting, unit, source, pending_restart
FROM pg_settings
WHERE name IN (
  'hot_standby',
  'hot_standby_feedback',
  'max_standby_streaming_delay',
  'max_standby_archive_delay',
  'log_recovery_conflict_waits'
)
ORDER BY name;

\echo '[3/7] Recovery conflict counters'
SELECT datname,
       confl_tablespace,
       confl_lock,
       confl_snapshot,
       confl_bufferpin,
       confl_deadlock
FROM pg_stat_database_conflicts
ORDER BY datname;

\echo '[4/7] WAL receive/replay evidence'
SELECT pg_is_in_recovery() AS is_in_recovery,
       CASE WHEN pg_is_in_recovery() THEN pg_last_wal_receive_lsn() END AS last_receive_lsn,
       CASE WHEN pg_is_in_recovery() THEN pg_last_wal_replay_lsn() END AS last_replay_lsn,
       CASE WHEN pg_is_in_recovery() THEN pg_last_xact_replay_timestamp() END AS last_replay_timestamp;

\echo '[5/7] Active non-idle sessions'
SELECT pid,
       usename,
       application_name,
       state,
       query_start,
       now() - query_start AS query_runtime,
       wait_event_type,
       wait_event,
       left(query,160) AS query
FROM pg_stat_activity
WHERE state <> 'idle'
  AND pid <> pg_backend_pid()
ORDER BY query_start;

\echo '[6/7] Controlled lab action'

\if :'lab_role' = 'primary'

  SELECT CASE WHEN pg_is_in_recovery()
    THEN 'WARNING: PRIMARY requested but server is in recovery'
    ELSE 'PASS: verified writable primary'
  END AS topology_check;

  \if :'lab_action' = 'setup'
    DO $$
    BEGIN
      IF pg_is_in_recovery() THEN
        RAISE EXCEPTION 'Safety stop: setup requested on standby';
      END IF;
    END $$;

    CREATE SCHEMA IF NOT EXISTS pg_ha_conflict_lab;
    CREATE TABLE IF NOT EXISTS pg_ha_conflict_lab.conflict_demo (
      id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
      payload text NOT NULL,
      created_at timestamptz NOT NULL DEFAULT clock_timestamp()
    );

    TRUNCATE pg_ha_conflict_lab.conflict_demo RESTART IDENTITY;

    INSERT INTO pg_ha_conflict_lab.conflict_demo(payload)
    SELECT repeat(md5(g::text),4)
    FROM generate_series(1,10000) AS g;

    ANALYZE pg_ha_conflict_lab.conflict_demo;

    SELECT count(*) AS primary_lab_rows
    FROM pg_ha_conflict_lab.conflict_demo;

    SELECT pg_current_wal_lsn() AS primary_wal_lsn_after_setup;

    \echo 'PRIMARY setup complete. Wait for standby replay before continuing.'

  \elif :'lab_action' = 'mutate'
    DO $$
    BEGIN
      IF pg_is_in_recovery() THEN
        RAISE EXCEPTION 'Safety stop: mutation requested on standby';
      END IF;
      IF to_regclass('pg_ha_conflict_lab.conflict_demo') IS NULL THEN
        RAISE EXCEPTION 'Lab table missing; run setup first';
      END IF;
    END $$;

    UPDATE pg_ha_conflict_lab.conflict_demo
       SET payload = payload || '-updated'
     WHERE id <= 5000;

    DELETE FROM pg_ha_conflict_lab.conflict_demo
     WHERE id > 5000;

    -- Deliberately restricted to the dedicated lab table.
    VACUUM (VERBOSE, ANALYZE) pg_ha_conflict_lab.conflict_demo;

    SELECT count(*) AS primary_rows_after_mutation
    FROM pg_ha_conflict_lab.conflict_demo;

    SELECT pg_current_wal_lsn() AS primary_wal_lsn_after_mutation;

    \echo 'PRIMARY mutation complete. Inspect the standby evidence.'

  \elif :'lab_action' = 'cleanup'
    DO $$
    BEGIN
      IF pg_is_in_recovery() THEN
        RAISE EXCEPTION 'Safety stop: cleanup requested on standby';
      END IF;
    END $$;

    DROP SCHEMA IF EXISTS pg_ha_conflict_lab CASCADE;
    \echo 'PRIMARY cleanup complete.'

  \else
    \echo 'PRIMARY observe mode: no writes performed.'
  \endif

\elif :'lab_role' = 'standby'

  SELECT CASE WHEN pg_is_in_recovery()
    THEN 'PASS: verified standby'
    ELSE 'WARNING: STANDBY requested but server is not in recovery'
  END AS topology_check;

  \echo 'STANDBY evidence mode: no writes performed.'
  \echo 'After primary setup has replayed, verify:'
  \echo '  SELECT count(*) FROM pg_ha_conflict_lab.conflict_demo;'
  \echo ''
  \echo 'In a separate standby psql session:'
  \echo '  BEGIN TRANSACTION ISOLATION LEVEL REPEATABLE READ READ ONLY;'
  \echo '  SELECT count(*) FROM pg_ha_conflict_lab.conflict_demo;'
  \echo ''
  \echo 'Keep the transaction open while PRIMARY runs lab_action=mutate.'
  \echo 'Then repeat the SELECT and observe recovery/conflict behavior.'
  \echo 'Finish with ROLLBACK.'
  \echo ''
  \echo 'Conflict reproduction is timing-dependent.'
  \echo 'No cancellation is a valid INFO result.'

\else
  \echo 'OBSERVE mode: no role selected and no writes performed.'
\endif

\echo '[7/7] Result semantics'
SELECT 'PASS' AS class,
       'Expected recovery/conflict evidence observed.' AS meaning
UNION ALL
SELECT 'INFO',
       'Controlled experiment completed but no conflict occurred.'
UNION ALL
SELECT 'WARNING',
       'Topology, settings, role, or execution context is unsuitable.'
UNION ALL
SELECT 'UNKNOWN',
       'Evidence is insufficient to determine the outcome.';

\echo 'Safety reminders:'
\echo '- Do not change standby delay settings just to force a conflict.'
\echo '- Do not disable autovacuum globally.'
\echo '- Do not manipulate replication slots or WAL.'
\echo '- Do not modify application tables.'
\echo '- Run cleanup only on the verified lab primary.'
\echo '======================================================================'
\echo '6.9 lab execution complete.'
\echo '======================================================================'
