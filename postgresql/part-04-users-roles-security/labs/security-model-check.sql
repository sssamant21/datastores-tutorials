/*
===============================================================================
Part 4.1 — PostgreSQL Security Model Fundamentals
Canonical Acceptance Artifact

[TUTORIAL-ACCEPTANCE — SAFE-READ]

Target: PostgreSQL 18

Purpose:
  Validate the declared session context and inspect database-visible security
  metadata without modifying database state.

Required psql variables:
  expected_database
  expected_session_user

Safety:
  - Catalog reads and PostgreSQL built-in inspection functions only
  - No CREATE / ALTER / DROP
  - No INSERT / UPDATE / DELETE / MERGE / TRUNCATE
  - No GRANT / REVOKE
  - No SET ROLE / SET SESSION AUTHORIZATION
  - No CALL or arbitrary user-defined function execution
  - No configuration changes

Expected impact:
  Catalog reads inside a REPEATABLE READ, READ ONLY transaction. Runtime and
  output volume scale with catalog, ACL, and membership size. The output
  contains security-sensitive metadata and must be protected.
===============================================================================
*/

\set ON_ERROR_STOP on

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

-- Restrict safety inputs to simple, unquoted lowercase PostgreSQL identifiers.
SELECT :'expected_database' ~ '^[a-z_][a-z0-9_]*$'
   AND :'expected_session_user' ~ '^[a-z_][a-z0-9_]*$'
AS inputs_are_safe
\gset gate_

\if :gate_inputs_are_safe
\else
    \echo 'ERROR: expected values must be simple lowercase identifiers.'
    \quit 3
\endif

SELECT pg_catalog.current_database() = :'expected_database'
   AND session_user = :'expected_session_user'
AS declared_context_matches
\gset gate_

\if :gate_declared_context_matches
\else
    \echo 'ERROR: connected database or session_user differs from declared context.'
    \quit 3
\endif

-- PostgreSQL 18 is a pre-inventory gate because later queries intentionally
-- use PostgreSQL 18 catalog columns such as inherit_option and set_option.
SELECT pg_catalog.current_setting('server_version_num')::integer / 10000 = 18
AS postgres_major_is_18
\gset gate_

\if :gate_postgres_major_is_18
\else
    \echo 'ERROR: this acceptance artifact requires PostgreSQL major version 18.'
    \quit 3
\endif

BEGIN TRANSACTION ISOLATION LEVEL REPEATABLE READ READ ONLY;

\echo ''
\echo '============================================================'
\echo 'Part 4.1 — PostgreSQL Security Model Acceptance Check'
\echo '[TUTORIAL-ACCEPTANCE — SAFE-READ]'
\echo '============================================================'
\echo 'NOTICE: output contains security-sensitive metadata.'
\echo 'Protect, redact, retain, and dispose of it under approved policy.'

-- ---------------------------------------------------------------------------
-- 1. Hard-gate context
-- ---------------------------------------------------------------------------

\echo ''
\echo '--- [1/12] Version, transaction, and identity hard gates ---'

SELECT
    pg_catalog.current_setting('server_version') AS server_version,
    pg_catalog.current_setting('server_version_num') AS server_version_num,
    pg_catalog.current_database() AS database_name,
    system_user AS authenticated_system_identity,
    session_user AS session_user,
    current_user AS current_user,
    current_role AS current_role,
    pg_catalog.current_setting('transaction_isolation') AS transaction_isolation,
    pg_catalog.current_setting('transaction_read_only') AS transaction_read_only;

-- ---------------------------------------------------------------------------
-- 2. Session and effective role identity
-- ---------------------------------------------------------------------------

\echo ''
\echo '--- [2/12] Session and effective role identity ---'

SELECT
    system_user AS authenticated_system_identity,
    session_user AS session_user,
    sr.oid AS session_role_oid,
    current_user AS current_user,
    cr.oid AS current_role_oid,
    session_user = current_user AS identities_match
FROM pg_catalog.pg_roles AS sr
JOIN pg_catalog.pg_roles AS cr
    ON cr.rolname = current_user
WHERE sr.rolname = session_user;

-- ---------------------------------------------------------------------------
-- 3. Role attributes
-- ---------------------------------------------------------------------------

\echo ''
\echo '--- [3/12] Session and effective role attributes ---'

