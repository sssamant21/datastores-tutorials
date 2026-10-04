# 09 — Sequences, Identity Columns & Generated Values

**Status:** Canonical  
**Part:** 2 — Data Objects & SQL  
**Goal:** Understand sequences, NEXTVAL, identity/autoincrement, generated defaults, gaps, concurrency, UUIDs, and production surrogate-key design.

## 1. Why generated values matter
Tables often need CUSTOMER_ID, CLAIM_ID, ORDER_ID, EVENT_ID, BATCH_ID, or TRANSACTION_ID. Sometimes the source supplies a business key; other times Snowflake generates a surrogate key.

## 2. Natural vs surrogate key
A natural key comes from business data (for example MEMBER_ID). A surrogate key is generated primarily for internal identity. Preserve both when both semantics matter.

## 3. Sequences
```sql
CREATE SEQUENCE CUSTOMER_SEQ;
SELECT CUSTOMER_SEQ.NEXTVAL;
```

A sequence is a schema-level object.

## 4. Qualified sequence names
```sql
SELECT SNOWFLAKE_TUTORIAL.DATA_MODEL.CUSTOMER_SEQ.NEXTVAL;
```

Qualified names reduce namespace ambiguity in production pipelines.

## 5. START and INCREMENT
```sql
CREATE SEQUENCE CUSTOMER_SEQ
    START = 100000
    INCREMENT = 1;
```

## 6. Inspect sequences
```sql
SHOW SEQUENCES;
SHOW SEQUENCES IN SCHEMA SNOWFLAKE_TUTORIAL.DATA_MODEL;
```

## 7. Sequence during INSERT
```sql
CREATE TABLE CUSTOMER (
    CUSTOMER_KEY NUMBER,
    CUSTOMER_ID VARCHAR,
    CUSTOMER_NAME VARCHAR
);

INSERT INTO CUSTOMER
VALUES (CUSTOMER_SEQ.NEXTVAL,'CUST-100','Alice');
```

## 8. Multiple rows
```sql
INSERT INTO CUSTOMER (CUSTOMER_KEY,CUSTOMER_ID,CUSTOMER_NAME)
SELECT CUSTOMER_SEQ.NEXTVAL, CUSTOMER_ID, CUSTOMER_NAME
FROM CUSTOMER_STAGE;
```

## 9. Sequences are not gap-free
Generated sequence values prioritize uniqueness rather than gap-free numbering. Missing numeric values can be normal.

## 10. Why gaps exist
Values can be consumed or skipped due to processing behavior. Do not use a Snowflake sequence for a business requirement that mandates perfectly consecutive invoice numbers.

## 11. Concurrency
Multiple pipelines can request values from the same sequence. Do not rely on exact request ordering across concurrent workloads.

## 12. Ordering warning
A higher generated key does not prove a later commit or business event. Use an explicit timestamp/source-order field when ordering matters.

## 13. Keys are not timestamps
Do not assume `ORDER BY CUSTOMER_KEY DESC` means newest customer. Store and order by `CREATED_AT` when that is the actual requirement.

## 14. Identity columns
```sql
CREATE TABLE CUSTOMER_IDENTITY (
    CUSTOMER_KEY NUMBER AUTOINCREMENT START 1 INCREMENT 1,
    CUSTOMER_ID VARCHAR,
    CUSTOMER_NAME VARCHAR
);
```

IDENTITY is synonymous for this purpose.

## 15. Insert without identity value
```sql
INSERT INTO CUSTOMER_IDENTITY (CUSTOMER_ID,CUSTOMER_NAME)
VALUES ('CUST-300','Alice');
```

Snowflake generates CUSTOMER_KEY.

## 16. Multiple rows
```sql
INSERT INTO CUSTOMER_IDENTITY (CUSTOMER_ID,CUSTOMER_NAME)
VALUES
('CUST-301','Bob'),
('CUST-302','Carol'),
('CUST-303','David');
```

## 17. Identity gaps
Identity/autoincrement values are not guaranteed to be gap-free.

## 18. Sequence vs identity
A sequence is an independent schema object with explicit NEXTVAL and can be referenced by multiple statements/tables. Identity/autoincrement is a table-column property and automatically generates values for that table.

## 19. Sequence example
```sql
CREATE SEQUENCE ORDER_SEQ;

CREATE TABLE ORDERS (
    ORDER_KEY NUMBER,
    ORDER_ID VARCHAR,
    ORDER_DATE DATE
);

INSERT INTO ORDERS
VALUES (ORDER_SEQ.NEXTVAL,'ORD-1001',CURRENT_DATE());
```

## 20. Identity example
```sql
CREATE TABLE ORDERS_IDENTITY (
    ORDER_KEY NUMBER AUTOINCREMENT,
    ORDER_ID VARCHAR,
    ORDER_DATE DATE
);

INSERT INTO ORDERS_IDENTITY (ORDER_ID,ORDER_DATE)
VALUES ('ORD-1001',CURRENT_DATE());
```

## 21. When to use sequence
Use sequences when key generation should be explicit in transformation SQL or shared generation logic.

