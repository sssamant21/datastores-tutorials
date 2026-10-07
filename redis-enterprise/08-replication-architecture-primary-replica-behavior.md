# Chapter 08 --- Replication Architecture & Primary/Replica Behavior

**Status:** Canonical\
**Track:** Redis Enterprise / Redis Software Production Engineering\
**Level:** Foundation → Production High Availability\
**Audience:** Redis Administrators, SREs, DBREs, Platform Engineers,
Developers\
**Lab type:** Replication topology inspection, lag analysis,
failure-domain review, failover tabletop, degraded-HA troubleshooting,
recovery validation, and production acceptance

------------------------------------------------------------------------

# 1. Objective

Replication is one of the foundations of Redis Enterprise high
availability.

A replicated database maintains redundant shard copies so that a failure
of a primary shard, node, or supported failure domain does not
automatically mean loss of database availability.

Conceptually:

``` text
Application
    |
    v
Database Endpoint
    |
    v
Primary Shard
    |
    v
Replica Shard
```

But production replication requires more understanding than:

``` text
replication = enabled
```

An SRE must know:

``` text
where the primary is
where the replica is
whether replication is healthy
whether the copies are in separate failure domains
whether the replica is current enough
what happens during failover
what happens after failover
how redundancy is restored
what data-loss window the architecture permits
```

By the end, you should be able to:

-   Explain primary/replica architecture.
-   Explain asynchronous replication concepts.
-   Explain replication lag.
-   Understand synchronization and resynchronization.
-   Understand failover at an operational level.
-   Explain why availability and durability are different.
-   Explain why replication is not backup.
-   Identify potential acknowledged-write loss scenarios.
-   Understand replica placement requirements.
-   Detect degraded redundancy.
-   Build a replication topology map.
-   Analyze node and shard failure scenarios.
-   Validate HA after recovery.
-   Build replication and failover runbooks.

------------------------------------------------------------------------

# Part 1 --- Why Replication Exists

## 2. Without Replication

A single primary shard:

``` text
Primary Shard
```

has no redundant shard copy.

If that shard becomes unavailable, availability and recovery depend on
the broader database architecture and recovery mechanisms.

For production services requiring high availability, this is usually
insufficient.

------------------------------------------------------------------------

## 3. With Replication

A replicated shard has:

``` text
Primary
   |
   v
Replica
```

For a multi-shard database:

``` text
Database
|
+-- P1 -> R1
+-- P2 -> R2
+-- P3 -> R3
+-- P4 -> R4
```

Each primary partition has a redundant copy.

------------------------------------------------------------------------

# Part 2 --- Primary Behavior

## 4. Primary Shard

The primary is the active shard copy for its portion of the database.

Client operations routed to that partition are handled through the
active database architecture.

Writes change the primary's state and must then be propagated according
to the replication design.

------------------------------------------------------------------------

## 5. Primary Is Not a Permanent Machine Identity

Do not think:

``` text
Node 1 is always primary
```

Think:

``` text
a shard currently has an active primary copy on Node 1
```

During failover or maintenance, roles and placement can change.

Runbooks should reference:

``` text
database
shard
role
node
```

rather than assuming static placement forever.

------------------------------------------------------------------------

# Part 3 --- Replica Behavior

## 6. Replica Shard

A replica maintains a copy of a primary shard's data.

Conceptually:

``` text
Primary changes
      |
      v
Replication stream
      |
      v
Replica applies changes
```

The replica supports high availability.

------------------------------------------------------------------------

## 7. Replica Is Not Backup

Suppose an application executes:

``` redis
DEL customer:1001
```

If the deletion is replicated:

``` text
Primary -> delete
Replica -> delete
```

The replica does not preserve the previous logical value simply because
it is a replica.

Therefore:

``` text
replication != backup
```

Backup and recovery are covered later.

------------------------------------------------------------------------

# Part 4 --- Replication Timing

## 8. Replication Is Not Magic Synchrony

There is always some concept of state propagation between active and
replica copies.

At any instant, operational questions include:

``` text
Has the replica received the latest change?
Has it applied it?
Is replication delayed?
Is the replica reconnecting?
Is a synchronization occurring?
```

