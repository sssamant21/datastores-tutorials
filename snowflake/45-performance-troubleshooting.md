# 45 — Performance Troubleshooting

## Overview

Snowflake performance troubleshooting should be evidence-driven.

When a user reports:

> Snowflake is slow.

that statement alone does not identify the problem.

Slowness can originate from many different layers:

```text
Application
    |
    v
Authentication / connection
    |
    v
Cloud Services
    |
    v
Warehouse queueing
    |
    v
Query execution
    |
    +---- Table scan
    +---- Poor pruning
    +---- Join
    +---- Aggregation
    +---- Sort
    +---- Spill
    +---- Data skew
    |
    v
Result delivery
```

A slow query might actually be caused by:

- warehouse provisioning
- warehouse overload
- concurrency
- undersized compute
- oversized compute used inefficiently
- poor micro-partition pruning
- excessive data scanning
- join explosion
- data skew
- local spill
- remote spill
- expensive sorting
- expensive aggregation
- inefficient window functions
- repeated computation
- cold warehouse cache
- changed data distribution
- changed query plan
- Search Optimization not being applicable
- Query Acceleration not being applicable
- workload contention
- application behavior
- network/client behavior

The production troubleshooting process should therefore follow:

```text
Detect
   |
   v
Scope
   |
   v
Compare
   |
   v
Measure
   |
   v
Profile
   |
   v
Classify bottleneck
   |
   v
Remediate
   |
   v
Validate
   |
   v
Prevent recurrence
```

This chapter provides a production-focused troubleshooting framework for Data Engineers, DBREs, SREs, Snowflake administrators, platform engineers, and application teams.

---

# Part 1 — Define "Slow"

## 1. Start With Evidence

Do not begin with:

> Should we resize the warehouse?

Begin with:

```text
What is slow?
When did it become slow?
Which queries are affected?
Which warehouse?
Which users?
Which application?
What changed?
```

---

# Part 2 — Scope the Incident

## 2. Determine Blast Radius

Identify whether the problem affects:

```text
One query
One user
One application
One warehouse
One schema
One workload
Multiple warehouses
Entire account
```

This immediately changes the investigation path.

---

# Part 3 — Single Query vs Broad Incident

## 3. Single Query

If only one query is slow, query design, data volume, pruning, join behavior, spill, and query plan become strong investigation areas.

## 4. Many Queries

If many unrelated queries suddenly become slow, warehouse capacity, concurrency, queueing, workload spikes, configuration changes, and platform/service conditions become more likely.

---

# Part 4 — Establish the Time Window

## 5. Incident Window

Capture:

```text
Start:
End:
Timezone:
First reported:
Last known good:
```

Always use an explicit timezone.

---

# Part 5 — Identify Query IDs

## 6. Query IDs Are Critical

Collect representative query IDs for slow, normal, failed, queued, and high-cost queries.

Query IDs provide a concrete investigation anchor.

---

# Part 6 — Compare Slow vs Fast

## 7. Best Troubleshooting Technique

Find the same query or workload on the same warehouse when it was previously fast, then compare it with the slow execution.

This is often more useful than examining the slow query in isolation.

---

# Part 7 — Comparison Matrix

## 8. Capture

| Metric | Fast | Slow |
|---|---:|---:|
| Total elapsed | | |
| Compilation | | |
| Queue | | |
| Execution | | |
| Bytes scanned | | |
| Partitions scanned | | |
| Rows produced | | |
| Spill local | | |
| Spill remote | | |
| Warehouse size | | |
| Warehouse state | | |

The exact available metrics depend on the current Snowflake telemetry interface.

---

# Part 8 — Query Lifecycle

## 9. Understand Where Time Is Spent

Conceptually:

```text
Query submitted
      |
      v
Compilation
      |
      v
Queue / provisioning
      |
      v
Execution
      |
      v
Result delivery
```

Performance troubleshooting should determine which phase dominates.

---

# Part 9 — Compilation

## 10. Compilation Time

If total query time is high but execution time is small, investigate time outside execution.

Compilation can become relevant for complex SQL or metadata-heavy operations.

Do not classify every slow query as a warehouse compute problem.

---

# Part 10 — Warehouse Provisioning

## 11. Resume / Provisioning

A suspended warehouse may need to resume before executing work.

```text
Query
  |
  v
Warehouse suspended
  |
  v
Resume
  |
  v
Provisioning
  |
  v
Execute
```

A first query after suspension can therefore behave differently from a warm warehouse query.

---

# Part 11 — Overload Queueing

## 12. Warehouse Busy

If warehouse execution resources are saturated, incoming queries can wait for capacity.

This is primarily a concurrency problem.

---

# Part 12 — Queue vs Execution

## 13. Example A

```text
Total = 60 sec
Queue = 50 sec
Execution = 10 sec
```

Focus on concurrency.

## 14. Example B

```text
Total = 60 sec
Queue = 1 sec
Execution = 58 sec
```

Focus on query execution.

This distinction prevents many incorrect warehouse changes.

