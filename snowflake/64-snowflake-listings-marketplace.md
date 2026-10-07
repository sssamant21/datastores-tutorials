# Chapter 64 --- Snowflake Listings & Snowflake Marketplace

## 64.1 Overview

Snowflake Listings provide a governed mechanism for providers to
distribute supported data products to consumers through Snowflake.
Listings can support private, organization-specific, commercial, or
Marketplace distribution and build on secure data-sharing concepts.

## 64.2 Why Listings Matter

Direct Secure Data Sharing works well for known consumer accounts.
Listings provide a higher-level distribution model with improved
discoverability, lifecycle management, onboarding, and data-product
governance.

## 64.3 Secure Sharing vs. Listings

Secure Shares are suited to direct account-to-account sharing. Listings
package a consumer-facing data product for controlled discovery and
access.

## 64.4 Snowflake Marketplace

Snowflake Marketplace enables supported data products to be discovered
and accessed through Snowflake, reducing the need for custom delivery
pipelines.

## 64.5 Listing Types

At a high level, distribution may include private,
organization/internal, and Marketplace/public models. Validate current
Snowflake capabilities before production implementation.

## 64.6 Private Listings

Use private listings for specifically approved customers, partners,
subsidiaries, vendors, or internal accounts.

## 64.7 Marketplace Listings

Marketplace listings support broader distribution of governed data
products such as industry, financial, geospatial, healthcare reference,
demographic, security-intelligence, or business-reference datasets.

## 64.8 Provider Responsibilities

Providers own data quality, security, classification, contracts,
documentation, freshness, schema stability, support, lifecycle, and
compliance. Treat a listing as a production data product.

## 64.9 Consumer Responsibilities

Consumers must review the product and terms, control local access,
manage compute, monitor usage, manage downstream dependencies, and
validate suitability.

# Data Product Design

## 64.10 Do Not Publish Raw Production Schemas

Do not expose raw, staging, internal, temporary, or pipeline-metadata
schemas. Build a curated data-product layer.

## 64.11 Dedicated Data Product Schema

``` sql
CREATE SCHEMA IF NOT EXISTS PROD_DB.DATA_PRODUCTS;
```

## 64.12 Consumer-Facing Secure View

``` sql
CREATE OR REPLACE SECURE VIEW
PROD_DB.DATA_PRODUCTS.CUSTOMER_MARKET_SUMMARY AS
SELECT
    STATE,
    CUSTOMER_SEGMENT,
    COUNT(*) AS CUSTOMER_COUNT
FROM PROD_DB.CUSTOMER.CUSTOMER_PROFILE
GROUP BY STATE, CUSTOMER_SEGMENT;
```

## 64.13 Explicit Columns

Avoid `SELECT *`. Explicit columns reduce accidental exposure when
source schemas evolve.

## 64.14 Minimum Necessary Data

Expose only the data consumers actually need.

## 64.15 Sensitive Data Review

Review PII, PHI, PCI, financial information, credentials, internal
identifiers, restricted attributes, and contract-restricted data before
publication.

## 64.16 Aggregation

When detailed records are unnecessary, publish aggregates at the
required business grain.

## 64.17 Data Product Contract

Document purpose, objects, columns, data types, definitions, refresh
frequency, historical coverage, limitations, support, change policy, and
deprecation policy.

# Provider Preparation

## 64.18 Provider Readiness Checklist

Confirm data/business/technical ownership, classification,
security/legal/compliance review, contract, quality, refresh process,
schema stability, support, and lifecycle.

## 64.19 Validate Source Freshness

``` sql
SELECT MAX(UPDATED_AT) AS LAST_UPDATE
FROM PROD_DB.CUSTOMER.CUSTOMER_PROFILE;
```

## 64.20 Validate Row Counts

``` sql
SELECT COUNT(*)
FROM PROD_DB.DATA_PRODUCTS.CUSTOMER_MARKET_SUMMARY;
```

## 64.21 Validate Nulls

