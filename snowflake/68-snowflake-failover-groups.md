# Chapter 68 --- Snowflake Failover Groups

## 68.1 Overview

Snowflake Failover Groups provide a mechanism for replicating supported
Snowflake objects between accounts and enabling controlled failover for
disaster recovery and business continuity.

``` text
PRIMARY ACCOUNT / REGION
        |
        v
PRIMARY FAILOVER GROUP
        |
        | Replication
        v
SECONDARY ACCOUNT / REGION
        |
        v
SECONDARY FAILOVER GROUP
```

A failover group builds on replication by supporting transition of
ownership from a primary group to a secondary group during a DR event.

## 68.2 Why Failover Groups Matter

Replication answers how to maintain a secondary copy. Failover answers
how to make that secondary environment authoritative when the primary
fails.

## 68.3 Replication Group vs. Failover Group

A replication group focuses primarily on replication. A failover group
supports replication plus controlled failover/failback capabilities for
supported objects. Always validate current Snowflake behavior and object
support.

## 68.4 Failover Is Not Backup

Logical corruption such as accidental DELETE can replicate to the
secondary. Use Time Travel, clones, UNDROP, source replay, and recovery
procedures for logical recovery where appropriate.

## 68.5 Failover Groups Are Part of DR

Failover groups do not automatically solve DNS, application routing,
external secrets, cloud IAM, Kafka routing, ETL configuration, private
connectivity, external storage, identity-provider availability,
application state, or operational decision making.

# Architecture

## 68.6 Basic Architecture

Normal operation: Application → Primary Account → Primary Failover Group
→ replication → Secondary Failover Group → Secondary Account.

During failure: Primary unavailable → promote Secondary Failover Group →
New Primary → Application.

## 68.7 Primary Failover Group

The primary group defines supported objects participating in replication
and failover.

## 68.8 Secondary Failover Group

The secondary group receives replicated state and normally represents
the passive DR side before promotion.

## 68.9 Promotion

Promotion changes the failover relationship so the secondary becomes the
new primary according to Snowflake's supported process. This is
production-impacting.

# Recovery Objectives

## 68.10 Define RPO

Example: `RPO = 30 minutes`.

## 68.11 Define RTO

Example: `RTO = 2 hours`. Include detection, decision, promotion,
authentication, compute, integrations, pipelines, application routing,
and validation.

## 68.12 Failover Groups Do Not Guarantee RPO

RPO depends on frequency, refresh duration, failures, lag, change
volume, and response. Monitor actual lag.

## 68.13 Failover Groups Do Not Guarantee RTO

Fast promotion does not mean the application has recovered. Measure
service-level RTO.

# Planning

## 68.14 Failover Group Readiness

Validate business service/owner, RPO/RTO, primary/secondary accounts and
regions/clouds, Snowflake capability, supported objects, DR scope,
external dependencies, security/residency, cost, failover authority,
failback process, and DR test plan.

## 68.15 Define Service Boundary

Prefer logical service boundaries such as `PATIENT360_DR_GROUP` rather
than one giant everything-in-production group where separation is
appropriate.

## 68.16 Inventory Required Objects

Identify databases, roles, users, warehouses, resource monitors,
integrations, network/security objects, and other supported objects
needed for recovery.

## 68.17 Identify Non-Replicated Dependencies

Document AWS IAM, Azure identities, S3, Kafka, Kubernetes, Secrets
Manager, DNS, PrivateLink, external APIs, and other separately recovered
dependencies.

# Verify Environment

## 68.18 Verify Primary

``` sql
SELECT
    CURRENT_ORGANIZATION_NAME(),
    CURRENT_ACCOUNT_NAME(),
    CURRENT_REGION();
```

## 68.19 Verify Secondary

Run equivalent checks in the secondary account. Never configure failover
based on assumed context.

## 68.20 Validate Failure-Domain Separation

The secondary must be outside the targeted failure domain for the
required DR objective.

# Create Failover Group

