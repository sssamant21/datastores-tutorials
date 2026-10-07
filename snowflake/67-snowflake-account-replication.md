# Chapter 67 --- Snowflake Account Replication

## 67.1 Overview

Snowflake Account Replication extends disaster-recovery planning beyond
an individual database by allowing supported account-level objects and
databases to be replicated to another Snowflake account.

Conceptually:

``` text
PRIMARY ACCOUNT
     |
     +-- Databases
     +-- Roles
     +-- Users
     +-- Warehouses
     +-- Integrations
     +-- Other supported account objects
     |
     v
Replication / Failover Group
     |
     v
SECONDARY ACCOUNT
```

The exact objects supported for replication depend on current Snowflake
capabilities, account configuration, edition, cloud, and region.

## 67.2 Why Account Replication Matters

Database replication protects database-level data and metadata.
Production applications often also depend on roles, users, warehouses,
security objects, integrations, and account configuration. Recovering
only the database may therefore leave the application unusable.

## 67.3 Database Replication vs. Account Replication

Database Replication focuses on database data and supported database
objects. Account Replication focuses on broader service recovery by
replicating supported account state.

## 67.4 Account Replication Is Part of DR

Complete DR may also require application routing, DNS, secrets, cloud
IAM, external storage, network connectivity, Kafka, ETL systems,
Kubernetes, CI/CD, monitoring, and operational procedures.

## 67.5 Replication Is Not Backup

Account replication can propagate logical changes. It does not replace
Time Travel, Zero-Copy Cloning, Fail-safe where applicable, source
replay, recovery procedures, or backup/recovery strategy.

# Recovery Objectives

## 67.6 Define Service RPO

Define RPO at the service level, for example:
`Patient360 Snowflake Service — RPO = 30 minutes`.

## 67.7 Define Service RTO

Example: `Patient360 Snowflake Service — RTO = 2 hours`. This should
include more than database promotion.

## 67.8 Component Recovery Objectives

Different components may have different recovery requirements, including
production databases, RBAC, warehouses, integrations, and applications.

## 67.9 RTO Includes Dependencies

Real RTO includes detect + decide + promote + configure + route +
validate + resume, not just database promotion time.

# Inventory

## 67.10 Account Inventory

Inventory databases, roles, users, warehouses, resource monitors,
network policies, security/API/storage/notification integrations,
shares, replication objects, account parameters, and other critical
objects.

## 67.11 Database Inventory

``` sql
SHOW DATABASES;
```

Identify production, configuration, utility, shared/imported, temporary,
and test databases. Not every database necessarily belongs in DR scope.

## 67.12 Warehouse Inventory

``` sql
SHOW WAREHOUSES;
```

Document warehouse purpose, size, auto-suspend, scaling policy,
workload, and DR requirement.

## 67.13 Role Inventory

``` sql
SHOW ROLES;
```

Identify application, operational, security, read-only, ETL, and
administrative roles.

## 67.14 User Inventory

``` sql
SHOW USERS;
```

Classify human users, service accounts, automation identities, legacy
users, and disabled users.

## 67.15 Integration Inventory

Inventory critical storage, security, API, notification, and
external-access integrations using appropriate Snowflake metadata
interfaces.

## 67.16 Dependency Map

Map Application → User/Service Identity → Role → Warehouse → Database →
External Integration. This becomes the DR validation basis.

# Supported Objects

## 67.17 Validate Current Support

Verify current Snowflake documentation for replicable object types,
edition requirements, region/cloud support, replication/failover-group
capabilities, limitations, refresh behavior, and promotion behavior.

## 67.18 Do Not Assume Everything Replicates

Account Replication is not a perfect account clone. Document what
replicates automatically, requires manual recreation, requires external
configuration, or is unnecessary in DR.

## 67.19 External Systems

AWS/Azure/GCP IAM, cloud-storage permissions, DNS, private endpoints,
firewalls, Kubernetes secrets, Kafka ACLs, and application secrets are
outside Snowflake replication.

