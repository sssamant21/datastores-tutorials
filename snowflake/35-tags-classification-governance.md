# 35 — Tags, Classification & Governance

## Overview

As Snowflake environments grow, manually identifying and protecting sensitive data becomes difficult. Production accounts can contain hundreds of databases, thousands of schemas, tens of thousands of tables, and hundreds of thousands of columns.

Governance teams need to answer where sensitive data exists, what category it belongs to, who owns it, who can access it, whether masking or row-level security is required, and whether controls remain consistent.

A scalable governance model connects:

```text
Classification
     |
     v
Tags
     |
     v
Governance Policies
     |
     +---- Masking
     +---- Row Access
     |
     v
Monitoring / Auditing
```

This chapter covers object tagging, classification, sensitive-data discovery, tag-based governance, tag-based masking, ownership, auditing, coverage-gap detection, monitoring, incident response, and production rollout.

---

# Part 1 — Why Data Governance Matters

## 1. The Scale Problem

Manual governance may work for a few tables. It becomes unreliable across thousands of tables and columns.

## 2. Governance Questions

For every sensitive column, an organization should understand what the data represents, its classification, owner, authorized consumers, protection requirements, sharing restrictions, and retention requirements.

Tags and classification provide machine-readable metadata for answering these questions systematically.

---

# Part 2 — Snowflake Tags

## 3. What Is a Tag?

A Snowflake tag is a schema-level object used to associate metadata with supported Snowflake objects.

```text
Snowflake Object
      |
      v
Tag
      |
      v
Tag Value
```

## 4. Example

A customer email column could have:

```text
DATA_CLASSIFICATION = PII
```

A patient identifier could have:

```text
DATA_CLASSIFICATION = PHI
```

## 5. Tags Are Metadata

Tags do not inherently hide data. They become powerful when integrated with governance policies and operational processes.

---

# Part 3 — Create a Tag

## 6. Basic Tag

```sql
CREATE TAG governance_db.tags.data_classification;
```

## 7. Allowed Values

```sql
CREATE TAG governance_db.tags.data_classification
    ALLOWED_VALUES
        'PUBLIC',
        'INTERNAL',
        'CONFIDENTIAL',
        'PII',
        'PHI',
        'FINANCIAL';
```

## 8. Why Allowed Values?

Controlled values prevent inconsistent labels and improve automation, reporting, and policy enforcement.

---

# Part 4 — Apply Tags

## 9. Tag a Table

```sql
ALTER TABLE customer
SET TAG governance_db.tags.data_classification =
    'CONFIDENTIAL';
```

## 10. Tag a Column

```sql
ALTER TABLE customer
MODIFY COLUMN email
SET TAG governance_db.tags.data_classification =
    'PII';
```

## 11. Multiple Tags

```text
DATA_CLASSIFICATION = PII
DATA_OWNER          = CUSTOMER_PLATFORM
RETENTION_CLASS     = SEVEN_YEARS
BUSINESS_DOMAIN     = CUSTOMER
```

---

# Part 5 — Governance Tag Model

## 12. Recommended Categories

A governance model may include DATA_CLASSIFICATION, DATA_OWNER, BUSINESS_DOMAIN, RETENTION_CLASS, CRITICALITY, REGULATORY_SCOPE, and DATA_ENVIRONMENT.

## 13. Example

```text
Column: CUSTOMER.EMAIL
DATA_CLASSIFICATION = PII
DATA_OWNER          = CUSTOMER_PLATFORM
BUSINESS_DOMAIN     = CUSTOMER
RETENTION_CLASS     = SEVEN_YEARS
REGULATORY_SCOPE    = PRIVACY
```

## 14. Keep Tags Purposeful

Every tag should have a purpose, owner, controlled values where appropriate, lifecycle, and known consumers.

---

# Part 6 — Tag Ownership

## 15. Tags Are Governance Objects

Creating and modifying governance tags should be controlled by an appropriate governance role.

## 16. Separation of Duties

