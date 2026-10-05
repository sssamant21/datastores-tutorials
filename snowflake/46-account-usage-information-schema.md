# 46 — ACCOUNT_USAGE & INFORMATION_SCHEMA

## Overview

Operating Snowflake in production requires more than running SQL against application tables.

DBREs, SREs, administrators, platform engineers, security teams, and FinOps teams also need visibility into:

- query activity
- warehouse usage
- storage
- data loading
- users and roles
- access activity
- object metadata
- replication
- tasks
- pipes
- resource consumption
- failures
- performance
- historical trends

Snowflake exposes operational metadata primarily through interfaces such as:

```text
SNOWFLAKE.ACCOUNT_USAGE
          |
          +---- Historical account telemetry
          |
          +---- Query activity
          +---- Warehouse metering
          +---- Storage
          +---- Users / roles
          +---- Access history
          +---- Tasks / pipes
          +---- Other account metadata
```

and:

```text
<database>.INFORMATION_SCHEMA
          |
          +---- Database metadata
          |
          +---- Tables
          +---- Columns
          +---- Views
          +---- Schemas
          +---- Functions
          +---- Query/table functions
```

They overlap in some areas, but they are not interchangeable.

The operational rule is:

> Choose the telemetry source according to scope, freshness, retention, privileges, and the question you are trying to answer.

This chapter covers ACCOUNT_USAGE, INFORMATION_SCHEMA, differences between them, query history, warehouse metering, warehouse load, storage monitoring, table metadata, user and role metadata, access history, tasks, pipes, load history, latency and retention considerations, deleted objects, privileges, incident troubleshooting, performance analysis, security investigations, FinOps, reusable operational SQL, and a hands-on investigation.

---

# Part 1 — Why Operational Metadata Matters

## 1. Production Questions

During normal operations you may need to answer:

```text
Which query caused the slowdown?
Which warehouse consumed the most credits?
Who executed this query?
Which warehouse had queueing?
How quickly is storage growing?
Which tables are largest?
Which users exist?
Which role owns an object?
Did a task fail?
Did a pipe load data?
Who accessed sensitive data?
What changed during the incident?
```

Without operational metadata, these questions become guesswork.

---

# Part 2 — Two Important Metadata Interfaces

## 2. ACCOUNT_USAGE

The shared `SNOWFLAKE` database exposes account-level metadata through schemas such as:

```sql
SNOWFLAKE.ACCOUNT_USAGE
```

This is commonly used for historical operational analysis.

## 3. INFORMATION_SCHEMA

Each database includes an Information Schema.

```sql
MY_DATABASE.INFORMATION_SCHEMA
```

It provides metadata and functions associated with Snowflake objects and operational activity.

---

# Part 3 — Conceptual Difference

## 4. ACCOUNT_USAGE

Think:

```text
Account-level
+
Historical
+
Operational analytics
```

## 5. INFORMATION_SCHEMA

Think:

```text
Database-oriented metadata
+
Operational functions
+
More immediate investigation in applicable interfaces
```

This is a useful mental model, but exact behavior varies by view or function.

---

# Part 4 — Do Not Assume Identical Behavior

## 6. Important Rule

Two interfaces may expose related information while differing in scope, latency, retention, privileges, columns, row limits, function parameters, and deleted-object handling.

Always validate the exact interface being used.

---

# Part 5 — ACCOUNT_USAGE Structure

## 7. Basic Pattern

```sql
SELECT ...
FROM SNOWFLAKE.ACCOUNT_USAGE.<view>;
```

Example:

```sql
SELECT *
FROM SNOWFLAKE.ACCOUNT_USAGE.QUERY_HISTORY;
```

Use explicit column lists in production tooling rather than relying on `SELECT *`.

---

# Part 6 — INFORMATION_SCHEMA Structure

## 8. Metadata Views

```sql
SELECT
    table_catalog,
    table_schema,
    table_name,
    table_type
FROM my_database.information_schema.tables;
```

---

# Part 7 — Information Schema Table Functions

## 9. Functions

Some operational metadata is exposed through table functions.

```sql
SELECT *
FROM TABLE(
    INFORMATION_SCHEMA.<function>(...)
);
```

Exact function signatures and supported ranges must be checked against current Snowflake documentation.

---

# Part 8 — Query History

## 10. One of the Most Important Views

Query history helps answer what ran, who ran it, when, where, how long it took, whether it failed, how much data it scanned, and whether it was queued.

For DBRE/SRE operations, query history is foundational.

---

# Part 9 — ACCOUNT_USAGE Query History

## 11. Basic Investigation

