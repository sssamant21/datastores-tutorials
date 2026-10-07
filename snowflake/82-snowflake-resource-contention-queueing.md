# Chapter 82 --- Snowflake Resource Contention & Queueing

## 82.1 Overview

Snowflake performance incidents frequently appear as:

``` text
Queries are slow
Application requests are timing out
Dashboard refresh is delayed
ETL takes longer than normal
Queries are waiting
Performance is inconsistent
Warehouse looks overloaded
```

The critical question is:

``` text
Where is the query spending its time?
```

A query can be slow because it is:

``` text
Waiting for warehouse capacity
Waiting for warehouse provisioning
Waiting on a transaction
Actually executing slowly
Waiting outside Snowflake
```

**Primary rule: Never treat total query duration as warehouse execution
time.**

## 82.2 Resource Contention

Resource contention occurs when concurrent workloads compete for
available compute capacity.

``` text
                +--> Query A
                |
Application --->+--> Query B
                |
                +--> Query C
                |
                +--> Query D
                |
                +--> Query E
                       |
                       v
                   WAREHOUSE
                       |
                       v
                 Limited capacity
```

When concurrency exceeds available capacity, queries may queue.

## 82.3 Queueing Is Not Execution

``` text
Total elapsed:       40 sec
Execution:            5 sec
Queue:               34 sec
```

The SQL did not require 40 seconds of execution. Most of the delay
occurred before execution.

## 82.4 Critical Timing Signals

Useful query-history signals include:

``` text
TOTAL_ELAPSED_TIME
EXECUTION_TIME
QUEUED_OVERLOAD_TIME
QUEUED_PROVISIONING_TIME
QUEUED_REPAIR_TIME
TRANSACTION_BLOCKED_TIME
```

Use the fields available in the relevant Snowflake query-history
interface.

## 82.5 Timing Model

``` text
TOTAL ELAPSED
    |
    +--> Compilation
    |
    +--> Queueing
    |      |
    |      +--> Overload
    |      +--> Provisioning
    |      +--> Repair
    |
    +--> Transaction blocking
    |
    +--> Execution
```

## 82.6 Query History

``` sql
SELECT
    QUERY_ID,
    USER_NAME,
    ROLE_NAME,
    WAREHOUSE_NAME,
    QUERY_TYPE,
    EXECUTION_STATUS,
    TOTAL_ELAPSED_TIME,
    EXECUTION_TIME,
    QUEUED_OVERLOAD_TIME,
    QUEUED_PROVISIONING_TIME,
    QUEUED_REPAIR_TIME,
    TRANSACTION_BLOCKED_TIME,
    START_TIME,
    END_TIME
FROM SNOWFLAKE.ACCOUNT_USAGE.QUERY_HISTORY
WHERE START_TIME >= DATEADD('hour', -2, CURRENT_TIMESTAMP())
ORDER BY START_TIME DESC;
```

## 82.7 Queueing Example

``` text
TOTAL_ELAPSED_TIME:        52,000 ms
EXECUTION_TIME:             6,000 ms
QUEUED_OVERLOAD_TIME:      45,000 ms
```

Primary direction: warehouse concurrency/resource contention.

## 82.8 Execution Example

``` text
TOTAL_ELAPSED_TIME:        52,000 ms
EXECUTION_TIME:            49,000 ms
QUEUED_OVERLOAD_TIME:           0 ms
```

Primary direction: Query Profile, scan, join, aggregation, spill,
pruning, or warehouse execution capacity.

## 82.9 Transaction Example

``` text
TOTAL_ELAPSED_TIME:        52,000 ms
EXECUTION_TIME:             3,000 ms
QUEUED_OVERLOAD_TIME:           0 ms
TRANSACTION_BLOCKED_TIME:  48,000 ms
```

Primary direction: transaction blocking, not compute capacity.

## 82.10 Provisioning Example

``` text
TOTAL_ELAPSED_TIME:        20,000 ms
EXECUTION_TIME:             4,000 ms
QUEUED_PROVISIONING_TIME:  15,000 ms
```

Investigate warehouse startup, resize, or provisioning behavior.

## 82.11 Queue Percentage

``` text
Queue % =
QUEUED_OVERLOAD_TIME
--------------------
TOTAL_ELAPSED_TIME
```

