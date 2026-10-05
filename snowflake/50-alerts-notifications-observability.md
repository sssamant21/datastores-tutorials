# 50 — Alerts, Notifications & Observability

## Overview

A production Snowflake platform should not depend on engineers manually checking dashboards to discover problems.

Operational telemetry must be converted into:

```text
Metrics
   |
   v
Detection
   |
   v
Alert
   |
   v
Notification
   |
   v
Investigation
   |
   v
Remediation
```

The objective is not to generate as many alerts as possible.

The objective is:

> Detect meaningful Snowflake conditions early enough for the appropriate team to take action.

A mature observability system should help answer:

```text
Is Snowflake healthy?
Are queries becoming slower?
Are warehouses overloaded?
Are queries queueing?
Are pipelines failing?
Are tasks failing?
Is Snowpipe healthy?
Is storage growing unexpectedly?
Are credits increasing unexpectedly?
Are authentication failures increasing?
Are governance controls operating correctly?
Did something materially change?
Who needs to know?
What should they do next?
```

This chapter covers:

- Snowflake observability architecture
- metrics
- logs and history
- operational metadata
- ACCOUNT_USAGE
- INFORMATION_SCHEMA
- Query History
- warehouse monitoring
- task monitoring
- Snowpipe monitoring
- loading failures
- storage monitoring
- authentication monitoring
- cost monitoring
- Snowflake Alerts
- notification integrations
- email notifications
- webhook notifications
- cloud messaging integrations
- alert conditions
- alert schedules
- alert actions
- alert severity
- thresholds
- baselines
- anomaly detection
- deduplication
- alert fatigue
- dashboards
- SLI/SLO concepts
- incident evidence
- monitoring architecture
- production runbooks
- hands-on lab

---

# Part 1 — Observability vs Monitoring

## 1. Monitoring

Monitoring asks:

```text
Is a known condition occurring?
```

Examples:

```text
Warehouse queueing > threshold
Task failed
Pipe load failed
Storage growth > baseline
Credits > expected level
```

## 2. Observability

Observability asks a broader question:

```text
Can we understand what the system is doing
from the telemetry it exposes?
```

For Snowflake, this commonly involves combining:

```text
Query history
Warehouse telemetry
Task history
Load history
Storage history
Access history
Authentication history
Billing telemetry
Application context
```

---

# Part 2 — Production Observability Model

## 3. Core Model

```text
Snowflake
   |
   +---- Queries
   +---- Warehouses
   +---- Tasks
   +---- Pipes
   +---- Data Loads
   +---- Storage
   +---- Security
   +---- Governance
   +---- Credits
   |
   v
Snowflake Metadata / Telemetry
   |
   v
Collection
   |
   v
Metrics + Events
   |
   v
Dashboards
   |
   v
Alerts
   |
   v
Notifications
   |
   v
Incident Response
```

---

# Part 3 — The Three Operational Questions

## 4. Every Monitoring System Should Answer

### What happened?

Example:

```text
Queries started queueing at 14:05 UTC.
```

### Why did it happen?

Example:

```text
Warehouse concurrency exceeded the available execution capacity.
```

### What should we do?

Example:

```text
Investigate workload increase and warehouse concurrency before resizing.
```

An alert that only says:

```text
Snowflake is slow
```

is not operationally useful.

---

# Part 4 — Telemetry Sources

## 5. Common Sources

Production monitoring can use Snowflake interfaces such as:

```text
SNOWFLAKE.ACCOUNT_USAGE
INFORMATION_SCHEMA
Query History
Warehouse history
Task history
Pipe/load history
Storage history
Login/authentication history
Access history
Organization/account usage interfaces
```

Exact availability, retention, latency, privileges, and edition requirements vary.

Always validate the current Snowflake documentation before building production monitoring around a specific interface.

---

# Part 5 — ACCOUNT_USAGE

## 6. Historical Operational Telemetry

`SNOWFLAKE.ACCOUNT_USAGE` is one of the primary sources for historical Snowflake operational analysis.

Examples of relevant telemetry areas include:

```text
QUERY_HISTORY
WAREHOUSE_LOAD_HISTORY
WAREHOUSE_METERING_HISTORY
TASK_HISTORY
COPY_HISTORY
PIPE_USAGE_HISTORY
STORAGE_USAGE
DATABASE_STORAGE_USAGE_HISTORY
STAGE_STORAGE_USAGE_HISTORY
LOGIN_HISTORY
ACCESS_HISTORY
```

The exact set of available views can evolve.

---

# Part 6 — INFORMATION_SCHEMA

## 7. Operational Functions and Metadata

`INFORMATION_SCHEMA` can provide:

- object metadata
- table functions
- operational history
- database-scoped information

depending on the interface.

It can be useful when:

```text
Lower-latency operational data is required
Database-scoped metadata is sufficient
A supported table function exposes the required history
```

Do not assume it has the same retention or semantics as `ACCOUNT_USAGE`.

---

# Part 7 — Monitoring Latency

## 8. Critical Design Consideration

Telemetry may not appear immediately.

A monitoring system must understand:

```text
Event time
   |
   v
Snowflake telemetry availability
   |
   v
Collector execution
   |
   v
Alert evaluation
   |
   v
Notification
```

An alert cannot be more real-time than its underlying telemetry source.

---

# Part 8 — Detection Delay

## 9. Example

Suppose:

```text
Problem begins          10:00
Telemetry visible       10:05
Monitor runs            10:10
Notification delivered  10:11
```

Actual detection time:

```text
11 minutes
```

That may be unacceptable for a high-severity operational condition.

---

# Part 9 — Choose the Right Source

## 10. Source Selection

Use the telemetry source that matches the requirement.

Conceptually:

```text
Need historical analysis?
        |
        v
ACCOUNT_USAGE

Need supported near-current operational metadata?
        |
        v
Appropriate INFORMATION_SCHEMA function
or supported Snowflake telemetry

Need application-level behavior?
        |
        v
Application observability
```

Do not force every monitoring requirement through one source.

---

# Part 10 — Observability Dimensions

## 11. Monitor Multiple Layers

A production Snowflake environment should generally monitor:

```text
Availability
Performance
Concurrency
Pipelines
Data loading
Storage
Security
Governance
Cost
Automation
```

---

# Part 11 — Query Observability

## 12. Query Health

Track signals such as:

```text
Query count
Execution time
Queue time
Compilation time
Bytes scanned
Rows produced
Spill
Failures
Cancellations
Timeouts
Query tags
Warehouse
User
Role
```

Only use fields supported by the selected current Snowflake interface.

---

# Part 12 — Query Failure Rate

## 13. Metric

Conceptually:

```text
Query Failure Rate =
Failed Queries
--------------
Total Queries
```

Example:

```text
10,000 total queries
200 failed

Failure rate = 2%
```

A sudden increase may indicate:

- application deployment
- permission issue
- schema change
- malformed SQL
- missing objects
- resource issue

---

# Part 13 — Query Latency

## 14. Percentiles Matter

Do not monitor only average execution time.

Track:

```text
P50
P95
P99
```

when your monitoring system supports appropriate aggregation.