```sql
SELECT
    query_id,
    user_name,
    role_name,
    warehouse_name,
    warehouse_size,
    start_time,
    end_time,
    total_elapsed_time,
    execution_time,
    bytes_scanned,
    rows_produced,
    execution_status,
    query_text
FROM SNOWFLAKE.ACCOUNT_USAGE.QUERY_HISTORY
WHERE start_time >= DATEADD(hour, -1, CURRENT_TIMESTAMP())
ORDER BY start_time DESC;
```

Before standardizing this query, verify current column definitions and telemetry latency.

---

# Part 10 — Query History Time Units

## 12. Important Operational Detail

Timing fields may use units such as milliseconds. Always verify units.

For human-readable reporting, convert explicitly when the source field is documented in milliseconds:

```sql
execution_time / 1000.0 AS execution_seconds
```

---

# Part 11 — Slowest Queries

## 13. Example

```sql
SELECT
    query_id,
    user_name,
    warehouse_name,
    total_elapsed_time / 1000.0 AS elapsed_seconds,
    execution_time / 1000.0 AS execution_seconds,
    bytes_scanned,
    query_text
FROM SNOWFLAKE.ACCOUNT_USAGE.QUERY_HISTORY
WHERE start_time >= DATEADD(hour, -24, CURRENT_TIMESTAMP())
  AND execution_status = 'SUCCESS'
ORDER BY total_elapsed_time DESC
LIMIT 20;
```

This identifies slow queries, but it does not prove why they were slow. Use Query Profile and queue metrics for root-cause analysis.

---

# Part 12 — Failed Queries

## 14. Failure Investigation

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

Use this to identify repeated failures and common error patterns.

---

# Part 13 — Query Volume

## 15. Queries Per Hour

```sql
SELECT
    DATE_TRUNC('hour', start_time) AS hour,
    COUNT(*) AS query_count
FROM SNOWFLAKE.ACCOUNT_USAGE.QUERY_HISTORY
WHERE start_time >= DATEADD(day, -7, CURRENT_TIMESTAMP())
GROUP BY 1
ORDER BY 1;
```

---

# Part 14 — Query Volume by Warehouse

## 16. Example

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

# Part 15 — Queue Analysis

## 17. Queue Metrics

Operationally, distinguish overload queue, provisioning queue, and repair queue.

These represent different causes. Do not combine them blindly.

---

# Part 16 — Overload Queueing

## 18. Concept

Overload queueing indicates that a query waited because warehouse execution capacity was unavailable.

```text
Queries
   |
   v
Warehouse saturated
   |
   v
Queue
```

This is a strong concurrency signal.

---

# Part 17 — Provisioning Queue

## 19. Concept

A query may wait while compute resources are being provisioned. This can occur around warehouse startup or resource changes.

This is different from an already-running warehouse being overloaded.

---

# Part 18 — Queue Investigation Query

## 20. Example

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
WHERE start_time >= DATEADD(hour, -4, CURRENT_TIMESTAMP())
ORDER BY queued_overload_time DESC;
```

Validate exact column names and units against current Snowflake documentation before making this a production runbook query.

---

# Part 19 — Bytes Scanned

## 21. Scan Analysis

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
LIMIT 20;
```

High bytes scanned can identify expensive workloads, but a legitimate full-table analytical scan may be expected.

---

# Part 20 — Spill Analysis

## 22. Memory Pressure

Query history can expose bytes spilled to local storage and bytes spilled to remote storage.

Remote spill is especially important during performance investigations.

---

# Part 21 — Spill Query

## 23. Example

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
ORDER BY bytes_spilled_to_remote_storage DESC;
```

Validate exact current columns before operational use.

---

# Part 22 — Query Attribution

## 24. Group by User

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

# Part 23 — Query Attribution by Role

## 25. Example

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

# Part 24 — Query Tags

## 26. Application Attribution

Query tags can make workload analysis significantly easier.

Example conceptual values:

```text
service=claims-api
pipeline=daily-claims-load
dashboard=finance-summary
environment=prod
```

Then telemetry can be grouped by workload rather than only by username.

---

# Part 25 — Warehouse Metering

## 27. Compute Consumption

Warehouse metering history helps answer which warehouse consumed credits, when, and how much.

A common source is:

```sql
SNOWFLAKE.ACCOUNT_USAGE.WAREHOUSE_METERING_HISTORY
```

---

# Part 26 — Warehouse Credit Usage

## 28. Example

```sql
SELECT
    warehouse_name,
    SUM(credits_used) AS credits_used
