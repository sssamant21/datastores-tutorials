# 48 — Warehouse Monitoring

## Overview

Snowflake virtual warehouses provide the compute layer for SQL workloads.

From an operational perspective, a warehouse should never be monitored only by asking:

> Is the warehouse running?

A warehouse can be running while users experience:

- query queueing
- high latency
- insufficient compute
- excessive concurrency
- frequent suspend/resume cycles
- cold-cache effects
- unexpected scaling
- excessive credit consumption
- workload interference
- failed queries
- inefficient utilization

Production warehouse monitoring therefore requires several telemetry sources.

Conceptually:

```text
Warehouse Monitoring
        |
        +---- State
        +---- Query workload
        +---- Queueing
        +---- Load
        +---- Concurrency
        +---- Scaling
        +---- Credits
        +---- Cache behavior
        +---- Failures
        +---- Workload attribution
        |
        v
Operational Health
```

This chapter develops a production-focused monitoring framework for Snowflake warehouses.

It covers:

- warehouse state
- warehouse configuration
- warehouse inventory
- warehouse load
- query throughput
- query latency
- queueing
- concurrency
- provisioning delay
- warehouse sizing
- multi-cluster warehouses
- cluster scaling
- auto-suspend
- auto-resume
- warehouse cache considerations
- warehouse metering
- credit consumption
- utilization
- workload isolation
- baseline monitoring
- capacity indicators
- operational dashboards
- alerting
- incident investigation
- monitoring runbooks
- hands-on monitoring lab

---

# Part 1 — What Should Be Monitored?

## 1. Warehouse Health Is Multi-Dimensional

A healthy warehouse should be evaluated across several dimensions.

```text
Warehouse
   |
   +---- Available?
   +---- Correctly configured?
   +---- Handling workload?
   +---- Queueing?
   +---- Properly sized?
   +---- Scaling correctly?
   +---- Consuming expected credits?
   +---- Serving the correct workload?
```

No single metric answers all of these questions.

---

# Part 2 — Warehouse State

## 2. Operational State

Warehouse state provides basic availability information.

Depending on the interface and operation, warehouses may be:

```text
STARTED
SUSPENDED
RESIZING
```

or represented through other current Snowflake state values.

Always validate exact state values against the current Snowflake interface being queried.

---

# Part 3 — Warehouse Inventory

## 3. Know What Exists

Production teams should maintain visibility into:

```text
Warehouse name
Size
Type
Owner
Auto-suspend
Auto-resume
Min clusters
Max clusters
Scaling policy
Resource monitor
Purpose
Environment
Owning team
```

An unknown warehouse is an operational and FinOps risk.

---

# Part 4 — SHOW WAREHOUSES

## 4. Operational Inspection

Snowflake provides warehouse metadata through supported SQL interfaces such as:

```sql
SHOW WAREHOUSES;
```

Use the current Snowflake documentation to validate available output columns and their semantics.

---

# Part 5 — Warehouse Configuration

## 5. Configuration Matters

Two warehouses processing similar workloads may behave very differently because of configuration.

Example:

```text
Warehouse A
Size = SMALL
Auto-suspend = 60 sec

Warehouse B
Size = LARGE
Auto-suspend = 600 sec
```

Monitoring should therefore include configuration context.

---

# Part 6 — Warehouse Size

## 6. Capacity Signal

Warehouse size affects available compute resources.

Typical size classes conceptually progress from smaller to larger compute configurations.

Do not hard-code assumptions about the complete current size range into monitoring without validating Snowflake's current warehouse offerings.

---

# Part 7 — Size Is Not Utilization

## 7. Important Distinction

A LARGE warehouse is not automatically heavily utilized.

Likewise, a SMALL warehouse is not automatically overloaded.

Monitor actual workload behavior.

```text
Warehouse size
      ≠
Warehouse load
```

---

# Part 8 — Query Throughput

## 8. Queries per Time Window

Track query volume by warehouse.

Useful metrics include:

```text
Queries/minute
Queries/hour
Queries/day
```

Example:

```sql
SELECT
    DATE_TRUNC('hour', start_time) AS hour,
    warehouse_name,
    COUNT(*) AS query_count
FROM SNOWFLAKE.ACCOUNT_USAGE.QUERY_HISTORY
WHERE start_time >= DATEADD(day, -7, CURRENT_TIMESTAMP())
  AND warehouse_name IS NOT NULL
GROUP BY 1, 2
ORDER BY 1, 2;
```

---

# Part 9 — Throughput Baseline

## 9. Know Normal

Suppose a warehouse normally processes:

```text
08:00–09:00 = 10,000 queries
09:00–10:00 = 12,000 queries
10:00–11:00 = 11,500 queries
```

Then suddenly:

```text
10:00–11:00 = 45,000 queries
```

That change deserves investigation even if the warehouse has not yet failed.

---

# Part 10 — Query Latency

## 10. Monitor User Experience

Warehouse monitoring should include query latency.

Track:

```text
P50
P95
P99
```

for important workloads.

Average latency alone can hide tail degradation.

---

# Part 11 — Warehouse-Level Latency

## 11. Example

Conceptually:

```sql
SELECT
    warehouse_name,
    APPROX_PERCENTILE(total_elapsed_time, 0.50) AS p50_ms,
    APPROX_PERCENTILE(total_elapsed_time, 0.95) AS p95_ms,
    APPROX_PERCENTILE(total_elapsed_time, 0.99) AS p99_ms
FROM SNOWFLAKE.ACCOUNT_USAGE.QUERY_HISTORY
WHERE start_time >= DATEADD(hour, -24, CURRENT_TIMESTAMP())
  AND execution_status = 'SUCCESS'
  AND warehouse_name IS NOT NULL
GROUP BY warehouse_name;
```

Validate the current percentile function and Query History field semantics before using this query in production automation.

---

# Part 12 — Execution vs Elapsed Time

## 12. Separate Them

Suppose:

```text
Elapsed = 30 sec
Execution = 4 sec
```

The warehouse may not have spent 30 seconds executing the SQL.

Possible contributors include:

- queueing
- provisioning
- compilation
- other lifecycle components

Monitor elapsed and execution time separately.

---

# Part 13 — Queueing

## 13. One of the Most Important Warehouse Signals

Queueing indicates that a query had to wait before execution.

Conceptually:

```text
Query arrives
     |
     v
Warehouse capacity available?
     |
   No
     |
     v
Queue
     |
     v
Execute
```

Persistent queueing is a strong capacity or concurrency signal.

---

# Part 14 — Overload Queue

## 14. Compute Contention

