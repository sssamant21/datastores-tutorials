# 19 — Tasks & Scheduled Processing

## Overview

Snowflake Tasks provide native scheduling and orchestration for executing SQL statements, stored procedures, and data-pipeline operations inside Snowflake.

A task can execute work on a schedule, after another task completes, when a condition is satisfied, as part of a task graph, using warehouse-managed compute, or using Snowflake-managed serverless compute.

A common CDC architecture is:

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
MERGE / INSERT
     |
     v
Target Table
```

Tasks allow Snowflake pipelines to run without requiring an external scheduler for every operation.

---

## 1. What Is a Snowflake Task?

A task is a Snowflake object containing execution logic, a schedule/dependency, and compute configuration.

A simple task might execute:

```sql
INSERT INTO reporting.daily_orders
SELECT *
FROM raw.orders
WHERE order_date >= CURRENT_DATE();
```

on a recurring schedule.

---

## 2. Basic Task Architecture

```text
Schedule
   |
   v
Task
   |
   v
SQL Statement
   |
   v
Target Object
```

For example:

```text
Every 5 minutes
      |
      v
PROCESS_ORDERS_TASK
      |
      v
INSERT / MERGE
      |
      v
CURATED.ORDERS
```

---

## 3. Create the Lab Environment

```sql
CREATE OR REPLACE TABLE snowflake_tutorial.raw.task_orders (
    order_id       NUMBER,
    customer_id    NUMBER,
    status         VARCHAR,
    order_amount   NUMBER(12,2),
    updated_at     TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP()
);

CREATE OR REPLACE TABLE snowflake_tutorial.raw.task_orders_processed (
    order_id       NUMBER,
    customer_id    NUMBER,
    status         VARCHAR,
    order_amount   NUMBER(12,2),
    processed_at   TIMESTAMP_NTZ
);

INSERT INTO snowflake_tutorial.raw.task_orders
    (order_id, customer_id, status, order_amount)
VALUES
    (1001, 501, 'NEW', 100.00),
    (1002, 502, 'NEW', 200.00);
```

---

## 4. Create a Basic Scheduled Task

A task can run using a user-managed virtual warehouse.

```sql
CREATE OR REPLACE TASK snowflake_tutorial.raw.process_orders_task
    WAREHOUSE = tutorial_wh
    SCHEDULE = '5 MINUTE'
AS
INSERT INTO snowflake_tutorial.raw.task_orders_processed
SELECT
    order_id,
    customer_id,
    status,
    order_amount,
    CURRENT_TIMESTAMP()
FROM snowflake_tutorial.raw.task_orders;
```

This defines a task scheduled to run every five minutes.

---

## 5. Tasks Start Suspended

Inspect the task:

```sql
SHOW TASKS
IN SCHEMA snowflake_tutorial.raw;
```

Resume it when ready:

```sql
ALTER TASK snowflake_tutorial.raw.process_orders_task
RESUME;
```

Suspend it:

```sql
ALTER TASK snowflake_tutorial.raw.process_orders_task
SUSPEND;
```

Always verify task state after deployment.

---

## 6. Inspect Tasks

```sql
SHOW TASKS;

SHOW TASKS
IN SCHEMA snowflake_tutorial.raw;

DESC TASK snowflake_tutorial.raw.process_orders_task;
```

This helps verify schedule, compute, state, task definition, dependencies, and conditions.

---

## 7. Schedule Syntax

A task can use interval-based scheduling:

```sql
SCHEDULE = '10 MINUTE'
```

Another common scheduling mechanism is CRON:

```sql
SCHEDULE = 'USING CRON 0 2 * * * UTC'
```

Always specify and document the intended timezone.

---

## 8. CRON Scheduling

CRON schedules are useful for predictable calendar-based processing such as hourly, daily, weekly, month-end, and business-hour workflows.

```sql
CREATE OR REPLACE TASK daily_processing_task
    WAREHOUSE = tutorial_wh
    SCHEDULE = 'USING CRON 0 3 * * * UTC'
