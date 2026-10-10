# Chapter 64 --- Redis Enterprise Kubernetes Upgrade, Backup & Recovery Operations

**Status:** Canonical\
**Track:** Redis Enterprise / Redis Software Production Engineering\
**Part:** Part 11 --- Advanced Kubernetes, Active-Active & Platform
Engineering\
**Level:** Advanced → Production Lifecycle, Backup & Recovery
Engineering\
**Audience:** SREs, DBREs, Platform Engineers, Kubernetes
Administrators, Redis Administrators, Cloud Engineers, GitOps Engineers\
**Lab type:** Compatibility assessment, Operator/CRD/Redis upgrade
planning, preflight validation, maintenance, backup policy, restore
testing, failed-upgrade recovery, GitOps coordination, RPO/RTO
validation, failure injection, troubleshooting, runbooks, and production
acceptance

------------------------------------------------------------------------

# 1. Objective

Redis Enterprise on Kubernetes has several lifecycle layers:

``` text
Kubernetes platform
      |
Redis Enterprise Operator + CRDs
      |
Redis Enterprise cluster
      |
Redis Enterprise databases
      |
application clients
```

A production upgrade must respect compatibility across all layers.

Backup and recovery introduce another chain:

``` text
database
   |
backup creation
   |
backup repository
   |
retention/integrity
   |
restore
   |
application validation
```

An upgrade is not successful merely because pods become `Running`.

A backup is not proven merely because a backup job reports success.

By the end of this chapter, you should be able to:

-   inventory all lifecycle versions;
-   build a supported compatibility matrix;
-   perform upgrade preflight checks;
-   understand Operator and CRD upgrade implications;
-   plan Redis Enterprise upgrades;
-   coordinate Kubernetes upgrades;
-   define rollback versus recovery boundaries;
-   establish backup policy;
-   validate backup integrity;
-   perform restore drills;
-   measure RPO and RTO;
-   coordinate GitOps during maintenance;
-   recover from failed upgrades;
-   execute production runbooks and acceptance gates.

------------------------------------------------------------------------

# 2. Core Production Principle

Every lifecycle change needs two plans:

``` text
forward plan
+
recovery plan
```

Do not approve:

``` text
"upgrade and see what happens"
```

A safe change answers:

``` text
What changes?
What is compatible?
What can fail?
What can be rolled back?
What requires restore/recovery?
How will success be proven?
```

------------------------------------------------------------------------

# Part 1 --- Lifecycle Inventory

## 3. Record Versions

Before planning a change, inventory:

``` text
Kubernetes version
Redis Enterprise Operator version
Redis CRD/API versions
Redis Enterprise cluster version
database capabilities/modules
client libraries
CSI
CNI
GitOps controller
```

------------------------------------------------------------------------

# Part 2 --- Version Evidence

## 4. Kubernetes

``` bash
kubectl version
```

Use the supported output for your Kubernetes release.

## 5. Operator

Discover:

``` bash
kubectl get deploy -A | grep -i redis
```

Then inspect the actual Operator deployment/image.

## 6. CRDs

``` bash
kubectl get crd | grep -i redis
```

Inspect relevant CRDs:

``` bash
kubectl get crd <name> -o yaml
```

## 7. Redis Enterprise

Use supported Redis Enterprise interfaces and custom-resource status to
record the deployed version.

Do not infer product version only from a pod name.

------------------------------------------------------------------------

# Part 3 --- Compatibility Matrix

## 8. Build Before Upgrade

Create:

  Layer              Current   Target   Compatibility Verified?
  ------------------ --------- -------- -------------------------
  Kubernetes                            
  Operator                              
  CRDs                                  
  Redis Enterprise                      
  CSI                                   
  CNI                                   
  Clients                               

Use current official documentation for the exact versions.

------------------------------------------------------------------------

# Part 4 --- Release Notes

## 9. Review

For each target release, identify:

``` text
breaking changes
deprecated fields
removed features
known issues
upgrade prerequisites
minimum/maximum supported versions
security changes
storage changes
networking changes
```

------------------------------------------------------------------------

# Part 5 --- Upgrade Path

## 10. Intermediate Versions

Some upgrades may require intermediate releases.

Do not assume:

``` text
current -> latest
```

is a supported direct path.

------------------------------------------------------------------------

# Part 6 --- Upgrade Order

## 11. Version-Specific

The correct sequence among:

``` text
CRDs
Operator
Redis Enterprise cluster
databases
Kubernetes
```

must come from documentation for the exact source/target versions.

Do not invent a universal order.

------------------------------------------------------------------------

# Part 7 --- Preflight Health

## 12. Start Healthy

Do not begin routine upgrade work while the platform is already
degraded.

