# 21 — Streams + Tasks Production Pipelines

## Overview

Snowflake Streams and Tasks can be combined to build native incremental data pipelines.

Streams provide Change Data Capture. Tasks provide scheduling and orchestration.

Together:

```text
Source Table
     |
     v
Stream
     |
     v
Task
     |
     v
Transformation / MERGE
     |
     v
Target Table
```

This architecture is useful when a pipeline requires explicit control over CDC, scheduling, incremental processing, INSERT/UPDATE/DELETE handling, retries, transactional processing, monitoring, backfill, and recovery.

---

## 1. Production Architecture

A typical production pipeline may look like:

```text
Application / Source
        |
        v
Snowpipe / Snowpipe Streaming
        |
        v
RAW.ORDERS
        |
        v
ORDERS_STREAM
        |
        v
PROCESS_ORDERS_TASK
        |
        v
MERGE
        |
        v
CURATED.ORDERS
```

| Component | Responsibility |
|---|---|
| Snowpipe / Streaming | Ingestion |
| Raw table | Durable landing layer |
| Stream | CDC tracking |
| Task | Orchestration |
| MERGE | Apply incremental changes |
| Curated table | Consumer-ready state |

Keeping these responsibilities separate improves troubleshooting and recovery.

---

## 2. Why Streams + Tasks?

Consider a raw table containing hundreds of millions of rows. A poor pipeline might repeatedly scan the full source and rebuild downstream data.

With CDC:

```text
500,000,000 existing rows
        +
10,000 changed rows
        |
        v
Process the changes
```

This can significantly reduce unnecessary processing.

---

## 3. Create the Source Table

```sql
CREATE OR REPLACE TABLE snowflake_tutorial.raw.orders_pipeline_source (
    order_id          NUMBER,
    customer_id       NUMBER,
    status            VARCHAR,
    order_amount      NUMBER(12,2),
    source_updated_at TIMESTAMP_NTZ
);

INSERT INTO snowflake_tutorial.raw.orders_pipeline_source
VALUES
    (1001, 501, 'NEW', 100.00, CURRENT_TIMESTAMP()),
    (1002, 502, 'NEW', 200.00, CURRENT_TIMESTAMP()),
    (1003, 503, 'NEW', 300.00, CURRENT_TIMESTAMP());
```

---

## 4. Create the Target Table

```sql
CREATE OR REPLACE TABLE snowflake_tutorial.raw.orders_pipeline_target (
    order_id          NUMBER,
    customer_id       NUMBER,
    status            VARCHAR,
    order_amount      NUMBER(12,2),
    source_updated_at TIMESTAMP_NTZ,
    processed_at      TIMESTAMP_NTZ
);
```

The target should have a clear business key. Here, ORDER_ID is used for incremental synchronization.

---

## 5. Create the Stream

```sql
CREATE OR REPLACE STREAM snowflake_tutorial.raw.orders_pipeline_stream
ON TABLE snowflake_tutorial.raw.orders_pipeline_source;

SHOW STREAMS
IN SCHEMA snowflake_tutorial.raw;

DESC STREAM snowflake_tutorial.raw.orders_pipeline_stream;
```

---

## 6. Generate CDC Changes

Insert:

```sql
INSERT INTO snowflake_tutorial.raw.orders_pipeline_source
VALUES
    (1004, 504, 'NEW', 400.00, CURRENT_TIMESTAMP());
```

Update:

```sql
UPDATE snowflake_tutorial.raw.orders_pipeline_source
SET
    status = 'COMPLETE',
    source_updated_at = CURRENT_TIMESTAMP()
WHERE order_id = 1002;
```

Delete:

```sql
DELETE FROM snowflake_tutorial.raw.orders_pipeline_source
WHERE order_id = 1003;
```

Inspect the stream:

```sql
SELECT
    order_id,
    customer_id,
    status,
    order_amount,
    source_updated_at,
    METADATA$ACTION,
    METADATA$ISUPDATE,
    METADATA$ROW_ID
FROM snowflake_tutorial.raw.orders_pipeline_stream;
```

---

## 7. Understand the CDC Records

The stream can represent INSERT, DELETE, and UPDATE changes.

An update is represented through change records corresponding to the old and new row states.