## 82.12 Queue Percentage SQL

``` sql
SELECT
    QUERY_ID,
    WAREHOUSE_NAME,
    TOTAL_ELAPSED_TIME,
    QUEUED_OVERLOAD_TIME,
    ROUND(
        QUEUED_OVERLOAD_TIME * 100.0 /
        NULLIF(TOTAL_ELAPSED_TIME, 0),
        2
    ) AS QUEUE_PCT
FROM SNOWFLAKE.ACCOUNT_USAGE.QUERY_HISTORY
WHERE START_TIME >= DATEADD('hour', -4, CURRENT_TIMESTAMP())
ORDER BY QUEUE_PCT DESC;
```

## 82.13 Find Highly Queued Queries

``` sql
SELECT
    QUERY_ID,
    USER_NAME,
    WAREHOUSE_NAME,
    QUERY_TYPE,
    TOTAL_ELAPSED_TIME / 1000 AS TOTAL_SECONDS,
    EXECUTION_TIME / 1000 AS EXECUTION_SECONDS,
    QUEUED_OVERLOAD_TIME / 1000 AS QUEUED_SECONDS,
    START_TIME
FROM SNOWFLAKE.ACCOUNT_USAGE.QUERY_HISTORY
WHERE START_TIME >= DATEADD('hour', -4, CURRENT_TIMESTAMP())
  AND QUEUED_OVERLOAD_TIME > 0
ORDER BY QUEUED_OVERLOAD_TIME DESC;
```

## 82.14 Warehouse State

``` sql
SHOW WAREHOUSES;
```

Capture warehouse, state, size, min/max clusters, scaling policy, auto
suspend/resume, and resource monitor where applicable.

## 82.15 Why Queries Queue

Common causes:

``` text
Too many concurrent queries
Long-running queries
Heavy ETL overlap
BI/dashboard burst
Application burst
Retry storm
Ad-hoc workload
Insufficient warehouse capacity
Single-cluster concurrency limitation
Poor workload isolation
```

## 82.16 Concurrency

Concurrency is not simply query count.

Ten lightweight queries may be harmless. Ten large joins, aggregations,
or data transformations may create significant resource pressure.

## 82.17 Query Mix

Determine:

``` text
How many queries?
What query types?
How much data?
How expensive are they?
Which workload generated them?
```

## 82.18 Workload Attribution

Identify application, service, pipeline, user, role, warehouse, and
query tag.

## 82.19 Query Tags

``` sql
ALTER SESSION SET QUERY_TAG =
'env=prod;service=patient360;workload=api';
```

ETL:

``` sql
ALTER SESSION SET QUERY_TAG =
'env=prod;service=empi;workload=etl';
```

## 82.20 Shared Warehouse Risk

``` text
                  SHARED_WH
                     |
       +-------------+-------------+
       |             |             |
       v             v             v
 Patient360         ETL            BI
    API             Jobs        Dashboards
```

A workload spike in one area can affect the others.

## 82.21 Noisy Neighbor

If API queries normally take two seconds but begin queueing when a large
ETL workload starts, the API SQL may be unchanged. The problem can be
shared compute contention.

## 82.22 Workload Isolation

``` text
APP_WH
  |
  +--> Patient360

ETL_WH
  |
  +--> ETL

BI_WH
  |
  +--> BI
```

## 82.23 Why Isolation Matters

Workload isolation improves performance predictability, blast-radius
control, cost attribution, capacity planning, incident diagnosis, and
SLA management.

## 82.24 Isolation Is Not Free

Additional warehouses can increase cost if poorly managed.

Use auto suspend/resume, right sizing, monitoring, resource monitors,
and cost attribution.

## 82.25 Scale Up vs Scale Out

Scale up:

``` text
Larger warehouse
      |
      v
More compute per cluster
```

Scale out:

``` text
Additional clusters
      |
      v
More concurrency capacity
```

## 82.26 When Scale Up Helps

Scale up when execution itself is constrained by available compute.

Example:

``` text
Execution time high
Queue low
Query benefits from more compute
```

## 82.27 When Scale Out Helps

Scale out can help when many concurrent queries cause high queueing
while individual execution remains acceptable, for workloads where
multi-cluster scaling is appropriate.

