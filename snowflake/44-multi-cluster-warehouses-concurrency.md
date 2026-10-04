# 44 — Multi-Cluster Warehouses & Concurrency

## Overview

Snowflake virtual warehouses provide compute resources for executing queries and data-processing workloads.

A single warehouse cluster has finite execution capacity.

As concurrent workload increases, queries can begin waiting for available compute resources.

Conceptually:

```text
Users / Applications
        |
        v
   BI Warehouse
        |
        v
Execution capacity full
        |
        v
     Queueing
```

A common response is to increase the warehouse size.

However, a larger warehouse and a multi-cluster warehouse solve different problems.

```text
Scale Up
   |
   v
Larger warehouse cluster
   |
   v
More resources for query execution


Scale Out
   |
   v
Additional warehouse clusters
   |
   v
More concurrency capacity
```

Multi-cluster warehouses are designed primarily to address **concurrent workloads**.

Conceptually:

```text
                     Queries
                        |
                        v
                Multi-Cluster WH
                 /      |      \
                /       |       \
               v        v        v
          Cluster 1 Cluster 2 Cluster 3
```

Instead of forcing all concurrent queries through a single warehouse cluster, Snowflake can use additional clusters according to the warehouse configuration and scaling policy.

This chapter covers:

- concurrency fundamentals
- query queueing
- scale-up vs scale-out
- multi-cluster architecture
- minimum and maximum clusters
- scaling policies
- Standard and Economy behavior
- auto-scale mode
- maximized mode
- warehouse sizing
- workload isolation
- concurrency telemetry
- Query History
- queue-time metrics
- cost implications
- BI workloads
- application workloads
- ETL considerations
- troubleshooting
- capacity planning
- production rollout
- incident response
- hands-on testing
- FinOps controls

---

# Part 1 — What Is Concurrency?

## 1. Concurrent Queries

Concurrency refers to multiple queries attempting to execute at approximately the same time.

Example:

```text
User 1 ---- Query A
User 2 ---- Query B
User 3 ---- Query C
User 4 ---- Query D
User 5 ---- Query E
```

All queries may target the same warehouse.

---

# Part 2 — Warehouse Capacity

## 2. Finite Execution Resources

A warehouse has finite compute resources.

As concurrency grows:

```text
Queries
   |
   v
Available execution resources
   |
   +---- Capacity available -> execute
   |
   +---- Capacity unavailable -> wait
```

The exact number of queries that can execute simultaneously is not a universal fixed number.

It depends on workload characteristics and Snowflake execution behavior.

---

# Part 3 — Why Query Count Alone Is Misleading

## 3. Different Queries Consume Different Resources

Ten lightweight queries may create little pressure.

Ten expensive queries may create substantial pressure.

Example:

```text
10 × simple lookup
```

is very different from:

```text
10 × large join + aggregation
```

Therefore:

> Concurrent query count alone does not define warehouse capacity.

---

# Part 4 — Query Queueing

## 4. Capacity Exhaustion

When warehouse execution resources are unavailable, queries may queue.

Conceptually:

```text
Incoming queries
      |
      v
Warehouse busy
      |
      v
Queries waiting
      |
      v
Resources become available
      |
      v
Execution
```

Queueing directly affects user-perceived latency.

---

# Part 5 — Queue Time vs Execution Time

## 5. Example

Suppose a dashboard query reports:

```text
Total elapsed = 45 seconds
Execution     = 5 seconds
Queue         = 40 seconds
```

The query itself is not the primary performance problem.

The concurrency environment is.

---

# Part 6 — Another Example

## 6. Execution-Dominated Query

Suppose:

```text
Total elapsed = 45 seconds
Execution     = 44 seconds
Queue         = 1 second
```

This is a different problem.

Multi-cluster scaling may not materially improve the individual query.

Investigate query execution.

---

# Part 7 — Scale Up

## 7. Larger Warehouse

Scaling up means:

```text
MEDIUM
   |
   v
LARGE
```

The warehouse cluster receives more compute resources.

This can improve appropriate compute-intensive query workloads.

---

# Part 8 — Scale Out

## 8. Additional Clusters

Scaling out means allowing multiple warehouse clusters.

Example:

```text
                 BI_WH
                   |
        +----------+----------+
        |          |          |
        v          v          v
    Cluster 1  Cluster 2  Cluster 3
```

This primarily increases capacity for concurrent workloads.

---

# Part 9 — Critical Difference

## 9. One Slow Query

Do not assume:

```text
1 slow query
     |
     v
Add 5 clusters
```

and expect that one query to automatically use all five clusters.

Multi-cluster warehouses are primarily a concurrency solution.

---

# Part 10 — Multi-Cluster Warehouse Architecture

## 10. Logical Warehouse

Applications still reference one warehouse.

