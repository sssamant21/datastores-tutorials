# Chapter 76 --- Snowflake Query Slowness Troubleshooting

## 76.1 Overview

When an application reports **"Snowflake is slow"**, do not immediately
resize the warehouse. First determine where the time is being spent.

``` text
Application Slow
      |
      v
Snowflake Query Slow?
      |
   +--+--+
   |     |
  No    Yes
   |     |
   |     v
   |  Identify Query ID
   |     |
   |     v
   |  Break Down Runtime
   |     |
   |     +--> Queueing
   |     +--> Provisioning
   |     +--> Compilation
   |     +--> Execution
   |     +--> Data Transfer
   |
   v
Investigate application/network
```

**Primary rule: Diagnose before resizing.**

## 76.2 Troubleshooting Objectives

For every slow-query incident determine what query is slow, when it
became slow, scope, warehouse, whether the delay is queueing or
execution, recent SQL/data/configuration changes, spilling, pruning,
concurrency, workload overlap, and whether the latency is actually
inside Snowflake.

## 76.3 Standard Workflow

REPORT → VERIFY → IDENTIFY QUERY → CAPTURE BASELINE → BREAK DOWN RUNTIME
→ QUERY PROFILE → ROOT CAUSE → REMEDIATE → VALIDATE → PREVENT.

## 76.4 Define the Problem

Capture application, environment, query ID, warehouse, user, role, start
time, normal runtime, current runtime, frequency, and customer impact.

## 76.5 Example

``` text
Application: Patient360
Environment: Production
Warehouse: PATIENT360_WH
Normal runtime: 3–5 seconds
Current runtime: 45–60 seconds
Incident start: 13:20 UTC
Impact: Clinical workflow delayed
```

## 76.6 Determine Scope

Determine whether the issue affects one query, one application, one
warehouse, multiple warehouses, or the entire account.

## 76.7 Scope Interpretation

One query suggests SQL/data investigation. Many queries on one warehouse
suggests load/concurrency/queueing. Many workloads across warehouses
warrants broader platform, network, or account investigation.

## 76.8 Query ID Is Critical

Capture `QUERY_ID` whenever possible.

## 76.9 Recent Query History

``` sql
SELECT QUERY_ID, USER_NAME, ROLE_NAME, WAREHOUSE_NAME, QUERY_TYPE,
       EXECUTION_STATUS, TOTAL_ELAPSED_TIME, START_TIME, END_TIME
FROM SNOWFLAKE.ACCOUNT_USAGE.QUERY_HISTORY
WHERE START_TIME >= DATEADD('hour', -1, CURRENT_TIMESTAMP())
ORDER BY START_TIME DESC;
```

## 76.10 Historical Runtime

Compare current runtime against historical executions rather than
judging a single execution.

## 76.11 Query Hash

Where appropriate use `QUERY_HASH` and `QUERY_PARAMETERIZED_HASH` to
identify repeated logically equivalent workloads.

## 76.12 Baseline

``` text
Historical P50: 3.2 sec
Historical P95: 5.8 sec
Current:        47 sec
```

## 76.13 Important Timing Fields

Review `TOTAL_ELAPSED_TIME`, `COMPILATION_TIME`, `EXECUTION_TIME`,
`QUEUED_PROVISIONING_TIME`, `QUEUED_REPAIR_TIME`,
`QUEUED_OVERLOAD_TIME`, and `TRANSACTION_BLOCKED_TIME`.

## 76.14 Timing Breakdown Query

``` sql
SELECT QUERY_ID, WAREHOUSE_NAME, TOTAL_ELAPSED_TIME,
       COMPILATION_TIME, EXECUTION_TIME,
       QUEUED_PROVISIONING_TIME, QUEUED_REPAIR_TIME,
       QUEUED_OVERLOAD_TIME, TRANSACTION_BLOCKED_TIME
FROM SNOWFLAKE.ACCOUNT_USAGE.QUERY_HISTORY
WHERE QUERY_ID = '<query_id>';
```

## 76.15 Runtime Decomposition

Separate compilation, queueing, transaction blocking, execution, and
other overhead. The largest component usually determines the next
investigation.