SELECT
    r.rolname AS role_name,
    CASE
        WHEN r.rolname = session_user AND r.rolname = current_user
            THEN 'session and effective'
        WHEN r.rolname = session_user THEN 'session'
        ELSE 'effective'
    END AS identity_scope,
    r.rolsuper,
    r.rolinherit,
    r.rolcreaterole,
    r.rolcreatedb,
    r.rolcanlogin,
    r.rolreplication,
    r.rolbypassrls,
    r.rolconnlimit,
    r.rolvaliduntil
FROM pg_catalog.pg_roles AS r
WHERE r.rolname IN (session_user, current_user)
ORDER BY r.rolname;

-- ---------------------------------------------------------------------------
-- 4. Direct membership edges
-- ---------------------------------------------------------------------------

\echo ''
\echo '--- [4/12] Direct memberships involving session/effective roles ---'

SELECT
    parent.rolname AS granted_role,
    member.rolname AS member_role,
    grantor.rolname AS grantor_role,
    m.admin_option,
    m.inherit_option,
    m.set_option
FROM pg_catalog.pg_auth_members AS m
JOIN pg_catalog.pg_roles AS parent
    ON parent.oid = m.roleid
JOIN pg_catalog.pg_roles AS member
    ON member.oid = m.member
JOIN pg_catalog.pg_roles AS grantor
    ON grantor.oid = m.grantor
WHERE member.rolname IN (session_user, current_user)
   OR parent.rolname IN (session_user, current_user)
ORDER BY parent.rolname, member.rolname, grantor.rolname;

-- ---------------------------------------------------------------------------
-- 5. Predefined-role membership signals
-- ---------------------------------------------------------------------------

\echo ''
\echo '--- [5/12] Direct predefined-role membership and database-owner signals ---'

SELECT
    'EXPLICIT MEMBERSHIP'::text AS signal_type,
    parent.rolname AS predefined_role,
    member.rolname AS member_role,
    m.admin_option::text AS admin_option,
    m.inherit_option::text AS inherit_option,
    m.set_option::text AS set_option
FROM pg_catalog.pg_auth_members AS m
JOIN pg_catalog.pg_roles AS parent
    ON parent.oid = m.roleid
JOIN pg_catalog.pg_roles AS member
    ON member.oid = m.member
WHERE pg_catalog.left(parent.rolname, 3) = 'pg_'
  AND member.rolname IN (session_user, current_user)
UNION ALL
SELECT
    'IMPLICIT CURRENT-DATABASE OWNER',
    'pg_database_owner',
    pg_catalog.pg_get_userbyid(d.datdba),
    'not applicable',
    'implicit',
    'not grantable'
FROM pg_catalog.pg_database AS d
WHERE d.datname = pg_catalog.current_database()
  AND pg_catalog.pg_get_userbyid(d.datdba) IN (session_user, current_user)
ORDER BY predefined_role, member_role;

-- ---------------------------------------------------------------------------
-- 6. Database and schema ownership
-- ---------------------------------------------------------------------------

\echo ''
\echo '--- [6/12] Database and non-system schema ownership ---'

SELECT
    'DATABASE'::text AS object_type,
    d.datname AS object_name,
    pg_catalog.pg_get_userbyid(d.datdba) AS owner
FROM pg_catalog.pg_database AS d
WHERE d.datname = pg_catalog.current_database()
UNION ALL
SELECT
    'SCHEMA',
    n.nspname,
    pg_catalog.pg_get_userbyid(n.nspowner)
FROM pg_catalog.pg_namespace AS n
WHERE n.nspname <> 'information_schema'
  AND n.nspname !~ '^pg_'
ORDER BY object_type, object_name;

-- ---------------------------------------------------------------------------
-- 7. Objects owned by the effective role
-- ---------------------------------------------------------------------------

\echo ''
\echo '--- [7/12] Non-system relation/routine counts owned by current_user ---'

WITH owned_objects AS (
    SELECT
        CASE c.relkind
            WHEN 'r' THEN 'TABLE'
            WHEN 'p' THEN 'PARTITIONED TABLE'
            WHEN 'v' THEN 'VIEW'
            WHEN 'm' THEN 'MATERIALIZED VIEW'
            WHEN 'S' THEN 'SEQUENCE'
            WHEN 'f' THEN 'FOREIGN TABLE'
            ELSE 'RELATION (' || c.relkind || ')'
        END AS object_type
    FROM pg_catalog.pg_class AS c
    JOIN pg_catalog.pg_namespace AS n
        ON n.oid = c.relnamespace
    WHERE c.relowner = (SELECT oid FROM pg_catalog.pg_roles WHERE rolname = current_user)
      AND n.nspname <> 'information_schema'
      AND n.nspname !~ '^pg_'
    UNION ALL
    SELECT 'ROUTINE'
    FROM pg_catalog.pg_proc AS p
    JOIN pg_catalog.pg_namespace AS n
        ON n.oid = p.pronamespace
    WHERE p.proowner = (SELECT oid FROM pg_catalog.pg_roles WHERE rolname = current_user)
      AND n.nspname <> 'information_schema'
      AND n.nspname !~ '^pg_'
)
SELECT object_type, pg_catalog.count(*) AS object_count
FROM owned_objects
GROUP BY object_type
ORDER BY object_type;

