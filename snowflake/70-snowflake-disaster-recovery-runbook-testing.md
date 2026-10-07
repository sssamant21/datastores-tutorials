# Chapter 70 --- Snowflake Disaster Recovery Runbook & Testing

## 70.1 Overview

A Snowflake disaster recovery design is not production-ready until the
organization can execute it through a documented, tested, repeatable
runbook.

The complete operational lifecycle is:

``` text
DESIGN
  |
  v
REPLICATE
  |
  v
MONITOR
  |
  v
TEST
  |
  v
INCIDENT
  |
  v
ASSESS
  |
  v
DECLARE DR
  |
  v
FAILOVER
  |
  v
VALIDATE
  |
  v
OPERATE IN DR
  |
  v
FAILBACK
  |
  v
POST-DR REVIEW
```

This chapter converts the replication and failover concepts from
Chapters 66--69 into an operational SRE/DBRE runbook.

# DR Principles

## 70.2 DR Is a Business-Service Recovery Process

The goal is not simply that Snowflake is available. The goal is that the
business service is operational.

## 70.3 DR Must Be Executable

The recovery process must be documented, owned, tested, monitored,
repeatable, and measurable.

## 70.4 DR Must Be Tested Before an Incident

The first failover should never occur during the first real disaster.

## 70.5 Recovery Must Be Measured

Every exercise should measure actual RPO, actual RTO, replication lag,
failover duration, application recovery duration, and failback duration.

# Recovery Objectives

## 70.6 Business RPO

Example: `RPO = 30 minutes`.

## 70.7 Business RTO

Example: `RTO = 2 hours`.

## 70.8 Technical RPO

Technical targets should provide margin. Example: business RPO 30
minutes; technical target 20 minutes.

## 70.9 RPO Warning Threshold

Example: warning at 20 minutes.

## 70.10 RPO Critical Threshold

Example: critical at 30 minutes.

## 70.11 RTO Breakdown

  Activity                        Target
  ------------------------ -------------
  Detection                       10 min
  Decision                        15 min
  Snowflake failover              15 min
  Integration activation          20 min
  Application routing             20 min
  Validation                      20 min
  Buffer                          20 min
  **Total**                  **120 min**

# DR Ownership

## 70.12 Required Owners

Define Business Owner, Incident Commander, Snowflake Owner, Application
Owner, Network Owner, Security Owner, Data Pipeline Owner, and Cloud
Owner.

## 70.13 Failover Authority

Document who may authorize failover.

## 70.14 Failback Authority

Failback also requires explicit authorization.

## 70.15 Escalation Path

Document primary/secondary on-call, engineering lead, incident
management, Snowflake Support, cloud-provider support, and business
leadership as applicable.

# DR Inventory

## 70.16 Snowflake Inventory

Maintain accounts, regions, clouds, databases, replication/failover
groups, roles, users, warehouses, integrations, network policies,
resource monitors, and shares.

## 70.17 External Inventory

Maintain applications, Kafka, Airflow, Databricks, Kubernetes, cloud
IAM, external storage, secrets, DNS, private connectivity, and
monitoring.

## 70.18 Dependency Matrix

  Component   Primary   DR        Owner      Recovery
  ----------- --------- --------- ---------- ---------------------
  PROD_DB     us-east   us-west   DBRE       Replication
  APP_ROLE    Primary   DR        DBRE       Account replication
  APP_WH      Primary   DR        DBRE       Failover/IaC
  Kafka       East      West      Data Eng   Connector switch
  App         East      West      App Team   DR deployment
  Secrets     East      West      Security   Secret replication
  Network     East      West      Network    DR routing

# DR Readiness

## 70.19 Daily Readiness

Automatically monitor replication status, lag, refresh failures,
secondary availability, and critical object presence.

## 70.20 Weekly Readiness

Review RPO compliance, replication failure trends, DR capacity,
configuration drift, and open defects.

## 70.21 Monthly Readiness

Validate authentication, service-account access, critical queries,
warehouses, and integrations where practical and approved.

