# PostgreSQL Practical Tutorial & Production Labs

Production-oriented PostgreSQL tutorials, hands-on labs, runbooks, and practical use cases for administrators, DBREs, SREs, platform engineers, and application engineers.

## Tutorial Method

Production troubleshooting labs follow:

**Symptom → Evidence → Diagnostic SQL → Root Cause → Immediate Mitigation → Permanent Fix → Validation → Prevention**

## Part 1 — PostgreSQL Foundations

Architecture; server processes; databases, schemas, tables, and objects; directory structure; configuration files; `postgresql.conf`; `pg_hba.conf`; roles and authentication; system catalogs; essential `psql` commands.

**Lab:** Install PostgreSQL and explore a running instance.

## Part 2 — Installation & Production Configuration

Linux installation; package vs source installation; `initdb`; systemd; data-directory design; memory; connections; logging; OS/kernel considerations; production baseline.

**Lab:** Build a production-style PostgreSQL server from scratch.

## Part 3 — Database, Schema & Object Administration

Databases; schemas; tables; constraints; sequences; identity columns; views; materialized views; functions; procedures; extensions; ownership; dependencies.

**Lab:** Build and administer an application database.

## Part 4 — Users, Roles & Security

Login and non-login roles; inheritance; `GRANT`/`REVOKE`; database, schema, table, sequence, and function privileges; default privileges; ownership; `SECURITY DEFINER`; row-level security; SSL/TLS.

**Lab:** Build Developer, Application, Read-Only, and DBA access models.

## Part 5 — Backup, Recovery & Disaster Recovery

Logical and physical backups; `pg_dump`; `pg_restore`; `pg_dumpall`; `pg_basebackup`; WAL archiving; PITR; recovery targets and timelines; backup validation; RPO/RTO; retention; recovery readiness.

**Project:** Design, validate, and rehearse a production recovery strategy with a separate acceptance-evidence lab.

## Part 6 — Streaming Replication, High Availability & Failover

Physical streaming replication; primary/standby architecture; asynchronous and synchronous replication; replication lag; slots and WAL-retention safety; read-only standbys; cascading replication; monitoring; switchover; failover; fencing; rejoin; `pg_rewind`; failback.

**Project:** Build a primary and standby, execute controlled switchover and failover exercises, rejoin the old primary, and produce HA acceptance evidence.

## Part 7 — Storage & WAL

Pages; blocks; tuples; heap storage; TOAST; FSM; visibility map; WAL internals; checkpoints; tablespaces; temporary files; storage sizing.

**Lab:** Trace a transaction from SQL through buffers and WAL to storage.

## Part 8 — MVCC & Transactions

MVCC; `xmin`/`xmax`; transaction IDs; isolation; locks; deadlocks; long-running transactions; idle-in-transaction sessions; multixacts; wraparound.

**Lab:** Reproduce blocking, deadlocks, and long-running transactions.

## Part 9 — VACUUM & Autovacuum

Dead tuples; VACUUM; ANALYZE; autovacuum architecture and thresholds; freeze; wraparound prevention; table/index bloat; tuning methodology.

**Lab:** Generate bloat and troubleshoot autovacuum.

## Part 10 — Indexing

B-tree; Hash; GIN; GiST; BRIN; partial indexes; expression indexes; multicolumn indexes; covering indexes; index bloat; unused and duplicate indexes.

**Lab:** Diagnose a slow query and design the appropriate index.

## Part 11 — Query Performance

Planner; statistics; `EXPLAIN`; `EXPLAIN ANALYZE`; scans; joins; sorts; parallel queries; `work_mem`; `pg_stat_statements`; slow-query investigation.

**Lab:** Perform a production-style query-performance investigation.

## Part 12 — Memory, CPU & Connection Management

`shared_buffers`; `work_mem`; `maintenance_work_mem`; `effective_cache_size`; connection overhead; PgBouncer; CPU saturation; I/O bottlenecks.

**Lab:** Diagnose PostgreSQL at 90–100% CPU.

## Part 13 — Monitoring & Observability

`pg_stat_activity`; `pg_stat_database`; `pg_stat_user_tables`; `pg_stat_user_indexes`; `pg_stat_statements`; locks; WAL; replication; autovacuum; Prometheus/Grafana; alerting.

**Lab:** Build a PostgreSQL operational dashboard.

## Part 14 — Troubleshooting Scenarios

CPU saturation; too many connections; connection exhaustion; slow queries; blocking; deadlocks; long transactions; idle in transaction; autovacuum lag; bloat; disk growth; temporary-file explosion; WAL growth; replication lag; replica failure; checkpoint pressure; OOM; transaction-ID wraparound risk; recovery scenarios.

## Part 15 — PostgreSQL on AWS

RDS PostgreSQL; Aurora PostgreSQL; parameter groups; storage/autoscaling; Multi-AZ; read replicas; Performance Insights; CloudWatch; RDS Proxy; backup/PITR; failover; upgrades.

**Labs:** Real RDS and Aurora operational scenarios.

## Part 16 — PostgreSQL on Azure

Azure Database for PostgreSQL Flexible Server; HA; storage; parameters; monitoring; backup/PITR; read replicas; maintenance; upgrades.

**Labs:** Azure production operational scenarios.

## Part 17 — PostgreSQL on Google Cloud Platform (GCP)

### 17.1 — PostgreSQL Options on GCP
Cloud SQL for PostgreSQL; PostgreSQL on Compute Engine; PostgreSQL on GKE; AlloyDB for PostgreSQL; architecture selection.