Validate:

``` text
Operator healthy
REC healthy
REDB healthy
pods ready
PVCs healthy
nodes healthy
Redis replication healthy
capacity sufficient
application SLO normal
```

------------------------------------------------------------------------

# Part 8 --- Preflight Events

## 13. Check

``` bash
kubectl get events -A --sort-by=.lastTimestamp
```

Investigate meaningful unresolved warnings.

------------------------------------------------------------------------

# Part 9 --- Preflight Nodes

## 14. Capacity

``` bash
kubectl get nodes
kubectl describe node <node>
```

Validate:

``` text
Ready
no unexpected pressure
failure-domain capacity
maintenance headroom
```

------------------------------------------------------------------------

# Part 10 --- Preflight Storage

## 15. Validate

``` bash
kubectl get pvc -A
kubectl get pv
kubectl get storageclass
```

Also check infrastructure telemetry:

``` text
capacity
IOPS
throughput
latency
errors
```

------------------------------------------------------------------------

# Part 11 --- Preflight Database Capacity

## 16. Headroom

An upgrade can temporarily increase resource demand.

Validate:

``` text
CPU
memory
storage
network
shard/node placement
N-1 capacity
```

------------------------------------------------------------------------

# Part 12 --- Preflight Backup

## 17. Recovery Gate

Before high-risk change:

``` text
backup policy healthy
recent backup successful
restore procedure known
restore test current
repository reachable
credentials valid
```

A recent backup without a tested restore is incomplete evidence.

------------------------------------------------------------------------

# Part 13 --- Configuration Capture

## 18. Non-Secret State

Capture:

``` bash
kubectl get <redis-resources> -A
kubectl get pods -A
kubectl get pvc -A
kubectl get pdb -A
```

Store approved YAML/configuration evidence without secret values.

------------------------------------------------------------------------

# Part 14 --- Application Baseline

## 19. Before Change

Record:

``` text
request rate
Redis ops/sec
P50/P95/P99
error rate
timeouts
connections
CPU
memory
```

This becomes the post-upgrade comparison baseline.

------------------------------------------------------------------------

# Part 15 --- Change Freeze

## 20. Reduce Variables

During a high-risk maintenance window, avoid unrelated changes such as:

``` text
application deployment
database schema/config change
network policy change
storage migration
large data load
```

unless they are part of the approved plan.

------------------------------------------------------------------------

# Part 16 --- GitOps Coordination

## 21. Source of Truth

Determine:

``` text
what GitOps owns
what the Redis Operator owns
what maintenance changes GitOps could revert
```

------------------------------------------------------------------------

# Part 17 --- GitOps Maintenance Strategy

## 22. Controlled

Use the organization's approved mechanism to prevent GitOps from
fighting the upgrade.

Possible approaches depend on the GitOps platform.

Do not simply disable reconciliation and forget to restore it.

------------------------------------------------------------------------

# Part 18 --- Operator Upgrade

## 23. Scope

Operator upgrade can change:

``` text
controller behavior
supported APIs
validation
generated resources
upgrade logic
```

Treat it as a production control-plane change.

------------------------------------------------------------------------

# Part 19 --- CRD Upgrade

## 24. API Change

CRD updates can alter:

``` text
served versions
storage version
validation schema
defaulting
fields
subresources
```

Back up/configure recovery for custom-resource definitions and
desired-state manifests according to the supported procedure.

------------------------------------------------------------------------

# Part 20 --- CRD Conversion

## 25. Awareness

When API versions evolve, conversion/storage semantics can matter.

Never manually rewrite stored custom-resource data without documented
procedure.

------------------------------------------------------------------------

# Part 21 --- Operator Image

## 26. Validate

Before deployment:

``` text
image source trusted
version approved
registry reachable
imagePullSecrets valid
```

------------------------------------------------------------------------

# Part 22 --- Operator Upgrade Observation

## 27. Monitor

During upgrade:

``` text
deployment rollout
pod readiness
Operator logs
reconciliation errors
REC status
REDB status
Kubernetes events
```

------------------------------------------------------------------------

# Part 23 --- Operator Upgrade Validation

## 28. Functional Test

After Operator upgrade:

``` text
read CRs
reconcile existing CRs
perform one approved nonproduction reconciliation
verify no unexpected drift
```

------------------------------------------------------------------------

# Part 24 --- Redis Enterprise Upgrade

## 29. Data-Plane Change

Redis Enterprise upgrade can affect:

``` text
nodes
shards
database availability
persistence
networking
clients
capabilities
```

Use vendor-supported orchestration.

------------------------------------------------------------------------

# Part 25 --- Rolling Behavior

## 30. Do Not Assume Zero Impact

