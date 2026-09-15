# Hands-On Lab 02 — Elasticsearch Production Installation & Configuration

**Module:** 02 — Production Installation & Configuration  
**Track:** Elasticsearch Administrator / DBRE / SRE  
**Reference Elasticsearch:** 9.5.3  
**Primary Platform:** Kubernetes  
**Edition:** Revised Final / Canonical  
**Status:** CANONICAL / COMMITTED / VERIFIED  
**Prerequisites:** Tutorial 02 and Hands-On Lab 01

---

## 1. Purpose

This lab turns the production-installation principles from Tutorial 02 into a reproducible Kubernetes implementation. The goal is not merely to make three Elasticsearch Pods report `Running`. The goal is to prove that the Elasticsearch cluster is correctly installed, securely configured, persistently stored, bootstrapped exactly once, able to restart and rejoin without forming a different cluster, and able to preserve data through Pod recreation.

The lab follows this production-readiness chain:

```text
Kubernetes worker prerequisites
  → persistent storage
  → TLS and credentials
  → Elasticsearch configuration
  → discovery
  → one-time cluster bootstrap
  → three-node cluster formation
  → record cluster UUID
  → remove bootstrap configuration
  → restart/rejoin each node
  → verify the same cluster UUID
  → verify persistent data
  → security validation
  → runtime/configuration audit
  → evidence capture
  → cleanup verification
```

A successful Kubernetes rollout is therefore only one input to the validation. It is not the success criterion.

---

## 2. Learning Outcomes

After completing the lab, an Administrator, DBRE, or SRE should be able to:

1. Prepare a Kubernetes environment for Elasticsearch memory mapping requirements.
2. Deploy Elasticsearch 9.5.3 without using an unpinned `latest` image.
3. Use persistent volumes rather than ephemeral Elasticsearch data storage.
4. Configure discovery and understand the difference between discovery and first-cluster bootstrap.
5. Bootstrap a brand-new cluster once and remove `cluster.initial_master_nodes` afterward.
6. Keep Elasticsearch security enabled and validate HTTPS authentication and CA trust.
7. Use separate HTTP TLS identity and per-node transport identities.
8. Validate cluster identity with the cluster UUID before and after node recreation.
9. Demonstrate that Pod recreation does not replace the node's persistent volume.
10. Audit runtime roles, JVM/process information, file-descriptor capacity, and cluster settings.
11. Capture sanitized evidence suitable for review without publishing credentials or private keys.
12. Clean up the disposable environment while explicitly observing Kubernetes PV/PVC reclaim behavior.

---

## 3. Scope Boundary

This is a production-oriented training lab, not a claim that a single local Kubernetes worker provides production infrastructure high availability.

The lab validates:

- Elasticsearch process isolation across three Pods;
- cluster formation and discovery;
- master election and cluster-state persistence;
- persistent data volumes;
- TLS and authentication;
- transport identity between Elasticsearch nodes;
- one-time bootstrap lifecycle;
- rolling Pod recreation and node rejoin;
- cluster UUID continuity;
- data persistence;
- runtime configuration and resource evidence.

A three-Pod Elasticsearch cluster on one `kind` worker does **not** prove availability-zone, Kubernetes-worker, host, storage-backend, or regional fault tolerance. Production deployments must place failure domains deliberately and validate the actual infrastructure topology.

---

## 4. Safety Classification

### Read-only / diagnostic

Examples include:

- cluster identity and health APIs;
- node and shard inspection;
- JVM and process statistics;
- Kubernetes Pod/PVC/PV inspection;
- reading the effective Elasticsearch configuration;
- bounded validation searches and document counts.

### State-changing — lab controlled

Examples include:

- creating the namespace, Secrets, ConfigMaps, Services, StatefulSet, and PVCs;
- creating the synthetic validation index;
- replacing the bootstrap ConfigMap with the runtime ConfigMap;
- deleting one Elasticsearch Pod at a time to validate restart/rejoin behavior;
- deleting the disposable namespace during cleanup.