``` sql
SELECT
    COUNT_IF(STATE IS NULL) AS NULL_STATE,
    COUNT_IF(CUSTOMER_SEGMENT IS NULL) AS NULL_SEGMENT
FROM PROD_DB.DATA_PRODUCTS.CUSTOMER_MARKET_SUMMARY;
```

## 64.22 Validate Duplicates

``` sql
SELECT BUSINESS_KEY, COUNT(*)
FROM PROD_DB.DATA_PRODUCTS.PRODUCT_DATA
GROUP BY BUSINESS_KEY
HAVING COUNT(*) > 1;
```

## 64.23 Validate Sensitive Columns

``` sql
DESCRIBE VIEW PROD_DB.DATA_PRODUCTS.CUSTOMER_MARKET_SUMMARY;
```

# Creating the Listing

## 64.24 Listing Creation

Use Snowflake-supported listing interfaces. Exact workflows depend on
distribution type, provider profile, commercial model, region/cloud,
product type, and current capabilities.

## 64.25 Listing Name

Use consumer-friendly product names rather than internal implementation
names.

## 64.26 Listing Description

Describe contents, audience, coverage, history, refresh frequency, use
cases, and limitations.

## 64.27 Consumer Documentation

Include schema, definitions, sample queries, freshness expectations,
support, and change policy.

## 64.28 Example Consumer Documentation

Dataset: Customer Market Summary. Refresh: daily. Coverage: United
States. History: 24 months. Grain: State + Customer Segment + Month.

## 64.29 Sample Query

``` sql
SELECT STATE, CUSTOMER_SEGMENT, CUSTOMER_COUNT
FROM <LISTING_DATABASE>.DATA_PRODUCTS.CUSTOMER_MARKET_SUMMARY
WHERE STATE = 'NC'
ORDER BY CUSTOMER_SEGMENT;
```

# Private Listing

## 64.30 Private Distribution Model

A provider publishes a private listing to specifically approved
consumers.

## 64.31 Private Listing Use Cases

Strategic customers, healthcare partners, vendors, subsidiaries, joint
ventures, and contracted analytics partners.

## 64.32 Consumer Approval

Verify identity, business relationship, contract, data-use purpose,
security/compliance approval, and expiration/review date.

## 64.33 Consumer Onboarding

Approve consumer → grant listing access → consumer obtains product →
validate access/data → production use.

# Marketplace

## 64.34 Marketplace Publication

Marketplace publication requires product ownership, documentation,
support, quality, commercial/legal terms, communication, and version
management.

## 64.35 Marketplace Product Quality

Products should be accurate, documented, stable, fresh, discoverable,
supported, secure, and governed.

## 64.36 Product Metadata

Provide title, description, category, provider information, coverage,
refresh frequency, sample data, documentation, and support.

## 64.37 Data Dictionary

  Column             Type      Description
  ------------------ --------- -------------------------
  STATE              VARCHAR   U.S. state code
  CUSTOMER_SEGMENT   VARCHAR   Customer market segment
  CUSTOMER_COUNT     NUMBER    Number of customers
  REPORT_MONTH       DATE      Reporting month

## 64.38 Free and Commercial Products

Commercial models depend on current Snowflake capabilities and provider
eligibility. Validate current contractual and commercial requirements.

# Consumer Experience

## 64.39 Consumer Discovery

Review provider, dataset, description, terms, coverage, freshness,
schema, commercial terms, and support.

## 64.40 Consumer Gets Listing

After approval/acquisition, consumers receive access according to
listing configuration.

## 64.41 Consumer Database

Database acquisition behavior depends on listing type and current
Snowflake interfaces.

## 64.42 Consumer Compute

Consumers generally use their own Snowflake compute to query listing
data.

## 64.43 Consumer RBAC

Use controlled local roles such as `MARKETPLACE_DATA_READER`.

## 64.44 Consumer Warehouse

``` sql
CREATE WAREHOUSE IF NOT EXISTS MARKETPLACE_WH
WITH WAREHOUSE_SIZE='XSMALL'
AUTO_SUSPEND=60
AUTO_RESUME=TRUE;
```