Even a rolling procedure can create:

``` text
failovers
reconnections
latency spikes
temporary reduced redundancy
```

Validate application tolerance.

------------------------------------------------------------------------

# Part 26 --- Client Behavior

## 31. During Upgrade

Clients should be qualified for:

``` text
connection loss
reconnect
DNS changes if any
retry/backoff
failover
TLS
```

Chapter 53's client engineering principles apply.

------------------------------------------------------------------------

# Part 27 --- Upgrade SLO

## 32. Define

Example categories:

``` text
maximum error rate
maximum P99
maximum failover duration
maximum unavailable databases
maximum recovery time
```

Use application-specific values.

------------------------------------------------------------------------

# Part 28 --- Stop Conditions

## 33. Before Start

Define conditions that pause or abort the change.

Examples:

``` text
unexpected database unavailable
error rate exceeds threshold
P99 exceeds threshold
replication not recovering
storage latency critical
multiple nodes degraded
```

------------------------------------------------------------------------

# Part 29 --- Kubernetes Upgrade

## 34. Separate Lifecycle

Kubernetes upgrades can affect:

``` text
API compatibility
scheduling
node images
CNI
CSI
admission
PodSecurity
load balancers
```

Validate Redis support before platform upgrade.

------------------------------------------------------------------------

# Part 30 --- Kubernetes API Deprecation

## 35. Precheck

Check whether Redis Operator manifests/CRDs or organizational policies
depend on APIs removed in the target Kubernetes release.

------------------------------------------------------------------------

# Part 31 --- Node-Pool Upgrade

## 36. Stateful Workload

Node replacement/rotation must respect:

``` text
Redis redundancy
PDB
placement
PVC topology
remaining capacity
```

------------------------------------------------------------------------

# Part 32 --- One Failure Domain at a Time

## 37. Maintenance

Where architecture and procedure permit, avoid removing excessive Redis
capacity simultaneously.

Monitor recovery before proceeding to the next maintenance unit.

------------------------------------------------------------------------

# Part 33 --- Rollback Definition

## 38. Clarify

Rollback means:

``` text
return to previous software/configuration state
```

Recovery means:

``` text
restore service/data after failure
```

They are not the same.

------------------------------------------------------------------------

# Part 34 --- Rollback Feasibility

## 39. Not Guaranteed

Rollback can be limited by:

``` text
data format changes
CRD/API changes
database migrations
persistent state
unsupported downgrade paths
```

Document the real boundary.

------------------------------------------------------------------------

# Part 35 --- Point of No Return

## 40. Explicit

For every upgrade, identify the step after which:

``` text
simple rollback is no longer supported
```

Beyond that point, use the documented recovery path.

------------------------------------------------------------------------

# Part 36 --- Backup Objective

## 41. Why Backup

Backup protects against scenarios such as:

``` text
accidental deletion
logical corruption
operator error
disaster
migration failure
upgrade failure requiring recovery
```

HA alone is not backup.

------------------------------------------------------------------------

# Part 37 --- RPO

## 42. Recovery Point Objective

RPO answers:

``` text
How much data loss can the business tolerate?
```

Example:

``` text
RPO = 15 minutes
```

means the recovery design must meet that business requirement.

------------------------------------------------------------------------

# Part 38 --- RTO

## 43. Recovery Time Objective

RTO answers:

``` text
How long can service remain unavailable/degraded?
```

Restore tests must measure actual recovery time.

------------------------------------------------------------------------

# Part 39 --- Backup Frequency

## 44. Derive from RPO

Backup frequency should be driven by:

``` text
data criticality
RPO
backup duration
repository capacity
operational impact
```

------------------------------------------------------------------------

# Part 40 --- Backup Retention

## 45. Policy

Define:

``` text
short-term operational retention
longer retention if required
compliance retention
deletion policy
```

Do not retain indefinitely without purpose.

------------------------------------------------------------------------

# Part 41 --- Backup Repository

## 46. Separate Failure Domain

Where supported, store backups so the same infrastructure failure does
not destroy both primary data and backups.

------------------------------------------------------------------------

# Part 42 --- Repository Security

## 47. Protect

Use:

``` text
encryption
least privilege
credential rotation
access logging
retention controls
```

------------------------------------------------------------------------

# Part 43 --- Backup Credentials

## 48. Secrets

Do not hard-code repository credentials in Git or runbooks.

Use supported secret-management integration.

------------------------------------------------------------------------

# Part 44 --- Backup Monitoring

## 49. Alert

Monitor:

``` text
last successful backup
backup age
backup duration
backup failures
repository errors
capacity
```

------------------------------------------------------------------------

# Part 45 --- Backup Success Is Not Enough

## 50. Restore Proof

