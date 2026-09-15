# Tutorial 02 — Elasticsearch Production Installation & Configuration

**Track:** Elasticsearch Administrator / DBRE / SRE  
**Edition:** Revised Final / Canonical  
**Reference Elasticsearch:** 9.5.x  
**Status:** CANONICAL / COMMITTED / VERIFIED

## 1. Purpose

Starting Elasticsearch is not the same as creating a production-ready Elasticsearch cluster.

A production installation requires infrastructure, operating-system or Kubernetes prerequisites, CPU, memory, storage, networking, JVM behavior, Elasticsearch node configuration, discovery, initial bootstrap, security, persistent cluster state, shard allocation, restart/rejoin behavior, failure validation, and production-readiness verification to work together.

```text
Infrastructure
      ↓
Operating System / Kubernetes
      ↓
CPU + Memory + Storage + Network
      ↓
JVM
      ↓
Elasticsearch Process
      ↓
Node Configuration
      ↓
Discovery
      ↓
Initial Cluster Bootstrap
      ↓
Security
      ↓
Persistent Cluster State
      ↓
Shard Allocation
      ↓
Restart / Rejoin
      ↓
Failure Validation
      ↓
Production Readiness
```

The Administrator/DBRE/SRE objective is a secure, persistent, recoverable, observable, capacity-aware, failure-tested, and operationally safe Elasticsearch installation—not merely a running process.

## 2. Production safety classification

### READ-ONLY / DIAGNOSTIC

Examples include `GET /`, `GET /_cluster/health`, `GET /_cat/nodes`, `GET /_cat/master`, `GET /_cat/shards`, `GET /_nodes/stats`, and `GET /_cluster/settings`.

### STATE-CHANGING — REVIEW REQUIRED

Examples include restarting Elasticsearch, deleting/recreating a pod, changing replicas or cluster settings, rotating certificates, modifying node roles, changing discovery configuration, and changing JVM settings. Before a change, record the current state, expected effect, risk, rollback, and verification plan.

### HIGH-RISK / RECOVERY OR DATA-LOSS RISK

Examples include deleting an Elasticsearch data path, destroying persistent volumes, bootstrapping an existing cluster, forcing stale-primary allocation, destructive reroute operations, and replacing storage without recovery validation. These require a deliberate recovery/DR process.

## 3. Deployment models

Self-managed Elasticsearch can run on Linux VM/bare metal through RPM, DEB, or archive distributions, and in containers through Docker or Kubernetes. Kubernetes does not remove Elasticsearch's operating-system, storage, JVM, networking, or distributed-system requirements; it changes how they are delivered.

| Linux / VM | Kubernetes |
|---|---|
| process | container |
| systemd | controller/kubelet |
| host | worker |
| filesystem | persistent volume |
| hostname | pod identity |
| DNS | Kubernetes DNS |
| service restart | pod/controller reconciliation |

## 4. Pre-installation engineering

Do not begin production sizing with “How many Elasticsearch nodes do we need?” Establish the workload first.

Review search/write mix, analytics/vector/observability requirements, current data volume, daily ingestion, retention, replicas, 3/6/12-month growth, requests per second, concurrency, page sizes, aggregations, sorting, pagination, query fan-out, latency SLOs, write rates, bulk size/concurrency, refresh requirements, update/delete frequency, CPU, RAM, disk capacity, IOPS, throughput, latency, network bandwidth, failure domains, maintenance, recovery traffic, and N-1 requirements.

The production question is: **What infrastructure is required to sustain the expected workload while retaining acceptable service during the intended failure conditions?**

## 5. Dedicated resources

Elasticsearch should normally be the primary resource-intensive workload on its host or container. Avoid uncontrolled competition with Kafka, databases, heavy Logstash, or application workloads unless resource isolation and capacity have been deliberately engineered.

## 6. Service identity

Elasticsearch must not run as `root`. Use an unprivileged Elasticsearch service identity with only the permissions required for configuration, data, logs, certificates, plugins, and snapshot repository paths. Where shared filesystems are involved, consistent numeric UID/GID ownership across participating hosts can be important.

## 7. Linux production prerequisites

