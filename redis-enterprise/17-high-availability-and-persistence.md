# 17 — High Availability and Persistence

**Status:** Draft

**Audience:** Redis Enterprise administrators, SREs, and DBREs.

## Availability and durability

Replication provides additional shard copies; failover can promote eligible replicas. Persistence stores data on disk through configured RDB/AOF policies. Backups support recovery from deletion and broader failures.

Do not infer zero data loss from replication alone. Define RPO (acceptable data loss) and RTO (recovery time) for the application.

## Administration checks

Confirm replication is enabled where required, replica health is good, failure-domain placement is correct, and remaining nodes can sustain a failure. Check disk capacity and persistence health.

Choose persistence based on the data's role: rebuildable cache and authoritative state can have different requirements. A cache rebuild must not overload the source database.

## Staging failover exercise

Use the documented release-specific failover procedure in an isolated staging environment.

1. Record shard placement, health, and application latency.
2. Start bounded reads/writes with identifiable test records.
3. Perform the planned failover.
4. Measure errors, interruption, reconnection, and any lost acknowledged writes.
5. Verify replicas recover and placement is healthy.

Do not stop arbitrary production processes to simulate failure. A planned failover does not prove every unplanned-failure scenario.

## Acceptance and references

Acceptance: measured recovery within requirements, understood loss semantics, healthy replication, and validated client recovery.

- [Durability and availability](https://redis.io/docs/latest/operate/rs/databases/durability-ha/)
- [Cluster management](https://redis.io/docs/latest/operate/rs/clusters/)

**Next:** [18 — Backup and Restore Administration](18-backup-and-restore-administration.md)