## 70.22 Quarterly/Scheduled DR Exercise

Perform controlled DR testing according to criticality and
organizational requirements.

# Monitoring

## 70.23 DR Dashboard

Track primary/secondary account and region, replication/failover group,
last successful refresh, lag, refresh duration, failure count, RPO
target/status, and last DR/failover/failback tests.

## 70.24 RPO Alert

Example: warning lag \>=20 minutes; critical \>=30 minutes.

## 70.25 Replication Failure Alert

Investigate failures immediately when they threaten DR readiness.

## 70.26 Configuration Drift

Monitor changes to groups, databases, roles, warehouses, integrations,
authentication, and network policies.

# Pre-Incident Checklist

## 70.27 Production DR Readiness Checklist

-   [ ] RPO approved
-   [ ] RTO approved
-   [ ] Failure scenarios documented
-   [ ] Primary account documented
-   [ ] Secondary account documented
-   [ ] Replication healthy
-   [ ] Replication lag monitored
-   [ ] RPO alerts configured
-   [ ] Secondary data validated
-   [ ] RBAC validated
-   [ ] Authentication validated
-   [ ] Service accounts validated
-   [ ] Warehouses validated
-   [ ] Warehouse capacity tested
-   [ ] Integrations validated
-   [ ] Network validated
-   [ ] External storage validated
-   [ ] Ingestion DR documented
-   [ ] Application DR documented
-   [ ] Split-brain prevention documented
-   [ ] Failover authority documented
-   [ ] Failback authority documented
-   [ ] Runbook current
-   [ ] DR test current
-   [ ] Remediation items tracked

# Incident Detection

## 70.28 Possible DR Trigger

Examples include Snowflake regional outage, cloud-region outage,
extended account outage, regional network isolation, major
infrastructure failure, and application-region outage.

## 70.29 DR Is Not Always the Correct Response

Do not automatically fail over for a bad query, warehouse sizing issue,
user permission issue, application bug, logical corruption, or single
pipeline failure.

## 70.30 Classify the Incident

Determine what failed, what still works, failure domain, duration,
estimated recovery, whether data is still changing, and whether
replication is working.

# Incident Command

## 70.31 Establish Incident Commander

One person coordinates decision making, communication, owners, timeline,
risk, and failover authorization.

## 70.32 Assign Technical Leads

Assign Snowflake, Application, Pipeline, Network, and Security leads as
required.

## 70.33 Create Incident Timeline

Record incident start, detection, replication state, last refresh, DR
declaration, promotion, application activation, recovery, and failback.

# Primary Assessment

## 70.34 Verify Primary Context

``` sql
SELECT
    CURRENT_ORGANIZATION_NAME(),
    CURRENT_ACCOUNT_NAME(),
    CURRENT_REGION(),
    CURRENT_TIMESTAMP();
```

## 70.35 Determine Primary Availability

Check login, queries, writes, warehouses, network, and integrations.

## 70.36 Determine Recovery Estimate

Obtain the best estimate from Snowflake, cloud provider, network team,
and internal platform team.

## 70.37 Compare Recovery With RTO

If expected primary recovery exceeds remaining RTO, failover becomes
increasingly justified.

# Replication Assessment

## 70.38 Determine Last Successful Replication

Record last successful refresh, completion time, last attempted refresh,
and status.

## 70.39 Determine Secondary Data Point

``` sql
SELECT MAX(UPDATED_AT) AS LAST_UPDATE
FROM PROD_DB.EMPI.PATIENT;
```

## 70.40 Determine Last Primary Data Point

If accessible, run the same freshness query against primary.

## 70.41 Calculate Potential Data Loss

Example: primary last update 10:29; secondary 10:17; potential exposure
12 minutes.

## 70.42 Compare With RPO

Example: exposure 12 minutes; RPO 30 minutes; status within RPO.

## 70.43 Communicate Data-Loss Exposure

Incident leadership should understand expected recovery point before
failover.

# Secondary Assessment

## 70.44 Verify Secondary Context

