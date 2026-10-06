# Chapter 60 --- Snowflake Accidental DELETE/DROP Recovery Runbook

## 60.1 Overview

This chapter is a production incident runbook for recovering from
accidental Snowflake data deletion or object deletion.

Primary incidents covered:

-   `DELETE`
-   `TRUNCATE TABLE`
-   `DROP TABLE`
-   `DROP SCHEMA`
-   `DROP DATABASE`

The runbook combines Time Travel, Zero-Copy Cloning, Fail-safe, Query
History, selective restoration, and recovery validation.

The objective is to stop further damage, preserve evidence, recover the
correct state, preserve legitimate changes, validate the application,
and prevent recurrence.

## 60.2 Golden Rule

When accidental deletion is detected, **stop the destructive process
first**.

Sequence:

``` text
Stop
  ↓
Preserve
  ↓
Investigate
  ↓
Recover
  ↓
Validate
  ↓
Resume
```

## 60.3 Incident Types

  Incident                     Typical Recovery
  ---------------------------- ---------------------------------
  Accidental DELETE            Time Travel + selective restore
  Accidental TRUNCATE          Historical recovery
  DROP TABLE                   UNDROP
  DROP SCHEMA                  UNDROP
  DROP DATABASE                UNDROP
  Time Travel expired          Fail-safe evaluation
  Repeated pipeline deletion   Stop pipeline + recover
  Unknown deletion source      Query-history investigation

## 60.4 Recovery Priority

Use the least disruptive safe mechanism:

1.  Time Travel query
2.  Historical zero-copy clone
3.  Selective restoration
4.  UNDROP for dropped objects
5.  Source-system replay if appropriate
6.  Fail-safe evaluation if normal recovery expired

Do not restore an entire database for a row-level DELETE.

## 60.5 Incident Severity

Use the organization's severity model. Critical production data loss or
widespread customer impact may warrant the highest severity; limited or
rebuildable datasets may warrant lower severity.

## 60.6 Immediate Response Checklist

-   Declare incident.
-   Stop destructive workload.
-   Disable faulty pipeline/task.
-   Prevent unnecessary manual changes.
-   Identify affected object.
-   Record incident time.
-   Capture query ID, user, role, and warehouse.
-   Determine Time Travel retention.
-   Preserve current state if required.
-   Begin recovery evidence log.

## 60.7 Stop Automated Workloads

Potential sources include Snowflake Tasks, Airflow, dbt, stored
procedures, applications, Kafka consumers, ETL/ELT pipelines, CronJobs,
and manual scripts.

## 60.8 Suspend a Snowflake Task

``` sql
ALTER TASK PROD_DB.PIPELINES.LOAD_PATIENT
SUSPEND;

SHOW TASKS LIKE 'LOAD_PATIENT';
```

## 60.9 Preserve Incident Evidence

Capture incident ID, detection time, estimated incident time, affected
database/schema/object, query ID, user, role, warehouse, query text,
rows affected, pipeline/job, and application impact.

## 60.10 Identify Recent Queries

``` sql
SELECT
    query_id,
    user_name,
    role_name,
    warehouse_name,
    query_type,
    start_time,
    end_time,
    query_text
FROM snowflake.account_usage.query_history
WHERE start_time >= DATEADD('hour', -6, CURRENT_TIMESTAMP())
ORDER BY start_time DESC;
```

Account Usage can have latency; use the appropriate near-real-time
query-history interface when required.

## 60.11 Search for DELETE Statements

``` sql
SELECT
    query_id,
    user_name,
    role_name,
    warehouse_name,
    start_time,
    query_text
FROM snowflake.account_usage.query_history
WHERE start_time >= DATEADD('hour', -24, CURRENT_TIMESTAMP())
  AND query_text ILIKE '%DELETE%'
ORDER BY start_time DESC;
```

Correlate results with the object and incident time.

## 60.12 Search for DROP Statements

