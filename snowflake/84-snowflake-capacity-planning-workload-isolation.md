# Chapter 84 --- Snowflake Capacity Planning & Workload Isolation

## 84.1 Overview

Snowflake capacity planning is not simply:

``` text
Choose a large warehouse
```

A production capacity strategy must balance:

``` text
Performance
Concurrency
Workload isolation
Availability
Growth
Cost
Operational headroom
```

The objective is:

``` text
Right workload
     +
Right warehouse
     +
Right concurrency model
     +
Right isolation
     +
Right cost
     =
Predictable production performance
```

**Primary rule: Size and isolate Snowflake workloads using measured
production behavior, not assumptions.**

## 84.2 Capacity Planning Goals

A production capacity plan should answer:

``` text
What workloads exist?
How much compute do they require?
How concurrent are they?
What are their SLAs?
When do they run?
How fast are they growing?
Which workloads can safely share compute?
How much headroom is required?
What does the capacity cost?
```

## 84.3 Snowflake Capacity Model

At a high level:

``` text
WORKLOAD
   |
   v
QUERY VOLUME
   |
   v
CONCURRENCY
   |
   v
QUERY COMPLEXITY
   |
   v
WAREHOUSE CAPACITY
   |
   v
PERFORMANCE + COST
```

Capacity planning must evaluate all of these dimensions.

## 84.4 Workload Inventory

Start by identifying every significant Snowflake workload.

Example:

``` text
Patient360 API
EMPI ETL
Clinical analytics
Finance BI
Ad-hoc analytics
Data science
Snowpipe ingestion
Scheduled exports
Data quality
Maintenance
```

## 84.5 Workload Classification

Classify each workload.

``` text
Interactive application
Batch ETL
ELT transformation
BI/dashboard
Ad-hoc analytics
Data science
Ingestion
Operational monitoring
Administration
```

Different workloads have different capacity requirements.

## 84.6 Workload Profile

For each workload capture:

``` text
Owner
Environment
Service
Warehouse
Role
Query tag
Query volume
Concurrency
Query duration
Data scanned
Schedule
SLA
Growth rate
Criticality
Cost center
```

## 84.7 SLA First

Capacity planning begins with business requirements.

Example:

``` text
Patient360 API
P95 response < 5 sec

EMPI ETL
Complete within 45 min

BI dashboards
P95 < 10 sec
```

Without an SLA, there is no objective definition of sufficient capacity.

## 84.8 Interactive vs Batch

Interactive workload:

``` text
User waiting
Low latency required
Unpredictable arrival
Sensitive to queueing
```

Batch workload:

``` text
Scheduled
High throughput
Longer latency acceptable
Often resource intensive
```

These workloads should not automatically share the same warehouse.

## 84.9 Shared Warehouse Risk

``` text
                    PROD_WH
                       |
        +--------------+--------------+
        |              |              |
        v              v              v
   Patient360        EMPI ETL       BI
      API
```

When ETL or BI demand increases, application queries can queue.

## 84.10 Workload Isolation

Better:

``` text
PATIENT360_APP_WH
        |
        v
 Patient360 API

EMPI_ETL_WH
        |
        v
    EMPI ETL

BI_PROD_WH
        |
        v
   Dashboards
```

## 84.11 Benefits of Isolation

Workload isolation provides:

``` text
Predictable latency
Reduced noisy-neighbor impact
Independent scaling
Independent suspension
Better cost attribution
Simpler troubleshooting
Smaller incident blast radius
Workload-specific SLAs
```

## 84.12 Isolation Trade-Off

Isolation can increase the number of warehouses.

Therefore:

``` text
Isolation
   +
Auto suspend
   +
Right sizing
   +
Monitoring
   =
Controlled architecture
```

Do not consolidate everything solely to reduce warehouse count.

## 84.13 When Sharing Can Be Reasonable

Sharing may be reasonable when workloads:

``` text
Have similar SLAs
Have similar usage patterns
Do not create harmful contention
Have predictable concurrency
Have compatible cost ownership
```

