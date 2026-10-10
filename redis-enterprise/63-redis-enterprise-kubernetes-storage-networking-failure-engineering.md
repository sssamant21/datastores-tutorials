# Chapter 63 --- Redis Enterprise Kubernetes Storage, Networking & Failure Engineering

**Status:** Canonical\
**Track:** Redis Enterprise / Redis Software Production Engineering\
**Part:** Part 11 --- Advanced Kubernetes, Active-Active & Platform
Engineering\
**Level:** Advanced → Production Kubernetes Infrastructure & Failure
Engineering\
**Audience:** SREs, DBREs, Platform Engineers, Kubernetes
Administrators, Redis Administrators, Cloud Engineers, Network
Engineers\
**Lab type:** StorageClass/CSI/PV architecture, storage performance,
CNI/DNS/services, NetworkPolicy, failure domains,
node/zone/storage/network failures, controlled failure injection,
observability, troubleshooting, runbooks, and production acceptance

------------------------------------------------------------------------

# 1. Objective

A Redis Enterprise Kubernetes deployment depends on much more than Redis
pods.

Its availability path includes:

``` text
application
   |
DNS / load balancer / service
   |
Kubernetes networking / CNI
   |
Redis Enterprise pods
   |
Kubernetes nodes
   |
persistent volumes / CSI
   |
cloud or datacenter infrastructure
```

A Redis incident may therefore originate in:

``` text
storage
network
DNS
node capacity
zone failure
CSI
CNI
load balancer
NetworkPolicy
```

rather than Redis itself.

By the end of this chapter, you should be able to:

-   map Redis Enterprise Kubernetes infrastructure dependencies;
-   understand StorageClass, PVC, PV, and CSI relationships;
-   reason about storage topology;
-   qualify storage IOPS, throughput, and latency;
-   identify storage saturation and degradation;
-   understand CNI, services, EndpointSlices, DNS, and load balancers;
-   troubleshoot NetworkPolicy;
-   define node and zone failure domains;
-   distinguish control-plane, Kubernetes, infrastructure, and Redis
    failures;
-   perform controlled failure testing;
-   validate recovery and N-1 behavior;
-   build infrastructure observability;
-   execute production runbooks and acceptance checks.

------------------------------------------------------------------------

# 2. Core Production Principle

Kubernetes object health is not equivalent to application health.

For example:

``` text
PVC = Bound
pod = Running
service = present
```

does not prove:

``` text
storage latency acceptable
network path healthy
DNS reliable
Redis P99 within SLO
```

Production engineering must validate both state and performance.

------------------------------------------------------------------------

# Part 1 --- Dependency Map

## 3. Build the Map

For every production Redis Enterprise deployment, document:

``` text
Kubernetes cluster
node pools
zones
REC/REDB resources
pods
StorageClasses
PVCs/PVs
CSI driver
CNI
services
DNS
load balancers
NetworkPolicies
firewalls/security groups
```

------------------------------------------------------------------------

# Part 2 --- Storage Architecture

## 4. Kubernetes Storage Chain

Conceptually:

``` text
Redis pod
   |
PVC
   |
PV
   |
StorageClass
   |
CSI provisioner
   |
physical/cloud storage
```

Each layer can fail independently.

------------------------------------------------------------------------

# Part 3 --- StorageClass

## 5. Inspect

``` bash
kubectl get storageclass
```

Then:

``` bash
kubectl get storageclass <name> -o yaml
```

Record:

``` text
provisioner
parameters
reclaimPolicy
volumeBindingMode
allowVolumeExpansion
```

------------------------------------------------------------------------

# Part 4 --- PVC

## 6. Inspect

``` bash
kubectl get pvc -n <namespace>
kubectl describe pvc <pvc> -n <namespace>
```

Record:

``` text
status
requested size
actual capacity
StorageClass
access mode
bound PV
events
```

------------------------------------------------------------------------

# Part 5 --- PV

## 7. Inspect

``` bash
kubectl get pv
kubectl get pv <pv> -o yaml
```

Review:

``` text
capacity
claim reference
storage class
node affinity
reclaim policy
CSI source
```

Do not expose sensitive provider identifiers unnecessarily.

------------------------------------------------------------------------

# Part 6 --- CSI

## 8. Role

Container Storage Interface components connect Kubernetes volume
operations to the underlying storage platform.

CSI problems can affect:

``` text
provisioning
attach
mount
expand
snapshot
```

------------------------------------------------------------------------

# Part 7 --- CSI Health

## 9. Inspect

Discover the deployed CSI components:

``` bash
kubectl get pods -A | grep -i csi
```

Then inspect relevant controller/node pods and events.

Do not restart CSI components casually in production.

------------------------------------------------------------------------

# Part 8 --- Volume Binding Mode

## 10. Topology

StorageClass may use binding behavior that interacts with pod
scheduling.

A volume may need to be provisioned in a zone compatible with the
scheduled pod.

