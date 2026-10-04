# 34 — Row Access Policies

## Overview

Dynamic Data Masking controls **what value a user sees in a column**.

Row Access Policies solve a different problem:

> Which rows should the user be allowed to see?

Consider a table containing customers from multiple regions:

```text
CUSTOMER_ID | REGION | CUSTOMER_NAME
------------+--------+--------------
1001        | EAST   | Jane
1002        | WEST   | Robert
1003        | SOUTH  | Maria
1004        | EAST   | David
```

An East-region analyst may be allowed to see the EAST rows but not WEST or SOUTH rows.

Instead of creating separate regional tables or views, Snowflake can dynamically determine which rows are visible.

Conceptually:

```text
Query
  |
  v
Row Access Policy
  |
  +---- Allowed row → Returned
  |
  +---- Unauthorized row → Filtered
```

The underlying table still contains every row.

This chapter covers Row Access Policies, role-based filtering, user-based entitlements, mapping tables, regional access, tenant isolation, business-unit isolation, multi-column policies, policy ownership, centralized governance, masking integration, testing, performance, monitoring, troubleshooting, incident response, and production rollout.

---

# Part 1 — What Is a Row Access Policy?

## 1. Definition

A Row Access Policy is a Snowflake schema-level security object that determines whether an individual row should be visible during query execution.

```text
Stored Rows
    |
    v
Row Access Policy
    |
    +---- TRUE  → Return row
    |
    +---- FALSE → Filter row
```

## 2. Data Is Not Deleted

If a table contains EAST, WEST, SOUTH, and NORTH rows, a user might see only EAST. The other rows still exist and are filtered from that user's query result.

## 3. Transparent Enforcement

Applications can continue executing:

```sql
SELECT *
FROM customer;
```

The application does not need to add a security WHERE clause. Snowflake applies the policy automatically.

---

# Part 2 — Why Row-Level Security Matters

## 4. Application Filtering Is Not Enough

An application may normally query:

```sql
SELECT *
FROM customer
WHERE region = 'EAST';
```

But a user with direct Snowflake access could potentially omit that filter. Application filtering alone is not database-enforced row security.

## 5. Centralized Enforcement

Applications, BI tools, SQL worksheets, Python, JDBC, and ODBC can query the same protected object while Snowflake evaluates the row policy centrally.

---

# Part 3 — Row Access Policy Object

## 6. Schema-Level Object

A Row Access Policy belongs to a schema, for example:

```text
GOVERNANCE_DB.POLICIES.REGION_ACCESS_POLICY
```

## 7. Basic Policy Structure

```sql
CREATE ROW ACCESS POLICY region_access_policy
AS (region STRING)
RETURNS BOOLEAN ->
    CASE
        WHEN <authorized-condition>
            THEN TRUE
        ELSE FALSE
    END;
```

TRUE means visible; FALSE means filtered.

## 8. Policy Signature

The policy receives one or more values from the protected table.

```sql
AS (region STRING)
RETURNS BOOLEAN
```

The protected table column must be compatible with the policy signature.

---

# Part 4 — Role-Based Row Access

## 9. Simple Role Example

```sql
CREATE ROW ACCESS POLICY east_region_policy
AS (region STRING)
RETURNS BOOLEAN ->
    CASE
        WHEN IS_ROLE_IN_SESSION('REGION_ADMIN')
            THEN TRUE
        WHEN IS_ROLE_IN_SESSION('EAST_ANALYST')
             AND region = 'EAST'
            THEN TRUE
        ELSE FALSE
    END;
```

## 10. Administrator Access

A privileged role may need all rows:

```sql
WHEN IS_ROLE_IN_SESSION('REGION_ADMIN')
THEN TRUE
```

Use broad access only where required.

## 11. Limited Role

For an East analyst:

```text
region = EAST  → TRUE
region = WEST  → FALSE
region = SOUTH → FALSE
```

---

# Part 5 — Apply Row Access Policy

## 12. Example Table

```sql
CREATE TABLE customer (
    customer_id NUMBER,
    region STRING,
    customer_name STRING
);
```

## 13. Attach Policy

```sql
ALTER TABLE customer
ADD ROW ACCESS POLICY region_access_policy
ON (region);
```

## 14. Query

```sql
SELECT *
FROM customer;
```

The visible result depends on policy execution context.

---

# Part 6 — Removing a Policy

