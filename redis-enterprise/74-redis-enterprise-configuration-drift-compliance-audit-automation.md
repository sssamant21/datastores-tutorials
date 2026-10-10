# Chapter 74 --- Redis Enterprise Configuration Drift, Compliance & Audit Automation

**Status:** Canonical\
**Track:** Redis Enterprise / Redis Software Production Engineering\
**Part:** Part 12 --- Advanced Operations, FinOps & Resilience\
**Level:** Advanced → Configuration Governance, Compliance & Automated
Control Engineering\
**Audience:** SREs, DBREs, Redis Administrators, Platform Engineers,
Kubernetes Administrators, Security Engineers, Compliance Engineers\
**Lab type:** Desired-state inventory, configuration baselines,
GitOps/IaC, drift detection, security controls, TLS/ACL compliance,
backup/DR evidence, Kubernetes and Operator governance, exceptions,
remediation, audit automation, failure scenarios, runbooks, and
production acceptance

------------------------------------------------------------------------

# 1. Objective

Production Redis Enterprise configuration changes continuously.

Changes can come from:

``` text
Git
Terraform/IaC
Kubernetes manifests
Redis Enterprise UI
REST API
CLI
automation
operators
human emergency actions
```

Without governance, the environment can slowly diverge from its approved
design.

This is configuration drift.

Drift can create:

``` text
security exposure
unexpected downtime
inconsistent environments
backup gaps
weak HA
capacity problems
failed upgrades
audit findings
```

The objective is not simply to detect differences.

The objective is to maintain a trustworthy relationship between:

``` text
approved desired state
        |
        v
deployed configuration
        |
        v
runtime behavior
        |
        v
audit evidence
```

By the end of this chapter, you should be able to:

-   define Redis Enterprise desired state;
-   build configuration baselines;
-   classify configuration by risk;
-   detect configuration drift;
-   distinguish expected from unauthorized drift;
-   use GitOps and IaC safely;
-   govern Redis Enterprise Kubernetes resources;
-   validate TLS, authentication, and authorization controls;
-   validate persistence, backup, and DR controls;
-   automate compliance evidence;
-   implement policy-as-code concepts;
-   manage approved exceptions;
-   design safe auto-remediation;
-   preserve audit trails;
-   execute drift/compliance incident runbooks;
-   complete production acceptance.

------------------------------------------------------------------------

# 2. Core Production Principle

Do not ask only:

``` text
Is the cluster healthy?
```

Also ask:

``` text
Is the cluster configured the way we approved?
```

------------------------------------------------------------------------

# Part 1 --- Desired State

## 3. Definition

Desired state is the approved configuration the platform is expected to
maintain.

Examples:

``` text
Redis version
node topology
database memory
replication
persistence
eviction
TLS
ACLs
backup policy
network policy
Kubernetes resources
```

------------------------------------------------------------------------

# Part 2 --- Runtime State

## 4. Definition

Runtime state is what actually exists now.

It may differ from desired state because of:

``` text
manual change
failed automation
partial rollout
emergency action
software behavior
configuration error
```

------------------------------------------------------------------------

# Part 3 --- Drift

## 5. Formula

Conceptually:

``` text
drift = runtime state - approved desired state
```

But not every difference is automatically bad.

------------------------------------------------------------------------

# Part 4 --- Expected Drift

## 6. Examples

Some runtime values are intentionally dynamic:

``` text
pod IP
generated IDs
timestamps
status fields
replication state
runtime counters
```

Do not alert on non-governed dynamic fields.

------------------------------------------------------------------------

# Part 5 --- Material Drift

## 7. Examples

High-value drift includes:

``` text
replication disabled
TLS disabled
backup retention changed
memory limit changed
eviction changed
ACL widened
NetworkPolicy removed
database exposed publicly
unsupported version introduced
```

------------------------------------------------------------------------

# Part 6 --- Source of Truth

## 8. Define

For every configuration object, identify authoritative source.

Example:

``` text
Kubernetes CR -> Git
cloud firewall -> Terraform
Redis database policy -> platform configuration repository
secrets -> secret manager
```

------------------------------------------------------------------------

# Part 7 --- Multiple Writers

## 9. Risk

If:

``` text
Git
UI
CLI
automation
```

all independently own the same field, drift becomes difficult to reason
about.

Prefer clear ownership.

------------------------------------------------------------------------

# Part 8 --- Configuration Ownership

## 10. Record

``` text
configuration object
owner
source of truth
change mechanism
approval
validation
rollback
```

------------------------------------------------------------------------

# Part 9 --- Baseline Categories

## 11. Build

At minimum:

``` text
cluster
database
security
network
backup
DR
observability
Kubernetes
client
```

------------------------------------------------------------------------

# Part 10 --- Cluster Baseline

## 12. Record

``` text
Redis Enterprise version
node count
node sizing
failure domains
storage
network
time synchronization
license/subscription state
```

------------------------------------------------------------------------

# Part 11 --- Database Baseline

## 13. Record

``` text
database name
memory allocation
shards
replication
persistence
eviction
TLS
endpoint
modules/capabilities
backup
```

------------------------------------------------------------------------

# Part 12 --- Security Baseline

## 14. Record

``` text
authentication
authorization
ACLs
TLS
certificate issuer
certificate expiry
secret ownership
network exposure
admin access
```

------------------------------------------------------------------------

# Part 13 --- Backup Baseline

## 15. Record