These actions are appropriate for this isolated lab. They must not be copied into a production incident without production change controls, evidence, rollback planning, and ownership approval.

### High-risk operations intentionally excluded

This lab does not teach or normalize:

- disabling Elasticsearch security;
- `curl -k` / `--insecure`;
- deleting production indices;
- force allocation or stale-primary allocation;
- lowering replicas simply to make health green;
- changing allocation settings without evidence;
- using `cluster.initial_master_nodes` on an existing cluster;
- deleting production PVCs/PVs as a troubleshooting shortcut.

---

## 5. Repository Layout

```text
lab-002-production-installation-configuration/
├── README.md
├── data/
│   └── validation.ndjson
├── manifests/
│   ├── 00-namespace.yaml
│   ├── 01-headless-service.yaml
│   ├── 02-client-service.yaml
│   ├── 03-configmap-bootstrap.yaml
│   ├── 04-secret-example.yaml
│   ├── 05-statefulset.yaml
│   └── 06-configmap-runtime.yaml
└── scripts/
    ├── cleanup.sh
    ├── generate-tls.sh
    ├── preflight.sh
    ├── restart-rejoin-test.sh
    ├── sanitize-evidence.sh
    ├── transition-runtime.sh
    ├── validate-index.sh
    └── validate-runtime.sh
```

The CI implementation is defined in:

```text
.github/workflows/elasticsearch-lab-002-validation.yml
```

---

## 6. Version and Kernel Prerequisites

The reference container image is pinned to:

```text
docker.elastic.co/elasticsearch/elasticsearch:9.5.3
```

Do not replace the reference image with `latest` in a reproducible or production workflow.

The lab requires:

```text
vm.max_map_count=1048576
```

The CI harness validates this on the GitHub runner and the `kind` Kubernetes node before Elasticsearch deployment.

The lab intentionally does not use `node.store.allow_mmap: false` as a workaround. The environment is prepared for Elasticsearch rather than weakening the storage/mmap model to accommodate an incorrectly prepared host.

---

## 7. Kubernetes Service Architecture

The deployment uses two Services.

### Headless discovery Service

The headless Service provides stable StatefulSet DNS identities used by Elasticsearch discovery and transport communication. `publishNotReadyAddresses: true` is intentional for peer discovery during cluster formation.

### Client Service

The client Service exposes the Elasticsearch HTTP endpoint inside Kubernetes. CI uses a local `kubectl port-forward` for controlled validation from the runner.

HTTP traffic uses port `9200`. Elasticsearch transport communication uses port `9300`.

---

## 8. Persistent Storage

Each StatefulSet ordinal receives its own PVC:

```text
data-elasticsearch-0
data-elasticsearch-1
data-elasticsearch-2
```

The reference lab uses `ReadWriteOnce` for portability across common Kubernetes storage implementations.

During restart/rejoin validation the harness records:

- original Pod UID;
- PVC UID;
- backing PV name.

After Pod recreation it requires:

- a new Pod UID;
- the same PVC UID;
- the same PV name.

This distinction is fundamental:

```text
Pod identity may be recreated
        ≠
persistent Elasticsearch data may be replaced
```

Production storage classes, CSI behavior, topology, IOPS, latency, reclaim policy, snapshots, and recovery design require separate production validation.

---

## 9. TLS and Authentication

Elasticsearch security remains enabled throughout the lab.

The implementation generates a disposable lab CA and TLS material. It uses:

- an HTTP certificate for the HTTPS endpoint;
- per-node transport certificates for `elasticsearch-0`, `elasticsearch-1`, and `elasticsearch-2`;
- transport hostname verification with `verification_mode: full`;
- certificate SANs matching the Kubernetes DNS identities used by the nodes;
- localhost/127.0.0.1 SAN coverage for the controlled CI port-forward path.