---

# Part 13 — Query History

## 15. Start With Query History

Query History is one of the primary operational data sources for performance troubleshooting.

Use it to investigate query ID, user, role, warehouse, warehouse size, start/end time, execution time, queue time, bytes scanned, rows produced, errors, and query text.

Use current Snowflake documentation for exact column names and retention behavior.

---

# Part 14 — ACCOUNT_USAGE

## 16. Historical Investigation

Snowflake's `ACCOUNT_USAGE` schema provides account-level operational history useful for investigations.

A commonly used source is:

```sql
SNOWFLAKE.ACCOUNT_USAGE.QUERY_HISTORY
```

Chapter 46 covers `ACCOUNT_USAGE` and `INFORMATION_SCHEMA` in depth.

---

# Part 15 — INFORMATION_SCHEMA

## 17. Near-Term Operational Investigation

Snowflake also exposes query history through Information Schema functions/interfaces.

Use the appropriate interface based on required latency, retention, privileges, and scope.

---

# Part 16 — Query Profile

## 18. Execution-Level Evidence

Query Profile provides operator-level visibility.

Use it to answer:

```text
Where did execution time go?
What scanned the most data?
Which operator produced too many rows?
Was there spill?
Was pruning effective?
Which join expanded rows?
Was Search Optimization used?
Was Query Acceleration used?
```

---

# Part 17 — Profile From the Top

## 19. Start With Expensive Operators

Do not inspect every operator randomly.

Begin with the most expensive operator, highest bytes, highest rows, largest spill, and largest row expansion.

Then follow the data flow.

---

# Part 18 — Table Scan

## 20. Scan Investigation

For table scan operators, inspect partitions scanned, partitions total, bytes scanned, rows scanned, and filter selectivity.

A large scan can dominate execution.

---

# Part 19 — Micro-Partition Pruning

## 21. Pruning Ratio

Suppose:

```text
Partitions total   = 100,000
Partitions scanned = 2,000
```

Pruning is strong.

Now suppose:

```text
Partitions total   = 100,000
Partitions scanned = 95,000
```

Pruning is weak.

This may be the primary performance problem.

---

# Part 20 — Why Pruning Changes

## 22. Common Causes

Poor pruning can result from broad filters, data distribution, poor clustering, function-wrapped predicates, type conversion, query pattern changes, or large date ranges.

Investigate the actual predicate.

---

# Part 21 — Filter Selectivity

## 23. Selective Predicate

```sql
WHERE claim_id = 'CLAIM-EXAMPLE-1001'
```

This may target very few rows.

## 24. Broad Predicate

```sql
WHERE claim_status = 'PROCESSED'
```

If most rows have that value, the predicate is not selective.

Different optimization strategies apply.

---

# Part 22 — Search Optimization Candidate

## 25. Point Lookup

If a very large table repeatedly performs highly selective lookups but scans substantial data, evaluate Search Optimization Service.

Do not automatically enable it.

First verify query pattern, supported predicate, selectivity, frequency, and cost.

Chapter 41 covers this in detail.

---

# Part 23 — Clustering Candidate

## 26. Repeated Range Filtering

If large tables repeatedly filter on ranges such as:

```sql
WHERE event_date BETWEEN :start_date AND :end_date
```

and pruning degrades because of data organization, evaluate clustering strategy.

Chapter 39 covers clustering.

---

# Part 24 — Join Investigation

## 27. Joins Can Dominate Queries

A join may appear simple in SQL while producing enormous intermediate results.

Example:

```text
Table A = 10M rows
Table B = 10M rows
Join output = 5B rows
```

This should immediately be investigated.

---

# Part 25 — Join Explosion

## 28. Warning Pattern

```text
Input A: 10M
Input B: 10M
     |
     v
    JOIN
     |
     v
Output: 3B
```

Potential causes include missing join predicates, incorrect keys, many-to-many relationships, duplicate records, range joins, and unexpected NULL behavior.

---

# Part 26 — Missing Join Predicate

## 29. Example

Problem:

```sql
SELECT *
FROM orders o
JOIN customers c;
```

This can produce Cartesian behavior.

Correct joins require the intended relationship.

```sql
SELECT *
FROM orders o
JOIN customers c
    ON o.customer_id = c.customer_id;
```

---

# Part 27 — Duplicate Join Keys

## 30. Hidden Multiplication

Suppose both sides contain duplicate business keys.

```text
A contains 10 rows for key X
B contains 20 rows for key X
```

The join can produce 200 rows for one key.

Inspect uniqueness assumptions.

---

# Part 28 — Data Skew

## 31. Uneven Distribution

If one key represents a disproportionate percentage of rows, operations involving that key can become disproportionately expensive.

Look for uneven operator workloads and unusually large key groups.

---

# Part 29 — Aggregation

## 32. GROUP BY

Large aggregations can consume substantial compute and memory.

```sql
SELECT
    customer_id,
    product_id,
    event_date,
    COUNT(*)
FROM events
GROUP BY
    customer_id,
    product_id,
    event_date;
```

