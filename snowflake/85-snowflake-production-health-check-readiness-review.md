# Chapter 85 --- Snowflake Production Health Check & Readiness Review

## 85.1 Overview

A production Snowflake environment should not be considered healthy
simply because:

``` text
Queries are running
```

Production readiness requires validation across:

``` text
Availability
Performance
Warehouses
Concurrency
Storage
Data pipelines
Security
RBAC
Monitoring
Cost
Backup / recovery
Disaster recovery
Operational ownership
Incident readiness
```

The objective is:

``` text
Snowflake Environment
        |
        v
Architecture Review
        |
        v
Performance Review
        |
        v
Security Review
        |
        v
Operational Review
        |
        v
Recovery Review
        |
        v
Cost Review
        |
        v
PRODUCTION READY
```

**Primary rule: Production readiness must be demonstrated with evidence,
not assumed from successful deployment.**

## 85.2 Health Check vs Readiness Review

A **health check** evaluates the current environment.

``` text
Is the environment healthy now?
```

A **readiness review** asks:

``` text
Can this environment safely support production?
```

Both are necessary.

## 85.3 When to Perform a Health Check

Perform health checks:

``` text
Before production launch
After major architecture changes
After incidents
After warehouse changes
After security changes
After large migrations
Before major business events
Periodically in production
```

## 85.4 Review Domains

Use the following domains:

``` text
1. Account and environment
2. Architecture
3. Warehouses
4. Query performance
5. Concurrency
6. Data/storage
7. Ingestion
8. Transformation
9. Security
10. RBAC
11. Authentication
12. Network
13. Monitoring
14. Cost
15. Recovery
16. DR
17. Automation
18. Operations
19. Incident readiness
20. Ownership
```

## 85.5 Establish Environment Context

Start by verifying where you are connected.

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

Never perform a production review without verifying account and
environment context.

## 85.6 Environment Inventory

Capture:

``` text
Organization
Account
Cloud
Region
Environment
Edition
Critical applications
Critical databases
Warehouses
Integrations
Data pipelines
External dependencies
```

## 85.7 Business Context

Document:

``` text
Business services
Customer-facing applications
Critical datasets
Peak hours
Maintenance windows
SLA/SLO
RTO
RPO
Compliance requirements
```

Technology readiness must align with business requirements.

## 85.8 Architecture Review

Document the architecture.

Example:

``` text
Source Systems
      |
      v
Cloud Storage
      |
      v
Snowpipe / COPY
      |
      v
L1 / RAW
      |
      v
L2 / CURATED
      |
      v
L3 / CONSUMPTION
      |
      +------> Patient360
      |
      +------> BI
      |
      +------> Data Sharing
```

## 85.9 Architecture Questions

Ask:

``` text
Are workloads clearly separated?
Are ingestion paths documented?
Are transformation dependencies known?
Are consumers known?
Are external dependencies known?
Is failure propagation understood?
```

## 85.10 Warehouse Inventory

``` sql
SHOW WAREHOUSES;
```

Capture for each warehouse:

``` text
Name
Size
State
Auto suspend
Auto resume
Min clusters
Max clusters
Scaling policy
Owner
Purpose
Workload
SLA
```

## 85.11 Warehouse Ownership

Every production warehouse should have an owner.

Bad:

``` text
PROD_WH
Owner: Unknown
Purpose: Multiple
```

Better:

``` text
PATIENT360_APP_PROD_WH
Owner: Patient360 / Data Platform
Purpose: Patient360 application queries
SLA: P95 < 5 sec
```

## 85.12 Warehouse Naming

Production naming should clearly identify application, environment, and
purpose.

Example:

``` text
PATIENT360_APP_PROD_WH
EMPI_ETL_PROD_WH
BI_PROD_WH
```

## 85.13 Warehouse Right-Sizing

Review whether warehouses are undersized, right-sized, or oversized.

Use measured execution time, queueing, concurrency, SLA, and credits.

## 85.14 Warehouse Queueing

Review:

``` text
QUEUED_OVERLOAD_TIME
QUEUED_PROVISIONING_TIME
```

High queueing requires investigation.

## 85.15 Query Timing Review

``` sql
SELECT
    QUERY_ID,
    USER_NAME,
    ROLE_NAME,
    WAREHOUSE_NAME,
    QUERY_TYPE,
    TOTAL_ELAPSED_TIME,
    COMPILATION_TIME,
    EXECUTION_TIME,
    QUEUED_OVERLOAD_TIME,
    QUEUED_PROVISIONING_TIME,
    TRANSACTION_BLOCKED_TIME,
    START_TIME
FROM SNOWFLAKE.ACCOUNT_USAGE.QUERY_HISTORY
WHERE START_TIME >= DATEADD('day', -7, CURRENT_TIMESTAMP())
ORDER BY TOTAL_ELAPSED_TIME DESC;
```

## 85.16 Performance Baselines

Critical workloads should have baselines for P50, P95, and P99 for total
latency, execution, queue, and compilation.

## 85.17 Slow Query Review

Identify:

``` text
Top slow queries
High execution queries
High compilation queries
High queue queries
Blocked queries
Frequently executed expensive queries
```

## 85.18 Query Profile Review

For critical or expensive queries review:

``` text
Table scans
Partition pruning
Join behavior
Data explosion
Aggregation
Sorting
Spilling
Remote spill
```

## 85.19 Query Efficiency

Look for:

``` text
SELECT *
Unnecessary scans
Poor filtering
Repeated transformations
Large generated SQL
Excessive nested views
Large joins
Unnecessary sorting
```

## 85.20 Concurrency Review

Determine:

``` text
Average concurrency
Peak concurrency
Burst concurrency
Queue duration
Workload overlap
```

## 85.21 Workload Isolation Review

Verify whether application, ETL, BI, ad-hoc, and data science workloads
are appropriately isolated.

## 85.22 Shared Warehouse Risk

Flag architecture such as:

``` text
                SHARED_PROD_WH
                      |
       +--------------+--------------+
       |              |              |
       v              v              v
      API            ETL             BI
```

when workloads have different SLAs or create measurable contention.

## 85.23 Multi-Cluster Review

For concurrency-heavy workloads review:

``` text
MIN_CLUSTER_COUNT
MAX_CLUSTER_COUNT
SCALING_POLICY
```

and verify configuration against actual concurrency.

## 85.24 Auto-Suspend Review

Check whether idle warehouses remain running unnecessarily.

Also avoid settings that create excessive resume cycles for
latency-sensitive workloads.

## 85.25 Auto-Resume Review

Ensure workloads that depend on automatic availability are configured
appropriately.

## 85.26 Provisioning Review

If `QUEUED_PROVISIONING_TIME` is significant, review warehouse lifecycle
behavior and workload requirements.

## 85.27 Storage Review

Review:

``` text
Database growth
Table growth
Retention
Transient objects
Temporary objects
Clones
Stages
Historical data
```

## 85.28 Storage Trend

Track current storage, monthly growth, and 3-month, 6-month, and
12-month forecasts.

## 85.29 Retention Review

Verify Time Travel retention is aligned with recovery requirements,
compliance, cost, and object criticality.

Do not apply one retention value blindly everywhere.

## 85.30 Fail-safe Awareness

Understand which objects and editions/features are subject to Snowflake
recovery capabilities and what operational recovery actions are
customer-controlled versus Snowflake-controlled.

Do not treat Fail-safe as a normal user-operated backup mechanism.

## 85.31 Clone Review

Identify unnecessary long-lived clones.

Clones are operationally useful but should still have owner, purpose,
lifecycle, and cleanup.

## 85.32 Temporary Object Review

Look for excessive temporary or transient object creation.

Ensure failed pipelines clean up objects appropriately.

## 85.33 Data Growth Review

For critical tables capture:

``` text
Rows
Logical size
Growth rate
Retention
Query frequency
Downstream consumers
```

## 85.34 Ingestion Inventory

Document every ingestion path.

