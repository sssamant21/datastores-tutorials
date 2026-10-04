# 40 — Caching: Result, Metadata & Warehouse Cache

## Overview

Caching is a major reason two executions of what appears to be the same Snowflake workload can have very different runtimes.

A query might take:

```text
First execution  = 45 seconds
Second execution = 2 seconds
```

That does not automatically mean the query was optimized. The second execution may have benefited from cached data or persisted query results.

For DBREs, SREs, administrators, developers, and performance engineers, understanding caching is essential because it affects query latency, warehouse behavior, performance testing, incident analysis, benchmarking, warehouse suspension decisions, workload isolation, query-cost interpretation, and before/after optimization validation.

A useful conceptual model is:

```text
Query
  |
  v
Can Snowflake reuse a persisted result?
  |
  +---- Yes ---> Return reusable result
  |
  +---- No
          |
          v
      Query execution
          |
          +---- Metadata/optimization information
          |
          +---- Warehouse compute
          |
          +---- Warehouse-local cached data where available
          |
          +---- Remote storage where required
```

This chapter focuses on three concepts:

```text
Persisted Query Results
Metadata / Cloud Services Optimization
Warehouse Data Cache
```

These mechanisms solve different problems and should not be treated as one generic "Snowflake cache."

---

# Part 1 — Why Caching Matters

## 1. Repeated Workloads

Analytical systems frequently execute similar or identical queries.

Examples include:

```text
Dashboard refreshes
BI reports
Scheduled analytics
Application queries
Data validation
Operational monitoring
Developer testing
```

Reusing previously available information can reduce repeated work.

## 2. Performance Impact

Caching can reduce data access, warehouse processing, and query execution time.

But the amount of benefit depends on which caching mechanism is involved.

---

# Part 2 — Three Different Concepts

## 3. Do Not Treat All Caching the Same

When someone says:

> Snowflake used cache.

Ask:

> Which cache or reuse mechanism?

The answer materially changes the investigation.

## 4. Conceptual Comparison

| Mechanism | Main Purpose | Typical Scope |
|---|---|---|
| Persisted query results | Reuse eligible previous query results | Query/result reuse |
| Metadata / Cloud Services optimization | Use metadata to plan and optimize work | Snowflake services layer |
| Warehouse data cache | Reuse table data already read by warehouse compute | Running warehouse |

These mechanisms have different lifecycles and behavior.

---

# Part 3 — Persisted Query Results

## 5. Concept

Snowflake can persist query results for eligible queries.

When Snowflake determines that a new query can reuse a valid previous result, it may return that result rather than execute the full workload again.

```text
Query submitted
      |
      v
Eligible reusable result?
      |
   +--+--+
   |     |
  Yes    No
   |     |
   v     v
Return  Execute
result  query
```

## 6. Why This Can Be Very Fast

If Snowflake can reuse a previous result, it may avoid substantial warehouse execution.

That can make repeated queries appear dramatically faster.

---

# Part 4 — Example of Result Reuse

## 7. First Execution

```sql
SELECT
    region,
    SUM(amount)
FROM sales
WHERE sale_date >= '2026-10-01'
GROUP BY region;
```

Suppose:

```text
Execution time = 18 seconds
```

## 8. Repeated Execution

The same eligible query is submitted again while the previous result remains reusable.

It may complete much faster.

## 9. Important Interpretation

Do not conclude:

> The warehouse became 20x faster.

The second execution may have avoided most of the original work.

---

# Part 5 — Persisted Results and Performance Testing

## 10. Benchmark Risk

Suppose you test:

```text
Before optimization = 30 sec
After optimization  = 1 sec
```

That appears to be a 30x improvement.

But if the second execution reused a persisted result, the comparison is invalid.

## 11. Production Rule

When benchmarking:

> Determine whether persisted result reuse influenced the measurement.

---

# Part 6 — USE_CACHED_RESULT

## 12. Session Control

Snowflake provides a session parameter commonly used during controlled testing:

```sql
ALTER SESSION SET USE_CACHED_RESULT = FALSE;
```

