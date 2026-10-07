# Chapter 88 — Snowflake Data Quality & Validation Project

## 1. Project Goal

This chapter builds a production-oriented data quality and validation framework in Snowflake.

The framework validates data after ingestion or CDC processing and provides a repeatable way to detect, record, investigate, and remediate bad data before downstream consumers are affected.

By the end of this project, you will have a framework that can validate:

- row completeness
- required columns
- uniqueness
- duplicate records
- accepted values
- numeric and date ranges
- referential integrity
- data freshness
- source-to-target row counts
- source-to-target aggregates
- CDC reconciliation
- schema expectations

The project also introduces configurable rules, execution history, failed-record quarantine, operational monitoring, and acceptance testing.

---

## 2. Architecture

```text
Source / Landing Data
        |
        v
+---------------------+
| RAW / STAGING       |
+---------------------+
        |
        | ingestion / CDC
        v
+---------------------+
| CURATED TARGET      |
+---------------------+
        |
        v
+-----------------------------+
| DATA QUALITY FRAMEWORK      |
|                             |
| Rule Configuration          |
| Validation Procedures       |
| Reconciliation              |
| Freshness Checks            |
| Failure Logging             |
| Quarantine                  |
+-----------------------------+
        |
        +------------------+
        |                  |
        v                  v
+---------------+   +----------------+
| DQ RESULTS    |   | QUARANTINE     |
+---------------+   +----------------+
        |
        v
Monitoring / Alerting / Investigation
```

The important design principle is that validation results are treated as operational data themselves.

A failed check should leave enough evidence to answer:

1. What failed?
2. When did it fail?
3. Which object was affected?
4. What rule was violated?
5. How many records were affected?
6. What was expected?
7. What was actually observed?
8. Can the affected records be identified?
9. Can the validation safely be rerun?

---

## 3. Create the Project Environment

Use a dedicated training database and schemas.

```sql
USE ROLE SYSADMIN;

CREATE DATABASE IF NOT EXISTS SNOWFLAKE_DQ_PROJECT;

CREATE SCHEMA IF NOT EXISTS SNOWFLAKE_DQ_PROJECT.RAW;
CREATE SCHEMA IF NOT EXISTS SNOWFLAKE_DQ_PROJECT.CURATED;
CREATE SCHEMA IF NOT EXISTS SNOWFLAKE_DQ_PROJECT.DQ;
CREATE SCHEMA IF NOT EXISTS SNOWFLAKE_DQ_PROJECT.QUARANTINE;
```

Create or select a warehouse.

```sql
CREATE WAREHOUSE IF NOT EXISTS DQ_PROJECT_WH
    WAREHOUSE_SIZE = 'XSMALL'
    AUTO_SUSPEND = 60
    AUTO_RESUME = TRUE
    INITIALLY_SUSPENDED = TRUE;

USE WAREHOUSE DQ_PROJECT_WH;
USE DATABASE SNOWFLAKE_DQ_PROJECT;
```

---

## 4. Create the Source Dataset

Create a sample customer landing table.

```sql
CREATE OR REPLACE TABLE RAW.CUSTOMER_EVENTS (
    EVENT_ID       NUMBER,
    CUSTOMER_ID    NUMBER,
    EMAIL          VARCHAR,
    COUNTRY_CODE   VARCHAR,
    STATUS         VARCHAR,
    CREDIT_LIMIT   NUMBER(12,2),
    UPDATED_AT     TIMESTAMP_NTZ,
    INGESTED_AT    TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP()
);
```

Insert mostly valid data plus several intentional quality problems.

```sql
INSERT INTO RAW.CUSTOMER_EVENTS
    (EVENT_ID, CUSTOMER_ID, EMAIL, COUNTRY_CODE, STATUS,
     CREDIT_LIMIT, UPDATED_AT)
VALUES
    (1, 1001, 'alice@example.com', 'US', 'ACTIVE',   5000, DATEADD('minute', -5, CURRENT_TIMESTAMP())),
    (2, 1002, 'bob@example.com',   'US', 'ACTIVE',   2500, DATEADD('minute', -4, CURRENT_TIMESTAMP())),
    (3, 1003, NULL,                'CA', 'ACTIVE',   4000, DATEADD('minute', -3, CURRENT_TIMESTAMP())),
    (4, 1004, 'dave@example.com',  'XX', 'ACTIVE',   3000, DATEADD('minute', -2, CURRENT_TIMESTAMP())),
    (5, 1005, 'eve@example.com',   'US', 'UNKNOWN',  1500, DATEADD('minute', -1, CURRENT_TIMESTAMP())),
    (6, 1006, 'frank@example.com', 'US', 'ACTIVE',   -500, CURRENT_TIMESTAMP()),
    (7, 1002, 'bob2@example.com',  'US', 'ACTIVE',   2700, CURRENT_TIMESTAMP());
```

The intentional defects are:

- customer `1003` has no email
- customer `1004` has an unsupported country code
- customer `1005` has an unsupported status
- customer `1006` has a negative credit limit
- customer `1002` appears more than once

---

## 5. Create the Curated Target

```sql
CREATE OR REPLACE TABLE CURATED.CUSTOMERS (
    CUSTOMER_ID    NUMBER,
    EMAIL          VARCHAR,
    COUNTRY_CODE   VARCHAR,
    STATUS         VARCHAR,
    CREDIT_LIMIT   NUMBER(12,2),
    UPDATED_AT     TIMESTAMP_NTZ,
    LOAD_TS        TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP()
);
```

Load a sample target dataset.

