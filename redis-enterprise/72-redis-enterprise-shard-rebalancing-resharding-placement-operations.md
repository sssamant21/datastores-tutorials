# Chapter 72 --- Redis Enterprise Shard Rebalancing, Resharding & Placement Operations

**Status:** Canonical\
**Track:** Redis Enterprise / Redis Software Production Engineering\
**Part:** Part 12 --- Advanced Operations, FinOps & Resilience\
**Level:** Advanced → Shard Topology, Data Movement & Placement
Engineering\
**Audience:** SREs, DBREs, Redis Administrators, Platform Engineers,
Kubernetes Administrators, Capacity Engineers\
**Lab type:** Shard topology discovery, placement analysis, skew
detection, scale-out/in, rebalance and resharding planning,
failure-domain validation, node maintenance/replacement, data-movement
observability, stop conditions, troubleshooting, runbooks, and
production acceptance

------------------------------------------------------------------------

# 1. Objective

Redis Enterprise distributes databases across shards and nodes to
provide capacity, performance, and resilience.

But adding a node does not automatically mean:

``` text
problem solved
```

Production engineers must understand:

``` text
where shards are placed
where replicas are placed
which nodes carry load
which shards are hot
what happens during movement
whether failure domains remain safe
whether the cluster has enough temporary capacity
```

A poorly planned rebalance or resharding event can increase:

``` text
CPU
network traffic
memory pressure
storage I/O
replication traffic
application latency
recovery risk
```

This chapter develops a production-safe approach to shard placement and
data movement.

By the end of this chapter, you should be able to:

-   inventory Redis Enterprise shard topology;
-   distinguish shard count from node count;
-   understand primary/replica placement;
-   identify placement and workload skew;
-   distinguish capacity skew from hot-key skew;
-   plan scale-out and scale-in;
-   understand rebalancing and resharding;
-   estimate data-movement cost;
-   preserve failure-domain resilience;
-   execute node maintenance/replacement safely;
-   monitor migration/rebalance progress;
-   define stop conditions;
-   troubleshoot stalled or harmful data movement;
-   validate application behavior during movement;
-   execute production runbooks and acceptance gates.

------------------------------------------------------------------------

# 2. Core Production Principle

Never treat shard movement as a background event that needs no capacity
planning.

During data movement, the cluster may need to serve:

``` text
normal application traffic
+
replication
+
data transfer
+
recovery/rebalance work
```

at the same time.

------------------------------------------------------------------------

# Part 1 --- Topology Model

## 3. Conceptual View

``` text
Redis Enterprise cluster
    |
    +-- node A
    |    +-- shard 1 primary
    |    +-- shard 4 replica
    |
    +-- node B
    |    +-- shard 1 replica
    |    +-- shard 2 primary
    |
    +-- node C
         +-- shard 2 replica
         +-- shard 3 primary
```

Exact topology depends on database configuration and Redis Enterprise
version.

------------------------------------------------------------------------

# Part 2 --- Shard vs Node

## 4. Distinction

A node is infrastructure.

A shard is a partition of database responsibility.

Do not assume:

``` text
1 node = 1 shard
```

A node can host multiple shard processes depending on supported
architecture and configuration.

------------------------------------------------------------------------

# Part 3 --- Primary and Replica

## 5. Resilience

For replicated databases, a primary shard has one or more replicas
according to configured topology.

Production placement should avoid creating a failure domain where loss
of one infrastructure component removes both required copies.

------------------------------------------------------------------------

# Part 4 --- Failure Domain

## 6. Examples

``` text
node
rack
availability zone
host group
power domain
```

The relevant domain depends on deployment.

------------------------------------------------------------------------

# Part 5 --- Topology Inventory

## 7. Record

For every database:

``` text
database
memory allocation
shard count
replication
primary placement
replica placement
node
zone
CPU
memory
network
storage
```

Use Redis Enterprise-supported UI/API/CLI/metrics for the exact deployed
version.

------------------------------------------------------------------------

# Part 6 --- Node Inventory

## 8. Record

``` text
node ID
hostname
zone
role/state
CPU capacity
memory capacity
storage capacity
network capacity
hosted shards
maintenance state
```

------------------------------------------------------------------------

# Part 7 --- Shard Inventory

## 9. Record

``` text
database
shard ID
primary/replica
node
zone
memory
CPU
ops/sec
network
status
```

------------------------------------------------------------------------

# Part 8 --- Healthy Placement

## 10. Characteristics

A healthy placement generally aims for:

``` text
failure-domain separation
sufficient node headroom
balanced resource consumption
supported placement rules
predictable recovery
```

Not every shard must have identical CPU.

------------------------------------------------------------------------

# Part 9 --- Balanced Does Not Mean Equal

## 11. Workload

Two shards with equal memory may have very different:

``` text
ops/sec
CPU
network
latency
```

because workload distribution differs.

------------------------------------------------------------------------

# Part 10 --- Resource Dimensions

## 12. Evaluate

Placement must consider:

``` text
memory
CPU
network
storage
connections
```

Do not balance only by dataset bytes.

------------------------------------------------------------------------

