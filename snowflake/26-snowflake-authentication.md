# 26 — Snowflake Authentication

## Overview

Authentication answers one fundamental question: **Who are you?**

Before Snowflake evaluates what a user or service is authorized to do, the connecting identity must first authenticate successfully.

```text
Client
  |
  v
Identity
  |
  v
Authentication
  |
  v
Snowflake Session
  |
  v
Authorization / RBAC
```

Snowflake supports multiple authentication approaches for human users, applications, automation, and service workloads.

Common approaches include password authentication, multi-factor authentication (MFA), federated authentication/SSO, key-pair authentication, OAuth, workload identity federation where supported, and programmatic access tokens where appropriate.

Production authentication must be designed around identity, credential protection, rotation, MFA, federation, monitoring, and recovery.

---

# Part 1 — Authentication vs Authorization

## 1. Authentication

Authentication determines who you are.

Examples include password, MFA, key pair, OAuth token, and federated identity.

---

## 2. Authorization

Authorization determines what you are allowed to do.

Examples include using warehouses, selecting tables, creating schemas, and administering users.

Snowflake roles and privileges control authorization.

Chapter 27 covers RBAC and role hierarchy.

---

## 3. Authentication Flow

```text
User / Application
        |
        v
Credentials / Identity
        |
        v
Authentication
        |
        +---- Failure → Connection rejected
        |
        +---- Success
                |
                v
             Session
                |
                v
         Role / Privileges
```

Successful authentication does not imply unlimited access.

---

# Part 2 — Snowflake Users

## 4. User Objects

Snowflake users are account-level objects representing identities that can interact with the platform according to their configuration and assigned privileges.

---

## 5. Create a User

```sql
CREATE USER tutorial_user
    PASSWORD = '<temporary-secure-password>'
    DEFAULT_ROLE = tutorial_role
    DEFAULT_WAREHOUSE = tutorial_wh;
```

Do not use weak passwords or expose credentials in source control.

---

## 6. Inspect Users

```sql
SHOW USERS;
```

Use this to review users and relevant metadata available through the command output.

---

## 7. Describe a User

```sql
DESC USER tutorial_user;
```

Avoid exposing sensitive authentication information in tickets, screenshots, or chat messages.

---

# Part 3 — Human vs Service Identities

## 8. Human Users

Human users normally require interactive authentication.

Examples include engineers, analysts, administrators, data scientists, and business users.

Human authentication should generally integrate with organizational identity controls.

---

## 9. Service Users

Machine workloads include ETL pipelines, Airflow, dbt, applications, Kubernetes workloads, CI/CD, Terraform, and monitoring systems.

Machine identities should not depend on interactive human authentication.

---

## 10. Separate Human and Machine Identity

Avoid using an employee account for both human access and production automation.

If the employee leaves or the account is disabled, production automation can break.

Prefer dedicated workload identities.

---

# Part 4 — Password Authentication

## 11. Password Authentication

The simplest conceptual authentication flow is username plus password.

Client configuration commonly includes account, user, password, warehouse, database, schema, and role.

---

## 12. Password Security

Never store passwords in Git repositories, SQL scripts, container images, Dockerfiles, ConfigMaps, documentation, Slack messages, or tickets.

Use an approved secret-management system.

---

## 13. Password Rotation

If passwords are used for automation, define credential owner, rotation interval, secret store, deployment process, rollback procedure, and monitoring.

Manual password rotation without coordination can cause outages.

---

## 14. Password Rotation Failure Scenario

If a password is rotated in Snowflake while the application still has the old password, authentication failures and pipeline outages can result.

Credential rotation is an operational change and should be tested accordingly.

---

# Part 5 — Multi-Factor Authentication

## 15. What Is MFA?

Multi-factor authentication requires more than one authentication factor.

MFA significantly reduces risk associated with password compromise.

---

## 16. MFA for Human Users

Privileged human access should use strong authentication controls according to organizational policy.

This includes administrators, security teams, platform engineers, DBAs, and production support.

---

## 17. MFA Is Not a Machine Credential Strategy

Do not build automated workloads that require a person to approve MFA challenges.

