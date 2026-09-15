# Elasticsearch Module 1 — Real-World Use Case 01

## Production Three-Node Cluster Failure, Shard Promotion, Recovery, and SRE Investigation

**Track:** Elasticsearch Administrator / DBRE / SRE  
**Status:** CANONICAL / COMMITTED / VERIFIED  
**Edition:** Revised Final / Canonical  
**Reference Elasticsearch:** 9.5.x  
**Prerequisite:** Hands-On Lab 01 — CANONICAL / COMMITTED / VERIFIED

## Purpose

This use case demonstrates how an Elasticsearch Administrator, DBRE, or SRE should investigate and manage the failure of one node in a three-node production Elasticsearch cluster. The objective is not simply to restart the failed node: establish service impact, verify master and primary-shard availability, observe replica promotion and allocation, measure surviving-node pressure, determine the underlying cause, restore the node safely, and prove both Elasticsearch and the application have returned to a stable state.

> A node failure is an event. The root cause is the condition that caused the node to fail or become unreachable.

## Scenario

A three-node production cluster changes from 3 nodes to 2. Cluster health may transition from GREEN to YELLOW, search latency rises, and applications may observe timeouts or HTTP 429 responses. The example index `patients-v1` has 3 primary shards and 1 replica.

A single-node failure does **not** guarantee a sustained YELLOW state. Elasticsearch may promote surviving in-sync replicas and may be able to recreate missing replicas across the two surviving nodes, subject to allocation rules and available resources. Always observe actual cluster state rather than assuming a health transition.

## Production command standard

Use authenticated HTTPS with certificate verification:

```bash
export ES_URL="https://elasticsearch.example.com:9200"
export ES_USER="sre_operator"
export ES_CA="/etc/elasticsearch/certs/http_ca.crt"
read -rsp "Elasticsearch password: " ES_PASSWORD
export ES_PASSWORD
echo
```

Standard pattern:

```bash
curl --cacert "$ES_CA" \
  -u "$ES_USER:$ES_PASSWORD" \
  "$ES_URL/<API>"
```

Do not normalize production troubleshooting around `curl -k` / `--insecure`, and do not embed real passwords in documentation or command history.

## Investigation workflow

### 1. Establish cluster health

**Safety: READ-ONLY / DIAGNOSTIC**

```bash
curl --cacert "$ES_CA" \
  -u "$ES_USER:$ES_PASSWORD" \
  "$ES_URL/_cluster/health?pretty"
```

Interpretation:

- **GREEN** — primary and replica shards are assigned.
- **YELLOW** — all primary shards are assigned, but one or more replicas are unassigned. Replica redundancy is reduced and additional-failure risk is higher.
- **RED** — one or more primary shards are unassigned. Some data is unavailable, although unaffected indices/shards may continue operating.

### 2. Identify the missing node

```bash
curl --cacert "$ES_CA" \
  -u "$ES_USER:$ES_PASSWORD" \
  "$ES_URL/_cat/nodes?v"
```

Separate these questions: **Which node is absent from Elasticsearch?** and **Why did that node disappear?** Elasticsearch membership answers the first; infrastructure/process evidence is required for the second.

### 3. Verify elected-master stability

```bash
curl --cacert "$ES_CA" \
  -u "$ES_USER:$ES_PASSWORD" \
  "$ES_URL/_cat/master?v"
```

For modern Elasticsearch, reason about a **majority of the current voting configuration**, not legacy `minimum_master_nodes` configuration.

### 4. Determine primary and replica impact

```bash
curl --cacert "$ES_CA" \
  -u "$ES_USER:$ES_PASSWORD" \
  "$ES_URL/_cat/shards/patients-v1?v&s=shard,prirep,state,node"
```

If the failed node owned a primary and an in-sync replica survives on another node, Elasticsearch can promote the surviving copy to primary. This is a core availability mechanism.

### 5. Diagnose unassigned shards

```bash
curl --cacert "$ES_CA" \
  -u "$ES_USER:$ES_PASSWORD" \
  "$ES_URL/_cat/shards?v&h=index,shard,prirep,state,node,unassigned.reason&s=state"
```

For a specific replica:

```bash
curl --cacert "$ES_CA" \
  -u "$ES_USER:$ES_PASSWORD" \
  -X POST \
  "$ES_URL/_cluster/allocation/explain?pretty" \
  -H "Content-Type: application/json" \
  -d '{
    "index": "patients-v1",
    "shard": 0,
    "primary": false
  }'
```

Although this uses HTTP POST, allocation explain is diagnostic. Use allocation-decider evidence rather than guessing why a shard cannot be allocated.

### 6. Observe recovery

```bash
curl --cacert "$ES_CA" \
  -u "$ES_USER:$ES_PASSWORD" \
  "$ES_URL/_cat/recovery?v&active_only=true"
```

Monitor cluster health alongside recovery and watch `initializing_shards`, `relocating_shards`, `unassigned_shards`, and `active_shards_percent_as_number`.

### 7. Verify application availability

Use a known, bounded, representative query rather than adding expensive diagnostic load:

```bash
curl --cacert "$ES_CA" \
  -u "$ES_USER:$ES_PASSWORD" \
  -X POST \
  "$ES_URL/patients-v1/_search?pretty" \
  -H "Content-Type: application/json" \
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

Record HTTP status, latency, `timed_out`, shard failures, and expected result behavior. A degraded cluster is not automatically an unavailable application.

### 8. Measure surviving-node pressure

```bash
curl --cacert "$ES_CA" \
  -u "$ES_USER:$ES_PASSWORD" \
  "$ES_URL/_nodes/stats/jvm,process,fs,thread_pool?pretty"
```

Review CPU, JVM heap, GC, filesystem capacity/I/O indicators, search/write thread pools, queues, and rejections. The surviving nodes now carry normal workload plus failover/recovery work.

### 9. Inspect search/write backpressure

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

Investigate application retry behavior as well. Immediate/unbounded retries can amplify a survivable node failure. Prefer bounded retry, backoff, jitter, limits, and observability.

## Failed-node investigation

For Kubernetes deployments, gather platform evidence before taking disruptive action:

```bash
kubectl get pods -o wide
kubectl describe pod <elasticsearch-pod>
kubectl logs <elasticsearch-pod>
kubectl logs <elasticsearch-pod> --previous
kubectl get events --sort-by=.lastTimestamp
kubectl get nodes -o wide
kubectl describe node <worker-node>
```

For VM/systemd deployments:

```bash
systemctl status elasticsearch
journalctl -u elasticsearch
dmesg
df -h
df -i
free -m
```

Look for evidence such as OOM/OOMKilled, disk or inode exhaustion, read-only filesystem, storage latency, VM reboot, Kubernetes node failure, network interruption, TLS failure, invalid configuration, or an Elasticsearch fatal exception.

## Do not blindly restart

A missing node is not itself justification for an immediate restart. First determine whether the surviving cluster is stable, what caused the node failure, whether the underlying condition has been corrected, and whether returning the node is safe. Repeated restarts can cause repeated shard recovery, extra disk/network I/O, and greater cluster instability.

## Allocation safety guardrail

Do not immediately change `cluster.routing.allocation.*` or manually reroute shards simply because the cluster is YELLOW or RED. First establish health, nodes, shards, allocation-explain evidence, infrastructure state, and root cause.

If a primary is unavailable, do not blindly force-allocate a stale shard or use an operation that explicitly accepts data loss merely to make the cluster GREEN. Such actions belong in a dedicated disaster-recovery procedure with backup/data-loss assessment and appropriate approval.

## Restore and verify the node

**Safety: STATE-CHANGING / POTENTIALLY DISRUPTIVE**

After correcting the underlying failure, restore the node using the appropriate platform procedure and verify membership:

```bash
curl --cacert "$ES_CA" \
  -u "$ES_USER:$ES_PASSWORD" \
  "$ES_URL/_cat/nodes?v"
```

Three visible nodes do not by themselves prove recovery.

## Bootstrap/rejoin safety

`cluster.initial_master_nodes` is for the initial formation of a brand-new cluster. After initial formation it must not become a routine restart/discovery troubleshooting mechanism. A returning node should discover and rejoin the existing cluster using normal discovery and persistent cluster state.

Record cluster identity where practical:

```bash
curl --cacert "$ES_CA" \
  -u "$ES_USER:$ES_PASSWORD" \
  "$ES_URL/?pretty"
