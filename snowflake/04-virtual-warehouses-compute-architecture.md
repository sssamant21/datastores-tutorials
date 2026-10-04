# 04 — Virtual Warehouses & Compute Architecture

**Status:** Canonical  
**Part:** 1 — Foundations & Architecture  
**Goal:** Understand virtual warehouses, sizing, lifecycle, concurrency, caching, workload isolation, performance, and cost implications.

A Snowflake virtual warehouse is a cluster of compute resources used to execute queries and DML. Warehouses can be resized, suspended, and resumed independently of persistent table storage.

## 1. What Is a Virtual Warehouse?

```text
                  Snowflake Storage
                         |
        +----------------+----------------+
        |                |                |
        v                v                v
      ETL_WH       REPORTING_WH         APP_WH
        |                |                |
   Data Loading      Analytics       Application
```

Independent compute is one of Snowflake's core workload-isolation mechanisms.

## 2. Warehouse Sizes

Snowflake provides warehouse sizes from X-Small upward.

```text
X-Small
   |
 Small
   |
 Medium
   |
 Large
   |
 X-Large
   |
2X-Large
   |
...
```

For standard warehouse sizes, each size step generally provides approximately twice the compute resources and approximately twice the credit rate of the previous size.

Example:

```sql
CREATE WAREHOUSE ETL_WH
    WAREHOUSE_SIZE = 'MEDIUM';
```

## 3. Create a Production-Style Warehouse

```sql
CREATE WAREHOUSE ETL_WH
    WAREHOUSE_SIZE = 'MEDIUM'
    AUTO_SUSPEND = 300
    AUTO_RESUME = TRUE
    INITIALLY_SUSPENDED = TRUE;
```

Inspect and select it:

```sql
SHOW WAREHOUSES LIKE 'ETL_WH';
USE WAREHOUSE ETL_WH;
SELECT CURRENT_WAREHOUSE();
```

## 4. Warehouse Lifecycle

```text
Created
   |
   v
Suspended
   |
   v
Resumed
   |
   v
Running
   |
   v
Suspended
```

Commands:

```sql
ALTER WAREHOUSE ETL_WH RESUME;
ALTER WAREHOUSE ETL_WH SUSPEND;

ALTER WAREHOUSE ETL_WH
SET WAREHOUSE_SIZE = 'LARGE';
```

Warehouses can be resized without first suspending them.

## 5. Auto-Suspend

```sql
ALTER WAREHOUSE ETL_WH
SET AUTO_SUSPEND = 300;
```

Conceptually:

```text
No warehouse activity
       |
       v
Wait configured period
       |
       v
Suspend warehouse
```

Auto-suspend is one of the simplest controls for reducing idle warehouse compute.

## 6. Auto-Resume

```sql
ALTER WAREHOUSE ETL_WH
SET AUTO_RESUME = TRUE;
```

```text
Warehouse suspended
       |
       v
Eligible query arrives
       |
       v
Warehouse resumes
       |
       v
Query executes
```

## 7. Do Not Set Auto-Suspend Blindly

An aggressively short suspend interval can create a pattern like:

```text
Query
 |
Warehouse starts
 |
Query completes
 |
Warehouse suspends
 |
Next query
 |
Warehouse starts again
```

This can reduce warehouse-cache reuse and can repeatedly trigger minimum billing on warehouse starts. Choose lifecycle settings according to workload patterns.

Examples:

```text
ETL batch warehouse
-> aggressive suspension may make sense

Interactive BI warehouse
-> balance cache reuse against idle cost

Always-active application
-> different lifecycle requirements
```

## 8. Warehouse Billing

Warehouse compute is billed using Snowflake credits. For standard sizes, the rate approximately doubles at each size step:

```text
X-Small    1x
Small      2x
Medium     4x
Large      8x
X-Large   16x
```

Warehouse usage is billed per second after a minimum charge each time a warehouse starts. Check current Snowflake pricing/compute documentation for exact billing behavior.

## 9. Scale Up

```text
MEDIUM
   |
   v
LARGE
```

```sql
ALTER WAREHOUSE ANALYTICS_WH
SET WAREHOUSE_SIZE = 'LARGE';
```

