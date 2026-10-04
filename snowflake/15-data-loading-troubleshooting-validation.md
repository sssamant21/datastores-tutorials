# 15 — Data Loading Troubleshooting & Validation

**Status:** CANONICAL  
**Part:** 3 — Data Loading & Unloading  
**Batch:** 11–15

## Goal
Provide an SRE/DBRE-ready method for Snowflake loading incidents across source delivery, stages, integrations/IAM, file formats, parsing, COPY, schema drift, duplicates, partial loads, performance, reconciliation, replay, and post-load acceptance.

## 1. Troubleshoot source to target
```text
Source -> Storage -> Integration/IAM -> Stage -> File format
       -> Parse/convert -> COPY -> RAW -> Reconcile
       -> Business validation -> Publish
```

Do not randomly resize warehouses or modify tables/file formats.

## 2. Incident intake
Capture:
- environment/account/region,
- database/schema/warehouse/role,
- pipeline/batch ID,
- stage/file format/target,
- expected files and rows,
- last successful load,
- query ID,
- exact error and start time.

Verify context:

```sql
SELECT CURRENT_ORGANIZATION_NAME(), CURRENT_ACCOUNT_NAME(),
       CURRENT_REGION(), CURRENT_USER(), CURRENT_ROLE(),
       CURRENT_WAREHOUSE(), CURRENT_DATABASE(), CURRENT_SCHEMA();
```

Then ask what changed since the last successful batch: producer version, filename/path, schema, delimiter, cloud IAM, integration, grants, format, target schema, warehouse, network policy, or pipeline SQL.

## 3. File arrival
```sql
LIST @CUSTOMER_STAGE;
LIST @CUSTOMER_STAGE/customer/;
```

Verify exact filename, path, size, timestamp, compression, and whether files are zero-byte or abnormal compared with baseline. If the file is missing, investigate upstream delivery rather than the target table.

## 4. External-stage access
```sql
DESC STAGE CUSTOMER_EXTERNAL_STAGE;
DESC INTEGRATION CUSTOMER_STORAGE_INT;
LIST @CUSTOMER_EXTERNAL_STAGE;
```

If LIST fails, inspect role privileges, allowed locations, cloud IAM/trust, bucket/container policy, encryption-key permissions, and storage/network controls. Fix access before COPY troubleshooting.

## 5. Parse staged data
```sql
SELECT METADATA$FILENAME, METADATA$FILE_ROW_NUMBER,
       $1,$2,$3
FROM @CUSTOMER_STAGE
  (FILE_FORMAT => 'CUSTOMER_CSV_FORMAT')
LIMIT 100;
```

Inspect:

```sql
DESC FILE FORMAT CUSTOMER_CSV_FORMAT;
SELECT GET_DDL('FILE_FORMAT','RAW_DB.INGESTION.CUSTOMER_CSV_FORMAT');
```

CSV checks: delimiter, record delimiter, header, enclosure/quotes, NULL_IF, empty-field behavior, trim/escape behavior, encoding, compression, column-count mismatch.

## 6. Common parsing failures
**Whole row in $1:** wrong delimiter.

**Header fails numeric cast:** SKIP_HEADER wrong.

**Embedded comma shifts columns:** quote/enclosure handling wrong.

**Unexpected symbols:** encoding mismatch.

**Wrong column count:** malformed row, delimiter/quote/newline issue, or producer schema change.

**Compression error:** extension/configuration does not match actual content.

Do not change the target schema before understanding raw parsing.

## 7. Type validation
Numbers:

```sql
SELECT METADATA$FILENAME, METADATA$FILE_ROW_NUMBER,$1
FROM @CUSTOMER_STAGE
  (FILE_FORMAT => 'CUSTOMER_CSV_FORMAT')
WHERE $1 IS NOT NULL
  AND TRY_TO_NUMBER($1) IS NULL;
```

Dates:

```sql
SELECT METADATA$FILENAME, METADATA$FILE_ROW_NUMBER,
       $4, TRY_TO_DATE($4)
FROM @CLAIMS_STAGE
  (FILE_FORMAT => 'CLAIMS_CSV_FORMAT');
```

