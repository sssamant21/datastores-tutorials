# Chapter 62 --- Redis Enterprise REC, REDB, RERC & REAADB Resource Administration

**Status:** Canonical\
**Track:** Redis Enterprise / Redis Software Production Engineering\
**Part:** Part 11 --- Advanced Kubernetes, Active-Active & Platform
Engineering\
**Level:** Advanced → Production Kubernetes Resource Administration\
**Audience:** SREs, DBREs, Platform Engineers, Kubernetes
Administrators, Redis Administrators, GitOps Engineers\
**Lab type:** REC, REDB, RERC, REAADB discovery and administration,
manifests, lifecycle, scaling, persistence, security, status/conditions,
GitOps, deletion safety, failure injection, troubleshooting, runbooks,
and production acceptance

------------------------------------------------------------------------

# 1. Objective

Chapter 61 established the Redis Enterprise Kubernetes Operator model:

``` text
desired state
   |
custom resource
   |
Operator reconciliation
   |
Redis Enterprise + Kubernetes resources
```

This chapter moves into administration of the Redis Enterprise
custom-resource layer.

Conceptually:

``` text
RedisEnterpriseCluster (REC)
        |
        +-- RedisEnterpriseDatabase (REDB)
        |
        +-- supporting Kubernetes resources

Remote/Active-Active architecture
        |
        +-- RedisEnterpriseRemoteCluster (RERC)
        |
        +-- RedisEnterpriseActiveActiveDatabase (REAADB)
```

Exact API groups, versions, fields, capabilities, and lifecycle rules
depend on the installed Redis Enterprise Kubernetes Operator version.

By the end of this chapter, you should be able to:

-   discover installed REC, REDB, RERC, and REAADB APIs;
-   inspect resource schemas;
-   understand resource relationships;
-   create safe nonproduction manifests;
-   inspect status and conditions;
-   administer database resources through supported specs;
-   plan cluster/database scaling;
-   understand persistence and storage configuration boundaries;
-   manage security references safely;
-   understand remote-cluster relationships;
-   understand Active-Active database declarations;
-   use GitOps safely;
-   plan deletion and cleanup;
-   troubleshoot failed reconciliation;
-   execute production runbooks and acceptance gates.

------------------------------------------------------------------------

# 2. Core Production Principle

Custom resources are APIs.

Treat them with the same discipline as production infrastructure APIs:

``` text
versioned
validated
reviewed
tested
observable
recoverable
```

Do not copy a manifest from another cluster and assume its fields are
valid.

Always discover the installed schema.

------------------------------------------------------------------------

# Part 1 --- Resource Discovery

## 3. Discover Redis APIs

``` bash
kubectl api-resources | grep -i redis
```

Then:

``` bash
kubectl get crd | grep -i redis
```

Record:

``` text
resource
short name
API group
namespaced/cluster-scoped
kind
CRD version
```

------------------------------------------------------------------------

# Part 2 --- Verify Resource Names

## 4. Do Not Guess

Depending on installed version, resources may expose familiar short
names or full resource names.

Use:

``` bash
kubectl api-resources
```

as the source of truth for the cluster.

------------------------------------------------------------------------

# Part 3 --- Schema Discovery

## 5. kubectl explain

For each installed resource:

``` bash
kubectl explain <resource>
kubectl explain <resource>.spec
kubectl explain <resource>.status
```

Where needed:

``` bash
kubectl explain <resource>.spec.<field>
```

------------------------------------------------------------------------

# Part 4 --- Export CRD Schema

## 6. Deep Inspection

``` bash
kubectl get crd <crd-name> -o yaml
```

Review:

``` text
versions
served
storage
schema
validation
subresources
```

Do not modify the CRD manually.

------------------------------------------------------------------------

# Part 5 --- API Version

## 7. Manifest Contract

Every manifest includes:

``` yaml
apiVersion: <installed-api-group/version>
kind: <installed-kind>
```

Never hard-code an API version from a tutorial without verifying the
installed Operator.

------------------------------------------------------------------------

# Part 6 --- REC Purpose

## 8. RedisEnterpriseCluster

REC represents desired state for the Redis Enterprise cluster managed by
the Operator.

Conceptually it can govern cluster-level concerns such as:

``` text
node count
resource sizing
storage-related configuration
scheduling
security/integration settings
```

Exact supported fields are version-specific.

------------------------------------------------------------------------

# Part 7 --- REC Inventory

## 9. List

After discovering the actual resource name:

``` bash
kubectl get <rec-resource> -A
```

Inspect:

``` bash
kubectl get <rec-resource> <name> -n <namespace> -o yaml
```

------------------------------------------------------------------------

# Part 8 --- REC Baseline

## 10. Record

For every production REC, document:

``` text
name
namespace
Operator version
Redis Enterprise version
node count
CPU request/limit
memory request/limit
storage class
storage size
node placement
service configuration
security configuration
status
```

------------------------------------------------------------------------

# Part 9 --- REC Spec vs Runtime

## 11. Avoid Confusion

REC spec expresses requested cluster state.

Generated Kubernetes workloads represent implementation state.

Redis Enterprise itself has internal cluster state.

Troubleshooting may require all three layers.

------------------------------------------------------------------------

# Part 10 --- REC Status

## 12. Inspect

Record:

``` text
status
conditions
reason
message
generation-related fields
```

Do not use only pod status to declare REC healthy.

------------------------------------------------------------------------

# Part 11 --- REC Node Count

## 13. Scaling

A node-count change is not merely a Kubernetes replica-count change.

It can trigger Redis Enterprise topology/data placement operations.

Use supported REC scaling procedures.

------------------------------------------------------------------------

# Part 12 --- REC Scale-Out Preconditions

## 14. Before Change

Validate:

``` text
new node capacity
storage capacity
network
failure domains
license/subscription requirements
cluster health
backup/recovery
```

------------------------------------------------------------------------

# Part 13 --- REC Scale-Out Observation

## 15. Monitor

During an approved scale-out:

``` text
REC conditions
Operator logs
pods
PVCs
Redis Enterprise health
database placement
CPU/memory
network
application P99
```

------------------------------------------------------------------------

# Part 14 --- REC Scale-In

## 16. Higher Risk

Removing cluster capacity can require data movement.

Before scale-in verify:

``` text
remaining capacity
N-1
database placement
storage
rebalancing
failure-domain resilience
```

Never reduce nodes merely because Kubernetes nodes look underutilized.

------------------------------------------------------------------------

# Part 15 --- REC Resource Sizing

## 17. CPU and Memory

Kubernetes resource requests influence:

``` text
scheduling
node capacity
QoS behavior
```

Redis Enterprise sizing must also satisfy database workload and failure
headroom.

------------------------------------------------------------------------

# Part 16 --- REC Storage

## 18. Persistent Storage

Where configured, understand:

``` text
StorageClass
PVC behavior
capacity
topology
expansion support
performance
```

Use only supported storage changes.

------------------------------------------------------------------------

# Part 17 --- Storage Expansion

## 19. Not Just YAML

Before changing storage capacity:

``` text
verify Redis support
verify StorageClass expansion
verify CSI support
verify filesystem/device behavior
verify rollback limitations
```

------------------------------------------------------------------------

# Part 18 --- REC Scheduling

## 20. Placement

Review supported:

``` text
node selectors
affinity
anti-affinity
tolerations
topology
```

Do not create placement rules that prevent quorum/resilience or
scheduling.

------------------------------------------------------------------------

# Part 19 --- REC Upgrade

## 21. Controlled Lifecycle

Cluster-version changes require:

``` text
compatibility review
Operator compatibility
release notes
backup/recovery readiness
nonproduction qualification
change window
post-change validation
```

------------------------------------------------------------------------

# Part 20 --- REDB Purpose

## 22. RedisEnterpriseDatabase

REDB represents desired state for a Redis Enterprise database.

Conceptually:

``` text
REC = platform/cluster
REDB = database/service
```

------------------------------------------------------------------------

# Part 21 --- REDB Inventory

## 23. List

``` bash
kubectl get <redb-resource> -A
```

Inspect:

``` bash
kubectl get <redb-resource> <name> -n <namespace> -o yaml
```

------------------------------------------------------------------------

# Part 22 --- REDB Baseline

## 24. Record

For each production database:

``` text
name
namespace
REC reference/relationship
memory/capacity
replication/HA
persistence
eviction policy
TLS/security
endpoint
shards
modules/capabilities
status
owners
```

Only record fields relevant to the installed version.

------------------------------------------------------------------------

# Part 23 --- Minimal Manifest Pattern

## 25. Safe Skeleton

Use schema discovery first.

Conceptually:

``` yaml
apiVersion: <installed-api-version>
kind: <installed-redb-kind>
metadata:
  name: tutorial-db
  namespace: <lab-namespace>
spec:
  # fields verified with kubectl explain
```

