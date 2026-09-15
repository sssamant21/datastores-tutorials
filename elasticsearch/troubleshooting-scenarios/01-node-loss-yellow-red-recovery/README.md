# Elasticsearch Module 1 — Troubleshooting Scenario 01

## Node Loss, YELLOW/RED Cluster, Unassigned Shards, Recovery Stall, and Application 429/Timeout Investigation

**Track:** Elasticsearch Administrator / DBRE / SRE  
**Edition:** Revised Final / Canonical  
**Status:** CANONICAL / COMMITTED / VERIFIED  
**Reference Elasticsearch:** 9.5.x  
**Difficulty:** Intermediate → Advanced  
**Scenario Type:** Production Incident Simulation

### Prerequisites

- Tutorial 01 — Elasticsearch Production Architecture
- Hands-On Lab 01 — Three-Node Elasticsearch Cluster on Kubernetes
- Real-World Use Case 01 — Production Three-Node Cluster Failure
- Production Runbook 01 — Elasticsearch Node Failure and Cluster Recovery

---

## 1. Scenario Objective

This scenario trains an Elasticsearch Administrator, DBRE, or SRE to investigate a production incident in which one Elasticsearch node disappears, replica promotion occurs, shard allocation becomes constrained, the cluster enters a degraded state, surviving nodes experience increased pressure, and applications begin reporting latency, timeouts, and HTTP 429 responses.

The goal is not simply to return cluster health to GREEN. The responder must preserve evidence, protect primary data, determine the actual failure mechanism, identify recovery blockers and workload amplification, restore capacity safely, and verify application recovery.

The investigation follows an evidence-first sequence:

**Cluster state → node membership → master/quorum → shard state → allocation decision → infrastructure failure → workload pressure → application behavior → safe recovery → verification**

---

## 2. Production Mental Model

A node-loss incident can create several independent but interacting conditions:

```text
High-cost / high-concurrency workload
              ↓
CPU / memory / storage pressure
              ↓
Container or node failure
              ↓
Elasticsearch node disappears
              ↓
Replica promotion + reduced capacity
              ↓
Replica restoration attempted
              ↓
Allocation constraint blocks recovery
              ↓
YELLOW / unassigned replica
              ↓
Surviving-node pressure
              ↓
Search queues / rejected work
              ↓
429 / timeout
              ↓
Immediate application retries
              ↓
Additional Elasticsearch load
```

A responder must not collapse this chain into a single conclusion such as “Elasticsearch is slow” or “the pod OOMed.” Each link requires evidence.

---

## 3. Synthetic Production Topology

The scenario uses three Elasticsearch nodes:

| Node | Roles |
|---|---|
| `es-data-01` | master, data |
| `es-data-02` | master, data |
| `es-data-03` | master, data |

Synthetic application index:

```text
patients-v1
Primary shards: 3
Replicas:       1
```

Initial illustrative placement:

| Shard | Primary | Replica |
|---|---|---|
| 0 | es-data-01 | es-data-02 |
| 1 | es-data-02 | es-data-03 |
| 2 | es-data-03 | es-data-01 |

The exact placement in a real cluster is dynamic. Always inspect the live cluster rather than assuming a diagram matches current allocation.

---

## 4. Synthetic Workload Baseline

Before the incident:

```text
Search rate:      ~600 requests/sec
Write rate:       ~120 requests/sec
Search P95:       ~90 ms
Search P99:       ~180 ms
Application pods: 8
Workers per pod:  4
Client timeout:   2 seconds
Retries:          enabled
```

The application is healthy and the Elasticsearch cluster is GREEN.

---

## 5. Incident Trigger

At approximately 14:02:

```text
Cluster health: GREEN → YELLOW
Elasticsearch nodes: 3 → 2
Search P95: ~90 ms → ~850 ms
Search P99: ~180 ms → ~2.4 s
HTTP 429 responses: increasing
Application timeouts: increasing
```

One Elasticsearch node is no longer present in cluster membership.

The correct first response is **not** to restart Elasticsearch, delete a pod, increase thread pools, reduce replicas, disable disk allocation protection, or force shard allocation.

The first task is to establish the actual state of the system.

---

## 6. Safety Classification

### READ-ONLY / DIAGNOSTIC

The following APIs are safe starting points:

