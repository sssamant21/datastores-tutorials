# Chapter 62 --- Snowflake Provider & Consumer Configuration

## 62.1 Overview

This chapter builds on Chapter 61 and focuses on operational
configuration of Snowflake Secure Data Sharing from both sides: provider
configuration, secure sharing, consumer imported databases, validation,
troubleshooting, governance, and safe production operation.

## 62.2 Provider Responsibilities

The provider identifies approved data, creates consumer-facing objects
and shares, grants required privileges, authorizes consumers, protects
sensitive data, manages schema changes, monitors configuration, revokes
access, and supports consumers.

## 62.3 Consumer Responsibilities

The consumer supplies the correct account identifier, creates an
imported database, configures local RBAC and compute, validates shared
data, manages cost/downstream dependencies, and reports sharing issues.

## 62.4 End-to-End Architecture

Provider production data is exposed through a dedicated sharing layer
and secure share. The consumer creates an imported database and queries
it using consumer-managed compute.

# Provider Configuration

## 62.5 Step 1 --- Confirm Provider Context

``` sql
SELECT
    CURRENT_ACCOUNT(),
    CURRENT_ROLE(),
    CURRENT_DATABASE(),
    CURRENT_SCHEMA();
```

Never assume you are connected to the intended production account.

## 62.6 Step 2 --- Confirm Consumer Account Identifier

Obtain the consumer's approved Snowflake account identifier. Record
organization/account, environment, business owner, and technical owner.
Do not guess identifiers.

## 62.7 Step 3 --- Validate Sharing Request

Confirm business purpose, consumer approval, dataset approval,
data-owner approval, security/compliance review, minimum rows/columns,
and expected lifecycle.

## 62.8 Step 4 --- Identify Source Objects

Document the source database, schema, and objects before designing the
consumer contract.

## 62.9 Inspect Source Table

``` sql
DESCRIBE TABLE PROD_DB.CUSTOMER.CUSTOMER_PROFILE;
```

Review columns, types, sensitive data, business keys, internal metadata,
and operational columns.

## 62.10 Review Sample Data

``` sql
SELECT
    CUSTOMER_ID,
    STATUS,
    STATE
FROM PROD_DB.CUSTOMER.CUSTOMER_PROFILE
LIMIT 20;
```

Use approved access and avoid unnecessary exposure of sensitive data.

## 62.11 Step 5 --- Create Sharing Schema

``` sql
CREATE SCHEMA IF NOT EXISTS PROD_DB.SHARING;
```

A dedicated sharing schema provides a clear consumer contract layer.

## 62.12 Why Use a Sharing Schema

Benefits include ownership clarity, auditing, reduced accidental
exposure, stable interfaces, lifecycle management, and separation from
operational objects.

## 62.13 Step 6 --- Create Consumer-Facing Secure View

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

Use only approved columns.

## 62.14 Validate Secure View

``` sql
SELECT *
FROM PROD_DB.SHARING.CUSTOMER_SUMMARY
LIMIT 100;
```

Validate columns, rows, transformations, filters, data types, and
sensitive-data exclusions.

## 62.15 Validate View Definition

``` sql
SELECT GET_DDL(
    'VIEW',
    'PROD_DB.SHARING.CUSTOMER_SUMMARY'
);
```

Store important production definitions in version control.

## 62.16 Avoid SELECT \*

Avoid consumer contracts based on `SELECT *`; explicit columns reduce
accidental future exposure and uncontrolled contract changes.

## 62.17 Step 7 --- Create Share

``` sql
CREATE SHARE CUSTOMER_DATA_SHARE;

SHOW SHARES LIKE 'CUSTOMER_DATA_SHARE';
```

## 62.18 Step 8 --- Grant Database Usage

``` sql
GRANT USAGE
ON DATABASE PROD_DB
TO SHARE CUSTOMER_DATA_SHARE;
```

## 62.19 Step 9 --- Grant Schema Usage

``` sql
GRANT USAGE
ON SCHEMA PROD_DB.SHARING
TO SHARE CUSTOMER_DATA_SHARE;
```

## 62.20 Step 10 --- Grant Consumer-Facing Object

``` sql
GRANT SELECT
ON VIEW PROD_DB.SHARING.CUSTOMER_SUMMARY
TO SHARE CUSTOMER_DATA_SHARE;
```

