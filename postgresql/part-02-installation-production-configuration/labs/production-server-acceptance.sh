#!/usr/bin/env bash
# Part 2.15 — Integrated Project: Build a Production-Style PostgreSQL Server
# [TUTORIAL-ACCEPTANCE — SAFE-READ]
# Target: PostgreSQL 18
#
# Default behavior:
#   - PostgreSQL inspection only.
#
# Optional CHECK_HOST=1:
#   - read-only Linux host inspection.
#
# Optional PG_SYSTEMD_UNIT:
#   - read-only systemd inspection when CHECK_HOST=1.
#
# This script DOES NOT:
#   - install packages
#   - initialize a cluster
#   - create/edit files or directories
#   - change ownership/permissions
#   - execute ALTER SYSTEM
#   - reload/restart/start/stop/enable PostgreSQL
#   - modify pg_hba.conf / pg_ident.conf
#   - change roles/passwords/TLS/firewalls
#   - terminate sessions
#   - reset statistics
#   - execute application DDL/DML
#
# Use approved libpq authentication (.pgpass, PGPASSFILE, secret wrapper, etc.).
# Do not hard-code credentials in this script.

set -euo pipefail

CHECK_HOST="${CHECK_HOST:-0}"
PG_SYSTEMD_UNIT="${PG_SYSTEMD_UNIT:-}"

command -v psql >/dev/null 2>&1 || {
  echo "FAIL: psql was not found in PATH." >&2
  exit 1
}

PSQL=(psql -X -v ON_ERROR_STOP=1 --no-psqlrc)

echo "=================================================================="
echo "Part 2.15 — PostgreSQL 18 Production-Style Server Acceptance"
echo "[TUTORIAL-ACCEPTANCE — SAFE-READ]"
echo "=================================================================="
echo

echo ">>> PostgreSQL connectivity and identity"

"${PSQL[@]}" <<'SQL'
\pset pager off

SELECT
    current_database() AS database_name,
    current_user AS current_user,
    current_setting('server_version') AS server_version,
    current_setting('server_version_num') AS server_version_num,
    pg_postmaster_start_time() AS postmaster_start_time;

\echo ''
\echo '>>> Configuration locations'
SELECT name, setting
FROM pg_settings
WHERE name IN (
    'data_directory',
    'config_file',
    'hba_file',
    'ident_file'
)
ORDER BY name;

\echo ''
\echo '>>> Configuration provenance summary'
SELECT
    source,
    COUNT(*) AS settings
FROM pg_settings
GROUP BY source
ORDER BY source;

\echo ''
\echo '>>> Pending restart settings'
SELECT
    name,
    setting,
    unit,
    context,
    source,
    pending_restart
FROM pg_settings
WHERE pending_restart
ORDER BY name;

\echo ''
\echo '>>> Memory, worker, and PostgreSQL 18 I/O baseline'
SELECT
    name,
    setting,
    unit,
    context,
    source,
    pending_restart
FROM pg_settings
WHERE name IN (
    'shared_buffers',
    'work_mem',
    'hash_mem_multiplier',
    'maintenance_work_mem',
    'autovacuum_work_mem',
    'temp_buffers',
    'effective_cache_size',
    'huge_pages',
    'max_worker_processes',
    'max_parallel_workers',
    'max_parallel_workers_per_gather',
    'io_method',
    'io_workers',
    'io_max_concurrency'
)
ORDER BY name;

\echo ''
\echo '>>> Connection, network, and timeout baseline'
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
    'ssl',
    'max_connections',
    'reserved_connections',
    'superuser_reserved_connections',
    'authentication_timeout',
    'statement_timeout',
    'lock_timeout',
    'transaction_timeout',
    'idle_in_transaction_session_timeout',
    'idle_session_timeout',
    'client_connection_check_interval'
)
ORDER BY name;

\echo ''
\echo '>>> Client backend session counts'
SELECT
    COALESCE(state, '<null>') AS state,
    COUNT(*) AS sessions
FROM pg_stat_activity
WHERE backend_type = 'client backend'
GROUP BY state
ORDER BY state;

\echo ''
\echo '>>> WAL, checkpoint, and background-writer baseline'
SELECT
    name,
    CASE
        WHEN name IN ('archive_command', 'archive_library')
            THEN CASE
                WHEN setting = '' THEN '<empty>'
                ELSE '<configured>'
            END
        ELSE setting
    END AS setting,
    unit,
    context,
    source,
    pending_restart