``` sql
SELECT
    CURRENT_ORGANIZATION_NAME(),
    CURRENT_ACCOUNT_NAME(),
    CURRENT_REGION(),
    CURRENT_TIMESTAMP();
```

## 70.45 Validate Databases

``` sql
SHOW DATABASES;
```

## 70.46 Validate Critical Schemas

``` sql
SHOW SCHEMAS IN DATABASE PROD_DB;
```

## 70.47 Validate Critical Tables

``` sql
SHOW TABLES IN DATABASE PROD_DB;
```

## 70.48 Validate Data

``` sql
SELECT
    COUNT(*) AS ROW_COUNT,
    MAX(UPDATED_AT) AS LAST_UPDATE
FROM PROD_DB.EMPI.PATIENT;
```

## 70.49 Validate Roles

``` sql
SHOW ROLES;
```

## 70.50 Validate Users

``` sql
SHOW USERS;
```

## 70.51 Validate Warehouses

``` sql
SHOW WAREHOUSES;
```

## 70.52 Validate Authentication

Test administrator, application service account, and ETL service account
through approved procedures.

## 70.53 Validate Integrations

Test required storage, API, notification, and external-access
integrations.

## 70.54 Validate Network

Confirm application and operator connectivity.

# Failover Decision

## 70.55 Decision Inputs

Evaluate business impact, primary recovery estimate, remaining RTO,
secondary readiness, replication point, potential data loss, security
readiness, and application readiness.

## 70.56 Failover Decision Record

Record time, decision, approver, reason, RPO exposure, known risks, and
secondary status.

## 70.57 Do Not Promote Without Knowing Replication State

Promotion without understanding recovery point can cause unexpected data
loss.

# Fence Primary

## 70.58 Why Fencing Matters

Avoid simultaneous old-primary and new-primary writes.

## 70.59 Fencing Methods

Depending on architecture, stop ingestion, disable application writes,
remove credentials, change routing, disable jobs, or restrict network
access using safe approved mechanisms.

## 70.60 Record Fencing Status

Record old primary fenced as YES, NO, or UNKNOWN. Treat unknown as
explicit split-brain risk.

# Promote DR

## 70.61 Promotion

Use the current supported Snowflake failover process.

## 70.62 Promotion Command

The exact command must come from the validated production runbook and
current Snowflake documentation. Do not rely on memory during an
incident.

## 70.63 Record Promotion

Record start/end, operator, result, request/query identifier, and
errors.

# Post-Promotion Snowflake Validation

## 70.64 Verify New Primary

Confirm promoted environment is authoritative.

## 70.65 Validate Database

``` sql
SHOW DATABASES;
```

## 70.66 Validate Data Freshness

``` sql
SELECT MAX(UPDATED_AT)
FROM PROD_DB.EMPI.PATIENT;
```

## 70.67 Validate Representative Records

Select known records from critical datasets.

## 70.68 Validate Read

Run a safe representative query.

## 70.69 Validate Write

Where approved, use a designated validation object for a controlled
write.

## 70.70 Validate RBAC

Test actual production roles.

## 70.71 Validate Warehouse

Confirm required warehouses execute queries.

# Activate Capacity

## 70.72 Scale Warehouses

Scale reduced passive capacity to production requirement.

## 70.73 Validate Multi-Cluster Settings

Confirm concurrency settings where applicable.

## 70.74 Validate Resource Controls

Confirm required cost/resource controls.

# Activate Integrations

## 70.75 Storage Integration

Validate Snowflake → cloud identity → storage.

## 70.76 API Integration

Validate API connectivity and authentication.

## 70.77 Notification Integration

Validate notification destinations.

## 70.78 External Access

Validate required outbound connectivity.

# Activate Ingestion

## 70.79 Kafka

Redirect approved connectors and validate account, authentication, role,
warehouse, database, and network.

## 70.80 Batch Pipelines

Activate required Airflow, Databricks, Glue, ADF, Kubernetes jobs,
Lambda, and custom ETL.

## 70.81 Prevent Duplicate Pipelines