Application teams create data, governance teams define classification standards, and security teams define protection requirements.

## 17. Prevent Tag Tampering

If tags drive security policy, unauthorized tag changes can alter effective security behavior. Restrict tag creation, application, modification, and removal.

---

# Part 7 — Classification

## 18. What Is Data Classification?

Classification determines what type of data a column contains, such as contact information, personal identifiers, financial information, or medical identifiers.

## 19. Classification vs Tagging

Classification answers what the data is. Tagging records how the object should be categorized or governed.

---

# Part 8 — Sensitive Data Discovery

## 20. Why Discovery Matters

Security controls cannot consistently protect sensitive data if the organization does not know where it exists.

## 21. Common Discovery Problem

A table can gain a new sensitive column after initial deployment. Without continuous governance, the new field may remain unprotected.

## 22. Continuous Discovery

```text
Schema Change
     |
     v
Classification
     |
     v
Governance Review
     |
     v
Tag / Policy
```

---

# Part 9 — Snowflake Classification

## 23. Classification Capabilities

Snowflake provides capabilities for identifying and classifying potentially sensitive data. Validate current system functions, semantic categories, privacy categories, supported objects, and automation features against current Snowflake documentation.

## 24. Classification Output

Classification can identify categories representing names, contact information, addresses, financial identifiers, government identifiers, and other sensitive personal data depending on current Snowflake capabilities.

## 25. Human Review

Automated classification is not infallible. Review false positives, false negatives, business context, regulatory context, and transformed data.

---

# Part 10 — Classification Architecture

## 26. Discovery Pipeline

```text
Snowflake Data
      |
      v
Classification
      |
      v
Sensitive Data Inventory
      |
      v
Governance Tags
      |
      v
Protection Policies
```

## 27. Classification Result Is Not the Final Control

Finding sensitive data does not protect it. Follow-up may include tagging, masking, RBAC review, Row Access Policies, sharing restrictions, retention controls, and monitoring.

---

# Part 11 — PII Classification

## 28. Personally Identifiable Information

Examples include names, email, phone, address, date of birth, and government identifiers. The organization's privacy program determines the precise model.

## 29. PII Tag

```text
DATA_CLASSIFICATION = PII
```

---

# Part 12 — PHI Classification

## 30. Healthcare Data

Healthcare environments may classify patient identifiers, demographics, diagnoses, procedures, medications, lab information, and insurance identifiers according to organizational and regulatory requirements.

## 31. PHI Tag

```text
DATA_CLASSIFICATION = PHI
```

## 32. Context Matters

A value may become sensitive because of its relationship to other data. Classification cannot always rely only on column names.

---

# Part 13 — Financial Data

## 33. Financial Categories

Examples include bank information, payment information, transactions, salary, and balances.

## 34. Tagging

```text
DATA_CLASSIFICATION = FINANCIAL
```

Different subcategories may require different controls.

---

# Part 14 — Tag-Based Masking

## 35. Scaling Problem

Manually attaching masking policies to thousands of sensitive columns becomes difficult to manage.

## 36. Tag-Based Masking Concept

Snowflake supports governance patterns where masking policies can be associated with tags.

```text
Column
   |
   v
Classification Tag
   |
   v
Masking Policy
```

## 37. Example

```text
CUSTOMER.EMAIL
      |
      v
PII_EMAIL
      |
      v
EMAIL_MASK
```

---

# Part 15 — Why Tag-Based Masking Helps

## 38. Centralized Policy

Instead of managing thousands of individual Column → Policy attachments, an organization can manage Tag → Policy relationships and classify/tag applicable columns.

## 39. Reduced Governance Drift

Tag-driven governance can reduce the chance that new sensitive columns are created without expected masking controls.

---

# Part 16 — Tag-Based Masking Design

## 40. Example Tags

```text
PII_EMAIL
PII_PHONE
PII_GOVERNMENT_ID
PHI_PATIENT_ID
FINANCIAL_ACCOUNT
```

## 41. Why Specific Tags?

