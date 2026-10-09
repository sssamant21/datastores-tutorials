# Chapter 37 --- Redis Enterprise Active-Active, Geo-Distribution & Multi-Region Engineering

**Status:** Canonical\
**Track:** Redis Enterprise / Redis Software Production Engineering\
**Part:** Part 4 --- Persistence, Availability & Data Protection\
**Level:** Advanced → Production Multi-Region Redis Engineering\
**Audience:** SREs, DBREs, Platform Engineers, Redis Administrators,
Application Architects, Developers\
**Lab type:** Active-Active topology discovery, local-region writes,
CRDT behavior, geo-replication, conflict testing, network-partition
simulation, region-loss testing, region rejoin, application routing,
latency/capacity measurement, observability, troubleshooting, runbooks,
and production acceptance

------------------------------------------------------------------------

# 1. Objective

Chapter 35 covered local replication and high availability.

Chapter 36 covered backup, restore, and disaster recovery.

This chapter covers a different architecture:

``` text
multiple active Redis Enterprise regions
```

A simplified design is:

``` text
              Region A
         +----------------+
App A -->| Active-Active  |
         | Redis database |
         +-------+--------+
                 |
          geo replication
                 |
         +-------+--------+
App B -->| Active-Active  |
         | Redis database |
         +----------------+
              Region B
```

Both regions can accept supported writes locally.

Redis Enterprise Active-Active uses conflict-free replicated data type
(CRDT) technology and product-specific geo-distributed database behavior
to reconcile concurrent updates.

This is not equivalent to simply placing two independent Redis databases
behind global DNS.

By the end, you should be able to:

-   Explain Active-Active architecture.
-   Explain why CRDT semantics are required.
-   Understand local-region writes.
-   Understand inter-region convergence.
-   Understand network-latency effects.
-   Understand partition behavior.
-   Test concurrent updates.
-   Understand data-type-specific conflict behavior.
-   Design application routing.
-   Plan regional capacity.
-   Handle region loss and rejoin.
-   Monitor geo-replication health.
-   Test multi-region failure scenarios.
-   Troubleshoot divergence/convergence issues.
-   Build production runbooks.
-   Define production acceptance criteria.

------------------------------------------------------------------------

# 2. Core Production Principle

Multi-region writable Redis changes the consistency model.

Do not assume:

``` text
write in Region A
immediately visible in Region B
```

The more accurate model is:

``` text
local write
    |
    v
local Redis result
    |
    v
geo replication
    |
    v
remote region
    |
    v
eventual convergence according to supported CRDT semantics
```

Applications must be designed for this model.

------------------------------------------------------------------------

# Part 1 --- Why Multi-Region?

## 3. Goals

Common goals include:

``` text
low-latency local access
regional availability
regional write capability
reduced dependence on one region
global application architecture
```

------------------------------------------------------------------------

# Part 2 --- Single-Region HA vs. Active-Active

## 4. Single-Region HA

Typical local HA:

``` text
primary
+
replica
+
failover
```

One node/shard is authoritative for writes at a time.

## 5. Active-Active

Active-Active permits supported writes in multiple participating regions
and reconciles state through geo-distributed semantics.

These are different architectures.

------------------------------------------------------------------------

# Part 3 --- Why Simple Dual-Primary Is Unsafe

## 6. Concurrent Writes

Suppose two independent Redis databases both accept:

``` text
Region A: SET user:1 tier gold
Region B: SET user:1 tier platinum
```

Without defined conflict semantics:

``` text
Which value wins?
How are changes merged?
What happens after reconnection?
```

A global writable architecture needs deterministic convergence rules.

------------------------------------------------------------------------

# Part 4 --- CRDT Concept

## 7. Conflict-Free Replicated Data Types

CRDTs are data structures designed so replicas can process updates
independently and later converge according to defined rules.

Conceptually:

``` text
Region A updates state
Region B updates state
        |
        v
updates exchanged
        |
        v
deterministic merge
        |
        v
converged state
```

Exact Redis Enterprise Active-Active behavior depends on supported
commands, data types, and product version.

------------------------------------------------------------------------

# Part 5 --- Convergence

## 8. Meaning

Convergence means participating regions eventually reach compatible
final state after all relevant updates are exchanged.

It does not mean every region sees every write immediately.

------------------------------------------------------------------------

# Part 6 --- Local Write Latency

## 9. Benefit

An application can often write to its local Active-Active region without
waiting for a full cross-region round trip.

This can improve application latency.

------------------------------------------------------------------------

