# Chapter 90 — Snowflake Production Pipeline Reliability & Recovery Project

## 1. Project Goal

A production data pipeline is not complete simply because it works when every dependency is healthy.

Production pipelines must also behave predictably when:

- source data arrives late,
- ingestion fails halfway through,
- a Snowflake task fails,
- a warehouse is unavailable or suspended,
- a CDC consumer stops,
- a stream approaches staleness,
- duplicate events are replayed,
- bad data reaches staging,
- a deployment introduces a defect,
- data is accidentally updated or deleted,
- downstream processing falls behind,
- or an operator must replay historical data.

This project builds a reliability and recovery framework around the Snowflake pipelines created in the previous chapters.

The objective is to make pipeline recovery:

- observable,
- repeatable,
- idempotent,
- auditable,
- bounded by RPO/RTO objectives,
- and safe to execute during an incident.

---

## 2. What You Will Build

By the end of this chapter, you will have a production-oriented framework containing:

1. pipeline run tracking,
2. checkpoint and watermark management,
3. retry classification,
4. idempotent `MERGE` processing,
5. duplicate-event protection,
6. partial-load recovery,
7. CDC stream recovery procedures,
8. replay and backfill controls,
9. reconciliation checks,
10. Time Travel recovery examples,
11. accidental object-drop recovery,
12. failure-injection tests,
13. RPO/RTO measurements,
14. operational recovery runbooks,
15. production acceptance criteria.

---

## 3. Architecture

The logical recovery flow is:

```text
Source
  |
  v
Landing / Raw
  |
  v
Staging
  |
  +----------------------+
  |                      |
  v                      v
CDC Stream          DQ / Validation
  |                      |
  +----------+-----------+
             |
             v
      Incremental MERGE
             |
             v
          Target
             |
             v
     Reconciliation
             |
             v
      Commit Watermark
```

Operational metadata surrounds the entire pipeline:

```text
PIPELINE_RUN_CONTROL
PIPELINE_CHECKPOINT
PIPELINE_RETRY_LOG
PIPELINE_REPLAY_REQUEST
PIPELINE_RECONCILIATION
PIPELINE_RECOVERY_AUDIT
```

A critical principle is:

> Do not advance the durable checkpoint until the business transaction has been validated successfully.

---

## 4. Recovery Principles

### 4.1 Idempotency

Running the same recovery operation more than once must not corrupt the target.

For example:

```sql
MERGE INTO PROD.CUSTOMER T
USING STAGE.CUSTOMER_DELTA S
ON T.CUSTOMER_ID = S.CUSTOMER_ID

WHEN MATCHED THEN
UPDATE SET
    T.CUSTOMER_NAME = S.CUSTOMER_NAME,
    T.EMAIL = S.EMAIL,
    T.UPDATED_AT = S.UPDATED_AT

WHEN NOT MATCHED THEN
INSERT (
    CUSTOMER_ID,
    CUSTOMER_NAME,
    EMAIL,
    UPDATED_AT
)
VALUES (
    S.CUSTOMER_ID,
    S.CUSTOMER_NAME,
    S.EMAIL,
    S.UPDATED_AT
);
```

Replaying the same input should converge on the same target state.

### 4.2 Checkpoint only after success

Never record a batch as complete before:

- target processing succeeds,
- validation succeeds,
- reconciliation succeeds.

### 4.3 Preserve replayable source data

Recovery becomes much harder if raw source records disappear immediately after processing.

Where appropriate, preserve immutable landing data long enough to support the required replay window.

### 4.4 Separate transient and permanent failures

Retrying every failure blindly can make incidents worse.

Transient failures may include:

- temporary warehouse availability problems,
- dependency delays,
- network or integration errors,
- lock/contention conditions.

Permanent failures may include:

- invalid SQL,
- incompatible schema changes,
- broken transformations,
- invalid business data,
- missing privileges.

Permanent failures should normally require intervention rather than infinite retry.

---

## 5. Create the Project Environment

```sql
CREATE DATABASE IF NOT EXISTS PIPELINE_RELIABILITY;

CREATE SCHEMA IF NOT EXISTS PIPELINE_RELIABILITY.CONTROL;
CREATE SCHEMA IF NOT EXISTS PIPELINE_RELIABILITY.RAW;
CREATE SCHEMA IF NOT EXISTS PIPELINE_RELIABILITY.STAGE;
CREATE SCHEMA IF NOT EXISTS PIPELINE_RELIABILITY.PROD;
CREATE SCHEMA IF NOT EXISTS PIPELINE_RELIABILITY.RECOVERY;
```

Create a warehouse for the lab if required:

```sql
CREATE WAREHOUSE IF NOT EXISTS RELIABILITY_WH
WAREHOUSE_SIZE = 'XSMALL'
AUTO_SUSPEND = 60
AUTO_RESUME = TRUE
INITIALLY_SUSPENDED = TRUE;
```

```sql
USE WAREHOUSE RELIABILITY_WH;
USE DATABASE PIPELINE_RELIABILITY;
```

---

## 6. Pipeline Run Control Table

Create a durable run-control table.

```sql
CREATE OR REPLACE TABLE CONTROL.PIPELINE_RUN_CONTROL (
    RUN_ID STRING,
    PIPELINE_NAME STRING,
    BATCH_ID STRING,
    STARTED_AT TIMESTAMP_LTZ,
    COMPLETED_AT TIMESTAMP_LTZ,
    STATUS STRING,
    ATTEMPT_NUMBER NUMBER,
    SOURCE_ROWS NUMBER,
    TARGET_ROWS NUMBER,
    ERROR_CODE STRING,
    ERROR_MESSAGE STRING,
    RECOVERY_REQUIRED BOOLEAN,
    CREATED_AT TIMESTAMP_LTZ DEFAULT CURRENT_TIMESTAMP(),
    UPDATED_AT TIMESTAMP_LTZ DEFAULT CURRENT_TIMESTAMP()
);
```

Recommended statuses:

```text
STARTED
RUNNING
VALIDATING
SUCCEEDED
FAILED
RETRY_PENDING
RECOVERY_REQUIRED
REPLAYING
RECONCILING
RECOVERED
```

