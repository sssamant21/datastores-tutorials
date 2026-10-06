# Chapter 56 --- Snowflake Time Travel

## 56.1 Overview

Snowflake Time Travel provides access to historical data that has been
changed or deleted within a configured retention period.

It is one of Snowflake's most important operational recovery
capabilities.

Time Travel can help recover from:

-   Accidental `DELETE`
-   Incorrect `UPDATE`
-   Incorrect `MERGE`
-   Accidental table drops
-   Accidental schema drops
-   Accidental database drops
-   Application defects that modify data incorrectly
-   ETL pipelines that overwrite valid data

For SREs and DBREs, Time Travel should be treated as a production
recovery capability rather than only a historical-query feature.

## 56.2 Time Travel Concept

A table changes over time, but Time Travel can expose historical states
as long as the requested version remains within the applicable retention
window.

## 56.3 Time Travel Is Not a Traditional Backup

Time Travel is tightly integrated with Snowflake storage and object
lifecycle. A broader recovery strategy can include Time Travel,
Fail-safe, Zero-Copy Cloning, replication, disaster recovery, and
application-level recovery procedures.

## 56.4 Time Travel vs. Fail-safe

Time Travel provides user-accessible historical querying and recovery.
Fail-safe is a separate Snowflake-managed recovery mechanism and is not
a substitute for normal Time Travel operations.

## 56.5 Time Travel Retention Period

The relevant parameter is:

`DATA_RETENTION_TIME_IN_DAYS`

Example:

``` sql
ALTER TABLE CUSTOMER
SET DATA_RETENTION_TIME_IN_DAYS = 7;
```

The supported retention depends on the Snowflake edition and object
type.

## 56.6 Retention Is a Recovery Policy

Select retention based on recovery requirements, incident detection
time, investigation time, business criticality, and storage
implications.

## 56.7 Check Object Retention

``` sql
SHOW TABLES LIKE 'CUSTOMER';
```

Confirm the object's retention configuration and recovery requirement.

## 56.8 Retention Hierarchy

Retention policies can be managed at account, database, schema, and
table levels. Explicitly document intended retention for critical
production objects.

## 56.9 Configure Database Retention

``` sql
ALTER DATABASE PROD_DB
SET DATA_RETENTION_TIME_IN_DAYS = 7;
```

## 56.10 Configure Schema Retention

``` sql
ALTER SCHEMA PROD_DB.CUSTOMER
SET DATA_RETENTION_TIME_IN_DAYS = 7;
```

## 56.11 Configure Table Retention

``` sql
ALTER TABLE PROD_DB.CUSTOMER.CUSTOMER_PROFILE
SET DATA_RETENTION_TIME_IN_DAYS = 7;
```

## 56.12 Permanent, Transient, and Temporary Objects

Object type matters when designing Time Travel policies. Permanent,
transient, and temporary objects do not provide identical recovery
characteristics. Understand these differences before using transient
objects as a cost optimization.

## 56.13 Query Historical Data with AT

``` sql
SELECT *
FROM CUSTOMER
AT (...);
```

`AT` identifies the historical point to query.

## 56.14 Query by Timestamp

``` sql
SELECT *
FROM PROD_DB.CUSTOMER.CUSTOMER_PROFILE
AT (
    TIMESTAMP => '2026-10-06 10:00:00'::TIMESTAMP
);
```

Pay close attention to timestamps and time zones during incidents.

## 56.15 Query with BEFORE

``` sql
SELECT *
FROM CUSTOMER
BEFORE (...);
```

`BEFORE` is particularly useful when you need the state immediately
before a destructive operation.

## 56.16 Query Before a Statement

``` sql
SELECT *
FROM PROD_DB.CUSTOMER.CUSTOMER_PROFILE
BEFORE (
    STATEMENT => '01b12345-0001-abcd-0000-123456789abc'
);
```

Statement-based recovery can be safer than estimating an incident
timestamp.

## 56.17 Why Statement-Based Recovery Is Powerful

Using the destructive query ID allows the recovery team to target the
state immediately before that statement and reduces timestamp ambiguity.

## 56.18 Query Using an Offset

``` sql
SELECT *
FROM CUSTOMER
AT (
    OFFSET => -3600
);
```

For formal production recovery, timestamps or statement IDs are
generally easier to audit.