Validate any additional privileges required by the shared-object design.

## 62.21 Validate Share Grants

``` sql
SHOW GRANTS TO SHARE CUSTOMER_DATA_SHARE;
```

Expected exposure should exactly match the approved contract.

## 62.22 Provider Validation Gate

Before adding the consumer, confirm correct database/schema/view,
columns/filters, sensitive-data controls, grants, and security behavior.

## 62.23 Step 11 --- Authorize Consumer

``` sql
ALTER SHARE CUSTOMER_DATA_SHARE
ADD ACCOUNTS = <CONSUMER_ACCOUNT_IDENTIFIER>;
```

Use the exact approved identifier.

## 62.24 Verify Consumer Authorization

Inspect share metadata/configuration and confirm authorization
succeeded.

## 62.25 Provider Configuration Summary

Source table → secure view → create share → database usage → schema
usage → object SELECT → add consumer.

# Consumer Configuration

## 62.26 Consumer Receives Provider Information

Provider supplies provider account identifier, share name, approved
dataset/contract, support contact, and change policy.

## 62.27 Step 1 --- Confirm Consumer Context

``` sql
SELECT
    CURRENT_ACCOUNT(),
    CURRENT_ROLE();
```

## 62.28 Step 2 --- Inspect Available Shares

Confirm the expected provider/share identity is visible before creating
the imported database.

## 62.29 Step 3 --- Create Imported Database

``` sql
CREATE DATABASE CUSTOMER_SHARED_DB
FROM SHARE <PROVIDER_ACCOUNT>.CUSTOMER_DATA_SHARE;
```

Use the exact provider/share identifier available to the consumer.

## 62.30 Verify Imported Database

``` sql
SHOW DATABASES LIKE 'CUSTOMER_SHARED_DB';
```

## 62.31 Inspect Schemas

``` sql
SHOW SCHEMAS IN DATABASE CUSTOMER_SHARED_DB;
```

## 62.32 Inspect Shared Objects

``` sql
SHOW VIEWS IN SCHEMA CUSTOMER_SHARED_DB.SHARING;
```

## 62.33 Query Shared Data

``` sql
SELECT *
FROM CUSTOMER_SHARED_DB.SHARING.CUSTOMER_SUMMARY
LIMIT 100;
```

## 62.34 Consumer Needs Compute

The imported database does not provide a warehouse. The consumer
supplies its own query compute.

## 62.35 Create Consumer Warehouse

``` sql
CREATE WAREHOUSE IF NOT EXISTS SHARED_DATA_WH
WITH
    WAREHOUSE_SIZE = 'XSMALL'
    AUTO_SUSPEND = 60
    AUTO_RESUME = TRUE;
```

Size according to workload.

## 62.36 Use Consumer Warehouse

``` sql
USE WAREHOUSE SHARED_DATA_WH;

SELECT *
FROM CUSTOMER_SHARED_DB.SHARING.CUSTOMER_SUMMARY
LIMIT 100;
```

# Consumer RBAC

## 62.37 Do Not Give Every User Direct Access

Use consumer-side RBAC rather than unmanaged direct access.

## 62.38 Create Consumer Role

``` sql
CREATE ROLE CUSTOMER_SHARED_READER;
```

## 62.39 Grant Imported Database Privileges

``` sql
GRANT IMPORTED PRIVILEGES
ON DATABASE CUSTOMER_SHARED_DB
TO ROLE CUSTOMER_SHARED_READER;
```

Use Snowflake's applicable imported-database privilege model.

## 62.40 Grant Warehouse Usage

``` sql
GRANT USAGE
ON WAREHOUSE SHARED_DATA_WH
TO ROLE CUSTOMER_SHARED_READER;
```

## 62.41 Grant Role to User

``` sql
GRANT ROLE CUSTOMER_SHARED_READER
TO USER <CONSUMER_USER>;
```

Prefer role hierarchy over large numbers of direct user grants.

## 62.42 Validate Consumer Role

``` sql
USE ROLE CUSTOMER_SHARED_READER;
USE WAREHOUSE SHARED_DATA_WH;

SELECT *
FROM CUSTOMER_SHARED_DB.SHARING.CUSTOMER_SUMMARY
LIMIT 10;
```

