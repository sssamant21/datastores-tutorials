# Production Runbook 02 — Production Installation & Configuration

**Module:** 02 — Production Installation & Configuration  
**Track:** Elasticsearch Administrator / DBRE / SRE  
**Reference Elasticsearch:** 9.5.x  
**Artifact Type:** Production Runbook  
**Edition:** Revised Final / Canonical  
**Status:** **CANONICAL / COMMITTED / VERIFIED**  
**Prerequisites:** Tutorial 02, Hands-On Lab 02, Real-World Use Case 02

---

## 1. Purpose

This runbook provides the production procedure for validating, accepting, restarting, and operationally signing off a newly installed or materially reconfigured Elasticsearch cluster.

Use it for initial production deployment, Kubernetes or VM installation validation, node replacement, configuration changes, storage/platform changes, security/TLS changes, controlled restart validation, and final production acceptance.

> **Can this Elasticsearch cluster be safely accepted and operated as production infrastructure?**

```text
Running
   ≠
Healthy
   ≠
Resilient
   ≠
Recoverable
   ≠
Production Ready
```

## 2. Production Readiness Model

Production acceptance covers seven domains: Identity, Configuration, Security, Persistence, Resilience, Recovery, and Operations.

```text
Infrastructure
      ↓
Cluster Identity
      ↓
Cluster Health
      ↓
Runtime Configuration
      ↓
Security
      ↓
Persistence
      ↓
Resilience
      ↓
Controlled Recovery Test
      ↓
Snapshot / Restore
      ↓
Monitoring / Capacity
      ↓
Cleanup
      ↓
Production Sign-Off
```

## 3. Scope

The reference implementation is a secured three-node Elasticsearch 9.5.x cluster on Kubernetes with persistent storage. Elasticsearch-level checks also apply to VM and bare-metal installations. Platform-specific infrastructure commands must be adapted to the deployment environment.

## 4. Safety Classification

- **SAFE / READ-ONLY** — inspection such as `_cluster/health` and `_cat/nodes`.
- **CONTROLLED CHANGE** — alters cluster/platform state, such as restart or validation-index creation.
- **HIGH-RISK / DR** — potential outage/data loss operations such as stale-primary allocation.

For every controlled change record reason, owner, precheck, expected effect, rollback/recovery method, start time, and post-change validation.

## 5. Prohibited Normal-Runbook Actions

This runbook does not authorize routine use of `allocate_stale_primary`, `allocate_empty_primary`, blind force allocation, manual cluster-state manipulation, production data-path deletion, production PVC/PV deletion, blind replica reduction, re-bootstrap of an existing cluster, or simultaneous blind node restarts.

## 6. STOP Conditions

Stop normal execution for an unexpected cluster UUID/name, unexpected membership, loss of master/quorum, unavailable primary shards, unexpected storage replacement, validation-data loss, transport TLS failure, certificate identity mismatch, authentication unexpectedly disabled, node rejoin failure, bootstrap configuration unexpectedly present, insufficient recovery capacity, critical disk-capacity/watermark condition, or unavailable required recovery capability.

Preserve evidence, assess impact, escalate, and select the appropriate incident/DR runbook. Do not increase command risk merely to complete a maintenance window.

## 7. Required Access and Change Context

Use least privilege. Record environment, cluster name, expected UUID, version, expected nodes and roles, namespace, storage class, expected PVC/PVs, zones, snapshot repository, change/ticket, operator, and start time.

For a brand-new cluster, record its UUID immediately after successful initial cluster formation.

## 8. Safe Diagnostic Session

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
curl --cacert "$ES_CA" -u "$ES_USER:$ES_PASSWORD" "$ES_URL/<API>"
```

Do not normalize `curl -k` or `curl --insecure`. Certificate validation failures must be investigated rather than bypassed.

## 9. Infrastructure Precheck

```bash
kubectl get nodes -o wide
kubectl get pods -n elasticsearch -o wide
kubectl get pvc -n elasticsearch
kubectl get pv
```

Record Pod, worker, availability zone, status, restart count, Pod IP, PVC, PVC UID, PV, storage class, capacity, and storage topology.

Three Elasticsearch Pods do not prove three independent failure domains.

## 10. OS / Host Production Prerequisites

For the Elasticsearch 9.5.x Linux/Kubernetes reference environment:

```bash
sysctl vm.max_map_count
```

Reference gate:

```text
vm.max_map_count >= 1048576
```

Do not normalize `node.store.allow_mmap: false` as a production workaround for an improperly configured worker.

Inspect runtime file descriptors:

```bash
curl --cacert "$ES_CA" -u "$ES_USER:$ES_PASSWORD" \
  "$ES_URL/_nodes/stats/process?filter_path=nodes.*.name,nodes.*.process.max_file_descriptors&pretty"