FROM SNOWFLAKE.ACCOUNT_USAGE.WAREHOUSE_METERING_HISTORY
WHERE start_time >= DATEADD(day, -30, CURRENT_TIMESTAMP())
GROUP BY warehouse_name
ORDER BY credits_used DESC;
```

---

# Part 27 — Credits Over Time

## 29. Daily Trend

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

---

# Part 28 — Credits Used vs Cloud Services

## 30. Understand the Columns

Warehouse metering may expose multiple credit-related metrics. Do not assume every credit field represents the same component.

Understand compute credits, cloud services credits, and total reported usage according to the current Snowflake view definition.

---

# Part 29 — Warehouse Load History

## 31. Capacity Telemetry

Warehouse load history helps investigate warehouse utilization and queueing.

A common account-level source is:

```sql
SNOWFLAKE.ACCOUNT_USAGE.WAREHOUSE_LOAD_HISTORY
```

This is especially useful for concurrency analysis.

---

# Part 30 — Warehouse Load Concepts

## 32. Analyze

Look for metrics describing running load, queued load, provisioning, and blocking.

Exact fields and semantics should be validated against current Snowflake documentation.

---

# Part 31 — Performance + Cost

## 33. Combine Perspectives

Cost alone does not tell the complete story. Performance alone does not tell the complete story.

Operational analysis should combine both.

---

# Part 32 — Storage Usage

## 34. Account Storage

Snowflake exposes storage telemetry through Account Usage views.

Use these to monitor database storage, stage storage, Fail-safe related storage, Time Travel effects, and growth trends.

Exact available views and fields should be checked against current documentation.

---

# Part 33 — Database Storage Trend

## 35. Operational Question

If Snowflake storage increases significantly, investigate database growth, new tables, clones, retention, stages, data loading, and deleted data.

---

# Part 34 — Table Storage

## 36. Table-Level Investigation

Account-level table storage telemetry can help identify large tables and storage growth.

Use current Snowflake storage views rather than estimating only from logical row counts.

---

# Part 35 — Tables Metadata

## 37. INFORMATION_SCHEMA.TABLES

```sql
SELECT
    table_catalog,
    table_schema,
    table_name,
    table_type,
    row_count,
    bytes
FROM my_database.information_schema.tables
WHERE table_schema <> 'INFORMATION_SCHEMA'
ORDER BY bytes DESC;
```

Validate which columns are available and how current their statistics are before treating them as real-time measurements.

---

# Part 36 — Columns Metadata

## 38. INFORMATION_SCHEMA.COLUMNS

```sql
SELECT
    table_schema,
    table_name,
    column_name,
    ordinal_position,
    data_type,
    is_nullable
FROM my_database.information_schema.columns
WHERE table_schema = 'PUBLIC'
ORDER BY table_name, ordinal_position;
```

---

# Part 37 — Schema Metadata

## 39. SCHEMATA

```sql
SELECT
    catalog_name,
    schema_name,
    schema_owner
FROM my_database.information_schema.schemata
ORDER BY schema_name;
```

---

# Part 38 — Views Metadata

## 40. VIEWS

```sql
SELECT
    table_schema,
    table_name,
    view_definition
FROM my_database.information_schema.views
WHERE table_schema <> 'INFORMATION_SCHEMA';
```

Be careful when exporting view definitions because they may contain sensitive business logic or object references.

---

# Part 39 — ACCOUNT_USAGE Tables

## 41. Historical Object Metadata

ACCOUNT_USAGE also exposes table-related metadata. This can be useful when broader account scope or historical/deleted-object analysis is needed.

---

# Part 40 — Deleted Objects

## 42. Important Difference

Some Account Usage views include metadata about objects that were dropped.

Operational tooling should understand deletion timestamps where applicable. Do not assume every returned object still exists.

---

# Part 41 — Users

## 43. User Metadata

Account Usage can expose user metadata useful for access reviews, dormant-account reviews, authentication audits, ownership analysis, and security investigations.

A typical source is:

```sql
SNOWFLAKE.ACCOUNT_USAGE.USERS
```

---

# Part 42 — Roles

## 44. Role Metadata

Role-related views can help understand roles, role grants, privileges, hierarchy, and ownership.

These are essential for RBAC audits.

---

# Part 43 — Grants to Roles

## 45. Privilege Analysis

```sql
SNOWFLAKE.ACCOUNT_USAGE.GRANTS_TO_ROLES
```

Use it to analyze privileges granted to account roles. Exact role models and columns should be validated against current Snowflake behavior.

---

# Part 44 — Grants to Users

## 46. Role Assignment

```sql
SNOWFLAKE.ACCOUNT_USAGE.GRANTS_TO_USERS
```

This can support user-to-role analysis.

---

# Part 45 — Role Hierarchy

## 47. Effective Access

Understanding only direct grants is insufficient.

```text
USER
 |
 v