Timestamps:

```sql
SELECT $5, TRY_TO_TIMESTAMP_NTZ($5), TRY_TO_TIMESTAMP_TZ($5)
FROM @EVENT_STAGE
  (FILE_FORMAT => 'EVENT_CSV_FORMAT');
```

Use exact file/row metadata as incident evidence.

## 8. Semi-structured validation
```sql
SELECT METADATA$FILENAME,$1,TYPEOF($1),
       $1:patient_id,TYPEOF($1:patient_id),
       $1:addresses,TYPEOF($1:addresses)
FROM @PATIENT_STAGE
  (FILE_FORMAT => 'PATIENT_JSON_FORMAT');
```

For the EMPI-style mixed representation problem:

```sql
SELECT TYPEOF(VERATO_MULTIPLE_ADDRESSES),
       VERATO_MULTIPLE_ADDRESSES
FROM DAP.L2.EMPI;

SELECT TRY_PARSE_JSON(VERATO_MULTIPLE_ADDRESSES)
FROM DAP.L2.EMPI
WHERE TYPEOF(VERATO_MULTIPLE_ADDRESSES)='VARCHAR';
```

ARRAY versus VARCHAR/stringified JSON is a schema/source consistency issue; normalize deliberately rather than hiding it.

For Parquet/other supported formats, use INFER_SCHEMA and representative files to detect schema evolution.

## 9. Validate COPY
```sql
COPY INTO CUSTOMER
FROM @CUSTOMER_STAGE
FILE_FORMAT=(FORMAT_NAME='CUSTOMER_CSV_FORMAT')
VALIDATION_MODE='RETURN_ERRORS';
```

Use this after stage parsing/type checks and before a sensitive bulk load.

## 10. Query and load history
For recent session activity:

```sql
SELECT *
FROM TABLE(
  INFORMATION_SCHEMA.QUERY_HISTORY_BY_SESSION(RESULT_LIMIT=>100)
)
ORDER BY START_TIME DESC;
```

Historical account view:

```sql
SELECT QUERY_ID, QUERY_TEXT, USER_NAME, ROLE_NAME, WAREHOUSE_NAME,
       START_TIME, END_TIME, EXECUTION_STATUS,
       ERROR_CODE, ERROR_MESSAGE
FROM SNOWFLAKE.ACCOUNT_USAGE.QUERY_HISTORY
WHERE START_TIME >= DATEADD('day',-1,CURRENT_TIMESTAMP())
  AND QUERY_TEXT ILIKE '%COPY INTO%'
ORDER BY START_TIME DESC;
```

Use COPY/load history to determine whether a file was new, already loaded, partial, or failed. Remember ACCOUNT_USAGE latency.

## 11. Zero rows loaded
Investigate in this order:

```text
LIST -> expected files present?
 -> FILES/PATTERN/path correct?
 -> already loaded?
 -> correct account/environment?
 -> load history?
```

Do not immediately use FORCE.

## 12. FORCE and replay
Before FORCE:
1. Identify exact failed batch/files.
2. Determine what already loaded.
3. Determine rejected rows.
4. Assess duplicate risk.
5. Correct root cause.
6. Define smallest replay scope.
7. Plan rollback.
8. Replay.
9. Reconcile.
10. Record outcome.

Prefer targeted FILES over replaying an entire day. File-level COPY metadata is not business deduplication.

## 13. Duplicates
```sql
SELECT BUSINESS_KEY, COUNT(*) AS ROW_COUNT
FROM TARGET_TABLE
GROUP BY BUSINESS_KEY
HAVING COUNT(*)>1;
```

Investigate FORCE, renamed files, producer resend, duplicate source rows, multiple writers, missing MERGE, or wrong business keys. Use SOURCE_FILE/BATCH_ID lineage.

## 14. Partial loads and reconciliation
A pipeline must not report simple SUCCESS when rows are silently missing.

Minimum equation:

```text
Expected source rows
 = loaded rows
 + rejected rows
 + intentionally filtered rows
```

