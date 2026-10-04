# 14 — Data Unloading with COPY INTO <location>

**Status:** CANONICAL  
**Part:** 3 — Data Loading & Unloading  
**Batch:** 11–15

## Goal
Build production-safe outbound pipelines using `COPY INTO <location>`, including internal/external stages, explicit export contracts, file formats, compression, file sizing, partitioning, security, validation, reconciliation, and troubleshooting.

## 1. Unload flow
```text
Snowflake table/query -> COPY INTO <location> -> Stage -> S3/Azure/GCS or consumer
```

Loading uses `COPY INTO <table>`; unloading uses `COPY INTO <location>`.

## 2. Basic unload
```sql
CREATE OR REPLACE STAGE CUSTOMER_EXPORT_STAGE;

COPY INTO @CUSTOMER_EXPORT_STAGE
FROM CUSTOMER;

LIST @CUSTOMER_EXPORT_STAGE;
```

For production, export explicit columns:

```sql
COPY INTO @CUSTOMER_EXPORT_STAGE/customer/
FROM (
  SELECT CUSTOMER_ID, CUSTOMER_NAME, REGION
  FROM CUSTOMER
  WHERE STATUS='ACTIVE'
);
```

Avoid long-lived `SELECT *` external contracts.

## 3. External stage architecture
```text
Snowflake -> External Stage -> Storage Integration
          -> Cloud IAM -> S3/Azure/GCS -> Consumer
```

Prefer storage integrations/cloud-native identity to embedded long-lived credentials. Separate inbound and outbound locations/stages and grant only required read/write permissions.

## 4. File formats
CSV example:

```sql
CREATE OR REPLACE FILE FORMAT CUSTOMER_EXPORT_CSV_FORMAT
  TYPE=CSV
  FIELD_DELIMITER=','
  FIELD_OPTIONALLY_ENCLOSED_BY='"'
  COMPRESSION=GZIP
  NULL_IF=('NULL');

COPY INTO @CUSTOMER_EXPORT_STAGE/customer/
FROM (
  SELECT CUSTOMER_ID,CUSTOMER_NAME,REGION
  FROM CUSTOMER
)
FILE_FORMAT=(FORMAT_NAME='CUSTOMER_EXPORT_CSV_FORMAT')
HEADER=TRUE;
```

The consumer contract must define header, delimiter, quoting, NULL/empty-string semantics, encoding, compression, column order, and date/timestamp representation.

## 5. Parquet
```sql
COPY INTO @CUSTOMER_EXPORT_STAGE/parquet/
FROM (
  SELECT CUSTOMER_ID,CUSTOMER_NAME,REGION
  FROM CUSTOMER
)
FILE_FORMAT=(TYPE=PARQUET);
```

Parquet is often appropriate for analytical/data-lake consumers; CSV remains useful for simple text integrations.

## 6. Multiple files and SINGLE
Parallel multi-file output is normal and scalable. Use `SINGLE=TRUE` only when the consumer genuinely requires one file:

```sql
COPY INTO @CUSTOMER_EXPORT_STAGE/customer_single/customer.csv
FROM (
  SELECT CUSTOMER_ID,CUSTOMER_NAME,REGION
  FROM CUSTOMER
)
FILE_FORMAT=(TYPE=CSV FIELD_OPTIONALLY_ENCLOSED_BY='"')
HEADER=TRUE
SINGLE=TRUE;
```

Do not impose single-file output on large exports merely for convenience.

## 7. File size and overwrite
`MAX_FILE_SIZE` controls output sizing behavior. Choose values based on consumer parallelism, transfer/retry cost, and operational manageability.

Use overwrite behavior carefully. Prefer unique batch paths:

```text
customer/export_date=2026-10-04/batch_id=20261004_001/
```

instead of repeatedly overwriting a shared `current/` prefix.

## 8. Partitioning
Partitioned output can help downstream consumers:

```sql
COPY INTO @CLAIMS_EXPORT_STAGE/
FROM (
  SELECT CLAIM_ID,MEMBER_ID,SERVICE_DATE,CLAIM_AMOUNT
  FROM CLAIMS
)
PARTITION BY=('service_date=' || TO_VARCHAR(SERVICE_DATE))
FILE_FORMAT=(TYPE=PARQUET);
```