------------------------------------------------------------------------

## 9. Replication Lag

Replication lag represents the replica being behind the primary in some
measurable way.

Lag can be considered in terms such as:

``` text
time
bytes
offset/progress
pending work
```

The exact metrics exposed depend on the Redis Enterprise / Redis
Software release and monitoring interface.

------------------------------------------------------------------------

## 10. Why Lag Matters

Suppose:

``` text
Primary accepts write W1
Primary fails
Replica has not yet received/applied W1
```

If failover promotes the replica before W1 exists there, the
acknowledged state can differ from what the application expected.

This is why:

``` text
high availability
```

does not automatically mean:

``` text
zero data loss under every failure
```

------------------------------------------------------------------------

# Part 5 --- Availability vs Durability

## 11. Availability

Availability asks:

> Can the application continue using Redis?

Replication primarily supports this goal.

------------------------------------------------------------------------

## 12. Durability

Durability asks:

> What data survives a failure?

This depends on architecture including:

``` text
replication
persistence
failure timing
backup
application semantics
```

A database can be highly available while still having a non-zero failure
window for the most recent writes.

------------------------------------------------------------------------

# Part 6 --- Acknowledged Writes

## 13. Ambiguous Failure Window

Conceptual timeline:

``` text
T1 client sends write
T2 primary applies write
T3 primary replies to client
T4 replication catches up
```

If failure occurs between relevant propagation events, the resulting
state depends on the replication and failure behavior.

Applications storing critical state must understand the guarantees of
the exact deployed architecture.

------------------------------------------------------------------------

## 14. Do Not Invent Stronger Guarantees

Never tell an application team:

``` text
Redis replication guarantees zero data loss
```

unless the exact product configuration and documented guarantee support
that statement.

Instead document:

``` text
availability requirement
durability requirement
RPO
persistence configuration
backup strategy
failure behavior
```

------------------------------------------------------------------------

# Part 7 --- Replica Placement

## 15. Same-Node Placement Risk

Conceptually unsafe for node-level HA:

``` text
Node 1
|
+-- P1
+-- R1
```

Node 1 failure removes both copies.

------------------------------------------------------------------------

## 16. Separate Nodes

Better:

``` text
Node 1 -> P1
Node 2 -> R1
```

Now a single-node failure does not remove both copies.

------------------------------------------------------------------------

## 17. Separate Failure Domains

For zone-level resilience:

``` text
AZ-A / Node 1 -> P1
AZ-B / Node 3 -> R1
```

is stronger than:

``` text
AZ-A / Node 1 -> P1
AZ-A / Node 2 -> R1
```

if AZ-A is a credible failure domain.

Placement policy must match the failure model.

------------------------------------------------------------------------

# Part 8 --- Replication Topology

## 18. Build the Map

Example:

``` text
P1 Node1 AZ-A ---- R1 Node3 AZ-B
P2 Node2 AZ-A ---- R2 Node4 AZ-B
P3 Node3 AZ-B ---- R3 Node1 AZ-A
P4 Node4 AZ-B ---- R4 Node2 AZ-A
```

This map lets an incident responder answer:

``` text
Which copy is active?
Where is the replica?
What happens if Node 1 fails?
What happens if AZ-A fails?
```

------------------------------------------------------------------------

# Part 9 --- Synchronization

## 19. Initial Synchronization

When a replica is created, it must obtain enough state from its primary
to become a usable redundant copy.

At a high level:

``` text
Replica created
      |
      v
State synchronization
      |
      v
Ongoing replication
```

Synchronization consumes resources.

------------------------------------------------------------------------

## 20. Resynchronization

If replication is interrupted, the replica may need to catch up or
perform a larger synchronization depending on the product state and
failure conditions.

Operational effects can include:

``` text
network usage
CPU
memory
storage/I/O depending on architecture
temporary recovery load
```

Monitor recovery rather than assuming it is free.

------------------------------------------------------------------------

# Part 10 --- Failover

## 21. Failover Concept

When an active primary copy becomes unavailable, HA mechanisms can
transition service to an available replica according to Redis Enterprise
behavior and configuration.

Conceptually:

``` text
Before:

P1 active
 |
 v
R1 replica

Failure:

P1 unavailable

After HA transition:

R1 becomes active role
```

Exact election, detection, timing, and role-transition behavior must be
validated against the deployed product release.

------------------------------------------------------------------------

## 22. Failover Is More Than Promotion

An operational failover includes:

``` text
failure detection
role transition
routing update
client behavior
replication state
redundancy restoration
```

Application availability is only one part.

------------------------------------------------------------------------

# Part 11 --- Client Behavior During Failover

## 23. Clients May Observe Errors

During a failure transition, applications can experience:

``` text
connection reset
timeout
temporary command failure
reconnect
latency spike
```

Client configuration matters:

``` text
connect timeout
socket timeout
connection pool
retry policy
backoff
jitter
idempotency
```

HA architecture must include client behavior.

------------------------------------------------------------------------

## 24. Retry Amplification

Suppose 500 application instances all receive a Redis timeout and
immediately retry at full speed.

The recovering system can receive a retry storm.

Use:

``` text
bounded retries
backoff
jitter
idempotency awareness
```

where appropriate.

------------------------------------------------------------------------

# Part 12 --- After Failover

## 25. Service Restored Does Not Mean HA Restored

After failover:

``` text
Application = healthy
```

but replication may temporarily be:

``` text
Primary only
```

until another replica is established.

This is degraded redundancy.

------------------------------------------------------------------------

## 26. Incident Exit Criteria

Do not close a Redis HA incident only because:

``` text
PING works
```

Validate:

``` text
database available
application healthy
all expected primaries healthy
all expected replicas healthy
replication current
placement safe
capacity healthy
alerts cleared
```

------------------------------------------------------------------------

# Part 13 --- Degraded Redundancy

## 27. What It Means

Expected:

``` text
P1 -> R1
```

Observed:

``` text
P1 -> no healthy replica
```

The database may still serve traffic.

But another failure could have greater impact.

Treat degraded redundancy as an operational risk.

------------------------------------------------------------------------

## 28. Maintenance During Degraded HA

Avoid routine maintenance that removes additional capacity while
redundancy is already degraded unless an approved recovery plan
specifically requires it.

Example:

``` text
Replica missing
+
take another node down
=
increased failure exposure
```

------------------------------------------------------------------------

# Part 14 --- Monitoring Replication

## 29. What to Monitor

Monitor signals for:

``` text
primary health
replica health
replication state
lag/progress
synchronization activity
failover events
role changes
node health
database availability
```

Exact metric names depend on the deployed release and monitoring
integration.

------------------------------------------------------------------------

## 30. Alerting Philosophy

Useful alerts should identify actionable conditions such as:

``` text
replica unhealthy
replication delayed beyond workload baseline
database redundancy degraded
failover occurred
synchronization not completing
node unavailable
```

Avoid alerting only on raw metrics without operational meaning.

------------------------------------------------------------------------

# Part 15 --- Capacity During Replication

## 31. Replicas Consume Resources

Replication increases resource requirements.

A replicated database requires capacity for:

``` text
primary data
replica data
replication traffic
recovery/synchronization
failover headroom
```

Do not size a replicated database as though replicas were free.

------------------------------------------------------------------------

## 32. Failure Capacity

Ask:

``` text
If one node disappears,
can remaining nodes:
- serve workload?
- host/recover replicas?
- absorb replication traffic?
- remain below safe CPU/memory/network limits?
```

This is part of HA capacity planning.

------------------------------------------------------------------------

# Part 16 --- Persistence Interaction

## 33. Replication and Persistence Solve Different Problems

Replication:

``` text
runtime redundancy / availability
```

Persistence:

``` text
durability/restart recovery characteristics
```

Backup:

``` text
recoverable historical copy
```

A production design may use more than one.

------------------------------------------------------------------------

## 34. Logical Corruption

Example:

``` text
bad deployment overwrites 1 million cache/state keys
```

Replication can faithfully reproduce the bad writes.

Persistence may also preserve the resulting bad state.

Historical recovery requires a separate recovery strategy when the
workload needs it.

------------------------------------------------------------------------

# Hands-On Lab

## 35. Lab Safety

Use:

``` text
development
test
staging
training
```

The core lab is inspection-based.

