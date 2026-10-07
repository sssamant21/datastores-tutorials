# Chapter 69 --- Snowflake Cross-Region / Cross-Cloud Disaster Recovery

## 69.1 Overview

Cross-region and cross-cloud disaster recovery protects critical
Snowflake workloads from failures that affect an entire Snowflake
region, cloud region, or potentially a broader cloud-provider
dependency.

A typical cross-region architecture is:

``` text
PRIMARY
AWS us-east
    |
    | replication
    v
SECONDARY
AWS us-west
```

A cross-cloud architecture may look like:

``` text
PRIMARY
AWS
 |
 | replication
 v
SECONDARY
Azure
```

The exact region/cloud combinations, supported objects, replication
capabilities, edition requirements, and failover behavior must be
validated against current Snowflake capabilities.

## 69.2 What Cross-Region DR Protects Against

Cross-region DR can help address regional Snowflake service disruption,
cloud-region outage, regional networking disruption, major
infrastructure failure, extended regional service degradation, and
business-continuity requirements.

## 69.3 What Cross-Cloud DR Adds

Cross-cloud DR can reduce dependence on a single cloud provider.
However, it introduces additional IAM, networking, storage,
private-connectivity, secrets, application-infrastructure, and
operational complexity.

## 69.4 DR Is a Service Capability

Do not design DR only around whether a database exists in another
region. The goal is for the business service to operate from another
region/cloud.

## 69.5 Define RPO

Recovery Point Objective defines acceptable data loss. Example:
`RPO = 30 minutes`.

## 69.6 Define RTO

Recovery Time Objective defines acceptable service outage. Example:
`RTO = 2 hours`.

## 69.7 Define Failure Scenarios

Document whether DR must cover Snowflake account issues, Snowflake
regional issues, AWS/Azure/GCP regional outages, network isolation,
cloud-provider outages, or application-region outages.

# Architecture Models

## 69.8 Same-Cloud Cross-Region

Example: AWS us-east → AWS us-west. This can simplify cloud IAM,
networking, and application DR.

## 69.9 Cross-Cloud

Example: AWS → Azure. This may provide stronger cloud-provider isolation
but introduces different IAM, networking, storage, private connectivity,
secrets, infrastructure, and tooling.

## 69.10 Multi-Region Multi-Cloud

Large enterprises may maintain a primary plus regional and cloud-level
DR targets. This increases complexity and should be justified by
business requirements.

## 69.11 Avoid DR for DR's Sake

Additional targets increase cost, security scope, monitoring, testing,
operational complexity, failover decisions, and data-governance
requirements.

# Failure Domains

## 69.12 Understand Failure Domains

Possible failure domains include database, Snowflake account, Snowflake
region, cloud region, cloud provider, corporate network, identity
provider, and application region.

## 69.13 Match DR to Failure Domain

If the requirement is to survive AWS us-east failure, an AWS us-west
secondary may satisfy the regional objective.

## 69.14 Cloud-Provider Failure

If the requirement is to survive a broader AWS dependency failure,
another cloud may be considered.

## 69.15 Independent Dependencies

True cross-cloud DR may require independent cloud IAM, networking,
secrets, storage, application compute, monitoring, DNS, and security
controls.

# Region and Cloud Selection

## 69.16 Secondary Region Selection

Evaluate Snowflake support, distance, latency, data residency,
compliance, cloud services, application infrastructure, network
connectivity, cost, and operational skill.

## 69.17 Data Residency

Validate legal, regulatory, contractual, and organizational requirements
before replicating data between regions or countries.

## 69.18 Healthcare Data

PHI replicated to DR remains PHI. Apply required security and compliance
controls.

## 69.19 Region Availability

Do not assume every Snowflake feature is available in every region/cloud
combination. Validate current support.

# Snowflake Replication Layer

## 69.20 Database Replication

Use when the DR requirement primarily concerns specific databases.

## 69.21 Account Replication

Use broader replication when account-level objects are required.

## 69.22 Failover Groups

Use failover groups where supported and appropriate when controlled
promotion/failback is required.

