# Chapter 65 --- Snowflake Secure Cross-Account Data Sharing

## 65.1 Overview

Snowflake Secure Cross-Account Data Sharing allows one Snowflake account
to provide governed access to data for another Snowflake account without
building a traditional copy/export/import pipeline.

Conceptually:

``` text
PROVIDER ACCOUNT
      |
      v
Curated Shared Objects
      |
      v
Secure Share
      |
      v
CONSUMER ACCOUNT
      |
      v
Imported Database
      |
      v
Consumer Warehouse
```

The provider controls the shared data. The consumer queries that data
using compute in the consumer account.

## 65.2 Why Cross-Account Sharing Matters

Traditional cross-account data delivery often uses export files, object
storage, transfer processes, and consumer-side loading. This creates
duplicate storage, synchronization delays, additional security
boundaries, operational complexity, and more failure points.

Secure sharing simplifies this architecture.

## 65.3 Secure Sharing Model

``` text
Provider Storage
      |
      v
Snowflake Secure Share
      |
      v
Consumer Metadata Reference
      |
      v
Consumer Query
```

The consumer does not require the provider to maintain a traditional
exported copy for standard secure sharing.

## 65.4 Provider and Consumer

The **provider** owns and exposes the data. The **consumer** is the
Snowflake account authorized to access it.

## 65.5 Ownership Boundary

The provider retains control of source objects and sharing
authorization. The consumer queries shared data and controls local RBAC
and query compute.

## 65.6 Compute Boundary

The consumer normally uses its own warehouse. This separates provider
data ownership from consumer query compute.

## 65.7 Common Use Cases

Cross-account sharing can support business partners, customers,
subsidiaries, separate organizational accounts, analytics partners,
vendors, data-product consumers, cross-business-unit access, and
controlled external reporting.

# Architecture

## 65.8 Production Architecture

``` text
PROVIDER ACCOUNT

PROD_DB
   |
   +-- CUSTOMER
   |      +-- CUSTOMER_PROFILE
   |
   +-- SHARING
          +-- CUSTOMER_SUMMARY
                    |
                    v
              CUSTOMER_SHARE
                    |
             Snowflake Sharing
                    |
                    v

CONSUMER ACCOUNT

CUSTOMER_SHARED_DB
       |
       +-- SHARING
              +-- CUSTOMER_SUMMARY
                       |
                       v
                 ANALYTICS_WH
                       |
                       v
                CONSUMER_ROLE
                       |
                       v
                    User
```

## 65.9 Cross-Account Sharing Is a Contract

Treat the share as a provider data contract covering schema, columns,
semantics, freshness, security, and lifecycle. Consumers may build
production systems on this interface.

# Provider Preparation

## 65.10 Provider Readiness

Before sharing, document business purpose, consumer identity, account
identifier, approvals, dataset, classification, contract, support
ownership, and review/expiration dates.

## 65.11 Verify Provider Context

``` sql
SELECT
    CURRENT_ACCOUNT(),
    CURRENT_ROLE(),
    CURRENT_DATABASE(),
    CURRENT_SCHEMA();
```

Never perform production sharing changes based on assumed account
context.

## 65.12 Identify Consumer Account

Obtain the exact consumer Snowflake account identifier through an
approved process. Do not guess organization, account, region, or cloud
identifiers.

## 65.13 Consumer Inventory

Record consumer organization, Snowflake account identifier, environment,
business purpose, owners, technical contact, classification, approval
date, review date, and expiration.

# Consumer Contract Layer

## 65.14 Avoid Sharing Raw Operational Schemas

Avoid exposing RAW, STAGING, TEMP, INTERNAL, or PIPELINE_METADATA unless
explicitly required. Prefer source → sharing schema → secure consumer
views → share.

## 65.15 Create Sharing Schema

``` sql
CREATE SCHEMA IF NOT EXISTS PROD_DB.SHARING;
```

## 65.16 Create Secure View

``` sql
CREATE OR REPLACE SECURE VIEW
PROD_DB.SHARING.CUSTOMER_SUMMARY AS
SELECT
    CUSTOMER_ID,
    STATUS,
    STATE,
    CREATED_DATE
FROM PROD_DB.CUSTOMER.CUSTOMER_PROFILE;
```

## 65.17 Explicit Columns

Avoid:

``` sql
SELECT *
FROM PROD_DB.CUSTOMER.CUSTOMER_PROFILE;
```