Overload queue time generally indicates that warehouse execution resources were busy.

Monitor:

```text
Queued queries
Queue duration
P95 queue
P99 queue
```

Do not rely only on the average.

---

# Part 15 — Provisioning Queue

## 15. Different Cause

Provisioning queueing may occur while compute resources are being made available.

Examples can include warehouse startup or scaling behavior.

This should not automatically be diagnosed as warehouse overload.

---

# Part 16 — Repair Queue

## 16. Operational Distinction

Where the current telemetry exposes repair-related queue time, analyze it separately.

The important principle is:

```text
Queue time
   |
   +---- Overload
   +---- Provisioning
   +---- Repair
```

Different queue types require different investigation paths.

---

# Part 17 — Queue Monitoring Query

## 17. Example

```sql
SELECT
    warehouse_name,
    COUNT(*) AS query_count,
    SUM(queued_overload_time) AS overload_queue_ms,
    SUM(queued_provisioning_time) AS provisioning_queue_ms,
    SUM(queued_repair_time) AS repair_queue_ms
FROM SNOWFLAKE.ACCOUNT_USAGE.QUERY_HISTORY
WHERE start_time >= DATEADD(hour, -1, CURRENT_TIMESTAMP())
  AND warehouse_name IS NOT NULL
GROUP BY warehouse_name
ORDER BY overload_queue_ms DESC;
```

Validate current column names and units before operationalizing this query.

---

# Part 18 — Queue Percentage

## 18. Useful Derived Metric

A useful operational concept is:

```text
Queue Ratio =
Queue Time
-----------
Elapsed Time
```

For example:

```text
Elapsed = 20 sec
Queue   = 15 sec

Queue ratio = 75%
```

This workload is primarily waiting rather than executing.

---

# Part 19 — Queue Percentiles

## 19. Tail Monitoring

Suppose:

```text
Average queue = 0.5 sec
P95 queue     = 8 sec
P99 queue     = 30 sec
```

The average suggests health.

The tail indicates user impact.

---

# Part 20 — Warehouse Load History

## 20. Load Telemetry

Snowflake provides warehouse-load telemetry through account usage interfaces.

A key source is conceptually:

```sql
SNOWFLAKE.ACCOUNT_USAGE.WAREHOUSE_LOAD_HISTORY
```

Validate current retention, latency, privileges, and columns against current Snowflake documentation.

---

# Part 21 — What Load History Provides

## 21. Operational View

Warehouse load history can help analyze:

```text
Running workload
Queued workload
Provisioning
Blocking
```

depending on the current interface and exposed metrics.

This is particularly valuable for capacity analysis.

---

# Part 22 — Average Running

## 22. Workload Activity

A running-query metric provides evidence about active warehouse workload during a time interval.

Track it over time rather than looking at one isolated sample.

---

# Part 23 — Average Queued Load

## 23. Capacity Pressure

If average queued workload rises while running workload remains high:

```text
Running workload ↑
Queued workload  ↑
```

the warehouse may be reaching concurrency capacity.

---

# Part 24 — Warehouse Load Timeline

## 24. Example

```text
08:00  Running low     Queue 0
09:00  Running medium  Queue 0
10:00  Running high    Queue low
10:30  Running high    Queue high
11:00  Running high    Queue high
12:00  Running medium  Queue 0
```

The 10:30–11:00 window deserves investigation.

---

# Part 25 — Concurrency

## 25. Throughput Is Not Concurrency

These workloads are different:

```text
100,000 queries/day
spread evenly
```

versus:

```text
100,000 queries/day
70,000 between 09:00–10:00
```

The second workload creates much greater concurrency pressure.

---

# Part 26 — Query Overlap

## 26. Concept

```text
Q1  |----------------|
Q2      |----------|
Q3       |-------------------|
Q4          |-------|
Q5             |------------|
```

Overlapping queries consume warehouse resources concurrently.

---

# Part 27 — Concurrency Monitoring

## 27. Signals

Use a combination of:

```text
Query count
Warehouse load
Queue time
Execution time
Cluster count
```

to understand concurrency.

Do not infer concurrency solely from query count.

---

# Part 28 — Workload Burst

## 28. Common Pattern

```text
09:00 dashboard refresh
        |
        v
Hundreds of queries
        |
        v
Warehouse concurrency spike
        |
        v
Queueing
```

This may be solved differently from a single long-running query.

---

# Part 29 — Multi-Cluster Warehouses

## 29. Scale-Out Monitoring

For multi-cluster warehouses, monitor:

```text
Minimum clusters
Maximum clusters
Scaling policy
Active cluster behavior
Queueing
Credit consumption
```

Chapter 44 covers multi-cluster architecture in depth.

---

# Part 30 — Scaling Behavior

## 30. Expected Pattern

Conceptually:

```text
Concurrency rises
       |
       v
Additional cluster starts
       |
       v
Queue pressure decreases
```

If queueing remains high despite scale-out, investigate:

- maximum cluster limit
- scaling policy
- workload shape
- single-query bottlenecks
- configuration
- unexpected workload growth

---

# Part 31 — Maximum Cluster Ceiling

## 31. Capacity Guardrail

Suppose:

```text
MIN_CLUSTER_COUNT = 1
MAX_CLUSTER_COUNT = 4
```

and demand reaches the configured ceiling.

If all allowed clusters are active and queueing remains high:

```text
Demand > configured scale-out capacity
```

This becomes a capacity-planning signal.

---

# Part 32 — Scaling Policy

## 32. Monitor the Policy Context

Scaling behavior depends on the configured policy.

Do not diagnose multi-cluster behavior without recording the warehouse's current scaling policy.

Validate current Snowflake policy options and exact behavior against current documentation.

---

# Part 33 — Warehouse Resize

## 33. Scale-Up

Resizing increases or decreases the compute capacity of warehouse clusters.

Monitor before and after:

```text
Execution P95
Queue P95
Spill
Throughput
Credits
```

A resize should be evaluated using evidence.

---

# Part 34 — Resize Validation

## 34. Example

Before:

```text
Size = MEDIUM
Execution P95 = 18 sec
Remote spill = high
```

After:

```text
Size = LARGE
Execution P95 = 7 sec
Remote spill = low
```

Now evaluate credit impact.

---

# Part 35 — Resize Does Not Fix Everything

## 35. Important

Increasing warehouse size does not automatically fix:

- poor pruning
- bad joins
- unnecessary scans
- excessive query frequency
- retry storms
- mixed workloads
- poor application design

Warehouse monitoring should help prevent resize from becoming the default response to every problem.

---

# Part 36 — Auto-Suspend

