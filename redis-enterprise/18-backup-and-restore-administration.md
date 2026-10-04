# 18 — Backup and Restore Administration

**Status:** Draft

**Audience:** Redis Enterprise administrators, SREs, and DBREs.

## Recovery policy

Document RPO/RTO, backup schedule, retention, destination, encryption, access, ownership, and restore test frequency. Replicas and persistence do not replace backups against accidental deletion.

For disposable cache data, explicitly document whether source rebuild is the chosen recovery strategy and validate its load impact.

## Backup workflow

Use Enterprise-supported export or scheduled backup mechanisms.

1. Configure a supported destination and credentials.
2. Trigger a test export/backup.
3. Verify completion and all required artifacts for the database.
4. Record timestamp, source version/configuration, artifact location, and retention.
5. Alert on failures or overdue successful backups.

An uploaded object alone does not prove a complete usable backup.

## Restore lab

Restore into a separate compatible test database. Review the documented import behavior first; do not assume it safely merges existing data.

Use a disposable restore marker without TTL so backup duration does not make the test inconclusive. Remove it from both source and restored databases when finished.

Before backup:
```redis
SET tutorial:backup:marker "restore-check"
GET tutorial:backup:marker
```

After restore, check that GET tutorial:backup:marker returns restore-check. Separately verify representative expiring records with their elapsed TTL, types, application reads, and recovery duration. Clean up the marker in both databases with DEL tutorial:backup:marker.

## Cutover and rollback

Validate destination access, TLS, configuration, and application compatibility. Freeze or coordinate writes if needed to prevent divergence. Document endpoint cutover, reconciliation, and rollback behavior.

## Acceptance and references

Acceptance: successful backup, isolated restore, verified data, measured recovery time, and documented limitations.

- [Import/export and backups](https://redis.io/docs/latest/operate/rs/databases/import-export/)
- [Database recovery](https://redis.io/docs/latest/operate/rs/databases/recover/)

**Next:** [19 — Upgrades and Maintenance](19-upgrades-and-maintenance.md)
