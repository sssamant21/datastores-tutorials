# 10 — SQL Fundamentals, Joins, CTEs & Window Functions

**Status:** Canonical  
**Part:** 2 — Data Objects & SQL  
**Goal:** Build production-ready Snowflake SQL skills covering filtering, aggregation, joins, CTEs, subqueries, QUALIFY, window functions, set operations, DML, query safety, and performance troubleshooting.

## 1. SQL in Snowflake
SQL is the primary interface for SELECT, INSERT, UPDATE, DELETE, MERGE, JOIN, GROUP BY, CTEs, window functions, DDL, and administration. Production SQL must be correct and also consider performance, data volume, concurrency, compute consumption, and recoverability.

## 2. Basic SELECT
```sql
SELECT CUSTOMER_ID, CUSTOMER_NAME, STATUS
FROM CUSTOMER;
```
Prefer explicit columns for pipelines, APIs, and published contracts.

## 3. WHERE
```sql
SELECT CUSTOMER_ID, CUSTOMER_NAME
FROM CUSTOMER
WHERE STATUS='ACTIVE';

SELECT CUSTOMER_ID, CUSTOMER_NAME, REGION
FROM CUSTOMER
WHERE STATUS='ACTIVE' AND REGION='EAST';
```
Common operators include =, <>, >, <, >=, <=, IN, BETWEEN, LIKE, ILIKE, IS NULL, and IS NOT NULL.

## 4. IN
```sql
SELECT * FROM CUSTOMER
WHERE REGION IN ('EAST','WEST');
```

## 5. BETWEEN
```sql
SELECT * FROM CLAIM
WHERE SERVICE_DATE BETWEEN '2026-10-01' AND '2026-10-31';
```
BETWEEN includes both boundaries.

## 6. NULL
Do not use `EMAIL = NULL`. Use:
```sql
SELECT * FROM CUSTOMER WHERE EMAIL IS NULL;
SELECT * FROM CUSTOMER WHERE EMAIL IS NOT NULL;
```

## 7. COALESCE
```sql
SELECT CUSTOMER_ID,
       COALESCE(EMAIL,'NO_EMAIL') AS EMAIL
FROM CUSTOMER;
```

## 8. CASE
```sql
SELECT
    CUSTOMER_ID,
    CLAIM_AMOUNT,
    CASE
        WHEN CLAIM_AMOUNT >= 10000 THEN 'HIGH'
        WHEN CLAIM_AMOUNT >= 1000 THEN 'MEDIUM'
        ELSE 'LOW'
    END AS CLAIM_CATEGORY
FROM CLAIM;
```

## 9. ORDER BY
```sql
SELECT CUSTOMER_ID, CUSTOMER_NAME
FROM CUSTOMER
ORDER BY CUSTOMER_NAME;

SELECT CUSTOMER_ID, CUSTOMER_NAME, REGION
FROM CUSTOMER
ORDER BY REGION, CUSTOMER_NAME;
```
Do not assume result order without ORDER BY.

## 10. LIMIT
```sql
SELECT * FROM LARGE_EVENT_TABLE LIMIT 100;
```
LIMIT reduces returned rows but does not guarantee minimal scanning for every query pattern.

## 11. DISTINCT
```sql
SELECT DISTINCT REGION FROM CUSTOMER;
```
Do not add DISTINCT merely to hide duplicates caused by incorrect joins. Understand cardinality first.

## 12. Aggregation
Common functions include COUNT, SUM, AVG, MIN, and MAX.
```sql
SELECT COUNT(*) AS CUSTOMER_COUNT FROM CUSTOMER;
```

## 13. GROUP BY
```sql
SELECT REGION, COUNT(*) AS CUSTOMER_COUNT
FROM CUSTOMER
GROUP BY REGION;
```

## 14. HAVING
WHERE filters rows before aggregation; HAVING filters groups.
```sql
SELECT REGION, COUNT(*) AS CUSTOMER_COUNT
FROM CUSTOMER
GROUP BY REGION
HAVING COUNT(*) > 10000;
```

## 15. Joins
Common types are INNER, LEFT, RIGHT, FULL OUTER, and CROSS JOIN.

