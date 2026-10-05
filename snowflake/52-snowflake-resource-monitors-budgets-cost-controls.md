# Chapter 52 — Snowflake Resource Monitors, Budgets & Cost Controls

## 52.1 Overview

Chapter 51 explained how Snowflake credits are consumed and how compute costs can be investigated.

The next operational requirement is **cost control**.

A production Snowflake environment should not rely solely on engineers noticing that credit consumption has increased.

Instead, organizations should establish controls that can:

- Monitor consumption
- Detect abnormal spending
- Notify responsible teams
- Enforce warehouse credit limits
- Attribute cost to workloads
- Prevent runaway workloads
- Establish application and team ownership
- Protect production workloads from inappropriate enforcement actions

Two important Snowflake capabilities are:

```text
Resource Monitors
        +
Snowflake Budgets
```

They address related cost-governance problems but should not be considered identical.

---

## 52.2 Cost Governance Model

A practical Snowflake FinOps model looks like:

```text
                 Snowflake Account
                        |
        +---------------+---------------+
        |                               |
   Cost Visibility                 Cost Controls
        |                               |
 ACCOUNT_USAGE                    Resource Monitors
 Metering Views                         |
 Query Attribution                 Credit Quotas
 Tags                                  |
 Budgets                         Notifications
        |                               |
        +---------------+---------------+
                        |
                 Operational Response
```

The goal is not simply:

```text
Spend less
```

The real objective is:

```text
Understand cost
      +
Control abnormal consumption
      +
Maintain workload reliability
```

---

## 52.3 Why Cost Controls Are Necessary

Without cost controls, several operational problems can occur.

For example:

```text
Application retry loop
        ↓
Thousands of queries
        ↓
Warehouse continuously active
        ↓
Credit consumption increases
        ↓
Problem continues unnoticed
        ↓
Unexpected Snowflake bill
```

Another example:

```text
Analyst changes warehouse

MEDIUM
   ↓
4X-LARGE

Runs expensive query
        ↓
Warehouse remains active
        ↓
Large credit spike
```

Cost governance should detect these situations before they become large billing events.

---

## 52.4 Resource Monitors

A Snowflake **resource monitor** monitors credit consumption associated with supported virtual warehouse compute.

A resource monitor can define:

```text
Credit quota
Frequency
Start time
Trigger thresholds
Trigger actions
```

Typical actions include:

```text
NOTIFY
SUSPEND
SUSPEND_IMMEDIATE
```

Resource monitors are especially useful when organizations want to enforce warehouse credit limits.

---

## 52.5 Resource Monitor Architecture

Conceptually:

```text
              RESOURCE MONITOR
                     |
               CREDIT_QUOTA
                     |
          +----------+----------+
          |          |          |
         70%        90%        100%
          |          |          |
       NOTIFY     NOTIFY      SUSPEND
```

For example:

```text
Monthly quota = 10,000 credits

70%  → warning
90%  → critical warning
100% → suspend
```

This creates an operational guardrail around warehouse consumption.

---

## 52.6 Creating a Resource Monitor

Example:

```sql
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

This monitor defines:

```text
Quota      = 1000 credits
Frequency  = Monthly

70%        = Notify
90%        = Notify
100%       = Suspend
```

---

## 52.7 Assigning a Resource Monitor to a Warehouse

After creating the resource monitor:

```sql
ALTER WAREHOUSE ETL_WH
SET RESOURCE_MONITOR = ETL_MONITOR;
```

The warehouse is now governed by that resource monitor.

Verify warehouse configuration:

```sql
SHOW WAREHOUSES;
```

And inspect resource monitors:

```sql
SHOW RESOURCE MONITORS;
```

---

## 52.8 Multiple Warehouses Under One Monitor

A resource monitor can be used to control a group of warehouses.

Conceptually:

```text
              ETL_RESOURCE_MONITOR
                       |
          +------------+------------+
          |            |            |
       ETL_WH_1     ETL_WH_2     ETL_WH_3
```

The quota represents the monitored credit consumption across the warehouses associated with the monitor.

This can be useful for team-level or workload-level governance.

Example:

```text
DATA_ENGINEERING_MONITOR

    INGESTION_WH
    ETL_WH
    TRANSFORM_WH
