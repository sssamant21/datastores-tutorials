# Chapter 78 --- Redis Enterprise Kubernetes Production Operations Project

**Status:** Canonical\
**Track:** Redis Enterprise / Redis Software Production Engineering\
**Part:** Part 13 --- Production Projects & Final Acceptance\
**Level:** Advanced → Kubernetes Production Operations Capstone\
**Audience:** SREs, DBREs, Redis Administrators, Platform Engineers,
Kubernetes Administrators, Cloud Engineers\
**Lab type:** End-to-end Redis Enterprise Kubernetes architecture,
Operator reconciliation, REC/REDB/RERC/REAADB administration,
scheduling, storage, networking, resources, node maintenance, scaling,
GitOps, backup/recovery, upgrades, observability, failure engineering,
incident response, runbooks, and production acceptance

------------------------------------------------------------------------

# 1. Objective

Running Redis Enterprise on Kubernetes creates two interacting
distributed systems:

``` text
Kubernetes
+
Redis Enterprise
```

Production operations must understand both.

A Kubernetes symptom may originate from:

``` text
scheduler
node
CNI
CSI
DNS
Service
NetworkPolicy
resource pressure
admission
GitOps
Operator
```

while a Redis symptom may originate from:

``` text
database
shard
proxy
replication
persistence
backup
placement
capacity
```

The Redis Enterprise Operator connects these systems through
reconciliation.

This chapter is an integrated Kubernetes production-operations project.

By the end, you should be able to:

-   map the Redis Enterprise Kubernetes architecture;
-   discover deployed CRDs safely;
-   understand Operator reconciliation;
-   administer REC and REDB resources;
-   understand RERC/REAADB where Active-Active is used;
-   inspect desired vs observed state;
-   troubleshoot scheduling;
-   validate failure-domain placement;
-   troubleshoot PVC/PV/CSI storage;
-   troubleshoot Services, endpoints, DNS, and NetworkPolicy;
-   manage CPU/memory requests and limits;
-   diagnose node pressure and OOM;
-   plan node maintenance and drains;
-   use PDBs correctly;
-   scale safely;
-   integrate GitOps without fighting the Operator;
-   validate backup and restore;
-   execute supported upgrades;
-   troubleshoot reconciliation;
-   perform controlled failure engineering;
-   operate incident runbooks;
-   complete Kubernetes production acceptance.

------------------------------------------------------------------------

# 2. Core Production Principle

Never troubleshoot Redis Enterprise on Kubernetes from only one layer.

Always correlate:

``` text
Kubernetes desired state
Kubernetes runtime state
Operator state
Redis Enterprise state
application behavior
```

------------------------------------------------------------------------

# Part 1 --- Project Deliverables

## 3. Required Outputs

Produce:

``` text
architecture map
CRD inventory
resource ownership map
scheduling baseline
storage baseline
network baseline
resource/capacity baseline
maintenance procedure
scaling procedure
backup/recovery evidence
upgrade procedure
GitOps ownership model
failure-test results
runbooks
production acceptance report
```

------------------------------------------------------------------------

# Part 2 --- Architecture

## 4. Logical Model

``` text
Git / administrator
        |
        v
Kubernetes API
        |
        v
Redis Enterprise Operator
        |
        v
Redis Enterprise resources
        |
        v
Pods / Services / Storage / Network
        |
        v
Redis Enterprise cluster + databases
```

------------------------------------------------------------------------

# Part 3 --- Control Loops

## 5. Kubernetes

Kubernetes controllers continuously reconcile declared resources.

------------------------------------------------------------------------

# Part 4 --- Redis Enterprise Operator

## 6. Role

The Operator observes Redis Enterprise custom resources and reconciles
supported Kubernetes/Redis state.

Exact behavior depends on deployed version.

------------------------------------------------------------------------

# Part 5 --- GitOps

## 7. Nested Reconciliation

With GitOps:

``` text
Git
 |
GitOps controller
 |
CR
 |
Redis Enterprise Operator
 |
generated/runtime resources
```

Understand ownership at each layer.

------------------------------------------------------------------------

# Part 6 --- Ownership Rule

## 8. Important

Do not manually modify an Operator-generated object and expect the
change to persist.

Make configuration changes through the supported owning
resource/mechanism.

------------------------------------------------------------------------

# Part 7 --- CRD Discovery

## 9. Never Guess

Start with:

``` bash
kubectl api-resources
```

Identify Redis Enterprise resources actually installed.

------------------------------------------------------------------------

# Part 8 --- Schema Discovery

## 10. Use

``` bash
kubectl explain <resource>
kubectl explain <resource>.spec
kubectl explain <resource>.status
```

against the actual cluster.

------------------------------------------------------------------------

# Part 9 --- API Version

## 11. Record

For each CRD:

``` text
group
version
kind
scope
```

Operator upgrades may change APIs.

------------------------------------------------------------------------

# Part 10 --- Core Resources

## 12. Typical Concepts

Depending on Operator/version:

``` text
REC
REDB
RERC
REAADB
```

Validate actual installed names and versions.

------------------------------------------------------------------------

# Part 11 --- REC

## 13. Concept

Redis Enterprise Cluster custom resource represents cluster-level
desired state.

------------------------------------------------------------------------

# Part 12 --- REDB

## 14. Concept

Redis Enterprise Database custom resource represents database-level
desired state.

------------------------------------------------------------------------

# Part 13 --- RERC

## 15. Concept

Used in supported Active-Active/multi-cluster configurations.

Validate exact semantics against deployed Operator documentation.

------------------------------------------------------------------------

# Part 14 --- REAADB

## 16. Concept

Represents supported Active-Active database configuration in Operator
environments.

Validate exact schema.

------------------------------------------------------------------------

# Part 15 --- Resource Inventory

## 17. Capture

``` bash
kubectl get <redis-resource> -A
```

for discovered resource types.

------------------------------------------------------------------------

# Part 16 --- Desired State

## 18. Inspect

