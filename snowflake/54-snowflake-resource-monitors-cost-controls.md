# Chapter 54 --- Snowflake Resource Monitors & Cost Controls

## 54.1 Overview

Snowflake resource monitors provide operational guardrails for compute
consumption. The objective is to detect unexpected consumption, notify
operators, prevent runaway workloads, preserve production reliability,
and provide predictable incident response.

## 54.2 Why Cost Controls Are Necessary

Unexpected consumption can result from warehouse resizing, disabled
AUTO_SUSPEND, new workloads, concurrency, multi-cluster scale-out,
duplicate ETL execution, retry loops, ad hoc queries, deployments, and
scheduling changes.

## 54.3 Resource Monitor Fundamentals

A resource monitor tracks virtual-warehouse credit consumption and can
notify or enforce actions at configured thresholds.

## 54.4 Resource Monitor Architecture

Core components are credit quota, frequency, start time, optional end
time, threshold triggers, and warehouse assignments.

## 54.5 Create a Resource Monitor

``` sql
CREATE RESOURCE MONITOR ETL_MONITOR
WITH
    CREDIT_QUOTA = 1000
    FREQUENCY = MONTHLY
    START_TIMESTAMP = IMMEDIATELY
TRIGGERS
    ON 70 PERCENT DO NOTIFY
    ON 90 PERCENT DO NOTIFY
    ON 100 PERCENT DO SUSPEND;
```

## 54.6 Understanding CREDIT_QUOTA

Base quotas on historical consumption, expected growth, and operational
headroom rather than arbitrary values.

## 54.7 Resource Monitor Frequency

Choose the supported frequency that matches the operational and
financial control period.

## 54.8 Start Timestamp

Use `START_TIMESTAMP = IMMEDIATELY` or an explicit schedule and align
the monitoring cycle with the cost-management period.

## 54.9 Resource Monitor Triggers

Primary actions are `NOTIFY`, `SUSPEND`, and `SUSPEND_IMMEDIATE`.

## 54.10 NOTIFY

Use notification thresholds as early warnings so operators can
investigate while workloads continue.

## 54.11 Multiple Notification Thresholds

Use escalating thresholds such as 70%, 85%, and 95%, while avoiding
unnecessary alert noise.

## 54.12 SUSPEND

`SUSPEND` provides stronger enforcement and should be applied carefully
to production workloads.

## 54.13 SUSPEND_IMMEDIATE

Reserve immediate suspension for situations where strict containment
outweighs the impact to running work.

## 54.14 Recommended Threshold Pattern

A practical starting model is 70% notify, 85% notify, 95% escalation,
and 100% suspension where operationally safe.

## 54.15 Production vs. Non-Production Controls

Development can use stricter enforcement. Production requires SLA-aware
thresholds, escalation, operational headroom, and careful containment.

## 54.16 Assign a Resource Monitor to a Warehouse

``` sql
ALTER WAREHOUSE ETL_WH
SET RESOURCE_MONITOR = ETL_MONITOR;
```

## 54.17 Multiple Warehouses Under One Monitor

Shared monitors can implement environment-level, team-level, or
project-level quotas.

## 54.18 Dedicated vs. Shared Resource Monitors

Dedicated monitors improve ownership and workload-specific controls.
Shared monitors simplify administration.

## 54.19 Account-Level Resource Monitor

Account-level resource monitoring can provide broader virtual-warehouse
guardrails, but it should not be interpreted as controlling every
possible Snowflake charge.

## 54.20 Resource Monitor Scope Limitation

Resource monitors are not complete billing controls. Combine them with
budgets, usage monitoring, alerts, and FinOps governance.

## 54.21 Inspect Resource Monitors

``` sql
SHOW RESOURCE MONITORS;
```

## 54.22 Inspect Warehouses

``` sql
SHOW WAREHOUSES;
```

## 54.23 Modify a Resource Monitor

``` sql
ALTER RESOURCE MONITOR ETL_MONITOR
SET CREDIT_QUOTA = 2000;
```

Investigate why consumption changed before increasing a quota.

## 54.24 Remove a Resource Monitor from a Warehouse

