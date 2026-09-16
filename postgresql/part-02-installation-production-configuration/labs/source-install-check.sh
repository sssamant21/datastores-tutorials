#!/usr/bin/env bash

# [TUTORIAL-ACCEPTANCE — SAFE-READ]
#
# Part 2.4 — Source Installation and Build Fundamentals
#
# Purpose:
#   Inspect PostgreSQL source-build prerequisites and an existing
#   source installation without changing the host.
#
# This script does NOT:
#   - invoke sudo
#   - install packages or build dependencies
#   - modify repositories
#   - download/extract source
#   - configure or compile PostgreSQL
#   - execute regression tests
#   - install PostgreSQL
#   - modify ownership or permissions
#   - modify PATH or create symlinks
#   - run initdb
#   - create/delete clusters
#   - start/stop PostgreSQL
#   - modify systemd/PostgreSQL/firewall configuration

set -u

PREFIX="${POSTGRES_SOURCE_PREFIX:-/opt/postgresql/18}"

section() {
    printf '\n============================================================\n'
    printf '%s\n' "$1"
    printf '============================================================\n'
}

command_exists() {
    command -v "$1" >/dev/null 2>&1
}

show_tool() {
    local cmd="$1"

    if command_exists "$cmd"; then
        printf '\n%s\n' "$cmd"
        printf 'Path: %s\n' "$(command -v "$cmd")"

        case "$cmd" in
            perl)
                "$cmd" -v 2>&1 | head -n 3 || true
                ;;
            *)
                "$cmd" --version 2>&1 | head -n 3 || true
                ;;
        esac
    else
        printf '\n%s: NOT DETECTED\n' "$cmd"
    fi
}

show_pg_binary() {
    local binary="$1"
    local path="${PREFIX}/bin/${binary}"

    if [[ -x "$path" ]]; then
        printf '%s: %s\n' "$binary" "$path"
        "$path" --version 2>&1 || \
            printf 'REQUIRES VALIDATION: unable to inspect %s.\n' "$path"
    else
        printf '%s: NOT FOUND/EXECUTABLE at %s\n' "$binary" "$path"
    fi
}

section "OPERATING SYSTEM"

if [[ -r /etc/os-release ]]; then
    cat /etc/os-release
else
    printf 'REQUIRES VALIDATION: /etc/os-release is not readable.\n'
fi

section "ARCHITECTURE"

uname -m

section "FILESYSTEM CAPACITY"

df -h 2>/dev/null || \
    printf 'REQUIRES VALIDATION: unable to inspect filesystem capacity.\n'

section "INODE CAPACITY"

df -i 2>/dev/null || \
    printf 'REQUIRES VALIDATION: unable to inspect inode capacity.\n'

section "BUILD TOOLCHAIN"

for cmd in cc gcc make gmake meson ninja flex bison perl tar; do
    show_tool "$cmd"
done

section "PACKAGE-MANAGED POSTGRESQL INVENTORY"

if command_exists rpm; then
    printf '\nRPM PostgreSQL packages:\n'
    rpm -qa 2>/dev/null |
        grep -i postgres ||
        printf 'INFO: no PostgreSQL packages returned by RPM inventory.\n'
fi

if command_exists dpkg; then
    printf '\nDPKG PostgreSQL packages:\n'
    dpkg -l 2>/dev/null |
        grep -i postgres ||
        printf 'INFO: no PostgreSQL packages returned by DPKG inventory.\n'
fi

if ! command_exists rpm && ! command_exists dpkg; then
    printf 'NOT APPLICABLE: RPM/DPKG inventory tools were not detected.\n'
fi

section "SHELL POSTGRESQL RESOLUTION"

for cmd in postgres psql initdb pg_config; do
    if command_exists "$cmd"; then
        printf '%s -> %s\n' "$cmd" "$(command -v "$cmd")"
        "$cmd" --version 2>&1 || true
    else
        printf '%s: NOT FOUND IN PATH\n' "$cmd"
    fi
done

section "SOURCE INSTALLATION PREFIX"

printf 'Expected tutorial/source prefix: %s\n' "$PREFIX"

if [[ -e "$PREFIX" ]]; then
    printf '\nPREFIX EXISTS\n'
    ls -ld "$PREFIX" 2>/dev/null || \
        printf 'REQUIRES VALIDATION: unable to inspect prefix metadata.\n'

    if [[ -d "${PREFIX}/bin" ]]; then
        printf '\nPrefix bin directory:\n'
        ls -ld "${PREFIX}/bin" 2>/dev/null || true
    else
        printf 'REQUIRES VALIDATION: %s/bin is not present.\n' "$PREFIX"
    fi
