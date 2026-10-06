# Chapter 63 --- Snowflake Reader Accounts

## 63.1 Overview

Snowflake Reader Accounts allow a data provider to share data with
consumers who do not have their own full Snowflake account.

The provider creates and manages the Reader Account and shares approved
data with it.

## 63.2 Why Reader Accounts Exist

Standard Secure Data Sharing assumes the consumer already has a
Snowflake account. Reader Accounts provide an alternative for approved
consumers that do not.

## 63.3 Reader Account Terminology

Reader Accounts are associated with managed accounts. The provider
creates and manages the account used by the reader consumer.

## 63.4 Standard Consumer vs. Reader Account

With standard sharing, the consumer manages and pays for its own
Snowflake compute. With a Reader Account, the provider creates/manages
the account and is responsible for associated usage and cost.

## 63.5 Reader Account Architecture

Provider production data → consumer-facing secure view → secure share →
Reader Account → Reader warehouse → Reader users.

## 63.6 Primary Reader Account Use Cases

Potential uses include external partners without Snowflake, customer
reporting, vendors requiring controlled data access, temporary
consumers, client-facing analytics, and controlled data-product
delivery.

## 63.7 Reader Account Decision

If the consumer already has Snowflake, standard Secure Data Sharing is
usually cleaner. If not, evaluate whether a Reader Account is justified.

## 63.8 Provider Responsibility

The provider may manage account lifecycle, users, roles, warehouses,
security, authentication, cost, monitoring, reviews, and offboarding.
Treat Reader Accounts as managed production environments.

## 63.9 Cost Responsibility

Reader warehouse compute creates provider-associated cost, making cost
controls especially important.

## 63.10 Reader Account Request Requirements

Capture consumer organization, purpose, data, expected users/query
volume/concurrency/duration, classification, business/technical/cost
owners, and required security/compliance approvals.

## 63.11 Account Naming Standard

Use meaningful names such as `PARTNER_ACME_READER`,
`CLIENT_REPORTING_READER`, or `VENDOR_CLAIMS_READER`.

## 63.12 Create Reader Account

Conceptual administrative pattern:

``` sql
CREATE MANAGED ACCOUNT <READER_ACCOUNT_NAME>
ADMIN_NAME = <ADMIN_USER>
ADMIN_PASSWORD = '<INITIAL_PASSWORD>';
```

Validate exact current Snowflake syntax, authentication requirements,
availability, and privileges before production execution.

## 63.13 Password Handling

Do not store Reader credentials in Git, tickets, Slack, or
documentation. Use the organization's approved secret-distribution
process.

## 63.14 Initial Administrator

Establish named ownership, secure authentication, role separation,
credential rotation, and auditability. Avoid long-term shared
administrative credentials.

## 63.15 Identify Reader Account

Record organization/account identifiers, locator where operationally
required, region, environment, owners, creation date, and
review/expiration date.

# Provider Share Configuration

## 63.16 Create Consumer Contract

``` sql
CREATE OR REPLACE SECURE VIEW
PROD_DB.SHARING.READER_CUSTOMER_SUMMARY AS
SELECT
    CUSTOMER_ID,
    STATUS,
    STATE
FROM PROD_DB.CUSTOMER.CUSTOMER_PROFILE;
```

## 63.17 Validate Consumer Contract

``` sql
SELECT *
FROM PROD_DB.SHARING.READER_CUSTOMER_SUMMARY
LIMIT 100;
```

Validate approved columns/rows, filters, business logic, and
sensitive-data exclusions.

## 63.18 Create Share

``` sql
CREATE SHARE CUSTOMER_READER_SHARE;
```

## 63.19 Grant Database Usage

``` sql
GRANT USAGE
ON DATABASE PROD_DB
TO SHARE CUSTOMER_READER_SHARE;
```

## 63.20 Grant Schema Usage

``` sql
GRANT USAGE
ON SCHEMA PROD_DB.SHARING
TO SHARE CUSTOMER_READER_SHARE;
```

## 63.21 Grant Secure View

``` sql
GRANT SELECT
ON VIEW PROD_DB.SHARING.READER_CUSTOMER_SUMMARY
TO SHARE CUSTOMER_READER_SHARE;
```

