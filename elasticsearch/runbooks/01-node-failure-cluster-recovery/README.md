# Elasticsearch Module 1 — Production Runbook 01

## Elasticsearch Node Failure and Cluster Recovery

**Track:** Elasticsearch Administrator / DBRE / SRE  
**Edition:** Revised Final / Canonical  
**Status:** CANONICAL / COMMITTED / VERIFIED  
**Reference Elasticsearch:** 9.5.x  
**Prerequisites:** Tutorial 01, Hands-On Lab 01, Real-World Use Case 01

## Purpose

This runbook provides the production procedure for responding to the unexpected loss, restart, or disappearance of an Elasticsearch node. Use it when node count decreases, health becomes YELLOW or RED, shards become unassigned, latency/429/timeouts rise after node loss, unexpected recovery starts, or a failed node must safely return to service.

> A node failure is an event. The root cause is the condition that caused the node to fail or become unreachable.

## Safety classification

### READ-ONLY / DIAGNOSTIC

`_cluster/health`, `_cat/nodes`, `_cat/master`, `_cat/shards`, `_cluster/allocation/explain`, `_cat/recovery`, `_nodes/stats`, and `_cat/thread_pool`.

### STATE-CHANGING / REVIEW REQUIRED

Restart Elasticsearch, delete/restart an Elasticsearch pod, restart VM/worker, change replica count or allocation settings, manual reroute, node exclusion/inclusion, or discovery changes.

### HIGH-RISK / DR PROCEDURE REQUIRED

Potential data-loss operations such as forcing stale-primary allocation or operations that explicitly accept data loss are not normal node-failure recovery actions.

## Critical guardrails

Do not blindly restart Elasticsearch or delete a pod; change `cluster.routing.allocation.*` or replica count merely to remove YELLOW; force stale-primary allocation; use data-loss-accepting recovery without DR procedure; add `cluster.initial_master_nodes` to an already formed cluster; normalize `curl -k`; or run expensive/uncontrolled diagnostics against a degraded cluster.

## Production command environment

```bash
export ES_URL="https://elasticsearch.example.com:9200"
export ES_USER="sre_operator"
export ES_CA="/etc/elasticsearch/certs/http_ca.crt"
read -rsp "Elasticsearch password: " ES_PASSWORD
export ES_PASSWORD
echo
```

```bash
curl --cacert "$ES_CA" \
  -u "$ES_USER:$ES_PASSWORD" \
  "$ES_URL/"
```

Record `cluster_name`, `cluster_uuid`, Elasticsearch version, responding node, and timestamp. Never embed real credentials in commands, documentation, tickets, Slack, or repositories.

CAT APIs in this runbook are for interactive human/SRE investigation. Automation should prefer structured JSON APIs where appropriate.

## Incident baseline

Record incident start, environment, cluster, application, expected/observed node count, previous/current health, alert, application symptoms, recent changes, on-call engineer, and incident channel/ticket. Capture evidence before remediation when doing so does not materially delay critical restoration.

## 1. Determine cluster health and primary risk

**READ-ONLY / DIAGNOSTIC**

```bash
curl --cacert "$ES_CA" \
  -u "$ES_USER:$ES_PASSWORD" \
  "$ES_URL/_cluster/health?filter_path=status,number_of_nodes,number_of_data_nodes,active_primary_shards,unassigned_primary_shards,unassigned_shards,initializing_shards,relocating_shards,active_shards_percent_as_number&pretty"
```

- GREEN: primaries and replicas assigned; still investigate reduced node capacity.
- YELLOW: all primaries assigned, one or more replicas unassigned; redundancy reduced.
- RED: one or more primaries unassigned; some data unavailable.

If `unassigned_primary_shards > 0`, enter the PRIMARY-DATA RISK path immediately.

## 2. Verify node membership

```bash
curl --cacert "$ES_CA" -u "$ES_USER:$ES_PASSWORD" "$ES_URL/_cat/nodes?v"
```

Focused view:

```bash
curl --cacert "$ES_CA" \
  -u "$ES_USER:$ES_PASSWORD" \
  "$ES_URL/_cat/nodes?v&h=name,ip,node.role,master,cpu,heap.percent,ram.percent,disk.used_percent"
```

Record expected/present/missing nodes, roles, master marker, CPU, heap, and disk. Which node disappeared and why it disappeared are separate questions.

## 3. Verify elected master

```bash
curl --cacert "$ES_CA" -u "$ES_USER:$ES_PASSWORD" "$ES_URL/_cat/master?v"
```

Modern Elasticsearch coordination requires a majority of the current voting configuration. The voting configuration is not necessarily identical to the currently available master-eligible nodes. If no elected master exists and APIs are unstable/unavailable, treat this as a cluster-coordination incident and do not make speculative bootstrap/discovery changes.

## 4. Inspect shards

```bash
curl --cacert "$ES_CA" \
  -u "$ES_USER:$ES_PASSWORD" \
  "$ES_URL/_cat/shards?v&h=index,shard,prirep,state,node,unassigned.reason&s=state,index,shard"
```

Identify STARTED, INITIALIZING, RELOCATING, and UNASSIGNED shards; `p` is primary and `r` replica.

## RED cluster — primary-shard triage

If primaries are unassigned, determine whether another valid shard copy exists, whether the failed node will return, whether normal recovery is progressing, whether a decider blocks allocation, whether storage is healthy, whether snapshot recovery exists, and whether a proposed recovery could discard newer data.

If no clearly valid in-sync copy is available: **STOP NORMAL RUNBOOK**, preserve evidence, assess failed-node data path and snapshots/data-loss exposure, and invoke the Elasticsearch DR procedure. Do not use data-loss-accepting allocation merely to obtain GREEN.

## 5. Explain unassigned shards

```bash
curl --cacert "$ES_CA" \
  -u "$ES_USER:$ES_PASSWORD" \
  -X POST \
  "$ES_URL/_cluster/allocation/explain?pretty" \
  -H "Content-Type: application/json" \
  -d '{"index":"patients-v1","shard":0,"primary":false}'
```

Review `current_state`, `unassigned_info`, `can_allocate`, `allocate_explanation`, `node_allocation_decisions`, and `deciders`. Investigate same-shard, disk threshold, filters, awareness, shard limits, disabled allocation, and other constraints before changing configuration.

### Optional storage-aware allocation diagnosis

**READ-ONLY / DIAGNOSTIC — STORAGE INVESTIGATION**

```bash
curl --cacert "$ES_CA" \
  -u "$ES_USER:$ES_PASSWORD" \
  -X POST \
  "$ES_URL/_cluster/allocation/explain?include_disk_info=true&pretty" \
  -H "Content-Type: application/json" \
  -d '{"index":"patients-v1","shard":0,"primary":false}'
```

Do not disable disk protections without understanding the storage condition.

## 6. Verify replica promotion

```bash
curl --cacert "$ES_CA" \
  -u "$ES_USER:$ES_PASSWORD" \
  "$ES_URL/_cat/shards/patients-v1?v&s=shard,prirep,state,node"
```

A surviving in-sync replica can be promoted to primary. A single node loss does not guarantee sustained YELLOW; observe actual allocation state.

## 7. Check recovery

```bash
curl --cacert "$ES_CA" -u "$ES_USER:$ES_PASSWORD" "$ES_URL/_cat/recovery?v&active_only=true"
```

```bash
curl --cacert "$ES_CA" -u "$ES_USER:$ES_PASSWORD" "$ES_URL/_cat/recovery/patients-v1?v&active_only=true"
```

Determine whether recovery is starting, progressing, stalled, restarting, or complete. Use multiple observations.

## 8. Validate application search

`patients-v1` is synthetic training data. In production use a known low-cost representative query.

```bash
curl --cacert "$ES_CA" \
  -u "$ES_USER:$ES_PASSWORD" \
  -X POST "$ES_URL/patients-v1/_search?pretty" \
  -H "Content-Type: application/json" \
  -d '{"size":10,"track_total_hits":false,"_source":["patient_id","status"],"query":{"term":{"status":"active"}}}'
```