``` sql
ALTER WAREHOUSE ETL_WH
UNSET RESOURCE_MONITOR;
```

Treat removal as a controlled configuration change.

## 54.25 Cost Baselines Before Quotas

``` sql
SELECT
    warehouse_name,
    DATE_TRUNC('day', start_time) AS usage_day,
    ROUND(SUM(credits_used), 2) AS credits_used
FROM snowflake.account_usage.warehouse_metering_history
WHERE start_time >= DATEADD('day', -30, CURRENT_TIMESTAMP())
GROUP BY warehouse_name, usage_day
ORDER BY usage_day DESC, credits_used DESC;
```

## 54.26 Monthly Warehouse Consumption

``` sql
SELECT
    warehouse_name,
    DATE_TRUNC('month', start_time) AS usage_month,
    ROUND(SUM(credits_used), 2) AS credits_used
FROM snowflake.account_usage.warehouse_metering_history
WHERE start_time >= DATEADD('month', -6, CURRENT_TIMESTAMP())
GROUP BY warehouse_name, usage_month
ORDER BY usage_month DESC, credits_used DESC;
```

## 54.27 Quota Sizing Model

Initial quota = baseline monthly usage + expected growth + operational
headroom. Adjust the model for workload variability.

## 54.28 Quota Is a Guardrail, Not Capacity Planning

A quota controls allowed consumption; it does not determine whether a
warehouse can meet its SLA.

## 54.29 Snowflake Budgets

Budgets provide broader cost monitoring and complement resource
monitors.

## 54.30 Resource Monitor vs. Budget

Resource monitors are strong virtual-warehouse controls. Budgets are
better suited to broader cost monitoring. Use them together where
appropriate.

## 54.31 Recommended Combined Model

Use resource monitors for warehouse guardrails, budgets for broader
visibility, and FinOps monitoring for governance and response.

## 54.32 Warehouse Auto-Suspend Is Still Required

``` sql
ALTER WAREHOUSE DEV_WH
SET
    AUTO_SUSPEND = 60
    AUTO_RESUME = TRUE;
```

AUTO_SUSPEND controls idle runtime while resource monitors control
cumulative consumption.

## 54.33 Preventing Runaway Development Warehouses

Combine small default sizes, AUTO_SUSPEND, resource monitors,
notifications, restricted modification, and controlled multi-cluster
scaling.

## 54.34 Preventing Accidental Warehouse Upsizing

Use RBAC, change management, configuration monitoring, resource
monitors, anomaly alerts, and periodic audits.

## 54.35 RBAC as a Cost Control

Restrict permissions to resize/create warehouses, alter suspension
settings, enable multi-cluster, and modify/remove resource monitors.

## 54.36 Multi-Cluster Cost Guardrails

Review cluster limits, scaling policy, concurrency, queueing, and credit
consumption together.

## 54.37 Cost Alert Investigation

Identify the monitor and warehouses, compare against baseline, determine
what changed, and classify consumption as expected or abnormal before
modifying quotas.

## 54.38 Warehouse Cost Investigation

``` sql
SELECT
    warehouse_name,
    ROUND(SUM(credits_used), 2) AS credits_used
FROM snowflake.account_usage.warehouse_metering_history
WHERE start_time >= DATEADD('day', -7, CURRENT_TIMESTAMP())
GROUP BY warehouse_name
ORDER BY credits_used DESC;
```

## 54.39 Query Investigation After a Cost Alert

``` sql
SELECT
    query_id,
    user_name,
    role_name,
    warehouse_name,
    query_type,
    start_time,
    end_time,
    total_elapsed_time,
    bytes_scanned,
    rows_produced,
    query_text
FROM snowflake.account_usage.query_history
WHERE warehouse_name = 'PROD_ETL_WH'
  AND start_time >= DATEADD('hour', -24, CURRENT_TIMESTAMP())
ORDER BY total_elapsed_time DESC
LIMIT 100;
```

## 54.40 Detect Recent Warehouse Configuration Changes

Review warehouse size, AUTO_SUSPEND, AUTO_RESUME, multi-cluster
settings, monitor assignments, new warehouses, and new workloads. Ask:
**What changed?**

