# Real-World Use Case 02 — Production Installation & Configuration

**Module:** 02 — Production Installation & Configuration  
**Track:** Elasticsearch Administrator / DBRE / SRE  
**Reference Elasticsearch:** 9.5.x  
**Artifact Type:** Real-World Production Use Case  
**Edition:** Revised Final / Canonical  
**Status:** **CANONICAL / COMMITTED / VERIFIED**  
**Prerequisites:** Tutorial 02 + Hands-On Lab 02

---

## 1. Purpose

A production Elasticsearch deployment is not ready merely because its processes or Kubernetes Pods are running.

This use case establishes an evidence-based production-readiness methodology covering seven domains:

```text
Production Readiness
│
├── 1. Identity
├── 2. Configuration
├── 3. Security
├── 4. Persistence
├── 5. Resilience
├── 6. Recovery
└── 7. Operations
```

The central operational principle is:

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

Production readiness must be demonstrated through both **normal operation and controlled failure/recovery behavior**.

## 2. Production Scenario

A new three-node Elasticsearch cluster has been deployed on Kubernetes for a production search application.

```text
Application
    |
    v
Service / Load Balancer
    |
    v
+-----------------------------------+
|       Elasticsearch Cluster       |
|                                   |
|   es-0        es-1        es-2    |
|    |           |           |      |
|   PVC         PVC         PVC     |
+-----------------------------------+
    |
Kubernetes
    |
Persistent Storage
```

The platform team reports that all three Elasticsearch Pods are running and therefore assumes the cluster is production ready. The DBRE/SRE team rejects Pod readiness as the acceptance criterion because it does not prove correct cluster formation, cluster identity, master election, persistent storage, shard availability, HTTP or transport TLS, authentication, safe bootstrap lifecycle, failure-domain isolation, restart/rejoin safety, data persistence, snapshot recovery, or operational readiness.

## 3. Production Acceptance Model

```text
Infrastructure prepared
        ↓
Elasticsearch processes start
        ↓
Nodes discover one another
        ↓
Intended cluster forms
        ↓
Cluster identity established
        ↓
Master election succeeds
        ↓
Shards become available
        ↓
Security controls validated
        ↓
Persistent storage validated
        ↓
Bootstrap configuration removed
        ↓
Controlled node restart/rejoin tested
        ↓
Cluster identity remains unchanged
        ↓
Validation data remains available
        ↓
Failure domains reviewed
        ↓
Snapshot + restore readiness validated
        ↓
Operational controls verified
        ↓
PRODUCTION READY
```

## 4. Safety Classification

### 4.1 Read-Only / Diagnostic

Begin with read-only evidence such as `GET /`, `GET /_cluster/health`, `GET /_cat/nodes`, `GET /_cat/shards`, `GET /_nodes`, `GET /_nodes/jvm`, `GET /_nodes/stats`, and `GET /_cluster/settings`. Kubernetes inspection commands such as `kubectl get pods`, `kubectl get pvc`, `kubectl get pv`, and `kubectl describe pod` are also appropriate diagnostics.

### 4.2 State-Changing — Controlled

Creating a validation index, loading synthetic validation data, restarting a Pod, replacing configuration, rotating certificates, changing persistent cluster settings, or changing node roles requires a precheck, reason, expected effect, rollback/recovery plan, change execution, and post-change verification.

### 4.3 High-Risk / Recovery Operations

Forced shard allocation, stale-primary allocation, blind replica reduction, deleting production indices or data paths, deleting production PVC/PV storage, cluster-state manipulation, re-bootstrapping an existing cluster, and simultaneous blind node restarts are not normal production-readiness troubleshooting techniques. They require separate incident/DR procedures and strong evidence.

## 5. Safe Diagnostic Session

```bash
export ES_URL="https://elasticsearch.example.com:9200"
export ES_USER="sre_operator"
export ES_CA="/etc/elasticsearch/certs/http_ca.crt"
read -rsp "Elasticsearch password: " ES_PASSWORD
export ES_PASSWORD
echo
```