## 16. INNER JOIN
```sql
SELECT
    C.CUSTOMER_ID,
    C.CUSTOMER_NAME,
    O.ORDER_ID,
    O.ORDER_AMOUNT
FROM CUSTOMER C
JOIN ORDERS O
  ON C.CUSTOMER_ID = O.CUSTOMER_ID;
```

## 17. LEFT JOIN
```sql
SELECT C.CUSTOMER_ID, C.CUSTOMER_NAME, O.ORDER_ID
FROM CUSTOMER C
LEFT JOIN ORDERS O
  ON C.CUSTOMER_ID = O.CUSTOMER_ID;
```
All rows from the left side remain.

## 18. Find rows with no match
```sql
SELECT C.CUSTOMER_ID, C.CUSTOMER_NAME
FROM CUSTOMER C
LEFT JOIN ORDERS O
  ON C.CUSTOMER_ID = O.CUSTOMER_ID
WHERE O.CUSTOMER_ID IS NULL;
```

## 19. FULL OUTER JOIN
```sql
SELECT A.ID AS A_ID, B.ID AS B_ID
FROM SOURCE_A A
FULL OUTER JOIN SOURCE_B B
  ON A.ID=B.ID;
```
Useful for reconciliation: only A, matched, and only B.

## 20. CROSS JOIN
```sql
SELECT * FROM TABLE_A CROSS JOIN TABLE_B;
```
Every A row combines with every B row. Large inputs can create enormous results.

## 21. Accidental Cartesian behavior
An incomplete predicate such as joining only on a low-cardinality REGION can explode row counts. Inspect join cardinality before blaming warehouse size.

## 22. Join explosion
If expected output is 100M rows but intermediate output is billions, investigate join keys, duplicate keys, many-to-many relationships, missing predicates, and skew.

## 23. Validate cardinality
```sql
SELECT CUSTOMER_ID, COUNT(*) AS CNT
FROM CUSTOMER
GROUP BY CUSTOMER_ID
HAVING COUNT(*) > 1;

SELECT CUSTOMER_ID, COUNT(*) AS CNT
FROM CLAIM
GROUP BY CUSTOMER_ID
ORDER BY CNT DESC
LIMIT 100;
```

## 24. CTEs
```sql
WITH ACTIVE_CUSTOMERS AS (
    SELECT CUSTOMER_ID, CUSTOMER_NAME
    FROM CUSTOMER
    WHERE STATUS='ACTIVE'
)
SELECT * FROM ACTIVE_CUSTOMERS;
```

## 25. Multiple CTEs
```sql
WITH ACTIVE_CUSTOMERS AS (
    SELECT CUSTOMER_ID, CUSTOMER_NAME
    FROM CUSTOMER
    WHERE STATUS='ACTIVE'
),
CUSTOMER_ORDERS AS (
    SELECT CUSTOMER_ID, SUM(ORDER_AMOUNT) AS TOTAL_AMOUNT
    FROM ORDERS
    GROUP BY CUSTOMER_ID
)
SELECT C.CUSTOMER_ID, C.CUSTOMER_NAME, O.TOTAL_AMOUNT
FROM ACTIVE_CUSTOMERS C
LEFT JOIN CUSTOMER_ORDERS O
  ON C.CUSTOMER_ID=O.CUSTOMER_ID;
```

## 26. CTEs are not guaranteed materialization
A CTE is primarily a query-structuring construct. Snowflake's optimizer determines the physical plan.

## 27. Subqueries
```sql
SELECT *
FROM CUSTOMER
WHERE CUSTOMER_ID IN (
    SELECT CUSTOMER_ID
    FROM ORDERS
    WHERE ORDER_AMOUNT > 10000
);
```

## 28. EXISTS
```sql
SELECT C.CUSTOMER_ID, C.CUSTOMER_NAME
FROM CUSTOMER C
WHERE EXISTS (
    SELECT 1
    FROM ORDERS O
    WHERE O.CUSTOMER_ID=C.CUSTOMER_ID
);
```

## 29. Window functions
Common functions include ROW_NUMBER, RANK, DENSE_RANK, LAG, LEAD, SUM, AVG, MIN, MAX, and COUNT with an OVER clause.

