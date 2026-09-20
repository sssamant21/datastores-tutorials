/*
===============================================================================
Part 4.15 — Integrated Project — Build and Validate an Application Access Model
Canonical Acceptance Artifact

[TUTORIAL-ACCEPTANCE — SAFE-READ]

Target: PostgreSQL 18

Reference identifiers:
  database: appdb
  schema:   app
  roles:    app_owner, app_read, app_write, app_runtime, app_migration

IMPORTANT:
  Application catalogs are database-local. Connect to appdb before using this
  artifact to validate appdb application objects. This script reports the
  current target but does not automatically reconnect.

Safety:
  - No CREATE/ALTER/DROP ROLE.
  - No GRANT / REVOKE.
  - No ownership changes.
  - No DDL/DML against application objects.
  - No RLS changes.
  - No ALTER SYSTEM.
  - No HBA/TLS changes or reload.
  - No SET ROLE / SET SESSION AUTHORIZATION.
  - No password-verifier inspection.
  - No external authentication tests.
  - No automatic remediation.
  - No session termination.

Evidence sensitivity:
  SAFE-READ != safe to publish.
===============================================================================
*/

\echo '======================================================================'
\echo 'Part 4.15 — Integrated Project — Application Access Model'
\echo '[TUTORIAL-ACCEPTANCE — SAFE-READ]'
\echo '======================================================================'

\echo '1. Execution context and target-database check'
SELECT
    current_database() AS database_name,
    current_database() = 'appdb' AS connected_to_expected_database,
    session_user,
    current_user,
    current_role,
    current_setting('server_version') AS server_version;

\echo '2. Candidate application role attributes'
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
WHERE rolname IN (
    'app_owner','app_read','app_write','app_runtime','app_migration'
)
ORDER BY rolname;

\echo '3. Membership involving candidate application roles'
SELECT
    member_role.rolname AS member_name,
    granted_role.rolname AS granted_role_name,
    grantor_role.rolname AS grantor_name,
    m.admin_option,
    m.inherit_option,
    m.set_option
FROM pg_auth_members AS m
JOIN pg_roles AS member_role ON member_role.oid = m.member
JOIN pg_roles AS granted_role ON granted_role.oid = m.roleid
LEFT JOIN pg_roles AS grantor_role ON grantor_role.oid = m.grantor
WHERE member_role.rolname IN (
          'app_owner','app_read','app_write','app_runtime','app_migration'
      )
   OR granted_role.rolname IN (
          'app_owner','app_read','app_write','app_runtime','app_migration'
      )
ORDER BY member_name, granted_role_name, grantor_name;

\echo '4. Candidate-role membership in predefined PostgreSQL roles'
SELECT
    member_role.rolname AS member_name,
    granted_role.rolname AS predefined_role,
    m.admin_option,
    m.inherit_option,
    m.set_option
FROM pg_auth_members AS m
JOIN pg_roles AS member_role ON member_role.oid = m.member
JOIN pg_roles AS granted_role ON granted_role.oid = m.roleid
WHERE member_role.rolname IN (
    'app_owner','app_read','app_write','app_runtime','app_migration'
)
  AND granted_role.rolname LIKE 'pg_%'
ORDER BY member_name, predefined_role;

\echo '5. appdb database ownership and ACL'
SELECT
    d.datname,
    pg_get_userbyid(d.datdba) AS owner_name,
    d.datallowconn,
    d.datconnlimit,
    d.datacl
FROM pg_database AS d
WHERE d.datname = 'appdb';

\echo '6. app schema ownership and ACL'
SELECT
    n.nspname AS schema_name,
    pg_get_userbyid(n.nspowner) AS owner_name,
    n.nspacl
FROM pg_namespace AS n
WHERE n.nspname = 'app';

\echo '7. app relation ownership, type, RLS state, and ACLs'
SELECT
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
WHERE n.nspname = 'app'
  AND c.relkind IN ('r','p','v','m','f')
ORDER BY c.relname, c.relkind;

\echo '8. Explicit column ACLs in app schema'
SELECT
    c.relname AS relation_name,
    a.attname AS column_name,
    a.attacl
FROM pg_attribute AS a
JOIN pg_class AS c ON c.oid = a.attrelid
JOIN pg_namespace AS n ON n.oid = c.relnamespace
WHERE n.nspname = 'app'
  AND a.attnum > 0
  AND NOT a.attisdropped
  AND a.attacl IS NOT NULL
ORDER BY c.relname, a.attnum;

\echo '9. app sequence ownership and ACLs'
SELECT
    c.relname AS sequence_name,
    pg_get_userbyid(c.relowner) AS owner_name,
    c.relacl
FROM pg_class AS c
JOIN pg_namespace AS n ON n.oid = c.relnamespace
WHERE n.nspname = 'app'
  AND c.relkind = 'S'
ORDER BY c.relname;

\echo '10. app routine security, kind, ownership, ACLs, and configuration'
SELECT
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
WHERE n.nspname = 'app'
ORDER BY p.proname, pg_get_function_identity_arguments(p.oid);

\echo '11. Default privileges relevant to app schema / creator roles'
SELECT
    pg_get_userbyid(d.defaclrole) AS creator_role,
    COALESCE(n.nspname, '<all-schemas>') AS schema_scope,
    d.defaclobjtype,
    d.defaclacl
FROM pg_default_acl AS d
LEFT JOIN pg_namespace AS n ON n.oid = d.defaclnamespace
WHERE n.nspname = 'app'
   OR n.nspname IS NULL
ORDER BY creator_role, schema_scope, d.defaclobjtype;