Validate with measurements.

## 84.14 When to Separate

Strong candidates for separation include:

``` text
Interactive application vs ETL
Production vs development
Critical vs noncritical
BI vs heavy transformation
Ad-hoc vs application
Different business units with independent cost ownership
```

## 84.15 Baseline Before Sizing

Establish:

``` text
P50 latency
P95 latency
P99 latency
Execution time
Queue time
Query volume
Peak concurrency
Warehouse credits
Data volume
```

before changing capacity.

## 84.16 Query Timing

Use query history to distinguish execution from queueing.

``` sql
SELECT
    QUERY_ID,
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
ORDER BY START_TIME DESC;
```

## 84.17 Capacity Question

If:

``` text
Execution high
Queue low
```

investigate execution capacity/query efficiency.

If:

``` text
Execution normal
Queue high
```

investigate concurrency capacity.

## 84.18 Scale Up

Scale up means using a larger warehouse.

Conceptually:

``` text
SMALL
  |
  v
MEDIUM
  |
  v
LARGE
```

This increases compute resources available to the warehouse cluster.

## 84.19 Scale Up Use Case

Example:

``` text
One large transformation
Queue = 0
Execution = 20 min
```

Test whether a larger warehouse materially reduces execution time.

## 84.20 Scale Up Validation

Do not assume doubling warehouse size halves runtime.

Measure:

``` text
Runtime before
Runtime after
Credits before
Credits after
SLA improvement
```

## 84.21 Cost/Performance Test

Example:

``` text
MEDIUM
Runtime: 20 min
Cost: X

LARGE
Runtime: 12 min
Cost: Y
```

Evaluate whether the runtime improvement justifies the credit
consumption.

## 84.22 Scale Out

Scale out means increasing concurrency capacity using additional
warehouse clusters where multi-cluster configuration is appropriate.

``` text
             WAREHOUSE
                 |
       +---------+---------+
       |         |         |
       v         v         v
   Cluster 1 Cluster 2 Cluster 3
```

## 84.23 Scale Out Use Case

Example:

``` text
100 concurrent dashboard queries
Execution per query normal
Queue time high
```

Additional concurrency capacity may help.

## 84.24 Scale Up vs Scale Out

``` text
Problem                     Direction

Slow individual execution   Scale up / optimize
High concurrency queue       Scale out / isolate
Mixed workloads              Isolate
Bad SQL                      Optimize SQL
Transaction blocking         Fix transaction pattern
Provisioning delay           Review warehouse lifecycle
```

## 84.25 Warehouse Size Is Not Capacity Planning

A warehouse may be large and still have poor workload architecture.

``` text
2X-LARGE warehouse
       |
       +--> API
       +--> ETL
       +--> BI
       +--> Ad-hoc
       +--> Data science
```

Increasing size does not eliminate workload interference.

## 84.26 Peak Concurrency

Measure the maximum and percentile concurrency during normal business
hours, peak hours, batch windows, month-end, quarter-end, and special
events.

## 84.27 Average Is Dangerous

``` text
Average concurrency = 10
Peak concurrency = 120
```

Sizing only for average load can create severe queueing.

## 84.28 Percentile-Based Planning

Use P50, P95, P99, and peak rather than only averages.

## 84.29 Query Volume Trend

Track queries/hour, queries/day, and queries/month by workload.

Growth in query count can become a capacity issue even when individual
SQL remains unchanged.

## 84.30 Data Growth

Track table size, rows, partitions, files, and historical retention
because larger datasets may change query execution requirements.

## 84.31 Workload Growth

Capacity planning should model current demand and 3-month, 6-month, and
12-month demand for critical systems.

## 84.32 Simple Growth Model

Example:

``` text
Current peak concurrency: 50
Monthly growth:            10%
```

Future demand should be modeled before the current configuration reaches
its operational limit.

## 84.33 Headroom

Do not operate critical production workloads continuously at maximum
observed capacity.

Headroom protects against:

``` text
Traffic spikes
Batch overlap
Unexpected queries
Business growth
Retry storms
Failover conditions
Deployment events
```

## 84.34 Headroom Is Workload Specific

A critical API may require more reserve capacity than a nightly batch
process.

Define headroom based on business risk.

## 84.35 Burst Capacity

Interactive workloads often experience bursts.

``` text
Normal concurrency: 15
Short burst:        80
```

Design for the SLA during realistic bursts.

## 84.36 Sustained Growth

If concurrency grows:

``` text
20 -> 30 -> 50 -> 70
```

over several months, temporary scaling is not a long-term capacity
strategy.

Review architecture.

## 84.37 Scheduling

Bad:

``` text
01:00 EMPI ETL
01:00 Claims ETL
01:00 BI refresh
01:00 Data quality
01:00 Export
```

## 84.38 Schedule Staggering

Better where dependencies allow:

``` text
01:00 EMPI ETL
01:15 Claims ETL
01:30 Data quality
01:45 BI refresh
02:00 Export
```

## 84.39 Dependency-Aware Scheduling

Do not stagger blindly.

Respect data dependencies, SLA deadlines, downstream consumers, and
recovery windows.

## 84.40 Query Tagging

``` sql
ALTER SESSION SET QUERY_TAG =
'env=prod;service=patient360;workload=api';
```

ETL:

``` sql
ALTER SESSION SET QUERY_TAG =
'env=prod;service=empi;workload=etl';
```

## 84.41 Service Accounts

Use workload-specific identities.

``` text
SVC_PATIENT360
SVC_EMPI_ETL
SVC_BI
SVC_DATA_QUALITY
```

This improves security, attribution, monitoring, and troubleshooting.

## 84.42 Warehouse Ownership

Every warehouse should have owner, purpose, workloads, SLA, size,
scaling model, cost center, resource monitor, and runbook.

## 84.43 Warehouse Naming

Good:

``` text
PATIENT360_APP_PROD_WH
EMPI_ETL_PROD_WH
BI_PROD_WH
```

Avoid:

``` text
WH1
WH_NEW
TEMP_WH
```

for long-lived production resources.

## 84.44 Warehouse Lifecycle

Capacity planning includes `AUTO_SUSPEND` and `AUTO_RESUME`, not only
size.

## 84.45 Auto-Suspend

Set auto-suspend according to workload behavior.

Too long creates idle credits. Too short can create frequent resume
cycles and potential startup latency.

## 84.46 Auto-Resume

For workloads requiring automatic availability, configure auto-resume
appropriately and measure resume/provisioning impact against SLA.

## 84.47 Provisioning Time

Monitor:

``` text
QUEUED_PROVISIONING_TIME
```

If it becomes material, warehouse lifecycle configuration may need
review.

## 84.48 Multi-Cluster Configuration

For suitable concurrency-heavy workloads, document:

``` text
MIN_CLUSTER_COUNT
MAX_CLUSTER_COUNT
SCALING_POLICY
```

along with the reason for each setting.

## 84.49 Minimum Clusters

A larger minimum can reduce some scale-out responsiveness concerns but
increases baseline compute consumption.

Choose based on workload requirements.

## 84.50 Maximum Clusters

Maximum cluster count limits concurrency scale-out and cost exposure.

Do not choose it arbitrarily.

## 84.51 Scaling Policy

Choose scaling behavior based on latency tolerance, concurrency pattern,
SLA, and cost tolerance.

Validate with actual workload tests.

## 84.52 Application Connection Pools

Example:

``` text
25 Kubernetes pods
x
20 max DB connections
=
500 possible connections
```

## 84.53 Sessions Are Not Queries

A connection/session does not necessarily mean a running query.

Still, application pool configuration influences potential concurrency.

## 84.54 Kubernetes Autoscaling

``` text
5 pods
   |
   v
50 pods
```

If every pod can submit concurrent Snowflake queries, database demand
can increase rapidly.

## 84.55 Autoscaling Coordination