``` text
enabled
frequency
retention
repository
encryption
RPO
restore test frequency
```

------------------------------------------------------------------------

# Part 14 --- DR Baseline

## 16. Record

``` text
DR architecture
region
RPO
RTO
replication
failover method
last test
```

------------------------------------------------------------------------

# Part 15 --- Observability Baseline

## 17. Record

``` text
metrics collection
alert rules
log collection
retention
dashboards
synthetic checks
```

------------------------------------------------------------------------

# Part 16 --- Kubernetes Baseline

## 18. Record

``` text
Operator version
CRD/API versions
REC
REDB
RERC
REAADB
namespace
service account
RBAC
NetworkPolicy
StorageClass
PDB
scheduling rules
```

------------------------------------------------------------------------

# Part 17 --- Client Baseline

## 19. Record

``` text
supported client
version
TLS
timeouts
pooling
retry
backoff
jitter
DNS behavior
```

Client configuration can be part of Redis production compliance.

------------------------------------------------------------------------

# Part 18 --- Risk Classification

## 20. Example

Classify settings:

``` text
Critical
High
Medium
Low
Informational
```

------------------------------------------------------------------------

# Part 19 --- Critical Drift

## 21. Examples

``` text
TLS disabled
replication disabled
backup disabled for durable data
public exposure introduced
privileged access widened
```

Require urgent action.

------------------------------------------------------------------------

# Part 20 --- High Drift

## 22. Examples

``` text
memory allocation changed
eviction changed
backup retention reduced
unsupported version
failure-domain rule violated
```

------------------------------------------------------------------------

# Part 21 --- Medium Drift

## 23. Examples

``` text
monitoring retention changed
noncritical alert threshold changed
nonproduction sizing changed
```

------------------------------------------------------------------------

# Part 22 --- Drift Inventory

## 24. Record

``` text
object
field
desired
actual
severity
owner
detected
approved?
ticket
remediation
```

------------------------------------------------------------------------

# Part 23 --- Snapshot

## 25. Baseline Collection

Periodically capture approved non-secret configuration.

Do not dump secrets into compliance reports.

------------------------------------------------------------------------

# Part 24 --- Normalize

## 26. Important

Before comparing configuration, remove or normalize:

``` text
timestamps
generated IDs
ordering differences
status fields
ephemeral addresses
```

------------------------------------------------------------------------

# Part 25 --- Canonical Representation

## 27. Goal

Represent comparable state consistently:

``` text
sorted JSON/YAML
stable field selection
secret redaction
```

------------------------------------------------------------------------

# Part 26 --- Diff

## 28. Concept

``` text
desired.json
vs
runtime.json
```

Generate structured differences.

------------------------------------------------------------------------

# Part 27 --- Example Shell Concept

## 29. Non-Secret

For two sanitized files:

``` bash
diff -u desired.yaml runtime.yaml
```

For production automation, use structured parsers rather than text-only
comparison.

------------------------------------------------------------------------

# Part 28 --- JSON Comparison

## 30. Better

Compare semantic fields rather than formatting.

Example logic:

``` text
desired.replication == actual.replication
desired.persistence == actual.persistence
desired.tls == actual.tls
```

------------------------------------------------------------------------

# Part 29 --- GitOps

## 31. Model

``` text
Git
 |
 v
GitOps controller
 |
 v
Kubernetes CR
 |
 v
Redis Enterprise Operator
 |
 v
Redis runtime
```

There are multiple reconciliation layers.

------------------------------------------------------------------------

# Part 30 --- Nested Controllers

## 32. Ownership

A useful model:

``` text
GitOps owns declared CRs
Redis Enterprise Operator owns supported generated resources/runtime reconciliation
```

Avoid fighting controllers.

------------------------------------------------------------------------

# Part 31 --- Manual Kubernetes Edits

## 33. Risk

Editing an Operator-managed generated resource may be:

``` text
overwritten
unsupported
temporary
```

Make changes through the supported owner.

------------------------------------------------------------------------

# Part 32 --- Git Drift

## 34. Example

If a human changes a Kubernetes CR directly:

``` text
Git != cluster CR
```

GitOps may revert it.

This can be good or dangerous depending on whether the manual change was
an emergency action.

------------------------------------------------------------------------

# Part 33 --- Break-Glass

## 35. Requirement

Emergency manual changes need:

``` text
authorized operator
incident/change ID
reason
timestamp
expiry
reconciliation plan
```

------------------------------------------------------------------------

# Part 34 --- Break-Glass Reconciliation

## 36. After Incident

Choose one:

``` text
A. update desired state to approved new configuration
B. revert runtime to original desired state
```

Do not leave silent drift.

------------------------------------------------------------------------

# Part 35 --- IaC

## 37. Scope

Infrastructure as Code can govern:

``` text
cloud network
security groups/firewalls
Kubernetes infrastructure
storage
DNS
load balancers
```

depending on architecture.

------------------------------------------------------------------------

# Part 36 --- Terraform Drift

## 38. Concept

Use approved planning workflows to identify differences between IaC
state/configuration and infrastructure.

Do not automatically apply destructive changes without review.

------------------------------------------------------------------------

# Part 37 --- Plan Review

## 39. Gate

A plan should show:

``` text
create
update
destroy
replacement
```

High-risk Redis dependencies require human review.

------------------------------------------------------------------------

# Part 38 --- Policy as Code

## 40. Goal

Prevent invalid configuration before deployment.

Examples:

``` text
production databases require replication
TLS required
approved storage class required
approved namespaces only
required labels present
```

------------------------------------------------------------------------

# Part 39 --- Admission Control

## 41. Kubernetes

Policy engines/admission controls can reject noncompliant manifests
before they reach runtime.

Use organizationally approved tooling.

------------------------------------------------------------------------

# Part 40 --- Policy Safety

## 42. Warning

A broken policy can block:

``` text
deployments
emergency recovery
Operator reconciliation
```

Test policy changes carefully.

------------------------------------------------------------------------

# Part 41 --- Policy Rollout

## 43. Safer Pattern

``` text
audit mode
warning mode
enforcement
```

where supported.

------------------------------------------------------------------------

# Part 42 --- Required Labels

## 44. Governance

Examples:

``` text
owner
environment
application
criticality
cost-center
data-classification
```

------------------------------------------------------------------------

# Part 43 --- Naming Standard

## 45. Benefit

Consistent names improve:

``` text
automation
ownership
search
audit
cost allocation
```

------------------------------------------------------------------------

# Part 44 --- Environment Standard

## 46. Example

``` text
dev
test
staging
prod
dr
```

Avoid ambiguous environment names.

------------------------------------------------------------------------

# Part 45 --- Production Database Policy

## 47. Example Concept

Production database must have:

``` text
owner
replication
TLS
monitoring
backup/recovery policy if durable
capacity/SLO
approved network exposure
```

------------------------------------------------------------------------

# Part 46 --- TLS Compliance

## 48. Validate

``` text
TLS enabled where required
approved protocol
certificate valid
trusted issuer
hostname correct
expiry monitored
```

------------------------------------------------------------------------

# Part 47 --- Certificate Expiry

## 49. Automation

Alert well before expiry.

Do not discover certificate expiry through application outage.

------------------------------------------------------------------------

# Part 48 --- Certificate Inventory

## 50. Record

``` text
certificate
endpoint
issuer
not before
not after
owner
rotation method
```

------------------------------------------------------------------------

# Part 49 --- Secret Compliance

## 51. Validate

``` text
secret manager/source
rotation
access control
no plaintext Git
no plaintext documentation
```

------------------------------------------------------------------------

# Part 50 --- Secret Drift

## 52. Pattern

Application may use old credential while platform expects new one.

Rotation compliance must validate consumers.

------------------------------------------------------------------------

# Part 51 --- ACL Baseline

## 53. Principle

Permissions should match least privilege.

Track:

``` text
identity
commands
key patterns
environment
owner
expiry where temporary
```

------------------------------------------------------------------------

# Part 52 --- ACL Drift

## 54. Examples

``` text
wildcard command access added
wildcard key access added
temporary account never removed
admin privilege granted
```

------------------------------------------------------------------------

# Part 53 --- Privileged Access

## 55. Audit

Track:

``` text
who
when
what
why
result
```

according to security policy.

------------------------------------------------------------------------

# Part 54 --- Network Exposure

## 56. Baseline

Document:

``` text
private/public
allowed source ranges
ports
load balancer
NetworkPolicy
firewall
```

------------------------------------------------------------------------

# Part 55 --- Public Exposure Drift

## 57. Critical

Unexpected public exposure should be treated as critical security drift.

------------------------------------------------------------------------

# Part 56 --- NetworkPolicy Drift

## 58. Kubernetes

Detect:

``` text
policy removed
selector changed
allow widened
default-deny removed
```

------------------------------------------------------------------------

# Part 57 --- Firewall Drift

## 59. Cloud

Compare approved:

``` text
source
destination
port
direction
```

with runtime.

------------------------------------------------------------------------

# Part 58 --- Replication Compliance

## 60. Validate

For production databases requiring HA:

``` text
configured replication
healthy replica
failure-domain placement
```

Configuration alone is not enough.

------------------------------------------------------------------------

# Part 59 --- Persistence Compliance

## 61. Validate

Persistence should match data classification.

A cache and durable workflow state may require different controls.

------------------------------------------------------------------------

# Part 60 --- Backup Compliance

## 62. Validate

``` text
backup configured
last successful backup
retention
repository
encryption
restore evidence
```

------------------------------------------------------------------------

# Part 61 --- Backup Configured vs Working

## 63. Important

Compliance should not stop at:

``` text
backup.enabled = true
```

Also validate recent successful execution.

------------------------------------------------------------------------

# Part 62 --- Restore Compliance

## 64. Evidence

Record:

``` text
last restore test
dataset
result
RTO
data validation
owner
```

------------------------------------------------------------------------

# Part 63 --- RPO Compliance

## 65. Validate

Measured backup/replication behavior should meet declared RPO.

------------------------------------------------------------------------

# Part 64 --- RTO Compliance

## 66. Validate

Restore/failover exercises should demonstrate achievable RTO.

------------------------------------------------------------------------

# Part 65 --- DR Compliance

## 67. Validate

``` text
secondary environment ready
network ready
credentials ready
runbook current
last drill successful
```

------------------------------------------------------------------------

# Part 66 --- Active-Active Compliance

## 68. Validate

For Active-Active:

``` text
participating regions
connectivity
versions
certificates
replication health
capacity
application routing
```

------------------------------------------------------------------------

# Part 67 --- Version Compliance

## 69. Inventory

Track:

``` text
Redis Enterprise
Operator
Kubernetes
client SDK
capabilities/modules
```

against approved/support matrix.

------------------------------------------------------------------------

