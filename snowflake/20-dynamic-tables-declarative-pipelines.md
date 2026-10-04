# 20 — Dynamic Tables & Declarative Pipelines

## Overview

Snowflake Dynamic Tables provide a declarative approach for building continuously refreshed data transformation pipelines.

With traditional pipeline orchestration, engineers explicitly manage processing steps:

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

With a Dynamic Table, engineers primarily define what the target data should look like. Snowflake manages refresh execution to keep the Dynamic Table within its configured freshness objective.

```text
Source Tables
     |
     v
SELECT / Transformation
     |
     v
Dynamic Table
     |
     v
Automatically Refreshed Result
```

Dynamic Tables are useful for declarative ELT pipelines, incremental transformations, multi-layer data pipelines, continuously refreshed aggregates, curated datasets, analytics pipelines, and simplifying some Streams + Tasks architectures.

---

## 1. Imperative vs Declarative Pipelines

Traditional pipeline engineering is often imperative. You define when to run, what changes to read, how to process them, and where to write them.

Dynamic Tables use a more declarative model. You define the desired query result, freshness requirement, and compute. Snowflake handles refresh orchestration.

---

## 2. Basic Dynamic Table Architecture

```text
RAW.ORDERS
     |
     v
SELECT / TRANSFORM
     |
     v
CURATED.ORDERS_DYNAMIC
```

The Dynamic Table stores the transformed result and refreshes it over time.

---

## 3. Dynamic Table vs View

A standard view stores the SQL definition but does not materialize the query result in the same way.

```text
VIEW
 |
 v
Query executed when consumer reads
```

A Dynamic Table maintains materialized results through refresh processing:

```text
Source
  |
  v
Refresh
  |
  v
Dynamic Table
  |
  v
Consumer
```

This can move transformation work away from every downstream query.

---

## 4. Dynamic Table vs Materialized View

| Area | Dynamic Table | Materialized View |
|---|---|---|
| Primary purpose | Data pipelines | Query acceleration |
| Pipeline chaining | Yes | Not primary purpose |
| Freshness model | Target lag | Automatic maintenance |
| Transformation pipelines | Strong use case | More constrained |
| Declarative ELT | Yes | Not primary design |
| Operational model | Pipeline object | Query optimization object |

Choose based on workload purpose rather than assuming the objects are interchangeable.

---

## 5. Dynamic Tables vs Streams + Tasks

Streams + Tasks provide explicit control:

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
MERGE
  |
  v
Target
```

Dynamic Tables provide a declarative model:

```text
Source
  |
  v
Dynamic Table Definition
  |
  v
Managed Refresh
```

Streams + Tasks may be better when you need explicit CDC handling, procedural logic, custom scheduling, complex side effects, explicit replay control, or custom orchestration.

Dynamic Tables may be better when the primary requirement is to keep a transformed dataset reasonably current.

---

## 6. Create a Lab Source Table

```sql
CREATE OR REPLACE TABLE snowflake_tutorial.raw.orders_dt_source (
    order_id        NUMBER,
    customer_id     NUMBER,
    order_status    VARCHAR,
    order_amount    NUMBER(12,2),
    order_timestamp TIMESTAMP_NTZ
);

INSERT INTO snowflake_tutorial.raw.orders_dt_source
VALUES
    (1001, 501, 'COMPLETE', 100.00, CURRENT_TIMESTAMP()),
    (1002, 502, 'NEW',      200.00, CURRENT_TIMESTAMP()),
    (1003, 501, 'COMPLETE', 150.00, CURRENT_TIMESTAMP());

SELECT *
FROM snowflake_tutorial.raw.orders_dt_source;
```

---

## 7. Create a Dynamic Table

```sql
CREATE OR REPLACE DYNAMIC TABLE snowflake_tutorial.raw.completed_orders_dt
    TARGET_LAG = '5 minutes'
    WAREHOUSE = tutorial_wh
AS
SELECT
    order_id,
    customer_id,
    order_amount,
    order_timestamp
FROM snowflake_tutorial.raw.orders_dt_source
WHERE order_status = 'COMPLETE';
```

The important components are DYNAMIC TABLE, TARGET_LAG, WAREHOUSE, and SELECT.

---

## 8. TARGET_LAG

`TARGET_LAG` expresses the desired freshness relationship between the Dynamic Table and its upstream data.

```sql
TARGET_LAG = '5 minutes'
```

This should be interpreted as a freshness target rather than "run exactly every five minutes."

Dynamic Tables are freshness-driven, not simply cron-driven.

---

## 9. Target Lag Is Not a Fixed Schedule

Do not design operations around an assumption that a five-minute target lag means exact executions at 12:00, 12:05, 12:10, and so on.

The target lag describes desired freshness. Snowflake determines refresh timing based on the Dynamic Table pipeline and refresh requirements.

If exact clock-time execution is a hard business requirement, Tasks may be more appropriate.

---

## 10. DOWNSTREAM Target Lag

Dynamic Tables can participate in dependency chains.

```sql
TARGET_LAG = DOWNSTREAM
```

This is useful for intermediate Dynamic Tables whose refresh behavior should be driven by downstream pipeline requirements.

```text
RAW
 |
 v