Application teams and data platform teams should jointly define:

``` text
Max application replicas
Connection pool limits
Request concurrency
Snowflake concurrency expectations
Retry policy
```

## 84.56 Retry Capacity

Retries consume capacity.

Capacity planning must consider failure behavior, not only healthy-state
traffic.

## 84.57 Retry Storm Model

``` text
100 requests
     |
     v
Timeout
     |
     v
100 retries
     |
     v
200 requests
```

Repeated retries can multiply demand.

## 84.58 Retry Standards

Use bounded retries, exponential backoff, jitter, timeout budgets,
circuit breaking where appropriate, and idempotency.

## 84.59 BI Capacity

``` text
1 dashboard
20 widgets
100 users
```

Potential demand may be much greater than user count suggests.

## 84.60 BI Refresh Schedules

Coordinate dashboard refresh, extract refresh, semantic model refresh,
and scheduled reports with other production workloads.

## 84.61 ETL Capacity

For ETL measure rows processed, bytes processed, execution time,
warehouse size, credits, schedule, and concurrency.

## 84.62 ETL Throughput

Useful metrics include rows processed/minute or GB processed/minute
depending on the workload.

## 84.63 Cost per Workload

Where attribution permits, estimate credits per pipeline, dashboard
workload, application, and environment.

## 84.64 Performance per Credit

A larger warehouse can cost more per unit time but finish work faster.

Evaluate total credits, runtime, SLA, and throughput together.

## 84.65 Resource Monitors

Use resource monitors where appropriate to control warehouse credit
consumption.

Capacity planning without cost controls is incomplete.

## 84.66 Resource Monitor Caution

For critical production workloads, understand the impact of actions that
can suspend compute.

A cost-control action should not unexpectedly become a production
outage.

## 84.67 Development Isolation

Separate DEV, TEST, STAGING, and PROD appropriately.

Development experiments should not compete with critical production
workloads.

## 84.68 Ad-Hoc Isolation

Ad-hoc analytics can be unpredictable.

A dedicated warehouse provides blast-radius control, independent
scaling, independent cost, and simpler governance.

## 84.69 Data Science Isolation

Data science workloads may generate large scans, experimental SQL,
long-running transformations, and unpredictable concurrency.

Consider separate compute.

## 84.70 Production API Isolation

Latency-sensitive production APIs are strong candidates for dedicated
compute.

The objective is predictable application latency.

## 84.71 Batch Isolation

Heavy batch workloads should generally not interfere with
latency-sensitive applications when isolation is practical.

## 84.72 Environment Matrix

  Workload         Environment   Warehouse                SLA
  ---------------- ------------- ------------------------ ---------------
  Patient360 API   Prod          PATIENT360_APP_PROD_WH   P95 \< 5 sec
  EMPI ETL         Prod          EMPI_ETL_PROD_WH         \< 45 min
  BI               Prod          BI_PROD_WH               P95 \< 10 sec
  Ad-hoc           Prod          ANALYST_PROD_WH          Best effort

## 84.73 Capacity Dashboard

Recommended dashboard:

``` text
Warehouse state
Warehouse size
Cluster count
Query volume
Concurrent queries
P50/P95/P99 total latency
P50/P95/P99 execution
P50/P95/P99 queue
Provisioning time
Transaction blocking
Credits
Application latency
Retry rate
```

## 84.74 Query Volume SQL

``` sql
SELECT
    DATE_TRUNC('hour', START_TIME) AS HOUR,
    WAREHOUSE_NAME,
    COUNT(*) AS QUERY_COUNT
FROM SNOWFLAKE.ACCOUNT_USAGE.QUERY_HISTORY
WHERE START_TIME >= DATEADD('day', -7, CURRENT_TIMESTAMP())
GROUP BY
    DATE_TRUNC('hour', START_TIME),
    WAREHOUSE_NAME
ORDER BY HOUR, WAREHOUSE_NAME;
```

## 84.75 Queue Trend SQL

