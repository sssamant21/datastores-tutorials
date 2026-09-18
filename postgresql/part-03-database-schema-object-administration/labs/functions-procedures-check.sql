/*
===============================================================================
Part 3.10 — Functions and Procedures — Administration Fundamentals
Canonical Acceptance Artifact

[TUTORIAL-ACCEPTANCE — SAFE-READ]

Target: PostgreSQL 18

Purpose:
  Inspect function/procedure metadata and security characteristics without
  modifying database state.

Safety:
  - No CREATE
  - No ALTER
  - No DROP
  - No INSERT / UPDATE / DELETE / MERGE
  - No TRUNCATE
  - No GRANT / REVOKE
  - No CALL
  - No execution of arbitrary user-defined functions
  - No configuration changes

Expected impact:
  Catalog reads only.
===============================================================================
*/

\set ON_ERROR_STOP on

\echo ''
\echo '============================================================'
\echo 'Part 3.10 — Functions and Procedures Acceptance Check'
\echo '[TUTORIAL-ACCEPTANCE — SAFE-READ]'
\echo '============================================================'
\echo ''

-- ---------------------------------------------------------------------------
-- 1. PostgreSQL version
-- ---------------------------------------------------------------------------

\echo '--- [1/10] PostgreSQL version ---'

SELECT
    current_setting('server_version') AS server_version,
    current_setting('server_version_num') AS server_version_num;

-- ---------------------------------------------------------------------------
-- 2. Current execution context
-- ---------------------------------------------------------------------------

\echo ''
\echo '--- [2/10] Current database/session context ---'

SELECT
    current_database() AS database_name,
    current_user AS current_user,
    session_user AS session_user;

-- ---------------------------------------------------------------------------
-- 3. Installed procedural languages
-- ---------------------------------------------------------------------------

\echo ''
\echo '--- [3/10] Installed languages ---'

SELECT
    lanname AS language_name,
    lanpltrusted AS trusted
FROM pg_catalog.pg_language
ORDER BY lanname;

-- ---------------------------------------------------------------------------
-- 4. User-visible routines
-- ---------------------------------------------------------------------------

\echo ''
\echo '--- [4/10] User-visible functions and procedures ---'

SELECT
    n.nspname AS schema_name,
    p.proname AS routine_name,
    pg_catalog.pg_get_function_identity_arguments(p.oid)
        AS identity_arguments,
    CASE p.prokind
        WHEN 'f' THEN 'FUNCTION'
        WHEN 'p' THEN 'PROCEDURE'
        WHEN 'a' THEN 'AGGREGATE'
        WHEN 'w' THEN 'WINDOW FUNCTION'
        ELSE p.prokind::text
    END AS routine_kind,
    pg_catalog.pg_get_userbyid(p.proowner) AS owner,
    l.lanname AS language
FROM pg_catalog.pg_proc AS p
JOIN pg_catalog.pg_namespace AS n
    ON n.oid = p.pronamespace
JOIN pg_catalog.pg_language AS l
    ON l.oid = p.prolang
WHERE n.nspname <> 'pg_catalog'
  AND n.nspname <> 'information_schema'
  AND n.nspname !~ '^pg_toast'
ORDER BY
    n.nspname,
    p.proname,
    identity_arguments;

-- ---------------------------------------------------------------------------
-- 5. Security mode
-- ---------------------------------------------------------------------------

\echo ''
\echo '--- [5/10] Routine security mode ---'

SELECT
    n.nspname AS schema_name,
    p.proname AS routine_name,
    pg_catalog.pg_get_function_identity_arguments(p.oid)
        AS identity_arguments,
    pg_catalog.pg_get_userbyid(p.proowner) AS owner,
    CASE
        WHEN p.prosecdef THEN 'SECURITY DEFINER'
        ELSE 'SECURITY INVOKER'
    END AS security_mode
FROM pg_catalog.pg_proc AS p
JOIN pg_catalog.pg_namespace AS n
    ON n.oid = p.pronamespace
WHERE n.nspname <> 'pg_catalog'
  AND n.nspname <> 'information_schema'
  AND n.nspname !~ '^pg_toast'
ORDER BY
    n.nspname,
    p.proname,
    identity_arguments;

-- ---------------------------------------------------------------------------
-- 6. SECURITY DEFINER inventory
-- ---------------------------------------------------------------------------

\echo ''
\echo '--- [6/10] SECURITY DEFINER review inventory ---'

SELECT
    n.nspname AS schema_name,
    p.proname AS routine_name,
    pg_catalog.pg_get_function_identity_arguments(p.oid)
        AS identity_arguments,
    pg_catalog.pg_get_userbyid(p.proowner) AS owner,
    p.proconfig AS routine_configuration,
    p.proacl AS acl
FROM pg_catalog.pg_proc AS p
JOIN pg_catalog.pg_namespace AS n
    ON n.oid = p.pronamespace
WHERE p.prosecdef
  AND n.nspname <> 'pg_catalog'
  AND n.nspname <> 'information_schema'
  AND n.nspname !~ '^pg_toast'
