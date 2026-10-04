# 16 — Snowpipe

## Overview

Snowpipe provides continuous, serverless ingestion of files into Snowflake.

Unlike a traditional batch process where an operator or scheduled job executes `COPY INTO`, Snowpipe can automatically detect newly arrived files and load them into a Snowflake table.

A common production flow is:

```text
Application / Source
        |
        v
Cloud Object Storage
(S3 / Azure Blob / GCS)
        |
        v
Storage Event Notification
        |
        v
Snowpipe
        |
        v
Snowflake Table
```

Snowpipe is designed for frequent ingestion of relatively small batches of files where lower data-arrival latency is required.

---

## 1. Snowpipe vs COPY INTO

Both Snowpipe and `COPY INTO` ultimately load staged files into Snowflake tables, but their operational models are different.

| Feature | COPY INTO | Snowpipe |
|---|---|---|
| Execution | User/job initiated | Continuous/event driven |
| Compute | Virtual warehouse | Snowflake-managed serverless compute |
| Typical workload | Batch loading | Continuous file ingestion |
| Scheduling | External scheduler/task | Event notification |
| Latency | Depends on batch schedule | Near-continuous |
| Compute management | Customer manages warehouse | Snowflake manages compute |

Use `COPY INTO` when predictable batch ingestion is sufficient.

Use Snowpipe when files continuously arrive in object storage and should be loaded without waiting for the next batch job.

---

## 2. Snowpipe Components

A typical Snowpipe implementation contains:

```text
Source files
     |
     v
External Stage
     |
     +---- Storage Integration
     |
     +---- File Format
     |
     v
Pipe Object
     |
     v
Target Table
```

The primary objects are:

- target table
- file format
- stage
- storage integration
- pipe

For automated ingestion, the cloud storage platform also sends event notifications when new files arrive.

---

## 3. Create the Target Table

Example:

```sql
CREATE OR REPLACE TABLE raw.orders (
    order_id       NUMBER,
    customer_id    NUMBER,
    order_date     TIMESTAMP_NTZ,
    order_amount   NUMBER(12,2)
);
```

Verify:

```sql
DESC TABLE raw.orders;
```

---

## 4. Create the File Format

Example CSV format:

```sql
CREATE OR REPLACE FILE FORMAT raw.orders_csv_format
    TYPE = CSV
    FIELD_DELIMITER = ','
    SKIP_HEADER = 1
    FIELD_OPTIONALLY_ENCLOSED_BY = '"'
    NULL_IF = ('NULL', 'null', '');
```

Verify:

```sql
DESC FILE FORMAT raw.orders_csv_format;
```

File formats should normally be created as reusable named objects rather than repeatedly embedding format configuration inside ingestion commands.

---

## 5. Create the External Stage

The exact configuration depends on the cloud platform.

Conceptually:

```sql
CREATE OR REPLACE STAGE raw.orders_stage
    URL = '<cloud-storage-location>'
    STORAGE_INTEGRATION = <storage_integration>
    FILE_FORMAT = raw.orders_csv_format;
```

Verify the stage:

```sql
DESC STAGE raw.orders_stage;
```

List available files:

```sql
LIST @raw.orders_stage;
```

Before creating Snowpipe, confirm that Snowflake can successfully access and list the expected files.

---

## 6. Create the Pipe

A pipe contains the `COPY INTO` statement Snowflake uses to ingest files.

Example:

```sql
CREATE OR REPLACE PIPE raw.orders_pipe
    AUTO_INGEST = TRUE
AS
COPY INTO raw.orders
FROM @raw.orders_stage;
```

Inspect the pipe:

```sql
DESC PIPE raw.orders_pipe;
```

You can also list pipes:

```sql
SHOW PIPES IN SCHEMA raw;
```

---

## 7. AUTO_INGEST

The important property in an automated Snowpipe configuration is:

```sql
AUTO_INGEST = TRUE
```

This enables event-driven ingestion.

The cloud storage platform sends notifications when new files arrive.

```text
New file uploaded
       |
       v
Cloud storage
       |
       v
Event notification
       |
       v
Snowpipe notification endpoint
       |
       v
Pipe executes load
       |
       v
Target table
```

The cloud-specific notification configuration must be completed correctly for automatic ingestion to work.

---

## 8. Validate the Pipe

Check the pipe definition:

```sql
SHOW PIPES LIKE 'ORDERS_PIPE';
```

Inspect details:

```sql
DESC PIPE raw.orders_pipe;
```

One important value returned by Snowflake is the notification configuration required for the cloud integration.

The exact configuration differs between AWS, Azure, and Google Cloud.

---

## 9. Check Snowpipe Status

Snowflake provides `SYSTEM$PIPE_STATUS`.

```sql
SELECT SYSTEM$PIPE_STATUS('RAW.ORDERS_PIPE');
```