## 30. ROW_NUMBER
```sql
SELECT
    CUSTOMER_ID,
    STATUS,
    UPDATED_AT,
    ROW_NUMBER() OVER (
        PARTITION BY CUSTOMER_ID
        ORDER BY UPDATED_AT DESC
    ) AS RN
FROM CUSTOMER_HISTORY;
```

## 31. QUALIFY
```sql
SELECT CUSTOMER_ID, STATUS, UPDATED_AT
FROM CUSTOMER_HISTORY
QUALIFY ROW_NUMBER() OVER (
    PARTITION BY CUSTOMER_ID
    ORDER BY UPDATED_AT DESC
)=1;
```

## 32. QUALIFY vs WHERE
WHERE filters before window evaluation. QUALIFY filters after window functions are evaluated, making it ideal for top-N-per-group and deduplication.

## 33. Deduplication
```sql
SELECT *
FROM CUSTOMER_STAGE
QUALIFY ROW_NUMBER() OVER (
    PARTITION BY CUSTOMER_ID
    ORDER BY UPDATED_AT DESC
)=1;
```

## 34. Deterministic deduplication
When timestamps tie, add reliable tie-breakers:
```sql
QUALIFY ROW_NUMBER() OVER (
    PARTITION BY CUSTOMER_ID
    ORDER BY UPDATED_AT DESC,
             INGESTED_AT DESC,
             SOURCE_SEQUENCE DESC
)=1;
```

## 35. ROW_NUMBER vs RANK vs DENSE_RANK
ROW_NUMBER always assigns unique sequential positions. RANK gives ties the same rank and leaves gaps. DENSE_RANK gives ties the same rank without gaps.

## 36. LAG
```sql
SELECT
    EVENT_DATE,
    SALES_AMOUNT,
    LAG(SALES_AMOUNT) OVER (ORDER BY EVENT_DATE) AS PREVIOUS_AMOUNT
FROM DAILY_SALES;
```

## 37. LEAD
```sql
SELECT
    EVENT_DATE,
    STATUS,
    LEAD(STATUS) OVER (ORDER BY EVENT_DATE) AS NEXT_STATUS
FROM STATUS_HISTORY;
```

## 38. Running total
```sql
SELECT
    EVENT_DATE,
    SALES_AMOUNT,
    SUM(SALES_AMOUNT) OVER (
        ORDER BY EVENT_DATE
        ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
    ) AS RUNNING_TOTAL
FROM DAILY_SALES;
```

## 39. Partitioned running total
```sql
SELECT
    REGION,
    EVENT_DATE,
    SALES_AMOUNT,
    SUM(SALES_AMOUNT) OVER (
        PARTITION BY REGION
        ORDER BY EVENT_DATE
        ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
    ) AS REGION_RUNNING_TOTAL
FROM DAILY_SALES;
```

## 40. Set operations
Snowflake supports UNION, UNION ALL, INTERSECT, and MINUS/EXCEPT.

## 41. UNION ALL
```sql
SELECT CUSTOMER_ID FROM EAST_CUSTOMER
UNION ALL
SELECT CUSTOMER_ID FROM WEST_CUSTOMER;
```
UNION ALL retains duplicates.

## 42. UNION
```sql
SELECT CUSTOMER_ID FROM EAST_CUSTOMER
UNION
SELECT CUSTOMER_ID FROM WEST_CUSTOMER;
```
UNION removes duplicates and requires duplicate-elimination work. Prefer UNION ALL when deduplication is unnecessary.

## 43. INTERSECT
```sql
SELECT CUSTOMER_ID FROM SOURCE_A
INTERSECT
SELECT CUSTOMER_ID FROM SOURCE_B;
```

## 44. MINUS / EXCEPT
```sql
SELECT CUSTOMER_ID FROM SOURCE_A
MINUS
SELECT CUSTOMER_ID FROM SOURCE_B;
```
Useful for migration reconciliation.

## 45. INSERT
```sql
INSERT INTO CUSTOMER (CUSTOMER_ID,CUSTOMER_NAME,STATUS)
VALUES ('C100','Alice','ACTIVE');
```
Prefer explicit target columns.

