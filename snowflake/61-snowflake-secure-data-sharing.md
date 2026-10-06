# Chapter 61 --- Snowflake Secure Data Sharing

## 61.1 Overview

Snowflake Secure Data Sharing allows a provider to share selected
Snowflake data with another Snowflake account without copying the
underlying data into the consumer account.

Conceptually:

``` text
Provider Account
      |
      | Secure Share
      v
Consumer Account
      |
      v
Imported Database
```

The provider controls what is shared. The consumer accesses shared data
through its own Snowflake compute.

## 61.2 Why Secure Data Sharing Matters

Traditional data exchange often requires export, file creation,
transfer, copying, loading, and synchronization. Secure Data Sharing
removes much of this operational pipeline.

## 61.3 Provider and Consumer

The provider account exposes data. The consumer account receives
controlled access to the shared data.

## 61.4 No Traditional Data Copy

The consumer does not normally receive a separate physical copy through
Secure Data Sharing. This reduces export pipelines, file transfers,
duplicate storage, synchronization jobs, and copy delays.

## 61.5 Consumer Compute

The provider shares data while the consumer generally uses its own
virtual warehouse to query the imported shared database.

## 61.6 Basic Sharing Architecture

A production database exposes selected objects through a secure share,
and the consumer creates an imported database from that share.

## 61.7 Create a Share

``` sql
CREATE SHARE CUSTOMER_DATA_SHARE;

SHOW SHARES;
```

## 61.8 Grant Database Usage

``` sql
GRANT USAGE
ON DATABASE PROD_DB
TO SHARE CUSTOMER_DATA_SHARE;
```

## 61.9 Grant Schema Usage

``` sql
GRANT USAGE
ON SCHEMA PROD_DB.CUSTOMER
TO SHARE CUSTOMER_DATA_SHARE;
```

## 61.10 Grant Table Access

``` sql
GRANT SELECT
ON TABLE PROD_DB.CUSTOMER.CUSTOMER_PROFILE
TO SHARE CUSTOMER_DATA_SHARE;
```

## 61.11 Complete Basic Provider Example

``` sql
CREATE SHARE CUSTOMER_DATA_SHARE;

GRANT USAGE
ON DATABASE PROD_DB
TO SHARE CUSTOMER_DATA_SHARE;

GRANT USAGE
ON SCHEMA PROD_DB.CUSTOMER
TO SHARE CUSTOMER_DATA_SHARE;

GRANT SELECT
ON TABLE PROD_DB.CUSTOMER.CUSTOMER_PROFILE
TO SHARE CUSTOMER_DATA_SHARE;
```

## 61.12 Inspect Share Grants

``` sql
SHOW GRANTS TO SHARE CUSTOMER_DATA_SHARE;
```

Validate exactly what the share exposes.

## 61.13 Add a Consumer Account

``` sql
ALTER SHARE CUSTOMER_DATA_SHARE
ADD ACCOUNTS = <CONSUMER_ACCOUNT_IDENTIFIER>;
```

Use the correct organization/account identifier for the environment.

## 61.14 Consumer Creates Database

``` sql
CREATE DATABASE CUSTOMER_SHARED_DB
FROM SHARE <PROVIDER_ACCOUNT>.CUSTOMER_DATA_SHARE;
```

Use the exact provider identifier exposed to the consumer.

## 61.15 Query Shared Data

``` sql
SELECT *
FROM CUSTOMER_SHARED_DB.CUSTOMER.CUSTOMER_PROFILE
LIMIT 100;
```

## 61.16 Shared Data Is Read-Only

Secure Data Sharing is fundamentally controlled read access. The
consumer should not treat provider-owned shared tables as locally
writable tables.

## 61.17 Provider Controls Data Changes

When provider data changes, the consumer's shared view of current
provider data changes accordingly without a traditional export/reload
pipeline.

## 61.18 Sharing a Schema Is Not Automatic

Granting schema `USAGE` does not automatically expose every table.
Required object privileges must also be granted.

## 61.19 Share Only What Is Required

Apply least privilege. If a consumer needs only a customer summary, do
not expose unrelated customer addresses, payment information,
identifiers, or operational data.