Different data types may require different transformations. A single generic masking transformation may not fit every sensitive category.

---

# Part 17 — Tag Inheritance

## 42. Hierarchical Objects

```text
Database
   |
   v
Schema
   |
   v
Table
   |
   v
Column
```

Tag behavior can include inheritance considerations depending on object and configuration.

## 43. Effective Tag

Distinguish direct, inherited, and effective tag values. Use current Snowflake metadata functions/views to inspect effective tagging.

## 44. Avoid Assumptions

Do not assume a tag set on a database automatically has exactly the desired security meaning for every descendant object. Validate inheritance explicitly.

---

# Part 18 — Conflicting Tags

## 45. Example

A table can be CONFIDENTIAL while a specific column is PII. The column classification may require stronger controls.

## 46. Governance Rules

Document precedence and effective-governance rules. Do not leave conflict resolution to individual interpretation.

---

# Part 19 — Data Ownership

## 47. Ownership Tag

```text
DATA_OWNER = PATIENT_PLATFORM
```

## 48. Why Ownership Matters

Teams need to know who approves access, validates classification, approves sharing, owns retention, and responds to incidents.

## 49. Avoid Personal Names

Prefer stable team/function identifiers over individual employee names.

---

# Part 20 — Business Domain

## 50. Domain Tag

Examples include CUSTOMER, PATIENT, CLAIMS, FINANCE, HR, and OPERATIONS.

## 51. Why Domain Matters

Domain metadata helps with ownership, discovery, cost attribution, governance, data products, and access review.

---

# Part 21 — Regulatory Scope

## 52. Regulatory Tag

Organizations may define internal values such as PRIVACY, HEALTHCARE, FINANCIAL, or INTERNAL_CONTROL.

## 53. Tags Are Not Compliance

A regulatory tag does not itself make a system compliant. It provides metadata that can support compliance controls.

---

# Part 22 — Retention Classification

## 54. Retention Tag

```text
RETENTION_CLASS = SEVEN_YEARS
```

## 55. Lifecycle Integration

Retention metadata can feed archival, deletion, legal hold, data lifecycle, and cost-optimization processes. Actual enforcement requires appropriate controls.

---

# Part 23 — Criticality

## 56. Criticality Tag

```text
CRITICALITY = TIER_1
```

## 57. Operational Use

Criticality can influence monitoring, backup strategy, DR, incident priority, change controls, and SLOs.

---

# Part 24 — Governance Metadata Architecture

## 58. Example

```text
DATA_CLASSIFICATION = PHI
DATA_OWNER          = PATIENT_PLATFORM
BUSINESS_DOMAIN     = PATIENT
RETENTION_CLASS     = SEVEN_YEARS
CRITICALITY         = TIER_1
REGULATORY_SCOPE    = HEALTHCARE
```

## 59. Machine-Readable Governance

Structured tags allow governance systems to query combinations of classification, ownership, criticality, retention, and regulatory scope.

---

# Part 25 — Governance Inventory

## 60. Inventory Requirements

Administrators should be able to identify all tags, tagged objects, sensitive columns, data owners, classification values, and policy associations.

## 61. Metadata Sources

Use current ACCOUNT_USAGE, Information Schema, and supported system functions to inspect tags, tag references, policies, columns, objects, and access history as appropriate.

---

# Part 26 — Coverage Analysis

## 62. Critical Governance Query

A valuable control asks: Which sensitive columns do not have required protection?

```text
Sensitive Columns
       |
       v
Compare
       |
       v
Masking Coverage
```

## 63. Example Finding

```text
CUSTOMER.EMAIL
Classification = PII
Masking = YES

CUSTOMER.GOVERNMENT_ID
Classification = PII
Masking = NO
```

The second result requires investigation.

---

# Part 27 — Governance Drift

## 64. What Is Governance Drift?

Examples include new sensitive columns without tags, removed tags, removed masking policies, changed owners, unexpected classifications, or new tables bypassing governance.

## 65. Continuous Detection

