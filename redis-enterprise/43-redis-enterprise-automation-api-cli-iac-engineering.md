# Chapter 43 --- Redis Enterprise Automation, APIs, CLI & Infrastructure-as-Code Engineering

**Status:** Canonical\
**Track:** Redis Enterprise / Redis Software Production Engineering\
**Part:** Part 6 --- Observability, Reliability & Production Operations\
**Level:** Advanced → Production Automation & Platform Engineering\
**Audience:** SREs, DBREs, Platform Engineers, Redis Administrators,
DevOps Engineers, Developers\
**Lab type:** API discovery, CLI workflows, authentication, secret
handling, idempotent database lifecycle automation, RBAC workflows,
backup automation, Terraform/IaC patterns, Kubernetes automation, CI/CD
gates, drift detection, failure injection, troubleshooting, runbooks,
and production acceptance

------------------------------------------------------------------------

# 1. Objective

Production Redis automation should convert repeatable operational
procedures into controlled, observable, auditable workflows.

The goal is not:

``` text
automate every command
```

The goal is:

``` text
desired state
    |
    v
validate
    |
    v
plan
    |
    v
approve
    |
    v
apply
    |
    v
verify
    |
    v
record evidence
```

By the end, you should be able to:

-   decide what should and should not be automated;
-   discover Redis Enterprise APIs safely;
-   use CLI workflows without embedding credentials;
-   design idempotent automation;
-   automate database lifecycle operations;
-   automate configuration validation;
-   automate RBAC workflows carefully;
-   automate backup verification;
-   integrate monitoring;
-   design Terraform/IaC workflows;
-   automate Redis Enterprise on Kubernetes;
-   protect secrets;
-   detect configuration drift;
-   build CI/CD safety gates;
-   handle partial failures;
-   troubleshoot automation;
-   create production automation runbooks.

------------------------------------------------------------------------

# 2. Core Production Principle

Automation should reduce operational risk.

Bad automation makes mistakes:

``` text
faster
more consistently
at larger scale
```

Good automation includes:

``` text
validation
idempotency
least privilege
approval
bounded scope
health gates
audit evidence
recovery
```

------------------------------------------------------------------------

# Part 1 --- Automation Candidates

## 3. Good Candidates

Examples:

``` text
inventory collection
health checks
database provisioning
configuration validation
backup verification
monitoring registration
certificate-expiry checks
capacity reporting
drift detection
```

------------------------------------------------------------------------

# Part 2 --- High-Risk Automation

## 4. Extra Controls

Examples:

``` text
database deletion
large-scale configuration change
upgrade
failover
restore
credential rotation
Active-Active topology change
```

These require stronger approval and validation.

------------------------------------------------------------------------

# Part 3 --- Do Not Automate Ambiguity

## 5. Principle

If an operator must make a complex judgment from incomplete evidence, do
not hide that decision inside an unconditional script.

Automation can collect evidence and stop for approval.

------------------------------------------------------------------------

# Part 4 --- API Discovery

## 6. Version Matters

Redis Enterprise API endpoints, schemas, authentication methods, and
capabilities can vary by product/version.

Always use the API documentation for the exact deployed version.

------------------------------------------------------------------------

# Part 5 --- API Base

## 7. Pattern

A generic conceptual API call is:

``` bash
curl --fail-with-body \
  --silent \
  --show-error \
  --request GET \
  "https://${REDIS_ENTERPRISE_HOST}:${API_PORT}/<supported-endpoint>"
```

Add only the authentication method documented for your deployed version.

------------------------------------------------------------------------

# Part 6 --- Do Not Hard-Code Credentials

## 8. Avoid

``` bash
curl -u admin:MyPassword ...
```

inside:

``` text
Git
shell history
CI logs
tickets
documentation
```

------------------------------------------------------------------------

# Part 7 --- Environment Variables

## 9. Better Lab Pattern

``` bash
export REDIS_ENTERPRISE_HOST="redis.example.internal"
export REDIS_ENTERPRISE_USER="automation-user"
```

Retrieve secrets from an approved secret manager at runtime.

------------------------------------------------------------------------

# Part 8 --- TLS Validation

## 10. Never Normalize Insecure TLS

Do not make this the production standard:

``` bash
curl -k ...
```

Use trusted CA material and validate the endpoint identity.

------------------------------------------------------------------------

# Part 9 --- API Error Handling

## 11. Check More Than HTTP 200

Automation should detect:

``` text
HTTP status
response body
schema
operation status
asynchronous task state
```

------------------------------------------------------------------------

# Part 10 --- Timeouts

## 12. Bound Calls

Example:

``` bash
curl \
  --connect-timeout 5 \
  --max-time 30 \
  ...
```

Choose timeouts appropriate to the endpoint.

------------------------------------------------------------------------

# Part 11 --- Retries