```

Compare the expected `cluster_name` and `cluster_uuid` after recovery. UUID comparison is additional identity evidence; it is not a substitute for correct discovery/bootstrap configuration.

## Final recovery gate

```bash
curl --cacert "$ES_CA" \
  -u "$ES_USER:$ES_PASSWORD" \
  "$ES_URL/_cluster/health?pretty"
```

Desired steady state:

```text
status                  GREEN
number_of_nodes         3
number_of_data_nodes    3
unassigned_shards       0
initializing_shards     0
relocating_shards       0
```

Then validate the application: searches/indexing succeed, latency and timeout/429 rates normalize, queues are stable, rejection growth is no longer abnormal, heap/GC/disk are healthy, and there is no restart loop or unexpected shard failure.

Only then transition the incident from **RECOVERING** to **STABLE**.

## Evidence package

Preserve cluster health snapshots, cluster UUID, node membership, elected master, shard placement, allocation explanations, recovery state, node/thread-pool statistics, CPU/heap/GC and disk evidence, application latency/errors/429s/retry behavior, Elasticsearch and platform logs, infrastructure events, actions performed, recovery timeline, and final validation evidence.

## Root-cause model

Separate the incident into:

- Trigger
- Root cause
- Elasticsearch response
- Application impact
- Contributing factors
- Recovery
- Corrective actions
- Preventive actions

`YELLOW` is a cluster state produced by an incident; it is not itself the root cause.

## Core SRE model

```text
NODE FAILURE
     |
     v
CLUSTER IMPACT
     |
     v
MASTER + PRIMARY AVAILABILITY
     |
     v
REPLICA PROMOTION / ALLOCATION
     |
     v
APPLICATION AVAILABILITY
     |
     v
SURVIVING-NODE PRESSURE
     |
     v
ROOT-CAUSE INVESTIGATION
     |
     v
SAFE NODE RESTORATION
     |
     v
SHARD RECOVERY
     |
     v
CLUSTER VALIDATION
     |
     v
APPLICATION VALIDATION
     |
     v
STABLE
```

## Operational lessons

1. A node failure does not automatically mean a cluster outage.
2. YELLOW means primaries remain assigned but replica redundancy is incomplete.
3. RED means at least one primary is unassigned; determine exactly which data is affected.
4. Replica promotion is a fundamental Elasticsearch availability mechanism.
5. Master election and shard availability are separate dimensions of cluster health.
6. Use modern voting-configuration terminology for cluster coordination.
7. Use allocation-decider evidence instead of guessing.
8. Surviving nodes may have substantially less performance headroom.
9. Recovery itself consumes CPU, storage I/O, network bandwidth, and Elasticsearch resources.
10. Application retries can amplify an incident.
11. Do not restart failed nodes before investigating the underlying condition.
12. Do not change allocation settings merely to remove YELLOW status.
13. Do not force stale-primary recovery without a data-loss-aware DR procedure.
14. `cluster.initial_master_nodes` belongs only to initial cluster bootstrap.
15. A returning node must rejoin the existing cluster.
16. Cluster UUID is useful identity evidence but does not replace correct discovery configuration.
17. A running node does not prove Elasticsearch has recovered.
18. GREEN does not prove the application has recovered.
19. Incident closure requires cluster, infrastructure, and application validation.
20. Preserve evidence before disruptive changes whenever service conditions allow.

## Vendor reference areas

Validate behavior against official Elastic documentation for the applicable release: Cluster Health, CAT Nodes, CAT Master, CAT Shards, Cluster Allocation Explain, CAT Recovery, Node Stats, red/yellow health troubleshooting, unassigned-shard diagnosis, cluster bootstrapping, discovery/cluster formation, and voting configurations.

## Canonical state

**Draft:** PASS  
**Technical + Source Review:** PASS  
**Production + Copyright Review:** PASS  
**Revised Final:** PASS  
**Canonical state:** CANONICAL / COMMITTED / VERIFIED

The operational goal is not to restart Elasticsearch until it becomes green. The goal is to understand the failure, preserve service, prove Elasticsearch recovery behavior, correct the underlying cause, restore redundancy safely, and verify that both the cluster and the application have returned to a stable production state.
