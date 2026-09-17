#!/usr/bin/env bash
# Part 2.13
# [TUTORIAL-ACCEPTANCE — SAFE-READ] [HOST-READ]
set -u

section() { printf '\n=== %s ===\n' "$1"; }

section "OS identity"
uname -a 2>/dev/null || true
[[ -r /etc/os-release ]] && cat /etc/os-release

section "CPU"
command -v nproc >/dev/null && nproc || true

section "Memory"
command -v free >/dev/null && free -h || true

section "Filesystem capacity"
command -v df >/dev/null && df -h || true

section "Filesystem inodes"
command -v df >/dev/null && df -i || true

section "Mounts"
if command -v findmnt >/dev/null; then
  findmnt -o TARGET,SOURCE,FSTYPE,OPTIONS 2>/dev/null || true
else
  mount 2>/dev/null || true
fi

section "Interactive-shell limits (not proof of service limits)"
printf 'open files: '
ulimit -n 2>/dev/null || true
printf 'max user processes: '
ulimit -u 2>/dev/null || true

section "Kernel values (read-only, when exposed)"
for k in vm.overcommit_memory vm.nr_hugepages fs.file-max net.core.somaxconn; do
  if command -v sysctl >/dev/null; then
    sysctl "$k" 2>/dev/null || true
  fi
done

section "Cgroup hints"
for f in /sys/fs/cgroup/memory.max /sys/fs/cgroup/cpu.max /sys/fs/cgroup/pids.max; do
  [[ -r "$f" ]] && printf '%s: %s\n' "$f" "$(cat "$f")"
done

echo
echo "SAFE-READ/HOST-READ complete. No host state was intentionally changed."