- `_cluster/health`
- `_cat/nodes`
- `_cat/master`
- `_cat/shards`
- `_cluster/allocation/explain`
- `_cat/recovery`
- `_nodes/stats`
- `_cat/thread_pool`
- `_cluster/settings`

`POST /_cluster/allocation/explain` is diagnostic even though the HTTP method is POST.

### STATE-CHANGING — REVIEW REQUIRED

Examples:

- restarting Elasticsearch
- deleting or restarting a Kubernetes pod
- restarting a VM or worker
- changing replica counts
- changing allocation settings
- reroute operations
- changing discovery configuration

### HIGH-RISK / DISASTER RECOVERY

Operations involving stale-primary allocation, accepting data loss, destroying a data path, or forcing a primary require a separate DR decision process.

---

## 7. Credential-Safe Command Setup

Do not place literal passwords in documentation, shell history, tickets, or chat messages.

```bash
export ES_URL="https://elasticsearch.example.com:9200"
export ES_USER="sre_operator"
export ES_CA="/etc/elasticsearch/certs/http_ca.crt"
read -rsp "Elasticsearch password: " ES_PASSWORD
export ES_PASSWORD
echo
```

Use certificate validation:

```bash
curl --cacert "$ES_CA" \
  -u "$ES_USER:$ES_PASSWORD" \
  "$ES_URL/"
```

Do not normalize `curl -k` as an operational practice.

---

## 8. Establish Cluster Health

```bash
curl --cacert "$ES_CA" \
  -u "$ES_USER:$ES_PASSWORD" \
  "$ES_URL/_cluster/health?pretty"
```

Synthetic observation:

```text
status:                    yellow
number_of_nodes:           2
number_of_data_nodes:      2
active_primary_shards:     3
unassigned_primary_shards: 0
unassigned_shards:         1
```

Interpretation:

- all primary shards are assigned;
- primary data remains available;
- at least one replica is unavailable;
- redundancy is reduced;
- the cluster requires investigation.

YELLOW does not mean that all application requests are unavailable.

---

## 9. Identify the Missing Node

```bash
curl --cacert "$ES_CA" \
  -u "$ES_USER:$ES_PASSWORD" \
  "$ES_URL/_cat/nodes?v&h=name,ip,node.role,master,cpu,heap.percent,ram.percent,disk.used_percent"
```

Synthetic observation:

```text
es-data-01  cpu=78  heap=72  ram=88  disk=73
es-data-02  cpu=84  heap=76  ram=90  disk=79
es-data-03  MISSING
```

Do not assume the missing node merely needs a restart. Determine why it disappeared.

---

## 10. Verify Master Availability

```bash
curl --cacert "$ES_CA" \
  -u "$ES_USER:$ES_PASSWORD" \
  "$ES_URL/_cat/master?v"
```

In a three-master-eligible-node design, the cluster can normally tolerate one master-eligible node failure while a majority of the current voting configuration remains available.

The elected master in this scenario is `es-data-01`.

If no master exists, treat the incident as a cluster-coordination problem before continuing normal shard-recovery assumptions.

---

## 11. Inspect Shard State

```bash
curl --cacert "$ES_CA" \
  -u "$ES_USER:$ES_PASSWORD" \
  "$ES_URL/_cat/shards/patients-v1?v&h=index,shard,prirep,state,node,unassigned.reason"
```

Synthetic post-failure placement:

| Shard | Copy | State | Node |
|---|---|---|---|
| 0 | p | STARTED | es-data-01 |
| 0 | r | STARTED | es-data-02 |
| 1 | p | STARTED | es-data-02 |
| 1 | r | UNASSIGNED | — |
| 2 | p | STARTED | es-data-01 |
| 2 | r | STARTED | es-data-02 |

Shard 2 demonstrates replica promotion: the former replica can become the primary when the original primary node disappears.

Important nuance: a three-node cluster with three primaries and one replica does **not** inherently remain YELLOW after losing one node. With two eligible surviving nodes, replicas may still be allocatable. Persistent YELLOW therefore requires an allocation blocker or another constraint.

---

## 12. RED Variant — Primary Risk Gate

If cluster health is RED, immediately check:

```bash
curl --cacert "$ES_CA" \
  -u "$ES_USER:$ES_PASSWORD" \
  "$ES_URL/_cluster/health?pretty"
```