## 76.16 Queued Overload Time

High `QUEUED_OVERLOAD_TIME` generally indicates insufficient immediately
available execution capacity for the concurrent workload.

## 76.17 Typical Queueing Causes

Concurrency spikes, simultaneous queries, ETL/BI overlap, batch
workloads, insufficient concurrency capacity, and long-running queries.

## 76.18 Queueing Response

Consider query optimization, workload isolation, schedule separation,
multi-cluster strategy, or resizing depending on evidence.

## 76.19 Queued Provisioning Time

High `QUEUED_PROVISIONING_TIME` indicates waiting while compute is
created, resumed, or resized.

## 76.20 Typical Provisioning Scenario

Warehouse suspended → query arrives → warehouse resumes → query waits.

## 76.21 Provisioning Interpretation

A small resume delay can be normal and is not automatically a
performance defect.

## 76.22 Queued Repair Time

Review `QUEUED_REPAIR_TIME`. Unusual elevation across workloads may
require broader warehouse/platform investigation.

## 76.23 Transaction Blocked Time

Review `TRANSACTION_BLOCKED_TIME`.

## 76.24 Transaction Blocking

Investigate concurrent DML, explicit/long transactions, and conflicting
writes.

## 76.25 High Compilation Time

If compilation is a large portion of total runtime, investigate SQL
complexity.

## 76.26 Compilation Contributors

Complex SQL, many joins, large UNION structures, deeply nested views,
generated SQL, and metadata-heavy operations can contribute.

## 76.27 Compilation vs Execution

A larger warehouse does not automatically solve compilation bottlenecks.

## 76.28 High Execution Time

If `EXECUTION_TIME` dominates, inspect Query Profile.

## 76.29 Query Profile

Review table scans, joins, aggregations, sorts, window functions, data
exchange, spilling, and exploding joins.

## 76.30 Large Table Scan

Investigate bytes scanned, partitions scanned/total, rows scanned, and
rows returned.

## 76.31 Scan Warning Example

``` text
Rows scanned: 2,000,000,000
Rows returned: 10
```

For a selective query this deserves pruning/filter investigation.

## 76.32 Micro-Partition Pruning

Snowflake uses micro-partition metadata to avoid scanning partitions
that cannot contain required data.

## 76.33 Good Pruning

``` text
Total partitions:   100,000
Scanned partitions:   2,000
```

## 76.34 Poor Pruning

``` text
Total partitions:   100,000
Scanned partitions:  95,000
```

## 76.35 Poor Pruning Causes

Nonselective filters, changed distribution/access patterns, poor
clustering for the workload, transformations around filter columns, or
predicates unable to eliminate enough partitions.

## 76.36 Filter Early

``` sql
SELECT EMPI, STATUS
FROM PROD_DB.EMPI.PATIENT
WHERE SERVICE_DATE >= '2026-10-01'
  AND STATUS = 'ACTIVE';
```

## 76.37 Avoid Unnecessary Data

Avoid `SELECT *` when only a few columns are required.

## 76.38 SELECT \* Impact

Unnecessary columns can increase processing, transfer, and client
memory.

## 76.39 LIMIT Is Not Universal Optimization

`LIMIT 10` does not guarantee expensive scans, joins, sorting, or
aggregation can be avoided.

## 76.40 Join Investigation

Review join type, input/output rows, keys, duplicates, and data
explosion.

## 76.41 Exploding Join Example

``` text
Left input:      10 million rows
Right input:      5 million rows
Join output:     900 million rows
```

## 76.42 Common Cause

Many-to-many joins caused by non-unique keys can dramatically increase
intermediate rows.

## 76.43 Validate Join Cardinality

Confirm expected cardinality before blaming warehouse capacity.

## 76.44 Expensive Aggregation

Review GROUP BY cardinality, DISTINCT, COUNT(DISTINCT), intermediate
datasets, and spilling.

## 76.45 DISTINCT as a Symptom

Do not use DISTINCT merely to hide duplicates caused by an incorrect
join.

## 76.46 Sort Operations

