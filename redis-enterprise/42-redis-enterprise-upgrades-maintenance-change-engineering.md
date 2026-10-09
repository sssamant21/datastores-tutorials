# Chapter 42 --- Redis Enterprise Upgrades, Maintenance & Change Engineering

**Status:** Canonical\
**Track:** Redis Enterprise / Redis Software Production Engineering\
**Part:** Part 6 --- Observability, Reliability & Production Operations\
**Level:** Advanced → Production Change Engineering\
**Audience:** SREs, DBREs, Platform Engineers, Redis Administrators\
**Lab type:** Upgrade-path validation, compatibility review, recovery readiness, N-1 prechecks, rolling maintenance, reconnect testing, rollback planning, failure injection, runbooks, and production acceptance

------------------------------------------------------------------------

# 1. Objective

Redis Enterprise upgrades and maintenance are reliability events. The goal is not merely to install a version; it is to preserve availability, recoverability, client compatibility, and operational control throughout the change.

By the end of this chapter you should be able to validate supported upgrade paths, identify compatibility dependencies, establish go/no-go criteria, prove recovery readiness, execute rolling maintenance safely, validate clients and workloads after each step, and choose rollback, roll-forward, or recovery when a change fails.

# 2. Core Production Principle

```text
inventory -> compatibility -> recovery proof -> capacity proof
          -> change -> validate -> stabilize -> close
```

Never begin a production upgrade without knowing the exact current version, target version, supported path, recovery method, and failure capacity.

# Part 1 --- Change Inventory

## 3. Record

```text
Redis Enterprise version
database versions/features
modules
client libraries
Kubernetes/operator version if applicable
OS/cloud dependencies
TLS/certificates
monitoring integrations
backup/restore dependencies
```

# Part 2 --- Supported Upgrade Path

## 4. Validate

Use the exact vendor documentation for the deployed release. Do not assume direct upgrades across multiple major versions are supported. Record required intermediate releases and version-skew limitations.

# Part 3 --- Compatibility Review

## 5. Test

Validate client protocols, commands, modules, authentication, TLS, monitoring, backup, automation, and API behavior before production.

# Part 4 --- Recovery Readiness

## 6. Gate

Before change, require a recent valid recovery point and recent restore evidence appropriate to the service. A backup without tested recovery is insufficient.

# Part 5 --- Capacity Gate

## 7. N-1

Prove the remaining topology can carry expected production demand during rolling maintenance. Check CPU, memory, connections, network, storage, replication, and recovery headroom.

# Part 6 --- Workload Window

## 8. Avoid Known Peaks

Do not schedule maintenance during known batch, data-sync, campaign, or seasonal peaks unless the change specifically requires it and capacity has been proven.

# Part 7 --- Change Isolation

## 9. One Risk at a Time

Avoid combining unrelated Redis, application, network, certificate, and infrastructure changes in the same window.

# Part 8 --- Go / No-Go

## 10. Required PASS Conditions

- healthy baseline;
- replication healthy;
- backup/recovery ready;
- failure headroom proven;
- monitoring healthy;
- rollback/recovery plan reviewed;
- required engineers available;
- no unresolved critical incident.

# Part 9 --- Rolling Maintenance

## 11. Principle

Change one supported failure domain/component at a time. After each step validate Redis health, replication, application errors, latency, reconnect behavior, and redundancy before proceeding.

# Part 10 --- Client Reconnect

## 12. Validate

Maintenance often exposes weak client behavior. Measure connection errors, reconnect rate, retry amplification, pool recovery, DNS behavior, and TLS handshakes.

# Part 11 --- Post-Step Validation

## 13. Check

```text
application errors/P99
Redis latency
CPU/memory
connections
replication
persistence
alerts
shard/node placement
```

# Part 12 --- Stabilization

## 14. Do Not Rush

Observe representative traffic before continuing to the next maintenance step.

# Part 13 --- Rollback vs Roll-Forward

## 15. Decide Before Change

