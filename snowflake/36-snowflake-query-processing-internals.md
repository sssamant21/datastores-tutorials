# 36 — Snowflake Query Processing Internals

## Overview

Troubleshooting Snowflake performance requires understanding what happens between submitting SQL and receiving the result.

A slow query is not automatically a warehouse-sizing problem. Delay can originate from query submission, authentication and authorization, parsing, optimization, Cloud Services, warehouse queueing, data scanning, micro-partition pruning, joins, aggregation, sorting, data redistribution, local spilling, remote spilling, external operations, or result production.

A production engineer should therefore avoid starting with "increase the warehouse size." Instead ask:

> Where is the query spending its time?

This chapter builds the mental model required to answer that question.

It covers Snowflake query lifecycle, Cloud Services, query compilation, parsing and validation, optimization, query plans, virtual warehouses, micro-partition scanning, pruning, parallel execution, joins, aggregation, sorting, data redistribution, memory pressure, local and remote spilling, queueing, concurrency, caching, metadata operations, external operations, Query Profile concepts, and production troubleshooting.

---

# Part 1 — Snowflake Query Architecture

## 1. Three Major Architectural Layers

At a high level, Snowflake separates:

```text
Cloud Services
      |
      v
Compute
      |
      v
Storage
```

These layers interact during query execution.

## 2. Cloud Services

Cloud Services performs control-plane and coordination functions such as authentication, authorization, metadata management, query parsing, query optimization, transaction coordination, and infrastructure coordination.

The exact responsibilities and implementation details can evolve, so use current Snowflake documentation for version-specific behavior.

## 3. Compute

Virtual warehouses provide compute resources for executing most SQL workloads.

Examples:

```text
ETL_WH
BI_WH
REPORTING_WH
DATA_SCIENCE_WH
```

## 4. Storage

Snowflake stores table data in its managed storage layer. Compute and storage are separated, allowing warehouses to scale independently from stored data volume.

---

# Part 2 — Query Lifecycle

## 5. Simplified Query Flow

```text
Client
  |
  v
Cloud Services
  |
  +---- Parse
  +---- Validate
  +---- Optimize
  |
  v
Virtual Warehouse
  |
  +---- Scan
  +---- Filter
  +---- Join
  +---- Aggregate
  +---- Sort
  |
  v
Result
```

## 6. Query Submission

A query may arrive through Snowsight, Snowflake CLI, Python Connector, JDBC, ODBC, Snowpark, a BI tool, ETL platform, or application.

Before execution, Snowflake must understand and authorize the request.

---

# Part 3 — Parsing

## 7. SQL Parsing

Snowflake parses SQL to determine its structure.

```sql
SELECT
    customer_id,
    SUM(amount)
FROM sales
WHERE order_date >= '2026-01-01'
GROUP BY customer_id;
```

Snowflake identifies table access, column access, filters, aggregation, and grouping.

## 8. Syntax Errors

Invalid SQL can fail before warehouse execution. This is not a warehouse performance problem.

---

# Part 4 — Validation

## 9. Object Resolution

Snowflake resolves referenced databases, schemas, tables, views, columns, and functions.

## 10. Authorization

Snowflake evaluates whether the current security context has required privileges.

A query may fail because of missing USAGE, SELECT, function privileges, warehouse access, or policy restrictions.

This is different from slow warehouse execution.

---

# Part 5 — Query Compilation

## 11. Compilation Phase

Snowflake prepares the query for execution. Compilation-related work can include parsing, object resolution, security evaluation, metadata lookup, optimization, and plan generation.

## 12. Compilation vs Execution

Conceptually:

```text
Total Query Time
      |
      +---- Compilation
      +---- Queueing
      +---- Execution
      +---- Other coordination
```

This distinction is important during troubleshooting.

---

# Part 6 — Query Optimization

## 13. Cost-Based Optimization

Snowflake's optimizer determines an execution strategy based on available information about the query and data.

Potential decisions include scan strategy, filter placement, join strategy, join order, aggregation strategy, data movement, and partition pruning.

## 14. Declarative SQL

When you write:

```sql
SELECT *
FROM orders
WHERE customer_id = 1001;
```