Example:

```sql
USE WAREHOUSE production_bi_wh;
```

Behind that logical warehouse, Snowflake can operate multiple clusters according to configuration.

Conceptually:

```text
Application
     |
     v
PRODUCTION_BI_WH
     |
 +---+---+---+
 |       |   |
 v       v   v
C1      C2  C3
```

The application does not need to choose a cluster.

---

# Part 11 — Shared Data

## 11. Storage Separation

Clusters access the same Snowflake data.

```text
             Snowflake Storage
                    |
       +------------+------------+
       |            |            |
       v            v            v
   Cluster 1    Cluster 2    Cluster 3
```

This is possible because Snowflake separates storage from compute.

---

# Part 12 — Minimum Clusters

## 12. MIN_CLUSTER_COUNT

Multi-cluster configuration includes a minimum cluster count.

Conceptually:

```text
MIN_CLUSTER_COUNT = 1
```

This defines the lower bound for active warehouse clusters according to the current Snowflake multi-cluster behavior.

---

# Part 13 — Maximum Clusters

## 13. MAX_CLUSTER_COUNT

The maximum cluster count defines the upper scaling boundary.

Example:

```text
MAX_CLUSTER_COUNT = 5
```

Conceptually:

```text
Minimum = 1
Maximum = 5

1 <= active clusters <= 5
```

depending on configuration and workload.

---

# Part 14 — Why Maximum Matters

## 14. Capacity and Cost Guardrail

The maximum cluster count controls potential scale-out capacity.

It also limits potential compute expansion.

```text
Higher maximum
      |
      +---- More concurrency capacity
      |
      +---- More potential credit consumption
```

Therefore, maximum cluster count is both a performance and FinOps decision.

---

# Part 15 — Auto-Scale Mode

## 15. Elastic Cluster Count

A common multi-cluster configuration uses a range:

```text
Minimum clusters < Maximum clusters
```

Example:

```text
MIN_CLUSTER_COUNT = 1
MAX_CLUSTER_COUNT = 4
```

Snowflake can add or remove clusters according to workload and scaling policy.

This is commonly described as auto-scale behavior.

---

# Part 16 — Maximized Mode

## 16. Fixed Multiple Clusters

When minimum and maximum cluster counts are configured to the same value greater than one, the warehouse can operate with that fixed number of clusters.

Conceptually:

```text
MIN_CLUSTER_COUNT = 3
MAX_CLUSTER_COUNT = 3
```

This represents a maximized-style configuration rather than dynamically varying between one and three clusters.

Validate exact current Snowflake terminology and behavior before production configuration.

---

# Part 17 — Auto-Scale Example

## 17. Morning BI Workload

At 06:00:

```text
Queries = low

Cluster 1
```

At 09:00:

```text
Queries = high

Cluster 1
Cluster 2
Cluster 3
```

At 14:00:

```text
Queries = moderate

Cluster 1
Cluster 2
```

Later:

```text
Queries = low

Cluster 1
```

The objective is elastic concurrency capacity.

---

# Part 18 — Scaling Policy

## 18. Policy Controls

Snowflake supports scaling policies for multi-cluster warehouses.

Common policy concepts include:

```text
STANDARD
ECONOMY
```

The exact current behavior and timing rules should always be validated against Snowflake documentation.

---

# Part 19 — Standard Scaling Policy

## 19. Performance-Oriented Behavior

The Standard policy generally prioritizes reducing query queueing by making additional clusters available more readily when workload requires them.

Conceptually:

```text
Concurrency rises
       |
       v
Potential queueing
       |
       v
Additional cluster
```

This can provide better responsiveness at potentially higher compute cost.

---

# Part 20 — Economy Scaling Policy

## 20. Cost-Oriented Behavior

The Economy policy generally favors keeping existing clusters more fully utilized before starting additional clusters.

Conceptually:

```text
Concurrency rises
       |
       v
Use existing capacity more aggressively
       |
       v
Scale when justified
```

This can reduce cluster expansion but may permit more queueing.

---

# Part 21 — Standard vs Economy

## 21. Conceptual Comparison

| Policy | Primary Bias |
|---|---|
| Standard | Performance / lower queueing |
| Economy | Compute efficiency / fewer additional clusters |

The exact scaling conditions are controlled by Snowflake and should not be reduced to a simplistic fixed threshold.

---

# Part 22 — Choosing a Policy

## 22. Interactive BI

For latency-sensitive dashboards:

```text
Queueing tolerance = low
```

A performance-oriented policy may be more appropriate.

## 23. Batch Workloads

For workloads where some queueing is acceptable and cost efficiency is more important, a more conservative policy may be appropriate.

Always validate using the real workload.

---

# Part 23 — Multi-Cluster DDL

## 24. Conceptual Configuration

