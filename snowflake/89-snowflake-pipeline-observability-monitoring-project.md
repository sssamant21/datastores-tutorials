# Chapter 89 — Snowflake Pipeline Observability & Monitoring Project

## 1. Project Goal

Build a production-ready observability framework for Snowflake data pipelines.

By the end of this project, you will be able to answer:

- Is the pipeline running?
- When did it last succeed?
- Is data fresh?
- Is CDC falling behind?
- Are Snowflake tasks failing or being skipped?
- How long are pipeline runs taking?
- How many rows are being processed?
- Are data-quality checks passing?
- Are warehouses consuming unexpected credits?
- Which pipeline breached its SLA/SLO?
- What evidence should an SRE/DBRE collect during an incident?

This project builds on the ingestion, CDC, and data-quality pipelines from Chapters 86–88.

---

## 2. Target Architecture

```text
Source / Landing
      |
      v
Ingestion Pipeline
      |
      v
CDC / Incremental Processing
      |
      v
Curated Tables
      |
      +--------------------+
      |                    |
      v                    v
Data Quality          Pipeline Metrics
      |                    |
      +---------+----------+
                |
                v
       Observability Schema
                |
        +-------+-------+
        |               |
        v               v
 Monitoring Views   Alert Queries
        |               |
        +-------+-------+
                |
                v
          SRE / DBRE
```

We will combine custom telemetry with Snowflake operational metadata.

---

## 3. Observability Dimensions

A production pipeline should be observable across several dimensions.

| Dimension | Question |
|---|---|
| Availability | Did the pipeline execute successfully? |
| Freshness | How old is the latest available data? |
| Latency | How long did processing take? |
| Throughput | How many rows were processed? |
| Correctness | Did validation and DQ checks pass? |
| Backlog | Is unprocessed data accumulating? |
| Reliability | How often does the pipeline fail? |
| Cost | How much compute is the pipeline consuming? |
| SLA/SLO | Is the pipeline meeting operational objectives? |

Observability should describe pipeline behavior rather than only infrastructure state.

---

## 4. Create the Project Environment

```sql
USE ROLE SYSADMIN;

CREATE DATABASE IF NOT EXISTS PIPELINE_LAB;
CREATE SCHEMA IF NOT EXISTS PIPELINE_LAB.OBSERVABILITY;

CREATE WAREHOUSE IF NOT EXISTS PIPELINE_MONITOR_WH
    WAREHOUSE_SIZE = 'XSMALL'
    AUTO_SUSPEND = 60
    AUTO_RESUME = TRUE
    INITIALLY_SUSPENDED = TRUE;

USE WAREHOUSE PIPELINE_MONITOR_WH;
USE DATABASE PIPELINE_LAB;
USE SCHEMA OBSERVABILITY;
```

For production, use your organization's role hierarchy rather than routinely operating as `SYSADMIN`.

---

## 5. Pipeline Registry

Create a registry containing the pipelines we want to monitor.

```sql
CREATE OR REPLACE TABLE PIPELINE_REGISTRY (
    PIPELINE_NAME          VARCHAR,
    PIPELINE_TYPE          VARCHAR,
    OWNER_TEAM             VARCHAR,
    EXPECTED_FREQUENCY_MIN NUMBER,
    FRESHNESS_SLO_MIN      NUMBER,
    MAX_RUNTIME_MIN        NUMBER,
    ENABLED                BOOLEAN DEFAULT TRUE,
    CREATED_AT             TIMESTAMP_LTZ DEFAULT CURRENT_TIMESTAMP(),
    PRIMARY KEY (PIPELINE_NAME)
);
```

Add sample pipelines.

```sql
INSERT INTO PIPELINE_REGISTRY
    (PIPELINE_NAME, PIPELINE_TYPE, OWNER_TEAM,
     EXPECTED_FREQUENCY_MIN, FRESHNESS_SLO_MIN, MAX_RUNTIME_MIN)
VALUES
    ('CUSTOMER_INGESTION', 'INGESTION', 'DATA_ENGINEERING', 15, 30, 10),
    ('CUSTOMER_CDC',       'CDC',       'DATA_ENGINEERING', 5, 15, 5),
    ('CUSTOMER_DQ',        'DATA_QUALITY', 'DATA_PLATFORM', 15, 30, 10);
```

The registry becomes the operational contract for each pipeline.

---

## 6. Pipeline Run History

Create a central table for pipeline executions.

```sql
CREATE OR REPLACE TABLE PIPELINE_RUN_HISTORY (
    RUN_ID              VARCHAR,
    PIPELINE_NAME       VARCHAR,
    START_TIME          TIMESTAMP_LTZ,
    END_TIME            TIMESTAMP_LTZ,
    STATUS              VARCHAR,
    ROWS_READ           NUMBER DEFAULT 0,
    ROWS_INSERTED       NUMBER DEFAULT 0,
    ROWS_UPDATED        NUMBER DEFAULT 0,
    ROWS_DELETED        NUMBER DEFAULT 0,
    ROWS_REJECTED       NUMBER DEFAULT 0,
    ERROR_CODE          VARCHAR,
    ERROR_MESSAGE       VARCHAR,
    QUERY_ID            VARCHAR,
    WAREHOUSE_NAME      VARCHAR,
    CREATED_AT          TIMESTAMP_LTZ DEFAULT CURRENT_TIMESTAMP()
);
```

Recommended statuses:

```text
RUNNING
SUCCESS
FAILED
PARTIAL
SKIPPED
```

Do not depend only on task history. Custom run telemetry provides business-level context such as processed rows, rejected rows, and logical pipeline status.