High-cardinality grouping can produce large intermediate results.

---

# Part 30 — Sort

## 33. ORDER BY

Sorting very large result sets can be expensive.

```sql
SELECT *
FROM events
ORDER BY event_timestamp;
```

Ask whether the consumer requires every row sorted, whether filtering can occur first, and whether a limited result is appropriate.

---

# Part 31 — Window Functions

## 34. Analytical Operations

Window functions may require partitioning, sorting, and large intermediate state.

```sql
ROW_NUMBER() OVER (
    PARTITION BY customer_id
    ORDER BY event_timestamp DESC
)
```

These are powerful operations, but they should be examined when they dominate Query Profile.

---

# Part 32 — Spill

## 35. Memory Pressure

When execution operators require more memory than is available, intermediate data can spill.

```text
Operator
   |
   v
Memory capacity exceeded
   |
   +---- Local storage
   |
   +---- Remote storage
```

---

# Part 33 — Local Spill

## 36. Local Temporary Storage

Local spill is slower than in-memory processing.

It is an important performance signal.

---

# Part 34 — Remote Spill

## 37. Stronger Warning

Remote spill generally indicates more severe memory pressure.

If a query has substantial remote spill, do not immediately resize.

First determine why the query requires so much intermediate state.

---

# Part 35 — Spill Root Causes

## 38. Investigate

Potential causes include large joins, join explosion, large sorts, large aggregations, high-cardinality GROUP BY, window functions, data skew, and an undersized warehouse.

The warehouse may be too small, but SQL design must be evaluated first.

---

# Part 36 — Warehouse Scale-Up Candidate

## 39. Evidence-Based Resize

Scaling up becomes more reasonable when the query is logically efficient, pruning is reasonable, join behavior is expected, data volume is legitimate, spill remains substantial, and execution is compute-bound.

Then test a larger warehouse.

---

# Part 37 — Warehouse Scale-Out Candidate

## 40. Queueing Pattern

Scaling out becomes more reasonable when individual queries are healthy, concurrent workload is high, and overload queueing dominates latency.

Chapter 44 covers multi-cluster warehouses.

---

# Part 38 — Warehouse Resize Test

## 41. Controlled Comparison

Test two warehouse sizes with the same representative workload.

Measure execution, queueing, spill, credits, and SLA.

Do not judge only by runtime.

---

# Part 39 — Cost per Query

## 42. Example

Before:

```text
Runtime = 12 min
Cost = 0.4 credits
```

After:

```text
Runtime = 6 min
Cost = 0.4 credits
```

This may be a strong improvement.

A result of 11 minutes at 0.75 credits may not justify the larger warehouse.

---

# Part 40 — Warehouse Cache

## 43. Warm vs Cold

A query may be faster when relevant data remains in warehouse-local cache.

Compare the first query after resume with subsequent queries.

Do not confuse cache effects with SQL optimization.

---

# Part 41 — Persisted Query Results

## 44. Result Reuse

Snowflake can reuse persisted query results when reuse conditions are satisfied.

For performance benchmarking, a result-cache hit can make a query appear dramatically faster without executing the workload again.

---

# Part 42 — Disable Result Reuse for Testing

## 45. Controlled Benchmark

```sql
ALTER SESSION SET USE_CACHED_RESULT = FALSE;
```

After testing:

```sql
ALTER SESSION SET USE_CACHED_RESULT = TRUE;
```

Validate current parameter behavior before using this in production workflows.

---

# Part 43 — Do Not Disable Caching Globally

## 46. Testing Scope

Do not broadly disable useful caching just because you are troubleshooting one query.

Use controlled sessions.

---

# Part 44 — Query Acceleration Service

## 47. QAS Candidate

Some eligible scan-heavy analytical workloads may benefit from Query Acceleration Service.

Do not assume every slow query is eligible.

Evaluate eligibility, query shape, scan characteristics, estimated benefit, and serverless cost.

Chapter 42 covers QAS.

---

# Part 45 — QAS Is Not a SQL Fix

## 48. Important Rule

Do not use Query Acceleration to hide Cartesian joins, poor predicates, unnecessary SELECT *, bad data modeling, or avoidable scans.

Optimize first.

---

# Part 46 — Search Optimization vs QAS

## 49. Different Problems

```text
Highly selective lookup
        |
        v
Search Optimization

Large eligible analytical query
        |
        v
Query Acceleration
```

They are not interchangeable.

---

# Part 47 — Materialized Views

## 50. Repeated Expensive Computation

If many queries repeatedly calculate the same expensive result, consider whether a materialized view or another precomputation strategy is appropriate.

---

# Part 48 — Dynamic Tables

## 51. Precomputed Pipeline State

Dynamic Tables can be useful when downstream workloads repeatedly require transformed data that can be maintained declaratively.

This is different from simply increasing query compute.

---

# Part 49 — Data Growth

## 52. Query Did Not Change

SQL, warehouse, and application can remain unchanged while data volume grows significantly.