## 56.19 AT vs. BEFORE

`AT` accesses the state associated with a specified historical point.
`BEFORE` accesses the state immediately before the specified point or
event.

## 56.20 Find the Destructive Query

``` sql
SELECT
    query_id,
    user_name,
    role_name,
    warehouse_name,
    start_time,
    end_time,
    query_type,
    query_text
FROM snowflake.account_usage.query_history
WHERE start_time >= DATEADD('hour', -6, CURRENT_TIMESTAMP())
ORDER BY start_time DESC;
```

Look for unexpected `DELETE`, `UPDATE`, `MERGE`, `TRUNCATE`, `DROP`,
`CREATE OR REPLACE`, ETL, or user activity.

## 56.21 Query History Latency Consideration

`ACCOUNT_USAGE` views can have reporting latency. During an active
incident, use more immediate query-history visibility where available.

## 56.22 Accidental DELETE Scenario

After an accidental DELETE, identify the query ID, verify historical
data, quantify affected records, create a recovery copy, validate it,
and only then restore.

## 56.23 Validate Historical Data

``` sql
SELECT COUNT(*)
FROM CUSTOMER
BEFORE (
    STATEMENT => '<DELETE_QUERY_ID>'
);
```

Compare with:

``` sql
SELECT COUNT(*)
FROM CUSTOMER;
```

## 56.24 Inspect the Missing Rows

``` sql
SELECT *
FROM CUSTOMER
BEFORE (
    STATEMENT => '<DELETE_QUERY_ID>'
)
WHERE STATE = 'NC';
```

## 56.25 Create a Recovery Table First

Prefer the pattern:

Historical version → Recovery table/clone → Validation → Production
restoration.

## 56.26 Create Recovery Data from Historical State

``` sql
CREATE TABLE CUSTOMER_RECOVERY AS
SELECT *
FROM CUSTOMER
BEFORE (
    STATEMENT => '<DELETE_QUERY_ID>'
);
```

## 56.27 Validate Recovery Table

``` sql
SELECT COUNT(*)
FROM CUSTOMER_RECOVERY;
```

Validate row count, business keys, affected population, null
distribution, critical columns, duplicate risk, and application
expectations.

## 56.28 Restore Deleted Rows

``` sql
INSERT INTO CUSTOMER
SELECT r.*
FROM CUSTOMER_RECOVERY r
WHERE NOT EXISTS (
    SELECT 1
    FROM CUSTOMER c
    WHERE c.CUSTOMER_ID = r.CUSTOMER_ID
);
```

Adapt the restoration SQL to the actual table design and business keys.

## 56.29 Why Blind INSERT Is Dangerous

Do not blindly insert the entire recovery table. Legitimate writes may
have occurred after the incident and recovery must avoid duplicates or
overwriting valid changes.

## 56.30 Accidental UPDATE Scenario

An UPDATE without the intended WHERE clause can preserve rows while
corrupting values. Time Travel can expose previous values.

## 56.31 Compare Current and Historical Versions

``` sql
SELECT
    c.CUSTOMER_ID,
    c.STATUS AS CURRENT_STATUS,
    h.STATUS AS PREVIOUS_STATUS
FROM CUSTOMER c
JOIN CUSTOMER
BEFORE (
    STATEMENT => '<UPDATE_QUERY_ID>'
) h
    ON c.CUSTOMER_ID = h.CUSTOMER_ID
WHERE c.STATUS <> h.STATUS;
```

## 56.32 Restore Incorrectly Updated Values

Use a controlled UPDATE or MERGE after validating the historical values
and affected population. Preserve legitimate post-incident changes.

## 56.33 Accidental MERGE Scenario

A faulty MERGE can create incorrect updates, unexpected inserts, missing
matches, or logical duplicates. Understand each mutation category before
recovery.

## 56.34 Historical Zero-Copy Clone

``` sql
CREATE TABLE CUSTOMER_RECOVERY
CLONE CUSTOMER
BEFORE (
    STATEMENT => '<QUERY_ID>'
);
```

## 56.35 Why Historical Cloning Is Valuable

Historical cloning provides a fast, isolated recovery workspace that can
be validated before production changes.

## 56.36 Recovery Clone Naming

Use clear names such as:

-   `CUSTOMER_RECOVERY_INC12345`
-   `CUSTOMER_PRE_DELETE_20261006`
-   `CUSTOMER_RECOVERY_20261006_1030`