## 68.21 Source-Side Pattern

Primary Account → Create Failover Group → Select Object Types → Select
Databases/Objects → Authorize Secondary Account.

## 68.22 Conceptual SQL

``` sql
CREATE FAILOVER GROUP PROD_FAILOVER_GROUP
    OBJECT_TYPES = DATABASES, ROLES, USERS, WAREHOUSES
    ALLOWED_DATABASES = PROD_DB
    ALLOWED_ACCOUNTS = <SECONDARY_ACCOUNT>
    REPLICATION_SCHEDULE = '15 MINUTE';
```

This is an architectural example. Validate current Snowflake syntax,
object support, scheduling syntax, privileges, edition requirements, and
topology before production execution.

## 68.23 Object Scope

Include only objects required by the service.

## 68.24 Avoid Excessive Scope

Unnecessary scope increases replication volume, complexity, cost,
validation effort, testing scope, and blast radius.

# Secondary Failover Group

## 68.25 Create Secondary

Create the corresponding secondary failover group using Snowflake's
supported process.

## 68.26 Initial Refresh

Initial refresh establishes secondary state and may take longer than
later incremental refreshes.

## 68.27 Initial Refresh Planning

Consider database size, object count, change rate,
cross-region/cross-cloud transfer, service limits, and cost.

## 68.28 Initial Validation

Validate databases, schemas, tables, data, roles, users, warehouses,
integrations, and authentication according to scope.

# Replication Schedule

## 68.29 Replication Schedule

Configure refresh frequency according to RPO and supported Snowflake
scheduling capabilities.

## 68.30 Example

For an RPO of 30 minutes, replication may need to run more frequently to
preserve operational margin.

## 68.31 Operational Margin

Example: Business RPO 30 min; target lag \<20 min; warning 20 min;
critical 30 min.

## 68.32 Measure Actual Lag

Monitor last successful refresh, current time, data freshness, and
refresh duration instead of relying only on schedule.

# Monitoring

## 68.33 Failover Group Monitoring

Track group, accounts/regions, last successful/attempted refresh,
duration, lag, status, failures, RPO target, and compliance.

## 68.34 Refresh Failure

Alert on failure and escalate repeated failures before RPO breach.

## 68.35 Lag Trend

Monitor stable, increasing, or recovering lag.

## 68.36 Data Freshness

``` sql
SELECT MAX(UPDATED_AT)
FROM PROD_DB.EMPI.PATIENT;
```

Compare primary and secondary.

## 68.37 Object Validation

Periodically validate required account objects and configuration.

# Security

## 68.38 Security Must Survive Failover

Validate authentication, RBAC, network controls, MFA, SSO, service
accounts, key-pair authentication, integrations, and auditing.

## 68.39 DR Account Is Production

Treat passive DR as production infrastructure because it may contain
production data and identities.

## 68.40 Data Classification

Replication does not change classification. PHI remains PHI, PII remains
PII, and confidential data remains confidential.

## 68.41 Administrative Access

Ensure authorized administrators can access the secondary during
incidents.

## 68.42 Break-Glass Access

Where policy permits, emergency access should be restricted, audited,
rotated, tested, and documented.

# Authentication Validation

## 68.43 SSO

Test SSO against the DR account.

## 68.44 Service Accounts

Validate account identifier, authentication, key pair/OAuth, role,
warehouse, and network access.

## 68.45 External Identity Provider

The identity provider itself must be part of service-level DR planning.

# Warehouse Readiness

## 68.46 Warehouse Availability

``` sql
SHOW WAREHOUSES;
```

Verify required warehouses.

## 68.47 Warehouse Capacity

DR warehouses must support expected failover workload.

## 68.48 Scaling During Failover

A passive-low-capacity model can reduce cost, but scaling time must fit
RTO.

# Integration Readiness

## 68.49 Storage Integrations

Validate Snowflake → Storage Integration → Cloud IAM → External Storage
end to end.

## 68.50 Notification Integrations

Verify event destinations from the secondary.

