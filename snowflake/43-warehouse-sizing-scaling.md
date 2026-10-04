# 43 — Warehouse Sizing & Scaling

## Overview

Virtual warehouses provide the compute layer for Snowflake workloads.

Choosing the correct warehouse configuration directly affects:

- query performance
- concurrency
- queueing
- workload isolation
- credit consumption
- cache behavior
- operational stability
- user experience

A common mistake is treating warehouse sizing as:

```text
Query slow
   |
   v
Increase warehouse size
```

That is incomplete.

Before resizing a warehouse, determine **why** the workload is slow.

The problem may be:

```text
Single-query compute pressure
Concurrency
Queueing
Poor SQL
Poor pruning
Join explosion
Spill
Data skew
Cold warehouse/cache
External dependency
Workload mixing
```

Each problem requires a different response.

A better decision process is:

```text
Performance problem
       |
       v
Identify bottleneck
       |
       +---- Single-query compute pressure
       |          |
       |          v
       |      Scale up
       |
       +---- Concurrency / queueing
       |          |
       |          v
       |      Scale out
       |
       +---- Inefficient query
       |          |
       |          v
       |      Optimize query/data
       |
       +---- Eligible burst workload
                  |
                  v
                QAS
```

This chapter covers:

- virtual warehouse architecture
- warehouse sizes
- scaling up
- scaling down
- multi-cluster scaling
- concurrency
- queueing
- auto-suspend
- auto-resume
- warehouse cache
- workload isolation
- sizing methodology
- performance testing
- credit economics
- warehouse utilization
- spill
- Query Profile
- Query History
- production sizing
- troubleshooting
- capacity planning
- change management
- hands-on validation

---

# Part 1 — Virtual Warehouse Fundamentals

## 1. Compute Layer

A Snowflake virtual warehouse provides compute resources for query execution and many data-processing operations.

Conceptually:

```text
Snowflake
   |
   +---- Storage
   |
   +---- Cloud Services
   |
   +---- Virtual Warehouse
             |
             v
          Compute
```

Storage and compute are separated.

This allows compute resources to be independently sized and managed.

---

# Part 2 — Warehouse Isolation

## 2. Independent Compute

Different warehouses can process different workloads independently.

Example:

```text
                    Snowflake Storage
                          |
          +---------------+---------------+
          |               |               |
          v               v               v
       ETL_WH           BI_WH          ADHOC_WH
          |               |               |
          v               v               v
       Pipelines       Dashboards      Analysts
```

This is one of Snowflake's most important workload-management capabilities.

---

# Part 3 — Warehouse Sizes

## 3. Size Classes

Snowflake supports multiple virtual warehouse sizes.

Common sizes include:

```text
X-Small
Small
Medium
Large
X-Large
2X-Large
3X-Large
4X-Large
...
```

Availability of larger sizes can depend on current Snowflake capabilities, region, cloud, account, and release behavior.

Always validate current supported warehouse sizes before production design.

---

# Part 4 — Scaling Pattern

## 4. Relative Compute

Conceptually:

```text
X-Small
   |
   v
Small
   |
   v
Medium
   |
   v
Large
   |
   v
X-Large
```

Each step provides greater compute capacity and correspondingly higher credit consumption while running.

---

# Part 5 — Credit Scaling

## 5. Cost Relationship

Warehouse credit consumption generally increases as warehouse size increases.

```text
More compute
     |
     v
Higher credit rate
```

Therefore:

> Bigger is not automatically better.

The objective is not to minimize warehouse size.

The objective is to achieve the required SLA at an acceptable total cost.

---

# Part 6 — Scale Up

## 6. What Scale Up Means

Scaling up means increasing warehouse size.

Example:

```text
MEDIUM
   |
   v
LARGE
```

This provides additional compute resources to the warehouse.

---

# Part 7 — When Scaling Up Can Help

## 7. Compute-Intensive Queries

Scaling up can help workloads dominated by substantial query processing.

Examples may include:

```text
Large scans
Large joins
Large aggregations
Sorting
Window functions
Memory-intensive operations
```

But Query Profile should confirm the bottleneck.

---

# Part 8 — Scaling Up Does Not Fix Everything

## 8. Poor SQL

Suppose a join accidentally produces billions of unnecessary rows.

Increasing warehouse size may process the mistake faster.