ROLE_A
 |
 v
ROLE_B
 |
 v
ROLE_C
 |
 v
OBJECT
```

Effective access may be inherited through the hierarchy.

---

# Part 46 — Access History

## 48. Security and Governance

Access History can help answer who accessed an object, which objects a query read or modified, and which columns were referenced.

Availability and detail can depend on Snowflake edition and current feature behavior.

Validate current requirements before building governance tooling around it.

---

# Part 47 — Access Investigation

## 49. Example Use Case

For unexpected access to a sensitive table, investigate query ID, user, role, time, source objects, columns, and downstream objects.

Access history can provide stronger lineage evidence than query text alone.

---

# Part 48 — Data Lineage

## 50. Operational Lineage

```text
SOURCE_TABLE
     |
     v
Transformation Query
     |
     v
TARGET_TABLE
```

Access metadata can help reconstruct these relationships.

---

# Part 49 — Tasks

## 51. Task Operations

Operational metadata can help determine whether a task ran, failed, how long it ran, what was scheduled, and what query executed.

Task telemetry is important for production pipelines.

---

# Part 50 — Task Failure Investigation

## 52. Workflow

```text
Pipeline delayed
      |
      v
Check task history
      |
      +---- Did not run
      +---- Failed
      +---- Running slowly
      +---- Dependency blocked
```

---

# Part 51 — Pipes

## 53. Snowpipe Operations

Pipe-related metadata helps investigate pipe configuration, load activity, errors, and usage.

---

# Part 52 — Copy History

## 54. Load Investigation

Copy/load history helps answer whether a file was loaded, when, how many rows were loaded, whether errors occurred, and whether it was already processed.

---

# Part 53 — Load Failure Workflow

## 55. Example

```text
File exists
   |
   v
Check load/copy history
   |
   +---- Loaded
   +---- Failed
   +---- Not observed
```

Each result leads to a different investigation path.

---

# Part 54 — Metadata Latency

## 56. Critical Operational Concept

ACCOUNT_USAGE should not automatically be treated as real-time telemetry.

Different views can have different latency. During an active incident, this matters.

---

# Part 55 — Example

## 57. Incident at 10:00

If an incident started at 10:00 and the current time is 10:05, an Account Usage view with ingestion latency may not yet reflect the newest activity.

Querying it could otherwise produce a false conclusion.

---

# Part 56 — Operational Rule

## 58. Freshness First

Before relying on a metadata source during an incident, know how fresh it is.

If near-real-time information is required, use the appropriate current Snowflake interface.

---

# Part 57 — Retention

## 59. Historical Depth

Different metadata interfaces provide different retention windows.

A recent incident and a historical investigation may therefore require different interfaces.

Validate retention for the exact view or function.

---

# Part 58 — Do Not Memorize One Retention Number

## 60. Why

Snowflake services evolve. Retention can differ by view, function, feature, and edition.

Runbooks should reference current documented behavior.

---

# Part 59 — Privileges

## 61. Metadata Is Not Automatically Visible

A query may return no rows because nothing happened or because the current role cannot see the relevant data.

These are very different conclusions.

---

# Part 60 — Metadata Access

## 62. Operational Roles

Create an intentional access model for DBRE, SRE, Security, FinOps, Data Engineering, and auditors.

Do not simply grant broad administrative roles for observability.

---

# Part 61 — Least Privilege

## 63. Goal

```text
Enough metadata to perform the job
+
No unnecessary control-plane privileges
```

This is particularly important for automated monitoring services.

---

# Part 62 — Metadata Queries Have Cost

## 64. Operational SQL Is Still SQL

Poorly designed telemetry queries can scan unnecessary history, return excessive data, run too frequently, and create monitoring overhead.

Filter by time and required scope.

---

# Part 63 — Avoid SELECT *

## 65. Monitoring Queries

Instead of:

```sql
SELECT *
FROM SNOWFLAKE.ACCOUNT_USAGE.QUERY_HISTORY;
```

prefer:

```sql
SELECT
    query_id,
    start_time,
    warehouse_name,
    execution_time