```

For Linux/macOS reference deployments, require `max_file_descriptors >= 65535`. Also review swap, thread/process limits, clock synchronization, TCP failure-detection baseline, JNA temporary-directory requirements, and numeric UID/GID consistency where relevant.

## 11. Cluster Identity

```bash
curl --cacert "$ES_CA" -u "$ES_USER:$ES_PASSWORD" "$ES_URL/?pretty"
```

Record and verify `cluster_name`, `cluster_uuid`, and `version.number`. For an established cluster, a UUID mismatch is a STOP condition.

## 12. Node Membership, Master, and Roles

```bash
curl --cacert "$ES_CA" -u "$ES_USER:$ES_PASSWORD" "$ES_URL/_cat/nodes?v"
curl --cacert "$ES_CA" -u "$ES_USER:$ES_PASSWORD" \
  "$ES_URL/_cat/nodes?v&h=name,ip,node.role,master"
```

Validate expected count, names, roles, addresses, elected master, and absence of unexpected nodes.

`Pod Running ≠ Elasticsearch Node Joined`.

## 13. Cluster Health and Shards

```bash
curl --cacert "$ES_CA" -u "$ES_USER:$ES_PASSWORD" "$ES_URL/_cluster/health?pretty"
curl --cacert "$ES_CA" -u "$ES_USER:$ES_PASSWORD" \
  "$ES_URL/_cat/shards?v&s=index,shard,prirep"
```

GREEN means all primary and replica shards are assigned. YELLOW means all primaries are assigned but at least one replica is unassigned. RED means at least one primary is unassigned; data belonging to affected primary shard(s) is unavailable, but this does not automatically mean the entire cluster is unavailable.

For unexplained allocation:

```bash
curl --cacert "$ES_CA" -u "$ES_USER:$ES_PASSWORD" \
  -X POST "$ES_URL/_cluster/allocation/explain?pretty" \
  -H 'Content-Type: application/json' -d '{}'
```

Use Allocation Explain before considering remediation.

## 14. Runtime Configuration and Drift

```bash
curl --cacert "$ES_CA" -u "$ES_USER:$ES_PASSWORD" "$ES_URL/_nodes?pretty"
curl --cacert "$ES_CA" -u "$ES_USER:$ES_PASSWORD" "$ES_URL/_nodes/jvm?pretty"
curl --cacert "$ES_CA" -u "$ES_USER:$ES_PASSWORD" \
  "$ES_URL/_cluster/settings?flat_settings=true&include_defaults=true&pretty"
```

Review node roles, versions, JVM, transport/HTTP addresses, attributes, persistent/transient/default settings, allocation/recovery/watermark/routing overrides, and maintenance leftovers.

Validate the chain: approved design → Git/IaC → deployment manifest → ConfigMap/Secret → running process → effective Elasticsearch state.

## 15. Bootstrap and Discovery Safety

`cluster.initial_master_nodes` is for one-time initial bootstrap of a brand-new cluster. After successful formation, remove it from every node and never configure it again for that existing cluster, including joining nodes, node restart/replacement, rolling restart, full-cluster restart, or ordinary discovery troubleshooting.

Keep the distinction:

```text
cluster.initial_master_nodes = one-time bootstrap

discovery.seed_hosts = normal discovery/rejoin path
```

Verify every node retains a valid discovery path after bootstrap configuration is removed.

## 16. Security Validation

Validate authentication, authorization, HTTP TLS, transport TLS, certificate trust/identity, negative authentication, and negative trust behavior.

Positive HTTPS/authentication:

```bash
curl --cacert "$ES_CA" -u "$ES_USER:$ES_PASSWORD" "$ES_URL/"
```

Negative authentication:

```bash
curl --cacert "$ES_CA" \
  -u "$ES_USER:deliberately-wrong-password" \
  -o /dev/null -w "%{http_code}\n" "$ES_URL/"
```

Expected: `401`.

From a controlled client where the private CA is not otherwise trusted, a request without `--cacert` should fail certificate validation. Do not add `-k`.

HTTP TLS protects client-to-Elasticsearch traffic. Transport TLS protects and authenticates Elasticsearch node-to-node traffic.

## 17. Deterministic Persistence Validation

Recommended for a new production installation, major storage change, platform migration, new Kubernetes deployment model, or significant recovery-design change. Use synthetic data only.

Create `installation-validation-v1` only if it does not conflict with an existing active validation artifact:

```bash
curl --cacert "$ES_CA" -u "$ES_USER:$ES_PASSWORD" \
  -X PUT "$ES_URL/installation-validation-v1" \
  -H 'Content-Type: application/json' \
  -d '{
    "settings":{"number_of_shards":3,"number_of_replicas":1},
    "mappings":{"properties":{
      "patient_id":{"type":"keyword"},
      "event_type":{"type":"keyword"},
      "event_time":{"type":"date"}
    }}
  }'
