# Chapter 77 --- Snowflake Warehouse & Concurrency Troubleshooting

## 77.1 Overview

A Snowflake query can be well written and still experience latency when
the virtual warehouse cannot immediately provide enough compute capacity
for the workload.

Typical symptoms include query queueing, application latency during peak
periods, ETL SLA misses, BI slowdown, elevated queued overload time,
credit increases, and multi-cluster expansion.

**Primary rule: Do not resize a warehouse until you know whether the
problem is query execution or concurrency.**

## 77.2 Virtual Warehouse

A Snowflake virtual warehouse provides compute for queries, DML, data
loading, ETL/ELT, BI, applications, and administrative operations.
Storage is separate from warehouse compute.

## 77.3 Why This Matters

A database can be healthy while its warehouse is improperly sized or
overloaded.

## 77.4 Warehouse Sizes

Warehouse sizes provide increasing compute capacity: X-SMALL → SMALL →
MEDIUM → LARGE → X-LARGE and above. Larger warehouses consume credits at
higher rates while running.

## 77.5 Scale Up

Scale up means increasing warehouse size, for example MEDIUM → LARGE.

## 77.6 Scale Out

Scale out means adding clusters in a multi-cluster warehouse.

## 77.7 Different Problems

Scale up primarily helps workloads that benefit from more resources per
executing workload. Scale out primarily helps concurrency. Do not treat
them as interchangeable.

## 77.8 Warehouse Inventory

``` sql
SHOW WAREHOUSES;
```

Review warehouse name, state, size, auto-suspend, auto-resume, min/max
clusters, scaling policy, and resource monitor where applicable.

## 77.9 Verify Current Warehouse

``` sql
SELECT CURRENT_WAREHOUSE();
```

Never troubleshoot an assumed warehouse.

## 77.10 Verify Query Warehouse

Use query history to determine the warehouse that actually executed the
affected query.

## 77.11 Warehouse Query History

``` sql
SELECT QUERY_ID, USER_NAME, WAREHOUSE_NAME, QUERY_TYPE,
       TOTAL_ELAPSED_TIME, EXECUTION_TIME,
       QUEUED_OVERLOAD_TIME, QUEUED_PROVISIONING_TIME, START_TIME
FROM SNOWFLAKE.ACCOUNT_USAGE.QUERY_HISTORY
WHERE WAREHOUSE_NAME = 'PATIENT360_WH'
  AND START_TIME >= DATEADD('hour', -4, CURRENT_TIMESTAMP())
ORDER BY START_TIME DESC;
```

## 77.12 What Is Queueing?

A query is queued when it cannot immediately begin required execution
work. The reason matters.

## 77.13 Major Queue Categories

Review `QUEUED_OVERLOAD_TIME`, `QUEUED_PROVISIONING_TIME`,
`QUEUED_REPAIR_TIME`, and `TRANSACTION_BLOCKED_TIME`.

## 77.14 Queued Overload Time

High `QUEUED_OVERLOAD_TIME` usually indicates warehouse workload
contention.

## 77.15 Example

``` text
Total elapsed:           45 sec
Execution:                6 sec
Queued overload:         38 sec
```

Most latency occurred before execution.

## 77.16 Concurrency Problem

Concurrency occurs when many queries compete for warehouse resources
simultaneously.

## 77.17 Common Causes

Traffic spikes, batch overlap, BI refresh, ETL schedules, retry storms,
ad-hoc analytics, excessive application workers, poor workload
isolation, and long-running queries.

## 77.18 Highest Queue Time

``` sql
SELECT QUERY_ID, USER_NAME, WAREHOUSE_NAME,
       TOTAL_ELAPSED_TIME, EXECUTION_TIME,
       QUEUED_OVERLOAD_TIME, START_TIME
FROM SNOWFLAKE.ACCOUNT_USAGE.QUERY_HISTORY
WHERE START_TIME >= DATEADD('hour', -4, CURRENT_TIMESTAMP())
ORDER BY QUEUED_OVERLOAD_TIME DESC
LIMIT 50;
```

## 77.19 Queue Percentage

Conceptually:
`Queue % = QUEUED_OVERLOAD_TIME / TOTAL_ELAPSED_TIME × 100`.