Understand the installed storage design.

------------------------------------------------------------------------

# Part 9 --- Zone Topology

## 11. Failure Domain

A PV may have topology constraints.

Inspect:

``` text
PV node affinity
pod node
zone labels
StorageClass binding behavior
```

A volume in one zone cannot necessarily follow a pod to another zone.

------------------------------------------------------------------------

# Part 10 --- Storage Reclaim Policy

## 12. Destructive Boundary

Common conceptual behaviors include:

``` text
Retain
Delete
```

Understand what happens to underlying storage after PVC/PV deletion.

Never test deletion semantics with production data.

------------------------------------------------------------------------

# Part 11 --- Volume Expansion

## 13. Preconditions

Before expanding storage:

``` text
Redis procedure supported?
StorageClass allows expansion?
CSI supports it?
filesystem/device supports it?
restart required?
rollback possible?
```

Storage expansion is often easier than shrinking.

Do not assume reversibility.

------------------------------------------------------------------------

# Part 12 --- Storage Capacity

## 14. Headroom

Capacity planning must include:

``` text
current data
growth
persistence
temporary operational overhead
recovery
maintenance
```

Avoid running stateful storage near exhaustion.

------------------------------------------------------------------------

# Part 13 --- Storage Performance

## 15. Three Core Dimensions

Measure:

``` text
IOPS
throughput
latency
```

All three matter.

------------------------------------------------------------------------

# Part 14 --- IOPS

## 16. Small I/O

High operation rates can saturate IOPS before throughput.

Track:

``` text
read IOPS
write IOPS
provisioned IOPS
actual IOPS
```

where available.

------------------------------------------------------------------------

# Part 15 --- Throughput

## 17. Large I/O

Large persistence, backup, recovery, or data movement can saturate
bandwidth.

Track:

``` text
MB/s read
MB/s write
provisioned throughput
```

------------------------------------------------------------------------

# Part 16 --- Latency

## 18. Tail Matters

Track:

``` text
average
P95
P99
```

when infrastructure telemetry supports it.

Averages can hide storage tail latency.

------------------------------------------------------------------------

# Part 17 --- Queue Depth

## 19. Saturation Signal

Rising queueing plus rising latency can indicate storage saturation.

Correlate with:

``` text
IOPS
throughput
Redis latency
CPU
```

------------------------------------------------------------------------

# Part 18 --- Burst Credits

## 20. Cloud Storage

Some storage classes may have burst/baseline behavior.

A benchmark can look healthy briefly and degrade after credits are
consumed.

Use sustained tests.

------------------------------------------------------------------------

# Part 19 --- Shared Storage Effects

## 21. Noisy Neighbor

Underlying shared infrastructure may create variable latency.

If Redis P99 changes without workload change, inspect infrastructure
telemetry.

------------------------------------------------------------------------

# Part 20 --- Persistence Interaction

## 22. I/O

Redis persistence can create storage activity.

Measure application latency during persistence operations.

------------------------------------------------------------------------

# Part 21 --- Backup Interaction

## 23. I/O + Network

Backup may consume:

``` text
storage throughput
CPU
network
```

Test backup under representative load.

------------------------------------------------------------------------

# Part 22 --- Recovery Interaction

## 24. Highest Stress

Recovery can combine:

``` text
storage reads/writes
network transfer
CPU
Redis synchronization
```

Size for recovery, not only steady state.

------------------------------------------------------------------------

# Part 23 --- Storage Monitoring

## 25. Dashboard

Include:

``` text
PVC usage
underlying disk usage
IOPS
throughput
latency
queueing
errors
CSI health
Redis persistence/recovery state
```

------------------------------------------------------------------------

# Part 24 --- Storage Alerts

## 26. Examples

Alert before:

``` text
capacity exhaustion
sustained high latency
I/O errors
CSI failures
volume attachment failures
```

Thresholds must match the actual storage platform.

------------------------------------------------------------------------

# Part 25 --- Networking Architecture

## 27. Path

Conceptually:

``` text
client
  |
DNS
  |
LB / ingress / route if used
  |
Kubernetes service
  |
EndpointSlice
  |
pod IP
  |
Redis process
```

Troubleshoot layer by layer.

------------------------------------------------------------------------

# Part 26 --- CNI

## 28. Role

The Container Network Interface implementation provides pod networking.

CNI problems can appear as:

``` text
pod cannot get IP
pod-to-pod failure
routing failure
policy failure
```

------------------------------------------------------------------------

# Part 27 --- CNI Health

## 29. Discover

``` bash
kubectl get pods -A
```

Identify the cluster's actual CNI components.

Inspect:

``` text
readiness
restarts
logs
events
node-specific failures
```

------------------------------------------------------------------------

# Part 28 --- Service

## 30. Inspect

``` bash
kubectl get svc -n <namespace>
kubectl describe svc <service> -n <namespace>
```

Record:

``` text
type
cluster IP
ports
selectors
external endpoint if applicable
```

------------------------------------------------------------------------

# Part 29 --- EndpointSlice

## 31. Backend Reality

Inspect:

``` bash
kubectl get endpointslice -n <namespace>
```

A service with no usable endpoints cannot route to Redis pods.

------------------------------------------------------------------------

# Part 30 --- Pod Readiness

## 32. Endpoint Eligibility

Readiness can influence whether a pod is used as a service endpoint.

Check:

``` bash
kubectl get pods -n <namespace> -o wide
kubectl describe pod <pod> -n <namespace>
```

------------------------------------------------------------------------

# Part 31 --- DNS

## 33. Dependency

Applications commonly depend on DNS for Redis endpoints.

DNS failures can resemble Redis connection failures.

------------------------------------------------------------------------

# Part 32 --- DNS Test

## 34. Diagnostic Pod

From an approved diagnostic environment:

``` bash
getent hosts <redis-service>
```

If available and approved:

``` bash
nslookup <redis-service>
```

Do not modify production application images merely to add
troubleshooting tools.

------------------------------------------------------------------------

# Part 33 --- DNS Symptoms

## 35. Examples

``` text
temporary name resolution failure
NXDOMAIN
lookup timeout
stale client resolution
```

Correlate application logs with cluster DNS metrics.

------------------------------------------------------------------------

# Part 34 --- DNS Caching

## 36. Client Behavior

Client runtimes can cache DNS.

During endpoint changes, investigate:

``` text
JVM DNS TTL
OS resolver behavior
client library behavior
connection pooling
```

------------------------------------------------------------------------

# Part 35 --- Load Balancer

## 37. External Path

If a database endpoint uses a cloud/external load balancer, validate:

``` text
frontend health
backend health
health checks
security rules
idle timeout
connection limits
```

------------------------------------------------------------------------

# Part 36 --- Load-Balancer Health Check

## 38. Correct Target

A health check can be:

``` text
too shallow
too strict
misconfigured
```

Validate that health checks represent the intended service state without
causing false removal.

------------------------------------------------------------------------

# Part 37 --- Firewalls / Security Groups

## 39. Outside Kubernetes

Traffic may be blocked even when Kubernetes objects are correct.

Check the infrastructure path.

------------------------------------------------------------------------

# Part 38 --- NetworkPolicy

## 40. Kubernetes Policy

Inspect:

``` bash
kubectl get networkpolicy -A
```

Understand:

``` text
ingress
egress
namespace selectors
pod selectors
ports
```

------------------------------------------------------------------------

# Part 39 --- Default Deny

## 41. Design

Default-deny policies can be valuable but require explicit flows for:

``` text
Redis clients
Operator
cluster internode communication
DNS
monitoring
backup/integration paths
```

Use vendor-required connectivity.

------------------------------------------------------------------------

# Part 40 --- NetworkPolicy Test

## 42. Safe Lab

In a dedicated lab namespace:

``` text
allow expected client
deny unrelated client
```

Validate both positive and negative paths.

------------------------------------------------------------------------

# Part 41 --- Latency

## 43. Network P99

Track application/Redis latency alongside network telemetry.

High Redis command latency may include network delay outside the server.

------------------------------------------------------------------------

# Part 42 --- Packet Loss

## 44. Impact

Packet loss can produce:

``` text
retransmissions
timeouts
connection resets
retry amplification
```

Even small loss can hurt tail latency.

------------------------------------------------------------------------

# Part 43 --- Jitter

## 45. Impact

Variable network delay can produce unstable P99 even when average
latency appears acceptable.

------------------------------------------------------------------------

# Part 44 --- MTU

## 46. Mismatch

MTU problems can cause difficult-to-diagnose connectivity or
fragmentation behavior.

Use the cluster/network platform's supported MTU configuration.

------------------------------------------------------------------------

# Part 45 --- Connection Tracking

## 47. Infrastructure

High connection churn can stress:

``` text
NAT
conntrack
load balancer
client ephemeral ports
```

Redis connection-pooling guidance from Chapter 53 applies.

------------------------------------------------------------------------

# Part 46 --- Node Failure Domain

## 48. Node Loss

A Kubernetes node failure can cause:

``` text
Redis pod loss
volume attachment implications
traffic redistribution
Redis failover/recovery
```

Test the full application impact.

------------------------------------------------------------------------

# Part 47 --- Zone Failure Domain

## 49. Zone Loss

A zone failure can simultaneously affect:

``` text
nodes
volumes
network
load balancers
```

Placement must avoid concentrating Redis redundancy in one failure
domain.

------------------------------------------------------------------------

# Part 48 --- Failure-Domain Inventory

## 50. Record

``` text
Redis pod
Kubernetes node
node pool
zone
PV zone
service/LB dependencies
```

Map replicas/shards across domains.

------------------------------------------------------------------------

# Part 49 --- N-1

## 51. Capacity

