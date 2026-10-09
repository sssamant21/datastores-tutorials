# Redis Enterprise Production Engineering — Status

**Updated:** 2026-10-09
**Curriculum target:** 80 chapters
**Content progress:** 51/80
**Remaining:** 29
**Current chapter:** 52 — Redis Enterprise Data Migration, Import/Export & Cutover Engineering

## Reconciliation Completed

The curriculum was reconciled against the actual repository sequence on 2026-10-09.

Structural corrections completed:

- Chapter 42 restored as **Upgrades, Maintenance & Change Engineering**.
- Duplicate Chapter 44 security content replaced by **Governance, Standards & Operational Readiness Engineering**.
- Duplicate/overlapping Chapter 47 capacity content replaced by **Database Lifecycle, Provisioning & Configuration Engineering**.
- Chapter 51 added as the **End-to-End Production Engineering Project**.
- MASTER-LAYOUT.md replaced with the authoritative 01–80 roadmap.
- Chapters 52–80 now cover remaining advanced topics rather than repeating completed subjects.

## Current State

| Range | State |
|---|---|
| 01–20 | Content present |
| 21–30 | Content present; Chapter 21/27 overlap flagged for final deduplication review |
| 31–38 | Content present |
| 39–44 | Content present and structurally reconciled |
| 45–51 | Content present and structurally reconciled |
| 52–80 | Planned in MASTER-LAYOUT.md |

## Authoritative Curriculum

MASTER-LAYOUT.md is the authoritative roadmap.

Do not use the earlier 2/80 tracker state or the former 36-chapter layout as the curriculum definition.

## Canonical Standard

Where applicable, chapters should include:

- concepts;
- architecture/internal behavior;
- operational commands/examples;
- hands-on lab;
- expected results;
- safe failure injection;
- troubleshooting;
- production considerations;
- operational runbooks;
- validation questions/checklists;
- cleanup;
- exact-version vendor-documentation validation.

## Validation Status

Repository content presence is not the same as live production validation.

Environment-specific validation still requires the exact deployed Redis Enterprise version/topology, client versions, supported staging endpoint, certificates, scoped identity, and approval for failover/restore/upgrade/failure exercises.

## Known Final-Review Item

Chapters 21 and 27 both cover pipelining/batching. They are intentionally retained during the build because Chapter 27 contains high-throughput engineering material, but they require a final content-deduplication pass before 80/80 completion.

## Progress

```text
Content present: 51 / 80
Remaining:       29
Next:            52
Target:          80 / 80
```

## Next

**Chapter 52 — Redis Enterprise Data Migration, Import/Export & Cutover Engineering**
