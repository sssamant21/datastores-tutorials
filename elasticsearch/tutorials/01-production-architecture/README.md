# Tutorial 01 — Elasticsearch Production Architecture for Administrator / DBRE / SRE

**Type:** Production Tutorial  
**Audience:** Elasticsearch Administrator / DBRE / SRE  
**Level:** Foundation → Production Operations  
**Status:** Revised Final / Canonical  
**Track:** Elasticsearch Administrator / DBRE / SRE

---

## 1. Purpose

Operating Elasticsearch in production requires more than knowing REST APIs. An Administrator, DBRE, or SRE needs to understand how application requests travel through the cluster, how documents are distributed, how shards interact with nodes, how Lucene stores and searches data, and how architecture decisions appear as CPU, JVM, storage, latency, recovery, and availability behavior.

This tutorial establishes that production mental model.

---

## 2. What Is Elasticsearch?

**Elasticsearch is a distributed search and analytics engine built on Apache Lucene.**

It stores data as JSON documents and distributes those documents across one or more nodes so that large datasets can be indexed, searched, filtered, aggregated, and analyzed efficiently. Elasticsearch exposes HTTP APIs that applications and operators use to index, retrieve, search, aggregate, and administer data.

At a high level:

```text
Data
 |
 v
JSON Documents
 |
 v
Elasticsearch
 |
 +------> Indices
 |          |
 |          +------> Shards
 |                     |
 |                     +------> Apache Lucene
 |
 +------> Distributed Search
 +------> Filtering
 +------> Aggregations
 +------> Near-Real-Time Search
```

### 2.1 Why Elasticsearch Exists

Elasticsearch is designed for search and analytics workloads such as full-text search, relevance-based search, filtering across large datasets, faceted navigation, aggregations, log and event search, operational search, and application search.

For example, a healthcare search application might search providers by specialty, location, network, provider identifier, organization, status, and free-text name. A logging platform might search timestamp, application, environment, error code, host, message, and trace identifier.

### 2.2 Elasticsearch and Apache Lucene

Elasticsearch builds its core search capabilities on **Apache Lucene**, a high-performance search library.

A useful mental model is:

```text
Application
     |
     v
Elasticsearch
     |
     +------ Distributed cluster management
     +------ REST APIs
     +------ Index and shard management
     +------ Replication and routing
     +------ Distributed search coordination
     |
     v
Apache Lucene
     |
     +------ Inverted indexes
     +------ Segments
     +------ Term dictionaries
     +------ Search execution
     +------ Scoring
```

Many Elasticsearch behaviors involving segments, refresh, merge, search, indexing, disk I/O, and filesystem cache make more sense once you understand that every Elasticsearch shard is backed by a Lucene index.

### 2.3 Elasticsearch Is a Distributed System

Elasticsearch is fundamentally distributed. Data and workload can be spread across multiple nodes, enabling horizontal scaling while introducing operational concerns such as shard placement, replication, node failure, cluster coordination, recovery, rebalancing, shard fan-out, and distributed query execution.

### 2.4 Elasticsearch Stores Documents

Elasticsearch primarily works with JSON documents.

```json
{
  "patient_id": "P10001",
  "status": "ACTIVE",
  "city": "Charlotte",
  "event_date": "2026-09-15"
}
```

A collection of related documents is stored in an **index**, for example `patients-v1`, `providers-v1`, or `claims-v1`.

Elasticsearch does not simply store JSON and scan every document for every search. During indexing, Lucene builds specialized search structures that make efficient search possible.

### 2.5 The Inverted Index

One foundational search structure is the **inverted index**. A simplified example is:

```text
Document 1: "Elasticsearch production cluster"
Document 2: "Elasticsearch query performance"
Document 3: "Production database performance"

Term              Documents
--------------------------------
elasticsearch     1, 2
production        1, 3
cluster           1
query             2
performance       2, 3
database          3
```

A search for `elasticsearch` can identify documents 1 and 2 without scanning every document from beginning to end. Real Lucene indexing and search are considerably more sophisticated, but this is the right foundational mental model.

### 2.6 Elasticsearch Is Near Real Time

Elasticsearch provides near-real-time search. A successfully acknowledged write is not necessarily visible to a normal search at the exact same instant. Search visibility is normally established by refresh behavior. We will distinguish write acknowledgement, refresh, search visibility, Lucene commit, and durability later in this tutorial.

