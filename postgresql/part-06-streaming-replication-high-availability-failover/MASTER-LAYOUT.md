# Part 6 — Streaming Replication, High Availability & Failover — Master Layout

**Target:** PostgreSQL 18  
**Status:** LOCKED — Master Layout v1.0  
**Audience:** PostgreSQL Administrators, DBREs, SREs, Platform Engineers

## Mission

Part 6 builds a production-oriented PostgreSQL high-availability discipline: design a primary/standby topology, establish and validate physical streaming replication, measure lag correctly, control WAL-retention risk, execute fenced role transitions, reintegrate former primaries safely, and prove service continuity without treating replication as backup or promotion as complete failover.

## Prerequisite and Boundary

Parts 1–5 are prerequisites. Part 6 applies rather than repeats:

- Part 2 host installation, systemd, capacity, and production configuration
- Part 4 roles, `pg_hba.conf`, least privilege, and TLS
- Part 5 physical backup, WAL, slots, RPO/RTO, recovery readiness, and HA-vs-backup-vs-DR boundaries

Out of scope: logical replication/CDC, Patroni implementation, Kubernetes operators, cloud-managed HA implementation, backup redesign, and PITR procedures.

## Canonical Workflow

Every section follows:

1. Draft + Hands-On Lab
2. Technical + PostgreSQL 18 Vendor Source Review
3. Production + Safety + Copyright Review
4. Revised Final / Canonical Edition + acceptance artifact
5. Commit to `main`, update Part 6 status, fetch back, and verify

Evidence artifacts default to `[TUTORIAL-ACCEPTANCE — SAFE-READ]`. Promotion, fencing, switchover, failover, rewind, and failback exercises are `[DISRUPTIVE-LAB]` and must use isolated disposable targets.

## 15-Section Curriculum

| Section | Tutorial | Canonical Lab / Acceptance Artifact |
|---|---|---|
| 6.1 | Streaming Replication and HA Architecture | `labs/ha-architecture-assessment.md` |
| 6.2 | Replication Prerequisites and Change Planning | `labs/replication-prerequisites-check.sql` |
| 6.3 | Replication Identity, Authentication, and TLS | `labs/replication-access-check.sql` |
| 6.4 | Build a Physical Standby | `labs/build-standby.sh` |
| 6.5 | Verify Streaming and WAL Replay | `labs/streaming-replay-check.sql` |
| 6.6 | Measure Replication Lag Correctly | `labs/replication-lag-sampler.sql` |
| 6.7 | Asynchronous and Synchronous Replication Policy | `labs/sync-policy-experiment.sql` |
| 6.8 | Replication Slots, WAL Retention, and Standby Safety | `labs/slot-retention-risk-check.sql` |
| 6.9 | Read-Only Standbys and Conflict Management | `labs/hot-standby-conflict-lab.sql` |
| 6.10 | Cascading Replication and Topology Trade-offs | `labs/cascade-topology-check.sql` |
| 6.11 | Monitoring, Alerting, and Capacity Signals | `labs/ha-observability-check.sql` |
| 6.12 | Planned Switchover | `labs/planned-switchover-runbook.md` |
| 6.13 | Unplanned Failover and Split-Brain Prevention | `labs/unplanned-failover-runbook.md` |
| 6.14 | Rejoin, Rewind, and Failback | `labs/rejoin-failback-checklist.md` |
| 6.15 | Integrated Project — Production HA Readiness and Acceptance | `labs/ha-acceptance.sql`; `labs/ha-acceptance-checklist.md` |

## Section Intent

### 6.1 — Streaming Replication and HA Architecture
Establish physical replication flow, primary/standby roles, failure domains, asynchronous vs synchronous behavior, service endpoints, and the boundary between HA, backup, and DR.

### 6.2 — Replication Prerequisites and Change Planning
Validate version compatibility, capacity, network and time dependencies, WAL and sender settings, connection budget, change gates, rollback, and evidence requirements.

### 6.3 — Replication Identity, Authentication, and TLS
Apply least privilege to replication identities, restrict `pg_hba.conf`, verify TLS, protect connection material, and define credential rotation without exposing secrets.

### 6.4 — Build a Physical Standby
Seed a disposable standby from an approved consistent physical backup, configure standby startup, preserve ownership and permissions, and validate the initial recovery-to-streaming transition.

### 6.5 — Verify Streaming and WAL Replay
Prove server roles, sender/receiver health, LSN movement, WAL receive/flush/replay, timeline alignment, and controlled-write visibility.

