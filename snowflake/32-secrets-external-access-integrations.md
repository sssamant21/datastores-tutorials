# 32 — Secrets & External Access Integrations

## Overview

Snowflake workloads sometimes need to communicate with systems outside Snowflake.

Examples include REST APIs, SaaS platforms, internal APIs, external data services, authentication endpoints, AI/ML services, and metadata services.

A naive implementation might embed credentials directly inside Python code:

```python
api_key = "super-secret-api-key"
```

This is not an acceptable production design.

A stronger architecture separates code, network authorization, credential storage, and external access policy.

Snowflake provides several objects that work together:

```text
NETWORK RULE
     |
     v
EXTERNAL ACCESS INTEGRATION
     |
     +------ SECRET
     |
     v
UDF / Stored Procedure
     |
     v
External Service
```

This chapter covers Snowflake secrets, network rules, external access integrations, OAuth/API credentials, Python handlers, rotation, monitoring, troubleshooting, and production runbooks.

---

# Part 1 — External Access Architecture

## 1. Why External Access Requires Controls

A Python stored procedure may need to call an external API. Arbitrary outbound network access would create significant security risk, so Snowflake uses explicit security objects to define permitted external access.

## 2. Production Architecture

A typical design combines an external endpoint, network rule, external access integration, secret, and UDF/stored procedure.

## 3. Responsibility of Each Object

- Network Rule: defines the external network destination.
- Secret: stores supported credential material.
- External Access Integration: defines which network rules and secrets a workload may use.
- UDF/Procedure: executes application logic.

---

# Part 2 — Why Secrets Should Not Be Hard-Coded

## 4. Bad Pattern

Avoid embedding bearer tokens, passwords, or API keys directly in handler code.

Problems include credential exposure in source code, Git, deployment history, logs, and difficult rotation.

## 5. Better Pattern

Use Snowflake SECRET → External Access Integration → Python Handler.

The application retrieves only the credential it is authorized to use.

---

# Part 3 — Snowflake Secrets

## 6. What Is a Secret?

A Snowflake secret is a schema-level object used to securely represent supported authentication information required by workloads.

## 7. Secret Object Scope

Secrets live inside a database and schema, for example:

```text
PLATFORM_DB.SECURITY.API_SECRET
```

## 8. Why Dedicated Security Schema?

A dedicated security schema can simplify ownership, auditing, and access management for secrets and network rules.

---

# Part 4 — Secret Types

## 9. Supported Secret Patterns

Snowflake supports secret configurations for scenarios including OAuth, username/password, generic strings, and supported cloud-provider token scenarios.

Validate current TYPE values and syntax against current Snowflake documentation when implementing.

## 10. Generic Secret

```sql
CREATE SECRET platform_db.security.vendor_api_secret
    TYPE = GENERIC_STRING
    SECRET_STRING = '<api-secret>';
```

Never place the real credential in documentation or source control.

## 11. Username/Password Secret

```sql
CREATE SECRET platform_db.security.vendor_login
    TYPE = PASSWORD
    USERNAME = '<username>'
    PASSWORD = '<password>';
```

Use only where this authentication model is required.

## 12. OAuth Secret

OAuth integrations can use a Snowflake secret associated with an appropriate API authentication security integration.

---

# Part 5 — Secret Ownership

## 13. Restrict Secret Administration

Do not allow every developer to administer production secrets. Use controlled ownership.

## 14. Runtime Access Is Different from Administration

A runtime/developer role may need permission to reference a secret without needing permission to alter or replace it.

Separate secret administration from runtime usage.

---

# Part 6 — Network Rules for External Access

## 15. Network Rule Purpose

For external access, a network rule defines which network destination Snowflake workloads may reach.

## 16. Host/Port Design

Restrict outbound access to the required endpoint and port. Prefer api.vendor.example:443 over unnecessarily broad destinations.

## 17. Example Network Rule

```sql
CREATE NETWORK RULE platform_db.security.vendor_api_rule
    MODE = EGRESS
    TYPE = HOST_PORT
    VALUE_LIST = (
        'api.vendor.example:443'
    );
```

Use the actual approved endpoint.

## 18. Multiple Endpoints

If a workload legitimately requires multiple destinations:

```sql
VALUE_LIST = (
    'api.vendor.example:443',
    'auth.vendor.example:443'
)
```

Do not add endpoints merely to make errors disappear.

