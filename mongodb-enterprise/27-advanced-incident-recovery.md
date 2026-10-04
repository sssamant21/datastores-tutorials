# 27 — Advanced Incident Recovery

**Status:** Draft; live lab not run.

**Objective:** Diagnose transaction, replication and sharded incidents while preserving data.

## Evidence first

Capture scope/timezone, full error labels, application impact, topology, versions/FCV, resource metrics, relevant logs and recent changes. Establish incident ownership and a recoverable backup. Preserve affected files/evidence before destructive recovery. Use Tutorial 14 for ordinary slowness.

| Scenario | Investigation | Recovery direction |
|---|---|---|
| Transaction conflicts/timeouts | Labels, duration, contention, dependencies | Shorten/reduce contention; correct driver retry policy |
| Unknown commit result | Business transaction ID and committed state | Reconcile; retry commit per driver protocol |
| Lag beyond available oplog | Source history, logs, disk/network | Supported member resync/rebuild |
| Rollback/recovering member | Member logs, surviving data, acknowledged-write impact | Version-specific investigation/support |
| No primary | Voting majority, network, member states | Restore healthy quorum before reconfiguration |
| Hot shard | Tenant/key skew, targeting, per-shard resource load | Query/key/load redesign |
| Migration failure | Recipient capacity, zones, logs, long operations | Resolve cause; observe migration outcome |
| Config-server incident | Quorum, routing metadata, connectivity | Restore config replica-set health |

## Read-only incident lab

Use an existing staging cluster. Capture on each relevant replica-set member:
```javascript
db.adminCommand({ hello: 1 })
db.adminCommand({ replSetGetStatus: 1 })
db.getReplicationInfo()
```

getReplicationInfo describes that member's local oplog time span. It is not Ops Manager backup retention. On mongos:
```javascript
sh.status()
```

Inspect long transactions including inactive sessions holding locks:
```javascript
db.getSiblingDB("admin").aggregate([
  { $currentOp: { allUsers: true, idleSessions: true } },
  { $match: { transaction: { $exists: true } } },
  { $limit: 20 },
  { $project: { _id: 0, host: 1, opid: 1, active: 1, transaction: 1, waitingForLock: 1 } }
], { maxTimeMS: 5000 })
```

Requires approved monitoring privileges. Fields vary by release and operation; an empty snapshot does not exclude intermittent transactions.

## Controlled recovery drills

Use isolated staging and a scenario-specific runbook. Rebuild only the selected failed secondary through the owning workflow after verifying a healthy source, quorum, disk and history. For disaster recovery, restore a consistent topology using supported backup procedures; preserve config metadata together with shard recovery. Do not restore random shards independently and assume routing consistency.

Forced reconfiguration, repair, deleting dbPath and rolling back binaries are not default incident fixes. They require explicit data-loss/compatibility assessment and release-specific procedures. Primary transition/rebuild drills must define acceptable interruption, stop conditions and validation.

**Acceptance:** diagnose from evidence, select a supported recovery, validate application/data invariants and record any loss or uncertainty.

## References

- [Replica-set recovery](https://www.mongodb.com/docs/manual/administration/replica-set-maintenance/)
- [Transaction considerations](https://www.mongodb.com/docs/manual/core/transactions-production-consideration/)
- [Sharding](https://www.mongodb.com/docs/manual/sharding/)

**Next:** [28 — Extended Acceptance and Coverage](28-extended-acceptance-and-coverage.md).