## 61.20 Secure Views

``` sql
CREATE SECURE VIEW PROD_DB.SHARING.CUSTOMER_SHARED_V AS
SELECT
    CUSTOMER_ID,
    STATUS,
    STATE
FROM PROD_DB.CUSTOMER.CUSTOMER_PROFILE;
```

Expose curated secure views where appropriate instead of raw base
tables.

## 61.21 Why Secure Views Matter

Secure views can control exposed columns, business logic, derived
values, abstraction, and the consumer-facing schema.

## 61.22 Do Not Use SELECT \* for Consumer Contracts

Avoid:

``` sql
CREATE SECURE VIEW SHARED_CUSTOMER AS
SELECT *
FROM CUSTOMER;
```

Prefer:

``` sql
CREATE SECURE VIEW SHARED_CUSTOMER AS
SELECT
    CUSTOMER_ID,
    STATUS,
    STATE
FROM CUSTOMER;
```

Explicit columns reduce accidental future exposure.

## 61.23 Sharing Sensitive Data

Classify data before sharing: public, internal, confidential, PII, PHI,
PCI, financial, restricted, or other organization-specific classes.

## 61.24 PHI/PII Review

Validate business purpose, approved consumer, required columns/rows,
minimum necessary data, masking/filtering requirements,
legal/compliance/security approval, retention expectations, and
revocation procedures.

## 61.25 Masking Policies and Sharing

Validate masking-policy behavior for the actual sharing architecture and
consumer context. Do not assume internal masking automatically makes
every share safe.

## 61.26 Row Access Policies

When different consumers require different subsets, design and test
row-level controls against the actual consumer context.

## 61.27 Provider Contract Layer

A strong pattern is production data → dedicated sharing schema → secure
views → secure share → consumer.

## 61.28 Dedicated Sharing Schema

``` sql
CREATE SCHEMA PROD_DB.SHARING;
```

Use a curated sharing layer rather than exposing operational schemas
directly where practical.

## 61.29 Consumer-Facing View

``` sql
CREATE SECURE VIEW PROD_DB.SHARING.CUSTOMER_SUMMARY AS
SELECT
    CUSTOMER_ID,
    STATUS,
    STATE,
    CREATED_DATE
FROM PROD_DB.CUSTOMER.CUSTOMER_PROFILE;
```

## 61.30 Grant Sharing Schema

``` sql
GRANT USAGE
ON SCHEMA PROD_DB.SHARING
TO SHARE CUSTOMER_DATA_SHARE;
```

## 61.31 Grant Secure View

``` sql
GRANT SELECT
ON VIEW PROD_DB.SHARING.CUSTOMER_SUMMARY
TO SHARE CUSTOMER_DATA_SHARE;
```

Validate all required Snowflake sharing privileges for referenced
objects.

## 61.32 Provider Sharing Pattern

Production base data → consumer-facing secure view → share → approved
consumer.

## 61.33 Multiple Consumers

A provider can support multiple consumers, but determine whether each
should receive identical data and controls.

## 61.34 One Share vs. Multiple Shares

Use one share when consumers have the same approved dataset and
lifecycle. Use separate shares when tables, columns, regions, security
policies, contracts, lifecycle, or ownership differ.

## 61.35 Share Naming Standard

Use descriptive names such as:

-   `CUSTOMER_ANALYTICS_SHARE`
-   `PARTNER_CLAIMS_SHARE`
-   `FINANCE_REPORTING_SHARE`
-   `VENDOR_X_PATIENT_SUMMARY_SHARE`

Avoid ambiguous names such as `SHARE1`.

## 61.36 Share Ownership

Every production share should have a business owner, technical owner,
data owner, classification, approved consumers, purpose, review date,
and lifecycle/expiration.

## 61.37 Share Inventory

Maintain an inventory of share, consumer, data, owner, classification,
and review cadence.

## 61.38 Inspect Existing Shares

``` sql
SHOW SHARES;
```

## 61.39 Inspect Share Contents

``` sql
SHOW GRANTS TO SHARE CUSTOMER_DATA_SHARE;
```