After losing one approved failure unit, remaining infrastructure must
support the degraded service.

Validate:

``` text
CPU
memory
storage
network
Redis placement
application P99
```

------------------------------------------------------------------------

# Part 50 --- N-Zone

## 52. Regional Design

If the availability requirement includes zone loss, validate capacity
after losing one zone.

Do not infer this from node-level N-1.

------------------------------------------------------------------------

# Part 51 --- Node Pressure

## 53. Signals

Inspect:

``` bash
kubectl describe node <node>
```

Look for:

``` text
MemoryPressure
DiskPressure
PIDPressure
Ready
```

------------------------------------------------------------------------

# Part 52 --- Node Disk Pressure

## 54. Kubernetes Disk

Node filesystem pressure can affect pods even when Redis persistent
volumes have free space.

Monitor node root/runtime storage separately.

------------------------------------------------------------------------

# Part 53 --- CPU Pressure

## 55. Contention

Kubernetes node CPU contention can increase latency.

Compare:

``` text
pod CPU
node CPU
CPU throttling
application P99
```

------------------------------------------------------------------------

# Part 54 --- Memory Pressure

## 56. Risk

Memory pressure can trigger:

``` text
evictions
OOM kills
node instability
```

Redis nodes require deliberate memory capacity.

------------------------------------------------------------------------

# Part 55 --- OOMKilled

## 57. Investigate

``` bash
kubectl describe pod <pod> -n <namespace>
kubectl get pod <pod> -n <namespace> -o yaml
```

Determine whether:

``` text
container limit
node pressure
unexpected memory growth
```

caused termination.

------------------------------------------------------------------------

# Part 56 --- Pod Eviction

## 58. Not Redis Failover Test

Kubernetes eviction and Redis failover are different mechanisms.

Test their interaction.

------------------------------------------------------------------------

# Part 57 --- Graceful Termination

## 59. Shutdown

Understand supported termination behavior:

``` text
terminationGracePeriod
Redis process shutdown
failover
volume detach
```

Do not reduce grace periods blindly.

------------------------------------------------------------------------

# Part 58 --- PDB

## 60. Voluntary Disruption

``` bash
kubectl get pdb -A
```

A PDB helps protect against excessive voluntary disruption but does not
prevent all failures.

------------------------------------------------------------------------

# Part 59 --- Node Drain

## 61. Maintenance

Before drain:

``` text
Redis healthy
replicas healthy
remaining capacity sufficient
PDB understood
storage topology understood
monitoring active
```

------------------------------------------------------------------------

# Part 60 --- Drain Observation

## 62. Monitor

During approved maintenance:

``` text
pod termination/rescheduling
Redis failover
PVC attach/mount
REC/REDB status
application errors/P99
```

------------------------------------------------------------------------

# Part 61 --- Storage Failure Scenario

## 63. Safety

Do not detach or corrupt production volumes for testing.

Use:

``` text
nonproduction environment
provider-supported fault injection
tabletop where destructive testing is unsafe
```

------------------------------------------------------------------------

# Part 62 --- Slow Storage Scenario

## 64. More Realistic

Storage often degrades before failing.

Simulate or benchmark controlled latency/throughput constraints only
through approved mechanisms.

Observe:

``` text
Redis P99
storage latency
queueing
Operator/REC status
```

------------------------------------------------------------------------

# Part 63 --- Full Disk Scenario

## 65. Avoid Production

Use a disposable lab volume/workload.

Validate:

``` text
alerts fire before exhaustion
failure is diagnosable
recovery procedure works
```

------------------------------------------------------------------------

# Part 64 --- CSI Failure Scenario

## 66. Tabletop/Lab

Do not disable production CSI.

In nonproduction, use supported testing to understand:

``` text
new PVC provisioning failure
attach/mount failure
existing mounted volume behavior
```

------------------------------------------------------------------------

# Part 65 --- DNS Failure Scenario

## 67. Lab

Use isolated diagnostic/application workloads.

Validate behavior when:

``` text
DNS lookup fails
DNS is slow
endpoint changes
```

Observe client retry behavior.

------------------------------------------------------------------------

# Part 66 --- Network Partition

## 68. High Risk

Network partitions can affect:

``` text
client connectivity
Redis internode communication
Operator communication
Active-Active links
```

Use only approved fault-injection environments.

------------------------------------------------------------------------

# Part 67 --- Packet Loss Scenario

## 69. Lab

Inject bounded packet loss only in a dedicated nonproduction environment
using approved platform tools.

Measure:

``` text
P50/P95/P99
timeouts
retries
connections
Redis health
```

------------------------------------------------------------------------

# Part 68 --- Latency Injection

## 70. Lab

Inject bounded network delay in nonproduction.

Measure application and Redis behavior.

Stop at predefined safety thresholds.

------------------------------------------------------------------------

# Part 69 --- Load-Balancer Failure

## 71. Scenario

Use approved test endpoints to validate:

``` text
backend removal
health-check failure
endpoint recovery
client reconnection
```

------------------------------------------------------------------------

# Part 70 --- NetworkPolicy Failure

## 72. Scenario

Apply an intentionally restrictive policy only to disposable lab
workloads.

Confirm:

``` text
failure detected
policy identified
rollback immediate
```

------------------------------------------------------------------------

# Part 71 --- Node Failure Test

## 73. Scenario

In a qualified environment, remove or stop one approved node according
to the platform procedure.

Measure:

``` text
detection time
Redis failover
pod recovery
volume behavior
application errors
P99
time to restore redundancy
```

------------------------------------------------------------------------

# Part 72 --- Zone Failure Test

## 74. Scenario

Where safe and supported, simulate a zone outage in nonproduction.

Validate:

``` text
placement
remaining capacity
volume accessibility
service routing
Redis recovery
application routing
```

------------------------------------------------------------------------

# Part 73 --- Recovery Validation

## 75. Not Complete at "Green"

Recovery is complete only when:

``` text
Redis redundancy restored
pods stable
volumes healthy
services/endpoints correct
application P99 normal
backlog/retries normal
alerts cleared for correct reason
```

------------------------------------------------------------------------

# Part 74 --- Observability Layers

## 76. Four Layers

Build dashboards for:

``` text
1. application/client
2. Redis Enterprise
3. Kubernetes
4. infrastructure
```

------------------------------------------------------------------------

# Part 75 --- Application Layer

## 77. Monitor

``` text
request latency
Redis command latency
timeouts
connection errors
retry rate
fallback/source load
```

------------------------------------------------------------------------

# Part 76 --- Redis Layer

## 78. Monitor

``` text
database availability
latency
CPU
memory
connections
replication
persistence
shard/node health
```

------------------------------------------------------------------------

# Part 77 --- Kubernetes Layer

## 79. Monitor

``` text
pod readiness
restarts
OOMKilled
Pending
evictions
node conditions
PVC status
events
```

------------------------------------------------------------------------

# Part 78 --- Infrastructure Layer

## 80. Monitor

``` text
disk IOPS
disk throughput
disk latency
disk queueing
network packets
drops
retransmissions
LB health
node CPU/memory
```

------------------------------------------------------------------------

# Part 79 --- Timeline Correlation

## 81. Incident Analysis

Align:

``` text
application P99
Redis latency
pod events
node events
storage latency
network loss
change events
```

on one timeline.

This prevents false attribution.

------------------------------------------------------------------------

# Part 80 --- Baseline

## 82. Healthy Reference

Capture during normal operation:

``` text
P50/P95/P99
ops/sec
CPU
memory
storage IOPS
storage latency
network throughput
connections
```

Without a baseline, "high" is difficult to interpret.

------------------------------------------------------------------------

# Part 81 --- Capacity Headroom

## 83. Production

Define thresholds for:

``` text
node CPU
node memory
PVC capacity
storage IOPS
storage throughput
network
pod placement
```

Include failure-state headroom.

------------------------------------------------------------------------

# Part 82 --- Failure Budget

## 84. Ask

Can the platform tolerate:

``` text
one pod?
one node?
one volume?
one zone?
one load balancer path?
```

The answer must be demonstrated, not assumed.

------------------------------------------------------------------------

# Part 83 --- Failure Scenario 1: PVC Pending

## 85. Test

In a disposable namespace, request an invalid/nonexistent StorageClass.

Observe:

``` text
PVC Pending
events
pod scheduling impact
```

------------------------------------------------------------------------

# Part 84 --- Failure Scenario 2: Storage Latency

## 86. Test

Use approved nonproduction storage-performance controls.

Observe correlation between storage latency and Redis/application P99.

------------------------------------------------------------------------

# Part 85 --- Failure Scenario 3: Storage Capacity

## 87. Test

Use a disposable volume to approach an approved alert threshold.

Do not fill a production Redis volume.

Validate alert and remediation.

------------------------------------------------------------------------

# Part 86 --- Failure Scenario 4: DNS Failure

## 88. Test

Break DNS only for an isolated test workload.

Observe:

``` text
resolution errors
connection behavior
retries
recovery
```

------------------------------------------------------------------------

# Part 87 --- Failure Scenario 5: NetworkPolicy

## 89. Test

Block an isolated test client's Redis path.

Verify policy is identified quickly.

------------------------------------------------------------------------

# Part 88 --- Failure Scenario 6: Packet Loss

## 90. Test

Inject bounded packet loss in a lab.

Measure:

``` text
retransmissions
timeouts
P99
retry amplification
```

------------------------------------------------------------------------

# Part 89 --- Failure Scenario 7: Node Failure

## 91. Test

Remove one approved nonproduction node.

Measure full Redis and application recovery.

------------------------------------------------------------------------

# Part 90 --- Failure Scenario 8: Node Drain

## 92. Test