## 64.45 Consumer Validation

Validate database, schemas, objects, columns, row counts, freshness, and
representative records.

# Data Quality

## 64.46 Listings Need Data Quality SLOs

Define measurable freshness, completeness, availability, and
schema-stability expectations.

## 64.47 Freshness Validation

``` sql
SELECT MAX(REPORT_DATE)
FROM PROD_DB.DATA_PRODUCTS.CUSTOMER_MARKET_SUMMARY;
```

## 64.48 Volume Validation

``` sql
SELECT COUNT(*)
FROM PROD_DB.DATA_PRODUCTS.CUSTOMER_MARKET_SUMMARY;
```

## 64.49 Distribution Validation

``` sql
SELECT STATE, COUNT(*)
FROM PROD_DB.DATA_PRODUCTS.CUSTOMER_MARKET_SUMMARY
GROUP BY STATE
ORDER BY STATE;
```

## 64.50 Data Quality Pipeline

Source → transformation → quality checks → data product → listing. Do
not knowingly publish corrupted data.

# Schema Evolution

## 64.51 Listings Are Data Contracts

Once consumers depend on listing schemas, schema changes become
production changes.

## 64.52 Safe Additive Change

Even additive changes require classification, documentation, impact
review, testing, and communication.

## 64.53 Breaking Change

Removing/renaming columns, changing types, grain, semantics, or filters
requires controlled migration.

## 64.54 Versioned Product

Use parallel versions such as `CUSTOMER_MARKET_SUMMARY_V1` and
`CUSTOMER_MARKET_SUMMARY_V2` for significant changes.

## 64.55 Deprecation Process

Announce → migration guide → parallel versions → monitor adoption →
final notice → retire old version.

# Security and Governance

## 64.56 Least Data Exposure

Expose only intended data products.

## 64.57 Data Classification

Classify each listing appropriately, such as Public, Internal,
Confidential, or Restricted.

## 64.58 PHI/PII

Evaluate legal authority, contracts, consent where applicable, minimum
necessary, de-identification, masking, aggregation, consumer controls,
and jurisdiction.

## 64.59 Data Rights

Verify redistribution rights for third-party or derived data.

## 64.60 Listing Approval Workflow

Data Owner → Security → Compliance/Legal → Product Owner → Platform/DBRE
→ Publication.

## 64.61 Change Approval

Formal change management should cover sensitive fields, contracts,
commercial terms, sources, refresh frequency, retention, and geographic
coverage.

# Monitoring

## 64.62 Provider Monitoring

Monitor source pipelines, freshness, quality, availability, schema,
consumer-facing objects, security changes, usage, and cost.

## 64.63 Consumer Monitoring

Monitor database availability, query failures, schema changes,
freshness, warehouse cost, and downstream failures.

## 64.64 Listing Inventory

Maintain listing type, owner, data product, classification, and review
cadence.

## 64.65 Consumer Inventory

For private products track consumer, purpose, approval, contract,
status, review date, and expiration.

# Cost

## 64.66 Provider Costs

Potential costs include storage, transformation compute, validation,
preparation, replication, and support.

## 64.67 Consumer Costs

Consumers generally provide query compute and should monitor warehouse
size, runtime, concurrency, query efficiency, and auto-suspend.

## 64.68 Cross-Region Considerations

Cross-region/cloud distribution may add replication, availability,
architecture, and cost considerations.

# Troubleshooting

## 64.69 Consumer Cannot Find Listing

Check account, visibility, private authorization, listing state,
region/cloud availability, and provider publication state.

## 64.70 Consumer Cannot Access Product

Check acquisition/approval, authorization, database, consumer
role/warehouse, and provider state.

## 64.71 Object Missing

Check provider data product, listing contents, consumer database/schema,
and recent provider changes.

## 64.72 Data Missing

Trace source → transformation → consumer-facing view → listing →
consumer.

## 64.73 Data Stale