``` sql
SELECT
    DATE_TRUNC('hour', START_TIME) AS HOUR,
    WAREHOUSE_NAME,
    SUM(QUEUED_OVERLOAD_TIME) / 1000 AS QUEUED_SECONDS
FROM SNOWFLAKE.ACCOUNT_USAGE.QUERY_HISTORY
WHERE START_TIME >= DATEADD('day', -7, CURRENT_TIMESTAMP())
GROUP BY
    DATE_TRUNC('hour', START_TIME),
    WAREHOUSE_NAME
ORDER BY HOUR, WAREHOUSE_NAME;
```

## 84.76 Execution Trend SQL

``` sql
SELECT
    DATE_TRUNC('hour', START_TIME) AS HOUR,
    WAREHOUSE_NAME,
    SUM(EXECUTION_TIME) / 1000 AS EXECUTION_SECONDS
FROM SNOWFLAKE.ACCOUNT_USAGE.QUERY_HISTORY
WHERE START_TIME >= DATEADD('day', -7, CURRENT_TIMESTAMP())
GROUP BY
    DATE_TRUNC('hour', START_TIME),
    WAREHOUSE_NAME
ORDER BY HOUR, WAREHOUSE_NAME;
```

## 84.77 Workload Attribution SQL

``` sql
SELECT
    USER_NAME,
    ROLE_NAME,
    WAREHOUSE_NAME,
    QUERY_TYPE,
    COUNT(*) AS QUERY_COUNT,
    SUM(EXECUTION_TIME) / 1000 AS EXECUTION_SECONDS,
    SUM(QUEUED_OVERLOAD_TIME) / 1000 AS QUEUE_SECONDS
FROM SNOWFLAKE.ACCOUNT_USAGE.QUERY_HISTORY
WHERE START_TIME >= DATEADD('day', -1, CURRENT_TIMESTAMP())
GROUP BY
    USER_NAME,
    ROLE_NAME,
    WAREHOUSE_NAME,
    QUERY_TYPE
ORDER BY EXECUTION_SECONDS DESC;
```

## 84.78 Peak Windows

Identify peak query volume, peak queue time, peak execution demand, peak
business traffic, and peak batch overlap.

Do not plan from daily averages.

## 84.79 Seasonal Capacity

Account for month-end, quarter-end, year-end, open enrollment, business
campaigns, large migrations, and backfills where relevant.

## 84.80 Backfill Capacity

Large historical backfills can overwhelm normal production capacity.

Use a dedicated warehouse, controlled concurrency, defined schedule,
cost limit, and progress monitoring.

## 84.81 Migration Capacity

During migrations, temporary capacity may be needed.

Document expected data volume, ingestion rate, transformation rate,
duration, warehouse size, credits, and rollback.

## 84.82 Incident Capacity

Emergency scaling should be controlled.

Capture why, old configuration, new configuration, start time, owner,
expected effect, and rollback condition.

## 84.83 Temporary Capacity

Temporary scaling should have an explicit expiration or review.

Avoid permanent cost drift.

## 84.84 Capacity Testing

Test with representative data volume, query mix, concurrency,
application behavior, batch overlap, and retry behavior.

## 84.85 Single-Query Tests Are Insufficient

A query may perform well alone but poorly under production concurrency.

Load tests must represent actual workload interaction.

## 84.86 Production-Like Testing

A useful test includes API traffic, ETL, BI, metadata activity, and
concurrent users in realistic proportions.

## 84.87 Controlled Experiments

Change one major capacity variable at a time where practical.

``` text
Baseline
   |
   v
Increase warehouse size
   |
   v
Measure
```

Then separately test multi-cluster or workload isolation.

## 84.88 Acceptance Criteria

Before a capacity change define target latency, target queue, target
throughput, and maximum acceptable credits.

## 84.89 Example Acceptance

``` text
Patient360

P95 total Snowflake latency < 3 sec
P95 queued overload < 500 ms
P99 < 5 sec
No material error increase
Credits within approved budget
```