```

Load four synthetic documents with the Bulk API and inspect the bulk response for item-level errors. Verify:

```bash
curl --cacert "$ES_CA" -u "$ES_USER:$ES_PASSWORD" \
  "$ES_URL/installation-validation-v1/_count?pretty"
```

Required count: `4`.

## 18. Capture Pre-Restart Baseline

Record cluster UUID, health, node count, master, roles, shard/recovery state, validation count, Pod UIDs, PVC UIDs, PV names, current allocation setting, and disk state.

## 19. Rolling Restart Precheck

Before every data-node restart verify correct UUID/name, expected nodes/master, approved health, no unavailable primaries, healthy storage, disk below operational restart threshold, no unexpected watermark condition, sufficient recovery headroom, no active storage-capacity incident, recovery capacity, no conflicting maintenance, and recovery readiness appropriate to the change risk.

If the precheck fails: **DO NOT RESTART**.

## 20. Record and Temporarily Change Allocation

First record the current effective `cluster.routing.allocation.enable` value. Do not assume the original state is `all`.

For the documented rolling-restart procedure, temporarily restrict replica allocation:

```bash
curl --cacert "$ES_CA" -u "$ES_USER:$ES_PASSWORD" \
  -X PUT "$ES_URL/_cluster/settings" \
  -H 'Content-Type: application/json' \
  -d '{"persistent":{"cluster.routing.allocation.enable":"primaries"}}'
```

Optionally pause/reduce non-essential indexing and flush when operationally appropriate.

## 21. Restart ONE Node

Example:

```bash
kubectl delete pod elasticsearch-2 -n elasticsearch
kubectl get pods -n elasticsearch -w
```

Kubernetes Running/Ready is not the Elasticsearch recovery gate.

Verify rejoin:

```bash
curl --cacert "$ES_CA" -u "$ES_USER:$ES_PASSWORD" "$ES_URL/_cat/nodes?v"
```

## 22. Restore Allocation and Monitor Recovery

Restore the exact original allocation state. If the original state was normal/default and no explicit persistent override should remain:

```bash
curl --cacert "$ES_CA" -u "$ES_USER:$ES_PASSWORD" \
  -X PUT "$ES_URL/_cluster/settings" \
  -H 'Content-Type: application/json' \
  -d '{"persistent":{"cluster.routing.allocation.enable":null}}'
