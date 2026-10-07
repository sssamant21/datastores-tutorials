# Chapter 83 --- Snowflake Metadata & Cloud Services Performance

## 83.1 Overview

Not every Snowflake performance problem is caused by a virtual
warehouse.

Snowflake also performs work through its cloud services layer for
activities such as:

``` text
Authentication
Metadata management
Query parsing
Query compilation
Query optimization
Access control
Transaction coordination
Infrastructure coordination
```

This creates an important troubleshooting distinction:

``` text
QUERY SLOW
   |
   +--> Warehouse execution?
   |
   +--> Warehouse queueing?
   |
   +--> Transaction blocking?
   |
   +--> Compilation / metadata / cloud services?
   |
   +--> Application / network?
```

**Primary rule: Do not resize a virtual warehouse until you know the
warehouse is actually responsible for the delay.**

## 83.2 Snowflake Architecture

At a high level:

``` text
CLIENT / APPLICATION
        |
        v
+----------------------+
|   CLOUD SERVICES     |
|----------------------|
| Authentication       |
| Metadata             |
| Query optimization   |
| Access control       |
| Coordination         |
+----------------------+
        |
        v
+----------------------+
| VIRTUAL WAREHOUSE    |
|----------------------|
| Query execution      |
| Compute              |
+----------------------+
        |
        v
+----------------------+
| STORAGE              |
+----------------------+
```

This separation is fundamental to Snowflake troubleshooting.

## 83.3 Why This Matters

If a query spends most of its time before warehouse execution begins,
increasing warehouse size may provide little or no improvement.

Example:

``` text
Total elapsed:       30 sec
Compilation:         27 sec
Execution:            2 sec
Queue:                0 sec
```

Direction:

``` text
Compilation / metadata investigation
```

not warehouse scaling.

## 83.4 Query Lifecycle

Conceptually:

``` text
SQL submitted
     |
     v
Authentication / authorization
     |
     v
Parsing
     |
     v
Metadata resolution
     |
     v
Optimization / compilation
     |
     v
Warehouse queue
     |
     v
Execution
     |
     v
Result
```

A delay can occur at different stages.

## 83.5 Start With Query History

``` sql
SELECT
    QUERY_ID,
    USER_NAME,
    ROLE_NAME,
    WAREHOUSE_NAME,
    QUERY_TYPE,
    EXECUTION_STATUS,
    TOTAL_ELAPSED_TIME,
    COMPILATION_TIME,
    EXECUTION_TIME,
    QUEUED_OVERLOAD_TIME,
    QUEUED_PROVISIONING_TIME,
    TRANSACTION_BLOCKED_TIME,
    START_TIME,
    END_TIME
FROM SNOWFLAKE.ACCOUNT_USAGE.QUERY_HISTORY
WHERE START_TIME >= DATEADD('hour', -2, CURRENT_TIMESTAMP())
ORDER BY START_TIME DESC;
```

## 83.6 Compilation Time

A useful signal is:

``` text
COMPILATION_TIME
```

Compilation includes work performed before normal warehouse execution.

## 83.7 Example

``` text
TOTAL_ELAPSED_TIME:      42,000 ms
COMPILATION_TIME:        35,000 ms
EXECUTION_TIME:           5,000 ms
QUEUED_OVERLOAD_TIME:         0 ms
```

The warehouse is not where most of the time is being spent.

## 83.8 Compilation Percentage

``` text
Compilation % =
COMPILATION_TIME
----------------
TOTAL_ELAPSED_TIME
```

## 83.9 Compilation Percentage SQL

``` sql
SELECT
    QUERY_ID,
    WAREHOUSE_NAME,
    TOTAL_ELAPSED_TIME,
    COMPILATION_TIME,
    EXECUTION_TIME,
    ROUND(
        COMPILATION_TIME * 100.0 /
        NULLIF(TOTAL_ELAPSED_TIME, 0),
        2
    ) AS COMPILATION_PCT
FROM SNOWFLAKE.ACCOUNT_USAGE.QUERY_HISTORY
WHERE START_TIME >= DATEADD('hour', -4, CURRENT_TIMESTAMP())
ORDER BY COMPILATION_PCT DESC;
```

