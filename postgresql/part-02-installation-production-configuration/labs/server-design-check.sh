#!/usr/bin/env bash

# [TUTORIAL-ACCEPTANCE — SAFE-READ]
# Part 2.1 — PostgreSQL Installation Architecture and Planning
#
# Purpose:
#   Collect read-only Linux host facts needed for the PostgreSQL
#   Server Build Specification.
#
# This script does NOT install PostgreSQL, initialize a cluster,
# change filesystems, modify networking/firewalls, change permissions,
# or control services.

set -u

section() {
    printf '\n============================================================\n'
    printf '%s\n' "$1"
    printf '============================================================\n'
}

run_if_available() {
    local command_name="$1"
    shift

    if command -v "$command_name" >/dev/null 2>&1; then
        "$@"
    else
        printf 'SKIP: %s is not available on this host.\n' "$command_name"
    fi
}

section "HOST IDENTITY"
run_if_available hostname hostname
run_if_available hostnamectl hostnamectl

section "OPERATING SYSTEM"
if [[ -r /etc/os-release ]]; then
    cat /etc/os-release
else
    printf 'SKIP: /etc/os-release is not readable.\n'
fi

section "KERNEL AND ARCHITECTURE"
uname -m
uname -r

section "CPU"
run_if_available nproc nproc
run_if_available lscpu lscpu

section "MEMORY"
run_if_available free free -h

if [[ -r /proc/meminfo ]]; then
    grep -E 'MemTotal|MemAvailable|SwapTotal|SwapFree' /proc/meminfo || true
fi

section "STORAGE"
run_if_available lsblk lsblk
run_if_available df df -hT
run_if_available findmnt findmnt

section "NETWORK IDENTITY"
if command -v hostname >/dev/null 2>&1; then
    hostname -f 2>/dev/null || printf 'INFO: FQDN could not be resolved.\n'
fi

run_if_available ip ip addr
run_if_available ip ip route

section "TIME"
run_if_available timedatectl timedatectl

section "ACCEPTANCE RESULT"
cat <<'EOF'
SAFE-READ host inventory completed.

Use these observations to populate:
  postgresql-server-build-spec.txt

No PostgreSQL installation, initdb, service control, firewall change,
filesystem creation, mount operation, ownership change, or PostgreSQL
configuration change was performed by this acceptance script.
EOF
