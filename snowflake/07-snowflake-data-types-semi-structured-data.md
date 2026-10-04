# 07 — Snowflake Data Types & Semi-Structured Data

**Status:** Canonical  
**Part:** 2 — Data Objects & SQL  
**Goal:** Understand scalar and semi-structured data types, conversions, VARIANT, JSON, ARRAY, OBJECT, FLATTEN, and production modeling.

## 1. Why data types matter
Data types affect validation, query behavior, comparisons, arithmetic, storage, transformations, and application compatibility.

```sql
CREATE TABLE CLAIM (
    CLAIM_ID NUMBER,
    MEMBER_ID VARCHAR,
    SERVICE_DATE DATE,
    CLAIM_AMOUNT NUMBER(12,2),
    IS_ACTIVE BOOLEAN,
    CREATED_AT TIMESTAMP_NTZ
);
```

## 2. Major type families
Snowflake supports numeric, string/binary, Boolean, date/time, semi-structured (VARIANT/OBJECT/ARRAY), geospatial, and vector types.

## 3. Numeric types
Common declarations include NUMBER, DECIMAL, NUMERIC, INTEGER, INT, BIGINT, SMALLINT, FLOAT, DOUBLE, and REAL. NUMBER/DECIMAL/NUMERIC are fixed-point synonyms; integer-style types map to NUMBER with scale 0.

```sql
CREATE TABLE PAYMENT (
    PAYMENT_ID NUMBER,
    AMOUNT NUMBER(12,2),
    TAX NUMBER(12,2)
);
```

## 4. Precision and scale
`NUMBER(12,2)` has precision 12 and scale 2. Exact fixed-point numbers are generally appropriate for financial amounts.

## 5. Floating point
FLOAT/DOUBLE/REAL are approximate numeric types. Use them when approximation is acceptable; do not treat floating-point values as exact financial decimals.

## 6. Character types
Common declarations include VARCHAR, CHAR, CHARACTER, STRING, and TEXT.

```sql
CREATE TABLE CUSTOMER (
    CUSTOMER_ID NUMBER,
    FIRST_NAME VARCHAR,
    LAST_NAME VARCHAR,
    EMAIL VARCHAR
);
```

## 7. Boolean
```sql
CREATE TABLE CUSTOMER_STATUS (
    CUSTOMER_ID NUMBER,
    IS_ACTIVE BOOLEAN
);

INSERT INTO CUSTOMER_STATUS VALUES (1, TRUE), (2, FALSE);

SELECT * FROM CUSTOMER_STATUS WHERE IS_ACTIVE = TRUE;
```

## 8. Date and time
Important types include DATE, TIME, TIMESTAMP_NTZ, TIMESTAMP_LTZ, and TIMESTAMP_TZ.

## 9. DATE
Use DATE when only a calendar date matters.

```sql
CREATE TABLE CLAIM_DATE (
    CLAIM_ID NUMBER,
    SERVICE_DATE DATE
);
```

## 10. TIME
Use TIME for a time of day without a date.

```sql
CREATE TABLE BUSINESS_HOURS (
    LOCATION_ID NUMBER,
    OPEN_TIME TIME,
    CLOSE_TIME TIME
);
```

## 11. TIMESTAMP_NTZ
TIMESTAMP_NTZ represents a timestamp without time-zone semantics. Use it when the value is intentionally a wall-clock timestamp without conversion semantics.

## 12. TIMESTAMP_LTZ
TIMESTAMP_LTZ represents an instant and displays it using the session time zone.

```sql
SHOW PARAMETERS LIKE 'TIMEZONE';
```

## 13. TIMESTAMP_TZ
TIMESTAMP_TZ retains offset information associated with the value. Timestamp selection should be part of the application/data contract.

## 14. Timestamp production rule
Before choosing a timestamp type, decide whether it represents a real instant, whether timezone conversion matters, whether display should follow session timezone, whether an offset must be retained, or whether it is only a local wall-clock value.