## 82.28 Wrong Scale-Up Example

``` text
Query runtime: 45 sec
Execution:       4 sec
Queue:          40 sec
```

Moving from Small to Medium may not be the best first response to a
concurrency problem.

## 82.29 Wrong Scale-Out Example

``` text
One query
Execution: 300 sec
Queue:        0 sec
```

Adding clusters does not inherently make that single query faster.

## 82.30 Multi-Cluster Warehouse

``` text
             MULTI-CLUSTER WH
                    |
       +------------+------------+
       |            |            |
       v            v            v
   Cluster 1    Cluster 2    Cluster 3
```

## 82.31 Min and Max Clusters

Example:

``` text
MIN_CLUSTER_COUNT = 1
MAX_CLUSTER_COUNT = 4
```

The minimum controls baseline cluster availability; the maximum limits
scale-out.

## 82.32 Scaling Policy

Evaluate scaling policy together with SLA, concurrency, queue tolerance,
cost, and workload pattern.

## 82.33 Standard vs Economy

Snowflake supports scaling-policy choices intended to balance
responsiveness and credit usage.

For latency-sensitive production applications, evaluate the policy
against actual queue-time and cost requirements rather than selecting
solely on cost.

## 82.34 Auto-Suspend

Auto-suspend reduces idle warehouse cost, but an excessively aggressive
value can create frequent suspend/resume cycles.

## 82.35 Auto-Resume

Auto-resume allows workloads to restart a suspended warehouse
automatically when configured.

Provisioning delay can still contribute to query latency.

## 82.36 Provisioning vs Overload

Do not confuse `QUEUED_PROVISIONING_TIME` with `QUEUED_OVERLOAD_TIME`.

They indicate different operational conditions.

## 82.37 Provisioning Direction

If provisioning time is high, investigate warehouse suspension/resume,
resize, cluster provisioning, and recent warehouse changes.

## 82.38 Overload Direction

If overload queueing is high, investigate concurrent workload, query
volume, heavy queries, shared warehouses, retry storms, multi-cluster
behavior, and capacity.

## 82.39 Repair Queueing

If repair-related queue time is significant, treat it as a distinct
signal and investigate the warehouse/platform condition rather than
assuming normal concurrency pressure.

## 82.40 Warehouse Load History

Snowflake warehouse load history can help analyze warehouse load and
queueing trends over time.

Use the relevant Information Schema or Account Usage interfaces
supported in the environment.

## 82.41 Historical Analysis

Compare incident window, previous hour, previous day, same weekday, and
normal peak window.

## 82.42 Baseline Example

Normal:

``` text
P95 queue = 0.5 sec
P95 execution = 3 sec
Concurrency = 20
```

Incident:

``` text
P95 queue = 28 sec
P95 execution = 4 sec
Concurrency = 85
```

This strongly points toward concurrency pressure.

## 82.43 Burst vs Sustained Contention

Burst:

``` text
09:00-09:03 high queue
09:04 normal
```

Sustained:

``` text
09:00-10:30 high queue
```

These require different capacity responses.

## 82.44 Burst Workload

Examples include dashboard refresh, application traffic spike,
top-of-hour batch, and scheduled reports.

Multi-cluster or schedule staggering may help.

## 82.45 Sustained Workload

Examples include business growth, a new application, larger dataset, new
ETL pipeline, or permanent query-volume increase.

This may require architecture or capacity changes.

## 82.46 Top-of-Hour Problem

``` text
01:00 ETL
01:00 Dashboard refresh
01:00 Data quality
01:00 Reporting
01:00 Export
```

## 82.47 Schedule Staggering

Where business requirements permit:

``` text
01:00 ETL
01:10 Data quality
01:20 Reporting
01:30 Export
```

## 82.48 Retry Storms

Application retries can transform temporary queueing into severe
queueing.

## 82.49 Retry Amplification

``` text
100 requests
     |
     v
Queue
     |
     v
Timeout
     |
     v
100 retries
     |
     v
200 outstanding
```

## 82.50 Retry Controls

Use bounded retries, exponential backoff, jitter, concurrency limits,
circuit breaking where appropriate, and idempotency.

## 82.51 Application Connection Pools

