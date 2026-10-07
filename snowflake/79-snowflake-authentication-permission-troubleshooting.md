# Chapter 79 --- Snowflake Authentication & Permission Troubleshooting

## 79.1 Overview

Snowflake access incidents commonly appear as:

``` text
Unable to log in
Authentication failed
Incorrect username/password
Key-pair authentication failed
OAuth token rejected
SSO login failed
Network policy blocked connection
User can log in but cannot query
Object does not exist or not authorized
Insufficient privileges
Warehouse cannot be used
Role cannot access database/schema/table
Service account suddenly stopped working
Application receives authorization errors
```

These failures must first be separated into:

``` text
CONNECT
   |
   v
AUTHENTICATE
   |
   v
AUTHORIZE
   |
   v
ACCESS OBJECT
   |
   v
EXECUTE OPERATION
```

**Primary rule: Determine whether the problem is authentication or
authorization before changing privileges.**

## 79.2 Authentication

Authentication answers: **Who are you?**

Examples include password, key pair, OAuth, SSO, federated identity, and
workload identity.

## 79.3 Authorization

Authorization answers: **What are you allowed to do?**

Snowflake authorization primarily involves roles, privileges, ownership,
role hierarchy, object grants, future grants, and managed access.

## 79.4 Critical Difference

If a user cannot authenticate, granting `SELECT` will not solve the
problem.

If authentication succeeds but the user cannot query a table, resetting
the password will not solve the problem.

## 79.5 Standard Flow

``` text
ACCESS FAILURE
      |
      v
CAN CONNECT?
      |
   +--+--+
   |     |
  No    Yes
   |     |
   v     v
AUTH /  CAN USE ROLE?
NETWORK      |
         +--+--+
         |     |
        No    Yes
         |     |
         v     v
      ROLE    CAN USE
      ISSUE   WAREHOUSE?
                 |
              +--+--+
              |     |
             No    Yes
              |     |
              v     v
             WH    CAN ACCESS
           GRANT   DATABASE?
                     |
                  +--+--+
                  |     |
                 No    Yes
                  |     |
                  v     v
                DB/    OBJECT
              SCHEMA   PRIVILEGE
```

## 79.6 Capture Context

Record:

``` text
Environment
Account
Region
Application
User
Authentication method
Role
Warehouse
Database
Schema
Object
Operation
Exact error
Incident start
Last successful access
Customer impact
```

## 79.7 Example

``` text
Environment: Production
Application: Patient360
User: SVC_PATIENT360
Authentication: Key pair
Role: PATIENT360_APP_ROLE
Warehouse: PATIENT360_APP_WH
Database: DAP
Schema: L2
Object: EMPI
Operation: SELECT
Last successful access: 13:45 UTC
Failure start: 14:00 UTC
```

## 79.8 Never Start by Granting ACCOUNTADMIN

Do not troubleshoot access by giving the user `ACCOUNTADMIN` or broad
privileges. This can hide the real problem and violate least privilege.

## 79.9 Verify Session Context

``` sql
SELECT
    CURRENT_USER(),
    CURRENT_ROLE(),
    CURRENT_WAREHOUSE(),
    CURRENT_DATABASE(),
    CURRENT_SCHEMA();
```

## 79.10 Verify Account

``` sql
SELECT
    CURRENT_ORGANIZATION_NAME(),
    CURRENT_ACCOUNT_NAME(),
    CURRENT_REGION();
```

Always verify the correct account and environment.

## 79.11 Show Users

``` sql
SHOW USERS;
```

## 79.12 Specific User

Confirm that the user exists and review login name, disabled state,
authentication configuration, default role, and default warehouse using
appropriate Snowflake inspection commands.

## 79.13 User Disabled

If the identity is disabled or restricted, determine why before
re-enabling it. Do not automatically enable a disabled production
identity.

## 79.14 Password Failure

Potential causes:

``` text
Incorrect password
Password expired
User disabled
Wrong account
Wrong username/login name
Network policy
Authentication policy
Client configuration
```

## 79.15 Do Not Log Passwords

Never ask users to paste passwords into Slack, incident tickets, email,
chat, logs, or shell history.

## 79.16 Login History

Snowflake login history is one of the most useful sources for
authentication investigations.

