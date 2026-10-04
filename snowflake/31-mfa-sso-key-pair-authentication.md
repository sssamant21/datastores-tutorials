# 31 — MFA, SSO & Key-Pair Authentication

## Overview

Snowflake authentication answers a fundamental security question: who is attempting to connect?

Production environments contain human users, administrators, developers, data engineers, BI users, applications, ETL pipelines, automation, Terraform, and monitoring systems. These identities should not necessarily authenticate the same way.

A strong production model separates human authentication from machine authentication. Human users commonly use enterprise federation plus MFA. Machine identities should use approved non-interactive authentication such as key-pair authentication, OAuth, or workload identity where appropriate.

Authentication should work together with network security, RBAC, governance, and monitoring.

This chapter covers MFA, federated SSO, key-pair authentication, named key pairs, migration, credential rotation, service accounts, monitoring, troubleshooting, and incident response.

---

# Part 1 — Authentication vs Authorization

## 1. Authentication

Authentication verifies identity.

Examples include password, MFA, SSO, key pair, OAuth, and workload identity.

Authentication answers: who are you?

## 2. Authorization

Authorization determines what the authenticated identity can do.

Snowflake authorization primarily uses roles and privileges.

Authorization answers: what are you allowed to do?

## 3. Keep the Layers Separate

A user can authenticate successfully and still receive an insufficient-privileges error. That is an authorization problem.

Conversely, a user can have correctly configured roles but fail to log in. That is an authentication problem.

---

# Part 2 — Authentication Strategy

## 4. Identity Classes

Before choosing authentication, classify the identity:

- Human employee
- Administrator
- Contractor
- Service account
- Application
- CI/CD pipeline
- Infrastructure automation
- Monitoring system
- Emergency account

Different identity classes have different requirements.

## 5. Human Authentication

A common enterprise pattern is employee → corporate identity provider → MFA → federated SSO → Snowflake.

This centralizes identity lifecycle and authentication policy.

## 6. Machine Authentication

A common machine pattern is application → dedicated Snowflake service user → key pair/OAuth/approved workload identity → dedicated role → Snowflake.

Avoid using a human employee's credentials in automation.

---

# Part 3 — Multi-Factor Authentication

## 7. What Is MFA?

Multi-factor authentication requires additional authentication assurance beyond a single reusable credential.

MFA significantly reduces the usefulness of stolen passwords.

## 8. Why MFA Matters

If a password is compromised, an enforced second factor can prevent the password alone from being sufficient for authentication.

## 9. Human Users

Interactive human users should follow the organization's MFA requirements. Administrative users deserve especially strong protection because compromise can have a larger blast radius.

## 10. MFA and SSO

MFA and SSO solve related but different problems.

SSO centralizes identity authentication. MFA adds authentication assurance.

Snowflake authentication policies can control allowed authentication methods and MFA requirements. Federated environments can also enforce MFA through the identity provider according to the chosen architecture.

---

# Part 4 — Federated Single Sign-On

## 11. What Is Federated SSO?

Federated SSO allows Snowflake to trust authentication performed by an external identity provider.

Conceptually:

User → Identity Provider → Authentication → Federation → Snowflake

## 12. Benefits of SSO

SSO can provide centralized authentication, centralized MFA, enterprise identity policy, centralized lifecycle management, reduced Snowflake-specific passwords, improved user experience, and stronger auditability.

## 13. Supported Federation Models

Snowflake supports federated authentication through SAML 2.0 and OpenID Connect (OIDC) security integrations.

Common enterprise identity providers include Microsoft Entra ID, Okta, and other supported standards-compliant providers.

---

# Part 5 — SAML Federation

## 14. SAML Concept

A common SAML flow is browser → Snowflake → identity provider → authentication → SAML assertion → Snowflake session.

## 15. Identity Provider

The IdP authenticates the user and can enforce password policy, MFA, conditional access, device requirements, location restrictions, and risk policies.

## 16. Service Provider

Snowflake acts as the service provider in the SAML federation model. The federation configuration establishes trust between Snowflake and the identity provider.