A multi-cluster warehouse configuration can conceptually resemble:

```sql
CREATE WAREHOUSE production_bi_wh
WITH
    WAREHOUSE_SIZE = 'MEDIUM'
    MIN_CLUSTER_COUNT = 1
    MAX_CLUSTER_COUNT = 4
    SCALING_POLICY = 'STANDARD'
    AUTO_SUSPEND = 300
    AUTO_RESUME = TRUE;
```

Validate current Snowflake syntax, feature availability, edition requirements, and defaults before production execution.

---

# Part 24 — Altering an Existing Warehouse

## 25. Conceptual Example

```sql
ALTER WAREHOUSE production_bi_wh
SET
    MIN_CLUSTER_COUNT = 1
    MAX_CLUSTER_COUNT = 4
    SCALING_POLICY = 'STANDARD';
```

Use approved change management before modifying production warehouse capacity.

---

# Part 25 — Edition Considerations

## 26. Feature Availability

Multi-cluster warehouse capabilities can depend on Snowflake edition and current product behavior.

Before designing around multi-cluster warehouses, verify:

```text
Account edition
Region/cloud availability
Warehouse feature support
Current Snowflake documentation
```

Do not assume every account has identical capabilities.

---

# Part 26 — Concurrency vs Warehouse Size

## 27. Two Variables

A warehouse can be configured with:

```text
Cluster size
+
Cluster count
```

Example:

```text
4 × MEDIUM clusters
```

is different from:

```text
1 × XLARGE cluster
```

Even when total theoretical compute appears comparable, the workload behavior can differ significantly.

---

# Part 27 — Which One Should You Choose?

## 28. Question 1

Are individual queries slow with little queueing?

```text
Yes
 |
 v
Investigate query optimization / scale up
```

## 29. Question 2

Are otherwise healthy queries waiting in queues?

```text
Yes
 |
 v
Investigate scale out
```

---

# Part 28 — Scale Up Before Scale Out?

## 30. No Universal Rule

Do not apply a universal sequence such as:

> Always resize before enabling multi-cluster.

The correct action depends on evidence.

Some workloads have single-query resource pressure. Others have concurrency pressure. Others have both.

---

# Part 29 — Combined Scaling

## 31. Both May Be Required

Example:

```text
Current:
1 × SMALL

Problem:
Queries individually slow
+
High queueing
```

A validated architecture might eventually use:

```text
Multiple MEDIUM clusters
```

But each change should be tested carefully.

---

# Part 30 — Query History

## 32. Concurrency Evidence

Snowflake Query History provides important workload telemetry.

Capture fields related to query start/end time, execution time, warehouse, warehouse size, queueing, bytes scanned, and rows produced.

Exact column names should be verified against the current Snowflake Query History interface.

---

# Part 31 — Queue Metrics

## 33. Overload Queueing

A key metric for concurrency analysis is time spent queued because warehouse execution capacity is overloaded.

Snowflake exposes queue-related timing in query telemetry.

Use the exact current field names from Snowflake documentation.

---

# Part 32 — Provisioning Queue

## 34. Different Queue Causes

Not every queued query is waiting because of concurrency.

Queueing can have different causes.

Examples include:

```text
Warehouse overload
Warehouse provisioning
Warehouse repair
Other execution state
```

Therefore:

> Do not aggregate every type of queue time into one concurrency metric.

---

# Part 33 — Why Queue Classification Matters

## 35. Example

Suppose:

```text
Queued time = 30 sec
```

If the time is caused by warehouse provisioning, adding more clusters may not address the root cause.

If the time is caused by overload, concurrency capacity becomes more relevant.

---

# Part 34 — Concurrency Analysis Window

## 36. Use Time Buckets

Analyze workload in intervals such as:

```text
1 minute
5 minutes
15 minutes
1 hour
```

depending on workload.

Daily averages can hide short but severe concurrency spikes.

---

# Part 35 — Example Daily Average Problem

## 37. Daily View

```text
Average concurrent queries = 8
```

Looks healthy.

But between 09:00 and 09:15:

```text
Concurrent queries = 120
```

and dashboard users experience severe queueing.

Capacity planning must capture peaks.

---

# Part 36 — P95 and P99 Queue Time

## 38. Tail Latency

Track average, P50, P95, P99, and maximum queue time.

Tail queue time is often more meaningful for interactive applications.

---

# Part 37 — BI Dashboard Concurrency

## 39. Fan-Out

One dashboard refresh may execute many queries.

Example:

```text
1 user
   |
   v
Dashboard
   |
   +---- Query 1
   +---- Query 2
   +---- Query 3
   +---- Query 4
   +---- Query 5
```

Now multiply by hundreds of users.

Concurrency can increase rapidly.

---

# Part 38 — Morning Login Storm

## 40. Example