```

---

## 52.9 Dedicated vs. Shared Resource Monitors

There are two common designs.

### Dedicated Monitor

```text
ETL_WH
   |
ETL_MONITOR
```

Benefits:

- Clear ownership
- Clear credit limits
- Easier troubleshooting
- Easier workload attribution

### Shared Monitor

```text
        TEAM_MONITOR
             |
      +------+------+
      |             |
   ETL_WH         BI_WH
```

Benefits:

- Team-level budget control
- Simpler administration

Disadvantage:

One warehouse can consume most of the shared quota.

For critical workloads, dedicated monitors often provide better isolation.

---

## 52.10 Resource Monitor Frequencies

Resource monitors can reset according to configured frequency.

Common operational patterns include:

```text
DAILY
WEEKLY
MONTHLY
YEARLY
```

The correct frequency depends on the governance requirement.

Examples:

```text
Development warehouse
        ↓
Monthly quota

High-risk batch workload
        ↓
Daily monitoring

Department allocation
        ↓
Monthly governance
```

---

## 52.11 Understanding Trigger Percentages

Assume:

```text
CREDIT_QUOTA = 1000
```

Then:

```text
50%  = 500 credits
75%  = 750 credits
90%  = 900 credits
100% = 1000 credits
```

Example:

```sql
TRIGGERS
    ON 50 PERCENT DO NOTIFY
    ON 75 PERCENT DO NOTIFY
    ON 90 PERCENT DO NOTIFY
    ON 100 PERCENT DO SUSPEND;
```

This gives operations teams several opportunities to respond before enforcement occurs.

---

## 52.12 NOTIFY

The least disruptive action is:

```text
NOTIFY
```

Conceptually:

```text
Quota threshold reached
        ↓
Notification generated
        ↓
Warehouse continues running
```

This is appropriate for warning thresholds.

Example:

```sql
ON 70 PERCENT DO NOTIFY
```

Use notification thresholds early enough that teams have time to investigate.

---

## 52.13 SUSPEND

A stronger control is:

```text
SUSPEND
```

This can prevent additional warehouse credit consumption after the resource-monitor threshold is exceeded according to Snowflake's resource-monitor behavior.

Example:

```sql
ON 100 PERCENT DO SUSPEND
```

This is useful for environments where exceeding the quota is less acceptable than interrupting additional compute.

Examples:

```text
DEV
TEST
SANDBOX
TRAINING
```

Production requires more careful consideration.

---

## 52.14 SUSPEND_IMMEDIATE

The strongest resource-monitor action is:

```text
SUSPEND_IMMEDIATE
```

Example:

```sql
ON 110 PERCENT DO SUSPEND_IMMEDIATE;
```

This is a disruptive action.

It should be treated similarly to an automated operational kill switch.

Potential impact:

```text
Running queries interrupted
ETL processing interrupted
Dashboard queries fail
Applications receive errors
Scheduled workloads fail
```

Do not use aggressive enforcement thresholds on critical production warehouses without understanding the availability impact.

---

## 52.15 Recommended Threshold Model

A practical pattern might be:

```text
50%   Informational
75%   Warning
90%   Critical
100%  Escalation
110%  Enforcement
```

For example:

```sql
CREATE RESOURCE MONITOR DEV_MONITOR
WITH
    CREDIT_QUOTA = 500
    FREQUENCY = MONTHLY
    START_TIMESTAMP = IMMEDIATELY
TRIGGERS
    ON 50 PERCENT DO NOTIFY
    ON 75 PERCENT DO NOTIFY
    ON 90 PERCENT DO NOTIFY
    ON 100 PERCENT DO SUSPEND
    ON 110 PERCENT DO SUSPEND_IMMEDIATE;
```

The exact thresholds should reflect workload criticality.

---

## 52.16 Production vs. Non-Production Controls

Do not automatically apply identical controls everywhere.

### Development

Aggressive controls may be appropriate.

```text
DEV_WH

75%  → NOTIFY
90%  → NOTIFY
100% → SUSPEND
```

### Production

Availability may be more important than a strict quota.

```text
PROD_ETL_WH