Use the appropriate `LOGIN_HISTORY` interface for the incident window.

## 79.17 Login History Example

``` sql
SELECT
    EVENT_TIMESTAMP,
    USER_NAME,
    CLIENT_IP,
    REPORTED_CLIENT_TYPE,
    IS_SUCCESS,
    ERROR_CODE,
    ERROR_MESSAGE
FROM SNOWFLAKE.ACCOUNT_USAGE.LOGIN_HISTORY
WHERE EVENT_TIMESTAMP >= DATEADD('hour', -4, CURRENT_TIMESTAMP())
ORDER BY EVENT_TIMESTAMP DESC;
```

Review current Snowflake documentation for exact fields available in the
environment.

## 79.18 Authentication Investigation

Determine whether login was attempted, whether Snowflake received it,
whether it succeeded, which client and source IP were used, the error
code/message, and whether failures began suddenly.

## 79.19 Source IP

If the same user succeeds from one network and fails from another,
investigate network policy, private connectivity, proxy, NAT, VPN,
firewall, and DNS.

## 79.20 Network Policy

Snowflake network policies can restrict access based on network
rules/configuration. A blocked connection can appear to be an
authentication problem even when credentials are correct.

## 79.21 Network Investigation

Compare:

``` text
Successful source IP
Failed source IP
Expected application egress IP
Current application egress IP
```

A NAT or infrastructure change can break previously valid access.

## 79.22 Key-Pair Authentication

Applications frequently use key-pair authentication.

``` text
Application
    |
Private Key
    |
    v
Snowflake User
    |
Public Key
```

## 79.23 Key-Pair Failure

Common causes:

``` text
Wrong private key
Wrong public key assigned
Key rotation incomplete
Old key removed too early
Private key format issue
Passphrase issue
Wrong username
Wrong account
Client library configuration
Clock/token issue where applicable
```

## 79.24 Safe Key Rotation Principle

``` text
Existing key
     +
New key
     |
     v
Validate new key
     |
     v
Move applications
     |
     v
Remove old key
```

Do not remove the working credential before validating the replacement.

## 79.25 Key Verification

Confirm expected user/public key, application secret version, deployment
version, rotation timestamp, last successful login, and first failed
login.

Correlate failures with credential rotation.

## 79.26 Secret Manager

When credentials are stored in a secret manager, investigate secret
path/version, rotation, application access, deployment synchronization,
environment variables, and mount/injection behavior.

Do not expose secret values.

## 79.27 OAuth Failure

Potential causes include expired/invalid tokens, wrong audience or
issuer, incorrect integration, unauthorized role, clock skew, token
scope, or client configuration.

## 79.28 OAuth Investigation

``` text
TOKEN ISSUED?
     |
     v
TOKEN VALID?
     |
     v
SNOWFLAKE ACCEPTS TOKEN?
     |
     v
ROLE AUTHORIZED?
     |
     v
OBJECT ACCESS?
```

## 79.29 SSO Failure

Possible causes include identity-provider outage, federation
configuration, certificate issue, user mapping, MFA, browser/session
issue, incorrect account URL, and network policy.

## 79.30 SSO Scope

If one user fails, investigate user-specific configuration. If all SSO
users fail, investigate federation, IdP, or account-wide configuration.

## 79.31 MFA Investigation

Determine authentication method, client compatibility, enrollment state,
policy, and recent policy changes.

Do not bypass MFA controls merely to restore convenience.

## 79.32 Service Account vs Human User

Human users may use SSO, MFA, and interactive login.

Service identities may use key pair, OAuth, or workload identity.

Avoid treating them identically.

## 79.33 Authorization

If login succeeds but SQL fails, move to authorization troubleshooting.

## 79.34 Current Role

``` sql
SELECT CURRENT_ROLE();
```

## 79.35 Role Inventory

``` sql
SHOW ROLES;
```

## 79.36 User Grants

``` sql
SHOW GRANTS TO USER SVC_PATIENT360;
```

Confirm the required role is granted to the user.

## 79.37 Role Grants

``` sql
SHOW GRANTS TO ROLE PATIENT360_APP_ROLE;
```

This is one of the most important authorization troubleshooting
commands.

## 79.38 Role Hierarchy

``` text
PATIENT360_APP_ROLE
        |
        v
PATIENT360_READ_ROLE
        |
        v
Object privileges
```