### 6.6 — Measure Replication Lag Correctly
Distinguish byte and time lag, transport and replay backlog, idle-system timestamp behavior, observation windows, and workload-aligned thresholds.

### 6.7 — Asynchronous and Synchronous Replication Policy
Evaluate durability, commit latency, availability, priority/quorum selection, degraded-mode authority, rollback triggers, and business RPO implications.

### 6.8 — Replication Slots, WAL Retention, and Standby Safety
Extend Part 5.10 into HA operations: physical-slot lifecycle, bounded retention, inactive consumers, invalidation, disk headroom, alerting, and controlled remediation.

### 6.9 — Read-Only Standbys and Conflict Management
Operate hot-standby reads, analyze replay conflicts, evaluate feedback trade-offs, manage cancellations, and define stale-read and workload-isolation contracts.

### 6.10 — Cascading Replication and Topology Trade-offs
Compare fan-out and cascading designs, upstream dependencies, bandwidth, lag amplification, downstream behavior during promotion, and recovery complexity.

### 6.11 — Monitoring, Alerting, and Capacity Signals
Build evidence from sender/receiver state, LSN progress, lag, slot/WAL risk, restart age, disk headroom, and topology expectations; treat absent or stale evidence as UNKNOWN.

### 6.12 — Planned Switchover
Define authority, write drain, fencing, final replay, promotion, endpoint change, application validation, observation, abort criteria, and rollback boundary.

### 6.13 — Unplanned Failover and Split-Brain Prevention
Declare failure, establish promotion authority, fence the former primary, estimate potential data loss, promote, route clients, validate service, and preserve incident evidence.

### 6.14 — Rejoin, Rewind, and Failback
Assess divergence and timelines, validate `pg_rewind` prerequisites, choose rewind vs rebuild, prove one writable authority, reattach safely, and perform controlled failback.

### 6.15 — Integrated Project
Build a primary/standby service, establish lag and durability policy, execute controlled switchover and failover exercises, fence correctly, rejoin the former primary, validate application behavior, and produce PASS/FAIL/UNKNOWN acceptance evidence.

## PostgreSQL 18 Technical Baseline

Validate behavior against PostgreSQL 18 documentation, including as applicable:

- physical streaming replication and standby configuration
- WAL sender/receiver processes and statistics
- `pg_stat_replication`, `pg_stat_wal_receiver`, and replication slots
- receive, write, flush, and replay LSNs
- asynchronous and synchronous replication
- hot standby and recovery conflicts
- cascading replication
- promotion and timeline behavior
- `pg_rewind` prerequisites and limitations
- WAL-retention and disk-capacity controls
- authentication, TLS, and secret-handling boundaries
- provider/orchestrator differences

Version-specific behavior must not be silently generalized to older releases.

## Production Safety Rules

1. Verify target identity, cluster, role, timeline, and expected topology before every action.
2. Run disruptive exercises only on isolated disposable targets unless an approved production change explicitly authorizes them.
3. Fence the old primary before accepting writes on a promoted standby.
4. Promotion alone is not successful failover.
5. Preserve Part 5 backup and recovery readiness; replication is not backup.
6. Never expose passwords, connection strings, private keys, tokens, or unrestricted network details.
7. Define stop conditions, blast radius, rollback/fallback, ownership, and observation window.
8. Treat missing, stale, inaccessible, or contradictory evidence as UNKNOWN.
9. Do not infer RPO from a green process state or RTO from a successful SQL connection.
10. Distinguish sent, written, flushed, and replayed WAL positions.
11. Bound slot/WAL retention and monitor disk headroom.
12. Validate application reads and writes after endpoint or role changes.
13. Rejoin only after divergence assessment; prove a single writable authority.
14. Document self-managed vs managed-service behavior before applying procedures.
15. Prefer evidence and explicit decision gates over automatic remediation.

## Acceptance Philosophy

The final acceptance must answer:

```text
Is there exactly one writable authority?
Is the former primary fenced?
Is WAL being received, flushed, and replayed?
Is measured lag within the declared operating objective?
Can the service tolerate the tested failure?
What data loss and interruption were measured?
Did client routing and application validation pass?
Can the old primary be safely rewound or must it be rebuilt?
Are WAL retention and disk headroom controlled?
Does the independent Part 5 recovery path remain valid?
Who owns unresolved risks?
```

Final principle:

```text
streaming        != zero data loss
promotion        != complete failover
replication      != backup
process healthy  != application healthy
missing evidence = UNKNOWN
one writer       = mandatory
```
