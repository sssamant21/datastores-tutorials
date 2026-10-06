# Chapter 59 --- Snowflake Backup & Recovery Strategies

## 59.1 Overview

Snowflake does not use the traditional database backup model of manually
scheduling full, differential, and transaction-log backups.

Instead, production recovery is built from complementary capabilities:

-   Time Travel
-   Zero-Copy Cloning
-   Fail-safe
-   Replication / Failover
-   Source-System Replay
-   External exports where required
-   Tested recovery runbooks

A production strategy must answer: **How do we recover data, and how do
we recover service?**

## 59.2 Traditional Backup vs. Snowflake Recovery

Traditional databases commonly use full/incremental backups, transaction
logs, restore, and point-in-time recovery. Snowflake instead provides
mechanisms such as Time Travel, historical clones, Fail-safe,
replication/failover, and independent source or archive copies.

## 59.3 Backup Is a Recovery Requirement

The objective is not merely to have backups. The objective is to recover
required data and service within acceptable data-loss and recovery-time
limits. Define RPO, RTO, criticality, failure scenarios, mechanisms,
ownership, validation, and testing.

## 59.4 Recovery Point Objective --- RPO

RPO defines how much data loss the business can tolerate. Different
workloads can have different RPOs.

## 59.5 Recovery Time Objective --- RTO

RTO defines how quickly required service or data must be restored.

## 59.6 RPO and RTO Are Different

An RPO of 15 minutes and RTO of four hours means approximately 15
minutes of acceptable data loss and four hours of acceptable recovery
time.

## 59.7 Data Classification

Classify datasets by criticality, from authoritative
customer/transaction data through rebuildable analytics and temporary
staging. Recovery design should follow business criticality.

## 59.8 Source of Truth

For every critical table determine whether Snowflake is authoritative or
whether the data can be rebuilt from another durable source.

## 59.9 Example --- Rebuildable Table

If `RAW.CLAIMS` is loaded from durable S3 objects, source replay may be
the most appropriate recovery mechanism.

## 59.10 Example --- Snowflake Is Authoritative

If `PROD_DB.CUSTOMER.CUSTOMER_PROFILE` contains changes that exist only
in Snowflake, stronger recovery protection is required.

## 59.11 Recovery Layers

Use defense in depth: application safety → change controls → Time Travel
→ recovery clone → Fail-safe → replication/failover → independent
source/export where appropriate.

## 59.12 Layer 1 --- Prevent Data Loss

Use least privilege, change management, deployment validation,
destructive-DML controls, pipeline validation, data-quality checks,
row-count checks, auditing, and monitoring.

## 59.13 Layer 2 --- Time Travel

Time Travel should normally be the first recovery mechanism for
accidental DELETE, incorrect UPDATE/MERGE, accidental DROP, bad ETL, and
incorrect deployments.

## 59.14 Time Travel Recovery Example

``` sql
SELECT *
FROM PROD_DB.EMPI.PATIENT
BEFORE (
    STATEMENT => '<DELETE_QUERY_ID>'
);
```

## 59.15 Layer 3 --- Recovery Clone

``` sql
CREATE TABLE PROD_DB.EMPI.PATIENT_RECOVERY
CLONE PROD_DB.EMPI.PATIENT
BEFORE (
    STATEMENT => '<DELETE_QUERY_ID>'
);
```

## 59.16 Why Recovery Clones Matter

Clones enable historical validation, current-vs-historical comparison,
selective restoration, investigation, application testing, and evidence
preservation without immediately modifying production.

## 59.17 Layer 4 --- Fail-safe

Fail-safe is the last-resort Snowflake-managed recovery layer for
eligible permanent data after Time Travel. It should not be the normal
backup strategy.

## 59.18 Layer 5 --- Replication

Replication addresses region-level, cross-region/cross-cloud,
account-level, and business-continuity recovery requirements.

## 59.19 Layer 6 --- Source-System Replay

For rebuildable data, authoritative sources such as S3, Kafka,
applications, or upstream databases can provide independent
reconstruction paths.

## 59.20 Source Replay Requirements

