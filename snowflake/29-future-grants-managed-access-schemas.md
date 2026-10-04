# 29 — Future Grants & Managed Access Schemas

## Overview

A Snowflake role can have perfect access today and fail tomorrow when a new object is created.

Example:

```text
Today

REPORTING_READER
    |
    +---- SELECT → TABLE_A
    +---- SELECT → TABLE_B
```

Tomorrow:

```text
TABLE_C created
```

Unless access to future objects has been configured:

```text
REPORTING_READER
    |
    +---- TABLE_A ✓
    +---- TABLE_B ✓
    +---- TABLE_C ✗
```

Future grants solve this problem.

Managed access schemas solve a related governance problem: who is allowed to grant privileges on objects inside a schema?

Together, future grants and managed access schemas provide a powerful foundation for scalable Snowflake privilege administration.

---

# Part 1 — Existing vs Future Grants

## 1. Existing Object Grants

Suppose a schema contains CUSTOMERS, ORDERS, and PAYMENTS.

You can grant SELECT on all existing tables:

```sql
GRANT SELECT
ON ALL TABLES IN SCHEMA analytics.reporting
TO ROLE reporting_reader;
```

This applies to the applicable tables that exist at the time the command is executed.

---

## 2. What Happens to a New Table?

Later:

```sql
CREATE TABLE analytics.reporting.claims (
    claim_id NUMBER,
    amount NUMBER
);
```

The earlier ON ALL TABLES grant does not automatically mean the new table receives SELECT.

That requires a future grant.

---

## 3. Future Grant

```sql
GRANT SELECT
ON FUTURE TABLES IN SCHEMA analytics.reporting
TO ROLE reporting_reader;
```

Now newly created tables within that future-grant scope can receive the configured privilege.

---

## 4. Existing + Future Pattern

```sql
GRANT SELECT
ON ALL TABLES IN SCHEMA analytics.reporting
TO ROLE reporting_reader;

GRANT SELECT
ON FUTURE TABLES IN SCHEMA analytics.reporting
TO ROLE reporting_reader;
```

ON ALL handles existing objects. ON FUTURE handles objects created later.

---

# Part 2 — Complete Read Access

## 5. Database USAGE

```sql
GRANT USAGE
ON DATABASE analytics
TO ROLE reporting_reader;
```

Future table SELECT does not replace database access.

---

## 6. Schema USAGE

```sql
GRANT USAGE
ON SCHEMA analytics.reporting
TO ROLE reporting_reader;
```

---

## 7. Existing Tables

```sql
GRANT SELECT
ON ALL TABLES IN SCHEMA analytics.reporting
TO ROLE reporting_reader;
```

---

## 8. Future Tables

```sql
GRANT SELECT
ON FUTURE TABLES IN SCHEMA analytics.reporting
TO ROLE reporting_reader;
```

---

## 9. Warehouse Access

```sql
GRANT USAGE
ON WAREHOUSE analytics_wh
TO ROLE reporting_reader;
```

The complete design can require warehouse USAGE, database USAGE, schema USAGE, existing table SELECT, and future table SELECT.

Do not confuse future object privileges with container or compute privileges.

---

# Part 3 — Future Grants by Object Type

## 10. Future Tables

```sql
GRANT SELECT
ON FUTURE TABLES IN SCHEMA analytics.reporting
TO ROLE reporting_reader;
```

---

## 11. Future Views

```sql
GRANT SELECT
ON FUTURE VIEWS IN SCHEMA analytics.reporting
TO ROLE reporting_reader;
```

A table future grant does not automatically represent every other object type.

---

## 12. Future Sequences

Where required:

```sql
GRANT USAGE
ON FUTURE SEQUENCES IN SCHEMA application.data
TO ROLE application_writer;
```

Grant only object types the workload actually requires.

---

## 13. Other Future Object Types

Snowflake supports future grants for supported securable object types.

Do not assume every Snowflake object supports the same privilege or future-grant behavior.

Always match object type, supported privilege, and required scope.

---

# Part 4 — Schema-Level vs Database-Level Future Grants

## 14. Schema-Level Future Grants

```sql
GRANT SELECT
ON FUTURE TABLES IN SCHEMA analytics.reporting
TO ROLE reporting_reader;
```

The scope is future tables within ANALYTICS.REPORTING.

---

## 15. Database-Level Future Grants

Snowflake also supports future grants at database scope for supported objects.

```sql
GRANT SELECT
ON FUTURE TABLES IN DATABASE analytics
TO ROLE analytics_reader;
```

This is broader than a single-schema future grant.

---

## 16. Scope Carefully

