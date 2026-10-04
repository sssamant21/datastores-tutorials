# 33 — Management Automation and Configuration Drift

**Status:** Draft; live lab not run.

**Objective:** Automate administration through supported management interfaces.

Management API/administrative CLI and application Redis commands are separate interfaces/identities. rladmin manages supported cluster operations; Active-Active has additional tooling. Kubernetes uses its owning custom resources. Select one authoritative workflow per setting to avoid controllers overwriting changes.

## Read-only inventory exercise

On an approved self-managed staging node, with required administration permissions:
```bash
rladmin status
```
Record node/database/shard identifiers, roles and health. API alternative: use the installed-release REST API guide to issue authenticated, verified-TLS read-only inventory requests. Capture only approved non-secret fields; do not place passwords in URLs/history or use certificate-verification bypasses.

## Reconciliation design

1. Version desired non-secret configuration: databases, owners, limits, replication, persistence, access policy and backups.
2. Read current state and normalize defaults/version differences.
3. Produce a reviewable drift report and proposed changes.
4. Check immutable settings, available capacity and application consequences.
5. Apply bounded supported changes; poll asynchronous progress to terminal state.
6. Verify health/configuration and record audit evidence.

Retries of creation must identify an existing resource rather than create duplicates. A request timeout does not imply failure: inspect state before replay. Respect rate limits and concurrent change ownership. Keep secret values separately; reference their managed identity/version.

## Acceptance

Compare two inventory snapshots and explain a deliberately changed lab setting. Reapply the same desired state and verify no duplicate resource/change. Test partial failure, API timeout, stale inventory and configuration ownership. Exported configuration is not a data backup; preserve both when recovery requires them.

## References

- [rladmin](https://redis.io/docs/latest/operate/rs/references/cli-utilities/rladmin/)
- [REST API](https://redis.io/docs/latest/operate/rs/references/rest-api/)

**Next:** [34 — Flex and Auto Tiering](34-flex-and-auto-tiering.md).