Performance can still degrade.

Always compare data volume.

---

# Part 50 — Partition Growth

## 53. Example

Last month:

```text
Partitions = 20,000
Scanned = 1,000
```

Today:

```text
Partitions = 80,000
Scanned = 20,000
```

The query text may be identical, but the physical workload changed significantly.

---

# Part 51 — Query Pattern Change

## 54. Application Deployment

An application may change:

```sql
WHERE claim_id = ?
```

to:

```sql
WHERE UPPER(claim_id) = UPPER(?)
```

The queries appear logically similar but may have different optimization characteristics.

Compare query text before and after deployments.

---

# Part 52 — Type Conversion

## 55. Data-Type Mismatch

Implicit or explicit conversions can change execution behavior.

Review predicate data types and use consistent types whenever possible.

---

# Part 53 — SELECT *

## 56. Excessive Columns

```sql
SELECT *
FROM very_wide_table;
```

If the consumer needs only three columns, select only those columns.

This can reduce unnecessary processing and data transfer.

---

# Part 54 — Filter Early

## 57. Reduce Data

Whenever logically possible, reduce unnecessary data before expensive downstream operations.

The optimizer handles many transformations automatically, but query design still matters.

---

# Part 55 — LIMIT Misconception

## 58. LIMIT Does Not Guarantee Cheap Work

```sql
SELECT *
FROM huge_table
ORDER BY event_timestamp DESC
LIMIT 10;
```

The engine may still need substantial work to determine the top 10 rows.

Do not assume `LIMIT 10` means only ten rows are processed.

---

# Part 56 — CTE Misconceptions

## 59. Read Query Profile

Do not assume a CTE is automatically materialized or automatically expensive.

Snowflake optimizer behavior matters.

Use Query Profile rather than generic SQL folklore.

---

# Part 57 — Application Layer

## 60. Snowflake May Not Be the Bottleneck

Suppose Snowflake reports 500 ms execution but the application reports a 15-second response.

Investigate connection pools, application processing, network, serialization, result consumption, and downstream services.

Do not assign all 15 seconds to Snowflake without evidence.

---

# Part 58 — Result Size

## 61. Large Results

A query returning millions of rows may finish execution reasonably quickly but take substantial time to consume.

Ask how many rows and how much data are returned and whether the application needs all of them.

---

# Part 59 — Connection Behavior

## 62. Client Investigation

Check connection establishment, connection pooling, authentication, retries, driver version, timeouts, and fetch behavior when Snowflake execution metrics do not explain application latency.

---

# Part 60 — Workload Change

## 63. Ask What Changed

Check for new releases, dashboards, backfills, data syncs, pipelines, users, customers, warehouse resizing, scaling-policy changes, auto-suspend changes, query changes, schema changes, and clustering changes.

Change correlation is one of the strongest incident signals.

---

# Part 61 — Warehouse History

## 64. Configuration Timeline

During an incident, determine whether warehouse size, cluster count, or scaling policy changed.

---

# Part 62 — Query Volume

## 65. Compare Baseline

```text
Normal:
20,000 queries/hour

Incident:
80,000 queries/hour
```

The SQL may not have changed.

Demand changed.

---

# Part 63 — Concurrency

## 66. Peak Matters

```text
Normal peak concurrency = 15
Incident peak = 75
```

This strongly supports a concurrency investigation.

---

# Part 64 — Data Loading Impact

## 67. Overlapping Workloads

Large ingestion, transformation, or maintenance workloads may overlap with interactive workloads.

If ETL, BI, and ad hoc activity share a warehouse, contention becomes possible.

Workload isolation may be the better solution.

---

# Part 65 — Query Tagging

## 68. Operational Attribution

Use query tagging conventions where appropriate so workload sources can be identified.

Examples:

```text
application=claims-api
pipeline=daily-load
dashboard=finance
environment=prod
```

Validate current Snowflake `QUERY_TAG` syntax and behavior before standardizing.

---

# Part 66 — User Attribution

## 69. Identify Sources

Group slow or expensive queries by user, role, warehouse, query tag, and application.

This can expose one workload driving the incident.

---

# Part 67 — Warehouse Attribution

## 70. Group by Warehouse

Determine whether slowness is isolated to one warehouse or affects several.

If only one warehouse is affected, account-wide platform problems become less likely.

---

# Part 68 — Query Fingerprinting

## 71. Similar Queries

Applications often submit the same logical query with different literal values.

Group similar query patterns when investigating.

This helps identify top slow query families, top credit-consuming query families, and queue-producing workloads.

---

# Part 69 — Baseline Metrics

## 72. Maintain Normal Values

For important workloads, know normal P50, P95, P99, queue time, bytes scanned, partitions scanned, spill, and credits.

Without a baseline, "slow" is subjective.

---

# Part 70 — SLOs

## 73. Define Performance Objectives

Examples:

```text
Application lookup P95 < 1 sec
Dashboard P95 < 5 sec
ETL completion < 60 min
Queue P95 < 2 sec
```

