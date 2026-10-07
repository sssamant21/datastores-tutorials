# Chapter 86 --- Snowflake Batch Ingestion Production Project

## 86.1 Overview

This chapter brings together the Snowflake concepts from the previous
chapters into a production-style batch ingestion project.

The project builds:

``` text
Source System
     |
     v
Object Storage
     |
     v
External Stage
     |
     v
COPY INTO
     |
     v
RAW / L1
     |
     v
Validation
     |
     v
CURATED / L2
     |
     v
Consumer
```

The objective is not simply:

``` text
Load a CSV file into Snowflake
```

The objective is to build an ingestion process that is:

``` text
Repeatable
Secure
Observable
Recoverable
Idempotent
Scalable
Auditable
Cost-aware
Production-ready
```

**Primary rule: A production ingestion pipeline is complete only when
loading, validation, monitoring, failure handling, replay, security, and
operational ownership are all defined.**

## 86.2 Project Scenario

We will model a simplified EMPI batch ingestion pipeline.

Source data arrives in cloud object storage.

Example:

``` text
empi/
 |
 +-- 2026/
      |
      +-- 10/
           |
           +-- 07/
                |
                +-- empi_20261007_0001.csv
                +-- empi_20261007_0002.csv
                +-- empi_20261007_0003.csv
```

The files must be loaded into:

``` text
DAP.L1.EMPI_RAW
```

and transformed into:

``` text
DAP.L2.EMPI
```

## 86.3 Production Requirements

Assume:

``` text
Batch frequency: Daily
Expected arrival: 01:00 UTC
Target completion: 02:00 UTC
Expected files: 20–100
Expected rows: 5–20 million
Recovery: Replay failed batch
Retention: Per organizational policy
Environment: Production
```

## 86.4 SLA

Example SLA:

``` text
Source arrival: 01:00 UTC

L1 ingestion complete:
< 30 minutes after source arrival

L2 processing complete:
< 60 minutes after source arrival
```

## 86.5 Data Quality Requirements

Validate:

``` text
File count
Row count
Required columns
Data types
Duplicate records
Null business keys
Batch completeness
Source-to-target reconciliation
```

## 86.6 Recovery Requirements

The pipeline must support:

``` text
Retry
Replay
Partial failure recovery
Duplicate prevention
Quarantine
Controlled backfill
```

## 86.7 Security Requirements

Use:

``` text
Dedicated service identity
Dedicated role
Least privilege
Storage integration
Dedicated warehouse
Query tagging
Auditable access
```

Avoid embedding long-lived cloud credentials directly in SQL or scripts.

## 86.8 Target Architecture

``` text
        SOURCE SYSTEM
              |
              v
       OBJECT STORAGE
              |
              v
       STORAGE INTEGRATION
              |
              v
        EXTERNAL STAGE
              |
              v
         FILE FORMAT
              |
              v
         COPY INTO
              |
              v
        DAP.L1.EMPI_RAW
              |
              v
       DATA VALIDATION
              |
              v
      TRANSFORMATION
              |
              v
         DAP.L2.EMPI
              |
              v
          CONSUMERS
```

## 86.9 Operational Architecture

``` text
Scheduler
    |
    v
Batch Job
    |
    +----> Query Tag
    |
    +----> COPY INTO
    |
    +----> Validation
    |
    +----> Transformation
    |
    +----> Reconciliation
    |
    +----> Audit Record
    |
    +----> Monitoring / Alert
```

## 86.10 Object Model

We will use:

``` text
Database
  DAP

Schemas
  L1
  L2
  CONTROL

Warehouse
  EMPI_BATCH_PROD_WH

Role
  EMPI_BATCH_ROLE

Stage
  EMPI_PROD_STAGE

File format
  EMPI_CSV_FORMAT

Tables
  DAP.L1.EMPI_RAW
  DAP.L2.EMPI
  DAP.CONTROL.BATCH_RUN
  DAP.CONTROL.BATCH_FILE
  DAP.CONTROL.BATCH_ERROR
```

## 86.11 Dedicated Warehouse

Example:

``` sql
CREATE WAREHOUSE IF NOT EXISTS EMPI_BATCH_PROD_WH
    WAREHOUSE_SIZE = 'MEDIUM'
    AUTO_SUSPEND = 60
    AUTO_RESUME = TRUE
    INITIALLY_SUSPENDED = TRUE;
```

Production sizing must be based on measured workload behavior.

## 86.12 Why Dedicated Compute

A dedicated warehouse isolates the batch workload from Patient360
application, BI dashboards, ad-hoc analytics, and other ETL workloads.

This reduces noisy-neighbor risk.

## 86.13 Warehouse Ownership

Document:

``` text
Warehouse: EMPI_BATCH_PROD_WH
Purpose: EMPI production batch ingestion
Owner: Data Engineering
Backup owner: Platform/SRE
SLA: Batch complete within 60 minutes
```

## 86.14 Query Tagging

At the beginning of the batch session:

``` sql
ALTER SESSION SET QUERY_TAG =
'env=prod;service=empi;pipeline=batch_ingestion';
```

This helps identify pipeline activity in query history.

## 86.15 Database and Schemas

``` sql
CREATE DATABASE IF NOT EXISTS DAP;

CREATE SCHEMA IF NOT EXISTS DAP.L1;
CREATE SCHEMA IF NOT EXISTS DAP.L2;
CREATE SCHEMA IF NOT EXISTS DAP.CONTROL;
```

In an existing production environment, these objects should normally
already be governed through established deployment processes.