It does not fix the mistake.

## 9. Poor Pruning

Suppose a query scans:

```text
95,000 / 100,000 partitions
```

when it should need only a small date range.

Investigate pruning before increasing compute.

## 10. Queueing

If a query spends most of its time queued, a larger warehouse may not be the best concurrency solution.

---

# Part 9 — Scale Down

## 11. Oversized Warehouses

A warehouse may be larger than required.

Example:

```text
XLARGE warehouse

Typical query runtime:
2 seconds

Workload:
light
```

A smaller warehouse may satisfy the same SLA at lower cost.

## 12. Controlled Downsizing

Test:

```text
XLARGE
  |
  v
LARGE
  |
  v
MEDIUM
```

while monitoring:

```text
P50
P95
P99
Queueing
Spill
Credits
SLA violations
```

---

# Part 10 — Scale Up vs Scale Out

## 13. Critical Difference

```text
Scale Up
   =
Larger warehouse

Scale Out
   =
Additional warehouse clusters
```

They solve different problems.

---

# Part 11 — Single-Query Performance

## 14. Scale-Up Candidate

Suppose:

```text
Concurrent queries = 2

Query runtime = 15 minutes

Queue time = 0
```

Query Profile shows substantial compute work.

This can be a scale-up investigation candidate.

---

# Part 12 — Concurrency

## 15. Scale-Out Candidate

Suppose:

```text
Concurrent queries = 100

Individual query execution = 5 sec

Queue time = 40 sec
```

The queries themselves are reasonably fast.

The problem is workload concurrency.

This is a scale-out investigation candidate.

---

# Part 13 — Queueing

## 16. Query Queue

When warehouse capacity cannot immediately execute additional workload, queries can queue.

Conceptually:

```text
Queries
  |
  v
Warehouse capacity full
  |
  v
Queue
  |
  v
Execution
```

---

# Part 14 — Queue Time vs Execution Time

## 17. Example

```text
Total elapsed       = 60 sec
Queue time          = 50 sec
Execution time      = 10 sec
```

The dominant problem is not query execution.

It is queueing.

## 18. Wrong Response

Do not immediately rewrite a 10-second query to solve a 50-second queue.

Address concurrency and workload capacity.

---

# Part 15 — Multi-Cluster Warehouses

## 19. Scaling Concurrency

Multi-cluster warehouses can add warehouse clusters to handle concurrent workloads.

Conceptually:

```text
                BI Workload
                    |
                    v
              Multi-Cluster WH
              /      |      \
             /       |       \
            v        v        v
        Cluster 1 Cluster 2 Cluster 3
```

This allows additional queries to execute concurrently.

---

# Part 16 — Multi-Cluster Is Not Single-Query Parallelism

## 20. Important Distinction

Adding more clusters does not generally mean one individual query automatically uses all clusters.

Multi-cluster warehouses primarily address concurrency.

Therefore:

```text
One slow query
     !=
Automatically add clusters
```

---

# Part 17 — Scaling Policies

## 21. Multi-Cluster Behavior

Snowflake supports scaling behavior for multi-cluster warehouses.

The exact configuration options and scaling-policy semantics should be validated against current Snowflake documentation.

Production design should consider:

```text
Minimum clusters
Maximum clusters
Scaling policy
Concurrency pattern
Cost ceiling
```

---

# Part 18 — Min and Max Clusters

## 22. Concept

A warehouse may conceptually be configured with:

```text
Minimum clusters = 1
Maximum clusters = 5
```

Snowflake can scale cluster count within the configured range according to workload and policy.

---

# Part 19 — Cost Implication

## 23. Multiple Running Clusters

Each active cluster consumes compute credits.

Therefore:

```text
More clusters
      |
      v
More concurrency capacity
      +
Potentially more cost
```

Scale-out decisions require both performance and FinOps review.

---

# Part 20 — Warehouse Sizing vs Multi-Cluster

## 24. Decision Matrix

| Problem | Likely Direction |
|---|---|
| One heavy query | Scale up / optimize |
| Many queries queue | Scale out |
| Poor pruning | Fix pruning |
| Selective point lookup | Search Optimization |
| Eligible heavy analytical work | Evaluate QAS |
| Bad join | Fix SQL |
| Repeated expensive transformation | Consider precomputation |