Validate all privileges required by the actual sharing design.

## 63.22 Validate Share

``` sql
SHOW GRANTS TO SHARE CUSTOMER_READER_SHARE;
```

Ensure no unapproved objects are exposed.

## 63.23 Authorize Reader Account

``` sql
ALTER SHARE CUSTOMER_READER_SHARE
ADD ACCOUNTS = <READER_ACCOUNT_IDENTIFIER>;
```

Use the exact Snowflake identifier.

# Reader Account Configuration

## 63.24 Connect to Reader Account

``` sql
SELECT
    CURRENT_ACCOUNT(),
    CURRENT_USER(),
    CURRENT_ROLE();
```

Verify administration is occurring in the intended account.

## 63.25 Shared Data Availability

Validate that the expected provider share/database is available before
configuring users.

## 63.26 Reader Account Compute

``` sql
CREATE WAREHOUSE READER_WH
WITH
    WAREHOUSE_SIZE = 'XSMALL'
    AUTO_SUSPEND = 60
    AUTO_RESUME = TRUE;
```

Start small and scale from measured workload.

## 63.27 Why Start X-Small

Reader workloads are often reporting, dashboard queries, partner
lookups, or light analytics. Oversizing can create unnecessary provider
cost.

## 63.28 Auto-Suspend

``` sql
ALTER WAREHOUSE READER_WH
SET AUTO_SUSPEND = 60;
```

## 63.29 Auto-Resume

``` sql
ALTER WAREHOUSE READER_WH
SET AUTO_RESUME = TRUE;
```

# Reader RBAC

## 63.30 Do Not Use Administrator for Queries

Create controlled roles for normal consumer analytics rather than using
administrative roles.

## 63.31 Create Reader Role

``` sql
CREATE ROLE READER_DATA_USER;
```

## 63.32 Grant Shared Data Access

``` sql
GRANT IMPORTED PRIVILEGES
ON DATABASE <SHARED_DATABASE>
TO ROLE READER_DATA_USER;
```

Use the applicable shared/imported database privilege model.

## 63.33 Grant Warehouse Access

``` sql
GRANT USAGE
ON WAREHOUSE READER_WH
TO ROLE READER_DATA_USER;
```

## 63.34 Create Reader User

``` sql
CREATE USER PARTNER_USER_01
DEFAULT_ROLE = READER_DATA_USER
DEFAULT_WAREHOUSE = READER_WH;
```

Configure authentication according to current Snowflake and
organizational security requirements.

## 63.35 Grant Role to Reader User

``` sql
GRANT ROLE READER_DATA_USER
TO USER PARTNER_USER_01;
```

## 63.36 Validate User

``` sql
USE ROLE READER_DATA_USER;
USE WAREHOUSE READER_WH;
```

Then query only the approved shared object.

## 63.37 Reader Access Model

Shared data → controlled Reader role → named users → dedicated Reader
warehouse.

## 63.38 Separate Consumer Roles

Use separate roles such as `READER_CUSTOMER_ROLE`, `READER_CLAIMS_ROLE`,
and `READER_FINANCE_ROLE` when users require different datasets.

# Security

## 63.39 Reader Account Security Boundary

Treat the Reader Account as an external consumer environment even though
the provider manages it. Expose only approved information.

## 63.40 Sensitive Data

Classify PII/PHI/PCI and review minimum necessary data, sensitive-column
exclusion, masking, row filtering, security approval, and compliance
approval.

## 63.41 Authentication

Use current Snowflake and organizational authentication standards and
stronger supported controls where appropriate.

## 63.42 User Lifecycle

Every user should have an owner, purpose, role, creation date, review
date, and expiration where appropriate.

## 63.43 No Shared User Accounts

Prefer individually attributable identities rather than one shared
partner login used by many people.

## 63.44 Administrative Access

Limit administrative privileges to authorized provider administrators.
Reader consumers should not need administration privileges for normal
queries.

# Cost Governance

## 63.45 Why Cost Governance Is Critical

Reader warehouse usage creates provider-associated credit consumption,
so Reader Accounts require strong cost visibility.

## 63.46 Dedicated Warehouse

