# 13 — COPY INTO: Bulk Data Loading

**Status:** CANONICAL  
**Part:** 3 — Data Loading & Unloading  
**Batch:** 11–15

## Goal
Use `COPY INTO <table>` safely for production bulk loading, including explicit mapping, validation, lineage, file selection, error handling, history, replay, reconciliation, performance, and idempotency.

## 1. Bulk-load flow
```text
Source -> Stage -> File format -> COPY INTO -> RAW -> Validate -> STAGING -> CURATED
```

Basic load:

```sql
COPY INTO CUSTOMER
FROM @CUSTOMER_STAGE
FILE_FORMAT=(FORMAT_NAME='CUSTOMER_CSV_FORMAT');
```

Use fully qualified object names in production automation.

## 2. Pre-load checks
Before COPY:

```sql
SELECT CURRENT_ACCOUNT_NAME(), CURRENT_REGION(), CURRENT_USER(),
       CURRENT_ROLE(), CURRENT_WAREHOUSE(),
       CURRENT_DATABASE(), CURRENT_SCHEMA();

LIST @RAW_DB.INGESTION.CUSTOMER_STAGE;

SELECT METADATA$FILENAME, METADATA$FILE_ROW_NUMBER,
       $1,$2,$3
FROM @RAW_DB.INGESTION.CUSTOMER_STAGE
  (FILE_FORMAT => 'RAW_DB.INGESTION.CUSTOMER_CSV_FORMAT')
LIMIT 100;
```

If staged parsing is wrong, fix that layer before changing the target.

## 3. Explicit transformation/mapping
```sql
COPY INTO RAW_CUSTOMER (
  CUSTOMER_ID, CUSTOMER_NAME, REGION,
  SOURCE_FILE, SOURCE_ROW_NUMBER, INGESTED_AT
)
FROM (
  SELECT
    $1::NUMBER,
    $2::VARCHAR,
    $3::VARCHAR,
    METADATA$FILENAME,
    METADATA$FILE_ROW_NUMBER,
    CURRENT_TIMESTAMP()
  FROM @CUSTOMER_STAGE
)
FILE_FORMAT=(FORMAT_NAME='CUSTOMER_CSV_FORMAT');
```

Explicit mapping makes production contracts easier to review.

## 4. Defensive validation
Before hard casts:

```sql
SELECT METADATA$FILENAME, METADATA$FILE_ROW_NUMBER,
       $1, TRY_TO_NUMBER($1) AS CUSTOMER_ID
FROM @CUSTOMER_STAGE
  (FILE_FORMAT => 'CUSTOMER_CSV_FORMAT')
WHERE $1 IS NOT NULL
  AND TRY_TO_NUMBER($1) IS NULL;
```

Apply similar `TRY_TO_DATE`, `TRY_TO_TIMESTAMP_*`, and `TRY_PARSE_JSON` checks where appropriate.

## 5. File selection
Load known files explicitly:

```sql
COPY INTO CUSTOMER
FROM @CUSTOMER_STAGE
FILES=('customer_20261004_001.csv.gz',
       'customer_20261004_002.csv.gz')
FILE_FORMAT=(FORMAT_NAME='CUSTOMER_CSV_FORMAT');
```

Or use a carefully tested PATTERN:

```sql
COPY INTO CUSTOMER
FROM @CUSTOMER_STAGE
PATTERN='.*customer.*[.]csv[.]gz'
FILE_FORMAT=(FORMAT_NAME='CUSTOMER_CSV_FORMAT');
```

Use FILES for controlled replay when the affected objects are known.

## 6. Load metadata and idempotency
Snowflake records COPY load metadata and normally avoids reloading the same file. This is file-level idempotency, not business-record deduplication.

```text
COPY history -> Was this file loaded?
MERGE/business key -> Was this logical record already processed?
```

A different filename can contain duplicate business records.

## 7. FORCE
```sql
COPY INTO CUSTOMER
FROM @CUSTOMER_STAGE
FILES=('customer_20261004.csv.gz')
FILE_FORMAT=(FORMAT_NAME='CUSTOMER_CSV_FORMAT')
FORCE=TRUE;
```

FORCE deliberately bypasses normal file-load protection. Before using it, understand what already loaded, duplicate risk, rollback, and replay scope. Never use FORCE as the first response to “0 rows loaded.”

