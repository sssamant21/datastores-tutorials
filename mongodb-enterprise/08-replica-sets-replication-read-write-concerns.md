# 08 — Replica Sets, Replication, and Read/Write Concerns

**Status:** Draft

**Objective:** Understand availability and read/write guarantees.

**Prerequisite:** Test replica set and appropriate monitoring/read-write privileges. No failover is triggered here.

## Replica-set behavior

Primary accepts writes; secondaries replicate asynchronously using the oplog. Elections select an eligible primary and can temporarily interrupt writes. A common production topology has three data-bearing voting members across suitable failure domains. Replication does not replace backups.

## Three controls

| Control | Question |
|---|---|
| Read preference | Which member serves reads? |
| Read concern | What consistency is required? |
| Write concern | What acknowledgment is required? |

primary reads from primary; primaryPreferred permits secondary fallback; secondary selects secondaries; secondaryPreferred permits primary fallback; nearest chooses eligible members by latency criteria. Secondary reads can be stale. Nearest is not guaranteed geographic proximity.

local reads locally available data that may roll back. majority reads majority-committed data, not necessarily newest data. w:1 acknowledges at the primary; w:"majority" uses the calculated acknowledgment majority; j:true requests journal durability; wtimeout bounds write-concern waiting. Verify configured defaults.

## Health checks

```javascript
db.adminCommand({ hello: 1 })
rs.status()
rs.printReplicationInfo()
rs.printSecondaryReplicationInfo()
```

Inspect member health/states, primary presence, heartbeats, progress, lag and oplog window. These helpers apply to replica-set members, not mongos; verify monitoring privileges. A secondary outside retained oplog history can require resynchronization.

## Test write and read

```javascript
use mongodb_tutorials
db.tutorial_replication.updateOne(
  { _id: "tutorial-replication-check" },
  { $set: { status: "ready", checkedAt: new Date() } },
  {
    upsert: true,
    writeConcern: { w: "majority", j: true, wtimeout: 5000 }
  }
)

db.tutorial_replication.find({ _id: "tutorial-replication-check" })
  .readPref("primary").readConcern("majority").maxTimeMS(2000)
```

Expect acknowledged update/insertion and a majority-committed read when required members are healthy.

A write-concern timeout does not undo a write applied on primary. Verify outcomes before repeating non-idempotent operations. wtimeout is not an overall request deadline. Majority reads on a secondary can still lag; read-your-writes across members requires an appropriately configured causally consistent session.

## Problems

No primary: inspect voting availability/network/eligibility. Lag: inspect disk/CPU/network/write volume. Majority timeouts: inspect member and journal/replication progress. Stale reads: inspect preference, concern and session. Resync: inspect oplog coverage.

## Cleanup and production practice

```javascript
db.tutorial_replication.deleteOne(
  { _id: "tutorial-replication-check" },
  { writeConcern: { w: "majority", j: true, wtimeout: 5000 } }
)
```

Monitor lag/oplog coverage, use application discovery, define loss/recovery targets, rehearse elections in staging, and check quorum/capacity before topology changes.

## References

- [Write concern](https://www.mongodb.com/docs/manual/reference/write-concern/)
- [Majority read concern](https://www.mongodb.com/docs/manual/reference/read-concern-majority/)
- [Read preference](https://www.mongodb.com/docs/manual/core/read-preference/)

**Next:** [09 — Security](09-users-roles-authentication-and-tls.md)