FROM SNOWFLAKE.ACCOUNT_USAGE.QUERY_HISTORY
WHERE start_time >= DATEADD(hour, -1, CURRENT_TIMESTAMP());
```

---

# Part 64 — Always Bound Time

## 66. Example

Prefer:

```sql
WHERE start_time >= DATEADD(hour, -1, CURRENT_TIMESTAMP())
```

when only the last hour matters.

---

# Part 65 — Timezones

## 67. Incident Accuracy

Always understand the timezone of the incident report, application logs, Snowflake session, telemetry timestamps, and monitoring dashboard.

Timezone confusion can make related events appear unrelated.

---

# Part 66 — UTC for Operations

## 68. Recommendation

For cross-region operational workflows, UTC often simplifies correlation.

```text
Application error: 14:03 UTC
Snowflake query:    14:03 UTC
Pipeline event:     14:04 UTC
```

---

# Part 67 — Incident Query Template

## 69. Start With a Narrow Window

```sql
SELECT
    query_id,
    user_name,
    role_name,
    warehouse_name,
    start_time,
    end_time,
    execution_status,
    total_elapsed_time,
    execution_time,
    bytes_scanned,
    query_text
FROM SNOWFLAKE.ACCOUNT_USAGE.QUERY_HISTORY
WHERE start_time >= :incident_start
  AND start_time < :incident_end
ORDER BY start_time;
```

Use bound values appropriate for your client/tooling.

---

# Part 68 — Performance Investigation Template

## 70. Sort by Runtime

```sql
SELECT
    query_id,
    warehouse_name,
    total_elapsed_time / 1000.0 AS elapsed_seconds,
    execution_time / 1000.0 AS execution_seconds,
    bytes_scanned,
    rows_produced,
    query_text
FROM SNOWFLAKE.ACCOUNT_USAGE.QUERY_HISTORY
WHERE start_time >= :incident_start
  AND start_time < :incident_end
ORDER BY total_elapsed_time DESC;
```

---

# Part 69 — Queue Investigation Template

## 71. Add Queue Metrics

```sql
SELECT
    query_id,
    warehouse_name,
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

Validate exact current fields and units.

---

# Part 70 — Workload Attribution Template

## 72. By Warehouse

```sql
SELECT
    warehouse_name,
    COUNT(*) AS query_count,
    SUM(execution_time) / 1000.0 AS execution_seconds
FROM SNOWFLAKE.ACCOUNT_USAGE.QUERY_HISTORY
WHERE start_time >= :incident_start
  AND start_time < :incident_end
GROUP BY warehouse_name
ORDER BY query_count DESC;
```

This provides workload volume, not warehouse credit consumption. Do not equate summed query execution time with billed warehouse time.

---

# Part 71 — Cost Investigation Template

## 73. Warehouse Credits

```sql
SELECT
    warehouse_name,
    SUM(credits_used) AS credits_used
FROM SNOWFLAKE.ACCOUNT_USAGE.WAREHOUSE_METERING_HISTORY
WHERE start_time >= :period_start
  AND start_time < :period_end
GROUP BY warehouse_name
ORDER BY credits_used DESC;
```

---

# Part 72 — Cost Trend

## 74. Daily

```sql
SELECT
    DATE_TRUNC('day', start_time) AS usage_day,
    warehouse_name,
    SUM(credits_used) AS credits_used
FROM SNOWFLAKE.ACCOUNT_USAGE.WAREHOUSE_METERING_HISTORY
WHERE start_time >= DATEADD(day, -30, CURRENT_TIMESTAMP())
GROUP BY 1, 2
ORDER BY 1, 2;
```

Chapter 52 will go deeper into compute cost analysis.

---

# Part 73 — Detecting Cost Anomalies

## 75. Compare Baselines

If normal BI warehouse consumption is 20 credits/day and it rises to 75 credits/day, investigate query volume, warehouse runtime, resizing, multi-cluster activity, auto-suspend, and new workloads.

---

# Part 74 — Security Investigation Template

## 76. Start With Identity

Capture user, role, query, time, object, and authentication context.

Then correlate with access metadata and role grants.

---

# Part 75 — Dormant Users

## 77. Governance Use Case

User metadata can support periodic reviews of inactive users, disabled users, legacy service accounts, and unexpected administrators.

Do not disable users solely from one telemetry signal without understanding business ownership and authentication patterns.

---

# Part 76 — Object Ownership

## 78. Why It Matters

Objects without intentional ownership can create deployment problems, access problems, governance gaps, and operational confusion.

Metadata should support ownership reviews.

---

# Part 77 — Metadata Snapshotting

## 79. Long-Term History

If your organization needs history beyond native retention, build an intentional telemetry retention pipeline.

```text
Snowflake metadata
      |
      v
Scheduled extraction
      |
      v
Operations schema
      |
      v
Long-term history
```

---

# Part 78 — Do Not Copy Everything