A successful backup job proves only that backup creation reported
success.

Production readiness requires restore testing.

------------------------------------------------------------------------

# Part 46 --- Restore Environment

## 51. Isolated

Prefer restore drills into:

``` text
nonproduction
isolated namespace/cluster
controlled network
```

Avoid overwriting production during validation.

------------------------------------------------------------------------

# Part 47 --- Restore Validation

## 52. Verify

After restore:

``` text
database starts
expected keys/data exist
TTL semantics acceptable
application can connect
queries/commands work
data integrity checks pass
```

------------------------------------------------------------------------

# Part 48 --- Application-Level Validation

## 53. Important

Infrastructure restore success does not prove application correctness.

Run application-specific smoke tests.

------------------------------------------------------------------------

# Part 49 --- Data Validation

## 54. Examples

Depending on workload:

``` text
key count
sample keys
checksums/hashes
business records
stream state
JSON documents
Search queries
vector retrieval
```

Use workload-appropriate checks.

------------------------------------------------------------------------

# Part 50 --- TTL Validation

## 55. Time-Sensitive Data

For cache/TTL-heavy databases, understand how backup/restore affects
expiration semantics.

Validate with representative data.

------------------------------------------------------------------------

# Part 51 --- Search / JSON / Vector

## 56. Capability Validation

After restore, validate advanced database capabilities required by the
application.

Examples:

``` text
JSON reads/updates
Search indexes/queries
vector retrieval
```

Use current product recovery semantics.

------------------------------------------------------------------------

# Part 52 --- Restore Timing

## 57. Measure

Break RTO into:

``` text
decision time
environment preparation
backup retrieval
restore execution
Redis recovery
application validation
traffic restoration
```

------------------------------------------------------------------------

# Part 53 --- Restore Throughput

## 58. Capacity

Large restore operations can be limited by:

``` text
repository throughput
network
storage write throughput
CPU
Redis ingestion/recovery
```

Benchmark representative sizes.

------------------------------------------------------------------------

# Part 54 --- Backup During Load

## 59. Qualification

Test backup while the database serves representative workload.

Measure:

``` text
P99
CPU
storage I/O
network
backup duration
```

------------------------------------------------------------------------

# Part 55 --- Restore During Incident

## 60. Capacity Reservation

Disaster recovery often happens while infrastructure is degraded.

Ensure the recovery environment has enough:

``` text
CPU
memory
storage
network
```

------------------------------------------------------------------------

# Part 56 --- Configuration Backup

## 61. Beyond Data

Recovery may also require:

``` text
Git manifests
CR configuration
network policies
certificates/trust configuration
secret references
DNS/LB configuration
```

Do not treat data backup as the entire platform recovery plan.

------------------------------------------------------------------------

# Part 57 --- Secret Recovery

## 62. Separate Process

Backups should not encourage storing plaintext secrets in Git.

Document how secrets are recreated/restored through the approved secret
system.

------------------------------------------------------------------------

# Part 58 --- Certificate Recovery

## 63. Trust

Recovery must restore valid:

``` text
server certificates
CA trust
client trust
```

where required.

------------------------------------------------------------------------

# Part 59 --- GitOps Recovery

## 64. Desired State

Git can help reconstruct:

``` text
REC
REDB
RERC
REAADB
NetworkPolicy
supporting manifests
```

but only if the repository reflects the approved production state.

------------------------------------------------------------------------

# Part 60 --- Recovery Order

## 65. Dependency Driven

A conceptual recovery dependency chain can be:

``` text
Kubernetes infrastructure
 -> Operator/CRDs
 -> Redis Enterprise cluster
 -> database resources
 -> data restore
 -> endpoints/security
 -> application validation
 -> traffic
```

Use exact product recovery procedures.

------------------------------------------------------------------------

# Part 61 --- Failed Operator Upgrade

## 66. Diagnose

If Operator upgrade fails:

``` text
inspect rollout
inspect image pull
inspect logs
inspect CRD compatibility
inspect RBAC
inspect admission
inspect existing CR status
```

Do not immediately downgrade without confirming support.

------------------------------------------------------------------------

# Part 62 --- Failed Redis Upgrade

## 67. Protect Data

If Redis Enterprise upgrade stalls:

``` text
pause further changes
preserve evidence
check cluster/database health
check storage/network
follow vendor-supported recovery
```

Do not delete failed pods/PVCs blindly.

------------------------------------------------------------------------

# Part 63 --- Partial Upgrade

## 68. Mixed State

A cluster may temporarily contain components at different versions
during a supported upgrade.

Know:

``` text
which mixed versions are supported
how long
what actions are prohibited
```

------------------------------------------------------------------------

# Part 64 --- Upgrade Timeout

