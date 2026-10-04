# 42 — Query Acceleration Service

## Overview

Snowflake's Query Acceleration Service (QAS) can improve the performance of eligible queries by using additional serverless compute resources to process portions of query workloads.

The important distinction is:

```text
Virtual Warehouse
       |
       +---- Normal query processing
       |
       +---- Eligible work can be offloaded
                       |
                       v
             Query Acceleration Service
                       |
                       v
              Serverless compute
```

QAS does **not** replace the virtual warehouse.

It supplements warehouse compute for eligible portions of eligible queries.

This makes QAS fundamentally different from warehouse resizing, multi-cluster warehouses, Search Optimization, Automatic Clustering, caching, and materialized views.

A production team should not enable QAS simply because queries are slow.

The correct process is:

```text
Slow workload
      |
      v
Identify bottleneck
      |
      v
Is the query a QAS candidate?
      |
     Yes
      |
      v
Estimate benefit and cost
      |
      v
Controlled test
      |
      v
Measure latency + credits
      |
      v
Production decision
```

This chapter covers Query Acceleration Service architecture, serverless compute, candidate queries, eligibility, query acceleration estimates, scale factor, warehouse configuration, Query Profile, Query History, monitoring, cost, comparisons with other Snowflake optimization techniques, workload selection, production rollout, troubleshooting, incident investigation, hands-on testing, and FinOps controls.

---

# Part 1 — Why Query Acceleration Exists

## 1. Large Analytical Queries

Consider a query that performs:

```text
Large scan
   |
   v
Filtering
   |
   v
Aggregation
   |
   v
Large amount of work
```

The warehouse performs the query, but selected work may be suitable for acceleration.

## 2. Traditional Response

A common reaction is:

```text
Query slow
   |
   v
Resize warehouse
```

For example:

```text
MEDIUM
   |
   v
LARGE
   |
   v
XLARGE
```

This may improve performance.

But resizing changes the compute capacity for the entire warehouse workload.

QAS provides another option for appropriate workloads.

---

# Part 2 — QAS Architecture

## 3. Supplemental Compute

Conceptually:

```text
                 Query
                   |
                   v
            Virtual Warehouse
                   |
          +--------+--------+
          |                 |
          v                 v
   Warehouse work     Eligible work
                            |
                            v
                  Query Acceleration
                       Service
                            |
                            v
                  Serverless compute
```

The virtual warehouse remains responsible for the query.

QAS provides supplemental compute for eligible work.

---

# Part 3 — Serverless Compute

## 4. Snowflake-Managed Resources

QAS uses Snowflake-managed serverless resources.

You do not create separate QAS worker warehouses.

```text
Your Warehouse
      +
Snowflake-managed
serverless acceleration
```

## 5. Operational Advantage

This can provide temporary additional processing capacity without permanently resizing the warehouse.

---

# Part 4 — QAS Is Workload-Specific

## 6. Not Every Query Benefits

QAS should not be treated as:

> Make every query faster.

Some queries may not be eligible.

Some eligible queries may receive little benefit.

Some queries may have bottlenecks elsewhere.

## 7. Example

Suppose a query spends most of its time waiting for a warehouse queue.

QAS may not address the fundamental concurrency problem.

Another query may be dominated by external API latency.

Again, QAS is unlikely to be the correct primary solution.

---

# Part 5 — Candidate Workloads

## 8. General Candidate Characteristics

QAS is worth investigating when queries involve substantial eligible processing and when acceleration could materially reduce elapsed time.

Candidate workloads often include large analytical operations where portions of the work can be parallelized or offloaded.

Always validate exact current eligibility against Snowflake documentation.

---

# Part 6 — Query Eligibility

## 9. Eligibility Matters

The first question is not:

> Is the query slow?

The first question is:

> Is this query eligible for Query Acceleration?

Snowflake provides mechanisms to help identify candidate queries and estimate potential acceleration.

---

# Part 7 — Candidate Identification

## 10. Production Approach

Use Snowflake query history and QAS-related metadata/functions to identify queries that may benefit.

```text
Query History
      |
      v
Long-running queries
      |
      v
QAS candidate evaluation
      |
      v
Potential benefit
      |
      v
Controlled test
```

