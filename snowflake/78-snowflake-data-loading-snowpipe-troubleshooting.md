# Chapter 78 --- Snowflake Data Loading / Snowpipe Troubleshooting

## 78.1 Overview

Snowflake ingestion problems can appear as files not loading, files
loading late, missing rows, duplicate data, COPY INTO failures, Snowpipe
failures, stage access errors, file-format errors, schema mismatch, high
ingestion latency, or unexpected ingestion cost.

``` text
SOURCE
   |
   v
CLOUD STORAGE
   |
   v
STAGE
   |
   v
FILE FORMAT
   |
   v
COPY / SNOWPIPE
   |
   v
TARGET TABLE
   |
   v
DOWNSTREAM CONSUMER
```

**Primary rule: Find the layer where data stopped before changing the
pipeline.**

## 78.2 Standard Flow

``` text
DATA MISSING
    |
    v
SOURCE FILE EXISTS?
    |
 +--+--+
 |     |
No    Yes
 |     |
 v     v
SOURCE  FILE IN EXPECTED STORAGE PATH?
ISSUE          |
            +--+--+
            |     |
           No    Yes
            |     |
            v     v
          PATH   STAGE CAN SEE FILE?
          ISSUE       |
                   +--+--+
                   |     |
                  No    Yes
                   |     |
                   v     v
                ACCESS  LOAD HISTORY
                ISSUE       |
                            v
                       COPY / PIPE
                            |
                            v
                       TARGET TABLE
```

## 78.3 Capture Scope

Record environment, pipeline, source system, storage location, stage,
pipe, target table, expected file, expected/actual arrival,
expected/actual rows, incident start, and customer impact.

## 78.4 Example

``` text
Environment: Production
Pipeline: EMPI ingestion
Source: Patient360 export
Stage: @EMPI_STAGE
Pipe: EMPI_PIPE
Target: DAP.L1.EMPI
Expected file: empi_20261007_1400.csv
Expected arrival: 14:05 UTC
Current time: 14:30 UTC
Status: Missing from target
```

## 78.5 Do Not Start with Snowpipe

First verify that the expected source file actually exists. A missing
source file cannot be fixed by restarting or recreating Snowpipe.

## 78.6 Source Questions

Was the file generated, uploaded, complete, named correctly, delivered
to the expected prefix/path, overwritten, or delivered late?

## 78.7 Storage Validation

Verify the object exists in the expected bucket/container, prefix,
folder, region, account, and environment.

## 78.8 Common Path Problem

Expected `prod/empi/2026/10/07/file.csv` but actual path is
`prod/empi/2026/10/7/file.csv`. Small path differences can prevent
expected ingestion.

## 78.9 Snowflake Stage

A stage provides Snowflake access to files used for loading. Stages can
be internal, external, table, or user stages.

## 78.10 LIST

``` sql
LIST @EMPI_STAGE;
```

## 78.11 Prefix Filter

``` sql
LIST @EMPI_STAGE/2026/10/07/;
```

## 78.12 Expected File

If the expected file is not visible, investigate storage path, storage
integration, credentials/permissions, stage URL, encryption, and
environment before troubleshooting COPY or Snowpipe.

## 78.13 Stage Configuration

``` sql
DESC STAGE EMPI_STAGE;
```

Review configured URL, storage integration, file format, and relevant
properties.

## 78.14 Storage Integration

External stages commonly rely on storage integrations. Review the
configured integration when stage access fails.

## 78.15 Show Integrations

``` sql
SHOW INTEGRATIONS;
```

## 78.16 Stage Access Failure

Typical symptoms include access denied, authorization failure, file not
found, inability to list the stage, or inability to read an object.

## 78.17 Access Investigation

Validate storage integration, cloud IAM role/identity, bucket/container
policy, object permissions, stage URL, allowed locations, encryption
configuration, and environment.

## 78.18 File Format Problems

A file can exist and still fail because its contents do not match the
configured format.

## 78.19 Show File Formats

``` sql
SHOW FILE FORMATS;
```

## 78.20 Describe File Format

``` sql
DESC FILE FORMAT EMPI_CSV_FORMAT;
```

## 78.21 Common CSV Problems

Wrong delimiter, unexpected quotes, embedded delimiters, header
mismatch, escape/newline problems, invalid encoding, or wrong column
count.

## 78.22 Common JSON Problems

