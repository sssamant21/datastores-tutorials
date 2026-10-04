# 27 — RBAC & Role Hierarchy

## Overview

Authentication answers: **Who are you?**

Authorization answers: **What are you allowed to do?**

Snowflake primarily uses Role-Based Access Control (RBAC) to manage authorization.

```text
User
 |
 v
Role
 |
 v
Privileges
 |
 v
Snowflake Objects
```

Instead of granting privileges directly to every user, a scalable design assigns privileges to roles and roles to users.

This provides centralized access management, least privilege, simpler onboarding/offboarding, better auditing, separation of duties, reusable access patterns, and manageable production administration.

A strong production design asks what job function requires access, which role should represent it, where that role belongs in the hierarchy, and who should own and administer it.

---

# Part 1 — Snowflake Access Control

## 1. Core Access-Control Models

Snowflake access control includes concepts from Role-Based Access Control, Discretionary Access Control, user-based access concepts, and policy-driven controls.

For day-to-day administration, RBAC is the central operational model.

---

## 2. Basic RBAC Model

```text
USER
 |
 v
ROLE
 |
 v
PRIVILEGE
 |
 v
OBJECT
```

Example:

```text
ANALYST_USER
     |
     v
ANALYST_ROLE
     |
     +---- USAGE → DATABASE
     +---- USAGE → SCHEMA
     +---- SELECT → TABLE
     +---- USAGE → WAREHOUSE
```

---

## 3. Why Roles Matter

Without roles, privileges must be repeatedly managed for individual users.

With roles, required privileges can be packaged once and assigned to many users.

This makes the access model reusable and auditable.

---

# Part 2 — Privileges

## 4. What Is a Privilege?

A privilege permits an operation against a securable object.

Examples include USAGE, SELECT, INSERT, UPDATE, DELETE, CREATE TABLE, CREATE SCHEMA, OPERATE, MONITOR, and OWNERSHIP.

Available privileges depend on the object type.

---

## 5. Privilege Example

```sql
GRANT SELECT
ON TABLE analytics.reporting.customer_summary
TO ROLE reporting_reader;
```

The role can SELECT from that table if it also has the required access through the containing object hierarchy.

---

## 6. Database and Schema USAGE

A role generally also requires access through its database and schema.

```sql
GRANT USAGE
ON DATABASE analytics
TO ROLE reporting_reader;

GRANT USAGE
ON SCHEMA analytics.reporting
TO ROLE reporting_reader;

GRANT SELECT
ON TABLE analytics.reporting.customer_summary
TO ROLE reporting_reader;
```

Conceptually:

```text
DATABASE
   |
   +---- USAGE
          |
          v
       SCHEMA
          |
          +---- USAGE
                 |
                 v
               TABLE
                 |
                 +---- SELECT
```

---

## 7. Warehouse Privileges

A role may be able to SELECT from a table but still fail to execute a query if it cannot use a warehouse.

```sql
GRANT USAGE
ON WAREHOUSE reporting_wh
TO ROLE reporting_reader;
```

Authorization troubleshooting must consider both data and compute privileges.

---

# Part 3 — Roles

## 8. Create a Role

```sql
CREATE ROLE reporting_reader;
```

Then grant privileges:

```sql
GRANT USAGE ON DATABASE analytics TO ROLE reporting_reader;
GRANT USAGE ON SCHEMA analytics.reporting TO ROLE reporting_reader;
GRANT SELECT ON TABLE analytics.reporting.customer_summary TO ROLE reporting_reader;
GRANT USAGE ON WAREHOUSE reporting_wh TO ROLE reporting_reader;
```

---

## 9. Grant Role to User

```sql
GRANT ROLE reporting_reader
TO USER analyst_user;
```

The user can then activate the role according to Snowflake role/session behavior.

---

## 10. Inspect Roles

```sql
SHOW ROLES;
```

Use role metadata and grant information together when investigating access.

---

# Part 4 — Role Hierarchy

## 11. Role Inheritance

Roles can be granted to other roles.

```sql
GRANT ROLE reporting_reader
TO ROLE analytics_engineer;
```