Do not terminate production nodes or shards for tutorial purposes.

------------------------------------------------------------------------

## 36. Lab 1 --- Confirm Database Replication

On an authorized administration host:

``` bash
rladmin info db
```

Identify the target database.

Record:

``` text
Database:
ID:
Replication enabled:
Primary shard count:
Status:
```

Use syntax appropriate for the deployed release.

------------------------------------------------------------------------

## 37. Lab 2 --- Inspect Shards

``` bash
rladmin info shard
```

Build:

  Shard   Database   Role      Node   Status
  ------- ---------- --------- ------ --------
                     Primary          
                     Replica          

------------------------------------------------------------------------

## 38. Lab 3 --- Pair Primary and Replica

Build:

  Pair   Primary   Primary Node   Replica   Replica Node
  ------ --------- -------------- --------- --------------
  1                                         
  2                                         

Verify:

``` text
primary node != replica node
```

for expected node-level HA.

------------------------------------------------------------------------

## 39. Lab 4 --- Failure-Domain Check

Add:

  Pair   Primary Domain   Replica Domain   Same Domain?
  ------ ---------------- ---------------- --------------
  1                                        
  2                                        

Document any risk.

Do not move production shards as part of the lab.

------------------------------------------------------------------------

## 40. Lab 5 --- Node Failure Impact Matrix

For each node:

  Node     Primaries   Replicas Databases Affected   HA Impact
  ------ ----------- ---------- -------------------- -----------
                                                     

This becomes an incident-response artifact.

------------------------------------------------------------------------

# Part 17 --- API Inspection

## 41. Database API

Conceptual:

``` bash
curl \
  --cacert /path/to/ca.pem \
  -u '<admin-user>:<admin-password>' \
  https://<cluster-manager>:9443/v1/bdbs
```

Identify fields related to:

``` text
replication
shards
status
```

Field names vary by release.

------------------------------------------------------------------------

## 42. Shards API

Conceptual:

``` bash
curl \
  --cacert /path/to/ca.pem \
  -u '<admin-user>:<admin-password>' \
  https://<cluster-manager>:9443/v1/shards
```

Use this to correlate:

``` text
database
role
node
state
```

Use secure credential handling in production.

------------------------------------------------------------------------

# Part 18 --- Replication Health Worksheet

## 43. Baseline

Complete:

``` text
Database:
Primary shards:
Expected replicas:
Healthy replicas:
Failure domains:
Current synchronization:
Replication alerts:
Last failover:
Current node health:
Capacity headroom:
```

------------------------------------------------------------------------

## 44. Pair-Level Baseline

  Pair    Primary Node   Replica Node   Domains Separated?   Healthy?
  ------- -------------- -------------- -------------------- ----------
  P1/R1                                                      
  P2/R2                                                      

------------------------------------------------------------------------

# Failure Injection / Tabletop

## 45. Failure 1 --- Primary Node Loss

Scenario:

``` text
P1 -> Node 1
R1 -> Node 3

Node 1 fails.
```

Answer:

``` text
Is R1 healthy?
What role transition is expected?
What might clients observe?
Is another replica eventually required?
Does Node 3 have capacity?
```

------------------------------------------------------------------------

## 46. Failure 2 --- Replica Node Loss

Scenario:

``` text
P1 -> Node 1
R1 -> Node 3

Node 3 fails.
```

The primary may continue serving.

But:

``` text
redundancy is degraded
```

Required action:

``` text
restore replica protection
```

not:

``` text
ignore because application is healthy
```

------------------------------------------------------------------------

## 47. Failure 3 --- Same Failure Domain

Scenario:

``` text
P1 -> Node 1 / AZ-A
R1 -> Node 2 / AZ-A
```

Failure:

``` text
AZ-A unavailable
```

Both copies may be affected.

Lesson:

``` text
node separation != zone separation
```

------------------------------------------------------------------------

## 48. Failure 4 --- Lag Before Failure

Timeline:

``` text
T1 client writes A
T2 primary acknowledges A
T3 replica is behind
T4 primary fails
```

Question:

``` text
Could the promoted state differ from the last acknowledged client state?
```

The answer depends on the exact replication guarantees and failure
timing.