## 62.43 Consumer Access Architecture

Provider share → imported database → controlled consumer role →
authorized users → consumer warehouse.

## 62.44 Consumer Least Privilege

Use separate roles for separate shared domains where needed rather than
granting every imported database to a universal analytics role.

# Validation

## 62.45 Provider Row Count

``` sql
SELECT COUNT(*)
FROM PROD_DB.SHARING.CUSTOMER_SUMMARY;
```

## 62.46 Consumer Row Count

``` sql
SELECT COUNT(*)
FROM CUSTOMER_SHARED_DB.SHARING.CUSTOMER_SUMMARY;
```

## 62.47 Validate Representative Records

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

## 62.48 Validate Column Contract

Validate column names, data types, required fields, business
definitions, and consumer expectations---not only row counts.

## 62.49 Validate Sensitive-Data Exclusion

Confirm consumers cannot see unapproved fields such as SSNs, secrets,
payment-card data, unapproved PHI, or internal security metadata.

## 62.50 Validate Freshness

Use controlled, production-safe validation to confirm consumers see
expected current provider data without an export/import cycle.

# Provider Changes

## 62.51 Add a New Shared Object

``` sql
CREATE SECURE VIEW PROD_DB.SHARING.ORDER_SUMMARY AS
SELECT
    ORDER_ID,
    CUSTOMER_ID,
    ORDER_DATE,
    STATUS
FROM PROD_DB.SALES.ORDERS;

GRANT SELECT
ON VIEW PROD_DB.SHARING.ORDER_SUMMARY
TO SHARE CUSTOMER_DATA_SHARE;
```

## 62.52 Consumer Sees New Shared Object

After correct provider exposure, the consumer can access the object
through the imported database subject to applicable privileges and
contract.

## 62.53 Add a Column

Treat additions as contract changes: request → classification → impact
analysis → approval → deploy → validate.

## 62.54 Breaking Change

For major incompatible changes, consider parallel versioned objects such
as `CUSTOMER_SUMMARY_V1` and `CUSTOMER_SUMMARY_V2`.

## 62.55 Remove a Shared Object

``` sql
REVOKE SELECT
ON VIEW PROD_DB.SHARING.ORDER_SUMMARY
FROM SHARE CUSTOMER_DATA_SHARE;
```

Communicate planned production removals unless emergency containment
requires immediate action.

## 62.56 Remove Consumer

``` sql
ALTER SHARE CUSTOMER_DATA_SHARE
REMOVE ACCOUNTS = <CONSUMER_ACCOUNT_IDENTIFIER>;
```

Validate intended access loss.

# Multiple Consumers

## 62.57 Same Dataset

One share can be appropriate when multiple consumers require exactly the
same approved dataset and controls.

## 62.58 Different Dataset Requirements

Separate shares improve governance when consumers require different
data, classifications, contracts, or lifecycle.

## 62.59 Avoid Consumer-Specific Logic Everywhere

Prefer a clear consumer-specific contract layer rather than scattered
conditions across operational objects.

# Troubleshooting

## 62.60 Provider --- Share Not Visible to Consumer

Check share existence, consumer identifier, successful authorization,
share configuration, and provider-supplied identity.

## 62.61 Provider --- Object Missing

``` sql
SHOW GRANTS TO SHARE CUSTOMER_DATA_SHARE;
```

Check database usage, schema usage, object SELECT, and any required
referenced-object privileges.

## 62.62 Consumer --- Cannot Create Database

Check provider identifier, share name, consumer authorization, share
existence, and local role privileges.

## 62.63 Consumer --- Database Exists but Query Fails

Check consumer role, imported privileges, warehouse/warehouse usage,
shared object, provider grants, and provider object state.

## 62.64 Consumer --- No Warehouse

``` sql
USE WAREHOUSE SHARED_DATA_WH;
```

## 62.65 Consumer --- Data Missing

Provider base:

``` sql
SELECT COUNT(*)
FROM PROD_DB.CUSTOMER.CUSTOMER_PROFILE;
```

Provider contract:

``` sql
SELECT COUNT(*)
FROM PROD_DB.SHARING.CUSTOMER_SUMMARY;
```

Consumer:

``` sql
SELECT COUNT(*)
FROM CUSTOMER_SHARED_DB.SHARING.CUSTOMER_SUMMARY;
```

