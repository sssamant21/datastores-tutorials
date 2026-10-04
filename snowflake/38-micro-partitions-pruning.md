# 38 — Micro-Partitions & Pruning

## Overview

One of the most important principles in Snowflake query performance is:

> The fastest data to process is data that Snowflake does not need to scan.

Snowflake automatically organizes table data into micro-partitions and maintains metadata that can help determine which micro-partitions are relevant to a query.

When predicates allow Snowflake to eliminate irrelevant micro-partitions, the process is called **pruning**.

Conceptually:

```text
Large Table
   |
   v
Micro-Partitions
   |
   +---- MP001
   +---- MP002
   +---- MP003
   +---- MP004
   +---- ...
   |
   v
Predicate
   |
   v
Metadata Evaluation
   |
   +---- Relevant partitions → Scan
   |
   +---- Irrelevant partitions → Skip
```

Effective pruning can reduce partitions scanned, bytes scanned, warehouse work, query latency, and credit consumption.

Poor pruning can result in Snowflake scanning a large portion of a table even when the final result is small.

This chapter covers micro-partition fundamentals, immutable storage concepts, metadata, columnar storage, partition pruning, partition scan ratios, predicate selectivity, range predicates, equality predicates, date and timestamp filtering, function-wrapped predicates, casts, expression design, data distribution, natural clustering, overlap, pruning diagnosis, Query Profile, clustering information, troubleshooting, production runbooks, and hands-on testing.

---

# Part 1 — What Is a Micro-Partition?

## 1. Snowflake Storage Organization

Snowflake automatically divides table data into micro-partitions.

Users do not manually create individual micro-partitions.

```text
TABLE
 |
 +---- Micro-Partition 1
 +---- Micro-Partition 2
 +---- Micro-Partition 3
 +---- Micro-Partition 4
 +---- ...
```

## 2. Automatic Management

Snowflake manages micro-partitions automatically.

You do not perform traditional manual partition administration such as:

```text
CREATE PARTITION
DROP PARTITION
REBUILD PARTITION
```

for Snowflake micro-partitions.

## 3. Why Micro-Partitions Matter

Micro-partitions provide units of storage metadata that Snowflake can use when determining what data needs to be scanned.

This makes them fundamental to query pruning.

---

# Part 2 — Columnar Storage

## 4. Column-Oriented Organization

Snowflake stores table data in a columnar form within its managed storage architecture.

For analytical workloads, this allows Snowflake to focus processing on columns referenced by the query.

## 5. Example

Table:

```text
transactions
--------------------------------
transaction_id
customer_id
transaction_date
merchant_id
amount
status
description
source_system
```

Query:

```sql
SELECT
    customer_id,
    amount
FROM transactions
WHERE transaction_date = '2026-10-01';
```

The query does not require every column.

## 6. Projection Matters

Compare:

```sql
SELECT *
FROM transactions;
```

with:

```sql
SELECT
    customer_id,
    amount
FROM transactions;
```

Selecting only required columns can reduce unnecessary data processing and result movement.

---

# Part 3 — Micro-Partition Metadata

## 7. Metadata Concept

Snowflake maintains metadata about data stored in micro-partitions.

Conceptually, metadata can help Snowflake understand properties such as value ranges for columns.

```text
Micro-Partition 1
transaction_date:
MIN = 2026-01-01
MAX = 2026-01-07

Micro-Partition 2
transaction_date:
MIN = 2026-01-08
MAX = 2026-01-14

Micro-Partition 3
transaction_date:
MIN = 2026-01-15
MAX = 2026-01-21
```

## 8. Query

```sql
SELECT *
FROM transactions
WHERE transaction_date = '2026-01-10';
```

Conceptually Snowflake can determine:

```text
MP1 → Cannot contain Jan 10 → Skip
MP2 → Could contain Jan 10  → Scan
MP3 → Cannot contain Jan 10 → Skip
```

This is pruning.

---

# Part 4 — Partition Pruning

## 9. Definition

Partition pruning means avoiding micro-partitions that cannot contain rows needed by the query.

## 10. Conceptual Example

Suppose:

```text
Total partitions = 10,000
```

and the query requires 100 partitions. Snowflake may need to scan only approximately 1% of the micro-partitions.

## 11. Why This Matters