# Part 11 --- Memory Skew

## 13. Pattern

Example:

``` text
shard A = 20 GB
shard B = 21 GB
shard C = 60 GB
```

Investigate why.

------------------------------------------------------------------------

# Part 12 --- CPU Skew

## 14. Pattern

Example:

``` text
shard A = 20% CPU
shard B = 25%
shard C = 90%
```

Possible:

``` text
hot key
hot tenant
command mix
uneven traffic
```

Adding nodes alone may not remove the logical hot key.

------------------------------------------------------------------------

# Part 13 --- Network Skew

## 15. Pattern

Large values or read-heavy hot shards can drive network saturation even
when CPU is moderate.

Monitor bytes/sec.

------------------------------------------------------------------------

# Part 14 --- Connection Skew

## 16. Pattern

Client routing or application topology can concentrate connections.

Review endpoint/proxy/client behavior.

------------------------------------------------------------------------

# Part 15 --- Hot Key vs Placement Problem

## 17. Critical Distinction

If one logical key dominates traffic:

``` text
moving the shard
```

moves the hotspot.

It does not eliminate it.

Use hot-key/data-model mitigation.

------------------------------------------------------------------------

# Part 16 --- Hot Tenant

## 18. Multi-Tenant

One tenant can dominate a shard's workload.

Possible design responses include:

``` text
better key distribution
tenant isolation
database isolation
application rate limits
```

depending on requirements.

------------------------------------------------------------------------

# Part 17 --- Sharding Key Distribution

## 19. Application Design

Redis Cluster-style hash-slot distribution is influenced by key names
and hash tags where applicable.

Poor key-tag design can intentionally or accidentally concentrate
related keys.

Validate exact Redis Enterprise database behavior before redesign.

------------------------------------------------------------------------

# Part 18 --- Hash Tags

## 20. Awareness

Hash tags can keep keys together for multi-key operations, but excessive
use can create skew.

Tradeoff:

``` text
co-location
vs
distribution
```

------------------------------------------------------------------------

# Part 19 --- Baseline

## 21. Before Movement

Capture:

``` text
P50/P95/P99
ops/sec
CPU per node/shard
memory per node/shard
network
storage I/O
errors
replication health
connections
```

------------------------------------------------------------------------

# Part 20 --- Change Trigger

## 22. Valid Reasons

Examples:

``` text
capacity threshold
node maintenance
node replacement
hardware generation change
failure-domain correction
persistent imbalance
database growth
```

------------------------------------------------------------------------

# Part 21 --- Weak Trigger

## 23. Avoid

Do not rebalance solely because:

``` text
graphs look uneven
```

First determine whether the difference is harmful.

------------------------------------------------------------------------

# Part 22 --- Scale Out

## 24. Concept

Scale-out adds cluster capacity.

But additional capacity is useful only after supported placement/data
movement makes use of it.

------------------------------------------------------------------------

# Part 23 --- Scale-Out Preflight

## 25. Verify

``` text
new node healthy
version compatible
network healthy
storage healthy
time sync healthy
failure domain correct
resource capacity correct
cluster healthy
```

------------------------------------------------------------------------

# Part 24 --- N+1 Capacity

## 26. Principle

Do not scale only when the cluster is already critically saturated.

Maintain enough headroom to perform movement and survive failures.

------------------------------------------------------------------------

# Part 25 --- Scale-In

## 27. Higher Risk

Removing capacity requires ensuring workloads can fit safely on
remaining nodes.

Check:

``` text
memory
CPU
network
storage
failure domains
recovery headroom
```

------------------------------------------------------------------------

# Part 26 --- Scale-In Gate

## 28. Formula Concept

For each remaining resource dimension:

``` text
post-scale-in peak
<
safe supported capacity
```

with failure headroom.

------------------------------------------------------------------------

# Part 27 --- Rebalancing

## 29. Concept

Rebalancing changes placement to improve distribution or satisfy
topology constraints.

Exact mechanics are product/version specific.

------------------------------------------------------------------------

# Part 28 --- Resharding

## 30. Concept

Resharding changes how database data is partitioned across shards.

It can involve significant data movement.

------------------------------------------------------------------------

# Part 29 --- Rebalance vs Reshard

## 31. Distinguish

Conceptually:

``` text
rebalance = placement adjustment
reshard = partition topology/data redistribution
```

Exact terminology/actions should follow Redis Enterprise documentation
for the deployed version.

------------------------------------------------------------------------

# Part 30 --- Data Movement Cost

## 32. Components

Moving data can consume:

``` text
source CPU
destination CPU
source network
destination network
memory
storage I/O
replication bandwidth
```

------------------------------------------------------------------------

# Part 31 --- Transfer-Time Estimate

## 33. Simple Model

``` text
transfer time
≈
data to move / effective transfer throughput
```

But effective throughput must leave capacity for application traffic.

------------------------------------------------------------------------

# Part 32 --- Example

## 34. Model

If:

``` text
data to move = 500 GB
safe effective movement throughput = 50 MB/s
```

rough lower-bound transfer time:

``` text
500 GB / 50 MB/s
```