Never paste guessed production values.

------------------------------------------------------------------------

# Part 24 --- Manifest Validation

## 26. Before Apply

Use available Kubernetes validation and organizational CI.

Example:

``` bash
kubectl apply --dry-run=server -f redb.yaml
```

Server-side dry run can detect schema/admission issues without
persisting the object.

------------------------------------------------------------------------

# Part 25 --- REDB Creation

## 27. Observe

After an approved nonproduction creation:

``` bash
kubectl apply -f redb.yaml
kubectl get <redb-resource> <name> -n <namespace> -o yaml
kubectl describe <redb-resource> <name> -n <namespace>
```

Observe until reconciliation reaches the expected state.

------------------------------------------------------------------------

# Part 26 --- REDB Endpoint

## 28. Application Contract

After provisioning, determine the supported connection endpoint.

Validate:

``` text
DNS
port
TLS
authentication
network policy
client connectivity
```

Do not scrape generated internals when a supported database endpoint is
provided.

------------------------------------------------------------------------

# Part 27 --- REDB Capacity

## 29. Change

Increasing database capacity may require:

``` text
additional cluster resources
placement changes
shard changes
```

Check REC headroom before changing REDB capacity.

------------------------------------------------------------------------

# Part 28 --- REDB Replication

## 30. HA

If database replication is required, verify:

``` text
replication configured
placement resilient
failover tested
remaining capacity sufficient
```

------------------------------------------------------------------------

# Part 29 --- REDB Persistence

## 31. Durability

Persistence configuration is a database-level reliability decision.

Document:

``` text
persistence mode
RPO expectation
performance impact
backup relationship
```

Use only supported values for the installed version.

------------------------------------------------------------------------

# Part 30 --- REDB Eviction

## 32. Data Semantics

Eviction configuration must match the application.

Classify database as:

``` text
cache
derived/rebuildable
durable state
```

before selecting eviction behavior.

------------------------------------------------------------------------

# Part 31 --- REDB TLS

## 33. Security

Validate:

``` text
endpoint TLS
certificate trust
client configuration
rotation process
```

Do not disable TLS merely to simplify troubleshooting.

------------------------------------------------------------------------

# Part 32 --- REDB Credentials

## 34. Secrets

Credential configuration can involve Kubernetes secrets and Redis
Enterprise security configuration.

Never embed plaintext production credentials in Git.

------------------------------------------------------------------------

# Part 33 --- REDB Capabilities

## 35. JSON/Search/Vector

If a database requires advanced capabilities:

``` text
verify support
verify client compatibility
verify memory/capacity
verify backup/restore
verify upgrade path
```

Chapter 59's compatibility process applies.

------------------------------------------------------------------------

# Part 34 --- REDB Safe Update

## 36. Workflow

Before changing a database spec:

``` text
1. capture current YAML/status.
2. identify exact field.
3. read installed schema.
4. review data/availability impact.
5. dry-run.
6. apply one reviewed change.
7. monitor reconciliation.
8. validate application.
```

------------------------------------------------------------------------

# Part 35 --- Immutable / Restricted Fields

## 37. Important

Some fields may not be safely mutable after creation.

Do not assume Kubernetes accepts every in-place database change.

Use schema and product documentation.

------------------------------------------------------------------------

# Part 36 --- REDB Deletion

## 38. Destructive Boundary

Deleting a database custom resource may delete or decommission the
underlying database depending on product semantics.

Before deletion:

``` text
confirm owner
confirm data disposition
confirm backup
confirm restore
confirm application disconnected
confirm retention requirement
```

------------------------------------------------------------------------

# Part 37 --- Finalizer Behavior

## 39. Observe

If deletion is pending:

``` bash
kubectl get <redb-resource> <name> -n <namespace> -o yaml
```

Inspect:

``` text
deletionTimestamp
finalizers
status
Operator logs
```

Never remove finalizers blindly.

------------------------------------------------------------------------

# Part 38 --- RERC Purpose

## 40. Remote Cluster Relationship

Where supported, a RedisEnterpriseRemoteCluster resource represents
information/relationship needed to reference another Redis Enterprise
Kubernetes cluster for capabilities such as Active-Active.

Exact semantics and fields are version-specific.

------------------------------------------------------------------------

# Part 39 --- RERC Discovery

## 41. Commands

``` bash
kubectl api-resources | grep -i remote
kubectl get crd | grep -i remote
```

Then inspect:

``` bash
kubectl explain <rerc-resource>
kubectl explain <rerc-resource>.spec
```