---

# Part 7 — External Access Integration

## 19. What Is an External Access Integration?

An external access integration controls which external network rules and secrets can be used by Snowflake handler code.

## 20. Example Integration

```sql
CREATE EXTERNAL ACCESS INTEGRATION vendor_api_eai
    ALLOWED_NETWORK_RULES = (
        platform_db.security.vendor_api_rule
    )
    ALLOWED_AUTHENTICATION_SECRETS = (
        platform_db.security.vendor_api_secret
    )
    ENABLED = TRUE;
```

## 21. Enabled State

The integration can be enabled or disabled, providing an operational control for stopping external access through that integration.

---

# Part 8 — External Access Integration Security Model

## 22. Network Access Alone Is Not Enough

A network rule permitting an endpoint does not mean every Snowflake procedure can call it. The handler must use an authorized external access integration.

## 23. Secret Alone Is Not Enough

Creating a secret does not automatically allow a procedure to use it. It must be allowed through the external access architecture and referenced correctly.

## 24. Combined Security Boundary

Ask three questions:

- Can I reach it? → Network Rule
- Can I use this credential? → Secret
- Can this workload use both? → External Access Integration

---

# Part 9 — Python External Access

## 25. Python Procedure Architecture

A Python stored procedure can reference an external access integration and a mapped secret to call an approved external API.

## 26. Packages

A Python handler may require packages such as requests. Validate package availability and runtime versions against the Snowflake runtime environment.

## 27. Example Procedure Structure

```sql
CREATE OR REPLACE PROCEDURE call_vendor_api()
RETURNS STRING
LANGUAGE PYTHON
RUNTIME_VERSION = '<supported-version>'
PACKAGES = ('requests')
HANDLER = 'main'
EXTERNAL_ACCESS_INTEGRATIONS = (
    vendor_api_eai
)
SECRETS = (
    'api_credential' =
        platform_db.security.vendor_api_secret
)
AS
$$
...
$$;
```

Use a currently supported Snowflake Python runtime.

---

# Part 10 — Accessing Secrets from Python

## 28. Snowflake Secret API

Snowflake provides Python APIs for retrieving authorized secret values inside handler code.

## 29. Generic Secret Pattern

```python
import _snowflake

api_token = _snowflake.get_generic_secret_string(
    "api_credential"
)
```

The handler uses the mapping name from the SQL object's SECRETS clause.

## 30. Build Request

```python
headers = {
    "Authorization": f"Bearer {api_token}"
}

response = requests.get(
    "https://api.vendor.example/data",
    headers=headers,
    timeout=30
)
```

Never log api_token.

---

# Part 11 — Password Secrets

## 31. Username/Password Retrieval

```python
credential = _snowflake.get_username_password(
    "vendor_login"
)
```

Use the returned credential according to the external service's authentication protocol.

## 32. Do Not Print Credentials

Never print or return credential objects. Secrets must not appear in logs, query results, exceptions, debug traces, or monitoring output.

---

# Part 12 — OAuth

## 33. OAuth Architecture

OAuth external access commonly combines an API authentication security integration, OAuth secret, external access integration, handler, and external OAuth service.

## 34. Why OAuth?

OAuth provides token-based authorization rather than requiring a permanently reusable service password.

## 35. Token Lifecycle

Design for access-token expiration, refresh tokens, revocation, consent, and scopes.

---

# Part 13 — OAuth Token Retrieval

## 36. Handler Token Access

```python
token = _snowflake.get_oauth_access_token(
    "oauth_secret"
)
```

Validate the exact handler API against the runtime/language being used.

## 37. API Request

```python
headers = {
    "Authorization": f"Bearer {token}"
}
```

Never expose the token in logs.

---

# Part 14 — Least Privilege

## 38. Restrict Network Destinations

If the application needs api.vendor.example:443, do not permit broader destinations unless genuinely required and supported.

## 39. Restrict Secrets

An integration should expose only the secrets required by workloads using it.

## 40. Separate Integrations by Workload

Prefer workload-specific integrations such as SALESFORCE_EAI, SERVICENOW_EAI, INTERNAL_API_EAI, and ML_API_EAI rather than one global external-access integration.

---

# Part 15 — Role Design

## 41. Administrative Role

A controlled role can manage network rules, secrets, and external access integrations.

## 42. Developer Role

