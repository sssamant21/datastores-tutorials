# Chapter 80 --- Snowflake Production Incident Investigation Runbook

## 80.1 Overview

Production Snowflake incidents rarely arrive with a precise diagnosis.

Typical reports are:

``` text
Snowflake is slow.
Patient360 is timing out.
Data is missing.
The pipeline stopped.
Users cannot log in.
Queries are failing.
Warehouse cost suddenly increased.
The dashboard is stale.
```

The SRE/DBRE responsibility is to turn a vague symptom into an
evidence-based incident diagnosis.

``` text
DETECT
   |
   v
ASSESS IMPACT
   |
   v
ESTABLISH SCOPE
   |
   v
CAPTURE EVIDENCE
   |
   v
CLASSIFY
   |
   v
ISOLATE FAILED LAYER
   |
   v
MITIGATE
   |
   v
VALIDATE
   |
   v
RECOVER
   |
   v
MONITOR
   |
   v
RCA
   |
   v
PREVENT
```

**Primary rule: Mitigate quickly, but do not make uncontrolled
production changes without evidence.**

## 80.2 Primary Objectives

During an incident:

1.  Protect customer impact.
2.  Establish scope.
3.  Preserve evidence.
4.  Identify the failed layer.
5.  Apply the minimum safe mitigation.
6.  Validate recovery.
7.  Prevent recurrence.

## 80.3 What Is Actually Broken?

Do not begin with:

``` text
Snowflake is broken.
```

Determine whether the incident is:

``` text
Query performance
Warehouse/concurrency
Data ingestion
Authentication
Authorization
Transaction blocking
Resource contention
Metadata/cloud services
Application/network
Cost
Data correctness
External dependency
```

## 80.4 Severity Model

Use the organization's incident-severity model.

A practical example:

``` text
SEV-1
Critical customer/business outage

SEV-2
Major degradation or significant production impact

SEV-3
Limited degradation / workaround available

SEV-4
Low-impact operational issue
```

Business impact determines severity---not merely the technical symptom.

## 80.5 Ownership

For significant incidents, establish:

``` text
Incident Commander
Snowflake investigator
Application owner
Pipeline owner
Cloud/network owner
Security owner
Communications owner
```

Avoid multiple engineers making independent production changes.

## 80.6 Start the Timeline Immediately

Record:

``` text
Incident detected
Customer impact began
Last known good
First known bad
Alerts
Deployments
Configuration changes
Mitigations
Recovery
Validation
Incident closed
```

## 80.7 First Five Minutes

Capture:

``` text
Environment
Account
Region
Application
Incident start
Customer impact
Affected users
Affected workload
Warehouse
Database/schema
Query IDs
Pipeline
Authentication identity
Recent changes
```

Do not wait until after recovery to reconstruct this information.

## 80.8 Verify Environment

``` sql
SELECT
    CURRENT_ORGANIZATION_NAME(),
    CURRENT_ACCOUNT_NAME(),
    CURRENT_REGION(),
    CURRENT_USER(),
    CURRENT_ROLE(),
    CURRENT_WAREHOUSE(),
    CURRENT_DATABASE(),
    CURRENT_SCHEMA();
```

Confirm you are investigating the correct environment.

## 80.9 Snowflake Service Health

Determine whether there is a known Snowflake service event affecting the
account or region.

Do not assume every production problem is account-local. At the same
time, do not stop internal investigation simply because external service
status appears healthy.

## 80.10 Basic Connectivity

Where appropriate:

``` sql
SELECT CURRENT_TIMESTAMP();
```

This answers only a limited question:

``` text
Can this session execute a trivial statement?
```

It does not prove application workloads are healthy.

## 80.11 Determine Blast Radius

Ask:

``` text
One query?
One user?
One service?
One warehouse?
One pipeline?
One database?
Multiple workloads?
Entire account?
```

## 80.12 Scope Matrix

  Scope                      Likely Direction
  -------------------------- --------------------------
  One query                  SQL/query plan/data
  One user                   Identity/role
  One application            App/config/workload
  One warehouse              Warehouse/concurrency
  One pipeline               Ingestion/transformation
  Many warehouses            Account/platform/network
  All users cannot connect   Auth/network/platform

## 80.13 Always Ask What Changed

Check:

``` text
Application deployment
SQL deployment
Warehouse resize
RBAC change
Network policy
Key rotation
OAuth/SSO configuration
Stage configuration
Pipe configuration
Task deployment
Schema change
Table recreation
Terraform deployment
Cloud networking
Batch schedule
Traffic pattern
```

## 80.14 Timeline Correlation

``` text
13:55 Terraform deployment
14:00 Application failures begin
14:02 Alert fires
14:05 Incident declared
```

This does not automatically prove causation, but it provides a strong
investigation direction.

## 80.15 Query History

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
    QUEUED_PROVISIONING_TIME,
    TRANSACTION_BLOCKED_TIME,
    START_TIME,
    END_TIME,
    ERROR_CODE,
    ERROR_MESSAGE
FROM SNOWFLAKE.ACCOUNT_USAGE.QUERY_HISTORY
WHERE START_TIME >= DATEADD('hour', -2, CURRENT_TIMESTAMP())
ORDER BY START_TIME DESC;
```

Adjust the time window appropriately.

## 80.16 Failed Queries

``` sql
SELECT
    QUERY_ID,
    USER_NAME,
    ROLE_NAME,
    WAREHOUSE_NAME,
    QUERY_TEXT,
    ERROR_CODE,
    ERROR_MESSAGE,
    START_TIME
FROM SNOWFLAKE.ACCOUNT_USAGE.QUERY_HISTORY
WHERE EXECUTION_STATUS = 'FAIL'
  AND START_TIME >= DATEADD('hour', -2, CURRENT_TIMESTAMP())
ORDER BY START_TIME DESC;
```

Protect sensitive SQL and data when sharing results.

## 80.17 Long-Running Queries

``` sql
SELECT
    QUERY_ID,
    USER_NAME,
    WAREHOUSE_NAME,
    TOTAL_ELAPSED_TIME,
    EXECUTION_TIME,
    START_TIME
FROM SNOWFLAKE.ACCOUNT_USAGE.QUERY_HISTORY
WHERE START_TIME >= DATEADD('hour', -2, CURRENT_TIMESTAMP())
ORDER BY TOTAL_ELAPSED_TIME DESC
LIMIT 50;
```

## 80.18 Break Runtime Apart

A slow query may spend time in:

``` text
Compilation
Execution
Queued overload
Queued provisioning
Repair
Transaction blocking
Result transfer / application
```

Do not treat total elapsed time as execution time.

## 80.19 Queueing Example

``` text
Total elapsed:          50 sec
Execution:               5 sec
Queued overload:        44 sec
```

Direction:

``` text
Warehouse/concurrency
```

not primarily SQL optimization.

## 80.20 Execution Example

``` text
Total elapsed:          50 sec
Execution:              47 sec
Queued overload:         0 sec
```

Direction:

``` text
Query profile
Data scanned
Joins
Aggregation
Sort
Spill
Warehouse size
```

## 80.21 Warehouse Investigation

``` sql
SHOW WAREHOUSES;
```

Capture state, size, auto-suspend, auto-resume, min/max clusters,
scaling policy, and resource monitor where applicable.

## 80.22 Queueing

High `QUEUED_OVERLOAD_TIME` indicates warehouse contention/concurrency
should be investigated.

## 80.23 Provisioning

High `QUEUED_PROVISIONING_TIME` may indicate waiting for warehouse
provisioning, resume, or resize behavior.

## 80.24 Transaction Blocking

High `TRANSACTION_BLOCKED_TIME` points toward transaction/locking
investigation.

Do not solve transaction blocking by blindly resizing the warehouse.

## 80.25 Warehouse Contention

Investigate:

``` text
Concurrent queries
Long-running queries
ETL overlap
BI workload
Application burst
Retry storm
Ad-hoc activity
Recent size changes
Multi-cluster behavior
```

## 80.26 Workload Attribution

Query tags can help identify:

``` text
Application
Service
Pipeline
Operation
Environment
```

Example:

``` text
service=patient360-api
pipeline=empi-load
env=prod
```

## 80.27 Data Ingestion Incident

``` text
SOURCE
   |
   v
STORAGE
   |
   v
STAGE
   |
   v
COPY / SNOWPIPE
   |
   v
TARGET
   |
   v
TRANSFORMATION
   |
   v
