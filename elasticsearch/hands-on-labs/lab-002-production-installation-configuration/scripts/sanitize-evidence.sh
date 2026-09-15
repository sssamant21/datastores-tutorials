#!/usr/bin/env bash
set -euo pipefail
DIR="${1:-evidence}"
[ -d "$DIR" ] || { echo "FAIL: evidence directory missing"; exit 1; }
if grep -RIlE 'BEGIN (RSA )?PRIVATE KEY|ELASTIC_PASSWORD=|Authorization:[[:space:]]*Basic|Basic[[:space:]][A-Za-z0-9+/=]{12,}' "$DIR" >/dev/null; then
  echo 'FAIL: potential credential/private-key material found in evidence'
  exit 1
fi
echo 'PASS: evidence sanitization'