Example run registration:

```sql
INSERT INTO CONTROL.PIPELINE_RUN_CONTROL (
    RUN_ID,
    PIPELINE_NAME,
    BATCH_ID,
    STARTED_AT,
    STATUS,
    ATTEMPT_NUMBER,
    RECOVERY_REQUIRED
)
SELECT
    UUID_STRING(),
    'CUSTOMER_CDC',
    'BATCH_20261007_001',
    CURRENT_TIMESTAMP(),
    'STARTED',
    1,
    FALSE;
```

---

## 7. Durable Checkpoint Table

```sql
CREATE OR REPLACE TABLE CONTROL.PIPELINE_CHECKPOINT (
    PIPELINE_NAME STRING,
    CHECKPOINT_TYPE STRING,
    CHECKPOINT_VALUE STRING,
    LAST_SUCCESSFUL_RUN_ID STRING,
    LAST_SUCCESSFUL_BATCH_ID STRING,
    LAST_SUCCESSFUL_AT TIMESTAMP_LTZ,
    UPDATED_AT TIMESTAMP_LTZ DEFAULT CURRENT_TIMESTAMP()
);
```

Examples of checkpoint types:

```text
EVENT_TIMESTAMP
BATCH_ID
SOURCE_SEQUENCE
FILE_NAME
FILE_TIMESTAMP
CDC_OFFSET
```

Example:

```sql
INSERT INTO CONTROL.PIPELINE_CHECKPOINT (
    PIPELINE_NAME,
    CHECKPOINT_TYPE,
    CHECKPOINT_VALUE,
    LAST_SUCCESSFUL_RUN_ID,
    LAST_SUCCESSFUL_BATCH_ID,
    LAST_SUCCESSFUL_AT
)
VALUES (
    'CUSTOMER_CDC',
    'EVENT_TIMESTAMP',
    '2026-10-07 12:00:00',
    'RUN_001',
    'BATCH_001',
    CURRENT_TIMESTAMP()
);
```

---

## 8. Checkpoint Safety Rule

Consider the following incorrect sequence:

```text
1. Read source batch
2. Update checkpoint
3. Merge target
4. Pipeline fails
```

The checkpoint now claims data was processed even though the target update failed.

The safer sequence is:

```text
1. Read source batch
2. Transform
3. Merge target
4. Validate target
5. Reconcile
6. Commit successful run
7. Advance checkpoint
```

This makes the checkpoint represent the last known-good processing boundary.

---

## 9. Build the Source and Target Tables

```sql
CREATE OR REPLACE TABLE RAW.CUSTOMER_EVENTS (
    EVENT_ID STRING,
    CUSTOMER_ID NUMBER,
    OPERATION STRING,
    CUSTOMER_NAME STRING,
    EMAIL STRING,
    EVENT_TS TIMESTAMP_LTZ,
    INGESTED_AT TIMESTAMP_LTZ DEFAULT CURRENT_TIMESTAMP()
);
```

```sql
CREATE OR REPLACE TABLE PROD.CUSTOMER (
    CUSTOMER_ID NUMBER,
    CUSTOMER_NAME STRING,
    EMAIL STRING,
    SOURCE_EVENT_TS TIMESTAMP_LTZ,
    UPDATED_AT TIMESTAMP_LTZ DEFAULT CURRENT_TIMESTAMP()
);
```

Load sample events:

```sql
INSERT INTO RAW.CUSTOMER_EVENTS
VALUES
('EVT-001', 101, 'INSERT', 'Alice', 'alice@example.com',
 '2026-10-07 12:00:00', CURRENT_TIMESTAMP()),
('EVT-002', 102, 'INSERT', 'Bob', 'bob@example.com',
 '2026-10-07 12:01:00', CURRENT_TIMESTAMP()),
('EVT-003', 101, 'UPDATE', 'Alice Smith', 'alice.smith@example.com',
 '2026-10-07 12:02:00', CURRENT_TIMESTAMP());
```

---

## 10. Duplicate Event Protection

Create an event-processing ledger.

```sql
CREATE OR REPLACE TABLE CONTROL.PROCESSED_EVENT (
    PIPELINE_NAME STRING,
    EVENT_ID STRING,
    PROCESSED_AT TIMESTAMP_LTZ DEFAULT CURRENT_TIMESTAMP(),
    RUN_ID STRING
);
```

Before processing an event:

```sql
SELECT R.*
FROM RAW.CUSTOMER_EVENTS R
LEFT JOIN CONTROL.PROCESSED_EVENT P
    ON P.PIPELINE_NAME = 'CUSTOMER_CDC'
   AND P.EVENT_ID = R.EVENT_ID
WHERE P.EVENT_ID IS NULL;
```

After successful processing:

```sql
INSERT INTO CONTROL.PROCESSED_EVENT (
    PIPELINE_NAME,
    EVENT_ID,
    RUN_ID
)
SELECT
    'CUSTOMER_CDC',
    EVENT_ID,
    'RUN_002'
FROM STAGE.CUSTOMER_DELTA;
```

This gives the pipeline an additional defense against duplicate delivery.

---

## 11. Handle Out-of-Order Events

CDC systems may deliver events in a different order than the logical business sequence.

The target should avoid overwriting a newer state with an older event.

Example:

```sql
MERGE INTO PROD.CUSTOMER T
USING STAGE.CUSTOMER_DELTA S
ON T.CUSTOMER_ID = S.CUSTOMER_ID

WHEN MATCHED
 AND S.EVENT_TS >= T.SOURCE_EVENT_TS
 AND S.OPERATION <> 'DELETE'
THEN UPDATE SET
    T.CUSTOMER_NAME = S.CUSTOMER_NAME,
    T.EMAIL = S.EMAIL,
    T.SOURCE_EVENT_TS = S.EVENT_TS,
    T.UPDATED_AT = CURRENT_TIMESTAMP()

WHEN NOT MATCHED
 AND S.OPERATION <> 'DELETE'
THEN INSERT (
    CUSTOMER_ID,
    CUSTOMER_NAME,
    EMAIL,
    SOURCE_EVENT_TS
)
VALUES (
    S.CUSTOMER_ID,
    S.CUSTOMER_NAME,
    S.EMAIL,
    S.EVENT_TS
);
```

