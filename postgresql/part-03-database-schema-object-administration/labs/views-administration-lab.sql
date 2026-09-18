-- ============================================================================
-- Part 3.8 — Views and View Administration
-- File: labs/views-administration-lab.sql
-- Classification: [LAB-ONLY — MUTATING — TRANSACTIONALLY CONTAINED]
-- Target: PostgreSQL 18
--
-- Run only in an authorized disposable, non-production database.
-- This script creates isolated objects and finishes with ROLLBACK.
-- Do not add COMMIT. Use a dedicated psql session.
-- Transactionally contained does not mean read-only or zero-cost.
-- This lab verifies definitions and catalog options, not cross-role security.
-- ============================================================================

\set ON_ERROR_STOP on
\pset pager off

\echo 'Part 3.8 — Views and View Administration lab'

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

SELECT to_regnamespace('tutorial_view_admin') IS NULL AS collision_free
\gset

\if :collision_free
    \echo 'Preflight passed: tutorial schema name is unused.'
\else
    \echo 'ERROR: tutorial_view_admin already exists.'
    \echo 'The lab will not reuse or remove an existing schema.'
    \quit 4
\endif

BEGIN;

SET LOCAL lock_timeout = '5s';
SET LOCAL statement_timeout = '2min';
SET LOCAL idle_in_transaction_session_timeout = '5min';

CREATE SCHEMA tutorial_view_admin;

CREATE TABLE tutorial_view_admin.patient_event (
    event_id bigint GENERATED ALWAYS AS IDENTITY,
    patient_reference text NOT NULL,
    status text NOT NULL,
    confidential_note text,
    CONSTRAINT patient_event_pk PRIMARY KEY (event_id),
    CONSTRAINT patient_event_status_check
        CHECK (status IN ('active', 'closed'))
);

INSERT INTO tutorial_view_admin.patient_event
    (patient_reference, status, confidential_note)
VALUES
    ('PAT-001', 'active', 'internal-a'),
    ('PAT-002', 'closed', 'internal-b'),
    ('PAT-003', 'active', 'internal-c');

CREATE VIEW tutorial_view_admin.active_patient_event AS
SELECT
    event_id,
    patient_reference,
    status
FROM tutorial_view_admin.patient_event
WHERE status = 'active'
WITH LOCAL CHECK OPTION;

SELECT count(*) = 2 AS initial_view_rows_correct
FROM tutorial_view_admin.active_patient_event
\gset

\if :initial_view_rows_correct
    \echo 'PASS: filtered view returned the expected rows.'
\else
    \echo 'ERROR: filtered view returned unexpected rows.'
    \quit 5
\endif

\echo 'Prove the simple view is automatically updatable'
UPDATE tutorial_view_admin.active_patient_event
SET patient_reference = 'PAT-001-UPDATED'
WHERE patient_reference = 'PAT-001';

SELECT count(*) = 1 AS base_update_visible
FROM tutorial_view_admin.patient_event
WHERE patient_reference = 'PAT-001-UPDATED'
  AND status = 'active'
\gset

\if :base_update_visible
    \echo 'PASS: update through the view reached the base table.'
\else
    \echo 'ERROR: view update did not reach the base table.'
    \quit 6
\endif

INSERT INTO tutorial_view_admin.active_patient_event
    (patient_reference, status)
VALUES
    ('PAT-004', 'active');

SELECT count(*) = 1 AS view_insert_visible
FROM tutorial_view_admin.patient_event
WHERE patient_reference = 'PAT-004'
  AND status = 'active'
\gset

\if :view_insert_visible
    \echo 'PASS: insert through the view reached the base table.'
\else
    \echo 'ERROR: view insert did not reach the base table.'
    \quit 7
\endif

\echo 'Prove CHECK OPTION rejects rows outside the view predicate'
DO $lab$
BEGIN
    BEGIN
        INSERT INTO tutorial_view_admin.active_patient_event
            (patient_reference, status)
        VALUES
            ('MUST-FAIL', 'closed');
        RAISE EXCEPTION 'expected with_check_option_violation was not raised';
    EXCEPTION
        WHEN with_check_option_violation THEN
            RAISE NOTICE 'Expected with_check_option_violation observed';
    END;
END
$lab$;

SELECT count(*) = 0 AS rejected_row_absent
FROM tutorial_view_admin.patient_event
WHERE patient_reference = 'MUST-FAIL'
\gset

\if :rejected_row_absent
    \echo 'PASS: the CHECK OPTION rejection left no base-table row.'
\else
    \echo 'ERROR: the rejected row unexpectedly persisted.'
    \quit 8
\endif

CREATE VIEW tutorial_view_admin.patient_event_summary AS
SELECT
    status,
    count(*) AS event_count
FROM tutorial_view_admin.patient_event
GROUP BY status;

SELECT
    is_updatable = 'NO'
    AND is_insertable_into = 'NO'
        AS summary_is_read_only
FROM information_schema.views
WHERE table_schema = 'tutorial_view_admin'
  AND table_name = 'patient_event_summary'
\gset

\if :summary_is_read_only
    \echo 'PASS: aggregate view is reported as read-only.'
