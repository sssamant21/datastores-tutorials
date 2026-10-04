# 12 — File Formats

**Status:** CANONICAL  
**Part:** 3 — Data Loading & Unloading  
**Batch:** 11–15

## Goal
Understand Snowflake file-format objects and production parsing for CSV, JSON, Parquet, Avro, ORC, and XML, including compression, NULL handling, schema evolution, validation, and troubleshooting.

## 1. File-format fundamentals
A stage answers where a file is. A file format tells Snowflake how to interpret it.

```text
File -> Stage -> File Format -> Parsed values -> COPY/query -> Table
```

Create a reusable named format:

```sql
CREATE FILE FORMAT CUSTOMER_CSV_FORMAT
  TYPE=CSV
  FIELD_DELIMITER=','
  SKIP_HEADER=1;
```

Inspect:

```sql
SHOW FILE FORMATS;
DESC FILE FORMAT CUSTOMER_CSV_FORMAT;
SELECT GET_DDL('FILE_FORMAT','DB.SCHEMA.CUSTOMER_CSV_FORMAT');
```

Named formats are preferred for recurring governed pipelines; inline options are useful for ad-hoc testing.

## 2. CSV
A production CSV contract can include delimiter, record delimiter, header handling, enclosure/quotes, NULL semantics, empty fields, whitespace, encoding, compression, and column-count behavior.

```sql
CREATE OR REPLACE FILE FORMAT CUSTOMER_CSV_FORMAT
  TYPE=CSV
  COMPRESSION=AUTO
  FIELD_DELIMITER=','
  SKIP_HEADER=1
  FIELD_OPTIONALLY_ENCLOSED_BY='"'
  NULL_IF=('NULL','\\N')
  EMPTY_FIELD_AS_NULL=TRUE
  ERROR_ON_COLUMN_COUNT_MISMATCH=TRUE;
```

Do not copy these options blindly; match the producer contract.

### Delimiters and quoting
Source:
```text
1001,"Charlotte, NC",ACTIVE
```

Correct quote handling keeps `Charlotte, NC` in one field. A wrong delimiter or enclosure setting often causes misleading downstream conversion errors.

### NULL versus empty string
`NULL`, `\N`, an empty field, and `""` are not automatically the same business value. Define the contract intentionally.

### Encoding and escaping
If names or special characters become corrupted, compare actual source encoding with the file-format encoding. Inspect escape behavior instead of guessing.

## 3. Compression
File format and compression are separate concepts:

```text
customer.csv.gz = CSV data + GZIP compression
events.json.gz  = JSON data + GZIP compression
```

`COMPRESSION=AUTO` is useful for supported formats, but source files still must be valid.

## 4. JSON
```sql
CREATE FILE FORMAT PATIENT_JSON_FORMAT TYPE=JSON;

SELECT
  METADATA$FILENAME,
  $1,
  TYPEOF($1),
  $1:patient_id::NUMBER,
  $1:name::VARCHAR
FROM @PATIENT_STAGE
  (FILE_FORMAT => 'PATIENT_JSON_FORMAT');
```

For an outer array of records, `STRIP_OUTER_ARRAY=TRUE` can be appropriate, but only when the array wrapper is not semantically required.

Inspect nested field types:

```sql
SELECT
  $1:addresses,
  TYPEOF($1:addresses)
FROM @PATIENT_STAGE
  (FILE_FORMAT => 'PATIENT_JSON_FORMAT');
```

Mixed ARRAY versus VARCHAR/stringified JSON should be treated as a source/schema consistency problem and normalized deliberately, e.g. with `TRY_PARSE_JSON` where appropriate.

## 5. Parquet
```sql
CREATE FILE FORMAT CUSTOMER_PARQUET_FORMAT TYPE=PARQUET;

SELECT $1
FROM @CUSTOMER_PARQUET_STAGE
  (FILE_FORMAT => 'CUSTOMER_PARQUET_FORMAT')
LIMIT 20;
```

Parquet is columnar and commonly used in data lakes. Validate representative files because producer/schema versions can differ.

## 6. Schema inference
For supported formats:

```sql
SELECT *
FROM TABLE(
  INFER_SCHEMA(
    LOCATION => '@CUSTOMER_PARQUET_STAGE',
    FILE_FORMAT => 'CUSTOMER_PARQUET_FORMAT'
  )
);
```

Inference is a discovery tool, not a replacement for a governed production schema contract.

## 7. Avro, ORC, XML
```sql
CREATE FILE FORMAT EVENT_AVRO_FORMAT TYPE=AVRO;
CREATE FILE FORMAT DATA_ORC_FORMAT TYPE=ORC;
CREATE FILE FORMAT CLAIM_XML_FORMAT TYPE=XML;
```

Use representative source files to validate nested structures, type consistency, and schema evolution.

## 8. Query staged data before COPY
```sql
SELECT
  METADATA$FILENAME,
  METADATA$FILE_ROW_NUMBER,
  $1,$2,$3
FROM @CUSTOMER_STAGE
  (FILE_FORMAT => 'CUSTOMER_CSV_FORMAT')
LIMIT 100;
```

Validate expected numbers:

```sql
SELECT METADATA$FILENAME, METADATA$FILE_ROW_NUMBER, $1
FROM @CUSTOMER_STAGE
  (FILE_FORMAT => 'CUSTOMER_CSV_FORMAT')
WHERE $1 IS NOT NULL
  AND TRY_TO_NUMBER($1) IS NULL;
```

