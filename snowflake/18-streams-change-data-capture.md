# 18 — Streams & Change Data Capture

## Overview

Snowflake Streams provide Change Data Capture (CDC) capabilities for tracking changes made to tables and other supported objects.

Instead of repeatedly processing an entire table:

```text
Source Table
     |
     v
Scan Everything
     |
     v
Transformation
```

a stream allows a pipeline to work with changes:

```text
Source Table
     |
     v
INSERT / UPDATE / DELETE
     |
     v
Stream
     |
     v
Changed Rows
     |
     v
Incremental Processing
```

Streams are fundamental building blocks for incremental Snowflake data pipelines.

Typical use cases include incremental ETL/ELT, CDC processing, synchronization between tables, audit pipelines, incremental aggregates, downstream data marts, event-driven processing, and Streams + Tasks pipelines.

---

## 1. What Is a Snowflake Stream?

A stream records change-tracking information for a source object.

```sql
CREATE OR REPLACE STREAM orders_stream
ON TABLE raw.orders;
```

Query it:

```sql
SELECT *
FROM orders_stream;
```

A stream is not a duplicate copy of the source table. It represents change information relative to an offset maintained by Snowflake.

---

## 2. CDC Concept

Suppose a table initially contains orders 1001, 1002, and 1003. After a stream is created, order 1004 is inserted, 1002 is updated, and 1003 is deleted.

Instead of rescanning every order, the stream exposes the changes required for incremental processing.

```text
RAW.ORDERS
    |
    +---- INSERT 1004
    +---- UPDATE 1002
    +---- DELETE 1003
    |
    v
ORDERS_STREAM
```

---

## 3. Create a Lab Environment

```sql
CREATE DATABASE IF NOT EXISTS snowflake_tutorial;
CREATE SCHEMA IF NOT EXISTS snowflake_tutorial.raw;

CREATE OR REPLACE TABLE snowflake_tutorial.raw.orders (
    order_id       NUMBER,
    customer_id    NUMBER,
    status         VARCHAR,
    order_amount   NUMBER(12,2),
    updated_at     TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP()
);

INSERT INTO snowflake_tutorial.raw.orders
    (order_id, customer_id, status, order_amount)
VALUES
    (1001, 501, 'NEW', 100.00),
    (1002, 502, 'NEW', 250.00),
    (1003, 503, 'NEW', 175.00);

SELECT *
FROM snowflake_tutorial.raw.orders
ORDER BY order_id;
```

---

## 4. Create a Stream

```sql
CREATE OR REPLACE STREAM snowflake_tutorial.raw.orders_stream
ON TABLE snowflake_tutorial.raw.orders;

SHOW STREAMS IN SCHEMA snowflake_tutorial.raw;

DESC STREAM snowflake_tutorial.raw.orders_stream;

SELECT *
FROM snowflake_tutorial.raw.orders_stream;
```

Immediately after creation there may be no changes for the stream to return.

---

## 5. Generate an INSERT

```sql
INSERT INTO snowflake_tutorial.raw.orders
    (order_id, customer_id, status, order_amount)
VALUES
    (1004, 504, 'NEW', 325.00);

SELECT *
FROM snowflake_tutorial.raw.orders_stream;
```

In addition to source columns, Snowflake exposes stream metadata columns.

---

## 6. Stream Metadata Columns

Important metadata includes:

```text
METADATA$ACTION
METADATA$ISUPDATE
METADATA$ROW_ID
```

```sql
SELECT
    order_id,
    customer_id,
    status,
    order_amount,
    METADATA$ACTION,
    METADATA$ISUPDATE,
    METADATA$ROW_ID
FROM snowflake_tutorial.raw.orders_stream;
```

---

## 7. METADATA$ACTION

`METADATA$ACTION` identifies the row-level action represented by the stream.

Common values are `INSERT` and `DELETE`.

An update requires special interpretation because change tracking represents the old and new row versions.

---

## 8. METADATA$ISUPDATE

`METADATA$ISUPDATE` helps identify records participating in an update.

Conceptually:

```text
UPDATE
  |
  +---- DELETE old row
  |
  +---- INSERT new row
```

Both records are associated with update semantics. This matters when implementing downstream `MERGE` operations.

---

## 9. Test an UPDATE

```sql
UPDATE snowflake_tutorial.raw.orders
SET
    status = 'PROCESSED',
    updated_at = CURRENT_TIMESTAMP()
WHERE order_id = 1002;

SELECT
    order_id,
    status,
    METADATA$ACTION,
    METADATA$ISUPDATE,
    METADATA$ROW_ID
FROM snowflake_tutorial.raw.orders_stream
ORDER BY order_id;
```