``` sql
SELECT
    query_id,
    user_name,
    role_name,
    start_time,
    query_text
FROM snowflake.account_usage.query_history
WHERE start_time >= DATEADD('hour', -24, CURRENT_TIMESTAMP())
  AND query_text ILIKE '%DROP%'
ORDER BY start_time DESC;
```

## 60.13 Search for TRUNCATE

``` sql
SELECT
    query_id,
    user_name,
    role_name,
    start_time,
    query_text
FROM snowflake.account_usage.query_history
WHERE start_time >= DATEADD('hour', -24, CURRENT_TIMESTAMP())
  AND query_text ILIKE '%TRUNCATE%'
ORDER BY start_time DESC;
```

## 60.14 Validate the Destructive Query

Confirm the correct query ID, object, user, timestamp, operation, and
incident before recovery.

## 60.15 Determine Current Row Count

``` sql
SELECT COUNT(*)
FROM PROD_DB.EMPI.PATIENT;
```

Record the result.

## 60.16 Determine Expected Row Count

Use historical Snowflake state, source systems, pipeline metrics,
data-quality dashboards, row-count monitoring, or business
reconciliation. Do not guess.

## 60.17 Verify Time Travel

``` sql
SELECT COUNT(*)
FROM PROD_DB.EMPI.PATIENT
BEFORE (
    STATEMENT => '<DELETE_QUERY_ID>'
);
```

If the historical state is available and valid, customer-controlled
recovery is likely possible.

## 60.18 Inspect Historical Data

``` sql
SELECT *
FROM PROD_DB.EMPI.PATIENT
BEFORE (
    STATEMENT => '<DELETE_QUERY_ID>'
)
WHERE PATIENT_ID IN (
    '<EXPECTED_PATIENT_ID_1>',
    '<EXPECTED_PATIENT_ID_2>'
);
```

Validate business records, not only counts.

## 60.19 Preserve Current Production State

``` sql
CREATE TABLE PROD_DB.EMPI.PATIENT_CURRENT_INC12345
CLONE PROD_DB.EMPI.PATIENT;
```

## 60.20 Why Preserve Current State

Legitimate inserts or updates may have occurred after the destructive
statement. Preserving current state allows historical/current
reconciliation instead of blindly rolling everything back.

## 60.21 Create Historical Recovery Clone

``` sql
CREATE TABLE PROD_DB.EMPI.PATIENT_RECOVERY_INC12345
CLONE PROD_DB.EMPI.PATIENT
BEFORE (
    STATEMENT => '<DELETE_QUERY_ID>'
);
```

Do not modify production yet.

## 60.22 Validate Recovery Clone

``` sql
SELECT COUNT(*)
FROM PROD_DB.EMPI.PATIENT_RECOVERY_INC12345;

SELECT *
FROM PROD_DB.EMPI.PATIENT_RECOVERY_INC12345
WHERE PATIENT_ID = '<PATIENT_ID>';
```

## 60.23 Compare Current vs. Historical

``` sql
SELECT r.*
FROM PROD_DB.EMPI.PATIENT_RECOVERY_INC12345 r
LEFT JOIN PROD_DB.EMPI.PATIENT p
    ON p.PATIENT_ID = r.PATIENT_ID
WHERE p.PATIENT_ID IS NULL;
```

## 60.24 Count Missing Records

``` sql
SELECT COUNT(*) AS missing_rows
FROM PROD_DB.EMPI.PATIENT_RECOVERY_INC12345 r
LEFT JOIN PROD_DB.EMPI.PATIENT p
    ON p.PATIENT_ID = r.PATIENT_ID
WHERE p.PATIENT_ID IS NULL;
```

## 60.25 Validate Business Key

Confirm the actual unique business key. Some datasets may require
composite keys such as `PATIENT_ID + SOURCE_SYSTEM` or
`CLAIM_ID + LINE_NUMBER`.

## 60.26 Create Recovery Delta

``` sql
CREATE TABLE PROD_DB.EMPI.PATIENT_RECOVERY_DELTA_INC12345 AS
SELECT r.*
FROM PROD_DB.EMPI.PATIENT_RECOVERY_INC12345 r
WHERE NOT EXISTS (
    SELECT 1
    FROM PROD_DB.EMPI.PATIENT p
    WHERE p.PATIENT_ID = r.PATIENT_ID
);
```

