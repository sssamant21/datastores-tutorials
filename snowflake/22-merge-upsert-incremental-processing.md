# 22 — MERGE, UPSERT & Incremental Processing

## Overview

Production data pipelines rarely perform only inserts. Data changes over time through INSERT, UPDATE, and DELETE operations.

Snowflake `MERGE` allows multiple data-change operations to be expressed in a single statement.

A common architecture is:

```text
Source / CDC
     |
     v
Staging Data
     |
     v
MERGE
     |
     v
Target Table
```

For CDC pipelines:

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
MERGE
     |
     v
Curated Table
```

Correct MERGE design is essential for incremental loading, upserts, CDC, synchronization, deduplication, idempotent processing, and recovery/replay.

---

## 1. What Is MERGE?

MERGE compares source rows with target rows using a join condition.

```text
Source Row
    |
    v
Does target match?
   /       \
 Yes        No
 |           |
 v           v
UPDATE      INSERT
```

A basic pattern:

```sql
MERGE INTO target_table t
USING source_table s
ON t.id = s.id

WHEN MATCHED THEN
    UPDATE SET ...

WHEN NOT MATCHED THEN
    INSERT (...);
```

This pattern is commonly called an UPSERT because it combines UPDATE and INSERT.

---

## 2. Create Lab Tables

```sql
CREATE OR REPLACE TABLE snowflake_tutorial.raw.customer_target (
    customer_id    NUMBER,
    customer_name  VARCHAR,
    email           VARCHAR,
    status          VARCHAR,
    updated_at      TIMESTAMP_NTZ
);

CREATE OR REPLACE TABLE snowflake_tutorial.raw.customer_stage (
    customer_id    NUMBER,
    customer_name  VARCHAR,
    email           VARCHAR,
    status          VARCHAR,
    updated_at      TIMESTAMP_NTZ
);
```

---

## 3. Seed the Target

```sql
INSERT INTO snowflake_tutorial.raw.customer_target
VALUES
    (101, 'Alice', 'alice@example.com', 'ACTIVE', CURRENT_TIMESTAMP()),
    (102, 'Bob',   'bob@example.com',   'ACTIVE', CURRENT_TIMESTAMP()),
    (103, 'Carol', 'carol@example.com', 'ACTIVE', CURRENT_TIMESTAMP());

SELECT *
FROM snowflake_tutorial.raw.customer_target
ORDER BY customer_id;
```

---

## 4. Load Incremental Changes

Suppose customer 101 has a changed email and customer 104 is new.

```sql
INSERT INTO snowflake_tutorial.raw.customer_stage
VALUES
    (101, 'Alice', 'alice.new@example.com', 'ACTIVE', CURRENT_TIMESTAMP()),
    (104, 'David', 'david@example.com',     'ACTIVE', CURRENT_TIMESTAMP());
```

Now staging represents incremental changes.

---

## 5. Basic UPSERT

```sql
MERGE INTO snowflake_tutorial.raw.customer_target t
USING snowflake_tutorial.raw.customer_stage s
ON t.customer_id = s.customer_id

WHEN MATCHED THEN
    UPDATE SET
        t.customer_name = s.customer_name,
        t.email = s.email,
        t.status = s.status,
        t.updated_at = s.updated_at

WHEN NOT MATCHED THEN
    INSERT (
        customer_id,
        customer_name,
        email,
        status,
        updated_at
    )
    VALUES (
        s.customer_id,
        s.customer_name,
        s.email,
        s.status,
        s.updated_at
    );
```

Customer 101 is updated and customer 104 is inserted.

---

## 6. The Match Condition Is Critical

```sql
ON t.customer_id = s.customer_id
```

The match condition should normally use a stable business key.

Poor match conditions can create duplicate rows, incorrect updates, multiple matches, unexpected inserts, and data corruption.

Before writing MERGE, identify the business key.

---

## 7. Business Key vs Surrogate Key

A pipeline may use a source business key such as CUSTOMER_ID to locate a target row while the target also contains a warehouse-generated surrogate key.

Do not automatically match on a generated surrogate key if the source does not know it.

---

## 8. Conditional UPDATE

Not every matched row needs an update.

```sql
WHEN MATCHED
AND (
       t.customer_name <> s.customer_name
    OR t.email <> s.email
    OR t.status <> s.status
)
THEN UPDATE SET
    t.customer_name = s.customer_name,
    t.email = s.email,
    t.status = s.status,
    t.updated_at = s.updated_at