This can be useful when you need to prevent persisted query-result reuse from distorting a benchmark.

## 13. Restore Normal Behavior

After testing:

```sql
ALTER SESSION SET USE_CACHED_RESULT = TRUE;
```

Do not leave diagnostic settings changed unintentionally.

---

# Part 7 — What Disabling Cached Results Does Not Mean

## 14. Important Distinction

Setting:

```sql
ALTER SESSION SET USE_CACHED_RESULT = FALSE;
```

does not mean Snowflake now has no caching of any kind.

It addresses persisted query-result reuse.

The warehouse may still have locally cached table data.

---

# Part 8 — Result Reuse Eligibility

## 15. Not Every Repeated Query Is Guaranteed to Reuse Results

Result reuse depends on Snowflake determining that the previous result remains eligible and reusable.

## 16. Why Reuse Can Be Invalidated

Conceptually, result reuse can be affected when:

```text
Underlying data changes
Query semantics change
Relevant configuration changes
Reuse requirements are not satisfied
```

Use current Snowflake documentation for exact eligibility and reuse rules.

---

# Part 9 — Query Text and Semantics

## 17. Do Not Build Applications Around Assumed Cache Hits

Applications should remain correct whether Snowflake reuses a persisted result or executes the query.

Result reuse is an optimization, not an application correctness mechanism.

---

# Part 10 — Data Changes

## 18. Correctness Comes First

Suppose:

```text
Query A executes
      |
      v
Data changes
      |
      v
Query A executes again
```

Snowflake must preserve correct query semantics.

Do not assume an old persisted result will be returned after relevant underlying data changes.

---

# Part 11 — Persisted Results Are Not a Materialized View

## 19. Different Concepts

Persisted query results should not be confused with materialized views, dynamic tables, permanent tables, or application caches.

A persisted result is a query optimization mechanism.

---

# Part 12 — Warehouse Data Cache

## 20. Concept

A running virtual warehouse can maintain local cached data from previously accessed table data.

```text
Remote Snowflake Storage
         |
         v
Virtual Warehouse
         |
         +---- Local cached data
```

Repeated access to the same data may benefit from this cache.

---

# Part 13 — Cold vs Warm Warehouse

## 21. Cold Execution

A warehouse that has just started may not have useful local data cached for the workload.

```text
Query
  |
  v
Warehouse
  |
  v
Remote storage
```

## 22. Warm Execution

After data has been accessed:

```text
Query
  |
  v
Warehouse
  |
  +---- Local cache hit
  |
  +---- Remote storage for missing data
```

The second execution may therefore be faster even when persisted result reuse is disabled.

---

# Part 14 — Partial Cache Benefit

## 23. Cache Does Not Need to Be All-or-Nothing

A query may read some data from warehouse cache and some from remote storage.

```text
Required data = 1 TB

Warehouse cache = 600 GB
Remote read     = 400 GB
```

The query can still benefit substantially.

---

# Part 15 — Warehouse Suspension

## 24. Why Suspension Matters

Warehouse-local cache is associated with warehouse compute.

When the warehouse is suspended, do not assume its local cache remains available for future execution.

## 25. Operational Tradeoff

Aggressive auto-suspend can reduce idle compute cost.

But frequently suspending a warehouse can reduce opportunities for workloads to benefit from warm warehouse cache.

---

# Part 16 — Cost vs Cache Tradeoff

## 26. Example

Workload:

```text
Dashboard refresh every 3 minutes
```

Warehouse configuration:

```text
AUTO_SUSPEND = 60 seconds
```

Possible behavior:

```text
Dashboard query
Warehouse becomes idle
Warehouse suspends
Next dashboard refresh
Warehouse resumes
Cache is cold again
```

## 27. Do Not Disable Auto-Suspend Blindly

Keeping a warehouse running merely to preserve cache may waste credits.

Evaluate query frequency, latency requirement, warehouse cost, cache benefit, and idle duration.

---

# Part 17 — Warehouse Cache Is Warehouse-Specific

