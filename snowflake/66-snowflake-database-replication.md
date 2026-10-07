# Chapter 66 --- Snowflake Database Replication

## 66.1 Overview

Snowflake Database Replication allows supported database objects and
data to be replicated from a primary database to a secondary database in
another Snowflake account or region, subject to Snowflake's current
replication capabilities and edition requirements.

Database replication is primarily used for disaster recovery,
cross-region data availability, business continuity, readiness for
regional failures, controlled copies in another Snowflake account, and
migration scenarios.

``` text
PRIMARY ACCOUNT / REGION
        |
        v
   PRIMARY DATABASE
        |
        | Replication
        v
SECONDARY ACCOUNT / REGION
        |
        v
  SECONDARY DATABASE
```

Replication is different from Secure Data Sharing.

## 66.2 Replication vs. Sharing

Secure Data Sharing provides consumer access to provider-controlled
data. Database Replication creates and maintains a secondary database
copy according to the configured replication process.

## 66.3 Replication Is Not Backup

Do not treat replication as your only recovery mechanism. Logical
corruption such as an accidental DELETE can eventually propagate to the
secondary.

Replication does not replace Time Travel, Zero-Copy Cloning, recovery
runbooks, source replay, Fail-safe where applicable, or a tested
backup/recovery strategy.

## 66.4 Primary Database

The primary database is the authoritative database from which
replication originates, for example `PROD_DB`.

## 66.5 Secondary Database

The secondary database is maintained from the primary through
replication, for example `PROD_DB_SECONDARY`. Its allowed operations
depend on its current Snowflake replication/failover state.

## 66.6 Replication Direction

Basic database replication follows PRIMARY → SECONDARY. Do not assume
arbitrary active-active writes. Clearly understand primary/secondary
ownership.

## 66.7 Common Replication Topologies

Common topologies include same organization/different region,
cross-cloud, and cross-account. Exact supported combinations depend on
current Snowflake capabilities.

# Recovery Objectives

## 66.8 Define RPO

Recovery Point Objective answers: how much data loss can the business
tolerate?

Example: `RPO = 15 minutes`.

## 66.9 Define RTO

Recovery Time Objective answers: how long can the service remain
unavailable?

Example: `RTO = 60 minutes`.

## 66.10 Replication Frequency Must Support RPO

A four-hour replication schedule cannot satisfy a 15-minute RPO.

## 66.11 RPO Is More Than Schedule

Actual recovery point depends on replication schedule, duration,
failures, retry delay, replication lag, and operational response. Do not
equate schedule directly with guaranteed RPO.

# Planning

## 66.12 Database Replication Readiness

Validate business requirements, RPO/RTO, primary/secondary accounts and
regions, cloud topology, Snowflake edition/capability, database
inventory, supported objects, cost, security, ownership, and testing.

## 66.13 Inventory Database

``` sql
SHOW DATABASES LIKE 'PROD_DB';
```

Inventory relevant schemas and objects.

## 66.14 Object Inventory

Document schemas, tables, views, secure views, materialized views,
sequences, stages, pipes, tasks, streams, policies, functions,
procedures, and other dependencies.

## 66.15 Validate Supported Objects

Snowflake capabilities evolve. Validate current documentation for
supported/unsupported objects, account-level dependencies, region/cloud
restrictions, edition requirements, and limitations.

## 66.16 External Dependencies

Identify external stages, cloud storage, secrets, network policies,
external functions, integrations, notification services, Kafka, ETL
systems, and other dependencies. Database replication alone does not
make these DR-ready.

# Account and Region Preparation

## 66.17 Verify Source Account

``` sql
SELECT
    CURRENT_ORGANIZATION_NAME(),
    CURRENT_ACCOUNT_NAME(),
    CURRENT_REGION();
```

Use currently supported context functions in your environment.

## 66.18 Verify Target Account

Run equivalent checks in the target account. Never create DR
infrastructure in an assumed account.

## 66.19 Region Selection

Choose the secondary region based on failure domain, business
requirements, residency, latency, cloud strategy, cost, and regulatory
requirements.

## 66.20 Avoid Same Failure Domain