```

This can avoid unnecessary updates. NULL handling must be considered carefully.

---

## 9. NULL-Safe Comparison

A comparison such as `t.email <> s.email` does not behave as a simple Boolean comparison when NULL is involved.

For change detection, Snowflake supports NULL-safe comparison such as:

```sql
t.email IS DISTINCT FROM s.email
```

Example:

```sql
WHEN MATCHED
AND (
       t.customer_name IS DISTINCT FROM s.customer_name
    OR t.email IS DISTINCT FROM s.email
    OR t.status IS DISTINCT FROM s.status
)
THEN UPDATE SET
    t.customer_name = s.customer_name,
    t.email = s.email,
    t.status = s.status,
    t.updated_at = s.updated_at
```

---

## 10. MERGE with DELETE

Suppose staging contains an operation indicator: I = Insert, U = Update, D = Delete.

```sql
CREATE OR REPLACE TABLE snowflake_tutorial.raw.customer_cdc_stage (
    customer_id    NUMBER,
    customer_name  VARCHAR,
    email           VARCHAR,
    status          VARCHAR,
    updated_at      TIMESTAMP_NTZ,
    operation       VARCHAR
);
```

---

## 11. Full INSERT / UPDATE / DELETE MERGE

```sql
MERGE INTO snowflake_tutorial.raw.customer_target t
USING snowflake_tutorial.raw.customer_cdc_stage s
ON t.customer_id = s.customer_id

WHEN MATCHED
AND s.operation = 'D'
THEN DELETE

WHEN MATCHED
AND s.operation IN ('U', 'I')
THEN UPDATE SET
    t.customer_name = s.customer_name,
    t.email = s.email,
    t.status = s.status,
    t.updated_at = s.updated_at

WHEN NOT MATCHED
AND s.operation IN ('I', 'U')
THEN INSERT (
    customer_id,
    customer_name,
    email,
    status,
    updated_at
)
VALUES (
    s.customer_id,
    s.customer_name,
    s.email,
    s.status,
    s.updated_at
);
```

This is a common current-state synchronization pattern.

---

## 12. Why Clause Ordering Matters

A MERGE can contain multiple matched conditions, such as DELETE and UPDATE conditions.

Production engineers should be able to answer which clause should process a given source row.

Avoid overlapping conditions whose behavior is difficult to reason about.

---

## 13. Source Duplicates

If staging contains multiple rows for the same business key, the intended target state can become ambiguous.

Production pipelines should normalize duplicate source keys before merging.

---

## 14. Detect Duplicate Source Keys

```sql
SELECT
    customer_id,
    COUNT(*) AS row_count
FROM snowflake_tutorial.raw.customer_stage
GROUP BY customer_id
HAVING COUNT(*) > 1;
```

If duplicates are unexpected, stop and investigate the source before choosing a record.

---

## 15. Deduplicate with ROW_NUMBER

```sql
SELECT *
FROM snowflake_tutorial.raw.customer_stage
QUALIFY ROW_NUMBER() OVER (
    PARTITION BY customer_id
    ORDER BY updated_at DESC
) = 1;
```

This selects the most recent row per customer, but timestamp ties must still be considered.

---

## 16. Deterministic Deduplication

Better ordering may use UPDATED_AT, SOURCE_SEQUENCE, and INGESTED_AT.

```sql
QUALIFY ROW_NUMBER() OVER (
    PARTITION BY customer_id
    ORDER BY
        updated_at DESC,
        source_sequence DESC,
        ingested_at DESC
) = 1
```

The ordering should produce a deterministic winner.

---

## 17. MERGE from a Deduplicated Source

```sql
MERGE INTO snowflake_tutorial.raw.customer_target t

USING (
    SELECT *
    FROM snowflake_tutorial.raw.customer_stage
    QUALIFY ROW_NUMBER() OVER (
        PARTITION BY customer_id
        ORDER BY updated_at DESC
    ) = 1
) s