# Part 7 --- Remote Visibility

## 10. Replication Delay

A write accepted in Region A needs time to reach Region B.

Delay depends on:

``` text
network RTT
network congestion
replication backlog
write volume
region health
product processing
```

------------------------------------------------------------------------

# Part 8 --- Application Consistency

## 11. Read-After-Write

If an application writes in Region A and immediately reads in Region B,
the new state may not yet be visible.

Applications must define whether this is acceptable.

------------------------------------------------------------------------

# Part 9 --- Session Affinity

## 12. Routing Strategy

Where appropriate, keeping a user's immediate read/write path in one
region can reduce cross-region visibility surprises.

Do not treat affinity as a substitute for correct distributed semantics.

------------------------------------------------------------------------

# Part 10 --- Global Routing

## 13. Possible Inputs

Routing may consider:

``` text
user geography
region health
latency
capacity
compliance
maintenance
```

Routing logic must understand Redis regional availability.

------------------------------------------------------------------------

# Part 11 --- Region-Local Dependency

## 14. Preferred Path

A common architecture is:

``` text
regional application
    |
    v
regional Redis endpoint
```

rather than forcing every operation across regions.

------------------------------------------------------------------------

# Part 12 --- Network RTT

## 15. Geo Distance

Inter-region latency can be tens or hundreds of milliseconds depending
on geography and network.

Measure real RTT.

Do not use same-AZ latency assumptions for geo replication.

------------------------------------------------------------------------

# Part 13 --- Replication Bandwidth

## 16. Capacity

Geo replication consumes network bandwidth.

Capacity planning must include:

``` text
write rate
value size
metadata/replication overhead
number of participating regions
recovery/catch-up traffic
```

------------------------------------------------------------------------

# Part 14 --- Write Amplification

## 17. Multiple Regions

A write may need to propagate to multiple remote regions.

Increasing region count can increase replication traffic and operational
complexity.

------------------------------------------------------------------------

# Part 15 --- Data-Type Semantics

## 18. Critical Requirement

Conflict behavior can differ by Redis data type and operation.

Do not generalize:

``` text
"CRDT automatically merges everything exactly how the business wants."
```

Validate each application's commands and data types against official
Redis Enterprise Active-Active support and semantics.

------------------------------------------------------------------------

# Part 16 --- String-Like State

## 19. Concurrent Assignment

For concurrent assignments, the platform applies defined
conflict-resolution semantics.

The application must not assume a custom business rule such as:

``` text
largest value wins
most expensive tier wins
Region A always wins
```

unless explicitly implemented and supported.

------------------------------------------------------------------------

# Part 17 --- Counters

## 20. Concurrent Increments

Counters are a classic CRDT use case because independent increments can
be reconciled according to counter semantics.

Test the exact commands used by the application.

------------------------------------------------------------------------

# Part 18 --- Sets

## 21. Concurrent Membership

Concurrent add/remove operations have defined Active-Active semantics.

Applications must validate whether those semantics match business
expectations.

------------------------------------------------------------------------

# Part 19 --- Hashes

## 22. Field-Level Behavior

Concurrent operations on hash fields can differ from replacing an entire
application object stored as one serialized string.

Data modeling therefore affects conflict granularity.

------------------------------------------------------------------------

# Part 20 --- Lists / Ordered Data

## 23. Ordering Complexity

Globally concurrent ordered updates are inherently more complex than a
simple local list.

Validate supported Active-Active command behavior and ordering
expectations.

------------------------------------------------------------------------

# Part 21 --- Streams

## 24. Event Semantics

If using Streams in a geo-distributed design, validate supported
Active-Active behavior, IDs, consumer processing, ordering expectations,
and duplicate/idempotency handling for the exact product version.

Do not assume a globally strict total order across independent regional
producers.

------------------------------------------------------------------------

# Part 22 --- Modules

## 25. Compatibility

Redis modules/features may have specific Active-Active support
constraints.

Validate:

``` text
module
version
data type
command
conflict behavior
```

before production use.

------------------------------------------------------------------------

# Part 23 --- Unsupported Commands

## 26. Design Review

Some commands or patterns may not be supported or may have special
semantics in Active-Active databases.

Create an application command inventory and validate it against current
Redis Enterprise documentation.

------------------------------------------------------------------------

# Part 24 --- Command Inventory

## 27. Template

``` text
Application:
Key pattern:
Redis type:
Commands:
Write region:
Read region:
Concurrent writers:
Conflict expectation:
Active-Active support validated:
```