If each partition contains substantial data, skipping thousands of partitions can dramatically reduce query work.

---

# Part 5 — Partitions Scanned vs Total

## 12. Query Profile

Query Profile can expose useful scan information such as:

```text
Partitions scanned
Partitions total
```

These are among the most important metrics for pruning analysis.

## 13. Example — Good Pruning

```text
Partitions total   = 50,000
Partitions scanned = 250
```

Scan ratio:

```text
250 / 50,000 = 0.5%
```

This may indicate strong pruning.

## 14. Example — Poor Pruning

```text
Partitions total   = 50,000
Partitions scanned = 48,000
```

Scan ratio:

```text
96%
```

If the query asks for a narrow date range, this deserves investigation.

---

# Part 6 — Do Not Use a Universal Threshold

## 15. Context Matters

A 90% scan ratio is not automatically bad.

```sql
SELECT SUM(amount)
FROM transactions;
```

If the query genuinely requires the entire table, scanning most partitions is expected.

## 16. Better Question

Do not ask only what percentage of partitions were scanned.

Ask:

> Given the business predicate, how many partitions should reasonably need to be scanned?

---

# Part 7 — Predicate Selectivity

## 17. Selective Predicate

```sql
WHERE transaction_id = 10012345
```

If the identifier is selective and the data layout supports elimination, relatively little data may need to be scanned.

## 18. Low-Selectivity Predicate

```sql
WHERE status = 'ACTIVE'
```

If 95% of rows are ACTIVE, the predicate may provide little opportunity for pruning.

## 19. Selectivity and Pruning Are Related but Different

A predicate may return few rows but still scan many partitions.

```text
Rows returned      = 10
Partitions scanned = 50,000
```

This can happen when matching values are scattered across many micro-partitions.

---

# Part 8 — Data Distribution

## 20. Organized Data

```text
MP001 → Jan 01–Jan 03
MP002 → Jan 04–Jan 06
MP003 → Jan 07–Jan 09
MP004 → Jan 10–Jan 12
```

A narrow date query may prune efficiently.

## 21. Scattered Data

```text
MP001 → Jan–Dec
MP002 → Jan–Dec
MP003 → Jan–Dec
MP004 → Jan–Dec
```

A query for one day may need to inspect many partitions.

---

# Part 9 — Natural Clustering

## 22. Natural Data Organization

Data can sometimes become naturally organized based on ingestion patterns.

```text
Daily batch ingestion
      |
      v
Mostly increasing transaction_date
```

This can produce useful locality for date-based filtering.

## 23. Not Guaranteed Forever

As tables evolve through INSERT, UPDATE, MERGE, DELETE, backfills, and late-arriving data, data organization may change.

---

# Part 10 — Micro-Partition Immutability

## 24. Immutable Storage Concept

Existing micro-partition data is not modified in place in the same manner as a traditional mutable database page.

Data changes result in new storage structures representing the changed state.

## 25. Operational Consequence

Repeated changes, backfills, and MERGE operations can affect how values are distributed across micro-partitions over time.

This can influence pruning behavior.

---

# Part 11 — Equality Predicates

## 26. Example

```sql
SELECT *
FROM customer_events
WHERE customer_id = 1001;
```

Pruning effectiveness depends partly on how customer IDs are distributed across micro-partitions.

## 27. Scattered IDs

If customer 1001 appears across many partitions, many partitions may need evaluation/scanning.

---

# Part 12 — Range Predicates

## 28. Date Range

```sql
WHERE event_date >= '2026-10-01'
  AND event_date < '2026-10-08'
```

Range predicates often align well with metadata-driven elimination when data is suitably organized.

## 29. Timestamp Range

```sql
WHERE event_timestamp >= '2026-10-01 00:00:00'
  AND event_timestamp <  '2026-10-02 00:00:00'
```

This clearly expresses a bounded range.

---

# Part 13 — Date Filtering

## 30. Common Pattern

Suppose the column is EVENT_TIMESTAMP TIMESTAMP and a user wants one day.

A clear range predicate is:

```sql
WHERE event_timestamp >= '2026-10-01 00:00:00'
  AND event_timestamp <  '2026-10-02 00:00:00'
```

## 31. Why Half-Open Ranges?