## 69. Don't Guess

A long-running step is not automatically failed.

Use:

``` text
status
logs
events
Redis health
documented expectations
```

before intervention.

------------------------------------------------------------------------

# Part 65 --- Maintenance Window

## 70. Size

Include time for:

``` text
preflight
upgrade
validation
recovery buffer
rollback/recovery decision
```

Do not size the window only for the happy path.

------------------------------------------------------------------------

# Part 66 --- Communication

## 71. Operational

Before change, publish:

``` text
scope
start/end
expected impact
owners
stop conditions
rollback/recovery path
validation
```

During change, record major milestones.

------------------------------------------------------------------------

# Part 67 --- Change Evidence

## 72. Timeline

Record:

``` text
T0 preflight complete
T1 change started
T2 component upgraded
T3 failover/restart
T4 health restored
T5 application validation
T6 change complete
```

------------------------------------------------------------------------

# Part 68 --- Post-Upgrade Soak

## 73. Don't Close Immediately

Observe for an appropriate period:

``` text
P99
errors
CPU
memory
storage
connections
replication
backup
Operator reconciliation
```

------------------------------------------------------------------------

# Part 69 --- Post-Upgrade Backup

## 74. Validate

After major lifecycle change, confirm scheduled backup/recovery
mechanisms still work.

------------------------------------------------------------------------

# Part 70 --- Restore Drill Cadence

## 75. Recurring

Restore testing should be repeated because:

``` text
versions change
data grows
credentials rotate
repositories change
runbooks drift
people change
```

------------------------------------------------------------------------

# Part 71 --- Recovery Evidence

## 76. Record

For every drill:

``` text
backup selected
backup age
restore start
restore end
RPO achieved
RTO achieved
validation result
issues
corrective actions
```

------------------------------------------------------------------------

# Part 72 --- Failure Scenario 1: Operator Image Pull Failure

## 77. Lab

Use an isolated test deployment with an invalid image reference.

Validate:

``` text
failure visible
existing Redis data plane understood
rollback path documented
```

------------------------------------------------------------------------

# Part 73 --- Failure Scenario 2: CRD Validation Change

## 78. Lab/Tabletop

Use nonproduction to test how a manifest behaves against target CRD
validation.

Catch incompatibility before production.

------------------------------------------------------------------------

# Part 74 --- Failure Scenario 3: Upgrade Capacity Shortage

## 79. Tabletop

Model temporary upgrade/recovery resource needs exceeding available
capacity.

Verify preflight rejects the change.

------------------------------------------------------------------------

# Part 75 --- Failure Scenario 4: Node Failure During Upgrade

## 80. Lab

During a qualified nonproduction rolling upgrade, simulate one approved
infrastructure failure only if supported and safe.

Validate remaining capacity and recovery.

------------------------------------------------------------------------

# Part 76 --- Failure Scenario 5: Backup Failure

## 81. Lab

Cause a disposable backup to fail through a safe test condition such as
invalid test credentials or unavailable test destination.

Verify:

``` text
alert
diagnosis
no false success
```

------------------------------------------------------------------------

# Part 77 --- Failure Scenario 6: Stale Backup

## 82. Test

Simulate:

``` text
last backup age > RPO threshold
```

Verify alert/escalation blocks high-risk change.

------------------------------------------------------------------------

# Part 78 --- Failure Scenario 7: Restore Failure

## 83. Lab

Use an invalid/incomplete disposable backup reference where safe.

Validate clear failure and recovery procedure.

------------------------------------------------------------------------

# Part 79 --- Failure Scenario 8: Insufficient Restore Capacity

## 84. Tabletop/Lab

Model restore into an undersized target.

Ensure capacity validation catches the problem before production
recovery.

------------------------------------------------------------------------

# Part 80 --- Failure Scenario 9: GitOps Reverts Maintenance Change

## 85. Lab

In nonproduction, demonstrate an uncoordinated maintenance change being
reverted by GitOps.

Document the correct maintenance workflow.

------------------------------------------------------------------------

# Part 81 --- Failure Scenario 10: Post-Upgrade Regression

## 86. Test

Use a controlled performance comparison:

``` text
before baseline
after baseline
```

Detect:

``` text
P99 regression
CPU regression
memory regression
connection regression
```

before closing the change.

------------------------------------------------------------------------

# Part 82 --- Troubleshooting Matrix