Malformed JSON, unexpected arrays, schema evolution, invalid characters,
oversized records, unexpected nesting, and mixed data types.

## 78.23 Common Parquet Problems

Unexpected schema, type changes, corrupt files, producer changes, or
nested structure changes.

## 78.24 COPY Validation

Use safe validation before modifying production data where appropriate.

``` sql
COPY INTO DAP.L1.EMPI
FROM @EMPI_STAGE
FILE_FORMAT = (FORMAT_NAME = 'EMPI_CSV_FORMAT')
VALIDATION_MODE = 'RETURN_ERRORS';
```

## 78.25 Basic COPY

``` sql
COPY INTO DAP.L1.EMPI
FROM @EMPI_STAGE
FILE_FORMAT = (FORMAT_NAME = 'EMPI_CSV_FORMAT');
```

## 78.26 Why Load History Matters

Load history helps determine whether a file loaded successfully,
partially loaded, failed, was skipped, or was previously loaded.

## 78.27 COPY_HISTORY

``` sql
SELECT *
FROM TABLE(
    INFORMATION_SCHEMA.COPY_HISTORY(
        TABLE_NAME => 'DAP.L1.EMPI',
        START_TIME => DATEADD('hour', -4, CURRENT_TIMESTAMP())
    )
)
ORDER BY LAST_LOAD_TIME DESC;
```

Validate exact function usage and privileges for the environment.

## 78.28 Important Load Fields

Review file name, stage location, load time, status, rows parsed, rows
loaded, errors, and first error as available.

## 78.29 Failure Categories

Parsing, type conversion, column mismatch, corruption, access, file
format, target constraints, and transformation SQL.

## 78.30 ON_ERROR

Do not change `ON_ERROR` merely to make a pipeline appear successful.

## 78.31 Error-Handling Warning

Understand what rows failed, how many failed, why they failed, and
whether missing rows are acceptable before changing error behavior.

## 78.32 Successful COPY Does Not Guarantee Correct Data

Validate row count, key count, null rate, duplicate count, date range,
expected partitions, and business totals.

## 78.33 Snowpipe

Snowpipe provides continuous file ingestion as files become available
for loading.

## 78.34 Typical Snowpipe Flow

``` text
Producer
   |
   v
Cloud Storage
   |
   v
Cloud Event
   |
   v
Snowpipe
   |
   v
COPY Processing
   |
   v
Target Table
```

## 78.35 Pipe Inventory

``` sql
SHOW PIPES;
```

## 78.36 Pipe Definition

``` sql
DESC PIPE EMPI_PIPE;
```

Review target table, stage, path, COPY statement, auto-ingest
configuration, and integration.

## 78.37 Pipe Status

``` sql
SELECT SYSTEM$PIPE_STATUS('EMPI_PIPE');
```

This is one of the most useful first checks for Snowpipe incidents.

## 78.38 Pipe Status Interpretation

Review execution state, pending files, notification information, last
received/forwarded activity, and fault information where returned.
Interpret status in context.

## 78.39 Pipe Paused

If the pipe is not operating as expected, determine whether it is paused
or otherwise unable to process files.

## 78.40 ALTER PIPE REFRESH

``` sql
ALTER PIPE EMPI_PIPE REFRESH;
```

Use deliberately. Repeated refresh commands are not a substitute for
identifying broken event delivery.

## 78.41 Targeted Recovery

Where supported and appropriate, limit recovery to the affected
path/prefix instead of unnecessarily scanning broad storage locations.

## 78.42 Auto-Ingest Dependency

Automatic Snowpipe ingestion depends on cloud event notification
configuration. If a file exists, the stage sees it, and the pipe is
configured but the file does not load, investigate notification
delivery.

## 78.43 Notification Path

``` text
S3 / Azure Blob / GCS
        |
        v
Cloud Event / Notification
        |
        v
Snowflake Integration
        |
        v
Snowpipe
```

## 78.44 Event Failure Symptoms

If files are visible in the stage and manual COPY works but Snowpipe
does not ingest automatically, investigate the automatic notification
path.

## 78.45 Cloud-Side Checks

Depending on cloud provider, validate event configuration,
queue/topic/subscription, permissions, destination, filters/prefixes,
dead-letter behavior, and delivery failures.

## 78.46 Notification Filters

A pipe expecting `prod/empi/` will not necessarily receive the expected
event when files move to `prod/empi-v2/`.