## 68.51 API Integrations

Test API gateway, authentication, cloud permissions, and network path.

## 68.52 External Access

Validate required outbound connectivity; object replication does not
prove connectivity.

# Ingestion

## 68.53 Ingestion Must Be Redirected

External ingestion such as Kafka requires controlled routing from
primary Snowflake to secondary Snowflake during DR.

## 68.54 ETL Systems

Validate Airflow, dbt, Databricks, Glue, ADF, Lambda, Kubernetes
CronJobs, and custom applications.

## 68.55 Avoid Double Ingestion

Prevent sources from writing simultaneously to old and new primaries
unless explicitly safe and controlled.

# Application Routing

## 68.56 Connection Configuration

Applications may require new account identifiers, URLs, secrets,
regions, or authentication configuration.

## 68.57 Abstract Endpoints Where Possible

Reduce manual DR work through controlled configuration, service
discovery, or automation.

## 68.58 Validate Application Connectivity

Application → Authenticate → Role → Warehouse → Database must work end
to end before traffic.

# Split-Brain Prevention

## 68.59 Split Brain

Split brain occurs when both environments behave as independent
primaries and accept writes.

## 68.60 Fence Old Primary

Prevent uncontrolled old-primary writes before/during promotion whenever
possible.

## 68.61 Single Write Authority

Normal: Primary = WRITE; Secondary = PASSIVE. After failover: Old
Primary = FENCED; New Primary = WRITE.

# Pre-Failover Assessment

## 68.62 Confirm Incident

Determine whether the issue is transient, account, regional, cloud,
Snowflake-service, network, or application related. Do not trigger DR
for unrelated application failure.

## 68.63 Estimate Primary Recovery

Compare expected primary recovery time with business RTO.

## 68.64 Determine Replication Point

Capture last successful refresh, last known primary data point, current
lag, and failed refreshes.

## 68.65 Calculate Data-Loss Exposure

Example: last primary data 10:28; last secondary data 10:17; potential
exposure 11 minutes.

## 68.66 Validate Secondary

Check replication, freshness, database health, RBAC, authentication,
warehouses, integrations, and monitoring.

# Promotion

## 68.67 Promotion Is a Controlled Change

Promotion requires explicit incident/DR authorization.

## 68.68 Promotion Concept

Secondary Failover Group → Promote → Primary Failover Group.

## 68.69 Conceptual Promotion SQL

``` sql
ALTER FAILOVER GROUP PROD_FAILOVER_GROUP PRIMARY;
```

Do not use this blindly. Validate exact current syntax and failover
semantics.

## 68.70 Promotion Changes Authority

Update operational documentation immediately after authority changes.

# Post-Promotion Validation

## 68.71 Validate Group State

Verify promoted group role/state through supported Snowflake metadata.

## 68.72 Validate Database

``` sql
SHOW DATABASES;
```

## 68.73 Validate Data

``` sql
SELECT
    COUNT(*) AS ROW_COUNT,
    MAX(UPDATED_AT) AS LAST_UPDATE
FROM PROD_DB.EMPI.PATIENT;
```

## 68.74 Validate Role

``` sql
SHOW ROLES;
```

## 68.75 Validate Users

``` sql
SHOW USERS;
```

## 68.76 Validate Warehouses

``` sql
SHOW WAREHOUSES;
```

## 68.77 Validate Application Identity

Use the actual service identity, not only an administrator.

## 68.78 Validate Ingestion

Confirm new records reach the new primary.

## 68.79 Validate Read/Write

Run controlled, business-safe tests proving expected behavior.

# Failover Flow

## 68.80 Complete Flow

Incident → Assess Primary → Compare with RTO → Declare DR → Check
Replication Point → Calculate Data Loss → Validate Secondary → Fence Old
Primary → Promote Failover Group → Activate/Scale Compute → Validate
Auth → Validate Integrations → Redirect Ingestion → Redirect Application
→ Smoke Test → Business Validation → Monitor.