Standard command pattern:

```bash
curl --cacert "$ES_CA" \
  -u "$ES_USER:$ES_PASSWORD" \
  "$ES_URL/<API>"
```

Do not normalize `curl -k` or `curl --insecure` for production validation. Certificate verification failures are evidence to investigate, not controls to bypass.

## 6. Domain 1 — Identity

### 6.1 Verify Version and Cluster Identity

```bash
curl --cacert "$ES_CA" \
  -u "$ES_USER:$ES_PASSWORD" \
  "$ES_URL/?pretty"
```

Record `cluster_name`, `cluster_uuid`, and `version.number`. The deployed version must match the approved release specification. The reference release family for this learning track is Elasticsearch 9.5.x.

### 6.2 Cluster UUID

Record the cluster UUID before maintenance. The UUID before and after an ordinary restart/rejoin must remain the same. A changed UUID is a STOP condition. Matching UUID is necessary evidence of continuity, but not sufficient by itself: also verify node membership, persistent storage, cluster state, shard recovery, expected configuration, and validation data.

### 6.3 Verify Node Membership

```bash
curl --cacert "$ES_CA" \
  -u "$ES_USER:$ES_PASSWORD" \
  "$ES_URL/_cat/nodes?v"
```

Expected for this scenario: three Elasticsearch nodes. A Kubernetes Pod being Running does not prove that the Elasticsearch node joined the intended cluster.

### 6.4 Verify Master Election and Roles

```bash
curl --cacert "$ES_CA" \
  -u "$ES_USER:$ES_PASSWORD" \
  "$ES_URL/_cat/nodes?v&h=name,ip,node.role,master"
```

Validate expected nodes, expected roles, and the elected master. Explicit `node.roles` configuration requires careful review because removing required roles can alter or break intended cluster functionality.

## 7. Domain 2 — Configuration

### 7.1 Verify Cluster Health

```bash
curl --cacert "$ES_CA" \
  -u "$ES_USER:$ES_PASSWORD" \
  "$ES_URL/_cluster/health?pretty"
```

Review status, node counts, active primary shards, active shards, unassigned shards, and unassigned primary shards.

- **GREEN:** all primary and replica shards are assigned.
- **YELLOW:** all primary shards are assigned, but at least one replica is unassigned.
- **RED:** at least one primary shard is unassigned. Data belonging to affected primary shards is unavailable; this does not necessarily mean the entire cluster is unavailable.

GREEN is required for this use case's final gate, but GREEN alone does not prove production readiness.

### 7.2 Verify Shard Placement

```bash
curl --cacert "$ES_CA" \
  -u "$ES_USER:$ES_PASSWORD" \
  "$ES_URL/_cat/shards?v"
```

Review index, shard, primary/replica designation, state, and node. Elasticsearch node separation must not be confused with infrastructure failure-domain separation.

### 7.3 Verify OS Prerequisites

```bash
sysctl vm.max_map_count
```

The reference value used by this tutorial/lab is `1048576`. Validate requirements against the actual Elasticsearch version and deployment platform. For Kubernetes, verify the relevant worker-node kernel configuration. Do not routinely disable mmap to compensate for an improperly prepared host.

### 7.4 File Descriptors

```bash
curl --cacert "$ES_CA" \
  -u "$ES_USER:$ES_PASSWORD" \
  "$ES_URL/_nodes/stats/process?filter_path=nodes.*.name,nodes.*.process.max_file_descriptors&pretty"
```

Validate that the effective running process has an appropriately high limit for the approved deployment rather than assuming intended OS configuration reached Elasticsearch.

### 7.5 JVM

```bash
curl --cacert "$ES_CA" \
  -u "$ES_USER:$ES_PASSWORD" \
  "$ES_URL/_nodes/jvm?pretty"
```

Review JVM version, heap initialization, heap maximum, and runtime characteristics. Do not make arbitrary JVM changes based only on generic tuning advice.

