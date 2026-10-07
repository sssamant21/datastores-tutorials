# Chapter 75 --- Snowflake Production Administration Runbook

## 75.1 Overview

Production Snowflake administration is not simply creating warehouses,
users, and databases.

A production administrator must continuously manage availability,
performance, security, access, cost, capacity, data protection,
operational changes, monitoring, incident response, and disaster
recovery readiness.

``` text
MONITOR
   |
   v
DETECT
   |
   v
ASSESS
   |
   v
ACT
   |
   v
VALIDATE
   |
   v
DOCUMENT
   |
   v
IMPROVE
```

This chapter provides a practical production administration runbook for
Snowflake SRE/DBRE teams.

## 75.2 Core Responsibilities

Production administration normally includes account administration,
warehouse administration, database/schema administration, RBAC,
authentication, security, performance, cost management, storage
management, data loading, monitoring, backup/recovery, replication/DR,
change management, and incident response.

## 75.3 Administrative Layers

``` text
Snowflake Account
      |
      +--> Security / Identity
      +--> Databases / Schemas
      +--> Warehouses
      +--> Data Pipelines
      +--> Monitoring
      +--> Cost Controls
      +--> Recovery / DR
```

## 75.4 First Rule

Before executing a production change, verify account, region, user,
role, warehouse, database, and schema.

## 75.5 Context Verification

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

## 75.6 Stop Condition

If the returned environment is not the expected environment: **STOP**.

## 75.7 Built-In Roles

Snowflake provides system-defined roles including ORGADMIN,
ACCOUNTADMIN, SECURITYADMIN, USERADMIN, SYSADMIN, and PUBLIC. Other
system roles can exist for specialized administrative capabilities.

## 75.8 ACCOUNTADMIN

`ACCOUNTADMIN` is highly privileged. Do not use it as the default
operational role.

## 75.9 Least Privilege

Routine administration should use purpose-specific roles such as
`SNOWFLAKE_DBA_ROLE`, `SNOWFLAKE_SECURITY_ROLE`,
`SNOWFLAKE_FINOPS_ROLE`, `SNOWFLAKE_MONITORING_ROLE`, and
`SNOWFLAKE_PIPELINE_ADMIN_ROLE`.

## 75.10 Separation of Duties

Separate security/identity, DBRE warehouse/performance operations,
FinOps governance, and data-engineering pipeline ownership where
appropriate.

## 75.11 Daily Production Checklist

Review service health, failed queries, long-running queries, query
queueing, warehouse utilization/failures, credit consumption,
resource-monitor alerts, data-load/Snowpipe/task failures,
authentication/access anomalies, replication status, and critical data
freshness.

## 75.12 External Service Health

When a broad issue is suspected, check official Snowflake service
status. Do not assume every application failure is a Snowflake platform
outage.

## 75.13 Internal Health

``` sql
SELECT CURRENT_TIMESTAMP();
```

Then validate required application context.

## 75.14 Query History

``` sql
SELECT
    QUERY_ID,
    USER_NAME,
    ROLE_NAME,
    WAREHOUSE_NAME,
    QUERY_TYPE,
    EXECUTION_STATUS,
    TOTAL_ELAPSED_TIME,
    START_TIME,
    END_TIME,
    ERROR_CODE,
    ERROR_MESSAGE
FROM SNOWFLAKE.ACCOUNT_USAGE.QUERY_HISTORY
WHERE START_TIME >= DATEADD('hour', -1, CURRENT_TIMESTAMP())
ORDER BY START_TIME DESC;
```

## 75.15 Failed Queries

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
WHERE START_TIME >= DATEADD('hour', -1, CURRENT_TIMESTAMP())
  AND EXECUTION_STATUS = 'FAIL'
ORDER BY START_TIME DESC;
```

Protect sensitive SQL text when sharing incident evidence.

## 75.16 Long-Running Queries

``` sql
SELECT
    QUERY_ID,
    USER_NAME,
    WAREHOUSE_NAME,
    QUERY_TYPE,
    TOTAL_ELAPSED_TIME,
    START_TIME