``` text
COPY INTO
Snowpipe
Snowpipe Streaming
Connectors
External ETL
Custom applications
```

## 85.35 Ingestion Ownership

Each production ingestion pipeline should have:

``` text
Owner
Source
Target
SLA
Monitoring
Retry behavior
Replay procedure
Runbook
```

## 85.36 Stage Review

Review internal stages, external stages, storage integrations, path
conventions, permissions, encryption, and lifecycle.

## 85.37 File Format Review

Verify production file formats are explicitly managed.

Examples:

``` text
CSV
JSON
Parquet
Avro
ORC
```

Avoid hidden assumptions in ingestion jobs.

## 85.38 COPY Review

Review error handling, validation, duplicate protection, replay
behavior, file sizing, and load history.

## 85.39 Snowpipe Review

For Snowpipe validate pipe definition, pipe status, notification path,
storage integration, load history, failure handling, and monitoring.

## 85.40 Pipeline Freshness

Every critical dataset should have a freshness expectation.

Example:

``` text
DAP.L1.EMPI
Expected freshness: < 5 minutes
```

## 85.41 Transformation Review

Document dependencies:

``` text
L1
 |
 v
L2
 |
 v
L3
 |
 v
Consumer
```

Do not stop investigation at ingestion when downstream transformations
may be stale.

## 85.42 Task Review

``` sql
SHOW TASKS;
```

Review state, schedule, dependencies, failures, owner, and
warehouse/serverless configuration.

## 85.43 Stream Review

For stream-based pipelines validate consumer, consumption frequency,
failure behavior, recovery process, and staleness risk.

## 85.44 Dynamic Table Review

Where dynamic tables are used, verify target lag, refresh behavior,
dependencies, failures, cost, and freshness against the workload
requirement.

## 85.45 Data Quality

Production readiness requires data validation.

Check:

``` text
Row counts
Null rates
Duplicates
Schema
Business rules
Freshness
Reconciliation
```

## 85.46 Source-to-Target Reconciliation

For critical pipelines:

``` text
Source count
      |
      v
L1 count
      |
      v
L2 count
      |
      v
Consumer count
```

Understand expected transformations before interpreting differences.

## 85.47 Schema Drift

Verify detection for:

``` text
New columns
Removed columns
Type changes
JSON structure changes
Required-field changes
```

## 85.48 Authentication Review

Inventory authentication methods:

``` text
SSO
Key pair
OAuth
Password
Workload identity
```

Use methods appropriate to human and service access.

## 85.49 Service Accounts

Every service account should have:

``` text
Owner
Application
Authentication method
Secret/key location
Rotation procedure
Role
Warehouse
Environment
```

## 85.50 Shared Credentials

Flag shared service identities where attribution or security is
weakened.

Prefer workload-specific identities.

## 85.51 Key Rotation

For key-pair authentication document rotation schedule, overlap
strategy, secret update, validation, and rollback.

Do not discover the process during an outage.

## 85.52 OAuth Review

Validate integration, issuer, audience, role mapping, token lifecycle,
rotation, and monitoring.

## 85.53 SSO Review

Validate identity provider, user mapping, MFA requirements, certificate
lifecycle, and break-glass access.

## 85.54 RBAC Review

Start with:

``` sql
SHOW ROLES;
SHOW USERS;
```

Then review role hierarchy and grants.

## 85.55 Least Privilege

Users and services should have only required privileges.

Avoid:

``` text
ACCOUNTADMIN for applications
SECURITYADMIN for ETL
Broad ownership for convenience
```

## 85.56 Privilege Chain

For table access validate:

``` text
Warehouse USAGE
Database USAGE
Schema USAGE
Object privilege
```

## 85.57 Future Grants

Verify future grants where automatic access to new objects is required.

A common readiness failure is:

``` text
Existing tables work
New table deployed
Application loses access
```

## 85.58 Managed Access

Where managed access schemas are used, ensure teams understand the
grant-management model.

## 85.59 Ownership

Review object ownership.

