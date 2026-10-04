# 35 — Migration and Disaster Recovery

**Status:** Draft; live lab not run.

**Objective:** Recover or move a deployment with known consistency and cutover behavior.

Database restore, complete cluster recovery and Active-Active participant recovery are distinct procedures. Select the exact product/version/topology runbook. Record RPO/RTO, artifacts, configuration, key material/certificates, supported versions, endpoints and owners.

## Migration plan

1. Inventory source data types, capabilities, persistence, ACLs, client assumptions and key/TTL policies.
2. Provision compatible destination with capacity/security/monitoring.
3. Choose supported export/import or replication-based migration; verify feature restrictions.
4. Establish a consistent source point and a write-coordination/final synchronization plan.
5. Validate representative data, types, TTLs, capability configuration and application operations.
6. Cut over endpoints/secrets through the application deployment workflow.
7. Monitor errors, tail latency and source/destination write ownership.
8. Retain source only under a defined retirement/rollback policy.

Rollback after destination writes needs reconciliation. Repointing to an old source can discard new updates. TTL comparison accounts for elapsed time rather than requiring identical TTL values.

## Cluster-loss staging drill

Use a separate recovery environment. Rebuild supported cluster infrastructure/configuration, restore complete usable artifacts, reestablish identities/TLS and endpoints, then validate application behavior. Measure recovery including provisioning, download, restore, verification and cutover. For disposable cache, separately measure controlled source rebuild without overloading it.

Active-Active recovery follows its participant/convergence rules; do not arbitrarily merge snapshots from different regions. Protect surviving healthy resources and inspect write/data-loss consequences before changing membership.

## Verification

Use synthetic persistent markers plus representative expiring records. Compare sampled values/types, application invariants, security controls and required index/function configuration. Record lost/missing writes and uncertainty explicitly. Cleanup both sides after verified reconciliation.

**Acceptance:** measured recovery/cutover meets targets with a rehearsed rollback or forward-recovery plan.

## References

- [Import/export](https://redis.io/docs/latest/operate/rs/databases/import-export/)
- [Database recovery](https://redis.io/docs/latest/operate/rs/databases/recover/)
- [Active-Active](https://redis.io/docs/latest/operate/rs/databases/active-active/)

**Next:** [36 — Extended Acceptance and Coverage](36-extended-acceptance-and-coverage.md).
