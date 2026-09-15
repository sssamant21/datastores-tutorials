# Hands-On Lab 01 — Deploy and Operate a Three-Node Elasticsearch Cluster on Kubernetes

**Track:** Elasticsearch Administrator / DBRE / SRE  
**Status:** CANONICAL / COMMITTED / VERIFIED  
**Reference Elasticsearch:** 9.5.3  
**Runtime Validation:** PASS — expanded GitHub Actions implementation matrix  

> This is a production-style learning environment, not a complete production-ready Elasticsearch deployment.

## Objective

Deploy a three-node Elasticsearch StatefulSet with persistent storage, create an explicitly mapped index, ingest synthetic data, inspect shard placement, delete a pod that owns a primary shard, and validate Elasticsearch/Kubernetes recovery.

## Safety

- `kubectl get`, Elasticsearch health/CAT APIs: **READ-ONLY / DIAGNOSTIC**.
- Applying manifests and creating the index: **STATE-CHANGING**.
- Pod deletion and cleanup: **LAB-DESTRUCTIVE**.
- Never use real patient/customer data or production credentials.

## Architecture

```text
Client
  |
Kubernetes Service
  |
  +-- elasticsearch-0 -- PVC-0
  +-- elasticsearch-1 -- PVC-1
  +-- elasticsearch-2 -- PVC-2
             |
      Elasticsearch cluster
             |
      patients-v1: 3P / 1R
```

Kubernetes manages pods, scheduling, services and volumes. Elasticsearch independently manages cluster membership, master election, shard allocation, primary promotion and recovery. `Pod Running` does not mean `Elasticsearch Healthy`, and `Elasticsearch GREEN` does not prove good infrastructure performance.

## Files

- `manifests/00-namespace.yaml` — isolated lab namespace.
- `manifests/01-service-headless.yaml` — discovery and client services.
- `manifests/02-configmap.yaml` — initial Elasticsearch bootstrap configuration.
- `manifests/03-secret.example.yaml` — placeholder only; CI creates the real lab Secret dynamically.
- `manifests/04-statefulset.yaml` — three Elasticsearch pods and PVC templates.
- `manifests/05-configmap-runtime.yaml` — post-bootstrap runtime configuration without `cluster.initial_master_nodes`.
- `configs/patients-v1.json` — strict mapping, 3 primary shards, 1 replica.
- `data/patients.ndjson` — synthetic records.
- `scripts/validate.sh` — baseline cluster/index/mapping/data/search validation.
- `scripts/failure-test.sh` — primary-owner pod deletion, replica-promotion, search-continuity, PVC-persistence and recovery evidence.
- `cleanup/cleanup.sh` — namespace cleanup plus PV inspection.

## Bootstrap lifecycle

`cluster.initial_master_nodes` is used only for the initial formation of the brand-new lab cluster. After cluster formation, CI applies `manifests/05-configmap-runtime.yaml`, which removes the bootstrap setting, restarts a node, and verifies that the node rejoins the existing cluster successfully.

Do not restore or routinely reuse `cluster.initial_master_nodes` after a cluster has already formed.

## Host prerequisite

The reference CI configures `vm.max_map_count=1048576` before Elasticsearch starts and verifies the value inside the kind node. Other environments must validate the requirement for their pinned Elasticsearch release.

## Security

Security remains enabled. Do not commit real credentials. The CI workflow creates a lab-only Kubernetes credential Secret and short-lived TLS material dynamically and uses CA-verified authenticated HTTPS requests. The shared lab certificate is appropriate for this disposable educational environment and is not a production PKI design recommendation.

## Expected steady state

```text
Kubernetes: 3 Elasticsearch pods Ready; expected PVCs Bound
Elasticsearch: 3 nodes; GREEN; 0 unassigned shards
patients-v1: 3 primaries; 1 replica per primary
```

A temporary YELLOW state during pod loss is possible but is not a required observation. With one replica and two surviving nodes, Elasticsearch may recover redundancy before the deleted pod returns.

## Canonical implementation validation

The workflow `.github/workflows/elasticsearch-lab-001.yml` is the executable validation gate. The canonical implementation has passed the expanded runtime matrix, including:

- pinned Elasticsearch 9.5.3 execution;
- Kubernetes and `vm.max_map_count` prerequisites;
- three-node secured cluster formation;
- TLS and authenticated HTTPS;
- three Ready pods and Bound persistent claims;
- explicit index settings and mapping validation;
- synthetic bulk ingestion, count and search validation;
- 3 primary shards and 1 replica per primary;
- removal of `cluster.initial_master_nodes` after initial formation;
- restart and rejoin using post-bootstrap runtime configuration;
- deletion of a primary-owning pod;
- observed replica promotion;
- successful search during the failure/recovery window;
- PVC/PV identity persistence across pod recreation;
- no recovery-induced container restart loop;
- final 3-node GREEN state with 0 unassigned shards;
- validation evidence capture and cleanup.

**Canonical state:** `CANONICAL / COMMITTED / VERIFIED`.