else
    printf 'INFO: source installation prefix does not currently exist.\n'
fi

section "SOURCE POSTGRESQL BINARIES"

for binary in postgres psql initdb pg_config pg_ctl pg_dump pg_restore pg_isready; do
    show_pg_binary "$binary"
done

section "SOURCE PG_CONFIG LAYOUT"

PG_CONFIG="${PREFIX}/bin/pg_config"

if [[ -x "$PG_CONFIG" ]]; then
    printf 'version: '
    "$PG_CONFIG" --version 2>/dev/null || printf 'REQUIRES VALIDATION\n'

    printf 'bindir: '
    "$PG_CONFIG" --bindir 2>/dev/null || printf 'REQUIRES VALIDATION\n'

    printf 'libdir: '
    "$PG_CONFIG" --libdir 2>/dev/null || printf 'REQUIRES VALIDATION\n'

    printf 'pkglibdir: '
    "$PG_CONFIG" --pkglibdir 2>/dev/null || printf 'REQUIRES VALIDATION\n'

    printf 'sharedir: '
    "$PG_CONFIG" --sharedir 2>/dev/null || printf 'REQUIRES VALIDATION\n'
else
    printf 'INFO: source-install pg_config not detected at %s.\n' "$PG_CONFIG"
fi

section "PACKAGE / SOURCE COEXISTENCE"

shell_postgres=""
source_postgres="${PREFIX}/bin/postgres"

if command_exists postgres; then
    shell_postgres="$(command -v postgres)"
fi

printf 'PATH-resolved postgres: %s\n' "${shell_postgres:-NOT FOUND}"
printf 'Source-prefix postgres: %s\n' "$source_postgres"

if [[ -n "$shell_postgres" && -x "$source_postgres" && "$shell_postgres" != "$source_postgres" ]]; then
    printf '\nREQUIRES VALIDATION: PATH and source prefix resolve different postgres binaries.\n'
    printf 'This can be legitimate, but operational ownership must be understood.\n'
fi

section "POSTGRESQL PROCESS DISCOVERY"

postgres_processes="$(ps -ef 2>/dev/null | grep '[p]ostgres' || true)"

if [[ -n "$postgres_processes" ]]; then
    printf '%s\n' "$postgres_processes"
    printf '\nREQUIRES VALIDATION: PostgreSQL process(es) detected.\n'
    printf '%s\n' \
        'Determine version, PGDATA, port, owner, service, and binary path' \
        'before assuming the process belongs to this source installation.'
else
    printf 'INFO: no PostgreSQL server process detected.\n'
fi

section "BUILD-METHOD INTERPRETATION"

cat <<'EOF'
Interpret prerequisites according to the selected build method.

AUTOCONF_MAKE:
  Validate the documented compiler, GNU Make, Flex, Bison,
  Perl, archive tooling, and selected feature dependencies.

MESON_NINJA:
  Validate the documented compiler, Meson, Ninja, Flex,
  Bison, Perl, archive tooling, and selected feature dependencies.

A tool that is not required by the selected build path can be
classified NOT APPLICABLE rather than BLOCKER.
EOF

section "STOP CONDITIONS"

cat <<'EOF'
Stop or classify REQUIRES VALIDATION/BLOCKER if:

  - PostgreSQL source provenance cannot be established
  - integrity verification failed
  - required build prerequisites are missing
  - the installation prefix contains unknown software
  - the resulting postgres binary is not PostgreSQL 18
  - package/source coexistence is not understood
  - unexpected PostgreSQL processes or clusters exist
  - required build capabilities are absent
  - regression-test failures remain unexplained
EOF

section "SAFETY RESULT"

cat <<'EOF'
[TUTORIAL-ACCEPTANCE — SAFE-READ]

Inspection completed.

This script did NOT:
  - invoke sudo
  - modify repositories
  - install/remove/upgrade packages
  - download or extract PostgreSQL source
  - configure or compile PostgreSQL
  - run regression tests
  - install PostgreSQL
  - remove build artifacts
  - modify ownership or permissions
  - modify PATH or create symlinks
  - run initdb
  - create or delete PostgreSQL clusters
  - start/stop/restart PostgreSQL
  - modify systemd
  - modify PostgreSQL configuration
  - modify pg_hba.conf
  - modify firewall/network configuration
EOF