------------------------------------------------------------------------

# Part 40 --- RERC Security

## 42. Trust Boundary

Remote-cluster configuration may involve:

``` text
cluster identity
endpoint
credentials/secrets
TLS trust
network connectivity
```

Treat it as cross-cluster security configuration.

------------------------------------------------------------------------

# Part 41 --- RERC Network

## 43. Validate

Before creating the relationship:

``` text
DNS
routing
firewall
NetworkPolicy
load balancer
TLS
latency
```

must meet product requirements.

------------------------------------------------------------------------

# Part 42 --- RERC Failure

## 44. Troubleshoot

If remote relationship fails:

``` text
inspect resource status
inspect Operator logs
test approved network path
validate endpoint
validate TLS
validate credentials
validate remote cluster health
```

------------------------------------------------------------------------

# Part 43 --- REAADB Purpose

## 45. Active-Active Database

Where supported, RedisEnterpriseActiveActiveDatabase represents desired
state for an Active-Active database spanning participating Redis
Enterprise clusters.

Conceptually:

``` text
Cluster A <----> Cluster B
     \            /
      \-- Active-Active DB
```

------------------------------------------------------------------------

# Part 44 --- Active-Active Is Not Simple Replication

## 46. Semantics

Active-Active involves:

``` text
multi-region writes
CRDT/data-type semantics
conflict behavior
network partitions
regional recovery
```

Chapter 65 will cover these semantics in depth.

------------------------------------------------------------------------

# Part 45 --- REAADB Discovery

## 47. Commands

``` bash
kubectl api-resources | grep -i active
kubectl get crd | grep -i active
```

Then:

``` bash
kubectl explain <reaadb-resource>
kubectl explain <reaadb-resource>.spec
```

------------------------------------------------------------------------

# Part 46 --- Participating Clusters

## 48. Inventory

Document:

``` text
cluster names
regions
namespaces
remote-cluster resources
network paths
latency
Redis versions
Operator versions
```

------------------------------------------------------------------------

# Part 47 --- Version Compatibility

## 49. Gate

Before Active-Active creation or upgrade, verify the exact supported
matrix across participating clusters.

Do not assume independently supported versions are supported together.

------------------------------------------------------------------------

# Part 48 --- REAADB Capacity

## 50. Multi-Region

Each participating site must have enough capacity for its supported
role.

Include:

``` text
data
metadata
replication/sync
failure headroom
regional traffic shift
```

------------------------------------------------------------------------

# Part 49 --- Regional Traffic

## 51. Application Layer

Active-Active database availability does not automatically route
application traffic correctly.

Coordinate:

``` text
DNS/GSLB
application endpoints
regional failover
client retry
```

------------------------------------------------------------------------

# Part 50 --- GitOps Layout

## 52. Example

``` text
redis/
  cluster/
    rec.yaml
  databases/
    app-a-redb.yaml
    app-b-redb.yaml
  active-active/
    remote-cluster-a.yaml
    remote-cluster-b.yaml
    global-db.yaml
```

Adapt to organizational repository standards.

------------------------------------------------------------------------

# Part 51 --- Environment Overlays

## 53. Avoid Copy/Paste Drift

Use controlled environment-specific values for:

``` text
namespace
capacity
storage
endpoints
secrets references
region
```

Do not copy production secrets into staging manifests.

------------------------------------------------------------------------

# Part 52 --- Policy as Code

## 54. Validate

CI/GitOps can enforce standards such as:

``` text
approved namespaces
required labels
resource ranges
approved storage classes
required TLS
change ownership
```

------------------------------------------------------------------------

# Part 53 --- Labels and Annotations

## 55. Governance

Where safe and supported, use metadata for:

``` text
application
owner
environment
cost center
criticality
change ticket
```

Do not place secrets in labels/annotations.

------------------------------------------------------------------------

# Part 54 --- Backup Before High-Risk Change

## 56. Rule

Before destructive or difficult-to-reverse database changes, validate:

``` text
backup current
restore procedure known
RPO acceptable
recovery environment available
```

------------------------------------------------------------------------

# Part 55 --- Change Evidence

## 57. Capture

For a production CR change:

``` text
Git commit
change ticket
before spec
target spec
dry-run result
approval
reconciliation evidence
application validation
```

------------------------------------------------------------------------

# Part 56 --- Drift

## 58. Detect

Compare:

``` text
Git desired state
Kubernetes spec
Redis Enterprise runtime
```