``` bash
kubectl get <resource> <name> -n <namespace> -o yaml
```

Review:

``` text
metadata
spec
status
conditions
```

Redact secrets before sharing.

------------------------------------------------------------------------

# Part 17 --- Generation

## 19. Concept

Where present, compare:

``` text
metadata.generation
observed generation/status
```

to identify whether reconciliation has caught up.

------------------------------------------------------------------------

# Part 18 --- Conditions

## 20. Use

Conditions may expose:

``` text
Ready
progress
error
reconciliation state
```

depending on CRD.

------------------------------------------------------------------------

# Part 19 --- Events

## 21. Inspect

``` bash
kubectl get events -n <namespace> --sort-by=.lastTimestamp
```

Events can reveal:

``` text
scheduling
mount
admission
probe
image
```

failures.

------------------------------------------------------------------------

# Part 20 --- Operator Pods

## 22. Locate

``` bash
kubectl get pods -A
```

Identify Operator namespace/deployment.

------------------------------------------------------------------------

# Part 21 --- Operator Logs

## 23. Use Carefully

``` bash
kubectl logs -n <operator-namespace> <operator-pod>
```

or supported deployment selector.

Look for reconciliation errors.

Avoid dumping sensitive logs broadly.

------------------------------------------------------------------------

# Part 22 --- Operator Health

## 24. Validate

``` text
pod running
no crash loop
API connectivity
RBAC sufficient
CRD compatible
reconciliation active
```

------------------------------------------------------------------------

# Part 23 --- RBAC

## 25. Operator

Operator requires permissions to manage its supported resources.

An RBAC regression can stop reconciliation.

------------------------------------------------------------------------

# Part 24 --- Admission

## 26. Risk

Admission policies/webhooks can reject Operator-created or updated
resources.

Correlate:

``` text
events
Operator logs
admission messages
```

------------------------------------------------------------------------

# Part 25 --- REC Baseline

## 27. Record

``` text
name
namespace
version
node count
resources
storage
scheduling
status
```

using actual supported fields.

------------------------------------------------------------------------

# Part 26 --- REDB Baseline

## 28. Record

``` text
name
namespace
memory
replication
persistence
shards
TLS
backup
status
endpoint
```

where supported.

------------------------------------------------------------------------

# Part 27 --- Active-Active Baseline

## 29. Record

Where applicable:

``` text
participating clusters
regions
RERC
REAADB
replication/convergence
network
```

------------------------------------------------------------------------

# Part 28 --- Namespace

## 30. Governance

Record:

``` text
Operator namespace
REC namespace
database namespaces
application namespaces
```

and supported scoping model.

------------------------------------------------------------------------

# Part 29 --- Labels

## 31. Use

Labels help with:

``` text
ownership
environment
cost
policy
observability
```

Do not change vendor-managed labels casually.

------------------------------------------------------------------------

# Part 30 --- Owner References

## 32. Inspect

Owner references can help identify controller ownership of generated
resources.

------------------------------------------------------------------------

# Part 31 --- Finalizers

## 33. Understand

Finalizers can delay deletion until cleanup completes.

Do not remove them blindly to force deletion.

------------------------------------------------------------------------

# Part 32 --- Scheduling

## 34. Path

A Redis pod can remain Pending because of:

``` text
CPU
memory
node selector
affinity
taint
PVC
topology
quota
```

------------------------------------------------------------------------

# Part 33 --- Pod Placement

## 35. Inspect

``` bash
kubectl get pods -n <namespace> -o wide
```

Map:

``` text
pod
node
zone
IP
status
```

------------------------------------------------------------------------

# Part 34 --- Node Inventory

## 36. Inspect

``` bash
kubectl get nodes -o wide
kubectl describe node <node>
```

------------------------------------------------------------------------

# Part 35 --- Failure Domains

## 37. Record

Depending on environment:

``` text
region
zone
rack
node pool
```

Redis primary/replica placement should align with supported resilience
design.

------------------------------------------------------------------------

# Part 36 --- Affinity

## 38. Understand

Affinity/anti-affinity may influence placement.

Validate vendor-supported configuration path.

------------------------------------------------------------------------

# Part 37 --- Topology Spread

## 39. Understand

Kubernetes topology spread can distribute pods across domains.

Do not add constraints that conflict with Redis Enterprise Operator
placement requirements.

------------------------------------------------------------------------

# Part 38 --- Taints

## 40. Inspect

``` bash
kubectl describe node <node>
```

Look for taints.

Pods require matching tolerations when appropriate.

------------------------------------------------------------------------

# Part 39 --- Node Selectors

## 41. Risk

Overly restrictive selectors can make pods unschedulable during failure.

------------------------------------------------------------------------

# Part 40 --- Resource Requests

## 42. Scheduling

Requests affect scheduler placement.

Undersized requests can also distort cluster capacity planning.

------------------------------------------------------------------------

# Part 41 --- Resource Limits

## 43. Runtime

Limits can create:

``` text
CPU throttling
OOM termination
```

if incorrectly sized.

Follow vendor sizing/support guidance.

------------------------------------------------------------------------

# Part 42 --- CPU

## 44. Monitor

``` text
usage
request
limit
throttling
node utilization
```

------------------------------------------------------------------------

# Part 43 --- Memory

## 45. Monitor

``` text
working set
request
limit
Redis memory
node available memory
```

------------------------------------------------------------------------

# Part 44 --- OOMKilled

## 46. Diagnose

Check:

``` bash
kubectl describe pod <pod> -n <namespace>
```

and container termination state.

Do not simply increase limit without identifying Redis/container/node
memory model.

------------------------------------------------------------------------

# Part 45 --- Node Memory Pressure

## 47. Risk

Even if pod limit is adequate, node-level pressure can cause eviction or
instability.

------------------------------------------------------------------------

# Part 46 --- Disk Pressure

## 48. Risk

Node disk pressure can affect:

``` text
pods
logs
container runtime
local storage
```

------------------------------------------------------------------------