## 77.20 Warehouse Load History

Use warehouse load history to evaluate running and queued workload over
time.

## 77.21 Incident Correlation

Correlate application latency → query queueing → warehouse load →
concurrent workload using the same incident window.

## 77.22 Burst vs Sustained Load

Determine whether load is a short burst or sustained saturation.

## 77.23 Short Burst

A sudden burst of hundreds of queries within seconds should trigger
application concurrency and burst analysis.

## 77.24 Sustained Load

Continuous overload may require capacity, workload isolation,
scheduling, or query optimization.

## 77.25 Long Queries Consume Capacity

A few expensive queries can occupy resources long enough to cause other
queries to queue.

## 77.26 Find Long Queries

``` sql
SELECT QUERY_ID, USER_NAME, WAREHOUSE_NAME,
       TOTAL_ELAPSED_TIME, EXECUTION_TIME, START_TIME
FROM SNOWFLAKE.ACCOUNT_USAGE.QUERY_HISTORY
WHERE WAREHOUSE_NAME = 'PATIENT360_WH'
  AND START_TIME >= DATEADD('hour', -4, CURRENT_TIMESTAMP())
ORDER BY EXECUTION_TIME DESC
LIMIT 50;
```

## 77.27 Shared Warehouse

Application API, ETL, BI, data science, and ad-hoc workloads sharing one
warehouse can become unpredictable at peak load.

## 77.28 Isolation Model

Where justified use separate warehouses such as `PATIENT360_APP_WH`,
`PATIENT360_ETL_WH`, `PATIENT360_BI_WH`, and `PATIENT360_ADHOC_WH`.

## 77.29 Isolation Benefits

Workload isolation improves predictability, SLA protection,
troubleshooting, cost attribution, capacity planning, and blast-radius
control.

## 77.30 Isolation Tradeoff

More warehouses increase operational complexity and can increase cost if
poorly configured.

## 77.31 Auto-Suspend

``` sql
ALTER WAREHOUSE PATIENT360_WH SET AUTO_SUSPEND = 60;
```

## 77.32 Auto-Resume

``` sql
ALTER WAREHOUSE PATIENT360_WH SET AUTO_RESUME = TRUE;
```

## 77.33 Resume Latency

A suspended warehouse must resume before processing new workload and can
create `QUEUED_PROVISIONING_TIME`.

## 77.34 Auto-Suspend Tradeoff

Aggressive suspension reduces idle cost but can increase resume latency.

## 77.35 Warehouse Resize

``` sql
ALTER WAREHOUSE PATIENT360_WH SET WAREHOUSE_SIZE = 'LARGE';
```

## 77.36 Resize Is an Operational Change

Before resizing capture current size, latency, queueing, concurrency,
spill, credits, and business impact.

## 77.37 When Scale-Up May Help

Execution-heavy queries, large joins/aggregations/sorts, significant
spill, and ETL processing may benefit.

## 77.38 When Scale-Up May Not Solve Root Cause

Poor SQL, join explosions, bad filters, transaction blocking,
application/network latency, and extreme concurrency need different
remedies.

## 77.39 Scientific Resize Test

BASELINE → RESIZE → RUN REPRESENTATIVE WORKLOAD → MEASURE
runtime/queueing/spill/credits → DECIDE.

## 77.40 Measure Cost

Performance improvement without cost measurement is incomplete.

## 77.41 Multi-Cluster Purpose

Multi-cluster warehouses are designed to help handle concurrency.

## 77.42 Architecture

Incoming queries can be distributed across additional warehouse clusters
as capacity expands.

## 77.43 Minimum and Maximum Clusters

Configure minimum and maximum cluster counts according to supported
account features and workload requirements.

## 77.44 Example

``` sql
ALTER WAREHOUSE BI_WH
SET MIN_CLUSTER_COUNT = 1
    MAX_CLUSTER_COUNT = 4;
```

Validate production configuration against current Snowflake
feature/edition support.

## 77.45 Scaling Policy

Multi-cluster behavior can use policy concepts such as STANDARD and
ECONOMY.

## 77.46 Standard

Generally prioritizes reducing queueing more aggressively.

## 77.47 Economy

