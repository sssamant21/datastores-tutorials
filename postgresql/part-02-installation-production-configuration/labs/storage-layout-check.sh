#!/usr/bin/env bash

# [TUTORIAL-ACCEPTANCE — SAFE-READ]
#
# Part 2.6 — Data Directory, Tablespace, and Filesystem Design
#
# Purpose:
#   Inspect an explicitly supplied PostgreSQL 18 PGDATA and its
#   underlying storage without modifying PostgreSQL or the host.

set -u

PASS=0
WARN=0
BLOCK=0
REVIEW=0

section() { printf '\n=== %s ===\n' "$1"; }
pass() { printf 'PASS: %s\n' "$1"; PASS=$((PASS + 1)); }
warning() { printf 'WARNING: %s\n' "$1"; WARN=$((WARN + 1)); }
blocker() { printf 'BLOCKER: %s\n' "$1"; BLOCK=$((BLOCK + 1)); }
review() { printf 'REQUIRES VALIDATION: %s\n' "$1"; REVIEW=$((REVIEW + 1)); }

section "Identity"
date
hostname
id
uname -a

section "PGDATA"

if [ -z "${PGDATA:-}" ]; then
    blocker "PGDATA is not explicitly set."
    printf '\nSafety result: BLOCKER\n'
    exit 2
fi

printf 'PGDATA=%s\n' "$PGDATA"

if [ ! -d "$PGDATA" ]; then
    blocker "PGDATA does not exist: $PGDATA"
    printf '\nSafety result: BLOCKER\n'
    exit 2
fi

pass "PGDATA exists."

if [ ! -r "$PGDATA" ]; then
    blocker "PGDATA is not readable by the current account."
    printf '\nSafety result: BLOCKER\n'
    exit 2
fi

section "Cluster Marker"

if [ -f "$PGDATA/PG_VERSION" ]; then
    printf 'PG_VERSION='
    cat "$PGDATA/PG_VERSION"
    printf '\n'
    if grep -qx '18' "$PGDATA/PG_VERSION" 2>/dev/null; then
        pass "PG_VERSION identifies PostgreSQL 18."
    else
        review "PG_VERSION is not PostgreSQL 18; validate the intended target."
    fi
else
    blocker "PG_VERSION is missing."
fi

section "Ownership and Permissions"

if stat -c 'owner=%U group=%G mode=%a path=%n' "$PGDATA"; then
    pass "PGDATA ownership and mode were inspected."
else
    review "Unable to inspect PGDATA ownership or permissions."
fi

printf '%s\n' \
  "Permission interpretation must follow the approved owner-only" \
  "or intentional PostgreSQL group-read access model."

section "PGDATA Filesystem"

df -hT "$PGDATA" || review "Unable to inspect filesystem capacity."
df -i "$PGDATA" || review "Unable to inspect inode capacity."

if command -v findmnt >/dev/null 2>&1; then
    findmnt -T "$PGDATA" || review "Unable to resolve the PGDATA mount."
    printf '\nFilesystem type:\n'
    findmnt -T "$PGDATA" -no FSTYPE || true
    printf '\nMount options:\n'
    findmnt -T "$PGDATA" -no OPTIONS || true
else
    review "findmnt is unavailable; mount topology requires separate validation."
fi

section "Cluster Storage Markers"

for item in base global pg_xact pg_multixact pg_tblspc; do
    if [ -e "$PGDATA/$item" ]; then
        pass "$item exists."
    else
        warning "$item was not found."
    fi
done

section "WAL"

WAL_PATH="$PGDATA/pg_wal"

if [ ! -e "$WAL_PATH" ]; then
    blocker "pg_wal is missing."
else
    ls -ld "$WAL_PATH"
    RESOLVED_WAL="$(readlink -f "$WAL_PATH" 2>/dev/null || true)"

    if [ -z "$RESOLVED_WAL" ]; then
        blocker "Unable to resolve the physical pg_wal location."
    elif [ ! -d "$RESOLVED_WAL" ]; then
        blocker "Resolved WAL target is unavailable: $RESOLVED_WAL"
    else
        printf 'Resolved WAL path: %s\n' "$RESOLVED_WAL"
        pass "WAL target resolves to an available directory."
        df -hT "$RESOLVED_WAL" || review "Unable to inspect WAL filesystem capacity."
        df -i "$RESOLVED_WAL" || review "Unable to inspect WAL inode capacity."

        if command -v findmnt >/dev/null 2>&1; then
            findmnt -T "$RESOLVED_WAL" || review "Unable to resolve WAL mount topology."
        fi
    fi
fi

section "External Tablespaces"

TBLSPC="$PGDATA/pg_tblspc"

if [ ! -d "$TBLSPC" ]; then
    blocker "pg_tblspc directory is missing."
else
    TABLESPACE_COUNT=0

    while IFS= read -r link; do
        [ -n "$link" ] || continue
        TABLESPACE_COUNT=$((TABLESPACE_COUNT + 1))

        printf '\nTablespace link: %s\n' "$link"
        ls -ld "$link"

        TARGET="$(readlink -f "$link" 2>/dev/null || true)"

        if [ -z "$TARGET" ] || [ ! -d "$TARGET" ]; then
            blocker "Tablespace target is unavailable: $link"
            continue
        fi

        printf 'Resolved target: %s\n' "$TARGET"
        pass "Tablespace target is available."
        df -hT "$TARGET" || review "Unable to inspect tablespace filesystem capacity."
        df -i "$TARGET" || review "Unable to inspect tablespace inode capacity."

        if command -v findmnt >/dev/null 2>&1; then
            findmnt -T "$TARGET" || review "Unable to resolve tablespace mount topology."
        fi

    done < <(
        find "$TBLSPC" \
            -maxdepth 1 \
            -mindepth 1 \
            -type l \
            -print 2>/dev/null
    )

    if [ "$TABLESPACE_COUNT" -eq 0 ]; then
        printf '%s\n' \
          "NOT APPLICABLE: no external/user-defined tablespace links detected."
    fi
fi

section "Safety Contract"

printf '%s\n' \
  "No files created." \
  "No files removed." \
  "No ownership changed." \
  "No permissions changed." \
  "No filesystem mounted or unmounted." \
  "No filesystem resized." \
  "No PostgreSQL process started or stopped." \
  "No PostgreSQL configuration modified." \
  "No tablespace modified." \
  "No synthetic storage writes generated." \
  "No automatic remediation performed."

section "Summary"

printf 'PASS=%d\n' "$PASS"
printf 'WARNING=%d\n' "$WARN"
printf 'BLOCKER=%d\n' "$BLOCK"
printf 'REQUIRES_VALIDATION=%d\n' "$REVIEW"

if [ "$BLOCK" -gt 0 ]; then
    printf 'Safety result: BLOCKER\n'
    exit 2
fi

if [ "$REVIEW" -gt 0 ]; then
    printf 'Safety result: REQUIRES VALIDATION\n'
    exit 1
fi

if [ "$WARN" -gt 0 ]; then
    printf 'Safety result: WARNING\n'
    exit 0
fi

printf 'Safety result: PASS\n'
exit 0