## 80. Selective Retention

Retain only what is operationally justified.

Consider cost, security, privacy, volume, retention policy, and compliance.

Query text in particular may contain sensitive values.

---

# Part 79 — Query Text Security

## 81. Sensitive Information

Query text can potentially expose object names, business logic, literals, identifiers, and user-supplied values.

Do not broadly export raw query text into unsecured monitoring systems.

---

# Part 80 — Monitoring Architecture

## 82. Example

```text
ACCOUNT_USAGE
INFORMATION_SCHEMA
        |
        v
Collection queries
        |
        v
Operations tables
        |
        v
Dashboards / alerts
```

Apply least privilege at every layer.

---

# Part 81 — Metadata Health Dashboard

## 83. Recommended Sections

Query: query count, failures, P50/P95/P99 latency, queueing, bytes scanned, spill.

Warehouse: credits, load, queueing, runtime.

Storage: database growth, table growth, stage growth.

Pipelines: task failures, load failures, pipe health.

---

# Part 82 — Alerting

## 84. Potential Alerts

Examples include query failure spikes, queue P95 above threshold, warehouse credit anomalies, remote spill spikes, task failures, load failures, and unexpected storage growth.

Thresholds must be based on real baselines.

---

# Part 83 — ACCOUNT_USAGE Troubleshooting

## 85. No Rows Returned

Check the correct account, time range, timezone, telemetry latency, privileges, view, and filters.

---

# Part 84 — INFORMATION_SCHEMA Troubleshooting

## 86. Object Not Visible

Check the correct database, schema, current role, privileges, whether the object was dropped, and case-sensitive identifiers.

---

# Part 85 — Metadata Query Slow

## 87. Check Your Own Query

Review the time range, selected columns, filters, grouping, sorting, and execution frequency.

Observability queries should themselves be operationally efficient.

---

# Part 86 — ACCOUNT_USAGE vs INFORMATION_SCHEMA Decision Tree

## 88. Decision

```text
Need metadata
     |
     v
Historical account-wide analysis?
     /        \
   Yes         No
   |            |
   v            v
ACCOUNT_USAGE   Need database/object
                metadata or applicable
                near-term function?
                     |
                     v
             INFORMATION_SCHEMA
```

Then verify freshness, retention, privileges, and exact interface.

---

# Part 87 — Production Incident Workflow

## 89. Step 1 — Define Window

Capture start, end, and timezone.

## 90. Step 2 — Identify Warehouse

Determine which compute resource handled the workload.

## 91. Step 3 — Identify Queries

Collect query IDs.

## 92. Step 4 — Separate Queue and Execution

Determine where latency occurred.

## 93. Step 5 — Analyze Workload

Group by user, role, query tag, and warehouse.

## 94. Step 6 — Check Warehouse Load

Determine whether concurrency increased.

## 95. Step 7 — Check Credits

Determine whether compute consumption changed.

## 96. Step 8 — Correlate Changes

Look for deployments, data growth, workload changes, and configuration changes.

---

# Part 88 — Evidence Template

## 97. Operational Investigation

```text
Environment:
Account:
Region:
Incident start:
Incident end:
Timezone:
Affected warehouse:
Warehouse size:
Query IDs:
Query count:
Failed queries:
Queue P50:
Queue P95:
Queue P99:
Execution P50:
Execution P95:
Execution P99:
Bytes scanned:
Local spill:
Remote spill:
Warehouse credits:
Top users:
Top roles:
Top query tags:
Task failures:
Load failures:
Recent changes:
Metadata source:
Metadata freshness:
Root cause:
Mitigation:
Validation:
```

---

# Part 89 — Hands-On Lab

## 98. Objective

Use Snowflake metadata interfaces to investigate a controlled workload.

## 99. Create Lab Database

```sql
CREATE OR REPLACE DATABASE metadata_lab;
```

## 100. Create Schema

```sql
CREATE OR REPLACE SCHEMA metadata_lab.demo;
```

## 101. Create Table

```sql
CREATE OR REPLACE TABLE metadata_lab.demo.events (
    event_id NUMBER,
    event_date DATE,
    event_type STRING,
    amount NUMBER(12,2)
);
```

## 102. Load Synthetic Data

```sql
INSERT INTO metadata_lab.demo.events
SELECT
    seq,
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
    FROM TABLE(GENERATOR(ROWCOUNT => 1000000))
);
```

All data is synthetic.

---

# Part 90 — Generate Query Activity

## 103. Query 1

```sql
SELECT
    event_type,
    COUNT(*) AS event_count,
    SUM(amount) AS total_amount
FROM metadata_lab.demo.events
GROUP BY event_type;
```