Study how the updated row is represented before building production CDC logic.

---

## 10. Test a DELETE

```sql
DELETE FROM snowflake_tutorial.raw.orders
WHERE order_id = 1003;

SELECT
    order_id,
    status,
    METADATA$ACTION,
    METADATA$ISUPDATE,
    METADATA$ROW_ID
FROM snowflake_tutorial.raw.orders_stream
ORDER BY order_id;
```

You can now distinguish inserts, deletes, and changes associated with updates.

---

## 11. Stream Offset

A stream tracks changes relative to its current position.

```text
Table Timeline

T0 -------- T1 -------- T2 -------- T3
             ^
             |
       Stream Offset
```

Changes after the offset are available to the stream. After qualifying DML consumes the stream, its offset advances.

---

## 12. Querying vs Consuming a Stream

A simple:

```sql
SELECT *
FROM snowflake_tutorial.raw.orders_stream;
```

does not by itself consume the stream.

You can query it repeatedly while investigating.

The stream offset advances when the stream participates in a committed DML transaction that consumes its change records.

This distinction is extremely useful during troubleshooting.

---

## 13. Consume Stream Data

Create a target table:

```sql
CREATE OR REPLACE TABLE snowflake_tutorial.raw.orders_processed (
    order_id       NUMBER,
    customer_id    NUMBER,
    status         VARCHAR,
    order_amount   NUMBER(12,2),
    updated_at     TIMESTAMP_NTZ
);
```

For a simple insert-only example:

```sql
INSERT INTO snowflake_tutorial.raw.orders_processed
SELECT
    order_id,
    customer_id,
    status,
    order_amount,
    updated_at
FROM snowflake_tutorial.raw.orders_stream
WHERE METADATA$ACTION = 'INSERT'
  AND METADATA$ISUPDATE = FALSE;
```

After the transaction commits:

```sql
SELECT *
FROM snowflake_tutorial.raw.orders_stream;
```

The offset should reflect the consumed changes.

---

## 14. Check Whether a Stream Has Data

Snowflake provides `SYSTEM$STREAM_HAS_DATA`.

```sql
SELECT SYSTEM$STREAM_HAS_DATA(
    'SNOWFLAKE_TUTORIAL.RAW.ORDERS_STREAM'
);
```

This indicates whether the stream might contain change data and is especially useful with Snowflake Tasks.

---

## 15. Incremental Pipeline Pattern

```text
Source
   |
   v
RAW TABLE
   |
   v
STREAM
   |
   v
Incremental Transformation
   |
   v
CURATED TABLE
```

Instead of repeatedly scanning an entire large source table, a pipeline can process the stream.

---

## 16. CDC with MERGE

Streams are frequently combined with `MERGE`.

```text
RAW.ORDERS
    |
    v
ORDERS_STREAM
    |
    v
MERGE
    |
    v
CURATED.ORDERS
```

```sql
CREATE OR REPLACE TABLE snowflake_tutorial.raw.orders_curated (
    order_id       NUMBER,
    customer_id    NUMBER,
    status         VARCHAR,
    order_amount   NUMBER(12,2),
    updated_at     TIMESTAMP_NTZ
);
```

Production merge logic must carefully handle inserts, updates, deletes, duplicate source records, and multiple changes to the same business key.

`MERGE` and UPSERT patterns are covered in detail in Chapter 22.

---

## 17. Standard Streams

A standard stream tracks INSERT, UPDATE, and DELETE changes.

```sql
CREATE STREAM orders_stream
ON TABLE orders;
```

Use standard streams when deletes and updates matter.

---

## 18. Append-Only Streams

An append-only stream focuses on inserted rows.

```sql
CREATE STREAM events_stream
ON TABLE events
APPEND_ONLY = TRUE;
```

This is useful for naturally insert-only workloads such as immutable events, logs, telemetry, and some ingestion pipelines.

If update/delete tracking is required, use standard CDC semantics.

---

## 19. Insert-Only Streams

Snowflake also has stream behavior associated with supported external-table scenarios where newly inserted files/rows are tracked differently from standard table CDC.

Understand the stream type and source object before assuming update/delete semantics are available.

```sql
SHOW STREAMS;
DESC STREAM <stream_name>;
```

---

## 20. Multiple Consumers

Create multiple streams on the same source when different consumers require independent progress.

```text
                 RAW.ORDERS
                    |
          +---------+---------+
          |                   |
          v                   v
 ANALYTICS_STREAM       AUDIT_STREAM
          |                   |
          v                   v
 Analytics Pipeline      Audit Pipeline
```