``` text
20 pods
x
25 connections
=
500 possible sessions
```

Application scaling can unintentionally increase Snowflake concurrency.

## 82.52 Kubernetes Autoscaling

If an application scales from five pods to twenty and each pod opens the
same connection pool, potential downstream concurrency can increase
fourfold.

Coordinate application autoscaling with downstream capacity.

## 82.53 Connection Pool Standard

Document minimum connections, maximum connections, application replicas,
maximum possible sessions, and expected concurrent queries.

## 82.54 BI Tools

BI tools can create dashboard fan-out, auto refresh, multiple widgets,
multiple users, and repeated queries.

## 82.55 Dashboard Example

``` text
1 dashboard
15 widgets
100 users
```

Potential query volume can become substantial depending on caching and
BI behavior.

## 82.56 ETL Contention

ETL commonly performs COPY, MERGE, INSERT SELECT, CTAS, large
aggregations, and large joins.

These workloads may compete with interactive applications when sharing a
warehouse.

## 82.57 Ad-Hoc Queries

Analysts can unintentionally create expensive workloads against a
production warehouse.

Prefer workload-specific warehouse and role design where appropriate.

## 82.58 Warehouse Ownership

Every production warehouse should have:

``` text
Owner
Purpose
Workloads
SLA
Expected concurrency
Expected size
Scaling model
Cost center
Resource monitor
Runbook
```

## 82.59 Do Not Resize Blindly

Before resizing, capture queue time, execution time, concurrency,
warehouse size, cluster count, query volume, and cost.

After resizing, capture the same measurements.

## 82.60 Controlled Resize Test

``` text
Baseline
   |
   v
Resize
   |
   v
Observe
   |
   v
Compare
```

Measure whether the change improved the intended metric.

## 82.61 Temporary Incident Resize

Document old size, new size, time changed, reason, owner, validation,
and rollback condition.

## 82.62 Do Not Forget to Revert

Temporary emergency scaling can quietly become permanent cost.

Track temporary production changes.

## 82.63 Cost vs Performance

The objective is:

``` text
Required SLA
at
acceptable cost
```

not minimum credits or maximum performance in isolation.

## 82.64 Queue SLA

Example:

``` text
Patient360 API:
P95 queue < 1 sec

ETL:
P95 queue < 30 sec
```

The acceptable queue time differs by workload.

## 82.65 Application SLA

``` text
Application SLA
      |
      v
Snowflake budget
      |
      +--> Queue
      +--> Execution
      +--> Fetch
```

Do not allow Snowflake alone to consume the entire application latency
budget.

## 82.66 Warehouse-Level Metrics

Track query count, concurrency, queue time, execution time, warehouse
credits, cluster count, warehouse uptime, and failed queries.

## 82.67 Workload-Level Metrics

Track service, query tag, user, role, query type, latency, queue,
execution, and errors.

Warehouse averages can hide one affected workload.

## 82.68 P50/P95/P99

Do not rely only on averages.

``` text
Average = 3 sec
P95 = 18 sec
P99 = 45 sec
```

Users may still experience severe latency.

## 82.69 Queue-Time Distribution

Monitor P50, P95, and P99 queue time.

## 82.70 Execution-Time Distribution

Track execution separately from queueing to prevent capacity incidents
from being mistaken for SQL regressions.

## 82.71 Patient360 Scenario

Normal:

``` text
Application latency:       3 sec
Snowflake execution:       2 sec
Queue:                    <1 sec
```

At 10:00:

``` text
Application latency:      38 sec
Snowflake execution:       3 sec
Queue:                    33 sec
```

## 82.72 Investigation

At 10:00 a large EMPI ETL and BI refresh start while API traffic remains
normal.

All three use `SHARED_PROD_WH`.

## 82.73 Diagnosis

The primary cause is warehouse resource contention caused by overlapping
workloads.

The Patient360 SQL itself did not materially regress.

## 82.74 Immediate Mitigation

Depending on business priority, pause noncritical ETL, move the ETL
workload, or provide temporary concurrency capacity.

Validate queue and application latency.

## 82.75 Permanent Remediation

Example:

``` text
PATIENT360_APP_WH
EMPI_ETL_WH
BI_WH
```

plus capacity baselines and queue alerts.