ON t.customer_id = s.customer_id

WHEN MATCHED THEN
    UPDATE SET
        t.customer_name = s.customer_name,
        t.email = s.email,
        t.status = s.status,
        t.updated_at = s.updated_at

WHEN NOT MATCHED THEN
    INSERT (
        customer_id,
        customer_name,
        email,
        status,
        updated_at
    )
    VALUES (
        s.customer_id,
        s.customer_name,
        s.email,
        s.status,
        s.updated_at
    );
```

This pattern is safer when staging can contain multiple versions of the same key.

---

## 18. Late-Arriving Records

Suppose the target contains customer 101 with UPDATED_AT 12:00 and the pipeline later receives an older 11:30 record.

Blindly updating the target would regress it to an older state.

Protect against this when source timestamps or versions are reliable.

---

## 19. Protect Against Older Updates

```sql
WHEN MATCHED
AND s.updated_at > t.updated_at
THEN UPDATE SET
    t.customer_name = s.customer_name,
    t.email = s.email,
    t.status = s.status,
    t.updated_at = s.updated_at
```

Now older source records do not overwrite newer target state.

---

## 20. Timestamp Alone May Not Be Enough

Timestamps can have clock differences, low precision, duplicate values, or incorrect source values.

If the source provides a sequence/version such as SOURCE_VERSION, prefer deterministic ordering based on source semantics.

---

## 21. Idempotent MERGE

A major advantage of a well-designed MERGE is replay safety.

If the same source batch is processed twice, the desired final target state should remain correct without duplicate business rows.

This is idempotency.

---

## 22. Idempotency Does Not Mean No Work

Even if a MERGE produces the same final result, it may still perform unnecessary processing if every matched row is updated.

Conditional updates can reduce unnecessary data modification.

---

## 23. Incremental Processing

Instead of scanning a massive source table on every run, process only a bounded change set.

Possible sources include Snowflake Streams, timestamp watermarks, sequence watermarks, batch IDs, change tables, and external CDC feeds.

The goal is to process what changed rather than reprocess everything.

---

## 24. Watermark-Based Incremental Processing

Example:

```sql
SELECT *
FROM source_table
WHERE updated_at > :last_successful_timestamp
  AND updated_at <= :current_high_watermark;
```

This defines a bounded processing window.

---

## 25. Why a High Watermark Matters

Avoid an unbounded condition that only uses the last successful timestamp because new rows can continue arriving during execution.

Use a fixed low and high watermark for the batch.

After successful processing, the next low watermark becomes the committed high watermark.

---

## 26. Watermark Failure Safety

Do not advance the watermark before processing succeeds.

Correct sequence:

```text
Determine high watermark
      |
      v
Process batch
      |
      v
Validate / commit
      |
      v
Advance watermark
```

---

## 27. Streams as Managed CDC State

Snowflake Streams provide managed change tracking rather than requiring a custom timestamp watermark for every use case.

```text
Source Table
     |
     v
Stream Offset
     |
     v
Task
     |
     v
MERGE
```

Watermarks remain useful for external systems, backfills, historical recovery, sources without Streams, and bounded replay.

---

## 28. MERGE from a Stream

Conceptually:

```sql
MERGE INTO curated.orders t
USING normalized_stream_changes s
ON t.order_id = s.order_id

WHEN MATCHED
AND s.operation = 'DELETE'
THEN DELETE

WHEN MATCHED
AND s.operation = 'UPSERT'
THEN UPDATE SET ...