Understand inherited privileges before adding duplicate grants.

## 79.39 Default Role

A user may authenticate successfully but begin with a role that lacks
required privileges.

## 79.40 Explicit Role Selection

``` sql
USE ROLE PATIENT360_APP_ROLE;
```

If this resolves the issue, investigate default-role/session
configuration rather than adding unnecessary object privileges.

## 79.41 Warehouse Privilege

To execute queries using a warehouse, the active role needs the
appropriate warehouse privilege.

## 79.42 Warehouse Failure

If a user can connect and see the database but cannot use the warehouse,
investigate warehouse grants.

## 79.43 Show Warehouse Grants

``` sql
SHOW GRANTS ON WAREHOUSE PATIENT360_APP_WH;
```

## 79.44 Database Access

Object access normally requires appropriate privileges through the
hierarchy:

``` text
Database
   |
   v
Schema
   |
   v
Object
```

## 79.45 Database USAGE

``` sql
GRANT USAGE
ON DATABASE DAP
TO ROLE PATIENT360_APP_ROLE;
```

Only grant after confirming it is required and approved.

## 79.46 Schema USAGE

``` sql
GRANT USAGE
ON SCHEMA DAP.L2
TO ROLE PATIENT360_APP_ROLE;
```

## 79.47 Table SELECT

``` sql
GRANT SELECT
ON TABLE DAP.L2.EMPI
TO ROLE PATIENT360_APP_ROLE;
```

## 79.48 Privilege Chain

A SELECT workload may require:

``` text
USAGE on database
        +
USAGE on schema
        +
SELECT on table/view
        +
USAGE on warehouse
```

depending on the operation.

## 79.49 Object Does Not Exist or Not Authorized

Snowflake may intentionally avoid revealing object existence when the
active role lacks access.

Therefore, an "object does not exist or not authorized" message does not
always mean the object is absent.

## 79.50 Check Context

Verify database, schema, object name, and role.

## 79.51 Fully Qualified Name

``` sql
SELECT *
FROM DAP.L2.EMPI
LIMIT 10;
```

This helps distinguish context problems from object problems.

## 79.52 Case Sensitivity

Quoted identifiers can create case-sensitive names.

``` sql
CREATE TABLE "EmpiData" (...);
```

is not equivalent to every unquoted spelling.

## 79.53 Future Grants

A role may access existing tables but fail on newly created tables when
future grants are missing or incorrect.

## 79.54 Typical Future-Grant Symptom

``` text
Yesterday's tables work.
Today's newly created table fails.
```

Investigate future grants and ownership.

## 79.55 Future Grant Investigation

Ask who created the object, who owns it, whether future grants are
configured, whether the schema is managed access, and whether ownership
changed.

## 79.56 Managed Access Schema

Managed access schemas centralize grant management. Understand whether
the schema is managed access before attempting object-level grant
changes.

## 79.57 OWNERSHIP

Ownership is powerful. Do not transfer ownership simply to fix a SELECT
failure.

## 79.58 Ownership Investigation

Determine who owns the database, schema, and object, and who is
authorized to grant access.

## 79.59 Views

A user may have access to a view but encounter problems related to
dependencies, security model, or referenced objects depending on the
view type/design.

## 79.60 Secure Objects

Do not weaken secure-view or secure-sharing controls merely to
troubleshoot access.

## 79.61 Stored Procedures

Procedure behavior can depend on EXECUTE privilege, owner's rights,
caller's rights, referenced objects, and execution role.

## 79.62 Functions

Verify appropriate function privileges and referenced-object permissions
for the execution model.

## 79.63 Stage Authorization

For loading/unloading, verify access to stage, storage integration, file
format, target/source object, and warehouse where required.

## 79.64 Task Authorization

Task failures may be caused by execution-role privileges even when the
task owner can manually execute similar SQL under another role.

Always identify the actual automation context.

## 79.65 Service Account Production Standard

Service identities should have:

``` text
Dedicated user
Dedicated role
Required warehouse
Required database/schema/object privileges
Noninteractive authentication
Credential rotation
Ownership documentation
Monitoring
```

## 79.66 Avoid Shared Service Users

Shared credentials make it difficult to determine who used the account,
which application/deployment/secret was involved, and who rotated the
credential.