---

# Part 6 — Security Integration

## 17. Snowflake Security Integration

Federated SAML authentication is configured through a SAML2 security integration. OIDC federation uses an OIDC security integration.

Legacy SAML account parameters are deprecated; use security integrations for current designs.

## 18. Inspect Security Integrations

```sql
SHOW SECURITY INTEGRATIONS;
```

Then inspect the relevant integration:

```sql
DESC SECURITY INTEGRATION <integration_name>;
```

## 19. Treat Integration Changes Carefully

Changes to issuer configuration, URLs, certificates, metadata, identifiers, or authentication settings can affect many users and should be treated as production security changes.

---

# Part 7 — SSO User Mapping

## 20. Identity Mapping

The identity asserted by the IdP must map correctly to the Snowflake user.

A mismatch can cause authentication failure even when IdP authentication succeeds.

## 21. LOGIN_NAME

```sql
DESC USER jane_smith;
```

Pay attention to the login identity expected by the federation/client configuration.

## 22. Common Mapping Problem

If the IdP identity and Snowflake expected login identity differ, IdP authentication can succeed while Snowflake user mapping fails.

For key-pair troubleshooting, the client username must match the Snowflake user's LOGIN_NAME.

---

# Part 8 — SSO Rollout

## 23. Do Not Migrate Everyone at Once

Use staged rollout: configure integration → pilot user → pilot administrator → small group → application/client validation → broader rollout.

## 24. Test Positive Login

Verify redirect, IdP authentication, MFA where required, assertion/token processing, and Snowflake session establishment.

## 25. Test Failure Scenarios

Test disabled users, incorrect identity mapping, expired sessions, MFA failure, invalid configuration, and unauthorized users.

Negative tests validate the security boundary.

---

# Part 9 — SSO Failure Domains

## 26. Identity Provider Outage

If the IdP is unavailable, federated login can fail. Plan for this dependency.

## 27. Configuration Failure

Incorrect federation configuration can cause broad authentication issues. Maintain a documented recovery procedure.

## 28. Certificate and Metadata Lifecycle

Track integration owner, metadata/certificate lifecycle, refresh/rotation procedure, testing, and rollback.

Where supported, Snowflake SAML2 integrations can use an IdP metadata URL, simplifying refresh of IdP configuration and certificate information.

---

# Part 10 — Key-Pair Authentication

## 29. Why Key-Pair Authentication?

Applications and automation should avoid long-lived reusable passwords where stronger non-interactive methods are appropriate.

Key-pair authentication uses asymmetric cryptography. The client protects the private key; Snowflake registers the corresponding public key.

## 30. Public and Private Keys

Private key:
- secret
- never shared with Snowflake
- stored securely

Public key:
- registered with Snowflake
- used to validate authentication

---

# Part 11 — Generate RSA Key Pair

## 31. Generate Encrypted PKCS#8 Private Key

A production-friendly example:

```bash
openssl genrsa 2048 | openssl pkcs8 -topk8 -v2 des3 -inform PEM -out rsa_key.p8
```

Follow organizational cryptographic and secret-management standards.

## 32. Generate Public Key

```bash
openssl rsa -in rsa_key.p8 -pubout -out rsa_key.pub
```

## 33. Protect Private Key

On Unix-like systems:

```bash
chmod 600 rsa_key.p8
```

File permissions are only one layer of secret protection.

---

# Part 12 — Register Public Key

## 34. Current Named Key-Pair Management

Snowflake supports named key pairs for users. Named key pairs provide explicit names and can support optional role restriction and expiration.

Example:

```sql
ALTER USER airflow_svc
ADD KEY PAIR airflow_prod_key
PUBLIC_KEY = '<public-key-value>'
ROLE_RESTRICTION = 'AIRFLOW_ROLE'
DAYS_TO_EXPIRY = 90
COMMENT = 'Airflow production authentication';
```

Use current Snowflake syntax and organizational expiry policy.

## 35. Legacy Public-Key Properties