Review for unexpected tables, old schemas, sensitive objects, temporary
objects, and deprecated views.

## 61.40 Consumer Access Review

Periodically confirm that consumers remain active, authorized,
contractually valid, and limited to required data.

## 61.41 Remove Consumer Access

``` sql
ALTER SHARE CUSTOMER_DATA_SHARE
REMOVE ACCOUNTS = <CONSUMER_ACCOUNT_IDENTIFIER>;
```

Validate before and after revocation.

## 61.42 Revoke an Object

``` sql
REVOKE SELECT
ON TABLE PROD_DB.CUSTOMER.CUSTOMER_PROFILE
FROM SHARE CUSTOMER_DATA_SHARE;
```

Revoke the applicable view instead when using a consumer-facing view.

## 61.43 Drop a Share

``` sql
DROP SHARE CUSTOMER_DATA_SHARE;
```

Perform consumer-impact review first.

## 61.44 Share Lifecycle

Request → classification → security approval → design → implementation →
consumer validation → production → periodic review → revoke/retire.

## 61.45 Share Request Requirements

Capture consumer, business purpose, requested datasets/columns/rows,
classification, expected duration, consumer account identifier,
business/technical owners, and security approval.

## 61.46 Share Change Management

Treat production share changes like API/data-contract changes. Adding or
removing columns, rows, views, tables, or policies can affect consumers.

## 61.47 Consumer Contract

Document object names, columns, data types, business definitions,
freshness behavior, ownership, support process, change policy, and
deprecation policy.

## 61.48 Schema Evolution

Assess consumer compatibility, downstream pipelines, BI reports,
applications, and data contracts before changing consumer-facing
schemas.

## 61.49 Version Consumer Interfaces

For breaking changes, consider parallel interfaces such as
`CUSTOMER_SUMMARY_V1` and `CUSTOMER_SUMMARY_V2` to allow migration.

## 61.50 Do Not Expose Internal Implementation

Avoid exposing staging tables, temporary transformations, internal IDs,
pipeline metadata, debug columns, and operational-only fields unless
explicitly required.

## 61.51 Share Performance

Consumer query performance depends on consumer warehouse sizing, query
design, data volume, pruning, clustering characteristics, concurrency,
and caching behavior.

## 61.52 Provider Compute

Ordinary consumer queries use consumer compute, so the provider does not
need to run an export warehouse for every delivery.

## 61.53 Provider Cost Considerations

Monitor storage, lifecycle, sharing administration, transformation
workloads, replication requirements, and governance overhead.

## 61.54 Consumer Cost Considerations

Consumers should manage warehouse size, auto-suspend, query
optimization, concurrency, workload isolation, and resource monitors.

## 61.55 Shared Data Freshness

Sharing removes separate export/import synchronization delay, but
business freshness still depends on when the provider updates the
underlying data.

## 61.56 Data Sharing Is Not Replication

Sharing provides access to provider data. Replication creates supported
secondary copies. They solve different problems.

## 61.57 Data Sharing Is Not Backup

A consumer's shared access is not automatically a provider backup
strategy.

## 61.58 Data Sharing Is Not DR

Secure Data Sharing alone does not provide region/account/cross-cloud
failover or application continuity.

## 61.59 Sharing and Data Ownership

The provider remains responsible for source data and the sharing
contract. Consumers depend on provider-controlled data and lifecycle.

## 61.60 Consumer Dependency Risk

If a production application depends on shared data, document SLO/SLA
expectations, change process, support contacts, incident escalation, and
deprecation policy.

## 61.61 Provider Incident Impact

Bad ETL, DELETE, schema changes, view failures, policy errors, or
revocation can affect consumers. Include sharing in incident response.

## 61.62 Consumer Incident Investigation

Investigate provider source data, secure view, share grants, consumer
authorization, object changes, policies, upstream pipeline, and consumer
query.

## 61.63 Troubleshooting --- Consumer Cannot See Share

Check share existence, consumer account identifier, authorization,
hierarchy/object grants, provider object existence, and consumer
provider/share identifier.

## 61.64 Troubleshooting --- Consumer Cannot Query Object

