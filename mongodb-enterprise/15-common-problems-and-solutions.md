# 15 — Common Problems and Solutions

**Status:** Draft; live lab not run.

**Objective:** Recognize failures, collect evidence and apply appropriate fixes.

## Capture failure

Record environment, timestamp/timezone, app/operation, DB/collection, full error/code/labels, frequency, impact and recent changes. Remove credentials and sensitive values from shared evidence.

## Connectivity/security

| Problem | Checks | Solution |
|---|---|---|
| Server selection timeout | DNS, ports, advertised addresses, primary, set name | Fix connectivity/topology |
| Authentication failed | User, secret, authSource, mechanism | Correct identity/authentication DB |
| Unauthorized | Required privilege/target DB | Approved least-privilege role |
| TLS failure | CA, hostname, expiry, client certificate | Correct trust/certificates |
| Pool timeout | Pool wait, concurrency, slow operations, reuse | Reuse clients/control load; tune capacity |

Authentication verifies identity; authorization governs permissions. Ping confirms basic command connectivity, not application read/write privileges.

## Data/write failures

Duplicate key: inspect error index/key and existing constraints:
```javascript
db.getSiblingDB("mongodb_tutorials").tutorial_products.getIndexes()
```
Check repeated insertion, racing upserts or duplicate business keys. Correct identity/upsert logic and resolve data while preserving required uniqueness.

Validation failure: inspect validator:
```javascript
db.getSiblingDB("mongodb_tutorials")
  .getCollectionInfos({ name: "tutorial_products" })
```
Compare required fields and BSON types. Our schema uses Decimal128 prices and Int32 quantities. Correct input or plan a schema migration. validationAction: error rejects writes violating applicable rules.

Write-concern timeout: inspect replica health, lag, I/O and acknowledgement policy. Applied writes are not undone by timeout. Determine outcome before manually retrying non-idempotent operations such as increments.

## Availability/replication

| Problem | Checks/solution |
|---|---|
| No primary | Reachable voting members, elections/logs; restore healthy quorum |
| Secondary lag | Write rate, I/O, CPU/network; resolve bottleneck/excess load |
| Initial sync failure | Logs, disk, network, oplog; correct cause before retry |
| Stale secondary reads | Read preference/lag; required consistency policy |
| Frequent elections | Restarts, resource/network instability; stabilize members |

Use rs.status() on a replica-set member. Preserve evidence before restarting or changing membership.

## Performance/storage

| Problem | First investigation | Correction |
|---|---|---|
| Slow query | Shape/plan/examined records/sort | Filters and suitable indexes |
| Slow aggregation | Inputs/joins/grouping/spilling | Reduce inputs; pipeline design |
| Ingestion CPU | Batch concurrency/index overhead | Backpressure/batch tuning |
| Disk nearly full | Growth/largest data and indexes | Capacity/retention |
| Disk unchanged after delete | Reusable versus allocated space | Planned supported reclamation |
| OOM | Effective limit/memory/workload | Align limits/capacity |

Use Tutorial 14 for diagnosis. Never delete WiredTiger/journal files to reclaim space.

## Backup/management

| Problem | Action |
|---|---|
| Backup overdue | Job state, Agent, storage, latest snapshot |
| Restore duplicate keys | Partial results and fresh destination |
| Recovery time unavailable | Retained snapshot/oplog coverage |
| Metrics absent | Collector and sample freshness |
| Configuration reverts | Owning Ops Manager/Operator workflow |

## Completion

Repeat the affected operation; verify errors/latency and replication/resources/backup health. Record cause, evidence, permanent action and owner.

## References

- [Error codes](https://www.mongodb.com/docs/manual/reference/error-codes/)
- [Write concern](https://www.mongodb.com/docs/manual/reference/write-concern/)
- [Invalid documents](https://www.mongodb.com/docs/manual/core/schema-validation/handle-invalid-documents/)

**Next:** [16 — Upgrades and Maintenance](16-upgrades-and-maintenance.md).