## 69.23 Choose the Right Scope

Database-only requirements may use database replication. Full
application-service recovery may require account objects, databases, and
failover groups.

# DR Scope

## 69.24 Inventory Service Dependencies

Inventory databases, roles, users, warehouses, integrations,
authentication, network, ingestion, applications, external storage,
secrets, and monitoring.

## 69.25 Classify Dependencies

Classify each dependency as Snowflake replicated, Snowflake manually
recreated, external DR dependency, or not required during DR.

## 69.26 Dependency Matrix

  Component     Primary    DR         Recovery Method
  ------------- ---------- ---------- ------------------------
  PROD_DB       AWS East   AWS West   Snowflake replication
  APP_ROLE      Primary    DR         Account replication
  APP_WH        Primary    DR         Replication/IaC
  Kafka         Primary    DR         Connector reroute
  Secrets       AWS        AWS        Secrets DR
  Application   East       West       Application deployment
  Monitoring    Primary    DR         Monitoring platform

# Networking

## 69.27 Network DR

Validate DNS, firewall, private connectivity, allow lists, network
policies, corporate routing, VPN, and proxy access to the secondary.

## 69.28 Private Connectivity

The DR account may require independent private connectivity in the
secondary region/cloud.

## 69.29 Cross-Cloud Networking

AWS and Azure DR paths may require completely separate connectivity.
Both must be tested.

# Identity and Authentication

## 69.30 Identity Is a DR Dependency

Users must be able to authenticate during the incident.

## 69.31 SSO

Validate Identity Provider → Secondary Snowflake.

## 69.32 Identity Provider Failure

If both Snowflake accounts rely exclusively on the same unavailable IdP,
Snowflake DR may still be inaccessible.

## 69.33 Service Accounts

Test authentication, key pair/OAuth, role, warehouse, network access,
and account identifier.

## 69.34 Secrets

Different clouds may use different secret stores. Define secure
provisioning for DR credentials.

# Cloud IAM

## 69.35 Cloud IAM Does Not Replicate Automatically

Snowflake replication does not automatically reproduce external cloud
IAM.

## 69.36 AWS Example

Snowflake → AWS IAM Role → S3. The DR account must have valid cloud-side
trust and permissions.

## 69.37 Azure Example

Snowflake → Azure Identity → Blob Storage.

## 69.38 Cross-Cloud Mapping

Do not assume AWS IAM roles and Azure managed identities are
interchangeable. Map equivalent permissions explicitly.

# External Storage

## 69.39 External Stage Dependencies

If workloads depend on S3, Azure Blob, or GCS, determine whether those
storage systems remain available during the same failure.

## 69.40 Same-Region Storage Risk

A Snowflake DR account in us-west may still fail ingestion if its only
source S3 bucket is unavailable in us-east.

## 69.41 Storage DR

Protect external storage independently where required.

# Ingestion

## 69.42 Ingestion Architecture

Normal: Source → Kafka → Primary Snowflake.

DR: Source → Kafka/DR Connector → Secondary Snowflake.

## 69.43 Kafka

Plan connector target, credentials, Snowflake account, role, warehouse,
database, and network path.

## 69.44 Batch Pipelines

Validate Airflow, Databricks, Glue, ADF, Kubernetes CronJobs, Lambda,
and custom ETL.

## 69.45 Avoid Duplicate Processing

Control activation so old and DR pipelines do not create uncontrolled
duplicate ingestion.

# Application DR

## 69.46 Snowflake DR Without Application DR Is Incomplete

A healthy Snowflake secondary does not restore the business service if
the application region remains unavailable.

## 69.47 Application Secondary

Critical applications may require secondary compute, container platform,
load balancer, secrets, configuration, networking, and monitoring.

## 69.48 Connection Configuration

Applications must know how to connect to the DR Snowflake account.

## 69.49 Avoid Hard-Coded Account Endpoints

Where feasible, use controlled configuration management rather than
primary-only endpoints embedded in code.

# Replication Monitoring

## 69.50 DR Dashboard

