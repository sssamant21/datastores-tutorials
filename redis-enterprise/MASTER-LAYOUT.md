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

## Scope

Application caching plus self-managed Redis Software administration. Administration labs require a staging cluster and appropriate privileges. Kubernetes and Redis Cloud use their own management procedures. Detailed installation automation and Active-Active deployment remain outside this concise foundation.

## Workflow

Draft → technical validation → production review → canonical. All 23 tutorials are written as drafts; live validation and production review remain pending. See [STATUS.md](STATUS.md).

## Review and validation

See [REVIEW.md](REVIEW.md) for findings, fixes, and pending staging acceptance. Run [tools/validate_tutorials.py](tools/validate_tutorials.py) for offline Markdown, syntax, and simulated caching checks. These do not replace live Enterprise tests.
