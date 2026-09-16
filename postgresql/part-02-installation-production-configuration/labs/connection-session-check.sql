/*
 * Part 2.9 — Connection and Session Configuration
 * [TUTORIAL-ACCEPTANCE — SAFE-READ]
 *
 * Target: PostgreSQL 18
 *
 * Safety:
 *   - Read-only inspection only
 *   - No DDL / DML
 *   - No SET / ALTER SYSTEM
 *   - No role changes
 *   - No HBA changes
 *   - No backend termination
 *   - No reload / restart
 *
 * SECURITY NOTE:
 *   pg_hba_file_rules can reveal role names, database names, source
 *   networks, and authentication methods. Treat its output as
 *   security-sensitive operational information.
 */

\echo '=== Part 2.9: Connection and Session Configuration — SAFE-READ ==='

\echo ''
\echo '--- Server / session identity ---'
SELECT
    current_database() AS database_name,
    current_user       AS current_user,
    session_user       AS session_user,
    pg_backend_pid()   AS backend_pid,
    version()          AS server_version;

\echo ''
\echo '--- Connection and session configuration ---'
SELECT
    name,
    setting,
    unit,
    context,
    source
FROM pg_settings
WHERE name IN (
    'listen_addresses',
    'port',
    'unix_socket_directories',
    'max_connections',
    'reserved_connections',
    'superuser_reserved_connections',
    'authentication_timeout',
    'password_encryption',
    'client_connection_check_interval',
    'tcp_keepalives_idle',
    'tcp_keepalives_interval',
    'tcp_keepalives_count',
    'tcp_user_timeout',
    'application_name',
    'search_path',
    'statement_timeout',
    'lock_timeout',
    'idle_in_transaction_session_timeout',
    'idle_session_timeout'
)
ORDER BY name;

\echo ''
\echo '--- Current backend ---'
SELECT
    pid,
    usename,
    application_name,
    client_addr,
    client_port,
    backend_start,
    state
FROM pg_stat_activity
WHERE pid = pg_backend_pid();

\echo ''
\echo '--- Connection state summary ---'
SELECT
    state,
    count(*) AS sessions
FROM pg_stat_activity
GROUP BY state
ORDER BY sessions DESC, state NULLS LAST;

\echo ''
\echo '--- Sessions by user/application/state ---'
SELECT
    usename,
    COALESCE(NULLIF(application_name, ''), '<unset>') AS application_name,
    state,
    count(*) AS sessions
FROM pg_stat_activity
GROUP BY
    usename,
    COALESCE(NULLIF(application_name, ''), '<unset>'),
    state
ORDER BY sessions DESC, usename, application_name, state NULLS LAST;

\echo ''
\echo '--- Effective session setting sources ---'
SELECT
    name,
    setting,
    context,
    source,
    sourcefile,
    sourceline
FROM pg_settings
WHERE name IN (
    'application_name',
    'search_path',
    'statement_timeout',
    'lock_timeout',
    'idle_in_transaction_session_timeout',
    'idle_session_timeout',
    'work_mem'
)
ORDER BY name;

\echo ''
\echo '--- HBA parsed rules: SECURITY-SENSITIVE OUTPUT ---'
SELECT
    rule_number,
    type,
    database,
    user_name,
    address,
    auth_method,
    options,
    error
FROM pg_hba_file_rules
ORDER BY rule_number;

\echo ''
\echo '=== SAFE-READ COMPLETE: no PostgreSQL state was intentionally changed ==='