### 2.7 Common Elasticsearch Use Cases

Common workloads include application search, product or entity search, operational log/event search, observability, aggregations and dashboards, and security investigation workloads. Architecture and sizing requirements can differ substantially between these workloads.

### 2.8 What Elasticsearch Is Not

Elasticsearch should not automatically be treated as a replacement for every relational or transactional database. In many architectures, PostgreSQL, MongoDB, Snowflake, object storage, or another datastore remains authoritative while Elasticsearch provides a derived search layer.

```text
Source / System of Record
          |
          v
     Data Pipeline
          |
          v
     Elasticsearch
          |
          v
  Search Application
```

DBRE/SRE must understand whether Elasticsearch is authoritative, a derived search index, or one component of a larger data pipeline because that distinction affects backup, recovery, reindexing, disaster recovery, retention, and incident response.

### 2.9 Administrator / DBRE / SRE View

A developer may reasonably see `Send JSON → Search JSON`. Operations needs the deeper model:

```text
Application
   |
REST API
   |
Query / Indexing Workload
   |
Index + Mapping
   |
Shards + Replicas
   |
Lucene + Segments
   |
CPU / JVM / Filesystem Cache / Storage
   |
Nodes
   |
Distributed Cluster
```

---

## 3. Learning Objectives

After completing this tutorial, you should be able to:

- Define Elasticsearch and explain its primary purpose.
- Explain Elasticsearch's relationship with Apache Lucene.
- Explain at a high level how an inverted index supports search.
- Explain why Elasticsearch is a distributed system.
- Identify common Elasticsearch use cases.
- Explain when Elasticsearch may operate as a search layer rather than a system of record.
- Explain clusters, nodes, indices, shards, replicas, Lucene indices, segments, and documents.
- Explain how Elasticsearch distributes data across nodes.
- Describe primary and replica shard responsibilities.
- Explain node and primary-shard failure behavior.
- Describe basic search and indexing request lifecycles.
- Explain near-real-time search.
- Explain why shard architecture, mapping, queries, and infrastructure affect production reliability.

---

## 4. Version and Deployment Scope

This tutorial teaches architectural concepts applicable across commonly deployed Elasticsearch versions. Some implementation details—including node roles, thread-pool defaults, configuration syntax, and available APIs—change between releases.

> Always verify version-sensitive configuration against official Elastic documentation for the exact Elasticsearch version running in your environment.

Unless stated otherwise, operational examples assume an authenticated cluster.

---

## 5. Elasticsearch from an SRE Perspective

An application may see `Application → Elasticsearch → Results`. A DBRE/SRE must see the layers underneath: nodes, shard copies, Lucene indices, segments, CPU, JVM, filesystem cache, storage, and distributed coordination.

When someone reports **“Elasticsearch is slow”**, the failing layer could involve application concurrency, query design, mapping design, index architecture, shard fan-out, shard size, thread pools, CPU, JVM/GC, filesystem cache, storage latency, IOPS, network, recovery, or cluster state.

---

## 6. Correct Cluster, Index, Node, and Shard Model

Avoid thinking of the hierarchy as `Cluster → Node → Index → Shard`. Indices are logical cluster-level objects; their shard copies are allocated across eligible nodes.

```text
Elasticsearch Cluster
│
├── Nodes
│   ├── Node 1
│   ├── Node 2
│   └── Node 3
│
└── Indices
    └── patients-v1
        ├── Primary shards
        └── Replica shards
```

A possible allocation for three primaries and one replica is:

```text
Node 1              Node 2              Node 3
------              ------              ------
P0                  P1                  P2
R1                  R2                  R0
```

Each Elasticsearch shard is a self-contained Lucene index containing a subset of the documents belonging to the Elasticsearch index.

---

## 7. Cluster and Cluster Health

**READ-ONLY / DIAGNOSTIC**

```bash
curl -u "$ES_USER:$ES_PASSWORD" \
  "https://<es-host>:9200/_cluster/health?pretty"
```

Health states:

```text
GREEN  All primary and replica shard copies are assigned.
YELLOW All primary shards are assigned, but one or more replicas are unassigned.
RED    One or more primary shards are unassigned; some data may be unavailable.
```

> **GREEN does not mean fast.**