# Part 47 --- PID Pressure

## 49. Check

Node conditions can include PID pressure.

Rare but important during systemic node problems.

------------------------------------------------------------------------

# Part 48 --- Storage Architecture

## 50. Map

``` text
StorageClass
PVC
PV
CSI driver
cloud/storage backend
topology
```

------------------------------------------------------------------------

# Part 49 --- StorageClass

## 51. Inspect

``` bash
kubectl get storageclass
```

Record:

``` text
provisioner
binding mode
reclaim policy
parameters
```

------------------------------------------------------------------------

# Part 50 --- PVC

## 52. Inspect

``` bash
kubectl get pvc -A
kubectl describe pvc <pvc> -n <namespace>
```

------------------------------------------------------------------------

# Part 51 --- PV

## 53. Inspect

``` bash
kubectl get pv
```

Understand bound PVC, capacity, reclaim behavior, topology.

------------------------------------------------------------------------

# Part 52 --- CSI

## 54. Failure

CSI issues may appear as:

``` text
provision failure
attach failure
mount failure
resize failure
```

------------------------------------------------------------------------

# Part 53 --- Volume Binding

## 55. Topology

Binding mode affects when and where volume is provisioned.

This matters in zonal storage environments.

------------------------------------------------------------------------

# Part 54 --- Zonal Storage

## 56. Risk

A volume tied to one zone can constrain pod rescheduling.

Design storage and failure domains together.

------------------------------------------------------------------------

# Part 55 --- Storage Performance

## 57. Measure

For Redis persistence/recovery workloads:

``` text
IOPS
throughput
latency
queue
```

------------------------------------------------------------------------

# Part 56 --- Storage Capacity

## 58. Monitor

Do not wait for filesystem/storage exhaustion.

Forecast growth.

------------------------------------------------------------------------

# Part 57 --- Expansion

## 59. Validate

Volume expansion behavior depends on:

``` text
StorageClass
CSI
filesystem
Operator/product support
```

Test before emergency.

------------------------------------------------------------------------

# Part 58 --- Reclaim Policy

## 60. Understand

Deletion behavior may be:

``` text
Delete
Retain
```

or provider-specific.

Know data implications before deleting PVCs/resources.

------------------------------------------------------------------------

# Part 59 --- Network Path

## 61. Model

``` text
application pod
 |
DNS
 |
Service / LB
 |
endpoint
 |
Redis proxy
 |
shard
```

------------------------------------------------------------------------

# Part 60 --- Service

## 62. Inspect

``` bash
kubectl get svc -n <namespace>
kubectl describe svc <service> -n <namespace>
```

------------------------------------------------------------------------

# Part 61 --- EndpointSlice

## 63. Inspect

``` bash
kubectl get endpointslice -n <namespace>
```

Validate healthy backend selection.

------------------------------------------------------------------------

# Part 62 --- Empty Endpoint

## 64. Causes

``` text
selector mismatch
pod not Ready
service mismatch
controller issue
```
------------------------------------------------------------------------

# Part 63 --- DNS

## 65. Test From Client Pod

``` bash
getent hosts <redis-host>
```

or approved DNS tooling.

------------------------------------------------------------------------

# Part 64 --- CoreDNS

## 66. If Cluster-Wide

Investigate Kubernetes DNS health when multiple services are affected.

------------------------------------------------------------------------

# Part 65 --- NetworkPolicy

## 67. Inspect

``` bash
kubectl get networkpolicy -A
```

Validate intended ingress/egress.

------------------------------------------------------------------------

# Part 66 --- DNS Egress

## 68. Common Error

A default-deny egress policy can accidentally block DNS.

------------------------------------------------------------------------

# Part 67 --- CNI

## 69. Symptoms

CNI problems can cause:

``` text
pod IP allocation
routing
packet loss
network setup failure
```

------------------------------------------------------------------------

# Part 68 --- Load Balancer

## 70. Validate

Where used:

``` text
listener
backend
health
security rules
idle timeout
```

------------------------------------------------------------------------

# Part 69 --- MTU

## 71. Advanced

Overlay/network MTU mismatch can cause intermittent large-packet issues.

Use network-team-approved diagnostics.

------------------------------------------------------------------------

# Part 70 --- Network Baseline

## 72. Record

``` text
Service type
DNS
ports
NetworkPolicy
load balancer
source networks
TLS
```

------------------------------------------------------------------------

# Part 71 --- Probes

## 73. Understand

Kubernetes readiness/liveness/startup probes can affect traffic and
restarts.

Do not alter vendor-managed probes without support guidance.

------------------------------------------------------------------------

# Part 72 --- Readiness

## 74. Meaning

A Running pod may not be Ready.

Service endpoints may exclude unready pods.

------------------------------------------------------------------------

# Part 73 --- Liveness

## 75. Risk

An overly aggressive liveness probe can turn temporary slowness into
restart loops.

------------------------------------------------------------------------

# Part 74 --- Pod Restart

## 76. Investigate

Before restarting:

``` text
reason
logs
events
resource pressure
node condition
```

Restart can erase evidence.

------------------------------------------------------------------------

# Part 75 --- Pod Lifecycle

## 77. Observe

``` text
Pending
Running
Terminating
Failed
Unknown
```

with readiness and restart count.

------------------------------------------------------------------------

# Part 76 --- Graceful Termination

## 78. Importance

Node maintenance and rollout should allow supported Redis Enterprise
shutdown/failover behavior.

------------------------------------------------------------------------

# Part 77 --- PDB

## 79. Purpose

PodDisruptionBudget helps constrain voluntary disruption.

It does not prevent all failures.

------------------------------------------------------------------------

# Part 78 --- PDB Inspection

## 80. Use

``` bash
kubectl get pdb -A
kubectl describe pdb <name> -n <namespace>
```

------------------------------------------------------------------------

# Part 79 --- Drain

## 81. Before

Do not begin node drain without checking:

``` text
Redis health
replicas
PDB
placement
capacity
storage
other maintenance
```