For easier inspection:

```sql
SELECT PARSE_JSON(
    SYSTEM$PIPE_STATUS('RAW.ORDERS_PIPE')
);
```

This should be one of the first commands used when troubleshooting a Snowpipe ingestion problem.

---

## 10. Validate Loaded Data

```sql
SELECT COUNT(*)
FROM raw.orders;
```

```sql
SELECT *
FROM raw.orders
ORDER BY order_date DESC
LIMIT 20;
```

Never validate ingestion only by confirming that the pipe exists.

Validate all three layers:

```text
File arrived
      |
      v
Pipe processed file
      |
      v
Expected rows exist
```

---

## 11. COPY_HISTORY

Load history is essential for operational troubleshooting.

```sql
SELECT *
FROM TABLE(
    INFORMATION_SCHEMA.COPY_HISTORY(
        TABLE_NAME => 'RAW.ORDERS',
        START_TIME => DATEADD('hour', -1, CURRENT_TIMESTAMP())
    )
)
ORDER BY LAST_LOAD_TIME DESC;
```

This helps determine which files were processed, whether a load succeeded, whether errors occurred, how many rows were loaded, and when ingestion occurred.

---

## 12. Snowpipe File Tracking

Snowpipe tracks files that have already been loaded. This prevents normal repeated event notifications from blindly inserting the same staged file again.

Use immutable, unique object names:

```text
orders/2026/10/04/orders_20261004_120001_001.csv
orders/2026/10/04/orders_20261004_120001_002.csv
orders/2026/10/04/orders_20261004_120501_001.csv
```

Avoid continuously overwriting:

```text
orders/latest.csv
```

Immutable file naming makes ingestion, auditing, replay, and incident investigation easier.

---

## 13. Refresh a Pipe

If files already exist in the stage but were not queued through event notifications:

```sql
ALTER PIPE raw.orders_pipe REFRESH;
```

A path can also be targeted:

```sql
ALTER PIPE raw.orders_pipe
REFRESH PREFIX = '2026/10/04/';
```

`REFRESH` should not become the normal ingestion mechanism. If operators repeatedly need it, investigate the event-notification architecture.

---

## 14. Pause and Resume Snowpipe

Pause:

```sql
ALTER PIPE raw.orders_pipe
SET PIPE_EXECUTION_PAUSED = TRUE;
```

Check status:

```sql
SELECT SYSTEM$PIPE_STATUS('RAW.ORDERS_PIPE');
```

Resume:

```sql
ALTER PIPE raw.orders_pipe
SET PIPE_EXECUTION_PAUSED = FALSE;
```

Pausing can be useful during controlled maintenance, downstream incidents, schema remediation, ingestion investigations, and cutovers.

---

## 15. Production Troubleshooting Flow

Troubleshoot from the source toward Snowflake:

```text
1. Was the file created?
          |
          v
2. Is it present in cloud storage?
          |
          v
3. Can Snowflake see it through the stage?
          |
          v
4. Was an event notification generated?
          |
          v
5. Is the pipe running?
          |
          v
6. Was the file processed?
          |
          v
7. Did COPY encounter an error?
          |
          v
8. Did rows reach the target table?
```

### Step 1 — Verify stage access

```sql
LIST @raw.orders_stage;
```

### Step 2 — Check pipe status

```sql
SELECT SYSTEM$PIPE_STATUS('RAW.ORDERS_PIPE');
```

### Step 3 — Inspect load history

```sql
SELECT *
FROM TABLE(
    INFORMATION_SCHEMA.COPY_HISTORY(
        TABLE_NAME => 'RAW.ORDERS',
        START_TIME => DATEADD('hour', -4, CURRENT_TIMESTAMP())
    )
)
ORDER BY LAST_LOAD_TIME DESC;
```

### Step 4 — Validate the target

```sql
SELECT COUNT(*)
FROM raw.orders;
```

### Step 5 — Compare source and target

Check expected files, processed files, failed files, expected rows, and loaded rows.

This separates storage problems, notification problems, Snowpipe problems, file-format problems, and downstream data-quality problems.

---

## 16. Common Snowpipe Problems

### Files exist but data is not loading

Check:

```sql
LIST @raw.orders_stage;
SELECT SYSTEM$PIPE_STATUS('RAW.ORDERS_PIPE');
```

Then inspect `COPY_HISTORY`.

Possible causes include:

- incorrect stage path
- broken event notification
- storage integration permissions
- paused pipe
- malformed files
- file format mismatch
- incorrect pipe definition

### Pipe exists but receives no events

Verify the cloud notification integration. A healthy Snowflake pipe cannot ingest automatically if the upstream notification never reaches it.

### File is visible but was not loaded

Check whether Snowflake already considers the file processed, then inspect `COPY_HISTORY`.