Example:

```text
P50 = 1.2 sec
P95 = 8 sec
P99 = 45 sec
```

Average latency can hide a severe long tail.

---

# Part 14 — Workload Segmentation

## 15. Do Not Mix Everything Together

Separate workloads by dimensions such as:

```text
Warehouse
Application
Query tag
User
Role
Environment
Workload type
```

Otherwise fast BI queries and slow ETL jobs can create misleading aggregate metrics.

---

# Part 15 — Query Tags

## 16. Operational Context

Query tags can make monitoring significantly more useful.

Example:

```sql
ALTER SESSION SET QUERY_TAG = 'app=orders;env=prod;job=daily_load';
```

Then telemetry can be attributed to application, environment, pipeline, and job.

Use a consistent organizational tagging convention.

---

# Part 16 — Warehouse Observability

## 17. Warehouse Signals

Monitor:

```text
Running queries
Queued queries
Queue time
Warehouse state
Warehouse size
Cluster count
Load
Credit consumption
Suspension/resumption behavior
```

Chapter 48 covers warehouse monitoring in depth.

---

# Part 17 — Queueing

## 18. Important Signal

Queueing may indicate concurrency pressure, provisioning delay, warehouse startup, repair/recovery conditions, or a workload burst.

Do not assume every queue means the warehouse is undersized.

---

# Part 18 — Queue Alert

## 19. Example Condition

Conceptually:

```text
Queue time > threshold
AND
query count > minimum sample size
```

This is usually more useful than alerting on one isolated queued query.

---

# Part 19 — Persistent Queueing

## 20. Better Signal

Instead of one query queued for five seconds, consider:

```text
P95 queue time > 30 seconds
for 10 minutes
```

if your telemetry and monitoring architecture support this calculation.

This reduces noise.

---

# Part 20 — Warehouse Credit Monitoring

## 21. Compute Consumption

Monitor:

```text
Credits/hour
Credits/day
Credits by warehouse
Credits by workload
Deviation from baseline
```

Detailed cost monitoring is covered in Chapters 51–55.

---

# Part 21 — Credit Anomaly

## 22. Example

Normal:

```text
Warehouse = ETL_PROD
Average = 40 credits/day
```

Observed:

```text
120 credits/day
```

Potential causes include new workload, warehouse resizing, ineffective auto-suspend, query regression, repeated retries, backfill, or concurrency increase.

---

# Part 22 — Task Monitoring

## 23. Scheduled Processing

Tasks should be monitored for:

```text
Success
Failure
Skipped execution
Runtime
Schedule delay
Dependency failure
Long-running execution
```

---

# Part 23 — Task Failure Alert

## 24. Basic Condition

Conceptually:

```text
Task state = FAILED
```

Production monitoring should include task name, database/schema, scheduled time, completed time, error, query ID, owner, and environment where available.

---

# Part 24 — Repeated Task Failures

## 25. Severity

One failure may be transient. Repeated failures may require escalation.

Example:

```text
1 failure       → warning
3 consecutive   → high
critical SLA job failure → critical
```

Severity should be based on business impact, not simply event count.

---

# Part 25 — Task Freshness

## 26. Missing Success Is Also a Failure Mode

A task can be problematic even without a visible failure event.

Example:

```text
Expected success every hour
Last successful execution = 4 hours ago
```

Monitor time since last successful execution.

---

# Part 26 — Snowpipe Monitoring

## 27. Ingestion Signals

Monitor:

```text
Files processed
Rows loaded
Load failures
Latency
Backlog
Pipe state
Credits/serverless usage where applicable
```

Exact telemetry depends on ingestion method.

---

# Part 27 — Snowpipe Failure

## 28. Operational Alert

An alert should include enough context to answer:

```text
Which pipe?
Which table?
Which files?
When did failure begin?
What error occurred?
Is ingestion still progressing?
```

---

# Part 28 — Ingestion Freshness

## 29. More Important Than Individual Events

For many pipelines the business requirement is:

```text
Data must be no more than 15 minutes old.
```

Monitor current time minus the latest successfully loaded source event/file where the architecture provides a reliable timestamp.

---

# Part 29 — COPY Monitoring

## 30. Batch Loads

Monitor:

```text
COPY executions
Files loaded
Rows loaded
Rejected rows
Errors
Duration
Bytes
```

A successful SQL statement does not necessarily mean the business dataset is complete.

---

# Part 30 — Data Quality Observability

## 31. Platform Health Is Not Data Health

Snowflake may be operating perfectly while the data is wrong.

Monitor separately:

```text
Row counts
Null rates
Duplicate rates
Freshness
Schema expectations
Business validation
```

---

# Part 31 — Storage Observability

## 32. Storage Signals

Monitor:

```text
Total storage
Daily growth
7-day growth
30-day growth
Database growth
Table growth
Historical storage
Stage storage
```

Chapter 49 covers storage monitoring in depth.

---

# Part 32 — Storage Alert

## 33. Example

Instead of:

```text
Storage > 100 TB
```

consider:

```text
Daily storage growth > 3× 30-day baseline
AND
absolute growth > 500 GB
```

This is more context-aware.

---

# Part 33 — Security Observability

## 34. Security Signals

Depending on supported telemetry, monitor:

```text
Failed logins
Unexpected authentication methods
Unusual source locations/networks
Disabled users attempting access
Privilege changes
Role grants
Policy changes
Network-policy changes
```

Security alerts should be coordinated with the organization's security team.

---

# Part 34 — Login Failure Monitoring

## 35. Example

A spike in failed authentication can indicate expired credentials, application misconfiguration, key rotation problems, SSO problems, user error, or potentially suspicious activity.

Context is required before assigning cause.

---

# Part 35 — Privilege Change Monitoring

## 36. Important Changes

High-value events may include:

```text
ACCOUNTADMIN grant
SECURITYADMIN grant
New privileged user
Privilege escalation
Network policy modification
Authentication policy modification
```

Exact auditability depends on current Snowflake telemetry.

---

# Part 36 — Governance Observability

## 37. Governance Signals

Monitor for drift such as:

```text
Sensitive columns without expected tags
Masking policy removed
Row access policy changed
Unapproved object ownership
Unexpected sharing
```

Not every governance control can or should be represented by a single Snowflake Alert.

---

# Part 37 — Access Observability

## 38. Questions

Where supported, access telemetry can help answer:

```text
Who accessed the object?
Which query accessed it?
Which objects were read?
Which objects were written?
What role was used?
```

Access History and related interfaces can be valuable for governance investigations.

---

# Part 38 — Cost Observability

## 39. Cost Signals

Monitor:

```text
Credits
Warehouse consumption
Serverless consumption
Storage
Replication
Cloud services
Budget variance
```

Cost is operational telemetry.

Do not wait for the monthly bill to discover an abnormal workload.

---

# Part 39 — Snowflake Alerts

## 40. Native Alerting Concept

Snowflake provides native alerting capabilities that can evaluate conditions and execute actions according to supported current Snowflake syntax and features.

Conceptually:

```text
Schedule
   |
   v
Condition
   |
 True?
 /   \
No    Yes
       |
       v
     Action
```