Using >= start and < next boundary avoids ambiguity around fractional seconds and end-of-day values.

---

# Part 14 — Functions Around Filter Columns

## 32. Example

A common query is:

```sql
WHERE DATE(event_timestamp) = '2026-10-01'
```

This may be logically correct.

When investigating pruning, compare its actual Query Profile behavior with an equivalent range predicate where appropriate.

## 33. Preferred Investigation

Do not assume a function automatically prevents pruning.

Instead:

1. Run the query.
2. Capture query ID.
3. Inspect partitions scanned.
4. Rewrite using a clear range.
5. Capture another query ID.
6. Compare.

---

# Part 15 — Casting

## 34. Example

```sql
WHERE event_timestamp::DATE = '2026-10-01'
```

Determine performance from actual execution evidence rather than assuming behavior.

## 35. Production Principle

Prefer predicates that clearly express the filtering boundary and minimize unnecessary transformations when practical.

---

# Part 16 — Expressions

## 36. Complex Predicate

```sql
WHERE UPPER(customer_code) = 'ABC123'
```

If this query is performance-critical, investigate whether the expression affects efficient elimination.

## 37. Do Not Rewrite Blindly

First measure partitions scanned, bytes scanned, and execution time. Then test alternatives.

---

# Part 17 — OR Predicates

## 38. Example

```sql
WHERE region = 'EAST'
   OR event_date = '2026-10-01'
```

Complex predicate combinations can affect which partitions qualify.

## 39. Investigate

Use Query Profile to determine whether the query is scanning more data than expected.

---

# Part 18 — IN Predicates

## 40. Example

```sql
WHERE customer_id IN (
    1001,
    1002,
    1003
)
```

Pruning effectiveness depends on the values and their distribution.

---

# Part 19 — NULL Values

## 41. NULL Filtering

```sql
WHERE customer_id IS NULL
```

If NULL values are distributed broadly, many partitions may still need scanning.

## 42. Data Quality Connection

Large volumes of NULL, UNKNOWN, DEFAULT, 0, or -1 values can affect both data quality and query behavior.

---

# Part 20 — Multiple Predicates

## 43. Example

```sql
WHERE event_date = '2026-10-01'
  AND region = 'EAST'
  AND status = 'COMPLETE'
```

Snowflake can use available metadata and optimization strategies to determine relevant data.

## 44. Strongest Predicate

Often one predicate provides most of the elimination.

During analysis, determine which column actually drives pruning.

---

# Part 21 — Join Filters and Pruning

## 45. Example

```sql
SELECT ...
FROM transactions t
JOIN customers c
    ON t.customer_id = c.customer_id
WHERE t.transaction_date >= '2026-10-01';
```

The date predicate can reduce transaction data before expensive downstream work when the plan permits.

## 46. Production Principle

Filter large fact tables as narrowly as business requirements allow.

---

# Part 22 — CTEs and Views

## 47. CTE Example

```sql
WITH recent_transactions AS (
    SELECT *
    FROM transactions
    WHERE transaction_date >= '2026-10-01'
)
SELECT ...
FROM recent_transactions;
```

Snowflake's optimizer determines the physical plan.

## 48. Do Not Judge by SQL Formatting

A CTE does not necessarily imply physical materialization.

Use Query Profile to determine what actually happened.

---

# Part 23 — Secure and Regular Views

## 49. View Layers

```text
Application
   |
   v
View
   |
   v
View
   |
   v
Base Table
```

When performance is poor, identify which base tables are actually scanned.

## 50. Query Profile

Do not stop at the logical view definition. Follow execution to the scan operators.

---

# Part 24 — Table Growth

## 51. Growth Changes Performance

A query that originally ran against 100 GB may behave differently when the table grows to 10 TB.

## 52. Monitor

Track table size, partition count, rows, pruning, bytes scanned, and query latency.

---

# Part 25 — Backfills

## 53. Historical Loads

```text
Current daily data
Historical 5-year backfill
Current daily data
```

## 54. Why It Matters

Historical values may become distributed differently than the original ingestion pattern.

Validate pruning after major backfills.

---

# Part 26 — MERGE Workloads

## 55. Incremental Pipelines

```sql
MERGE INTO target t
USING source s
ON t.id = s.id
WHEN MATCHED THEN UPDATE ...
WHEN NOT MATCHED THEN INSERT ...;
```