# Part 68 --- Unsupported Version

## 70. Risk

Unsupported software can create:

``` text
security
upgrade
support
compatibility
```

risk.

------------------------------------------------------------------------

# Part 69 --- Upgrade Compliance

## 71. Record

``` text
current
approved target
support end
planned date
owner
```

------------------------------------------------------------------------

# Part 70 --- Client Compliance

## 72. Validate

Approved clients should meet:

``` text
supported version
TLS
timeouts
pooling
retry/backoff/jitter
```

------------------------------------------------------------------------

# Part 71 --- Timeout Drift

## 73. Example

One application may silently change:

``` text
Redis timeout 100 ms -> 10 s
```

masking incidents and increasing request pile-up.

Client configuration governance matters.

------------------------------------------------------------------------

# Part 72 --- Capacity Compliance

## 74. Validate

``` text
memory headroom
CPU headroom
network headroom
failure capacity
growth forecast
```

------------------------------------------------------------------------

# Part 73 --- Memory Limit Drift

## 75. Risk

Increasing database memory without cluster capacity review can reduce
failure headroom.

------------------------------------------------------------------------

# Part 74 --- Eviction Policy Drift

## 76. Risk

Changing eviction policy can alter application semantics.

Treat as behavior change, not cosmetic config.

------------------------------------------------------------------------

# Part 75 --- TTL Policy Compliance

## 77. Application

Some namespaces may require TTL.

Detect unbounded key growth where policy expects expiration.

------------------------------------------------------------------------

# Part 76 --- Observability Compliance

## 78. Validate

``` text
metrics flowing
alerts enabled
logs available
synthetic probes healthy
dashboard ownership
```

------------------------------------------------------------------------

# Part 77 --- Alert Drift

## 79. Examples

``` text
alert disabled
threshold widened
notification route removed
```

------------------------------------------------------------------------

# Part 78 --- Audit Evidence

## 80. Evidence Should Answer

``` text
what control?
what resource?
what expected state?
what actual state?
when checked?
who owns it?
pass/fail?
exception?
```

------------------------------------------------------------------------

# Part 79 --- Evidence Freshness

## 81. Important

A six-month-old screenshot does not prove today's configuration.

Automate evidence where possible.

------------------------------------------------------------------------

# Part 80 --- Screenshots vs Structured Evidence

## 82. Prefer

Machine-readable evidence is generally easier to:

``` text
compare
search
retain
audit
```

Screenshots can supplement but should not be the primary control
mechanism.

------------------------------------------------------------------------

# Part 81 --- Evidence Security

## 83. Redact

Do not include:

``` text
passwords
private keys
tokens
sensitive connection strings
```

in audit artifacts.

------------------------------------------------------------------------

# Part 82 --- Audit Trail

## 84. Preserve

For significant changes:

``` text
request
approval
actor
timestamp
before
after
validation
rollback
```

------------------------------------------------------------------------

# Part 83 --- Change Correlation

## 85. Incident Use

During an incident, ask:

``` text
what changed?
```

A reliable audit trail reduces time to answer.

------------------------------------------------------------------------

# Part 84 --- Drift Detection Frequency

## 86. Risk Based

Critical controls may require near-real-time or frequent checking.

Lower-risk configuration can be checked less often.

------------------------------------------------------------------------

# Part 85 --- Event-Driven Detection

## 87. Better for Some Controls

Trigger checks after:

``` text
deployment
configuration change
secret rotation
upgrade
```

in addition to scheduled scans.

------------------------------------------------------------------------

# Part 86 --- Drift Alert

## 88. Include

``` text
resource
field
desired
actual
severity
owner
change evidence
```

------------------------------------------------------------------------

# Part 87 --- Alert Noise

## 89. Avoid

Do not alert on every harmless dynamic field.

Noise causes critical drift to be ignored.

------------------------------------------------------------------------

# Part 88 --- Drift Suppression

## 90. Controlled

Suppress only with:

``` text
reason
owner
expiry
ticket
```

------------------------------------------------------------------------

# Part 89 --- Exception Management

## 91. Required Fields

``` text
control
resource
reason
risk
compensating control
owner
approver
expiry
review date
```

------------------------------------------------------------------------

# Part 90 --- Permanent Exceptions

## 92. Avoid

Exceptions should not silently become permanent architecture.

Require periodic review.

------------------------------------------------------------------------

# Part 91 --- Expiring Exception

## 93. Automation

Alert before exception expiry.

Then:

``` text
remediate
renew with approval
```

------------------------------------------------------------------------

# Part 92 --- Compensating Control

## 94. Example

If a required control cannot temporarily be met, an approved
compensating control may reduce risk.

Document it explicitly.

------------------------------------------------------------------------

# Part 93 --- Auto-Remediation

## 95. Caution

Detection is easier than safe remediation.

Do not automatically "fix" every Redis configuration difference.

------------------------------------------------------------------------

# Part 94 --- Safe Auto-Remediation Candidates

## 96. Examples

Potential low-risk candidates:

``` text
required metadata labels
non-disruptive monitoring config
known-safe policy metadata
```

depending on environment.

------------------------------------------------------------------------

# Part 95 --- High-Risk Auto-Remediation

## 97. Avoid Blindly

Examples:

``` text
database memory reduction
replication changes
node removal
persistence change
ACL revocation
certificate replacement
```

require careful workflow.

------------------------------------------------------------------------

# Part 96 --- Remediation Gate

## 98. Require