Scale up when evidence shows that an individual workload can benefit from additional compute/memory.

Do not assume:

```text
Slow query = need larger warehouse
```

## 10. Diagnose Before Scaling

```text
Slow Query
   |
   +-- Poor partition pruning
   +-- Huge table scan
   +-- Join explosion
   +-- Memory spilling
   +-- Query queueing
   +-- High concurrency
   +-- Complex SQL
   +-- Warehouse undersized
```

Warehouse resizing addresses only some of these causes.

## 11. Scale Out

Concurrency can produce queueing:

```text
                  REPORTING_WH
                       |
       +---------------+---------------+
       |               |               |
    Query 1         Query 2         Query N
```

Multi-cluster warehouses can add clusters for concurrency:

```text
                REPORTING_WH
                     |
        +------------+------------+
        |            |            |
    Cluster 1    Cluster 2    Cluster 3
```

This is scale out.

## 12. Scale Up vs Scale Out

| Problem | Investigate / Consider |
|---|---|
| Individual query needs more resources | Query profile, then possible scale up |
| Memory spilling | Query design and possible scale up |
| Many concurrent queries | Concurrency and possible scale out |
| Queries queueing | Workload isolation / multi-cluster |
| Poor pruning | Query/data access pattern |
| Bad join | Query correction |
| Idle cost | Lifecycle configuration |

```text
Performance problem
       |
       +-- Query resource problem
       |       |
       |       +--> Scale UP?
       |
       +-- Concurrency problem
               |
               +--> Scale OUT?
```

## 13. Multi-Cluster Warehouse

Example:

```sql
CREATE WAREHOUSE REPORTING_WH
    WAREHOUSE_SIZE = 'MEDIUM'
    MIN_CLUSTER_COUNT = 1
    MAX_CLUSTER_COUNT = 3
    SCALING_POLICY = 'STANDARD'
    AUTO_SUSPEND = 300
    AUTO_RESUME = TRUE
    INITIALLY_SUSPENDED = TRUE;
```

Multi-cluster warehouse availability depends on Snowflake edition. Verify current edition requirements before adopting it.

## 14. Scaling Policies

Multi-cluster warehouses support policies including:

```text
STANDARD
ECONOMY
```

At a high level, STANDARD favors responsiveness to queueing, while ECONOMY favors conserving credits by requiring more sustained workload before additional clusters remain active. Validate exact current behavior in Snowflake documentation.

## 15. Warehouse Cache

```text
Query 1
   |
   v
Warehouse
   |
   +----> Remote Storage
              |
              v
          Local Cache

Query 2
   |
   v
Warehouse
   |
   +----> Local Cache where reusable
```

Repeated workloads can benefit when needed data remains cached.

## 16. Result Cache vs Warehouse Cache

These are different:

```text
Persisted query result
    |
Previously computed query result may be reused
```

versus:

```text
Warehouse cache
    |
Table data cached on warehouse compute
```

A query can sometimes reuse a persisted result without substantial warehouse execution. Warehouse cache instead reduces remote data reads during warehouse execution.

## 17. Workload Isolation

Anti-pattern:

```text
                  PROD_WH
                     |
     +---------------+---------------+
     |               |               |
   ETL jobs      BI reports       Application
```

Better when isolation is required:

```text
                 Shared Snowflake Data
                          |
          +---------------+---------------+
          |               |               |
          v               v               v
       ETL_WH       REPORTING_WH        APP_WH
          |               |               |
      Pipelines       BI users        Application
```

Each can have independent size, scaling, auto-suspend, monitoring, cost attribution, and resource controls.

## 18. Warehouse Monitoring

Inspect configuration:

```sql
SHOW WAREHOUSES;
```

Historical usage:

```sql
SELECT
    START_TIME,
    END_TIME,
    WAREHOUSE_NAME,
    CREDITS_USED,
    CREDITS_USED_COMPUTE,
    CREDITS_USED_CLOUD_SERVICES
FROM SNOWFLAKE.ACCOUNT_USAGE.WAREHOUSE_METERING_HISTORY
WHERE START_TIME >= DATEADD('day', -7, CURRENT_TIMESTAMP())
ORDER BY START_TIME DESC;
```

