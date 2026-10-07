# Chapter 81 --- Snowflake Locks, Transactions & Concurrency

## 81.1 Overview

Snowflake is designed for highly concurrent analytical workloads, but
transactions can still interfere with one another when multiple sessions
modify overlapping data or objects.

Typical production symptoms include:

``` text
Query running much longer than normal
Transaction blocked
UPDATE appears stuck
DELETE appears stuck
MERGE waiting
Concurrent ingestion slows down
Application timeout
Retry storm
Transaction aborted
High TRANSACTION_BLOCKED_TIME
```

A common mistake is to interpret these symptoms as insufficient
warehouse compute.

``` text
Slow query
   |
   +--> Execution?
   +--> Warehouse queue?
   +--> Transaction blocked?
```

**Primary rule: Determine whether the query is executing, queued for
compute, or waiting on another transaction before changing warehouse
capacity.**

## 81.2 Transaction Basics

A transaction is a logical unit of work.

``` text
BEGIN
   |
   v
SQL statements
   |
   +--> INSERT
   +--> UPDATE
   +--> DELETE
   +--> MERGE
   |
   v
COMMIT
```

or:

``` text
BEGIN
   |
   v
SQL statements
   |
   v
ROLLBACK
```

## 81.3 ACID

Transactions are commonly described using:

``` text
Atomicity
Consistency
Isolation
Durability
```

These properties help protect data correctness when multiple operations
occur concurrently.

## 81.4 Autocommit

Many Snowflake sessions operate with autocommit behavior.

``` text
UPDATE table ...
      |
      v
Statement completes
      |
      v
Commit
```

Explicit transactions behave differently:

``` sql
BEGIN;

UPDATE ...;

INSERT ...;

COMMIT;
```

## 81.5 Explicit Transactions

Explicit transactions are useful when multiple operations must succeed
or fail together.

``` sql
BEGIN;

DELETE FROM DAP.L2.EMPI_STAGE
WHERE LOAD_ID = '20261007';

INSERT INTO DAP.L2.EMPI_STAGE
SELECT *
FROM DAP.L1.EMPI_STAGE
WHERE LOAD_ID = '20261007';

COMMIT;
```

Use explicit transactions deliberately.

## 81.6 Long Transactions

Long-running transactions can create operational problems.

``` text
Session begins transaction
        |
        v
UPDATE
        |
        v
Application performs other work
        |
        v
Transaction remains open
        |
        v
Another session attempts conflicting operation
```

The second workload may wait.

## 81.7 Transaction Blocking

``` text
Session A
UPDATE TABLE_A
     |
     v
Transaction remains open
     |
     +-------------------+
                         |
                         v
                    Session B
                    UPDATE TABLE_A
                         |
                         v
                       WAIT
```

## 81.8 Why This Matters

Blocked transactions can produce:

``` text
Application latency
Pipeline delay
Timeouts
Retries
Connection buildup
Downstream SLA failure
```

The original blocking transaction may itself appear healthy.

## 81.9 Blocking vs Warehouse Queueing

Warehouse contention:

``` text
Query
  |
  v
Waiting for compute
```

Transaction blocking:

``` text
Query
  |
  v
Compute available
  |
  v
Waiting for conflicting transaction
```

## 81.10 Critical Metric

In query history, investigate:

``` text
TRANSACTION_BLOCKED_TIME
```

when transaction blocking is suspected.

## 81.11 Example

``` text
TOTAL_ELAPSED_TIME:         65 sec
EXECUTION_TIME:              3 sec
QUEUED_OVERLOAD_TIME:        0 sec
TRANSACTION_BLOCKED_TIME:   61 sec
```

This is not primarily a warehouse-sizing problem.

## 81.12 Wrong Remediation

Do not immediately resize a warehouse because the query took 65 seconds
when nearly all of that time was transaction blocking.

## 81.13 Correct Direction

Investigate:

``` text
Which transaction blocked it?
Which session owns that transaction?
What SQL is running?
How long has the transaction been open?
Is it expected?
Can it safely commit/rollback?
Why was it left open?
```

## 81.14 Query History

