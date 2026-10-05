# 47 — Query History & Workload Analysis

## Overview

Query History is one of the most important operational data sources in Snowflake.

It answers questions such as:

```text
What queries are running?
Who submitted them?
Which warehouse executed them?
Which workload generated them?
How long did they take?
How much time was spent queued?
How much data was scanned?
Did they spill?
Did they fail?
Which queries consume the most resources?
When does workload peak?
Which applications are driving growth?
```

But production workload analysis requires more than sorting queries by execution time.

A complete investigation should correlate:

```text
Query
  |
  +---- User
  +---- Role
  +---- Warehouse
  +---- Query tag
  +---- Application
  +---- Time
  +---- Queue
  +---- Execution
  +---- Scan
  +---- Spill
  +---- Result size
  +---- Failure
  +---- Workload pattern
```

This chapter develops a production-focused framework for analyzing Snowflake query workloads.

It covers:

- Query History
- recent versus historical telemetry
- query IDs
- query status
- elapsed time
- execution time
- compilation time
- queue time
- bytes scanned
- partitions scanned
- spill
- rows produced
- workload attribution
- users
- roles
- warehouses
- query tags
- client applications
- query-volume analysis
- hourly and daily patterns
- P50/P95/P99
- query fingerprints
- repeated workloads
- slow-query families
- concurrency
- queueing
- workload isolation
- failures
- regression analysis
- baseline comparison
- capacity planning
- incident investigation
- operational dashboards
- alerting
- FinOps correlation
- hands-on workload analysis

---

# Part 1 — Query History as Operational Evidence

## 1. Why Query History Matters

During a Snowflake incident, Query History often becomes the starting point.

Suppose users report:

> The application became slow around 14:00 UTC.

The investigation can begin with:

```text
14:00 UTC
    |
    v
Query History
    |
    +---- Query count
    +---- Latency
    +---- Queueing
    +---- Warehouse
    +---- User
    +---- Query tag
    +---- Scan
    +---- Spill
    +---- Failures
```

This converts a subjective report into measurable evidence.

---

# Part 2 — Query ID

## 2. Primary Investigation Identifier

Every important performance investigation should capture query IDs.

Conceptually:

```text
Incident
   |
   v
Query ID
   |
   +---- Query History
   +---- Query Profile
   +---- User
   +---- Warehouse
   +---- Timing
   +---- Error
```

A query ID provides a precise reference for investigation.

---

# Part 3 — Representative Queries

## 3. Do Not Capture Only One Query

During an incident, collect representative examples.

Ideally:

```text
Slow query
Fast query
Failed query
Queued query
High-scan query
High-spill query
```

Comparing them is often more useful than examining one isolated execution.

---

# Part 4 — Recent vs Historical Investigation

## 4. Recent Investigation

During an active incident, freshness matters.

Use the appropriate Snowflake query-history interface for the required time window and freshness.

## 5. Historical Investigation

For longer-term analysis, account-level historical telemetry is commonly used.

Example:

```sql
SNOWFLAKE.ACCOUNT_USAGE.QUERY_HISTORY
```

Always validate current latency, retention, privileges, and columns for the interface being used.

---

# Part 5 — Basic Query History

## 6. Example

```sql
SELECT
    query_id,
    user_name,
    role_name,
    warehouse_name,
    warehouse_size,
    start_time,
    end_time,
    execution_status,
    total_elapsed_time,
    execution_time,
    bytes_scanned,
    rows_produced,
    query_text
FROM SNOWFLAKE.ACCOUNT_USAGE.QUERY_HISTORY
WHERE start_time >= DATEADD(hour, -4, CURRENT_TIMESTAMP())
ORDER BY start_time DESC;
```

This provides a useful first-level operational view.

---

# Part 6 — Always Bound the Time Window

## 7. Avoid Unbounded Analysis

Do not start incident troubleshooting with:

```sql
SELECT *
FROM SNOWFLAKE.ACCOUNT_USAGE.QUERY_HISTORY;
```

Instead:

```sql
WHERE start_time >= :incident_start
  AND start_time < :incident_end
```

This improves relevance and operational efficiency.

---

# Part 7 — Timezone Discipline

## 8. Correlation

Suppose:

```text
Application logs = UTC
Monitoring       = UTC
Snowflake session = local timezone
```

Without normalization, the same incident may appear to occur at different times.

For production operations, explicitly document the timezone.

---

# Part 8 — Query Status

## 9. Important States

Queries can represent successful, failed, cancelled, or otherwise incomplete activity depending on the telemetry interface.

Do not analyze only successful queries during incidents.

Failures can be the most important signal.

---

# Part 9 — Successful Queries

## 10. Example

```sql
SELECT
    query_id,
    start_time,
    warehouse_name,
    total_elapsed_time,
    query_text
FROM SNOWFLAKE.ACCOUNT_USAGE.QUERY_HISTORY
WHERE start_time >= DATEADD(hour, -1, CURRENT_TIMESTAMP())
  AND execution_status = 'SUCCESS'
ORDER BY total_elapsed_time DESC;
```

Validate current status values before using them in automated tooling.

---

# Part 10 — Failed Queries

## 11. Example

```sql
SELECT
    query_id,
    user_name,
    role_name,
    warehouse_name,
    start_time,
    error_code,
    error_message,
    query_text
FROM SNOWFLAKE.ACCOUNT_USAGE.QUERY_HISTORY
WHERE start_time >= DATEADD(hour, -24, CURRENT_TIMESTAMP())
  AND execution_status = 'FAIL'
ORDER BY start_time DESC;
```

This helps identify recurring failure patterns.

---

# Part 11 — Failure Rate

## 12. Workload Health

Query count alone is insufficient.

Track:

```text
Total queries
Successful queries
Failed queries
Failure %
```

Example concept:

```text
Normal failure rate = 0.2%
Incident failure rate = 8.7%
```

That is a strong operational signal.

---

# Part 12 — Elapsed Time