## 36. Cost and Performance Trade-Off

Auto-suspend reduces idle warehouse consumption.

Conceptually:

```text
No workload
    |
    v
Idle timer
    |
    v
Suspend
```

This is valuable for cost control.

---

# Part 37 — Auto-Suspend Monitoring

## 37. What to Watch

Monitor whether warehouses:

```text
Never suspend
Suspend too frequently
Remain idle too long
Repeatedly suspend/resume
```

Each pattern can indicate a configuration issue.

---

# Part 38 — Auto-Resume

## 38. Workload Availability

Auto-resume allows an eligible suspended warehouse to resume when workload arrives.

Monitor provisioning delay and user impact associated with resume behavior.

---

# Part 39 — Suspend/Resume Thrashing

## 39. Pattern

Consider:

```text
10:00 resume
10:02 suspend
10:03 resume
10:05 suspend
10:06 resume
```

This can create unnecessary startup activity and potentially affect cache efficiency and latency.

---

# Part 40 — Auto-Suspend Tuning

## 40. Workload-Specific

For sporadic workloads:

```text
shorter idle timeout
```

may be appropriate.

For continuously interactive workloads:

```text
longer timeout
```

may improve responsiveness.

There is no universal auto-suspend value that is optimal for every warehouse.

---

# Part 41 — Warehouse Cache

## 41. Local Compute Cache

Warehouse compute can benefit from cached data associated with the running warehouse.

Suspending a warehouse can affect this cache.

Therefore:

```text
Aggressive suspension
        |
        v
More cold starts
        |
        v
Potentially more remote reads
```

The exact impact depends on workload.

---

# Part 42 — Cache Monitoring Principle

## 42. Avoid False Conclusions

Do not interpret every slower query immediately after resume as an SQL regression.

Compare:

```text
Cold execution
Warm execution
Queue
Scan
Warehouse state
```

Chapter 40 covers Snowflake caching in detail.

---

# Part 43 — Warehouse Metering

## 43. Compute Consumption

Warehouse metering provides the credit-consumption side of monitoring.

A key historical interface is conceptually:

```sql
SNOWFLAKE.ACCOUNT_USAGE.WAREHOUSE_METERING_HISTORY
```

Validate current columns, latency, retention, and privilege requirements.

---

# Part 44 — Why Metering Matters

## 44. Performance Alone Is Incomplete

Suppose:

```text
P95 improved 50%
Credits increased 400%
```

The change may not be economically justified.

Operational monitoring should correlate:

```text
Performance
+
Cost
```

---

# Part 45 — Credits by Warehouse

## 45. Example

Conceptually:

```sql
SELECT
    warehouse_name,
    SUM(credits_used) AS credits_used
FROM SNOWFLAKE.ACCOUNT_USAGE.WAREHOUSE_METERING_HISTORY
WHERE start_time >= DATEADD(day, -7, CURRENT_TIMESTAMP())
GROUP BY warehouse_name
ORDER BY credits_used DESC;
```

Validate current fields before production use.

---

# Part 46 — Daily Credit Trend

## 46. Example

```sql
SELECT
    DATE_TRUNC('day', start_time) AS day,
    warehouse_name,
    SUM(credits_used) AS credits_used
FROM SNOWFLAKE.ACCOUNT_USAGE.WAREHOUSE_METERING_HISTORY
WHERE start_time >= DATEADD(day, -30, CURRENT_TIMESTAMP())
GROUP BY 1, 2
ORDER BY 1, 2;
```

This provides a useful warehouse-level consumption trend.

---

# Part 47 — Credit Baseline

## 47. Example

Normal:

```text
ETL_WH = 50 credits/day
```

New behavior:

```text
ETL_WH = 120 credits/day
```

Investigate:

- query growth
- runtime growth
- warehouse resize
- additional clusters
- longer active periods
- schedule changes
- retry behavior

---

# Part 48 — Idle Consumption

## 48. Important FinOps Signal

A warehouse can consume compute while providing little useful workload.

Potential pattern:

```text
Warehouse active
      |
      +---- few queries
      +---- long idle periods
      |
      v
Unnecessary credits
```

Later FinOps chapters will analyze this in more detail.

---

# Part 49 — Utilization

## 49. No Single Universal Percentage

Warehouse utilization should not be reduced to one simplistic percentage without defining what it means.

Useful evidence includes:

```text
Active duration
Query volume
Running workload
Queueing
Credits
Idle periods
```

Together they provide a more useful operational picture.

---

# Part 50 — Underutilized Warehouse

## 50. Example Pattern

```text
Warehouse = LARGE
Queries/hour = 5
Queue = 0
Execution = short
Credits = high
```

This warehouse may be oversized or unnecessarily active.

Validate workload requirements before resizing.

---

# Part 51 — Overloaded Warehouse

## 51. Example Pattern

```text
Warehouse = SMALL
Concurrent workload = high
Queue P95 = 30 sec
Execution P95 = 3 sec
```

The primary issue is likely concurrency capacity rather than slow SQL execution.

---

# Part 52 — Long-Running Queries

## 52. Monitor Outliers

Track top queries by:

```text
Elapsed time
Execution time
Bytes scanned
Spill
```

Long-running queries can monopolize resources or indicate inefficient workload behavior.

---

# Part 53 — High-Spill Queries

## 53. Warehouse Memory Pressure

Track:

```text
Bytes spilled to local storage
Bytes spilled to remote storage
```

Repeated remote spill can indicate:

- warehouse too small for the workload
- large joins
- large sorts
- large aggregations
- data skew
- excessive intermediate results

---

# Part 54 — Query Failures

## 54. Warehouse Health Includes Failures

Monitor failure rate by warehouse.

A warehouse may appear available while a large portion of its workload is failing.

---

# Part 55 — Failure Percentage

## 55. Example

```text
Total queries = 100,000
Failed        = 10,000

Failure rate = 10%
```

This is a serious workload-health signal even if compute utilization appears normal.

---

# Part 56 — Workload Attribution

## 56. Who Is Using the Warehouse?

Monitor usage by:

```text
User
Role
Query tag
Application
Team
Pipeline
```

This is critical when a warehouse is shared.

---

# Part 57 — Shared Warehouse Risk

## 57. Example

```text
Shared Warehouse
      |
      +---- BI
      +---- ETL
      +---- Ad hoc
      +---- Application
```

One workload can affect the others.

Monitoring must identify which workload caused the pressure.

---

# Part 58 — Query Tags

## 58. Recommended Practice

Production applications should use meaningful workload tags where appropriate.

For example:

```text
application=claims-api
environment=prod
team=data-platform
workload=interactive
```

