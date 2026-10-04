# 05 — Snowflake Editions, Regions & Cloud Platforms

**Status:** Canonical  
**Part:** 1 — Foundations & Architecture  
**Goal:** Understand Snowflake editions, cloud platforms, regions, account placement, feature availability, data residency, and production design considerations.

Snowflake supports accounts on AWS, Microsoft Azure, and Google Cloud. An account is deployed into a specific cloud platform and region.

## 1. Snowflake Deployment Model

```text
                     Snowflake
                         |
        +----------------+----------------+
        |                |                |
        v                v                v
       AWS             Azure         Google Cloud
        |                |                |
     Regions          Regions           Regions
        |                |                |
     Account          Account           Account
```

The storage, compute, and cloud-services architecture discussed earlier operates within the selected account deployment.

## 2. One Account Has One Region

A Snowflake account is hosted in a single region. Multi-region architectures use multiple accounts plus the appropriate replication, sharing, failover, or application patterns.

```text
Organization
|
+-- Account: PROD_US
|      +-- AWS us-east-1
|
+-- Account: DR_US
|      +-- AWS us-west-2
|
+-- Account: PROD_EU
       +-- Azure westeurope
```

Snowflake organizations can contain accounts in different regions and, where supported, different cloud platforms.

## 3. Supported Cloud Platforms

Primary platforms:

```text
AWS
Azure
Google Cloud
```

An organization does not need every account to use the same cloud provider.

Example:

```text
Organization
|
+-- PROD_AWS
|      +-- AWS
|
+-- ANALYTICS_AZURE
|      +-- Azure
|
+-- DATA_GCP
       +-- Google Cloud
```

This flexibility can be useful for acquisitions, regulatory requirements, cross-cloud data products, DR, or organizations already operating across multiple clouds.

## 4. Choosing a Cloud Platform

If an application stack already runs primarily in AWS:

```text
Application
    |
   AWS
    |
    +-- S3
    +-- EKS
    +-- MSK
    +-- Lambda
    |
    +-- Snowflake on AWS
```

co-location may simplify network and data-movement architecture.

Likewise:

```text
Azure application stack
        |
        +--> Snowflake on Azure
```

or:

```text
GCP application stack
        |
        +--> Snowflake on Google Cloud
```

Cloud choice should be an architecture decision, not simply a default.

## 5. Region Selection

Region selection affects:

```text
Region Selection
      |
      +-- Data residency
      +-- Compliance
      +-- Network proximity
      +-- Integration architecture
      +-- DR strategy
      +-- Replication
      +-- Data transfer
      +-- Feature availability
```

The exact region list differs by cloud platform and changes over time. Always verify the current Snowflake supported-region matrix during design.

## 6. Snowflake Editions

Snowflake documents editions including:

```text
Standard
   |
   v
Enterprise
   |
   v
Business Critical
   |
   v
Virtual Private Snowflake
```

Higher editions build on lower-edition capabilities and add enterprise, security, data-protection, or isolation features.

## 7. Standard Edition

Standard provides Snowflake's core platform capabilities. Depending on current product availability, these include broad areas such as:

```text
Virtual warehouses
SQL
Data loading
Snowpipe / streaming capabilities
Streams and tasks
Time Travel within applicable limits
Secure Data Sharing
Resource monitors
Connectors and APIs
Snowpark capabilities
```

Do not interpret "Standard" as meaning Snowflake lacks its fundamental data-engineering features. Always check current feature/edition documentation for a specific capability.

## 8. Enterprise Edition

Enterprise includes Standard capabilities and adds features intended for larger or more demanding enterprise workloads.

A key example from Tutorial 04 is:

```text
Multi-cluster warehouses
```

Multi-cluster warehouses require Enterprise Edition or higher under current Snowflake edition documentation.

Enterprise-level features also become relevant in governance and longer-retention scenarios. Later chapters call out edition requirements where they materially affect implementation.

## 9. Business Critical Edition

Business Critical builds on Enterprise and adds stronger security and data-protection capabilities for sensitive and regulated workloads.

This edition is particularly relevant when requirements involve:

```text
Sensitive regulated data
Enhanced security controls
Business continuity
Account-level replication/failover capabilities
Failback requirements
```

For healthcare or other regulated data, do not infer compliance solely from choosing an edition. Contractual, configuration, organizational, and regulatory requirements must also be satisfied. For example, organizations handling applicable PHI should verify current Snowflake healthcare/compliance requirements and contractual prerequisites before storing that data.

## 10. Virtual Private Snowflake

Virtual Private Snowflake (VPS) provides Snowflake's highest isolation model.

Conceptually:

```text
Standard Snowflake service model
Customer A
Customer B
Customer C
     |
Snowflake-managed service infrastructure


VPS
Customer organization
        |
        v
Separate isolated
Snowflake environment
```

VPS is intended for organizations with especially strict isolation requirements. Verify current availability and contractual requirements directly with Snowflake.

## 11. Edition Selection Is Requirements-Driven

Do not use:

```text
Higher edition = automatically better architecture
```

Instead:

```text
Business requirements
        |
        +-- Security
        +-- Compliance
        +-- HA / DR
        +-- Concurrency
        +-- Governance
        +-- Time Travel requirements
        +-- Isolation
        |
        v
Required Features
        |
        v
Snowflake Edition
```

This connects cost to actual requirements.

## 12. Check the Current Edition

With appropriate organization-level access, edition information can be obtained from organization usage.

Example:

```sql
SELECT edition
FROM SNOWFLAKE.ORGANIZATION_USAGE.ACCOUNTS
WHERE account_name = CURRENT_ACCOUNT();
```

For broader inventory:

```sql
SELECT
    ACCOUNT_NAME,
    REGION,
    EDITION
FROM SNOWFLAKE.ORGANIZATION_USAGE.ACCOUNTS;
```

Access requires appropriate privileges, and organization usage views can have latency.

## 13. Account Identity

Useful context functions:

```sql
SELECT
    CURRENT_ORGANIZATION_NAME(),
    CURRENT_ACCOUNT_NAME(),
    CURRENT_REGION();
```

During operational work, always be able to answer:

```text
Which organization?
Which account?
Which region?
```

## 14. Environment Separation

A production organization may use separate accounts:

```text
Organization
|
+-- DEV
+-- TEST
+-- STAGING
+-- PROD
```

Separate accounts can provide stronger administrative, security, billing, and failure-domain boundaries than putting every lifecycle environment into one account. The right model depends on organizational requirements.

## 15. Multi-Region Architecture

Example:

```text
             Primary
         AWS us-east-1
               |
          Replication
               |
               v
               DR
         AWS us-west-2
```

Where supported, organizations can also design cross-cloud replication/failover patterns.

```text
AWS
 |
 | supported replication/failover design
 v
Azure
```

Feature and edition requirements vary by replication scope. Verify the exact current Snowflake requirements before implementing DR.

## 16. Replication Is Not Automatically DR

```text
Replication != complete DR strategy
```

A production DR design also requires:

```text
RPO
RTO
Failover
Failback
Authentication
Network access
Integrations
Applications
DNS/endpoints
Testing
Operational ownership
```

Tutorials 66–70 will turn these into a full DR design and runbook.

## 17. Cross-Region Data Sharing

Cross-region/cross-cloud sharing may require replication or Snowflake fulfillment mechanisms depending on the sharing/listing model.

Conceptually:

```text
Provider
AWS / US
    |
    v
Snowflake
    |
Replication / Fulfillment
    |
    v
Consumer
Azure / Europe
```

Data residency and legal restrictions must be evaluated before copying or fulfilling data into another geography.

## 18. Production Region Selection

Before account creation, ask:

```text
Where are the users?

Where are the applications?

Where are source systems?

Where must data legally reside?

Where is the DR environment?

Which Snowflake features are available?

What cross-region/cloud transfer will occur?
```

Then determine:

```text
Cloud
   +
Region
   +
Edition
   =
Account Architecture
```

## 19. Common Architecture Mistake

Avoid:

```text
Cloud = whatever is easiest today
Region = default
Edition = cheapest
```

and discovering later that the platform requires:

```text
Regulatory controls
Cross-region DR
Advanced governance
Multi-cluster concurrency
Specific security controls
Data residency guarantees
```

Cloud, region, and edition should be part of initial platform design.

## 20. Troubleshooting: Know Where You Are

During an incident, establish context before making changes:

```sql
SELECT
    CURRENT_ORGANIZATION_NAME(),
    CURRENT_ACCOUNT_NAME(),
    CURRENT_REGION(),
    CURRENT_USER(),
    CURRENT_ROLE(),
    CURRENT_WAREHOUSE(),
    CURRENT_DATABASE(),
    CURRENT_SCHEMA();
```

This prevents a dangerous operational class of error:

```text
Engineer believes:
PROD / US

Actually connected to:
STAGING / US
```

or the reverse.

For DBRE/SRE work, verify context before administrative mutations.

## 21. Hands-On Lab

### Step 1 — Identify the account

```sql
SELECT
    CURRENT_ORGANIZATION_NAME(),
    CURRENT_ACCOUNT_NAME(),
    CURRENT_REGION();
```

### Step 2 — Identify session context

```sql
SELECT
    CURRENT_USER(),
    CURRENT_ROLE(),
    CURRENT_WAREHOUSE(),
    CURRENT_DATABASE(),
    CURRENT_SCHEMA();
```

### Step 3 — Inspect organization accounts

If your role has access:

```sql
SELECT
    ACCOUNT_NAME,
    REGION,
    EDITION
FROM SNOWFLAKE.ORGANIZATION_USAGE.ACCOUNTS
ORDER BY ACCOUNT_NAME;
```

### Step 4 — Document the environment

```text
Organization:
Account:
Environment:
Cloud:
Region:
Edition:

Primary workload:
DR account:
DR region:

Data classification:
Compliance requirements:
```

Reuse this inventory later for security, FinOps, replication, and DR exercises.

## 22. Production Takeaways

```text
Snowflake Organization
        |
        +-- Account
        |      |
        |      +-- Cloud Platform
        |      +-- Region
        |      +-- Edition
        |
        +-- Account
        +-- Account
```

Core rules:

- An individual Snowflake account is deployed in one region.
- Snowflake supports AWS, Azure, and Google Cloud.
- Organizations can contain accounts across supported regions/cloud platforms.
- Edition selection should follow required features, security, compliance, HA/DR, governance, and workload needs.
- Multi-cluster warehouses require an appropriate edition; verify current requirements.
- Replication and failover capabilities have scope-specific edition requirements.
- Cloud and region selection affect residency, integrations, network paths, DR, and data movement.
- Verify account/session context before production administrative changes.

## Technical references

- Snowflake editions: https://docs.snowflake.com/en/user-guide/intro-editions
- Supported cloud platforms: https://docs.snowflake.com/en/user-guide/intro-cloud-platforms
- Regions: https://docs.snowflake.com/en/user-guide/intro-regions
- Organizations: https://docs.snowflake.com/en/user-guide/organizations
- Replication and failover: https://docs.snowflake.com/en/user-guide/account-replication-config
- Cross-region/platform sharing: https://docs.snowflake.com/en/user-guide/secure-data-sharing-across-regions-platforms