Important host settings include `vm.max_map_count`, file descriptors, thread limits, swap behavior, memory locking, filesystem permissions, clock synchronization, and network failure detection. Production bootstrap checks are safety controls. Fix the unsafe prerequisite rather than bypassing the check.

## 8. `vm.max_map_count`

For this Elasticsearch 9.5.x production track, standardize on:

```text
vm.max_map_count = 1048576
```

Check:

```bash
sysctl vm.max_map_count
```

Temporary host change:

```bash
sudo sysctl -w vm.max_map_count=1048576
```

Manage the setting persistently through the operating-system or node-management mechanism.

## 9. Kubernetes and `vm.max_map_count`

```text
Elasticsearch Pod
       ↓
Linux Kernel
       ↓
Kubernetes Worker
       ↓
vm.max_map_count
```

A pod does not automatically correct the worker kernel. Depending on the platform, manage the prerequisite through worker/node provisioning, supported node configuration, a DaemonSet, privileged init mechanism, or platform-specific configuration.

## 10. Do not normalize disabling mmap

Do not routinely work around an incorrectly configured production worker with:

```yaml
node.store.allow_mmap: false
```

Correct the host/kernel prerequisite and preserve normal Elasticsearch mmap behavior.

## 11. File descriptors

Production Linux environments should provide at least 65,535 file descriptors. Check the shell with `ulimit -n`, but verify what Elasticsearch actually received:

```bash
curl --cacert "$ES_CA" \
  -u "$ES_USER:$ES_PASSWORD" \
  "$ES_URL/_nodes/stats/process?filter_path=**.max_file_descriptors&pretty"
```

Shell configuration is not proof of the running Elasticsearch process configuration.

## 12. Thread limits

Elasticsearch creates threads for search, write, management, transport, refresh, flush, merge, snapshot, and recovery. When administrators manage OS limits themselves, permit the Elasticsearch service identity to create at least 4096 threads. Verify the running process rather than assuming an interactive-shell limit applies.

## 13. Swap

Unexpected swapping can cause severe Elasticsearch latency. Prevent Elasticsearch process memory from being swapped under production workload while retaining enough host/container memory for heap, native memory, filesystem cache, and OS requirements. Depending on the environment, this may involve disabling swap, reducing swappiness, appropriate memory locking, and correct memory sizing. `bootstrap.memory_lock` is not a substitute for capacity engineering.

## 14. Clock synchronization

Production Elasticsearch hosts should use an appropriate clock-synchronization service. Clock problems complicate incident timelines, log correlation, certificate validation, monitoring, and distributed-system diagnosis.

## 15. Network failure detection

Review OS TCP failure-detection settings, including retransmission behavior such as `net.ipv4.tcp_retries2`. Changes must be tested with the network/platform team rather than copied blindly. The objective is predictable failure detection appropriate to the environment.

## 16. Storage architecture

Elasticsearch storage must be evaluated for capacity, IOPS, throughput, latency, queue depth, filesystem behavior, recovery performance, and failure characteristics. Disk capacity alone is not storage performance. Indexing, Lucene segment merges, searches, and shard recovery can all generate substantial storage I/O.

## 17. Data-path architecture

Treat Elasticsearch software and Elasticsearch data as different lifecycle objects. For containers, the container is disposable process infrastructure while the persistent volume carries Elasticsearch state. Recreating a pod should not inherently destroy Elasticsearch data.

## 18. Persistent-storage deletion warning

Never assume namespace deletion means cloud storage has been physically destroyed. Verify PVCs, PVs, StorageClass, `reclaimPolicy`, the actual cloud/storage backend, and snapshot state. Cleanup validation must account for `Delete` versus `Retain` behavior.

## 19. JVM memory architecture

Host/container memory includes JVM heap, JVM native memory, direct buffers, thread stacks, memory-mapped files, Elasticsearch/Lucene native requirements, and filesystem cache. An 8-GB container does not imply an 8-GB heap.

## 20. Automatic heap sizing

Modern Elasticsearch automatically sizes JVM heap based on available resources and node roles. Prefer automatic sizing unless a justified reason exists to override it. Do not blindly copy legacy settings such as `-Xms31g` and `-Xmx31g`. Manual sizing must consider heap, native/off-heap memory, filesystem cache, and host/container overhead together.