If regional DR is required, placing both copies in the same region does
not satisfy that objective.

# Enable Replication

## 66.21 Replication Authorization

Cross-account or cross-region replication requires appropriate
authorization/configuration. Validate current Snowflake prerequisites
and syntax before execution.

## 66.22 Replication Pattern

Source Account → Enable Replication → Authorize Target → Target Account
→ Create Secondary.

## 66.23 Create Secondary Database

Conceptual pattern:

``` sql
CREATE DATABASE PROD_DB_SECONDARY
AS REPLICA OF
<ORGANIZATION>.<SOURCE_ACCOUNT>.PROD_DB;
```

Validate exact syntax and naming requirements against current Snowflake
documentation.

## 66.24 Initial Replication

Plan initial replication based on database size, object count, transfer
volume, cross-region/cross-cloud transfer, duration, and cost.

## 66.25 Validate Secondary

``` sql
SHOW DATABASES LIKE 'PROD_DB_SECONDARY';

SHOW SCHEMAS IN DATABASE PROD_DB_SECONDARY;
```

# Refresh

## 66.26 Secondary Refresh

Conceptual pattern:

``` sql
ALTER DATABASE PROD_DB_SECONDARY REFRESH;
```

Validate exact syntax/current supported behavior.

## 66.27 Manual Refresh

Useful for initial validation, DR testing, troubleshooting, controlled
migrations, and operational verification. It should not be the only
production mechanism when strict RPO requires frequent replication.

## 66.28 Scheduled Refresh

Production DR normally requires automated replication according to RPO
using Snowflake-supported automation for the chosen architecture.

## 66.29 Refresh Frequency

Choose frequency from business requirements and measure actual
replication lag rather than treating schedule as a guarantee.

# Monitoring

## 66.30 Replication Monitoring

Monitor last successful/attempted refresh, refresh duration, replication
lag, bytes transferred, failure status/error, and secondary state.

## 66.31 Replication History

Use current Snowflake replication history/account usage/information
schema interfaces. Track start/end time, status, bytes, objects, and
errors.

## 66.32 Replication Lag

Conceptually:

`Replication Lag = Current Time - Latest Successfully Replicated Data Point`

This is one of the most important DR metrics.

## 66.33 Lag Threshold

Example for a 15-minute RPO: warning near 10 minutes and critical at 15
minutes. Actual thresholds must match business requirements.

## 66.34 Failed Refresh

A failed refresh should alert immediately. Do not wait for a DR test to
discover persistent failures.

## 66.35 Repeated Failures

Escalate when repeated failures threaten the RPO. Incident severity
should reflect business impact and remaining recovery margin.

# Data Validation

## 66.36 Validate Primary Row Count

``` sql
SELECT COUNT(*)
FROM PROD_DB.CUSTOMER.CUSTOMER_PROFILE;
```

## 66.37 Validate Secondary Row Count

``` sql
SELECT COUNT(*)
FROM PROD_DB_SECONDARY.CUSTOMER.CUSTOMER_PROFILE;
```

Compare after accounting for the known replication point.

## 66.38 Validate Freshness

Primary:

``` sql
SELECT MAX(UPDATED_AT)
FROM PROD_DB.CUSTOMER.CUSTOMER_PROFILE;
```

Secondary:

``` sql
SELECT MAX(UPDATED_AT)
FROM PROD_DB_SECONDARY.CUSTOMER.CUSTOMER_PROFILE;
```

## 66.39 Validate Representative Records

Check important business records on both sides; do not rely only on
object existence.

## 66.40 Validate Schema

Compare required schemas, tables, columns, data types, views, policies,
and other supported replicated objects.

# Security

## 66.41 DR Security Must Match Production Requirements

Validate authentication, RBAC, network controls, secrets, integrations,
classification, audit logging, and administrative access.

## 66.42 Replicated Data Classification

Replication does not change classification. PHI in the primary remains
PHI in the secondary.

## 66.43 Data Residency

Validate regulatory restrictions, contracts, residency requirements,
security requirements, and legal approval before cross-region/cloud
replication.

## 66.44 Least Privilege

Only authorized administrators should control replication and DR
promotion.

# Cost