```text
400 users open dashboard
       |
       v
Multiple queries/user
       |
       v
Concurrency spike
       |
       v
Warehouse queue
```

Multi-cluster warehouses are particularly relevant to this type of workload.

---

# Part 39 — Application Workloads

## 41. Interactive Applications

Applications may generate short queries, high frequency, bursty concurrency, and low latency SLAs.

If query execution is already efficient but queueing dominates latency, scale-out can be appropriate.

---

# Part 40 — ETL Workloads

## 42. Batch Processing

ETL may consist of a few large queries rather than thousands of short concurrent queries.

In such cases, scaling up or query optimization may be more useful than multi-cluster scaling.

---

# Part 41 — Parallel Pipelines

## 43. ETL Can Also Be Concurrent

Suppose Pipeline A through Pipeline E all start at midnight on the same warehouse.

Then ETL becomes a concurrency problem as well.

---

# Part 42 — Scheduling Before Scaling

## 44. Avoid Artificial Concurrency

If five non-urgent pipelines all start at exactly 00:00, consider whether they can be staggered.

Scheduling may reduce unnecessary peak demand.

---

# Part 43 — Workload Isolation

## 45. Shared Warehouse

Suppose BI, ETL, ad hoc, and application workloads all use one warehouse.

Queueing may be caused by unrelated workloads.

---

# Part 44 — Separate Warehouses

## 46. Better Architecture

```text
BI           -> BI_WH
ETL          -> ETL_WH
Applications -> APP_WH
Ad hoc       -> ADHOC_WH
```

This provides independent concurrency capacity.

---

# Part 45 — Isolation Before Multi-Cluster

## 47. Example

If one ETL query blocks BI workload capacity, adding clusters to the shared warehouse may hide an architectural problem.

Separating workloads can improve predictability, cost attribution, troubleshooting, and SLA management.

---

# Part 46 — Multi-Cluster Cache Behavior

## 48. Cluster-Local Cache

Warehouse-local data cache behavior must be considered when multiple clusters are active.

Do not assume every cluster has identical warm-cache state.

```text
Cluster 1 cache != Cluster 2 cache
```

A newly started cluster may initially have different cache behavior from an existing warm cluster.

---

# Part 47 — Cache and Benchmarking

## 49. Test Carefully

When testing multi-cluster performance, record cluster count, warehouse state, cache conditions, query concurrency, and query mix.

Otherwise, cache effects can be mistaken for concurrency improvements or regressions.

---

# Part 48 — Auto-Suspend

## 50. Warehouse-Level Behavior

Auto-suspend remains important for multi-cluster warehouses.

The exact relationship between warehouse suspension, individual cluster shutdown, and scaling behavior should be understood from current Snowflake documentation.

---

# Part 49 — Credit Consumption

## 51. Every Active Cluster Costs Compute

Conceptually:

```text
1 active cluster
     |
     v
Compute credits

3 active clusters
     |
     v
More compute credits
```

The exact consumption depends on warehouse size, active duration, and Snowflake billing rules.

---

# Part 50 — Performance vs Cost

## 52. Example

Before:

```text
1 cluster
Dashboard P95 = 30 sec
Queue P95     = 24 sec
```

After:

```text
Up to 3 clusters
Dashboard P95 = 7 sec
Queue P95     = 1 sec
```

The performance improvement may be substantial.

Now measure the additional credits.

---

# Part 51 — Cost per Business Transaction

## 53. Better FinOps Metric

For BI, calculate metrics such as:

```text
Credits / dashboard refresh
Credits / active user
Credits / 1,000 queries
```

This provides better context than warehouse credits alone.

---

# Part 52 — Maximum Cluster Guardrail

## 54. Avoid Unlimited Thinking

Do not simply configure the highest available maximum cluster count because it might be needed someday.

Determine a capacity requirement from observed peak demand, forecast growth, and defined operational headroom.

---

# Part 53 — Minimum Cluster Cost

## 55. Minimum Greater Than One

A higher minimum cluster count can provide immediately available capacity.

But it can also keep more compute active.

This may be justified for strict latency SLAs.

It should not be the default without evidence.

---

# Part 54 — Scaling Policy Economics

## 56. Standard

Potential benefits include lower queueing, faster response to concurrency, and better interactive latency.

Potential trade-off: more aggressive cluster use.

## 57. Economy

Potential benefits include better cluster utilization and potentially lower compute use.

Potential trade-off: more tolerated queueing.

Measure the actual workload.

---

# Part 55 — Production Baseline

## 58. Before Enabling Multi-Cluster

Capture:

```text
Warehouse:
Size:
Current clusters:
Query volume:
Peak concurrency:
Average queue:
P95 queue:
P99 queue:
Average execution:
P95 execution:
Credits/day:
SLA:
```