Also reconcile by file, batch, business key, and important aggregates/control totals.

Example:

```sql
SELECT SOURCE_FILE, COUNT(*) AS LOADED_ROWS
FROM RAW_CUSTOMER
WHERE BATCH_ID='20261004_001'
GROUP BY SOURCE_FILE;

SELECT COUNT(*) AS TOTAL_ROWS,
       COUNT(DISTINCT CUSTOMER_ID) AS UNIQUE_CUSTOMERS
FROM RAW_CUSTOMER
WHERE BATCH_ID='20261004_001';
```

## 15. Schema drift
Treat added/removed columns and type changes as governed producer changes. Automatic schema evolution, where used, must still be monitored for what changed, who/what caused it, downstream compatibility, and rollback.

Do not simply widen a target because an upstream identifier unexpectedly changed from NUMBER to values such as `A123`.

## 16. Performance troubleshooting
Compare the current batch with a known-good baseline:
- file count,
- total bytes,
- average/min/max file size,
- rows,
- warehouse,
- queue time,
- execution duration,
- rejected rows,
- format/producer version.

Millions of tiny files can increase management overhead; too few huge files can reduce useful parallelism and make retries expensive.

Check queue-related query-history metrics such as provisioning/repair/overload time. Separate queue time from execution before tuning.

A larger warehouse does not fix missing files, malformed CSV, bad IAM, wrong delimiters, or duplicate source data.

## 17. RAW and quarantine
A RAW layer preserves source data/lineage and simplifies replay. For invalid records, use a governed quarantine process:

```text
Validation -> valid -> RAW
           -> invalid -> quarantine -> investigate -> correct -> replay
```

Capture batch ID, source file/row, raw payload/value, error category/message, detection time, resolution status, and replay time.

## 18. Retry strategy
Retry transient failures with bounded retries/backoff. Do not retry deterministic malformed data repeatedly. Classify errors and alert when manual intervention is required.

## 19. Post-load acceptance
COPY success is only one layer.

```text
File arrival
 -> file integrity/parsing
 -> type validation
 -> row reconciliation
 -> duplicate/completeness checks
 -> business-rule validation
 -> freshness/distribution checks
 -> publish
```

Examples:

```sql
SELECT COUNT(*) FROM CUSTOMER WHERE CUSTOMER_ID IS NULL;

SELECT CUSTOMER_ID,COUNT(*)
FROM CUSTOMER
GROUP BY CUSTOMER_ID
HAVING COUNT(*)>1;

SELECT MAX(INGESTED_AT) AS LAST_INGESTION
FROM RAW_CUSTOMER;

SELECT REGION,COUNT(*)
FROM CUSTOMER
WHERE BATCH_ID='20261004_001'
GROUP BY REGION;
```

A total count can look correct while a region/partition is missing and another is duplicated.

## 20. Observability and alerts
Monitor file arrival delay/count/bytes, rows loaded/rejected, rejection percentage, COPY duration, queue time, warehouse, last successful batch, freshness, duplicates, schema changes, and replay count.

Alert on missing expected files, failed loads, duration regression, rejection thresholds, count mismatches, freshness SLA misses, unexpected schema changes, repeated replay, and stage-access failures.

## 21. Hands-on incident lab
```sql
CREATE DATABASE IF NOT EXISTS SNOWFLAKE_TUTORIAL;
CREATE SCHEMA IF NOT EXISTS SNOWFLAKE_TUTORIAL.LOAD_TROUBLESHOOTING;
USE DATABASE SNOWFLAKE_TUTORIAL;
USE SCHEMA LOAD_TROUBLESHOOTING;

CREATE WAREHOUSE IF NOT EXISTS TUTORIAL_LOAD_WH
  WAREHOUSE_SIZE='XSMALL'
  AUTO_SUSPEND=60 AUTO_RESUME=TRUE
  INITIALLY_SUSPENDED=TRUE;
USE WAREHOUSE TUTORIAL_LOAD_WH;

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
  BATCH_ID VARCHAR,
  INGESTED_AT TIMESTAMP_LTZ
);
```