Do not treat this table as an absolute rule.

Use evidence.

---

# Part 21 — Workload Isolation

## 25. Shared Warehouse Problem

Suppose:

```text
ETL
BI
Ad hoc
Data science
Maintenance
```

all use:

```text
SHARED_WH
```

A large ETL job can affect dashboard users.

An analyst can affect production pipelines.

## 26. Better Architecture

Use workload-specific warehouses.

Example:

```text
ETL_WH
BI_WH
ADHOC_WH
DATA_SCIENCE_WH
ADMIN_WH
```

All can access the same Snowflake data while using independent compute.

---

# Part 22 — Why Isolation Matters

## 27. Benefits

Workload isolation improves:

```text
Performance predictability
Cost attribution
Capacity planning
Troubleshooting
SLA management
Security/governance
Change management
```

---

# Part 23 — ETL Warehouse

## 28. ETL Characteristics

ETL workloads may involve:

```text
COPY
MERGE
INSERT
Large transformations
Scheduled batch processing
```

Sizing should consider batch completion SLA and pipeline concurrency.

---

# Part 24 — BI Warehouse

## 29. BI Characteristics

BI workloads often involve:

```text
Many concurrent queries
Dashboard refreshes
Interactive latency requirements
Morning/peak usage periods
```

Concurrency may matter more than one-query throughput.

---

# Part 25 — Ad Hoc Warehouse

## 30. Analyst Workloads

Ad hoc queries can be unpredictable.

A dedicated warehouse prevents exploratory queries from affecting production BI or ETL.

---

# Part 26 — Auto-Suspend

## 31. Idle Warehouses

Snowflake warehouses consume compute credits while running.

Auto-suspend allows warehouses to suspend after a configured period of inactivity.

```text
No workload
    |
    v
Idle timer
    |
    v
Warehouse suspended
```

---

# Part 27 — Auto-Resume

## 32. New Query

Auto-resume allows a suspended warehouse to resume when new work arrives.

```text
Warehouse suspended
       |
       v
New query
       |
       v
Warehouse resumes
       |
       v
Query executes
```

---

# Part 28 — Auto-Suspend Trade-Off

## 33. Aggressive Suspension

Short auto-suspend periods can reduce idle compute cost.

But they can also increase:

```text
Warehouse restarts
Cold-cache behavior
Startup latency exposure
```

## 34. Long Suspension

Long idle periods can preserve a warm warehouse but may consume credits while little or no useful work occurs.

---

# Part 29 — Choosing Auto-Suspend

## 35. Workload-Based Decision

For intermittent ETL:

```text
Run job
   |
   v
Finish
   |
   v
Suspend
```

A short auto-suspend may be appropriate.

For continuously active BI, frequent suspension may provide little benefit and can hurt cache reuse.

---

# Part 30 — Warehouse Cache

## 36. Local Cache

Running warehouse compute can maintain local cached data.

As covered in Chapter 40:

```text
Warehouse running
      |
      v
Local cache available

Warehouse suspended
      |
      v
Local cache lost
```

---

# Part 31 — Auto-Suspend and Cache Economics

## 37. Important Trade-Off

Suppose a warehouse receives queries every few minutes.

An extremely short auto-suspend setting could repeatedly:

```text
Suspend
Resume
Re-read data
Rebuild cache
```

The lowest idle-compute setting is not always the lowest total-cost configuration.

---

# Part 32 — Auto-Resume Configuration

## 38. Production Principle

Interactive warehouses typically require auto-resume so applications do not depend on manual warehouse startup.

Validate current Snowflake DDL and parameter behavior before applying production settings.

---

# Part 33 — Warehouse DDL

## 39. Conceptual Creation

Example:

```sql
CREATE WAREHOUSE analytics_wh
WITH
    WAREHOUSE_SIZE = 'MEDIUM'
    AUTO_SUSPEND = 300
    AUTO_RESUME = TRUE;
```

Validate exact current syntax and defaults before production use.

---

# Part 34 — Resize Warehouse

## 40. Concept

Example:

```sql
ALTER WAREHOUSE analytics_wh
SET WAREHOUSE_SIZE = 'LARGE';
```

Resizing a running warehouse changes the available compute resources according to Snowflake's current warehouse-resize behavior.

---

# Part 35 — Production Resize Safety