Not every runtime difference is configuration drift, but every
unexplained spec difference should be investigated.

------------------------------------------------------------------------

# Part 57 --- Resource Ownership

## 59. Define

For each resource class:

``` text
who can propose?
who can approve?
who can apply?
who owns data?
who owns recovery?
```

------------------------------------------------------------------------

# Part 58 --- Quotas

## 60. Guardrail

Database self-service should have boundaries.

Examples:

``` text
maximum memory
approved persistence
approved replication
approved storage
approved capabilities
```

------------------------------------------------------------------------

# Part 59 --- Admission Policy

## 61. Guardrail

Where organizational tooling supports it, reject dangerous or
nonstandard manifests before reconciliation.

Examples:

``` text
unapproved namespace
missing owner
unsupported storage class
excessive capacity
```

Do not create policy that conflicts with required Operator behavior.

------------------------------------------------------------------------

# Part 60 --- Production Readiness Before Apply

## 62. Ask

``` text
Is the API supported?
Is the field mutable?
Is capacity available?
Is data protected?
Is rollback possible?
Will GitOps accept it?
What does the Operator do next?
```

------------------------------------------------------------------------

# Part 61 --- Failure Scenario 1: Invalid REDB Field

## 63. Test

In a disposable lab manifest, use an invalid field/value.

Run:

``` bash
kubectl apply --dry-run=server -f invalid-redb.yaml
```

Expected:

``` text
validation/admission failure
```

------------------------------------------------------------------------

# Part 62 --- Failure Scenario 2: REDB Capacity \> Cluster Headroom

## 64. Tabletop / Lab

Model a database request larger than available REC capacity.

Validate:

``` text
capacity review catches it
alert/status is understandable
no production overcommit
```

------------------------------------------------------------------------

# Part 63 --- Failure Scenario 3: Unsupported Spec Change

## 65. Test

Use documentation/schema to identify a restricted/immutable change.

Verify the change process rejects or redirects it to the supported
migration workflow.

------------------------------------------------------------------------

# Part 64 --- Failure Scenario 4: Missing Secret

## 66. Lab

Use an isolated resource that references a nonexistent lab secret where
the installed API supports such a reference.

Observe:

``` text
status
events
Operator logs
```

Restore immediately.

------------------------------------------------------------------------

# Part 65 --- Failure Scenario 5: Remote Endpoint Unreachable

## 67. Lab/Tabletop

In a dedicated Active-Active lab, block or misconfigure only the test
remote endpoint.

Observe RERC/REAADB status and alerts.

Do not disrupt production regions.

------------------------------------------------------------------------

# Part 66 --- Failure Scenario 6: TLS Trust Failure

## 68. Lab

Use an isolated invalid test trust/certificate configuration.

Validate:

``` text
clear TLS failure
no silent downgrade
```

------------------------------------------------------------------------

# Part 67 --- Failure Scenario 7: GitOps Reversion

## 69. Test

Manually modify a harmless Git-managed CR field in nonproduction.

Observe GitOps restoring source-controlled desired state.

------------------------------------------------------------------------

# Part 68 --- Failure Scenario 8: Database Deletion Tabletop

## 70. Review

Before any real deletion, verify:

``` text
data owner
backup
restore
application disconnect
finalizer
retention
```

Use only disposable lab data for deletion testing.

------------------------------------------------------------------------

# Part 69 --- Failure Scenario 9: REC Scale-In Safety

## 71. Tabletop

Model removal of one node.

Calculate:

``` text
remaining CPU
remaining RAM
remaining storage
database placement
N-1 after change
```

Reject unsafe scale-in.

------------------------------------------------------------------------

# Part 70 --- Failure Scenario 10: Active-Active Region Loss

## 72. Lab/Tabletop

Simulate one test region becoming unavailable.

Validate:

``` text
database state
application routing
remaining capacity
rejoin plan
```

Detailed regional recovery comes later in Part 11.

------------------------------------------------------------------------

# Part 71 --- Troubleshooting Matrix

## 73. Common Problems

  Symptom                              Investigate
  ------------------------------------ ------------------------------------------------
  REC not Ready                        status, conditions, pods, storage, Operator
  REC scale stalls                     node capacity, PVC, placement, Redis health
  REDB not created                     schema, REC capacity, status, Operator
  REDB endpoint unavailable            service, DNS, TLS, NetworkPolicy
  REDB update rejected                 immutable/restricted field, schema
  REDB stuck deleting                  finalizer, Operator, underlying database
  RERC unhealthy                       remote endpoint, TLS, auth, network
  REAADB degraded                      participating clusters, remote links, capacity
  Git value keeps reverting            GitOps ownership
  manifest works in one cluster only   API/operator/version drift