Before using database-level future grants, ask whether the role should automatically read tables in every applicable schema in the database.

If not, use narrower schema-level grants.

Least privilege applies to future grants too.

---

# Part 5 — Why Future Grants Matter

## 17. Manual Grant Problem

Without future grants, a developer can create a table, an application can fail, a ticket can be opened, and an administrator then has to grant access manually.

This creates operational friction and inconsistent access.

---

## 18. Automated Access Model

With properly designed future grants, an object is created and the expected future-grant policy provides the intended role access.

This improves consistency and reduces repetitive manual administration.

---

## 19. Future Grants Are Policy

A future grant effectively says every future object of this supported type in this scope should receive this privilege for this role.

Treat it as an access policy, not merely a convenience command.

---

# Part 6 — Security Risks of Future Grants

## 20. Future Grants Can Be Too Broad

```sql
GRANT SELECT
ON FUTURE TABLES IN DATABASE production
TO ROLE broad_reader;
```

This may cause the role to automatically receive access to future tables containing sensitive data.

---

## 21. Sensitive Data Appears Later

A database containing operational data today can later receive PHI, PII, or financial tables.

A broad future grant may automatically extend access.

Therefore future grants require security review.

---

## 22. Prefer Intentional Boundaries

A stronger design may use separate schemas such as REPORTING, SENSITIVE, INTERNAL, and STAGING with different future-grant policies.

Schema architecture and security architecture often reinforce each other.

---

# Part 7 — Inspecting Future Grants

## 23. Show Future Grants

Use Snowflake grant metadata and SHOW commands appropriate to the scope to inspect configured future grants.

Do not assume a future grant exists merely because existing objects currently have access.

---

## 24. Verify Both Current and Future State

During an access review, check both existing grants and future grants.

Both matter.

---

## 25. Why Existing Access Can Hide a Problem

Every current table can work while the first newly created table exposes missing future-grant configuration.

Test future-object behavior explicitly.

---

# Part 8 — Revoking Future Grants

## 26. Revoke Future Table Access

```sql
REVOKE SELECT
ON FUTURE TABLES IN SCHEMA analytics.reporting
FROM ROLE reporting_reader;
```

This changes the policy for future objects in the specified scope.

---

## 27. Existing Objects Require Separate Review

Revoking a future grant does not mean existing object grants should be assumed to disappear.

Future policy and existing grants must be reviewed separately.

---

# Part 9 — Managed Access Schemas

## 28. What Is a Managed Access Schema?

A managed access schema centralizes privilege management for objects within the schema.

The key goal is consistent centralized access governance.

---

## 29. Why Managed Access?

Allowing every object owner to independently manage grants can create inconsistent privileges, unexpected access, security drift, difficult auditing, and manual exceptions.

Managed access schemas provide stronger centralized control.

---

# Part 10 — Create Managed Access Schema

## 30. Create Managed Access Schema

```sql
CREATE SCHEMA analytics.secure_reporting
WITH MANAGED ACCESS;
```

Objects created within this schema follow managed-access privilege-governance behavior.

---

## 31. Verify Schema

```sql
SHOW SCHEMAS LIKE 'SECURE_REPORTING'
IN DATABASE analytics;
```

Review schema metadata to verify its configuration.

---

## 32. Existing Schema Conversion

Snowflake provides mechanisms for changing schema managed-access behavior subject to required privileges and platform rules.

Treat conversion of a production schema as a controlled security change.

Before changing it, review current ownership, grants, automation, deployment roles, future grants, IaC, and operational processes.

---

# Part 11 — Managed Access Governance

## 33. Centralized Grant Administration

In a managed access schema, object owners do not have the same independent grant-management model they would have in a regular schema.

Grant administration is intentionally centralized according to Snowflake's managed-access rules.

---

## 34. Object Ownership Still Matters

Managed access does not mean object ownership disappears.

Objects still have owners.

What changes is how privilege administration is governed.

---

## 35. Why This Is Important

If engineers and pipelines create different objects, decentralized grant management can produce inconsistent access.

Managed access helps enforce a common privilege-management boundary.

---

# Part 12 — Managed Access + Future Grants

## 36. Strong Production Combination

A common production pattern is a managed access schema combined with future grants and access roles.

This creates predictable access for newly created objects while centralizing grant administration.

---

## 37. Example Setup

```sql
CREATE SCHEMA analytics.reporting
WITH MANAGED ACCESS;

GRANT USAGE
ON DATABASE analytics
TO ROLE reporting_reader;

GRANT USAGE
ON SCHEMA analytics.reporting
TO ROLE reporting_reader;

GRANT SELECT
ON FUTURE TABLES IN SCHEMA analytics.reporting
TO ROLE reporting_reader;

GRANT SELECT
ON FUTURE VIEWS IN SCHEMA analytics.reporting
TO ROLE reporting_reader;
```