Always validate current `CREATE ALERT` syntax, privileges, scheduling behavior, and feature availability against current Snowflake documentation.

---

# Part 40 — Alert Components

## 41. Core Components

A native alert generally needs concepts equivalent to:

```text
Schedule
Condition
Action
```

Potential supporting components include warehouse or serverless compute, notification integration, stored procedure, and logging table depending on the design.

---

# Part 41 — Alert Condition

## 42. Condition Design

The condition should answer:

```text
Is there something actionable right now?
```

Avoid conditions that produce notifications without a clear operational response.

---

# Part 42 — Simple Condition

## 43. Conceptual Example

```sql
EXISTS (
    SELECT 1
    FROM monitoring.failed_jobs
    WHERE detected_at >= DATEADD(minute, -10, CURRENT_TIMESTAMP())
)
```

The exact syntax used inside a Snowflake Alert must follow the current supported alert syntax.

---

# Part 43 — Alert Action

## 44. Action

When a condition is true, an action might insert an event into a monitoring table, call an approved notification mechanism, or execute an approved stored procedure.

Keep alert actions small and predictable.

---

# Part 44 — Avoid Complex Remediation Inside Alerts

## 45. Safety

Avoid designing alerts that automatically perform destructive operations such as:

```text
DROP TABLE
DELETE production data
Revoke large sets of privileges
Resize every warehouse
Terminate workloads broadly
```

without appropriate safeguards.

Detection and destructive remediation should usually be separated.

---

# Part 45 — Alert Schedule

## 46. Frequency

Choose frequency based on business impact, telemetry latency, cost, and expected response time.

Do not evaluate a telemetry source every minute if that source itself updates much less frequently.

---

# Part 46 — Alert Frequency vs Data Freshness

## 47. Important

If telemetry updates every 15 minutes, running the alert every one minute does not create one-minute observability.

It may only create repeated queries against stale information.

---

# Part 47 — Notification Integrations

## 48. Notification Architecture

Depending on current Snowflake support and cloud platform, notifications may integrate with supported destinations such as email, webhook-based endpoints, cloud messaging services, and external incident/notification workflows.

The exact supported notification mechanisms and syntax must be validated against current Snowflake documentation.

---

# Part 48 — Email Notifications

## 49. Appropriate Use

Email may work well for:

```text
Low/medium urgency
Daily summaries
Governance reports
Capacity reports
Non-paging notifications
```

Email is often insufficient by itself for critical incidents.

---

# Part 49 — Webhook Notifications

## 50. Operational Integration

Where supported, webhook-style notification integrations can connect Snowflake alerts to approved external systems.

Use only approved endpoints and securely managed integration configuration.

---

# Part 50 — Cloud Messaging

## 51. Cloud-Native Patterns

Conceptually:

```text
Snowflake Alert
      |
      v
Notification Integration
      |
      v
Cloud Messaging
      |
      v
Incident / Chat / Automation System
```

---

# Part 51 — Separate Detection From Delivery

## 52. Recommended Design

```text
Detection
   |
   v
Standard Alert Event
   |
   v
Notification Layer
   |
   +---- Email
   +---- Chat
   +---- Pager
   +---- Ticket
```

This makes alert routing easier to maintain.

---

# Part 52 — Alert Event Schema

## 53. Standardize Events

Example:

```text
event_time
environment
account
category
severity
object_type
object_name
condition
observed_value
threshold
owner
runbook
correlation_id
```

---

# Part 53 — Severity Levels

## 54. Example Model

### SEV-1 / Critical

```text
Production unavailable
Critical data pipeline stopped
Major security event
```

### SEV-2 / High

```text
Significant degradation
Critical warehouse persistent queueing
Important ingestion SLA violation
```

### SEV-3 / Medium

```text
Non-critical task failure
Cost anomaly
Storage-growth anomaly
```

### SEV-4 / Informational

```text
Capacity trend
Governance review
Optimization opportunity
```

Align severity with the organization's incident-management model.

---

# Part 54 — Severity Is Based on Impact

## 55. Important

Do not define:

```text
Query > 30 seconds = SEV-1
```

without workload context.

A 30-second query may be normal ETL while a five-second query may violate an interactive application SLO.

---

# Part 55 — Static Thresholds

## 56. Example

```text
Queue time > 60 seconds
```

Advantages: simple, understandable, easy to implement.

Disadvantages: ignores workload differences, can create noise, and may miss gradual regressions.

---

# Part 56 — Baseline Thresholds

## 57. Example

```text
P95 runtime > 2× 30-day baseline
```

Advantages: workload-aware and adapts to normal behavior.

Disadvantages: requires history, unhealthy baselines are possible, and seasonality must be handled.

---

# Part 57 — Combined Thresholds

## 58. Recommended Pattern

```text
P95 runtime > 2× baseline
AND
P95 runtime > 10 seconds
AND
query_count > 100
```

This reduces false positives.

---

# Part 58 — Persistence

## 59. Avoid Single-Sample Alerts

Instead of one queue sample, consider requiring several consecutive unhealthy evaluation windows where business impact permits.

Do not delay alerts where one failure is already business-critical.

---

# Part 59 — Consecutive Failure Logic

## 60. Example

```text
Check 1 = unhealthy
Check 2 = unhealthy
Check 3 = unhealthy
      |
      v
Alert
```

---

# Part 60 — Recovery Detection

## 61. Alerts Need Closure

Monitoring should detect:

```text
Problem began
Problem ongoing
Problem recovered
```

A recovery notification can be as valuable as the initial alert.

---

# Part 61 — Alert State

## 62. Conceptual State Machine

```text
NORMAL
  |
  v
PENDING
  |
  v
FIRING
  |
  v
RECOVERED
```

Native Snowflake alert behavior and external monitoring systems may implement state differently.

---

# Part 62 — Deduplication

## 63. Prevent Repeated Pages

Bad:

```text
10:00 queue alert
10:01 queue alert
10:02 queue alert
10:03 queue alert
```

Better:

```text
One incident:
WAREHOUSE_X persistent queueing
Start: 10:00
Status: ongoing
```

---

# Part 63 — Correlation

## 64. Group Related Signals

Example:

```text
Warehouse queueing ↑
Query latency ↑
Credits ↑
Application latency ↑
```

These may represent one incident rather than four independent incidents.

---

# Part 64 — Alert Fatigue

## 65. Symptoms

```text
Alerts ignored
Channels muted
Pages acknowledged without investigation
Repeated false positives
```

At that point monitoring is failing operationally even if technically functional.

---

# Part 65 — Every Alert Needs an Owner

## 66. Required

An alert should identify:

```text
Owning team
Escalation path
Runbook
Severity
```

If nobody owns an alert, remove or redesign it.

---

# Part 66 — Every Alert Needs an Action

## 67. Test

Ask:

```text
What should the engineer do when this fires?
```

If the answer is nothing, it probably should not page anyone.

---

# Part 67 — Runbook Link

## 68. Alert Payload

A useful notification contains:

```text
Condition
Observed value
Threshold
Start time
Environment
Affected object
Owner
Dashboard
Runbook
```

---