A green cluster can still have high CPU, JVM pressure, GC pauses, storage saturation, disk latency, thread-pool saturation, slow queries, 429 responses, timeouts, or retry amplification. Cluster health primarily describes shard assignment and availability, not performance.

---

## 8. Nodes and Node Roles

Every running Elasticsearch instance is a node.

**READ-ONLY / DIAGNOSTIC**

```bash
curl -u "$ES_USER:$ES_PASSWORD" \
  "https://<es-host>:9200/_cat/nodes?v"
```

Modern releases support master, data and specialized data-tier roles, ingest, ML, remote-cluster, transform, voting-only, and coordinating behavior. Exact roles and defaults are version-sensitive; do not treat one release's role list as universal.

Every Elasticsearch node can coordinate requests. Dedicated coordinating-only nodes are a deployment choice, not a prerequisite for request coordination.

---

## 9. Master-Eligible and Data Nodes

Master-eligible nodes participate in cluster coordination and master election. The elected master coordinates cluster-state changes and responsibilities such as node membership, index and mapping metadata, aliases, templates, and shard-allocation decisions. It should not be thought of as the node through which all application data traffic must pass.

Data nodes hold shard data and execute data-intensive work including search, indexing, aggregations, recovery, segment activity, merges, and storage I/O. Production symptoms commonly include CPU pressure, heap/GC pressure, disk saturation, storage latency, thread-pool queues, rejected operations, long-running searches, and slow recovery.

---

## 10. Indices and Mappings

An index is a logical collection of related documents. It has settings, mappings, primary-shard count, replica count, and other index-level behavior.

**READ-ONLY / DIAGNOSTIC**

```bash
curl -u "$ES_USER:$ES_PASSWORD" \
  "https://<es-host>:9200/_cat/indices?v"
```

Example design:

```json
{
  "settings": {
    "number_of_shards": 3,
    "number_of_replicas": 1
  },
  "mappings": {
    "properties": {
      "patient_id": { "type": "keyword" },
      "name": { "type": "text" }
    }
  }
}
```

Index architecture and mapping architecture are both production concerns.

---

## 11. Primary Shards, Replica Shards, and Replication Groups

Primary shards partition an index's documents. If an index has three primaries, they can be represented as `P0`, `P1`, and `P2`. Every document belongs to one primary shard.

Replica shards are copies of primary shards. Elasticsearch does not allocate a replica to the same node as its primary. Replicas provide resilience and can provide additional capacity for read/search operations.

A primary shard and its replica copies form a replication group. Elasticsearch tracks shard copies considered in-sync; this state is important to write availability and failure handling.

---

## 12. Node Failure and Recovery

Given:

```text
Node 1              Node 2              Node 3
------              ------              ------
P0                  P1                  P2
R1                  R2                  R0
```

if Node 1 fails, `P0` and `R1` disappear from the active cluster. An eligible replica such as `R0` can be promoted to primary. Depending on allocation and recovery state, operators may observe a health transition such as `GREEN → YELLOW → recovery → GREEN`.

Elasticsearch may allocate, relocate, recover, rebalance, and promote shard copies as cluster conditions change.

---

## 13. Why Shard Count Matters

Too few shards can create very large shards, increasing recovery, relocation, rebalancing, maintenance, and failure-recovery cost. Too many shards create per-shard overhead, more metadata, more shard-level work, more coordination, and potentially excessive search fan-out.

> More shards are not automatically better.

Shard count is a workload and capacity-design decision.

---

## 14. Search Shard Fan-Out and Request Lifecycle

A broad search against an index with five logical primary shards may involve five shard-level searches; an index with fifty may involve fifty. For each relevant logical shard, Elasticsearch selects an eligible active copy, which can be a primary or replica. Current Elasticsearch uses adaptive replica selection by default when choosing among eligible copies.

```text
Search Request
      |
      v
Coordinating Node
      |
      v
Determine Relevant Logical Shards
      |
      v
Choose Eligible Active Copy
(primary or replica)
      |
      v
Shard-Level Search
      |
      v
Merge / Reduce
      |
      v
Response
```

Distributed search therefore has both shard-level execution cost and coordination cost.

---

## 15. Application Concurrency Changes the Workload

A query that performs well once may behave very differently under production concurrency. For example:

```text
8 application pods
× 4 workers
× 16 concurrent requests
= 512 potential concurrent application operations
```

A useful operational model is:

```text
Query Complexity
× Data Volume
× Shard Fan-Out
× Request Rate
× Application Concurrency
= Production Search Workload
```

---

## 16. Write Request Lifecycle

Elasticsearch uses a primary-backup replication model. A simplified write path is:

```text
Application
    |
Node receiving request
    |
Determine replication group using routing
    |
Current primary shard
    |
Validate and execute operation
    |
Forward to current in-sync replicas
    |
Required replication completes
    |
Acknowledge request
```

This is more accurate than treating writes simply as `Primary → Replica → ACK` because real failure handling depends on replication-group and in-sync-copy state.

---

## 17. Near-Real-Time Search, Refresh, and Visibility

A successful write acknowledgement does not necessarily mean the document is immediately visible to a normal search.

```text
Document indexed
      |
Indexing buffer
      |
Refresh
      |
New Lucene segment opened
      |
Document visible to search
```

The key distinction is:

```text
WRITE ACKNOWLEDGED
        ≠
SEARCHABLE
        ≠
LUCENE COMMIT
```

Refresh establishes search visibility; it should not be confused with a full Lucene commit or the complete durability model.

---

## 18. Lucene and Segments

Each Elasticsearch shard is backed by a Lucene index, and a Lucene index contains immutable segments. As indexing continues, new segments are created and background merging can combine smaller segments.

Indexing therefore involves document processing, analysis, indexing buffers, refresh, segment creation, replication, merging, filesystem cache, CPU, and storage I/O—not simply `JSON → disk`.

---

## 19. Mapping Is Part of Production Architecture

Different fields have different semantics. A reasonable design might use `keyword` for exact identifiers/status values and `text` for analyzed full-text content.

Poor mapping design can contribute to mapping explosion, unnecessary indexing, heap pressure, increased storage, expensive searches or aggregations, metadata growth, incorrect search behavior, and future reindexing requirements.

### Mapping ownership model

```text
Application / Data Team
        |
        +-- Business semantics
        +-- Search requirements
        +-- Data shape
        |
        v
Mapping / Query Design
        |
        v
DBRE / SRE Technical Review
        |
        +-- Mapping standards
        +-- Performance impact
        +-- Field growth
        +-- Cluster impact
        +-- Production guardrails
```

Current Elasticsearch uses `index.mapping.total_fields.limit` as one guardrail against excessive field growth. A documented default should never be treated as a design target; schema growth should be controlled intentionally.

For applicable field types, `doc_values` provide an on-disk column-oriented representation useful for sorting, aggregations, and scripting. Enabling fielddata on large `text` fields can consume significant heap; appropriate `keyword` or multi-field design is generally preferable when exact-value operations are needed.

---

## 20. Query Design Is an Operational Concern

An unbounded or unnecessarily broad query can have a very different operational cost from a bounded query. Important review dimensions include result size, date range, filtering, sorting, aggregations, scripts, wildcards, pagination, shard fan-out, and concurrency.

Application teams own business semantics; DBRE/SRE should still be able to read, profile, and diagnose production queries and establish technical guardrails.

---

## 21. Architecture Meets Infrastructure

Search and indexing ultimately consume CPU, memory, filesystem cache, storage IOPS/throughput, disk latency, and network capacity.

A storage bottleneck can propagate as:

```text
Search workload
      |
Disk requests increase
      |
Storage saturation
      |
Queue depth increases
      |
Disk latency increases
      |
Searches take longer
      |
Threads remain busy longer
      |
Thread queue grows
      |
Rejections / timeouts
```

An application may report an Elasticsearch timeout while the underlying bottleneck is storage latency.

---

## 22. Thread Pools and Backpressure

For early troubleshooting, focus on operational signals rather than memorizing version-specific pool sizes:

```text
active
queue
rejected
completed
```

A common saturation path is `request rate ↑ → active threads ↑ → queue ↑ → queue capacity exhausted → rejected operations → HTTP 429`.

Immediate uncontrolled retries can amplify overload. Production clients should use bounded retries and appropriate backoff/jitter where retry behavior is safe.

---

## 23. Essential Production Diagnostic APIs

The following are **READ-ONLY / DIAGNOSTIC** examples.

