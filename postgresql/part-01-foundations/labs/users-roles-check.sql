-- labs/users-roles-check.sql
-- [TUTORIAL-ACCEPTANCE — SAFE-READ]
-- Part 1.11 — Users and Roles — Introduction
-- PostgreSQL 18
-- READ ONLY: no authorization or database mutation.

-- 1. Inspect current authorization context.
SELECT
    current_database() AS current_database,
    current_user       AS current_user,
    session_user       AS session_user;

-- 2. Verify tutorial roles and attributes.
SELECT
    rolname,
    rolcanlogin,
    rolsuper,
    rolcreatedb,
    rolcreaterole,
    rolinherit
FROM pg_roles
WHERE rolname IN ('tutorial_reader', 'tutorial_writer', 'tutorial_app')
ORDER BY rolname;

-- Expected:
-- tutorial_reader: rolcanlogin=false
-- tutorial_writer: rolcanlogin=false
-- tutorial_app:    rolcanlogin=true
-- All: rolsuper=false, rolcreatedb=false, rolcreaterole=false

-- 3. Verify PostgreSQL 18 membership relationships and options.
SELECT
    member_role.rolname  AS member_role,
    granted_role.rolname AS granted_role,
    m.admin_option,
    m.inherit_option,
    m.set_option
FROM pg_auth_members AS m
JOIN pg_roles AS granted_role ON granted_role.oid = m.roleid
JOIN pg_roles AS member_role ON member_role.oid = m.member
WHERE member_role.rolname = 'tutorial_app'
  AND granted_role.rolname IN ('tutorial_reader', 'tutorial_writer')
ORDER BY granted_role.rolname;

-- Expected memberships:
-- tutorial_app -> tutorial_reader
-- tutorial_app -> tutorial_writer
-- admin_option should not have been intentionally enabled by this tutorial.

-- 4. Verify reader schema access.
SELECT has_schema_privilege(
    'tutorial_reader', 'clinical', 'USAGE'
) AS reader_schema_usage;
-- Expected: true

-- 5. Verify writer schema access.
SELECT has_schema_privilege(
    'tutorial_writer', 'clinical', 'USAGE'
) AS writer_schema_usage;
-- Expected: true

-- 6. Verify reader SELECT access.
SELECT has_table_privilege(
    'tutorial_reader', 'clinical.constraint_patient', 'SELECT'
) AS reader_can_select;
-- Expected: true

-- 7. Verify reader was not granted DELETE.
SELECT has_table_privilege(
    'tutorial_reader', 'clinical.constraint_patient', 'DELETE'
) AS reader_can_delete;
-- Expected: false

-- 8. Verify writer privileges.
SELECT
    has_table_privilege('tutorial_writer', 'clinical.constraint_patient', 'SELECT') AS writer_can_select,
    has_table_privilege('tutorial_writer', 'clinical.constraint_patient', 'INSERT') AS writer_can_insert,
    has_table_privilege('tutorial_writer', 'clinical.constraint_patient', 'UPDATE') AS writer_can_update,
    has_table_privilege('tutorial_writer', 'clinical.constraint_patient', 'DELETE') AS writer_can_delete;
-- Expected: true, true, true, false

-- 9. Inspect explicitly visible table grants.
SELECT
    grantee,
    privilege_type
FROM information_schema.role_table_grants
WHERE table_schema = 'clinical'
  AND table_name = 'constraint_patient'
  AND grantee IN ('tutorial_reader', 'tutorial_writer')
ORDER BY grantee, privilege_type;

-- 10. Inspect ownership without changing it.
SELECT
    n.nspname AS schema_name,
    c.relname AS object_name,
    pg_get_userbyid(c.relowner) AS owner
FROM pg_class AS c
JOIN pg_namespace AS n ON n.oid = c.relnamespace
WHERE n.nspname = 'clinical'
  AND c.relname = 'constraint_patient';

-- 11. Inspect tutorial_app database CONNECT access.
SELECT has_database_privilege(
    'tutorial_app', current_database(), 'CONNECT'
) AS tutorial_app_can_connect;
-- Observational: effective CONNECT can include applicable PUBLIC privileges.

-- 12. Inspect relevant PUBLIC table privileges.
SELECT
    has_table_privilege('PUBLIC', 'clinical.constraint_patient', 'SELECT') AS public_can_select,
    has_table_privilege('PUBLIC', 'clinical.constraint_patient', 'INSERT') AS public_can_insert,
    has_table_privilege('PUBLIC', 'clinical.constraint_patient', 'UPDATE') AS public_can_update,
    has_table_privilege('PUBLIC', 'clinical.constraint_patient', 'DELETE') AS public_can_delete;
-- Observational only. Do not change PUBLIC privileges here.

-- [TUTORIAL-ACCEPTANCE — SAFE-READ]
-- PASS when:
--   all three tutorial roles exist
--   reader/writer cannot LOGIN; app can LOGIN
--   tutorial roles are not SUPERUSER and lack CREATEDB/CREATEROLE
--   tutorial_app has reader and writer memberships
--   PostgreSQL 18 ADMIN/INHERIT/SET membership metadata is inspectable
--   reader has schema USAGE and table SELECT but not DELETE
--   writer has schema USAGE and SELECT/INSERT/UPDATE but not DELETE
--   ownership, CONNECT, and PUBLIC access are inspectable
--   no database or authorization state is changed
