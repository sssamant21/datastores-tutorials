# 33 — Dynamic Data Masking

## Overview

Production Snowflake environments frequently contain sensitive information such as patient data, customer and employee information, email addresses, phone numbers, addresses, Social Security numbers, financial information, account identifiers, tokens, and internal business data.

Access to a table does not necessarily mean every user should see every value in that table.

Consider:

```text
CUSTOMER_ID | NAME       | SSN
------------+------------+-------------
1001        | Jane Smith | 123-45-6789
```

An analyst may need access to the record but not the complete SSN.

Instead of creating separate sanitized copies of the table, Snowflake can dynamically transform the value returned to a user based on a masking policy.

Conceptually:

```text
Table
  |
  v
Masking Policy
  |
  +---- Authorized user → Original value
  |
  +---- Unauthorized user → Masked value
```

The underlying data remains unchanged. The policy controls what is returned at query time.

This chapter covers dynamic data masking, masking policies, role-aware masking, execution context, policy attachment, policy management, PII/PHI protection, testing, monitoring, troubleshooting, incident response, and production rollout.

---

# Part 1 — What Is Dynamic Data Masking?

## 1. Definition

Dynamic Data Masking is a Snowflake column-level security capability that applies masking policies when protected data is queried.

Stored value → Masking Policy → Returned value.

## 2. Data Is Not Physically Modified

If the stored value is 123-45-6789, an authorized user may receive the original value while an unauthorized or limited user receives XXX-XX-XXXX.

The stored table value remains unchanged.

## 3. Why Dynamic Masking?

Without masking, organizations often create multiple raw, masked, analytics, support, and export copies of datasets.

Dynamic masking supports one authoritative dataset with different visibility based on policy.

---

# Part 2 — Security Architecture

## 4. RBAC + Masking

RBAC answers whether a role can query the table.

Masking answers what value the role should see when it can query the protected column.

Both controls matter.

## 5. Example

ANALYST_ROLE may have SELECT on CUSTOMER but still receive XXX-XX-XXXX instead of raw SSNs.

## 6. Defense in Depth

A mature model can combine RBAC, masking policies, row access policies, tags/classification, network controls, authentication, and auditing.

---

# Part 3 — Masking Policy Object

## 7. What Is a Masking Policy?

A masking policy is a schema-level Snowflake object.

Example:

```text
GOVERNANCE_DB.POLICIES.EMAIL_MASK
```

## 8. Basic Policy Structure

```sql
CREATE MASKING POLICY email_mask
AS (val STRING)
RETURNS STRING ->
    CASE
        WHEN <authorized-condition>
            THEN val
        ELSE '***MASKED***'
    END;
```

## 9. Data Type Matters

The policy signature and return type must be compatible with the protected column.

For strings:

```sql
AS (val STRING)
RETURNS STRING
```

For numeric values:

```sql
AS (val NUMBER)
RETURNS NUMBER
```

---

# Part 4 — Role-Aware Masking

## 10. Role-Based Visibility

A common policy allows privileged roles to see raw values.

```sql
CASE
    WHEN CURRENT_ROLE() = 'PII_ADMIN'
        THEN val
    ELSE '***MASKED***'
END
```

Production policy design should carefully consider role hierarchy and active-role semantics.

## 11. IS_ROLE_IN_SESSION

For many role-based designs, Snowflake role-context functions can determine whether an authorized role is active/available according to Snowflake semantics.

```sql
CASE
    WHEN IS_ROLE_IN_SESSION('PII_READER')
        THEN val
    ELSE '***MASKED***'
END
```

## 12. Why CURRENT_ROLE Alone Can Be Too Narrow

A single CURRENT_ROLE comparison may not reflect the complete intended role hierarchy. Design policy logic around the organization's Snowflake role model.

---

# Part 5 — Email Masking

## 13. Full Mask