Snowflake continues to support the legacy public-key slots:

```sql
ALTER USER airflow_svc
SET RSA_PUBLIC_KEY = '<public-key-value>';
```

and the secondary slot:

```sql
ALTER USER airflow_svc
SET RSA_PUBLIC_KEY_2 = '<public-key-value>';
```

Do not paste private-key material into Snowflake.

## 36. Verify Key Configuration

For legacy keys:

```sql
DESC USER airflow_svc;
```

Review RSA public-key fingerprint properties.

For named keys, use the current named-key-pair inspection command:

```sql
SHOW USER KEY PAIRS FOR USER airflow_svc;
```

---

# Part 13 — Key-Pair Connection

## 37. Client Configuration

A client typically needs account identifier, username/login name, private key, and workload context such as role and warehouse depending on the application.

## 38. Python and Other Connectors

Load private-key material securely and use the connector's supported key-pair configuration.

Do not hard-code the private key in source code.

## 39. Client Compatibility

Snowflake CLI and connector authentication capabilities evolve. Validate the exact configuration against the version of the client/driver being deployed.

---

# Part 14 — Secret Management

## 40. Never Store Private Keys in Git

Never commit private keys, passphrases, or exported secret values to application repositories.

## 41. Use a Secret Manager

Use an approved platform such as AWS Secrets Manager, Azure Key Vault, Google Secret Manager, HashiCorp Vault, or an enterprise secret-management system.

## 42. Kubernetes Pattern

A common design is secret manager → external secrets controller → Kubernetes Secret → application pod → Snowflake.

Avoid baking private keys into container images.

## 43. File Mount

When an application consumes a mounted private key, protect filesystem permissions, pod access, secret RBAC, logs, debug output, and backups.

---

# Part 15 — Key Rotation

## 44. Why Rotate Keys?

Keys can be exposed, copied, mishandled, or exceed organizational age requirements. Rotation limits long-term risk.

## 45. Named Key-Pair Rotation

For current named key pairs, Snowflake provides dedicated SQL operations to add, modify, rotate, and remove named key pairs.

Use the current ALTER USER ... ROTATE KEY PAIR workflow for named-key management.

## 46. Legacy Dual-Key Rotation

For legacy RSA_PUBLIC_KEY/RSA_PUBLIC_KEY_2 configurations, the secondary slot supports controlled migration.

A safe flow is generate new key → register secondary key → deploy new private key → test → migrate all consumers → remove old key → destroy old private key.

## 47. Do Not Replace the Only Working Key First

Always validate the replacement authentication path before retiring the currently working credential.

---

# Part 16 — Key Rotation Runbook

## 48. Pre-Rotation

Capture service user, application owner, key identity/fingerprint, secret location, workloads using the key, rotation window, and rollback plan.

## 49. Generate New Key

Generate the replacement using approved cryptographic tooling and store the private key securely.

## 50. Register Replacement

For named keys, use Snowflake's named-key rotation operations. For legacy configurations, register the secondary public key.

## 51. Deploy New Private Key

Update the application's secret-management location and restart/redeploy only as required.

## 52. Validate

Test authentication, query execution, warehouse access, database access, application health, and scheduled jobs.

## 53. Remove Old Key

Only after every consumer has migrated successfully should the old key be removed. Retire the old private key according to security policy.

---

# Part 17 — Service Account Design

## 54. Dedicated Identity

Prefer AIRFLOW_SVC, DBT_SVC, TERRAFORM_SVC, and MONITORING_SVC rather than one shared identity for unrelated workloads.

## 55. Dedicated Role

Map each service identity to a least-privilege service role. Do not use ACCOUNTADMIN for application workloads.

## 56. Dedicated Authentication

Each service should have its own authentication material. Do not reuse one private key across unrelated identities.

## 57. Environment Separation

Where appropriate, separate development, staging, and production service identities to reduce blast radius.

---

# Part 18 — Human vs Machine Authentication

## 58. Human Identity

Preferred enterprise pattern: human → enterprise IdP → MFA → SSO → Snowflake.