Use an appropriate non-interactive authentication method for service workloads.

---

# Part 6 — Federated Authentication / SSO

## 18. Single Sign-On

Federated authentication allows Snowflake authentication to integrate with an enterprise identity provider.

Examples may include Microsoft Entra ID, Okta, and Ping Identity depending on organizational architecture.

---

## 19. Benefits of SSO

SSO can centralize user lifecycle, authentication policy, MFA, conditional access, identity governance, and employee termination controls.

---

## 20. Federated Authentication Flow

```text
User
 |
 v
Snowflake login
 |
 v
Identity Provider
 |
 v
Authentication + MFA
 |
 v
Federation assertion
 |
 v
Snowflake session
```

The exact flow depends on the configured federation architecture.

---

## 21. SSO Failure Domains

If SSO fails, investigate Snowflake, the identity provider, federation configuration, certificates, user mapping, network/browser behavior, and authentication policy.

---

# Part 7 — Key-Pair Authentication

## 22. Why Key-Pair Authentication?

Key-pair authentication is commonly used for non-interactive workloads.

The client proves identity using a private key while Snowflake stores the corresponding public-key information on the user.

---

## 23. Public vs Private Key

The private key must remain secret and client-side.

The public key is assigned to the Snowflake user.

---

## 24. Generate RSA Key Pair

Example using OpenSSL:

```bash
openssl genrsa 2048 | openssl pkcs8 -topk8 -inform PEM -out rsa_key.p8
```

Generate the public key:

```bash
openssl rsa -in rsa_key.p8 -pubout -out rsa_key.pub
```

Use organizationally approved cryptographic standards and key-management procedures.

---

## 25. Protect the Private Key

On supported Unix-like environments:

```bash
chmod 600 rsa_key.p8
```

File permissions alone are not a complete security strategy.

Prefer secure secret/key-management systems for production automation.

---

## 26. Assign Public Key

After extracting the public-key value in the format required by Snowflake:

```sql
ALTER USER service_user
SET RSA_PUBLIC_KEY = '<public-key-value>';
```

Do not place the private key in Snowflake.

---

## 27. Key-Pair Connection

The application uses the Snowflake username and private key while Snowflake validates against the configured public key.

---

## 28. Key Rotation

Snowflake supports key-rotation patterns that allow transition between key pairs.

Use supported primary and secondary public-key properties according to current Snowflake documentation.

---

## 29. Why Dual-Key Rotation Matters

Avoid removing the old key before the new client credential is deployed and validated.

Prefer an overlap period where both old and new keys can authenticate, then retire the old key after successful validation.

---

# Part 8 — OAuth

## 30. OAuth Authentication

OAuth allows supported clients to authenticate using tokens rather than directly using a Snowflake password.

OAuth is useful for certain applications and identity architectures.

---

## 31. OAuth Security Integration

OAuth configurations use Snowflake security integrations according to the selected OAuth architecture.

Conceptually:

```sql
CREATE SECURITY INTEGRATION ...
TYPE = OAUTH
...
```

Exact configuration depends on whether the architecture uses Snowflake OAuth or an external OAuth provider.

---

## 32. Token Lifecycle

Tokens have a lifecycle: issue, use, expire, and refresh/obtain a new token.

Applications must handle token expiration correctly.

---

## 33. OAuth Failure Scenario

If an application presents an expired token, Snowflake rejects authentication.

The application should obtain a valid token according to the configured OAuth flow rather than repeatedly retrying an expired token.

---

# Part 9 — Workload Identity Federation

## 34. Workload Identity

Modern cloud environments increasingly use workload identity rather than long-lived static secrets where supported.

The exact supported architecture depends on Snowflake features, cloud provider, client, and account configuration.

---

## 35. Why Workload Identity Is Valuable

It can reduce dependence on long-lived passwords, private keys, and manually rotated static credentials by relying on short-lived identity assertions or tokens.

---

## 36. Example Workloads

Potential workloads include AWS, Azure, Google Cloud, Kubernetes, and CI/CD workloads.

Use only architectures currently supported by Snowflake and the relevant client/driver.