WHEN NOT MATCHED
AND s.operation = 'UPSERT'
THEN INSERT ...;
```

The difficult part is usually correctly normalizing CDC records before the MERGE.

---

## 29. Stream UPDATE Semantics

An update can appear as DELETE old row plus INSERT new row with update metadata.

A current-state pipeline usually wants the latest new state, not to delete the target and accidentally lose the replacement row.

Normalize the stream according to the intended target model.

---

## 30. Stream DELETE Semantics

A true source DELETE may need to become a target DELETE, but first determine the business requirement.

Some systems require hard delete. Others require soft delete with fields such as STATUS, IS_ACTIVE, or DELETED_AT.

Do not assume physical deletion is always correct.

---

## 31. Hard Delete vs Soft Delete

Hard delete removes the target row. It can simplify current-state queries but removes history and can affect audit requirements.

Soft delete preserves the record and marks it inactive/deleted. It supports auditing but requires queries to filter correctly and increases retained history.

Choose based on business and compliance requirements.

---

## 32. Current-State MERGE

A current-state target answers: What does this entity look like now?

Typical behavior:

```text
INSERT → INSERT
UPDATE → UPDATE
DELETE → DELETE or soft delete
```

---

## 33. Historical Processing

A historical target answers: How did this entity change over time?

Historical modeling may require effective start, effective end, current flag, version, and change reason.

This often leads to Slowly Changing Dimension patterns rather than a simple one-row UPSERT.

---

## 34. SCD Type 1 Concept

SCD Type 1 overwrites old values.

```text
Before:
101 | Alice | old@email.com

After:
101 | Alice | new@email.com
```

Old values disappear.

---

## 35. SCD Type 2 Concept

SCD Type 2 preserves history.

```text
101 | old@email.com | 2026-01-01 | 2026-05-01 | FALSE
101 | new@email.com | 2026-05-01 | NULL       | TRUE
```

This requires more complex processing than a simple one-row UPSERT.

---

## 36. Transactions

For multi-step incremental processing, transactions may be required.

```sql
BEGIN;

-- normalize changes
-- apply target DML
-- update audit/control information

COMMIT;
```

If something fails:

```sql
ROLLBACK;
```

Design transactional boundaries according to pipeline correctness requirements.

---

## 37. Avoid Partial Pipeline State

If multiple target/control operations must succeed together, partial success can leave inconsistent state.

Use transactional design when operations must succeed or fail together.

---

## 38. MERGE Performance

A MERGE can become expensive when the target or source batch is large, match-key pruning is poor, many rows are updated, expressions are complex, compute is constrained, or concurrency is high.

Use Query Profile to determine where time is spent. Do not automatically increase warehouse size.

---

## 39. Reduce Source Before MERGE

Prefer:

```text
Raw source
   |
   v
Filter
   |
   v
Deduplicate
   |
   v
Validate
   |
   v
MERGE
```

Smaller source sets can improve performance and correctness.

---

## 40. Avoid SELECT *

Production pipelines should prefer explicit columns to reduce unexpected behavior after schema changes.

---

## 41. Validate Source Before MERGE

Check duplicate keys, NULL business keys, invalid operations, unexpected data types, unexpected record counts, old versions, and malformed records.

Bad source data should not silently become bad target data.

---

## 42. Reject or Quarantine Invalid Rows

```text
Stage
 |
 v
Validation
 /       \
Valid    Invalid
 |         |
 v         v
MERGE    Quarantine
```

This allows healthy records to continue while preserving invalid data for investigation when business requirements permit partial processing.

---

## 43. MERGE Audit Metrics

Capture operational metrics such as batch ID, source row count, inserted count, updated count, deleted count, rejected count, start/end time, status, and query ID.

These metrics are invaluable during incidents.

---

## 44. Pipeline Audit Table

```sql
CREATE OR REPLACE TABLE snowflake_tutorial.raw.pipeline_audit (
    batch_id          VARCHAR,
    pipeline_name     VARCHAR,
    source_row_count  NUMBER,
    started_at        TIMESTAMP_NTZ,
    completed_at      TIMESTAMP_NTZ,
    status            VARCHAR,
    query_id          VARCHAR,
    error_message     VARCHAR
);
```

A production implementation may add inserted, updated, deleted, and rejected counts where they can be reliably captured.

---

## 45. Reconciliation After MERGE

Do not assume successful SQL means correct data.

Validate expected keys, row counts, business totals, latest timestamps, duplicate keys, and missing records.

```sql
SELECT
    customer_id,
    COUNT(*)