---

# Part 56 — Candidate Criteria

## 59. Strong Candidate

A workload is a stronger scale-out candidate when queries are individually efficient, queueing occurs under concurrency, queueing affects SLA, and concurrency is legitimate business demand.

## 60. Poor Candidate

Multi-cluster may be a weak first response when one query dominates the warehouse, queries have poor pruning, join explosion exists, remote spill dominates, bad SQL dominates, or concurrency is caused by avoidable scheduling.

---

# Part 58 — Controlled Rollout

## 61. Step 1

Capture baseline.

## 62. Step 2

Confirm overload queueing.

## 63. Step 3

Confirm query efficiency.

## 64. Step 4

Define:

```text
Min clusters
Max clusters
Scaling policy
Cost threshold
SLA target
```

## 65. Step 5

Enable in a controlled environment or change window.

## 66. Step 6

Measure queue time, execution time, total latency, cluster count, and credits.

## 67. Step 7

Compare against baseline.

---

# Part 59 — Acceptance Criteria for Change

## 68. Example

Before:

```text
Dashboard P95 = 25 sec
Queue P95     = 18 sec
```

Target:

```text
Dashboard P95 < 10 sec
Queue P95     < 2 sec
```

Cost guardrail: daily warehouse credits must remain within approved budget.

---

# Part 60 — Rollback Criteria

## 69. Define Before Production

Examples include no meaningful queue reduction, no SLA improvement, unexpected cost increase, application regression, or operational instability.

---

# Part 61 — Troubleshooting: Multi-Cluster Enabled but Queueing Continues

## 70. Check

```text
Current active clusters
Maximum clusters
Scaling policy
Query type
Query duration
Concurrency level
Warehouse size
Workload mix
```

The warehouse may already be at its configured maximum.

---

# Part 62 — Troubleshooting: Max Clusters Reached

## 71. Scenario

```text
MAX_CLUSTER_COUNT = 3
Active clusters = 3
Queueing remains high
```

Investigate demand growth, warehouse size, query efficiency, workload isolation, scheduling, and maximum cluster capacity.

Do not automatically raise the maximum.

---

# Part 63 — Troubleshooting: Clusters Scale but Performance Does Not Improve

## 72. Possible Cause

The workload may not actually be concurrency-bound.

Check execution time, queue time, Query Profile, spill, pruning, joins, and external dependencies.

---

# Part 64 — Troubleshooting: Cost Spike

## 73. Scenario

Warehouse credits increase after multi-cluster enablement.

Check how many clusters became active, for how long, what triggered them, whether query volume increased, whether scaling policy or minimum cluster count changed, and whether the latency improvement justified the cost.

---

# Part 65 — Troubleshooting: New Cluster Slower

## 74. Cache Effects

A newly started cluster may not have the same local cache state as an existing cluster.

Investigate cold-cache effects before declaring the additional cluster unhealthy.

---

# Part 66 — Troubleshooting: Queueing Only at One Time

## 75. Peak Analysis

If queueing occurs only during a narrow time window, investigate dashboard refreshes, scheduled pipelines, application batch jobs, user login patterns, and external orchestrators.

A scheduling change may reduce the spike.

---

# Part 67 — Troubleshooting: One User Causes Queueing

## 76. Ad Hoc Workload

A single analyst may submit many expensive queries simultaneously.

Potential actions include workload isolation, a dedicated warehouse, query optimization, and usage governance.

Do not automatically scale the production BI warehouse for an unrelated ad hoc workload.

---

# Part 68 — Concurrency Incident Runbook

## 77. Production Incident

1. Identify affected warehouse.
2. Identify incident start time.
3. Capture affected query IDs.
4. Check total query volume.
5. Check concurrency.
6. Check overload queue time.
7. Separate execution time from queue time.
8. Check active cluster count.
9. Check minimum cluster count.
10. Check maximum cluster count.
11. Check scaling policy.
12. Determine whether max clusters were reached.
13. Identify workload sources.
14. Check BI activity.
15. Check ETL schedules.
16. Check application traffic.
17. Check ad hoc workloads.
18. Review Query Profile for representative queries.
19. Check warehouse size.
20. Check cache considerations.
21. Check recent warehouse changes.
22. Check query/deployment changes.
23. Determine root cause.
24. Apply targeted mitigation.
25. Validate queue reduction.
26. Validate SLA.
27. Validate cost.
28. Document findings.

---

# Part 69 — Immediate Mitigation

## 78. Incident Options

Depending on evidence and operational approval, mitigation may include temporarily increasing concurrency capacity, moving workload to another warehouse, pausing non-critical jobs, rescheduling batch workloads, optimizing pathological queries, increasing warehouse size, or adjusting multi-cluster configuration.

Choose the action that addresses the actual bottleneck.

---

