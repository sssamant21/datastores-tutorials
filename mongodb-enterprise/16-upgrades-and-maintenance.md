# 16 — Upgrades and Maintenance

**Status:** Draft; live lab not run.

**Objective:** Prepare, execute and verify maintenance with availability/recovery planning.

## Identify change

| Change | Consideration |
|---|---|
| Patch | Fixes, compatibility, rolling restart |
| Major version | Supported path, drivers, FCV, downgrade restrictions |
| OS/node | Quorum, capacity, restart behavior |
| Certificates | Trust overlap, expiry, clients |
| Storage | Integrity, capacity, catch-up |

Use the exact source/target/topology procedure. Example: 7.0 to 8.0 requires a 7.0 deployment and compatible drivers; older releases need intermediate upgrades.

## Preparation

Record environment, versions, topology, management owner, window, expected impact, backup/restore evidence, stop criteria, recovery procedure and owner.

Rehearse representative operations in staging. Review compatibility/release notes; verify healthy replication/capacity, recoverable backup, driver/Agent/Ops Manager/Operator compatibility, retries/reconnections and expiring alert suppression. Estimate window from rehearsal including catch-up, validation and recovery.

## Read-only preflight

In mongosh:
```javascript
db.version()
db.adminCommand({ getParameter: 1, featureCompatibilityVersion: 1 })
db.adminCommand({ hello: 1 })
```
On a replica-set member:
```javascript
var maintenanceStatus = db.adminCommand({ replSetGetStatus: 1 })
printjson(maintenanceStatus.members.map(member => ({
  name: member.name,
  health: member.health,
  state: member.stateStr,
  appliedTime: member.optimeDate
})))
```

Check versions/FCV on each member through approved connections. Inspect monitoring and backup evidence separately. Expected: verified inventory and healthy baseline.

## Replica-set sequence

For a supported rolling procedure:

1. Maintain/upgrade one secondary through the owning workflow.
2. Restart; wait for health and catch-up.
3. Repeat remaining secondaries.
4. Perform planned primary transition.
5. Maintain former primary.
6. Verify all members/application.

Preserve voting quorum and required write acknowledgements. Elections may briefly interrupt operations; rolling upgrades do not guarantee zero errors. The 7.0 to 8.0 guide uses secondaries first, then stepdown/former-primary upgrade.

Sharded clusters require their dedicated config-server, shard, mongos and balancer sequence. Standalone maintenance requires a planned outage or migration approach.

## FCV separately

Binary version and Feature Compatibility Version differ. Confirm required components upgraded, complete validation/burn-in, check target FCV prerequisites, then advance FCV through the documented workflow. New incompatible features can complicate downgrade. No generic FCV mutation command is supplied here.

## Stop/recover

| Condition | Response |
|---|---|
| Member won't restart | Stop progression; inspect logs/config |
| Catch-up fails | Investigate before another member goes offline |
| Sustained app errors | Pause; compare baseline |
| Resource pressure | Resolve before continuing |
| Compatibility failure | Prepared recovery procedure |

Do not assume old-binary reinstallation is valid rollback. Verify release-specific downgrade/FCV restrictions and support requirements before the change. Restore/cutover recovery must account for subsequent writes.

## Post-maintenance

Verify versions/FCV, topology/replication, application reads/writes, latency/errors, monitoring/automation/backup and removal of suppression. Record duration, impact, deviations and actions.

## References

- [7.0 to 8.0 replica-set upgrade](https://www.mongodb.com/docs/v8.0/release-notes/8.0-upgrade-replica-set/)
- [7.0 to 8.0 sharded upgrade](https://www.mongodb.com/docs/v8.0/release-notes/8.0-upgrade-sharded-cluster/)
- [FCV](https://www.mongodb.com/docs/manual/reference/command/setFeatureCompatibilityVersion/)

**Next:** [17 — Production Readiness and Acceptance Lab](17-production-readiness-and-acceptance-lab.md).
