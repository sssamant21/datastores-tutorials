# Part 2 — Installation & Production Configuration

**Status:** LOCKED — Master Layout v1.0

## Objective

Build, configure, validate, operate, and troubleshoot a production-style PostgreSQL 18 server on Linux from the ground up.

The Part 2 workflow retains the 15-section structure used for Part 1. Each section contributes knowledge or a reusable validation artifact toward the final integrated production-server build in 2.15.

## Master Layout — 2.1–2.15

| Section | Title | Primary Hands-On Outcome |
| --- | --- | --- |
| **2.1** | **PostgreSQL Installation Architecture and Planning** | Design the target PostgreSQL server before installation. |
| **2.2** | **Linux Host Preparation and Prerequisites** | Prepare and validate the Linux host for PostgreSQL. |
| **2.3** | **Package-Based PostgreSQL Installation** | Install PostgreSQL 18 using supported OS packages/repositories and verify the installation. |
| **2.4** | **Source Installation and Build Fundamentals** | Build PostgreSQL from source in an isolated lab and understand the operational tradeoffs. |
| **2.5** | **Cluster Initialization with `initdb`** | Initialize and inspect a PostgreSQL database cluster correctly. |
| **2.6** | **Data Directory, Tablespace, and Filesystem Design** | Design production storage, `PGDATA`, tablespace, and filesystem layout. |
| **2.7** | **PostgreSQL Service Management with systemd** | Configure and validate controlled startup, shutdown, restart, reload, and boot behavior. |
| **2.8** | **Memory and Resource Configuration** | Establish a conservative production memory and resource baseline. |
| **2.9** | **Connection, Session, and Process Configuration** | Configure connection limits, timeouts, listening behavior, and session controls. |
| **2.10** | **Authentication and Network Access Baseline** | Configure `listen_addresses`, `pg_hba.conf`, authentication, and controlled remote access. |
| **2.11** | **WAL, Checkpoint, and Background Writer Configuration** | Establish a safe WAL/checkpoint baseline and understand the operational tradeoffs. |
| **2.12** | **Logging, Diagnostics, and Observability Configuration** | Configure useful production logging and operational visibility. |
| **2.13** | **Linux OS, Kernel, Filesystem, and Resource-Limit Considerations** | Validate host-level PostgreSQL requirements and operational limits without relying on obsolete tuning folklore. |
| **2.14** | **Production Configuration Baseline and Validation** | Assemble and validate the complete production configuration baseline. |
| **2.15** | **Integrated Project — Build a Production-Style PostgreSQL Server from Scratch** | Build and validate the complete server from a fresh Linux host using the practices developed throughout Part 2. |

## Learning Progression

**Plan → Prepare OS → Install → Initialize → Design Storage → Manage Service → Configure Resources → Configure Access → Configure WAL → Configure Observability → Validate Host → Validate Baseline → Build Everything**

## Integrated Project — 2.15

The final project must require the learner to perform the complete workflow rather than simply repeat individual walkthroughs:

1. Assess the Linux host.
2. Produce an installation plan.
3. Install PostgreSQL 18.
4. Verify binaries and package provenance.
5. Design the storage layout.
6. Initialize the database cluster.
7. Configure ownership and permissions.
8. Configure systemd.
9. Establish memory settings.
10. Configure connections and timeouts.
11. Configure authentication.
12. Establish controlled network access.
13. Configure the WAL/checkpoint baseline.
14. Configure production logging.
15. Validate OS and resource limits.
16. Start PostgreSQL.
17. Validate configuration.
18. Create a test database.
19. Create a restricted application role.
20. Test local connectivity.
21. Test authorized remote connectivity.
22. Verify unauthorized connectivity is rejected.
23. Generate and locate diagnostic/logging events.
24. Validate restart persistence.
25. Run the production-readiness acceptance suite.

## Planned Lab Artifacts

```text
labs/
├── host-readiness-check.sh
├── postgres-install-check.sh
├── cluster-init-check.sh
├── storage-layout-check.sh
├── systemd-check.sh
├── memory-config-check.sql
├── connection-config-check.sql
├── authentication-check.sh
├── wal-config-check.sql
├── logging-check.sql
├── os-baseline-check.sh
├── production-baseline-check.sh
└── production-server-acceptance.sh
```

Inspection and acceptance artifacts should default to **SAFE-READ** behavior. Installation, initialization, configuration changes, service restarts, firewall changes, permissions changes, and other mutations remain explicit operator actions and must be clearly identified in their respective tutorials.

## Lock Declaration

This document is the authoritative **Part 2 — Installation & Production Configuration — Master Layout v1.0**.

The section numbering and primary scope for **2.1–2.15 are locked**. Any later structural change should be intentional, reviewed, and recorded rather than introduced implicitly while drafting individual sections.

**Next workflow stage:** Part 2.1 — PostgreSQL Installation Architecture and Planning → Introduction → Draft + Hands-On Server Design Lab.
