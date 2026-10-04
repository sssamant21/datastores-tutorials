# 28 — Users, Roles & Privilege Management

## Overview

Snowflake access management is not complete after designing an RBAC hierarchy.

Production environments continuously change:

```text
Employees join
Employees leave
Teams change
Applications are deployed
Services are retired
Databases are created
Schemas are added
Privileges change
Temporary access is requested
Incidents require emergency access
```

Users, roles, and privileges therefore require continuous lifecycle management.

The operational model is:

```text
Identity
   |
   v
User
   |
   v
Role
   |
   v
Privilege
   |
   v
Snowflake Object
```

Production administration should make every access path answerable: who has access, why they have it, through which role, who approved it, what objects they can access, and when access should be removed.

This chapter focuses on managing that lifecycle safely.

---

# Part 1 — User Administration

## 1. What Is a Snowflake User?

A Snowflake user represents an identity that can interact with the account according to its authentication configuration, assigned roles, and other properties.

Users can represent human users, service identities, automation, applications, and integration workloads.

Human and machine identities should be managed differently.

---

## 2. Create a Human User

```sql
CREATE USER jane_smith
    LOGIN_NAME = 'jane.smith'
    DISPLAY_NAME = 'Jane Smith'
    DEFAULT_ROLE = data_analyst
    DEFAULT_WAREHOUSE = analytics_wh;
```

Authentication configuration depends on organizational standards.

If enterprise SSO is used, do not create unnecessary standalone credentials.

---

## 3. Create a Service User

```sql
CREATE USER airflow_svc
    DEFAULT_ROLE = airflow_role
    DEFAULT_WAREHOUSE = etl_wh;
```

Then configure the approved non-interactive authentication mechanism.

Avoid sharing a human user's identity with automation.

---

## 4. Human vs Service User

Human users commonly use SSO/MFA and functional roles. Service users should use approved non-interactive authentication and dedicated service roles.

Keep these identity classes separate.

---

# Part 2 — User Properties

## 5. Default Role

```sql
ALTER USER jane_smith
SET DEFAULT_ROLE = data_analyst;
```

The default role should represent the user's normal working context.

Do not automatically make an administrative role the default.

---

## 6. Default Warehouse

```sql
ALTER USER jane_smith
SET DEFAULT_WAREHOUSE = analytics_wh;
```

This improves usability but does not itself grant warehouse access.

The active role still requires the appropriate warehouse privilege.

---

## 7. Default Namespace

```sql
ALTER USER jane_smith
SET DEFAULT_NAMESPACE = analytics.reporting;
```

This affects session convenience, not the underlying privilege model.

---

## 8. Inspect User

```sql
DESC USER jane_smith;
SHOW USERS;
```

Use these when reviewing user configuration and account user inventory.

---

## 9. Current Session Identity

```sql
SELECT
    CURRENT_USER(),
    CURRENT_ROLE(),
    CURRENT_WAREHOUSE(),
    CURRENT_DATABASE(),
    CURRENT_SCHEMA();
```

Never troubleshoot access without first confirming session context.

---

# Part 3 — Role Administration

## 10. Create a Role

```sql
CREATE ROLE claims_reader;
```

A role should have a clear purpose, owner, naming standard, defined privilege scope, documented consumers, and lifecycle.

Avoid creating roles without ownership or purpose.

---

## 11. Grant Role to User

```sql
GRANT ROLE claims_reader
TO USER jane_smith;
```

---

## 12. Grant Role to Role

```sql
GRANT ROLE claims_reader
TO ROLE data_analyst;
```

DATA_ANALYST inherits the privileges available through CLAIMS_READER.

---

## 13. Revoke Role from User

```sql
REVOKE ROLE claims_reader
FROM USER jane_smith;
```

Before revoking production access, determine whether the user or service depends on it.

---

## 14. Revoke Role from Role

```sql
REVOKE ROLE claims_reader
FROM ROLE data_analyst;
```

This can affect every user inheriting DATA_ANALYST.

Understand the blast radius first.

---

# Part 4 — Privilege Administration

## 15. Grant Database Access

```sql
GRANT USAGE
ON DATABASE claims
TO ROLE claims_reader;
```