Avoid orphaned or personal ownership for critical production objects.

## 85.60 Network Review

Review where applicable:

``` text
Network policies
Private connectivity
Firewall rules
Proxy
DNS
Cloud networking
Allowed source ranges
```

## 85.61 Dependency Review

Snowflake production may depend on:

``` text
Cloud storage
Identity provider
Secret manager
Notification service
ETL platform
Kubernetes
Application network
```

These dependencies belong in readiness reviews.

## 85.62 Monitoring Coverage

Production monitoring should include:

``` text
Query latency
Query failures
Warehouse queueing
Warehouse state
Pipeline freshness
Task failures
Snowpipe health
Authentication failures
Storage growth
Credit consumption
Application latency
```

## 85.63 Query Performance Monitoring

Monitor by workload:

``` text
P50
P95
P99
Execution
Queue
Compilation
Blocked time
```

## 85.64 Warehouse Monitoring

Monitor:

``` text
State
Size
Cluster count
Running queries
Queued queries
Provisioning
Credits
```

## 85.65 Pipeline Monitoring

Monitor:

``` text
Last successful load
Rows loaded
Files loaded
Failures
Lag
Freshness
Retry count
```

## 85.66 Security Monitoring

Monitor failed logins, unexpected access, privilege changes, role
changes, and authentication changes according to organizational
requirements.

## 85.67 Cost Monitoring

Monitor:

``` text
Credits/day
Credits/warehouse
Credits/workload
Storage growth
Cloud services usage
Budget variance
```

## 85.68 Resource Monitors

Review resource monitors where used.

Verify thresholds, notifications, actions, and owners.

## 85.69 Cost Guardrail Risk

A resource monitor action that suspends a critical warehouse can create
customer impact.

Ensure cost controls align with production criticality.

## 85.70 Cost Baseline

Document normal daily, weekly, monthly, and peak credits, plus storage
growth.

## 85.71 Cost Anomaly Detection

Alert on unexpected deviations from baseline rather than relying only on
monthly review.

## 85.72 Time Travel Readiness

Verify critical recovery scenarios have documented Time Travel
procedures.

Example:

``` text
Accidental DELETE
Accidental UPDATE
Accidental table DROP
```

## 85.73 Recovery Testing

A recovery procedure that has never been tested is not sufficient
production evidence.

Test recovery safely in nonproduction or controlled scenarios.

## 85.74 Recovery Objectives

Document RTO and RPO for critical workloads.

## 85.75 DR Architecture

For workloads requiring disaster recovery, document:

``` text
Primary account/region
Secondary account/region
Replication
Failover groups
Dependencies
DNS/application cutover
Authentication dependencies
Validation
Failback
```

## 85.76 Replication Review

Verify required objects and account capabilities are included in the
chosen replication architecture.

Do not assume everything is replicated automatically.

## 85.77 Failover Review

Document:

``` text
Who can initiate failover?
When?
How?
How is application traffic redirected?
How is data validated?
How is failback performed?
```

## 85.78 DR Testing

Test DR periodically.

A configuration existing on paper is not enough.

## 85.79 RTO Validation

Measure actual detection, decision, failover, application cutover, and
validation time.

Compare with RTO.

## 85.80 RPO Validation

Measure replication lag and validate whether the observed recovery point
meets business requirements.

## 85.81 Automation Review

Inventory automation:

``` text
Terraform
CI/CD
Snowflake CLI
Python
REST APIs
Custom scripts
```

## 85.82 Infrastructure as Code

Critical configuration should be managed consistently where practical.

Examples:

``` text
Warehouses
Roles
Grants
Integrations
Resource monitors
Databases
Schemas
```

## 85.83 Drift Detection

Production readiness includes identifying configuration drift between
expected state and actual state.

## 85.84 CI/CD Review

Validate approval, testing, rollback, secrets, environment separation,
deployment identity, and auditability.

## 85.85 Change Management

Production changes should capture:

``` text
Change
Reason
Owner
Start time
Expected impact
Validation
Rollback
```

## 85.86 Emergency Changes