---

## 7. Record Pipeline Start

Generate a run identifier before processing.

```sql
SET RUN_ID = UUID_STRING();

INSERT INTO PIPELINE_RUN_HISTORY (
    RUN_ID,
    PIPELINE_NAME,
    START_TIME,
    STATUS,
    WAREHOUSE_NAME
)
VALUES (
    $RUN_ID,
    'CUSTOMER_CDC',
    CURRENT_TIMESTAMP(),
    'RUNNING',
    CURRENT_WAREHOUSE()
);
```

The same `RUN_ID` should follow the pipeline through processing, validation, and incident investigation.

---

## 8. Record Successful Completion

After processing completes:

```sql
UPDATE PIPELINE_RUN_HISTORY
SET
    END_TIME = CURRENT_TIMESTAMP(),
    STATUS = 'SUCCESS',
    ROWS_READ = 10000,
    ROWS_INSERTED = 500,
    ROWS_UPDATED = 9200,
    ROWS_DELETED = 300
WHERE RUN_ID = $RUN_ID;
```

Runtime can be derived from `START_TIME` and `END_TIME` rather than stored independently.

---

## 9. Record Pipeline Failure

Failures must also be persisted.

Example pattern inside a Snowflake Scripting procedure:

```sql
EXCEPTION
    WHEN OTHER THEN
        UPDATE PIPELINE_RUN_HISTORY
        SET
            END_TIME = CURRENT_TIMESTAMP(),
            STATUS = 'FAILED',
            ERROR_CODE = SQLCODE::VARCHAR,
            ERROR_MESSAGE = SQLERRM
        WHERE RUN_ID = :V_RUN_ID;

        RAISE;
```

The important principle is:

> A pipeline failure should leave operational evidence behind.

Do not swallow the original exception after logging it.

---

## 10. Pipeline Runtime View

Create a reusable monitoring view.

```sql
CREATE OR REPLACE VIEW V_PIPELINE_RUNS AS
SELECT
    RUN_ID,
    PIPELINE_NAME,
    START_TIME,
    END_TIME,
    STATUS,
    DATEDIFF('second', START_TIME, COALESCE(END_TIME, CURRENT_TIMESTAMP()))
        AS RUNTIME_SECONDS,
    ROWS_READ,
    ROWS_INSERTED,
    ROWS_UPDATED,
    ROWS_DELETED,
    ROWS_REJECTED,
    ERROR_CODE,
    ERROR_MESSAGE,
    QUERY_ID,
    WAREHOUSE_NAME
FROM PIPELINE_RUN_HISTORY;
```

Query it:

```sql
SELECT *
FROM V_PIPELINE_RUNS
ORDER BY START_TIME DESC;
```

---

## 11. Latest Pipeline Status

Operations teams usually care first about the latest execution.

```sql
CREATE OR REPLACE VIEW V_LATEST_PIPELINE_STATUS AS
SELECT *
FROM V_PIPELINE_RUNS
QUALIFY ROW_NUMBER() OVER (
    PARTITION BY PIPELINE_NAME
    ORDER BY START_TIME DESC
) = 1;
```

Check all pipelines:

```sql
SELECT
    PIPELINE_NAME,
    STATUS,
    START_TIME,
    END_TIME,
    RUNTIME_SECONDS,
    ERROR_MESSAGE
FROM V_LATEST_PIPELINE_STATUS
ORDER BY PIPELINE_NAME;
```

---

## 12. Freshness Monitoring

Pipeline success does not guarantee fresh data.

Create a freshness table.

```sql
CREATE OR REPLACE TABLE PIPELINE_FRESHNESS (
    PIPELINE_NAME       VARCHAR,
    OBSERVED_AT         TIMESTAMP_LTZ,
    MAX_SOURCE_EVENT_TS TIMESTAMP_LTZ,
    MAX_TARGET_EVENT_TS TIMESTAMP_LTZ,
    SOURCE_LAG_SECONDS  NUMBER,
    TARGET_LAG_SECONDS  NUMBER
);
```

Example measurement:

```sql
INSERT INTO PIPELINE_FRESHNESS
SELECT
    'CUSTOMER_CDC',
    CURRENT_TIMESTAMP(),
    MAX(EVENT_TS),
    MAX(EVENT_TS),
    DATEDIFF('second', MAX(EVENT_TS), CURRENT_TIMESTAMP()),
    DATEDIFF('second', MAX(EVENT_TS), CURRENT_TIMESTAMP())
FROM CURATED.CUSTOMERS;
```

In a real source-to-target pipeline, calculate source and target timestamps independently.

---

## 13. Freshness SLO View

```sql
CREATE OR REPLACE VIEW V_PIPELINE_FRESHNESS_STATUS AS
SELECT
    F.PIPELINE_NAME,
    F.OBSERVED_AT,
    F.MAX_TARGET_EVENT_TS,
    F.TARGET_LAG_SECONDS,
    R.FRESHNESS_SLO_MIN,
    CASE
        WHEN F.TARGET_LAG_SECONDS > R.FRESHNESS_SLO_MIN * 60
            THEN 'BREACHED'
        ELSE 'HEALTHY'
    END AS FRESHNESS_STATUS
FROM PIPELINE_FRESHNESS F
JOIN PIPELINE_REGISTRY R
    ON F.PIPELINE_NAME = R.PIPELINE_NAME
QUALIFY ROW_NUMBER() OVER (
    PARTITION BY F.PIPELINE_NAME
    ORDER BY F.OBSERVED_AT DESC
) = 1;
```

Query:

```sql
SELECT *
FROM V_PIPELINE_FRESHNESS_STATUS;
```

---

## 14. Detect Missing Pipeline Runs

A pipeline can fail silently if it simply stops running.

```sql
CREATE OR REPLACE VIEW V_MISSING_PIPELINE_RUNS AS
SELECT
    R.PIPELINE_NAME,
    R.EXPECTED_FREQUENCY_MIN,
    MAX(H.START_TIME) AS LAST_RUN_TIME,
    DATEDIFF('minute', MAX(H.START_TIME), CURRENT_TIMESTAMP()) AS MINUTES_SINCE_LAST_RUN,
    CASE
        WHEN MAX(H.START_TIME) IS NULL THEN 'NEVER_RUN'
        WHEN DATEDIFF('minute', MAX(H.START_TIME), CURRENT_TIMESTAMP())
             > R.EXPECTED_FREQUENCY_MIN * 2
            THEN 'MISSING_RUN'
        ELSE 'HEALTHY'
    END AS RUN_STATUS
FROM PIPELINE_REGISTRY R
LEFT JOIN PIPELINE_RUN_HISTORY H
    ON R.PIPELINE_NAME = H.PIPELINE_NAME
WHERE R.ENABLED = TRUE
GROUP BY
    R.PIPELINE_NAME,
    R.EXPECTED_FREQUENCY_MIN;
```

Using `2 × expected frequency` is only a sample policy. Tune it to your scheduling and alerting requirements.

---

## 15. Long-Running Pipeline Detection

```sql
CREATE OR REPLACE VIEW V_LONG_RUNNING_PIPELINES AS
SELECT
    H.RUN_ID,
    H.PIPELINE_NAME,
    H.START_TIME,
    DATEDIFF('minute', H.START_TIME, CURRENT_TIMESTAMP()) AS RUNNING_MINUTES,
    R.MAX_RUNTIME_MIN
FROM PIPELINE_RUN_HISTORY H
JOIN PIPELINE_REGISTRY R
    ON H.PIPELINE_NAME = R.PIPELINE_NAME
WHERE H.STATUS = 'RUNNING'
  AND DATEDIFF('minute', H.START_TIME, CURRENT_TIMESTAMP())
      > R.MAX_RUNTIME_MIN;
```

This catches pipelines that started but never completed normally.

---

## 16. Throughput Monitoring

Calculate pipeline throughput.

```sql
SELECT
    PIPELINE_NAME,
    START_TIME,
    ROWS_READ,
    RUNTIME_SECONDS,
    ROUND(
        ROWS_READ / NULLIF(RUNTIME_SECONDS, 0),
        2
    ) AS ROWS_PER_SECOND
FROM V_PIPELINE_RUNS
WHERE STATUS = 'SUCCESS'
ORDER BY START_TIME DESC;
```

A pipeline may remain successful while throughput steadily degrades. That makes throughput a valuable early-warning signal.

---

## 17. Throughput Baseline

Create a rolling baseline.

```sql
SELECT
    PIPELINE_NAME,
    AVG(ROWS_READ / NULLIF(RUNTIME_SECONDS, 0)) AS AVG_ROWS_PER_SECOND,
    MEDIAN(ROWS_READ / NULLIF(RUNTIME_SECONDS, 0)) AS MEDIAN_ROWS_PER_SECOND
FROM V_PIPELINE_RUNS
WHERE STATUS = 'SUCCESS'
  AND START_TIME >= DATEADD('day', -7, CURRENT_TIMESTAMP())
GROUP BY PIPELINE_NAME;
```

Compare current throughput with historical behavior before concluding that a pipeline is slow.

---

## 18. Failure Rate

```sql
SELECT
    PIPELINE_NAME,
    COUNT(*) AS TOTAL_RUNS,
    COUNT_IF(STATUS = 'FAILED') AS FAILED_RUNS,
    ROUND(
        100 * COUNT_IF(STATUS = 'FAILED') / NULLIF(COUNT(*), 0),
        2
    ) AS FAILURE_PERCENT
FROM PIPELINE_RUN_HISTORY
WHERE START_TIME >= DATEADD('day', -7, CURRENT_TIMESTAMP())
GROUP BY PIPELINE_NAME;
```

This provides a basic reliability indicator.

---

## 19. Snowflake Task Monitoring

Snowflake exposes task execution history through metadata functions and Account Usage.

For near-real-time troubleshooting, use the Information Schema table function.

```sql
SELECT
    NAME,
    STATE,
    SCHEDULED_TIME,
    QUERY_START_TIME,
    COMPLETED_TIME,
    ERROR_CODE,
    ERROR_MESSAGE,
    QUERY_ID
FROM TABLE(
    INFORMATION_SCHEMA.TASK_HISTORY(
        SCHEDULED_TIME_RANGE_START => DATEADD('hour', -4, CURRENT_TIMESTAMP()),
        RESULT_LIMIT => 100
    )
)
ORDER BY SCHEDULED_TIME DESC;
```

`ACCOUNT_USAGE.TASK_HISTORY` is useful for historical analysis but Account Usage views can have ingestion latency. Do not treat them as zero-latency alert sources.

---

## 20. Failed Tasks

```sql
SELECT
    NAME,
    STATE,
    SCHEDULED_TIME,
    QUERY_ID,
    ERROR_CODE,
    ERROR_MESSAGE
FROM TABLE(
    INFORMATION_SCHEMA.TASK_HISTORY(
        SCHEDULED_TIME_RANGE_START => DATEADD('hour', -24, CURRENT_TIMESTAMP()),
        RESULT_LIMIT => 1000
    )
)
WHERE STATE = 'FAILED'
ORDER BY SCHEDULED_TIME DESC;
```