---

## 16. Grant Schema Access

```sql
GRANT USAGE
ON SCHEMA claims.reporting
TO ROLE claims_reader;
```

---

## 17. Grant Table Read Access

```sql
GRANT SELECT
ON TABLE claims.reporting.claim_summary
TO ROLE claims_reader;
```

The complete access path generally requires database USAGE, schema USAGE, and object SELECT.

---

## 18. Grant Warehouse Access

```sql
GRANT USAGE
ON WAREHOUSE analytics_wh
TO ROLE claims_reader;
```

Data access and compute access are separate concerns.

---

## 19. Grant Write Privileges

```sql
GRANT INSERT, UPDATE
ON TABLE claims.processing.claim_work
TO ROLE claims_writer;
```

Grant only the DML operations actually required.

---

## 20. Delete Privilege

```sql
GRANT DELETE
ON TABLE claims.processing.claim_work
TO ROLE claims_writer;
```

Do not grant DELETE merely because the role already has INSERT and UPDATE.

---

# Part 5 — Bulk Grants

## 21. Existing Tables

```sql
GRANT SELECT
ON ALL TABLES IN SCHEMA claims.reporting
TO ROLE claims_reader;
```

This applies to existing applicable tables.

Future objects require separate consideration.

---

## 22. Existing Views

```sql
GRANT SELECT
ON ALL VIEWS IN SCHEMA claims.reporting
TO ROLE claims_reader;
```

Understand exactly which object types the workload needs.

---

## 23. Bulk Grants Require Care

Before broadly granting access to all objects in a schema, determine whether the role truly requires every object and whether sensitive or regulated data is included.

Convenience is not a security justification.

---

# Part 6 — Future Objects

## 24. The Future Object Problem

A role can have access to existing TABLE_A and TABLE_B while a newly created TABLE_C remains inaccessible unless future grants are configured.

---

## 25. Future Grant Example

```sql
GRANT SELECT
ON FUTURE TABLES IN SCHEMA claims.reporting
TO ROLE claims_reader;
```

This allows new tables in the applicable scope to receive the configured privilege.

Chapter 29 covers future grants and managed access schemas in depth.

---

## 26. Existing + Future Pattern

Production read access often needs consideration of both existing objects and future objects.

Do not configure only one and assume the other is covered.

---

# Part 7 — Ownership Management

## 27. Object Ownership

Ownership is powerful and should belong to controlled roles.

Prefer organizational roles such as CLAIMS_OBJECT_OWNER rather than personal engineer roles for production object ownership.

---

## 28. Why Personal Ownership Is Risky

If production objects depend operationally on personal roles, employee departure can create operational debt.

Use organizational roles for production ownership.

---

## 29. Transfer Ownership Carefully

Before transferring ownership:

1. Identify current owner.
2. Identify target owner.
3. Review downstream privileges.
4. Review future grants.
5. Review managed access behavior.
6. Review IaC state.
7. Plan rollback.
8. Execute through change control.

Do not casually transfer ownership during troubleshooting.

---

# Part 8 — Service Account Management

## 30. Dedicated Service Users

Prefer dedicated users such as AIRFLOW_SVC, DBT_SVC, TERRAFORM_SVC, REPORTING_APP_SVC, and MONITORING_SVC rather than one shared Snowflake service account for unrelated workloads.

---

## 31. Dedicated Service Roles

Map each service identity to an appropriate dedicated role.

This makes access easier to audit and revoke.

---

## 32. Service Account Inventory

| Service | User | Role | Auth Method | Owner | Environment |
|---|---|---|---|---|---|
| Airflow | AIRFLOW_SVC | AIRFLOW_ROLE | Key pair | Data Platform | Prod |
| dbt | DBT_SVC | DBT_ROLE | Approved method | Analytics | Prod |
| Terraform | TF_SVC | TERRAFORM_ROLE | Approved method | Platform | Prod |

Unknown service accounts should be investigated.

---

## 33. Service Account Lifecycle

Every service identity needs provisioning, authentication, role assignment, monitoring, credential rotation, ownership, and decommissioning.

Do not create permanent service identities without lifecycle ownership.

---

# Part 9 — Onboarding