# Target Account

## 67.20 Secondary Account

Document organization, account, region, cloud, edition, environment,
owner, and DR role.

## 67.21 Verify Primary Account

``` sql
SELECT
    CURRENT_ORGANIZATION_NAME(),
    CURRENT_ACCOUNT_NAME(),
    CURRENT_REGION();
```

## 67.22 Verify Secondary Account

Run equivalent validation in the secondary account. Never configure
replication based on assumed context.

## 67.23 Failure-Domain Separation

Choose a secondary location that meaningfully reduces exposure to the
targeted failure.

## 67.24 Cross-Cloud DR

Evaluate Snowflake support, transfer, latency, cloud dependencies,
security, cost, residency, and application architecture.

# Replication Groups

## 67.25 Replication Group Concept

A replication group logically groups supported Snowflake objects that
should replicate together, such as databases, roles, users, warehouses,
and supported integrations.

## 67.26 Why Group Objects

Grouping defines DR scope intentionally rather than treating the entire
account as an uncontrolled unit.

## 67.27 Group by Service

Example: `PATIENT360_DR` can contain the Patient360 database, roles,
warehouses, service identities, and required integrations.

## 67.28 Avoid Unnecessary Objects

Do not automatically replicate developer sandboxes, old test databases,
unused warehouses, legacy users, or temporary objects unless required.

# Configure Replication

## 67.29 Source-Side Configuration

Conceptually: Primary Account → Define Replication Group → Select
Objects → Authorize Secondary. Exact SQL depends on current Snowflake
capabilities.

## 67.30 Example Conceptual Replication Group

``` sql
CREATE REPLICATION GROUP PROD_DR_GROUP
    OBJECT_TYPES = DATABASES, ROLES, USERS, WAREHOUSES
    ALLOWED_DATABASES = PROD_DB
    ALLOWED_ACCOUNTS = <SECONDARY_ACCOUNT>;
```

This is an architectural example. Validate exact current syntax and
supported object types before execution.

## 67.31 Secondary Group

The secondary account creates the corresponding secondary replication
object using the supported Snowflake process.

## 67.32 Initial Refresh

Plan for database size, object count, role/user count, warehouse
metadata, integrations, cross-region/cross-cloud transfer, duration, and
cost.

## 67.33 Validate Initial Refresh

Do not stop at "refresh succeeded." Validate actual service components.

# Refresh Strategy

## 67.34 Replication Refresh

Refresh the secondary group using the supported Snowflake mechanism.

## 67.35 Refresh Frequency

Choose frequency based on RPO.

## 67.36 Monitor Actual Lag

A 15-minute schedule does not automatically guarantee a 15-minute RPO
because refreshes take time and can fail.

## 67.37 Large Change Events

Large loads, role/user redesigns, warehouse changes, database rebuilds,
and massive DML can affect refresh duration or readiness.

# Validation

## 67.38 Database Validation

``` sql
SHOW DATABASES;
```

Compare expected DR scope in primary and secondary.

## 67.39 Schema Validation

``` sql
SHOW SCHEMAS IN DATABASE PROD_DB;
```

## 67.40 Table Validation

``` sql
SHOW TABLES IN DATABASE PROD_DB;
```

## 67.41 Data Validation

``` sql
SELECT
    COUNT(*) AS ROW_COUNT,
    MAX(UPDATED_AT) AS LAST_UPDATE
FROM PROD_DB.EMPI.PATIENT;
```

Run in both appropriate account contexts.

## 67.42 Role Validation

``` sql
SHOW ROLES;
```

## 67.43 User Validation

``` sql
SHOW USERS;
```

## 67.44 Warehouse Validation

``` sql
SHOW WAREHOUSES;
```

## 67.45 Integration Validation

Validate integrations individually and end to end. Object existence does
not prove external connectivity.

# Authentication

## 67.46 Authentication Is Critical to DR

Validate SSO, MFA, service accounts, OAuth, key-pair authentication,
SCIM, and network access as applicable.