## 41. Before Resizing

Capture:

```text
Current size
Query workload
Concurrency
Queueing
P50
P95
P99
Credits/hour
Spill
SLA
```

Do not resize without a baseline.

---

# Part 36 — Benchmarking

## 42. Controlled Test

Compare:

```text
SMALL
MEDIUM
LARGE
```

using the same representative workload.

## 43. Metrics

Measure:

```text
Query runtime
Throughput
Queue time
Spill
Credits
Cost/query
SLA
```

---

# Part 37 — Bigger Warehouse and Runtime

## 44. Runtime Does Not Always Scale Linearly

Do not assume:

```text
2x warehouse cost
      =
2x query speed
```

Some workloads scale well.

Others do not.

---

# Part 38 — Cost per Query

## 45. Example

Suppose:

```text
MEDIUM
Runtime = 8 min
Cost/query = 0.27 credits
```

and:

```text
LARGE
Runtime = 4 min
Cost/query = 0.27 credits
```

The larger warehouse may provide better latency at similar query cost.

Actual results depend on workload.

Measure rather than assume.

---

# Part 39 — Another Cost Example

## 46. Poor Scaling

Suppose:

```text
MEDIUM
Runtime = 8 min
Cost = 0.27 credits

LARGE
Runtime = 7 min
Cost = 0.47 credits
```

The larger warehouse may provide weak economic value.

---

# Part 40 — Query Profile and Warehouse Size

## 47. Evidence

Use Query Profile to understand whether a larger warehouse could help.

Look for:

```text
Large processing operators
Spill
Heavy aggregation
Sort
Join
Data redistribution
```

---

# Part 41 — Spill

## 48. Memory Pressure

Query execution can spill intermediate data when available memory is insufficient.

Conceptually:

```text
Operator
   |
   v
Memory pressure
   |
   +---- Local spill
   |
   +---- Remote spill
```

Remote spill can be particularly expensive.

---

# Part 42 — Scaling for Spill

## 49. Larger Warehouse

A larger warehouse can provide more resources and may reduce spill for appropriate workloads.

But first check whether spill is caused by:

```text
Bad join
Row explosion
Skew
Unnecessary sort
Poor query design
```

Do not solve a logical problem with compute.

---

# Part 43 — Warehouse Utilization

## 50. Underutilization

Signs can include:

```text
Low workload
Little queueing
Short queries
High idle time
Large warehouse
```

This can indicate downsizing or auto-suspend opportunity.

---

# Part 44 — Overutilization

## 51. Signs

Potential indicators include:

```text
Persistent queueing
SLA degradation
High concurrency
Long batch completion
Repeated spill
```

But determine whether the cause is warehouse capacity or inefficient queries.

---

# Part 45 — Query History Analysis

## 52. Group by Warehouse

Analyze query count, average runtime, P95 runtime, queue time, bytes scanned, and workload pattern by warehouse.

---

# Part 46 — Time-of-Day Analysis

## 53. Peak Periods

A warehouse may perform well most of the day but queue during:

```text
08:00–10:00
```

because dashboards, pipelines, and users overlap.

Do not size only from daily averages.

---

# Part 47 — Percentiles

## 54. Average Is Not Enough

Track:

```text
P50
P95
P99
```

Averages can hide severe tail latency.

---

# Part 48 — Throughput

## 55. Batch Workloads

For ETL, the important metric may be:

```text
Rows/hour
Files/hour
Jobs/hour
Pipeline completion time
```

rather than individual query latency.

---

# Part 49 — BI Workloads

## 56. User Experience

For BI:

```text
Dashboard P95
Queue time
Concurrent users
SLA violations
```

may matter more.

---

# Part 50 — Warehouse Cost Attribution

## 57. Separate Workloads

Dedicated warehouses allow clearer attribution:

```text
ETL_WH     -> ingestion cost
BI_WH      -> dashboard cost
ADHOC_WH   -> analyst cost
```

This improves FinOps.

---

# Part 51 — Warehouse Naming

## 58. Production Convention

Example:

```text
PROD_ETL_WH
PROD_BI_WH
PROD_ADHOC_WH
STAGE_ETL_WH
DEV_ANALYTICS_WH
```

Use a consistent organizational naming standard.

---

# Part 52 — Warehouse Ownership

