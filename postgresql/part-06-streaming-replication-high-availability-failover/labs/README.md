# Part 6 Labs — Safety and Artifact Contract

This directory contains the canonical hands-on and acceptance artifacts for Part 6 — Streaming Replication, High Availability & Failover.

## Safety Labels

| Label | Meaning |
|---|---|
| `SAFE-READ` | PostgreSQL-visible evidence only; may still impose cost |
| `LAB-WRITE` | State-changing action limited to an isolated lab |
| `DISRUPTIVE-LAB` | Role or availability change on disposable targets only |
| `PRODUCTION-CHANGE` | Requires an approved change, owner, recovery verification, rollback/fallback, and observation window |

## Mandatory Artifact Header

Every executable artifact must state:

- section and purpose
- PostgreSQL target version
- safety label
- required topology and privileges
- target identity and expected role
- mutations performed
- blast radius and stop conditions
- cleanup and rollback/fallback
- evidence produced
- what the artifact cannot prove

SQL evidence scripts use `\set ON_ERROR_STOP on`. They must redact secrets and sensitive connection material.

## Operational Invariants

- Exactly one writable authority is mandatory.
- Fence the old primary before routing writes to a promoted standby.
- Promotion is not complete failover.
- Replication is not backup; preserve the Part 5 recovery path.
- Missing, stale, inaccessible, or contradictory evidence is UNKNOWN.
- Do not report RPO/RTO achievement without measured workload and application evidence.
- Rejoin follows divergence assessment; use `pg_rewind` only when its prerequisites are proven.
- No disruptive artifact is production-safe by default.

Planned filenames and completion state are authoritative in `../STATUS.md`.