Capture the `QUERY_ID`; it is one of the most useful identifiers during Snowflake incident analysis.

---

## 21. Task Runtime Analysis

```sql
SELECT
    NAME,
    SCHEDULED_TIME,
    QUERY_START_TIME,
    COMPLETED_TIME,
    DATEDIFF('second', QUERY_START_TIME, COMPLETED_TIME) AS RUNTIME_SECONDS,
    STATE,
    QUERY_ID
FROM TABLE(
    INFORMATION_SCHEMA.TASK_HISTORY(
        SCHEDULED_TIME_RANGE_START => DATEADD('day', -1, CURRENT_TIMESTAMP()),
        RESULT_LIMIT => 1000
    )
)
WHERE QUERY_START_TIME IS NOT NULL
ORDER BY SCHEDULED_TIME DESC;
```

Watch for increasing runtime even when tasks still succeed.

---

## 22. Stream Backlog Monitoring

For CDC pipelines, monitor whether a stream contains unconsumed change records.

```sql
SELECT SYSTEM$STREAM_HAS_DATA('PIPELINE_LAB.CDC.CUSTOMER_STREAM');
```

This returns whether the stream currently contains change data.

It does **not** tell you the exact backlog size.

When operationally safe, a stream can also be queried to inspect pending records:

```sql
SELECT COUNT(*) AS PENDING_CHANGE_ROWS
FROM PIPELINE_LAB.CDC.CUSTOMER_STREAM;
```

Remember that stream semantics and consumption are transaction-dependent. Monitoring queries should be designed so they do not accidentally alter pipeline behavior.

---

## 23. Stream Staleness Risk

Inspect stream metadata.

```sql
SHOW STREAMS IN DATABASE PIPELINE_LAB;
```

Then inspect the result if needed:

```sql
SELECT *
FROM TABLE(RESULT_SCAN(LAST_QUERY_ID()));
```

Pay particular attention to stream staleness metadata such as `stale_after`.

A stream that is not consumed before its retention window is exceeded can become stale and may require recreation or pipeline recovery.

---

## 24. Query History for Pipeline Investigation

```sql
SELECT
    QUERY_ID,
    QUERY_TEXT,
    USER_NAME,
    ROLE_NAME,
    WAREHOUSE_NAME,
    START_TIME,
    END_TIME,
    TOTAL_ELAPSED_TIME,
    EXECUTION_STATUS,
    ERROR_CODE,
    ERROR_MESSAGE
FROM SNOWFLAKE.ACCOUNT_USAGE.QUERY_HISTORY
WHERE START_TIME >= DATEADD('hour', -2, CURRENT_TIMESTAMP())
  AND WAREHOUSE_NAME = 'PIPELINE_MONITOR_WH'
ORDER BY START_TIME DESC;
```

For very recent queries, Information Schema query-history functions can be preferable because Account Usage has latency.

---

## 25. Query Performance Signals

Useful fields from query history include:

```text
TOTAL_ELAPSED_TIME
BYTES_SCANNED
ROWS_PRODUCED
PARTITIONS_SCANNED
PARTITIONS_TOTAL
BYTES_SPILLED_TO_LOCAL_STORAGE
BYTES_SPILLED_TO_REMOTE_STORAGE
QUEUED_OVERLOAD_TIME
QUEUED_PROVISIONING_TIME
COMPILATION_TIME
EXECUTION_TIME
```

Example:

```sql
SELECT
    QUERY_ID,
    TOTAL_ELAPSED_TIME,
    EXECUTION_TIME,
    QUEUED_OVERLOAD_TIME,
    BYTES_SCANNED,
    BYTES_SPILLED_TO_LOCAL_STORAGE,
    BYTES_SPILLED_TO_REMOTE_STORAGE
FROM SNOWFLAKE.ACCOUNT_USAGE.QUERY_HISTORY
WHERE START_TIME >= DATEADD('hour', -6, CURRENT_TIMESTAMP())
  AND WAREHOUSE_NAME = 'PIPELINE_MONITOR_WH'
ORDER BY TOTAL_ELAPSED_TIME DESC;
```

This helps distinguish execution cost from queuing, scanning, and spill-related symptoms.

---

## 26. Warehouse Load Monitoring

```sql
SELECT
    START_TIME,
    END_TIME,
    WAREHOUSE_NAME,
    AVG_RUNNING,
    AVG_QUEUED_LOAD,
    AVG_QUEUED_PROVISIONING,
    AVG_BLOCKED
FROM SNOWFLAKE.ACCOUNT_USAGE.WAREHOUSE_LOAD_HISTORY
WHERE START_TIME >= DATEADD('hour', -6, CURRENT_TIMESTAMP())
  AND WAREHOUSE_NAME = 'PIPELINE_MONITOR_WH'
ORDER BY START_TIME DESC;
```

Repeated queuing can indicate concurrency pressure or warehouse-sizing issues.

---

## 27. Warehouse Credit Monitoring

```sql
SELECT
    START_TIME,
    END_TIME,
    WAREHOUSE_NAME,
    CREDITS_USED,
    CREDITS_USED_COMPUTE,
    CREDITS_USED_CLOUD_SERVICES
FROM SNOWFLAKE.ACCOUNT_USAGE.WAREHOUSE_METERING_HISTORY
WHERE START_TIME >= DATEADD('day', -7, CURRENT_TIMESTAMP())
  AND WAREHOUSE_NAME = 'PIPELINE_MONITOR_WH'
ORDER BY START_TIME DESC;
```

