/*
===============================================================================
Part 4.4 — Ownership and Deployment/Runtime Role Separation
Canonical Acceptance Artifact

[TUTORIAL-ACCEPTANCE — SAFE-READ]

Target: PostgreSQL 18

Purpose:
  Inspect declared owner, deployment, and runtime roles plus current-database
  ownership and dependency signals without changing database state.

Required psql variables:
  expected_database
  expected_session_user
  owner_role
  deployment_role
  runtime_role

Safety:
  - Catalog reads and PostgreSQL built-in inquiry functions only
  - No CREATE / ALTER / DROP
  - No INSERT / UPDATE / DELETE / MERGE / TRUNCATE
  - No GRANT / REVOKE
  - No SET ROLE / SET SESSION AUTHORIZATION
  - No CALL or arbitrary user-defined function execution
  - No configuration changes
  - No routine body or raw routine-configuration value output

Expected impact:
  Catalog reads inside a REPEATABLE READ, READ ONLY transaction. Output volume
  scales with runtime-owned object count. Evidence contains security-sensitive
  role, ownership, routine, and dependency metadata.
===============================================================================
*/

\set ON_ERROR_STOP on
\pset pager off

\if :{?expected_database}
\else
    \echo 'ERROR: required variable expected_database is missing.'
    \quit 3
\endif
\if :{?expected_session_user}
\else
    \echo 'ERROR: required variable expected_session_user is missing.'
    \quit 3
\endif
\if :{?owner_role}
\else
    \echo 'ERROR: required variable owner_role is missing.'
    \quit 3
\endif
\if :{?deployment_role}
\else
    \echo 'ERROR: required variable deployment_role is missing.'
    \quit 3
\endif
\if :{?runtime_role}
\else
    \echo 'ERROR: required variable runtime_role is missing.'
    \quit 3
\endif

SELECT
    :'expected_database' ~ '^[a-z_][a-z0-9_]*$'
    AND :'expected_session_user' ~ '^[a-z_][a-z0-9_]*$'
    AND :'owner_role' ~ '^[a-z_][a-z0-9_]*$'
    AND :'deployment_role' ~ '^[a-z_][a-z0-9_]*$'
    AND :'runtime_role' ~ '^[a-z_][a-z0-9_]*$'
AS inputs_are_safe
\gset gate_

\if :gate_inputs_are_safe
\else
    \echo 'ERROR: all declared values must be simple lowercase identifiers.'
    \quit 3
\endif

SELECT
    pg_catalog.current_database() = :'expected_database'
    AND session_user = :'expected_session_user'
AS declared_context_matches
\gset gate_

\if :gate_declared_context_matches
\else
    \echo 'ERROR: connected database or session_user differs from declared context.'
    \quit 3
\endif

SELECT pg_catalog.current_setting('server_version_num')::integer / 10000 = 18
AS postgres_major_is_18
\gset gate_

\if :gate_postgres_major_is_18
\else
    \echo 'ERROR: this acceptance artifact requires PostgreSQL major version 18.'
    \quit 3
\endif

SELECT pg_catalog.count(*) = 3 AS all_declared_roles_exist
FROM pg_catalog.pg_roles
WHERE rolname IN (:'owner_role', :'deployment_role', :'runtime_role')
\gset gate_

\if :gate_all_declared_roles_exist
\else
    \echo 'ERROR: one or more declared roles do not exist or names are duplicated.'
    \quit 3
\endif

BEGIN TRANSACTION ISOLATION LEVEL REPEATABLE READ READ ONLY;

\echo ''
\echo '============================================================'
\echo 'Part 4.4 — Ownership Boundary Acceptance Check'
\echo '[TUTORIAL-ACCEPTANCE — SAFE-READ]'
\echo '============================================================'
\echo 'NOTICE: output contains security-sensitive ownership metadata.'

-- ---------------------------------------------------------------------------
-- 1. Hard-gate context
-- ---------------------------------------------------------------------------

\echo ''
\echo '--- [1/10] Version, transaction, identity, and declared roles ---'

