# Module 03 — Index, Shard & Replica Administration

## Tutorial 03 — Index, Shard & Replica Administration

**Edition:** Revised Final / Canonical
**Audience:** Elasticsearch administrators, SREs, DBREs, platform engineers, developers, and data engineers
**Lab index:** `sre_tutorial_03`

---

## 3.1 Introduction

An Elasticsearch index is a logical collection of documents, but Elasticsearch does not store the entire index as one indivisible object.

Instead, Elasticsearch divides an index into **shards**.

Those shards are distributed across eligible cluster nodes, allowing Elasticsearch to distribute storage and processing while supporting recovery and availability.

Understanding this relationship is fundamental:

```text
Index
  ↓
Primary shards
  ↓
Replica copies
  ↓
Nodes
  ↓
Shard allocation
  ↓
Cluster health
```

A cluster can report `green` health and still have poor shard architecture, oversized shards, excessive shard counts, disk pressure, hot spotting, or recovery risk.

For an administrator, shard management is therefore not simply about keeping the cluster green. It is about designing and operating a topology that can support the workload **and recover safely when infrastructure fails**.

---

# 3.2 Learning Objectives

After completing this tutorial, you should be able to:

* explain the relationship between an index, primary shard, replica shard, and node;
* understand a shard replication group;
* create an index with explicit shard and replica settings;
* distinguish static and dynamic index settings;
* calculate total desired shard copies;
* understand the document-routing model;
* understand the primary-to-replica write path;
* understand how primary and replica copies participate in reads;
* inspect shard placement;
* change replica counts safely;
* interpret common shard states;
* understand `green`, `yellow`, and `red` cluster health;
* diagnose unassigned shards;
* use the Cluster Allocation Explain API;
* recognize oversized and excessively small-shard designs;
* understand why shard sizing affects recovery;
* distinguish diagnostic commands from state-changing and destructive operations;
* safely clean up the tutorial environment.

---

# 3.3 Tutorial Safety Classification

Commands in this tutorial use four operational classifications.

### `[TUTORIAL-ACCEPTANCE — SAFE-READ]`

Used for read-only inspection and validation.

Examples:

```text
GET /_cluster/health
GET /_cat/indices
GET /_cat/shards
GET /_cat/nodes
GET /_cat/allocation
GET /<index>/_settings
GET /_cluster/allocation/explain
```

---

### `[TUTORIAL-LAB — CONTROLLED-WRITE]`

Creates or modifies resources belonging specifically to this tutorial.

Examples:

```text
PUT /sre_tutorial_03
POST /sre_tutorial_03/_doc/1
PUT /sre_tutorial_03/_settings
POST /sre_tutorial_03/_refresh
```

---

### `[TUTORIAL-LAB — DESTRUCTIVE]`

Deletes a dedicated tutorial resource.

Example:

```text
DELETE /sre_tutorial_03
```

The exact target must be verified before execution.

---

### `[PRODUCTION-RECOVERY — HIGH-RISK]`

Operations capable of causing significant service or data consequences.

Examples include manual rerouting and forced primary recovery.

These operations are **not executed in this tutorial**.

---

# 3.4 Lab Safety Boundary

All write and delete operations in this tutorial must target:

```text
sre_tutorial_03
```

Do not substitute an existing production index.

Avoid destructive wildcard commands such as:

```text
DELETE /*
DELETE /prod-*
DELETE /logs-*
```

Tutorial cleanup always uses the exact lab index name.

---

# 3.5 Authentication

The examples assume authentication information is supplied securely through:

```text
ES_URL
ES_USER
ES_PASSWORD
```

Commands therefore use:

```bash
curl -u "$ES_USER:$ES_PASSWORD"
```

rather than embedding credentials directly into the tutorial.

Do not commit Elasticsearch usernames, passwords, API keys, or other credentials into source repositories, CI configuration, screenshots, documentation, or incident records.

---

# 3.6 Index → Shards → Nodes

Consider an index configured with:

```text
number_of_shards   = 3
number_of_replicas = 1
```

Conceptually:

```text
                    INDEX
                      |
          +-----------+-----------+
          |           |           |
          v           v           v
       Shard 0     Shard 1     Shard 2
          |           |           |
      +---+---+   +---+---+   +---+---+
      |       |   |       |   |       |
      P0      R0  P1      R1  P2      R2
```

`P` represents a primary copy.