Also grant access to existing applicable objects where needed.

---

# Part 13 — Object Creation and Access

## 38. Object Creator vs Access Administrator

A useful separation is to let data engineers create objects while a security or schema-governance role controls grants.

This can reduce accidental privilege expansion.

---

## 39. Pipeline-Created Objects

Production pipelines often create or replace objects automatically, including dbt models, ETL staging tables, pipeline objects, and deployment-created views.

Future grants help keep access consistent as these objects appear.

---

## 40. CREATE OR REPLACE Considerations

Object replacement can have security implications depending on the object, ownership, grants, and deployment method.

Production deployments should validate ownership after deployment, existing grants, future-grant behavior, role access, and managed-access behavior.

Do not assume object recreation is security-neutral.

---

# Part 14 — Schema Design for Access Control

## 41. Organize Schemas by Security Boundary

Rather than mixing public reporting, PHI, internal operations, and restricted finance data in one schema, consider deliberate boundaries such as REPORTING, CLINICAL_RESTRICTED, FINANCE_RESTRICTED, INTERNAL, and STAGING where appropriate.

---

## 42. Why Schema Boundaries Help

Future grants operate on scope.

A clean schema boundary makes it easier to grant all future reporting tables to REPORTING_READER without unintentionally granting restricted datasets.

---

# Part 15 — Role Design

## 43. Access Roles

Examples include REPORTING_READ, REPORTING_WRITE, STAGING_READ, STAGING_WRITE, and CLINICAL_READ.

Future grants can be attached to narrowly scoped access roles.

---

## 44. Functional Roles

Access roles can then be inherited by functional roles such as DATA_ANALYST and DATA_ENGINEER.

This keeps resource privileges separate from job-function roles.

---

# Part 16 — Ownership Roles

## 45. Schema Owner

Use controlled ownership roles such as REPORTING_SCHEMA_OWNER rather than tying production schema ownership to an individual.

---

## 46. Object Owner

Similarly, REPORTING_OBJECT_OWNER may own application objects depending on the organization's model.

---

## 47. Ownership Hierarchy

A possible hierarchy is SYSADMIN → DATA_PLATFORM_ADMIN → REPORTING_SCHEMA_OWNER.

Exact design depends on organizational governance.

---

# Part 17 — Infrastructure as Code

## 48. Manage Future Grants as Code

Future grants are security policy.

Store them in controlled IaC where practical.

Benefits include code review, version history, repeatability, environment consistency, and auditability.

---

## 49. Managed Access as Code

Schema managed-access configuration should also be represented in the authoritative deployment model where supported.

Avoid configuration drift between IaC and Snowflake.

---

## 50. Drift Detection

Periodically compare expected future grants, schema configuration, and ownership against actual Snowflake state.

---

# Part 18 — Troubleshooting

## 51. New Table Is Not Accessible

If old tables work but a new table fails, immediately check future grants.

---

## 52. Troubleshooting Flow

Check database USAGE, schema USAGE, object privilege, future-grant configuration, scope, and object type.

---

## 53. Future Grant Exists but Access Still Fails

Check correct role, database, schema, object type, privilege, role inheritance, active role, and warehouse access.

Do not assume the future grant itself is the problem.

---

## 54. Table Works but View Fails

A future TABLE grant may exist while a future VIEW grant is missing.

Object types are separate.

---

## 55. One Schema Works, Another Fails

Check scope.

A future grant on ANALYTICS.REPORTING does not automatically apply to ANALYTICS.FINANCE.

---

## 56. Grant Command Fails in Managed Access Schema

Check whether the executing role is authorized to manage privileges under Snowflake's managed-access rules.

The object creator may not be the appropriate grant administrator.

---

## 57. Pipeline Creates Object but Users Cannot Read It

Check:

1. Object created in expected schema.
2. Future grant exists.
3. Future-grant object type matches.
4. Reader has database USAGE.
5. Reader has schema USAGE.
6. Reader has warehouse access.
7. Reader role is active/inherited.
8. Deployment did not move the object to another scope.

---

# Part 19 — Unexpected Access

## 58. New Object Is Accessible to Too Many Users

Check database-level future grants, schema-level future grants, PUBLIC, inherited roles, database roles, broad access roles, and ownership.

A broad future grant can automatically reproduce overprivilege.

---

## 59. Security Investigation

