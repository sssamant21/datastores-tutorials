# Chapter 65 --- Redis Enterprise Active-Active CRDT Semantics & Conflict Engineering

**Status:** Canonical\
**Track:** Redis Enterprise / Redis Software Production Engineering\
**Part:** Part 11 --- Advanced Kubernetes, Active-Active & Platform
Engineering\
**Level:** Advanced → Multi-Region Data Semantics & Conflict
Engineering\
**Audience:** SREs, DBREs, Platform Engineers, Redis Administrators,
Application Architects, Developers, Cloud Engineers\
**Lab type:** Active-Active architecture, CRDT semantics, concurrent
writes, convergence, partitions, application invariants, conflict
testing, observability, troubleshooting, runbooks, and production
acceptance

------------------------------------------------------------------------

# 1. Objective

Traditional replication often assumes a primary write location.

Active-Active changes the model:

``` text
Region A ----\
              \
               Active-Active database
              /
Region B ----/
```

Applications can write in multiple participating regions.

This improves regional availability and locality, but it introduces a
critical question:

``` text
What happens when two regions update related data at the same time?
```

Redis Enterprise Active-Active uses conflict-free replicated data type
concepts and product-defined semantics so participating replicas can
converge after concurrent operations and network disruption.

The application must still understand those semantics.

By the end of this chapter, you should be able to:

-   explain Active-Active architecture;
-   explain CRDT concepts;
-   distinguish replication lag from semantic conflict;
-   understand concurrent writes;
-   reason about convergence;
-   understand network-partition behavior;
-   identify application invariants that CRDT convergence does not
    automatically protect;
-   classify safe and unsafe workload patterns;
-   test conflicting operations;
-   define regional traffic behavior;
-   monitor convergence and replication health;
-   troubleshoot multi-region anomalies;
-   execute production runbooks and acceptance gates.

------------------------------------------------------------------------

# 2. Core Production Principle

Active-Active does not mean:

``` text
all regions see every write instantly
```

and it does not mean:

``` text
all application business rules are automatically preserved
```

The correct mental model is:

``` text
local availability
+
multi-region replication
+
defined conflict semantics
+
eventual convergence
```

Applications must be designed for those semantics.

------------------------------------------------------------------------

# Part 1 --- Why Active-Active

## 3. Regional Availability

Active-Active can help applications continue serving writes when one
participating region is unavailable, subject to the deployed
architecture and supported failure mode.

## 4. Locality

Clients can often use a geographically closer database endpoint,
reducing wide-area request latency.

## 5. Multi-Region Writes

Multiple sites can accept writes.

That is the capability that creates both value and semantic complexity.

------------------------------------------------------------------------

# Part 2 --- Traditional Primary/Replica Model

## 6. Simplified

``` text
Region A
  |
primary
  |
replication
  v
Region B replica
```

Writes are normally directed to one authority.

Conflict handling is simpler because concurrent independent writers are
limited.

------------------------------------------------------------------------

# Part 3 --- Active-Active Model

## 7. Simplified

``` text
        write
Client A ---> Region A
                |
                | replication
                |
Client B ---> Region B
        write
```

Both regions can accept operations.

------------------------------------------------------------------------

# Part 4 --- The Distributed Systems Problem

## 8. Concurrent Operations

Imagine:

``` text
Region A writes X
Region B writes Y
```

before either region receives the other's operation.

The system must reconcile those operations.

------------------------------------------------------------------------

# Part 5 --- CRDT

## 9. Definition

CRDT stands for:

``` text
Conflict-Free Replicated Data Type
```

CRDT designs allow distributed replicas to process updates and converge
according to deterministic semantics without requiring every write to
synchronously coordinate with every region.

------------------------------------------------------------------------

# Part 6 --- Convergence

## 10. Desired Property

After communication is restored and all relevant operations propagate:

``` text
Region A state == Region B state
```

according to the data type's defined semantics.

------------------------------------------------------------------------

# Part 7 --- Eventual Convergence

## 11. Time Window

During propagation:

``` text
Region A may temporarily observe state A
Region B may temporarily observe state B
```

After synchronization:

``` text
both converge
```

Applications must tolerate the expected convergence window.

------------------------------------------------------------------------

# Part 8 --- Strong Consistency vs Active-Active

## 12. Different Goal

A globally synchronous strongly consistent write path may require
cross-region coordination before acknowledging a write.

Active-Active prioritizes local operation and availability with defined
convergence semantics.

Do not describe it as global synchronous consistency unless the exact
product capability guarantees that for the operation in question.

------------------------------------------------------------------------

# Part 9 --- Replication Delay

## 13. Not Automatically Conflict

If Region A writes a key and Region B has not received it yet:

``` text
temporary difference
```

