/*
 * Part 2.13 — Connection Management, Limits, and Timeouts
 * [TUTORIAL-ACCEPTANCE — SAFE-READ]
 * Target: PostgreSQL 18
 *
 * No DDL / DML
 * No SET / ALTER SYSTEM
 * No BEGIN / intentional transaction
 * No intentional timeout or blocking
 * No pg_cancel_backend() / pg_terminate_backend()
 * No pg_reload_conf()
 * No statistics reset
 * No restart
 * Query text intentionally excluded.
 */

\echo '=== Part 2.13 — Connection Management, Limits, and Timeouts — SAFE-READ ==='

\echo ''
\echo '--- Server identity ---'
SELECT
    current_database() AS database_name,
    current_user AS current_user,
    version() AS server_version;

\echo ''
\echo '--- Connection capacity and timeout configuration ---'
SELECT
    name,
    setting,
    unit,
    context,
    source,
    pending_restart
FROM pg_settings
WHERE name IN (
    'max_connections',
    'reserved_connections',
    'superuser_reserved_connections',
    'authentication_timeout',
    'statement_timeout',
    'lock_timeout',
    'transaction_timeout',
    'idle_in_transaction_session_timeout',
    'idle_session_timeout',
    'client_connection_check_interval',
    'tcp_keepalives_idle',
    'tcp_keepalives_interval',
    'tcp_keepalives_count',
    'tcp_user_timeout'
)
ORDER BY name;

\echo ''
\echo '--- Current client sessions by state ---'
SELECT
    state,
    COUNT(*) AS sessions
FROM pg_stat_activity
WHERE backend_type = 'client backend'
GROUP BY state
ORDER BY state;

\echo ''
\echo '--- Current client sessions by database ---'
SELECT
    datname,
    COUNT(*) AS sessions
FROM pg_stat_activity
WHERE backend_type = 'client backend'
GROUP BY datname
ORDER BY sessions DESC, datname;

\echo ''
\echo '--- Current client sessions by application and state ---'
SELECT
    application_name,
    state,
    COUNT(*) AS sessions
FROM pg_stat_activity
WHERE backend_type = 'client backend'
GROUP BY application_name, state
ORDER BY application_name, state;

\echo ''
\echo '--- Idle-in-transaction client sessions (metadata only) ---'
SELECT
    pid,
    usename,
    datname,
    application_name,
    state,
    xact_start,
    state_change,
    wait_event_type,
    wait_event
FROM pg_stat_activity
WHERE backend_type = 'client backend'
  AND state LIKE 'idle in transaction%'
ORDER BY xact_start NULLS LAST;

\echo ''
\echo '--- Active client sessions (metadata only; query text excluded) ---'
SELECT
    pid,
    usename,
    datname,
    application_name,
    state,
    query_start,
    now() - query_start AS runtime,
    wait_event_type,
    wait_event
FROM pg_stat_activity
WHERE backend_type = 'client backend'
  AND state = 'active'
  AND pid <> pg_backend_pid()
ORDER BY query_start;

\echo ''
\echo '=== SAFE-READ COMPLETE: no PostgreSQL state was intentionally changed ==='
