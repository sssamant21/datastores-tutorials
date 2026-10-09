# Chapter 38 --- Redis Enterprise Security, Authentication, Authorization & TLS Engineering

**Status:** Canonical\
**Track:** Redis Enterprise / Redis Software Production Engineering\
**Part:** Part 5 --- Security, Governance & Access Engineering\
**Level:** Advanced → Production Redis Security Engineering\
**Audience:** SREs, DBREs, Platform Engineers, Redis Administrators,
Security Engineers, Application Owners\
**Lab type:** Identity inventory, authentication, least-privilege
authorization, Redis ACL concepts, Redis Enterprise RBAC review, TLS
validation, certificate lifecycle, credential rotation, secret
management, network isolation, administrative access, audit review,
failure injection, troubleshooting, security runbooks, and production
acceptance

------------------------------------------------------------------------

# 1. Objective

Redis security is not one password.

A production security model includes:

``` text
identity
authentication
authorization
transport encryption
network controls
secret management
administrative access
auditability
credential/certificate lifecycle
incident response
```

A simplified trust path is:

``` text
Application identity
       |
       v
Authentication
       |
       v
Authorization
       |
       v
TLS-protected connection
       |
       v
Redis Enterprise database
```

Administrative access has a separate path:

``` text
Administrator
     |
     v
Enterprise identity / RBAC
     |
     v
Redis Enterprise control plane
```

By the end, you should be able to:

-   Separate data-plane and control-plane security.
-   Inventory Redis identities.
-   Design least-privilege access.
-   Understand Redis ACL concepts.
-   Understand Redis Enterprise RBAC concepts.
-   Protect Redis with TLS.
-   Validate certificate trust and hostname verification.
-   Plan certificate rotation.
-   Rotate credentials safely.
-   Manage application secrets.
-   Reduce network exposure.
-   Protect administrative interfaces.
-   Design break-glass access.
-   Monitor authentication/security events.
-   Troubleshoot access and TLS failures.
-   Run security failure drills.
-   Define production acceptance criteria.

------------------------------------------------------------------------

# 2. Core Production Principle

Security should answer four questions for every connection:

``` text
Who is connecting?
How is identity verified?
What is the identity allowed to do?
Is the connection protected in transit?
```

For administrators add:

``` text
Who changed the system?
What changed?
When?
Was the action authorized?
```

------------------------------------------------------------------------

# Part 1 --- Threat Model

## 3. Protect Against

Consider:

``` text
stolen credentials
overprivileged applications
unauthorized administrators
network interception
certificate expiry
secret leakage
accidental destructive commands
cross-environment access
compromised workload identity
misconfigured firewall/security group
```

------------------------------------------------------------------------

# Part 2 --- Data Plane vs. Control Plane

## 4. Data Plane

The data plane is application access to Redis data and commands.

Examples:

``` text
GET
SET
HGET
HSET
XREADGROUP
```

## 5. Control Plane

The control plane manages Redis Enterprise itself.

Examples:

``` text
database creation
user/role administration
cluster configuration
backup configuration
certificate management
```

Use separate identities and permissions where practical.

------------------------------------------------------------------------

# Part 3 --- Identity Inventory

## 6. Required Inventory

Document every Redis-accessing identity:

``` text
application/service
human administrator
automation
backup process
monitoring
CI/CD
emergency/break-glass
```

Unknown identities are a security gap.

------------------------------------------------------------------------

# Part 4 --- Shared Credentials

## 7. Avoid

Do not use one shared production credential for every application.

Shared credentials make it difficult to:

``` text
revoke one service
attribute activity
apply least privilege
rotate safely
```

------------------------------------------------------------------------

# Part 5 --- Authentication

## 8. Purpose

Authentication proves the identity attempting to connect.

Never treat network location alone as sufficient identity.

------------------------------------------------------------------------

# Part 6 --- Authorization

## 9. Purpose

Authorization controls what an authenticated identity may do.

A valid identity should not automatically receive unrestricted Redis
access.

------------------------------------------------------------------------

# Part 7 --- Least Privilege

## 10. Principle

Grant only commands and key patterns required for the workload.

Example:

``` text
cache-reader:
    read cache keys

cache-writer:
    read/write cache keys

stream-consumer:
    stream commands on approved streams

administrator:
    separate administrative privileges
```

------------------------------------------------------------------------

# Part 8 --- Redis ACL Concepts

## 11. Users

Modern Redis supports ACL concepts that can associate users with:

``` text
authentication
command permissions
key patterns
channel patterns
```

Exact syntax/capabilities depend on version and Redis Enterprise
configuration.

------------------------------------------------------------------------

# Part 9 --- ACL Discovery

## 12. Commands