The parent role inherits privileges from roles granted to it.

---

## 12. Build Hierarchies by Job Function

Example:

```text
                    DATA_PLATFORM_ADMIN
                     /              \
                    /                \
          DATA_ENGINEER          ANALYTICS_ADMIN
               |                       |
               v                       v
         INGESTION_ROLE          ANALYST_ROLE
                                       |
                                       v
                                REPORTING_READER
```

Higher-level roles inherit lower-level capabilities where intentionally designed.

---

## 13. Avoid Flat Role Design

Avoid hundreds of unrelated direct grants with no clear hierarchy.

Prefer structured inheritance.

---

## 14. Avoid Uncontrolled Deep Hierarchies

A hierarchy can become too complex.

A good hierarchy should be intentional, understandable, documented, testable, and auditable.

---

# Part 5 — System-Defined Roles

## 15. Snowflake System Roles

Common system roles include:

- ORGADMIN
- ACCOUNTADMIN
- SECURITYADMIN
- USERADMIN
- SYSADMIN
- PUBLIC

Some Snowflake capabilities may introduce additional system or application-specific roles.

---

## 16. ACCOUNTADMIN

ACCOUNTADMIN is a highly privileged account-level role.

It should be tightly controlled and should not be used for normal daily queries or routine application workloads.

---

## 17. SECURITYADMIN

SECURITYADMIN is intended for security and access-control administration according to Snowflake's system-role hierarchy.

Use it through controlled administrative processes.

---

## 18. USERADMIN

USERADMIN is associated with user and role administration capabilities.

Organizations should define governance around who may use it.

---

## 19. SYSADMIN

SYSADMIN is commonly used as the parent for roles that own or manage business/application objects.

Custom object-management roles should connect into the system hierarchy intentionally.

---

## 20. PUBLIC

Every user receives the PUBLIC pseudo-role.

Privileges granted to PUBLIC are effectively available to all users in the account.

Be extremely careful with privileges granted to PUBLIC.

---

# Part 6 — Custom Roles

## 21. Why Custom Roles?

Production workloads should generally use purpose-built custom roles rather than giving users broad system roles.

Examples:

```text
FINANCE_READER
FINANCE_WRITER
CLAIMS_ETL
REPORTING_READER
DATA_ENGINEER
APP_SERVICE_ROLE
SNOWFLAKE_MONITOR
```

---

## 22. Functional Roles

Functional roles represent job functions such as DATA_ANALYST, DATA_ENGINEER, DBRE, PLATFORM_ENGINEER, and SECURITY_AUDITOR.

They can inherit lower-level access roles.

---

## 23. Access Roles

An access role can represent privileges to a specific resource set.

Examples:

```text
CUSTOMER_READ
CUSTOMER_WRITE
CLAIMS_READ
CLAIMS_WRITE
```

This separates what resources can be accessed from what job the person performs.

---

## 24. Example Layered Model

```text
Object privileges
      |
      v
Access Roles
      |
      v
Functional Roles
      |
      v
Users
```

This is often easier to maintain than granting every object privilege directly to functional roles.

---

# Part 7 — Least Privilege

## 25. Least-Privilege Principle

Grant only the privileges required to perform the workload.

Do not grant OWNERSHIP when SELECT is all that is required, and do not grant broad administrative roles for access to one schema.

---

## 26. Reader Role

A reader role normally needs warehouse USAGE, database USAGE, schema USAGE, and SELECT on required objects.

It normally does not require INSERT, UPDATE, DELETE, CREATE, or OWNERSHIP unless explicitly required.

---

## 27. Writer Role

A writer role may require INSERT, UPDATE, and DELETE depending on the workload.

Do not automatically grant every DML privilege.

---

## 28. Administrative Role

Administrative roles may require object-creation and management privileges.

Keep administrative capabilities separate from ordinary application execution whenever practical.

---

# Part 8 — Ownership

## 29. OWNERSHIP Is Powerful

OWNERSHIP is a powerful privilege associated with control of an object.

Treat ownership changes carefully.

