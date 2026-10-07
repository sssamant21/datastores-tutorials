# Redis Enterprise — Complete Production Engineering Track

**Status:** ACTIVE — 80-Chapter Rebuild  
**Target:** 80 production-grade canonical chapters  
**Audience:** Redis Administrators, SREs, DBREs, Platform Engineers, Developers, Data Engineers  
**Workflow:** Draft → Technical Validation → Production Review → Canonical  
**Chapter standard:** Concept → Architecture → Internals → Commands → Hands-On Lab → Expected Results → Failure Injection → Troubleshooting → Production Considerations → Runbook → Validation Checklist

> The original 36-chapter Redis Enterprise track is being rebuilt into this 80-chapter production curriculum. Useful material from the original chapters is retained and expanded rather than discarded.

## Part 1 — Foundations & Architecture

| # | Tutorial | Status |
|---|---|---|
| 01 | Redis Enterprise Fundamentals & Architecture | REBUILT — CANONICAL CONTENT READY |
| 02 | Connecting to Redis Enterprise — Clients, Endpoints, TLS & Connection Management | REBUILT — CANONICAL CONTENT READY |
| 03 | Redis Data Types, Key Design & Memory-Aware Data Modeling | PLANNED |
| 04 | Redis Commands, Command Semantics & Safe Operations | PLANNED |
| 05 | Redis Enterprise Databases, Endpoints & Configuration | PLANNED |
| 06 | Redis Enterprise Nodes, Shards, Proxies & Placement | PLANNED |
| 07 | Hash Slots, Key Distribution & Sharding Internals | PLANNED |
| 08 | Replication Architecture & Primary/Replica Behavior | PLANNED |
| 09 | Redis Enterprise Administration Interfaces — UI, rladmin & REST API | PLANNED |
| 10 | Architecture Inspection & Foundation Acceptance Lab | PLANNED |

## Part 2 — Caching & Application Engineering

| # | Tutorial | Status |
|---|---|---|
| 11 | TTL, Expiration & Cache Freshness Engineering | PLANNED |
| 12 | Cache-Aside Pattern | PLANNED |
| 13 | Cache Updates, Invalidation & Consistency | PLANNED |
| 14 | Write-Through, Write-Behind & Read-Through Patterns | PLANNED |
| 15 | Cache Stampede, Thundering Herd & Source Protection | PLANNED |
| 16 | Negative Caching & Missing-Data Protection | PLANNED |
| 17 | Connection Pooling, Pipelining & Batching | PLANNED |
| 18 | Sessions, Counters & Atomic Operations | PLANNED |
| 19 | Rate Limiting, Leaderboards & Application Patterns | PLANNED |
| 20 | Production Caching Architecture & Acceptance Lab | PLANNED |

## Part 3 — Memory & Performance Engineering

| # | Tutorial | Status |
|---|---|---|
| 21 | Redis Memory Architecture & Memory Accounting | PLANNED |
| 22 | Database Memory Limits & Replica Memory Overhead | PLANNED |
| 23 | Eviction Policies — LRU, LFU, TTL & Noeviction | PLANNED |
| 24 | Expiration Internals & Memory Reclamation | PLANNED |
| 25 | Memory Fragmentation, RSS & Allocator Behavior | PLANNED |
| 26 | Big Keys, Hot Keys & Skew Detection | PLANNED |
| 27 | CPU, Command Complexity & Slow Operations | PLANNED |
| 28 | Latency Engineering, SLOWLOG & Command Analysis | PLANNED |
| 29 | Shard Imbalance, Throughput & Capacity Planning | PLANNED |
| 30 | Redis Performance Troubleshooting & Benchmark Lab | PLANNED |

## Part 4 — Enterprise Administration & High Availability

| # | Tutorial | Status |
|---|---|---|
| 31 | Redis Enterprise Cluster Administration | PLANNED |
| 32 | Database Administration & Lifecycle Management | PLANNED |
| 33 | Shard Administration, Resharding & Rebalancing | PLANNED |
| 34 | High Availability & Automatic Failover | PLANNED |
| 35 | Rack/Zone Awareness & Failure-Domain Design | PLANNED |
| 36 | Replica HA & Redundancy Restoration | PLANNED |
| 37 | Persistence — AOF & Snapshot Engineering | PLANNED |
| 38 | Backup & Restore Administration | PLANNED |
| 39 | Upgrades, Patching & Maintenance Operations | PLANNED |
| 40 | Enterprise Administration & HA Acceptance Lab | PLANNED |

## Part 5 — Security & Access

| # | Tutorial | Status |
|---|---|---|
| 41 | Redis Enterprise Security Architecture | PLANNED |
| 42 | Users, Roles, ACLs & Least Privilege | PLANNED |
| 43 | TLS, Certificates & PKI Operations | PLANNED |
| 44 | Mutual TLS & Certificate-Based Authentication | PLANNED |
| 45 | Network Security, Firewalls & Connectivity Controls | PLANNED |
| 46 | Secrets Management & Credential Rotation | PLANNED |
| 47 | Security Auditing, Logging & Troubleshooting | PLANNED |
| 48 | Redis Enterprise Security Hardening & Acceptance Lab | PLANNED |

## Part 6 — Observability, Troubleshooting & SRE