## 56.37 Clone at Timestamp

``` sql
CREATE TABLE CUSTOMER_RECOVERY
CLONE CUSTOMER
AT (
    TIMESTAMP => '2026-10-06 10:00:00'::TIMESTAMP
);
```

## 56.38 Database Historical Clone

``` sql
CREATE DATABASE PROD_DB_RECOVERY
CLONE PROD_DB
AT (...);
```

Use broader recovery workspaces where the applicable object and
operation support them.

## 56.39 Schema Historical Clone

``` sql
CREATE SCHEMA CUSTOMER_RECOVERY
CLONE CUSTOMER
AT (...);
```

A schema-level recovery workspace can help when multiple related tables
are affected.

## 56.40 Accidental DROP TABLE

If a dropped object remains within the applicable Time Travel retention
period, Snowflake provides UNDROP capabilities for supported objects.

## 56.41 UNDROP TABLE

``` sql
UNDROP TABLE CUSTOMER;
```

## 56.42 UNDROP SCHEMA

``` sql
UNDROP SCHEMA CUSTOMER_SCHEMA;
```

## 56.43 UNDROP DATABASE

``` sql
UNDROP DATABASE PROD_DB;
```

## 56.44 Name Conflicts During UNDROP

If an object with the same name was recreated after the drop, resolve
the naming conflict carefully. Preserve any valid new object before
restoring the old one.

## 56.45 DROP Recovery Runbook

1.  Confirm the object was dropped.
2.  Identify drop timestamp/query.
3.  Confirm retention eligibility.
4.  Check whether the object name has been reused.
5.  Preserve any new object if necessary.
6.  Execute the appropriate UNDROP operation.
7.  Validate object metadata.
8.  Validate row counts.
9.  Validate permissions and dependencies.
10. Validate application access.
11. Monitor.
12. Document the incident.

## 56.46 Time Travel Storage Impact

Large tables with high UPDATE/DELETE/MERGE activity and longer retention
can create greater historical storage consumption.

## 56.47 Monitor Historical Storage

``` sql
SELECT
    table_catalog,
    table_schema,
    table_name,
    active_bytes,
    time_travel_bytes,
    failsafe_bytes,
    retained_for_clone_bytes
FROM snowflake.account_usage.table_storage_metrics
ORDER BY time_travel_bytes DESC;
```

## 56.48 High-Churn Tables

Frequently updated customer tables, large MERGE targets, CDC targets,
high-volume DELETE/INSERT workloads, and frequently refreshed datasets
can generate significant Time Travel storage.

## 56.49 Retention vs. Storage Tradeoff

Longer retention provides a larger recovery window but can increase
historical storage. Balance recovery objectives, incident detection
time, business criticality, and storage cost.

## 56.50 Do Not Reduce Retention Only to Save Cost

Before reducing retention, evaluate incident detection time, response
time, recovery requirements, alternative recovery mechanisms, and
business impact.

## 56.51 Time Travel and Zero-Copy Cloning

A strong recovery pattern is:

Production Object → Historical Point → Zero-Copy Recovery Clone →
Validation → Selective Restoration.

## 56.52 Time Travel and Transactions

The recovery objective is usually to recover the damage while preserving
valid subsequent changes, not simply restore the entire table to the
past.

## 56.53 Stop Writes or Keep Writes Running?

Stop writes when corruption is continuing or reconciliation is unsafe.
Writes may continue when damage is isolated and recovery can safely
preserve concurrent legitimate activity.

## 56.54 Time Zone Problems

Document incident timestamp, timestamp time zone, session time zone,
query start/end time, and application time zone. Statement-based
recovery reduces ambiguity when the query ID is available.

## 56.55 Historical Data Not Available

Investigate retention expiration, incorrect timestamps, wrong objects,
lifecycle changes, object-type limitations, retention configuration, and
incorrect statement IDs.

## 56.56 Recovery Privileges

Ensure recovery roles can inspect query history, read affected objects,
create recovery objects, clone where required, restore dropped objects
where authorized, and perform controlled restoration.

## 56.57 Time Travel Recovery Role

Use a controlled least-privilege recovery role with audited access for
historical reads, recovery object creation, and controlled restoration.

## 56.58 Production Recovery Safety Rules