## 15. Type conversion
```sql
SELECT CAST('123' AS NUMBER);
SELECT '123'::NUMBER;
SELECT '2026-10-04'::DATE;
SELECT '125.50'::NUMBER(10,2);
SELECT 'TRUE'::BOOLEAN;
```

## 16. TRY conversion functions
Defensive conversion returns NULL rather than failing on malformed values.

```sql
SELECT TRY_TO_NUMBER('ABC');
SELECT TRY_TO_DATE('not-a-date');
```

## 17. Data-quality pattern
```sql
SELECT
    RAW_AMOUNT,
    TRY_TO_NUMBER(RAW_AMOUNT, 18, 2) AS PARSED_AMOUNT
FROM STAGING_PAYMENTS;

SELECT *
FROM STAGING_PAYMENTS
WHERE RAW_AMOUNT IS NOT NULL
  AND TRY_TO_NUMBER(RAW_AMOUNT, 18, 2) IS NULL;
```

## 18. Semi-structured data
Snowflake provides VARIANT, OBJECT, and ARRAY for JSON, API payloads, event messages, nested records, and changing schemas.

## 19. VARIANT
```sql
CREATE TABLE API_EVENTS (
    EVENT_ID NUMBER,
    PAYLOAD VARIANT
);

INSERT INTO API_EVENTS
SELECT 1, PARSE_JSON(
'{"patient_id":1001,"status":"ACTIVE","address":{"city":"Charlotte","state":"NC"}}'
);
```

## 20. PARSE_JSON
PARSE_JSON converts a valid JSON-formatted string to a semi-structured value.

```sql
SELECT PARSE_JSON('{"name":"Alice","department":"Engineering"}');
```

## 21. TRY_PARSE_JSON
Use TRY_PARSE_JSON to validate potentially malformed JSON without failing the validation query.

```sql
SELECT TRY_PARSE_JSON('{"name":"Alice"');
```

Invalid input returns NULL.

## 22. Practical mixed-type problem
A semi-structured column can contain different runtime types. Inspect them rather than assuming consistency.

```sql
SELECT
    TYPEOF(VERATO_MULTIPLE_ADDRESSES),
    COUNT(*)
FROM DAP.L2.EMPI
GROUP BY 1;
```

A result containing both ARRAY and VARCHAR indicates an inconsistent data contract.

## 23. TYPEOF
```sql
SELECT TYPEOF(PAYLOAD) FROM API_EVENTS;
SELECT TYPEOF(PAYLOAD:address) FROM API_EVENTS;
```

TYPEOF is invaluable when troubleshooting VARIANT content.

## 24. Validate JSON strings
```sql
SELECT
    VERATO_MULTIPLE_ADDRESSES,
    TRY_PARSE_JSON(VERATO_MULTIPLE_ADDRESSES::VARCHAR)
FROM DAP.L2.EMPI
WHERE TYPEOF(VERATO_MULTIPLE_ADDRESSES) = 'VARCHAR';

SELECT *
FROM DAP.L2.EMPI
WHERE TYPEOF(VERATO_MULTIPLE_ADDRESSES) = 'VARCHAR'
  AND TRY_PARSE_JSON(VERATO_MULTIPLE_ADDRESSES::VARCHAR) IS NULL;
```

## 25. Query JSON attributes
```sql
SELECT
    PAYLOAD:patient_id,
    PAYLOAD:name,
    PAYLOAD:status
FROM API_EVENTS;
```

## 26. Cast extracted values
```sql
SELECT
    PAYLOAD:patient_id::NUMBER AS PATIENT_ID,
    PAYLOAD:name::VARCHAR AS NAME,
    PAYLOAD:status::VARCHAR AS STATUS
FROM API_EVENTS;
```