FROM snowflake_tutorial.raw.customer_target
GROUP BY customer_id
HAVING COUNT(*) > 1;
```

For a current-state target keyed by customer_id, this should normally return no rows.

---

## 46. Replay

If a pipeline failed between 10:00 and 11:00, replay only the required window:

```sql
WHERE updated_at >= '2026-10-04 10:00:00'
  AND updated_at <  '2026-10-04 11:00:00'
```

Feed the bounded dataset through the same normalization and MERGE logic.

Avoid creating separate emergency transformation logic unless necessary.

---

## 47. Replay Should Use the Same Business Rules

Preferred:

```text
Historical source
      |
      v
Same normalization
      |
      v
Same MERGE
      |
      v
Target
```

Recovery paths should be designed and tested before incidents.

---

## 48. Overlapping Replay Windows

An idempotent current-state MERGE should generally tolerate overlapping replay windows more safely than raw INSERT logic.

Still verify version ordering, late records, delete semantics, and audit metrics.

---

## 49. Batch IDs

A batch ID can improve traceability.

Store it in audit tables, quarantine tables, and operational logs to trace a problematic load across pipeline components.

---

## 50. Troubleshooting — Duplicate Target Rows

Investigate:

1. What is the intended business key?
2. Does the target already contain duplicates?
3. Does staging contain duplicate keys?
4. Is the MERGE condition correct?
5. Was another pipeline writing concurrently?
6. Was replay performed?
7. Was INSERT used outside the MERGE?

Do not simply delete duplicates without understanding how they were created.

---

## 51. Troubleshooting — Old Data Replaced New Data

Likely causes include late-arriving records, out-of-order CDC, missing source-version checks, incorrect timestamp logic, or replay applying older state.

Compare source version/timestamp with target version/timestamp and add ordering protection where required.

---

## 52. Troubleshooting — MERGE Is Slow

Investigate source rows, target size, match condition, Query Profile, pruning, join strategy, bytes scanned, spilling, warehouse queueing, warehouse size, concurrent workload, and update percentage.

Do not start by resizing compute. Find the expensive operation first.

---

## 53. Troubleshooting — Unexpected Deletes

Immediately determine which source rows were marked DELETE, which batch/query/task performed the operation, and what MERGE condition was used.

Preserve query history and audit information.

If recovery is required, use Snowflake recovery capabilities such as Time Travel where applicable and follow the recovery runbooks covered later in the tutorial series.

---

## 54. Troubleshooting — MERGE Failed

Capture query ID, error message, source batch, row count, task, timestamp, and warehouse.

Determine whether the failure came from SQL, data, schema, permissions, compute, duplicate source matches, or another dependency.

Do not clear staging or CDC state until the unprocessed window is understood.

---

## 55. Production MERGE Runbook

When incremental processing fails:

1. Stop unnecessary retries if they increase risk.
2. Capture the failed query ID.
3. Capture the exact error.
4. Identify the source batch/window.
5. Preserve staging and CDC state.
6. Check source row count.
7. Check duplicate business keys.
8. Check NULL keys.
9. Check operation values.
10. Check schema changes.
11. Check permissions.
12. Check Query Profile if performance-related.
13. Determine last known-good target state.
14. Determine the missing processing window.
15. Correct the root cause.
16. Test with a bounded dataset.
17. Replay using normal MERGE logic.
18. Reconcile.
19. Confirm freshness.
20. Resume normal processing.

---

## 56. Production Best Practices

Use stable business keys, explicit columns, source deduplication, deterministic ordering, NULL-safe comparisons, conditional updates, version/timestamp protection, idempotent processing, bounded batches, transactional consistency, audit metrics, quarantine strategy, reconciliation, and tested replay procedures.

Avoid MERGE without understanding the business key, SELECT *, blindly processing duplicate source keys, updating newer target rows with older source data, advancing watermarks before successful processing, clearing staging after failures, unbounded replay, ad-hoc incident SQL without validation, and assuming successful MERGE means correct data.

---

## 57. Hands-On Lab — Production UPSERT

### Step 1 — Reset target

```sql
TRUNCATE TABLE snowflake_tutorial.raw.customer_target;
```

### Step 2 — Seed target

```sql
INSERT INTO snowflake_tutorial.raw.customer_target
VALUES
    (101, 'Alice', 'alice@example.com', 'ACTIVE', '2026-10-04 10:00:00'),
    (102, 'Bob',   'bob@example.com',   'ACTIVE', '2026-10-04 10:00:00');