Run governance checks regularly. Do not wait for an audit or incident.

---

# Part 28 — Schema Change Governance

## 66. New Column Workflow

```text
ALTER TABLE / New Pipeline
          |
          v
New Column
          |
          v
Classification
          |
          v
Tag
          |
          v
Required Security Policy
          |
          v
Validation
```

## 67. Deployment Gate

For sensitive environments, consider blocking production promotion when required governance metadata or controls are missing.

---

# Part 29 — CI/CD Integration

## 68. Governance as Code

Repository definitions can contain expected tags, policy mappings, ownership, and classification.

## 69. Pull Request Review

A schema change introducing a new sensitive identifier should trigger questions about business need, classification, masking, authorized access, and retention.

---

# Part 30 — Tag Changes Are Security-Relevant

## 70. Security Impact

If masking behavior is driven by a tag, changing its classification can alter protection.

## 71. Treat Tag Changes Carefully

Use change review, audit trails, limited privileges, and automated validation for security-relevant tags.

---

# Part 31 — Monitoring

## 72. Governance Dashboard

Useful metrics include total tables, total columns, sensitive columns, classified/unclassified columns, masked/unmasked sensitive columns, objects without owners, recent tag changes, and recent policy changes.

## 73. Coverage Percentage

```text
Sensitive columns = 10,000
Protected = 9,850
Coverage = 98.5%
```

The remaining columns require review.

## 74. Do Not Optimize for the Percentage Alone

A high coverage rate can still be unacceptable if an unprotected column contains highly sensitive information. Prioritize by risk.

---

# Part 32 — Access History

## 75. Why Access History Matters

Classification answers what data exists. Access history helps answer who accessed it.

## 76. Investigation

Investigators may need users, roles, queries, applications, timestamps, and downstream objects depending on available Snowflake metadata.

---

# Part 33 — Troubleshooting

## 77. Tag Not Visible

Check tag existence, correct object, database/schema, privileges, direct vs inherited tagging, and metadata latency.

## 78. Wrong Tag Value

Check allowed values, automation logic, manual changes, inheritance, and object-level overrides.

## 79. Sensitive Column Not Masked

Check classification, tag assignment, tag-based masking policy, policy signature, data type, policy association, and role context.

## 80. Unexpected Masking

Check effective/inherited tags, tag-based policy, direct policy, role context, and classification changes.

---

# Part 34 — Governance Incident Runbook

## 81. Sensitive Data Found Unprotected

1. Capture object name.
2. Capture database/schema/table/column.
3. Identify data classification.
4. Identify tag state.
5. Identify policy state.
6. Identify data owner.
7. Identify current grants.
8. Review query/access history.
9. Determine who accessed the data.
10. Determine exposure period.
11. Apply containment if necessary.
12. Apply correct classification.
13. Apply required tags.
14. Apply required masking/access policy.
15. Run negative tests.
16. Validate applications.
17. Review similar objects.
18. Determine why governance failed.
19. Add preventive control.
20. Document incident.

---

# Part 35 — Emergency Containment

## 82. Possible Actions

Depending on risk: revoke SELECT, revoke role, apply masking policy, apply Row Access Policy, suspend sharing/export, or restrict a user.

## 83. Preserve Evidence

Capture tag state, policy state, grants, query IDs, access history, recent changes, and timestamps before extensive remediation where required.

---

# Part 36 — Change Management

## 84. Governance Changes

Treat changes to classification, tags, tag-based policies, masking, Row Access Policies, and ownership metadata as controlled changes when they affect security.

## 85. Pre-Change Checklist

- Business requirement
- Data owner approval
- Classification reviewed
- Tag value reviewed
- Security impact reviewed
- Policy impact reviewed
- Dependencies identified
- Tests ready
- Rollback ready

## 86. Post-Change Checklist

- Tag correct
- Effective tag verified
- Policy correct
- Raw access tested
- Masked access tested
- Row access tested
- Application tested
- Monitoring clean

---