-   Never overwrite production blindly.
-   Never assume the incident timestamp.
-   Never restore before validating historical data.
-   Never assume all current rows are corrupted.
-   Never discard legitimate post-incident changes.
-   Never reduce retention during an active incident.
-   Never remove recovery objects before validation completes.
-   Never perform large corrective DML without a rollback strategy.

## 56.59 Recommended Recovery Pattern

Incident detected → Stop faulty process → Identify destructive query →
Verify Time Travel availability → Create historical recovery clone/table
→ Validate recovered state → Determine affected records → Restore
selectively → Validate production/application → Monitor → Document RCA.

## 56.60 Accidental DELETE Recovery Runbook

1.  Stop the faulty process.
2.  Identify and capture the query ID.
3.  Confirm historical state.
4.  Create a recovery object.
5.  Validate current versus historical data.
6.  Restore only missing records.
7.  Validate production and downstream applications.
8.  Monitor.
9.  Document root cause and preventive actions.

Example:

``` sql
CREATE TABLE CUSTOMER_RECOVERY
CLONE CUSTOMER
BEFORE (
    STATEMENT => '<QUERY_ID>'
);
```

## 56.61 Accidental UPDATE Recovery Runbook

1.  Stop the faulty process.
2.  Identify UPDATE query ID.
3.  Query state before the statement.
4.  Create recovery clone/table.
5.  Compare current and historical values.
6.  Identify affected rows/columns.
7.  Preserve legitimate subsequent changes.
8.  Restore through controlled UPDATE/MERGE.
9.  Validate business data and application behavior.
10. Monitor and document.

## 56.62 Accidental DROP Recovery Runbook

1.  Identify the dropped object.
2.  Determine drop time.
3.  Confirm Time Travel eligibility.
4.  Check for name reuse.
5.  Preserve conflicting new objects if necessary.
6.  UNDROP the object.
7.  Validate metadata and data.
8.  Validate grants/dependencies.
9.  Validate application behavior.
10. Monitor and document.

## 56.63 Recovery Validation Checklist

-   Correct historical point identified
-   Query ID verified
-   Recovery object created
-   Row counts validated
-   Business keys validated
-   Duplicate risk checked
-   Legitimate current writes preserved
-   Schema validated
-   Application validated
-   Downstream pipelines validated
-   Security/grants validated where relevant
-   Monitoring normal
-   Faulty process corrected
-   Recovery evidence retained
-   RCA initiated

## 56.64 Time Travel Troubleshooting Checklist

-   Check retention period
-   Check object type
-   Check timestamp and time zone
-   Check statement/query ID
-   Check object name
-   Check whether object was recreated
-   Check privileges
-   Check retention configuration/inheritance
-   Check whether historical state expired
-   Verify the selected point is actually before the incident

## 56.65 SRE/DBRE Time Travel Health Review

Periodically review critical databases, schemas, tables, retention
policies, transient object usage, Time Travel storage, high-churn
tables, recovery privileges, recovery runbooks, recovery testing, and
incident detection latency.

## 56.66 Recovery Drill

``` sql
CREATE TABLE TT_RECOVERY_TEST (
    ID NUMBER,
    STATUS VARCHAR
);

INSERT INTO TT_RECOVERY_TEST
VALUES
    (1, 'ACTIVE'),
    (2, 'ACTIVE'),
    (3, 'ACTIVE');

DELETE FROM TT_RECOVERY_TEST
WHERE ID = 2;
```

Capture the DELETE query ID, then:

``` sql
SELECT *
FROM TT_RECOVERY_TEST
BEFORE (
    STATEMENT => '<DELETE_QUERY_ID>'
);

CREATE TABLE TT_RECOVERY_TEST_RESTORE
CLONE TT_RECOVERY_TEST
BEFORE (
    STATEMENT => '<DELETE_QUERY_ID>'
);

SELECT *
FROM TT_RECOVERY_TEST_RESTORE
ORDER BY ID;
```

## 56.67 Recovery Drill Acceptance Criteria

The drill passes when the destructive query is identified, query ID
captured, historical data queried, recovery object created, deleted
record verified, restoration method documented, privileges confirmed,
recovery time measured, AT versus BEFORE understood, and cleanup
completed.

## 56.68 Time Travel Decision Tree