------------------------------------------------------------------------

# Part 80 --- Drain Command

## 82. Caution

`kubectl drain` options are environment-specific.

Use the organization's approved procedure.

Do not bypass PDBs casually.

------------------------------------------------------------------------

# Part 81 --- Cordon

## 83. Purpose

Prevent new scheduling on a node during planned maintenance.

Use as part of approved workflow.

------------------------------------------------------------------------

# Part 82 --- Maintenance Sequence

## 84. Concept

``` text
precheck
cordon
validate failover/disruption
drain safely
perform maintenance
restore node
uncordon
validate placement
```

------------------------------------------------------------------------

# Part 83 --- One Node at a Time

## 85. Principle

Avoid concurrent disruption beyond tested resilience.

------------------------------------------------------------------------

# Part 84 --- Node Replacement

## 86. Validate

After replacement:

``` text
node Ready
storage/network healthy
Redis placement converged
replicas healthy
capacity restored
```

------------------------------------------------------------------------

# Part 85 --- Cluster Autoscaler

## 87. Interaction

Autoscaler behavior can interact with:

``` text
requests
PDB
affinity
storage topology
```

Validate Redis workload behavior.

------------------------------------------------------------------------

# Part 86 --- Scale Out

## 88. Redis Enterprise

Adding Kubernetes nodes is not necessarily the same as adding Redis
Enterprise capacity.

Understand product workflow.

------------------------------------------------------------------------

# Part 87 --- Redis Node Addition

## 89. Plan

Validate:

``` text
infrastructure
Operator/product workflow
placement
data movement
headroom
```

------------------------------------------------------------------------

# Part 88 --- Data Movement

## 90. Impact

Scaling/rebalancing can consume:

``` text
CPU
network
storage
```

Monitor application SLO.

------------------------------------------------------------------------

# Part 89 --- Scale In

## 91. Higher Risk

Before removing capacity:

``` text
remaining capacity
shard placement
replicas
failure headroom
storage
```

must pass.

------------------------------------------------------------------------

# Part 90 --- Database Scaling

## 92. REDB

Database memory/shard changes should use supported REDB/Redis Enterprise
workflows.

Validate before applying.

------------------------------------------------------------------------

# Part 91 --- Scaling Gate

## 93. Require

``` text
baseline
target
capacity
failure-state capacity
change plan
rollback/recovery
```

------------------------------------------------------------------------

# Part 92 --- GitOps Source of Truth

## 94. Define

For each managed resource:

``` text
repository
path
owner
promotion process
```

------------------------------------------------------------------------

# Part 93 --- Direct kubectl Edit

## 95. Risk

If Git owns a CR, a direct edit can be reverted.

Use break-glass only when required and reconcile afterward.

------------------------------------------------------------------------

# Part 94 --- Generated Resources

## 96. Rule

Do not put every Operator-generated object into Git and create
controller conflict.

Version desired configuration, not uncontrolled generated state.

------------------------------------------------------------------------

# Part 95 --- Drift

## 97. Detect

Compare:

``` text
Git desired CR
cluster CR
Operator status
Redis runtime
```

------------------------------------------------------------------------

# Part 96 --- Server-Side Dry Run

## 98. Use

Where supported:

``` bash
kubectl apply --dry-run=server -f <manifest>
```

before change.

------------------------------------------------------------------------

# Part 97 --- Diff

## 99. Use

Where appropriate:

``` bash
kubectl diff -f <manifest>
```

Review before apply.

------------------------------------------------------------------------

# Part 98 --- Backup

## 100. Kubernetes Context

Redis data protection remains a Redis Enterprise concern integrated
with:

``` text
storage
network
credentials
repository
```

Do not assume a generic Kubernetes object backup alone equals
Redis-consistent backup.

------------------------------------------------------------------------

# Part 99 --- Backup Dependencies

## 101. Validate

``` text
repository reachable
credentials valid
DNS/network
capacity
last success
```

------------------------------------------------------------------------

# Part 100 --- Restore

## 102. Test

A production backup strategy requires tested restore.

Measure:

``` text
RPO
RTO
data validation
```

------------------------------------------------------------------------

# Part 101 --- Kubernetes Object Recovery

## 103. Also Protect

Version/recover:

``` text
CR manifests
GitOps config
policies
RBAC
NetworkPolicy
```

through approved mechanisms.

------------------------------------------------------------------------

# Part 102 --- Secrets Recovery

## 104. Separate

Recover secrets from approved secret-management system.

Do not export plaintext secrets into Git backups.

------------------------------------------------------------------------

# Part 103 --- Upgrade Layers

## 105. Inventory

Potential layers:

``` text
cloud/node OS
Kubernetes
Redis Enterprise Operator
CRDs
Redis Enterprise
clients
```

------------------------------------------------------------------------

# Part 104 --- Compatibility Matrix

## 106. Before Upgrade

Document supported:

``` text
Kubernetes version
Operator version
Redis Enterprise version
CRD/API version
client dependencies
```

------------------------------------------------------------------------

# Part 105 --- Upgrade Order

## 107. Do Not Guess

Follow vendor-supported upgrade sequence for exact versions.

------------------------------------------------------------------------

# Part 106 --- Upgrade Precheck

## 108. Validate

``` text
cluster healthy
databases healthy
replicas healthy
capacity
backup
recovery
PDB
storage
network
GitOps
```

------------------------------------------------------------------------

# Part 107 --- Upgrade Baseline

## 109. Capture

``` text
application P95/P99
errors
Redis health
CPU/memory/network
backup status
```

------------------------------------------------------------------------

# Part 108 --- CRD Upgrade

## 110. Risk

CRD/API changes can affect:

``` text
manifests
automation
policy
GitOps
```

------------------------------------------------------------------------

# Part 109 --- Operator Upgrade

## 111. Validate

After Operator upgrade:

``` text
pod healthy
CRDs compatible
reconciliation healthy
existing REC/REDB healthy
```

------------------------------------------------------------------------