## 8. Error handling and validation
Use validation before sensitive loads:

```sql
COPY INTO CUSTOMER
FROM @CUSTOMER_STAGE
FILE_FORMAT=(FORMAT_NAME='CUSTOMER_CSV_FORMAT')
VALIDATION_MODE='RETURN_ERRORS';
```

Choose `ON_ERROR` behavior based on data-integrity requirements. If permissive loading is used, monitor rejected rows/files, thresholds, reconciliation, quarantine, and replay. “CONTINUE” must not mean silent data loss.

## 9. Load history
Use current Snowflake COPY history/load-history interfaces to determine:
- whether a file loaded,
- when,
- target table,
- row/error status,
- whether it was partial/failed.

Use query history for SQL execution context:

```sql
SELECT QUERY_ID, QUERY_TEXT, USER_NAME, ROLE_NAME, WAREHOUSE_NAME,
       START_TIME, END_TIME, EXECUTION_STATUS,
       ERROR_CODE, ERROR_MESSAGE
FROM SNOWFLAKE.ACCOUNT_USAGE.QUERY_HISTORY
WHERE START_TIME >= DATEADD('day',-1,CURRENT_TIMESTAMP())
  AND QUERY_TEXT ILIKE '%COPY INTO%'
ORDER BY START_TIME DESC;
```

ACCOUNT_USAGE has latency; use more immediate Information Schema/session history during live incidents.

## 10. Query tags
```sql
ALTER SESSION SET QUERY_TAG=
'pipeline=customer_bulk_load;env=prod;batch=20261004_001';
-- COPY ...
ALTER SESSION UNSET QUERY_TAG;
```

Tags make automated ingestion easier to find in history.

## 11. RAW-first semi-structured load
```sql
CREATE TABLE RAW_PATIENT_EVENT (
  PAYLOAD VARIANT,
  SOURCE_FILE VARCHAR,
  INGESTED_AT TIMESTAMP_LTZ
);

COPY INTO RAW_PATIENT_EVENT
FROM (
  SELECT $1, METADATA$FILENAME, CURRENT_TIMESTAMP()
  FROM @PATIENT_JSON_STAGE
)
FILE_FORMAT=(FORMAT_NAME='PATIENT_JSON_FORMAT');
```

Preserving raw payloads can improve replay and later normalization.

## 12. Reconciliation
A successful COPY command is not sufficient. Reconcile:
- expected source files,
- expected source rows/control totals,
- loaded rows,
- rejected rows,
- intentionally filtered rows,
- duplicates.

A control table can track batch ID, source file, expected/loaded/rejected counts, status, query ID, start/end time, and replay count.

## 13. File retention
Do not automatically REMOVE files immediately after COPY. Use:

```text
Inbound -> COPY -> Validate -> Reconcile -> Mark success
        -> retain/archive -> delete after approved retention
```

Source files can be recovery assets.

## 14. Performance
Bulk loading uses warehouse compute. Investigate file count/size, compression, parsing, transformation complexity, warehouse queueing, concurrency, and cloud-storage behavior before resizing.

A dedicated ingestion warehouse can isolate COPY from BI/application workloads:

```sql
CREATE WAREHOUSE IF NOT EXISTS INGEST_WH
  WAREHOUSE_SIZE='SMALL'
  AUTO_SUSPEND=60
  AUTO_RESUME=TRUE
  INITIALLY_SUSPENDED=TRUE;
```

Choose size from measured workload.

## 15. Common incidents
**0 rows loaded:** verify LIST, FILES/PATTERN, path, file arrival, and whether files already loaded.

**Conversion error:** query staged data and use TRY_TO_* to identify exact file/row.

**Duplicate data after replay:** inspect FORCE usage, renamed files, producer resend, lineage, and business-key MERGE/dedup.

**Partial load:** capture COPY result, rejected rows, affected files, reconcile, and do not publish until understood.

**Slow load:** compare current file count/size and queue/execution metrics with a normal baseline.