-- ---------------------------------------------------------------------------
-- 8. Raw ACL inventory
-- ---------------------------------------------------------------------------

\echo ''
\echo '--- [8/12] Raw database, schema, and relation ACL inventory ---'

SELECT
    'DATABASE'::text AS object_type,
    d.datname AS qualified_name,
    pg_catalog.pg_get_userbyid(d.datdba) AS owner,
    d.datacl::text AS acl,
    d.datacl IS NULL AS uses_builtin_acl_default
FROM pg_catalog.pg_database AS d
WHERE d.datname = pg_catalog.current_database()
UNION ALL
SELECT
    'SCHEMA',
    n.nspname,
    pg_catalog.pg_get_userbyid(n.nspowner),
    n.nspacl::text,
    n.nspacl IS NULL
FROM pg_catalog.pg_namespace AS n
WHERE n.nspname <> 'information_schema'
  AND n.nspname !~ '^pg_'
UNION ALL
SELECT
    CASE WHEN c.relkind = 'S' THEN 'SEQUENCE' ELSE 'RELATION' END,
    pg_catalog.quote_ident(n.nspname) || '.' || pg_catalog.quote_ident(c.relname),
    pg_catalog.pg_get_userbyid(c.relowner),
    c.relacl::text,
    c.relacl IS NULL
FROM pg_catalog.pg_class AS c
JOIN pg_catalog.pg_namespace AS n
    ON n.oid = c.relnamespace
WHERE c.relkind IN ('r', 'p', 'v', 'm', 'S', 'f')
  AND n.nspname <> 'information_schema'
  AND n.nspname !~ '^pg_'
ORDER BY object_type, qualified_name;

-- ---------------------------------------------------------------------------
-- 9. Explicit PUBLIC grants
-- ---------------------------------------------------------------------------

\echo ''
\echo '--- [9/12] Explicit PUBLIC grants on inspected objects ---'

WITH public_grants AS (
    SELECT
        'DATABASE'::text AS object_type,
        d.datname AS qualified_name,
        x.privilege_type,
        x.is_grantable
    FROM pg_catalog.pg_database AS d
    CROSS JOIN LATERAL pg_catalog.aclexplode(d.datacl) AS x
    WHERE d.datname = pg_catalog.current_database()
      AND x.grantee = 0
    UNION ALL
    SELECT
        'SCHEMA', n.nspname, x.privilege_type, x.is_grantable
    FROM pg_catalog.pg_namespace AS n
    CROSS JOIN LATERAL pg_catalog.aclexplode(n.nspacl) AS x
    WHERE n.nspname <> 'information_schema'
      AND n.nspname !~ '^pg_'
      AND x.grantee = 0
    UNION ALL
    SELECT
        CASE WHEN c.relkind = 'S' THEN 'SEQUENCE' ELSE 'RELATION' END,
        pg_catalog.quote_ident(n.nspname) || '.' || pg_catalog.quote_ident(c.relname),
        x.privilege_type,
        x.is_grantable
    FROM pg_catalog.pg_class AS c
    JOIN pg_catalog.pg_namespace AS n
        ON n.oid = c.relnamespace
    CROSS JOIN LATERAL pg_catalog.aclexplode(c.relacl) AS x
    WHERE c.relkind IN ('r', 'p', 'v', 'm', 'S', 'f')
      AND n.nspname <> 'information_schema'
      AND n.nspname !~ '^pg_'
      AND x.grantee = 0
)
SELECT object_type, qualified_name, privilege_type, is_grantable
FROM public_grants
ORDER BY object_type, qualified_name, privilege_type;

-- NULL ACLs use built-in defaults and are intentionally reported in section 8.
-- This section shows explicit stored ACL entries only.

-- ---------------------------------------------------------------------------
-- 10. Effective database and schema privileges
-- ---------------------------------------------------------------------------