## 28. Separate Warehouses

```text
Warehouse A
    |
    +---- Local cache A

Warehouse B
    |
    +---- Local cache B
```

Do not assume warming one warehouse warms another independent warehouse.

---

# Part 18 — Workload Isolation and Cache

## 29. Isolation Has Tradeoffs

Separate warehouses provide useful workload isolation.

```text
ETL_WH
BI_WH
APP_WH
ADHOC_WH
```

Benefits include concurrency isolation, cost attribution, independent scaling, independent suspension, and failure-domain reduction.

But separate warehouses also have independent local cache behavior.

---

# Part 19 — Metadata

## 30. Snowflake Maintains Rich Metadata

Snowflake maintains metadata about storage structures such as micro-partitions.

This metadata is fundamental to optimization.

Examples conceptually include value ranges, partition characteristics, and data organization information.

---

# Part 20 — Metadata and Pruning

## 31. Chapter 38 Connection

Suppose a query asks for:

```sql
WHERE event_date = '2026-10-01';
```

Snowflake can use micro-partition metadata to identify partitions that cannot contain the requested values.

Those partitions can be pruned.

## 32. Important Distinction

This is not the same as reading table data from warehouse cache.

Metadata-driven elimination can prevent data from needing to be scanned in the first place.

---

# Part 21 — Cloud Services Layer

## 33. Metadata Processing

Snowflake's Cloud Services layer participates in activities such as authentication, authorization, metadata management, query parsing, optimization, and transaction coordination.

Caching discussions should therefore distinguish between metadata-driven optimization and warehouse-local data caching.

---

# Part 22 — Metadata Can Beat Data Cache

## 34. Better Than Reading Cached Data

Suppose a table contains 100,000 micro-partitions and metadata allows Snowflake to prune 99,500.

Then only 500 need consideration for scanning.

Avoiding the scan entirely is generally more powerful than simply reading unnecessary data faster.

---

# Part 23 — Performance Optimization Order

## 35. Good Optimization Sequence

```text
Reduce unnecessary work
        |
        v
Improve pruning
        |
        v
Reduce bytes scanned
        |
        v
Benefit from caching
        |
        v
Scale compute if still necessary
```

## 36. Bad Optimization Sequence

Avoid:

```text
Slow query
    |
    v
Increase warehouse
    |
    v
Hope cache helps
```

without understanding the underlying workload.

---

# Part 24 — Cache and Query Profile

## 37. Query Profile Evidence

Query Profile and query history should be used to understand what happened during execution.

Useful questions include whether the result was reused, how much data was scanned, how much data came from cache, whether execution occurred, and whether remote storage was accessed.

Use current Snowflake UI and metadata definitions for exact field names.

---

# Part 25 — Percentage Scanned from Cache

## 38. Useful Metric

Snowflake query telemetry can expose information related to the percentage of data scanned from cache.

This is useful when comparing cold and warm executions.

## 39. Example

Execution 1:

```text
Bytes scanned                 = 500 GB
Percentage scanned from cache = 0%
Runtime                       = 40 sec
```

Execution 2:

```text
Bytes scanned                 = 500 GB
Percentage scanned from cache = 85%
Runtime                       = 12 sec
```

This strongly suggests warehouse-local cache influenced the second execution.

---

# Part 26 — Query History

## 40. Historical Analysis

Query history can help compare execution time, bytes scanned, warehouse, warehouse size, cache-related metrics, queue time, and compilation time.

Chapter 47 covers Query History deeply.

---

# Part 27 — Query ID

## 41. Always Capture Query IDs

For performance investigations, record the slow query ID and fast query ID.

Then compare the two executions.

---

# Part 28 — Same SQL, Different Performance

## 42. Scenario

The same query takes:

```text
09:00 → 50 sec
09:05 → 8 sec
```

Possible reasons include persisted result reuse, warehouse cache, different warehouse state, different concurrency, different data, different query plan, or different pruning.

Do not attribute the difference to caching without evidence.

---

# Part 29 — Different SQL, Same Data

## 43. Warehouse Cache Can Still Help

