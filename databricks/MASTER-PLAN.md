# Databricks Tutorial Master Plan

Version: 1.0 | Planned: 2026-10-09 | Status: curriculum defined; 5/100 chapters authored; 0/100 labs validated.

## Purpose and scope

Build a practical, production-focused learning path from Databricks fundamentals to data engineering, analytics, ML, application integration, and SRE operations. This is a curriculum and authoring plan, not a claim that tutorials or labs are complete. It includes 100 chapters across 20 parts, with one hands-on lab per chapter and five final projects.

Use Python, PySpark, and SQL. Use AWS examples as the initial cloud track, with explicit Azure/GCP differences and a GovCloud availability checklist. Feature availability must be verified for each workspace, region, edition, runtime, and access mode before authoring a lab. Free or restricted workspaces may require a simulation or alternative; label that limitation and do not claim production validation.

## Lab environment and dataset

Prerequisites: basic SQL, Python, Git, cloud storage, and IAM concepts. Introduce Spark from the beginning; prior Spark experience is not required. Provision only disposable lab resources with an agreed budget, isolated catalog/schema or equivalent, and permission to create the relevant resources.

Use synthetic encounters, patients, facilities, and event data with deterministic IDs. Never use real patient records. Include duplicates, nulls, malformed JSON, late events, schema changes, and CDC insert/update/delete cases. Use a synthetic classification target for ML demonstrations; results are educational and are not a clinical risk model.

Core labs use a small dataset; scale tests use a separately documented dataset and budget. Record runtime/library versions, cloud, compute type, identity, and configuration for reproducibility. Stop unused compute and remove disposable endpoints after labs.

## Architecture covered

Data track: source systems → ingestion → bronze → silver → gold → SQL/reporting or model training.

Model artifact track: training → registered/versioned artifact → application backend loads trusted artifact → prediction returned to UI.

Model service track: training/model selection → deployed serving endpoint → application backend calls API → result returned to UI.

External deployment track: exported artifact or model weights → container → Kubernetes/TrueFoundry → API. Use vLLM for compatible LLM serving rather than treating it as a general scikit-learn server. Application integration must cover input validation, preprocessing consistency, authentication, timeouts, versioning, and rollback.

## Ordered curriculum

Chapters 001–005 are authored; Chapters 006–100 remain **Planned**. See the progress tracker for validation status. The lab column describes the minimum practical outcome; the full chapter must provide commands, expected results, validation, troubleshooting, and cleanup.

### Part 01 — Foundations & Architecture

| Chapter | Tutorial | Hands-on lab / acceptance focus |
|---|---|---|
| 001 | What Is Databricks? | Identify ingestion, storage, compute, governance, analytics, and model serving in a sample architecture. |
| 002 | Data Lakes, Warehouses & Lakehouses | Compare raw files, warehouse tables, and Delta tables using one dataset. |
| 003 | Control Plane, Compute Plane & Cloud Storage | Draw workspace and storage boundaries; trace a notebook read. |
| 004 | Spark, Delta Lake, Unity Catalog & MLflow | Map each component to an observable operation. |
| 005 | Databricks, Snowflake, Kubernetes & TrueFoundry | Design separate data processing and model deployment paths. |

### Part 02 — Workspace & Lab Setup

| Chapter | Tutorial | Hands-on lab / acceptance focus |
|---|---|---|
| 006 | Workspace Navigation & Environment Inventory | Record cloud, region, edition, permissions, and available compute. |
| 007 | Lab Identity, Catalog, Schema & Volumes | Create an isolated namespace and verify authorized read/write access. |
| 008 | Notebooks, SQL Editor & Git Folders | Run and version a Python notebook and SQL query. |
| 009 | Python, SQL & Dependency Setup | Pin dependencies and reproduce a small transformation. |
| 010 | Synthetic Dataset & First End-to-End Lab | Load synthetic encounters and reconcile source and destination counts. |

### Part 03 — Compute & Platform Administration