DT_STAGE
TARGET_LAG = DOWNSTREAM
 |
 v
DT_CURATED
TARGET_LAG = '10 minutes'
```

---

## 11. Multi-Layer Dynamic Table Pipeline

Dynamic Tables can be chained.

```text
RAW TABLES
     |
     v
STAGING DYNAMIC TABLE
     |
     v
CURATED DYNAMIC TABLE
     |
     v
AGGREGATE DYNAMIC TABLE
```

This supports layered data architecture without requiring a separate Task for every transformation step.

---

## 12. Create an Intermediate Dynamic Table

```sql
CREATE OR REPLACE DYNAMIC TABLE snowflake_tutorial.raw.orders_clean_dt
    TARGET_LAG = DOWNSTREAM
    WAREHOUSE = tutorial_wh
AS
SELECT
    order_id,
    customer_id,
    UPPER(order_status) AS order_status,
    order_amount,
    order_timestamp
FROM snowflake_tutorial.raw.orders_dt_source
WHERE order_id IS NOT NULL;
```

---

## 13. Create an Aggregate Dynamic Table

```sql
CREATE OR REPLACE DYNAMIC TABLE snowflake_tutorial.raw.customer_order_summary_dt
    TARGET_LAG = '10 minutes'
    WAREHOUSE = tutorial_wh
AS
SELECT
    customer_id,
    COUNT(*) AS order_count,
    SUM(order_amount) AS total_order_amount,
    MAX(order_timestamp) AS latest_order_timestamp
FROM snowflake_tutorial.raw.orders_clean_dt
WHERE order_status = 'COMPLETE'
GROUP BY customer_id;
```

Architecture:

```text
ORDERS_DT_SOURCE
      |
      v
ORDERS_CLEAN_DT
      |
      v
CUSTOMER_ORDER_SUMMARY_DT
```

---

## 14. Query a Dynamic Table

```sql
SELECT *
FROM snowflake_tutorial.raw.customer_order_summary_dt
ORDER BY customer_id;
```

Downstream consumers do not need to manually trigger the transformation each time they query it.

---

## 15. Add New Source Data

```sql
INSERT INTO snowflake_tutorial.raw.orders_dt_source
VALUES
    (1004, 501, 'COMPLETE', 300.00, CURRENT_TIMESTAMP());
```

The Dynamic Table pipeline should subsequently refresh according to its configured freshness behavior.

```sql
SELECT *
FROM snowflake_tutorial.raw.customer_order_summary_dt
WHERE customer_id = 501;
```

---

## 16. Refresh Modes

Dynamic Table refresh behavior can use modes such as AUTO, INCREMENTAL, and FULL.

The exact refresh capability depends on the query definition and Snowflake-supported incrementalization behavior.

Understanding refresh mode is important for performance and cost.

---

## 17. AUTO Refresh Mode

With:

```sql
REFRESH_MODE = AUTO
```

Snowflake determines an appropriate refresh mode based on the Dynamic Table definition and supported behavior.

Production teams should still inspect the resulting refresh behavior. Do not assume AUTO guarantees incremental processing.

---

## 18. INCREMENTAL Refresh

Incremental refresh attempts to process changes rather than rebuilding the entire Dynamic Table result.

```text
Source changes
      |
      v
Process affected data
      |
      v
Update Dynamic Table
```

For large datasets, this can be significantly more efficient than repeatedly recomputing everything. Not every query pattern can necessarily be incrementally refreshed.

---

## 19. FULL Refresh

Full refresh recomputes the Dynamic Table result.

```text
Source
  |
  v
Recompute full query
  |
  v
Replace refreshed result
```

For small tables this may be acceptable. For very large transformations, repeated full refreshes can be expensive.

---

## 20. Incrementalization Matters

Consider a source containing billions of rows where only a small amount changes:

```text
Total rows   = 2,000,000,000
Changed rows = 100,000
```

An incremental strategy can potentially avoid repeatedly processing the entire source, but SQL design must support efficient incremental refresh.

---

## 21. Inspect Dynamic Tables

```sql
SHOW DYNAMIC TABLES;

