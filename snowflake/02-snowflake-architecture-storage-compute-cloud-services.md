# 02 — Snowflake Architecture: Storage, Compute & Cloud Services

**Status:** Canonical  
**Part:** 1 — Foundations & Architecture  
**Goal:** Understand how Snowflake processes workloads and how the storage, compute, and cloud services layers affect performance, scalability, isolation, and cost.

## 1. Architecture Overview

```text
                    Users / Applications
                           |
                           v
              +--------------------------+
              |     CLOUD SERVICES       |
              | Authentication           |
              | Authorization            |
              | Metadata                 |
              | Query Parsing            |
              | Query Optimization       |
              | Transaction Management   |
              +------------+-------------+
                           |
                           v
              +--------------------------+
              |         COMPUTE          |
              | Virtual Warehouses       |
              | ETL_WH / REPORTING_WH    |
              | APP_WH / ANALYTICS_WH    |
              +------------+-------------+
                           |
                           v
              +--------------------------+
              |          STORAGE         |
              | Tables                   |
              | Micro-partitions         |
              | Compressed Columnar Data |
              | Persistent Cloud Storage |
              +--------------------------+
```

The key architectural idea is that storage, compute, and cloud services are separate layers managed by Snowflake.

## 2. Storage Layer

For Snowflake-managed tables, Snowflake reorganizes loaded data into an internally optimized, compressed, columnar format and stores it in cloud storage. Snowflake manages physical organization, storage metadata, and statistics.

Users do not manually manage database files such as:

```text
/data/database01.dbf
/data/table01.dat
/data/index01.idx
```

## 3. Micro-Partitions

Snowflake automatically divides table data into micro-partitions and maintains metadata that can help determine which partitions need to be scanned.

Conceptually:

```text
Logical Table
     |
     v
Micro-partitions
     |
 +---+---+---+---+
 |   |   |   |   |
 MP1 MP2 MP3 MP4 MP5
     |
     v
Cloud Storage
```

Suppose metadata indicates:

```text
MP1  SERVICE_DATE Jan 1–5
MP2  SERVICE_DATE Jan 5–12
MP3  SERVICE_DATE Jan 12–20
MP4  SERVICE_DATE Jan 20–31
```

For:

```sql
SELECT *
FROM CLAIMS
WHERE SERVICE_DATE = '2026-01-06';
```

Snowflake may be able to prune partitions whose metadata proves they cannot contain qualifying rows.

```text
MP1    MP2    MP3    MP4
 X      ✓      X      X
```

Micro-partition pruning is a core performance concept and is covered deeply later.

## 4. Compute Layer

Virtual warehouses provide compute for queries and DML.

```text
                   Shared Snowflake Data
                           |
          +----------------+----------------+
          |                |                |
          v                v                v
     INGEST_WH        REPORTING_WH      APP_WH
       MEDIUM             LARGE          SMALL
          |                |                |
       ETL jobs        BI queries      Application
```

Warehouses can access common data while providing independent compute resources.

## 5. Workload Isolation

A shared warehouse can mix very different workload characteristics:

```text
               SHARED_WH
                   |
      +------------+-------------+
      |            |             |
     ETL        BI/Reports    Application
```

A production design may isolate them:

```text
ETL          -> ETL_WH
Reporting    -> REPORTING_WH
Application  -> APP_WH
```

This can improve workload isolation, monitoring, and cost attribution.

## 6. Warehouse Scaling

Resize:

```sql
ALTER WAREHOUSE ANALYTICS_WH
SET WAREHOUSE_SIZE = 'LARGE';
```

Scale down:

```sql
ALTER WAREHOUSE ANALYTICS_WH
SET WAREHOUSE_SIZE = 'MEDIUM';
```

A larger warehouse is not automatically the correct solution for every slow query. Poor pruning, inefficient joins, queueing, spilling, or other bottlenecks may be the real cause.

## 7. Scale Up vs Scale Out

**Scale up** means increasing warehouse size:

```text
SMALL -> MEDIUM -> LARGE
```

It can help individual workloads that benefit from additional compute/memory.

**Scale out** means using multiple clusters in a multi-cluster warehouse:

```text
              REPORTING_WH
                    |
          +---------+---------+
          |         |         |
       Cluster 1 Cluster 2 Cluster 3
```

Multi-cluster warehouses primarily address concurrency.

```text
Slow individual query
        |
        v
Investigate query + possible scale-up

Many queries waiting
        |
        v
Investigate concurrency + possible scale-out
```

## 8. Warehouse Lifecycle

Create:

```sql
CREATE WAREHOUSE ETL_WH
    WAREHOUSE_SIZE = 'MEDIUM'
    AUTO_SUSPEND = 60
    AUTO_RESUME = TRUE
    INITIALLY_SUSPENDED = TRUE;
```

Resume:

```sql
ALTER WAREHOUSE ETL_WH RESUME;
```

Suspend:

```sql
ALTER WAREHOUSE ETL_WH SUSPEND;
```

Inspect:

```sql
SHOW WAREHOUSES;
```

Warehouse lifecycle configuration affects both compute consumption and cache behavior.

## 9. Warehouse Cache

Compute nodes can cache table data locally while the warehouse remains available.

```text
First query:
Warehouse -> remote storage -> local warehouse cache

Later query:
Warehouse -> local warehouse cache where reusable
```

Aggressive suspension can reduce idle cost but can also reduce warehouse cache reuse. Treat this as a workload-specific tradeoff.