## 13. User-Visible Perspective

Total elapsed time represents the overall query lifecycle more closely than execution time alone.

Conceptually:

```text
Query submitted
      |
      +---- Compilation
      +---- Queue
      +---- Execution
      +---- Other processing
      |
      v
Query complete
```

---

# Part 13 — Execution Time

## 14. Compute Work

Execution time helps determine how long the query spent executing after it reached the execution stage.

A query can have:

```text
Elapsed = 60 sec
Execution = 10 sec
```

This indicates most of the latency occurred outside core execution.

---

# Part 14 — Queue Time

## 15. Concurrency Evidence

A query may spend significant time waiting for warehouse resources.

Example:

```text
Elapsed     = 40 sec
Queue       = 32 sec
Execution   = 7 sec
```

The SQL may not be the primary problem.

Concurrency is the stronger investigation path.

---

# Part 15 — Queue Categories

## 16. Separate Causes

Operational telemetry may distinguish:

```text
Overload queue
Provisioning queue
Repair queue
```

Each indicates a different condition.

Do not add them together and call the result "warehouse overload" without understanding the cause.

---

# Part 16 — Overload Queue

## 17. Interpretation

Overload queueing generally indicates warehouse execution capacity was busy.

Conceptually:

```text
Concurrent queries
       |
       v
Warehouse capacity reached
       |
       v
New queries wait
```

---

# Part 17 — Provisioning Queue

## 18. Interpretation

Provisioning queue time is associated with waiting for compute resources to become available.

This may be associated with warehouse startup or scaling behavior.

It should not automatically be interpreted as concurrency overload.

---

# Part 18 — Queue Analysis

## 19. Example

```sql
SELECT
    query_id,
    warehouse_name,
    start_time,
    total_elapsed_time,
    execution_time,
    queued_overload_time,
    queued_provisioning_time,
    queued_repair_time,
    query_text
FROM SNOWFLAKE.ACCOUNT_USAGE.QUERY_HISTORY
WHERE start_time >= :incident_start
  AND start_time < :incident_end
ORDER BY queued_overload_time DESC;
```

Validate exact fields and units against current Snowflake documentation.

---

# Part 19 — Compilation Time

## 20. Compilation Matters

Not every query spends most of its time executing.

Complex SQL, metadata operations, or other query-planning activities may increase compilation-related time.

When:

```text
Elapsed >> Execution + Queue
```

investigate the remaining lifecycle components.

---

# Part 20 — Bytes Scanned

## 21. Workload Size

Bytes scanned help measure how much data a query processed.

Example:

```sql
SELECT
    query_id,
    warehouse_name,
    bytes_scanned,
    execution_time,
    query_text
FROM SNOWFLAKE.ACCOUNT_USAGE.QUERY_HISTORY
WHERE start_time >= DATEADD(day, -1, CURRENT_TIMESTAMP())
ORDER BY bytes_scanned DESC
LIMIT 25;
```

High scan volume is a signal, not automatically a defect.

---

# Part 21 — Convert Bytes

## 22. Human-Readable Reporting

For dashboards:

```sql
bytes_scanned / POWER(1024, 3) AS gb_scanned
```

This can make operational reporting easier.

Be explicit about whether you are using binary or decimal units.

---

# Part 22 — Partitions Scanned

## 23. Pruning Evidence

Where the telemetry interface exposes partition metrics, compare:

```text
Partitions scanned
Partitions total
```

Example:

```text
Scanned = 500
Total   = 100,000
```

Strong pruning.

Versus:

```text
Scanned = 95,000
Total   = 100,000
```

Weak pruning.

Query Profile remains important for detailed execution analysis.

---

# Part 23 — Spill

## 24. Memory Pressure

Query History can expose spill-related metrics.

Conceptually:

```text
Execution operator
       |
       v
Memory pressure
       |
       +---- Local spill
       |
       +---- Remote spill
```

---

# Part 24 — Local Spill

## 25. Signal

Local spill indicates intermediate data exceeded available execution memory and used local temporary storage.

It can degrade performance.

---

# Part 25 — Remote Spill

## 26. Strong Signal

Remote spill is generally more expensive than local spill.

Large remote spill should trigger investigation into:

- joins
- sorts
- aggregations
- window functions
- data skew
- warehouse size
- intermediate result volume

---

# Part 26 — Spill Analysis Query

## 27. Example

```sql
SELECT
    query_id,
    warehouse_name,
    bytes_spilled_to_local_storage,
    bytes_spilled_to_remote_storage,
    execution_time,
    query_text
FROM SNOWFLAKE.ACCOUNT_USAGE.QUERY_HISTORY
WHERE start_time >= DATEADD(day, -1, CURRENT_TIMESTAMP())
ORDER BY bytes_spilled_to_remote_storage DESC
LIMIT 25;
```

Validate exact current column names.

---

# Part 27 — Rows Produced

## 28. Result Volume

Large result sets can affect:

- execution
- result transfer
- client processing
- application memory
- network behavior

A query returning 50 million rows may not be an appropriate interactive query even if warehouse execution itself is acceptable.

---

# Part 28 — Query Text

## 29. Powerful but Sensitive

Query text helps identify:

- query patterns
- application behavior
- SQL regressions
- missing filters
- SELECT *
- new joins
- new workloads

But query text can contain sensitive information.

Treat it as protected operational data.

---

# Part 29 — Query Tag

## 30. Workload Attribution

A strong production practice is to tag workloads.

Examples:

```text
service=patient-api
pipeline=claims-load
dashboard=executive
team=data-platform
environment=prod
```

This allows workload analysis by application rather than only by user.

---

# Part 30 — Query Tagging Example

## 31. Concept

Using the current supported syntax, applications can assign a session or workload query tag.

Then Query History can answer:

```text
Which application generated these queries?
```

This becomes extremely useful during incidents.

---

# Part 31 — Workload Dimensions

## 32. Recommended Dimensions

Analyze queries by:

```text
Warehouse
User
Role
Query tag
Application
Time
Query family
Status
```

Each dimension reveals a different aspect of workload behavior.

---

# Part 32 — Queries by Warehouse

## 33. Example

```sql
SELECT
    warehouse_name,
    COUNT(*) AS query_count
FROM SNOWFLAKE.ACCOUNT_USAGE.QUERY_HISTORY
WHERE start_time >= DATEADD(day, -1, CURRENT_TIMESTAMP())
  AND warehouse_name IS NOT NULL
GROUP BY warehouse_name
ORDER BY query_count DESC;
```

This identifies where query volume is concentrated.

---

# Part 33 — Queries by User

## 34. Example

```sql
SELECT
    user_name,
    COUNT(*) AS query_count
FROM SNOWFLAKE.ACCOUNT_USAGE.QUERY_HISTORY
WHERE start_time >= DATEADD(day, -1, CURRENT_TIMESTAMP())
GROUP BY user_name
ORDER BY query_count DESC;
```

---

# Part 34 — Queries by Role

## 35. Example

```sql
SELECT
    role_name,
    COUNT(*) AS query_count
FROM SNOWFLAKE.ACCOUNT_USAGE.QUERY_HISTORY
WHERE start_time >= DATEADD(day, -1, CURRENT_TIMESTAMP())
GROUP BY role_name
ORDER BY query_count DESC;
```

---

# Part 35 — Queries by Query Tag

## 36. Example

Conceptually:

```sql
SELECT
    query_tag,
    COUNT(*) AS query_count
FROM SNOWFLAKE.ACCOUNT_USAGE.QUERY_HISTORY
WHERE start_time >= DATEADD(day, -1, CURRENT_TIMESTAMP())
GROUP BY query_tag
ORDER BY query_count DESC;
```

Validate current column availability.

---

# Part 36 — Queries per Hour

## 37. Workload Pattern

```sql
SELECT
    DATE_TRUNC('hour', start_time) AS hour,
    COUNT(*) AS query_count
FROM SNOWFLAKE.ACCOUNT_USAGE.QUERY_HISTORY
WHERE start_time >= DATEADD(day, -7, CURRENT_TIMESTAMP())
GROUP BY 1
ORDER BY 1;
```

This reveals peaks and valleys.

---

# Part 37 — Queries per Hour per Warehouse

## 38. Example

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

This can identify which warehouse drove a workload spike.

---

# Part 38 — Daily Workload

## 39. Trend

```sql
SELECT
    DATE_TRUNC('day', start_time) AS day,
    COUNT(*) AS query_count
FROM SNOWFLAKE.ACCOUNT_USAGE.QUERY_HISTORY
WHERE start_time >= DATEADD(day, -30, CURRENT_TIMESTAMP())
GROUP BY 1
ORDER BY 1;
```

Useful for growth analysis.

---

# Part 39 — Day-of-Week Pattern

## 40. Capacity Planning

Workload may vary significantly by day.

Examples:

```text
Monday = heavy batch
Friday = reporting
Weekend = maintenance
```

Capacity planning should consider recurring patterns rather than only monthly averages.

---

# Part 40 — Hour-of-Day Pattern

## 41. Peak Analysis

Analyze demand by hour.

Conceptually:

```text
00:00  low
06:00  ETL begins
08:00  BI begins
10:00  peak
18:00  declines
```

This is valuable for scheduling and workload isolation.

---

# Part 41 — Average Is Not Enough

## 42. Example

Suppose:

```text
Average latency = 2 sec
```

This can hide:

```text
P50 = 0.8 sec
P95 = 8 sec
P99 = 30 sec
```

Users often experience the tail, not the average.

---

# Part 42 — Percentiles

## 43. Recommended Metrics

Track:

```text
P50
P90
P95
P99
```

for important workloads.

Use the Snowflake percentile function appropriate to your analysis and current supported syntax.

---

# Part 43 — P50

## 44. Typical Experience

P50 represents the median query.

Half of queries are faster and half slower.

---

# Part 44 — P95

## 45. Tail Performance

P95 is often useful for production SLOs.

Example:

```text
Dashboard P95 < 5 sec
```

---

# Part 45 — P99

## 46. Severe Tail

P99 exposes the worst-performing portion of the workload.

It is useful for detecting intermittent degradation hidden by averages.

---

# Part 46 — Percentile by Warehouse

## 47. Conceptual Query

```sql
SELECT
    warehouse_name,
    APPROX_PERCENTILE(total_elapsed_time, 0.50) AS p50_ms,
    APPROX_PERCENTILE(total_elapsed_time, 0.95) AS p95_ms,
    APPROX_PERCENTILE(total_elapsed_time, 0.99) AS p99_ms
FROM SNOWFLAKE.ACCOUNT_USAGE.QUERY_HISTORY
WHERE start_time >= DATEADD(day, -1, CURRENT_TIMESTAMP())
  AND execution_status = 'SUCCESS'
GROUP BY warehouse_name;
```

Validate the current percentile function and telemetry field semantics before using this in canonical monitoring.

---

# Part 47 — Queue Percentiles

## 48. More Useful Than Average Queue

A warehouse can show:

```text
Average queue = 1 sec
P95 queue     = 12 sec
P99 queue     = 40 sec
```

The average hides user-impacting peaks.

---

# Part 48 — Failure Percentages

## 49. Per Workload

Track failure percentage by:

```text
Warehouse
Application
Query tag
User
Pipeline
```

This helps identify whether failures are localized.

---

# Part 49 — Query Families

## 50. Same Logical Query

Applications frequently generate SQL such as:

```sql
SELECT *
FROM claims
WHERE claim_id = 'A100';
```

and:

```sql
SELECT *
FROM claims
WHERE claim_id = 'B200';
```

These are different query texts but the same logical workload family.

---

# Part 50 — Query Fingerprinting

## 51. Goal

A query fingerprint normalizes changing literals so similar queries can be grouped.

Conceptually:

```text
SELECT *
FROM claims
WHERE claim_id = ?
```

This makes workload-level analysis much more useful.

---

# Part 51 — Why Fingerprinting Matters

## 52. Without Fingerprinting

You may see:

```text
100,000 unique query texts
```

## 53. With Fingerprinting

You may discover:

```text
25 dominant query patterns
```

Those patterns can then be optimized systematically.

---

# Part 52 — Fingerprinting Caution

## 54. Do Not Build Fragile Regex SQL Parsers

SQL normalization is complex.

A simple regular expression can incorrectly modify:

- strings
- comments
- identifiers
- dates
- JSON
- SQL syntax

Use purpose-built tooling where reliable fingerprinting is required.

---

# Part 53 — Slow Query Families

## 55. Better Than Top 10 Queries

A single query may be slow once.

A query family may run:

```text
100,000 times/day
```

and consume far more total resources.

Analyze:

```text
Frequency
P95 latency
Total execution time
Scan volume
Failure rate
```

---

# Part 54 — High-Frequency Queries

## 56. Example

Query A:

```text
Runtime = 60 sec
Runs/day = 5
```

Query B:

```text
Runtime = 2 sec
Runs/day = 100,000
```

Query B may be the more important optimization target.

---

# Part 55 — Total Workload Impact

## 57. Think Multiplicatively

Conceptually:

```text
Impact =
Frequency
×
Resource use per execution
```

This is more useful than ranking only by single-query latency.

---

# Part 56 — Repeated Failed Queries

## 58. Hidden Waste

Suppose an application submits a failing query every second.

```text
86,400 failures/day
```

Even if each failure is fast, it indicates:

- application defects
- unnecessary traffic
- noisy telemetry
- operational waste

Track repeated failure patterns.

---

# Part 57 — Retry Storms

## 59. Incident Pattern

A service may respond to latency with aggressive retries.

```text
Original requests
       |
       v
Latency
       |
       v
Retries
       |
       v
More queries
       |
       v
More load
       |
       v
More latency
```

This feedback loop can amplify incidents.

---

# Part 58 — Detecting Retry Storms

## 60. Signals

Look for:

```text
Sudden query-count increase
Same query family repeated
Same application/query tag
Same user
Short intervals
Rising queue time
```

---

# Part 59 — Concurrency

## 61. Query Count Is Not Concurrency

A warehouse may execute 100,000 queries/day without high concurrency.

Another warehouse may execute only 10,000 queries/day but receive them all during one hour.

Peak concurrency matters.

---

# Part 60 — Concurrency Analysis

## 62. Concept

```text
Query A  |----------------|
Query B      |----------------|
Query C         |-----------|
Query D           |--------------|
```

Overlapping execution creates concurrency.

---

# Part 61 — Warehouse Load History

## 63. Better Capacity View

Use warehouse load telemetry together with Query History.

Query History explains:

```text
What workload ran?
```

Warehouse Load History helps explain:

```text
How loaded was the warehouse?
```

Together they provide stronger evidence.

---

# Part 62 — Queue + Query Volume

## 64. Example

Normal:

```text
Queries/minute = 100
Queue P95      = 0.2 sec
```

Incident:

```text
Queries/minute = 700
Queue P95      = 18 sec
```

This strongly suggests a concurrency event.

---

# Part 63 — Query Volume Without Queueing

## 65. Example

```text
Queries/minute = 700
Queue P95      = 0.1 sec
```

The warehouse may be handling the increased load successfully.

Do not declare an incident based only on query volume.

---

# Part 64 — Execution Regression

## 66. Different Pattern

Normal:

```text
Queue P95     = 0.1 sec
Execution P95 = 2 sec
```

Incident:

```text
Queue P95     = 0.2 sec
Execution P95 = 20 sec
```

This is more likely an execution-performance regression than a concurrency problem.

---

# Part 65 — Baselines

## 67. Know Normal

For important workloads, maintain baselines for:

```text
Query volume
P50 latency
P95 latency
P99 latency
Queue P95
Bytes scanned
Spill
Failure rate
Warehouse credits
```

Without a baseline, anomaly detection becomes difficult.

---

# Part 66 — Compare Same Time

## 68. Avoid Bad Comparisons

Do not compare:

```text
Monday 10:00
```

with:

```text
Sunday 03:00
```

if workload patterns differ dramatically.

Prefer comparable business periods.

---

# Part 67 — Week-over-Week

## 69. Example

Compare:

```text
This Monday 10:00–11:00
Last Monday 10:00–11:00
```

This can be more meaningful than comparing with the immediately preceding hour.

---

# Part 68 — Workload Growth

## 70. Capacity Signal

Track:

```text
Queries/day
Queries/hour peak
Concurrent workload
Bytes scanned/day
Warehouse credits/day
```

Growth in these metrics can indicate approaching capacity pressure.

---

# Part 69 — Data Growth

## 71. Query Work Can Increase Without Query Count Increasing

Suppose:

```text
Queries/day unchanged
Bytes scanned/query +80%
Execution P95 +50%
```

The underlying dataset may have grown or pruning may have degraded.

---

# Part 70 — Scan Efficiency

## 72. Useful Comparison

Track:

```text
Bytes scanned per query
Partitions scanned per query
Rows returned per query
```

These can expose workloads that process increasing amounts of data for the same business result.

---

# Part 71 — Result Efficiency

## 73. Example

```text
Bytes scanned = 500 GB
Rows returned = 10
```

This does not automatically prove inefficiency, but it deserves investigation.

---

# Part 72 — Workload Isolation

## 74. Identify Mixed Workloads

Suppose one warehouse handles:

```text
BI dashboards
ETL
Ad hoc analysts
Application queries
```

Query History can quantify how each workload contributes.

---

# Part 73 — Isolation Decision

## 75. Example

If ETL activity correlates with BI queue spikes:

```text
ETL
 |
 v
Shared warehouse
 |
 +---- BI
 |
 v
Queueing
```