## 59. Every Warehouse Needs an Owner

Track:

```text
Technical owner
Business owner
Purpose
Environment
SLA
Cost center
Sizing policy
```

Avoid orphaned warehouses.

---

# Part 53 — Resource Monitors

## 60. Cost Guardrails

Warehouse credit usage can be controlled and monitored with Snowflake cost-governance capabilities such as resource monitors where appropriate.

Chapter 54 covers Resource Monitors & Cost Controls in detail.

---

# Part 54 — Sizing Methodology

## 61. Step 1 — Classify Workload

Identify:

```text
ETL
BI
Ad hoc
Data science
Administration
Application
```

## 62. Step 2 — Define SLA

Example:

```text
Dashboard P95 < 5 sec
ETL completes < 60 min
Application lookup P95 < 1 sec
```

## 63. Step 3 — Capture Baseline

Measure:

```text
Warehouse size
Query count
Concurrency
Queueing
Runtime
Spill
Credits
```

## 64. Step 4 — Identify Bottleneck

Determine:

```text
Compute?
Concurrency?
Query design?
Pruning?
Memory?
External dependency?
```

## 65. Step 5 — Test Alternatives

Possible actions:

```text
Optimize SQL
Improve pruning
Scale up
Scale out
Workload isolation
Search Optimization
QAS
Precomputation
```

## 66. Step 6 — Compare Economics

Measure:

```text
Performance
Credits
Cost/query
Cost/job
Cost/day
SLA
```

## 67. Step 7 — Productionize

Document:

```text
Chosen size
Cluster configuration
Auto-suspend
Auto-resume
QAS settings
Owner
SLA
Cost expectation
Rollback
```

---

# Part 55 — Sizing Matrix

## 68. Example

| Workload | Current Problem | Likely Investigation |
|---|---|---|
| ETL | Single batch too slow | Scale up / optimize |
| BI | Queueing at peak | Scale out |
| Lookup | Huge scan for 1 row | Search Optimization |
| Analytics | Eligible heavy query | QAS |
| Dashboard | Repeated aggregation | Precompute |
| Shared workload | Cross-impact | Isolate warehouses |

---

# Part 56 — Production Resize Runbook

## 69. Before Change

Capture:

```text
Warehouse:
Current size:
Target size:

Current cluster count:
Current auto-suspend:

P50:
P95:
P99:

Queue time:
Spill:

Credits/day:

Reason:
Expected improvement:
Rollback condition:
```

## 70. Execute Change

Use approved Snowflake DDL.

Avoid making multiple unrelated performance changes simultaneously.

## 71. Validate

Compare:

```text
Runtime
Queueing
Spill
Throughput
Credits
SLA
```

## 72. Roll Back

If the expected benefit does not materialize or cost exceeds approved limits, restore the previous configuration.

---

# Part 57 — Scale-Out Runbook

## 73. Before Multi-Cluster Change

Confirm:

```text
Queueing is real
Concurrency is high
Queries themselves are reasonably efficient
Single-query performance is acceptable
```

Then establish:

```text
Minimum clusters
Maximum clusters
Scaling policy
Cost ceiling
```

---

# Part 58 — Troubleshooting: Warehouse Slow

## 74. Investigation

Check:

```text
Warehouse state
Warehouse size
Query queue
Concurrency
Query Profile
Spill
Pruning
Join behavior
Cache state
QAS
Recent configuration changes
```

---

# Part 59 — Troubleshooting: Queueing

## 75. Questions

```text
How many concurrent queries?
Which workload?
When did queueing begin?
Is this peak-period only?
Did workload increase?
Did warehouse size change?
Are multiple workloads sharing the warehouse?
```

---

# Part 60 — Troubleshooting: Cost Spike

## 76. Investigate

Check:

```text
Warehouse resized?
More clusters active?
Auto-suspend changed?
Warehouse left running?
Query volume increased?
New workload?
Backfill?
QAS enabled?
```

---

# Part 61 — Troubleshooting: Resize Did Not Help

## 77. Scenario

Warehouse changed:

```text
MEDIUM -> XLARGE
```

but query remains slow.

Investigate:

```text
Poor pruning
Join explosion
External latency
Serialization
Data skew
SQL logic
Unsupported scaling characteristics
```

Do not continue increasing size blindly.

---