Where permitted in a disposable lab:

``` redis
ACL WHOAMI
ACL LIST
```

Administrative ACL commands require appropriate privilege.

Do not expose ACL output containing sensitive authentication material.

------------------------------------------------------------------------

# Part 10 --- Command Categories

## 13. Authorization Design

Redis commands can be grouped into command categories.

Use categories carefully.

A broad category can grant more capability than the application needs.

------------------------------------------------------------------------

# Part 11 --- Dangerous Commands

## 14. Restrict

Application identities normally should not need
administrative/destructive capabilities such as:

``` text
FLUSHDB
FLUSHALL
CONFIG
ACL administration
shutdown/administrative operations
```

Exact restrictions depend on product architecture.

------------------------------------------------------------------------

# Part 12 --- Key Pattern Authorization

## 15. Namespace

Where supported, scope application access to approved key namespaces.

Example conceptual boundary:

``` text
orders-service -> orders:*
profile-service -> profile:*
```

Key naming from Chapter 29 makes authorization easier.

------------------------------------------------------------------------

# Part 13 --- Namespace Is Not Enough

## 16. Important

A naming convention by itself is not an access-control boundary.

Enforce permissions using supported authorization mechanisms.

------------------------------------------------------------------------

# Part 14 --- Pub/Sub Authorization

## 17. Channels

Applications using Pub/Sub may require channel-pattern permissions
separate from key access.

Validate the deployed Redis ACL behavior.

------------------------------------------------------------------------

# Part 15 --- Redis Enterprise RBAC

## 18. Administrative Roles

Redis Enterprise provides product-specific users, roles, and permissions
for administrative/control-plane access.

Use supported RBAC rather than giving every operator full administrative
rights.

------------------------------------------------------------------------

# Part 16 --- Role Separation

## 19. Example

Possible responsibilities:

``` text
platform administrator
database administrator
security administrator
read-only operator
application operator
auditor
```

Map actual Redis Enterprise roles/permissions according to the deployed
version.

------------------------------------------------------------------------

# Part 17 --- Human vs. Machine Identity

## 20. Separate

Do not reuse a human administrator's credential inside an application or
automation job.

Machine identities should have independent lifecycle and permissions.

------------------------------------------------------------------------

# Part 18 --- Production vs. Nonproduction

## 21. Isolation

Avoid credentials that work across:

``` text
development
staging
production
```

unless explicitly required and risk-reviewed.

Compromise of a test environment should not automatically grant
production access.

------------------------------------------------------------------------

# Part 19 --- TLS

## 22. Purpose

TLS protects data in transit and authenticates the server when
certificate validation is performed correctly.

Conceptually:

``` text
client
  |
  | encrypted TLS
  v
Redis endpoint
```

------------------------------------------------------------------------

# Part 20 --- Encryption Without Verification

## 23. Incomplete

A client that encrypts traffic but does not properly validate the server
certificate can remain vulnerable to impersonation.

Validate:

``` text
certificate chain
trusted CA
hostname/SAN
expiry
```

------------------------------------------------------------------------

# Part 21 --- Certificate Chain

## 24. Trust

A client typically validates:

``` text
server certificate
intermediate CA
trusted root CA
```

Missing trust-chain configuration can cause connection failures.

------------------------------------------------------------------------

# Part 22 --- Hostname Verification

## 25. Endpoint Identity

The hostname used by the client should match the certificate identity
according to TLS rules.

Do not solve hostname mismatch by disabling verification in production.

------------------------------------------------------------------------

# Part 23 --- Certificate Expiration

## 26. Operational Risk

An expired certificate can create a Redis outage even when the database
is healthy.

Monitor certificate expiration proactively.

------------------------------------------------------------------------

# Part 24 --- Certificate Rotation

## 27. Lifecycle

Plan:

``` text
issue new certificate
install/trust new chain
validate clients
rotate endpoint certificate
verify connections
retire old certificate
```

Avoid a rotation process that requires every client to change at the
same instant.

------------------------------------------------------------------------

# Part 25 --- CA Rotation

## 28. Overlap

Where architecture supports it, use a trust-overlap period:

``` text
clients trust old + new CA
server rotates
clients verified
old CA removed
```

Validate exact Redis Enterprise certificate procedures.

------------------------------------------------------------------------

# Part 26 --- Mutual TLS

## 29. mTLS

Where supported and required, mutual TLS can authenticate both server
and client certificates.

Do not assume mTLS is enabled merely because TLS is enabled.

------------------------------------------------------------------------

# Part 27 --- Secret Management

## 30. Do Not Hard-Code

Never store production Redis credentials directly in:

``` text
source code
Dockerfile
Git repository
public documentation
ticket
chat message
```