# Part 68 — Monitoring Dashboards

## 69. Executive/Platform Overview

A top-level Snowflake dashboard might contain:

```text
Query health
Warehouse health
Pipeline health
Storage growth
Security events
Credit consumption
Active alerts
```

---

# Part 69 — Query Dashboard

## 70. Recommended

```text
Query volume
P50/P95/P99 runtime
Failure rate
Queue time
Bytes scanned
Spill
Top slow queries
Top workloads
```

---

# Part 70 — Warehouse Dashboard

## 71. Recommended

```text
Warehouse state
Running workload
Queueing
Load
Cluster activity
Credits
Suspend/resume activity
```

---

# Part 71 — Pipeline Dashboard

## 72. Recommended

```text
Task success
Task failures
Last successful run
Pipe health
Load failures
Data freshness
```

---

# Part 72 — Storage Dashboard

## 73. Recommended

```text
Total storage
Growth
Top-growing databases
Top-growing tables
Historical storage
Stage storage
```

---

# Part 73 — Security Dashboard

## 74. Recommended

Where supported:

```text
Failed logins
Privileged grants
Authentication changes
Network-policy changes
Sensitive-data access indicators
```

---

# Part 74 — Cost Dashboard

## 75. Recommended

```text
Credits/day
Credits by warehouse
Serverless consumption
Storage trend
Budget variance
Top cost contributors
```

---

# Part 75 — Golden Signals for Snowflake

## 76. Adapted Operational Model

A useful high-level model is:

```text
Latency
Traffic
Errors
Saturation
Cost
Freshness
```

For Snowflake:

- **Latency:** query runtime, queue time, pipeline delay
- **Traffic:** query volume, rows loaded, files processed
- **Errors:** query failures, task failures, load failures, authentication failures
- **Saturation:** warehouse queueing, concurrency pressure, spill
- **Cost:** credits, storage, serverless usage
- **Freshness:** last successful load, latest business data, task freshness

---

# Part 76 — SLI

## 77. Service-Level Indicator

An SLI is a measurable signal.

Examples:

```text
P95 query latency
Successful pipeline percentage
Data freshness
Task success rate
Queue time
```

---

# Part 77 — SLO

## 78. Service-Level Objective

Examples:

```text
99% of interactive queries complete within 3 seconds
```

or:

```text
99.9% of hourly ingestion runs complete within 15 minutes
```

The correct objective depends on the service.

---

# Part 78 — Error Budget

## 79. Concept

If an SLO allows a small amount of failure, that permitted amount forms an error budget.

For example, a 99.9% SLO permits approximately 0.1% failure within the defined measurement window and SLI semantics.

---

# Part 79 — Alert on User Impact

## 80. Better Principle

Prefer:

```text
Interactive workload SLO violation
```

over a generic infrastructure-like metric when possible.

Snowflake does not expose every traditional infrastructure metric, so user-impact signals are especially valuable.

---

# Part 80 — Application Observability

## 81. Snowflake Is Only One Layer

```text
User
 |
 v
Application
 |
 v
API
 |
 v
Snowflake
```

Application latency may include network, connection acquisition, authentication, application processing, query queueing, query execution, and result transfer.

Do not attribute the entire request duration to Snowflake without evidence.

---

# Part 81 — End-to-End Correlation

## 82. Recommended

Capture identifiers such as:

```text
Application request ID
Query ID
Query tag
Job ID
Pipeline run ID
Incident ID
```

This allows application requests to be correlated to Snowflake queries, warehouses, and Query Profile evidence.

---

# Part 82 — Query ID

## 83. Critical Evidence

When investigating Snowflake performance, capture the query ID whenever possible.

It enables deeper analysis of Query History, Query Profile, execution statistics, and errors.

---

# Part 83 — Incident Timeline

## 84. Standardize

Example:

```text
14:00 UTC — latency starts increasing
14:03 UTC — queueing begins
14:05 UTC — alert fires
14:08 UTC — engineer acknowledges
14:12 UTC — workload spike identified
14:18 UTC — mitigation applied
14:23 UTC — queue clears
14:30 UTC — service recovered
```

A timeline helps distinguish cause from coincidence.

---

# Part 84 — Monitoring Change Events

## 85. Correlate With Changes

Record operational changes such as warehouse resize, deployment, schema migration, task modification, role change, network-policy change, and pipeline release.

Then correlate changes with metric shifts.

---

# Part 85 — Alert Suppression

## 86. Maintenance Windows

During approved maintenance, tasks may be paused, warehouses intentionally stopped, or pipelines intentionally disabled.

Alerts may need controlled suppression.

Never disable monitoring globally simply because maintenance is occurring.

---

# Part 86 — Alert Routing

## 87. Route by Category

Example:

```text
Performance → DBRE/SRE
Pipeline → Data Engineering
Security → Security
Cost → FinOps/Platform
Governance → Data Governance
```

---

# Part 87 — Escalation

## 88. Example

```text
Warning
   |
   v
Owning team
   |
No response / impact increases
   |
   v
On-call
   |
   v
Incident Management
```

---

# Part 88 — Notification Content

## 89. Good Alert

```text
Severity: High
Environment: Production
Category: Warehouse Concurrency
Warehouse: APP_PROD_WH
Started: 14:05 UTC

Condition:
P95 queue time > 30 sec for 10 minutes

Observed:
P95 queue = 78 sec
Query count = 4,200

Impact:
Interactive application queries delayed

Next:
Review workload concurrency and warehouse load.

Runbook:
<approved internal runbook>
```

---

# Part 89 — Bad Alert

## 90. Example

```text
SNOWFLAKE ALERT!!!

Warehouse slow.
Please check.
```

This forces the responder to rediscover basic context.

---

# Part 90 — Alert Naming

## 91. Use Predictable Names

```text
SNOWFLAKE_PROD_QUERY_FAILURE_RATE_HIGH
SNOWFLAKE_PROD_WAREHOUSE_QUEUE_HIGH
SNOWFLAKE_PROD_TASK_FAILED
SNOWFLAKE_PROD_INGESTION_FRESHNESS
SNOWFLAKE_PROD_STORAGE_GROWTH
SNOWFLAKE_PROD_CREDIT_ANOMALY
```

---

# Part 91 — Alert Metadata

## 92. Tag Alerts

Recommended dimensions:

```text
platform=snowflake
environment=prod
category=performance
severity=high
owner=data-platform
```

---

# Part 92 — Alert Inventory

## 93. Maintain a Catalog

| Alert | Severity | Owner | Runbook | Destination | Status |
|---|---|---|---|---|---|
| Query failures | High | Platform | Defined | On-call | Enabled |
| Task failure | High | Data Eng | Defined | On-call | Enabled |
| Storage growth | Medium | Platform | Defined | Chat | Enabled |
| Cost anomaly | Medium | FinOps | Defined | Chat | Enabled |

Review the catalog periodically.

---

# Part 93 — Alert Review

## 94. Measure Alert Quality

Track:

```text
Alerts fired
Actionable alerts
False positives
Duplicate alerts
Ignored alerts
Time to acknowledge
Time to resolve
```

---