Identify the first layer where the discrepancy appears.

## 62.66 Consumer --- Unexpected Data

Check secure-view definition, row filters, masking behavior, source
data, provider deployments, and consumer query filters.

## 62.67 Consumer --- Query Slow

Check consumer warehouse sizing/queueing, query profile, scan volume,
pruning, concurrency, provider data design, and data growth.

## 62.68 Provider --- View Broken

Treat consumer-facing views as production interfaces. Base-table changes
can break consumer access.

## 62.69 Provider --- Accidental Revocation

Confirm incident, determine consumers, preserve evidence, restore
approved privileges, validate access, monitor, and perform RCA when
warranted.

# Monitoring and Governance

## 62.70 Provider Monitoring

Monitor shares, grants, consumer authorization, secure-view health,
source pipelines, schema changes, and policy changes.

## 62.71 Consumer Monitoring

Monitor imported-database availability, query failures, warehouse
health/queueing, freshness, schema changes, and downstream failures.

## 62.72 Provider Inventory

Maintain share, consumer, object, owner, classification, and review
cadence.

## 62.73 Consumer Inventory

Maintain imported database, provider, purpose, local role, owner, and
dependencies.

## 62.74 Provider Access Review

Review consumer approval, business purpose, required objects,
sensitive-data appropriateness, view definition, owner, and expiration.

## 62.75 Consumer Access Review

Review local user need, role appropriateness, warehouse access,
downstream dependencies, and ongoing provider-contract requirement.

# Security

## 62.76 Provider Security Principles

Use minimum necessary data, secure views, explicit columns, approved
consumers, least privilege, ownership, recertification, and emergency
revocation.

## 62.77 Consumer Security Principles

Imported-data access still requires RBAC, least privilege, auditing,
user lifecycle, warehouse controls, data-use policy, and regulatory
compliance.

## 62.78 Production Data Boundary

Treat the secure consumer-facing view as an external data boundary.
Anything exposed through it should be intentional.

# Operational Runbooks

## 62.79 Provider Onboarding Runbook

1.  Receive request.
2.  Validate consumer.
3.  Verify account identifier.
4.  Classify data.
5.  Obtain approvals.
6.  Identify minimum data.
7.  Create sharing schema.
8.  Create secure view.
9.  Validate view.
10. Create share.
11. Grant database usage.
12. Grant schema usage.
13. Grant approved objects.
14. Review grants.
15. Add consumer.
16. Validate provider configuration.
17. Send share identity to consumer.
18. Consumer creates database.
19. Perform end-to-end validation.
20. Record ownership/review date.

## 62.80 Consumer Onboarding Runbook

1.  Receive provider/share identity.
2.  Verify provider.
3.  Confirm expected dataset.
4.  Create imported database.
5.  Verify schemas/objects.
6.  Create local role.
7.  Grant imported privileges.
8.  Configure warehouse access.
9.  Grant local role.
10. Query shared data.
11. Validate row count.
12. Validate columns.
13. Validate representative records.
14. Validate sensitive-data expectations.
15. Document dependencies.
16. Begin monitoring.

## 62.81 Consumer Offboarding Runbook

Provider confirms approval, notifies the consumer, removes account
access, and validates revocation. Consumer stops dependencies, removes
local access, drops the imported database when appropriate, and updates
inventory.

## 62.82 Emergency Revocation Runbook

Declare security incident → identify share/consumers → remove affected
access → revoke objects if required → validate containment → preserve
evidence → determine exposure → engage security/compliance → restore
access only after approval.

# Production Scenario

## 62.83 Scenario

A healthcare data-platform provider shares only `PATIENT_ID`, `STATUS`,
and `STATE` with an approved analytics partner even though the source
contains more sensitive information.

## 62.84 Provider Configuration

``` sql
CREATE OR REPLACE SECURE VIEW
PROD_DB.SHARING.PARTNER_PATIENT_SUMMARY AS
SELECT
    PATIENT_ID,
    STATUS,
    STATE
FROM PROD_DB.EMPI.PATIENT;

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

Authorize only the approved partner account.

## 62.85 Consumer Configuration

``` sql
CREATE DATABASE PATIENT_SHARED_DB
FROM SHARE <PROVIDER_ACCOUNT>.PARTNER_PATIENT_SHARE;