### 7.6 Discovery

Review `discovery.seed_hosts`. Kubernetes StatefulSet deployments commonly use stable DNS identities such as `elasticsearch-0.elasticsearch-headless`, `elasticsearch-1.elasticsearch-headless`, and `elasticsearch-2.elasticsearch-headless`.

## 8. Bootstrap Lifecycle — Critical Safety Gate

A brand-new cluster may require `cluster.initial_master_nodes` during initial bootstrap. The correct lifecycle is:

```text
Brand-new cluster
        ↓
Configure initial master-eligible nodes
        ↓
Initial master elected
        ↓
Cluster state created
        ↓
Cluster UUID established
        ↓
REMOVE cluster.initial_master_nodes
        ↓
Normal discovery/restart/rejoin lifecycle
```

After successful initial cluster formation, remove `cluster.initial_master_nodes` from every node and never configure it again for that existing cluster. It is not a restart setting, node-join setting, normal recovery setting, or full-cluster-restart setting.

## 9. Bootstrap Failure Anti-Pattern

If an existing production cluster suffers an infrastructure outage and nodes fail to discover their existing cluster, adding `cluster.initial_master_nodes` attacks the wrong problem. Investigate why the nodes cannot discover and rejoin their existing cluster. If cluster identity appears inconsistent, preserve evidence and stop ordinary maintenance.

## 10. Dynamic Configuration Audit

```bash
curl --cacert "$ES_CA" \
  -u "$ES_USER:$ES_PASSWORD" \
  "$ES_URL/_cluster/settings?flat_settings=true&include_defaults=true&pretty"
```

Review persistent, transient, and default settings. Prefer appropriately managed persistent dynamic settings when a cluster-wide dynamic change is required. Do not use transient settings as an informal configuration-management system.

## 11. Configuration Drift

Validate the full chain from approved design to Git/IaC/deployment definition, ConfigMap/Secret/host configuration, running Elasticsearch process, and effective runtime state. Configuration in Git is evidence of intent; effective runtime configuration is evidence of reality.

## 12. Domain 3 — Security

Production validation must prove authentication, HTTP TLS, transport TLS, certificate validation, negative authentication, negative trust behavior, and credential lifecycle regardless of whether security originated through automatic configuration, an operator, enterprise PKI, or another approved mechanism.

### 12.1 HTTP TLS

```bash
curl --cacert "$ES_CA" \
  -u "$ES_USER:$ES_PASSWORD" \
  "$ES_URL/"
```

The trusted request should succeed.

### 12.2 Negative TLS Test

From a controlled environment where the private CA is not otherwise trusted:

```bash
curl \
  -u "$ES_USER:$ES_PASSWORD" \
  "$ES_URL/"
```

TLS verification should fail. Do not add `-k` to make the negative test succeed.

### 12.3 Authentication

```bash
curl --cacert "$ES_CA" \
  -u "$ES_USER:deliberately-wrong-password" \
  -o /dev/null \
  -w "%{http_code}\n" \
  "$ES_URL/"
```

Expected result: HTTP `401`.

### 12.4 Transport TLS

HTTP TLS protects client-to-Elasticsearch communication. Transport security protects Elasticsearch node-to-node communication. Production must validate both, and transport certificate identity should match the actual node identities used for inter-node communication.

## 13. Domain 4 — Persistence

### 13.1 Verify PVC/PV Mapping

```bash
kubectl get pvc -n elasticsearch
kubectl get pv
```

Record the relationship from Elasticsearch Pod to PVC, PV, and storage backend. A `Bound` PVC is necessary, but not the complete persistence test.

## 14. Deterministic Validation Dataset

Before controlled restart validation, create a small synthetic index. This is a controlled state-changing operation.

```bash
curl --cacert "$ES_CA" \
  -u "$ES_USER:$ES_PASSWORD" \
  -X PUT \
  "$ES_URL/installation-validation-v1" \
  -H 'Content-Type: application/json' \
  -d '{
    "settings": {
      "number_of_shards": 3,
      "number_of_replicas": 1
    },
    "mappings": {
      "properties": {
        "patient_id": {"type": "keyword"},
        "event_type": {"type": "keyword"},
        "event_time": {"type": "date"}
      }
    }
  }'
```