```sql
CREATE OR REPLACE MASKING POLICY
governance_db.policies.email_mask
AS (val STRING)
RETURNS STRING ->
    CASE
        WHEN IS_ROLE_IN_SESSION('PII_READER')
            THEN val
        ELSE '***MASKED***'
    END;
```

## 14. Partial Email Mask

A value such as jane.smith@example.com could be transformed to a business-approved partially masked representation such as j***@example.com.

## 15. Do Not Overexpose

Partial masking may still identify a person. Requirements should come from security, privacy, compliance, and legitimate business need.

---

# Part 6 — Phone Number Masking

## 16. Full Mask

A stored value such as 704-555-1234 can be returned as XXX-XXX-XXXX.

## 17. Partial Mask

A support workflow might be approved to see only the last four digits, such as XXX-XXX-1234.

## 18. Business Requirement First

Do not expose partial values merely because it is technically easy. Determine whether the business requires them.

---

# Part 7 — SSN Masking

## 19. Sensitive Identifier

```sql
CREATE OR REPLACE MASKING POLICY
governance_db.policies.ssn_mask
AS (val STRING)
RETURNS STRING ->
    CASE
        WHEN IS_ROLE_IN_SESSION('PII_PRIVILEGED_READER')
            THEN val
        ELSE 'XXX-XX-XXXX'
    END;
```

## 20. Privileged Access

Raw SSN access should normally be limited to a small approved set of roles rather than broadly granted to analysts, developers, support, or reporting roles.

---

# Part 8 — Healthcare / PHI

## 21. PHI Protection

Healthcare datasets may contain patient name, DOB, address, phone, email, MRN, insurance identifiers, and clinical information.

Masking can restrict visibility for workflows that do not require raw PHI.

## 22. Example Role Model

- PHI_PRIVILEGED_READER → raw PHI
- DATA_ANALYST → masked PHI
- SUPPORT_ROLE → masked or approved partially masked values

Exact access depends on organizational policy.

---

# Part 9 — Apply a Masking Policy

## 23. Column Attachment

```sql
ALTER TABLE customer
MODIFY COLUMN email
SET MASKING POLICY governance_db.policies.email_mask;
```

## 24. Query Behavior

After attachment:

```sql
SELECT email
FROM customer;
```

Snowflake evaluates the masking policy according to query execution context.

## 25. Application Transparency

Applications generally continue querying the column normally. They do not explicitly invoke a mask function.

---

# Part 10 — Removing a Policy

## 26. Unset Masking Policy

```sql
ALTER TABLE customer
MODIFY COLUMN email
UNSET MASKING POLICY;
```

This is a security-sensitive change.

## 27. Impact

Removing a policy can immediately expose raw values to users who already have SELECT access. Treat UNSET MASKING POLICY as a production security change.

---

# Part 11 — Replace a Policy

## 28. Policy Updates

Policy logic may change because of new roles, privacy requirements, business requirements, incident remediation, or policy simplification.

Test changes before production deployment.

## 29. Blast Radius

One policy may protect many columns. Changing it can affect many datasets simultaneously.

Identify dependencies before changing a shared policy.

---

# Part 12 — Centralized Governance

## 30. Governance Database

A common design:

```text
GOVERNANCE_DB
      |
      +---- POLICIES
      +---- CLASSIFICATION
      +---- AUDIT
```

## 31. Why Centralize?

Benefits include consistent logic, controlled ownership, easier auditing, simpler discovery, reduced duplication, and standard naming.

## 32. Avoid Policy Sprawl

Avoid unmanaged versions such as email_mask_v1, email_mask_v2, email_mask_final, and email_mask_final2.

Use documented lifecycle management.

---

# Part 13 — Policy Ownership

## 33. Dedicated Policy Administrator

Consider a governance role such as MASKING_POLICY_ADMIN or DATA_GOVERNANCE_ADMIN depending on organizational design.

## 34. Separation of Duties

Developers may create application objects, governance administrators control masking policy, and analysts consume protected data.

This reduces accidental weakening of policy.

---

# Part 14 — Policy Naming