```text
UPDATE order 1002
       |
       +---- DELETE old version
       |
       +---- INSERT new version
```

This behavior must be considered when building downstream MERGE logic.

---

## 8. Initial Load vs CDC

A production pipeline should explicitly distinguish the initial load from incremental CDC.

```text
Create target
     |
     v
Initial bulk load
     |
     v
Establish CDC
     |
     v
Incremental processing
```

The exact sequencing depends on consistency requirements and source activity.

Do not casually create a stream after a long-running initial load without understanding what change window must be captured.

---

## 9. Initial Load Example

```sql
INSERT INTO snowflake_tutorial.raw.orders_pipeline_target
SELECT
    order_id,
    customer_id,
    status,
    order_amount,
    source_updated_at,
    CURRENT_TIMESTAMP()
FROM snowflake_tutorial.raw.orders_pipeline_source;
```

In a real production migration, initial-load and CDC-cutover sequencing must be carefully designed to avoid missing rows, duplicate rows, incorrect updates, and lost deletes.

---

## 10. Stream Has Data Condition

```sql
SELECT SYSTEM$STREAM_HAS_DATA(
    'SNOWFLAKE_TUTORIAL.RAW.ORDERS_PIPELINE_STREAM'
);
```

This function can be used in a Task condition.

```text
Task scheduled
     |
     v
Stream has data?
   /       \
 No        Yes
 |          |
Skip       Execute
```

---

## 11. Basic Production Task

```sql
CREATE OR REPLACE TASK snowflake_tutorial.raw.orders_pipeline_task
    WAREHOUSE = tutorial_wh
    SCHEDULE = '5 MINUTE'
    WHEN SYSTEM$STREAM_HAS_DATA(
        'SNOWFLAKE_TUTORIAL.RAW.ORDERS_PIPELINE_STREAM'
    )
AS
-- incremental processing SQL
;
```

The processing SQL should be designed carefully before the task is resumed.

---

## 12. INSERT-Only Pipeline

If the source is truly append-only, processing can be simple.

```sql
INSERT INTO target_table
SELECT
    ...
FROM source_stream
WHERE METADATA$ACTION = 'INSERT'
  AND METADATA$ISUPDATE = FALSE;
```

This pattern is suitable only when updates and deletes are not required.

---

## 13. Full CDC Pipeline

A full CDC pipeline must account for INSERT, UPDATE, and DELETE.

```text
Source state
    |
    v
CDC changes
    |
    v
Target state converges
    |
    v
Target reflects source
```

This requires correct business-key and DML logic.

---

## 14. MERGE Concept

```text
Stream
  |
  v
Normalize CDC records
  |
  v
MERGE
  |
  v
Target
```

Conceptually:

```sql
MERGE INTO target t
USING changes s
ON t.order_id = s.order_id
WHEN MATCHED THEN ...
WHEN NOT MATCHED THEN ...
```

Chapter 22 covers MERGE and UPSERT behavior in depth. This chapter focuses on integrating that operation into a production pipeline.

---

## 15. Why CDC Normalization Matters

A raw stream can contain multiple records related to the same business key. A production pipeline must determine the desired final state.

Possible strategies include using the latest source state, deduplicating by business key, preserving every event in a history model, or processing changes sequentially.

The correct strategy depends on the data model.

---

## 16. Current-State vs History Pipelines

### Current-State Model

The target represents the latest known state.

### History Model

The target preserves meaningful changes over time.

Do not mix these models accidentally.

---

## 17. Idempotency

A production pipeline should answer:

```text
What happens if processing runs twice?
```

A non-idempotent design can create duplicate rows, double-counted metrics, or repeated side effects.

A robust design uses mechanisms such as business keys, MERGE, deduplication, transactions, and CDC offsets.

---

## 18. Transactional Consumption

One of the major benefits of Streams is that CDC processing can be tied to transactional DML.

```text
Read stream
     |
     v
Apply changes
     |
     v
Commit
     |
     v
Advance stream offset
```

If processing fails before commit:

```text
Read stream
     |
     v
Apply changes
     |
     X
Failure
     |
     v
Rollback
```

The changes should not be treated as successfully processed.

---

## 19. Never Separate Consumption from Success Tracking

Avoid designs where changes are marked processed before the target update succeeds.