------------------------------------------------------------------------

# Part 25 --- Network Partition

## 28. Scenario

Suppose:

``` text
Region A <X> Region B
```

but both regional Redis deployments remain available locally.

Each region may continue processing supported local operations according
to Active-Active behavior.

When connectivity returns, updates must converge.

------------------------------------------------------------------------

# Part 26 --- Partition Tradeoff

## 29. Availability vs. Immediate Consistency

Multi-region writable systems intentionally make tradeoffs.

Applications must tolerate temporary regional differences if they want
continued regional writes during network separation.

------------------------------------------------------------------------

# Part 27 --- Partition Duration

## 30. Backlog

Longer partitions create more replication catch-up work.

Monitor:

``` text
pending replication
network throughput
catch-up duration
regional resource pressure
```

------------------------------------------------------------------------

# Part 28 --- Region Loss

## 31. Scenario

``` text
Region A unavailable
Region B healthy
```

Applications should be able to route appropriately according to the
global architecture.

Redis availability alone is not enough; application and network routing
must also work.

------------------------------------------------------------------------

# Part 29 --- Regional Application Failover

## 32. Dependencies

Failing application traffic to another region may require:

``` text
DNS/global load balancing
application capacity
Redis endpoint configuration
secrets
TLS
downstream services
```

------------------------------------------------------------------------

# Part 30 --- Rejoining a Region

## 33. Recovery

When a failed region returns:

``` text
do not immediately assume it is current
```

Allow supported synchronization/convergence to complete and validate
health before routing normal traffic.

------------------------------------------------------------------------

# Part 31 --- Rejoin Capacity

## 34. Catch-Up Load

A returning region may need to process substantial accumulated changes.

Plan:

``` text
network headroom
CPU
memory
replication capacity
application routing
```

------------------------------------------------------------------------

# Part 32 --- Regional Maintenance

## 35. Controlled Drain

Before maintenance:

``` text
confirm other regions healthy
confirm application routing
confirm capacity
reduce/drain traffic if required
perform maintenance
verify convergence
restore traffic
```

------------------------------------------------------------------------

# Part 33 --- Region Count

## 36. Complexity

More regions can improve locality/resilience but increase:

``` text
network traffic
failure combinations
routing complexity
operational testing
cost
```

Use only the regions required by business objectives.

------------------------------------------------------------------------

# Part 34 --- Placement

## 37. Failure Independence

Participating regions should represent meaningful independent failure
domains.

Do not call two zones in one region "multi-region."

------------------------------------------------------------------------

# Part 35 --- Capacity Planning

## 38. Each Region

A region may need enough capacity for:

``` text
normal local traffic
failover traffic from another region
replication catch-up
maintenance
```

------------------------------------------------------------------------

# Part 36 --- N-1 Capacity

## 39. Region Failure

If one region fails, remaining regions may receive more application
traffic.

Capacity-test the intended failover distribution.

------------------------------------------------------------------------

# Part 37 --- Catch-Up Plus Failover

## 40. Combined Pressure

When a region returns, remaining regions may still be carrying failover
traffic while geo replication catches up.

Test combined conditions.

------------------------------------------------------------------------

# Part 38 --- Memory Capacity

## 41. Data Footprint

Plan for:

``` text
dataset
CRDT/product metadata
replication buffers
client buffers
persistence
operational headroom
```

Measure actual deployment behavior.

------------------------------------------------------------------------

# Part 39 --- Network Capacity Model

## 42. Inputs

Record:

``` text
peak writes/sec
average write bytes
peak write bytes
regions
geo replication throughput
RTT
catch-up throughput
```

------------------------------------------------------------------------

# Part 40 --- Latency Model

## 43. Separate Paths

Measure:

``` text
application -> local Redis
region A -> region B network
write -> remote visibility
partition recovery -> convergence
```

These are different latency metrics.

------------------------------------------------------------------------

# Part 41 --- Conflict Rate

## 44. Application Metric

Track how often the same logical entities are concurrently updated in
different regions.

High conflict frequency can indicate that the data model or routing
strategy needs redesign.

------------------------------------------------------------------------

# Part 42 --- Ownership Strategy

## 45. Reduce Conflicts

Some applications reduce conflict frequency by assigning a logical "home
region" for particular entities while retaining Active-Active
resilience.

This is an application architecture choice, not a Redis requirement.

------------------------------------------------------------------------

# Part 43 --- Hot Global Keys

## 46. Risk

A globally hot key can create:

``` text
local CPU pressure
replication traffic
conflict frequency
cross-region churn
```

Avoid unnecessary global coordination through one key.

------------------------------------------------------------------------

# Part 44 --- Rate Limiting

## 47. Global Limits

A strict globally synchronized rate limit is difficult to implement with
low latency across independently writable regions.

Decide whether the requirement is:

``` text
per-region approximate
per-tenant regional
globally strict
```

The architecture may differ.

------------------------------------------------------------------------

# Part 45 --- Distributed Locks

## 48. Caution

Do not assume a Redis lock pattern designed for one primary behaves as a
globally strict cross-region coordination mechanism in Active-Active.

Use an architecture appropriate to the required consistency guarantee.

------------------------------------------------------------------------

# Part 46 --- Uniqueness

## 49. Global Uniqueness

Requirements such as:

``` text
username must be globally unique
order number allocated exactly once
inventory must never oversell
```

may require stronger coordination or an authoritative system designed
for those invariants.

Do not rely on eventual convergence alone for strict global invariants.

------------------------------------------------------------------------

# Part 47 --- Source of Truth

## 50. Define

For every Active-Active use case document:

``` text
Is Redis authoritative?
Is Redis derived?
Can data be rebuilt?
What consistency is required?
```

------------------------------------------------------------------------

# Part 48 --- Backup

## 51. Still Required Where Applicable

Active-Active protects regional availability.

It does not replace historical backup.

A logical mistake can propagate across regions.

------------------------------------------------------------------------

# Part 49 --- Security

## 52. Regional Controls

Validate in every region:

``` text
TLS
authentication
authorization
network policy
secrets
audit controls
backup access
```

------------------------------------------------------------------------

# Part 50 --- Compliance

## 53. Data Residency

Multi-region replication may copy data across geographic or regulatory
boundaries.

Confirm data residency and compliance requirements before enabling geo
distribution.

------------------------------------------------------------------------

# Part 51 --- Observability

## 54. Regional Dashboard

For every region track:

``` text
availability
CPU
memory
latency
connections
ops/sec
network
database health
```

------------------------------------------------------------------------

## 55. Geo Dashboard

Track:

``` text
region connectivity
replication health
replication delay
pending/catch-up state
network RTT
network throughput
convergence health
```

Use Redis Enterprise-supported metrics for the deployed version.

------------------------------------------------------------------------

## 56. Application Dashboard

Track:

``` text
request region
Redis region
local latency
remote visibility delay
conflict-related business errors
failover routing
```

------------------------------------------------------------------------

# Part 52 --- Alerting

## 57. Examples

Alert on:

``` text
region disconnected
geo replication unhealthy
replication delay above SLO
catch-up not progressing
regional database unhealthy
network RTT abnormal
regional capacity exhausted
```

------------------------------------------------------------------------

# Part 53 --- SLOs

## 58. Define Separately

Possible SLOs:

``` text
local Redis availability
local operation latency
geo replication delay
regional failover time
regional convergence time
```

Do not collapse them into one metric.

------------------------------------------------------------------------

# Part 54 --- Hands-On Lab

## 59. Safety

Use a disposable Redis Enterprise Active-Active lab.

Do not simulate regional partitions against production.

Exact creation/configuration commands depend on Redis Enterprise
deployment and version; use the supported product workflow.

------------------------------------------------------------------------

# Part 55 --- Lab Topology

## 60. Two Regions

Prepare:

``` text
Region A
Region B
```

with one Active-Active database participating in both regions.

Record:

``` text
database name
regional endpoints
product version
participating regions
supported data types
```

------------------------------------------------------------------------

# Part 56 --- Baseline

## 61. Region A

Write:

``` redis
SET tutorial:chapter37:region-a "hello-from-a"
INCR tutorial:chapter37:counter
```

Verify local result.

Then verify remote visibility from Region B and measure delay.

------------------------------------------------------------------------

# Part 57 --- Region B

## 62. Local Write

From Region B:

``` redis
SET tutorial:chapter37:region-b "hello-from-b"
INCR tutorial:chapter37:counter
```

Verify convergence from both regions.

------------------------------------------------------------------------

# Part 58 --- Visibility Timer

## 63. Python Concept

Run a writer in one region and a reader in the other.

``` python
import os
import time
import uuid
import redis

r = redis.Redis(
    host=os.environ["REDIS_HOST"],
    port=int(os.getenv("REDIS_PORT", "6379")),
    password=os.getenv("REDIS_PASSWORD") or None,
    decode_responses=True,
)

key = "tutorial:chapter37:visibility"
value = str(uuid.uuid4())

started = time.time()
r.set(key, value)

print(
    "written",
    value,
    "at",
    started,
)
```