```sql
INSERT INTO CURATED.CUSTOMERS
    (CUSTOMER_ID, EMAIL, COUNTRY_CODE, STATUS, CREDIT_LIMIT, UPDATED_AT)
SELECT
    CUSTOMER_ID,
    EMAIL,
    COUNTRY_CODE,
    STATUS,
    CREDIT_LIMIT,
    UPDATED_AT
FROM RAW.CUSTOMER_EVENTS
QUALIFY ROW_NUMBER() OVER (
    PARTITION BY CUSTOMER_ID
    ORDER BY UPDATED_AT DESC, EVENT_ID DESC
) = 1;
```

This target intentionally contains the bad source values so the validation framework can detect them.

---

# Part I — Data Quality Metadata

## 6. Create the Rule Configuration Table

A production framework should avoid hard-coding every rule into one monolithic procedure.

Create a metadata table describing the validations.

```sql
CREATE OR REPLACE TABLE DQ.RULE_CONFIG (
    RULE_ID             NUMBER AUTOINCREMENT,
    RULE_NAME           VARCHAR,
    DATABASE_NAME       VARCHAR,
    SCHEMA_NAME         VARCHAR,
    TABLE_NAME          VARCHAR,
    COLUMN_NAME         VARCHAR,
    RULE_TYPE           VARCHAR,
    EXPECTED_VALUE      VARCHAR,
    SEVERITY            VARCHAR,
    IS_ACTIVE           BOOLEAN DEFAULT TRUE,
    CREATED_AT          TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP(),
    UPDATED_AT          TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP()
);
```

Example rule types include:

```text
NOT_NULL
UNIQUE
ACCEPTED_VALUES
MIN_VALUE
MAX_VALUE
FRESHNESS
ROW_COUNT
REFERENTIAL_INTEGRITY
CUSTOM_SQL
```

Insert representative rules.

```sql
INSERT INTO DQ.RULE_CONFIG
    (RULE_NAME, DATABASE_NAME, SCHEMA_NAME, TABLE_NAME,
     COLUMN_NAME, RULE_TYPE, EXPECTED_VALUE, SEVERITY)
VALUES
    ('customer_id_not_null',
     'SNOWFLAKE_DQ_PROJECT', 'CURATED', 'CUSTOMERS',
     'CUSTOMER_ID', 'NOT_NULL', NULL, 'CRITICAL'),

    ('customer_id_unique',
     'SNOWFLAKE_DQ_PROJECT', 'CURATED', 'CUSTOMERS',
     'CUSTOMER_ID', 'UNIQUE', NULL, 'CRITICAL'),

    ('email_not_null',
     'SNOWFLAKE_DQ_PROJECT', 'CURATED', 'CUSTOMERS',
     'EMAIL', 'NOT_NULL', NULL, 'HIGH'),

    ('valid_status',
     'SNOWFLAKE_DQ_PROJECT', 'CURATED', 'CUSTOMERS',
     'STATUS', 'ACCEPTED_VALUES', 'ACTIVE,INACTIVE,SUSPENDED', 'HIGH'),

    ('credit_limit_non_negative',
     'SNOWFLAKE_DQ_PROJECT', 'CURATED', 'CUSTOMERS',
     'CREDIT_LIMIT', 'MIN_VALUE', '0', 'HIGH');
```

Review the configuration.

```sql
SELECT *
FROM DQ.RULE_CONFIG
ORDER BY RULE_ID;
```

---

## 7. Create the Validation Run Table

Each execution should have a unique run identifier.

```sql
CREATE OR REPLACE TABLE DQ.VALIDATION_RUNS (
    RUN_ID          VARCHAR,
    PIPELINE_NAME   VARCHAR,
    STARTED_AT      TIMESTAMP_NTZ,
    COMPLETED_AT    TIMESTAMP_NTZ,
    STATUS          VARCHAR,
    TOTAL_CHECKS    NUMBER,
    PASSED_CHECKS   NUMBER,
    FAILED_CHECKS   NUMBER,
    ERROR_MESSAGE   VARCHAR
);
```

Possible statuses:

```text
RUNNING
PASSED
FAILED
ERROR
```

---

## 8. Create the Validation Result Table

```sql
CREATE OR REPLACE TABLE DQ.VALIDATION_RESULTS (
    RUN_ID              VARCHAR,
    RULE_NAME           VARCHAR,
    DATABASE_NAME       VARCHAR,
    SCHEMA_NAME         VARCHAR,
    TABLE_NAME          VARCHAR,
    COLUMN_NAME         VARCHAR,
    RULE_TYPE           VARCHAR,
    SEVERITY            VARCHAR,
    STATUS              VARCHAR,
    EXPECTED_VALUE      VARCHAR,
    ACTUAL_VALUE        VARCHAR,
    FAILED_ROW_COUNT    NUMBER,
    CHECKED_AT          TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP(),
    DETAILS             VARCHAR
);
```

This becomes the primary operational history for data quality checks.

---

# Part II — Core Validation Patterns

## 9. Required-Column Validation

Check whether required values are missing.

```sql
SELECT COUNT(*) AS FAILED_ROWS
FROM CURATED.CUSTOMERS
WHERE EMAIL IS NULL;
```

Expected result for the sample dataset:

```text
1
```

Record the failure.

```sql
INSERT INTO DQ.VALIDATION_RESULTS
(
    RUN_ID,
    RULE_NAME,
    DATABASE_NAME,
    SCHEMA_NAME,
    TABLE_NAME,
    COLUMN_NAME,
    RULE_TYPE,
    SEVERITY,
    STATUS,
    EXPECTED_VALUE,
    ACTUAL_VALUE,
    FAILED_ROW_COUNT,
    DETAILS
)
SELECT
    UUID_STRING(),
    'email_not_null',
    'SNOWFLAKE_DQ_PROJECT',
    'CURATED',
    'CUSTOMERS',
    'EMAIL',
    'NOT_NULL',
    'HIGH',
    IFF(COUNT(*) = 0, 'PASS', 'FAIL'),
    '0 null rows',
    COUNT(*) || ' null rows',
    COUNT(*),
    'EMAIL must be populated'
FROM CURATED.CUSTOMERS
WHERE EMAIL IS NULL;
```