SELECT
    pg_catalog.current_setting('server_version') AS server_version,
    pg_catalog.current_database() AS database_name,
    system_user AS authenticated_system_identity,
    session_user AS session_user,
    current_user AS current_user,
    :'owner_role' AS owner_role,
    :'deployment_role' AS deployment_role,
    :'runtime_role' AS runtime_role,
    pg_catalog.current_setting('transaction_isolation') AS transaction_isolation,
    pg_catalog.current_setting('transaction_read_only') AS transaction_read_only;

-- ---------------------------------------------------------------------------
-- 2. Declared role attributes
-- ---------------------------------------------------------------------------

\echo ''
\echo '--- [2/10] Declared role attributes ---'

SELECT
    r.rolname,
    r.rolcanlogin,
    r.rolsuper,
    r.rolcreaterole,
    r.rolcreatedb,
    r.rolreplication,
    r.rolbypassrls
FROM pg_catalog.pg_roles AS r
WHERE r.rolname IN (:'owner_role', :'deployment_role', :'runtime_role')
ORDER BY r.rolname;

-- ---------------------------------------------------------------------------
-- 3. Owner-role reachability
-- ---------------------------------------------------------------------------

\echo ''
\echo '--- [3/10] Deployment/runtime relationship to owner_role ---'

SELECT
    candidate.role_name,
    pg_catalog.pg_has_role(candidate.role_name, :'owner_role', 'MEMBER')
        AS owner_membership,
    pg_catalog.pg_has_role(candidate.role_name, :'owner_role', 'USAGE')
        AS owner_privileges_inherited,
    pg_catalog.pg_has_role(candidate.role_name, :'owner_role', 'SET')
        AS may_set_owner_role,
    pg_catalog.pg_has_role(
        candidate.role_name,
        :'owner_role',
        'MEMBER WITH ADMIN OPTION'
    ) AS owner_admin_option
FROM (
    VALUES
        (:'deployment_role'::name),
        (:'runtime_role'::name)
) AS candidate(role_name)
ORDER BY candidate.role_name;

-- ---------------------------------------------------------------------------
-- 4. Ownership counts by role and object class
-- ---------------------------------------------------------------------------

\echo ''
\echo '--- [4/10] Current-database ownership counts ---'

WITH declared_roles AS (
    SELECT oid, rolname FROM pg_catalog.pg_roles
    WHERE rolname IN (:'owner_role', :'deployment_role', :'runtime_role')
),
owned AS (
    SELECT r.rolname, 'SCHEMA'::text AS object_class
    FROM pg_catalog.pg_namespace AS n
    JOIN declared_roles AS r ON r.oid = n.nspowner
    WHERE n.nspname <> 'pg_catalog'
      AND n.nspname <> 'information_schema'
      AND n.nspname !~ '^pg_toast'
      AND n.nspname !~ '^pg_temp_'
    UNION ALL
    SELECT r.rolname, 'RELATION'
    FROM pg_catalog.pg_class AS c
    JOIN pg_catalog.pg_namespace AS n ON n.oid = c.relnamespace
    JOIN declared_roles AS r ON r.oid = c.relowner
    WHERE c.relkind IN ('r', 'p', 'v', 'm', 'S', 'f')
      AND n.nspname <> 'pg_catalog'
      AND n.nspname <> 'information_schema'
      AND n.nspname !~ '^pg_toast'
      AND n.nspname !~ '^pg_temp_'
    UNION ALL
    SELECT r.rolname, 'ROUTINE'
    FROM pg_catalog.pg_proc AS p
    JOIN pg_catalog.pg_namespace AS n ON n.oid = p.pronamespace
    JOIN declared_roles AS r ON r.oid = p.proowner
    WHERE n.nspname <> 'pg_catalog'
      AND n.nspname <> 'information_schema'
      AND n.nspname !~ '^pg_toast'
      AND n.nspname !~ '^pg_temp_'
    UNION ALL
    SELECT r.rolname, 'TYPE'
    FROM pg_catalog.pg_type AS t
    JOIN pg_catalog.pg_namespace AS n ON n.oid = t.typnamespace
    JOIN declared_roles AS r ON r.oid = t.typowner
    LEFT JOIN pg_catalog.pg_class AS backing_relation
        ON backing_relation.oid = t.typrelid
    WHERE n.nspname <> 'pg_catalog'
      AND n.nspname <> 'information_schema'
      AND n.nspname !~ '^pg_toast'
      AND n.nspname !~ '^pg_temp_'
      AND (t.typrelid = 0 OR backing_relation.relkind = 'c')
      AND NOT EXISTS (
          SELECT 1
          FROM pg_catalog.pg_type AS base_type
          WHERE base_type.typarray = t.oid
      )
)
SELECT rolname, object_class, pg_catalog.count(*) AS object_count
FROM owned
GROUP BY rolname, object_class
ORDER BY rolname, object_class;

