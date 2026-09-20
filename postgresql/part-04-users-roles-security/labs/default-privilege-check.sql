/*
===============================================================================
Part 4.8 — Default Privileges and Future-Object Access
Canonical Acceptance Artifact

[TUTORIAL-ACCEPTANCE — SAFE-READ]

Target: PostgreSQL 18

Purpose:
  Inspect customized default privileges, creator roles, schema scope,
  object classes, and expanded ACL entries without changing database state.

Allowed:
  - SELECT
  - pg_get_userbyid()
  - pg_default_acl inspection
  - pg_namespace inspection
  - pg_roles inspection
  - aclexplode()
  - aggregation of catalog results

Forbidden:
  - ALTER DEFAULT PRIVILEGES
  - GRANT / REVOKE
  - CREATE / ALTER / DROP
  - SET ROLE
  - SET SESSION AUTHORIZATION
  - ALTER OWNER
  - CREATE ROLE / DROP ROLE
  - application-data modification

Notes:
  - pg_default_acl contains customized default privilege configuration.
  - Global and per-schema entries have different semantics.
  - ACL expansion does not by itself prove complete effective access.
  - Large-object default privileges are supported by PostgreSQL 18.
===============================================================================
*/

\echo '======================================================================'
\echo 'Part 4.8 — Default Privileges and Future-Object Access'
\echo '[TUTORIAL-ACCEPTANCE — SAFE-READ]'
\echo '======================================================================'

\echo ''
\echo '1. Session identity'

SELECT
    current_database() AS database_name,
    session_user,
    current_user,
    current_role;

\echo ''
\echo '2. Complete customized default-privilege inventory'

SELECT
    d.oid AS default_acl_oid,
    pg_get_userbyid(d.defaclrole) AS creator_role,
    CASE
        WHEN d.defaclnamespace = 0 THEN '<GLOBAL>'
        ELSE n.nspname
    END AS scope,
    CASE d.defaclobjtype
        WHEN 'r' THEN 'TABLE'
        WHEN 'S' THEN 'SEQUENCE'
        WHEN 'f' THEN 'ROUTINE'
        WHEN 'T' THEN 'TYPE'
        WHEN 'n' THEN 'SCHEMA'
        WHEN 'L' THEN 'LARGE OBJECT'
        ELSE d.defaclobjtype::text
    END AS object_type,
    d.defaclacl
FROM pg_default_acl AS d
LEFT JOIN pg_namespace AS n
    ON n.oid = d.defaclnamespace
ORDER BY creator_role, d.defaclnamespace, object_type;

\echo ''
\echo '3. Global customized default privileges'

SELECT
    pg_get_userbyid(d.defaclrole) AS creator_role,
    CASE d.defaclobjtype
        WHEN 'r' THEN 'TABLE'
        WHEN 'S' THEN 'SEQUENCE'
        WHEN 'f' THEN 'ROUTINE'
        WHEN 'T' THEN 'TYPE'
        WHEN 'n' THEN 'SCHEMA'
        WHEN 'L' THEN 'LARGE OBJECT'
        ELSE d.defaclobjtype::text
    END AS object_type,
    d.defaclacl
FROM pg_default_acl AS d
WHERE d.defaclnamespace = 0
ORDER BY creator_role, object_type;

\echo ''
\echo '4. Schema-scoped customized default privileges'

SELECT
    pg_get_userbyid(d.defaclrole) AS creator_role,
    n.nspname AS schema_name,
    CASE d.defaclobjtype
        WHEN 'r' THEN 'TABLE'
        WHEN 'S' THEN 'SEQUENCE'
        WHEN 'f' THEN 'ROUTINE'
        WHEN 'T' THEN 'TYPE'
        ELSE d.defaclobjtype::text
    END AS object_type,
    d.defaclacl
FROM pg_default_acl AS d
JOIN pg_namespace AS n
    ON n.oid = d.defaclnamespace
WHERE d.defaclnamespace <> 0
ORDER BY creator_role, schema_name, object_type;

\echo ''
\echo '5. Expanded default ACL entries'