# Part 94 — Alert Precision

## 95. Concept

```text
Alert Precision =
Actionable Alerts
-----------------
Total Alerts
```

Low precision means responders receive too much noise.

---

# Part 95 — Alert Coverage

## 96. Another Question

Ask:

```text
Did incidents occur without an alert?
```

If yes, monitoring coverage has gaps.

---

# Part 96 — Post-Incident Monitoring Review

## 97. After Every Significant Incident

Ask:

```text
Did we detect it?
Did we detect it early enough?
Did the alert identify impact?
Was routing correct?
Was the runbook useful?
Did we receive duplicate alerts?
What telemetry was missing?
```

Monitoring should improve after incidents.

---

# Part 97 — Observability Data Retention

## 98. Keep Enough History

Operational analysis may require 7 days, 30 days, 90 days, or one year depending on incident review, capacity planning, seasonality, compliance, and cost analysis.

If native telemetry retention does not satisfy organizational requirements, approved metadata may need to be persisted separately.

---

# Part 98 — Monitoring Schema

## 99. Optional Pattern

```text
OBSERVABILITY
 |
 +---- METRICS
 +---- ALERTS
 +---- EVENTS
 +---- BASELINES
 +---- SNAPSHOTS
```

Apply least privilege and retention policies.

---

# Part 99 — Alert Event Table

## 100. Example

```sql
CREATE TABLE observability.alerts.alert_events (
    event_time TIMESTAMP_LTZ,
    alert_name STRING,
    severity STRING,
    environment STRING,
    object_name STRING,
    condition STRING,
    observed_value STRING,
    status STRING,
    correlation_id STRING
);
```

This is an organizational monitoring design, not a Snowflake-required schema.

---

# Part 100 — Monitoring Query Cost

## 101. Monitoring Is Also a Workload

Poorly designed observability queries can consume unnecessary compute.

Avoid unbounded history scans, `SELECT *`, very frequent polling, and repeated expensive aggregation.

---

# Part 101 — Efficient Monitoring Queries

## 102. Prefer

```text
Bounded time ranges
Required columns only
Incremental collection
Pre-aggregation
Appropriate schedule
```

---

# Part 102 — Monitoring Warehouse

## 103. Isolation

Where appropriate, organizations may use a dedicated warehouse for monitoring queries.

Benefits include workload isolation, predictable cost, independent suspend policy, and reduced interference.

Sizing depends on monitoring workload.

---

# Part 103 — Monitoring Failure

## 104. Monitor the Monitor

Watch for:

```text
Collector stopped
Alert evaluation stopped
Notification failed
Credentials expired
Telemetry stale
Dashboard stale
```

---

# Part 104 — Heartbeat

## 105. Pattern

```text
Monitoring system expected heartbeat
          |
          v
Heartbeat missing?
          |
         Yes
          |
          v
Monitoring-system alert
```

---

# Part 105 — Data Freshness of Monitoring

## 106. Dashboard Timestamp

Every dashboard should make it easy to answer:

```text
When was this data last updated?
```

Without freshness information, stale telemetry can look healthy.

---

# Part 106 — Security of Monitoring Data

## 107. Important

Telemetry may contain query text, object names, user names, roles, error messages, and potential business identifiers.

Protect observability data appropriately.

---

# Part 107 — Query Text

## 108. Sensitive Context

Query text can potentially contain sensitive literals or operational details.

Avoid broadly exposing raw query text in dashboards or notifications.

Use least privilege and sanitization where appropriate.

---

# Part 108 — Notification Security

## 109. Do Not Leak Sensitive Data

Avoid putting credentials, tokens, sensitive row values, full sensitive query text, or private keys into notifications.

Notifications often leave the primary Snowflake security boundary.

---

# Part 109 — Production Alert Matrix

## 110. Suggested Starting Point

| Area | Signal | Example Severity |
|---|---|---|
| Query | Failure-rate spike | High |
| Query | P95/P99 latency regression | High |
| Warehouse | Persistent queueing | High |
| Warehouse | Credit anomaly | Medium |
| Task | Critical task failure | High |
| Task | Freshness violation | High |
| Ingestion | Load failure | High |
| Ingestion | Data freshness violation | High |
| Storage | Unexpected growth | Medium |
| Security | Authentication anomaly | High |
| Security | Privileged-role change | High |
| Cost | Spend anomaly | Medium |
| Monitoring | Telemetry heartbeat missing | High |

Severity must be adjusted for actual business impact.

---

# Part 110 — Production Observability Architecture

## 111. Reference Model

```text
                  Snowflake
                     |
     +---------------+---------------+
     |               |               |
Query History   Warehouse Data   Pipeline Data
     |               |               |
     +---------------+---------------+
                     |
                     v
             Telemetry Collection
                     |
          +----------+----------+
          |                     |
          v                     v
      Dashboards             Detection
                                |
                                v
                             Alerts
                                |
                                v
                      Notification Layer
                                |
             +------------------+------------------+
             |                  |                  |
             v                  v                  v
            Chat              Pager              Ticket
                                |
                                v
                           Responder
                                |
                                v
                             Runbook
```

---

# Part 111 — Layered Monitoring

## 112. Layer 1 — Platform

```text
Warehouse
Query
Storage
Credits
Authentication
```

## 113. Layer 2 — Data Pipeline

```text
Tasks
Snowpipe
COPY
Freshness
Failures
```

## 114. Layer 3 — Application

```text
User latency
Request failures
Connection errors
Query correlation
```

## 115. Layer 4 — Business

```text
Data completeness
Business freshness
Critical report readiness
```

All four layers matter.

---

# Part 112 — Troubleshooting an Alert

## 116. Step 1 — Validate

Ask:

```text
Is the alert real?
Is telemetry fresh?
Is the condition still occurring?
```

## 117. Step 2 — Determine Impact

Identify users, applications, pipelines, warehouses, and data products affected.

## 118. Step 3 — Establish Timeline

Capture start, first alert, first user impact, recent change, and current status.

## 119. Step 4 — Identify Scope

Determine whether the problem affects one query, one workload, one warehouse, one pipeline, one database, or the whole account.

## 120. Step 5 — Correlate Signals

Example:

```text
Latency ↑
Queue ↑
Concurrency ↑
Credits ↑
```

This suggests a workload/capacity path.

Another example:

```text
Application errors ↑
Snowflake query latency normal
```

Investigate outside Snowflake before blaming the warehouse.

## 121. Step 6 — Identify Recent Changes

Check deployment, warehouse configuration, role/privilege, schema, task, pipeline, network, and authentication changes.

## 122. Step 7 — Mitigate

Apply the smallest safe mitigation appropriate to the verified root cause.

## 123. Step 8 — Verify Recovery

Confirm metric recovery, user impact recovery, pipeline catch-up, and alert clearance.

## 124. Step 9 — Document

Capture root cause, impact, timeline, mitigation, permanent action, and monitoring improvement.

---

# Part 113 — Alert Troubleshooting Decision Tree

## 125. Decision

