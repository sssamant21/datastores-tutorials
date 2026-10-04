# 01 — Snowflake Fundamentals

**Status:** Canonical  
**Part:** 1 — Foundations & Architecture  
**Goal:** Establish the Snowflake concepts needed for every later tutorial.

## 1. What is Snowflake?

Snowflake is a cloud-native data platform for storing, processing, analyzing, and sharing structured, semi-structured, and unstructured data. A foundational architectural characteristic is the separation of persistent storage, compute, and cloud services.

```text
Applications / BI / Users
          |
          v
+-------------------------+
|     Cloud Services      |
| Auth / Metadata / SQL   |
+-------------------------+
          |
          v
+-------------------------+
|   Virtual Warehouses    |
|      Compute Layer      |
+-------------------------+
          |
          v
+-------------------------+
|   Centralized Storage   |
|      Data Layer         |
+-------------------------+
```

## 2. Three Core Architectural Layers

### Storage layer

Snowflake manages how table data is stored, compressed, organized, and distributed in cloud storage. Users do not manage traditional database files, disks, or storage volumes for Snowflake-managed table storage.

### Compute layer

Queries execute on compute clusters called **virtual warehouses**.

Examples:

```text
ETL_WH
REPORTING_WH
ANALYTICS_WH
DATA_SCIENCE_WH
```

Different workloads can use different warehouses while accessing the same underlying Snowflake data.

### Cloud services layer

The cloud services layer coordinates activities such as authentication, access control, metadata management, query parsing and optimization, and transaction management.

Tutorial 02 examines all three layers in greater depth.

## 3. Basic Snowflake Object Hierarchy

```text
Organization
   |
   +-- Account
        |
        +-- Database
             |
             +-- Schema
                  |
                  +-- Tables
                  +-- Views
                  +-- Stages
                  +-- File Formats
                  +-- Streams
                  +-- Tasks
                  +-- Procedures
                  +-- Functions
```

For example:

```text
Database: DAP
Schema:   L2
Table:    EMPI
```

The fully qualified table name is:

```sql
DAP.L2.EMPI
```

## 4. First Snowflake Commands

Check the current session:

```sql
SELECT
    CURRENT_USER(),
    CURRENT_ROLE(),
    CURRENT_WAREHOUSE(),
    CURRENT_DATABASE(),
    CURRENT_SCHEMA();
```

View databases:

```sql
SHOW DATABASES;
```

Create and select a training database:

```sql
CREATE DATABASE SNOWFLAKE_TUTORIAL;
USE DATABASE SNOWFLAKE_TUTORIAL;
```

Create and select a schema:

```sql
CREATE SCHEMA LAB;
USE SCHEMA LAB;
```

## 5. Working with a Virtual Warehouse

Create a small lab warehouse:

```sql
CREATE WAREHOUSE TUTORIAL_WH
    WAREHOUSE_SIZE = 'XSMALL'
    AUTO_SUSPEND = 60
    AUTO_RESUME = TRUE
    INITIALLY_SUSPENDED = TRUE;
```

Select it:

```sql
USE WAREHOUSE TUTORIAL_WH;
```

Inspect warehouses:

```sql
SHOW WAREHOUSES;
```

`AUTO_SUSPEND` is an important control for reducing idle compute consumption.

## 6. Create Your First Table

```sql
CREATE TABLE employees (
    employee_id INTEGER,
    employee_name VARCHAR,
    department VARCHAR,
    salary NUMBER(10,2),
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP()
);
```

Insert records:

```sql
INSERT INTO employees
    (employee_id, employee_name, department, salary)
VALUES
    (1, 'Alice', 'Engineering', 120000),
    (2, 'Bob', 'Database', 115000),
    (3, 'Carol', 'Analytics', 110000);
```

Query:

```sql
SELECT *
FROM employees;
```

## 7. Basic DML Operations

Update:

```sql
UPDATE employees
SET salary = 125000
WHERE employee_id = 1;
```

Delete:

```sql
DELETE FROM employees
WHERE employee_id = 3;
```

Insert:

```sql
INSERT INTO employees
VALUES (
    4,
    'David',
    'Platform',
    118000,
    CURRENT_TIMESTAMP()
);
```

Later tutorials cover `MERGE`, bulk loading, Snowpipe, Streams, Tasks, and production ingestion patterns.

## 8. Snowflake Roles

Snowflake uses role-based access control.