| Chapter | Tutorial | Hands-on lab / acceptance focus |
|---|---|---|
| 011 | Classic Compute, Serverless & SQL Warehouses | Select compute for interactive work, jobs, and SQL; document availability. |
| 012 | Runtime Versions, Access Modes & Libraries | Test a supported runtime and diagnose a library mismatch. |
| 013 | Sizing, Autoscaling & Auto-Termination | Measure run time and verify idle compute shutdown. |
| 014 | Compute Policies, Pools & Quotas | Apply limits and demonstrate a rejected configuration where supported. |
| 015 | Compute Startup & Capacity Troubleshooting | Investigate a startup failure using events and cloud evidence. |

### Part 04 — Spark & PySpark Fundamentals

| Chapter | Tutorial | Hands-on lab / acceptance focus |
|---|---|---|
| 016 | Spark Driver, Executors, Tasks & Stages | Locate a job, stage, and task in the Spark UI. |
| 017 | DataFrames, Schemas & Lazy Evaluation | Build an explicit schema and inspect a query plan. |
| 018 | Transformations, Actions & Built-In Functions | Clean records without unnecessary Python UDFs. |
| 019 | Joins, Aggregations & Window Functions | Produce a latest-record view and validate duplicate handling. |
| 020 | Partitions, Shuffle & Persistence | Compare shuffle behavior and remove unnecessary caching. |

### Part 05 — Delta Lake & Table Operations

| Chapter | Tutorial | Hands-on lab / acceptance focus |
|---|---|---|
| 021 | Delta Transactions & Table History | Write a table and inspect committed versions. |
| 022 | Managed Tables, External Tables & Storage Ownership | Compare lifecycle behavior using disposable resources. |
| 023 | Schema Enforcement & Controlled Evolution | Reject an incompatible write and approve a planned schema change. |
| 024 | MERGE, Updates, Deletes & Idempotency | Replay a batch twice and verify stable business keys. |
| 025 | Time Travel, RESTORE & VACUUM Retention | Recover a disposable table and explain retention limits. |

### Part 06 — Unity Catalog & Data Governance

| Chapter | Tutorial | Hands-on lab / acceptance focus |
|---|---|---|
| 026 | Metastores, Catalogs, Schemas & Securables | Map the object hierarchy and ownership. |
| 027 | Users, Groups, Service Principals & Grants | Demonstrate allowed and denied operations with test identities. |
| 028 | Storage Credentials, External Locations & Volumes | Verify both cloud access and catalog permissions. |
| 029 | Views, Row Filters & Column Masks | Validate access to synthetic sensitive fields where supported. |
| 030 | Lineage, Audit Evidence & Access Reviews | Trace a transformation and produce an access review. |

### Part 07 — Batch Ingestion & Source Integration

| Chapter | Tutorial | Hands-on lab / acceptance focus |
|---|---|---|
| 031 | CSV, JSON, Parquet & Nested Records | Ingest three formats and quarantine malformed records. |
| 032 | Auto Loader & Incremental File Discovery | Process new files and verify restart behavior. |
| 033 | JDBC Ingestion from PostgreSQL | Load a bounded dataset and reconcile counts without overloading the source. |
| 034 | MongoDB Exports & Connector Integration | Normalize nested synthetic documents; document connector requirements. |
| 035 | Lakeflow Connect & Connector Selection | Compare managed and custom ingestion; test one available connector. |

### Part 08 — Medallion Architecture & Data Quality

| Chapter | Tutorial | Hands-on lab / acceptance focus |
|---|---|---|
| 036 | Bronze Layer & Source Metadata | Preserve raw records with ingest timestamp and source identifier. |
| 037 | Silver Layer: Cleaning & Deduplication | Deduplicate using deterministic ordering. |
| 038 | Gold Layer: Facts, Dimensions & Aggregates | Build a reporting model with validated keys. |
| 039 | Quality Rules, Quarantine & Reconciliation | Inject bad data and report accepted, rejected, and missing records. |
| 040 | Contracts, Schema Drift & Late-Arriving Data | Handle added columns and delayed business events. |

### Part 09 — Streaming & CDC

