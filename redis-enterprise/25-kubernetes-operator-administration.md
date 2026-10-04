# 25 — Kubernetes Operator Administration

**Status:** Draft; live lab not run.

**Objective:** Deploy and inspect Enterprise resources through their owning Operator.

REC describes a Redis Enterprise cluster; REDB describes a database. Controller reconciliation applies desired state. Active-Active resources use additional release-specific custom resources. Pin compatible Operator, cluster image and Kubernetes versions.

## Deployment exercise

Use a dedicated staging namespace and the installed-version quickstart/Helm procedure. Review CRDs, RBAC, admission configuration, storage classes, resources, placement and networking before applying manifests. Create REC, wait for healthy reconciliation, create REDB with deliberate memory/replication/persistence/TLS choices, then test its assigned endpoint. Keep secrets out of versioned manifests.

## Read-only checks

Replace namespace and inspect the current context before use:
```bash
kubectl config current-context
kubectl get crd
kubectl -n redis get rec
kubectl -n redis get redb
kubectl -n redis get pods -o wide
kubectl -n redis get pvc
kubectl -n redis get services
kubectl -n redis get events --sort-by=.metadata.creationTimestamp
```

Inspect selected pod/controller logs with explicit names and bounded output. Do not print secret values. Check custom-resource status, reconciliation errors, endpoints, PVCs and actual shard health. Ready pods alone do not prove a healthy database.

## Operations

Change owning custom resources through approved GitOps/controller workflows. Hand edits to managed files may revert. Verify anti-affinity/failure domains, disruption budgets and spare capacity before drains; budgets do not prevent every involuntary failure. Rehearse pod replacement, certificate rotation, Operator/cluster upgrade and restore separately in staging.

**Acceptance:** desired resources converge; secure application access, durable storage, fresh metrics and measured recovery pass. Retire lab resources using documented storage/backup retention rules.

## References

- [Redis Enterprise for Kubernetes](https://redis.io/docs/latest/operate/kubernetes/)

**Next:** [26 — Active-Active Geo-Distribution](26-active-active-geo-distribution.md).