Consumption and target changes should be part of a consistent transactional design whenever possible.

---

## 20. Create the Processing Task

For a simplified insert-focused example:

```sql
CREATE OR REPLACE TASK snowflake_tutorial.raw.orders_pipeline_task
    WAREHOUSE = tutorial_wh
    SCHEDULE = '5 MINUTE'
    WHEN SYSTEM$STREAM_HAS_DATA(
        'SNOWFLAKE_TUTORIAL.RAW.ORDERS_PIPELINE_STREAM'
    )
AS
INSERT INTO snowflake_tutorial.raw.orders_pipeline_target
SELECT
    order_id,
    customer_id,
    status,
    order_amount,
    source_updated_at,
    CURRENT_TIMESTAMP()
FROM snowflake_tutorial.raw.orders_pipeline_stream
WHERE METADATA$ACTION = 'INSERT'
  AND METADATA$ISUPDATE = FALSE;
```

This demonstrates the orchestration pattern. A production full-CDC implementation would replace this simplified INSERT with appropriate synchronization logic.

---

## 21. Validate Before Resume

```sql
DESC TASK snowflake_tutorial.raw.orders_pipeline_task;
```

Check schedule, warehouse, WHEN condition, SQL definition, owner, and privileges. Also manually validate the processing SQL.

---

## 22. Resume the Task

```sql
ALTER TASK snowflake_tutorial.raw.orders_pipeline_task
RESUME;

SHOW TASKS
IN SCHEMA snowflake_tutorial.raw;
```

Never assume a deployment is active merely because CREATE TASK succeeded.

---

## 23. Monitor Task Execution

```sql
SELECT *
FROM TABLE(
    INFORMATION_SCHEMA.TASK_HISTORY(
        TASK_NAME => 'ORDERS_PIPELINE_TASK',
        SCHEDULED_TIME_RANGE_START =>
            DATEADD('hour', -4, CURRENT_TIMESTAMP())
    )
)
ORDER BY SCHEDULED_TIME DESC;
```

Review scheduled time, state, query ID, start time, completion time, and error.

---

## 24. Monitor Stream Backlog

```sql
SELECT SYSTEM$STREAM_HAS_DATA(
    'SNOWFLAKE_TUTORIAL.RAW.ORDERS_PIPELINE_STREAM'
);

SELECT
    METADATA$ACTION,
    METADATA$ISUPDATE,
    COUNT(*)
FROM snowflake_tutorial.raw.orders_pipeline_stream
GROUP BY
    METADATA$ACTION,
    METADATA$ISUPDATE;
```

This provides a basic view of pending CDC work.

---

## 25. Monitor Target Freshness

Task success alone is not enough.

```sql
SELECT MAX(processed_at)
FROM snowflake_tutorial.raw.orders_pipeline_target;

SELECT MAX(source_updated_at)
FROM snowflake_tutorial.raw.orders_pipeline_source;
```

A healthy pipeline should maintain freshness within the required SLA.

---

## 26. Three-Layer Monitoring

Production monitoring should cover source, CDC, consumer, and target.

Monitor source timestamps and arrival rates; stream backlog and staleness; task state, failures, duration, and last success; and target timestamps, row counts, business validation, and freshness.

---

## 27. Why Task Success Is Not Enough

```text
Snowpipe stopped
      |
      v
No new source rows
      |
      v
Stream empty
      |
      v
Task skips successfully
```

The task system may look healthy while business data is stale.

Task health is not the same as pipeline health. Always monitor end-to-end freshness.

---

## 28. Failure Scenario — Task Fails

When the stream has changes but task SQL fails:

1. Capture task history.
2. Capture query ID.
3. Capture exact error.
4. Do not recreate the stream.
5. Confirm stream data remains available.
6. Correct the SQL or dependency.
7. Test safely.
8. Resume/retry processing.
9. Validate target.

---

## 29. Failure Scenario — Warehouse Problem

```sql
SHOW WAREHOUSES LIKE 'TUTORIAL_WH';
```

Investigate warehouse state, queueing, concurrency, size, auto-resume, and credit/resource restrictions.

Do not modify the stream because the warehouse is unhealthy.

---

## 30. Failure Scenario — Permission Change

A pipeline can fail after role changes, revoked grants, ownership transfers, object replacement, or schema deployment.