If a newly created sensitive object automatically becomes accessible to an unauthorized population, preserve evidence, identify the future grant, determine affected objects and roles/users, contain access, review access/query history, and correct policy.

Follow organizational security procedures.

---

# Part 20 — Operational Runbook

## 60. Future Grant Incident Runbook

When a newly created object has incorrect access:

1. Capture object name.
2. Capture object type.
3. Capture database/schema.
4. Capture creation timestamp.
5. Capture owner.
6. Identify expected role.
7. Check database USAGE.
8. Check schema USAGE.
9. Check existing object grants.
10. Check future grants.
11. Check future-grant scope.
12. Check object type.
13. Check role inheritance.
14. Check managed-access state.
15. Check deployment/IaC changes.
16. Compare with a known-good object.
17. Correct the minimum required configuration.
18. Validate expected access.
19. Validate unauthorized access remains blocked.
20. Reconcile IaC.
21. Document root cause.

---

## 61. Managed Access Incident Runbook

If grants cannot be administered as expected:

1. Confirm schema.
2. Confirm managed-access status.
3. Identify schema owner.
4. Identify executing role.
5. Identify object owner.
6. Review required privilege-management authority.
7. Review role hierarchy.
8. Check recent ownership changes.
9. Check IaC changes.
10. Apply the correct governance-role change.
11. Validate grant administration.
12. Document the security model.

Do not bypass managed-access governance by assigning unnecessary administrative roles.

---

# Part 21 — Migration to Managed Access

## 62. Why Migrate?

Organizations may start with regular schemas and later want centralized privilege governance.

Migration should be planned.

---

## 63. Pre-Migration Review

Inventory schema owner, object owners, existing grants, future grants, deployment roles, service accounts, IaC, automation, and security policies.

---

## 64. Test in Non-Production

Reproduce a representative design, enable managed access, test object creation, test grants, test pipelines, and test IaC.

Do not discover grant-management assumptions during the production change.

---

## 65. Post-Migration Validation

Verify objects remain accessible, pipelines work, future grants are correct, grant administrators work, unauthorized users remain blocked, and IaC matches actual state.

---

# Part 22 — Production Design Example

## 66. Reporting Schema

Goal: analysts can read all reporting tables/views, including new ones.

Use ANALYTICS.REPORTING with managed access and a REPORTING_READ access role receiving appropriate existing and future SELECT privileges.

Then grant REPORTING_READ into the DATA_ANALYST functional role.

---

## 67. Restricted Schema

For a restricted clinical schema, use a dedicated CLINICAL_READ role and narrowly scoped policy.

Do not apply broad database-level future SELECT if it would cross the security boundary.

---

# Part 23 — Hands-On Lab

## 68. Lab Objective

Demonstrate existing-object grants, future grants, creation of new objects, managed access, grant verification, revocation, and troubleshooting.

Use a non-production environment.

---

## 69. Create Database

```sql
CREATE OR REPLACE DATABASE future_grants_lab;
```

---

## 70. Create Managed Access Schema

```sql
CREATE OR REPLACE SCHEMA future_grants_lab.reporting
WITH MANAGED ACCESS;
```

---

## 71. Create Reader Role

```sql
CREATE ROLE future_grants_reader;
```

---

## 72. Grant Container Access

```sql
GRANT USAGE
ON DATABASE future_grants_lab
TO ROLE future_grants_reader;

GRANT USAGE
ON SCHEMA future_grants_lab.reporting
TO ROLE future_grants_reader;
```

Grant appropriate warehouse access separately for testing.

---

## 73. Create Existing Table

```sql
CREATE OR REPLACE TABLE future_grants_lab.reporting.table_a (
    id NUMBER,
    value VARCHAR
);
```

---

## 74. Grant Existing Table Access

```sql
GRANT SELECT
ON ALL TABLES IN SCHEMA future_grants_lab.reporting
TO ROLE future_grants_reader;
```

---

## 75. Configure Future Table Access

```sql
GRANT SELECT
ON FUTURE TABLES IN SCHEMA future_grants_lab.reporting
TO ROLE future_grants_reader;
```

---

## 76. Create New Table

```sql
CREATE OR REPLACE TABLE future_grants_lab.reporting.table_b (
    id NUMBER,
    value VARCHAR
);
```

TABLE_B was created after the future grant.

---

## 77. Validate Access

Using an appropriately configured lab user:

```sql
USE ROLE future_grants_reader;

SELECT *
FROM future_grants_lab.reporting.table_a;

SELECT *
FROM future_grants_lab.reporting.table_b;
```

Both should be readable when required warehouse access is present.

---

## 78. Test Future View Behavior