may simply be replication delay.

A conflict involves concurrent or competing operations whose combination
must follow defined semantics.

------------------------------------------------------------------------

# Part 10 --- Causality

## 14. Concept

If operation B is based on seeing operation A:

``` text
A -> B
```

they have a causal relationship.

If two operations occur independently without seeing one another, they
may be concurrent.

------------------------------------------------------------------------

# Part 11 --- Concurrent Writes

## 15. Example

Starting state:

``` text
status = pending
```

During partition:

``` text
Region A -> status = approved
Region B -> status = rejected
```

The eventual result depends on the exact data type and conflict
semantics.

Do not invent business meaning from the final technical value.

------------------------------------------------------------------------

# Part 12 --- Business Conflict

## 16. Important

Even if the database converges deterministically:

``` text
technical conflict resolved
```

does not necessarily mean:

``` text
business conflict resolved correctly
```

The application must decide whether concurrent `approved` and `rejected`
updates are allowed.

------------------------------------------------------------------------

# Part 13 --- Application Invariant

## 17. Definition

An invariant is a business rule that must remain true.

Examples:

``` text
inventory cannot be negative
one seat cannot be sold twice
a workflow cannot be both approved and rejected
balance must obey accounting rules
```

CRDT convergence does not automatically preserve arbitrary application
invariants.

------------------------------------------------------------------------

# Part 14 --- Workload Classification

## 18. Before Active-Active

Classify each key/data model:

``` text
cache
session
counter
set membership
profile/document
workflow state
lock/coordination
financial state
inventory
queue/event stream
```

Then validate semantics.

------------------------------------------------------------------------

# Part 15 --- Cache Workloads

## 19. Often Easier

Derived/rebuildable cache data may tolerate temporary regional
differences better than authoritative transactional state.

Still validate:

``` text
TTL
invalidation
staleness
source load
```

------------------------------------------------------------------------

# Part 16 --- Session Workloads

## 20. Questions

Ask:

``` text
Can user traffic move regions?
Can concurrent session updates occur?
What happens to logout/revocation?
What is acceptable staleness?
```

------------------------------------------------------------------------

# Part 17 --- Counters

## 21. Semantics Matter

Distributed increments can be a natural CRDT use case, but exact
command/data-type support and semantics must be verified for the
deployed Redis Enterprise version.

Do not assume every numeric read-modify-write pattern behaves like a
CRDT counter.

------------------------------------------------------------------------

# Part 18 --- Sets

## 22. Add/Remove Concurrency

Concurrent:

``` text
add member
remove member
```

requires defined semantics.

Verify the exact supported behavior for the data type and commands.

------------------------------------------------------------------------

# Part 19 --- Registers / Scalar Values

## 23. Concurrent Assignment

Two regions assigning different values to the same logical field is a
classic conflict case.

Do not rely on intuitive "last write wins" assumptions without checking
product semantics.

------------------------------------------------------------------------

# Part 20 --- Hashes / Documents

## 24. Field-Level Design

A document containing independent fields can have different concurrency
characteristics than replacing an entire serialized object.

Prefer data modeling that minimizes unnecessary conflict domains where
supported.

------------------------------------------------------------------------

# Part 21 --- Whole-Object Rewrite

## 25. Risk

Application pattern:

``` text
GET entire object
modify one field locally
SET entire object
```

can overwrite unrelated concurrent changes.

This is risky even outside Active-Active and deserves extra scrutiny in
multi-region designs.

------------------------------------------------------------------------

# Part 22 --- Partial Updates

## 26. Better Conflict Isolation

Where data type semantics support it, updating only the intended field
can reduce accidental conflict surface.

------------------------------------------------------------------------

# Part 23 --- Read-Modify-Write

## 27. Race

Pattern:

``` text
read X
calculate new X
write X
```

may be unsafe under concurrent regional writers.

Prefer atomic operations whose Active-Active semantics are explicitly
supported.

------------------------------------------------------------------------

# Part 24 --- Distributed Locks

## 28. Caution

A lock that assumes one globally serialized Redis authority can behave
differently in a multi-region partitioned environment.

Do not use Active-Active as a distributed-lock solution without
validating the exact safety model.

------------------------------------------------------------------------

# Part 25 --- Leader Election

## 29. Caution

Leader election requires stronger coordination properties than ordinary
convergent data.

Use an appropriate coordination system/design when uniqueness is
required.

------------------------------------------------------------------------

# Part 26 --- Inventory

## 30. Example Invariant

``` text
stock >= 0
```

Two regions independently selling the last item can violate the business
invariant even if Redis later converges.

Use application architecture designed for scarce-resource coordination.

------------------------------------------------------------------------

# Part 27 --- Financial Balance

## 31. High Risk