## 79.67 Least Privilege

Grant only what the workload requires.

An application that only needs `SELECT DAP.L2.EMPI` should not receive
CREATE DATABASE, DROP SCHEMA, MANAGE GRANTS, or ACCOUNTADMIN.

## 79.68 Troubleshooting Least Privilege

Determine the missing privilege and grant only that privilege through
the approved role model.

## 79.69 Reproduce Safely

Where appropriate, test using the same user, role, warehouse, database,
schema, and SQL as the failing workload.

Testing as ACCOUNTADMIN does not reproduce an application authorization
problem.

## 79.70 Application Context

An engineer successfully querying `DAP.L2.EMPI` as an administrator does
not prove `SVC_PATIENT360` using `PATIENT360_APP_ROLE` can execute it.

## 79.71 Query History

Use query history to identify user, role, warehouse, query, error, and
time for failed operations.

## 79.72 Failed Queries

``` sql
SELECT
    QUERY_ID,
    USER_NAME,
    ROLE_NAME,
    WAREHOUSE_NAME,
    QUERY_TEXT,
    ERROR_CODE,
    ERROR_MESSAGE,
    START_TIME
FROM SNOWFLAKE.ACCOUNT_USAGE.QUERY_HISTORY
WHERE EXECUTION_STATUS = 'FAIL'
  AND START_TIME >= DATEADD('hour', -4, CURRENT_TIMESTAMP())
ORDER BY START_TIME DESC;
```

Protect sensitive SQL/data when sharing troubleshooting output.

## 79.73 Last Successful Query

Identify the last successful and first failed query, then correlate with
grant/role/key/deployment/network/policy/object/ownership changes.

## 79.74 Object Recreation

Dropping and recreating an object can change ownership/grant behavior.

``` text
TABLE_A works
   |
DROP
   |
CREATE TABLE_A
   |
Application loses access
```

Investigate object lifecycle and grant automation.

## 79.75 Deployment-Induced Access Failure

A deployment may create/swap/recreate objects or change ownership
without restoring required grants.

## 79.76 Terraform / IaC Drift

If RBAC is managed by Terraform/IaC, emergency manual grants can create
drift.

``` text
Restore service
        |
        v
Update IaC
        |
        v
Reconcile state
```

Do not leave permanent undocumented manual access.

## 79.77 Privilege Revocation

If access suddenly stops, investigate REVOKE operations, role hierarchy
changes, ownership transfers, object recreation, future-grant changes,
IaC deployments, and security remediation.

## 79.78 Change Correlation

``` text
13:55  Terraform deployment
14:00  Application errors begin
14:03  Authorization failures detected
```

This correlation is stronger evidence than assuming Snowflake
instability.

## 79.79 Wrong Environment

Always verify the expected production account rather than accidentally
troubleshooting staging.

## 79.80 Wrong Role

The connection can succeed while the session uses an unexpected role.
Log non-sensitive session context for important service connections.

## 79.81 Wrong Warehouse

If the role has access to `PATIENT360_APP_WH` but configuration
specifies `PATIENT360_ETL_WH`, authorization may fail despite otherwise
correct grants.

## 79.82 Wrong Database or Schema

Applications that depend on session context rather than fully qualified
names can produce misleading object errors when database/schema context
is wrong.

## 79.83 Connection String

Validate account identifier, username, authentication method, role,
warehouse, database, schema, region, and private endpoint where
applicable.

Never log secret values.

## 79.84 Client Version

Capture driver, version, runtime, and authentication method. Old or
incompatible clients can occasionally contribute to authentication
problems.

## 79.85 Clock

Token-based mechanisms depend on correct time. Significant clock skew
can break authentication.

## 79.86 Network

If login history shows no corresponding attempt, investigate DNS,
firewall, proxy, routing, private connectivity, TLS, and client
behavior.

## 79.87 Private Connectivity

Verify DNS, endpoint, routing, security rules, network policy, and TLS
behavior.

## 79.88 Authentication Incident

Examples: user cannot log in, token rejected, key-pair failure, SSO
failure, network-policy block.

## 79.89 Authorization Incident

Examples: login works but warehouse/object/CREATE/DML access is denied.

## 79.90 Authentication First 10 Minutes