## 78.47 Snowpipe History

Use Snowflake-provided pipe usage/history interfaces to correlate
ingestion activity, files, and credits during the incident window.

## 78.48 Duplicate Data Investigation

Duplicates can originate from duplicate source files, repeated source
records, pipeline replay, different filenames containing the same data,
downstream MERGE logic, or manual reload.

## 78.49 File Load Metadata

Snowflake tracks loaded-file metadata for COPY/Snowpipe behavior. Do not
assume renaming the same data file guarantees business-level
deduplication.

## 78.50 Reloading / FORCE

Use forced reload behavior with extreme caution in production because it
can create duplicate business data.

## 78.51 File Loaded but Rows Missing

Compare rows in source, rows parsed, rows loaded, errors, and target
rows.

## 78.52 Row Count Validation

``` text
Source file:    1,000,000
Rows parsed:    1,000,000
Rows loaded:      999,940
Difference:            60
```

Investigate the missing 60 rows.

## 78.53 Schema Drift

Schema drift occurs when incoming structure changes while the pipeline
expects the old structure.

## 78.54 Drift Examples

New/removed/reordered columns, VARCHAR↔NUMBER changes, JSON structure
changes, timestamp-format changes, or unexpected nullability.

## 78.55 Schema Drift Symptoms

Sudden failures, conversion errors, column-count mismatch, unexpected
NULLs, shifted data, and downstream failures.

## 78.56 Type Conversion

If a target expects NUMBER but the source sends `UNKNOWN`, loading may
fail or require explicit handling.

## 78.57 Defensive Transformation

``` sql
SELECT TRY_TO_NUMBER($1)
FROM @EMPI_STAGE;
```

Do not silently convert invalid business data without data-quality
requirements.

## 78.58 Timestamp Problems

Timezone changes, format changes, invalid dates, locale differences, and
unexpected epoch units can cause ingestion errors.

## 78.59 Very Small Files

Large numbers of tiny files can reduce ingestion efficiency and increase
operational overhead.

## 78.60 Tiny File Pattern

``` text
1,000,000 files
Each file: 5 KB
```

This is generally less efficient than appropriately sized files.

## 78.61 Very Large Files

Very large files can increase latency and recovery impact because each
file takes longer to produce, transfer, and process.

## 78.62 File Sizing Principle

Use appropriately sized files for the workload and validate current
Snowflake recommendations for the ingestion method in use.

## 78.63 Compression

Compressed files generally reduce storage/network transfer. Ensure
configured format/compression matches the actual file.

## 78.64 Slow Bulk Load

Investigate file count/sizes, compression, warehouse size, concurrent
load, transformation complexity, target design, and cloud-storage
location.

## 78.65 Warehouse for COPY

Traditional `COPY INTO` uses virtual warehouse compute. Investigate
warehouse execution and concurrency when bulk loading is slow.

## 78.66 Shared Load Warehouse

Multiple large COPY and transformation jobs sharing an ETL warehouse can
contend.

## 78.67 Snowpipe Compute

Snowpipe uses Snowflake-managed compute rather than a user-managed
virtual warehouse for continuous file ingestion.

## 78.68 Define Ingestion Latency

Measure file creation → upload → notification → Snowpipe receipt → load
→ consumer visibility.

## 78.69 Latency Breakdown

``` text
File generated:       14:00
Uploaded:             14:01
Notification:         14:01
Snowpipe received:    14:02
Loaded:               14:03
Application visible:  14:20
```

Snowpipe is not the primary cause of this end-to-end delay.

## 78.70 Downstream Processing

After load, check streams, tasks, dynamic tables, transformations, MERGE
jobs, and application caches where applicable.

## 78.71 Streams

If ingestion feeds CDC-style processing, validate stream state and
consumer processing.

## 78.72 Tasks

``` sql
SHOW TASKS;
```

Check task history when downstream transformation is delayed.

## 78.73 End-to-End Principle

Do not stop at COPY success. The requirement is usually that correct
source data becomes available to the consumer within SLA.

## 78.74 Manual COPY Test

If automatic Snowpipe ingestion fails but manual COPY works, storage
access, stage, file format, and target are likely functioning. Focus on
pipe/event/notification behavior. Use a safe test file to avoid
duplicates.

## 78.75 Controlled Test Files