CREATE ROLE PATIENT_SHARED_READER;

GRANT IMPORTED PRIVILEGES
ON DATABASE PATIENT_SHARED_DB
TO ROLE PATIENT_SHARED_READER;

GRANT USAGE
ON WAREHOUSE SHARED_DATA_WH
TO ROLE PATIENT_SHARED_READER;
```

## 62.86 End-to-End Validation

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

Then verify representative records and approved columns.

## 62.87 Failure Scenario

If the imported database is visible but a shared view cannot be queried,
investigate consumer warehouse, local role, imported privileges,
imported database, provider share, share grants, secure view, base
table, security policies, and recent changes---in that order rather than
immediately recreating the share.

## 62.88 Common Configuration Mistakes

Avoid wrong provider/consumer identifiers, unnecessary raw-table
sharing, missing hierarchy/object grants, unvalidated secure-view
dependencies, `SELECT *`, missing consumer warehouse, missing imported
privileges, excessive local access, unannounced contract changes,
accidental consumer removal, missing ownership/review dates, missing
emergency revocation, and skipped end-to-end validation.

## 62.89 Production Standards

Verify provider/consumer identifiers, approve every request, prefer a
dedicated sharing layer, expose minimum necessary data, use explicit
columns, classify sensitive data, review grants before authorization,
explicitly validate consumer authorization, use consumer RBAC/least
privilege, maintain inventories, treat shared interfaces as production
contracts, control breaking changes, monitor both sides, recertify
access, document emergency revocation, and validate every significant
change end to end.

## 62.90 Provider Checklist

Validate consumer, purpose, classification, source, sharing schema,
secure view, explicit columns, sensitive exclusions, view output, share
creation, database/schema/object grants, grant review, consumer
authorization, authorization verification, ownership, review date, and
consumer notification.

## 62.91 Consumer Checklist

Validate provider/share identity, imported database/schemas/objects,
consumer role, imported privileges, warehouse/access, local users/roles,
successful query, row counts, columns, representative records,
sensitive-data expectations, dependencies, and monitoring.

## 62.92 Provider/Consumer Quick Reference

Provider: create secure view → create share → grant
database/schema/object access → add consumer → verify.

Consumer: create imported database → create local role → grant imported
privileges → configure warehouse → grant local access → query →
validate.

## 62.93 Key Takeaways

1.  Secure Data Sharing requires provider and consumer configuration.
2.  Verify account context before production changes.
3.  Never guess consumer identifiers.
4.  Validate requests before implementation.
5.  Dedicated sharing schemas provide a strong contract layer.
6.  Secure views minimize exposure.
7.  Avoid `SELECT *`.
8.  Understand the consumer contract before creating the share.
9.  Database/schema hierarchy privileges are required.
10. Explicit object privileges are required.
11. Review grants before authorizing consumers.
12. Consumers create imported databases from provider shares.
13. Imported databases do not provide compute.
14. Consumers use their own warehouses.
15. Consumer access should use RBAC.
16. Imported privileges should be granted to controlled roles.
17. Validate provider/consumer row counts.
18. Validate columns and representative records.
19. Validate sensitive-data exclusions.
20. Treat shared objects as production contracts.
21. Version breaking changes when appropriate.
22. Separate shares when requirements differ.
23. Troubleshoot sharing layer by layer.
24. Consumer slowness may be a compute/query issue.
25. Monitor both provider and consumer environments.
26. Periodically review access.
27. Maintain emergency revocation.
28. Document onboarding/offboarding.
29. Validate significant changes end to end.
30. Provider and consumer operational ownership is essential.

## 62.94 Chapter Completion Checklist

After this chapter you should be able to configure provider-side
sharing, verify account context/consumer identifiers, design a sharing
schema and secure views, create shares and grants, authorize consumers,
validate share grants, configure imported databases and consumer
compute/RBAC, grant imported privileges, validate data and sensitive
boundaries, add/remove shared objects, handle contract changes/multiple
consumers, troubleshoot both sides, monitor sharing infrastructure,
maintain inventories/access reviews, execute
onboarding/offboarding/emergency revocation, perform end-to-end
validation, and apply production standards.

**Chapter 62 --- Snowflake Provider & Consumer Configuration: Complete**