``` sql
SELECT
    QUERY_ID,
    USER_NAME,
    ROLE_NAME,
    WAREHOUSE_NAME,
    QUERY_TYPE,
    EXECUTION_STATUS,
    TOTAL_ELAPSED_TIME,
    EXECUTION_TIME,
    QUEUED_OVERLOAD_TIME,
    TRANSACTION_BLOCKED_TIME,
    START_TIME,
    END_TIME,
    ERROR_CODE,
    ERROR_MESSAGE
FROM SNOWFLAKE.ACCOUNT_USAGE.QUERY_HISTORY
WHERE START_TIME >= DATEADD('hour', -2, CURRENT_TIMESTAMP())
ORDER BY START_TIME DESC;
```

## 81.15 Find High Blocking Time

``` sql
SELECT
    QUERY_ID,
    USER_NAME,
    WAREHOUSE_NAME,
    QUERY_TYPE,
    TOTAL_ELAPSED_TIME,
    EXECUTION_TIME,
    TRANSACTION_BLOCKED_TIME,
    START_TIME
FROM SNOWFLAKE.ACCOUNT_USAGE.QUERY_HISTORY
WHERE START_TIME >= DATEADD('hour', -4, CURRENT_TIMESTAMP())
  AND TRANSACTION_BLOCKED_TIME > 0
ORDER BY TRANSACTION_BLOCKED_TIME DESC;
```

## 81.16 Convert Milliseconds

``` sql
SELECT
    QUERY_ID,
    TOTAL_ELAPSED_TIME / 1000 AS TOTAL_SECONDS,
    EXECUTION_TIME / 1000 AS EXECUTION_SECONDS,
    TRANSACTION_BLOCKED_TIME / 1000 AS BLOCKED_SECONDS
FROM SNOWFLAKE.ACCOUNT_USAGE.QUERY_HISTORY
WHERE START_TIME >= DATEADD('hour', -4, CURRENT_TIMESTAMP())
ORDER BY TRANSACTION_BLOCKED_TIME DESC;
```

## 81.17 Blocking Percentage

``` text
blocked percentage =
transaction blocked time
------------------------
total elapsed time
```

## 81.18 Blocking Percentage SQL

``` sql
SELECT
    QUERY_ID,
    TOTAL_ELAPSED_TIME,
    TRANSACTION_BLOCKED_TIME,
    ROUND(
        TRANSACTION_BLOCKED_TIME * 100.0 /
        NULLIF(TOTAL_ELAPSED_TIME, 0),
        2
    ) AS BLOCKED_PCT
FROM SNOWFLAKE.ACCOUNT_USAGE.QUERY_HISTORY
WHERE START_TIME >= DATEADD('hour', -4, CURRENT_TIMESTAMP())
  AND TRANSACTION_BLOCKED_TIME > 0
ORDER BY BLOCKED_PCT DESC;
```

## 81.19 Blocking Example

``` text
Query ID:       01abc...
Total:          120 sec
Execution:        5 sec
Blocked:        114 sec
Blocked %:       95%
```

Direction: transaction investigation.

## 81.20 Common Blocking Workloads

Typical operations include:

``` text
UPDATE
DELETE
MERGE
INSERT
DDL
Table maintenance
ETL
CDC processing
Application writes
```

The exact concurrency behavior depends on the operations and objects
involved.

## 81.21 MERGE

``` sql
MERGE INTO DAP.L2.EMPI T
USING DAP.L1.EMPI S
ON T.EMPI_ID = S.EMPI_ID

WHEN MATCHED THEN
    UPDATE SET
        T.STATUS = S.STATUS

WHEN NOT MATCHED THEN
    INSERT (EMPI_ID, STATUS)
    VALUES (S.EMPI_ID, S.STATUS);
```

Concurrent modifications against overlapping target data can create
contention.

## 81.22 CDC Example

``` text
CDC Pipeline A
     |
     v
MERGE DAP.L2.EMPI
     |
     +------------------+
                        |
CDC Pipeline B          |
     |                  |
     v                  |
MERGE DAP.L2.EMPI ------+
```

If pipelines modify overlapping data concurrently, transaction
contention may occur.

## 81.23 Batch Overlap

``` text
01:00 ETL Batch A starts
01:05 ETL Batch B starts
```

