# 03 — Databases, Schemas, Tables & Objects

**Status:** Canonical  
**Part:** 1 — Foundations & Architecture  
**Goal:** Understand Snowflake's logical object hierarchy, namespaces, object naming, session context, and core commands for managing database objects.

## 1. Snowflake Object Hierarchy

A database is a logical container for schemas, and schemas provide namespaces for many database objects.

```text
Snowflake Account
|
+-- Warehouses
+-- Users
+-- Roles
+-- Databases
    |
    +-- DEV
    |   +-- RAW
    |   +-- STAGING
    |   +-- CURATED
    |
    +-- PROD
        +-- RAW
        +-- STAGING
        +-- CURATED
```

Inside a schema you can have objects such as:

```text
Schema
|
+-- Tables
+-- Views
+-- Materialized Views
+-- Stages
+-- File Formats
+-- Sequences
+-- Streams
+-- Tasks
+-- Functions
+-- Procedures
```

## 2. Database

Create:

```sql
CREATE DATABASE SNOWFLAKE_TUTORIAL;
```

Inspect:

```sql
SHOW DATABASES;
DESCRIBE DATABASE SNOWFLAKE_TUTORIAL;
```

Set context:

```sql
USE DATABASE SNOWFLAKE_TUTORIAL;
SELECT CURRENT_DATABASE();
```

Snowflake supports lifecycle operations such as CREATE, ALTER, DROP, UNDROP, USE, SHOW, and cloning for applicable database objects.

## 3. Schema

Organize the tutorial database:

```text
SNOWFLAKE_TUTORIAL
|
+-- RAW
+-- STAGING
+-- CURATED
+-- ADMIN
```

Create and inspect:

```sql
CREATE SCHEMA RAW;
CREATE SCHEMA STAGING;
CREATE SCHEMA CURATED;
CREATE SCHEMA ADMIN;

SHOW SCHEMAS;
```

Set context:

```sql
USE SCHEMA RAW;

SELECT
    CURRENT_DATABASE(),
    CURRENT_SCHEMA();
```

## 4. Why Schemas Matter in Production

Avoid putting every object into `PROD.PUBLIC` simply because the schema already exists.

A deliberate organization might be:

```text
PROD
|
+-- RAW
|   +-- Incoming/source data
+-- STAGING
|   +-- Intermediate transformations
+-- CURATED
|   +-- Validated business data
+-- ANALYTICS
|   +-- Reporting objects
+-- ADMIN
    +-- Administrative objects
```

This can provide cleaner boundaries for ownership, RBAC, lifecycle management, governance, troubleshooting, and deployment automation. The exact schema model should follow the organization's architecture.

## 5. Tables

```sql
USE DATABASE SNOWFLAKE_TUTORIAL;
USE SCHEMA RAW;

CREATE TABLE CUSTOMERS (
    CUSTOMER_ID NUMBER,
    FIRST_NAME VARCHAR,
    LAST_NAME VARCHAR,
    EMAIL VARCHAR,
    CREATED_AT TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP()
);
```

Inspect:

```sql
DESCRIBE TABLE CUSTOMERS;
SHOW TABLES;
```

## 6. Fully Qualified Object Names

A schema object can be referenced with:

```text
DATABASE.SCHEMA.OBJECT
```

Example:

```text
SNOWFLAKE_TUTORIAL.RAW.CUSTOMERS
```

Query:

```sql
SELECT *
FROM SNOWFLAKE_TUTORIAL.RAW.CUSTOMERS;
```

This is especially useful in production automation where ambiguity is undesirable.

## 7. Session Context

```sql
USE DATABASE SNOWFLAKE_TUTORIAL;
USE SCHEMA RAW;
```

Now:

```sql
SELECT *
FROM CUSTOMERS;
```

can resolve through the current database and schema.

Always be able to verify:

```sql
SELECT
    CURRENT_DATABASE(),
    CURRENT_SCHEMA(),
    CURRENT_WAREHOUSE(),
    CURRENT_ROLE(),
    CURRENT_USER();
```

## 8. Production Recommendation: Qualify Critical References

Interactive exploration may use:

```sql
SELECT * FROM CUSTOMERS;
```