## 82.76 Scenario --- Retry Storm

Initial:

``` text
Queue = 8 sec
Application timeout = 10 sec
```

The application retries immediately.

Soon:

``` text
Queue = 30 sec
Outstanding requests triple
```

Root issue: initial resource contention plus retry amplification.

## 82.77 Scenario --- Provisioning Delay

``` text
Total:          12 sec
Execution:       2 sec
Provisioning:    9 sec
Overload:        0 sec
```

Investigate warehouse resume/provisioning behavior rather than
concurrency overload.

## 82.78 Scenario --- Slow SQL

``` text
Total:          180 sec
Execution:      176 sec
Overload:         0 sec
```

Do not solve this primarily with multi-cluster scale-out. Investigate
query execution.

## 82.79 Scenario --- Transaction Blocking

``` text
Total:           70 sec
Execution:        2 sec
Queue:            0 sec
Blocked:         67 sec
```

Use Chapter 81.

## 82.80 First 10-Minute Runbook

1.  Capture query IDs.
2.  Capture application impact.
3.  Check total elapsed time.
4.  Check execution time.
5.  Check queued overload.
6.  Check queued provisioning.
7.  Check transaction blocked time.
8.  Identify warehouse.
9.  Check warehouse state.
10. Check concurrent workload.
11. Identify workload owners.
12. Check recent traffic/batch changes.
13. Check retry behavior.
14. Establish hypothesis.
15. Apply minimum safe mitigation.

## 82.81 Queueing Incident Runbook

1.  Confirm high queue time.
2.  Identify affected warehouse.
3.  Determine incident window.
4.  Count concurrent workload.
5.  Identify top workloads.
6.  Identify long-running queries.
7.  Check query tags.
8.  Check application traffic.
9.  Check ETL schedules.
10. Check BI workload.
11. Check retry storm.
12. Check warehouse configuration.
13. Check multi-cluster behavior.
14. Determine temporary mitigation.
15. Validate queue reduction.
16. Validate application SLA.
17. Review cost.
18. Implement permanent remediation.

## 82.82 Provisioning Delay Runbook

1.  Confirm `QUEUED_PROVISIONING_TIME`.
2.  Check warehouse state.
3.  Check auto-suspend.
4.  Check auto-resume.
5.  Check resize events.
6.  Check cluster provisioning.
7.  Compare frequency.
8.  Determine whether behavior violates SLA.
9.  Tune configuration if justified.
10. Validate cost impact.

## 82.83 Shared Warehouse Runbook

1.  Identify all workloads.
2.  Identify owners.
3.  Measure query volume by workload.
4.  Measure queue by workload.
5.  Identify overlap windows.
6.  Determine SLA differences.
7.  Determine cost attribution.
8.  Isolate latency-sensitive workloads.
9.  Validate performance.
10. Validate cost.

## 82.84 Retry Storm Runbook

1.  Confirm initial latency increase.
2.  Confirm timeout threshold.
3.  Confirm retry count.
4.  Confirm outstanding concurrency growth.
5.  Stop or reduce amplification.
6.  Use bounded retry/backoff.
7.  Restore underlying capacity.
8.  Validate duplicate safety.
9.  Monitor recovery.
10. Fix retry policy.

## 82.85 Capacity Runbook

1.  Establish baseline.
2.  Measure peak concurrency.
3.  Measure P95/P99 queue.
4.  Measure P95/P99 execution.
5.  Identify workload mix.
6.  Identify growth trend.
7.  Test warehouse sizing.
8.  Test multi-cluster behavior if appropriate.
9.  Measure credits.
10. Select configuration meeting SLA/cost goals.
11. Document limits.
12. Monitor.

## 82.86 Evidence Package

Capture incident start/end, query IDs, warehouse, warehouse size,
cluster configuration, queue time, execution time, provisioning time,
transaction blocked time, concurrency, query volume, query tags,
application traffic, retry count, batch schedules, credit consumption,
mitigation, and before/after metrics.

## 82.87 RCA Template

``` text
Incident:
Environment:
Application:
Warehouse:
Incident start:
Incident end:
Normal latency:
Incident latency:
P50 queue:
P95 queue:
P99 queue:
Execution time:
Provisioning time:
Transaction blocked time:
Normal concurrency:
Incident concurrency:
Workloads sharing warehouse:
Recent changes:
Retry behavior:
Root cause:
Contributing factors:
Immediate mitigation:
Permanent remediation:
Cost impact:
Monitoring improvement:
Owner:
Due date:
```