Do not choose candidates based only on runtime.

---

# Part 8 — Query Acceleration Estimate

## 11. Estimation

Snowflake provides functionality for estimating whether queries may benefit from Query Acceleration.

```text
Historical Query
       |
       v
QAS Estimate
       |
       +---- Not a strong candidate
       |
       +---- Potential candidate
```

Use the current Snowflake documentation for the exact function syntax and output fields.

---

# Part 9 — SYSTEM$ESTIMATE_QUERY_ACCELERATION

## 12. Candidate Evaluation

A Snowflake system function commonly used for this purpose is:

```sql
SELECT SYSTEM$ESTIMATE_QUERY_ACCELERATION('<query_id>');
```

The function can provide information that helps determine whether a query may benefit from Query Acceleration.

Always validate current function behavior and output fields against the Snowflake version/documentation used by your account.

---

# Part 10 — Query IDs

## 13. Capture Representative Queries

Do not evaluate random SQL text.

Capture actual production query IDs.

For example:

```text
Query ID:
01abc123-...
```

Then evaluate representative executions.

---

# Part 11 — One Query Is Not Enough

## 14. Workload Sampling

A single query execution may not represent the workload.

Collect 10, 50, or 100 queries depending on workload size and variability.

Evaluate representative queries across normal load, peak load, different data ranges, different users, and different warehouses.

---

# Part 12 — Scale Factor

## 15. Controlling Acceleration

QAS configuration includes a scale factor that limits how much serverless compute can be used relative to the warehouse.

```text
Warehouse compute
       |
       +---- QAS scale factor
                 |
                 v
        Maximum acceleration
        resource allowance
```

## 16. Why Scale Factor Matters

Higher scale factors can potentially allow more acceleration resources.

But they can also increase serverless credit consumption.

---

# Part 13 — Scale Factor Is a Cost Control

## 17. Do Not Treat It as a Performance Knob Only

The scale factor controls both potential performance and potential cost exposure.

Therefore:

```text
Higher scale factor
       !=
Always better
```

## 18. Production Principle

Start conservatively.

Measure.

Increase only when evidence justifies it.

---

# Part 14 — Enabling Query Acceleration

## 19. Warehouse Configuration

QAS is configured at the virtual warehouse level.

A commonly used configuration pattern is conceptually:

```sql
ALTER WAREHOUSE analytics_wh
SET ENABLE_QUERY_ACCELERATION = TRUE;
```

A scale factor can also be configured.

Exact syntax and parameter behavior should be validated against current Snowflake documentation before production execution.

---

# Part 15 — Maximum Scale Factor

## 20. Example Concept

A configuration may conceptually resemble:

```sql
ALTER WAREHOUSE analytics_wh
SET
    ENABLE_QUERY_ACCELERATION = TRUE
    QUERY_ACCELERATION_MAX_SCALE_FACTOR = 4;
```

Validate the current allowed values, defaults, and semantics before using this in production.

---

# Part 16 — Disabling QAS

## 21. Rollback

A production change should always include a reversal path.

Conceptually:

```sql
ALTER WAREHOUSE analytics_wh
SET ENABLE_QUERY_ACCELERATION = FALSE;
```

Validate current syntax before production use.

---

# Part 17 — QAS vs Warehouse Resizing

## 22. Warehouse Resizing

Resizing:

```text
MEDIUM
   |
   v
LARGE
```

changes the compute resources available to the warehouse.

## 23. QAS

QAS:

```text
Existing warehouse
       +
Serverless acceleration
for eligible query work
```

## 24. Decision

Warehouse resizing may be appropriate when many queries consistently need more compute.

QAS may be attractive when selected eligible workloads need burst acceleration.

Measure both approaches when economics matter.

---

# Part 18 — QAS vs Multi-Cluster Warehouse

## 25. Multi-Cluster Warehouses

Multi-cluster warehouses primarily address concurrency.

```text
100 simultaneous queries
          |
          v
Warehouse queue
```

Adding clusters can provide additional capacity for concurrent workloads.

## 26. QAS

QAS primarily targets eligible processing within queries.

```text
Concurrency problem
      |
      v
Evaluate multi-cluster

Eligible expensive query work
      |
      v
Evaluate QAS
```