Do not use ownership simply because another privilege was difficult to troubleshoot.

---

## 30. Object Ownership Strategy

Production objects should generally be owned by controlled roles rather than personal user-specific roles.

This reduces lifecycle and offboarding problems.

---

## 31. Ownership Transfer

Before transferring ownership, understand the current owner, target owner, downstream grants, future grants, managed-access behavior, and operational impact.

Ownership transfer is an administrative change.

---

# Part 9 — Account Roles and Database Roles

## 32. Account Roles

Traditional Snowflake roles are account-level roles.

They can participate in account-level role hierarchies and be granted to users.

---

## 33. Database Roles

Snowflake also supports database roles.

A database role scopes privileges and role relationships to a database-oriented security model.

---

## 34. Why Database Roles?

Database roles can make packaged or database-specific access easier to manage.

Example:

```text
SALES_DB
   |
   +---- SALES_READER
   +---- SALES_WRITER
```

---

## 35. Database Role to Account Role

A common design is:

```text
Database Role
      |
      v
Account Role
      |
      v
User
```

This allows database-specific privileges to be consumed through broader functional account roles.

---

## 36. Account Role vs Database Role

Database roles package database-scoped access.

Account roles participate in broader account-level functional hierarchies.

Choose intentionally rather than creating both without a model.

---

# Part 10 — Service Roles

## 37. Service-Specific Roles

Each major service should generally have its own role.

Examples include AIRFLOW_ROLE, DBT_ROLE, FHIR_INGEST_ROLE, REPORTING_APP_ROLE, and TERRAFORM_ROLE.

Do not give all services one shared broad role.

---

## 38. Service User Mapping

```text
AIRFLOW_SVC
    |
    v
AIRFLOW_ROLE
    |
    v
Required privileges only
```

This improves auditability and incident containment.

---

## 39. Separate Read and Write Workloads

Where appropriate, APP_READ_ROLE and APP_WRITE_ROLE can provide clearer separation than one broad application role.

---

# Part 11 — Default and Active Roles

## 40. Default Role

```sql
ALTER USER analyst_user
SET DEFAULT_ROLE = data_analyst;
```

The default role should normally reflect the user's normal working context.

---

## 41. Current Role

```sql
SELECT CURRENT_ROLE();
```

When troubleshooting permissions, always verify the active role.

---

## 42. Switch Role

```sql
USE ROLE data_analyst;
```

A user must have access to the role being activated.

---

## 43. Why Active Role Matters

A user may have been granted a role but still execute a query under a different role.

Always check session context.

---

## 44. Secondary Roles

Snowflake supports secondary-role behavior, which can affect effective privileges available during a session.

Understand organizational secondary-role configuration when diagnosing unexpected access.

---

# Part 12 — Grant Management

## 45. Show Grants to Role

```sql
SHOW GRANTS TO ROLE reporting_reader;
```

This is one of the most useful RBAC troubleshooting commands.

---

## 46. Show Grants of Role

Use Snowflake grant metadata to determine which users or roles receive a role.

Distinguish privileges granted TO a role from a role granted TO a user or another role.

---

## 47. Show Grants on Object

Use grant metadata to inspect who has privileges on an object.

This is useful when investigating unexpected access.

---

## 48. Revoke Privilege

```sql
REVOKE SELECT
ON TABLE analytics.reporting.customer_summary
FROM ROLE reporting_reader;
```

Understand downstream impact before revoking production privileges.

---

## 49. Revoke Role

```sql
REVOKE ROLE reporting_reader
FROM USER analyst_user;
```

Determine whether the user has another path to the same privileges through role inheritance.

---

# Part 13 — Future Grants

## 50. Current vs Future Objects

A grant on existing tables does not necessarily solve access for tables created later.

Production access design must consider future objects.

Chapter 29 covers Future Grants and Managed Access Schemas in depth.

---

## 51. Example Problem

A role may have SELECT on TABLE_A and TABLE_B, but a newly created TABLE_C may not automatically receive the same access unless future grants are configured appropriately.

---

# Part 14 — Separation of Duties

## 52. Why Separation Matters