SELECT
    pg_get_userbyid(d.defaclrole) AS creator_role,
    CASE
        WHEN d.defaclnamespace = 0 THEN '<GLOBAL>'
        ELSE n.nspname
    END AS scope,
    CASE d.defaclobjtype
        WHEN 'r' THEN 'TABLE'
        WHEN 'S' THEN 'SEQUENCE'
        WHEN 'f' THEN 'ROUTINE'
        WHEN 'T' THEN 'TYPE'
        WHEN 'n' THEN 'SCHEMA'
        WHEN 'L' THEN 'LARGE OBJECT'
        ELSE d.defaclobjtype::text
    END AS object_type,
    CASE
        WHEN x.grantee = 0 THEN 'PUBLIC'
        ELSE pg_get_userbyid(x.grantee)
    END AS grantee,
    pg_get_userbyid(x.grantor) AS grantor,
    x.privilege_type,
    x.is_grantable
FROM pg_default_acl AS d
LEFT JOIN pg_namespace AS n
    ON n.oid = d.defaclnamespace
CROSS JOIN LATERAL aclexplode(d.defaclacl) AS x
ORDER BY creator_role, d.defaclnamespace, object_type, grantee, x.privilege_type;

\echo ''
\echo '6. Customized default privileges granted to PUBLIC'

SELECT
    pg_get_userbyid(d.defaclrole) AS creator_role,
    CASE
        WHEN d.defaclnamespace = 0 THEN '<GLOBAL>'
        ELSE n.nspname
    END AS scope,
    CASE d.defaclobjtype
        WHEN 'r' THEN 'TABLE'
        WHEN 'S' THEN 'SEQUENCE'
        WHEN 'f' THEN 'ROUTINE'
        WHEN 'T' THEN 'TYPE'
        WHEN 'n' THEN 'SCHEMA'
        WHEN 'L' THEN 'LARGE OBJECT'
        ELSE d.defaclobjtype::text
    END AS object_type,
    x.privilege_type,
    x.is_grantable
FROM pg_default_acl AS d
LEFT JOIN pg_namespace AS n
    ON n.oid = d.defaclnamespace
CROSS JOIN LATERAL aclexplode(d.defaclacl) AS x
WHERE x.grantee = 0
ORDER BY creator_role, d.defaclnamespace, object_type, x.privilege_type;

\echo ''
\echo '7. Roles owning customized default privilege configurations'

SELECT DISTINCT
    r.rolname AS creator_role,
    r.rolsuper,
    r.rolinherit,
    r.rolcreaterole,
    r.rolcreatedb,
    r.rolcanlogin
FROM pg_default_acl AS d
JOIN pg_roles AS r
    ON r.oid = d.defaclrole
ORDER BY r.rolname;

\echo ''
\echo '8. Schemas referenced by schema-scoped defaults'

SELECT DISTINCT
    n.nspname AS schema_name,
    pg_get_userbyid(n.nspowner) AS schema_owner
FROM pg_default_acl AS d
JOIN pg_namespace AS n
    ON n.oid = d.defaclnamespace
WHERE d.defaclnamespace <> 0
ORDER BY n.nspname;

\echo ''
\echo '9. Default privilege entry counts by creator, scope, and object type'

SELECT
    pg_get_userbyid(d.defaclrole) AS creator_role,
    CASE
        WHEN d.defaclnamespace = 0 THEN '<GLOBAL>'
        ELSE n.nspname
    END AS scope,
    CASE d.defaclobjtype
        WHEN 'r' THEN 'TABLE'
        WHEN 'S' THEN 'SEQUENCE'
        WHEN 'f' THEN 'ROUTINE'
        WHEN 'T' THEN 'TYPE'
        WHEN 'n' THEN 'SCHEMA'
        WHEN 'L' THEN 'LARGE OBJECT'
        ELSE d.defaclobjtype::text
    END AS object_type,
    count(*) AS default_acl_entries
FROM pg_default_acl AS d
LEFT JOIN pg_namespace AS n
    ON n.oid = d.defaclnamespace
GROUP BY
    d.defaclrole,
    pg_get_userbyid(d.defaclrole),
    d.defaclnamespace,
    n.nspname,
    d.defaclobjtype
ORDER BY creator_role, d.defaclnamespace, object_type;

\echo ''
\echo '10. SAFE-READ interpretation reminder'

SELECT
    'pg_default_acl describes customized default ACL configuration; '
    'it does not by itself prove complete effective access.' AS reminder;

\echo ''
\echo '======================================================================'
\echo 'SAFE-READ acceptance check complete.'
\echo 'No default privileges, roles, ownership, objects, or application data'
\echo 'were intentionally modified.'
\echo '======================================================================'