---

## 10. Uniqueness Validation

A simple duplicate check is:

```sql
SELECT
    CUSTOMER_ID,
    COUNT(*) AS RECORD_COUNT
FROM CURATED.CUSTOMERS
GROUP BY CUSTOMER_ID
HAVING COUNT(*) > 1;
```

For large datasets, count duplicate rows:

```sql
SELECT COALESCE(SUM(RECORD_COUNT - 1), 0) AS DUPLICATE_ROWS
FROM (
    SELECT CUSTOMER_ID, COUNT(*) AS RECORD_COUNT
    FROM CURATED.CUSTOMERS
    GROUP BY CUSTOMER_ID
    HAVING COUNT(*) > 1
);
```

Do not assume a declared Snowflake primary key automatically guarantees uniqueness. Validate business-key uniqueness explicitly when correctness depends on it.

---

## 11. Accepted-Value Validation

Validate status values.

```sql
SELECT *
FROM CURATED.CUSTOMERS
WHERE STATUS NOT IN ('ACTIVE', 'INACTIVE', 'SUSPENDED')
   OR STATUS IS NULL;
```

Count failures.

```sql
SELECT COUNT(*) AS FAILED_ROWS
FROM CURATED.CUSTOMERS
WHERE STATUS NOT IN ('ACTIVE', 'INACTIVE', 'SUSPENDED')
   OR STATUS IS NULL;
```

---

## 12. Range Validation

Validate that credit limits cannot be negative.

```sql
SELECT *
FROM CURATED.CUSTOMERS
WHERE CREDIT_LIMIT < 0;
```

A more general numeric validation can test both boundaries.

```sql
SELECT *
FROM CURATED.CUSTOMERS
WHERE CREDIT_LIMIT < 0
   OR CREDIT_LIMIT > 1000000;
```

---

## 13. Reference Data Validation

Create a valid-country reference table.

```sql
CREATE OR REPLACE TABLE CURATED.COUNTRY_REFERENCE (
    COUNTRY_CODE VARCHAR,
    COUNTRY_NAME VARCHAR
);

INSERT INTO CURATED.COUNTRY_REFERENCE VALUES
    ('US', 'United States'),
    ('CA', 'Canada'),
    ('GB', 'United Kingdom'),
    ('AU', 'Australia');
```

Identify invalid references.

```sql
SELECT c.*
FROM CURATED.CUSTOMERS c
LEFT JOIN CURATED.COUNTRY_REFERENCE r
    ON c.COUNTRY_CODE = r.COUNTRY_CODE
WHERE r.COUNTRY_CODE IS NULL;
```

This detects customer `1004` with country code `XX`.

---

## 14. Freshness Validation

Freshness checks determine whether a pipeline is continuing to deliver current data.

```sql
SELECT
    MAX(UPDATED_AT) AS LATEST_RECORD,
    DATEDIFF('minute', MAX(UPDATED_AT), CURRENT_TIMESTAMP()) AS AGE_MINUTES
FROM CURATED.CUSTOMERS;
```

Example SLA:

```text
The newest customer record must be less than 30 minutes old.
```

Validation query:

```sql
SELECT
    IFF(
        DATEDIFF('minute', MAX(UPDATED_AT), CURRENT_TIMESTAMP()) <= 30,
        'PASS',
        'FAIL'
    ) AS STATUS
FROM CURATED.CUSTOMERS;
```

Freshness is especially important for CDC pipelines because a pipeline can technically succeed while processing no new data due to an upstream failure.

---

# Part III — Source-to-Target Reconciliation

## 15. Row Count Reconciliation

For append-only pipelines, source and target counts may sometimes be directly comparable.

For CDC pipelines, raw event count and target row count usually are not equivalent because multiple events can represent the same business key.

Instead compare the expected current-state population.

```sql
WITH EXPECTED AS (
    SELECT CUSTOMER_ID
    FROM RAW.CUSTOMER_EVENTS
    QUALIFY ROW_NUMBER() OVER (
        PARTITION BY CUSTOMER_ID
        ORDER BY UPDATED_AT DESC, EVENT_ID DESC
    ) = 1
)
SELECT
    (SELECT COUNT(*) FROM EXPECTED) AS EXPECTED_ROWS,
    (SELECT COUNT(*) FROM CURATED.CUSTOMERS) AS ACTUAL_ROWS;
```

Calculate the difference.

```sql
WITH EXPECTED AS (
    SELECT CUSTOMER_ID
    FROM RAW.CUSTOMER_EVENTS
    QUALIFY ROW_NUMBER() OVER (
        PARTITION BY CUSTOMER_ID
        ORDER BY UPDATED_AT DESC, EVENT_ID DESC
    ) = 1
)
SELECT
    (SELECT COUNT(*) FROM EXPECTED)
      -
    (SELECT COUNT(*) FROM CURATED.CUSTOMERS)
        AS ROW_COUNT_DIFFERENCE;
```

Expected:

```text
0
```

---

## 16. Missing-Key Reconciliation

Find records expected from the source but missing from the target.

