#!/usr/bin/env bash

# [TUTORIAL-ACCEPTANCE — SAFE-READ]
# Part 2.7 — PostgreSQL Service Management with systemd
# Inspects an explicitly selected PostgreSQL systemd service without mutation.

set -u

PASS=0; WARN=0; BLOCK=0; REVIEW=0; NA=0
section(){ printf '\n=== %s ===\n' "$1"; }
pass(){ printf 'PASS: %s\n' "$1"; PASS=$((PASS+1)); }
warning(){ printf 'WARNING: %s\n' "$1"; WARN=$((WARN+1)); }
blocker(){ printf 'BLOCKER: %s\n' "$1"; BLOCK=$((BLOCK+1)); }
review(){ printf 'REQUIRES VALIDATION: %s\n' "$1"; REVIEW=$((REVIEW+1)); }
not_applicable(){ printf 'NOT APPLICABLE: %s\n' "$1"; NA=$((NA+1)); }

section "Identity"
date; hostname; id; uname -a

section "systemd Availability"
if ! command -v systemctl >/dev/null 2>&1; then
  blocker "systemctl is unavailable on this Part 2.7 target."
  printf '\nSafety result: BLOCKER\n'; exit 2
fi
pass "systemctl is available."

section "Explicit Service Selection"
if [ -z "${PG_SERVICE:-}" ]; then
  blocker "PG_SERVICE is not explicitly set."
  printf '\nSet PG_SERVICE to the intended PostgreSQL systemd unit.\nSafety result: BLOCKER\n'
  exit 2
fi
printf 'PG_SERVICE=%s\n' "$PG_SERVICE"

section "PostgreSQL Unit Discovery"
systemctl list-units --type=service --all --no-legend --no-pager 2>/dev/null | grep -i postgres || true
systemctl list-unit-files --type=service --no-legend --no-pager 2>/dev/null | grep -i postgres || true
printf '%s\n' "Discovery is informational only; no service is selected automatically."

section "Unit Validation"
LOAD_STATE="$(systemctl show "$PG_SERVICE" -p LoadState --value 2>/dev/null || true)"
printf 'LoadState=%s\n' "${LOAD_STATE:-unknown}"
case "$LOAD_STATE" in
  loaded) pass "Specified systemd unit is loaded." ;;
  not-found|"") blocker "Specified systemd unit was not found." ;;
  *) review "Unexpected LoadState: $LOAD_STATE" ;;
esac
[ "$BLOCK" -eq 0 ] || { printf '\nSafety result: BLOCKER\n'; exit 2; }

section "Runtime State"
ACTIVE_STATE="$(systemctl show "$PG_SERVICE" -p ActiveState --value 2>/dev/null || true)"
SUB_STATE="$(systemctl show "$PG_SERVICE" -p SubState --value 2>/dev/null || true)"
UNIT_FILE_STATE="$(systemctl show "$PG_SERVICE" -p UnitFileState --value 2>/dev/null || true)"
printf 'ActiveState=%s\nSubState=%s\nUnitFileState=%s\n' "${ACTIVE_STATE:-unknown}" "${SUB_STATE:-unknown}" "${UNIT_FILE_STATE:-unknown}"
case "$ACTIVE_STATE" in
  active) pass "Service is active." ;;
  failed) blocker "Service is in failed state." ;;
  inactive) review "Service is inactive; validate this against intended state." ;;
  activating|deactivating) review "Service is transitioning state: $ACTIVE_STATE" ;;
  *) review "Unexpected or unknown service state: ${ACTIVE_STATE:-unknown}" ;;
esac
case "$UNIT_FILE_STATE" in masked|masked-runtime) review "Service is masked; validate whether intentional." ;; esac

section "Effective Unit"
systemctl cat "$PG_SERVICE" --no-pager 2>/dev/null || review "Unable to display effective unit definition."

section "Structured Properties"
systemctl show "$PG_SERVICE" \
  -p Id -p LoadState -p ActiveState -p SubState -p UnitFileState \
  -p MainPID -p User -p Group -p ExecStart -p ExecReload \
  -p Restart -p FragmentPath --no-pager 2>/dev/null ||
  review "Unable to retrieve all structured properties."

section "Service Identity"
SERVICE_USER="$(systemctl show "$PG_SERVICE" -p User --value 2>/dev/null || true)"
SERVICE_GROUP="$(systemctl show "$PG_SERVICE" -p Group --value 2>/dev/null || true)"
printf 'Configured User=%s\nConfigured Group=%s\n' "${SERVICE_USER:-<not-explicit>}" "${SERVICE_GROUP:-<not-explicit>}"
if [ "$SERVICE_USER" = root ]; then
  blocker "PostgreSQL service is explicitly configured with User=root."
elif [ -n "$SERVICE_USER" ]; then
  pass "An explicit non-root service user is configured."
else
  review "User= is not explicit; correlate with running process and architecture."
fi

section "ExecStart and ExecReload"
EXEC_START="$(systemctl show "$PG_SERVICE" -p ExecStart --value 2>/dev/null || true)"
EXEC_RELOAD="$(systemctl show "$PG_SERVICE" -p ExecReload --value 2>/dev/null || true)"
printf 'ExecStart=%s\nExecReload=%s\n' "${EXEC_START:-<unavailable>}" "${EXEC_RELOAD:-<not-configured>}"
[ -n "$EXEC_START" ] && printf '%s\n' "ExecStart is evidence only; it is never evaluated or executed." || review "ExecStart could not be established."