## 56. Monitor Long-Term Behavior

For large frequently updated tables, monitor query pruning, table growth, clustering characteristics, and MERGE performance.

---

# Part 27 — DELETE and UPDATE

## 57. Changes to Existing Data

Frequent modifications can influence physical organization as Snowflake creates new micro-partition versions.

## 58. Production Review

Do not assume a table's pruning characteristics remain constant forever.

---

# Part 28 — Clustering

## 59. When Natural Organization Is Insufficient

For some large tables, frequently used predicates may not align well with natural data organization.

Snowflake supports clustering keys for appropriate workloads.

## 60. Important Warning

Do not add clustering merely because a table is large.

First prove:

```text
Poor pruning
+
Important repeated workload
+
Suitable clustering expression
+
Expected benefit > maintenance cost
```

Chapter 39 covers clustering deeply.

---

# Part 29 — Clustering Depth and Overlap

## 61. Conceptual Overlap

```text
MP1 customer_id 1–100
MP2 customer_id 50–150
MP3 customer_id 75–200
MP4 customer_id 100–250
```

Ranges overlap heavily.

## 62. Lower Overlap Concept

```text
MP1 customer_id 1–100
MP2 customer_id 101–200
MP3 customer_id 201–300
MP4 customer_id 301–400
```

A narrow customer range may require fewer partitions.

## 63. Real Data Is More Complex

These examples do not imply that perfectly ordered partitions are required. They illustrate why value locality can affect pruning.

---

# Part 30 — SYSTEM$CLUSTERING_INFORMATION

## 64. Clustering Analysis

Snowflake provides system functions that can help evaluate clustering characteristics.

A commonly used function is:

```sql
SELECT SYSTEM$CLUSTERING_INFORMATION(
    'DATABASE.SCHEMA.TABLE',
    '(COLUMN_NAME)'
);
```

Use current Snowflake documentation for exact supported syntax and interpretation.

## 65. What to Evaluate

Clustering information can help investigate partition overlap, clustering depth, and distribution characteristics.

---

# Part 31 — Query Profile Investigation

## 66. Start with Scan Operator

For pruning problems, inspect the TableScan.

Capture table, partitions scanned, partitions total, bytes scanned, and filter.

## 67. Example

```text
Table              = EVENTS
Partitions total   = 80,000
Partitions scanned = 76,000
Bytes scanned      = 7.2 TB
Predicate           = one day
```

This is a strong signal to investigate data organization and predicate behavior.

---

# Part 32 — Establish a Baseline

## 68. Baseline Metrics

Before making changes record query ID, execution time, warehouse, warehouse size, partitions total, partitions scanned, bytes scanned, and rows returned.

## 69. Why?

Without a baseline, you cannot prove improvement.

---

# Part 33 — Compare Equivalent Predicates

## 70. Test A

```sql
WHERE DATE(event_timestamp) = '2026-10-01'
```

## 71. Test B

```sql
WHERE event_timestamp >= '2026-10-01 00:00:00'
  AND event_timestamp <  '2026-10-02 00:00:00'
```

## 72. Compare

| Metric | Test A | Test B |
|---|---:|---:|
| Partitions scanned | | |
| Bytes scanned | | |
| Execution time | | |
| Result rows | | |

Do not declare one better without evidence.

---

# Part 34 — Result Correctness

## 73. Performance Is Secondary to Correctness

Any rewritten predicate must return the correct business result.

Validate row count, boundary timestamps, NULL behavior, timezone behavior, and business totals.

---

# Part 35 — Time Zones

## 74. Timestamp Filtering

Date boundaries can become complicated with TIMESTAMP_NTZ, TIMESTAMP_LTZ, TIMESTAMP_TZ, session timezone, and application timezone.

## 75. Production Rule

Do not change timestamp predicates solely for performance without validating timezone semantics.

---

# Part 36 — Common Pruning Mistakes

## 76. Mistake — Assume Small Result Means Small Scan

```text
Rows returned = 1
Bytes scanned = 3 TB
```

A tiny result does not imply efficient pruning.

## 77. Mistake — Assume Large Table Requires Clustering

A large table with excellent natural pruning may not need an explicit clustering key.

## 78. Mistake — Add Many Clustering Columns