### Rows are rejected

Common causes include bad delimiters, incorrect quoting, invalid timestamps or numeric values, unexpected column counts, schema drift, and malformed JSON.

---

## 17. Monitoring Snowpipe

A production monitoring strategy should cover:

```text
File arrival
    +
Pipe health
    +
Load failures
    +
Ingestion latency
    +
Target freshness
    +
Cost
```

Monitoring only whether the pipe is running is insufficient.

A stronger application-level freshness check is:

```sql
SELECT MAX(order_date)
FROM raw.orders;
```

For ingestion-controlled tables, an explicit ingestion timestamp can provide better freshness monitoring.

---

## 18. File Size and Ingestion Design

Avoid designing continuous ingestion around extremely large files arriving infrequently.

Likewise, avoid producing enormous numbers of tiny files unnecessarily.

Balance file generation frequency, file size, ingestion latency, upstream throughput, operational manageability, and cost.

---

## 19. Snowpipe Cost Model

Snowpipe uses Snowflake-managed serverless compute. You do not provision a dedicated virtual warehouse for the pipe.

However:

```text
Serverless != Free
```

Production teams should monitor Snowpipe consumption and ingestion patterns.

Cost optimization should consider data latency requirements, file generation strategy, and serverless ingestion consumption.

---

## 20. Production Design Pattern

Separate raw ingestion from transformation:

```text
Cloud Storage
      |
      v
Snowpipe
      |
      v
RAW.ORDERS
      |
      v
Transformation / CDC
      |
      v
CURATED.ORDERS
      |
      v
Analytics / Applications
```

Snowpipe handles file arrival. Downstream pipelines handle validation, deduplication, transformations, enrichment, and business rules.

---

## 21. Operational Runbook

When Snowpipe ingestion is delayed:

1. Confirm source produced the expected file.
2. Confirm the file exists in object storage.
3. `LIST` the Snowflake stage.
4. Run `SYSTEM$PIPE_STATUS`.
5. Confirm the pipe is not paused.
6. Inspect `COPY_HISTORY`.
7. Identify failed or missing files.
8. Check storage/event notification configuration.
9. Validate file format and schema compatibility.
10. Confirm rows reached the target.
11. Measure ingestion freshness.
12. Use `REFRESH` only when operationally justified.
13. Document the actual failure domain.

Do not immediately recreate the pipe. Recreating infrastructure before identifying the failure domain can hide useful evidence.

---

## 22. Production Best Practices

Use:

- named file formats
- storage integrations instead of embedded credentials
- unique and immutable object names
- dedicated raw ingestion tables
- `COPY_HISTORY` monitoring
- `SYSTEM$PIPE_STATUS` health checks
- data-freshness monitoring
- cloud event monitoring
- least-privilege RBAC
- controlled pause/resume procedures
- cost monitoring
- replay/recovery procedures

Avoid:

- embedded cloud credentials
- continuously reusing the same filename
- treating `REFRESH` as normal ingestion
- monitoring only the Snowflake pipe
- assuming file arrival means successful row ingestion
- mixing raw ingestion and complex transformations unnecessarily
- recreating a pipe before collecting incident evidence

---

## 23. Hands-On Lab

### Objective

Build and validate a continuous file-ingestion path.

Create a target table, file format, external stage, and pipe.

Then:

1. Upload a valid file.
2. Verify it appears in the stage.
3. Verify Snowpipe processes it.
4. Query `COPY_HISTORY`.
5. Validate target rows.
6. Pause the pipe.
7. Upload another test file.
8. Inspect pipe status.
9. Resume the pipe.
10. Verify ingestion catches up appropriately.

Run the exercise only in a development or lab environment.

---

## 24. Acceptance Criteria

The chapter is complete when you can:

- explain the difference between Snowpipe and `COPY INTO`
- describe Snowpipe's event-driven architecture
- create and inspect a pipe
- explain `AUTO_INGEST`
- check `SYSTEM$PIPE_STATUS`
- inspect `COPY_HISTORY`
- pause and resume a pipe
- explain when `ALTER PIPE ... REFRESH` is appropriate
- troubleshoot missing files systematically
- distinguish storage, notification, pipe, parsing, and target-table failures
- monitor actual ingestion freshness
- explain the serverless cost model
- design an operationally supportable Snowpipe pipeline

---

## Key Takeaways

Snowpipe is an event-driven, serverless file-ingestion service.

For production operations, always think across the complete path:

```text
Producer
   ↓
Cloud Storage
   ↓
Event Notification
   ↓
Stage
   ↓
Snowpipe
   ↓
COPY
   ↓
Target Table
   ↓
Freshness Validation
```

When ingestion fails, identify exactly where that chain broke before making changes.

The next chapter is **Chapter 17 — Snowpipe Streaming**.