## 59. Machine Identity

Preferred pattern: application → dedicated service identity → key pair/OAuth/workload identity → Snowflake.

## 60. Avoid Machine MFA Workarounds

Do not design automation around interactive MFA prompts. Use supported non-interactive authentication mechanisms.

---

# Part 19 — Password Reduction

## 61. Why Reduce Password Usage?

Long-lived service passwords create risks such as shared credentials, hard-coded secrets, weak rotation, password reuse, and human knowledge of machine credentials.

## 62. Migration Strategy

Inventory password users → classify human vs machine → move humans toward approved federation/MFA → move services toward approved non-interactive authentication → validate → remove obsolete paths.

---

# Part 20 — Administrative Accounts

## 63. Administrative Users

Powerful roles such as ACCOUNTADMIN, SECURITYADMIN, USERADMIN, and SYSADMIN require strong controls.

## 64. Avoid Daily ACCOUNTADMIN Usage

Use the least privileged role required for routine work and elevate only when necessary.

## 65. Protect Administrative Authentication

Use strong authentication, controlled network paths, monitoring, and documented emergency procedures.

---

# Part 21 — Break-Glass Access

## 66. Why Break-Glass Access Exists

Identity providers and federation configurations can fail. Organizations need an approved emergency recovery strategy.

## 67. Break-Glass Requirements

Define identity, authentication method, network restrictions, credential storage, retrieval authorization, approval, monitoring, rotation, and post-use review.

## 68. Do Not Use Break-Glass Daily

Emergency credentials should not become normal operational credentials. Review every use.

---

# Part 22 — Monitoring Authentication

## 69. Login History

Monitor successful and failed logins, unexpected identities, unexpected source networks, repeated failures, and service-account anomalies.

## 70. Baseline Service Authentication

Document the expected authentication method, source, and role for each production service.

## 71. Repeated Authentication Failures

Possible causes include rotated credentials, wrong private key, wrong LOGIN_NAME, wrong account, federation/MFA issues, disabled user, network restrictions, clock skew, and client configuration.

For key-pair JWT failures, host clock synchronization matters.

---

# Part 23 — Troubleshooting MFA

## 72. MFA Login Failure

Determine whether primary/federated authentication works, MFA enrollment/policy is valid, the factor is available, the IdP is enforcing MFA, and the user is active.

## 73. Lost MFA Device

Use the organization's identity-recovery process. Do not bypass MFA informally.

---

# Part 24 — Troubleshooting SSO

## 74. SSO Troubleshooting Flow

Check redirect to IdP → IdP authentication → MFA → assertion/token generation → Snowflake acceptance → user mapping.

## 75. SSO Works for Others but Not One User

Check Snowflake user existence, LOGIN_NAME/identity mapping, IdP assignment, user status, MFA, and federation attributes.

## 76. SSO Fails for Everyone

Check IdP health, Snowflake health, security integration, metadata/certificate, issuer, SSO URL, DNS/network, and recent changes.

---

# Part 25 — Troubleshooting Key-Pair Authentication

## 77. Authentication Failure

Check correct Snowflake user/LOGIN_NAME, private key, matching registered public key, private-key format, encryption/passphrase, connector support, account identifier, key expiry/restriction, and rotation state.

## 78. Public/Private Key Mismatch

If the registered public key does not correspond to the private key used by the application, authentication fails.

## 79. Wrong Key Format

Common issues include PKCS#1 vs PKCS#8, encrypted vs unencrypted keys, PEM formatting, line breaks, secret-manager transformation, and incorrect passphrase.

## 80. Works Locally but Not in Kubernetes

Compare key material, secret value, permissions, mount path, passphrase, connector version, environment variables, Snowflake login name, account identifier, and network connectivity.

---

# Part 26 — Authentication Incident Runbook

## 81. Production Authentication Failure

