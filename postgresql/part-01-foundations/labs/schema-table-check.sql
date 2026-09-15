/*
 PostgreSQL Practical Tutorial
 Part 1.7 — Schema and Table Validation

 Classification: [SAFE-READ]

 Purpose:
 Validate database context, schema resolution,
 schema metadata, privileges, and the tutorial
 table definition.

 Safety:
 - Read-only.
 - Contains no credentials.
 - Performs no DDL or DML.
 - Metadata can reveal internal database design.
 - Results depend on current PostgreSQL privileges.
 - Review/redact real-environment output before sharing.
*/

SELECT
    current_database() AS database_name,
    session_user AS session_user,
    current_user AS effective_role,
    pg_backend_pid() AS backend_pid;

SHOW search_path;

SELECT
    current_schema() AS current_schema,
    current_schemas(true) AS effective_schemas;

SELECT
    n.nspname AS schema_name,
    pg_catalog.pg_get_userbyid(n.nspowner) AS schema_owner
FROM pg_catalog.pg_namespace AS n
WHERE n.nspname = 'clinical';

SELECT
    has_database_privilege(
        current_user,
        current_database(),
        'CREATE'
    ) AS database_create_privilege;

SELECT
    n.nspname AS schema_name,
    has_schema_privilege(
        current_user,
        n.oid,
        'USAGE'
    ) AS schema_usage_privilege,
    has_schema_privilege(
        current_user,
        n.oid,
        'CREATE'
    ) AS schema_create_privilege
FROM pg_catalog.pg_namespace AS n
WHERE n.nspname = 'clinical';

SELECT
    schemaname AS schema_name,
    tablename AS table_name,
    tableowner AS table_owner
FROM pg_catalog.pg_tables
WHERE schemaname = 'clinical'
  AND tablename = 'patients';

SELECT
    ordinal_position,
    column_name,
    data_type,
    is_nullable,
    column_default,
    is_identity,
    identity_generation
FROM information_schema.columns
WHERE table_schema = 'clinical'
  AND table_name = 'patients'
ORDER BY ordinal_position;

SELECT
    pg_catalog.to_regclass(
        'clinical.patients'
    ) AS patients_relation;
