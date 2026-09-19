/*
===============================================================================
Part 4.5 — Database, Schema, and Secure search_path Privileges
Canonical Acceptance Artifact

[TUTORIAL-ACCEPTANCE — SAFE-READ]

Target: PostgreSQL 18

Purpose:
  Inspect declared application-role database/schema privileges, raw ACLs, and
  current-session search_path signals without changing database state.

Required psql variables:
  expected_database
  expected_session_user
  application_role
  application_schema

Safety:
  - Catalog reads and PostgreSQL built-in inquiry functions only
  - No CREATE / ALTER / DROP
  - No INSERT / UPDATE / DELETE / MERGE / TRUNCATE
  - No GRANT / REVOKE
  - No SET ROLE / SET SESSION AUTHORIZATION
  - No CALL or arbitrary user-defined function execution
  - No configuration changes

Expected impact:
  Catalog reads inside a REPEATABLE READ, READ ONLY transaction. Evidence
  contains security-sensitive role, owner, ACL, authentication-identity, and
  namespace metadata. Results are point-in-time evidence. On a standby, they
  can lag the primary.
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
\if :{?application_role}
\else
    \echo 'ERROR: required variable application_role is missing.'
    \quit 3
\endif
\if :{?application_schema}
\else
    \echo 'ERROR: required variable application_schema is missing.'
    \quit 3
\endif

SELECT
    :'expected_database' ~ '^[a-z_][a-z0-9_]*$'
    AND :'expected_session_user' ~ '^[a-z_][a-z0-9_]*$'
    AND :'application_role' ~ '^[a-z_][a-z0-9_]*$'
    AND :'application_schema' ~ '^[a-z_][a-z0-9_]*$'
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

SELECT pg_catalog.count(*) = 1 AS application_role_exists
FROM pg_catalog.pg_roles
WHERE rolname = :'application_role'
\gset gate_

\if :gate_application_role_exists
\else
    \echo 'ERROR: declared application_role does not exist.'
    \quit 3
\endif

SELECT pg_catalog.count(*) = 1 AS application_schema_exists
FROM pg_catalog.pg_namespace
WHERE nspname = :'application_schema'
\gset gate_

\if :gate_application_schema_exists
\else
    \echo 'ERROR: declared application_schema does not exist.'
    \quit 3
\endif

BEGIN TRANSACTION ISOLATION LEVEL REPEATABLE READ READ ONLY;

\echo ''
\echo '============================================================'
\echo 'Part 4.5 — Database/Schema Privilege and search_path Check'
\echo '[TUTORIAL-ACCEPTANCE — SAFE-READ]'
\echo '============================================================'
\echo 'NOTICE: output contains security-sensitive privilege metadata.'

-- ---------------------------------------------------------------------------
-- 1. Hard-gate context
-- ---------------------------------------------------------------------------

\echo ''
\echo '--- [1/10] Version, transaction, identity, and declared target ---'

SELECT
    pg_catalog.statement_timestamp() AS evidence_timestamp,
    pg_catalog.current_setting('server_version') AS server_version,
    pg_catalog.current_database() AS database_name,
    pg_catalog.pg_is_in_recovery() AS server_is_in_recovery,
    system_user AS authenticated_system_identity,
    session_user AS session_user,
    current_user AS current_user,
    :'application_role' AS application_role,
    :'application_schema' AS application_schema,
    app_role.rolcanlogin AS application_role_can_login,
    app_role.rolsuper AS application_role_is_superuser,
    app_role.rolinherit AS application_role_inherits_privileges,
    app_role.rolcreaterole AS application_role_can_create_roles,
    app_role.rolcreatedb AS application_role_can_create_databases,
    app_role.rolreplication AS application_role_has_replication,
    app_role.rolbypassrls AS application_role_bypasses_rls,
    pg_catalog.current_setting('transaction_isolation') AS transaction_isolation,
    pg_catalog.current_setting('transaction_read_only') AS transaction_read_only
FROM pg_catalog.pg_roles AS app_role
WHERE app_role.rolname = :'application_role';

-- ---------------------------------------------------------------------------
-- 2. Database owner, ACL, and effective privilege matrix
-- ---------------------------------------------------------------------------

\echo ''
\echo '--- [2/10] Current database owner, ACL, and effective privileges ---'

SELECT
    d.datname AS database_name,
    pg_catalog.pg_get_userbyid(d.datdba) AS owner,
    d.datallowconn AS connections_allowed,
    d.datconnlimit AS connection_limit,
    d.datacl AS raw_acl,
    pg_catalog.has_database_privilege(
        :'application_role', d.oid, 'CONNECT'
    ) AS application_connect,
    pg_catalog.has_database_privilege(
        :'application_role', d.oid, 'CREATE'
    ) AS application_create,
    pg_catalog.has_database_privilege(
        :'application_role', d.oid, 'TEMPORARY'
    ) AS application_temporary,
    pg_catalog.has_database_privilege('public', d.oid, 'CONNECT')
        AS public_connect,
    pg_catalog.has_database_privilege('public', d.oid, 'CREATE')
        AS public_create,
    pg_catalog.has_database_privilege('public', d.oid, 'TEMPORARY')
        AS public_temporary
FROM pg_catalog.pg_database AS d
WHERE d.datname = pg_catalog.current_database();

-- ---------------------------------------------------------------------------
-- 3. Expanded database ACL
-- ---------------------------------------------------------------------------

\echo ''
\echo '--- [3/10] Current database ACL entries, including defaults ---'

SELECT
    CASE
        WHEN acl.grantee = 0 THEN 'PUBLIC'
        ELSE pg_catalog.pg_get_userbyid(acl.grantee)
    END AS grantee,
    pg_catalog.pg_get_userbyid(acl.grantor) AS grantor,
    acl.privilege_type,
    acl.is_grantable
FROM pg_catalog.pg_database AS d
CROSS JOIN LATERAL pg_catalog.aclexplode(
    COALESCE(
        d.datacl,
        pg_catalog.acldefault('d'::"char", d.datdba)
    )
) AS acl
WHERE d.datname = pg_catalog.current_database()
ORDER BY grantee, acl.privilege_type, grantor;

-- ---------------------------------------------------------------------------
-- 4. Application schema owner, ACL, and effective privilege matrix
-- ---------------------------------------------------------------------------

\echo ''
\echo '--- [4/10] Application schema owner, ACL, and privileges ---'

SELECT
    n.nspname AS schema_name,
    pg_catalog.pg_get_userbyid(n.nspowner) AS owner,
    n.nspacl AS raw_acl,
    pg_catalog.has_schema_privilege(
        :'application_role', n.oid, 'USAGE'
    ) AS application_usage,
    pg_catalog.has_schema_privilege(
        :'application_role', n.oid, 'CREATE'
    ) AS application_create,
    pg_catalog.has_schema_privilege('public', n.oid, 'USAGE')
        AS public_usage,
    pg_catalog.has_schema_privilege('public', n.oid, 'CREATE')
        AS public_create
FROM pg_catalog.pg_namespace AS n
WHERE n.nspname = :'application_schema';

-- ---------------------------------------------------------------------------
-- 5. Expanded application-schema ACL
-- ---------------------------------------------------------------------------

\echo ''
\echo '--- [5/10] Application schema ACL entries, including defaults ---'

SELECT
    CASE
        WHEN acl.grantee = 0 THEN 'PUBLIC'
        ELSE pg_catalog.pg_get_userbyid(acl.grantee)
    END AS grantee,
    pg_catalog.pg_get_userbyid(acl.grantor) AS grantor,
    acl.privilege_type,
    acl.is_grantable
FROM pg_catalog.pg_namespace AS n
CROSS JOIN LATERAL pg_catalog.aclexplode(
    COALESCE(
        n.nspacl,
        pg_catalog.acldefault('n'::"char", n.nspowner)
    )
) AS acl
WHERE n.nspname = :'application_schema'
ORDER BY grantee, acl.privilege_type, grantor;

-- ---------------------------------------------------------------------------
-- 6. public schema evidence
-- ---------------------------------------------------------------------------

\echo ''
\echo '--- [6/10] public schema owner and effective privileges ---'

SELECT
    n.nspname AS schema_name,
    pg_catalog.pg_get_userbyid(n.nspowner) AS owner,
    n.nspacl AS raw_acl,
    pg_catalog.has_schema_privilege(
        :'application_role', n.oid, 'USAGE'
    ) AS application_usage,
    pg_catalog.has_schema_privilege(
        :'application_role', n.oid, 'CREATE'
    ) AS application_create,
    pg_catalog.has_schema_privilege('public', n.oid, 'USAGE')
        AS public_usage,
    pg_catalog.has_schema_privilege('public', n.oid, 'CREATE')
        AS public_create
FROM pg_catalog.pg_namespace AS n
WHERE n.nspname = 'public';

-- Zero rows means this database has no schema named public.

-- ---------------------------------------------------------------------------
-- 7. Configured and resolved current-session search path
-- ---------------------------------------------------------------------------

\echo ''
\echo '--- [7/10] Current-session configured and resolved search path ---'

SELECT
    pg_catalog.current_setting('search_path') AS configured_search_path,
    current_schema AS current_schema,
    pg_catalog.current_schemas(false) AS resolved_explicit_schemas,
    pg_catalog.current_schemas(true) AS resolved_with_implicit_schemas;

-- ---------------------------------------------------------------------------
-- 8. Current-session effective path details
-- ---------------------------------------------------------------------------

\echo ''
\echo '--- [8/10] Current-session effective path ownership and writability ---'

SELECT
    path.position,
    path.schema_name,
    pg_catalog.pg_get_userbyid(n.nspowner) AS owner,
    pg_catalog.has_schema_privilege(current_user, n.oid, 'USAGE')
        AS current_user_usage,
    pg_catalog.has_schema_privilege(current_user, n.oid, 'CREATE')
        AS current_user_create,
    pg_catalog.has_schema_privilege('public', n.oid, 'CREATE')
        AS public_create,
    n.nspname = 'pg_catalog' AS is_pg_catalog,
    n.nspname ~ '^pg_temp_' AS is_temporary_schema
FROM pg_catalog.unnest(pg_catalog.current_schemas(true))
    WITH ORDINALITY AS path(schema_name, position)
JOIN pg_catalog.pg_namespace AS n
    ON n.nspname = path.schema_name
ORDER BY path.position;

-- current_schemas(true) describes current_user, not application_role.
-- A TRUE current_user_create or public_create value is a review signal, not by
-- itself a final safe/unsafe verdict.

-- ---------------------------------------------------------------------------
-- 9. Application-role access across user schemas
-- ---------------------------------------------------------------------------

\echo ''
\echo '--- [9/10] Application-role and PUBLIC user-schema privilege inventory ---'

SELECT
    n.nspname AS schema_name,
    pg_catalog.pg_get_userbyid(n.nspowner) AS owner,
    pg_catalog.has_schema_privilege(
        :'application_role', n.oid, 'USAGE'
    ) AS application_usage,
    pg_catalog.has_schema_privilege(
        :'application_role', n.oid, 'CREATE'
    ) AS application_create,
    pg_catalog.has_schema_privilege('public', n.oid, 'USAGE')
        AS public_usage,
    pg_catalog.has_schema_privilege('public', n.oid, 'CREATE')
        AS public_create,
    n.nspname = :'application_schema' AS is_declared_application_schema
FROM pg_catalog.pg_namespace AS n
WHERE n.nspname <> 'pg_catalog'
  AND n.nspname <> 'information_schema'
  AND n.nspname !~ '^pg_toast'
  AND n.nspname !~ '^pg_temp_'
ORDER BY n.nspname;

-- ---------------------------------------------------------------------------
-- 10. Declared access and final hard-gate summary
-- ---------------------------------------------------------------------------

\echo ''
\echo '--- [10/10] Declared access and final hard-gate summary ---'

SELECT
    pg_catalog.has_database_privilege(
        :'application_role', pg_catalog.current_database(), 'CONNECT'
    ) AS database_connect,
    pg_catalog.has_database_privilege(
        :'application_role', pg_catalog.current_database(), 'CREATE'
    ) AS database_create,
    pg_catalog.has_database_privilege(
        :'application_role', pg_catalog.current_database(), 'TEMPORARY'
    ) AS database_temporary,
    pg_catalog.has_schema_privilege(
        :'application_role', :'application_schema', 'USAGE'
    ) AS application_schema_usage,
    pg_catalog.has_schema_privilege(
        :'application_role', :'application_schema', 'CREATE'
    ) AS application_schema_create;

SELECT
    pg_catalog.current_setting('server_version_num')::integer / 10000 = 18
        AS postgres_major_is_18,
    pg_catalog.current_database() = :'expected_database' AS database_matches,
    session_user = :'expected_session_user' AS session_user_matches,
    (
        SELECT pg_catalog.count(*) = 1
        FROM pg_catalog.pg_roles
        WHERE rolname = :'application_role'
    ) AS application_role_exists,
    (
        SELECT pg_catalog.count(*) = 1
        FROM pg_catalog.pg_namespace
        WHERE nspname = :'application_schema'
    ) AS application_schema_exists,
    pg_catalog.current_setting('transaction_isolation') = 'repeatable read'
        AS isolation_is_repeatable_read,
    pg_catalog.current_setting('transaction_read_only')::boolean
        AS transaction_is_read_only
\gset final_

SELECT
    :'final_postgres_major_is_18'::boolean AS postgres_major_is_18,
    :'final_database_matches'::boolean AS database_matches,
    :'final_session_user_matches'::boolean AS session_user_matches,
    :'final_application_role_exists'::boolean AS application_role_exists,
    :'final_application_schema_exists'::boolean AS application_schema_exists,
    :'final_isolation_is_repeatable_read'::boolean
        AS isolation_is_repeatable_read,
    :'final_transaction_is_read_only'::boolean AS transaction_is_read_only;

\echo ''
\echo 'Interpret effective privileges with ownership, membership, PUBLIC,'
\echo 'raw ACLs, session settings, object privileges, and external controls.'
\echo 'The lab does not impersonate application_role and does not declare the'
\echo 'current session or application configuration safe.'
\echo 'If server_is_in_recovery is true, account for replication lag before'
\echo 'using this evidence to approve a primary-side authorization decision.'

ROLLBACK;

SELECT
    :'final_postgres_major_is_18'::boolean
    AND :'final_database_matches'::boolean
    AND :'final_session_user_matches'::boolean
    AND :'final_application_role_exists'::boolean
    AND :'final_application_schema_exists'::boolean
    AND :'final_isolation_is_repeatable_read'::boolean
    AND :'final_transaction_is_read_only'::boolean
AS all_hard_gates_passed
\gset final_

\if :final_all_hard_gates_passed
    \echo ''
    \echo 'SAFE-READ acceptance checks completed; all hard gates passed.'
    \echo 'No database objects, privileges, or configuration were changed.'
    \echo 'Protect this output because it contains security-sensitive metadata.'
\else
    \echo ''
    \echo 'ERROR: one or more hard gates failed.'
    \quit 4
\endif