# Logical Corruption

## 68.81 Do Not Fail Over Blindly

Accidental DELETE/DROP, bad deployment, or wrong data update may already
exist in the secondary.

## 68.82 Check Secondary First

Determine corruption time, last successful refresh, and whether
corruption reached secondary before refresh/promotion.

## 68.83 Preserve Good Secondary State

If the secondary is still clean, do not refresh until recovery strategy
is determined.

## 68.84 Logical Recovery Tools

Evaluate Time Travel, historical clone, UNDROP, source replay, selective
restore, and preserved secondary state.

# Failback

## 68.85 Failback Definition

Failback returns production authority to the recovered original
environment.

## 68.86 Failback Is Not Automatic

A recovered region may contain stale state. Do not simply redirect
applications.

## 68.87 Synchronize First

Synchronize current primary → recovered original account before
failback.

## 68.88 Validate Recovered Environment

Validate lag, data, RBAC, authentication, warehouses, integrations,
ingestion, and applications.

## 68.89 Controlled Failback

Plan → Approve → Fence → Final Sync → Promote → Route → Validate →
Monitor.

# DR Testing

## 68.90 Failover Test

Production-ready failover groups should be tested.

## 68.91 Test Scope

Validate replication, promotion, authentication, RBAC, warehouses,
integrations, ingestion, application routing, monitoring, and failback.

## 68.92 Measure RPO

Determine actual data difference at failover.

## 68.93 Measure RTO

Measure from DR declaration until business service is operational.

## 68.94 Test Failback

A DR test is incomplete if failback is never tested.

## 68.95 Capture Lessons

Document actual RPO/RTO, manual steps, failures, missing automation,
security/capacity issues, cost, and remediation.

# Troubleshooting

## 68.96 Failover Group Creation Fails

Check Snowflake edition, privileges, object types, database eligibility,
account identifiers, allowed accounts, region/cloud support, and
existing replication relationships.

## 68.97 Secondary Creation Fails

Check source authorization, account identifiers, group name,
region/cloud support, privileges, and primary-group state.

## 68.98 Refresh Fails

Check primary availability, secondary state, privileges, unsupported
object changes, recent DDL, platform errors, and configuration.

## 68.99 Replication Lag Increasing

Investigate large loads, high DML, large rebuilds, repeated failures,
region/cloud issues, or schedule changes.

## 68.100 Promotion Fails

Check group/replication state, privileges, account context, existing
primary, Snowflake errors, and topology. Do not repeatedly issue
promotion commands without understanding state.

## 68.101 Application Fails After Promotion

Check account URL, authentication, role, warehouse, database, network
policy, secret, integration, and DNS/configuration.

## 68.102 Ingestion Fails After Promotion

Check target account, connector configuration, authentication, role,
warehouse, integration, external storage, and network.

## 68.103 Performance Poor After Failover

Check warehouse sizing, concurrency, queueing, cache warm-up, workload
isolation, query profile, and external dependencies.

# Operational Runbooks

## 68.104 Failover Group Setup Runbook

1.  Identify business service.
2.  Define RPO.
3.  Define RTO.
4.  Verify primary account.
5.  Verify secondary account.
6.  Validate regions/clouds.
7.  Validate Snowflake capability.
8.  Inventory required objects.
9.  Map external dependencies.
10. Define service boundary.
11. Complete security review.
12. Complete residency review.
13. Estimate cost.
14. Create primary failover group.
15. Authorize secondary account.
16. Create secondary group.
17. Perform initial refresh.
18. Validate databases.
19. Validate data.
20. Validate roles/users.
21. Validate warehouses.
22. Validate authentication.
23. Validate integrations.
24. Configure replication schedule.
25. Configure monitoring.
26. Configure RPO alerts.
27. Document failover.
28. Document failback.
29. Execute DR test.
30. Track remediation.

## 68.105 Replication Failure Runbook