A balance often requires:

``` text
ordering
auditability
atomic business transactions
invariant protection
```

Do not treat a generic Active-Active key as a replacement for a ledger
design.

------------------------------------------------------------------------

# Part 28 --- Idempotency

## 32. Essential

Cross-region retries can duplicate application operations unless
requests have idempotency semantics.

Example:

``` text
operation_id = globally unique request identifier
```

Track business operations, not only network attempts.

------------------------------------------------------------------------

# Part 29 --- Retry Behavior

## 33. Ambiguous Outcome

If a client times out after sending a write:

``` text
write may have succeeded
```

A blind retry can duplicate non-idempotent business behavior.

Chapter 53 retry engineering applies.

------------------------------------------------------------------------

# Part 30 --- Regional Affinity

## 34. Useful Pattern

Where practical:

``` text
Region A users -> Region A endpoint
Region B users -> Region B endpoint
```

reduces cross-region client latency.

Replication still distributes updates.

------------------------------------------------------------------------

# Part 31 --- Traffic Failover

## 35. Separate Layer

Active-Active database availability does not automatically redirect
applications.

Traffic systems may include:

``` text
DNS
GSLB
service mesh
load balancer
application routing
```

------------------------------------------------------------------------

# Part 32 --- Failover vs Active-Active

## 36. Terminology

In Active-Active:

``` text
database may already be writable in surviving region
```

Application traffic still needs to move there.

This differs from promoting a passive database replica.

------------------------------------------------------------------------

# Part 33 --- Network Partition

## 37. Scenario

``` text
Region A  X  Region B
```

Both regions may continue local operations according to the supported
Active-Active design.

Updates accumulate until connectivity returns.

------------------------------------------------------------------------

# Part 34 --- Partition Duration

## 38. Operational Risk

Longer partition can mean:

``` text
more divergent operations
larger synchronization work
greater business-semantic exposure
```

Monitor partition duration.

------------------------------------------------------------------------

# Part 35 --- Partition Healing

## 39. Convergence

When connectivity returns:

``` text
replication resumes
operations propagate
CRDT semantics merge state
replicas converge
```

Do not immediately declare recovery complete.

------------------------------------------------------------------------

# Part 36 --- Post-Partition Validation

## 40. Check

``` text
replication healthy
regions converged
application invariants validated
backlog cleared
latency normal
traffic routing normal
```

------------------------------------------------------------------------

# Part 37 --- Conflict Domain

## 41. Design

The more unrelated business state packed into one conflict unit, the
larger the risk of concurrent updates interfering.

Use key/data modeling deliberately.

------------------------------------------------------------------------

# Part 38 --- Key Ownership

## 42. Optional Strategy

Some applications reduce conflict by assigning natural ownership:

``` text
tenant home region
user home region
entity home region
```

while retaining Active-Active availability for failure.

------------------------------------------------------------------------

# Part 39 --- Home-Region Pattern

## 43. Normal Operation

``` text
entity A writes primarily in Region A
entity B writes primarily in Region B
```

During disaster, ownership can move through an explicit procedure.

This reduces routine concurrent conflicts.

------------------------------------------------------------------------

# Part 40 --- Global Writers

## 44. Higher Complexity

If every entity is actively written from every region, conflict testing
must be much more comprehensive.

------------------------------------------------------------------------

# Part 41 --- Timestamps

## 45. Dangerous Assumption

Do not use application wall-clock timestamps as a universal
conflict-resolution mechanism.

Clocks can differ, and product CRDT semantics may not use application
timestamps the way you expect.

------------------------------------------------------------------------

# Part 42 --- Clock Skew

## 46. Operational

Maintain accurate time synchronization for:

``` text
logs
incident correlation
certificates
application behavior
```

But do not assume clock synchronization turns distributed operations
into globally ordered transactions.

------------------------------------------------------------------------

# Part 43 --- TTL

## 47. Expiration

Expiration is state.

Concurrent updates and expiration can interact.

Validate TTL behavior for Active-Active data using the exact
product/version semantics.

------------------------------------------------------------------------

# Part 44 --- Delete vs Update

## 48. Critical Conflict

Scenario:

``` text
Region A deletes key
Region B updates key
```

during a partition.

Test the exact data type and command behavior.

Do not guess whether delete or update "wins."

------------------------------------------------------------------------

# Part 45 --- Recreate After Delete

## 49. Scenario

``` text
delete
then recreate
```

can be semantically different from:

``` text
update existing
```

Test lifecycle workflows.

------------------------------------------------------------------------

# Part 46 --- Schema Version

## 50. Multi-Region Deployment

If application versions differ temporarily across regions:

``` text
Region A writes schema v2
Region B still expects v1
```

Active-Active can expose compatibility problems quickly.