Perform controlled maintenance.

Validate PDB, placement, storage, and Redis behavior.

------------------------------------------------------------------------

# Part 91 --- Failure Scenario 9: Zone Failure

## 93. Test

Use supported simulation/tabletop if real failure injection is unsafe.

Validate zone-level capacity and storage dependencies.

------------------------------------------------------------------------

# Part 92 --- Failure Scenario 10: Load-Balancer Path

## 94. Test

Fail an approved test backend/path.

Validate health checks, endpoint removal, client reconnection, and
recovery.

------------------------------------------------------------------------

# Part 93 --- Troubleshooting Matrix

## 95. Common Problems

  Symptom                              Investigate
  ------------------------------------ --------------------------------------------
  pod Pending + PVC Pending            StorageClass, CSI, quota, topology
  pod Pending + PVC Bound              scheduler, taints, affinity, resources
  Redis P99 high + disk latency high   storage saturation/degradation
  Redis P99 high + disk normal         CPU, network, workload, Redis
  service exists/no connectivity       endpoints, readiness, NetworkPolicy
  intermittent connection timeout      packet loss, DNS, LB, client pool
  one node unhealthy                   node pressure, CNI, storage, hardware
  failover slow                        capacity, storage, network, Redis recovery
  zone loss causes outage              placement/capacity/storage topology
  PVC healthy but app slow             performance path, not object state

------------------------------------------------------------------------

# Part 94 --- Runbook 1: PVC Pending

## 96. Procedure

``` text
1. inspect PVC status/events.
2. inspect StorageClass.
3. inspect CSI health.
4. inspect quota.
5. inspect topology.
6. inspect pod scheduling.
7. correct supported storage dependency.
8. validate Redis reconciliation.
```

------------------------------------------------------------------------

# Part 95 --- Runbook 2: High Storage Latency

## 97. Procedure

``` text
1. confirm application impact.
2. inspect Redis P99.
3. inspect disk latency/queueing.
4. inspect IOPS/throughput.
5. inspect persistence/backup/recovery activity.
6. identify storage saturation or degradation.
7. reduce disruptive workload or scale/remediate storage.
8. validate return to baseline.
```

------------------------------------------------------------------------

# Part 96 --- Runbook 3: Redis Endpoint Unreachable

## 98. Procedure

``` text
1. test DNS.
2. inspect service.
3. inspect EndpointSlices.
4. inspect pod readiness.
5. inspect NetworkPolicy.
6. inspect LB/firewall path.
7. test approved connectivity.
8. validate client reconnection.
```

------------------------------------------------------------------------

# Part 97 --- Runbook 4: DNS Incident

## 99. Procedure

``` text
1. capture client error.
2. test resolution from approved workload.
3. inspect cluster DNS health.
4. inspect DNS service/endpoints.
5. inspect network policy/egress.
6. inspect client DNS caching.
7. restore resolver path.
8. validate new and existing connections.
```

------------------------------------------------------------------------

# Part 98 --- Runbook 5: Node Failure

## 100. Procedure

``` text
1. identify failed node.
2. inspect Redis impact.
3. inspect pod/PVC state.
4. validate failover.
5. validate remaining capacity.
6. restore/replace node through platform procedure.
7. monitor Redis recovery/redundancy.
8. validate application SLO.
```

------------------------------------------------------------------------

# Part 99 --- Runbook 6: Node Maintenance

## 101. Procedure

``` text
1. validate Redis health.
2. validate redundancy/headroom.
3. inspect PDB and placement.
4. cordon/drain using approved procedure.
5. monitor pod/volume movement.
6. monitor Redis/application SLO.
7. restore capacity.
8. validate steady state.
```

------------------------------------------------------------------------

# Part 100 --- Runbook 7: Zone Failure

## 102. Procedure

``` text
1. identify affected zone.
2. inventory lost nodes/volumes.
3. inspect Redis placement.
4. validate remaining capacity.
5. validate service/LB routing.
6. protect application traffic.
7. restore supported infrastructure/Redis redundancy.
8. validate recovery and document gaps.
```

------------------------------------------------------------------------

# Part 101 --- Runbook 8: Network Degradation

## 103. Procedure

``` text
1. confirm timeout/P99 impact.
2. inspect packet loss/retransmission/latency.
3. identify affected path/nodes.
4. inspect CNI and NetworkPolicy.
5. inspect LB/firewall.
6. control client retry amplification.
7. remediate network path.
8. validate Redis/application recovery.
```

------------------------------------------------------------------------

# Part 102 --- Storage Inventory Template

## 104. Record

``` text
Cluster:
Redis namespace:
StorageClass:
CSI driver:
Volume type:
Capacity/PVC:
IOPS:
Throughput:
Latency baseline:
Expansion supported:
Binding mode:
Reclaim policy:
Zones:
Monitoring:
Owner:
```

------------------------------------------------------------------------

# Part 103 --- Network Inventory Template