you describe the desired result rather than the physical execution algorithm. Snowflake determines the execution plan.

## 15. Optimizer Goal

The optimizer attempts to produce an efficient execution strategy. Query design and data layout still matter, and poor SQL can force expensive work.

---

# Part 7 — Execution Plan

## 16. Logical Operations

A query can contain operations such as:

```text
TableScan
Filter
Join
Aggregate
Sort
Window
Union
Result
```

## 17. Query Profile

After execution, Query Profile provides visibility into how Snowflake executed the query.

This becomes one of the most important tools for performance troubleshooting.

Chapter 37 covers Query Profile in depth.

---

# Part 8 — Virtual Warehouse Execution

## 18. Warehouse Role

The virtual warehouse supplies compute resources for query execution, including scanning, filtering, joining, aggregating, sorting, window functions, and data transformation.

## 19. Warehouse Size

Larger warehouses provide more compute resources:

```text
X-Small
Small
Medium
Large
X-Large
...
```

But larger does not automatically mean proportionally faster for every query.

## 20. Why?

A query may be limited by poor pruning, large intermediate results, data skew, queueing, spilling, expensive joins, Cloud Services work, or external operations.

Warehouse resizing does not solve every problem.

---

# Part 9 — Parallel Processing

## 21. Distributed Execution

Snowflake can divide query work across compute resources.

```text
Query
  |
  +---- Worker
  +---- Worker
  +---- Worker
  +---- Worker
```

This allows large datasets to be processed in parallel.

## 22. Parallelism

Operations that can benefit from parallelism include table scans, aggregations, joins, sorting, and data loading.

The exact execution strategy depends on the query.

---

# Part 10 — Micro-Partitions

## 23. Snowflake Storage Organization

Snowflake automatically organizes table data into micro-partitions. Applications do not manually create these micro-partitions.

## 24. Metadata

Snowflake maintains metadata about micro-partitions that can help determine whether partitions need to be scanned.

## 25. Why This Matters

If a table contains 10 TB but a query needs only a small date range, efficient pruning can prevent unnecessary scanning of much of the table.

---

# Part 11 — Partition Pruning

## 26. Pruning Concept

```sql
SELECT *
FROM orders
WHERE order_date = '2026-10-01';
```

Conceptually:

```text
All Micro-Partitions
        |
        v
Metadata Evaluation
        |
        +---- Relevant → Scan
        +---- Irrelevant → Skip
```

## 27. Good Pruning

```text
Less data scanned
      |
      v
Less compute work
      |
      v
Potentially faster query
```

## 28. Poor Pruning

Poor pruning can cause more partitions scanned, more bytes scanned, more compute, longer execution, and higher credit consumption.

## 29. Important Principle

Performance optimization is often about reducing unnecessary work, not simply increasing compute.

---

# Part 12 — Filters

## 30. Selective Filters

```sql
SELECT
    customer_id,
    amount
FROM sales
WHERE transaction_date >= '2026-10-01'
  AND transaction_date < '2026-10-02';
```

A selective predicate may allow Snowflake to eliminate irrelevant data.

## 31. Broad Query

```sql
SELECT *
FROM sales;
```

This may require substantially more scanning.

## 32. Avoid Unnecessary Columns

Compare selecting every column with selecting only required columns. Projection can reduce unnecessary work and result/data movement.

---

# Part 13 — Joins

## 33. Join Processing

```sql
SELECT
    o.order_id,
    c.customer_name
FROM orders o
JOIN customers c
    ON o.customer_id = c.customer_id;
```

Snowflake must combine matching rows from both inputs.

## 34. Join Cost

Join performance depends on input size, filter selectivity, join cardinality, data distribution, intermediate result size, and available memory.

## 35. Exploding Joins

An unexpectedly many-to-many join can produce a massive intermediate result even when each input looks manageable.

## 36. Symptoms

Look for large intermediate row counts, long join operators, memory pressure, spilling, and high bytes processed.

---

# Part 14 — Join Filtering

## 37. Filter Early Conceptually

If only a narrow date range is required, express predicates clearly so irrelevant data can be eliminated before expensive downstream work where the optimizer can do so.