## 87. Common Problems

  -----------------------------------------------------------------------
  Symptom                             Investigate
  ----------------------------------- -----------------------------------
  Operator rollout stuck              image, RBAC, CRD, admission, logs

  CR invalid after upgrade            API/schema/deprecated field

  Redis upgrade stalls                cluster health, capacity, storage,
                                      network

  app errors during rolling change    failover, reconnect, retry,
                                      endpoint

  backup fails                        repository, credentials, network,
                                      capacity

  backup too old                      scheduler, previous failures,
                                      repository

  restore slow                        repository/network/storage/CPU

  restore succeeds/app fails          endpoint, TLS, auth, data semantics

  GitOps reverts change               source-of-truth/maintenance
                                      coordination

  upgrade green but P99 worse         performance regression
  -----------------------------------------------------------------------

------------------------------------------------------------------------

# Part 83 --- Runbook 1: Upgrade Preflight

## 88. Procedure

``` text
1. inventory current/target versions.
2. verify compatibility and upgrade path.
3. review release notes.
4. validate Operator/REC/REDB health.
5. validate node/storage/network capacity.
6. validate backup and recent restore evidence.
7. capture baseline and configuration.
8. obtain approval/start window.
```

------------------------------------------------------------------------

# Part 84 --- Runbook 2: Operator / CRD Upgrade

## 89. Procedure

``` text
1. verify exact supported sequence.
2. capture CRD/CR state.
3. coordinate GitOps.
4. apply supported CRD/Operator change.
5. monitor rollout/logs/events.
6. validate existing CR reconciliation.
7. run nonproduction functional reconciliation.
8. restore normal GitOps and monitor.
```

------------------------------------------------------------------------

# Part 85 --- Runbook 3: Redis Enterprise Upgrade

## 90. Procedure

``` text
1. confirm preflight.
2. establish enhanced monitoring.
3. start supported upgrade.
4. monitor node/shard/database state.
5. monitor application SLO.
6. stop/escalate if thresholds exceeded.
7. validate cluster/database/application.
8. complete soak and evidence.
```

------------------------------------------------------------------------

# Part 86 --- Runbook 4: Kubernetes Node Upgrade

## 91. Procedure

``` text
1. verify target Kubernetes compatibility.
2. validate Redis redundancy/capacity.
3. inspect PDB/placement/PVC topology.
4. upgrade one approved maintenance unit.
5. monitor Redis recovery.
6. wait for steady state.
7. continue according to plan.
8. validate final application/platform health.
```

------------------------------------------------------------------------

# Part 87 --- Runbook 5: Backup Failure

## 92. Procedure

``` text
1. confirm failed backup.
2. identify last successful backup.
3. compare backup age with RPO.
4. inspect repository/network/credentials.
5. correct supported cause.
6. rerun backup.
7. validate success.
8. escalate if RPO is at risk.
```

------------------------------------------------------------------------

# Part 88 --- Runbook 6: Restore Drill

## 93. Procedure

``` text
1. select approved backup.
2. prepare isolated target.
3. verify target capacity/security.
4. execute supported restore.
5. measure restore time.
6. validate data/application.
7. calculate achieved RPO/RTO.
8. record gaps/corrective actions.
```

------------------------------------------------------------------------

# Part 89 --- Runbook 7: Failed Upgrade Recovery

## 94. Procedure

``` text
1. stop additional changes.
2. preserve logs/events/status.
3. determine current component versions.
4. assess data-plane health.
5. identify rollback/recovery boundary.
6. follow supported recovery path.
7. validate Redis/application/data.
8. document incident and prevention.
```

------------------------------------------------------------------------

# Part 90 --- Runbook 8: Post-Upgrade Regression

## 95. Procedure

``` text
1. compare pre/post P50/P95/P99.
2. compare errors/timeouts.
3. compare CPU/memory.
4. compare storage/network.
5. compare client connections/retries.
6. identify version/config behavior change.
7. mitigate through supported path.
8. update qualification tests.
```

------------------------------------------------------------------------

# Part 91 --- Upgrade Plan Template

## 96. Record

``` text
Environment:
Current Kubernetes:
Target Kubernetes:
Current Operator:
Target Operator:
Current Redis:
Target Redis:
CRD changes:
Compatibility evidence:
Upgrade sequence:
Maintenance window:
Expected impact:
Stop conditions:
Point of no return:
Rollback:
Recovery:
Backup evidence:
Validation:
Owners:
```

------------------------------------------------------------------------

# Part 92 --- Backup Policy Template

## 97. Record

``` text
Database:
Owner:
Criticality:
RPO:
RTO:
Backup frequency:
Retention:
Repository:
Encryption:
Credential owner:
Last successful backup:
Last restore test:
Restore target:
Alert thresholds:
```

------------------------------------------------------------------------

# Part 93 --- Restore Evidence Template

## 98. Record

``` text
Backup ID/reference:
Backup timestamp:
Restore environment:
Restore start:
Restore complete:
Application validation complete:
Data validation:
Expected RPO:
Achieved RPO:
Expected RTO:
Achieved RTO:
Issues:
Corrective actions:
Owner:
```