------------------------------------------------------------------------

# Part 72 --- Runbook 1: REC Health

## 74. Procedure

``` text
1. inspect REC spec/status/conditions.
2. inspect Operator health/logs.
3. inspect Redis pods.
4. inspect PVC/storage.
5. inspect scheduling/events.
6. inspect Redis Enterprise cluster health.
7. validate database impact.
8. remediate supported root cause.
```

------------------------------------------------------------------------

# Part 73 --- Runbook 2: REC Scale-Out

## 75. Procedure

``` text
1. confirm capacity requirement.
2. validate infrastructure headroom.
3. validate storage/network/topology.
4. capture baseline.
5. change supported REC field.
6. monitor reconciliation/data movement.
7. validate databases/application SLO.
8. update capacity documentation.
```

------------------------------------------------------------------------

# Part 74 --- Runbook 3: REDB Provisioning

## 76. Procedure

``` text
1. validate schema/version.
2. validate REC capacity.
3. validate security/persistence.
4. server-side dry-run.
5. merge/apply through approved path.
6. monitor REDB status.
7. validate endpoint/client.
8. record ownership/runbook.
```

------------------------------------------------------------------------

# Part 75 --- Runbook 4: REDB Change

## 77. Procedure

``` text
1. capture current spec/status.
2. verify field mutability/support.
3. assess data/availability impact.
4. validate capacity.
5. dry-run.
6. apply one reviewed change.
7. monitor reconciliation.
8. validate application and update baseline.
```

------------------------------------------------------------------------

# Part 76 --- Runbook 5: REDB Deletion

## 78. Procedure

``` text
1. obtain data-owner approval.
2. disconnect application.
3. verify backup/restore.
4. verify retention/compliance.
5. execute supported deletion.
6. monitor finalizers/Operator.
7. verify underlying cleanup.
8. retain evidence.
```

------------------------------------------------------------------------

# Part 77 --- Runbook 6: RERC Failure

## 79. Procedure

``` text
1. inspect RERC status/conditions.
2. inspect Operator logs.
3. verify remote cluster health.
4. verify DNS/routing/firewall.
5. verify TLS.
6. verify credentials/secret references.
7. restore supported connectivity.
8. validate dependent Active-Active database.
```

------------------------------------------------------------------------

# Part 78 --- Runbook 7: REAADB Degraded

## 80. Procedure

``` text
1. identify affected participating cluster.
2. inspect REAADB status.
3. inspect RERC resources.
4. validate regional Redis health.
5. validate network/TLS.
6. validate remaining capacity/application routing.
7. follow supported recovery/rejoin.
8. validate convergence.
```

------------------------------------------------------------------------

# Part 79 --- Runbook 8: GitOps CR Drift

## 81. Procedure

``` text
1. identify Git revision.
2. capture live CR spec.
3. compare desired/live.
4. identify owning controller.
5. classify emergency/manual change.
6. reconcile approved state in Git.
7. sync.
8. validate Redis runtime.
```

------------------------------------------------------------------------

# Part 80 --- REC Inventory Template

## 82. Record

``` text
REC:
Namespace:
Operator version:
Redis Enterprise version:
Nodes:
CPU:
Memory:
StorageClass:
Storage/node:
Placement:
Failure domains:
Security:
Status:
Owner:
```

------------------------------------------------------------------------

# Part 81 --- REDB Inventory Template

## 83. Record

``` text
REDB:
Namespace:
Application:
Owner:
REC:
Capacity:
Replication:
Persistence:
Eviction:
TLS:
Endpoint:
Capabilities:
Backup:
RPO/RTO:
Status:
```

------------------------------------------------------------------------

# Part 82 --- Active-Active Inventory Template

## 84. Record

``` text
REAADB:
Application:
Owners:
Cluster A:
Region A:
RERC A:
Cluster B:
Region B:
RERC B:
Redis versions:
Operator versions:
Network path:
TLS:
Capacity/site:
Traffic routing:
Recovery plan:
```

------------------------------------------------------------------------

# Part 83 --- Change Template

## 85. Record

``` text
Resource kind:
Resource name:
Namespace:
Current generation:
Current spec:
Target change:
Schema/support evidence:
Capacity impact:
Data impact:
Availability impact:
Security impact:
Dry-run:
Backup:
Rollback/recovery:
Approval:
Validation:
```