70%  → NOTIFY
85%  → NOTIFY
95%  → CRITICAL ALERT
```

A production organization may intentionally avoid automatic suspension and instead use operational escalation.

The design depends on business requirements.

---

## 52.17 Account-Level Resource Monitor

Resource monitors can also participate in broader account-level warehouse credit governance.

Conceptually:

```text
ACCOUNT
   |
ACCOUNT_RESOURCE_MONITOR
   |
   +--- ETL_WH
   +--- BI_WH
   +--- ADHOC_WH
   +--- DEV_WH
```

This provides another layer of warehouse credit governance.

However, broad enforcement actions should be designed carefully because they can affect multiple workloads.

---

## 52.18 Inspecting Resource Monitors

Use:

```sql
SHOW RESOURCE MONITORS;
```

This provides information about configured monitors.

Operationally review:

```text
Name
Credit quota
Frequency
Used credits
Remaining quota
Trigger configuration
```

This should be part of regular Snowflake platform review.

---

## 52.19 Modifying a Resource Monitor

Example:

```sql
ALTER RESOURCE MONITOR ETL_MONITOR
SET CREDIT_QUOTA = 2000;
```

Triggers can also be changed as governance requirements evolve.

Always document why quota changes were made.

Avoid:

```text
Monitor reached quota
      ↓
Engineer increases quota
      ↓
No investigation
```

The correct process is:

```text
Monitor reached quota
      ↓
Investigate consumption
      ↓
Determine expected vs abnormal
      ↓
Optimize if necessary
      ↓
Change quota only if justified
```

---

## 52.20 Removing a Resource Monitor from a Warehouse

If governance requirements change:

```sql
ALTER WAREHOUSE ETL_WH
UNSET RESOURCE_MONITOR;
```

Before doing this in production, confirm that another cost-control mechanism exists.

Removing a monitor without replacement can eliminate an important guardrail.

---

## 52.21 Snowflake Budgets

Snowflake Budgets provide broader cost-monitoring capabilities.

Conceptually:

```text
Resource Monitor
       |
Warehouse credit enforcement

Budget
       |
Cost monitoring and governance
across supported Snowflake resources
```

Budgets are especially useful when organizations need visibility beyond individual warehouse quotas.

---

## 52.22 Why Budgets Are Important

Modern Snowflake workloads can consume resources through more than virtual warehouses.

Examples include:

```text
Virtual warehouses
Snowpipe
Automatic clustering
Serverless tasks
Search Optimization
Materialized view maintenance
Other serverless features
```

A governance model focused only on warehouse credits can miss significant consumption.

Budgets help provide broader cost visibility for supported resources.

---

## 52.23 Resource Monitor vs. Budget

| Capability | Resource Monitor | Budget |
|---|---|---|
| Warehouse credit monitoring | Yes | Supported cost monitoring |
| Credit quota | Yes | Budget-based |
| Notification | Yes | Yes |
| Automatic warehouse suspension | Yes | No equivalent warehouse kill-switch behavior |
| Serverless visibility | Limited | Broader supported scope |
| Primary purpose | Enforcement | Spend monitoring |
| Best use | Warehouse guardrail | FinOps governance |

The two mechanisms complement each other.

A mature Snowflake environment may use both.

---

## 52.24 Recommended Combined Model

```text
                    Snowflake Account
                           |
                         Budget
                           |
                 Account Cost Visibility
                           |
             +-------------+-------------+
             |                           |
        Production                  Development
             |                           |
      Resource Monitor             Resource Monitor
             |                           |
       Notifications              Notifications
             |                           |
     Human escalation          Automatic suspension
```

This balances cost governance with workload reliability.

---

## 52.25 Cost Ownership

Every warehouse should have an identifiable owner.

Recommended metadata:

```text
Warehouse
Application
Environment
Team
Cost center
Owner
Business criticality
```

Example:

```text
Warehouse: PROD_ETL_WH
Application: DATA_PLATFORM
Environment: PROD
Team: DATA_ENGINEERING
Cost Center: CC-1042
Criticality: HIGH
```

Without ownership, alerts frequently become:

```text
Cost increased
      ↓