------------------------------------------------------------------------

# Part 94 --- Upgrade Timeline Template

## 99. Record

``` text
Preflight completed:
Backup verified:
Change started:
Operator/CRD milestone:
Redis milestone:
Node/Kubernetes milestone:
Application validation:
Backup validation:
Soak completed:
Change closed:
```

------------------------------------------------------------------------

# Part 95 --- Production Acceptance

## 100. Compatibility

-   [ ] current versions inventoried;
-   [ ] target versions documented;
-   [ ] official compatibility verified;
-   [ ] direct/intermediate upgrade path verified;
-   [ ] release notes reviewed;
-   [ ] deprecated/removed APIs reviewed;
-   [ ] client compatibility reviewed.

## 101. Preflight

-   [ ] Operator healthy;
-   [ ] REC/REDB healthy;
-   [ ] nodes healthy;
-   [ ] storage healthy;
-   [ ] network healthy;
-   [ ] N-1 capacity validated;
-   [ ] recent backup verified;
-   [ ] recent restore evidence available;
-   [ ] application baseline captured;
-   [ ] stop conditions approved.

## 102. Upgrade Operations

-   [ ] exact sequence documented;
-   [ ] GitOps coordination defined;
-   [ ] point of no return documented;
-   [ ] rollback feasibility documented;
-   [ ] recovery path documented;
-   [ ] maintenance window includes recovery buffer;
-   [ ] enhanced monitoring enabled;
-   [ ] post-upgrade soak defined.

## 103. Backup / Recovery

-   [ ] RPO approved;
-   [ ] RTO approved;
-   [ ] backup frequency aligns with RPO;
-   [ ] retention documented;
-   [ ] repository protected;
-   [ ] backup monitoring configured;
-   [ ] restore drill completed;
-   [ ] application-level restore validation completed;
-   [ ] achieved RPO/RTO measured;
-   [ ] configuration/secret/certificate recovery documented.

## 104. Operational Acceptance

-   [ ] ten failure scenarios completed;
-   [ ] eight runbooks reviewed;
-   [ ] failed-upgrade recovery tested/tabletopped;
-   [ ] post-upgrade regression test completed;
-   [ ] production acceptance completed.

------------------------------------------------------------------------

# 105. Knowledge Validation

1.  Why must lifecycle versions be inventoried before upgrade?
2.  Why is a compatibility matrix necessary?
3.  Why should release notes be reviewed for every target version?
4.  Why might an intermediate upgrade be required?
5.  Why is there no universal Operator/CRD/Redis upgrade order?
6.  Why should routine upgrades start from a healthy state?
7.  Why is N-1 capacity part of upgrade preflight?
8.  Why is a recent backup insufficient without restore evidence?
9.  Why capture an application performance baseline?
10. Why coordinate GitOps during maintenance?
11. Why are CRD changes production API changes?
12. Why can a rolling upgrade still affect applications?
13. Why should upgrade stop conditions be predefined?
14. Why must Kubernetes compatibility be checked separately?
15. What is the difference between rollback and recovery?
16. What is a point of no return?
17. Why is HA not a backup?
18. What does RPO measure?
19. What does RTO measure?
20. Why should backup frequency derive from RPO?
21. Why should backups be in a separate failure domain?
22. Why must backup repositories be secured?
23. Why is backup success not proof of recoverability?
24. Why should restore tests use application-level validation?
25. Why do TTL-heavy workloads need restore-specific validation?
26. Why should restore throughput be benchmarked?
27. Why does recovery require more than database data?
28. Why can partial/mixed-version state matter?
29. Why is a post-upgrade soak period important?
30. What must pass before lifecycle and recovery operations are
    production-ready?

------------------------------------------------------------------------

# 106. Hands-On Acceptance Checklist

-   [ ] Inventoried Kubernetes version.
-   [ ] Inventoried Operator version.
-   [ ] Inventoried CRD/API versions.
-   [ ] Inventoried Redis Enterprise version.
-   [ ] Built compatibility matrix.
-   [ ] Reviewed release notes.
-   [ ] Verified upgrade path.
-   [ ] Completed health preflight.
-   [ ] Completed storage/network preflight.
-   [ ] Validated N-1 capacity.
-   [ ] Captured application baseline.
-   [ ] Captured non-secret configuration.
-   [ ] Documented GitOps maintenance workflow.
-   [ ] Documented upgrade sequence.
-   [ ] Documented stop conditions.
-   [ ] Documented point of no return.
-   [ ] Documented rollback/recovery boundary.
-   [ ] Verified backup schedule.
-   [ ] Verified backup repository security.
-   [ ] Verified backup monitoring.
-   [ ] Performed isolated restore.
-   [ ] Validated restored data.
-   [ ] Validated application against restore.
-   [ ] Measured achieved RPO.
-   [ ] Measured achieved RTO.
-   [ ] Tested backup failure.
-   [ ] Tested stale-backup alert.
-   [ ] Tested restore failure.
-   [ ] Tested GitOps maintenance conflict.
-   [ ] Completed post-upgrade regression comparison.
-   [ ] Completed ten failure scenarios.
-   [ ] Completed eight runbooks.
-   [ ] Completed production acceptance.