---

# Part 10 — Programmatic Access

## 37. Drivers and Connectors

Snowflake authentication is used by Snowflake CLI, Python Connector, JDBC, ODBC, Snowpark, Terraform, BI tools, ETL platforms, and applications.

Not every authentication method is supported identically by every client/version.

---

## 38. Python Connector Concept

```python
import snowflake.connector

conn = snowflake.connector.connect(
    account="my_account",
    user="my_user",
    password="...",
    warehouse="my_wh",
    database="my_db",
    schema="my_schema"
)
```

Do not hard-code the password in production code.

---

## 39. Key-Pair Python Connection

Conceptually:

```python
conn = snowflake.connector.connect(
    account="my_account",
    user="service_user",
    private_key=private_key,
    warehouse="my_wh",
    database="my_db"
)
```

The exact private-key loading code depends on application security implementation and connector requirements.

---

## 40. Environment Variables

Environment variables can reduce credentials embedded directly in source code, but they are not automatically secure.

Avoid exposing them through process dumps, debug output, CI logs, shell history, or container inspection.

---

# Part 11 — Authentication Policies

## 41. Centralized Authentication Controls

Snowflake provides security mechanisms that can help organizations centrally govern authentication behavior.

Authentication policies should reflect human users, service users, approved clients, authentication methods, MFA requirements, and organizational standards.

---

## 42. Different Identity Classes

A useful model is human identities using SSO/MFA and service identities using key pair, OAuth, or workload identity where supported.

The exact standards should match organizational policy and currently supported Snowflake capabilities.

---

# Part 12 — Network and Authentication

## 43. Authentication vs Network Access

A user can have valid credentials but still fail to connect because of network restrictions.

Network policies are covered in Chapter 30.

---

## 44. Troubleshooting Order

When a connection fails, separate DNS/network, network policy, authentication, authorization, and warehouse/database access.

Do not treat every connection failure as a password problem.

---

# Part 13 — Authentication Monitoring

## 45. Login History

Snowflake provides login history information that can help investigate authentication events.

Use appropriate account usage/information schema interfaces available to your environment.

Review user, time, client, authentication result, error, and source information where available.

---

## 46. Authentication Failure Monitoring

Monitor repeated failed logins, unexpected source locations, disabled-user attempts, expired credentials, unexpected authentication methods, and service-account failures.

---

## 47. Service Account Monitoring

A service account that normally authenticates successfully and suddenly starts failing can indicate credential rotation problems, expired tokens, key mismatch, configuration deployment, network restrictions, or user changes.

---

# Part 14 — Credential Lifecycle

## 48. Credential Inventory

Maintain an inventory of service authentication.

| Service | Snowflake User | Auth Method | Owner | Rotation |
|---|---|---|---|---|
| ETL | ETL_SVC | Key pair | Data Platform | Defined |
| Terraform | TF_SVC | Workload/key pair | Platform | Defined |
| BI | BI_SVC | OAuth/SSO | Analytics | Defined |

Avoid unknown service accounts.

---

## 49. Credential Ownership

Every production credential should have a technical owner, business/service owner, rotation process, recovery process, and monitoring.

---

## 50. Credential Rotation Runbook

A safe rotation process:

1. Identify consumers.
2. Generate/new credential.
3. Add new credential.
4. Update secret store.
5. Deploy consumers.
6. Validate authentication.
7. Monitor.
8. Remove old credential.
9. Verify old credential no longer works.
10. Document completion.

Avoid destructive rotation before consumers are ready.

---

# Part 15 — Production Authentication Standards

## 51. Human Users

A recommended general model is enterprise identity provider → SSO → MFA → Snowflake.

Exceptions should be documented and controlled.

---

## 52. Service Accounts

Use controlled non-interactive authentication and least-privilege roles.

Avoid sharing service credentials between unrelated applications.

---

## 53. Separate Service Identities

Prefer separate identities such as AIRFLOW_SVC, DBT_SVC, TERRAFORM_SVC, APP_SVC, and MONITORING_SVC where operationally appropriate.

This improves auditing, credential rotation, least privilege, and incident isolation.

