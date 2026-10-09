# Redis Enterprise — Complete Production Engineering Track

**Status:** ACTIVE — 80-Chapter Production Engineering Curriculum
**Target:** 80 production-grade chapters
**Current content:** Chapters 01–51
**Next:** Chapter 52
**Workflow:** Draft → Technical Validation → Production Review → Canonical → Repository Verification

> This layout is the authoritative curriculum. It was reconciled on 2026-10-09 against the actual rebuilt chapter sequence. Duplicate Chapter 44 security content and duplicate Chapter 47 capacity content were replaced with distinct production topics; missing Chapter 42 was restored.

## Part 1 — Foundations & Architecture

| # | Tutorial | Status |
|---|---|---|
| 01 | Redis Enterprise Fundamentals & Architecture | COMPLETE |
| 02 | Connecting to Redis Enterprise — Clients, Endpoints, TLS & Connection Management | COMPLETE |
| 03 | Redis Data Types, Key Design & Memory-Aware Data Modeling | COMPLETE |
| 04 | Redis Commands, Command Semantics & Safe Operations | COMPLETE |
| 05 | Redis Enterprise Databases, Endpoints & Configuration | COMPLETE |
| 06 | Redis Enterprise Nodes, Shards, Proxies & Placement | COMPLETE |
| 07 | Hash Slots, Key Distribution & Sharding Internals | COMPLETE |
| 08 | Replication Architecture & Primary/Replica Behavior | COMPLETE |
| 09 | Redis Enterprise Administration Interfaces — UI, rladmin & REST API | COMPLETE |
| 10 | Architecture Inspection & Foundation Acceptance Lab | COMPLETE |

## Part 2 — Caching & Application Engineering

| # | Tutorial | Status |
|---|---|---|
| 11 | TTL, Expiration & Cache Freshness Engineering | COMPLETE |
| 12 | Cache-Aside Pattern | COMPLETE |
| 13 | Cache Updates, Invalidation & Consistency | COMPLETE |
| 14 | Write-Through, Write-Behind & Read-Through Patterns | COMPLETE |
| 15 | Cache Stampede, Thundering Herd & Source Protection | COMPLETE |
| 16 | Cache Warming, Refresh-Ahead & Cold-Start Engineering | COMPLETE |
| 17 | Redis Eviction Policies, Memory Pressure & Cache Survival Engineering | COMPLETE |
| 18 | Redis Hot Keys, Big Keys & Workload Skew Engineering | COMPLETE |
| 19 | Redis TTL Strategy, Expiration Engineering & Data Freshness | COMPLETE |
| 20 | Redis Cache Invalidation, Consistency & Change Propagation | COMPLETE |

## Part 3 — Application Reliability & Command Engineering

| # | Tutorial | Status |
|---|---|---|
| 21 | Redis Pipelining, Batching & Round-Trip Optimization | COMPLETE |
| 22 | Redis Transactions, WATCH & Atomic Update Patterns | COMPLETE |
| 23 | Redis Lua Scripting & Server-Side Atomic Logic | COMPLETE |
| 24 | Redis Distributed Locks, Leases & Coordination Patterns | COMPLETE |
| 25 | Redis Rate Limiting, Quotas & Traffic Protection | COMPLETE |
| 26 | Redis Connection Management, Pooling & Client Reliability | COMPLETE |
| 27 | Redis Pipelining, Batching & High-Throughput Command Engineering | COMPLETE — REVIEW OVERLAP WITH 21 |
| 28 | Redis Serialization, Compression & Value-Size Engineering | COMPLETE |
| 29 | Redis Key Naming, Namespaces & Keyspace Design | COMPLETE |
| 30 | Redis Multi-Tenancy, Isolation & Noisy-Neighbor Engineering | COMPLETE |

> Chapter 27 is retained for now because it contains high-throughput workload engineering beyond basic round-trip optimization. During final 80/80 review, Chapter 21/27 will receive a content-deduplication pass rather than deleting either chapter blindly.

## Part 4 — Messaging, Persistence, HA & Geo

| # | Tutorial | Status |
|---|---|---|
| 31 | Redis Pub/Sub, Messaging & Real-Time Event Delivery | COMPLETE |
| 32 | Redis Streams, Consumer Groups & Durable Event Processing | COMPLETE |
| 33 | Redis Streams Reliability, Retry, DLQ & Recovery Engineering | COMPLETE |
| 34 | Redis Persistence: RDB, AOF & Durability Engineering | COMPLETE |
| 35 | Redis Replication, High Availability & Failover Engineering | COMPLETE |
| 36 | Redis Backup, Restore & Disaster Recovery Engineering | COMPLETE |
| 37 | Redis Enterprise Active-Active, Geo-Distribution & Multi-Region Engineering | COMPLETE |

## Part 5 — Security

| # | Tutorial | Status |
|---|---|---|
| 38 | Redis Enterprise Security, Authentication, Authorization & TLS Engineering | COMPLETE |

## Part 6 — Observability, Reliability, Change & Governance

| # | Tutorial | Status |
|---|---|---|
| 39 | Redis Enterprise Observability, Metrics, Alerting & SLO Engineering | COMPLETE |
| 40 | Redis Enterprise Performance Troubleshooting & Production Incident Engineering | COMPLETE |
| 41 | Redis Enterprise Capacity Planning, Scaling & Resource Engineering | COMPLETE |
| 42 | Redis Enterprise Upgrades, Maintenance & Change Engineering | COMPLETE |
| 43 | Redis Enterprise Automation, APIs, CLI & Infrastructure-as-Code Engineering | COMPLETE |
| 44 | Redis Enterprise Governance, Standards & Operational Readiness Engineering | COMPLETE |