---

# Part 19 — Scale Up vs Scale Out vs Accelerate

## 27. Three Different Decisions

```text
Scale Up
   |
   v
Larger warehouse

Scale Out
   |
   v
More warehouse clusters

Accelerate
   |
   v
QAS serverless resources
```

These solve different problems.

---

# Part 20 — QAS vs Search Optimization

## 28. Search Optimization

Chapter 41 covered highly selective lookup patterns.

```sql
WHERE claim_id = 'CLAIM-EXAMPLE-1001'
```

Search Optimization can provide a more efficient access path for supported searches.

## 29. QAS

QAS provides supplemental compute for eligible query work.

Do not use QAS to hide a fundamentally inefficient point lookup when Search Optimization or better pruning would eliminate unnecessary scanning.

---

# Part 21 — QAS vs Clustering

## 30. Clustering

Clustering improves data organization and can improve micro-partition pruning.

## 31. QAS

QAS adds compute.

A useful principle is:

```text
Reduce unnecessary work first
          |
          v
Accelerate remaining necessary work
```

---

# Part 22 — QAS vs Caching

## 32. Cache

Caching can reduce repeated data access or reuse eligible query results.

## 33. QAS

QAS accelerates eligible query processing.

A warm-cache query and a cold query may therefore show different QAS economics.

Use controlled tests.

---

# Part 23 — QAS vs Materialized Views

## 34. Materialized Views

Materialized views maintain precomputed results for supported workloads.

## 35. QAS

QAS does not precompute the result.

It supplies additional compute during eligible query execution.

---

# Part 24 — QAS vs Dynamic Tables

## 36. Dynamic Tables

Dynamic tables can move transformation work into declaratively maintained pipelines.

If a dashboard repeatedly executes an expensive transformation, consider whether the architecture should precompute some of that data instead of accelerating the same transformation repeatedly.

---

# Part 25 — Fix Query Design First

## 37. Example

Suppose:

```sql
SELECT *
FROM enormous_table;
```

returns columns the application never uses.

Enabling QAS does not correct the poor projection.

## 38. Preferred Sequence

```text
Query design
     |
     v
Pruning
     |
     v
Data scanned
     |
     v
Warehouse sizing
     |
     v
QAS evaluation
```

---

# Part 26 — Query Profile Before QAS

## 39. Understand the Bottleneck

Inspect Query Profile before enabling QAS.

Look for evidence such as:

```text
Large scans
Expensive filters
Heavy aggregation
Data redistribution
Spill
Skew
Join explosion
Queueing
```

## 40. QAS Cannot Fix Everything

If the query is slow because of join explosion, bad SQL logic, external dependency, lock/transaction issue, queueing, or poor data model, QAS may not address the root cause.

---

# Part 27 — Query History

## 41. Workload Analysis

Query History helps identify:

```text
Long-running queries
Frequently executed queries
Warehouse
Warehouse size
Execution time
Queueing
Bytes scanned
```

Use this data to identify potential QAS candidates.

---

# Part 28 — Production Candidate Matrix

## 42. Example

| Query | Frequency | Runtime | Bytes Scanned | SLA Impact | QAS Candidate |
|---|---:|---:|---:|---|---|
| Q1 | 5/day | 20 min | Very high | High | Evaluate |
| Q2 | 1M/day | 200 ms | Low | Low | Poor candidate |
| Q3 | 100/day | 5 min | High | Critical | Evaluate |
| Q4 | 500/day | 30 sec | Low | Medium | Investigate bottleneck |

---

# Part 29 — Cost Model

## 43. QAS Uses Additional Credits

Query Acceleration serverless compute can consume additional credits.

Therefore:

```text
Faster query
     !=
Cheaper query
```

## 44. Total Cost

Evaluate:

```text
Warehouse credits
       +
QAS credits
       =
Total compute cost
```

---

# Part 30 — Business Value

## 45. Cost Can Still Be Justified

Suppose:

```text
Before = 20 minutes
After  = 3 minutes
```

For a business-critical workflow, the additional QAS cost may be justified.

For a monthly internal report, it may not be.

---

# Part 31 — Cost per Query

## 46. Useful Metric