ORDER BY
    n.nspname,
    p.proname,
    identity_arguments;

-- NOTE:
-- proconfig is intentionally displayed for review.
-- A SECURITY DEFINER routine should receive explicit review for its
-- search_path and other security-sensitive configuration.
--
-- This query does not declare a routine safe merely because proconfig
-- contains a search_path value.

-- ---------------------------------------------------------------------------
-- 7. Function volatility
-- ---------------------------------------------------------------------------

\echo ''
\echo '--- [7/10] Function volatility ---'

SELECT
    n.nspname AS schema_name,
    p.proname AS routine_name,
    pg_catalog.pg_get_function_identity_arguments(p.oid)
        AS identity_arguments,
    CASE p.provolatile
        WHEN 'i' THEN 'IMMUTABLE'
        WHEN 's' THEN 'STABLE'
        WHEN 'v' THEN 'VOLATILE'
        ELSE p.provolatile::text
    END AS volatility
FROM pg_catalog.pg_proc AS p
JOIN pg_catalog.pg_namespace AS n
    ON n.oid = p.pronamespace
WHERE p.prokind IN ('f', 'w')
  AND n.nspname <> 'pg_catalog'
  AND n.nspname <> 'information_schema'
  AND n.nspname !~ '^pg_toast'
ORDER BY
    n.nspname,
    p.proname,
    identity_arguments;

-- ---------------------------------------------------------------------------
-- 8. Parallel-safety classification
-- ---------------------------------------------------------------------------

\echo ''
\echo '--- [8/10] Function parallel safety ---'

SELECT
    n.nspname AS schema_name,
    p.proname AS routine_name,
    pg_catalog.pg_get_function_identity_arguments(p.oid)
        AS identity_arguments,
    CASE p.proparallel
        WHEN 's' THEN 'SAFE'
        WHEN 'r' THEN 'RESTRICTED'
        WHEN 'u' THEN 'UNSAFE'
        ELSE p.proparallel::text
    END AS parallel_safety
FROM pg_catalog.pg_proc AS p
JOIN pg_catalog.pg_namespace AS n
    ON n.oid = p.pronamespace
WHERE p.prokind IN ('f', 'w')
  AND n.nspname <> 'pg_catalog'
  AND n.nspname <> 'information_schema'
  AND n.nspname !~ '^pg_toast'
ORDER BY
    n.nspname,
    p.proname,
    identity_arguments;

-- ---------------------------------------------------------------------------
-- 9. Routine ACL inventory
-- ---------------------------------------------------------------------------

\echo ''
\echo '--- [9/10] Routine ACL inventory ---'

SELECT
    n.nspname AS schema_name,
    p.proname AS routine_name,
    pg_catalog.pg_get_function_identity_arguments(p.oid)
        AS identity_arguments,
    CASE p.prokind
        WHEN 'f' THEN 'FUNCTION'
        WHEN 'p' THEN 'PROCEDURE'
        WHEN 'a' THEN 'AGGREGATE'
        WHEN 'w' THEN 'WINDOW FUNCTION'
        ELSE p.prokind::text
    END AS routine_kind,
    pg_catalog.pg_get_userbyid(p.proowner) AS owner,
    p.proacl AS acl
FROM pg_catalog.pg_proc AS p
JOIN pg_catalog.pg_namespace AS n
    ON n.oid = p.pronamespace
WHERE n.nspname <> 'pg_catalog'
  AND n.nspname <> 'information_schema'
  AND n.nspname !~ '^pg_toast'
ORDER BY
    n.nspname,
    p.proname,
    identity_arguments;

-- NULL proacl does NOT mean "nobody has privileges".
-- PostgreSQL default privileges still apply.
-- Interpret ACL results together with PostgreSQL privilege rules and
-- ALTER DEFAULT PRIVILEGES configuration.

-- ---------------------------------------------------------------------------
-- 10. Summary
-- ---------------------------------------------------------------------------

\echo ''
\echo '--- [10/10] Routine inventory summary ---'

SELECT
    CASE p.prokind
        WHEN 'f' THEN 'FUNCTION'
        WHEN 'p' THEN 'PROCEDURE'
        WHEN 'a' THEN 'AGGREGATE'
        WHEN 'w' THEN 'WINDOW FUNCTION'
        ELSE p.prokind::text
    END AS routine_kind,
    COUNT(*) AS routine_count
FROM pg_catalog.pg_proc AS p
JOIN pg_catalog.pg_namespace AS n
    ON n.oid = p.pronamespace
WHERE n.nspname <> 'pg_catalog'
  AND n.nspname <> 'information_schema'
  AND n.nspname !~ '^pg_toast'
GROUP BY p.prokind
ORDER BY routine_kind;

\echo ''
\echo '============================================================'
\echo 'SAFE-READ acceptance checks completed.'
\echo ''
\echo 'No database objects were intentionally created, altered,'
\echo 'dropped, granted, revoked, or otherwise modified.'
\echo '============================================================'