``` text
severity
blast radius
dependency
rollback
maintenance requirement
validation
```

------------------------------------------------------------------------

# Part 97 --- Reconciliation Loop

## 99. Concept

``` text
detect
classify
approve
remediate
validate
close
```

------------------------------------------------------------------------

# Part 98 --- Drift SLO

## 100. Example

Define:

``` text
critical drift detection time
critical drift remediation time
high drift remediation time
exception review time
```

according to organizational risk.

------------------------------------------------------------------------

# Part 99 --- Compliance Score

## 101. Caution

A single percentage can hide critical failures.

Example:

``` text
99 controls pass
1 critical TLS control fails
```

"99% compliant" is misleading.

Always show severity.

------------------------------------------------------------------------

# Part 100 --- Dashboard

## 102. Views

``` text
critical drift
high drift
exceptions
expiring certificates
unsupported versions
backup failures
restore-test age
DR-test age
ownership gaps
```

------------------------------------------------------------------------

# Part 101 --- Environment Comparison

## 103. Useful

Compare:

``` text
staging
prod
DR
```

for required parity.

But intentional differences should be documented.

------------------------------------------------------------------------

# Part 102 --- Parity Drift

## 104. Example

Staging uses new client/TLS configuration while prod uses old
configuration.

This can invalidate preproduction testing.

------------------------------------------------------------------------

# Part 103 --- Golden Configuration

## 105. Pattern

Define approved templates for common service tiers.

Example:

``` text
production-cache
production-durable
nonproduction-cache
active-active-tier1
```

------------------------------------------------------------------------

# Part 104 --- Golden Manifest

## 106. Kubernetes

A template can include:

``` text
required labels
approved database settings
TLS expectation
backup references
resource policy
```

Exact CRD fields must match deployed Operator version.

------------------------------------------------------------------------

# Part 105 --- Server-Side Dry Run

## 107. Kubernetes

Where supported:

``` bash
kubectl apply --dry-run=server -f <manifest>
```

This can validate against API/admission without persisting the object.

------------------------------------------------------------------------

# Part 106 --- kubectl diff

## 108. Kubernetes

Where appropriate:

``` bash
kubectl diff -f <manifest>
```

Review proposed differences before apply.

------------------------------------------------------------------------

# Part 107 --- Schema Discovery

## 109. Before Policy

Use:

``` bash
kubectl api-resources
kubectl explain <resource>
```

against the actual cluster.

Do not write compliance logic against guessed CRD fields.

------------------------------------------------------------------------

# Part 108 --- CRD Version Drift

## 110. Risk

Operator upgrades may change:

``` text
API versions
fields
defaults
status
```

Update compliance logic accordingly.

------------------------------------------------------------------------

# Part 109 --- Default Drift

## 111. Subtle

A software upgrade can change a default even if your manifest did not
change.

For critical settings, prefer explicit configuration where supported.

------------------------------------------------------------------------

# Part 110 --- Configuration Backup

## 112. Recovery

Back up or version:

``` text
Git configuration
IaC
policies
runbooks
non-secret inventory
```

Configuration recovery is part of DR.

------------------------------------------------------------------------

# Part 111 --- Secrets Recovery

## 113. Separate

Secrets should be recoverable through the approved secret-management
system.

Do not solve configuration backup by exporting plaintext secrets.

------------------------------------------------------------------------

# Part 112 --- Compliance During Incident

## 114. Priority

Service restoration may require break-glass changes.

That is acceptable when governed.

After stabilization:

``` text
capture
review
reconcile
```

------------------------------------------------------------------------

# Part 113 --- Lab Namespace

## 115. Scope

Use a disposable namespace and:

``` text
tutorial:chapter74:*
```

for Redis synthetic keys.

Do not test policy enforcement on shared production.

------------------------------------------------------------------------

# Part 114 --- Lab 1: Desired-State Inventory

## 116. Exercise

Create a table:

  Resource   Field         Desired        Source of Truth   Severity
  ---------- ------------- -------------- ----------------- ----------
  REDB       replication   enabled        Git               Critical
  REDB       TLS           required       Git               Critical
  Backup     retention     policy value   platform policy   High

Use your actual supported schema.

------------------------------------------------------------------------

# Part 115 --- Lab 2: Normalize Runtime State

## 117. Exercise

Export a non-secret test configuration.

Remove:

``` text
status
timestamps
generated IDs
```

Create stable comparison output.

------------------------------------------------------------------------

# Part 116 --- Lab 3: Detect Drift

## 118. Exercise

In nonproduction, change a harmless governed test field.

Run comparison.

Expected:

``` text
desired != runtime
```

with resource/field identified.

------------------------------------------------------------------------

# Part 117 --- Lab 4: GitOps Reconciliation

## 119. Exercise

In a disposable environment:

1.  define test resource in Git;
2.  reconcile;
3.  make an approved temporary manual change;
4.  observe controller behavior;
5.  restore source of truth.

Document ownership.

------------------------------------------------------------------------

# Part 118 --- Lab 5: Policy Audit

## 120. Exercise

Create policy logic in audit-only mode for:

``` text
required owner label
required environment label
```

Validate compliant/noncompliant manifests.

------------------------------------------------------------------------

# Part 119 --- Lab 6: TLS Evidence

## 121. Exercise

Collect non-secret evidence:

``` text
endpoint
certificate issuer
expiry
TLS status
```

Create expiry alert threshold per organizational policy.

------------------------------------------------------------------------