Each stream maintains its own offset.

Do not make independent applications compete for one stream unless that behavior is explicitly intended.

---

## 21. Stream Staleness

Streams cannot retain unconsumed changes indefinitely.

If a stream is not consumed within the relevant retention window, it can become stale. Once stale, it can no longer reliably provide the required historical change set.

A stale stream can break an incremental pipeline.

---

## 22. Monitor Stream Staleness

```sql
SHOW STREAMS;
```

Review properties such as `STALE` and `STALE_AFTER`.

Operational monitoring should identify streams approaching their stale boundary before they become unusable.

---

## 23. Why Streams Become Stale

Typical causes include:

- task disabled for an extended period
- pipeline failure
- consumer application outage
- maintenance lasting too long
- stream created but never consumed
- source retention insufficient for consumer delay

The stream is often exposing a failure in the downstream consumption process.

---

## 24. Recovering from a Stale Stream

Do not blindly recreate a stale stream and assume no data was lost.

First determine:

- What was the last successfully processed change?
- What source history remains available?
- What time range is missing?
- Can the missing range be reconstructed?
- Will replay introduce duplicates?

Recovery may require determining the missing range, backfilling it, validating completeness, and then recreating/resuming CDC.

---

## 25. Streams and Transactions

Production pipelines should treat:

```text
Read stream
+
Transform
+
Write target
+
Advance stream
```

as one logical processing unit.

A failed transaction should not be treated as successfully processed data.

---

## 26. Stream Processing Failure

If processing fails and the transaction rolls back, the desired behavior is that the changes remain available rather than being treated as successfully consumed.

Always test failure behavior in a non-production environment.

---

## 27. Streams + Tasks

Streams become especially powerful when paired with Tasks.

```text
Source Table
     |
     v
Stream
     |
     v
SYSTEM$STREAM_HAS_DATA
     |
     v
Task
     |
     v
MERGE / INSERT
     |
     v
Target Table
```

Tasks are covered in the next chapter.

---

## 28. CDC Architecture Example

```text
Application
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
TASK
     |
     v
MERGE
     |
     v
CURATED.ORDERS
```

Responsibilities:

```text
Snowpipe        → ingestion
Raw table       → landing
Stream          → change tracking
Task            → orchestration
MERGE           → incremental application
Curated table   → consumer-ready state
```

---

## 29. Monitoring Streams

Production monitoring should include stream existence, stream type, staleness, `STALE_AFTER`, pending changes, consumer/task status, last successful processing time, and pipeline freshness.

Checking only whether a stream object exists is insufficient.

---

## 30. Data Freshness

```sql
SELECT
    MAX(updated_at)
FROM snowflake_tutorial.raw.orders_curated;
```

Compare source freshness with target freshness. If source data is current but the target is stale, investigate the CDC pipeline.

---

## 31. Troubleshooting — Stream Has No Rows

If changes were expected but the stream returns nothing, check:

1. Did the source table actually change?
2. Were changes made after stream creation/current offset?
3. Did another DML transaction already consume the stream?
4. Are you querying the expected stream?
5. Is the stream stale?
6. Are you in the correct database/schema?
7. Did the source operation result in a net change visible to the stream?

Do not immediately recreate the stream.

---

## 32. Troubleshooting — Stream Keeps Growing

If pending changes continue accumulating, investigate the consumer.

Check task state, task failures, warehouse availability, SQL errors, permissions, processing duration, processing frequency, and data-volume increases.

A growing stream backlog is often a downstream processing problem.

---

## 33. Troubleshooting — Duplicate Target Rows

If duplicates appear downstream, investigate business keys, MERGE conditions, multiple source changes, replay behavior, task retries, and source duplicates.

Do not assume the stream itself created the business-level duplicate.

---

## 34. Troubleshooting — Missing Changes

Investigate stream offset, stream staleness, retention, consumer history, task history, source transaction timing, and replay/backfill activity.

Establish the last known-good processing point before changing the stream.

---

## 35. Operational Runbook

When a Streams-based CDC pipeline stops progressing:

1. Confirm the source table is receiving changes.
2. Identify the expected stream.
3. Run `SHOW STREAMS`.
4. Check `STALE` and `STALE_AFTER`.
5. Query the stream.
6. Run `SYSTEM$STREAM_HAS_DATA`.
7. Identify the consumer.
8. Check task/application state.
9. Review processing errors.
10. Verify target-table freshness.
11. Determine the last successful processing point.
12. Measure the missing/backlog window.
13. Protect existing evidence before recreating anything.
14. Determine whether backfill is required.
15. Validate duplicate/idempotency handling.
16. Recover the consumer.
17. Confirm the stream begins advancing.
18. Validate source-to-target completeness.