## 15. Drop Policy from Table

```sql
ALTER TABLE customer
DROP ROW ACCESS POLICY region_access_policy;
```

## 16. Security Impact

Removing a Row Access Policy can immediately expose rows previously filtered from users who already have SELECT.

Treat DROP ROW ACCESS POLICY as a production security change.

---

# Part 7 — Mapping Table Architecture

## 17. Why Mapping Tables?

Hard-coding every role/region combination inside policy logic does not scale.

A mapping table is usually easier to maintain.

## 18. Example Mapping Table

```text
ROLE_NAME      | REGION
---------------+-------
EAST_ANALYST   | EAST
WEST_ANALYST   | WEST
SOUTH_ANALYST  | SOUTH
REGION_MANAGER | EAST
REGION_MANAGER | WEST
```

## 19. Policy Architecture

Query → Row Access Policy → Entitlement Mapping Table → TRUE/FALSE.

---

# Part 8 — Entitlement Mapping Table

## 20. Create Mapping Table

```sql
CREATE TABLE governance_db.security.region_entitlements (
    role_name STRING,
    region STRING
);
```

## 21. Example Data

```sql
INSERT INTO governance_db.security.region_entitlements
VALUES
    ('EAST_ANALYST', 'EAST'),
    ('WEST_ANALYST', 'WEST'),
    ('SOUTH_ANALYST', 'SOUTH');
```

## 22. Policy Using Mapping Table

```sql
CREATE ROW ACCESS POLICY
governance_db.policies.region_policy
AS (region STRING)
RETURNS BOOLEAN ->
    IS_ROLE_IN_SESSION('REGION_ADMIN')
    OR EXISTS (
        SELECT 1
        FROM governance_db.security.region_entitlements e
        WHERE e.region = region
          AND IS_ROLE_IN_SESSION(e.role_name)
    );
```

Validate exact supported policy expression and context-function behavior before production deployment.

---

# Part 9 — Why Mapping Tables Scale

## 23. Add New Entitlement

```sql
INSERT INTO governance_db.security.region_entitlements
VALUES ('CENTRAL_ANALYST', 'CENTRAL');
```

The policy logic remains stable.

## 24. Remove Entitlement

```sql
DELETE FROM governance_db.security.region_entitlements
WHERE role_name = 'WEST_ANALYST'
  AND region = 'WEST';
```

Mapping-table modifications can change production access immediately and should be treated as security changes.

---

# Part 10 — User-Based Entitlements

## 25. User Mapping

Some use cases require individual user entitlements:

```text
USER_NAME | REGION
----------+-------
ALICE     | EAST
BOB       | WEST
CAROL     | SOUTH
```

## 26. Policy Concept

```sql
EXISTS (
    SELECT 1
    FROM user_region_entitlements e
    WHERE e.user_name = CURRENT_USER()
      AND e.region = region
)
```

## 27. Prefer Roles Where Possible

Role-based entitlements are generally easier to manage at scale. Use user-specific mapping when the business requirement genuinely depends on individual identity.

---

# Part 11 — Multi-Region Access

## 28. Multiple Entitlements

A manager may need EAST and WEST while an analyst needs only EAST. Mapping tables naturally support multiple rows per role or user.

## 29. Example

```text
ROLE_NAME       | REGION
----------------+-------
REGION_MANAGER  | EAST
REGION_MANAGER  | WEST
EAST_ANALYST    | EAST
```

---

# Part 12 — Tenant Isolation

## 30. Multi-Tenant Data

```text
TENANT_ID | CUSTOMER_ID | DATA
----------+-------------+------
TENANT_A  | 1001        | ...
TENANT_B  | 2001        | ...
TENANT_C  | 3001        | ...
```

Applications should not expose one tenant's data to another.

## 31. Tenant Row Policy

Application identity → tenant entitlement → Row Access Policy → authorized tenant rows.

## 32. Defense in Depth

Tenant isolation should not rely solely on an application-provided WHERE TENANT_ID predicate. Database-enforced filtering can provide another security boundary.

---

# Part 13 — Business Unit Isolation

## 33. Example

A global company might have HEALTHCARE, FINANCE, RETAIL, and INTERNAL business units. Users should see only authorized units.

## 34. Policy Design

Use a business-unit entitlement mapping rather than duplicating tables for each organizational unit where centralized storage is appropriate.

---