| Chapter | Tutorial | Hands-on lab / acceptance focus |
|---|---|---|
| 041 | Structured Streaming & Checkpoints | Restart a stream and verify state recovery. |
| 042 | Kafka/MSK Integration & Offset Handling | Consume synthetic events and inspect lag and offsets. |
| 043 | Watermarks, Windows & Stateful Processing | Test late events against a defined lateness policy. |
| 044 | Database CDC, Deletes & SCD Types 1/2 | Apply insert/update/delete events and validate history. |
| 045 | Change Data Feed, Replay & Recovery Boundaries | Read Delta changes and document retention and downstream replay limits. |

### Part 10 — Lakeflow Spark Declarative Pipelines

| Chapter | Tutorial | Hands-on lab / acceptance focus |
|---|---|---|
| 046 | Pipeline Concepts & Dataset Dependencies | Create a small declared pipeline and inspect its dependency graph. |
| 047 | Streaming Tables & Materialized Views | Select an appropriate dataset type and verify refresh behavior. |
| 048 | Expectations & Event Logs | Introduce invalid records and inspect quality metrics. |
| 049 | AUTO CDC & Ordered Change Application | Apply out-of-order CDC events using supported APIs. |
| 050 | Pipeline Updates, Backfills & Recovery | Recompute a bounded range and reconcile the result. |

### Part 11 — Jobs & Orchestration

| Chapter | Tutorial | Hands-on lab / acceptance focus |
|---|---|---|
| 051 | Lakeflow Jobs: Tasks, Dependencies & Parameters | Build a parameterized multi-task job. |
| 052 | Schedules, Triggers & Concurrency | Prevent overlapping runs and verify trigger behavior. |
| 053 | Retries, Timeouts & Repair Runs | Fail one task and recover without duplicating output. |
| 054 | REST API, CLI & SDK Automation | Submit a run and poll its status using a service identity. |
| 055 | Kubernetes CronJob Integration | Trigger a job from a lab CronJob and avoid duplicate submissions. |

### Part 12 — SQL Analytics & Business Consumption

| Chapter | Tutorial | Hands-on lab / acceptance focus |
|---|---|---|
| 056 | SQL Warehouses & Query Execution | Execute and profile a representative analytics query. |
| 057 | Advanced SQL & Semi-Structured Analysis | Query nested records and validate window calculations. |
| 058 | Dashboards, Parameters & Alerts | Build a dashboard with freshness and quality indicators. |
| 059 | BI Connectivity & SQL Application Access | Query through a supported SQL client with least privilege. |
| 060 | Sharing, Federation & Snowflake Interoperability | Evaluate federation, sharing, and copying; test an available path. |

### Part 13 — Performance Engineering

| Chapter | Tutorial | Hands-on lab / acceptance focus |
|---|---|---|
| 061 | Spark UI, Query Plans & Baselines | Capture a repeatable performance baseline. |
| 062 | Join Strategies, Skew & Shuffle Tuning | Identify and improve a deliberately skewed join. |
| 063 | Small Files, Compaction & Table Maintenance | Measure file counts before and after supported compaction. |
| 064 | Liquid Clustering, Partitioning & Data Skipping | Compare layout choices using a reproducible query set. |
| 065 | Photon, Caching & End-to-End Benchmarking | Measure supported execution options and record cost/performance tradeoffs. |

### Part 14 — Security, Networking & Cloud Integration

| Chapter | Tutorial | Hands-on lab / acceptance focus |
|---|---|---|
| 066 | Authentication, OAuth & Secret Handling | Run automation without embedding credentials in code. |
| 067 | AWS IAM, S3 & Cross-Account Access | Validate minimal storage permissions in an AWS lab. |
| 068 | Private Connectivity, DNS & Egress | Trace a connection failure through network and identity layers. |
| 069 | Encryption, Audit Logs & Sensitive Data Controls | Verify configured controls using synthetic data. |
| 070 | Azure, GCP & GovCloud Differences | Build a feature/region checklist and document cloud-specific alternatives. |

### Part 15 — Machine Learning & MLflow

| Chapter | Tutorial | Hands-on lab / acceptance focus |
|---|---|---|
| 071 | ML Lifecycle & Reproducible Training | Train a baseline model with a reproducible dataset split. |
| 072 | Feature Engineering & Leakage Prevention | Fit preprocessing on training data and validate holdout separation. |
| 073 | MLflow Experiments, Metrics & Artifacts | Compare tracked training runs. |
| 074 | Evaluation, Tuning & Model Selection | Select a candidate using recorded quality criteria. |
| 075 | Models in Unity Catalog & Promotion | Register a model version and perform controlled promotion. |