# Part 120 --- Lab 7: Backup Compliance

## 122. Exercise

For a nonproduction durable database, record:

``` text
backup policy
last success
retention
last restore test
```

Identify whether configuration and execution both pass.

------------------------------------------------------------------------

# Part 121 --- Lab 8: Exception Workflow

## 123. Exercise

Create a fictional exception:

``` text
control
reason
risk
compensating control
owner
expiry
```

Then test expiry notification.

------------------------------------------------------------------------

# Part 122 --- Lab 9: Drift Alert

## 124. Exercise

Generate a synthetic drift alert containing:

``` text
desired
actual
severity
owner
```

Ensure it contains no secret.

------------------------------------------------------------------------

# Part 123 --- Lab 10: Remediation Gate

## 125. Exercise

Classify five drift examples as:

``` text
auto-remediate
manual remediation
emergency response
accepted exception
```

Explain why.

------------------------------------------------------------------------

# Part 124 --- Failure Scenario 1: Replication Disabled

## 126. Tabletop

Detect critical drift.

Validate:

``` text
alert
owner
change evidence
safe remediation
HA validation
```

------------------------------------------------------------------------

# Part 125 --- Failure Scenario 2: TLS Disabled

## 127. Tabletop

Treat as critical security drift.

Validate escalation and remediation workflow.

------------------------------------------------------------------------

# Part 126 --- Failure Scenario 3: Backup Enabled but Failing

## 128. Test/Tabletop

Configuration says compliant.

Execution says noncompliant.

Ensure compliance engine checks operational success.

------------------------------------------------------------------------

# Part 127 --- Failure Scenario 4: Direct Kubernetes Edit

## 129. Test

In nonproduction, change a Git-managed field directly.

Observe GitOps reconciliation.

Document why multiple writers are risky.

------------------------------------------------------------------------

# Part 128 --- Failure Scenario 5: Policy Blocks Operator

## 130. Tabletop

A new admission policy rejects required Operator behavior.

Practice:

``` text
identify policy
use approved exception/rollback
restore reconciliation
```

------------------------------------------------------------------------

# Part 129 --- Failure Scenario 6: Expired Certificate

## 131. Tabletop

Validate certificate inventory and pre-expiry alert would detect risk
before outage.

------------------------------------------------------------------------

# Part 130 --- Failure Scenario 7: ACL Privilege Widening

## 132. Test/Tabletop

Detect wildcard privilege introduced to a test identity.

Validate security escalation.

------------------------------------------------------------------------

# Part 131 --- Failure Scenario 8: Memory Allocation Drift

## 133. Test/Tabletop

Increase test database allocation.

Validate capacity review is required before accepting desired-state
change.

------------------------------------------------------------------------

# Part 132 --- Failure Scenario 9: Stale Exception

## 134. Test

Allow an exception to reach simulated expiry.

Ensure it becomes actionable rather than silently permanent.

------------------------------------------------------------------------

# Part 133 --- Failure Scenario 10: Auto-Remediation Causes Risk

## 135. Tabletop

Model a bot automatically reducing memory to match stale Git
configuration.

Show why high-risk changes require remediation gates.

------------------------------------------------------------------------

# Part 134 --- Troubleshooting Matrix

## 136. Common Problems

  -----------------------------------------------------------------------
  Symptom                             Investigate
  ----------------------------------- -----------------------------------
  Git differs from cluster            manual edit/reconciliation failure

  cluster differs from Redis runtime  Operator/reconciliation/product
                                      state

  repeated drift                      multiple writers/wrong source of
                                      truth

  false-positive drift                dynamic/default
                                      fields/normalization

  TLS compliance failure              cert/config/trust/endpoint

  backup appears enabled but audit    execution/last success/restore
  fails                               evidence

  policy blocks deployment            admission rule/schema/version

  exception never closes              missing expiry/owner/governance

  unsupported version detected        lifecycle/upgrade planning

  remediation keeps reverting         wrong ownership/controller conflict
  -----------------------------------------------------------------------

------------------------------------------------------------------------

# Part 135 --- Runbook 1: Critical Configuration Drift

## 137. Procedure

``` text
1. identify resource/field.
2. verify desired state.
3. determine actor/change.
4. assess security/availability impact.
5. stabilize if required.
6. remediate through correct owner.
7. validate runtime.
8. preserve audit evidence.
```

------------------------------------------------------------------------

# Part 136 --- Runbook 2: GitOps Drift

## 138. Procedure

``` text
1. compare Git and cluster CR.
2. identify last approved change.
3. identify manual/break-glass change.
4. determine correct desired state.
5. update Git or revert runtime.
6. allow supported reconciliation.
7. validate Redis behavior.
8. close drift record.
```

------------------------------------------------------------------------

# Part 137 --- Runbook 3: TLS / Certificate Compliance

## 139. Procedure

``` text
1. identify affected endpoint.
2. inspect TLS configuration.
3. inspect certificate issuer/expiry.
4. inspect client trust.
5. rotate/fix through approved process.
6. validate clients.
7. verify expiry monitoring.
8. preserve evidence.
```

------------------------------------------------------------------------

# Part 138 --- Runbook 4: ACL Drift

## 140. Procedure

``` text
1. identify identity.
2. compare approved permissions.
3. identify privilege change.
4. assess exposure.
5. revoke/adjust safely.
6. validate application.
7. rotate credentials if required.
8. document change.
```

------------------------------------------------------------------------