Use approved secret-management systems.

------------------------------------------------------------------------

# Part 28 --- Environment Variables

## 31. Caution

Environment variables are convenient but can be exposed through:

``` text
process inspection
debug output
crash dumps
misconfigured logging
```

Use the platform's supported secret-injection pattern and avoid logging
values.

------------------------------------------------------------------------

# Part 29 --- Kubernetes Secrets

## 32. Operational Model

For Kubernetes-hosted applications, Redis credentials may be delivered
through approved Secret/ExternalSecret mechanisms.

Validate:

``` text
RBAC
namespace isolation
secret-store permissions
rotation behavior
pod restart/reload behavior
```

------------------------------------------------------------------------

# Part 30 --- Cloud Secret Managers

## 33. Centralized Storage

Cloud secret-management services can provide:

``` text
access policy
encryption
rotation workflows
audit logs
```

Redis applications still need safe retrieval and reload behavior.

------------------------------------------------------------------------

# Part 31 --- Credential Rotation

## 34. Zero/Low-Downtime Goal

A safe pattern may use overlapping credentials where supported:

``` text
create new credential
deploy clients with new credential
verify adoption
revoke old credential
```

Do not revoke the old credential before clients are ready.

------------------------------------------------------------------------

# Part 32 --- Rotation Evidence

## 35. Track

Record:

``` text
credential owner
creation date
last rotation
next rotation
applications using it
revocation procedure
```

------------------------------------------------------------------------

# Part 33 --- Secret Leakage

## 36. Incident

If a credential is exposed:

``` text
treat it as compromised
```

Do not merely delete the message/file and continue using the secret.

Rotate/revoke according to incident policy.

------------------------------------------------------------------------

# Part 34 --- Network Security

## 37. Reduce Exposure

Restrict Redis endpoints to required networks/workloads.

Avoid unnecessary public exposure.

------------------------------------------------------------------------

# Part 35 --- Firewall / Security Group

## 38. Allow Only Required Sources

Document:

``` text
source workload/network
destination Redis endpoint
port
protocol
business purpose
```

------------------------------------------------------------------------

# Part 36 --- Kubernetes Network Policy

## 39. Workload Isolation

Where applicable, network policy can restrict which namespaces/pods can
reach Redis.

Test policy behavior before relying on it.

------------------------------------------------------------------------

# Part 37 --- Private Connectivity

## 40. Preferred Where Required

Use supported private network paths when architecture/security policy
requires them.

Still use authentication and TLS.

Private networking does not replace identity.

------------------------------------------------------------------------

# Part 38 --- Administrative Interface

## 41. Higher Privilege

Redis Enterprise administrative APIs/UI deserve stronger protection than
application data endpoints.

Apply:

``` text
restricted network access
strong identity
RBAC
auditability
MFA/SSO where supported and configured
```

according to product and organizational controls.

------------------------------------------------------------------------

# Part 39 --- Automation Credentials

## 42. CI/CD

Automation that modifies Redis Enterprise should have only the
permissions needed for its workflow.

Do not use a full cluster-admin credential for routine database
deployment if narrower access is supported.

------------------------------------------------------------------------

# Part 40 --- Break-Glass Access

## 43. Emergency Identity

Break-glass access should be:

``` text
rare
protected
audited
tested
revocable
```

It should not become the everyday administrator account.

------------------------------------------------------------------------

# Part 41 --- Auditability

## 44. Questions

You should be able to investigate:

``` text
who authenticated
who changed configuration
who changed access
who performed administrative operations
when the action occurred
```

Use Redis Enterprise and surrounding platform audit capabilities
available in your environment.

------------------------------------------------------------------------

# Part 42 --- Application Logging

## 45. Never Log Secrets

Do not log:

``` text
Redis password
authentication token
private key
full connection string containing credentials
```

Sanitize errors and configuration dumps.

------------------------------------------------------------------------

# Part 43 --- Connection Strings

## 46. Sensitive

A URI can contain credentials:

``` text
rediss://user:password@host:port
```

Treat it as a secret if credentials are embedded.

Prefer configuration patterns that avoid accidental URI logging.

------------------------------------------------------------------------

# Part 44 --- TLS Client Example

## 47. Python

Conceptual redis-py configuration:

``` python
import os
import redis

r = redis.Redis(
    host=os.environ["REDIS_HOST"],
    port=int(os.getenv("REDIS_PORT", "6379")),
    username=os.getenv("REDIS_USERNAME"),
    password=os.getenv("REDIS_PASSWORD"),
    ssl=True,
    ssl_ca_certs=os.environ["REDIS_CA_CERT"],
    decode_responses=True,
    socket_connect_timeout=2,
    socket_timeout=2,
)

print(r.ping())
```