Use explicit columns to prevent uncontrolled future exposure.

## 65.18 Minimum Necessary Data

Only share columns the consumer actually needs. Data availability is not
authorization to share it.

## 65.19 Row Filtering

``` sql
CREATE OR REPLACE SECURE VIEW
PROD_DB.SHARING.CUSTOMER_NC_SUMMARY AS
SELECT
    CUSTOMER_ID,
    STATUS,
    STATE
FROM PROD_DB.CUSTOMER.CUSTOMER_PROFILE
WHERE STATE = 'NC';
```

Validate that filters implement the approved business rule.

## 65.20 Aggregated Sharing

``` sql
CREATE OR REPLACE SECURE VIEW
PROD_DB.SHARING.CUSTOMER_STATE_SUMMARY AS
SELECT
    STATE,
    STATUS,
    COUNT(*) AS CUSTOMER_COUNT
FROM PROD_DB.CUSTOMER.CUSTOMER_PROFILE
GROUP BY
    STATE,
    STATUS;
```

Aggregation can reduce unnecessary exposure.

## 65.21 Sensitive Data

Review PII, PHI, PCI, financial data, internal identifiers, security
metadata, secrets, and restricted business data before sharing.

# Create the Share

## 65.22 Create Share

``` sql
CREATE SHARE CUSTOMER_CROSS_ACCOUNT_SHARE;
```

## 65.23 Verify Share

``` sql
SHOW SHARES LIKE 'CUSTOMER_CROSS_ACCOUNT_SHARE';
```

## 65.24 Grant Database Usage

``` sql
GRANT USAGE
ON DATABASE PROD_DB
TO SHARE CUSTOMER_CROSS_ACCOUNT_SHARE;
```

## 65.25 Grant Schema Usage

``` sql
GRANT USAGE
ON SCHEMA PROD_DB.SHARING
TO SHARE CUSTOMER_CROSS_ACCOUNT_SHARE;
```

## 65.26 Grant Shared Object

``` sql
GRANT SELECT
ON VIEW PROD_DB.SHARING.CUSTOMER_SUMMARY
TO SHARE CUSTOMER_CROSS_ACCOUNT_SHARE;
```

Validate any additional requirements for the actual shared-object
design.

## 65.27 Review Share Grants

``` sql
SHOW GRANTS TO SHARE CUSTOMER_CROSS_ACCOUNT_SHARE;
```

Confirm that only approved objects are exposed.

## 65.28 Provider Security Gate

Validate the database, schema, objects, explicit columns, row filters,
sensitive-data exclusions, security policies, contract, and grants
before consumer authorization.

# Authorize Consumer Account

## 65.29 Add Consumer

``` sql
ALTER SHARE CUSTOMER_CROSS_ACCOUNT_SHARE
ADD ACCOUNTS = <CONSUMER_ACCOUNT_IDENTIFIER>;
```

Use the exact approved account identifier.

## 65.30 Multiple Consumers

A share may support multiple consumers when they require the same
contract, but do not combine unrelated consumers merely because the
mechanism allows it.

## 65.31 Different Consumer Requirements

If consumers need different data contracts, use separate views/shares
such as `CUSTOMER_DETAIL_SHARE` and `CUSTOMER_AGGREGATE_SHARE`.

## 65.32 Why Separate Shares

Separate shares improve access boundaries, auditing, revocation,
lifecycle management, and consumer-specific contract enforcement.

# Consumer Configuration

## 65.33 Consumer Receives Share Information

Provide the provider account identifier, share name, dataset
description, schema documentation, support contact, freshness
expectation, and change policy.

## 65.34 Verify Consumer Context

``` sql
SELECT
    CURRENT_ACCOUNT(),
    CURRENT_ROLE();
```

## 65.35 Discover Inbound Share

Verify the expected provider, share, and consumer account through the
supported Snowflake sharing interface.

## 65.36 Create Imported Database

``` sql
CREATE DATABASE CUSTOMER_SHARED_DB
FROM SHARE <PROVIDER_ACCOUNT>.CUSTOMER_CROSS_ACCOUNT_SHARE;
```

Use the exact provider/share identifier visible to the consumer.

## 65.37 Verify Database

``` sql
SHOW DATABASES LIKE 'CUSTOMER_SHARED_DB';
```

## 65.38 Inspect Schemas