CONSUMER
```

Find the exact boundary where data stopped.

## 80.28 Stage Check

``` sql
LIST @EMPI_STAGE;
```

## 80.29 Pipe Status

``` sql
SELECT SYSTEM$PIPE_STATUS('EMPI_PIPE');
```

## 80.30 Pipe Inventory

``` sql
SHOW PIPES;
DESC PIPE EMPI_PIPE;
```

## 80.31 Load History

Use the appropriate Snowflake load-history interface to determine:

``` text
Was the file received?
Was it loaded?
Did it fail?
How many rows loaded?
What error occurred?
```

## 80.32 Missing Data

If:

``` text
L1 contains data
L2 does not
```

then the source-to-Snowflake ingestion path may be healthy.

Investigate downstream transformation.

## 80.33 Authentication Incident

Symptoms:

``` text
Login failure
Key-pair failure
OAuth rejection
SSO failure
Network-policy block
```

## 80.34 Login History

Use Snowflake login history to identify:

``` text
User
Timestamp
Success/failure
Source IP
Client
Error
```

## 80.35 Authentication Timeline

Compare:

``` text
Last successful login
First failed login
Credential rotation
Application deployment
Network change
Policy change
```

## 80.36 Authorization Incident

Authentication works but the operation fails.

Examples:

``` text
Warehouse not authorized
Database not authorized
Schema not authorized
Table not authorized
Insufficient privileges
Object does not exist or not authorized
```

## 80.37 Authorization Checks

``` sql
SELECT CURRENT_ROLE();

SHOW GRANTS TO USER SVC_PATIENT360;

SHOW GRANTS TO ROLE PATIENT360_APP_ROLE;

SHOW GRANTS ON WAREHOUSE PATIENT360_APP_WH;
```

## 80.38 Privilege Chain

A SELECT workload may need:

``` text
USAGE on warehouse
+
USAGE on database
+
USAGE on schema
+
SELECT on object
```

through the intended RBAC hierarchy.

## 80.39 Application vs Snowflake

Application latency is not automatically Snowflake query latency.

Measure:

``` text
Application request duration
Snowflake queue time
Snowflake execution time
Result fetch time
Network time
Application processing
```

## 80.40 Application Layer Example

``` text
Application request:     45 sec
Snowflake query:          3 sec
```

Do not resize Snowflake solely because the application request took 45
seconds.

## 80.41 Network Investigation

When relevant, investigate:

``` text
DNS
Firewall
Proxy
NAT
VPN
Private connectivity
TLS
Routing
```

when requests do not reach Snowflake or connection behavior changes.

## 80.42 External Components

Snowflake pipelines may depend on:

``` text
S3
Azure Blob
GCS
Identity provider
OAuth provider
Secret manager
DNS
Cloud event notification
Kafka/connectors
Applications
```

The failed layer may be outside Snowflake.

## 80.43 Cost Incident

Symptoms:

``` text
Credit spike
Warehouse running unexpectedly
Additional clusters
Repeated query execution
Retry storm
Unexpected ingestion usage
Task frequency increase
```

## 80.44 Cost Investigation

Ask:

``` text
Which warehouse/service?
When did cost increase?
Did warehouse size change?
Did runtime increase?
Did concurrency increase?
Did cluster count increase?
Did query volume increase?
Did retries increase?
Did schedule change?
```

## 80.45 Resource Monitor

``` sql
SHOW RESOURCE MONITORS;
```

A resource-monitor action can itself affect workload availability.

## 80.46 Data Correctness Incident

Examples:

``` text
Duplicate records
Missing records
Wrong values
Stale data
Partial load
Schema drift
Incorrect transformation
```

Do not declare recovery merely because queries execute successfully.

## 80.47 Data Validation

Validate:

``` text
Row counts
Distinct business keys
Null rates
Duplicates
Date ranges
Expected partitions
Business totals
Source-to-target counts
```

## 80.48 Preserve Evidence

Before major changes capture:

``` text
Query IDs
Query timing
Query Profile
Warehouse state
Warehouse configuration
Pipe status
Load history
Login history
Grants
Errors
Application metrics
Deployment version
Timeline
```

Production evidence can become difficult to reconstruct after
remediation.

## 80.49 Change Control During Incident

Where practical:

``` text
Baseline
   |
   v
Change
   |
   v