If `unassigned_primary_shards > 0`, determine whether Elasticsearch has a valid in-sync shard copy, whether the missing storage is recoverable, and whether a valid snapshot exists.

If no clearly valid primary copy exists, **STOP normal troubleshooting and invoke the disaster-recovery/data-loss decision process**.

Do not blindly force a stale primary.

---

## 13. Explain the Unassigned Replica

```bash
curl --cacert "$ES_CA" \
  -u "$ES_USER:$ES_PASSWORD" \
  -X POST \
  "$ES_URL/_cluster/allocation/explain?include_disk_info=true" \
  -H 'Content-Type: application/json' \
  -d '{
    "index": "patients-v1",
    "shard": 1,
    "primary": false
  }'
```

Synthetic decision:

```text
disk_threshold: NO
```

This is evidence that Elasticsearch is intentionally refusing the replica placement under the active allocation policy.

Do not disable the disk threshold merely to make the cluster GREEN.

---

## 14. Verify the Actual Disk Watermark

Never infer the configured threshold from memory or from a runbook.

```bash
curl --cacert "$ES_CA" \
  -u "$ES_USER:$ES_PASSWORD" \
  "$ES_URL/_cluster/settings?flat_settings=true&include_defaults=true&pretty"
```

For this **training narrative only**, assume a custom low watermark of 70% is active. With the surviving nodes at approximately 73% and 79% disk use, this explains the allocation decision.

The 70% value is a synthetic training configuration, **not an Elasticsearch production default or recommendation**.

The CI implementation uses an even stricter temporary **1% training-only low watermark** solely to reproduce the same `disk_threshold` decision deterministically without filling CI disks. Neither training value should be copied into production.

---

## 15. Separate the Two Cluster Conditions

At this point there are two distinct problems:

1. `es-data-03` disappeared from the cluster.
2. Replica restoration is blocked by the current disk-allocation constraint.

Fixing only one may not fully restore the service.

---

## 16. Inspect Recovery Activity

```bash
curl --cacert "$ES_CA" \
  -u "$ES_USER:$ES_PASSWORD" \
  "$ES_URL/_cat/recovery?v&active_only=true"
```

Use recovery evidence to distinguish:

- recovery progressing normally;
- recovery waiting on allocation;
- recovery stalled on storage/network throughput;
- repeated recovery/restart cycles.

A quiet recovery API does not prove the cluster is healthy; correlate with shard state and Allocation Explain.

---

## 17. Inspect Search Thread-Pool Pressure

```bash
curl --cacert "$ES_CA" \
  -u "$ES_USER:$ES_PASSWORD" \
  "$ES_URL/_cat/thread_pool/search?v&h=node_name,name,active,queue,rejected,completed"
```

Synthetic snapshots:

```text
T1
es-data-01 active=24 queue=420 rejected=1280 completed=5843021
es-data-02 active=24 queue=510 rejected=1740 completed=6019944

T2
es-data-01 active=24 queue=690 rejected=2415 completed=5878110
es-data-02 active=24 queue=760 rejected=3188 completed=6058030
```

For `es-data-01`, the rejection counter increased by 1,135 between observations.

Cumulative `rejected` counters are not a rate. Use deltas over a known interval and correlate them with `active`, `queue`, `completed`, latency, and application responses.

---

## 18. Interpret HTTP 429 Correctly

HTTP 429 indicates rejected work/backpressure, but it does not automatically prove that the search thread pool is the rejecting component.

Inspect the actual response/error type and correlate it with Elasticsearch metrics and thread-pool counters before assigning causality.

---

## 19. Investigate Application Retry Behavior

Synthetic client configuration:

```text
request timeout: 2 seconds
maximum attempts: 4
retry delay: immediate
backoff: none
jitter: none
```

This configuration can amplify a degraded-cluster incident.

Illustrative only:

```text
Baseline requests = 600 rps
If 20% require one retry:
Extra requests = 120 rps
Illustrative total = 720 rps
```

This arithmetic is a hypothesis until validated using application/client telemetry. Multiple attempts can increase the amplification further.

---

## 20. Recognize the Retry Feedback Loop

```text
Reduced Elasticsearch capacity
        ↓
Higher latency
        ↓
Application timeout
        ↓
Immediate retry
        ↓
Additional request volume
        ↓
Longer queues
        ↓
More rejected work / 429
        ↓
More retries
```