Calculate cost per execution before and after QAS.

Then calculate daily, monthly, and annual cost.

---

# Part 32 — Serverless Usage Monitoring

## 47. Monitor QAS Consumption

Snowflake provides usage information for Query Acceleration serverless compute.

Use current `ACCOUNT_USAGE` or other supported monitoring interfaces to determine credits consumed, warehouse, time period, and usage trend.

Validate exact view names and fields against current Snowflake documentation.

---

# Part 33 — Warehouse-Level Cost

## 48. Attribution

Because QAS is enabled on a warehouse, monitor usage by warehouse.

```text
ANALYTICS_WH
    |
    +---- Warehouse credits
    |
    +---- QAS credits
```

This supports FinOps attribution.

---

# Part 34 — Cost Guardrails

## 49. Recommended Controls

For production:

```text
Start with limited warehouses
Use conservative scale factor
Monitor daily credits
Set budget thresholds
Review candidate workload
Compare SLA improvement
```

---

# Part 35 — Production Rollout Strategy

## 50. Phase 1 — Baseline

Collect:

```text
Query IDs
Runtime
Warehouse
Warehouse size
Bytes scanned
Partitions scanned
Queueing
Query Profile
Daily frequency
Business SLA
```

## 51. Phase 2 — Candidate Estimate

Use Snowflake's QAS estimation capability on representative queries.

## 52. Phase 3 — Controlled Enablement

Enable QAS on a selected non-production or controlled production warehouse.

Use a conservative scale factor.

## 53. Phase 4 — Validate

Compare:

```text
Before runtime
After runtime

Before warehouse credits
After warehouse credits

QAS credits

Total cost
```

## 54. Phase 5 — Expand or Roll Back

If the performance/cost ratio is acceptable, expand carefully.

Otherwise, disable or redesign.

---

# Part 36 — Benchmarking

## 55. Disable Persisted Result Reuse

For controlled performance tests:

```sql
ALTER SESSION SET USE_CACHED_RESULT = FALSE;
```

This helps prevent persisted query-result reuse from invalidating the test.

## 56. Cache Still Matters

As covered in Chapter 40, this does not eliminate warehouse-local cache effects.

Record warehouse state.

---

# Part 37 — Multiple Executions

## 57. Avoid One-Run Tests

Run:

```text
Before #1
Before #2
Before #3

After #1
After #2
After #3
```

Prefer a larger representative sample for production decisions.

---

# Part 38 — Compare Equivalent Conditions

## 58. Keep Constant

Where practical:

```text
Same SQL
Same warehouse
Same warehouse size
Same data
Similar concurrency
Same result
Comparable cache conditions
```

---

# Part 39 — QAS and Concurrency

## 59. Do Not Confuse Queue Time with Execution Time

Suppose:

```text
Total elapsed = 90 sec

Queue time     = 70 sec
Execution      = 20 sec
```

Accelerating execution cannot remove the 70-second queue.

The primary problem is concurrency/capacity.

---

# Part 40 — QAS and Spill

## 60. Spill Scenario

Suppose Query Profile shows significant remote spill.

Before assuming QAS is the solution, investigate:

```text
Warehouse memory
Join design
Aggregation
Sort
Data skew
Intermediate row explosion
```

Warehouse resizing or SQL redesign may be more appropriate.

---

# Part 41 — QAS and Join Explosion

## 61. Example

A join unexpectedly produces:

```text
Input rows = 100 million
Output intermediate rows = 40 billion
```

QAS should not be used as the first response.

Fix the join.

---

# Part 42 — QAS and Poor Pruning

## 62. Example

A query scans:

```text
95,000 of 100,000 partitions
```

when business logic should require a small date range.

Investigate pruning first.

---

# Part 43 — QAS and SELECT *

## 63. Projection

If a query requests 150 columns but uses only 10, reduce unnecessary projection before adding compute.

---

# Part 44 — QAS and ETL

## 64. Large Batch Queries

ETL workloads can contain large transformations that may be QAS candidates.

But also evaluate pipeline architecture, incremental processing, MERGE design, pruning, and warehouse sizing.

---

# Part 45 — QAS and BI

## 65. Dashboard Queries

A dashboard query may be business-critical.