## 83.10 Find High Compilation Queries

``` sql
SELECT
    QUERY_ID,
    USER_NAME,
    ROLE_NAME,
    WAREHOUSE_NAME,
    QUERY_TYPE,
    TOTAL_ELAPSED_TIME / 1000 AS TOTAL_SECONDS,
    COMPILATION_TIME / 1000 AS COMPILATION_SECONDS,
    EXECUTION_TIME / 1000 AS EXECUTION_SECONDS,
    START_TIME
FROM SNOWFLAKE.ACCOUNT_USAGE.QUERY_HISTORY
WHERE START_TIME >= DATEADD('hour', -4, CURRENT_TIMESTAMP())
  AND COMPILATION_TIME > 0
ORDER BY COMPILATION_TIME DESC;
```

## 83.11 Compilation Is Not Automatically a Platform Incident

High compilation time for one query can result from query complexity.

Ask:

``` text
One query?
One workload?
Many unrelated queries?
One account?
One time window?
```

## 83.12 Complex SQL

Compilation can become more expensive with highly complex SQL.

Examples:

``` text
Many joins
Deeply nested subqueries
Large UNION trees
Complex views
Nested views
Large generated SQL
Many expressions
Large numbers of referenced objects
```

## 83.13 Generated SQL

Some applications and BI tools generate extremely large SQL statements.

``` text
BI Tool
   |
   v
Generated query
   |
   +--> many CTEs
   +--> many joins
   +--> many predicates
   +--> many columns
```

Compilation itself can become material.

## 83.14 View Expansion

``` text
Application
    |
    v
VIEW_A
    |
    v
VIEW_B
    |
    v
VIEW_C
    |
    v
10 base tables
```

Nested views can increase logical query complexity.

## 83.15 Avoid Excessive View Nesting

Views are useful abstractions, but uncontrolled layering can make SQL
difficult to compile, understand, troubleshoot, optimize, and govern.

## 83.16 Metadata Operations

Metadata-heavy operations may include:

``` text
SHOW commands
DESCRIBE commands
Information Schema queries
Account Usage queries
Object discovery
Catalog crawling
Schema introspection
```

These should not automatically be treated as warehouse execution
problems.

## 83.17 Metadata Crawlers

Common sources:

``` text
BI tools
ETL tools
Data catalogs
Governance platforms
ORMs
Monitoring agents
Custom inventory scripts
```

Some repeatedly scan Snowflake metadata.

## 83.18 Metadata Storm

``` text
100 application instances
        |
        v
Each performs metadata discovery
        |
        v
SHOW / DESCRIBE / catalog queries
        |
        v
Large metadata request volume
```

This can create unnecessary cloud-services activity.

## 83.19 Application Startup Pattern

A poorly designed application may do:

``` text
Connect
  |
  v
SHOW DATABASES
  |
  v
SHOW SCHEMAS
  |
  v
SHOW TABLES
  |
  v
DESCRIBE objects
```

for every new connection.

At large connection counts, this becomes expensive operational behavior.

## 83.20 Connection Pooling Helps

Instead of repeatedly creating connections and rediscovering metadata,
use appropriate connection pooling and application-side caching where
safe.

## 83.21 ORM Behavior

Some frameworks automatically inspect tables, columns, types,
constraints, and schemas during startup or request handling.

Understand what your client libraries actually execute.

## 83.22 Metadata Query Identification

Search query history for SHOW, DESCRIBE, Information Schema, and Account
Usage activity during the incident window.

## 83.23 Query-Type Analysis

``` sql
SELECT
    QUERY_TYPE,
    COUNT(*) AS QUERY_COUNT,
    SUM(TOTAL_ELAPSED_TIME) / 1000 AS TOTAL_SECONDS
FROM SNOWFLAKE.ACCOUNT_USAGE.QUERY_HISTORY
WHERE START_TIME >= DATEADD('hour', -1, CURRENT_TIMESTAMP())
GROUP BY QUERY_TYPE
ORDER BY QUERY_COUNT DESC;
```

## 83.24 User-Level Analysis