Both modify the same target table.

The schedule itself becomes a contributing factor.

## 81.24 Application Retry Amplification

``` text
Transaction blocked
       |
       v
Application timeout
       |
       v
Retry
       |
       v
More concurrent writes
       |
       v
More contention
```

## 81.25 Retry Principle

Retries should normally use:

``` text
Bounded attempts
Backoff
Jitter
Idempotency
```

Avoid immediate unlimited retries.

## 81.26 Transactions and Application Timeouts

An application timeout does not necessarily mean Snowflake stopped
processing at that point.

Investigate what happened to the underlying Snowflake query and
transaction.

## 81.27 Client Disconnect

Do not assume closing an application request automatically produced the
intended transaction outcome.

Verify transaction/query state.

## 81.28 Open Transaction Risk

Application code such as:

``` text
BEGIN
UPDATE
external API call
business logic
COMMIT
```

keeps the transaction open while unrelated work occurs.

Minimize the duration of the transaction.

## 81.29 Keep Transactions Short

Preferred:

``` text
Prepare data
     |
     v
BEGIN
     |
     v
Required DML
     |
     v
COMMIT
```

Avoid slow external processing inside the transactional window.

## 81.30 User Think Time

Interactive workflows should not unnecessarily hold a transaction open
while waiting for user input.

## 81.31 Large Transactions

Very large transactions can increase runtime, recovery complexity,
conflict window, rollback impact, and operational risk.

## 81.32 Do Not Blindly Split Transactions

Splitting one transaction into many smaller transactions changes
atomicity.

Do this only when the application/data-correctness model allows it.

## 81.33 Transaction Ownership

During an incident, identify:

``` text
User
Role
Application
Warehouse
Query
Pipeline
Session
Transaction
```

This is easier when workloads use dedicated service identities and query
tags.

## 81.34 Query Tags

``` sql
ALTER SESSION SET QUERY_TAG =
'service=patient360;pipeline=empi-cdc;env=prod';
```

## 81.35 Application Identity

Prefer dedicated identities such as:

``` text
SVC_PATIENT360_API
SVC_EMPI_ETL
SVC_REPORTING
```

over one shared service account.

## 81.36 Blocking Investigation Flow

``` text
SLOW QUERY
    |
    v
CHECK TIMING
    |
    +--> QUEUED_OVERLOAD high --> Warehouse
    |
    +--> EXECUTION high --> Query Profile
    |
    +--> TRANSACTION_BLOCKED high --> Transaction investigation
```

## 81.37 First Five Minutes

1.  Capture affected query ID.
2.  Capture start time.
3.  Capture user.
4.  Capture warehouse.
5.  Capture SQL operation.
6.  Check `TRANSACTION_BLOCKED_TIME`.
7.  Identify other writes against the object.
8.  Check recent batch/deployment activity.
9.  Determine customer impact.
10. Avoid resizing without evidence.

## 81.38 Find Concurrent Writes

During the incident window, search query history for INSERT, UPDATE,
DELETE, MERGE, and DDL against the affected workload/object.

## 81.39 Query Text Investigation

``` sql
SELECT
    QUERY_ID,
    USER_NAME,
    ROLE_NAME,
    WAREHOUSE_NAME,
    QUERY_TYPE,
    QUERY_TEXT,
    START_TIME,
    END_TIME,
    EXECUTION_STATUS,
    TRANSACTION_BLOCKED_TIME
FROM SNOWFLAKE.ACCOUNT_USAGE.QUERY_HISTORY
WHERE START_TIME >= DATEADD('hour', -2, CURRENT_TIMESTAMP())
ORDER BY START_TIME;
```

Protect sensitive SQL when sharing incident evidence.

## 81.40 Timeline Analysis

``` text
13:59 MERGE A begins
14:00 MERGE B begins
14:00 B starts waiting
14:03 application timeout
14:04 retry starts
14:05 additional waits
14:08 A commits
14:08 blocked workload proceeds
```

This tells the story far better than simply saying Snowflake was slow.

## 81.41 Blocking Query vs Blocked Query

The blocked query is the victim.

The blocking transaction is the dependency that must be investigated.

## 81.42 Long-Running Does Not Mean Blocking