```text
Alert fires
   |
   v
Telemetry fresh?
 /        \
No         Yes
|           |
v           v
Fix       Condition
monitor   still active?
          /       \
        No         Yes
        |           |
        v           v
      Close       Impact?
                  /    \
                Low    High
                 |       |
                 v       v
              Review   Incident
```

---

# Part 114 — Query Alert Decision Tree

## 126. Decision

```text
Query latency ↑
      |
      v
Queue time ↑?
 /          \
Yes          No
 |            |
 v            v
Concurrency  Execution slow?
             /          \
           Yes           No
            |             |
            v             v
       Query/Profile   App/network/
       investigation  result transfer
```

---

# Part 115 — Pipeline Alert Decision Tree

## 127. Decision

```text
Data stale
   |
   v
Task running?
 /       \
No        Yes
|          |
v          v
Task      Load progressing?
issue      /        \
         No          Yes
         |            |
         v            v
       Pipe/COPY    Downstream
       issue        processing
```

---

# Part 116 — Cost Alert Decision Tree

## 128. Decision

```text
Credits ↑
   |
   v
Which service/workload?
   |
   +---- Warehouse
   +---- Serverless
   +---- Other supported category
   |
   v
Expected activity?
 /        \
Yes        No
 |          |
 v          v
Track     Investigate
budget    configuration/workload
```

---

# Part 117 — Hands-On Lab

## 129. Objective

Build a small observability environment that demonstrates telemetry, alert condition, alert event, notification design, and recovery.

Use a non-production Snowflake environment.

---

# Part 118 — Create Lab Database

## 130. Database

```sql
CREATE OR REPLACE DATABASE observability_lab;
```

---

# Part 119 — Create Schemas

## 131. Schemas

```sql
CREATE OR REPLACE SCHEMA observability_lab.app;
CREATE OR REPLACE SCHEMA observability_lab.monitoring;
```

---

# Part 120 — Create Application Table

## 132. Table

```sql
CREATE OR REPLACE TABLE observability_lab.app.pipeline_status (
    pipeline_name STRING,
    environment STRING,
    last_success_time TIMESTAMP_LTZ,
    status STRING
);
```

---

# Part 121 — Insert Synthetic Status

## 133. Healthy Pipeline

```sql
INSERT INTO observability_lab.app.pipeline_status
VALUES (
    'synthetic_orders_pipeline',
    'LAB',
    CURRENT_TIMESTAMP(),
    'SUCCESS'
);
```

This is synthetic lab data.

---

# Part 122 — Create Alert Event Table

## 134. Event Table

```sql
CREATE OR REPLACE TABLE observability_lab.monitoring.alert_events (
    event_time TIMESTAMP_LTZ,
    alert_name STRING,
    severity STRING,
    object_name STRING,
    observed_status STRING,
    message STRING
);
```

---

# Part 123 — Build Detection Query

## 135. Failure Detection

```sql
SELECT *
FROM observability_lab.app.pipeline_status
WHERE status <> 'SUCCESS';
```

Expected result: zero rows.

---

# Part 124 — Build Freshness Detection

## 136. Query

```sql
SELECT *
FROM observability_lab.app.pipeline_status
WHERE last_success_time < DATEADD(minute, -30, CURRENT_TIMESTAMP());
```

Initially this should return no row if the lab was just created.

---

# Part 125 — Simulate Failure

## 137. Controlled Failure

```sql
UPDATE observability_lab.app.pipeline_status
SET
    status = 'FAILED',
    last_success_time = DATEADD(hour, -2, CURRENT_TIMESTAMP())
WHERE pipeline_name = 'synthetic_orders_pipeline';
```

---

# Part 126 — Verify Detection

## 138. Failure Query

```sql
SELECT *
FROM observability_lab.app.pipeline_status
WHERE status <> 'SUCCESS';
```

The synthetic pipeline should now appear.

---

# Part 127 — Verify Freshness Violation

## 139. Query

```sql
SELECT *
FROM observability_lab.app.pipeline_status
WHERE last_success_time < DATEADD(minute, -30, CURRENT_TIMESTAMP());
```

The row should now appear.

---

# Part 128 — Record an Alert Event

## 140. Event

```sql
INSERT INTO observability_lab.monitoring.alert_events
SELECT
    CURRENT_TIMESTAMP(),
    'LAB_PIPELINE_FAILURE',
    'HIGH',
    pipeline_name,
    status,
    'Synthetic pipeline is failed or stale'
FROM observability_lab.app.pipeline_status
WHERE status <> 'SUCCESS'
   OR last_success_time < DATEADD(minute, -30, CURRENT_TIMESTAMP());
```

---

# Part 129 — Inspect Alert Event

## 141. Query

```sql
SELECT *
FROM observability_lab.monitoring.alert_events
ORDER BY event_time DESC;
```

Verify alert name, severity, object, status, message, and timestamp.

---

# Part 130 — Native Alert Exercise

## 142. Validate Current Syntax First

Before creating a native Snowflake Alert, verify current Snowflake documentation for:

```text
CREATE ALERT syntax
Compute model
Schedule syntax
Condition syntax
Action syntax
Privileges
Resume/suspend behavior
Notification support
```

Do not copy historical syntax blindly into production.

---

# Part 131 — Native Alert Design

## 143. Conceptual Definition

Design an alert equivalent to:

```text
Every N minutes:
    Check pipeline_status

If:
    status != SUCCESS
    OR
    last_success_time exceeds freshness threshold

Then:
    Write alert event
    and/or
    invoke approved notification mechanism
```

---

# Part 132 — Notification Integration Exercise

## 144. Optional

If your non-production environment permits notification integrations:

1. Create or use an approved notification integration.
2. Route only synthetic lab alerts.
3. Do not include credentials or sensitive data.
4. Trigger the synthetic failure.
5. Verify delivery.
6. Restore the healthy state.
7. Remove the test integration if it was created only for the lab.

Use the exact current Snowflake syntax for your cloud and notification type.

---

# Part 133 — Recovery

## 145. Restore Pipeline

```sql
UPDATE observability_lab.app.pipeline_status
SET
    status = 'SUCCESS',
    last_success_time = CURRENT_TIMESTAMP()
WHERE pipeline_name = 'synthetic_orders_pipeline';
```

---

# Part 134 — Verify Recovery

## 146. Failure Condition

```sql
SELECT *
FROM observability_lab.app.pipeline_status
WHERE status <> 'SUCCESS'
   OR last_success_time < DATEADD(minute, -30, CURRENT_TIMESTAMP());
```

Expected: zero rows.

---

# Part 135 — Record Recovery

## 147. Event

```sql
INSERT INTO observability_lab.monitoring.alert_events
VALUES (
    CURRENT_TIMESTAMP(),
    'LAB_PIPELINE_FAILURE',
    'INFO',
    'synthetic_orders_pipeline',
    'SUCCESS',
    'Synthetic pipeline recovered'
);
```

---

# Part 136 — Review Timeline

## 148. Query

```sql
SELECT *
FROM observability_lab.monitoring.alert_events
ORDER BY event_time;
```

You should see the failure event and recovery event.

---

# Part 137 — Query Tag Exercise

## 149. Set Query Tag