Generally prioritizes conserving credits before starting additional
clusters.

## 77.48 Select Based on SLA

Latency-sensitive workloads may justify more aggressive scaling;
lower-priority workloads may justify conservative policies.

## 77.49 Multi-Cluster Is Not Query Optimization

If one query is slow while running alone, adding clusters does not
automatically make it fast.

## 77.50 Concurrency vs Single-Query Performance

If a query is slow alone, investigate execution and warehouse size. If
fast alone but slow under load, investigate concurrency and queueing.

## 77.51 Application Retry Storm

Retries can multiply request volume and make contention significantly
worse.

## 77.52 Retry Storm Symptoms

Request count, query count, queueing, credits, and application latency
can spike together.

## 77.53 Retry Response

Control retry count, exponential backoff, jitter, timeouts, and worker
concurrency.

## 77.54 Connection Pool Behavior

A large application connection pool can permit excessive simultaneous
query submission.

## 77.55 Concurrency Control

Use bounded application concurrency where appropriate.

## 77.56 ETL Concurrency

Large numbers of simultaneous ETL statements can create warehouse
contention.

## 77.57 Batch Scheduling

Avoid launching every workload at exactly the same time when business
requirements allow staggering.

## 77.58 BI Dashboard Burst

One dashboard can generate many simultaneous SQL statements. Many users
refreshing dashboards can create substantial concurrency.

## 77.59 Protect Critical Applications

Avoid uncontrolled ad-hoc analytics competing with latency-sensitive
application queries when SLA protection matters.

## 77.60 Resource Monitor

A resource monitor can affect warehouse availability when
thresholds/actions are reached.

## 77.61 Resource Monitor Troubleshooting

``` sql
SHOW RESOURCE MONITORS;
```

## 77.62 Warehouse State Check

``` sql
SHOW WAREHOUSES;
```

## 77.63 Manual Resume

``` sql
ALTER WAREHOUSE PATIENT360_WH RESUME;
```

## 77.64 Manual Suspend

``` sql
ALTER WAREHOUSE PATIENT360_WH SUSPEND;
```

Do not suspend without understanding active workload impact.

## 77.65 Concurrency Can Increase Cost

Higher concurrency can cause longer runtime, larger warehouses,
additional clusters, and more retries.

## 77.66 Cost Spike Decision Tree

Investigate warehouse → size changes → runtime → concurrency → extra
clusters → retry storms.

## 77.67 Warehouse Metering

Use warehouse metering/account usage data to correlate credits with
warehouse, time, workload, resize, and cluster count.

## 77.68 Warehouse Baseline

Maintain normal query volume, concurrency, queue time, execution time,
warehouse runtime, credits, and cluster count.

## 77.69 Know Your Peak

Capacity decisions should consider peak windows and batch periods, not
only daily averages.

## 77.70 Average Can Hide Saturation

Low daily average utilization can still contain short severe queueing
windows.

## 77.71 Tag by Workload

Use query tags such as `service=patient360-api`, `pipeline=empi-load`,
and `dashboard=clinical-operations`.

## 77.72 Query Tag Benefit

Tags help identify which workload consumed warehouse capacity during an
incident.

## 77.73 User Attribution

Capture `USER_NAME`, `ROLE_NAME`, `QUERY_TAG`, and `WAREHOUSE_NAME`.

## 77.74 Recent Changes

Check resize, auto-suspend, multi-cluster settings, scaling policy,
resource monitor, and workload movement.

## 77.75 Performance vs Cost

The target is required SLA plus acceptable cost.

## 77.76 Capacity Planning Inputs

Use query growth, concurrency growth, data growth, application growth,
batch growth, BI adoption, peak workload, and credit trends.

## 77.77 Forecast

Forecast future peak concurrency before queueing becomes an incident.

## 77.78 First 10 Minutes

1.  Confirm customer impact.
2.  Record incident start.
3.  Identify warehouse/state/size.
4.  Capture queueing, provisioning, and execution time.
5.  Identify concurrent workloads.
6.  Check recent warehouse changes.
7.  Check resource monitor.
8.  Check retry/request volume.

## 77.79 Warehouse Queueing Runbook