FROM SNOWFLAKE.ACCOUNT_USAGE.QUERY_HISTORY
WHERE START_TIME >= DATEADD('hour', -4, CURRENT_TIMESTAMP())
ORDER BY TOTAL_ELAPSED_TIME DESC
LIMIT 20;
```

## 75.17 Cancel Query

``` sql
SELECT SYSTEM$CANCEL_QUERY('<query_id>');
```

## 75.18 Do Not Cancel Blindly

Determine query owner, workload, business impact, transaction/pipeline
impact, and reason for high runtime before cancellation.

## 75.19 Warehouse Inventory

``` sql
SHOW WAREHOUSES;
```

Review size, state, auto-suspend/resume, cluster configuration, and
resource monitor.

## 75.20 Warehouse State

``` sql
ALTER WAREHOUSE APP_WH RESUME;
ALTER WAREHOUSE APP_WH SUSPEND;
```

Use manual intervention carefully.

## 75.21 Auto-Suspend

Production warehouses should normally have an appropriate auto-suspend
policy unless the workload explicitly requires otherwise.

## 75.22 Auto-Resume

Enable auto-resume where workloads require automatic availability.

## 75.23 Queueing Indicators

Investigate queued overload time, queued provisioning time, execution
time, warehouse utilization, and concurrency.

## 75.24 Queueing Does Not Automatically Mean Resize

Possible causes include burst concurrency, poor SQL, large scans, ETL
overlap, BI overlap, and insufficient capacity. Determine cause first.

## 75.25 Scale Up

Scale up when workloads benefit from more compute per query.

## 75.26 Scale Out

For concurrency-heavy workloads, multi-cluster warehouse configuration
may be appropriate where supported and justified.

## 75.27 Cost Review

Every scale operation should consider expected duration, credit impact,
auto-suspend, business priority, and rollback size.

## 75.28 Temporary Scale-Up Runbook

1.  Identify warehouse and workload.
2.  Capture current size and queueing.
3.  Confirm business impact.
4.  Obtain approval if required.
5.  Resize warehouse.
6.  Monitor workload and confirm improvement.
7.  Restore original size when no longer required.
8.  Validate queueing and record cost/change evidence.

## 75.29 Daily Cost Monitoring

Review credit consumption by warehouse, service, application,
environment, and team.

## 75.30 Warehouse Metering

Use appropriate Snowflake usage views to analyze warehouse credit
consumption.

## 75.31 Cost Spike Investigation

Check warehouse size/runtime, concurrency, retries, new workloads,
inefficient queries, auto-suspend changes, and multi-cluster expansion.

## 75.32 Resource Monitor Review

``` sql
SHOW RESOURCE MONITORS;
```

## 75.33 Resource Monitor Incident

Identify monitor → review credits → identify workload → obtain approval
→ adjust/restore service if appropriate → investigate root cause. Do not
simply increase the limit.

## 75.34 Storage Monitoring

Monitor active data, Time Travel data, Fail-safe data, stages, clones,
and temporary/transient objects.

## 75.35 Storage Growth

Unexpected growth can result from large ingestion, high churn, long
retention, clones, unused tables, staging files, and duplication.

## 75.36 Show Databases

``` sql
SHOW DATABASES;
```

## 75.37 Show Schemas

``` sql
SHOW SCHEMAS IN DATABASE PROD_DB;
```

## 75.38 Object Ownership

Production objects should have clearly understood ownership. Avoid
unmanaged objects owned by personal roles.

## 75.39 Role Inventory

``` sql
SHOW ROLES;
```

## 75.40 Grants

``` sql
SHOW GRANTS TO ROLE PATIENT360_APP_ROLE;
```

## 75.41 Role Review

Review unused/overprivileged roles, direct user grants, ownership,
service-account roles, and hierarchy.

## 75.42 User Inventory

``` sql
SHOW USERS;
```

## 75.43 Production User Review

Check disabled/inactive users, service users, authentication methods,
default roles/warehouses, and ownership.

## 75.44 Shared Accounts

Avoid shared human accounts. Human operators should have attributable
identities.

## 75.45 Service Identity Standard

Each service identity should have owner, application, environment,
purpose, role, authentication, rotation, and review/expiration
processes.

## 75.46 No Personal Ownership

Production applications should not depend on a personal engineer's
Snowflake account.

## 75.47 Login History

``` sql
SELECT
    EVENT_TIMESTAMP,
    USER_NAME,
    CLIENT_IP,
    REPORTED_CLIENT_TYPE,
    IS_SUCCESS,
    ERROR_CODE,
    ERROR_MESSAGE
