# 11 — Stages — Internal & External

**Status:** CANONICAL  
**Part:** 3 — Data Loading & Unloading  
**Batch:** 11–15

## Goal
Understand Snowflake stages as the file-access boundary for bulk loading and unloading, including internal/user/table/named stages, external stages, storage integrations, security, lineage, operations, and troubleshooting.

## 1. Stage fundamentals
A stage identifies files that Snowflake can load or unload.

```text
Source files -> Stage -> File format -> COPY INTO -> Table
Table/query  -> COPY INTO <location> -> Stage -> Consumer
```

Named stages are schema objects. Internal stages store files in Snowflake-managed storage; external stages reference S3, Azure, or GCS.

## 2. Internal stage types
Snowflake supports user, table, and named internal stages.

```sql
LIST @~;                  -- current user's stage
LIST @%CUSTOMER;          -- CUSTOMER table stage
CREATE STAGE CUSTOMER_STAGE;
LIST @CUSTOMER_STAGE;     -- named internal stage
```

User stages are convenient for individual/ad-hoc work. Table stages are tied to a table. Named stages are usually clearer for shared production pipelines because they are explicit securable objects.

## 3. Named internal stage
```sql
CREATE OR REPLACE STAGE RAW_CUSTOMER_STAGE;
SHOW STAGES LIKE 'RAW_CUSTOMER_STAGE';
DESC STAGE RAW_CUSTOMER_STAGE;
LIST @RAW_CUSTOMER_STAGE;
```

Use path prefixes to separate domains or flows:

```sql
LIST @RAW_CUSTOMER_STAGE/inbound/;
LIST @RAW_CUSTOMER_STAGE/archive/;
```

Avoid recreating a production stage casually. CREATE OR REPLACE changes the underlying object identity and can break dependencies such as external tables.

## 4. PUT and REMOVE
Local files can be uploaded to internal stages from a client that supports PUT:

```sql
PUT file://C:/snowflake-lab/customer.csv
@RAW_CUSTOMER_STAGE
AUTO_COMPRESS=TRUE;
```

Verify before deletion:

```sql
LIST @RAW_CUSTOMER_STAGE;
REMOVE @RAW_CUSTOMER_STAGE/customer.csv.gz;
LIST @RAW_CUSTOMER_STAGE;
```

Do not run broad REMOVE operations until load status, replay requirements, and retention are known. Dropping an internal named stage purges its staged files; dropping an external stage does not delete objects in the external cloud location.

## 5. External stages
External stages reference cloud object storage.

```text
Snowflake -> External Stage -> Storage Integration -> Cloud IAM -> S3/Azure/GCS
```

Examples:

```sql
CREATE STAGE CUSTOMER_S3_STAGE
  URL='s3://company-data/customer/'
  STORAGE_INTEGRATION=CUSTOMER_S3_INT;

CREATE STAGE CUSTOMER_AZURE_STAGE
  URL='azure://account.blob.core.windows.net/container/customer/'
  STORAGE_INTEGRATION=CUSTOMER_AZURE_INT;

CREATE STAGE CUSTOMER_GCS_STAGE
  URL='gcs://company-data/customer/'
  STORAGE_INTEGRATION=CUSTOMER_GCS_INT;
```

For recurring protected-storage access, prefer storage integrations/cloud-native identity over long-lived credentials embedded in SQL.

## 6. Least privilege and path design
Restrict access to the narrowest practical bucket/container/prefix. Separate DEV, STAGING, and PROD locations and avoid one unrestricted stage for unrelated domains.

```text
customer/inbound/
customer/archive/
claims/inbound/
claims/archive/
```

Document owner, source system, storage location, consumer pipeline, classification, retention, and replay policy.

## 7. File formats on stages
A stage can reference a named file format:

```sql
CREATE FILE FORMAT CUSTOMER_CSV_FORMAT
  TYPE=CSV
  FIELD_DELIMITER=','
  SKIP_HEADER=1
  FIELD_OPTIONALLY_ENCLOSED_BY='"';

CREATE STAGE CUSTOMER_STAGE
  FILE_FORMAT=(FORMAT_NAME='CUSTOMER_CSV_FORMAT');
```

Named formats improve reuse and change control. File-format options can also be supplied directly by stage queries or COPY commands.

## 8. Query staged files before loading
```sql
SELECT
  METADATA$FILENAME,
  METADATA$FILE_ROW_NUMBER,
  $1,$2,$3
FROM @CUSTOMER_STAGE
  (FILE_FORMAT => 'CUSTOMER_CSV_FORMAT')
LIMIT 100;
```

For JSON:

```sql
SELECT
  METADATA$FILENAME,
  $1:patient_id::NUMBER AS patient_id,
  $1:name::VARCHAR AS patient_name
FROM @PATIENT_STAGE
  (FILE_FORMAT => 'PATIENT_JSON_FORMAT');
```

Stage queries isolate storage/parsing problems before COPY is involved.

## 9. Lineage
Persist source metadata when operational traceability matters:

```sql
CREATE TABLE RAW_CUSTOMER (
  CUSTOMER_ID VARCHAR,
  CUSTOMER_NAME VARCHAR,
  REGION VARCHAR,
  SOURCE_FILE VARCHAR,
  SOURCE_FILE_ROW_NUMBER NUMBER,
  INGESTED_AT TIMESTAMP_LTZ DEFAULT CURRENT_TIMESTAMP()
);
```

