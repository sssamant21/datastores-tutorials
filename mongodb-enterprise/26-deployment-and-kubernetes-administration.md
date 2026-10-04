# 26 — Deployment and Kubernetes Administration

**Status:** Draft; live lab not run.

**Objective:** Establish reproducible deployment ownership and inspect Kubernetes readiness.

## Deployment choices

| Approach | Owner |
|---|---|
| VM/package installation | Infrastructure/configuration automation |
| Ops Manager Automation | Project automation configuration |
| Kubernetes controller | Custom resource and owning controller |

Use supported Enterprise packages/images for the chosen OS, architecture and release. Verify signatures, configuration paths, service identity and filesystem permissions. Install mongosh/Database Tools separately as needed. Follow exact platform installation documentation instead of copying packages across releases.

## Configuration baseline

Document dbPath, logs, bind addresses, ports, replication identity, member DNS, TLS, authentication, internal member authentication, resource limits, storage and monitoring/backup credentials. Bootstrap administrator access through the supported secured procedure; then verify authorization. Do not expose an unauthenticated deployment for convenience.

Use durable storage and documented failure-domain placement. Verify persistent volumes survive pod replacement, backups restore independently of volumes, and host/container settings match the deployed MongoDB version.

## Kubernetes read-only lab

Replace context/namespace with the staging inventory. Resource kinds differ between controller generations; discover installed CRDs first.
```bash
kubectl config current-context
kubectl get crd
kubectl -n mongodb get pods -o wide
kubectl -n mongodb get statefulsets
kubectl -n mongodb get pvc
kubectl -n mongodb get services
kubectl -n mongodb get events --sort-by=.metadata.creationTimestamp
```

Inspect selected resource without printing secrets:
```bash
kubectl -n mongodb describe pod <pod-name>
kubectl -n mongodb logs <pod-name> -c <container-name> --tail=100
```

Replace placeholders before execution. Review restart/OOM/scheduling events, PVC state, service endpoints, controller reconciliation and actual replica-set health. A Ready pod does not prove database quorum or backup readiness.

## Maintenance/rotation

Update the owning custom resource/configuration workflow; watch convergence and stop on unhealthy replication. Check node anti-affinity/topology spread, disruption budgets, probes and capacity before drains. A disruption budget constrains voluntary disruptions, not every failure. Manage secrets/certificate rotation through approved tooling and verify reconnections. Do not hand-edit managed pod files expecting persistence.

## Acceptance

Rehearse deployment recreation, controlled pod replacement, certificate rotation and isolated restore in staging. Record manifests/config versions, storage behavior, interruption and owners. No replacement/drain action is part of this read-only lab.

## References

- [Enterprise installation](https://www.mongodb.com/docs/manual/administration/install-enterprise/)
- [MongoDB Controllers for Kubernetes](https://www.mongodb.com/docs/kubernetes/current/)
- [Production checklist](https://www.mongodb.com/docs/manual/administration/production-checklist-operations/)

**Next:** [27 — Advanced Incident Recovery](27-advanced-incident-recovery.md).