## 66.45 Replication Has Cost

Potential costs include secondary storage, replication transfer,
cross-region/cross-cloud transfer, replication services/compute where
applicable, DR testing, and secondary workloads.

## 66.46 Initial vs. Incremental Cost

Initial replication can be substantially larger than later incremental
refreshes. Actual behavior depends on architecture and change volume.

## 66.47 High-Churn Databases

Frequent INSERT, UPDATE, DELETE, and MERGE activity can generate more
replication work than mostly static databases.

## 66.48 Cost Monitoring

Monitor storage growth, transfer volume, frequency, change rate,
secondary query usage, and DR-test usage.

# Performance

## 66.49 Replication and Production Workload

Observe replication duration/lag alongside source change volume,
ingestion, and large batch jobs.

## 66.50 Large Batch Ingestion

A large batch can temporarily increase replication duration and lag.
Plan large loads with DR objectives in mind.

## 66.51 RPO During Large Loads

Do not assume normal replication behavior during abnormal ingestion.
Monitor actual lag.

# Logical Corruption

## 66.52 Replication Can Propagate Bad Changes

An accidental destructive statement can eventually be replicated to the
secondary.

## 66.53 Stop the Cause First

Stop the destructive process, assess primary and secondary state, and do
not blindly refresh the secondary.

## 66.54 Preserve Recovery Options

If the secondary has not received corruption, preserve it as potential
evidence/recovery state depending on architecture and supported
operations.

## 66.55 Use Time Travel for Logical Recovery

Logical corruption is generally better addressed first through Time
Travel, historical clones, UNDROP, selective restoration, or source
replay rather than treating DR replication as the primary
logical-recovery mechanism.

# Disaster Recovery

## 66.56 Database Replication and DR

Replication provides the data-copy foundation for DR, but complete DR
also requires compute, users, roles, integrations, network,
applications, endpoints, secrets, pipelines, and operational runbooks.

## 66.57 Database-Level Recovery

A database replica may be sufficient when only database availability is
required and surrounding dependencies already exist.

## 66.58 Account-Level DR

If broad account objects/services must recover, database replication
alone may be insufficient. This leads into Chapter 67 --- Snowflake
Account Replication.

# Promotion

## 66.59 Promotion Concept

During a supported DR event, a secondary may be promoted/failover
activated according to the configured architecture.

## 66.60 Do Not Promote Casually

Promotion affects data ownership, write direction, application routing,
recovery strategy, and failback. Use an approved runbook.

## 66.61 Pre-Promotion Checks

Confirm incident declaration, primary condition, DR authority approval,
replication status, estimated data loss, secondary/dependency readiness,
application readiness, and communication.

## 66.62 Data Loss Assessment

Determine last known primary point, last successful replication, lag,
and estimated missing transactions before promotion.

# DR Testing

## 66.63 Replication Without Testing Is Not DR

Test data, queries, applications, authentication, integrations,
pipelines, and operational procedures.

## 66.64 DR Test Frequency

Choose frequency based on business criticality, such as quarterly,
semiannual, or annual.

## 66.65 DR Test Should Measure

Measure actual RPO, actual RTO, replication lag, promotion duration,
application recovery, data validation, and operational gaps.

## 66.66 Successful DR Test

A test is complete only when the defined business service can operate
within approved objectives.

# Troubleshooting

## 66.67 Secondary Creation Fails

Check account identifiers, organization, region/cloud support, edition,
authorization, privileges, and database eligibility.

## 66.68 Refresh Fails

Check configuration, source availability, secondary state, privileges,
object compatibility, platform errors, and recent changes.

## 66.69 Replication Lag Increasing

Investigate large ingestion, high change rate, large DELETE/MERGE
operations, failures, network/region issues, platform incidents, or
changed frequency.

## 66.70 Secondary Missing Object

Check whether the object is supported, existed before refresh, belongs
to the replicated database, has external dependencies, or requires
account-level replication.

## 66.71 Row Counts Differ

Check replication point, active source writes, refresh completion,
transaction timing, and freshness. Compare data at a consistent point.

## 66.72 Secondary Data Stale

Check last refresh, refresh status, lag, automation, failed schedules,
and source update timestamps.