Record HTTP status, `took`, `timed_out`, and shard success/failure. Do not create extra load with expensive diagnostics.

## 9. Check surviving-node capacity

```bash
curl --cacert "$ES_CA" \
  -u "$ES_USER:$ES_PASSWORD" \
  "$ES_URL/_nodes/stats/jvm,process,fs,thread_pool?pretty"
```

Review CPU, heap, GC, filesystem, search/write workload, queues, and rejections. Surviving nodes handle normal workload plus failover/recovery work.

## 10. Check backpressure

```bash
curl --cacert "$ES_CA" -u "$ES_USER:$ES_PASSWORD" "$ES_URL/_cat/thread_pool/search?v&h=node_name,name,active,queue,rejected,completed"
```

```bash
curl --cacert "$ES_CA" -u "$ES_USER:$ES_PASSWORD" "$ES_URL/_cat/thread_pool/write?v&h=node_name,name,active,queue,rejected,completed"
```

Collect multiple samples. Investigate retry count, max attempts, interval, backoff, jitter, timeout, client concurrency, connection pool, and request rates. Retries should be bounded, backed off, jittered, limited, and observable.

## 11. Investigate failed infrastructure

### Kubernetes

```bash
kubectl get pods -o wide
kubectl describe pod <elasticsearch-pod>
kubectl logs <elasticsearch-pod>
kubectl logs <elasticsearch-pod> --previous
kubectl get events --sort-by=.lastTimestamp
kubectl get nodes -o wide
kubectl describe node <worker-node>
kubectl get pvc
```

Investigate OOMKilled, eviction, CrashLoopBackOff, NodeNotReady, DiskPressure, MemoryPressure, PVC failures, container exits, probe failures, and scheduling failures.

### Kubernetes restart/delete gate

Before intentionally deleting/restarting a production ES pod, verify cluster health, primary availability, replica coverage, PVC/storage state, failure evidence, worker health, surviving capacity, and absence of conflicting recovery/maintenance. `kubectl delete pod` is **STATE-CHANGING / REVIEW REQUIRED**, not a generic ES repair command.

### VM / systemd

```bash
systemctl status elasticsearch
journalctl -u elasticsearch
dmesg
df -h
df -i
free -m
```

Also inspect CPU, disk latency, IOPS, throughput, queue depth, network, and platform events.

### Service restart gate

Before `systemctl restart elasticsearch`, review ES logs, disk/inodes, memory/OOM, filesystem/storage, network, configuration, TLS, and cluster state. Restart is **STATE-CHANGING / REVIEW REQUIRED** and may reproduce/worsen an unresolved condition.

## 12. Root-cause gate

Before returning the node, confirm the failure mechanism is identified or bounded, underlying problem corrected, surviving cluster stable, primary/recovery status understood, storage/network/configuration/TLS safe, existing data path understood, and the node is expected to rejoin the existing cluster.

## 13. Restore node

**STATE-CHANGING / REVIEW REQUIRED**

Use the platform-specific recovery procedure. Avoid stacking speculative fixes: apply one understood remediation, observe, and continue based on evidence.

## Bootstrap safety — critical

Never add `cluster.initial_master_nodes` to repair an already formed cluster. It belongs only to initial brand-new-cluster bootstrap and must be removed after formation; normal restart/recovery uses discovery and persistent cluster state.

## Different-cluster STOP gate

If a returning node appears associated with another Elasticsearch cluster: **STOP**. Do not attempt to merge clusters, bootstrap again, destroy the data path, or make speculative cluster-state changes. Preserve storage, configuration, and logs and escalate to DBRE/SRE recovery.

## 14. Verify node rejoin

```bash
curl --cacert "$ES_CA" -u "$ES_USER:$ES_PASSWORD" "$ES_URL/_cat/nodes?v"
```