## 21. `OOMKilled` versus Java heap OOM

In Kubernetes, `OOMKilled` means the container/cgroup was terminated because of a memory condition. It does not automatically prove Java heap exhaustion. Investigate heap, old generation, GC, native memory, direct buffers, thread stacks, mmap, container limits, node memory, and workload before assigning root cause.

## 22. Bundled JVM

Use the JVM bundled with Elasticsearch unless there is a documented and tested reason to use another supported JVM. This minimizes compatibility, version, support, and security-lifecycle risk.

## 23. Configuration hierarchy

The primary node configuration file is `elasticsearch.yml`. Use it primarily for node-specific/static settings and settings required before the node joins, including cluster/node identity, roles, network settings, discovery, data paths, and TLS configuration. Static changes normally require restart of the affected node.

## 24. Dynamic cluster settings

Dynamic cluster-wide settings should normally be changed through the Cluster Update Settings API when supported. Prefer persistent settings; do not routinely use transient settings for production configuration. For every production setting change record the setting, old/new values, reason, owner, timestamp, expected effect, rollback, and verification.

## 25. Cluster name

Use an environment-specific cluster identity, for example:

```yaml
cluster.name: healthcare-search-prod
```

Avoid ambiguous names such as `cluster1`, `test`, or `elasticsearch`.

## 26. Node identity

Use stable, meaningful node names such as `es-master-01`, `es-data-01`, or Kubernetes StatefulSet identities such as `elasticsearch-0`. Stable identity helps correlate logs, metrics, shards, storage, incidents, and recovery.

## 27. Modern node roles

Relevant roles include `master`, `data`, `data_content`, `data_hot`, `data_warm`, `data_cold`, `data_frozen`, `ingest`, `ml`, `remote_cluster_client`, `transform`, and `voting_only`. Role design depends on architecture. If `node.roles` is explicitly configured, retain the roles required for cluster operation and workload; do not remove roles merely to make nodes appear more dedicated.

## 28. Networking architecture

Elasticsearch has two important communication planes: HTTP(S) for applications/administrators and transport for Elasticsearch node-to-node communication. Secure and troubleshoot them separately.

## 29. Bind and publish addresses

A bind address determines where Elasticsearch listens. A publish address tells other participants where the node can be reached. This distinction matters with multiple NICs, NAT, containers, Kubernetes, and cloud networking. A node can listen successfully yet publish an unreachable address.

## 30. Production network configuration

Do not normalize `network.host: 0.0.0.0` as the default production example. Use an address or hostname appropriate to the environment, such as:

```yaml
network.host: es-data-01.example.internal
```

Wildcard binding can be legitimate, but bind and publish behavior must be deliberately understood.

## 31. Discovery

Nodes need a way to find candidate master-eligible peers:

```yaml
discovery.seed_hosts:
  - es-master-01.example.internal
  - es-master-02.example.internal
  - es-master-03.example.internal
```

`discovery.seed_hosts` is a discovery starting point, not permanent cluster membership.

## 32. Bootstrap versus discovery

Discovery asks: **Where are candidate master-eligible nodes?** Bootstrap asks: **Which master-eligible nodes may establish the first voting configuration of this brand-new cluster?**

| Setting | Purpose |
|---|---|
| `discovery.seed_hosts` | discovery |
| `cluster.initial_master_nodes` | first bootstrap only |

## 33. Initial cluster bootstrap

A brand-new cluster has no existing cluster state, elected master, or voting configuration. For first formation, the initial master-eligible set may be configured:

```yaml
cluster.initial_master_nodes:
  - es-master-01
  - es-master-02
  - es-master-03
```

Node names must match the intended master-eligible identities. Bootstrap is a one-time cluster-formation operation.

## 34. Critical bootstrap rule

After the cluster successfully forms, **remove `cluster.initial_master_nodes` from normal runtime configuration**. Do not use it for node/pod restarts, VM reboot, rolling restart, replacement node, node rejoin, or full-cluster restart.

