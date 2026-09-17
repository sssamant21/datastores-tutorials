-- Part 2.9 — Connection, Session, and Process Configuration
-- [TUTORIAL-ACCEPTANCE — SAFE-READ]
\set ON_ERROR_STOP on
\pset pager off

SELECT current_setting('server_version') AS server_version;

SELECT name, setting, unit, context, source, pending_restart
FROM pg_settings
WHERE name IN (
  'listen_addresses','port','unix_socket_directories','max_connections',
  'reserved_connections','superuser_reserved_connections','authentication_timeout',
  'client_connection_check_interval','statement_timeout','lock_timeout',
  'idle_in_transaction_session_timeout','idle_session_timeout','application_name','search_path'
)
ORDER BY name;

SELECT state, count(*) AS sessions
FROM pg_stat_activity
GROUP BY state
ORDER BY sessions DESC, state NULLS LAST;

SELECT backend_type, count(*) AS processes
FROM pg_stat_activity
GROUP BY backend_type
ORDER BY processes DESC, backend_type;