For production pipelines, procedures, operational SQL, and automation, explicit references can reduce ambiguity:

```sql
SELECT *
FROM PROD.CURATED.CUSTOMERS;
```

This reduces the chance that a script runs against the wrong object because session context differs from what the operator expected.

## 9. Identifier Case Sensitivity

Unquoted identifiers are normally stored and resolved in uppercase.

```sql
CREATE TABLE CUSTOMER_DATA (
    ID NUMBER
);
```

These normally resolve to the same unquoted identifier:

```sql
SELECT * FROM customer_data;
SELECT * FROM CUSTOMER_DATA;
```

Quoted identifiers preserve case and special characters:

```sql
CREATE TABLE "CustomerData" (
    ID NUMBER
);
```

Reference it exactly:

```sql
SELECT *
FROM "CustomerData";
```

### Production recommendation

Prefer simple, consistent naming unless quoted identifiers are genuinely required:

```text
CUSTOMER
CUSTOMER_ADDRESS
CLAIM_HEADER
CLAIM_DETAIL
```

Unnecessary quoted names can create avoidable operational friction.

## 10. Naming Convention

One possible convention:

```text
Database
PROD

Schemas
RAW
STAGING
CURATED
ANALYTICS

Tables
CUSTOMER
CUSTOMER_ADDRESS
CLAIM
CLAIM_DETAIL

Warehouses
ETL_WH
REPORTING_WH
APP_WH

Roles
DATA_ENGINEER_ROLE
ANALYST_ROLE
APP_ROLE
```

Consistency becomes increasingly valuable when CI/CD, Terraform, monitoring, and automation are introduced.

## 11. Create a Simple Data Flow

```sql
CREATE SCHEMA IF NOT EXISTS RAW;
CREATE SCHEMA IF NOT EXISTS STAGING;
CREATE SCHEMA IF NOT EXISTS CURATED;
```

Raw table:

```sql
CREATE TABLE RAW.CUSTOMERS (
    CUSTOMER_ID NUMBER,
    FIRST_NAME VARCHAR,
    LAST_NAME VARCHAR,
    EMAIL VARCHAR
);

INSERT INTO RAW.CUSTOMERS
VALUES
    (1, 'Alice', 'Smith', 'alice@example.com'),
    (2, 'Bob', 'Jones', 'bob@example.com');
```

Transform:

```sql
CREATE TABLE STAGING.CUSTOMERS AS
SELECT
    CUSTOMER_ID,
    UPPER(FIRST_NAME) AS FIRST_NAME,
    UPPER(LAST_NAME) AS LAST_NAME,
    LOWER(EMAIL) AS EMAIL
FROM RAW.CUSTOMERS;
```

Curate:

```sql
CREATE TABLE CURATED.CUSTOMERS AS
SELECT *
FROM STAGING.CUSTOMERS;
```

Conceptually:

```text
Source
  |
  v
RAW.CUSTOMERS
  |
  v
STAGING.CUSTOMERS
  |
  v
CURATED.CUSTOMERS
  |
  v
Analytics / Applications
```

Later tutorials replace this simplified full-copy example with incremental patterns using MERGE, Streams, Tasks, and Dynamic Tables.

## 12. Views

```sql
CREATE VIEW CURATED.ACTIVE_CUSTOMERS AS
SELECT
    CUSTOMER_ID,
    FIRST_NAME,
    LAST_NAME,
    EMAIL
FROM CURATED.CUSTOMERS;
```

Query:

```sql
SELECT *
FROM CURATED.ACTIVE_CUSTOMERS;
```

Secure and materialized views are covered separately.

## 13. Discovering Objects

```sql
SHOW DATABASES;
SHOW SCHEMAS IN DATABASE SNOWFLAKE_TUTORIAL;
SHOW TABLES IN DATABASE SNOWFLAKE_TUTORIAL;
SHOW TABLES IN SCHEMA SNOWFLAKE_TUTORIAL.RAW;

DESC TABLE SNOWFLAKE_TUTORIAL.RAW.CUSTOMERS;
DESC DATABASE SNOWFLAKE_TUTORIAL;
```