## 35. Use Clear Names

Examples:

- EMAIL_MASK
- PHONE_MASK
- SSN_MASK
- DOB_MASK
- MRN_MASK
- FINANCIAL_ACCOUNT_MASK

Avoid vague names such as POLICY1, MASK_NEW, or TEMP_POLICY.

## 36. Include Purpose

Specialized names can include EMAIL_PARTIAL_SUPPORT_MASK, PHI_ANALYTICS_MASK, or SSN_PRIVILEGED_ACCESS_MASK.

---

# Part 15 — Policy Conditions

## 37. Role Context

Policies can evaluate supported Snowflake context functions for role, account, user, session, or other supported execution context.

Use only context necessary for the security requirement.

## 38. Avoid Hard-Coding Individual Users

Avoid long-term policies based on lists of individual usernames unless specifically justified.

Prefer role-based access.

## 39. Why Roles Scale Better

Users change. Roles represent capabilities.

Prefer User → Role → Policy authorization rather than policy definitions containing hundreds of usernames.

---

# Part 16 — NULL Handling

## 40. NULL Values

```sql
CASE
    WHEN val IS NULL
        THEN NULL
    WHEN IS_ROLE_IN_SESSION('PII_READER')
        THEN val
    ELSE '***MASKED***'
END
```

## 41. Why Preserve NULL?

Changing NULL to a mask string can alter application semantics. Define desired behavior explicitly.

---

# Part 17 — Data Type Preservation

## 42. Numeric Columns

A NUMBER masking policy cannot return a string mask such as ***MASKED***. Use a type-compatible, business-approved transformation.

## 43. Date Columns

For DATE columns, use an approved replacement/transformation compatible with DATE.

## 44. Type-Safe Policy Design

Always preserve the expected return type to reduce application and query failures.

---

# Part 18 — Views and Masking

## 45. Protected Data Through Views

If a view exposes a protected column, understand how Snowflake applies the masking policy through the query path.

Do not assume creating a view bypasses masking.

## 46. Test Every Access Path

Test direct table access, standard views, secure views, applicable materialized-view scenarios, BI queries, application queries, and export workflows.

---

# Part 19 — Masking and Data Sharing

## 47. Shared Data

If protected data is shared, understand applicable policy behavior for consumers. Do not assume masking disappears across a sharing boundary.

## 48. Consumer Context

Provider/consumer context can differ. Test sharing behavior explicitly.

---

# Part 20 — Masking and Cloning

## 49. Zero-Copy Clone

Cloning protected objects requires governance review. Verify policy references and protected-column behavior for the specific clone operation.

## 50. Development Environments

Do not assume cloning production data into development makes sensitive data safe. Verify governance controls after cloning.

---

# Part 21 — Masking and Time Travel

## 51. Historical Data

Time Travel does not eliminate governance requirements. Sensitive historical values remain sensitive.

## 52. Recovery Workflows

When using UNDROP, Time Travel, clone, or other recovery workflows, verify required masking policies remain correctly associated.

---

# Part 22 — Monitoring Policies

## 53. Inventory Policies

Administrators should know which policies exist, who owns them, which columns use them, which roles can see raw data, and which sensitive columns remain unprotected.

## 54. Policy References

Use supported Snowflake metadata capabilities to inspect policy references and dependencies.

## 55. Governance Dashboard

Useful metrics include sensitive columns, masked columns, unmasked sensitive columns, policies by type, policy owners, privileged roles, and recent policy changes.

---

# Part 23 — Detecting Coverage Gaps

## 56. Sensitive Column Without Policy

A common governance failure is a column classified as sensitive with no masking policy.

Automate detection where possible.

## 57. New Columns

Schema evolution can introduce a new sensitive column after initial governance implementation. Manual processes may leave it exposed.

## 58. Classification + Masking

A mature model connects classification → sensitive tag → masking policy.

Chapter 35 expands this model.

---

# Part 24 — Tag-Based Masking

