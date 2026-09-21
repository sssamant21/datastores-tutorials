# Part 5 — Backup, Recovery & Disaster Recovery — Status

**Status:** ACTIVE
**Canonical progress:** **2/15 canonical + merged**
**Target:** PostgreSQL 18
**Authoritative layout:** `MASTER-LAYOUT.md` — LOCKED, Master Layout v1.0

| Section | Title | Status |
| --- | --- | --- |
| 5.1 | Backup and Recovery Fundamentals | CANONICAL + MERGED |
| 5.2 | Logical Backups with `pg_dump` | CANONICAL + MERGED |
| 5.3 | Restore and Selective Recovery with `pg_restore` | NEXT |
| 5.4 | Cluster-Wide Logical Backup with `pg_dumpall` | PLANNED |
| 5.5 | Physical Backup Architecture and `pg_basebackup` | PLANNED |
| 5.6 | WAL Fundamentals for Backup and Recovery | PLANNED |
| 5.7 | Continuous WAL Archiving and Archive Operations | PLANNED |
| 5.8 | Point-in-Time Recovery — PITR | PLANNED |
| 5.9 | Recovery Targets, Timelines, and Recovery Control | PLANNED |
| 5.10 | Replication Slots, WAL Retention, and Disk-Risk Management | PLANNED |
| 5.11 | Backup Validation, Integrity, and Restore Testing | PLANNED |
| 5.12 | RPO, RTO, Retention, and Backup Capacity Planning | PLANNED |
| 5.13 | High Availability vs Backup vs Disaster Recovery | PLANNED |
| 5.14 | Production Backup/Recovery Runbook and Recovery Readiness | PLANNED |
| 5.15 | Integrated Project — Design, Validate, and Rehearse a Recovery Strategy | PLANNED |

## Planned canonical artifacts

| Section | Acceptance artifact |
| --- | --- |
| 5.1 | `labs/backup-recovery-fundamentals-check.sql` |
| 5.2 | `labs/pg-dump-readiness-check.sql` |
| 5.3 | `labs/pg-restore-readiness-check.sql` |
| 5.4 | `labs/pg-dumpall-readiness-check.sql` |
| 5.5 | `labs/basebackup-readiness-check.sql` |
| 5.6 | `labs/wal-recovery-readiness-check.sql` |
| 5.7 | `labs/wal-archive-check.sql` |
| 5.8 | `labs/pitr-readiness-check.sql` |
| 5.9 | `labs/recovery-target-check.sql` |
| 5.10 | `labs/wal-retention-check.sql` |
| 5.11 | `labs/backup-validation-check.sql` |
| 5.12 | `labs/recovery-objectives-check.sql` |
| 5.13 | `labs/ha-dr-readiness-check.sql` |
| 5.14 | `labs/recovery-readiness-check.sql` |
| 5.15 | `labs/disaster-recovery-acceptance.sql` |

## Next workflow stage

Part 5.3 — Restore and Selective Recovery with `pg_restore` → Draft + Hands-On Lab (`labs/pg-restore-readiness-check.sql`).