-- ---------------------------------------------------------------------------
-- 5. Runtime-owned durable objects
-- ---------------------------------------------------------------------------

\echo ''
\echo '--- [5/10] Runtime-owned durable object review ---'

SELECT 'SCHEMA'::text AS object_class, n.nspname AS object_name
FROM pg_catalog.pg_namespace AS n
JOIN pg_catalog.pg_roles AS r ON r.oid = n.nspowner
WHERE r.rolname = :'runtime_role'
  AND n.nspname <> 'pg_catalog'
  AND n.nspname <> 'information_schema'
  AND n.nspname !~ '^pg_toast'
  AND n.nspname !~ '^pg_temp_'
UNION ALL
SELECT
    CASE c.relkind
        WHEN 'r' THEN 'TABLE'
        WHEN 'p' THEN 'PARTITIONED TABLE'
        WHEN 'v' THEN 'VIEW'
        WHEN 'm' THEN 'MATERIALIZED VIEW'
        WHEN 'S' THEN 'SEQUENCE'
        WHEN 'f' THEN 'FOREIGN TABLE'
        ELSE 'RELATION (' || c.relkind || ')'
    END,
    pg_catalog.quote_ident(n.nspname) || '.' || pg_catalog.quote_ident(c.relname)
FROM pg_catalog.pg_class AS c
JOIN pg_catalog.pg_namespace AS n ON n.oid = c.relnamespace
JOIN pg_catalog.pg_roles AS r ON r.oid = c.relowner
WHERE r.rolname = :'runtime_role'
  AND c.relkind IN ('r', 'p', 'v', 'm', 'S', 'f')
  AND n.nspname <> 'pg_catalog'
  AND n.nspname <> 'information_schema'
  AND n.nspname !~ '^pg_toast'
  AND n.nspname !~ '^pg_temp_'
UNION ALL
SELECT
    'ROUTINE',
    pg_catalog.quote_ident(n.nspname) || '.' || pg_catalog.quote_ident(p.proname)
        || '(' || pg_catalog.pg_get_function_identity_arguments(p.oid) || ')'
FROM pg_catalog.pg_proc AS p
JOIN pg_catalog.pg_namespace AS n ON n.oid = p.pronamespace
JOIN pg_catalog.pg_roles AS r ON r.oid = p.proowner
WHERE r.rolname = :'runtime_role'
  AND n.nspname <> 'pg_catalog'
  AND n.nspname <> 'information_schema'
  AND n.nspname !~ '^pg_toast'
  AND n.nspname !~ '^pg_temp_'
UNION ALL
SELECT
    'TYPE',
    pg_catalog.quote_ident(n.nspname) || '.' || pg_catalog.quote_ident(t.typname)
FROM pg_catalog.pg_type AS t
JOIN pg_catalog.pg_namespace AS n ON n.oid = t.typnamespace
JOIN pg_catalog.pg_roles AS r ON r.oid = t.typowner
LEFT JOIN pg_catalog.pg_class AS backing_relation
    ON backing_relation.oid = t.typrelid
