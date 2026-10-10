# Chapter 61 --- Redis Enterprise Kubernetes Operator Architecture & Reconciliation

**Status:** Canonical\
**Track:** Redis Enterprise / Redis Software Production Engineering\
**Part:** Part 11 --- Advanced Kubernetes, Active-Active & Platform
Engineering\
**Level:** Advanced → Production Kubernetes Operator Engineering\
**Audience:** SREs, DBREs, Platform Engineers, Kubernetes
Administrators, Redis Administrators, Cloud Engineers, GitOps Engineers\
**Lab type:** Operator architecture, CRDs, reconciliation, REC/REDB
relationships, RBAC, scheduling, storage, networking, GitOps, upgrades,
observability, failure injection, troubleshooting, runbooks, and
production acceptance

------------------------------------------------------------------------

# 1. Objective

Running Redis Enterprise on Kubernetes introduces a control-plane
relationship:

``` text
Kubernetes desired state
        |
Redis Enterprise Operator
        |
Redis Enterprise custom resources
        |
Redis Enterprise cluster/databases
        |
compute + storage + networking + secrets
```

The Operator continuously reconciles declared state with observed state:

``` text
observe -> compare -> act -> observe again
```

By the end of this chapter, you should be able to:

-   explain Redis Enterprise Kubernetes Operator architecture;
-   explain reconciliation and eventual convergence;
-   discover installed Redis CRDs and API resources;
-   understand REC and REDB relationships;
-   inspect spec, status, conditions, events, owner references, and
    finalizers;
-   understand Operator RBAC and namespace scope;
-   diagnose scheduling, storage, networking, and secret dependencies;
-   operate safely with GitOps;
-   plan Operator and Kubernetes upgrades;
-   troubleshoot failed reconciliation;
-   monitor control-plane and Redis data-plane health separately;
-   execute production runbooks and acceptance checks.

------------------------------------------------------------------------

# 2. Core Production Principle

Do not manage Operator-owned Redis resources as ordinary hand-maintained
Kubernetes objects.

Use:

``` text
supported desired-state change
        |
Operator reconciliation
        |
observe resulting state
```

Direct edits to generated resources may be overwritten, reverted, or
unsupported.

------------------------------------------------------------------------

# Part 1 --- Operator Control Loop

## 3. Desired State

A custom resource can declare intent such as:

``` text
cluster size
resources
storage
security
database configuration
```

## 4. Observed State

Actual state can include:

``` text
pods
services
PVCs
secrets
Redis Enterprise processes
database state
```

## 5. Reconciliation

Conceptually:

``` text
watch resource/event
       |
read desired state
       |
read actual state
       |
difference?
  |          |
 no         yes
  |          |
status    perform supported action
              |
           update status
```

## 6. Idempotency

Reconciliation may run repeatedly. Repeated execution should converge
rather than create uncontrolled duplicate state.

## 7. Eventual Convergence

A requested state can require time for:

``` text
scheduling
image pulls
volume provisioning
Redis cluster operations
database placement
service changes
```

Use status and events to understand progress.

------------------------------------------------------------------------

# Part 2 --- CRDs and Redis Resources

## 8. CRD

A CustomResourceDefinition extends the Kubernetes API.

``` bash
kubectl get crd
kubectl get crd | grep -i redis
```

## 9. API Discovery

Never guess installed resource names:

``` bash
kubectl api-resources | grep -i redis
```

## 10. REC

`RedisEnterpriseCluster` commonly represents the Redis Enterprise
cluster managed through the Operator.

## 11. REDB

`RedisEnterpriseDatabase` commonly represents a database managed within
that cluster.

Conceptually:

``` text
REC
 |
 +-- Redis Enterprise cluster
      |
      +-- REDB A
      +-- REDB B
```

Additional CRDs can support other capabilities. Chapter 62 covers REC,
REDB, RERC, and REAADB administration in depth.

## 12. Explain Installed Schema