More clustering expressions do not automatically improve performance and can increase maintenance complexity/cost.

## 79. Mistake — Ignore Query Patterns

Optimize for important recurring workloads, not hypothetical predicates.

## 80. Mistake — Ignore Cost

Performance improvement must be evaluated against clustering and compute costs.

---

# Part 37 — Production Pruning Troubleshooting Workflow

## 81. Step 1 — Capture Query ID

Always start with evidence.

## 82. Step 2 — Confirm Scan Is the Bottleneck

Do not optimize pruning if the real problem is queueing, join explosion, remote spill, or external function latency.

## 83. Step 3 — Identify TableScan

Find the dominant table scan.

## 84. Step 4 — Record Partition Metrics

Capture partitions total and partitions scanned.

## 85. Step 5 — Record Bytes Scanned

Determine the actual data volume processed.

## 86. Step 6 — Review Predicate

Identify equality, range, function, cast, expression, OR, or IN behavior.

## 87. Step 7 — Understand Data Distribution

Determine whether the filter column is naturally organized or broadly scattered.

## 88. Step 8 — Compare Known-Good Queries

Find similar queries with better pruning if available.

## 89. Step 9 — Test Predicate Improvements

Use equivalent predicates where semantically valid.

## 90. Step 10 — Evaluate Clustering

Only after confirming persistent poor pruning on an important workload.

---

# Part 38 — Production Example: Date Pruning

## 91. Scenario

A 20 TB events table receives daily data.

```sql
SELECT
    event_type,
    COUNT(*)
FROM events
WHERE event_timestamp >= '2026-10-01 00:00:00'
  AND event_timestamp <  '2026-10-02 00:00:00'
GROUP BY event_type;
```

## 92. Expected Pattern

If data is well organized by event time, the query should generally avoid scanning historical partitions unrelated to the requested day.

## 93. Incident Signal

```text
Partitions total   = 120,000
Partitions scanned = 110,000
```

That deserves investigation.

---

# Part 39 — Production Example: Customer Lookup

## 94. Scenario

```sql
SELECT *
FROM claims
WHERE patient_id = 123456;
```

Table size: 15 TB.

Query Profile:

```text
Partitions total   = 90,000
Partitions scanned = 85,000
```

## 95. Interpretation

If patient lookups are frequent and latency-sensitive, the physical organization may not support this access pattern efficiently.

Possible options can include clustering, Search Optimization Service, an alternative data model, or a precomputed access structure.

Later chapters cover these options.

---

# Part 40 — Search Optimization vs Clustering

## 96. Do Not Confuse Them

Conceptually:

```text
Large range/filter workloads
        |
        v
Clustering may help

Highly selective point-lookups
        |
        v
Search Optimization may help
```

This is a simplified decision model.

Chapter 41 covers Search Optimization Service.

---

# Part 41 — Monitoring Pruning Over Time

## 97. Why Monitor?

A table may perform well today but degrade as data grows, backfills occur, MERGE increases, or query patterns change.

## 98. Useful Baseline

For critical queries track query pattern, partitions scanned, partitions total, bytes scanned, execution time, and warehouse.

---

# Part 42 — Incident Runbook

## 99. Poor Pruning Runbook

1. Capture query ID.
2. Confirm execution is slow.
3. Confirm scan dominates.
4. Identify table.
5. Record table size.
6. Record partitions total.
7. Record partitions scanned.
8. Record bytes scanned.
9. Record predicate.
10. Validate expected selectivity.
11. Check selected columns.
12. Review function/cast usage.
13. Review range boundaries.
14. Validate timestamp semantics.
15. Compare known-good execution.
16. Review recent table growth.
17. Review recent backfills.
18. Review MERGE/UPDATE patterns.
19. Review data distribution.
20. Evaluate clustering characteristics.
21. Test equivalent predicate.
22. Capture new query ID.
23. Compare scan metrics.
24. Validate result correctness.
25. Evaluate clustering only if needed.
26. Evaluate other optimization features if appropriate.
27. Validate cost.
28. Document root cause.

---

# Part 43 — Evidence Template

## 100. Pruning Investigation