``` sql
SELECT
    USER_NAME,
    COUNT(*) AS QUERY_COUNT,
    SUM(COMPILATION_TIME) / 1000 AS COMPILATION_SECONDS
FROM SNOWFLAKE.ACCOUNT_USAGE.QUERY_HISTORY
WHERE START_TIME >= DATEADD('hour', -1, CURRENT_TIMESTAMP())
GROUP BY USER_NAME
ORDER BY COMPILATION_SECONDS DESC;
```

## 83.25 Role-Level Analysis

``` sql
SELECT
    ROLE_NAME,
    COUNT(*) AS QUERY_COUNT,
    SUM(COMPILATION_TIME) / 1000 AS COMPILATION_SECONDS
FROM SNOWFLAKE.ACCOUNT_USAGE.QUERY_HISTORY
WHERE START_TIME >= DATEADD('hour', -1, CURRENT_TIMESTAMP())
GROUP BY ROLE_NAME
ORDER BY COMPILATION_SECONDS DESC;
```

## 83.26 Workload Attribution

Use user, role, application, query tag, client, and query type to
identify who is generating metadata-heavy activity.

## 83.27 Query Tags

``` sql
ALTER SESSION SET QUERY_TAG =
'env=prod;service=metadata-catalog;operation=inventory';
```

## 83.28 Metadata Inventory Jobs

Do not run full-account metadata scans unnecessarily frequently.

``` text
Every minute:
Scan every database
Scan every schema
Scan every table
Scan every column
```

This may provide little operational value while creating avoidable
overhead.

## 83.29 Incremental Metadata Collection

Where supported by the use case, prefer incremental discovery, cached
metadata, scoped discovery, and reasonable refresh intervals over
repeated full-account scans.

## 83.30 Information Schema

Information Schema is useful for metadata inspection.

Broad, repeated queries across large object inventories should be
designed carefully.

## 83.31 Account Usage

Account Usage provides historical operational data useful for query
analysis, login analysis, cost, warehouses, access, tasks, pipes, and
loads.

Remember that historical views may have documented latency. Do not
assume every Account Usage view is real-time.

## 83.32 Incident-Time Data Source

During an active incident, determine whether you need near-real-time
state or historical analysis.

Choose the Snowflake interface accordingly.

## 83.33 SHOW Commands

``` sql
SHOW WAREHOUSES;
SHOW DATABASES;
SHOW SCHEMAS;
SHOW TABLES;
SHOW USERS;
SHOW ROLES;
SHOW PIPES;
SHOW TASKS;
```

Use only the commands needed for the investigation.

## 83.34 DESCRIBE

``` sql
DESC TABLE DAP.L2.EMPI;
DESC PIPE EMPI_PIPE;
```

Avoid indiscriminate metadata polling.

## 83.35 Compilation Baseline

Establish normal compilation time by workload.

``` text
Patient360 API
P95 compilation: 150 ms

BI workload
P95 compilation: 800 ms

Complex ETL
P95 compilation: 2 sec
```

A single universal threshold is rarely appropriate.

## 83.36 Compilation Regression

``` text
Normal P95 compilation:   200 ms
Incident P95:               8 sec
Execution unchanged
```

This requires a different investigation than warehouse contention.

## 83.37 Compare Query Shape

Ask whether SQL text, number of joins, views, generated SQL size, object
count, or predicates changed.

## 83.38 Query Hash

Where appropriate, query hashes can help group logically equivalent or
repeated query patterns for historical comparison.

Use the query-history fields available for the environment.

## 83.39 Compare Same Workload

Do not compare a simple SELECT with a large ETL transformation.

Compare equivalent workload patterns.

## 83.40 DDL and Metadata

Frequent object creation and deletion can produce large metadata churn.

Examples:

``` text
CREATE TABLE
DROP TABLE
CREATE VIEW
DROP VIEW
CREATE TEMP TABLE
DROP TEMP TABLE
```

## 83.41 Temporary Object Explosion

Some pipelines create very large numbers of temporary/transient working
objects.

``` text
JOB_001_TEMP_1
JOB_001_TEMP_2
...
JOB_500_TEMP_20
```

Review whether the object-creation pattern is necessary.

## 83.42 Object Lifecycle

Production pipelines should clean up temporary working objects when they
are no longer required.