During an incident, application retry policy can become part of the database workload.

---

## 21. Investigate Kubernetes State

```bash
kubectl get pods -n elasticsearch -o wide
```

Synthetic observation:

```text
elasticsearch-2   CrashLoopBackOff
```

Inspect the pod:

```bash
kubectl describe pod elasticsearch-2 -n elasticsearch
```

Inspect previous-container logs:

```bash
kubectl logs elasticsearch-2 -n elasticsearch --previous
```

Synthetic last state:

```text
Reason: OOMKilled
```

`OOMKilled` establishes that the container/cgroup was terminated for a memory condition. It does **not**, by itself, prove Java heap exhaustion.

---

## 22. Investigate JVM and Memory Evidence

```bash
curl --cacert "$ES_CA" \
  -u "$ES_USER:$ES_PASSWORD" \
  "$ES_URL/_nodes/stats/jvm,process?pretty"
```

Inspect old-generation memory specifically:

```bash
curl --cacert "$ES_CA" \
  -u "$ES_USER:$ES_PASSWORD" \
  "$ES_URL/_nodes/stats?filter_path=nodes.*.name,nodes.*.jvm.mem.pools.old&pretty"
```

Correlate:

- JVM heap use;
- old-generation occupancy;
- GC behavior;
- Elasticsearch logs;
- container memory requests/limits;
- native/off-heap memory;
- mmap/page cache behavior;
- concurrent workload;
- node-level memory pressure.

Use `kubectl top` for current resource observations when metrics are available, but do not treat current usage as a reconstruction of historical memory state.

---

## 23. Investigate the Workload

A representative expensive request might include:

```json
{
  "size": 5000,
  "query": {
    "bool": {
      "must": [
        { "match_all": {} }
      ]
    }
  },
  "sort": [
    { "event_date": "desc" }
  ]
}
```

Do not conclude that `match_all` alone caused the incident. `match_all` is a valid query construct.

Workload cost is a combination of factors:

```text
Query shape
× page size
× sorting / aggregations
× data volume
× shard fan-out
× request rate
× application concurrency
= cluster workload
```

---

## 24. Correlate Slow Logs and Timeline

Synthetic slow-log durations:

```text
4.2 s
5.8 s
7.1 s
9.4 s
```

The important question is not simply whether slow queries exist. Correlate their timestamps with:

- memory pressure;
- node disappearance;
- search queues;
- rejection-counter growth;
- 429 responses;
- application retries;
- storage pressure.

Causality requires combined evidence and timing.

---

## 25. Evidence-Supported Incident Chain

For this scenario, the evidence supports the following chain:

```text
High-cost / high-concurrency workload
        ↓
Elevated resource pressure
        ↓
Container memory condition
        ↓
Kubernetes OOM termination
        ↓
Elasticsearch node loss
        ↓
Replica promotion
        ↓
Cluster capacity reduction
        ↓
Replica restoration required
        ↓
Training disk-allocation constraint blocks one replica
        ↓
YELLOW cluster
        ↓
Higher pressure on surviving nodes
        ↓
Search queues / rejected work
        ↓
Application 429 / timeout symptoms
        ↓
Immediate retries amplify load
```

The wording is intentionally careful: the workload materially increased pressure and contributed to the memory condition. `OOMKilled` identifies the container failure mechanism. Java heap exhaustion should only be stated when JVM/GC evidence supports it.

---

## 26. Incident Classification

| Layer | Finding |
|---|---|
| Trigger / contributor | high-cost, high-concurrency workload |
| Immediate failure mechanism | Kubernetes container OOM termination |
| Memory investigation | JVM + native/off-heap + container limit + workload |
| Cluster consequence | node count 3 → 2 |
| Shard consequence | replica promotion and replica restoration |
| Availability consequence | reduced replica redundancy |
| Recovery blocker | disk allocation decision |
| Performance consequence | queues and rejected work |
| Application consequence | latency, timeout, 429 |
| Amplifier | immediate retries without backoff/jitter |

---

## 27. Remediation Order

A reasonable sequence for this synthetic incident is:

1. control the proven high-cost workload;
2. control retry amplification with the application owner;
3. verify surviving nodes are stable;
4. determine and correct the failed-node memory condition;
5. restore the node safely;
6. monitor shard recovery;
7. correct the legitimate storage/capacity condition blocking allocation;
8. verify GREEN and zero unassigned shards;
9. restore workload gradually while watching performance.