Determine whether the object still exists. For DML incidents, identify
the destructive statement, query the historical state, create a recovery
object, validate, and selectively restore. For dropped objects,
determine whether they remain within retention and use UNDROP where
supported.

## 56.69 Production Scenario

Assume an ETL deployment executes:

``` sql
DELETE FROM PROD_DB.EMPI.PATIENT
WHERE SOURCE_SYSTEM IS NOT NULL;
```

instead of the intended narrow condition.

Recommended response:

1.  Disable the faulty ETL.
2.  Capture the DELETE query ID.
3.  Verify the historical PATIENT table.
4.  Create a recovery clone.
5.  Compare current versus historical keys.
6.  Identify the deleted population.
7.  Check legitimate writes since the incident.
8.  Restore only missing records.
9.  Validate counts and application behavior.
10. Resume the pipeline and monitor.

Do not immediately replace the entire production table with a historical
version because valid changes may have occurred after the destructive
statement.

## 56.70 Time Travel Production Standards

-   Critical objects have documented retention requirements.
-   Retention aligns with recovery objectives.
-   Critical production objects are not made transient solely for cost
    savings without recovery review.
-   Recovery roles and privileges are pre-established.
-   Destructive query IDs are captured during incidents.
-   Recovery uses isolated clones/tables where practical.
-   Legitimate post-incident writes are preserved.
-   UNDROP procedures are documented.
-   Time zones are documented during incidents.
-   Recovery drills are performed periodically.
-   Historical storage is monitored.
-   Retention changes follow change management.
-   Recovery objects have cleanup procedures.
-   Every recovery produces incident evidence and RCA actions.

## 56.71 Common Time Travel Mistakes

Avoid assuming Time Travel is an unlimited backup, waiting until
retention expires, using incorrect timestamps/time zones, restoring
entire tables unnecessarily, overwriting legitimate changes, blind
INSERTs, ignoring duplicate keys, reducing retention solely for cost
savings, misunderstanding transient objects, discovering missing
privileges during incidents, deleting recovery clones too early,
treating Fail-safe like Time Travel, or running corrective DML before
validation.

## 56.72 Key Takeaways

1.  Time Travel provides access to historical Snowflake data within the
    applicable retention period.
2.  It is a core production recovery capability.
3.  It can help recover from accidental DELETE, UPDATE, MERGE, and
    supported object drops.
4.  `DATA_RETENTION_TIME_IN_DAYS` controls the intended recovery window
    within applicable limits.
5.  Retention should be based on recovery requirements.
6.  `AT` accesses a specified historical point.
7.  `BEFORE` is particularly useful for destructive-statement recovery.
8.  Statement-based recovery can reduce timestamp ambiguity.
9.  Query history is critical for identifying destructive operations.
10. Historical data should be validated before restoration.
11. Recovery clones/tables are safer than immediate production
    modification.
12. Recovery should normally be selective.
13. Legitimate post-incident writes must be preserved.
14. `UNDROP` can restore supported dropped objects within retention.
15. Name conflicts must be handled carefully.
16. Time Travel storage increases with retention and data churn.
17. Retention changes affect recovery capability.
18. Object types have different recovery characteristics.
19. Time Travel and zero-copy cloning form a powerful recovery
    combination.
20. Production recovery procedures should be tested before an incident.

## 56.73 Chapter Completion Checklist

After completing this chapter, you should be able to:

-   Explain Snowflake Time Travel and retention.
-   Configure `DATA_RETENTION_TIME_IN_DAYS`.
-   Understand object-type recovery differences.
-   Query historical data using `AT` and `BEFORE`.
-   Use timestamps, statement IDs, and offsets appropriately.
-   Find destructive queries.
-   Investigate accidental DELETE, UPDATE, and MERGE operations.
-   Create and validate recovery tables/clones.
-   Restore deleted rows and incorrect values selectively.
-   Preserve legitimate post-incident writes.
-   Recover supported dropped tables, schemas, and databases.
-   Handle UNDROP naming conflicts.
-   Analyze Time Travel storage.
-   Balance retention against storage cost.
-   Troubleshoot unavailable historical data.
-   Design recovery privileges and roles.
-   Execute production recovery runbooks.
-   Perform Time Travel recovery drills.
-   Validate recovery readiness.

**Chapter 56 --- Snowflake Time Travel: Complete**