`R` represents a replica copy.

The desired number of shard copies is:

```text
Total shard copies =
number_of_shards × (1 + number_of_replicas)
```

Therefore:

```text
3 × (1 + 1)
=
6 shard copies
```

An important distinction is:

```text
number_of_replicas
```

means the number of replicas **for each primary shard**, not the total number of replicas for the index.

---

# 3.7 Replication Groups

Each shard has a replication group.

For example:

```text
Shard 0 replication group

        P0
       /  \
     R0    R0
```

One copy acts as the current primary, while other eligible copies act as replicas.

Every document belongs to one primary shard.

Writes are routed to the appropriate replication group and processed through its current primary before being replicated to the appropriate in-sync replica copies.

This primary-backup model is central to Elasticsearch's distributed architecture.

---

# 3.8 Why Elasticsearch Uses Shards

Imagine an index containing hundreds of millions of documents.

Without sharding, the entire index would effectively be tied to one indivisible storage and processing unit.

Sharding allows Elasticsearch to distribute the index:

```text
                  INDEX
                    |
          +---------+---------+
          |         |         |
          v         v         v
       Shard 0   Shard 1   Shard 2
          |         |         |
          v         v         v
        Node A    Node B    Node C
```

This supports capabilities such as:

* distributed storage;
* horizontal scaling;
* parallel search execution;
* distributed indexing;
* shard recovery;
* relocation;
* rebalancing.

However:

```text
More shards ≠ automatically better
```

Every shard introduces operational overhead.

Shard topology is therefore a **capacity and architecture decision**.

---

# 3.9 Primary Shards

Suppose:

```text
number_of_shards = 3
```

Elasticsearch creates three primary shards:

```text
P0
P1
P2
```

Documents are routed to one of those shards.

Conceptually:

```text
Document
   |
   v
Routing
   |
   +----> Shard 0
   |
   +----> Shard 1
   |
   +----> Shard 2
```

`index.number_of_shards` is a **static index setting**.

You cannot convert an ordinary existing three-primary index into six primaries simply by running:

```http
PUT /existing-index/_settings
{
  "index.number_of_shards": 6
}
```

Changing primary-shard topology requires an appropriate design and migration strategy.

Depending on the situation, that might involve:

```text
Reindex
Split
Shrink
Rollover/new-index design
Data migration
```

The appropriate method depends on the actual requirement.

---

# 3.10 Replica Shards

Replica shards provide additional copies of primary shards.

For example:

```text
P0 ───── R0
P1 ───── R1
P2 ───── R2
```

Replicas contribute to availability because an eligible in-sync replica can be promoted if the current primary copy becomes unavailable.

Replica copies can also participate in reads.

However, replicas consume resources:

```text
Disk
CPU
Memory
Network bandwidth
Recovery bandwidth
Shard overhead
```

Increasing replicas is therefore not operationally free.

---

# 3.11 Primary and Replica Placement

Elasticsearch does not place a replica copy on the same node as another copy of the same shard.

A three-node topology might look like:

```text
Node A
  P0
  R1

Node B
  P1
  R2

Node C
  P2
  R0
```

If Node A disappears, another copy of shard `0` still exists on Node C.

This separation provides useful redundancy.

---

# 3.12 Automatic Shard Allocation

Administrators normally do not manually select the node for every shard.

Elasticsearch's allocation system handles:

```text
Allocation
Recovery
Relocation
Rebalancing
```

based on node eligibility, allocation rules, cluster conditions, and other allocation decisions.

Conceptually:

```text
Administrator
      |
      | architecture / constraints
      v
Elasticsearch allocation system
      |
      +--> Allocate
      +--> Recover
      +--> Relocate
      +--> Rebalance
```

Normal administration should generally allow Elasticsearch's allocator to perform its job unless there is a specific reason to intervene.

---

# 3.13 Document Routing

When a document is indexed, Elasticsearch must determine which shard owns it.

Conceptually:

```text
Document
   |
   | _id / routing value
   v
Routing calculation
   |
   v
Target shard
```

By default, routing is derived from the document's routing value, normally its `_id`.

Custom routing can deliberately control shard placement.

However, custom routing is an architecture decision.

Poor routing-key cardinality or heavily skewed routing can concentrate documents and requests onto only a subset of shards, producing **hot shards**.

---

# 3.14 Write Path

Consider an indexing request.

Conceptually:

```text
Client
   |
   v
Coordinating node
   |
   v
Determine target shard
   |
   v
Current primary
   |
   +---- Execute operation
   |
   +---- Replicate
             |
        +----+----+
        |         |
        v         v
     Replica   Replica
```

The operation is routed to the appropriate replication group.

The primary processes the operation and forwards it to the appropriate in-sync replica copies.

This is important when troubleshooting:

* write failures;
* replication failures;
* unavailable shard copies;
* write latency;
* recovery conditions.

Replica shards are therefore more than passive backup files.

---

# 3.15 Read Path

Reads may be served from active primary or replica shard copies.

Conceptually:

```text
SEARCH
   |
   v
Coordinating node
   |
   +----> Shard 0 active copy
   |
   +----> Shard 1 active copy
   |
   +----> Shard 2 active copy
   |
   v
Merge results
   |
   v
Client
```

Elasticsearch can use adaptive replica selection when choosing among available shard copies.

This helps explain why replicas can contribute additional search-serving capacity.

---

# 3.16 Check Cluster Health

`[TUTORIAL-ACCEPTANCE — SAFE-READ]`

Before creating anything, inspect cluster health:

```bash
curl -u "$ES_USER:$ES_PASSWORD" \
  "$ES_URL/_cluster/health?pretty"
```

Important fields include:

```text
status
number_of_nodes
number_of_data_nodes
active_primary_shards
active_shards
relocating_shards
initializing_shards
unassigned_shards
```

---

# 3.17 Understanding Cluster Health

### GREEN

All required primary and replica shard copies are allocated.

### YELLOW

All primary shards are allocated, but one or more replica shards are unassigned.

The affected data may remain available, but redundancy may be reduced.

### RED

At least one primary shard is unassigned.

Data associated with affected primary shards may be unavailable, and affected operations can fail.

Important:

```text
Cluster health = GREEN
```

does **not** mean:

```text
Cluster architecture = healthy
```

A green cluster can still experience:

```text
Oversized shards
Too many shards
Disk pressure
CPU saturation
Search latency
Indexing pressure
Hot spotting
Poor mappings
Expensive queries
Slow recovery characteristics
```

Cluster-health color primarily describes shard-allocation health.

---

# 3.18 Create the Tutorial Index

`[TUTORIAL-LAB — CONTROLLED-WRITE]`

Create:

```bash
curl -u "$ES_USER:$ES_PASSWORD" \
  -X PUT "$ES_URL/sre_tutorial_03" \
  -H 'Content-Type: application/json' \
  -d '{
    "settings": {
      "number_of_shards": 3,
      "number_of_replicas": 1
    }
  }'
```

We requested:

```text
Primary shards       = 3
Replicas per primary = 1
```

Desired shard copies:

```text
3 × (1 + 1)
=
6
```

---

# 3.19 Inspect the Index

`[TUTORIAL-ACCEPTANCE — SAFE-READ]`

```bash
curl -u "$ES_USER:$ES_PASSWORD" \
  "$ES_URL/_cat/indices/sre_tutorial_03?v"
```

Typical fields:

```text
health
status
index
pri
rep
docs.count
store.size
```

Here:

```text
pri = primary shard count
rep = replicas per primary
```

---

# 3.20 CAT API Operational Note

CAT APIs such as:

```text
_cat/indices
_cat/shards
_cat/nodes
_cat/allocation
```

are useful for human-readable operational inspection.

Application monitoring and automation should generally prefer structured JSON APIs instead of building dependencies around formatted CAT output.

---

# 3.21 Inspect Index Settings

`[TUTORIAL-ACCEPTANCE — SAFE-READ]`

```bash
curl -u "$ES_USER:$ES_PASSWORD" \
  "$ES_URL/sre_tutorial_03/_settings?pretty"
```

Verify:

```json
"number_of_shards": "3",
"number_of_replicas": "1"
```

Remember:

```text
number_of_shards
       ↓
STATIC

number_of_replicas
       ↓
DYNAMIC
```

---

# 3.22 Inspect Individual Shards

`[TUTORIAL-ACCEPTANCE — SAFE-READ]`

```bash
curl -u "$ES_USER:$ES_PASSWORD" \
  "$ES_URL/_cat/shards/sre_tutorial_03?v"
```

A healthy three-node example might resemble:

```text
index           shard prirep state   node
sre_tutorial_03 0     p      STARTED node-a
sre_tutorial_03 0     r      STARTED node-c
sre_tutorial_03 1     p      STARTED node-b
sre_tutorial_03 1     r      STARTED node-a
sre_tutorial_03 2     p      STARTED node-c
sre_tutorial_03 2     r      STARTED node-b
```

Here:

```text
p = primary
r = replica
```

---

# 3.23 Important Shard States

### `STARTED`

The shard is allocated and operational.

### `INITIALIZING`

The shard is being initialized.

This can occur during creation, recovery, or replica initialization.

### `RELOCATING`

The shard is moving from one node to another.

Possible reasons include:

* rebalancing;
* node addition/removal;
* allocation changes;
* maintenance;
* recovery activity.

### `UNASSIGNED`

The shard currently has no assigned eligible node.

An unassigned primary deserves particularly careful investigation because affected data may be unavailable.

---

# 3.24 Index Sample Documents

`[TUTORIAL-LAB — CONTROLLED-WRITE]`

```bash
curl -u "$ES_USER:$ES_PASSWORD" \
  -X POST "$ES_URL/sre_tutorial_03/_doc/1" \
  -H 'Content-Type: application/json' \
  -d '{
    "patient_id": "P1001",
    "event_type": "visit",
    "event_date": "2026-09-16"
  }'
```

Add another:

```bash
curl -u "$ES_USER:$ES_PASSWORD" \
  -X POST "$ES_URL/sre_tutorial_03/_doc/2" \
  -H 'Content-Type: application/json' \
  -d '{
    "patient_id": "P1002",
    "event_type": "claim",
    "event_date": "2026-09-16"
  }'
```

---

# 3.25 Lab-Only Explicit Refresh

`[TUTORIAL-LAB — CONTROLLED-WRITE]`

For this small lab only, force a refresh so the documents become immediately searchable during the next exercise:

```bash
curl -u "$ES_USER:$ES_PASSWORD" \
  -X POST "$ES_URL/sre_tutorial_03/_refresh"
```

This is a teaching convenience.

Do **not** routinely force explicit refreshes in production ingestion pipelines. Explicit refresh operations have a cost; production applications should normally rely on Elasticsearch's refresh behavior or deliberately use appropriate visibility semantics when immediate search visibility is required.

---

# 3.26 Inspect Document Distribution

`[TUTORIAL-ACCEPTANCE — SAFE-READ]`

```bash
curl -u "$ES_USER:$ES_PASSWORD" \
  "$ES_URL/_cat/shards/sre_tutorial_03?v"
```

Documents will be distributed according to Elasticsearch routing.

Do not expect every shard to contain an equal number of documents in this tiny two-document lab.

---

# 3.27 Change the Replica Count

`[TUTORIAL-LAB — CONTROLLED-WRITE]`

Change:

```text
1 replica
```

to:

```text
2 replicas
```

```bash
curl -u "$ES_USER:$ES_PASSWORD" \
  -X PUT "$ES_URL/sre_tutorial_03/_settings" \
  -H 'Content-Type: application/json' \
  -d '{
    "index": {
      "number_of_replicas": 2
    }
  }'
```

The desired shard-copy count becomes:

```text
3 × (1 + 2)
=
9 shard copies
```

---

# 3.28 Dynamic Does Not Mean Free

`number_of_replicas` can be changed dynamically.

But:

```text
Dynamic ≠ operationally free
```

Before increasing replica counts in production, evaluate:

```text
Eligible data nodes
Available disk capacity
Shard sizes
Total shard count
Recovery traffic
Network capacity
CPU
Heap
Indexing workload
Search workload
Allocation awareness
Failure-domain topology
```

Increasing a large index from one replica to two can require approximately another logical copy of its shard data to be allocated across the cluster.

That can generate substantial:

```text
Disk consumption
Network transfer
Recovery activity
I/O
CPU work
```

Replica changes should therefore be treated as capacity changes.

---

# 3.29 Node Count Matters

Suppose:

```text
number_of_shards   = 3
number_of_replicas = 2
```

Each replication group requires:

```text
1 primary
+
2 replicas
=
3 copies
```

Now suppose there are only two eligible data nodes.

Elasticsearch can place:

```text
Node A → P0
Node B → R0
```

but cannot place another `R0` on either node without colocating copies of the same shard.

The result may therefore be:

```text
P0 STARTED
R0 STARTED
R0 UNASSIGNED
```

and the index can remain:

```text
YELLOW
```

This does not automatically indicate an Elasticsearch defect.

The requested topology cannot currently be satisfied.

---

# 3.30 Diagnose an Unassigned Shard

Start with observation.

`[TUTORIAL-ACCEPTANCE — SAFE-READ]`

```bash
curl -u "$ES_USER:$ES_PASSWORD" \
  "$ES_URL/_cat/shards/sre_tutorial_03?v"
```

Look for:

```text
UNASSIGNED
```

Then ask Elasticsearch why allocation cannot occur.

```bash
curl -u "$ES_USER:$ES_PASSWORD" \
  "$ES_URL/_cluster/allocation/explain?pretty"
```

Potential causes include:

```text
Insufficient eligible nodes
Allocation filtering
Disk allocation thresholds
Node-role eligibility
Allocation awareness
Allocation disabled
Recovery conditions
Maximum retry conditions
```

This is not an exhaustive list.

---

# 3.31 Explain a Specific Shard

`[TUTORIAL-ACCEPTANCE — SAFE-READ]`

```bash
curl -u "$ES_USER:$ES_PASSWORD" \
  -X GET "$ES_URL/_cluster/allocation/explain?pretty" \
  -H 'Content-Type: application/json' \
  -d '{
    "index": "sre_tutorial_03",
    "shard": 0,
    "primary": false
  }'
```

Conceptually, we are asking:

```text
Why can't replica shard 0
of sre_tutorial_03
be allocated?
```

This is much safer than guessing and immediately changing cluster allocation settings.

---

# 3.32 Production Troubleshooting Workflow

When an alert reports:

```text
Elasticsearch cluster health = YELLOW
```

do not immediately change cluster configuration.

Use:

```text
1. Check cluster health
        |
        v
2. Identify affected shards
        |
        v
3. Determine primary vs replica
        |
        v
4. Run allocation explain
        |
        v
5. Check whether recovery/relocation
   is already progressing normally
        |
        +---- YES ---> Monitor
        |
        +---- NO
               |
               v
6. Inspect allocation constraints
        |
        v
7. Determine root cause
        |
        v
8. Select controlled remediation
        |
        v
9. Monitor recovery
```

The core principle is:

> Diagnose the allocation decision before changing the allocation configuration.

---

# 3.33 Useful Investigation Commands

`[TUTORIAL-ACCEPTANCE — SAFE-READ]`

Cluster health:

```bash
curl -u "$ES_USER:$ES_PASSWORD" \
  "$ES_URL/_cluster/health?pretty"
```

Shard inventory:

```bash
curl -u "$ES_USER:$ES_PASSWORD" \
  "$ES_URL/_cat/shards?v&s=state,index,shard"
```

Allocation overview:

```bash
curl -u "$ES_USER:$ES_PASSWORD" \
  "$ES_URL/_cat/allocation?v"
```

Node inventory:

```bash
curl -u "$ES_USER:$ES_PASSWORD" \
  "$ES_URL/_cat/nodes?v"
```

Allocation explanation:

```bash
curl -u "$ES_USER:$ES_PASSWORD" \
  "$ES_URL/_cluster/allocation/explain?pretty"
```

---

# 3.34 Restore the Lab Replica Count

`[TUTORIAL-LAB — CONTROLLED-WRITE]`

Return the index to:

```text
number_of_replicas = 1
```

```bash
curl -u "$ES_USER:$ES_PASSWORD" \
  -X PUT "$ES_URL/sre_tutorial_03/_settings" \
  -H 'Content-Type: application/json' \
  -d '{
    "index": {
      "number_of_replicas": 1
    }
  }'
```

Monitor:

```bash
curl -u "$ES_USER:$ES_PASSWORD" \
  "$ES_URL/_cluster/health/sre_tutorial_03?wait_for_status=green&timeout=30s&pretty"
```

If sufficient eligible nodes exist and no other allocation constraints apply, the index should be able to return to green.

---

# 3.35 Shard Sizing

Shard size has no single universal value that is correct for every workload.

As general starting guidance, Elastic commonly recommends shard sizes in approximately the:

```text
10 GB – 50 GB
```

range for many workloads and keeping shard document counts below roughly:

```text
200 million documents per shard
```

These are **guidelines, not universal limits or SLOs**.