## 60.27 Validate Recovery Delta

``` sql
SELECT COUNT(*)
FROM PROD_DB.EMPI.PATIENT_RECOVERY_DELTA_INC12345;

SELECT
    PATIENT_ID,
    COUNT(*)
FROM PROD_DB.EMPI.PATIENT_RECOVERY_DELTA_INC12345
GROUP BY PATIENT_ID
HAVING COUNT(*) > 1;
```

## 60.28 Sample Recovery Records

``` sql
SELECT *
FROM PROD_DB.EMPI.PATIENT_RECOVERY_DELTA_INC12345
LIMIT 100;
```

Have appropriate application/data owners validate representative
records.

## 60.29 Restore Deleted Records

After approval:

``` sql
INSERT INTO PROD_DB.EMPI.PATIENT
SELECT *
FROM PROD_DB.EMPI.PATIENT_RECOVERY_DELTA_INC12345;
```

Use explicit columns for actual production restoration where practical.

## 60.30 Prefer Explicit Columns

``` sql
INSERT INTO PROD_DB.EMPI.PATIENT (
    PATIENT_ID,
    SOURCE_SYSTEM,
    FIRST_NAME,
    LAST_NAME,
    STATUS
)
SELECT
    PATIENT_ID,
    SOURCE_SYSTEM,
    FIRST_NAME,
    LAST_NAME,
    STATUS
FROM PROD_DB.EMPI.PATIENT_RECOVERY_DELTA_INC12345;
```

## 60.31 Validate Restored Count

``` sql
SELECT COUNT(*)
FROM PROD_DB.EMPI.PATIENT;
```

Compare pre-incident, post-incident, expected recovery, and final
counts.

## 60.32 Validate Missing Rows Again

``` sql
SELECT COUNT(*) AS remaining_missing_rows
FROM PROD_DB.EMPI.PATIENT_RECOVERY_INC12345 r
LEFT JOIN PROD_DB.EMPI.PATIENT p
    ON p.PATIENT_ID = r.PATIENT_ID
WHERE p.PATIENT_ID IS NULL;
```

Expected result is zero for the defined recovery scope.

## 60.33 Validate Legitimate New Rows

Confirm records created after the incident remain intact.

## 60.34 Application Validation

Validate application lookups, APIs, UI behavior, batch processing,
reports, downstream pipelines, and data shares.

## 60.35 DELETE Recovery Flow

Accidental DELETE → stop workload → capture query ID → verify Time
Travel → preserve current state → historical clone → compare → recovery
delta → validate → selective INSERT → application validation.

# DROP Recovery

## 60.36 Accidental DROP TABLE

``` sql
UNDROP TABLE PROD_DB.EMPI.PATIENT;
```

Use when the table remains recoverable within the applicable Time Travel
window.

## 60.37 Validate Restored Table

``` sql
SELECT COUNT(*)
FROM PROD_DB.EMPI.PATIENT;
```

Validate schema, columns, data, privileges, dependencies, and
application access.

## 60.38 Name Conflict During UNDROP

If another object exists with the same name, determine who created it,
whether it contains valid data, whether it is in use, and whether it can
be safely preserved or renamed. Do not blindly drop it.

## 60.39 Safe Name-Conflict Strategy

Preserve or safely rename the replacement object → UNDROP original →
compare → reconcile.

## 60.40 Accidental DROP SCHEMA

``` sql
UNDROP SCHEMA PROD_DB.EMPI;
```

Validate contained objects and dependencies.

## 60.41 Accidental DROP DATABASE

``` sql
UNDROP DATABASE PROD_DB;
```

Database recovery requires broader validation.

## 60.42 Database Recovery Validation

Validate schemas, tables, views, stages, streams, tasks, pipes,
policies, grants, applications, shares, integrations, and downstream
dependencies.

## 60.43 DROP Recovery Flow