is hours, not minutes.

Add overhead and validation time.

------------------------------------------------------------------------

# Part 33 --- Network Headroom

## 35. Guardrail

If normal network utilization is already 85-90%, large movement can
threaten application latency.

Scale or reduce competing load first.

------------------------------------------------------------------------

# Part 34 --- CPU Headroom

## 36. Guardrail

If nodes are near sustained CPU saturation:

``` text
movement + normal workload
```

can create queueing/tail latency.

------------------------------------------------------------------------

# Part 35 --- Memory Headroom

## 37. Guardrail

Movement/recovery may require temporary memory overhead.

Do not plan using only steady-state dataset size.

------------------------------------------------------------------------

# Part 36 --- Storage Headroom

## 38. Guardrail

For deployments where persistence/storage participates in the
movement/recovery path, ensure:

``` text
capacity
IOPS
throughput
latency
```

are sufficient.

------------------------------------------------------------------------

# Part 37 --- Replication Traffic

## 39. Include

Replicated databases may require additional transfer/recovery work.

Account for replica topology.

------------------------------------------------------------------------

# Part 38 --- Multiple Concurrent Moves

## 40. Risk

Parallel movement can shorten elapsed time but increase:

``` text
CPU
network
I/O
latency risk
```

Use supported concurrency and operational limits.

------------------------------------------------------------------------

# Part 39 --- Maintenance Window

## 41. Estimate

Include:

``` text
preflight
movement
stabilization
validation
rollback/recovery allowance
```

not only theoretical copy time.

------------------------------------------------------------------------

# Part 40 --- Stop Conditions

## 42. Define Before Change

Examples:

``` text
P99 > agreed threshold
error rate > threshold
CPU sustained > threshold
network saturation
replication unhealthy
node health degraded
movement stalled
```

------------------------------------------------------------------------

# Part 41 --- Abort vs Pause

## 43. Product Specific

Some data movement may not be instantly reversible.

Before change, determine:

``` text
can operation pause?
can it cancel?
what state exists after cancellation?
what is rollback?
```

from exact version documentation.

------------------------------------------------------------------------

# Part 42 --- Point of No Return

## 44. Change Plan

Explicitly document any stage after which rollback becomes:

``` text
forward recovery
```

rather than simple reversal.

------------------------------------------------------------------------

# Part 43 --- Application SLO

## 45. During Movement

Define:

``` text
P95
P99
error rate
timeout rate
```

that must remain acceptable.

------------------------------------------------------------------------

# Part 44 --- Canary Movement

## 46. Principle

Where supported, prefer limited initial movement/maintenance scope
before broad changes.

Observe behavior.

------------------------------------------------------------------------

# Part 45 --- One Change at a Time

## 47. Operational

Avoid combining:

``` text
node scale
Redis upgrade
network change
resharding
client release
```

unless required and tested.

------------------------------------------------------------------------

# Part 46 --- Failure-Domain Placement

## 48. Rule

Primary and replica copies should satisfy supported failure-domain
separation.

Validate after every movement.

------------------------------------------------------------------------

# Part 47 --- Zone Capacity

## 49. N-1 Zone

If architecture targets zonal resilience, remaining zones must have
enough capacity to sustain required service after a zone loss.

------------------------------------------------------------------------

# Part 48 --- Node Failure During Movement

## 50. Plan

Ask before starting:

``` text
what if a source node fails?
what if destination fails?
what if another unrelated node fails?
```

Movement reduces operational simplicity.

------------------------------------------------------------------------

# Part 49 --- Node Maintenance

## 51. Preflight

Before draining/restarting/replacing a node:

``` text
cluster healthy
replicas healthy
capacity sufficient
no conflicting movement
application stable
```

------------------------------------------------------------------------

# Part 50 --- Kubernetes Node Drain

## 52. Operator Environment

For Redis Enterprise on Kubernetes, node drain interacts with:

``` text
Redis Enterprise Operator
pod scheduling
PDB
storage topology
failure domains
```

Use supported maintenance procedure.

------------------------------------------------------------------------

# Part 51 --- PDB

## 53. Purpose

PodDisruptionBudgets can limit voluntary disruption.

Do not bypass them casually to force maintenance.

------------------------------------------------------------------------

# Part 52 --- Storage Attachment

## 54. Kubernetes

Stateful movement/rescheduling can depend on:

``` text
PVC
CSI
zone
attachment/detachment
```

Validate before maintenance.

------------------------------------------------------------------------

# Part 53 --- Node Replacement

## 55. Reasons

``` text
hardware fault
OS issue
instance-family change
capacity change
lifecycle replacement
```

Treat as topology change.

------------------------------------------------------------------------

# Part 54 --- Replacement Sequence

## 56. Concept

``` text
add/validate replacement capacity
ensure healthy topology
move/recover workload through supported procedure
validate
remove old capacity
```

Exact sequence is version/platform specific.

------------------------------------------------------------------------

# Part 55 --- Failed Node

## 57. Emergency

A failed node is different from planned replacement.

Priorities:

``` text
service availability
replication health
capacity
recovery
```