Investigate the task owner and privileges on source, stream, target, warehouse, database, schema, and procedures.

Avoid solving privilege incidents with unnecessarily broad grants.

---

## 31. Failure Scenario — Schema Change

```text
Source column renamed
      |
      v
Task SQL still references old column
      |
      v
Task failure
      |
      v
Stream backlog
```

Production schema changes should account for downstream Streams, Tasks, procedures, views, and consumers.

---

## 32. Failure Scenario — Stream Backlog Growing

If source writes continue but consumption slows, investigate task frequency, task failures, runtime, warehouse capacity, SQL performance, data volume, change volume, and MERGE performance.

Do not automatically increase task frequency. If each run is already slow, more frequent scheduling may worsen contention.

---

## 33. Failure Scenario — Stream Approaching Staleness

```sql
SHOW STREAMS;
```

Review STALE and STALE_AFTER.

Determine how much data is pending, why the consumer is not processing, whether it can recover before staleness, and what the backfill plan is.

Do not wait until the stream becomes stale before designing recovery.

---

## 34. Stale Stream Recovery

```text
STOP
 |
 v
Do not blindly recreate
 |
 v
Determine last successful target state
 |
 v
Determine missing source range
 |
 v
Backfill
 |
 v
Validate
 |
 v
Re-establish CDC
```

Recreating the stream without reconstructing missing changes can silently lose data.

---

## 35. Backfill Strategy

Every production CDC pipeline should have a backfill mechanism independent of normal incremental processing.

```text
Normal path:
Stream → Task → Target

Recovery path:
Source history → bounded query → Target repair
```

A backfill should be bounded.

```sql
WHERE source_updated_at >= :recovery_start
  AND source_updated_at <  :recovery_end
```

Do not perform an unbounded full-table replay during an incident unless required.

---

## 36. Establish the Recovery Window

Find the last known-good target timestamp, first missing source timestamp, and current source timestamp.

Then define Recovery Start and Recovery End and preserve them in incident notes.

---

## 37. Replay Safety

Before replaying, determine whether already processed rows can be replayed safely.

Good replay designs use MERGE, business keys, deterministic transformations, deduplication, and bounded time windows.

---

## 38. Duplicate Prevention

Common duplicate causes include manual task execution, replay, retries, non-idempotent INSERT, overlapping pipelines, and source duplicates.

Protect the target using business-aware logic. Do not rely only on the assumption that a task executes once.

---

## 39. Late-Arriving Data

Data may arrive after the expected processing window.

Distinguish event time, ingestion time, and processing time. This becomes especially important during replay.

---

## 40. Out-of-Order Changes

A distributed source may deliver changes out of order.

Where relevant, use source version, event timestamp, sequence number, or change identifier to determine the correct state.

---

## 41. Poison Records

A malformed or unexpected record should not necessarily block an entire production pipeline indefinitely.

Possible strategies include validation, quarantine tables, dead-letter tables, error logging, and controlled skip policies.

Any skip policy must be observable and auditable.

---

## 42. Quarantine Table Example

```sql
CREATE OR REPLACE TABLE snowflake_tutorial.raw.orders_quarantine (
    order_id          NUMBER,
    raw_payload       VARIANT,
    failure_reason    VARCHAR,
    quarantined_at    TIMESTAMP_NTZ
);
```

Rejected data should not silently disappear.

---

## 43. Audit Columns

Useful operational columns include SOURCE_UPDATED_AT, INGESTED_AT, PROCESSED_AT, PIPELINE_RUN_ID, and SOURCE_SYSTEM.

These improve freshness analysis, incident investigation, replay, lineage, and reconciliation.

---

## 44. Reconciliation

A pipeline should periodically verify more than execution success.

Possible checks include source vs target counts, key coverage, missing business keys, duplicate keys, aggregate totals, freshness, and NULL anomalies.

For filtered or historical models, use business-specific reconciliation.

---

## 45. Reconciliation by Business Key

```sql
SELECT s.order_id
FROM snowflake_tutorial.raw.orders_pipeline_source s
LEFT JOIN snowflake_tutorial.raw.orders_pipeline_target t
    ON s.order_id = t.order_id
WHERE t.order_id IS NULL;
```