Two queries do not need to be identical to access overlapping data.

```sql
SELECT SUM(amount)
FROM sales
WHERE sale_date >= '2026-10-01';
```

and:

```sql
SELECT COUNT(*)
FROM sales
WHERE sale_date >= '2026-10-01';
```

They cannot simply be treated as the same persisted query result.

However, both may access overlapping table data and potentially benefit from warehouse-local cache.

---

# Part 30 — Dashboard Workloads

## 44. BI Dashboards

Dashboards frequently issue repeated queries, similar queries, and queries against overlapping date ranges.

Caching can significantly affect observed dashboard performance.

## 45. Benchmark Carefully

Testing a dashboard immediately after several warm-up executions may not represent first-user or cold-start behavior.

---

# Part 31 — ETL Workloads

## 46. Batch Processing

ETL pipelines often scan newly arrived data.

If each run processes a completely new data range, warehouse cache may provide less benefit than for repetitive dashboard workloads.

## 47. Do Not Depend on Cache

Production ETL should meet its SLA without assuming that the required data is already cached.

---

# Part 32 — Application Workloads

## 48. Repetitive Access

Applications may repeatedly query the same reference data.

Warehouse cache or persisted results may help.

But application architecture should not assume a Snowflake cache hit.

---

# Part 33 — Benchmarking Methodology

## 49. Define What You Are Testing

Before benchmarking, decide whether you want to measure cold execution, warm execution, persisted-result behavior, warehouse-cache behavior, or typical production behavior.

These are different tests.

---

# Part 34 — Cold Execution Test

## 50. Goal

Measure performance without persisted-result reuse and without intentionally relying on warm warehouse data.

## 51. Considerations

A rigorous cold test may require careful warehouse-state control.

Do not claim a query is truly cold unless you have controlled the relevant conditions.

---

# Part 35 — Warm Execution Test

## 52. Goal

Measure performance under repeated workload conditions.

This can represent dashboard or application behavior more realistically.

## 53. Run Multiple Iterations

```text
Run 1
Run 2
Run 3
Run 4
Run 5
```

Record each separately.

---

# Part 36 — Avoid Single-Run Benchmarks

## 54. Why?

One execution can be influenced by warehouse startup, cache state, concurrency, queueing, transient workload, or Cloud Services activity.

## 55. Better Method

Collect multiple runs and compare median, range, outliers, cold behavior, and warm behavior.

---

# Part 37 — Controlled Benchmark Template

## 56. Record

```text
Query:
Query ID:

Warehouse:
Warehouse size:

Warehouse state before test:
AUTO_SUSPEND:

USE_CACHED_RESULT:

Run 1:
Run 2:
Run 3:
Run 4:
Run 5:

Bytes scanned:
Partitions scanned:
Percentage scanned from cache:

Queue time:
Execution time:
Total elapsed time:

Notes:
```

---

# Part 38 — Result Cache Troubleshooting

## 57. Symptom

A repeated query used to return almost instantly but now performs full execution.

## 58. Investigate

Check whether underlying data changed, query text/semantics changed, session/context changed, persisted-result reuse is enabled, and the previous result is still reusable.

Use current Snowflake documentation for exact reuse conditions.

---

# Part 39 — Warehouse Cache Troubleshooting

## 59. Symptom

Queries are fast during sustained activity but slower after idle periods.

## 60. Possible Cause

The warehouse may have suspended and later resumed without the previously useful local cache state.

## 61. Validate

Compare warehouse state, resume time, cache-related scan metrics, bytes scanned, and execution time.

Do not diagnose cache loss from runtime alone.

---

# Part 40 — Auto-Suspend Investigation

## 62. Example

Warehouse:

```text
AUTO_SUSPEND = 60
```

Queries arrive every five minutes.

The warehouse may repeatedly suspend between queries.

## 63. Possible Effects

```text
Frequent resumes
Reduced cache reuse
Potential latency variation
Compute startup overhead
```

## 64. Decision

Do not simply increase auto-suspend.