Verify old pipelines are fenced before DR pipelines write.

## 70.82 Validate New Data

Confirm new source data reaches DR Snowflake.

# Activate Application

## 70.83 Application Configuration

Update application to use DR Snowflake.

## 70.84 Validate Secret

Confirm approved DR credential.

## 70.85 Validate Connection

Application-to-Snowflake authentication must succeed.

## 70.86 Validate Application Workflow

Test critical business workflows.

# Smoke Testing

## 70.87 Minimum Smoke Test

Validate login, critical query, read, write, warehouse, ingestion,
application, and monitoring.

## 70.88 Business Validation

Technical success does not equal business recovery. Obtain
service/business-owner confirmation.

# Declare Service Restored

## 70.89 Recovery Time

Record incident start, DR declaration, Snowflake promotion, application
recovery, and business validation.

## 70.90 Calculate Actual RTO

Example: DR declaration 10:20; business restored 11:32; actual RTO 72
minutes.

## 70.91 Calculate Actual RPO

Example: last primary transaction 10:14; latest available in DR 10:08;
actual RPO 6 minutes.

# Operating in DR

## 70.92 DR Is Now Production

After failover, the DR environment is production.

## 70.93 Monitor Closely

Watch warehouse load, query latency, queueing, ingestion, errors,
application latency, and integration failures.

## 70.94 Preserve Incident Evidence

Keep logs, query IDs, replication status, timeline, screenshots, error
messages, and change records according to policy.

# Failback Preparation

## 70.95 Do Not Rush Failback

Fail back only after the original environment is stable.

## 70.96 Restore Original Environment

Validate Snowflake, cloud, network, identity, storage, and application
infrastructure.

## 70.97 Establish Replication Back

Synchronize current production toward the recovered environment using
supported mechanisms.

## 70.98 Monitor Synchronization

Track lag, refresh status, freshness, and errors.

## 70.99 Validate Recovered Environment

Repeat pre-failover validation.

# Failback

## 70.100 Failback Decision

Evaluate stability, synchronization, business timing, change freeze,
application readiness, and risk.

## 70.101 Schedule Failback

Prefer a controlled maintenance/change window where practical.

## 70.102 Fence Current Primary

Prevent writes before authority changes.

## 70.103 Final Synchronization

Complete final supported synchronization.

## 70.104 Switch Authority

Promote/switch the recovered environment using the approved Snowflake
process.

## 70.105 Redirect Ingestion

Move pipelines back.

## 70.106 Redirect Applications

Move application traffic back.

## 70.107 Validate Service

Repeat authentication, read, write, ingestion, application, and
monitoring checks.

## 70.108 Restore DR Posture

Re-establish normal primary-to-secondary replication.

# Logical Corruption

## 70.109 DR Runbook Is Different for Logical Corruption

Do not automatically use regional failover for DELETE, DROP, bad UPDATE,
bad deployment, or incorrect RBAC.

## 70.110 Stop the Cause

Disable the destructive process first.

## 70.111 Determine Corruption Time

Record timestamp, query ID, user, job, and deployment.

## 70.112 Check Secondary State

Determine whether corruption already replicated.

## 70.113 Preserve Clean Secondary

If secondary is clean, do not refresh until recovery is planned.

## 70.114 Evaluate Recovery Options

Consider Time Travel, historical clone, UNDROP, selective restore,
source replay, and preserved secondary.

# DR Testing Program

## 70.115 Testing Levels

1.  Documentation Review
2.  Component Validation
3.  Replication Validation
4.  Technical Failover
5.  Application Failover
6.  Full Business DR Exercise

## 70.116 Level 1 --- Documentation Review

Verify owners, contacts, commands, account identifiers, regions,
dependencies, runbooks, and escalations.

## 70.117 Level 2 --- Component Validation

Test authentication, warehouses, network, integrations, and service
accounts.

## 70.118 Level 3 --- Replication Validation

Validate refresh, lag, data, objects, and alerts.

## 70.119 Level 4 --- Technical Failover

Promote secondary under controlled testing and validate Snowflake.

