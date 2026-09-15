# Elasticsearch Administrator / DBRE / SRE — Master Learning Roadmap

This track is production-oriented and practice-first. The learning model is:

**Tutorial → Hands-On Lab → Troubleshooting Scenario → Production Use Case → Runbook → Automation**

Mapping governance and query performance are first-class Administrator/DBRE/SRE responsibilities because mapping and query design directly affect CPU, heap, disk I/O, shard pressure, thread pools, latency, scalability, and cluster reliability. Application and data teams retain ownership of business semantics and search requirements; DBRE/SRE provides technical governance, performance validation, and production guardrails.

## Module 01 — Production Architecture & Cluster Fundamentals

- Elasticsearch and Lucene architecture
- Cluster, node, index, shard, document, and segment model
- Node roles
- Cluster state
- Discovery and master election concepts
- Primary and replica shards
- Request routing
- Search scatter/gather
- Indexing lifecycle
- Near-real-time behavior

**Lab:** Build and inspect a multi-node cluster; stop a node and observe recovery.

**Runbook:** Cluster Health & Node Failure Investigation.

## Module 02 — Production Installation & Configuration

- Production prerequisites
- `elasticsearch.yml`
- JVM configuration
- Storage and networking
- Discovery configuration
- Bootstrap checks
- File descriptors and OS considerations
- Configuration governance
- Safe restart procedures

**Runbook:** Node Startup / Configuration Failure.

## Module 03 — Index, Shard & Replica Administration

- Index settings
- Primary and replica shard design
- Shard sizing
- Oversharding and oversized shards
- Allocation and routing
- Aliases and templates
- Rollover
- Versioned indices
- Reindexing
- Zero-downtime alias cutover

**Runbooks:** Shard Allocation Troubleshooting; Oversized Shard Remediation; Reindex & Alias Cutover.

## Module 04 — Mapping Governance & Data Modeling

- Mapping architecture
- Explicit vs dynamic mapping
- `text` vs `keyword`
- Numeric, date, boolean, and IP types
- Arrays
- `object` vs `nested`
- Multi-fields
- `doc_values`
- Fielddata
- `ignore_above`
- Dynamic templates
- Mapping explosion
- Field limits
- Mapping compatibility
- Mapping versioning
- Reindex requirements

**Lab:** Create intentionally poor mappings and observe operational consequences.

**Runbook:** Mapping Explosion / Field Limit Investigation.

**Governance artifact:** Production Mapping Review Checklist.

## Module 05 — Query DSL for Administrator / DBRE / SRE

- `match`
- `term` and `terms`
- `range`
- `exists`
- `bool`
- `must`, `filter`, `should`, `must_not`
- Sorting
- Pagination
- Aggregations
- Nested queries
- Scripts
- Wildcard and regex queries
- Source filtering

**Goal:** Administrators must be able to read, explain, profile, and troubleshoot application queries even when application teams own the business search logic.

## Module 06 — Query Performance Engineering

- Query execution fundamentals
- Query vs filter context
- `must` vs `filter`
- Shard fan-out
- Result-size control
- Deep pagination
- `search_after`
- Point in Time (PIT)
- Scroll use cases and limitations
- `track_total_hits`
- `_source` filtering
- Wildcard and regex cost
- Script cost
- High-cardinality aggregations
- Date-range bounding
- Slow logs
- Profile API
- Task inspection
- Query concurrency

Core production model:

`Query complexity × data volume × shard fan-out × request rate × application concurrency = production search workload`

**Runbook:** Slow Search / Query Performance Investigation.

## Module 07 — Thread Pools, Concurrency & Backpressure

- Search and write thread pools
- Active, queue, rejected, and completed metrics
- HTTP 429
- Application concurrency
- Bounded retries
- Exponential backoff and jitter
- Backpressure
- Retry storms

**Lab:** Saturate search capacity, observe queue growth and rejections, then evaluate retry behavior.

**Runbook:** Search / Write Thread-Pool Rejection.

## Module 08 — JVM, Memory, CPU & Storage Performance

- JVM heap
- Filesystem cache
- Garbage collection
- Circuit breakers
- Memory pressure
- CPU saturation
- Disk utilization
- Storage latency
- IOPS and throughput
- Queue depth
- Disk watermarks
- Recovery I/O

**Runbooks:** High JVM Pressure; High CPU; Disk Pressure; Storage I/O Bottleneck.

## Module 09 — Monitoring & Production Troubleshooting

Operational APIs and evidence collection:

- `_cluster/health`
- `_cluster/state`
- `_cluster/allocation/explain`
- `_cat/nodes`
- `_cat/indices`
- `_cat/shards`
- `_cat/thread_pool`
- Node stats
- Index stats
- Tasks
- Hot threads
- Slow logs

Incident labs include RED/YELLOW health, unassigned shards, missing nodes, high CPU, JVM pressure, slow search, indexing latency, disk pressure, rejections, and recovery problems.

## Module 10 — Backup, Recovery, Maintenance & Upgrades

- Snapshot architecture
- Repository configuration
- Snapshot creation and validation
- Restore
- Partial restore
- Deleted-index recovery
- Rolling restart
- Node replacement
- Upgrade planning
- Validation and rollback

**Runbooks:** Snapshot Failure; Index Restore; Rolling Restart; Node Replacement; Version Upgrade.

## Module 11 — Capacity Planning & FinOps

Capacity decisions should consider:

- Current data
- Daily growth
- Retention
- Replica overhead
- Shard requirements
- Search workload
- Indexing workload
- Recovery capacity
- Safety headroom
- Compute and storage cost

Labs will include 3-, 6-, and 12-month forecasts and scale-up vs scale-out analysis.

**Runbook:** Elasticsearch Capacity Assessment.

## Module 12 — Automation & Production Incident Capstone

Automation areas:

- Cluster health checks
- Shard-size audits
- Mapping audits
- Index growth reports
- Thread-pool rejection reports
- Snapshot validation
- Capacity reporting
- Stale-index detection
- Incident evidence collection

### Capstone

Starting symptom: **P1 — application search requests are timing out.**

The learner must investigate application behavior, query design, index/shard layout, thread pools, CPU, JVM, storage, recovery activity, and cluster state, then produce:

- Evidence
- Root cause
- Immediate mitigation
- Permanent corrective action
- Capacity recommendation
- Monitoring improvements
- RCA

## Content Standards

Every tutorial should explain why the topic matters operationally and include production considerations. Every lab should be reproducible and include setup, validation, expected observations, failure conditions, and cleanup. Every runbook should include symptoms, safety notes, evidence collection, diagnosis, mitigation, permanent remediation, validation, rollback where applicable, monitoring, and escalation guidance.

Operational `curl` examples should assume authenticated production clusters and use placeholders such as `-u "$ES_USER:$ES_PASSWORD"` rather than embedding credentials.