# Part 14 — Environment Isolation

## 35. Environment Column

Some shared datasets may contain DEV, STAGING, and PROD attributes. A Row Access Policy can enforce environment-specific visibility.

## 36. Better Architecture First

Do not use Row Access Policies to compensate for poor environment isolation. Production and non-production should still follow appropriate architectural separation.

---

# Part 15 — Multi-Column Policies

## 37. More Than One Input

A policy can use multiple columns when supported by the policy design, such as Region + Business Unit.

## 38. Signature

```sql
AS (
    region STRING,
    business_unit STRING
)
RETURNS BOOLEAN
```

## 39. Example Rule

A user may require entitlement to both REGION = EAST and BUSINESS_UNIT = HEALTHCARE before a row is visible.

---

# Part 16 — Mapping Table Security

## 40. Mapping Table Is Security-Critical

If a policy depends on REGION_ENTITLEMENTS, modifying that table modifies effective data access.

## 41. Restrict Write Access

Do not allow ordinary analysts to INSERT, UPDATE, or DELETE security mapping rows.

## 42. Dedicated Administrative Role

Consider ROW_ACCESS_ADMIN or DATA_GOVERNANCE_ADMIN for entitlement management.

---

# Part 17 — Mapping Table Integrity

## 43. Validate Values

Prevent inconsistent values such as EAST, east, East, and EAST_REGION if the protected table uses one canonical value.

## 44. Standardize Entitlements

Use controlled values and governance processes. Entitlement mistakes can produce either excessive or missing access.

---

# Part 18 — Row Access + Dynamic Masking

## 45. Different Problems

Row Access Policy answers: Which rows?

Masking Policy answers: Which values?

They can work together.

## 46. Example

An East analyst can see only East customers through a Row Access Policy while email and SSN remain masked through masking policies.

## 47. Combined Architecture

Query → Row Access Policy → Allowed Rows → Masking Policies → Protected Values.

Understand exact current Snowflake evaluation behavior from current policy documentation.

---

# Part 19 — Secure Views vs Row Access Policies

## 48. Secure View Pattern

Organizations sometimes create EAST_CUSTOMERS_VIEW, WEST_CUSTOMERS_VIEW, and SOUTH_CUSTOMERS_VIEW.

## 49. Scaling Problem

Many regions, business units, and user classes can create significant view sprawl.

## 50. Row Access Policy Advantage

A centralized policy can often enforce row authorization while applications query the same object. Secure views remain useful for other security and abstraction requirements.

---

# Part 20 — Policy Ownership

## 51. Central Governance

A common model uses a governance database with POLICIES and ENTITLEMENTS schemas/areas.

## 52. Separation of Duties

Application teams can own application tables, governance teams can own row policies, and security administrators can control governance roles.

---

# Part 21 — Policy Naming

## 53. Clear Names

Examples:

- REGION_ACCESS_POLICY
- TENANT_ACCESS_POLICY
- BUSINESS_UNIT_ACCESS_POLICY
- PATIENT_ORG_ACCESS_POLICY
- ENVIRONMENT_ACCESS_POLICY

## 54. Avoid Generic Names

Avoid POLICY1, ROW_POLICY_NEW, or ACCESS_TEMP. Policy names should communicate intent.

---

# Part 22 — NULL Handling

## 55. NULL Security Column

If REGION = NULL, determine whether the row should be visible. The safest default is normally FALSE unless explicitly required otherwise.

## 56. Fail Closed

```sql
CASE
    WHEN <explicit authorization>
        THEN TRUE
    ELSE FALSE
END
```

Avoid defaulting to TRUE.

---

# Part 23 — Privileged Roles

## 57. Administrative Bypass

```sql
WHEN IS_ROLE_IN_SESSION('DATA_GOVERNANCE_ADMIN')
THEN TRUE
```

## 58. Minimize Bypass Roles

Every bypass role increases the blast radius of a compromised account. Keep bypass roles limited and monitored.

---

# Part 24 — Testing

## 59. Test Matrix

| Role | EAST | WEST | SOUTH |
|---|---:|---:|---:|
| EAST_ANALYST | Yes | No | No |
| WEST_ANALYST | No | Yes | No |
| REGION_MANAGER | Yes | Yes | No |
| REGION_ADMIN | Yes | Yes | Yes |

## 60. Test Every Combination