The correct ordering key depends on the source system.

Prefer a source-generated sequence/offset when one exists.

---

## 12. Delete Handling

Physical deletes can make replay and auditing more difficult.

One approach is a soft-delete model:

```sql
ALTER TABLE PROD.CUSTOMER
ADD COLUMN IF NOT EXISTS IS_DELETED BOOLEAN DEFAULT FALSE;
```

Then:

```sql
WHEN MATCHED
 AND S.OPERATION = 'DELETE'
 AND S.EVENT_TS >= T.SOURCE_EVENT_TS
THEN UPDATE SET
    T.IS_DELETED = TRUE,
    T.SOURCE_EVENT_TS = S.EVENT_TS,
    T.UPDATED_AT = CURRENT_TIMESTAMP()
```

If physical deletion is required, ensure the raw event history remains available for recovery.

---

## 13. Retry Log

```sql
CREATE OR REPLACE TABLE CONTROL.PIPELINE_RETRY_LOG (
    RETRY_ID STRING,
    RUN_ID STRING,
    PIPELINE_NAME STRING,
    ATTEMPT_NUMBER NUMBER,
    FAILURE_CLASS STRING,
    RETRYABLE BOOLEAN,
    ERROR_MESSAGE STRING,
    RETRY_SCHEDULED_AT TIMESTAMP_LTZ,
    RETRY_STARTED_AT TIMESTAMP_LTZ,
    RETRY_COMPLETED_AT TIMESTAMP_LTZ,
    RETRY_STATUS STRING,
    CREATED_AT TIMESTAMP_LTZ DEFAULT CURRENT_TIMESTAMP()
);
```

Possible failure classes:

```text
TRANSIENT_DEPENDENCY
WAREHOUSE_RESOURCE
DATA_QUALITY
SCHEMA_CHANGE
SQL_ERROR
PERMISSION_ERROR
SOURCE_DELAY
CDC_GAP
UNKNOWN
```

---

## 14. Retry Policy

An example operational policy:

| Failure | Retry? | Action |
|---|---:|---|
| Temporary dependency failure | Yes | Retry with bounded backoff |
| Warehouse resource contention | Yes | Retry or resize after investigation |
| Source data not arrived | Yes | Wait/retry |
| Invalid SQL | No | Fix deployment |
| Missing privilege | No | Correct RBAC |
| DQ failure | Usually no | Quarantine/investigate |
| Schema incompatibility | No | Apply schema remediation |
| Duplicate event | No failure | Skip idempotently |
| Stream staleness | Recovery | Replay from retained source |

Retries should always have a maximum attempt count.

Never create an infinite retry loop.

---

## 15. Bounded Backoff

A simple conceptual schedule might be:

```text
Attempt 1 -> immediate
Attempt 2 -> +1 minute
Attempt 3 -> +5 minutes
Attempt 4 -> +15 minutes
Attempt 5 -> operator intervention
```

The actual schedule should match the workload's latency objectives and failure characteristics.

Record every attempt so that retries are observable.

---

## 16. Partial-Load Failure Scenario

Assume a pipeline performs:

```text
RAW -> STAGE -> TARGET
```

and fails after staging.

Do not blindly reload the entire source.

Determine:

1. which batch was being processed,
2. whether target changes committed,
3. whether the checkpoint advanced,
4. whether the source data remains available,
5. whether replay is idempotent.

Example query:

```sql
SELECT *
FROM CONTROL.PIPELINE_RUN_CONTROL
WHERE PIPELINE_NAME = 'CUSTOMER_CDC'
ORDER BY STARTED_AT DESC;
```

Then inspect the checkpoint:

```sql
SELECT *
FROM CONTROL.PIPELINE_CHECKPOINT
WHERE PIPELINE_NAME = 'CUSTOMER_CDC';
```

Recovery should begin from the last successful durable boundary.

---

## 17. Transaction Boundaries

For operations that must succeed together, use explicit transaction boundaries where appropriate.

Example:

```sql
BEGIN;

MERGE INTO PROD.CUSTOMER T
USING STAGE.CUSTOMER_DELTA S
ON T.CUSTOMER_ID = S.CUSTOMER_ID
WHEN MATCHED THEN
    UPDATE SET
        T.CUSTOMER_NAME = S.CUSTOMER_NAME,
        T.EMAIL = S.EMAIL,
        T.SOURCE_EVENT_TS = S.EVENT_TS,
        T.UPDATED_AT = CURRENT_TIMESTAMP()
WHEN NOT MATCHED THEN
    INSERT (
        CUSTOMER_ID,
        CUSTOMER_NAME,
        EMAIL,
        SOURCE_EVENT_TS
    )
    VALUES (
        S.CUSTOMER_ID,
        S.CUSTOMER_NAME,
        S.EMAIL,
        S.EVENT_TS
    );

INSERT INTO CONTROL.PROCESSED_EVENT (
    PIPELINE_NAME,
    EVENT_ID,
    RUN_ID
)
SELECT
    'CUSTOMER_CDC',
    EVENT_ID,
    'RUN_003'
FROM STAGE.CUSTOMER_DELTA;

COMMIT;
```

Use transaction design carefully.

Do not make transactions unnecessarily large.

---

## 18. Stream-Based CDC Recovery

Create a stream:

```sql
CREATE OR REPLACE STREAM RAW.CUSTOMER_EVENTS_STREAM
ON TABLE RAW.CUSTOMER_EVENTS;
```

Inspect it:

```sql
SELECT *
FROM RAW.CUSTOMER_EVENTS_STREAM;
```

Check whether data exists:

```sql
SELECT SYSTEM$STREAM_HAS_DATA(
    'PIPELINE_RELIABILITY.RAW.CUSTOMER_EVENTS_STREAM'
);
```

Streams are change-tracking objects, not permanent event archives.

The recovery architecture should therefore not depend on a stream being the only copy of replayable CDC data.

---

## 19. Stream Staleness Risk

A stream can become unusable if it is not consumed within the relevant retention window.

Operational monitoring should therefore track stream health.