## 34. User Onboarding Workflow

A controlled onboarding flow includes access request, approval, identity provisioning, role assignment, authentication configuration, validation, and an audit record.

---

## 35. Do Not Clone Another User Blindly

Do not simply copy all access from another user.

The existing user may have legacy grants, temporary access, administrative roles, or project-specific privileges.

Grant according to actual job requirements.

---

## 36. Validate New Access

```sql
SELECT
    CURRENT_USER(),
    CURRENT_ROLE();
```

Then validate both required positive access and expected negative access.

---

# Part 10 — Offboarding

## 37. Offboarding Is Security-Critical

When a human or service no longer requires access, revoke it promptly according to organizational policy.

Do not leave dormant production identities indefinitely.

---

## 38. Offboarding Workflow

Disable access, review active sessions/credentials, revoke roles, review owned objects, transfer required ownership, remove credentials, and audit completion.

---

## 39. Disable Before Destructive Cleanup

For many offboarding situations, disabling access first gives administrators time to investigate dependencies safely.

Do not immediately drop an identity without understanding ownership, automation, integrations, dependencies, and audit requirements.

---

## 40. Service Decommissioning

Before removing a service user, confirm the application is retired, traffic has stopped, scheduled jobs are disabled, no other system uses the credential, object ownership is handled, and secrets are removed.

---

# Part 11 — Temporary Access

## 41. Temporary Privilege Requests

Temporary elevated access should have a reason, approver, scope, start time, expiration, owner, and audit record.

---

## 42. Avoid Permanent Temporary Access

Temporary access that is never removed becomes permanent privilege accumulation.

---

## 43. Post-Incident Cleanup

After an incident:

1. Review emergency grants.
2. Revoke unnecessary roles.
3. Remove temporary privileges.
4. Reconcile IaC.
5. Document changes.
6. Validate normal access.

Include this in incident closure.

---

# Part 12 — Direct Grants

## 44. Prefer Roles

Prefer privilege → role → user rather than unmanaged direct grants to individual users where supported and appropriate.

---

## 45. Why Direct Grants Are Harder

Direct grants can bypass role design, complicate audits, create hidden access paths, complicate offboarding, and increase configuration drift.

Use controlled exceptions only when required.

---

# Part 13 — PUBLIC Review

## 46. PUBLIC Is Broad

Because every user receives PUBLIC, privileges granted to PUBLIC deserve special attention.

Review PUBLIC regularly.

---

## 47. Audit PUBLIC Grants

Ask what privileges PUBLIC has, why they were granted, whether they are still required, and whether they expose sensitive objects.

Remove unnecessary broad access through change-controlled procedures.

---

# Part 14 — Access Reviews

## 48. Periodic Access Review

Production environments should periodically review users, roles, role hierarchy, direct grants, system-role assignments, service accounts, PUBLIC grants, ownership, and temporary access.

---

## 49. User Review

For every user, verify that the identity is still active, correctly classified, has appropriate roles/defaults, does not hold unjustified administrative access, and has expected activity.

---

## 50. Service Account Review

For every service identity, verify the service still runs, ownership remains valid, authentication is current, roles remain necessary, credentials are rotated, and interactive usage is expected or prohibited as designed.

---

## 51. Role Review

For every custom role, verify purpose, owner, users, parent roles, privileges, and continuing need.

Roles without known purpose should be investigated.

---

## 52. Privilege Review

Review higher-risk privileges such as OWNERSHIP, broad grants, administrative privileges, write privileges, DELETE, CREATE, broad warehouse access, and sensitive-data access.

---

# Part 15 — Grant Discovery

## 53. Show Grants to Role

```sql
SHOW GRANTS TO ROLE claims_reader;
```

Use this to inspect privileges available directly to the role.

---

## 54. Show Roles

```sql
SHOW ROLES;
```

Use role metadata to understand the account's role inventory.

---

## 55. Show Users

```sql
SHOW USERS;
```

Review active users and relevant properties.

---

## 56. Role Assignment Investigation

When investigating access, trace the user through direct roles, parent roles, inherited roles, and privileges.

Do not stop at the first role found.

---

# Part 16 — Effective Access

## 57. Effective Privileges