A dedicated ETL warehouse may provide better isolation.

---

# Part 74 — User Hotspots

## 76. One User Dominating

Example:

```text
User A = 70% of queries
```

Investigate whether this represents:

- expected application activity
- runaway automation
- retry loop
- ad hoc workload
- compromised credentials

Do not assume malicious behavior from volume alone.

---

# Part 75 — Role Hotspots

## 77. Operational Signal

A role suddenly generating significantly more workload can indicate:

- new deployment
- new application
- role reuse
- workload migration
- automation change

---

# Part 76 — Query Tag Hotspots

## 78. Best Application Signal

If query tagging is consistently implemented, it often provides the cleanest application-level workload attribution.

Example:

```text
claims-api       45%
billing-etl      30%
executive-bi     15%
ad-hoc           10%
```

---

# Part 77 — Missing Query Tags

## 79. Governance Gap

If production applications do not tag workloads, incidents become harder to investigate.

A practical standard is:

```text
application
environment
team
workload
pipeline
```

Do not include secrets or sensitive customer data in query tags.

---

# Part 78 — Warehouse Size Analysis

## 80. Correlate Performance

Compare:

```text
Warehouse size
Execution latency
Spill
Queueing
Credits
```

Do not analyze warehouse size independently of workload.

---

# Part 79 — Warehouse Resize Event

## 81. Example

Before:

```text
Size = MEDIUM
P95 = 12 sec
```

After:

```text
Size = LARGE
P95 = 6 sec
```

Now also compare credits.

Performance improvement without cost context is incomplete.

---

# Part 80 — Multi-Cluster Analysis

## 82. Concurrency

For multi-cluster warehouses, analyze query demand together with:

```text
Active cluster behavior
Queueing
Scaling policy
Maximum clusters
Credits
```

Chapter 44 covers this architecture in detail.

---

# Part 81 — Cost Correlation

## 83. Query History Is Not Billing

Do not calculate exact warehouse billing simply by summing query execution time.

Warehouse billing depends on warehouse operation, not just individual query duration.

Use warehouse metering telemetry for credits.

---

# Part 82 — Query + Metering

## 84. Better Model

```text
Query History
     |
     v
What workload ran?
     |
     +
     |
Warehouse Metering
     |
     v
What compute was consumed?
```

Together they support FinOps analysis.

---

# Part 83 — Cost per Workload

## 85. Attribution Challenge

When several workloads share one warehouse, exact cost attribution can be difficult.

Possible allocation models may use:

- dedicated warehouses
- query tags
- execution characteristics
- time windows
- organizational chargeback rules

Dedicated workload warehouses often make cost attribution cleaner.

---

# Part 84 — Query Regression Analysis

## 86. Same Query Family

Compare:

```text
Before
After
```

for:

```text
Latency
Bytes scanned
Partitions scanned
Spill
Warehouse size
Queueing
Result rows
```

---

# Part 85 — Regression Example

## 87. Before

```text
Execution P95 = 2 sec
Bytes scanned = 2 GB
```

## 88. After

```text
Execution P95 = 15 sec
Bytes scanned = 80 GB
```

Investigate pruning, data growth, predicate changes, clustering, and query changes.

---

# Part 86 — Deployment Correlation

## 89. Timeline

```text
13:55 application deployment
14:00 query volume +300%
14:02 queue P95 rises
14:05 user complaints
```

This does not automatically prove causation, but it is strong evidence for investigation.

---

# Part 87 — Data Pipeline Correlation

## 90. Example

```text
02:00 ETL begins
02:05 warehouse load rises
02:07 BI queue rises
03:00 ETL completes
03:02 BI queue normal
```

This strongly supports workload contention.

---

# Part 88 — Query Cancellation

## 91. Operational Investigation

Cancelled queries may indicate:

- user cancellation
- application timeout
- workload management
- incident mitigation
- client disconnect

Analyze cancellations separately from failures.

---

# Part 89 — Long-Running Queries

## 92. Top Queries

```sql
SELECT
    query_id,
    user_name,
    warehouse_name,
    total_elapsed_time / 1000.0 AS elapsed_seconds,
    query_text
FROM SNOWFLAKE.ACCOUNT_USAGE.QUERY_HISTORY
WHERE start_time >= DATEADD(day, -1, CURRENT_TIMESTAMP())
ORDER BY total_elapsed_time DESC
LIMIT 25;
```

Do not automatically terminate long queries. First determine business purpose.

---

# Part 90 — High-Scan Queries

## 93. Example

```sql
SELECT
    query_id,
    user_name,
    warehouse_name,
    bytes_scanned / POWER(1024, 3) AS gb_scanned,
    query_text
FROM SNOWFLAKE.ACCOUNT_USAGE.QUERY_HISTORY
WHERE start_time >= DATEADD(day, -1, CURRENT_TIMESTAMP())
ORDER BY bytes_scanned DESC
LIMIT 25;
```

---

# Part 91 — High-Spill Queries

## 94. Example

```sql
SELECT
    query_id,
    warehouse_name,
    bytes_spilled_to_local_storage,
    bytes_spilled_to_remote_storage,
    query_text
FROM SNOWFLAKE.ACCOUNT_USAGE.QUERY_HISTORY
WHERE start_time >= DATEADD(day, -1, CURRENT_TIMESTAMP())
ORDER BY bytes_spilled_to_remote_storage DESC
LIMIT 25;
```

---

# Part 92 — High-Queue Queries

## 95. Example

```sql
SELECT
    query_id,
    warehouse_name,
    queued_overload_time,
    execution_time,
    total_elapsed_time,
    query_text
FROM SNOWFLAKE.ACCOUNT_USAGE.QUERY_HISTORY
WHERE start_time >= DATEADD(day, -1, CURRENT_TIMESTAMP())
ORDER BY queued_overload_time DESC
LIMIT 25;
```

---

# Part 93 — High-Frequency Users

## 96. Example