Measure whether the performance improvement justifies additional idle credits.

---

# Part 41 — FinOps Considerations

## 65. Caching Can Reduce Work

Effective reuse can reduce repeated compute work.

## 66. But Keeping Warehouses Running Costs Money

A warehouse kept active solely to preserve cache can consume credits while idle.

## 67. Optimize Total Cost

Evaluate idle compute cost, resume behavior, query latency, query frequency, cache benefit, and business SLA.

---

# Part 42 — Common Caching Mistakes

## 68. Mistake — Second Run Means Optimization Worked

Wrong.

The second run may simply be warmer.

## 69. Mistake — USE_CACHED_RESULT = FALSE Disables All Cache

Wrong.

It addresses persisted query-result reuse, not every Snowflake caching mechanism.

## 70. Mistake — Warehouse Cache Is Shared Everywhere

Wrong.

Treat local cache as warehouse-specific.

## 71. Mistake — Never Suspend Warehouses

Wrong.

This can waste credits.

## 72. Mistake — Suspend as Aggressively as Possible

Also wrong.

For some frequent latency-sensitive workloads, overly aggressive suspension can create undesirable performance behavior.

## 73. Mistake — Optimize Cache Before Pruning

Wrong.

Avoiding unnecessary scans is usually more important than making unnecessary scans faster.

---

# Part 43 — Production Performance Test

## 74. Scenario

A query optimization is proposed.

Before:

```text
Runtime = 45 sec
```

After:

```text
Runtime = 5 sec
```

## 75. Required Questions

Before declaring success:

```text
Were both executions on the same warehouse?
Was warehouse size the same?
Was persisted-result reuse controlled?
Was cache state comparable?
Were partitions scanned comparable?
Were bytes scanned comparable?
Was concurrency comparable?
```

---

# Part 44 — Before/After Validation

## 76. Weak Evidence

```text
Before = 45 sec
After  = 5 sec
```

This is insufficient.

## 77. Stronger Evidence

```text
Before Query ID:
After Query ID:

Same warehouse:
Same warehouse size:

Persisted result controlled:

Before partitions scanned:
After partitions scanned:

Before bytes scanned:
After bytes scanned:

Before cache percentage:
After cache percentage:

Before execution:
After execution:

Result correctness:
```

---

# Part 45 — Production Incident Runbook

## 78. Cache-Related Performance Regression

1. Capture slow query ID.
2. Capture comparable fast query ID.
3. Confirm SQL/query semantics.
4. Compare warehouse.
5. Compare warehouse size.
6. Check warehouse state.
7. Check recent resume/suspend behavior.
8. Compare bytes scanned.
9. Compare partitions scanned.
10. Compare cache-related scan metrics.
11. Determine whether persisted-result reuse occurred.
12. Check whether underlying data changed.
13. Check concurrency.
14. Check queueing.
15. Compare execution profile.
16. Confirm cache is actually causal.
17. Avoid changing auto-suspend without evidence.
18. Test controlled remediation.
19. Compare cost.
20. Document root cause.

---

# Part 46 — Cache Evidence Template

## 79. Investigation Template

```text
Query:

Slow query ID:
Fast query ID:

Warehouse:
Warehouse size:

Warehouse state:
Last resume:
Last suspend:

USE_CACHED_RESULT:

Slow execution time:
Fast execution time:

Slow bytes scanned:
Fast bytes scanned:

Slow partitions scanned:
Fast partitions scanned:

Slow cache percentage:
Fast cache percentage:

Persisted result reused:

Underlying data changed:

Concurrency difference:

Queueing difference:

Observed cause:

Recommended action:

Cost impact:
```

---

# Part 47 — Production Example: Dashboard

## 80. Scenario

A dashboard is reported as:

```text
Fast during the day
Slow every morning
```

## 81. Investigation

Warehouse:

```text
BI_WH
AUTO_SUSPEND = 300
```

The warehouse is inactive overnight.

## 82. Morning Behavior

First dashboard queries may run against a newly resumed warehouse.

Later queries may benefit from warm local data.