## 13. Safe Retries

Retry only when semantics are understood.

Use:

``` text
bounded attempts
backoff
jitter
idempotency
```

Do not blindly retry destructive requests.

------------------------------------------------------------------------

# Part 12 --- Idempotency

## 14. Definition

An idempotent workflow converges toward desired state.

Conceptually:

``` text
read current state
compare desired state
change only differences
verify
```

------------------------------------------------------------------------

# Part 13 --- Create-or-Update

## 15. Pattern

Do not blindly:

``` text
CREATE database
```

on every run.

Use:

``` text
does database exist?
    |
    +-- no --> create
    |
    +-- yes --> compare configuration
                    |
                    +-- same --> no-op
                    |
                    +-- different --> approved update
```

------------------------------------------------------------------------

# Part 14 --- Stable Identity

## 16. Prefer IDs

Names can change.

Where APIs expose stable identifiers, persist and use them
appropriately.

Never invent object IDs.

------------------------------------------------------------------------

# Part 15 --- Desired State

## 17. Example

``` yaml
database:
  name: application-cache
  memory: 20GB
  replication: true
  persistence: disabled
  owner: application-team
```

The exact schema belongs to your automation layer, not Redis itself.

------------------------------------------------------------------------

# Part 16 --- Validation Before Apply

## 18. Check

``` text
required fields
allowed ranges
naming policy
capacity
security policy
environment
change authorization
```

------------------------------------------------------------------------

# Part 17 --- Plan

## 19. Human-Readable Diff

Before production mutation, produce:

``` text
current:
desired:
difference:
impact:
```

------------------------------------------------------------------------

# Part 18 --- Approval

## 20. Production

High-risk changes should require an approved workflow.

Examples:

``` text
pull request
change ticket
deployment approval
manual gate
```

------------------------------------------------------------------------

# Part 19 --- Apply

## 21. Small Scope

Prefer one logical change per execution.

Avoid combining:

``` text
database resize
ACL change
certificate rotation
backup change
```

unless the change requires it.

------------------------------------------------------------------------

# Part 20 --- Verify

## 22. Mandatory

After mutation:

``` text
read object again
confirm desired state
confirm health
run application smoke test where relevant
```

------------------------------------------------------------------------

# Part 21 --- Audit

## 23. Record

``` text
who/identity
what
when
environment
desired state
previous state
result
change reference
```

Never log secrets.

------------------------------------------------------------------------

# Part 22 --- CLI Automation

## 24. Use Cases

CLI tools can be useful for:

``` text
operator workflows
diagnostics
CI jobs
local administration
```

but scripts should still validate versions and output.

------------------------------------------------------------------------

# Part 23 --- Exit Codes

## 25. Required

Automation must fail on command failure.

Shell example:

``` bash
set -euo pipefail
```

Understand its behavior before using it in complex scripts.

------------------------------------------------------------------------

# Part 24 --- Parse Structured Output

## 26. Prefer

``` text
JSON
machine-readable fields
stable schemas
```

over scraping human-formatted tables.

------------------------------------------------------------------------

# Part 25 --- Database Provisioning

## 27. Workflow

``` text
validate request
check capacity
check name
check existing object
create
wait for healthy state
configure monitoring
run smoke test
record ID/evidence
```

------------------------------------------------------------------------

# Part 26 --- Database Deletion

## 28. High Risk

Before deletion verify:

``` text
correct environment
correct database ID
owner approval
dependency check
backup/retention policy
explicit confirmation
```

------------------------------------------------------------------------

# Part 27 --- Two-Key Delete Guard

## 29. Example

Require both:

``` text
database ID
expected database name
```

to match before deletion.

This reduces wrong-target risk.

------------------------------------------------------------------------

# Part 28 --- Environment Guard

## 30. Prevent Cross-Environment Mistakes

Example policy:

``` text
production job may target only production allowlist
staging job may target only staging allowlist
```

------------------------------------------------------------------------

# Part 29 --- RBAC Automation

## 31. Principle

Automate least privilege, not broad administrative access.

Model:

``` text
identity
role
scope
expiry where applicable
owner
```

------------------------------------------------------------------------

# Part 30 --- Access Review

## 32. Drift

Regularly compare:

``` text
approved identities
actual identities
approved roles
actual roles
```

------------------------------------------------------------------------

# Part 31 --- Secret Rotation

## 33. Workflow

A safe rotation often requires:

``` text
create/new secret
distribute
validate clients
switch
revoke old
verify
```

Exact sequence depends on authentication model.

------------------------------------------------------------------------

# Part 32 --- Certificate Automation

## 34. Monitor

Automate:

``` text
expiry inventory
warning thresholds
renewal workflow
deployment validation
```

Do not rotate certificates without client trust validation.

------------------------------------------------------------------------