AS
CALL process_daily_data();
```

Document schedules in operational runbooks.

---

## 9. Serverless Tasks

Snowflake can manage compute for tasks instead of requiring a specific virtual warehouse.

```sql
CREATE OR REPLACE TASK serverless_processing_task
    SCHEDULE = '10 MINUTE'
AS
INSERT INTO target_table
SELECT *
FROM source_table;
```

Snowflake manages compute sizing according to the serverless task configuration and workload.

---

## 10. User-Managed vs Serverless Tasks

| Area | User-Managed | Serverless |
|---|---|---|
| Compute | Virtual warehouse | Snowflake managed |
| Warehouse sizing | Administrator | Snowflake |
| Warehouse monitoring | Required | Reduced |
| Compute isolation | Warehouse design | Service managed |
| Cost model | Warehouse credits | Serverless consumption |
| Operational control | Higher | Simpler |

Choose based on workload predictability, isolation, cost, performance, and operational requirements.

---

## 11. Task History

Task execution history is critical during troubleshooting.

```sql
SELECT *
FROM TABLE(
    INFORMATION_SCHEMA.TASK_HISTORY(
        TASK_NAME => 'PROCESS_ORDERS_TASK',
        SCHEDULED_TIME_RANGE_START =>
            DATEADD('hour', -4, CURRENT_TIMESTAMP())
    )
)
ORDER BY SCHEDULED_TIME DESC;
```

Review scheduled time, execution state, completion time, error information, and query identifiers.

---

## 12. Check Failed Task Runs

```sql
SELECT *
FROM TABLE(
    INFORMATION_SCHEMA.TASK_HISTORY(
        SCHEDULED_TIME_RANGE_START =>
            DATEADD('day', -1, CURRENT_TIMESTAMP())
    )
)
WHERE STATE = 'FAILED'
ORDER BY SCHEDULED_TIME DESC;
```

---

## 13. Manually Execute a Task

```sql
EXECUTE TASK snowflake_tutorial.raw.process_orders_task;
```

Manual execution is useful for deployment validation, troubleshooting, controlled testing, and verifying corrected SQL.

Do not repeatedly execute production tasks manually without understanding whether the operation is idempotent.

---

## 14. Tasks with Streams

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
Target
```

Create a stream:

```sql
CREATE OR REPLACE STREAM snowflake_tutorial.raw.task_orders_stream
ON TABLE snowflake_tutorial.raw.task_orders;
```

Now the task can process only changed data.

---

## 15. Conditional Task Execution

```sql
CREATE OR REPLACE TASK snowflake_tutorial.raw.process_order_changes
    WAREHOUSE = tutorial_wh
    SCHEDULE = '5 MINUTE'
    WHEN SYSTEM$STREAM_HAS_DATA(
        'SNOWFLAKE_TUTORIAL.RAW.TASK_ORDERS_STREAM'
    )
AS
INSERT INTO snowflake_tutorial.raw.task_orders_processed
SELECT
    order_id,
    customer_id,
    status,
    order_amount,
    CURRENT_TIMESTAMP()
FROM snowflake_tutorial.raw.task_orders_stream
WHERE METADATA$ACTION = 'INSERT'
  AND METADATA$ISUPDATE = FALSE;
```

This combines scheduling with change detection.

---

## 16. Why Use a WHEN Condition?

Without a condition, a task can wake up and run SQL even when no new data exists.

With a condition:

```text
Task evaluation
     |
     v
Stream has data?
   /       \
 No        Yes
 |          |
Skip       Execute
```

This can reduce unnecessary processing.

---

## 17. Task Graphs

Tasks can be connected through dependencies.

```text
ROOT_TASK
    |
    v
LOAD_RAW
    |
    v
TRANSFORM
    |
    v
PUBLISH
```

This creates a task graph.

---

## 18. Create a Child Task

```sql
CREATE OR REPLACE TASK transform_orders_task
    WAREHOUSE = tutorial_wh
    AFTER load_orders_task
AS
INSERT INTO curated.orders
SELECT *
FROM raw.orders;
```