Identify object → capture DROP query → stop conflicting changes → check
Time Travel → resolve name conflicts safely → UNDROP → validate →
application test.

# TRUNCATE Recovery

## 60.44 Accidental TRUNCATE

Treat accidental `TRUNCATE TABLE` as urgent production data loss.

## 60.45 Find TRUNCATE Query ID

``` sql
SELECT COUNT(*)
FROM PROD_DB.EMPI.PATIENT
BEFORE (
    STATEMENT => '<TRUNCATE_QUERY_ID>'
);
```

## 60.46 Create TRUNCATE Recovery Clone

``` sql
CREATE TABLE PROD_DB.EMPI.PATIENT_RECOVERY_INC12345
CLONE PROD_DB.EMPI.PATIENT
BEFORE (
    STATEMENT => '<TRUNCATE_QUERY_ID>'
);
```

## 60.47 Restore After TRUNCATE

If new records were inserted after the TRUNCATE, reconcile current and
historical state before restoration. Do not assume full rollback is
safe.

# Time Travel Expired

## 60.48 Time Travel Not Available

Determine object type, retention policy, incident time, Time Travel
expiration, source replay availability, independent copies, and
Fail-safe eligibility. Do not retry random timestamps.

## 60.49 Evaluate Source Replay

Determine whether upstream data can reconstruct the deleted data,
whether S3/Kafka/source retention is sufficient, whether updates/deletes
are reproducible, and whether replay satisfies RPO/RTO.

## 60.50 Evaluate Fail-safe

For eligible permanent data outside Time Travel, promptly engage
Snowflake Support to evaluate Fail-safe recovery. Capture account,
region, database, schema, table, incident time, query ID, business
impact, desired recovery point, and actions already taken.

## 60.51 Fail-safe Escalation Rule

Do not promise Fail-safe recovery. State that Time Travel is unavailable
and Snowflake is being engaged to determine whether Fail-safe recovery
is possible.

# Large-Scale Recovery

## 60.52 Large Table Recovery

For hundreds of millions/billions of rows or multi-terabyte tables,
avoid unnecessary unrestricted comparisons. Narrow by incident evidence.

## 60.53 Narrow Recovery by Incident Predicate

If the bad DELETE targeted `SOURCE_SYSTEM = 'ABC'`, focus reconciliation
on that predicate where appropriate.

## 60.54 Narrow Recovery by Time

``` sql
WHERE INGESTED_AT >= '<START_TIME>'
  AND INGESTED_AT <  '<END_TIME>'
```

Use evidence-based boundaries.

## 60.55 Narrow Recovery by Batch

``` sql
WHERE BATCH_ID = '<BAD_BATCH_ID>'
```

## 60.56 Recovery Warehouse

``` sql
CREATE WAREHOUSE RECOVERY_WH
WITH
    WAREHOUSE_SIZE = 'MEDIUM'
    AUTO_SUSPEND = 60
    AUTO_RESUME = TRUE;
```

Adjust based on workload.

## 60.57 Why Isolate Recovery Compute

Benefits include protecting production workloads, independent scaling,
cost attribution, recovery monitoring, and reduced concurrency
interference.

## 60.58 Recovery Query Safety

Verify target, source, WHERE clause, business key, SELECT result, row
count, required peer review, and query capture before running large
recovery DML.

## 60.59 SELECT Before DML

Run the equivalent SELECT first wherever practical and confirm exactly
which records will be affected.

## 60.60 Recovery Transactions

``` sql
BEGIN;

-- recovery DML
-- validate

COMMIT;
```

Use `ROLLBACK` when appropriate. Do not assume every large recovery
operation belongs in one enormous transaction.

# Validation

## 60.61 Technical Validation

Validate object existence, schema, columns, data types, permissions, and
dependencies.

## 60.62 Data Validation

Validate row counts, business keys, duplicates, nulls,
missing/unexpected rows, affected columns, and expected ranges.

## 60.63 Duplicate Validation

``` sql
SELECT
    PATIENT_ID,
    COUNT(*)
FROM PROD_DB.EMPI.PATIENT
GROUP BY PATIENT_ID
HAVING COUNT(*) > 1;
```