## 46. INSERT SELECT
```sql
INSERT INTO CURATED.CUSTOMER (CUSTOMER_ID,CUSTOMER_NAME,STATUS)
SELECT CUSTOMER_ID,CUSTOMER_NAME,STATUS
FROM STAGING.CUSTOMER
WHERE IS_VALID=TRUE;
```

## 47. UPDATE
```sql
UPDATE CUSTOMER
SET STATUS='INACTIVE'
WHERE CUSTOMER_ID='C100';
```
Before large production changes, run a SELECT/COUNT with the identical predicate to validate blast radius.

## 48. Dangerous UPDATE/DELETE
An UPDATE without WHERE can affect every row; DELETE without WHERE can remove every row. Production DML requires deliberate validation.

## 49. DELETE
```sql
SELECT COUNT(*) FROM CUSTOMER WHERE CUSTOMER_ID='C100';
DELETE FROM CUSTOMER WHERE CUSTOMER_ID='C100';
```

## 50. MERGE
```sql
MERGE INTO TARGET_CUSTOMER T
USING SOURCE_CUSTOMER S
ON T.CUSTOMER_ID=S.CUSTOMER_ID
WHEN MATCHED THEN UPDATE SET
    T.CUSTOMER_NAME=S.CUSTOMER_NAME,
    T.STATUS=S.STATUS
WHEN NOT MATCHED THEN INSERT
    (CUSTOMER_ID,CUSTOMER_NAME,STATUS)
VALUES
    (S.CUSTOMER_ID,S.CUSTOMER_NAME,S.STATUS);
```
Tutorial 22 covers production MERGE and idempotent incremental processing.

## 51. Transactions
```sql
BEGIN;
UPDATE CUSTOMER
SET STATUS='INACTIVE'
WHERE CUSTOMER_ID='C100';

DELETE FROM CUSTOMER_ADDRESS
WHERE CUSTOMER_ID='C100';
COMMIT;
```
Use ROLLBACK instead of COMMIT when appropriate.

## 52. Performance starts with SQL
Slow SQL can result from huge scans, poor pruning, join explosion, Cartesian behavior, expensive sort/aggregation/window work, repeated transformations, skew, spill, or queueing. Do not automatically conclude that the warehouse is too small.

## 53. Filter appropriately
Write correct selective predicates and let the optimizer determine the physical plan. Focus on data model, join conditions, pruning opportunities, and reasonable result sizes.

## 54. Pruning-friendly predicates
A direct timestamp range is often clearer than unnecessarily transforming every row:
```sql
WHERE EVENT_TIMESTAMP >= '2026-10-01'
  AND EVENT_TIMESTAMP <  '2026-11-01'
```
Confirm actual behavior with Query Profile.

## 55. Avoid unnecessary data
Request only needed columns and relevant date ranges instead of scanning/returning an entire event history without purpose.

## 56. Query Profile
Use Query Profile to inspect table scans, filters, joins, aggregates, sorts, windows, spill, and data movement. Tutorial 37 covers this deeply.

## 57. Join slowness
Check input row counts, join type/predicates, duplicate keys, many-to-many relationships, intermediate row counts, and spill before resizing compute.

## 58. Unexpected duplicates
If A has 5 rows per key and B has 2, a many-to-many join can produce 10 rows per key. Profile duplicates on both sides before adding DISTINCT.

## 59. Unexpected NULLs
For LEFT JOINs, NULL values on the right can simply mean no match. Check data types, whitespace, case, NULL keys, and transformations before masking them with defaults.

## 60. Safe production DML workflow
1. Verify account/environment.
2. Verify role.
3. Verify database/schema.
4. Preview target rows.
5. Count affected rows.
6. Confirm predicate.
7. Understand recovery.
8. Execute.
9. Validate.
10. Capture query ID.

```sql
SELECT
    CURRENT_ORGANIZATION_NAME(),
    CURRENT_ACCOUNT_NAME(),
    CURRENT_REGION(),
    CURRENT_ROLE(),
    CURRENT_WAREHOUSE(),
    CURRENT_DATABASE(),
    CURRENT_SCHEMA();
```