## 83. Recommendation

Do not immediately keep the warehouse running overnight.

Determine morning latency requirement, number of affected users, cost of idle warehouse, potential scheduled warm-up alternatives, and query optimization opportunities.

Use measured economics.

---

# Part 48 — Production Example: False Optimization

## 84. Scenario

Developer changes:

```sql
SELECT *
FROM events
WHERE event_date = '2026-10-01';
```

to another logically equivalent form.

They report:

```text
Old query = 25 sec
New query = 0.8 sec
```

## 85. Investigation

The new query was executed immediately after another query accessed the same data.

## 86. Conclusion

The performance result cannot be attributed solely to the SQL rewrite.

Run a controlled benchmark.

---

# Part 49 — Production Example: Result Reuse

## 87. Scenario

A BI tool repeatedly issues the same query.

Execution appears nearly instantaneous after the first run.

## 88. Interpretation

Investigate whether persisted query-result reuse is responsible before attributing performance to warehouse size.

---

# Part 50 — Production Example: ETL

## 89. Scenario

A daily pipeline processes yesterday's new data.

Each day uses a different range.

## 90. Interpretation

Warehouse-local cache from yesterday's processing may not materially help today's new range.

Focus optimization on pruning, data layout, query design, warehouse sizing, and pipeline architecture rather than depending on cache.

---

# Part 51 — Cache and Warehouse Sizing

## 91. Do Not Confuse Cache Benefit with Compute Requirement

A warm query may perform well on a warehouse even though its cold execution is much slower.

## 92. SLA Design

If an SLA must hold after warehouse resume, test the resumed/cold behavior.

Do not size exclusively from warm benchmarks.

Chapter 43 covers warehouse sizing deeply.

---

# Part 52 — Cache and Multi-Cluster Warehouses

## 93. Concurrency Architecture

Multi-cluster warehouses are primarily used to address concurrency.

Different clusters should not be assumed to have identical local cache state.

## 94. Testing

When evaluating a multi-cluster workload, consider that requests may not always execute against compute with the same warm-cache history.

Chapter 44 covers multi-cluster warehouses and concurrency.

---

# Part 53 — Cache and Clustering

## 95. Different Optimizations

Clustering improves physical organization and pruning.

Warehouse cache accelerates access to previously read data.

## 96. Do Not Use Cache to Hide Poor Clustering

If:

```text
Cold query = 90 sec
Warm query = 15 sec
```

but the query unnecessarily scans several terabytes, investigate pruning rather than accepting the warm result.

---

# Part 54 — Cache and Search Optimization

## 97. Different Purpose

Search Optimization can improve selected lookup/access patterns.

Cache improves repeated access.

Do not treat them as substitutes.

---

# Part 55 — Cache and Materialized Views

## 98. Different Purpose

Materialized views maintain precomputed results for supported query patterns.

Persisted query results reuse previous eligible query results.

Warehouse cache stores locally useful data for compute.

These are separate mechanisms.

---

# Part 56 — Cache-Aware SRE Monitoring

## 99. Monitor Patterns, Not Just Average Runtime

Averages can hide cold-start latency, warm-cache latency, queueing, and result reuse.

## 100. Example

Average:

```text
10 sec
```

Actual:

```text
Cold executions = 40 sec
Warm executions = 5 sec
```

For a customer-facing SLA, the cold behavior may be more important than the average.

---

# Part 57 — Hands-On Lab

## 101. Lab Objective

Observe differences between persisted result reuse, warehouse-local cache effects, and cold/warm execution.

Use a non-production environment.

## 102. Create Database

```sql
CREATE OR REPLACE DATABASE cache_lab;
```

## 103. Create Schema

```sql
CREATE OR REPLACE SCHEMA cache_lab.demo;
```

## 104. Create Table

```sql
CREATE OR REPLACE TABLE cache_lab.demo.sales (
    sale_id NUMBER,
    customer_id NUMBER,
    sale_date DATE,
    region STRING,
    amount NUMBER(12,2)
);
```

## 105. Generate Synthetic Data