## Part 7 — Platform, Cloud & Database Service Operations

| # | Tutorial | Status |
|---|---|---|
| 45 | Redis Enterprise Kubernetes Operations, Scheduling & Platform Engineering | COMPLETE |
| 46 | Redis Enterprise Cloud Infrastructure, Networking & Storage Engineering | COMPLETE |
| 47 | Redis Enterprise Database Lifecycle, Provisioning & Configuration Engineering | COMPLETE |

## Part 8 — Production Operations

| # | Tutorial | Status |
|---|---|---|
| 48 | Redis Enterprise Production Readiness, Operational Acceptance & Go-Live Engineering | COMPLETE |
| 49 | Redis Enterprise Incident Management, RCA & Corrective Action Engineering | COMPLETE |
| 50 | Redis Enterprise SRE Runbooks, Day-2 Operations & Production Operations Handbook | COMPLETE |

## Part 9 — Integrated Project

| # | Tutorial | Status |
|---|---|---|
| 51 | Redis Enterprise End-to-End Production Engineering Project | COMPLETE |

## Part 10 — Migration, Data Services & Advanced Capabilities

| # | Tutorial | Status |
|---|---|---|
| 52 | Redis Enterprise Data Migration, Import/Export & Cutover Engineering | NEXT |
| 53 | Redis Enterprise Client SDK Compatibility & Application Integration Engineering | PLANNED |
| 54 | Redis Enterprise Benchmarking, Load Testing & Performance Qualification Engineering | PLANNED |
| 55 | Redis Enterprise RedisJSON Data Modeling & Document Engineering | PLANNED |
| 56 | Redis Enterprise Search & Query Architecture, Indexing & Operations | PLANNED |
| 57 | Redis Enterprise Search Performance, Capacity & Troubleshooting Engineering | PLANNED |
| 58 | Redis Enterprise Vector Search & Semantic Retrieval Engineering | PLANNED |
| 59 | Redis Enterprise Modules/Capabilities Lifecycle & Compatibility Engineering | PLANNED |
| 60 | Redis Enterprise Auto Tiering / Flex Architecture & Operations | PLANNED |

## Part 11 — Advanced Kubernetes, Active-Active & Platform Engineering

| # | Tutorial | Status |
|---|---|---|
| 61 | Redis Enterprise Kubernetes Operator Architecture & Reconciliation | PLANNED |
| 62 | REC, REDB, RERC & REAADB Resource Administration | PLANNED |
| 63 | Redis Enterprise Kubernetes Storage, Networking & Failure Engineering | PLANNED |
| 64 | Redis Enterprise Kubernetes Upgrade, Backup & Recovery Operations | PLANNED |
| 65 | Redis Enterprise Active-Active CRDT Semantics & Conflict Engineering | PLANNED |
| 66 | Redis Enterprise Active-Active Operations, Monitoring & Failure Recovery | PLANNED |
| 67 | Redis Enterprise Active-Active Regional Cutover, Rejoin & Failback Engineering | PLANNED |
| 68 | Redis Enterprise Multi-Cluster / Multi-Environment Platform Standards | PLANNED |

## Part 12 — Advanced Operations, FinOps & Resilience

| # | Tutorial | Status |
|---|---|---|
| 69 | Redis Enterprise Advanced Memory Forensics, Fragmentation & Allocator Engineering | PLANNED |
| 70 | Redis Enterprise Command Complexity, SLOWLOG & Latency Forensics | PLANNED |
| 71 | Redis Enterprise Proxy, Endpoint & Network Path Troubleshooting Engineering | PLANNED |
| 72 | Redis Enterprise Shard Rebalancing, Resharding & Placement Operations | PLANNED |
| 73 | Redis Enterprise Cost Optimization & FinOps Engineering | PLANNED |
| 74 | Redis Enterprise Configuration Drift, Compliance & Audit Automation | PLANNED |
| 75 | Redis Enterprise Business Continuity, Regional DR & Failback Project | PLANNED |

## Part 13 — Production Projects & Final Acceptance

| # | Tutorial | Status |
|---|---|---|
| 76 | Redis Enterprise Performance & Capacity Engineering Project | PLANNED |
| 77 | Redis Enterprise Security Hardening & Credential-Rotation Project | PLANNED |
| 78 | Redis Enterprise Kubernetes Production Operations Project | PLANNED |
| 79 | Redis Enterprise Incident, Recovery & Resilience Game-Day Project | PLANNED |
| 80 | Redis Enterprise Final Production Readiness & Acceptance Project | PLANNED |

## Curriculum Rules

Every production-grade chapter should include, where applicable:

1. production-focused concepts;
2. architecture/internal behavior;
3. operational commands/examples;
4. hands-on lab;
5. expected behavior;
6. safe failure injection;
7. troubleshooting;
8. production considerations;
9. operational runbooks;
10. validation questions/checklists;
11. cleanup;
12. exact-version vendor-documentation validation.

## Lab Safety

Use development, test, staging, or dedicated training databases for write/failure exercises. Production exercises should be read-only unless explicitly reviewed and approved. Never use FLUSHALL or FLUSHDB as routine tutorial cleanup.

## Progress

Content present: **51 / 80**
Remaining: **29**
Next: **Chapter 52 — Redis Enterprise Data Migration, Import/Export & Cutover Engineering**
Target: **80 / 80**

## Final Review Rule

At 80/80, perform a complete sequence audit for duplicate content, broken links, filename/title consistency, lab safety, current Redis documentation compatibility, and tracker accuracy before declaring the curriculum complete.
