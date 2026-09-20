/*
===============================================================================
Part 4.9 — Effective Privilege Auditing and Access Evidence
Canonical Acceptance Artifact

[TUTORIAL-ACCEPTANCE — SAFE-READ]

Target: PostgreSQL 18

Purpose:
  Collect read-only authorization evidence for the current PostgreSQL
  execution context using PostgreSQL privilege-inquiry functions and catalogs.

Allowed:
  - SELECT
  - has_*_privilege() inquiry functions
  - pg_has_role()
  - row_security_active()
  - pg_roles / pg_auth_members inspection
  - pg_class / pg_namespace / pg_attribute inspection
  - pg_proc / pg_type inspection
  - aclexplode()
  - ownership and role-attribute inspection

Forbidden:
  - SET ROLE / SET SESSION AUTHORIZATION
  - GRANT / REVOKE
  - CREATE / ALTER / DROP
  - CREATE ROLE / ALTER ROLE / DROP ROLE
  - ALTER OWNER
  - application-data modification
  - sequence advancement
  - application routine execution
  - maintenance operations

Important:
  - Effective privilege evidence is broader than explicit ACL evidence.
  - Direct membership is not the complete transitive membership graph.
  - Table privilege does not prove unrestricted row visibility.
  - SAFE-READ output can still contain security-sensitive metadata.
  - Broad catalog scans should be scoped in very large production databases.
===============================================================================
*/

\echo '======================================================================'
\echo 'Part 4.9 — Effective Privilege Auditing and Access Evidence'
\echo '[TUTORIAL-ACCEPTANCE — SAFE-READ]'
\echo '======================================================================'

\echo ''
\echo '1. Execution context'

SELECT
    current_database() AS database_name,
    session_user,
    current_user,
    current_role;

\echo ''
\echo '2. Current role security attributes'

SELECT
    r.oid AS role_oid,
    r.rolname,
    r.rolsuper,
    r.rolinherit,
    r.rolcreaterole,
    r.rolcreatedb,
    r.rolcanlogin,
    r.rolreplication,
    r.rolbypassrls,
    r.rolconnlimit
FROM pg_roles AS r
WHERE r.rolname = current_user;

\echo ''
\echo '3. Direct memberships for current_user'
\echo '   NOTE: direct membership only; not the complete transitive graph'

SELECT
    member_role.rolname AS member_role,
    granted_role.rolname AS granted_role,
    m.admin_option,
    m.inherit_option,
    m.set_option
FROM pg_auth_members AS m
JOIN pg_roles AS granted_role ON granted_role.oid = m.roleid
JOIN pg_roles AS member_role ON member_role.oid = m.member
WHERE member_role.rolname = current_user
ORDER BY granted_role.rolname;

\echo ''
\echo '4. Effective role relationship evidence'

SELECT
    r.rolname AS target_role,
    pg_has_role(current_user, r.oid, 'MEMBER') AS is_member,
    pg_has_role(current_user, r.oid, 'USAGE') AS privileges_available,
    pg_has_role(current_user, r.oid, 'SET') AS can_set_role
FROM pg_roles AS r
WHERE r.rolname <> current_user
  AND (
        pg_has_role(current_user, r.oid, 'MEMBER')
        OR pg_has_role(current_user, r.oid, 'USAGE')
        OR pg_has_role(current_user, r.oid, 'SET')
      )
ORDER BY r.rolname;

\echo ''
\echo '5. Current database privilege evidence'

SELECT
    current_user AS role_name,
    current_database() AS database_name,
    has_database_privilege(current_user, current_database(), 'CONNECT') AS has_connect,
    has_database_privilege(current_user, current_database(), 'CREATE') AS has_create,
    has_database_privilege(current_user, current_database(), 'TEMPORARY') AS has_temporary;

\echo ''
\echo '6. Non-system schema privilege evidence'

SELECT
    n.nspname AS schema_name,
    pg_get_userbyid(n.nspowner) AS schema_owner,
    has_schema_privilege(current_user, n.oid, 'USAGE') AS has_usage,
    has_schema_privilege(current_user, n.oid, 'CREATE') AS has_create
FROM pg_namespace AS n
WHERE n.nspname <> 'information_schema'
  AND n.nspname NOT LIKE 'pg_%'
ORDER BY n.nspname;

\echo ''
\echo '7. Relation ownership, effective privileges, grant option, and RLS'

SELECT
    n.nspname AS schema_name,
    c.relname AS relation_name,
    c.relkind,
    pg_get_userbyid(c.relowner) AS relation_owner,
    has_table_privilege(current_user, c.oid, 'SELECT') AS can_select,
    has_table_privilege(current_user, c.oid, 'SELECT WITH GRANT OPTION') AS can_grant_select,
    has_table_privilege(current_user, c.oid, 'INSERT') AS can_insert,
    has_table_privilege(current_user, c.oid, 'UPDATE') AS can_update,
    has_table_privilege(current_user, c.oid, 'DELETE') AS can_delete,
    has_any_column_privilege(current_user, c.oid, 'SELECT') AS can_select_any_column,
    c.relrowsecurity AS rls_enabled,
    c.relforcerowsecurity AS rls_forced,
    CASE
        WHEN c.relkind IN ('r', 'p') THEN row_security_active(c.oid)
        ELSE NULL
    END AS rls_active_for_current_user
FROM pg_class AS c
JOIN pg_namespace AS n ON n.oid = c.relnamespace
WHERE n.nspname <> 'information_schema'
  AND n.nspname NOT LIKE 'pg_%'
  AND c.relkind IN ('r', 'p', 'v', 'm', 'f')