## 83.43 Schema Explosion

Avoid uncontrolled patterns such as:

``` text
One schema per request
One table per event
One table per tiny partition
```

unless there is a strong architectural reason.

## 83.44 Object Count Matters Operationally

Very large numbers of objects can increase operational complexity for
discovery, governance, RBAC, cataloging, deployment, and
troubleshooting.

## 83.45 RBAC Complexity

Highly complex role hierarchies and privilege models can also increase
operational difficulty.

Keep access models intentional and documented.

## 83.46 Access Checks

Cloud services participate in access control.

If the application fails before query execution due to authorization,
increasing warehouse size has no value.

## 83.47 Authentication

Authentication occurs outside normal warehouse query execution.

Login, OAuth, key-pair, and SSO failures should not be treated as
warehouse performance incidents.

## 83.48 Cloud Services vs Warehouse

``` text
Cloud services
!=
Virtual warehouse
```

They are separate architectural layers.

## 83.49 Cloud Services Cost

Snowflake pricing includes cloud-services usage considerations.

Operationally, monitor workloads that generate excessive
metadata/control-plane activity and understand the current Snowflake
billing model for the account.

## 83.50 Do Not Optimize Only for Billing

Even where cloud-services usage does not produce a direct incremental
charge under a particular billing threshold/model, inefficient metadata
behavior can still create operational problems.

## 83.51 Service Health

If many unrelated workloads simultaneously show unusual cloud-services
behavior, check Snowflake service health for the account/region.

Do not assume every widespread issue is caused by customer SQL.

## 83.52 Platform-Wide Pattern

``` text
Many warehouses affected
Many unrelated users affected
Compilation increases simultaneously
No common application deployment
No common warehouse
```

This warrants checking broader Snowflake service conditions.

## 83.53 Account-Local Pattern

``` text
One application affected
One service identity
One query pattern
One metadata crawler
Recent deployment
```

Investigate the local workload first.

## 83.54 Network vs Cloud Services

Application connection delay can also originate from DNS, proxy,
firewall, TLS, private connectivity, or identity provider dependencies.

Do not label every pre-execution delay as Snowflake cloud-services
degradation.

## 83.55 Measure End-to-End

``` text
Application request
       |
       v
Connection/authentication
       |
       v
Compilation
       |
       v
Queue
       |
       v
Execution
       |
       v
Fetch
       |
       v
Application processing
```

Measure each layer where possible.

## 83.56 Application Example

``` text
Application request:   20 sec
Snowflake total:        3 sec
```

Direction: application/network/connection/fetch.

## 83.57 Snowflake Example

``` text
Application request:   20 sec
Snowflake total:       18 sec
Compilation:           15 sec
Execution:              2 sec
```

Direction: compilation/query complexity/metadata.

## 83.58 Warehouse Example

``` text
Application request:   20 sec
Snowflake total:       18 sec
Compilation:            1 sec
Queue:                 14 sec
Execution:              2 sec
```

Direction: warehouse concurrency.

## 83.59 Execution Example

``` text
Application request:   20 sec
Snowflake total:       18 sec
Compilation:            1 sec
Queue:                  0 sec
Execution:             16 sec
```

Direction: query execution.

## 83.60 Compilation Incident Runbook

1.  Capture query IDs.
2.  Capture application impact.
3.  Measure total elapsed time.
4.  Measure compilation time.
5.  Measure execution time.
6.  Measure queue time.
7.  Measure transaction blocking.
8.  Compare with baseline.
9.  Identify query pattern.
10. Compare last-known-good SQL.
11. Check recent view/schema changes.
12. Check generated SQL size/complexity.
13. Check metadata activity.
14. Determine scope.
15. Check service health if widespread.
16. Apply minimum safe mitigation.
17. Validate compilation and application latency.

## 83.61 Metadata Storm Runbook

1.  Identify incident window.
2.  Measure query volume.
3.  Group by user.
4.  Group by role.
5.  Group by query type.
6.  Identify SHOW/DESCRIBE/catalog activity.
7.  Identify client/application.
8.  Check connection count.
9.  Check deployment changes.
10. Reduce unnecessary polling.
11. Scope metadata discovery.
12. Add caching where safe.
13. Validate application behavior.
14. Monitor recurrence.