Emergency changes still require evidence and post-change cleanup.

Temporary fixes should not silently become permanent architecture.

## 85.87 Incident Readiness

Verify runbooks exist for:

``` text
Query slowness
Warehouse queueing
Transaction blocking
Snowpipe failure
Missing data
Authentication failure
Authorization failure
Cost spike
Accidental DELETE/DROP
Regional outage
```

## 85.88 Incident Roles

Define:

``` text
Incident commander
Snowflake investigator
Application owner
Pipeline owner
Security
Cloud/network
Communications
```

before incidents occur.

## 85.89 Evidence Collection

During incidents capture query IDs, warehouse, user, role, query tag,
timing breakdown, pipeline state, authentication events, recent changes,
and application metrics.

## 85.90 Production Support Access

Support engineers should have sufficient read-only diagnostic access
without requiring broad administrative privileges for routine
investigations.

## 85.91 Break-Glass Access

Document:

``` text
When break-glass is allowed
Who approves
How access is obtained
How actions are audited
How access is removed
```

## 85.92 Documentation Review

Required documentation should include architecture, data flow, warehouse
inventory, RBAC, authentication, pipeline inventory, monitoring,
recovery, DR, incident runbooks, ownership, and escalation.

## 85.93 Ownership Matrix

  Component              Owner              Backup Owner
  ---------------------- ------------------ -------------------
  Patient360 warehouse   Platform           Patient360
  EMPI pipeline          Data Engineering   Platform
  SSO                    IAM                Security
  Snowpipe               Data Engineering   Platform
  DR                     Platform           Cloud Engineering

## 85.94 Escalation Matrix

Document escalation for Snowflake, application, data engineering, cloud,
network, security, IAM, and vendor support.

## 85.95 Readiness Evidence

Do not mark:

``` text
Monitoring: Complete
```

without evidence.

Better:

``` text
Monitoring: PASS
Evidence: Dashboard + alert test completed 2026-10-01
Owner: Platform SRE
```

## 85.96 Readiness Status

Use:

``` text
PASS
PASS WITH RISK
FAIL
NOT APPLICABLE
```

## 85.97 Risk Severity

Example:

``` text
Critical
High
Medium
Low
```

based on customer impact, likelihood, recovery difficulty, security
impact, and data risk.

## 85.98 Readiness Register

  Domain        Check                Status           Risk     Owner      Due Date
  ------------- -------------------- ---------------- -------- ---------- ----------
  Performance   P95 baseline         PASS             Low      SRE        Complete
  DR            Failover test        FAIL             High     Platform   TBD
  Security      Key rotation         PASS             Low      IAM        Complete
  Monitoring    Pipeline freshness   PASS WITH RISK   Medium   DE         TBD

## 85.99 Production Blockers

Examples that may justify blocking production launch:

``` text
No critical pipeline monitoring
No tested recovery path
Unknown production owner
Critical security gap
No rollback plan
Unacceptable performance
Uncontrolled warehouse queueing
No authentication recovery
DR required but untested
```

Severity depends on business requirements.

## 85.100 Exceptions

If a known risk is accepted, document:

``` text
Risk
Impact
Reason
Compensating control
Approver
Expiration
Remediation date
```

Risk acceptance should not mean risk disappearance.

## 85.101 Patient360 Readiness Example

Architecture:

``` text
Application
    |
    v
PATIENT360_APP_PROD_WH
    |
    v
DAP.L2.EMPI
```

Review finds:

``` text
P95 latency: PASS
Queueing: PASS
Warehouse isolation: PASS
Query tagging: PASS
Monitoring: PASS
Key rotation: PASS
Recovery: PASS
DR test: FAIL
```

Overall:

``` text
PASS WITH RISK
```

until the DR requirement is resolved or formally accepted.

## 85.102 EMPI Pipeline Readiness Example