```

If a legitimate pre-existing explicit value existed, restore that value instead.

If maintenance is aborted after allocation was restricted, restore the original value before leaving the procedure.

Monitor:

```bash
curl --cacert "$ES_CA" -u "$ES_USER:$ES_PASSWORD" "$ES_URL/_cat/recovery?v"
curl --cacert "$ES_CA" -u "$ES_USER:$ES_PASSWORD" "$ES_URL/_cluster/health?pretty"
curl --cacert "$ES_CA" -u "$ES_USER:$ES_PASSWORD" "$ES_URL/_cat/shards?v"
```

## 23. Recovery Gate

For this installation-acceptance runbook require all of the following before proceeding to another node:

```text
Expected nodes present
Same cluster UUID
GREEN
0 unassigned shards
Storage continuity
Validation documents = 4
No unintended maintenance override
```

## 24. Storage and Data Continuity

After Pod recreation expect Pod UID before ≠ Pod UID after, while PVC UID before = PVC UID after and PV before = PV after.

Verify validation count remains `4`. UUID mismatch or missing validation data is a STOP condition.

Only after the full gate passes may the next approved node be restarted.

## 25. Failure-Domain and N-1 Validation

```bash
kubectl get pods -n elasticsearch -o wide
kubectl get nodes -L topology.kubernetes.io/zone
```

Review Pod, worker, zone, storage topology, and network dependencies.

Three Elasticsearch nodes do not equal three independent failure domains.

Confirm surviving nodes can serve application traffic, hold required shards, provide sufficient disk/CPU/heap, absorb recovery I/O, and meet expected recovery/SLO requirements.

## 26. Snapshot / Restore Readiness

```bash
curl --cacert "$ES_CA" -u "$ES_USER:$ES_PASSWORD" "$ES_URL/_snapshot?pretty"
```

Require repository configured/reachable, successful and visible snapshot, documented and successfully exercised restore, validated restored data, defined recovery owner, RPO, and RTO.

A configured repository alone does not prove recoverability.

## 27. Monitoring and Capacity

Confirm monitoring for cluster health, nodes, unassigned shards, disk utilization/latency/IOPS/throughput, heap pressure, GC, CPU, search/indexing latency, thread-pool queues/rejections, shard growth, snapshot failures, and certificate expiration.

Critical alerts need threshold, severity, owner, notification path, runbook, and escalation.

Record data/master node counts, CPU/memory/heap/disk per node, storage tier, utilization, primary data size, shard count/largest shard, daily growth, peak search/indexing rate, and recovery bandwidth.

## 28. Post-Maintenance Cleanup Gate

Before sign-off verify:

- allocation setting restored;
- no unexpected transient settings;
- no temporary routing restrictions or replica changes;
- no maintenance-only configuration remains;
- indexing resumed if paused;
- monitoring/alerts restored if suppressed;
- bootstrap setting absent;
- validation-index disposition decided;
- evidence sanitized;
- change ticket updated.

Recheck cluster settings after maintenance.

Do not automatically delete `installation-validation-v1`. Retain it according to policy or delete it later through an approved cleanup procedure.

## 29. Final Acceptance

Require:

```text
status = green
unassigned_shards = 0
validation count = 4
expected node count = 3
cluster UUID = baseline UUID
```

The acceptance checklist must cover Identity, Configuration, Security, Persistence, Resilience, Recovery, and Operations, including tested restore, RPO/RTO, monitoring, capacity baseline, and maintenance cleanup.

## 30. Evidence Package

Retain sanitized evidence for cluster identity/health, nodes, shards, runtime, cluster settings before/after, Kubernetes Pods/PVCs/PVs, security validation, pre-restart baseline, allocation setting, restart/recovery, storage continuity, snapshots/restores, capacity, maintenance cleanup, and production sign-off.

Never retain passwords, API keys, authentication headers, private keys, reusable tokens, real patient data, or other production secrets.

## 31. Escalation

Escalate Elasticsearch-specific identity, master-election, primary-shard, node-rejoin, allocation/recovery, bootstrap, security, snapshot/restore, or N-1 capacity failures to the Elasticsearch DBRE/SRE owner.

Escalate worker, storage/CSI, network, DNS, load balancer, zone, kernel, OS-resource, and infrastructure-capacity issues to platform/cloud operations. Follow the approved security escalation process for security findings.

## 32. Production Sign-Off

Record cluster, environment, version, UUID, validation date, change/ticket, DBRE/SRE owner, platform owner, application owner, validation results for all seven readiness domains, exceptions, risk owner, remediation due date, and final decision.

Allowed final states:

```text
APPROVED
APPROVED WITH DOCUMENTED EXCEPTION
REJECTED / REMEDIATION REQUIRED
```

## 33. Core DBRE/SRE Principle

Before accepting production, be able to answer with evidence: What cluster am I connected to? Is it intended? What configuration is actually running? Where is its data? Is security enforced? What happens if a node disappears? Can it safely rejoin? Will data survive? Can replicas recover? Can we restore? Can surviving infrastructure carry the workload? Are temporary maintenance settings removed? Who responds when something fails?

If these cannot be answered with evidence, installation is not operationally complete.

## 34. Official Elastic References

- Elastic — Rolling and full-cluster restart procedures: https://www.elastic.co/docs/deploy-manage/maintenance/start-stop-services/full-cluster-restart-rolling-restart-procedures
- Elastic — Important system configuration: https://www.elastic.co/docs/deploy-manage/deploy/self-managed/important-system-configuration
- Elastic — Virtual memory configuration: https://www.elastic.co/docs/deploy-manage/deploy/self-managed/vm-max-map-count
- Elastic — File descriptors: https://www.elastic.co/docs/deploy-manage/deploy/self-managed/file-descriptors
- Elastic — Discovery and cluster formation settings: https://www.elastic.co/docs/reference/elasticsearch/configuration-reference/discovery-cluster-formation-settings
- Elastic — Bootstrapping a cluster: https://www.elastic.co/docs/deploy-manage/distributed-architecture/discovery-cluster-formation/modules-discovery-bootstrap-cluster
- Elastic — Secure cluster communications: https://www.elastic.co/docs/deploy-manage/security/secure-cluster-communications

## 35. Canonical Status

**Technical + Source Review:** PASS  
**Production + Copyright Review:** PASS  
**Production safety:** PASS  
**Rolling-restart safety:** PASS  
**Recovery controls:** PASS  
**Copyright/originality:** PASS  
**Blocking findings:** 0

**Production Runbook 02 — CANONICAL / COMMITTED / VERIFIED**