But if the same expensive transformation runs thousands of times, consider whether precomputation is more economical.

Possible alternatives include dynamic tables, materialized views, and aggregate tables.

---

# Part 46 — QAS and Ad Hoc Analytics

## 66. Analyst Workloads

Ad hoc analytical queries can be unpredictable.

QAS may provide useful burst acceleration for eligible queries without permanently oversizing the warehouse.

This can be a strong use case when controlled economically.

---

# Part 47 — QAS and SLA

## 67. Define the Requirement

Example:

```text
Current P95 = 8 minutes
Required P95 = 3 minutes
```

Do not define success as:

> Query feels faster.

Define measurable acceptance criteria.

---

# Part 48 — Before/After Evidence

## 68. Evidence Template

```text
Query:
Query ID before:
Query ID after:

Warehouse:
Warehouse size:

QAS enabled:
QAS scale factor:

Before runtime:
After runtime:

Before bytes scanned:
After bytes scanned:

Before queue:
After queue:

Warehouse credits:
QAS credits:
Total credits:

SLA:
Result:
```

---

# Part 49 — Troubleshooting: No Improvement

## 69. Symptom

QAS is enabled but query runtime is unchanged.

## 70. Investigate

Check:

```text
Is the query eligible?
Did QAS actually accelerate it?
Is the dominant operator eligible?
Is queueing the bottleneck?
Is the query waiting on an external dependency?
Is poor pruning the real problem?
Is join explosion dominating?
Is warehouse memory/spill dominating?
```

---

# Part 50 — Troubleshooting: Cost Increased

## 71. Symptom

QAS credits increase significantly.

## 72. Investigate

Check:

```text
Which warehouse?
Which queries?
Query frequency changed?
Scale factor changed?
New workload?
Large backfill?
New dashboard?
ETL schedule changed?
Was latency improvement worth it?
```

---

# Part 51 — Troubleshooting: Only Some Queries Improve

## 73. Expected Possibility

QAS is workload-specific.

Different queries can have different eligibility and acceleration opportunities.

## 74. Do Not Generalize

Do not conclude:

> QAS works for this warehouse.

Instead determine:

> Which query families benefit from QAS on this warehouse?

---

# Part 52 — Troubleshooting: QAS Enabled on Wrong Warehouse

## 75. Scenario

QAS is enabled on `BI_WH` but the expensive workload runs on `ETL_WH`.

Always confirm actual query-to-warehouse mapping.

---

# Part 53 — Troubleshooting: Application Changed

## 76. Scenario

QAS historically provided good results.

After an application release, performance changes.

Compare SQL text, Query Profile, data scanned, join pattern, filters, warehouse, and QAS eligibility.

The new query may have different acceleration characteristics.

---

# Part 54 — Production Incident Runbook

## 77. Slow Query with QAS Enabled

1. Capture query ID.
2. Capture historical fast query ID.
3. Confirm warehouse.
4. Confirm warehouse size.
5. Confirm QAS configuration.
6. Confirm scale factor.
7. Check query eligibility.
8. Review QAS estimate where appropriate.
9. Review Query Profile.
10. Check queueing.
11. Check bytes scanned.
12. Check partitions scanned.
13. Check pruning.
14. Check joins.
15. Check spill.
16. Check skew.
17. Check external dependencies.
18. Check recent SQL changes.
19. Check data growth.
20. Check workload concurrency.
21. Check QAS usage.
22. Compare QAS credits.
23. Determine root cause.
24. Apply controlled remediation.
25. Validate before/after.
26. Document cost impact.

---

# Part 55 — QAS Cost Incident Runbook

## 78. Unexpected QAS Credit Increase

1. Identify affected warehouse.
2. Determine when cost increased.
3. Compare QAS usage history.
4. Check scale-factor changes.
5. Check QAS enablement changes.
6. Identify high-cost query families.
7. Check query frequency.
8. Check recent deployments.
9. Check backfills.
10. Check scheduled jobs.
11. Check BI workload changes.
12. Compare latency benefit.
13. Determine whether QAS is still justified.
14. Reduce scope or configuration if necessary.
15. Disable QAS if appropriate.
16. Validate application SLA.
17. Document corrective action.