## 86.16 File Format

Example CSV format:

``` sql
CREATE OR REPLACE FILE FORMAT DAP.L1.EMPI_CSV_FORMAT
    TYPE = CSV
    FIELD_DELIMITER = ','
    SKIP_HEADER = 1
    FIELD_OPTIONALLY_ENCLOSED_BY = '"'
    NULL_IF = ('NULL', 'null', '')
    EMPTY_FIELD_AS_NULL = TRUE
    ERROR_ON_COLUMN_COUNT_MISMATCH = TRUE;
```

## 86.17 File Format Ownership

Treat file formats as production configuration.

Manage them through version control, change management, IaC where
appropriate, and testing.

## 86.18 Storage Integration

Prefer a Snowflake storage integration for supported cloud object
storage.

Conceptually:

``` sql
CREATE STORAGE INTEGRATION EMPI_STORAGE_INT
    TYPE = EXTERNAL_STAGE
    STORAGE_PROVIDER = '<provider>'
    ENABLED = TRUE
    STORAGE_ALLOWED_LOCATIONS =
        ('<cloud-storage-location>');
```

Provider-specific properties must be configured for the cloud platform
in use.

## 86.19 Storage Security

Limit allowed locations to the required paths.

Avoid granting access to an entire storage account or bucket when only
one ingestion prefix is required.

## 86.20 External Stage

Example:

``` sql
CREATE OR REPLACE STAGE DAP.L1.EMPI_PROD_STAGE
    URL = '<cloud-storage-location>/empi/'
    STORAGE_INTEGRATION = EMPI_STORAGE_INT
    FILE_FORMAT = DAP.L1.EMPI_CSV_FORMAT;
```

## 86.21 Verify Stage

``` sql
LIST @DAP.L1.EMPI_PROD_STAGE;
```

Verify expected files before ingestion.

## 86.22 Stage Path Convention

Use predictable paths.

Example:

``` text
empi/YYYY/MM/DD/
```

Benefits include replay, troubleshooting, retention, auditability, and
backfill.

## 86.23 Raw Table Design

Example:

``` sql
CREATE TABLE IF NOT EXISTS DAP.L1.EMPI_RAW (
    EMPI_ID                VARCHAR,
    SOURCE_SYSTEM          VARCHAR,
    FIRST_NAME             VARCHAR,
    LAST_NAME              VARCHAR,
    DATE_OF_BIRTH          DATE,
    ADDRESS_JSON           VARIANT,
    SOURCE_FILE_NAME       VARCHAR,
    SOURCE_FILE_ROW_NUMBER NUMBER,
    LOAD_TIMESTAMP         TIMESTAMP_LTZ,
    BATCH_ID               VARCHAR
);
```

## 86.24 Ingestion Metadata

Always consider storing ingestion metadata.

Useful fields:

``` text
SOURCE_FILE_NAME
SOURCE_FILE_ROW_NUMBER
LOAD_TIMESTAMP
BATCH_ID
```

These are invaluable during reconciliation and recovery.

## 86.25 Batch ID

Generate a unique batch identifier.

Example:

``` text
EMPI_20261007_010000
```

The batch ID should identify one logical ingestion run.

## 86.26 Batch Control Table

``` sql
CREATE TABLE IF NOT EXISTS DAP.CONTROL.BATCH_RUN (
    BATCH_ID           VARCHAR,
    PIPELINE_NAME      VARCHAR,
    STATUS             VARCHAR,
    START_TIME         TIMESTAMP_LTZ,
    END_TIME           TIMESTAMP_LTZ,
    EXPECTED_FILES     NUMBER,
    DISCOVERED_FILES   NUMBER,
    LOADED_FILES       NUMBER,
    REJECTED_FILES     NUMBER,
    SOURCE_ROWS        NUMBER,
    LOADED_ROWS        NUMBER,
    CURATED_ROWS       NUMBER,
    ERROR_MESSAGE      VARCHAR,
    CREATED_BY         VARCHAR
);
```

## 86.27 Batch Status

Recommended states:

``` text
STARTED
FILES_DISCOVERED
VALIDATING
LOADING
L1_COMPLETE
TRANSFORMING
RECONCILING
COMPLETED
FAILED
REPLAYING
```

## 86.28 File Control Table

``` sql
CREATE TABLE IF NOT EXISTS DAP.CONTROL.BATCH_FILE (
    BATCH_ID        VARCHAR,
    FILE_NAME       VARCHAR,
    FILE_SIZE       NUMBER,
    STATUS          VARCHAR,
    ROWS_PARSED     NUMBER,
    ROWS_LOADED     NUMBER,
    ERROR_COUNT     NUMBER,
    LOAD_TIME       TIMESTAMP_LTZ
);
```

## 86.29 Error Table

``` sql
CREATE TABLE IF NOT EXISTS DAP.CONTROL.BATCH_ERROR (
    BATCH_ID       VARCHAR,
    FILE_NAME      VARCHAR,
    ERROR_TIME     TIMESTAMP_LTZ,
    ERROR_TYPE     VARCHAR,
    ERROR_MESSAGE  VARCHAR,
    QUERY_ID       VARCHAR
);
```

## 86.30 Start Batch

Example:

``` sql
INSERT INTO DAP.CONTROL.BATCH_RUN (
    BATCH_ID,
    PIPELINE_NAME,
    STATUS,
    START_TIME,
    CREATED_BY
)
VALUES (
    'EMPI_20261007_010000',
    'EMPI_BATCH',
    'STARTED',
    CURRENT_TIMESTAMP(),
    CURRENT_USER()
);
```