1.  Identify warehouse and incident window.
2.  Capture affected query IDs.
3.  Measure queued overload and execution time.
4.  Check warehouse size/state/load history.
5.  Identify concurrent and long-running queries.
6.  Review tags, users, roles, ETL, BI, application traffic, and
    retries.
7.  Check recent configuration changes.
8.  Determine burst versus sustained load.
9.  Evaluate optimization, isolation, staggering, multi-cluster, and
    scale-up.
10. Apply minimum remediation.
11. Validate queue reduction/application latency.
12. Measure credit impact.
13. Monitor, document root cause, and add preventive action.

## 77.80 Provisioning Delay Runbook

Check state, provisioning time, auto-suspend/resume, arrival pattern,
SLA, and cost of keeping compute active longer. Adjust only when
justified.

## 77.81 Multi-Cluster Runbook

Confirm concurrency is the problem and single-query performance is
acceptable; capture baseline queueing/concurrency/cost; review feature
support, min/max clusters, and policy; apply controlled configuration;
measure queueing, cluster expansion, latency, and credits; tune and
document.

## 77.82 Resize Runbook

Capture size/runtime/queueing/spill/credits; resize one step where
appropriate; rerun representative workload; compare execution, queueing,
spill, and credits; retain or revert based on evidence.

## 77.83 Retry Storm Runbook

Identify request spike; compare requests to queries; inspect timeouts,
retries, workers, and queueing; bound retries and add backoff/jitter;
validate stable traffic and latency.

## 77.84 Workload Isolation Runbook

Identify shared workloads; classify SLA/volume/concurrency/cost;
identify interference; design warehouse separation, sizes, auto-suspend,
monitors, and tags; test; migrate deliberately; validate and document
ownership.

## 77.85 Patient360 Scenario

`PATIENT360_WH` supports Patient API, ETL, and BI dashboards.

## 77.86 Normal State

``` text
P95 API query:       3 sec
Queueing:            <100 ms
Warehouse:           MEDIUM
```

## 77.87 Incident

``` text
P95 API query:       38 sec
Execution:            4 sec
Queued overload:     33 sec
```

## 77.88 Evidence

API execution remains normal while concurrent warehouse workload
increases at ETL start.

## 77.89 Root Cause

ETL and latency-sensitive API workloads compete on the same warehouse.

## 77.90 Immediate Mitigation

Pause/stagger ETL, move ETL to another warehouse, or temporarily
increase concurrency capacity according to operational approval.

## 77.91 Permanent Remediation

Separate `PATIENT360_APP_WH` and `PATIENT360_ETL_WH` with ownership,
monitoring, cost controls, and capacity policies.

## 77.92 Warehouse / Concurrency RCA Template

``` text
Incident:
Environment:
Application:
Warehouse:
Start:
End:
Customer impact:
Warehouse size:
Warehouse state:
Normal queue time:
Incident queue time:
Normal execution:
Incident execution:
Concurrent workload:
Long-running queries:
Retry behavior:
ETL/BI overlap:
Recent warehouse changes:
Resource monitor status:
Multi-cluster configuration:
Root cause:
Contributing factors:
Immediate mitigation:
Permanent remediation:
Cost impact:
Preventive monitoring:
Owner:
```

## 77.93 Monitor Queueing

Alert on sustained queueing rather than waiting for application
complaints.

## 77.94 Monitor Concurrency

Understand normal and peak query concurrency.

## 77.95 Monitor Cost

Capacity changes should be visible in FinOps monitoring.

## 77.96 Tag Workloads

Use query tags so workload attribution is immediate.

## 77.97 Control Application Concurrency

Avoid unlimited workers sending queries simultaneously.

## 77.98 Stagger Batch Workloads

Avoid unnecessary schedule collisions.

## 77.99 Isolate Critical Workloads

Protect latency-sensitive applications from large ETL and ad-hoc
workloads where justified.

## 77.100 Review Warehouse Configuration

Periodically review size, auto-suspend/resume, min/max clusters, scaling
policy, resource monitor, owner, and workload.

## 77.101 Common Mistakes