``` text
Source
  |
  v
S3
  |
  v
Snowpipe
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

Validate source arrival, stage visibility, pipe status, load history, L1
freshness, L2 freshness, data quality, retry, replay, monitoring, and
ownership.

## 85.103 First 30-Minute Health Check

For a rapid production review:

1.  Verify account and region.
2.  Check service health.
3.  Review warehouses.
4.  Review failed queries.
5.  Review slow queries.
6.  Review queueing.
7.  Review blocked time.
8.  Review critical pipeline freshness.
9.  Review failed tasks.
10. Review Snowpipe status.
11. Review authentication failures.
12. Review recent privilege changes.
13. Review credits.
14. Review recent deployments.
15. Confirm monitoring.
16. Confirm incident ownership.

This is a rapid check, not a complete readiness certification.

## 85.104 Deep Health Check

A deep review should cover:

``` text
Architecture
Performance
Concurrency
Capacity
Storage
Ingestion
Transformation
Data quality
Authentication
Authorization
Networking
Monitoring
Cost
Recovery
DR
Automation
Change management
Incident readiness
Documentation
Ownership
```

## 85.105 Production Readiness Runbook

1.  Define scope.
2.  Identify business services.
3.  Capture SLA/SLO.
4.  Capture RTO/RPO.
5.  Verify account/region.
6.  Inventory databases.
7.  Inventory warehouses.
8.  Inventory pipelines.
9.  Inventory integrations.
10. Inventory service accounts.
11. Review architecture.
12. Review workload isolation.
13. Review warehouse sizing.
14. Review concurrency.
15. Review performance baseline.
16. Review query efficiency.
17. Review storage growth.
18. Review retention.
19. Review ingestion.
20. Review transformations.
21. Review data quality.
22. Review authentication.
23. Review RBAC.
24. Review network controls.
25. Review monitoring.
26. Review alerts.
27. Review cost.
28. Review resource monitors.
29. Review recovery.
30. Test recovery.
31. Review DR.
32. Test DR where required.
33. Review automation.
34. Review IaC.
35. Review CI/CD.
36. Review change management.
37. Review incident runbooks.
38. Review support access.
39. Review documentation.
40. Review ownership.
41. Record risks.
42. Assign remediation.
43. Obtain approval.
44. Schedule follow-up.

## 85.106 Health Check Report Template

``` text
SNOWFLAKE PRODUCTION HEALTH CHECK

Environment:
Account:
Region:
Date:
Reviewer:

Executive status:
PASS / PASS WITH RISK / FAIL

Business services:

Critical databases:

Critical warehouses:

Critical pipelines:

PERFORMANCE
Status:
Findings:
Risks:
Actions:

CONCURRENCY
Status:
Findings:
Risks:
Actions:

CAPACITY
Status:
Findings:
Risks:
Actions:

STORAGE
Status:
Findings:
Risks:
Actions:

INGESTION
Status:
Findings:
Risks:
Actions:

DATA QUALITY
Status:
Findings:
Risks:
Actions:

SECURITY
Status:
Findings:
Risks:
Actions:

RBAC
Status:
Findings:
Risks:
Actions:

MONITORING
Status:
Findings:
Risks:
Actions:

COST
Status:
Findings:
Risks:
Actions:

RECOVERY
Status:
Findings:
Risks:
Actions:

DISASTER RECOVERY
Status:
Findings:
Risks:
Actions:

AUTOMATION
Status:
Findings:
Risks:
Actions:

INCIDENT READINESS
Status:
Findings:
Risks:
Actions:

DOCUMENTATION
Status:
Findings:
Risks:
Actions:

OWNERSHIP
Status:
Findings:
Risks:
Actions:

Production blockers:

Accepted risks:

Required remediation:

Owners:

Due dates:

Next review:
```

## 85.107 Common Mistakes

Avoid:

``` text
Calling the environment healthy because queries work
No business SLA
No RTO/RPO
Unknown warehouse ownership
Shared warehouse without contention analysis
No P95/P99 baseline
No queue monitoring
No pipeline freshness monitoring
No authentication monitoring
Shared service accounts
No key rotation process
Overprivileged application roles
No future-grant strategy
No data-quality validation
No schema-drift handling
No storage-growth monitoring
No cost baseline
No resource-monitor impact review
No recovery testing
Treating Fail-safe as normal backup
No DR testing
Assuming replication includes everything
No IaC/drift review
No rollback process
No incident runbooks
No break-glass process
No escalation matrix
No evidence behind readiness status
Accepting risk without owner/date
No follow-up review
```

## 85.108 SRE/DBRE Readiness Checklist

### Environment

-   [ ] Account verified
-   [ ] Region verified
-   [ ] Environment verified
-   [ ] Business services documented
-   [ ] SLA/SLO documented
-   [ ] RTO documented
-   [ ] RPO documented

### Architecture

-   [ ] Architecture documented
-   [ ] Data flow documented
-   [ ] Dependencies documented
-   [ ] Workloads inventoried
-   [ ] Owners identified

### Warehouses

-   [ ] Warehouses inventoried
-   [ ] Purpose documented
-   [ ] Owner documented
-   [ ] Size reviewed
-   [ ] Auto-suspend reviewed
-   [ ] Auto-resume reviewed
-   [ ] Multi-cluster configuration reviewed
-   [ ] Resource monitors reviewed

### Performance

-   [ ] P50 baseline
-   [ ] P95 baseline
-   [ ] P99 baseline
-   [ ] Slow queries reviewed
-   [ ] Compilation reviewed
-   [ ] Execution reviewed
-   [ ] Queueing reviewed
-   [ ] Blocking reviewed
-   [ ] Query profiles reviewed

### Capacity

-   [ ] Peak concurrency measured
-   [ ] Workload isolation reviewed
-   [ ] Growth forecast created
-   [ ] Headroom defined
-   [ ] Connection pools reviewed
-   [ ] Retry behavior reviewed

### Data

-   [ ] Storage growth reviewed
-   [ ] Retention reviewed
-   [ ] Clones reviewed
-   [ ] Temporary objects reviewed
-   [ ] Data-quality checks implemented
-   [ ] Schema drift handled

### Ingestion

-   [ ] Pipelines inventoried
-   [ ] Pipeline owners documented
-   [ ] Snowpipe monitored
-   [ ] Load failures monitored
-   [ ] Freshness monitored
-   [ ] Replay documented
-   [ ] Retry documented

### Security

-   [ ] Authentication methods reviewed
-   [ ] Service accounts inventoried
-   [ ] Shared accounts reviewed
-   [ ] Key rotation documented
-   [ ] OAuth reviewed
-   [ ] SSO reviewed
-   [ ] Network controls reviewed

### RBAC

-   [ ] Roles reviewed
-   [ ] Least privilege validated
-   [ ] Role hierarchy documented
-   [ ] Ownership reviewed
-   [ ] Future grants reviewed
-   [ ] Managed access reviewed

### Monitoring

-   [ ] Query monitoring
-   [ ] Warehouse monitoring
-   [ ] Pipeline monitoring
-   [ ] Authentication monitoring
-   [ ] Cost monitoring
-   [ ] Application monitoring
-   [ ] Alerts tested

### Recovery

-   [ ] Time Travel procedures documented
-   [ ] Recovery tested
-   [ ] DELETE recovery tested
-   [ ] DROP recovery tested
-   [ ] Recovery owner documented

### DR

-   [ ] DR architecture documented
-   [ ] Replication reviewed
-   [ ] Failover documented
-   [ ] Failback documented
-   [ ] DR test completed
-   [ ] RTO validated
-   [ ] RPO validated

### Operations

-   [ ] IaC reviewed
-   [ ] Drift detection reviewed
-   [ ] CI/CD reviewed
-   [ ] Change process documented
-   [ ] Rollback documented
-   [ ] Incident runbooks available
-   [ ] Break-glass documented
-   [ ] Escalation documented

### Governance

-   [ ] Risks documented
-   [ ] Owners assigned
-   [ ] Due dates assigned
-   [ ] Exceptions approved
-   [ ] Follow-up review scheduled

## 85.109 Readiness Decision Tree

``` text
START READINESS REVIEW
          |
          v