Check object grant, database/schema usage, SELECT, secure-view
dependencies, imported database source, and consumer warehouse
availability.

## 61.65 Troubleshooting --- Data Missing

Determine whether data is missing from provider base table, secure view,
share, or consumer query result. Test each layer.

## 61.66 Troubleshooting --- Unexpected Columns

Check base-table changes, `SELECT *`, view-definition changes, and
whether the wrong shared object is being queried.

## 61.67 Troubleshooting --- Access Suddenly Lost

Investigate consumer removal, share drop, privilege revocation, source
changes, secure-view replacement, policy changes, and account-identifier
changes.

## 61.68 Troubleshooting --- Query Slow

Check consumer warehouse sizing/queueing, query design, scan size,
pruning, concurrency, provider data model, and data growth before
blaming the share.

## 61.69 Sharing Audit

``` sql
SHOW SHARES;

SHOW GRANTS TO SHARE CUSTOMER_DATA_SHARE;
```

Combine SQL review with governance metadata.

## 61.70 Monthly Share Review

Review owner, business purpose, consumer, required objects/columns,
sensitive data, policies, contract, deprecated objects, and expiration.

## 61.71 Security Review

Review PII, PHI, PCI, secrets, internal identifiers, restricted
attributes, masking, row filtering, consumer environment, and regulatory
restrictions.

## 61.72 Share Deployment Runbook

1.  Receive request.
2.  Identify consumer.
3.  Verify account identifier.
4.  Document business purpose.
5.  Classify data.
6.  Obtain approvals.
7.  Determine minimum required rows/columns.
8.  Create sharing schema if appropriate.
9.  Create secure consumer-facing views.
10. Validate view output.
11. Create share.
12. Grant database usage.
13. Grant schema usage.
14. Grant required objects.
15. Add approved consumer.
16. Review grants.
17. Consumer creates imported database.
18. Consumer validates access.
19. Validate sensitive-data controls.
20. Record ownership.
21. Record lifecycle/review date.
22. Monitor and recertify.

## 61.73 Share Removal Runbook

Confirm approval, consumers, dependencies, communication, removal time,
and current configuration. Then remove the consumer, revoke objects, or
drop the share. Validate access removal and update
inventory/documentation/change records.

## 61.74 Emergency Share Revocation

For a security incident: contain exposure → revoke access → validate
containment → preserve evidence → investigate.

## 61.75 Share Configuration Example

``` sql
CREATE SHARE PARTNER_CUSTOMER_SHARE;

GRANT USAGE
ON DATABASE PROD_DB
TO SHARE PARTNER_CUSTOMER_SHARE;

GRANT USAGE
ON SCHEMA PROD_DB.SHARING
TO SHARE PARTNER_CUSTOMER_SHARE;

GRANT SELECT
ON VIEW PROD_DB.SHARING.CUSTOMER_SUMMARY
TO SHARE PARTNER_CUSTOMER_SHARE;
```

Then authorize the approved consumer using the appropriate Snowflake
account identifier.

## 61.76 Consumer Configuration Example

``` sql
CREATE DATABASE PARTNER_CUSTOMER_DB
FROM SHARE <PROVIDER_ACCOUNT>.PARTNER_CUSTOMER_SHARE;

SELECT *
FROM PARTNER_CUSTOMER_DB.SHARING.CUSTOMER_SUMMARY
LIMIT 100;
```

## 61.77 Validate Provider Data

``` sql
SELECT COUNT(*)
FROM PROD_DB.SHARING.CUSTOMER_SUMMARY;
```

## 61.78 Validate Consumer Data

``` sql
SELECT COUNT(*)
FROM PARTNER_CUSTOMER_DB.SHARING.CUSTOMER_SUMMARY;
```

Validate representative business records as well.

## 61.79 Data Contract Validation

Validate object name, columns, types, required fields, business keys,
filters, sensitive-data exclusions, freshness, and consumer query
behavior.

## 61.80 Production Scenario

A healthcare partner requires only `PATIENT_ID`, `STATUS`, and `STATE`,
while the source table also contains names, date of birth, SSN, address,
phone, and email.

Do not expose the whole table.