# Part 110 --- Redis Upgrade

## 112. Validate

Monitor:

``` text
availability
failover
latency
errors
replication
```

through supported upgrade.

------------------------------------------------------------------------

# Part 111 --- Kubernetes Upgrade

## 113. Validate

Review:

``` text
API deprecations
CNI
CSI
admission
node images
PDB
scheduling
```

------------------------------------------------------------------------

# Part 112 --- Node Pool Upgrade

## 114. Treat As Maintenance

One node/failure domain at a time according to resilience design.

------------------------------------------------------------------------

# Part 113 --- Rollback vs Recovery

## 115. Important

Some upgrades cannot simply be rolled back.

Define:

``` text
rollback
or
restore/recovery
```

before change.

------------------------------------------------------------------------

# Part 114 --- Observability

## 116. Layers

Monitor:

``` text
application
Redis database
Redis cluster
Operator
pods
nodes
storage
network
Kubernetes control plane
```

------------------------------------------------------------------------

# Part 115 --- Kubernetes Metrics

## 117. Include

``` text
pod CPU/memory
restarts
readiness
node pressure
PVC usage
network
events
```

------------------------------------------------------------------------

# Part 116 --- Redis Metrics

## 118. Include

``` text
ops/sec
P95/P99
memory
connections
errors
replication
shards
```

------------------------------------------------------------------------

# Part 117 --- Operator Metrics / Logs

## 119. Include

Where supported, monitor reconciliation and Operator health.

------------------------------------------------------------------------

# Part 118 --- Event Correlation

## 120. Timeline

During incident correlate:

``` text
application error
Redis metric
pod event
node event
Operator log
storage/network event
change
```

------------------------------------------------------------------------

# Part 119 --- Change Correlation

## 121. Ask

``` text
deployment?
GitOps sync?
node drain?
Kubernetes upgrade?
Operator change?
NetworkPolicy?
StorageClass?
```

------------------------------------------------------------------------

# Part 120 --- Alert Ownership

## 122. Every Alert

Needs:

``` text
owner
severity
runbook
escalation
```

------------------------------------------------------------------------

# Part 121 --- Lab Environment

## 123. Scope

Use disposable/nonproduction Kubernetes resources.

Synthetic Redis namespace:

``` text
tutorial:chapter78:*
```

------------------------------------------------------------------------

# Part 122 --- Lab 1: CRD Discovery

## 124. Exercise

Run:

``` bash
kubectl api-resources
```

Identify installed Redis Enterprise CRDs.

Use `kubectl explain` to inspect schemas.

------------------------------------------------------------------------

# Part 123 --- Lab 2: Ownership Map

## 125. Exercise

For a test REDB:

map:

``` text
Git
CR
Operator
Service
pods
Redis runtime
```

Identify owner of each object.

------------------------------------------------------------------------

# Part 124 --- Lab 3: Scheduling

## 126. Exercise

Inspect pod/node placement and failure domains.

Identify what would happen if one node became unavailable.

------------------------------------------------------------------------

# Part 125 --- Lab 4: Storage

## 127. Exercise

Map:

``` text
pod -> PVC -> PV -> StorageClass -> CSI
```

Record zone/topology.

------------------------------------------------------------------------

# Part 126 --- Lab 5: Network

## 128. Exercise

From approved client pod:

``` text
resolve DNS
test TCP/TLS
PING Redis
```

Map Service/EndpointSlice.

------------------------------------------------------------------------

# Part 127 --- Lab 6: Resource Pressure

## 129. Exercise

Using safe synthetic workload, observe:

``` text
pod CPU
memory
node utilization
Redis P99
```

Do not force production OOM.

------------------------------------------------------------------------

# Part 128 --- Lab 7: Node Maintenance Tabletop

## 130. Exercise

Select a nonproduction node.

Build precheck:

``` text
PDB
replicas
placement
capacity
storage
```

Execute only if approved.

------------------------------------------------------------------------

# Part 129 --- Lab 8: GitOps Drift

## 131. Exercise

Create a harmless test difference in disposable environment.

Observe ownership/reconciliation.

Restore source of truth.

------------------------------------------------------------------------

# Part 130 --- Lab 9: Restore

## 132. Exercise

Restore nonproduction Redis data using supported process.

Measure RTO and validate synthetic keys.

------------------------------------------------------------------------

# Part 131 --- Lab 10: Upgrade Tabletop

## 133. Exercise

Build compatibility matrix and step-by-step upgrade plan for:

``` text
Kubernetes
Operator
Redis Enterprise
```

without performing production upgrade.

------------------------------------------------------------------------

# Part 132 --- Failure Scenario 1: Operator Crash

## 134. Test/Tabletop

Determine:

``` text
existing Redis data plane behavior
reconciliation impact
recovery
```

Do not assume data plane fails because Operator is unavailable.

------------------------------------------------------------------------

# Part 133 --- Failure Scenario 2: Pending Redis Pod

## 135. Test/Tabletop

Investigate:

``` text
resourcestaints
affinity
PVC
topology
quota
```

------------------------------------------------------------------------

# Part 134 --- Failure Scenario 3: PVC Mount Failure

## 136. Tabletop

Trace:

``` text
pod event
PVC
PV
CSI
zone
node
```

------------------------------------------------------------------------

# Part 135 --- Failure Scenario 4: Empty Service Endpoint

## 137. Test

In disposable environment, diagnose:

``` text
selector
readiness
Service
EndpointSlice
```

------------------------------------------------------------------------

# Part 136 --- Failure Scenario 5: NetworkPolicy Blocks Redis

## 138. Test

Verify denied path and correct only the minimum policy required.

------------------------------------------------------------------------

# Part 137 --- Failure Scenario 6: Node Memory Pressure

## 139. Tabletop

Identify:

``` text
node condition
pod usage
Redis memory
other workloads
evictions
```

------------------------------------------------------------------------

# Part 138 --- Failure Scenario 7: Drain Blocked by PDB

## 140. Tabletop