``` sql
SHOW SCHEMAS IN DATABASE CUSTOMER_SHARED_DB;
```

## 65.39 Inspect Shared Objects

``` sql
SHOW VIEWS IN SCHEMA CUSTOMER_SHARED_DB.SHARING;
```

## 65.40 Query Shared Data

``` sql
SELECT *
FROM CUSTOMER_SHARED_DB.SHARING.CUSTOMER_SUMMARY
LIMIT 100;
```

# Consumer Compute

## 65.41 Consumer Warehouse

``` sql
CREATE WAREHOUSE IF NOT EXISTS SHARED_DATA_WH
WITH
    WAREHOUSE_SIZE = 'XSMALL'
    AUTO_SUSPEND = 60
    AUTO_RESUME = TRUE;
```

## 65.42 Compute Ownership

The provider owns the data. The consumer controls its warehouse,
concurrency, and query cost.

## 65.43 Query Cost

Consumers should monitor warehouse runtime, credits, concurrency, query
efficiency, auto-suspend, and warehouse sizing.

# Consumer RBAC

## 65.44 Create Consumer Role

``` sql
CREATE ROLE CUSTOMER_SHARED_READER;
```

## 65.45 Grant Imported Privileges

``` sql
GRANT IMPORTED PRIVILEGES
ON DATABASE CUSTOMER_SHARED_DB
TO ROLE CUSTOMER_SHARED_READER;
```

Use the current privilege model applicable to imported shared databases.

## 65.46 Grant Warehouse Usage

``` sql
GRANT USAGE
ON WAREHOUSE SHARED_DATA_WH
TO ROLE CUSTOMER_SHARED_READER;
```

## 65.47 Grant Role

``` sql
GRANT ROLE CUSTOMER_SHARED_READER
TO USER <CONSUMER_USER>;
```

Prefer role hierarchy over many direct user grants.

## 65.48 Validate Consumer Access

``` sql
USE ROLE CUSTOMER_SHARED_READER;
USE WAREHOUSE SHARED_DATA_WH;

SELECT *
FROM CUSTOMER_SHARED_DB.SHARING.CUSTOMER_SUMMARY
LIMIT 10;
```

# End-to-End Validation

## 65.49 Provider Count

``` sql
SELECT COUNT(*)
FROM PROD_DB.SHARING.CUSTOMER_SUMMARY;
```

## 65.50 Consumer Count

``` sql
SELECT COUNT(*)
FROM CUSTOMER_SHARED_DB.SHARING.CUSTOMER_SUMMARY;
```

Compare results according to the contract.

## 65.51 Validate Representative Record

Provider:

``` sql
SELECT *
FROM PROD_DB.SHARING.CUSTOMER_SUMMARY
WHERE CUSTOMER_ID = 1001;
```

Consumer:

``` sql
SELECT *
FROM CUSTOMER_SHARED_DB.SHARING.CUSTOMER_SUMMARY
WHERE CUSTOMER_ID = 1001;
```

## 65.52 Validate Schema

Confirm column names, data types, business definitions, nullable
behavior, and expected grain.

## 65.53 Validate Security Boundary

The consumer should not see unapproved columns/rows, internal schemas,
operational metadata, secrets, or restricted attributes.

## 65.54 Validate Freshness

Provider and consumer should agree on a measurable freshness
expectation, such as `< 24 hours` where appropriate.

# Provider Changes

## 65.55 Add Shared Object

``` sql
CREATE OR REPLACE SECURE VIEW
PROD_DB.SHARING.ORDER_SUMMARY AS
SELECT
    ORDER_ID,
    CUSTOMER_ID,
    ORDER_DATE,
    STATUS
FROM PROD_DB.SALES.ORDERS;

GRANT SELECT
ON VIEW PROD_DB.SHARING.ORDER_SUMMARY
TO SHARE CUSTOMER_CROSS_ACCOUNT_SHARE;
```

## 65.56 Add Column

Treat every new consumer-facing column as possible new exposure. Review
classification, consumer need, compatibility, security, and
documentation.

## 65.57 Remove Object

``` sql
REVOKE SELECT
ON VIEW PROD_DB.SHARING.ORDER_SUMMARY
FROM SHARE CUSTOMER_CROSS_ACCOUNT_SHARE;
```

Communicate planned removals.

## 65.58 Remove Consumer