Do not test only EAST_ANALYST → EAST. Also test EAST_ANALYST → WEST and EAST_ANALYST → SOUTH.

Negative tests are essential.

---

# Part 25 — Role Hierarchy Testing

## 61. Inherited Roles

Understand how role inheritance/session semantics affect policy evaluation.

## 62. Secondary Roles

Policy design and testing should reflect actual primary/secondary role behavior used by applications and users.

---

# Part 26 — Application Testing

## 63. Test Through the Real Application

A policy may appear correct in a worksheet but differ through an application because of service users, roles, secondary roles, connection pools, or session reuse.

## 64. Capture Session Context

```sql
SELECT
    CURRENT_USER(),
    CURRENT_ROLE();
```

Capture other relevant supported context functions as needed.

---

# Part 27 — BI Tool Testing

## 65. BI Connections

BI tools may use shared service users, per-user OAuth, dedicated roles, or connection pools. Understand which identity Snowflake evaluates.

## 66. Shared Service Account Risk

If every BI user connects as BI_SERVICE_USER, Snowflake may not see individual end-user identity unless the architecture provides it.

Design policies accordingly.

---

# Part 28 — Performance

## 67. Policy Evaluation Cost

Row Access Policies add query-processing work. Complex policies referencing large mapping tables can affect performance.

## 68. Mapping Table Size

Keep entitlement tables focused, governed, and appropriately designed.

## 69. Benchmark

Compare before/after policy query duration, warehouse consumption, Query Profile, scan behavior, and concurrency.

---

# Part 29 — Query Profile

## 70. Investigate Slow Queries

1. Capture query ID.
2. Open Query Profile.
3. Compare previous execution.
4. Review policy complexity.
5. Review mapping-table access.
6. Review warehouse load.
7. Review pruning behavior.
8. Test representative roles.

## 71. Do Not Remove Security for Performance

Do not permanently remove a required security policy merely because a query became slower. Optimize while preserving controls.

---

# Part 30 — Monitoring

## 72. Governance Inventory

Administrators should know which Row Access Policies exist, which tables use them, which columns feed them, which mapping tables they reference, and which roles bypass them.

## 73. Policy References

Use Snowflake metadata capabilities to inspect policy references and dependencies.

## 74. Entitlement Monitoring

Track changes to role-to-region, user-to-tenant, business-unit mappings, and privileged bypass roles.

These are access-control changes.

---

# Part 31 — Troubleshooting

## 75. User Sees No Rows

Check SELECT privilege, policy attachment, active role, role hierarchy, entitlement mapping, security-column value, and NULL behavior.

## 76. User Sees Too Many Rows

Treat this as a potential security incident.

Check policy logic, mapping table, role grants, bypass roles, secondary roles, policy attachment, and recent changes.

## 77. Policy Cannot Be Applied

Check column type, policy signature, privileges, existing policies, object type, ownership, and dependencies.

## 78. Query Fails After Policy Change

Possible causes include invalid policy SQL, missing mapping table, missing privileges, type mismatch, or dependency changes.

Correct or roll back promptly.

---

# Part 32 — Data Exposure Incident Runbook

## 79. Unexpected Row Exposure

1. Capture timestamp.
2. Capture query ID.
3. Identify user.
4. Identify active role.
5. Identify secondary-role context.
6. Identify table/view.
7. Identify Row Access Policy.
8. Capture policy definition.
9. Identify mapping table.
10. Capture relevant entitlement rows.
11. Review recent mapping changes.
12. Review recent role grants.
13. Review recent policy changes.
14. Determine affected users.
15. Determine affected queries.
16. Contain access.
17. Correct policy or entitlement.
18. Run negative tests.
19. Review query history.
20. Determine exposure scope.
21. Engage security/privacy process.
22. Document root cause.
23. Add preventive controls.

---

# Part 33 — Emergency Containment

## 80. Containment Options

Depending on severity: revoke SELECT, revoke role, remove entitlement, disable user, correct policy, or suspend downstream export.

## 81. Preserve Evidence

Preserve query IDs, policy definitions, entitlement records, role grants, login history, and change timestamps where incident procedures require it.

---

# Part 34 — Change Management

## 82. Policy Changes Are Security Changes

Changes to policy logic, mapping tables, policy attachment, bypass roles, or role hierarchy can change effective row visibility.

## 83. Pre-Change Checklist