## 70.120 Level 5 --- Application Failover

Redirect ingestion and applications.

## 70.121 Level 6 --- Full Business Exercise

Test complete service with business validation and controlled failback.

# DR Test Preparation

## 70.122 Test Change Record

Create an approved change/test record.

## 70.123 Test Objectives

Define RPO/RTO targets, components, expected outcome, success criteria,
and rollback criteria.

## 70.124 Test Participants

Include DBRE/SRE, Application, Data Engineering, Cloud, Network,
Security, Incident Management, and Business Owner as required.

## 70.125 Test Timeline

Define start, failover, validation, business test, failback, and end.

## 70.126 Test Communication

Notify affected stakeholders before the exercise.

# DR Test Execution

## 70.127 Capture Baseline

Record primary/secondary data points, lag, warehouse state, and
application state.

## 70.128 Simulate Failure

Use a safe approved method without uncontrolled production impact.

## 70.129 Execute Runbook Exactly

Follow documented procedure. Required improvisation identifies a runbook
gap.

## 70.130 Record Every Step

Capture step, start/end time, owner, result, and issue.

## 70.131 Measure Failover Time

Measure Snowflake failover separately from full service recovery.

## 70.132 Measure Application Recovery

Track when the application becomes operational.

## 70.133 Measure Actual RPO

Compare source and recovered business-data points.

## 70.134 Measure Actual RTO

Measure end-to-end recovery.

## 70.135 Execute Failback

A complete exercise includes controlled failback.

# DR Test Acceptance Criteria

## 70.136 Example Acceptance Criteria

-   [ ] Replication healthy before test
-   [ ] Secondary promoted successfully
-   [ ] Actual RPO \<= approved RPO
-   [ ] Actual RTO \<= approved RTO
-   [ ] Authentication works
-   [ ] RBAC works
-   [ ] Warehouses operational
-   [ ] Integrations operational
-   [ ] Ingestion operational
-   [ ] Application operational
-   [ ] Monitoring operational
-   [ ] No uncontrolled dual writes
-   [ ] Failback successful
-   [ ] Normal replication restored

## 70.137 Failed Test

A failed DR test is valuable if defects are identified and remediated.
Do not hide failed acceptance criteria.

# DR Test Report

## 70.138 Test Summary

Document test date, scenario, participants, primary/secondary,
target/actual RPO, target/actual RTO, and overall result.

## 70.139 Timeline

  Time    Event
  ------- --------------------
  10:00   Test started
  10:10   DR declared
  10:20   Secondary promoted
  10:35   Ingestion active
  10:45   Application active
  10:52   Business validated
  11:30   Failback started
  12:00   Failback complete

## 70.140 Findings

Classify Critical, High, Medium, Low, or Improvement.

## 70.141 Remediation

Every issue should have owner, priority, due date, and status.

# Troubleshooting During DR

## 70.142 Secondary Not Ready

Check replication state, lag, objects, Snowflake service status, and
account access.

## 70.143 Authentication Failure

Check account identifier, SSO, MFA, OAuth, key pair, network policy, and
IdP.

## 70.144 Warehouse Failure

Check warehouse existence, privileges, state, resource monitor, and
capacity.

## 70.145 Integration Failure

Check Snowflake configuration and external cloud/network dependencies.

## 70.146 Ingestion Failure

Check target account, credentials, role, warehouse, database, connector,
and network.

## 70.147 Application Failure

Check endpoint, secret, authentication, role, warehouse, network, and
configuration.

## 70.148 Performance Degradation

Check warehouse size, concurrency, queueing, cache warm-up, query
profile, and external latency.

# Emergency Failover Runbook

## 70.149 Emergency Runbook