## 22. When to use identity
Use identity/autoincrement when automatic per-table generation is simpler and callers should not explicitly request sequence values.

## 23. Production dimension example
```sql
CREATE TABLE DIM_CUSTOMER (
    CUSTOMER_KEY NUMBER AUTOINCREMENT,
    CUSTOMER_ID VARCHAR,
    CUSTOMER_NAME VARCHAR,
    REGION VARCHAR,
    CREATED_AT TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP()
);
```

## 24. Surrogate vs business key
CUSTOMER_KEY might be 100002 while CUSTOMER_ID is CUST-84552. The former supports internal warehouse relationships; the latter preserves source/business identity.

## 25. Do not generate a new key on every reload
If CUST-100 already exists, a routine reload should not blindly create a new surrogate identity for the same logical entity.

## 26. Upsert design
Determine whether the business key exists. Update/reuse the existing entity when matched; generate a new surrogate key only for a genuinely new entity. Tutorial 22 covers MERGE deeply.

## 27. Generated values and data quality
Unique surrogate keys do not prevent duplicate business entities.

## 28. Key generation does not replace validation
Still enforce or test business-key uniqueness, source duplication, referential logic, reconciliation, deduplication, and pipeline idempotency.

## 29. Constraint consideration
For standard Snowflake tables, most PRIMARY KEY, UNIQUE, and FOREIGN KEY constraints are informational rather than enforced; NOT NULL is enforced. Do not assume a declared primary key prevents duplicates. Hybrid tables have different semantics and are outside this chapter.

## 30. Duplicate detection
```sql
SELECT CUSTOMER_ID, COUNT(*) AS ROW_COUNT
FROM CUSTOMER
GROUP BY CUSTOMER_ID
HAVING COUNT(*) > 1;
```

## 31. Defaults
```sql
CREATE TABLE CUSTOMER_AUDIT (
    CUSTOMER_ID VARCHAR,
    STATUS VARCHAR DEFAULT 'ACTIVE',
    CREATED_AT TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP()
);
```

## 32. Useful defaults
Defaults can supply statuses, ingestion timestamps, and generated expressions, but distinguish source event time from Snowflake ingestion time.

## 33. Source vs ingestion time
```sql
CREATE TABLE EVENTS (
    EVENT_ID VARCHAR,
    EVENT_TIMESTAMP TIMESTAMP_TZ,
    INGESTED_AT TIMESTAMP_LTZ DEFAULT CURRENT_TIMESTAMP()
);
```

This preserves when the event occurred separately from when Snowflake received it.

## 34. UUID identifiers
```sql
SELECT UUID_STRING();

CREATE TABLE API_REQUEST (
    REQUEST_ID VARCHAR DEFAULT UUID_STRING(),
    REQUEST_TYPE VARCHAR,
    CREATED_AT TIMESTAMP_LTZ DEFAULT CURRENT_TIMESTAMP()
);
```

## 35. Sequence vs UUID
Numeric sequences are compact and convenient surrogate keys; UUIDs are useful for distributed uniqueness patterns without sequential numbering. Choose by architecture.

## 36. Avoid MAX(ID)+1
```sql
SELECT MAX(CUSTOMER_KEY) + 1 FROM CUSTOMER;
```

This is unsafe under concurrency because multiple sessions can calculate the same next value. Use sequence or identity/autoincrement.

## 37. Sequence troubleshooting
If a key jumps from 10050 to 10100, check whether a sequence is used, whether gap-free numbering is actually required, whether values were generated but not retained, whether multiple workloads use it, and whether configuration changed.

## 38. Inspect sequence configuration
```sql
SHOW SEQUENCES LIKE 'CUSTOMER_SEQ';
SELECT GET_DDL('SEQUENCE','SNOWFLAKE_TUTORIAL.DATA_MODEL.CUSTOMER_SEQ');
```

## 39. Identity troubleshooting
```sql
DESC TABLE CUSTOMER_IDENTITY;
SELECT GET_DDL('TABLE','SNOWFLAKE_TUTORIAL.DATA_MODEL.CUSTOMER_IDENTITY');
```

Verify the expected AUTOINCREMENT/IDENTITY configuration.

## 40. Production design questions
Ask whether a source key exists, whether a surrogate is needed, whether it must be numeric/globally unique/gap-free, whether ordering matters, whether inserts are concurrent, whether identity must survive reloads, and how duplicates are detected.

## 41. Lab setup
```sql
CREATE DATABASE IF NOT EXISTS SNOWFLAKE_TUTORIAL;
CREATE SCHEMA IF NOT EXISTS SNOWFLAKE_TUTORIAL.DATA_MODEL;
USE DATABASE SNOWFLAKE_TUTORIAL;
USE SCHEMA DATA_MODEL;
```

## 42. Sequence lab
```sql
CREATE SEQUENCE CUSTOMER_SEQ START=1000 INCREMENT=1;
SELECT CUSTOMER_SEQ.NEXTVAL;
SELECT CUSTOMER_SEQ.NEXTVAL;
SELECT CUSTOMER_SEQ.NEXTVAL;
SHOW SEQUENCES LIKE 'CUSTOMER_SEQ';
```