## 66.73 Replication Cost Spike

Investigate large loads, high update/delete activity, replication
frequency, new large tables, cross-region/cloud transfer, and DR
testing.

# Monitoring Standards

## 66.74 Minimum Dashboard

Track primary/secondary databases and regions, last successful
replication, duration, lag, status, RPO target/compliance, database
size, change volume, and failure count.

## 66.75 Alert Levels

INFO: successful replication. WARNING: lag approaching RPO. CRITICAL:
lag exceeds RPO or repeated failures.

## 66.76 Operational Ownership

Every replicated database should have business, database, DR, on-call,
and security ownership.

# Change Management

## 66.77 Schema Changes

Consider replication implications before large table creation, reloads,
DELETE/MERGE operations, object replacement, or new dependencies.

## 66.78 Large Rebuild

A multi-terabyte rebuild can affect change volume, replication duration,
lag, cost, and RPO.

## 66.79 Replication Configuration Changes

Treat primary/secondary relationship, schedule, target region/account,
automation, and DR ownership changes as production changes.

# Operational Runbooks

## 66.80 Database Replication Setup Runbook

1.  Document business requirement.
2.  Define RPO.
3.  Define RTO.
4.  Identify source account.
5.  Identify target account.
6.  Identify source region/cloud.
7.  Identify target region/cloud.
8.  Validate Snowflake capability.
9.  Validate edition.
10. Inventory database.
11. Validate supported objects.
12. Identify external dependencies.
13. Complete security review.
14. Complete residency/compliance review.
15. Estimate cost.
16. Configure replication authorization.
17. Create secondary database.
18. Run initial replication.
19. Validate objects.
20. Validate row counts.
21. Validate freshness.
22. Configure refresh automation.
23. Configure monitoring.
24. Configure alerts.
25. Document DR procedure.
26. Execute DR test.

## 66.81 Replication Failure Runbook

1.  Detect failure.
2.  Confirm affected database.
3.  Capture error.
4.  Determine last successful replication.
5.  Calculate current lag.
6.  Compare lag with RPO.
7.  Check source health.
8.  Check secondary state.
9.  Check recent changes.
10. Correct issue.
11. Retry using supported process.
12. Validate refresh.
13. Validate data.
14. Monitor next cycles.
15. Escalate if RPO breached.
16. Document incident.

## 66.82 RPO Breach Runbook

1.  Declare RPO risk/breach.
2.  Identify affected service.
3.  Determine last recoverable point.
4.  Calculate data-loss exposure.
5.  Notify incident management.
6.  Notify application/business owners.
7.  Restore replication.
8.  Validate secondary.
9.  Update recovery assessment.
10. Continue monitoring.
11. Complete RCA.

## 66.83 Logical Corruption Runbook

1.  Stop destructive process.
2.  Record incident timestamp.
3.  Capture destructive query/job.
4.  Check primary.
5.  Check replication status.
6.  Determine whether corruption reached secondary.
7.  Do not blindly refresh secondary.
8.  Preserve useful recovery state.
9.  Evaluate Time Travel.
10. Create historical clone where appropriate.
11. Recover/reconcile data.
12. Validate.
13. Resume replication safely.
14. Monitor.
15. Complete RCA.

# Production Scenario

## 66.84 Scenario

Production database: `PROD_DB`.

Primary: AWS us-east.

Secondary: AWS us-west.

Business requirements: RPO 30 minutes; RTO 2 hours.

## 66.85 Architecture

Applications → AWS us-east → PROD_DB → Replication → AWS us-west →
PROD_DB_SECONDARY.

## 66.86 Validation

Primary:

``` sql
SELECT
    COUNT(*) AS ROW_COUNT,
    MAX(UPDATED_AT) AS LAST_UPDATE
FROM PROD_DB.EMPI.PATIENT;
```

Secondary:

``` sql
SELECT
    COUNT(*) AS ROW_COUNT,
    MAX(UPDATED_AT) AS LAST_UPDATE
FROM PROD_DB_SECONDARY.EMPI.PATIENT;
```

## 66.87 Monitoring Requirement

Alert on replication failure or when lag approaches the 30-minute RPO.