ORDER BY n.nspname, c.relname;

\echo ''
\echo '8. Column-level effective privilege evidence'

SELECT
    n.nspname AS schema_name,
    c.relname AS relation_name,
    a.attname AS column_name,
    has_column_privilege(current_user, c.oid, a.attnum, 'SELECT') AS can_select,
    has_column_privilege(current_user, c.oid, a.attnum, 'INSERT') AS can_insert,
    has_column_privilege(current_user, c.oid, a.attnum, 'UPDATE') AS can_update
FROM pg_attribute AS a
JOIN pg_class AS c ON c.oid = a.attrelid
JOIN pg_namespace AS n ON n.oid = c.relnamespace
WHERE a.attnum > 0
  AND NOT a.attisdropped
  AND n.nspname <> 'information_schema'
  AND n.nspname NOT LIKE 'pg_%'
  AND c.relkind IN ('r', 'p', 'v', 'm', 'f')
ORDER BY n.nspname, c.relname, a.attnum;

\echo ''
\echo '9. Sequence privilege evidence'

SELECT
    n.nspname AS schema_name,
    c.relname AS sequence_name,
    pg_get_userbyid(c.relowner) AS sequence_owner,
    has_sequence_privilege(current_user, c.oid, 'USAGE') AS has_usage,
    has_sequence_privilege(current_user, c.oid, 'SELECT') AS has_select,
    has_sequence_privilege(current_user, c.oid, 'UPDATE') AS has_update
FROM pg_class AS c
JOIN pg_namespace AS n ON n.oid = c.relnamespace
WHERE c.relkind = 'S'
  AND n.nspname <> 'information_schema'
  AND n.nspname NOT LIKE 'pg_%'
ORDER BY n.nspname, c.relname;

\echo ''
\echo '10. Routine EXECUTE privilege evidence'
\echo '    No application routines are executed.'

SELECT
    n.nspname AS schema_name,
    p.proname AS routine_name,
    pg_get_function_identity_arguments(p.oid) AS identity_arguments,
    pg_get_userbyid(p.proowner) AS routine_owner,
    p.prosecdef AS security_definer,
    has_function_privilege(current_user, p.oid, 'EXECUTE') AS can_execute,
    has_function_privilege(current_user, p.oid, 'EXECUTE WITH GRANT OPTION') AS can_grant_execute
FROM pg_proc AS p
JOIN pg_namespace AS n ON n.oid = p.pronamespace
WHERE n.nspname <> 'information_schema'
  AND n.nspname NOT LIKE 'pg_%'
ORDER BY n.nspname, p.proname, pg_get_function_identity_arguments(p.oid);

\echo ''
\echo '11. User-defined type USAGE privilege evidence'

SELECT
    n.nspname AS schema_name,
    t.typname AS type_name,
    t.typtype,
    pg_get_userbyid(t.typowner) AS type_owner,
    has_type_privilege(current_user, t.oid, 'USAGE') AS has_usage
FROM pg_type AS t
JOIN pg_namespace AS n ON n.oid = t.typnamespace
WHERE n.nspname <> 'information_schema'
  AND n.nspname NOT LIKE 'pg_%'
  AND t.typtype IN ('b', 'c', 'd', 'e', 'r', 'm')
ORDER BY n.nspname, t.typname;

\echo ''
\echo '12. Explicit configured relation ACL evidence'
\echo '    NOTE: absence from this result does not prove absence of access.'

SELECT
    n.nspname AS schema_name,
    c.relname AS relation_name,
    pg_get_userbyid(c.relowner) AS relation_owner,
    CASE WHEN x.grantee = 0 THEN 'PUBLIC' ELSE pg_get_userbyid(x.grantee) END AS grantee,
    pg_get_userbyid(x.grantor) AS grantor,
    x.privilege_type,
    x.is_grantable
FROM pg_class AS c
JOIN pg_namespace AS n ON n.oid = c.relnamespace
CROSS JOIN LATERAL aclexplode(c.relacl) AS x
WHERE n.nspname <> 'information_schema'
  AND n.nspname NOT LIKE 'pg_%'
ORDER BY n.nspname, c.relname, grantee, x.privilege_type;

\echo ''
\echo '13. Relations with Row-Level Security enabled'

SELECT
    n.nspname AS schema_name,
    c.relname AS relation_name,
    pg_get_userbyid(c.relowner) AS relation_owner,
    c.relrowsecurity AS rls_enabled,
    c.relforcerowsecurity AS rls_forced,
    row_security_active(c.oid) AS rls_active_for_current_user
FROM pg_class AS c
JOIN pg_namespace AS n ON n.oid = c.relnamespace
WHERE c.relkind IN ('r', 'p')
  AND c.relrowsecurity
  AND n.nspname <> 'information_schema'
  AND n.nspname NOT LIKE 'pg_%'
ORDER BY n.nspname, c.relname;

\echo ''
\echo '14. Security-sensitive interpretation reminder'

SELECT
    'Effective privilege evidence must be interpreted with ownership, '
    'membership, PUBLIC, predefined roles, role attributes, database/schema '
    'prerequisites, and object-specific security controls. Explicit ACL '
    'evidence alone is not a complete authorization decision.' AS reminder;

\echo ''
\echo '======================================================================'
\echo 'SAFE-READ acceptance check complete.'
\echo 'No roles, grants, ownership, objects, sequences, application routines,'
\echo 'maintenance state, or application data were intentionally modified.'
\echo 'Treat collected authorization evidence as security-sensitive.'
\echo '======================================================================'