Use exact client/version parameters supported in your environment.

------------------------------------------------------------------------

# Part 45 --- Verification Must Stay Enabled

## 48. Anti-Pattern

Do not "fix" certificate errors with production settings equivalent to:

``` text
verify = false
```

Find and correct:

``` text
CA trust
hostname
certificate chain
expiry
```

------------------------------------------------------------------------

# Part 46 --- Authentication Failure

## 49. Common Causes

``` text
wrong username
wrong password
expired/rotated secret
disabled user
wrong database/endpoint
client using old secret
```

------------------------------------------------------------------------

# Part 47 --- Authorization Failure

## 50. Different From Authentication

A user may authenticate successfully but receive an error because a
command/key/channel is not permitted.

Troubleshoot identity and permission separately.

------------------------------------------------------------------------

# Part 48 --- TLS Failure

## 51. Common Causes

``` text
expired certificate
hostname mismatch
unknown CA
missing intermediate
wrong port
TLS disabled on one side
protocol/cipher incompatibility
client clock problems
```

------------------------------------------------------------------------

# Part 49 --- Certificate Inspection

## 52. OpenSSL

From an approved diagnostic host:

``` bash
openssl s_client \
  -connect redis.example.internal:6379 \
  -servername redis.example.internal \
  -showcerts
```

Do not paste private keys into diagnostic commands.

Inspect:

``` text
subject
issuer
SAN
validity
verification result
```

------------------------------------------------------------------------

# Part 50 --- Expiration Check

## 53. Example

``` bash
openssl s_client \
  -connect redis.example.internal:6379 \
  -servername redis.example.internal \
  </dev/null 2>/dev/null \
  | openssl x509 -noout -dates -subject -issuer
```

Adjust endpoint/port for the environment.

------------------------------------------------------------------------

# Part 51 --- Secret Rotation and Pools

## 54. Existing Connections

Connection pools can keep authenticated connections alive while new
connections use updated credentials.

Rotation testing must include:

``` text
existing connections
new connections
pod/process restart
connection pool recycle
```

------------------------------------------------------------------------

# Part 52 --- Rotation Rollback

## 55. Plan

Before revoking the old credential, know how to revert clients if the
new credential fails.

------------------------------------------------------------------------

# Part 53 --- Certificate Rotation and Pools

## 56. Reconnection

Long-lived connections may not immediately exercise the new certificate.

Force controlled reconnects in a test environment to validate the new
trust chain.

------------------------------------------------------------------------

# Part 54 --- ACL Change Risk

## 57. Production Outage

Removing a command or key permission can break an application
immediately.

Test permission changes against actual application command inventory.

------------------------------------------------------------------------

# Part 55 --- Command Inventory

## 58. Build

Record:

``` text
service
identity
key patterns
Redis types
commands
Pub/Sub channels
admin operations
```

Use this to design least privilege.

------------------------------------------------------------------------

# Part 56 --- Permission Drift

## 59. Detect

Compare intended policy with actual configuration periodically.

Watch for:

``` text
new broad permissions
unused users
old credentials
unexpected administrators
cross-environment access
```

------------------------------------------------------------------------

# Part 57 --- Dormant Accounts

## 60. Remove

Disable/revoke identities no longer required.

Do not keep old accounts indefinitely "just in case."

------------------------------------------------------------------------

# Part 58 --- Ownership

## 61. Every Identity Needs an Owner

Record:

``` text
identity
owner
purpose
environment
permissions
rotation
expiration
```

Orphaned credentials are operational risk.

------------------------------------------------------------------------

# Part 59 --- Monitoring

## 62. Authentication Metrics

Where available, monitor:

``` text
authentication failures
connection failures
unexpected source networks
disabled-user attempts
```

------------------------------------------------------------------------

## 63. Authorization Metrics

Monitor or log repeated denied commands/access attempts where supported.

Distinguish:

``` text
application misconfiguration
security event
```

------------------------------------------------------------------------

## 64. TLS Metrics

Track:

``` text
certificate expiration
TLS handshake failures
certificate verification failures
```

------------------------------------------------------------------------

## 65. Administrative Changes

Monitor important control-plane changes:

``` text
users
roles
database configuration
certificates
network/security settings
backup configuration
```

according to available audit capabilities.

------------------------------------------------------------------------

# Part 60 --- Alerting

## 66. Examples

Alert on:

``` text
certificate nearing expiration
sudden authentication-failure spike
unexpected privileged user creation
backup/security configuration change
repeated administrative login failure
security monitoring pipeline failure
```

Tune to avoid alert fatigue.

------------------------------------------------------------------------

# Part 61 --- Hands-On Lab

## 67. Safety

