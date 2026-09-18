-- ============================================================================
-- Part 3.7 — ALTER TABLE and Safe Schema Evolution
-- File: labs/alter-table-evolution-lab.sql
-- Classification: [LAB-ONLY — MUTATING — TRANSACTIONALLY CONTAINED]
-- Target: PostgreSQL 18
--
-- Run only in an authorized disposable, non-production database.
-- This script creates isolated objects and finishes with ROLLBACK.
-- Do not add COMMIT. Use a dedicated psql session.
-- Transactionally contained does not mean read-only or zero-cost.
-- ============================================================================

\set ON_ERROR_STOP on
\pset pager off

\echo 'Part 3.7 — ALTER TABLE and Safe Schema Evolution lab'

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

SELECT to_regnamespace('tutorial_alter_admin') IS NULL AS collision_free
\gset

\if :collision_free
    \echo 'Preflight passed: tutorial schema name is unused.'
\else
    \echo 'ERROR: tutorial_alter_admin already exists.'
    \echo 'The lab will not reuse or remove an existing schema.'
    \quit 4
\endif

BEGIN;

SET LOCAL lock_timeout = '5s';
SET LOCAL statement_timeout = '2min';
SET LOCAL idle_in_transaction_session_timeout = '5min';

CREATE SCHEMA tutorial_alter_admin;

CREATE TABLE tutorial_alter_admin.patient_activity (
    activity_id bigint GENERATED ALWAYS AS IDENTITY,
    patient_ref varchar(20) NOT NULL,
    event_count integer,
    legacy_note text,
    CONSTRAINT patient_activity_pk PRIMARY KEY (activity_id)
);

INSERT INTO tutorial_alter_admin.patient_activity
    (patient_ref, event_count, legacy_note)
VALUES
    ('PAT-001', 2, 'remove later'),
    ('PAT-002', 0, 'remove later'),
    ('PAT-003', 4, 'remove later');

\echo 'Stage 1 — add a nullable column and a future-row default'
ALTER TABLE tutorial_alter_admin.patient_activity
ADD COLUMN source_system text;

ALTER TABLE tutorial_alter_admin.patient_activity
ALTER COLUMN source_system SET DEFAULT 'application';

INSERT INTO tutorial_alter_admin.patient_activity
    (patient_ref, event_count)
VALUES
    ('PAT-004', 1)
RETURNING source_system = 'application' AS future_default_applied
\gset

\if :future_default_applied
    \echo 'PASS: future insert received the new default.'
\else
    \echo 'ERROR: future insert did not receive the new default.'
    \quit 5
\endif

SELECT count(*) FILTER (WHERE source_system IS NULL) = 3
       AS historical_rows_not_backfilled
FROM tutorial_alter_admin.patient_activity
\gset

\if :historical_rows_not_backfilled
    \echo 'PASS: setting a default did not backfill historical rows.'
\else
    \echo 'ERROR: unexpected historical source_system state.'
    \quit 6
\endif

\echo 'Stage 2 — backfill historical rows explicitly'
UPDATE tutorial_alter_admin.patient_activity
SET source_system = 'legacy'
WHERE source_system IS NULL;

SELECT count(*) FILTER (WHERE source_system IS NULL) = 0
       AS backfill_complete
FROM tutorial_alter_admin.patient_activity
\gset

\if :backfill_complete
    \echo 'PASS: explicit backfill completed.'
\else
    \echo 'ERROR: explicit backfill is incomplete.'
    \quit 7
\endif

\echo 'Stage 3 — add and validate a proof constraint'
ALTER TABLE tutorial_alter_admin.patient_activity
ADD CONSTRAINT patient_activity_source_nn_check
CHECK (source_system IS NOT NULL) NOT VALID;

\echo 'Prove NOT VALID still enforces the check for new writes'
DO $lab$
BEGIN
    BEGIN
        INSERT INTO tutorial_alter_admin.patient_activity
            (patient_ref, event_count, source_system)
        VALUES
            ('MUST-FAIL', 1, NULL);
        RAISE EXCEPTION 'expected check_violation was not raised';
    EXCEPTION
        WHEN check_violation THEN
            RAISE NOTICE 'Expected check_violation observed';
    END;
END
$lab$;

SELECT NOT convalidated AS constraint_initially_not_valid
FROM pg_constraint
WHERE conrelid = 'tutorial_alter_admin.patient_activity'::regclass
  AND conname = 'patient_activity_source_nn_check'
\gset