## 105. Record

``` text
CNI:
Cluster DNS:
Redis service:
Service type:
Load balancer:
Ports:
NetworkPolicies:
Firewall/security groups:
Client networks:
Cross-zone path:
Monitoring:
Owner:
```

------------------------------------------------------------------------

# Part 104 --- Failure-Domain Template

## 106. Record

``` text
Redis pod:
Redis role/shard:
Node:
Node pool:
Zone:
PVC:
PV zone:
Service path:
Failure impact:
Recovery path:
```

------------------------------------------------------------------------

# Part 105 --- Incident Evidence Template

## 107. Record

``` text
Start time:
Application symptom:
Redis symptom:
Affected pods:
Affected nodes:
Affected zone:
PVC/PV state:
Storage latency:
Storage IOPS:
Network loss:
DNS status:
LB status:
Recent changes:
Recovery time:
Root cause:
Corrective action:
```

------------------------------------------------------------------------

# Part 106 --- Production Acceptance

## 108. Storage

-   [ ] StorageClass documented;
-   [ ] CSI driver/version documented;
-   [ ] volume topology understood;
-   [ ] reclaim policy understood;
-   [ ] expansion procedure documented;
-   [ ] IOPS qualified;
-   [ ] throughput qualified;
-   [ ] P95/P99 storage latency baselined;
-   [ ] capacity alerts configured;
-   [ ] storage degradation runbook tested.

## 109. Networking

-   [ ] CNI documented;
-   [ ] Redis service/endpoints validated;
-   [ ] DNS path validated;
-   [ ] client DNS behavior understood;
-   [ ] load-balancer health checks validated;
-   [ ] firewall/security rules documented;
-   [ ] NetworkPolicies reviewed;
-   [ ] required Operator/Redis/DNS flows documented;
-   [ ] network degradation monitoring enabled.

## 110. Failure Domains

-   [ ] Redis placement mapped to nodes/zones;
-   [ ] PV topology mapped;
-   [ ] node N-1 validated;
-   [ ] zone failure requirement defined;
-   [ ] zone-loss capacity validated where required;
-   [ ] node drain tested;
-   [ ] node failure tested;
-   [ ] recovery time measured;
-   [ ] redundancy restoration validated.

## 111. Operational Acceptance

-   [ ] four-layer observability implemented;
-   [ ] healthy baseline recorded;
-   [ ] failure stop conditions documented;
-   [ ] ten failure scenarios completed;
-   [ ] eight runbooks reviewed;
-   [ ] production acceptance completed.

------------------------------------------------------------------------

# 112. Knowledge Validation

1.  Why is Kubernetes object health not enough to prove Redis health?
2.  What is the PVC/PV/StorageClass/CSI relationship?
3.  What does a StorageClass define?
4.  Why can storage topology affect pod scheduling?
5.  Why must reclaim policy be understood?
6.  Why is storage expansion not always reversible?
7.  What are the three primary storage performance dimensions?
8.  Why can IOPS saturate before throughput?
9.  Why can throughput saturate before IOPS?
10. Why is P99 storage latency important?
11. What can queue depth indicate?
12. Why can burstable storage mislead short benchmarks?
13. Why test persistence and backup under application load?
14. Why is recovery often more resource-intensive than steady state?
15. What role does CNI play?
16. Why should EndpointSlices be inspected?
17. Why can DNS failure look like Redis failure?
18. Why does client DNS caching matter?
19. What can NetworkPolicy block?
20. Why can packet loss strongly affect P99?
21. Why is zone failure different from node failure?
22. Why should Redis/PV placement be mapped to failure domains?
23. Why must N-1 include storage and network?
24. Why can node disk pressure matter even when Redis PVC has space?
25. Why can Kubernetes eviction and Redis failover interact?
26. What does a PDB protect against?
27. Why should storage/network failure injection be isolated from
    production?
28. What four observability layers should be correlated?
29. Why is recovery not complete merely because objects are green?
30. What must pass before Kubernetes infrastructure is production-ready
    for Redis?

------------------------------------------------------------------------

# 113. Hands-On Acceptance Checklist

-   [ ] Mapped Redis infrastructure dependencies.
-   [ ] Inspected StorageClasses.
-   [ ] Inspected Redis PVCs/PVs.
-   [ ] Recorded CSI driver.
-   [ ] Reviewed binding mode/reclaim policy.
-   [ ] Mapped PV topology.
-   [ ] Verified expansion capability.
-   [ ] Recorded storage IOPS/throughput/latency baseline.
-   [ ] Reviewed persistence I/O.
-   [ ] Reviewed backup I/O.
-   [ ] Reviewed recovery I/O.
-   [ ] Identified CNI.
-   [ ] Inspected Redis services.
-   [ ] Inspected EndpointSlices.
-   [ ] Tested DNS from approved diagnostic workload.
-   [ ] Reviewed NetworkPolicies.
-   [ ] Reviewed load-balancer/firewall path.
-   [ ] Mapped Redis pods to nodes/zones.
-   [ ] Mapped PVs to zones.
-   [ ] Reviewed node pressure signals.
-   [ ] Reviewed PDBs.
-   [ ] Tested approved node drain.
-   [ ] Tested PVC Pending failure.
-   [ ] Tested isolated DNS failure.
-   [ ] Tested isolated NetworkPolicy failure.
-   [ ] Tested bounded packet-loss scenario.
-   [ ] Tested node failure.
-   [ ] Completed zone-failure test/tabletop.
-   [ ] Validated recovery.
-   [ ] Completed ten failure scenarios.
-   [ ] Completed eight runbooks.
-   [ ] Completed production acceptance.