## 59. Why Tag-Based Masking?

Manually applying policies to thousands of columns can become difficult. Tag-based masking can support scalable governance.

## 60. Example Categories

Examples include PII.EMAIL, PII.PHONE, PII.SSN, PHI.MRN, and FINANCIAL.ACCOUNT.

Different categories can receive different masking logic.

---

# Part 25 — Testing

## 61. Test as Privileged Role

Expected: raw value visible.

## 62. Test as Standard Analyst

Expected: masked value.

## 63. Test as Unauthorized Role

Expected: no table access, or masked output only if that is the intended RBAC design.

## 64. Test Role Hierarchy

Test inherited roles and secondary-role behavior according to the organization's role model. Do not test only as the policy owner.

---

# Part 26 — Negative Testing

## 65. Why Negative Tests Matter

A successful privileged query proves only that privileged access works. It does not prove masking works.

Always test:

- Authorized → raw
- Limited → masked
- No access → denied

## 66. Test New Roles

Whenever a new role is introduced, explicitly determine whether it should see raw data, masked data, or no data.

---

# Part 27 — Performance Considerations

## 67. Policy Logic Has Cost

Masking logic executes during queries. Very complex policy expressions can add overhead.

## 68. Keep Logic Understandable

Prefer policy logic that is easy to review, test, troubleshoot, audit, and maintain.

## 69. Benchmark Critical Workloads

For high-volume workloads, benchmark latency, warehouse consumption, query profile, and concurrency behavior when material governance changes are introduced.

---

# Part 28 — Troubleshooting

## 70. User Sees Masked Data but Should See Raw

Check active role, role hierarchy, policy logic, policy attachment, policy version, and session context.

## 71. User Sees Raw Data but Should Be Masked

Treat this as a potential security incident.

Check role grants, policy logic, policy attachment/removal, secondary roles, ownership changes, and tag-based associations.

## 72. Policy Cannot Be Applied

Check column type, policy signature, return type, privileges, existing policy, object type, and policy ownership.

## 73. Query Fails After Policy Change

Possible causes include return-type mismatch, invalid SQL expression, missing referenced object, role/context logic, or dependency changes.

Correct or roll back promptly.

---

# Part 29 — Data Exposure Incident Runbook

## 74. Suspected Masking Failure

1. Capture timestamp.
2. Capture query ID.
3. Identify user.
4. Identify active role.
5. Identify table/view.
6. Identify column.
7. Identify masking policy.
8. Determine whether policy is attached.
9. Review recent policy changes.
10. Review recent role grants.
11. Determine affected users.
12. Determine affected queries.
13. Restrict access if necessary.
14. Correct policy or grants.
15. Validate with negative tests.
16. Review query history.
17. Determine exposure scope.
18. Engage security/privacy process.
19. Document root cause.
20. Add preventive control.

---

# Part 30 — Emergency Containment

## 75. Containment Options

Depending on severity, options include revoking SELECT, revoking a role, disabling a user, correcting the masking policy, restricting network access, or suspending downstream exports.

Choose the minimum action that safely contains exposure.

## 76. Preserve Evidence

Preserve relevant query IDs, login activity, role grants, policy definitions, policy references, change history, and timestamps according to incident procedures.

---

# Part 31 — Change Management

## 77. Masking Policy Changes Are Security Changes

Changing authorized roles, masking transformation, policy attachment, policy ownership, or policy references can change who sees sensitive data.

## 78. Pre-Change Checklist

- Sensitive column identified
- Data owner approved
- Security/privacy requirement documented
- Authorized roles identified
- Masked output defined
- Data type validated
- Dependencies identified
- Positive test ready
- Negative test ready
- Rollback ready

## 79. Post-Change Checklist

- Authorized role sees expected value
- Limited role sees masked value
- No-access role remains denied
- Applications work
- BI reports work
- Exports validated
- Policy metadata correct
- Monitoring clean

---

# Part 32 — Infrastructure as Code

## 80. Policies as Code