Use a disposable Redis/Redis Enterprise lab.

Do not modify production ACLs, certificates, users, or network rules for
training.

------------------------------------------------------------------------

# Part 62 --- Baseline Identity

## 68. Discover

Where permitted:

``` redis
ACL WHOAMI
```

Record the lab identity.

------------------------------------------------------------------------

# Part 63 --- Lab Namespace

## 69. Create

``` redis
SET tutorial:chapter38:allowed:key value
SET tutorial:chapter38:other:key value
```

------------------------------------------------------------------------

# Part 64 --- Least-Privilege User Lab

## 70. Concept

Using the supported Redis/Redis Enterprise administrative workflow,
create a disposable user allowed only the commands and key namespace
required for the lab.

Target policy concept:

``` text
allow GET/SET
allow tutorial:chapter38:allowed:*
deny unrelated keys
deny administrative commands
```

Use syntax appropriate to the installed version/product.

------------------------------------------------------------------------

# Part 65 --- Positive Test

## 71. Expected

Authenticate as the limited user and verify permitted operations:

``` redis
SET tutorial:chapter38:allowed:test 1
GET tutorial:chapter38:allowed:test
```

------------------------------------------------------------------------

# Part 66 --- Negative Key Test

## 72. Expected Denial

Attempt an unauthorized key:

``` redis
GET tutorial:chapter38:other:key
```

The operation should be denied according to the lab policy.

------------------------------------------------------------------------

# Part 67 --- Negative Command Test

## 73. Expected Denial

Attempt a command not required by the application.

Do not use a destructive command merely to prove denial.

Choose a safe administrative/read-only command that the limited identity
should not possess.

------------------------------------------------------------------------

# Part 68 --- TLS Validation Lab

## 74. Verify

Connect with:

``` text
TLS enabled
CA validation enabled
hostname verification enabled
```

Confirm successful connection.

------------------------------------------------------------------------

# Part 69 --- Wrong CA Test

## 75. Expected Failure

Use an intentionally incorrect lab CA bundle.

Connection should fail certificate validation.

This proves the client is not silently trusting any server.

------------------------------------------------------------------------

# Part 70 --- Wrong Hostname Test

## 76. Expected Failure

Where safe and practical, connect using a hostname not covered by the
lab certificate.

Verification should fail.

------------------------------------------------------------------------

# Part 71 --- Credential Rotation Lab

## 77. Procedure

In the disposable environment:

1.  identify current credential;
2.  create/enable replacement credential where supported;
3.  update one test client;
4.  verify new connections;
5.  migrate remaining test clients;
6.  revoke old credential;
7.  verify old credential fails;
8.  verify new credential succeeds.

------------------------------------------------------------------------

# Part 72 --- Connection Pool Rotation Lab

## 78. Validate

Test:

``` text
existing pooled connection
new pooled connection
process restart
old credential revoked
```

Ensure the application does not depend indefinitely on old authenticated
sockets.

------------------------------------------------------------------------

# Part 73 --- Certificate Rotation Lab

## 79. Procedure

Using the supported lab workflow:

1.  inventory current certificate;
2.  prepare new certificate/trust;
3.  update clients if CA changes;
4.  rotate endpoint certificate;
5.  reconnect clients;
6.  verify certificate identity;
7.  verify application operations;
8.  retire old trust only after validation.

------------------------------------------------------------------------

# Part 74 --- Secret Leak Drill

## 80. Simulate

Mark a disposable credential as "exposed."

Execute:

``` text
identify consumers
issue replacement
deploy replacement
revoke exposed credential
validate
document timeline
```

Do not use real production credentials.

------------------------------------------------------------------------

# Part 75 --- Network Denial Lab

## 81. Disposable Environment

Block one test workload from Redis using the supported network-control
mechanism.

Verify:

``` text
blocked workload cannot connect
approved workload still connects
monitoring detects expected failure
```

------------------------------------------------------------------------

# Part 76 --- Failure Injection

## 82. Failure 1 --- Wrong Password

Verify authentication failure is clear and does not expose the secret in
logs.

## 83. Failure 2 --- Disabled User

Disable a disposable user and verify new access fails.

## 84. Failure 3 --- Missing Key Permission

Remove access to a lab key namespace and verify authorization failure.

## 85. Failure 4 --- Missing Command Permission

Remove one required safe command and observe application failure mode.

## 86. Failure 5 --- Wrong CA

Verify TLS trust failure.

## 87. Failure 6 --- Hostname Mismatch

Verify hostname validation failure.

## 88. Failure 7 --- Certificate Expiry Scenario

Use a controlled test certificate or simulated expiration alert to
validate monitoring/runbook response.

## 89. Failure 8 --- Credential Rotation With Old Client