The remote-region reader should record when the exact value becomes
visible.

Do not interpret one sample as the SLO; run repeated measurements.

------------------------------------------------------------------------

# Part 59 --- Concurrent Counter Lab

## 64. Procedure

From both regions, increment the same lab counter concurrently.

Validate the final converged result according to supported Active-Active
semantics.

------------------------------------------------------------------------

# Part 60 --- Concurrent Assignment Lab

## 65. Procedure

On a disposable key, perform concurrent assignments from both regions.

Record:

``` text
Region A operation
Region B operation
timestamps
local immediate results
eventual state
```

Compare the observed behavior with official product semantics.

------------------------------------------------------------------------

# Part 61 --- Hash Conflict Lab

## 66. Separate Fields

Where supported, update different hash fields from different regions.

Then test concurrent updates to the same field.

Document the difference.

------------------------------------------------------------------------

# Part 62 --- Set Conflict Lab

## 67. Membership

Where supported, perform concurrent add/remove operations on the same
member.

Observe and document the supported conflict semantics.

------------------------------------------------------------------------

# Part 63 --- Network Partition Lab

## 68. Disposable Environment

Using supported network-lab controls:

1.  verify both regions healthy;
2.  interrupt geo connectivity;
3.  keep regional applications connected locally;
4.  perform supported writes in both regions;
5.  record local availability;
6.  restore connectivity;
7.  measure catch-up/convergence;
8.  validate final state.

------------------------------------------------------------------------

# Part 64 --- Partition Duration Test

## 69. Compare

Test:

``` text
short partition
longer partition
```

Measure:

``` text
pending changes
catch-up time
network throughput
CPU
application latency
```

------------------------------------------------------------------------

# Part 65 --- Region Loss Lab

## 70. Simulate

Make Region A unavailable in the disposable environment.

Verify:

``` text
Region B Redis remains available
application routing changes correctly
Region B has required capacity
business smoke tests pass
```

------------------------------------------------------------------------

# Part 66 --- Region Rejoin Lab

## 71. Restore

Bring Region A back.

Before returning application traffic:

``` text
verify Redis health
verify geo replication
wait for required convergence
verify application connectivity
```

------------------------------------------------------------------------

# Part 67 --- Failover Capacity Lab

## 72. N-1 Load

Route representative Region A workload to Region B in the lab.

Measure:

``` text
CPU
memory
network
connections
latency
geo replication
```

------------------------------------------------------------------------

# Part 68 --- Hot-Key Lab

## 73. Global Hot Key

Generate writes to one shared lab key from both regions.

Observe:

``` text
local latency
replication traffic
conflict behavior
resource pressure
```

Compare with region-owned/sharded keys.

------------------------------------------------------------------------

# Part 69 --- Application Routing Lab

## 74. Test

Validate:

``` text
normal regional routing
Region A unavailable
Region B unavailable
region restored
```

Measure client recovery and endpoint behavior.

------------------------------------------------------------------------

# Part 70 --- Failure Injection

## 75. Failure 1 --- Geo Link Loss

Disconnect Region A from Region B while preserving local service.

Validate local availability and eventual convergence.

## 76. Failure 2 --- Region A Loss

Verify Region B application and Redis capacity.

## 77. Failure 3 --- Region B Loss

Verify Region A application and Redis capacity.

## 78. Failure 4 --- Long Partition

Create larger catch-up work and measure convergence time.

## 79. Failure 5 --- Concurrent Same-Key Writes

Write conflicting values from both regions and validate documented
semantics.

## 80. Failure 6 --- Hot Global Key

Generate high cross-region churn and observe impact.

## 81. Failure 7 --- Application Misrouting

Send Region A application traffic to remote Redis unnecessarily and
measure latency impact.

## 82. Failure 8 --- Region Rejoin Under Load

Restore a region while failover traffic remains high.

Measure combined catch-up and application pressure.

## 83. Failure 9 --- Insufficient N-1 Capacity

Constrain surviving-region capacity in the lab and demonstrate why
failover sizing matters.

## 84. Failure 10 --- Logical Corruption

Write a bad logical value and demonstrate that geo replication can
propagate it.

Confirm why Active-Active does not replace backup.

------------------------------------------------------------------------

# Part 71 --- Troubleshooting

## 85. Geo Replication Delay Increasing

Check:

``` text
inter-region RTT
packet loss
network throughput
write rate
value size
regional CPU
regional memory
catch-up state
```

------------------------------------------------------------------------

## 86. Regions Not Converging

Check:

``` text
regional database health
geo connectivity
supported command/data type
replication state
product logs
version compatibility
```

Escalate according to Redis Enterprise support guidance if product-level
convergence is unhealthy.

------------------------------------------------------------------------

## 87. Remote Reads Are Stale

Determine:

``` text
which region accepted the write
which region served the read
geo replication delay
application routing
required consistency
```

This may be expected architecture behavior rather than a Redis fault.

------------------------------------------------------------------------

## 88. Region Rejoin Slow

Check:

``` text
partition duration
change volume
network bandwidth
CPU
memory
catch-up backlog
current application load
```

------------------------------------------------------------------------

## 89. Surviving Region Overloaded

Check:

``` text
N-1 capacity
global routing
connections
read/write traffic
hot keys
catch-up work
```

------------------------------------------------------------------------

## 90. Unexpected Final Value

Check:

``` text
all regional writes
timestamps
Redis type
commands used
official Active-Active conflict semantics
application assumptions
```

Do not label convergence behavior as data corruption until semantics are
verified.

------------------------------------------------------------------------

## 91. High Cross-Region Traffic

Check:

``` text
write volume
value sizes
hot keys
region count
unnecessary global writes
application data model
```

------------------------------------------------------------------------

## 92. Application Latency High in One Region

Check whether the application is using a remote Redis endpoint instead
of its intended local endpoint.

------------------------------------------------------------------------

# Part 72 --- Production Runbooks

## 93. Runbook --- Geo Replication Degraded

``` text
1. Confirm affected regions.
2. Confirm local Redis availability.
3. Measure replication delay.
4. Check inter-region network.
5. Check regional capacity.
6. Reduce avoidable pressure.
7. Protect local application service.
8. Monitor catch-up.
9. Verify convergence.
10. Record duration and RPO/consistency impact.
```

------------------------------------------------------------------------

## 94. Runbook --- Region Failure

``` text
1. Confirm regional failure.
2. Confirm surviving region health.
3. Activate approved global routing.
4. Monitor application errors.
5. Monitor surviving Redis capacity.
6. Validate critical reads/writes.
7. Confirm backup/DR posture.
8. Prepare region recovery.
9. Maintain incident communication.
10. Record application-visible RTO.
```

------------------------------------------------------------------------

## 95. Runbook --- Region Rejoin

``` text
1. Restore regional infrastructure.
2. Confirm Redis Enterprise health.
3. Confirm geo connectivity.
4. Monitor catch-up/convergence.
5. Keep traffic controlled during recovery.
6. Validate regional data/application.
7. Confirm capacity.
8. Gradually restore routing.
9. Monitor errors/latency.
10. Close only after steady state.
```

------------------------------------------------------------------------

## 96. Runbook --- Unexpected Conflict Result

``` text
1. Identify key/data type.
2. Capture operations from all regions.
3. Capture timestamps and commands.
4. Confirm product version.
5. Check documented Active-Active semantics.
6. Determine whether application assumption was invalid.
7. Correct business state if required.
8. Redesign data model/routing if needed.
9. Add regression test.
10. Update command inventory.
```

------------------------------------------------------------------------

## 97. Runbook --- Surviving Region Capacity Pressure

``` text
1. Confirm failed/degraded region.
2. Measure redirected traffic.
3. Check Redis CPU/memory/network.
4. Check application connections.
5. Reduce noncritical workload if approved.
6. Scale supported infrastructure if possible.
7. Protect critical traffic.
8. Restore failed region.
9. Rebalance traffic gradually.
10. Update N-1 capacity plan.
```

------------------------------------------------------------------------

# Part 73 --- Active-Active Design Template

## 98. Fields

``` text
Database:
Owner:
Business use case:
Authoritative/derived:
Regions:
Regional endpoints:
Application regions:
Normal routing:
Failover routing:
Redis data types:
Redis commands:
Concurrent writers:
Conflict semantics validated:
Read-after-write requirement:
Remote visibility SLO:
Geo replication SLO:
Peak writes/sec:
Average value size:
Peak replication throughput:
N-1 capacity:
Backup policy:
Data residency:
Security controls:
Last partition test:
Last region-loss test:
Last rejoin test:
Runbook:
```

------------------------------------------------------------------------

# Part 74 --- Command Compatibility Review