Use backward-compatible deployment patterns.

------------------------------------------------------------------------

# Part 47 --- Rolling Application Deployments

## 51. Contract

During rolling/multi-region deployment:

``` text
old reader must tolerate new data
new reader must tolerate old data
```

until all regions are upgraded.

------------------------------------------------------------------------

# Part 48 --- JSON / Search / Vector

## 52. Capability Semantics

Advanced capabilities can have additional Active-Active support
constraints and semantics.

Validate exact support for:

``` text
JSON
Search
vector
other modules/capabilities
```

against current product documentation.

------------------------------------------------------------------------

# Part 49 --- Streams / Messaging

## 53. Semantics

Event ordering and consumer behavior across regions require careful
design.

Do not assume global total ordering merely because data is
Active-Active.

------------------------------------------------------------------------

# Part 50 --- Pub/Sub

## 54. Ephemeral Messaging

Pub/Sub delivery semantics differ from durable replicated state.

Do not use Active-Active database assumptions to infer cross-region
Pub/Sub guarantees.

------------------------------------------------------------------------

# Part 51 --- Consistency Requirement Matrix

## 55. Template

  -----------------------------------------------------------------------------------
  Data           Multi-region   Staleness      Invariant          Active-Active fit
                 write?         tolerated?                        
  -------------- -------------- -------------- ------------------ -------------------
  cache          yes            yes            low                evaluate

  session        maybe          limited        logout/security    evaluate

  counter        yes            maybe          command-specific   validate

  inventory      risky          low            nonnegative        redesign/validate

  ledger         risky          very low       accounting         specialized design
  -----------------------------------------------------------------------------------

------------------------------------------------------------------------

# Part 52 --- Conflict Matrix

## 56. Test Every Important Pair

Examples:

``` text
set vs set
set vs delete
increment vs increment
add vs remove
field update vs field update
TTL vs update
delete vs recreate
```

Record actual observed/supported semantics.

------------------------------------------------------------------------

# Part 53 --- Lab Environment

## 57. Requirements

Use isolated participating regions/clusters.

Never create intentional network partitions in production merely to
learn semantics.

------------------------------------------------------------------------

# Part 54 --- Lab Namespace

## 58. Isolate

Use keys such as:

``` text
tutorial:chapter65:*
```

and dedicated disposable databases where possible.

------------------------------------------------------------------------

# Part 55 --- Baseline Replication Test

## 59. Test

1.  Write key in Region A.
2.  Read locally.
3.  Wait for supported propagation.
4.  Read in Region B.
5.  Record convergence time.

Repeat B -\> A.

------------------------------------------------------------------------

# Part 56 --- Concurrent Set Test

## 60. Test

Start with:

``` text
tutorial:chapter65:status = pending
```

Apply conflicting values in each region as close together as the lab can
reasonably produce.

Record:

``` text
local immediate reads
eventual values
convergence time
```

Interpret only using official semantics.

------------------------------------------------------------------------

# Part 57 --- Increment Test

## 61. Test

Where the command/data type is supported for Active-Active:

``` text
Region A increments
Region B increments
```

Verify eventual value against documented semantics.

------------------------------------------------------------------------

# Part 58 --- Add/Remove Test

## 62. Test

Use a supported collection type.

Perform concurrent:

``` text
Region A add member
Region B remove member
```

Record eventual state.

------------------------------------------------------------------------

# Part 59 --- Delete/Update Test

## 63. Test

In an isolated key:

``` text
Region A delete
Region B update
```

Observe final supported behavior.

------------------------------------------------------------------------

# Part 60 --- TTL Test

## 64. Test

Apply:

``` text
write/update
expiration
cross-region read
```

under controlled timing.

Record expiration behavior and convergence.

------------------------------------------------------------------------

# Part 61 --- Partition Lab

## 65. High Risk

Only use an approved nonproduction fault-injection mechanism.

During partition:

``` text
write A in Region A
write B in Region B
```

Then restore connectivity.

Measure:

``` text
local availability
replication recovery
convergence time
final state
```

------------------------------------------------------------------------

# Part 62 --- Partition Stop Conditions

## 66. Define

Stop the lab if:

``` text
unexpected database degradation
resource saturation
uncontrolled replication backlog
unrelated workload affected
recovery exceeds approved limit
```

------------------------------------------------------------------------

# Part 63 --- Conflict Logging

## 67. Application Evidence

Log business operation IDs and region identity.

Example fields:

``` text
operation_id
entity_id
region
application_version
operation_type
timestamp
result
```

Do not log sensitive values unnecessarily.

------------------------------------------------------------------------

# Part 64 --- Region Tagging

## 68. Observability

Include region in:

``` text
metrics
logs
traces
alerts
```

