#!/usr/bin/env bash

# [TUTORIAL-ACCEPTANCE — SAFE-READ]
#
# Part 2.5 — Cluster Initialization with initdb
#
# Purpose:
#   Inspect PostgreSQL 18 cluster-initialization prerequisites and,
#   when PGDATA is already initialized, validate cluster metadata
#   without starting or modifying PostgreSQL.
#
# This script does NOT:
#   - invoke sudo/su/runuser
#   - create/delete/move files or directories
#   - change ownership or permissions
#   - run initdb or pg_ctl initdb
#   - enable/disable data checksums
#   - start/stop/restart PostgreSQL
#   - modify systemd
#   - modify PostgreSQL configuration
#   - modify pg_hba.conf or pg_ident.conf
#   - modify firewall/network configuration
#   - install packages

set -u

PGDATA="${PGDATA:-/pgdata/18/main}"
PG_BIN="${POSTGRES_BIN:-/opt/postgresql/18/bin}"

section() {
    printf '\n============================================================\n'
    printf '%s\n' "$1"
    printf '============================================================\n'
}

command_exists() {
    command -v "$1" >/dev/null 2>&1
}

section "SAFETY CLASSIFICATION"

cat <<'EOF'
[TUTORIAL-ACCEPTANCE — SAFE-READ]

Mode:
  Inspect
    ↓
  Classify
    ↓
  Report

No automatic remediation is performed.
EOF

section "CURRENT IDENTITY"

id 2>/dev/null || \
    printf 'REQUIRES VALIDATION: unable to inspect current identity.\n'

if [[ "$(id -u 2>/dev/null || printf 'unknown')" == "0" ]]; then
    printf '\nWARNING: current shell is running as root.\n'
    printf 'initdb itself must NOT be executed as root.\n'
fi

section "OPERATING SYSTEM"

if [[ -r /etc/os-release ]]; then
    cat /etc/os-release
else
    printf 'REQUIRES VALIDATION: /etc/os-release is not readable.\n'
fi

section "ARCHITECTURE"

uname -m 2>/dev/null || \
    printf 'REQUIRES VALIDATION: unable to inspect architecture.\n'

section "POSTGRESQL 18 BINARY VALIDATION"

INITDB="${PG_BIN}/initdb"
PG_CONTROLDATA="${PG_BIN}/pg_controldata"

printf 'Expected PostgreSQL binary directory: %s\n' "$PG_BIN"
printf 'Expected initdb: %s\n' "$INITDB"

if [[ -x "$INITDB" ]]; then
    initdb_version="$("$INITDB" --version 2>&1 || true)"
    printf 'initdb version: %s\n' "$initdb_version"

    case "$initdb_version" in
        *"PostgreSQL 18"*)
            printf 'PASS: PostgreSQL 18 initdb detected.\n'
            ;;
        *)
            printf 'BLOCKER: expected PostgreSQL 18 initdb.\n'
            ;;
    esac
else
    printf 'REQUIRES VALIDATION: expected initdb is not executable.\n'

    if command_exists initdb; then
        printf 'PATH-resolved initdb: %s\n' "$(command -v initdb)"
        initdb --version 2>&1 || true
        printf 'WARNING: PATH resolution is evidence only; do not assume it is the approved binary.\n'
    fi
fi

section "PGDATA"

printf 'Expected PGDATA: %s\n' "$PGDATA"

if [[ -e "$PGDATA" ]]; then
    ls -ld "$PGDATA" 2>/dev/null || \
        printf 'REQUIRES VALIDATION: unable to inspect PGDATA metadata.\n'
else
    printf 'INFO: PGDATA does not currently exist.\n'
    printf 'This can be expected before an approved initialization.\n'
fi

section "FILESYSTEM CAPACITY"

if [[ -e "$PGDATA" ]]; then
    df -h "$PGDATA" 2>/dev/null || \
        printf 'REQUIRES VALIDATION: unable to inspect PGDATA filesystem capacity.\n'

    df -i "$PGDATA" 2>/dev/null || \
        printf 'REQUIRES VALIDATION: unable to inspect PGDATA inode capacity.\n'
else
    parent="$PGDATA"

    while [[ "$parent" != "/" && ! -e "$parent" ]]; do
        parent="$(dirname "$parent")"
    done

    printf 'Nearest existing parent: %s\n' "$parent"

    df -h "$parent" 2>/dev/null || \
        printf 'REQUIRES VALIDATION: unable to inspect parent filesystem capacity.\n'

    df -i "$parent" 2>/dev/null || \
        printf 'REQUIRES VALIDATION: unable to inspect parent inode capacity.\n'
fi

section "TARGET DIRECTORY CONTENTS"

if [[ -d "$PGDATA" ]]; then
    contents="$(find "$PGDATA" -mindepth 1 -maxdepth 1 -print 2>/dev/null || true)"

    if [[ -n "$contents" ]]; then
        printf '%s\n' "$contents"
        printf '\nINFO: PGDATA contains existing content.\n'
        printf 'Determine whether this is an initialized cluster or unexplained state.\n'
    else
        printf 'PASS: PGDATA is currently empty.\n'
    fi
else
    printf 'NOT APPLICABLE: PGDATA is not currently a directory.\n'
fi

section "CLUSTER MARKERS"

cluster_detected=0

for marker in \
    "PG_VERSION" \
    "global/pg_control" \
    "base" \
    "pg_wal" \
    "postgresql.conf" \
    "pg_hba.conf" \
    "pg_ident.conf"
do
    if [[ -e "${PGDATA}/${marker}" ]]; then
        printf 'PRESENT: %s\n' "$marker"
        cluster_detected=1
    else
        printf 'NOT PRESENT: %s\n' "$marker"
    fi