Never put sensitive values such as SSN, patient/member identifiers, names, or email addresses into object paths. Paths can appear in metadata/logging.

## 9. Security and minimization
An unload creates another copy of data. Verify:
- destination is approved,
- cloud encryption/access controls,
- retention/lifecycle,
- consumer authorization,
- masking/row policies where applicable,
- only required columns are exported.

A governed/secure view can be a useful outbound source boundary.

## 10. Validate before export
```sql
SELECT COUNT(*) AS EXPECTED_ROWS
FROM CUSTOMER
WHERE STATUS='ACTIVE';

SELECT CUSTOMER_ID,CUSTOMER_NAME,REGION
FROM CUSTOMER
WHERE STATUS='ACTIVE'
LIMIT 100;
```

Validate filters, duplicates, NULLs, time windows, date/timestamp representation, and sensitive columns before writing files.

## 11. Query tags and batch control
```sql
ALTER SESSION SET QUERY_TAG=
'pipeline=customer_export;env=prod;batch=20261004_001';
-- export
ALTER SESSION UNSET QUERY_TAG;
```

Track batch ID, dataset, destination path, expected/exported rows, file count, query ID, status, and timestamps in a control table for important interfaces.

## 12. Validate output
After COPY:

```sql
LIST @CUSTOMER_EXPORT_STAGE/customer/;
```

Read it back with a compatible file format:

```sql
CREATE OR REPLACE FILE FORMAT CUSTOMER_EXPORT_READ_FORMAT
  TYPE=CSV
  FIELD_DELIMITER=','
  FIELD_OPTIONALLY_ENCLOSED_BY='"'
  SKIP_HEADER=1
  COMPRESSION=AUTO
  NULL_IF=('NULL');

SELECT METADATA$FILENAME,$1,$2,$3
FROM @CUSTOMER_EXPORT_STAGE/customer/
  (FILE_FORMAT => 'CUSTOMER_EXPORT_READ_FORMAT');
```

Reconcile source rows with exported/read-back rows for critical deliveries.

## 13. Delivery completion
Do not notify consumers before export and validation finish.

```text
Export -> LIST/read-back -> reconcile -> mark complete
       -> publish manifest/completion marker -> consumer reads
```

A manifest can contain batch ID, dataset/schema version, row count, file count, file list, and export timestamp.

## 14. Retention and reproducibility
Document retention, archive, legal requirements, consumer SLA, replay window, and deletion process. Capture query/query ID, batch ID, source time window/snapshot, file-format version, destination, and expected count. Rerunning SQL later may not reproduce the same data if the source changed.

## 15. Troubleshooting
**Stage not authorized:** verify current role/context, SHOW/DESC STAGE, privileges.

**External write denied:** inspect storage integration, cloud IAM write permissions, allowed location, encryption key, and storage/network policy.

**No output files:** confirm source query returns rows, exact stage/path, account/environment, and LIST the destination.

**Wrong row count:** investigate filters, joins, DISTINCT, NULL predicates, time windows, row policies, and source changes.

**Duplicate rows:** test the export query by business key; do not hide a broken join with DISTINCT.

**Consumer cannot parse CSV:** verify delimiter, quotes, headers, NULL representation, encoding, compression, and embedded line breaks.

**Slow export:** separate source-query time from serialization/compression/storage write; inspect queueing, scans, joins, sorts, SINGLE, volume, and warehouse behavior before resizing.

## 16. Workload isolation
Large exports can use a dedicated warehouse:

```sql
CREATE WAREHOUSE IF NOT EXISTS EXPORT_WH
  WAREHOUSE_SIZE='SMALL'
  AUTO_SUSPEND=60
  AUTO_RESUME=TRUE
  INITIALLY_SUSPENDED=TRUE;
```

Choose size from measured workload. Include compute, storage, retention, and cross-region/cloud transfer considerations in FinOps review.

