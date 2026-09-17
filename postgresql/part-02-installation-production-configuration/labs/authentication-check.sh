#!/usr/bin/env bash
# Part 2.10
# [TUTORIAL-ACCEPTANCE — SAFE-READ]
set -euo pipefail
command -v psql >/dev/null || { echo "FAIL: psql not found" >&2; exit 1; }
PSQL=(psql -X -v ON_ERROR_STOP=1 --no-psqlrc)

"${PSQL[@]}" <<'SQL'
\pset pager off
\echo '=== Authentication / network baseline ==='
SELECT current_database(), current_user, current_setting('server_version');

SELECT name, setting, context, source, pending_restart
FROM pg_settings
WHERE name IN (
 'listen_addresses','port','ssl','hba_file','ident_file',
 'password_encryption','authentication_timeout'
)
ORDER BY name;

\echo '=== HBA parsing errors only ==='
SELECT rule_number, error
FROM pg_hba_file_rules
WHERE error IS NOT NULL
ORDER BY rule_number;

\echo '=== Connection privilege context ==='
SELECT datname, datallowconn,
       has_database_privilege(current_user, datname, 'CONNECT') AS current_user_can_connect
FROM pg_database
ORDER BY datname;
SQL

echo "SAFE-READ complete. No authentication/network state was changed."