Use synthetic data only.

## 15. Load Validation Data

```bash
curl --cacert "$ES_CA" \
  -u "$ES_USER:$ES_PASSWORD" \
  -X POST \
  "$ES_URL/_bulk?refresh=true" \
  -H 'Content-Type: application/x-ndjson' \
  --data-binary @validation-data.ndjson
```

Expected deterministic count: `4`.

```bash
curl --cacert "$ES_CA" \
  -u "$ES_USER:$ES_PASSWORD" \
  "$ES_URL/installation-validation-v1/_count?pretty"
```

## 16. Record the Pre-Restart Baseline

Capture cluster UUID, health, node count, master, node roles, shard state, document count, Pod UIDs, PVC UIDs, and PV names. This baseline becomes the comparison point for recovery validation.

## 17. Domain 5 — Resilience

Three Elasticsearch nodes do not automatically mean three Kubernetes workers, three availability zones, or three independent storage failure domains. If all three Elasticsearch Pods are scheduled on one Kubernetes worker, a worker failure can remove all three nodes simultaneously.

## 18. Failure-Domain Review

Production sign-off should examine Pod anti-affinity, topology spread, worker placement, availability-zone placement, storage topology, network dependencies, load-balancer dependencies, and N-1 capacity. DBRE/SRE must understand what happens when an actual infrastructure component disappears.

## 19. Domain 6 — Recovery

### Controlled Rolling Restart

A production restart is state-changing and requires maintenance/change controls.

```text
Precheck
   ↓
Restart ONE node
   ↓
Wait for Elasticsearch rejoin
   ↓
Validate approved recovery gate
   ↓
Verify cluster UUID
   ↓
Verify storage
   ↓
Verify validation data
   ↓
Only then continue
```

For this scenario, validate `elasticsearch-2`, then `elasticsearch-1`, then `elasticsearch-0`. Do not convert a rolling restart into an unreviewed simultaneous restart.

## 20. Approved Recovery Gate

For this use case, require expected node membership, same cluster UUID, GREEN health, zero unassigned shards, persistent storage continuity, and validation data count `4` before proceeding to the next node. Large production environments may use a deliberately tailored recovery gate; it must be explicitly defined rather than inferred from Kubernetes readiness.

## 21. Node Rejoin Validation

```bash
curl --cacert "$ES_CA" \
  -u "$ES_USER:$ES_PASSWORD" \
  "$ES_URL/_cat/nodes?v"
```

Confirm the node actually rejoined Elasticsearch, then check cluster health. Do not proceed solely because the Pod is Running or Ready.

## 22. Cluster Identity After Restart

```bash
curl --cacert "$ES_CA" \
  -u "$ES_USER:$ES_PASSWORD" \
  "$ES_URL/?pretty"
```

The UUID must match the baseline. If it does not, STOP and preserve evidence. Do not attempt force allocation, storage deletion, or bootstrap changes simply to make the environment look healthy.

## 23. Storage Continuity

For a recreated Kubernetes Pod, the Pod UID should change while the PVC UID and PV remain the same. This demonstrates that the Pod lifecycle and data lifecycle are intentionally separate.

## 24. Data Persistence

```bash
curl --cacert "$ES_CA" \
  -u "$ES_USER:$ES_PASSWORD" \
  "$ES_URL/installation-validation-v1/_count?pretty"
```

Expected count after every controlled restart: `4`. Successful container startup without expected data is not a successful recovery.

## 25. Runtime Bootstrap Verification

After restart, verify that the effective runtime configuration does not contain `cluster.initial_master_nodes`. The node must rejoin using persistent cluster state and normal discovery rather than repeating first-cluster bootstrap.

## 26. Snapshot and Restore Readiness