Downgrade may not be supported. Document whether failure response is rollback, roll-forward, restore/recovery, or vendor-assisted remediation.

# Part 14 --- Writes During Window

## 16. RPO Implication

If writes continue during maintenance, understand what happens if recovery requires restoring an earlier point. Define traffic control where business semantics require it.

# Part 15 --- Kubernetes / Cloud

## 17. Additional Dependencies

For Kubernetes, validate operator/CRD compatibility, scheduling, PDBs, storage, and node-drain behavior. For cloud deployments, validate VM, disk, network, quota, and maintenance dependencies.

# Part 16 --- Observability

## 18. Mark the Change

Place change markers on dashboards and retain before/during/after evidence.

# Part 17 --- Hands-On Lab

## 19. Nonproduction Exercise

1. Inventory versions and dependencies.
2. Confirm the supported path.
3. Capture baseline metrics.
4. Verify backup/restore evidence.
5. Validate N-1.
6. Run application smoke tests.
7. Perform one supported rolling maintenance step.
8. measure reconnect/errors/P99.
9. Validate redundancy.
10. Record stabilization evidence.

# Part 18 --- Failure Injection

## 20. Ten Scenarios

1. unsupported direct upgrade path;
2. client incompatibility;
3. insufficient N-1 capacity;
4. reconnect storm;
5. replication fails to recover;
6. persistence/storage pressure;
7. monitoring disappears mid-change;
8. certificate/secret dependency fails;
9. Kubernetes/cloud component does not return healthy;
10. rollback is unavailable and recovery path is required.

# Part 19 --- Troubleshooting

## 21. Change Failure Matrix

| Symptom | Investigate |
|---|---|
| application errors | client compatibility, auth, TLS, endpoint |
| high latency | reconnect, CPU, recovery, storage, network |
| replica unhealthy | topology, network, capacity, logs |
| node will not return | platform, storage, operator/cloud events |
| monitoring missing | collectors, credentials, endpoint changes |

# Part 20 --- Production Runbooks

## 22. Pre-Change
Inventory → compatibility → recovery → N-1 → monitoring → go/no-go.

## 23. Rolling Change
One component → validate → stabilize → continue.

## 24. Failed Step
Stop progression → preserve evidence → restore service → decide rollback/roll-forward/recovery.

## 25. Client Regression
Measure failures/retries → isolate client version/config → restore compatible path → retest.

## 26. Post-Change
Validate application, Redis, redundancy, backup, alerts, and representative workload.

# Part 21 --- Change Record Template

## 27. Record

```text
Current version:
Target version:
Supported path:
Dependencies:
Recovery point:
N-1 result:
Window:
Owner:
Rollback/recovery:
Go/no-go:
Post-change result:
Evidence:
```

# Part 22 --- Production Acceptance

## 28. Checklist

- [ ] Exact versions inventoried.
- [ ] Supported path verified.
- [ ] Client/module compatibility tested.
- [ ] Backup and restore evidence current.
- [ ] N-1 capacity proven.
- [ ] Peak windows reviewed.
- [ ] Monitoring healthy.
- [ ] Go/no-go completed.
- [ ] Rolling procedure rehearsed.
- [ ] Reconnect behavior tested.
- [ ] Rollback/roll-forward/recovery decision documented.
- [ ] Ten failure scenarios reviewed.
- [ ] Post-change validation completed.
- [ ] Evidence retained.

# 29. Key Takeaways

1. Upgrades are reliability events.
2. Supported paths are version-specific.
3. Recovery and failure capacity are preconditions.
4. Rolling does not mean risk-free.
5. Client reconnect behavior is part of upgrade readiness.
6. Validate after every step.
7. Do not assume downgrade is possible.
8. Separate unrelated changes.
9. Preserve before/during/after evidence.
10. Close only after stabilization.

# 30. References

Validate all upgrade, maintenance, compatibility, rollback, Kubernetes, and cloud procedures against the exact deployed Redis Enterprise release and official Redis documentation.