This can identify source keys missing from the target. Reverse reconciliation can identify unexpected target keys.

---

## 46. Task Frequency Design

Choose frequency based on freshness SLA, change rate, processing runtime, warehouse startup behavior, cost, and concurrency.

A one-minute schedule may provide little additional value when the business SLA is fifteen minutes and processing already takes several minutes.

---

## 47. Workload Isolation

Avoid running every pipeline on the same warehouse without understanding contention.

Possible architecture:

```text
INGEST_WH
TRANSFORM_WH
BI_WH
```

Isolation can prevent heavy BI workloads from delaying CDC processing.

---

## 48. Cost Optimization

CDC can reduce processing cost by avoiding unnecessary full-table work.

Watch for very frequent schedules, long-running MERGE operations, oversized warehouses, missing WHEN conditions, repeated empty processing, poor pruning, and excessive replay.

Optimize the pipeline rather than focusing only on warehouse size.

---

## 49. Deployment Strategy

```text
Create/alter objects
      |
      v
Validate SQL
      |
      v
Validate permissions
      |
      v
Validate stream
      |
      v
Validate task
      |
      v
Test controlled changes
      |
      v
Resume
      |
      v
Monitor
```

Do not deploy and immediately leave the pipeline unattended.

---

## 50. Production Readiness Checklist

Before enabling:

- Source identified
- Business key identified
- Initial-load strategy documented
- Stream created
- Stream retention/staleness understood
- Task created
- Task schedule documented
- Warehouse selected
- WHEN condition validated
- CDC logic validated
- INSERT behavior validated
- UPDATE behavior validated
- DELETE behavior validated
- Idempotency tested
- Replay tested
- Backfill procedure documented
- Monitoring configured
- Freshness alert configured
- Task failure alert configured
- Reconciliation defined
- Ownership documented
- Runbook documented

---

## 51. Production Troubleshooting Runbook

When the pipeline becomes stale:

1. Confirm the symptom and target freshness.
2. Check whether source data is arriving.
3. Check upstream Snowpipe or Snowpipe Streaming if applicable.
4. Check stream state and whether it contains data.
5. Check task state.
6. Check task history.
7. Capture task, query ID, timestamp, and exact error.
8. Check warehouse health and queueing.
9. Check permissions.
10. Check schema changes.
11. Determine backlog.
12. Check staleness risk and STALE_AFTER.
13. Correct the root cause without destroying evidence.
14. Recover processing safely.
15. Backfill using a bounded recovery window if required.
16. Reconcile source and target.
17. Confirm freshness SLA has recovered.

---

## 52. Hands-On Production Lab

### Objective

Build and operate a Stream + Task incremental pipeline.

### Step 1 — Create source

```sql
CREATE OR REPLACE TABLE snowflake_tutorial.raw.cdc_orders_lab (
    order_id       NUMBER,
    customer_id    NUMBER,
    status         VARCHAR,
    amount         NUMBER(12,2),
    source_ts      TIMESTAMP_NTZ
);
```

### Step 2 — Create target

```sql
CREATE OR REPLACE TABLE snowflake_tutorial.raw.cdc_orders_target (
    order_id       NUMBER,
    customer_id    NUMBER,
    status         VARCHAR,
    amount         NUMBER(12,2),
    source_ts      TIMESTAMP_NTZ,
    processed_at   TIMESTAMP_NTZ
);
```

### Step 3 — Seed source

```sql
INSERT INTO snowflake_tutorial.raw.cdc_orders_lab
VALUES
    (1, 101, 'NEW', 100.00, CURRENT_TIMESTAMP()),
    (2, 102, 'NEW', 200.00, CURRENT_TIMESTAMP());
```

### Step 4 — Perform initial load

```sql
INSERT INTO snowflake_tutorial.raw.cdc_orders_target
SELECT
    order_id,
    customer_id,
    status,
    amount,
    source_ts,
    CURRENT_TIMESTAMP()
FROM snowflake_tutorial.raw.cdc_orders_lab;
```

### Step 5 — Create stream

```sql
CREATE OR REPLACE STREAM snowflake_tutorial.raw.cdc_orders_stream
ON TABLE snowflake_tutorial.raw.cdc_orders_lab;
```

### Step 6 — Generate a new record