Do not bypass immediately.

Determine whether:

``` text
Redis health
placement
capacity
PDB
```

correctly prevents unsafe maintenance.

------------------------------------------------------------------------

# Part 139 --- Failure Scenario 8: GitOps Fights Manual Change

## 141. Test

Observe direct edit being reverted.

Practice break-glass reconciliation.

------------------------------------------------------------------------

# Part 140 --- Failure Scenario 9: Admission Policy Blocks Operator

## 142. Tabletop

Identify denial, restore reconciliation through approved
exception/rollback, then fix policy.

------------------------------------------------------------------------

# Part 141 --- Failure Scenario 10: Upgrade Leaves Partial Reconciliation

## 143. Tabletop

Investigate:

``` text
Operator
CRD/API
conditions
events
GitOps
Redis health
```

and define recovery.

------------------------------------------------------------------------

# Part 142 --- Troubleshooting Matrix

## 144. Common Problems

  Symptom                    Investigate
  -------------------------- ----------------------------------------
  CR not becoming Ready      Operator/status/events/RBAC/admission
  pod Pending                resources/taints/affinity/PVC/topology
  pod CrashLoopBackOff       logs/config/resources/probes
  pod OOMKilled              container memory/Redis/node pressure
  PVC Pending                StorageClass/CSI/topology/capacity
  mount failure              CSI/PV/node/zone
  Service has no endpoints   selector/readiness
  Redis DNS fails            Service/CoreDNS/NetworkPolicy
  node drain blocked         PDB/placement/health
  Git change not applied     GitOps/CR schema/admission/Operator

------------------------------------------------------------------------

# Part 143 --- Runbook 1: REDB Reconciliation Failure

## 145. Procedure

``` text
1. inspect REDB spec/status/conditions.
2. inspect events.
3. inspect Operator health/logs.
4. inspect RBAC/admission.
5. inspect generated resources.
6. correct source-of-truth issue.
7. observe reconciliation.
8. validate Redis/application.
```

------------------------------------------------------------------------

# Part 144 --- Runbook 2: Redis Pod Pending

## 146. Procedure

``` text
1. describe pod.
2. read scheduling event.
3. inspect requests/limits.
4. inspect nodes/taints.
5. inspect affinity/selectors.
6. inspect PVC/topology.
7. correct supported configuration/capacity.
8. validate placement.
```

------------------------------------------------------------------------

# Part 145 --- Runbook 3: Storage Failure

## 147. Procedure

``` text
1. inspect pod events.
2. inspect PVC/PV.
3. inspect StorageClass.
4. inspect CSI.
5. inspect node/zone.
6. inspect backend capacity/health.
7. restore supported storage path.
8. validate Redis persistence/recovery.
```

------------------------------------------------------------------------

# Part 146 --- Runbook 4: Redis Connectivity Failure

## 148. Procedure

``` text
1. resolve DNS.
2. inspect Service.
3. inspect EndpointSlice.
4. test TCP/TLS.
5. inspect NetworkPolicy.
6. inspect CNI/LB.
7. validate Redis endpoint/proxy.
8. validate application.
```

------------------------------------------------------------------------

# Part 147 --- Runbook 5: Node Maintenance

## 149. Procedure

``` text
1. verify Redis health.
2. verify replicas/placement.
3. verify PDB.
4. verify remaining capacity.
5. cordon/drain using approved procedure.
6. monitor Redis/application.
7. restore/uncordon node.
8. validate placement/capacity.
```

------------------------------------------------------------------------

# Part 148 --- Runbook 6: Node Pressure / OOM

## 150. Procedure

``` text
1. inspect node conditions.
2. inspect pod termination/restarts.
3. compare requests/limits/usage.
4. inspect Redis memory.
5. inspect other workloads.
6. stabilize capacity.
7. correct sizing/scheduling.
8. validate no recurrence.
```

------------------------------------------------------------------------

# Part 149 --- Runbook 7: GitOps / Operator Conflict

## 151. Procedure

``` text
1. identify desired source.
2. compare Git and CR.
3. identify manual/generated change.
4. identify controller ownership.
5. choose correct desired state.
6. update source of truth.
7. allow reconciliation.
8. validate runtime.
```

------------------------------------------------------------------------

# Part 150 --- Runbook 8: Kubernetes / Operator Upgrade

## 152. Procedure

``` text
1. build compatibility matrix.
2. capture baseline.
3. validate backup/recovery.
4. validate cluster/Redis health.
5. follow supported upgrade order.
6. monitor reconciliation/SLO.
7. validate CRDs/REC/REDB.
8. soak and close change.
```

------------------------------------------------------------------------

# Part 151 --- Architecture Template

## 153. Record

``` text
Kubernetes cluster:
Region/zones:
Operator version:
Redis Enterprise version:
REC:
REDBs:
RERC/REAADB:
Node pools:
StorageClass:
CNI:
Ingress/LB:
GitOps:
Secret manager:
Owners:
```

------------------------------------------------------------------------

# Part 152 --- Resource Ownership Template

## 154. Record

``` text
Resource:
Namespace:
Owner/controller:
Source of truth:
Editable by humans?:
Change method:
Validation:
```

------------------------------------------------------------------------

# Part 153 --- Node Maintenance Template

## 155. Record

``` text
Node:
Zone:
Hosted Redis pods:
Redis health:
Replica health:
PDB:
Remaining capacity:
Storage risk:
Start:
Drain result:
Application impact:
Restore:
Validation:
```

------------------------------------------------------------------------

# Part 154 --- Upgrade Template

## 156. Record

``` text
Current Kubernetes:
Target Kubernetes:
Current Operator:
Target Operator:
Current Redis:
Target Redis:
Compatibility verified:
Backup verified:
Rollback/recovery:
Maintenance window:
Stop conditions:
Validation:
```

------------------------------------------------------------------------

# Part 155 --- Incident Evidence Template

## 157. Record