## 104. Query 2

```sql
SELECT
    event_date,
    COUNT(*) AS event_count
FROM metadata_lab.demo.events
WHERE event_date >= DATE '2026-09-01'
GROUP BY event_date
ORDER BY event_date;
```

Record the query IDs.

---

# Part 91 — Explore INFORMATION_SCHEMA

## 105. Tables

```sql
SELECT
    table_catalog,
    table_schema,
    table_name,
    table_type
FROM metadata_lab.information_schema.tables
WHERE table_schema = 'DEMO';
```

## 106. Columns

```sql
SELECT
    table_name,
    column_name,
    ordinal_position,
    data_type,
    is_nullable
FROM metadata_lab.information_schema.columns
WHERE table_schema = 'DEMO'
ORDER BY table_name, ordinal_position;
```

---

# Part 92 — Explore Query History

## 107. Find Lab Queries

Use the appropriate current query-history interface and locate the query IDs recorded earlier.

Capture query ID, warehouse, user, role, start time, elapsed time, execution time, bytes scanned, and rows produced.

If using ACCOUNT_USAGE, account for its documented latency.

---

# Part 93 — Compare Telemetry Sources

## 108. Exercise

For a query that just completed:

1. Locate it through the appropriate recent-query interface.
2. Attempt to locate it through ACCOUNT_USAGE.
3. Record whether it is already visible.
4. Compare available fields.
5. Document freshness differences.

This demonstrates why metadata latency matters during incidents.

---

# Part 94 — Warehouse Metering Exercise

## 109. Query Credits

Using the approved lab warehouse, inspect warehouse metering for a controlled period.

Record warehouse, period, and credits used.

Do not attempt to attribute a tiny individual query's exact cost simply by dividing hourly warehouse credits without accounting for shared warehouse activity and billing behavior.

---

# Part 95 — Failure Exercise

## 110. Generate a Harmless Failure

In the lab only:

```sql
SELECT *
FROM metadata_lab.demo.object_that_does_not_exist;
```

Then locate the failed query in the appropriate query-history interface.

Capture query ID, status, error code, error message, user, and role.

---

# Part 96 — Query Attribution Exercise

## 111. Set a Lab Query Tag

Using current Snowflake-supported syntax, assign a clearly identifiable lab query tag such as:

```text
tutorial=chapter46
environment=lab
```

Run several lab queries and then find and group them using metadata.

---

# Part 97 — Storage Exercise

## 112. Inspect Metadata

Determine table, rows, bytes, creation time, and owner using the appropriate metadata interfaces.

Compare logical row count with physical/storage telemetry where available.

---

# Part 98 — Cleanup

## 113. Drop Lab Database

```sql
DROP DATABASE IF EXISTS metadata_lab;
```

Restore any session parameters or query tags changed for the lab.

---

# Part 99 — Production Checklist

## 114. Metadata Source

```text
□ Correct source selected
□ Scope understood
□ Freshness understood
□ Retention understood
□ Privileges understood
```

## 115. Query History

```text
□ Time range bounded
□ Timezone explicit
□ Query IDs captured
□ User captured
□ Role captured
□ Warehouse captured
□ Query tag captured
```

## 116. Performance

```text
□ Elapsed time
□ Execution time
□ Queue time
□ Bytes scanned
□ Spill
□ Query Profile
```

## 117. Warehouse

```text
□ Metering
□ Load
□ Queueing
□ Size
□ Cluster configuration
```

## 118. Cost

```text
□ Credits by warehouse
□ Trend
□ Baseline
□ Anomaly
```

## 119. Security

```text
□ User
□ Role
□ Grants
□ Access history
□ Sensitive query text protected
```

## 120. Pipeline

```text
□ Tasks
□ Pipes
□ Copy history
□ Load failures
```

---

# Part 100 — Common Mistakes

## 121. Mistake 1

Using ACCOUNT_USAGE as though every view were real time.

## 122. Mistake 2

Assuming Information Schema and Account Usage have identical retention.

## 123. Mistake 3

Running metadata queries without time filters.

## 124. Mistake 4

Treating no rows as proof that nothing happened.

## 125. Mistake 5

Ignoring role visibility and privileges.

## 126. Mistake 6

Mixing different queue-time causes.

## 127. Mistake 7

Treating execution time as billed warehouse time.

## 128. Mistake 8

Exporting raw query text into unsecured observability systems.

## 129. Mistake 9

Using daily averages to investigate a five-minute incident.

## 130. Mistake 10

Building production automation around undocumented assumptions about metadata latency or retention.