FROM SNOWFLAKE.ACCOUNT_USAGE.LOGIN_HISTORY
WHERE EVENT_TIMESTAMP >= DATEADD('hour', -24, CURRENT_TIMESTAMP())
ORDER BY EVENT_TIMESTAMP DESC;
```

## 75.48 Failed Login Spike

Investigate expired credentials, rotated keys, OAuth issues, network
policy, service-account configuration, unauthorized attempts, and client
misconfiguration.

## 75.49 Network Controls

Understand network policies, private connectivity, firewall rules, DNS,
and proxy configuration.

## 75.50 Network Change

Treat network-policy changes as production changes because incorrect
changes can block applications.

## 75.51 Load Monitoring

Monitor COPY failures, rejected records, stage availability, file
formats, permissions, schema mismatches, and duplicate loading.

## 75.52 COPY History

Use Snowflake load-history capabilities appropriate to the ingestion
architecture.

## 75.53 Snowpipe Monitoring

Monitor pipe status, pending files, load errors, notification
integration, stage access, credits, and freshness.

## 75.54 Data Freshness

Infrastructure health does not guarantee data-pipeline health. Monitor
source → stage → Snowpipe → target table → application freshness.

## 75.55 Task Inventory

``` sql
SHOW TASKS;
```

## 75.56 Task Failure

Investigate task state, schedule, predecessor, warehouse, SQL errors,
privileges, timeout, and data dependencies.

## 75.57 Stream Monitoring

Streams used for CDC should be monitored for operational health and
consumption behavior.

## 75.58 Stale Stream Risk

Do not leave critical streams unconsumed indefinitely. Understand
retention/staleness behavior.

## 75.59 Dynamic Table Monitoring

Monitor refresh status/failures, target lag, warehouse, and data
freshness.

## 75.60 Infrastructure Healthy Does Not Mean Data Healthy

Monitor row counts, freshness, null rates, duplicates, business rules,
and pipeline completeness.

## 75.61 Recovery Readiness

Know Time Travel retention settings for critical data before an incident
occurs.

## 75.62 Accidental DELETE

Stop additional writes if necessary, record incident time, identify
table/query, assess Time Travel, create recovery clone/table, validate,
and restore safely.

## 75.63 Accidental DROP

Where retention permits:

``` sql
UNDROP TABLE <table_name>;
```

Validate the exact recovery path before production use.

## 75.64 Zero-Copy Clone

``` sql
CREATE TABLE PATIENT_BACKUP CLONE PATIENT;
```

Use lifecycle standards so temporary clones do not become permanent
unmanaged storage.

## 75.65 Fail-safe Is Not an Operational Backup

Use Time Travel, cloning, replication, and documented recovery
procedures appropriately.

## 75.66 Replication Monitoring

Monitor replication status, last successful refresh, lag, failures, and
target availability.

## 75.67 Failover Readiness

Verify primary/secondary, schedule, included objects, last refresh,
failover, and failback procedures.

## 75.68 DR Checklist

Confirm RPO/RTO, secondary availability, replication health,
role/integration behavior, secrets, network/routing readiness,
failover/failback testing, and current runbooks.

## 75.69 Production Change Principles

Every significant change should have purpose, owner, scope, risk,
precheck, implementation, validation, rollback, and monitoring.

## 75.70 Change Workflow

REQUEST → REVIEW → PRECHECK → CHANGE → VALIDATE → MONITOR or ROLLBACK.

## 75.71 Mandatory Precheck

Run the context query and capture relevant current configuration before
change.

## 75.72 Rollback Must Be Defined First

Do not begin a high-risk production change before defining rollback.

## 75.73 Rollback Examples

Restore warehouse size/parameter/grants, revert Terraform, UNDROP,
restore via Time Travel, switch logical routing, or fail back depending
on the change.

## 75.74 Terraform-Owned Resources

Prefer Terraform for changes to Terraform-managed objects.

## 75.75 Emergency Manual Change

Make the minimum manual change → stabilize → update Terraform →
reconcile drift.

## 75.76 Automation Requirements

Automation should include dedicated identity, least privilege,
environment validation, idempotency, retries, timeouts, logging,
monitoring, and rollback.

## 75.77 Monitoring Architecture

Monitor queries, warehouses, costs, pipelines, security, and DR through
central observability and actionable alerts.

## 75.78 Useful Alerts

Examples: query-failure spikes, latency, queueing, credit spikes,
resource-monitor thresholds, pipeline/task/Snowpipe failures,
authentication spikes, replication lag, and freshness breaches.

## 75.79 Avoid Alert Noise

Page only for actionable operational conditions according to service
objectives.

## 75.80 Incident Severity

Use organizational severity definitions; conceptually SEV1 critical
outage through lower-severity operational issues.

## 75.81 First Five Minutes

Confirm incident/impact/environment/start time/recent changes, service
health, query failures, warehouses, authentication, and freshness; open
communications and assign an incident owner.

## 75.82 Slowness Decision Tree

Determine whether slowness is in Snowflake or upstream. For Snowflake
queries, distinguish queueing/capacity from query execution problems
before remediation.

## 75.83 Query Slowness First Checks

Capture query ID, execution/compilation/queueing time, warehouse,
bytes/partitions scanned, spilling, query profile, and concurrency.

## 75.84 Warehouse Incident First Checks

Check warehouse state/size, queueing, concurrency, multi-cluster
behavior, resource monitors, recent resize, and workload spikes.

## 75.85 Data Loading Incident First Checks

Check stage, file, format, COPY history, pipe, permissions, schema,
rejected rows, and notifications.

## 75.86 Authentication Incident First Checks

Check user/service identity, role, authentication method, token/key,
login history, network policy, and privileges.

## 75.87 Capture Before Changing

Capture query IDs, metrics/screenshots, warehouse configuration, errors,
history, pipeline status, timestamps, and recent changes where
practical.

## 75.88 Why Capture Evidence?

Remediation can remove evidence needed for RCA.

## 75.89 Health Domains

Cover account, security, RBAC, warehouses, queries, pipelines, storage,
cost, recovery, replication, monitoring, and automation.

## 75.90 Weekly Checklist

Review performance/utilization/queueing/credit/storage trends, task/pipe
failures, authentication failures, role/user/service-account changes,
replication lag, incident actions, and operational risks.

## 75.91 Monthly Checklist

Review cost, warehouse sizing/unused warehouses, roles/users/service
identities, storage/retention, resource monitors, security policies, DR
readiness, runbooks, Terraform/provider changes, and capacity forecasts.

## 75.92 Quarterly Checklist

Perform access, DR, failover, capacity, FinOps, security, automation,
runbook, incident-trend, and recovery reviews/tests.

## 75.93 Capacity Is Workload-Specific

Review query volume, concurrency, warehouse runtime, queueing,
data/ingestion/user/application growth.

## 75.94 Do Not Size from CPU Thinking

Evaluate Snowflake workload behavior and query performance rather than
mapping directly to fixed-server CPU sizing.

## 75.95 Establish Baselines

Track P50/P95/P99 query latency, queueing, daily credits, warehouse
runtime, data freshness, and load duration.

## 75.96 Why Baselines Matter

Without a baseline, claims such as "Snowflake is slow" are difficult to
evaluate objectively.

## 75.97 Security Checklist

Review MFA/SSO standards, service authentication, least privilege,
shared accounts, network controls, sensitive data, logging, high-risk
roles, secret rotation, and access reviews.

## 75.98 FinOps Checklist

Review auto-suspend/resume, warehouse sizing, multi-cluster
justification, resource monitors, unused warehouses, credit spikes,
inefficient queries, tags, and ownership.

## 75.99 Every Production Resource Needs an Owner

Track warehouse/database/pipeline/service-account owners, cost center,
application, and environment.

## 75.100 Orphaned Resources

Investigate and assign, migrate, disable, or remove resources through
controlled change management.

## 75.101 Production Inventory

Maintain account, region, critical databases, warehouses, pipelines,
integrations, service identities, roles, replication, DR targets,
owners, and runbooks.

## 75.102 Planned Change Window

Ensure approval, stakeholder notification, dependency identification,
recovery verification, prechecks, rollback, monitoring, engineer
assignment, and validation.

## 75.103 Start-of-Shift Runbook

1.  Check outstanding incidents and service health.
2.  Review overnight alerts.
3.  Review failed/long-running queries and queueing.
4.  Review warehouses, credits, and resource-monitor events.
5.  Review pipelines, Snowpipe, tasks, authentication failures,
    freshness, and replication.
6.  Review scheduled changes and unresolved risks.

## 75.104 Production Change Runbook

1.  Confirm ticket, owner, window, and stakeholders.
2.  Confirm account, region, role, and warehouse.
3.  Capture configuration/metrics.
4.  Confirm recovery/rollback.
5.  Execute precheck and change.
6.  Capture output and validate.
7.  Monitor application/Snowflake against baseline.
8.  Roll back if validation fails.
9.  Confirm final configuration.
10. Update/communicate/monitor/close.

## 75.105 Emergency Production Change

Confirm severity/owner/minimum change/current
state/context/authorization → execute minimum change →
validate/monitor/record → stabilize → reconcile IaC → restore temporary
settings → RCA/prevention.

## 75.106 Production Access Runbook

Identify requester/business requirement/environment/objects/privileges →
prefer existing role → avoid direct grants → least privilege → approval
→ grant/validate/record → review or expiration where appropriate.

## 75.107 Warehouse Resize Runbook

Identify problem → baseline → queueing/profile/concurrency → determine
resize suitability → capture size/cost → approve → resize →
monitor/compare → restore if temporary → document.

## 75.108 Cost Spike Runbook

Determine spike window/service/warehouse/size/runtime → inspect
resize/multi-cluster/query volume/retries/long SQL/auto-suspend →
identify owner → stop unnecessary work if approved → remediate →
validate normalization → document/prevent.

## 75.109 Failed Query Runbook

Capture query ID/timestamp/user/role/warehouse/error/SQLSTATE/message →
inspect recent changes/object/grants/schema/types/warehouse → reproduce
safely → remediate → validate → document.

## 75.110 Authentication Failure Runbook

Identify identity/time → inspect login
history/authentication/credential/network policy/account/client/rotation
→ correct → validate → monitor → document.

## 75.111 Pipeline Failure Runbook

Identify pipeline/last success/freshness → inspect
stage/source/files/format/history/pipe/permissions/schema/duplicate risk
→ correct/resume safely → validate counts/freshness → document.

## 75.112 Recovery Runbook

Stop damaging workload → record time/query/object/operation → determine
Time Travel/transaction state → create recovery copy/clone → compare
data → restore affected data → validate counts/application →
resume/monitor → RCA.

## 75.113 DR Verification Runbook

Confirm critical databases, replication, secondary, last refresh/lag,
RPO/RTO, roles/access/network/secrets/routing, failover/failback
runbooks, last test, and readiness status.

## 75.114 Shift Handoff

Include incident status, customer impact, timeline, queries/warehouses,
changes, current metrics, risks, next actions, and owners.

## 75.115 Root Cause Analysis

Distinguish trigger, root cause, contributing factors, impact,
detection, mitigation, recovery, and prevention.

## 75.116 Evidence-Based RCA

Do not state that Snowflake caused an issue without evidence. Use query
history, warehouse metrics, application telemetry, logs, and timestamps
to establish causality.

## 75.117 Automation Candidates

Automate safe repetitive checks such as daily health, cost anomalies,
long/failed queries, warehouse validation, role/access review,
replication lag, freshness, and resource-monitor checks.

## 75.118 Do Not Automate Unsafe Remediation Blindly

Do not automatically cancel every long query, resize every queued
warehouse, increase every resource monitor, retry every failed DML, or
grant privileges without context and guardrails.

## 75.119 Recommended Dashboard

Include query latency/failures, queueing, warehouse utilization/runtime,
credits, storage, pipeline/freshness status, login failures, replication
lag, and open incidents.

## 75.120 New Workload Checklist

Verify owner, database/schema, RBAC/service identity/authentication,
warehouse/sizing/auto-suspend/cost controls, network, data
classification, pipeline, baseline, monitoring/alerts, recovery/DR,
runbook, and support ownership.

## 75.121 Resource Decommission Runbook

Identify resource/owner/usage/dependencies/retention → confirm no
dependency → approve → capture configuration → disable/observe → remove
access/resource → update Terraform/monitoring/inventory → document.

## 75.122 Common Production Mistakes

Avoid routine ACCOUNTADMIN, changes without context verification, direct
user grants, shared accounts, missing auto-suspend, uncontrolled
resizing, ignored queueing/task/freshness issues, blind
cancellation/retries, weak cost ownership, missing resource
monitors/baselines/recovery/DR tests/rollback, unmanaged IaC drift, poor
evidence/timelines/RCA, missing ownership, and uncontrolled
decommissioning.

## 75.123 Recommended Standards

Use least privilege, dedicated administrative/service roles, explicit
context verification, change management, prechecks/rollback,
query/warehouse/cost/pipeline/security/freshness/replication monitoring,
recovery/DR testing, baselines, ownership, IaC, evidence-based
incidents, current runbooks, and recurring access/FinOps/capacity
reviews.

## 75.124 SRE/DBRE Production Administration Checklist

-   [ ] Production context verified
-   [ ] Least privilege enforced
-   [ ] High-risk roles controlled
-   [ ] Service identities owned
-   [ ] Warehouses/queueing monitored
-   [ ] Auto-suspend reviewed
-   [ ] Query failures/latency monitored
-   [ ] Cost/resource monitors reviewed
-   [ ] Storage growth monitored
-   [ ] Pipelines/tasks/freshness monitored
-   [ ] Authentication/RBAC reviewed
-   [ ] Recovery tested
-   [ ] Replication/DR monitored and tested
-   [ ] Performance baseline maintained
-   [ ] Capacity reviewed
-   [ ] Terraform drift controlled
-   [ ] Changes/rollback documented
-   [ ] Incident runbooks/RCA evidence current
-   [ ] Ownership/decommissioning controlled

## 75.125 Incident Flow

``` text
ALERT
  |
  v
