-- [TUTORIAL-ACCEPTANCE — SAFE-READ]
-- labs/data-types-check.sql
-- Part 1.9 — PostgreSQL Data Types
-- Read-only validation only.
--
-- NO INSERT
-- NO UPDATE
-- NO DELETE
-- NO TRUNCATE
-- NO DDL

-- 1. Confirm context.
SELECT
    current_database() AS current_database,
    current_user       AS current_user;

-- 2. Confirm the tutorial table exists.
SELECT
    table_schema,
    table_name
FROM information_schema.tables
WHERE table_schema = 'clinical'
  AND table_name = 'data_type_lab';

-- 3. Validate declared column types.
SELECT
    column_name,
    data_type,
    udt_name,
    numeric_precision,
    numeric_scale,
    character_maximum_length,
    is_nullable
FROM information_schema.columns
WHERE table_schema = 'clinical'
  AND table_name = 'data_type_lab'
ORDER BY ordinal_position;

-- 4. Confirm the deterministic synthetic record is readable.
SELECT
    lab_id,
    patient_uuid,
    patient_code,
    description,
    visit_count,
    charge_amount,
    temperature_c,
    is_active,
    birth_date,
    appointment_at,
    recorded_at,
    metadata,
    allergies,
    binary_payload
FROM clinical.data_type_lab
WHERE patient_code = 'LAB-0001';

-- 5. Confirm runtime PostgreSQL types.
SELECT
    pg_typeof(patient_uuid)   AS patient_uuid_type,
    pg_typeof(patient_code)   AS patient_code_type,
    pg_typeof(description)    AS description_type,
    pg_typeof(visit_count)    AS visit_count_type,
    pg_typeof(charge_amount)  AS charge_amount_type,
    pg_typeof(temperature_c)  AS temperature_type,
    pg_typeof(is_active)      AS active_type,
    pg_typeof(birth_date)     AS birth_date_type,
    pg_typeof(appointment_at) AS appointment_type,
    pg_typeof(recorded_at)    AS recorded_at_type,
    pg_typeof(metadata)       AS metadata_type,
    pg_typeof(allergies)      AS allergies_type,
    pg_typeof(binary_payload) AS binary_payload_type
FROM clinical.data_type_lab
WHERE patient_code = 'LAB-0001';

-- 6. Validate NULL handling without changing data.
SELECT
    COUNT(*) FILTER (WHERE description IS NULL)
        AS null_description_rows,
    COUNT(*) FILTER (WHERE description IS NOT NULL)
        AS populated_description_rows
FROM clinical.data_type_lab;

-- 7. Show session timezone used to render timestamptz.
SHOW TimeZone;

-- [TUTORIAL-ACCEPTANCE — SAFE-READ]
-- PASS condition:
--   table exists;
--   expected types are present;
--   LAB-0001 is readable;
--   pg_typeof() reports expected PostgreSQL types;
--   this artifact makes no state changes.