## 99. Table

  --------------------------------------------------------------------------------------
  Key Pattern   Type                 Commands    Multi-Region   Conflict     Validated
                                                 Writers        Expected     
  ------------- -------------------- ----------- -------------- ------------ -----------
  `profile:*`   Hash                 HSET/HGET   Yes            Field        
                                                                conflicts    
                                                                possible     

  `counter:*`   Counter-compatible   INCR        Yes            Concurrent   
                                                                increments   

  `cache:*`     String               SET/GET     Yes            Concurrent   
                                                                assignment   

  `events:*`    Stream               XADD/...    Yes            Validate     
                                                                exact        
                                                                semantics    
  --------------------------------------------------------------------------------------

Complete this with actual application commands.

------------------------------------------------------------------------

# Part 75 --- Capacity Worksheet

## 100. Per Region

Record:

``` text
normal local requests/sec
normal CPU
normal memory
normal network
failover requests/sec
failover CPU
failover memory
geo replication throughput
catch-up throughput
safe maximum
```

------------------------------------------------------------------------

# Part 76 --- Regional Failure Test Record

## 101. Evidence

``` text
test date
regions
dataset size
normal traffic
failed region
routing change time
surviving region peak CPU
surviving region peak memory
application errors
application RTO
region restore time
convergence time
issues
remediation owner
```

------------------------------------------------------------------------

# Part 77 --- Partition Test Record

## 102. Evidence

``` text
partition start
partition end
writes in Region A
writes in Region B
local availability
replication backlog
reconnect time
convergence time
final validation
conflict observations
```

------------------------------------------------------------------------

# Part 78 --- Production Acceptance Checklist

## 103. Active-Active Engineering

-   [ ] Business reason for Active-Active documented.
-   [ ] Participating regions documented.
-   [ ] Regional endpoints documented.
-   [ ] Application routing documented.
-   [ ] Failover routing tested.
-   [ ] Data residency reviewed.
-   [ ] Redis data types inventoried.
-   [ ] Redis commands inventoried.
-   [ ] Active-Active command support validated.
-   [ ] Conflict semantics validated.
-   [ ] Concurrent-write tests completed.
-   [ ] Read-after-write requirements documented.
-   [ ] Remote visibility behavior measured.
-   [ ] Geo replication delay monitored.
-   [ ] Inter-region RTT monitored.
-   [ ] Regional capacity monitored.
-   [ ] N-1 capacity tested.
-   [ ] Hot global keys reviewed.
-   [ ] Strict global invariants reviewed.
-   [ ] Global lock assumptions reviewed.
-   [ ] Backup retained independently.
-   [ ] Network partition tested.
-   [ ] Region A failure tested.
-   [ ] Region B failure tested.
-   [ ] Region rejoin tested.
-   [ ] Catch-up under load tested.
-   [ ] Application routing recovery tested.
-   [ ] Regional RTO measured.
-   [ ] Convergence time measured.
-   [ ] Five production runbooks validated.
-   [ ] Active-Active design template completed.

------------------------------------------------------------------------

# Knowledge Validation

## 104. Questions

1.  What problem does Active-Active Redis solve?
2.  How is Active-Active different from local HA?
3.  Why is simple dual-primary Redis unsafe?
4.  What is a CRDT?
5.  What does convergence mean?
6.  Why can local writes be low latency?
7.  Why may remote reads be stale?
8.  What determines remote visibility delay?
9.  Why must conflict semantics be reviewed per data type?
10. Why does data modeling affect conflict granularity?
11. Why should application commands be inventoried?
12. What happens conceptually during a network partition?
13. Why can local service remain available during geo-link failure?
14. What happens when connectivity returns?
15. Why does partition duration affect catch-up?
16. What is N-1 regional capacity?
17. Why can region rejoin create heavy load?
18. Why are hot global keys risky?
19. Why are strict global rate limits difficult?
20. Why should single-primary lock assumptions not be blindly reused?
21. Why can global uniqueness require stronger coordination?
22. Why does Active-Active not replace backup?
23. Why is data residency important?
24. Which geo metrics should be monitored?
25. Why should local latency and geo replication delay be separate SLOs?
26. How do you test conflict behavior?
27. How do you test regional loss?
28. Why should routing be tested independently from Redis?
29. What must happen before returning traffic to a recovered region?
30. What must pass before Active-Active is production-ready?

------------------------------------------------------------------------

# Hands-On Acceptance Checklist

## 105. Lab Completion