```sql
ALTER SESSION SET QUERY_TAG =
    'app=observability_lab;env=lab;component=monitoring';
```

Run several lab queries.

Then use an appropriate current Query History interface to locate those tagged queries.

---

# Part 138 — Query History Exercise

## 150. Investigate

Capture for the lab queries where supported:

```text
Query ID
Start time
End time
Execution time
Warehouse
User
Role
Query tag
Status
```

---

# Part 139 — Monitoring Freshness Exercise

## 151. Record Collection Time

```sql
CREATE OR REPLACE TABLE observability_lab.monitoring.heartbeat (
    observed_at TIMESTAMP_LTZ,
    source_name STRING,
    status STRING
);
```

Insert:

```sql
INSERT INTO observability_lab.monitoring.heartbeat
VALUES (
    CURRENT_TIMESTAMP(),
    'snowflake_monitor',
    'HEALTHY'
);
```

---

# Part 140 — Missing Heartbeat Detection

## 152. Concept

```sql
SELECT
    MAX(observed_at) AS last_heartbeat
FROM observability_lab.monitoring.heartbeat;
```

Compare the result with the expected heartbeat interval.

The monitoring system itself must be monitored.

---

# Part 141 — Alert Payload Exercise

## 153. Create a Useful Message

For the synthetic pipeline, build an alert containing:

```text
Severity
Environment
Pipeline
Condition
Observed status
Last success
Current time
Owner
Runbook
```

Compare it with a message that only says `Pipeline failed.`

---

# Part 142 — Severity Exercise

## 154. Classify

Classify these examples:

```text
A. Development task failed once.
B. Production hourly pipeline has been stale for 3 hours.
C. Production interactive query P99 increased 10%.
D. Privileged administrative role unexpectedly granted.
E. Storage growth is 20% above monthly forecast.
```

Severity should reflect business and security impact.

---

# Part 143 — Deduplication Exercise

## 155. Scenario

Suppose the pipeline remains failed for one hour and the detector runs every five minutes.

Without deduplication: 12 notifications.

Design a state model that instead produces one firing event and one recovery event, with ongoing status updates handled appropriately.

---

# Part 144 — Cleanup

## 156. Remove Lab

```sql
DROP DATABASE IF EXISTS observability_lab;
```

If you created notification integrations or other account-level objects specifically for the lab, remove them separately after confirming they are not shared.

---

# Part 145 — Production Alert Checklist

## 157. Detection

```text
□ Condition is meaningful
□ Telemetry source is documented
□ Telemetry latency is understood
□ Threshold is justified
□ Evaluation frequency is appropriate
□ Persistence is considered
```

## 158. Context

```text
□ Environment included
□ Object included
□ Observed value included
□ Threshold included
□ Start time included
□ Severity included
```

## 159. Ownership

```text
□ Owner assigned
□ Escalation defined
□ Runbook linked
□ Destination defined
```

## 160. Noise Control

```text
□ Deduplication exists
□ Recovery is detected
□ Maintenance suppression exists
□ False-positive rate reviewed
```

## 161. Security

```text
□ No credentials exposed
□ No tokens exposed
□ Sensitive query text controlled
□ Notification destination approved
```

## 162. Operations

```text
□ Alert tested
□ Failure tested
□ Recovery tested
□ Notification tested
□ Monitoring heartbeat tested
```

---

# Part 146 — Daily Observability Review

## 163. Review

```text
□ Critical alerts
□ Query failures
□ Query latency
□ Warehouse queueing
□ Critical task failures
□ Ingestion freshness
□ Security events
□ Credit anomalies
```

---

# Part 147 — Weekly Observability Review

## 164. Review

```text
□ Alert volume
□ False positives
□ Duplicate alerts
□ Missed incidents
□ Slow-query trends
□ Warehouse trends
□ Pipeline trends
□ Storage growth
□ Cost trend
```

---

# Part 148 — Monthly Observability Review

## 165. Review

```text
□ Alert catalog
□ Owners
□ Runbooks
□ Thresholds
□ Baselines
□ SLOs
□ Notification routes
□ Telemetry retention
□ Monitoring cost
□ Monitoring gaps
```

---

# Part 149 — Incident Evidence Template

## 166. Capture

```text
Incident:
Severity:
Environment:
Account:
Region:

Detected:
User impact began:
Recovered:
Timezone:

Alert:
Condition:
Observed value:
Threshold:

Affected warehouse:
Affected application:
Affected pipeline:
Affected database:

Query IDs:
Query tags:

Queue metrics:
Execution metrics:
Failure metrics:

Task status:
Pipe/load status:
Data freshness:

Storage signal:
Credit signal:
Security signal:

Recent changes:

Root cause:
Mitigation:
Recovery validation:

Alert quality:
Was detection early enough?
Was routing correct?
Was runbook useful?
Was anything missing?

Permanent actions:
Owner:
```

---

# Part 150 — Observability Runbook

## 167. Trigger

An operational alert fires.

## 168. Validate

```text
Confirm telemetry freshness
Confirm condition
Confirm current state
```

## 169. Scope

```text
Query?
Warehouse?
Pipeline?
Storage?
Security?
Cost?
Account-wide?
```

## 170. Impact

Determine users, applications, data products, and SLA/SLO impact.

## 171. Timeline

Record start, alert, recent change, mitigation, and recovery.

## 172. Correlate

Combine relevant telemetry.

## 173. Mitigate

Use the smallest safe mitigation.

## 174. Verify

Confirm user and system recovery.

## 175. Close

Record the recovery event.

## 176. Improve

Update alert, dashboard, runbook, baseline, or SLO where necessary.

---

# Part 151 — Common Mistakes

## 177. Alerting on Everything

More alerts do not mean better monitoring.

## 178. Alerting Without Context

Responders need enough information to start investigation.

## 179. Ignoring Telemetry Latency

A five-minute alert schedule cannot overcome a slower telemetry source.

## 180. Using Only Static Thresholds

Static thresholds often create noise across different workloads.

## 181. Alerting on One Sample

Transient conditions can generate unnecessary incidents.

## 182. No Recovery Signal

Responders should know when the condition has cleared.

## 183. No Deduplication

Repeated notifications create alert fatigue.

## 184. No Owner

Every actionable alert needs ownership.

## 185. No Runbook

The alert should tell responders where to start.

## 186. Treating Severity as Metric Magnitude

Severity should reflect impact.

## 187. Ignoring Application Telemetry

Not all user latency is caused by Snowflake.

## 188. Ignoring Data Freshness

Infrastructure can be healthy while business data is stale.

## 189. Ignoring Monitoring Cost

Monitoring queries consume resources too.

## 190. Not Monitoring the Monitor

A broken monitoring pipeline can create a false sense of health.

## 191. Exposing Sensitive Query Text

Observability systems must follow security controls.

## 192. Automatically Remediating Destructively

Detection should not casually trigger destructive production changes.

---

# Part 152 — Production Principles

## 193. Principle 1

Alert on actionable conditions.

## 194. Principle 2

Prefer user/business impact signals.

## 195. Principle 3

Understand telemetry latency.

## 196. Principle 4

Choose the correct telemetry source.

## 197. Principle 5