## 83.62 Catalog Tool Runbook

1.  Identify service account.
2.  Identify query tags/client.
3.  Determine scan frequency.
4.  Determine object scope.
5.  Determine query volume.
6.  Compare normal vs incident.
7.  Check recent configuration.
8.  Reduce scan scope/frequency if appropriate.
9.  Validate catalog requirements.
10. Monitor Snowflake impact.

## 83.63 BI Metadata Runbook

Investigate connection count, dashboard users, dataset refresh, schema
discovery, column discovery, startup behavior, and metadata caching.

Coordinate changes with BI owners.

## 83.64 ORM Metadata Runbook

1.  Identify application version.
2.  Identify ORM/driver.
3.  Capture startup SQL.
4.  Identify metadata discovery.
5.  Determine whether discovery occurs per connection/request.
6.  Check connection-pool behavior.
7.  Cache metadata where safe.
8.  Reduce unnecessary discovery.
9.  Validate deployment.
10. Monitor.

## 83.65 Object Churn Runbook

1.  Count object creation/drop activity.
2.  Identify workload owner.
3.  Identify temporary/transient object pattern.
4.  Determine retention/cleanup.
5.  Check failed jobs leaving objects behind.
6.  Review architecture.
7.  Clean up safely.
8.  Prevent unnecessary object creation.
9.  Add lifecycle controls.
10. Monitor growth.

## 83.66 Incident Evidence

Capture query IDs, compilation/execution/queue/blocked time, query
text/pattern, query hash where useful, user, role, application, client,
query tag, metadata query volume, object creation/drop activity, recent
deployments, service health, and application latency.

## 83.67 Before Changing Warehouse Size

Ask:

``` text
Is execution time high?
Is queue time high?
Is compilation time high?
Is transaction blocking high?
```

If compilation dominates, warehouse resizing is unlikely to be the
primary solution.

## 83.68 Before Blaming Snowflake Platform

Ask:

``` text
Is the issue widespread?
Are unrelated workloads affected?
Did a deployment occur?
Did metadata traffic change?
Did SQL complexity change?
Did connection behavior change?
```

## 83.69 Controlled Testing

Reproduce with same SQL, role, application context, environment, and
comparable data.

Avoid changing multiple variables simultaneously.

## 83.70 Compare Before and After

Capture compilation, execution, queue, application latency, query
volume, and metadata volume before and after mitigation.

## 83.71 Patient360 Scenario

Normal:

``` text
Total Snowflake time:     2 sec
Compilation:            150 ms
Execution:              1.5 sec
```

After deployment:

``` text
Total Snowflake time:    12 sec
Compilation:             10 sec
Execution:              1.5 sec
Queue:                    0 sec
```

## 83.72 Investigation

The application deployment introduced dynamically generated SQL
containing significantly more nested views and predicates.

## 83.73 Diagnosis

The regression is primarily compilation/query-complexity related.

The warehouse execution baseline remains normal.

## 83.74 Wrong Mitigation

``` text
Resize warehouse:
MEDIUM -> 2X-LARGE
```

without evidence that warehouse execution is the bottleneck.

## 83.75 Better Mitigation

Depending on the application:

``` text
Rollback SQL generation change
Simplify generated query
Reduce unnecessary view nesting
Restore previous query pattern
```

Then validate compilation time.

## 83.76 Metadata Crawler Scenario

Normal:

``` text
Metadata queries: 500/hour
```

Incident:

``` text
Metadata queries: 50,000/hour
```

A new catalog configuration begins full metadata discovery every few
minutes.

## 83.77 Root Cause

Excessive metadata polling caused by a catalog configuration change.

## 83.78 Permanent Remediation

``` text
Reduce polling frequency
Scope discovery
Use incremental metadata refresh
Add query tags
Monitor metadata query volume
```

## 83.79 Application Startup Scenario

A Kubernetes deployment scales:

``` text
5 pods -> 50 pods
```

Each new pod performs full metadata discovery during startup.

Result:

``` text
Large short-duration metadata burst
```

## 83.80 Prevention