# Part 62 — Troubleshooting: Cold Warehouse

## 78. Scenario

First dashboard query after idle period is slower.

Potential contributors include:

```text
Warehouse resume
Cold warehouse cache
Data access
```

Compare warm and cold behavior.

---

# Part 63 — Troubleshooting: ETL Affecting BI

## 79. Scenario

```text
ETL job starts
      |
      v
Dashboard latency rises
```

If both use the same warehouse, investigate workload contention.

A strong solution may be workload isolation rather than simply increasing warehouse size.

---

# Part 64 — Capacity Planning

## 80. Growth Dimensions

Plan for:

```text
Data growth
Query growth
User growth
Concurrency growth
Pipeline growth
Peak-period growth
```

## 81. Trend, Not Snapshot

Do not size a warehouse based on one day's metrics.

Track trends.

Example:

```text
Month 1 P95 concurrency = 20
Month 2 P95 concurrency = 30
Month 3 P95 concurrency = 45
```

This signals capacity pressure.

---

# Part 65 — Headroom

## 82. Production Capacity

Running constantly at the edge of capacity leaves little room for:

```text
Traffic spikes
Backfills
Incident recovery
Late jobs
Unexpected dashboards
```

Maintain appropriate operational headroom without excessive permanent overprovisioning.

---

# Part 66 — Scheduled Workload Management

## 83. Avoid Peak Collisions

Suppose:

```text
08:00 BI dashboards
08:00 ETL batch
08:00 data science refresh
```

Even isolated workloads can create cost and downstream pressure.

Scheduling can be part of capacity management.

---

# Part 67 — Performance vs Cost

## 84. Three Outcomes

### Outcome A

```text
Faster
Cheaper
```

Ideal.

### Outcome B

```text
Faster
Same cost
```

Often attractive.

### Outcome C

```text
Faster
More expensive
```

Requires business justification.

---

# Part 68 — Cost Efficiency

## 85. Useful Metrics

Track:

```text
Credits/query
Credits/job
Credits/dashboard refresh
Credits/TB processed
Credits/day
```

Choose metrics appropriate to the workload.

---

# Part 69 — Production Warehouse Review

## 86. Monthly Review

For each warehouse:

```text
Purpose
Owner
Size
Cluster configuration
Auto-suspend
Auto-resume
QAS
Query volume
Queueing
P95
Credits
SLA
```

---

# Part 70 — Unused Warehouses

## 87. Governance

Identify warehouses with:

```text
No recent queries
Very low utilization
No clear owner
```

Review whether they should still exist.

Do not leave unnecessary compute configurations unmanaged.

---

# Part 71 — Change Management

## 88. Warehouse Changes Are Production Changes

Track changes to:

```text
Size
Auto-suspend
Auto-resume
Cluster count
Scaling policy
QAS
Resource monitor
```

These can affect both performance and cost.

---

# Part 72 — Incident Runbook

## 89. Warehouse Performance Incident

1. Identify affected warehouse.
2. Identify affected workload.
3. Determine incident start time.
4. Capture representative slow query IDs.
5. Capture historical fast query IDs.
6. Check warehouse state.
7. Check warehouse size.
8. Check recent resize history.
9. Check concurrency.
10. Check queueing.
11. Check cluster count.
12. Check auto-suspend/resume behavior.
13. Review Query Profile.
14. Check spill.
15. Check pruning.
16. Check joins.
17. Check workload isolation.
18. Check QAS configuration.
19. Check query volume change.
20. Check data growth.
21. Check recent deployments.
22. Determine root cause.
23. Apply targeted remediation.
24. Validate performance.
25. Validate cost.
26. Document findings.

---

# Part 73 — Evidence Template

## 90. Warehouse Investigation

```text
Warehouse:
Environment:

Purpose:
Owner:

Warehouse size:
Cluster configuration:

Auto-suspend:
Auto-resume:

QAS:

Incident start:

Query IDs:

Concurrency:
Queue time:

P50:
P95:
P99:

Spill:

Credits/hour:
Credits/day:

Recent changes:

Observed bottleneck:

Root cause:

Action:

Performance result:

Cost result:
```

---

# Part 74 — Hands-On Lab

## 91. Objective

Compare warehouse sizes using the same analytical workload.

Use a non-production environment.

## 92. Create Database