This is why RPO must be based on documented product behavior, not
assumption.

------------------------------------------------------------------------

## 49. Failure 5 --- Retry Storm During Failover

Scenario:

``` text
1,000 clients
timeout
immediate retry
immediate retry
immediate retry
```

Potential impact:

``` text
connection surge
CPU surge
network surge
recovery slowdown
duplicate non-idempotent operations
```

Review:

``` text
backoff
jitter
retry limits
idempotency
```

------------------------------------------------------------------------

## 50. Failure 6 --- Replica Cannot Be Recreated

Scenario:

``` text
database serving after failover
new replica remains unavailable
```

Investigate:

``` text
cluster capacity
node health
placement constraints
failure-domain availability
memory
recovery status
```

Do not declare HA restored.

------------------------------------------------------------------------

# Part 19 --- Optional Controlled HA Test

## 51. Test Only With Approval

A controlled failover exercise can be valuable in:

``` text
dedicated lab
non-production
approved staging
```

Do not improvise node/process termination.

Use the supported Redis Enterprise failure/maintenance procedure for the
exact release.

------------------------------------------------------------------------

## 52. Capture Before Test

Record:

``` text
database health
primary/replica map
node health
latency
error rate
ops/sec
replication state
client connections
```

------------------------------------------------------------------------

## 53. During Test

Observe:

``` text
failure detection
client errors
role changes
database availability
latency
replication state
```

Record timestamps.

------------------------------------------------------------------------

## 54. After Test

Validate:

``` text
application recovered
database healthy
primary roles healthy
replicas restored
failure-domain separation healthy
latency baseline restored
alerts cleared
```

------------------------------------------------------------------------

# Troubleshooting

## 55. Replica Unhealthy

Check:

``` text
replication enabled
replica state
primary state
hosting node
node capacity
network
placement
synchronization status
recent failover
recent maintenance
```

------------------------------------------------------------------------

## 56. Replication Lag Elevated

Investigate:

``` text
primary write rate
network
replica CPU
node CPU
memory pressure
recovery/synchronization
large writes
background activity
```

Compare against the database's normal baseline.

------------------------------------------------------------------------

## 57. Frequent Failovers

Check:

``` text
node stability
network instability
resource saturation
platform alerts
maintenance activity
infrastructure health
```

Failover is a protection mechanism, not a normal steady-state workload
pattern.

------------------------------------------------------------------------

## 58. Application Errors During Failover

Review:

``` text
connection timeout
socket timeout
connection pool
retry count
retry interval
backoff
jitter
idempotency
DNS/endpoint usage
```

The Redis platform and client behavior must be evaluated together.

------------------------------------------------------------------------

## 59. Database Healthy but Replica Missing

Treat as:

``` text
service available
HA degraded
```

Prioritize redundancy restoration according to service criticality.

------------------------------------------------------------------------

## 60. Replica on Wrong Failure Domain

Check:

``` text
rack/zone configuration
node metadata
available capacity
placement constraints
recent cluster change
```

Do not manually force unsupported placement changes.

Follow documented Redis Enterprise procedures.

------------------------------------------------------------------------

# Part 20 --- Replication Incident Runbooks

## 61. Runbook --- Primary Failure

``` text
1. Record incident timestamp.
2. Identify database.
3. Identify failed primary shard.
4. Identify hosting node.
5. Identify replica.
6. Confirm replica health.
7. Observe HA transition.
8. Validate database endpoint.
9. Validate application traffic.
10. Check client errors/retries.
11. Confirm active shard role.
12. Check remaining cluster capacity.
13. Confirm replacement redundancy is being restored.
14. Validate new primary/replica placement.
15. Confirm replication healthy.
16. Close only after HA protection is restored.
```

------------------------------------------------------------------------

## 62. Runbook --- Replica Failure

``` text
1. Identify database.
2. Identify failed replica.
3. Identify corresponding primary.
4. Confirm primary healthy.
5. Mark database as degraded HA.
6. Identify failed node/domain.
7. Check cluster capacity.
8. Check synchronization/recovery.
9. Avoid unnecessary maintenance.
10. Restore replica protection.
11. Validate placement.
12. Validate replication health.
13. Clear degraded-HA condition.
```