1.  Detect failure.
2.  Identify failover group.
3.  Capture error.
4.  Determine last successful refresh.
5.  Calculate lag.
6.  Compare with RPO.
7.  Check primary.
8.  Check secondary.
9.  Review recent changes.
10. Correct root issue.
11. Retry safely.
12. Validate refresh.
13. Validate critical objects.
14. Monitor subsequent refreshes.
15. Escalate if RPO is threatened.
16. Document incident.

## 68.106 Failover Runbook

1.  Declare incident.
2.  Establish incident commander.
3.  Confirm primary impact.
4.  Estimate primary recovery.
5.  Compare with RTO.
6.  Determine last successful replication.
7.  Calculate potential data loss.
8.  Validate secondary.
9.  Obtain failover authorization.
10. Fence old primary where possible.
11. Promote failover group.
12. Verify new primary state.
13. Activate/scale warehouses.
14. Validate authentication.
15. Validate RBAC.
16. Validate integrations.
17. Redirect ingestion.
18. Validate ingestion.
19. Redirect applications.
20. Execute smoke tests.
21. Obtain business validation.
22. Monitor.
23. Communicate recovery.
24. Begin failback planning.

## 68.107 Failback Runbook

1.  Stabilize DR production.
2.  Restore original environment.
3.  Establish replication toward recovered environment.
4.  Synchronize.
5.  Validate lag.
6.  Validate data.
7.  Validate account objects.
8.  Validate authentication.
9.  Validate integrations.
10. Schedule failback.
11. Notify stakeholders.
12. Fence active primary.
13. Complete final synchronization.
14. Promote recovered environment using supported procedure.
15. Redirect ingestion.
16. Redirect applications.
17. Validate business service.
18. Monitor.
19. Restore normal DR replication.
20. Complete post-incident review.

## 68.108 Logical Corruption Runbook

1.  Stop destructive process.
2.  Record incident timestamp.
3.  Capture query/job/change.
4.  Determine affected objects.
5.  Determine last replication.
6.  Check secondary state.
7.  Do not refresh a clean secondary.
8.  Preserve recovery evidence.
9.  Evaluate Time Travel.
10. Evaluate clone.
11. Evaluate UNDROP.
12. Evaluate source replay.
13. Recover/reconcile.
14. Validate.
15. Resume replication safely.
16. Monitor.
17. Complete RCA.

# Production Scenario

## 68.109 Scenario

Application: Patient360.

Primary: Snowflake Production, AWS us-east.

Secondary: Snowflake DR, AWS us-west.

Requirements: RPO = 30 minutes; RTO = 2 hours.

## 68.110 Failover Scope

Required: `PROD_DB`, P360 roles, P360 service account, P360 warehouses,
required integrations, authentication configuration, and monitoring.

External: Kafka, AWS IAM, secrets, application configuration,
DNS/routing.

## 68.111 Normal State

Patient360 → Primary Snowflake → PROD_FAILOVER_GROUP → replication →
Secondary Snowflake.

## 68.112 Incident

Suppose primary region is unavailable. Last successful replication:
10:15. Last confirmed primary transaction: 10:23. Potential exposure: 8
minutes, within a 30-minute RPO.

## 68.113 Failover Decision

If incident management confirms expected primary recovery exceeds the
2-hour RTO, failover may be authorized.

## 68.114 Promotion

Confirm secondary state; record replication point; fence old primary
where possible; promote secondary group; validate objects; scale
warehouses; validate authentication; redirect ingestion and Patient360;
execute smoke tests; confirm business functionality.

## 68.115 Data Validation

``` sql
SELECT
    COUNT(*) AS ROW_COUNT,
    MAX(UPDATED_AT) AS LAST_UPDATE
FROM PROD_DB.EMPI.PATIENT;
```

Validate expected recovery point.

## 68.116 Service Validation

Test Patient360 → Service Identity → P360_ROLE → P360_WH → PROD_DB.

# Production Standards

## 68.117 Common Mistakes