Leave one test client on the old credential, revoke it, and verify
monitoring identifies the failure.

## 90. Failure 9 --- Network Rule Denial

Block the test client at the network layer and distinguish it from
authentication failure.

## 91. Failure 10 --- Exposed Credential

Run the disposable credential-compromise rotation procedure and measure
revocation time.

------------------------------------------------------------------------

# Part 77 --- Troubleshooting

## 92. Cannot Connect

Separate layers:

``` text
DNS
network
port
TLS
authentication
authorization
Redis health
```

Do not rotate credentials before proving authentication is the failing
layer.

------------------------------------------------------------------------

## 93. `NOAUTH` / Authentication Error

Check:

``` text
username
password source
secret version
endpoint
user enabled state
application reload
```

------------------------------------------------------------------------

## 94. Permission Denied

Check:

``` text
authenticated identity
command
key pattern
channel pattern
role/ACL policy
recent access changes
```

------------------------------------------------------------------------

## 95. TLS Handshake Failure

Check:

``` text
TLS endpoint/port
CA trust
certificate chain
hostname
expiry
client/server protocol compatibility
system clock
```

------------------------------------------------------------------------

## 96. Works on One Pod but Not Another

Compare:

``` text
secret version
mounted secret
environment
CA bundle
DNS
network policy
application version
connection pool state
```

------------------------------------------------------------------------

## 97. Rotation Broke Application

Check:

``` text
which clients migrated
old credential revocation time
connection pools
secret reload
deployment rollout
rollback credential availability
```

------------------------------------------------------------------------

## 98. Certificate Rotation Broke Clients

Check:

``` text
new certificate SAN
new issuer
client trust bundle
intermediate certificates
long-lived connections
endpoint
```

------------------------------------------------------------------------

## 99. Unexpected Privileged Access

Treat as a security issue.

Capture evidence before changing state where incident policy requires
it, then revoke/restrict access through the approved response process.

------------------------------------------------------------------------

# Part 78 --- Production Runbooks

## 100. Runbook --- Authentication Failure Spike

``` text
1. Confirm affected applications.
2. Identify failing identity.
3. Check recent secret/user changes.
4. Check secret-store availability.
5. Check application secret version.
6. Avoid exposing credentials in logs.
7. Restore correct identity/secret.
8. Verify new connections.
9. Monitor failure rate.
10. Review whether activity was malicious.
```

------------------------------------------------------------------------

## 101. Runbook --- Credential Compromise

``` text
1. Declare security incident as required.
2. Identify compromised identity.
3. Identify all consumers.
4. Create/enable replacement credential.
5. Deploy replacement safely.
6. Revoke compromised credential.
7. Validate legitimate clients.
8. Review audit/network evidence.
9. Remove leaked copies.
10. Document root cause and prevention.
```

------------------------------------------------------------------------

## 102. Runbook --- Certificate Expiration / Rotation

``` text
1. Confirm affected certificate.
2. Check expiration and SANs.
3. Prepare approved replacement.
4. Validate trust chain.
5. Update client trust if required.
6. Rotate through supported procedure.
7. Force controlled reconnect tests.
8. Validate application traffic.
9. Retire old certificate/trust safely.
10. Update expiration monitoring.
```

------------------------------------------------------------------------

## 103. Runbook --- Authorization Regression

``` text
1. Identify affected identity.
2. Capture denied command/key.
3. Compare intended policy.
4. Check recent ACL/RBAC changes.
5. Restore minimum required permission.
6. Validate application flow.
7. Confirm no broad privilege was added.
8. Test negative access.
9. Update command inventory.
10. Record change evidence.
```

------------------------------------------------------------------------

## 104. Runbook --- Suspected Unauthorized Access

``` text
1. Follow security incident process.
2. Preserve relevant evidence.
3. Identify source identity/network.
4. Determine commands/actions performed.
5. Contain/revoke access.
6. Rotate affected credentials.
7. Validate Redis data/configuration.
8. Review backup/recovery need.
9. Monitor for continued attempts.
10. Complete security remediation.
```

------------------------------------------------------------------------

# Part 79 --- Security Design Template

## 105. Fields

``` text
Database:
Environment:
Owner:
Data classification:
Application identities:
Human identities:
Automation identities:
Authentication method:
Authorization model:
Allowed key patterns:
Allowed commands:
Pub/Sub channels:
Administrative roles:
TLS required:
CA:
Certificate owner:
Certificate expiration:
Rotation process:
Secret store:
Credential rotation:
Network sources:
Redis endpoint exposure:
Audit source:
Break-glass identity:
Last access review:
Last rotation test:
Last TLS test:
Runbook:
```

------------------------------------------------------------------------