``` bash
kubectl explain <resource>
kubectl explain <resource>.spec
```

Use fields supported by the installed Operator release.

------------------------------------------------------------------------

# Part 3 --- Operator Deployment

## 13. Locate the Operator

``` bash
kubectl get deploy -A | grep -i redis
kubectl get pods -A | grep -i redis
```

Record actual namespace, deployment, image, and version.

## 14. Pod Health

Do not stop at `Running`.

Check:

``` text
Ready
restarts
events
logs
```

## 15. Logs

``` bash
kubectl logs -n <operator-namespace> deploy/<operator-deployment>
```

Useful patterns:

``` text
reconcile
error
forbidden
timeout
conflict
validation
```

## 16. Namespace Scope

Record:

``` text
Operator namespace
watched namespaces
Redis resource namespaces
```

Exact watch behavior depends on installation/version.

------------------------------------------------------------------------

# Part 4 --- RBAC

## 17. Service Account

Inspect:

``` bash
kubectl get serviceaccount -n <namespace>
kubectl get role,rolebinding -n <namespace>
kubectl get clusterrole,clusterrolebinding
```

Identify the actual Operator identity.

## 18. Least Privilege

Use vendor-supported permissions. Do not arbitrarily remove required
Operator access or grant unrelated privileges.

## 19. Forbidden Error

If logs show:

``` text
forbidden
```

check:

``` text
service account
role/clusterrole
binding
verb
resource
namespace
```

------------------------------------------------------------------------

# Part 5 --- Spec, Status and Conditions

## 20. Inspect Resource

``` bash
kubectl get <resource> <name> -n <namespace> -o yaml
kubectl describe <resource> <name> -n <namespace>
```

## 21. Spec

``` text
spec = requested desired state
```

## 22. Status

``` text
status = controller-reported state/progress
```

Do not manually edit status.

## 23. Conditions

Record:

``` text
type
status
reason
message
transition time
```

Exact condition names vary by version.

## 24. Generation

Kubernetes metadata such as `generation` and `resourceVersion` helps
correlate changes. Where the controller exposes observed-generation
information, use it to determine whether the current spec has been
processed.

------------------------------------------------------------------------

# Part 6 --- Events and Ownership

## 25. Events

``` bash
kubectl get events -n <namespace> --sort-by=.lastTimestamp
```

Events can reveal:

``` text
scheduling
storage
image
admission
reconciliation
```

problems.

## 26. Owner References

Inspect generated objects for:

``` yaml
metadata:
  ownerReferences:
```

This helps map lifecycle ownership.

## 27. Finalizers

Inspect:

``` yaml
metadata:
  finalizers:
```

Finalizers can prevent deletion until cleanup completes.

Do not remove finalizers blindly to force deletion.

------------------------------------------------------------------------

# Part 7 --- Scheduling Dependencies

## 28. Scheduler Boundary

The Operator requests workloads, but Kubernetes scheduling still depends
on:

``` text
CPU/memory requests
node capacity
taints/tolerations
affinity
anti-affinity
topology
```

## 29. Pending Pod

``` bash
kubectl describe pod <pod> -n <namespace>
```

Read scheduler events before changing anything.

## 30. Taints

A pod can remain Pending if eligible nodes are tainted without matching
tolerations.

## 31. Affinity

Strong anti-affinity can protect resilience while also making placement
impossible if insufficient nodes/failure domains exist.

## 32. Failure Domains

Design supported placement across:

``` text
nodes
zones
racks
```

according to Redis Enterprise guidance.

------------------------------------------------------------------------

# Part 8 --- Storage Dependencies

## 33. Inventory

``` bash
kubectl get storageclass
kubectl get pvc -n <namespace>
kubectl get pv
```

## 34. PVC Pending

Investigate:

``` text
StorageClass
CSI driver
quota
capacity
access mode
topology
```

## 35. Storage/Scheduling Interaction

Volume topology can constrain pod placement.