Without region labels, multi-region incidents are difficult to
reconstruct.

------------------------------------------------------------------------

# Part 65 --- Replication Monitoring

## 69. Monitor

Use supported Redis Enterprise metrics/status for:

``` text
Active-Active connectivity
replication health
sync state
lag/backlog where exposed
database state
```

Exact metrics depend on version.

------------------------------------------------------------------------

# Part 66 --- Application Monitoring

## 70. Per Region

Track:

``` text
request rate
P50/P95/P99
errors
Redis timeouts
retry rate
fallback
```

by region.

------------------------------------------------------------------------

# Part 67 --- Convergence SLO

## 71. Define

If the business depends on cross-region visibility, define an acceptable
convergence expectation.

Do not promise a number without measuring the deployed architecture.

------------------------------------------------------------------------

# Part 68 --- WAN Monitoring

## 72. Track

``` text
latency
packet loss
jitter
availability
bandwidth
```

between participating regions.

------------------------------------------------------------------------

# Part 69 --- Replication Bandwidth

## 73. Capacity

Replication traffic depends on workload.

Estimate:

``` text
write rate
average replicated operation/data size
number of participating sites
recovery/backlog traffic
```

Benchmark rather than relying only on estimates.

------------------------------------------------------------------------

# Part 70 --- Partition Backlog

## 74. Recovery Capacity

After a partition, synchronization can create additional:

``` text
network
CPU
storage
```

load.

Reserve headroom.

------------------------------------------------------------------------

# Part 71 --- Hot Keys

## 75. Multi-Region

A hot key written concurrently from several regions can create:

``` text
high replication traffic
contention at application semantic level
large conflict surface
```

Review Chapter 18 hot-key principles.

------------------------------------------------------------------------

# Part 72 --- Large Values

## 76. WAN Cost

Large replicated values increase:

``` text
bandwidth
convergence time
recovery traffic
```

Use bounded values and partial updates where appropriate.

------------------------------------------------------------------------

# Part 73 --- Region Count

## 77. Complexity

More participating regions can increase:

``` text
network paths
failure combinations
operational complexity
conflict opportunities
```

Do not add regions without a business requirement.

------------------------------------------------------------------------

# Part 74 --- Two-Region Caveat

## 78. Availability Architecture

Two regions may satisfy some business designs, but resilience decisions
must account for the exact Active-Active product architecture and
external dependencies.

Do not reduce distributed-system design to "two is always enough."

------------------------------------------------------------------------

# Part 75 --- Three-Region Considerations

## 79. Tradeoff

Additional region can improve some resilience options but increases:

``` text
cost
network
testing
traffic routing
operational complexity
```

Evaluate deliberately.

------------------------------------------------------------------------

# Part 76 --- Security

## 80. Cross-Region Trust

Protect:

``` text
remote cluster credentials
TLS
certificates
network paths
RBAC
secret rotation
```

Active-Active expands the trust boundary.

------------------------------------------------------------------------

# Part 77 --- Certificate Expiry

## 81. Failure Mode

A certificate problem can break cross-region communication even when
local Redis remains healthy.

Monitor expiration and test rotation.

------------------------------------------------------------------------

# Part 78 --- Credential Rotation

## 82. Multi-Site

Coordinate rotation so participating regions do not lose
trust/connectivity.

Use supported procedures.

------------------------------------------------------------------------

# Part 79 --- Application Failover Test

## 83. Beyond Database

Test:

``` text
client traffic moves to surviving region
endpoint resolves
credentials work
capacity sufficient
business operations succeed
```

------------------------------------------------------------------------

# Part 80 --- Region Return

## 84. Rejoin

When a failed region returns:

``` text
do not immediately send full traffic
```

First validate:

``` text
Redis health
Active-Active sync
capacity
application version
network
```

------------------------------------------------------------------------

# Part 81 --- Traffic Ramp

## 85. Controlled

A useful pattern:

``` text
0% -> small canary -> partial -> full
```

while monitoring:

``` text
errors
P99
replication
business correctness
```

------------------------------------------------------------------------

# Part 82 --- Failure Scenario 1: Concurrent Scalar Writes

## 86. Test

Write conflicting scalar values from two regions.

Record documented final semantics and convergence.

------------------------------------------------------------------------

# Part 83 --- Failure Scenario 2: Concurrent Increments

## 87. Test

Perform increments from both regions using a supported operation.

Validate final result.

------------------------------------------------------------------------

# Part 84 --- Failure Scenario 3: Add vs Remove

## 88. Test

Perform concurrent membership add/remove.

Validate documented result.

------------------------------------------------------------------------

# Part 85 --- Failure Scenario 4: Delete vs Update

## 89. Test

Delete in one region and update in another.

