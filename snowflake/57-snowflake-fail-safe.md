# Chapter 57 --- Snowflake Fail-safe

## 57.1 Overview

Snowflake Fail-safe provides a Snowflake-managed recovery period for
historical data after the Time Travel retention period has ended.
Fail-safe is a last-resort recovery mechanism, not a normal backup or
operational recovery strategy.

Preferred sequence:

``` text
Incident
  ↓
Time Travel available?
  ├─ Yes → Recover using Time Travel
  └─ No  → Evaluate Fail-safe eligibility and contact Snowflake Support
```

## 57.2 What Fail-safe Is

Fail-safe is an additional data-recovery period maintained by Snowflake
for eligible permanent objects after Time Travel expires. Customers
cannot directly query Fail-safe data.

## 57.3 Fail-safe Duration

For eligible permanent Snowflake tables, Fail-safe provides a 7-day
Snowflake-managed recovery period after Time Travel ends.

## 57.4 Fail-safe Is Not Configurable

Customers do not configure the Fail-safe duration. Time Travel retention
is managed through `DATA_RETENTION_TIME_IN_DAYS` within applicable
limits.

## 57.5 Time Travel + Fail-safe Recovery Timeline

A permanent table moves from its configured Time Travel window into the
Snowflake-managed Fail-safe period. Once both periods expire, those
historical recovery mechanisms are no longer available.

## 57.6 Fail-safe vs. Time Travel

Time Travel provides customer-controlled historical queries, `AT`,
`BEFORE`, historical clones, and `UNDROP`. Fail-safe is
Snowflake-managed and requires Support involvement.

## 57.7 Why Fail-safe Exists

Fail-safe provides an additional recovery layer for exceptional
situations where critical historical data is no longer available through
Time Travel.

## 57.8 Fail-safe Is Not for Routine Recovery

Normal operational recovery should use Time Travel, recovery clones, and
selective restoration. Fail-safe should remain a last resort.

## 57.9 Customer Cannot Query Fail-safe

There is no normal SQL interface for customers to query Fail-safe
historical data.

## 57.10 Customer Cannot Clone Fail-safe Data

Historical cloning is a Time Travel capability. Fail-safe does not
provide a customer SQL command to clone its historical state.

## 57.11 Customer Cannot UNDROP Through Fail-safe

`UNDROP` operates through Time Travel capabilities. Once outside that
recovery window, normal customer-controlled `UNDROP` is unavailable.

## 57.12 Permanent Tables

Eligible permanent data receives Time Travel plus Fail-safe protection
according to Snowflake's applicable behavior.

## 57.13 Transient Tables

Transient tables do not have Fail-safe protection. Do not use them for
critical production data solely to reduce storage cost without a
recovery-impact review.

## 57.14 Temporary Tables

Temporary tables are session-oriented and do not provide Fail-safe
protection.

## 57.15 Permanent vs. Transient Recovery Design

Object type is a recovery architecture decision, not merely a
storage-cost decision. Permanent storage provides stronger historical
protection; transient storage has fewer recovery layers.

## 57.16 Why Teams Use Transient Tables

Appropriate uses include staging data, intermediate ETL data,
rebuildable datasets, temporary transformations, and short-lived
pipelines.

## 57.17 When Transient Tables Become Dangerous

Avoid using transient storage blindly for authoritative customer data,
critical transaction history, regulatory records, production master
data, or irreplaceable source data.

## 57.18 Fail-safe Storage

Storage analysis should distinguish active storage, Time Travel storage,
Fail-safe storage, clone-retained storage, and stage storage.

## 57.19 Inspect Fail-safe Storage

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
ORDER BY failsafe_bytes DESC;
```

## 57.20 Convert Fail-safe Bytes to GB

``` sql
SELECT
    table_catalog,
    table_schema,
    table_name,
    ROUND(active_bytes / POWER(1024, 3), 2) AS active_gb,
    ROUND(time_travel_bytes / POWER(1024, 3), 2) AS time_travel_gb,
    ROUND(failsafe_bytes / POWER(1024, 3), 2) AS failsafe_gb