## 61. Capture query IDs
```sql
SELECT
    QUERY_ID,
    QUERY_TEXT,
    USER_NAME,
    ROLE_NAME,
    WAREHOUSE_NAME,
    START_TIME,
    END_TIME,
    EXECUTION_STATUS
FROM SNOWFLAKE.ACCOUNT_USAGE.QUERY_HISTORY
WHERE START_TIME >= DATEADD('hour',-1,CURRENT_TIMESTAMP())
ORDER BY START_TIME DESC;
```
ACCOUNT_USAGE has latency and is not a real-time operational source.

## 62. Current-session query history
```sql
SELECT *
FROM TABLE(
    INFORMATION_SCHEMA.QUERY_HISTORY_BY_SESSION(
        RESULT_LIMIT => 100
    )
)
ORDER BY START_TIME DESC;
```

## 63. Query tagging
```sql
ALTER SESSION SET QUERY_TAG='customer_daily_pipeline';
-- workload SQL
ALTER SESSION UNSET QUERY_TAG;
```
Tags improve observability, cost attribution, incident investigation, and workload identification.

## 64. Formatting matters
Readable SQL is easier to review, troubleshoot, optimize, audit, and modify safely. Use explicit aliases, indentation, and clear predicates.

## 65. Lab setup
```sql
CREATE DATABASE IF NOT EXISTS SNOWFLAKE_TUTORIAL;
CREATE SCHEMA IF NOT EXISTS SNOWFLAKE_TUTORIAL.SQL_LAB;
USE DATABASE SNOWFLAKE_TUTORIAL;
USE SCHEMA SQL_LAB;

CREATE TABLE CUSTOMER (
    CUSTOMER_ID NUMBER,
    CUSTOMER_NAME VARCHAR,
    REGION VARCHAR,
    STATUS VARCHAR
);

INSERT INTO CUSTOMER VALUES
(1,'Alice','EAST','ACTIVE'),
(2,'Bob','WEST','ACTIVE'),
(3,'Carol','EAST','INACTIVE'),
(4,'David','SOUTH','ACTIVE');
```

## 66. Orders
```sql
CREATE TABLE ORDERS (
    ORDER_ID NUMBER,
    CUSTOMER_ID NUMBER,
    ORDER_DATE DATE,
    ORDER_AMOUNT NUMBER(12,2)
);

INSERT INTO ORDERS VALUES
(1001,1,'2026-10-01',500.00),
(1002,1,'2026-10-03',750.00),
(1003,2,'2026-10-02',1200.00),
(1004,2,'2026-10-04',300.00),
(1005,2,'2026-10-04',450.00);
```

## 67. Aggregation lab
```sql
SELECT
    CUSTOMER_ID,
    COUNT(*) AS ORDER_COUNT,
    SUM(ORDER_AMOUNT) AS TOTAL_AMOUNT,
    AVG(ORDER_AMOUNT) AS AVG_AMOUNT
FROM ORDERS
GROUP BY CUSTOMER_ID
ORDER BY CUSTOMER_ID;
```

## 68. Join lab
```sql
SELECT
    C.CUSTOMER_ID,
    C.CUSTOMER_NAME,
    O.ORDER_ID,
    O.ORDER_AMOUNT
FROM CUSTOMER C
LEFT JOIN ORDERS O
  ON C.CUSTOMER_ID=O.CUSTOMER_ID
ORDER BY C.CUSTOMER_ID,O.ORDER_ID;
```

## 69. CTE lab
```sql
WITH ORDER_SUMMARY AS (
    SELECT
        CUSTOMER_ID,
        COUNT(*) AS ORDER_COUNT,
        SUM(ORDER_AMOUNT) AS TOTAL_AMOUNT
    FROM ORDERS
    GROUP BY CUSTOMER_ID
)
SELECT
    C.CUSTOMER_ID,
    C.CUSTOMER_NAME,
    COALESCE(O.ORDER_COUNT,0) AS ORDER_COUNT,
    COALESCE(O.TOTAL_AMOUNT,0) AS TOTAL_AMOUNT
FROM CUSTOMER C
LEFT JOIN ORDER_SUMMARY O
  ON C.CUSTOMER_ID=O.CUSTOMER_ID
ORDER BY C.CUSTOMER_ID;
```

