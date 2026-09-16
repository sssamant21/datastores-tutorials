-- labs/processes-check.sql
-- [TUTORIAL-ACCEPTANCE — SAFE-READ]
-- Part 1.12 — PostgreSQL Processes — Introduction
-- PostgreSQL 18
-- READ ONLY.
-- No cancellation, termination, DDL, DML, transaction manipulation,
-- configuration changes, OS process operations, or intentional workload generation.

-- 1. Current session identity and backend PID.
SELECT
    current_database() AS current_database,
    current_user       AS current_user,
    session_user       AS session_user,
    pg_backend_pid()   AS backend_pid;

-- 2. Current backend metadata.
SELECT
    pid,
    usename,
    datname,
    application_name,
    client_addr,
    backend_start,
    xact_start,
    query_start,
    state_change,
    state,
    wait_event_type,
    wait_event,
    backend_type
FROM pg_stat_activity
WHERE pid = pg_backend_pid();
-- For an ordinary psql/application connection, backend_type is expected
-- to be 'client backend'.

-- 3. Backend-type distribution.
SELECT
    backend_type,
    COUNT(*) AS process_count
FROM pg_stat_activity
GROUP BY backend_type
ORDER BY backend_type;
-- Exact backend types and counts are environment-dependent.

-- 4. Client backend count.
SELECT
    COUNT(*) AS client_backend_count
FROM pg_stat_activity
WHERE backend_type = 'client backend';
-- Connection count != active query count.

-- 5. Client connections by database.
SELECT
    datname,
    COUNT(*) AS connection_count
FROM pg_stat_activity
WHERE backend_type = 'client backend'
GROUP BY datname
ORDER BY connection_count DESC, datname;

-- 6. Client session-state distribution.
SELECT
    state,
    COUNT(*) AS session_count
FROM pg_stat_activity
WHERE backend_type = 'client backend'
GROUP BY state
ORDER BY state;
-- Exact states and counts are environment-dependent.

-- 7. Open transaction age.
SELECT
    pid,
    usename,
    datname,
    state,
    xact_start,
    now() - xact_start AS transaction_age
FROM pg_stat_activity
WHERE xact_start IS NOT NULL
ORDER BY xact_start;
-- Observational only. Do not interpret old transaction = terminate.

-- 8. Wait-event visibility.
SELECT
    pid,
    usename,
    state,
    wait_event_type,
    wait_event
FROM pg_stat_activity
WHERE wait_event IS NOT NULL
ORDER BY pid;
-- Zero rows is valid. state=active with a wait_event is also valid.
-- active != necessarily CPU-bound.

-- 9. Current backend state + wait correlation.
SELECT
    pid,
    state,
    wait_event_type,
    wait_event,
    backend_start,
    xact_start,
    query_start
FROM pg_stat_activity
WHERE pid = pg_backend_pid();

-- 10. Application connection distribution.
SELECT
    COALESCE(NULLIF(application_name, ''), '<not set>') AS application_name,
    COUNT(*) AS connection_count
FROM pg_stat_activity
WHERE backend_type = 'client backend'
GROUP BY COALESCE(NULLIF(application_name, ''), '<not set>')
ORDER BY connection_count DESC, application_name;

-- 11. SAFE-READ completion marker.
SELECT
    'PASS — PostgreSQL process inspection completed without cancellation, '
    || 'termination, DDL, DML, configuration changes, or intentional workload generation.'
    AS tutorial_acceptance;

-- [TUTORIAL-ACCEPTANCE — SAFE-READ]
-- PASS when:
--   pg_backend_pid() returns the current backend PID
--   current backend is visible in pg_stat_activity
--   backend_type information is inspectable
--   client backend counts are inspectable
--   session-state distribution is inspectable
--   transaction-age information is inspectable
--   wait-event information is inspectable
--   current state/wait/timing information is inspectable
--   application connection distribution is inspectable
--   no query text needs to be copied or exposed
--   no backend is cancelled or terminated
--   no OS process is signaled
--   no transaction is intentionally held open
--   no blocking workload is manufactured
--   no database object/data/configuration is changed
-- Exact process counts, session counts, states, waits, and application
-- names are intentionally not hard-coded because they depend on the live environment.