Replay requires retained source data, reproducible
ordering/updates/deletes, known schema history, available pipeline code,
and functioning dependencies. Test these assumptions.

## 59.21 External Data Exports

Independent exports may be required for compliance, archive, legal,
vendor-independence, historical-retention, or cross-platform recovery
requirements.

## 59.22 Export Is Not Automatically a Backup

Know what was exported, when, completeness, encryption, storage
location, retention, restore procedure, and restore duration.

## 59.23 Recovery Scenario Matrix

  Failure                     Preferred Recovery
  --------------------------- -----------------------------------
  Accidental DELETE           Time Travel + clone
  Incorrect UPDATE            Time Travel + selective restore
  Bad MERGE                   Historical clone + reconciliation
  DROP TABLE                  UNDROP
  Time Travel expired         Evaluate Fail-safe
  Bad ETL                     Time Travel / source replay
  Lost derived table          Rebuild
  Region failure              Replication/failover
  Long-term historical need   Archive/export strategy
  Security compromise         Incident-specific recovery plan

## 59.24 Logical Corruption

Logical corruption includes incorrect DELETE, UPDATE, MERGE, application
bugs, pipeline bugs, and incorrect transformations while the platform
itself remains healthy.

## 59.25 Why Replication Does Not Solve Every Recovery Problem

Replication can replicate corrupted data. Therefore replication is not
protection from logical corruption; historical recovery remains
necessary.

## 59.26 Physical / Regional Failure

Region/account availability failures may require replication, failover
groups, secondary databases, cross-region design, or cross-cloud design.

## 59.27 Recovery Strategy by Failure Domain

Use Time Travel for row corruption, historical clones for table
corruption, UNDROP for supported dropped objects, Fail-safe evaluation
after Time Travel expiration, source replay for reconstructable
pipelines, and replication/failover for region failures.

## 59.28 Production Recovery Principle

Use the least disruptive recovery mechanism that safely solves the
problem. Do not restore an entire database for a small row-level
incident.

## 59.29 Selective Recovery

Identify exact damage → create recovery dataset → validate → restore
only affected records.

## 59.30 Preserve Current State

``` sql
CREATE TABLE PATIENT_CURRENT_INC12345
CLONE PATIENT;
```

Preserving current state can protect valid post-incident changes and
investigation evidence.

## 59.31 Historical Recovery State

``` sql
CREATE TABLE PATIENT_RECOVERY_INC12345
CLONE PATIENT
BEFORE (
    STATEMENT => '<QUERY_ID>'
);
```

## 59.32 Recovery Reconciliation

Compare current state, historical state, source-system state, and
application expectations to determine the correct final production
state.

## 59.33 Recovery Is Not Always Rollback

Recovery may require historical records plus valid new records and
updates minus corrupted changes---not simply restoring everything to an
older timestamp.

## 59.34 Accidental DELETE Strategy

Stop the faulty process → identify DELETE query → create historical
clone → find missing rows → restore missing rows → validate.

## 59.35 Accidental UPDATE Strategy

Identify UPDATE → create historical clone → compare changed columns →
determine affected rows → restore only incorrect values.

## 59.36 Accidental MERGE Strategy

Analyze incorrect inserts, incorrect updates, missing updates, and
logical duplicates separately.

## 59.37 Accidental DROP Strategy

``` sql
UNDROP TABLE CUSTOMER;
```

Use supported UNDROP capabilities while within applicable Time Travel
retention and validate dependencies/access afterward.

## 59.38 Bad TRUNCATE Strategy

Treat TRUNCATE as urgent logical data loss. Capture the statement and
immediately evaluate Time Travel/historical-clone recovery.

## 59.39 Bad CREATE OR REPLACE Strategy

Stop further changes, capture query ID/object metadata, evaluate Time
Travel, check dependencies, create a recovery workspace, and validate
before restoration.

## 59.40 Pipeline Corruption Strategy

Disable the faulty pipeline before recovery so it cannot immediately
corrupt restored data again.

## 59.41 Source Replay vs. Time Travel

Use Time Travel for fast historical recovery inside Snowflake. Use
source replay when data can be reliably reconstructed from an
authoritative source. Some incidents use both.

## 59.42 Recovery Dependency Mapping