# Part 33 --- Backup Automation

## 35. More Than Triggering

A backup automation should verify:

``` text
job started
job completed
artifact exists
age acceptable
size plausible
retention applied
```

------------------------------------------------------------------------

# Part 34 --- Restore Validation Automation

## 36. Stronger Control

Periodically:

``` text
select backup
restore into isolation
validate data
run smoke tests
record RTO
clean up
```

where organizational policy allows.

------------------------------------------------------------------------

# Part 35 --- Monitoring Automation

## 37. Provision With Database

When a database is created, automation can also create:

``` text
dashboard registration
alerts
ownership metadata
capacity tracking
backup monitoring
```

------------------------------------------------------------------------

# Part 36 --- Alert Validation

## 38. Test

A provisioned alert is not complete until delivery is validated.

------------------------------------------------------------------------

# Part 37 --- Inventory Automation

## 39. Collect

Periodically record:

``` text
cluster
nodes
databases
memory limits
replication
persistence
backup
owners
versions
```

------------------------------------------------------------------------

# Part 38 --- Drift Detection

## 40. Definition

Drift is:

``` text
actual state != approved desired state
```

------------------------------------------------------------------------

# Part 39 --- Drift Categories

## 41. Examples

``` text
memory changed
replication changed
persistence changed
ACL changed
backup changed
alert removed
owner missing
```

------------------------------------------------------------------------

# Part 40 --- Do Not Auto-Remediate Everything

## 42. Risk

Some drift may be an emergency manual change.

A safer workflow:

``` text
detect
classify
notify
approve
remediate
```

------------------------------------------------------------------------

# Part 41 --- Terraform / IaC

## 43. Principle

IaC provides:

``` text
review
version control
repeatability
plan
state
```

Use the supported Redis provider/API integration appropriate to the
deployed platform.

------------------------------------------------------------------------

# Part 42 --- Terraform State

## 44. Sensitive

Terraform state can contain sensitive configuration.

Protect:

``` text
backend
encryption
access
locking
retention
```

------------------------------------------------------------------------

# Part 43 --- Plan Before Apply

## 45. Production Pattern

``` text
terraform fmt/check
validate
plan
review
approve
apply saved plan
verify
```

Exact commands depend on implementation.

------------------------------------------------------------------------

# Part 44 --- Destructive Plan

## 46. Block

CI should flag or block unexpected:

``` text
destroy
replace
recreate
```

for production Redis resources.

------------------------------------------------------------------------

# Part 45 --- Lifecycle Controls

## 47. Use Carefully

IaC lifecycle protection can help prevent accidental deletion, but
should not replace approvals and backups.

------------------------------------------------------------------------

# Part 46 --- Imports

## 48. Existing Resources

When adopting existing Redis resources into IaC:

``` text
inventory
backup
import
plan
review drift
```

Do not immediately apply an unreviewed plan.

------------------------------------------------------------------------

# Part 47 --- State Drift

## 49. Causes

``` text
manual change
failed apply
provider change
out-of-band emergency fix
```

Reconcile intentionally.

------------------------------------------------------------------------

# Part 48 --- CI/CD Pipeline

## 50. Suggested Flow

``` text
lint
  |
validate
  |
security/policy checks
  |
plan
  |
human review
  |
approval
  |
apply
  |
health validation
  |
evidence
```

------------------------------------------------------------------------

# Part 49 --- Policy Gates

## 51. Examples

Block:

``` text
production database deletion
replication removal
backup disablement
memory reduction below safe threshold
public exposure
unapproved admin role
```

------------------------------------------------------------------------

# Part 50 --- Capacity Gate

## 52. Before Provisioning

Validate requested capacity against:

``` text
available memory
CPU headroom
shard placement
failure headroom
quota
```

------------------------------------------------------------------------

# Part 51 --- Naming Policy

## 53. Example

A database naming standard might encode:

``` text
application
environment
purpose
```

Keep names human-readable.

------------------------------------------------------------------------

# Part 52 --- Metadata

## 54. Track

Where supported or in external inventory:

``` text
owner
service
environment
cost center
criticality
data classification
```

------------------------------------------------------------------------

# Part 53 --- Kubernetes Automation

## 55. GitOps

For Redis Enterprise on Kubernetes, desired state may be stored as
manifests/CRs.

Validate exact operator and CRD versions.

------------------------------------------------------------------------

# Part 54 --- Operator Compatibility

## 56. Gate

Before changing manifests:

``` text
Kubernetes version
operator version
Redis Enterprise version
CRD schema
```

must be compatible.

------------------------------------------------------------------------

# Part 55 --- Kubernetes Secrets

## 57. Avoid Plaintext Git

Use approved secret-management integration.

Do not commit production credentials into manifests.

------------------------------------------------------------------------

# Part 56 --- Admission Policy

