#!/usr/bin/env bash
# Part 6.4 — Build a Physical Standby
# PostgreSQL 18
# STATE-CHANGING — APPROVED DISPOSABLE STANDBY ONLY
set -Eeuo pipefail

fail(){ printf 'FAIL: %s\n' "$*" >&2; exit 1; }
info(){ printf 'INFO: %s\n' "$*"; }
need(){ command -v "$1" >/dev/null 2>&1 || fail "Missing command: $1"; }

: "${PRIMARY_HOST:?Set PRIMARY_HOST}"
: "${PRIMARY_PORT:=5432}"
: "${REPLICATION_USER:?Set REPLICATION_USER}"
: "${STANDBY_PGDATA:?Set STANDBY_PGDATA}"
: "${EXPECTED_STANDBY_HOST:?Set EXPECTED_STANDBY_HOST}"
: "${MAX_RATE:=}"

for c in hostname pg_basebackup pg_verifybackup psql df find mkdir; do need "$c"; done

ACTUAL_HOST="$(hostname -s)"
[[ "$ACTUAL_HOST" == "$EXPECTED_STANDBY_HOST" ]] ||
  fail "Host mismatch: expected $EXPECTED_STANDBY_HOST, got $ACTUAL_HOST"

[[ "$STANDBY_PGDATA" = /* ]] || fail "PGDATA must be absolute"
case "$STANDBY_PGDATA" in
  ""|"/"|"/var"|"/var/lib"|"/usr"|"/etc"|"/home") fail "Unsafe PGDATA: $STANDBY_PGDATA";;
esac

info "Host identity PASS: $ACTUAL_HOST"
info "Target PGDATA: $STANDBY_PGDATA"
info "Primary: $PRIMARY_HOST:$PRIMARY_PORT"
info "No password will be printed or requested."

# This connection intentionally relies on an approved libpq auth mechanism.
PRIMARY_VERSION_NUM="$(
  psql -X -At "host=$PRIMARY_HOST port=$PRIMARY_PORT user=$REPLICATION_USER dbname=postgres" \
    -c 'SHOW server_version_num'
)" || fail "Primary connectivity/authentication failed"

[[ "$PRIMARY_VERSION_NUM" =~ ^[0-9]+$ ]] || fail "Invalid server_version_num"
(( PRIMARY_VERSION_NUM >= 180000 && PRIMARY_VERSION_NUM < 190000 )) ||
  fail "Lab targets PostgreSQL 18; primary reports $PRIMARY_VERSION_NUM"
info "PostgreSQL 18 primary gate PASS"

TABLESPACES="$(
  psql -X -At "host=$PRIMARY_HOST port=$PRIMARY_PORT user=$REPLICATION_USER dbname=postgres" \
    -c "SELECT spcname || '|' || pg_tablespace_location(oid)
        FROM pg_tablespace
        WHERE spcname NOT IN ('pg_default','pg_global')
        ORDER BY spcname"
)" || fail "Tablespace inspection failed"

if [[ -n "$TABLESPACES" ]]; then
  printf '%s\n' "$TABLESPACES"
  fail "User-defined tablespaces exist. Validate destination mapping/capacity first."
fi

df -h "$STANDBY_PGDATA" 2>/dev/null || df -h "$(dirname "$STANDBY_PGDATA")"

if [[ -d "$STANDBY_PGDATA" ]] &&
   [[ -n "$(find "$STANDBY_PGDATA" -mindepth 1 -maxdepth 1 -print -quit 2>/dev/null)" ]]; then
  fail "PGDATA is populated. Quarantine/prepare it explicitly; nothing will be deleted."
fi

mkdir -p "$STANDBY_PGDATA"

printf '\nType exactly:\nBUILD-STANDBY:%s:%s\n' "$ACTUAL_HOST" "$STANDBY_PGDATA"
read -r CONFIRM
[[ "$CONFIRM" == "BUILD-STANDBY:$ACTUAL_HOST:$STANDBY_PGDATA" ]] ||
  fail "Confirmation mismatch"

cmd=(
  pg_basebackup
  --host="$PRIMARY_HOST"
  --port="$PRIMARY_PORT"
  --username="$REPLICATION_USER"
  --pgdata="$STANDBY_PGDATA"
  --format=plain
  --wal-method=stream
  --write-recovery-conf
  --progress
)
[[ -z "$MAX_RATE" ]] || cmd+=(--max-rate="$MAX_RATE")

info "Starting pg_basebackup"
"${cmd[@]}" || fail "BASEBACKUP_FAILED; quarantine partial target before retry"

[[ -f "$STANDBY_PGDATA/standby.signal" ]] || fail "standby.signal missing"
[[ -f "$STANDBY_PGDATA/backup_manifest" ]] || fail "backup_manifest missing"

info "Running pg_verifybackup"
pg_verifybackup "$STANDBY_PGDATA" ||
  fail "VERIFYBACKUP_FAILED; DO NOT START standby"

cat <<'EOF'

BOOTSTRAP FILESYSTEM PHASE: PASS

Do not print postgresql.auto.conf or primary_conninfo as evidence.

Start PostgreSQL with the approved environment-specific mechanism, then run:

  SELECT pg_is_in_recovery();

Required: true

Then inspect:

  SELECT status FROM pg_stat_wal_receiver;

If the expected standby returns pg_is_in_recovery() = false:
  FAIL / STOP

Detailed LSN/replay validation belongs to Part 6.5.

Cleanup: NONE is automatic.
On failure preserve diagnostics, quarantine the incomplete target,
correct the cause, and rebuild from a clean approved target.
EOF
