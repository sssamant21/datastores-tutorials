# Chapter 87 — Snowflake CDC / Incremental Pipeline Project

## 87.1 Introduction

Chapter 86 built a production batch-ingestion pipeline. This chapter extends that foundation into a production-ready **Change Data Capture (CDC) and incremental processing pipeline** in Snowflake.

The objective is to process only data that has changed since the previous successful pipeline execution instead of repeatedly rebuilding an entire target table.

A production CDC pipeline must handle more than inserts. It must safely process:

- Inserts
- Updates
- Deletes
- Duplicate events
- Out-of-order events
- Pipeline retries
- Task failures
- Replay and recovery
- Schema changes
- Monitoring and alerting
- Data reconciliation

The reference implementation uses:

- Snowflake tables
- Snowflake Streams
- Snowflake Tasks
- `MERGE`
- Control and audit tables
- Data-quality validation
- Operational monitoring

---

## 87.2 Project Objective

Build an incremental pipeline with the following logical flow:

```text
Source / Upstream Feed
        |
        v
+-------------------------+
| DAP.L1.EMPI_SOURCE      |
| Current landing state   |
+------------+------------+
             |
             | Snowflake Stream
             v
+-------------------------+
| EMPI_SOURCE_STREAM      |
| INSERT / UPDATE / DELETE|
+------------+------------+
             |
             | Scheduled Task
             v
+-------------------------+
| CDC Processing          |
| Validation + MERGE      |
+------------+------------+
             |
             v
+-------------------------+
| DAP.L2.EMPI             |
| Current trusted state   |
+------------+------------+
             |
             v
+-------------------------+
| Audit / Monitoring      |
| Reconciliation          |
+-------------------------+
```

### Production requirements

The pipeline should provide:

1. Incremental processing.
2. Correct insert/update/delete behavior.
3. Idempotent target state.
4. Controlled task execution.
5. Failure visibility.
6. Recovery procedures.
7. Reconciliation between source changes and target results.
8. Operational evidence for incident investigation.

---

## 87.3 CDC Versus Batch Processing

A batch pipeline often processes a complete file, partition, or dataset for each run.

CDC processes only changed records.

Example source state:

| EMPI_ID | NAME | STATUS | UPDATED_AT |
|---|---|---|---|
| 1001 | Alice | ACTIVE | 10:00 |
| 1002 | Bob | ACTIVE | 10:00 |

Later changes:

```text
1001 -> STATUS changes ACTIVE -> INACTIVE
1002 -> deleted
1003 -> inserted
```

A full batch could reload all records.

A CDC pipeline should process only:

```text
UPDATE 1001
DELETE 1002
INSERT 1003
```

This can reduce unnecessary scanning, compute consumption, and processing latency for suitable workloads.

---

## 87.4 CDC Design Principles

A reliable CDC design should follow these principles.

### Principle 1 — Changes must be identifiable

The system needs a reliable way to determine what changed.

Examples include:

- Snowflake Streams
- Source CDC sequence numbers
- Source transaction timestamps
- Incrementing IDs
- Reliable `UPDATED_AT` columns
- External CDC tools

### Principle 2 — Processing must be restartable

A failed pipeline should be recoverable without corrupting the target.

### Principle 3 — Target changes should be idempotent

Reprocessing the same logical source change should converge on the same target state whenever possible.

### Principle 4 — Deletes must be explicitly designed

Ignoring deletes produces stale target data.

### Principle 5 — Operational state must be observable

Operators need to know:

- When the pipeline last succeeded
- Whether changes are waiting
- How many rows were processed
- Whether tasks failed
- Whether source and target remain consistent

---

## 87.5 Create the Project Objects

For the lab, use separate schemas or objects appropriate for the environment.

```sql
CREATE DATABASE IF NOT EXISTS DAP;

CREATE SCHEMA IF NOT EXISTS DAP.L1;
CREATE SCHEMA IF NOT EXISTS DAP.L2;
CREATE SCHEMA IF NOT EXISTS DAP.CONTROL;
```

Create the source table:

```sql
CREATE OR REPLACE TABLE DAP.L1.EMPI_SOURCE (
    EMPI_ID        NUMBER,
    FIRST_NAME     VARCHAR,
    LAST_NAME      VARCHAR,
    STATUS         VARCHAR,
    UPDATED_AT     TIMESTAMP_NTZ,
    SOURCE_SYSTEM  VARCHAR
);
```

Create the target table:

```sql
CREATE OR REPLACE TABLE DAP.L2.EMPI (
    EMPI_ID          NUMBER,
    FIRST_NAME       VARCHAR,
    LAST_NAME        VARCHAR,
    STATUS           VARCHAR,
    SOURCE_SYSTEM    VARCHAR,
    SOURCE_UPDATED_AT TIMESTAMP_NTZ,
    CREATED_AT       TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP(),
    MODIFIED_AT      TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP()
);
```

For this project, `EMPI_ID` is treated as the business key used to match source changes to target rows.

---

## 87.6 Load Initial Source Data

```sql
INSERT INTO DAP.L1.EMPI_SOURCE
    (EMPI_ID, FIRST_NAME, LAST_NAME, STATUS, UPDATED_AT, SOURCE_SYSTEM)
VALUES
    (1001, 'Alice', 'Brown', 'ACTIVE', CURRENT_TIMESTAMP(), 'CRM'),
    (1002, 'Bob',   'Smith', 'ACTIVE', CURRENT_TIMESTAMP(), 'CRM'),
    (1003, 'Carol', 'Jones', 'ACTIVE', CURRENT_TIMESTAMP(), 'CRM');
```

Verify:

```sql
SELECT *
FROM DAP.L1.EMPI_SOURCE
ORDER BY EMPI_ID;
```

For an initial deployment, bootstrap the target before starting normal incremental processing.

```sql
INSERT INTO DAP.L2.EMPI (
    EMPI_ID,
    FIRST_NAME,
    LAST_NAME,
    STATUS,
    SOURCE_SYSTEM,
    SOURCE_UPDATED_AT
)
SELECT
    EMPI_ID,
    FIRST_NAME,
    LAST_NAME,
    STATUS,
    SOURCE_SYSTEM,
    UPDATED_AT
FROM DAP.L1.EMPI_SOURCE;
```

---