---

# Part 56 — Change Management

## 79. Production Change Record

Document:

```text
Warehouse:
Environment:

Current warehouse size:

QAS current state:
QAS target state:

Scale factor:

Candidate query IDs:

Current P50:
Current P95:
Current P99:

Expected improvement:

Current credits:
Expected QAS credits:

Validation period:

Rollback condition:

Owner:
```

---

# Part 57 — Rollback Criteria

## 80. Define Before Change

Examples:

```text
QAS cost exceeds approved threshold
No measurable SLA improvement
Unexpected workload behavior
Total compute cost materially increases
```

Do not invent rollback criteria after cost has already increased.

---

# Part 58 — FinOps Decision Framework

## 81. Example A

Before:

```text
Runtime = 20 min
Warehouse cost/query = 1.0 credit
```

After QAS:

```text
Runtime = 4 min
Warehouse cost/query = 0.4 credit
QAS cost/query       = 0.3 credit
Total                = 0.7 credit
```

Result:

```text
Faster
+
Lower total compute cost
```

Strong outcome.

## 82. Example B

Before:

```text
Runtime = 5 min
Cost    = 0.2 credit
```

After:

```text
Runtime    = 4 min
Total cost = 1.0 credit
```

Whether this is acceptable depends on business value.

---

# Part 59 — Candidate Selection Checklist

## 83. Query

```text
□ Long-running
□ Business-critical
□ Representative
□ Query ID captured
□ QAS eligibility checked
□ Query Profile reviewed
```

## 84. Bottleneck

```text
□ Queueing excluded
□ Poor SQL excluded
□ Poor pruning investigated
□ Join explosion investigated
□ Spill investigated
□ External latency excluded
```

## 85. Economics

```text
□ Frequency known
□ Warehouse credits known
□ QAS credits measured
□ SLA value known
□ Monthly cost estimated
```

---

# Part 60 — Hands-On Lab

## 86. Objective

Evaluate a large analytical workload before and after QAS.

Use a non-production environment.

QAS uses billable serverless compute. Confirm account feature availability and current pricing before running the lab.

## 87. Create Database

```sql
CREATE OR REPLACE DATABASE qas_lab;
```

## 88. Create Schema

```sql
CREATE OR REPLACE SCHEMA qas_lab.demo;
```

## 89. Create Synthetic Fact Table

```sql
CREATE OR REPLACE TABLE qas_lab.demo.sales (
    transaction_id NUMBER,
    customer_id NUMBER,
    product_id NUMBER,
    transaction_date DATE,
    region STRING,
    amount NUMBER(12,2)
);
```

## 90. Generate Data

```sql
INSERT INTO qas_lab.demo.sales
SELECT
    SEQ4(),
    MOD(SEQ4(), 1000000),
    MOD(SEQ4(), 100000),
    DATEADD(
        day,
        -MOD(SEQ4(), 730),
        CURRENT_DATE()
    ),
    CASE MOD(SEQ4(), 5)
        WHEN 0 THEN 'EAST'
        WHEN 1 THEN 'WEST'
        WHEN 2 THEN 'NORTH'
        WHEN 3 THEN 'SOUTH'
        ELSE 'CENTRAL'
    END,
    MOD(SEQ4(), 1000000) / 100.0
FROM TABLE(GENERATOR(ROWCOUNT => 50000000));
```

All data is synthetic.

Adjust row count downward if your lab environment should use less compute.

## 91. Disable Persisted Result Reuse

```sql
ALTER SESSION SET USE_CACHED_RESULT = FALSE;
```

## 92. Baseline Query

```sql
SELECT
    region,
    product_id,
    COUNT(*) AS transaction_count,
    SUM(amount) AS total_amount,
    AVG(amount) AS average_amount
FROM qas_lab.demo.sales
WHERE transaction_date >= DATEADD(day, -365, CURRENT_DATE())
GROUP BY
    region,
    product_id
ORDER BY
    total_amount DESC;
```

## 93. Capture Baseline

Record:

```text
Query ID:
Warehouse:
Warehouse size:

Runtime:
Bytes scanned:
Partitions scanned:
Queue time:
Spill:
```

## 94. Repeat Baseline