# Part 70 — Do Not Change Everything

## 79. Incident Discipline

Avoid simultaneously resizing the warehouse, increasing max clusters, changing scaling policy, enabling QAS, and changing SQL unless emergency conditions require multiple actions.

Otherwise, determining what fixed the issue becomes difficult.

---

# Part 71 — Evidence Template

## 80. Concurrency Investigation

```text
Environment:
Warehouse:
Warehouse size:
Min clusters:
Max clusters:
Scaling policy:
Incident start:
Incident end:
Peak query count:
Peak concurrency:
Average queue:
P95 queue:
P99 queue:
Execution P50:
Execution P95:
Execution P99:
Active cluster count:
Workload sources:
BI:
ETL:
Application:
Ad hoc:
Credits before:
Credits during:
Recent changes:
Root cause:
Mitigation:
Validation:
Cost impact:
```

---

# Part 72 — Capacity Planning

## 81. Trend Concurrency

Track peak concurrency, P95 concurrency, queue P95, queue P99, active clusters, and credits over time.

## 82. Trend Example

```text
January peak concurrency = 30
February                 = 42
March                    = 58
April                    = 75
```

If cluster utilization and queueing rise with this trend, future capacity requirements should be planned before SLA failures occur.

---

# Part 74 — Headroom

## 83. Why Headroom Matters

Production systems need room for traffic spikes, backfills, late jobs, incident recovery, business events, and unexpected dashboard demand.

Do not operate permanently at maximum configured capacity if the SLA requires predictable response.

---

# Part 75 — Multi-Cluster Monitoring Dashboard

## 84. Recommended Metrics

Track warehouse, warehouse size, min/max clusters, scaling policy, active clusters, query count, concurrency, queue percentiles, execution percentiles, credits/hour, credits/day, and SLA violations.

---

# Part 76 — Alerting

## 85. Useful Alerts

Potential alerts include persistent overload queueing, max cluster count reached, P95/P99 queue exceeding SLA, unexpected cluster expansion, and warehouse credit anomalies.

Thresholds must reflect the workload's SLA and normal baseline.

---

# Part 77 — Daily Review

## 86. Operational Check

Review peak queue, peak cluster count, SLA violations, credit anomalies, and unexpected workload.

---

# Part 78 — Weekly Review

## 87. Capacity Check

Review concurrency trend, queue trend, cluster utilization, scaling events, and cost trend.

---

# Part 79 — Monthly Review

## 88. Architecture Check

Ask whether warehouse size, min/max clusters, and scaling policy remain appropriate; whether workloads should be separated; whether jobs can be rescheduled; and whether multi-cluster remains economically justified.

---

# Part 80 — FinOps Review

## 89. Performance Alone Is Not Enough

Compare before/after credits, queueing, and SLA.

---

# Part 81 — Example FinOps Outcome

## 90. Before

```text
1 cluster
Credits/day = 100
P95 latency = 30 sec
```

## 91. After

```text
Auto-scale 1–3 clusters
Credits/day = 125
P95 latency = 6 sec
```

This may represent strong value if the SLA requires interactive performance.

---

# Part 82 — Poor FinOps Outcome

## 92. Example

```text
Before:
Credits/day = 100
P95 = 8 sec

After:
Credits/day = 220
P95 = 7 sec
```

The additional capacity may not be economically justified.

---

# Part 83 — Workload Isolation Example

## 93. Before

```text
SHARED_WH
   |
   +---- BI
   +---- ETL
   +---- Ad hoc
```

Queueing occurs unpredictably.

## 94. After

```text
BI_WH
ETL_WH
ADHOC_WH
```

BI concurrency becomes easier to size independently.

---

# Part 84 — Production Architecture Example

## 95. BI

```text
PROD_BI_WH
Size: Medium
Min: 1
Max: 4
Policy: Standard
```

## 96. ETL

```text
PROD_ETL_WH
Size: Large
Single cluster
```

## 97. Ad Hoc

```text
PROD_ADHOC_WH
Size: Small
Aggressive auto-suspend
```

These are examples only.

Actual configuration must be based on measured workload and current Snowflake capabilities.

---

# Part 85 — Hands-On Lab

## 98. Objective

Observe concurrency and queueing behavior using a controlled non-production warehouse.

Do not generate uncontrolled load against a shared or production warehouse.

## 99. Create Lab Database

```sql
CREATE OR REPLACE DATABASE concurrency_lab;
```

## 100. Create Schema

```sql
CREATE OR REPLACE SCHEMA concurrency_lab.demo;
```

## 101. Create Synthetic Table

```sql
CREATE OR REPLACE TABLE concurrency_lab.demo.sales (
    transaction_id NUMBER,
    customer_id NUMBER,
    product_id NUMBER,
    transaction_date DATE,
    region STRING,
    amount NUMBER(12,2)
);
```