```sql
SELECT CURRENT_ROLE();
SHOW ROLES;
```

A simplified hierarchy might look like:

```text
ACCOUNTADMIN
     |
  SYSADMIN
     |
DATA_ENGINEER_ROLE
     |
ANALYST_ROLE
```

Production users should follow least-privilege practices rather than routinely operating with the highest administrative role.

## 9. Warehouses and Workload Isolation

Instead of making ingestion, application, and reporting workloads compete on one warehouse, they can use independent compute:

```text
                Snowflake Storage
                      |
        +-------------+-------------+
        |             |             |
        v             v             v
   INGEST_WH       APP_WH      REPORTING_WH
```

This provides compute isolation while allowing the workloads to access shared data.

## 10. Why Snowflake Is Different

Important concepts include:

- **Storage and compute separation** — compute can scale independently of stored data.
- **Virtual warehouses** — different workloads can use independent compute.
- **Managed storage** — users do not administer database data files or storage volumes.
- **Micro-partitions** — Snowflake automatically organizes Snowflake-managed table data into internal storage units.
- **Zero-copy cloning** — supported objects can be cloned without initially copying all underlying data.
- **Time Travel** — historical object/data states can be accessed within applicable retention rules.
- **Secure Data Sharing** — supported data can be shared without traditional file-copy pipelines.

Each topic receives dedicated treatment later.

## 11. Basic Troubleshooting Commands

When someone reports "Snowflake is slow," do not immediately resize a warehouse.

Start by identifying the workload:

```sql
SELECT
    query_id,
    user_name,
    warehouse_name,
    execution_status,
    total_elapsed_time,
    query_text
FROM SNOWFLAKE.ACCOUNT_USAGE.QUERY_HISTORY
ORDER BY start_time DESC
LIMIT 20;
```

Check warehouses:

```sql
SHOW WAREHOUSES;
```

Check context:

```sql
SELECT
    CURRENT_USER(),
    CURRENT_ROLE(),
    CURRENT_WAREHOUSE(),
    CURRENT_DATABASE(),
    CURRENT_SCHEMA();
```

A useful investigation model is:

```text
Slow query
   |
   +-- Poor pruning
   +-- Large scan
   +-- Warehouse undersized
   +-- Warehouse queueing
   +-- Concurrency
   +-- Data skew / row explosion
   +-- Expensive joins
   +-- Cloud services overhead
   +-- Loading workload
   +-- Network/client latency
```

**Operational note:** ACCOUNT_USAGE views are historical/observability interfaces and can have latency. Do not treat them as guaranteed real-time telemetry.

## 12. Hands-On Lab

Build:

```text
Database:  SNOWFLAKE_TUTORIAL
Schema:    LAB
Warehouse: TUTORIAL_WH
Table:     EMPLOYEES
```

Verify:

```sql
SELECT CURRENT_DATABASE();
SELECT CURRENT_SCHEMA();
SELECT CURRENT_WAREHOUSE();

SELECT *
FROM SNOWFLAKE_TUTORIAL.LAB.EMPLOYEES;
```

Inspect recent query history:

```sql
SELECT
    query_id,
    query_type,
    warehouse_name,
    total_elapsed_time,
    bytes_scanned,
    rows_produced
FROM SNOWFLAKE.ACCOUNT_USAGE.QUERY_HISTORY
WHERE user_name = CURRENT_USER()
ORDER BY start_time DESC
LIMIT 20;
```

## 13. Cleanup

```sql
DROP DATABASE IF EXISTS SNOWFLAKE_TUTORIAL;
DROP WAREHOUSE IF EXISTS TUTORIAL_WH;
```

## Production Takeaways

```text
Snowflake
|
+-- Storage
+-- Compute
|   +-- Virtual Warehouses
+-- Cloud Services
+-- Databases
|   +-- Schemas
|       +-- Objects
+-- RBAC
+-- Consumption-based operation
```

The most important foundation is the separation of storage and compute. Many later decisions about performance tuning, workload isolation, scaling, concurrency, and cost follow from this architecture.

## Technical references

- Snowflake key concepts: https://docs.snowflake.com/en/user-guide/intro-key-concepts
- Virtual warehouses: https://docs.snowflake.com/en/user-guide/warehouses
- Access control overview: https://docs.snowflake.com/en/user-guide/security-access-control-overview
- Query history: https://docs.snowflake.com/en/sql-reference/account-usage/query_history