# Part 80 --- Identity Inventory Template

## 106. Table

  ------------------------------------------------------------------------------------------------
  Identity           Type         Owner      Environment   Purpose          Privilege   Rotation
  ------------------ ------------ ---------- ------------- ---------------- ----------- ----------
  `orders-api`       Machine      Orders     Prod          Cache access     Limited     Defined
                                  team                                                  

  `redis-operator`   Human/role   Platform   Prod          Administration   Elevated    SSO/RBAC

  `backup-job`       Machine      Platform   Prod          Backup           Limited     Defined
  ------------------------------------------------------------------------------------------------

Replace examples with real identities.

------------------------------------------------------------------------

# Part 81 --- Access Review

## 107. Questions

For every identity:

``` text
Is it still used?
Does it have an owner?
Are permissions still required?
Can permissions be reduced?
Is rotation current?
Does it cross environments?
```

------------------------------------------------------------------------

# Part 82 --- TLS Review

## 108. Questions

``` text
Is TLS mandatory?
Do clients validate the CA?
Is hostname verification enabled?
When does the certificate expire?
Who owns rotation?
Has rotation been tested?
Are old trust anchors removed?
```

------------------------------------------------------------------------

# Part 83 --- Secret Review

## 109. Questions

``` text
Where is the secret stored?
Who can read it?
How is it injected?
Can it appear in logs?
How is it rotated?
How quickly can it be revoked?
```

------------------------------------------------------------------------

# Part 84 --- Network Review

## 110. Questions

``` text
Is Redis publicly reachable?
Which workloads can connect?
Are firewall/security-group rules minimal?
Are Kubernetes policies present where required?
Are admin endpoints more restricted?
```

------------------------------------------------------------------------

# Part 85 --- Production Acceptance Checklist

## 111. Security Engineering

-   [ ] Data classification documented.
-   [ ] Data-plane identities inventoried.
-   [ ] Control-plane identities inventoried.
-   [ ] Every identity has an owner.
-   [ ] Shared credentials minimized.
-   [ ] Production/nonproduction credentials separated.
-   [ ] Human/machine credentials separated.
-   [ ] Least privilege implemented.
-   [ ] Application command inventory completed.
-   [ ] Key-pattern access reviewed.
-   [ ] Pub/Sub channel access reviewed where applicable.
-   [ ] Administrative/destructive commands restricted.
-   [ ] Redis Enterprise RBAC reviewed.
-   [ ] Dormant users removed.
-   [ ] TLS required where policy requires.
-   [ ] CA validation enabled.
-   [ ] Hostname verification enabled.
-   [ ] Certificate expiration monitored.
-   [ ] Certificate rotation tested.
-   [ ] Credential rotation tested.
-   [ ] Connection-pool rotation behavior tested.
-   [ ] Secrets stored in approved system.
-   [ ] Secrets excluded from source control.
-   [ ] Secrets excluded from logs.
-   [ ] Network exposure minimized.
-   [ ] Administrative endpoint restricted.
-   [ ] Break-glass process documented.
-   [ ] Audit/security telemetry reviewed.
-   [ ] Authentication failures monitored.
-   [ ] Security runbooks validated.
-   [ ] Access review scheduled.

------------------------------------------------------------------------

# Knowledge Validation

## 112. Questions

1.  What is the difference between authentication and authorization?
2.  What is the Redis data plane?
3.  What is the Redis Enterprise control plane?
4.  Why should application and administrator identities be separate?
5.  Why are shared credentials risky?
6.  What does least privilege mean for Redis?
7.  Why are key naming conventions useful for authorization?
8.  Why is a namespace not itself a security boundary?
9.  What do Redis ACLs control?
10. Why should destructive/admin commands be restricted?
11. What is Redis Enterprise RBAC used for?
12. What does TLS protect?
13. Why is encryption without certificate verification insufficient?
14. What is hostname verification?
15. Why is certificate expiration an availability risk?
16. Why is CA rotation often performed with trust overlap?
17. What is mTLS?
18. Why should Redis credentials not be hard-coded?
19. Why can environment variables still expose secrets?
20. Why must credential rotation include connection-pool behavior?
21. What should happen after a secret leak?
22. Why does private networking not replace authentication?
23. Why should administrative interfaces be more restricted?
24. What is break-glass access?
25. Why must logs exclude connection credentials?
26. How do you distinguish network, TLS, authentication, and
    authorization failures?
27. Why should ACL changes be tested against command inventory?
28. Why should unused identities be removed?
29. Which security events should be monitored?
30. What must pass before Redis security is production-ready?

------------------------------------------------------------------------

# Hands-On Acceptance Checklist

## 113. Lab Completion