Where practical, manage masking policies and policy attachments through controlled IaC or version-controlled deployment processes.

## 81. Security Review

Changes should clearly show old/new authorization, old/new mask behavior, affected columns, and reason for change.

## 82. Drift Detection

Detect differences between expected and actual policy definitions, attachments, owners, role grants, and sensitive-column coverage.

---

# Part 33 — Production Design Example

## 83. Customer Table

Suppose CUSTOMER contains CUSTOMER_ID, NAME, EMAIL, PHONE, SSN, and CREATED_AT.

A governance design could leave identifiers/timestamps unmasked where appropriate while protecting NAME, EMAIL, PHONE, and SSN according to business policy.

## 84. Role Behavior

- PII_PRIVILEGED_READER → raw approved PII
- DATA_ANALYST → masked PII
- APPLICATION_ROLE → application-specific visibility
- UNAUTHORIZED_ROLE → no table access

---

# Part 34 — Hands-On Lab

## 85. Lab Objective

Create a governance schema, masking policies, protected table, privileged role, and analyst role, then validate positive and negative behavior.

Use non-production only.

## 86. Create Lab Database

```sql
CREATE OR REPLACE DATABASE masking_lab;
```

## 87. Create Schemas

```sql
CREATE OR REPLACE SCHEMA
masking_lab.data;

CREATE OR REPLACE SCHEMA
masking_lab.policies;
```

## 88. Create Table

```sql
CREATE OR REPLACE TABLE
masking_lab.data.customer (
    customer_id NUMBER,
    customer_name STRING,
    email STRING,
    phone STRING,
    ssn STRING
);
```

## 89. Insert Test Data

Use fictional values only:

```sql
INSERT INTO masking_lab.data.customer
VALUES
(
    1001,
    'Jane Example',
    'jane@example.com',
    '704-555-1234',
    '123-45-6789'
);
```

Never use real PII in a training lab.

## 90. Create Roles

```sql
CREATE ROLE masking_lab_privileged;
CREATE ROLE masking_lab_analyst;
```

## 91. Grant Basic Access

Grant required database/schema/table privileges to both lab roles according to the environment's role hierarchy.

The objective is for both roles to query the table while seeing different protected values.

## 92. Create Email Policy

```sql
CREATE OR REPLACE MASKING POLICY
masking_lab.policies.email_mask
AS (val STRING)
RETURNS STRING ->
    CASE
        WHEN IS_ROLE_IN_SESSION(
            'MASKING_LAB_PRIVILEGED'
        )
            THEN val
        WHEN val IS NULL
            THEN NULL
        ELSE '***MASKED***'
    END;
```

## 93. Create Phone Policy

```sql
CREATE OR REPLACE MASKING POLICY
masking_lab.policies.phone_mask
AS (val STRING)
RETURNS STRING ->
    CASE
        WHEN IS_ROLE_IN_SESSION(
            'MASKING_LAB_PRIVILEGED'
        )
            THEN val
        WHEN val IS NULL
            THEN NULL
        ELSE 'XXX-XXX-XXXX'
    END;
```

## 94. Create SSN Policy

```sql
CREATE OR REPLACE MASKING POLICY
masking_lab.policies.ssn_mask
AS (val STRING)
RETURNS STRING ->
    CASE
        WHEN IS_ROLE_IN_SESSION(
            'MASKING_LAB_PRIVILEGED'
        )
            THEN val
        WHEN val IS NULL
            THEN NULL
        ELSE 'XXX-XX-XXXX'
    END;
```

## 95. Apply Policies

```sql
ALTER TABLE masking_lab.data.customer
MODIFY COLUMN email
SET MASKING POLICY
masking_lab.policies.email_mask;
```

```sql
ALTER TABLE masking_lab.data.customer
MODIFY COLUMN phone
SET MASKING POLICY
masking_lab.policies.phone_mask;
```

```sql
ALTER TABLE masking_lab.data.customer
MODIFY COLUMN ssn
SET MASKING POLICY
masking_lab.policies.ssn_mask;
```