Troubleshooting becomes easier when the target is explicit.

---

# Part 71 — Performance Incident Severity

## 74. Example Classification

### SEV-1

Critical production workload unavailable or severe widespread degradation.

### SEV-2

Major production performance degradation with significant business impact.

### SEV-3

Localized performance degradation with workaround available.

Use your organization's incident standard.

---

# Part 72 — First 5 Minutes

## 75. Initial Response

Capture incident start, affected service, affected warehouse, representative query IDs, current warehouse state, current query volume, queueing, and recent changes.

Avoid premature configuration changes.

---

# Part 73 — First 15 Minutes

## 76. Classification

Determine whether the problem is queue-bound, execution-bound, isolated to one query, broad across a workload, related to data growth, or correlated with a recent deployment.

---

# Part 74 — First 30 Minutes

## 77. Deep Investigation

Analyze Query Profile, pruning, join behavior, spill, concurrency, warehouse capacity, cache, data volume, and query changes.

Then choose targeted mitigation.

---

# Part 75 — Immediate Mitigation

## 78. Possible Actions

Depending on evidence:

```text
Pause non-critical workload
Move workload to another warehouse
Scale warehouse up
Scale warehouse out
Reschedule batch
Rollback query change
Optimize SQL
Enable validated acceleration feature
```

Do not use every mitigation at once.

---

# Part 76 — Temporary vs Permanent Fix

## 79. Example

Temporary:

```text
Resize MEDIUM -> LARGE
```

Permanent:

```text
Fix join explosion
```

Document both.

A successful incident mitigation is not automatically the root-cause remediation.

---

# Part 77 — Performance Troubleshooting Decision Tree

## 80. Start

```text
Query/workload slow
        |
        v
Queue time high?
      /     \
    Yes      No
    |         |
    v         v
Concurrency   Execution slow?
problem          /      \
                Yes      No
                |         |
                v         v
          Query Profile   Check client /
                |         connection /
                |         result delivery
                v
          Scan dominant?
             /    \
           Yes     No
           |        |
           v        v
       Pruning?   Join/spill/
        /   \     sort/aggregate
      Poor  Good
       |      |
       v      v
   Fix data/   Evaluate
   query       SOS/QAS/
   layout      compute
```

---

# Part 78 — Scan Troubleshooting

## 81. Checklist

```text
□ Bytes scanned
□ Partitions scanned
□ Partitions total
□ Filter predicates
□ Filter selectivity
□ Data types
□ Functions on predicates
□ Date range
□ Clustering
□ Search Optimization
```

---

# Part 79 — Join Troubleshooting

## 82. Checklist

```text
□ Join keys
□ Input rows
□ Output rows
□ Duplicate keys
□ Many-to-many relationships
□ Missing predicates
□ Data skew
□ Spill
```

---

# Part 80 — Spill Troubleshooting

## 83. Checklist

```text
□ Local spill
□ Remote spill
□ Join size
□ Sort size
□ Aggregation size
□ Window functions
□ Warehouse size
□ Data skew
```

---

# Part 81 — Queue Troubleshooting

## 84. Checklist

```text
□ Overload queue
□ Provisioning queue
□ Query volume
□ Peak concurrency
□ Warehouse size
□ Active clusters
□ Max clusters
□ Scaling policy
□ Workload isolation
□ Batch overlap
```

---

# Part 82 — Cache Troubleshooting

## 85. Checklist

```text
□ Persisted result reused?
□ Warehouse warm?
□ Warehouse recently resumed?
□ Different cluster?
□ Data changed?
□ Query text changed?
```

---

# Part 83 — Cost Troubleshooting

## 86. Performance Fix Increased Cost

Check whether the warehouse was resized, clusters increased, QAS enabled, query volume increased, warehouse idle time changed, or auto-suspend changed.

Every performance remediation should include cost validation.

---

# Part 84 — Query Regression

## 87. Same Query Became Slower

Compare query text, warehouse, data volume, partitions, bytes scanned, Query Profile, spill, concurrency, and cache state.

Avoid assuming Snowflake changed internally before checking workload evidence.

---

# Part 85 — Production Evidence Template

## 88. Incident Record

```text
Incident:
Environment:
Start:
End:
Timezone:
Affected application:
Affected warehouse:
Business impact:
Slow query IDs:
Fast baseline query IDs:
Warehouse size:
Cluster configuration:
Query volume:
Peak concurrency:
Queue P50:
Queue P95:
Queue P99:
Execution P50:
Execution P95:
Execution P99:
Bytes scanned:
Partitions scanned:
Partitions total:
Local spill:
Remote spill:
Top expensive operator:
Join input/output:
Recent changes:
Data growth:
Root cause:
Immediate mitigation:
Permanent remediation:
Performance before:
Performance after:
Credit impact:
Follow-up:
```

---

# Part 86 — RCA Structure

## 89. Root Cause

State the actual technical cause.

Example:

```text
The query regression was caused by a many-to-many join
introduced by duplicate customer mapping records.
```