The lab certificates are short-lived training credentials. They are not a model for enterprise CA lifecycle, certificate issuance, HSM/private-key governance, or production PKI ownership.

The CI workflow generates the Elasticsearch password dynamically, masks it in GitHub Actions output, and creates the Kubernetes Secret at runtime. The repository's Secret example is instructional only and must not contain a production credential.

Use trusted CA validation:

```bash
curl --cacert "$ES_CA" \
  -u "$ES_USER:$ES_PASSWORD" \
  "$ES_URL/"
```

Do not normalize `curl -k`.

---

## 10. Discovery and One-Time Bootstrap

The bootstrap ConfigMap is used only to form the brand-new cluster. It includes the initial master-eligible node list required for first bootstrap.

After the cluster forms, the lab records the cluster UUID and transitions to the runtime ConfigMap. The runtime configuration deliberately omits:

```text
cluster.initial_master_nodes
```

This is a required safety property.

`cluster.initial_master_nodes` is not a normal restart setting, not a node-join setting, and not a full-cluster-restart setting for an already formed cluster. Reintroducing it to an existing cluster can create serious cluster-identity risk.

Because the ConfigMap is mounted using `subPath`, updating the ConfigMap does not magically replace the already mounted file inside an existing container. The lab therefore consumes the runtime configuration through controlled Pod recreation and explicitly verifies that the effective Elasticsearch configuration no longer contains the bootstrap setting.

---

## 11. Cluster Identity STOP Gate

Once the initial cluster forms, record its UUID.

Every restart/rejoin cycle must return the same UUID.

Conceptually:

```text
EXPECTED_CLUSTER_UUID = UUID recorded after first successful cluster formation
```

If a node or the cluster reports a different cluster UUID, stop the procedure and preserve evidence. Do not attempt to make the environment green by force allocation, deleting data paths, resetting cluster state, or reintroducing bootstrap configuration.

Cluster UUID is an important identity signal, but production safety also depends on persistent cluster state, correct discovery configuration, correct data paths, and correct bootstrap lifecycle.

---

## 12. Validation Workload

The lab creates a deterministic synthetic index:

```text
installation-validation-v1
```

The validation index uses explicit settings and mapping and contains four synthetic healthcare-style documents. No real patient, client, or production data is used.

The validation checks include:

- index creation;
- expected shard/replica configuration;
- explicit mapping;
- successful bulk ingestion;
- bulk response without item errors;
- exact document count of `4`;
- bounded search behavior;
- healthy shard assignment.

The deterministic dataset makes restart and persistence checks reproducible.

---

## 13. Bootstrap-to-Runtime Transition

The transition procedure:

1. confirms the cluster formed successfully;
2. records the expected cluster UUID;
3. applies the runtime ConfigMap;
4. confirms the runtime ConfigMap excludes `cluster.initial_master_nodes`;
5. recreates Elasticsearch Pods one at a time;
6. verifies the runtime configuration inside the recreated Pod;
7. verifies each node rejoins the original cluster.

Do not delete all three Pods simultaneously for this validation.

---

## 14. Rolling Restart / Rejoin Validation

The harness validates the nodes in this order:

```text
elasticsearch-2
elasticsearch-1
elasticsearch-0
```

Before each recreation it verifies:

- three Elasticsearch nodes are present;
- cluster UUID equals the expected UUID;
- validation index is green with zero unassigned shards;
- validation index contains exactly four documents.

For each Pod it then:

1. records Pod UID, PVC UID, and PV;
2. deletes only that Pod;
3. waits for the replacement Pod to become Ready;
4. requires a different Pod UID;
5. requires the same PVC UID;
6. requires the same PV;
7. confirms the effective runtime configuration does not contain the bootstrap setting;
8. re-runs cluster identity, health, and data checks.

