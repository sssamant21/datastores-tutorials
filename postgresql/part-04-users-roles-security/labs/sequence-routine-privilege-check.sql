/*
===============================================================================
Part 4.7 — Sequence, Routine, Type, and Maintenance Privileges
Canonical Acceptance Artifact

[TUTORIAL-ACCEPTANCE — SAFE-READ]

Target: PostgreSQL 18

Purpose:
  Inspect sequence, routine, type, maintenance, and related privilege metadata
  without deliberately changing database state.

SAFETY CONTRACT

Allowed:
  - SELECT catalog metadata
  - pg_get_userbyid()
  - pg_get_function_identity_arguments()
  - has_sequence_privilege()
  - has_function_privilege()
  - has_type_privilege()
  - has_table_privilege()
  - pg_has_role()
  - ACL inspection
  - routine configuration inspection

Forbidden:
  - nextval()
  - setval()
  - application routine execution
  - CALL
  - VACUUM
  - ANALYZE
  - CLUSTER
  - REINDEX
  - REFRESH MATERIALIZED VIEW
  - explicit maintenance LOCK
  - GRANT / REVOKE
  - ALTER DEFAULT PRIVILEGES
  - ownership changes
  - CREATE / ALTER / DROP
  - application-data mutation

Important:
  This artifact reports security-relevant facts. It does not automatically
  classify a SECURITY DEFINER routine without a local search_path as
  vulnerable. Such cases require contextual security review.
===============================================================================
*/

\echo '======================================================================'
\echo 'Part 4.7 — Sequence, Routine, Type, and Maintenance Privilege Check'
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
\echo '2. Sequence inventory, ownership, and ACL'

SELECT
    n.nspname AS schema_name,
    c.relname AS sequence_name,
    pg_get_userbyid(c.relowner) AS owner,
    c.relacl
FROM pg_class AS c
JOIN pg_namespace AS n ON n.oid = c.relnamespace
WHERE c.relkind = 'S'
  AND n.nspname NOT IN ('pg_catalog', 'information_schema')
ORDER BY n.nspname, c.relname;

\echo ''
\echo '3. Effective current-user sequence privileges'

SELECT
    n.nspname AS schema_name,
    c.relname AS sequence_name,
    has_sequence_privilege(current_user, c.oid, 'USAGE') AS has_usage,
    has_sequence_privilege(current_user, c.oid, 'SELECT') AS has_select,
    has_sequence_privilege(current_user, c.oid, 'UPDATE') AS has_update
FROM pg_class AS c
JOIN pg_namespace AS n ON n.oid = c.relnamespace
WHERE c.relkind = 'S'
  AND n.nspname NOT IN ('pg_catalog', 'information_schema')
ORDER BY n.nspname, c.relname;

\echo ''
\echo '4. pg_proc object inventory, ownership, security mode, and ACL'

SELECT
    n.nspname AS schema_name,
    p.proname AS routine_name,
    pg_get_function_identity_arguments(p.oid) AS identity_arguments,
    CASE p.prokind
        WHEN 'f' THEN 'FUNCTION'
        WHEN 'p' THEN 'PROCEDURE'
        WHEN 'a' THEN 'AGGREGATE'
        WHEN 'w' THEN 'WINDOW'
        ELSE p.prokind::text
    END AS routine_kind,
    pg_get_userbyid(p.proowner) AS owner,
    CASE
        WHEN p.prosecdef THEN 'SECURITY DEFINER'
        ELSE 'SECURITY INVOKER'
    END AS security_mode,
    p.proacl
FROM pg_proc AS p
JOIN pg_namespace AS n ON n.oid = p.pronamespace
WHERE n.nspname NOT IN ('pg_catalog', 'information_schema')
ORDER BY n.nspname, p.proname, pg_get_function_identity_arguments(p.oid);

\echo ''
\echo '5. SECURITY DEFINER review inventory'

SELECT
    n.nspname AS schema_name,
    p.proname AS routine_name,
    pg_get_function_identity_arguments(p.oid) AS identity_arguments,
    pg_get_userbyid(p.proowner) AS owner,
    p.proconfig AS routine_configuration,
    CASE
        WHEN EXISTS (
            SELECT 1
            FROM unnest(COALESCE(p.proconfig, ARRAY[]::text[])) AS cfg
            WHERE cfg LIKE 'search_path=%'
        )
        THEN true
        ELSE false
    END AS has_local_search_path,
    p.proacl
FROM pg_proc AS p
JOIN pg_namespace AS n ON n.oid = p.pronamespace
WHERE p.prosecdef
  AND n.nspname NOT IN ('pg_catalog', 'information_schema')
ORDER BY n.nspname, p.proname, pg_get_function_identity_arguments(p.oid);

\echo ''
\echo '6. Effective EXECUTE privilege on pg_proc objects for current user'

SELECT
    n.nspname AS schema_name,
    p.proname AS routine_name,
    pg_get_function_identity_arguments(p.oid) AS identity_arguments,
    CASE p.prokind
        WHEN 'f' THEN 'FUNCTION'
        WHEN 'p' THEN 'PROCEDURE'
        WHEN 'a' THEN 'AGGREGATE'
        WHEN 'w' THEN 'WINDOW'
        ELSE p.prokind::text
    END AS routine_kind,
    has_function_privilege(current_user, p.oid, 'EXECUTE')
        AS current_user_can_execute