```sql
CREATE OR REPLACE DATABASE warehouse_sizing_lab;
```

## 93. Create Schema

```sql
CREATE OR REPLACE SCHEMA warehouse_sizing_lab.demo;
```

## 94. Create Table

```sql
CREATE OR REPLACE TABLE warehouse_sizing_lab.demo.sales (
    transaction_id NUMBER,
    customer_id NUMBER,
    product_id NUMBER,
    transaction_date DATE,
    region STRING,
    amount NUMBER(12,2)
);
```

## 95. Generate Synthetic Data

```sql
INSERT INTO warehouse_sizing_lab.demo.sales
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

Reduce the row count if appropriate for your lab budget.

## 96. Disable Persisted Results

```sql
ALTER SESSION SET USE_CACHED_RESULT = FALSE;
```

## 97. Test Query

```sql
SELECT
    region,
    product_id,
    COUNT(*) AS transaction_count,
    SUM(amount) AS total_amount,
    AVG(amount) AS average_amount
FROM warehouse_sizing_lab.demo.sales
WHERE transaction_date >= DATEADD(day, -365, CURRENT_DATE())
GROUP BY
    region,
    product_id
ORDER BY
    total_amount DESC;
```

## 98. Test Size A

Run the workload on the approved smaller lab warehouse size.

Capture:

```text
Warehouse size:
Query ID:
Runtime:
Queue time:
Bytes scanned:
Partitions scanned:
Spill:
```

Run multiple times.

## 99. Test Size B

Resize the lab warehouse one size larger using current Snowflake-supported DDL.

Run the same workload.

Capture the same metrics.

## 100. Test Size C

If budget permits, repeat with another size.

Do not increase warehouse size unnecessarily just to complete the lab.

## 101. Compare

| Metric | Size A | Size B | Size C |
|---|---:|---:|---:|
| Runtime | | | |
| Queue time | | | |
| Local spill | | | |
| Remote spill | | | |
| Credits | | | |
| Cost/query | | | |

## 102. Calculate Improvement

For each size, calculate:

```text
Runtime improvement
Credit change
Cost/query
SLA result
```

## 103. Concurrency Test

If your lab environment permits safe parallel testing, run multiple representative queries concurrently.

Observe:

```text
Queue time
Throughput
Latency
```

Do not generate uncontrolled concurrency.

## 104. Auto-Suspend Test

Configure an appropriate lab auto-suspend interval.

Observe:

```text
Idle behavior
Suspend
Resume
First query after resume
Subsequent warm query
```

## 105. Restore Session

```sql
ALTER SESSION SET USE_CACHED_RESULT = TRUE;
```

## 106. Cleanup

```sql
DROP DATABASE IF EXISTS warehouse_sizing_lab;
```

Restore the lab warehouse to its approved baseline configuration.

---

# Part 75 — Lab Results

## 107. Results Template

| Warehouse | Runtime | Spill | Queue | Credits | Cost/Query |
|---|---:|---:|---:|---:|---:|
| Size A | | | | | |
| Size B | | | | | |
| Size C | | | | | |

---

# Part 76 — Production Sizing Checklist

## 108. Performance

```text
□ P50
□ P95
□ P99
□ Queue time
□ Spill
□ Throughput
□ SLA
```

## 109. Workload

```text
□ Query volume
□ Concurrency
□ Peak periods
□ Batch windows
□ Workload type
□ Growth trend
```

## 110. Cost

```text
□ Credits/hour
□ Credits/day
□ Cost/query
□ Cost/job
□ Idle compute
□ Multi-cluster cost
□ QAS cost
```

## 111. Configuration

```text
□ Warehouse size
□ Auto-suspend
□ Auto-resume
□ Min clusters
□ Max clusters
□ Scaling policy
□ QAS
□ Resource monitor
```

---

# Part 77 — Decision Tree

## 112. Warehouse Performance Decision

```text
Slow workload
     |
     v
Queueing high?
   /     \
 Yes      No
 |         |
 v         v
Concurrency   Query execution slow?
problem           /       \
 |              Yes        No
 v               |          |
Scale out /      v          v
isolate       Profile      Check external/
              query        application factors
                |
                v
        Poor pruning?
          /      \
        Yes       No
        |          |
        v          v
      Fix       Compute/memory
    pruning      pressure?
                  /   \
                Yes    No
                |       |
                v       v
            Scale up   Other
            / QAS      root cause