Dedicated Reader warehouses improve cost attribution, workload
isolation, sizing, monitoring, suspension, and troubleshooting.

## 63.47 Avoid Oversizing

Do not start with large warehouses without evidence. Start with the
smallest size that satisfies workload requirements.

## 63.48 Warehouse Auto-Suspend

``` sql
ALTER WAREHOUSE READER_WH
SET AUTO_SUSPEND = 60;
```

## 63.49 Resource Monitoring

Where supported/applicable, monitor credit consumption, warehouse
runtime, query volume, concurrency, and unexpected growth.

## 63.50 Cost Owner

Every Reader Account should have a named cost owner and review cadence.

## 63.51 Cost Thresholds

Define expected, warning, and critical usage thresholds based on the
business case.

## 63.52 Unexpected Cost Investigation

Investigate warehouse runtime, size, auto-suspend, query frequency,
dashboard refreshes, concurrency, long queries, retries, automation, and
data growth.

# Monitoring

## 63.53 Reader Account Monitoring

Monitor account availability, authentication failures, warehouse
state/credits, query failures/latency, data freshness, and shared-data
availability.

## 63.54 Provider Monitoring

Monitor share health, secure views, source pipelines, Reader
authorization/cost, security events, and schema changes.

## 63.55 Consumer Query Monitoring

Review long-running/frequent/failed queries, large scans, unexpected
users, and abnormal workload patterns.

## 63.56 Data Freshness Monitoring

Reader freshness depends on provider source ingestion and
transformation. A Reader Account cannot make stale provider data fresh.

# Troubleshooting

## 63.57 Reader Cannot Log In

Check account identifier, user existence/status, authentication,
credentials, network/security policy, and role configuration.

## 63.58 Reader Cannot See Data

Check provider share, Reader authorization, shared database, imported
privileges, Reader role, secure view, and provider source object.

## 63.59 Reader Has No Warehouse

``` sql
SHOW WAREHOUSES;

USE WAREHOUSE READER_WH;
```

## 63.60 Warehouse Permission Error

``` sql
SHOW GRANTS ON WAREHOUSE READER_WH;
```

Confirm required warehouse privileges.

## 63.61 Shared Database Permission Error

Check the Reader role's shared/imported database privileges. Do not
solve ordinary access issues by granting administration roles.

## 63.62 Missing Data

Trace source table → secure view → share → Reader Account and identify
the first layer where data differs.

## 63.63 Slow Query

Check warehouse size/queueing, query profile, scan volume, pruning,
concurrency, data growth, and query design before scaling.

## 63.64 High Reader Cost

Check runtime, auto-suspend, warehouse size, query frequency,
dashboards, concurrency, long queries, and automated consumers.

## 63.65 Provider Revoked Access

Investigate consumer removal, object revocation, share drop,
secure-view/source changes, and security incidents.

## 63.66 Secure View Failure

Provider schema changes can break consumer contracts. Treat this as a
production incident when Reader consumers depend on the data.

# Lifecycle Management

## 63.67 Reader Account Inventory

Maintain account name/identifier, consumer, purpose, owners, users,
roles, warehouses, shares, classification, creation/review/expiration
dates.

## 63.68 Monthly Review

Review consumer/business purpose, users/roles, required data, sensitive
controls, warehouse sizing, cost, share requirement, and expiration.

## 63.69 User Offboarding

Disable users promptly, verify access removal, remove unnecessary
grants, and update inventory.

## 63.70 Reader Account Offboarding

Notify stakeholders → stop consumer access → remove share authorization
→ disable users → suspend warehouses → preserve audit evidence → retire
the Reader Account using the supported process.

## 63.71 Suspend Compute Before Retirement

``` sql
ALTER WAREHOUSE READER_WH
SUSPEND;
```

## 63.72 Remove Share Authorization

``` sql
ALTER SHARE CUSTOMER_READER_SHARE
REMOVE ACCOUNTS = <READER_ACCOUNT_IDENTIFIER>;
```

Validate access removal.

## 63.73 Preserve Audit Evidence

Retain required account ownership, users, role grants, share
configuration, usage, cost, security/access reviews, and change records.

# Production Runbooks