Cost observability belongs beside performance observability.

A faster pipeline is not automatically better if its compute consumption increases disproportionately.

---

## 28. Daily Credit Trend

```sql
SELECT
    DATE_TRUNC('day', START_TIME) AS USAGE_DAY,
    WAREHOUSE_NAME,
    SUM(CREDITS_USED) AS TOTAL_CREDITS
FROM SNOWFLAKE.ACCOUNT_USAGE.WAREHOUSE_METERING_HISTORY
WHERE START_TIME >= DATEADD('day', -30, CURRENT_TIMESTAMP())
GROUP BY 1, 2
ORDER BY 1 DESC, 2;
```

Use trends rather than isolated credit values when investigating cost regressions.

---

## 29. Data Quality Integration

Chapter 88 produced data-quality results. Pipeline observability should surface them.

Assume a table similar to:

```text
DQ_VALIDATION_HISTORY
```

Create a monitoring view:

```sql
CREATE OR REPLACE VIEW V_DQ_FAILURES AS
SELECT
    PIPELINE_NAME,
    RULE_NAME,
    CHECK_TIME,
    STATUS,
    FAILED_ROW_COUNT,
    DETAILS
FROM DATA_QUALITY.DQ_VALIDATION_HISTORY
WHERE STATUS = 'FAILED';
```

This connects operational success with data correctness.

A pipeline that returns `SUCCESS` while publishing invalid data should not be considered healthy.

---

## 30. Unified Pipeline Health View

Create a simplified health view.

```sql
CREATE OR REPLACE VIEW V_PIPELINE_HEALTH AS
SELECT
    R.PIPELINE_NAME,
    L.STATUS AS LAST_RUN_STATUS,
    L.START_TIME AS LAST_RUN_TIME,
    L.RUNTIME_SECONDS,
    R.MAX_RUNTIME_MIN,
    DATEDIFF('minute', L.START_TIME, CURRENT_TIMESTAMP()) AS MINUTES_SINCE_LAST_RUN,
    R.EXPECTED_FREQUENCY_MIN,
    CASE
        WHEN L.PIPELINE_NAME IS NULL THEN 'CRITICAL'
        WHEN L.STATUS = 'FAILED' THEN 'CRITICAL'
        WHEN L.STATUS = 'RUNNING'
             AND L.RUNTIME_SECONDS > R.MAX_RUNTIME_MIN * 60
            THEN 'CRITICAL'
        WHEN DATEDIFF('minute', L.START_TIME, CURRENT_TIMESTAMP())
             > R.EXPECTED_FREQUENCY_MIN * 2
            THEN 'CRITICAL'
        WHEN L.STATUS NOT IN ('SUCCESS', 'RUNNING') THEN 'WARNING'
        ELSE 'HEALTHY'
    END AS HEALTH_STATUS
FROM PIPELINE_REGISTRY R
LEFT JOIN V_LATEST_PIPELINE_STATUS L
    ON R.PIPELINE_NAME = L.PIPELINE_NAME
WHERE R.ENABLED = TRUE;
```

Query:

```sql
SELECT *
FROM V_PIPELINE_HEALTH
ORDER BY
    CASE HEALTH_STATUS
        WHEN 'CRITICAL' THEN 1
        WHEN 'WARNING' THEN 2
        ELSE 3
    END,
    PIPELINE_NAME;
```

---

## 31. SLA and SLO Definitions

Example operational objectives:

| Metric | Target |
|---|---:|
| Pipeline success rate | >= 99.5% |
| Data freshness | <= 15 minutes |
| CDC processing runtime | <= 5 minutes |
| DQ critical-rule success | 100% |
| Missing scheduled runs | 0 |

Do not choose thresholds simply because they are easy to monitor.

They should reflect business requirements and pipeline design.

---

## 32. SLO Compliance Query

```sql
WITH DAILY AS (
    SELECT
        PIPELINE_NAME,
        DATE_TRUNC('day', START_TIME) AS RUN_DAY,
        COUNT(*) AS TOTAL_RUNS,
        COUNT_IF(STATUS = 'SUCCESS') AS SUCCESSFUL_RUNS
    FROM PIPELINE_RUN_HISTORY
    WHERE START_TIME >= DATEADD('day', -30, CURRENT_TIMESTAMP())
    GROUP BY 1, 2
)
SELECT
    PIPELINE_NAME,
    RUN_DAY,
    TOTAL_RUNS,
    SUCCESSFUL_RUNS,
    ROUND(
        100 * SUCCESSFUL_RUNS / NULLIF(TOTAL_RUNS, 0),
        3
    ) AS SUCCESS_RATE_PERCENT
FROM DAILY
ORDER BY RUN_DAY DESC, PIPELINE_NAME;
```

---

## 33. Alert Candidate View

Snowflake monitoring views can expose conditions that an external alerting system or Snowflake-native alerting workflow can evaluate.

```sql
CREATE OR REPLACE VIEW V_PIPELINE_ALERTS AS
SELECT
    PIPELINE_NAME,
    'PIPELINE_FAILURE' AS ALERT_TYPE,
    'CRITICAL' AS SEVERITY,
    'Latest pipeline run failed' AS MESSAGE,
    CURRENT_TIMESTAMP() AS OBSERVED_AT
FROM V_LATEST_PIPELINE_STATUS
WHERE STATUS = 'FAILED'

UNION ALL

SELECT
    PIPELINE_NAME,
    'MISSING_RUN',
    'CRITICAL',
    'Pipeline has not executed within expected interval',
    CURRENT_TIMESTAMP()
FROM V_MISSING_PIPELINE_RUNS
WHERE RUN_STATUS IN ('MISSING_RUN', 'NEVER_RUN')

UNION ALL

SELECT
    PIPELINE_NAME,
    'LONG_RUNNING',
    'WARNING',
    'Pipeline runtime exceeded configured threshold',
    CURRENT_TIMESTAMP()
FROM V_LONG_RUNNING_PIPELINES;
```