```sql
WITH EXPECTED AS (
    SELECT CUSTOMER_ID
    FROM RAW.CUSTOMER_EVENTS
    QUALIFY ROW_NUMBER() OVER (
        PARTITION BY CUSTOMER_ID
        ORDER BY UPDATED_AT DESC, EVENT_ID DESC
    ) = 1
)
SELECT e.CUSTOMER_ID
FROM EXPECTED e
LEFT JOIN CURATED.CUSTOMERS t
    ON e.CUSTOMER_ID = t.CUSTOMER_ID
WHERE t.CUSTOMER_ID IS NULL;
```

Find unexpected target records.

```sql
WITH EXPECTED AS (
    SELECT CUSTOMER_ID
    FROM RAW.CUSTOMER_EVENTS
    QUALIFY ROW_NUMBER() OVER (
        PARTITION BY CUSTOMER_ID
        ORDER BY UPDATED_AT DESC, EVENT_ID DESC
    ) = 1
)
SELECT t.CUSTOMER_ID
FROM CURATED.CUSTOMERS t
LEFT JOIN EXPECTED e
    ON t.CUSTOMER_ID = e.CUSTOMER_ID
WHERE e.CUSTOMER_ID IS NULL;
```

---

## 17. Aggregate Reconciliation

Row counts alone do not prove data correctness.

Compare business aggregates as well.

```sql
WITH EXPECTED AS (
    SELECT
        CUSTOMER_ID,
        CREDIT_LIMIT
    FROM RAW.CUSTOMER_EVENTS
    QUALIFY ROW_NUMBER() OVER (
        PARTITION BY CUSTOMER_ID
        ORDER BY UPDATED_AT DESC, EVENT_ID DESC
    ) = 1
)
SELECT
    (SELECT SUM(CREDIT_LIMIT) FROM EXPECTED) AS SOURCE_TOTAL,
    (SELECT SUM(CREDIT_LIMIT) FROM CURATED.CUSTOMERS) AS TARGET_TOTAL;
```

Other useful reconciliation dimensions include:

- record count
- distinct business keys
- monetary totals
- min/max timestamps
- status counts
- counts by date
- counts by region
- counts by tenant/customer

---

## 18. Hash-Based Reconciliation

For selected deterministic columns, create a row-level comparison hash.

```sql
WITH SOURCE_CURRENT AS (
    SELECT
        CUSTOMER_ID,
        EMAIL,
        COUNTRY_CODE,
        STATUS,
        CREDIT_LIMIT,
        UPDATED_AT
    FROM RAW.CUSTOMER_EVENTS
    QUALIFY ROW_NUMBER() OVER (
        PARTITION BY CUSTOMER_ID
        ORDER BY UPDATED_AT DESC, EVENT_ID DESC
    ) = 1
),
SOURCE_HASH AS (
    SELECT
        CUSTOMER_ID,
        HASH(
            CUSTOMER_ID,
            EMAIL,
            COUNTRY_CODE,
            STATUS,
            CREDIT_LIMIT,
            UPDATED_AT
        ) AS ROW_HASH
    FROM SOURCE_CURRENT
),
TARGET_HASH AS (
    SELECT
        CUSTOMER_ID,
        HASH(
            CUSTOMER_ID,
            EMAIL,
            COUNTRY_CODE,
            STATUS,
            CREDIT_LIMIT,
            UPDATED_AT
        ) AS ROW_HASH
    FROM CURATED.CUSTOMERS
)
SELECT
    COALESCE(s.CUSTOMER_ID, t.CUSTOMER_ID) AS CUSTOMER_ID,
    s.ROW_HASH AS SOURCE_HASH,
    t.ROW_HASH AS TARGET_HASH
FROM SOURCE_HASH s
FULL OUTER JOIN TARGET_HASH t
    ON s.CUSTOMER_ID = t.CUSTOMER_ID
WHERE s.ROW_HASH IS DISTINCT FROM t.ROW_HASH;
```

Hash comparison is useful when many columns need to be compared efficiently, but the selected columns and normalization rules must remain consistent on both sides.

---

# Part IV — Quarantine Pattern

## 19. Create a Quarantine Table

Invalid records should not disappear silently.

```sql
CREATE OR REPLACE TABLE QUARANTINE.CUSTOMER_FAILURES (
    RUN_ID          VARCHAR,
    CUSTOMER_ID     NUMBER,
    EMAIL           VARCHAR,
    COUNTRY_CODE    VARCHAR,
    STATUS          VARCHAR,
    CREDIT_LIMIT    NUMBER(12,2),
    UPDATED_AT      TIMESTAMP_NTZ,
    RULE_NAME       VARCHAR,
    FAILURE_REASON  VARCHAR,
    QUARANTINED_AT  TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP()
);
```

Quarantine invalid credit limits.

```sql
INSERT INTO QUARANTINE.CUSTOMER_FAILURES
(
    RUN_ID,
    CUSTOMER_ID,
    EMAIL,
    COUNTRY_CODE,
    STATUS,
    CREDIT_LIMIT,
    UPDATED_AT,
    RULE_NAME,
    FAILURE_REASON
)
SELECT
    UUID_STRING(),
    CUSTOMER_ID,
    EMAIL,
    COUNTRY_CODE,
    STATUS,
    CREDIT_LIMIT,
    UPDATED_AT,
    'credit_limit_non_negative',
    'CREDIT_LIMIT is below zero'
FROM CURATED.CUSTOMERS
WHERE CREDIT_LIMIT < 0;
```

Review quarantined records.

```sql
SELECT *
FROM QUARANTINE.CUSTOMER_FAILURES
ORDER BY QUARANTINED_AT DESC;
```

### Quarantine Design Rule

Do not automatically delete questionable production data merely because a quality rule fails.

The response depends on the rule and workload.