# Part 139 --- Runbook 5: Backup Compliance Failure

## 141. Procedure

``` text
1. identify failed control.
2. inspect backup configuration.
3. inspect last successful execution.
4. inspect repository/credentials.
5. restore backup operation.
6. perform validation/restore test as required.
7. confirm RPO.
8. preserve evidence.
```

------------------------------------------------------------------------

# Part 140 --- Runbook 6: Policy Blocks Redis Operation

## 142. Procedure

``` text
1. identify admission/policy denial.
2. identify affected Operator/resource.
3. assess urgency.
4. use approved rollback/exception.
5. restore reconciliation.
6. correct policy.
7. test in audit mode.
8. re-enable enforcement safely.
```

------------------------------------------------------------------------

# Part 141 --- Runbook 7: Unsupported Version

## 143. Procedure

``` text
1. confirm deployed version.
2. confirm support status.
3. identify dependencies.
4. build compatibility matrix.
5. plan supported upgrade path.
6. test.
7. upgrade with rollback/recovery plan.
8. update compliance baseline.
```

------------------------------------------------------------------------

# Part 142 --- Runbook 8: Expired Exception

## 144. Procedure

``` text
1. identify exception/control.
2. contact owner.
3. reassess risk.
4. remediate if possible.
5. renew only with approval if necessary.
6. update compensating control.
7. set new expiry.
8. preserve audit evidence.
```

------------------------------------------------------------------------

# Part 143 --- Baseline Template

## 145. Record

``` text
Resource:
Environment:
Owner:
Source of truth:
Field:
Desired value:
Severity:
Validation method:
Remediation owner:
```

------------------------------------------------------------------------

# Part 144 --- Drift Record Template

## 146. Record

``` text
Detected:
Resource:
Field:
Desired:
Actual:
Severity:
Owner:
Change ID:
Authorized?:
Impact:
Remediation:
Validated:
Closed:
```

------------------------------------------------------------------------

# Part 145 --- Exception Template

## 147. Record

``` text
Control:
Resource:
Reason:
Risk:
Compensating control:
Owner:
Approver:
Created:
Expiry:
Review date:
Remediation plan:
```

------------------------------------------------------------------------

# Part 146 --- Audit Evidence Template

## 148. Record

``` text
Control ID:
Control:
Resource:
Environment:
Expected:
Observed:
Result:
Evidence timestamp:
Evidence source:
Owner:
Exception:
Reviewer:
```

------------------------------------------------------------------------

# Part 147 --- Production Acceptance

## 149. Desired State

-   [ ] authoritative source defined for governed configuration;
-   [ ] cluster baseline documented;
-   [ ] database baseline documented;
-   [ ] security baseline documented;
-   [ ] backup/DR baseline documented;
-   [ ] Kubernetes baseline documented;
-   [ ] client baseline documented where required.

## 150. Detection

-   [ ] runtime state can be collected safely;
-   [ ] secrets are redacted;
-   [ ] dynamic fields normalized;
-   [ ] semantic drift comparison implemented;
-   [ ] drift severity defined;
-   [ ] critical drift alerting implemented;
-   [ ] false-positive suppression governed.

## 151. Security / Resilience

-   [ ] TLS compliance checked;
-   [ ] certificate expiry monitored;
-   [ ] ACL compliance checked;
-   [ ] network exposure checked;
-   [ ] replication health checked;
-   [ ] persistence classification checked;
-   [ ] backup success checked;
-   [ ] restore evidence checked;
-   [ ] DR test age checked;
-   [ ] version support checked.

## 152. Governance

-   [ ] break-glass process documented;
-   [ ] exceptions have owner/expiry;
-   [ ] auto-remediation risk classified;
-   [ ] high-risk remediation requires review;
-   [ ] audit evidence retained;
-   [ ] policy changes tested before enforcement;
-   [ ] ten failure scenarios completed;
-   [ ] eight runbooks reviewed;
-   [ ] production acceptance completed.

------------------------------------------------------------------------

# 153. Knowledge Validation

1.  What is desired state?
2.  What is runtime state?
3.  What is configuration drift?
4.  Why should dynamic fields be excluded from drift alerts?
5.  Give examples of critical Redis configuration drift.
6.  Why must each configuration object have a source of truth?
7.  What problem do multiple configuration writers create?
8.  What belongs in a Redis database baseline?
9.  Why should client configuration sometimes be governed?
10. Why should drift have severity?
11. Why should secrets not be exported into audit evidence?
12. Why is structured semantic comparison better than raw text diff?
13. What are nested reconciliation loops in GitOps + Redis Operator?
14. Why can manual edits to generated Kubernetes resources be unsafe?
15. What is a break-glass change?
16. What must happen after a break-glass change?
17. What is policy as code?
18. Why can an admission policy itself create an outage?
19. Why should certificate expiry be monitored proactively?
20. What is ACL drift?
21. Why is `backup enabled` insufficient proof of backup compliance?
22. Why should restore testing be a compliance control?
23. What does version compliance protect against?
24. Why is an eviction-policy change operationally significant?
25. What should an audit evidence record contain?
26. Why is evidence freshness important?
27. Why should exceptions expire?
28. Why is automatic remediation dangerous for high-risk settings?
29. Why can a compliance percentage hide serious risk?
30. What must pass before Redis configuration governance is
    production-ready?

------------------------------------------------------------------------

# 154. Hands-On Acceptance Checklist