```

### Step 3 — Reset staging

```sql
TRUNCATE TABLE snowflake_tutorial.raw.customer_stage;
```

### Step 4 — Add changes

```sql
INSERT INTO snowflake_tutorial.raw.customer_stage
VALUES
    (101, 'Alice', 'alice.new@example.com', 'ACTIVE', '2026-10-04 11:00:00'),
    (103, 'Carol', 'carol@example.com',     'ACTIVE', '2026-10-04 11:00:00');
```

### Step 5 — Validate duplicate keys

```sql
SELECT
    customer_id,
    COUNT(*)
FROM snowflake_tutorial.raw.customer_stage
GROUP BY customer_id
HAVING COUNT(*) > 1;
```

Expected: no rows.

### Step 6 — Run MERGE

```sql
MERGE INTO snowflake_tutorial.raw.customer_target t
USING snowflake_tutorial.raw.customer_stage s
ON t.customer_id = s.customer_id

WHEN MATCHED
AND s.updated_at > t.updated_at
THEN UPDATE SET
    t.customer_name = s.customer_name,
    t.email = s.email,
    t.status = s.status,
    t.updated_at = s.updated_at

WHEN NOT MATCHED
THEN INSERT (
    customer_id,
    customer_name,
    email,
    status,
    updated_at
)
VALUES (
    s.customer_id,
    s.customer_name,
    s.email,
    s.status,
    s.updated_at
);
```

### Step 7 — Validate

```sql
SELECT *
FROM snowflake_tutorial.raw.customer_target
ORDER BY customer_id;
```

Expected: customer 101 updated, 102 unchanged, and 103 inserted.

---

## 58. Lab — Test Replay Safety

Run the same MERGE again.

```sql
SELECT
    customer_id,
    COUNT(*)
FROM snowflake_tutorial.raw.customer_target
GROUP BY customer_id
ORDER BY customer_id;
```

Expected: one row each for 101, 102, and 103.

---

## 59. Lab — Test Late Data Protection

Add an older record:

```sql
INSERT INTO snowflake_tutorial.raw.customer_stage
VALUES
    (101, 'Alice', 'old@example.com', 'ACTIVE', '2026-10-04 09:00:00');
```

Run the deduplicated/version-aware processing logic.

The target should retain the newer state. This demonstrates why `s.updated_at > t.updated_at` or a stronger source-version rule is important.

---

## 60. Acceptance Criteria

The chapter is complete when you can:

- explain Snowflake MERGE
- build an UPSERT
- identify an appropriate business key
- use conditional MATCHED clauses
- handle INSERT/UPDATE/DELETE
- perform NULL-safe change detection
- detect source duplicates
- deduplicate with ROW_NUMBER
- design deterministic deduplication
- protect against late-arriving older records
- explain timestamp vs sequence ordering
- design idempotent MERGE logic
- implement incremental processing
- explain low and high watermarks
- safely advance processing state
- integrate MERGE with Streams
- reason about stream update/delete semantics
- choose hard vs soft delete
- distinguish current-state and historical models
- explain SCD Type 1 and Type 2 concepts
- use transactions where required
- troubleshoot MERGE performance
- capture pipeline audit data
- reconcile results
- safely replay bounded windows
- operate a production MERGE recovery runbook

---

## Key Takeaways

MERGE is one of the most important Snowflake operations for production incremental pipelines.

```text
Incremental Changes
        |
        v
Normalize
        |
        v
Deduplicate
        |
        v
Validate
        |
        v
MERGE
        |
        v
Target
```

Reliable incremental processing depends on business keys, ordering, deduplication, idempotency, transactional safety, auditability, replay, and reconciliation.

The central production rule is:

```text
Never advance processing state
until the corresponding data changes
have completed successfully.
```

During an incident:

```text
Preserve source/CDC state
      |
      v
Determine missing window
      |
      v
Correct root cause
      |
      v
Replay with normal logic
      |
      v
Reconcile
```

The next chapter is **Chapter 23 — Stored Procedures**.