Check source ingestion, transformation schedules, task/pipeline
failures, product, and freshness timestamps.

## 64.74 Query Slow

Check consumer warehouse sizing/queueing, query design, scans, pruning,
and concurrency.

## 64.75 Schema Changed Unexpectedly

Investigate deployments, view replacements, source changes, automation,
change records, and versioning.

## 64.76 Consumer Reports Wrong Data

Validate consumer query/filters, listing object, provider view,
transformation, source data, and business definition.

# Incident Management

## 64.77 Listing Incident Types

Missing/stale/incorrect data, unauthorized exposure, schema breaks,
unavailable listings, access failures, and performance issues.

## 64.78 Security Incident

Contain → restrict access → preserve evidence → identify consumers →
assess exposure → engage security/compliance.

## 64.79 Data Quality Incident

Identify scope → stop bad pipeline where applicable → preserve evidence
→ correct → validate → communicate → monitor → RCA.

## 64.80 Consumer Communication

Include affected listing, issue, data/time window, impact, status,
workaround, next update, and resolution.

# Listing Lifecycle

## 64.81 Lifecycle

Idea → design → security/legal review → build → validate → publish →
operate → version → deprecate → retire.

## 64.82 Periodic Review

Review purpose, owners, classification, quality, freshness, schema
documentation, consumers/contracts, cost, and ongoing need.

## 64.83 Listing Retirement

Identify consumers/dependencies → communicate → replacement/migration →
stop new adoption → remove access → preserve evidence.

# Production Runbooks

## 64.84 Listing Publication Runbook

1.  Define use case.
2.  Assign product owner.
3.  Identify source.
4.  Verify distribution rights.
5.  Classify data.
6.  Complete security review.
7.  Complete legal/compliance review.
8.  Define contract.
9.  Create data-product schema.
10. Create secure objects.
11. Validate sensitive exposure.
12. Validate quality.
13. Validate freshness.
14. Define SLOs.
15. Create listing.
16. Configure audience.
17. Add documentation.
18. Add sample queries.
19. Test consumer experience.
20. Obtain approval.
21. Publish.
22. Monitor.

## 64.85 Private Consumer Onboarding Runbook

Receive request → verify identity/relationship/purpose → approve → grant
access → consumer obtains product → validate → record consumer → assign
review/expiration.

## 64.86 Listing Change Runbook

Define change → compatibility → classification → impact → contract →
test → approval → notify → deploy → validate → monitor.

## 64.87 Listing Retirement Runbook

Approve → inventory consumers/dependencies → announce → migration
guidance → stop onboarding → monitor migration → final notice → remove →
preserve evidence → update inventory.

# Production Scenario

## 64.88 Healthcare Market Dataset

A healthcare organization distributes market statistics while keeping
patient-level PHI out of the product.

## 64.89 Build Aggregated Product

``` sql
CREATE OR REPLACE SECURE VIEW
PROD_DB.DATA_PRODUCTS.HEALTHCARE_MARKET_SUMMARY AS
SELECT
    STATE,
    DATE_TRUNC('MONTH', SERVICE_DATE) AS SERVICE_MONTH,
    DIAGNOSIS_CATEGORY,
    COUNT(DISTINCT PATIENT_ID) AS PATIENT_COUNT
FROM PROD_DB.CLINICAL.ACTIVITY
GROUP BY STATE, DATE_TRUNC('MONTH', SERVICE_DATE), DIAGNOSIS_CATEGORY;
```

## 64.90 Validate Product

``` sql
SELECT
    MIN(SERVICE_MONTH) AS FIRST_MONTH,
    MAX(SERVICE_MONTH) AS LAST_MONTH,
    COUNT(*) AS ROW_COUNT
FROM PROD_DB.DATA_PRODUCTS.HEALTHCARE_MARKET_SUMMARY;
```

## 64.91 Data Quality Validation