## 58. Guardrails

Policy engines can reject configurations that violate:

``` text
resource requirements
security
storage
network
labels
```

------------------------------------------------------------------------

# Part 57 --- GitOps Drift

## 59. Understand Controller Behavior

A controller may automatically revert manual changes.

During incidents, know whether reconciliation must be paused through the
approved mechanism.

------------------------------------------------------------------------

# Part 58 --- Reconciliation Loop

## 60. Principle

Automation should converge carefully:

``` text
observe
compare
act
verify
sleep
repeat
```

Avoid tight failure loops.

------------------------------------------------------------------------

# Part 59 --- Rate Limits

## 61. API Protection

Respect documented API limits and platform capacity.

Do not poll aggressively.

------------------------------------------------------------------------

# Part 60 --- Async Operations

## 62. Wait Correctly

Some operations may return before completion.

Automation must:

``` text
capture task/object
poll boundedly
check terminal status
timeout
report failure
```

according to documented API behavior.

------------------------------------------------------------------------

# Part 61 --- Partial Failure

## 63. Example

``` text
database created
monitoring creation failed
```

The workflow should report:

``` text
PARTIAL
```

not success.

------------------------------------------------------------------------

# Part 62 --- Compensation

## 64. Caution

Do not automatically delete a successfully created production database
because a later dashboard step failed.

Compensating actions must be risk-aware.

------------------------------------------------------------------------

# Part 63 --- Checkpoints

## 65. Long Workflows

Persist:

``` text
completed step
object IDs
task IDs
validation state
```

so recovery does not repeat unsafe operations.

------------------------------------------------------------------------

# Part 64 --- Locking

## 66. Prevent Concurrent Changes

Two automation runs should not race to modify the same production
resource.

Use an appropriate locking/concurrency mechanism.

------------------------------------------------------------------------

# Part 65 --- Change Queue

## 67. Serialize Where Needed

For sensitive resources:

``` text
one mutation workflow at a time
```

may be safer than parallel changes.

------------------------------------------------------------------------

# Part 66 --- Dry Run

## 68. Useful

Support:

``` text
validate only
plan only
read-only audit
```

modes.

------------------------------------------------------------------------

# Part 67 --- Production Allowlist

## 69. Safety

Production automation can require explicit:

``` text
cluster ID
environment
database ID
```

allowlisting.

------------------------------------------------------------------------

# Part 68 --- Break Glass

## 70. Emergency

Define a controlled manual path when automation is unavailable.

Break-glass access must be:

``` text
limited
audited
time-bound where possible
reviewed afterward
```

------------------------------------------------------------------------

# Part 69 --- API Credential Scope

## 71. Least Privilege

A read-only inventory job should not use a credential capable of
deleting databases.

------------------------------------------------------------------------

# Part 70 --- Credential Rotation

## 72. Automation Identity

Rotate automation credentials without creating an outage.

Test new identity before revoking old access.

------------------------------------------------------------------------

# Part 71 --- Logging Secrets

## 73. Redact

Never log:

``` text
password
token
private key
authorization header
full connection URI containing secret
```

------------------------------------------------------------------------

# Part 72 --- CI Secret Masking

## 74. Verify

Do not assume masking is perfect.

Avoid echoing secrets at all.

------------------------------------------------------------------------

# Part 73 --- Dependency Pinning

## 75. Automation Runtime

Pin/test:

``` text
provider version
client library
CLI version
container image
Python packages
```

Upgrade automation dependencies deliberately.

------------------------------------------------------------------------

# Part 74 --- API Schema Change

## 76. Regression

A product upgrade can change automation assumptions.

Test automation against target Redis Enterprise versions before
upgrading production.

------------------------------------------------------------------------

# Part 75 --- Test Pyramid

## 77. Layers

``` text
unit tests
schema tests
mock/API tests
nonproduction integration
failure tests
production smoke validation
```

------------------------------------------------------------------------

# Part 76 --- Contract Tests

## 78. Validate

Confirm expected API response fields/types for supported versions.

Fail clearly when schema is unexpected.

------------------------------------------------------------------------

# Part 77 --- Smoke Tests

## 79. After Provisioning

Example:

``` text
connect
authenticate
SET test key
GET test key
TTL
delete test key
```

Use isolated keys.

------------------------------------------------------------------------

# Part 78 --- Health Gates

## 80. Before Next Mutation

Check:

``` text
database healthy
replication healthy
resource headroom
application SLO
```

------------------------------------------------------------------------

# Part 79 --- Observability

## 81. Automation Metrics

Track:

``` text
runs
success
failure
partial
duration
retries
API errors
drift findings
```

------------------------------------------------------------------------

# Part 80 --- Automation SLO

## 82. Example

For a provisioning service:

``` text
successful requests / valid requests
```

with latency and failure objectives appropriate to the platform.