ACCOUNT_USAGE is not guaranteed to be real-time.

## 19. Detect Query Queueing

```sql
SELECT
    QUERY_ID,
    WAREHOUSE_NAME,
    TOTAL_ELAPSED_TIME,
    EXECUTION_TIME,
    QUEUED_OVERLOAD_TIME,
    QUEUED_PROVISIONING_TIME,
    BYTES_SCANNED
FROM SNOWFLAKE.ACCOUNT_USAGE.QUERY_HISTORY
WHERE START_TIME >= DATEADD('hour', -1, CURRENT_TIMESTAMP())
ORDER BY START_TIME DESC;
```

Useful fields include:

```text
TOTAL_ELAPSED_TIME
EXECUTION_TIME
QUEUED_OVERLOAD_TIME
QUEUED_PROVISIONING_TIME
```

Queueing and execution time should be separated before deciding on remediation.

## 20. Operational Troubleshooting Flow

```text
Slow workload
     |
     v
Are queries queued?
     |
 +---+---+
 |       |
YES      NO
 |       |
 v       v
Check    Check Query Profile
concurrency       |
                  +-- Scan volume
                  +-- Pruning
                  +-- Join explosion
                  +-- Spill
                  +-- Execution operators
```

If queueing dominates:

```text
Queueing
   |
   +-- Too much concurrency?
   +-- Workloads sharing warehouse?
   +-- Warehouse provisioning/resizing?
   +-- Multi-cluster appropriate?
```

If execution dominates:

```text
Execution
   |
   +-- Poor pruning?
   +-- Large scans?
   +-- Spill?
   +-- Bad joins?
   +-- Warehouse too small?
```

## 21. Production Example

```text
                     SNOWFLAKE DATA
                           |
       +-------------------+-------------------+
       |                   |                   |
       v                   v                   v
    INGEST_WH         ANALYTICS_WH          APP_WH
     MEDIUM               LARGE              SMALL
       |                   |                   |
     Batch             BI / Ad Hoc          API/App
```

There is no universal warehouse size.

```text
Workload
   +
Concurrency
   +
Latency requirement
   +
Memory requirement
   +
Cost objective
   =
Sizing decision
```

## 22. Hands-On Lab

```sql
CREATE WAREHOUSE TUTORIAL_WH
    WAREHOUSE_SIZE = 'XSMALL'
    AUTO_SUSPEND = 60
    AUTO_RESUME = TRUE
    INITIALLY_SUSPENDED = TRUE;

SHOW WAREHOUSES LIKE 'TUTORIAL_WH';

USE WAREHOUSE TUTORIAL_WH;

SELECT
    CURRENT_WAREHOUSE(),
    CURRENT_DATABASE(),
    CURRENT_SCHEMA();

ALTER WAREHOUSE TUTORIAL_WH
SET WAREHOUSE_SIZE = 'SMALL';

SHOW WAREHOUSES LIKE 'TUTORIAL_WH';

ALTER WAREHOUSE TUTORIAL_WH
SET WAREHOUSE_SIZE = 'XSMALL';

ALTER WAREHOUSE TUTORIAL_WH SUSPEND;
```

## 23. Cleanup

```sql
DROP WAREHOUSE IF EXISTS TUTORIAL_WH;
```

## Production Takeaways

- Separate workloads where isolation matters.
- Use auto-suspend and auto-resume deliberately.
- Do not resize simply because a query is slow.
- Scale up primarily for per-query resource requirements.
- Scale out when concurrency is the bottleneck.
- Check queueing, pruning, spilling, joins, and Query Profile before changing compute.
- Monitor credit usage alongside performance.

## Technical references

- Warehouse overview: https://docs.snowflake.com/en/user-guide/warehouses-overview
- Warehouse considerations: https://docs.snowflake.com/en/user-guide/warehouses-considerations
- Multi-cluster warehouses: https://docs.snowflake.com/en/user-guide/warehouses-multicluster
- Compute cost: https://docs.snowflake.com/en/user-guide/cost-understanding-compute
- Query history: https://docs.snowflake.com/en/sql-reference/account-usage/query_history
- Warehouse metering history: https://docs.snowflake.com/en/sql-reference/account-usage/warehouse_metering_history