## 38. Optimizer Behavior

Snowflake may push predicates and reorganize operations. SQL should still clearly express the smallest required dataset.

---

# Part 15 — Aggregation

## 39. Aggregation Example

```sql
SELECT
    region,
    SUM(amount)
FROM sales
GROUP BY region;
```

Snowflake processes input rows and combines them into groups.

## 40. High Cardinality

Grouping by a high-cardinality identifier can produce vastly more groups than grouping by a small domain such as region.

## 41. Memory Requirements

Large aggregations can require substantial memory. If memory is insufficient, spilling may occur.

---

# Part 16 — Sorting

## 42. ORDER BY

```sql
SELECT *
FROM sales
ORDER BY transaction_timestamp;
```

Sorting large result sets can be expensive.

## 43. Sorting Work

Sorting may require reading input, redistributing data, holding intermediate state, comparing values, and producing ordered output.

## 44. Avoid Unnecessary Sorting

Do not add ORDER BY unless the consumer requires ordered output.

---

# Part 17 — Window Functions

## 45. Example

```sql
SELECT
    customer_id,
    transaction_date,
    ROW_NUMBER() OVER (
        PARTITION BY customer_id
        ORDER BY transaction_date DESC
    ) AS rn
FROM transactions;
```

## 46. Processing Requirements

Window functions can involve partitioning, sorting, intermediate state, and memory. They are powerful but can be expensive on very large datasets.

---

# Part 18 — Data Redistribution

## 47. Distributed Processing

```text
Worker A ----\
Worker B -----+---- Redistribution ----> New Processing Stage
Worker C -----+
Worker D ----/
```

## 48. Why Redistribution Happens

Examples include joins, GROUP BY, DISTINCT, window functions, and sorting.

## 49. Cost

Large data redistribution can increase execution time. Reduce unnecessary input before expensive distributed operations where possible.

---

# Part 19 — Data Skew

## 50. What Is Skew?

A key distribution such as:

```text
A = 1%
B = 1%
C = 1%
UNKNOWN = 97%
```

can create uneven workloads.

## 51. Impact

```text
Worker 1 → Small work
Worker 2 → Small work
Worker 3 → Small work
Worker 4 → Huge work
```

The query can be limited by the slowest portion.

## 52. Troubleshooting

Look for uneven operator timing, unexpectedly large intermediate data, dominant key values, NULL-heavy join keys, and default/sentinel values.

---

# Part 20 — Memory

## 53. In-Memory Processing

Snowflake uses warehouse resources to process intermediate query data. Joins, aggregation, and sorting may require significant memory.

## 54. Memory Pressure

If an operation requires more memory than available, Snowflake may spill intermediate data.

---

# Part 21 — Local Spilling

## 55. What Is Local Spill?

When intermediate data cannot remain entirely in memory, some data may be written to local storage associated with compute.

```text
Memory
  |
  | insufficient
  v
Local Storage
```

## 56. Performance Impact

Local storage is slower than memory. Significant local spilling can increase execution time.

---

# Part 22 — Remote Spilling

## 57. What Is Remote Spill?

If processing pressure exceeds available memory/local capacity, intermediate data can spill to remote storage.

```text
Memory
  |
  v
Local Storage
  |
  v
Remote Storage
```

## 58. Performance Impact

Remote spilling is generally much more expensive than processing in memory and is an important performance signal.

## 59. Typical Causes

Possible causes include very large joins, large sorts, high-cardinality aggregations, huge intermediate datasets, insufficient warehouse resources, poor filtering, and join explosion.

---

# Part 23 — Spill Troubleshooting

## 60. Do Not Immediately Resize

If remote spilling occurs, ask whether the query processes too much data, pruning is poor, joins explode, unnecessary sorts occur, filters can reduce input, or the warehouse is genuinely undersized.

## 61. Corrective Actions

Depending on root cause: improve filtering, improve pruning, fix join logic, reduce intermediate data, remove unnecessary sorting, break complex processing into stages, or increase warehouse size when justified.

---

# Part 24 — Queueing

## 62. What Is Queueing?

A query may be ready to execute but wait because warehouse resources are busy.

