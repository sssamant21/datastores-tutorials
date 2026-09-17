-- ============================================================================
-- Part 3.2 — Schema Design and Administration
-- File: labs/schema-admin-check.sql
-- Classification: [TUTORIAL-ACCEPTANCE — SAFE-READ]
-- Target: PostgreSQL 18
--
-- SAFETY CONTRACT
--   This script intentionally performs observational queries only.
--
-- IMPORTANT
--   * SAFE-READ does not mean zero operational cost.
--   * Metadata visibility and effective privileges can differ by role.
--   * A permission failure is not automatically a database health failure.
--
-- This script must not create, alter, move, grant, revoke, or drop objects;
-- modify data; change search_path; terminate sessions; reset statistics;
-- invoke maintenance; or modify configuration.
-- ============================================================================

\set ON_ERROR_STOP on
\pset pager off

\echo '======================================================================'
\echo 'Part 3.2 — Schema Design and Administration'
\echo '[TUTORIAL-ACCEPTANCE — SAFE-READ]'
\echo '======================================================================'

\echo ''
\echo 'CHECK 1 — Session and server identity'
SELECT
    current_database()  AS database_name,
    current_user        AS current_user,
    session_user        AS session_user,
    inet_server_addr()  AS server_address,
    inet_server_port()  AS server_port,
    pg_is_in_recovery() AS in_recovery;

\echo ''
\echo 'CHECK 2 — PostgreSQL version'
SELECT version();

\echo ''
\echo 'CHECK 3 — Configured and effective search path'
SELECT
    current_setting('search_path') AS configured_search_path,
    current_schema                 AS current_schema,
    current_schemas(false)         AS explicit_effective_schemas,
    current_schemas(true)          AS effective_schemas_with_implicit;

\echo ''
\echo 'CHECK 4 — Schema inventory and ownership'
SELECT
    n.oid,
    n.nspname AS schema_name,
    pg_get_userbyid(n.nspowner) AS owner
FROM pg_namespace AS n
ORDER BY n.nspname;

\echo ''
\echo 'CHECK 5 — Current-role-visible information-schema inventory'
SELECT
    s.schema_name,
    s.schema_owner
FROM information_schema.schemata AS s
ORDER BY s.schema_name;

\echo ''
\echo 'CHECK 6 — Schema ACL evidence'
SELECT
    n.nspname AS schema_name,
    pg_get_userbyid(n.nspowner) AS owner,
    n.nspacl
FROM pg_namespace AS n
ORDER BY n.nspname;

\echo ''
\echo 'CHECK 7 — Current-role effective schema privileges'
SELECT
    n.nspname AS schema_name,
    has_schema_privilege(current_user, n.oid, 'USAGE')  AS has_usage,
    has_schema_privilege(current_user, n.oid, 'CREATE') AS has_create
FROM pg_namespace AS n
ORDER BY n.nspname;

\echo ''
\echo 'CHECK 8 — Public schema ownership and privileges'
SELECT
    n.nspname AS schema_name,
    pg_get_userbyid(n.nspowner) AS owner,
    n.nspacl,
    has_schema_privilege(current_user, n.oid, 'USAGE')  AS current_user_usage,
    has_schema_privilege(current_user, n.oid, 'CREATE') AS current_user_create
FROM pg_namespace AS n
WHERE n.nspname = 'public';

\echo ''
\echo 'CHECK 9 — System, information, temporary, and application categories'
SELECT
    n.nspname AS schema_name,
    CASE
        WHEN n.nspname = 'information_schema' THEN 'information_schema'
        WHEN n.nspname LIKE 'pg_temp_%' OR n.nspname LIKE 'pg_toast_temp_%'
            THEN 'temporary-system'
        WHEN n.nspname LIKE 'pg_%' THEN 'system'
        ELSE 'application-or-extension'
    END AS schema_category
FROM pg_namespace AS n
ORDER BY schema_category, schema_name;

\echo ''
\echo 'CHECK 10 — Relation counts by schema and relation kind'
\echo 'NOTE: On very large databases, use an approved schema filter if needed.'
SELECT
    n.nspname AS schema_name,
    c.relkind,
    count(*) AS relation_count
FROM pg_class AS c
JOIN pg_namespace AS n
  ON n.oid = c.relnamespace
GROUP BY n.nspname, c.relkind
ORDER BY n.nspname, c.relkind;

\echo ''
\echo 'CHECK 11 — Non-system relation ownership inventory'
SELECT
    n.nspname AS schema_name,
    c.relname AS relation_name,
    c.relkind,
    pg_get_userbyid(c.relowner) AS relation_owner
FROM pg_class AS c
JOIN pg_namespace AS n
  ON n.oid = c.relnamespace
WHERE n.nspname <> 'information_schema'
  AND n.nspname NOT LIKE 'pg_%'
ORDER BY n.nspname, c.relname;

\echo ''
\echo 'CHECK 12 — Acceptance safety confirmation'
SELECT
    current_database() IS NOT NULL AS database_detected,
    current_user IS NOT NULL AS user_detected,
    current_schemas(true) IS NOT NULL AS effective_path_detected,
    EXISTS (
        SELECT 1
        FROM pg_namespace
        WHERE nspname = 'pg_catalog'
    ) AS pg_catalog_detected;

\echo ''
\echo '======================================================================'
\echo 'SAFE-READ LAB COMPLETE'
\echo 'No schemas, objects, privileges, configuration, or data were changed.'
\echo '======================================================================'