Document source systems, stages, streams, tasks, dynamic tables, pipes,
views, materialized views, applications, exports, and data shares.

## 59.43 Recovery Order

Recover authoritative/base data first, then dependent tables, derived
datasets, views/applications, and downstream consumers.

## 59.44 Metadata Recovery

Recovery may require databases, schemas, tables, views, stages, file
formats, sequences, streams, tasks, pipes, policies, roles, grants,
tags, and integrations---not only rows.

## 59.45 Infrastructure as Code

Maintain Snowflake configuration in Terraform, version-controlled
SQL/DDL, CI/CD, and policy/role definitions where practical.

## 59.46 Why DDL Version Control Matters

Version-controlled DDL provides a known historical metadata definition
and reproducible reconstruction path.

## 59.47 Recovery Security

Use dedicated recovery roles, least privilege, controlled temporary
elevation, audit logging, approvals, and incident documentation.

## 59.48 Recovery Role

A recovery role may require controlled ability to inspect query history,
read historical data, create recovery clones/tables, restore supported
objects, perform controlled DML, and inspect grants.

## 59.49 Recovery Warehouse

``` sql
CREATE WAREHOUSE RECOVERY_WH
WITH
    WAREHOUSE_SIZE = 'MEDIUM'
    AUTO_SUSPEND = 60
    AUTO_RESUME = TRUE;
```

Size according to workload rather than automatically using a very large
warehouse.

## 59.50 Why Use a Recovery Warehouse

Benefits include workload isolation, cost attribution, reduced
production contention, independent scaling, and clearer incident
monitoring.

## 59.51 Recovery Compute Cost

Monitor warehouse size, runtime, repeated scans, concurrency, and large
reconciliation queries even during urgent recovery.

## 59.52 Recovery Performance

For very large tables, avoid unnecessary full-table comparisons when
incident time, date key, business key, source system, or batch ID can
safely narrow the scope.

## 59.53 Recovery Query Example

Avoid multi-terabyte unrestricted comparisons when evidence allows a
narrow incident predicate.

## 59.54 Recovery Validation Levels

Validate technical state → data → business meaning → application
behavior → downstream consumers.

## 59.55 Technical Validation

Check object existence, schema, columns, data types, permissions, and
dependencies.

## 59.56 Data Validation

Check row counts, business keys, duplicates, nulls, expected ranges,
affected records, and historical comparisons.

## 59.57 Business Validation

Application/data owners should validate expected customers,
transactions, balances, statuses, and reporting.

## 59.58 Application Validation

Verify application reads/writes, APIs, batch processing, dashboards,
reports, and downstream consumers.

## 59.59 Recovery Acceptance Criteria

Confirm faulty process correction, required data restoration,
preservation of valid current changes, row/business validation,
application/downstream/security validation, normal monitoring, evidence
retention, and RCA initiation.

## 59.60 Backup and Recovery Inventory

Maintain criticality, source of truth, RPO, RTO, and recovery method for
every important data domain.

## 59.61 Recovery Runbook Inventory

Maintain runbooks for DELETE, UPDATE, MERGE, TRUNCATE, DROP
table/schema/database, bad deployments, pipeline corruption, Time Travel
expiration, regional/account failures, and security incidents.

## 59.62 Recovery Ownership

Define Incident Commander, Snowflake SRE/DBRE, application owner, data
owner, security, platform/cloud team, Snowflake Support, and business
approver responsibilities.

## 59.63 Recovery Communication

Communicate what happened, affected data, whether corruption continues,
recovery mechanism, known facts, unknowns, and validation requirements.
Avoid unsupported recovery-time promises.

## 59.64 Recovery Evidence

Capture incident ID, query IDs, timestamps, users, roles, warehouses,
objects, row counts, commands, validation, Support cases, application
validation, and final state.

## 59.65 Recovery Drill

``` sql
CREATE TABLE RECOVERY_TEST (
    ID NUMBER,
    STATUS VARCHAR
);

INSERT INTO RECOVERY_TEST
VALUES
    (1, 'ACTIVE'),
    (2, 'ACTIVE'),
    (3, 'ACTIVE');
```