## 67.47 External Identity Provider

An external identity provider becomes a DR dependency.

## 67.48 Service Accounts

Validate identity existence, authentication, keys/secrets, role
assignment, and network access.

## 67.49 Do Not Copy Secrets Into Documentation

Never place passwords, private keys, OAuth secrets, or client secrets in
DR documents, Git, tickets, or chat. Store only references to approved
secret-management locations.

# RBAC

## 67.50 RBAC Validation

Test Application User → Application Role → Warehouse → Database.

## 67.51 Administrative Access

Ensure authorized emergency administrators can access the DR account
during primary-region failure.

## 67.52 Break-Glass Access

Where policy permits, maintain controlled emergency access with strong
authentication, restricted ownership, auditing, periodic testing,
rotation, and documented activation.

# Warehouses

## 67.53 Warehouse DR Strategy

Determine whether warehouses are replicated, pre-created, created during
failover, or managed through IaC based on capabilities and standards.

## 67.54 DR Warehouse Sizing

Passive DR does not necessarily need full production capacity, but
required capacity must be available before activation.

## 67.55 Cost vs. Recovery Time

Warm DR improves RTO but may increase steady-state cost. Cold/minimal DR
can lower steady-state cost but increase RTO.

# Integrations

## 67.56 Storage Integration

Validate Snowflake integration → cloud IAM → S3/Blob/GCS end to end.

## 67.57 Notification Integration

Validate external notifications and event destinations.

## 67.58 API Integration

Validate API gateway, cloud IAM, allowed endpoints, network
connectivity, and authentication.

## 67.59 External Access

External network access may depend on infrastructure outside Snowflake;
test end to end.

# Pipelines

## 67.60 Data Ingestion DR

Replication alone does not redirect Kafka or other ingestion from the
primary account to the secondary. Explicit routing is required.

## 67.61 ETL/ELT

Validate Airflow, dbt, Databricks, Kubernetes jobs, Lambda, ADF, Glue,
and custom applications for DR endpoint/account configuration.

## 67.62 Snowpipe

Validate all required Snowflake and cloud-side components for ingestion
DR.

## 67.63 Scheduled Tasks

Ensure required scheduled processing is available and intentionally
activated during failover. Avoid accidental double processing.

# Split-Brain Prevention

## 67.64 Avoid Dual Writers

Avoid independent writes to primary and secondary without a supported
active-active design.

## 67.65 Single Write Authority

Normal: Primary = WRITE; Secondary = PASSIVE.

Failover: Primary = DISABLED/UNAVAILABLE; Secondary = WRITE.

## 67.66 Application Routing

Application configuration must enforce current write authority.

# Logical Corruption

## 67.67 Account Replication Can Propagate Errors

Accidental DELETE/DROP, incorrect RBAC changes, bad schema deployments,
and wrong configuration can replicate.

## 67.68 Preserve Secondary State

Stop the bad change, check replication state, and preserve useful
secondary state. Do not automatically refresh.

## 67.69 Recovery Mechanisms

Use Time Travel, Zero-Copy Clone, UNDROP, source replay,
configuration/IaC restoration, or preserved secondary state as
appropriate.

# Monitoring

## 67.70 Account Replication Dashboard

Track replication group, primary/secondary account and region, last
refresh, duration, lag, status, RPO target/compliance, and failure
count.

## 67.71 Object Validation Dashboard

Track database, RBAC, users, warehouses, integrations, authentication,
ingestion, and application readiness.

## 67.72 RPO Alert

For a 30-minute RPO, a possible model is warning at 20 minutes and
critical at 30 minutes, tuned to operational requirements.

## 67.73 Replication Failure Alert

Repeated failure threatening recovery objectives should page the
responsible team.

# Cost

## 67.74 Account Replication Cost

Potential costs include secondary storage,
replication/cross-region/cross-cloud transfer, DR account usage,
warehouses, testing, and monitoring.