SHOW DYNAMIC TABLES
IN SCHEMA snowflake_tutorial.raw;

DESC DYNAMIC TABLE
snowflake_tutorial.raw.customer_order_summary_dt;
```

Operational teams should know how to inspect target lag, refresh mode, warehouse, state, source dependencies, and refresh behavior.

---

## 22. Refresh History

Dynamic Table refresh history is one of the most important troubleshooting sources.

Use Snowflake's Dynamic Table refresh history interfaces to investigate refresh start, completion, status, duration, errors, and data freshness.

When a Dynamic Table appears stale, refresh history should be checked before recreating the object.

---

## 23. Manual Refresh

During controlled testing or recovery, Dynamic Tables can support manual refresh operations where applicable.

```sql
ALTER DYNAMIC TABLE <name> REFRESH;
```

Use manual refresh carefully in production. Understand why automatic refresh is insufficient, expected compute impact, upstream dependency state, and whether the previous refresh is failing.

---

## 24. Suspend a Dynamic Table

```sql
ALTER DYNAMIC TABLE <name> SUSPEND;
```

Resume:

```sql
ALTER DYNAMIC TABLE <name> RESUME;
```

After resuming, verify refresh health and data freshness.

---

## 25. Pipeline Dependencies

Dynamic Tables can create dependency chains.

```text
RAW.CUSTOMERS ──────┐
                    |
                    v
              CUSTOMER_DT
                    |
                    +----------+
                               |
RAW.ORDERS --------> ORDER_DT  |
       |                       |
       +-----------+-----------+
                   |
                   v
            CUSTOMER_360_DT
```

When the final table becomes stale, do not investigate only the final object. The problem may exist upstream.

---

## 26. Troubleshooting Dependency Chains

Investigate from upstream to downstream:

```text
Source freshness
      |
      v
First Dynamic Table
      |
      v
Intermediate Dynamic Table
      |
      v
Final Dynamic Table
```

Ask whether source data is current, which layer first became stale, whether a refresh failed, whether SQL/schema changed, and whether the warehouse is healthy.

Find the first broken layer.

---

## 27. Schema Changes

Changes such as a column being removed or renamed, a data type changing, an object being replaced, or permissions changing can break refresh processing.

Schema changes should follow controlled deployment procedures.

---

## 28. Warehouse Considerations

Consider warehouse size, workload isolation, concurrency, queueing, auto-suspend, auto-resume, transformation complexity, and refresh duration.

Do not automatically increase warehouse size when refreshes become slow. Inspect the workload first.

---

## 29. Target Lag and Cost

Freshness has a cost.

Compare:

```sql
TARGET_LAG = '1 minute'
```

with:

```sql
TARGET_LAG = '1 hour'
```

A tighter target can require more frequent refresh activity.

Choose target lag based on actual business requirements.

---

## 30. Freshness SLA Design

Start with the business requirement.

If a dashboard SLA is 30 minutes, determine an appropriate pipeline freshness design around that requirement.

Avoid setting a one-minute target merely because it is possible when the business only requires 30-minute freshness.

---

## 31. Dynamic Tables and Data Engineering Layers

A practical architecture can use:

```text
RAW
 |
 v
CLEAN
 |
 v
CURATED
 |
 v
SERVING
```

For example:

```text
RAW.ORDERS
    |
    v
DT_ORDERS_CLEAN
    |
    v
DT_ORDER_METRICS
    |
    v
BI / ANALYTICS
```

---

## 32. Keep Transformations Understandable

Avoid one enormous Dynamic Table query containing every business rule.

Prefer logical layers such as RAW → CLEAN → ENRICHED → AGGREGATED → FINAL, while also avoiding unnecessary layering.

Each layer should have a clear purpose.

---

## 33. Dynamic Tables Are Not a Universal Replacement

Dynamic Tables do not eliminate the need for Streams, Tasks, stored procedures, external orchestration, Snowpipe, Snowpipe Streaming, or application-level workflows.

Choose the right tool:

```text
Need file ingestion?
→ Snowpipe

Need record streaming?
→ Snowpipe Streaming

Need explicit CDC?
→ Streams

Need scheduled/procedural execution?
→ Tasks