A scheduling problem can originate in storage binding.

## 36. Performance

`Bound` does not mean fast enough.

Production storage must satisfy required:

``` text
IOPS
throughput
P95/P99 latency
```

------------------------------------------------------------------------

# Part 9 --- Networking

## 37. Services

``` bash
kubectl get svc -n <namespace>
kubectl get endpoints -n <namespace>
```

Use EndpointSlice inspection where appropriate.

## 38. DNS

From an approved diagnostic workload:

``` bash
getent hosts <service>
```

## 39. NetworkPolicy

``` bash
kubectl get networkpolicy -A
```

A healthy service can still be unreachable because of policy.

## 40. Load Balancers / Routes

Where used, validate:

``` text
service type
cloud load balancer
DNS
firewall/security groups
TLS
```

------------------------------------------------------------------------

# Part 10 --- Secrets and Certificates

## 41. Secrets

Never:

``` text
commit secrets to Git
paste decoded secrets into tickets
log credentials
```

## 42. Rotation

Determine whether a secret/certificate update:

``` text
is watched automatically
requires resource reconciliation
requires restart
requires explicit Redis operation
```

Test exact version behavior.

## 43. Certificate Expiry

Monitor expiration and rehearse rotation before production expiry
events.

------------------------------------------------------------------------

# Part 11 --- Safe Changes

## 44. Change the Supported Control Surface

A CR spec change can trigger:

``` text
scale
pod changes
storage/configuration work
database operations
security changes
```

Understand expected reconciliation before applying.

## 45. One Change at a Time

For high-impact operations, isolate variables where practical.

Capture:

``` text
before state
change
events
status transition
after state
```

## 46. Manual Generated-Resource Edits

Avoid direct edits to Operator-generated workloads unless vendor
guidance explicitly calls for them.

------------------------------------------------------------------------

# Part 12 --- GitOps

## 47. Nested Controllers

``` text
Git
 |
GitOps controller
 |
Redis custom resource
 |
Redis Operator
 |
generated state
```

Two controllers are reconciling different layers.

## 48. Ownership

A clean model is:

``` text
GitOps owns declared custom resources
Redis Operator owns supported generated resources
```

## 49. Drift

Expected status/runtime fields should not cause constant GitOps
conflict.

But do not suppress meaningful desired-state drift.

## 50. Manual Change

If Git is authoritative, a manual `kubectl edit` can be reverted.

Emergency changes need a break-glass process and subsequent
source-control reconciliation.

## 51. Git Revert

A Git revert changes desired configuration.

It does not guarantee reversal of a completed data migration or
destructive database action.

------------------------------------------------------------------------

# Part 13 --- Reconciliation Troubleshooting

## 52. Correct Order

When a CR does not converge:

``` text
1. inspect spec/status
2. inspect conditions
3. inspect events
4. inspect generated objects
5. inspect Operator logs
6. inspect scheduler/storage/network/RBAC dependencies
```

Do not start by deleting random pods.

## 53. Operator Restart

Restarting the Operator does not repair:

``` text
invalid spec
missing permission
missing storage
unschedulable workload
network policy
unsupported configuration
```

Find the root cause first.

------------------------------------------------------------------------

# Part 14 --- Control Plane vs Data Plane

## 54. Distinguish

``` text
Operator = control plane
Redis Enterprise database = data plane
```

Temporary Operator unavailability may stop reconciliation while existing
Redis traffic continues, depending on the failure.

Monitor both independently.

## 55. Operator Availability

Use only the supported Operator availability model. Do not manually
create competing active controllers.

------------------------------------------------------------------------

# Part 15 --- Image Management

## 56. Pull Failures

Symptoms:

``` text
ErrImagePull
ImagePullBackOff
```

Investigate:

``` text
image/tag
registry
imagePullSecret
network
registry policy
```

## 57. Version Pinning

Track and review:

``` text
Operator image/version
Redis Enterprise image/version
```

Avoid unreviewed floating-version behavior.