Avoid giving one operational identity unrestricted ability to create users, grant security privileges, own production data, modify pipelines, and read all sensitive data unless explicitly required and governed.

---

## 53. Example Separation

USERADMIN can handle identity administration, SECURITYADMIN security administration, SYSADMIN/custom owner roles object administration, and functional roles workload access.

Exact implementation can differ, but responsibilities should be intentional.

---

# Part 15 — Auditing

## 54. Why Audit RBAC?

Permissions accumulate over time due to temporary incident access, project changes, team transfers, legacy services, old environments, and manual grants.

Without review, least privilege degrades.

---

## 55. Access Review Questions

Regularly ask:

- Does this user still exist?
- Does this service still exist?
- Does this role still have an owner?
- Does this role need these privileges?
- Are system roles being used unnecessarily?
- Are privileges granted directly to users?
- Are PUBLIC grants appropriate?
- Are stale roles present?

---

## 56. Direct Grants to Users

Prefer role-based grants rather than direct object privileges to individual users.

Direct user grants can make the authorization model harder to understand and audit.

---

## 57. Role Naming Standard

Use names that reveal purpose, such as CLAIMS_READER, CLAIMS_WRITER, DATA_ENGINEER, SNOWFLAKE_MONITOR, and AIRFLOW_SVC_ROLE.

Avoid generic names such as ROLE1, ROLE_NEW, TEMP_ACCESS, and TEST_ROLE_2.

---

# Part 16 — Troubleshooting

## 58. Insufficient Privileges

When Snowflake reports insufficient privileges, do not immediately grant a broader role.

Investigate current user, current role, secondary roles, required object, required privilege, database USAGE, schema USAGE, object privilege, warehouse privilege, and role inheritance.

---

## 59. Permission Troubleshooting Commands

```sql
SELECT
    CURRENT_USER(),
    CURRENT_ROLE(),
    CURRENT_WAREHOUSE(),
    CURRENT_DATABASE(),
    CURRENT_SCHEMA();

SHOW GRANTS TO ROLE <role_name>;
```

Then inspect relevant role and object grants.

---

## 60. Can See Database but Not Table

Check database USAGE, schema USAGE, and table SELECT.

Seeing part of the object hierarchy does not prove all required privileges exist.

---

## 61. Can SELECT but Query Will Not Run

Check warehouse access.

```sql
SHOW GRANTS TO ROLE reporting_reader;
```

Look for required warehouse privileges.

---

## 62. User Has Role but Still Gets Permission Error

```sql
SELECT CURRENT_ROLE();
```

The role may not be active, or the required privilege may not be inherited through the active role hierarchy.

---

## 63. Role Has Privilege but User Does Not

Trace the privilege through the complete role inheritance chain to the user.

Look for a missing role grant anywhere in the chain.

---

## 64. Unexpected Access

Investigate direct grants, inherited roles, secondary roles, PUBLIC, database roles, broad future grants, ownership, and administrative/system roles.

Unexpected access is as important to investigate as missing access.

---

## 65. Access Worked Yesterday

Check whether a grant was revoked, a role removed, ownership changed, future grants changed, managed-access behavior changed, the default role changed, a service deployment changed, or an object was recreated.

---

# Part 17 — RBAC Incident Runbook

## 66. Production Access Incident

When a production workload receives authorization failures:

1. Capture user/service identity.
2. Capture query ID.
3. Capture timestamp.
4. Capture exact error.
5. Capture current role.
6. Capture secondary-role context.
7. Identify affected object.
8. Identify required operation.
9. Check database USAGE.
10. Check schema USAGE.
11. Check object privilege.
12. Check warehouse privilege.
13. Trace role inheritance.
14. Check recent grant/revoke activity.
15. Check recent ownership changes.
16. Check object recreation/deployment.
17. Compare with last known-good configuration.
18. Apply the minimum required correction.
19. Test using the actual service identity.
20. Monitor recovery.
21. Document root cause.

---

## 67. Do Not Fix Permissions with ACCOUNTADMIN

Never solve a narrow permission error by granting ACCOUNTADMIN.

