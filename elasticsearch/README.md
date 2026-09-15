# Elasticsearch

Production-oriented Elasticsearch learning for administrators, DBREs, and SREs, with supporting material for developers, application engineers, and data engineers.

## Learning Areas

### Tutorials
Core architecture, cluster administration, index management, mappings, shard design, query behavior, query performance, indexing performance, security, monitoring, capacity planning, backup/recovery, upgrades, and troubleshooting.

### Hands-on Labs
Reproducible exercises for cluster operations, index creation, custom settings and mappings, data ingestion, query analysis, slow logs, shard behavior, failure scenarios, recovery, and performance troubleshooting.

### Runbooks
Production procedures for health checks, disk pressure, unassigned shards, oversized shards, high CPU, heap pressure, slow searches, rejected requests, mapping issues, indexing failures, node failures, snapshots, recovery, upgrades, and capacity incidents.

### Use Cases
Realistic workflows such as application search, healthcare-style search datasets, Snowflake/Kafka-to-Elasticsearch ingestion, multi-index configuration-driven ingestion, operational search, and high-volume indexing/search scenarios.

## Administrator / DBRE / SRE Responsibility Areas

Mapping and query performance are included explicitly in this track. They are not only application concerns: poor mappings and inefficient queries can create excessive heap, CPU, disk I/O, shard pressure, thread-pool saturation, latency, and cluster-wide reliability problems.

The operations track therefore covers both governance and troubleshooting while application teams remain responsible for their business search requirements and query semantics.

## Master Roadmap

See [ROADMAP.md](ROADMAP.md) for the 12-module Elasticsearch Administrator / DBRE / SRE learning roadmap.

## Planned Structure

```text
elasticsearch/
├── tutorials/
├── hands-on-labs/
├── runbooks/
├── use-cases/
├── troubleshooting/
├── automation/
├── examples/
├── ROADMAP.md
└── README.md
```

## First Track

**Elasticsearch for Administrator / DBRE / SRE**

The track progresses from architecture and administration fundamentals into index/shard management, mapping governance, query performance, production operations, troubleshooting, capacity planning, automation, and realistic hands-on incidents.

## Next Tutorial

**Tutorial 01 — Elasticsearch Production Architecture for Administrator / DBRE / SRE**