Use connection pooling, cached schema metadata, scoped discovery,
controlled pod rollout, and startup concurrency limits where
appropriate.

## 83.81 Object Explosion Scenario

A pipeline creates:

``` text
10,000 temporary tables/day
```

and failed runs do not clean them up.

Over time this creates significant operational metadata complexity.

## 83.82 Remediation

Review whether the design can use reusable staging tables, temporary
objects with controlled lifecycle, fewer objects, and explicit cleanup
while preserving correctness and isolation.

## 83.83 Deployment Review

Before releasing metadata-heavy applications, test startup metadata
calls, connection behavior, schema discovery, query compilation, object
creation, and object cleanup.

## 83.84 Load Testing

Performance testing should include query execution, compilation,
connection startup, metadata discovery, concurrent sessions, and
application autoscaling.

## 83.85 Monitoring Compilation

Monitor:

``` text
P50 compilation
P95 compilation
P99 compilation
```

by critical workload.

## 83.86 Monitoring Metadata Volume

Monitor trends for query count, SHOW/DESCRIBE activity, Information
Schema activity, service-account query volume, and object creation/drop
where operationally useful.

## 83.87 Monitoring Object Growth

Track growth in databases, schemas, tables, views, stages, pipes, tasks,
and other governed objects for environments where uncontrolled object
growth is a risk.

## 83.88 Monitoring Application Startup

For large Kubernetes/application environments, correlate pod count,
connection count, metadata query volume, compilation, and application
latency.

## 83.89 Alerting

Example:

``` text
Patient360 P95 compilation time exceeds
the established baseline threshold for
10 minutes.
```

Another:

``` text
Metadata service account query volume
increases 10x above baseline.
```

Thresholds should be workload-specific.

## 83.90 Avoid Static Universal Thresholds

A complex ETL query may legitimately require more compilation time than
an API lookup.

Use baselines.

## 83.91 Capacity Planning

Cloud-services/metadata performance planning includes more than
warehouse size.

Consider:

``` text
Object count
Connection count
Query volume
Compilation complexity
Metadata crawlers
BI tools
Catalogs
Application replicas
Automation
```

## 83.92 Governance

Require ownership for metadata crawlers, catalog integrations, BI
integrations, monitoring tools, and automation accounts.

## 83.93 Service Accounts

Use dedicated service identities.

``` text
SVC_DATA_CATALOG
SVC_MONITORING
SVC_BI
SVC_PATIENT360
```

Avoid one generic identity for unrelated systems.

## 83.94 Least Privilege

Metadata integrations should have only the visibility required for their
purpose.

Do not grant excessive access merely to simplify discovery.

## 83.95 Security

Metadata itself can reveal sensitive structural information.

Protect object names, schema names, user information, role structure,
and query text according to organizational policy.

## 83.96 Cost Review

When metadata/control-plane behavior changes materially, review both
performance impact and billing/cost impact against current Snowflake
pricing and account behavior.

## 83.97 RCA Template

``` text
Incident:
Environment:
Account:
Region:
Application:

Incident start:
Incident end:

Customer impact:

Affected queries:
Affected users:
Affected roles:

Normal total latency:
Incident total latency:

Normal compilation:
Incident compilation:

Execution:
Queue:
Transaction blocked:

Metadata query volume:
Object activity:
Connection count:

Recent deployments:
Recent configuration changes:

Snowflake service health:

Root cause:

Contributing factors:

Immediate mitigation:

Permanent remediation:

Monitoring improvement:

Cost impact:

Owner:
Due date:
```

## 83.98 Incident Communication

``` text
Current evidence indicates the latency increase is occurring
primarily during query compilation rather than warehouse
execution.

Execution and queue time remain near baseline.

The increase began immediately after the application deployment,
which introduced a substantially more complex generated query
pattern.

The application team is rolling back the query-generation change
while we continue monitoring compilation and end-to-end latency.
```

## 83.99 Blameless RCA Language

Prefer:

``` text
The deployment introduced a query-generation pattern that
significantly increased compilation complexity.
```

rather than:

``` text
The developer wrote a bad query.
```

Focus on testing, controls, and architecture.

## 83.100 Preventive Controls

