# Redis Enterprise — Application Caching

Concise application caching and administration tutorials for developers, data engineers, SREs, and DBREs. Each page includes concepts, examples, validation, and production practices. Run exercises in a test database.

## Application caching — Tutorials 01–12

| # | Tutorial | Status |
|---|---|---|
| 01 | [Redis Enterprise Fundamentals](01-redis-enterprise-fundamentals.md) | Draft |
| 02 | [Connecting to Redis Enterprise](02-connecting-to-redis-enterprise.md) | Draft |
| 03 | [Data Types and Key Design](03-data-types-and-key-design.md) | Draft |
| 04 | [Basic Cache Operations](04-basic-cache-operations.md) | Draft |
| 05 | [TTL and Expiration](05-ttl-and-expiration.md) | Draft |
| 06 | [Implementing Cache-Aside](06-implementing-cache-aside.md) | Draft |
| 07 | [Cache Updates and Invalidation](07-cache-updates-and-invalidation.md) | Draft |
| 08 | [Memory Management and Eviction](08-memory-management-and-eviction.md) | Draft |
| 09 | [Caching Performance](09-caching-performance.md) | Draft |
| 10 | [Cache Failures and Application Resilience](10-cache-failures-and-application-resilience.md) | Draft |
| 11 | [Monitoring and Troubleshooting](11-monitoring-and-troubleshooting.md) | Draft |
| 12 | [Production Readiness and End-to-End Lab](12-production-readiness-and-end-to-end-lab.md) | Draft |

## Administration — Tutorials 13–20

| # | Tutorial | Status |
|---|---|---|
| 13 | [Cluster Administration](13-cluster-administration.md) | Draft |
| 14 | [Database Administration](14-database-administration.md) | Draft |
| 15 | [Security and Access Administration](15-security-and-access-administration.md) | Draft |
| 16 | [Capacity and Shard Administration](16-capacity-and-shard-administration.md) | Draft |
| 17 | [High Availability and Persistence](17-high-availability-and-persistence.md) | Draft |
| 18 | [Backup and Restore Administration](18-backup-and-restore-administration.md) | Draft |
| 19 | [Upgrades and Maintenance](19-upgrades-and-maintenance.md) | Draft |
| 20 | [Administration Runbook and Acceptance](20-administration-runbook-and-acceptance.md) | Draft |

## Operations — Tutorials 21–23

| # | Tutorial | Status |
|---|---|---|
| 21 | [Observability, Dashboards and Alerts](21-observability-dashboards-and-alerts.md) | Draft |
| 22 | [Step-by-Step Troubleshooting](22-step-by-step-troubleshooting.md) | Draft |
| 23 | [Common Problems and Solutions](23-common-problems-and-solutions.md) | Draft |


## Advanced track — Tutorials 24–36

| # | Tutorial | Status |
|---|---|---|
| 24 | [Installation and Deployment](24-installation-and-deployment.md) | Draft |
| 25 | [Kubernetes Operator Administration](25-kubernetes-operator-administration.md) | Draft |
| 26 | [Active-Active Geo-Distribution](26-active-active-geo-distribution.md) | Draft |
| 27 | [Transactions and Programmability](27-transactions-and-programmability.md) | Draft |
| 28 | [Advanced Client Integration](28-advanced-client-integration.md) | Draft |
| 29 | [Advanced Caching and Source Protection](29-advanced-caching-and-source-protection.md) | Draft |
| 30 | [Sessions, Counters, Rate Limits, and Leaderboards](30-sessions-counters-rate-limits-and-leaderboards.md) | Draft |
| 31 | [Streams and Messaging Recovery](31-streams-and-messaging-recovery.md) | Draft |
| 32 | [JSON and Search](32-json-and-search.md) | Draft |
| 33 | [Management Automation and Configuration Drift](33-management-automation-and-configuration-drift.md) | Draft |
| 34 | [Flex and Auto Tiering](34-flex-and-auto-tiering.md) | Draft |
| 35 | [Migration and Disaster Recovery](35-migration-and-disaster-recovery.md) | Draft |
| 36 | [Extended Acceptance and Coverage](36-extended-acceptance-and-coverage.md) | Draft |

## Scope

Application caching plus self-managed Redis Software administration. Administration labs require a staging cluster and appropriate privileges. Kubernetes and Redis Cloud use their own management procedures. The advanced track adds installation, Kubernetes, Active-Active, programmability, clients, application patterns, Streams, JSON/Search, automation, tiering and disaster recovery. Platform mutations use deployed-version workflows. This is the agreed practical scope, not every Redis product or command.

## Workflow

Draft → technical validation → production review → canonical. All 36 tutorials are written as drafts; live validation and production review remain pending. See [STATUS.md](STATUS.md).

## Review and validation

See [REVIEW.md](REVIEW.md) for findings, fixes, and pending staging acceptance. Run [tools/validate_tutorials.py](tools/validate_tutorials.py) for offline Markdown, syntax, and simulated caching checks. These do not replace live Enterprise tests.