Use a known small test file in nonproduction or a controlled production
test path. Do not repeatedly replay real production files during
diagnosis.

## 78.76 Metadata Latency

Some ACCOUNT_USAGE views have latency. During active incidents, use the
most appropriate near-real-time source available and understand its
latency characteristics.

## 78.77 COPY Query ID

For warehouse-based COPY, capture query ID to correlate query history,
warehouse, runtime, errors, and queueing.

## 78.78 COPY Queueing Example

``` text
COPY total elapsed:      120 sec
Execution:                20 sec
Queued overload:          95 sec
```

The ingestion issue is largely warehouse contention.

## 78.79 COPY Execution Example

``` text
COPY total elapsed:      120 sec
Execution:               115 sec
Queueing:                  0 sec
```

Investigate file layout, warehouse size, transformations, and execution.

## 78.80 Monitor Expected Files

For critical pipelines, monitor whether expected files arrive within
SLA.

## 78.81 Monitor Loaded Files

Do not monitor only source delivery. Monitor successful Snowflake
loading.

## 78.82 Monitor Business Completeness

Examples include expected patient/claims/activity counts, date ranges,
and distinct EMPI counts.

## 78.83 Pipeline SLA

``` text
Source generation:    5 min
Storage delivery:     2 min
Snowflake ingestion:  5 min
Transformation:       5 min
End-to-end SLA:      17 min
```

## 78.84 First 10 Minutes

1.  Confirm business impact.
2.  Identify pipeline and expected file.
3.  Verify source generation and cloud object.
4.  Verify stage visibility.
5.  Check load history and pipe status.
6.  Check errors.
7.  Verify target data.
8.  Check downstream processing.
9.  Record timestamps for each stage.

## 78.85 Missing File Runbook

1.  Identify expected file.
2.  Verify source generation/upload.
3.  Verify storage path/environment/filename.
4.  LIST stage.
5.  Check stage configuration, integration, and cloud permissions.
6.  Restore file delivery.
7.  Validate load, target, and downstream processing.
8.  Document root cause.

## 78.86 COPY Failure Runbook

1.  Capture COPY query ID/error/source file.
2.  LIST stage.
3.  Validate file format/source schema/target schema.
4.  Use safe validation mode.
5.  Identify failing rows.
6.  Determine data vs configuration issue.
7.  Correct and retry safely.
8.  Validate row counts/business data.
9.  Document.

## 78.87 Snowpipe Not Loading Runbook

1.  Identify pipe.
2.  `SHOW PIPES`.
3.  `DESC PIPE`.
4.  Run `SYSTEM$PIPE_STATUS`.
5.  Verify expected file and LIST stage.
6.  Check load history and whether file was already processed.
7.  Check pipe execution state.
8.  Check notification configuration/event delivery/filters/integration
    permissions.
9.  Review errors.
10. Use controlled refresh/recovery if appropriate.
11. Validate file load, target rows, and downstream processing.
12. Monitor next automatic file.
13. Document root cause.

## 78.88 Snowpipe Latency Runbook

Capture file creation, upload, notification, pipe receipt, load
completion, and downstream completion times. Identify the largest
interval before remediation.

## 78.89 Duplicate Data Runbook

1.  Identify duplicate business keys/files.
2.  Check source duplication, filenames, manual reloads, forced COPY,
    refresh history, and downstream MERGE logic.
3.  Determine whether duplication occurred before or after ingestion.
4.  Correct safely.
5.  Validate counts.
6.  Add idempotency controls.

## 78.90 Schema Drift Runbook

1.  Capture failing file.
2.  Compare with last successful file and schemas.
3.  Identify added/removed/changed columns.
4.  Review file format, target schema, and transformation logic.
5.  Determine expected contract.
6.  Coordinate source correction or target evolution.
7.  Test, deploy, replay safely, validate, and add schema monitoring.

## 78.91 Slow COPY Runbook

1.  Capture query ID/warehouse.
2.  Measure queueing/execution.
3.  Review file count/sizes/compression/transformations/concurrent
    workload/warehouse size.
4.  Test controlled optimization.
5.  Measure runtime and credits.
6.  Select best configuration and document.

## 78.92 Patient360 EMPI Pipeline

``` text
Patient360
    |
    v
S3
    |
    v
EMPI_STAGE
    |
    v
EMPI_PIPE
    |
    v
DAP.L1.EMPI
    |
    v
Transformation
    |
    v
DAP.L2.EMPI
```

