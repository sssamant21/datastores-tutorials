# Part 6 — Streaming Replication, High Availability & Failover — Status

**Status:** PLANNED  
**Canonical progress:** **0/15 canonical + merged**  
**Target:** PostgreSQL 18  
**Authoritative layout:** `MASTER-LAYOUT.md` — LOCKED, Master Layout v1.0

Status values: `PLANNED` | `DRAFT` | `LAB VALIDATED` | `CANONICAL + MERGED` | `BLOCKED`

| Section | Title | Tutorial Status | Lab Artifact | Lab Status | Evidence / Commit | Notes |
|---|---|---|---|---|---|---|
| 6.1 | Streaming Replication and HA Architecture | PLANNED | `labs/ha-architecture-assessment.md` | PLANNED | — | — |
| 6.2 | Replication Prerequisites and Change Planning | PLANNED | `labs/replication-prerequisites-check.sql` | PLANNED | — | — |
| 6.3 | Replication Identity, Authentication, and TLS | PLANNED | `labs/replication-access-check.sql` | PLANNED | — | — |
| 6.4 | Build a Physical Standby | PLANNED | `labs/build-standby.sh` | PLANNED | — | LAB-WRITE |
| 6.5 | Verify Streaming and WAL Replay | PLANNED | `labs/streaming-replay-check.sql` | PLANNED | — | — |
| 6.6 | Measure Replication Lag Correctly | PLANNED | `labs/replication-lag-sampler.sql` | PLANNED | — | — |
| 6.7 | Asynchronous and Synchronous Replication Policy | PLANNED | `labs/sync-policy-experiment.sql` | PLANNED | — | LAB-WRITE |
| 6.8 | Replication Slots, WAL Retention, and Standby Safety | PLANNED | `labs/slot-retention-risk-check.sql` | PLANNED | — | Links Part 5.10 |
| 6.9 | Read-Only Standbys and Conflict Management | PLANNED | `labs/hot-standby-conflict-lab.sql` | PLANNED | — | LAB-WRITE |
| 6.10 | Cascading Replication and Topology Trade-offs | PLANNED | `labs/cascade-topology-check.sql` | PLANNED | — | — |
| 6.11 | Monitoring, Alerting, and Capacity Signals | PLANNED | `labs/ha-observability-check.sql` | PLANNED | — | SAFE-READ |
| 6.12 | Planned Switchover | PLANNED | `labs/planned-switchover-runbook.md` | PLANNED | — | DISRUPTIVE-LAB |
| 6.13 | Unplanned Failover and Split-Brain Prevention | PLANNED | `labs/unplanned-failover-runbook.md` | PLANNED | — | DISRUPTIVE-LAB |
| 6.14 | Rejoin, Rewind, and Failback | PLANNED | `labs/rejoin-failback-checklist.md` | PLANNED | — | DISRUPTIVE-LAB |
| 6.15 | Integrated Project — Production HA Readiness and Acceptance | PLANNED | `labs/ha-acceptance.sql`; `labs/ha-acceptance-checklist.md` | PLANNED | — | Final gate |

## Completion Rule

A section counts toward `N/15` only when:

1. the tutorial is Revised Final / Canonical Edition;
2. its lab or acceptance artifact is validated;
3. expected and negative paths are documented;
4. safety boundaries and cleanup are explicit;
5. sensitive evidence is redacted; and
6. the exact commit is recorded above.

Part 6 becomes `15/15 canonical + merged` only after 6.15 records topology, test window, fencing, role transitions, application validation, measured RPO/RTO outcome, rejoin/failback result, unresolved risks, owners, and PASS/FAIL/UNKNOWN acceptance.

## Next Workflow Stage

Start Part 6.1 — Streaming Replication and HA Architecture — Draft + Hands-On Lab.
