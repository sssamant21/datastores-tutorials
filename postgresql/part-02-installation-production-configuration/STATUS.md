# Part 2 — Installation & Production Configuration — Status

**Canonical + merged:** 5/15

| Section | Title | Status |
| --- | --- | --- |
| 2.1 | PostgreSQL Installation Architecture and Planning | CANONICAL + MERGED |
| 2.2 | Linux Host Preparation and Prerequisites | CANONICAL + MERGED |
| 2.3 | Package-Based PostgreSQL Installation | CANONICAL + MERGED |
| 2.4 | Source Installation and Build Fundamentals | CANONICAL + MERGED |
| 2.5 | Cluster Initialization with `initdb` | CANONICAL + MERGED |
| 2.6 | Data Directory, Tablespace, and Filesystem Design | Not started |
| 2.7 | PostgreSQL Service Management with systemd | Not started |
| 2.8 | Memory and Resource Configuration | Not started |
| 2.9 | Connection, Session, and Process Configuration | Not started |
| 2.10 | Authentication and Network Access Baseline | Not started |
| 2.11 | WAL, Checkpoint, and Background Writer Configuration | Not started |
| 2.12 | Logging, Diagnostics, and Observability Configuration | Not started |
| 2.13 | Linux OS, Kernel, Filesystem, and Resource-Limit Considerations | Not started |
| 2.14 | Production Configuration Baseline and Validation | Not started |
| 2.15 | Integrated Project — Build a Production-Style PostgreSQL Server from Scratch | Not started |

## Canonical Evidence — 2.1

- Manuscript: `2.1-postgresql-installation-architecture-and-planning.md`
- Acceptance artifact: `labs/server-design-check.sh`
- Lab classification: `[TUTORIAL-ACCEPTANCE — SAFE-READ]`

## Canonical Evidence — 2.2

- Manuscript: `2.2-linux-host-preparation-and-prerequisites.md`
- Acceptance artifact: `labs/host-readiness-check.sh`
- Lab classification: `[TUTORIAL-ACCEPTANCE — SAFE-READ]`

## Canonical Evidence — 2.3

- Manuscript: `2.3-package-based-postgresql-installation.md`
- Acceptance artifact: `labs/postgres-install-check.sh`
- Installation classification: `[TUTORIAL-OPERATOR-ACTION — MUTATING]`
- Acceptance classification: `[TUTORIAL-ACCEPTANCE — SAFE-READ]`

## Canonical Evidence — 2.4

- Manuscript: `2.4-source-installation-and-build-fundamentals.md`
- Acceptance artifact: `labs/source-install-check.sh`
- Build classification: `[TUTORIAL-OPERATOR-ACTION — MUTATING]`
- Regression-test classification: `[TUTORIAL-OPERATOR-ACTION — MUTATING / TEMPORARY TEST RUNTIME]`
- Acceptance classification: `[TUTORIAL-ACCEPTANCE — SAFE-READ]`

## Canonical Evidence — 2.5

- Manuscript: `2.5-cluster-initialization-with-initdb.md`
- Acceptance artifact: `labs/cluster-init-check.sh`
- Initialization classification: `[TUTORIAL-OPERATOR-ACTION — MUTATING]`
- Acceptance classification: `[TUTORIAL-ACCEPTANCE — SAFE-READ]`

**Next workflow stage:** Part 2.6 — Data Directory, Tablespace, and Filesystem Design → Draft + Hands-On Lab.