```sql
INSERT INTO cache_lab.demo.sales
SELECT
    SEQ4(),
    MOD(SEQ4(), 100000),
    DATEADD(
        day,
        -MOD(SEQ4(), 365),
        CURRENT_DATE()
    ),
    CASE MOD(SEQ4(), 4)
        WHEN 0 THEN 'EAST'
        WHEN 1 THEN 'WEST'
        WHEN 2 THEN 'SOUTH'
        ELSE 'NORTH'
    END,
    MOD(SEQ4(), 100000) / 100.0
FROM TABLE(GENERATOR(ROWCOUNT => 10000000));
```

All data is synthetic.

## 106. Baseline Query

```sql
SELECT
    region,
    COUNT(*) AS transactions,
    SUM(amount) AS total_amount
FROM cache_lab.demo.sales
WHERE sale_date >= DATEADD(day, -90, CURRENT_DATE())
GROUP BY region;
```

Record query ID, execution time, bytes scanned, partitions scanned, and cache-related scan metrics.

## 107. Repeat Immediately

Execute the same query again.

Record the same metrics.

## 108. Compare

Ask whether execution was dramatically faster, whether a persisted result was reused, and whether the warehouse executed the scan again.

## 109. Disable Persisted Result Reuse

```sql
ALTER SESSION SET USE_CACHED_RESULT = FALSE;
```

## 110. Execute Again

Run:

```sql
SELECT
    region,
    COUNT(*) AS transactions,
    SUM(amount) AS total_amount
FROM cache_lab.demo.sales
WHERE sale_date >= DATEADD(day, -90, CURRENT_DATE())
GROUP BY region;
```

Now inspect warehouse execution behavior.

## 111. Repeat with Result Reuse Disabled

Run the same query several times.

| Run | Runtime | Bytes Scanned | Cache % |
|---|---:|---:|---:|
| 1 | | | |
| 2 | | | |
| 3 | | | |

This helps demonstrate warehouse-local cache effects separately from persisted result reuse.

## 112. Different Query, Similar Data

```sql
SELECT
    region,
    AVG(amount) AS average_amount
FROM cache_lab.demo.sales
WHERE sale_date >= DATEADD(day, -90, CURRENT_DATE())
GROUP BY region;
```

This accesses a similar data range but computes a different result.

Compare its cache-related metrics.

## 113. Narrower Range

```sql
SELECT
    region,
    SUM(amount)
FROM cache_lab.demo.sales
WHERE sale_date >= DATEADD(day, -7, CURRENT_DATE())
GROUP BY region;
```

Compare pruning and cache effects.

## 114. Restore Session

```sql
ALTER SESSION SET USE_CACHED_RESULT = TRUE;
```

## 115. Cleanup

```sql
DROP DATABASE IF EXISTS cache_lab;
```

---

# Part 58 — Lab Results Template

## 116. Record Results

| Test | Result Reuse | Runtime | Bytes Scanned | Cache % |
|---|---|---:|---:|---:|
| First execution | | | | |
| Immediate repeat | | | | |
| Cached result disabled #1 | No | | | |
| Cached result disabled #2 | No | | | |
| Different SQL / same range | No direct result reuse | | | |

---

# Part 59 — Production Checklist

## 117. Performance Testing

- Query IDs captured
- Same warehouse used
- Same warehouse size used
- Persisted-result behavior controlled
- Warehouse state recorded
- Cache metrics recorded
- Partitions scanned recorded
- Bytes scanned recorded
- Multiple executions tested
- Result correctness validated

## 118. Auto-Suspend Review

- Query frequency understood
- Idle intervals measured
- Resume frequency measured
- Cold latency measured
- Warm latency measured
- Idle credit cost understood
- SLA requirement documented

## 119. Incident Investigation

- Slow and fast query IDs compared
- Result reuse checked
- Warehouse cache behavior checked
- Warehouse resume/suspend checked
- Query Profile compared
- Queueing checked
- Data changes checked
- Pruning checked
- Cost impact reviewed

---

# Part 60 — Operational Principles