\else
    \echo 'ERROR: aggregate view updatability metadata is unexpected.'
    \quit 8
\endif

CREATE VIEW tutorial_view_admin.secure_patient_event
WITH (
    security_barrier = true,
    security_invoker = true
) AS
SELECT
    event_id,
    patient_reference,
    status
FROM tutorial_view_admin.patient_event
WHERE status = 'active';

SELECT
    c.reloptions @> ARRAY['security_barrier=true']::text[]
    AND c.reloptions @> ARRAY['security_invoker=true']::text[]
        AS security_options_correct
FROM pg_class AS c
JOIN pg_namespace AS n
  ON n.oid = c.relnamespace
WHERE n.nspname = 'tutorial_view_admin'
  AND c.relname = 'secure_patient_event'
  AND c.relkind = 'v'
\gset

\if :security_options_correct
    \echo 'PASS: security barrier and invoker options are recorded.'
\else
    \echo 'ERROR: expected view security options are missing.'
    \quit 9
\endif

CREATE VIEW tutorial_view_admin.active_patient_event_consumer AS
SELECT
    event_id,
    patient_reference,
    status
FROM tutorial_view_admin.active_patient_event;

\echo 'Append a compatible output column through CREATE OR REPLACE VIEW'
CREATE OR REPLACE VIEW tutorial_view_admin.active_patient_event AS
SELECT
    event_id,
    patient_reference,
    status,
    status = 'active' AS status_matches_filter
FROM tutorial_view_admin.patient_event
WHERE status = 'active'
WITH LOCAL CHECK OPTION;

SELECT
    count(*) = 4
    AND max(ordinal_position) = 4
        AS replacement_appended_column
FROM information_schema.columns
WHERE table_schema = 'tutorial_view_admin'
  AND table_name = 'active_patient_event'
\gset

\if :replacement_appended_column
    \echo 'PASS: replacement preserved existing columns and appended one.'
\else
    \echo 'ERROR: replacement view column contract is unexpected.'
    \quit 10
\endif

SELECT
    (SELECT count(*)
     FROM tutorial_view_admin.active_patient_event_consumer) = 3
    AND
    (SELECT count(*)
     FROM information_schema.columns
     WHERE table_schema = 'tutorial_view_admin'
       AND table_name = 'active_patient_event_consumer') = 3
        AS dependent_consumer_compatible
\gset

\if :dependent_consumer_compatible
    \echo 'PASS: dependent consumer retained three columns and expected rows.'
\else
    \echo 'ERROR: dependent consumer compatibility check failed.'
    \quit 11
\endif

SELECT
    check_option = 'LOCAL'
    AND is_updatable = 'YES'
        AS active_view_metadata_correct
FROM information_schema.views
WHERE table_schema = 'tutorial_view_admin'
  AND table_name = 'active_patient_event'
\gset

\if :active_view_metadata_correct
    \echo 'PASS: active view metadata reports LOCAL and updatable.'
\else
    \echo 'ERROR: active view metadata is unexpected.'
    \quit 11
\endif

\echo 'Prove RESTRICT protects a view with a dependent consumer view'
DO $lab$
BEGIN
    BEGIN
        DROP VIEW tutorial_view_admin.active_patient_event RESTRICT;
        RAISE EXCEPTION 'expected dependent_objects_still_exist was not raised';
    EXCEPTION
        WHEN dependent_objects_still_exist THEN
            RAISE NOTICE 'Expected dependent_objects_still_exist observed';
    END;
END
$lab$;

SELECT to_regclass('tutorial_view_admin.active_patient_event') IS NOT NULL
       AS restricted_view_preserved
\gset

\if :restricted_view_preserved
    \echo 'PASS: RESTRICT preserved the depended-on view.'
\else
    \echo 'ERROR: depended-on view was unexpectedly removed.'
    \quit 12
\endif

\echo 'Inspect portable view metadata'
SELECT
    table_schema,
    table_name,
    check_option,
    is_updatable,
    is_insertable_into,
    is_trigger_updatable
FROM information_schema.views
WHERE table_schema = 'tutorial_view_admin'
ORDER BY table_name;

\echo 'Inspect PostgreSQL view definitions'
SELECT
    schemaname,
    viewname,
    viewowner,
    definition
FROM pg_views
WHERE schemaname = 'tutorial_view_admin'
ORDER BY viewname;

SELECT count(*) = 4 AS expected_view_count
FROM pg_views
WHERE schemaname = 'tutorial_view_admin'
\gset

\if :expected_view_count
    \echo 'PASS: all four expected views exist.'
\else
    \echo 'ERROR: expected view inventory is incomplete.'
    \quit 13
\endif

ROLLBACK;

SELECT
    to_regnamespace('tutorial_view_admin') IS NULL
    AND to_regclass('tutorial_view_admin.patient_event') IS NULL
    AND to_regclass('tutorial_view_admin.active_patient_event') IS NULL
        AS rollback_cleanup_verified
\gset

\if :rollback_cleanup_verified
    \echo 'PASS: rollback removed the lab schema, table, and views.'
\else
    \echo 'ERROR: rollback cleanup verification failed.'
    \quit 14
\endif

\echo 'LAB COMPLETE — all assertions passed and no lab objects remain.'