1.  Open incident.
2.  Assign incident commander.
3.  Record incident start.
4.  Identify failure domain.
5.  Assess primary.
6.  Estimate primary recovery.
7.  Check remaining RTO.
8.  Check replication state.
9.  Record last successful refresh.
10. Determine primary data point.
11. Determine secondary data point.
12. Calculate data-loss exposure.
13. Validate secondary.
14. Validate authentication.
15. Validate network.
16. Obtain failover authorization.
17. Fence old primary where possible.
18. Record fencing state.
19. Promote secondary.
20. Verify new primary.
21. Validate databases.
22. Validate critical data.
23. Scale warehouses.
24. Validate RBAC.
25. Validate integrations.
26. Redirect ingestion.
27. Validate new ingestion.
28. Redirect applications.
29. Execute smoke tests.
30. Obtain business validation.
31. Record recovery time.
32. Calculate actual RPO.
33. Calculate actual RTO.
34. Communicate service restoration.
35. Monitor DR production.
36. Begin failback planning.

# Emergency Failback Runbook

## 70.150 Emergency Failback Runbook

1.  Confirm original environment stable.
2.  Restore required infrastructure.
3.  Establish replication toward recovered environment.
4.  Synchronize.
5.  Monitor lag.
6.  Validate data.
7.  Validate authentication.
8.  Validate RBAC.
9.  Validate warehouses.
10. Validate integrations.
11. Validate network.
12. Validate application readiness.
13. Obtain failback authorization.
14. Schedule failback.
15. Notify stakeholders.
16. Fence current primary.
17. Complete final synchronization.
18. Switch authority.
19. Redirect ingestion.
20. Validate ingestion.
21. Redirect application.
22. Run smoke tests.
23. Obtain business validation.
24. Restore normal replication.
25. Monitor.
26. Close DR operation.
27. Start post-incident review.

# Production Scenario

## 70.151 Patient360 DR Scenario

Primary: Snowflake AWS us-east.

Secondary: Snowflake AWS us-west.

Application: Patient360.

Requirements: RPO = 30 minutes; RTO = 2 hours.

## 70.152 Incident

At 10:00 the primary region becomes unavailable.

## 70.153 Detection

Monitoring alerts at 10:03.

## 70.154 Incident Declaration

Incident commander assigned at 10:08.

## 70.155 Replication Assessment

Last successful secondary data: 09:54. Last confirmed primary data:
09:59. Potential data loss: 5 minutes, within the 30-minute RPO.

## 70.156 Recovery Estimate

Expected regional recovery \>3 hours. Business RTO is 2 hours. Failover
is authorized.

## 70.157 Failover

At 10:20 the secondary is promoted.

## 70.158 Snowflake Validation

Complete by 10:30.

## 70.159 Ingestion Recovery

Kafka/ETL switched by 10:42.

## 70.160 Application Recovery

Patient360 switched to DR by 10:52.

## 70.161 Business Validation

Completed at 11:00.

## 70.162 Actual RTO

DR declaration 10:08; service restored 11:00; actual RTO 52 minutes.

## 70.163 Actual RPO

Last primary 09:59; DR recovery point 09:54; actual RPO 5 minutes.

# Production Standards

## 70.164 Common Mistakes

Avoid untested/outdated runbooks, undefined RPO/RTO, unclear
failover/failback authority, missing dependency
matrix/monitoring/alerts/secondary
validation/authentication/network/integration/ingestion/application
DR/split-brain protection/data-loss calculation/business
validation/RPO-RTO measurement/failback testing/remediation tracking.

## 70.165 Production Standards

Every critical service should have an owned DR runbook;
business-approved RPO/RTO; documented scenarios and authorities;
maintained dependency matrix; continuous replication/lag monitoring and
pre-breach alerts; validated secondary/authentication/service
accounts/network/capacity/integrations/ingestion/application;
single-write authority; data-loss calculation before failover;
timeline/business validation; measured actual RPO/RTO; tested failback;
remediation ownership; and runbook updates after every exercise or
incident.

## 70.166 SRE/DBRE DR Checklist