## 78.93 Incident

Operations reports latest EMPI data missing from `DAP.L2.EMPI`.

## 78.94 Initial Assumption

Do not accept "Snowpipe failed" without evidence.

## 78.95 Investigation

Source confirms generation and storage confirms `empi_20261007_1400.csv`
exists.

## 78.96 Stage Check

``` sql
LIST @EMPI_STAGE;
```

The file is visible.

## 78.97 Pipe Check

``` sql
SELECT SYSTEM$PIPE_STATUS('EMPI_PIPE');
```

The pipe appears operational.

## 78.98 Load History

The file shows loaded into `DAP.L1.EMPI`.

## 78.99 Target Validation

L1 contains expected records; L2 does not.

## 78.100 Root Cause Direction

The ingestion path is working. The problem exists in the L1 → L2
transformation, not Snowpipe.

## 78.101 Lesson

Always determine the exact pipeline boundary where data stopped.

## 78.102 File Visible but Not Auto-Loaded

If the file exists, LIST sees it, manual COPY succeeds, but Snowpipe
does not automatically load it, investigate cloud notification,
notification integration, prefix filtering, and auto-ingest
configuration.

## 78.103 Root Cause Direction

Focus on the notification path rather than file format or target table
first.

## 78.104 COPY Slow

``` text
Total COPY runtime:     180 sec
Execution:               25 sec
Queued overload:        150 sec
```

## 78.105 Root Cause Direction

Warehouse contention is primary. Use Chapter 77 warehouse/concurrency
troubleshooting.

## 78.106 Data Loading RCA Template

``` text
Incident:
Environment:
Pipeline:
Source:
Storage:
Stage:
Pipe:
Target table:
Expected file:
Expected arrival:
Actual arrival:
Source generated:
Storage object present:
Stage visible:
Notification received:
Pipe status:
Load status:
Rows parsed:
Rows loaded:
Errors:
Target validation:
Downstream validation:
Root cause:
Contributing factors:
Immediate mitigation:
Permanent remediation:
Replay required:
Duplicate risk:
Data validation completed:
Preventive monitoring:
Owner:
```

## 78.107 Pipeline Monitoring Layers

Monitor source generation, storage arrival, stage visibility, load
success, pipe health, ingestion latency, row/error counts, downstream
completion, and business completeness.

## 78.108 Useful Alerts

Expected file missing, delayed arrival, COPY failure, Snowpipe fault,
SLA exceeded, low row counts, schema drift, duplicate data, and
downstream task failure.

## 78.109 Idempotency

Every production pipeline should define whether files can be replayed,
duplicate behavior, unique event/record keys, and partial-load handling.

## 78.110 Safe Replay Process

Identify affected files/current state/duplicate risk/rollback;
understand file-load metadata and downstream transformations; replay
controlled scope; validate and monitor.

## 78.111 Do Not Blindly Reload

Never reload all files without understanding current state. A
missing-data incident can become a duplicate-data incident.

## 78.112 Stage Security

Use storage integrations, least privilege, approved cloud identities,
restricted locations, encryption, and network controls where applicable.
Avoid long-lived embedded credentials.

## 78.113 PHI / PII

Do not expose sensitive records in incident tickets, Slack, logs,
screenshots, test files, or troubleshooting output. Use safe identifiers
and masked examples.

## 78.114 Ingestion Cost

Review file frequency/count, Snowpipe usage, warehouse runtime, repeated
loads, retries, replay activity, and downstream processing.

## 78.115 Tiny Files and Cost

Excessive tiny files can increase ingestion overhead. Coordinate
efficient delivery patterns with producers.

## 78.116 Batch vs Continuous

Large scheduled batches commonly fit `COPY INTO`; continuous file
arrival commonly fits Snowpipe. Select based on latency, throughput,
operations, and cost.

## 78.117 Snowpipe Streaming

If using Snowpipe Streaming rather than file-based Snowpipe, use
streaming-specific observability/troubleshooting. Do not apply
file-notification assumptions.

## 78.118 Recommended Standards

Every production ingestion pipeline should define owner, source,
storage, stage, file format, load method, target, frequency, volume,
SLA, retry/replay behavior, duplicate protection, schema contract,
data-quality validation, monitoring, alerting, runbook, and escalation
path.

## 78.119 Common Mistakes