``` sql
ALTER SHARE CUSTOMER_CROSS_ACCOUNT_SHARE
REMOVE ACCOUNTS = <CONSUMER_ACCOUNT_IDENTIFIER>;
```

Validate access removal.

## 65.59 Drop Share

``` sql
DROP SHARE CUSTOMER_CROSS_ACCOUNT_SHARE;
```

Dropping a production share can affect every attached consumer and
should be treated as a high-risk change.

# Schema Evolution

## 65.60 Shared Objects Are APIs

Consumers depend on object names, columns, data types, semantics,
freshness, and availability.

## 65.61 Additive Change

Even additive changes require review because new fields may expose
sensitive information.

## 65.62 Breaking Change

Dropping/renaming columns, changing types, grain, filtering, or semantic
meaning requires consumer-impact analysis.

## 65.63 Versioning

For major changes, use versions such as `CUSTOMER_SUMMARY_V1` and
`CUSTOMER_SUMMARY_V2`.

## 65.64 Deprecation

Create V2 → notify consumers → migration period → validate migration →
retire V1.

# Cross-Region and Cross-Cloud Considerations

## 65.65 Same-Region Sharing

Same-region/account-compatible sharing is operationally simpler, but
validate the exact topology against current Snowflake support.

## 65.66 Cross-Region Sharing

Different regions may require additional Snowflake sharing/replication
mechanisms depending on current platform capabilities.

## 65.67 Cross-Cloud Sharing

Different cloud platforms may require additional architecture. Evaluate
supported topology, replication, latency, cost, residency, security, and
DR.

## 65.68 Why This Matters

Cross-account does not necessarily mean same region, cloud, or
organization. Verify architecture before implementation.

# Security

## 65.69 Least Privilege

The provider shares minimum necessary data. The consumer grants minimum
necessary local access.

## 65.70 Provider Security

Provider controls objects, rows, columns, consumer authorization, and
share lifecycle.

## 65.71 Consumer Security

Consumer controls local roles, users, warehouses, downstream access, and
applications.

## 65.72 Shared Data Is Still Sensitive

Sharing does not change classification. PHI remains PHI, PII remains
PII, and confidential data remains confidential.

## 65.73 Auditability

Maintain evidence of approval, shared data, consumer account, start
date, contract changes, and access termination.

# Monitoring

## 65.74 Provider Monitoring

Monitor share existence/grants, authorized consumers, secure-view
health, source pipelines, schema/security-policy changes, and freshness.

## 65.75 Consumer Monitoring

Monitor imported database availability, query failures, warehouse
health, freshness, schema changes, and downstream failures.

## 65.76 Share Inventory

Maintain share, consumer, data product, owner, classification, and
review cadence.

## 65.77 Access Review

Periodically verify consumer approval, purpose, dataset requirement,
sensitive fields, ownership, contract status, and expiration.

# Troubleshooting

## 65.78 Consumer Cannot See Share

Provider checks: share existence, correct consumer identifier,
authorization, account/environment, and configuration. Consumer checks:
correct account, role, provider, and share.

## 65.79 Imported Database Creation Fails

Check provider identifier, share name, consumer authorization, consumer
role privileges, and share availability.

## 65.80 Database Exists but Object Missing

``` sql
SHOW GRANTS TO SHARE CUSTOMER_CROSS_ACCOUNT_SHARE;
```

Validate database usage, schema usage, object privilege, secure view,
and dependencies.

## 65.81 Consumer Permission Error

Check imported privileges, consumer role, role hierarchy, and warehouse
usage. Do not solve normal access issues with excessive admin
privileges.

## 65.82 No Active Warehouse

``` sql
USE WAREHOUSE SHARED_DATA_WH;
```

## 65.83 Missing Data

Trace provider source → secure view → share → imported database →
consumer query and identify the first difference.

## 65.84 Stale Data

Check source ingestion, provider transformation, secure-view logic,
freshness timestamp, and pipeline/task failures.

## 65.85 Query Slowness

Inspect consumer warehouse size, queueing, concurrency, query profile,
scan volume, and pruning before provider-side data design.

## 65.86 Consumer Sees Too Much Data

Treat as a potential security incident. Investigate secure-view
definitions, row filters, columns, policy behavior, grants, and recent
changes; contain exposure when required.

# Incident Management

## 65.87 Cross-Account Sharing Incidents