------------------------------------------------------------------------

# 107. Cleanup

Remove only disposable Chapter 64 lab resources.

Restore:

``` text
GitOps reconciliation
temporary test manifests
test backup credentials
test backup destinations
isolated restore databases
temporary test namespaces
temporary maintenance settings
```

Verify:

``` bash
kubectl get nodes
kubectl get pods -A
kubectl get pvc -A
kubectl get <redis-resources> -A
```

Confirm:

``` text
Operator healthy
Redis cluster healthy
databases healthy
GitOps synchronized
scheduled backups healthy
temporary restore data removed
application performance at baseline
```

Never delete production backups merely as tutorial cleanup.

Never downgrade Redis Enterprise, the Operator, CRDs, or Kubernetes
solely to practice rollback.

Use isolated nonproduction environments for destructive recovery
exercises.

------------------------------------------------------------------------

# 108. Key Takeaways

1.  Redis Enterprise Kubernetes upgrades span Kubernetes, Operator,
    CRDs, Redis Enterprise, storage/networking, and clients.
2.  Compatibility must be proven for the exact source and target
    versions.
3.  Release notes and supported upgrade paths are mandatory inputs.
4.  A healthy preflight reduces change risk.
5.  N-1 capacity matters during maintenance and recovery.
6.  A recent backup without a tested restore is incomplete protection.
7.  GitOps must be coordinated so it does not fight maintenance.
8.  Operator and CRD upgrades are production control-plane/API changes.
9.  Rolling upgrades can still produce failovers, reconnects, and
    latency spikes.
10. Stop conditions should be agreed before the change begins.
11. Kubernetes lifecycle must be qualified separately from Redis
    lifecycle.
12. Rollback and recovery are different operations.
13. Every change should document its point of no return.
14. HA does not replace backup.
15. RPO defines acceptable data loss; RTO defines acceptable recovery
    time.
16. Backup frequency should align with RPO.
17. Backup repositories should survive primary-platform failure.
18. Backup credentials and repositories require production security
    controls.
19. Backup job success does not prove restore success.
20. Restore drills must validate application behavior and data
    semantics.
21. TTL, Search, JSON, and vector workloads require workload-specific
    recovery validation.
22. Restore throughput must be sized for the actual dataset.
23. Recovery includes configuration, endpoints, security, and
    application validation---not only data.
24. Failed upgrades require evidence preservation and supported
    recovery, not random pod/PVC deletion.
25. Production lifecycle readiness requires compatibility, preflight,
    backup, restore evidence, rollback/recovery boundaries,
    observability, and tested runbooks together.

------------------------------------------------------------------------

# 109. References

Validate every compatibility claim, upgrade sequence, backup/restore
capability, downgrade restriction, and recovery procedure against the
exact deployed Redis Enterprise Kubernetes Operator version, Redis
Enterprise version, Kubernetes platform, and current official Redis
documentation.

Recommended documentation areas:

-   Redis Enterprise for Kubernetes
-   Redis Enterprise Kubernetes Operator upgrades
-   Redis Enterprise Kubernetes cluster upgrades
-   Redis Enterprise Kubernetes compatibility
-   Redis Enterprise backup and restore
-   Redis Enterprise database persistence
-   Redis Enterprise disaster recovery
-   Redis Enterprise Active-Active recovery considerations
-   Kubernetes version-skew policy
-   Kubernetes API deprecation guidance
-   Kubernetes CRDs
-   Kubernetes node maintenance
-   Kubernetes persistent storage
-   CSI/CNI provider upgrade documentation
-   GitOps platform maintenance and reconciliation documentation

------------------------------------------------------------------------

# Next Chapter

**Chapter 65 --- Redis Enterprise Active-Active CRDT Semantics &
Conflict Engineering**

Chapter 65 will move into the core of multi-region Active-Active
behavior: CRDT principles, concurrent writes, conflict resolution,
data-type semantics, causality, network partitions, convergence,
application design, key/data-model constraints, regional latency,
consistency expectations, failure injection, troubleshooting, runbooks,
and production acceptance.