This order is conditional, not universal. A RED cluster with an unassigned primary can take precedence over performance tuning.

---

## 28. Why Not Increase Search Threads First?

Increasing thread-pool capacity without understanding CPU, heap, queueing, storage, and request concurrency can simply move pressure deeper into the node and increase memory or CPU contention.

Thread-pool tuning is not a substitute for workload control or capacity planning.

---

## 29. Why Not Disable Disk Protection?

Disk allocation thresholds exist to protect the cluster from unsafe storage conditions.

If allocation is blocked because the nodes genuinely lack sufficient disk headroom, correct the capacity problem or data lifecycle rather than changing the threshold merely to obtain GREEN health.

---

## 30. Why Not Reduce Replicas Just to Get GREEN?

Reducing replicas can make health appear GREEN by redefining the desired redundancy. It does not restore the lost failure tolerance.

Replica changes must be a deliberate architecture/capacity decision, not a cosmetic incident response.

---

## 31. Application-Side Mitigation

Coordinate with the application owner before changing client behavior.

Possible controls include:

- bounded exponential backoff;
- jitter;
- retry only appropriate failures;
- strict maximum attempts;
- concurrency limits;
- circuit breaking/load shedding where appropriate;
- smaller result pages;
- bounded date ranges;
- avoiding unnecessary expensive sorting/aggregations;
- eliminating unnecessary repeated clauses.

For deep pagination, prefer `search_after`. When a consistent multi-page view is required, use point-in-time (PIT) with `search_after`.

---

## 32. Safe Node-Restoration Gate

Before restarting/recreating/restoring the failed node, verify:

- failure evidence has been preserved;
- memory condition has been investigated;
- workload/retry amplification is controlled where necessary;
- surviving nodes are stable enough for recovery;
- PVC/storage is healthy;
- Elasticsearch configuration is valid;
- TLS/security material is valid;
- the existing data path is preserved unless a deliberate recovery procedure says otherwise;
- the node is configured to join the expected cluster;
- `cluster.initial_master_nodes` is **not** reintroduced into the formed cluster.

---

## 33. Bootstrap Safety

`cluster.initial_master_nodes` is for initial bootstrap of a brand-new cluster.

After cluster formation, remove it from normal runtime configuration. Do not add it while restarting a node, joining a replacement node, or performing a full-cluster restart of an existing cluster.

Misuse can create a separate cluster and introduce serious recovery risk.

---

## 34. Restore the Node

The exact operation depends on the platform and root cause. Examples may include a controlled pod recreation, VM recovery, or service restart after the restoration gate is satisfied.

After the state-changing action, verify membership:

```bash
curl --cacert "$ES_CA" \
  -u "$ES_USER:$ES_PASSWORD" \
  "$ES_URL/_cat/nodes?v"
```

Then verify cluster identity using the root API as supporting evidence:

```bash
curl --cacert "$ES_CA" \
  -u "$ES_USER:$ES_PASSWORD" \
  "$ES_URL/"
```

Cluster UUID is useful identity evidence, but safe rejoin primarily depends on preserved cluster state, correct discovery configuration, and correct bootstrap handling.

---

## 35. Different-Cluster STOP Gate

If the returning node appears to belong to a different cluster, shows unexpected cluster identity, or has suspicious data-path state:

**STOP.**

Do not:

- bootstrap a new cluster;
- delete the data path;
- attempt to merge clusters;
- force allocation to “make it work.”

Preserve evidence and escalate through the recovery/DR process.

---

## 36. Monitor Recovery

```bash
curl --cacert "$ES_CA" \
  -u "$ES_USER:$ES_PASSWORD" \
  "$ES_URL/_cat/recovery?v&active_only=true"
```

```bash
curl --cacert "$ES_CA" \
  -u "$ES_USER:$ES_PASSWORD" \
  "$ES_URL/_cat/shards/patients-v1?v"
```

```bash
curl --cacert "$ES_CA" \
  -u "$ES_USER:$ES_PASSWORD" \
  "$ES_URL/_cluster/health?pretty"
```

Recovery can create significant disk and network I/O. Watch the surviving workload while shards recover.

---

## 37. Recovery-Stall Variant

Suppose the failed node returns, but the cluster remains YELLOW.