Validate final state and application expectation.

------------------------------------------------------------------------

# Part 86 --- Failure Scenario 5: TTL vs Update

## 90. Test

Exercise expiration and update concurrency.

Validate whether application freshness assumptions remain safe.

------------------------------------------------------------------------

# Part 87 --- Failure Scenario 6: Network Partition

## 91. Test

Partition only the approved lab.

Continue local writes, restore connectivity, measure convergence.

------------------------------------------------------------------------

# Part 88 --- Failure Scenario 7: Replication Backlog

## 92. Test

Generate bounded writes during a short approved partition.

Measure recovery load and time.

------------------------------------------------------------------------

# Part 89 --- Failure Scenario 8: Application Retry

## 93. Test

Force an ambiguous client timeout in a lab.

Verify idempotency prevents duplicate business effect.

------------------------------------------------------------------------

# Part 90 --- Failure Scenario 9: Region Traffic Shift

## 94. Test

Move test traffic from one region to another.

Validate endpoint, capacity, credentials, latency, and correctness.

------------------------------------------------------------------------

# Part 91 --- Failure Scenario 10: Region Rejoin

## 95. Test

Restore a previously isolated lab region.

Validate synchronization before traffic ramp.

------------------------------------------------------------------------

# Part 92 --- Troubleshooting Matrix

## 96. Common Problems

  -----------------------------------------------------------------------
  Symptom                             Investigate
  ----------------------------------- -----------------------------------
  value differs between regions       propagation/convergence
  briefly                             

  value differs for long period       replication/network/Active-Active
                                      health

  unexpected final value              data-type conflict semantics

  duplicate business action           retry/idempotency

  invariant violated                  application concurrency design

  region writes succeed but remote    WAN/replication
  stale                               

  local latency good, remote          WAN/backlog
  visibility slow                     

  rejoin causes load spike            backlog recovery/capacity

  one region cannot join              RERC/TLS/network/version

  app fails after traffic shift       DNS/LB/client/capacity/security
  -----------------------------------------------------------------------

------------------------------------------------------------------------

# Part 93 --- Runbook 1: Cross-Region Divergence

## 97. Procedure

``` text
1. identify key/data type.
2. identify operation history/regions.
3. inspect Active-Active health.
4. inspect WAN.
5. determine replication delay vs conflict.
6. consult documented data-type semantics.
7. validate eventual convergence.
8. assess business correctness.
```

------------------------------------------------------------------------

# Part 94 --- Runbook 2: Network Partition

## 98. Procedure

``` text
1. identify affected regional path.
2. confirm local database health.
3. protect application traffic.
4. monitor replication state/backlog.
5. control write/retry amplification if needed.
6. restore network.
7. monitor convergence.
8. validate business invariants.
```

------------------------------------------------------------------------

# Part 95 --- Runbook 3: Unexpected Conflict Result

## 99. Procedure

``` text
1. capture operation sequence.
2. identify data type/commands.
3. identify concurrent regions.
4. verify product semantics.
5. reproduce in isolated lab.
6. determine application-design mismatch.
7. redesign conflict domain/operation.
8. add regression test.
```

------------------------------------------------------------------------

# Part 96 --- Runbook 4: Duplicate Operation

## 100. Procedure

``` text
1. identify operation ID.
2. inspect client timeout/retry.
3. inspect both regional logs.
4. determine whether write succeeded before retry.
5. apply idempotency control.
6. correct duplicate business state if required.
7. update client retry policy.
8. add failure test.
```

------------------------------------------------------------------------

# Part 97 --- Runbook 5: Region Traffic Shift

## 101. Procedure

``` text
1. validate target-region Redis health.
2. validate Active-Active sync.
3. validate capacity.
4. validate DNS/LB/security.
5. shift canary traffic.
6. monitor P99/errors/business operations.
7. ramp gradually.
8. record steady state.
```

------------------------------------------------------------------------

# Part 98 --- Runbook 6: Region Rejoin

## 102. Procedure

``` text
1. restore regional infrastructure.
2. validate Redis/Operator health.
3. validate remote-cluster connectivity.
4. monitor synchronization.
5. wait for supported healthy/converged state.
6. validate application version/security.
7. ramp traffic gradually.
8. confirm global steady state.
```

------------------------------------------------------------------------

# Part 99 --- Runbook 7: Replication Recovery Load

## 103. Procedure

``` text
1. confirm partition healed.
2. monitor WAN throughput.
3. monitor Redis CPU/memory.
4. monitor application P99.
5. identify backlog/recovery pressure.
6. reduce nonessential load if required.
7. wait for healthy convergence.
8. validate headroom and update capacity model.
```

------------------------------------------------------------------------

# Part 100 --- Runbook 8: Business Invariant Violation

