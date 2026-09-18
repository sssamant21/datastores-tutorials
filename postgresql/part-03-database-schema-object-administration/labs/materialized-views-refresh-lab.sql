-- ============================================================================
-- Part 3.9 — Materialized Views and Refresh Operations
-- File: labs/materialized-views-refresh-lab.sql
-- Classification: [LAB-ONLY — MUTATING — TRANSACTIONALLY CONTAINED]
-- Target: PostgreSQL 18
--
-- Run only in an authorized disposable, non-production database.
-- This script creates isolated objects and finishes with ROLLBACK.
-- Do not add COMMIT. Use a dedicated psql session.
-- Transactionally contained does not mean read-only or zero-cost.
-- Rollback removes persistent catalog and data changes from this transaction.
-- It does not eliminate CPU, I/O, temporary-space, WAL, or locking impact.
-- REFRESH MATERIALIZED VIEW commands in this lab are real operations.
-- ============================================================================

\set ON_ERROR_STOP on
\pset pager off

\echo 'Part 3.9 — Materialized Views and Refresh Operations lab'

\if :{?lab_confirm}
\else
    \echo 'ERROR: explicit acknowledgement is required.'
    \echo 'Run with: -v lab_confirm=I_UNDERSTAND'
    \quit 3
\endif

SELECT :'lab_confirm' = 'I_UNDERSTAND' AS lab_confirmed
\gset

\if :lab_confirmed
\else
    \echo 'ERROR: lab_confirm must equal I_UNDERSTAND.'
    \quit 3
\endif

SELECT
    current_database() AS database_name,
    current_user AS current_user,
    inet_server_addr() AS server_address,
    inet_server_port() AS server_port,
    pg_is_in_recovery() AS in_recovery;

SELECT NOT pg_is_in_recovery() AS writable_primary
\gset

\if :writable_primary
    \echo 'Preflight passed: server is not in recovery.'
\else
    \echo 'ERROR: this mutating lab must not run on a recovery server.'
    \quit 4
\endif

SELECT to_regnamespace('tutorial_matview_admin') IS NULL AS collision_free
\gset

\if :collision_free
    \echo 'Preflight passed: tutorial schema name is unused.'
\else
    \echo 'ERROR: tutorial_matview_admin already exists.'
    \echo 'The lab will not reuse or remove an existing schema.'
    \quit 5
\endif

BEGIN;

SET LOCAL lock_timeout = '5s';
SET LOCAL statement_timeout = '2min';
SET LOCAL idle_in_transaction_session_timeout = '5min';

CREATE SCHEMA tutorial_matview_admin;

CREATE TABLE tutorial_matview_admin.patient_event (
    event_id bigint GENERATED ALWAYS AS IDENTITY,
    patient_reference text NOT NULL,
    status text NOT NULL,
    occurred_on date NOT NULL,
    CONSTRAINT patient_event_pk PRIMARY KEY (event_id),
    CONSTRAINT patient_event_status_check
        CHECK (status IN ('active', 'closed'))
);

INSERT INTO tutorial_matview_admin.patient_event
    (patient_reference, status, occurred_on)
VALUES
    ('PAT-001', 'active', DATE '2026-01-10'),
    ('PAT-002', 'active', DATE '2026-01-10'),
    ('PAT-003', 'closed', DATE '2026-01-10'),
    ('PAT-004', 'active', DATE '2026-01-11');

CREATE MATERIALIZED VIEW tutorial_matview_admin.daily_event_summary AS
SELECT
    occurred_on AS event_day,
    status,
    count(*)::bigint AS event_count
FROM tutorial_matview_admin.patient_event
GROUP BY occurred_on, status
WITH DATA;

SELECT
    ispopulated
    AND hasindexes = false
        AS initial_metadata_correct
FROM pg_matviews
WHERE schemaname = 'tutorial_matview_admin'
  AND matviewname = 'daily_event_summary'
\gset

\if :initial_metadata_correct
    \echo 'PASS: materialized view is populated and initially has no index.'
\else
    \echo 'ERROR: initial materialized-view metadata is unexpected.'
    \quit 5
\endif

SELECT
    count(*) = 3
    AND sum(event_count) = 4
        AS initial_summary_correct
FROM tutorial_matview_admin.daily_event_summary
\gset

\if :initial_summary_correct
    \echo 'PASS: initial stored result is correct.'
\else
    \echo 'ERROR: initial stored result is incorrect.'
    \quit 6
\endif

CREATE UNIQUE INDEX daily_event_summary_refresh_uidx
ON tutorial_matview_admin.daily_event_summary (event_day, status);

SELECT
    i.indisunique
    AND i.indisvalid
    AND i.indisready
    AND i.indimmediate
    AND i.indpred IS NULL
    AND i.indexprs IS NULL
        AS qualifying_unique_index
FROM pg_index AS i
JOIN pg_class AS idx
  ON idx.oid = i.indexrelid
JOIN pg_class AS mv
  ON mv.oid = i.indrelid
JOIN pg_namespace AS n
  ON n.oid = mv.relnamespace
WHERE n.nspname = 'tutorial_matview_admin'
  AND mv.relname = 'daily_event_summary'
  AND idx.relname = 'daily_event_summary_refresh_uidx'
\gset