Track primary/secondary account, region/cloud, replication/failover
group, last successful refresh, duration, lag, RPO target/status, and
failure count.

## 69.51 Service Readiness Dashboard

Also track authentication, warehouses, integrations, network, ingestion,
application DR, external storage, and monitoring.

## 69.52 Replication Lag Alert

Example: RPO 30 min; warning 20 min; critical 30 min.

## 69.53 DR Readiness Is More Than Green Replication

Replication can be healthy while SSO, Kafka, warehouses, private
connectivity, or application connectivity is broken. Use synthetic
readiness checks.

# Capacity Planning

## 69.54 DR Capacity

Decide whether DR is hot, warm, or cold.

## 69.55 Hot DR

Fast RTO but higher steady-state cost.

## 69.56 Warm DR

Core infrastructure exists but some scaling/activation is required.

## 69.57 Cold DR

Infrastructure is created or substantially configured during the
incident, reducing steady-state cost but increasing RTO and operational
risk.

## 69.58 Warehouse Capacity

A DR X-Small warehouse may not sustain a production workload normally
running on a Large multi-cluster warehouse.

## 69.59 Capacity Test

Run representative workloads against DR.

# Cost

## 69.60 Cross-Region Cost

Consider secondary storage, replication transfer, DR compute, testing,
network services, and external-storage replication.

## 69.61 Cross-Cloud Cost

Also consider cloud egress, cross-cloud networking, duplicate
infrastructure, separate monitoring, and security services.

## 69.62 Cost vs. RTO

Lower RTO generally requires more pre-provisioned capability and higher
steady-state cost.

## 69.63 FinOps Review

Periodically review DR cost without weakening required recovery
objectives.

# Security

## 69.64 DR Security Baseline

Apply least privilege, MFA, RBAC, network restrictions, encryption,
audit logging, secret management, and data classification.

## 69.65 Secondary Is Not a Test Environment

Do not weaken controls because the secondary is normally passive.

## 69.66 Access Review

Review who can administer DR, promote failover, change replication,
access DR data, and modify routing.

# Logical Corruption

## 69.67 Regional DR Does Not Solve Logical Corruption

Bad data can replicate from primary to secondary.

## 69.68 Preserve Secondary When Appropriate

If corruption has not replicated, do not refresh until recovery options
are assessed.

## 69.69 Logical Recovery

Evaluate Time Travel, Clone, UNDROP, Source Replay, Selective Restore,
and preserved secondary state.

# Failover Decision

## 69.70 Incident Classification

Determine whether failure is Snowflake-specific, regional,
cloud-specific, network-specific, application-specific, or
identity-specific.

## 69.71 Do Not Fail Over Unnecessarily

Failover has risks including data loss, routing errors, split brain,
pipeline duplication, unexpected performance, and failback complexity.

## 69.72 Compare Recovery vs. Failover

Compare expected primary recovery time, RTO, and expected failover time.

## 69.73 Determine Data-Loss Exposure

Record last known primary data point, last replicated data point, and
the difference.

# Failover

## 69.74 Failover Workflow

Incident → Classify Failure → Assess Primary Recovery → Check RPO →
Validate DR → Authorize Failover → Fence Primary → Promote Secondary →
Activate Compute → Validate Auth → Validate Network → Redirect Ingestion
→ Redirect Application → Smoke Test → Business Validation.

## 69.75 Fence Primary

Prevent old-primary writes whenever possible.

## 69.76 Promote Snowflake

Use the supported Snowflake failover procedure for the configured
architecture.

## 69.77 Activate Compute

Scale warehouses to required production capacity.

## 69.78 Activate Integrations

Validate external integrations before workload activation.

## 69.79 Redirect Ingestion

Move Kafka, ETL, batch, and other pipelines to DR.

## 69.80 Redirect Applications

Update application configuration/routing to DR.

## 69.81 Smoke Test

Validate authentication, read, write, warehouse, critical query,
ingestion, and application workflow.

# Cross-Cloud Failover

## 69.82 Cross-Cloud Adds Additional Steps

Cross-cloud recovery may require cloud IAM, private connectivity,
storage, secrets, monitoring, and application-infrastructure changes.