Developers may need USAGE on an integration, appropriate privilege on referenced secrets, and CREATE PROCEDURE/FUNCTION without secret-administration privileges.

## 43. Runtime Role

Runtime roles should receive only the privileges needed to execute the handler and access required Snowflake objects.

---

# Part 16 — Privilege Model

## 44. External Access Integration Privilege

```sql
GRANT USAGE
ON INTEGRATION vendor_api_eai
TO ROLE application_developer;
```

Validate exact privilege requirements for the operation being performed.

## 45. Secret Privilege

The role creating a UDF or procedure that references a secret requires the appropriate secret privilege. Validate current requirements before production implementation.

---

# Part 17 — Credential Rotation

## 46. Why Rotate External Credentials?

External credentials can expire, be compromised, be revoked, change ownership, or be replaced by vendor policy.

## 47. Rotation Architecture

Separating external credentials into Snowflake secrets allows credential changes without rewriting handler source code.

## 48. Rotation Flow

Generate vendor credential → update Snowflake secret → test external access → revoke old credential → monitor.

---

# Part 18 — Rotation Runbook

## 49. Pre-Rotation

Capture secret name, integration, external service, credential owner, expiration, consumers, and rollback method.

## 50. Generate Replacement

Create the replacement credential in the external system. Where possible, maintain both old and new credentials temporarily during transition.

## 51. Update Secret

Update or replace the Snowflake secret using supported secret-management commands. Never expose credentials in tickets or Git.

## 52. Validate

Validate DNS, network access, TLS, authentication, API authorization, response, and application behavior.

## 53. Revoke Old Credential

After successful validation, revoke the previous credential where a dual-credential transition is possible.

---

# Part 19 — Disabling External Access

## 54. Emergency Disable

```sql
ALTER EXTERNAL ACCESS INTEGRATION vendor_api_eai
SET ENABLED = FALSE;
```

Use current supported syntax.

## 55. When to Disable

Examples include credential compromise, unexpected outbound activity, vendor incident, security investigation, misconfigured procedure, or unauthorized endpoint access.

---

# Part 20 — Monitoring

## 56. What Should Be Monitored?

Monitor procedure/function failures, network errors, authentication failures, API response codes, latency, timeouts, unexpected usage, and credential expiration.

## 57. External Access History

Snowflake provides account-level observability for external access activity. Use the appropriate ACCOUNT_USAGE external-access telemetry available in the account.

## 58. Important Investigation Fields

Useful information can include query ID, hostname, port, bytes sent/received, integration, secret/authentication context, and timestamp depending on available telemetry.

---

# Part 21 — Troubleshooting

## 59. External API Call Fails

Check procedure execution, integration enabled state, network rule, hostname, secret authorization, credential validity, and external API health.

## 60. DNS Failure

Check hostname spelling, network rule, external DNS, vendor endpoint, and private/public endpoint requirements.

## 61. Connection Timeout

Possible causes include wrong hostname/port, vendor outage, network restriction, slow API, TLS issue, or overly short timeout.

## 62. HTTP 401

Usually indicates authentication failure. Check secret value, expiration, token, username/password, and vendor-side credential state.

## 63. HTTP 403

Usually means authentication succeeded but external authorization was denied. Check OAuth scopes, API permissions, vendor role, resource policy, and endpoint authorization.

## 64. HTTP 404

Check endpoint URL, API version, resource path, object identifier, and vendor routing.

## 65. HTTP 429

Implement vendor-appropriate backoff, bounded retry, jitter, rate control, and batching.

## 66. HTTP 5xx

The external service may be unhealthy. Use bounded retries and avoid infinite retry loops.

---

# Part 22 — Secret Troubleshooting

## 67. Secret Not Available

Check secret existence, database/schema, name, handler mapping, integration authorization, and required privilege.

## 68. Wrong Secret Mapping

SQL:

```sql
SECRETS = (
    'api_credential' = platform_db.security.api_secret
)
```

Python:

```python
_snowflake.get_generic_secret_string(
    "api_credential"
)
```

The handler uses the mapping name.

## 69. Secret Type Mismatch

Match the secret TYPE to the correct handler retrieval API.

---

# Part 23 — Network Rule Troubleshooting

## 70. Hostname Not Allowed

If the rule allows api.vendor.example:443 but code calls auth.vendor.example, the request can fail because the second hostname is outside the permitted rule.

## 71. Redirects