\if :constraint_initially_not_valid
    \echo 'PASS: proof constraint began as NOT VALID.'
\else
    \echo 'ERROR: proof constraint validation state is unexpected.'
    \quit 8
\endif

ALTER TABLE tutorial_alter_admin.patient_activity
VALIDATE CONSTRAINT patient_activity_source_nn_check;

SELECT convalidated AS constraint_now_valid
FROM pg_constraint
WHERE conrelid = 'tutorial_alter_admin.patient_activity'::regclass
  AND conname = 'patient_activity_source_nn_check'
\gset

\if :constraint_now_valid
    \echo 'PASS: proof constraint validated successfully.'
\else
    \echo 'ERROR: proof constraint did not validate.'
    \quit 9
\endif

ALTER TABLE tutorial_alter_admin.patient_activity
ALTER COLUMN source_system SET NOT NULL;

ALTER TABLE tutorial_alter_admin.patient_activity
DROP CONSTRAINT patient_activity_source_nn_check;

SELECT a.attnotnull AS source_system_not_null
FROM pg_attribute AS a
WHERE a.attrelid = 'tutorial_alter_admin.patient_activity'::regclass
  AND a.attname = 'source_system'
  AND NOT a.attisdropped
\gset

\if :source_system_not_null
    \echo 'PASS: source_system is now NOT NULL.'
\else
    \echo 'ERROR: source_system is not marked NOT NULL.'
    \quit 10
\endif

\echo 'Stage 4 — apply a compatible varchar-to-text type change and rename'
ALTER TABLE tutorial_alter_admin.patient_activity
ALTER COLUMN patient_ref TYPE text;

ALTER TABLE tutorial_alter_admin.patient_activity
RENAME COLUMN patient_ref TO patient_reference;

SELECT
    data_type = 'text'
    AND column_name = 'patient_reference'
        AS type_and_name_correct
FROM information_schema.columns
WHERE table_schema = 'tutorial_alter_admin'
  AND table_name = 'patient_activity'
  AND column_name = 'patient_reference'
\gset

\if :type_and_name_correct
    \echo 'PASS: type and column name evolved as expected.'
\else
    \echo 'ERROR: type or column-name evolution failed.'
    \quit 11
\endif

\echo 'Stage 5 — remove an isolated obsolete column with RESTRICT semantics'
ALTER TABLE tutorial_alter_admin.patient_activity
DROP COLUMN legacy_note RESTRICT;

SELECT NOT EXISTS (
    SELECT 1
    FROM information_schema.columns
    WHERE table_schema = 'tutorial_alter_admin'
      AND table_name = 'patient_activity'
      AND column_name = 'legacy_note'
) AS obsolete_column_removed
\gset

\if :obsolete_column_removed
    \echo 'PASS: isolated obsolete column was removed.'
\else
    \echo 'ERROR: obsolete column still exists.'
    \quit 12
\endif

SELECT column_default = '''application''::text'
       AS source_system_default_retained
FROM information_schema.columns
WHERE table_schema = 'tutorial_alter_admin'
  AND table_name = 'patient_activity'
  AND column_name = 'source_system'
\gset

\if :source_system_default_retained
    \echo 'PASS: source_system retained the intended catalog default.'
\else
    \echo 'ERROR: source_system catalog default is missing or unexpected.'
    \quit 13
\endif

\echo 'Acceptance state before rollback'
SELECT
    activity_id,
    patient_reference,
    event_count,
    source_system
FROM tutorial_alter_admin.patient_activity
ORDER BY activity_id;

SELECT
    count(*) = 4
    AND count(*) FILTER (WHERE source_system = 'legacy') = 3
    AND count(*) FILTER (WHERE source_system = 'application') = 1
        AS final_row_state_correct
FROM tutorial_alter_admin.patient_activity
\gset

\if :final_row_state_correct
    \echo 'PASS: final row state is correct.'
\else
    \echo 'ERROR: final row state is incorrect.'
    \quit 14
\endif

ROLLBACK;

SELECT
    to_regnamespace('tutorial_alter_admin') IS NULL
    AND to_regclass('tutorial_alter_admin.patient_activity') IS NULL
        AS rollback_cleanup_verified
\gset

\if :rollback_cleanup_verified
    \echo 'PASS: rollback removed the lab schema and table.'
\else
    \echo 'ERROR: rollback cleanup verification failed.'
    \quit 15
\endif

\echo 'LAB COMPLETE — all assertions passed and no lab objects remain.'
