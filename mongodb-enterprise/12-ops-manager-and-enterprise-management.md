# 12 — Ops Manager and Enterprise Management

**Status:** Draft; live lab not run.

**Objective:** Understand Ops Manager and perform a routine administration health check.

## Capabilities and components

| Capability | Purpose |
|---|---|
| Automation | Deploy, configure and upgrade MongoDB processes |
| Monitoring | Collect metrics, display health and generate alerts |
| Backup | Scheduled snapshots and supported recovery |

Each capability requires configuration. Monitoring visibility does not prove automation or backup is enabled. Applications connect to MongoDB endpoints; Ops Manager handles administration.

| Component | Responsibility |
|---|---|
| Ops Manager application | UI, API and coordination |
| MongoDB Agent | Enabled automation, monitoring and backup functions |
| Managed deployment | Application replica set or sharded cluster |
| Backup infrastructure | Store/process configured recovery data |

The Agent polls for desired configuration, performs required work and reports status. Make managed changes through the owning workflow. For Kubernetes, follow the owning Operator/resource workflow.

## Routine checks

Confirm the correct organization/project/environment; expected hosts and roles; server/Agent/Ops Manager compatibility; recent metrics; automation progress; pending changes; backup status and recovery window; unresolved alerts and disk capacity.

Use documentation matching installed versions; screen labels and supported features differ.

## Read-only health-check exercise

Prerequisite: access to an existing project with permission to view deployment, monitoring and backups.

1. Inspect deployment topology against inventory.
2. Review recent latency, throughput, connections, replication lag, CPU/memory and storage metrics. Confirm sample freshness.
3. Inspect backup job state, last successful snapshot, retention and recoverable window.
4. Capture unresolved alert scope, start time, condition and owner.

Record:
```text
Project / environment:
Replica set / cluster:
Expected members / current primary:
Server versions / Agent status:
Automation status:
Latest metric timestamp:
Backup enabled / job state:
Latest successful snapshot / recovery window:
Retention / last verified restore:
Unresolved alerts and owners:
```

Active backup jobs create snapshots; stopped jobs retain old snapshots but create no new ones. Terminate deletes retained backups and is not a routine pause operation.

Expected result: a health record covering deployment status, metric freshness, backup coverage and unresolved issues.

## Safe changes

1. Record current configuration and intended result.
2. Check compatibility, capacity and recovery readiness.
3. Review proposed changes and expected restart/election.
4. Apply through the owning management workflow.
5. Observe progress until configuration converges.
6. Verify topology, application behavior, metrics and backups.

Prepare a change-specific rollback. Reversing configuration alone may not reverse a version upgrade or data change.

## Common problems

| Problem | Investigation/action |
|---|---|
| Agent unavailable | Process/pod, logs, network, DNS, TLS, credentials |
| Stale metrics | Monitoring function, connectivity and permissions |
| Automation stuck | Failed step, logs, filesystem permissions, disk, package access |
| Manual setting reverts | Check automation/Operator ownership |
| No recent snapshot | Job state, backup errors, Agent and storage |
| Action denied | Ops Manager project permissions separately from DB roles |

## References

- [Ops Manager](https://www.mongodb.com/docs/ops-manager/current/)
- [MongoDB Agent](https://www.mongodb.com/docs/ops-manager/current/tutorial/nav/mongodb-agent/)
- [Backup states](https://www.mongodb.com/docs/ops-manager/current/core/backup-overview/)

**Next:** [13 — Monitoring, Dashboards, and Alerts](13-monitoring-dashboards-and-alerts.md).