Production recovery readiness requires more than a configured snapshot repository. Required evidence includes a configured/reachable repository, successful snapshot, snapshot verification/inventory, documented restore procedure, successfully exercised restore, identified recovery owner, defined RPO and RTO, and retained restore evidence. A backup strategy that has never demonstrated restoration provides incomplete recovery assurance.

## 27. Domain 7 — Operations

Before production sign-off, establish operational ownership for cluster monitoring, alerting, logging, disk capacity and performance, JVM/heap, CPU, shard growth, query/indexing latency, thread-pool rejection, certificate expiration, snapshot failures, node loss, maintenance, upgrades, capacity planning, and incident response. Installation is finished when the service can be safely operated, not merely when the installer exits successfully.

## 28. Capacity and Failure Planning

Production validation should answer what happens if one data node, worker, or availability zone disappears; whether remaining nodes can absorb shards; whether CPU, heap, disk, and storage recovery performance are sufficient; how long shard recovery takes; and whether application traffic remains supportable during recovery. This is the difference between N-node capacity and N-1 operational capacity.

## 29. Monitoring Readiness

Monitor cluster health, node availability, disk utilization/latency/IOPS/throughput, heap pressure, GC, CPU, search and indexing latency, thread-pool queues/rejections, unassigned shards, shard size, snapshot success/failure, and certificate expiration. Monitoring must produce actionable alerts with ownership.

## 30. Upgrade Readiness

Never use an uncontrolled image reference such as `image: elasticsearch:latest`. Pin the approved release, for example:

```yaml
image: docker.elastic.co/elasticsearch/elasticsearch:9.5.3
```

Treat upgrades as an explicit lifecycle: compatibility review, upgrade plan, recovery readiness, staging validation, maintenance/change approval, controlled upgrade, and post-upgrade validation.

## 31. Final Validation Gate

```bash
curl --cacert "$ES_CA" \
  -u "$ES_USER:$ES_PASSWORD" \
  "$ES_URL/_cluster/health/installation-validation-v1?wait_for_status=green&timeout=120s&pretty"
```

Required: `status = green` and `unassigned_shards = 0`.

```bash
curl --cacert "$ES_CA" \
  -u "$ES_USER:$ES_PASSWORD" \
  "$ES_URL/installation-validation-v1/_count?pretty"
```

Required: `count = 4`.

```bash
curl --cacert "$ES_CA" \
  -u "$ES_USER:$ES_PASSWORD" \
  "$ES_URL/_cat/nodes?v"
```

Required: expected node count `3`. Also verify the cluster UUID still equals the recorded baseline.

## 32. Production Readiness Matrix

| Domain | Validation | Required |
|---|---|---|
| Identity | Approved Elasticsearch version | PASS |
| Identity | Expected cluster name | PASS |
| Identity | Stable cluster UUID | PASS |
| Identity | Expected nodes joined | PASS |
| Identity | Master election | PASS |
| Identity | Expected node roles | PASS |
| Configuration | OS prerequisites | PASS |
| Configuration | Runtime file descriptors | PASS |
| Configuration | JVM/runtime review | PASS |
| Configuration | Discovery | PASS |
| Configuration | Bootstrap setting removed | PASS |
| Configuration | Dynamic settings audit | PASS |
| Configuration | Drift review | PASS |
| Security | Authentication | PASS |
| Security | Invalid authentication | 401 |
| Security | HTTP TLS | PASS |
| Security | Untrusted TLS | FAIL as expected |
| Security | Transport TLS | PASS |
| Persistence | PVC/PV mapping | PASS |
| Persistence | Storage continuity | PASS |
| Persistence | Validation data | 4/4 |
| Resilience | Shard placement | PASS |
| Resilience | Worker placement | PASS |
| Resilience | Failure-domain review | PASS |
| Resilience | N-1 capacity review | PASS |
| Recovery | Rolling restart | PASS |
| Recovery | Node rejoin | PASS |
| Recovery | UUID continuity | PASS |
| Recovery | Snapshot | PASS |
| Recovery | Tested restore | PASS |
| Recovery | RPO/RTO | DEFINED |
| Operations | Monitoring | READY |
| Operations | Alerting | READY |
| Operations | Maintenance | READY |
| Operations | Upgrade procedure | READY |
| Operations | Incident ownership | READY |
| Final | Cluster health | GREEN |
| Final | Unassigned shards | 0 |
| Final | Validation documents | 4 |