Run several executions under comparable conditions.

Do not base conclusions on one run.

## 95. Evaluate Candidate

Use the current Snowflake-supported QAS estimation capability against the representative query ID.

For example, after validating current syntax:

```sql
SELECT SYSTEM$ESTIMATE_QUERY_ACCELERATION('<query_id>');
```

Record the returned recommendation/estimate.

## 96. Enable QAS

On the lab warehouse, use the current supported Snowflake DDL to enable Query Acceleration.

Conceptually:

```sql
ALTER WAREHOUSE qas_lab_wh
SET ENABLE_QUERY_ACCELERATION = TRUE;
```

Do not run against a shared production warehouse for a lab.

## 97. Configure Conservative Scale Factor

After validating current syntax:

```sql
ALTER WAREHOUSE qas_lab_wh
SET QUERY_ACCELERATION_MAX_SCALE_FACTOR = 2;
```

The value is an example for controlled testing, not a universal production recommendation.

## 98. Re-Run Query

Execute the same analytical query.

Capture the new query ID.

## 99. Repeat

Run several controlled executions.

## 100. Compare

| Metric | QAS Off | QAS On |
|---|---:|---:|
| Runtime | | |
| Bytes scanned | | |
| Partitions scanned | | |
| Queue time | | |
| Warehouse credits | | |
| QAS credits | | |
| Total credits | | |

## 101. Evaluate SLA

Example:

```text
Target runtime = < 120 seconds
```

Record whether QAS achieved the target.

## 102. Evaluate Cost

Calculate cost per query, daily projected cost, and monthly projected cost.

## 103. Disable QAS

After testing, restore the warehouse according to your lab baseline.

Conceptually:

```sql
ALTER WAREHOUSE qas_lab_wh
SET ENABLE_QUERY_ACCELERATION = FALSE;
```

## 104. Restore Cached Results

```sql
ALTER SESSION SET USE_CACHED_RESULT = TRUE;
```

## 105. Cleanup

```sql
DROP DATABASE IF EXISTS qas_lab;
```

---

# Part 61 — Lab Results Template

## 106. Results

| Test | Runtime | Warehouse Credits | QAS Credits | Total |
|---|---:|---:|---:|---:|
| QAS off #1 | | | 0 | |
| QAS off #2 | | | 0 | |
| QAS off #3 | | | 0 | |
| QAS on #1 | | | | |
| QAS on #2 | | | | |
| QAS on #3 | | | | |

---

# Part 62 — Production Monitoring

## 107. Daily

Monitor QAS credits, warehouse credits, long-running accelerated queries, and unexpected usage spikes.

## 108. Weekly

Review top QAS-consuming warehouses, top candidate workloads, latency improvement, and total compute economics.

## 109. Monthly

Review whether QAS is still justified.

Applications and workloads change.

---

# Part 63 — Operational Dashboard

## 110. Recommended Metrics

A QAS dashboard should include:

```text
Warehouse
QAS enabled
Scale factor

Warehouse credits
QAS credits
Total credits

Accelerated workload volume

P50 runtime
P95 runtime
P99 runtime

SLA violations
```

---

# Part 64 — Production Example

## 111. Scenario

A financial analytics query:

```text
Frequency = 200/day
P95       = 12 minutes
SLA       = 5 minutes
```

Query Profile shows a large analytical workload, and Snowflake's acceleration estimate identifies it as a candidate.

## 112. Controlled Test

With QAS:

```text
P95 = 4 minutes
```

Additional QAS cost:

```text
0.25 credits/query
```

## 113. Decision

Calculate:

```text
200 queries/day
×
0.25 credits
=
50 QAS credits/day
```

Then evaluate the business value of meeting the SLA against the added cost.

This is a production engineering decision, not merely a performance decision.

---

# Part 65 — Anti-Patterns

## 114. Enable QAS Everywhere

Avoid enabling QAS on every warehouse without candidate analysis.

## 115. Maximum Scale Factor Immediately

Avoid beginning with the highest available acceleration allowance without evidence.

## 116. Ignore Query Profile

Do not enable QAS before understanding the actual bottleneck.

## 117. Ignore Cost

Do not celebrate a 10x performance improvement without checking how many additional credits were consumed.