## 86.31 File Discovery

Before loading, determine expected files, actual files, file names, file
sizes, and arrival time.

Do not start blindly if the upstream batch is incomplete.

## 86.32 Completeness Gate

Example logic:

``` text
Expected files = 50
Discovered files = 37
```

Result:

``` text
DO NOT PROCESS
```

unless partial processing is explicitly supported.

## 86.33 Stable File Gate

Avoid processing a file that is still being written by the upstream
producer.

Common patterns include:

``` text
Temporary suffix then rename
Manifest file
_SUCCESS marker
Control file
Stable-size check
```

Choose one contract with the source team.

## 86.34 Manifest Pattern

Example:

``` text
empi_20261007_0001.csv
empi_20261007_0002.csv
empi_20261007_0003.csv
manifest_20261007.json
```

The manifest can contain expected file names, file count, row count,
checksums, and batch ID.

## 86.35 Validate Before Load

Use COPY validation where appropriate.

Example:

``` sql
COPY INTO DAP.L1.EMPI_RAW
FROM (
    SELECT
        $1,
        $2,
        $3,
        $4,
        $5,
        TRY_PARSE_JSON($6),
        METADATA$FILENAME,
        METADATA$FILE_ROW_NUMBER,
        CURRENT_TIMESTAMP(),
        'EMPI_20261007_010000'
    FROM @DAP.L1.EMPI_PROD_STAGE/2026/10/07/
)
VALIDATION_MODE = 'RETURN_ALL_ERRORS';
```

## 86.36 Validation Purpose

Validation can identify malformed records, invalid dates, column
mismatch, parsing failures, and unexpected data before committing the
production load.

## 86.37 Validation Threshold

Define an explicit policy.

Example:

``` text
0 structural errors allowed
```

or:

``` text
< 0.01% known noncritical rejects
```

The threshold must be a business/data-quality decision.

## 86.38 Load Raw Data

Example:

``` sql
COPY INTO DAP.L1.EMPI_RAW (
    EMPI_ID,
    SOURCE_SYSTEM,
    FIRST_NAME,
    LAST_NAME,
    DATE_OF_BIRTH,
    ADDRESS_JSON,
    SOURCE_FILE_NAME,
    SOURCE_FILE_ROW_NUMBER,
    LOAD_TIMESTAMP,
    BATCH_ID
)
FROM (
    SELECT
        $1,
        $2,
        $3,
        $4,
        $5,
        TRY_PARSE_JSON($6),
        METADATA$FILENAME,
        METADATA$FILE_ROW_NUMBER,
        CURRENT_TIMESTAMP(),
        'EMPI_20261007_010000'
    FROM @DAP.L1.EMPI_PROD_STAGE/2026/10/07/
)
ON_ERROR = 'ABORT_STATEMENT';
```

## 86.39 Why ABORT_STATEMENT

For critical data, silently skipping malformed rows can create
incomplete datasets.

The correct `ON_ERROR` policy depends on business requirements.

## 86.40 Load Result

Capture COPY output.

Important information includes file, status, rows parsed, rows loaded,
errors, and first error.

Persist relevant results into the control tables.

## 86.41 Load History

Use Snowflake load history to investigate ingestion.

Operationally capture file name, load time, status, rows loaded, and
errors.

## 86.42 Duplicate File Protection

Snowflake maintains load metadata for COPY operations, but production
replay design should still explicitly define:

``` text
What constitutes a duplicate?
When is replay allowed?
When can FORCE be used?
Who approves it?
How is downstream duplication prevented?
```

## 86.43 FORCE Caution

Do not routinely use:

``` sql
FORCE = TRUE
```

because it can intentionally bypass normal loaded-file protections.

Use only in a controlled replay procedure.

## 86.44 Row-Level Idempotency

File-level duplicate protection may not be enough.

For important pipelines define a business key.

Example:

``` text
EMPI_ID
SOURCE_SYSTEM
SOURCE_RECORD_ID
```

## 86.45 L1 Philosophy

L1 should preserve source fidelity where practical.

Responsibilities:

``` text
Capture source
Add ingestion metadata
Minimize destructive transformation
Support replay
Support audit
```

## 86.46 L1 Validation

After COPY:

``` sql
SELECT
    BATCH_ID,
    COUNT(*) AS ROW_COUNT,
    COUNT(DISTINCT SOURCE_FILE_NAME) AS FILE_COUNT
FROM DAP.L1.EMPI_RAW
WHERE BATCH_ID = 'EMPI_20261007_010000'
GROUP BY BATCH_ID;
```

## 86.47 Required-Key Validation

``` sql
SELECT COUNT(*) AS INVALID_ROWS
FROM DAP.L1.EMPI_RAW
WHERE BATCH_ID = 'EMPI_20261007_010000'
  AND EMPI_ID IS NULL;
```

Expected: `0` unless explicitly allowed.

## 86.48 Duplicate Validation

``` sql
SELECT
    EMPI_ID,
    SOURCE_SYSTEM,
    COUNT(*) AS CNT
FROM DAP.L1.EMPI_RAW
WHERE BATCH_ID = 'EMPI_20261007_010000'
GROUP BY
    EMPI_ID,
    SOURCE_SYSTEM
HAVING COUNT(*) > 1;
```

Interpret duplicates using the actual business key.

## 86.49 JSON Validation

Example:

``` sql
SELECT
    TYPEOF(ADDRESS_JSON),
    COUNT(*)
FROM DAP.L1.EMPI_RAW
WHERE BATCH_ID = 'EMPI_20261007_010000'
GROUP BY TYPEOF(ADDRESS_JSON);
```

This is especially useful when semi-structured source fields can drift.

## 86.50 Data Type Drift

Watch for source changes such as:

``` text
DATE -> VARCHAR
NUMBER -> VARCHAR
OBJECT -> JSON string
ARRAY -> VARCHAR
```

Do not allow silent type drift to reach consumers.

## 86.51 Schema Contract

Maintain a source contract containing:

``` text
Column name
Type
Nullable
Business meaning
Required/optional
Expected format
```

## 86.52 L2 Table

Example:

``` sql
CREATE TABLE IF NOT EXISTS DAP.L2.EMPI (
    EMPI_ID          VARCHAR,
    SOURCE_SYSTEM    VARCHAR,
    FIRST_NAME       VARCHAR,
    LAST_NAME        VARCHAR,
    DATE_OF_BIRTH    DATE,
    ADDRESS          VARIANT,
    UPDATED_AT       TIMESTAMP_LTZ,
    SOURCE_BATCH_ID  VARCHAR
);
```

## 86.53 L1 to L2 Transformation

Use a deterministic transformation.

Example:

``` sql
MERGE INTO DAP.L2.EMPI T
USING (
    SELECT
        EMPI_ID,
        SOURCE_SYSTEM,
        FIRST_NAME,
        LAST_NAME,
        DATE_OF_BIRTH,
        ADDRESS_JSON,
        BATCH_ID
    FROM DAP.L1.EMPI_RAW
    WHERE BATCH_ID = 'EMPI_20261007_010000'
) S
ON T.EMPI_ID = S.EMPI_ID
AND T.SOURCE_SYSTEM = S.SOURCE_SYSTEM

WHEN MATCHED THEN UPDATE SET
    FIRST_NAME      = S.FIRST_NAME,
    LAST_NAME       = S.LAST_NAME,
    DATE_OF_BIRTH   = S.DATE_OF_BIRTH,
    ADDRESS         = S.ADDRESS_JSON,
    UPDATED_AT      = CURRENT_TIMESTAMP(),
    SOURCE_BATCH_ID = S.BATCH_ID

WHEN NOT MATCHED THEN INSERT (
    EMPI_ID,
    SOURCE_SYSTEM,
    FIRST_NAME,
    LAST_NAME,
    DATE_OF_BIRTH,
    ADDRESS,
    UPDATED_AT,
    SOURCE_BATCH_ID
)
VALUES (
    S.EMPI_ID,
    S.SOURCE_SYSTEM,
    S.FIRST_NAME,
    S.LAST_NAME,
    S.DATE_OF_BIRTH,
    S.ADDRESS_JSON,
    CURRENT_TIMESTAMP(),
    S.BATCH_ID
);
```

## 86.54 MERGE Key Requirement

The source used by MERGE should be deterministic for the target business
key.

Unexpected duplicate source keys can create incorrect or
nondeterministic processing behavior.

Validate them before MERGE.

## 86.55 Deduplication Policy

If duplicate source records are valid, define deterministic precedence.

Example:

``` text
Latest source timestamp wins
```

or:

``` text
Highest source sequence wins
```

Never use arbitrary deduplication.

## 86.56 Transaction Boundary

Define what must succeed atomically.

Possible flow:

``` text
L1 load
   |
   v
Validation
   |
   v
L2 MERGE
```

Do not hold a transaction open while waiting on external systems.

## 86.57 Reconciliation

After transformation compare source, L1, and L2 using business-aware
rules.

## 86.58 Source Row Count

If provided by manifest:

``` text
Source rows = 10,000,000
```

Compare with loaded rows.

## 86.59 L1 Count

``` sql
SELECT COUNT(*)
FROM DAP.L1.EMPI_RAW
WHERE BATCH_ID = 'EMPI_20261007_010000';
```

## 86.60 L2 Batch Count

``` sql
SELECT COUNT(*)
FROM DAP.L2.EMPI
WHERE SOURCE_BATCH_ID = 'EMPI_20261007_010000';
```

Remember that MERGE updates can make L2 batch counts different from raw
input counts.

Reconciliation must understand inserts vs updates.

## 86.61 Reconciliation Metrics

Capture:

``` text
Source rows
L1 rows
Valid rows
Rejected rows
Inserted rows
Updated rows
Unchanged rows
L2 affected rows
```

## 86.62 Batch Completion

Update the control record only after validation and reconciliation
succeed.

Example:

``` sql
UPDATE DAP.CONTROL.BATCH_RUN
SET
    STATUS = 'COMPLETED',
    END_TIME = CURRENT_TIMESTAMP()
WHERE BATCH_ID = 'EMPI_20261007_010000';
```

## 86.63 Failed Batch

On failure set `STATUS = FAILED`.

Record failure stage, error, query ID, file, timestamp, and retry count.

## 86.64 Do Not Hide Failure

Avoid automation that converts `FAILED` into `SUCCESS` simply because a
retry eventually started.

Preserve the operational history.

## 86.65 Retry Classification

Classify failures:

``` text
Transient
Permanent
Data quality
Configuration
Authentication
Authorization
Capacity
Dependency
```

Retry only failures that are appropriate to retry.

## 86.66 Retry Policy

Example:

``` text
Maximum attempts: 3
Backoff: exponential
Jitter: enabled
```

Do not use unlimited immediate retries.

## 86.67 Replay Runbook

Before replay:

1.  Identify failed batch.
2.  Identify failed stage.
3.  Identify files already loaded.
4.  Identify L1 rows already present.
5.  Identify L2 changes already committed.
6.  Determine whether retry is safe.
7.  Correct root cause.
8.  Define replay scope.
9.  Obtain approval if destructive action is required.
10. Replay.
11. Reconcile.
12. Close batch.

## 86.68 Replay From File Discovery

If nothing was loaded, restart the batch after correcting the
source/dependency issue.

## 86.69 Replay After Partial L1 Load

Determine exactly which files succeeded.

Do not automatically reload the entire directory.

## 86.70 Replay After L2 Failure

If L1 is complete and valid, do not reload source unnecessarily.

Retry the L2 transformation when safe.

## 86.71 Replay Safety

Before replay answer:

``` text
Will this duplicate L1?
Will this duplicate L2?
Will this overwrite valid data?
Will downstream consumers see duplicates?
```

## 86.72 Quarantine

Invalid files should be logically or physically quarantined according to
the platform design.

Record batch, file, reason, error, owner, and resolution.

## 86.73 Bad Record Handling

Possible policies:

``` text
Reject entire batch
Reject file
Quarantine bad rows
Continue with threshold
```

The choice depends on data criticality.

## 86.74 Backfill

A backfill is not a normal retry.

Example:

``` text
Replay 90 days of historical EMPI data
```

Treat it as a controlled production change.

## 86.75 Backfill Planning

Document date range, data volume, files, warehouse, concurrency,
estimated runtime, estimated credits, consumer impact, and rollback.

## 86.76 Backfill Isolation

Use dedicated compute where practical so historical processing does not
interfere with current production ingestion.

## 86.77 File Size

Avoid creating extremely large numbers of tiny files.

Also avoid single massive files that limit parallelism.

Test representative file sizes for the workload.

## 86.78 Parallel Loading

Batch throughput depends partly on file count, file size, warehouse
capacity, compression, and parsing complexity.

Measure rather than assume.

## 86.79 Compression

Use appropriate compression supported by the source format and ingestion
design.

Evaluate storage, network transfer, load throughput, and CPU cost.

## 86.80 Warehouse Sizing Test

Example:

``` text
MEDIUM
10M rows
12 minutes

LARGE
10M rows
7 minutes
```

Then compare credits and SLA.

## 86.81 Scaling Decision

Choose the smallest configuration that consistently meets SLA,
throughput, recovery requirement, and operational headroom at acceptable
cost.

## 86.82 Query History

Investigate batch queries using:

``` sql
SELECT
    QUERY_ID,
    QUERY_TYPE,
    WAREHOUSE_NAME,
    TOTAL_ELAPSED_TIME,
    EXECUTION_TIME,
    QUEUED_OVERLOAD_TIME,
    QUEUED_PROVISIONING_TIME,
    START_TIME,
    END_TIME,
    EXECUTION_STATUS,
    ERROR_MESSAGE
FROM SNOWFLAKE.ACCOUNT_USAGE.QUERY_HISTORY
WHERE QUERY_TAG =
      'env=prod;service=empi;pipeline=batch_ingestion'
  AND START_TIME >= DATEADD('day', -1, CURRENT_TIMESTAMP())
ORDER BY START_TIME;
```

## 86.83 Queueing

If batch queries show high `QUEUED_OVERLOAD_TIME`, investigate
concurrency, warehouse sharing, overlapping jobs, retry storms, and
warehouse capacity.

## 86.84 Execution

If queue is low and execution is high, investigate data volume, Query
Profile, MERGE behavior, warehouse size, and transformation efficiency.

## 86.85 Batch Metrics

Monitor:

``` text
Batch duration
Source files
Loaded files
Rejected files
Source rows
Loaded rows
Rejected rows
L2 rows affected
Load throughput
Transformation duration
Queue time
Credits
Retry count
Freshness
```

## 86.86 Freshness Metric

Example:

``` text
Freshness =
Current time - latest successful source batch time
```

This often matters more to consumers than whether the scheduler itself
succeeded.

## 86.87 Pipeline Dashboard

Recommended:

``` text
Current batch
Last successful batch
Last failed batch
Batch duration
File count
Row count
Reject count
Freshness
Warehouse
Queue
Credits
Retry count
```

## 86.88 Alerting

Alert on:

``` text
Source late
Missing files
Validation failure
COPY failure
Transformation failure
Reconciliation failure
Batch SLA breach
Freshness breach
Repeated retries
Cost anomaly
```

## 86.89 Late Source Alert

Example:

``` text
Expected arrival: 01:00
Grace period: 10 minutes
No manifest by 01:10
=> Alert
```

## 86.90 SLA Alert

Example:

``` text
Batch STARTED
but not COMPLETED within 60 minutes
=> Alert
```

## 86.91 Freshness Alert

Even if the job reports success:

``` text
DAP.L2.EMPI freshness > SLA
=> Alert
```

This catches incomplete downstream processing.

## 86.92 Cost Monitoring

Track:

``` text
Credits per batch
Credits per million rows
Credits per GB
Monthly ingestion credits
Backfill credits
```

## 86.93 Cost Regression

Example:

``` text
Normal:
0.8 credits / batch

Current:
2.5 credits / batch
```

Investigate even if SLA is still met.

## 86.94 Security Model

Conceptually:

``` text
EMPI_BATCH_ROLE
      |
      +--> USAGE warehouse
      +--> USAGE database
      +--> USAGE schemas
      +--> READ stage
      +--> INSERT L1
      +--> SELECT L1
      +--> DML L2
      +--> DML CONTROL
```