done

if [[ "$cluster_detected" -eq 1 ]]; then
    printf '\nINFO: PostgreSQL cluster markers were detected.\n'
else
    printf '\nINFO: no PostgreSQL cluster markers were detected.\n'
fi

section "PG_VERSION"

if [[ -r "${PGDATA}/PG_VERSION" ]]; then
    pg_version="$(cat "${PGDATA}/PG_VERSION" 2>/dev/null || true)"
    printf 'PG_VERSION: %s\n' "$pg_version"

    if [[ "$pg_version" == "18" ]]; then
        printf 'PASS: cluster major version is PostgreSQL 18.\n'
    else
        printf 'BLOCKER: expected PG_VERSION 18.\n'
    fi
elif [[ -e "${PGDATA}/PG_VERSION" ]]; then
    printf 'REQUIRES VALIDATION: PG_VERSION exists but is not readable.\n'
else
    printf 'NOT APPLICABLE: PG_VERSION does not exist.\n'
fi

section "CONTROL METADATA"

if [[ -e "${PGDATA}/global/pg_control" ]]; then
    if [[ -x "$PG_CONTROLDATA" ]]; then
        "$PG_CONTROLDATA" "$PGDATA" 2>&1 || \
            printf 'REQUIRES VALIDATION: pg_controldata could not inspect the cluster.\n'
    elif command_exists pg_controldata; then
        printf 'WARNING: approved absolute pg_controldata was not found.\n'
        printf 'PATH-resolved candidate: %s\n' "$(command -v pg_controldata)"
        printf 'REQUIRES VALIDATION: confirm binary/version before using it against PGDATA.\n'
    else
        printf 'REQUIRES VALIDATION: pg_controldata was not detected.\n'
    fi
else
    printf 'NOT APPLICABLE: pg_control was not detected.\n'
fi

section "GENERATED CONFIGURATION"

for file in postgresql.conf pg_hba.conf pg_ident.conf; do
    path="${PGDATA}/${file}"

    if [[ -r "$path" ]]; then
        printf 'PASS: readable %s\n' "$file"
    elif [[ -e "$path" ]]; then
        printf 'REQUIRES VALIDATION: %s exists but is not readable.\n' "$file"
    else
        printf 'NOT PRESENT: %s\n' "$file"
    fi
done

section "BOOTSTRAP HBA INSPECTION"

HBA="${PGDATA}/pg_hba.conf"

if [[ -r "$HBA" ]]; then
    printf 'Active/non-comment pg_hba.conf entries:\n\n'

    awk '
        /^[[:space:]]*#/ { next }
        /^[[:space:]]*$/ { next }
        { print }
    ' "$HBA" 2>/dev/null || \
        printf 'REQUIRES VALIDATION: unable to inspect pg_hba.conf.\n'
else
    printf 'NOT APPLICABLE / REQUIRES VALIDATION: readable pg_hba.conf not available.\n'
fi

section "LOCALE ENVIRONMENT"

locale 2>/dev/null || \
    printf 'REQUIRES VALIDATION: unable to inspect locale environment.\n'

section "POSTGRESQL PROCESS DISCOVERY"

postgres_processes="$(ps -ef 2>/dev/null | grep '[p]ostgres' || true)"

if [[ -n "$postgres_processes" ]]; then
    printf '%s\n' "$postgres_processes"
    printf '\nREQUIRES VALIDATION: PostgreSQL process(es) detected.\n'
    printf '%s\n' \
        'Determine owner, binary, version, PGDATA, port, service, and purpose.' \
        'Do not automatically stop or restart the process.'
else
    printf 'PASS: no PostgreSQL server process detected.\n'
fi

section "POSTGRESQL 18 INITIALIZATION EXPECTATIONS"

cat <<'EOF'
Validate the approved initialization record against the actual cluster.

PostgreSQL major version:
  18

initdb execution:
  non-root PostgreSQL server owner

Data checksums:
  enabled by default in PostgreSQL 18 unless explicitly disabled

Default WAL location:
  PGDATA/pg_wal

Default WAL segment size:
  16 MB

Initialization should NOT automatically imply:
  server startup
  systemd enablement
  network exposure
  firewall changes
  broad HBA access
EOF

section "STOP CONDITIONS"

cat <<'EOF'
Stop or classify BLOCKER / REQUIRES VALIDATION when:

  - the approved initdb binary cannot be identified
  - the intended PostgreSQL major version is not 18
  - initialization would be executed as root
  - PGDATA points to an unexpected location
  - PGDATA contains unexplained existing files
  - an existing PostgreSQL cluster cannot be ruled out
  - ownership or permissions are unresolved
  - filesystem/storage is unresolved
  - locale/provider or encoding is unresolved
  - checksum policy is unresolved
  - bootstrap authentication is unresolved
  - WAL layout is unresolved
  - unexpected PostgreSQL processes exist
  - PG_VERSION is not 18
  - control metadata conflicts with the approved design
EOF

section "SAFETY RESULT"

cat <<'EOF'
[TUTORIAL-ACCEPTANCE — SAFE-READ]

Inspection completed.

This script did NOT:
  - invoke sudo, su, or runuser
  - create/delete/move files or directories
  - modify ownership or permissions
  - mount/unmount/format storage
  - run initdb
  - run pg_ctl initdb
  - enable or disable data checksums
  - start/stop/restart PostgreSQL
  - modify systemd
  - modify postgresql.conf
  - modify pg_hba.conf
  - modify pg_ident.conf
  - modify firewall/network configuration
  - expose PostgreSQL to the network
  - install/remove/upgrade packages
EOF
