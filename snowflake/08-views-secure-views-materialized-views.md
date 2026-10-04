# 08 — Views, Secure Views & Materialized Views

**Status:** Canonical  
**Part:** 2 — Data Objects & SQL  
**Goal:** Understand standard views, secure views, and materialized views; when to use each; security, performance, maintenance, cost, and production troubleshooting.

## 1. What is a view?
A view is a named SQL query over underlying objects.

```sql
CREATE VIEW ACTIVE_CUSTOMERS AS
SELECT CUSTOMER_ID, CUSTOMER_NAME, EMAIL
FROM CUSTOMER
WHERE STATUS = 'ACTIVE';
```

A standard view does not normally store a separate result copy.

## 2. Why use views?
Views provide SQL abstraction, simplify complex queries, hide unnecessary columns, provide stable interfaces, reuse business logic, and separate consumers from base tables.

## 3. Standard views
```sql
CREATE VIEW CUSTOMER_SUMMARY AS
SELECT CUSTOMER_ID, CUSTOMER_NAME, STATUS
FROM CUSTOMER;

SHOW VIEWS;
DESC VIEW CUSTOMER_SUMMARY;
SELECT GET_DDL('VIEW','CUSTOMER_SUMMARY');
```

## 4. Query-time derivation
A standard view resolves its definition and queries underlying objects when used. Changes to underlying data are reflected in subsequent view queries.

## 5. Example
```sql
CREATE TABLE CUSTOMER (
    CUSTOMER_ID NUMBER,
    CUSTOMER_NAME VARCHAR,
    STATUS VARCHAR,
    EMAIL VARCHAR
);

INSERT INTO CUSTOMER VALUES
(1,'Alice','ACTIVE','alice@example.com'),
(2,'Bob','INACTIVE','bob@example.com'),
(3,'Carol','ACTIVE','carol@example.com');

CREATE VIEW ACTIVE_CUSTOMER AS
SELECT CUSTOMER_ID, CUSTOMER_NAME, EMAIL
FROM CUSTOMER
WHERE STATUS='ACTIVE';
```

## 6. Abstraction layer
A common architecture is Applications/BI → Published Views → Curated Tables → Raw/Staging. This decouples consumers from internal table design.

## 7. Avoid SELECT *
For important published views, explicit columns provide a clearer contract, easier review, stronger governance, and less accidental exposure if a sensitive base-table column is later added.

## 8. Views do not automatically provide security
A view that omits SSN can be part of access control, but creating it does not automatically secure the base table. Privileges must ensure the consumer can select the view without inappropriate direct access to the base table.

## 9. Secure views
```sql
CREATE SECURE VIEW CUSTOMER_SECURE AS
SELECT CUSTOMER_ID, CUSTOMER_NAME, EMAIL
FROM CUSTOMER
WHERE STATUS='ACTIVE';
```

Secure views are designed for cases where the definition and underlying-data details require stronger protection.

## 10. Why secure views exist
Secure views protect view definitions/details from unauthorized consumers and are especially relevant in secure sharing and sensitive publication.

## 11. Secure view example
```sql
CREATE SECURE VIEW SHARED_PATIENT AS
SELECT PATIENT_ID, FIRST_NAME, LAST_NAME, STATUS
FROM PATIENT
WHERE STATUS='ACTIVE';
```

Grant access according to RBAC/sharing design rather than exposing the sensitive base table.

## 12. Secure views do not replace RBAC
Security architecture can include RBAC, object privileges, secure views, masking policies, row access policies, tags/classification, and network controls.

## 13. Secure-view performance
Security guarantees can constrain optimizer transformations that might expose underlying information. Do not automatically make every view secure; use secure views when security requirements justify them.

## 14. Standard vs secure
| Feature | Standard View | Secure View |
|---|---|---|
| Stores result data | No | No |
| Query abstraction | Yes | Yes |
| Definition protection | Standard | Stronger |
| Security-focused | No | Yes |
| Sharing use cases | Possible | Common |
| Optimizer freedom | Normal | Security can constrain optimization |

## 15. Materialized views
A materialized view stores derived results and Snowflake maintains them as base-table data changes.

```sql
CREATE MATERIALIZED VIEW CUSTOMER_ACTIVE_MV AS
SELECT CUSTOMER_ID, CUSTOMER_NAME, EMAIL
FROM CUSTOMER
WHERE STATUS='ACTIVE';
```

## 16. Why materialized views?
They can reduce repeated work for eligible, frequently repeated access patterns over large tables, especially when the materialized subset is substantially smaller or cheaper to access.

## 17. Cost model
Materialized views can incur storage and maintenance compute. Evaluate query savings against storage and maintenance cost.