FROM pg_proc AS p
JOIN pg_namespace AS n ON n.oid = p.pronamespace
WHERE n.nspname NOT IN ('pg_catalog', 'information_schema')
ORDER BY n.nspname, p.proname, pg_get_function_identity_arguments(p.oid);

\echo ''
\echo '7. PUBLIC EXECUTE exposure'

SELECT
    n.nspname AS schema_name,
    p.proname AS routine_name,
    pg_get_function_identity_arguments(p.oid) AS identity_arguments,
    CASE p.prokind
        WHEN 'f' THEN 'FUNCTION'
        WHEN 'p' THEN 'PROCEDURE'
        WHEN 'a' THEN 'AGGREGATE'
        WHEN 'w' THEN 'WINDOW'
        ELSE p.prokind::text
    END AS routine_kind,
    p.prosecdef AS security_definer,
    has_function_privilege('public', p.oid, 'EXECUTE') AS public_can_execute
FROM pg_proc AS p
JOIN pg_namespace AS n ON n.oid = p.pronamespace
WHERE n.nspname NOT IN ('pg_catalog', 'information_schema')
ORDER BY n.nspname, p.proname, pg_get_function_identity_arguments(p.oid);

\echo ''
\echo '8. User-defined type/domain inventory'

SELECT
    n.nspname AS schema_name,
    t.typname AS type_name,
    CASE t.typtype
        WHEN 'b' THEN 'BASE'
        WHEN 'c' THEN 'COMPOSITE'
        WHEN 'd' THEN 'DOMAIN'
        WHEN 'e' THEN 'ENUM'
        WHEN 'm' THEN 'MULTIRANGE'
        WHEN 'p' THEN 'PSEUDO'
        WHEN 'r' THEN 'RANGE'
        ELSE t.typtype::text
    END AS type_kind,
    pg_get_userbyid(t.typowner) AS owner,
    t.typacl
FROM pg_type AS t
JOIN pg_namespace AS n ON n.oid = t.typnamespace
WHERE n.nspname NOT IN ('pg_catalog', 'information_schema')
  AND t.typtype IN ('b', 'c', 'd', 'e', 'm', 'r')
ORDER BY n.nspname, t.typname;

\echo ''
\echo '9. Effective current-user USAGE on user-defined types/domains'

SELECT
    n.nspname AS schema_name,
    t.typname AS type_name,
    CASE t.typtype
        WHEN 'b' THEN 'BASE'
        WHEN 'c' THEN 'COMPOSITE'
        WHEN 'd' THEN 'DOMAIN'
        WHEN 'e' THEN 'ENUM'
        WHEN 'm' THEN 'MULTIRANGE'
        WHEN 'r' THEN 'RANGE'
        ELSE t.typtype::text
    END AS type_kind,
    has_type_privilege(current_user, t.oid, 'USAGE') AS has_usage
FROM pg_type AS t
JOIN pg_namespace AS n ON n.oid = t.typnamespace
WHERE n.nspname NOT IN ('pg_catalog', 'information_schema')
  AND t.typtype IN ('b', 'c', 'd', 'e', 'm', 'r')
ORDER BY n.nspname, t.typname;

\echo ''
\echo '10. Effective MAINTAIN privilege on user relations'

SELECT
    n.nspname AS schema_name,
    c.relname AS relation_name,
    CASE c.relkind
        WHEN 'r' THEN 'TABLE'
        WHEN 'p' THEN 'PARTITIONED TABLE'
        WHEN 'm' THEN 'MATERIALIZED VIEW'
        WHEN 'f' THEN 'FOREIGN TABLE'
        ELSE c.relkind::text
    END AS relation_kind,
    pg_get_userbyid(c.relowner) AS owner,
    has_table_privilege(current_user, c.oid, 'MAINTAIN') AS has_maintain
FROM pg_class AS c
JOIN pg_namespace AS n ON n.oid = c.relnamespace
WHERE c.relkind IN ('r', 'p', 'm', 'f')
  AND n.nspname NOT IN ('pg_catalog', 'information_schema')
ORDER BY n.nspname, c.relname;

\echo ''
\echo '11. Current-user pg_maintain membership'

SELECT
    current_user,
    pg_has_role(current_user, 'pg_maintain', 'MEMBER')
        AS member_of_pg_maintain;

\echo ''
\echo '12. pg_maintain role metadata'

SELECT
    rolname,
    rolsuper,
    rolinherit,
    rolcreaterole,
    rolcreatedb,
    rolcanlogin
FROM pg_roles
WHERE rolname = 'pg_maintain';

\echo ''
\echo '13. Relevant default privilege metadata'

SELECT
    pg_get_userbyid(d.defaclrole) AS owner_role,
    n.nspname AS schema_name,
    CASE d.defaclobjtype
        WHEN 'r' THEN 'TABLE'
        WHEN 'S' THEN 'SEQUENCE'
        WHEN 'f' THEN 'FUNCTION / ROUTINE'
        WHEN 'T' THEN 'TYPE'
        ELSE d.defaclobjtype::text
    END AS object_type,
    d.defaclacl
FROM pg_default_acl AS d
LEFT JOIN pg_namespace AS n ON n.oid = d.defaclnamespace
WHERE d.defaclobjtype IN ('r', 'S', 'f', 'T')
ORDER BY owner_role, schema_name NULLS FIRST, object_type;

\echo ''
\echo '======================================================================'
\echo 'SAFE-READ acceptance check complete.'
\echo 'No database state was intentionally modified.'
\echo '======================================================================'