## 43. Sequence + table
```sql
CREATE TABLE CUSTOMER_SEQUENCE (
    CUSTOMER_KEY NUMBER,
    CUSTOMER_ID VARCHAR,
    CUSTOMER_NAME VARCHAR,
    CREATED_AT TIMESTAMP_LTZ DEFAULT CURRENT_TIMESTAMP()
);

INSERT INTO CUSTOMER_SEQUENCE
(CUSTOMER_KEY,CUSTOMER_ID,CUSTOMER_NAME)
VALUES (CUSTOMER_SEQ.NEXTVAL,'CUST-100','Alice');

INSERT INTO CUSTOMER_SEQUENCE
(CUSTOMER_KEY,CUSTOMER_ID,CUSTOMER_NAME)
SELECT CUSTOMER_SEQ.NEXTVAL, COLUMN1, COLUMN2
FROM VALUES
('CUST-101','Bob'),
('CUST-102','Carol'),
('CUST-103','David');
```

## 44. Identity lab
```sql
CREATE TABLE CUSTOMER_IDENTITY (
    CUSTOMER_KEY NUMBER AUTOINCREMENT START 1 INCREMENT 1,
    CUSTOMER_ID VARCHAR,
    CUSTOMER_NAME VARCHAR,
    CREATED_AT TIMESTAMP_LTZ DEFAULT CURRENT_TIMESTAMP()
);

INSERT INTO CUSTOMER_IDENTITY (CUSTOMER_ID,CUSTOMER_NAME)
VALUES
('CUST-200','Emma'),
('CUST-201','Frank'),
('CUST-202','Grace');
```

## 45. Default lab
```sql
CREATE TABLE CUSTOMER_DEFAULT (
    CUSTOMER_ID VARCHAR,
    STATUS VARCHAR DEFAULT 'ACTIVE',
    CREATED_AT TIMESTAMP_LTZ DEFAULT CURRENT_TIMESTAMP()
);

INSERT INTO CUSTOMER_DEFAULT (CUSTOMER_ID) VALUES ('CUST-300');
```

## 46. UUID lab
```sql
CREATE TABLE REQUEST_LOG (
    REQUEST_ID VARCHAR DEFAULT UUID_STRING(),
    REQUEST_TYPE VARCHAR,
    CREATED_AT TIMESTAMP_LTZ DEFAULT CURRENT_TIMESTAMP()
);

INSERT INTO REQUEST_LOG (REQUEST_TYPE)
VALUES ('CREATE_CUSTOMER'),('UPDATE_CUSTOMER');
```

## 47. Duplicate business-key lab
```sql
INSERT INTO CUSTOMER_IDENTITY (CUSTOMER_ID,CUSTOMER_NAME)
VALUES ('CUST-500','Test A'),('CUST-500','Test B');

SELECT CUSTOMER_ID, COUNT(*) AS ROW_COUNT
FROM CUSTOMER_IDENTITY
GROUP BY CUSTOMER_ID
HAVING COUNT(*) > 1;
```

Different surrogate keys do not make the business duplicate disappear.

## 48. Operational validation
```sql
SHOW SEQUENCES IN SCHEMA SNOWFLAKE_TUTORIAL.DATA_MODEL;
SHOW TABLES IN SCHEMA SNOWFLAKE_TUTORIAL.DATA_MODEL;
DESC TABLE SNOWFLAKE_TUTORIAL.DATA_MODEL.CUSTOMER_IDENTITY;
SELECT GET_DDL('TABLE','SNOWFLAKE_TUTORIAL.DATA_MODEL.CUSTOMER_IDENTITY');
```

## 49. Cleanup
```sql
DROP TABLE IF EXISTS CUSTOMER_SEQUENCE;
DROP TABLE IF EXISTS CUSTOMER_IDENTITY;
DROP TABLE IF EXISTS CUSTOMER_DEFAULT;
DROP TABLE IF EXISTS REQUEST_LOG;
DROP SEQUENCE IF EXISTS CUSTOMER_SEQ;
```

## 50. Decision guide
Preserve a stable source business key. If Snowflake also needs a numeric surrogate, use a sequence when generation should be explicit or identity when automatic per-table generation is appropriate. Use UUIDs when that identifier model better fits the architecture. Always separately define duplicate detection.

## 51. Production takeaways
Do not assume sequence/identity values are gap-free. Do not use generated keys as event timestamps or guaranteed processing order. Never use MAX(ID)+1 for concurrent generation. Preserve business keys, validate duplicates, understand Snowflake constraint semantics, and store explicit event/ingestion timestamps when needed.

## Technical references
- https://docs.snowflake.com/en/user-guide/querying-sequences
- https://docs.snowflake.com/en/sql-reference/sql/create-sequence
- https://docs.snowflake.com/en/sql-reference/sql/create-table
- https://docs.snowflake.com/en/sql-reference/constraints-overview
- https://docs.snowflake.com/en/sql-reference/functions/uuid_string