Do not place sensitive values or secrets in query tags.

---

# Part 59 — Workload Isolation

## 59. Monitoring Can Reveal Isolation Needs

Suppose:

```text
ETL starts
   |
   v
Warehouse load rises
   |
   v
BI queue rises
```

This correlation may justify separate warehouses.

---

# Part 60 — Dedicated Warehouses

## 60. Benefits

Dedicated warehouses can improve:

- performance isolation
- capacity planning
- ownership
- troubleshooting
- chargeback
- resource-monitor configuration

But additional warehouses must still be governed to avoid unnecessary cost.

---

# Part 61 — Warehouse Ownership

## 61. Every Warehouse Needs an Owner

Recommended metadata:

```text
Warehouse:
Environment:
Purpose:
Application:
Owning team:
Technical owner:
Business owner:
Expected schedule:
Expected credits:
SLO:
```

Without ownership, unused warehouses often remain active indefinitely.

---

# Part 62 — Naming Standards

## 62. Example

A naming convention might communicate:

```text
Environment
Team
Workload
Purpose
```

For example:

```text
PROD_DATA_ETL_WH
PROD_BI_REPORTING_WH
DEV_ANALYTICS_WH
```

Use organizational standards rather than blindly copying this example.

---

# Part 63 — Resource Monitors

## 63. Cost Guardrails

Where applicable, Snowflake resource monitors can provide controls around warehouse credit usage.

Monitor:

```text
Assigned resource monitor
Credit quota
Current consumption
Notification thresholds
Suspend actions
```

Validate current Snowflake resource-monitor capabilities and applicability.

---

# Part 64 — Resource Monitor Is Not Performance Monitoring

## 64. Different Purpose

Resource monitors primarily provide cost-governance controls.

They do not replace:

```text
Queue monitoring
Latency monitoring
Failure monitoring
Load monitoring
```

---

# Part 65 — Baselines

## 65. Establish Normal Behavior

For each production warehouse, baseline:

```text
Queries/hour
P50 latency
P95 latency
P99 latency
Queue P95
Queue P99
Failure %
Running load
Queued load
Credits/hour
Credits/day
Active duration
```

---

# Part 66 — Baseline by Time

## 66. Workloads Are Cyclical

A warehouse may behave differently at:

```text
08:00
12:00
18:00
02:00
```

Build time-aware baselines.

---

# Part 67 — Day-of-Week Baseline

## 67. Example

```text
Monday     = heavy
Tuesday    = normal
Wednesday  = normal
Thursday   = heavy
Friday     = reporting
Weekend    = low
```

Comparing Friday reporting traffic with Sunday idle traffic is not useful.

---

# Part 68 — Seasonal Baseline

## 68. Business Cycles

Warehouse demand may change during:

- month-end
- quarter-end
- year-end
- billing cycles
- enrollment periods
- campaign events
- scheduled backfills

Monitoring should understand these expected peaks.

---

# Part 69 — Capacity Monitoring

## 69. Early Warning

Capacity pressure may appear as:

```text
Queue P95 ↑
Peak concurrency ↑
Query volume ↑
Spill ↑
Credits ↑
```

before users report a severe outage.

---

# Part 70 — Headroom

## 70. Production Principle

Do not operate critical workloads continuously at their capacity limit.

Maintain headroom for:

- bursts
- retries
- data growth
- failover scenarios
- deployments
- unexpected workload

---

# Part 71 — Capacity Trend

## 71. Example

Month 1:

```text
Peak queue P95 = 1 sec
```

Month 2:

```text
Peak queue P95 = 3 sec
```

Month 3:

```text
Peak queue P95 = 8 sec
```

This is a capacity trend even if no formal incident has occurred yet.

---

# Part 72 — Data Growth Effect

## 72. Same Queries, More Work

Suppose:

```text
Query count = unchanged
Data volume = +50%
Execution P95 = +40%
Credits = +35%
```

The workload may require tuning or capacity adjustment even though query volume did not increase.

---

# Part 73 — Query Growth Effect

## 73. Same Data, More Requests

Suppose:

```text
Data size = unchanged
Queries/hour = +300%
Queue P95 = +500%
```

This points toward concurrency pressure.

---

# Part 74 — Application Retry Effect

## 74. Feedback Loop

```text
Latency
  |
  v
Application retry
  |
  v
More queries
  |
  v
More warehouse pressure
  |
  v
More latency
```

Warehouse monitoring should detect sudden query-volume spikes.

---

# Part 75 — Dashboard Design

## 75. Warehouse Overview

A production dashboard should include:

```text
Warehouse state
Warehouse size
Query volume
Running load
Queued load
P50 latency
P95 latency
P99 latency
Queue P95
Failure %
Credits
```

---

# Part 76 — Multi-Cluster Dashboard

## 76. Additional Metrics

For multi-cluster warehouses add:

```text
Configured min clusters
Configured max clusters
Scaling policy
Cluster scaling behavior
Queueing at max capacity
Credits
```

---

# Part 77 — Workload Dashboard

## 77. Attribution

Break warehouse workload down by:

```text
Application
Query tag
User
Role
Pipeline
```

This makes incident response faster.

---

# Part 78 — Cost Dashboard

## 78. Warehouse-Level Cost View

Track:

```text
Credits/hour
Credits/day
Credits/week
Credits/month
Change %
Active time
Query volume
```

This helps identify unexplained consumption growth.

---

# Part 79 — Performance/Cost Dashboard

## 79. Combine Them

Useful combined view:

```text
Warehouse
   |
   +---- P95 latency
   +---- Queue P95
   +---- Queries/hour
   +---- Credits/hour
```

This prevents optimizing performance without considering cost.

---

# Part 80 — Alerting Strategy

## 80. Alert on Symptoms That Require Action

Useful alert candidates include:

```text
Queue P95 above SLO
Failure rate above baseline
Warehouse unexpectedly active
Warehouse unexpectedly suspended
Credit consumption spike
Warehouse reaches scaling ceiling
Query volume anomaly
Remote spill anomaly
Latency P95/P99 regression
```

---

# Part 81 — Static Thresholds

## 81. Useful but Limited

Example:

```text
Queue P95 > 10 seconds
```

Static thresholds are easy to understand.

But the correct value depends on workload.

---

# Part 82 — Baseline Alerts

## 82. Better for Variable Workloads

Example:

```text
Current credits/hour > 2× normal for this warehouse and hour
```

This may detect anomalies that static thresholds miss.

---

# Part 83 — SLO-Based Alerts

## 83. Best for User-Facing Workloads

Suppose the application SLO is:

```text
P95 query latency < 5 seconds
```

Alert directly against the service objective where possible.

---

# Part 84 — Avoid Alert Noise

## 84. One Query Is Not Always an Incident

Avoid alerts such as:

```text
Any query > 30 seconds
```

unless the workload specifically requires it.

A legitimate batch query may run for hours.

Alerts should understand workload purpose.

---

# Part 85 — Warning and Critical

## 85. Example

```text
Queue P95

Warning  > 5 sec
Critical > 15 sec
```

Thresholds must be derived from actual workload SLOs and baselines.

---

# Part 86 — Monitoring Cadence

## 86. Real-Time / Near Real-Time

Use appropriate fresh telemetry for:

- active incidents
- user-facing latency
- queueing
- failures

## 87. Hourly

Useful for:

- workload trends
- queue trends
- credit consumption

## 88. Daily

Useful for:

- cost review
- utilization
- capacity trends
- anomalies

## 89. Weekly

Useful for:

- warehouse sizing
- workload isolation
- optimization candidates

## 90. Monthly

Useful for:

- FinOps
- ownership review
- unused warehouses
- capacity planning
- governance

---

# Part 87 — Active Incident Workflow

## 91. Step 1 — Confirm Impact

Capture:

```text
Warehouse
Application
Start
Timezone
User impact
```

## 92. Step 2 — Check Query Volume

Did workload increase?

## 93. Step 3 — Check Queue

Did waiting increase?

## 94. Step 4 — Check Execution

Did queries themselves become slower?

## 95. Step 5 — Check Load

Was warehouse capacity saturated?

## 96. Step 6 — Check Scaling

For multi-cluster warehouses:

```text
Did additional clusters start?
Did warehouse hit MAX_CLUSTER_COUNT?
```

## 97. Step 7 — Check Spill

Did memory pressure increase?

## 98. Step 8 — Check Failures

Did error rate increase?

## 99. Step 9 — Identify Workload

Which application, user, role, or query tag caused the change?

## 100. Step 10 — Check Changes

Look for:

```text
Deployment
ETL overlap
Warehouse resize
Configuration change
Data growth
Retry storm
```

---

# Part 88 — Queue Troubleshooting

## 101. Pattern

```text
Queue high
   |
   v
Overload queue?
 /       \
Yes       No
 |         |
 v         v
Concurrency   Provisioning/
analysis      repair analysis
```

---

# Part 89 — Overload Troubleshooting

## 102. Investigate

If overload queueing is high:

```text
Check query volume
Check concurrency
Check warehouse size
Check multi-cluster configuration
Check workload overlap
Check query duration
Check retries
```

---

# Part 90 — Provisioning Troubleshooting

## 103. Investigate

If provisioning queueing is elevated:

```text
Check warehouse resume behavior
Check scale-out behavior
Check recent suspend/resume
Check workload burst timing
```

Do not treat provisioning delay as SQL execution latency.

---

# Part 91 — Slow Queries Without Queue

## 104. Pattern

```text
Queue normal
Execution high
```

Investigate:

- Query Profile
- pruning
- spill
- joins
- sorts
- aggregations
- data growth
- warehouse sizing

---

# Part 92 — High Queue, Fast Execution

## 105. Pattern

```text
Queue = 25 sec
Execution = 2 sec
```

Optimizing the SQL from 2 seconds to 1 second may not materially solve the incident.

Focus first on concurrency and capacity.

---

# Part 93 — High Credits, Normal Workload

## 106. Pattern

```text
Query volume = normal
Performance = normal
Credits = +200%
```

Investigate:

```text
Warehouse resize
Longer active duration
Additional clusters
Auto-suspend changes
New warehouse
Schedule changes
```

---

# Part 94 — High Credits, High Workload

## 107. Pattern

```text
Query volume = +150%
Credits = +140%
```

The increase may be workload-driven.

Determine whether it is expected business growth.

---

# Part 95 — Low Query Volume, High Credits

## 108. Pattern

```text
Queries = low
Credits = high
```

Investigate:

- oversized warehouse
- idle active periods
- auto-suspend configuration
- long-running queries
- background workloads
- multi-cluster behavior

---

# Part 96 — Frequent Resume Latency

## 109. Pattern

```text
Warehouse repeatedly suspends
        |
        v
New query arrives
        |
        v
Resume/provision
        |
        v
User latency
```

Consider whether the current auto-suspend setting fits the workload.

---

# Part 97 — Cache-Related Performance Pattern

## 110. Pattern

```text
First query after resume = slower
Repeated query          = faster
Queue                   = normal
```

Investigate warehouse-cache effects before declaring a SQL regression.

---

# Part 98 — Monitoring Evidence Template

## 111. Capture

```text
Incident:
Environment:
Account:
Region:

Warehouse:
Warehouse size:
Warehouse type:
Scaling policy:
Min clusters:
Max clusters:
Auto-suspend:
Auto-resume:
Resource monitor:

Incident start:
Incident end:
Timezone:

Queries/hour baseline:
Queries/hour incident:

Latency P50 baseline:
Latency P50 incident:

Latency P95 baseline:
Latency P95 incident:

Latency P99 baseline:
Latency P99 incident:

Queue P95 baseline:
Queue P95 incident:

Running load baseline:
Running load incident:

Queued load baseline:
Queued load incident:

Failure % baseline:
Failure % incident:

Local spill:
Remote spill:

Credits/hour baseline:
Credits/hour incident:

Top user:
Top role:
Top query tag:
Top query IDs:

Recent deployment:
Recent warehouse change:
Recent workload change:
Data growth:

Root cause:
Mitigation:
Validation:
Permanent remediation:
```

---

# Part 99 — Warehouse Health Decision Tree

## 112. Decision

```text
Warehouse issue
      |
      v
User impact?
  /       \
Yes        No
 |          |
 v          v
Queue high? Cost anomaly?
 /    \       /      \
Yes    No    Yes      No
 |      |     |        |
 v      v     v        v
Capacity Execution  Metering  Trend/
analysis analysis   analysis  baseline
```

---

# Part 100 — Capacity Decision Tree

## 113. Decision

```text
Queue increasing
      |
      v
Query volume increased?
 /                \
Yes                No
 |                  |
 v                  v
Concurrency      Query duration
pressure         increased?
 |               /       \
 v             Yes        No
Scale out/       |          |
isolate          v          v
              Profile    Config/
              queries    capacity
```

---

# Part 101 — Cost Decision Tree

## 114. Decision

