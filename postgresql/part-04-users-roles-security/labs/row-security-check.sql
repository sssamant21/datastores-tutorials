/*
===============================================================================
Part 4.11 — Row-Level Security Design and Validation
Canonical Acceptance Artifact
[TUTORIAL-ACCEPTANCE — SAFE-READ]
Target: PostgreSQL 18

Purpose:
  Inspect RLS configuration and authorization evidence without reading
  application rows, changing execution identity, or modifying security state.
===============================================================================
*/

\echo '======================================================================'
\echo 'Part 4.11 — Row-Level Security Design and Validation'
\echo '[TUTORIAL-ACCEPTANCE — SAFE-READ]'
\echo '======================================================================'

\echo '1. Execution context'
SELECT current_database() AS database_name, session_user, current_user, current_role;

\echo '2. Current role security attributes'
SELECT rolname, rolsuper, rolinherit, rolcreaterole, rolcreatedb, rolcanlogin,
       rolreplication, rolbypassrls
FROM pg_roles
WHERE rolname = current_user;

\echo '3. RLS-enabled user tables'
SELECT n.nspname AS schema_name, c.relname AS table_name,
       CASE c.relkind WHEN 'r' THEN 'table' WHEN 'p' THEN 'partitioned table'
            ELSE c.relkind::text END AS relation_kind,
       pg_get_userbyid(c.relowner) AS table_owner,
       c.relrowsecurity AS rls_enabled, c.relforcerowsecurity AS force_rls
FROM pg_class c
JOIN pg_namespace n ON n.oid=c.relnamespace
WHERE c.relkind IN ('r','p')
  AND c.relrowsecurity
  AND n.nspname <> 'information_schema'
  AND n.nspname NOT LIKE 'pg_%'
ORDER BY n.nspname,c.relname;

\echo '4. Current-user privilege and RLS evidence'
SELECT n.nspname AS schema_name, c.relname AS table_name,
       pg_get_userbyid(c.relowner) AS table_owner,
       has_table_privilege(current_user,c.oid,'SELECT') AS can_select,
       has_table_privilege(current_user,c.oid,'INSERT') AS can_insert,
       has_table_privilege(current_user,c.oid,'UPDATE') AS can_update,
       has_table_privilege(current_user,c.oid,'DELETE') AS can_delete,
       c.relrowsecurity AS rls_enabled,
       c.relforcerowsecurity AS force_rls,
       row_security_active(c.oid) AS rls_active_for_current_context
FROM pg_class c
JOIN pg_namespace n ON n.oid=c.relnamespace
WHERE c.relkind IN ('r','p')
  AND c.relrowsecurity
  AND n.nspname <> 'information_schema'
  AND n.nspname NOT LIKE 'pg_%'
ORDER BY n.nspname,c.relname;

\echo '5. Operator-friendly policy inventory'
SELECT schemaname,tablename,policyname,permissive,roles,cmd,qual,with_check
FROM pg_policies
WHERE schemaname <> 'information_schema'
  AND schemaname NOT LIKE 'pg_%'
ORDER BY schemaname,tablename,policyname;

\echo '6. Lower-level pg_policy evidence'
SELECT n.nspname AS schema_name, c.relname AS table_name, pol.polname AS policy_name,
       CASE pol.polcmd WHEN 'r' THEN 'SELECT' WHEN 'a' THEN 'INSERT'
            WHEN 'w' THEN 'UPDATE' WHEN 'd' THEN 'DELETE'
            WHEN '*' THEN 'ALL' ELSE pol.polcmd::text END AS command,
       pol.polpermissive AS permissive,
       ARRAY(
         SELECT CASE WHEN role_oid=0 THEN 'PUBLIC' ELSE pg_get_userbyid(role_oid) END
         FROM unnest(pol.polroles) AS role_oid
       ) AS policy_roles,
       pg_get_expr(pol.polqual,pol.polrelid) AS using_expression,
       pg_get_expr(pol.polwithcheck,pol.polrelid) AS explicit_with_check_expression
FROM pg_policy pol
JOIN pg_class c ON c.oid=pol.polrelid
JOIN pg_namespace n ON n.oid=c.relnamespace
WHERE n.nspname <> 'information_schema'
  AND n.nspname NOT LIKE 'pg_%'
ORDER BY n.nspname,c.relname,pol.polname;