Example:

```sql
SHOW STREAMS IN DATABASE PIPELINE_RELIABILITY;
```

Review fields such as:

```text
stale
stale_after
```

Operational rule:

> Alert before the stream reaches its staleness boundary.

Chapter 89's observability framework should be used to surface this condition before recovery is required.

---

## 20. Recovery When the Stream Is Still Valid

If processing stopped but the stream remains valid:

1. stop competing consumers if necessary,
2. identify the failed run,
3. confirm the target checkpoint,
4. inspect pending stream changes,
5. fix the root cause,
6. rerun the idempotent consumer,
7. reconcile source and target,
8. mark the recovery successful.

Example:

```sql
SELECT COUNT(*)
FROM RAW.CUSTOMER_EVENTS_STREAM;
```

Do not consume pending changes merely to inspect them through a DML operation.

---

## 21. Recovery When a Stream Is Stale

If a stream can no longer provide the required change set, recovery must come from another retained source.

Possible sources include:

```text
immutable raw table
landing files
source-system CDC archive
event bus retention
historical extraction
backup/recovery dataset
```

Recovery pattern:

```text
Determine last successful checkpoint
        |
        v
Identify missing time/sequence range
        |
        v
Re-extract or read retained source
        |
        v
Load replay staging table
        |
        v
Run idempotent MERGE
        |
        v
Reconcile
        |
        v
Reset normal CDC path
```

This is why raw-data retention is part of reliability design.

---

## 22. Replay Request Table

```sql
CREATE OR REPLACE TABLE RECOVERY.PIPELINE_REPLAY_REQUEST (
    REPLAY_ID STRING,
    PIPELINE_NAME STRING,
    REQUESTED_BY STRING,
    REQUESTED_AT TIMESTAMP_LTZ,
    RANGE_START TIMESTAMP_LTZ,
    RANGE_END TIMESTAMP_LTZ,
    REASON STRING,
    STATUS STRING,
    APPROVED_BY STRING,
    STARTED_AT TIMESTAMP_LTZ,
    COMPLETED_AT TIMESTAMP_LTZ,
    ROWS_REPLAYED NUMBER,
    ERROR_MESSAGE STRING
);
```

Example request:

```sql
INSERT INTO RECOVERY.PIPELINE_REPLAY_REQUEST (
    REPLAY_ID,
    PIPELINE_NAME,
    REQUESTED_BY,
    REQUESTED_AT,
    RANGE_START,
    RANGE_END,
    REASON,
    STATUS
)
VALUES (
    UUID_STRING(),
    'CUSTOMER_CDC',
    CURRENT_USER(),
    CURRENT_TIMESTAMP(),
    '2026-10-07 12:00:00',
    '2026-10-07 13:00:00',
    'Recover missed CDC window',
    'REQUESTED'
);
```

Production replay should be controlled and auditable.

---

## 23. Build a Replay Dataset

```sql
CREATE OR REPLACE TEMP TABLE STAGE.CUSTOMER_REPLAY AS
SELECT *
FROM RAW.CUSTOMER_EVENTS
WHERE EVENT_TS >= '2026-10-07 12:00:00'
  AND EVENT_TS <  '2026-10-07 13:00:00';
```

Validate:

```sql
SELECT
    COUNT(*) AS ROW_COUNT,
    MIN(EVENT_TS) AS MIN_EVENT_TS,
    MAX(EVENT_TS) AS MAX_EVENT_TS
FROM STAGE.CUSTOMER_REPLAY;
```

Check duplicate event IDs:

```sql
SELECT
    EVENT_ID,
    COUNT(*)
FROM STAGE.CUSTOMER_REPLAY
GROUP BY EVENT_ID
HAVING COUNT(*) > 1;
```

---

## 24. Replay Safely

Replay through the same business logic used by the normal pipeline whenever possible.

Avoid maintaining completely separate transformation logic for recovery.

Example:

```sql
MERGE INTO PROD.CUSTOMER T
USING STAGE.CUSTOMER_REPLAY S
ON T.CUSTOMER_ID = S.CUSTOMER_ID

WHEN MATCHED
 AND S.OPERATION <> 'DELETE'
 AND S.EVENT_TS >= T.SOURCE_EVENT_TS
THEN UPDATE SET
    T.CUSTOMER_NAME = S.CUSTOMER_NAME,
    T.EMAIL = S.EMAIL,
    T.SOURCE_EVENT_TS = S.EVENT_TS,
    T.UPDATED_AT = CURRENT_TIMESTAMP()

WHEN NOT MATCHED
 AND S.OPERATION <> 'DELETE'
THEN INSERT (
    CUSTOMER_ID,
    CUSTOMER_NAME,
    EMAIL,
    SOURCE_EVENT_TS
)
VALUES (
    S.CUSTOMER_ID,
    S.CUSTOMER_NAME,
    S.EMAIL,
    S.EVENT_TS
);
```

Then process deletes according to the pipeline's delete policy.

---

## 25. Backfill vs Replay

These operations are related but different.

### Replay

Reprocesses data that should already have been processed.

Example:

```text
CDC failed from 12:00–13:00.
Replay that missing window.
```

### Backfill

Processes historical data that was not previously part of normal pipeline coverage.

Example:

```text
A new derived column requires recalculating six months of history.
```

Both operations should be:

- bounded,
- auditable,
- idempotent,
- resource controlled,
- reconciled.

---

## 26. Prevent Backfills From Hurting Production

Large recovery operations can compete with production workloads.

Possible controls:

- dedicated recovery warehouse,
- smaller replay batches,
- resource monitors,
- scheduled recovery windows,
- query timeouts,
- bounded concurrency,
- incremental reconciliation.

Example:

```sql
CREATE WAREHOUSE IF NOT EXISTS RECOVERY_WH
WAREHOUSE_SIZE = 'SMALL'
AUTO_SUSPEND = 60
AUTO_RESUME = TRUE
INITIALLY_SUSPENDED = TRUE;
```

A separate warehouse isolates compute, although shared data and metadata considerations still remain.

---

## 27. Reconciliation Table