## 82.88 Preventive Controls

Use workload isolation, query tagging, dedicated warehouse ownership,
capacity baselines, queue alerts, concurrency monitoring, schedule
staggering, bounded retries, backoff/jitter, connection-pool limits,
cost monitoring, and resource monitors.

## 82.89 Alert Design

Useful:

``` text
PATIENT360_APP_WH P95 queued overload exceeds
the agreed production threshold for 10 minutes.
```

Weak:

``` text
Warehouse slow.
```

## 82.90 Capacity Headroom

Maintain reasonable operational headroom for traffic spikes, batch
overlap, failover, unexpected query volume, and business growth.

## 82.91 Capacity Reviews

Review capacity after major application launches, traffic growth, new
pipelines, new BI workloads, large data growth, warehouse architecture
changes, and performance incidents.

## 82.92 Query Governance

Use dedicated roles, dedicated warehouses, query tags, ownership,
monitoring, and cost attribution.

## 82.93 Cost Attribution

If multiple teams share a warehouse, cost attribution becomes difficult.

Isolation can improve both operational and FinOps accountability.

## 82.94 Warehouse Naming

Good:

``` text
PATIENT360_APP_PROD_WH
EMPI_ETL_PROD_WH
FINANCE_BI_PROD_WH
```

Less useful:

``` text
WH1
WH2
NEW_WH
```

## 82.95 Production Standards

For each warehouse document purpose, owner, environment, workloads,
size, scaling policy, min/max clusters, auto suspend/resume, resource
monitor, SLA, expected concurrency, cost center, and runbook.

## 82.96 Monitoring Dashboard

Recommended dashboard sections:

``` text
Warehouse state
Query volume
Concurrent queries
Queue time
Execution time
Provisioning time
Transaction blocking
P50/P95/P99
Warehouse credits
Cluster count
Application latency
Retry rate
```

## 82.97 Top Queued Warehouses

``` sql
SELECT
    WAREHOUSE_NAME,
    COUNT(*) AS QUERY_COUNT,
    SUM(QUEUED_OVERLOAD_TIME) / 1000 AS QUEUED_SECONDS
FROM SNOWFLAKE.ACCOUNT_USAGE.QUERY_HISTORY
WHERE START_TIME >= DATEADD('hour', -4, CURRENT_TIMESTAMP())
GROUP BY WAREHOUSE_NAME
ORDER BY QUEUED_SECONDS DESC;
```

## 82.98 Top Queued Users

``` sql
SELECT
    USER_NAME,
    COUNT(*) AS QUERY_COUNT,
    SUM(QUEUED_OVERLOAD_TIME) / 1000 AS QUEUED_SECONDS
FROM SNOWFLAKE.ACCOUNT_USAGE.QUERY_HISTORY
WHERE START_TIME >= DATEADD('hour', -4, CURRENT_TIMESTAMP())
GROUP BY USER_NAME
ORDER BY QUEUED_SECONDS DESC;
```

## 82.99 Top Queued Query Types

``` sql
SELECT
    QUERY_TYPE,
    COUNT(*) AS QUERY_COUNT,
    SUM(QUEUED_OVERLOAD_TIME) / 1000 AS QUEUED_SECONDS
FROM SNOWFLAKE.ACCOUNT_USAGE.QUERY_HISTORY
WHERE START_TIME >= DATEADD('hour', -4, CURRENT_TIMESTAMP())
GROUP BY QUERY_TYPE
ORDER BY QUEUED_SECONDS DESC;
```

## 82.100 Hourly Queue Trend

``` sql
SELECT
    DATE_TRUNC('hour', START_TIME) AS HOUR,
    WAREHOUSE_NAME,
    COUNT(*) AS QUERY_COUNT,
    SUM(QUEUED_OVERLOAD_TIME) / 1000 AS QUEUED_SECONDS
FROM SNOWFLAKE.ACCOUNT_USAGE.QUERY_HISTORY
WHERE START_TIME >= DATEADD('day', -1, CURRENT_TIMESTAMP())
GROUP BY
    DATE_TRUNC('hour', START_TIME),
    WAREHOUSE_NAME
ORDER BY HOUR, WAREHOUSE_NAME;
```