-   [ ] Business service identified
-   [ ] Business owner assigned
-   [ ] DR owner assigned
-   [ ] RPO approved
-   [ ] RTO approved
-   [ ] Failure scenarios documented
-   [ ] Primary documented
-   [ ] Secondary documented
-   [ ] Dependency matrix current
-   [ ] Replication configured
-   [ ] Replication monitored
-   [ ] Lag monitored
-   [ ] RPO alerts configured
-   [ ] Secondary data validated
-   [ ] RBAC validated
-   [ ] Authentication validated
-   [ ] Service accounts validated
-   [ ] Warehouses validated
-   [ ] DR capacity tested
-   [ ] Integrations validated
-   [ ] Network validated
-   [ ] External storage validated
-   [ ] Ingestion DR documented
-   [ ] Application DR documented
-   [ ] Split-brain controls documented
-   [ ] Failover authority documented
-   [ ] Failback authority documented
-   [ ] Emergency failover runbook complete
-   [ ] Emergency failback runbook complete
-   [ ] Logical corruption runbook complete
-   [ ] DR test plan complete
-   [ ] DR test executed
-   [ ] Failback tested
-   [ ] Actual RPO measured
-   [ ] Actual RTO measured
-   [ ] Test report completed
-   [ ] Remediation tracked
-   [ ] Runbook updated

## 70.167 Operational Quick Reference

Normal Operation → Monitor Replication → Validate DR Readiness → Test
Regularly → Incident → Classify Failure → Assess Primary → Check RPO/RTO
→ Validate Secondary → Authorize DR → Fence Primary → Promote Secondary
→ Validate Snowflake → Activate Ingestion → Activate Application →
Business Validation → Measure RPO/RTO → Operate in DR → Synchronize
Original → Failback → Post-DR Review.

## 70.168 Key Takeaways

1.  DR must be operational, not just architectural.
2.  DR should recover the business service, not only Snowflake.
3.  Every critical service needs an owned runbook.
4.  RPO must be explicitly defined.
5.  RTO must be explicitly defined.
6.  Technical targets should provide margin below business limits.
7.  Failover authority must be documented.
8.  Failback authority must be documented.
9.  Maintain a dependency matrix.
10. Monitor replication continuously.
11. Alert before RPO breach.
12. Validate the secondary before an incident.
13. Test authentication.
14. Test service accounts.
15. Test network connectivity.
16. Test warehouse capacity.
17. Test integrations.
18. Test ingestion recovery.
19. Test application recovery.
20. Prevent dual writers.
21. Calculate potential data loss before failover.
22. Record failover decisions.
23. Measure actual RPO.
24. Measure actual RTO.
25. Treat DR as production after failover.
26. Do not rush failback.
27. Synchronize before failback.
28. Test failback.
29. Every DR test should produce measurable evidence.
30. Update the runbook after every test and incident.

## 70.169 Chapter Completion Checklist

After completing this chapter, you should be able to build a production
Snowflake DR runbook; define RPO/RTO and operational components; define
ownership/authority; build inventories/dependency matrix; establish
readiness checks and monitoring; identify/classify DR triggers;
establish incident command; assess primary and replication state;
calculate data-loss exposure; validate secondary; make controlled
failover decisions; fence primary; promote DR; validate Snowflake;
activate capacity/integrations/ingestion/applications; perform
technical/business tests; measure actual RPO/RTO; operate in DR; execute
failback; distinguish logical corruption; build tiered testing; define
acceptance criteria/reporting; troubleshoot DR failures; execute
emergency failover/failback; and apply SRE/DBRE standards.

**Chapter 70 --- Snowflake Disaster Recovery Runbook & Testing:
Complete**

# Part Completion

Chapters 66--70 now form the complete Snowflake replication and
disaster-recovery sequence:

``` text
Chapter 66
Database Replication
        |
        v
Chapter 67
Account Replication
        |
        v
Chapter 68
Failover Groups
        |
        v
Chapter 69
Cross-Region / Cross-Cloud DR
        |
        v
Chapter 70
DR Runbook & Testing
```

The progression is:

``` text
REPLICATE DATA
      |
      v
REPLICATE SERVICE STATE
      |
      v
ENABLE FAILOVER
      |
      v
DESIGN REGIONAL/CLOUD DR
      |
      v
OPERATE + TEST DR
```