Dates:

```sql
SELECT $4, TRY_TO_DATE($4)
FROM @CLAIMS_STAGE
  (FILE_FORMAT => 'CLAIMS_CSV_FORMAT');
```

Timestamps:

```sql
SELECT $5, TRY_TO_TIMESTAMP_NTZ($5), TRY_TO_TIMESTAMP_TZ($5)
FROM @EVENT_STAGE
  (FILE_FORMAT => 'EVENT_CSV_FORMAT');
```

## 9. Troubleshooting model
```text
Can LIST see the file?
 -> can Snowflake decompress it?
 -> can the file format parse it?
 -> do $1/$2/... align?
 -> can values be converted?
 -> does target mapping match?
```

Common symptoms:
- Numeric value contains the whole CSV row: delimiter likely wrong.
- Header text fails numeric conversion: SKIP_HEADER likely wrong.
- Extra column appears around a comma in text: enclosure/quote issue.
- Unicode corruption: encoding mismatch.
- Some Parquet files have missing/new fields: schema evolution.
- JSON field changes ARRAY/VARCHAR: producer inconsistency.

Do not change a target table merely to accommodate one malformed file.

## 10. Versioning and governance
If a producer contract changes, consider versioned formats such as `CUSTOMER_CSV_V1` and `CUSTOMER_CSV_V2`. Before changing a shared format:
1. Identify dependent stages/COPY/Snowpipe jobs.
2. Test old and new representative files.
3. Validate failure behavior.
4. Plan rollback.
5. Deploy and monitor.

Document source, delimiter, headers, quotes, NULL semantics, encoding, compression, expected columns/schema, owner, and dependent pipelines.

## 11. File organization
Avoid both pathological tiny-file counts and unnecessarily huge files. File size should balance parallelism, transfer efficiency, retry cost, producer capability, and operational manageability. Measure actual workloads instead of enforcing a universal size.

## 12. Hands-on lab
```sql
CREATE DATABASE IF NOT EXISTS SNOWFLAKE_TUTORIAL;
CREATE SCHEMA IF NOT EXISTS SNOWFLAKE_TUTORIAL.FILE_FORMATS;
USE DATABASE SNOWFLAKE_TUTORIAL;
USE SCHEMA FILE_FORMATS;

CREATE OR REPLACE FILE FORMAT CUSTOMER_CSV_FORMAT
  TYPE=CSV
  COMPRESSION=AUTO
  FIELD_DELIMITER=','
  SKIP_HEADER=1
  FIELD_OPTIONALLY_ENCLOSED_BY='"'
  NULL_IF=('NULL','\\N')
  EMPTY_FIELD_AS_NULL=TRUE
  ERROR_ON_COLUMN_COUNT_MISMATCH=TRUE;

CREATE OR REPLACE STAGE CUSTOMER_STAGE
  FILE_FORMAT=(FORMAT_NAME='CUSTOMER_CSV_FORMAT');
```

Test file:

```text
customer_id,customer_name,region,email
1,Alice,EAST,alice@example.com
2,"Bob Smith",WEST,bob@example.com
3,"Carol, Jones",SOUTH,NULL
4,David,EAST,
```

Upload and inspect:

```sql
PUT file://C:/snowflake-lab/customer.csv
@CUSTOMER_STAGE
AUTO_COMPRESS=TRUE;

LIST @CUSTOMER_STAGE;

SELECT METADATA$FILENAME, METADATA$FILE_ROW_NUMBER,
       $1,$2,$3,$4
FROM @CUSTOMER_STAGE
  (FILE_FORMAT => 'CUSTOMER_CSV_FORMAT');
```

Create an intentionally wrong format:

```sql
CREATE OR REPLACE FILE FORMAT WRONG_CSV_FORMAT
  TYPE=CSV
  FIELD_DELIMITER='|'
  SKIP_HEADER=1;

SELECT $1,$2,$3
FROM @CUSTOMER_STAGE
  (FILE_FORMAT => 'WRONG_CSV_FORMAT');
```

Compare the parsed output.

## 13. Cleanup
```sql
REMOVE @CUSTOMER_STAGE;
DROP STAGE IF EXISTS CUSTOMER_STAGE;
DROP FILE FORMAT IF EXISTS CUSTOMER_CSV_FORMAT;
DROP FILE FORMAT IF EXISTS WRONG_CSV_FORMAT;
```

Only run cleanup against disposable lab objects/files.

## Production checklist
- Format, compression, delimiter/header/quote behavior documented.
- NULL and empty-string semantics documented.
- Encoding documented.
- Expected schema/columns documented.
- Representative normal and malformed files tested.
- Old/new producer versions tested.
- Shared format dependencies identified.
- Change and rollback procedure defined.
- Source-file lineage retained where needed.

## Production takeaways
1. Stage = where; file format = how.
2. Named formats improve reuse/governance.
3. Query staged files before COPY.
4. Use metadata columns to pinpoint file/row failures.
5. Use TRY_TO_* validation to isolate bad values.
6. Treat schema drift as a governed producer change.
7. Do not weaken parsing merely to make malformed files succeed.

## Technical references
- https://docs.snowflake.com/en/sql-reference/sql/create-file-format
- https://docs.snowflake.com/en/user-guide/querying-stage
- https://docs.snowflake.com/en/user-guide/data-load-semistructured-intro
- https://docs.snowflake.com/en/sql-reference/functions/infer_schema