before optimization.

------------------------------------------------------------------------

# Part 56 --- Rebalance After Failure

## 58. Caution

Do not immediately optimize placement while recovery is still consuming
resources unless product guidance requires it.

Stabilize first.

------------------------------------------------------------------------

# Part 57 --- Rebalance After Scale-Out

## 59. Observe

Adding nodes can create opportunity to distribute resource load.

Measure before and after.

------------------------------------------------------------------------

# Part 58 --- Rebalance After Scale-In

## 60. Precondition

All required data/workload must fit safely on remaining capacity before
node removal.

------------------------------------------------------------------------

# Part 59 --- Memory-Balanced, CPU-Unbalanced

## 61. Example

``` text
Node A memory 60%, CPU 25%
Node B memory 61%, CPU 30%
Node C memory 59%, CPU 90%
```

Memory is balanced.

Workload is not.

Investigate hot shard/key rather than blindly moving bytes.

------------------------------------------------------------------------

# Part 60 --- CPU-Balanced, Network-Unbalanced

## 62. Example

Large response workloads may saturate one path.

Inspect:

``` text
bytes/sec
client locality
proxy path
hot keys
```

------------------------------------------------------------------------

# Part 61 --- Shard Count

## 63. Capacity Decision

Shard count affects:

``` text
parallelism
placement flexibility
overhead
recovery behavior
```

Do not increase shard count without workload evidence.

------------------------------------------------------------------------

# Part 62 --- Too Few Shards

## 64. Possible Impact

``` text
limited parallelism
large shard recovery unit
placement inflexibility
```

depending on architecture/workload.

------------------------------------------------------------------------

# Part 63 --- Too Many Shards

## 65. Possible Impact

``` text
process/metadata overhead
operational complexity
more placement objects
```

Use vendor guidance and measured workload.

------------------------------------------------------------------------

# Part 64 --- Shard Size

## 66. Redis Context

Unlike disk-centric systems, Redis shard sizing must be evaluated in
terms of:

``` text
memory
recovery
CPU
network
operational behavior
```

Use Redis Enterprise-specific sizing guidance rather than importing
Elasticsearch shard rules.

------------------------------------------------------------------------

# Part 65 --- Recovery Unit

## 67. Operational

Larger shard data volumes can increase time required for:

``` text
replica recovery
movement
node replacement
```

Measure recovery throughput.

------------------------------------------------------------------------

# Part 66 --- Recovery-Time Objective

## 68. Capacity

If:

``` text
shard data = D
effective recovery throughput = R
```

rough recovery copy time:

``` text
D / R
```

before additional overhead.

------------------------------------------------------------------------

# Part 67 --- Growth

## 69. Forecast

Track:

``` text
database GB/day
shard memory growth
ops growth
network growth
```

Do not wait for emergency resharding.

------------------------------------------------------------------------

# Part 68 --- Placement Constraints

## 70. Sources

Constraints can arise from:

``` text
failure domains
rack/zone awareness
node capacity
Kubernetes scheduling
storage topology
policy
```

------------------------------------------------------------------------

# Part 69 --- Kubernetes Affinity

## 71. Platform

Node affinity/anti-affinity/topology rules can affect Redis Enterprise
pod placement.

Do not manually alter Operator-managed resources outside supported
patterns.

------------------------------------------------------------------------

# Part 70 --- Taints and Tolerations

## 72. Scheduling

A node may have capacity but remain unusable for Redis pods because of
scheduling constraints.

Check before scale-out.

------------------------------------------------------------------------

# Part 71 --- Resource Requests

## 73. Scheduling

New capacity must be schedulable.

A physically large node does not help if Kubernetes cannot place the
required pods due to requests/constraints.

------------------------------------------------------------------------

# Part 72 --- Resource Limits

## 74. Runtime

Too-tight limits can create throttling/OOM risk during
recovery/movement.

Validate supported sizing.

------------------------------------------------------------------------

# Part 73 --- Topology Spread

## 75. Resilience

Where applicable, use supported topology mechanisms to reduce correlated
failure.

Validate actual placement, not only declared intent.

------------------------------------------------------------------------

# Part 74 --- Placement Drift

## 76. Detect

After:

``` text
failures
maintenance
autoscaling
upgrade
```

placement may differ from the preferred baseline.

Audit regularly.

------------------------------------------------------------------------

# Part 75 --- Rebalance Observability

## 77. Monitor

During movement:

``` text
movement state/progress
source CPU
destination CPU
network bytes
memory
storage I/O
replication
P99
errors
```

------------------------------------------------------------------------

# Part 76 --- Progress Stall

## 78. Diagnose

If movement appears stalled:

``` text
node health
network
storage
capacity
replication
cluster events/logs
```

before restarting components.

------------------------------------------------------------------------

# Part 77 --- Throughput Collapse

## 79. Diagnose

Movement throughput may fall due to:

``` text
application load
network saturation
destination CPU
storage bottleneck
recovery contention
```

------------------------------------------------------------------------

# Part 78 --- Latency Regression

## 80. Diagnose

If P99 rises during movement:

1.  determine affected database/shard;
2.  compare CPU/network/storage;
3.  inspect application traffic;
4.  apply stop condition if crossed.

------------------------------------------------------------------------

# Part 79 --- Error Increase

## 81. Serious

Connection/command errors during movement require immediate correlation
with:

``` text
proxy
failover
node health
client reconnect
```

------------------------------------------------------------------------

# Part 80 --- Client Reconnect

## 82. Movement / Failover

Some topology events may trigger transient reconnect behavior depending
on architecture.

Clients must be qualified for:

``` text
retry
backoff
jitter
connection reuse
```

------------------------------------------------------------------------

# Part 81 --- Data Correctness

## 83. Validate

After supported resharding/rebalance:

``` text
application reads/writes
key counts where meaningful
critical synthetic records
replication health
```

Do not rely only on "operation complete."

------------------------------------------------------------------------

# Part 82 --- Synthetic Validation

## 84. Namespace

Use:

``` text
tutorial:chapter72:*
```

for lab validation.

------------------------------------------------------------------------

# Part 83 --- Pre/Post Comparison

## 85. Record

``` text
before placement
after placement
before CPU
after CPU
before memory
after memory
before network
after network
before P99
after P99
```

------------------------------------------------------------------------

# Part 84 --- Success Criteria

## 86. Example

``` text
cluster healthy
replication healthy
failure domains correct
P99 within SLO
errors normal
resource headroom improved
no movement remaining
```

------------------------------------------------------------------------

# Part 85 --- Rollback Validation

## 87. Before Change

Rollback must state:

``` text
trigger
owner
method
time estimate
capacity requirement
validation
```

------------------------------------------------------------------------

# Part 86 --- Backups

## 88. Safety

For high-risk topology/database changes, verify backup/recovery posture
according to data durability requirements.

Backup is not a substitute for safe movement planning.

------------------------------------------------------------------------

# Part 87 --- Change Freeze

## 89. Recommended

During major resharding:

avoid unrelated changes to:

``` text
application
network
Redis config
Kubernetes
```

where operationally possible.

------------------------------------------------------------------------

# Part 88 --- Communication

## 90. Change Window

Communicate:

``` text
start
expected duration
risk
stop conditions
status checkpoints
completion
```

------------------------------------------------------------------------

# Part 89 --- Evidence

## 91. Preserve

Capture:

``` text
topology before
topology after
metrics
events
logs
change commands/API requests
validation
```

------------------------------------------------------------------------

# Part 90 --- Automation

## 92. Safe Automation

Automation should include:

``` text
preflight
approval
health gates
progress monitoring
stop conditions
post-validation
```

not just "run rebalance."

------------------------------------------------------------------------

# Part 91 --- API / CLI

## 93. Version Specific

Redis Enterprise administrative APIs/CLI capabilities vary by version.

Use current official documentation for:

``` text
node add/remove
database shard changes
placement
rebalance
status
```

Do not copy commands from a different release without validation.

------------------------------------------------------------------------

# Part 92 --- Lab 1: Topology Inventory

## 94. Exercise

In nonproduction:

1.  list cluster nodes;
2.  list databases;
3.  identify shard count;
4.  map shard placement;
5.  map replicas;
6.  map zones.

Use supported UI/API/CLI.

------------------------------------------------------------------------

# Part 93 --- Lab 2: Resource Heatmap

## 95. Exercise

Build table:

  Node/Shard     CPU   Memory   Network   Ops/sec
  ------------ ----- -------- --------- ---------
  A                                     
  B                                     
  C                                     

Identify skew.

------------------------------------------------------------------------

# Part 94 --- Lab 3: Hot Key vs Placement

## 96. Exercise

Generate bounded traffic to one synthetic key.

Observe:

``` text
hot shard
```

Then reason why moving the shard does not remove the hot key.

------------------------------------------------------------------------

# Part 95 --- Lab 4: Distributed Keys

## 97. Exercise

Generate similar traffic across many distributed synthetic keys.

Compare resource distribution.

------------------------------------------------------------------------

# Part 96 --- Lab 5: Scale-Out Tabletop

## 98. Exercise

Given:

``` text
3 nodes
70% memory
65% CPU
```

design a scale-out plan including:

``` text
new-node validation
movement
SLO
stop conditions
```

------------------------------------------------------------------------

# Part 97 --- Lab 6: Scale-In Tabletop

## 99. Exercise

Given current per-node peaks, calculate whether remaining nodes can
safely handle:

``` text
normal load
+
one additional failure
```

after removal.

------------------------------------------------------------------------

# Part 98 --- Lab 7: Movement Capacity

## 100. Exercise

Estimate transfer time from:

``` text
data volume
safe network throughput
```

Then add operational buffer.

------------------------------------------------------------------------

# Part 99 --- Lab 8: Failure-Domain Audit

## 101. Exercise

Map primaries/replicas to zones.

Identify any unsafe co-location.

------------------------------------------------------------------------

# Part 100 --- Lab 9: Node Maintenance

## 102. Exercise

In approved nonproduction, execute supported node maintenance procedure.

Measure:

``` text
movement/failover
P99
errors
recovery time
```

------------------------------------------------------------------------

# Part 101 --- Lab 10: Node Failure

## 103. Exercise

In a disposable environment, simulate supported node failure.

Observe:

``` text
replica promotion/recovery
placement
client impact
```

------------------------------------------------------------------------

# Part 102 --- Failure Scenario 1: Hot Shard

## 104. Test

Concentrate traffic on one shard.

Determine whether root cause is:

``` text
key distribution
command mix
placement
```

------------------------------------------------------------------------

# Part 103 --- Failure Scenario 2: Node Near Memory Capacity

## 105. Test/Tabletop

Attempt planned movement only after proving destination headroom.

Validate preflight blocks unsafe move.

------------------------------------------------------------------------

# Part 104 --- Failure Scenario 3: Network Saturation

## 106. Test

In isolated lab, constrain movement network headroom.

Observe:

``` text
movement slowdown
P99 impact
```

------------------------------------------------------------------------

# Part 105 --- Failure Scenario 4: Destination CPU Saturation

## 107. Test

Create bounded destination workload.

Validate movement stop criteria.

------------------------------------------------------------------------

# Part 106 --- Failure Scenario 5: Failure-Domain Violation

## 108. Tabletop

Model primary/replica placement in same failure domain.

Show why node-count health alone is insufficient.

------------------------------------------------------------------------

# Part 107 --- Failure Scenario 6: Node Failure During Movement

## 109. Test/Tabletop

Determine:

``` text
service state
remaining replicas
capacity
recovery priority
```

------------------------------------------------------------------------

# Part 108 --- Failure Scenario 7: Scale-In Too Early

## 110. Tabletop

Model node removal before movement/recovery is complete.

Validate change procedure prevents it.

------------------------------------------------------------------------

# Part 109 --- Failure Scenario 8: Client Retry Storm

## 111. Test

During approved failover/movement, compare clients with and without
backoff/jitter.

------------------------------------------------------------------------

# Part 110 --- Failure Scenario 9: Movement Stall

## 112. Test/Tabletop

Practice diagnosis using:

``` text
node
network
storage
capacity
replication
```

evidence.

------------------------------------------------------------------------

# Part 111 --- Failure Scenario 10: Post-Movement Skew

## 113. Test

Complete movement, then validate all resource dimensions.

A memory-balanced result may still be CPU/network-unbalanced.

------------------------------------------------------------------------

# Part 112 --- Troubleshooting Matrix

## 114. Common Problems

  Symptom                     Investigate
  --------------------------- ----------------------------------
  one shard CPU high          hot key/tenant/command mix
  one node memory high        placement/database growth
  movement slow               network/CPU/storage/load
  P99 rises during movement   saturation/queueing
  errors during movement      failover/proxy/client reconnect
  new node unused             placement/scheduling/config
  replica placement unsafe    failure-domain constraints
  scale-in blocked            remaining capacity/topology
  movement stalled            node/network/storage/replication
  memory balanced, CPU not    workload skew
  repeated rebalance needed   growth/design/placement policy

------------------------------------------------------------------------

# Part 113 --- Runbook 1: Hot Shard

## 115. Procedure

``` text
1. identify hot shard.
2. identify database.
3. identify hot keys/tenants/commands.
4. compare memory vs CPU/network skew.
5. determine logical vs placement cause.
6. mitigate traffic/data-model issue.
7. rebalance only if placement helps.
8. validate P99 and distribution.
```

------------------------------------------------------------------------

# Part 114 --- Runbook 2: Scale Out

## 116. Procedure

``` text
1. confirm capacity trigger.
2. add supported node capacity.
3. validate node/version/network/storage.
4. capture baseline.
5. initiate supported placement/movement.
6. monitor stop conditions.
7. validate topology/failure domains.
8. update capacity model.
```

------------------------------------------------------------------------

# Part 115 --- Runbook 3: Scale In

## 117. Procedure

``` text
1. calculate remaining capacity.
2. validate N-1 headroom.
3. validate failure domains.
4. move/recover workloads through supported procedure.
5. confirm node is safe to remove.
6. remove capacity.
7. validate application/topology.
8. update inventory.
```

------------------------------------------------------------------------

# Part 116 --- Runbook 4: Rebalance / Reshard

## 118. Procedure

``` text
1. document objective.
2. capture topology and SLO baseline.
3. validate CPU/memory/network/storage headroom.
4. define stop/rollback conditions.
5. execute supported operation.
6. monitor movement and application.
7. validate data/replication/placement.
8. preserve evidence.
```

------------------------------------------------------------------------

# Part 117 --- Runbook 5: Node Maintenance

## 119. Procedure

``` text
1. confirm cluster healthy.
2. confirm replicas/capacity.
3. ensure no conflicting movement.
4. use supported maintenance procedure.
5. monitor failover/movement.
6. perform maintenance.
7. restore/validate node.
8. validate final topology.
```

------------------------------------------------------------------------

# Part 118 --- Runbook 6: Failed Node Replacement

## 120. Procedure