## 54.41 Resource Monitor Incident Example

If a development monitor reaches 90% because a warehouse changed from
SMALL to 2X-LARGE and AUTO_SUSPEND was disabled, correct the
configuration and governance rather than simply increasing the quota.

## 54.42 Production Cost-Control Runbook

1.  Identify the monitor and threshold.
2.  Identify affected warehouses.
3.  Determine current quota consumption.
4.  Compare against historical baseline.
5.  Identify recent configuration changes.
6.  Check warehouse size and auto-suspend.
7.  Check multi-cluster behavior.
8.  Review query volume and long-running queries.
9.  Check failed/retried workloads.
10. Identify the workload owner.
11. Determine expected versus abnormal consumption.
12. Assess business impact.
13. Contain abnormal consumption if required.
14. Correct root cause.
15. Verify consumption stabilizes.
16. Review thresholds.
17. Add preventive controls.
18. Document findings.

## 54.43 Emergency Containment

``` sql
ALTER WAREHOUSE DEV_WH SUSPEND;
```

Other actions can include stopping runaway jobs, disabling duplicate
schedules, resizing warehouses, correcting auto-suspend, restricting
roles, and fixing retry behavior.

## 54.44 Before Suspending Production

Assess customer impact, ETL/pipeline dependencies, recovery
implications, SLA impact, and running work.

## 54.45 Alert Escalation Model

Map thresholds to ownership: informational review, SRE/DBRE warning,
high-urgency escalation, and environment-specific enforcement.

## 54.46 Production Guardrail Strategy

Combine AUTO_SUSPEND, RBAC, resource monitors, cost alerts, SRE/DBRE
ownership, and incident runbooks.

## 54.47 Non-Production Guardrail Strategy

Use small defaults, AUTO_SUSPEND/AUTO_RESUME, strict quotas, restricted
resizing, anomaly alerts, and cleanup.

## 54.48 Recommended Governance Matrix

Development and test can use stronger automatic enforcement. Production
and critical production should use SLA-aware enforcement and escalation.

## 54.49 Cost-Control Ownership

Every monitor needs an owner, technical owner, business owner, and
escalation path.

## 54.50 Monitor Naming Standard

Use predictable names such as `RM_PROD_ETL`, `RM_PROD_BI`,
`RM_DEV_ANALYTICS`, and `RM_TEAM_FINANCE`.

## 54.51 Document Every Monitor

Document scope, owner, warehouses, quota, frequency, thresholds,
expected consumption, escalation, enforcement behavior, and business
justification.

## 54.52 Monthly Resource Monitor Review

Review quota, actual usage, peak usage, threshold events, assignments,
ownership, workload changes, growth trends, enforcement behavior, and
budget alignment.

## 54.53 Weekly SRE/DBRE Review

Review alerts, warehouses approaching quota, unexpected growth, size
changes, auto-suspend, multi-cluster settings, new/unmonitored
warehouses, failed/retried workloads, and anomalies.

## 54.54 Detect Warehouses Without Governance

Compare `SHOW WAREHOUSES` with `SHOW RESOURCE MONITORS`. At scale,
automate configuration inventory and policy validation.

## 54.55 Resource Monitor Drift

Monitor for removed monitors, changed quotas/triggers, reassignment,
unmonitored warehouses, and incorrect environment assignments.

## 54.56 Infrastructure as Code

Where supported, manage cost-control configuration through IaC for
versioning, peer review, auditability, repeatability, consistency, and
drift detection.

## 54.57 Resource Monitor Testing

Validate monitor existence, assignments, thresholds, notifications,
escalation, enforcement behavior, and recovery procedures in a safe
environment.

## 54.58 Recovery After Resource Monitor Suspension

Confirm enforcement, determine why the quota was reached, correct
abnormal workload, decide whether quota adjustment is justified, restore
service, and validate.

## 54.59 What Not to Do

Do not blindly increase quotas, hard-stop critical production, assume
monitors cover every charge, configure arbitrary quotas, remove controls
to silence alerts, ignore serverless consumption, or operate alerts
without ownership.

## 54.60 Common Resource Monitor Mistakes