## 87.7 Create a Snowflake Stream

A Snowflake Stream records change information for a source object between offsets.

Create the stream after the initial bootstrap:

```sql
CREATE OR REPLACE STREAM DAP.L1.EMPI_SOURCE_STREAM
ON TABLE DAP.L1.EMPI_SOURCE;
```

Inspect it:

```sql
SHOW STREAMS IN SCHEMA DAP.L1;
```

Check whether the stream currently has data:

```sql
SELECT SYSTEM$STREAM_HAS_DATA('DAP.L1.EMPI_SOURCE_STREAM');
```

Expected immediately after creation:

```text
FALSE
```

---

## 87.8 Understand Stream Metadata

Query the stream:

```sql
SELECT
    EMPI_ID,
    FIRST_NAME,
    LAST_NAME,
    STATUS,
    UPDATED_AT,
    SOURCE_SYSTEM,
    METADATA$ACTION,
    METADATA$ISUPDATE,
    METADATA$ROW_ID
FROM DAP.L1.EMPI_SOURCE_STREAM;
```

Important metadata fields include:

| Field | Purpose |
|---|---|
| `METADATA$ACTION` | Indicates INSERT or DELETE |
| `METADATA$ISUPDATE` | Helps identify rows participating in an UPDATE |
| `METADATA$ROW_ID` | Snowflake row identifier associated with change tracking |

A standard table stream represents an update as a DELETE plus INSERT pair, with update metadata indicating the relationship.

That behavior must be considered when building downstream logic.

---

## 87.9 Generate CDC Events

### Insert

```sql
INSERT INTO DAP.L1.EMPI_SOURCE
VALUES (
    1004,
    'David',
    'Wilson',
    'ACTIVE',
    CURRENT_TIMESTAMP(),
    'CRM'
);
```

### Update

```sql
UPDATE DAP.L1.EMPI_SOURCE
SET
    STATUS = 'INACTIVE',
    UPDATED_AT = CURRENT_TIMESTAMP()
WHERE EMPI_ID = 1001;
```

### Delete

```sql
DELETE FROM DAP.L1.EMPI_SOURCE
WHERE EMPI_ID = 1002;
```

Inspect the stream:

```sql
SELECT
    EMPI_ID,
    STATUS,
    METADATA$ACTION,
    METADATA$ISUPDATE,
    METADATA$ROW_ID
FROM DAP.L1.EMPI_SOURCE_STREAM
ORDER BY EMPI_ID, METADATA$ACTION;
```

The stream should now contain change records representing the insert, update, and delete operations.

---

## 87.10 CDC Processing Strategy

For this project:

- True deletes remove the matching target record.
- Inserts and the INSERT side of updates are upserted into the target.
- The DELETE side of an update must **not** be treated as a business delete.

Logical rule:

```text
IF ACTION = DELETE AND ISUPDATE = FALSE
    DELETE target row

IF ACTION = INSERT
    MERGE source row into target
```

This prevents an UPDATE from accidentally deleting the target row permanently.

---

## 87.11 Create an Audit Table

Production pipelines need execution evidence.

```sql
CREATE OR REPLACE TABLE DAP.CONTROL.CDC_PIPELINE_AUDIT (
    RUN_ID            VARCHAR,
    PIPELINE_NAME     VARCHAR,
    STARTED_AT        TIMESTAMP_NTZ,
    COMPLETED_AT      TIMESTAMP_NTZ,
    STATUS            VARCHAR,
    STREAM_ROWS       NUMBER,
    INSERT_UPDATE_ROWS NUMBER,
    DELETE_ROWS       NUMBER,
    ERROR_MESSAGE     VARCHAR
);
```

Example statuses:

```text
RUNNING
SUCCESS
FAILED
```

The audit table provides a durable operational record independent of transient task monitoring views.

---

## 87.12 Create the CDC Processing Procedure

A stored procedure can package the CDC transaction and audit behavior.

The important production requirement is that stream consumption and target modification occur as one controlled unit of work.