FROM pg_settings
WHERE name IN (
    'wal_level',
    'wal_buffers',
    'wal_compression',
    'checkpoint_timeout',
    'checkpoint_completion_target',
    'max_wal_size',
    'min_wal_size',
    'archive_mode',
    'archive_command',
    'archive_library',
    'max_wal_senders',
    'bgwriter_delay',
    'bgwriter_lru_maxpages',
    'bgwriter_lru_multiplier'
)
ORDER BY name;

\echo ''
\echo '>>> Logging and diagnostics baseline'
SELECT
    name,
    setting,
    unit,
    context,
    source,
    pending_restart
FROM pg_settings
WHERE name IN (
    'logging_collector',
    'log_destination',
    'log_min_messages',
    'log_min_error_statement',
    'log_connections',
    'log_disconnections',
    'log_checkpoints',
    'log_lock_waits',
    'log_lock_failures',
    'log_temp_files',
    'log_autovacuum_min_duration',
    'log_error_verbosity'
)
ORDER BY name;

\echo ''
\echo '>>> Database inventory'
SELECT
    datname,
    pg_size_pretty(pg_database_size(datname)) AS database_size
FROM pg_database
WHERE datallowconn
ORDER BY datname;

\echo ''
\echo '>>> Tablespace inventory'
SELECT
    spcname,
    pg_tablespace_location(oid) AS location
FROM pg_tablespace
ORDER BY spcname;

\echo ''
\echo '>>> Configuration-file parsing errors'
\echo 'Privilege dependent. A permission error stops this acceptance run.'
SELECT
    sourcefile,
    sourceline,
    name,
    error
FROM pg_file_settings
WHERE error IS NOT NULL
ORDER BY seqno;

\echo ''
\echo '>>> HBA parsing errors'
\echo 'Rule details are intentionally omitted from the generic evidence output.'
SELECT
    rule_number,
    error
FROM pg_hba_file_rules
WHERE error IS NOT NULL
ORDER BY rule_number;

\echo ''
\echo '>>> Recovery/replication identity'
SELECT
    pg_is_in_recovery() AS is_in_recovery;

\echo ''
\echo '>>> Final PostgreSQL SAFE-READ inspection completed'
SQL

echo
echo ">>> Host inspection mode"

if [[ "$CHECK_HOST" == "1" ]]; then
  echo "CHECK_HOST=1: collecting read-only host evidence."
  echo

  if command -v uname >/dev/null 2>&1; then
    echo "--- uname ---"
    uname -a || true
  fi

  if [[ -r /etc/os-release ]]; then
    echo
    echo "--- OS release ---"
    cat /etc/os-release || true
  fi

  if command -v nproc >/dev/null 2>&1; then
    echo
    echo "--- CPU count ---"
    nproc || true
  fi

  if command -v free >/dev/null 2>&1; then
    echo
    echo "--- Memory ---"
    free -h || true
  fi

  if command -v df >/dev/null 2>&1; then
    echo
    echo "--- Filesystem capacity ---"
    df -h || true
    echo
    echo "--- Filesystem inodes ---"
    df -i || true
  fi

  echo
  echo "--- Shell resource limits ---"
  echo "open files: $(ulimit -n 2>/dev/null || echo '<unavailable>')"
  echo "max user processes: $(ulimit -u 2>/dev/null || echo '<unavailable>')"

  if [[ -n "$PG_SYSTEMD_UNIT" ]]; then
    echo
    echo "--- systemd service inspection: $PG_SYSTEMD_UNIT ---"

    if command -v systemctl >/dev/null 2>&1; then
      systemctl is-enabled "$PG_SYSTEMD_UNIT" 2>&1 || true
      systemctl is-active "$PG_SYSTEMD_UNIT" 2>&1 || true
      systemctl status "$PG_SYSTEMD_UNIT" --no-pager 2>&1 || true
    else
      echo "REVIEW: systemctl not available on this host."
    fi
  else
    echo
    echo "PG_SYSTEMD_UNIT not supplied; systemd unit inspection skipped."
  fi
else
  echo "CHECK_HOST is not 1; host inspection skipped."
  echo "Run with CHECK_HOST=1 only when read-only host inspection is appropriate."
fi

echo
echo "=================================================================="
echo "SAFE-READ ACCEPTANCE COMPLETE"
echo
echo "No PostgreSQL or host state was intentionally modified."
echo
echo "Manual/external validation is still required for:"
echo "  - approved configuration values and drift"
echo "  - storage latency/IOPS/throughput and capacity headroom"
echo "  - firewall/network-policy correctness"
echo "  - TLS/security compliance"
echo "  - backup success and restore testing"
echo "  - HA/failover behavior"
echo "  - monitoring/alerting"
echo "  - application connectivity and workload behavior"
echo "  - RPO/RTO"
echo "=================================================================="