These commands are useful during both administration and incident response.

## 14. INFORMATION_SCHEMA

Each database exposes an INFORMATION_SCHEMA.

```sql
SELECT
    TABLE_SCHEMA,
    TABLE_NAME,
    TABLE_TYPE
FROM SNOWFLAKE_TUTORIAL.INFORMATION_SCHEMA.TABLES
ORDER BY TABLE_SCHEMA, TABLE_NAME;
```

Use cases include inventory, metadata inspection, automation, and object discovery.

Later we compare INFORMATION_SCHEMA with SNOWFLAKE.ACCOUNT_USAGE and discuss freshness/retention differences.

## 15. Troubleshooting: Object Not Found

If an application reports:

```text
Object 'CUSTOMERS' does not exist
```

do not immediately assume deletion.

Check:

```sql
SELECT
    CURRENT_DATABASE(),
    CURRENT_SCHEMA(),
    CURRENT_ROLE();

SHOW TABLES LIKE 'CUSTOMERS';

SHOW TABLES LIKE 'CUSTOMERS'
IN SCHEMA PROD.CURATED;
```

Potential causes:

```text
Object not found
      |
      +-- Wrong database
      +-- Wrong schema
      +-- Wrong role / insufficient visibility
      +-- Incorrect identifier case
      +-- Quoted identifier mismatch
      +-- Object renamed
      +-- Object dropped
```

Namespace and identifier behavior are therefore troubleshooting concepts, not just syntax details.

## 16. Hands-On Lab

Build:

```text
SNOWFLAKE_TUTORIAL
|
+-- RAW
|   +-- CUSTOMERS
+-- STAGING
|   +-- CUSTOMERS
+-- CURATED
    +-- CUSTOMERS
    +-- ACTIVE_CUSTOMERS (view)
```

Start:

```sql
CREATE DATABASE IF NOT EXISTS SNOWFLAKE_TUTORIAL;

CREATE SCHEMA IF NOT EXISTS SNOWFLAKE_TUTORIAL.RAW;
CREATE SCHEMA IF NOT EXISTS SNOWFLAKE_TUTORIAL.STAGING;
CREATE SCHEMA IF NOT EXISTS SNOWFLAKE_TUTORIAL.CURATED;
```

Verify:

```sql
SHOW SCHEMAS IN DATABASE SNOWFLAKE_TUTORIAL;
SHOW TABLES IN DATABASE SNOWFLAKE_TUTORIAL;
```

Metadata:

```sql
SELECT
    TABLE_SCHEMA,
    TABLE_NAME,
    TABLE_TYPE
FROM SNOWFLAKE_TUTORIAL.INFORMATION_SCHEMA.TABLES
WHERE TABLE_SCHEMA <> 'INFORMATION_SCHEMA'
ORDER BY TABLE_SCHEMA, TABLE_NAME;
```

Context:

```sql
SELECT
    CURRENT_USER(),
    CURRENT_ROLE(),
    CURRENT_WAREHOUSE(),
    CURRENT_DATABASE(),
    CURRENT_SCHEMA();
```

## 17. Production Takeaways

```text
DATABASE
   |
   +-- SCHEMA
          |
          +-- TABLE
          +-- VIEW
          +-- STAGE
          +-- STREAM
          +-- TASK
          +-- FUNCTION
          +-- PROCEDURE
```

Remember the namespace:

```text
DATABASE.SCHEMA.OBJECT
```

Production rules:

- Use schemas deliberately rather than putting everything in PUBLIC.
- Use consistent naming conventions.
- Understand session context before troubleshooting missing objects.
- Prefer fully qualified names in critical automation where ambiguity would be dangerous.
- Avoid unnecessary quoted/case-sensitive identifiers.
- Separate logical concerns such as RAW → STAGING → CURATED when that model fits the workload.

## Technical references

- Database and schema DDL: https://docs.snowflake.com/en/sql-reference/ddl-database
- Identifiers: https://docs.snowflake.com/en/sql-reference/identifiers
- Object name resolution: https://docs.snowflake.com/en/sql-reference/name-resolution
- Table DDL: https://docs.snowflake.com/en/sql-reference/ddl-table