```sql
CREATE OR REPLACE PROCEDURE DAP.CONTROL.PROCESS_EMPI_CDC()
RETURNS VARCHAR
LANGUAGE SQL
EXECUTE AS OWNER
AS
$$
DECLARE
    V_RUN_ID VARCHAR DEFAULT UUID_STRING();
    V_STREAM_ROWS NUMBER DEFAULT 0;
    V_UPSERT_ROWS NUMBER DEFAULT 0;
    V_DELETE_ROWS NUMBER DEFAULT 0;
BEGIN

    INSERT INTO DAP.CONTROL.CDC_PIPELINE_AUDIT (
        RUN_ID,
        PIPELINE_NAME,
        STARTED_AT,
        STATUS
    )
    VALUES (
        :V_RUN_ID,
        'EMPI_CDC_PIPELINE',
        CURRENT_TIMESTAMP(),
        'RUNNING'
    );

    BEGIN TRANSACTION;

    CREATE OR REPLACE TEMPORARY TABLE EMPI_CDC_WORK AS
    SELECT
        EMPI_ID,
        FIRST_NAME,
        LAST_NAME,
        STATUS,
        UPDATED_AT,
        SOURCE_SYSTEM,
        METADATA$ACTION AS CDC_ACTION,
        METADATA$ISUPDATE AS CDC_ISUPDATE,
        METADATA$ROW_ID AS CDC_ROW_ID
    FROM DAP.L1.EMPI_SOURCE_STREAM;

    SELECT COUNT(*)
      INTO :V_STREAM_ROWS
    FROM EMPI_CDC_WORK;

    SELECT COUNT(*)
      INTO :V_DELETE_ROWS
    FROM EMPI_CDC_WORK
    WHERE CDC_ACTION = 'DELETE'
      AND CDC_ISUPDATE = FALSE;

    SELECT COUNT(*)
      INTO :V_UPSERT_ROWS
    FROM EMPI_CDC_WORK
    WHERE CDC_ACTION = 'INSERT';

    DELETE FROM DAP.L2.EMPI AS T
    USING EMPI_CDC_WORK AS S
    WHERE S.CDC_ACTION = 'DELETE'
      AND S.CDC_ISUPDATE = FALSE
      AND T.EMPI_ID = S.EMPI_ID;

    MERGE INTO DAP.L2.EMPI AS T
    USING (
        SELECT
            EMPI_ID,
            FIRST_NAME,
            LAST_NAME,
            STATUS,
            UPDATED_AT,
            SOURCE_SYSTEM
        FROM EMPI_CDC_WORK
        WHERE CDC_ACTION = 'INSERT'
        QUALIFY ROW_NUMBER() OVER (
            PARTITION BY EMPI_ID
            ORDER BY UPDATED_AT DESC, CDC_ROW_ID DESC
        ) = 1
    ) AS S
    ON T.EMPI_ID = S.EMPI_ID

    WHEN MATCHED THEN UPDATE SET
        T.FIRST_NAME        = S.FIRST_NAME,
        T.LAST_NAME         = S.LAST_NAME,
        T.STATUS            = S.STATUS,
        T.SOURCE_SYSTEM     = S.SOURCE_SYSTEM,
        T.SOURCE_UPDATED_AT = S.UPDATED_AT,
        T.MODIFIED_AT       = CURRENT_TIMESTAMP()

    WHEN NOT MATCHED THEN INSERT (
        EMPI_ID,
        FIRST_NAME,
        LAST_NAME,
        STATUS,
        SOURCE_SYSTEM,
        SOURCE_UPDATED_AT,
        CREATED_AT,
        MODIFIED_AT
    )
    VALUES (
        S.EMPI_ID,
        S.FIRST_NAME,
        S.LAST_NAME,
        S.STATUS,
        S.SOURCE_SYSTEM,
        S.UPDATED_AT,
        CURRENT_TIMESTAMP(),
        CURRENT_TIMESTAMP()
    );

    COMMIT;

    UPDATE DAP.CONTROL.CDC_PIPELINE_AUDIT
    SET
        COMPLETED_AT       = CURRENT_TIMESTAMP(),
        STATUS             = 'SUCCESS',
        STREAM_ROWS        = :V_STREAM_ROWS,
        INSERT_UPDATE_ROWS = :V_UPSERT_ROWS,
        DELETE_ROWS        = :V_DELETE_ROWS
    WHERE RUN_ID = :V_RUN_ID;

    RETURN 'SUCCESS: ' || V_RUN_ID;

EXCEPTION
    WHEN OTHER THEN
        ROLLBACK;

        UPDATE DAP.CONTROL.CDC_PIPELINE_AUDIT
        SET
            COMPLETED_AT = CURRENT_TIMESTAMP(),
            STATUS       = 'FAILED',
            ERROR_MESSAGE = SQLERRM
        WHERE RUN_ID = :V_RUN_ID;

        RAISE;
END;
$$;
```

### Why materialize the stream into a temporary work table?

The work table creates one stable change set for the processing run.

The procedure can then:

- Count the changes.
- Separate real deletes from update pairs.
- Deduplicate inserts/upserts.
- Apply multiple target operations against the same captured change set.
- Preserve transactional control over stream consumption.

---

## 87.13 Test the Procedure Manually

Before automating CDC, execute it manually.

```sql
CALL DAP.CONTROL.PROCESS_EMPI_CDC();
```

Verify target state:

```sql
SELECT *
FROM DAP.L2.EMPI
ORDER BY EMPI_ID;
```

Expected business result:

```text
1001 -> INACTIVE
1002 -> removed
1003 -> unchanged
1004 -> inserted
```

Verify audit state:

```sql
SELECT *
FROM DAP.CONTROL.CDC_PIPELINE_AUDIT
ORDER BY STARTED_AT DESC;
```

Verify stream state:

```sql
SELECT SYSTEM$STREAM_HAS_DATA('DAP.L1.EMPI_SOURCE_STREAM');
```

After successful transactional consumption, it should normally report no pending changes until new source DML occurs.

---

## 87.14 Automate the Pipeline with a Snowflake Task

Create a task that runs only when the stream contains changes.

```sql
CREATE OR REPLACE TASK DAP.CONTROL.EMPI_CDC_TASK
    WAREHOUSE = CDC_WH
    SCHEDULE = '1 MINUTE'
    WHEN SYSTEM$STREAM_HAS_DATA('DAP.L1.EMPI_SOURCE_STREAM')
AS
    CALL DAP.CONTROL.PROCESS_EMPI_CDC();
```

Enable it:

```sql
ALTER TASK DAP.CONTROL.EMPI_CDC_TASK RESUME;
```

Check task definition:

```sql
SHOW TASKS LIKE 'EMPI_CDC_TASK' IN SCHEMA DAP.CONTROL;
```

For production, choose the schedule based on actual latency requirements rather than automatically selecting the shortest possible interval.

---

## 87.15 Monitor Task Execution

Query task history:

```sql
SELECT
    NAME,
    STATE,
    SCHEDULED_TIME,
    QUERY_START_TIME,
    COMPLETED_TIME,
    ERROR_CODE,
    ERROR_MESSAGE
FROM TABLE(
    INFORMATION_SCHEMA.TASK_HISTORY(
        TASK_NAME => 'DAP.CONTROL.EMPI_CDC_TASK',
        RESULT_LIMIT => 100
    )
)
ORDER BY SCHEDULED_TIME DESC;
```

Investigate failures:

```sql
SELECT
    NAME,
    STATE,
    SCHEDULED_TIME,
    ERROR_CODE,
    ERROR_MESSAGE
FROM TABLE(
    INFORMATION_SCHEMA.TASK_HISTORY(
        TASK_NAME => 'DAP.CONTROL.EMPI_CDC_TASK',
        RESULT_LIMIT => 100
    )
)
WHERE STATE = 'FAILED'
ORDER BY SCHEDULED_TIME DESC;
```

Also inspect the pipeline audit table:

```sql
SELECT *
FROM DAP.CONTROL.CDC_PIPELINE_AUDIT
ORDER BY STARTED_AT DESC;
```

Do not rely on only one monitoring source. Task history shows scheduler execution; the audit table shows pipeline-level processing state.

---

## 87.16 Incremental Watermark Pattern

Streams are not the only incremental pattern.

Some sources provide a reliable timestamp or sequence number instead.

Example control table:

```sql
CREATE OR REPLACE TABLE DAP.CONTROL.PIPELINE_WATERMARK (
    PIPELINE_NAME       VARCHAR,
    LAST_WATERMARK_TS   TIMESTAMP_NTZ,
    LAST_SUCCESS_AT     TIMESTAMP_NTZ
);
```