Avoid assuming Snowpipe is broken before checking source/storage/stage;
ignoring file format/load history/pipe status/event notifications/path
filters/downstream processing; blind refresh/replay/FORCE; changing
ON_ERROR to hide bad rows; ignoring parsed-vs-loaded counts, schema
drift, warehouse contention, tiny files, end-to-end timestamps, SLA,
data validation, idempotency, or replay procedures.

## 78.120 Data Loading Troubleshooting Checklist

-   [ ] Business impact and incident window confirmed
-   [ ] Pipeline/source/expected file identified
-   [ ] Cloud object/path verified
-   [ ] Stage identified and LIST completed
-   [ ] Stage/integration/file format reviewed
-   [ ] Target table reviewed
-   [ ] Load history reviewed
-   [ ] COPY query ID/queueing/execution checked where applicable
-   [ ] Pipe/definition/status reviewed
-   [ ] Auto-ingest/notification/filter configuration reviewed
-   [ ] Rows parsed/loaded/errors reviewed
-   [ ] Schema drift and duplicate risk reviewed
-   [ ] Target/downstream data validated
-   [ ] End-to-end latency measured
-   [ ] Root cause identified
-   [ ] Recovery/data quality validated
-   [ ] Preventive monitoring added

## 78.121 Troubleshooting Decision Tree

``` text
DATA MISSING
    |
    v
FILE GENERATED?
    |
 +--+--+
 |     |
No    Yes
 |     |
 v     v
SOURCE  STORAGE OBJECT?
        |
     +--+--+
     |     |
    No    Yes
     |     |
     v     v
 DELIVERY  STAGE LIST?
            |
         +--+--+
         |     |
        No    Yes
         |     |
         v     v
       ACCESS  LOAD HISTORY?
               |
            +--+--+
            |     |
          FAILED LOADED
            |     |
            v     v
         FORMAT/ TARGET DATA?
         SCHEMA      |
                  +--+--+
                  |     |
                 No    Yes
                  |     |
                  v     v
              LOAD     DOWNSTREAM
              ISSUE    PROCESSING
```

## 78.122 Quick Reference

``` sql
LIST @EMPI_STAGE;
DESC STAGE EMPI_STAGE;
SHOW FILE FORMATS;
SHOW PIPES;
DESC PIPE EMPI_PIPE;
SELECT SYSTEM$PIPE_STATUS('EMPI_PIPE');
ALTER PIPE EMPI_PIPE REFRESH;
SHOW TASKS;
SHOW WAREHOUSES;
```

Use recovery commands only after understanding current pipeline state
and duplicate risk.

## 78.123 Data Loading Principles

1.  Missing data does not automatically mean Snowpipe failed.
2.  Start at the source and follow the pipeline forward.
3.  Verify source generation, cloud object, path, and stage visibility.
4.  Validate stage/integration/file format and load history.
5.  Compare rows parsed with rows loaded.
6.  Capture COPY query IDs and separate queueing from execution.
7.  Traditional COPY uses warehouse compute; Snowpipe uses managed
    compute.
8.  Use `SYSTEM$PIPE_STATUS` for Snowpipe investigation.
9.  Verify cloud event delivery for auto-ingest failures.
10. Manual COPY success can isolate notification problems.
11. Do not blindly refresh/replay files.
12. Understand duplicate risk before recovery.
13. Schema drift is a common failure mode.
14. Validate business data after technical success.
15. Measure end-to-end ingestion latency and downstream processing.
16. Monitor expected arrival, load completion, counts, and completeness.
17. Define SLA, idempotency, and safe replay.
18. Avoid inefficient file patterns.
19. Protect credentials and sensitive data.
20. Use evidence to identify the failed layer and add preventive
    monitoring.

## 78.124 Chapter Completion Checklist

After completing this chapter, you should be able to troubleshoot
missing data; validate source generation and storage delivery; inspect
stages/integrations/file formats; validate COPY/load history;
investigate rejected rows; troubleshoot Snowpipe/auto-ingest
notifications; diagnose ingestion latency, schema drift, duplicate data,
and slow COPY; perform safe replay; validate target/downstream
completeness; build ingestion SLAs/monitoring/alerts; create production
recovery procedures; and produce an evidence-based ingestion RCA.

**Chapter 78 --- Snowflake Data Loading / Snowpipe Troubleshooting:
Complete**