A query may run for 30 minutes because it is legitimately processing
large data.

Do not cancel it merely because another workload is slow. Establish
causal evidence.

## 81.43 Cancellation

Where approved:

``` sql
SELECT SYSTEM$CANCEL_QUERY('<query_id>');
```

Cancellation is not the default solution to every concurrency incident.

## 81.44 Before Canceling

Determine:

``` text
Who owns the query?
What business process is it?
Is it blocking production?
Will cancellation roll back work?
Can it be safely restarted?
Could cancellation create partial upstream/downstream state?
```

## 81.45 Commit vs Rollback

For an open transaction, the correct resolution may be COMMIT or
ROLLBACK depending on application intent and data correctness.

Do not choose one simply to remove blocking.

## 81.46 Data Correctness First

Incident mitigation must preserve data correctness.

A fast recovery that corrupts business data is not successful recovery.

## 81.47 DDL Concurrency

Schema/object changes can interact with concurrent workloads.

Examples:

``` text
ALTER TABLE
DROP
RENAME
SWAP
Schema deployment
Object replacement
```

Coordinate production DDL with active data pipelines.

## 81.48 Deployment Window

Avoid high-risk schema changes during known peak write windows unless
designed and tested for that concurrency.

## 81.49 ETL Scheduling

Bad:

``` text
01:00 Customer load
01:00 EMPI MERGE
01:00 Claims MERGE
01:00 Maintenance
```

Better, when business SLAs permit:

``` text
01:00 EMPI
01:30 Claims
02:00 Maintenance
```

## 81.50 Workload Isolation

Separate warehouses can help compute contention:

``` text
ETL_WH
APP_WH
BI_WH
```

but warehouse separation does not automatically eliminate transaction
conflicts against the same data.

## 81.51 Important Distinction

Two warehouses can still run operations that contend against overlapping
target data.

Compute isolation and transaction isolation are different concepts.

## 81.52 Multi-Cluster Warehouse

Multi-cluster warehouses can improve compute concurrency for appropriate
workloads.

They are not a universal solution for transaction blocking.

## 81.53 Scale Up

Increasing warehouse size can improve execution performance when compute
is the bottleneck.

It does not remove a logical transaction dependency.

## 81.54 Transaction Design

Ask:

``` text
What must be atomic?
What can be prepared before BEGIN?
What data can overlap?
How long is the transaction?
What happens on retry?
Is the operation idempotent?
```

## 81.55 Idempotency

A retry should not accidentally create duplicate inserts, duplicate
business events, repeated billing, or repeated state transitions.

## 81.56 MERGE and Idempotency

A properly designed MERGE can support idempotent ingestion patterns, but
correctness depends on stable business keys, source uniqueness, matching
conditions, duplicate-source handling, and update semantics.

## 81.57 Duplicate Source Keys

``` sql
SELECT
    EMPI_ID,
    COUNT(*) AS CNT
FROM DAP.L1.EMPI
GROUP BY EMPI_ID
HAVING COUNT(*) > 1;
```

## 81.58 Transaction Failures

Determine which statement failed, whether the transaction rolled back,
whether the application retried, and whether external side effects
already occurred.

## 81.59 External Side Effects

Snowflake transactions, Kafka events, and API calls do not automatically
behave as one distributed transaction.

Design failure/retry handling explicitly.

## 81.60 Stored Procedures

Stored procedures may contain multiple DML operations.

Inspect transaction boundaries rather than treating the procedure as an
opaque operation.

## 81.61 Task Concurrency

Scheduled tasks can create unexpected write overlap.

Investigate task schedule, duration, previous-run duration, overlapping
pipelines, and target objects.

## 81.62 Task History

Use Snowflake task-history interfaces to correlate scheduled execution
with blocking incidents.

## 81.63 Streams and CDC

Concurrency design must consider consumer pattern, transaction
boundaries, MERGE target, task scheduling, and retry behavior.

## 81.64 Multiple Consumers

Do not assume multiple consumers can independently mutate the same
target without coordination.

## 81.65 Application Connection Pools

``` text
10 application pods
x
30 DB connections
=
300 potential sessions
```

This does not mean all 300 should perform concurrent writes.

## 81.66 Bound Write Concurrency