Nobody knows who owns the workload
```

---

## 52.26 Using Tags for Cost Governance

Snowflake tags can help associate resources with ownership metadata.

Conceptually:

```text
COST_CENTER = DATA_PLATFORM
ENVIRONMENT = PROD
APPLICATION = ANALYTICS
OWNER = DATA_ENGINEERING
```

Cost attribution can then be designed around these organizational dimensions.

A strong tagging standard should be established before the Snowflake environment becomes large.

---

## 52.27 Warehouse Naming Standards

Warehouse names should communicate purpose.

Good examples:

```text
PROD_ETL_WH
PROD_BI_WH
PROD_INGESTION_WH
DEV_ANALYTICS_WH
QA_ETL_WH
```

Poor examples:

```text
WH1
WH2
BIG_WH
TEST123
TEMP_WH
```

Clear naming makes incident and cost investigations much easier.

---

## 52.28 Preventing Runaway Warehouses

Common runaway scenarios include:

```text
Application retry loops
Bad deployment
Infinite job retry
Unexpected concurrency
Large Cartesian join
Warehouse resized accidentally
Dashboard refresh storm
Uncontrolled analyst query
```

Controls should include:

```text
AUTO_SUSPEND
Resource Monitor
Budget
Query monitoring
Workload isolation
RBAC
Alerting
```

No single control is sufficient.

---

## 52.29 Preventing Accidental Warehouse Upsizing

Warehouse resizing can dramatically change credit burn rate.

Example:

```text
MEDIUM
   ↓
4X-LARGE
```

A seemingly simple configuration change can substantially increase hourly credit consumption.

Restrict warehouse modification privileges.

Only appropriate administrative roles should be able to execute operations such as:

```sql
ALTER WAREHOUSE PROD_ETL_WH
SET WAREHOUSE_SIZE = '4X-LARGE';
```

RBAC is therefore part of FinOps governance.

---

## 52.30 Multi-Cluster Cost Controls

Multi-cluster warehouses require additional attention.

Example:

```text
Warehouse Size = LARGE
MAX_CLUSTER_COUNT = 10
```

During heavy concurrency:

```text
1 cluster
   ↓
2
   ↓
4
   ↓
8
   ↓
10
```

Credit consumption can rise quickly.

Monitor:

```text
MIN_CLUSTER_COUNT
MAX_CLUSTER_COUNT
SCALING_POLICY
Queueing
Cluster utilization
Credits consumed
```

Do not configure large maximum cluster counts without workload evidence.

---

## 52.31 Serverless Cost Governance

Serverless workloads should also have ownership.

Track features such as:

```text
Snowpipe
Automatic Clustering
Search Optimization
Materialized Views
Serverless Tasks
Query Acceleration
```

Questions to ask:

```text
Who enabled the feature?
Which application benefits?
What is normal daily consumption?
What is the expected monthly cost?
What alert threshold exists?
```

Serverless does not mean free.

It means Snowflake manages the compute.

---

## 52.32 Detecting Cost Anomalies

Start with account-level consumption.

```sql
SELECT
    usage_date,
    service_type,
    credits_used,
    credits_billed
FROM snowflake.account_usage.metering_daily_history
WHERE usage_date >= DATEADD('day', -30, CURRENT_DATE())
ORDER BY usage_date DESC, credits_used DESC;
```

Look for unexpected changes.

Example:

```text
Normal:
AUTOMATIC_CLUSTERING = 15 credits/day

Today:
AUTOMATIC_CLUSTERING = 180 credits/day
```

That requires investigation.

---

## 52.33 Warehouse Cost Investigation

```sql
SELECT
    warehouse_name,
    ROUND(SUM(credits_used), 2) AS credits_used
FROM snowflake.account_usage.warehouse_metering_history
WHERE start_time >= DATEADD('day', -7, CURRENT_TIMESTAMP())
GROUP BY warehouse_name
ORDER BY credits_used DESC;
```

Identify the largest consumers first.

Then investigate workload behavior.

---

## 52.34 Daily Warehouse Baseline

```sql
SELECT
    DATE_TRUNC('day', start_time) AS usage_day,
    warehouse_name,
    ROUND(SUM(credits_used), 2) AS credits
FROM snowflake.account_usage.warehouse_metering_history
WHERE start_time >= DATEADD('day', -30, CURRENT_TIMESTAMP())
GROUP BY usage_day, warehouse_name
ORDER BY usage_day DESC, credits DESC;
```

This allows operators to establish normal consumption.

Example:

```text
PROD_ETL_WH