```bash
curl --cacert "$ES_CA" -u "$ES_USER:$ES_PASSWORD" "$ES_URL/?pretty"
```

Verify expected node count/name/roles and record cluster name, UUID, and version. Expected cluster UUID should remain consistent. UUID is supporting evidence, not a substitute for correct discovery/persistent state/bootstrap configuration.

## 15. Monitor recovery

```bash
curl --cacert "$ES_CA" -u "$ES_USER:$ES_PASSWORD" "$ES_URL/_cat/recovery?v&active_only=true"
curl --cacert "$ES_CA" -u "$ES_USER:$ES_PASSWORD" "$ES_URL/_cat/shards?v&s=state,index,shard,prirep"
curl --cacert "$ES_CA" -u "$ES_USER:$ES_PASSWORD" "$ES_URL/_cluster/health?pretty"
```

If recovery stalls, inspect allocation explain, disk capacity/watermarks, filters/awareness, network, storage errors/latency, node logs, and recovery pressure. Do not repeatedly restart as a recovery strategy.

## 16. Final Elasticsearch gate

Desired steady state: GREEN, expected nodes present, unassigned primaries 0, unassigned shards 0, initializing shards 0, relocating shards 0. Verify health, nodes, and shard placement.

## 17. Performance recovery gate

Recheck search/write thread pools and node stats. Confirm CPU, heap, GC, disk, queues, and rejection behavior are stable and recovery workload is complete.

## 18. Application recovery gate

Verify search and indexing success, expected data, no unexpected shard failures, normalized search/index latency, normalized timeouts/429s/retries, and normal application concurrency. **GREEN Elasticsearch does not automatically mean the production incident is resolved.**

## Incident closure gate

Before close/downgrade verify expected nodes, stable master, GREEN, zero unassigned primaries/shards, no unexpected initialization/relocation, healthy primary/replica placement, completed recovery, stable CPU/heap/GC/disk/queues/rejections, healthy application reads/writes, normalized latency/errors, root cause identified or tracked, evidence preserved, and follow-ups assigned.

## Credential cleanup

```bash
unset ES_PASSWORD
```

Never paste passwords, API keys, bearer tokens, private keys, or other credentials into incident tickets, Slack, GitHub, or permanent documentation.

## Evidence checklist

Preserve incident timestamp, health, UUID, membership, elected master, shard placement, allocation explanations, recovery state, node/thread-pool stats, CPU/heap/GC, disk/storage evidence, ES/platform logs, cloud metrics, application latency/429/timeouts/retries, actions, recovery timestamps, and final validation.

## Escalation criteria

Escalate immediately for no elected master, multiple master-eligible losses, unassigned primaries/RED, possible data loss, filesystem/storage corruption, snapshot restoration need, persistent-storage failure, repeated crashes/recovery failure, unexpected UUID, different-cluster association, continued application outage, severe sustained 429/timeouts, or surviving-node resource exhaustion.

## Fast on-call flow

```text
_cluster/health
      ↓
unassigned primaries?
      ↓
_cat/nodes
      ↓
_cat/master
      ↓
_cat/shards
      ↓
allocation explain
      ↓
_cat/recovery
      ↓
bounded application query
      ↓
node/thread-pool pressure
      ↓
infrastructure/log evidence
      ↓
root-cause gate
      ↓
safe restoration
      ↓
verify existing-cluster rejoin
      ↓
monitor recovery
      ↓
GREEN + zero unassigned
      ↓
performance validation
      ↓
application validation
      ↓
evidence + closure
```

## Core operational principle

The goal is not simply to make Elasticsearch GREEN. Restore availability, primary-data safety, redundancy, performance, infrastructure stability, and application service without introducing additional risk or destroying evidence needed to understand the failure.

## Workflow state

**Draft:** PASS  
**Technical + Source Review:** PASS  
**Production + Copyright Review:** PASS  
**Revised Final / Canonical Edition:** PASS  
**Commit + Repository Verification:** PASS  
**Canonical Status:** CANONICAL / COMMITTED / VERIFIED