------------------------------------------------------------------------

# Part 81 --- Alerting

## 83. Alert On

``` text
repeated failures
stuck task
backup verification failure
unexpected drift
credential expiry
certificate expiry
```

------------------------------------------------------------------------

# Part 82 --- Hands-On Lab

## 84. Safety

Use a disposable Redis Enterprise or approved nonproduction environment.

Do not run destructive automation against production while learning.

------------------------------------------------------------------------

# Part 83 --- Lab Configuration

## 85. Environment

``` bash
export REDIS_ENTERPRISE_HOST="lab.example.internal"
export REDIS_ENTERPRISE_USER="chapter43-lab"
export REDIS_ENTERPRISE_ENV="lab"
```

Retrieve the secret from the lab secret manager.

------------------------------------------------------------------------

# Part 84 --- Read-Only API Lab

## 86. Goal

Using the exact documented endpoint for your deployed version:

``` text
authenticate
list cluster/database inventory
parse structured response
handle non-2xx status
```

Do not copy an endpoint from another product version without validation.

------------------------------------------------------------------------

# Part 85 --- Python API Skeleton

## 87. Pattern

``` python
import os
import requests

base = os.environ["REDIS_ENTERPRISE_API_BASE"]
token = os.environ["REDIS_ENTERPRISE_API_TOKEN"]

session = requests.Session()
session.headers.update({
    "Authorization": f"Bearer {token}",
    "Accept": "application/json",
})

response = session.get(
    f"{base}/<documented-read-only-endpoint>",
    timeout=(5, 30),
)

response.raise_for_status()
data = response.json()

print(type(data).__name__)
```

The authentication header is illustrative only. Use the authentication
mechanism documented for the deployed Redis Enterprise version.

------------------------------------------------------------------------

# Part 86 --- Idempotency Lab

## 88. Desired State

Create a lab specification:

``` yaml
name: chapter43-lab
environment: lab
memory: <lab-value>
replication: <lab-setting>
```

Write automation that:

``` text
reads current
compares
prints plan
changes only differences
verifies
```

------------------------------------------------------------------------

# Part 87 --- Dry-Run Lab

## 89. Output

Expected:

``` text
DRY RUN
Resource: chapter43-lab
Current: ...
Desired: ...
Actions: ...
No changes applied.
```

------------------------------------------------------------------------

# Part 88 --- Wrong-Environment Guard

## 90. Inject

Set:

``` text
expected = lab
actual = production
```

The automation must exit before mutation.

------------------------------------------------------------------------

# Part 89 --- Delete Guard Lab

## 91. Require

``` text
expected database name
expected database ID
explicit destructive approval
```

Inject a mismatch and verify deletion is blocked.

------------------------------------------------------------------------

# Part 90 --- Secret Redaction Lab

## 92. Verify

Run automation with a fake secret.

Confirm the secret does not appear in:

``` text
stdout
stderr
CI artifact
debug log
exception
```

------------------------------------------------------------------------

# Part 91 --- Retry Lab

## 93. Temporary Failure

Inject transient HTTP failures.

Verify:

``` text
bounded retries
backoff
jitter
terminal failure
```

No infinite loop.

------------------------------------------------------------------------

# Part 92 --- Partial Failure Lab

## 94. Scenario

Simulate:

``` text
resource creation = success
monitoring registration = failure
```

Expected result:

``` text
PARTIAL
resource retained
follow-up action identified
```

------------------------------------------------------------------------

# Part 93 --- Drift Lab

## 95. Scenario

Change one lab property outside the desired-state workflow.

Run drift detection.

Expected:

``` text
resource
property
expected
actual
severity
```

------------------------------------------------------------------------

# Part 94 --- CI Gate Lab

## 96. Policy

Create a test plan containing a destructive production change.

Verify CI blocks it before apply.

------------------------------------------------------------------------

# Part 95 --- Backup Verification Lab

## 97. Validate

Using supported lab APIs/workflows, verify:

``` text
last backup status
backup age
artifact existence
```

Do not expose storage credentials.

------------------------------------------------------------------------

# Part 96 --- Smoke Validation Lab

## 98. Python

``` python
import os
import redis
import uuid

r = redis.Redis(
    host=os.environ["REDIS_HOST"],
    port=int(os.getenv("REDIS_PORT", "6379")),
    username=os.getenv("REDIS_USERNAME"),
    password=os.getenv("REDIS_PASSWORD"),
    ssl=os.getenv("REDIS_SSL", "false").lower() == "true",
    decode_responses=True,
)

key = f"tutorial:chapter43:smoke:{uuid.uuid4().hex}"

r.set(key, "ok", ex=120)

assert r.get(key) == "ok"
assert r.ttl(key) > 0

r.unlink(key)

print("PASS: Chapter 43 Redis smoke validation")
```