Not:

```text
Snowflake was slow.
```

---

# Part 87 — Contributing Factors

## 90. Example

Large data growth, shared warehouses, insufficient monitoring, missing query tags, and missing performance regression tests can contribute without being the root cause.

---

# Part 88 — Corrective Actions

## 91. Categories

### Immediate

Restore service.

### Short Term

Prevent recurrence of the same failure.

### Long Term

Improve architecture and detection.

---

# Part 89 — Preventive Controls

## 92. Recommended Controls

```text
Query latency dashboards
Queue alerts
Warehouse credit alerts
Spill monitoring
Query regression detection
Workload isolation
Query tagging
Capacity reviews
Data growth monitoring
```

---

# Part 90 — Performance Review

## 93. Weekly

Review top slow queries, top queued queries, top spilling queries, top bytes scanned, and top credit consumers.

---

# Part 91 — Monthly

## 94. Architecture Review

Review warehouse sizing, multi-cluster settings, Search Optimization, QAS, clustering, materialized views, Dynamic Tables, and workload isolation.

---

# Part 92 — Anti-Patterns

## 95. Anti-Pattern 1

Query slow -> resize warehouse without investigation.

## 96. Anti-Pattern 2

Queueing high -> rewrite SQL without checking concurrency.

## 97. Anti-Pattern 3

Poor pruning -> add more clusters.

## 98. Anti-Pattern 4

Join explosion -> enable QAS.

## 99. Anti-Pattern 5

Application latency is 20 seconds while Snowflake execution is 500 ms, yet Snowflake is declared slow.

Evidence must drive the conclusion.

---

# Part 93 — Performance Optimization Order

## 100. Recommended Thinking Order

```text
1. Correctness
2. Query design
3. Data reduction
4. Pruning
5. Join behavior
6. Spill
7. Workload isolation
8. Warehouse capacity
9. Specialized optimization
10. Cost validation
```

This is a troubleshooting framework, not an absolute optimizer rule.

---

# Part 94 — Hands-On Lab

## 101. Objective

Create several intentionally different performance scenarios and diagnose each one using Snowflake telemetry.

Use only a non-production environment.

## 102. Create Database

```sql
CREATE OR REPLACE DATABASE performance_lab;
```

## 103. Create Schema

```sql
CREATE OR REPLACE SCHEMA performance_lab.demo;
```

## 104. Create Synthetic Table

```sql
CREATE OR REPLACE TABLE performance_lab.demo.events (
    event_id NUMBER,
    customer_id NUMBER,
    product_id NUMBER,
    event_date DATE,
    event_type STRING,
    amount NUMBER(12,2)
);
```

## 105. Generate Data

```sql
INSERT INTO performance_lab.demo.events
SELECT
    seq,
    MOD(seq, 1000000),
    MOD(seq, 100000),
    DATEADD(day, -MOD(seq, 730), DATE '2026-10-01'),
    CASE MOD(seq, 5)
        WHEN 0 THEN 'READ'
        WHEN 1 THEN 'WRITE'
        WHEN 2 THEN 'UPDATE'
        WHEN 3 THEN 'DELETE'
        ELSE 'OTHER'
    END,
    MOD(seq, 1000000) / 100.0
FROM (
    SELECT SEQ4() AS seq
    FROM TABLE(GENERATOR(ROWCOUNT => 20000000))
);
```

All data is synthetic.

Reduce row count if needed for your lab budget.

---

# Part 95 — Disable Persisted Results

## 106. Session Setting

```sql
ALTER SESSION SET USE_CACHED_RESULT = FALSE;
```

This helps prevent persisted result reuse from invalidating controlled execution comparisons.

---

# Part 96 — Scenario 1: Broad Scan

## 107. Query

```sql
SELECT
    event_type,
    COUNT(*),
    SUM(amount)
FROM performance_lab.demo.events
GROUP BY event_type;
```

Capture query ID, runtime, bytes scanned, partitions scanned, and Query Profile.

---

# Part 97 — Scenario 2: Selective Filter

## 108. Query

```sql
SELECT *
FROM performance_lab.demo.events
WHERE customer_id = 500000;
```

Compare scan behavior with Scenario 1.

---

# Part 98 — Scenario 3: Range Filter

## 109. Query

```sql
SELECT
    event_date,
    SUM(amount)
FROM performance_lab.demo.events
WHERE event_date BETWEEN DATE '2026-09-01'
                     AND DATE '2026-09-30'
GROUP BY event_date;
```

Inspect pruning.

---

# Part 99 — Scenario 4: Expensive Sort

## 110. Query

```sql
SELECT
    customer_id,
    product_id,
    amount
FROM performance_lab.demo.events
ORDER BY amount DESC;
```

Inspect sort cost and spill.

Do not retrieve unnecessary results through a client if the lab query would generate excessive transfer.

---

# Part 100 — Scenario 5: Window Function

## 111. Query

