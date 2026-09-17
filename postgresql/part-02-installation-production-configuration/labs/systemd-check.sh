#!/usr/bin/env bash
# Part 2.7 — PostgreSQL Service Management with systemd
# [TUTORIAL-ACCEPTANCE — SAFE-READ]
set -u

if ! command -v systemctl >/dev/null 2>&1; then
  echo "BLOCKER: systemctl is unavailable." >&2
  exit 2
fi

if [ -z "${PG_SERVICE:-}" ]; then
  echo "BLOCKER: set PG_SERVICE to the intended PostgreSQL systemd unit." >&2
  exit 2
fi

printf 'PG_SERVICE=%s\n' "$PG_SERVICE"
systemctl show "$PG_SERVICE" -p Id -p LoadState -p ActiveState -p SubState -p UnitFileState -p MainPID -p User -p Group -p ExecStart -p ExecReload -p Restart -p FragmentPath --no-pager
systemctl show "$PG_SERVICE" -p TimeoutStartUSec -p TimeoutStopUSec -p LimitNOFILE -p LimitNPROC -p LimitMEMLOCK -p TasksMax --no-pager
systemctl cat "$PG_SERVICE" --no-pager

echo "SAFE-READ complete. No service lifecycle or systemd state was changed."