Control application-side write concurrency when appropriate.

More concurrent writers do not always mean more throughput.

## 81.67 Retry Storm Example

``` text
50 blocked requests
       |
       v
50 timeouts
       |
       v
50 retries
       |
       v
100 outstanding requests
       |
       v
More contention
```

## 81.68 Backoff

Use bounded exponential backoff where appropriate and add jitter to
avoid synchronized retries.

## 81.69 Timeout Design

Coordinate timeouts across application, driver, load balancer, API,
Snowflake operation, and orchestration system.

Misaligned timeouts can create orphaned or repeated work.

## 81.70 Incident Metrics

Capture:

``` text
Blocked query count
Transaction blocked time
Application latency
Application timeout count
Retry count
Concurrent writes
Affected tables
Warehouse queue time
Execution time
```

## 81.71 Baseline

Know normal write duration, transaction blocked time, concurrent
writers, MERGE duration, and batch overlap.

## 81.72 Alerting

Consider alerting on sustained abnormal transaction blocked time,
blocked query count, write latency, application timeout rate, retry
rate, and pipeline SLA delay.

## 81.73 Do Not Alert on Every Wait

Brief waits may be normal.

Alert on sustained or impactful contention.

## 81.74 Patient360 Scenario

At 14:00:

``` text
Patient360 write operations increase from 2 sec to 45 sec.
```

Initial assumption: Snowflake warehouse is overloaded.

## 81.75 Timing Evidence

``` text
Total elapsed:             46 sec
Execution:                  2 sec
Queued overload:            0 sec
Transaction blocked:       43 sec
```

## 81.76 Finding

At 13:59 `EMPI_BATCH_MERGE` began modifying the same target used by the
application write workflow.

## 81.77 Additional Finding

Application timeout of 30 seconds caused retries while the original
workload remained blocked.

## 81.78 Root Cause

A scheduled EMPI batch and an application write workload created
conflicting transaction activity against overlapping target data.

## 81.79 Contributing Factor

Application retry behavior amplified concurrency after requests timed
out.

## 81.80 Immediate Mitigation

Depending on business priority and transaction safety:

``` text
Pause/resequence noncritical batch
Allow blocking transaction to complete
Reduce application retry amplification
```

Do not blindly cancel the blocking transaction.

## 81.81 Permanent Remediation

Possible actions:

``` text
Separate write windows
Reduce transaction duration
Improve batch partitioning
Bound application write concurrency
Use backoff/jitter
Improve idempotency
Add blocking monitoring
Document workload ownership
```

## 81.82 Batch Overlap Runbook

1.  Capture affected queries.
2.  Check transaction blocked time.
3.  Identify concurrent write workloads.
4.  Identify target objects.
5.  Build timeline.
6.  Determine blocking workload.
7.  Determine business priority.
8.  Determine safe commit/rollback/cancel options.
9.  Mitigate minimum workload.
10. Validate data.
11. Validate application latency.
12. Review scheduling.
13. Prevent recurrence.

## 81.83 Application Write Runbook

1.  Capture application request ID.
2.  Capture Snowflake query ID.
3.  Compare app latency with Snowflake timing.
4.  Check transaction blocked time.
5.  Check query execution time.
6.  Check warehouse queueing.
7.  Check concurrent writers.
8.  Check application retries.
9.  Check connection-pool concurrency.
10. Determine transaction boundary.
11. Mitigate.
12. Validate data correctness.
13. Monitor.

## 81.84 MERGE Blocking Runbook

1.  Identify MERGE query.
2.  Identify target table and source.
3.  Check start time and transaction blocked time.
4.  Find concurrent target writers.
5.  Determine overlap.
6.  Review batch schedule and transaction duration.
7.  Review retry behavior.
8.  Apply safe mitigation.
9.  Validate target data.
10. Adjust scheduling/design.

## 81.85 Long Transaction Runbook

1.  Identify transaction owner/session/application.
2.  Determine start time and statements.
3.  Determine whether transaction is expected.
4.  Identify blocked workloads and business impact.
5.  Contact workload owner.
6.  Determine correct commit/rollback/cancel action.
7.  Apply approved action.
8.  Validate data.
9.  Fix application transaction lifecycle.