## 67.75 Avoid Replicating Unnecessary Objects

Unnecessary DR scope increases storage, transfer, operational
complexity, and testing scope.

## 67.76 DR Cost Ownership

Assign ownership for DR cost.

# Failover Readiness

## 67.77 Failover Readiness Checklist

Validate healthy replication, RPO compliance, databases, roles, users,
warehouses, authentication, integrations, ingestion/application routing,
monitoring, security approval, and tested runbooks.

## 67.78 Failover Decision

Consider primary availability/recovery estimate, replication point,
data-loss exposure, secondary readiness, and business impact.

## 67.79 Pre-Failover Data Assessment

Record last primary data point, last successful replication, current
lag, estimated missing data, and known errors.

# Failover

## 67.80 Failover Flow

Incident → Assess Primary → Declare DR → Freeze/Fence Primary → Validate
Secondary → Promote → Activate Compute → Validate Authentication →
Activate Pipelines → Route Applications → Business Validation.

## 67.81 Fence the Old Primary

When possible, prevent old-primary writes before secondary activation to
reduce split-brain risk.

## 67.82 Activate in Controlled Order

Conceptually: Data → Security/Authentication → Compute → Integrations →
Ingestion → Applications.

## 67.83 Validate Before Traffic

Run smoke tests before directing production traffic.

# DR Testing

## 67.84 Account DR Test

Validate login, RBAC, queries, warehouses, data freshness, ingestion,
integrations, applications, monitoring, and incident procedures.

## 67.85 Measure Actual RTO

Measure from DR declaration until the business service is operational.

## 67.86 Measure Actual RPO

Determine the latest recoverable business transaction/data point
available in DR.

## 67.87 Record Test Results

Document expected/actual RPO and RTO, failures, manual steps, missing
dependencies, security issues, cost, and remediation owners.

# Failback

## 67.88 Failback Is Part of DR

Design both Primary → DR and DR → Recovered Primary.

## 67.89 Failback Risks

Risks include data divergence, lost transactions, wrong replication
direction, routing errors, dual writers, and stale integrations.

## 67.90 Failback Process

Stabilize DR → restore original region → establish replication →
synchronize → validate → schedule failback → fence current primary →
switch authority → route applications → validate.

# Troubleshooting

## 67.91 Replication Group Creation Fails

Check edition, privileges, account identifiers, region/cloud support,
object eligibility, existing relationships, and allowed accounts.

## 67.92 Refresh Fails

Check primary/secondary state, privileges, replication configuration,
unsupported object changes, platform errors, and recent changes.

## 67.93 RPO Increasing

Investigate large changes, high DML, failures, cross-region/cloud
issues, refresh duration, and changed schedules.

## 67.94 User Cannot Login to DR

Check user replication, authentication method, SSO, identity provider,
network policy, MFA, key pair, and account identifier.

## 67.95 User Logs In but Cannot Query

Check role/grants, database access, warehouse access/state, and
imported/shared dependencies.

## 67.96 Warehouse Missing

Determine whether it was in scope, should be created through IaC, or was
intentionally excluded.

## 67.97 Integration Fails

Check both Snowflake and external cloud configuration. All layers must
work.

## 67.98 Application Cannot Connect

Check account identifier, connection string, DNS/configuration,
authentication, network policy, secrets, role, and warehouse.

## 67.99 Ingestion Still Going to Old Account

Evaluate split-brain/data-divergence risk immediately. Check pipeline
configuration, secrets, account URL, Kafka connector, ETL configuration,
and scheduled jobs.

# Operational Runbooks

## 67.100 Account Replication Setup Runbook