Observe
   |
   v
Validate
```

Avoid simultaneously resizing the warehouse, changing SQL, restarting
applications, changing retry policy, and changing RBAC unless emergency
impact requires coordinated actions.

## 80.50 Minimum Safe Mitigation

Prefer the smallest reversible action that restores service.

Examples:

``` text
Pause noncritical batch
Move ETL workload
Temporarily resize warehouse
Restore valid credential
Restore missing privilege
Correct notification path
Cancel pathological query
Rollback deployment
```

## 80.51 Query Cancellation

Where approved:

``` sql
SELECT SYSTEM$CANCEL_QUERY('<query_id>');
```

Do not cancel a query simply because it is long-running. Determine its
purpose and business impact.

## 80.52 Rollback

If an incident begins immediately after a reversible deployment or
configuration change, rollback may be safer than debugging indefinitely
in production.

## 80.53 Emergency Scaling

If evidence shows compute capacity is the immediate bottleneck,
temporary scaling may restore service.

Capture before/after:

``` text
Queue time
Execution time
Application latency
Credits
```

Then determine whether to retain or revert.

## 80.54 Emergency Workload Isolation

``` text
Before:

SHARED_WH
  |
  +-- API
  +-- ETL
  +-- BI

Mitigation:

APP_WH
  |
  +-- API

ETL_WH
  |
  +-- ETL
```

## 80.55 Retry Storm Mitigation

If application retries amplify Snowflake load:

``` text
Reduce retries
Bound concurrency
Add backoff
Add jitter
Adjust timeout carefully
```

Coordinate with the application team.

## 80.56 Recovery Is Not Incident Closure

Service recovery means customer impact stopped.

Incident closure requires additional validation.

## 80.57 Recovery Validation

Confirm:

``` text
Application healthy
Queries healthy
Queueing normalized
Errors stopped
Data current
Pipelines current
Authentication works
Correct role/access restored
Cost behavior understood
No duplicate/missing data
```

## 80.58 Observation Window

After recovery, observe the system long enough to ensure the problem
does not immediately recur.

Use a duration appropriate to workload frequency and incident type.

## 80.59 Compare to Baseline

Do not validate only against:

``` text
It works now.
```

Compare with:

``` text
Normal P50/P95/P99
Normal queue time
Normal execution
Normal ingestion latency
Normal error rate
Normal credit rate
```

## 80.60 Incident Communication

A useful update contains:

``` text
Impact
Current status
Evidence
Mitigation
Validation
Next action
Risk
```

## 80.61 Example Internal Update

``` text
Patient360 Snowflake-backed requests experienced elevated
latency beginning at 14:02 UTC.

Investigation shows query execution remains near the normal
baseline, while queued overload time increased significantly
on PATIENT360_APP_WH.

The team isolated a concurrent ETL workload sharing the
warehouse during the incident window.

The ETL workload has been paused temporarily. Queue time and
application latency are returning toward baseline.

We are continuing validation and reviewing permanent workload
isolation options.
```

This is evidence-based and avoids blame.

## 80.62 Avoid Premature RCA

Avoid statements such as:

``` text
Snowflake caused the outage.
```

until evidence establishes causation.

Use:

``` text
Current evidence indicates...
We are investigating...
The strongest correlation is...
We have confirmed...
```

## 80.63 Root Cause Standard

A root cause should explain:

``` text
What failed?
Why did it fail?
Why did it affect customers?
Why did controls not prevent it?
Why did detection/mitigation take the observed time?
```

## 80.64 Contributing Factors

Do not confuse root cause with contributing factors.

Example:

``` text
Root cause:
ETL and API workloads shared insufficient concurrency capacity.

Contributing factors:
ETL schedule overlapped peak API traffic.
No queue-time alert existed.
Application retries amplified workload.
```

## 80.65 Five Whys

The Five Whys can help uncover systemic causes but should not be forced
into an artificial chain.

Focus on architecture, process, monitoring, automation, capacity, and
change management rather than individual blame.

## 80.66 Corrective Action Categories

Every meaningful RCA should consider:

``` text
Immediate correction
Permanent remediation
Monitoring
Automation
Testing
Capacity
Documentation
Ownership
Change management
```

## 80.67 Weak Action Item

``` text
Monitor Snowflake.
```

## 80.68 Strong Action Item

``` text
Create an alert when PATIENT360_APP_WH P95 queued overload
exceeds the agreed threshold for 10 minutes during production
hours.