## 81.86 Retry Storm Runbook

1.  Confirm timeout and retry increase.
2.  Identify original dependency.
3.  Bound new retries.
4.  Add/increase backoff if safe.
5.  Reduce write concurrency if appropriate.
6.  Restore underlying dependency.
7.  Validate outstanding requests.
8.  Check duplicate processing.
9.  Review retry policy.

## 81.87 Cancellation Runbook

Before cancellation:

``` text
[ ] Query identified
[ ] Owner identified
[ ] Business process identified
[ ] Blocking relationship established
[ ] Data impact understood
[ ] Restart/recovery understood
[ ] Approval obtained
```

If cancellation is appropriate:

``` sql
SELECT SYSTEM$CANCEL_QUERY('<query_id>');
```

Afterward validate rollback/state, dependent workloads, and application
recovery, and document the action.

## 81.88 Transaction RCA Template

``` text
Incident:
Environment:
Application:
Pipeline:
Affected object:
Affected query:
Blocked query:
Blocking workload:
Incident start:
Last known good:
First known bad:
Total elapsed time:
Execution time:
Queued overload time:
Transaction blocked time:
Transaction owner:
Application owner:
Warehouse:
Concurrent writers:
Batch schedule:
Application retries:
Connection pool:
Root cause:
Contributing factors:
Immediate mitigation:
Data validation:
Permanent remediation:
Monitoring improvement:
Owner:
Due date:
```

## 81.89 Preventive Controls

Production controls should include:

``` text
Short transactions
Clear workload ownership
Controlled write concurrency
Non-overlapping batch schedules
Idempotent retries
Backoff and jitter
Query tagging
Dedicated service identities
Transaction monitoring
Runbooks
```

## 81.90 Change Management

Before introducing a new writer against an existing production table,
review existing writers, write frequency, transaction duration, batch
windows, MERGE strategy, retry policy, business keys, and idempotency.

## 81.91 Capacity Testing

Test:

``` text
1 writer
5 writers
10 writers
Expected production concurrency
Burst concurrency
Retry behavior
```

## 81.92 Production Testing

Test realistic data volume, write overlap, MERGE behavior, timeouts,
retries, and failure recovery before high-volume production deployment.

## 81.93 Operational Ownership

Every critical write pipeline should document:

``` text
Owner
Schedule
Target tables
Warehouse
Service identity
Expected duration
Retry policy
Recovery procedure
SLA
```

## 81.94 Query Tag Standard

Example:

``` text
env=prod
service=patient360
pipeline=empi-cdc
operation=merge
```

## 81.95 Transaction Monitoring Dashboard

Include:

``` text
Transaction blocked time
Blocked query count
Top blocked workloads
Top writers
MERGE duration
UPDATE duration
DELETE duration
Application timeouts
Retries
Pipeline SLA
```

## 81.96 Blocking Percentage Dashboard

Track:

``` text
Blocked time / Total elapsed time
```

for important write workloads.

## 81.97 Top Blocked Workloads

``` sql
SELECT
    USER_NAME,
    WAREHOUSE_NAME,
    QUERY_TYPE,
    COUNT(*) AS QUERY_COUNT,
    SUM(TRANSACTION_BLOCKED_TIME) / 1000 AS BLOCKED_SECONDS
FROM SNOWFLAKE.ACCOUNT_USAGE.QUERY_HISTORY
WHERE START_TIME >= DATEADD('hour', -4, CURRENT_TIMESTAMP())
  AND TRANSACTION_BLOCKED_TIME > 0
GROUP BY
    USER_NAME,
    WAREHOUSE_NAME,
    QUERY_TYPE
ORDER BY BLOCKED_SECONDS DESC;
```

## 81.98 Top Blocked Users

``` sql
SELECT
    USER_NAME,
    COUNT(*) AS BLOCKED_QUERIES,
    SUM(TRANSACTION_BLOCKED_TIME) / 1000 AS BLOCKED_SECONDS
FROM SNOWFLAKE.ACCOUNT_USAGE.QUERY_HISTORY
WHERE START_TIME >= DATEADD('hour', -4, CURRENT_TIMESTAMP())
  AND TRANSACTION_BLOCKED_TIME > 0
GROUP BY USER_NAME
ORDER BY BLOCKED_SECONDS DESC;
```