-   [ ] Identified current lab identity.
-   [ ] Created Chapter 38 namespace.
-   [ ] Created disposable least-privilege identity.
-   [ ] Verified allowed operation.
-   [ ] Verified unauthorized key denial.
-   [ ] Verified unauthorized command denial.
-   [ ] Connected with validated TLS.
-   [ ] Tested wrong CA.
-   [ ] Tested hostname mismatch.
-   [ ] Rotated disposable credential.
-   [ ] Verified old credential revocation.
-   [ ] Tested connection-pool behavior.
-   [ ] Rotated lab certificate/trust where supported.
-   [ ] Ran secret-leak drill.
-   [ ] Tested network denial.
-   [ ] Completed ten failure scenarios.
-   [ ] Completed troubleshooting.
-   [ ] Reviewed five security runbooks.
-   [ ] Completed identity inventory.
-   [ ] Completed TLS review.
-   [ ] Completed secret review.
-   [ ] Completed network review.
-   [ ] Completed production acceptance checklist.

------------------------------------------------------------------------

# 114. Lab Cleanup

Delete only Chapter 38 lab keys:

``` bash
redis-cli --scan --pattern 'tutorial:chapter38:*'
```

Review matches, then remove confirmed keys in bounded batches:

``` redis
UNLINK <confirmed-key>
```

Remove only disposable lab users/roles/certificates/network rules
created for the exercise.

Do not remove shared or production identities.

Do not use:

``` redis
KEYS tutorial:chapter38:*
FLUSHDB
FLUSHALL
```

against a shared or production database.

Confirm the lab environment has returned to its intended security
baseline.

------------------------------------------------------------------------

# 115. Key Takeaways

1.  Redis security requires identity, authentication, authorization,
    TLS, network controls, secrets, auditability, and lifecycle
    management.
2.  Data-plane and control-plane access should be treated separately.
3.  Every Redis identity should have an owner and purpose.
4.  Shared credentials weaken revocation, attribution, and least
    privilege.
5.  Human and machine identities should not be reused interchangeably.
6.  Production and nonproduction credentials should be isolated.
7.  Redis ACL concepts support command/key/channel restrictions.
8.  Redis Enterprise RBAC should limit administrative access.
9.  Application identities normally should not receive destructive
    administrative commands.
10. Key namespaces help authorization design but are not security
    boundaries by themselves.
11. TLS protects data in transit only when trust validation is correctly
    configured.
12. Hostname verification should remain enabled.
13. Certificate expiration is both a security and availability risk.
14. Certificate and CA rotation must be tested before emergency expiry.
15. Production secrets should never be committed to source code.
16. Secret rotation must include long-lived connections and connection
    pools.
17. Exposed credentials should be treated as compromised and revoked.
18. Private networking reduces exposure but does not replace
    authentication.
19. Administrative interfaces deserve stronger network and identity
    controls.
20. Break-glass access should be exceptional, protected, audited, and
    tested.
21. Logs and diagnostics must not expose credentials.
22. Troubleshooting should isolate network, TLS, authentication,
    authorization, and Redis health layers.
23. Permission changes can cause outages and should be tested against
    real command inventories.
24. Security monitoring should cover authentication, TLS, privileged
    access, and configuration changes.
25. Production readiness requires tested least privilege, rotation, TLS
    verification, network isolation, monitoring, and incident runbooks.

------------------------------------------------------------------------

# 116. References

Validate security behavior against the exact Redis Enterprise, Redis,
client, Kubernetes/cloud, and organizational security versions/policies
in use.

Recommended official documentation areas:

-   Redis security
-   Redis ACLs
-   Redis ACL command/key/channel permissions
-   Redis TLS
-   Redis Enterprise access control
-   Redis Enterprise role-based access control
-   Redis Enterprise users and roles
-   Redis Enterprise TLS and certificates
-   Redis Enterprise certificate management
-   Redis Enterprise security configuration
-   Redis Enterprise audit/security logging
-   Redis Enterprise networking
-   Redis Enterprise Kubernetes security
-   Redis client TLS configuration
-   Organization-approved secret-management documentation

------------------------------------------------------------------------

# Next Chapter

**Chapter 39 --- Redis Enterprise Observability, Metrics, Alerting & SLO
Engineering**

Chapter 39 will cover:

-   observability architecture
-   database metrics
-   node metrics
-   shard metrics
-   latency
-   throughput
-   memory
-   eviction
-   replication
-   persistence
-   connections
-   hot-key indicators
-   Prometheus/Grafana integration
-   alert design
-   SLI/SLO definitions
-   saturation
-   dashboards
-   incident correlation
-   failure injection
-   troubleshooting
-   production monitoring runbooks
-   acceptance validation