### Part 16 — Model Packaging & Application Integration

| Chapter | Tutorial | Hands-on lab / acceptance focus |
|---|---|---|
| 076 | Exporting joblib/pkl & MLflow Model Artifacts | Package a trusted model with preprocessing, signatures, and pinned dependencies. |
| 077 | Loading a Model in an Application Backend | Load once in a Python backend and test valid/invalid requests. |
| 078 | Batch Inference & Prediction Tables | Score a dataset and write versioned prediction output. |
| 079 | Databricks Model Serving & REST Requests | Deploy an available serving endpoint and test authentication and payloads. |
| 080 | Container Serving with Kubernetes & TrueFoundry | Build an external deployment plan and test model parity and rollback. |

### Part 17 — Generative AI & LLM Applications

| Chapter | Tutorial | Hands-on lab / acceptance focus |
|---|---|---|
| 081 | LLMs, Embeddings & Inference Architecture | Separate model training, embedding generation, and inference. |
| 082 | Retrieval & Vector Search | Index synthetic documents and evaluate retrieval quality. |
| 083 | RAG Pipeline & Backend Integration | Build a response with source references and access-aware retrieval. |
| 084 | Prompt, Retrieval & Response Evaluation | Measure quality against a fixed evaluation set. |
| 085 | LLM Serving, vLLM & Operational Tradeoffs | Compare available managed serving and external GPU serving paths. |

### Part 18 — Git, CI/CD & Infrastructure as Code

| Chapter | Tutorial | Hands-on lab / acceptance focus |
|---|---|---|
| 086 | Repository Layout & Automated Validation | Validate transformations and package structure in CI. |
| 087 | Declarative Automation Bundles | Validate and deploy a lab job from a bundle. |
| 088 | Terraform & Platform Resource Management | Plan isolated platform resources and inspect changes. |
| 089 | Dev/Staging/Prod Promotion & Rollback | Promote one version and restore the previous deployment. |
| 090 | Release Evidence & Dependency Maintenance | Record runtime, library, configuration, and model versions. |

### Part 19 — Observability, Reliability & FinOps

| Chapter | Tutorial | Hands-on lab / acceptance focus |
|---|---|---|
| 091 | System Tables, Logs & Operational Dashboards | Create run success, freshness, and resource indicators. |
| 092 | SLOs, Alerting & Incident Triage | Trigger a test failure and follow a short triage runbook. |
| 093 | Cost Attribution, Budgets & Compute Efficiency | Attribute available usage data and identify idle resources. |
| 094 | Backup, Recovery, RPO/RTO & Disaster Recovery | Restore a disposable asset and measure recovery against targets. |
| 095 | Common Failures & Production Maintenance | Diagnose permissions, OOM, skew, checkpoint, schema, and dependency failures. |

### Part 20 — End-to-End Production Projects

| Chapter | Tutorial | Hands-on lab / acceptance focus |
|---|---|---|
| 096 | Batch Lakehouse & Data Quality Project | Build bronze/silver/gold with reconciled counts, quarantine, and scheduled jobs. |
| 097 | Streaming CDC & Recovery Project | Demonstrate updates, deletes, late events, restart, replay, and bounded recovery. |
| 098 | Train, Package & Consume a Model Project | Train and register a model; compare backend artifact loading with API inference. |
| 099 | Production Deployment, Monitoring & Cost Project | Deploy through CI/CD and prove alerts, access boundaries, and usage attribution. |
| 100 | Failure Injection & Final Acceptance Project | Recover from controlled failures and publish evidence plus operational runbooks. |

## Consistent chapter format

1. Title, chapter number, status, prerequisites, and learning objectives.
2. Concept explanation with one concrete operational example.
3. Architecture and component responsibilities where useful.
4. Availability, runtime, access, and cost requirements.
5. Lab setup with exact sample data and resource names.
6. Complete numbered steps with executable SQL/Python/CLI and expected results.
7. Acceptance checks that verify behavior, including a failure or edge case.
8. Production considerations: permissions, idempotency, performance, costs, and recovery as applicable.
9. Troubleshooting table: symptom, evidence, likely cause, corrective action.
10. Cleanup and rollback instructions.
11. Review questions, official references, and previous/next navigation.

