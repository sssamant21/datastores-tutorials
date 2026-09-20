/*
===============================================================================
Part 4.10 — SECURITY DEFINER and Privileged Routine Hardening
Canonical Acceptance Artifact
[TUTORIAL-ACCEPTANCE — SAFE-READ]
Target: PostgreSQL 18
===============================================================================
*/
\echo 'Part 4.10 — SECURITY DEFINER and Privileged Routine Hardening'
\echo '[TUTORIAL-ACCEPTANCE — SAFE-READ]'

\echo '1. Execution context'
SELECT current_database() AS database_name, session_user, current_user, current_role;

\echo '2. SECURITY DEFINER routine inventory'
SELECT n.nspname AS schema_name, p.proname AS routine_name,
       pg_get_function_identity_arguments(p.oid) AS identity_arguments,
       CASE p.prokind WHEN 'f' THEN 'function' WHEN 'p' THEN 'procedure'
            WHEN 'a' THEN 'aggregate' WHEN 'w' THEN 'window function'
            ELSE p.prokind::text END AS routine_kind,
       pg_get_userbyid(p.proowner) AS routine_owner,
       p.prosecdef AS security_definer, p.proconfig AS routine_configuration
FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
WHERE p.prosecdef AND n.nspname <> 'information_schema' AND n.nspname NOT LIKE 'pg_%'
ORDER BY n.nspname,p.proname,pg_get_function_identity_arguments(p.oid);

\echo '3. SECURITY DEFINER owner attributes'
SELECT DISTINCT r.rolname AS routine_owner, r.rolsuper, r.rolinherit,
       r.rolcreaterole, r.rolcreatedb, r.rolcanlogin, r.rolreplication, r.rolbypassrls
FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
JOIN pg_roles r ON r.oid=p.proowner
WHERE p.prosecdef AND n.nspname <> 'information_schema' AND n.nspname NOT LIKE 'pg_%'
ORDER BY r.rolname;

\echo '4. Routine-level search_path configuration evidence'
SELECT n.nspname AS schema_name, p.proname AS routine_name,
       pg_get_function_identity_arguments(p.oid) AS identity_arguments,
       pg_get_userbyid(p.proowner) AS routine_owner, p.proconfig,
       (SELECT cfg.setting FROM unnest(COALESCE(p.proconfig,ARRAY[]::text[])) cfg(setting)
        WHERE cfg.setting LIKE 'search_path=%' LIMIT 1) AS routine_search_path,
       EXISTS (SELECT 1 FROM unnest(COALESCE(p.proconfig,ARRAY[]::text[])) cfg(setting)
               WHERE cfg.setting LIKE 'search_path=%') AS has_routine_search_path
FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
WHERE p.prosecdef AND n.nspname <> 'information_schema' AND n.nspname NOT LIKE 'pg_%'
ORDER BY n.nspname,p.proname,pg_get_function_identity_arguments(p.oid);

\echo '5. Effective EXECUTE evidence for current_user'
SELECT n.nspname AS schema_name, p.proname AS routine_name,
       pg_get_function_identity_arguments(p.oid) AS identity_arguments,
       has_function_privilege(current_user,p.oid,'EXECUTE') AS current_user_can_execute,
       has_function_privilege(current_user,p.oid,'EXECUTE WITH GRANT OPTION') AS current_user_can_grant_execute
FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
WHERE p.prosecdef AND n.nspname <> 'information_schema' AND n.nspname NOT LIKE 'pg_%'
ORDER BY n.nspname,p.proname,pg_get_function_identity_arguments(p.oid);

\echo '6. Effective PUBLIC EXECUTE evidence'
SELECT n.nspname AS schema_name, p.proname AS routine_name,
       pg_get_function_identity_arguments(p.oid) AS identity_arguments,
       has_function_privilege('public',p.oid,'EXECUTE') AS public_can_execute,
       has_function_privilege('public',p.oid,'EXECUTE WITH GRANT OPTION') AS public_can_grant_execute
FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
WHERE p.prosecdef AND n.nspname <> 'information_schema' AND n.nspname NOT LIKE 'pg_%'
ORDER BY n.nspname,p.proname,pg_get_function_identity_arguments(p.oid);

\echo '7. Explicit configured ACL evidence'
SELECT n.nspname AS schema_name, p.proname AS routine_name,
       pg_get_function_identity_arguments(p.oid) AS identity_arguments,
       CASE WHEN acl.grantee=0 THEN 'PUBLIC' ELSE pg_get_userbyid(acl.grantee) END AS grantee,
       pg_get_userbyid(acl.grantor) AS grantor, acl.privilege_type, acl.is_grantable
FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
CROSS JOIN LATERAL aclexplode(p.proacl) acl
WHERE p.prosecdef AND n.nspname <> 'information_schema' AND n.nspname NOT LIKE 'pg_%'
ORDER BY n.nspname,p.proname,identity_arguments,grantee,acl.privilege_type;

\echo '8. Schemas containing SECURITY DEFINER routines'
\echo 'Routine-schema evidence only; not complete search_path validation.'
SELECT DISTINCT n.nspname AS schema_name, pg_get_userbyid(n.nspowner) AS schema_owner,
       has_schema_privilege('public',n.oid,'CREATE') AS public_has_create,
       has_schema_privilege('public',n.oid,'USAGE') AS public_has_usage
FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
WHERE p.prosecdef AND n.nspname <> 'information_schema' AND n.nspname NOT LIKE 'pg_%'
ORDER BY n.nspname;

\echo '9. SECURITY DEFINER review signals'
SELECT n.nspname AS schema_name, p.proname AS routine_name,
       pg_get_function_identity_arguments(p.oid) AS identity_arguments,
       r.rolname AS routine_owner, r.rolsuper AS owner_is_superuser,
       r.rolcreaterole AS owner_has_createrole, r.rolcreatedb AS owner_has_createdb,
       r.rolreplication AS owner_has_replication, r.rolbypassrls AS owner_bypasses_rls,
       has_function_privilege('public',p.oid,'EXECUTE') AS public_can_execute,
       NOT EXISTS (SELECT 1 FROM unnest(COALESCE(p.proconfig,ARRAY[]::text[])) cfg(setting)
                   WHERE cfg.setting LIKE 'search_path=%') AS no_routine_search_path_evidence
FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
JOIN pg_roles r ON r.oid=p.proowner
WHERE p.prosecdef AND n.nspname <> 'information_schema' AND n.nspname NOT LIKE 'pg_%'
ORDER BY n.nspname,p.proname,pg_get_function_identity_arguments(p.oid);

\echo '10. Summary counts'
SELECT count(*) AS security_definer_routines,
       count(*) FILTER (WHERE has_function_privilege('public',p.oid,'EXECUTE')) AS public_executable,
       count(*) FILTER (WHERE r.rolsuper) AS superuser_owned,
       count(*) FILTER (WHERE r.rolbypassrls) AS bypassrls_owned,
       count(*) FILTER (WHERE NOT EXISTS (
           SELECT 1 FROM unnest(COALESCE(p.proconfig,ARRAY[]::text[])) cfg(setting)
           WHERE cfg.setting LIKE 'search_path=%')) AS without_routine_search_path_evidence
FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
JOIN pg_roles r ON r.oid=p.proowner
WHERE p.prosecdef AND n.nspname <> 'information_schema' AND n.nspname NOT LIKE 'pg_%';

\echo 'SAFE-READ acceptance check complete.'
\echo 'No discovered routines were executed or security state modified.'
\echo 'Treat privileged-routine evidence as security-sensitive.'