Avoid immediate resizing, assuming larger is always better, using
multi-cluster for one bad query, ignoring
queue/provisioning/overlap/retry metrics, unlimited application
concurrency, simultaneous batches, uncontrolled workload mixing,
disabling auto-suspend without cost review, ignoring resource monitors,
scaling without before/after metrics or cost measurement, changing SQL
and warehouse size simultaneously, using only daily averages, ignoring
peak windows, missing query tags/ownership, and failing to forecast
capacity.

## 77.102 Recommended Standards

Baseline every critical warehouse; monitor
queueing/concurrency/runtime/credits; track peak windows; tag workloads;
control application concurrency; configure auto-suspend/resume
appropriately; isolate workloads where justified; use multi-cluster for
concurrency; scale up for appropriate execution workloads; measure
performance and cost before/after; document ownership; review capacity
regularly.

## 77.103 Warehouse Troubleshooting Checklist

-   [ ] Customer impact and incident window confirmed
-   [ ] Warehouse/state/size captured
-   [ ] Auto-suspend/resume captured
-   [ ] Resource monitor checked
-   [ ] Queued overload/provisioning/execution measured
-   [ ] Concurrent and long-running workload identified
-   [ ] Tags/users/roles reviewed
-   [ ] ETL/BI/application traffic reviewed
-   [ ] Retry behavior reviewed
-   [ ] Burst versus sustained determined
-   [ ] Recent configuration changes reviewed
-   [ ] Multi-cluster configuration reviewed
-   [ ] Workload isolation considered
-   [ ] Scale-up and scale-out considered
-   [ ] Before/after performance measured
-   [ ] Cost impact measured
-   [ ] Root cause established
-   [ ] Preventive action documented

## 77.104 Warehouse Troubleshooting Flow

``` text
APPLICATION SLOW
      |
      v
QUERY ID
      |
      v
QUEUE TIME HIGH?
      |
   +--+--+
   |     |
  Yes    No
   |     |
   v     v
CONCURRENCY    EXECUTION HIGH?
   |               |
   |            +--+--+
   |            |     |
   |           Yes    No
   |            |     |
   |            v     v
   |         QUERY   APP /
   |         PROFILE NETWORK
   |
   v
BURST OR SUSTAINED?
   |
   +--> Burst --> App concurrency / retry / multi-cluster
   +--> Sustained --> Optimize / isolate / capacity
```

## 77.105 Warehouse & Concurrency Principles

1.  Warehouse and query performance are related but different.
2.  Determine whether latency occurs before or during execution.
3.  `QUEUED_OVERLOAD_TIME` is critical for concurrency analysis.
4.  Provisioning delay differs from overload queueing.
5.  Transaction blocking is not warehouse queueing.
6.  Scale up and scale out solve different problems.
7.  Multi-cluster primarily addresses concurrency.
8.  Multi-cluster does not automatically fix one slow query.
9.  Long queries and workload overlap can create contention.
10. Retry storms can amplify queueing.
11. Application concurrency should be bounded.
12. Workload isolation improves predictability and cost attribution.
13. Auto-suspend controls idle cost but can introduce resume latency.
14. Warehouse resizing is a production change.
15. Capture baseline before resizing.
16. Measure performance and cost after resizing.
17. Change one major variable at a time.
18. Daily averages can hide peak saturation.
19. Query tags improve attribution.
20. Resource monitors can affect availability.
21. Capacity planning should include concurrency growth.
22. Monitor queueing, concurrency, and credits proactively.
23. Diagnose before scaling.

## 77.106 Chapter Completion Checklist

After completing this chapter, you should be able to explain warehouse
concurrency; distinguish scale-up from scale-out; identify warehouse
configuration; analyze queueing and provisioning delays; distinguish
transaction blocking; identify long-running and overlapping workloads;
identify retry storms; control application concurrency; evaluate ETL/BI
bursts; configure auto-suspend/resume appropriately; perform controlled
resizing; measure performance and cost; understand multi-cluster
warehouses and scaling policies; design workload isolation; investigate
resource-monitor effects; correlate load with incidents; establish
baselines and peak windows; perform capacity planning; execute
queueing/provisioning/multi-cluster/resize/retry/isolation runbooks;
produce an evidence-based RCA; and establish preventive monitoring.

**Chapter 77 --- Snowflake Warehouse & Concurrency Troubleshooting:
Complete**