## 104. Procedure

``` text
1. stop/limit affected workflow if required.
2. preserve operation history.
3. identify concurrent regional writes.
4. separate CRDT correctness from business correctness.
5. repair business state using approved process.
6. redesign invariant protection.
7. add multi-region concurrency tests.
8. document corrective action.
```

------------------------------------------------------------------------

# Part 101 --- Data Semantics Template

## 105. Record

``` text
Key/data model:
Business owner:
Data type:
Commands:
Regions writing:
Staleness allowed:
Concurrent writes expected:
Conflict pairs:
Documented CRDT behavior:
Business invariant:
Idempotency:
TTL:
Delete semantics:
Test evidence:
```

------------------------------------------------------------------------

# Part 102 --- Regional Architecture Template

## 106. Record

``` text
Region A:
Region B:
Additional regions:
Redis versions:
Operator versions:
RERC resources:
REAADB:
WAN:
Expected latency:
Traffic routing:
Home-region strategy:
Failover strategy:
Rejoin strategy:
Capacity/site:
Security:
```

------------------------------------------------------------------------

# Part 103 --- Conflict Test Template

## 107. Record

``` text
Test:
Initial state:
Region A operation:
Region B operation:
Partition?:
Immediate A result:
Immediate B result:
Final A result:
Final B result:
Convergence time:
Expected semantics:
Business expectation:
Pass/fail:
```

------------------------------------------------------------------------

# Part 104 --- Production Acceptance

## 108. Architecture

-   [ ] participating regions documented;
-   [ ] Active-Active resources documented;
-   [ ] joint version compatibility verified;
-   [ ] WAN path documented;
-   [ ] traffic routing documented;
-   [ ] per-region capacity validated;
-   [ ] security/trust documented.

## 109. Data Semantics

-   [ ] every critical data model classified;
-   [ ] commands inventoried;
-   [ ] concurrent-write patterns documented;
-   [ ] conflict semantics verified;
-   [ ] TTL semantics tested;
-   [ ] delete/update semantics tested;
-   [ ] application invariants documented;
-   [ ] unsafe coordination workloads identified;
-   [ ] idempotency implemented where required.

## 110. Failure / Recovery

-   [ ] network partition tested/tabletopped;
-   [ ] backlog recovery measured;
-   [ ] region traffic shift tested;
-   [ ] region rejoin tested;
-   [ ] convergence validated;
-   [ ] business correctness validated;
-   [ ] WAN monitoring configured;
-   [ ] Active-Active monitoring configured.

## 111. Operational Acceptance

-   [ ] conflict regression suite exists;
-   [ ] region labels present in observability;
-   [ ] stop conditions documented;
-   [ ] ten failure scenarios completed;
-   [ ] eight runbooks reviewed;
-   [ ] production acceptance completed.

------------------------------------------------------------------------

# 112. Knowledge Validation

1.  Why does Active-Active create semantic complexity?
2.  What is a CRDT?
3.  What does convergence mean?
4.  Why can regions temporarily show different values?
5.  What is the difference between replication delay and conflict?
6.  What is causality?
7.  What is a concurrent operation?
8.  Why can technical convergence still produce a business problem?
9.  What is an application invariant?
10. Why should workloads be classified before Active-Active adoption?
11. Why are cache workloads often easier than scarce inventory?
12. Why must counter operations use documented semantics?
13. Why are add/remove conflicts important?
14. Why are whole-object rewrites risky?
15. Why can read-modify-write be unsafe across regions?
16. Why are distributed locks a special concern?
17. Why can inventory invariants fail under independent regional writes?
18. Why is idempotency important?
19. Why does Active-Active not automatically route application traffic?
20. What happens conceptually during a network partition?
21. Why should recovery include post-partition business validation?
22. What is a conflict domain?
23. How can home-region ownership reduce conflicts?
24. Why should application timestamps not be treated as universal
    conflict resolution?
25. Why must TTL and delete/update concurrency be tested?
26. Why must application versions be backward compatible across regions?
27. Why should WAN and replication be monitored together?
28. Why does partition recovery require resource headroom?
29. Why should a returning region not immediately receive full traffic?
30. What must pass before Active-Active data semantics are
    production-ready?

------------------------------------------------------------------------

# 113. Hands-On Acceptance Checklist