## 84.90 Patient360 Scenario

Current architecture:

``` text
                 SHARED_PROD_WH
                      |
        +-------------+-------------+
        |             |             |
        v             v             v
 Patient360 API    EMPI ETL        BI
```

Normal:

``` text
API P95 = 3 sec
```

During ETL:

``` text
API P95 = 35 sec
Queue = 30 sec
Execution = 3 sec
```

## 84.91 Diagnosis

The primary issue is workload contention.

The API SQL execution time remains close to baseline.

## 84.92 Proposed Architecture

``` text
PATIENT360_APP_PROD_WH
          |
          v
     Patient360

EMPI_ETL_PROD_WH
          |
          v
       EMPI

BI_PROD_WH
          |
          v
         BI
```

## 84.93 Validation

After isolation measure API P95/P99, queue, execution, ETL runtime, BI
runtime, and total credits.

Do not declare success from latency alone.

## 84.94 Cost Outcome

Isolation may increase warehouse runtime but can reduce
overprovisioning, incident frequency, retry amplification, and
unpredictable scaling.

Evaluate total operational cost.

## 84.95 Capacity Review Runbook

1.  Inventory workloads.
2.  Identify workload owners.
3.  Capture SLAs.
4.  Map warehouses.
5.  Capture warehouse configuration.
6.  Capture query volume.
7.  Capture concurrency.
8.  Capture P50/P95/P99 latency.
9.  Capture execution time.
10. Capture queue time.
11. Capture provisioning time.
12. Capture credits.
13. Identify peak windows.
14. Identify workload overlap.
15. Identify growth.
16. Identify noisy neighbors.
17. Review isolation.
18. Review scaling model.
19. Review lifecycle settings.
20. Review retry behavior.
21. Review application connection pools.
22. Review cost controls.
23. Model future demand.
24. Define remediation.
25. Validate changes.

## 84.96 Workload Isolation Runbook

1.  Identify affected workload.
2.  Identify shared warehouse.
3.  List other workloads.
4.  Compare SLAs.
5.  Compare schedules.
6.  Measure contention.
7.  Identify cost owners.
8.  Create isolation hypothesis.
9.  Test separate compute.
10. Compare performance.
11. Compare cost.
12. Validate application SLA.
13. Document ownership.
14. Monitor.

## 84.97 Warehouse Sizing Runbook

1.  Establish baseline.
2.  Identify execution-bound workload.
3.  Capture warehouse size.
4.  Capture runtime.
5.  Capture credits.
6.  Resize in controlled test.
7.  Repeat workload.
8.  Compare runtime.
9.  Compare credits.
10. Compare SLA.
11. Choose best cost/performance point.
12. Document result.

## 84.98 Concurrency Capacity Runbook

1.  Confirm overload queueing.
2.  Measure peak concurrency.
3.  Identify workload mix.
4.  Identify burst vs sustained load.
5.  Review multi-cluster configuration.
6.  Review workload isolation.
7.  Review retry behavior.
8.  Test concurrency capacity.
9.  Validate queue reduction.
10. Validate cost.
11. Establish alerting.
12. Document limit.

## 84.99 Growth Planning Runbook

1.  Capture current query volume.
2.  Capture current data volume.
3.  Capture current concurrency.
4.  Calculate growth trend.
5.  Identify seasonal events.
6.  Forecast 3 months.
7.  Forecast 6 months.
8.  Forecast 12 months.
9.  Model capacity requirements.
10. Model cost.
11. Define trigger thresholds.
12. Review quarterly.

## 84.100 Capacity Trigger

Do not wait for an incident.

Example:

``` text
If P95 queue exceeds 1 second
for 20% of peak business windows,
initiate capacity review.
```

Another:

``` text
If peak concurrency reaches 80%
of tested capacity,
begin expansion planning.
```

Thresholds should be evidence-based and workload-specific.

## 84.101 Capacity Readiness Review