VERIFY IMPACT
  |
  v
VERIFY ENVIRONMENT
  |
  v
CAPTURE EVIDENCE
  |
  v
CLASSIFY
  |
  v
MITIGATE
  |
  v
VALIDATE
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

## 75.126 Daily

Service health, query failures/long queries, queueing, warehouses,
credits, pipelines, authentication, freshness, and replication.

## 75.127 Weekly

Performance trends, warehouse utilization, cost trends, storage growth,
task/pipe failures, access changes, and operational risks.

## 75.128 Monthly

FinOps, warehouse sizing, unused resources, inactive users, service
identities, retention, resource monitors, security, capacity, and
runbooks.

## 75.129 Quarterly

Access review, DR/recovery tests, capacity/security/FinOps reviews,
incident trends, and runbook reviews.

## 75.130 Production Administration Principles

1.  Verify environment before production administration.
2.  Do not use ACCOUNTADMIN for routine work.
3.  Apply least privilege and separation of duties.
4.  Monitor failures, latency, queueing, cost, pipelines, freshness,
    authentication, and replication.
5.  Establish performance baselines.
6.  Do not resize, cancel, retry, or raise limits blindly.
7.  Every production resource/service identity needs ownership.
8.  Capture evidence before remediation.
9.  Infrastructure health and data health are different.
10. Define rollback before high-risk changes.
11. Reconcile emergency manual changes with IaC.
12. Know Time Travel retention before incidents.
13. Fail-safe is not routine backup.
14. Monitor replication and test DR/recovery.
15. Automate safe repetitive checks with guardrails.
16. Validate and monitor production changes.
17. Maintain incident timelines and evidence-based RCA.
18. Review capacity, security, and FinOps regularly.
19. Keep operational runbooks current.

## 75.131 Chapter Completion Checklist

After completing this chapter, you should be able to operate a
production Snowflake account; verify context; apply administrative least
privilege; perform recurring operational reviews; investigate query,
warehouse, cost, authentication, loading, pipeline, and data-freshness
issues; administer RBAC/service identities; respond to accidental data
changes; use Time Travel/clones operationally; monitor replication/DR;
execute controlled changes and rollback; reconcile Terraform; design
monitoring/alerts; establish baselines; perform security/FinOps/capacity
reviews; execute production, emergency, access, resize, cost, query,
authentication, pipeline, recovery, DR, handoff, and decommission
runbooks; and produce evidence-based RCA.

**Chapter 75 --- Snowflake Production Administration Runbook: Complete**