Do not restart it again merely because health is not GREEN.

Run Allocation Explain again:

```bash
curl --cacert "$ES_CA" \
  -u "$ES_USER:$ES_PASSWORD" \
  -X POST \
  "$ES_URL/_cluster/allocation/explain?include_disk_info=true" \
  -H 'Content-Type: application/json' \
  -d '{
    "index": "patients-v1",
    "shard": 1,
    "primary": false
  }'
```

The allocation deciders tell you why Elasticsearch is not placing the shard.

---

## 38. RED / No-Valid-Copy Variant

If a primary remains unassigned:

1. identify the shard;
2. inspect Allocation Explain;
3. determine whether an in-sync copy exists;
4. verify the missing node/storage state;
5. verify snapshot availability;
6. assess data-loss risk.

If there is no clearly valid copy, stop normal incident remediation and enter the disaster-recovery decision path.

Never use stale-primary allocation as a routine troubleshooting shortcut.

---

## 39. Bounded Application Validation

After recovery, use a representative bounded request rather than an unbounded exploratory search:

```bash
curl --cacert "$ES_CA" \
  -u "$ES_USER:$ES_PASSWORD" \
  -X POST \
  "$ES_URL/patients-v1/_search" \
  -H 'Content-Type: application/json' \
  -d '{
    "size": 10,
    "track_total_hits": false,
    "_source": ["patient_id", "status"],
    "query": {
      "term": {
        "status": "active"
      }
    }
  }'
```

Verify:

- request succeeds;
- `timed_out` is false;
- no failed shards;
- latency has returned near expected baseline.

---

## 40. Performance Validation

Recheck thread pools:

```bash
curl --cacert "$ES_CA" \
  -u "$ES_USER:$ES_PASSWORD" \
  "$ES_URL/_cat/thread_pool/search?v&h=node_name,name,active,queue,rejected,completed"
```

```bash
curl --cacert "$ES_CA" \
  -u "$ES_USER:$ES_PASSWORD" \
  "$ES_URL/_cat/thread_pool/write?v&h=node_name,name,active,queue,rejected,completed"
```

Inspect node resource state:

```bash
curl --cacert "$ES_CA" \
  -u "$ES_USER:$ES_PASSWORD" \
  "$ES_URL/_nodes/stats/jvm,process,fs,thread_pool?pretty"
```

Validate trends, not merely a single point-in-time number.

---

## 41. Synthetic Incident Timeline

| Time | Event |
|---|---|
| 14:00 | high-cost workload active |
| 14:02 | memory pressure increases |
| 14:03 | Elasticsearch pod terminated for memory condition |
| 14:03 | node count falls from 3 to 2 |
| 14:04 | replica promotion occurs |
| 14:04 | cluster YELLOW; one replica remains unassigned |
| 14:05 | surviving-node search queues rise |
| 14:06 | 429 and timeout rate rises |
| 14:07 | immediate retries amplify request volume |
| 14:10 | SRE begins evidence-first investigation |
| 14:15 | workload/retry pressure controlled |
| 14:18 | failed-node condition reviewed and node restored |
| 14:20 | shard recovery monitored |
| 14:24 | allocation/storage blocker corrected |
| 14:27 | cluster GREEN, 3 nodes, zero unassigned shards |
| 14:30 | application latency and errors return toward baseline |

---

## 42. RCA Wording

A defensible RCA for the synthetic incident is:

> A high-cost, high-concurrency search workload materially increased Elasticsearch resource pressure. The affected Kubernetes container was terminated under a memory condition, causing one Elasticsearch node to leave the cluster. Elasticsearch promoted available replica data to maintain primary availability, but replica restoration was constrained by the active disk-allocation policy. The resulting two-node state reduced capacity and increased queueing and rejected work. Application timeouts and immediate retries amplified the degraded workload. Service was restored by controlling workload/retries, correcting the failed-node condition, restoring cluster capacity, resolving the legitimate allocation/storage constraint, and validating shard, performance, and application recovery.

Do not replace “memory condition” with “Java heap exhaustion” unless JVM/GC evidence proves that narrower claim.

---

## 43. Corrective Actions — Application

