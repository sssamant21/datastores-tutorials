#!/usr/bin/env bash
set -euo pipefail

for cmd in docker kind kubectl curl openssl jq; do
  command -v "$cmd" >/dev/null || { echo "FAIL: missing $cmd"; exit 1; }
done

value="$(sysctl -n vm.max_map_count)"
if [ "$value" -lt 1048576 ]; then
  echo "FAIL: vm.max_map_count=$value; require >=1048576"
  exit 1
fi
printf 'PASS: vm.max_map_count=%s\n' "$value"