## 17. Hands-on lab
```sql
CREATE DATABASE IF NOT EXISTS SNOWFLAKE_TUTORIAL;
CREATE SCHEMA IF NOT EXISTS SNOWFLAKE_TUTORIAL.UNLOAD_LAB;
USE DATABASE SNOWFLAKE_TUTORIAL;
USE SCHEMA UNLOAD_LAB;

CREATE WAREHOUSE IF NOT EXISTS TUTORIAL_EXPORT_WH
  WAREHOUSE_SIZE='XSMALL'
  AUTO_SUSPEND=60 AUTO_RESUME=TRUE
  INITIALLY_SUSPENDED=TRUE;
USE WAREHOUSE TUTORIAL_EXPORT_WH;

CREATE OR REPLACE TABLE CUSTOMER (
  CUSTOMER_ID NUMBER,
  CUSTOMER_NAME VARCHAR,
  REGION VARCHAR,
  STATUS VARCHAR
);

INSERT INTO CUSTOMER VALUES
(1,'Alice','EAST','ACTIVE'),
(2,'Bob','WEST','ACTIVE'),
(3,'Carol, Jones','SOUTH','ACTIVE'),
(4,'David','EAST','INACTIVE'),
(5,NULL,'WEST','ACTIVE');

CREATE OR REPLACE FILE FORMAT CUSTOMER_EXPORT_CSV_FORMAT
  TYPE=CSV
  FIELD_DELIMITER=','
  FIELD_OPTIONALLY_ENCLOSED_BY='"'
  COMPRESSION=GZIP
  NULL_IF=('NULL');

CREATE OR REPLACE STAGE CUSTOMER_EXPORT_STAGE
  FILE_FORMAT=(FORMAT_NAME='CUSTOMER_EXPORT_CSV_FORMAT');
```

Validate and export:

```sql
SELECT COUNT(*) FROM CUSTOMER WHERE STATUS='ACTIVE';

COPY INTO @CUSTOMER_EXPORT_STAGE/customer/
FROM (
  SELECT CUSTOMER_ID,CUSTOMER_NAME,REGION
  FROM CUSTOMER
  WHERE STATUS='ACTIVE'
)
FILE_FORMAT=(FORMAT_NAME='CUSTOMER_EXPORT_CSV_FORMAT')
HEADER=TRUE;

LIST @CUSTOMER_EXPORT_STAGE/customer/;
```

Create a read-back format and validate the exported rows, including `Carol, Jones` and NULL behavior.

Optional Parquet experiment:

```sql
COPY INTO @CUSTOMER_EXPORT_STAGE/customer_parquet/
FROM (
  SELECT CUSTOMER_ID,CUSTOMER_NAME,REGION
  FROM CUSTOMER
  WHERE STATUS='ACTIVE'
)
FILE_FORMAT=(TYPE=PARQUET);

LIST @CUSTOMER_EXPORT_STAGE/customer_parquet/;
```

## 18. Cleanup
Only for disposable lab objects:

```sql
REMOVE @CUSTOMER_EXPORT_STAGE;
DROP STAGE IF EXISTS CUSTOMER_EXPORT_STAGE;
DROP FILE FORMAT IF EXISTS CUSTOMER_EXPORT_CSV_FORMAT;
DROP FILE FORMAT IF EXISTS CUSTOMER_EXPORT_READ_FORMAT;
DROP TABLE IF EXISTS CUSTOMER;
DROP WAREHOUSE IF EXISTS TUTORIAL_EXPORT_WH;
```

## Production takeaways
1. Treat exports as external data contracts.
2. Validate the source query before COPY.
3. Use explicit columns and data minimization.
4. Multi-file output is normal; justify SINGLE.
5. Use unique batch paths rather than unsafe overwrite.
6. Never expose sensitive values in partition paths.
7. LIST and read output back for critical pipelines.
8. Reconcile before consumer notification.
9. Define retention and replay.
10. Treat outbound movement as a security/governance boundary.

## Technical references
- https://docs.snowflake.com/en/sql-reference/sql/copy-into-location
- https://docs.snowflake.com/en/user-guide/data-unload-overview
- https://docs.snowflake.com/en/user-guide/data-unload-snowflake
- https://docs.snowflake.com/en/sql-reference/sql/create-file-format
- https://docs.snowflake.com/en/sql-reference/sql/list