```text
Credits increased
      |
      v
Query volume increased?
 /                \
Yes                No
 |                  |
 v                  v
Expected growth?   Warehouse active longer?
 /       \          /              \
Yes       No       Yes              No
 |         |        |                |
 v         v        v                v
Validate   Find     Auto-suspend/   Size/
efficiency source  schedule         clusters
```

---

# Part 102 — Daily Warehouse Review

## 115. Review

For critical production warehouses:

```text
□ Availability
□ Query volume
□ P95/P99 latency
□ Queue P95/P99
□ Failure rate
□ Spill
□ Credit anomaly
□ Scaling anomaly
```

---

# Part 103 — Weekly Warehouse Review

## 116. Review

```text
□ Peak concurrency
□ Capacity headroom
□ Workload growth
□ Data growth
□ Warehouse sizing
□ Workload isolation
□ Suspend/resume behavior
□ Cost trend
```

---

# Part 104 — Monthly Warehouse Review

## 117. Review

```text
□ Ownership
□ Purpose
□ Active usage
□ Sizing
□ Resource monitor
□ Cost
□ Unused warehouses
□ Configuration drift
□ Capacity forecast
```

---

# Part 105 — Configuration Drift

## 118. Why It Matters

A warehouse may begin with:

```text
AUTO_SUSPEND = 60
SIZE = MEDIUM
```

and later become:

```text
AUTO_SUSPEND = 3600
SIZE = XLARGE
```

without an operational review.

Configuration monitoring should detect unexpected changes.

---

# Part 106 — Change Management

## 119. Record Changes

For production warehouses, record:

```text
Who changed it?
What changed?
When?
Why?
Expected impact?
Rollback?
```

This makes incident correlation significantly easier.

---

# Part 107 — Warehouse Monitoring Architecture

## 120. Concept

```text
Snowflake
   |
   +---- Query History
   |
   +---- Warehouse Load History
   |
   +---- Warehouse Metering History
   |
   +---- Warehouse Metadata
   |
   v
Monitoring Pipeline
   |
   +---- Dashboard
   +---- Alerts
   +---- Capacity Reports
   +---- FinOps Reports
   +---- Incident Evidence
```

---

# Part 108 — Telemetry Freshness

## 121. Critical Consideration

Different Snowflake metadata interfaces can have different latency characteristics.

Therefore:

```text
Incident monitoring
        ≠
Historical reporting
```

Use the interface appropriate to the required freshness.

Do not assume ACCOUNT_USAGE is always appropriate for immediate incident detection.

---

# Part 109 — Monitoring Permissions

## 122. Least Privilege

Monitoring roles should receive only the privileges required to inspect operational telemetry.

Avoid granting broad administrative privileges merely to build dashboards.

---

# Part 110 — Monitoring Security

## 123. Sensitive Data

Monitoring systems may expose:

- query text
- user names
- object names
- errors
- query tags
- workload patterns

Protect monitoring data appropriately.

---

# Part 111 — Query Text Handling

## 124. Do Not Export Blindly

Query text may contain sensitive literals.

If telemetry is exported externally:

```text
Review
Mask
Restrict
Retain appropriately
```

---

# Part 112 — Monitoring Retention

## 125. Define Requirements

Operational teams may need:

```text
Recent incident data
30-day trends
90-day capacity trends
12-month FinOps trends
```

Use supported Snowflake retention and organizational monitoring storage appropriately.

---

# Part 113 — Monitoring SLO

## 126. Monitor the Monitor

Define expectations such as:

```text
Dashboard freshness
Alert delivery latency
Telemetry completeness
Pipeline success
```

A broken monitoring pipeline can make a healthy warehouse appear silent.

---

# Part 114 — Missing Data

## 127. Important

No metrics do not necessarily mean:

```text
No workload
```

They may mean:

```text
Monitoring failure
Permission issue
Telemetry delay
Query failure
```

Validate monitoring health.

---

# Part 115 — Hands-On Lab

## 128. Objective

Build and observe a controlled Snowflake warehouse workload.

Use a non-production environment.

---

# Part 116 — Create Lab Warehouse

## 129. Warehouse

Use a small approved warehouse size appropriate to your environment.

Conceptually:

```sql
CREATE OR REPLACE WAREHOUSE warehouse_monitor_lab_wh
    WAREHOUSE_SIZE = 'XSMALL'
    AUTO_SUSPEND = 60
    AUTO_RESUME = TRUE
    INITIALLY_SUSPENDED = TRUE;
```

Validate exact current syntax before running.

---

# Part 117 — Create Lab Database

## 130. Database

```sql
CREATE OR REPLACE DATABASE warehouse_monitor_lab;
```

---

# Part 118 — Create Schema

## 131. Schema

```sql
CREATE OR REPLACE SCHEMA warehouse_monitor_lab.demo;
```

---

# Part 119 — Create Synthetic Table

## 132. Table

```sql
CREATE OR REPLACE TABLE warehouse_monitor_lab.demo.events (
    event_id NUMBER,
    customer_id NUMBER,
    event_date DATE,
    event_type STRING,
    amount NUMBER(12,2)
);
```

---

# Part 120 — Load Synthetic Data

## 133. Data

```sql
INSERT INTO warehouse_monitor_lab.demo.events
SELECT
    seq,
    MOD(seq, 100000),
    DATEADD(day, -MOD(seq, 365), DATE '2026-10-01'),
    CASE MOD(seq, 4)
        WHEN 0 THEN 'READ'
        WHEN 1 THEN 'WRITE'
        WHEN 2 THEN 'UPDATE'
        ELSE 'DELETE'
    END,
    MOD(seq, 100000) / 100.0
FROM (
    SELECT SEQ4() AS seq
    FROM TABLE(GENERATOR(ROWCOUNT => 5000000))
);
```

All data is synthetic.

Reduce the row count if necessary for lab cost control.

---

# Part 121 — Tag the Workload

## 134. Query Tag

Using current supported syntax, apply a query tag such as:

```text
tutorial=chapter48;workload=warehouse-monitoring
```

Do not place sensitive information in query tags.

---

# Part 122 — Baseline Query

## 135. Query

```sql
SELECT
    event_type,
    COUNT(*) AS event_count,
    SUM(amount) AS total_amount
FROM warehouse_monitor_lab.demo.events
GROUP BY event_type;
```

Run the query several times.

Record query IDs.

---

# Part 123 — Selective Query

## 136. Query

```sql
SELECT *
FROM warehouse_monitor_lab.demo.events
WHERE customer_id = 50000;
```

Record:

```text
Elapsed
Execution
Queue
Bytes scanned
```

---

# Part 124 — Analytical Query

## 137. Query