WHERE r.rolname = :'runtime_role'
  AND n.nspname <> 'pg_catalog'
  AND n.nspname <> 'information_schema'
  AND n.nspname !~ '^pg_toast'
  AND n.nspname !~ '^pg_temp_'
  AND (t.typrelid = 0 OR backing_relation.relkind = 'c')
  AND NOT EXISTS (
      SELECT 1
      FROM pg_catalog.pg_type AS base_type
      WHERE base_type.typarray = t.oid
  )
ORDER BY object_class, object_name;

-- ---------------------------------------------------------------------------
-- 6. Owner-owned schemas and relations
-- ---------------------------------------------------------------------------

\echo ''
\echo '--- [6/10] Owner-owned schemas and relation counts ---'

SELECT
    n.nspname AS schema_name,
    n.nspowner = owner_role.oid AS schema_owned_by_owner,
    pg_catalog.count(c.oid) FILTER (WHERE c.relowner = owner_role.oid)
        AS owner_owned_relations,
    pg_catalog.count(c.oid) FILTER (WHERE c.relowner = runtime_role.oid)
        AS runtime_owned_relations
FROM pg_catalog.pg_namespace AS n
CROSS JOIN LATERAL (
    SELECT oid FROM pg_catalog.pg_roles WHERE rolname = :'owner_role'
) AS owner_role
CROSS JOIN LATERAL (
    SELECT oid FROM pg_catalog.pg_roles WHERE rolname = :'runtime_role'
) AS runtime_role
LEFT JOIN pg_catalog.pg_class AS c
    ON c.relnamespace = n.oid
   AND c.relkind IN ('r', 'p', 'v', 'm', 'S', 'f')
WHERE n.nspname <> 'pg_catalog'
  AND n.nspname <> 'information_schema'
  AND n.nspname !~ '^pg_toast'
  AND n.nspname !~ '^pg_temp_'
GROUP BY n.nspname, n.nspowner, owner_role.oid, runtime_role.oid
HAVING n.nspowner = owner_role.oid
    OR pg_catalog.count(c.oid) FILTER (
        WHERE c.relowner IN (owner_role.oid, runtime_role.oid)
    ) > 0
ORDER BY n.nspname;

-- ---------------------------------------------------------------------------
-- 7. Direct membership edges involving declared roles
-- ---------------------------------------------------------------------------

\echo ''
\echo '--- [7/10] Direct membership edges involving declared roles ---'

SELECT
    parent.rolname AS granted_role,
    member.rolname AS member_role,
    grantor.rolname AS grantor_role,
    m.admin_option,
    m.inherit_option,
    m.set_option
FROM pg_catalog.pg_auth_members AS m
JOIN pg_catalog.pg_roles AS parent ON parent.oid = m.roleid
JOIN pg_catalog.pg_roles AS member ON member.oid = m.member
JOIN pg_catalog.pg_roles AS grantor ON grantor.oid = m.grantor
WHERE parent.rolname IN (:'owner_role', :'deployment_role', :'runtime_role')
   OR member.rolname IN (:'owner_role', :'deployment_role', :'runtime_role')
ORDER BY parent.rolname, member.rolname, grantor.rolname;

-- ---------------------------------------------------------------------------
-- 8. Owner-associated SECURITY DEFINER routines
-- ---------------------------------------------------------------------------

\echo ''
\echo '--- [8/10] Owner-associated SECURITY DEFINER routines ---'

SELECT
    n.nspname AS schema_name,
    p.proname AS routine_name,
    pg_catalog.pg_get_function_identity_arguments(p.oid) AS identity_arguments,
    r.rolname AS owner,
    l.lanname AS language,
    p.proconfig IS NOT NULL AS has_routine_configuration,
    EXISTS (
        SELECT 1
        FROM pg_catalog.unnest(
            COALESCE(p.proconfig, ARRAY[]::text[])
        ) AS config(setting)
        WHERE pg_catalog.split_part(config.setting, '=', 1) = 'search_path'
    ) AS has_explicit_search_path,
    p.proacl AS acl
FROM pg_catalog.pg_proc AS p
JOIN pg_catalog.pg_namespace AS n ON n.oid = p.pronamespace
JOIN pg_catalog.pg_roles AS r ON r.oid = p.proowner
JOIN pg_catalog.pg_language AS l ON l.oid = p.prolang
WHERE r.rolname = :'owner_role'
  AND p.prosecdef