------------------------------------------------------------------------

# Part 84 --- Production Acceptance

## 86. API / Governance

-   [ ] installed CRDs inventoried;
-   [ ] API versions documented;
-   [ ] schemas inspected;
-   [ ] owners assigned;
-   [ ] GitOps ownership defined;
-   [ ] policy/admission rules reviewed;
-   [ ] resource labels/metadata standardized.

## 87. REC

-   [ ] REC baseline documented;
-   [ ] node capacity validated;
-   [ ] storage validated;
-   [ ] placement/failure domains validated;
-   [ ] scale-out procedure tested;
-   [ ] scale-in safety reviewed;
-   [ ] upgrade procedure documented;
-   [ ] status/conditions monitored.

## 88. REDB

-   [ ] database baseline documented;
-   [ ] capacity validated;
-   [ ] replication validated;
-   [ ] persistence aligned with RPO;
-   [ ] eviction aligned with data semantics;
-   [ ] TLS/auth validated;
-   [ ] endpoint/client validated;
-   [ ] backup/restore validated;
-   [ ] safe-update process tested;
-   [ ] deletion safeguards documented.

## 89. Active-Active Resources

-   [ ] RERC APIs/fields validated;
-   [ ] remote connectivity validated;
-   [ ] TLS/auth validated;
-   [ ] REAADB APIs/fields validated;
-   [ ] participating-cluster compatibility validated;
-   [ ] per-site capacity validated;
-   [ ] application traffic routing documented;
-   [ ] regional recovery/rejoin procedure documented.

## 90. Operational Acceptance

-   [ ] server-side dry-run included in workflow;
-   [ ] before/after evidence retained;
-   [ ] drift detection configured;
-   [ ] ten failure scenarios completed;
-   [ ] eight runbooks reviewed;
-   [ ] production acceptance completed.

------------------------------------------------------------------------

# 91. Knowledge Validation

1.  Why should custom resources be treated as production APIs?
2.  How do you discover installed Redis custom resources?
3.  Why should `kubectl explain` precede manifest authoring?
4.  What does REC represent?
5.  What does REDB represent?
6.  Why is REC scaling different from changing a normal replica count?
7.  What should be checked before REC scale-out?
8.  Why is REC scale-in higher risk?
9.  Why must storage expansion be validated across Redis, CSI, and
    StorageClass?
10. What belongs in a REDB baseline?
11. Why use server-side dry run?
12. Why should application endpoints come from supported database
    interfaces?
13. Why check REC headroom before increasing REDB capacity?
14. Why must persistence align with RPO?
15. Why must eviction align with data semantics?
16. Why should TLS not be disabled just to troubleshoot?
17. Why must field mutability be checked before a REDB update?
18. Why is REDB deletion a destructive boundary?
19. What role do finalizers play in deletion?
20. What does RERC represent conceptually?
21. Which dependencies can break a remote-cluster relationship?
22. What does REAADB represent?
23. Why is Active-Active more than ordinary replication?
24. Why must participating-cluster versions be checked together?
25. Why must each Active-Active site have failure headroom?
26. Why does Active-Active not automatically solve application traffic
    routing?
27. Why should GitOps own desired custom resources?
28. Why should high-risk CR changes require backup/recovery evidence?
29. Why compare Git, Kubernetes spec, and Redis runtime during drift
    analysis?
30. What must pass before custom-resource administration is
    production-ready?

------------------------------------------------------------------------

# 92. Hands-On Acceptance Checklist

-   [ ] Discovered Redis API resources.
-   [ ] Listed Redis CRDs.
-   [ ] Inspected installed API versions.
-   [ ] Used `kubectl explain` for REC.
-   [ ] Used `kubectl explain` for REDB.
-   [ ] Discovered RERC where installed.
-   [ ] Discovered REAADB where installed.
-   [ ] Built REC inventory.
-   [ ] Built REDB inventory.
-   [ ] Inspected REC status/conditions.
-   [ ] Inspected REDB status/conditions.
-   [ ] Reviewed REC capacity and placement.
-   [ ] Reviewed REC storage.
-   [ ] Modeled REC scale-out.
-   [ ] Modeled REC scale-in.
-   [ ] Created safe REDB lab manifest.
-   [ ] Ran server-side dry run.
-   [ ] Observed REDB reconciliation.
-   [ ] Validated endpoint/TLS/auth.
-   [ ] Reviewed REDB persistence/eviction.
-   [ ] Tested one safe REDB update.
-   [ ] Reviewed deletion/finalizers.
-   [ ] Built Active-Active resource inventory.
-   [ ] Validated remote network/TLS dependencies.
-   [ ] Documented GitOps ownership.
-   [ ] Tested GitOps reversion in nonproduction.
-   [ ] Completed ten failure scenarios.
-   [ ] Completed eight runbooks.
-   [ ] Completed production acceptance.