### 17.2 — Cloud SQL for PostgreSQL Architecture
Instance architecture; regional vs zonal deployment; primary/standby; storage; connectivity; maintenance model.

### 17.3 — Production Instance Design
Machine sizing; CPU and memory; storage sizing; SSD; storage autoscaling; connection limits; capacity methodology.

### 17.4 — Networking & Connectivity
Private IP; public IP; VPC; Private Service Connect; Cloud SQL Auth Proxy/connectors; application connectivity; network security.

### 17.5 — Authentication & Security
PostgreSQL users; IAM database authentication; service accounts; SSL/TLS; secret management; least privilege.

### 17.6 — PostgreSQL Configuration
Database flags; PostgreSQL parameters; restart-required vs runtime changes; validation; configuration governance.

### 17.7 — High Availability
Regional HA; primary/standby; failover; switchover; application reconnection; HA testing.

### 17.8 — Read Replicas
Replica creation; cross-zone/cross-region patterns; replication lag; read scaling; promotion; DR use cases.

### 17.9 — Backup & PITR
Automated/on-demand backups; PITR; retention; recovery testing; accidental-delete recovery.

### 17.10 — Monitoring & Observability
Cloud Monitoring; Cloud Logging; CPU; memory; connections; disk; IOPS/latency; WAL; replication lag.

### 17.11 — Query Insights
Expensive queries; latency; execution frequency; database load; application tags; correlation with `pg_stat_statements`.

### 17.12 — Performance Troubleshooting
**Lab:** High CPU → Query Insights → `pg_stat_statements` → `EXPLAIN ANALYZE` → root cause.

**Lab:** High latency → Cloud Monitoring → storage/I/O → PostgreSQL wait events → query analysis.

### 17.13 — Connection Management
Connection limits; connection storms; pooling; PgBouncer; Cloud SQL connectors; application design.

### 17.14 — Autovacuum & Bloat
Dead tuples; long transactions; bloat; wraparound risk; monitoring; tuning.

### 17.15 — Storage & Capacity Management
Disk utilization; autoscaling; WAL growth; temporary files; table/index growth; forecasting; storage-exhaustion incidents.

### 17.16 — Maintenance & Patching
Maintenance windows; PostgreSQL minor versions; maintenance events; restart impact; pre/post-validation.

### 17.17 — Major PostgreSQL Upgrades
Compatibility; extensions; prechecks; testing; upgrade; validation; rollback planning.

### 17.18 — Disaster Recovery
Regional failures; cross-region replicas; RPO/RTO; promotion; application cutover; DR drills.

### 17.19 — Cloud SQL Troubleshooting Runbooks
CPU 100%; memory pressure; too many connections; slow queries; locking/deadlocks; disk growth; replication lag; autovacuum; WAL growth; failover; connectivity failures.

### 17.20 — PostgreSQL on Compute Engine
Self-managed PostgreSQL; systemd; disks; WAL; replication; Patroni; backups; monitoring; upgrades; failover.

### 17.21 — PostgreSQL on GKE
Operators; StatefulSets; persistent storage; CloudNativePG/other operator patterns; HA; backups; failover; monitoring; upgrades; DR.

### 17.22 — AlloyDB for PostgreSQL
Cloud SQL vs AlloyDB vs self-managed PostgreSQL; compatibility; performance; HA; read scaling; operational control; cost and workload selection.

### 17.23 — Migration to GCP
On-prem/AWS/Azure PostgreSQL migrations; `pg_dump`/`pg_restore`; logical replication; Database Migration Service; large-database and low-downtime migration; validation; rollback.

### 17.24 — GCP Production Lab

Build:

**Python App → Cloud SQL Connector/PgBouncer → Cloud SQL PostgreSQL HA → Read Replica → Backup/PITR → Cloud Monitoring + Query Insights**

Inject and troubleshoot CPU saturation, connection exhaustion, slow SQL, blocking, bloat, replication lag, and storage pressure.

## Part 18 — PostgreSQL on Kubernetes

StatefulSets; persistent storage; operators; CloudNativePG; Patroni-based deployments; backups; HA; failover; monitoring; upgrades.

**Lab:** Run and recover PostgreSQL on Kubernetes across GKE/EKS/AKS concepts.

## Part 19 — Automation with Python

Driver setup; connection management; configuration-driven connections; database/schema/table creation; DDL; data loading; bulk ingestion; transactions; retries; pooling; health checks; maintenance; backups; monitoring; multi-database configuration.

**Project:** Build a configuration-driven PostgreSQL administration pipeline.

## Part 20 — Production Runbooks

High CPU; high connections; slow queries; blocking/deadlocks; disk full; WAL growth; replication lag; autovacuum failure; bloat; failover; restore; emergency access; password rotation; upgrades; capacity expansion.

## Part 21 — Real-World Production Project

Build:

**Python Application → PgBouncer → PostgreSQL Primary → Replica → Backup/PITR → Prometheus/Grafana**

Then deliberately introduce slow SQL, missing indexes, connection exhaustion, blocking, bloat, replication lag, and disk pressure. Diagnose, remediate, validate, and document each incident.

## Multi-Cloud Coverage

- AWS → RDS PostgreSQL / Aurora PostgreSQL
- Azure → Azure Database for PostgreSQL
- GCP → Cloud SQL for PostgreSQL / AlloyDB
- Kubernetes → GKE / EKS / AKS with PostgreSQL operators