ORDER BY n.nspname, p.proname, identity_arguments;

-- Configuration values are intentionally not printed because arbitrary custom
-- settings can contain secrets. The search_path indicator and ACL still require
-- review; their presence alone does not prove safety.

-- ---------------------------------------------------------------------------
-- 9. Shared dependency signals
-- ---------------------------------------------------------------------------

\echo ''
\echo '--- [9/10] Shared dependency summary for declared roles ---'

SELECT
    referenced_role.rolname AS referenced_role,
    CASE
        WHEN sd.dbid = 0 THEN '<shared object>'
        ELSE COALESCE(d.datname, '<database oid ' || sd.dbid::text || '>')
    END AS dependency_database,
    CASE sd.deptype
        WHEN 'o' THEN 'OWNER'
        WHEN 'a' THEN 'ACL'
        WHEN 'i' THEN 'INITIAL ACL'
        WHEN 'r' THEN 'POLICY'
        ELSE 'UNKNOWN (' || sd.deptype || ')'
    END AS dependency_type,
    pg_catalog.count(*) AS dependency_count
FROM pg_catalog.pg_shdepend AS sd
JOIN pg_catalog.pg_roles AS referenced_role ON referenced_role.oid = sd.refobjid
LEFT JOIN pg_catalog.pg_database AS d ON d.oid = sd.dbid
WHERE sd.refclassid = 'pg_catalog.pg_authid'::pg_catalog.regclass
  AND referenced_role.rolname IN (
      :'owner_role', :'deployment_role', :'runtime_role'
  )
GROUP BY referenced_role.rolname, dependency_database, dependency_type
ORDER BY referenced_role.rolname, dependency_database, dependency_type;

-- ---------------------------------------------------------------------------
-- 10. Final hard-gate summary
-- ---------------------------------------------------------------------------

\echo ''
\echo '--- [10/10] Final hard-gate summary ---'

SELECT
    pg_catalog.current_setting('server_version_num')::integer / 10000 = 18
        AS postgres_major_is_18,
    pg_catalog.current_database() = :'expected_database' AS database_matches,
    session_user = :'expected_session_user' AS session_user_matches,
    (
        SELECT pg_catalog.count(*) = 3
        FROM pg_catalog.pg_roles
        WHERE rolname IN (:'owner_role', :'deployment_role', :'runtime_role')
    ) AS all_declared_roles_exist,
    pg_catalog.current_setting('transaction_isolation') = 'repeatable read'
        AS isolation_is_repeatable_read,
    pg_catalog.current_setting('transaction_read_only')::boolean
        AS transaction_is_read_only
\gset final_

SELECT
    :'final_postgres_major_is_18'::boolean AS postgres_major_is_18,
    :'final_database_matches'::boolean AS database_matches,
    :'final_session_user_matches'::boolean AS session_user_matches,
    :'final_all_declared_roles_exist'::boolean AS all_declared_roles_exist,
    :'final_isolation_is_repeatable_read'::boolean AS isolation_is_repeatable_read,
    :'final_transaction_is_read_only'::boolean AS transaction_is_read_only;

ROLLBACK;

SELECT
    :'final_postgres_major_is_18'::boolean
    AND :'final_database_matches'::boolean
    AND :'final_session_user_matches'::boolean
    AND :'final_all_declared_roles_exist'::boolean
    AND :'final_isolation_is_repeatable_read'::boolean
    AND :'final_transaction_is_read_only'::boolean
AS all_hard_gates_passed
\gset final_

\if :final_all_hard_gates_passed
    \echo ''
    \echo 'SAFE-READ acceptance checks completed; all hard gates passed.'
    \echo 'No ownership, role, membership, privilege, or object state was changed.'
    \echo 'Protect this output because it contains security-sensitive metadata.'
\else
    \echo ''
    \echo 'ERROR: one or more hard gates failed.'
    \quit 4
\endif