```text
BRAND-NEW CLUSTER
No cluster state
      ↓
cluster.initial_master_nodes
      ↓
Initial bootstrap
      ↓
Cluster forms
      ↓
Persistent cluster state exists
      ↓
REMOVE bootstrap configuration
```

Later:

```text
EXISTING CLUSTER
Persistent cluster state
      ↓
Discovery
      ↓
Existing cluster found
      ↓
Node rejoins
```

## 35. Bootstrap misuse — HIGH RISK

Reintroducing bootstrap configuration into an existing cluster can lead to an unintended separate cluster. Separately formed Elasticsearch clusters cannot simply be merged. If cluster identity is unexpected: STOP, preserve data paths/logs/configuration, investigate, and enter the recovery/DR decision path. Do not delete data paths merely to force nodes to join.

## 36. Security defaults

Modern Elasticsearch includes automatic security configuration for applicable first-start scenarios, including HTTP TLS, transport TLS, CA/certificates, superuser credential workflow, and Kibana enrollment. Do not teach `xpack.security.enabled: false` as the standard production installation method.

## 37. Package credential nuance

Security bootstrap behavior differs by installation method. For RPM/DEB deployments, do not assume the `elastic` password is printed exactly as in every other flow. Use the supported password-management/reset procedure for the deployment method.

## 38. Transport TLS

Transport TLS protects cluster coordination, cluster state, shard operations, replication, recovery, and node communication. A secured multi-node production cluster requires correct transport security. Do not work around transport TLS failures by disabling security.

## 39. HTTP TLS

Standard shell setup:

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

Do not normalize `curl -k` as production practice.

## 40. Certificate lifecycle

Production requirements include certificate ownership, expiration monitoring, renewal, rotation, SAN validation, trust-chain management, keystore permissions, rollback, and post-rotation verification. Certificate expiration can become an Elasticsearch availability incident.

## 41. Kubernetes reference architecture

```text
                 Client Service
                      │
         ┌────────────┼────────────┐
         │            │            │
      ES Pod 0     ES Pod 1     ES Pod 2
         │            │            │
       PVC 0        PVC 1        PVC 2
         │            │            │
         └──── Persistent Storage ─┘

              Headless Service
                     │
              Node Discovery
```

Core objects include Namespace, ConfigMap, Secret, Service, Headless Service, StatefulSet, PVC, and StorageClass.

## 42. Why StatefulSet?

Elasticsearch nodes benefit from stable pod identity, stable DNS, stable persistent-storage association, and predictable ordinal identity. A StatefulSet is therefore a useful primitive for the manually managed educational cluster.

## 43. Pod count is not infrastructure HA

Three Elasticsearch pods do not automatically represent three independent failure domains. Three pods on one worker provide three Elasticsearch processes, not three worker-node failure domains. Production HA requires deliberate distribution across workers, hosts, zones, or other intended failure domains.

## 44. Pod restart and persistent state

Expected model:

```text
Pod disappears
      ↓
StatefulSet recreates pod
      ↓
Persistent storage reattached
      ↓
Existing Elasticsearch state found
      ↓
Node discovers existing cluster
      ↓
Node rejoins
```

Do not destroy the data path as a normal restart procedure.

## 45. Kubernetes resources and JVM

Container memory must account for JVM heap plus native/off-heap memory, direct buffers, thread stacks, mmap, and other process memory. JVM heap approximately equal to the container limit is unsafe architecture. Container limits, JVM sizing, node capacity, and workload must be designed together.

## 46. Probe design

Do not use `Cluster != GREEN → kill Elasticsearch` as a simplistic liveness strategy. Process alive, Elasticsearch responding, node participation, primary availability, and full cluster redundancy are different health questions. A YELLOW cluster can have all primaries available while replica redundancy is degraded.

## 47. Initial validation — cluster identity

Do not declare success because `systemctl status elasticsearch` or `kubectl get pods` shows Running. Validate Elasticsearch:

```bash
curl --cacert "$ES_CA" \
  -u "$ES_USER:$ES_PASSWORD" \
  "$ES_URL/?pretty"
```

Record `cluster_name`, `cluster_uuid`, and version.

## 48. Validate node membership