1.  Capture exact error.
2.  Identify user and authentication method.
3.  Verify account/region.
4.  Check login history.
5.  Determine whether Snowflake received the request.
6.  Compare source IP.
7.  Check user state.
8.  Check recent credential rotation.
9.  Check network/policy changes.
10. Check application deployment.
11. Avoid changing privileges.

## 79.91 Authorization First 10 Minutes

1.  Capture exact failing SQL.
2.  Identify user and active role.
3.  Identify warehouse/database/schema/object.
4.  Reproduce with equivalent context.
5.  Review grants to user and role.
6.  Review warehouse grant.
7.  Review database/schema/object privileges.
8.  Check role hierarchy.
9.  Check recent grant/object changes.

## 79.92 Authentication Runbook

1.  Record environment/account/region.
2.  Capture user/authentication method/error/timestamp.
3.  Review login history.
4.  Confirm request reached Snowflake.
5.  Review source IP and user state.
6.  Check network/authentication policies.
7.  Check key/token/SSO configuration.
8.  Check credential rotation and secret deployment.
9.  Check client configuration/version.
10. Check recent changes.
11. Correct the minimum issue.
12. Retest and confirm successful login.
13. Monitor, document root cause, and add prevention.

## 79.93 Key-Pair Runbook

1.  Identify service account/account/username.
2.  Review login-history error.
3.  Confirm expected public-key configuration.
4.  Confirm application secret/key version.
5.  Check rotation/deployment timeline.
6.  Validate private-key format/configuration safely.
7.  Test replacement credential through approved process.
8.  Restore service and complete rotation.
9.  Remove obsolete credential only after validation.
10. Document.

## 79.94 OAuth Runbook

1.  Capture error/integration.
2.  Confirm token issuance/expiration.
3.  Validate issuer/audience/role mapping.
4.  Check integration/client configuration and clock.
5.  Retest, monitor, and document.

## 79.95 SSO Runbook

1.  Determine one user vs many.
2.  Verify account URL.
3.  Check IdP availability/federation/certificates/user
    mapping/MFA/network policy.
4.  Review login history.
5.  Test a controlled user.
6.  Restore and document.

## 79.96 Authorization Runbook

1.  Capture user/active role/failing
    operation/warehouse/database/schema/object.
2.  Verify object exists with authorized administrative context.
3.  Review grants to user/role and role hierarchy.
4.  Review warehouse/database/schema/object privileges.
5.  Check ownership, managed access, future grants, and object
    recreation.
6.  Check recent IaC/grant changes.
7.  Identify minimum missing privilege.
8.  Obtain approval and grant through intended role.
9.  Retest using application context.
10. Reconcile IaC and document.

## 79.97 Warehouse Access Runbook

1.  Confirm active role and configured warehouse.
2.  `SHOW WAREHOUSES`.
3.  Review warehouse grants.
4.  Verify warehouse/environment.
5.  Ensure resource-monitor/state issues are not confused with
    privileges.
6.  Correct minimum grant/configuration.
7.  Retest and document.

## 79.98 Object Access Runbook

1.  Capture fully qualified object.
2.  Confirm object and active role.
3.  Check database/schema USAGE and object privilege.
4.  Check ownership, future grants, managed access, and object
    recreation.
5.  Correct through approved RBAC model.
6.  Retest and document.

## 79.99 Patient360 Service Account Scenario

Application: `Patient360 API`\
Identity: `SVC_PATIENT360`\
Authentication: Key pair\
Role: `PATIENT360_APP_ROLE`

## 79.100 Incident

At 14:00 all Patient360 Snowflake connections fail.

## 79.101 First Check

Application logs show authentication failure. Do not start with table
grants.

## 79.102 Login History

Failures begin immediately after a scheduled key rotation.

## 79.103 Secret Investigation

Snowflake has the new public key while the application still uses the
old private key.

## 79.104 Root Cause

Credential rotation was completed on the Snowflake side before the
application switched to the new private key.

## 79.105 Immediate Mitigation

Restore a valid credential pairing through the approved
rotation/recovery process.

## 79.106 Permanent Fix

``` text
Add new public key
       |
       v
Deploy new private key
       |
       v
Validate application
       |
       v
Remove old key
```

## 79.107 New Table Authorization Scenario