```sql
CREATE OR REPLACE TABLE RECOVERY.PIPELINE_RECONCILIATION (
    RECON_ID STRING,
    RUN_ID STRING,
    PIPELINE_NAME STRING,
    RECONCILED_AT TIMESTAMP_LTZ,
    SOURCE_COUNT NUMBER,
    TARGET_COUNT NUMBER,
    MISSING_COUNT NUMBER,
    EXTRA_COUNT NUMBER,
    MISMATCH_COUNT NUMBER,
    STATUS STRING,
    DETAILS VARIANT
);
```

Recovery is not complete until correctness has been verified.

---

## 28. Count Reconciliation

```sql
SELECT COUNT(*)
FROM RAW.CUSTOMER_EVENTS
WHERE EVENT_TS >= '2026-10-07 12:00:00'
  AND EVENT_TS <  '2026-10-07 13:00:00';
```

Compare the relevant business entities in the target.

Simple row counts alone are not sufficient for every pipeline, but they provide an initial signal.

---

## 29. Missing-Key Reconciliation

```sql
SELECT DISTINCT R.CUSTOMER_ID
FROM RAW.CUSTOMER_EVENTS R
LEFT JOIN PROD.CUSTOMER T
    ON R.CUSTOMER_ID = T.CUSTOMER_ID
WHERE R.EVENT_TS >= '2026-10-07 12:00:00'
  AND R.EVENT_TS <  '2026-10-07 13:00:00'
  AND R.OPERATION <> 'DELETE'
  AND T.CUSTOMER_ID IS NULL;
```

Expected result after successful recovery:

```text
0 rows
```

---

## 30. Value Reconciliation

Compare expected latest source state against the target.

```sql
WITH LATEST_SOURCE AS (
    SELECT *
    FROM RAW.CUSTOMER_EVENTS
    WHERE OPERATION <> 'DELETE'
    QUALIFY ROW_NUMBER() OVER (
        PARTITION BY CUSTOMER_ID
        ORDER BY EVENT_TS DESC
    ) = 1
)
SELECT
    S.CUSTOMER_ID,
    S.CUSTOMER_NAME AS SOURCE_NAME,
    T.CUSTOMER_NAME AS TARGET_NAME,
    S.EMAIL AS SOURCE_EMAIL,
    T.EMAIL AS TARGET_EMAIL
FROM LATEST_SOURCE S
JOIN PROD.CUSTOMER T
    ON S.CUSTOMER_ID = T.CUSTOMER_ID
WHERE
    NVL(S.CUSTOMER_NAME, '') <> NVL(T.CUSTOMER_NAME, '')
 OR NVL(S.EMAIL, '') <> NVL(T.EMAIL, '');
```

Expected result:

```text
0 rows
```

---

## 31. Hash Reconciliation

For wider records, a deterministic hash can simplify comparison.

Example:

```sql
SELECT
    CUSTOMER_ID,
    HASH(
        CUSTOMER_NAME,
        EMAIL
    ) AS RECORD_HASH
FROM PROD.CUSTOMER;
```

Use the same canonical column ordering and normalization on both sides.

Hash comparison does not eliminate the need to understand business semantics.

---

## 32. Recovery Audit Table

```sql
CREATE OR REPLACE TABLE RECOVERY.PIPELINE_RECOVERY_AUDIT (
    RECOVERY_ID STRING,
    PIPELINE_NAME STRING,
    FAILED_RUN_ID STRING,
    FAILURE_STARTED_AT TIMESTAMP_LTZ,
    FAILURE_DETECTED_AT TIMESTAMP_LTZ,
    RECOVERY_STARTED_AT TIMESTAMP_LTZ,
    RECOVERY_COMPLETED_AT TIMESTAMP_LTZ,
    FAILURE_CLASS STRING,
    ROOT_CAUSE STRING,
    RECOVERY_ACTION STRING,
    REPLAY_RANGE_START TIMESTAMP_LTZ,
    REPLAY_RANGE_END TIMESTAMP_LTZ,
    ROWS_RECOVERED NUMBER,
    RPO_SECONDS NUMBER,
    RTO_SECONDS NUMBER,
    VALIDATION_STATUS STRING,
    OPERATOR STRING,
    NOTES STRING
);
```

This provides a history for:

- incidents,
- reliability reviews,
- capacity planning,
- recurring-failure analysis,
- audit evidence.

---

## 33. RPO

**Recovery Point Objective (RPO)** defines the acceptable amount of data loss or unprocessed data after a failure.

Example:

```text
RPO = 5 minutes
```

The architecture must retain enough source information to reconstruct that window.

For a zero-data-loss logical requirement, replayable source records must remain durable until downstream processing is confirmed.

---

## 34. RTO

**Recovery Time Objective (RTO)** defines how quickly service should be restored.

Example:

```text
RTO = 30 minutes
```

RTO includes activities such as:

```text
detect
diagnose
repair
replay
reconcile
resume
```

Observability from Chapter 89 directly affects achievable RTO.

A failure that takes 20 minutes to detect already consumes most of a 30-minute RTO.

---

## 35. Measure Actual Recovery Time

```sql
SELECT
    RECOVERY_ID,
    PIPELINE_NAME,
    DATEDIFF(
        'second',
        FAILURE_DETECTED_AT,
        RECOVERY_COMPLETED_AT
    ) AS ACTUAL_RTO_SECONDS
FROM RECOVERY.PIPELINE_RECOVERY_AUDIT;
```

Compare measured recovery time with the defined objective.

---

## 36. Task Failure Investigation

Inspect task history:

```sql
SELECT *
FROM TABLE(
    INFORMATION_SCHEMA.TASK_HISTORY(
        SCHEDULED_TIME_RANGE_START =>
            DATEADD('hour', -24, CURRENT_TIMESTAMP())
    )
)
ORDER BY SCHEDULED_TIME DESC;
```

Review:

- task name,
- state,
- scheduled time,
- completed time,
- query ID,
- error code,
- error message.

Do not simply resume a failed task before determining whether replay is safe.

---

## 37. Task Recovery Workflow