## 59.66 DELETE Recovery Drill

``` sql
DELETE FROM RECOVERY_TEST
WHERE ID = 2;
```

Capture the query ID and create:

``` sql
CREATE TABLE RECOVERY_TEST_CLONE
CLONE RECOVERY_TEST
BEFORE (
    STATEMENT => '<DELETE_QUERY_ID>'
);

SELECT *
FROM RECOVERY_TEST_CLONE
ORDER BY ID;
```

## 59.67 Recovery Drill Acceptance Criteria

The team should detect the incident, identify the query ID, find
historical state, create a recovery clone, identify missing data,
restore selectively, validate application logic, document evidence,
clean up safely, and measure recovery time.

## 59.68 RTO Testing

If a one-hour RTO requires four hours in a drill, the architecture does
not satisfy the requirement. Improve automation, runbooks, retention,
compute, replication, monitoring, or replay capability.

## 59.69 RPO Testing

Validate whether each recovery mechanism actually reaches the required
recovery point. A six-hour replay lag cannot satisfy a 15-minute RPO by
itself.

## 59.70 Recovery Automation

Automate safe evidence collection, query-history lookup, clone creation,
validation, naming, permission checks, inventory, and cleanup reminders.

## 59.71 Do Not Fully Automate Dangerous Recovery

Do not automatically drop/replace production, mass-update production,
delete current data, or perform uncontrolled failover without validation
and approval.

## 59.72 Backup Strategy for Critical Snowflake Data

Critical data may combine Time Travel, recovery cloning, Fail-safe,
replication/failover, source replay, external archive where required,
version-controlled metadata, and tested runbooks.

## 59.73 Backup Strategy for Rebuildable Data

For rebuildable data, prioritize durable source retention, reproducible
pipelines, schema versioning, and replay testing.

## 59.74 Backup Strategy for Regulatory Data

Account for retention, legal hold, encryption, auditing, independent
archive, geographic restrictions, deletion requirements, and recovery
testing.

## 59.75 Recovery Monitoring

Monitor failed pipelines, abnormal row-count changes, mass DML,
DROP/TRUNCATE, unexpected schema changes, replication lag, task
failures, and data-quality failures.

## 59.76 Recovery Readiness Dashboard

Track critical objects with approved retention, missing RPO/RTO, last
recovery test, recovery duration, replication health, replay readiness,
unowned critical objects, expired recovery clones, and open risks.

## 59.77 Weekly SRE/DBRE Recovery Review

Review recent destructive queries, recovery incidents, critical Time
Travel retention, recovery clone lifecycle, replication health, source
replay readiness, failed drills, RPO/RTO violations, recovery-role
access, and runbook changes.

## 59.78 Monthly Recovery Governance Review

Review classification, RPO/RTO, retention, permanent/transient design,
DR configuration, tests, Fail-safe incidents, source replay, archive
requirements, ownership, and open RCA actions.

## 59.79 Production Recovery Runbook

1.  Declare incident.
2.  Stop ongoing corruption.
3.  Identify affected objects.
4.  Capture evidence.
5.  Determine source of truth.
6.  Determine scope.
7.  Identify recovery point.
8.  Evaluate Time Travel.
9.  Evaluate historical clone.
10. Evaluate UNDROP.
11. Evaluate source replay.
12. Evaluate DR copy.
13. Escalate Fail-safe if necessary.
14. Preserve current state.
15. Create recovery workspace.
16. Validate recovered data.
17. Design reconciliation.
18. Perform controlled restoration.
19. Validate technical state.
20. Validate data.
21. Validate business state.
22. Validate application.
23. Validate downstream systems.
24. Resume workloads.
25. Monitor.
26. Capture final evidence.
27. Complete RCA.
28. Update recovery controls.

## 59.80 Recovery Decision Tree

For data/service incidents, first stop ongoing corruption. Use Time
Travel/historical clones for DML corruption, UNDROP for supported
dropped objects, source replay where reproducible, Fail-safe evaluation
when normal historical recovery has expired, and replication/failover
for service or regional failure.

## 59.81 Production Scenario