BUSINESS REQUIREMENTS DEFINED?
          |
      +---+---+
      |       |
     No      Yes
      |       |
      v       v
   DEFINE   ARCHITECTURE
   SLA/RTO      |
   /RPO         v
            PERFORMANCE
                |
                v
            CAPACITY
                |
                v
             DATA
                |
                v
            SECURITY
                |
                v
              RBAC
                |
                v
           MONITORING
                |
                v
              COST
                |
                v
            RECOVERY
                |
                v
               DR
                |
                v
          OPERATIONS
                |
                v
        CRITICAL FAILURE?
             /     \
           Yes      No
            |        |
            v        v
          FAIL    RISKS?
                   /   \
                 Yes    No
                  |      |
                  v      v
             PASS WITH  PASS
                RISK
```

## 85.110 Key Principles

1.  Successful queries do not prove production readiness.
2.  Health and readiness are different assessments.
3.  Start with business requirements.
4.  Document SLA/SLO.
5.  Document RTO/RPO.
6.  Verify account and region before review.
7.  Maintain an architecture inventory.
8.  Every production warehouse needs ownership.
9.  Every production pipeline needs ownership.
10. Use measured warehouse sizing.
11. Monitor queueing.
12. Establish P50/P95/P99 baselines.
13. Review query profiles.
14. Review workload isolation.
15. Measure peak concurrency.
16. Forecast growth.
17. Monitor storage growth.
18. Align retention with recovery needs.
19. Do not treat Fail-safe as normal backup.
20. Manage clone lifecycle.
21. Monitor ingestion freshness.
22. Monitor transformation freshness.
23. Validate data quality.
24. Detect schema drift.
25. Use appropriate authentication for humans and services.
26. Rotate credentials and keys safely.
27. Apply least privilege.
28. Validate the complete privilege chain.
29. Plan grants for new objects.
30. Review external dependencies.
31. Monitor critical production signals.
32. Establish cost baselines.
33. Understand resource-monitor operational impact.
34. Test recovery.
35. Test DR.
36. Validate RTO and RPO.
37. Manage critical configuration consistently.
38. Detect configuration drift.
39. Require rollback for production changes.
40. Maintain incident runbooks.
41. Define break-glass access.
42. Maintain escalation paths.
43. Require evidence for readiness status.
44. Track risks with owners and dates.
45. Document accepted risks.
46. Treat temporary exceptions as temporary.
47. Review readiness after major changes.
48. Review readiness after incidents.
49. Schedule periodic production health checks.
50. Production readiness is a continuous operational discipline.

## 85.111 Chapter Completion Checklist

After completing this chapter, you should be able to:

-   Perform a Snowflake production health check.
-   Conduct a production readiness review.
-   Establish account and environment context.
-   Inventory critical Snowflake architecture.
-   Review warehouse configuration and ownership.
-   Evaluate query performance baselines.
-   Review concurrency and workload isolation.
-   Assess Snowflake capacity readiness.
-   Review storage and retention.
-   Review ingestion and Snowpipe readiness.
-   Review transformation pipelines.
-   Validate data quality and freshness.
-   Review authentication and service identities.
-   Review RBAC and least privilege.
-   Review network and external dependencies.
-   Assess monitoring and alert coverage.
-   Review cost controls and resource monitors.
-   Validate Time Travel recovery readiness.
-   Review disaster-recovery architecture.
-   Validate RTO and RPO.
-   Review automation, IaC, and CI/CD.
-   Assess configuration drift.
-   Review change and rollback processes.
-   Assess incident readiness.
-   Validate break-glass access.
-   Build ownership and escalation matrices.
-   Produce a readiness risk register.
-   Classify findings as PASS, PASS WITH RISK, FAIL, or NOT APPLICABLE.
-   Identify production blockers.
-   Document accepted risks.
-   Produce a complete Snowflake production health-check report.

**Chapter 85 --- Snowflake Production Health Check & Readiness Review:
Complete**