``` text
Timestamp:
Application symptom:
Redis symptom:
CR status:
Pod status:
Node status:
Storage:
Network:
Operator:
Recent change:
Action:
Result:
```

------------------------------------------------------------------------

# Part 156 --- Project Phase 1: Discovery

## 158. Deliverables

Create:

``` text
CRD inventory
architecture map
resource ownership
namespace map
version inventory
```

------------------------------------------------------------------------

# Part 157 --- Project Phase 2: Infrastructure Baseline

## 159. Deliverables

Create:

``` text
node/scheduling baseline
storage baseline
network baseline
resource baseline
failure-domain map
```

------------------------------------------------------------------------

# Part 158 --- Project Phase 3: Operational Procedures

## 160. Deliverables

Create/test:

``` text
node maintenance
scaling
backup/restore
GitOps change
upgrade
```

------------------------------------------------------------------------

# Part 159 --- Project Phase 4: Observability

## 161. Deliverables

Correlate:

``` text
application
Redis
Operator
pods
nodes
storage
network
events
```

------------------------------------------------------------------------

# Part 160 --- Project Phase 5: Failure Engineering

## 162. Deliverables

Complete ten controlled scenarios.

------------------------------------------------------------------------

# Part 161 --- Project Phase 6: Runbooks

## 163. Deliverables

Validate eight production runbooks.

------------------------------------------------------------------------

# Part 162 --- Project Phase 7: Acceptance

## 164. Deliverables

Produce:

``` text
evidence
gaps
owners
remediation
retest
production acceptance
```

------------------------------------------------------------------------

# Part 163 --- Production Acceptance

## 165. Architecture / Ownership

-   [ ] CRDs inventoried from actual cluster;
-   [ ] REC/REDB inventory complete;
-   [ ] RERC/REAADB inventoried where applicable;
-   [ ] Operator version documented;
-   [ ] Redis Enterprise version documented;
-   [ ] resource ownership defined;
-   [ ] GitOps source of truth defined;
-   [ ] generated-resource ownership understood.

## 166. Scheduling / Capacity

-   [ ] node pools documented;
-   [ ] failure domains documented;
-   [ ] pod placement reviewed;
-   [ ] taints/tolerations reviewed;
-   [ ] affinity/selectors reviewed;
-   [ ] requests/limits reviewed;
-   [ ] N-1/failure capacity reviewed;
-   [ ] node pressure monitoring enabled.

## 167. Storage / Network

-   [ ] StorageClass documented;
-   [ ] PVC/PV topology understood;
-   [ ] CSI dependencies documented;
-   [ ] storage performance monitored;
-   [ ] storage growth monitored;
-   [ ] Services documented;
-   [ ] EndpointSlices understood;
-   [ ] DNS tested;
-   [ ] NetworkPolicy reviewed;
-   [ ] load-balancer path reviewed where applicable.

## 168. Operations

-   [ ] PDBs reviewed;
-   [ ] node maintenance tested/tabletopped;
-   [ ] scaling procedure documented;
-   [ ] data movement impact understood;
-   [ ] backup success monitored;
-   [ ] restore tested;
-   [ ] secrets recoverable from approved source;
-   [ ] compatibility matrix maintained;
-   [ ] upgrade procedure tested/tabletopped;
-   [ ] rollback/recovery defined.

## 169. Observability / Reliability

-   [ ] application/Redis/Kubernetes metrics correlated;
-   [ ] Operator health monitored;
-   [ ] events included in incident workflow;
-   [ ] change correlation available;
-   [ ] ten failure scenarios completed;
-   [ ] eight runbooks reviewed;
-   [ ] gaps remediated/retested;
-   [ ] production acceptance approved.

------------------------------------------------------------------------

# 170. Knowledge Validation

1.  Why must Redis Enterprise Kubernetes troubleshooting include both
    Kubernetes and Redis layers?
2.  What role does the Redis Enterprise Operator play?
3.  Why should CRDs be discovered rather than guessed?
4.  What does `kubectl explain` provide?
5.  What is the difference between desired and observed state?
6.  Why are conditions/events useful?
7.  Why should Operator-generated resources not be manually managed?
8.  What can stop Operator reconciliation?
9.  What can cause a Redis pod to remain Pending?
10. Why do failure domains matter?
11. How can taints/selectors make recovery harder?
12. What is the difference between requests and limits?
13. Why should OOMKilled not be fixed blindly by increasing memory?
14. How can node memory pressure affect Redis pods?
15. What is the PVC → PV → StorageClass → CSI relationship?
16. Why does zonal storage affect rescheduling?
17. Why should storage performance be monitored for Redis?
18. What can cause an empty Service endpoint?
19. Why can NetworkPolicy accidentally break DNS?
20. What is the purpose of a PDB?
21. Why should PDBs not be bypassed casually during drain?
22. Why is adding Kubernetes nodes not always equivalent to adding Redis
    capacity?
23. Why is scale-in riskier than scale-out?
24. How can GitOps fight manual changes?
25. Why is generic Kubernetes backup insufficient as the only Redis
    backup strategy?
26. What belongs in an upgrade compatibility matrix?
27. Why might rollback differ from recovery after an upgrade?
28. Which observability layers should be correlated during an incident?
29. Why should recent changes be included in incident analysis?
30. What must pass before Redis Enterprise on Kubernetes is
    production-ready?

------------------------------------------------------------------------

# 171. Hands-On Acceptance Checklist