------------------------------------------------------------------------

## 63. Runbook --- Replication Lag

``` text
1. Identify database.
2. Identify affected replica.
3. Capture lag metric.
4. Compare historical baseline.
5. Capture primary write rate.
6. Check primary CPU.
7. Check replica CPU.
8. Check node network.
9. Check memory pressure.
10. Check synchronization activity.
11. Check large/burst writes.
12. Check infrastructure/network events.
13. Stabilize workload if necessary.
14. Confirm lag returns to normal.
15. Review RPO exposure if incident was significant.
```

------------------------------------------------------------------------

## 64. Runbook --- Post-Failover HA Validation

``` text
1. Confirm database endpoint healthy.
2. Confirm application transactions healthy.
3. List primary shards.
4. List replica shards.
5. Pair primaries and replicas.
6. Confirm all expected replicas exist.
7. Confirm replication healthy.
8. Confirm failure-domain separation.
9. Confirm node CPU/memory headroom.
10. Confirm latency baseline.
11. Confirm error rate baseline.
12. Confirm no recovery alert remains.
13. Update topology diagram.
14. Record failover timeline.
```

------------------------------------------------------------------------

# Part 21 --- RPO and RTO

## 65. RPO

Recovery Point Objective asks:

> How much data loss can the business tolerate?

Examples:

``` text
0 seconds
5 seconds
1 minute
15 minutes
```

Do not select RPO from Redis configuration alone.

It is a business requirement that architecture must satisfy.

------------------------------------------------------------------------

## 66. RTO

Recovery Time Objective asks:

> How long can the service be unavailable?

Examples:

``` text
seconds
minutes
hours
```

Replication primarily helps reduce service recovery time, but the
complete RTO includes:

``` text
failure detection
failover
client reconnect
application recovery
operator response
```

------------------------------------------------------------------------

## 67. Map Architecture to Objectives

Document:

  Requirement    Target   Mechanism                                   Validated?
  -------------- -------- ------------------------------------------- ------------
  Availability            Replication/HA                              
  RPO                     Replication + persistence + backup design   
  RTO                     HA + client behavior + runbook              

Never claim an RPO/RTO that has not been architecturally justified and
tested.

------------------------------------------------------------------------

# Part 22 --- Production Replication Review

## 68. Design Template

``` text
Database:
Business criticality:
Primary shards:
Replication enabled:
Replica count/model:
Failure domains:
Persistence:
Backup:
RPO:
RTO:
Peak write rate:
Replication lag baseline:
Client timeout:
Retry policy:
Backoff/jitter:
Failover test frequency:
Last HA test:
Monitoring:
Alerts:
Runbook:
Owner:
```

------------------------------------------------------------------------

## 69. Anti-Patterns

Avoid:

``` text
replication disabled for critical workload without documented reason
primary and replica in same failure domain
assuming replica equals backup
assuming HA means zero data loss
no replication monitoring
no degraded-HA alert
no spare capacity
no client retry strategy
unbounded retry storms
closing incident before redundancy restored
never testing failover
```

------------------------------------------------------------------------

# Production Acceptance

## 70. Replication Acceptance Checklist

-   [ ] Replication requirement documented.
-   [ ] Primary shard count documented.
-   [ ] Replica topology documented.
-   [ ] Primary/replica node separation validated.
-   [ ] Failure-domain separation validated.
-   [ ] Replication health monitoring available.
-   [ ] Lag/progress monitoring available where supported.
-   [ ] Degraded-HA alert configured.
-   [ ] Failover alert configured.
-   [ ] Node failure alert configured.
-   [ ] Capacity for failover reviewed.
-   [ ] Capacity for replica recreation reviewed.
-   [ ] Persistence strategy documented.
-   [ ] Backup strategy documented.
-   [ ] RPO documented.
-   [ ] RTO documented.
-   [ ] Client timeout policy documented.
-   [ ] Client retry policy documented.
-   [ ] Backoff/jitter reviewed.
-   [ ] Non-idempotent retry risk reviewed.
-   [ ] Primary-failure runbook available.
-   [ ] Replica-failure runbook available.
-   [ ] Replication-lag runbook available.
-   [ ] Post-failover validation runbook available.
-   [ ] Controlled HA test completed or scheduled according to policy.