Initialize:

```sql
INSERT INTO DAP.CONTROL.PIPELINE_WATERMARK
VALUES (
    'EMPI_INCREMENTAL',
    '1970-01-01 00:00:00',
    NULL
);
```

Incremental extraction:

```sql
SELECT S.*
FROM DAP.L1.EMPI_SOURCE S
JOIN DAP.CONTROL.PIPELINE_WATERMARK W
  ON W.PIPELINE_NAME = 'EMPI_INCREMENTAL'
WHERE S.UPDATED_AT > W.LAST_WATERMARK_TS;
```

### Critical warning

A timestamp-only watermark can lose changes when:

- Multiple records share the same timestamp.
- Events arrive late.
- Source clocks are inconsistent.
- The watermark is advanced before target commit.

A stronger design can use a composite cursor such as:

```text
(UPDATED_AT, EMPI_ID)
```

or a source-provided monotonically increasing sequence/LSN when available.

---

## 87.17 Watermark Safety Window

A common production pattern is to intentionally overlap incremental extraction windows.

Example:

```sql
WHERE UPDATED_AT >= DATEADD(
    'minute',
    -5,
    :LAST_SUCCESSFUL_WATERMARK
)
```

The overlap reduces the chance of missing late-arriving records.

However, overlap introduces duplicates.

Therefore:

```text
Overlap window
      +
Deterministic deduplication
      +
Idempotent MERGE
      =
Safer incremental processing
```

Do not add an overlap window without also designing deduplication.

---

## 87.18 Idempotency

An idempotent pipeline can safely process the same logical input more than once without creating incorrect target state.

Bad pattern:

```sql
INSERT INTO target
SELECT * FROM incremental_source;
```

Repeated execution can create duplicates.

Better pattern:

```sql
MERGE INTO target T
USING source S
ON T.EMPI_ID = S.EMPI_ID
WHEN MATCHED THEN UPDATE ...
WHEN NOT MATCHED THEN INSERT ...;
```

For a production `MERGE`, ensure the source contains at most one deterministic winner for each target key.

Example:

```sql
SELECT *
FROM source_changes
QUALIFY ROW_NUMBER() OVER (
    PARTITION BY EMPI_ID
    ORDER BY UPDATED_AT DESC
) = 1;
```

If timestamps can tie, add another deterministic ordering field such as a source sequence number.

---

## 87.19 Duplicate Event Handling

CDC systems can receive duplicate events because of:

- Source retries
- Connector retries
- Replay
- Network recovery
- Overlapping extraction windows
- At-least-once delivery

Recommended source event metadata:

```text
EVENT_ID
SOURCE_SEQUENCE
SOURCE_UPDATED_AT
SOURCE_SYSTEM
BUSINESS_KEY
```

If a globally unique event ID exists, retain processed event IDs for the required replay horizon.

Example:

```sql
CREATE TABLE DAP.CONTROL.PROCESSED_CDC_EVENTS (
    EVENT_ID        VARCHAR,
    PROCESSED_AT    TIMESTAMP_NTZ,
    PIPELINE_NAME   VARCHAR
);
```

Then reject already-processed events when exact event-level deduplication is required.

---

## 87.20 Out-of-Order Event Handling

Consider two events:

```text
Event A: EMPI_ID=1001, STATUS=ACTIVE,   source sequence=100
Event B: EMPI_ID=1001, STATUS=INACTIVE, source sequence=101
```

If Event B arrives first and Event A arrives later, a naive pipeline could incorrectly restore the older state.

Protect the target with source ordering metadata.

Example:

```sql
WHEN MATCHED
 AND S.SOURCE_SEQUENCE > T.SOURCE_SEQUENCE
THEN UPDATE ...
```

The strongest ordering field should come from the source transaction/change system.

Do not assume ingestion time represents source transaction order.

---

## 87.21 Delete Handling Patterns

Deletes require an explicit business decision.

### Pattern A — Hard delete

```sql
DELETE FROM target
WHERE key = deleted_source_key;
```

Use when the target must mirror current source state and retention rules permit physical deletion.

### Pattern B — Soft delete

Add columns:

```text
IS_DELETED
DELETED_AT
```

Then update:

```sql
UPDATE target
SET
    IS_DELETED = TRUE,
    DELETED_AT = CURRENT_TIMESTAMP()
WHERE EMPI_ID = :EMPI_ID;
```

Soft delete can be preferable when downstream consumers need deletion history or auditability.

### Pattern C — Historical/SCD processing

Maintain version history instead of representing only current state.

That pattern is useful when the business requires point-in-time reconstruction.

---

## 87.22 CDC and Slowly Changing Dimensions

CDC answers:

> What changed?

SCD design answers:

> How should the target preserve that change historically?

For SCD Type 1:

```text
old value -> overwritten
```

For SCD Type 2:

```text
old row -> expired
new row -> inserted
```

Typical SCD2 fields:

```text
EFFECTIVE_FROM
EFFECTIVE_TO
IS_CURRENT
```

CDC and SCD are complementary patterns, not competing concepts.

---

## 87.23 Stream Staleness

Streams cannot be ignored indefinitely.

Snowflake data retention and stream offset behavior must be considered operationally. A stream that is not consumed within the applicable retention window can become stale and may need to be recreated.

Check stream metadata:

```sql
SHOW STREAMS IN SCHEMA DAP.L1;
```

Monitor attributes such as:

```text
STALE
STALE_AFTER
```

### Operational rule

Do not treat a stream as permanent storage for unprocessed CDC events.

Alert when:

- The pipeline has not succeeded for an abnormal period.
- A stream is approaching its staleness boundary.
- Pending CDC data remains unconsumed.

---

## 87.24 Failure Scenario — Task Fails Before Processing

Example:

```text
Source DML
   |
Stream has pending changes
   |
Task execution fails before transaction consumes stream
```

The changes remain available for a later successful consumer transaction, subject to retention/staleness constraints.

Operator actions:

1. Identify the task failure.
2. Correct the underlying problem.
3. Confirm the stream is not stale.
4. Confirm pending stream data.
5. Execute or resume processing.
6. Reconcile target state.