A user's effective access may come from direct roles, inherited roles, secondary roles, database roles, PUBLIC, ownership, and administrative roles.

One user can therefore have multiple access paths.

---

## 58. Unexpected Access Example

If a user has DATA_ANALYST and PROJECT_ADMIN, a DELETE privilege might come from PROJECT_ADMIN even if DATA_ANALYST lacks it.

Investigating only one role can produce the wrong conclusion.

---

## 59. Trace the Complete Graph

Trace every relevant role relationship and privilege path when investigating authorization.

---

# Part 17 — Privilege Troubleshooting

## 60. Insufficient Privileges

```sql
SELECT
    CURRENT_USER(),
    CURRENT_ROLE(),
    CURRENT_WAREHOUSE(),
    CURRENT_DATABASE(),
    CURRENT_SCHEMA();
```

Then identify the exact failed operation.

---

## 61. SELECT Failure

Check database USAGE, schema USAGE, object SELECT, active role, and role inheritance.

---

## 62. Query Cannot Start

If data privileges look correct, check warehouse access and warehouse state.

Authorization to data does not automatically authorize compute usage.

---

## 63. CREATE TABLE Failure

Check whether the active role has the required privilege on the target schema.

Do not grant schema ownership merely to solve a CREATE problem unless ownership is actually required.

---

## 64. INSERT Failure

Check database USAGE, schema USAGE, INSERT privilege, active role, and role hierarchy.

Do not automatically grant UPDATE and DELETE.

---

## 65. DELETE Failure

If the application legitimately requires DELETE, grant DELETE through the correct role.

Do not use a broader role merely because it already has DELETE.

---

# Part 18 — Unexpected Privilege Troubleshooting

## 66. User Can Access Too Much

Check all roles assigned to the user, parent roles, secondary roles, PUBLIC, database roles, ownership, administrative roles, direct grants, and future grants.

Overprivilege is an incident worth investigating.

---

## 67. Privilege Returned After Removal

Possible causes include another role, parent-role inheritance, future grants, IaC redeployment, manual changes being overwritten, or PUBLIC access.

Find the authoritative source.

---

# Part 19 — Configuration Drift

## 68. What Is RBAC Drift?

If desired state in Git/Terraform differs from actual Snowflake state, RBAC drift exists.

---

## 69. Causes of Drift

Common causes include manual production grants, incident access, console changes, untracked ownership transfers, unmanaged users, and temporary roles.

---

## 70. Why Drift Is Dangerous

Drift can cause unexpected access, deployment failures, privilege removal, security gaps, and audit findings.

---

## 71. Reconcile Drift

After an emergency manual change, document it, update the authoritative configuration where required, review, deploy, and verify—or remove the temporary change when no longer needed.

---

# Part 20 — Change Management

## 72. Treat RBAC Changes as Production Changes

A privilege change can cause application outages, data exposure, failed pipelines, administrative lockout, or compliance issues.

RBAC changes deserve change control.

---

## 73. Pre-Change Checklist

Before changing production access, identify affected identities, roles, privileges, objects, dependent services, rollback plan, and validation procedure.

---

## 74. Post-Change Validation

After a grant, verify required access works and unauthorized access still fails.

After a revoke, verify target access is removed and unrelated workloads still function.

---

# Part 21 — Production Runbooks

## 75. New User Runbook

1. Validate approved request.
2. Identify identity type.
3. Create/provision identity.
4. Configure authentication.
5. Assign approved functional roles.
6. Configure appropriate defaults.
7. Validate login.
8. Validate required access.
9. Validate negative access.
10. Record completion.

---

## 76. New Service Account Runbook

1. Identify service owner.
2. Define service purpose.
3. Create dedicated service identity.
4. Create/select dedicated service role.
5. Grant minimum privileges.
6. Configure approved authentication.
7. Store credential securely.
8. Test application connection.
9. Configure monitoring.
10. Document rotation.
11. Document decommissioning.

---

## 77. Access Removal Runbook

1. Confirm request.
2. Identify user/service.
3. Identify roles.
4. Determine dependencies.
5. Revoke target access.
6. Validate expected denial.
7. Check for alternate access paths.
8. Reconcile IaC.
9. Record completion.