\echo '7. Policy inventory counts — inventory only, not applicability proof'
SELECT n.nspname AS schema_name, c.relname AS table_name,
       pg_get_userbyid(c.relowner) AS table_owner,
       c.relrowsecurity AS rls_enabled, c.relforcerowsecurity AS force_rls,
       count(pol.oid) AS total_policy_count,
       count(pol.oid) FILTER (WHERE pol.polpermissive) AS permissive_policy_count,
       count(pol.oid) FILTER (WHERE NOT pol.polpermissive) AS restrictive_policy_count,
       count(pol.oid) FILTER (WHERE pol.polcmd IN ('r','*')) AS select_or_all_policy_count,
       count(pol.oid) FILTER (WHERE pol.polcmd IN ('a','*')) AS insert_or_all_policy_count,
       count(pol.oid) FILTER (WHERE pol.polcmd IN ('w','*')) AS update_or_all_policy_count,
       count(pol.oid) FILTER (WHERE pol.polcmd IN ('d','*')) AS delete_or_all_policy_count
FROM pg_class c
JOIN pg_namespace n ON n.oid=c.relnamespace
LEFT JOIN pg_policy pol ON pol.polrelid=c.oid
WHERE c.relkind IN ('r','p')
  AND c.relrowsecurity
  AND n.nspname <> 'information_schema'
  AND n.nspname NOT LIKE 'pg_%'
GROUP BY n.nspname,c.relname,c.relowner,c.relrowsecurity,c.relforcerowsecurity
ORDER BY n.nspname,c.relname;

\echo '8. RLS review signals — contextual evidence, not vulnerability declarations'
SELECT n.nspname AS schema_name, c.relname AS table_name,
       pg_get_userbyid(c.relowner) AS table_owner,
       c.relrowsecurity AS rls_enabled, c.relforcerowsecurity AS force_rls,
       count(pol.oid) AS total_policy_count,
       (count(pol.oid)=0) AS no_policies_defined,
       (count(pol.oid) FILTER (WHERE pol.polpermissive)=0) AS no_permissive_policies_defined,
       (pg_get_userbyid(c.relowner)=current_user) AS current_user_is_table_owner,
       row_security_active(c.oid) AS rls_active_for_current_context
FROM pg_class c
JOIN pg_namespace n ON n.oid=c.relnamespace
LEFT JOIN pg_policy pol ON pol.polrelid=c.oid
WHERE c.relkind IN ('r','p')
  AND c.relrowsecurity
  AND n.nspname <> 'information_schema'
  AND n.nspname NOT LIKE 'pg_%'
GROUP BY c.oid,n.nspname,c.relname,c.relowner,c.relrowsecurity,c.relforcerowsecurity
ORDER BY n.nspname,c.relname;

\echo '9. Tables with FORCE ROW LEVEL SECURITY'
SELECT n.nspname AS schema_name, c.relname AS table_name,
       pg_get_userbyid(c.relowner) AS table_owner,
       c.relrowsecurity AS rls_enabled, c.relforcerowsecurity AS force_rls,
       row_security_active(c.oid) AS rls_active_for_current_context
FROM pg_class c
JOIN pg_namespace n ON n.oid=c.relnamespace
WHERE c.relkind IN ('r','p')
  AND c.relrowsecurity
  AND c.relforcerowsecurity
  AND n.nspname <> 'information_schema'
  AND n.nspname NOT LIKE 'pg_%'
ORDER BY n.nspname,c.relname;

\echo '10. Partitioned RLS objects requiring hierarchy-aware review'
SELECT n.nspname AS schema_name, c.relname AS partitioned_table,
       pg_get_userbyid(c.relowner) AS table_owner,
       c.relrowsecurity AS rls_enabled, c.relforcerowsecurity AS force_rls
FROM pg_class c
JOIN pg_namespace n ON n.oid=c.relnamespace
WHERE c.relkind='p'
  AND c.relrowsecurity
  AND n.nspname <> 'information_schema'
  AND n.nspname NOT LIKE 'pg_%'
ORDER BY n.nspname,c.relname;

\echo '11. Interpretation reminder'
SELECT 'RLS evidence must be interpreted with table privileges, execution identity, '
       'ownership, SUPERUSER/BYPASSRLS, FORCE RLS, applicable policy roles and commands, '
       'role membership, permissive/restrictive composition, USING/WITH CHECK semantics, '
       'policy dependencies, partition hierarchy, triggers, and trusted runtime context. '
       'Policy counts and metadata alone do not prove exact runtime row visibility.'
       AS reminder;

\echo '======================================================================'
\echo 'SAFE-READ RLS acceptance check complete.'
\echo 'No application rows were intentionally selected.'
\echo 'No execution identity was intentionally changed.'
\echo 'No RLS state, policies, privileges, ownership, objects, or application data were modified.'
\echo 'Treat RLS evidence as security-sensitive.'
\echo '======================================================================'