---

# Part 101 — Operational Principles

## 131. Principle 1

Know the question before choosing the metadata source.

## 132. Principle 2

Understand telemetry freshness.

## 133. Principle 3

Understand retention.

## 134. Principle 4

Use explicit time windows.

## 135. Principle 5

Use explicit timezones.

## 136. Principle 6

Use least privilege for metadata access.

## 137. Principle 7

Separate queue causes.

## 138. Principle 8

Do not confuse query runtime with warehouse billing.

## 139. Principle 9

Protect query text as potentially sensitive operational data.

## 140. Principle 10

Build reusable operational queries instead of troubleshooting from scratch during every incident.

---

# Part 102 — DBRE/SRE Metadata Workflow

## 141. Production Flow

```text
Operational question
        |
        v
Determine scope
        |
        v
Need current or historical data?
        |
        v
Choose metadata interface
        |
        v
Validate freshness
        |
        v
Validate privileges
        |
        v
Bound time window
        |
        v
Collect evidence
        |
        v
Correlate query + warehouse + cost
        |
        v
Reach conclusion
```

---

# Acceptance Criteria

The chapter is complete when you can:

- explain why Snowflake operational metadata matters
- distinguish ACCOUNT_USAGE from INFORMATION_SCHEMA
- understand account-level versus database-level scope
- understand metadata views and table functions
- investigate query history
- interpret query timing units
- identify slow queries
- identify failed queries
- measure query volume
- group query volume by warehouse
- distinguish overload, provisioning, and repair queueing
- investigate bytes scanned
- investigate local and remote spill
- attribute workload by user
- attribute workload by role
- use query tags for workload attribution
- analyze warehouse metering
- trend warehouse credits
- distinguish credit components
- use warehouse load telemetry
- correlate performance and cost
- investigate storage growth
- inspect table metadata
- inspect column metadata
- inspect schema metadata
- inspect view metadata
- understand historical object metadata
- account for deleted objects
- inspect user metadata
- inspect roles and grants
- understand role hierarchy
- use access history conceptually
- investigate data lineage
- investigate task execution
- investigate Snowpipe activity
- investigate copy/load history
- understand metadata latency
- avoid treating Account Usage as universally real time
- understand metadata retention differences
- validate privileges before interpreting missing rows
- design least-privilege metadata access
- write efficient metadata queries
- avoid unnecessary SELECT *
- bound operational queries by time
- correlate timezones
- use UTC effectively for incident correlation
- build incident queries
- build performance queries
- build queue-analysis queries
- build workload-attribution queries
- build cost-analysis queries
- detect cost anomalies
- support security investigations
- review dormant users
- review object ownership
- design long-term metadata retention
- protect sensitive query text
- design a monitoring architecture
- define metadata dashboards
- define useful alerts
- troubleshoot missing Account Usage data
- troubleshoot Information Schema visibility
- troubleshoot slow metadata queries
- select the correct metadata source
- execute a production incident workflow
- capture a complete operational evidence record
- perform the hands-on metadata lab
- compare metadata freshness
- inspect warehouse metering
- investigate failed queries
- use query tags in a lab
- inspect storage metadata
- clean up lab resources
- apply the production checklist
- avoid common metadata mistakes
- follow DBRE/SRE operational principles

---

## Key Takeaways

Snowflake provides multiple metadata interfaces because operational questions have different requirements.

The core distinction is:

```text
ACCOUNT_USAGE
     |
     v
Account-wide historical
operational analysis
```

versus:

```text
INFORMATION_SCHEMA
     |
     v
Database metadata
and applicable operational
functions/interfaces
```

Before querying either, ask:

```text
What scope do I need?
        |
        v
How fresh must the data be?
        |
        v
How far back must I look?
        |
        v
What can my role see?
```

For production incidents:

```text
Incident
   |
   v
Define time window
   |
   v
Capture query IDs
   |
   v
Query history
   |
   +---- Queue
   +---- Execution
   +---- Scan
   +---- Spill
   |
   v
Warehouse load
   |
   v
Warehouse metering
   |
   v
Workload attribution
   |
   v
Root cause
```

For FinOps:

```text
Warehouse metering
      |
      v
Credits by warehouse
      |
      v
Trend
      |
      v
Workload correlation
      |
      v
Optimization
```

For security:

```text
Users + Roles + Grants
          |
          v
     Access history
          |
          v
      Investigation
```

The most important operational lesson is:

> Metadata is evidence only when you understand its scope, freshness, retention, units, and visibility.

The next chapter is **Chapter 47 — Query History & Workload Analysis**.