## 18. Maintenance
INSERT/UPDATE/DELETE activity on the base table can create maintenance work. Highly volatile tables can therefore be more expensive to maintain.

## 19. Good candidates
Potential candidates have a large base table, repeated expensive access pattern, high query frequency, meaningful reduction opportunity, and manageable data-change rate.

## 20. Poor candidates
Be cautious with small tables, rare queries, highly volatile data, cases where a standard view already performs well, problems better solved by query design, or SQL shapes unsupported by materialized views.

## 21. SQL restrictions
Materialized-view definitions are more restricted than standard views. Check current supported SQL before designing one; do not assume any CREATE VIEW definition can become CREATE MATERIALIZED VIEW.

## 22. Automatic optimizer use
Snowflake can sometimes use a suitable materialized view when a query references the base table rather than naming the MV directly.

## 23. Do not create MVs blindly
For slow queries first inspect Query Profile: pruning, scan volume, joins, queueing, spill, warehouse sizing, Search Optimization, clustering, and whether an MV is actually a good fit.

## 24. Comparison
| Feature | Standard View | Secure View | Materialized View |
|---|---|---|---|
| Logical abstraction | Yes | Yes | Yes |
| Stores derived data | No | No | Yes |
| Automatically maintained | N/A | N/A | Yes |
| Primary goal | Abstraction | Security | Performance |
| Result storage cost | No | No | Yes |
| MV maintenance cost | No | No | Yes |
| SQL restrictions | Least | Security considerations | More restrictive |

## 25. Production layering
RAW → STAGING → CURATED, with standard views for internal consumers, secure views for protected publication/sharing, and carefully selected MVs for performance-sensitive workloads.

## 26. Replace views carefully
```sql
CREATE OR REPLACE VIEW CUSTOMER_VIEW AS
SELECT CUSTOMER_ID, CUSTOMER_NAME, EMAIL, STATUS
FROM CUSTOMER;
```

Changing names, order, data types, filters, or business logic can break consumers. Treat published views as interfaces.

## 27. Views as data contracts
A stable view can shield applications from internal table evolution when the published contract remains compatible.

## 28. Version published views
For breaking changes, consider versioned interfaces such as API_CUSTOMER_V1 and API_CUSTOMER_V2. Migrate consumers before retiring V1.

## 29. Inspect views
```sql
SHOW VIEWS IN DATABASE SNOWFLAKE_TUTORIAL;
DESC VIEW SNOWFLAKE_TUTORIAL.VIEWS.ACTIVE_CUSTOMER;
SELECT GET_DDL('VIEW','SNOWFLAKE_TUTORIAL.VIEWS.ACTIVE_CUSTOMER');
```

## 30. INFORMATION_SCHEMA
```sql
SELECT
    TABLE_CATALOG,
    TABLE_SCHEMA,
    TABLE_NAME,
    VIEW_DEFINITION,
    IS_SECURE
FROM SNOWFLAKE_TUTORIAL.INFORMATION_SCHEMA.VIEWS
ORDER BY TABLE_SCHEMA, TABLE_NAME;
```

## 31. Dependency troubleshooting
For a broken view, get its definition, identify referenced objects, and verify existence, schema, column changes, privileges, and type changes throughout the dependency chain.

## 32. “Object does not exist”
```sql
SELECT CURRENT_ROLE(), CURRENT_DATABASE(), CURRENT_SCHEMA();

SHOW VIEWS LIKE 'CUSTOMER_VIEW' IN SCHEMA REPORTING;

SELECT GET_DDL('VIEW','REPORTING.CUSTOMER_VIEW');
```

Then verify each referenced object.

## 33. Privilege troubleshooting
A consumer typically needs appropriate USAGE on database/schema and SELECT on the view. Snowflake view semantics can allow querying a view without direct SELECT on each underlying object, enabling controlled publication.

## 34. Security anti-pattern
If the purpose of CUSTOMER_PUBLIC_VIEW is to hide sensitive base columns, granting the same analyst direct SELECT on the base table defeats that boundary.

## 35. Secure sharing
A provider can expose a secure view rather than sensitive base tables through Snowflake sharing. Secure Data Sharing is covered in Tutorials 61–65.

## 36. MV troubleshooting
If an MV is not helping, check query eligibility/use, selectivity, base-table change rate, maintenance cost, and whether base-table pruning is already good.

## 37. Cost review
Measure current query frequency, scans, duration, and warehouse cost, then compare projected MV storage/maintenance and query savings.