1. Capture timestamp.
2. Identify user/service.
3. Identify environment.
4. Capture exact error.
5. Identify authentication method.
6. Determine scope.
7. Check user status.
8. Check Snowflake availability.
9. Check IdP availability if applicable.
10. Check network restrictions.
11. Check account identifier.
12. Check SSO/OIDC integration if applicable.
13. Check MFA if applicable.
14. Check key registration/private-key match if applicable.
15. Check secret-manager deployment.
16. Check recent key rotation.
17. Check recent user changes.
18. Check recent security-integration changes.
19. Compare with known-good identity.
20. Apply minimum correction.
21. Validate authentication.
22. Validate authorization separately.
23. Monitor recovery.
24. Document root cause.

---

# Part 27 — Credential Compromise Runbook

## 82. Suspected Credential Exposure

Detect → contain → rotate/revoke credential → review login history → review query activity → review privilege use → determine impact.

Engage the organization's security incident process.

## 83. Private Key Exposure

1. Identify affected Snowflake user.
2. Identify every consumer.
3. Register/rotate to replacement key.
4. Deploy replacement.
5. Validate workloads.
6. Remove compromised key.
7. Destroy exposed secret copies where possible.
8. Review authentication activity.
9. Review query activity.
10. Document incident.

Do not leave a compromised key active because rotation is inconvenient.

---

# Part 28 — Change Management

## 84. Authentication Changes Are Production Changes

SSO/OIDC integrations, certificates/metadata, MFA policies, user authentication, public keys, and service credentials can cause outages or security exposure.

## 85. Pre-Change Checklist

- Identity identified
- Authentication method known
- Consumers identified
- Current state captured
- New configuration validated
- Test plan ready
- Rollback ready
- Break-glass path verified
- Monitoring ready

## 86. Post-Change Checklist

- Authentication succeeds
- Required applications healthy
- Correct role used
- Old credential removed when appropriate
- Unauthorized path fails
- Monitoring clean
- Documentation updated

---

# Part 29 — Infrastructure as Code

## 87. Authentication Configuration as Code

Manage supported Snowflake authentication configuration through controlled IaC where practical for peer review, version control, repeatability, auditability, and drift detection.

## 88. Do Not Store Secrets in IaC Repositories

Configuration may be code. Private credentials are secrets. Keep them separate.

## 89. Secret References

Prefer deployment configuration that references an approved secret manager rather than embedding private-key material in source-controlled configuration.

---

# Part 30 — Hands-On Lab

## 90. Lab Objective

Practice creating a service identity, generating an RSA key pair, registering a named public key, connecting with the private key, rotating the key, validating authentication, and troubleshooting failures.

Use a non-production environment.

## 91. Create Lab Role

```sql
CREATE ROLE auth_lab_role;
```

Grant only minimum privileges required for the lab.

## 92. Create Lab User

```sql
CREATE USER auth_lab_svc
    DEFAULT_ROLE = auth_lab_role;
```

Configure the user according to current Snowflake requirements for the intended non-interactive service identity.

## 93. Generate Key Pair

```bash
openssl genrsa 2048 | openssl pkcs8 -topk8 -v2 des3 -inform PEM -out auth_lab_key.p8

openssl rsa   -in auth_lab_key.p8   -pubout   -out auth_lab_key.pub
```

## 94. Protect Private Key

```bash
chmod 600 auth_lab_key.p8
```

Never commit it to Git.

## 95. Register Named Public Key

Extract/format the public-key value as required by Snowflake.

```sql
ALTER USER auth_lab_svc
ADD KEY PAIR auth_lab_key
PUBLIC_KEY = '<public-key-value>'
ROLE_RESTRICTION = 'AUTH_LAB_ROLE'
DAYS_TO_EXPIRY = 30
COMMENT = 'Authentication lab key';
```

Never register the private key.

## 96. Verify Configuration

```sql
SHOW USER KEY PAIRS FOR USER auth_lab_svc;
```

Confirm the expected named key is registered.

## 97. Test Authentication

Use a supported Snowflake client with AUTH_LAB_SVC, the protected private key, and AUTH_LAB_ROLE.

Confirm authentication succeeds.

## 98. Negative Test

Attempt authentication with a different private key. Authentication should fail.