```text
Queries
  |
  v
Queue
  |
  v
Warehouse
```

## 63. Queueing Is Not the Same as Slow Execution

If queue time is 90 seconds and execution is 10 seconds, the SQL executed quickly even though the user experienced roughly 100 seconds of latency.

## 64. Correct Diagnosis

The primary issue is concurrency or warehouse capacity, not necessarily bad SQL.

---

# Part 25 — Concurrency

## 65. Concurrent Workloads

A warehouse may simultaneously receive dashboards, ETL, ad hoc analytics, data science, exports, and scheduled jobs.

## 66. Resource Competition

Even efficient queries can create contention when many execute simultaneously.

## 67. Workload Isolation

```text
ETL_WH
BI_WH
ADHOC_WH
DATA_SCIENCE_WH
```

Separating workload classes can reduce interference.

---

# Part 26 — Multi-Cluster Warehouses

## 68. Scaling Concurrency

Multi-cluster warehouses can add clusters to handle concurrent workloads according to configuration. They primarily address concurrency rather than making a single query inherently faster.

## 69. Important Distinction

```text
Scale Up
    |
    v
More resources per cluster

Scale Out
    |
    v
More clusters for concurrency
```

---

# Part 27 — Warehouse Startup

## 70. Suspended Warehouse

If a warehouse is suspended, Snowflake may need to resume it before query execution.

## 71. User Experience

Startup/resume delay may contribute to perceived latency. Do not confuse warehouse startup with SQL execution time.

---

# Part 28 — Result Cache

## 72. Persisted Query Results

Snowflake can reuse persisted query results when requirements for result reuse are satisfied.

```text
Same Eligible Query
       |
       v
Existing Result
       |
       v
Return Without Recomputing
```

## 73. Why This Matters

A repeated query may return very quickly because it reused a previous result. That does not prove the underlying query is efficient.

## 74. Benchmarking

When testing performance, understand whether result reuse affected the measurement. Chapter 40 covers caching in detail.

---

# Part 29 — Warehouse Cache

## 75. Local Data Cache

Running warehouses can retain data locally to accelerate subsequent access. This differs from persisted query-result reuse.

## 76. Warehouse Suspension

When a warehouse suspends, local cache behavior differs from permanent table storage. Performance after resume may differ from a warm warehouse.

---

# Part 30 — Metadata

## 77. Metadata-Driven Optimization

Snowflake maintains metadata that helps with micro-partition pruning, statistics, object management, and optimization.

## 78. Metadata Matters

Efficient query processing is not simply reading every row. Metadata can help avoid unnecessary work.

---

# Part 31 — Cloud Services Work

## 79. Not Everything Runs on the Warehouse

Some lifecycle activities occur in Cloud Services, including parsing, optimization, metadata operations, security checks, and coordination.

## 80. Why This Matters

A warehouse resize may have limited effect when most delay is outside warehouse execution.

---

# Part 32 — Complex SQL Compilation

## 81. Compilation Can Matter

Very complex SQL may involve many nested views, large numbers of joins, large UNION trees, complex generated SQL, and extensive metadata dependencies.

## 82. BI-Generated SQL

BI tools can generate very large SQL statements. Investigate both compilation time and execution time before changing warehouse size.

---

# Part 33 — External Operations

## 83. External Dependencies

Some workloads interact with services or data outside normal Snowflake-managed table processing, such as external functions, external tables, external access, and remote services.

## 84. Latency

External dependency latency can contribute to query duration. A larger warehouse may not fix a slow external API.

---

# Part 34 — Query Timing Model

## 85. User-Perceived Time

Conceptually:

```text
Total Time
   =
Compilation
+ Queueing
+ Execution
+ Coordination
+ External Dependencies
+ Result Delivery
```

## 86. Example A

```text
Compilation = 0.5 s
Queueing    = 0 s
Execution   = 45 s
```

Investigate execution.

## 87. Example B

```text
Compilation = 1 s
Queueing    = 120 s
Execution   = 8 s
```

Investigate concurrency/capacity.

## 88. Example C

```text
Compilation = 30 s
Queueing    = 0 s
Execution   = 3 s
```