---

## 54. Break-Glass Access

Break-glass accounts should be rarely used, strongly protected, monitored, documented, tested, and audited.

Do not use emergency accounts for routine administration.

---

# Part 16 — Troubleshooting

## 55. Invalid Username or Password

Check account identifier, username, authentication method, credential, user status, authentication policy, and client configuration.

Do not repeatedly rotate credentials before identifying the actual problem.

---

## 56. Key-Pair Authentication Fails

Check the Snowflake user, private key, matching public key, key format, encryption/passphrase handling, connector configuration, file permissions, and key rotation state.

Verify the public-key fingerprint where appropriate.

---

## 57. Key Mismatch

Ensure the deployed private key corresponds to one of the valid public keys configured for the Snowflake user.

---

## 58. SSO Authentication Fails

Check identity provider health, user existence/mapping, federation configuration, certificate/configuration changes, MFA, conditional-access policy, browser/client behavior, and Snowflake integration.

---

## 59. OAuth Authentication Fails

Check token expiration, issuer, audience, scope, security integration, user mapping, role mapping, client configuration, and clock/time issues.

Capture the exact authentication error.

---

## 60. Works in UI but Fails in Application

The clients may be using different authentication methods.

Compare authentication paths before assuming an account-wide Snowflake problem.

---

## 61. Works Locally but Fails in Kubernetes

Check secret mounts, key/password, file permissions, environment variables, account identifier, network path, proxy, DNS, clock, and connector version.

---

## 62. Authentication Suddenly Fails

Ask what changed.

Check password/key rotation, OAuth configuration, IdP changes, user changes, authentication policy, network policy, application deployment, connector upgrade, and secret-store changes.

---

# Part 17 — Production Incident Runbook

## 63. Authentication Incident Runbook

When a production workload cannot authenticate:

1. Capture affected user/service.
2. Capture timestamp.
3. Capture client/application.
4. Capture exact error.
5. Identify authentication method.
6. Determine whether one or many users are affected.
7. Check Snowflake availability.
8. Check network/DNS path.
9. Check network policies.
10. Check user status.
11. Check authentication policy.
12. Check login history.
13. Check recent credential rotation.
14. Check secret-store deployment.
15. For key pair, validate key/public-key match.
16. For SSO, check IdP health/configuration.
17. For OAuth, check token/integration configuration.
18. Check recent client/connector changes.
19. Correct the failed layer.
20. Test with the intended client.
21. Monitor recovery.
22. Confirm backlog processing if applicable.
23. Document root cause.

---

## 64. Do Not Destroy Evidence

During an authentication incident, avoid immediately resetting every password, replacing every key, changing every role, or disabling policies.

These actions can destroy useful evidence or create additional outages.

Collect evidence first unless immediate containment is required for a security incident.

---

# Part 18 — Security Incident Considerations

## 65. Suspected Credential Compromise

If compromise is suspected, follow organizational security incident procedures.

Potential actions may include disabling the affected credential/user, revoking or rotating credentials, reviewing login/access history, determining affected resources, engaging the security team, and preserving evidence.

---

## 66. Credential Exposure in Git

Removing a leaked credential from the current file does not make the credential safe again.

Assume it may have been exposed and rotate/revoke it as appropriate.

Repository history may retain the secret.

---

## 67. Private Key Exposure

If a private key is exposed, treat it as compromised.

Safely deploy replacement credentials and revoke the old trust according to incident and rotation procedures.

---

# Part 19 — Hands-On Lab

## 68. Lab Objective

Practice user creation, password authentication concepts, key-pair authentication, public-key configuration, key rotation, login-history investigation, and authentication troubleshooting.

Use a non-production environment.

---

## 69. Create Lab User

```sql
CREATE USER snowflake_auth_lab_user
    PASSWORD = '<secure-temporary-password>'
    MUST_CHANGE_PASSWORD = TRUE;
```

Use a secure temporary password generated according to organizational policy.

Do not commit it to the tutorial repository.

---

## 70. Inspect User

```sql
DESC USER snowflake_auth_lab_user;
```