## 99. Generate Rotation Key

Generate a second approved key pair for the rotation exercise.

## 100. Rotate Named Key Pair

Use the current Snowflake named-key rotation command:

```sql
ALTER USER auth_lab_svc
ROTATE KEY PAIR auth_lab_key
PUBLIC_KEY = '<new-public-key-value>';
```

Validate the exact optional rotation parameters required by the environment against current Snowflake documentation.

## 101. Test New Key

Authenticate with the new private key and confirm the workload succeeds.

## 102. Inspect Key State

```sql
SHOW USER KEY PAIRS FOR USER auth_lab_svc;
```

Confirm the intended active key state and retire obsolete key material according to policy.

## 103. Cleanup

Ensure resources belong only to the lab, remove the lab user's named key pair if needed, then remove the user and role:

```sql
DROP USER IF EXISTS auth_lab_svc;
DROP ROLE IF EXISTS auth_lab_role;
```

Securely remove local lab private-key files according to organizational policy.

---

# Part 31 — Production Checklist

## 104. Human User Checklist

- SSO configured
- MFA enforced according to policy
- Identity mapping correct
- User lifecycle integrated
- Network controls considered
- Default role appropriate
- Administrative access minimized

## 105. Service User Checklist

- Dedicated service identity
- Correct user type/configuration
- Dedicated role
- Approved non-interactive authentication
- Private key/secret stored securely
- Network source controlled
- Rotation owner identified
- Rotation schedule defined
- Monitoring enabled
- Decommission process defined

## 106. Key-Pair Checklist

- Strong RSA key generated
- Private key protected
- Public key registered
- Named key pair used where appropriate
- Role restriction/expiry considered
- Private key not in Git
- Private key not in image
- Secret manager used
- Rotation tested
- Legacy dual-key method understood where still used
- Old key removed after migration

## 107. SSO Checklist

- IdP owner identified
- Security integration documented
- SAML/OIDC model understood
- User mapping validated
- MFA policy validated
- Metadata/certificate lifecycle monitored
- Pilot users tested
- Negative tests completed
- Recovery procedure documented
- Break-glass path tested

---

# Acceptance Criteria

The chapter is complete when you can:

- distinguish authentication from authorization
- classify human and machine identities
- explain MFA
- explain federated SSO
- explain SAML and OIDC federation
- understand Snowflake security integrations
- troubleshoot identity mapping
- roll out SSO safely
- monitor federation metadata/certificate lifecycle
- explain key-pair authentication
- generate RSA key pairs
- protect private keys
- register named Snowflake key pairs
- understand legacy RSA_PUBLIC_KEY/RSA_PUBLIC_KEY_2
- configure service authentication
- store private keys securely
- use secret-management systems
- understand Kubernetes secret delivery
- rotate key pairs safely
- use current named-key rotation
- understand legacy dual-key rotation
- design dedicated service identities
- separate environment identities
- reduce service-password usage
- protect administrative identities
- design break-glass authentication
- monitor login activity
- troubleshoot MFA failures
- troubleshoot SSO failures
- troubleshoot key-pair failures
- investigate private/public key mismatches
- respond to credential compromise
- manage authentication changes safely
- separate IaC configuration from secrets
- perform positive and negative authentication tests

---

## Key Takeaways

Human and machine authentication should be designed differently.

A strong human pattern is human → enterprise identity provider → MFA → federated SSO → Snowflake.

A strong machine pattern is application → dedicated service identity → key pair/OAuth/workload identity → dedicated role → Snowflake.

Never store Snowflake private keys in Git or bake them into container images. Use an approved secret-management system and maintain a documented rotation process.

Snowflake now supports named key pairs with dedicated management operations, including registration and rotation. The legacy RSA_PUBLIC_KEY and RSA_PUBLIC_KEY_2 properties remain supported for existing designs.

Authentication proves identity. RBAC controls what that identity can do. Network security controls where it can connect from. Production security requires all three.

The next chapter is **Chapter 32 — Secrets & External Access Integrations**.