```bash
# Cluster health
curl -u "$ES_USER:$ES_PASSWORD" \
  "https://<es-host>:9200/_cluster/health?pretty"

# Nodes
curl -u "$ES_USER:$ES_PASSWORD" \
  "https://<es-host>:9200/_cat/nodes?v"

# Indices
curl -u "$ES_USER:$ES_PASSWORD" \
  "https://<es-host>:9200/_cat/indices?v"

# Shards
curl -u "$ES_USER:$ES_PASSWORD" \
  "https://<es-host>:9200/_cat/shards?v"

# Thread pools
curl -u "$ES_USER:$ES_PASSWORD" \
  "https://<es-host>:9200/_cat/thread_pool?v&h=node_name,name,active,queue,rejected,completed"

# Node statistics
curl -u "$ES_USER:$ES_PASSWORD" \
  "https://<es-host>:9200/_nodes/stats?pretty"

# Hot threads
curl -u "$ES_USER:$ES_PASSWORD" \
  "https://<es-host>:9200/_nodes/hot_threads"

# Search tasks
curl -u "$ES_USER:$ES_PASSWORD" \
  "https://<es-host>:9200/_tasks?detailed=true&actions=*search"

# Allocation explanation
curl -u "$ES_USER:$ES_PASSWORD" \
  "https://<es-host>:9200/_cluster/allocation/explain?pretty"
```

The goal is not mechanical memorization. Later labs will teach `Symptom → Question → Correct API → Evidence → Diagnosis`.

---

## 24. Production Command and Credential Safety

Throughout this repository, commands should be understood as either **READ-ONLY / DIAGNOSTIC** or **STATE-CHANGING**. State-changing commands require additional review, validation, and rollback planning where applicable.

Never commit real passwords, API keys, certificates, private keys, tokens, customer hostnames, or sensitive endpoints. Use placeholders and environment variables such as `$ES_USER`, `$ES_PASSWORD`, and `$ES_HOST`, and follow organizational secret-management and shell-history controls.

---

## 25. Production Incident Mental Model

Do not jump directly from an incident to **“add more nodes.”** Investigate systematically:

```text
INCIDENT
   |
Application
   |
Query / Indexing
   |
Mapping / Index
   |
Shards
   |
Thread Pools
   |
CPU / JVM / Storage
   |
Nodes
   |
Cluster
```

The purpose is to eliminate hypotheses with evidence and identify the actual bottleneck.

---

## 26. Two Core Mental Models

### Data architecture

```text
Document
  → Mapping
  → Index
  → Logical Shard
  → Shard Copy
  → Lucene Index
  → Segments
  → Node
  → Cluster
```

### Workload propagation

```text
Application
  → Query / Indexing Request
  → Concurrency
  → Shard Fan-Out
  → Thread Pools
  → CPU / JVM / Storage
  → Latency / Queueing
  → Rejections / Timeouts
```

Together these form the foundation for production Elasticsearch troubleshooting.

---

## 27. Administrator / DBRE / SRE Responsibilities

Operations engineers should understand enough of each layer to connect symptoms to causes:

- **Cluster:** health, nodes, master election, cluster state, allocation, recovery.
- **Index/shards:** primary and replica counts, sizing, distribution, routing, recovery impact.
- **Mapping:** field types, dynamic mapping, mapping growth, `text` vs `keyword`, object vs nested, doc values, fielddata risk, reindex implications.
- **Queries:** structure, filtering, result size, pagination, aggregations, scripts, wildcards, fan-out, concurrency.
- **Infrastructure:** CPU, memory, JVM, GC, filesystem cache, storage latency, IOPS, throughput, network.
- **Application interaction:** request rate, concurrency, retries, timeouts, backoff, bulk and pagination behavior.

This does not mean DBRE owns every business field or query. It means DBRE/SRE understands enough to protect the production platform.

---

## 28. Production Troubleshooting Principle

A mature investigation follows:

```text
Symptom
  → Collect Evidence
  → Build Hypotheses
  → Test Hypotheses
  → Identify Bottleneck
  → Immediate Mitigation
  → Permanent Remediation
  → Validate
  → Prevent Recurrence
```

Avoid `Symptom → Guess → Change production`.

---

## 29. Tutorial Summary