Useful query:

```sql
SELECT SYSTEM$STREAM_HAS_DATA('DAP.L1.EMPI_SOURCE_STREAM');
```

---

## 87.25 Failure Scenario — Target DML Fails

Suppose a target constraint, conversion, or SQL error occurs.

Desired behavior:

```text
BEGIN TRANSACTION
    capture stream change set
    apply target changes
    validation
COMMIT
```

On failure:

```text
ROLLBACK
```

The pipeline should not mark the run successful.

The audit record should contain:

- Run ID
- Start time
- Failure time
- Failure state
- Error message

After correction, rerun the transaction and verify the stream/target state.

---

## 87.26 Failure Scenario — Bad Record

A single malformed record should not create an endless production outage.

Possible design:

```text
CDC changes
    |
Validation
    +------ valid ------> target
    |
    +------ invalid ----> quarantine
```

Example quarantine table:

```sql
CREATE TABLE DAP.CONTROL.EMPI_CDC_QUARANTINE (
    RUN_ID          VARCHAR,
    EMPI_ID         NUMBER,
    RAW_PAYLOAD     VARIANT,
    ERROR_REASON    VARCHAR,
    QUARANTINED_AT  TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP()
);
```

Whether the pipeline continues or fails the entire transaction depends on the data contract and business correctness requirements.

Do not silently discard invalid records.

---

## 87.27 Replay Strategy

A production CDC design needs a replay mechanism independent of normal forward processing.

Possible replay sources:

- Retained raw files
- Durable source CDC log
- Kafka topic retention
- Landing/history table
- Time Travel, where applicable and within retention
- Upstream system re-extraction

Recommended architecture:

```text
Source
  |
  +----> durable raw/history layer
  |
  +----> current CDC processing
```

If the only copy of an event exists in a transient incremental mechanism, recovery options are limited.

---

## 87.28 Backfill Strategy

CDC handles forward changes. Backfill repairs or loads historical ranges.

Do not blindly run a large backfill through the normal low-latency task.

Preferred approach:

```text
Historical source
      |
      v
Dedicated backfill process
      |
      v
Validation / deduplication
      |
      v
MERGE into target
```

Backfill should define:

- Time/key range
- Expected row count
- Dedicated warehouse if appropriate
- Duplicate handling
- Conflict rules with live CDC
- Reconciliation
- Rollback/recovery plan

---

## 87.29 Live CDC and Backfill Concurrency

A dangerous scenario is:

```text
Live CDC updating target
          +
Historical backfill updating same keys
```

Potential outcomes include:

- Old values overwriting newer values
- Unnecessary transaction contention
- Non-deterministic final state

Protect the target using source version/sequence checks.

Example principle:

```text
Apply incoming record only when
incoming_source_version > target_source_version
```

If no trustworthy ordering metadata exists, operationally isolate the backfill or define a controlled cutover strategy.

---

## 87.30 Reconciliation

A successful task does not automatically prove business correctness.

Reconciliation should answer:

```text
Did the expected changes reach the target correctly?
```

### Current-state count comparison

```sql
SELECT COUNT(*) FROM DAP.L1.EMPI_SOURCE;
SELECT COUNT(*) FROM DAP.L2.EMPI;
```

Counts alone are insufficient, but large unexpected differences are useful signals.

### Missing target keys

```sql
SELECT S.EMPI_ID
FROM DAP.L1.EMPI_SOURCE S
LEFT JOIN DAP.L2.EMPI T
    ON S.EMPI_ID = T.EMPI_ID
WHERE T.EMPI_ID IS NULL;
```

### Unexpected target keys

```sql
SELECT T.EMPI_ID
FROM DAP.L2.EMPI T
LEFT JOIN DAP.L1.EMPI_SOURCE S
    ON T.EMPI_ID = S.EMPI_ID
WHERE S.EMPI_ID IS NULL;
```

### Attribute mismatch

```sql
SELECT
    S.EMPI_ID,
    S.STATUS AS SOURCE_STATUS,
    T.STATUS AS TARGET_STATUS
FROM DAP.L1.EMPI_SOURCE S
JOIN DAP.L2.EMPI T
    ON S.EMPI_ID = T.EMPI_ID
WHERE S.STATUS IS DISTINCT FROM T.STATUS;
```

For large datasets, reconciliation may use partitions, hashes, sampling, business aggregates, or exception-based checks rather than full row-by-row comparisons on every run.

---

## 87.31 CDC Lag Monitoring

CDC lag measures how far processing is behind the source.

A simple application-level approximation can be derived from source timestamps:

```sql
SELECT
    MAX(SOURCE_UPDATED_AT) AS LATEST_PROCESSED_SOURCE_TIME,
    DATEDIFF(
        'second',
        MAX(SOURCE_UPDATED_AT),
        CURRENT_TIMESTAMP()
    ) AS APPROX_PROCESSING_AGE_SECONDS
FROM DAP.L2.EMPI;
```

However, this is only meaningful when source timestamps are reliable and source activity is expected.

A more robust operational dashboard can combine:

- Last successful pipeline execution
- Oldest pending event time
- Latest source event time
- Latest target-applied source sequence
- Stream pending state
- Task failures

---

## 87.32 Monitoring Dashboard

Recommended production dashboard signals:

| Metric | Purpose |
|---|---|
| Last successful CDC run | Detect stalled pipeline |
| Last failed CDC run | Detect execution problems |
| Pending stream data | Detect unprocessed changes |
| CDC rows/run | Detect workload anomalies |
| Deletes/run | Detect unusual deletion activity |
| Processing duration | Detect performance degradation |
| Source-to-target lag | Detect freshness problems |
| Quarantined rows | Detect data-quality problems |
| Reconciliation failures | Detect correctness issues |
| Stream stale/stale-after | Protect recoverability |

---

## 87.33 Alerting Strategy

Example alert conditions:

### Critical

```text
Task repeatedly failing
Stream stale
CDC freshness SLA breached
Reconciliation detects material data loss/corruption
```

### Warning

```text
Processing duration significantly above baseline
Pending changes remain for multiple task intervals
Quarantine volume above threshold
CDC volume unexpectedly high/low
Stream approaching staleness window
```

Thresholds should be based on business SLAs and observed workload baselines.

---