------------------------------------------------------------------------

# Part 97 --- Failure Injection

## 99. Failure 1 --- Expired Credential

Verify authentication failure is explicit and no mutation occurs.

## 100. Failure 2 --- TLS Validation Failure

Verify automation fails closed rather than disabling certificate
validation.

## 101. Failure 3 --- Wrong Environment

Verify environment guard blocks mutation.

## 102. Failure 4 --- API Timeout

Verify bounded timeout/retry behavior.

## 103. Failure 5 --- Unexpected Schema

Verify contract validation stops safely.

## 104. Failure 6 --- Concurrent Change

Run two lab mutations and verify locking/concurrency protection.

## 105. Failure 7 --- Partial Workflow

Fail a downstream monitoring step and verify PARTIAL status.

## 106. Failure 8 --- Destructive Plan

Verify policy gate blocks unexpected deletion/replacement.

## 107. Failure 9 --- Drift

Inject manual change and verify detection.

## 108. Failure 10 --- Verification Failure

Make the post-change smoke test fail and verify the workflow is not
reported as successful.

------------------------------------------------------------------------

# Part 98 --- Troubleshooting

## 109. Authentication Failure

Check:

``` text
identity
secret/token
expiry
role
scope
authentication method
```

Do not print the credential.

------------------------------------------------------------------------

## 110. TLS Failure

Check:

``` text
hostname
certificate expiry
CA chain
client trust
system time
```

Do not solve by permanently disabling TLS validation.

------------------------------------------------------------------------

## 111. HTTP 4xx

Likely areas:

``` text
bad request
permission
wrong endpoint
unsupported operation
version mismatch
```

Read the documented error schema.

------------------------------------------------------------------------

## 112. HTTP 5xx

Check:

``` text
Redis Enterprise service health
request correlation
logs
resource pressure
temporary condition
```

Retry only if the operation is safe to retry.

------------------------------------------------------------------------

## 113. Automation Hangs

Check:

``` text
missing timeout
async task
poll loop
lock
network
API dependency
```

------------------------------------------------------------------------

## 114. Duplicate Resource

The workflow may not be idempotent or may be using the wrong stable
identity.

------------------------------------------------------------------------

## 115. Terraform Wants Replacement

Stop and review:

``` text
provider schema
immutable property
state drift
import/state
configuration change
```

Do not blindly approve production replacement.

------------------------------------------------------------------------

## 116. Drift Keeps Returning

Check:

``` text
manual operator
another controller
GitOps reconciliation
automation race
incorrect desired state
```

------------------------------------------------------------------------

## 117. CI Says Success but Resource Is Unhealthy

The pipeline lacks post-apply health validation.

Add verification gates.

------------------------------------------------------------------------

# Part 99 --- Production Runbooks

## 118. Runbook --- Automation Authentication Failure

``` text
1. Confirm affected automation identity.
2. Confirm environment/endpoint.
3. Check credential expiry.
4. Check role/scope.
5. Check secret-manager retrieval.
6. Check TLS separately.
7. Rotate/fix credential using approved process.
8. Test read-only call.
9. Resume workflow safely.
10. Record cause and prevention.
```

------------------------------------------------------------------------

## 119. Runbook --- Failed IaC Apply

``` text
1. Stop additional applies.
2. Preserve plan/logs.
3. Determine actual resource state.
4. Determine state-file state.
5. Check partial mutations.
6. Run read-only health checks.
7. Reconcile/import/repair using supported procedure.
8. Generate a new plan.
9. Review before apply.
10. Verify health and drift.
```

------------------------------------------------------------------------

## 120. Runbook --- Unexpected Destructive Plan

``` text
1. Do not apply.
2. Identify resources marked destroy/replace.
3. Check configuration change.
4. Check provider version.
5. Check state/import.
6. Check immutable properties.
7. Reconcile desired state.
8. Generate new plan.
9. Obtain review/approval.
10. Apply only when destruction is explicitly intended.
```

------------------------------------------------------------------------

## 121. Runbook --- Drift Detected

``` text
1. Identify resource/property.
2. Confirm actual state.
3. Find change owner/source.
4. Determine emergency/manual context.
5. Assess user/reliability impact.
6. Decide desired state.
7. Approve remediation.
8. Apply controlled correction.
9. Verify.
10. Record drift cause.
```

------------------------------------------------------------------------

## 122. Runbook --- Automation Partial Failure

``` text
1. Stop automatic continuation.
2. Identify completed steps.
3. Identify failed step.
4. Preserve object/task IDs.
5. Validate Redis health.
6. Avoid destructive compensation by default.
7. Resume from safe checkpoint.
8. Complete missing integration.
9. Run end-to-end validation.
10. Record PARTIAL-to-SUCCESS evidence.
```

------------------------------------------------------------------------