Large ORDER BY, window, and ranking operations can require substantial
compute and memory.

## 76.47 Window Functions

Review ROW_NUMBER, RANK, DENSE_RANK, LAG, LEAD, partition sizes, and
ordering.

## 76.48 Spilling

Intermediate data may spill when operations cannot remain entirely in
warehouse memory.

## 76.49 Spill Metrics

Review `BYTES_SPILLED_TO_LOCAL_STORAGE` and
`BYTES_SPILLED_TO_REMOTE_STORAGE`.

## 76.50 Local Spill

Significant local spill can indicate memory pressure or large
intermediate operations.

## 76.51 Remote Spill

Remote spilling is generally more expensive and is an important
performance warning.

## 76.52 Spill Query

``` sql
SELECT QUERY_ID, WAREHOUSE_NAME, TOTAL_ELAPSED_TIME,
       BYTES_SPILLED_TO_LOCAL_STORAGE,
       BYTES_SPILLED_TO_REMOTE_STORAGE
FROM SNOWFLAKE.ACCOUNT_USAGE.QUERY_HISTORY
WHERE START_TIME >= DATEADD('hour', -4, CURRENT_TIMESTAMP())
ORDER BY BYTES_SPILLED_TO_REMOTE_STORAGE DESC;
```

## 76.53 Spill Causes

Large joins, aggregations, sorts, windows, intermediate results, or
insufficient memory for the workload.

## 76.54 Spill Remediation

Optimize SQL, reduce intermediate data, filter earlier, fix join
cardinality, pre-aggregate, or scale when justified.

## 76.55 Bytes Scanned

Compare bytes scanned, rows returned, and historical scan volume.

## 76.56 Data Growth

Unchanged SQL can slow as data grows substantially.

## 76.57 Data Change Questions

Check row-count growth, distribution, clustering, retention, and
selectivity changes.

## 76.58 Clustering Is Workload-Specific

Do not add clustering keys to every large table. Evaluate repeated
selective access patterns.

## 76.59 Clustering Tradeoff

Potential benefit is better pruning; potential cost is additional
maintenance/credits.

## 76.60 Search Optimization Service

For appropriate selective lookup workloads, Search Optimization Service
may help. Evaluate benefit and cost.

## 76.61 Query Acceleration Service

For eligible workloads, evaluate Query Acceleration Service based on
eligibility, performance, and cost.

## 76.62 Materialization

For repeated expensive transformations consider precomputed tables,
dynamic tables, materialized views, or aggregated tables where
appropriate.

## 76.63 Result Cache

Persisted query results can be reused when conditions permit.

## 76.64 Cache Can Distort Testing

A query may appear very fast because cached results were reused.

## 76.65 Performance Testing

Understand cache behavior before concluding a SQL change improved
execution.

## 76.66 Warehouse-Local Cache

Repeated queries on an active warehouse can behave differently after
suspension/resume.

## 76.67 Benchmark Consistently

Control test conditions when comparing warehouse sizes, SQL versions, or
clustering strategies.

## 76.68 Bigger Is Not Always the First Fix

Scaling does not fix bad joins, unnecessary processing, poor isolation,
bad filters, transaction blocking, or application latency.

## 76.69 Resize Test

Capture before → resize → controlled comparison → measure runtime and
cost → decide → restore if unnecessary.

## 76.70 Concurrent Workload

A query may be fast alone and slow during peak concurrency.

## 76.71 Check Timing

Compare slow executions with concurrent query count, queueing, batch
schedules, BI usage, and ETL jobs.

## 76.72 Shared Warehouse Problem

Application, ETL, BI, and ad-hoc workloads sharing one warehouse can
contend.

## 76.73 Workload Isolation

Where justified use separate warehouses such as `PATIENT360_APP_WH`,
`PATIENT360_ETL_WH`, and `PATIENT360_BI_WH`.

## 76.74 Multi-Cluster Warehouses

Multi-cluster warehouses can help concurrency-heavy workloads but do not
automatically fix one poor query.

## 76.75 Snowflake vs Application Runtime

If Snowflake runs in 2 seconds but the API responds in 35 seconds,
investigate the remaining application path.