Production sizing should consider:

```text
Workload characteristics
Query patterns
Indexing throughput
Document size
Hardware
Storage performance
Recovery objectives
Relocation requirements
Data growth
Operational maintenance
```

Benchmarking against a representative production workload remains important.

---

# 3.36 Oversized-Shard Example

Consider:

```text
Index size       = 1.9 TB
Primary shards   = 6
Replicas         = 1
```

A rough average primary-shard size is:

```text
1.9 TB / 6
≈
317 GB per primary
```

That does not prove that Elasticsearch cannot operate the index.

However, it should trigger a **shard-sizing and recovery-risk review**.

Large shards can make operations such as:

```text
Recovery
Relocation
Node replacement
Rolling maintenance
Failure recovery
Snapshot/restore workflows
```

more expensive and potentially slower.

---

# 3.37 Recovery-Time Thinking

Shard sizing is not only about query performance.

An administrator should ask:

```text
If this node disappears right now,
how long will these shards take to recover?
```

Recovery may require shard data to be:

```text
Copied
Transferred
Recovered
Validated
Reallocated
Made available
```

over real network and storage infrastructure.

Therefore:

```text
Shard sizing
     =
Performance
+
Recovery
+
Relocation
+
Maintenance
+
Failure handling
```

This is why very large shards can create operational risk even when normal searches appear healthy.

---

# 3.38 Too Many Small Shards

The opposite problem also matters.

Imagine:

```text
2,000 indices
×
20 primary shards
×
2 total copies
```

This represents approximately:

```text
80,000 shard copies
```

before considering additional indices.

Every shard introduces overhead.

Large numbers of very small shards can increase:

```text
Cluster-management overhead
Heap/resource consumption
Search coordination
Recovery complexity
File/resource overhead
Operational complexity
```

Therefore:

```text
Too few / oversized shards
             |
             v
Expensive recovery
Concentrated workload


Too many / tiny shards
             |
             v
Excessive shard-management overhead
```

Good shard administration is about selecting an appropriate topology for the workload.

---

# 3.39 Should We Add More Primary Shards?

Do not automatically conclude:

```text
Large index
   ↓
Add more shards
```

Instead:

```text
Need more primary shards?
        |
        v
Why?
        |
        +--> Shards too large?
        |
        +--> Indexing bottleneck?
        |
        +--> Recovery too slow?
        |
        +--> Expected growth?
        |
        +--> Routing hotspot?
        |
        v
Measure workload
        |
        v
Choose appropriate architecture
```

Possible solutions might include:

```text
Reindexing
Split
Rollover
New-index design
Routing correction
Lifecycle changes
Query optimization
Additional infrastructure
```

depending on the actual problem.

---

# 3.40 High-Risk Allocation Operations

`[PRODUCTION-RECOVERY — HIGH-RISK]`

Operations involving concepts such as:

```text
_cluster/reroute
allocate_stale_primary
allocate_empty_primary
allocation.enable changes
allocation filtering changes
```

are intentionally **not performed in this tutorial**.

Some forced-primary recovery operations can introduce data-loss scenarios.

Do not execute them simply because:

```text
Cluster health = RED
```

or:

```text
Cluster health = YELLOW
```

Instead:

```text
Observe
   ↓
Explain
   ↓
Understand
   ↓
Select remediation
```

Forced allocation belongs in a dedicated disaster-recovery procedure with explicit validation, impact analysis, authorization, and recovery planning.

---

# 3.41 Production Incident Challenge

Assume:

```text
Cluster health = YELLOW

Data nodes = 3

Index:
  primary shards = 18
  replicas       = 1

Observation:
  2 replica shards are UNASSIGNED
```

A poor response would be:

```text
"Cluster is yellow.
Add nodes or run reroute."
```

There is not enough evidence yet to justify either action.

Instead:

```text
_cluster/health
       |
       v
_cat/shards
       |
       v
Identify affected replicas
       |
       v
_cluster/allocation/explain
       |
       v
Read allocation decisions
       |
       v
Check:
  disk?
  filtering?
  awareness?
  node eligibility?
  recovery?
       |
       v
Determine root cause
       |
       v
Controlled remediation
```

The key lesson:

> Cluster-health color tells you that an allocation problem exists. Allocation diagnostics help determine why.

---

# 3.42 Hands-On Replica Challenge

Suppose:

```text
number_of_nodes      = 2
number_of_data_nodes = 2

sre_tutorial_03:

number_of_shards   = 3
number_of_replicas = 2
```

You observe:

```text
P0 STARTED
R0 STARTED
R0 UNASSIGNED

P1 STARTED
R1 STARTED
R1 UNASSIGNED

P2 STARTED
R2 STARTED
R2 UNASSIGNED
```

Why?

Each shard requires:

```text
1 primary
+
2 replicas
=
3 independent copies
```

but only:

```text
2 eligible data nodes
```

exist.

Elasticsearch therefore cannot place all three copies while keeping copies of the same shard on different nodes.

Potential architectural responses include:

```text
Reduce replica count
```

or:

```text
Provide sufficient eligible nodes
```

The appropriate choice depends on the required availability architecture.

The objective is not simply to turn the cluster green.

---

# 3.43 Production Prechange Checklist

Before changing shard or replica configuration in production, review:

```text
[ ] Current cluster health
[ ] Primary/replica allocation
[ ] Data-node count
[ ] Node roles
[ ] Disk utilization
[ ] Shard sizes
[ ] Shard count
[ ] Recovery activity
[ ] Relocation activity
[ ] Allocation rules
[ ] Awareness configuration
[ ] Failure domains
[ ] Indexing workload
[ ] Search workload
[ ] Expected growth
[ ] Maintenance activity
[ ] Recovery objectives
```

A configuration change should have a known reason and expected result.

---

# 3.44 Lab Cleanup — Precheck

Before deleting anything, verify the exact target.

`[TUTORIAL-ACCEPTANCE — SAFE-READ]`

```bash
curl -u "$ES_USER:$ES_PASSWORD" \
  "$ES_URL/_cat/indices/sre_tutorial_03?v"
```

Then verify its settings:

```bash
curl -u "$ES_USER:$ES_PASSWORD" \
  "$ES_URL/sre_tutorial_03/_settings?pretty"
```

Confirm that the target is exactly:

```text
sre_tutorial_03
```

---

# 3.45 Delete the Tutorial Index

`[TUTORIAL-LAB — DESTRUCTIVE]`

Only after verifying the exact resource:

```bash
curl -u "$ES_USER:$ES_PASSWORD" \
  -X DELETE "$ES_URL/sre_tutorial_03"
```

Expected acknowledgement:

```json
{
  "acknowledged": true
}
```

Then verify the result.

`[TUTORIAL-ACCEPTANCE — SAFE-READ]`

```bash
curl -u "$ES_USER:$ES_PASSWORD" \
  "$ES_URL/_cat/indices/sre_tutorial_03?v"
```

Remember the operational pattern:

```text
Identify
   ↓
Verify
   ↓
Change / Delete
   ↓
Verify result
```

---

# 3.46 Tutorial Acceptance Check

You should now be able to answer the following without referring to the tutorial.

### 1. What is a primary shard?

One copy in each shard replication group acts as the current primary and handles the primary side of indexing operations for that shard.

### 2. What is a replica shard?

An additional shard copy that contributes to redundancy and can participate in reads.

### 3. How many desired shard copies exist with five primaries and two replicas?

```text
5 × (1 + 2)
=
15
```

### 4. Why can't Elasticsearch place a primary and its replica on the same node?

Doing so would defeat node-level redundancy because losing that node could remove multiple copies of the same shard.

### 5. Why might a two-node cluster with two replicas remain yellow?

Each replication group requires three independent copies but only two eligible nodes are available.

### 6. What does `UNASSIGNED` mean?

The shard currently has no eligible assigned node.

### 7. Which API should you use to understand why a shard cannot be allocated?

```text
_cluster/allocation/explain
```

### 8. Can `number_of_replicas` be changed dynamically?

Yes.

### 9. Is increasing replicas operationally free?

No. It can increase storage, recovery traffic, network activity, CPU work, and shard overhead.

### 10. Can `number_of_shards` normally be changed using `_settings`?

No. It is a static index setting.

### 11. Why can a green cluster still have poor architecture?

Green primarily indicates successful shard allocation. It does not guarantee appropriate shard sizing, available capacity, good query performance, balanced workloads, or acceptable recovery characteristics.

### 12. Why should explicit `_refresh` not become a routine ingestion pattern?

Because explicit refreshes have operational cost and should not be forced unnecessarily.

### 13. What should you do before manually changing shard allocation?