```sql
CREATE OR REPLACE VIEW future_grants_lab.reporting.view_a AS
SELECT *
FROM future_grants_lab.reporting.table_a;
```

If future SELECT was configured only for tables, do not assume the view automatically receives the same access.

---

## 79. Add Future View Grant

Using the appropriate grant-administration role:

```sql
GRANT SELECT
ON FUTURE VIEWS IN SCHEMA future_grants_lab.reporting
TO ROLE future_grants_reader;
```

Future grants primarily apply to objects created after the policy is established.

Handle the already-created view's current grant separately as required.

---

## 80. Grant Existing View

```sql
GRANT SELECT
ON ALL VIEWS IN SCHEMA future_grants_lab.reporting
TO ROLE future_grants_reader;
```

Now validate the existing view.

---

## 81. Create Another View

```sql
CREATE OR REPLACE VIEW future_grants_lab.reporting.view_b AS
SELECT *
FROM future_grants_lab.reporting.table_b;
```

Validate that the configured future-view policy behaves as expected.

---

## 82. Revoke Future Table Grant

```sql
REVOKE SELECT
ON FUTURE TABLES IN SCHEMA future_grants_lab.reporting
FROM ROLE future_grants_reader;
```

---

## 83. Create Table After Revocation

```sql
CREATE OR REPLACE TABLE future_grants_lab.reporting.table_c (
    id NUMBER
);
```

The new table should not receive the revoked future SELECT through that policy.

---

## 84. Verify Existing Access

Confirm whether TABLE_A and TABLE_B still retain their existing grants.

Revoking future policy does not automatically revoke historical object grants.

---

## 85. Inspect Schema

```sql
SHOW SCHEMAS LIKE 'REPORTING'
IN DATABASE future_grants_lab;
```

Confirm the schema's managed-access configuration.

---

## 86. Cleanup

Ensure all resources belong only to the lab.

```sql
DROP DATABASE IF EXISTS future_grants_lab;

DROP ROLE IF EXISTS future_grants_reader;
```

Remove any lab users or role relationships created specifically for the exercise.

---

# Part 24 — Production Checklist

## 87. Future Grant Checklist

- Existing object grants reviewed
- Future object grants reviewed
- Correct object type
- Correct privilege
- Correct database/schema scope
- Least privilege applied
- Sensitive schemas separated
- Database-level grants justified
- Role hierarchy documented
- IaC contains future grants

---

## 88. Managed Access Checklist

- Managed access requirement documented
- Schema owner controlled
- Grant administrators identified
- Object creators identified
- Pipelines tested
- Ownership model documented
- Future grants validated
- IaC reflects schema state
- Security review complete

---

## 89. Deployment Checklist

When a deployment creates new objects:

- Object created in expected schema
- Correct owner
- Future grant applied
- Reader access works
- Writer access works where required
- Unauthorized access fails
- Warehouse access works
- No broad unintended grants

---

# Acceptance Criteria

The chapter is complete when you can:

- distinguish existing-object grants from future grants
- grant access to existing tables
- configure future table grants
- configure future view grants
- understand object-type-specific future grants
- understand schema-level future-grant scope
- understand database-level future-grant scope
- apply least privilege to future grants
- explain why future grants are security policy
- identify risks of broad future grants
- inspect future-grant configuration
- revoke future grants safely
- distinguish future-policy revocation from existing grants
- explain managed access schemas
- create a managed access schema
- understand centralized grant administration
- distinguish object ownership from grant administration
- combine managed access with future grants
- design schema security boundaries
- use access roles with future grants
- use controlled ownership roles
- manage configuration through IaC
- troubleshoot inaccessible new objects
- troubleshoot incorrect future-grant scope
- troubleshoot managed-access grant failures
- investigate unexpected automatic access
- plan migration to managed access
- validate managed-access migration
- execute future-grant and managed-access incident runbooks
- test positive and negative access behavior

---

## Key Takeaways

ON ALL and ON FUTURE solve different problems.

ON ALL addresses objects that already exist. ON FUTURE addresses objects created later.

For continuously created objects, a complete access design often requires both.

Future grants should be treated as security policy because they determine who automatically receives access to data that does not yet exist.

Managed access schemas centralize privilege administration.

A strong production pattern combines security-aligned schema boundaries, managed access, narrow future grants, access roles, and controlled ownership.

When a new object is inaccessible, check container privileges, future grants, object type, scope, and role inheritance.

When a new object is accessible to too many users, investigate future grants immediately.

Most importantly: future grants automate access, and automated access must be designed as carefully as manual access.

The next chapter is **Chapter 30 — Network Policies & Connectivity Security**.
