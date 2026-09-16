-- labs/crud-check.sql
-- [TUTORIAL-ACCEPTANCE — SAFE-READ]
--
-- Part 1.8 — INSERT, SELECT, UPDATE & DELETE
-- Read-only acceptance validation.
--
-- This script intentionally contains:
--   NO INSERT
--   NO UPDATE
--   NO DELETE
--   NO TRUNCATE
--   NO DDL
--
-- It validates the tutorial objects and synthetic CRUD lab state
-- without changing database data.

-- 1. Confirm execution context.
SELECT
    current_database() AS current_database,
    current_user       AS current_user;

-- 2. Confirm the tutorial table exists.
SELECT
    table_schema,
    table_name
FROM information_schema.tables
WHERE table_schema = 'clinical'
  AND table_name = 'patient';

-- 3. Confirm expected core columns exist.
SELECT
    column_name,
    data_type,
    is_nullable
FROM information_schema.columns
WHERE table_schema = 'clinical'
  AND table_name = 'patient'
  AND column_name IN (
      'patient_id',
      'first_name',
      'last_name',
      'date_of_birth'
  )
ORDER BY ordinal_position;

-- 4. Read-only row count.
SELECT
    COUNT(*) AS patient_row_count
FROM clinical.patient;

-- 5. Inspect only the synthetic rows used by this tutorial.
SELECT
    patient_id,
    first_name,
    last_name,
    date_of_birth
FROM clinical.patient
WHERE
       (first_name = 'Avery'  AND last_name = 'Taylor')
    OR (first_name = 'Jordan' AND last_name = 'Lee')
    OR (first_name = 'Morgan' AND last_name = 'Rivera')
ORDER BY patient_id;

-- 6. Detect whether the rollback-only UPDATE value was accidentally persisted.
SELECT
    COUNT(*) AS unexpected_update_rows
FROM clinical.patient
WHERE last_name = 'Taylor-Lab';

-- Expected: unexpected_update_rows = 0

-- 7. Final read-only verification.
SELECT
    patient_id,
    first_name,
    last_name
FROM clinical.patient
ORDER BY patient_id
LIMIT 20;

-- [TUTORIAL-ACCEPTANCE — SAFE-READ]
-- End of read-only validation.