Good file:

```text
customer_id,customer_name,region
1,Alice,EAST
2,Bob,WEST
3,"Carol, Jones",SOUTH
```

Bad file:

```text
customer_id,customer_name,region
4,David,EAST
ABC,Emma,WEST
6,Frank,SOUTH
```

Upload both from a PUT-capable client, then:

```sql
LIST @CUSTOMER_STAGE;

SELECT METADATA$FILENAME,METADATA$FILE_ROW_NUMBER,
       $1,$2,$3
FROM @CUSTOMER_STAGE
  (FILE_FORMAT => 'CUSTOMER_CSV_FORMAT');

SELECT METADATA$FILENAME,METADATA$FILE_ROW_NUMBER,$1
FROM @CUSTOMER_STAGE
  (FILE_FORMAT => 'CUSTOMER_CSV_FORMAT')
WHERE $1 IS NOT NULL
  AND TRY_TO_NUMBER($1) IS NULL;
```

Run COPY with `VALIDATION_MODE='RETURN_ERRORS'`, identify the bad file/row, load only the known-good file using controlled FILES selection, reconcile, correct the bad source, revalidate, load the corrected file, and check duplicates.

Wrong-delimiter experiment:

```sql
CREATE OR REPLACE FILE FORMAT WRONG_FORMAT
  TYPE=CSV FIELD_DELIMITER='|' SKIP_HEADER=1;

SELECT $1,$2,$3
FROM @CUSTOMER_STAGE
  (FILE_FORMAT => 'WRONG_FORMAT')
LIMIT 10;
```

This demonstrates why parser validation precedes target-table changes.

## 22. Incident note template
```text
Environment / Account / Region:
Database / Schema / Warehouse / Role:
Pipeline / Batch ID:
Stage / File Format / Target:
Expected Files / Actual Files:
Expected / Loaded / Rejected Rows:
Last Successful Load:
Error / Query ID:
LIST: PASS/FAIL
Stage Query: PASS/FAIL
File Format: VALID/INVALID
COPY Validation: PASS/FAIL
Load History: NEW/ALREADY LOADED/PARTIAL/FAILED
Root Cause:
Corrective Action:
Replay Required / Scope:
Post-Replay Reconciliation:
Duplicate Check:
Business Validation:
Preventive Action:
```

## 23. Cleanup
Only for disposable lab resources:

```sql
REMOVE @CUSTOMER_STAGE;
DROP TABLE IF EXISTS RAW_CUSTOMER;
DROP STAGE IF EXISTS CUSTOMER_STAGE;
DROP FILE FORMAT IF EXISTS CUSTOMER_CSV_FORMAT;
DROP FILE FORMAT IF EXISTS WRONG_FORMAT;
DROP WAREHOUSE IF EXISTS TUTORIAL_LOAD_WH;
```

## Production takeaways
1. Verify environment/context first.
2. LIST before COPY troubleshooting.
3. Missing file = investigate upstream.
4. LIST failure = stage/integration/IAM path first.
5. Query staged files before target changes.
6. Use metadata file/row columns for evidence.
7. Use TRY_TO_* validation and COPY validation mode.
8. FORCE is controlled replay, not a generic fix.
9. Reconcile expected/loaded/rejected/filtered counts.
10. Validate duplicates, freshness, completeness, distributions, and business rules.
11. Tune performance from evidence and baseline comparison.
12. Preserve lineage, quarantine bad records, and replay the smallest scope.
13. Do not publish a partially understood batch.

## Technical references
- https://docs.snowflake.com/en/sql-reference/sql/copy-into-table
- https://docs.snowflake.com/en/user-guide/data-load-bulk
- https://docs.snowflake.com/en/user-guide/querying-stage
- https://docs.snowflake.com/en/user-guide/querying-metadata
- https://docs.snowflake.com/en/sql-reference/functions/validate
- https://docs.snowflake.com/en/sql-reference/functions/copy_history
- https://docs.snowflake.com/en/sql-reference/functions/infer_schema