Avoid treating failover groups as backup; undefined RPO/RTO; no service
boundary; excessive scope; assuming all objects replicate; missing
dependency maps/lag monitoring/RPO alerts/authentication/integration
testing/ingestion routing/application routing/split-brain
protection/data-loss assessment/failback/DR testing/actual RPO-RTO
measurement/ownership; blind promotion; and blind refresh after logical
corruption.

## 68.118 Production Standards

Every failover group should map to a documented business service;
RPO/RTO should be defined first; accounts verified; secondary outside
required failure domain; supported objects validated; scope minimized;
external dependencies documented; DR security enforced; lag continuously
monitored; RPO alerts configured; refresh failures visible;
authentication/service accounts/warehouse capacity/integrations tested;
ingestion/application routing documented; single write authority
enforced; failover authorized; data-loss exposure communicated; logical
corruption handled safely; failback documented; failover/failback
tested; actual RPO/RTO measured; and ownership assigned.

## 68.119 SRE/DBRE Failover Group Checklist

Validate business service/owner/RPO/RTO;
accounts/regions/clouds/failure-domain separation; Snowflake
capability/object support; DR scope;
database/role/user/warehouse/integration inventories; external
dependencies; security/residency; primary/secondary groups; initial
refresh; database/data/roles/users/warehouses/authentication/service
accounts/integrations; schedule/lag monitoring/RPO alerts;
ingestion/application routing; split-brain prevention; failover
authority; failover/failback/logical-corruption runbooks; DR/failback
tests; actual RPO/RTO; and remediation tracking.

## 68.120 Operational Quick Reference

Define Service → Define RPO/RTO → Inventory Dependencies → Define
Failover Scope → Create Primary Group → Create Secondary → Initial
Refresh → Validate → Automate Replication → Monitor Lag → DR Test →
Incident → Assess/Authorize → Fence Primary → Promote → Route Workload →
Validate → Failback.

## 68.121 Key Takeaways

1.  Failover groups combine replication with controlled failover
    capabilities.
2.  Replication and failover are different operational actions.
3.  Failover groups are not backups.
4.  Logical corruption can propagate.
5.  Failover groups are only one layer of complete DR.
6.  Define service-level RPO before configuring replication.
7.  Define service-level RTO before designing failover.
8.  Measure actual replication lag.
9.  Do not equate schedule frequency with guaranteed RPO.
10. Define a clear service boundary.
11. Replicate only required objects.
12. Validate current supported object types.
13. Map external dependencies.
14. Place the secondary outside the required failure domain.
15. Treat the DR account as production.
16. Validate authentication.
17. Validate service accounts.
18. Validate warehouse capacity.
19. Test integrations end to end.
20. Explicitly redirect ingestion during DR.
21. Explicitly redirect applications during DR.
22. Prevent dual writers.
23. Fence the old primary where possible.
24. Calculate data-loss exposure before promotion.
25. Promotion requires authorization.
26. Do not blindly fail over for logical corruption.
27. Preserve a clean secondary when useful for recovery.
28. Failback requires synchronization and controlled authority transfer.
29. DR tests must include both failover and failback.
30. Measure actual service RPO and RTO.

## 68.122 Chapter Completion Checklist

After completing this chapter, you should be able to explain Snowflake
Failover Groups; compare replication and failover groups; explain why
failover is not backup; define service RPO/RTO; design primary/secondary
architecture and service boundaries; inventory DR objects/dependencies;
validate Snowflake object support; design scope; understand
primary/secondary groups and initial replication; configure frequency
conceptually; monitor lag and thresholds; validate
freshness/security/authentication/service accounts/warehouse
capacity/integrations; design ingestion/application routing; prevent
split-brain; perform pre-failover assessment; calculate data-loss
exposure; understand promotion; validate after promotion; handle logical
corruption; design failback; execute DR testing; measure actual RPO/RTO;
troubleshoot replication/promotion/application failures; execute
operational runbooks; and apply SRE/DBRE production standards.

**Chapter 68 --- Snowflake Failover Groups: Complete**