Grant only what is required.

## 86.95 Avoid ACCOUNTADMIN

The batch service should not run as `ACCOUNTADMIN` or another broad
administrative role simply for convenience.

## 86.96 Secret Management

Store private keys, OAuth credentials, or other secrets in an approved
secret-management system.

Do not commit them into Git, SQL files, Docker images, ConfigMaps, or
logs.

## 86.97 Logging

Log batch ID, pipeline, start/end, file, rows, status, query ID, error
category, and retry.

Do not log secrets or sensitive source records unnecessarily.

## 86.98 Auditability

Given a production row, operations should be able to determine:

``` text
Which batch loaded it?
Which source file contained it?
When was it loaded?
Which pipeline processed it?
```

## 86.99 Deployment

Manage production objects through controlled deployment.

Example:

``` text
Git
  |
  v
Pull Request
  |
  v
Review
  |
  v
CI Validation
  |
  v
Approved Deployment
  |
  v
Snowflake
```

## 86.100 Change Management

For ingestion changes document schema change, file-format change, stage
change, warehouse change, MERGE logic change, schedule change, and retry
change.

## 86.101 Rollback

A deployment plan should define rollback for DDL, transformation logic,
role/grant changes, file-format changes, and pipeline configuration.

Data rollback may require a separate recovery procedure.

## 86.102 Schema Change Scenario

Suppose the source changes `ADDRESS` from `ARRAY` to
`VARCHAR containing JSON`.

Do not silently push the mixed representation into L2.

Detect and normalize deliberately.

## 86.103 Type Inspection

Example:

``` sql
SELECT
    TYPEOF(ADDRESS_JSON),
    COUNT(*)
FROM DAP.L1.EMPI_RAW
WHERE BATCH_ID = 'EMPI_20261007_010000'
GROUP BY TYPEOF(ADDRESS_JSON);
```

## 86.104 Parsing Validation

Where a raw string may contain JSON:

``` sql
SELECT
    COUNT(*) AS INVALID_JSON
FROM DAP.L1.EMPI_RAW
WHERE BATCH_ID = 'EMPI_20261007_010000'
  AND <raw_address_column> IS NOT NULL
  AND TRY_PARSE_JSON(<raw_address_column>) IS NULL;
```

Adapt the column to the actual raw schema.

## 86.105 Incident Scenario --- Missing Files

Symptom: batch has not completed.

Investigation:

``` text
Expected files = 50
Discovered = 42
```

Snowflake is healthy.

Root cause: upstream delivery incomplete.

Correct action:

``` text
Do not resize warehouse.
Escalate upstream delivery.
```

## 86.106 Incident Scenario --- Slow Load

Observed:

``` text
Normal COPY = 8 min
Current COPY = 35 min
```

Check file count, file size, data volume, queue, execution, warehouse,
and concurrent workload.

Do not assume warehouse capacity first.

## 86.107 Incident Scenario --- Queueing

Observed:

``` text
COPY total = 30 min
Execution = 6 min
Queue = 23 min
```

Diagnosis: concurrency / warehouse contention, not primarily slow file
parsing.

## 86.108 Incident Scenario --- Data Quality

Observed: COPY validation fails.

Error: invalid DATE value.

Correct action:

``` text
Quarantine / reject according to policy
Notify source owner
Preserve evidence
```

Do not convert invalid data silently merely to make the batch green.

## 86.109 Incident Scenario --- L2 Failure

Observed:

``` text
L1 load successful
L2 MERGE failed
```

Do not reload L1 automatically.

Investigate the MERGE and retry the transformation if safe.

## 86.110 Incident Scenario --- Retry Storm

Observed:

``` text
Batch timeout
Retry
Timeout
Retry
Timeout
Retry
```

Impact:

``` text
More concurrent queries
More queueing
Higher credits
Longer recovery
```

Use bounded retries with backoff and jitter.

## 86.111 Incident Scenario --- Duplicate Replay

An operator uses `FORCE = TRUE` against the full batch path without
checking prior load state.

Potential impact:

``` text
Duplicate L1 records
Duplicate downstream processing
Incorrect reconciliation
```

Replay must be controlled.

## 86.112 First 10-Minute Batch Troubleshooting

1.  Identify batch ID.
2.  Check batch status.
3.  Verify source arrival.
4.  Verify expected file count.
5.  LIST stage.
6.  Check COPY/load history.
7.  Check query history.
8.  Separate queue from execution.
9.  Check validation errors.
10. Check L1 count.
11. Check L2 status.
12. Check recent changes.
13. Check retries.
14. Check freshness.
15. Preserve query IDs and evidence.

## 86.113 Missing Data Runbook

``` text
Consumer missing data
        |
        v
Check L2 freshness
        |
        v
Check L2 transformation
        |
        v
Check L1 batch
        |
        v
Check COPY
        |
        v
Check stage
        |
        v
Check source
```

Always move backward through the pipeline.

## 86.114 Batch Failure Runbook

1.  Identify batch.
2.  Freeze uncontrolled retries.
3.  Determine failure stage.
4.  Capture error/query ID.
5.  Determine committed state.
6.  Determine source completeness.
7.  Determine L1 state.
8.  Determine L2 state.
9.  Classify failure.
10. Correct root cause.
11. Select retry/replay scope.
12. Execute controlled recovery.
13. Reconcile.
14. Validate consumer freshness.
15. Close incident.

## 86.115 Performance Runbook