- review page sizes and response sizes;
- use bounded search ranges;
- review expensive sorting/aggregations;
- remove unnecessary query clauses;
- use `search_after` for deep pagination;
- use PIT + `search_after` when a consistent paginated view is required;
- implement bounded exponential backoff and jitter where appropriate;
- cap retry attempts;
- instrument timeout, retry, and 429 metrics;
- perform realistic load testing before production changes.

---

## 44. Corrective Actions — Elasticsearch

- review shard sizing and shard count;
- review mapping and query governance;
- monitor search/write queues and rejection deltas;
- monitor JVM old generation and GC;
- monitor storage latency, IOPS, throughput, and disk headroom;
- review allocation decisions during degraded states;
- maintain adequate replica strategy;
- validate recovery behavior regularly.

---

## 45. Corrective Actions — Kubernetes / Infrastructure

- review container requests and limits;
- review node memory headroom;
- preserve persistent storage semantics;
- monitor storage performance and capacity;
- preserve previous-container logs/events;
- validate anti-affinity/topology design;
- test controlled pod and worker-node failure separately;
- ensure monitoring survives the component being failed.

---

## 46. N-1 Capacity Principle

A production Elasticsearch cluster should be designed so that losing a single expected failure-domain component does not immediately drive the surviving system beyond safe operating capacity.

This is an **N-1 engineering principle**, not a rigid universal utilization percentage. The required headroom depends on workload, shard topology, recovery traffic, node roles, storage, failure domain, and service objectives.

---

## 47. Troubleshooting Decision Tree — YELLOW

```text
Cluster YELLOW
   |
   +-- Are all primaries assigned?
   |       |
   |       +-- NO → primary-risk / RED-style investigation
   |       |
   |       +-- YES
   |
   +-- Which replica is unassigned?
   |
   +-- Allocation Explain
           |
           +-- disk threshold → capacity / storage remediation
           +-- allocation filter → inspect policy
           +-- awareness/topology → inspect failure domains
           +-- delayed allocation → inspect node-loss timing
           +-- no valid target → inspect topology/capacity
```

---

## 48. Troubleshooting Decision Tree — Node Missing

```text
Node missing
   |
   +-- Kubernetes / VM / service state
   |
   +-- Preserve logs/events
   |
   +-- OOM / disk / filesystem / storage / network / TLS / config / fatal ES error?
   |
   +-- Is cluster still coordinated?
   |
   +-- Are all primaries available?
   |
   +-- Are survivors stable?
   |
   +-- Root cause understood enough for safe restoration?
           |
           +-- NO → continue evidence collection
           +-- YES → controlled restoration
```

---

## 49. Troubleshooting Decision Tree — 429 / Timeout

```text
429 / timeout
   |
   +-- Identify actual ES error/rejection type
   |
   +-- Inspect active / queue / rejected / completed deltas
   |
   +-- Check node CPU / heap / old gen / GC / storage
   |
   +-- Inspect query cost and shard fan-out
   |
   +-- Inspect application concurrency
   |
   +-- Inspect retries/backoff/jitter
   |
   +-- Correlate with node loss/recovery timeline
```

---

## 50. Unsafe Actions to Avoid

Do not normalize the following as first-response actions:

- blind Elasticsearch restart;
- repeated pod deletion;
- reintroducing `cluster.initial_master_nodes`;
- forcing a stale primary;
- reducing replicas only to obtain GREEN;
- disabling disk allocation protection to force placement;
- arbitrarily increasing thread pools;
- using `curl -k` as the standard command pattern;
- running expensive exploratory production searches;
- enabling unbounded retries;
- destroying a returning node's data path without a recovery decision.

---

## 51. Completion Criteria

The incident is not complete merely because health becomes GREEN.

Verify all of the following:

- expected node count restored;
- expected master/coordinator state;
- cluster GREEN;
- zero unassigned shards;
- recovery complete;
- primary data safe;
- replica redundancy restored;
- CPU stable;
- JVM heap/old-generation/GC stable;
- storage latency and disk headroom acceptable;
- queues normalized;
- rejection-counter growth normalized;
- application latency recovered;
- 429 rate normalized;
- timeout rate normalized;
- retry volume normalized;
- high-cost workload controlled;
- RCA and corrective actions recorded.

---

## 52. Implementation Validation Matrix

The CI implementation intentionally validates the parts of the scenario that can be reproduced safely and deterministically.