```sql
SELECT
    customer_id,
    event_date,
    amount,
    ROW_NUMBER() OVER (
        PARTITION BY customer_id
        ORDER BY event_date DESC
    ) AS row_num
FROM performance_lab.demo.events;
```

Inspect sorting, partitioning, row volume, and spill.

---

# Part 101 — Scenario 6: Controlled Join

## 112. Create Dimension

```sql
CREATE OR REPLACE TABLE performance_lab.demo.customers AS
SELECT
    seq AS customer_id,
    'CUSTOMER-' || seq AS customer_name
FROM (
    SELECT SEQ4() AS seq
    FROM TABLE(GENERATOR(ROWCOUNT => 1000000))
);
```

## 113. Join Query

```sql
SELECT
    c.customer_name,
    COUNT(*) AS event_count,
    SUM(e.amount) AS total_amount
FROM performance_lab.demo.events e
JOIN performance_lab.demo.customers c
    ON e.customer_id = c.customer_id
GROUP BY c.customer_name;
```

Inspect join input rows, join output rows, spill, and execution time.

---

# Part 102 — Scenario 7: Queueing

## 114. Controlled Concurrency

Using a dedicated lab warehouse and a small approved number of sessions, execute representative analytical queries concurrently.

Capture queue time, execution time, and total elapsed time.

Do not perform uncontrolled load testing.

---

# Part 103 — Scenario 8: Warehouse Resize

## 115. Compare Sizes

Run the same representative query on two approved warehouse sizes.

| Metric | Size A | Size B |
|---|---:|---:|
| Execution | | |
| Queue | | |
| Local spill | | |
| Remote spill | | |
| Credits | | |

---

# Part 104 — Diagnose Before Fix

## 116. For Every Scenario

Write:

```text
Observed symptom:
Evidence:
Bottleneck:
Proposed fix:
Expected improvement:
Cost impact:
```

This is the most important part of the lab.

---

# Part 105 — Restore Session

## 117. Re-enable Persisted Results

```sql
ALTER SESSION SET USE_CACHED_RESULT = TRUE;
```

---

# Part 106 — Cleanup

## 118. Drop Lab

```sql
DROP DATABASE IF EXISTS performance_lab;
```

Restore any lab warehouse changes.

---

# Part 107 — Production Troubleshooting Checklist

## 119. Scope

```text
□ Incident time
□ Business impact
□ Affected workload
□ Affected warehouse
□ Query IDs
□ Fast baseline
```

## 120. Query

```text
□ Query text
□ Query Profile
□ Bytes scanned
□ Partitions scanned
□ Rows produced
□ Join expansion
□ Spill
```

## 121. Warehouse

```text
□ Size
□ State
□ Queueing
□ Concurrency
□ Cluster count
□ Scaling policy
□ Auto-suspend
```

## 122. Workload

```text
□ Query volume
□ Data volume
□ Peak demand
□ ETL overlap
□ BI overlap
□ Ad hoc workload
```

## 123. Optimization

```text
□ Pruning
□ Clustering
□ Search Optimization
□ QAS
□ Materialized view
□ Dynamic Table
```

## 124. Application

```text
□ Connection
□ Driver
□ Network
□ Fetch
□ Result size
□ Application processing
```

## 125. Change

```text
□ Deployment
□ Query change
□ Warehouse change
□ Schema change
□ Data growth
□ Pipeline change
```

## 126. Validation

```text
□ Performance before
□ Performance after
□ Credits before
□ Credits after
□ SLA restored
□ Root cause documented
```

---

# Part 108 — Troubleshooting Command Template

## 127. Query History

A production investigation commonly needs a query-history query conceptually similar to:

```sql
SELECT
    query_id,
    user_name,
    warehouse_name,
    warehouse_size,
    start_time,
    end_time,
    total_elapsed_time,
    execution_time,
    bytes_scanned,
    rows_produced,
    query_text
FROM snowflake.account_usage.query_history
WHERE start_time >= :incident_start
  AND start_time < :incident_end
ORDER BY total_elapsed_time DESC;
```

Before using this as a canonical production query, validate current Snowflake column names, latency, privileges, and retention.

---

# Part 109 — Queue Investigation Template

## 128. Conceptual Query

Extend Query History analysis with current queue-related columns.

Investigate overload, provisioning, and repair queue time separately.

Do not treat them as the same root cause.

---

# Part 110 — Top Workload Template

## 129. Grouping

Analyze by warehouse, user, role, query tag, and time bucket to identify the source of demand.

---

# Part 111 — DBRE/SRE Troubleshooting Flow

## 130. Operational Flow

```text
Alert
  |
  v
Confirm impact
  |
  v
Capture query IDs
  |
  v
Check queue vs execution
  |
  +---- Queue
  |       |
  |       v
  |   Concurrency path
  |
  +---- Execution
          |
          v
      Query Profile
          |
          +---- Scan
          |      |
          |      v
          |   Pruning
          |
          +---- Join
          |
          +---- Spill
          |
          +---- Sort
          |
          +---- Aggregate
          |
          v
      Root cause
          |
          v
      Targeted fix
          |
          v
      Validate SLA
          |
          v
      Validate credits
```

