-- ============================================================================
-- Part 3.4 — Constraints and Data Integrity
-- File: labs/constraints-integrity-lab.sql
-- Classification: [LAB-ONLY — MUTATING — TRANSACTIONALLY CONTAINED]
-- Target: PostgreSQL 18
--
-- Run only in an authorized disposable, non-production database.
-- This script creates isolated tutorial objects and finishes with ROLLBACK.
-- Do not add COMMIT. Use a dedicated psql session.
-- ============================================================================

\set ON_ERROR_STOP on
\pset pager off

\echo 'Part 3.4 — Constraints and Data Integrity lab'

\if :{?lab_confirm}
\else
    \echo 'ERROR: explicit acknowledgement is required.'
    \echo 'Run with: -v lab_confirm=I_UNDERSTAND'
    \quit 3
\endif

SELECT :'lab_confirm' = 'I_UNDERSTAND' AS lab_confirmed \gset
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

SELECT
    to_regnamespace('tutorial_integrity') IS NULL
    AND to_regclass('tutorial_integrity.patient') IS NULL
    AND to_regclass('tutorial_integrity.patient_activity') IS NULL
        AS collision_free
\gset

\if :collision_free
    \echo 'Preflight passed: tutorial object names are unused.'
\else
    \echo 'ERROR: tutorial_integrity or a lab relation already exists.'
    \echo 'The lab will not reuse or remove existing objects.'
    \quit 4
\endif

BEGIN;

SET LOCAL lock_timeout = '5s';
SET LOCAL statement_timeout = '2min';
SET LOCAL idle_in_transaction_session_timeout = '5min';

CREATE SCHEMA tutorial_integrity;

CREATE TABLE tutorial_integrity.patient (
    patient_id bigint
        CONSTRAINT patient_pk PRIMARY KEY,
    source_system text
        CONSTRAINT patient_source_nn NOT NULL,
    external_reference text,
    CONSTRAINT patient_source_external_uq
        UNIQUE NULLS NOT DISTINCT (source_system, external_reference)
);

CREATE TABLE tutorial_integrity.patient_activity (
    activity_id bigint
        CONSTRAINT patient_activity_pk PRIMARY KEY,
    patient_id bigint
        CONSTRAINT patient_activity_patient_nn NOT NULL,
    activity_type text
        CONSTRAINT patient_activity_type_nn NOT NULL,
    occurred_at timestamptz
        CONSTRAINT patient_activity_occurred_nn NOT NULL,
    completed_at timestamptz,
    CONSTRAINT patient_activity_type_ck
        CHECK (activity_type IN ('ENCOUNTER', 'CLAIM', 'LAB')),
    CONSTRAINT patient_activity_time_ck
        CHECK (completed_at IS NULL OR completed_at >= occurred_at),
    CONSTRAINT patient_activity_patient_fk
        FOREIGN KEY (patient_id)
        REFERENCES tutorial_integrity.patient (patient_id)
        ON UPDATE RESTRICT
        ON DELETE CASCADE
);

CREATE INDEX patient_activity_patient_id_idx
ON tutorial_integrity.patient_activity (patient_id);

INSERT INTO tutorial_integrity.patient
    (patient_id, source_system, external_reference)
VALUES
    (1, 'LAB', 'PATIENT-001'),
    (2, 'LAB', 'PATIENT-002'),
    (3, 'LAB', NULL);

INSERT INTO tutorial_integrity.patient_activity
    (activity_id, patient_id, activity_type, occurred_at, completed_at)
VALUES
    (101, 1, 'ENCOUNTER', timestamptz '2026-01-01 10:00:00+00',
                           timestamptz '2026-01-01 11:00:00+00'),
    (102, 2, 'CLAIM',     timestamptz '2026-01-02 10:00:00+00', NULL);

\echo 'Expected failure 1 — duplicate primary key'
DO $lab$
BEGIN
    BEGIN
        INSERT INTO tutorial_integrity.patient
        VALUES (1, 'LAB', 'PATIENT-DUPLICATE');
        RAISE EXCEPTION 'expected unique_violation was not raised';
    EXCEPTION
        WHEN unique_violation THEN
            RAISE NOTICE 'Expected unique_violation observed';
    END;
END
$lab$;

\echo 'Expected failure 2 — NULLS NOT DISTINCT composite uniqueness'
DO $lab$
BEGIN
    BEGIN
        INSERT INTO tutorial_integrity.patient
        VALUES (4, 'LAB', NULL);
        RAISE EXCEPTION 'expected unique_violation was not raised';
    EXCEPTION
        WHEN unique_violation THEN
            RAISE NOTICE 'Expected NULLS NOT DISTINCT violation observed';
    END;
END
$lab$;

\echo 'Expected failure 3 — invalid CHECK value'
DO $lab$
BEGIN
    BEGIN
        INSERT INTO tutorial_integrity.patient_activity
        VALUES (103, 1, 'INVALID', clock_timestamp(), NULL);
        RAISE EXCEPTION 'expected check_violation was not raised';
    EXCEPTION
        WHEN check_violation THEN
            RAISE NOTICE 'Expected check_violation observed';
    END;
END
$lab$;

\echo 'Expected failure 4 — orphan foreign key'
DO $lab$
BEGIN
    BEGIN
        INSERT INTO tutorial_integrity.patient_activity
        VALUES (104, 999, 'LAB', clock_timestamp(), NULL);
        RAISE EXCEPTION 'expected foreign_key_violation was not raised';
    EXCEPTION
        WHEN foreign_key_violation THEN
            RAISE NOTICE 'Expected foreign_key_violation observed';
    END;
END
$lab$;

\echo 'Inspect constraint definitions and states'
SELECT
    n.nspname AS schema_name,
    c.relname AS table_name,
    con.conname AS constraint_name,
    con.contype,
    con.conenforced,
    con.convalidated,
    con.condeferrable,
    con.condeferred,
    con.conperiod,
    con.conindid,
    pg_get_constraintdef(con.oid, true) AS definition
FROM pg_constraint AS con
JOIN pg_class AS c ON c.oid = con.conrelid
JOIN pg_namespace AS n ON n.oid = c.relnamespace
WHERE n.nspname = 'tutorial_integrity'
ORDER BY c.relname, con.conname;

\echo 'Inspect indexes supporting integrity and access'
SELECT
    schemaname,
    tablename,
    indexname,
    indexdef
FROM pg_indexes
WHERE schemaname = 'tutorial_integrity'
ORDER BY tablename, indexname;

\echo 'Demonstrate approved lab-only ON DELETE CASCADE semantics'
DELETE FROM tutorial_integrity.patient
WHERE patient_id = 1;

SELECT count(*) AS remaining_child_rows_for_patient_1
FROM tutorial_integrity.patient_activity
WHERE patient_id = 1;

SELECT
    (SELECT count(*) FROM tutorial_integrity.patient) AS patient_rows,
    (SELECT count(*) FROM tutorial_integrity.patient_activity) AS activity_rows;

ROLLBACK;

SELECT
    to_regnamespace('tutorial_integrity') AS schema_after_rollback,
    to_regclass('tutorial_integrity.patient') AS patient_after_rollback,
    to_regclass('tutorial_integrity.patient_activity') AS activity_after_rollback;

\echo 'LAB COMPLETE — all three final values must be NULL.'