## 69.83 Cloud-Native Dependencies

Identify every dependency tied to the original cloud.

## 69.84 Avoid Hidden Single-Cloud Dependencies

A cross-cloud Snowflake replica is not true cross-cloud DR if critical
services still depend solely on the failed cloud.

# Failback

## 69.85 Failback Planning

Design failback before the incident.

## 69.86 Recovered Primary Is Stale

After running in DR, the recovered original environment must receive new
changes before authority returns.

## 69.87 Reverse Replication

Use supported Snowflake replication/failover mechanisms to synchronize
the recovered environment.

## 69.88 Validate Before Failback

Validate data, lag, RBAC, authentication, network, warehouses,
integrations, ingestion, and applications.

## 69.89 Controlled Failback

Synchronize → Validate → Approve → Fence Current Primary → Final Sync →
Switch Authority → Route Workloads → Validate.

# DR Testing

## 69.90 Cross-Region DR Test

Test the full service, not only Snowflake replication.

## 69.91 Test Scope

Include replication, failover, authentication, network, warehouses,
integrations, external storage, ingestion, application, monitoring, and
failback.

## 69.92 Cross-Cloud DR Test

Also test cloud IAM differences, secret provisioning, cross-cloud
networking, cloud-specific storage, and cloud-specific application
deployment.

## 69.93 Measure Actual RPO

Measure the latest business transaction available after failover.

## 69.94 Measure Actual RTO

Measure from incident/DR declaration to restored business service.

## 69.95 Test Under Production-Like Load

A DR environment that supports one query may fail under real
concurrency.

## 69.96 Record Test Results

Capture expected/actual RPO/RTO,
replication/network/authentication/capacity/application issues, manual
steps, cost, and remediation.

# Troubleshooting

## 69.97 Replication Not Reaching Secondary

Check replication configuration, account authorization, region/cloud
support, privileges, object support, primary health, and Snowflake
errors.

## 69.98 Replication Lag Increasing

Investigate high DML, large loads/rebuilds, replication failures,
region/cloud issues, schedule changes, and platform incidents.

## 69.99 DR Authentication Failure

Check SSO, IdP, account identifier, MFA, key pair, OAuth, and network
policy.

## 69.100 DR Network Failure

Check DNS, private connectivity, firewall, proxy, VPN, allow lists, and
network policy.

## 69.101 Storage Integration Failure

Check Snowflake integration, cloud identity, trust policy, storage
permission, region, and network.

## 69.102 Ingestion Failure

Check connector target, credentials, role, warehouse, database,
integration, network, and external source.

## 69.103 Application Failure

Check account endpoint, secret, authentication, role, warehouse,
network, and application configuration.

## 69.104 DR Performance Problem

Check warehouse size, multi-cluster configuration, queueing,
concurrency, cache warm-up, query profile, and external latency.

# Operational Runbooks

## 69.105 Cross-Region DR Setup Runbook

1.  Identify business service.
2.  Define RPO.
3.  Define RTO.
4.  Define failure scenarios.
5.  Verify primary account/region/cloud.
6.  Select secondary region/cloud.
7.  Validate Snowflake support.
8.  Complete data-residency review.
9.  Complete security review.
10. Inventory Snowflake dependencies.
11. Inventory external dependencies.
12. Classify recovery method for every dependency.
13. Configure database/account/failover replication.
14. Perform initial replication.
15. Validate data.
16. Validate RBAC.
17. Validate authentication.
18. Validate warehouses.
19. Validate integrations.
20. Validate network.
21. Configure ingestion DR.
22. Configure application DR.
23. Configure monitoring.
24. Configure RPO alerts.
25. Document failover.
26. Document failback.
27. Execute full DR test.
28. Measure actual RPO/RTO.
29. Track remediation.

## 69.106 Cross-Cloud DR Setup Runbook

Follow the cross-region runbook plus:

1.  Map cloud IAM equivalents.
2.  Provision cloud-specific identities.
3.  Configure secondary-cloud networking.
4.  Configure private connectivity.
5.  Configure secondary-cloud secrets.
6.  Validate external-storage strategy.
7.  Validate application deployment.
8.  Validate monitoring independence.
9.  Test cloud-provider isolation.
10. Perform cross-cloud failover test.

## 69.107 Failover Runbook

1.  Declare incident.
2.  Establish incident commander.
3.  Classify failure domain.
4.  Estimate primary recovery.
5.  Compare with RTO.
6.  Determine last successful replication.
7.  Calculate data-loss exposure.
8.  Validate DR account.
9.  Validate authentication.
10. Validate network.
11. Obtain failover authorization.
12. Fence primary where possible.
13. Promote secondary.
14. Validate Snowflake state.
15. Scale warehouses.
16. Validate integrations.
17. Redirect ingestion.
18. Validate ingestion.
19. Redirect applications.
20. Run smoke tests.
21. Obtain business validation.
22. Monitor.
23. Communicate DR activation.
24. Begin failback planning.

## 69.108 Failback Runbook

1.  Stabilize DR production.
2.  Recover original region/cloud.
3.  Restore required infrastructure.
4.  Establish replication toward recovered environment.
5.  Synchronize.
6.  Validate lag.
7.  Validate data.
8.  Validate RBAC.
9.  Validate authentication.
10. Validate network.
11. Validate integrations.
12. Validate application.
13. Schedule failback.
14. Notify stakeholders.
15. Fence current production.
16. Complete final synchronization.
17. Switch authority.
18. Redirect ingestion.
19. Redirect application.
20. Validate service.
21. Monitor.
22. Restore normal DR posture.
23. Complete post-incident review.

## 69.109 Logical Corruption Runbook

1.  Stop destructive activity.
2.  Record timestamp.
3.  Capture query/job/change.
4.  Determine affected data.
5.  Determine replication point.
6.  Check secondary state.
7.  Preserve clean secondary state.
8.  Do not blindly refresh.
9.  Evaluate Time Travel.
10. Evaluate clone.
11. Evaluate UNDROP.
12. Evaluate source replay.
13. Recover/reconcile.
14. Validate.
15. Resume replication.
16. Monitor.
17. Complete RCA.

# Production Scenario

## 69.110 Patient360 Scenario

Application: Patient360.

Primary: AWS us-east.

Secondary: AWS us-west.

Requirements: RPO = 30 minutes; RTO = 2 hours.

## 69.111 Snowflake Components

`PROD_DB`, P360 roles, P360 service identity, P360 warehouses, storage
integration, and failover group.

## 69.112 External Components

Kafka, AWS IAM, S3, Secrets Manager, Kubernetes, application
configuration, and monitoring.

## 69.113 Normal Architecture

Patient360 → Kubernetes us-east → Snowflake us-east → replication →
Snowflake us-west.

## 69.114 Complete DR Architecture

Application and Snowflake recovery are both required. Patient360 should
have a recovery path in the secondary application region as well as the
Snowflake secondary.

## 69.115 Failure Scenario

At 10:30, AWS us-east becomes unavailable. Last replicated Snowflake
point: 10:18. Potential data-loss exposure: 12 minutes. This is within a
30-minute RPO.

## 69.116 Recovery

Declare DR; confirm regional failure; validate us-west Snowflake;
confirm replication point; promote DR; scale warehouses; validate
authentication; activate DR Kafka/ingestion; activate Patient360 in
us-west; route traffic; run smoke tests; validate business workflows.

## 69.117 Validation Query

``` sql
SELECT
    COUNT(*) AS ROW_COUNT,
    MAX(UPDATED_AT) AS LAST_UPDATE
FROM PROD_DB.EMPI.PATIENT;
```

# Production Standards

## 69.118 Common Mistakes

Avoid replicating Snowflake but not the application; undefined failure
scenarios/RPO/RTO; secondary in same failure domain; assuming universal
region/cloud feature support; missing
residency/dependency/network/authentication/IAM/storage/ingestion/application
plans; hard-coded primary endpoints; undersized DR warehouses; missing
split-brain protection/data-loss assessment/failback/full testing/load
testing/ownership.

