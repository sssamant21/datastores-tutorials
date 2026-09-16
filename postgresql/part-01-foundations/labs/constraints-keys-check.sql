-- labs/constraints-keys-check.sql
-- [TUTORIAL-ACCEPTANCE — SAFE-READ]
-- Part 1.10 — Constraints and Keys
-- PostgreSQL 18
-- READ ONLY: no INSERT, UPDATE, DELETE, TRUNCATE, ALTER, CREATE, or DROP.

-- 1. Confirm execution context.
SELECT
    current_database() AS current_database,
    current_user       AS current_user;

-- 2. Confirm both tutorial tables exist.
SELECT
    table_schema,
    table_name
FROM information_schema.tables
WHERE table_schema = 'clinical'
  AND table_name IN ('constraint_patient', 'constraint_visit')
ORDER BY table_name;

-- 3. Inspect constraints through information_schema.
SELECT
    table_schema,
    table_name,
    constraint_name,
    constraint_type,
    is_deferrable,
    initially_deferred,
    enforced
FROM information_schema.table_constraints
WHERE table_schema = 'clinical'
  AND table_name IN ('constraint_patient', 'constraint_visit')
ORDER BY table_name, constraint_type, constraint_name;

-- 4. PostgreSQL 18 catalog-level validation.
SELECT
    n.nspname AS schema_name,
    c.relname AS table_name,
    con.conname AS constraint_name,
    con.contype AS constraint_type,
    con.condeferrable,
    con.condeferred,
    con.conenforced,
    pg_get_constraintdef(con.oid) AS definition
FROM pg_constraint AS con
JOIN pg_class AS c ON c.oid = con.conrelid
JOIN pg_namespace AS n ON n.oid = c.relnamespace
WHERE n.nspname = 'clinical'
  AND c.relname IN ('constraint_patient', 'constraint_visit')
ORDER BY c.relname, con.conname;

-- 5. Inspect indexes.
SELECT
    schemaname,
    tablename,
    indexname,
    indexdef
FROM pg_indexes
WHERE schemaname = 'clinical'
  AND tablename IN ('constraint_patient', 'constraint_visit')
ORDER BY tablename, indexname;

-- 6. Confirm synthetic parent records.
SELECT
    patient_id,
    patient_code,
    age_years,
    status,
    created_at
FROM clinical.constraint_patient
WHERE patient_code LIKE 'LAB-%'
ORDER BY patient_code;

-- 7. Confirm synthetic parent/child relationship.
SELECT
    p.patient_code,
    v.visit_id,
    v.visit_sequence,
    v.visit_type,
    v.visit_at
FROM clinical.constraint_patient AS p
JOIN clinical.constraint_visit AS v
    ON v.patient_id = p.patient_id
WHERE p.patient_code LIKE 'LAB-%'
ORDER BY p.patient_code, v.visit_sequence;

-- 8. Verify that no orphan child rows exist.
SELECT COUNT(*) AS orphan_visit_count
FROM clinical.constraint_visit AS v
LEFT JOIN clinical.constraint_patient AS p
    ON p.patient_id = v.patient_id
WHERE p.patient_id IS NULL;
-- Expected: orphan_visit_count = 0

-- 9. Verify tutorial business-key uniqueness.
SELECT
    patient_code,
    COUNT(*) AS row_count
FROM clinical.constraint_patient
WHERE patient_code LIKE 'LAB-%'
GROUP BY patient_code
HAVING COUNT(*) > 1;
-- Expected: 0 rows

-- 10. Verify composite visit uniqueness.
SELECT
    patient_id,
    visit_sequence,
    COUNT(*) AS row_count
FROM clinical.constraint_visit
GROUP BY patient_id, visit_sequence
HAVING COUNT(*) > 1;
-- Expected: 0 rows

-- 11. Verify CHECK-compatible patient data.
SELECT
    patient_id,
    patient_code,
    age_years,
    status
FROM clinical.constraint_patient
WHERE
       (age_years IS NOT NULL AND age_years NOT BETWEEN 0 AND 130)
    OR status NOT IN ('ACTIVE', 'INACTIVE');
-- Expected: 0 rows

-- 12. Verify CHECK-compatible visit data.
SELECT
    visit_id,
    visit_sequence,
    visit_type
FROM clinical.constraint_visit
WHERE
       visit_sequence <= 0
    OR visit_type NOT IN ('ROUTINE', 'FOLLOW_UP', 'URGENT');
-- Expected: 0 rows

-- [TUTORIAL-ACCEPTANCE — SAFE-READ]
-- PASS when:
--   constraint_patient exists
--   constraint_visit exists
--   expected constraints are visible
--   PostgreSQL 18 pg_constraint metadata is readable
--   PK/UNIQUE indexes are visible
--   idx_constraint_visit_patient_id is visible
--   synthetic relationship is valid
--   orphan_visit_count = 0
--   duplicate patient-code query returns 0 rows
--   duplicate visit-sequence query returns 0 rows
--   invalid patient CHECK query returns 0 rows
--   invalid visit CHECK query returns 0 rows
--   no database state is changed