Investigate compilation complexity and metadata-related factors.

---

# Part 35 — Query History

## 89. First Operational Tool

During an incident, query history helps answer which queries are slow, who submitted them, which warehouse ran them, when they started, how long they ran, whether they queued, how much data they scanned, and whether they spilled.

## 90. Query ID

Always capture the query ID. It is the key identifier for deeper investigation.

---

# Part 36 — Query Profile

## 91. Query Profile Purpose

Query Profile helps answer where execution time went, which operator was expensive, whether scanning was excessive, pruning was poor, joins exploded, spilling occurred, or data was redistributed.

## 92. Operator-Level Thinking

Do not stop at "query took five minutes." Ask which operator consumed the time.

Chapter 37 goes deeply into this workflow.

---

# Part 37 — Production Troubleshooting Method

## 93. Step 1 — Confirm Scope

Determine whether the issue affects one query, one user, one application, one warehouse, one workload, or the entire account.

## 94. Step 2 — Capture Query ID

Do this before changing anything.

## 95. Step 3 — Separate Queueing from Execution

If queueing dominates, investigate concurrency. If execution dominates, investigate the query plan.

## 96. Step 4 — Check Data Scanned

Ask how many bytes and partitions were scanned and how selective the filters are.

## 97. Step 5 — Check Pruning

Poor pruning can cause massive unnecessary scans.

## 98. Step 6 — Check Joins

Look for join explosion, many-to-many behavior, large build/probe inputs, and skew.

## 99. Step 7 — Check Spill

Look for local and remote spill. Remote spill deserves particular attention.

## 100. Step 8 — Check Sorting and Aggregation

Large sorts and high-cardinality aggregation can consume substantial resources.

## 101. Step 9 — Check Warehouse

Only after understanding the query should you decide whether resize, multi-cluster, or workload isolation is appropriate.

---

# Part 38 — Common Mistakes

## 102. Mistake — Resize First

```text
Query slow
   |
   v
Find bottleneck
   |
   v
Fix correct layer
```

## 103. Mistake — Assume More Compute Fixes Poor SQL

More compute can accelerate some work. It does not make an incorrect many-to-many join correct.

## 104. Mistake — Ignore Queue Time

A 10-second query can appear to be a two-minute query if it waits in a queue.

## 105. Mistake — Benchmark Cached Results

A query returning instantly from persisted result reuse is not a valid measurement of underlying scan performance.

## 106. Mistake — Ignore Data Growth

A query that was fast at 100 GB may behave differently at 10 TB. Monitor workload evolution.

---

# Part 39 — Performance Decision Tree

## 107. Decision Flow

```text
Query Slow?
    |
    v
Queued?
 |       |
Yes      No
 |       |
 v       v
Concurrency   Execution
              |
              v
        Excessive Scan?
          |       |
         Yes      No
          |       |
          v       v
       Pruning   Join/Sort/Aggregate
                    |
                    v
                  Spill?
                  |   |
                 Yes  No
                  |   |
                  v   v
             Memory / Query
             Design / Size
```

---

# Part 40 — Hands-On Lab

## 108. Lab Objective

Create a dataset and observe how filtering, aggregation, joins, and sorting change query behavior.

Use a non-production environment.

## 109. Create Database

```sql
CREATE OR REPLACE DATABASE query_processing_lab;
```

## 110. Create Schema

```sql
CREATE OR REPLACE SCHEMA
query_processing_lab.demo;
```

## 111. Create Sales Table

```sql
CREATE OR REPLACE TABLE
query_processing_lab.demo.sales (
    transaction_id NUMBER,
    customer_id NUMBER,
    region STRING,
    transaction_date DATE,
    amount NUMBER(12,2)
);
```

## 112. Generate Sample Data

```sql
INSERT INTO query_processing_lab.demo.sales
SELECT
    SEQ4(),
    MOD(SEQ4(), 100000),
    CASE MOD(SEQ4(), 4)
        WHEN 0 THEN 'EAST'
        WHEN 1 THEN 'WEST'
        WHEN 2 THEN 'SOUTH'
        ELSE 'NORTH'
    END,
    DATEADD(
        day,
        -MOD(SEQ4(), 365),
        CURRENT_DATE()
    ),
    MOD(SEQ4(), 10000) / 100.0
FROM TABLE(GENERATOR(ROWCOUNT => 1000000));
```