## 82.101 Queue vs Execution

``` sql
SELECT
    WAREHOUSE_NAME,
    SUM(QUEUED_OVERLOAD_TIME) / 1000 AS QUEUE_SECONDS,
    SUM(EXECUTION_TIME) / 1000 AS EXECUTION_SECONDS
FROM SNOWFLAKE.ACCOUNT_USAGE.QUERY_HISTORY
WHERE START_TIME >= DATEADD('hour', -4, CURRENT_TIMESTAMP())
GROUP BY WAREHOUSE_NAME
ORDER BY QUEUE_SECONDS DESC;
```

Use this as one signal, not as a complete performance diagnosis.

## 82.102 Incident Communication

``` text
Current evidence shows elevated Patient360 latency is primarily
associated with warehouse queueing rather than increased SQL
execution time.

P95 execution remains close to baseline, while P95 queued
overload increased significantly during the incident window.

The queue increase correlates with overlapping ETL and BI
workloads on the shared warehouse.

The noncritical ETL workload has been moved from the application
warehouse, and queue/application latency are returning toward
baseline.
```

## 82.103 Common Mistakes

Avoid calling every delay slow SQL, looking only at total elapsed time,
ignoring queue/provisioning/transaction metrics, resizing without
evidence, scaling up for pure concurrency, scaling out for one slow
query, assuming multi-cluster fixes bad SQL, sharing every workload on
one warehouse, ignoring retry storms, connection pools, Kubernetes
autoscaling, top-of-hour batch collisions, BI fan-out, P95/P99, workload
attribution, cost validation, or leaving emergency scaling permanently.

## 82.104 SRE/DBRE Checklist

-   [ ] Customer impact captured
-   [ ] Query IDs captured
-   [ ] Warehouse identified
-   [ ] Total elapsed checked
-   [ ] Execution time checked
-   [ ] Queued overload checked
-   [ ] Queued provisioning checked
-   [ ] Repair queue checked where relevant
-   [ ] Transaction blocked time checked
-   [ ] Queue percentage calculated
-   [ ] Warehouse state/size checked
-   [ ] Cluster configuration checked
-   [ ] Concurrent workload identified
-   [ ] Query tags reviewed
-   [ ] ETL/BI overlap reviewed
-   [ ] Application traffic/retries reviewed
-   [ ] Connection pool/autoscaling reviewed
-   [ ] Baseline comparison completed
-   [ ] Scale-up vs scale-out decision evidence based
-   [ ] Temporary changes documented
-   [ ] Application SLA validated
-   [ ] Cost impact validated
-   [ ] Permanent remediation assigned
-   [ ] Monitoring updated

## 82.105 Decision Tree

``` text
QUERY SLOW
    |
    v
BREAK DOWN TIME
    |
    +----------------+----------------+----------------+
    |                |                |                |
    v                v                v                v
OVERLOAD          PROVISIONING     BLOCKED         EXECUTION
QUEUE HIGH?       HIGH?            HIGH?           HIGH?
    |                |                |                |
   Yes              Yes              Yes              Yes
    |                |                |                |
    v                v                v                v
CONCURRENCY      WAREHOUSE         TRANSACTION      QUERY
CAPACITY         START/RESIZE      INVESTIGATION    PROFILE
    |
    v
WHO IS USING WH?
    |
    +--> Application
    +--> ETL
    +--> BI
    +--> Ad hoc
    +--> Retries
    |
    v
ISOLATE / SCALE / RESCHEDULE
    |
    v
VALIDATE SLA + COST
```

## 82.106 Quick Reference