------------------------------------------------------------------------

# 114. Cleanup

Remove only disposable Chapter 63 test resources.

Restore:

``` text
temporary NetworkPolicies
fault-injection rules
test DNS overrides
temporary load-balancer changes
test workloads
test PVCs
node cordons where appropriate
```

Verify:

``` bash
kubectl get nodes
kubectl get pods -A
kubectl get pvc -A
kubectl get events -A --sort-by=.lastTimestamp
```

Confirm:

``` text
Redis Enterprise healthy
REC/REDB healthy
all intended nodes available
storage healthy
DNS healthy
services/endpoints correct
NetworkPolicies restored
application P99 at baseline
```

Never delete production PVCs/PVs as tutorial cleanup.

Never fill, detach, corrupt, or latency-inject production Redis storage
for a lab.

------------------------------------------------------------------------

# 115. Key Takeaways

1.  Redis Enterprise Kubernetes availability depends on storage,
    networking, nodes, and failure-domain design.
2.  A Bound PVC does not prove acceptable storage performance.
3.  Storage must be qualified for IOPS, throughput, and tail latency.
4.  Storage topology can constrain Redis pod recovery.
5.  Reclaim and expansion behavior must be understood before incidents.
6.  Persistence, backup, and recovery can create significant I/O.
7.  Recovery capacity can be more demanding than steady state.
8.  CNI health affects pod connectivity.
9.  Services require healthy backends/EndpointSlices.
10. DNS is part of the Redis application path.
11. Client DNS caching can affect endpoint transitions.
12. NetworkPolicy must permit all required Redis, Operator, DNS, and
    monitoring flows.
13. Packet loss and jitter can drive tail latency and retries.
14. Load balancers and infrastructure firewalls are outside Kubernetes
    service state but inside the application path.
15. Node failure and zone failure are different resilience tests.
16. Redis and PV placement must be mapped to failure domains.
17. N-1 must include CPU, memory, storage, network, and Redis placement.
18. Node root-disk pressure is separate from Redis PVC capacity.
19. Kubernetes eviction and Redis failover must be tested together.
20. PDBs protect voluntary disruption but cannot prevent infrastructure
    failure.
21. Failure injection must use isolated nonproduction environments and
    stop conditions.
22. Recovery is not complete until redundancy and application SLO are
    restored.
23. Application, Redis, Kubernetes, and infrastructure telemetry should
    share a timeline.
24. Healthy baselines are essential for incident comparison.
25. Production readiness requires demonstrated storage, network, node,
    zone, and recovery behavior---not just green Kubernetes objects.

------------------------------------------------------------------------

# 116. References

Validate storage classes, CSI behavior, supported volume configurations,
networking requirements, failure-domain recommendations, and operational
procedures against the exact Redis Enterprise Kubernetes Operator
version, Kubernetes platform, storage provider, and current official
documentation.

Recommended documentation areas:

-   Redis Enterprise for Kubernetes
-   Redis Enterprise Kubernetes persistent storage
-   Redis Enterprise Kubernetes networking
-   Redis Enterprise Kubernetes sizing and placement
-   Redis Enterprise Kubernetes high availability
-   Redis Enterprise Kubernetes backup and recovery
-   Kubernetes StorageClasses
-   Kubernetes PersistentVolumes and PersistentVolumeClaims
-   Kubernetes CSI
-   Kubernetes topology-aware volume provisioning
-   Kubernetes Services and EndpointSlices
-   Kubernetes DNS
-   Kubernetes NetworkPolicy
-   Kubernetes node-pressure eviction
-   Kubernetes PodDisruptionBudget
-   cloud-provider disk and load-balancer performance documentation

------------------------------------------------------------------------

# Next Chapter

**Chapter 64 --- Redis Enterprise Kubernetes Upgrade, Backup & Recovery
Operations**

Chapter 64 will combine lifecycle and resilience operations:
Operator/CRD/Redis Enterprise upgrade sequencing, Kubernetes
compatibility, preflight checks, backups, restore validation, node
maintenance, rollback boundaries, failed-upgrade recovery, disaster
recovery drills, GitOps coordination, observability, failure scenarios,
troubleshooting, runbooks, and production acceptance.