```sql
SELECT
    user_name,
    COUNT(*) AS query_count
FROM SNOWFLAKE.ACCOUNT_USAGE.QUERY_HISTORY
WHERE start_time >= DATEADD(day, -1, CURRENT_TIMESTAMP())
GROUP BY user_name
ORDER BY query_count DESC
LIMIT 25;
```

---

# Part 94 — Warehouse Failure Rate

## 97. Conceptual Analysis

For each warehouse, calculate:

```text
Total queries
Failed queries
Failure percentage
```

This can identify localized workload problems.

---

# Part 95 — Query Tag Failure Rate

## 98. Application Health

If tags identify applications, calculate failure rates by query tag.

This can reveal that only one service is failing while the warehouse itself remains healthy.

---

# Part 96 — Capacity Planning

## 99. Use Peaks

Capacity planning should consider:

```text
Peak queries/minute
Peak concurrency
Queue P95/P99
Execution P95/P99
Spill
Credits
Growth rate
```

Monthly averages alone are insufficient.

---

# Part 97 — Headroom

## 100. Production Capacity

Do not design warehouses to operate permanently at the edge of acceptable capacity.

Maintain headroom for:

- bursts
- retries
- data growth
- deployment changes
- unexpected workloads

---

# Part 98 — Forecasting

## 101. Example

Suppose query volume grows:

```text
5% per month
```

while P95 queue time also rises.

This may indicate future capacity pressure.

Capacity planning should occur before the SLA is violated.

---

# Part 99 — Performance Dashboard

## 102. Recommended Metrics

### Query volume

```text
Queries/min
Queries/hour
Queries/day
```

### Latency

```text
P50
P95
P99
```

### Queue

```text
P50
P95
P99
```

### Scan

```text
Bytes scanned
Top scan queries
```

### Spill

```text
Local spill
Remote spill
```

### Failures

```text
Failure count
Failure %
```

---

# Part 100 — Workload Dashboard

## 103. Dimensions

Break metrics down by:

```text
Warehouse
User
Role
Query tag
Application
```

This makes the dashboard operationally actionable.

---

# Part 101 — Alerting

## 104. Useful Alerts

Potential alerts include:

```text
Query failure rate > baseline
Queue P95 > threshold
Execution P95 > threshold
Remote spill > threshold
Query volume > expected range
High-scan workload spike
Retry-pattern spike
```

Thresholds should be workload-specific.

---

# Part 102 — Avoid Alerting on One Slow Query

## 105. Context Matters

One 20-minute query may be expected.

A dashboard workload with P95 increasing from 2 seconds to 20 seconds may be a serious incident.

Alert on workload behavior, not arbitrary isolated values.

---

# Part 103 — Incident Investigation Workflow

## 106. Step 1 — Define Impact

Capture:

```text
Application
Users
Warehouse
Start
End
Timezone
```

## 107. Step 2 — Query Volume

Determine whether workload increased.

## 108. Step 3 — Failure Rate

Determine whether failures increased.

## 109. Step 4 — Queue

Determine whether concurrency caused latency.

## 110. Step 5 — Execution

Determine whether execution itself became slower.

## 111. Step 6 — Scan and Spill

Look for physical workload changes.

## 112. Step 7 — Attribution

Identify user, role, query tag, and application.

## 113. Step 8 — Compare Baseline

Compare with a known-good period.

## 114. Step 9 — Correlate Changes

Check deployments, ETL, warehouse changes, and data growth.

## 115. Step 10 — Remediate

Choose the smallest evidence-based change.

---

# Part 104 — Incident Evidence Template

## 116. Capture

```text
Incident:
Environment:
Account:
Region:

Start:
End:
Timezone:

Affected application:
Affected warehouse:

Query count baseline:
Query count incident:

Failure % baseline:
Failure % incident:

Latency P50 baseline:
Latency P50 incident:

Latency P95 baseline:
Latency P95 incident:

Latency P99 baseline:
Latency P99 incident:

Queue P95 baseline:
Queue P95 incident:

Bytes scanned baseline:
Bytes scanned incident:

Remote spill baseline:
Remote spill incident:

Top user:
Top role:
Top query tag:

Representative slow query IDs:
Representative fast query IDs:
Representative failed query IDs:

Recent deployments:
Recent warehouse changes:
Data growth:

Root cause:
Mitigation:
Permanent remediation:
Validation:
```

---

# Part 105 — Workload Analysis Decision Tree

## 117. Decision

```text
Performance issue
      |
      v
Query volume increased?
    /       \
  Yes        No
  |           |
  v           v
Queue high?   Execution slower?
 /    \         /       \
Yes    No      Yes       No
 |      |       |         |
 v      v       v         v
Capacity/   New workload  Profile   Check client/
isolation   characteristics query   application
```

---

# Part 106 — Queue Decision Tree

## 118. Decision

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
 |
 v
Workload burst?
 /       \
Yes       No
 |         |
 v         v
Schedule/   Capacity/
isolate     scaling
```

---

# Part 107 — Regression Decision Tree

## 119. Decision

```text
Same query slower
      |
      v
Queue increased?
 /          \
Yes          No
 |            |
 v            v
Concurrency   Bytes scanned increased?
              /              \
            Yes               No
             |                 |
             v                 v
        Pruning/data       Spill increased?
        growth/query        /         \
        change            Yes         No
                           |            |
                           v            v
                       Memory/       Query Profile
                       compute       comparison