Adapt to the real business key.

## 60.64 Business Validation

Application/data owners should validate expected patients/customers,
transactions, statuses, balances, and reporting.

## 60.65 Downstream Validation

Validate streams, tasks, dynamic tables, reports, applications, exports,
data shares, ML pipelines, and downstream warehouses.

## 60.66 Resume Workloads Carefully

Recovery validated → pipeline fix validated → resume one workload →
monitor → resume dependent workloads.

## 60.67 Resume Snowflake Task

``` sql
ALTER TASK PROD_DB.PIPELINES.LOAD_PATIENT
RESUME;
```

Monitor subsequent runs.

## 60.68 Post-Recovery Monitoring

Watch row counts, pipeline/task status, application/query errors,
data-quality checks, unexpected DML, and downstream lag.

# Prevention

## 60.69 Why the Incident Happened

RCA should determine whether the cause was an incorrect WHERE clause,
parameter, deployment, pipeline logic, malformed source data, missing
validation, excessive privileges, or insufficient monitoring.

## 60.70 Prevent Mass DELETE

Automated pipelines should compare candidate deletion counts against
expected thresholds and stop/alert on abnormal changes.

## 60.71 Row-Count Guardrail

Calculate candidate row count → compare with threshold → continue when
normal or stop/alert when abnormal.

## 60.72 Use Least Privilege

Do not grant DELETE, TRUNCATE, or DROP on critical production objects to
service roles that do not require those capabilities.

## 60.73 Separate Administrative Roles

Separate read, write, pipeline, DDL, recovery, and
security-administration responsibilities where appropriate.

## 60.74 Monitor Destructive SQL

Alert on large DELETE, TRUNCATE, DROP TABLE/SCHEMA/DATABASE, unexpected
CREATE OR REPLACE, and mass UPDATE against critical data.

## 60.75 Detection Time Matters

Fast detection keeps incidents inside customer-controlled recovery
windows. Detection is part of recovery architecture.

## 60.76 Recovery Drill

``` sql
CREATE TABLE DELETE_RECOVERY_TEST (
    ID NUMBER,
    STATUS VARCHAR
);

INSERT INTO DELETE_RECOVERY_TEST
VALUES
    (1, 'ACTIVE'),
    (2, 'ACTIVE'),
    (3, 'ACTIVE');
```

## 60.77 Simulate Accidental DELETE

``` sql
DELETE FROM DELETE_RECOVERY_TEST
WHERE ID = 2;
```

Capture the query ID.

## 60.78 Create Historical Clone

``` sql
CREATE TABLE DELETE_RECOVERY_TEST_CLONE
CLONE DELETE_RECOVERY_TEST
BEFORE (
    STATEMENT => '<DELETE_QUERY_ID>'
);
```

## 60.79 Identify Missing Record

``` sql
SELECT r.*
FROM DELETE_RECOVERY_TEST_CLONE r
LEFT JOIN DELETE_RECOVERY_TEST c
    ON c.ID = r.ID
WHERE c.ID IS NULL;
```

Expected missing record: `ID = 2`.

## 60.80 Restore Test Record

``` sql
INSERT INTO DELETE_RECOVERY_TEST
SELECT r.*
FROM DELETE_RECOVERY_TEST_CLONE r
WHERE NOT EXISTS (
    SELECT 1
    FROM DELETE_RECOVERY_TEST c
    WHERE c.ID = r.ID
);
```

## 60.81 Validate Drill

``` sql
SELECT *
FROM DELETE_RECOVERY_TEST
ORDER BY ID;
```

Expected IDs: 1, 2, and 3 with `ACTIVE` status.

## 60.82 Drill Acceptance Criteria

The operator should detect deletion, identify query ID, verify Time
Travel, create a recovery clone, identify missing records, restore
selectively, validate, document evidence, clean up, and measure elapsed
recovery time.

# Incident Documentation

## 60.83 Recovery Evidence Template