If an API redirects to another hostname, the redirect destination may also need authorization if the client follows it. Investigate redirects before broadening rules.

## 72. Port Mismatch

Verify that the application's actual destination port matches the network rule.

---

# Part 24 — Production Incident Runbook

## 73. External Access Failure

1. Capture timestamp.
2. Capture query ID.
3. Identify procedure/UDF.
4. Identify external access integration.
5. Identify network rule.
6. Identify secret.
7. Capture exact error.
8. Determine scope.
9. Check integration enabled state.
10. Check network-rule destination.
11. Check DNS/hostname.
12. Check port.
13. Check secret mapping.
14. Check credential validity.
15. Check OAuth token/refresh state if applicable.
16. Check external API health.
17. Check HTTP response.
18. Check recent Snowflake changes.
19. Check recent vendor changes.
20. Compare with known-good request.
21. Apply minimum correction.
22. Retest.
23. Monitor.
24. Document root cause.

---

# Part 25 — Credential Exposure Runbook

## 74. Suspected External Secret Exposure

Contain → rotate credential → update Snowflake secret → revoke old credential → review external-access activity → review vendor logs.

## 75. Do Not Wait for Confirmation

If evidence strongly suggests a production API credential has been exposed, follow organizational security incident procedures promptly.

---

# Part 26 — Change Management

## 76. External Access Changes Are Security Changes

Changes to network rules, secrets, external access integrations, endpoints, OAuth configuration, and credential scopes change the external security boundary.

## 77. Pre-Change Checklist

- Endpoint approved
- Port approved
- Network rule reviewed
- Secret owner known
- Credential scope reviewed
- Integration scope reviewed
- Consumers identified
- Test plan ready
- Rollback ready
- Monitoring ready

## 78. Post-Change Checklist

- Procedure executes
- Endpoint reachable
- Authentication succeeds
- Authorization succeeds
- Response valid
- No secret exposure
- Unexpected destinations blocked
- Monitoring clean

---

# Part 27 — Infrastructure as Code

## 79. Manage Security Objects as Code

Where supported, manage network rules, external access integrations, and grants through controlled IaC.

## 80. Secret Values Are Different

Do not put actual secret values in Git-backed Terraform configuration. Use approved secret-delivery mechanisms.

## 81. Drift Detection

Compare expected endpoints, integrations, privileges, and enabled state against actual Snowflake configuration.

---

# Part 28 — Production Design Example

## 82. Vendor API Integration

Use a clear dependency chain: Python Procedure → VENDOR_API_EAI → VENDOR_API_SECRET → api.vendor.example:443, with VENDOR_API_RULE controlling the destination.

## 83. Multiple Vendors

Prefer workload-specific integrations instead of one global integration containing Salesforce, ServiceNow, internal APIs, AI APIs, and every other endpoint.

---

# Part 29 — Hands-On Lab

## 84. Lab Objective

Build a controlled external-access path using a network rule, secret, external access integration, and Python procedure.

Use non-production Snowflake and a non-sensitive test API.

## 85. Create Security Schema

```sql
CREATE OR REPLACE DATABASE external_access_lab;

CREATE OR REPLACE SCHEMA
external_access_lab.security;
```

## 86. Create Network Rule

```sql
CREATE NETWORK RULE
external_access_lab.security.test_api_rule
    MODE = EGRESS
    TYPE = HOST_PORT
    VALUE_LIST = (
        'api.example.com:443'
    );
```

Replace the example endpoint with the approved lab endpoint.

## 87. Create Secret

```sql
CREATE SECRET
external_access_lab.security.test_api_secret
    TYPE = GENERIC_STRING
    SECRET_STRING = '<lab-api-token>';
```

Use only a non-production credential.

## 88. Create External Access Integration

```sql
CREATE EXTERNAL ACCESS INTEGRATION
test_api_eai
    ALLOWED_NETWORK_RULES = (
        external_access_lab.security.test_api_rule
    )
    ALLOWED_AUTHENTICATION_SECRETS = (
        external_access_lab.security.test_api_secret
    )
    ENABLED = TRUE;
```

## 89. Create Procedure Schema

```sql
CREATE SCHEMA
external_access_lab.application;
```

## 90. Create Python Procedure