```sql
INSERT INTO snowflake_tutorial.raw.cdc_orders_lab
VALUES
    (3, 103, 'NEW', 300.00, CURRENT_TIMESTAMP());
```

### Step 7 — Inspect stream

```sql
SELECT
    *,
    METADATA$ACTION,
    METADATA$ISUPDATE,
    METADATA$ROW_ID
FROM snowflake_tutorial.raw.cdc_orders_stream;
```

### Step 8 — Create task

```sql
CREATE OR REPLACE TASK snowflake_tutorial.raw.cdc_orders_task
    WAREHOUSE = tutorial_wh
    SCHEDULE = '5 MINUTE'
    WHEN SYSTEM$STREAM_HAS_DATA(
        'SNOWFLAKE_TUTORIAL.RAW.CDC_ORDERS_STREAM'
    )
AS
INSERT INTO snowflake_tutorial.raw.cdc_orders_target
SELECT
    order_id,
    customer_id,
    status,
    amount,
    source_ts,
    CURRENT_TIMESTAMP()
FROM snowflake_tutorial.raw.cdc_orders_stream
WHERE METADATA$ACTION = 'INSERT'
  AND METADATA$ISUPDATE = FALSE;
```

### Step 9 — Inspect and resume task

```sql
DESC TASK snowflake_tutorial.raw.cdc_orders_task;

ALTER TASK snowflake_tutorial.raw.cdc_orders_task
RESUME;
```

### Step 10 — Validate target

```sql
SELECT *
FROM snowflake_tutorial.raw.cdc_orders_target
ORDER BY order_id;
```

### Step 11 — Inspect history

```sql
SELECT *
FROM TABLE(
    INFORMATION_SCHEMA.TASK_HISTORY(
        TASK_NAME => 'CDC_ORDERS_TASK',
        SCHEDULED_TIME_RANGE_START =>
            DATEADD('hour', -1, CURRENT_TIMESTAMP())
    )
)
ORDER BY SCHEDULED_TIME DESC;
```

### Step 12 — Generate another change

```sql
INSERT INTO snowflake_tutorial.raw.cdc_orders_lab
VALUES
    (4, 104, 'NEW', 400.00, CURRENT_TIMESTAMP());
```

Confirm the pipeline processes it.

### Step 13 — Test failure handling

In a non-production environment only:

1. Suspend the task.
2. Generate source changes.
3. Confirm the stream accumulates changes.
4. Inspect the stream.
5. Resume the task.
6. Confirm backlog is processed.
7. Validate target completeness.

### Step 14 — Suspend after lab

```sql
ALTER TASK snowflake_tutorial.raw.cdc_orders_task
SUSPEND;
```

---

## 53. Acceptance Criteria

The chapter is complete when you can:

- design a Streams + Tasks pipeline
- distinguish ingestion, CDC, orchestration, and target processing
- design initial-load and incremental phases
- inspect stream CDC metadata
- use SYSTEM$STREAM_HAS_DATA
- create conditional Tasks
- understand transactional stream consumption
- explain idempotency
- design current-state vs history targets
- monitor source, stream, task, and target
- detect growing backlog
- detect staleness risk
- investigate task failures
- recover from compute failures
- recover from permission failures
- recover from schema changes
- design bounded backfills
- safely replay data
- handle late-arriving data
- reason about out-of-order changes
- design quarantine handling
- reconcile source and target
- optimize schedule and compute
- operate the pipeline using a production runbook

---

## Key Takeaways

Streams + Tasks provide a powerful Snowflake-native CDC architecture:

```text
Source
  |
  v
Stream
  |
  v
Task
  |
  v
Incremental DML
  |
  v
Target
```

A production pipeline requires more than creating those two objects. Reliability depends on CDC correctness, transactions, idempotency, monitoring, freshness, backfill, replay, and reconciliation.

The most important operational principle is:

```text
Never destroy or recreate CDC state
during an incident until you understand
the unprocessed data window.
```

When a pipeline fails:

```text
Preserve evidence
     |
     v
Find last known-good state
     |
     v
Determine missing window
     |
     v
Correct root cause
     |
     v
Replay safely
     |
     v
Reconcile
     |
     v
Confirm freshness
```

The next chapter is **Chapter 22 — MERGE, UPSERT & Incremental Processing**.