## 120. Never Benchmark Blindly

Before saying:

> Query performance improved by 90%.

Know whether you compared cold vs cold, warm vs warm, cached result vs execution, or different warehouse states.

## 121. Cache Is an Optimization, Not a Guarantee

Production systems should remain correct and operational even when a persisted result cannot be reused, warehouse cache is cold, or the warehouse has just resumed.

## 122. Optimize the Root Cause

Preferred order:

```text
Correct query
      |
      v
Good pruning
      |
      v
Reasonable bytes scanned
      |
      v
Appropriate warehouse
      |
      v
Cache benefit
```

Do not reverse this order.

## 123. Measure Cost and Performance Together

A caching strategy is successful when it supports the required SLA at an acceptable total cost.

---

# Acceptance Criteria

The chapter is complete when you can:

- distinguish Snowflake caching mechanisms
- explain persisted query-result reuse
- explain why repeated queries can appear dramatically faster
- understand result-reuse eligibility conceptually
- use `USE_CACHED_RESULT` during controlled testing
- understand that disabling persisted results does not disable warehouse cache
- distinguish persisted results from materialized views
- explain warehouse-local data caching
- distinguish cold and warm warehouse behavior
- understand partial cache benefit
- explain why warehouse suspension matters
- evaluate auto-suspend/cache tradeoffs
- understand warehouse-specific cache behavior
- understand workload-isolation implications
- explain metadata-driven optimization
- distinguish metadata pruning from data caching
- understand Cloud Services' role conceptually
- prioritize pruning over cache dependency
- analyze cache-related Query Profile/query-history evidence
- interpret percentage-scanned-from-cache concepts
- capture query IDs
- investigate same-SQL/different-runtime scenarios
- understand overlapping-data queries
- evaluate dashboard caching behavior
- evaluate ETL caching behavior
- evaluate application caching behavior
- design cold and warm benchmarks
- avoid single-run performance conclusions
- build a controlled benchmark
- troubleshoot result-reuse changes
- troubleshoot warehouse-cache changes
- investigate auto-suspend effects
- evaluate FinOps tradeoffs
- avoid common caching mistakes
- validate before/after optimization fairly
- execute a cache-related incident runbook
- capture cache evidence consistently
- evaluate dashboard cold-start behavior
- identify false optimization results
- understand cache implications for warehouse sizing
- understand cache implications for multi-cluster warehouses
- distinguish caching from clustering
- distinguish caching from Search Optimization
- distinguish caching from materialized views
- monitor cold and warm latency separately
- perform the hands-on cache lab
- restore diagnostic session settings after testing
- integrate caching analysis with performance and cost engineering

---

## Key Takeaways

Snowflake does not have one single generic cache.

For production analysis, distinguish:

```text
Persisted Query Results
        |
        +---- Reuses eligible previous query result

Warehouse Data Cache
        |
        +---- Reuses table data available to warehouse compute

Metadata / Cloud Services
        |
        +---- Helps optimize work and eliminate unnecessary scanning
```

When the same query suddenly becomes much faster, do not immediately conclude that SQL optimization or warehouse resizing solved the problem.

Investigate result reuse, warehouse cache, warehouse state, pruning, bytes scanned, concurrency, and queueing.

For controlled testing:

```sql
ALTER SESSION SET USE_CACHED_RESULT = FALSE;
```

can help prevent persisted query-result reuse from distorting the test, but it does **not** disable every caching mechanism.

A strong performance test compares equivalent conditions:

```text
Same warehouse
Same warehouse size
Known cache/result-reuse state
Comparable concurrency
Same business result
Multiple executions
```

Finally, do not use cache to hide inefficient scanning.

The preferred strategy is:

```text
Eliminate unnecessary work
        |
        v
Improve pruning
        |
        v
Reduce data scanned
        |
        v
Size compute correctly
        |
        v
Allow caching to provide additional benefit
```

Caching should improve an already sound workload design—not compensate for an inefficient one.

The next chapter is **Chapter 41 — Search Optimization Service**.