Owner: Data Platform SRE
Due: YYYY-MM-DD
```

## 80.69 Master Production Incident Runbook

1.  Declare incident.
2.  Assign severity.
3.  Assign incident owner.
4.  Start timeline.
5.  Capture customer impact.
6.  Verify environment/account/region.
7.  Check external Snowflake health.
8.  Determine blast radius.
9.  Identify last known good.
10. Identify first known bad.
11. Review recent changes.
12. Capture query history.
13. Capture failed queries.
14. Capture long-running queries.
15. Break down query timing.
16. Check warehouse state/configuration.
17. Check queueing.
18. Check transaction blocking.
19. Check workload concurrency.
20. Check ingestion if data is missing.
21. Check authentication if connections fail.
22. Check authorization if login succeeds but SQL fails.
23. Check network/application layers.
24. Check cost/resource monitors if relevant.
25. Preserve evidence.
26. Form evidence-based hypothesis.
27. Select minimum safe mitigation.
28. Obtain required approval.
29. Apply one controlled change.
30. Observe.
31. Validate customer recovery.
32. Validate Snowflake metrics.
33. Validate data correctness.
34. Monitor observation window.
35. Remove temporary mitigation where appropriate.
36. Document final timeline.
37. Establish root cause.
38. Identify contributing factors.
39. Create corrective actions.
40. Assign owners/dates.
41. Update runbooks/monitoring.
42. Close incident.

## 80.70 Slowness Runbook

If the report is "Snowflake is slow":

1.  Capture affected query IDs.
2.  Establish normal runtime.
3.  Break down total elapsed time.
4.  Check queueing.
5.  Check execution.
6.  Check transaction blocking.
7.  Check Query Profile.
8.  Check spill/scans/joins.
9.  Check warehouse load.
10. Check concurrent workloads.
11. Check application latency.
12. Compare last-good/bad execution.
13. Mitigate based on evidence.
14. Validate performance and cost.

Use Chapters 76 and 77 for deeper investigation.

## 80.71 Missing Data Runbook

If the report is "Data is missing":

1.  Identify expected data/file.
2.  Verify source.
3.  Verify storage.
4.  LIST stage.
5.  Check COPY/load history.
6.  Check Snowpipe.
7.  Check target table.
8.  Check transformation.
9.  Check downstream consumer.
10. Validate counts.
11. Determine safe replay.
12. Prevent duplicates.
13. Validate business completeness.

Use Chapter 78.

## 80.72 Access Runbook

If the report is "User cannot access Snowflake":

1.  Determine authentication vs authorization.
2.  Capture exact error.
3.  Verify account.
4.  Check login history.
5.  Check identity state.
6.  Check source IP/network policy.
7.  Check credentials/SSO/OAuth.
8.  If login succeeds, verify role.
9.  Verify warehouse.
10. Verify database/schema/object grants.
11. Check recent RBAC changes.
12. Apply minimum approved remediation.
13. Retest with application context.

Use Chapter 79.

## 80.73 Cost Spike Runbook

1.  Identify incident window.
2.  Identify cost domain.
3.  Identify warehouse/service.
4.  Check warehouse size.
5.  Check runtime.
6.  Check query volume.
7.  Check concurrency.
8.  Check cluster count.
9.  Check retries.
10. Check task frequency.
11. Check ingestion.
12. Check recent changes.
13. Compare baseline.
14. Stop unnecessary workload if approved.
15. Validate business impact before suspension.
16. Correct root cause.
17. Monitor credits.

## 80.74 Data Correctness Runbook

1.  Define incorrect business result.
2.  Identify source.
3.  Compare source-to-target.
4.  Identify first incorrect layer.
5.  Check load history.
6.  Check schema drift.
7.  Check transformation.
8.  Check MERGE logic.
9.  Check duplicate/replay activity.
10. Check recent deployment.
11. Isolate affected data.
12. Define recovery.
13. Validate with business owner.
14. Prevent recurrence.

## 80.75 Evidence Package

For significant incidents retain:

``` text
Incident timeline
Query IDs
Relevant SQL metadata
Query Profile evidence
Warehouse metrics
Login evidence
Pipe/load evidence
Application metrics
Configuration changes
Deployment IDs
Screenshots where appropriate
Mitigation commands
Validation results
```

Never include secrets or unnecessary PHI/PII.

## 80.76 Security During Incidents

Avoid:

``` text
Sharing passwords
Sharing private keys
Disabling MFA without process
Granting ACCOUNTADMIN broadly
Opening network access globally
Embedding credentials in commands
Posting PHI/PII in Slack
```

## 80.77 Break-Glass

If break-glass access is required, it should be approved, audited,
time-bounded, minimum required, revoked afterward, and reviewed.

## 80.78 Useful Automation

Automate evidence collection for:

``` text
Query history
Failed queries
Queueing
Warehouse state
Warehouse metering
Pipe status
Load history
Login failures
Task failures
Cost anomalies
```

## 80.79 Automated Remediation Caution

Do not automatically resize warehouses, cancel queries, suspend
warehouses, replay files, refresh pipes, grant privileges, or rotate
credentials without strong guardrails and a well-defined failure model.

## 80.80 Incident Dashboard

A Snowflake operational dashboard should include:

``` text
Query P50/P95/P99
Failed queries
Queued overload
Provisioning delay
Transaction blocking
Warehouse state
Warehouse credits
Concurrency
Spill
Data ingestion latency
Load failures
Pipe health
Task failures
Login failures
Cost trend
```

## 80.81 Know Normal

Maintain baselines by workload:

``` text
Normal query latency
Normal queueing
Normal concurrency
Normal ingestion latency
Normal login failure rate
Normal warehouse credits
Normal data volume
```

Without baselines, incident diagnosis becomes guesswork.

## 80.82 Alert Quality

An alert should indicate:

``` text
Actionable abnormal condition
+
Relevant context
+
Owner
+
Runbook
```

Avoid hundreds of alerts that nobody trusts.

## 80.83 Preventive Review

After an incident ask:

``` text
Could monitoring have detected this earlier?
Could automation have prevented it?
Was capacity sufficient?
Was workload isolation sufficient?
Was change validation sufficient?
Was rollback available?
Was ownership clear?
Was the runbook sufficient?
```

## 80.84 Incident Readiness

Every critical Snowflake workload should have:

``` text
Owner
SLA
Architecture
Dependencies
Dashboard
Alerts
Runbook
Escalation
Rollback
Recovery procedure
Data validation
Capacity baseline
Cost baseline
```

## 80.85 Scenario --- Patient360 Query Slowness

At 10:15:

``` text
Patient360 latency increases from 3 sec to 40 sec.
```

## 80.86 Evidence

``` text
Snowflake execution:        4 sec
Queued overload:           34 sec
ETL started:               10:14
API and ETL share warehouse
```

## 80.87 Diagnosis

The primary issue is warehouse contention rather than slow SQL.

## 80.88 Mitigation

Move or pause the noncritical ETL workload, or provide temporary
concurrency capacity according to the approved incident procedure.

## 80.89 Permanent Action

Isolate API and ETL workloads and add queue-time monitoring.

## 80.90 Scenario --- Missing EMPI Data

At 14:30:

``` text
DAP.L2.EMPI is stale.
```

## 80.91 Evidence

``` text
Source file exists
Stage sees file
Snowpipe loaded file
DAP.L1.EMPI current
DAP.L2.EMPI stale
```

## 80.92 Diagnosis

The failure is downstream transformation, not Snowpipe.

## 80.93 Scenario --- Authentication

At 16:00:

``` text
SVC_PATIENT360 cannot authenticate.
```

## 80.94 Evidence

``` text
Failures start immediately after key rotation.
Snowflake has new public key.
Application still has old private key.
```

## 80.95 Diagnosis

Credential rotation synchronization failure.

## 80.96 Scenario --- Authorization

Application can query existing tables but not a newly deployed table.

Evidence:

``` text
Authentication succeeds
Role correct
Warehouse correct
Database/schema accessible
New table missing intended role access
```

## 80.97 Diagnosis

Deployment/RBAC automation failed to apply required access to the new
object.

## 80.98 Scenario --- Cost Spike

Credits double overnight.

Evidence:

``` text
Warehouse size unchanged
Query volume triples
Application timeout causes retry storm
Warehouse runs continuously
```

## 80.99 Diagnosis

Application retry amplification increased Snowflake workload and
runtime.

Simply reducing warehouse size would not address the root cause.

## 80.100 Production Incident RCA Template

``` text
Incident:
Severity:
Environment:
Account:
Region:

Start:
Detection:
Mitigation:
Recovery:
End:

Customer impact:

Affected application:
Affected workload:
Affected warehouse:
Affected database/schema:
Affected pipeline:
Affected identity:

Last known good:
First known bad:

Recent changes:

Evidence:

Query findings:
Warehouse findings:
Ingestion findings:
Authentication findings:
Authorization findings:
Application/network findings:
Cost findings:

Root cause:

Contributing factors:

Why monitoring did/did not detect it:

Immediate mitigation:

Permanent remediation:

Data validation:

Rollback/recovery validation:

Preventive monitoring:

Corrective actions:
1.
2.
3.

Owners:
Due dates:
```

## 80.101 Incident Handoff

Include:

``` text
Current severity
Customer impact
Current state
Timeline
Evidence
What has been ruled out
Current hypothesis
Mitigations applied
Temporary changes
Risks
Next actions
Owners
```

## 80.102 Temporary Change Tracking

Record temporary incident changes such as:

``` text
Warehouse resized
ETL paused
Auto-suspend changed
Multi-cluster changed
Role granted
Network rule modified
Pipe refreshed
Application retry reduced
```

Every temporary change requires an owner and disposition.

## 80.103 Post-Incident Cleanup

Verify:

``` text
Temporary warehouse size reverted if appropriate
Temporary access removed
Paused jobs restored
Retry settings normalized
Emergency network changes reverted
IaC reconciled
Monitoring updated
Runbook updated
```

## 80.104 Common Mistakes

Avoid:

``` text
Assuming Snowflake is the root cause
Resizing immediately
Restarting everything
Changing many variables simultaneously
Ignoring query IDs
Ignoring queueing
Ignoring transaction blocking
Ignoring application latency
Ignoring network dependencies
Assuming missing data means Snowpipe failure
Blind pipe refresh
Blind file replay
Ignoring duplicate risk
Granting ACCOUNTADMIN
Testing only as admin
Ignoring login history
Ignoring recent deployments
Ignoring Terraform changes
Ignoring cost impact
Ignoring data correctness
Declaring recovery without validation
Closing incident without observation
No timeline
No evidence preservation
No RCA
No preventive actions
```

## 80.105 SRE/DBRE Incident Checklist

-   [ ] Incident declared
-   [ ] Severity assigned
-   [ ] Incident owner assigned
-   [ ] Timeline started
-   [ ] Customer impact captured
-   [ ] Environment verified
-   [ ] Account/region verified
-   [ ] External service health checked
-   [ ] Blast radius established
-   [ ] Last known good identified
-   [ ] First known bad identified
-   [ ] Recent changes reviewed
-   [ ] Query IDs captured
-   [ ] Query history reviewed
-   [ ] Failed queries reviewed
-   [ ] Query timing broken down
-   [ ] Warehouse state reviewed
-   [ ] Queueing reviewed
-   [ ] Transaction blocking reviewed
-   [ ] Concurrent workload reviewed
-   [ ] Ingestion reviewed if applicable
-   [ ] Authentication reviewed if applicable
-   [ ] Authorization reviewed if applicable
-   [ ] Application/network reviewed
-   [ ] Cost reviewed if applicable
-   [ ] Data correctness reviewed
-   [ ] Evidence preserved
-   [ ] Hypothesis established
-   [ ] Minimum mitigation selected
-   [ ] Approval obtained where required
-   [ ] Change applied
-   [ ] Customer recovery validated
-   [ ] Snowflake metrics validated
-   [ ] Data correctness validated
-   [ ] Observation window completed
-   [ ] Temporary changes tracked
-   [ ] Root cause established
-   [ ] Contributing factors documented
-   [ ] Corrective actions assigned
-   [ ] Monitoring updated
-   [ ] Runbook updated
-   [ ] Incident closed

## 80.106 Master Decision Tree

``` text
PRODUCTION ISSUE
      |
      v