``` text
Incident ID:
Severity:
Detected at:
Incident occurred at:
Database:
Schema:
Table:
Operation:
Query ID:
User:
Role:
Warehouse:
Rows affected:
Time Travel retention:
Current-state clone:
Recovery clone:
Recovery delta:
Rows restored:
Application validation:
Downstream validation:
Pipeline resumed:
Incident commander:
DBRE/SRE:
RCA owner:
```

## 60.84 Recovery Communication Template

Communicate impact, containment, recovery mechanism, remaining
validation, risk to legitimate post-incident writes, and known/unknown
status. Avoid speculation.

## 60.85 Cleanup

``` sql
DROP TABLE PROD_DB.EMPI.PATIENT_RECOVERY_DELTA_INC12345;
DROP TABLE PROD_DB.EMPI.PATIENT_RECOVERY_INC12345;
DROP TABLE PROD_DB.EMPI.PATIENT_CURRENT_INC12345;
```

Only clean up after approval.

## 60.86 Do Not Clean Up Too Early

Recovery objects may be needed for RCA, audit, validation, support
investigation, and comparison. Assign ownership and expiration.

## 60.87 Production Recovery Checklist

Confirm incident declaration, containment, query/user/role/warehouse
capture, affected object, current-state preservation, Time Travel,
historical clone, clone validation, business key, recovery delta,
duplicate checks, approval, restoration, row/missing-record validation,
legitimate-write preservation, application/downstream validation,
pipeline fix, workload resume, monitoring, evidence, RCA, and cleanup
date.

## 60.88 DELETE Decision Tree

DELETE incident → stop workload → obtain query ID/query history →
determine Time Travel availability → historical clone when available →
compare → build delta → selectively restore → validate. If unavailable,
evaluate source replay and then Fail-safe where eligible.

## 60.89 DROP Decision Tree

DROP incident → identify object → determine Time Travel availability →
resolve name conflict safely → UNDROP → validate object and application.
If unavailable, evaluate alternate recovery/Fail-safe as applicable.

## 60.90 Production Scenario

A production ETL accidentally executes:

``` sql
DELETE FROM PROD_DB.EMPI.PATIENT
WHERE SOURCE_SYSTEM = 'EPIC';
```

Approximately 120 million records are deleted and monitoring detects the
row-count drop within minutes.

Contain the ETL and capture query evidence.

Preserve current state:

``` sql
CREATE TABLE PROD_DB.EMPI.PATIENT_CURRENT_INC90001
CLONE PROD_DB.EMPI.PATIENT;
```

Create historical recovery state:

``` sql
CREATE TABLE PROD_DB.EMPI.PATIENT_RECOVERY_INC90001
CLONE PROD_DB.EMPI.PATIENT
BEFORE (
    STATEMENT => '<DELETE_QUERY_ID>'
);
```

Build a recovery delta:

``` sql
CREATE TABLE PROD_DB.EMPI.PATIENT_DELTA_INC90001 AS
SELECT r.*
FROM PROD_DB.EMPI.PATIENT_RECOVERY_INC90001 r
WHERE r.SOURCE_SYSTEM = 'EPIC'
  AND NOT EXISTS (
      SELECT 1
      FROM PROD_DB.EMPI.PATIENT p
      WHERE p.PATIENT_ID = r.PATIENT_ID
        AND p.SOURCE_SYSTEM = r.SOURCE_SYSTEM
  );
```

Validate delta count, duplicates, representative records, source
reconciliation, and application-owner expectations.

Restore after approval:

``` sql
INSERT INTO PROD_DB.EMPI.PATIENT
SELECT *
FROM PROD_DB.EMPI.PATIENT_DELTA_INC90001;
```

Prefer explicit columns in actual production execution.

Validate expected row count, missing EPIC patients, duplicates,
legitimate post-incident records, and application health. Fix the ETL
predicate before resuming. RCA should address why the predicate passed
validation, why the large DELETE was permitted, whether row-count
thresholds can stop future runs, whether privileges are excessive, and
whether pre-delete validation can be automated.

## 60.91 Common Recovery Mistakes