| # | Tutorial | Status |
|---|---|---|
| 49 | Redis Enterprise Metrics & Observability Architecture | PLANNED |
| 50 | Prometheus, Grafana & Dashboard Engineering | PLANNED |
| 51 | Alerting, Thresholds, SLOs & Error Budgets | PLANNED |
| 52 | Memory Pressure, OOM & Eviction Troubleshooting | PLANNED |
| 53 | CPU Saturation & Latency Troubleshooting | PLANNED |
| 54 | Connections, Clients, Timeouts & Network Troubleshooting | PLANNED |
| 55 | Shard, Replica, Node & Proxy Failure Troubleshooting | PLANNED |
| 56 | Production Incident Investigation & SRE Runbook | PLANNED |

## Part 7 — Advanced Redis Enterprise

| # | Tutorial | Status |
|---|---|---|
| 57 | Active-Active Architecture & CRDT Fundamentals | PLANNED |
| 58 | Active-Active Conflict Resolution & Convergence | PLANNED |
| 59 | Active-Active Operations, Monitoring & Failure Handling | PLANNED |
| 60 | Redis Enterprise Kubernetes Operator Architecture | PLANNED |
| 61 | REC, REDB, RERC & REAADB Administration | PLANNED |
| 62 | Kubernetes Storage, Networking, Upgrades & Troubleshooting | PLANNED |
| 63 | Auto Tiering / Flex Architecture & Operations | PLANNED |
| 64 | Redis JSON, Search & Query Capabilities | PLANNED |
| 65 | Streams, Consumer Groups & Messaging Recovery | PLANNED |
| 66 | Transactions, Lua & Server-Side Programmability | PLANNED |
| 67 | REST API Automation & Infrastructure as Code | PLANNED |
| 68 | Configuration Drift, Automation & Operational Governance | PLANNED |

## Part 8 — Recovery, Migration & Disaster Recovery

| # | Tutorial | Status |
|---|---|---|
| 69 | Backup Strategy, Recovery Design, RPO & RTO | PLANNED |
| 70 | Migration, Disaster Recovery, Failover & Failback | PLANNED |

## Part 9 — End-to-End Production Projects

| # | Tutorial | Status |
|---|---|---|
| 71 | Production Cache-Aside Project | PLANNED |
| 72 | Redis Memory & Eviction Engineering Project | PLANNED |
| 73 | High Availability & Failover Project | PLANNED |
| 74 | Backup, Restore & Recovery Project | PLANNED |
| 75 | Redis Performance Engineering Project | PLANNED |
| 76 | Redis Observability & Alerting Project | PLANNED |
| 77 | Active-Active Geo-Distribution Project | PLANNED |
| 78 | Kubernetes Redis Enterprise Operations Project | PLANNED |
| 79 | Production Incident Troubleshooting Project | PLANNED |
| 80 | Redis Enterprise Production Readiness & Acceptance Project | PLANNED |

## Curriculum Coverage

The completed track will cover:

- Redis fundamentals and Redis Enterprise architecture
- nodes, databases, shards, proxies, endpoints and placement
- application connectivity, TLS and connection management
- data structures and memory-aware key design
- caching architecture and application resilience
- memory management, expiration and eviction
- CPU, latency and performance engineering
- sharding, replication and high availability
- persistence, backup and restore
- cluster/database/shard administration
- security, ACLs, TLS and certificate operations
- monitoring, Prometheus, Grafana and alerting
- production incident troubleshooting
- Active-Active and CRDT behavior
- Kubernetes Operator administration
- Auto Tiering / Flex
- JSON, Search and Streams
- programmability and transactions
- REST API and infrastructure automation
- migration and disaster recovery
- RPO/RTO engineering
- end-to-end production projects and acceptance testing

## Production Chapter Requirements

A chapter should not be marked canonical merely because explanatory text exists.

Where applicable, canonical chapters must include:

1. Production-focused concepts.
2. Architecture and internal behavior.
3. Operational commands.
4. A hands-on lab.
5. Expected results.
6. Safe failure injection.
7. Troubleshooting methodology.
8. Production considerations and safety warnings.
9. An operational runbook.
10. Validation questions/checklist.
11. Current Redis documentation validation.

## Lab Safety

Use development, test, staging, or dedicated training databases for write operations and failure exercises.

Production exercises should be read-only unless explicitly reviewed and approved.

Never use destructive commands such as `FLUSHALL` or `FLUSHDB` as routine tutorial cleanup.

## Rebuild Progress

- 01 — Redis Enterprise Fundamentals & Architecture: **REBUILT**
- 02 — Connecting to Redis Enterprise: **REBUILT**
- 03 — Redis Data Types, Key Design & Memory-Aware Data Modeling: **NEXT**
- Overall rebuild: **2 / 80**

## Legacy Chapters

The existing 36 tutorial files remain in the repository during the rebuild. They serve as source material until each corresponding topic is replaced or incorporated into the new production-grade curriculum.

Do not delete legacy content solely because the new master layout has been created. Cleanup should happen only after the relevant replacement chapter is complete and verified.

## Workflow

For each chapter:

```text
Draft
  ↓
Technical validation against current Redis documentation
  ↓
Production/SRE review
  ↓
Hands-on lab and failure-path validation
  ↓
Canonical
  ↓
Repository verification
```

The target is **80/80 production-grade canonical chapters**.