## 102. Generate Synthetic Data

```sql
INSERT INTO concurrency_lab.demo.sales
SELECT
    SEQ4(),
    MOD(SEQ4(), 1000000),
    MOD(SEQ4(), 100000),
    DATEADD(day, -MOD(SEQ4(), 730), CURRENT_DATE()),
    CASE MOD(SEQ4(), 5)
        WHEN 0 THEN 'EAST'
        WHEN 1 THEN 'WEST'
        WHEN 2 THEN 'NORTH'
        WHEN 3 THEN 'SOUTH'
        ELSE 'CENTRAL'
    END,
    MOD(SEQ4(), 1000000) / 100.0
FROM TABLE(GENERATOR(ROWCOUNT => 20000000));
```

All data is synthetic.

Adjust the row count to match your approved lab budget.

## 103. Disable Persisted Result Reuse

```sql
ALTER SESSION SET USE_CACHED_RESULT = FALSE;
```

## 104. Representative Query

```sql
SELECT
    region,
    product_id,
    COUNT(*) AS transaction_count,
    SUM(amount) AS total_amount,
    AVG(amount) AS average_amount
FROM concurrency_lab.demo.sales
WHERE transaction_date >= DATEADD(day, -365, CURRENT_DATE())
GROUP BY region, product_id
ORDER BY total_amount DESC;
```

---

# Part 86 — Baseline Test

## 105. Single Query

Run one query and capture query ID, execution time, queue time, warehouse, and warehouse size.

This establishes individual-query behavior.

---

# Part 87 — Controlled Concurrent Test

## 106. Generate Safe Concurrency

From a small number of separate approved sessions, execute the representative query concurrently.

Increase only within approved lab limits.

Do not create a load test against production.

## 107. Capture

For each query, capture query ID, start time, queue time, execution time, and total elapsed time.

---

# Part 88 — Multi-Cluster Test

## 108. Configure Lab Warehouse

If your Snowflake edition and lab environment support multi-cluster warehouses, configure a controlled range using current Snowflake-supported syntax.

Conceptually:

```sql
ALTER WAREHOUSE concurrency_lab_wh
SET
    MIN_CLUSTER_COUNT = 1
    MAX_CLUSTER_COUNT = 2
    SCALING_POLICY = 'STANDARD';
```

Validate syntax and account support first.

## 109. Repeat Concurrent Workload

Run the same controlled workload and capture queue time, execution time, total elapsed, active cluster behavior, and credits.

---

# Part 89 — Compare

## 110. Results

| Metric | Single Cluster | Multi-Cluster |
|---|---:|---:|
| Query count | | |
| P50 queue | | |
| P95 queue | | |
| P99 queue | | |
| P50 execution | | |
| P95 execution | | |
| Total elapsed | | |
| Credits | | |

---

# Part 90 — Interpret Results

## 111. Desired Observation

If the workload is concurrency-bound, multi-cluster scaling should primarily improve queueing and throughput rather than fundamentally changing the execution characteristics of each individual query.

---

# Part 91 — Scaling Policy Test

## 112. Optional

If budget and lab controls permit, compare supported scaling policies using the same workload.

Record cluster behavior, queue time, and credits.

Do not perform unnecessary load merely to observe scaling.

---

# Part 92 — Restore Environment

## 113. Restore Session

```sql
ALTER SESSION SET USE_CACHED_RESULT = TRUE;
```

## 114. Cleanup

```sql
DROP DATABASE IF EXISTS concurrency_lab;
```

Restore the lab warehouse configuration to its approved baseline.

---

# Part 93 — Production Checklist

## 115. Before Multi-Cluster

```text
□ Workload identified
□ SLA documented
□ Query efficiency reviewed
□ Concurrency measured
□ Overload queueing measured
□ Peak periods identified
□ Workload isolation reviewed
□ Scheduling reviewed
```

## 116. Configuration

```text
□ Warehouse size justified
□ Minimum clusters justified
□ Maximum clusters justified
□ Scaling policy justified
□ Auto-suspend reviewed
□ Auto-resume reviewed
□ Cost ceiling defined
```

## 117. Validation

```text
□ P50 queue measured
□ P95 queue measured
□ P99 queue measured
□ Execution time measured
□ Active clusters monitored
□ Credits measured
□ SLA validated
```

## 118. Operations

```text
□ Monitoring configured
□ Alerts configured
□ Owner assigned
□ Runbook documented
□ Rollback defined
□ Monthly review scheduled
```

---

# Part 94 — Decision Tree

## 119. Concurrency Decision