## 38. Lab setup
```sql
CREATE DATABASE IF NOT EXISTS SNOWFLAKE_TUTORIAL;
CREATE SCHEMA IF NOT EXISTS SNOWFLAKE_TUTORIAL.VIEWS;
USE DATABASE SNOWFLAKE_TUTORIAL;
USE SCHEMA VIEWS;

CREATE TABLE CUSTOMER (
    CUSTOMER_ID NUMBER,
    CUSTOMER_NAME VARCHAR,
    EMAIL VARCHAR,
    STATUS VARCHAR,
    REGION VARCHAR
);

INSERT INTO CUSTOMER VALUES
(1,'Alice','alice@example.com','ACTIVE','EAST'),
(2,'Bob','bob@example.com','INACTIVE','WEST'),
(3,'Carol','carol@example.com','ACTIVE','EAST'),
(4,'David','david@example.com','ACTIVE','WEST');
```

## 39. Standard-view lab
```sql
CREATE VIEW ACTIVE_CUSTOMER AS
SELECT CUSTOMER_ID, CUSTOMER_NAME, EMAIL, REGION
FROM CUSTOMER
WHERE STATUS='ACTIVE';

SELECT * FROM ACTIVE_CUSTOMER ORDER BY CUSTOMER_ID;
```

## 40. Secure-view lab
```sql
CREATE SECURE VIEW ACTIVE_CUSTOMER_SECURE AS
SELECT CUSTOMER_ID, CUSTOMER_NAME, REGION
FROM CUSTOMER
WHERE STATUS='ACTIVE';

SELECT * FROM ACTIVE_CUSTOMER_SECURE ORDER BY CUSTOMER_ID;
SHOW VIEWS LIKE 'ACTIVE_CUSTOMER_SECURE';
```

## 41. View update test
```sql
INSERT INTO CUSTOMER
VALUES (5,'Emma','emma@example.com','ACTIVE','SOUTH');

SELECT * FROM ACTIVE_CUSTOMER ORDER BY CUSTOMER_ID;
```

The new qualifying row appears because the view derives from current underlying data.

## 42. Materialized-view lab
Verify account/edition and current SQL support before running.

```sql
CREATE MATERIALIZED VIEW ACTIVE_CUSTOMER_MV AS
SELECT CUSTOMER_ID, CUSTOMER_NAME, EMAIL, STATUS, REGION
FROM CUSTOMER
WHERE STATUS='ACTIVE';

SELECT * FROM ACTIVE_CUSTOMER_MV ORDER BY CUSTOMER_ID;
SHOW MATERIALIZED VIEWS;
```

The tiny lab demonstrates object behavior, not realistic performance.

## 43. Inspect all three
```sql
SHOW VIEWS IN SCHEMA SNOWFLAKE_TUTORIAL.VIEWS;
SHOW MATERIALIZED VIEWS IN SCHEMA SNOWFLAKE_TUTORIAL.VIEWS;

SELECT GET_DDL('VIEW','SNOWFLAKE_TUTORIAL.VIEWS.ACTIVE_CUSTOMER');
SELECT GET_DDL('VIEW','SNOWFLAKE_TUTORIAL.VIEWS.ACTIVE_CUSTOMER_SECURE');
```

## 44. Troubleshooting lab
```sql
SELECT
    CURRENT_USER(),
    CURRENT_ROLE(),
    CURRENT_WAREHOUSE(),
    CURRENT_DATABASE(),
    CURRENT_SCHEMA();

SHOW VIEWS;
SHOW MATERIALIZED VIEWS;

SELECT TABLE_SCHEMA, TABLE_NAME, IS_SECURE
FROM SNOWFLAKE_TUTORIAL.INFORMATION_SCHEMA.VIEWS
WHERE TABLE_SCHEMA='VIEWS'
ORDER BY TABLE_NAME;
```

## 45. Cleanup
```sql
DROP MATERIALIZED VIEW IF EXISTS ACTIVE_CUSTOMER_MV;
DROP VIEW IF EXISTS ACTIVE_CUSTOMER_SECURE;
DROP VIEW IF EXISTS ACTIVE_CUSTOMER;
DROP TABLE IF EXISTS CUSTOMER;
```

## 46. Decision guide
Use a standard view for abstraction, a secure view when protected definition/secure publication is required, and evaluate an MV for a repeated expensive eligible access pattern where measured benefit exceeds maintenance/storage cost.

## 47. Production takeaways
Use standard views for abstraction and stable interfaces. Use secure views when security requirements justify them. Secure views do not replace RBAC/masking/row-access controls. Use MVs only after identifying a qualifying workload and measuring total cost. Treat published views as contracts, prefer explicit columns, and troubleshoot dependencies/context/privileges systematically.

## Technical references
- https://docs.snowflake.com/en/user-guide/views-introduction
- https://docs.snowflake.com/en/sql-reference/sql/create-view
- https://docs.snowflake.com/en/user-guide/views-secure
- https://docs.snowflake.com/en/user-guide/views-materialized
- https://docs.snowflake.com/en/sql-reference/sql/create-materialized-view