------------------------------------------------------------------------

# Part 16 --- Operator Upgrade

## 58. Pre-Upgrade

Review:

``` text
release notes
CRD changes
Kubernetes compatibility
Redis Enterprise compatibility
upgrade order
known issues
rollback/recovery
```

## 59. CRD Changes

CRD upgrades can affect:

``` text
validation
new/deprecated fields
stored objects
conversion behavior
```

Follow vendor procedure.

## 60. Upgrade Order

Do not guess the order among:

``` text
CRDs
Operator
Redis Enterprise cluster
databases
```

Use documentation for the exact source and target versions.

## 61. Capture Evidence

Before change, capture non-secret state such as:

``` bash
kubectl get crd
kubectl get <redis-resources> -A
kubectl get pods -A
kubectl get pvc -A
```

## 62. Post-Upgrade

Validate:

``` text
Operator ready
CRDs established
CRs readable
reconciliation healthy
REC healthy
REDB healthy
pods ready
PVCs healthy
services/endpoints healthy
application tests pass
```

------------------------------------------------------------------------

# Part 17 --- Kubernetes Upgrade

## 63. Compatibility Gate

Before Kubernetes upgrade, verify compatibility across:

``` text
Kubernetes
Redis Enterprise Operator
Redis Enterprise
CNI
CSI
```

## 64. Node Drain

Node maintenance can evict Redis workloads.

Validate:

``` text
redundancy
capacity
PDB
placement
recovery
```

## 65. PDB

``` bash
kubectl get pdb -A
```

Do not bypass disruption protection casually.

------------------------------------------------------------------------

# Part 18 --- Cluster Autoscaling and Quotas

## 66. Autoscaler

Stateful databases require explicit disruption/capacity design.

Do not assume generic scale-down behavior is automatically safe.

## 67. ResourceQuota

``` bash
kubectl get resourcequota -n <namespace>
```

Quota can block:

``` text
pods
CPU
memory
PVCs
```

## 68. LimitRange

``` bash
kubectl get limitrange -n <namespace>
```

Defaults/limits can alter requested resources.

------------------------------------------------------------------------

# Part 19 --- Security Policies

## 69. Pod Security

Admission/security policies can reject Operator-created pods because of:

``` text
user/group
capabilities
volume permissions
seccomp
```

Use supported security requirements.

## 70. Audit

Use Kubernetes audit history and Git history to determine:

``` text
who changed desired state
what changed
when
through which controller
```

------------------------------------------------------------------------

# Part 20 --- Observability

## 71. Operator Layer

Where supported, monitor:

``` text
controller availability
reconciliation errors
work queue/controller metrics
```

## 72. Kubernetes Layer

Monitor:

``` text
pod readiness
restarts
Pending pods
PVC status
node pressure
events
```

## 73. Redis Layer

Monitor:

``` text
database availability
latency
CPU
memory
connections
replication
persistence
```

## 74. Correlate

Example:

``` text
REDB degraded
+ pod Pending
+ PVC Pending
```

points toward a different cause than:

``` text
REDB degraded
+ all pods Ready
+ Redis memory pressure
```

------------------------------------------------------------------------

# Part 21 --- Hands-On Discovery Lab

## 75. Discover

``` bash
kubectl api-resources | grep -i redis
kubectl get crd | grep -i redis
kubectl get deploy -A | grep -i redis
kubectl get pods -A | grep -i redis
```

Record actual names.

## 76. Inspect REC

``` bash
kubectl get <rec-resource> -A
kubectl get <rec-resource> <name> -n <namespace> -o yaml
kubectl describe <rec-resource> <name> -n <namespace>
```

Record:

``` text
spec
status
conditions
events
```

## 77. Inspect REDB

``` bash
kubectl get <redb-resource> -A
kubectl get <redb-resource> <name> -n <namespace> -o yaml
```

## 78. Map Ownership

Map one approved nonproduction resource:

``` text
CR
 -> generated workload
 -> pod
 -> service
 -> PVC
```

Inspect owner references.

## 79. Observe Reconciliation

Make one supported, reversible change to an isolated nonproduction
custom resource.

Observe:

``` text
generation
status
conditions
events
Operator logs
generated-resource changes
```

Restore baseline.

------------------------------------------------------------------------

# Part 22 --- Failure Scenario 1: Invalid Spec

## 80. Test

Apply an intentionally invalid disposable manifest.

Expected:

``` text
schema/admission rejection
clear error
no partial production change
```

------------------------------------------------------------------------

# Part 23 --- Failure Scenario 2: Unschedulable Workload

## 81. Test

In an isolated lab, use an impossible scheduling constraint where safe.

Observe:

``` text
Pending
scheduler events
CR status
```

Restore baseline.

------------------------------------------------------------------------

# Part 24 --- Failure Scenario 3: Missing StorageClass

## 82. Test

Use a disposable manifest referencing a nonexistent StorageClass.

Observe PVC and events.

Do not alter production database storage.

------------------------------------------------------------------------

# Part 25 --- Failure Scenario 4: RBAC Denial

## 83. Test

Use a tabletop or isolated service account.

Validate:

``` text
forbidden
```

is visible and diagnosable.

Do not break production Operator RBAC.

------------------------------------------------------------------------

# Part 26 --- Failure Scenario 5: Image Pull

## 84. Test

Use a disposable workload with an invalid image tag.

Observe:

``` text
ErrImagePull
ImagePullBackOff
events
```

------------------------------------------------------------------------

# Part 27 --- Failure Scenario 6: NetworkPolicy

## 85. Test

Use a dedicated lab namespace and disposable diagnostic workloads.

Validate blocked traffic and policy troubleshooting.

Do not isolate production Redis resources.

------------------------------------------------------------------------

# Part 28 --- Failure Scenario 7: GitOps Conflict

## 86. Test

Change a harmless Git-managed field manually in nonproduction.

Observe GitOps reconciliation restoring declared state.

Document ownership.

------------------------------------------------------------------------

# Part 29 --- Failure Scenario 8: Operator Restart

## 87. Test

Restart only an approved nonproduction Operator using the supported
procedure.

Observe:

``` text
existing data plane
controller recovery
reconciliation resume
```

------------------------------------------------------------------------

# Part 30 --- Failure Scenario 9: Node Drain

## 88. Test

Drain an approved nonproduction node using supported Redis/Kubernetes
procedures.

Measure:

``` text
pod movement
database availability
recovery
```

------------------------------------------------------------------------

# Part 31 --- Failure Scenario 10: Deletion Tabletop

## 89. Test

Do not delete production REC/REDB resources.

Review:

``` text
finalizers
deletion semantics
data impact
backup
recovery
```

Use only an isolated disposable resource if actual deletion testing is
required.

------------------------------------------------------------------------

# Part 32 --- Troubleshooting Matrix

## 90. Common Problems

  Symptom                          Investigate
  -------------------------------- -------------------------------------------
  CR rejected                      CRD/schema/admission
  CR exists, no progress           status, conditions, events, Operator logs
  Operator forbidden               service account/RBAC
  pod Pending                      capacity, taints, affinity, PVC
  PVC Pending                      StorageClass, CSI, quota, topology
  ImagePullBackOff                 image, registry, secret, network
  service has no endpoints         selectors, readiness, pods
  Git change reverts               GitOps/controller ownership
  resource stuck Terminating       finalizer, Operator, dependencies
  Operator healthy/app unhealthy   Redis data plane

------------------------------------------------------------------------

# Part 33 --- Runbook 1: Operator Health

## 91. Procedure

``` text
1. locate Operator deployment.
2. check readiness/restarts.
3. inspect deployment conditions.
4. inspect events.
5. inspect Operator logs.
6. inspect CR status.
7. validate Redis data plane separately.
8. escalate with evidence.
```

