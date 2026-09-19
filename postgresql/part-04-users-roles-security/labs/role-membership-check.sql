/*
===============================================================================
Part 4.3 — Role Membership, Inheritance, and SET ROLE
Canonical Acceptance Artifact

[TUTORIAL-ACCEPTANCE — SAFE-READ]

Target: PostgreSQL 18

Purpose:
  Inspect one declared role's direct and indirect memberships, membership
  options, delegation edges, and reachable powerful attributes without
  changing roles, privileges, session authorization, or database state.

Required psql variables:
  expected_database
  expected_session_user
  target_role
  max_path_depth (integer from 1 through 32)

Safety:
  - Catalog reads and PostgreSQL built-in inspection functions only
  - No CREATE / ALTER / DROP
  - No INSERT / UPDATE / DELETE / MERGE / TRUNCATE
  - No GRANT / REVOKE
  - No SET ROLE / SET SESSION AUTHORIZATION
  - No CALL or arbitrary user-defined function execution
  - No configuration changes

Expected impact:
  Catalog reads inside a REPEATABLE READ, READ ONLY transaction. Recursive
  output volume scales with the number of membership paths. Output contains
  security-sensitive role and delegation metadata and must be protected.
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

\if :{?max_path_depth}
\else
    \echo 'ERROR: required variable max_path_depth is missing.'
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

SELECT CASE
    WHEN :'max_path_depth' ~ '^[1-9][0-9]?$'
    THEN :'max_path_depth'::integer BETWEEN 1 AND 32
    ELSE false
END AS max_path_depth_is_safe
\gset gate_

\if :gate_max_path_depth_is_safe
\else
    \echo 'ERROR: max_path_depth must be an integer from 1 through 32.'
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
\echo 'Part 4.3 — Role Membership Acceptance Check'
\echo '[TUTORIAL-ACCEPTANCE — SAFE-READ]'
\echo '============================================================'
\echo 'NOTICE: output contains security-sensitive membership metadata.'
\echo 'This inventory does not authorize GRANT, REVOKE, or SET ROLE.'

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
    current_role AS current_role,
    :'target_role' AS target_role,
    :max_path_depth::integer AS max_path_depth,
    pg_catalog.current_setting('transaction_isolation') AS transaction_isolation,
    pg_catalog.current_setting('transaction_read_only') AS transaction_read_only;

-- ---------------------------------------------------------------------------
-- 2. Target role attributes
-- ---------------------------------------------------------------------------

\echo ''
\echo '--- [2/10] Target role attributes and membership default ---'

SELECT
    r.oid AS role_oid,
    r.rolname AS role_name,
    r.rolcanlogin,
    r.rolinherit AS new_membership_inherit_default,
    r.rolsuper,
    r.rolcreaterole,
    r.rolcreatedb,
    r.rolreplication,
    r.rolbypassrls
FROM pg_catalog.pg_roles AS r
WHERE r.rolname = :'target_role';

-- rolinherit is the default for newly created membership edges. Existing
-- pg_auth_members.inherit_option values remain authoritative for those edges.

-- ---------------------------------------------------------------------------
-- 3. Direct roles granted to target
-- ---------------------------------------------------------------------------

\echo ''
\echo '--- [3/10] Direct parent roles granted to target_role ---'

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
WHERE member.rolname = :'target_role'
ORDER BY parent.rolname, grantor.rolname;

-- ---------------------------------------------------------------------------
-- 4. Direct members of target
-- ---------------------------------------------------------------------------

\echo ''
\echo '--- [4/10] Direct members of target_role ---'

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
WHERE parent.rolname = :'target_role'
ORDER BY member.rolname, grantor.rolname;

-- ---------------------------------------------------------------------------
-- 5. All upward membership paths
-- ---------------------------------------------------------------------------

\echo ''
\echo '--- [5/10] All upward membership paths from target_role ---'

WITH RECURSIVE paths AS (
    SELECT
        m.roleid AS current_oid,
        ARRAY[member.rolname, parent.rolname]::text[] AS role_path,
        ARRAY[m.member, m.roleid]::oid[] AS visited_role_oids,
        1 AS path_depth,
        m.inherit_option AS inherit_reachable,
        m.set_option AS set_reachable
    FROM pg_catalog.pg_auth_members AS m
    JOIN pg_catalog.pg_roles AS member ON member.oid = m.member
    JOIN pg_catalog.pg_roles AS parent ON parent.oid = m.roleid
    WHERE member.rolname = :'target_role'

    UNION ALL

    SELECT
        m.roleid,
        pg_catalog.array_append(p.role_path, parent.rolname),
        pg_catalog.array_append(p.visited_role_oids, m.roleid),
        p.path_depth + 1,
        p.inherit_reachable AND m.inherit_option,
        p.set_reachable AND m.set_option
    FROM paths AS p
    JOIN pg_catalog.pg_auth_members AS m ON m.member = p.current_oid
    JOIN pg_catalog.pg_roles AS parent ON parent.oid = m.roleid
    WHERE NOT m.roleid = ANY (p.visited_role_oids)
      AND p.path_depth < :max_path_depth
)
SELECT
    path_depth,
    path_depth = :max_path_depth
        AND EXISTS (
            SELECT 1
            FROM pg_catalog.pg_auth_members AS next_membership
            WHERE next_membership.member = paths.current_oid
        ) AS deeper_path_possible,
    pg_catalog.array_to_string(role_path, ' -> ') AS membership_path,
    inherit_reachable,
    set_reachable
FROM paths
ORDER BY path_depth, membership_path;

-- PostgreSQL rejects circular memberships. The visited array remains a
-- defensive guard and makes the recursive termination condition explicit.

-- ---------------------------------------------------------------------------
-- 6. Reachability summary by ancestor role
-- ---------------------------------------------------------------------------

\echo ''
\echo '--- [6/10] Inheritance and SET reachability by ancestor ---'

WITH RECURSIVE paths AS (
    SELECT
        m.roleid AS current_oid,
        m.inherit_option AS inherit_reachable,
        m.set_option AS set_reachable,
        ARRAY[m.member, m.roleid]::oid[] AS visited_role_oids,
        1 AS path_depth
    FROM pg_catalog.pg_auth_members AS m
    JOIN pg_catalog.pg_roles AS member ON member.oid = m.member
    WHERE member.rolname = :'target_role'

    UNION ALL

    SELECT
        m.roleid,
        p.inherit_reachable AND m.inherit_option,
        p.set_reachable AND m.set_option,
        pg_catalog.array_append(p.visited_role_oids, m.roleid),
        p.path_depth + 1
    FROM paths AS p
    JOIN pg_catalog.pg_auth_members AS m ON m.member = p.current_oid
    WHERE NOT m.roleid = ANY (p.visited_role_oids)
      AND p.path_depth < :max_path_depth
)
SELECT
    r.rolname AS ancestor_role,
    pg_catalog.bool_or(p.inherit_reachable) AS reachable_by_any_inherit_path,
    pg_catalog.bool_or(p.set_reachable) AS reachable_by_any_set_path,
    pg_catalog.bool_or(
        p.path_depth = :max_path_depth
        AND EXISTS (
            SELECT 1
            FROM pg_catalog.pg_auth_members AS next_membership
            WHERE next_membership.member = p.current_oid
        )
    ) AS deeper_path_possible,
    pg_catalog.count(*) AS path_count
FROM paths AS p
JOIN pg_catalog.pg_roles AS r ON r.oid = p.current_oid
GROUP BY r.rolname
ORDER BY r.rolname;

-- ---------------------------------------------------------------------------
-- 7. Delegation edges involving target
-- ---------------------------------------------------------------------------

\echo ''
\echo '--- [7/10] ADMIN delegation edges involving target_role ---'

SELECT
    CASE
        WHEN member.rolname = :'target_role' THEN 'TARGET IS MEMBER'
        ELSE 'TARGET IS GRANTED ROLE'
    END AS target_position,
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
WHERE parent.rolname = :'target_role'
   OR member.rolname = :'target_role'
ORDER BY target_position, granted_role, member_role, grantor_role;

-- ---------------------------------------------------------------------------
-- 8. Current session relationship to target
-- ---------------------------------------------------------------------------

\echo ''
\echo '--- [8/10] session_user relationship to target_role ---'

SELECT
    session_user AS evaluated_role,
    :'target_role' AS target_role,
    pg_catalog.pg_has_role(session_user, :'target_role', 'MEMBER')
        AS is_direct_or_indirect_member,
    pg_catalog.pg_has_role(session_user, :'target_role', 'USAGE')
        AS has_privileges_via_inheritance,
    pg_catalog.pg_has_role(session_user, :'target_role', 'SET')
        AS may_set_role,
    pg_catalog.pg_has_role(
        session_user,
        :'target_role',
        'MEMBER WITH ADMIN OPTION'
    ) AS holds_admin_option;

-- This query reports supported PostgreSQL role-membership semantics. It does
-- not execute SET ROLE and does not prove application or external-auth paths.
-- Superuser SET ROLE authority is an independent override and can therefore
-- differ from the ordinary membership paths reported by the recursive queries.

-- ---------------------------------------------------------------------------
-- 9. Powerful attributes reachable through membership
-- ---------------------------------------------------------------------------

\echo ''
\echo '--- [9/10] Reachable ancestor roles with powerful attributes ---'

WITH RECURSIVE paths AS (
    SELECT
        m.roleid AS current_oid,
        m.set_option AS set_reachable,
        ARRAY[m.member, m.roleid]::oid[] AS visited_role_oids,
        1 AS path_depth
    FROM pg_catalog.pg_auth_members AS m
    JOIN pg_catalog.pg_roles AS member ON member.oid = m.member
    WHERE member.rolname = :'target_role'

    UNION ALL

    SELECT
        m.roleid,
        p.set_reachable AND m.set_option,
        pg_catalog.array_append(p.visited_role_oids, m.roleid),
        p.path_depth + 1
    FROM paths AS p
    JOIN pg_catalog.pg_auth_members AS m ON m.member = p.current_oid
    WHERE NOT m.roleid = ANY (p.visited_role_oids)
      AND p.path_depth < :max_path_depth
)
SELECT
    r.rolname AS ancestor_role,
    pg_catalog.bool_or(p.set_reachable) AS reachable_by_set_path,
    pg_catalog.bool_or(
        p.path_depth = :max_path_depth
        AND EXISTS (
            SELECT 1
            FROM pg_catalog.pg_auth_members AS next_membership
            WHERE next_membership.member = p.current_oid
        )
    ) AS deeper_path_possible,
    r.rolsuper,
    r.rolcreaterole,
    r.rolcreatedb,
    r.rolreplication,
    r.rolbypassrls
FROM paths AS p
JOIN pg_catalog.pg_roles AS r ON r.oid = p.current_oid
WHERE r.rolsuper
   OR r.rolcreaterole
   OR r.rolcreatedb
   OR r.rolreplication
   OR r.rolbypassrls
GROUP BY
    r.rolname,
    r.rolsuper,
    r.rolcreaterole,
    r.rolcreatedb,
    r.rolreplication,
    r.rolbypassrls
ORDER BY r.rolname;

-- Special role attributes are not ordinary inherited object privileges.
-- A reachable SET path is a separate, high-value review signal.
-- deeper_path_possible means the configured depth truncated known ancestry.

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
    \echo 'No roles, memberships, privileges, or session identities were changed.'
    \echo 'Protect this output because it contains security-sensitive metadata.'
\else
    \echo ''
    \echo 'ERROR: one or more hard gates failed.'
    \quit 4
\endif