---

# Part 112 — Prevention Framework

## 131. Detect Early

Monitor latency, queueing, spill, scan volume, credits, and concurrency.

## 132. Control Workloads

Use dedicated warehouses, query tags, scheduling, and cost controls.

## 133. Review Growth

Monitor table growth, partition growth, query growth, user growth, and concurrency growth.

## 134. Test Changes

Before major production deployments, compare representative queries, review Query Profile, measure P95/P99, and measure credits.

---

# Acceptance Criteria

The chapter is complete when you can:

- define Snowflake performance incidents precisely
- determine incident blast radius
- distinguish single-query and broad workload issues
- establish an exact incident window
- collect representative query IDs
- compare slow and fast executions
- understand the query lifecycle
- investigate compilation time
- identify warehouse provisioning delay
- identify overload queueing
- distinguish queue time from execution time
- use Query History
- understand ACCOUNT_USAGE and INFORMATION_SCHEMA roles
- use Query Profile
- identify expensive operators
- analyze table scans
- evaluate micro-partition pruning
- identify poor pruning
- evaluate filter selectivity
- identify Search Optimization candidates
- identify clustering candidates
- troubleshoot joins
- recognize join explosion
- identify missing join predicates
- identify duplicate-key multiplication
- recognize data skew
- analyze aggregation cost
- analyze sort cost
- analyze window functions
- understand local spill
- understand remote spill
- identify spill root causes
- identify scale-up candidates
- identify scale-out candidates
- benchmark warehouse resizing
- calculate cost per query
- distinguish warm and cold warehouse behavior
- understand persisted result reuse
- disable result reuse safely for controlled tests
- identify QAS candidates
- distinguish QAS from SQL remediation
- distinguish Search Optimization from QAS
- identify precomputation opportunities
- account for data growth
- account for partition growth
- detect query-pattern changes
- investigate data-type conversions
- avoid unnecessary SELECT *
- reduce unnecessary processing
- understand LIMIT misconceptions
- avoid generic CTE assumptions
- distinguish Snowflake execution from application latency
- investigate large result delivery
- investigate connection behavior
- correlate performance with changes
- review warehouse configuration history
- measure query-volume changes
- measure concurrency changes
- investigate overlapping workloads
- use query tagging for attribution
- attribute workload by user and role
- isolate warehouse-specific issues
- group query patterns
- maintain performance baselines
- define performance SLOs
- classify incident severity
- execute first-5-minute triage
- execute first-15-minute classification
- execute deeper performance investigation
- choose evidence-based mitigation
- distinguish temporary mitigation from permanent remediation
- use the performance decision tree
- use scan, join, spill, queue, cache, and cost checklists
- investigate query regressions
- capture production incident evidence
- write a precise RCA
- distinguish root cause from contributing factors
- define corrective actions
- implement preventive controls
- conduct weekly performance reviews
- conduct monthly architecture reviews
- recognize common performance anti-patterns
- follow an optimization order
- perform the hands-on troubleshooting lab
- diagnose broad scans
- diagnose selective filters
- diagnose range scans
- diagnose expensive sorting
- diagnose window-function workloads
- diagnose joins
- diagnose queueing
- compare warehouse sizes
- document evidence before remediation
- restore the lab safely
- use the production troubleshooting checklist
- build query-history investigations
- build queue investigations
- identify top workload sources
- execute the DBRE/SRE troubleshooting flow
- implement performance prevention controls

---

## Key Takeaways

When Snowflake is reported as slow, do not begin with a solution.

Begin with classification:

```text
Slow
 |
 v
Where is the time?
 |
 +---- Queue
 |       |
 |       v
 |   Concurrency
 |
 +---- Execution
 |       |
 |       v
 |   Query Profile
 |
 +---- Outside execution
         |
         v
   Provisioning / client /
   network / result handling
```

For execution problems:

```text
Query Profile
     |
     +---- Large scan
     |       |
     |       v
     |    Pruning
     |
     +---- Join explosion
     |
     +---- Spill
     |
     +---- Sort
     |
     +---- Aggregation
     |
     +---- Data skew
```

For concurrency problems:

```text
Queueing
   |
   v
Workload isolation
   |
   v
Scheduling
   |
   v
Scale out
```

For compute problems:

```text
Efficient query
+
Legitimate workload
+
Compute pressure
       |
       v
Evaluate scale up / QAS
```

The production rule is:

> Never increase compute until you understand what the additional compute is expected to fix.

And after every remediation:

```text
Performance improved?
        +
SLA restored?
        +
Credits acceptable?
        |
        v
Change validated
```

A complete performance investigation explains not only **what was slow**, but also:

```text
Why it was slow
How the evidence proves it
What fixed it
What the fix cost
How recurrence will be detected or prevented
```

The next chapter is **Chapter 46 — ACCOUNT_USAGE & INFORMATION_SCHEMA**.
