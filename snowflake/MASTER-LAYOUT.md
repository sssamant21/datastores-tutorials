# Snowflake — Complete Production Tutorial Track

**Status:** ACTIVE — Master Layout v1.0  
**Audience:** Data Engineers, Snowflake Administrators, DBREs, SREs, Platform Engineers, Developers  
**Workflow:** Draft → Technical Validation → Production Review → Canonical  
**Repository rule:** Complete and validate five canonical chapters, then push that five-chapter batch before starting the next batch.

## Curriculum

| # | Tutorial | Status |
|---|---|---|
| 01 | [Snowflake Fundamentals](01-snowflake-fundamentals.md) | Canonical |
| 02 | [Snowflake Architecture — Storage, Compute & Cloud Services](02-snowflake-architecture-storage-compute-cloud-services.md) | Canonical |
| 03 | [Databases, Schemas, Tables & Objects](03-databases-schemas-tables-objects.md) | Canonical |
| 04 | [Virtual Warehouses & Compute Architecture](04-virtual-warehouses-compute-architecture.md) | Canonical |
| 05 | [Snowflake Editions, Regions & Cloud Platforms](05-snowflake-editions-regions-cloud-platforms.md) | Canonical |
| 06 | Table Types — Permanent, Transient & Temporary | Planned |
| 07 | Snowflake Data Types & Semi-Structured Data | Planned |
| 08 | Views, Secure Views & Materialized Views | Planned |
| 09 | Sequences, Identity Columns & Generated Values | Planned |
| 10 | SQL Fundamentals, Joins, CTEs & Window Functions | Planned |
| 11 | Stages — Internal & External | Planned |
| 12 | File Formats | Planned |
| 13 | COPY INTO — Bulk Data Loading | Planned |
| 14 | Data Unloading with COPY INTO | Planned |
| 15 | Loading Troubleshooting & Validation | Planned |
| 16 | Snowpipe | Planned |
| 17 | Snowpipe Streaming | Planned |
| 18 | Streams & Change Data Capture | Planned |
| 19 | Tasks & Scheduled Processing | Planned |
| 20 | Dynamic Tables & Declarative Pipelines | Planned |
| 21 | Streams + Tasks Production Pipelines | Planned |
| 22 | MERGE, UPSERT & Incremental Processing | Planned |
| 23 | Stored Procedures | Planned |
| 24 | User-Defined Functions — SQL/Python/Java | Planned |
| 25 | External Functions & API Integrations | Planned |
| 26 | Snowflake Authentication | Planned |
| 27 | RBAC & Role Hierarchy | Planned |
| 28 | Users, Roles & Privilege Management | Planned |
| 29 | Future Grants & Managed Access Schemas | Planned |
| 30 | Network Policies & Connectivity Security | Planned |
| 31 | MFA, SSO & Key-Pair Authentication | Planned |
| 32 | Secrets & External Access Integrations | Planned |
| 33 | Dynamic Data Masking | Planned |
| 34 | Row Access Policies | Planned |
| 35 | Tags, Classification & Governance | Planned |
| 36 | Snowflake Query Processing Internals | Planned |
| 37 | Query Profile Deep Dive | Planned |
| 38 | Micro-Partitions & Pruning | Planned |
| 39 | Clustering & Automatic Clustering | Planned |
| 40 | Caching — Result, Metadata & Warehouse Cache | Planned |
| 41 | Search Optimization Service | Planned |
| 42 | Query Acceleration Service | Planned |
| 43 | Warehouse Sizing & Scaling | Planned |
| 44 | Multi-Cluster Warehouses & Concurrency | Planned |
| 45 | Performance Troubleshooting | Planned |
| 46 | ACCOUNT_USAGE & INFORMATION_SCHEMA | Planned |
| 47 | Query History & Workload Analysis | Planned |
| 48 | Warehouse Monitoring | Planned |
| 49 | Storage & Data Growth Monitoring | Planned |
| 50 | Alerts, Notifications & Observability | Planned |
| 51 | Snowflake Credit & Billing Model | Planned |
| 52 | Compute Cost Analysis | Planned |
| 53 | Storage Cost Analysis | Planned |
| 54 | Resource Monitors & Cost Controls | Planned |
| 55 | Snowflake FinOps & Cost Optimization | Planned |
| 56 | Time Travel | Planned |
| 57 | Fail-safe | Planned |
| 58 | Zero-Copy Cloning | Planned |
| 59 | Backup & Recovery Strategies | Planned |
| 60 | Accidental DELETE/DROP Recovery Runbook | Planned |
| 61 | Secure Data Sharing | Planned |
| 62 | Provider & Consumer Configuration | Planned |
| 63 | Reader Accounts | Planned |
| 64 | Listings & Snowflake Marketplace | Planned |
| 65 | Secure Cross-Account Data Sharing | Planned |
| 66 | Database Replication | Planned |
| 67 | Account Replication | Planned |
| 68 | Failover Groups | Planned |
| 69 | Cross-Region / Cross-Cloud DR | Planned |
| 70 | Snowflake DR Runbook & Testing | Planned |
| 71 | SnowSQL & Snowflake CLI | Planned |
| 72 | Python Connector & Snowpark | Planned |
| 73 | Terraform / Infrastructure as Code | Planned |
| 74 | REST APIs & Automation | Planned |
| 75 | Production Administration Runbook | Planned |
| 76 | Query Slowness Troubleshooting | Planned |
| 77 | Warehouse & Concurrency Troubleshooting | Planned |
| 78 | Data Loading / Snowpipe Troubleshooting | Planned |
| 79 | Authentication & Permission Troubleshooting | Planned |
| 80 | Production Incident Investigation Runbook | Planned |
| 81 | Locks, Transactions & Concurrency | Planned |
| 82 | Resource Contention & Queueing | Planned |
| 83 | Metadata & Cloud Services Performance | Planned |
| 84 | Capacity Planning & Workload Isolation | Planned |
| 85 | Production Health Check & Readiness Review | Planned |
| 86 | Batch Ingestion Production Project | Planned |
| 87 | CDC / Incremental Pipeline Project | Planned |
| 88 | Secure Data Sharing Project | Planned |
| 89 | Performance & Cost Optimization Project | Planned |
| 90 | Production Snowflake Acceptance Lab | Planned |

## Batch checkpoints

- 01–05 → Batch 1
- 06–10 → Batch 2
- Continue in five-chapter batches through 86–90.

## Scope

The track covers foundations, SQL/data objects, ingestion, pipelines, data engineering, security, governance, performance, observability, FinOps, recovery, sharing, replication/DR, automation, troubleshooting, SRE operations, and end-to-end production projects.

Vendor behavior is validated against current Snowflake documentation during technical validation. Exercises should be run in a non-production account unless explicitly identified as safe read-only production inspection.