Before `elasticsearch-0` is recreated, CI moves the API port-forward to the surviving `elasticsearch-1` Pod. This prevents the validation control path from failing simply because its own tunnel target was intentionally deleted.

---

## 15. Runtime Audit

After restart/rejoin validation, the runtime audit captures and validates operational evidence including:

- Elasticsearch node names and roles;
- exact Elasticsearch version;
- transport publish identity;
- JVM information;
- process information;
- maximum file descriptors;
- cluster settings;
- absence of transient cluster-setting overrides used as hidden configuration.

The lab expects a file-descriptor capacity of at least `65535`; the validated CI environment reports substantially more.

Explicit node roles must be reviewed carefully in production. Removing required roles from `node.roles` can make a cluster unable to perform required functions.

---

## 16. Security Negative Tests

A production-readiness lab should prove not only that valid access succeeds, but also that invalid access is rejected.

CI therefore requires:

### Invalid authentication

A request using a deliberately incorrect password must return HTTP `401`.

### Untrusted TLS

An authenticated HTTPS request that does not trust the lab CA must fail TLS verification.

The negative TLS test must not use `-k` or `--insecure`.

These gates prove that authentication and certificate trust are active controls rather than decorative configuration.

---

## 17. Final Validation Gate

Before evidence sanitization and cleanup, CI captures:

```text
evidence/final-cluster-health.json
evidence/final-index-count.json
evidence/final-pods.txt
evidence/final-pvcs.txt
evidence/final-pvs.txt
```

The final gate requires:

```text
installation-validation-v1 status = green
unassigned_shards = 0
document count = 4
```

It also records the final Pod, PVC, and PV state before cleanup.

The objective is not merely a green color. The evidence must demonstrate cluster identity continuity, data persistence, runtime configuration correctness, security enforcement, and storage continuity.

---

## 18. Evidence Handling

The lab writes validation artifacts under `evidence/` and sanitizes them before upload.

Evidence must never intentionally contain:

- the generated Elasticsearch password;
- private TLS keys;
- reusable production credentials;
- real patient/client data.

GitHub Actions uploads the sanitized evidence even when the main validation fails, allowing troubleshooting without weakening the validation gates.

Failure diagnostics capture Pod/PVC/PV state and bounded Elasticsearch logs before cleanup.

---

## 19. Cleanup and Storage Reclaim Verification

Cleanup is an `if: always()` workflow step.

Before namespace deletion the cleanup script displays PVC and PV state. It then deletes the disposable namespace and displays PV state again.

This is intentionally evidence-driven. Namespace deletion does not, by itself, prove that physical backend storage has been erased. Actual behavior depends on the StorageClass, PV reclaim policy, CSI implementation, and storage provider.

For the validated `kind` environment, the dynamically provisioned PVs use reclaim policy `Delete`.

Production cleanup must follow the organization's data-retention, snapshot, legal, backup, and storage-destruction requirements.

---

## 20. Failure Policy

If any validation gate fails:

1. do not mark the lab verified;
2. do not merge merely because Elasticsearch appears usable;
3. preserve sanitized evidence;
4. determine whether the failure is Elasticsearch, Kubernetes/storage, security/configuration, or validation-harness behavior;
5. apply the narrowest justified correction;
6. rerun validation against the exact corrected branch head.

A harness defect may be fixed, but the validation requirement must not be weakened simply to obtain a green CI result.

---

## 21. Success Criteria

Lab 02 is successful only when all of the following are demonstrated:

- [x] pinned Elasticsearch 9.5.3 image;
- [x] `vm.max_map_count=1048576`;
- [x] security enabled;
- [x] HTTPS with trusted CA validation;
- [x] invalid credentials rejected;
- [x] untrusted TLS rejected;
- [x] three-node Elasticsearch cluster formed;
- [x] valid non-`_na_` cluster UUID recorded;
- [x] persistent PVC per Elasticsearch Pod;
- [x] deterministic validation index created and loaded;
- [x] runtime ConfigMap excludes `cluster.initial_master_nodes`;
- [x] `elasticsearch-2` recreated and rejoins with same PVC/PV and cluster UUID;
- [x] `elasticsearch-1` recreated and rejoins with same PVC/PV and cluster UUID;
- [x] `elasticsearch-0` recreated and rejoins with same PVC/PV and cluster UUID;
- [x] runtime audit passes;
- [x] final validation index is GREEN;
- [x] final unassigned shard count is zero;
- [x] final document count is four;
- [x] evidence sanitization passes;
- [x] sanitized evidence is uploaded;
- [x] cleanup executes successfully and records storage reclaim state.

---

## 22. Runtime Validation Record

### GitHub Actions validation

**Workflow:** `Elasticsearch Lab 002 Validation`  
**Run:** `#7`  
**Run ID:** `34988412039`  
**Validated branch head:** `5f69c59a725b9009d9f98e71f2950fb3210699b5`  
**Job ID:** `104446553206`  
**Conclusion:** `success`

The pull-request workflow checked out GitHub's synthetic PR merge commit representing the validated branch head against the current base. Artifact metadata independently records the source branch head as `5f69c59a725b9009d9f98e71f2950fb3210699b5`.

Observed validation results include:

- Ubuntu 24.04.5 runner;
- `kind` v0.31.0;
- Kubernetes node image v1.35.0;
- `vm.max_map_count=1048576` on host and kind node;
- invalid authentication → HTTP 401;
- request without trusted lab CA → TLS validation failure;
- deterministic index validation → PASS;
- runtime bootstrap-setting removal → PASS;
- all three node restart/rejoin cycles → PASS;
- persistent storage continuity → PASS;
- same cluster UUID through restart/rejoin → PASS;
- runtime audit → PASS;
- final GREEN / zero-unassigned / four-document gate → PASS;
- evidence sanitization/upload → PASS;
- cleanup → PASS.

### Sanitized evidence artifact

**Artifact:** `elasticsearch-lab-002-validation`  
**Artifact ID:** `10404134750`  
**Size:** `15,198 bytes`  
**Digest:** `sha256:d1174b6f53087567fab42f587241975941d794e3d5c2b04471abbdc1c52cb9c4`

The final storage evidence showed three Bound `10Gi` RWO PVCs immediately before cleanup. Their backing PVs used reclaim policy `Delete`, and the disposable namespace was successfully deleted.

---

## 23. Production Interpretation

This lab demonstrates a correct installation/configuration lifecycle in a controlled Kubernetes environment. A production rollout must additionally validate the real environment's:

- worker and availability-zone topology;
- storage latency, IOPS, throughput, topology, and failure behavior;
- resource requests/limits and N-1 capacity;
- certificate authority and secret lifecycle;
- network policy/firewall/load-balancer behavior;
- snapshot repository and restore procedure;
- monitoring, alerting, logging, and incident integration;
- maintenance and upgrade procedure;
- backup/retention/compliance controls;
- application concurrency and workload characteristics.

Three healthy Elasticsearch Pods do not prove those properties automatically.

---

## 24. Canonical Workflow State

```text
Tutorial 02
  → Revised Final / Canonical
  → COMMITTED / VERIFIED

Hands-On Lab 02
  → Revised Draft
  → Technical + Source Review
  → Production + Copyright Review
  → Revised Final / Canonical
  → Lab / Implementation Validation
  → Run #7 PASS
  → CANONICAL / COMMITTED / VERIFIED
```

The implementation-validation gate has passed. The README status records that validated state; the pull request still requires final exact-head CI after this documentation commit before merge.

---

## 25. Core Principle

> Production installation is not proven by `Running` Pods. It is proven by secure cluster formation, correct bootstrap lifecycle, persistent state, stable cluster identity, controlled restart/rejoin behavior, runtime configuration evidence, data persistence, and repeatable recovery-safe validation.
