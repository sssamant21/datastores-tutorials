# MongoDB Enterprise — Complete Production Curriculum

**Audience:** Developers, Data Engineers, DBREs, SREs and Platform Engineers  
**Workflow:** Planned → Draft → Technical review → Lab validated → Canonical  
**Progress:** 8/80 written; 0/80 runtime validated.  
**Lab baseline:** MongoDB 8.0 syntax; record exact server, mongosh, driver, tool and operator versions in every lab. Existing 7.0 deployments require their own compatibility review. Enterprise-only exercises require authorized Enterprise binaries and entitlements; Community labs must not claim Enterprise feature validation.

## Part 1 — Foundations and Architecture

| # | Chapter | Lab outcome | Status |
|---|---|---|---|
| 01 | [MongoDB Enterprise Fundamentals](01-mongodb-enterprise-fundamentals.md) | Create, query, update and verify a synthetic document collection | Written; runtime validation pending |
| 02 | [Document Model and BSON Types](02-document-model-and-bson-types.md) | Inspect BSON types, repair mismatches, verify EJSON and reject invalid documents | Written; runtime validation pending |
| 03 | [Server Architecture and WiredTiger](03-server-architecture-and-wiredtiger.md) | Collect WiredTiger snapshots, verify a bounded workload and distinguish storage sizes | Written; runtime validation pending |
| 04 | [Community Enterprise Advanced and Atlas](04-community-enterprise-advanced-and-atlas.md) | Inventory build/topology, verify a common contract and separate entitlement evidence | Written; runtime validation pending |
| 05 | [Lab Setup and Version Inventory](05-lab-setup-and-version-inventory.md) | Build authenticated persistent training server, inventory versions and test scoped access | Written; runtime validation pending |
| 06 | [mongosh Connections TLS and Authentication](06-mongosh-connections-tls-and-authentication.md) | Build verified TLS/SCRAM lab and distinguish transport, authentication and permission failures | Written; runtime validation pending |
| 07 | [Databases Collections and Namespaces](07-databases-collections-and-namespaces.md) | Inspect namespace metadata, reproduce a typo, verify read-only views and reverse a controlled rename | Written; runtime validation pending |
| 08 | [CRUD Filters Projections and Sorting](08-crud-filters-projections-and-sorting.md) | Verify bounded query contracts, guarded state transitions, upserts, bulk counts and scoped deletion | Written; runtime validation pending |

## Part 2 — Data Modeling and Application Development

| # | Chapter | Lab outcome | Status |
|---|---|---|---|
| 09 | Nested Documents and Arrays | Demonstrate nested documents and arrays with evidence and cleanup | Planned |
| 10 | Embedding Versus Referencing | Demonstrate embedding versus referencing with evidence and cleanup | Planned |
| 11 | Schema Validation and Evolution | Demonstrate schema validation and evolution with evidence and cleanup | Planned |
| 12 | Updates Upserts and Bulk Writes | Demonstrate updates upserts and bulk writes with evidence and cleanup | Planned |
| 13 | Aggregation Pipeline Fundamentals | Demonstrate aggregation pipeline fundamentals with evidence and cleanup | Planned |
| 14 | Advanced Aggregations and Joins | Demonstrate advanced aggregations and joins with evidence and cleanup | Planned |
| 15 | Pagination and API Query Design | Demonstrate pagination and api query design with evidence and cleanup | Planned |
| 16 | Transactions Sessions and Retry Semantics | Demonstrate transactions sessions and retry semantics with evidence and cleanup | Planned |

## Part 3 — Indexes and Performance

| # | Chapter | Lab outcome | Status |
|---|---|---|---|
| 17 | Single Field and Compound Indexes | Demonstrate single field and compound indexes with evidence and cleanup | Planned |
| 18 | ESR Index Design and Covered Queries | Demonstrate esr index design and covered queries with evidence and cleanup | Planned |
| 19 | Multikey Partial Sparse and Unique Indexes | Demonstrate multikey partial sparse and unique indexes with evidence and cleanup | Planned |
| 20 | TTL Retention and Index Lifecycle | Demonstrate ttl retention and index lifecycle with evidence and cleanup | Planned |
| 21 | Explain Plans and Query Optimization | Demonstrate explain plans and query optimization with evidence and cleanup | Planned |
| 22 | Profiling Slow Queries and Query Statistics | Demonstrate profiling slow queries and query statistics with evidence and cleanup | Planned |
| 23 | WiredTiger Cache Eviction and Checkpoints | Demonstrate wiredtiger cache eviction and checkpoints with evidence and cleanup | Planned |
| 24 | CPU Memory Storage IOPS and Capacity | Demonstrate cpu memory storage iops and capacity with evidence and cleanup | Planned |