For a faulty MERGE against `PROD_DB.EMPI.PATIENT`, disable the pipeline,
capture the MERGE query ID, preserve current state, create a historical
recovery clone, compare affected records, distinguish incorrect
inserts/updates from legitimate writes, restore only corrupted data,
validate application/downstream behavior, resume ingestion, monitor, and
complete RCA.

``` sql
CREATE TABLE PATIENT_CURRENT_INC78901
CLONE PROD_DB.EMPI.PATIENT;

CREATE TABLE PATIENT_RECOVERY_INC78901
CLONE PROD_DB.EMPI.PATIENT
BEFORE (
    STATEMENT => '<MERGE_QUERY_ID>'
);
```

## 59.82 Recovery Maturity Model

Maturity progresses from reactive recovery → documented procedures →
governed RPO/RTO/retention/ownership → regularly tested recovery →
resilient, monitored, measured, safely automated recovery integrated
with DR and incident management.

## 59.83 Common Backup and Recovery Mistakes

Avoid forcing traditional backup assumptions onto Snowflake, treating
Time Travel as unlimited backup, treating Fail-safe as normal backup,
treating clones as independent backup, assuming replication protects
logical corruption, using transient tables for critical data without
review, lacking RPO/RTO/source-of-truth documentation, claiming
rebuildability without replay testing, restoring entire objects
unnecessarily, overwriting legitimate changes, ignoring
metadata/security, lacking recovery roles/runbooks/tests, and retaining
temporary recovery clones indefinitely.

## 59.84 Production Standards

Every critical dataset should have an owner, classification, source of
truth, RPO, and RTO. Time Travel should align with recovery
requirements. Review critical transient usage. Pre-establish recovery
roles. Use isolated clones and selective restoration where appropriate.
Preserve current state and legitimate changes. Version-control metadata.
Test source replay and DR where relied upon. Treat Fail-safe as last
resort. Schedule drills, measure recovery time, retain evidence, perform
RCA, and clean up temporary recovery objects.

## 59.85 SRE/DBRE Backup and Recovery Checklist

Validate data classification, owner, source of truth, RPO/RTO, Time
Travel, object type, Fail-safe understanding, clone/UNDROP/replay
testing, replication requirements, metadata version control, recovery
role/warehouse strategy, application/downstream dependencies, runbooks,
drills, measured recovery time, monitoring, escalation contacts, and
cleanup.

## 59.86 Key Takeaways

1.  Snowflake recovery is not based solely on traditional
    full/incremental backups.
2.  Recovery architecture starts with business requirements.
3.  RPO defines acceptable data loss.
4.  RTO defines acceptable recovery time.
5.  Critical data should be classified.
6.  Every important dataset needs a known source of truth.
7.  Time Travel handles many logical corruption incidents.
8.  Historical clones provide safe recovery workspaces.
9.  Fail-safe is last resort.
10. Replication addresses broader service/regional recovery.
11. Replication does not inherently protect against logical corruption.
12. Source replay is useful only when reproducible.
13. External archives may be required by policy/compliance.
14. Recovery should normally be selective.
15. Preserve legitimate post-incident writes.
16. Preserve current state when appropriate.
17. Validate technical, data, business, application, and downstream
    state.
18. Metadata recovery matters.
19. Infrastructure-as-code improves reconstruction.
20. Recovery privileges should be pre-established.
21. Recovery compute can be isolated.
22. Runbooks must be tested.
23. Validate RPO/RTO through drills.
24. Detect corruption before recovery windows expire.
25. Use defense in depth.

## 59.87 Chapter Completion Checklist

After this chapter you should be able to explain Snowflake's
backup/recovery model; define RPO/RTO; classify data and identify source
of truth; design layered recovery; use Time Travel, clones, Fail-safe,
replication, replay, and archives appropriately; recover common logical
incidents; preserve/reconcile current and historical data; recover
metadata; design recovery roles/compute; validate recovery at multiple
levels; maintain inventories/runbooks/ownership/evidence; perform
drills; measure RPO/RTO; automate safe tasks; monitor readiness; and
execute a production-grade Snowflake recovery strategy.

**Chapter 59 --- Snowflake Backup & Recovery Strategies: Complete**