Find the missing privilege.

---

## 68. Do Not Randomly Add Grants

Do not repeatedly grant SELECT, ALL, OWNERSHIP, or administrative roles until a query works.

Use evidence to identify the exact missing privilege.

---

# Part 18 — RBAC Design Example

## 69. Example Production Architecture

A possible role model:

```text
                    SYSADMIN
                        |
        +---------------+----------------+
        |                                |
 DATA_PLATFORM_ADMIN              ANALYTICS_ADMIN
        |                                |
   DATA_ENGINEER                    DATA_ANALYST
        |                                |
   +----+----+                      +----+----+
   |         |                      |         |
RAW_WRITE  CURATED_WRITE       CURATED_READ REPORTING_READ
```

This is only an example. Role design should follow actual workload and organizational boundaries.

---

## 70. Data Engineering Role

Potential access includes RAW_WRITE, CURATED_WRITE, and pipeline warehouse usage.

Do not automatically give analytics or security administration privileges.

---

## 71. Analyst Role

Potential access includes CURATED_READ, REPORTING_READ, and analytics warehouse usage.

Do not automatically grant write privileges.

---

## 72. Application Role

An application service role should receive only required schema access, object access, and warehouse access.

Nothing more unless required.

---

# Part 19 — Infrastructure as Code

## 73. RBAC as Code

Production RBAC should ideally be managed through controlled deployment mechanisms.

Benefits include version history, code review, repeatability, environment consistency, change tracking, and rollback planning.

---

## 74. Avoid Configuration Drift

If Terraform or another IaC system manages RBAC, avoid undocumented manual grants in production.

Otherwise desired state can differ from actual state.

---

## 75. Emergency Manual Changes

If emergency access requires a manual grant, resolve the incident, document the change, reconcile it with IaC, and remove temporary access.

Do not leave emergency privileges indefinitely.

---

# Part 20 — Hands-On Lab

## 76. Lab Objective

Create LAB_READER, LAB_WRITER, and LAB_ENGINEER and demonstrate privilege inheritance.

Use a non-production environment.

---

## 77. Create Lab Database Objects

```sql
CREATE OR REPLACE DATABASE rbac_lab;

CREATE OR REPLACE SCHEMA rbac_lab.data;

CREATE OR REPLACE TABLE rbac_lab.data.customers (
    customer_id NUMBER,
    customer_name VARCHAR
);

INSERT INTO rbac_lab.data.customers
VALUES
    (1, 'Alice'),
    (2, 'Bob');
```

---

## 78. Create Roles

```sql
CREATE ROLE lab_reader;
CREATE ROLE lab_writer;
CREATE ROLE lab_engineer;
```

---

## 79. Configure Reader

```sql
GRANT USAGE ON DATABASE rbac_lab TO ROLE lab_reader;
GRANT USAGE ON SCHEMA rbac_lab.data TO ROLE lab_reader;
GRANT SELECT ON TABLE rbac_lab.data.customers TO ROLE lab_reader;
GRANT USAGE ON WAREHOUSE <lab_warehouse> TO ROLE lab_reader;
```

---

## 80. Configure Writer

```sql
GRANT USAGE ON DATABASE rbac_lab TO ROLE lab_writer;
GRANT USAGE ON SCHEMA rbac_lab.data TO ROLE lab_writer;
GRANT INSERT, UPDATE, DELETE ON TABLE rbac_lab.data.customers TO ROLE lab_writer;
```

Grant required warehouse privileges as appropriate.

---

## 81. Build Hierarchy

```sql
GRANT ROLE lab_reader
TO ROLE lab_engineer;

GRANT ROLE lab_writer
TO ROLE lab_engineer;
```

LAB_ENGINEER now inherits both reader and writer roles.

---

## 82. Inspect Reader

```sql
SHOW GRANTS TO ROLE lab_reader;
```

---

## 83. Inspect Writer

```sql
SHOW GRANTS TO ROLE lab_writer;
```

---

## 84. Inspect Engineer

```sql
SHOW GRANTS TO ROLE lab_engineer;
```