Before a major launch verify expected users, expected QPS, expected
concurrency, connection pools, retry behavior, warehouse sizing,
multi-cluster configuration, workload isolation, cost budget,
monitoring, alerts, and rollback.

## 84.102 Evidence Package

Capture warehouse configuration, workload inventory, SLA, query volume,
concurrency, P50/P95/P99, queue, execution, provisioning, data growth,
query growth, credits, peak windows, application replicas, connection
pools, retry configuration, BI fan-out, batch schedule, and growth
forecast.

## 84.103 Capacity Planning Template

``` text
Workload:
Owner:
Environment:
Business criticality:

Warehouse:
Current size:
Min clusters:
Max clusters:
Scaling policy:
Auto suspend:
Auto resume:

P50 latency:
P95 latency:
P99 latency:

P95 execution:
P95 queue:
P95 provisioning:

Average query volume:
Peak query volume:
Average concurrency:
Peak concurrency:

Current data volume:
Monthly data growth:
Monthly query growth:

Application replicas:
Connection pool max:
Retry policy:

SLA:
Headroom target:

Current credits/day:
Projected credits/day:

3-month forecast:
6-month forecast:
12-month forecast:

Recommended architecture:

Recommended size:
Recommended isolation:
Recommended scaling model:

Trigger for next review:

Owner:
Review date:
```

## 84.104 Common Mistakes

Avoid:

``` text
Sizing from averages only
Ignoring peak concurrency
Ignoring P95/P99
Treating warehouse size as the entire capacity strategy
Sharing all workloads
Mixing API and ETL without measurement
Scaling up for queueing
Scaling out for one slow query
Ignoring SQL efficiency
Ignoring transaction blocking
Ignoring provisioning
Ignoring connection pools
Ignoring Kubernetes autoscaling
Ignoring retries
Ignoring BI fan-out
Ignoring batch overlap
Ignoring data growth
Ignoring query growth
No headroom
No cost analysis
No workload owner
No warehouse owner
No query tags
No capacity baseline
No growth forecast
No acceptance criteria
No rollback plan
Leaving temporary scaling permanently
```

## 84.105 SRE/DBRE Checklist

-   [ ] Workloads inventoried
-   [ ] Owners identified
-   [ ] SLAs documented
-   [ ] Warehouses mapped
-   [ ] Query tags established
-   [ ] Service accounts identified
-   [ ] Query volume measured
-   [ ] Peak concurrency measured
-   [ ] P50/P95/P99 measured
-   [ ] Execution measured
-   [ ] Queue measured
-   [ ] Provisioning measured
-   [ ] Credits measured
-   [ ] Data growth measured
-   [ ] Query growth measured
-   [ ] Peak windows identified
-   [ ] Batch overlap reviewed
-   [ ] BI fan-out reviewed
-   [ ] Application connection pools reviewed
-   [ ] Kubernetes autoscaling reviewed
-   [ ] Retry behavior reviewed
-   [ ] Workload isolation reviewed
-   [ ] Scale-up requirement reviewed
-   [ ] Scale-out requirement reviewed
-   [ ] Multi-cluster configuration reviewed
-   [ ] Auto-suspend/resume reviewed
-   [ ] Resource monitors reviewed
-   [ ] Headroom defined
-   [ ] Seasonal events modeled
-   [ ] 3/6/12-month forecast created
-   [ ] Acceptance criteria defined
-   [ ] Cost impact reviewed
-   [ ] Monitoring configured
-   [ ] Capacity review schedule established

## 84.106 Decision Tree

``` text
PERFORMANCE / CAPACITY CONCERN
             |
             v
       IDENTIFY WORKLOAD
             |
             v
       DEFINE SLA
             |
             v
       BREAK DOWN TIME
             |
      +------+------+
      |             |
      v             v
 EXECUTION HIGH   QUEUE HIGH
      |             |
      v             v
OPTIMIZE /       CONCURRENCY
SCALE UP         ANALYSIS
                    |
              +-----+-----+
              |           |
              v           v
          BURST        SUSTAINED
              |           |
              v           v
        SCALE OUT /    ISOLATE /
        HEADROOM       EXPAND
              |
              v
       CHECK WORKLOAD MIX
              |
              v
       NOISY NEIGHBOR?
          /       \
        Yes        No
         |          |
         v          v
      ISOLATE    RIGHT-SIZE
         |
         v
   VALIDATE SLA + COST
         |
         v
     FORECAST GROWTH
```