-   [ ] Documented participating regions.
-   [ ] Documented RERC/REAADB resources.
-   [ ] Verified version compatibility.
-   [ ] Classified critical data models.
-   [ ] Inventoried Redis commands.
-   [ ] Documented business invariants.
-   [ ] Documented idempotency requirements.
-   [ ] Established isolated Chapter 65 namespace/database.
-   [ ] Tested A-to-B propagation.
-   [ ] Tested B-to-A propagation.
-   [ ] Measured convergence.
-   [ ] Tested concurrent scalar writes.
-   [ ] Tested concurrent increments where supported.
-   [ ] Tested add/remove where supported.
-   [ ] Tested delete/update.
-   [ ] Tested TTL/update.
-   [ ] Tested approved network partition.
-   [ ] Measured backlog recovery.
-   [ ] Tested ambiguous retry/idempotency.
-   [ ] Tested regional traffic shift.
-   [ ] Tested region rejoin.
-   [ ] Validated application business state.
-   [ ] Added region labels to telemetry.
-   [ ] Reviewed WAN monitoring.
-   [ ] Reviewed Active-Active monitoring.
-   [ ] Completed conflict regression suite.
-   [ ] Completed ten failure scenarios.
-   [ ] Completed eight runbooks.
-   [ ] Completed production acceptance.

------------------------------------------------------------------------

# 114. Cleanup

Remove only disposable Chapter 65 lab keys/resources.

For isolated keys:

``` text
tutorial:chapter65:*
```

use a safe `SCAN` plus `UNLINK` cleanup process appropriate for the lab
database.

Do not use:

``` text
FLUSHDB
FLUSHALL
```

on shared environments.

Restore:

``` text
fault-injection network rules
test traffic routing
test DNS/LB changes
temporary certificates/credentials
temporary lab resources
```

Confirm:

``` text
Active-Active links healthy
regions converged
traffic routing normal
no replication backlog
application SLO normal
business validation passed
```

------------------------------------------------------------------------

# 115. Key Takeaways

1.  Active-Active enables local multi-region writes but changes
    application consistency semantics.
2.  CRDTs provide deterministic distributed convergence for supported
    data types/operations.
3.  Convergence does not mean every region sees every write immediately.
4.  Replication delay and semantic conflict are different problems.
5.  Concurrent writes occur when regions update without observing one
    another's operation.
6.  Technical conflict resolution does not guarantee business
    correctness.
7.  Application invariants must be explicitly identified and protected.
8.  Cache data is often easier to distribute than scarce inventory or
    financial state.
9.  Whole-object read-modify-write patterns can enlarge conflict
    domains.
10. Atomic supported operations are preferable to client-side
    read-modify-write where semantics fit.
11. Distributed locks and leader election require careful coordination
    guarantees.
12. Idempotency protects business operations from ambiguous retries.
13. Active-Active database availability does not automatically perform
    application traffic failover.
14. Network partitions are normal distributed-systems scenarios that
    must be designed and tested.
15. Partition recovery is not complete until regions converge and
    business invariants are validated.
16. Home-region ownership can reduce routine conflict frequency.
17. Application wall-clock timestamps are not a universal distributed
    conflict solution.
18. TTL, delete/update, and recreate behavior must be explicitly tested.
19. Multi-region application versions require backward-compatible data
    contracts.
20. Advanced Redis capabilities require their own Active-Active
    compatibility validation.
21. WAN health is part of database health in Active-Active
    architectures.
22. Backlog recovery needs CPU, network, and operational headroom.
23. More regions increase both resilience options and operational
    complexity.
24. A returning region should synchronize and pass validation before
    receiving full traffic.
25. Production readiness requires proven data semantics, application
    invariants, idempotency, partition behavior, convergence, traffic
    routing, observability, and runbooks together.

------------------------------------------------------------------------

# 116. References

Validate all command-level conflict semantics, supported data types,
CRDT behavior, TTL/delete behavior, advanced capability support,
topology limits, and operational procedures against the exact deployed
Redis Enterprise version and current official Redis documentation.

Recommended documentation areas:

-   Redis Enterprise Active-Active
-   Redis Enterprise Active-Active databases
-   Redis Enterprise CRDTs
-   Redis Enterprise Active-Active conflict resolution
-   Redis Enterprise Active-Active supported commands/data types
-   Redis Enterprise Active-Active Kubernetes
-   RedisEnterpriseRemoteCluster
-   RedisEnterpriseActiveActiveDatabase
-   Redis Enterprise Active-Active networking
-   Redis Enterprise Active-Active monitoring
-   Redis Enterprise Active-Active recovery
-   distributed systems causality and convergence concepts
-   application idempotency and retry design

------------------------------------------------------------------------

# Next Chapter

**Chapter 66 --- Redis Enterprise Active-Active Operations, Monitoring &
Failure Recovery**

Chapter 66 will build on CRDT semantics and focus on operating
Active-Active in production: topology health, RERC/REAADB status,
regional observability, WAN monitoring, replication degradation,
partitions, backlog recovery, regional capacity, certificates and
credentials, maintenance, incident response, failure injection,
troubleshooting, runbooks, and production acceptance.