```bash
curl --cacert "$ES_CA" \
  -u "$ES_USER:$ES_PASSWORD" \
  "$ES_URL/_cat/nodes?v"
```

Three Kubernetes pods are not proof of three Elasticsearch cluster members.

## 49. Validate master election

```bash
curl --cacert "$ES_CA" \
  -u "$ES_USER:$ES_PASSWORD" \
  "$ES_URL/_cat/master?v"
```

Confirm an expected master exists. If no master exists, investigate coordination before assuming ordinary shard behavior.

## 50. Validate cluster health

```bash
curl --cacert "$ES_CA" \
  -u "$ES_USER:$ES_PASSWORD" \
  "$ES_URL/_cluster/health?pretty"
```

- **GREEN:** all desired primary and replica shards assigned.
- **YELLOW:** all primaries assigned, one or more replicas unassigned.
- **RED:** one or more primary shards unassigned and some data may be unavailable.

## 51. Validate shards

```bash
curl --cacert "$ES_CA" \
  -u "$ES_USER:$ES_PASSWORD" \
  "$ES_URL/_cat/shards?v"
```

Inspect primary/replica role, STARTED, INITIALIZING, RELOCATING, UNASSIGNED, and node placement. Running processes do not guarantee healthy distributed state.

## 52. Restart/rejoin validation

A production installation should be tested through at least one representative controlled restart/rejoin path in a suitable non-production environment.

```text
Node leaves
   ↓
Cluster detects loss
   ↓
Replica promotion if required
   ↓
Node returns
   ↓
Existing persistent state found
   ↓
Node rejoins SAME cluster
   ↓
Recovery proceeds
   ↓
Cluster stabilizes
```

Verify cluster UUID before/after, expected membership, persistent data, shard recovery, and absence of unexpected bootstrap.

## 53. Persistent-storage validation

Use `kubectl get pvc` and verify Bound state, expected capacity, StorageClass, access mode, and pod association. After controlled pod recreation, verify persistent data remains available. Where relevant, also verify PV and the actual cloud/storage backend.

## 54. Authentication validation

Test valid credentials with CA validation and separately verify invalid credentials are rejected. Security validation requires more than proving TCP/9200 is reachable; validate TLS, certificate trust, authentication, and authorization as appropriate.

## 55. Configuration-drift validation

Compare Elasticsearch version, JVM, node roles, kernel prerequisites, file descriptors, thread limits, storage, TLS, certificate expiry, discovery configuration, bootstrap configuration, and dynamic cluster settings across nodes. A single misconfigured node can create a future incident during restart, recovery, or failover.

## 56. Snapshot readiness

Production installation readiness includes a recovery strategy. Validate that the snapshot repository exists and is reachable, a snapshot succeeds and is visible, retention/ownership is defined, a restore procedure exists, and representative restore testing is planned or completed. Repository configuration alone is not proof of recoverability.

## 57. N-1 capacity

Engineer the cluster so an expected single failure does not immediately overload the surviving system. N-1 is an engineering principle, not a universal fixed CPU, heap, or disk percentage. Evaluate workload, roles, shard topology, recovery traffic, storage, network, failure domain, and SLO.

## 58. Common unsafe installation patterns

Avoid normalizing latest container tags, root execution, disabled security, `curl -k`, ephemeral data, inadequately sized OS storage, capacity planning by TB alone, all RAM assigned to heap, ignored swap or mmap prerequisites, `node.store.allow_mmap:false` as a production workaround, low file-descriptor limits, incorrect publish addresses/seed hosts, permanent or reused `cluster.initial_master_nodes`, blindly copied legacy JVM settings, GREEN-based liveness restart loops, repeated pod deletion during diagnosis, untracked transient settings, allocation changes without evidence, missing TLS lifecycle, unvalidated snapshots, and lack of N-1 planning.

## 59. Production readiness checklist

Before allowing application traffic:

```text
[ ] Exact Elasticsearch version pinned
[ ] Supported deployment model selected

HOST / PLATFORM
[ ] Dedicated/isolated resources reviewed
[ ] CPU and memory capacity reviewed
[ ] vm.max_map_count = 1048576
[ ] mmap production behavior preserved
[ ] file descriptors and thread limits validated
[ ] swap policy validated
[ ] clock synchronization validated
[ ] network failure-detection behavior reviewed

STORAGE
[ ] persistent storage configured
[ ] capacity, IOPS, throughput, latency, filesystem reviewed
[ ] reclaim behavior understood

JVM
[ ] bundled JVM/default runtime strategy reviewed
[ ] automatic heap sizing reviewed
[ ] container/host memory headroom reviewed

CLUSTER CONFIGURATION
[ ] cluster.name and node names correct
[ ] node roles correct
[ ] network bind/publish correct
[ ] discovery correct

BOOTSTRAP
[ ] initial cluster formation successful
[ ] expected cluster UUID recorded
[ ] cluster.initial_master_nodes removed
[ ] bootstrap configuration absent from normal runtime config

SECURITY
[ ] security enabled
[ ] HTTP and transport TLS validated
[ ] certificate trust and authentication validated
[ ] authorization model reviewed
[ ] certificate expiration monitoring and rotation documented

CLUSTER
[ ] expected nodes joined
[ ] master elected
[ ] health understood
[ ] shard placement validated
[ ] no unexplained unassigned shards

RESILIENCE
[ ] controlled restart/rejoin tested
[ ] persistent data verified
[ ] N-1 capacity reviewed
[ ] failure-domain topology reviewed

RECOVERY
[ ] snapshot repository validated
[ ] successful snapshot confirmed
[ ] restore procedure documented
[ ] representative restore test planned/completed

OPERATIONS
[ ] monitoring and alerting defined
[ ] configuration-drift checks defined
[ ] operational runbook available
[ ] escalation ownership defined
```

## 60. Responsibility model

**Platform / Infrastructure** owns or co-owns VM/Kubernetes, workers, network, DNS, load balancers, storage, host OS, kernel, and cloud infrastructure.

**Elasticsearch Administrator / DBRE / SRE** owns or governs cluster architecture, roles, JVM strategy, Elasticsearch configuration, discovery, bootstrap safety, security integration, storage requirements, validation, shard behavior, capacity, monitoring, recovery readiness, and production readiness.

**Application / Data Team** owns business data semantics, application queries, ingestion requirements, client concurrency, timeouts, and retry behavior.

**Shared responsibilities** include mapping design, query performance, load testing, capacity planning, SLOs, production readiness, and incident response.

## 61. Lab 02 implementation direction

Hands-On Lab 02 should implement:

```text
Kubernetes worker prerequisites
          ↓
Namespace
          ↓
Persistent storage
          ↓
TLS / credentials
          ↓
Elasticsearch configuration
          ↓
Headless discovery
          ↓
StatefulSet
          ↓
Three-node initial bootstrap
          ↓
Cluster formation
          ↓
Record cluster UUID
          ↓
Remove bootstrap setting
          ↓
Restart/rejoin test
          ↓
Verify same cluster UUID
          ↓
Verify persistent data
          ↓
Security validation
          ↓
Configuration audit
          ↓
Production-readiness evidence
```

The implementation must distinguish three Elasticsearch pods from three infrastructure failure domains unless the topology actually provides the latter.

## 62. Final production mental model

```text
Process started
     ↓
Node configured correctly
     ↓
Node discovered peers
     ↓
Cluster bootstrapped correctly
     ↓
Bootstrap configuration removed
     ↓
Security validated
     ↓
Persistent storage validated
     ↓
Cluster identity recorded
     ↓
Shard state validated
     ↓
Restart/rejoin validated
     ↓
Recovery path validated
     ↓
Capacity/failure model validated
     ↓
Production ready
```

**Core lesson:** A production Elasticsearch installation is a validated distributed system, not merely a running Elasticsearch process.

## Canonical review state

- Revised Draft: PASS
- Technical + Source Review: PASS — corrections incorporated
- Production + Copyright Review: PASS — corrections incorporated
- Production safety model: PASS
- Bootstrap safety: PASS
- Security/TLS: PASS
- JVM/OS configuration: PASS
- Kubernetes operational model: PASS
- Storage/persistence: PASS
- Restart/rejoin model: PASS
- Recovery readiness: PASS
- Copyright/originality: PASS