```text
Queries slow
    |
    v
Queueing significant?
   /        \
 Yes         No
 |            |
 v            v
Concurrency   Execution problem
pressure           |
 |                 v
 v           Review Query Profile
Are workloads      |
isolated?          +---- Poor pruning
 /   \             +---- Spill
No   Yes           +---- Bad joins
|      |            +---- Compute pressure
v      v
Isolate  Is demand
first    legitimate?
          /    \
        No      Yes
        |        |
        v        v
   Reschedule/   Evaluate
   optimize      scale out
                    |
                    v
            Define min/max
                    |
                    v
             Select policy
                    |
                    v
             Measure queue
                    +
                  credits
```

---

# Part 95 — Operational Principles

## 120. Principle 1

Multi-cluster warehouses primarily address concurrency.

## 121. Principle 2

Do not confuse queue time with execution time.

## 122. Principle 3

Do not add clusters to fix a bad query.

## 123. Principle 4

Separate unrelated workloads before scaling shared contention indefinitely.

## 124. Principle 5

Use peak and percentile metrics, not daily averages.

## 125. Principle 6

Maximum cluster count is both a capacity and cost guardrail.

## 126. Principle 7

Choose scaling policy according to SLA and economics.

## 127. Principle 8

Account for cluster-local cache behavior.

## 128. Principle 9

Measure credits together with latency.

## 129. Principle 10

Continuously revisit concurrency capacity as workloads grow.

---

# Acceptance Criteria

The chapter is complete when you can:

- explain Snowflake query concurrency
- explain warehouse execution capacity
- explain why query count alone is insufficient
- identify query queueing
- distinguish queue time from execution time
- explain scale up
- explain scale out
- distinguish scale up from scale out
- explain multi-cluster architecture
- explain logical warehouse abstraction
- explain shared Snowflake storage
- understand minimum cluster count
- understand maximum cluster count
- use maximum clusters as a cost guardrail
- explain auto-scale behavior
- explain maximized-style behavior
- understand scaling policies
- distinguish Standard and Economy policy goals
- choose policy according to workload requirements
- understand conceptual multi-cluster DDL
- understand edition considerations
- evaluate warehouse size and cluster count separately
- identify scale-up candidates
- identify scale-out candidates
- understand combined scaling
- use Query History for concurrency analysis
- analyze overload queueing
- distinguish different queue causes
- use time-bucket analysis
- avoid relying on daily averages
- monitor P50/P95/P99 queue time
- understand BI dashboard fan-out
- understand login/concurrency storms
- evaluate interactive application workloads
- evaluate ETL concurrency
- stagger workloads when appropriate
- implement workload isolation
- account for cluster-local cache
- understand multi-cluster credit implications
- calculate workload-oriented FinOps metrics
- justify maximum cluster count
- justify minimum cluster count
- evaluate scaling-policy economics
- capture a production baseline
- identify strong scale-out candidates
- identify weak scale-out candidates
- execute a controlled rollout
- define acceptance criteria
- define rollback criteria
- troubleshoot persistent queueing
- troubleshoot max-cluster saturation
- troubleshoot ineffective scale-out
- troubleshoot cost spikes
- troubleshoot new-cluster cache effects
- investigate time-specific queueing
- isolate disruptive ad hoc workloads
- execute a concurrency incident runbook
- choose evidence-based immediate mitigation
- avoid uncontrolled multi-variable changes
- capture concurrency investigation evidence
- perform concurrency capacity planning
- maintain operational headroom
- build a multi-cluster monitoring dashboard
- define useful alerts
- conduct daily, weekly, and monthly reviews
- evaluate multi-cluster FinOps
- design workload-specific warehouse architecture
- perform the controlled hands-on lab
- compare single-cluster and multi-cluster behavior
- interpret queueing improvements correctly
- restore lab configuration safely
- use the production checklist
- apply the concurrency decision tree

---

## Key Takeaways

The central distinction is:

```text
Scale Up
   |
   v
More resources
inside a warehouse cluster
   |
   v
Can improve appropriate
single-query workloads
```

versus:

```text
Scale Out
   |
   v
More warehouse clusters
   |
   v
Can improve concurrency
and reduce queueing
```

A multi-cluster warehouse should therefore not be the automatic answer to:

> Our queries are slow.

First determine:

```text
Slow because of execution?
          |
          v
Optimize / scale up / QAS

Slow because of queueing?
          |
          v
Isolate / reschedule / scale out
```

For production concurrency management:

```text
Measure demand
     |
     v
Measure queueing
     |
     v
Separate queue from execution
     |
     v
Review workload isolation
     |
     v
Define min/max clusters
     |
     v
Choose scaling policy
     |
     v
Measure latency + credits
```

The goal is not:

> Run as many clusters as possible.

The goal is:

> Provide enough elastic concurrency capacity to meet workload SLAs without unnecessary compute consumption.

The next chapter is **Chapter 45 — Performance Troubleshooting**.