```

---

# Part 78 — Operational Principles

## 113. Principle 1

Do not resize before identifying the bottleneck.

## 114. Principle 2

Scale up for appropriate single-query resource pressure.

## 115. Principle 3

Scale out for appropriate concurrency pressure.

## 116. Principle 4

Do not use compute to hide bad SQL.

## 117. Principle 5

Separate workloads when they have different SLAs or operational behavior.

## 118. Principle 6

Treat auto-suspend as both a cost and cache decision.

## 119. Principle 7

Measure percentiles, not just averages.

## 120. Principle 8

Evaluate performance and credits together.

## 121. Principle 9

Maintain production headroom.

## 122. Principle 10

Review warehouse sizing continuously as workloads evolve.

---

# Acceptance Criteria

The chapter is complete when you can:

- explain the purpose of virtual warehouses
- explain compute/storage separation
- explain warehouse isolation
- understand warehouse size classes
- understand relative compute and credit scaling
- explain scale up
- explain scale down
- identify scale-up candidates
- identify oversized warehouses
- distinguish scale up from scale out
- distinguish single-query performance from concurrency
- recognize queueing
- separate queue time from execution time
- explain multi-cluster warehouses
- understand that multi-cluster primarily addresses concurrency
- understand min/max cluster concepts
- understand scaling-policy concepts
- evaluate multi-cluster cost
- use a sizing decision matrix
- design workload isolation
- size ETL warehouses
- size BI warehouses
- isolate ad hoc workloads
- explain auto-suspend
- explain auto-resume
- understand auto-suspend trade-offs
- understand warehouse cache implications
- configure warehouse settings conceptually
- resize warehouses safely
- capture a performance baseline
- benchmark multiple sizes
- understand non-linear query scaling
- calculate cost per query
- use Query Profile during sizing
- understand local and remote spill
- investigate spill before resizing
- recognize underutilization
- recognize overutilization
- analyze Query History by warehouse
- analyze time-of-day demand
- use P50/P95/P99
- measure throughput
- evaluate BI user experience
- attribute warehouse cost
- use consistent naming
- assign warehouse ownership
- understand the role of resource monitors
- execute a structured sizing methodology
- use a sizing matrix
- execute a resize runbook
- execute a scale-out runbook
- troubleshoot slow warehouses
- troubleshoot queueing
- troubleshoot cost spikes
- troubleshoot ineffective resizing
- troubleshoot cold-warehouse behavior
- diagnose ETL/BI contention
- perform capacity planning
- maintain appropriate headroom
- manage scheduled workload collisions
- evaluate performance versus cost
- track cost-efficiency metrics
- conduct monthly warehouse reviews
- identify unused warehouses
- manage warehouse changes
- execute a warehouse performance incident runbook
- capture investigation evidence
- perform the hands-on sizing lab
- compare warehouse sizes
- evaluate concurrency safely
- evaluate auto-suspend behavior
- use a production sizing checklist
- use the warehouse decision tree

---

## Key Takeaways

Warehouse sizing should begin with the bottleneck, not the warehouse-size dropdown.

Use this mental model:

```text
One expensive query
       |
       v
Optimize + evaluate scale up

Many queries queue
       |
       v
Evaluate scale out

Workloads interfere
       |
       v
Isolate warehouses

Highly selective lookup
       |
       v
Search Optimization

Eligible heavy analytical work
       |
       v
Query Acceleration Service

Poor pruning / bad SQL
       |
       v
Fix the underlying work
```

Remember:

```text
Scale Up
   =
More resources per warehouse cluster

Scale Out
   =
More clusters for concurrency
```

And always evaluate:

```text
Performance
    +
SLA
    +
Throughput
    -
Credits
    =
Operational value
```

A larger warehouse is successful only when the additional compute creates enough performance or business value to justify its cost.

A smaller warehouse is successful only when it continues to meet the required SLA.

The production goal is therefore not:

> Use the smallest warehouse.

Nor is it:

> Use the largest warehouse for maximum performance.

The goal is:

> Use the warehouse architecture and capacity that meets the workload's SLA with predictable performance and acceptable cost.

The next chapter is **Chapter 44 — Multi-Cluster Warehouses & Concurrency**.