```text
Task failure detected
       |
       v
Identify failed run
       |
       v
Determine committed state
       |
       v
Check checkpoint
       |
       v
Classify failure
       |
       +--> transient -> retry
       |
       +--> permanent -> remediate
       |
       v
Replay safely
       |
       v
Reconcile
       |
       v
Resume schedule
```

If a task was suspended during investigation:

```sql
ALTER TASK <task_name> RESUME;
```

Resume only after the recovery boundary is understood.

---

## 38. Time Travel Recovery

Snowflake Time Travel can help recover from accidental data modifications while the historical data remains within the applicable retention period.

Example investigation:

```sql
SELECT *
FROM PROD.CUSTOMER
AT (OFFSET => -60 * 5);
```

This queries an earlier table state approximately five minutes before the current time.

Always verify the desired historical point before restoring data.

---

## 39. Recover an Accidentally Modified Table

One safe pattern is to clone a historical version for inspection.

```sql
CREATE OR REPLACE TABLE RECOVERY.CUSTOMER_BEFORE_INCIDENT
CLONE PROD.CUSTOMER
AT (OFFSET => -60 * 5);
```

Compare it with the current table:

```sql
SELECT *
FROM RECOVERY.CUSTOMER_BEFORE_INCIDENT
MINUS
SELECT *
FROM PROD.CUSTOMER;
```

Do not overwrite production immediately.

Validate the recovery dataset first.

---

## 40. Recover Specific Rows

If only specific rows were damaged, recover only those rows.

Example:

```sql
MERGE INTO PROD.CUSTOMER T
USING RECOVERY.CUSTOMER_BEFORE_INCIDENT S
ON T.CUSTOMER_ID = S.CUSTOMER_ID

WHEN MATCHED THEN
UPDATE SET
    T.CUSTOMER_NAME = S.CUSTOMER_NAME,
    T.EMAIL = S.EMAIL,
    T.SOURCE_EVENT_TS = S.SOURCE_EVENT_TS,
    T.UPDATED_AT = CURRENT_TIMESTAMP();
```

Restrict the recovery source to the affected keys whenever possible.

---

## 41. Recover a Dropped Object

If a table was accidentally dropped and remains recoverable:

```sql
UNDROP TABLE PROD.CUSTOMER;
```

Verify immediately:

```sql
SELECT COUNT(*)
FROM PROD.CUSTOMER;
```

Then validate:

- schema,
- row counts,
- downstream dependencies,
- pipeline behavior.

Do not treat `UNDROP` as a substitute for a complete recovery strategy.

---

## 42. Recovery From Bad Deployment

Suppose a transformation deployment writes incorrect values.

Recovery procedure:

```text
1. Stop or suspend affected processing
2. Record incident time
3. Identify affected runs
4. Identify affected rows/time window
5. Roll back/fix transformation
6. Build recovery dataset
7. Replay affected range
8. Reconcile
9. Resume pipeline
10. Document root cause
```

Avoid continuing to process bad data merely to keep the schedule green.

---

## 43. Schema-Change Failure

Example failure:

```text
Source changes CUSTOMER_ID from NUMBER to VARCHAR.
```

Possible pipeline impact:

- transformation failure,
- failed cast,
- DQ rejection,
- incorrect joins,
- silent data loss if unsafe conversion is used.

Detect the problem before replay.

Example inspection:

```sql
DESC TABLE RAW.CUSTOMER_EVENTS;
```

Recovery should include:

```text
schema remediation
+
reprocessing affected range
+
reconciliation
```

---

## 44. Quarantine Invalid Data

Not every invalid record should stop an entire batch.

Create a quarantine table:

```sql
CREATE OR REPLACE TABLE RECOVERY.CUSTOMER_QUARANTINE (
    EVENT_ID STRING,
    CUSTOMER_ID NUMBER,
    RAW_RECORD VARIANT,
    FAILURE_REASON STRING,
    QUARANTINED_AT TIMESTAMP_LTZ DEFAULT CURRENT_TIMESTAMP(),
    RUN_ID STRING,
    RESOLUTION_STATUS STRING
);
```

Use quarantine when business policy permits valid records to continue.

Do not use quarantine to hide systemic pipeline failures.

---

## 45. Dead-Letter Pattern

A dead-letter pattern can isolate records that repeatedly fail deterministic processing.

Example lifecycle:

```text
NEW
  |
  v
FAILED
  |
  v
RETRY
  |
  +--> SUCCESS
  |
  +--> DEAD_LETTER
```

Dead-letter records require:

- reason,
- original payload,
- attempt count,
- source identifier,
- remediation status,
- replay capability.

---

## 46. Failure Injection Test 1 — Duplicate Event

Insert the same event twice:

```sql
INSERT INTO RAW.CUSTOMER_EVENTS
SELECT *
FROM RAW.CUSTOMER_EVENTS
WHERE EVENT_ID = 'EVT-001';
```

Run the pipeline.

Expected result:

```text
No duplicate business state.
Duplicate event is skipped or converges idempotently.
```

---

## 47. Failure Injection Test 2 — Out-of-Order Event

Insert an older event after a newer event:

```sql
INSERT INTO RAW.CUSTOMER_EVENTS (
    EVENT_ID,
    CUSTOMER_ID,
    OPERATION,
    CUSTOMER_NAME,
    EMAIL,
    EVENT_TS
)
VALUES (
    'EVT-OLD-101',
    101,
    'UPDATE',
    'Old Alice',
    'old@example.com',
    '2026-10-07 11:00:00'
);
```

Expected result:

```text
The older event must not overwrite newer target state.
```

---

## 48. Failure Injection Test 3 — Bad Data

Insert invalid data:

```sql
INSERT INTO RAW.CUSTOMER_EVENTS (
    EVENT_ID,
    CUSTOMER_ID,
    OPERATION,
    CUSTOMER_NAME,
    EMAIL,
    EVENT_TS
)
VALUES (
    'EVT-BAD-001',
    NULL,
    'INSERT',
    'Invalid Customer',
    'invalid@example.com',
    CURRENT_TIMESTAMP()
);
```

Expected result:

```text
DQ validation fails or record is quarantined.
Checkpoint does not incorrectly skip the failed data.
```

---

## 49. Failure Injection Test 4 — Processing Interruption