## Part 4 — Replication and High Availability

| # | Chapter | Lab outcome | Status |
|---|---|---|---|
| 25 | Replica Set Architecture and Oplog | Demonstrate replica set architecture and oplog with evidence and cleanup | Planned |
| 26 | Build a Three Member Replica Set | Demonstrate build a three member replica set with evidence and cleanup | Planned |
| 27 | Read Preference Read Concern and Write Concern | Demonstrate read preference read concern and write concern with evidence and cleanup | Planned |
| 28 | Elections Stepdown and Planned Maintenance | Demonstrate elections stepdown and planned maintenance with evidence and cleanup | Planned |
| 29 | Replication Lag and Oplog Sizing | Demonstrate replication lag and oplog sizing with evidence and cleanup | Planned |
| 30 | Initial Sync Resync and Member Replacement | Demonstrate initial sync resync and member replacement with evidence and cleanup | Planned |
| 31 | Network Partitions Rollback and Consistency | Demonstrate network partitions rollback and consistency with evidence and cleanup | Planned |
| 32 | Replica Set Failure and Recovery Lab | Demonstrate replica set failure and recovery lab with evidence and cleanup | Planned |

## Part 5 — Sharding and Scale

| # | Chapter | Lab outcome | Status |
|---|---|---|---|
| 33 | Sharded Cluster Architecture | Demonstrate sharded cluster architecture with evidence and cleanup | Planned |
| 34 | Shard Key Selection and Workload Analysis | Demonstrate shard key selection and workload analysis with evidence and cleanup | Planned |
| 35 | Build a Sharded Lab Cluster | Demonstrate build a sharded lab cluster with evidence and cleanup | Planned |
| 36 | Chunk Distribution Balancing and Zones | Demonstrate chunk distribution balancing and zones with evidence and cleanup | Planned |
| 37 | Targeted Queries Scatter Gather and Hot Shards | Demonstrate targeted queries scatter gather and hot shards with evidence and cleanup | Planned |
| 38 | Resharding and Shard Key Refinement | Demonstrate resharding and shard key refinement with evidence and cleanup | Planned |
| 39 | Sharded Cluster Administration and Recovery | Demonstrate sharded cluster administration and recovery with evidence and cleanup | Planned |
| 40 | Scaling and Sharding Acceptance Lab | Demonstrate scaling and sharding acceptance lab with evidence and cleanup | Planned |

## Part 6 — Enterprise Security and Governance

| # | Chapter | Lab outcome | Status |
|---|---|---|---|
| 41 | Users Roles and Least Privilege | Demonstrate users roles and least privilege with evidence and cleanup | Planned |
| 42 | TLS Certificates and x509 Authentication | Demonstrate tls certificates and x509 authentication with evidence and cleanup | Planned |
| 43 | Enterprise External Authentication Compatibility | Demonstrate enterprise external authentication compatibility with evidence and cleanup | Planned |
| 44 | Enterprise Audit Configuration and Analysis | Demonstrate enterprise audit configuration and analysis with evidence and cleanup | Planned |
| 45 | Encryption at Rest and Key Management | Demonstrate encryption at rest and key management with evidence and cleanup | Planned |
| 46 | Client Side and Queryable Encryption | Demonstrate client side and queryable encryption with evidence and cleanup | Planned |
| 47 | Secrets Rotation and Access Review | Demonstrate secrets rotation and access review with evidence and cleanup | Planned |
| 48 | Security Hardening Acceptance Lab | Demonstrate security hardening acceptance lab with evidence and cleanup | Planned |

## Part 7 — Backup Recovery and Disaster Recovery

| # | Chapter | Lab outcome | Status |
|---|---|---|---|
| 49 | Backup Architecture RPO and RTO | Demonstrate backup architecture rpo and rto with evidence and cleanup | Planned |
| 50 | mongodump mongorestore and Logical Recovery | Demonstrate mongodump mongorestore and logical recovery with evidence and cleanup | Planned |
| 51 | Consistent Snapshots and Restore Validation | Demonstrate consistent snapshots and restore validation with evidence and cleanup | Planned |
| 52 | Ops Manager Backup and Point in Time Recovery | Demonstrate ops manager backup and point in time recovery with evidence and cleanup | Planned |
| 53 | Accidental Delete and Drop Recovery | Demonstrate accidental delete and drop recovery with evidence and cleanup | Planned |
| 54 | Replica Set Disaster Recovery | Demonstrate replica set disaster recovery with evidence and cleanup | Planned |
| 55 | Sharded Cluster Backup and Disaster Recovery | Demonstrate sharded cluster backup and disaster recovery with evidence and cleanup | Planned |
| 56 | Restore Drill and Recovery Acceptance Project | Demonstrate restore drill and recovery acceptance project with evidence and cleanup | Planned |