CAN CONNECT?
      |
   +--+--+
   |     |
  No    Yes
   |     |
   v     v
AUTH /  QUERY FAILS?
NETWORK      |
          +--+--+
          |     |
         Yes    No
          |     |
          v     v
       AUTHZ /  SLOW?
       SQL ERROR   |
                +--+--+
                |     |
               Yes    No
                |     |
                v     v
              QUEUED? DATA MISSING?
                |          |
             +--+--+    +--+--+
             |     |    |     |
            Yes    No   Yes    No
             |     |    |      |
             v     v    v      v
          WH/CONC QUERY PIPELINE APP/COST/
                 PROFILE       EXTERNAL
```

## 80.107 Quick Reference

``` sql
-- Context
SELECT
    CURRENT_ORGANIZATION_NAME(),
    CURRENT_ACCOUNT_NAME(),
    CURRENT_REGION(),
    CURRENT_USER(),
    CURRENT_ROLE(),
    CURRENT_WAREHOUSE(),
    CURRENT_DATABASE(),
    CURRENT_SCHEMA();

-- Health
SELECT CURRENT_TIMESTAMP();

-- Warehouses
SHOW WAREHOUSES;

-- Resource monitors
SHOW RESOURCE MONITORS;

-- Stage
LIST @EMPI_STAGE;