\if :qualifying_unique_index
    \echo 'PASS: qualifying unique index exists for concurrent refresh.'
\else
    \echo 'ERROR: concurrent-refresh unique index is not valid.'
    \quit 7
\endif

INSERT INTO tutorial_matview_admin.patient_event
    (patient_reference, status, occurred_on)
VALUES
    ('PAT-005', 'active', DATE '2026-01-10');

SELECT event_count = 2 AS stored_result_is_stale
FROM tutorial_matview_admin.daily_event_summary
WHERE event_day = DATE '2026-01-10'
  AND status = 'active'
\gset

\if :stored_result_is_stale
    \echo 'PASS: base-table change did not automatically update stored rows.'
\else
    \echo 'ERROR: expected stale stored result was not observed.'
    \quit 8
\endif

REFRESH MATERIALIZED VIEW tutorial_matview_admin.daily_event_summary;

SELECT event_count = 3 AS ordinary_refresh_visible
FROM tutorial_matview_admin.daily_event_summary
WHERE event_day = DATE '2026-01-10'
  AND status = 'active'
\gset

\if :ordinary_refresh_visible
    \echo 'PASS: ordinary refresh replaced the stored result.'
\else
    \echo 'ERROR: ordinary refresh result is incorrect.'
    \quit 9
\endif

INSERT INTO tutorial_matview_admin.patient_event
    (patient_reference, status, occurred_on)
VALUES
    ('PAT-006', 'closed', DATE '2026-01-11');

REFRESH MATERIALIZED VIEW CONCURRENTLY
    tutorial_matview_admin.daily_event_summary;

SELECT event_count = 1 AS concurrent_refresh_visible
FROM tutorial_matview_admin.daily_event_summary
WHERE event_day = DATE '2026-01-11'
  AND status = 'closed'
\gset

\if :concurrent_refresh_visible
    \echo 'PASS: concurrent refresh produced the expected stored result.'
\else
    \echo 'ERROR: concurrent refresh result is incorrect.'
    \quit 10
\endif

CREATE MATERIALIZED VIEW tutorial_matview_admin.unpopulated_summary AS
SELECT
    status,
    count(*)::bigint AS event_count
FROM tutorial_matview_admin.patient_event
GROUP BY status
WITH NO DATA;

SELECT NOT ispopulated AS created_unpopulated
FROM pg_matviews
WHERE schemaname = 'tutorial_matview_admin'
  AND matviewname = 'unpopulated_summary'
\gset

\if :created_unpopulated
    \echo 'PASS: WITH NO DATA created an unpopulated materialized view.'
\else
    \echo 'ERROR: expected unpopulated state was not recorded.'
    \quit 11
\endif

DO $lab$
BEGIN
    BEGIN
        EXECUTE 'SELECT count(*) FROM tutorial_matview_admin.unpopulated_summary';
        RAISE EXCEPTION 'expected object_not_in_prerequisite_state was not raised';
    EXCEPTION
        WHEN object_not_in_prerequisite_state THEN
            RAISE NOTICE 'Expected unpopulated materialized-view error observed';
    END;
END
$lab$;

REFRESH MATERIALIZED VIEW tutorial_matview_admin.unpopulated_summary;

SELECT
    m.ispopulated
    AND (SELECT sum(event_count)
         FROM tutorial_matview_admin.unpopulated_summary) = 6
        AS population_refresh_correct
FROM pg_matviews AS m
WHERE m.schemaname = 'tutorial_matview_admin'
  AND m.matviewname = 'unpopulated_summary'
\gset

\if :population_refresh_correct
    \echo 'PASS: refresh populated and made the second object scannable.'
\else
    \echo 'ERROR: population refresh did not produce the expected result.'
    \quit 12
\endif

\echo 'Materialized-view inventory'
SELECT
    schemaname,
    matviewname,
    matviewowner,
    hasindexes,
    ispopulated
FROM pg_matviews
WHERE schemaname = 'tutorial_matview_admin'
ORDER BY matviewname;

\echo 'Materialized-view indexes'
SELECT
    schemaname,
    tablename,
    indexname,
    indexdef
FROM pg_indexes
WHERE schemaname = 'tutorial_matview_admin'
ORDER BY tablename, indexname;

\echo 'Materialized-view sizes'
SELECT
    c.relname AS materialized_view,
    pg_relation_size(c.oid) AS relation_bytes,
    pg_indexes_size(c.oid) AS index_bytes,
    pg_total_relation_size(c.oid) AS total_bytes
FROM pg_class AS c
JOIN pg_namespace AS n
  ON n.oid = c.relnamespace
WHERE n.nspname = 'tutorial_matview_admin'
  AND c.relkind = 'm'
ORDER BY c.relname;

ROLLBACK;

SELECT
    to_regnamespace('tutorial_matview_admin') IS NULL
    AND to_regclass(
        'tutorial_matview_admin.daily_event_summary'
    ) IS NULL
    AND to_regclass(
        'tutorial_matview_admin.unpopulated_summary'
    ) IS NULL
        AS rollback_cleanup_complete
\gset

\if :rollback_cleanup_complete
    \echo 'PASS: rollback removed all lab objects.'
\else
    \echo 'ERROR: rollback cleanup verification failed.'
    \quit 13
\endif

\echo 'Part 3.9 lab complete.'