## Part 8 — Administration Deployment and Integration

| # | Chapter | Lab outcome | Status |
|---|---|---|---|
| 57 | Ops Manager Architecture and Prerequisites | Demonstrate ops manager architecture and prerequisites with evidence and cleanup | Planned |
| 58 | Ops Manager Automation Monitoring and Agents | Demonstrate ops manager automation monitoring and agents with evidence and cleanup | Planned |
| 59 | Linux Installation Configuration and Service Operations | Demonstrate linux installation configuration and service operations with evidence and cleanup | Planned |
| 60 | Kubernetes Operator Compatibility and Deployment | Demonstrate kubernetes operator compatibility and deployment with evidence and cleanup | Planned |
| 61 | Kubernetes Storage Scheduling and Maintenance | Demonstrate kubernetes storage scheduling and maintenance with evidence and cleanup | Planned |
| 62 | Rolling Upgrades FCV and Rollback Constraints | Demonstrate rolling upgrades fcv and rollback constraints with evidence and cleanup | Planned |
| 63 | Drivers Connection Pools Timeouts and Retries | Demonstrate drivers connection pools timeouts and retries with evidence and cleanup | Planned |
| 64 | Change Streams Resume Tokens and CDC | Demonstrate change streams resume tokens and cdc with evidence and cleanup | Planned |

## Part 9 — Specialized Data and Observability

| # | Chapter | Lab outcome | Status |
|---|---|---|---|
| 65 | Time Series Collections and Retention | Demonstrate time series collections and retention with evidence and cleanup | Planned |
| 66 | GridFS Capped Collections and Workload Boundaries | Demonstrate gridfs capped collections and workload boundaries with evidence and cleanup | Planned |
| 67 | MongoDB to Snowflake Direct Integration | Demonstrate mongodb to snowflake direct integration with evidence and cleanup | Planned |
| 68 | Import Export Migration and Data Reconciliation | Demonstrate import export migration and data reconciliation with evidence and cleanup | Planned |
| 69 | Metrics Logs FTDC and Dashboard Design | Demonstrate metrics logs ftdc and dashboard design with evidence and cleanup | Planned |
| 70 | Alert Thresholds SLOs and Capacity Forecasting | Demonstrate alert thresholds slos and capacity forecasting with evidence and cleanup | Planned |
| 71 | Daily Administration and Maintenance Runbook | Demonstrate daily administration and maintenance runbook with evidence and cleanup | Planned |
| 72 | Cost Optimization and Enterprise License Planning | Demonstrate cost optimization and enterprise license planning with evidence and cleanup | Planned |

## Part 10 — Troubleshooting and Production Projects

| # | Chapter | Lab outcome | Status |
|---|---|---|---|
| 73 | Query Slowness Investigation Runbook | Demonstrate query slowness investigation runbook with evidence and cleanup | Planned |
| 74 | Connection Authentication and TLS Troubleshooting | Demonstrate connection authentication and tls troubleshooting with evidence and cleanup | Planned |
| 75 | Disk Pressure Cache Pressure and Resource Incidents | Demonstrate disk pressure cache pressure and resource incidents with evidence and cleanup | Planned |
| 76 | Replication Elections and Sharding Troubleshooting | Demonstrate replication elections and sharding troubleshooting with evidence and cleanup | Planned |
| 77 | Production Data Modeling and Query Tuning Project | Demonstrate production data modeling and query tuning project with evidence and cleanup | Planned |
| 78 | HA Failover and Application Resilience Project | Demonstrate ha failover and application resilience project with evidence and cleanup | Planned |
| 79 | Backup Restore and Disaster Recovery Project | Demonstrate backup restore and disaster recovery project with evidence and cleanup | Planned |
| 80 | Production Readiness and Final Acceptance Project | Demonstrate production readiness and final acceptance project with evidence and cleanup | Planned |

## Coverage boundaries

This is a production-focused curriculum, not a claim to cover every product feature or every supported version. Search/vector features and product-specific services must receive explicit deployment and edition checks before being added. External authentication, operator support, upgrades and encryption require version-specific documentation review. MongoDB→Snowflake integration is direct; Elasticsearch is not a required intermediary.