The `AFTER` dependency connects the child to its predecessor.

---

## 19. Branching Task Graph

```text
                 ROOT
                   |
                   v
               LOAD_RAW
              /        \
             v          v
      PROCESS_ORDERS  PROCESS_CUSTOMERS
             \          /
              v        v
                PUBLISH
```

Task graphs allow more sophisticated Snowflake-native orchestration. Keep graphs understandable; extremely complex business workflows may be easier to operate with an external orchestration platform.

---

## 20. Root and Child Tasks

The root task defines the primary schedule. Child tasks generally execute based on dependencies.

When troubleshooting a child task that did not run, investigate the parent chain.

---

## 21. Task Dependencies

A downstream task depends on successful progression through its graph.

Troubleshooting should ask:

- Did the root run?
- Did the parent succeed?
- Was the child eligible?
- Did its WHEN condition evaluate appropriately?
- Did the child fail?

Looking only at the final task can hide the actual upstream failure.

---

## 22. Suspend Before Structural Changes

For production task graphs, use controlled change procedures:

```text
Inspect
   |
   v
Suspend as required
   |
   v
Modify
   |
   v
Validate
   |
   v
Resume
   |
   v
Verify execution
```

Do not casually recreate active production task graphs.

---

## 23. Task Failure Behavior

Tasks can fail because of SQL errors, missing objects, permission changes, schema changes, warehouse problems, resource limits, stored procedure failures, invalid data, or dependency problems.

Always capture the exact error from task history before changing the task.

---

## 24. Permissions

A task executes within Snowflake's security model.

Required privileges depend on task ownership, referenced objects, compute model, called procedures, and target tables.

A deployment can succeed while execution later fails because the task owner lacks a required privilege.

Test execution using the actual production role model.

---

## 25. Warehouse Considerations

For user-managed tasks:

```sql
SHOW WAREHOUSES LIKE 'TUTORIAL_WH';
```

Operational considerations include warehouse size, auto-suspend, auto-resume, concurrency, queueing, workload isolation, and credit consumption.

A task problem may actually be a compute problem.

---

## 26. Task Overlap

Consider what should happen when one scheduled execution takes longer than the scheduling interval.

Example:

```text
Schedule = every 5 minutes
Runtime  = 12 minutes
```

Ask whether executions can or should overlap, whether processing is idempotent, and whether two runs could modify the same data.

Never assume a high-frequency schedule is safe merely because Snowflake accepts it.

---

## 27. Scheduling Frequency

Choose frequency based on business freshness requirements, data arrival frequency, processing duration, cost, and downstream dependencies.

If the SLA is 30 minutes, executing expensive transformations every minute may provide little business value.

---

## 28. Task and Data Freshness

A task being successful does not prove the data is current.

Monitor task success, source freshness, and target freshness.

```sql
SELECT
    MAX(processed_at)
FROM snowflake_tutorial.raw.task_orders_processed;
```

A task can successfully process zero rows while upstream ingestion has stopped.

---

## 29. Task Monitoring Strategy

Monitor at least:

- task state
- last scheduled run
- last successful run
- recent failures
- execution duration
- rows/data processed
- warehouse behavior
- stream backlog
- target freshness

This provides much stronger operational coverage than checking only `SHOW TASKS`.

---

## 30. Troubleshooting — Task Did Not Run

1. Confirm the task exists with `SHOW TASKS`.
2. Verify it is resumed.
3. Check task history to determine whether it was scheduled.
4. For task graphs, inspect upstream dependencies.
5. Check whether a WHEN condition prevented execution.
6. Inspect task history for failures.

For Streams-based tasks:

```sql
SELECT SYSTEM$STREAM_HAS_DATA(
    'SNOWFLAKE_TUTORIAL.RAW.TASK_ORDERS_STREAM'
);
```

---

## 31. Troubleshooting — Task Failed

```sql
SELECT *
FROM TABLE(
    INFORMATION_SCHEMA.TASK_HISTORY(
        SCHEDULED_TIME_RANGE_START =>
            DATEADD('hour', -6, CURRENT_TIMESTAMP())
    )
)
ORDER BY SCHEDULED_TIME DESC;
```