section "Restart Policy, Timeouts, and Resource Limits"
systemctl show "$PG_SERVICE" \
  -p Restart -p TimeoutStartUSec -p TimeoutStopUSec \
  -p LimitNOFILE -p LimitNPROC -p LimitMEMLOCK -p TasksMax \
  --no-pager 2>/dev/null || review "Unable to retrieve all service resource properties."

section "Main Process"
MAIN_PID="$(systemctl show "$PG_SERVICE" -p MainPID --value 2>/dev/null || true)"
printf 'MainPID=%s\n' "${MAIN_PID:-unknown}"
case "$MAIN_PID" in
  ''|0)
    [ "$ACTIVE_STATE" = active ] && review "Service is active but no positive MainPID was reported." ||
      not_applicable "No MainPID for observed non-active state."
    ;;
  *[!0-9]*) review "MainPID is not numeric." ;;
  *) ps -fp "$MAIN_PID" && pass "MainPID exists and was inspected." || review "MainPID could not be inspected." ;;
esac

section "PostgreSQL Process Inventory"
ps -ef | grep '[p]ostgres' || true
printf '%s\n' "Multiple postgres processes are normal and do not by themselves prove multiple clusters."

section "Optional PGDATA Correlation"
if [ -z "${PGDATA:-}" ]; then
  not_applicable "PGDATA was not explicitly supplied."
else
  printf 'PGDATA=%s\n' "$PGDATA"
  if [ ! -d "$PGDATA" ]; then
    review "Explicit PGDATA does not exist or is not accessible."
  else
    pass "Explicit PGDATA exists."
    if [ -f "$PGDATA/PG_VERSION" ]; then
      printf 'PG_VERSION='; cat "$PGDATA/PG_VERSION"; printf '\n'
      grep -qx '18' "$PGDATA/PG_VERSION" 2>/dev/null &&
        pass "PGDATA identifies PostgreSQL 18." ||
        review "PGDATA does not identify PostgreSQL 18."
    else
      review "PG_VERSION is unavailable beneath explicit PGDATA."
    fi

    if [ -f "$PGDATA/postmaster.pid" ]; then
      POSTMASTER_PID="$(head -n 1 "$PGDATA/postmaster.pid" 2>/dev/null || true)"
      printf 'postmaster.pid PID=%s\n' "${POSTMASTER_PID:-unknown}"
      case "$POSTMASTER_PID" in
        ''|*[!0-9]*) review "postmaster.pid first line is not numeric." ;;
        *)
          if [ "$MAIN_PID" = "$POSTMASTER_PID" ]; then
            pass "systemd MainPID matches postmaster.pid."
          elif [ -n "$MAIN_PID" ] && [ "$MAIN_PID" != 0 ]; then
            review "systemd MainPID differs from postmaster.pid."
          else
            review "postmaster.pid exists but systemd has no positive MainPID."
          fi ;;
      esac
    else
      [ "$ACTIVE_STATE" = active ] &&
        review "Service is active but postmaster.pid was not found under explicit PGDATA." ||
        not_applicable "postmaster.pid absent for observed non-active state."
    fi
  fi
fi

section "Dependencies"
systemctl list-dependencies "$PG_SERVICE" --no-pager 2>/dev/null || review "Unable to inspect dependencies."

section "Bounded Journal Evidence"
if command -v journalctl >/dev/null 2>&1; then
  journalctl -u "$PG_SERVICE" -b -n 100 --no-pager ||
    review "Journal evidence is unavailable to the current account."
else
  review "journalctl is unavailable."
fi

section "Optional PostgreSQL Readiness"
printf '%s\n' \
  "Readiness is not executed automatically." \
  "If PostgreSQL is already running and an approved host/socket and port are known," \
  "run pg_isready separately without embedding credentials."
command -v pg_isready >/dev/null 2>&1 &&
  pass "pg_isready is installed for an explicitly scoped optional check." ||
  not_applicable "pg_isready is not installed; the script will not install it."

section "Safety Contract"
printf '%s\n' \
  "No privilege escalation performed." \
  "No service started, stopped, restarted, or reloaded." \
  "No service enabled, disabled, masked, or unmasked." \
  "No systemd manager state changed." \
  "No process signals sent." \
  "No pg_ctl lifecycle operation executed." \
  "No PostgreSQL server launched." \
  "No unit, drop-in, environment file, PostgreSQL configuration, or postmaster.pid modified." \
  "No packages installed." \
  "No credentials collected." \
  "No automatic remediation performed."

section "Summary"
printf 'PASS=%d\nWARNING=%d\nBLOCKER=%d\nNOT_APPLICABLE=%d\nREQUIRES_VALIDATION=%d\n' "$PASS" "$WARN" "$BLOCK" "$NA" "$REVIEW"
if [ "$BLOCK" -gt 0 ]; then printf 'Safety result: BLOCKER\n'; exit 2; fi
if [ "$REVIEW" -gt 0 ]; then printf 'Safety result: REQUIRES VALIDATION\n'; exit 1; fi
if [ "$WARN" -gt 0 ]; then printf 'Safety result: WARNING\n'; exit 0; fi
printf 'Safety result: PASS\n'
exit 0