Also inspect role inheritance to verify LAB_READER and LAB_WRITER are granted to LAB_ENGINEER.

---

## 85. Test Reader

```sql
USE ROLE lab_reader;

SELECT *
FROM rbac_lab.data.customers;
```

Then test:

```sql
DELETE FROM rbac_lab.data.customers
WHERE customer_id = 1;
```

It should fail because the reader role does not have DELETE.

This is a successful least-privilege test.

---

## 86. Test Writer

```sql
USE ROLE lab_writer;

INSERT INTO rbac_lab.data.customers
VALUES (3, 'Carol');
```

Validate only the privileges intentionally granted.

---

## 87. Test Inheritance

Using LAB_ENGINEER:

```sql
USE ROLE lab_engineer;

SELECT *
FROM rbac_lab.data.customers;
```

Then perform an allowed write operation.

The engineer role should inherit privileges of both child roles.

---

## 88. Troubleshooting Exercise

Revoke schema USAGE:

```sql
REVOKE USAGE
ON SCHEMA rbac_lab.data
FROM ROLE lab_reader;
```

Test the reader query again and investigate why SELECT no longer works even though table SELECT remains.

Restore:

```sql
GRANT USAGE
ON SCHEMA rbac_lab.data
TO ROLE lab_reader;
```

This demonstrates the importance of the complete object-access path.

---

## 89. Cleanup

Before cleanup, ensure objects and roles are used only for the lab.

```sql
DROP DATABASE IF EXISTS rbac_lab;

DROP ROLE IF EXISTS lab_engineer;
DROP ROLE IF EXISTS lab_writer;
DROP ROLE IF EXISTS lab_reader;
```

If roles were granted to lab users, remove those relationships as required.

---

# Part 21 — Production Checklist

## 90. RBAC Design Checklist

- Custom roles represent clear functions
- Least privilege applied
- Role hierarchy documented
- Access roles separated where useful
- Functional roles defined
- Service identities have dedicated roles
- Production ownership uses controlled roles
- PUBLIC grants reviewed
- System roles tightly controlled
- Direct user grants minimized
- Database roles used intentionally
- Future grants planned
- Separation of duties defined

---

## 91. Operational Checklist

- Role owner identified
- Access request process defined
- Grant process controlled
- Revoke process controlled
- Emergency access documented
- Temporary access expires
- RBAC changes audited
- IaC reconciled
- Access reviews scheduled
- Stale roles removed

---

# Acceptance Criteria

The chapter is complete when you can:

- explain RBAC
- distinguish authentication from authorization
- explain Snowflake privileges
- understand database/schema USAGE
- understand warehouse access
- create custom roles
- grant roles to users
- build role hierarchies
- explain privilege inheritance
- identify major system-defined roles
- explain risks of ACCOUNTADMIN
- explain PUBLIC behavior
- design functional roles
- design access roles
- apply least privilege
- understand OWNERSHIP
- design production object ownership
- distinguish account roles from database roles
- design service-specific roles
- understand default/current roles
- understand secondary-role implications
- inspect grants
- revoke privileges safely
- understand future-grant requirements
- apply separation of duties
- audit stale access
- troubleshoot insufficient privileges
- investigate unexpected access
- diagnose role inheritance problems
- operate the RBAC incident runbook
- manage RBAC through IaC
- validate access with positive and negative tests

---

## Key Takeaways

Snowflake RBAC should follow a structured model of privileges, access roles, functional roles, and users/services where that design fits the organization.

Do not design authorization around individual users.

Design around job function, resource access, least privilege, role inheritance, and separation of duties.

When troubleshooting, trace the complete chain from user to current role, role hierarchy, database USAGE, schema USAGE, object privilege, and warehouse access.

Most importantly: never solve a narrow permission problem with a broad administrative role.

Find the exact missing privilege and grant it through the correct role.

A mature Snowflake RBAC model should be simple enough to understand, structured enough to scale, restricted enough to protect production, and auditable enough to explain every access path.

The next chapter is **Chapter 28 — Users, Roles & Privilege Management**.