Need declarative refreshed transformations?
→ Dynamic Tables
```

---

## 34. Dynamic Tables vs Tasks Decision

Use Tasks when you need exact scheduling, procedural execution, stored procedure calls, explicit orchestration, operational side effects, or custom recovery flow.

Use Dynamic Tables when you primarily need continuously maintained query results, freshness-based transformations, declarative dependencies, or simplified transformation pipelines.

Some production architectures use both.

---

## 35. Monitoring Strategy

Monitor:

- Dynamic Table state
- refresh status
- refresh failures
- refresh duration
- target lag
- actual freshness
- warehouse utilization
- source freshness
- downstream freshness
- cost

Do not monitor only whether the object exists.

---

## 36. Data Freshness Check

```sql
SELECT
    MAX(order_timestamp) AS latest_source_event
FROM snowflake_tutorial.raw.customer_order_summary_dt;
```

Compare with the upstream source:

```sql
SELECT
    MAX(order_timestamp) AS latest_source_event
FROM snowflake_tutorial.raw.orders_dt_source;
```

This helps identify pipeline lag.

---

## 37. Troubleshooting — Dynamic Table Is Stale

Investigate:

1. Is source data current?
2. Is the Dynamic Table active?
3. What is its target lag?
4. What does refresh history show?
5. Did recent refreshes fail?
6. Did an upstream Dynamic Table fail?
7. Did source schemas change?
8. Are permissions still valid?
9. Is the configured warehouse healthy?
10. Has workload volume increased?

Do not immediately recreate the Dynamic Table.

---

## 38. Troubleshooting — Refresh Failed

Capture the exact refresh failure.

Then investigate SQL errors, schema changes, missing objects, permission issues, unsupported transformation behavior, compute problems, and upstream failures.

Preserve failure evidence before changing the object.

---

## 39. Troubleshooting — Refresh Is Slow

Investigate refresh mode, data volume, change volume, query complexity, joins, aggregations, warehouse performance, queueing, spilling, source layout, and dependency depth.

A slow refresh does not automatically mean the warehouse is undersized.

---

## 40. Troubleshooting — Cost Increased

Check whether target lag was reduced, data volume increased, refresh mode changed, full refreshes are occurring, transformation complexity increased, additional Dynamic Tables were added, warehouse size changed, or refresh duration increased.

Correlate cost increases with configuration and workload changes.

---

## 41. Troubleshooting — Downstream Table Is Stale

Suppose:

```text
RAW
 |
 v
DT_A
 |
 v
DT_B
 |
 v
DT_C
```

and DT_C is stale.

Check RAW, DT_A, DT_B, and DT_C freshness in order. Find the first layer where freshness diverges.

---

## 42. Production Operational Runbook

When a Dynamic Table pipeline becomes stale:

1. Confirm source data should be changing.
2. Check source freshness.
3. Run `SHOW DYNAMIC TABLES`.
4. Identify the affected Dynamic Table.
5. Verify target lag.
6. Verify current state.
7. Review refresh history.
8. Capture the first failed refresh.
9. Capture the exact error.
10. Inspect upstream dependencies.
11. Identify the first stale layer.
12. Check schema changes.
13. Check permissions.
14. Check warehouse/compute health.
15. Check refresh mode.
16. Check data-volume changes.
17. Correct the root cause.
18. Resume or refresh safely as required.
19. Validate target freshness.
20. Validate downstream consumers.

---

## 43. Production Best Practices

Use business-driven target lag, clear transformation layers, refresh history monitoring, source and target freshness monitoring, controlled schema changes, appropriate warehouse isolation, cost monitoring, meaningful object names, documented dependency chains, and production recovery procedures.

Avoid setting every target lag extremely low, assuming target lag is an exact schedule, assuming AUTO always means incremental, ignoring refresh mode, recreating failed objects before investigation, building unnecessarily deep dependency chains, ignoring upstream freshness, increasing warehouse size before analysis, and treating Dynamic Tables as replacements for every pipeline tool.

---

## 44. End-to-End Hands-On Lab

### Objective

Build a two-layer declarative transformation pipeline.

### Step 1 — Create source

```sql
CREATE OR REPLACE TABLE snowflake_tutorial.raw.sales_dt_lab (
    sale_id      NUMBER,
    customer_id  NUMBER,
    amount       NUMBER(12,2),
    sale_status  VARCHAR,
    sale_time    TIMESTAMP_NTZ
);
```

### Step 2 — Load source data

```sql
INSERT INTO snowflake_tutorial.raw.sales_dt_lab
VALUES
    (1, 101, 100.00, 'COMPLETE', CURRENT_TIMESTAMP()),
    (2, 102, 200.00, 'COMPLETE', CURRENT_TIMESTAMP()),
    (3, 101, 50.00,  'PENDING',  CURRENT_TIMESTAMP());
```

### Step 3 — Create clean layer

```sql
CREATE OR REPLACE DYNAMIC TABLE snowflake_tutorial.raw.sales_clean_dt
    TARGET_LAG = DOWNSTREAM
    WAREHOUSE = tutorial_wh