Examples include inaccessible, stale, incorrect, or overexposed data;
schema breaks; accidental consumer removal; accidental share drops; and
provider source failures.

## 65.88 Accidental Consumer Removal

Confirm → identify consumer → preserve evidence → restore approved
authorization → consumer validates → monitor.

## 65.89 Accidental Share Drop

1.  Identify affected consumers.
2.  Preserve query/change evidence.
3.  Determine expected share definition.
4.  Recreate only after validating the approved contract.
5.  Restore required grants.
6.  Re-authorize consumers.
7.  Validate consumer access.
8.  Monitor.
9.  Complete RCA.

Do not recreate a share from memory.

## 65.90 Unauthorized Exposure

Contain → revoke/correct → preserve evidence → identify consumers →
assess exposure → engage security/compliance → controlled restoration.

# Operational Runbooks

## 65.91 Provider Onboarding Runbook

1.  Receive request.
2.  Identify consumer.
3.  Verify account identifier.
4.  Document business purpose.
5.  Identify dataset.
6.  Classify data.
7.  Obtain approvals.
8.  Define contract.
9.  Create sharing schema.
10. Create secure view.
11. Validate rows/columns.
12. Create share.
13. Grant database usage.
14. Grant schema usage.
15. Grant objects.
16. Review grants.
17. Add consumer.
18. Validate authorization.
19. Provide consumer details.
20. Perform end-to-end validation.
21. Record inventory.
22. Establish review date.

## 65.92 Consumer Onboarding Runbook

1.  Receive provider/share details.
2.  Verify provider.
3.  Verify expected share.
4.  Create imported database.
5.  Inspect schemas.
6.  Inspect objects.
7.  Create local role.
8.  Grant imported privileges.
9.  Configure warehouse.
10. Grant warehouse usage.
11. Grant local users.
12. Query data.
13. Validate counts.
14. Validate schema.
15. Validate representative records.
16. Validate freshness.
17. Document dependencies.
18. Begin monitoring.

## 65.93 Consumer Offboarding Runbook

Confirm approval → identify dependencies → notify consumer → stop
downstream workloads → remove consumer → validate access removal →
consumer removes local access/database as appropriate → preserve
evidence → update inventory.

## 65.94 Emergency Revocation Runbook

Declare incident → identify share/consumer → remove authorization/object
access → validate containment → preserve evidence → assess exposure →
engage security/compliance → correct root cause → re-authorize only
after approval → validate → monitor.

# Production Scenario

## 65.95 Healthcare Partner Sharing

A healthcare provider shares approved data with an analytics partner.
The source contains PATIENT_ID, NAME, DOB, SSN, ADDRESS, PHONE, EMAIL,
STATUS, and STATE. The consumer needs only PATIENT_ID, STATUS, and
STATE.

## 65.96 Create Consumer Contract

``` sql
CREATE OR REPLACE SECURE VIEW
PROD_DB.SHARING.PARTNER_PATIENT_SUMMARY AS
SELECT
    PATIENT_ID,
    STATUS,
    STATE
FROM PROD_DB.EMPI.PATIENT;
```

## 65.97 Create Cross-Account Share

``` sql
CREATE SHARE PARTNER_PATIENT_SHARE;

GRANT USAGE
ON DATABASE PROD_DB
TO SHARE PARTNER_PATIENT_SHARE;

GRANT USAGE
ON SCHEMA PROD_DB.SHARING
TO SHARE PARTNER_PATIENT_SHARE;

GRANT SELECT
ON VIEW PROD_DB.SHARING.PARTNER_PATIENT_SUMMARY
TO SHARE PARTNER_PATIENT_SHARE;
```

## 65.98 Add Approved Consumer

``` sql
ALTER SHARE PARTNER_PATIENT_SHARE
ADD ACCOUNTS = <APPROVED_CONSUMER_ACCOUNT>;
```

Validate the identifier before execution.

## 65.99 Consumer Creates Database

``` sql
CREATE DATABASE PATIENT_SHARED_DB
FROM SHARE <PROVIDER_ACCOUNT>.PARTNER_PATIENT_SHARE;
```

## 65.100 Consumer Role

``` sql
CREATE ROLE PATIENT_SHARED_READER;

GRANT IMPORTED PRIVILEGES
ON DATABASE PATIENT_SHARED_DB
TO ROLE PATIENT_SHARED_READER;

GRANT USAGE
ON WAREHOUSE SHARED_DATA_WH
TO ROLE PATIENT_SHARED_READER;
```