---

## 78. Permission Incident Runbook

When production reports an authorization failure:

1. Capture query ID.
2. Capture user/service.
3. Capture timestamp.
4. Capture exact error.
5. Capture current role.
6. Identify operation.
7. Identify target object.
8. Check database USAGE.
9. Check schema USAGE.
10. Check object privilege.
11. Check warehouse privilege.
12. Trace role inheritance.
13. Check secondary roles.
14. Check database roles.
15. Check recent grant/revoke activity.
16. Check object recreation.
17. Check ownership changes.
18. Check IaC deployment.
19. Apply minimum correction.
20. Test using actual identity.
21. Monitor workload.
22. Document root cause.

---

# Part 22 — Security Incident Considerations

## 79. Unauthorized Access

If an identity appears to have access it should not have, preserve evidence, identify the access path, contain if required, review activity, correct the privilege, and determine root cause.

Engage organizational security processes where appropriate.

---

## 80. Do Not Destroy Evidence

Avoid immediately deleting users or roles during a suspected security incident unless containment requires it.

Preserve login history, query history, grant history, role relationships, and object-access evidence according to organizational procedures.

---

# Part 23 — Hands-On Lab

## 81. Lab Objective

Practice user lifecycle, role lifecycle, privilege grants, revokes, role inheritance, effective-access investigation, and access removal.

Use a non-production environment.

---

## 82. Create Lab Objects

```sql
CREATE OR REPLACE DATABASE privilege_lab;

CREATE OR REPLACE SCHEMA privilege_lab.app;

CREATE OR REPLACE TABLE privilege_lab.app.orders (
    order_id NUMBER,
    amount NUMBER
);

INSERT INTO privilege_lab.app.orders
VALUES
    (1, 100),
    (2, 250);
```

---

## 83. Create Lab Roles

```sql
CREATE ROLE privilege_lab_reader;
CREATE ROLE privilege_lab_writer;
CREATE ROLE privilege_lab_engineer;
```

---

## 84. Reader Grants

```sql
GRANT USAGE ON DATABASE privilege_lab TO ROLE privilege_lab_reader;
GRANT USAGE ON SCHEMA privilege_lab.app TO ROLE privilege_lab_reader;
GRANT SELECT ON TABLE privilege_lab.app.orders TO ROLE privilege_lab_reader;
```

Grant an appropriate lab warehouse privilege as needed.

---

## 85. Writer Grants

```sql
GRANT USAGE ON DATABASE privilege_lab TO ROLE privilege_lab_writer;
GRANT USAGE ON SCHEMA privilege_lab.app TO ROLE privilege_lab_writer;
GRANT INSERT, UPDATE ON TABLE privilege_lab.app.orders TO ROLE privilege_lab_writer;
```

Do not grant DELETE yet.

---

## 86. Build Engineer Role

```sql
GRANT ROLE privilege_lab_reader
TO ROLE privilege_lab_engineer;

GRANT ROLE privilege_lab_writer
TO ROLE privilege_lab_engineer;
```

The engineer now inherits read and write access.

---

## 87. Create Lab User

```sql
CREATE USER privilege_lab_user
    DEFAULT_ROLE = privilege_lab_reader;
```

Configure authentication according to the lab environment's policy.

---

## 88. Assign Reader

```sql
GRANT ROLE privilege_lab_reader
TO USER privilege_lab_user;
```

---

## 89. Test Read

```sql
USE ROLE privilege_lab_reader;

SELECT *
FROM privilege_lab.app.orders;
```

The query should succeed when warehouse access is correctly configured.

---

## 90. Negative Write Test

```sql
UPDATE privilege_lab.app.orders
SET amount = 300
WHERE order_id = 1;
```

This should fail under the reader role.

That failure proves least privilege is working.

---

## 91. Grant Engineer Role

```sql
GRANT ROLE privilege_lab_engineer
TO USER privilege_lab_user;

USE ROLE privilege_lab_engineer;
```

---

## 92. Test Inherited Access

```sql
SELECT *
FROM privilege_lab.app.orders;

UPDATE privilege_lab.app.orders
SET amount = 300
WHERE order_id = 1;
```