Identify task, scheduled time, start time, completion time, state, error, and query ID.

Then investigate the failing SQL/query rather than immediately recreating the task.

---

## 32. Troubleshooting — Task Is Successful but Data Is Missing

Check:

- Did source data arrive?
- Did the stream contain changes?
- Did the WHEN condition execute?
- How many rows were processed?
- Was filtering logic correct?
- Was the expected target queried?

A technically successful task may have legitimately processed zero records.

---

## 33. Troubleshooting — Task Is Slow

Investigate query profile, warehouse size, warehouse queueing, data volume, pruning, join behavior, MERGE behavior, spilling, concurrency, and downstream contention.

Do not automatically increase warehouse size. Determine whether the bottleneck is compute, SQL design, data layout, or concurrency.

---

## 34. Troubleshooting — Stream Backlog Increasing

If backlog grows, determine whether the task is running, failing, processing slower than the arrival rate, scheduled too infrequently, facing increased volume, or using insufficient compute.

The stream itself may be healthy.

---

## 35. Production CDC Pattern

```text
Snowpipe / Streaming
        |
        v
     RAW TABLE
        |
        v
      STREAM
        |
        v
      TASK
        |
        v
      MERGE
        |
        v
   CURATED TABLE
```

Responsibilities:

```text
Ingestion → Snowpipe
Change tracking → Stream
Scheduling → Task
Incremental application → MERGE
Consumption → Curated table
```

This separation helps isolate failures.

---

## 36. Task Cost Management

For user-managed tasks, cost is strongly influenced by warehouse size, runtime, execution frequency, auto-suspend, and concurrency.

For serverless tasks, monitor serverless task consumption.

A common waste pattern is a frequent task with no new data performing expensive processing. Conditional execution can help avoid unnecessary work.

---

## 37. Idempotency

Scheduled pipelines must consider retries and manual execution.

Ask:

```text
If this task runs twice, what happens?
```

Better designs use business keys, MERGE, CDC offsets, deduplication, and transactional processing.

Manual recovery should not create silent duplicate data.

---

## 38. Production Deployment Checklist

Before enabling a task:

- Validate SQL independently.
- Verify object names.
- Verify owner/role.
- Verify privileges.
- Verify compute configuration.
- Verify schedule/timezone.
- Verify dependency graph.
- Verify WHEN condition.
- Verify idempotency.
- Verify failure/retry behavior.
- Verify monitoring.
- Verify freshness alerting.
- Verify recovery procedure.

Only then resume production execution.

---

## 39. Operational Runbook

When a Snowflake task pipeline stops processing:

1. Confirm the expected data should exist.
2. Run `SHOW TASKS`.
3. Verify task state.
4. Inspect `TASK_HISTORY`.
5. Identify the last successful run.
6. Identify the first failed or missing run.
7. Capture the exact error.
8. Check parent tasks.
9. Check `WHEN` conditions.
10. Check stream state.
11. Check warehouse/serverless compute.
12. Inspect the failing query.
13. Check permissions.
14. Check recent deployments/schema changes.
15. Determine the unprocessed data window.
16. Correct the root cause.
17. Test safely.
18. Resume the task.
19. Backfill/replay if required.
20. Verify target freshness and completeness.

---

## 40. Production Best Practices

Use explicit schedules, documented timezones, Streams for incremental processing, WHEN conditions where appropriate, task history monitoring, target freshness monitoring, idempotent SQL, meaningful task names, workload isolation, controlled task graph changes, backfill procedures, and least-privilege ownership.

Avoid scheduling everything every minute, assuming task success means data freshness, ignoring task history, recreating failed tasks before investigation, manual execution without idempotency checks, ignoring stream staleness, oversizing warehouses before query analysis, unnecessarily complex task graphs, and leaving failed pipelines without backlog monitoring.

---

## 41. Hands-On Lab

### Objective

Build a Stream + Task incremental processing pipeline.

### Step 1 — Create source

