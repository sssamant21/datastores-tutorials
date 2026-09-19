/*
===============================================================================
Part 4.2 — Role Creation, Attributes, and Lifecycle Administration
Canonical Acceptance Artifact

[TUTORIAL-ACCEPTANCE — SAFE-READ]

Target: PostgreSQL 18

Purpose:
  Inspect one declared role's attributes, memberships, configuration,
  ownership, explicit grants, default ACLs, and dependency signals without
  changing database state.

Required psql variables:
  expected_database
  expected_session_user
  target_role

Safety:
  - Catalog reads and PostgreSQL built-in inspection functions only
  - No CREATE / ALTER / DROP
  - No INSERT / UPDATE / DELETE / MERGE / TRUNCATE
  - No GRANT / REVOKE
  - No SET ROLE / SET SESSION AUTHORIZATION
  - No CALL or arbitrary user-defined function execution
  - No password/verifier reads from pg_authid
  - No configuration changes

Expected impact:
  Catalog reads inside a REPEATABLE READ, READ ONLY transaction. Runtime and
  output volume scale with dependency and ACL counts. Output contains
  security-sensitive metadata and must be protected.
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

\if :{?target_role}
\else
    \echo 'ERROR: required variable target_role is missing.'
    \quit 3
\endif

SELECT
    :'expected_database' ~ '^[a-z_][a-z0-9_]*$'
    AND :'expected_session_user' ~ '^[a-z_][a-z0-9_]*$'
    AND :'target_role' ~ '^[a-z_][a-z0-9_]*$'
AS inputs_are_safe
\gset gate_

\if :gate_inputs_are_safe
\else
    \echo 'ERROR: expected values and target_role must be simple lowercase identifiers.'
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

SELECT pg_catalog.count(*) = 1 AS target_role_exists
FROM pg_catalog.pg_roles
WHERE rolname = :'target_role'
\gset gate_

\if :gate_target_role_exists
\else
    \echo 'ERROR: target_role does not exist in this PostgreSQL cluster.'
    \quit 3
\endif

BEGIN TRANSACTION ISOLATION LEVEL REPEATABLE READ READ ONLY;

\echo ''
\echo '============================================================'
\echo 'Part 4.2 — Role Lifecycle Acceptance Check'
\echo '[TUTORIAL-ACCEPTANCE — SAFE-READ]'
\echo '============================================================'
\echo 'NOTICE: output contains security-sensitive metadata.'
\echo 'Protect, redact, retain, and dispose of it under approved policy.'
\echo 'This inventory does not authorize ALTER ROLE, DROP OWNED, or DROP ROLE.'

-- ---------------------------------------------------------------------------
-- 1. Hard-gate context
-- ---------------------------------------------------------------------------

\echo ''
\echo '--- [1/10] Version, transaction, identity, and target context ---'

SELECT
    pg_catalog.current_setting('server_version') AS server_version,
    pg_catalog.current_setting('server_version_num') AS server_version_num,
    pg_catalog.current_database() AS database_name,
    system_user AS authenticated_system_identity,
    session_user AS session_user,
    current_user AS current_user,
    :'target_role' AS target_role,
    pg_catalog.current_setting('transaction_isolation') AS transaction_isolation,
    pg_catalog.current_setting('transaction_read_only') AS transaction_read_only;

-- ---------------------------------------------------------------------------
-- 2. Target role attributes
-- ---------------------------------------------------------------------------

\echo ''
\echo '--- [2/10] Target role attributes ---'

SELECT
    r.oid AS role_oid,
    r.rolname AS role_name,
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
WHERE r.rolname = :'target_role';

-- pg_roles masks password contents. This artifact intentionally does not
-- query pg_authid or attempt to prove authentication readiness.

-- ---------------------------------------------------------------------------
-- 3. Capability review signals
-- ---------------------------------------------------------------------------

\echo ''
\echo '--- [3/10] Capability review signals ---'

SELECT
    r.rolname AS role_name,
    signal.capability,
    signal.enabled,
    CASE signal.capability
        WHEN 'SUPERUSER' THEN 'critical: bypasses nearly all permission checks'
        WHEN 'BYPASSRLS' THEN 'critical: bypasses every row-security policy'
        WHEN 'REPLICATION' THEN 'high: replication and slot capability'
        WHEN 'CREATEROLE' THEN 'high: delegated role administration'
        WHEN 'CREATEDB' THEN 'elevated: database creation'
        WHEN 'LOGIN' THEN 'review: usable as an initial connection identity'
    END AS review_reason
FROM pg_catalog.pg_roles AS r
CROSS JOIN LATERAL (
    VALUES
        ('SUPERUSER', r.rolsuper),
        ('BYPASSRLS', r.rolbypassrls),
        ('REPLICATION', r.rolreplication),
        ('CREATEROLE', r.rolcreaterole),
        ('CREATEDB', r.rolcreatedb),
        ('LOGIN', r.rolcanlogin)
) AS signal(capability, enabled)
WHERE r.rolname = :'target_role'
ORDER BY signal.capability;

-- ---------------------------------------------------------------------------
-- 4. Role configuration defaults
-- ---------------------------------------------------------------------------

\echo ''
\echo '--- [4/10] Role and database-role configuration defaults ---'

SELECT
    CASE
        WHEN s.setdatabase = 0 THEN 'ROLE-WIDE'
        ELSE 'ROLE-IN-DATABASE'
    END AS setting_scope,
    r.rolname AS role_name,
    d.datname AS database_name,
    CASE
        WHEN pg_catalog.split_part(cfg.setting, '=', 1) = ANY (ARRAY[
            'search_path',
            'statement_timeout',
            'lock_timeout',
            'idle_in_transaction_session_timeout',
            'idle_session_timeout',
            'client_min_messages',
            'log_min_duration_statement',
            'log_statement',
            'row_security',
            'default_transaction_read_only'
        ])
        THEN cfg.setting
        ELSE pg_catalog.split_part(cfg.setting, '=', 1) || '=<redacted>'
    END AS setting
FROM pg_catalog.pg_db_role_setting AS s
JOIN pg_catalog.pg_roles AS r
    ON r.oid = s.setrole
LEFT JOIN pg_catalog.pg_database AS d
    ON d.oid = s.setdatabase
CROSS JOIN LATERAL pg_catalog.unnest(s.setconfig) AS cfg(setting)
WHERE r.rolname = :'target_role'
ORDER BY setting_scope, database_name, setting;

-- Values are shown only for the explicit operational allowlist above.
-- Arbitrary custom settings can contain sensitive data and are redacted.

-- ---------------------------------------------------------------------------
-- 5. Roles granted to the target
-- ---------------------------------------------------------------------------

\echo ''
\echo '--- [5/10] Direct roles granted to target_role ---'

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
WHERE member.rolname = :'target_role'
ORDER BY parent.rolname, grantor.rolname;

-- ---------------------------------------------------------------------------
-- 6. Members of the target
-- ---------------------------------------------------------------------------

\echo ''
\echo '--- [6/10] Direct members of target_role ---'

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
WHERE parent.rolname = :'target_role'
ORDER BY member.rolname, grantor.rolname;

-- ---------------------------------------------------------------------------
-- 7. Current-database ownership
-- ---------------------------------------------------------------------------

\echo ''
\echo '--- [7/10] Current-database ownership counts ---'

WITH target AS (
    SELECT oid
    FROM pg_catalog.pg_roles
    WHERE rolname = :'target_role'
),
owned AS (
    SELECT 'DATABASE'::text AS object_type
    FROM pg_catalog.pg_database AS d, target
    WHERE d.datname = pg_catalog.current_database()
      AND d.datdba = target.oid
    UNION ALL
    SELECT 'SCHEMA'
    FROM pg_catalog.pg_namespace AS n, target
    WHERE n.nspowner = target.oid
    UNION ALL
    SELECT CASE c.relkind
        WHEN 'r' THEN 'TABLE'
        WHEN 'p' THEN 'PARTITIONED TABLE'
        WHEN 'v' THEN 'VIEW'
        WHEN 'm' THEN 'MATERIALIZED VIEW'
        WHEN 'S' THEN 'SEQUENCE'
        WHEN 'f' THEN 'FOREIGN TABLE'
        ELSE 'RELATION (' || c.relkind || ')'
    END
    FROM pg_catalog.pg_class AS c, target
    WHERE c.relowner = target.oid
    UNION ALL
    SELECT 'ROUTINE'
    FROM pg_catalog.pg_proc AS p, target
    WHERE p.proowner = target.oid
    UNION ALL
    SELECT 'TYPE'
    FROM pg_catalog.pg_type AS t, target
    WHERE t.typowner = target.oid
)
SELECT object_type, pg_catalog.count(*) AS object_count
FROM owned
GROUP BY object_type
ORDER BY object_type;

-- ---------------------------------------------------------------------------
-- 8. Explicit grants and default ACL entries
-- ---------------------------------------------------------------------------

\echo ''
\echo '--- [8/10] Explicit ACL entries granted to target_role ---'

WITH target AS (
    SELECT oid
    FROM pg_catalog.pg_roles
    WHERE rolname = :'target_role'
),
grants AS (
    SELECT
        'DATABASE'::text AS object_type,
        d.datname AS object_name,
        x.privilege_type,
        x.is_grantable,
        pg_catalog.pg_get_userbyid(x.grantor) AS grantor
    FROM pg_catalog.pg_database AS d
    CROSS JOIN LATERAL pg_catalog.aclexplode(d.datacl) AS x
    CROSS JOIN target
    WHERE d.datname = pg_catalog.current_database()
      AND x.grantee = target.oid
    UNION ALL
    SELECT
        'SCHEMA',
        n.nspname,
        x.privilege_type,
        x.is_grantable,
        pg_catalog.pg_get_userbyid(x.grantor)
    FROM pg_catalog.pg_namespace AS n
    CROSS JOIN LATERAL pg_catalog.aclexplode(n.nspacl) AS x
    CROSS JOIN target
    WHERE x.grantee = target.oid
    UNION ALL
    SELECT
        CASE WHEN c.relkind = 'S' THEN 'SEQUENCE' ELSE 'RELATION' END,
        pg_catalog.quote_ident(n.nspname) || '.' || pg_catalog.quote_ident(c.relname),
        x.privilege_type,
        x.is_grantable,
        pg_catalog.pg_get_userbyid(x.grantor)
    FROM pg_catalog.pg_class AS c
    JOIN pg_catalog.pg_namespace AS n
        ON n.oid = c.relnamespace
    CROSS JOIN LATERAL pg_catalog.aclexplode(c.relacl) AS x
    CROSS JOIN target
    WHERE x.grantee = target.oid
    UNION ALL
    SELECT
        'ROUTINE',
        pg_catalog.quote_ident(n.nspname) || '.' || pg_catalog.quote_ident(p.proname)
            || '(' || pg_catalog.pg_get_function_identity_arguments(p.oid) || ')',
        x.privilege_type,
        x.is_grantable,
        pg_catalog.pg_get_userbyid(x.grantor)
    FROM pg_catalog.pg_proc AS p
    JOIN pg_catalog.pg_namespace AS n
        ON n.oid = p.pronamespace
    CROSS JOIN LATERAL pg_catalog.aclexplode(p.proacl) AS x
    CROSS JOIN target
    WHERE x.grantee = target.oid
    UNION ALL
    SELECT
        'DEFAULT ACL',
        pg_catalog.pg_get_userbyid(a.defaclrole)
            || ':' || CASE a.defaclobjtype
                WHEN 'r' THEN 'RELATION'
                WHEN 'S' THEN 'SEQUENCE'
                WHEN 'f' THEN 'FUNCTION'
                WHEN 'T' THEN 'TYPE'
                WHEN 'n' THEN 'SCHEMA'
                WHEN 'L' THEN 'LARGE OBJECT'
                ELSE 'UNKNOWN (' || a.defaclobjtype || ')'
            END
            || ':' || COALESCE(n.nspname, '<all schemas>'),
        x.privilege_type,
        x.is_grantable,
        pg_catalog.pg_get_userbyid(x.grantor)
    FROM pg_catalog.pg_default_acl AS a
    LEFT JOIN pg_catalog.pg_namespace AS n
        ON n.oid = a.defaclnamespace
    CROSS JOIN LATERAL pg_catalog.aclexplode(a.defaclacl) AS x
    CROSS JOIN target
    WHERE x.grantee = target.oid
)
SELECT object_type, object_name, privilege_type, is_grantable, grantor
FROM grants
ORDER BY object_type, object_name, privilege_type, grantor;

-- Only explicit stored ACL entries are expanded. Ownership, PUBLIC, inherited
-- access, and built-in defaults are separate access paths.

-- ---------------------------------------------------------------------------
-- 9. Shared dependency signals
-- ---------------------------------------------------------------------------

\echo ''
\echo '--- [9/10] Shared dependency signals relevant to role removal ---'

WITH target AS (
    SELECT oid
    FROM pg_catalog.pg_roles
    WHERE rolname = :'target_role'
)
SELECT
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
CROSS JOIN target
LEFT JOIN pg_catalog.pg_database AS d
    ON d.oid = sd.dbid
WHERE sd.refclassid = 'pg_catalog.pg_authid'::pg_catalog.regclass
  AND sd.refobjid = target.oid
GROUP BY dependency_database, dependency_type
ORDER BY dependency_database, dependency_type;

-- This is a planning signal, not a complete DROP ROLE simulation. Resolve
-- ownership and grants in every database and use a reviewed retirement plan.

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
    EXISTS (
        SELECT 1
        FROM pg_catalog.pg_roles
        WHERE rolname = :'target_role'
    ) AS target_role_exists,
    pg_catalog.current_setting('transaction_isolation') = 'repeatable read'
        AS isolation_is_repeatable_read,
    pg_catalog.current_setting('transaction_read_only')::boolean
        AS transaction_is_read_only
\gset final_

SELECT
    :'final_postgres_major_is_18'::boolean AS postgres_major_is_18,
    :'final_database_matches'::boolean AS database_matches,
    :'final_session_user_matches'::boolean AS session_user_matches,
    :'final_target_role_exists'::boolean AS target_role_exists,
    :'final_isolation_is_repeatable_read'::boolean AS isolation_is_repeatable_read,
    :'final_transaction_is_read_only'::boolean AS transaction_is_read_only;

ROLLBACK;

SELECT
    :'final_postgres_major_is_18'::boolean
    AND :'final_database_matches'::boolean
    AND :'final_session_user_matches'::boolean
    AND :'final_target_role_exists'::boolean
    AND :'final_isolation_is_repeatable_read'::boolean
    AND :'final_transaction_is_read_only'::boolean
AS all_hard_gates_passed
\gset final_

\if :final_all_hard_gates_passed
    \echo ''
    \echo 'SAFE-READ acceptance checks completed; all hard gates passed.'
    \echo 'No roles, memberships, objects, privileges, or settings were modified.'
    \echo 'Protect this output because it contains security-sensitive metadata.'
    \echo 'Treat dependency results as planning evidence, not drop authorization.'
\else
    \echo ''
    \echo 'ERROR: one or more hard gates failed.'
    \quit 4
\endif