FROM snowflake.account_usage.table_storage_metrics
ORDER BY failsafe_bytes DESC;
```

## 57.21 Why Fail-safe Storage Can Grow

Large tables, high DELETE/UPDATE volume, large MERGE operations, table
replacements, full reloads, and high data churn can increase historical
storage.

## 57.22 High-Churn Example

A multi-terabyte table with daily large MERGE operations can accumulate
historical micro-partitions through Time Travel and Fail-safe lifecycle
periods.

## 57.23 Fail-safe and DELETE

A large DELETE does not necessarily release physical historical storage
immediately because deleted data can remain retained through applicable
recovery lifecycle periods.

## 57.24 Fail-safe and DROP

Dropping a permanent table does not necessarily create an immediate
equivalent storage reduction because historical data may remain
protected during its recovery lifecycle.

## 57.25 Fail-safe and Table Replacement

Repeated `CREATE OR REPLACE`, large CTAS replacements, full reloads, and
refresh patterns can contribute to historical storage.

## 57.26 Fail-safe and Cloning

Review `active_bytes`, `time_travel_bytes`, `failsafe_bytes`, and
`retained_for_clone_bytes` together when clones and changing data are
involved.

## 57.27 Fail-safe Cost Investigation

Identify high-consuming tables, compare active size, inspect churn,
review recent DELETE/MERGE/replacement operations, examine clone
relationships, and determine whether the storage lifecycle is expected.

## 57.28 Top Fail-safe Consumers

``` sql
SELECT
    table_catalog,
    table_schema,
    table_name,
    ROUND(failsafe_bytes / POWER(1024, 3), 2) AS failsafe_gb