\echo '12. RLS policies in app schema'
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
WHERE schemaname = 'app'
ORDER BY tablename, policyname;

\echo '13. SECURITY DEFINER inventory in app schema'
SELECT
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
WHERE n.nspname = 'app'
  AND p.prosecdef
ORDER BY p.proname, pg_get_function_identity_arguments(p.oid);

\echo '14. Candidate-role database/schema effective privilege evidence'
SELECT
    r.rolname,
    CASE WHEN EXISTS (SELECT 1 FROM pg_database WHERE datname = 'appdb')
         THEN has_database_privilege(r.oid, 'appdb', 'CONNECT') END
         AS can_connect_appdb,
    CASE WHEN EXISTS (SELECT 1 FROM pg_namespace WHERE nspname = 'app')
         THEN has_schema_privilege(r.oid, 'app', 'USAGE') END
         AS can_use_app_schema,
    CASE WHEN EXISTS (SELECT 1 FROM pg_namespace WHERE nspname = 'app')
         THEN has_schema_privilege(r.oid, 'app', 'CREATE') END
         AS can_create_in_app_schema
FROM pg_roles AS r
WHERE r.rolname IN (
    'app_owner','app_read','app_write','app_runtime','app_migration'
)
ORDER BY r.rolname;

\echo '15. Candidate-role table privileges in app schema'
SELECT
    r.rolname,
    c.relname AS relation_name,
    has_table_privilege(r.oid, c.oid, 'SELECT') AS can_select,
    has_table_privilege(r.oid, c.oid, 'INSERT') AS can_insert,
    has_table_privilege(r.oid, c.oid, 'UPDATE') AS can_update,
    has_table_privilege(r.oid, c.oid, 'DELETE') AS can_delete
FROM pg_roles AS r
CROSS JOIN pg_class AS c
JOIN pg_namespace AS n ON n.oid = c.relnamespace
WHERE r.rolname IN (
    'app_owner','app_read','app_write','app_runtime','app_migration'
)
  AND n.nspname = 'app'
  AND c.relkind IN ('r','p','v','m','f')
ORDER BY r.rolname, c.relname;

\echo '16. Candidate-role sequence privileges in app schema'
SELECT
    r.rolname,
    c.relname AS sequence_name,
    has_sequence_privilege(r.oid, c.oid, 'USAGE') AS can_use,
    has_sequence_privilege(r.oid, c.oid, 'SELECT') AS can_select,
    has_sequence_privilege(r.oid, c.oid, 'UPDATE') AS can_update
FROM pg_roles AS r
CROSS JOIN pg_class AS c
JOIN pg_namespace AS n ON n.oid = c.relnamespace
WHERE r.rolname IN (
    'app_owner','app_read','app_write','app_runtime','app_migration'
)
  AND n.nspname = 'app'
  AND c.relkind = 'S'
ORDER BY r.rolname, c.relname;

\echo '17. Candidate-role routine EXECUTE privileges in app schema'
SELECT
    r.rolname,
    p.proname AS routine_name,
    pg_get_function_identity_arguments(p.oid) AS identity_arguments,
    has_function_privilege(r.oid, p.oid, 'EXECUTE') AS can_execute
FROM pg_roles AS r
CROSS JOIN pg_proc AS p
JOIN pg_namespace AS n ON n.oid = p.pronamespace
WHERE r.rolname IN (
    'app_owner','app_read','app_write','app_runtime','app_migration'
)
  AND n.nspname = 'app'
  AND p.prokind IN ('f','p')
ORDER BY r.rolname, p.proname, pg_get_function_identity_arguments(p.oid);

\echo '18. PUBLIC database/schema privilege evidence'
SELECT
    CASE WHEN EXISTS (SELECT 1 FROM pg_database WHERE datname = 'appdb')
         THEN has_database_privilege('public', 'appdb', 'CONNECT') END
         AS public_connect_appdb,
    CASE WHEN EXISTS (SELECT 1 FROM pg_namespace WHERE nspname = 'app')
         THEN has_schema_privilege('public', 'app', 'USAGE') END
         AS public_use_app_schema,
    CASE WHEN EXISTS (SELECT 1 FROM pg_namespace WHERE nspname = 'app')
         THEN has_schema_privilege('public', 'app', 'CREATE') END
         AS public_create_in_app_schema;

\echo '19. PUBLIC routine EXECUTE evidence in app schema'
SELECT
    p.proname AS routine_name,
    pg_get_function_identity_arguments(p.oid) AS identity_arguments,
    has_function_privilege('public', p.oid, 'EXECUTE') AS public_execute
FROM pg_proc AS p
JOIN pg_namespace AS n ON n.oid = p.pronamespace
WHERE n.nspname = 'app'
  AND p.prokind IN ('f','p')
ORDER BY p.proname, pg_get_function_identity_arguments(p.oid);

\echo '20. Interpretation reminder'
SELECT
    'This SAFE-READ artifact validates catalog/effective-privilege evidence for '
    'an existing model. It does not install the model and does not replace '
    'controlled expected-allow/expected-deny tests. Ownership, membership, '
    'PUBLIC, RLS, SECURITY DEFINER, authentication, TLS, extensions, provider '
    'controls, and runtime context can affect effective behavior.' AS reminder;

\echo '======================================================================'
\echo 'SAFE-READ application-access acceptance inspection complete.'
\echo 'No roles, memberships, privileges, ownership, objects, RLS, HBA/TLS'
\echo 'configuration, authorization context, credentials, or sessions were changed.'
\echo 'Treat collected security evidence as sensitive.'
\echo '======================================================================'