Do not mark a lab validated from syntax checks alone. Record whether execution was local, in a Databricks workspace, or a simulation. Unsupported features receive a documented alternate lab and remain unvalidated for the unavailable platform path.

## Repository layout proposal

Use a dedicated `databricks/` module in the tutorial repository. Canonical chapters use numbered Markdown filenames such as `001-what-is-databricks.md`; they are not individual README files.

| Path | Purpose |
|---|---|
| `databricks/MASTER-PLAN.md` | Curriculum and scope |
| `databricks/PROGRESS-TRACKER.md` | Chapter, lab, validation, and publication state |
| `databricks/README.md` | Module entry point and navigation |
| `databricks/chapters/001-what-is-databricks.md` | Canonical chapter format |
| `databricks/labs/001/` | Lab scripts, SQL, configuration, and expected results |
| `databricks/datasets/` | Synthetic generators and small fixtures |
| `databricks/projects/` | Final project implementations and acceptance evidence |
| `databricks/runbooks/` | Incident, recovery, maintenance, and cost runbooks |
| `databricks/tools/` | Link, syntax, and configuration validation helpers |

This layout is implemented for the master plan, tracker, and first five chapters. Additional lab/project directories will be added when their files are authored.

## Progress tracker and completion rules

Track each chapter separately with: number, title, content status, lab status, execution environment, validation date, evidence location, publication commit, and open limitations.

Content states: Planned → Draft → Reviewed → Complete. Lab states: Not started → Implemented → Executed → Validated, or Blocked with a reason. Publication state is separate from completion.

A chapter is complete only when its full content, reproducible lab, expected outputs, acceptance checks, troubleshooting, cleanup, and navigation are present and reviewed. A part is complete only when all five chapters meet those criteria. Final acceptance requires all 100 chapters plus the five project evidence sets; report blocked or simulated paths explicitly.

## Authoring and publishing workflow

Finish one chapter and its lab, validate it, update the tracker and navigation, then publish that chapter before starting the next. Record the actual commit only after publication succeeds. Never report a push based solely on a local commit. Publishing requires an available authorized repository connection.

Chapters 001–005 are now authored. Continue with Chapter 006 — Workspace Navigation & Environment Inventory. The Chapter 001 lab identifies the platform components, inspect the available workspace, run a minimal notebook/query where access exists, and explain where data, compute, and model artifacts reside.

## Learning routes

| Route | Primary parts | Expected result |
|---|---|---|
| Data engineering | 01–11, 13–14, 18–20 | Reliable batch/streaming lakehouse pipelines |
| SRE / platform administration | 01–03, 06, 11, 13–14, 18–20 | Operate, secure, monitor, recover, and control costs |
| Analytics | 01–02, 04–06, 08, 12–13 | Governed tables and SQL reporting |
| ML / application integration | 01–06, 08, 15–20 | Train, package, deploy, and consume models |

These routes reference the same canonical chapters and do not create duplicates. Complete prerequisite chapters before advanced labs.

## Source baseline and terminology

Checked against official Databricks documentation on 2026-10-09. Use current names while explaining older names encountered in existing environments: Lakeflow Spark Declarative Pipelines (older materials may say DLT) and Declarative Automation Bundles (formerly Databricks Asset Bundles). Recheck APIs and availability when implementing each chapter.

- [Databricks reference architectures](https://docs.databricks.com/aws/en/lakehouse-architecture/reference)
- [Lakehouse fundamentals](https://docs.databricks.com/aws/en/lakehouse/)
- [Pipeline naming release note](https://docs.databricks.com/aws/en/release-notes/product/2025/november)
- [Declarative Automation Bundles](https://docs.databricks.com/aws/en/dev-tools/bundles/)
- [MLflow on Databricks](https://docs.databricks.com/aws/en/mlflow/)
- [Model Serving](https://docs.databricks.com/aws/en/machine-learning/model-serving/)