------------------------------------------------------------------------

# Part 34 --- Runbook 2: CR Not Reconciling

## 92. Procedure

``` text
1. capture CR spec/status.
2. inspect conditions.
3. inspect events.
4. inspect Operator logs.
5. inspect generated objects.
6. inspect scheduling/storage/network/RBAC.
7. correct supported desired state.
8. confirm convergence.
```

------------------------------------------------------------------------

# Part 35 --- Runbook 3: Pending Redis Pod

## 93. Procedure

``` text
1. describe pod.
2. read scheduler events.
3. check CPU/memory.
4. check taints/tolerations.
5. check affinity/topology.
6. check PVC binding.
7. correct capacity/constraint.
8. validate Redis health.
```

------------------------------------------------------------------------

# Part 36 --- Runbook 4: PVC Failure

## 94. Procedure

``` text
1. inspect PVC.
2. inspect events.
3. inspect StorageClass.
4. inspect CSI.
5. inspect quota/capacity.
6. inspect topology.
7. remediate through supported storage path.
8. validate Redis recovery.
```

------------------------------------------------------------------------

# Part 37 --- Runbook 5: GitOps Drift

## 95. Procedure

``` text
1. identify source of truth.
2. identify differing field/resource.
3. identify owning controller.
4. classify expected vs real drift.
5. correct Git/controller configuration.
6. avoid generated-resource edits.
7. sync.
8. validate Redis state.
```

------------------------------------------------------------------------

# Part 38 --- Runbook 6: Operator Upgrade

## 96. Procedure

``` text
1. review release/support documentation.
2. verify Kubernetes/Redis compatibility.
3. capture inventory/status.
4. validate backup/recovery.
5. test in nonproduction.
6. execute supported upgrade order.
7. run reconciliation validation.
8. validate applications/data plane.
```

------------------------------------------------------------------------

# Part 39 --- Runbook 7: Node Maintenance

## 97. Procedure

``` text
1. validate Redis redundancy.
2. validate capacity.
3. inspect PDB/placement.
4. enable enhanced monitoring.
5. cordon/drain using approved procedure.
6. monitor Redis/pod recovery.
7. restore node/capacity.
8. validate steady state.
```

------------------------------------------------------------------------

# Part 40 --- Runbook 8: Stuck Termination

## 98. Procedure

``` text
1. inspect deletion timestamp.
2. inspect finalizers.
3. inspect Operator health/logs.
4. inspect dependent resources.
5. identify failed cleanup.
6. follow vendor-supported recovery.
7. never remove finalizer blindly.
8. validate cleanup/data state.
```

------------------------------------------------------------------------

# Part 41 --- Operator Inventory Template

## 99. Record

``` text
Cluster:
Kubernetes version:
Operator version:
Operator namespace:
Operator image:
Service account:
Watch scope:
Redis Enterprise version:
CRDs:
REC resources:
REDB resources:
StorageClass:
Node pools:
CNI:
CSI:
GitOps controller:
```

------------------------------------------------------------------------

# Part 42 --- Reconciliation Incident Template

## 100. Record

``` text
Time:
Resource:
Namespace:
Generation:
Desired change:
Current status:
Conditions:
Events:
Operator error:
Pod state:
PVC state:
Network state:
Recent Git/change:
Impact:
Remediation:
Prevention:
```

------------------------------------------------------------------------

# Part 43 --- Change Template

## 101. Record

``` text
Custom resource:
Current spec:
Target spec:
Expected reconciliation:
Generated resources affected:
Data impact:
Capacity impact:
Storage impact:
Network impact:
Rollback:
Validation:
Approval:
```

------------------------------------------------------------------------

# Part 44 --- Production Acceptance

## 102. Operator/API

-   [ ] Operator version documented;
-   [ ] Kubernetes compatibility verified;
-   [ ] Redis Enterprise compatibility verified;
-   [ ] CRDs inventoried;
-   [ ] watch scope documented;
-   [ ] RBAC reviewed;
-   [ ] image/version management documented.

