# Hands-On Lab 01 — Deploy and Operate a Three-Node Elasticsearch Cluster on Kubernetes

**Track:** Elasticsearch Administrator / DBRE / SRE  
**Status:** Implementation Candidate — runtime CI validation required before canonical merge  
**Reference Elasticsearch:** 9.5.3  

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
- `manifests/02-configmap.yaml` — Elasticsearch discovery/bootstrap configuration.
- `manifests/03-secret.example.yaml` — placeholder only; CI creates the real lab Secret dynamically.
- `manifests/04-statefulset.yaml` — three Elasticsearch pods and PVC templates.
- `configs/patients-v1.json` — strict mapping, 3 primary shards, 1 replica.
- `data/patients.ndjson` — synthetic records.
- `scripts/validate.sh` — baseline cluster/index/data validation.
- `scripts/failure-test.sh` — primary-owner pod deletion and recovery evidence.
- `cleanup/cleanup.sh` — namespace cleanup plus PV inspection.

## Bootstrap warning

`cluster.initial_master_nodes` is for the initial formation of a brand-new cluster only. It must not be treated as normal persistent discovery configuration. The implementation is not eligible for canonical merge until CI validates a safe post-bootstrap configuration/restart path.

## Host prerequisite

The reference CI configures `vm.max_map_count=1048576` before Elasticsearch starts. Other environments must validate the requirement for their pinned Elasticsearch release.

## Security

Security remains enabled. Do not commit real credentials. The CI workflow creates a lab-only Kubernetes Secret dynamically, retrieves the generated HTTP CA certificate, and uses CA-verified HTTPS requests.

## Expected steady state

```text
Kubernetes: 3 Elasticsearch pods Ready; expected PVCs Bound
Elasticsearch: 3 nodes; GREEN; 0 unassigned shards
patients-v1: 3 primaries; 1 replica per primary
```

A temporary YELLOW state during pod loss is possible but is not a required observation. With one replica and two surviving nodes, Elasticsearch may recover redundancy before the deleted pod returns.

## Implementation gate

The workflow `.github/workflows/elasticsearch-lab-001.yml` is the executable validation gate. The lab remains an implementation candidate until the workflow has actually run successfully and the evidence verifies cluster formation, authentication/TLS, persistent storage, ingestion/search, primary-owner failure, recovery, and cleanup.