------------------------------------------------------------------------

# Knowledge Validation

## 71. Questions

You should be able to answer:

1.  Why is replication used?
2.  What is a primary shard?
3.  What is a replica shard?
4.  Why is a primary role not permanently tied to one node?
5.  Why is replication not backup?
6.  What is replication lag?
7.  Why can lag matter during primary failure?
8.  What is the difference between availability and durability?
9.  Why should zero-data-loss guarantees not be assumed?
10. Why should primary and replica be on separate nodes?
11. Why may separate nodes still be insufficient for zone resilience?
12. What is initial synchronization?
13. What is resynchronization?
14. What resources can synchronization consume?
15. What happens conceptually during failover?
16. What can clients observe during failover?
17. Why can retries create a recovery storm?
18. Why is service recovery not the same as HA restoration?
19. What is degraded redundancy?
20. Why should maintenance generally be avoided during degraded HA?
21. What replication signals should be monitored?
22. Why do replicas require capacity planning?
23. How are replication, persistence, and backup different?
24. What is RPO?
25. What is RTO?
26. Why must RPO/RTO be tested rather than assumed?

------------------------------------------------------------------------

# Hands-On Acceptance Checklist

## 72. Lab Completion

-   [ ] Confirmed database replication state.
-   [ ] Inspected shard roles.
-   [ ] Paired primaries and replicas.
-   [ ] Verified node separation.
-   [ ] Reviewed failure-domain separation.
-   [ ] Built node failure impact matrix.
-   [ ] Reviewed database API.
-   [ ] Reviewed shard API.
-   [ ] Created replication health baseline.
-   [ ] Completed primary-node-loss tabletop.
-   [ ] Completed replica-node-loss tabletop.
-   [ ] Completed same-domain failure exercise.
-   [ ] Reviewed replication-lag failure window.
-   [ ] Reviewed retry-storm scenario.
-   [ ] Reviewed replica-recreation failure.
-   [ ] Reviewed controlled HA test procedure.
-   [ ] Reviewed primary-failure runbook.
-   [ ] Reviewed replica-failure runbook.
-   [ ] Reviewed lag runbook.
-   [ ] Reviewed post-failover acceptance procedure.

------------------------------------------------------------------------

# 73. Key Takeaways

1.  Replication provides redundant shard copies for high availability.
2.  A primary is the active shard role, not a permanent node identity.
3.  Replicas must be monitored as actively as primaries.
4.  Replication is not backup.
5.  Replication lag creates a potential difference between active and
    replica state.
6.  High availability does not automatically guarantee zero data loss.
7.  Availability and durability are different engineering objectives.
8.  Primary and replica placement must reflect real failure domains.
9.  Synchronization and recovery consume capacity.
10. Failover includes clients, routing, role changes, and redundancy
    restoration.
11. Retry storms can make failover recovery worse.
12. An application can be healthy while Redis redundancy remains
    degraded.
13. Incidents should not close until expected HA protection is restored.
14. Replication, persistence, and backup solve different failure
    problems.
15. RPO and RTO must be documented, architected, and tested.

------------------------------------------------------------------------

# 74. References

Validate replication semantics, synchronization behavior, failover
behavior, monitoring fields, and HA guarantees against documentation for
the exact Redis Enterprise / Redis Software release deployed.

Key documentation areas:

-   Redis Enterprise replication
-   high availability
-   shard roles
-   failover
-   rack/zone awareness
-   database replication
-   persistence
-   backup and restore
-   monitoring and alerts
-   `rladmin`
-   Redis Enterprise REST API

------------------------------------------------------------------------

# Next Chapter

**Chapter 09 --- Redis Enterprise Administration Interfaces: UI,
`rladmin` & REST API**

Chapter 09 will cover:

-   Cluster Manager UI
-   `rladmin`
-   REST API
-   read vs change operations
-   authentication
-   secure credential handling
-   cluster inspection
-   database inspection
-   node/shard/proxy inspection
-   operational automation
-   API failure handling
-   auditability
-   hands-on administration lab
-   production administration runbooks