Segment workloads.

## 198. Principle 6

Use query tags consistently.

## 199. Principle 7

Monitor query failures.

## 200. Principle 8

Monitor latency percentiles.

## 201. Principle 9

Monitor persistent queueing.

## 202. Principle 10

Monitor critical task failures.

## 203. Principle 11

Monitor pipeline freshness.

## 204. Principle 12

Monitor storage growth.

## 205. Principle 13

Monitor security events.

## 206. Principle 14

Monitor cost anomalies.

## 207. Principle 15

Use contextual thresholds.

## 208. Principle 16

Require persistence where appropriate.

## 209. Principle 17

Deduplicate alerts.

## 210. Principle 18

Detect recovery.

## 211. Principle 19

Assign ownership.

## 212. Principle 20

Link runbooks.

## 213. Principle 21

Protect monitoring data.

## 214. Principle 22

Monitor monitoring freshness.

## 215. Principle 23

Review alert quality.

## 216. Principle 24

Improve monitoring after incidents.

---

# Part 153 — DBRE/SRE Observability Flow

## 217. Production Flow

```text
Snowflake telemetry
       |
       v
Collect
       |
       v
Normalize
       |
       v
Baseline
       |
       v
Evaluate
       |
       v
Actionable condition?
    /           \
   No            Yes
   |              |
   v              v
Continue       Alert
monitoring        |
                  v
              Notify
                  |
                  v
              Validate
                  |
                  v
               Scope
                  |
                  v
               Impact
                  |
                  v
             Correlate
                  |
                  v
              Mitigate
                  |
                  v
               Verify
                  |
                  v
              Recover
                  |
                  v
               Review
```

---

# Acceptance Criteria

The chapter is complete when you can:

- explain monitoring versus observability
- design a production Snowflake observability model
- identify the three operational questions monitoring must answer
- identify major Snowflake telemetry sources
- use ACCOUNT_USAGE conceptually for historical monitoring
- use INFORMATION_SCHEMA appropriately
- explain telemetry latency
- calculate detection delay
- choose telemetry sources based on operational requirements
- identify major observability dimensions
- monitor query health
- calculate query failure rate
- explain why latency percentiles matter
- segment workloads
- use query tags for attribution
- monitor warehouse health
- interpret queueing
- design queue alerts
- detect persistent queueing
- monitor warehouse credits
- detect credit anomalies
- monitor tasks
- design task-failure alerts
- classify repeated task failures
- monitor task freshness
- monitor Snowpipe
- investigate ingestion failures
- monitor data freshness
- monitor COPY operations
- distinguish platform health from data quality
- monitor storage
- create storage-growth alerts
- monitor security signals
- investigate login failures
- monitor privilege changes
- monitor governance drift
- understand access observability
- monitor cost
- explain Snowflake native alerting conceptually
- identify alert components
- design alert conditions
- design alert actions
- avoid destructive automatic remediation
- choose alert schedules
- align alert frequency with telemetry freshness
- understand notification integrations
- understand email notification use cases
- understand webhook notification patterns
- understand cloud messaging patterns
- separate detection from delivery
- define a standard alert-event schema
- define severity levels
- classify severity by impact
- use static thresholds appropriately
- use baseline thresholds
- design combined thresholds
- require persistence where appropriate
- implement consecutive-failure logic
- detect recovery
- understand alert state
- deduplicate notifications
- correlate related signals
- identify alert fatigue
- assign alert ownership
- define alert actions
- include runbooks
- design Snowflake dashboards
- design query dashboards
- design warehouse dashboards
- design pipeline dashboards
- design storage dashboards
- design security dashboards
- design cost dashboards
- apply Snowflake golden signals
- define SLIs
- define SLOs
- understand error budgets
- alert on user impact
- correlate application and Snowflake telemetry
- implement end-to-end correlation
- capture query IDs
- build incident timelines
- correlate changes with telemetry
- suppress alerts safely during maintenance
- route alerts by ownership
- define escalation
- create useful notification payloads
- identify bad alert payloads
- standardize alert names
- tag alert metadata
- maintain an alert inventory
- measure alert quality
- calculate alert precision
- identify monitoring coverage gaps
- perform post-incident monitoring reviews
- plan observability-data retention
- design an observability schema
- create an alert-event table
- control monitoring-query cost
- optimize monitoring queries
- isolate monitoring workloads where appropriate
- monitor the monitoring system
- implement heartbeats
- expose dashboard freshness
- secure monitoring data
- protect query text
- secure notifications
- define a production alert matrix
- design layered monitoring
- troubleshoot alerts systematically
- determine alert impact
- determine alert scope
- correlate operational signals
- identify recent changes
- mitigate safely
- verify recovery
- document incidents
- use query, pipeline, and cost decision trees
- complete the hands-on observability lab
- create synthetic health telemetry
- detect failure
- detect freshness violations
- record alert events
- design a native Snowflake Alert using current syntax
- test approved notifications
- detect recovery
- record recovery
- use query tags in observability
- correlate Query History
- implement monitoring heartbeats
- design useful alert payloads
- classify severity
- design deduplication
- clean up lab resources
- use the production alert checklist
- perform daily observability reviews
- perform weekly observability reviews
- perform monthly observability reviews
- use the incident evidence template
- execute the observability runbook
- avoid common monitoring mistakes
- follow production observability principles
- execute the DBRE/SRE observability flow

---

## Key Takeaways

Snowflake observability should not be reduced to:

```text
Dashboard exists
```

A production system requires:

```text
Telemetry
   |
   v
Understanding
   |
   v
Detection
   |
   v
Action
```

The most useful monitoring architecture is:

```text
Snowflake
   |
   v
Operational telemetry
   |
   v
Metrics + events
   |
   +---- Dashboards
   |
   +---- Alerts
            |
            v
       Notifications
            |
            v
         Runbook
            |
            v
        Responder
```

For alerts:

```text
Actionable
+
Contextual
+
Owned
+
Routed
+
Deduplicated
+
Recoverable
```

For performance:

```text
Latency
+
Queueing
+
Failures
+
Workload context
```

For pipelines:

```text
Execution status
+
Freshness
+
Completeness
```

For platform operations:

```text
Query
+
Warehouse
+
Pipeline
+
Storage
+
Security
+
Cost
```

For end-to-end troubleshooting:

```text
Application request
      |
      v
Query ID / Query Tag
      |
      v
Snowflake query
      |
      v
Warehouse
      |
      v
Query Profile
```

The most important operational principle is:

> An alert is valuable only when it detects a meaningful condition, reaches the correct owner, provides enough context to investigate, and leads to a clear operational action.

A mature Snowflake observability system should answer:

```text
What happened?
When did it begin?
Who is affected?
What changed?
Which workload is involved?
Which warehouse is involved?
Are queries queueing?
Are pipelines fresh?
Are tasks succeeding?
Is storage behaving normally?
Is cost behaving normally?
Is there a security concern?
What is the severity?
Who owns the response?
What should they do next?
Has the system recovered?
Did our monitoring work as expected?
```

The next chapter is **Chapter 51 — Snowflake Credit & Billing Model**.