| Scenario behavior | Validation mode |
|---|---|
| secured Elasticsearch 9.5.x cluster | runtime |
| three-node GREEN baseline | runtime |
| node/capacity loss | runtime |
| sustained two-node state | runtime |
| YELLOW with zero unassigned primaries | runtime |
| unassigned replica | runtime |
| disk allocation `NO` decision | runtime |
| bounded search availability while degraded | runtime |
| thread-pool diagnostics | API/evidence |
| JVM old-generation diagnostics | API/evidence |
| node restoration | runtime |
| final three-node GREEN state | runtime |
| temporary training watermark removed | runtime |
| uncontrolled OOM storm | intentionally not forced |
| uncontrolled 429/rejection storm | intentionally not forced |
| RED/no-valid-copy data-loss path | documented STOP/DR guardrail only |

The implementation uses a controlled StatefulSet **3 → 2 → 3** transition and pins the observation API path to a surviving Elasticsearch pod. This prevents the monitoring channel from disappearing with the failed component and creates a deterministic degraded-state evidence window.

---

## 53. Validation Result

The Scenario 01 implementation validation passed in GitHub Actions against the validation branch.

Validated behaviors include:

- secured API access;
- healthy three-node baseline;
- controlled reduction from three Elasticsearch pods to two;
- observation of a two-node YELLOW state with all primaries assigned;
- unassigned replica evidence;
- Allocation Explain evidence containing a `disk_threshold` `NO` decision;
- safe search-thread-pool and JVM old-generation diagnostics;
- successful bounded search during degraded redundancy;
- restoration from two nodes to three;
- removal of the temporary training-only allocation setting;
- final GREEN cluster with zero unassigned shards;
- evidence artifact upload;
- cleanup.

Validation run:

```text
Workflow: Elasticsearch Scenario 001 Validation
Run ID:   34924798471
Head SHA: 39d0e8a9941b1aab1e8d4502756714e30646331d
Result:   PASS
```

The CI disk watermark is a deterministic training mechanism and is not a production recommendation.

---

## 54. Evidence Preservation Checklist

During a real incident preserve, as applicable:

- cluster health snapshots;
- node membership;
- master state;
- shard state;
- Allocation Explain output;
- recovery state;
- node/JVM/thread-pool metrics;
- Kubernetes events;
- pod describe output;
- current and previous-container logs;
- application latency/error/retry metrics;
- slow logs;
- infrastructure/storage telemetry;
- exact timeline of state-changing actions.

---

## 55. Credential Cleanup

When the shell investigation is complete:

```bash
unset ES_PASSWORD
```

Also follow the organization's credential-management and shell-history controls.

---

## 56. Core Troubleshooting Lessons

1. Establish cluster state before changing it.
2. YELLOW means all primaries are assigned but redundancy is incomplete.
3. RED means at least one primary is unassigned and may represent data unavailability.
4. Replica promotion is normal Elasticsearch recovery behavior.
5. Single-node loss does not guarantee sustained YELLOW; investigate the allocation blocker.
6. Allocation Explain is the authoritative starting point for “why won't this shard allocate?”
7. A disk decider `NO` should lead to capacity/policy investigation, not automatic threshold disabling.
8. `OOMKilled` proves a container memory termination, not necessarily Java heap exhaustion.
9. HTTP 429 proves rejected work/backpressure, not automatically the search thread pool.
10. Cumulative rejection counters require interval deltas and context.
11. Query cost is workload-dependent; `match_all` alone is not a root cause.
12. Immediate retries can amplify a degraded-cluster incident.
13. Restoring GREEN is necessary but not sufficient; performance and application behavior must also recover.
14. Preserve evidence and avoid destructive actions until the failure mechanism and data risk are understood.

---

## 57. Final Mental Model

```text
Observe
  ↓
Protect primary data
  ↓
Identify missing capacity
  ↓
Explain shard allocation
  ↓
Find infrastructure failure mechanism
  ↓
Measure surviving-node pressure
  ↓
Correlate application workload/retries
  ↓
Control amplification
  ↓
Restore capacity safely
  ↓
Monitor recovery
  ↓
Verify cluster + performance + application
  ↓
Document RCA and preventive actions
```

A production Elasticsearch incident is rarely solved by a single command. Reliable recovery comes from preserving evidence, understanding distributed-system behavior, distinguishing symptoms from mechanisms, and applying the smallest justified state-changing action.