## 103. Reconciliation

-   [ ] spec/status model understood;
-   [ ] conditions included in troubleshooting;
-   [ ] events included in troubleshooting;
-   [ ] owner references understood;
-   [ ] finalizer behavior reviewed;
-   [ ] supported change workflow documented;
-   [ ] generated-resource ownership documented.

## 104. Kubernetes Dependencies

-   [ ] node capacity validated;
-   [ ] taints/tolerations validated;
-   [ ] affinity/topology validated;
-   [ ] StorageClass/CSI validated;
-   [ ] storage performance validated;
-   [ ] CNI/DNS validated;
-   [ ] NetworkPolicy requirements documented;
-   [ ] secret/certificate process reviewed.

## 105. Operations

-   [ ] GitOps ownership defined;
-   [ ] drift policy reviewed;
-   [ ] emergency-change procedure defined;
-   [ ] Operator upgrade tested;
-   [ ] Kubernetes upgrade compatibility process defined;
-   [ ] node-drain procedure tested;
-   [ ] monitoring/alerts defined;
-   [ ] ten failure scenarios completed;
-   [ ] eight runbooks reviewed.

------------------------------------------------------------------------

# 106. Knowledge Validation

1.  What problem does a Kubernetes Operator solve?
2.  What is desired state?
3.  What is observed state?
4.  What is reconciliation?
5.  Why should reconciliation be idempotent?
6.  What is a CRD?
7.  What is a custom resource?
8.  What does REC commonly represent?
9.  What does REDB commonly represent?
10. Why discover installed API resources rather than guess?
11. Why is `spec` different from `status`?
12. What can conditions communicate?
13. Why are Kubernetes events important?
14. What do owner references indicate?
15. Why are finalizers operationally important?
16. Why avoid casual edits to Operator-generated resources?
17. Why can a Redis pod remain Pending?
18. How can storage topology affect scheduling?
19. Why does a Bound PVC not prove adequate storage performance?
20. How can NetworkPolicy affect Redis?
21. Why can GitOps and an Operator fight?
22. Why does reverting Git not always reverse a data operation?
23. Why is restarting the Operator not the first troubleshooting step?
24. Why distinguish control-plane health from data-plane health?
25. Why are CRD upgrades significant?
26. Why must upgrade order come from vendor documentation?
27. Why qualify Kubernetes upgrades for Operator compatibility?
28. Why are PDBs important?
29. Why should finalizers not be removed blindly?
30. What must pass before production readiness?

------------------------------------------------------------------------

# 107. Hands-On Acceptance Checklist

-   [ ] Discovered Redis API resources.
-   [ ] Listed Redis CRDs.
-   [ ] Located Operator deployment/pods.
-   [ ] Recorded Operator image/version.
-   [ ] Inspected service account/RBAC.
-   [ ] Listed REC resources.
-   [ ] Inspected REC spec/status/conditions.
-   [ ] Listed REDB resources.
-   [ ] Inspected REDB spec/status/conditions.
-   [ ] Reviewed events.
-   [ ] Mapped owner references.
-   [ ] Reviewed finalizers.
-   [ ] Mapped workloads/services/PVCs.
-   [ ] Reviewed scheduling constraints.
-   [ ] Reviewed storage/CSI.
-   [ ] Reviewed services/DNS/NetworkPolicy.
-   [ ] Reviewed secret/certificate handling.
-   [ ] Documented GitOps ownership.
-   [ ] Observed one safe reconciliation.
-   [ ] Tested invalid-spec rejection.
-   [ ] Tested isolated scheduling failure.
-   [ ] Tested isolated storage failure.
-   [ ] Tested image-pull failure.
-   [ ] Tested GitOps drift.
-   [ ] Tested approved Operator restart.
-   [ ] Tested approved node maintenance.
-   [ ] Reviewed deletion semantics.
-   [ ] Completed ten failure scenarios.
-   [ ] Completed eight runbooks.
-   [ ] Completed production acceptance.