## 27. Nested JSON
```sql
SELECT
    PAYLOAD:patient_id::NUMBER AS PATIENT_ID,
    PAYLOAD:address.city::VARCHAR AS CITY,
    PAYLOAD:address.state::VARCHAR AS STATE,
    PAYLOAD:address.zip::VARCHAR AS ZIP
FROM API_EVENTS;
```

## 28. ARRAY
```sql
SELECT ARRAY_CONSTRUCT('Charlotte','Atlanta','New York');

CREATE TABLE CUSTOMER_CONTACT (
    CUSTOMER_ID NUMBER,
    PHONE_NUMBERS ARRAY
);
```

## 29. Array elements
Array positions are zero-based.

```sql
SELECT PHONE_NUMBERS[0]::VARCHAR AS PRIMARY_PHONE
FROM CUSTOMER_CONTACT;
```

## 30. OBJECT
```sql
SELECT OBJECT_CONSTRUCT(
    'city','Charlotte',
    'state','NC',
    'zip','28202'
);
```

## 31. FLATTEN
```sql
SELECT
    PAYLOAD:patient_id::NUMBER AS PATIENT_ID,
    A.VALUE:city::VARCHAR AS CITY,
    A.VALUE:state::VARCHAR AS STATE
FROM PATIENT_EVENTS,
LATERAL FLATTEN(INPUT => PAYLOAD:addresses) A;
```

FLATTEN bridges nested arrays and relational rows.

## 32. FLATTEN behavior
One parent row with three array elements can become three relational rows while preserving parent context.

## 33. FLATTEN metadata
FLATTEN exposes SEQ, KEY, PATH, INDEX, VALUE, and THIS.

```sql
SELECT F.INDEX, F.VALUE, TYPEOF(F.VALUE)
FROM PATIENT_EVENTS,
LATERAL FLATTEN(INPUT => PAYLOAD:addresses) F;
```

## 34. Semi-structured modeling
A common production pattern is RAW VARIANT → STAGING validation/normalization → CURATED strongly typed columns. Flexible ingestion should not eliminate downstream contracts.

## 35. Good VARIANT use cases
Raw API payloads, Kafka events, changing source JSON, sparse attributes, nested structures, audit payloads, and landing zones are common candidates.

## 36. When relational columns are better
Frequently filtered or joined business fields such as PATIENT_ID, CLAIM_ID, SERVICE_DATE, STATUS, and CUSTOMER_ID often benefit from explicit typed columns.

## 37. Avoid inconsistent representation
A column containing ARRAY, VARCHAR-encoded JSON, OBJECT, and NULL may be technically legal in VARIANT but expensive for consumers to reason about. Define an expected contract.

## 38. Normalize mixed JSON types
```sql
SELECT
    CASE
        WHEN TYPEOF(ADDRESS_DATA) = 'ARRAY' THEN ADDRESS_DATA
        WHEN TYPEOF(ADDRESS_DATA) = 'VARCHAR'
            THEN TRY_PARSE_JSON(ADDRESS_DATA::VARCHAR)
        ELSE NULL
    END AS NORMALIZED_ADDRESS
FROM SOURCE_TABLE;
```

Then validate TYPEOF on the normalized result.

## 39. SQL NULL vs JSON null
Do not assume all visually null values have identical semantics. Inspect the value and TYPEOF when debugging semi-structured data.

## 40. Schema-on-read still needs governance
Flexible ingestion still needs a data contract, validation, normalization, and a curated schema.

## 41. Type troubleshooting
For conversion errors, identify actual source values, expected types, and where conversion occurs. Use TRY_TO_* to isolate invalid rows.

## 42. Semi-structured troubleshooting
Check valid JSON, TYPEOF, string vs VARIANT, OBJECT vs ARRAY, path existence, FLATTEN target, and cross-row type consistency.

