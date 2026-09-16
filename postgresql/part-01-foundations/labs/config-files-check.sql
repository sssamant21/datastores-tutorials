-- ============================================================
-- [TUTORIAL-ACCEPTANCE — SAFE-READ]
-- Part 1.14
-- postgresql.conf and pg_hba.conf — Inspection Lab
-- PostgreSQL 18
--
-- SAFETY:
--   READ ONLY
--   No DDL
--   No DML
--   No ALTER SYSTEM
--   No configuration changes
--   No configuration reload
--   No server restart
--   No role or privilege changes
--   No session termination
--
-- PRIVILEGE NOTE:
--   Some configuration inspection views may require elevated
--   PostgreSQL privileges. Do not grant superuser solely to
--   complete this tutorial.
--
-- SECURITY NOTE:
--   Output may contain sensitive operational metadata,
--   including filesystem paths, database/role names,
--   network ranges, and authentication configuration.
--   Sanitize captured output before external sharing.
-- ============================================================

\echo '============================================================'
\echo 'Part 1.14 - PostgreSQL Configuration Inspection'
\echo '============================================================'

\echo ''
\echo '[1/7] Server identity'

SELECT
    current_database() AS database_name,
    current_user AS current_user,
    current_setting('server_version') AS server_version;

\echo ''
\echo '[2/7] Active configuration locations'

SELECT
    current_setting('data_directory') AS data_directory,
    current_setting('config_file') AS config_file,
    current_setting('hba_file') AS hba_file,
    current_setting('ident_file') AS ident_file;

\echo ''
\echo '[3/7] Core PostgreSQL settings'

SELECT
    name,
    setting,
    unit,
    context,
    source,
    pending_restart
FROM pg_settings
WHERE name IN (
    'listen_addresses',
    'port',
    'max_connections',
    'shared_buffers',
    'work_mem',
    'maintenance_work_mem',
    'password_encryption'
)
ORDER BY name;

\echo ''
\echo '[4/7] Settings currently waiting for restart'

SELECT
    name,
    setting,
    context,
    pending_restart
FROM pg_settings
WHERE pending_restart
ORDER BY name;

\echo ''
\echo '[5/7] Configuration-file parsing errors'

SELECT
    sourcefile,
    sourceline,
    name,
    setting,
    error
FROM pg_file_settings
WHERE error IS NOT NULL
ORDER BY sourcefile, sourceline;

\echo ''
\echo '[6/7] Parsed pg_hba.conf rules'

SELECT
    rule_number,
    file_name,
    line_number,
    type,
    database,
    user_name,
    address,
    auth_method,
    error
FROM pg_hba_file_rules
ORDER BY rule_number NULLS LAST, line_number;

\echo ''
\echo '[7/7] pg_hba.conf parsing errors'

SELECT
    file_name,
    line_number,
    error
FROM pg_hba_file_rules
WHERE error IS NOT NULL
ORDER BY file_name, line_number;

\echo ''
\echo '============================================================'
\echo 'SAFE-READ inspection complete.'
\echo 'No PostgreSQL configuration or database state was modified.'
\echo '============================================================'