A failed mandatory gate prevents production sign-off until the exception is understood and formally handled.

## 33. Production Sign-Off Evidence

A final evidence package should allow another engineer to independently understand why the cluster was approved. It can include cluster identity/health, nodes/shards/runtime/settings, Kubernetes Pod/PVC/PV state, security validation, restart/storage/snapshot/restore validation, capacity review, and sign-off records. Do not include passwords, private keys, tokens, real patient information, or reusable secrets.

## 34. Findings from the Scenario

1. Pod readiness was incorrectly treated as cluster readiness.
2. Elasticsearch topology was confused with infrastructure topology.
3. Bootstrap configuration required explicit lifecycle control: bootstrap once, remove the setting, never reuse it for the existing cluster.
4. Security needed negative validation: wrong credentials and untrusted TLS must be rejected.
5. Persistence needed failure testing: new Pod + same PVC/PV + same cluster UUID + same validation data.
6. Backup configuration was not recovery proof; recovery required a tested restore, ownership, RPO, RTO, and retained evidence.

## 35. Root Cause

There was no Elasticsearch software incident. The root cause was an incomplete production-readiness model. The corrected model is:

```text
Identity
    +
Configuration
    +
Security
    +
Persistence
    +
Resilience
    +
Recovery
    +
Operations
    =
Production Readiness
```

## 36. DBRE/SRE Lessons

**Production readiness must be demonstrated through failure and recovery behavior, not inferred from startup behavior.** A cluster may start perfectly and still fail during Pod recreation, worker maintenance, node replacement, storage reattachment, certificate rotation, network disruption, rolling upgrade, availability-zone failure, or full infrastructure restart.

Two separate questions must therefore be answered: Can Elasticsearch start? And can Elasticsearch safely survive its expected operational lifecycle? Production DBRE/SRE ownership is primarily concerned with making the second answer defensible.

## 37. Relationship to Hands-On Lab 02

Tutorial 02 explains production installation. Hands-On Lab 02 builds and validates it. Real-World Use Case 02 adds the operational decision layer: observe, question assumptions, collect evidence, validate failure domains, exercise recovery, evaluate production gates, and approve or reject production readiness.

## 38. Official Elastic References

- Important system configuration: https://www.elastic.co/docs/deploy-manage/deploy/self-managed/important-system-configuration
- Discovery and cluster formation settings: https://www.elastic.co/docs/reference/elasticsearch/configuration-reference/discovery-cluster-formation-settings
- Bootstrapping a cluster: https://www.elastic.co/docs/deploy-manage/distributed-architecture/discovery-cluster-formation/modules-discovery-bootstrap-cluster
- Set up basic security: https://www.elastic.co/docs/deploy-manage/security/set-up-basic-security
- Set up HTTPS: https://www.elastic.co/docs/deploy-manage/security/set-up-basic-security-plus-https
- Cluster health API: https://www.elastic.co/docs/api/doc/elasticsearch/operation/operation-cluster-health

## 39. Canonical Acceptance

**Technical + Source Review:** PASS  
**Production Review:** PASS  
**Copyright / Originality Review:** PASS  
**Blocking findings:** 0  
**Edition:** REVISED FINAL / CANONICAL  
**Repository state:** CANONICAL / COMMITTED / VERIFIED

```text
Tutorial 02
    → CANONICAL / COMMITTED / VERIFIED

Hands-On Lab 02
    → CANONICAL / COMMITTED / VERIFIED

Real-World Use Case 02
    → CANONICAL / COMMITTED / VERIFIED
```
