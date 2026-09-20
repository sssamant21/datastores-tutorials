/*
===============================================================================
Part 4.14 — Security Baseline, Drift Detection, and Access Validation
Canonical Acceptance Artifact

[TUTORIAL-ACCEPTANCE — SAFE-READ]

Target: PostgreSQL 18

Purpose:
  Collect bounded, repeatable database/catalog security evidence for baseline
  and drift review.

Scope:
  Application-focused catalog evidence. System schemas are intentionally
  excluded from application-object inventories. This is not a complete
  cluster-wide security audit.

Safety:
  - No role or membership changes.
  - No GRANT / REVOKE.
  - No ownership changes.
  - No RLS changes.
  - No ALTER SYSTEM.
  - No HBA/TLS changes or reload.
  - No password-verifier inspection.
  - No SET ROLE.
  - No external authentication tests.
  - No automatic remediation.
  - No session termination.

Evidence sensitivity:
  SAFE-READ != safe to publish.
===============================================================================
*/

\echo '======================================================================'
\echo 'Part 4.14 — Security Baseline, Drift Detection, and Access Validation'
\echo '[TUTORIAL-ACCEPTANCE — SAFE-READ]'
\echo '======================================================================'

\echo '1. Execution and server context'
SELECT
    current_database() AS database_name,
    session_user,
    current_user,
    current_role,
    current_setting('server_version') AS server_version;

\echo '2. Role attribute baseline'
SELECT
    rolname,
    rolcanlogin,
    rolsuper,
    rolinherit,
    rolcreaterole,
    rolcreatedb,
    rolreplication,
    rolbypassrls,
    rolconnlimit,
    rolvaliduntil
FROM pg_roles
ORDER BY rolname;

\echo '3. Role membership baseline — PostgreSQL 18 membership options'
SELECT
    member_role.rolname AS member_name,
    granted_role.rolname AS granted_role_name,
    grantor_role.rolname AS grantor_name,
    m.admin_option,
    m.inherit_option,
    m.set_option
FROM pg_auth_members AS m
JOIN pg_roles AS member_role
  ON member_role.oid = m.member
JOIN pg_roles AS granted_role
  ON granted_role.oid = m.roleid
LEFT JOIN pg_roles AS grantor_role
  ON grantor_role.oid = m.grantor
ORDER BY member_name, granted_role_name, grantor_name;

\echo '4. Database ownership and ACL baseline'
SELECT
    d.datname,
    pg_get_userbyid(d.datdba) AS owner_name,
    d.datallowconn,
    d.datconnlimit,
    d.datacl
FROM pg_database AS d
ORDER BY d.datname;

\echo '5. Non-system schema ownership and ACL baseline'
SELECT
    n.nspname AS schema_name,
    pg_get_userbyid(n.nspowner) AS owner_name,
    n.nspacl
FROM pg_namespace AS n
WHERE n.nspname NOT LIKE 'pg_%'
  AND n.nspname <> 'information_schema'
ORDER BY n.nspname;

\echo '6. Non-system relation ownership, type, RLS state, and ACL baseline'
SELECT
    n.nspname AS schema_name,
    c.relname AS relation_name,
    c.relkind,
    CASE c.relkind
      WHEN 'r' THEN 'table'
      WHEN 'p' THEN 'partitioned table'
      WHEN 'v' THEN 'view'
      WHEN 'm' THEN 'materialized view'
      WHEN 'f' THEN 'foreign table'
      ELSE c.relkind::text
    END AS relation_type,
    pg_get_userbyid(c.relowner) AS owner_name,
    c.relrowsecurity,
    c.relforcerowsecurity,
    c.relacl
FROM pg_class AS c
JOIN pg_namespace AS n ON n.oid = c.relnamespace
WHERE n.nspname NOT LIKE 'pg_%'
  AND n.nspname <> 'information_schema'
  AND c.relkind IN ('r','p','v','m','f')
ORDER BY n.nspname, c.relname, c.relkind;

\echo '7. Dedicated sequence ownership and ACL baseline'
SELECT
    n.nspname AS schema_name,
    c.relname AS sequence_name,
    pg_get_userbyid(c.relowner) AS owner_name,
    c.relacl
FROM pg_class AS c
JOIN pg_namespace AS n ON n.oid = c.relnamespace
WHERE c.relkind = 'S'
  AND n.nspname NOT LIKE 'pg_%'
  AND n.nspname <> 'information_schema'
ORDER BY n.nspname, c.relname;

\echo '8. Column ACL evidence'
SELECT
    n.nspname AS schema_name,
    c.relname AS relation_name,
    a.attname AS column_name,
    a.attacl
FROM pg_attribute AS a
JOIN pg_class AS c ON c.oid = a.attrelid
JOIN pg_namespace AS n ON n.oid = c.relnamespace
WHERE a.attnum > 0
  AND NOT a.attisdropped
  AND a.attacl IS NOT NULL
  AND n.nspname NOT LIKE 'pg_%'
  AND n.nspname <> 'information_schema'
ORDER BY n.nspname, c.relname, a.attnum;

\echo '9. Routine security, kind, ownership, ACL, and configuration baseline'
SELECT
    n.nspname AS schema_name,
    p.proname AS routine_name,
    pg_get_function_identity_arguments(p.oid) AS identity_arguments,
    p.prokind,
    CASE p.prokind
      WHEN 'f' THEN 'function'
      WHEN 'p' THEN 'procedure'
      WHEN 'a' THEN 'aggregate'
      WHEN 'w' THEN 'window function'
      ELSE p.prokind::text
    END AS routine_kind,
    pg_get_userbyid(p.proowner) AS owner_name,
    p.prosecdef AS security_definer,
    p.proacl,
    p.proconfig