AS
SELECT
    sale_id,
    customer_id,
    amount,
    UPPER(sale_status) AS sale_status,
    sale_time
FROM snowflake_tutorial.raw.sales_dt_lab
WHERE sale_id IS NOT NULL;
```

### Step 4 — Create aggregate layer

```sql
CREATE OR REPLACE DYNAMIC TABLE snowflake_tutorial.raw.customer_sales_dt
    TARGET_LAG = '10 minutes'
    WAREHOUSE = tutorial_wh
AS
SELECT
    customer_id,
    COUNT(*) AS completed_sales,
    SUM(amount) AS total_sales,
    MAX(sale_time) AS latest_sale_time
FROM snowflake_tutorial.raw.sales_clean_dt
WHERE sale_status = 'COMPLETE'
GROUP BY customer_id;
```

### Step 5 — Inspect objects

```sql
SHOW DYNAMIC TABLES
IN SCHEMA snowflake_tutorial.raw;
```

### Step 6 — Query result

```sql
SELECT *
FROM snowflake_tutorial.raw.customer_sales_dt
ORDER BY customer_id;
```

### Step 7 — Add new source data

```sql
INSERT INTO snowflake_tutorial.raw.sales_dt_lab
VALUES
    (4, 101, 300.00, 'COMPLETE', CURRENT_TIMESTAMP());
```

### Step 8 — Validate eventual refresh

```sql
SELECT *
FROM snowflake_tutorial.raw.customer_sales_dt
WHERE customer_id = 101;
```

### Step 9 — Inspect freshness

```sql
SELECT MAX(sale_time)
FROM snowflake_tutorial.raw.sales_dt_lab;

SELECT MAX(latest_sale_time)
FROM snowflake_tutorial.raw.customer_sales_dt;
```

### Step 10 — Inspect refresh behavior

Review Dynamic Table state and refresh history using Snowflake monitoring interfaces available to your role.

Confirm source changes flow through the clean layer and aggregate layer until the expected result is visible.

---

## 45. Architecture Comparison

After Chapters 16–20, distinguish the major continuous-processing components:

| Requirement | Snowflake Feature |
|---|---|
| Continuously ingest files | Snowpipe |
| Continuously ingest records | Snowpipe Streaming |
| Track table changes | Streams |
| Schedule/orchestrate SQL | Tasks |
| Declaratively maintain transformed results | Dynamic Tables |

Example:

```text
Kafka
  |
  v
Snowpipe Streaming
  |
  v
RAW EVENTS
  |
  v
Dynamic Tables
  |
  v
CURATED DATA
```

Another architecture:

```text
Cloud Storage
     |
     v
Snowpipe
     |
     v
RAW TABLE
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
CURATED TABLE
```

The correct design depends on operational requirements.

---

## 46. Acceptance Criteria

The chapter is complete when you can:

- explain Dynamic Tables
- explain declarative pipelines
- distinguish Dynamic Tables from standard views
- distinguish Dynamic Tables from Materialized Views
- compare Dynamic Tables with Streams + Tasks
- create a Dynamic Table
- configure `TARGET_LAG`
- explain why target lag is not an exact schedule
- explain `TARGET_LAG = DOWNSTREAM`
- build chained Dynamic Tables
- explain AUTO, INCREMENTAL, and FULL refresh concepts
- inspect Dynamic Table definitions
- investigate refresh history
- reason about source-to-target freshness
- troubleshoot failed refreshes
- troubleshoot stale pipelines
- troubleshoot slow refreshes
- analyze Dynamic Table cost increases
- choose between Tasks and Dynamic Tables
- design a production declarative pipeline

---

## Key Takeaways

Dynamic Tables shift pipeline development from "How should I schedule and execute every transformation?" toward "What result should Snowflake maintain, and how fresh does it need to be?"

```text
Source
   |
   v
Declarative SQL
   |
   v
Dynamic Table
   |
   v
Managed Refresh
```

Production teams must understand target lag, refresh mode, refresh history, dependencies, freshness, compute, and cost.

Dynamic Tables simplify orchestration, but they do not eliminate the need for production engineering.

With Chapter 20 complete, the ingestion and continuous-processing foundation now includes:

```text
Chapter 16 — Snowpipe
Chapter 17 — Snowpipe Streaming
Chapter 18 — Streams & Change Data Capture
Chapter 19 — Tasks & Scheduled Processing
Chapter 20 — Dynamic Tables & Declarative Pipelines
```

The next chapter is **Chapter 21 — Streams + Tasks Production Pipelines**.