## 70. Window lab
```sql
SELECT
    CUSTOMER_ID,
    ORDER_ID,
    ORDER_DATE,
    ORDER_AMOUNT,
    ROW_NUMBER() OVER (
        PARTITION BY CUSTOMER_ID
        ORDER BY ORDER_DATE DESC, ORDER_ID DESC
    ) AS RN
FROM ORDERS
ORDER BY CUSTOMER_ID,RN;
```

## 71. Latest order
```sql
SELECT CUSTOMER_ID,ORDER_ID,ORDER_DATE,ORDER_AMOUNT
FROM ORDERS
QUALIFY ROW_NUMBER() OVER (
    PARTITION BY CUSTOMER_ID
    ORDER BY ORDER_DATE DESC,ORDER_ID DESC
)=1;
```

## 72. Running total
```sql
SELECT
    CUSTOMER_ID,
    ORDER_ID,
    ORDER_DATE,
    ORDER_AMOUNT,
    SUM(ORDER_AMOUNT) OVER (
        PARTITION BY CUSTOMER_ID
        ORDER BY ORDER_DATE,ORDER_ID
        ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
    ) AS RUNNING_TOTAL
FROM ORDERS
ORDER BY CUSTOMER_ID,ORDER_DATE,ORDER_ID;
```

## 73. Customers without orders
```sql
SELECT C.CUSTOMER_ID,C.CUSTOMER_NAME
FROM CUSTOMER C
LEFT JOIN ORDERS O
  ON C.CUSTOMER_ID=O.CUSTOMER_ID
WHERE O.CUSTOMER_ID IS NULL;
```

## 74. Reconciliation lab
```sql
CREATE TABLE SOURCE_CUSTOMER (CUSTOMER_ID NUMBER);
CREATE TABLE TARGET_CUSTOMER (CUSTOMER_ID NUMBER);

INSERT INTO SOURCE_CUSTOMER VALUES (1),(2),(3),(4);
INSERT INTO TARGET_CUSTOMER VALUES (1),(2),(4),(5);

SELECT CUSTOMER_ID FROM SOURCE_CUSTOMER
MINUS
SELECT CUSTOMER_ID FROM TARGET_CUSTOMER;

SELECT CUSTOMER_ID FROM TARGET_CUSTOMER
MINUS
SELECT CUSTOMER_ID FROM SOURCE_CUSTOMER;
```
The first query identifies 3 as missing from target; the second identifies 5 as unexpected in target.

## 75. Cleanup
```sql
DROP TABLE IF EXISTS CUSTOMER;
DROP TABLE IF EXISTS ORDERS;
DROP TABLE IF EXISTS SOURCE_CUSTOMER;
DROP TABLE IF EXISTS TARGET_CUSTOMER;
```

## 76. Troubleshooting checklist
For slowness: queueing, scan volume, pruning, join cardinality, Cartesian explosion, aggregation, sorting, windows, spill, and warehouse size. For wrong results: join keys, duplicate source rows, NULL behavior, filters, aggregation grain, window partition/order, and time/date conversion.

## 77. Production SQL review
Check correct database/schema references, explicit columns, predicates, join keys/cardinality, NULL behavior, compatible types, aggregation grain, deterministic windows, absence of accidental Cartesian joins, DML blast radius, recovery path, query tags, and realistic-volume testing.

## 78. Production takeaways
Do not use DISTINCT to hide broken joins. Understand cardinality before changing warehouse size. Use deterministic ROW_NUMBER ordering, QUALIFY for window filtering, UNION ALL when deduplication is unnecessary, and validate UPDATE/DELETE scope before execution. Verify account/role/database/schema before production mutation. Use query IDs/tags for investigation and Query Profile before assuming more compute is the answer.

## Technical references
- https://docs.snowflake.com/en/sql-reference/sql/select
- https://docs.snowflake.com/en/sql-reference/constructs/join
- https://docs.snowflake.com/en/sql-reference/constructs/with
- https://docs.snowflake.com/en/user-guide/functions-window-using
- https://docs.snowflake.com/en/sql-reference/constructs/qualify
- https://docs.snowflake.com/en/sql-reference/sql/merge
- https://docs.snowflake.com/en/user-guide/ui-query-profile