Possible actions include:

```text
WARN
QUARANTINE
BLOCK_BATCH
BLOCK_PUBLISH
CONTINUE_WITH_ALERT
```

A critical business-key failure may justify stopping publication, while a low-severity optional-field failure may only generate an alert.

---

# Part V — Reusable Validation Procedure

## 20. Create a Simple Validation Procedure

The following SQL procedure demonstrates how multiple checks can be executed under one run identifier.

```sql
CREATE OR REPLACE PROCEDURE DQ.RUN_CUSTOMER_VALIDATION()
RETURNS VARCHAR
LANGUAGE SQL
EXECUTE AS OWNER
AS
$$
DECLARE
    V_RUN_ID VARCHAR DEFAULT UUID_STRING();
    V_FAILED NUMBER DEFAULT 0;
BEGIN

    INSERT INTO DQ.VALIDATION_RUNS
    (
        RUN_ID,
        PIPELINE_NAME,
        STARTED_AT,
        STATUS
    )
    VALUES
    (
        :V_RUN_ID,
        'CUSTOMER_PIPELINE',
        CURRENT_TIMESTAMP(),
        'RUNNING'
    );

    INSERT INTO DQ.VALIDATION_RESULTS
    (
        RUN_ID,
        RULE_NAME,
        DATABASE_NAME,
        SCHEMA_NAME,
        TABLE_NAME,
        COLUMN_NAME,
        RULE_TYPE,
        SEVERITY,
        STATUS,
        EXPECTED_VALUE,
        ACTUAL_VALUE,
        FAILED_ROW_COUNT,
        DETAILS
    )
    SELECT
        :V_RUN_ID,
        'email_not_null',
        'SNOWFLAKE_DQ_PROJECT',
        'CURATED',
        'CUSTOMERS',
        'EMAIL',
        'NOT_NULL',
        'HIGH',
        IFF(COUNT(*) = 0, 'PASS', 'FAIL'),
        '0',
        COUNT(*)::VARCHAR,
        COUNT(*),
        'EMAIL must not be NULL'
    FROM CURATED.CUSTOMERS
    WHERE EMAIL IS NULL;

    INSERT INTO DQ.VALIDATION_RESULTS
    (
        RUN_ID,
        RULE_NAME,
        DATABASE_NAME,
        SCHEMA_NAME,
        TABLE_NAME,
        COLUMN_NAME,
        RULE_TYPE,
        SEVERITY,
        STATUS,
        EXPECTED_VALUE,
        ACTUAL_VALUE,
        FAILED_ROW_COUNT,
        DETAILS
    )
    SELECT
        :V_RUN_ID,
        'valid_status',
        'SNOWFLAKE_DQ_PROJECT',
        'CURATED',
        'CUSTOMERS',
        'STATUS',
        'ACCEPTED_VALUES',
        'HIGH',
        IFF(COUNT(*) = 0, 'PASS', 'FAIL'),
        'ACTIVE,INACTIVE,SUSPENDED',
        COUNT(*)::VARCHAR || ' invalid rows',
        COUNT(*),
        'Unexpected STATUS value detected'
    FROM CURATED.CUSTOMERS
    WHERE STATUS NOT IN ('ACTIVE', 'INACTIVE', 'SUSPENDED')
       OR STATUS IS NULL;

    INSERT INTO DQ.VALIDATION_RESULTS
    (
        RUN_ID,
        RULE_NAME,
        DATABASE_NAME,
        SCHEMA_NAME,
        TABLE_NAME,
        COLUMN_NAME,
        RULE_TYPE,
        SEVERITY,
        STATUS,
        EXPECTED_VALUE,
        ACTUAL_VALUE,
        FAILED_ROW_COUNT,
        DETAILS
    )
    SELECT
        :V_RUN_ID,
        'credit_limit_non_negative',
        'SNOWFLAKE_DQ_PROJECT',
        'CURATED',
        'CUSTOMERS',
        'CREDIT_LIMIT',
        'MIN_VALUE',
        'HIGH',
        IFF(COUNT(*) = 0, 'PASS', 'FAIL'),
        '>= 0',
        COUNT(*)::VARCHAR || ' invalid rows',
        COUNT(*),
        'Negative credit limit detected'
    FROM CURATED.CUSTOMERS
    WHERE CREDIT_LIMIT < 0;

    SELECT COUNT(*)
      INTO :V_FAILED
    FROM DQ.VALIDATION_RESULTS
    WHERE RUN_ID = :V_RUN_ID
      AND STATUS = 'FAIL';

    UPDATE DQ.VALIDATION_RUNS
    SET
        COMPLETED_AT = CURRENT_TIMESTAMP(),
        STATUS = IFF(:V_FAILED = 0, 'PASSED', 'FAILED'),
        TOTAL_CHECKS = (
            SELECT COUNT(*)
            FROM DQ.VALIDATION_RESULTS
            WHERE RUN_ID = :V_RUN_ID
        ),
        PASSED_CHECKS = (
            SELECT COUNT(*)
            FROM DQ.VALIDATION_RESULTS
            WHERE RUN_ID = :V_RUN_ID
              AND STATUS = 'PASS'
        ),
        FAILED_CHECKS = :V_FAILED
    WHERE RUN_ID = :V_RUN_ID;

    RETURN V_RUN_ID;
END;
$$;
```

Run the framework.

```sql
CALL DQ.RUN_CUSTOMER_VALIDATION();
```

Review recent runs.

```sql
SELECT *
FROM DQ.VALIDATION_RUNS
ORDER BY STARTED_AT DESC;
```

Review failures.