```sql
SELECT
    customer_id,
    SUM(amount) AS total_amount,
    COUNT(*) AS event_count
FROM warehouse_monitor_lab.demo.events
GROUP BY customer_id
ORDER BY total_amount DESC;
```

Record the query ID.

---

# Part 125 — Window Query

## 138. Query

```sql
SELECT
    customer_id,
    event_date,
    amount,
    ROW_NUMBER() OVER (
        PARTITION BY customer_id
        ORDER BY event_date DESC
    ) AS event_rank
FROM warehouse_monitor_lab.demo.events;
```

Observe execution behavior.

---

# Part 126 — Query History Exercise

## 139. Retrieve

Find the lab queries and capture:

```text
Query ID
Warehouse
Elapsed
Execution
Queue
Scan
Spill
Rows produced
Status
```

---

# Part 127 — Warehouse Load Exercise

## 140. Retrieve

Using the current warehouse-load interface, analyze the lab warehouse.

Capture:

```text
Running workload
Queued workload
Time window
```

---

# Part 128 — Metering Exercise

## 141. Retrieve

Using the current warehouse-metering interface, capture the lab warehouse's credit consumption.

Remember that telemetry latency may mean data is not immediately visible.

---

# Part 129 — Suspend Exercise

## 142. Suspend

After completing the initial workload:

```sql
ALTER WAREHOUSE warehouse_monitor_lab_wh SUSPEND;
```

Confirm the warehouse state using a supported metadata interface.

---

# Part 130 — Resume Exercise

## 143. Resume

Run another query with auto-resume enabled.

Observe:

```text
Resume behavior
Provisioning delay
Query elapsed time
```

Compare with a warm execution.

---

# Part 131 — Cache Exercise

## 144. Compare

Record:

| Execution | State | Elapsed | Execution | Queue |
|---|---|---:|---:|---:|
| First after resume | Cold | | | |
| Second | Warm | | | |
| Third | Warm | | | |

Do not confuse persisted-result reuse with warehouse-cache effects.

Design the test so the cache layer being investigated is clear.

---

# Part 132 — Controlled Concurrency Exercise

## 145. Optional

If permitted, run a small bounded set of concurrent analytical queries.

Do not perform uncontrolled load testing.

Capture:

```text
Query count
Running load
Queue time
Elapsed time
```

---

# Part 133 — Resize Exercise

## 146. Optional

If permitted, resize only the dedicated lab warehouse to the next approved size.

Compare:

```text
Execution P95
Queue
Spill
Credits
```

Then restore the original size.

---

# Part 134 — Results

## 147. Record

| Metric | Baseline | Test |
|---|---:|---:|
| Queries | | |
| P50 elapsed | | |
| P95 elapsed | | |
| Queue P95 | | |
| Running load | | |
| Queued load | | |
| Local spill | | |
| Remote spill | | |
| Credits | | |

---

# Part 135 — Findings

## 148. Document

```text
Warehouse:
Size:
Auto-suspend:
Auto-resume:

Observed workload:
Observed queue:
Observed execution:
Observed spill:
Observed credits:

Cold behavior:
Warm behavior:

Capacity issue:
Cost issue:
Configuration issue:

Recommended action:
Evidence:
```

---

# Part 136 — Cleanup

## 149. Database

```sql
DROP DATABASE IF EXISTS warehouse_monitor_lab;
```

## 150. Warehouse

```sql
DROP WAREHOUSE IF EXISTS warehouse_monitor_lab_wh;
```

Restore any session settings changed during the lab.

---

# Part 137 — Production Warehouse Checklist

## 151. Inventory

```text
□ Warehouse documented
□ Owner assigned
□ Purpose documented
□ Environment documented
```

## 152. Configuration

```text
□ Size reviewed
□ Auto-suspend reviewed
□ Auto-resume reviewed
□ Scaling policy reviewed
□ Min/max clusters reviewed
□ Resource monitor reviewed
```

## 153. Performance

```text
□ Query volume monitored
□ P50 monitored
□ P95 monitored
□ P99 monitored
□ Queue monitored
□ Spill monitored
□ Failures monitored
```

## 154. Capacity

```text
□ Peak workload known
□ Concurrency known
□ Headroom reviewed
□ Growth trend reviewed
□ Scaling ceiling reviewed
```

## 155. Cost

```text
□ Credits/hour monitored
□ Credits/day monitored
□ Idle behavior reviewed
□ Cost anomalies alerted
```

## 156. Operations

```text
□ Dashboard exists
□ Alerts exist
□ Runbook exists
□ Monitoring permissions reviewed
□ Monitoring freshness understood
```

---

# Part 138 — Warehouse Monitoring Runbook

## 157. User Reports Slowness

Check:

```text
1. Warehouse
2. Time window
3. Query volume
4. Queue
5. Execution
6. Load
7. Spill
8. Failures
9. Scaling
10. Workload source
```

---

# Part 139 — Queueing Runbook

## 158. If Queue Is High

```text
Check queue type
       |
       v
Overload?
   |
   +---- Query volume
   +---- Concurrency
   +---- Warehouse size
   +---- Multi-cluster
   +---- Workload overlap
   +---- Retry storm
```

---

# Part 140 — Credit Spike Runbook

## 159. If Credits Spike

```text
Credit spike
    |
    +---- Query volume changed?
    +---- Warehouse size changed?
    +---- Active time changed?
    +---- Cluster count changed?
    +---- Auto-suspend changed?
    +---- New workload?
    +---- Retry behavior?
```

---

# Part 141 — Unexpected Warehouse State Runbook

## 160. If Warehouse Is Suspended Unexpectedly

Check:

```text
Auto-suspend
Manual suspend
Resource-monitor action
Workload schedule
Recent configuration changes
```

Validate current Snowflake event/history sources for determining exact cause.

---

# Part 142 — Production Monitoring Matrix

## 161. Matrix

| Signal | Indicates | Primary Investigation |
|---|---|---|
| Queue ↑ | Concurrency/capacity | Load, volume, scaling |
| Execution ↑ | Query execution regression | Query Profile |
| Spill ↑ | Memory/intermediate data pressure | SQL, warehouse size |
| Query count ↑ | Workload growth/burst | Application/query tag |
| Failure % ↑ | Workload error | Error/query source |
| Credits ↑ | Compute consumption growth | Metering/config/workload |
| Resume delay ↑ | Provisioning/cold start | Suspend/resume |
| Queue at max clusters | Scale-out ceiling | Capacity/configuration |

---

# Part 143 — Operational Principles

## 162. Principle 1

Warehouse state alone does not define health.

## 163. Principle 2