# Part 37 — Governance Operating Model

## 87. Data Producer

Responsible for schema design, data quality, metadata, and ownership information.

## 88. Governance Team

Responsible for classification standards, tag taxonomy, policy standards, and coverage monitoring.

## 89. Security Team

Responsible for security requirements, privileged access, incident response, and security reviews.

## 90. Platform / DBRE / SRE

Responsible for automation, monitoring, operational reliability, troubleshooting, and change management.

---

# Part 38 — Production Governance Architecture

## 91. End-to-End Model

```text
Data Created
    |
    v
Classification
    |
    v
Governance Tags
    |
    +----------------------+
    |                      |
    v                      v
Masking Policy       Row Access Policy
    |                      |
    +-----------+----------+
                |
                v
         Controlled Access
                |
                v
         Access Monitoring
```

## 92. Governance Is Continuous

```text
Create
  |
  v
Classify
  |
  v
Protect
  |
  v
Monitor
  |
  v
Detect Drift
  |
  v
Correct
```

---

# Part 39 — Hands-On Lab

## 93. Lab Objective

Create a governance database, tags, sample customer table, classification metadata, specific sensitive-type metadata, and governance validation.

Use a non-production environment and fictional data.

## 94. Create Governance Database

```sql
CREATE OR REPLACE DATABASE governance_lab;
```

## 95. Create Schemas

```sql
CREATE OR REPLACE SCHEMA governance_lab.data;
CREATE OR REPLACE SCHEMA governance_lab.governance;
```

## 96. Create Classification Tag

```sql
CREATE OR REPLACE TAG
governance_lab.governance.data_classification
ALLOWED_VALUES
    'PUBLIC',
    'INTERNAL',
    'CONFIDENTIAL',
    'PII',
    'PHI',
    'FINANCIAL';
```

## 97. Create Owner Tag

```sql
CREATE OR REPLACE TAG
governance_lab.governance.data_owner;
```

## 98. Create Customer Table

```sql
CREATE OR REPLACE TABLE
governance_lab.data.customer (
    customer_id NUMBER,
    customer_name STRING,
    email STRING,
    phone STRING,
    government_id STRING
);
```

## 99. Insert Fictional Data

```sql
INSERT INTO governance_lab.data.customer
VALUES
(
    1001,
    'Jane Example',
    'jane@example.com',
    '704-555-1234',
    'ID-EXAMPLE-1001'
);
```

Never use real sensitive personal data in a lab.

## 100. Tag the Table Owner

```sql
ALTER TABLE governance_lab.data.customer
SET TAG governance_lab.governance.data_owner =
    'CUSTOMER_PLATFORM';
```

## 101. Tag Email

```sql
ALTER TABLE governance_lab.data.customer
MODIFY COLUMN email
SET TAG governance_lab.governance.data_classification =
    'PII';
```

## 102. Tag Phone

```sql
ALTER TABLE governance_lab.data.customer
MODIFY COLUMN phone
SET TAG governance_lab.governance.data_classification =
    'PII';
```

## 103. Tag Sensitive Identifier

```sql
ALTER TABLE governance_lab.data.customer
MODIFY COLUMN government_id
SET TAG governance_lab.governance.data_classification =
    'PII';
```

## 104. Inspect Tags

Use supported Snowflake metadata functions/views to inspect direct tags, inherited tags, effective tag values, and object references.

Verify EMAIL, PHONE, and GOVERNMENT_ID are classified PII.

## 105. Create Specific Security Tag

```sql
CREATE OR REPLACE TAG
governance_lab.governance.sensitive_type
ALLOWED_VALUES
    'EMAIL',
    'PHONE',
    'GOVERNMENT_ID';
```

## 106. Assign Specific Types

```sql
ALTER TABLE governance_lab.data.customer
MODIFY COLUMN email
SET TAG governance_lab.governance.sensitive_type = 'EMAIL';

ALTER TABLE governance_lab.data.customer
MODIFY COLUMN phone
SET TAG governance_lab.governance.sensitive_type = 'PHONE';

ALTER TABLE governance_lab.data.customer
MODIFY COLUMN government_id
SET TAG governance_lab.governance.sensitive_type = 'GOVERNMENT_ID';
```