The data is synthetic.

## 113. Baseline Query

```sql
SELECT *
FROM query_processing_lab.demo.sales;
```

Do not unnecessarily return a full large result to a client in a real production test.

## 114. Selective Query

```sql
SELECT
    customer_id,
    amount
FROM query_processing_lab.demo.sales
WHERE transaction_date = CURRENT_DATE();
```

Compare the Query Profile with the broader query.

## 115. Aggregation Query

```sql
SELECT
    region,
    COUNT(*) AS transaction_count,
    SUM(amount) AS total_amount
FROM query_processing_lab.demo.sales
GROUP BY region;
```

Observe aggregation operators.

## 116. High-Cardinality Aggregation

```sql
SELECT
    customer_id,
    SUM(amount)
FROM query_processing_lab.demo.sales
GROUP BY customer_id;
```

Compare it with grouping by only four regions.

## 117. Sorting Query

```sql
SELECT
    transaction_id,
    customer_id,
    amount
FROM query_processing_lab.demo.sales
ORDER BY amount DESC;
```

Observe sorting behavior.

## 118. Limited Sorting Query

```sql
SELECT
    transaction_id,
    customer_id,
    amount
FROM query_processing_lab.demo.sales
ORDER BY amount DESC
LIMIT 100;
```

Compare behavior.

## 119. Create Customer Table

```sql
CREATE OR REPLACE TABLE
query_processing_lab.demo.customer (
    customer_id NUMBER,
    customer_segment STRING
);
```

## 120. Populate Customers

```sql
INSERT INTO query_processing_lab.demo.customer
SELECT
    SEQ4(),
    CASE MOD(SEQ4(), 3)
        WHEN 0 THEN 'STANDARD'
        WHEN 1 THEN 'PREMIUM'
        ELSE 'ENTERPRISE'
    END
FROM TABLE(GENERATOR(ROWCOUNT => 100000));
```

## 121. Join Query

```sql
SELECT
    c.customer_segment,
    COUNT(*) AS transaction_count,
    SUM(s.amount) AS total_amount
FROM query_processing_lab.demo.sales s
JOIN query_processing_lab.demo.customer c
    ON s.customer_id = c.customer_id
GROUP BY c.customer_segment;
```

Observe scan, join, aggregation, and data movement.

## 122. Query IDs

After each query, capture its query ID through the appropriate Snowflake interface.

| Test | Query ID | Duration | Observation |
|---|---|---:|---|
| Selective scan | ... | ... | ... |
| Region aggregate | ... | ... | ... |
| Customer aggregate | ... | ... | ... |
| Sort | ... | ... | ... |
| Join | ... | ... | ... |

## 123. Compare Query Profiles

For each query ask:

- What operators exist?
- Which operator took the most time?
- How much data was scanned?
- How many partitions were scanned?
- Was data redistributed?
- Was there spill?

## 124. Cache Awareness

Run an eligible query more than once and observe whether subsequent execution differs. Do not immediately conclude that the SQL became more efficient; caching may have influenced the result.

## 125. Cleanup

```sql
DROP DATABASE IF EXISTS query_processing_lab;
```

---

# Part 41 — Production Query Investigation Checklist

## 126. Identification

- Query ID
- User
- Role
- Warehouse
- Application
- Start time
- End time
- Query type

## 127. Timing

- Total elapsed time
- Compilation time
- Queue time
- Execution time
- External dependency time where relevant

## 128. Scan

- Bytes scanned
- Partitions scanned
- Partitions total
- Filter selectivity
- Pruning effectiveness

## 129. Operators

- Table scans
- Joins
- Aggregations
- Sorts
- Window functions
- Data redistribution

## 130. Resource Pressure

- Local spill
- Remote spill
- Concurrency
- Warehouse load
- Warehouse size

## 131. Caching

- Result reuse considered
- Warehouse cache considered
- Warehouse recently resumed

---

# Part 42 — Production Incident Runbook