## 81.99 Top Blocked Warehouses

``` sql
SELECT
    WAREHOUSE_NAME,
    COUNT(*) AS BLOCKED_QUERIES,
    SUM(TRANSACTION_BLOCKED_TIME) / 1000 AS BLOCKED_SECONDS
FROM SNOWFLAKE.ACCOUNT_USAGE.QUERY_HISTORY
WHERE START_TIME >= DATEADD('hour', -4, CURRENT_TIMESTAMP())
  AND TRANSACTION_BLOCKED_TIME > 0
GROUP BY WAREHOUSE_NAME
ORDER BY BLOCKED_SECONDS DESC;
```

A warehouse appearing here does not prove warehouse capacity caused the
blocking.

## 81.100 Incident Communication

``` text
Current evidence shows the affected writes are spending most of
their elapsed time waiting on transaction blocking rather than
warehouse queueing or SQL execution.

We identified an overlapping batch MERGE against the same target
during the incident window.

The team is validating the safest mitigation while preserving
transaction and data correctness.
```

Avoid saying "Snowflake is locked" without evidence.

## 81.101 Blameless Language

Prefer:

``` text
The batch schedule overlapped the application write window.
```

rather than assigning individual blame.

Focus corrective actions on system design and controls.

## 81.102 Common Mistakes

Avoid:

``` text
Resizing warehouse for transaction blocking
Assuming every slow write is compute
Ignoring TRANSACTION_BLOCKED_TIME
Canceling long queries without causal evidence
Killing a transaction without understanding data impact
Leaving transactions open unnecessarily
Calling external APIs inside long transaction windows
Unlimited retries
Immediate retries without backoff
Unbounded connection pools
Too many concurrent writers
Overlapping heavy MERGE jobs
Assuming separate warehouses eliminate data conflicts
Using ACCOUNTADMIN to troubleshoot application behavior
No query tagging
Shared service identities
No workload owner
No batch schedule documentation
No blocking alerts
No data validation after mitigation
```

## 81.103 SRE/DBRE Checklist

-   [ ] Incident scope captured
-   [ ] Affected query IDs captured
-   [ ] User/role/warehouse captured
-   [ ] Target object/query type identified
-   [ ] Total elapsed/execution/queue/transaction blocked time checked
-   [ ] Blocking percentage calculated
-   [ ] Concurrent writes identified
-   [ ] Batch overlap/task schedules checked
-   [ ] Application retries/connection pool checked
-   [ ] Transaction boundary understood
-   [ ] Business priority established
-   [ ] Blocking workload owner identified
-   [ ] Safe mitigation determined
-   [ ] Cancellation impact reviewed
-   [ ] Data correctness validated
-   [ ] Application recovery validated
-   [ ] Retry amplification stopped
-   [ ] Permanent remediation assigned
-   [ ] Monitoring/runbook updated

## 81.104 Decision Tree

``` text
SLOW WRITE
    |
    v
QUERY HISTORY
    |
    v
WHERE IS TIME?
    |
    +--------------------+
    |                    |
    v                    v
QUEUE HIGH?          BLOCKED HIGH?
    |                    |
   Yes                  Yes
    |                    |
    v                    v
WAREHOUSE            TRANSACTION
CONCURRENCY           INVESTIGATION
                         |
                         v
                 CONCURRENT WRITER?
                         |
                    +----+----+
                    |         |
                   Yes        No
                    |         |
                    v         v
                IDENTIFY    CHECK DDL /
                BLOCKER     SESSION /
                    |       TRANSACTION
                    v
              SAFE MITIGATION
                    |
                    v
              VALIDATE DATA
```

## 81.105 Quick Reference