```

---

# Part 108 — Common Mistakes

## 120. Mistake 1

Ranking only by average latency.

## 121. Mistake 2

Treating query count as concurrency.

## 122. Mistake 3

Treating execution time as total user latency.

## 123. Mistake 4

Combining all queue types into one root cause.

## 124. Mistake 5

Ignoring failed and cancelled queries.

## 125. Mistake 6

Looking only at one query rather than the workload family.

## 126. Mistake 7

Optimizing the slowest single query while ignoring a high-frequency query family.

## 127. Mistake 8

Ignoring data growth.

## 128. Mistake 9

Ignoring application retries.

## 129. Mistake 10

Calculating warehouse billing from query execution time.

## 130. Mistake 11

Comparing unrelated time periods.

## 131. Mistake 12

Exporting sensitive query text without protection.

---

# Part 109 — Hands-On Lab

## 132. Objective

Generate several synthetic Snowflake workloads and analyze them using Query History.

Use a non-production environment.

---

# Part 110 — Create Lab Database

## 133. Database

```sql
CREATE OR REPLACE DATABASE workload_lab;
```

---

# Part 111 — Create Schema

## 134. Schema

```sql
CREATE OR REPLACE SCHEMA workload_lab.demo;
```

---

# Part 112 — Create Events Table

## 135. Table

```sql
CREATE OR REPLACE TABLE workload_lab.demo.events (
    event_id NUMBER,
    customer_id NUMBER,
    event_date DATE,
    event_type STRING,
    amount NUMBER(12,2)
);
```

---

# Part 113 — Generate Synthetic Data

## 136. Data

```sql
INSERT INTO workload_lab.demo.events
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

Reduce the row count if appropriate for your lab budget.

---

# Part 114 — Assign Query Tag

## 137. Lab Tag

Using the currently supported Snowflake syntax, assign a query tag such as:

```text
tutorial=chapter47;workload=baseline
```

Do not place secrets or sensitive data in query tags.

---

# Part 115 — Baseline Query

## 138. Query

```sql
SELECT
    event_type,
    COUNT(*) AS event_count,
    SUM(amount) AS total_amount
FROM workload_lab.demo.events
GROUP BY event_type;
```

Record the query ID.

---

# Part 116 — Selective Query

## 139. Query

```sql
SELECT *
FROM workload_lab.demo.events
WHERE customer_id = 50000;
```

Record the query ID.

---

# Part 117 — Range Query

## 140. Query

```sql
SELECT
    event_date,
    COUNT(*) AS event_count,
    SUM(amount) AS total_amount
FROM workload_lab.demo.events
WHERE event_date BETWEEN DATE '2026-09-01'
                     AND DATE '2026-09-30'
GROUP BY event_date
ORDER BY event_date;
```

Record the query ID.

---

# Part 118 — Analytical Query

## 141. Query

```sql
SELECT
    customer_id,
    event_date,
    amount,
    ROW_NUMBER() OVER (
        PARTITION BY customer_id
        ORDER BY event_date DESC
    ) AS event_rank
FROM workload_lab.demo.events;
```

Record the query ID.

---

# Part 119 — Generate Repeated Workload

## 142. Controlled Repetition

Run the selective query a small approved number of times.

The objective is to create a recognizable query family without generating uncontrolled load.

---

# Part 120 — Generate Failure

## 143. Harmless Lab Failure

```sql
SELECT *
FROM workload_lab.demo.nonexistent_table;
```

Record the failed query ID.

---

# Part 121 — Query History Exercise

## 144. Find Lab Queries

Using the appropriate query-history interface, retrieve:

```text
Query ID
User
Role
Warehouse
Query tag
Start
Status
Elapsed
Execution
Queue
Bytes scanned
Rows produced
Spill
```

---

# Part 122 — Workload Volume Exercise

## 145. Group Queries

Group the lab queries by:

```text
Query tag
User
Warehouse
Status
```

Verify that the repeated workload is visible.

---

# Part 123 — Latency Exercise

## 146. Calculate

For the lab workload calculate:

```text
P50
P95
P99
```

Use the current supported Snowflake percentile function.

With a very small sample, treat percentile results only as a mechanics exercise, not a statistically meaningful performance baseline.

---

# Part 124 — Failure Exercise

## 147. Analyze

Identify:

```text
Failure count
Failure %
Error code
Error message
```

for the lab workload.

---

# Part 125 — Scan Exercise

## 148. Compare

Compare bytes scanned for:

```text
Broad aggregation
Selective lookup
Date range
Window function
```

Explain why the values differ.

---

# Part 126 — Queue Exercise

## 149. Controlled Concurrency

If permitted, run a small bounded concurrent workload using a dedicated lab warehouse.

Record:

```text
Query count
Queue time
Execution time
Elapsed time
```

Do not perform uncontrolled stress testing.

---

# Part 127 — Baseline Comparison

## 150. Results Table

| Metric | Baseline | Test |
|---|---:|---:|
| Query count | | |
| Failure % | | |
| P50 elapsed | | |
| P95 elapsed | | |
| P99 elapsed | | |
| Queue P95 | | |
| Bytes scanned | | |
| Local spill | | |
| Remote spill | | |

---

# Part 128 — Diagnose

## 151. Write Findings

For every scenario document:

```text
Observed behavior:
Query IDs:
Workload source:
Evidence:
Bottleneck:
Expected behavior:
Remediation required:
Cost implication:
```

---

# Part 129 — Cleanup

## 152. Drop Lab

```sql
DROP DATABASE IF EXISTS workload_lab;
```

Restore query tags and any lab warehouse settings.

---

# Part 130 — Production Checklist

## 153. Time

```text
□ Incident start
□ Incident end
□ Timezone
□ Baseline period
```

## 154. Query

```text
□ Query IDs
□ Status
□ Elapsed
□ Execution
□ Compilation
□ Queue
□ Scan
□ Spill
□ Rows produced
```

## 155. Attribution

```text
□ User
□ Role
□ Warehouse
□ Query tag
□ Application
□ Query family
```

## 156. Workload

```text
□ Queries/minute
□ Queries/hour
□ Peak concurrency
□ Failure %
□ P50
□ P95
□ P99
```

## 157. Warehouse

```text
□ Size
□ Load
□ Queue
□ Cluster configuration
□ Credits
```

## 158. Change

```text
□ Deployment
□ Query change
□ Data growth
□ Warehouse change
□ Pipeline overlap
□ Retry behavior
```

## 159. Validation