## 118. Use QAS to Hide Bad SQL

Fix Cartesian joins, `SELECT *`, poor filters, and unnecessary transformations before adding compute.

---

# Part 66 — Production Review Questions

Before approving QAS, ask:

```text
What exact query family are we accelerating?

How often does it run?

What is its business SLA?

What is its current P95/P99?

What does Query Profile show?

Is it actually QAS eligible?

What does the acceleration estimate show?

Why is warehouse resizing not preferred?

Why is clustering not preferred?

Why is Search Optimization not preferred?

Why is precomputation not preferred?

What scale factor will we use?

How will we measure QAS credits?

What is the rollback threshold?
```

If these questions cannot be answered, the production change is not ready.

---

# Acceptance Criteria

The chapter is complete when you can:

- explain Query Acceleration Service
- explain supplemental serverless compute
- understand that QAS does not replace a warehouse
- understand that QAS is workload-specific
- identify potential QAS candidate workloads
- explain query eligibility
- use query IDs for QAS analysis
- understand Query Acceleration estimation
- recognize `SYSTEM$ESTIMATE_QUERY_ACCELERATION`
- evaluate multiple representative queries
- explain QAS scale factor
- treat scale factor as a cost control
- understand warehouse-level QAS configuration
- understand QAS rollback
- distinguish QAS from warehouse resizing
- distinguish QAS from multi-cluster warehouses
- distinguish scale-up, scale-out, and acceleration
- distinguish QAS from Search Optimization
- distinguish QAS from clustering
- distinguish QAS from caching
- distinguish QAS from materialized views
- distinguish QAS from dynamic tables
- optimize SQL before adding compute
- use Query Profile before enabling QAS
- use Query History for candidate identification
- build a production candidate matrix
- understand QAS credit consumption
- calculate total compute cost
- calculate cost per query
- monitor serverless QAS consumption
- attribute cost by warehouse
- implement QAS cost guardrails
- execute a controlled rollout
- benchmark QAS correctly
- control persisted-result reuse
- account for warehouse cache
- compare multiple executions
- distinguish queueing from execution time
- investigate spill before assuming QAS
- investigate join explosion
- investigate poor pruning
- reduce unnecessary projection
- evaluate ETL workloads
- evaluate BI workloads
- evaluate ad hoc analytics
- define measurable SLA targets
- capture before/after evidence
- troubleshoot missing improvement
- troubleshoot QAS cost growth
- understand why only some queries benefit
- confirm correct warehouse mapping
- investigate application changes
- execute a slow-query QAS runbook
- execute a QAS cost-incident runbook
- document production changes
- define rollback criteria
- evaluate performance and FinOps together
- perform the QAS hands-on lab
- monitor QAS daily, weekly, and monthly
- build an operational QAS dashboard
- avoid common QAS anti-patterns
- conduct a production readiness review

---

## Key Takeaways

Query Acceleration Service adds **Snowflake-managed serverless compute** to help process eligible portions of eligible queries.

The architecture is:

```text
Query
  |
  v
Virtual Warehouse
  |
  +---- Normal processing
  |
  +---- Eligible work
            |
            v
       Query Acceleration
            |
            v
       Serverless compute
```

Do not confuse QAS with:

```text
Bigger warehouse       -> Scale up
Multi-cluster          -> Scale out / concurrency
Search Optimization    -> Selective access
Clustering             -> Better pruning
Caching                -> Reuse
Materialized views     -> Precomputation
QAS                    -> Supplemental compute
```

Before enabling QAS:

```text
Capture query IDs
       |
       v
Analyze Query Profile
       |
       v
Confirm root bottleneck
       |
       v
Evaluate QAS eligibility
       |
       v
Estimate acceleration
       |
       v
Controlled test
       |
       v
Measure latency
       +
Measure credits
```

The key production equation is:

```text
Performance benefit
        +
Business/SLA value
        -
Additional QAS cost
        =
Production value
```

QAS is successful when it improves the **right workloads** at an acceptable total cost.

It should not be used to hide poor SQL, bad joins, weak pruning, unnecessary scanning, or concurrency problems.

The next chapter is **Chapter 43 — Warehouse Sizing & Scaling**.