\echo ''
\echo '--- [10/12] Effective database and schema privileges ---'

SELECT
    'DATABASE'::text AS object_type,
    pg_catalog.current_database() AS object_name,
    pg_catalog.has_database_privilege(
        current_user, pg_catalog.current_database(), 'CONNECT'
    ) AS can_connect,
    pg_catalog.has_database_privilege(
        current_user, pg_catalog.current_database(), 'CREATE'
    ) AS can_create,
    pg_catalog.has_database_privilege(
        current_user, pg_catalog.current_database(), 'TEMPORARY'
    ) AS can_temporary
UNION ALL
SELECT
    'SCHEMA',
    n.nspname,
    pg_catalog.has_schema_privilege(current_user, n.oid, 'USAGE'),
    pg_catalog.has_schema_privilege(current_user, n.oid, 'CREATE'),
    NULL::boolean
FROM pg_catalog.pg_namespace AS n
WHERE n.nspname <> 'information_schema'
  AND n.nspname !~ '^pg_'
ORDER BY object_type, object_name;

-- ---------------------------------------------------------------------------
-- 11. RLS and SECURITY DEFINER signals
-- ---------------------------------------------------------------------------

\echo ''
\echo '--- [11/12] RLS and SECURITY DEFINER review signals ---'

SELECT
    'ROW LEVEL SECURITY'::text AS signal_type,
    pg_catalog.quote_ident(n.nspname) || '.' || pg_catalog.quote_ident(c.relname) AS object_name,
    pg_catalog.pg_get_userbyid(c.relowner) AS owner,
    pg_catalog.format(
        'enabled=%s, forced=%s', c.relrowsecurity, c.relforcerowsecurity
    ) AS detail
FROM pg_catalog.pg_class AS c
JOIN pg_catalog.pg_namespace AS n
    ON n.oid = c.relnamespace
WHERE (c.relrowsecurity OR c.relforcerowsecurity)
  AND n.nspname <> 'information_schema'
  AND n.nspname !~ '^pg_'
UNION ALL
SELECT
    'SECURITY DEFINER',
    pg_catalog.quote_ident(n.nspname) || '.' || pg_catalog.quote_ident(p.proname)
        || '(' || pg_catalog.pg_get_function_identity_arguments(p.oid) || ')',
    pg_catalog.pg_get_userbyid(p.proowner),
    COALESCE(p.proconfig::text, 'no routine-local configuration')
FROM pg_catalog.pg_proc AS p
JOIN pg_catalog.pg_namespace AS n
    ON n.oid = p.pronamespace
WHERE p.prosecdef
  AND n.nspname <> 'information_schema'
  AND n.nspname !~ '^pg_'
ORDER BY signal_type, object_name;

-- ---------------------------------------------------------------------------
-- 12. Final hard-gate summary
-- ---------------------------------------------------------------------------

\echo ''
\echo '--- [12/12] Final hard-gate summary ---'

SELECT
    pg_catalog.current_setting('server_version_num')::integer / 10000 = 18
        AS postgres_major_is_18,
    pg_catalog.current_database() = :'expected_database' AS database_matches,
    session_user = :'expected_session_user' AS session_user_matches,
    pg_catalog.current_setting('transaction_isolation') = 'repeatable read'
        AS isolation_is_repeatable_read,
    pg_catalog.current_setting('transaction_read_only')::boolean
        AS transaction_is_read_only
\gset final_

SELECT
    :'final_postgres_major_is_18'::boolean AS postgres_major_is_18,
    :'final_database_matches'::boolean AS database_matches,
    :'final_session_user_matches'::boolean AS session_user_matches,
    :'final_isolation_is_repeatable_read'::boolean AS isolation_is_repeatable_read,
    :'final_transaction_is_read_only'::boolean AS transaction_is_read_only;

ROLLBACK;

SELECT
    :'final_postgres_major_is_18'::boolean
    AND :'final_database_matches'::boolean
    AND :'final_session_user_matches'::boolean
    AND :'final_isolation_is_repeatable_read'::boolean
    AND :'final_transaction_is_read_only'::boolean
AS all_hard_gates_passed
\gset final_

\if :final_all_hard_gates_passed
    \echo ''
    \echo 'SAFE-READ acceptance checks completed; all hard gates passed.'
    \echo 'No database objects or configuration were intentionally modified.'
    \echo 'Protect this output because it contains security-sensitive metadata.'
\else
    \echo ''
    \echo 'ERROR: one or more hard gates failed.'
    \quit 4
\endif
