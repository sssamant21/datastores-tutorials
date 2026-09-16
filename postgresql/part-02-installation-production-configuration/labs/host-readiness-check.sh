#!/usr/bin/env bash

# [TUTORIAL-ACCEPTANCE — SAFE-READ]
# Part 2.2 — Linux Host Preparation and Prerequisites
# Collect read-only Linux host evidence before PostgreSQL installation.
# No sudo and no host/PostgreSQL mutation.

set -u

section() {
    printf '\n============================================================\n'
    printf '%s\n' "$1"
    printf '============================================================\n'
}

command_exists() { command -v "$1" >/dev/null 2>&1; }

run_optional() {
    local cmd="$1"
    shift
    if command_exists "$cmd"; then
        "$@" || printf 'REQUIRES VALIDATION: %s could not be fully inspected.\n' "$cmd"
    else
        printf 'SKIP / NOT APPLICABLE: %s is not available.\n' "$cmd"
    fi
}

section "HOST IDENTITY"
run_optional hostname hostname
if command_exists hostname; then
    hostname -f 2>/dev/null || printf 'REQUIRES VALIDATION: FQDN could not be resolved.\n'
fi
run_optional hostnamectl hostnamectl

section "OPERATING SYSTEM"
if [[ -r /etc/os-release ]]; then cat /etc/os-release; else printf 'REQUIRES VALIDATION: /etc/os-release is not readable.\n'; fi

section "KERNEL AND ARCHITECTURE"
uname -r
uname -m

section "CPU"
run_optional nproc nproc
run_optional lscpu lscpu
run_optional numactl numactl --hardware

section "MEMORY"
run_optional free free -h
if [[ -r /proc/meminfo ]]; then grep -E 'MemTotal|MemAvailable|SwapTotal|SwapFree' /proc/meminfo || true; fi

section "SWAP"
run_optional swapon swapon --show

section "STORAGE DEVICES"
run_optional lsblk lsblk
run_optional lsblk lsblk -f

section "FILESYSTEM CAPACITY"
run_optional df df -hT

section "INODE CAPACITY"
run_optional df df -i

section "MOUNTS"
run_optional findmnt findmnt
if [[ -r /etc/fstab ]]; then cat /etc/fstab; else printf 'SKIP: /etc/fstab is not readable.\n'; fi

section "PLANNED POSTGRESQL STORAGE"
if [[ -e /pgdata ]]; then
    ls -ld /pgdata 2>/dev/null || printf 'REQUIRES VALIDATION: /pgdata metadata could not be inspected.\n'
    df -hT /pgdata 2>/dev/null || printf 'REQUIRES VALIDATION: /pgdata filesystem could not be inspected.\n'
    if command_exists findmnt; then
        findmnt /pgdata 2>/dev/null || printf 'INFO: /pgdata is not a distinct mount point or mount information is unavailable.\n'
    fi
else
    printf 'REQUIRES VALIDATION: planned /pgdata path is not prepared yet.\n'
fi

section "NETWORK"
run_optional ip ip addr
run_optional ip ip route

section "DNS / NAME RESOLUTION"
if command_exists hostname; then
    fqdn="$(hostname -f 2>/dev/null || true)"
    if [[ -n "$fqdn" ]]; then
        printf 'FQDN: %s\n' "$fqdn"
        if command_exists getent; then getent hosts "$fqdn" || printf 'REQUIRES VALIDATION: FQDN did not resolve through getent.\n'; else printf 'SKIP: getent is not available.\n'; fi
    else
        printf 'REQUIRES VALIDATION: FQDN is unavailable.\n'
    fi
fi

section "TIME"
run_optional timedatectl timedatectl

section "CURRENT OPERATOR"
run_optional whoami whoami
run_optional id id

section "POSTGRESQL OS ACCOUNT"
if command_exists getent; then
    if getent passwd postgres >/dev/null 2>&1; then
        getent passwd postgres
        printf 'PASS: postgres OS account exists.\n'
    else
        printf 'INFO: postgres OS account is not yet present; package/deployment workflow may create it.\n'
    fi
else
    printf 'REQUIRES VALIDATION: getent is unavailable.\n'
fi

section "SHELL RESOURCE LIMITS"
printf 'NOTE: These are current shell-context limits, not proof of future PostgreSQL systemd service limits.\n'
ulimit -a || true
printf '\nOpen-file limit:\n'; ulimit -n || true
printf '\nProcess/user limit:\n'; ulimit -u || true

section "SERVICE MANAGEMENT"
if [[ -r /proc/1/comm ]]; then printf 'PID 1: '; cat /proc/1/comm; fi
run_optional systemctl systemctl --version

section "SELINUX"
run_optional getenforce getenforce
run_optional sestatus sestatus

section "APPARMOR"
run_optional aa-status aa-status

section "FIREWALL TOOLING"
for fw in firewall-cmd nft ufw; do
    if command_exists "$fw"; then printf 'DETECTED: %s\n' "$fw"; else printf 'NOT DETECTED: %s\n' "$fw"; fi
done
printf '%s\n' 'NOTE: Complete firewall inspection may require privileges.' 'No privilege escalation or firewall mutation is performed.'

section "PACKAGE MANAGEMENT"
for pkg in dnf yum apt; do
    if command_exists "$pkg"; then printf 'DETECTED: %s\n' "$pkg"; else printf 'NOT DETECTED: %s\n' "$pkg"; fi
done

section "READINESS CLASSIFICATION"
cat <<'EOF'
Review the evidence above and classify each applicable requirement as:
  PASS
  WARNING
  BLOCKER
  NOT APPLICABLE
  REQUIRES VALIDATION

A missing optional utility is not automatically a BLOCKER.
An unavailable privileged inspection is not proof that a control is absent.
An unprepared /pgdata path is not automatically a host-readiness failure.
The absence of the postgres account before package installation is not automatically a failure.

Document the assessment in:
  postgresql-host-readiness.txt
EOF

section "SAFETY RESULT"
cat <<'EOF'
[TUTORIAL-ACCEPTANCE — SAFE-READ]

Completed Linux host evidence collection.
This script did NOT invoke sudo; install/remove packages; create users/groups;
create/modify filesystems; change mounts, ownership, permissions, swap, kernel
parameters, SELinux/AppArmor, firewall/network policy, or services; install
PostgreSQL; run initdb; or modify PostgreSQL configuration.
EOF
