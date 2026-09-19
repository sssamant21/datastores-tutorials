# Part 3 — Database, Schema & Object Administration — Status

**Status:** CLOSED
**Canonical + merged:** **15/15**
**Target:** PostgreSQL 18  
**Authoritative layout:** `MASTER-LAYOUT.md` — LOCKED, Master Layout v1.0

| Section | Title | Status |
| --- | --- | --- |
| 3.1 | Database Administration Fundamentals | CANONICAL / MERGED |
| 3.2 | Schema Design and Administration | CANONICAL / MERGED |
| 3.3 | Table Design and Lifecycle Administration | CANONICAL / MERGED |
| 3.4 | Constraints and Data Integrity | CANONICAL / MERGED |
| 3.5 | Sequences and Identity Columns | CANONICAL / MERGED |
| 3.6 | Generated Columns and Default Values | CANONICAL / MERGED |
| 3.7 | ALTER TABLE and Safe Schema Evolution | CANONICAL / MERGED |
| 3.8 | Views and View Administration | CANONICAL / MERGED |
| 3.9 | Materialized Views and Refresh Operations | CANONICAL / MERGED |
| 3.10 | Functions and Procedures — Administration Fundamentals | CANONICAL / MERGED |
| 3.11 | Extensions and Extension Lifecycle Administration | CANONICAL / MERGED |
| 3.12 | Object Ownership, Dependencies, and Safe DROP Operations | CANONICAL / MERGED |
| 3.13 | Object Metadata and Catalog-Based Administration | CANONICAL / MERGED |
| 3.14 | Application Database Administration Baseline and Validation | CANONICAL / MERGED |
| 3.15 | Integrated Project — Build and Administer an Application Database | CANONICAL / MERGED |

## Canonical artifacts for 3.1

- `3.1-database-administration-fundamentals.md`
- `labs/database-admin-check.sql`

## Canonical artifacts for 3.2

- `3.2-schema-design-and-administration.md`
- `labs/schema-admin-check.sql`

## Canonical artifacts for 3.3

- `3.3-table-design-and-lifecycle-administration.md`
- `labs/table-lifecycle-check.sql`

## Canonical artifacts for 3.4

- `3.4-constraints-and-data-integrity.md`
- `labs/constraints-integrity-lab.sql`

## Canonical artifacts for 3.5

- `3.5-sequences-and-identity-columns.md`
- `labs/sequences-identity-lab.sql`

## Canonical artifacts for 3.6

- `3.6-generated-columns-and-default-values.md`
- `labs/generated-defaults-lab.sql`

## Canonical artifacts for 3.7

- `3.7-alter-table-and-safe-schema-evolution.md`
- `labs/alter-table-evolution-lab.sql`

## Canonical artifacts for 3.8

- `3.8-views-and-view-administration.md`
- `labs/views-administration-lab.sql`

## Canonical artifacts for 3.9

- `3.9-materialized-views-and-refresh-operations.md`
- `labs/materialized-views-refresh-lab.sql`

## Canonical artifacts for 3.10

- `3.10-functions-and-procedures-administration-fundamentals.md`
- `labs/functions-procedures-check.sql`

## Canonical artifacts for 3.11

- `3.11-extensions-and-extension-lifecycle-administration.md`
- `labs/extensions-lifecycle-lab.sql`

## Canonical artifacts for 3.12

- `3.12-object-ownership-dependencies-and-safe-drop-operations.md`
- `labs/ownership-dependency-check.sql`

## Canonical artifacts for 3.13

- `3.13-object-metadata-and-catalog-based-administration.md`
- `labs/object-inventory-check.sql`

## Canonical artifacts for 3.14

- `3.14-application-database-administration-baseline-and-validation.md`
- `labs/object-baseline-check.sql`

## Canonical artifacts for 3.15

- `3.15-integrated-project-build-and-administer-an-application-database.md`
- `labs/application-database-acceptance.sql`

## Closure evidence

- All sections 3.1–3.15 are present on `main` and map to the locked Part 3 progression.
- Every section has its planned canonical hands-on or acceptance artifact under `labs/`.
- Mutating database and object operations remain explicit lab actions in the tutorials.
- Acceptance and inspection artifacts remain SAFE-READ and do not intentionally change database state.
- Part 3.14 defines the reusable administration baseline.
- Part 3.15 integrates database, schema, table, constraint, identity, generated-column, view, materialized-view, routine, extension, ownership, metadata, dependency, and decommission-planning concepts.

## Part 3 closure

Part 3 — Database, Schema & Object Administration is **15/15 CANONICAL + MERGED** and **CLOSED**.

## Next workflow stage

Design and lock the Part 4 — Users, Roles & Security master layout before drafting Part 4.1.