Common failures include arbitrary quotas, premature hard stops, alerts
without action, shared monitors without ownership, ignoring
non-warehouse consumption, and increasing quotas instead of fixing
waste.

## 54.61 Recommended Production Standards

Every production warehouse should have ownership, reviewed auto-suspend,
an appropriate resource-monitor strategy, documented thresholds and
escalation, baseline-based quotas, restricted resizing, governed
changes, periodic audits, and separate serverless monitoring.

## 54.62 SRE/DBRE Cost-Control Checklist

Validate monitor existence, assignment, quota, frequency, schedule,
thresholds, SLA impact, ownership, escalation, auto-suspend/resume,
warehouse size, multi-cluster configuration, RBAC, baselines, anomaly
alerts, serverless monitoring, budgets, drift, and runbook testing.

## 54.63 Operational Decision Tree

On an alert, identify the threshold and service impact, compare usage
with baseline, determine what changed and whether growth is expected,
then review the quota or contain/correct abnormal workload. Verify
usage, update the baseline, and prevent recurrence.

## 54.64 Production Scenario

Assume `PROD_ETL_WH` normally consumes 2,500 credits/month with a
3,500-credit quota. If usage reaches 85% by day 18 while historical
expectation is approximately 55%, investigate before changing the quota.

If ETL changed from once per day to once per hour, validate the
requirement, contact the workload owner, correct an accidental schedule,
verify query volume, monitor consumption, and document the incident.

If the increase was intentional and approved, recalculate expected
consumption, validate capacity, update the forecast, review the quota,
and establish the new baseline.

## 54.65 Resource Monitor Maturity Model

Maturity progresses from no controls → visibility → guardrails →
governed controls → automated IaC, drift detection, anomaly detection,
policy validation, and FinOps integration.

The goal is to move from:

``` text
Why did Snowflake consume so many credits?
```

to:

``` text
We detected abnormal consumption early,
identified the owner,
contained the issue,
and prevented recurrence.
```

## 54.66 Key Takeaways

1.  Resource monitors provide Snowflake warehouse credit guardrails.
2.  Resource monitors use credit quotas and threshold triggers.
3.  `NOTIFY` is appropriate for early warning.
4.  `SUSPEND` provides stronger enforcement.
5.  `SUSPEND_IMMEDIATE` requires careful operational consideration.
6.  Production and non-production require different enforcement
    policies.
7.  Quotas should be based on historical consumption and expected
    growth.
8.  Shared monitors simplify administration but can complicate
    ownership.
9.  Dedicated monitors improve workload-specific control.
10. Resource monitors do not control every Snowflake charge.
11. Serverless consumption must also be monitored.
12. Budgets complement resource monitors.
13. AUTO_SUSPEND remains an independent cost control.
14. RBAC is part of cost governance.
15. Multi-cluster configuration must be included in control design.
16. Cost alerts require ownership and operational response.
17. Investigate before increasing quotas.
18. Resource-monitor configuration should be governed and audited.
19. Infrastructure as code can improve consistency and drift control.
20. Cost controls must protect financial objectives and production
    reliability.

## 54.67 Chapter Completion Checklist

After completing this chapter, you should be able to:

-   Explain Snowflake resource monitors and credit quotas.
-   Configure resource-monitor frequencies and triggers.
-   Create and assign resource monitors.
-   Explain `NOTIFY`, `SUSPEND`, and `SUSPEND_IMMEDIATE`.
-   Design shared and dedicated monitor strategies.
-   Understand resource-monitor scope limitations.
-   Inspect and safely modify monitors.
-   Establish consumption baselines and quotas.
-   Explain the relationship between budgets and resource monitors.
-   Combine auto-suspend and resource monitors.
-   Design development and production guardrails.
-   Incorporate RBAC into cost governance.
-   Investigate resource-monitor alerts.
-   Identify and contain runaway consumption.
-   Design escalation and ownership.
-   Detect configuration drift.
-   Incorporate cost controls into IaC.
-   Test resource-monitor behavior.
-   Recover safely from quota enforcement.
-   Apply the SRE/DBRE cost-control runbook.

**Chapter 54 --- Snowflake Resource Monitors & Cost Controls: Complete**