## 107. Governance Validation

```text
COLUMN        | CLASSIFICATION | SENSITIVE_TYPE
--------------+----------------+----------------
EMAIL         | PII            | EMAIL
PHONE         | PII            | PHONE
GOVERNMENT_ID | PII            | GOVERNMENT_ID
```

## 108. Coverage Test

```sql
ALTER TABLE governance_lab.data.customer
ADD COLUMN date_of_birth DATE;
```

Do not tag it initially. Run the governance inventory. The new column should appear as a potential governance gap once classified or identified as requiring classification.

## 109. Remediate

Apply the organization's appropriate classification/tag.

```text
New column
   |
   v
Gap detected
   |
   v
Classified
   |
   v
Tagged
   |
   v
Protected
```

## 110. Cleanup

```sql
DROP DATABASE IF EXISTS governance_lab;
```

Follow dependency-safe cleanup if additional policies were created.

---

# Part 40 — Production Checklist

## 111. Tagging Checklist

- Tag taxonomy documented
- Allowed values standardized
- Tag owners defined
- Tag privileges restricted
- Inheritance understood
- Effective values validated
- Changes audited

## 112. Classification Checklist

- Sensitive-data discovery enabled/process defined
- Classification reviewed
- False positives handled
- False negatives investigated
- New columns reviewed
- High-risk datasets prioritized

## 113. Protection Checklist

- Sensitive columns identified
- Required masking applied
- Required row filtering applied
- Privileged roles minimized
- Sharing reviewed
- Export paths reviewed
- Negative tests completed

## 114. Monitoring Checklist

- Tag inventory
- Classification inventory
- Sensitive-column inventory
- Masking coverage
- Row-policy coverage
- Untagged sensitive objects
- Objects without owners
- Recent governance changes
- Access history available

---

# Acceptance Criteria

The chapter is complete when you can:

- explain Snowflake tags
- create tags and define allowed values
- apply tags to tables and columns
- design a governance tag taxonomy
- control tag ownership
- explain data classification and distinguish it from tagging
- design sensitive-data discovery
- classify PII, PHI, and financial information
- understand Snowflake classification concepts
- use human review with automated classification
- design tag-based governance and masking
- design data-type-specific security tags
- understand tag inheritance and effective values
- handle tag conflicts
- identify data owners and business domains
- represent regulatory scope, retention, and criticality
- build machine-readable governance metadata
- inventory tags and sensitive columns
- detect protection gaps and governance drift
- integrate governance into schema changes and CI/CD
- treat security-relevant tag changes as controlled changes
- build governance dashboards
- measure protection coverage
- use access history for investigations
- troubleshoot tag behavior and missing masking
- execute a governance incident runbook
- implement emergency containment
- define a governance operating model
- build an end-to-end production governance architecture

---

## Key Takeaways

Classification answers: What kind of data is this?

Tags provide structured metadata about how data should be categorized, who owns it, and what controls should apply.

Masking controls what value a user can see.

Row Access Policies control which rows a user can see.

```text
Data
  |
  v
Classification
  |
  v
Tags
  |
  +--------------------+
  |                    |
  v                    v
Masking            Row Access
  |                    |
  +----------+---------+
             |
             v
       Controlled Data
             |
             v
       Monitoring/Audit
```

Do not treat tags as decorative metadata. When tags drive security automation, changing a tag can potentially change security.

Governance must account for new data. A secure table today can become insecure tomorrow when a new sensitive column is added without classification or protection.

Continuously detect new columns, unclassified data, missing tags, missing policies, unexpected tag changes, and unexpected access.

Most importantly:

> You cannot consistently protect sensitive data if you do not know where that sensitive data exists.

The next chapter is **Chapter 36 — Snowflake Query Processing Internals**.
