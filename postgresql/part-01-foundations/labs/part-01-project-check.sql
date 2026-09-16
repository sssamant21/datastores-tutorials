-- ============================================================
-- [TUTORIAL-ACCEPTANCE — SAFE-READ]
-- PostgreSQL Part 1 — Hands-On Project Acceptance
-- Target: PostgreSQL 18
--
-- SAFETY:
--   READ ONLY
--   No CREATE / ALTER / DROP
--   No INSERT / UPDATE / DELETE / TRUNCATE
--   No GRANT / REVOKE
--   No ALTER SYSTEM
--   No configuration reload
--   No server restart
--   No session termination
--
-- EXPECTED DATABASE:
--   healthcare_lab
--
-- SECURITY:
--   Output may contain role names, filesystem paths,
--   client addresses, network information, and
--   authentication/configuration metadata.
--   Sanitize output before external sharing.
--
-- PRIVILEGE:
--   Some server inspection information is privilege-dependent.
--   Do not grant superuser solely to complete this tutorial.
-- ============================================================

\set ON_ERROR_STOP on

\echo '============================================================'
\echo 'PostgreSQL Part 1 - Hands-On Project Acceptance'
\echo '============================================================'

\echo ''
\echo '[1/11] Database guard'

SELECT current_database() = 'healthcare_lab' AS correct_database
\gset

\if :correct_database
    \echo 'PASS - connected to healthcare_lab'
\else
    \echo 'FAIL - acceptance must run against healthcare_lab'
    \quit
\endif

\echo ''
\echo '[2/11] Server identity'

SELECT current_database() AS database_name,
       current_user AS current_user,
       current_setting('server_version') AS server_version;

\echo ''
\echo '[3/11] Required roles'

SELECT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'healthcare_owner') AS healthcare_owner_exists,
       EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'healthcare_app') AS healthcare_app_exists,
       EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'healthcare_readonly') AS healthcare_readonly_exists;

\echo ''
\echo '[4/11] Required schemas'

SELECT EXISTS (SELECT 1 FROM pg_namespace WHERE nspname = 'clinical') AS clinical_schema_exists,
       EXISTS (SELECT 1 FROM pg_namespace WHERE nspname = 'scheduling') AS scheduling_schema_exists;

\echo ''
\echo '[5/11] Required tables'

SELECT to_regclass('clinical.patients') IS NOT NULL AS patients_exists,
       to_regclass('clinical.providers') IS NOT NULL AS providers_exists,
       to_regclass('scheduling.appointments') IS NOT NULL AS appointments_exists;

\echo ''
\echo '[6/11] Required constraints'

SELECT tc.table_schema, tc.table_name, tc.constraint_name, tc.constraint_type
FROM information_schema.table_constraints AS tc
WHERE tc.table_schema IN ('clinical', 'scheduling')
ORDER BY tc.table_schema, tc.table_name, tc.constraint_type, tc.constraint_name;

\echo ''
\echo '[7/11] Project row counts'

SELECT 'clinical.patients' AS relation_name, COUNT(*) AS row_count FROM clinical.patients
UNION ALL
SELECT 'clinical.providers', COUNT(*) FROM clinical.providers
UNION ALL
SELECT 'scheduling.appointments', COUNT(*) FROM scheduling.appointments
ORDER BY relation_name;

\echo ''
\echo '[8/11] Relationship verification'

SELECT p.medical_record, pr.provider_code, a.appointment_time, a.appointment_type, a.status
FROM scheduling.appointments AS a
JOIN clinical.patients AS p ON p.patient_id = a.patient_id
JOIN clinical.providers AS pr ON pr.provider_id = a.provider_id
ORDER BY a.appointment_time;

\echo ''
\echo '[9/11] Privilege boundary verification'

SELECT has_schema_privilege('healthcare_app','clinical','USAGE') AS app_clinical_usage,
       has_schema_privilege('healthcare_app','scheduling','USAGE') AS app_scheduling_usage,
       has_table_privilege('healthcare_app','clinical.patients','SELECT') AS app_patient_select,
       has_table_privilege('healthcare_app','clinical.patients','INSERT') AS app_patient_insert,
       has_table_privilege('healthcare_readonly','clinical.patients','SELECT') AS readonly_patient_select,
       has_table_privilege('healthcare_readonly','clinical.patients','DELETE') AS readonly_patient_delete;

\echo ''
\echo '[10/11] PostgreSQL activity and configuration'

SELECT pid, usename, datname, application_name, client_addr, state
FROM pg_stat_activity
WHERE datname = current_database()
ORDER BY pid;

SELECT name, setting, unit, context, source, pending_restart
FROM pg_settings
WHERE name IN ('listen_addresses','port','max_connections','shared_buffers','work_mem','password_encryption')
ORDER BY name;

\echo ''
\echo '[11/11] Configuration locations'

SELECT current_setting('data_directory') AS data_directory,
       current_setting('config_file') AS config_file,
       current_setting('hba_file') AS hba_file;

\echo ''
\echo '============================================================'
\echo 'CORE SAFE-READ ACCEPTANCE COMPLETE'
\echo 'PASS = required state verified'
\echo 'FAIL = required project state missing/incorrect'
\echo 'SKIP = optional inspection unavailable'
\echo 'Optional privileged HBA inspection is excluded from the mandatory acceptance path.'
\echo 'No PostgreSQL database or configuration state was modified.'
\echo '============================================================'