1.  Capture baseline.
2.  Capture current duration.
3.  Split COPY vs transformation.
4.  Split queue vs execution.
5.  Compare data volume.
6.  Compare file count.
7.  Compare file sizes.
8.  Review warehouse.
9.  Review overlapping workload.
10. Review Query Profile.
11. Review recent changes.
12. Test remediation.
13. Compare credits.
14. Validate SLA.

## 86.116 Data Quality Runbook

1.  Stop promotion to L2 if required.
2.  Identify batch.
3.  Identify invalid files/rows.
4.  Determine source vs pipeline defect.
5.  Preserve source.
6.  Quarantine according to policy.
7.  Notify owner.
8.  Correct source or transformation.
9.  Replay controlled scope.
10. Reconcile.
11. Validate downstream.
12. Document root cause.

## 86.117 Replay Runbook

1.  Identify batch ID.
2.  Identify original files.
3.  Check load history.
4.  Check L1 rows.
5.  Check L2 effects.
6.  Determine safe restart point.
7.  Remove/correct invalid state only when approved.
8.  Replay.
9.  Validate counts.
10. Validate duplicates.
11. Validate L2.
12. Validate consumer freshness.
13. Record replay event.

## 86.118 Backfill Runbook

1.  Define date range.
2.  Estimate volume.
3.  Identify files.
4.  Define warehouse.
5.  Define concurrency.
6.  Estimate credits.
7.  Identify consumer impact.
8.  Define query tag.
9.  Define batch IDs.
10. Execute limited sample.
11. Validate.
12. Scale controlled processing.
13. Monitor.
14. Reconcile.
15. Close backfill.

## 86.119 Production Acceptance Test

A production acceptance test should demonstrate:

``` text
Normal load
Malformed input
Missing file
Duplicate file
Partial failure
L2 failure
Retry
Replay
Backfill
Monitoring
Alerting
Recovery
```

## 86.120 Acceptance Test --- Normal Batch

Verify:

``` text
Files discovered
Validation passes
COPY succeeds
L1 count correct
L2 transformation succeeds
Reconciliation succeeds
Status COMPLETED
Freshness within SLA
```

## 86.121 Acceptance Test --- Bad File

Inject a controlled malformed file in nonproduction.

Expected:

``` text
Validation detects issue
Batch follows policy
Alert fires
Evidence captured
No silent corruption
```

## 86.122 Acceptance Test --- Duplicate File

Attempt to reprocess a previously loaded file.

Verify duplicate behavior matches the documented design.

## 86.123 Acceptance Test --- L2 Failure

Force a controlled transformation failure.

Verify:

``` text
L1 remains recoverable
Batch marked failed
Retry is safe
No unnecessary source reload
```

## 86.124 Acceptance Test --- Monitoring

Verify alerts actually fire.

Do not accept `Alert configured` as proof.

Require `Alert tested`.

## 86.125 Acceptance Test --- Recovery

Recover a failed batch using the documented runbook.

Measure detection time, diagnosis time, recovery time, and total RTO.

## 86.126 SRE/DBRE Dashboard

Recommended panels:

``` text
Last batch
Current status
Last success
Last failure
Freshness
Duration
Files expected
Files loaded
Rows loaded
Rows rejected
L2 affected rows
COPY duration
Transformation duration
Queue time
Warehouse
Credits
Retries
```

## 86.127 Capacity Planning

Track growth in rows/day, GB/day, files/day, batch duration, and
credits/batch.

Forecast 3 months, 6 months, and 12 months.

## 86.128 Capacity Trigger

Example:

``` text
If P95 batch duration exceeds
70% of the SLA window,
initiate capacity review.
```

This creates recovery headroom before an SLA breach.

## 86.129 Recovery Headroom

If SLA allows 60 minutes and normal batch duration is 58 minutes, the
pipeline has almost no recovery margin.

Production design should consider failure and retry time.

## 86.130 Operational Ownership

Document pipeline owner, Snowflake owner, source owner, consumer owner,
cloud storage owner, IAM owner, on-call, and escalation.

## 86.131 Handoff Checklist

Before handing the pipeline to operations:

-   [ ] Architecture documented
-   [ ] Source contract documented
-   [ ] Stage documented
-   [ ] File format documented
-   [ ] Warehouse documented
-   [ ] Role documented
-   [ ] Batch control implemented
-   [ ] File control implemented
-   [ ] Query tagging implemented
-   [ ] Validation implemented
-   [ ] Reconciliation implemented
-   [ ] Retry policy documented
-   [ ] Replay tested
-   [ ] Backfill tested
-   [ ] Monitoring implemented
-   [ ] Alerts tested
-   [ ] Dashboard available
-   [ ] Recovery runbook available
-   [ ] Ownership documented
-   [ ] Escalation documented

## 86.132 Production Readiness Checklist

### Architecture

-   [ ] Source identified
-   [ ] Storage identified
-   [ ] Stage configured
-   [ ] File format configured
-   [ ] L1 defined
-   [ ] L2 defined
-   [ ] Control schema defined

### Security

-   [ ] Service identity configured
-   [ ] Least-privilege role configured
-   [ ] Storage integration configured
-   [ ] Secrets managed securely
-   [ ] No broad admin role required

### Ingestion

-   [ ] File discovery implemented
-   [ ] Completeness gate implemented
-   [ ] Validation implemented
-   [ ] COPY configured
-   [ ] Load history monitored
-   [ ] Duplicate behavior documented

### Data Quality