# Part 100 --- Automation Design Template

## 123. Header

``` text
Workflow:
Owner:
Environment:
Redis objects:
Trigger:
Risk:
```

## 124. Identity

``` text
Automation identity:
Role:
Scope:
Credential source:
Rotation:
```

## 125. Safety

``` text
Dry run:
Environment guard:
Allowlist:
Approval:
Locking:
Timeout:
Retry:
Destructive guard:
```

## 126. Validation

``` text
Prechecks:
Postchecks:
Application smoke:
Health gate:
Rollback/recovery:
```

------------------------------------------------------------------------

# Part 101 --- Desired-State Template

## 127. Example

``` yaml
resource:
  type: redis-database
  name: example
  environment: staging
  owner: team-a

desired:
  memory: <approved-value>
  replication: true
  persistence: <approved-policy>

controls:
  destructive_change: false
  approval_required: true
  smoke_test: true
```

Adapt to the actual automation framework.

------------------------------------------------------------------------

# Part 102 --- Drift Record

## 128. Template

  Resource   Property   Desired   Actual   Severity   Action
  ---------- ---------- --------- -------- ---------- --------
                                                      

------------------------------------------------------------------------

# Part 103 --- CI/CD Checklist

## 129. Pipeline

-   [ ] Syntax/lint passed.
-   [ ] Schema validation passed.
-   [ ] Unit tests passed.
-   [ ] Contract tests passed.
-   [ ] Security scan passed.
-   [ ] Secret scan passed.
-   [ ] Environment guard passed.
-   [ ] Capacity check passed.
-   [ ] Plan generated.
-   [ ] Destructive-change policy passed.
-   [ ] Human review completed.
-   [ ] Production approval completed.
-   [ ] Apply used reviewed artifact/plan.
-   [ ] Redis health passed.
-   [ ] Application smoke passed.
-   [ ] Evidence retained.

------------------------------------------------------------------------

# Part 104 --- Production Acceptance Checklist

## 130. Automation Engineering

-   [ ] Automation ownership defined.
-   [ ] Supported APIs documented by product version.
-   [ ] API/CLI dependencies pinned/tested.
-   [ ] Automation identities use least privilege.
-   [ ] Secrets are retrieved securely.
-   [ ] TLS validation enforced.
-   [ ] Timeouts defined.
-   [ ] Retries bounded.
-   [ ] Idempotency implemented.
-   [ ] Stable resource identity used.
-   [ ] Dry-run/plan mode available.
-   [ ] Environment guards implemented.
-   [ ] Production allowlists implemented where appropriate.
-   [ ] Destructive changes protected.
-   [ ] Concurrent mutations controlled.
-   [ ] Partial failure explicitly represented.
-   [ ] Checkpoint/recovery behavior implemented.
-   [ ] Post-change verification required.
-   [ ] Application smoke tests implemented.
-   [ ] Audit evidence retained.
-   [ ] Sensitive values redacted.
-   [ ] Database lifecycle automation tested.
-   [ ] RBAC automation reviewed.
-   [ ] Backup verification automated.
-   [ ] Monitoring registration automated where useful.
-   [ ] Drift detection implemented.
-   [ ] IaC state protected.
-   [ ] Destructive IaC plans blocked/reviewed.
-   [ ] Kubernetes/GitOps compatibility validated where applicable.
-   [ ] Automation metrics/alerts available.
-   [ ] Five production runbooks validated.
-   [ ] Ten failure scenarios tested.

------------------------------------------------------------------------

# Knowledge Validation

## 131. Questions

1.  What is the purpose of production automation?
2.  Why can bad automation increase risk?
3.  Which operations need stronger controls?
4.  Why must APIs be validated against the deployed version?
5.  Why should credentials never be embedded in Git or commands?
6.  Why is disabling TLS validation unsafe?
7.  Why do API calls need bounded timeouts?
8.  What makes a workflow idempotent?
9.  Why should current state be read before mutation?
10. What is a human-readable plan?
11. Why should production changes have approval gates?
12. Why is post-change verification mandatory?
13. Why should structured output be parsed instead of tables?
14. What guards should protect database deletion?
15. Why should RBAC automation use least privilege?
16. What should backup automation verify beyond job start?
17. What is configuration drift?
18. Why should drift not always be auto-remediated?
19. Why is Terraform state sensitive?
20. Why should destructive IaC plans be blocked?
21. Why should existing resources be imported carefully?
22. What can cause state drift?
23. Why are Kubernetes operator/version compatibility gates important?
24. What is a partial automation failure?
25. Why can automatic compensation be dangerous?
26. Why are checkpoints useful?
27. Why must concurrent changes be controlled?
28. What should automation observability measure?
29. Why should product upgrades trigger automation regression tests?
30. What must pass before Redis automation is production-ready?

------------------------------------------------------------------------