------------------------------------------------------------------------

# 108. Cleanup

Restore all Chapter 61 nonproduction lab changes.

Remove only disposable test resources created for this chapter.

Verify:

``` bash
kubectl get pods -A
kubectl get pvc -A
kubectl get events -A --sort-by=.lastTimestamp
```

Confirm:

``` text
Operator healthy
Redis CRs converged
Redis data plane healthy
temporary policies removed
temporary scheduling constraints removed
temporary workloads removed
GitOps synchronized
```

Do not delete REC/REDB resources as cleanup unless they were isolated
disposable lab resources and deletion semantics were explicitly
reviewed.

Do not manually remove finalizers merely to accelerate cleanup.

------------------------------------------------------------------------

# 109. Key Takeaways

1.  The Redis Enterprise Operator is a Kubernetes control plane for
    Redis desired state.
2.  Reconciliation continuously compares desired and observed state.
3.  CRDs define Redis-specific Kubernetes APIs.
4.  REC commonly represents the Redis Enterprise cluster; REDB
    represents a managed database.
5.  Discover installed APIs instead of assuming names or fields.
6.  `spec` expresses intent; `status` reports observed state.
7.  Conditions and events are primary troubleshooting evidence.
8.  Owner references and finalizers expose lifecycle relationships.
9.  Operator-generated resources should not be edited casually.
10. Reconciliation depends on scheduling, storage, networking, RBAC, and
    security.
11. Pending pods often indicate placement/capacity issues rather than
    Operator defects.
12. Bound storage does not prove adequate storage performance.
13. Network policies can block healthy services.
14. Secret and certificate rotation must be tested.
15. GitOps and the Redis Operator create nested reconciliation loops.
16. GitOps should own declared CRs while the Operator owns supported
    generated state.
17. A Git revert does not necessarily reverse data operations.
18. Restarting the Operator does not fix invalid desired state.
19. Operator health and Redis data-plane health are distinct.
20. CRD/Operator upgrades require compatibility review.
21. Kubernetes upgrades must be qualified against Redis support.
22. Node maintenance requires redundancy, capacity, placement, and PDB
    awareness.
23. Monitoring should correlate CR, Kubernetes, and Redis layers.
24. Finalizers should not be removed blindly.
25. Production readiness requires reconciliation, infrastructure
    dependencies, GitOps ownership, upgrade, resilience, observability,
    and runbook evidence.

------------------------------------------------------------------------

# 110. References

Validate CRD names, API versions, fields, RBAC, upgrade sequencing,
Kubernetes compatibility, storage requirements, and operational
procedures against the exact deployed Redis Enterprise Kubernetes
Operator version and current official Redis documentation.

Recommended documentation areas:

-   Redis Enterprise for Kubernetes
-   Redis Enterprise Kubernetes Operator
-   Redis Enterprise Kubernetes custom resources
-   RedisEnterpriseCluster
-   RedisEnterpriseDatabase
-   Redis Enterprise Kubernetes installation and upgrades
-   Redis Enterprise Kubernetes storage/network/security
-   Kubernetes controllers and CRDs
-   Kubernetes RBAC
-   Kubernetes scheduling
-   Kubernetes persistent volumes
-   Kubernetes NetworkPolicy
-   Kubernetes PodDisruptionBudget

------------------------------------------------------------------------

# Next Chapter

**Chapter 62 --- Redis Enterprise REC, REDB, RERC & REAADB Resource
Administration**

Chapter 62 will move from Operator architecture into hands-on
custom-resource administration: REC lifecycle, REDB
provisioning/configuration, remote-cluster relationships, Active-Active
database resources, references, status/conditions, safe spec changes,
scaling, persistence, security, deletion behavior, GitOps patterns,
failure scenarios, troubleshooting, runbooks, and production acceptance.