## 76.76 Application Investigation

Check connection pools, network, serialization, gateways, retries,
application processing, and downstream dependencies.

## 76.77 Large Result Set

Fast SQL can feel slow if millions of rows must be transferred and
processed.

## 76.78 Result Questions

Determine returned rows/bytes, whether all are required, and whether
aggregation can occur in Snowflake.

## 76.79 Client Bottleneck

Measure server-side runtime separately from end-to-end latency.

## 76.80 Network Investigation

Consider client location, region, private connectivity, proxy, firewall,
DNS, packet loss, and network path.

## 76.81 Query Tagging

``` sql
ALTER SESSION SET QUERY_TAG =
'service=patient360,env=prod,operation=patient-search';
```

## 76.82 Compare Good vs Bad Execution

Compare runtime, warehouse/size, queueing, compilation, execution, bytes
scanned, spill, rows, time, and concurrency.

## 76.83 Queueing Example

``` text
Metric                  Normal       Incident
Total runtime           4 sec        42 sec
Queue time              0            35 sec
Execution               3.5 sec      5 sec
Remote spill            0            0
```

Primary issue: warehouse queueing.

## 76.84 Execution Regression Example

``` text
Metric                  Normal       Incident
Total runtime           5 sec        55 sec
Queue time              0            0
Execution               4 sec        54 sec
Remote spill            0            30 GB
```

Investigate spilling and Query Profile.

## 76.85 Data Growth Example

``` text
Metric                  Normal       Incident
Partitions scanned      2,000        95,000
Rows returned           100          110
Queueing                 0            0
```

Investigate pruning, distribution, and filters.

## 76.86 Top Slow Queries

``` sql
SELECT QUERY_ID, USER_NAME, WAREHOUSE_NAME, QUERY_TYPE,
       TOTAL_ELAPSED_TIME, EXECUTION_TIME,
       QUEUED_OVERLOAD_TIME, START_TIME
FROM SNOWFLAKE.ACCOUNT_USAGE.QUERY_HISTORY
WHERE START_TIME >= DATEADD('hour', -4, CURRENT_TIMESTAMP())
ORDER BY TOTAL_ELAPSED_TIME DESC
LIMIT 50;
```

## 76.87 Highest Queueing

``` sql
SELECT QUERY_ID, WAREHOUSE_NAME, TOTAL_ELAPSED_TIME,
       QUEUED_OVERLOAD_TIME, QUEUED_PROVISIONING_TIME, START_TIME
FROM SNOWFLAKE.ACCOUNT_USAGE.QUERY_HISTORY
WHERE START_TIME >= DATEADD('hour', -4, CURRENT_TIMESTAMP())
ORDER BY QUEUED_OVERLOAD_TIME DESC
LIMIT 50;
```

## 76.88 Highest Compilation

``` sql
SELECT QUERY_ID, WAREHOUSE_NAME, TOTAL_ELAPSED_TIME,
       COMPILATION_TIME, START_TIME
FROM SNOWFLAKE.ACCOUNT_USAGE.QUERY_HISTORY
WHERE START_TIME >= DATEADD('hour', -4, CURRENT_TIMESTAMP())
ORDER BY COMPILATION_TIME DESC
LIMIT 50;
```

## 76.89 Highest Remote Spill

``` sql
SELECT QUERY_ID, WAREHOUSE_NAME, TOTAL_ELAPSED_TIME,
       BYTES_SPILLED_TO_LOCAL_STORAGE,
       BYTES_SPILLED_TO_REMOTE_STORAGE, START_TIME
FROM SNOWFLAKE.ACCOUNT_USAGE.QUERY_HISTORY
WHERE START_TIME >= DATEADD('hour', -4, CURRENT_TIMESTAMP())
ORDER BY BYTES_SPILLED_TO_REMOTE_STORAGE DESC
LIMIT 50;
```