# Hands-On Acceptance Checklist

## 132. Lab Completion

-   [ ] Configured lab environment safely.
-   [ ] Performed read-only API discovery.
-   [ ] Parsed structured response.
-   [ ] Implemented bounded timeout.
-   [ ] Implemented idempotent desired-state comparison.
-   [ ] Generated dry-run output.
-   [ ] Tested wrong-environment guard.
-   [ ] Tested destructive delete guard.
-   [ ] Verified secret redaction.
-   [ ] Tested bounded retries.
-   [ ] Tested partial failure.
-   [ ] Detected configuration drift.
-   [ ] Tested CI destructive-change gate.
-   [ ] Verified backup status/age.
-   [ ] Ran Redis smoke validation.
-   [ ] Tested expired credential.
-   [ ] Tested TLS validation failure.
-   [ ] Tested API timeout.
-   [ ] Tested unexpected schema.
-   [ ] Tested concurrent mutation protection.
-   [ ] Tested verification failure.
-   [ ] Reviewed five production runbooks.
-   [ ] Completed automation design template.
-   [ ] Completed desired-state template.
-   [ ] Completed drift record.
-   [ ] Completed CI/CD checklist.
-   [ ] Completed production acceptance checklist.

------------------------------------------------------------------------

# 133. Lab Cleanup

Discover any Redis keys created by the Chapter 43 smoke tests:

``` bash
redis-cli --scan --pattern 'tutorial:chapter43:*'
```

Review matches and delete only confirmed lab keys:

``` redis
UNLINK <confirmed-key>
```

Remove only disposable lab:

``` text
automation identities
API credentials/tokens
test databases
test backups
CI jobs
temporary policies
Terraform state/resources
Kubernetes test resources
```

according to lab and retention policy.

Do not delete shared resources.

Do not use:

``` redis
KEYS tutorial:chapter43:*
FLUSHDB
FLUSHALL
```

against a shared or production database.

------------------------------------------------------------------------

# 134. Key Takeaways

1.  Automation should reduce operational risk, not merely reduce typing.
2.  Automate repeatable decisions; expose ambiguous decisions for
    review.
3.  Redis Enterprise API behavior must be validated against the deployed
    version.
4.  Never hard-code or log production credentials.
5.  Keep TLS verification enabled and manage trust correctly.
6.  Every network/API call needs bounded failure behavior.
7.  Idempotent workflows read current state and change only what is
    necessary.
8.  Production automation should produce a readable plan before
    mutation.
9.  High-risk changes require explicit approval.
10. Every mutation requires post-change health validation.
11. Database deletion needs strong wrong-target protection.
12. Automation identities should use least privilege.
13. Backup automation must verify successful, usable recovery points.
14. Drift detection is essential when both humans and automation can
    modify Redis.
15. Do not auto-remediate unexplained drift blindly.
16. IaC state is sensitive operational data and must be protected.
17. Unexpected destroy/replace plans should stop the pipeline.
18. Existing resources should be imported and reconciled before applying
    desired state.
19. Kubernetes/GitOps controllers can compete with emergency manual
    changes.
20. Partial workflow failure must never be reported as success.
21. Long workflows need checkpoints and safe resumption.
22. Concurrent mutations should be controlled.
23. Dry-run and plan modes are core safety features.
24. Automation itself needs metrics, alerts, tests, and runbooks.
25. Production automation is ready only when failure paths are tested as
    thoroughly as the happy path.

------------------------------------------------------------------------

# 135. References

Validate all commands, API endpoints, schemas, authentication methods,
Terraform resources, and Kubernetes objects against the exact Redis
Enterprise product and version deployed.

Recommended official documentation areas:

-   Redis Enterprise REST API
-   Redis Enterprise Software administration
-   Redis Enterprise command-line tooling
-   Redis Enterprise database lifecycle
-   Redis Enterprise access control
-   Redis Enterprise security and TLS
-   Redis Enterprise backup and restore
-   Redis Enterprise monitoring
-   Redis Enterprise Active-Active
-   Redis Enterprise Kubernetes operator and CRDs
-   Supported Terraform/provider documentation for the deployed Redis
    platform
-   Redis client documentation
-   Organization CI/CD, secret-management, IaC, and change-management
    standards

------------------------------------------------------------------------

# Next Chapter

**Chapter 44 --- Redis Enterprise Security, Authentication,
Authorization & TLS Engineering**

Chapter 44 will cover:

-   security architecture
-   authentication
-   authorization
-   RBAC
-   least privilege
-   service identities
-   ACL concepts
-   TLS
-   certificates
-   trust chains
-   secret management
-   credential rotation
-   network exposure
-   audit evidence
-   security monitoring
-   break-glass access
-   failure injection
-   troubleshooting
-   security runbooks
-   production acceptance validation