---

## 71. Generate Key Pair

```bash
openssl genrsa 2048 | openssl pkcs8 -topk8 -inform PEM -out snowflake_lab_key.p8

openssl rsa     -in snowflake_lab_key.p8     -pubout     -out snowflake_lab_key.pub
```

Protect the private key.

---

## 72. Configure Public Key

```sql
ALTER USER snowflake_auth_lab_user
SET RSA_PUBLIC_KEY = '<public-key-value>';
```

Never paste the private key into this command.

---

## 73. Verify Key Configuration

```sql
DESC USER snowflake_auth_lab_user;
```

Use Snowflake-supported fingerprint/metadata mechanisms where appropriate to verify the expected public key.

---

## 74. Test Key Authentication

Configure an approved client using account, user, private key, warehouse, and role.

Then execute:

```sql
SELECT
    CURRENT_USER(),
    CURRENT_ROLE(),
    CURRENT_WAREHOUSE();
```

Verify expected identity and session context.

---

## 75. Rotation Exercise

Generate a second key pair and configure the secondary public key using the supported secondary-key property.

Update the client to use the second private key and validate:

```sql
SELECT CURRENT_USER();
```

Only after successful validation should the old key be retired.

---

## 76. Authentication Failure Exercise

In the lab environment, intentionally use an invalid credential.

Capture timestamp, user, client, error, and authentication method, then investigate corresponding login evidence.

---

## 77. Cleanup

```sql
DROP USER IF EXISTS snowflake_auth_lab_user;
```

Securely remove lab private keys according to organizational key-handling procedures.

---

# Part 20 — Authentication Checklist

## 78. Human Authentication Checklist

- Enterprise identity provider used where required
- MFA enforced according to policy
- Personal accounts not shared
- Privileged accounts controlled
- Authentication policy documented
- Login failures monitored
- Offboarding integrated
- Break-glass process defined

---

## 79. Service Authentication Checklist

- Dedicated service identity
- Non-interactive authentication
- No credentials in source code
- Approved secret/key storage
- Credential owner defined
- Rotation procedure defined
- Rotation tested
- Least-privilege role
- Login failures monitored
- Recovery process documented

---

## 80. Production Readiness Checklist

Before a new application connects to Snowflake:

- Identity created
- Human/service classification defined
- Authentication method approved
- Client supports selected method
- Credentials securely stored
- Network path tested
- Network policy validated
- Authentication policy validated
- Role assigned
- Warehouse access validated
- Database/schema access validated
- Rotation procedure documented
- Monitoring configured
- Failure runbook documented

---

# Acceptance Criteria

The chapter is complete when you can:

- distinguish authentication from authorization
- explain Snowflake user identities
- distinguish human and service identities
- explain password authentication risks
- explain MFA
- explain SSO/federated authentication
- describe key-pair authentication
- generate an RSA key pair
- protect private keys
- configure a Snowflake public key
- perform safe key rotation
- explain OAuth authentication
- understand token lifecycle
- explain workload identity concepts
- understand connector authentication
- explain authentication policies
- separate network and authentication failures
- investigate login failures
- maintain credential inventory
- design credential rotation
- design service identities
- understand break-glass access
- troubleshoot password failures
- troubleshoot key-pair failures
- troubleshoot SSO failures
- troubleshoot OAuth failures
- investigate application-specific authentication failures
- respond to suspected credential compromise
- handle credentials exposed in source control
- execute the production authentication incident runbook

---

## Key Takeaways

Authentication establishes identity. Authorization then determines what that identity can do.

Human authentication should generally favor centrally governed enterprise identity controls such as SSO and MFA.

Service authentication should use controlled non-interactive methods such as key pair, OAuth, or supported workload identity.

Avoid long-lived unmanaged credentials wherever practical.

Credential creation is only the beginning. Production authentication requires the complete lifecycle: provision, secure, use, monitor, rotate, and revoke.

A secure Snowflake authentication design should provide strong identity, least privilege, credential protection, rotation, monitoring, and incident recovery.

The next chapter is **Chapter 27 — RBAC & Role Hierarchy**.