1. Elasticsearch is a distributed search and analytics engine built on Apache Lucene.
2. It stores JSON documents and builds specialized search structures such as inverted indexes.
3. Elasticsearch is commonly used for application search, operational search, analytics, and related workloads.
4. It may be authoritative in some designs, but is often a derived search layer fed from another system of record.
5. Indices are logical cluster-level structures whose shard copies are distributed across nodes.
6. Each shard is a self-contained Lucene index.
7. Primary shards partition an index's documents; replicas provide resilience and read capacity.
8. Searches may execute against eligible primary or replica copies.
9. Distributed search introduces shard-level execution and coordination cost.
10. Writes use a primary-backup replication model.
11. Search visibility is near real time; acknowledgement, refresh/search visibility, and Lucene commit are distinct concepts.
12. Shard count and size are production architecture decisions.
13. Mapping design, query design, and application concurrency can directly affect reliability.
14. Thread-pool rejection is usually a symptom requiring evidence-driven root-cause analysis.
15. Infrastructure performance—especially CPU, JVM, memory, and storage—directly affects Elasticsearch behavior.
16. GREEN cluster health does not prove acceptable performance.
17. Production troubleshooting should be evidence-driven rather than assumption-driven.

---

## 30. Knowledge Check

1. What is Elasticsearch and what is its relationship to Apache Lucene?
2. What is an inverted index at a high level?
3. What is the difference between an Elasticsearch index and a shard?
4. Why can a replica not be allocated to the same node as its primary?
5. Can a search execute against a replica shard?
6. What happens when a primary fails but an eligible replica exists?
7. Why can a green cluster still have severe performance problems?
8. Why can excessive shard counts affect search performance?
9. Why can very large shards affect recovery?
10. What is the difference between write acknowledgement and search visibility?
11. What does refresh do?
12. Why is mapping design an operational concern?
13. Why should DBRE/SRE understand application queries?
14. How can storage latency result in search-thread saturation?
15. Why can immediate retries after HTTP 429 worsen an incident?
16. What evidence would you collect before recommending additional nodes?
17. Why does it matter whether Elasticsearch is the system of record or a derived search index?

---

## 31. Production Safety Notes

Before running commands against production:

- Confirm the target cluster and environment.
- Confirm authentication and authorization.
- Never paste real credentials into repository files.
- Review commands before execution.
- Distinguish diagnostic commands from state-changing commands.
- Capture evidence before changing configuration during an incident.
- Follow organizational change-management procedures.
- Validate Elasticsearch-version compatibility.
- Sanitize customer and production identifiers before using incident evidence publicly.

---

## 32. Official References

Technical behavior in this tutorial was validated against official Elastic documentation covering distributed architecture, clusters/nodes/shards, node roles, reading and writing documents, search shard routing, adaptive replica selection, near-real-time search, mapping, mapping explosion, thread pools, rejected requests, shard allocation, relocation, and recovery.

Primary references:

- Elastic Docs — Elasticsearch distributed architecture: https://www.elastic.co/docs/deploy-manage/distributed-architecture/clusters-nodes-shards
- Elastic Docs — Reading and writing documents: https://www.elastic.co/docs/deploy-manage/distributed-architecture/reading-and-writing-documents
- Elastic Docs — Near real-time search: https://www.elastic.co/docs/manage-data/data-store/near-real-time-search
- Elastic Docs — Node settings and roles: https://www.elastic.co/docs/reference/elasticsearch/configuration-reference/node-settings
- Elastic Docs — Search shard routing: https://www.elastic.co/docs/reference/elasticsearch/rest-apis/search-shard-routing
- Elastic Docs — Mapping explosion: https://www.elastic.co/docs/troubleshoot/elasticsearch/mapping-explosion
- Elastic Docs — Thread pool settings: https://www.elastic.co/docs/reference/elasticsearch/configuration-reference/thread-pool-settings
- Elastic Docs — Rejected requests: https://www.elastic.co/docs/troubleshoot/elasticsearch/rejected-requests

The explanatory text, diagrams, operational models, examples, and learning structure in this tutorial are independently authored for this repository.

---

## 33. Next Practical Stage

**Hands-On Lab 01 — Build and Operate a Multi-Node Elasticsearch Cluster**

The lab will build a multi-node cluster, configure authentication safely, create an index with explicit settings and mapping, load sample data, inspect primary/replica placement, execute searches, stop a node, observe health changes and replica promotion/recovery, restore the node, and verify cluster recovery.

The objective is not merely to make Elasticsearch run. The objective is to **observe how the architecture behaves when something fails**.