## 10. Cloud Services Layer

Cloud services coordinate activities including authentication, authorization, metadata management, query parsing/optimization, and transaction coordination.

Simplified flow:

```text
SELECT ...
    |
    v
Cloud Services
    |
    +-- Authenticate
    +-- Authorize
    +-- Parse SQL
    +-- Resolve objects
    +-- Optimize query
    |
    v
Virtual Warehouse
    |
    +-- Execute plan
    +-- Scan required data
    |
    v
Result
```

## 11. Cloud Services Are Not the Warehouse

A query can involve:

```text
Cloud Services
     +
Warehouse Compute
     +
Storage Access
```

Not every performance problem is a warehouse sizing problem. Compilation/optimization complexity and metadata-heavy activity can also matter.

## 12. Query Execution Lifecycle

For:

```sql
SELECT
    CUSTOMER_ID,
    SUM(AMOUNT)
FROM SALES
WHERE SALE_DATE >= '2026-01-01'
GROUP BY CUSTOMER_ID;
```

A simplified lifecycle is:

```text
Client
  |
  v
Cloud Services
  +-- Authentication
  +-- Authorization
  +-- Parsing
  +-- Metadata lookup
  +-- Optimization
  |
  v
Execution Plan
  |
  v
Virtual Warehouse
  +-- Determine required partitions
  +-- Reuse cached data where possible
  +-- Read remaining data
  +-- Filter
  +-- Aggregate
  |
  v
Result
```

## 13. Architecture-Based Troubleshooting

```text
                 SNOWFLAKE SLOW
                       |
        +--------------+--------------+
        |              |              |
      STORAGE        COMPUTE      CLOUD SERVICES
        |              |              |
   Poor pruning     Queueing       Compilation
   Large scans      Spilling       Metadata
   Clustering       Undersized     Optimization
   Data layout      Concurrency    High-frequency DDL
```

For compute, investigate queueing, spilling, warehouse size, concurrency, cache behavior, and query characteristics before changing capacity.

## 14. Do Not Automatically Resize

Before:

```sql
ALTER WAREHOUSE PROD_WH
SET WAREHOUSE_SIZE = 'XLARGE';
```

ask:

```text
90-second query
       |
       +-- 40 sec queueing?
       +-- billions of rows scanned?
       +-- poor pruning?
       +-- spilling?
       +-- join explosion?
       +-- compilation overhead?
       +-- warehouse contention?
```

Scale only after identifying the bottleneck.

## 15. Cost Relationship

```text
Snowflake Cost
     |
     +-- Storage
     +-- Virtual Warehouse Compute
     +-- Serverless Compute
     +-- Cloud Services
     +-- Other applicable services
```

Architecture knowledge is therefore necessary for FinOps.

## 16. Production Design Example

```text
                   SNOWFLAKE DATA
                         |
       +-----------------+-----------------+
       |                 |                 |
       v                 v                 v
    ETL_WH          REPORTING_WH         APP_WH
    MEDIUM              LARGE             SMALL
       |                 |                 |
   Pipelines         Dashboards        Application
```

Each workload can have its own size, lifecycle settings, scaling behavior, monitoring, resource controls, and cost attribution.

## 17. Hands-On Lab

```sql
CREATE WAREHOUSE TUTORIAL_ETL_WH
    WAREHOUSE_SIZE = 'XSMALL'
    AUTO_SUSPEND = 60
    AUTO_RESUME = TRUE
    INITIALLY_SUSPENDED = TRUE;

CREATE WAREHOUSE TUTORIAL_REPORTING_WH
    WAREHOUSE_SIZE = 'XSMALL'
    AUTO_SUSPEND = 60
    AUTO_RESUME = TRUE
    INITIALLY_SUSPENDED = TRUE;

CREATE WAREHOUSE TUTORIAL_APP_WH
    WAREHOUSE_SIZE = 'XSMALL'
    AUTO_SUSPEND = 60
    AUTO_RESUME = TRUE
    INITIALLY_SUSPENDED = TRUE;
```

Inspect and switch compute:

```sql
SHOW WAREHOUSES;

USE WAREHOUSE TUTORIAL_ETL_WH;
SELECT CURRENT_USER(), CURRENT_ROLE(), CURRENT_WAREHOUSE();

USE WAREHOUSE TUTORIAL_REPORTING_WH;
SELECT CURRENT_WAREHOUSE();
```

This demonstrates:

```text
Same Data
Different Compute
```

## 18. Cleanup

```sql
DROP WAREHOUSE IF EXISTS TUTORIAL_ETL_WH;
DROP WAREHOUSE IF EXISTS TUTORIAL_REPORTING_WH;
DROP WAREHOUSE IF EXISTS TUTORIAL_APP_WH;
```

## Production Takeaways

- Storage and compute are separated.
- Virtual warehouses provide independent compute and enable workload isolation.
- Micro-partition pruning is central to scan efficiency.
- Scale up and scale out solve different problems.
- A slow query does not automatically mean the warehouse is too small.
- Architecture, performance, and cost are tightly connected.

## Technical references

- Key concepts: https://docs.snowflake.com/en/user-guide/intro-key-concepts
- Virtual warehouses: https://docs.snowflake.com/en/user-guide/warehouses
- Query performance: https://docs.snowflake.com/en/user-guide/performance-query-warehouse
- Storage optimization: https://docs.snowflake.com/en/user-guide/performance-query-storage