1.  Define service RPO.
2.  Define service RTO.
3.  Inventory primary account.
4.  Identify critical databases.
5.  Identify roles/users.
6.  Identify warehouses.
7.  Identify integrations.
8.  Map external dependencies.
9.  Identify secondary account.
10. Select secondary region/cloud.
11. Validate Snowflake capability.
12. Validate supported objects.
13. Complete security review.
14. Complete residency/compliance review.
15. Define replication scope.
16. Configure replication group.
17. Configure secondary.
18. Perform initial refresh.
19. Validate databases.
20. Validate RBAC.
21. Validate users.
22. Validate warehouses.
23. Validate integrations.
24. Validate authentication.
25. Configure automated refresh.
26. Configure monitoring.
27. Configure RPO alerts.
28. Document failover.
29. Document failback.
30. Execute DR test.

## 67.101 Replication Failure Runbook

1.  Detect failure.
2.  Identify affected group.
3.  Capture error.
4.  Determine last successful refresh.
5.  Calculate lag.
6.  Compare with RPO.
7.  Check primary.
8.  Check secondary.
9.  Review recent changes.
10. Identify unsupported/dependent objects.
11. Correct issue.
12. Retry safely.
13. Validate refresh.
14. Validate critical objects.
15. Monitor subsequent refreshes.
16. Escalate if RPO is threatened.
17. Document incident.

## 67.102 Account Failover Runbook

1.  Declare incident.
2.  Establish incident commander.
3.  Confirm primary impact.
4.  Estimate primary recovery time.
5.  Determine last successful replication.
6.  Calculate data-loss exposure.
7.  Validate secondary.
8.  Obtain DR authorization.
9.  Fence primary where possible.
10. Promote/activate secondary using supported procedure.
11. Validate databases.
12. Validate authentication.
13. Validate RBAC.
14. Activate/scale warehouses.
15. Validate integrations.
16. Redirect ingestion.
17. Validate ingestion.
18. Redirect applications.
19. Execute smoke tests.
20. Obtain business validation.
21. Monitor.
22. Communicate DR activation.
23. Begin failback planning.

## 67.103 Failback Runbook

1.  Stabilize DR environment.
2.  Recover original region/account.
3.  Establish supported replication toward recovered target.
4.  Synchronize data.
5.  Validate lag.
6.  Validate account objects.
7.  Schedule controlled failback.
8.  Notify stakeholders.
9.  Stop/fence active writes.
10. Complete final synchronization.
11. Validate data.
12. Switch write authority.
13. Redirect ingestion.
14. Redirect applications.
15. Validate authentication.
16. Validate workloads.
17. Monitor.
18. Re-establish normal replication.
19. Complete post-DR review.

## 67.104 Logical Corruption Runbook

1.  Stop destructive process.
2.  Capture timestamp/query/change.
3.  Determine affected objects.
4.  Check replication state.
5.  Determine whether corruption replicated.
6.  Preserve useful secondary state.
7.  Do not blindly refresh.
8.  Evaluate Time Travel.
9.  Evaluate clone/UNDROP/source replay.
10. Evaluate IaC/configuration restore for account objects.
11. Recover.
12. Validate.
13. Resume replication safely.
14. Monitor.
15. Complete RCA.

# Production Scenario

## 67.105 Scenario

Primary: Snowflake Production, AWS us-east.

Secondary: Snowflake DR, AWS us-west.

Application: Patient360.

Requirements: RPO = 30 minutes; RTO = 2 hours.

## 67.106 Required Components

`PROD_DB`, P360 application roles, P360 service account, P360
warehouses, storage integration, ingestion configuration,
authentication, and monitoring.

## 67.107 Dependency Architecture

Patient360 → Service Account → P360_ROLE → P360_WH → PROD_DB → External
Integrations.

Every layer must be validated in DR.

## 67.108 Replication Scope

Replicate only supported components required to restore the service. Do
not add unrelated development/test resources without justification.

## 67.109 DR Validation Query

``` sql
SELECT
    COUNT(*) AS ROW_COUNT,
    MAX(UPDATED_AT) AS LAST_UPDATE
FROM PROD_DB.EMPI.PATIENT;
```

Run in the appropriate primary and DR account contexts.

## 67.110 Authentication Test

Validate P360 Service Account → Authenticate to DR → Assume P360_ROLE →
Use P360_WH → Query PROD_DB.