Use compilation baselines, query tagging, dedicated service accounts,
metadata traffic monitoring, connection pooling, metadata caching,
scoped catalog discovery, controlled refresh intervals, object lifecycle
management, deployment testing, and application startup testing.

## 83.101 Common Mistakes

Avoid:

``` text
Assuming every Snowflake delay is warehouse compute
Resizing for high compilation time
Ignoring compilation metrics
Ignoring generated SQL complexity
Ignoring nested views
Ignoring metadata crawlers
Polling metadata every minute unnecessarily
Running full-account discovery too frequently
Ignoring connection startup behavior
Ignoring ORM metadata discovery
Ignoring Kubernetes scale-out effects
Ignoring BI metadata traffic
Ignoring object explosion
Ignoring failed-job cleanup
Assuming Account Usage is always real-time
Ignoring service health during widespread incidents
Calling every pre-execution delay cloud-services degradation
Ignoring network/identity dependencies
No workload baseline
No query tags
Shared service accounts
No metadata integration owner
No before/after validation
```

## 83.102 SRE/DBRE Checklist

-   [ ] Customer impact captured
-   [ ] Query IDs captured
-   [ ] Account/region verified
-   [ ] Total elapsed measured
-   [ ] Compilation time measured
-   [ ] Execution time measured
-   [ ] Queue time measured
-   [ ] Transaction blocked time measured
-   [ ] Compilation percentage calculated
-   [ ] Baseline comparison completed
-   [ ] Query pattern identified
-   [ ] Query complexity reviewed
-   [ ] View nesting reviewed
-   [ ] Generated SQL reviewed
-   [ ] Metadata query volume reviewed
-   [ ] SHOW/DESCRIBE activity reviewed
-   [ ] Information Schema activity reviewed
-   [ ] Service account identified
-   [ ] Query tag/client identified
-   [ ] Connection count reviewed
-   [ ] Application startup behavior reviewed
-   [ ] Kubernetes scaling reviewed
-   [ ] BI/catalog/ORM behavior reviewed
-   [ ] Object churn reviewed
-   [ ] Recent deployments reviewed
-   [ ] Service health checked if widespread
-   [ ] Network/auth dependencies reviewed
-   [ ] Minimum safe mitigation applied
-   [ ] Compilation validated
-   [ ] End-to-end latency validated
-   [ ] Monitoring updated

## 83.103 Decision Tree

``` text
QUERY / APPLICATION SLOW
          |
          v
BREAK DOWN TIME
          |
   +------+------+------+------+
   |      |      |      |      |
   v      v      v      v      v
COMPILE QUEUE  BLOCK  EXEC   OUTSIDE
 HIGH?   HIGH?  HIGH? HIGH? SNOWFLAKE?
   |      |      |      |      |
  Yes    Yes    Yes    Yes    Yes
   |      |      |      |      |
   v      v      v      v      v
QUERY   WH     TXN    QUERY   APP /
META   CAPACITY       PROFILE NETWORK
   |
   v
ONE QUERY OR WIDESPREAD?
   |
 +---+---+
 |       |
One     Many
 |       |
 v       v
SQL /   METADATA /
VIEW    SERVICE /
CHANGE  PLATFORM
```

## 83.104 Quick Reference