-   [ ] Required fields validated
-   [ ] Duplicate keys validated
-   [ ] Data types validated
-   [ ] Schema drift detected
-   [ ] JSON validated
-   [ ] Source contract documented

### Transformation

-   [ ] L1 to L2 logic defined
-   [ ] MERGE key validated
-   [ ] Deduplication deterministic
-   [ ] Reconciliation implemented

### Reliability

-   [ ] Retry bounded
-   [ ] Backoff enabled
-   [ ] Jitter enabled
-   [ ] Replay documented
-   [ ] Partial failure handled
-   [ ] Backfill documented

### Observability

-   [ ] Batch status monitored
-   [ ] File count monitored
-   [ ] Row count monitored
-   [ ] Freshness monitored
-   [ ] Queue monitored
-   [ ] Execution monitored
-   [ ] Credits monitored
-   [ ] Alerts tested

### Operations

-   [ ] Runbooks complete
-   [ ] Ownership assigned
-   [ ] Escalation defined
-   [ ] Acceptance test passed
-   [ ] Recovery tested
-   [ ] Capacity baseline established

## 86.133 Project Decision Tree

``` text
BATCH START
    |
    v
SOURCE COMPLETE?
   / \
 No   Yes
 |     |
 v     v
STOP  VALIDATE FILES
ALERT      |
           v
      VALIDATION PASS?
         /      \
       No        Yes
       |          |
       v          v
   QUARANTINE    COPY L1
   / FAIL          |
                   v
              L1 VALID?
                /   \
              No     Yes
              |       |
              v       v
            FAIL    TRANSFORM L2
                       |
                       v
                 L2 SUCCESS?
                    /    \
                  No      Yes
                  |        |
                  v        v
                RETRY   RECONCILE
                          |
                          v
                    RECONCILE PASS?
                       /      \
                     No        Yes
                     |          |
                     v          v
                   FAIL     COMPLETED
```

## 86.134 Key Principles

1.  Production ingestion is more than COPY INTO.
2.  Define the SLA before building the pipeline.
3.  Define data-quality requirements.
4.  Define recovery requirements.
5.  Use least privilege.
6.  Prefer storage integrations over embedded cloud credentials.
7.  Use dedicated workload identities.
8.  Isolate critical batch compute where appropriate.
9.  Tag pipeline queries.
10. Use predictable storage paths.
11. Track a batch ID.
12. Track source files.
13. Store ingestion metadata.
14. Validate source completeness.
15. Avoid reading files still being written.
16. Use manifests or equivalent source contracts where useful.
17. Validate before production load.
18. Define explicit error thresholds.
19. Preserve source fidelity in L1.
20. Validate required business keys.
21. Detect duplicate business keys.
22. Detect schema drift.
23. Validate semi-structured data.
24. Make L1-to-L2 transformation deterministic.
25. Validate MERGE source uniqueness.
26. Define deterministic deduplication.
27. Reconcile source, L1, and L2.
28. Preserve failure history.
29. Classify failures before retry.
30. Use bounded retries.
31. Use backoff and jitter.
32. Design replay before production.
33. Know the safe restart point.
34. Do not use FORCE casually.
35. Treat backfills as production changes.
36. Isolate backfill capacity where practical.
37. Measure file-size behavior.
38. Measure load throughput.
39. Right-size using performance and credits.
40. Separate queueing from execution.
41. Monitor freshness.
42. Monitor credits per batch.
43. Alert on source lateness.
44. Alert on SLA breach.
45. Test bad-data behavior.
46. Test duplicate behavior.
47. Test partial failure.
48. Test replay.
49. Test monitoring.
50. Test recovery.
51. Maintain operational headroom.
52. Document ownership.
53. Document escalation.
54. Make the pipeline auditable.
55. A production pipeline is not complete until operations can safely
    recover it.

## 86.135 Chapter Completion Checklist

After completing this project, you should be able to:

-   Design a production Snowflake batch-ingestion architecture.
-   Define ingestion SLAs.
-   Design source-file contracts.
-   Configure file formats and external stages.
-   Use storage integrations.
-   Create a dedicated batch warehouse.
-   Implement workload query tagging.
-   Design L1 and L2 tables.
-   Add source-file and batch metadata.
-   Create batch control tables.
-   Implement file discovery and completeness gates.
-   Validate files before loading.
-   Use COPY INTO safely.
-   Interpret load results and history.
-   Design duplicate-file protection.
-   Implement row-level idempotency.
-   Validate required keys and duplicates.
-   Detect semi-structured type drift.
-   Build deterministic MERGE processing.
-   Reconcile source, L1, and L2.
-   Implement batch state management.
-   Classify failures.
-   Implement bounded retries.
-   Design safe replay.
-   Design quarantine handling.
-   Execute controlled backfills.
-   Measure load throughput.
-   Right-size warehouse capacity.
-   Troubleshoot queueing vs execution.
-   Build batch dashboards.
-   Monitor freshness.
-   Monitor cost per batch.
-   Design production alerts.
-   Apply least-privilege RBAC.
-   Protect secrets.
-   Maintain ingestion auditability.
-   Manage pipeline changes and rollback.
-   Troubleshoot missing files, slow loads, queueing, bad data, L2
    failures, retry storms, and duplicate replay.
-   Execute batch-failure, performance, data-quality, replay, and
    backfill runbooks.
-   Perform production acceptance testing.
-   Establish capacity and recovery headroom.
-   Hand the pipeline safely to production operations.

**Chapter 86 --- Snowflake Batch Ingestion Production Project:
Complete**