Understand why Elasticsearch made the current allocation decision.

---

# 3.47 Administrator Command Sheet

## Cluster health

```bash
curl -u "$ES_USER:$ES_PASSWORD" \
  "$ES_URL/_cluster/health?pretty"
```

## Index inventory

```bash
curl -u "$ES_USER:$ES_PASSWORD" \
  "$ES_URL/_cat/indices?v"
```

## Shard inventory

```bash
curl -u "$ES_USER:$ES_PASSWORD" \
  "$ES_URL/_cat/shards?v"
```

## Unassigned-shard investigation

```bash
curl -u "$ES_USER:$ES_PASSWORD" \
  "$ES_URL/_cat/shards?v&s=state,index,shard"
```

## Node inventory

```bash
curl -u "$ES_USER:$ES_PASSWORD" \
  "$ES_URL/_cat/nodes?v"
```

## Allocation overview

```bash
curl -u "$ES_USER:$ES_PASSWORD" \
  "$ES_URL/_cat/allocation?v"
```

## Allocation explanation

```bash
curl -u "$ES_USER:$ES_PASSWORD" \
  "$ES_URL/_cluster/allocation/explain?pretty"
```

## Index settings

```bash
curl -u "$ES_USER:$ES_PASSWORD" \
  "$ES_URL/sre_tutorial_03/_settings?pretty"
```

## Change replicas

```bash
curl -u "$ES_USER:$ES_PASSWORD" \
  -X PUT "$ES_URL/sre_tutorial_03/_settings" \
  -H 'Content-Type: application/json' \
  -d '{
    "index": {
      "number_of_replicas": 1
    }
  }'
```

---

# 3.48 Key Administrator Takeaways

Remember these principles:

```text
1. An index is distributed through primary shards.

2. Replicas provide additional copies of those shards.

3. Replica count is per primary shard.

4. Primary-shard count is a static index setting.

5. Replica count is dynamic—but changing it has capacity consequences.

6. Elasticsearch normally handles shard allocation automatically.

7. Routing determines the target shard for a document.

8. Writes flow through the current primary and appropriate
   in-sync replica copies.

9. Reads may use active primary or replica copies.

10. YELLOW means all primaries are allocated but some
    replicas are unassigned.

11. RED means at least one primary is unassigned.

12. GREEN does not prove that the architecture is healthy.

13. Use allocation explain before changing allocation behavior.

14. Shard sizing must consider recovery as well as performance.

15. Avoid both oversized shards and excessive numbers
    of tiny shards.

16. Forced shard-allocation operations belong in controlled
    recovery procedures.

17. Identify → Verify → Change → Verify.
```

---

# 3.49 Vendor References

For further technical validation and deeper study, consult the official Elastic documentation for:

* Clusters, nodes, and shards
* Reading and writing documents
* Shard allocation, relocation, and recovery
* General index settings
* Cluster-level shard allocation and routing settings
* Cluster Allocation Explain API
* Diagnosing unassigned shards
* Shard sizing
* CAT APIs
* Refresh API

Vendor documentation should remain the authoritative reference for version-specific behavior and supported configuration.

---

# 3.50 Tutorial Completion

You have now completed the hands-on introduction to:

```text
Index architecture
      ↓
Primary shards
      ↓
Replication groups
      ↓
Replica shards
      ↓
Document routing
      ↓
Read/write paths
      ↓
Shard allocation
      ↓
Cluster health
      ↓
Allocation troubleshooting
      ↓
Shard sizing
      ↓
Production safety
```

The most important operational principle from this tutorial is:

> **Do not change shard allocation merely because a cluster is yellow or red. First determine which shards are affected, whether they are primary or replica copies, whether recovery is already progressing, and why Elasticsearch's allocation system made its current decision.**

---

## Canonical Status

**Module:** 03 — Index, Shard & Replica Administration
**Tutorial:** 03 — Index, Shard & Replica Administration
**Edition:** Revised Final / Canonical
**Technical + Vendor Review:** PASS
**Production + Safety Review:** PASS
**Copyright/Originality Review:** PASS
**Hands-On Lab:** PASS
**SAFE-READ acceptance commands:** Included
**Controlled-write classification:** Included
**Destructive-operation guardrails:** Included
**High-risk recovery boundary:** Included
**Publication status:** **CANONICAL — READY FOR REPOSITORY VALIDATION**