- Business requirement approved
- Protected object identified
- Security column identified
- Entitlement source identified
- Privileged roles identified
- NULL behavior defined
- Positive tests ready
- Negative tests ready
- Performance baseline captured
- Rollback ready

## 84. Post-Change Checklist

- Authorized rows visible
- Unauthorized rows hidden
- Bypass role behaves correctly
- Masking still works
- Application works
- BI reports work
- Performance acceptable
- Monitoring clean

---

# Part 35 — Infrastructure as Code

## 85. Policy as Code

Where practical, manage Row Access Policies, policy attachments, role grants, and governance objects through controlled deployment pipelines.

## 86. Mapping Data

Entitlement mapping tables may require a separate controlled workflow. Do not treat security mappings as ordinary application data.

## 87. Review Changes

A mapping change such as FINANCE_ROLE → ALL_REGIONS should receive appropriate security review.

---

# Part 36 — Production Design Example

## 88. Healthcare Organization Access

Suppose PATIENT_ACTIVITY contains PATIENT_ID, ORGANIZATION_ID, REGION, DIAGNOSIS, and EVENT_DATE.

Users should see only authorized organizations.

## 89. Entitlement Table

```text
ROLE_NAME          | ORGANIZATION_ID
-------------------+----------------
ORG_A_ANALYST      | ORG_A
ORG_B_ANALYST      | ORG_B
ENTERPRISE_ANALYST | ORG_A
ENTERPRISE_ANALYST | ORG_B
```

## 90. Combined Governance

PATIENT_ACTIVITY can use a Row Access Policy for organization authorization and masking policies for PHI protection.

---

# Part 37 — Hands-On Lab

## 91. Lab Objective

Create a customer table, region entitlement table, Row Access Policy, East analyst role, West analyst role, and admin role.

Then validate access in non-production.

## 92. Create Database

```sql
CREATE OR REPLACE DATABASE row_access_lab;
```

## 93. Create Schemas

```sql
CREATE OR REPLACE SCHEMA
row_access_lab.data;

CREATE OR REPLACE SCHEMA
row_access_lab.governance;
```

## 94. Create Customer Table

```sql
CREATE OR REPLACE TABLE
row_access_lab.data.customer (
    customer_id NUMBER,
    region STRING,
    customer_name STRING,
    email STRING
);
```

## 95. Insert Fictional Data

```sql
INSERT INTO row_access_lab.data.customer
VALUES
    (1001, 'EAST',  'Jane Example',   'jane@example.com'),
    (1002, 'WEST',  'Robert Example', 'robert@example.com'),
    (1003, 'SOUTH', 'Maria Example',  'maria@example.com'),
    (1004, 'EAST',  'David Example',  'david@example.com');
```

## 96. Create Roles

```sql
CREATE ROLE row_lab_east;
CREATE ROLE row_lab_west;
CREATE ROLE row_lab_admin;
```

Grant required database/schema/table privileges according to the lab role hierarchy.

## 97. Create Entitlement Table

```sql
CREATE OR REPLACE TABLE
row_access_lab.governance.region_entitlements (
    role_name STRING,
    region STRING
);
```

## 98. Add Entitlements

```sql
INSERT INTO
row_access_lab.governance.region_entitlements
VALUES
    ('ROW_LAB_EAST', 'EAST'),
    ('ROW_LAB_WEST', 'WEST');
```

## 99. Create Row Access Policy

```sql
CREATE OR REPLACE ROW ACCESS POLICY
row_access_lab.governance.region_policy
AS (region STRING)
RETURNS BOOLEAN ->
    IS_ROLE_IN_SESSION('ROW_LAB_ADMIN')
    OR EXISTS (
        SELECT 1
        FROM row_access_lab.governance.region_entitlements e
        WHERE e.region = region
          AND IS_ROLE_IN_SESSION(e.role_name)
    );
```

Validate exact supported expression against current Snowflake behavior before using this pattern in production.

## 100. Apply Policy

```sql
ALTER TABLE row_access_lab.data.customer
ADD ROW ACCESS POLICY
row_access_lab.governance.region_policy
ON (region);
```

## 101. Test East Role

Using ROW_LAB_EAST:

```sql
SELECT *
FROM row_access_lab.data.customer
ORDER BY customer_id;
```

Expected:

```text
1001 | EAST | Jane Example
1004 | EAST | David Example
```

No West or South rows should appear.