FROM snowflake.account_usage.table_storage_metrics
WHERE failsafe_bytes > 0
ORDER BY failsafe_bytes DESC
LIMIT 50;
```

## 57.29 Fail-safe Storage Is Not Necessarily Waste

High Fail-safe storage may represent expected historical protection.
Investigate what changed, how much changed, when it changed, and whether
the storage trend matches the expected lifecycle.

## 57.30 Fail-safe Recovery Scenario

If critical data loss is discovered after the Time Travel window
expires, evaluate whether the affected permanent object may still be
eligible for Fail-safe recovery.

## 57.31 First Response When Time Travel Has Expired

Capture the database, schema, table, incident timestamp, destructive
query ID, user, role, warehouse, expected/current state, retention
policy, and business impact.

## 57.32 Verify Time Travel First

Before requesting Fail-safe recovery, confirm that historical queries,
clones, `UNDROP`, existing recovery copies, downstream copies, source
replay, and other customer-controlled recovery options are unavailable
or unsuitable.

## 57.33 Do Not Wait During a Recovery Incident

If Time Travel is unavailable and critical data is affected, escalate
promptly because the recovery opportunity is finite.

## 57.34 Contact Snowflake Support

Provide account/region information, affected objects, approximate
incident time, query ID, data-loss type, retention, business impact,
requested recovery point, severity, and contacts.

## 57.35 Example Support Request

Include a concise description of the affected production object,
incident timestamp, destructive query ID, requested recovery point,
business impact, actions already taken, and request for Fail-safe
recovery evaluation.

## 57.36 Do Not Promise Fail-safe Recovery

Communicate that Time Travel is unavailable and Snowflake is being
engaged to determine whether Fail-safe recovery is possible. Do not
promise recovery before confirmation.

## 57.37 Fail-safe Recovery Time

Fail-safe recovery is not equivalent to an immediate `UNDROP`,
historical query, or clone. Support involvement means recovery timing
should not be assumed.

## 57.38 Application Continuity During Fail-safe Recovery

Evaluate whether applications can operate without the affected data,
whether reads can use another dataset, whether writes are safe, whether
pipelines should stop, and whether source replay or temporary recovery
datasets are possible.

## 57.39 Preserve Current Production State

Where appropriate, preserve the current state before reconciliation:

``` sql
CREATE TABLE CUSTOMER_CURRENT_INC12345
CLONE CUSTOMER;
```

## 57.40 Why Current-State Preservation Matters

Historical recovery may predate legitimate post-incident changes. The
objective is to reconcile recovered historical data with valid current
changes, not blindly replace production.

## 57.41 Reconciliation After Fail-safe Recovery

Compare recovered and current datasets, identify incident-specific
differences, and restore only the required data using business keys and
application logic.

## 57.42 Validate Recovered Data

Validate the object, recovery point, row count, business keys, critical
records, schema, data types, null patterns, duplicate risk, and
application expectations.

## 57.43 Fail-safe Recovery Runbook

1.  Detect the data-loss incident.
2.  Stop the destructive process.
3.  Identify affected objects.
4.  Capture query IDs and timestamps.
5.  Attempt Time Travel recovery.
6.  Determine whether `UNDROP` applies.
7.  Check existing recovery copies.
8.  Evaluate source-system replay.
9.  Confirm Time Travel is unavailable.
10. Preserve current production state.
11. Open a Snowflake Support case.
12. Provide exact recovery details.
13. Establish application continuity.
14. Track recovery status.
15. Receive and evaluate recovered data.
16. Validate the recovery point.
17. Compare recovered versus current data.
18. Design selective reconciliation.
19. Restore production.
20. Validate the application.
21. Resume pipelines.
22. Monitor.
23. Complete RCA.
24. Review retention policy.

## 57.44 Fail-safe Incident Checklist

Validate that the faulty workload is stopped, affected objects/query
IDs/timestamps are captured, Time Travel and alternate recovery paths
are evaluated, current state is preserved, Support is engaged,
application continuity is addressed, recovered data is validated,
reconciliation is complete, and RCA is initiated.

## 57.45 Fail-safe Troubleshooting Decision Tree

Start with Time Travel. If unavailable, determine object type and
possible Fail-safe eligibility. If Fail-safe may apply, engage Support
promptly; otherwise evaluate alternate recovery sources.

## 57.46 Fail-safe and RPO

Fail-safe should not define the normal Recovery Point Objective. Use
customer-controlled mechanisms such as Time Travel, replication, source
replay, pipelines, and other designed recovery methods.

## 57.47 Fail-safe and RTO

Fail-safe should not be the primary mechanism for a strict Recovery Time
Objective because customer SQL cannot directly initiate recovery and
Snowflake Support involvement is required.

## 57.48 Fail-safe Is Not Disaster Recovery

Disaster recovery addresses broader
region/account/application/network/identity failures. Fail-safe
addresses exceptional historical data recovery.

## 57.49 Fail-safe Is Not Replication

Fail-safe provides historical recovery protection. Replication creates
recovery copies in another target. They solve different problems.

## 57.50 Fail-safe Is Not High Availability

High availability maintains service during failures. Fail-safe provides
exceptional historical data recovery.

## 57.51 Recovery Defense in Depth

A mature architecture combines application controls, transaction safety,
Time Travel, recovery clones, replication/DR, and Fail-safe.

## 57.52 Preventing the Need for Fail-safe

Improve incident detection, data-quality monitoring, pipeline alerts,
retention policies, change management, destructive SQL controls,
recovery drills, and query auditing.

## 57.53 Alert on Large Data Changes

Monitor mass DELETE, large UPDATE, unexpected MERGE, TRUNCATE, DROP,
CREATE OR REPLACE, and abnormal row-count changes so incidents remain
within the Time Travel window.

## 57.54 Destructive Change Controls

Use restricted DML/DROP privileges, peer-reviewed deployments, change
windows, validation, pipeline safeguards, row-count sanity checks, and
dry-run validation.

## 57.55 Example Pipeline Safety Check

If a pipeline expects fewer than five million deletions but is about to
delete hundreds of millions, stop the operation and require
investigation.

## 57.56 Recovery Detection SLA

Define how quickly critical data-loss incidents must be detected.
Detection objectives should provide substantial margin inside the
configured Time Travel window.

## 57.57 Fail-safe Storage Optimization

Investigate unnecessary churn, full reloads, excessive updates,
DELETE/INSERT cycles, poor CDC design, table replacement, and clone
lifecycle before weakening recovery protection.

## 57.58 Full Reload vs. Incremental Processing

Full reloads can create greater historical churn. Incremental processing
changes only affected data and may reduce historical storage, depending
on workload design.

## 57.59 Monitor Storage Trend

Track whether Fail-safe storage is increasing, which tables are
responsible, whether recent bulk operations explain the trend, and
whether storage declines according to lifecycle expectations.

## 57.60 Fail-safe Cost Review

Monthly reviews should cover top Fail-safe consumers, storage trends,
large DML operations, full reloads, object classification, recovery
requirements, Time Travel configuration, clone-retained storage, and
anomalies.

## 57.61 Production Object Classification

Classify objects by criticality and rebuild capability. Critical
authoritative data generally requires stronger durable recovery
protection than rebuildable staging data.

## 57.62 Fail-safe Governance Standard

Document which data requires permanent storage, which may be transient,
the source of truth, rebuild time, RPO/RTO, and available recovery
mechanisms.

## 57.63 Fail-safe Recovery Testing

Test whether operators can identify expired Time Travel, gather
evidence, engage Snowflake Support, preserve current state, and safely
reconcile recovered data.

## 57.64 Fail-safe Escalation Information Template

Maintain incident ID, Snowflake account/region, database/schema/object,
object type, incident timestamp/time zone, query ID,
user/role/warehouse, retention, current state, desired recovery point,
business impact, source replay availability, preserved state, Support
case, incident commander, and SRE/DBRE owner.

## 57.65 Common Fail-safe Mistakes

Avoid treating Fail-safe as backup, assuming recovery is guaranteed or
immediate, waiting too long to escalate, using transient tables for
critical data without review, reducing Time Travel because Fail-safe
exists, ignoring historical storage, blindly replacing production,
ignoring post-incident writes, failing to preserve current state/query
IDs, confusing Fail-safe with DR/HA, or failing to test escalation.

## 57.66 Production Fail-safe Standards

Critical data should use appropriate durable object types. Time Travel
remains the primary historical recovery mechanism. Fail-safe is last
resort, not normal RPO/RTO. Monitor destructive changes, document
Support escalation, preserve current state, validate recovered data,
retain legitimate post-incident writes, review Fail-safe storage, and
perform RCA.

## 57.67 SRE/DBRE Fail-safe Checklist

Understand Time Travel and Fail-safe, identify critical
permanent/transient objects, review Fail-safe storage and high-churn
tables, monitor destructive operations, maintain Support escalation
procedures, capture query IDs, preserve current state,
validate/reconcile recovered data, validate applications, review
retention after incidents, and test escalation.

## 57.68 Operational Decision Tree

For data loss: stop the destructive process → test Time Travel → if
unavailable, evaluate object type and Fail-safe eligibility → engage
Support if appropriate → preserve current state → validate recovered
data → reconcile → validate production → complete RCA and prevention.

## 57.69 Production Scenario

If a permanent `PROD_DB.EMPI.PATIENT` table with seven-day Time Travel
suffers a large accidental delete discovered on day nine, disable the
faulty pipeline, preserve current state, collect incident evidence,
evaluate alternate recovery, promptly engage Snowflake Support, validate
any recovered historical data, reconcile it with valid post-incident
writes, restore selectively, validate the application, and complete RCA.

The RCA should focus on why detection exceeded the Time Travel window,
why destructive changes were not alerted, whether retention was
appropriate, and what preventive controls are needed.

## 57.70 Fail-safe Maturity Model

Maturity progresses from misunderstanding Fail-safe as backup →
documented understanding → governed object/retention policies →
operational escalation/reconciliation → resilient early detection where
Fail-safe is rarely required.

## 57.71 Key Takeaways

1.  Fail-safe is a Snowflake-managed last-resort recovery mechanism.
2.  It follows the applicable Time Travel period.
3.  Eligible permanent data receives a 7-day Snowflake-managed Fail-safe
    period.
4.  Customers cannot directly query Fail-safe data.
5.  `AT`, `BEFORE`, historical clones, and `UNDROP` are Time Travel
    capabilities.
6.  Fail-safe recovery requires Snowflake Support.
7.  Fail-safe should not be the normal backup, RPO, or strict-RTO
    strategy.
8.  Transient and temporary tables do not provide Fail-safe protection.
9.  Object type is a recovery architecture decision.
10. Fail-safe historical data contributes to storage consumption.
11. High churn can increase historical storage.
12. Large DELETE/MERGE/full-refresh workloads should be investigated
    when historical storage grows.
13. Preserve current state before reconciliation.
14. Validate recovered historical data.
15. Preserve legitimate post-incident writes.
16. Escalate critical incidents promptly.
17. Monitor destructive operations so incidents remain within Time
    Travel.
18. Maintain Snowflake Support escalation procedures.
19. Fail-safe is not HA, DR, or replication.
20. Mature systems detect and recover incidents before Fail-safe is
    needed.

## 57.72 Chapter Completion Checklist

After completing this chapter, you should be able to explain Fail-safe,
distinguish it from Time Travel, understand its recovery timeline and
object-type implications, analyze Fail-safe storage, investigate
high-churn consumers, determine when escalation may be required,
preserve current state, gather Support evidence, communicate recovery
uncertainty, validate and reconcile recovered data, execute the recovery
runbook, relate Fail-safe to RPO/RTO/DR/HA, establish governance, and
test the escalation process.

**Chapter 57 --- Snowflake Fail-safe: Complete**
