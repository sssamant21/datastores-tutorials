# 19 — Upgrades and Maintenance

**Status:** Draft

**Audience:** Redis Enterprise administrators, SREs, and DBREs.

## Distinguish upgrade types

Cluster software, database engine, capabilities/modules, and Kubernetes operator upgrades are separate changes. Confirm the supported source-to-target path and compatibility for each.

## Pre-maintenance

- Review release notes, supported platforms, client compatibility, and prerequisites.
- Verify cluster health, replicas, placement, and spare capacity.
- Complete required backup and restore validation.
- Rehearse the exact procedure in staging.
- Define maintenance scope, owner, success checks, and stop conditions.

Do not assume arbitrary version jumps or universal rolling-upgrade behavior.

## Execution

Follow the release-specific vendor sequence. Monitor each stage, verify health, and stop on unexpected replication loss, persistent application errors, or capacity pressure.

A software installation completing is not sufficient application validation. Database version changes may require a separate operation.

## Validation lab

Before and after maintenance, run from a test application identity:
```redis
PING
SET tutorial:maintenance:test "ready" EX 60
GET tutorial:maintenance:test
DEL tutorial:maintenance:test
```

Compare p95/p99 latency, errors, hit rate, shard health, persistence status, and node versions. Confirm intended database versions separately.

## Rollback

Document supported recovery before starting. Do not assume in-place downgrade is supported. Recovery may require restoring into a compatible replacement environment and reconciling writes since the backup.

## Acceptance and references

Acceptance: intended versions, healthy cluster/shards, functional application traffic, and no unexplained regression.

- [Upgrade guidance](https://redis.io/docs/latest/operate/rs/installing-upgrading/upgrading/)
- [Release notes](https://redis.io/docs/latest/operate/rs/release-notes/)

**Next:** [20 — Administration Runbook and Acceptance](20-administration-runbook-and-acceptance.md)