---

## 36. Production Best Practices

Use:

- one stream per independent consumer
- meaningful stream names
- explicit business keys
- staleness monitoring
- target freshness monitoring
- transactional processing
- replay/backfill procedures
- idempotent downstream logic
- raw → CDC → curated separation
- `SYSTEM$STREAM_HAS_DATA` for conditional processing
- retention planning

Avoid:

- treating a stream as a permanent event archive
- sharing one stream among unrelated consumers
- ignoring `STALE_AFTER`
- recreating a stale stream before identifying missing data
- assuming SELECT consumes a stream
- assuming Streams automatically solve duplicates
- running full-table transformations when CDC is sufficient
- operating CDC without a backfill strategy

---

## 37. Hands-On Lab

### Objective

Create a Snowflake Stream and observe INSERT, UPDATE, DELETE, and stream-consumption behavior.

### Step 1 — Create source

```sql
CREATE OR REPLACE TABLE snowflake_tutorial.raw.cdc_lab (
    id         NUMBER,
    value      VARCHAR,
    updated_at TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP()
);
```

### Step 2 — Seed data

```sql
INSERT INTO snowflake_tutorial.raw.cdc_lab (id, value)
VALUES
    (1, 'A'),
    (2, 'B'),
    (3, 'C');
```

### Step 3 — Create stream

```sql
CREATE OR REPLACE STREAM snowflake_tutorial.raw.cdc_lab_stream
ON TABLE snowflake_tutorial.raw.cdc_lab;
```

### Step 4 — Generate changes

```sql
INSERT INTO snowflake_tutorial.raw.cdc_lab (id, value)
VALUES (4, 'D');

UPDATE snowflake_tutorial.raw.cdc_lab
SET
    value = 'B-UPDATED',
    updated_at = CURRENT_TIMESTAMP()
WHERE id = 2;

DELETE FROM snowflake_tutorial.raw.cdc_lab
WHERE id = 3;
```

### Step 5 — Inspect CDC records

```sql
SELECT
    id,
    value,
    METADATA$ACTION,
    METADATA$ISUPDATE,
    METADATA$ROW_ID
FROM snowflake_tutorial.raw.cdc_lab_stream
ORDER BY id;
```

### Step 6 — Check for pending data

```sql
SELECT SYSTEM$STREAM_HAS_DATA(
    'SNOWFLAKE_TUTORIAL.RAW.CDC_LAB_STREAM'
);
```

### Step 7 — Query again

Run the same SELECT again and confirm that simply selecting from the stream does not consume its records.

### Step 8 — Consume in DML

```sql
CREATE OR REPLACE TABLE snowflake_tutorial.raw.cdc_lab_target (
    id         NUMBER,
    value      VARCHAR,
    updated_at TIMESTAMP_NTZ
);

INSERT INTO snowflake_tutorial.raw.cdc_lab_target
SELECT
    id,
    value,
    updated_at
FROM snowflake_tutorial.raw.cdc_lab_stream
WHERE METADATA$ACTION = 'INSERT';
```

### Step 9 — Inspect stream again

```sql
SELECT *
FROM snowflake_tutorial.raw.cdc_lab_stream;
```

Observe the stream state after committed DML processing.

---

## 38. Acceptance Criteria

The chapter is complete when you can:

- explain Snowflake Streams and CDC
- create and inspect a stream
- interpret `METADATA$ACTION`
- interpret `METADATA$ISUPDATE`
- explain `METADATA$ROW_ID`
- identify INSERT/UPDATE/DELETE changes
- explain stream offsets
- distinguish querying from consuming a stream
- use `SYSTEM$STREAM_HAS_DATA`
- explain standard vs append-only stream behavior
- design independent streams for multiple consumers
- explain stream staleness
- monitor `STALE_AFTER`
- troubleshoot missing or growing CDC backlogs
- design replay/backfill procedures
- combine Streams conceptually with Tasks and MERGE
- operate an incremental pipeline safely

---

## Key Takeaways

Snowflake Streams provide a powerful mechanism for incremental change processing.

```text
Source Table
     |
     v
Changes
     |
     v
Stream
     |
     v
Incremental Consumer
     |
     v
Target
```

Streams should not be treated as permanent message queues.

Production reliability depends on retention, consumption, transactions, monitoring, idempotency, and backfill.

The most important operational rule is:

```text
Never recreate a stale or problematic stream
before determining whether unprocessed data
must be recovered.
```

The next chapter is **Chapter 19 — Tasks & Scheduled Processing**.