## 66.88 Large Batch Scenario

For a nightly batch modifying 1.5 TB, monitor replication duration, lag,
transfer volume, cost, and RPO compliance.

## 66.89 Accidental Delete Scenario

If an accidental DELETE is discovered shortly after execution, stop the
bad process, check last successful replication, determine whether the
secondary received the deletion, preserve recovery options, and use Time
Travel/reconciliation as appropriate before forcing another refresh.

# Production Standards

## 66.90 Common Mistakes

Avoid calling replication a backup, undefined RPO/RTO, schedules
misaligned with RPO, missing lag monitoring/alerts, missing object
inventory, assuming every object replicates, ignoring external
dependencies/residency/cost, no DR tests, assuming secondary existence
proves recoverability, blindly refreshing after corruption, promotion
without data-loss assessment, missing failback plans, and missing
owners/runbooks.

## 66.91 Production Standards

Every replicated database should have documented RPO/RTO, architecture
aligned with business requirements, documented topology, validated
supported objects/dependencies, production-equivalent security,
residency review, lag monitoring and RPO alerts, visible failures,
replication impact review for large changes, safe logical-corruption
procedures, preserved secondary state during investigations, regular DR
tests, measured actual RPO/RTO, authorized promotion, data-loss
assessment, documented failback, cost monitoring, and assigned
operational ownership.

## 66.92 SRE/DBRE Database Replication Checklist

Validate business requirement, RPO/RTO, primary/secondary accounts and
regions, cloud topology, edition/capability, database inventory,
supported objects, external dependencies, security/residency/compliance,
cost, replication configuration, secondary creation, initial refresh,
schemas/objects/counts/freshness, automation, lag monitoring, alerts,
RPO compliance, failure/RPO/corruption runbooks, promotion/failback, DR
testing, measured RPO/RTO, and operational owners.

## 66.93 Operational Quick Reference

Business requirement → RPO/RTO → target region/account → capability
validation → inventory → replication configuration → secondary → initial
refresh → data validation → automated refresh → lag monitoring → RPO
alerts → DR test → measure actual RPO/RTO.

## 66.94 Key Takeaways

1.  Database replication maintains a secondary copy of a Snowflake
    database.
2.  Replication and Secure Data Sharing solve different problems.
3.  Replication is not a backup.
4.  Logical corruption can propagate.
5.  Define RPO before choosing frequency.
6.  Define RTO before designing DR.
7.  Actual RPO depends on success and lag.
8.  Inventory objects before replication.
9.  Validate supported objects against current capabilities.
10. Inventory external dependencies.
11. Verify source/target accounts.
12. Verify source/target regions/clouds.
13. Review data residency.
14. Initial replication may be larger than incremental refreshes.
15. Automate refresh according to RPO.
16. Monitor last successful replication.
17. Monitor duration.
18. Monitor lag.
19. Alert before RPO breach.
20. Validate counts and freshness.
21. Apply production-equivalent security to DR data.
22. Monitor cost.
23. Large ingestion can increase lag.
24. Do not blindly refresh during logical corruption.
25. Preserve secondary state when it has recovery value.
26. Prefer Time Travel/reconciliation for logical recovery where
    applicable.
27. Database replication alone is not complete account-level DR.
28. Promotion requires an approved runbook.
29. DR tests must measure actual RPO/RTO.
30. An untested secondary is not sufficient evidence of recoverability.

## 66.95 Chapter Completion Checklist

After completing this chapter, you should be able to explain Database
Replication; compare replication with sharing; explain why replication
is not backup; define primary/secondary databases, RPO, and RTO; align
frequency with RPO; inventory objects/dependencies; validate
accounts/regions/clouds; understand secondary creation and refresh;
design automation; monitor history/lag and alerts; validate data; apply
security/residency controls; analyze cost/high-churn workloads; handle
logical corruption safely; understand replication's DR role; perform
pre-promotion/data-loss checks; design DR testing; troubleshoot
failures; respond to RPO breaches; execute setup/failure/corruption
runbooks; and apply SRE/DBRE production standards.

**Chapter 66 --- Snowflake Database Replication: Complete**