## 96. Test Privileged Role

Query the table using the privileged lab role. Expected: fictional raw email, phone, and SSN values are visible.

## 97. Test Analyst Role

Query using the analyst role. Expected:

```text
EMAIL         PHONE          SSN
------------  -------------  -----------
***MASKED***  XXX-XXX-XXXX   XXX-XX-XXXX
```

## 98. Negative Test

Use a role with no table access. Expected: SELECT denied.

This validates that masking is not a replacement for RBAC.

## 99. Inspect Policies

Use supported Snowflake metadata commands/functions to review policy definitions, ownership, column associations, and dependencies.

## 100. Test Policy Removal

In the controlled lab only:

```sql
ALTER TABLE masking_lab.data.customer
MODIFY COLUMN email
UNSET MASKING POLICY;
```

Query as the analyst and observe that raw data can become visible if SELECT access remains.

Reapply the policy after the test.

## 101. Cleanup

Remove policy associations before dropping dependent objects where required, then clean up:

```sql
DROP DATABASE IF EXISTS masking_lab;

DROP ROLE IF EXISTS masking_lab_privileged;
DROP ROLE IF EXISTS masking_lab_analyst;
```

Follow dependency-safe cleanup order.

---

# Part 35 — Production Checklist

## 102. Policy Checklist

- Policy purpose documented
- Sensitive data category known
- Authorized roles approved
- Masked output approved
- NULL behavior defined
- Data type correct
- Owner controlled
- Positive test completed
- Negative test completed
- Dependencies documented

## 103. Column Checklist

- Column classified
- Sensitivity understood
- Masking requirement determined
- Correct policy attached
- Tagging considered
- Views tested
- Sharing tested if applicable
- Clone/recovery behavior understood

## 104. Role Checklist

- Raw-data roles minimized
- Role hierarchy reviewed
- Secondary-role behavior understood
- Service roles reviewed
- Analyst roles tested
- Support roles tested
- No direct-user exceptions unless justified

## 105. Monitoring Checklist

- Masking policy inventory
- Sensitive-column inventory
- Policy-reference inventory
- Raw-access roles monitored
- Policy changes monitored
- Coverage gaps detected
- Query activity available for investigation

---

# Acceptance Criteria

The chapter is complete when you can:

- explain dynamic data masking
- distinguish masking from RBAC
- explain and create masking policies
- create type-compatible policies
- preserve NULL behavior
- design role-aware masking
- understand CURRENT_ROLE considerations
- use role-context functions appropriately
- mask email addresses, phone numbers, and SSNs
- protect PHI/PII
- attach and safely remove masking policies
- understand the blast radius of policy changes
- centralize governance policies
- design policy ownership and naming
- avoid hard-coded user lists
- understand view, sharing, clone, and recovery considerations
- monitor policy references
- identify coverage gaps
- understand tag-based masking
- test privileged, limited, and no-access roles
- evaluate performance implications
- troubleshoot unexpected masking
- respond to unexpected raw-data exposure
- execute a masking incident runbook
- manage policy changes through change control
- manage policies through IaC/version control
- build a production masking architecture

---

## Key Takeaways

Dynamic Data Masking allows Snowflake to return different representations of sensitive data based on policy logic while leaving the underlying stored value unchanged.

Masking does not replace RBAC. Use RBAC + masking so unauthorized users cannot query the data, while authorized-but-limited users receive protected values.

Prefer role-based policy logic over lists of individual users.

Protect sensitive categories such as PII, PHI, financial data, credentials, and internal identifiers with centrally governed policies.

Always test:

```text
Privileged role → Raw
Limited role    → Masked
No-access role  → Denied
```

Removing a masking policy can expose raw data immediately to existing table readers. Masking policy changes are production security changes.

A user having permission to query a column does not automatically mean the user should see its raw value.

The next chapter is **Chapter 34 — Row Access Policies**.