``` sql
SELECT
    CURRENT_USER(),
    CURRENT_ROLE(),
    CURRENT_WAREHOUSE(),
    CURRENT_DATABASE(),
    CURRENT_SCHEMA();

SELECT
    QUERY_ID,
    USER_NAME,
    WAREHOUSE_NAME,
    QUERY_TYPE,
    TOTAL_ELAPSED_TIME,
    EXECUTION_TIME,
    QUEUED_OVERLOAD_TIME,
    TRANSACTION_BLOCKED_TIME,
    START_TIME
FROM SNOWFLAKE.ACCOUNT_USAGE.QUERY_HISTORY
WHERE START_TIME >= DATEADD('hour', -4, CURRENT_TIMESTAMP())
  AND TRANSACTION_BLOCKED_TIME > 0
ORDER BY TRANSACTION_BLOCKED_TIME DESC;

SELECT
    QUERY_ID,
    ROUND(
        TRANSACTION_BLOCKED_TIME * 100.0 /
        NULLIF(TOTAL_ELAPSED_TIME, 0),
        2
    ) AS BLOCKED_PCT
FROM SNOWFLAKE.ACCOUNT_USAGE.QUERY_HISTORY
WHERE START_TIME >= DATEADD('hour', -4, CURRENT_TIMESTAMP())
  AND TRANSACTION_BLOCKED_TIME > 0
ORDER BY BLOCKED_PCT DESC;

SELECT SYSTEM$CANCEL_QUERY('<query_id>');
```

## 81.106 Key Principles

1.  Slow queries are not always executing slowly.
2.  Separate compute queueing from transaction blocking.
3.  Check `TRANSACTION_BLOCKED_TIME`.
4.  High blocked time is not fixed by warehouse resizing.
5.  Identify both blocked and blocking workloads.
6.  Build a transaction timeline.
7.  Long-running does not automatically mean blocking.
8.  Do not cancel workloads without causal evidence.
9.  Preserve data correctness during mitigation.
10. Keep transaction duration as short as practical.
11. Do slow preparation before opening a transaction where possible.
12. Avoid unnecessary external work inside transactions.
13. Understand transaction boundaries.
14. Coordinate concurrent writers.
15. Overlapping MERGE workloads can create contention.
16. Separate warehouses do not guarantee absence of transaction
    conflicts.
17. Multi-cluster warehouses do not universally solve transaction
    blocking.
18. Bound application write concurrency.
19. Avoid unlimited retries.
20. Use backoff and jitter.
21. Design retries to be idempotent.
22. Coordinate application and Snowflake timeouts.
23. Monitor connection-pool concurrency.
24. Document batch schedules.
25. Avoid unnecessary write-window overlap.
26. Use dedicated service identities.
27. Use query tags.
28. Establish workload ownership.
29. Monitor transaction blocked time.
30. Monitor blocked query count.
31. Compare blocking against workload baseline.
32. Validate data after transaction incidents.
33. Reconcile temporary operational changes.
34. Test concurrent writes before production.
35. Test retry behavior.
36. Test failure recovery.
37. Separate root cause from retry amplification.
38. Keep incident communication evidence based.
39. Keep RCA blameless.
40. Fix transaction design rather than repeatedly treating symptoms.

## 81.107 Chapter Completion Checklist

After completing this chapter, you should be able to:

-   Explain Snowflake transaction fundamentals.
-   Understand explicit and implicit transaction behavior.
-   Distinguish transaction blocking from warehouse queueing.
-   Use transaction blocked time during investigations.
-   Calculate blocking percentage.
-   Identify affected write workloads.
-   Investigate concurrent MERGE/UPDATE/DELETE operations.
-   Build a blocking timeline.
-   Distinguish blocked from blocking workloads.
-   Investigate long-running transactions.
-   Safely evaluate query cancellation.
-   Protect data correctness during mitigation.
-   Understand why warehouse scaling does not solve logical blocking.
-   Understand why separate warehouses do not eliminate data conflicts.
-   Design shorter transaction windows.
-   Control application write concurrency.
-   Design bounded retries with backoff and jitter.
-   Design idempotent retry behavior.
-   Investigate connection-pool amplification.
-   Troubleshoot overlapping batch workloads.
-   Troubleshoot retry storms.
-   Execute blocking, MERGE, long-transaction, retry-storm, and
    cancellation runbooks.
-   Build transaction monitoring dashboards.
-   Produce an evidence-based transaction RCA.
-   Implement preventive transaction/concurrency controls.

**Chapter 81 --- Snowflake Locks, Transactions & Concurrency: Complete**