Query:

```sql
SELECT *
FROM V_PIPELINE_ALERTS;
```

---

## 34. Alerting Design

Possible alert delivery paths include:

```text
Snowflake monitoring query
        |
        v
Snowflake Alert / Task / Procedure
        |
        v
Notification integration or external monitoring platform
        |
        v
Pager / Slack / Email / Incident platform
```

The exact integration depends on your organization's security and notification architecture.

Keep detection logic separate from notification delivery whenever possible.

---

## 35. Avoid Alert Noise

Do not alert on every transient anomaly.

Useful techniques include:

- require multiple consecutive failures when appropriate;
- separate warning and critical thresholds;
- suppress duplicate notifications;
- alert on SLO impact rather than every metric fluctuation;
- include pipeline owner and run identifier;
- automatically resolve alerts when health returns;
- maintain runbooks for actionable alerts.

An alert that nobody can act on is operational noise.

---

## 36. Pipeline Dashboard Dataset

Create a dashboard-ready view.

```sql
CREATE OR REPLACE VIEW V_PIPELINE_DASHBOARD AS
SELECT
    R.PIPELINE_NAME,
    R.PIPELINE_TYPE,
    R.OWNER_TEAM,
    H.HEALTH_STATUS,
    L.STATUS AS LAST_RUN_STATUS,
    L.START_TIME AS LAST_RUN_TIME,
    L.RUNTIME_SECONDS,
    L.ROWS_READ,
    L.ROWS_INSERTED,
    L.ROWS_UPDATED,
    L.ROWS_DELETED,
    L.ROWS_REJECTED,
    R.EXPECTED_FREQUENCY_MIN,
    R.FRESHNESS_SLO_MIN,
    R.MAX_RUNTIME_MIN
FROM PIPELINE_REGISTRY R
LEFT JOIN V_PIPELINE_HEALTH H
    ON R.PIPELINE_NAME = H.PIPELINE_NAME
LEFT JOIN V_LATEST_PIPELINE_STATUS L
    ON R.PIPELINE_NAME = L.PIPELINE_NAME
WHERE R.ENABLED = TRUE;
```

This view can feed Snowsight or an approved external BI/monitoring platform.

---

## 37. Recommended Dashboard Panels

A useful pipeline dashboard should include:

| Panel | Purpose |
|---|---|
| Pipeline health | Current status |
| Last successful run | Detect stopped pipelines |
| Freshness lag | Detect stale data |
| Runtime trend | Detect performance degradation |
| Throughput trend | Detect processing slowdown |
| Failure count | Reliability |
| DQ failures | Data correctness |
| CDC backlog | Incremental processing health |
| Warehouse queue | Compute contention |
| Credit usage | Cost trend |

Avoid dashboards with dozens of metrics that do not support an operational decision.

---

## 38. Failure Injection Test

Observability must be tested, not assumed.

Simulate a pipeline failure:

```sql
SET TEST_RUN_ID = UUID_STRING();

INSERT INTO PIPELINE_RUN_HISTORY (
    RUN_ID,
    PIPELINE_NAME,
    START_TIME,
    END_TIME,
    STATUS,
    ERROR_CODE,
    ERROR_MESSAGE
)
VALUES (
    $TEST_RUN_ID,
    'CUSTOMER_CDC',
    DATEADD('minute', -2, CURRENT_TIMESTAMP()),
    CURRENT_TIMESTAMP(),
    'FAILED',
    'TEST_FAILURE',
    'Synthetic failure generated for observability validation'
);
```

Verify:

```sql
SELECT *
FROM V_PIPELINE_HEALTH
WHERE PIPELINE_NAME = 'CUSTOMER_CDC';
```

Expected result:

```text
HEALTH_STATUS = CRITICAL
```

Then verify the alert view:

```sql
SELECT *
FROM V_PIPELINE_ALERTS
WHERE PIPELINE_NAME = 'CUSTOMER_CDC';
```

---

## 39. Missing-Run Test

Insert an intentionally old successful run for a test pipeline.

```sql
INSERT INTO PIPELINE_REGISTRY (
    PIPELINE_NAME,
    PIPELINE_TYPE,
    OWNER_TEAM,
    EXPECTED_FREQUENCY_MIN,
    FRESHNESS_SLO_MIN,
    MAX_RUNTIME_MIN
)
VALUES (
    'OBSERVABILITY_TEST',
    'TEST',
    'DATA_PLATFORM',
    5,
    10,
    5
);

INSERT INTO PIPELINE_RUN_HISTORY (
    RUN_ID,
    PIPELINE_NAME,
    START_TIME,
    END_TIME,
    STATUS
)
VALUES (
    UUID_STRING(),
    'OBSERVABILITY_TEST',
    DATEADD('minute', -30, CURRENT_TIMESTAMP()),
    DATEADD('minute', -29, CURRENT_TIMESTAMP()),
    'SUCCESS'
);
```

Verify:

```sql
SELECT *
FROM V_MISSING_PIPELINE_RUNS
WHERE PIPELINE_NAME = 'OBSERVABILITY_TEST';
```

Expected:

```text
RUN_STATUS = MISSING_RUN
```

---

## 40. Long-Running Test

```sql
INSERT INTO PIPELINE_RUN_HISTORY (
    RUN_ID,
    PIPELINE_NAME,
    START_TIME,
    STATUS
)
VALUES (
    UUID_STRING(),
    'OBSERVABILITY_TEST',
    DATEADD('minute', -20, CURRENT_TIMESTAMP()),
    'RUNNING'
);
```

Verify:

```sql
SELECT *
FROM V_LONG_RUNNING_PIPELINES
WHERE PIPELINE_NAME = 'OBSERVABILITY_TEST';
```

The test pipeline should appear because its runtime exceeds the configured five-minute maximum.

---

## 41. Incident Troubleshooting Workflow

When a Snowflake pipeline incident occurs, investigate in this order.

### Step 1 — Confirm Impact

```sql
SELECT *
FROM V_PIPELINE_HEALTH
WHERE HEALTH_STATUS <> 'HEALTHY';
```

Determine:

- affected pipeline;
- last success;
- current status;
- freshness impact;
- downstream impact.

### Step 2 — Check Recent Runs

```sql
SELECT *
FROM V_PIPELINE_RUNS
WHERE PIPELINE_NAME = '<pipeline>'
ORDER BY START_TIME DESC
LIMIT 20;
```

Look for repeated failures, increasing runtime, and unusual row counts.

### Step 3 — Check Task History

```sql
SELECT *
FROM TABLE(
    INFORMATION_SCHEMA.TASK_HISTORY(
        SCHEDULED_TIME_RANGE_START => DATEADD('hour', -4, CURRENT_TIMESTAMP()),
        RESULT_LIMIT => 100
    )
)
ORDER BY SCHEDULED_TIME DESC;
```

### Step 4 — Capture Query IDs

Use the failed task or pipeline run to identify the relevant Snowflake query IDs.

### Step 5 — Inspect Query Behavior

Check:

```text
execution time
queue time
bytes scanned
partitions scanned
spill
errors
warehouse
```

### Step 6 — Check CDC State

Inspect streams and backlog indicators.

### Step 7 — Check Data Quality

Confirm whether bad data caused processing to stop or whether invalid data was published.

### Step 8 — Check Warehouse Pressure

Review load history and queuing.

### Step 9 — Check Cost Regression

Determine whether a recent change increased warehouse consumption.

### Step 10 — Recover and Validate

After remediation:

1. replay or restart safely;
2. confirm successful processing;
3. validate source-to-target counts;
4. validate DQ rules;
5. verify freshness;
6. confirm backlog clears;
7. confirm alerts resolve.

---

## 42. Troubleshooting Matrix

| Symptom | Likely Area | Check |
|---|---|---|
| Pipeline failed | SQL/task/procedure | Run history + task history |
| Pipeline never started | Scheduler/task state | Task history |
| Data stale | Missing run/backlog | Freshness + stream |
| Runtime increasing | Query/warehouse | Query history + load history |
| Low throughput | Query/data volume | Runtime and row metrics |
| CDC behind | Stream/task | Stream state + task history |
| Data incorrect | DQ/transformation | DQ history |
| High credits | Warehouse/query | Metering + query history |
| Query queued | Warehouse contention | Warehouse load history |
| Stream stale | Retention/consumer outage | SHOW STREAMS |

---

## 43. Operational Runbook — Pipeline Failure

When a pipeline fails:

```text
1. Identify pipeline and RUN_ID.
2. Record incident start time.
3. Determine last successful execution.
4. Check ERROR_CODE and ERROR_MESSAGE.
5. Capture QUERY_ID.
6. Review task history.
7. Review query history.
8. Check warehouse load/queueing.
9. Check stream/backlog state for CDC pipelines.
10. Check DQ failures.
11. Determine whether replay is safe.
12. Fix the underlying issue.
13. Re-run/replay using the pipeline's idempotent recovery procedure.
14. Validate counts and DQ.
15. Confirm freshness is restored.
16. Confirm monitoring returns to healthy.
17. Document cause, impact, remediation, and prevention.
```

Never blindly restart a CDC pipeline without understanding its replay and idempotency behavior.

---

## 44. Operational Runbook — Freshness Breach

```text
1. Confirm the freshness breach.
2. Determine source maximum event timestamp.
3. Determine target maximum event timestamp.
4. Check whether ingestion is delayed.
5. Check whether CDC processing is delayed.
6. Check stream state.
7. Check task history.
8. Check warehouse queuing.
9. Check failed DQ gates.
10. Recover the blocked stage.
11. Verify backlog drains.
12. Confirm freshness returns within SLO.
```

Freshness monitoring helps identify the affected stage instead of treating the entire pipeline as one black box.

---

## 45. Operational Runbook — Cost Spike

```text
1. Identify the warehouse with increased credits.
2. Compare usage against the historical baseline.
3. Identify queries executed during the spike.
4. Check bytes scanned and runtime.
5. Check query frequency.
6. Check warehouse size changes.
7. Check auto-suspend behavior.
8. Check retry loops or repeated failed jobs.
9. Check unexpected backfills.
10. Optimize or stop the responsible workload if appropriate.
11. Confirm credit consumption returns to baseline.
```

Do not resize a warehouse based only on credit usage. First identify the workload causing the increase.

---

## 46. Observability Retention

Custom telemetry should have an explicit retention policy.

Example:

```sql
DELETE FROM PIPELINE_RUN_HISTORY
WHERE START_TIME < DATEADD('day', -90, CURRENT_TIMESTAMP());
```