Avoid continuing recovery while the destructive workload runs, using the
wrong query ID, guessing timestamps unnecessarily, restoring entire
tables unnecessarily, dropping current production before reconciliation,
losing valid writes, using wrong keys, creating duplicates, skipping
application/downstream validation, assuming UNDROP alone completes
recovery, promising Fail-safe, granting excessive privileges, running
unrestricted multi-terabyte comparisons, resuming pipelines before
fixing the root cause, or deleting evidence too early.

## 60.92 Production Standards

Critical data should have documented Time Travel retention and
destructive-operation monitoring. Automated destructive workloads need
guardrails. Pipeline roles should use least privilege. Recovery roles
should be pre-established. Capture query IDs, preserve current state for
major incidents, use historical clones, restore selectively, validate
business keys, prefer explicit columns, preserve legitimate writes,
involve application owners, validate downstream systems, retain
evidence, perform drills, measure recovery time, perform RCA, and assign
owners/expiration to recovery objects.

## 60.93 SRE/DBRE Recovery Quick Reference

1.  **STOP** --- Stop the destructive process.
2.  **IDENTIFY** --- Confirm object, query ID, and timestamp.
3.  **PRESERVE** --- Clone current state when needed.
4.  **VERIFY** --- Test Time Travel.
5.  **CLONE** --- Create historical recovery clone.
6.  **COMPARE** --- Compare current vs. historical.
7.  **DELTA** --- Identify exactly what was lost.
8.  **VALIDATE** --- Validate counts, keys, and duplicates.
9.  **RESTORE** --- Restore only affected data.
10. **TEST** --- Validate application and downstream systems.
11. **RESUME** --- Resume only after root cause is fixed.
12. **MONITOR** --- Watch production closely.
13. **RCA** --- Prevent recurrence.
14. **CLEANUP** --- Remove recovery objects after approval.

## 60.94 Key Takeaways

1.  Stop the destructive process before recovery.
2.  Capture the exact query ID whenever possible.
3.  Time Travel is the primary recovery mechanism for many
    DELETE/TRUNCATE incidents.
4.  Historical clones provide safe recovery workspaces.
5.  Preserve current production state during major incidents when
    needed.
6.  Do not blindly roll production back.
7.  Preserve legitimate post-incident writes.
8.  Restore only affected records whenever practical.
9.  Validate business keys before reconciliation.
10. Prefer explicit column lists for production restoration.
11. UNDROP is the primary customer-controlled recovery mechanism for
    supported dropped objects within the applicable window.
12. Handle name conflicts carefully.
13. Time Travel expiration requires alternate recovery evaluation.
14. Fail-safe is last-resort evaluation, not guaranteed operational
    restore.
15. Narrow large recovery operations by evidence.
16. Isolate recovery compute when useful.
17. Peer-review high-risk recovery SQL where appropriate.
18. Validate applications after data restoration.
19. Validate downstream systems.
20. Do not resume pipelines until the destructive root cause is fixed.
21. Monitor destructive operations proactively.
22. Row-count guardrails can prevent mass-deletion incidents.
23. Least privilege reduces destructive scope.
24. Perform recovery drills before real incidents.
25. Major recovery incidents should produce prevention actions.

## 60.95 Chapter Completion Checklist

After this chapter you should be able to respond to accidental DELETE,
TRUNCATE, DROP TABLE, DROP SCHEMA, and DROP DATABASE incidents; stop
destructive workloads; capture evidence/query IDs; investigate query
history; verify Time Travel; preserve current state; create historical
clones; compare historical/current data; validate business keys; build
recovery deltas; check duplicates; selectively restore records; preserve
legitimate writes; use UNDROP safely; handle name conflicts; evaluate
replay and Fail-safe; recover large tables safely; isolate recovery
compute; validate technical/data/business/application/downstream state;
resume workloads safely; implement destructive-DML guardrails and least
privilege; perform drills; retain evidence; clean up recovery objects;
and execute production DELETE/DROP recovery decision trees.

**Chapter 60 --- Snowflake Accidental DELETE/DROP Recovery Runbook:
Complete**