The application successfully queries `DAP.L2.EMPI` but fails against
`DAP.L2.EMPI_V2`.

## 79.108 Investigation

Authentication, warehouse, and database/schema access work. Only the new
table fails.

## 79.109 Finding

The deployment created `EMPI_V2`, but the application role was not
granted access through the intended RBAC/future-grant model.

## 79.110 Root Cause

Deployment created the new object without applying required application
privileges.

## 79.111 Permanent Fix

Fix deployment/IaC/future-grant automation rather than repeatedly
applying manual grants.

## 79.112 Access Incident RCA Template

``` text
Incident:
Environment:
Account:
Region:
Application:
User:
Authentication method:
Role:
Warehouse:
Database:
Schema:
Object:
Operation:
Last successful access:
First failed access:
Exact error:
Login history finding:
Source IP:
User state:
Network-policy finding:
Credential-rotation finding:
Role finding:
Warehouse-grant finding:
Database-grant finding:
Schema-grant finding:
Object-grant finding:
Ownership finding:
Recent change:
Root cause:
Contributing factors:
Immediate mitigation:
Permanent remediation:
IaC update required:
Credential rotation required:
Preventive monitoring:
Owner:
```

## 79.113 Authentication Monitoring

Monitor failed logins, failure spikes, service-account failures,
unexpected source IPs, authentication-method changes, and credential
rotation/expiration.

## 79.114 Authorization Monitoring

Track important GRANT/REVOKE operations, ownership changes, role
hierarchy changes, privileged roles, and service-account role changes
using approved security/audit mechanisms.

## 79.115 Credential Rotation Monitoring

Maintain credential owner, rotation schedule, last/next rotation,
application dependency, rollback procedure, and validation procedure.

## 79.116 Break-Glass Access

Break-glass access should be rare, approved, audited, time-bounded,
documented, and reviewed.

## 79.117 Production RBAC Standard

Use a deliberate hierarchy such as functional roles inheriting
appropriate object-access roles according to the organization's
Snowflake RBAC model.

## 79.118 Service Identity Standard

Every service identity should have a dedicated user/role, documented
owner/application, approved authentication, only required
warehouse/object access, rotation process, monitoring, and runbook.

## 79.119 Access Request Standard

Include user/service, environment, role, database, schema, object,
required privilege, business reason, owner approval, and duration.

## 79.120 Temporary Access

Temporary elevated access should have a planned removal mechanism. Do
not rely on someone remembering to revoke it.

## 79.121 Common Mistakes

Avoid granting ACCOUNTADMIN to troubleshoot, resetting passwords for
authorization problems, adding table grants for authentication problems,
ignoring login history/source IP/network policy/key rotation, logging
secrets, sharing private keys, ignoring OAuth/SSO/MFA state, testing
only as admin, ignoring current role/warehouse/database/schema
privileges/role hierarchy/future grants/managed access, transferring
ownership to fix SELECT, ignoring object recreation/IaC drift, leaving
permanent manual grants, using shared service credentials, or operating
without credential-rotation/access-monitoring runbooks.

## 79.122 Authentication Checklist

-   [ ] Exact error/timestamp captured
-   [ ] Environment/account/region/user verified
-   [ ] Authentication method identified
-   [ ] Login history/source IP/user state checked
-   [ ] Network/authentication policy checked
-   [ ] Credential rotation/secret deployment checked
-   [ ] OAuth/SSO/key configuration checked
-   [ ] Client version checked
-   [ ] Recent changes reviewed
-   [ ] Root cause established
-   [ ] Successful authentication validated

## 79.123 Authorization Checklist

-   [ ] Authentication succeeds
-   [ ] User/active role/warehouse/database/schema/object/operation
    captured
-   [ ] Fully qualified object tested
-   [ ] Grants to user/role reviewed
-   [ ] Role hierarchy reviewed
-   [ ] Warehouse privilege reviewed
-   [ ] Database/schema USAGE reviewed
-   [ ] Object privilege reviewed
-   [ ] Ownership/managed access/future grants reviewed
-   [ ] Object recreation/recent IaC changes reviewed
-   [ ] Minimum missing privilege identified
-   [ ] Approved remediation applied
-   [ ] Application-context test successful
-   [ ] IaC reconciled

## 79.124 Access Troubleshooting Flow