## 63.74 Reader Account Provisioning Runbook

1.  Receive request.
2.  Confirm a Reader Account is appropriate.
3.  Document business purpose.
4.  Identify/classify data.
5.  Obtain approvals.
6.  Assign business/technical/security/cost owners.
7.  Create Reader Account.
8.  Secure administrator access.
9.  Record identifiers.
10. Create consumer contract/secure view.
11. Create share and grants.
12. Authorize Reader Account.
13. Configure warehouse and auto-suspend.
14. Create roles and named users.
15. Grant minimum access.
16. Validate data/security/cost controls.
17. Document account.
18. Establish review cadence.

## 63.75 Reader User Provisioning Runbook

Receive approved request → confirm identity → determine data/role →
create named user → configure authentication → grant approved role →
configure default warehouse → test login/query → record owner/review
date.

## 63.76 Reader User Removal Runbook

Confirm request → disable user → verify access removed → review grants →
preserve evidence → update inventory.

## 63.77 Reader Account Retirement Runbook

Confirm approval → identify dependencies → notify consumer → define
window → capture configuration → disable users → suspend warehouses →
remove share authorization → validate revocation → preserve evidence →
retire using supported process → update inventory/cost allocation/change
record.

# Production Scenario

## 63.78 Scenario

A healthcare analytics partner without a Snowflake account needs
aggregate patient status by state, not patient-level PHI.

## 63.79 Provider Contract

``` sql
CREATE OR REPLACE SECURE VIEW
PROD_DB.SHARING.PARTNER_PATIENT_COUNTS AS
SELECT
    STATE,
    STATUS,
    COUNT(*) AS PATIENT_COUNT
FROM PROD_DB.EMPI.PATIENT
GROUP BY
    STATE,
    STATUS;
```

## 63.80 Create Reader Share

``` sql
CREATE SHARE PARTNER_ANALYTICS_READER_SHARE;

GRANT USAGE
ON DATABASE PROD_DB
TO SHARE PARTNER_ANALYTICS_READER_SHARE;

GRANT USAGE
ON SCHEMA PROD_DB.SHARING
TO SHARE PARTNER_ANALYTICS_READER_SHARE;

GRANT SELECT
ON VIEW PROD_DB.SHARING.PARTNER_PATIENT_COUNTS
TO SHARE PARTNER_ANALYTICS_READER_SHARE;
```

Authorize only the approved Reader Account.

## 63.81 Reader Compute

``` sql
CREATE WAREHOUSE PARTNER_READER_WH
WITH
    WAREHOUSE_SIZE = 'XSMALL'
    AUTO_SUSPEND = 60
    AUTO_RESUME = TRUE;
```

## 63.82 Reader Role

``` sql
CREATE ROLE PARTNER_ANALYTICS_READER;
```

Grant only required shared-data and warehouse access.

## 63.83 Reader User

Create a named user with `PARTNER_ANALYTICS_READER` as the default role
and `PARTNER_READER_WH` as the default warehouse, using approved
authentication.

## 63.84 Validate Consumer Query

``` sql
SELECT
    STATE,
    STATUS,
    PATIENT_COUNT
FROM <SHARED_DATABASE>.SHARING.PARTNER_PATIENT_COUNTS
ORDER BY STATE, STATUS;
```

Validate against provider results.

## 63.85 Cost Validation

Monitor warehouse runtime, credits, queries/day, average duration,
concurrency, and auto-suspend behavior.

## 63.86 Security Validation

Confirm the consumer cannot access patient names, DOB, SSN, address,
phone, email, or other unapproved PHI.

# Reader Account vs. Alternatives

## 63.87 Reader Account vs. Standard Sharing

Use standard sharing when the consumer already has Snowflake and should
manage/pay for its own compute. Consider a Reader Account when the
consumer lacks Snowflake and the provider accepts management and cost
responsibility.

## 63.88 Reader Account vs. File Export

Reader Accounts can avoid recurring file exports/transfers and provide
governed SQL access. File export may be better for offline processing,
archive requirements, non-Snowflake interfaces, or regulatory
external-copy requirements.

## 63.89 Reader Account vs. Application/API