FROM pg_proc AS p
JOIN pg_namespace AS n ON n.oid = p.pronamespace
WHERE n.nspname NOT LIKE 'pg_%'
  AND n.nspname <> 'information_schema'
ORDER BY
    n.nspname,
    p.proname,
    pg_get_function_identity_arguments(p.oid);

\echo '10. Default privilege baseline'
SELECT
    pg_get_userbyid(d.defaclrole) AS creator_role,
    COALESCE(n.nspname, '<all-schemas>') AS schema_scope,
    d.defaclobjtype,
    CASE d.defaclobjtype
      WHEN 'r' THEN 'relation'
      WHEN 'S' THEN 'sequence'
      WHEN 'f' THEN 'function'
      WHEN 'T' THEN 'type'
      WHEN 'n' THEN 'schema'
      WHEN 'L' THEN 'large object'
      ELSE d.defaclobjtype::text
    END AS object_type,
    d.defaclacl
FROM pg_default_acl AS d
LEFT JOIN pg_namespace AS n ON n.oid = d.defaclnamespace
ORDER BY creator_role, schema_scope, d.defaclobjtype;

\echo '11. Row-level security policy baseline'
SELECT
    schemaname,
    tablename,
    policyname,
    permissive,
    roles,
    cmd,
    qual,
    with_check
FROM pg_policies
WHERE schemaname NOT LIKE 'pg_%'
  AND schemaname <> 'information_schema'
ORDER BY schemaname, tablename, policyname;

\echo '12. SECURITY DEFINER review inventory'
SELECT
    n.nspname AS schema_name,
    p.proname AS routine_name,
    pg_get_function_identity_arguments(p.oid) AS identity_arguments,
    CASE p.prokind
      WHEN 'f' THEN 'function'
      WHEN 'p' THEN 'procedure'
      WHEN 'a' THEN 'aggregate'
      WHEN 'w' THEN 'window function'
      ELSE p.prokind::text
    END AS routine_kind,
    pg_get_userbyid(p.proowner) AS owner_name,
    p.proacl,
    p.proconfig
FROM pg_proc AS p
JOIN pg_namespace AS n ON n.oid = p.pronamespace
WHERE p.prosecdef
  AND n.nspname NOT LIKE 'pg_%'
  AND n.nspname <> 'information_schema'
ORDER BY
    n.nspname,
    p.proname,
    pg_get_function_identity_arguments(p.oid);

\echo '13. High-impact role attribute review signals'
SELECT
    rolname,
    rolsuper,
    rolcreaterole,
    rolcreatedb,
    rolreplication,
    rolbypassrls
FROM pg_roles
WHERE rolsuper
   OR rolcreaterole
   OR rolcreatedb
   OR rolreplication
   OR rolbypassrls
ORDER BY rolname;

\echo '14. PUBLIC database privilege checks'
SELECT
    d.datname,
    has_database_privilege('public', d.oid, 'CONNECT') AS public_connect,
    has_database_privilege('public', d.oid, 'TEMPORARY') AS public_temporary
FROM pg_database AS d
ORDER BY d.datname;

\echo '15. PUBLIC non-system schema privilege checks'
SELECT
    n.nspname AS schema_name,
    has_schema_privilege('public', n.oid, 'USAGE') AS public_usage,
    has_schema_privilege('public', n.oid, 'CREATE') AS public_create
FROM pg_namespace AS n
WHERE n.nspname NOT LIKE 'pg_%'
  AND n.nspname <> 'information_schema'
ORDER BY n.nspname;

\echo '16. PUBLIC sequence privilege checks'
SELECT
    n.nspname AS schema_name,
    c.relname AS sequence_name,
    has_sequence_privilege('public', c.oid, 'USAGE') AS public_usage,
    has_sequence_privilege('public', c.oid, 'SELECT') AS public_select,
    has_sequence_privilege('public', c.oid, 'UPDATE') AS public_update
FROM pg_class AS c
JOIN pg_namespace AS n ON n.oid = c.relnamespace
WHERE c.relkind = 'S'
  AND n.nspname NOT LIKE 'pg_%'
  AND n.nspname <> 'information_schema'
ORDER BY n.nspname, c.relname;

\echo '17. PUBLIC routine EXECUTE checks'
SELECT
    n.nspname AS schema_name,
    p.proname AS routine_name,
    pg_get_function_identity_arguments(p.oid) AS identity_arguments,
    has_function_privilege('public', p.oid, 'EXECUTE') AS public_execute
FROM pg_proc AS p
JOIN pg_namespace AS n ON n.oid = p.pronamespace
WHERE p.prokind IN ('f','p')
  AND n.nspname NOT LIKE 'pg_%'
  AND n.nspname <> 'information_schema'
ORDER BY
    n.nspname,
    p.proname,
    pg_get_function_identity_arguments(p.oid);

\echo '18. Interpretation reminder'
SELECT
    'This output is application-focused database/catalog baseline evidence, '
    'not an automatic vulnerability verdict or complete cluster security '
    'audit. Effective access can depend on ownership, membership, ACLs, '
    'default privileges, PUBLIC, predefined roles, privileged routines, RLS, '
    'authentication/TLS, extensions, provider controls, and runtime context. '
    'Review and classify drift before remediation.' AS reminder;

\echo '======================================================================'
\echo 'SAFE-READ security-baseline acceptance collection complete.'
\echo 'No roles, memberships, privileges, ownership, RLS, HBA/TLS settings,'
\echo 'credentials, authorization context, or sessions were intentionally changed.'
\echo 'Treat collected security evidence as sensitive.'
\echo '======================================================================'