Simulate a failure after staging but before final checkpoint advancement.

Verify:

```text
target state
checkpoint state
run status
processed-event ledger
replay behavior
```

Then rerun the same batch.

Expected result:

```text
No duplicate target state.
Pipeline completes successfully.
Checkpoint advances only after successful reconciliation.
```

---

## 50. Failure Injection Test 5 — Accidental Update

Before the test, preserve a known state.

Then intentionally modify a test record:

```sql
UPDATE PROD.CUSTOMER
SET EMAIL = 'incorrect@example.com'
WHERE CUSTOMER_ID = 101;
```

Use Time Travel to identify the previous value.

Recover the row.

Expected result:

```text
Original value restored.
Recovery is recorded in audit history.
```

---

## 51. Failure Injection Test 6 — Dropped Table

Only perform this in a disposable lab environment.

```sql
DROP TABLE PROD.CUSTOMER;
```

Recover:

```sql
UNDROP TABLE PROD.CUSTOMER;
```

Validate:

```sql
SELECT COUNT(*)
FROM PROD.CUSTOMER;
```

Expected result:

```text
Table restored and pipeline validation passes.
```

---

## 52. Recovery Validation Checklist

After any recovery, verify:

```text
[ ] failed interval identified
[ ] root cause understood
[ ] source replay range identified
[ ] source data still available
[ ] replay is idempotent
[ ] checkpoint is correct
[ ] duplicate protection verified
[ ] target counts reconciled
[ ] missing keys checked
[ ] value/hash reconciliation passed
[ ] DQ checks passed
[ ] task schedule restored
[ ] stream health verified
[ ] pipeline freshness restored
[ ] recovery audit recorded
[ ] RPO measured
[ ] RTO measured
```

---

## 53. Incident Query Pack

### Recent failed pipeline runs

```sql
SELECT *
FROM CONTROL.PIPELINE_RUN_CONTROL
WHERE STATUS IN (
    'FAILED',
    'RETRY_PENDING',
    'RECOVERY_REQUIRED'
)
ORDER BY STARTED_AT DESC;
```

### Current checkpoints

```sql
SELECT *
FROM CONTROL.PIPELINE_CHECKPOINT
ORDER BY PIPELINE_NAME;
```

### Retry history

```sql
SELECT *
FROM CONTROL.PIPELINE_RETRY_LOG
ORDER BY CREATED_AT DESC;
```

### Open replay requests

```sql
SELECT *
FROM RECOVERY.PIPELINE_REPLAY_REQUEST
WHERE STATUS NOT IN ('COMPLETED', 'CANCELLED')
ORDER BY REQUESTED_AT;
```

### Recovery history

```sql
SELECT *
FROM RECOVERY.PIPELINE_RECOVERY_AUDIT
ORDER BY FAILURE_STARTED_AT DESC;
```

---

## 54. Operational Runbook — Pipeline Failed

### Step 1 — Confirm scope

Determine:

```text
pipeline
failed run
failure start
last successful run
last successful checkpoint
affected downstream datasets
```

### Step 2 — Stop unsafe processing

If continued processing could worsen the incident, suspend the affected task or orchestration path.

### Step 3 — Classify failure

Determine whether it is:

```text
transient
data quality
schema
permission
SQL/deployment
CDC gap
resource
source dependency
```

### Step 4 — Determine commit state

Answer:

```text
Did target DML commit?
Did the checkpoint advance?
Were processed-event records written?
Was the stream consumed?
```

### Step 5 — Fix root cause

Do not replay before the underlying deterministic failure is fixed.

### Step 6 — Replay

Replay from the last known-good boundary.

### Step 7 — Reconcile

Validate counts, keys, values, DQ, and freshness.

### Step 8 — Resume

Restore normal scheduling only after recovery validation succeeds.

### Step 9 — Audit

Record:

```text
cause
impact
replay window
rows recovered
RPO
RTO
follow-up actions
```

---

## 55. Operational Runbook — Missing CDC Window

```text
1. Identify last successful CDC checkpoint.
2. Identify first healthy event after the gap.
3. Determine exact missing range.
4. Verify retained raw/source data.
5. Pause normal consumer if overlap could occur.
6. Load replay staging dataset.
7. Deduplicate source events.
8. Apply ordering rules.
9. Run idempotent MERGE.
10. Apply deletes.
11. Reconcile target.
12. Re-establish normal CDC processing.
13. Verify stream/task health.
14. Record recovery.
```

---

## 56. Operational Runbook — Data Corruption

```text
1. Stop the writer causing corruption.
2. Identify incident start/end.
3. Identify affected objects and keys.
4. Determine whether Time Travel contains clean state.
5. Clone historical state for investigation.
6. Compare historical and current data.
7. Recover only affected rows where possible.
8. Reconcile.
9. Resume processing.
10. Record the recovery and root cause.
```

---

## 57. Operational Runbook — Stream Stale

```text
1. Confirm stream state.
2. Determine last successfully processed source boundary.
3. Determine missing CDC interval.
4. Locate durable raw/source history.
5. Rebuild the missing delta.
6. Replay through normal merge logic.
7. Reconcile.
8. Recreate/reset the CDC path as required.
9. Resume consumers.
10. Increase monitoring/retention protection if necessary.
```

The exact stream recreation procedure depends on the pipeline design and the desired CDC boundary.

---

## 58. Reliability SLOs

Example SLOs:

| Metric | Example Objective |
|---|---:|
| Pipeline success rate | >= 99.9% |
| Data freshness | <= 15 min |
| Failure detection | <= 5 min |
| Recovery RTO | <= 30 min |
| Recoverable source window | >= 24 h |
| Unreconciled recovery | 0 |
| Silent data loss | 0 |

These are examples only.

Production objectives must be based on business requirements.

---

## 59. Reliability Dashboard

Chapter 89's monitoring layer can expose:

```text
Pipeline Health
--------------
Success Rate
Failure Count
Retry Count
Recovery Required
Current Lag
Freshness
Stream Health
Checkpoint Age
Open Replay Requests
Open Quarantine Records
RPO Compliance
RTO Compliance
Reconciliation Failures
```