## 87.34 Troubleshooting Runbook

When the CDC pipeline is not updating the target:

### Step 1 — Check whether source changes exist

```sql
SELECT *
FROM DAP.L1.EMPI_SOURCE
ORDER BY UPDATED_AT DESC
LIMIT 100;
```

### Step 2 — Check stream state

```sql
SELECT SYSTEM$STREAM_HAS_DATA('DAP.L1.EMPI_SOURCE_STREAM');
```

### Step 3 — Inspect stream metadata

```sql
SELECT
    *,
    METADATA$ACTION,
    METADATA$ISUPDATE,
    METADATA$ROW_ID
FROM DAP.L1.EMPI_SOURCE_STREAM;
```

### Step 4 — Check task state

```sql
SHOW TASKS LIKE 'EMPI_CDC_TASK' IN SCHEMA DAP.CONTROL;
```

### Step 5 — Check task history

```sql
SELECT *
FROM TABLE(
    INFORMATION_SCHEMA.TASK_HISTORY(
        TASK_NAME => 'DAP.CONTROL.EMPI_CDC_TASK',
        RESULT_LIMIT => 50
    )
)
ORDER BY SCHEDULED_TIME DESC;
```

### Step 6 — Check audit history

```sql
SELECT *
FROM DAP.CONTROL.CDC_PIPELINE_AUDIT
ORDER BY STARTED_AT DESC;
```

### Step 7 — Check target freshness

```sql
SELECT
    MAX(SOURCE_UPDATED_AT),
    MAX(MODIFIED_AT)
FROM DAP.L2.EMPI;
```

### Step 8 — Reconcile source and target

Run missing-key, unexpected-key, and attribute-mismatch checks.

### Step 9 — Correct the root cause

Examples:

- Warehouse unavailable
- Privilege change
- Invalid SQL
- Schema drift
- Data conversion failure
- Stale stream
- Incorrect task state

### Step 10 — Recover and validate

Do not close the incident merely because the task turns green. Confirm target correctness and freshness.

---

## 87.35 Common Production Problems

### Problem 1 — Task is suspended

Symptom:

```text
Source changes exist but target is stale.
```

Check:

```sql
SHOW TASKS LIKE 'EMPI_CDC_TASK' IN SCHEMA DAP.CONTROL;
```

Resolution:

```sql
ALTER TASK DAP.CONTROL.EMPI_CDC_TASK RESUME;
```

Then validate pending changes and target state.

### Problem 2 — Stream is stale

Symptom:

```text
Normal stream-based recovery is no longer available.
```

Resolution:

1. Stop normal processing.
2. Determine the missing data interval.
3. Recover from the durable source/raw layer.
4. Reconcile target state.
5. Recreate/re-establish the stream as required.
6. Resume CDC only after correctness is verified.

### Problem 3 — Duplicate target rows

Likely causes:

- Target business key not unique in practice
- Source contains multiple rows for a key
- Non-deterministic `MERGE` source
- Append-only processing used where upsert was required

Resolution:

1. Identify duplicate business keys.
2. Determine authoritative row ordering.
3. Deduplicate the target.
4. Add deterministic source reduction before `MERGE`.

### Problem 4 — Old event overwrites new data

Cause:

```text
No source version/sequence protection.
```

Resolution:

Store source ordering metadata in the target and update only when the incoming event is newer.

### Problem 5 — Deletes never reach target

Cause:

```text
Pipeline processes inserts/updates only.
```

Resolution:

Implement an explicit hard-delete, soft-delete, or history-retention policy.

---

## 87.36 Schema Evolution

CDC pipelines are sensitive to schema changes.

Examples:

```text
Column added
Column removed
VARCHAR -> NUMBER
Timestamp precision changed
JSON structure changed
Business key changed
```

Production process:

```text
Schema change detected
        |
        v
Assess compatibility
        |
        +--> backward compatible -> deploy target/pipeline change
        |
        +--> breaking change -> controlled migration
```

Never allow a breaking upstream schema change to silently enter a critical CDC pipeline.

Recommended controls:

- Contract/version checks
- Schema-change alerts
- Quarantine for incompatible records
- Backward-compatible deployment sequencing
- Rollback plan

---

## 87.37 Security and Access Control

Use least privilege.

Example role separation:

```text
CDC_OWNER_ROLE
    owns procedure/task objects

CDC_RUNTIME_ROLE
    required execution privileges

CDC_MONITOR_ROLE
    read-only operational visibility
```

Typical privileges can include only what is required for:

- Source table/stream access
- Target DML
- Procedure execution
- Task operation
- Warehouse usage
- Audit table access

Avoid using `ACCOUNTADMIN` for routine pipeline execution.

Sensitive CDC data should inherit the same masking, row-access, governance, and audit requirements as the authoritative datasets it represents.

---

## 87.38 Warehouse and Cost Design

CDC workloads are often small and frequent.

A poorly configured pipeline can waste compute through excessive task frequency or oversized warehouses.

Cost considerations:

```text
CDC volume
Task frequency
Warehouse size
Execution duration
Idle/resume behavior
Number of dependent transformations
```

Recommended approach:

1. Measure actual rows/run.
2. Measure execution duration.
3. Size the warehouse to meet the freshness SLA.
4. Avoid unnecessarily frequent polling.
5. Use stream-data conditions to avoid unnecessary task work.
6. Reassess when CDC volume changes materially.

Cost optimization must not compromise correctness or recovery capability.

---

## 87.39 Performance Optimization

### Keep CDC transformations incremental

Avoid turning an incremental pipeline into a full-table transformation.

Bad pattern:

```sql
MERGE INTO target
USING (
    SELECT ... FROM very_large_source_table
) ...;
```

when only a small number of records changed.

Better:

```text
Stream/change set
      |
Transform changed rows only
      |
MERGE changed keys only
```

### Reduce multiple events per key

```sql
QUALIFY ROW_NUMBER() OVER (
    PARTITION BY EMPI_ID
    ORDER BY SOURCE_SEQUENCE DESC
) = 1
```

### Monitor target growth

Large target tables may require physical design and query optimization based on actual access patterns. Do not introduce clustering automatically without evidence that it provides benefit.

---

## 87.40 Task Graph Extension

A larger pipeline may require multiple dependent stages.

Example:

```text
ROOT_CDC_TASK
      |
      v
VALIDATE_TASK
      |
      v
L2_MERGE_TASK
      |
      +------> RECONCILIATION_TASK
      |
      +------> DOWNSTREAM_REFRESH_TASK
```

Task graphs should make dependencies explicit rather than relying on unrelated schedules that can race each other.

Each stage should define:

- Input contract
- Success criteria
- Failure behavior
- Retry/recovery behavior
- Monitoring ownership

---

## 87.41 End-to-End Hands-On Lab

### Lab objective

Prove that the pipeline correctly handles insert, update, delete, retry-safe processing, and monitoring.

### Step 1 — Confirm clean baseline

```sql
SELECT * FROM DAP.L1.EMPI_SOURCE ORDER BY EMPI_ID;
SELECT * FROM DAP.L2.EMPI ORDER BY EMPI_ID;
```

### Step 2 — Generate an insert

```sql
INSERT INTO DAP.L1.EMPI_SOURCE
VALUES (
    2001,
    'Test',
    'Insert',
    'ACTIVE',
    CURRENT_TIMESTAMP(),
    'LAB'
);
```

### Step 3 — Generate an update

```sql
UPDATE DAP.L1.EMPI_SOURCE
SET
    STATUS = 'INACTIVE',
    UPDATED_AT = CURRENT_TIMESTAMP()
WHERE EMPI_ID = 1003;
```

### Step 4 — Generate a delete

```sql
DELETE FROM DAP.L1.EMPI_SOURCE
WHERE EMPI_ID = 1004;
```

### Step 5 — Verify pending CDC

```sql
SELECT SYSTEM$STREAM_HAS_DATA('DAP.L1.EMPI_SOURCE_STREAM');
```

Expected:

```text
TRUE
```

### Step 6 — Execute CDC

```sql
CALL DAP.CONTROL.PROCESS_EMPI_CDC();
```

### Step 7 — Validate target

```sql
SELECT *
FROM DAP.L2.EMPI
WHERE EMPI_ID IN (1003, 1004, 2001)
ORDER BY EMPI_ID;
```

Expected:

```text
1003 -> INACTIVE
1004 -> absent
2001 -> ACTIVE
```

### Step 8 — Validate audit

```sql
SELECT *
FROM DAP.CONTROL.CDC_PIPELINE_AUDIT
ORDER BY STARTED_AT DESC
LIMIT 10;
```

### Step 9 — Validate stream consumption

```sql
SELECT SYSTEM$STREAM_HAS_DATA('DAP.L1.EMPI_SOURCE_STREAM');
```

### Step 10 — Reconcile

```sql
SELECT S.EMPI_ID
FROM DAP.L1.EMPI_SOURCE S
FULL OUTER JOIN DAP.L2.EMPI T
    ON S.EMPI_ID = T.EMPI_ID
WHERE S.EMPI_ID IS NULL
   OR T.EMPI_ID IS NULL;
```

Expected for a correctly synchronized current-state model:

```text
0 unexpected differences
```

---

## 87.42 Failure Injection Lab

A production tutorial should test failure behavior, not only the happy path.

### Test 1 — Suspend the task

```sql
ALTER TASK DAP.CONTROL.EMPI_CDC_TASK SUSPEND;
```

Generate source changes and verify they remain pending.

Then resume:

```sql
ALTER TASK DAP.CONTROL.EMPI_CDC_TASK RESUME;
```

Verify recovery.

### Test 2 — Introduce invalid processing logic in a non-production lab

Cause a controlled procedure failure.

Verify:

```text
Audit status = FAILED
Target transaction is not partially committed
Pending changes remain recoverable
```

Restore the procedure and rerun.

### Test 3 — Duplicate logical input

Replay the same logical business state.

Verify the target does not create duplicate business rows.

### Test 4 — Out-of-order change

Where source sequence metadata is available, submit an older version after a newer version.

Verify the older version cannot overwrite the newer target state.

---

## 87.43 Production Acceptance Criteria

The CDC pipeline is ready for production only when all required checks pass.

### Functional

- [ ] Inserts reach target.
- [ ] Updates reach target.
- [ ] Deletes follow the approved delete policy.
- [ ] Multiple events for the same key are deterministic.
- [ ] Duplicate/replayed input does not corrupt target state.
- [ ] Out-of-order handling is defined.

### Reliability

- [ ] Failure does not silently lose pending changes.
- [ ] Recovery procedure is documented and tested.
- [ ] Durable replay source exists for the required recovery horizon.
- [ ] Backfill procedure is defined.
- [ ] Stream staleness risk is monitored.

### Observability

- [ ] Task execution is monitored.
- [ ] Pipeline audit records are retained.
- [ ] Freshness/lag is monitored.
- [ ] Data-quality failures are visible.
- [ ] Reconciliation is implemented.

### Security

- [ ] Least-privilege execution role is used.
- [ ] Sensitive data controls are applied.
- [ ] Administrative roles are not used for normal execution.

### Performance and cost

- [ ] Warehouse sizing is validated.
- [ ] Task frequency matches the SLA.
- [ ] Incremental processing avoids unnecessary full scans.
- [ ] Cost baseline is documented.

---

## 87.44 Production Runbook

### Normal operation

Check:

```text
Task healthy
Last successful run within SLA
Stream not stale
CDC lag acceptable
No unexpected quarantine growth
Reconciliation healthy
```

### Pipeline delayed

```text
1. Check source activity.
2. Check stream pending state.
3. Check task status.
4. Check task history.
5. Check warehouse availability.
6. Check procedure/audit failures.
7. Estimate lag.
8. Recover processing.
9. Reconcile target.
```

### Pipeline failed

```text
1. Stop repeated failure if necessary.
2. Preserve evidence.
3. Identify last successful run.
4. Determine pending/missing change range.
5. Correct root cause.
6. Replay/reprocess safely.
7. Reconcile source and target.
8. Resume automation.
9. Monitor until backlog is cleared.
```

### Stream stale

```text
1. Do not assume no changes were lost.
2. Identify the affected time/change range.
3. Recover from durable source/history.
4. Rebuild current target state as required.
5. Re-establish the stream.
6. Validate reconciliation.
7. Resume automated CDC.
```

---

## 87.45 Production Case Study