```sql
SELECT *
FROM DQ.VALIDATION_RESULTS
WHERE STATUS = 'FAIL'
ORDER BY CHECKED_AT DESC;
```

---

# Part VI — Integrating Data Quality with CDC

## 21. Recommended CDC Processing Flow

The Chapter 87 CDC pipeline can be extended with a quality gate.

```text
CDC events arrive
      |
      v
Stream detects changes
      |
      v
Task / procedure processes changes
      |
      v
MERGE target
      |
      v
Run DQ validations
      |
      +-----------------------+
      |                       |
      v                       v
PASS                      FAIL
 |                         |
 v                         v
Publish / Continue     Log / Quarantine
                           |
                           v
                     Alert / Investigate
```

For critical pipelines, consider validating before downstream publication rather than assuming a successful `MERGE` means the data is correct.

---

## 22. Batch-Level Validation

A large table should not always be rescanned after every incremental load.

If the CDC process records a batch or run identifier, validate the changed population when possible.

Example:

```sql
SELECT COUNT(*)
FROM CURATED.CUSTOMERS
WHERE LOAD_TS >= DATEADD('minute', -10, CURRENT_TIMESTAMP())
  AND EMAIL IS NULL;
```

Better production designs maintain an explicit pipeline run identifier such as:

```text
PIPELINE_RUN_ID
CDC_BATCH_ID
SOURCE_BATCH_ID
```

This allows validations to target exactly the records associated with a load.

---

## 23. Idempotent Validation

Validation jobs should be safe to rerun.

A practical design uses:

```text
RUN_ID
RULE_NAME
OBJECT_NAME
BATCH_ID
```

as the logical identity of a validation result.

If reruns are expected, use a `MERGE` rather than blindly inserting duplicate results.

```sql
MERGE INTO DQ.VALIDATION_RESULTS t
USING (
    SELECT
        'RUN-1001' AS RUN_ID,
        'email_not_null' AS RULE_NAME,
        'FAIL' AS STATUS,
        1 AS FAILED_ROW_COUNT
) s
ON  t.RUN_ID = s.RUN_ID
AND t.RULE_NAME = s.RULE_NAME
WHEN MATCHED THEN UPDATE SET
    STATUS = s.STATUS,
    FAILED_ROW_COUNT = s.FAILED_ROW_COUNT,
    CHECKED_AT = CURRENT_TIMESTAMP()
WHEN NOT MATCHED THEN INSERT
    (RUN_ID, RULE_NAME, STATUS, FAILED_ROW_COUNT)
VALUES
    (s.RUN_ID, s.RULE_NAME, s.STATUS, s.FAILED_ROW_COUNT);
```

---

# Part VII — Schema Validation

## 24. Validate Expected Columns

Query Snowflake metadata to verify that required columns exist.

```sql
SELECT
    COLUMN_NAME,
    DATA_TYPE,
    IS_NULLABLE
FROM SNOWFLAKE_DQ_PROJECT.INFORMATION_SCHEMA.COLUMNS
WHERE TABLE_SCHEMA = 'CURATED'
  AND TABLE_NAME = 'CUSTOMERS'
ORDER BY ORDINAL_POSITION;
```

Find a required column.

```sql
SELECT COUNT(*) AS COLUMN_EXISTS
FROM SNOWFLAKE_DQ_PROJECT.INFORMATION_SCHEMA.COLUMNS
WHERE TABLE_SCHEMA = 'CURATED'
  AND TABLE_NAME = 'CUSTOMERS'
  AND COLUMN_NAME = 'CUSTOMER_ID';
```

Expected:

```text
1
```

Schema validation can detect:

- missing columns
- unexpected columns
- changed data types
- changed nullability expectations
- incompatible schema evolution

This is especially useful when upstream systems evolve independently from the Snowflake pipeline.

---

# Part VIII — Monitoring

## 25. Data Quality Dashboard Queries

### Latest Validation Runs

```sql
SELECT
    RUN_ID,
    PIPELINE_NAME,
    STARTED_AT,
    COMPLETED_AT,
    STATUS,
    TOTAL_CHECKS,
    PASSED_CHECKS,
    FAILED_CHECKS
FROM DQ.VALIDATION_RUNS
ORDER BY STARTED_AT DESC
LIMIT 20;
```

### Failure Rate by Rule

```sql
SELECT
    RULE_NAME,
    COUNT(*) AS EXECUTIONS,
    COUNT_IF(STATUS = 'FAIL') AS FAILURES,
    ROUND(
        100 * COUNT_IF(STATUS = 'FAIL') / NULLIF(COUNT(*), 0),
        2
    ) AS FAILURE_PERCENT
FROM DQ.VALIDATION_RESULTS
GROUP BY RULE_NAME
ORDER BY FAILURE_PERCENT DESC;
```

### Recent Critical Failures

```sql
SELECT *
FROM DQ.VALIDATION_RESULTS
WHERE STATUS = 'FAIL'
  AND SEVERITY = 'CRITICAL'
  AND CHECKED_AT >= DATEADD('hour', -24, CURRENT_TIMESTAMP())
ORDER BY CHECKED_AT DESC;
```

### Failed Rows Over Time

```sql
SELECT
    DATE_TRUNC('hour', CHECKED_AT) AS HOUR,
    SUM(FAILED_ROW_COUNT) AS FAILED_ROWS
FROM DQ.VALIDATION_RESULTS
WHERE CHECKED_AT >= DATEADD('day', -7, CURRENT_TIMESTAMP())
GROUP BY 1
ORDER BY 1;
```

---

## 26. Suggested Alert Conditions

Useful alert conditions include:

| Condition | Suggested Severity |
|---|---|
| Business key contains NULL | Critical |
| Business key duplicates detected | Critical |
| Source/target reconciliation mismatch | Critical |
| CDC freshness SLA exceeded | Critical/High |
| Required business attribute missing | High |
| Invalid reference value | High |
| Invalid numeric range | High |
| Optional attribute quality issue | Medium/Low |
| Quality failure rate suddenly increases | High |

Severity should reflect business impact rather than simply the technical type of check.

---

# Part IX — Failure Injection Lab

## 27. Inject a Duplicate

```sql
INSERT INTO CURATED.CUSTOMERS
(
    CUSTOMER_ID,
    EMAIL,
    COUNTRY_CODE,
    STATUS,
    CREDIT_LIMIT,
    UPDATED_AT
)
SELECT
    CUSTOMER_ID,
    EMAIL,
    COUNTRY_CODE,
    STATUS,
    CREDIT_LIMIT,
    UPDATED_AT
FROM CURATED.CUSTOMERS
WHERE CUSTOMER_ID = 1001
LIMIT 1;
```

Detect it.

```sql
SELECT
    CUSTOMER_ID,
    COUNT(*) AS RECORD_COUNT
FROM CURATED.CUSTOMERS
GROUP BY CUSTOMER_ID
HAVING COUNT(*) > 1;
```

Expected:

```text
CUSTOMER_ID 1001 is returned.
```

---

## 28. Inject a Freshness Failure

```sql
UPDATE CURATED.CUSTOMERS
SET UPDATED_AT = DATEADD('hour', -5, CURRENT_TIMESTAMP());
```

Run:

```sql
SELECT
    MAX(UPDATED_AT),
    DATEDIFF('minute', MAX(UPDATED_AT), CURRENT_TIMESTAMP()) AS AGE_MINUTES
FROM CURATED.CUSTOMERS;
```

If the freshness SLA is 30 minutes, the check should fail.

---

## 29. Inject a Source/Target Mismatch

Delete one target record.

```sql
DELETE FROM CURATED.CUSTOMERS
WHERE CUSTOMER_ID = 1003;
```

Run the missing-key reconciliation query.

Expected:

```text
1003
```

The validation framework should detect the mismatch even though the target table itself remains queryable.

---

# Part X — Recovery and Remediation

## 30. Failure Response Workflow

Use the following operational sequence when a quality gate fails.

```text
1. Identify the failed pipeline run.
2. Identify the failed rule.
3. Determine affected row count.
4. Inspect representative failed records.
5. Determine whether the problem originated upstream or in Snowflake processing.
6. Stop downstream publication when business correctness requires it.
7. Quarantine affected records when appropriate.
8. Correct source data or transformation logic.
9. Replay or reprocess the affected batch.
10. Rerun validation.
11. Reconcile source and target.
12. Resume downstream processing.
13. Record the operational outcome.
```

Do not treat rerunning the pipeline as sufficient remediation unless the underlying defect has been identified.

---

## 31. Replay Validation

After remediation, rerun the checks.

```sql
CALL DQ.RUN_CUSTOMER_VALIDATION();
```

Verify the latest result.

```sql
SELECT *
FROM DQ.VALIDATION_RUNS
ORDER BY STARTED_AT DESC
LIMIT 1;
```

Expected after successful remediation:

```text
STATUS = PASSED
FAILED_CHECKS = 0
```

Then confirm reconciliation separately.

---

# Part XI — Production Engineering Considerations

## 32. Avoid Full-Table Validation for Every CDC Batch

Repeatedly scanning multi-terabyte tables can create unnecessary compute consumption.

Prefer:

- batch-scoped validation
- partition/date-scoped validation
- changed-key validation
- incremental aggregate reconciliation
- scheduled full reconciliation

A common pattern is:

```text
Every CDC batch
    -> lightweight incremental checks

Hourly / Daily
    -> broader reconciliation

Weekly / Scheduled
    -> deep full-table validation
```

The exact cadence should be based on business risk, pipeline volume, and cost.

---

## 33. Separate Pipeline Success from Data Success

These states are not equivalent:

```text
Task succeeded
MERGE succeeded
Data is correct
```

A technically successful SQL statement can still load:

- duplicates
- stale data
- invalid codes
- incomplete records
- incorrect transformations
- missing source records

Production observability should therefore track both pipeline execution and data-quality outcomes.

---

## 34. Preserve Validation History

Do not overwrite historical failures.

Historical data helps identify:

- recurring source defects
- unstable pipelines
- worsening quality trends
- SLA violations
- high-failure attributes
- repeated operational incidents

Retention can be controlled separately from current-state dashboards.

---

## 35. Avoid Logging Sensitive Data Unnecessarily

Quality tables often become operational datasets containing copies of failed records.

Do not automatically copy every source column into a failure table.

Prefer storing:

```text
business key
rule name
failure reason
batch/run ID
safe diagnostic attributes
```

Sensitive fields should only be retained when operationally necessary and protected using the same governance controls as the source data.

---

## 36. Make Rules Observable

A rule should have operational ownership.

Useful metadata includes:

```text
RULE_ID
RULE_NAME
OWNER
SEVERITY
PIPELINE
OBJECT
BUSINESS_DESCRIPTION
THRESHOLD
ACTIVE_FLAG
CREATED_AT
UPDATED_AT
```

For mature environments, also track:

```text
notification destination
runbook link
SLA
allowed failure percentage
last successful execution
```

---

# Part XII — Troubleshooting Runbook

## 37. Validation Suddenly Starts Failing

Check recent failures.

```sql
SELECT *
FROM DQ.VALIDATION_RESULTS
WHERE STATUS = 'FAIL'
ORDER BY CHECKED_AT DESC;
```