``` sql
-- Query timing
SELECT
    QUERY_ID,
    USER_NAME,
    ROLE_NAME,
    WAREHOUSE_NAME,
    TOTAL_ELAPSED_TIME,
    COMPILATION_TIME,
    EXECUTION_TIME,
    QUEUED_OVERLOAD_TIME,
    TRANSACTION_BLOCKED_TIME,
    START_TIME
FROM SNOWFLAKE.ACCOUNT_USAGE.QUERY_HISTORY
WHERE START_TIME >= DATEADD('hour', -4, CURRENT_TIMESTAMP())
ORDER BY COMPILATION_TIME DESC;

-- Compilation percentage
SELECT
    QUERY_ID,
    ROUND(
        COMPILATION_TIME * 100.0 /
        NULLIF(TOTAL_ELAPSED_TIME, 0),
        2
    ) AS COMPILATION_PCT
FROM SNOWFLAKE.ACCOUNT_USAGE.QUERY_HISTORY
WHERE START_TIME >= DATEADD('hour', -4, CURRENT_TIMESTAMP())
ORDER BY COMPILATION_PCT DESC;

-- Compilation by user
SELECT
    USER_NAME,
    COUNT(*) AS QUERY_COUNT,
    SUM(COMPILATION_TIME) / 1000 AS COMPILATION_SECONDS
FROM SNOWFLAKE.ACCOUNT_USAGE.QUERY_HISTORY
WHERE START_TIME >= DATEADD('hour', -1, CURRENT_TIMESTAMP())
GROUP BY USER_NAME
ORDER BY COMPILATION_SECONDS DESC;

-- Query types
SELECT
    QUERY_TYPE,
    COUNT(*) AS QUERY_COUNT
FROM SNOWFLAKE.ACCOUNT_USAGE.QUERY_HISTORY
WHERE START_TIME >= DATEADD('hour', -1, CURRENT_TIMESTAMP())
GROUP BY QUERY_TYPE
ORDER BY QUERY_COUNT DESC;
```

## 83.105 Key Principles

1.  Cloud services and virtual warehouses are different architectural
    layers.
2.  Not every Snowflake slowdown is a warehouse problem.
3.  Always break down query elapsed time.
4.  Compilation time is an important diagnostic signal.
5.  High compilation time is not fixed by blindly resizing warehouses.
6.  One complex query does not prove a platform incident.
7.  Determine whether the issue is isolated or widespread.
8.  Generated SQL can create significant compilation complexity.
9.  Excessive nested views can increase query complexity.
10. Metadata operations deserve workload governance.
11. Catalog tools can create metadata storms.
12. BI tools can generate metadata traffic.
13. ORMs may perform schema discovery.
14. Application startup can generate metadata bursts.
15. Connection pooling can reduce repeated startup work.
16. Cache metadata where safe.
17. Scope metadata discovery.
18. Avoid unnecessarily frequent full-account scans.
19. Understand Information Schema usage.
20. Understand Account Usage latency.
21. Use appropriate near-real-time interfaces during incidents.
22. Avoid uncontrolled object churn.
23. Clean up temporary working objects.
24. Avoid unnecessary schema/table explosion.
25. Monitor object growth.
26. Use dedicated service accounts.
27. Use query tags.
28. Establish metadata integration ownership.
29. Baseline compilation by workload.
30. Monitor P50/P95/P99 compilation.
31. Correlate metadata traffic with application deployments.
32. Correlate metadata traffic with Kubernetes scaling.
33. Check Snowflake service health for widespread issues.
34. Do not confuse network/auth delay with cloud-services delay.
35. Measure end-to-end application latency.
36. Test metadata behavior before production deployment.
37. Test application startup at production scale.
38. Validate performance after mitigation.
39. Review both operational and cost impact.
40. Troubleshoot the layer where time is actually being spent.

## 83.106 Chapter Completion Checklist

After completing this chapter, you should be able to:

-   Explain the role of Snowflake cloud services.
-   Distinguish cloud-services activity from virtual-warehouse
    execution.
-   Understand the Snowflake query lifecycle.
-   Measure query compilation time.
-   Calculate compilation percentage.
-   Identify high-compilation queries.
-   Distinguish query complexity from platform-wide degradation.
-   Troubleshoot generated SQL.
-   Troubleshoot nested-view complexity.
-   Identify metadata-heavy workloads.
-   Investigate catalog crawlers.
-   Investigate BI metadata traffic.
-   Investigate ORM metadata discovery.
-   Investigate application startup metadata bursts.
-   Understand connection-pool implications.
-   Understand Information Schema and Account Usage use cases.
-   Investigate object churn and object explosion.
-   Build compilation baselines.
-   Monitor metadata volume.
-   Correlate metadata activity with deployments and autoscaling.
-   Execute compilation, metadata-storm, catalog, BI, ORM, and
    object-churn runbooks.
-   Produce evidence-based incident communications.
-   Produce a metadata/cloud-services RCA.
-   Implement preventive metadata governance and monitoring.

**Chapter 83 --- Snowflake Metadata & Cloud Services Performance:
Complete**