```sql
CREATE OR REPLACE PROCEDURE
external_access_lab.application.call_test_api()
RETURNS STRING
LANGUAGE PYTHON
RUNTIME_VERSION = '<supported-python-version>'
PACKAGES = ('requests')
HANDLER = 'main'
EXTERNAL_ACCESS_INTEGRATIONS = (
    test_api_eai
)
SECRETS = (
    'api_token' =
        external_access_lab.security.test_api_secret
)
AS
$$
import requests
import _snowflake

def main(session):

    token = _snowflake.get_generic_secret_string(
        "api_token"
    )

    headers = {
        "Authorization": f"Bearer {token}"
    }

    response = requests.get(
        "https://api.example.com/test",
        headers=headers,
        timeout=30
    )

    return f"HTTP {response.status_code}"
$$;
```

Replace the endpoint with the approved lab service.

## 91. Execute Procedure

```sql
CALL external_access_lab.application.call_test_api();
```

Validate the expected response.

## 92. Negative Test — Wrong Host

Call a hostname that is not in the network rule and confirm external access is denied/fails.

## 93. Negative Test — Secret

Remove or misconfigure the authorized secret mapping in a controlled test and confirm the procedure cannot retrieve an unauthorized secret.

## 94. Disable Integration

```sql
ALTER EXTERNAL ACCESS INTEGRATION
test_api_eai
SET ENABLED = FALSE;
```

Confirm external access fails.

## 95. Re-Enable

```sql
ALTER EXTERNAL ACCESS INTEGRATION
test_api_eai
SET ENABLED = TRUE;
```

Confirm recovery.

## 96. Cleanup

Drop objects in dependency-safe order:

```sql
DROP PROCEDURE IF EXISTS
external_access_lab.application.call_test_api();

DROP EXTERNAL ACCESS INTEGRATION
IF EXISTS test_api_eai;

DROP DATABASE IF EXISTS external_access_lab;
```

Revoke any external lab credential created specifically for the exercise.

---

# Part 30 — Production Checklist

## 97. Secret Checklist

- Secret stored in Snowflake
- No credential in source code
- No credential in Git
- Correct secret type
- Owner controlled
- Runtime privilege minimal
- Rotation owner identified
- Expiration monitored

## 98. Network Rule Checklist

- MODE = EGRESS
- Correct TYPE
- Hostnames approved
- Ports approved
- No unnecessary destinations
- Redirect destinations understood
- Ownership controlled

## 99. External Access Integration Checklist

- Correct network rules
- Correct secrets
- ENABLED state expected
- USAGE grants controlled
- Workloads identified
- Integration purpose documented
- Monitoring configured

## 100. Handler Checklist

- Supported runtime
- Required packages only
- Secret mapping correct
- Secret not logged
- Timeout configured
- Retry bounded
- 429 handling implemented
- Error handling implemented
- Response validated

---

# Acceptance Criteria

The chapter is complete when you can:

- explain Snowflake external access architecture
- explain Snowflake secrets and secret types
- create generic secrets
- understand password and OAuth secrets
- protect secret administration
- create egress network rules
- restrict hostnames and ports
- create external access integrations
- understand allowed network rules and authentication secrets
- enable and disable integrations
- create Python procedures with external access
- map secrets into handler code
- retrieve generic, username/password, and OAuth secrets
- design least-privilege integrations
- separate integrations by workload
- understand runtime vs administrative privileges
- rotate external credentials
- respond to credential exposure
- monitor external access
- troubleshoot DNS/connectivity and HTTP 401/403/404/429/5xx
- troubleshoot secret mappings and network-rule mismatches
- understand redirect behavior
- manage external-access changes safely
- manage security objects through IaC
- perform positive and negative security tests
- execute an external-access incident runbook

---

## Key Takeaways

Never hard-code external credentials in Snowflake handler code.

Use SECRET + NETWORK RULE + EXTERNAL ACCESS INTEGRATION to build a controlled external-access boundary.

Think of the architecture as three questions:

- Where can this workload connect? → Network Rule
- Which credential can it use? → Secret
- Can this workload use both? → External Access Integration

Prefer narrow workload-specific network and credential access over a single global integration.

Credentials should be rotatable without rewriting application code.

Never log passwords, API keys, OAuth tokens, refresh tokens, or secret values.

When troubleshooting, identify the failing layer: procedure → integration → network rule → secret → external service.

External access should be explicitly authorized, narrowly scoped, auditable, and easy to disable during an incident.

The next chapter is **Chapter 33 — Dynamic Data Masking**.