## 69.119 Production Standards

DR should be designed around the business service; failure scenarios
documented; RPO/RTO approved; secondary outside targeted failure domain;
current Snowflake region/cloud capabilities validated;
residency/security reviewed; every dependency has a recovery method;
authentication/network/IAM/external storage/integrations tested;
ingestion/application routing documented; primary-only hard coding
minimized; DR capacity tested; replication lag monitored; RPO alerts
configured; failover authorized; potential data loss communicated;
single write authority maintained; failback documented; full service
tests performed with representative workloads; actual RPO/RTO measured;
remediation tracked.

## 69.120 SRE/DBRE Cross-Region / Cross-Cloud DR Checklist

Validate business service/owner/failure scenarios/RPO/RTO;
primary/secondary account/region/cloud and failure-domain separation;
Snowflake capability/region-cloud support; residency/security;
Snowflake/external dependency inventories and matrix; replication and
initial sync; data/RBAC/authentication/service
accounts/warehouses/capacity/network/private connectivity/cloud
IAM/external storage/integrations; ingestion/application DR;
monitoring/lag/RPO alerts; split-brain prevention/failover
authority/runbooks; full DR and production-like load tests; actual
RPO/RTO; remediation.

## 69.121 Operational Quick Reference

Define Business Service → Define Failure Scenarios → Define RPO/RTO →
Select DR Region/Cloud → Validate Snowflake Support → Map Dependencies →
Configure Replication → Build Network/IAM/Application DR → Validate →
Monitor RPO → Full DR Test → Incident → Assess/Authorize → Fence Primary
→ Promote → Route Ingestion/Application → Validate Business Service →
Failback.

## 69.122 Key Takeaways

1.  Cross-region DR protects against regional failure.
2.  Cross-cloud DR can provide broader cloud-provider fault isolation.
3.  Cross-cloud DR introduces significantly more complexity.
4.  DR should be designed around the business service.
5.  Define failure scenarios before choosing architecture.
6.  Define RPO.
7.  Define RTO.
8.  RTO includes the entire application recovery process.
9.  Match DR topology to the required failure domain.
10. Validate current Snowflake region/cloud support.
11. Review data residency.
12. PHI/PII classification remains unchanged in DR.
13. Inventory all Snowflake dependencies.
14. Inventory all external dependencies.
15. Classify every dependency by recovery method.
16. Network connectivity must exist independently in DR.
17. Authentication must work during a primary-region outage.
18. Cloud IAM must be configured separately where required.
19. External storage may require its own DR strategy.
20. Ingestion must be explicitly redirected.
21. Application infrastructure also requires DR.
22. Avoid hard-coded primary-only endpoints.
23. Monitor actual replication lag.
24. Test DR warehouse capacity.
25. Maintain single write authority.
26. Calculate data-loss exposure before failover.
27. Regional DR does not protect against replicated logical corruption.
28. Failback requires synchronization.
29. Full DR tests must include Snowflake, network, ingestion, and
    application layers.
30. Measure actual service-level RPO and RTO.

## 69.123 Chapter Completion Checklist

After completing this chapter, you should be able to explain
cross-region and cross-cloud Snowflake DR; compare
same-cloud/cross-cloud architectures; define failure domains/RPO/RTO;
match architecture to business scenarios; select a secondary
region/cloud; evaluate residency and sensitive-data controls; select
database/account/failover replication scope; build a dependency matrix;
design network/private-connectivity DR; validate
identity/authentication; plan cross-cloud secrets/IAM/external storage;
design Kafka/ETL/application DR; monitor lag/readiness; design
hot/warm/cold DR; capacity-test warehouses; analyze cost; apply
security; handle logical corruption; make controlled failover decisions;
execute failover/failback; run full DR tests; measure actual RPO/RTO;
troubleshoot Snowflake/network/authentication/ingestion/application
failures; execute runbooks; and apply SRE/DBRE production standards.

**Chapter 69 --- Snowflake Cross-Region / Cross-Cloud Disaster Recovery:
Complete**