## 67.111 Ingestion Test

Validate Source → Pipeline → DR Snowflake → Target Table. Historical
data replication does not prove new ingestion is operational.

# Production Standards

## 67.112 Common Mistakes

Avoid calling account replication a backup; missing service-level
RPO/RTO; replicating only data while ignoring account dependencies;
assuming every object replicates; missing inventories/dependency
maps/authentication/service-account/integration testing; missing
ingestion/application routing; missing split-brain
prevention/failback/RPO monitoring/DR tests/security/residency review;
and missing ownership/runbooks.

## 67.113 Production Standards

Every critical Snowflake service should have defined RPO/RTO;
service-based DR scope; maintained account inventory; documented
supported/non-replicated dependencies; appropriate failure-domain
separation; DR security controls; tested authentication/service
identities/RBAC/warehouses/integrations; documented
ingestion/application routing; single write authority; lag monitoring
and RPO alerts; authorized failover; data-loss assessment; DR tests
measuring actual RPO/RTO; tested failback; and assigned ownership.

## 67.114 SRE/DBRE Account Replication Checklist

Validate service/owner/RPO/RTO; accounts/regions/clouds;
account/database/role/user/warehouse/integration inventories; external
dependencies; supported/non-replicated objects; security/residency;
replication scope/group/secondary/initial refresh;
databases/freshness/roles/users/warehouses/authentication/service
accounts/integrations; ingestion/application routing; split-brain
prevention; monitoring/RPO alerts; failover/failback/logical-corruption
runbooks; DR test; actual RPO/RTO; and remediation tracking.

## 67.115 Operational Quick Reference

Service Requirements → Define RPO/RTO → Inventory Account → Map
Dependencies → Define DR Scope → Select Secondary → Configure
Replication → Initial Refresh → Validate Data/RBAC/Auth/Compute →
Validate Integrations → Automate Refresh → Monitor RPO → DR Test →
Measure RPO/RTO → Failover/Failback Runbook.

## 67.116 Key Takeaways

1.  Account replication extends DR beyond individual databases.
2.  Production services depend on account-level and external components.
3.  Account replication is not a backup.
4.  Logical corruption can replicate.
5.  Define service-level RPO.
6.  Define service-level RTO.
7.  RTO includes application recovery, not just data promotion.
8.  Inventory the entire account.
9.  Inventory databases.
10. Inventory roles and users.
11. Inventory warehouses.
12. Inventory integrations.
13. Map external dependencies.
14. Do not assume every object replicates.
15. Validate current Snowflake capabilities.
16. Choose an appropriate secondary failure domain.
17. Cross-cloud DR requires additional planning.
18. Replication groups should follow service boundaries.
19. Avoid unnecessary DR scope.
20. Monitor actual replication lag.
21. Authentication must be tested.
22. Service accounts must be tested.
23. RBAC must be validated.
24. External integrations require end-to-end testing.
25. Replication does not automatically redirect ingestion.
26. Prevent dual writers.
27. Preserve secondary state during logical corruption investigations.
28. Failover requires data-loss assessment.
29. DR testing must measure actual RPO and RTO.
30. Failback is part of the DR design.

## 67.117 Chapter Completion Checklist

After completing this chapter, you should be able to explain Snowflake
Account Replication; compare database and account replication; explain
why replication is not backup; define service RPO/RTO; inventory account
components and dependencies; validate current support; identify
manual-recovery objects; design a secondary account and
cross-region/cloud DR; define replication groups/scope; understand
initial refresh; design refresh frequency and lag monitoring; validate
databases/data/RBAC/authentication/service
accounts/warehouses/integrations; design ingestion/application routing;
prevent split-brain; handle logical corruption; monitor cost/readiness;
execute controlled failover/failback; measure RPO/RTO; troubleshoot
account-level DR; execute operational runbooks; and apply SRE/DBRE
production standards.

**Chapter 67 --- Snowflake Account Replication: Complete**