-   [ ] Created disposable two-region Active-Active topology.
-   [ ] Recorded regional endpoints.
-   [ ] Performed local Region A writes.
-   [ ] Measured visibility in Region B.
-   [ ] Performed local Region B writes.
-   [ ] Measured visibility in Region A.
-   [ ] Tested concurrent counter updates.
-   [ ] Tested concurrent assignment.
-   [ ] Tested hash conflict behavior where supported.
-   [ ] Tested set conflict behavior where supported.
-   [ ] Simulated network partition.
-   [ ] Verified local regional availability.
-   [ ] Restored geo connectivity.
-   [ ] Measured convergence.
-   [ ] Tested longer partition.
-   [ ] Simulated Region A loss.
-   [ ] Simulated Region B loss.
-   [ ] Tested region rejoin.
-   [ ] Tested N-1 capacity.
-   [ ] Tested hot global key.
-   [ ] Tested application routing.
-   [ ] Completed ten failure scenarios.
-   [ ] Completed troubleshooting.
-   [ ] Reviewed five production runbooks.
-   [ ] Completed command compatibility review.
-   [ ] Completed capacity worksheet.
-   [ ] Completed production acceptance checklist.

------------------------------------------------------------------------

# 106. Lab Cleanup

Discover Chapter 37 lab keys only:

``` bash
redis-cli --scan --pattern 'tutorial:chapter37:*'
```

Review all matches.

Delete confirmed lab keys in bounded batches:

``` redis
UNLINK <confirmed-key>
```

Perform cleanup through the supported Active-Active topology so deletion
behavior is handled consistently across participating regions.

Do not use:

``` redis
KEYS tutorial:chapter37:*
FLUSHDB
FLUSHALL
```

against a shared or production database.

Remove disposable regional infrastructure only according to the lab
procedure.

------------------------------------------------------------------------

# 107. Key Takeaways

1.  Redis Enterprise Active-Active is a multi-region writable
    architecture, not simple dual-primary Redis.
2.  CRDT technology provides deterministic convergence semantics for
    supported distributed operations.
3.  Local-region writes can reduce application latency.
4.  Remote regions may not observe a local write immediately.
5.  Applications must explicitly define read-after-write and consistency
    requirements.
6.  Conflict semantics must be validated for every Redis type and
    command pattern used.
7.  Data modeling affects the granularity and meaning of concurrent
    updates.
8.  Network partitions can leave regions temporarily different while
    local service continues.
9.  Reconnection requires catch-up and convergence.
10. Longer partitions create more catch-up work.
11. Region failure requires application routing and surviving-region
    capacity, not only Redis availability.
12. N-1 regional capacity should be tested.
13. Region rejoin can create significant replication pressure.
14. Hot global keys increase replication and conflict pressure.
15. Strict global invariants may require stronger coordination than
    eventual convergence.
16. Single-primary distributed-lock assumptions should not be blindly
    applied to Active-Active.
17. Active-Active does not replace historical backup.
18. Multi-region replication can have data-residency implications.
19. Monitor local availability and geo replication separately.
20. Monitor inter-region RTT, replication delay, catch-up, and
    convergence.
21. Application telemetry should record which region served each
    operation.
22. Network-partition testing is essential.
23. Region-loss testing is essential.
24. A recovered region should not receive full traffic until health and
    convergence are validated.
25. Production readiness requires validated semantics, N-1 capacity,
    routing, partitions, region loss, rejoin, observability, and
    runbooks.

------------------------------------------------------------------------

# 108. References

Validate all Active-Active behavior against the exact Redis Enterprise
version and deployment model in use.

Recommended official Redis documentation areas:

-   Redis Enterprise Active-Active databases
-   Redis Enterprise CRDTs
-   Active-Active supported commands and data types
-   Active-Active conflict resolution
-   Active-Active database creation and administration
-   Active-Active monitoring
-   Redis Enterprise cluster architecture
-   Redis Enterprise networking
-   Redis Enterprise security
-   Redis Enterprise backup and restore
-   Redis Enterprise geo-distributed deployment guidance

------------------------------------------------------------------------

# Next Chapter

**Chapter 38 --- Redis Enterprise Security, Authentication,
Authorization & TLS Engineering**

Chapter 38 will cover:

-   authentication
-   ACL/RBAC concepts
-   users and roles
-   least privilege
-   database access
-   TLS
-   certificates
-   certificate rotation
-   secret management
-   network controls
-   administrative access
-   audit considerations
-   credential rotation
-   application identity
-   failure injection
-   observability
-   troubleshooting
-   security runbooks
-   production acceptance validation