Source-file lineage answers which file/row produced a bad record and supports targeted replay.

## 10. RBAC
Named stages are securable objects. Use dedicated ingestion/operations roles, database/schema USAGE, warehouse USAGE where required, and only the stage privileges needed. Do not use ACCOUNTADMIN for routine ingestion.

## 11. Inventory and inspection
```sql
SHOW STAGES IN ACCOUNT;
DESC STAGE RAW_DB.INGESTION.CUSTOMER_STAGE;

SELECT GET_DDL(
  'STAGE',
  'RAW_DB.INGESTION.CUSTOMER_STAGE'
);
```

Use fully qualified stage names in production jobs to reduce dependence on session context.

## 12. External-stage troubleshooting
Use this sequence:

```text
Correct account/role?
 -> stage exists?
 -> DESC STAGE
 -> correct URL/prefix?
 -> DESC INTEGRATION
 -> allowed location?
 -> cloud IAM/trust?
 -> encryption-key access?
 -> network/storage policy?
 -> LIST works?
 -> staged file query works?
```

Useful context:

```sql
SELECT CURRENT_ACCOUNT_NAME(), CURRENT_REGION(), CURRENT_USER(),
       CURRENT_ROLE(), CURRENT_WAREHOUSE(),
       CURRENT_DATABASE(), CURRENT_SCHEMA();
```

If LIST fails, fix stage/storage access before debugging COPY.

## 13. File lifecycle and replay
Define what happens after successful ingestion:

```text
Inbound -> Load -> Validate -> Reconcile -> Archive/retain -> Delete after policy
```

A staged source can be a recovery asset. Do not delete it before reconciliation and the approved replay window.

## 14. Production architecture
```text
Source -> Cloud storage -> External stage -> COPY/Snowpipe
       -> RAW -> Validation -> STAGING -> CURATED
```

Separate transport from business transformation. RAW-first designs improve traceability and replayability.

## 15. Hands-on lab
```sql
CREATE DATABASE IF NOT EXISTS SNOWFLAKE_TUTORIAL;
CREATE SCHEMA IF NOT EXISTS SNOWFLAKE_TUTORIAL.STAGES;
USE DATABASE SNOWFLAKE_TUTORIAL;
USE SCHEMA STAGES;

CREATE OR REPLACE FILE FORMAT CUSTOMER_CSV_FORMAT
  TYPE=CSV
  FIELD_DELIMITER=','
  SKIP_HEADER=1
  FIELD_OPTIONALLY_ENCLOSED_BY='"'
  NULL_IF=('NULL','\\N');

CREATE OR REPLACE STAGE CUSTOMER_STAGE
  FILE_FORMAT=(FORMAT_NAME='CUSTOMER_CSV_FORMAT');

DESC STAGE CUSTOMER_STAGE;
LIST @CUSTOMER_STAGE;
LIST @~;
```

Create `C:\snowflake-lab\customer.csv`:

```text
customer_id,customer_name,region
1,Alice,EAST
2,Bob,WEST
3,Carol,SOUTH
```

Upload from a client supporting PUT:

```sql
PUT file://C:/snowflake-lab/customer.csv
@CUSTOMER_STAGE
AUTO_COMPRESS=TRUE;

LIST @CUSTOMER_STAGE;

SELECT METADATA$FILENAME, METADATA$FILE_ROW_NUMBER,
       $1,$2,$3
FROM @CUSTOMER_STAGE
  (FILE_FORMAT => 'CUSTOMER_CSV_FORMAT');
```

Validate numeric IDs:

```sql
SELECT $1, TRY_TO_NUMBER($1) AS CUSTOMER_ID
FROM @CUSTOMER_STAGE
  (FILE_FORMAT => 'CUSTOMER_CSV_FORMAT');
```

## 16. Cleanup
Only for the disposable lab:

```sql
REMOVE @CUSTOMER_STAGE;
DROP STAGE IF EXISTS CUSTOMER_STAGE;
DROP FILE FORMAT IF EXISTS CUSTOMER_CSV_FORMAT;
```

Never run broad REMOVE/DROP commands against shared production stages.

## 17. Production checklist
- Stage type, owner, source, and consumer documented.
- Storage integration/cloud identity used where appropriate.
- Cloud path and permissions follow least privilege.
- DEV/STAGING/PROD are isolated.
- File format and schema contract are documented.
- Source filename/row lineage captured where useful.
- File retention and replay policy defined.
- Stage access is monitored.
- Recovery procedure is tested.

## Production takeaways
1. A stage answers where files are; a file format answers how to parse them.
2. Prefer named stages for governed shared pipelines.
3. Prefer storage integrations to embedded long-lived credentials.
4. LIST is an early troubleshooting command.
5. Query staged files before changing target tables.
6. Preserve lineage and replayability.
7. Treat external stages as cloud-security boundaries.
8. Verify exact environment and role before incident changes.

## Technical references
- https://docs.snowflake.com/en/sql-reference/sql/create-stage
- https://docs.snowflake.com/en/sql-reference/sql/list
- https://docs.snowflake.com/en/sql-reference/sql/put
- https://docs.snowflake.com/en/user-guide/querying-stage
- https://docs.snowflake.com/en/user-guide/querying-metadata