Normal:
80–110 credits/day

Warning:
130 credits/day

Critical:
175 credits/day
```

Thresholds should be workload-specific.

---

## 52.35 Percentage-Based Anomaly Detection

Absolute thresholds are useful but not always sufficient.

Example:

```text
Yesterday = 100 credits
Today     = 180 credits

Increase = 80%
```

A FinOps monitoring system might alert when:

```text
Daily consumption
>
30-day average × 1.5
```

This catches abnormal growth even when absolute quotas have not yet been reached.

---

## 52.36 Query Investigation After Cost Alert

After identifying the warehouse:

```sql
SELECT
    query_id,
    user_name,
    role_name,
    warehouse_name,
    query_type,
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

Investigate:

```text
Long-running queries
Large scans
Retry loops
Repeated queries
Unexpected users
New applications
Large transformations
```

---

## 52.37 Resource Monitor Incident

Example:

```text
PROD_ETL_MONITOR

Monthly quota:
10,000 credits

Current:
9,100 credits

Usage:
91%
```

A critical alert fires.

Do not immediately increase the quota.

Investigate:

```text
When did consumption increase?
Which warehouse increased?
Which workload changed?
Was the increase expected?
Was a deployment performed?
Did data volume increase?
Did concurrency increase?
Was warehouse size changed?
```

Only after answering these questions should the quota be reconsidered.

---

## 52.38 Production Cost-Control Runbook

When a cost alert fires:

```text
STEP 1
Confirm alert and time window

STEP 2
Check account-level metering

STEP 3
Identify service type

STEP 4
Identify warehouse/serverless feature

STEP 5
Compare against baseline

STEP 6
Check configuration changes

STEP 7
Inspect workload/query history

STEP 8
Identify owner

STEP 9
Determine expected vs abnormal usage

STEP 10
Contain runaway consumption if required

STEP 11
Optimize workload

STEP 12
Review quota/budget

STEP 13
Document root cause

STEP 14
Add preventive control
```

---

## 52.39 Emergency Containment

Suppose a development workload is consuming credits uncontrollably.

Possible containment action:

```sql
ALTER WAREHOUSE DEV_WH SUSPEND;
```

Before suspending a production warehouse, determine:

```text
Business impact
Running jobs
Application dependencies
SLA impact
Recovery procedure
```

Cost containment should not accidentally become a production outage.

---

## 52.40 Production Guardrail Strategy

A mature environment might use:

```text
                 ACCOUNT
                    |
                 BUDGET
                    |
         Account-Level Alerts
                    |
       +------------+------------+
       |                         |
     PROD                      NON-PROD
       |                         |
Notifications              Resource Monitors
       |                         |
Human escalation           Hard quotas
       |
Application-level monitors
```

Production focuses more heavily on:

```text
Visibility
Alerting
Escalation
Ownership
```

Non-production can often tolerate stronger automated enforcement.

---

## 52.41 Recommended Governance Matrix

| Environment | Warning | Critical | Automatic Suspend |
|---|---:|---:|---|
| Sandbox | 70% | 90% | Yes |
| Development | 70% | 90% | Yes |
| QA | 75% | 90% | Optional |
| Staging | 75% | 90% | Carefully |
| Production | 70% | 90% | Usually human-controlled |

This is a starting framework, not a universal rule.

Business requirements should determine final policy.

---

## 52.42 Monthly Cost Review

At least monthly, review:

```text
Total credits
Credits by warehouse
Credits by service
Storage growth
Serverless usage
Top workloads
Unused warehouses
Warehouse sizing
Auto-suspend settings
Multi-cluster configuration
Resource monitor status
Budget status
Cost anomalies
Ownership metadata
```

FinOps should be an operational process, not only an accounting exercise.

---

## 52.43 Weekly SRE/DBRE Review

A shorter weekly review can focus on:

```text
[ ] Top 10 warehouses by credits
[ ] Week-over-week credit growth
[ ] Serverless anomalies
[ ] Resource monitor thresholds
[ ] Budget alerts
[ ] Warehouse configuration changes
[ ] Unexpected large warehouses
[ ] Multi-cluster growth
[ ] Long-running expensive workloads
```

This can prevent monthly billing surprises.