``` text
1. stabilize database availability.
2. assess replication/capacity.
3. provision compatible replacement.
4. validate network/storage/failure domain.
5. recover/move through supported process.
6. validate replicas and SLO.
7. remove failed capacity when safe.
8. document recovery.
```

------------------------------------------------------------------------

# Part 119 --- Runbook 7: Movement Causing Latency

## 121. Procedure

``` text
1. confirm timing correlation.
2. inspect source/destination CPU.
3. inspect network/storage.
4. inspect P99/errors.
5. compare stop conditions.
6. pause/abort/mitigate only as supported.
7. stabilize application.
8. revise movement plan/capacity.
```

------------------------------------------------------------------------

# Part 120 --- Runbook 8: Placement Audit

## 122. Procedure

``` text
1. inventory nodes/zones.
2. map primary/replica shards.
3. map CPU/memory/network.
4. identify failure-domain violations.
5. identify persistent skew.
6. identify capacity risks.
7. create supported remediation plan.
8. record accepted exceptions.
```

------------------------------------------------------------------------

# Part 121 --- Topology Template

## 123. Record

``` text
Cluster:
Database:
Shard count:
Replication:
Shard:
Role:
Node:
Zone:
Memory:
CPU:
Network:
Status:
```

------------------------------------------------------------------------

# Part 122 --- Movement Plan Template

## 124. Record

``` text
Objective:
Data to move:
Source:
Destination:
Estimated throughput:
Estimated duration:
CPU headroom:
Memory headroom:
Network headroom:
Storage headroom:
Application SLO:
Stop conditions:
Rollback:
Point of no return:
Owner:
```

------------------------------------------------------------------------

# Part 123 --- Placement Audit Template

## 125. Record

``` text
Database:
Primary shard:
Primary node/zone:
Replica shard:
Replica node/zone:
Failure-domain compliant?:
CPU skew:
Memory skew:
Network skew:
Action:
```

------------------------------------------------------------------------

# Part 124 --- Production Acceptance

## 126. Inventory

-   [ ] nodes inventoried;
-   [ ] databases inventoried;
-   [ ] shard topology documented;
-   [ ] primary/replica placement documented;
-   [ ] failure domains documented;
-   [ ] Kubernetes scheduling constraints documented where applicable.

## 127. Capacity

-   [ ] per-node CPU monitored;
-   [ ] per-node memory monitored;
-   [ ] per-shard load monitored where supported;
-   [ ] network monitored;
-   [ ] storage monitored where applicable;
-   [ ] movement headroom defined;
-   [ ] N-1 capacity tested/modelled;
-   [ ] growth forecast maintained.

## 128. Change Safety

-   [ ] scale-out procedure tested;
-   [ ] scale-in procedure tested/tabletopped;
-   [ ] rebalance/reshard procedure documented;
-   [ ] node maintenance tested;
-   [ ] node replacement tested/tabletopped;
-   [ ] stop conditions defined;
-   [ ] rollback/forward-recovery path defined;
-   [ ] application SLO monitored during movement.

## 129. Resilience

-   [ ] primary/replica failure-domain separation validated;
-   [ ] node-failure behavior tested;
-   [ ] client reconnect behavior tested;
-   [ ] post-movement data validation tested;
-   [ ] ten failure scenarios completed;
-   [ ] eight runbooks reviewed;
-   [ ] production acceptance completed.

------------------------------------------------------------------------

# 130. Knowledge Validation

1.  What is the difference between a Redis Enterprise node and shard?
2.  Why should primary and replica placement consider failure domains?
3.  Why does equal shard memory not imply equal workload?
4.  What resource dimensions should placement consider?
5.  What can cause CPU skew?
6.  Why does moving a hot-key shard not eliminate the hot key?
7.  How can hash-tag usage affect distribution?
8.  What baseline should be captured before data movement?
9.  Why should scale-out happen before critical saturation?
10. Why is scale-in higher risk than scale-out?
11. What is the conceptual difference between rebalance and resharding?
12. What resources does data movement consume?
13. Why is theoretical network throughput not a safe transfer rate?
14. Why is application SLO part of a movement plan?
15. What are stop conditions?
16. Why must rollback feasibility be understood before movement?
17. Why should failure-domain placement be revalidated after movement?
18. Why must node maintenance check replica health first?
19. How can Kubernetes storage topology affect maintenance?
20. Why should recovery stabilize before unnecessary optimization?
21. Why can memory-balanced placement still be unhealthy?
22. Why should Redis shard sizing not reuse Elasticsearch shard rules?
23. How does shard data volume affect recovery time?
24. Why should database growth be forecast?
25. How can affinity/taints affect new Redis capacity?
26. Why must actual placement be audited after failures/upgrades?
27. What metrics should be monitored during movement?
28. Why can movement stall?
29. Why should post-movement validation include application
    reads/writes?
30. What must pass before Redis shard-placement operations are
    production-ready?

------------------------------------------------------------------------

# 131. Hands-On Acceptance Checklist

