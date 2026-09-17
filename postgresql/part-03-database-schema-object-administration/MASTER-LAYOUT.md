# Part 3 — Database, Schema & Object Administration

**Status:** LOCKED — Master Layout v1.0
**Target:** PostgreSQL 18

## Objective

Build the PostgreSQL object-administration skills required to design, create, inspect, change, validate, and safely retire application database objects while preserving ownership, dependency, and production-safety boundaries.

Part 3 follows the same 15-section progression used by Parts 1 and 2. Each section contributes a reusable hands-on artifact toward the integrated application-database administration project in 3.15.

## Master Layout — 3.1–3.15

| Section | Title | Primary Hands-On Outcome |
| --- | --- | --- |
| **3.1** | **Database Administration Fundamentals** | Create, inspect, alter, and safely retire a lab database while understanding database-level ownership and connection boundaries. |
| **3.2** | **Schema Design and Administration** | Design and administer application schemas, naming boundaries, ownership, and `search_path` safely. |
| **3.3** | **Table Design and Lifecycle Administration** | Create and inspect production-style tables and perform controlled table lifecycle changes. |
| **3.4** | **Constraints and Data Integrity** | Implement and validate `NOT NULL`, `CHECK`, `UNIQUE`, primary-key, and foreign-key integrity rules. |
| **3.5** | **Sequences and Identity Columns** | Administer sequences and identity columns and understand ownership, generation, and synchronization behavior. |
| **3.6** | **Generated Columns and Default Values** | Use defaults and generated columns deliberately and validate their operational behavior. |
| **3.7** | **ALTER TABLE and Safe Schema Evolution** | Perform controlled column, constraint, default, and table changes with dependency, locking, validation, and rollback awareness. |
| **3.8** | **Views and View Administration** | Create, replace, inspect, and safely administer views while understanding ownership and dependencies. |
| **3.9** | **Materialized Views and Refresh Operations** | Create, index, inspect, refresh, and operationally manage materialized views. |
| **3.10** | **Functions and Procedures — Administration Fundamentals** | Create and inspect routines while understanding signatures, ownership, replacement semantics, volatility/security boundaries, and dependencies. |
| **3.11** | **Extensions and Extension Lifecycle Administration** | Inspect available/installed extensions and practice controlled extension installation, update planning, and removal in an isolated lab. |
| **3.12** | **Object Ownership, Dependencies, and Safe DROP Operations** | Trace object ownership and dependencies before reassignment, alteration, or destructive operations. |
| **3.13** | **Object Metadata and Catalog-Based Administration** | Use PostgreSQL catalogs and information-schema views to build a reliable object inventory without mutating production state. |
| **3.14** | **Application Database Administration Baseline and Validation** | Assemble and validate a production-style database/schema/object administration baseline. |
| **3.15** | **Integrated Project — Build and Administer an Application Database** | Build, evolve, validate, inventory, and safely decommission selected objects in a complete application database. |

## Learning Progression

**Database → Schema → Table → Integrity → Value Generation → Schema Evolution → Views → Materialized Views → Routines → Extensions → Ownership & Dependencies → Catalog Inventory → Baseline → Integrated Project**

## Scope Boundaries

Part 3 focuses on database and object administration. Detailed role/privilege architecture, default privileges, row-level security, `SECURITY DEFINER` hardening, and TLS belong primarily to Part 4 — Users, Roles & Security. Index design and query-performance tuning belong primarily to Parts 8 and 9. Storage internals and WAL belong to Part 5.

Security or privilege implications that are necessary to administer an object safely are still identified here, but Part 3 does not duplicate the full security curriculum.

## PostgreSQL 18 Technical Baseline

Part 3 must account for PostgreSQL 18 data-definition behavior, including identity and generated columns, constraint semantics, dependency tracking, schemas, views/materialized views, routines, and extensions. PostgreSQL 18-specific constraint capabilities must not be silently generalized to older server versions.

## Integrated Project — 3.15

The final project must require the learner to perform the complete workflow rather than repeat isolated examples:

1. Define the application-database contract and naming model.
2. Create an isolated lab database.
3. Create application schemas.
4. Create related tables with explicit data types.
5. Define primary keys and required `NOT NULL` rules.
6. Add `CHECK`, `UNIQUE`, and foreign-key constraints.
7. Use identity/sequence-backed key generation deliberately.
8. Add defaults and an appropriate generated-column example.
9. Load controlled sample data and validate integrity failures safely.
10. Perform a reviewed schema-evolution change.
11. Create an application-facing view.
12. Create and refresh a materialized view.
13. Create a small lab function and procedure where appropriate.
14. Inspect extension state; install an extension only when the isolated lab explicitly permits mutation.
15. Inventory object ownership.
16. Trace dependencies before an object change or drop.
17. Inspect object metadata through supported catalogs/information-schema views.
18. Validate the final object baseline.
19. Demonstrate a safe decommission plan for selected lab objects.
20. Run the final application-database acceptance suite.

## Planned Lab Artifacts

```text
labs/
├── database-admin-check.sql
├── schema-admin-check.sql
├── table-lifecycle-check.sql
├── constraints-check.sql
├── sequence-identity-check.sql
├── generated-defaults-check.sql
├── schema-evolution-check.sql
├── views-check.sql
├── materialized-views-check.sql
├── routines-check.sql
├── extensions-check.sql
├── ownership-dependency-check.sql
├── object-inventory-check.sql
├── object-baseline-check.sql
└── application-database-acceptance.sql
```

Inspection and acceptance artifacts default to **[TUTORIAL-ACCEPTANCE — SAFE-READ]** whenever their learning objective can be validated without mutation. Labs that intentionally create, alter, refresh, install, or drop objects must be explicitly marked **[LAB-ONLY — MUTATING]** or the applicable production-change classification, use isolated tutorial objects, define prerequisites and cleanup, and must never imply that destructive commands are safe merely because they are shown in a tutorial.

## Production-Safety Rules

- Never use `DROP ... CASCADE` as a generic cleanup shortcut.
- Inspect dependencies before destructive object changes.
- Treat ownership changes as security-sensitive administrative changes.
- Treat `ALTER TABLE`, constraint validation, materialized-view refresh, extension lifecycle operations, and other potentially locking or resource-intensive actions as reviewed changes.
- Use schema-qualified names in administrative examples when ambiguity matters.
- Do not expose secrets or real production data in labs.
- Keep security-sensitive routine behavior within explicit review boundaries and defer full privilege/security architecture to Part 4.

## Canonical Workflow

Each section follows:

1. Draft + Hands-On Lab
2. Technical + PostgreSQL 18 Vendor Source Review
3. Production + Safety + Copyright Review
4. Revised Final / Canonical Edition + canonical acceptance artifact
5. Commit to `main`, update Part 3 status, fetch back, and verify

## Lock Declaration

This document is the authoritative **Part 3 — Database, Schema & Object Administration — Master Layout v1.0**.

The section numbering and primary scope for **3.1–3.15 are locked**. Later structural changes must be intentional, reviewed, and recorded rather than introduced implicitly while drafting individual tutorials.

**Next workflow stage:** Part 3.1 — Database Administration Fundamentals → Draft + Hands-On Lab.