## 132. Query Slowness Incident

1. Capture incident start time.
2. Identify affected application/users.
3. Capture representative query IDs.
4. Identify warehouse.
5. Determine queue time.
6. Determine execution time.
7. Determine compilation time.
8. Review warehouse load.
9. Review Query Profile.
10. Identify dominant operator.
11. Check partitions scanned.
12. Check pruning.
13. Check bytes scanned.
14. Check joins.
15. Check aggregation.
16. Check sorting.
17. Check data redistribution.
18. Check local spill.
19. Check remote spill.
20. Check concurrency.
21. Check cache effects.
22. Check external dependencies.
23. Compare with known-good executions.
24. Identify recent changes.
25. Apply targeted remediation.
26. Validate performance.
27. Monitor recurrence.
28. Document root cause.

---

# Part 43 — Root-Cause Examples

## 133. Example — Poor Pruning

Symptoms: large table, large partitions scanned, small expected result, and high bytes scanned.

Investigate filters, data distribution, clustering, and query predicates.

## 134. Example — Queueing

If execution is 8 seconds but queue time is 90 seconds, investigate concurrency, workload isolation, multi-cluster configuration, scheduling, and warehouse capacity.

## 135. Example — Remote Spill

Large joins, large intermediate results, remote spill, and long execution suggest investigation of join design, filtering, intermediate result reduction, and warehouse sizing.

## 136. Example — Result Cache Confusion

If run 1 takes 60 seconds and run 2 is near-instant, do not immediately claim performance is fixed. Investigate persisted query-result reuse.

---

# Part 44 — Operational Principles

## 137. Measure Before Changing

Capture evidence before resizing a warehouse, changing clustering, rewriting SQL, or changing workload routing.

## 138. Change One Major Variable at a Time

This makes it easier to determine what actually improved performance.

## 139. Compare Like for Like

Consider same SQL, data volume, warehouse, concurrency, cache state where practical, and parameter values.

## 140. Optimize the Largest Bottleneck

If queueing accounts for most user latency, rewriting a scan operator may not materially improve the experience. Focus on the dominant contributor.

---

# Acceptance Criteria

The chapter is complete when you can:

- explain the Snowflake query lifecycle
- distinguish Cloud Services, compute, and storage
- explain parsing and validation
- explain query compilation and optimization
- describe execution plans and virtual warehouse execution
- explain distributed parallel processing
- explain micro-partitions and partition pruning
- identify poor pruning and filter selectivity
- explain join processing and identify join explosion
- understand aggregation, sorting, and window-function costs
- explain data redistribution and recognize data skew
- explain memory pressure, local spill, and remote spill
- distinguish queueing from execution
- understand concurrency
- distinguish scale-up from scale-out
- understand warehouse startup effects
- distinguish result cache from warehouse cache
- understand metadata-driven optimization
- recognize Cloud Services work
- investigate complex compilation
- identify external dependency latency
- break down total query time
- use Query History and capture query IDs
- understand Query Profile's purpose
- follow a production troubleshooting workflow
- avoid resize-first troubleshooting
- benchmark without misleading cache effects
- compare representative executions
- perform a query-slowness incident investigation

---

## Key Takeaways

Snowflake query performance is not simply SQL → Warehouse.

A better mental model is:

```text
SQL
 |
 v
Cloud Services
 |
 +---- Parse
 +---- Validate
 +---- Optimize
 |
 v
Queue
 |
 v
Virtual Warehouse
 |
 +---- Scan
 +---- Prune
 +---- Filter
 +---- Join
 +---- Aggregate
 +---- Sort
 +---- Redistribute
 |
 +---- Memory
 |       |
 |       v
 |   Local Spill
 |       |
 |       v
 |   Remote Spill
 |
 v
Result
```

When a query is slow, first determine whether the delay is compilation, queueing, execution, or an external dependency.

If execution is slow, determine whether the dominant problem is scan, pruning, join, aggregation, sort, redistribution, or spill.

Do not automatically resize the warehouse.

The most useful performance question is:

> Where did the time and work go?

That question leads directly into the next chapter.

The next chapter is **Chapter 37 — Query Profile Deep Dive**.