``` sql
SHOW WAREHOUSES;

SELECT
    QUERY_ID,
    USER_NAME,
    WAREHOUSE_NAME,
    QUERY_TYPE,
    TOTAL_ELAPSED_TIME,
    EXECUTION_TIME,
    QUEUED_OVERLOAD_TIME,
    QUEUED_PROVISIONING_TIME,
    TRANSACTION_BLOCKED_TIME,
    START_TIME
FROM SNOWFLAKE.ACCOUNT_USAGE.QUERY_HISTORY
WHERE START_TIME >= DATEADD('hour', -4, CURRENT_TIMESTAMP())
ORDER BY QUEUED_OVERLOAD_TIME DESC;

SELECT
    QUERY_ID,
    WAREHOUSE_NAME,
    ROUND(
        QUEUED_OVERLOAD_TIME * 100.0 /
        NULLIF(TOTAL_ELAPSED_TIME, 0),
        2
    ) AS QUEUE_PCT
FROM SNOWFLAKE.ACCOUNT_USAGE.QUERY_HISTORY
WHERE START_TIME >= DATEADD('hour', -4, CURRENT_TIMESTAMP())
ORDER BY QUEUE_PCT DESC;

SELECT
    WAREHOUSE_NAME,
    COUNT(*) AS QUERY_COUNT,
    SUM(QUEUED_OVERLOAD_TIME) / 1000 AS QUEUED_SECONDS
FROM SNOWFLAKE.ACCOUNT_USAGE.QUERY_HISTORY
WHERE START_TIME >= DATEADD('hour', -4, CURRENT_TIMESTAMP())
GROUP BY WAREHOUSE_NAME
ORDER BY QUEUED_SECONDS DESC;
```

## 82.107 Key Principles

1.  Total elapsed time is not execution time.
2.  Always break query duration into components.
3.  Queueing and slow SQL are different problems.
4.  Transaction blocking and queueing are different problems.
5.  Provisioning delay and overload queueing are different.
6.  High overload queue time points toward concurrency pressure.
7.  High execution time points toward query execution.
8.  High blocked time points toward transactions.
9.  Identify the affected warehouse.
10. Identify every workload sharing that warehouse.
11. Query count alone does not measure workload cost.
12. Understand workload mix.
13. Use query tags.
14. Use dedicated service identities.
15. Workload isolation improves predictability.
16. Workload isolation improves blast-radius control.
17. Workload isolation improves cost attribution.
18. Scale up and scale out solve different problems.
19. Larger warehouses do not automatically solve concurrency.
20. Additional clusters do not automatically accelerate one query.
21. Evaluate multi-cluster configuration against workload needs.
22. Monitor auto-suspend/resume behavior.
23. Investigate provisioning delay separately.
24. Compare incident metrics with baseline.
25. Distinguish burst from sustained contention.
26. Stagger workloads when appropriate.
27. Control retry amplification.
28. Use bounded retries.
29. Use backoff and jitter.
30. Monitor application connection pools.
31. Consider application autoscaling impact.
32. Understand BI query fan-out.
33. Protect latency-sensitive workloads from heavy ETL.
34. Track P50/P95/P99.
35. Monitor queue and execution separately.
36. Maintain capacity headroom.
37. Validate performance and cost after scaling.
38. Revert temporary emergency changes when appropriate.
39. Assign warehouse ownership.
40. Capacity planning is an ongoing production responsibility.

## 82.108 Chapter Completion Checklist

After completing this chapter, you should be able to:

-   Explain Snowflake resource contention.
-   Distinguish queueing from execution.
-   Interpret overload, provisioning, repair, and transaction-blocked
    timing.
-   Calculate queue percentage.
-   Identify highly queued workloads.
-   Troubleshoot warehouse concurrency.
-   Identify noisy-neighbor workloads.
-   Design workload isolation.
-   Explain scale-up vs scale-out.
-   Understand multi-cluster warehouse use cases.
-   Investigate auto-suspend/resume and provisioning latency.
-   Distinguish burst from sustained contention.
-   Identify top-of-hour workload collisions.
-   Troubleshoot retry storms.
-   Evaluate connection-pool concurrency.
-   Evaluate Kubernetes autoscaling impact.
-   Investigate BI dashboard fan-out.
-   Build warehouse/workload baselines.
-   Monitor P50/P95/P99 queue and execution.
-   Execute queueing, provisioning, shared-warehouse, retry-storm, and
    capacity runbooks.
-   Create evidence-based incident communications.
-   Produce a resource-contention RCA.
-   Build production warehouse monitoring.
-   Balance performance, SLA, and Snowflake cost.

**Chapter 82 --- Snowflake Resource Contention & Queueing: Complete**