Reliability should be visible before an incident occurs.

---

## 60. Alert Conditions

Useful alert candidates include:

```text
pipeline failed
retry attempts exceeded
checkpoint not advancing
freshness SLO violated
stream approaching staleness
reconciliation failed
quarantine volume above threshold
replay request failed
RTO threshold exceeded
source-to-target gap detected
task repeatedly failing
```

Avoid alerts that do not lead to an operator action.

---

## 61. Recovery Access Control

Recovery operations can be destructive.

Separate normal pipeline permissions from recovery permissions.

Conceptually:

```text
PIPELINE_RUNTIME_ROLE
PIPELINE_OPERATOR_ROLE
PIPELINE_RECOVERY_ROLE
PIPELINE_ADMIN_ROLE
```

Examples of privileged recovery actions:

```text
UNDROP
historical restore
large replay
task suspension/resumption
production target correction
recovery warehouse changes
```

Use least privilege and auditable role activation.

---

## 62. Recovery Change Control

High-risk recovery actions should capture:

```text
incident/ticket ID
operator
approver
object
time range
estimated row count
recovery SQL/version
rollback approach
validation query
start/end time
result
```

The objective is not bureaucracy.

The objective is repeatability under pressure.

---

## 63. Avoid These Recovery Anti-Patterns

### Anti-pattern 1

```text
Just rerun everything.
```

Why it is dangerous:

- duplicate processing,
- unnecessary compute,
- extended recovery,
- unintended updates.

### Anti-pattern 2

```text
Advance the checkpoint manually to make the alert disappear.
```

This can create silent data loss.

### Anti-pattern 3

```text
Retry forever.
```

Permanent failures will never recover automatically.

### Anti-pattern 4

```text
Use the stream as the permanent CDC archive.
```

Streams are not a substitute for durable replay history.

### Anti-pattern 5

```text
Recovery succeeded because the SQL completed.
```

SQL success does not prove data correctness.

Reconciliation is mandatory.

---

## 64. Production Readiness Review

Before calling a pipeline production-ready, answer:

### Data durability

```text
Can we reconstruct missing data?
How long is source history retained?
Does retention satisfy the RPO?
```

### Idempotency

```text
Can the same batch run twice safely?
Can duplicate events arrive safely?
Can out-of-order events arrive safely?
```

### Checkpointing

```text
Where is the durable boundary?
When does it advance?
Can operators inspect it?
```

### Recovery

```text
Can we replay a bounded range?
Can we backfill safely?
Can we recover corrupted data?
```

### Observability

```text
Can we detect failures quickly?
Can we see pipeline lag?
Can we see stream health?
```

### Validation

```text
Can we prove recovery correctness?
```

If any answer is "no," the pipeline still has a reliability gap.

---

## 65. Final Acceptance Test

The project passes only when all of the following are demonstrated.

### Normal processing

```text
[ ] insert processed
[ ] update processed
[ ] delete processed
[ ] checkpoint advanced
[ ] run marked successful
```

### Duplicate safety

```text
[ ] duplicate event replayed
[ ] no duplicate business state
```

### Ordering safety

```text
[ ] old event delivered after new event
[ ] newer target state preserved
```

### Failure handling

```text
[ ] failed run recorded
[ ] failure classified
[ ] retry behavior correct
[ ] maximum retries enforced
```

### Replay

```text
[ ] bounded replay requested
[ ] replay executed
[ ] replay audited
```

### Reconciliation

```text
[ ] row/count validation passed
[ ] missing-key validation passed
[ ] value/hash validation passed
[ ] DQ checks passed
```

### Recovery

```text
[ ] accidental update recovered
[ ] historical state validated
[ ] dropped test object recovered
```

### Operations

```text
[ ] RPO measurable
[ ] RTO measurable
[ ] alert conditions defined
[ ] recovery runbooks usable
```

---

## 66. End-to-End Production Pattern

The completed architecture now looks like:

```text
                    +----------------------+
                    |   Observability      |
                    |   Chapter 89         |
                    +----------+-----------+
                               |
                               v
Source -> Raw -> CDC -> Stage -> DQ -> MERGE -> Target
  |       |      |       |      |       |        |
  |       |      |       |      |       |        |
  +-------+------+-------+------+-------+--------+
                               |
                               v
                    Reliability Controls
                    --------------------
                    Run Control
                    Checkpoints
                    Retry Log
                    Event Ledger
                    Replay Requests
                    Quarantine
                    Reconciliation
                    Recovery Audit
                               |
                               v
                       Recovery Runbooks
```

This gives the Snowflake project series a complete operational path:

```text
ingest
   ->
incrementally process
   ->
validate
   ->
observe
   ->
detect failure
   ->
recover
   ->
reconcile
   ->
resume
```

---

## 67. Key Takeaways

A reliable Snowflake pipeline is designed for failure before failure occurs.

The most important practices are:

1. Keep a durable last-known-good checkpoint.
2. Make processing idempotent.
3. Protect against duplicate and out-of-order events.
4. Retain replayable source data.
5. Separate retryable from permanent failures.
6. Bound all automatic retries.
7. Treat streams as change-tracking objects, not permanent archives.
8. Make replay and backfill explicit operational workflows.
9. Reconcile after every recovery.
10. Use Time Travel carefully for data-recovery scenarios.
11. Measure actual RPO and RTO performance.
12. Audit recovery operations.
13. Test failure scenarios before production incidents occur.
14. Never equate successful SQL execution with successful recovery.

The final reliability rule is simple:

> A production pipeline is not reliable because it never fails. It is reliable because failures are detected quickly, data remains recoverable, recovery is safe and repeatable, and correctness can be proven afterward.

---

## 68. Project Completion

You have now built a production-oriented Snowflake reliability and recovery framework covering:

- pipeline run control,
- checkpoints,
- retries,
- CDC recovery,
- idempotency,
- duplicate protection,
- ordering protection,
- replay,
- backfill,
- quarantine,
- reconciliation,
- Time Travel recovery,
- dropped-object recovery,
- RPO/RTO,
- operational runbooks,
- failure injection,
- and production acceptance testing.

**Chapter 90 status: COMPLETE**