-   [ ] Discovered actual Redis CRDs.
-   [ ] Used `kubectl explain`.
-   [ ] Inventoried REC/REDB.
-   [ ] Inventoried Active-Active CRs where applicable.
-   [ ] Built resource ownership map.
-   [ ] Inspected spec/status/conditions.
-   [ ] Inspected Operator health/logs.
-   [ ] Reviewed Operator RBAC/admission dependencies.
-   [ ] Mapped pod/node/zone placement.
-   [ ] Reviewed taints/affinity/selectors.
-   [ ] Reviewed requests/limits.
-   [ ] Reviewed node pressure.
-   [ ] Mapped PVC/PV/StorageClass/CSI.
-   [ ] Reviewed storage topology/performance.
-   [ ] Mapped Service/EndpointSlice/DNS.
-   [ ] Reviewed NetworkPolicy.
-   [ ] Reviewed PDBs.
-   [ ] Built node-maintenance precheck.
-   [ ] Reviewed scaling workflow.
-   [ ] Tested GitOps drift safely.
-   [ ] Reviewed backup dependencies.
-   [ ] Completed nonproduction restore.
-   [ ] Built version compatibility matrix.
-   [ ] Built upgrade plan.
-   [ ] Correlated application/Redis/Kubernetes metrics.
-   [ ] Completed ten failure scenarios.
-   [ ] Completed eight runbooks.
-   [ ] Completed production acceptance.

------------------------------------------------------------------------

# 172. Cleanup

Remove only disposable Chapter 78 resources.

For Redis synthetic keys:

``` text
tutorial:chapter78:*
```

use controlled:

``` text
SCAN
+
UNLINK
```

Do not use:

``` text
FLUSHDB
FLUSHALL
```

on shared environments.

Remove/revert approved temporary:

``` text
test REDB
test namespace
test NetworkPolicy
test GitOps drift
test load
test restore resources
test failure injection
```

through the correct owner/controller.

Confirm:

``` text
Git desired state restored
Operator reconciliation healthy
no test resources remain
all nodes intended state
Redis placement healthy
storage healthy
network healthy
application SLO normal
evidence preserved
```

------------------------------------------------------------------------

# 173. Key Takeaways

1.  Redis Enterprise on Kubernetes combines two distributed control
    systems that must be operated together.
2.  Kubernetes desired state, Operator reconciliation, Redis runtime
    state, and application behavior should always be correlated.
3.  Redis Enterprise CRDs must be discovered from the deployed cluster
    rather than assumed from examples.
4.  REC, REDB, RERC, and REAADB administration depends on the exact
    Operator/API version.
5.  GitOps and the Redis Enterprise Operator form nested reconciliation
    loops with distinct ownership.
6.  Manual edits to generated resources can be reverted or create
    unsupported controller conflicts.
7.  Pod scheduling depends on resources, taints, selectors, affinity,
    storage topology, quotas, and failure-domain capacity.
8.  CPU requests/limits and memory requests/limits affect both
    scheduling and runtime behavior.
9.  OOM and node pressure require layered diagnosis rather than
    immediate resource increases.
10. Redis storage troubleshooting should trace pod → PVC → PV →
    StorageClass → CSI → backend.
11. Zonal storage can constrain failover and rescheduling.
12. Storage IOPS, throughput, latency, and capacity matter for
    persistence, recovery, and data movement.
13. Redis connectivity troubleshooting should trace DNS → Service/LB →
    EndpointSlice → network policy/CNI → Redis endpoint.
14. NetworkPolicy can accidentally block DNS or required
    Operator/application communication.
15. Running is not the same as Ready, and probe behavior can affect
    endpoint membership and restarts.
16. PDBs help control voluntary disruption but do not replace Redis
    replication or failure-domain design.
17. Node maintenance requires Redis health, placement, PDB, remaining
    capacity, storage, and application checks before drain.
18. Adding Kubernetes infrastructure does not automatically add usable
    Redis Enterprise capacity.
19. Scale-in requires proof that remaining capacity and placement can
    safely absorb the change.
20. Backup/restore must protect Redis data through supported Redis
    Enterprise mechanisms as well as recover Kubernetes configuration.
21. Secrets should be recovered from approved secret-management systems,
    not copied into configuration backups.
22. Upgrades require a version compatibility matrix across Kubernetes,
    Operator, CRDs, Redis Enterprise, and dependent clients.
23. Rollback and recovery are not always the same operation.
24. Production observability must correlate application, Redis,
    Operator, pod, node, storage, network, event, and change data.
25. Kubernetes production acceptance requires tested architecture
    ownership, scheduling, storage, networking, maintenance, scaling,
    backup/recovery, upgrades, failure scenarios, runbooks, and
    documented remediation.

------------------------------------------------------------------------

# 174. References

Validate all Redis Enterprise Kubernetes resource names, CRD schemas,
Operator behavior, supported Kubernetes versions, upgrade paths, storage
requirements, network requirements, and operational procedures against
the exact deployed versions and current official documentation.

Recommended documentation areas:

-   Redis Enterprise Kubernetes Operator
-   Redis Enterprise Kubernetes deployment
-   Redis Enterprise Cluster custom resource
-   Redis Enterprise Database custom resource
-   Redis Enterprise Active-Active Kubernetes resources
-   Redis Enterprise Kubernetes upgrades
-   Redis Enterprise Kubernetes backup and recovery
-   Redis Enterprise high availability
-   Redis Enterprise cluster and shard architecture
-   Kubernetes custom resources and CRDs
-   Kubernetes scheduling
-   Kubernetes taints and tolerations
-   Kubernetes affinity/topology spread
-   Kubernetes requests and limits
-   Kubernetes PodDisruptionBudgets
-   Kubernetes node maintenance/drain
-   Kubernetes persistent volumes
-   CSI documentation
-   Kubernetes Services and EndpointSlices
-   Kubernetes DNS
-   Kubernetes NetworkPolicy
-   Kubernetes RBAC
-   Kubernetes admission control
-   organizational GitOps standards
-   organizational Kubernetes production standards

------------------------------------------------------------------------

# Next Chapter

**Chapter 79 --- Redis Enterprise Incident, Recovery & Resilience
Game-Day Project**

Chapter 79 will integrate incident detection, triage, command structure,
evidence preservation, latency/memory/network/storage failures, node and
shard failures, authentication/TLS incidents, backup/recovery,
Kubernetes failures, regional failures, controlled fault injection,
RPO/RTO, communications, recovery validation, post-incident analysis,
resilience scoring, runbooks, and a full production game-day acceptance
exercise.