For longer-term analysis, aggregate detailed telemetry before deleting it.

Example strategy:

```text
Raw run history       -> 90 days
Hourly aggregates     -> 1 year
Daily SLA/SLO metrics -> multiple years if required
```

Retention should reflect operational, compliance, and cost requirements.

---

## 47. Security and RBAC

Monitoring data can expose:

- query text;
- object names;
- user names;
- operational errors;
- workload patterns;
- cost information.

Use least privilege.

A production model might separate roles such as:

```text
PIPELINE_RUNTIME_ROLE
PIPELINE_MONITOR_ROLE
PIPELINE_ADMIN_ROLE
COST_OBSERVER_ROLE
```

Do not grant broad account-level metadata access merely to support a dashboard.

---

## 48. Production Design Principles

### Principle 1 — Monitor outcomes

A running warehouse does not prove that fresh, correct data reached consumers.

### Principle 2 — Preserve identifiers

Capture:

```text
RUN_ID
QUERY_ID
PIPELINE_NAME
TASK_NAME
WAREHOUSE_NAME
```

These connect telemetry during troubleshooting.

### Principle 3 — Separate detection from notification

Views and queries should identify problems independently of Slack, email, or paging integrations.

### Principle 4 — Measure trends

Runtime, throughput, and cost regressions often appear gradually.

### Principle 5 — Test monitoring failures

Inject controlled failures so you know the observability system actually detects them.

### Principle 6 — Make alerts actionable

Every critical alert should have:

```text
owner
severity
impact
runbook
recovery path
```

---

## 49. Production Acceptance Test

The project is complete only when all of the following are validated.

### Pipeline Telemetry

- [ ] Every pipeline has a registry entry.
- [ ] Every execution receives a unique `RUN_ID`.
- [ ] Start and completion status are recorded.
- [ ] Failed executions preserve error details.
- [ ] Query IDs are captured where applicable.
- [ ] Row-processing metrics are recorded.

### Reliability

- [ ] Latest pipeline status is visible.
- [ ] Missing runs are detected.
- [ ] Long-running executions are detected.
- [ ] Failure rate can be calculated.

### Freshness

- [ ] Source freshness is measurable.
- [ ] Target freshness is measurable.
- [ ] Freshness SLO breaches are detected.

### CDC

- [ ] Stream state is observable.
- [ ] Backlog can be investigated.
- [ ] Stream staleness risk is monitored.

### Data Quality

- [ ] Critical DQ failures are visible.
- [ ] Invalid data cannot appear healthy simply because SQL completed successfully.

### Performance

- [ ] Runtime trends are available.
- [ ] Throughput trends are available.
- [ ] Query history can be correlated with pipeline runs.
- [ ] Warehouse queueing can be investigated.

### Cost

- [ ] Warehouse credit usage is measurable.
- [ ] Daily cost trends are available.
- [ ] Cost spikes can be correlated with workloads.

### Alerting

- [ ] Failure conditions produce alert candidates.
- [ ] Missing runs produce alert candidates.
- [ ] Long-running jobs produce alert candidates.
- [ ] Alerts map to an owner and runbook.

### Recovery

- [ ] Synthetic failure test succeeds.
- [ ] Missing-run test succeeds.
- [ ] Long-running test succeeds.
- [ ] Recovery returns pipeline health to normal.

---

## 50. Final Project Validation

Run the primary operational checks.

```sql
SELECT * FROM V_PIPELINE_HEALTH;
```

```sql
SELECT * FROM V_PIPELINE_ALERTS;
```

```sql
SELECT * FROM V_PIPELINE_FRESHNESS_STATUS;
```

```sql
SELECT * FROM V_LONG_RUNNING_PIPELINES;
```

```sql
SELECT * FROM V_MISSING_PIPELINE_RUNS;
```

```sql
SELECT *
FROM V_PIPELINE_RUNS
ORDER BY START_TIME DESC
LIMIT 50;
```

The observability project is successful when an operator can determine pipeline health, impact, probable failure domain, and recovery status without manually reconstructing the entire execution history.

---

## 51. What You Built

You now have a reusable Snowflake pipeline observability framework containing:

```text
Pipeline registry
Pipeline run telemetry
Failure logging
Latest-status monitoring
Runtime monitoring
Freshness monitoring
Missing-run detection
Long-running detection
Throughput metrics
Failure-rate metrics
Task monitoring
CDC stream monitoring
Query-history investigation
Warehouse-load analysis
Credit monitoring
Data-quality integration
SLA/SLO reporting
Alert candidate views
Dashboard-ready datasets
Failure-injection tests
Incident runbooks
Production acceptance criteria
```

This turns the pipelines created in earlier chapters into operationally supportable production workloads.

---

## 52. Key Takeaways

1. Pipeline observability must measure **data outcomes**, not only compute availability.
2. A successful task does not guarantee fresh or correct data.
3. `RUN_ID` and Snowflake `QUERY_ID` provide critical correlation during incidents.
4. Monitor runtime, throughput, freshness, backlog, correctness, reliability, and cost together.
5. Use near-real-time metadata sources for active troubleshooting and understand latency in Account Usage views.
6. CDC pipelines require explicit stream and staleness monitoring.
7. Cost regressions are operational regressions too.
8. Alerts should represent actionable conditions tied to owners and runbooks.
9. Observability must be validated through controlled failure injection.
10. Recovery is complete only after pipeline health, freshness, backlog, and data quality return to expected levels.

---

## Next Chapter

**Chapter 90 — Snowflake Production Pipeline Reliability & Recovery Project**