```text
Query ID:

Table:
Table size:

Warehouse:
Warehouse size:

Execution time:

Filter predicate:

Partitions total:
Partitions scanned:
Scan ratio:

Bytes scanned:

Rows returned:

Expected selectivity:

Observed pruning:

Recent table growth:
Recent backfill:
Recent MERGE activity:

Clustering information:

Likely root cause:

Recommended remediation:

Before/after validation:
```

---

# Part 44 — Hands-On Lab

## 101. Lab Objective

Observe how data distribution and predicates affect partition pruning.

Use a non-production environment.

## 102. Create Database

```sql
CREATE OR REPLACE DATABASE pruning_lab;
```

## 103. Create Schema

```sql
CREATE OR REPLACE SCHEMA pruning_lab.demo;
```

## 104. Create Events Table

```sql
CREATE OR REPLACE TABLE
pruning_lab.demo.events (
    event_id NUMBER,
    customer_id NUMBER,
    event_date DATE,
    event_timestamp TIMESTAMP_NTZ,
    region STRING,
    amount NUMBER(12,2)
);
```

## 105. Generate Synthetic Data

```sql
INSERT INTO pruning_lab.demo.events
SELECT
    SEQ4(),
    MOD(SEQ4(), 100000),
    DATEADD(
        day,
        -MOD(SEQ4(), 365),
        CURRENT_DATE()
    ),
    DATEADD(
        second,
        -MOD(SEQ4(), 31536000),
        CURRENT_TIMESTAMP()
    ),
    CASE MOD(SEQ4(), 4)
        WHEN 0 THEN 'EAST'
        WHEN 1 THEN 'WEST'
        WHEN 2 THEN 'SOUTH'
        ELSE 'NORTH'
    END,
    MOD(SEQ4(), 100000) / 100.0
FROM TABLE(GENERATOR(ROWCOUNT => 5000000));
```

All generated data is synthetic.

## 106. Test 1 — Full Scan

```sql
SELECT
    COUNT(*),
    SUM(amount)
FROM pruning_lab.demo.events;
```

Capture the query ID and record partitions total, partitions scanned, bytes scanned, and execution time.

## 107. Test 2 — Date Predicate

```sql
SELECT
    COUNT(*),
    SUM(amount)
FROM pruning_lab.demo.events
WHERE event_date = CURRENT_DATE();
```

Capture another query ID and compare scan metrics.

## 108. Test 3 — Range Predicate

```sql
SELECT
    COUNT(*),
    SUM(amount)
FROM pruning_lab.demo.events
WHERE event_timestamp >= DATE_TRUNC('DAY', CURRENT_TIMESTAMP())
  AND event_timestamp < DATEADD(
        day,
        1,
        DATE_TRUNC('DAY', CURRENT_TIMESTAMP())
      );
```

Inspect Query Profile.

## 109. Test 4 — Function Predicate

```sql
SELECT
    COUNT(*),
    SUM(amount)
FROM pruning_lab.demo.events
WHERE DATE(event_timestamp) = CURRENT_DATE();
```

Capture the query ID and compare with Test 3.

Do not assume which is faster before examining the profile.

## 110. Test 5 — Region Predicate

```sql
SELECT
    COUNT(*)
FROM pruning_lab.demo.events
WHERE region = 'EAST';
```

Because approximately one-quarter of generated rows use EAST, compare how this predicate behaves relative to the date predicate.

## 111. Test 6 — Customer Predicate

```sql
SELECT *
FROM pruning_lab.demo.events
WHERE customer_id = 1001;
```

Inspect rows returned, partitions scanned, and bytes scanned.

This demonstrates that a highly selective result does not necessarily guarantee a small physical scan.

## 112. Record Results

| Test | Partitions Total | Partitions Scanned | Bytes Scanned | Execution |
|---|---:|---:|---:|---:|
| Full scan | | | | |
| Date | | | | |
| Timestamp range | | | | |
| DATE function | | | | |
| Region | | | | |
| Customer | | | | |

## 113. Compare Results

Ask which predicate pruned best, which scanned most data, whether selectivity matched pruning, whether function usage changed pruning, and how data distribution affected results.

## 114. Optional Clustering Investigation

Use an appropriate clustering-information function to inspect a candidate column.

```sql
SELECT SYSTEM$CLUSTERING_INFORMATION(
    'PRUNING_LAB.DEMO.EVENTS',
    '(EVENT_DATE)'
);
```