Then determine:

```text
Did source data change?
Did the schema change?
Did transformation logic change?
Did a reference table change?
Did a new code/value appear?
Did CDC processing skip records?
Is the validation threshold still correct?
```

Do not immediately disable the rule simply because new production data violates it.

---

## 38. Source Count and Target Count Differ

Investigate in this order:

```text
1. Confirm the counts are logically comparable.
2. Check CDC inserts, updates, and deletes separately.
3. Compare distinct business keys.
4. Find missing target keys.
5. Find unexpected target keys.
6. Compare aggregates.
7. Inspect failed/rejected/quarantined records.
8. Check pipeline execution history.
9. Check replay/backfill activity.
```

Raw CDC event counts should generally not be compared directly with current-state target counts.

---

## 39. Validation Query Is Too Expensive

Inspect query history and profile the validation SQL.

Common causes include:

- full scans of very large tables
- repeated `COUNT(DISTINCT ...)`
- large joins
- validation of unchanged historical data
- too many overlapping validation jobs

Possible improvements:

```text
validate only changed keys
validate by batch ID
validate recent partitions
persist reconciliation metrics
run deep checks less frequently
combine compatible scans
right-size the validation warehouse
```

Do not remove critical correctness checks solely to reduce compute cost.

---

## 40. False Positive Quality Failure

Confirm:

```text
rule definition
business expectation
NULL semantics
timezone handling
late-arriving data allowance
freshness threshold
reference-table version
CDC ordering assumptions
```

If the business rule changed, version or update the rule intentionally and document why.

---

# Part XIII — Production Acceptance Test

## 41. Acceptance Checklist

The project is complete when all of the following have been demonstrated.

### Framework

- [ ] Dedicated DQ schema exists.
- [ ] Rule configuration exists.
- [ ] Validation run history exists.
- [ ] Rule-level results are persisted.
- [ ] Validation can be rerun safely.

### Quality Checks

- [ ] NOT NULL validation works.
- [ ] uniqueness validation works.
- [ ] accepted-value validation works.
- [ ] range validation works.
- [ ] reference validation works.
- [ ] freshness validation works.
- [ ] schema validation works.

### Reconciliation

- [ ] source/target expected row counts can be compared.
- [ ] missing business keys can be identified.
- [ ] unexpected target keys can be identified.
- [ ] aggregate reconciliation works.
- [ ] row-level mismatch detection is available where required.

### Operations

- [ ] bad data can be quarantined.
- [ ] failed rules have severity.
- [ ] recent failures can be queried quickly.
- [ ] quality history can be trended.
- [ ] failure injection produces expected alerts/results.
- [ ] remediation and replay can return the pipeline to a passing state.

---

## 42. Final End-to-End Test

Perform the following sequence:

```text
1. Load valid source data.
2. Process it into the curated target.
3. Run the DQ framework.
4. Confirm all expected rules pass.
5. Insert an invalid record.
6. Rerun validation.
7. Confirm the appropriate rule fails.
8. Confirm the failed row can be identified or quarantined.
9. Correct the bad data.
10. Replay/reprocess the affected record.
11. Rerun validation.
12. Confirm all critical rules pass.
13. Run source-to-target reconciliation.
14. Confirm there are no unexplained mismatches.
```

This verifies not only detection, but also operational recoverability.

---

# 43. Production Design Summary

A production Snowflake data quality framework should provide five capabilities:

```text
DETECT
RECORD
ISOLATE
RECONCILE
RECOVER
```

The resulting architecture becomes:

```text
                 +-------------------+
                 | Source Systems    |
                 +---------+---------+
                           |
                           v
                 +-------------------+
                 | Raw / Landing     |
                 +---------+---------+
                           |
                           | CDC / Incremental Load
                           v
                 +-------------------+
                 | Curated Target    |
                 +---------+---------+
                           |
                           v
              +--------------------------+
              | Data Quality Framework   |
              |                          |
              | Completeness             |
              | Uniqueness               |
              | Validity                 |
              | Referential Integrity    |
              | Freshness                |
              | Reconciliation           |
              | Schema Validation        |
              +------------+-------------+
                           |
             +-------------+-------------+
             |                           |
             v                           v
     +---------------+           +---------------+
     | PASS          |           | FAIL          |
     | Publish       |           | Quarantine    |
     | Continue      |           | Alert         |
     +---------------+           +-------+-------+
                                         |
                                         v
                                 +---------------+
                                 | Remediate     |
                                 | Replay        |
                                 | Revalidate    |
                                 +---------------+
```

The key operational principle is simple:

> A successful pipeline execution does not prove that the resulting data is correct.

Data quality must therefore be observable, testable, repeatable, and recoverable just like the pipeline itself.

---

# 44. What You Built

In this project you created:

- a Snowflake data quality metadata model
- validation run tracking
- persistent rule-level results
- NOT NULL validation
- uniqueness checks
- accepted-value checks
- numeric range validation
- reference-data validation
- freshness monitoring
- source-to-target reconciliation
- aggregate reconciliation
- hash-based comparisons
- quarantine handling
- a reusable validation procedure
- CDC quality-gate patterns
- schema validation
- monitoring queries
- failure injection tests
- recovery and replay procedures
- production acceptance criteria

This framework can now be extended for application-specific tables and integrated with the CDC/incremental pipeline created in Chapter 87.

---

## Next Chapter

**Chapter 89 — Snowflake Pipeline Observability & Monitoring Project**

The next project builds operational observability around Snowflake pipelines, including task execution, stream state, query history, load failures, pipeline SLAs, data freshness, warehouse behavior, failure diagnostics, and operational dashboards.