## 16. Hands-on lab
```sql
CREATE DATABASE IF NOT EXISTS SNOWFLAKE_TUTORIAL;
CREATE SCHEMA IF NOT EXISTS SNOWFLAKE_TUTORIAL.COPY_LAB;
USE DATABASE SNOWFLAKE_TUTORIAL;
USE SCHEMA COPY_LAB;

CREATE WAREHOUSE IF NOT EXISTS TUTORIAL_INGEST_WH
  WAREHOUSE_SIZE='XSMALL'
  AUTO_SUSPEND=60 AUTO_RESUME=TRUE
  INITIALLY_SUSPENDED=TRUE;
USE WAREHOUSE TUTORIAL_INGEST_WH;

CREATE OR REPLACE FILE FORMAT CUSTOMER_CSV_FORMAT
  TYPE=CSV FIELD_DELIMITER=',' SKIP_HEADER=1
  FIELD_OPTIONALLY_ENCLOSED_BY='"'
  NULL_IF=('NULL','\\N')
  EMPTY_FIELD_AS_NULL=TRUE
  ERROR_ON_COLUMN_COUNT_MISMATCH=TRUE;

CREATE OR REPLACE STAGE CUSTOMER_STAGE
  FILE_FORMAT=(FORMAT_NAME='CUSTOMER_CSV_FORMAT');

CREATE OR REPLACE TABLE RAW_CUSTOMER (
  CUSTOMER_ID NUMBER,
  CUSTOMER_NAME VARCHAR,
  REGION VARCHAR,
  SOURCE_FILE VARCHAR,
  SOURCE_ROW_NUMBER NUMBER,
  INGESTED_AT TIMESTAMP_LTZ
);
```

Create and upload:

```text
customer_id,customer_name,region
1,Alice,EAST
2,Bob,WEST
3,"Carol Jones",SOUTH
4,David,EAST
```

```sql
PUT file://C:/snowflake-lab/customer.csv
@CUSTOMER_STAGE AUTO_COMPRESS=TRUE;

LIST @CUSTOMER_STAGE;

SELECT METADATA$FILENAME, METADATA$FILE_ROW_NUMBER,
       $1,$2,$3
FROM @CUSTOMER_STAGE
  (FILE_FORMAT => 'CUSTOMER_CSV_FORMAT');
```

Validate then load:

```sql
COPY INTO RAW_CUSTOMER (
  CUSTOMER_ID,CUSTOMER_NAME,REGION,
  SOURCE_FILE,SOURCE_ROW_NUMBER,INGESTED_AT
)
FROM (
  SELECT $1::NUMBER,$2::VARCHAR,$3::VARCHAR,
         METADATA$FILENAME,METADATA$FILE_ROW_NUMBER,
         CURRENT_TIMESTAMP()
  FROM @CUSTOMER_STAGE
)
FILE_FORMAT=(FORMAT_NAME='CUSTOMER_CSV_FORMAT')
VALIDATION_MODE='RETURN_ERRORS';
```

After errors are clear, run the same COPY without VALIDATION_MODE and verify:

```sql
SELECT SOURCE_FILE, COUNT(*) AS ROW_COUNT,
       MIN(SOURCE_ROW_NUMBER), MAX(SOURCE_ROW_NUMBER)
FROM RAW_CUSTOMER
GROUP BY SOURCE_FILE;
```

Rerun without FORCE to observe file-level load tracking. Experiment with FORCE only against this disposable lab and then inspect duplicates.

## 17. Cleanup
```sql
REMOVE @CUSTOMER_STAGE;
DROP TABLE IF EXISTS RAW_CUSTOMER;
DROP STAGE IF EXISTS CUSTOMER_STAGE;
DROP FILE FORMAT IF EXISTS CUSTOMER_CSV_FORMAT;
DROP WAREHOUSE IF EXISTS TUTORIAL_INGEST_WH;
```

## Production takeaways
1. LIST and stage-query before COPY troubleshooting.
2. Capture source filename/row lineage.
3. Validate types before large loads.
4. COPY file history is not business deduplication.
5. FORCE is a controlled replay operation.
6. ON_ERROR must align with data-quality policy.
7. Reconcile source, loaded, rejected, filtered, and duplicate counts.
8. Keep ingestion idempotent and replayable.
9. Retain source data according to recovery requirements.
10. Tune based on evidence, not warehouse size alone.

## Technical references
- https://docs.snowflake.com/en/sql-reference/sql/copy-into-table
- https://docs.snowflake.com/en/user-guide/data-load-bulk
- https://docs.snowflake.com/en/sql-reference/functions/validate
- https://docs.snowflake.com/en/sql-reference/functions/copy_history
- https://docs.snowflake.com/en/user-guide/querying-metadata