## 76.90 Symptom → Direction

  Symptom                     Investigate First
  --------------------------- ----------------------------
  High queued overload        Warehouse concurrency
  High provisioning           Resume/resize
  High transaction blocking   Concurrent transactions
  High compilation            SQL complexity
  High execution              Query Profile
  Large scan                  Pruning/filtering
  Large remote spill          Memory/intermediate data
  Huge join output            Join cardinality
  Snowflake fast, app slow    Client/network/application
  Slow only at peak           Concurrency
  Slow after data growth      Scan/pruning/data design

## 76.91 Query Slowness Runbook

1.  Confirm customer impact and incident start.
2.  Identify application/environment/query ID.
3.  Capture SQL safely, user, role, warehouse, size, start/end.
4.  Capture total, compilation, execution, queueing, provisioning,
    blocking, and spill.
5.  Open Query Profile and identify expensive operators.
6.  Check partitions/bytes/rows scanned and produced.
7.  Check join cardinality, aggregation, sorting, concurrency, and
    overlap.
8.  Compare historical executions.
9.  Check SQL, data, warehouse, and application changes.
10. Determine root cause.
11. Apply minimum remediation.
12. Re-run safely and compare baseline.
13. Monitor and document.

## 76.92 High Queue Time Runbook

Capture warehouse/query IDs and queue time; identify concurrent
workloads, batches, BI/ad-hoc, and long queries; inspect
warehouse/multi-cluster config; optimize/isolate/reschedule; scale only
when justified; validate queue reduction and cost.

## 76.93 High Spill Runbook

Capture query/profile/spilling operator/local/remote spill; inspect
joins, aggregations, sorts, windows, intermediate rows, columns, and
filters; optimize; test larger warehouse only when justified; compare
runtime/spill/cost.

## 76.94 Excessive Scan Runbook

Capture query/table/size/partitions; review filters, selectivity, access
pattern, history, growth, and distribution; evaluate clustering or
Search Optimization only when justified; retest and compare.

## 76.95 Join Explosion Runbook

Identify join; capture left/right/output rows; review keys, uniqueness,
duplicates, predicates, and expected cardinality; fix SQL/data; rerun
and compare.

## 76.96 Application Slowness Runbook

If Snowflake runtime is normal, compare end-to-end latency and check
connection acquisition, network, result size, fetch, serialization,
application processing, retries, and downstream calls.

## 76.97 Patient360 Incident

Patient search reports 45 seconds versus a normal 4 seconds.

## 76.98 Initial Evidence

``` text
Snowflake total elapsed: 43 sec
Execution:                5 sec
Queued overload:         37 sec
Remote spill:             0
```

## 76.99 Interpretation

Most latency is warehouse queueing; SQL execution remains near normal.

## 76.100 Further Investigation

Patient360 API, large ETL batch, and ad-hoc analytics are using the same
warehouse.

## 76.101 Root Cause

Workload contention on a shared warehouse rather than an inherently slow
Patient360 query.

## 76.102 Immediate Mitigation

Move/stop noncritical workload, temporarily scale, or use multi-cluster
capacity as appropriate.

## 76.103 Long-Term Fix

Consider separate APP, ETL, and BI warehouses where workload/cost
analysis supports isolation.

## 76.104 Query Slowness RCA Template

``` text
Incident:
Environment:
Application:
Start:
End:
Customer impact:

Affected query:
Query ID:
Warehouse:

Normal runtime:
Incident runtime:

Compilation:
Execution:
Queueing:
Provisioning:
Transaction blocking:
Local spill:
Remote spill:

Query Profile finding:
Concurrency finding:
Data-volume finding:
Application finding:

Root cause:
Contributing factors:

Immediate mitigation:
Permanent remediation:
Preventive monitoring:
Owner:
```

## 76.105 Performance Baselines

Maintain P50/P95/P99 for critical workloads.

## 76.106 Queueing Baseline

Monitor queueing trends before customers report slowness.

## 76.107 Spill Monitoring

Identify queries repeatedly spilling to remote storage.

## 76.108 Query Regression

Monitor critical query runtime over time.

## 76.109 Workload Isolation

Prevent unrelated workloads from competing unnecessarily.

## 76.110 Query Tagging

Tag critical applications for easy workload attribution.

## 76.111 Cost and Performance Together

Evaluate runtime improvements together with credit impact.