## 43. Hands-on structured lab
```sql
CREATE DATABASE IF NOT EXISTS SNOWFLAKE_TUTORIAL;
CREATE SCHEMA IF NOT EXISTS SNOWFLAKE_TUTORIAL.DATA_TYPES;
USE DATABASE SNOWFLAKE_TUTORIAL;
USE SCHEMA DATA_TYPES;

CREATE TABLE CLAIM (
    CLAIM_ID NUMBER,
    MEMBER_ID VARCHAR,
    SERVICE_DATE DATE,
    CLAIM_AMOUNT NUMBER(12,2),
    IS_ACTIVE BOOLEAN,
    CREATED_AT TIMESTAMP_NTZ
);

INSERT INTO CLAIM
VALUES (1001,'M100','2026-10-04',125.75,TRUE,CURRENT_TIMESTAMP());

SELECT * FROM CLAIM;
```

## 44. JSON lab
```sql
CREATE TABLE PATIENT_EVENT (
    EVENT_ID NUMBER,
    PAYLOAD VARIANT
);

INSERT INTO PATIENT_EVENT
SELECT 1, PARSE_JSON(
'{"patient_id":1001,"name":"Alice","addresses":[{"city":"Charlotte","state":"NC"},{"city":"Atlanta","state":"GA"}]}'
);

SELECT PAYLOAD, TYPEOF(PAYLOAD) FROM PATIENT_EVENT;
```

## 45. Extract fields
```sql
SELECT
    PAYLOAD:patient_id::NUMBER AS PATIENT_ID,
    PAYLOAD:name::VARCHAR AS PATIENT_NAME,
    PAYLOAD:addresses,
    TYPEOF(PAYLOAD:addresses)
FROM PATIENT_EVENT;
```

## 46. Flatten addresses
```sql
SELECT
    PAYLOAD:patient_id::NUMBER AS PATIENT_ID,
    F.INDEX AS ADDRESS_INDEX,
    F.VALUE:city::VARCHAR AS CITY,
    F.VALUE:state::VARCHAR AS STATE
FROM PATIENT_EVENT,
LATERAL FLATTEN(INPUT => PAYLOAD:addresses) F
ORDER BY ADDRESS_INDEX;
```

## 47. Invalid JSON lab
```sql
SELECT TRY_PARSE_JSON('{"patient_id":1001');
SELECT TRY_PARSE_JSON('{"patient_id":1001}');
```

## 48. Production validation
```sql
SELECT TYPEOF(PAYLOAD) AS VALUE_TYPE, COUNT(*) AS ROW_COUNT
FROM PATIENT_EVENT
GROUP BY 1;

SELECT TYPEOF(PAYLOAD:addresses) AS ADDRESS_TYPE, COUNT(*) AS ROW_COUNT
FROM PATIENT_EVENT
GROUP BY 1;
```

## 49. Cleanup
```sql
DROP TABLE IF EXISTS SNOWFLAKE_TUTORIAL.DATA_TYPES.CLAIM;
DROP TABLE IF EXISTS SNOWFLAKE_TUTORIAL.DATA_TYPES.PATIENT_EVENT;
```

## 50. Production takeaways
Choose types by business meaning. Use exact numeric types when exact decimal arithmetic is required. Define timestamp semantics deliberately. Use TRY_TO_* for malformed source values, VARIANT for flexible/nested raw ingestion, TYPEOF for troubleshooting, TRY_PARSE_JSON for validation, and FLATTEN for arrays. Do not publish an uncontrolled mixture of ARRAY, OBJECT, and VARCHAR-encoded JSON as a curated contract.

## Technical references
- https://docs.snowflake.com/en/sql-reference/data-types
- https://docs.snowflake.com/en/sql-reference/data-types-semistructured
- https://docs.snowflake.com/en/sql-reference/functions/parse_json
- https://docs.snowflake.com/en/sql-reference/functions/try_parse_json
- https://docs.snowflake.com/en/sql-reference/functions/typeof
- https://docs.snowflake.com/en/sql-reference/functions/flatten
