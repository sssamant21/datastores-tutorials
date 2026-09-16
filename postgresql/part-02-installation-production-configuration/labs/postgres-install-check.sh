#!/usr/bin/env bash

# [TUTORIAL-ACCEPTANCE — SAFE-READ]
# Part 2.3 — Package-Based PostgreSQL Installation
# Inspect PostgreSQL package/binary/runtime state after installation.
# No sudo and no host/PostgreSQL mutation.

set -u

section() {
    printf '\n============================================================\n'
    printf '%s\n' "$1"
    printf '============================================================\n'
}

command_exists() { command -v "$1" >/dev/null 2>&1; }

show_command() {
    local cmd="$1"
    if command_exists "$cmd"; then
        printf '%s: %s\n' "$cmd" "$(command -v "$cmd")"
    else
        printf '%s: NOT FOUND IN PATH\n' "$cmd"
    fi
}

show_version() {
    local cmd="$1"
    if command_exists "$cmd"; then
        "$cmd" --version 2>&1 || printf 'REQUIRES VALIDATION: unable to read %s version.\n' "$cmd"
    else
        printf 'SKIP: %s is not available in PATH.\n' "$cmd"
    fi
}

section "OPERATING SYSTEM"
if [[ -r /etc/os-release ]]; then cat /etc/os-release; else printf 'REQUIRES VALIDATION: /etc/os-release is not readable.\n'; fi

section "ARCHITECTURE"
uname -m

section "PACKAGE MANAGEMENT"
for cmd in dnf yum apt rpm dpkg; do
    if command_exists "$cmd"; then printf 'DETECTED: %s -> %s\n' "$cmd" "$(command -v "$cmd")"; else printf 'NOT DETECTED: %s\n' "$cmd"; fi
done

section "POSTGRESQL PACKAGE INVENTORY"
if command_exists rpm; then
    printf '\nRPM PostgreSQL packages:\n'
    rpm -qa 2>/dev/null | grep -i postgres || printf 'INFO: no PostgreSQL packages returned by RPM inventory.\n'
fi
if command_exists dpkg; then
    printf '\nDPKG PostgreSQL packages:\n'
    dpkg -l 2>/dev/null | grep -i postgres || printf 'INFO: no PostgreSQL packages returned by DPKG inventory.\n'
fi

section "POSTGRESQL COMMAND DISCOVERY"
for cmd in postgres psql initdb pg_config pg_ctl pg_dump pg_restore pg_isready; do show_command "$cmd"; done

section "POSTGRESQL VERSION DISCOVERY"
for cmd in postgres psql initdb pg_config pg_ctl pg_dump pg_restore pg_isready; do show_version "$cmd"; done

section "PG_CONFIG DETAILS"
if command_exists pg_config; then
    printf 'bindir: '; pg_config --bindir 2>/dev/null || printf 'REQUIRES VALIDATION\n'
    printf 'libdir: '; pg_config --libdir 2>/dev/null || printf 'REQUIRES VALIDATION\n'
    printf 'pkglibdir: '; pg_config --pkglibdir 2>/dev/null || printf 'REQUIRES VALIDATION\n'
else
    printf 'INFO: pg_config is not available; this is not automatically a blocker.\n'
fi

section "SYSTEMD DISCOVERY"
if command_exists systemctl; then
    printf '\nPostgreSQL-related unit files:\n'
    systemctl list-unit-files 2>/dev/null | grep -i postgres || printf 'INFO: no PostgreSQL-related unit files discovered or access unavailable.\n'
    printf '\nPostgreSQL-related loaded services:\n'
    systemctl list-units --type=service --all 2>/dev/null | grep -i postgres || printf 'INFO: no PostgreSQL-related loaded services discovered or access unavailable.\n'
else
    printf 'NOT APPLICABLE: systemctl is unavailable.\n'
fi

section "POSTGRESQL PROCESS DISCOVERY"
postgres_processes="$(ps -ef 2>/dev/null | grep '[p]ostgres' || true)"
if [[ -n "$postgres_processes" ]]; then
    printf '%s\n' "$postgres_processes"
    printf '\nREQUIRES VALIDATION: PostgreSQL process(es) detected.\n'
    printf '%s\n' 'Determine version, cluster, PGDATA, port, owner, service,' 'and packaging origin before continuing.'
else
    printf 'INFO: no PostgreSQL server process detected.\n'
fi

section "PACKAGING-SPECIFIC CLUSTER DISCOVERY"
if command_exists pg_lsclusters; then
    printf 'Detected pg_lsclusters utility:\n'
    pg_lsclusters 2>/dev/null || printf 'REQUIRES VALIDATION: pg_lsclusters could not complete.\n'
else
    printf 'NOT APPLICABLE / NOT DETECTED: pg_lsclusters is unavailable.\n'
fi

section "MULTIPLE-VERSION REVIEW"
cat <<'EOF'
Review package inventory and binary versions above.
If more than one PostgreSQL major version appears, classify it as REQUIRES VALIDATION until understood.
Do not automatically remove, relink, stop, or reconfigure any version.
EOF

section "ACCEPTANCE CLASSIFICATION"
cat <<'EOF'
Classify the installation as appropriate:
  PASS
  WARNING
  BLOCKER
  NOT APPLICABLE
  REQUIRES VALIDATION

Stop before controlled initdb if the PostgreSQL major version is wrong,
package provenance cannot be verified, an existing installation is not
understood, multiple versions have unknown purpose, an unexpected PostgreSQL
service/process/cluster exists, or installation errors remain unresolved.

Record evidence in:
  postgresql-package-installation.txt
EOF

section "SAFETY RESULT"
cat <<'EOF'
[TUTORIAL-ACCEPTANCE — SAFE-READ]
Inspection completed.
This script did NOT invoke sudo; modify repositories; install/remove/upgrade
packages; create users/groups; modify filesystems; run initdb; create/delete
PostgreSQL clusters; start/stop/restart/enable/disable services; modify
PostgreSQL configuration or pg_hba.conf; modify firewall/network configuration;
or modify PATH or symlinks.
EOF