```text
□ Root cause identified
□ Mitigation applied
□ SLA restored
□ Cost checked
□ Prevention defined
```

---

# Part 131 — Operational Principles

## 160. Principle 1

Always capture query IDs.

## 161. Principle 2

Analyze workloads, not only individual queries.

## 162. Principle 3

Separate queue time from execution time.

## 163. Principle 4

Separate different queue causes.

## 164. Principle 5

Use P95 and P99, not only averages.

## 165. Principle 6

Correlate workload with users, roles, warehouses, and query tags.

## 166. Principle 7

Track failures and cancellations.

## 167. Principle 8

Look for retry storms.

## 168. Principle 9

Compare against a relevant baseline.

## 169. Principle 10

Account for data growth.

## 170. Principle 11

Correlate Query History with warehouse load.

## 171. Principle 12

Correlate Query History with warehouse metering.

## 172. Principle 13

Protect query text.

## 173. Principle 14

Use workload isolation when different workload classes interfere.

## 174. Principle 15

Optimize by total workload impact, not only the slowest single query.

---

# Part 132 — DBRE/SRE Workload Analysis Flow

## 175. Production Flow

```text
Performance complaint
        |
        v
Define time window
        |
        v
Collect query IDs
        |
        v
Measure query volume
        |
        v
Measure failure rate
        |
        v
Queue or execution?
      /             \
   Queue             Execution
    |                   |
    v                   v
Concurrency         Query Profile
    |                   |
    v                   v
Attribution         Scan/spill/join
    |                   |
    +---------+---------+
              |
              v
      Compare baseline
              |
              v
      Correlate changes
              |
              v
       Root cause
              |
              v
        Remediation
              |
              v
    Performance validation
              |
              v
        Cost validation
```

---

# Acceptance Criteria

The chapter is complete when you can:

- explain why Query History is operationally important
- use query IDs as investigation anchors
- collect representative query examples
- distinguish recent from historical telemetry requirements
- query historical Query History
- bound investigation time windows
- normalize timezones
- analyze query status
- identify successful queries
- identify failed queries
- calculate failure rates
- distinguish elapsed and execution time
- identify queue-bound workloads
- distinguish queue categories
- identify overload queueing
- identify provisioning queueing
- investigate compilation time
- analyze bytes scanned
- report scan volume in human-readable units
- analyze partition scanning
- identify local spill
- identify remote spill
- analyze result size
- protect sensitive query text
- use query tags for workload attribution
- analyze workload by warehouse
- analyze workload by user
- analyze workload by role
- analyze workload by query tag
- analyze hourly workload
- analyze daily workload
- analyze day-of-week patterns
- analyze hour-of-day patterns
- understand why averages are insufficient
- calculate P50/P95/P99
- analyze queue percentiles
- analyze failure percentages
- understand query families
- understand query fingerprinting
- avoid fragile SQL normalization
- identify slow query families
- identify high-frequency workloads
- measure total workload impact
- identify repeated failures
- recognize retry storms
- distinguish query volume from concurrency
- analyze overlapping query execution
- correlate Query History with warehouse load
- interpret query-volume and queue relationships
- identify execution regressions
- establish performance baselines
- compare equivalent time periods
- perform week-over-week analysis
- analyze workload growth
- identify data-growth effects
- measure scan efficiency
- analyze result efficiency
- identify mixed workloads
- determine workload-isolation candidates
- identify user hotspots
- identify role hotspots
- identify query-tag hotspots
- identify missing query-tag governance
- correlate warehouse size with workload
- analyze resize results
- analyze multi-cluster workloads
- avoid treating Query History as billing data
- correlate Query History with warehouse metering
- understand workload cost attribution
- perform query regression analysis
- correlate deployments with performance
- correlate data pipelines with performance
- investigate cancelled queries
- identify long-running queries
- identify high-scan queries
- identify high-spill queries
- identify high-queue queries
- identify high-frequency users
- calculate warehouse failure rates
- calculate application/query-tag failure rates
- use workload telemetry for capacity planning
- plan production headroom
- identify growth trends
- design performance dashboards
- design workload dashboards
- create workload-specific alerts
- avoid noisy single-query alerting
- execute the incident investigation workflow
- capture a complete incident evidence record
- use workload decision trees
- avoid common workload-analysis mistakes
- complete the hands-on workload lab
- analyze controlled query families
- calculate workload percentiles
- compare scan patterns
- analyze controlled queueing
- compare baseline and test workloads
- document evidence-based findings
- clean up lab resources
- apply the production checklist
- follow the DBRE/SRE workload-analysis flow

---

## Key Takeaways

Query History should not be treated simply as a list of SQL statements.

It is a workload telemetry system.

The core analysis model is:

```text
Query History
      |
      +---- Volume
      +---- Latency
      +---- Queue
      +---- Scan
      +---- Spill
      +---- Failure
      +---- User
      +---- Role
      +---- Warehouse
      +---- Query tag
      |
      v
Workload behavior
```

When investigating slowness:

```text
Slow workload
      |
      v
Queue high?
   /      \
 Yes       No
 |          |
 v          v
Concurrency Execution
             |
             v
         Query Profile
```

When investigating workload growth:

```text
Query count
    +
Peak concurrency
    +
Bytes scanned
    +
Latency percentiles
    +
Credits
    |
    v
Capacity trend
```

When investigating application impact:

```text
Query tag
   |
   v
Query family
   |
   v
Frequency
   |
   v
P95/P99
   |
   v
Failures
   |
   v
Total workload impact
```

The most important production principle is:

> Do not optimize the query that merely looks worst. Optimize the workload that creates the greatest measurable business, performance, or cost impact.

A strong Snowflake workload investigation should always answer:

```text
What changed?
Who generated it?
Where did it run?
How much workload was generated?
Where was time spent?
How did it differ from baseline?
What was the business impact?
What remediation fixed it?
What did the remediation cost?
How will recurrence be detected?
```

The next chapter is **Chapter 48 — Warehouse Monitoring**.