Monitor workload and warehouse together.

## 164. Principle 3

Separate queue time from execution time.

## 165. Principle 4

Separate overload, provisioning, and repair queueing.

## 166. Principle 5

Use P95 and P99 for user-facing workloads.

## 167. Principle 6

Query volume is not the same as concurrency.

## 168. Principle 7

Correlate Query History with Warehouse Load History.

## 169. Principle 8

Correlate performance with Warehouse Metering History.

## 170. Principle 9

Monitor multi-cluster scaling behavior.

## 171. Principle 10

Monitor scaling ceilings.

## 172. Principle 11

Review auto-suspend against workload behavior.

## 173. Principle 12

Understand cold versus warm execution.

## 174. Principle 13

Track failures, not only successful queries.

## 175. Principle 14

Attribute shared-warehouse workload.

## 176. Principle 15

Use query tags where appropriate.

## 177. Principle 16

Maintain time-aware baselines.

## 178. Principle 17

Monitor capacity trends before incidents occur.

## 179. Principle 18

Maintain production headroom.

## 180. Principle 19

Protect monitoring telemetry.

## 181. Principle 20

Validate monitoring freshness.

---

# Part 144 — DBRE/SRE Monitoring Flow

## 182. Production Flow

```text
Warehouse telemetry
       |
       v
State/configuration
       |
       v
Query volume
       |
       v
Latency
       |
       v
Queue
       |
       v
Warehouse load
       |
       v
Concurrency/scaling
       |
       v
Spill/failures
       |
       v
Credits
       |
       v
Workload attribution
       |
       v
Compare baseline
       |
       v
Capacity + cost decision
```

---

# Acceptance Criteria

The chapter is complete when you can:

- explain why warehouse state alone is insufficient
- inventory production warehouses
- inspect warehouse configuration
- monitor warehouse size
- distinguish size from utilization
- measure query throughput
- establish throughput baselines
- monitor query latency
- calculate P50/P95/P99
- distinguish execution from elapsed time
- identify queueing
- identify overload queueing
- identify provisioning queueing
- distinguish repair queueing
- calculate queue metrics
- understand queue ratios
- monitor queue percentiles
- use Warehouse Load History
- analyze running workload
- analyze queued workload
- build load timelines
- distinguish throughput from concurrency
- understand query overlap
- analyze concurrency
- detect workload bursts
- monitor multi-cluster warehouses
- monitor scale-out behavior
- identify maximum-cluster ceilings
- include scaling policy in diagnosis
- monitor warehouse resizing
- validate resize impact
- understand why resize does not fix every problem
- monitor auto-suspend
- detect poor auto-suspend behavior
- monitor auto-resume
- detect suspend/resume thrashing
- tune suspension according to workload
- understand warehouse-cache implications
- distinguish cold and warm execution
- use Warehouse Metering History
- monitor warehouse credits
- trend daily credit consumption
- establish credit baselines
- identify idle consumption
- understand warehouse utilization
- identify underutilized warehouses
- identify overloaded warehouses
- monitor long-running queries
- monitor spill
- monitor query failures
- calculate failure rates
- attribute workload to users and applications
- identify shared-warehouse interference
- use query tags
- identify workload-isolation candidates
- understand dedicated warehouse benefits
- assign warehouse ownership
- apply naming standards
- understand resource-monitor purpose
- distinguish cost guardrails from performance monitoring
- establish warehouse baselines
- create time-aware baselines
- create day-of-week baselines
- account for seasonal workload
- monitor capacity
- maintain headroom
- identify capacity trends
- recognize data-growth effects
- recognize query-growth effects
- detect retry amplification
- design warehouse dashboards
- design multi-cluster dashboards
- design workload dashboards
- design cost dashboards
- correlate performance and cost
- define actionable alerts
- use static thresholds appropriately
- use baseline alerts
- use SLO-based alerts
- avoid alert noise
- define warning and critical thresholds
- choose monitoring cadence
- execute an active-incident workflow
- troubleshoot overload queueing
- troubleshoot provisioning queueing
- diagnose slow execution without queueing
- diagnose high queue with fast execution
- investigate credit anomalies
- investigate frequent resume latency
- identify cache-related patterns
- capture monitoring evidence
- use warehouse health decision trees
- use capacity decision trees
- use cost decision trees
- perform daily warehouse reviews
- perform weekly warehouse reviews
- perform monthly warehouse reviews
- detect configuration drift
- apply warehouse change management
- design a monitoring architecture
- understand telemetry freshness
- apply least-privilege monitoring
- protect monitoring data
- protect query text
- plan monitoring retention
- define monitoring SLOs
- detect missing telemetry
- complete the warehouse monitoring lab
- observe warehouse load
- observe metering
- test suspend/resume behavior
- compare cold and warm executions
- run bounded concurrency tests
- validate resize behavior safely
- clean up lab resources
- use the production warehouse checklist
- follow the DBRE/SRE monitoring flow

---

## Key Takeaways

A Snowflake warehouse should be monitored as a complete compute service rather than simply as an object that is running or suspended.

The core model is:

```text
Warehouse
   |
   +---- State
   +---- Configuration
   +---- Workload
   +---- Latency
   +---- Queue
   +---- Load
   +---- Scaling
   +---- Spill
   +---- Failures
   +---- Credits
   |
   v
Operational health
```

For performance:

```text
User latency
     |
     v
Queue or execution?
   /             \
Queue             Execution
 |                   |
 v                   v
Concurrency       Query Profile
Capacity          Scan/spill
Scaling           SQL design
```

For concurrency:

```text
Query volume
     +
Warehouse load
     +
Queue P95/P99
     +
Scaling behavior
     |
     v
Capacity decision
```

For cost:

```text
Warehouse activity
      +
Warehouse size
      +
Cluster count
      +
Active duration
      |
      v
Credit consumption
```

For production operations:

```text
Query History
      +
Warehouse Load History
      +
Warehouse Metering History
      +
Warehouse configuration
      |
      v
Complete warehouse evidence
```

The most important operational principle is:

> Monitor the workload, the warehouse, and the cost together. Optimizing only one of these dimensions can create a problem in another.

A production warehouse monitoring system should answer:

```text
Is the warehouse available?
Is it correctly configured?
What workload is using it?
Are users queueing?
Are queries executing slowly?
Is the warehouse reaching capacity?
Is multi-cluster scaling working?
Is the warehouse oversized?
Is it consuming unexpected credits?
Which workload caused the change?
How does current behavior compare with baseline?
Do we have enough capacity headroom?
```

The next chapter is **Chapter 49 — Storage & Data Growth Monitoring**.