-   [ ] Defined configuration sources of truth.
-   [ ] Built cluster baseline.
-   [ ] Built database baseline.
-   [ ] Built security baseline.
-   [ ] Built backup/DR baseline.
-   [ ] Built Kubernetes baseline.
-   [ ] Built client baseline where required.
-   [ ] Classified drift severity.
-   [ ] Collected sanitized runtime state.
-   [ ] Normalized dynamic fields.
-   [ ] Performed semantic drift comparison.
-   [ ] Tested GitOps drift in nonproduction.
-   [ ] Tested policy in audit mode.
-   [ ] Collected TLS/certificate evidence.
-   [ ] Reviewed ACL baseline.
-   [ ] Reviewed network exposure.
-   [ ] Reviewed replication compliance.
-   [ ] Reviewed backup execution.
-   [ ] Reviewed restore evidence.
-   [ ] Reviewed DR drill evidence.
-   [ ] Reviewed version compliance.
-   [ ] Created exception workflow.
-   [ ] Tested exception expiry.
-   [ ] Classified auto-remediation risk.
-   [ ] Built audit evidence record.
-   [ ] Completed ten failure scenarios.
-   [ ] Completed eight runbooks.
-   [ ] Completed production acceptance.

------------------------------------------------------------------------

# 155. Cleanup

Remove only disposable Chapter 74 lab resources.

For synthetic Redis keys:

``` text
tutorial:chapter74:*
```

use:

``` text
SCAN
+
UNLINK
```

in controlled batches.

Do not use:

``` text
FLUSHDB
FLUSHALL
```

on shared environments.

Remove:

``` text
temporary test policies
temporary exception records
temporary test manifests
temporary drift objects
temporary test credentials
```

through their approved owners.

Confirm:

``` text
Git and runtime reconciled
no test policy remains enforced
no temporary privilege remains
no synthetic drift remains
no secrets exist in lab output
normal Redis health
```

------------------------------------------------------------------------

# 156. Key Takeaways

1.  A healthy Redis cluster can still be noncompliant or dangerously
    misconfigured.
2.  Desired state must be explicitly defined before drift can be
    detected.
3.  Runtime state should be compared only on governed, stable fields.
4.  Every configuration object needs a clear source of truth and owner.
5.  Multiple uncontrolled writers create recurring drift and controller
    conflicts.
6.  Baselines should cover cluster, database, security, network, backup,
    DR, observability, Kubernetes, and relevant client configuration.
7.  Drift should be classified by risk so critical changes are not
    hidden in noise.
8.  Secret values must never be copied into ordinary compliance
    evidence.
9.  Semantic structured comparison is safer than relying only on text
    diffs.
10. GitOps and the Redis Enterprise Operator create nested
    reconciliation loops whose ownership must be understood.
11. Emergency break-glass changes are valid when authorized, documented,
    time-bounded, and reconciled afterward.
12. Policy as code can prevent unsafe configuration before deployment.
13. Policy enforcement itself must be tested because it can block
    recovery or Operator reconciliation.
14. TLS compliance includes configuration, certificate trust, validity,
    and expiry monitoring.
15. ACL compliance requires least privilege and detection of privilege
    widening.
16. Network exposure and NetworkPolicy/firewall state are part of Redis
    security compliance.
17. HA compliance requires healthy replicas and correct failure-domain
    placement, not merely a configuration flag.
18. Backup compliance requires successful execution and restore
    evidence.
19. RPO/RTO claims should be demonstrated through measured recovery
    behavior.
20. Version and compatibility compliance reduces security, support, and
    upgrade risk.
21. Capacity, eviction, TTL, and client timeout changes can be material
    operational drift.
22. Audit evidence should be structured, current, attributable, and
    secret-safe.
23. Exceptions need risk, owner, approval, compensating controls, and
    expiry.
24. Detection can be automated broadly; remediation should be automated
    only when blast radius is understood.
25. Production readiness requires desired-state ownership, drift
    detection, security/resilience controls, exception governance,
    evidence automation, tested failures, and practiced runbooks.

------------------------------------------------------------------------

# 157. References

Validate Redis Enterprise configuration fields, APIs, security
capabilities, backup/restore settings, Kubernetes CRDs, and Operator
behavior against the exact deployed versions and current official
documentation.

Recommended documentation areas:

-   Redis Enterprise administration
-   Redis Enterprise security
-   Redis Enterprise access control / ACLs
-   Redis Enterprise TLS and certificates
-   Redis Enterprise database configuration
-   Redis Enterprise high availability
-   Redis Enterprise backup and recovery
-   Redis Enterprise Active-Active
-   Redis Enterprise REST API / CLI
-   Redis Enterprise Kubernetes Operator
-   Redis Enterprise Kubernetes CRDs
-   Kubernetes RBAC
-   Kubernetes NetworkPolicy
-   Kubernetes admission control
-   Kubernetes server-side dry run and diff
-   GitOps platform documentation
-   Infrastructure as Code platform documentation
-   organizational security standards
-   organizational audit/compliance standards
-   organizational change-management standards

------------------------------------------------------------------------

# Next Chapter

**Chapter 75 --- Redis Enterprise Business Continuity, Regional DR &
Failback Project**

Chapter 75 will be a production project integrating backup, restore,
replication, regional dependency mapping, RPO/RTO, capacity, DNS/traffic
routing, failover decision gates, emergency regional recovery,
application validation, data validation, region rejoin, staged failback,
DR exercises, evidence, incident communication, runbooks, and final
project acceptance.