Reader Accounts suit SQL/data access. APIs may be better when business
logic must be enforced, consumers should not issue arbitrary SQL, or
application functions are required.

# Governance

## 63.90 Reader Account Governance Model

Assign business ownership for purpose/approval, technical ownership for
account/sharing/monitoring, security ownership for authentication/access
reviews, and cost ownership for warehouse/credit monitoring.

## 63.91 Reader Account Maturity Model

Maturity progresses from ad-hoc account/user/warehouse creation →
controlled ownership/roles/auto-suspend → governed
classification/views/cost/access reviews → automated
provisioning/monitoring/expiration → enterprise policy-as-code,
recertification, inventory, chargeback/showback, security monitoring,
automated offboarding, and contract governance.

## 63.92 Common Reader Account Mistakes

Avoid using Reader Accounts when standard sharing is sufficient,
raw-table sharing, unnecessary PII/PHI, `SELECT *`, shared users,
administrative consumer roles, oversized warehouses, disabled
auto-suspend, ignored cost, missing
owners/reviews/expiration/offboarding/retirement, missing
monitoring/security review/audit evidence, and missing consumer
contracts.

## 63.93 Production Standards

Reader Accounts require business justification and named
business/technical/security/cost ownership. Prefer standard sharing when
consumers already have Snowflake. Expose minimum necessary data through
curated secure views with explicit columns. Restrict administrative
roles, prefer named users, start warehouses small, enable auto-suspend,
monitor cost/usage, establish thresholds, review access, offboard
promptly, maintain lifecycle dates, document emergency revocation, and
use controlled retirement runbooks.

## 63.94 SRE/DBRE Reader Account Checklist

Validate business justification, standard-sharing evaluation, consumer
approval, classification, all owners, account creation/identifier/admin
security, sharing schema/view, sensitive-data minimization,
share/grants/authorization, warehouse sizing/auto-suspend, roles/named
users/minimum privileges/authentication, data/security/cost validation,
usage baseline, review date, offboarding, and retirement.

## 63.95 Operational Quick Reference

Business request → evaluate standard sharing → justify Reader Account →
create managed account → secure admin → create consumer contract →
create share → authorize Reader → configure warehouse → configure
roles/users → validate data/security → monitor cost/usage → periodic
review → offboard/retire.

## 63.96 Key Takeaways

1.  Reader Accounts support consumers without their own full Snowflake
    account.
2.  They are provider-created and provider-managed.
3.  Evaluate standard sharing first.
4.  Reader Accounts increase provider responsibility.
5.  Reader compute creates provider-associated cost.
6.  Cost ownership must be explicit.
7.  Business justification is required.
8.  Expose minimum necessary data.
9.  Avoid unnecessary raw production-table exposure.
10. Avoid `SELECT *`.
11. Govern sensitive data.
12. Use controlled authentication.
13. Prefer named users.
14. Do not give consumer users admin roles for normal queries.
15. Use dedicated Reader roles.
16. Use dedicated Reader warehouses where practical.
17. Start warehouses small.
18. Enable auto-suspend.
19. Monitor warehouse consumption.
20. Define cost thresholds.
21. Monitor query behavior.
22. Monitor provider data freshness.
23. Troubleshoot layer by layer.
24. Maintain inventory.
25. Review access periodically.
26. Offboard users promptly.
27. Retire unused Reader Accounts.
28. Preserve audit evidence.
29. Reader Accounts are not always the best external-sharing model.
30. Governance must cover security, cost, access, contracts, and
    lifecycle.

## 63.97 Chapter Completion Checklist

After this chapter you should be able to explain Reader Accounts and
when they are appropriate; compare them with standard sharing;
understand provider responsibilities/cost; define request and naming
standards; understand managed-account creation; secure administration;
create consumer contracts/views/shares; authorize Reader Accounts;
configure compute/auto-suspend/RBAC/named users; apply least privilege
and authentication; manage sensitive data/user lifecycle; monitor cost
and workloads; troubleshoot access/data/performance; maintain
inventory/reviews; offboard users/accounts; execute
provisioning/retirement runbooks; compare Reader Accounts with
files/APIs; and apply production governance standards.

**Chapter 63 --- Snowflake Reader Accounts: Complete**