Assume an EMPI source receives continuous member updates.

Normal workload:

```text
20 million current records
100,000 changes/hour
95% updates
4% inserts
1% deletes
```

A full-table rebuild every few minutes would repeatedly scan and transform millions of unchanged rows.

Incremental architecture:

```text
EMPI source table
      |
      v
Snowflake stream
      |
      v
CDC task
      |
      v
Deduplicate changed keys
      |
      v
MERGE / DELETE
      |
      v
DAP.L2.EMPI
      |
      +--> reconciliation
      +--> audit
      +--> downstream consumers
```

Incident scenario:

```text
CDC task fails for 45 minutes.
```

Correct operational response:

1. Detect the failure through task/audit monitoring.
2. Confirm the stream remains valid and pending changes exist.
3. Fix the failure.
4. Resume CDC processing.
5. Measure backlog clearance and freshness.
6. Reconcile the affected interval/current state.
7. Confirm downstream consumers are current.

The incident is not resolved merely because the task succeeds again. It is resolved when data correctness and freshness are demonstrated.

---

## 87.46 Anti-Patterns

Avoid these designs.

### Anti-pattern 1

```text
Use UPDATED_AT > last_timestamp with no tie-breaker.
```

Risk: missed records at timestamp boundaries.

### Anti-pattern 2

```text
Advance watermark before target commit.
```

Risk: permanent data loss after failure.

### Anti-pattern 3

```text
Treat every stream DELETE as a business delete.
```

Risk: update pairs can be misinterpreted.

### Anti-pattern 4

```text
MERGE multiple source rows into one target key without deterministic reduction.
```

Risk: incorrect or non-deterministic results.

### Anti-pattern 5

```text
Assume task SUCCESS means data is correct.
```

Risk: logical errors remain undetected.

### Anti-pattern 6

```text
Use stream retention as the only disaster-recovery strategy.
```

Risk: unrecoverable gaps after staleness/retention loss.

### Anti-pattern 7

```text
Run live CDC and historical backfill against the same keys without ordering rules.
```

Risk: older data overwrites newer state.

---

## 87.47 Automation Opportunities

The following checks can be automated:

```text
Task failure detection
Last-success SLA monitoring
Stream staleness warning
Pending-change detection
CDC volume anomaly detection
Quarantine threshold monitoring
Source-target reconciliation
Backlog/lag alerting
Warehouse cost monitoring
Schema drift detection
```

A mature CDC platform should make these controls reusable across pipelines rather than implementing them independently for every dataset.

---

## 87.48 Key Production Principles

### Principle 1

```text
CDC is a correctness problem before it is a performance optimization.
```

### Principle 2

```text
Incremental processing must have a deterministic position or change boundary.
```

### Principle 3

```text
MERGE does not automatically make a pipeline idempotent; source deduplication and ordering still matter.
```

### Principle 4

```text
Deletes, duplicates, and out-of-order events are normal CDC design cases, not edge cases to ignore.
```

### Principle 5

```text
A pipeline is recoverable only when the required source history remains available.
```

### Principle 6

```text
Operational success requires both pipeline execution health and data reconciliation.
```

---

## 87.49 Final Architecture

```text
                   +----------------------+
                   | Upstream Source      |
                   +----------+-----------+
                              |
                              v
                   +----------------------+
                   | DAP.L1.EMPI_SOURCE   |
                   +----------+-----------+
                              |
                              v
                   +----------------------+
                   | Snowflake Stream     |
                   | CDC change set       |
                   +----------+-----------+
                              |
                    SYSTEM$STREAM_HAS_DATA
                              |
                              v
                   +----------------------+
                   | Snowflake Task       |
                   +----------+-----------+
                              |
                              v
                   +----------------------+
                   | CDC Procedure        |
                   | Transaction          |
                   | Deduplication        |
                   | Delete handling      |
                   | MERGE                |
                   +----+------------+----+
                        |            |
                        v            v
              +-------------+   +----------------+
              | DAP.L2.EMPI |   | Audit / Errors |
              +------+------+   +----------------+
                     |
                     v
              +------------------+
              | Reconciliation   |
              | Freshness / Lag  |
              +--------+---------+
                       |
                       v
              +------------------+
              | Consumers        |
              +------------------+
```

---

## 87.50 Chapter Summary

In this project you built a production-oriented Snowflake CDC and incremental pipeline using Streams, Tasks, transactional processing, and `MERGE`.

You covered:

- CDC architecture
- Snowflake Streams
- Stream metadata
- Insert/update/delete handling
- Transactional stream processing
- `MERGE`-based upserts
- Snowflake Tasks
- Audit tables
- Watermark patterns
- Safety windows
- Idempotency
- Duplicate handling
- Out-of-order events
- Hard and soft deletes
- CDC with SCD models
- Stream staleness
- Failure recovery
- Quarantine handling
- Replay
- Backfill
- Reconciliation
- Lag monitoring
- Alerting
- Security
- Cost optimization
- Performance
- Task graphs
- Failure-injection testing
- Production acceptance criteria
- Operational runbooks

The central lesson is:

> A production CDC pipeline is not complete when changed rows merely reach the target. It is complete when change ordering, duplicate handling, deletes, failure recovery, replay, reconciliation, monitoring, security, and operational ownership are all defined and tested.

---

## Chapter 87 Completion Checklist

- [ ] CDC architecture understood
- [ ] Source and target tables created
- [ ] Stream created and validated
- [ ] Stream metadata understood
- [ ] Insert handling tested
- [ ] Update handling tested
- [ ] Delete handling tested
- [ ] CDC procedure implemented
- [ ] Transaction behavior validated
- [ ] `MERGE` logic validated
- [ ] Task created and monitored
- [ ] Audit records validated
- [ ] Idempotency tested
- [ ] Duplicate handling defined
- [ ] Out-of-order handling defined
- [ ] Watermark alternative understood
- [ ] Stream staleness monitoring defined
- [ ] Replay source identified
- [ ] Backfill procedure documented
- [ ] Reconciliation implemented
- [ ] Freshness/lag monitoring implemented
- [ ] Security reviewed
- [ ] Cost/performance baseline reviewed
- [ ] Failure-injection tests completed
- [ ] Production runbook reviewed

**Chapter 87 status: COMPLETE**