------------------------------------------------------------------------

# 93. Cleanup

Remove only Chapter 62 disposable lab resources.

Before deleting any REDB/REC/RERC/REAADB resource, confirm it was
explicitly created as disposable lab state.

Verify:

``` text
resource ownership
data disposition
finalizers
dependent resources
GitOps source
```

Then confirm:

``` bash
kubectl get <redis-resources> -A
kubectl get pods -A
kubectl get pvc -A
```

Ensure:

``` text
no lab database remains
no temporary secret remains
no temporary remote-cluster relationship remains
no temporary policy remains
GitOps synchronized
production resources unchanged
```

Never use production REC/REDB deletion as a tutorial cleanup mechanism.

------------------------------------------------------------------------

# 94. Key Takeaways

1.  REC, REDB, RERC, and REAADB are production APIs managed through
    Kubernetes reconciliation.
2.  Discover installed APIs and schemas rather than copying assumed
    manifests.
3.  REC governs Redis Enterprise cluster-level desired state.
4.  REDB governs database-level desired state.
5.  REC scaling can trigger real Redis topology and data-placement work.
6.  Scale-out requires infrastructure and failure-domain headroom.
7.  Scale-in requires careful remaining-capacity and resilience
    analysis.
8.  Storage changes depend on Redis, Kubernetes, CSI, and StorageClass
    capabilities.
9.  REDB capacity must fit within REC capacity.
10. Persistence must align with the database's RPO.
11. Eviction must align with cache/durable-data semantics.
12. Security references and credentials must remain outside plaintext
    Git.
13. Use server-side dry run before applying reviewed manifests.
14. Not every custom-resource field is safely mutable.
15. REDB deletion can be destructive and requires data-owner approval.
16. Finalizers are lifecycle controls, not obstacles to remove casually.
17. RERC represents a cross-cluster trust/connectivity relationship
    where supported.
18. Remote-cluster health depends on network, TLS, credentials, and both
    clusters.
19. REAADB declares Active-Active database intent where supported.
20. Active-Active requires explicit CRDT/conflict and regional-failure
    understanding.
21. Participating clusters require a supported joint compatibility
    matrix.
22. Each region needs capacity for expected degraded/failover behavior.
23. Application traffic routing remains an application/platform
    responsibility.
24. GitOps should provide reviewable desired state and drift control.
25. Production readiness requires API governance, capacity, durability,
    security, recovery, reconciliation, and runbook evidence together.

------------------------------------------------------------------------

# 95. References

Validate all API names, API versions, fields, mutability rules, scaling
behavior, persistence options, security references, RERC/REAADB
behavior, deletion semantics, and upgrade requirements against the exact
deployed Redis Enterprise Kubernetes Operator version and current
official Redis documentation.

Recommended documentation areas:

-   Redis Enterprise for Kubernetes
-   Redis Enterprise Kubernetes Operator
-   RedisEnterpriseCluster
-   RedisEnterpriseDatabase
-   RedisEnterpriseRemoteCluster
-   RedisEnterpriseActiveActiveDatabase
-   Redis Enterprise Active-Active on Kubernetes
-   Redis Enterprise Kubernetes persistence
-   Redis Enterprise Kubernetes security
-   Redis Enterprise Kubernetes scaling
-   Redis Enterprise Kubernetes upgrades
-   Kubernetes CustomResourceDefinitions
-   Kubernetes server-side dry run
-   Kubernetes finalizers
-   Kubernetes GitOps operational practices

------------------------------------------------------------------------

# Next Chapter

**Chapter 63 --- Redis Enterprise Kubernetes Storage, Networking &
Failure Engineering**

Chapter 63 will go deeper into the infrastructure beneath the Operator:
StorageClass and CSI behavior, persistent-volume topology,
IOPS/throughput/latency, CNI and DNS, services/load balancers,
NetworkPolicy, node/zone failures, volume failures, packet loss, DNS
failures, capacity exhaustion, observability, failure injection,
troubleshooting, runbooks, and production acceptance.