-- Pipes
SHOW PIPES;
DESC PIPE EMPI_PIPE;

-- Pipe status
SELECT SYSTEM$PIPE_STATUS('EMPI_PIPE');

-- Roles
SHOW ROLES;

-- User grants
SHOW GRANTS TO USER SVC_PATIENT360;

-- Role grants
SHOW GRANTS TO ROLE PATIENT360_APP_ROLE;

-- Warehouse grants
SHOW GRANTS ON WAREHOUSE PATIENT360_APP_WH;
```

## 80.108 Production Incident Principles

1.  Start with customer impact.
2.  Establish scope before changing production.
3.  Verify environment/account/region.
4.  Start the incident timeline immediately.
5.  Identify last known good and first known bad.
6.  Always review recent changes.
7.  Capture query IDs.
8.  Separate total elapsed time from execution time.
9.  Queueing is not execution.
10. Transaction blocking is not warehouse saturation.
11. Application latency is not automatically Snowflake latency.
12. Missing data is not automatically Snowpipe failure.
13. Authentication and authorization are different.
14. Test authorization using application context.
15. Preserve evidence before major changes.
16. Form hypotheses from evidence.
17. Prefer reversible mitigation.
18. Change one major variable at a time where practical.
19. Scale only when capacity evidence supports scaling.
20. Cancel queries only when justified.
21. Do not blindly replay data.
22. Protect against duplicate recovery.
23. Do not weaken security casually during incidents.
24. Validate data correctness after recovery.
25. Recovery is not the same as incident closure.
26. Compare recovery metrics with baseline.
27. Use an observation window.
28. Track every temporary change.
29. Reconcile emergency changes with IaC.
30. Separate root cause from contributing factors.
31. Keep RCA blameless and evidence based.
32. Corrective actions need owners and dates.
33. Monitor query latency.
34. Monitor queueing.
35. Monitor ingestion.
36. Monitor authentication.
37. Monitor cost.
38. Maintain workload baselines.
39. Automate evidence collection where safe.
40. Turn every significant incident into a preventive improvement.

## 80.109 Chapter Completion Checklist

After completing this chapter, you should be able to:

-   Declare and scope a Snowflake production incident.
-   Establish incident severity.
-   Build an incident timeline.
-   Verify account/session context.
-   Determine blast radius.
-   Correlate recent changes.
-   Investigate failed and slow queries.
-   Break down query runtime.
-   Troubleshoot warehouse contention.
-   Identify transaction blocking direction.
-   Troubleshoot missing data and Snowpipe incidents.
-   Troubleshoot authentication and authorization.
-   Separate application/network latency from Snowflake latency.
-   Investigate cost spikes and data-correctness incidents.
-   Preserve production evidence.
-   Select minimum safe mitigation.
-   Perform controlled production changes.
-   Validate recovery against baselines.
-   Manage an observation window.
-   Track temporary incident changes.
-   Produce blameless, evidence-based incident communications.
-   Produce a production RCA.
-   Create actionable preventive measures.
-   Execute the master Snowflake incident runbook.

**Chapter 80 --- Snowflake Production Incident Investigation Runbook:
Complete**