```sql
CREATE OR REPLACE TABLE snowflake_tutorial.raw.orders_task_lab (
    order_id       NUMBER,
    customer_id    NUMBER,
    amount         NUMBER(12,2),
    updated_at     TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP()
);
```

### Step 2 — Create target

```sql
CREATE OR REPLACE TABLE snowflake_tutorial.raw.orders_task_target (
    order_id       NUMBER,
    customer_id    NUMBER,
    amount         NUMBER(12,2),
    processed_at   TIMESTAMP_NTZ
);
```

### Step 3 — Create stream

```sql
CREATE OR REPLACE STREAM snowflake_tutorial.raw.orders_task_stream
ON TABLE snowflake_tutorial.raw.orders_task_lab;
```

### Step 4 — Create task

```sql
CREATE OR REPLACE TASK snowflake_tutorial.raw.orders_task
    WAREHOUSE = tutorial_wh
    SCHEDULE = '5 MINUTE'
    WHEN SYSTEM$STREAM_HAS_DATA(
        'SNOWFLAKE_TUTORIAL.RAW.ORDERS_TASK_STREAM'
    )
AS
INSERT INTO snowflake_tutorial.raw.orders_task_target
SELECT
    order_id,
    customer_id,
    amount,
    CURRENT_TIMESTAMP()
FROM snowflake_tutorial.raw.orders_task_stream
WHERE METADATA$ACTION = 'INSERT'
  AND METADATA$ISUPDATE = FALSE;
```

### Step 5 — Inspect before enabling

```sql
DESC TASK snowflake_tutorial.raw.orders_task;
```

### Step 6 — Resume

```sql
ALTER TASK snowflake_tutorial.raw.orders_task
RESUME;
```

### Step 7 — Generate data

```sql
INSERT INTO snowflake_tutorial.raw.orders_task_lab
    (order_id, customer_id, amount)
VALUES
    (2001, 601, 50.00),
    (2002, 602, 75.00);
```

### Step 8 — Check stream

```sql
SELECT *
FROM snowflake_tutorial.raw.orders_task_stream;
```

### Step 9 — Inspect task history

```sql
SELECT *
FROM TABLE(
    INFORMATION_SCHEMA.TASK_HISTORY(
        TASK_NAME => 'ORDERS_TASK',
        SCHEDULED_TIME_RANGE_START =>
            DATEADD('hour', -1, CURRENT_TIMESTAMP())
    )
)
ORDER BY SCHEDULED_TIME DESC;
```

### Step 10 — Validate target

```sql
SELECT *
FROM snowflake_tutorial.raw.orders_task_target
ORDER BY processed_at DESC;
```

### Step 11 — Suspend after lab

```sql
ALTER TASK snowflake_tutorial.raw.orders_task
SUSPEND;
```

Do not leave unnecessary lab tasks running.

---

## 42. Acceptance Criteria

The chapter is complete when you can:

- explain Snowflake Tasks
- create a scheduled task
- use interval and CRON schedules
- distinguish user-managed and serverless tasks
- resume and suspend tasks
- inspect task definitions
- query task execution history
- manually execute a task safely
- combine Streams with Tasks
- use `SYSTEM$STREAM_HAS_DATA`
- explain conditional task execution
- design parent/child task graphs
- troubleshoot dependency failures
- identify task SQL vs compute problems
- monitor target freshness
- reason about overlapping schedules
- design idempotent scheduled processing
- manage task cost
- perform safe production recovery

---

## Key Takeaways

Snowflake Tasks provide the orchestration layer for Snowflake-native pipelines.

```text
Schedule
   |
   v
Task
   |
   v
SQL / Procedure
   |
   v
Target
```

For incremental pipelines:

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
MERGE / INSERT
   |
   v
Target
```

Production task operations require more than confirming that the task exists.

Always monitor execution, failures, dependencies, backlog, freshness, and cost.

A successful scheduler is useful only when the expected data reaches the expected destination correctly and on time.

The next chapter is **Chapter 20 — Dynamic Tables & Declarative Pipelines**.