Both should succeed if all required privileges and warehouse access are configured.

---

## 93. Negative DELETE Test

```sql
DELETE FROM privilege_lab.app.orders
WHERE order_id = 2;
```

This should still fail because DELETE was never granted.

Inheritance does not create privileges that do not exist.

---

## 94. Inspect Grants

```sql
SHOW GRANTS TO ROLE privilege_lab_reader;
SHOW GRANTS TO ROLE privilege_lab_writer;
SHOW GRANTS TO ROLE privilege_lab_engineer;
```

Trace where each privilege originates.

---

## 95. Revoke Writer Role

```sql
REVOKE ROLE privilege_lab_writer
FROM ROLE privilege_lab_engineer;
```

The engineer should lose privileges inherited only from the writer role.

---

## 96. Validate Revocation

```sql
UPDATE privilege_lab.app.orders
SET amount = 350
WHERE order_id = 1;
```

It should fail if no alternate access path provides UPDATE.

SELECT should continue to work through the reader role.

---

## 97. Cleanup

Before cleanup, ensure resources belong only to the lab.

```sql
DROP USER IF EXISTS privilege_lab_user;

DROP DATABASE IF EXISTS privilege_lab;

DROP ROLE IF EXISTS privilege_lab_engineer;
DROP ROLE IF EXISTS privilege_lab_writer;
DROP ROLE IF EXISTS privilege_lab_reader;
```

Clean up credentials or secrets created for the lab according to organizational procedures.

---

# Part 24 — Production Checklist

## 98. User Checklist

- Identity type documented
- Owner identified
- Authentication approved
- Default role appropriate
- Default warehouse appropriate
- Required roles only
- Administrative roles justified
- Direct grants reviewed
- Activity monitored
- Offboarding process defined

---

## 99. Role Checklist

- Purpose documented
- Owner identified
- Naming standard followed
- Parent role documented
- Child roles documented
- Privileges justified
- Ownership understood
- Consumers known
- Future grants reviewed
- IaC ownership known

---

## 100. Privilege Checklist

- Least privilege
- Database USAGE
- Schema USAGE
- Required object privilege
- Required warehouse privilege
- Existing-object grants reviewed
- Future-object access reviewed
- PUBLIC exposure reviewed
- Direct grants minimized
- High-risk privileges reviewed

---

## 101. Service Account Checklist

- Dedicated identity
- Dedicated role
- Service owner
- Secure authentication
- Secret/key owner
- Rotation process
- Monitoring
- Least privilege
- Environment identified
- Decommission procedure

---

# Acceptance Criteria

The chapter is complete when you can:

- create and inspect users
- distinguish human and service users
- configure user defaults
- create and manage roles
- grant roles to users
- grant roles to roles
- revoke roles safely
- grant database privileges
- grant schema privileges
- grant table privileges
- grant warehouse privileges
- manage read/write access separately
- understand bulk grants
- understand existing vs future objects
- manage ownership safely
- manage dedicated service accounts
- perform controlled onboarding
- perform controlled offboarding
- manage temporary access
- minimize direct user grants
- audit PUBLIC
- perform user/role/service reviews
- investigate effective access
- troubleshoot missing privileges
- investigate excessive privileges
- detect RBAC drift
- reconcile emergency changes
- apply change management
- execute user/service/access runbooks
- investigate security-sensitive access
- validate grants and revokes with positive and negative tests

---

## Key Takeaways

Snowflake privilege management is a lifecycle: request, approve, provision, grant, validate, monitor, review, and revoke.

The preferred access pattern is privilege → role → user/service rather than unmanaged direct grants.

For production service accounts, use one dedicated identity with a dedicated role and minimum required privileges where appropriate.

When troubleshooting, trace user, active role, role hierarchy, database/schema access, object privilege, and warehouse access.

When reviewing security, consider direct roles, inherited roles, secondary roles, database roles, PUBLIC, ownership, and administrative roles.

Most importantly: grant only what is required, through the correct role, for only as long as it is required.

A mature Snowflake privilege-management process makes it possible to explain who has access, why they have it, where that access comes from, and how it will eventually be removed.

The next chapter is **Chapter 29 — Future Grants & Managed Access Schemas**.