## 84.107 Key Principles

1.  Capacity planning starts with workload requirements.
2.  Define SLAs before sizing.
3.  Inventory every important workload.
4.  Classify workloads by behavior.
5.  Interactive and batch workloads have different needs.
6.  Workload isolation reduces noisy-neighbor impact.
7.  Isolation improves troubleshooting.
8.  Isolation improves cost attribution.
9.  Sharing compute should be an intentional decision.
10. Baseline before changing capacity.
11. Measure execution separately from queueing.
12. Scale up and scale out solve different problems.
13. Do not scale up blindly for concurrency.
14. Do not scale out blindly for slow SQL.
15. Warehouse size alone is not capacity architecture.
16. Measure peak concurrency.
17. Do not size from averages only.
18. Use P50/P95/P99.
19. Monitor query-volume growth.
20. Monitor data growth.
21. Forecast future demand.
22. Maintain workload-specific headroom.
23. Design for realistic bursts.
24. Treat sustained growth as an architecture signal.
25. Schedule batch workloads intentionally.
26. Stagger jobs where dependencies allow.
27. Use query tags.
28. Use dedicated service identities.
29. Assign warehouse ownership.
30. Use descriptive warehouse names.
31. Tune auto-suspend/resume to workload behavior.
32. Monitor provisioning delay.
33. Configure multi-cluster warehouses based on measured concurrency.
34. Include connection pools in capacity planning.
35. Include application autoscaling.
36. Include retry amplification.
37. Include BI fan-out.
38. Measure performance per credit.
39. Use resource monitors carefully.
40. Isolate development and ad-hoc workloads appropriately.
41. Test production-like concurrency.
42. Define acceptance criteria before changes.
43. Measure performance and cost after changes.
44. Track temporary capacity changes.
45. Create 3/6/12-month forecasts.
46. Establish proactive capacity triggers.
47. Review capacity before major launches.
48. Review capacity after incidents.
49. Revisit capacity as workloads evolve.
50. Capacity planning is continuous SRE/DBRE work.

## 84.108 Chapter Completion Checklist

After completing this chapter, you should be able to:

-   Build a Snowflake workload inventory.
-   Classify workloads by operational behavior.
-   Define workload-specific SLAs.
-   Design workload isolation.
-   Decide when warehouses can safely be shared.
-   Establish performance baselines.
-   Distinguish execution-bound from concurrency-bound workloads.
-   Explain scale-up vs scale-out.
-   Test warehouse sizing.
-   Design multi-cluster capacity.
-   Measure peak concurrency.
-   Use percentile-based capacity planning.
-   Model query and data growth.
-   Define operational headroom.
-   Design burst and sustained-load capacity.
-   Stagger batch workloads safely.
-   Attribute capacity using query tags and service identities.
-   Define warehouse ownership standards.
-   Tune warehouse lifecycle settings.
-   Include application connection pools and Kubernetes autoscaling in
    capacity planning.
-   Account for retry amplification.
-   Model BI and ETL capacity.
-   Evaluate performance per credit.
-   Design development, ad-hoc, data-science, API, and batch isolation.
-   Build a production capacity dashboard.
-   Plan backfill and migration capacity.
-   Execute capacity-review, isolation, sizing, concurrency, and
    growth-planning runbooks.
-   Define proactive capacity triggers.
-   Perform launch-readiness capacity reviews.
-   Create a 3/6/12-month Snowflake capacity forecast.
-   Balance SLA, performance, growth, resilience, and cost.

**Chapter 84 --- Snowflake Capacity Planning & Workload Isolation:
Complete**