-   [ ] Inventoried cluster nodes.
-   [ ] Inventoried databases.
-   [ ] Mapped shard topology.
-   [ ] Mapped primary/replica placement.
-   [ ] Mapped failure domains.
-   [ ] Built CPU/memory/network heatmap.
-   [ ] Identified a hot-shard pattern.
-   [ ] Distinguished hot key from placement issue.
-   [ ] Reviewed key-distribution/hash-tag design.
-   [ ] Captured pre-change baseline.
-   [ ] Completed scale-out tabletop/lab.
-   [ ] Completed scale-in capacity calculation.
-   [ ] Estimated movement transfer time.
-   [ ] Defined movement stop conditions.
-   [ ] Audited failure-domain separation.
-   [ ] Tested node maintenance in approved nonproduction.
-   [ ] Tested/tabletopped node failure.
-   [ ] Monitored movement resources.
-   [ ] Validated application SLO during movement.
-   [ ] Validated post-movement topology.
-   [ ] Validated post-movement application reads/writes.
-   [ ] Built topology template.
-   [ ] Built movement plan.
-   [ ] Built placement audit.
-   [ ] Completed ten failure scenarios.
-   [ ] Completed eight runbooks.
-   [ ] Completed production acceptance.

------------------------------------------------------------------------

# 132. Cleanup

Remove only disposable Chapter 72 lab data.

For:

``` text
tutorial:chapter72:*
```

use safe:

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

Remove temporary lab load generators and restore any approved temporary
topology/fault-injection configuration.

Confirm:

``` text
cluster healthy
replication healthy
no movement in progress
expected shard placement
expected failure-domain separation
normal CPU/memory/network
normal application P99
no lab keys remain
```

------------------------------------------------------------------------

# 133. Key Takeaways

1.  Redis Enterprise nodes and shards are different operational objects.
2.  Production topology must be understood at node, shard, replica, and
    failure-domain levels.
3.  Balanced memory does not guarantee balanced CPU, network, or
    application latency.
4.  Hot keys and hot tenants are logical workload problems that shard
    movement alone may not solve.
5.  Key-distribution and hash-tag design can materially affect shard
    skew.
6.  Scale-out should occur before the cluster reaches critical
    saturation.
7.  Scale-in requires proving remaining capacity and resilience.
8.  Rebalancing and resharding can consume significant CPU, network,
    memory, and storage resources.
9.  Data-movement duration must be estimated using safe effective
    throughput, not theoretical maximum bandwidth.
10. Movement requires operational headroom above normal application
    demand.
11. Stop conditions and application SLOs must be defined before change
    begins.
12. Some movement stages may not support simple rollback; forward
    recovery may be required.
13. Primary/replica failure-domain separation must be validated after
    every topology change.
14. Node maintenance and replacement require capacity and replication
    preflight.
15. Kubernetes scheduling, PDBs, storage topology, affinity, taints,
    requests, and limits can constrain Redis movement.
16. Recovery should stabilize before unnecessary optimization.
17. Redis shard sizing must follow Redis Enterprise workload/recovery
    characteristics rather than unrelated datastore rules.
18. Larger shard data volumes can increase movement and recovery time.
19. Placement drift should be audited after failures, maintenance,
    scaling, and upgrades.
20. Movement observability must include source/destination resources and
    application SLOs.
21. A stalled movement requires evidence from node, network, storage,
    capacity, and replication layers.
22. Post-movement validation must include application behavior, not only
    cluster status.
23. Major resharding should avoid unrelated simultaneous changes where
    possible.
24. Automation needs health gates, stop conditions, and validation---not
    just an API call.
25. Production readiness requires topology inventory, multidimensional
    capacity, failure-domain validation, safe movement procedures,
    tested failure behavior, and practiced runbooks.

------------------------------------------------------------------------

# 134. References

Validate node-management, shard-management, rebalance, resharding,
database scaling, placement, maintenance, and recovery procedures
against the exact deployed Redis Enterprise version and current official
Redis documentation.

Recommended documentation areas:

-   Redis Enterprise cluster architecture
-   Redis Enterprise database architecture
-   Redis Enterprise shards and proxies
-   Redis Enterprise high availability
-   Redis Enterprise database scaling
-   Redis Enterprise node management
-   Redis Enterprise maintenance
-   Redis Enterprise REST API / CLI
-   Redis Enterprise observability
-   Redis Enterprise Kubernetes Operator
-   Kubernetes PodDisruptionBudget
-   Kubernetes node drain
-   Kubernetes affinity/anti-affinity
-   Kubernetes topology spread constraints
-   Kubernetes taints/tolerations
-   CSI/storage topology
-   organizational change-management and capacity standards

------------------------------------------------------------------------

# Next Chapter

**Chapter 73 --- Redis Enterprise Cost Optimization & FinOps
Engineering**

Chapter 73 will connect technical architecture to cost: memory
efficiency, node/database right-sizing, replication cost, shard
overhead, network and cross-zone/region transfer, persistence and backup
storage, Kubernetes/cloud infrastructure, Auto Tiering/Flex economics,
idle capacity vs resilience headroom, environment scheduling, cost
attribution/showback, unit economics, cost anomaly detection,
optimization guardrails, FinOps runbooks, and production acceptance.