``` text
ACCESS FAILURE
      |
      v
LOGIN SUCCESS?
      |
   +--+--+
   |     |
  No    Yes
   |     |
   v     v
AUTH     ROLE CORRECT?
   |         |
   |      +--+--+
   |      |     |
   |     No    Yes
   |      |     |
   |      v     v
   |     ROLE  WAREHOUSE ACCESS?
   |              |
   |           +--+--+
   |           |     |
   |          No    Yes
   |           |     |
   |           v     v
   |          WH    DB/SCHEMA ACCESS?
   |                   |
   |                +--+--+
   |                |     |
   |               No    Yes
   |                |     |
   |                v     v
   |              USAGE  OBJECT PRIVILEGE
   |
   v
LOGIN HISTORY
   |
   +--> User
   +--> Credentials
   +--> OAuth / SSO
   +--> Network Policy
   +--> Source IP
   +--> Client
```

## 79.125 Quick Reference

``` sql
SELECT
    CURRENT_USER(),
    CURRENT_ROLE(),
    CURRENT_WAREHOUSE(),
    CURRENT_DATABASE(),
    CURRENT_SCHEMA();

SELECT
    CURRENT_ORGANIZATION_NAME(),
    CURRENT_ACCOUNT_NAME(),
    CURRENT_REGION();

SHOW USERS;
SHOW ROLES;
SHOW GRANTS TO USER SVC_PATIENT360;
SHOW GRANTS TO ROLE PATIENT360_APP_ROLE;
SHOW GRANTS ON WAREHOUSE PATIENT360_APP_WH;
USE ROLE PATIENT360_APP_ROLE;
SHOW WAREHOUSES;
```

## 79.126 Authentication & Authorization Principles

1.  Authentication and authorization are different problems.
2.  Determine which one failed before remediation.
3.  Do not grant ACCOUNTADMIN to troubleshoot.
4.  Verify account and region.
5.  Capture the exact user and authentication method.
6.  Use login history for authentication evidence.
7.  Compare successful and failed source IPs.
8.  Network policies can cause apparent authentication failures.
9.  Key-pair rotation requires coordination.
10. Validate new credentials before removing old ones.
11. Never expose private keys or passwords.
12. OAuth failures require token/integration investigation.
13. SSO failures require IdP/federation investigation.
14. MFA should not be bypassed casually.
15. Service and human identities require different operating models.
16. After authentication succeeds, verify current role.
17. Review grants to user and role.
18. Understand role hierarchy.
19. Verify warehouse/database/schema/object access.
20. "Does not exist or not authorized" may be an authorization issue.
21. Use fully qualified object names during troubleshooting.
22. Understand quoted identifier behavior.
23. Future grants matter for newly created objects.
24. Managed access affects grant administration.
25. Ownership should not be moved casually.
26. Reproduce failures using application context.
27. Testing as ACCOUNTADMIN proves little about application access.
28. Compare last success with first failure.
29. Correlate failures with deployments and grant changes.
30. Object recreation can alter access behavior.
31. IaC-managed RBAC should remain authoritative.
32. Emergency manual changes must be reconciled.
33. Shared service credentials reduce accountability.
34. Use least privilege.
35. Monitor authentication and authorization changes.
36. Fix the minimum broken layer rather than broadening access.

## 79.127 Chapter Completion Checklist

After completing this chapter, you should be able to:

-   Distinguish authentication from authorization.
-   Troubleshoot login failures and use login history.
-   Investigate source-IP/network-policy problems.
-   Troubleshoot password, key-pair, OAuth, SSO, and MFA authentication.
-   Perform safe key rotation.
-   Troubleshoot service-account access.
-   Verify session/account context.
-   Troubleshoot roles and role hierarchy.
-   Troubleshoot warehouse/database/schema/object privileges.
-   Understand USAGE, future grants, managed access, and ownership.
-   Diagnose object recreation/deployment access failures.
-   Reproduce access using application context.
-   Reconcile RBAC with Terraform/IaC.
-   Execute
    authentication/key-pair/OAuth/SSO/authorization/warehouse/object
    runbooks.
-   Produce an evidence-based access RCA.
-   Establish preventive access monitoring.

**Chapter 79 --- Snowflake Authentication & Permission Troubleshooting:
Complete**