Interpret results using current Snowflake documentation.

## 115. Cleanup

```sql
DROP DATABASE IF EXISTS pruning_lab;
```

---

# Part 45 — Production Review Checklist

## 116. Before Changing SQL

- Query ID captured
- Query Profile reviewed
- Scan confirmed as bottleneck
- Partitions scanned recorded
- Partitions total recorded
- Bytes scanned recorded
- Result correctness baseline captured

## 117. Before Adding Clustering

- Table is sufficiently large
- Important workload has poor pruning
- Predicate is recurring
- Candidate clustering expression identified
- Clustering information reviewed
- Maintenance cost considered
- Before/after measurement plan exists

## 118. Before Using Search Optimization

- Access pattern is highly selective
- Point-lookup behavior confirmed
- Current pruning is insufficient
- Cost evaluated
- Search Optimization suitability reviewed

---

# Part 46 — Operational Principles

## 119. Optimize Scanning Before Scaling Compute

If a query scans 8 TB but should logically need 100 GB, increasing warehouse size treats the symptom.

Reducing unnecessary scanning can attack the root cause.

## 120. Query Profile Is the Evidence

Do not say:

> Pruning looks bad.

Say:

> The query requested one day of data but scanned 110,000 of 120,000 micro-partitions and 9.4 TB.

That is actionable evidence.

## 121. Validate Cost

Improving pruning can reduce both latency and compute work. Features such as clustering can introduce their own cost.

Measure the entire tradeoff.

## 122. Optimize Important Workloads

Prioritize production SLA queries, high-frequency queries, high-credit queries, customer-facing queries, and critical pipelines.

---

# Acceptance Criteria

The chapter is complete when you can:

- explain Snowflake micro-partitions
- explain automatic micro-partition management
- understand columnar storage
- explain micro-partition metadata
- explain partition pruning
- compare partitions scanned vs total
- calculate a conceptual scan ratio
- avoid universal pruning thresholds
- explain predicate selectivity
- distinguish selectivity from pruning
- explain data distribution effects
- understand natural clustering
- understand immutable micro-partition concepts
- analyze equality predicates
- analyze range predicates
- design clear date and timestamp ranges
- evaluate function-wrapped predicates
- evaluate casts and expressions
- analyze OR and IN predicates
- understand NULL/default-value effects
- analyze multiple predicates
- understand filtering before downstream work
- avoid assumptions about CTE materialization
- trace views to base-table scans
- understand table-growth effects
- understand backfill effects
- understand MERGE/UPDATE effects
- explain clustering conceptually
- understand overlap and clustering depth
- use clustering information as an investigation tool
- analyze TableScan metrics
- establish a pruning baseline
- compare equivalent predicates
- validate result correctness
- validate timestamp/timezone semantics
- avoid common pruning mistakes
- execute a production pruning investigation
- evaluate clustering only after evidence
- distinguish clustering from Search Optimization use cases
- monitor pruning over time
- execute the poor-pruning incident runbook
- capture pruning evidence consistently
- perform a hands-on pruning lab
- validate both performance and cost

---

## Key Takeaways

Snowflake automatically stores table data in micro-partitions.

```text
Table
 |
 v
Micro-Partitions
 |
 v
Metadata
 |
 v
Query Predicate
 |
 +---- Cannot Match → Skip
 |
 +---- Could Match → Scan
```

The goal is not necessarily to scan zero partitions.

The goal is:

> Avoid scanning partitions that cannot contribute to the result.

When troubleshooting, capture query ID, partitions total, partitions scanned, bytes scanned, predicate, and execution time.

A small result does not guarantee an efficient scan. One row returned can still involve several terabytes scanned.

Likewise, scanning most partitions is not automatically wrong if the query genuinely needs most of the table.

Always evaluate pruning against the **business predicate and expected data scope**.

For poor pruning:

```text
Confirm scan bottleneck
        |
        v
Measure partitions
        |
        v
Review predicate
        |
        v
Understand data distribution
        |
        v
Test equivalent query
        |
        v
Evaluate physical optimization
```

Do not immediately add clustering.

First prove that poor pruning is a meaningful, recurring production problem.

The next chapter is **Chapter 39 — Clustering & Automatic Clustering**.