## 102. Test West Role

Using ROW_LAB_WEST, expected:

```text
1002 | WEST | Robert Example
```

No East or South rows should appear.

## 103. Test Admin

Using ROW_LAB_ADMIN, all four rows should be visible.

## 104. Negative Test

As East:

```sql
SELECT *
FROM row_access_lab.data.customer
WHERE region = 'WEST';
```

Expected: 0 rows.

The user cannot bypass the policy by explicitly requesting another region.

## 105. Add Entitlement

```sql
INSERT INTO
row_access_lab.governance.region_entitlements
VALUES
    ('ROW_LAB_EAST', 'SOUTH');
```

Retest. The East role should now see EAST and SOUTH.

## 106. Remove Entitlement

```sql
DELETE FROM
row_access_lab.governance.region_entitlements
WHERE role_name = 'ROW_LAB_EAST'
  AND region = 'SOUTH';
```

Retest. SOUTH should disappear.

## 107. Remove Policy Test

In the controlled lab only:

```sql
ALTER TABLE row_access_lab.data.customer
DROP ROW ACCESS POLICY
row_access_lab.governance.region_policy;
```

Query as the East role and observe that all rows can become visible if the role retains table SELECT.

This demonstrates why removing a Row Access Policy is security-sensitive.

## 108. Cleanup

Remove policy associations before dropping dependent objects where required.

```sql
DROP DATABASE IF EXISTS row_access_lab;

DROP ROLE IF EXISTS row_lab_east;
DROP ROLE IF EXISTS row_lab_west;
DROP ROLE IF EXISTS row_lab_admin;
```

Follow dependency-safe cleanup order.

---

# Part 38 — Production Checklist

## 109. Policy Checklist

- Business requirement documented
- Security column identified
- Policy centrally managed
- Fail-closed behavior
- NULL behavior defined
- Bypass roles minimized
- Positive tests completed
- Negative tests completed
- Dependencies documented
- Performance tested

## 110. Entitlement Checklist

- Mapping table protected
- Write access restricted
- Values standardized
- Change workflow controlled
- Expired access removed
- Duplicate mappings reviewed
- Privileged mappings monitored

## 111. Application Checklist

- Application user identified
- Active role known
- Connection pool tested
- Session reuse tested
- BI identity model understood
- Direct SQL tested
- Application path tested

## 112. Monitoring Checklist

- Policy inventory
- Policy references
- Entitlement changes
- Bypass roles
- Role grants
- Query history
- Exposure investigation process

---

# Acceptance Criteria

The chapter is complete when you can:

- explain Row Access Policies
- distinguish row security from masking
- create Row Access Policies
- attach policies to tables
- remove policies safely
- design role-based row access
- use mapping tables
- design user-specific entitlements where required
- support multi-region access
- design tenant isolation
- design business-unit isolation
- create multi-column policy concepts
- secure entitlement tables
- standardize entitlement values
- combine Row Access Policies with masking
- compare secure views with Row Access Policies
- centralize policy ownership
- design fail-closed behavior
- handle NULL security attributes
- minimize privileged bypass roles
- build positive and negative test matrices
- test role hierarchy
- test secondary-role behavior
- test applications and BI tools
- understand shared service-account risks
- evaluate performance impact
- investigate Query Profile
- monitor policy references
- monitor entitlement changes
- troubleshoot missing rows
- investigate excess row visibility
- execute a data-exposure incident runbook
- perform emergency containment
- manage changes through controlled workflows
- manage policies through IaC
- build a production row-security architecture

---

## Key Takeaways

Dynamic Data Masking answers: What value can this user see?

Row Access Policies answer: Which rows can this user see?

Together:

```text
Query
  |
  v
Row Access Policy
  |
  v
Authorized Rows
  |
  v
Masking Policy
  |
  v
Authorized Values
```

Do not rely solely on application WHERE clauses for security-sensitive row isolation.

Use mapping tables when entitlement relationships become too large or dynamic to maintain safely inside policy SQL.

Protect entitlement tables as security objects because changing entitlement data changes effective authorization.

Design policies to fail closed.

Always test allowed rows, unauthorized rows, and explicitly approved administrator behavior.

If a user sees rows that should have been filtered, treat the event as a potential security incident.

Table access does not automatically mean access to every row in that table.

The next chapter is **Chapter 35 — Tags, Classification & Governance**.