---

## 52.44 Common Mistakes

### Mistake 1
Using resource monitors but nobody watches notifications.

### Mistake 2
Setting automatic suspension on critical production workloads without impact analysis.

### Mistake 3
Increasing quotas whenever thresholds are reached.

### Mistake 4
Monitoring warehouses while ignoring serverless consumption.

### Mistake 5
Using one warehouse for every workload.

### Mistake 6
Allowing too many users to resize warehouses.

### Mistake 7
No workload ownership.

### Mistake 8
No cost baseline.

### Mistake 9
No environment-specific policy.

### Mistake 10
Treating FinOps as only a finance-team responsibility.

---

## 52.45 Recommended Production Standards

Every production Snowflake deployment should define:

```text
Warehouse owner
Application owner
Cost center
Environment
Business criticality
Expected daily credits
Expected monthly credits
Warning threshold
Critical threshold
Escalation path
Resource monitor policy
Budget policy
```

This turns cost governance into an operational discipline.

---

## 52.46 SRE/DBRE Cost-Control Checklist

```text
[ ] AUTO_SUSPEND configured
[ ] AUTO_RESUME reviewed
[ ] Warehouse sizes justified
[ ] Multi-cluster limits reviewed
[ ] Resource monitors configured where appropriate
[ ] Notification thresholds configured
[ ] Suspension behavior documented
[ ] Production impact reviewed
[ ] Budgets configured where appropriate
[ ] Serverless services monitored
[ ] ACCOUNT_USAGE monitoring enabled
[ ] Cost baselines established
[ ] Daily anomaly detection implemented
[ ] Warehouse ownership documented
[ ] Cost center tagging established
[ ] RBAC restricts warehouse changes
[ ] Escalation procedures documented
[ ] Monthly FinOps review scheduled
```

---

## 52.47 Operational Decision Tree

```text
Cost Alert
    |
    v
Account consumption increased?
    |
    +--- No ---> Validate alert/baseline
    |
   Yes
    |
    v
Which service?
    |
 +--+----------------+
 |                   |
Warehouse         Serverless
 |                   |
 v                   v
Which WH?        Which feature?
 |
 v
Expected increase?
 |
 +--- Yes ---> Validate budget/capacity
 |
 No
 |
 v
Configuration changed?
 |
 +--- Yes ---> Review/rollback
 |
 No
 |
 v
Workload changed?
 |
 +--- Yes ---> Identify owner
 |
 v
Contain if necessary
 |
 v
Optimize
 |
 v
Update guardrail
```

---

## 52.48 Key Takeaways

1. Resource monitors provide warehouse credit guardrails.
2. Budgets provide broader Snowflake cost-governance capabilities.
3. `NOTIFY` is less disruptive than suspension actions.
4. Automatic suspension can affect application availability.
5. Production and development should not necessarily use identical enforcement policies.
6. Resource-monitor quotas should not be increased without investigating consumption.
7. Multi-cluster warehouses require explicit cost controls.
8. Serverless services must be monitored separately from warehouse compute.
9. RBAC is part of FinOps because warehouse resizing changes credit consumption.
10. Every warehouse should have an owner.
11. Every major workload should have a cost baseline.
12. Cost anomalies should be investigated like operational incidents.
13. FinOps should combine visibility, ownership, alerting, guardrails, and operational response.
14. Cost controls should reduce financial risk without creating unnecessary production outages.

---

## 52.49 Chapter Completion Checklist

After completing this chapter, you should be able to:

- Explain Snowflake resource monitors.
- Create a resource monitor.
- Configure credit quotas.
- Configure notification thresholds.
- Understand `SUSPEND` and `SUSPEND_IMMEDIATE`.
- Associate monitors with warehouses.
- Design shared and dedicated monitor strategies.
- Explain Snowflake Budgets.
- Distinguish budgets from resource monitors.
- Establish workload ownership.
- Use tags for cost governance.
- Design production and non-production policies.
- Detect abnormal credit consumption.
- Investigate cost alerts.
- Contain runaway warehouse consumption.
- Protect production availability while controlling cost.
- Build an SRE/DBRE Snowflake FinOps operating model.

**Chapter 52 — Snowflake Resource Monitors, Budgets & Cost Controls: Complete**