``` sql
CREATE SECURE VIEW PROD_DB.SHARING.PARTNER_PATIENT_SUMMARY AS
SELECT
    PATIENT_ID,
    STATUS,
    STATE
FROM PROD_DB.EMPI.PATIENT;
```

Expose only this approved contract through the share.

## 61.81 Production Change Scenario

Adding a sensitive column such as `DATE_OF_BIRTH` to a consumer-facing
view is new data exposure. Review consumer need, classification,
approval, contract, masking, and compliance before deployment.

## 61.82 Sharing Maturity Model

Maturity progresses from ad-hoc sharing → controlled ownership →
governed schemas/views/classification/approval → versioned data products
with monitoring/SLOs → enterprise automation, policy enforcement,
contract validation, usage monitoring, lifecycle automation,
recertification, and incident integration.

## 61.83 Common Secure Data Sharing Mistakes

Avoid unnecessary raw-table sharing, `SELECT *`, sensitive overexposure,
giant universal shares, undocumented consumers/owners, ignored consumer
dependencies, unannounced schema changes, assuming sharing masks data,
treating sharing as backup/DR, leaving former consumers authorized,
leaving deprecated objects exposed, ignoring secure-view dependencies,
skipping validation, and failing periodic review.

## 61.84 Production Standards

Every production share should have an owner, documented business
purpose, explicitly approved consumer, data classification, minimum
necessary rows/columns, curated secure views where appropriate, explicit
columns, sensitive-data review, least privilege, validated account
identifiers, documented configuration, versioned contracts where
appropriate, controlled breaking changes, documented dependencies,
periodic review, prompt removal of former consumers/deprecated objects,
emergency revocation, and separate backup/DR strategy.

## 61.85 SRE/DBRE Secure Sharing Checklist

Validate business purpose, provider owner, consumer identity/account,
data/security/compliance approval, classification, minimum rows/columns,
sensitive controls, sharing schema, secure views, explicit columns,
share/database/schema/object grants, consumer authorization, grant
review, imported database, consumer query, business data, contract,
monitoring, review date, and revocation process.

## 61.86 Operational Quick Reference

Create share → grant database usage → grant schema usage → grant
approved objects → add approved consumer → verify grants → consumer
creates database → validate → monitor/review.

## 61.87 Key Takeaways

1.  Secure Data Sharing provides controlled access without traditional
    export/import copying.
2.  The provider owns and manages source data.
3.  Consumers use their own compute.
4.  Apply least privilege.
5.  Grant only required objects.
6.  Schema usage does not automatically expose every table.
7.  Secure views provide useful consumer-facing interfaces.
8.  Dedicated sharing schemas improve governance.
9.  Avoid `SELECT *`.
10. Explicit columns reduce accidental exposure.
11. Classify production data before sharing.
12. Apply PII/PHI governance.
13. Sharing does not automatically mask data.
14. Test policy behavior for actual consumers.
15. Different consumers may require separate shares.
16. Every share needs ownership and purpose.
17. Review consumer access periodically.
18. Remove old consumers.
19. Manage shared-object changes carefully.
20. Treat consumer interfaces as data contracts.
21. Version breaking changes where appropriate.
22. Consumer compute still incurs cost.
23. Sharing is not replication.
24. Sharing is not backup.
25. Sharing is not DR.
26. Document production consumer dependencies.
27. Provider incidents can affect consumers.
28. Include sharing in incident response.
29. Maintain emergency revocation procedures.
30. Govern sharing throughout its lifecycle.

## 61.88 Chapter Completion Checklist

After this chapter you should be able to explain provider/consumer roles
and no-copy sharing; create shares and required grants; authorize
consumers; create/query imported databases; understand consumer compute;
design sharing schemas and secure views; avoid unnecessary base-table
exposure; apply least privilege and sensitive-data controls; manage
multiple consumers; define naming/ownership/inventory;
inspect/revoke/retire shares; manage schema evolution/versioned
contracts; troubleshoot access/data/performance; audit and review
shares; execute deployment/removal/emergency-revocation runbooks;
validate provider/consumer data; and apply production sharing standards.

**Chapter 61 --- Snowflake Secure Data Sharing: Complete**