## 65.101 Validate Privacy Boundary

The consumer must not see NAME, DOB, SSN, ADDRESS, PHONE, or EMAIL
unless explicitly approved.

## 65.102 Validate End to End

Provider:

``` sql
SELECT COUNT(*)
FROM PROD_DB.SHARING.PARTNER_PATIENT_SUMMARY;
```

Consumer:

``` sql
SELECT COUNT(*)
FROM PATIENT_SHARED_DB.SHARING.PARTNER_PATIENT_SUMMARY;
```

Validate columns, representative records, freshness, security, and
consumer RBAC.

# Production Standards

## 65.103 Common Mistakes

Avoid wrong consumer identifiers, raw operational sharing, `SELECT *`,
unnecessary PII/PHI, missing usage/object privileges, adding consumers
before grant review, overly broad shares, missing
contracts/versioning/reviews/expiration/inventory/revocation procedures,
assuming all cross-region/cloud topologies work identically, and blaming
provider storage before investigating consumer compute.

## 65.104 Production Standards

Every consumer should have documented justification and independently
verified identifiers. Every shared dataset should have an owner. Prefer
dedicated sharing layers, explicit columns, minimum necessary data,
classification, secure views, grant review, separate shares for
different contracts, controlled consumer RBAC, documented freshness,
API-like schema management, versioning, notifications, periodic access
reviews, topology validation, emergency revocation, and end-to-end
validation.

## 65.105 SRE/DBRE Cross-Account Sharing Checklist

Validate business purpose, provider/consumer accounts, consumer
identifier, owners, classification, security/compliance review, sharing
schema, secure view, explicit columns, filters, sensitive exclusions,
share and grants, consumer authorization, imported database, consumer
role/warehouse, row counts, schema, representative records, freshness,
security boundary, monitoring, inventory, review date, offboarding, and
emergency revocation.

## 65.106 Operational Quick Reference

Provider: verify consumer → classify → sharing schema → secure view →
share → grants → review → authorize.

Consumer: discover share → create imported database → local role →
imported privileges → warehouse → query → validate → monitor.

## 65.107 Key Takeaways

1.  Secure Cross-Account Data Sharing provides governed
    account-to-account access.
2.  Traditional export/import pipelines are not required for standard
    secure sharing.
3.  The provider retains source-data control.
4.  The consumer generally supplies query compute.
5.  Provider and consumer security responsibilities are separate.
6.  Verify provider and consumer account context.
7.  Never guess account identifiers.
8.  Maintain consumer inventory.
9.  Prefer a dedicated sharing schema.
10. Prefer curated secure consumer-facing views.
11. Avoid `SELECT *`.
12. Share minimum necessary data.
13. Use row filtering where required.
14. Use aggregation where detail is unnecessary.
15. Classification remains applicable after sharing.
16. Review grants before authorization.
17. Separate shares when contracts differ.
18. Consumers should use controlled RBAC.
19. Validate provider/consumer row counts.
20. Validate schema and representative records.
21. Define freshness expectations.
22. Treat shared schemas as APIs/data contracts.
23. Review new columns as potential exposure.
24. Version breaking changes.
25. Use controlled deprecation.
26. Validate cross-region/cloud topology.
27. Troubleshoot consumer performance from consumer compute/query layers
    first.
28. Unauthorized exposure is a security incident.
29. Maintain onboarding, offboarding, and emergency-revocation runbooks.
30. Perform end-to-end validation after significant sharing changes.

## 65.108 Chapter Completion Checklist

After completing this chapter, you should be able to explain Secure
Cross-Account Data Sharing; provider/consumer and compute boundaries;
verify accounts/identifiers; maintain inventory; design sharing schemas
and secure views; apply explicit columns, minimum necessary, filtering,
aggregation, and classification; create/configure shares and grants;
authorize consumers; configure imported databases, warehouses, and RBAC;
validate data/security/freshness; manage changes/versioning/deprecation;
evaluate cross-region/cloud considerations; monitor/troubleshoot
sharing; respond to accidental removal/drop and unauthorized exposure;
execute onboarding/offboarding/emergency runbooks; and apply SRE/DBRE
production standards.

**Chapter 65 --- Snowflake Secure Cross-Account Data Sharing: Complete**