``` sql
SELECT
    COUNT_IF(STATE IS NULL) AS NULL_STATE,
    COUNT_IF(SERVICE_MONTH IS NULL) AS NULL_MONTH,
    COUNT_IF(DIAGNOSIS_CATEGORY IS NULL) AS NULL_CATEGORY
FROM PROD_DB.DATA_PRODUCTS.HEALTHCARE_MARKET_SUMMARY;
```

## 64.92 Consumer Sample Query

``` sql
SELECT
    SERVICE_MONTH,
    SUM(PATIENT_COUNT) AS PATIENT_COUNT
FROM <LISTING_DATABASE>.DATA_PRODUCTS.HEALTHCARE_MARKET_SUMMARY
WHERE STATE = 'NC'
GROUP BY SERVICE_MONTH
ORDER BY SERVICE_MONTH;
```

## 64.93 Validate Privacy Boundary

Confirm patient ID, name, DOB, SSN, address, phone, email,
medical-record identifiers, and other unapproved PHI are not exposed.

# Operational Standards

## 64.94 Common Listing Mistakes

Avoid raw operational schemas, `SELECT *`, unnecessary sensitive data,
missing
owners/dictionaries/freshness/quality/contracts/versioning/support/inventory/retirement,
breaking changes without notice, assuming Marketplace removes compliance
duties, and ignoring cross-region or consumer-compute implications.

## 64.95 Production Standards

Every listing should have product/technical owners, verified
distribution rights, classification, minimum necessary curated data,
explicit columns, quality/freshness validation, documented
contracts/sample queries, controlled versioning, approved private
consumers, lifecycle reviews, support ownership, sensitive-data review,
cross-region evaluation, incident management, and retirement procedures.

## 64.96 SRE/DBRE Listing Checklist

Validate purpose, owners, source, rights, classification, security/legal
approval, data-product schema, secure views, explicit columns, sensitive
exclusions, quality/freshness/baselines, dictionary, contract, SLOs,
listing/audience, documentation/sample queries, consumer experience,
monitoring, support, change/versioning, consumer reviews, incident
process, and retirement.

## 64.97 Operational Quick Reference

Source → classify → verify rights → curate → secure view →
quality/freshness → listing → private/Marketplace consumer → monitor →
version/retire.

## 64.98 Key Takeaways

1.  Listings provide structured Snowflake data-product distribution.
2.  Listings build on secure sharing.
3.  Private listings support controlled distribution.
4.  Marketplace supports broader discovery/distribution.
5.  Treat listings as production data products.
6.  Do not expose raw schemas unnecessarily.
7.  Use dedicated data-product schemas.
8.  Prefer curated secure objects.
9.  Avoid `SELECT *`.
10. Expose minimum necessary data.
11. Govern sensitive data.
12. Verify distribution rights.
13. Document contracts.
14. Provide a data dictionary.
15. Document freshness.
16. Validate quality before publication.
17. Define measurable SLOs.
18. Consumers generally supply query compute.
19. Consumers should use local RBAC.
20. Schema changes can break consumers.
21. Version breaking changes.
22. Use controlled deprecation.
23. Maintain private-consumer inventories.
24. Monitor provider pipelines/listing health.
25. Monitor freshness/quality.
26. Treat incorrect data as a production incident.
27. Treat unauthorized exposure as a security incident.
28. Review cross-region/cloud architecture.
29. Manage lifecycle/retirement.
30. Marketplace operation requires product, security, operations, and
    governance ownership.

## 64.99 Chapter Completion Checklist

After this chapter you should be able to explain Listings/Marketplace;
compare them with Secure Sharing; design private/Marketplace
distribution; define responsibilities; create curated schemas/views;
apply minimum-necessary and sensitive-data controls; define
contracts/dictionaries/SLOs; validate freshness/quality;
document/onboard consumers; understand consumer compute/RBAC; manage
schema evolution/versioning/deprecation; monitor/troubleshoot listings;
manage incidents/lifecycle; execute publication/change/retirement
runbooks; and apply SRE/DBRE production standards.

**Chapter 64 --- Snowflake Listings & Snowflake Marketplace: Complete**