## 76.112 Common Mistakes

Avoid resizing before diagnosis, vague slowness claims, missing query
IDs/baselines, ignoring
queue/compilation/blocking/profile/spill/pruning/join issues, hiding bad
joins with DISTINCT, assuming LIMIT makes queries cheap, ignoring data
growth/concurrency/application/network, testing only cached results,
changing multiple variables simultaneously, and missing
before/after/cost/RCA evidence.

## 76.113 Recommended Standards

Capture query ID; measure before changing; separate queueing from
execution; use Query Profile; compare good and bad executions; track
P50/P95/P99; monitor queueing/spill/growth; review pruning/cardinality;
isolate workloads; use query tags; measure application latency
separately; test resizing scientifically; measure cost; document
evidence; create preventive alerts.

## 76.114 Query Slowness Checklist

-   [ ] Customer impact confirmed
-   [ ] Incident window recorded
-   [ ] Query ID captured
-   [ ] Warehouse and size captured
-   [ ] Historical baseline captured
-   [ ] Total/compilation/execution measured
-   [ ] Queueing/provisioning/blocking measured
-   [ ] Local/remote spill measured
-   [ ] Query Profile reviewed
-   [ ] Partitions/bytes scanned reviewed
-   [ ] Join cardinality/aggregation/sorting reviewed
-   [ ] Concurrency/workload overlap reviewed
-   [ ] Data growth/SQL/warehouse changes reviewed
-   [ ] Application/network/client latency considered
-   [ ] Root cause established
-   [ ] Remediation validated
-   [ ] Cost impact measured
-   [ ] Preventive action documented

## 76.115 Troubleshooting Flow

``` text
QUERY SLOW
   |
   v
GET QUERY ID
   |
   v
BREAK DOWN TIME
   |
   +--> Queueing High ------> CONCURRENCY / WAREHOUSE
   +--> Compilation High ---> SQL COMPLEXITY
   +--> Transaction Blocked -> TRANSACTIONS
   +--> Execution High
           |
           v
       QUERY PROFILE
           |
       +---+---+---+
       |       |   |
      Scan    Join Spill
       |       |   |
       v       v   v
    Pruning Cardinality Memory /
                      Intermediate Data
```

## 76.116 Query Performance Principles

1.  "Snowflake is slow" is not a root cause.
2.  Capture query ID and historical baseline.
3.  Separate queueing, provisioning, blocking, compilation, and
    execution.
4.  Use Query Profile for execution problems.
5.  Review bytes/partitions scanned and pruning.
6.  Data growth can slow unchanged SQL.
7.  Validate join cardinality.
8.  Monitor aggregation, sorting, windows, and spill.
9.  Remote spill is an important warning signal.
10. Optimize intermediate data before simply scaling.
11. Bigger warehouses do not fix every problem.
12. Concurrency and workload overlap matter.
13. Multi-cluster primarily addresses concurrency patterns.
14. Workload isolation improves predictability.
15. Snowflake and application runtimes are different.
16. Result transfer, client fetch, and network can create latency.
17. Cache can distort benchmarks.
18. Compare good and bad executions.
19. Change one major variable at a time.
20. Measure runtime and cost before/after.
21. Tag critical workloads.
22. Monitor P50/P95/P99, queueing, and spill.
23. Capture evidence before remediation.
24. RCA should identify the actual timing component.
25. Diagnose before resizing.

## 76.117 Chapter Completion Checklist

After completing this chapter, you should be able to triage Snowflake
query slowness; determine scope; identify query IDs; establish
baselines; decompose runtime; diagnose queueing, provisioning,
transaction blocking, compilation, and execution; use Query Profile;
investigate scans/pruning/data growth/join
explosions/aggregation/sorts/spilling; determine resize suitability;
analyze concurrency/workload isolation/multi-cluster use cases; separate
Snowflake and application latency; investigate result/client/network
latency; compare good and bad executions; execute
queueing/spill/scan/join/application runbooks; produce evidence-based
RCA; and establish preventive performance monitoring.

**Chapter 76 --- Snowflake Query Slowness Troubleshooting: Complete**
