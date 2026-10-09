# Chapter 35 --- Redis Replication, High Availability & Failover Engineering

**Status:** Canonical\
**Track:** Redis Enterprise / Redis Software Production Engineering\
**Part:** Part 4 --- Persistence, Availability & Data Protection\
**Level:** Advanced → Production Redis Availability Engineering\
**Audience:** SREs, DBREs, Platform Engineers, Redis Administrators,
Developers\
**Lab type:** Replication discovery, primary/replica behavior,
replication lag, partial/full synchronization, backlog analysis, planned
failover, unplanned failure, client reconnection, data-loss-window
analysis, replica capacity, failure injection, observability,
troubleshooting, runbooks, and production acceptance

------------------------------------------------------------------------

# 1. Objective

Chapter 34 covered persistence and restart durability. This chapter
focuses on keeping Redis available when a node or process fails.

``` text
                 +--> Replica 1
                 |
Application --> Primary
                 |
                 +--> Replica 2
```

Redis Enterprise provides product-managed high availability and shard
placement. Redis OSS deployments may use Sentinel, Redis Cluster, or
another supported architecture. Validate exact failover behavior against
the deployed topology.

By the end, you should be able to explain and operate replication, lag,
full/partial synchronization, replication backlog, replica sizing,
planned/unplanned failover, possible data-loss windows, client recovery,
failure domains, stale-primary/split-brain risks, monitoring, testing,
troubleshooting, and production runbooks.

------------------------------------------------------------------------

# 2. Core Production Principle

Replication improves availability, but does not automatically guarantee
zero data loss.

``` text
client write
    |
    v
primary memory
    |
    +--> response to client
    |
    +--> replication stream --> replica
```

With asynchronous replication, a primary may acknowledge a write before
a replica has applied it. A failure in that interval can expose an
acknowledged-write loss window.

------------------------------------------------------------------------

# Part 1 --- Replication, Persistence & Backup

## 3. Separate Responsibilities

Replication answers:

``` text
Can another Redis node continue serving after failure?
```

Persistence answers:

``` text
Can Redis recover state after restart?
```

Backup answers:

``` text
Can an older independent copy be restored?
```

Production designs often require all three.

------------------------------------------------------------------------

# Part 2 --- Primary and Replica

## 4. Primary

In a conventional primary/replica topology, writes are directed to the
primary, which propagates replication data to replicas.

## 5. Replica

A replica maintains a copy of primary state and can support failover
and, where appropriate, selected read or backup workflows.

------------------------------------------------------------------------

# Part 3 --- Asynchronous Replication

## 6. Failure Window

``` text
T0 client sends SET
T1 primary applies SET
T2 primary replies OK
T3 replica receives/applies SET
```

Failure between T2 and T3 can leave the client believing the write
succeeded while the failover target does not contain it.

## 7. RPO Implication

Possible failover loss depends on replication lag, network behavior,
write rate, failure timing, promotion behavior, and topology.

Never claim zero-loss failover unless the deployed architecture
explicitly provides and has validated that guarantee.

------------------------------------------------------------------------

# Part 4 --- Replication Discovery

## 8. `INFO replication`

Traditional Redis exposes replication information through:

``` redis
INFO replication
```

Typical concepts include:

``` text
role
connected replicas
replication offsets
link state
replication backlog
```

Exact fields vary by Redis version.

------------------------------------------------------------------------

# Part 5 --- Replication Progress

## 9. Offsets

Conceptually:

``` text
primary offset = 10,000,000
replica offset =  9,999,000
difference     =      1,000
```

Offset distance represents replication-stream progress, not directly
elapsed time.

## 10. Time-Based Freshness

Applications often care about how old replica state is. Measure both
replication progress and time-based freshness where available.

------------------------------------------------------------------------

# Part 6 --- Full Synchronization

## 11. Full Sync

When a replica cannot continue from retained replication history, Redis
may require a full synchronization.

``` text
primary dataset
      |
      v
full transfer
      |
      v
replica
```

Full sync can consume CPU, memory, network, and persistence/storage
resources depending on implementation.

------------------------------------------------------------------------

# Part 7 --- Partial Synchronization

## 12. Partial Resync

If sufficient replication history remains, a reconnecting replica can
often receive only missing replication data.

This is significantly cheaper than repeatedly transferring the entire
dataset.

------------------------------------------------------------------------

# Part 8 --- Replication Backlog

## 13. Purpose

The replication backlog retains recent replication history to support
partial resynchronization.

## 14. Approximate History Window

Conceptually:

``` text
backlog history seconds
≈ backlog bytes / peak replication bytes per second
```

Example:

``` text
1 GB backlog / 50 MB/sec ≈ 20 seconds
```

This is capacity intuition, not a guarantee.

## 15. Peak Traffic Matters

A fixed backlog covers less time during high write traffic. Size and
validate against peak replication traffic, not daily average.

------------------------------------------------------------------------

# Part 9 --- Replica Capacity

## 16. Promotion Readiness

A replica intended for failover must support the production workload
after promotion.

Validate:

``` text
CPU
memory
network
storage
connections
persistence workload
```

## 17. Capacity Symmetry

Replicas do not always need mathematically identical resources, but they
must have proven capacity for primary duties.

------------------------------------------------------------------------

# Part 10 --- Memory and Network

## 18. Memory Headroom

Include:

``` text
dataset
replication buffers
client buffers
persistence/COW
failover workload
```

## 19. Network

Replication consumes bandwidth in addition to application traffic. Large
values and high write rates can make replication network-heavy.

------------------------------------------------------------------------

# Part 11 --- Replica Reads

## 20. Stale Read Risk

``` text
write to primary
immediate read from replica
```

may return older state.

Before using replica reads, answer:

``` text
Can reads be stale?
How stale?
Does read-your-write matter?
Does ordering matter?
```

Do not enable replica reads solely to reduce primary CPU.

------------------------------------------------------------------------

# Part 12 --- HA Control Plane

## 21. Responsibilities

A supported HA mechanism typically performs:

``` text
health detection
failure decision
replica selection
promotion
topology update
client routing/reconnection
```

Redis Enterprise manages this according to its cluster/database
architecture. OSS architectures differ.

------------------------------------------------------------------------

# Part 13 --- Failure Detection

## 22. Tradeoff

Detection that is too aggressive can fail over during transient network
problems. Detection that is too slow increases outage duration.

Use vendor-supported configuration and validate against real network
behavior.

------------------------------------------------------------------------

# Part 14 --- Planned Failover

## 23. Uses

Planned failover can support:

``` text
maintenance
node replacement
upgrade
HA validation
```

It should verify that the standby path actually works before an
emergency.

------------------------------------------------------------------------

# Part 15 --- Unplanned Failover

## 24. Examples

``` text
process crash
host failure
node loss
network isolation
```

The HA system must restore service according to the supported topology.

------------------------------------------------------------------------

# Part 16 --- Failover Timeline

## 25. End-to-End Path

``` text
primary fails
    |
failure detection
    |
promotion
    |
routing/topology update
    |
client reconnect
    |
application stabilizes
```

Application-visible RTO includes the entire path.

------------------------------------------------------------------------

# Part 17 --- Client Recovery

## 26. Reconnection

Clients must tolerate:

``` text
connection reset
socket timeout
temporary errors
endpoint/topology change
```

Use bounded retries, backoff, jitter, and topology-aware client behavior
where required.

## 27. Retry Ambiguity

A connection can fail after Redis applied a write but before the client
received the response. Retrying a non-idempotent operation can duplicate
effects.

## 28. Idempotency

Where business semantics require it, use request IDs, operation IDs,
versions, or authoritative uniqueness constraints.

------------------------------------------------------------------------

# Part 18 --- Stale Primary & Split Brain

## 29. Stale Primary

During some network failures, an old primary can become isolated while
another node is promoted.

Do not build custom failover by merely promoting a replica and changing
DNS.

## 30. Split Brain

Split brain can create divergent writes and conflicting authority.

Use supported Redis Enterprise/Redis HA mechanisms.

## 31. Fencing

Fencing is the general concept of preventing an old authority from
continuing unsafe work after leadership changes. Exact mechanisms depend
on the deployed product/topology.

------------------------------------------------------------------------

# Part 19 --- Failure Domains

## 32. Placement

Avoid placing all copies in the same failure domain.

Consider:

``` text
process
host
rack
availability zone
power/network domain
```

## 33. Cross-Zone

Cross-zone placement improves resilience but may add network latency,
cost, and failure-mode complexity.

## 34. Regional Failure

Local HA is not automatically cross-region disaster recovery. DR is a
separate design problem.

------------------------------------------------------------------------

# Part 20 --- Degraded Redundancy

## 35. Replica Loss

A healthy primary with a failed replica may continue serving, but
redundancy is reduced.

Treat prolonged loss of redundancy as an availability-risk incident.

## 36. Restore Redundancy

Replacement replicas may require synchronization. Monitor transfer
duration and resource impact until redundancy is restored.

------------------------------------------------------------------------

# Part 21 --- Repeated Full Sync

## 37. Warning Signal

Repeated full synchronization can indicate:

``` text
unstable network
replica restarts
insufficient backlog
resource pressure
misconfiguration
```

It can become self-amplifying under load.

------------------------------------------------------------------------

# Part 22 --- Replication and Persistence

## 38. Combined Pressure

Replication and persistence may overlap:

``` text
full sync
+
RDB/AOF work
+
high write rate
+
client reconnects
```

Capacity testing should include realistic combinations.

------------------------------------------------------------------------

# Part 23 --- Redis Enterprise Considerations

## 39. Product Awareness

Redis Enterprise uses product-specific database shards, replicas,
cluster nodes, placement, and failover behavior.

Use Redis Enterprise administration and monitoring interfaces as the
authoritative topology view.

Do not assume every OSS Sentinel/Cluster command maps directly to Redis
Enterprise.

------------------------------------------------------------------------

# Part 24 --- Kubernetes Considerations

## 40. Scheduling

Validate:

``` text
anti-affinity
zone placement
persistent volumes
pod disruption
node drains
termination grace
network policy
```

Do not allow all HA copies to land in one failure domain.

------------------------------------------------------------------------

# Part 25 --- Maintenance

## 41. Pre-Maintenance Checks

Before removing a node or replica:

``` text
confirm redundancy
confirm replication health
confirm lag
confirm target capacity
confirm client behavior
confirm rollback
```

Never intentionally remove the only healthy redundant copy.

------------------------------------------------------------------------

# Part 26 --- Rolling Upgrades

## 42. Principle

A rolling upgrade should preserve required redundancy throughout the
sequence.

Follow vendor-supported version compatibility and upgrade order.

------------------------------------------------------------------------

# Part 27 --- Observability

## 43. Primary Metrics

Track:

``` text
role
connected replicas
replication offset
replication backlog
replica link state
```

## 44. Replica Metrics

Track:

``` text
primary link state
replication progress
lag/freshness
sync state
last replication I/O
```

## 45. Failover Metrics

Track:

``` text
failover count
failover duration
client error rate
client reconnect duration
observed data-loss window
```

## 46. Infrastructure

Correlate:

``` text
network latency
packet loss
CPU
memory
disk
node health
zone health
```

------------------------------------------------------------------------

# Part 28 --- Replication Lag SLO

## 47. Example

Illustrative only:

``` text
normal freshness < 1 second
warning > 2 seconds
critical > 10 seconds
```

Derive thresholds from the application's RPO and workload.

------------------------------------------------------------------------

# Part 29 --- Availability SLO

## 48. Application View

Track:

``` text
successful operations
error rate
latency
failover outage duration
```

"Promotion complete" does not prove application recovery.

------------------------------------------------------------------------

# Part 30 --- Capacity Model

## 49. Inputs

Record:

``` text
dataset size
write ops/sec
write bytes/sec
replication bytes/sec
backlog bytes
replica count
network capacity
full-sync duration
failover workload
```

## 50. Failover Capacity

After promotion, the target may need to support:

``` text
full application workload
client reconnect storm
persistence
replication to remaining/new replicas
```

------------------------------------------------------------------------

# Part 31 --- Hands-On Lab

## 51. Safety

Use a disposable HA lab.

Do not stop a production primary to practice failover.

For Redis Enterprise, use vendor-supported failover/test procedures
appropriate to the lab topology.

------------------------------------------------------------------------

# Part 32 --- Baseline Discovery

## 52. Traditional Redis

``` redis
INFO replication
```

Record:

``` text
role
replica count
offsets
link state
backlog
```

## 53. Test Data

``` redis
SET tutorial:chapter35:key value1
INCR tutorial:chapter35:counter
```

Verify replication according to the lab architecture.

------------------------------------------------------------------------

# Part 33 --- Write-Load Generator

## 54. Python

``` python
import os
import redis

r = redis.Redis(
    host=os.getenv("REDIS_HOST", "localhost"),
    port=int(os.getenv("REDIS_PORT", "6379")),
    password=os.getenv("REDIS_PASSWORD") or None,
    decode_responses=True,
)

for i in range(100000):
    r.set(
        f"tutorial:chapter35:write:{i % 1000}",
        str(i),
    )

    if i % 10000 == 0:
        print("writes:", i)
```

Observe replication metrics during load.

------------------------------------------------------------------------

# Part 34 --- Short Replica Disconnect

## 55. Partial Resync Test

In a disposable lab:

1.  isolate/stop one replica;
2.  continue primary writes;
3.  record offset divergence;
4.  restore the replica before retained replication history is
    exhausted;
5.  observe whether partial synchronization occurs;
6.  record resync duration.

------------------------------------------------------------------------

# Part 35 --- Long Replica Disconnect

## 56. Full Sync Test

If safe and practical, keep the replica unavailable long enough to
require a full synchronization.

Measure:

``` text
CPU
memory
network
sync duration
application latency
```

------------------------------------------------------------------------

# Part 36 --- Planned Failover Lab

## 57. Procedure

Before:

``` text
confirm replication healthy
confirm target current
confirm target capacity
start application monitoring
```

During:

``` text
record client errors
record latency
record promotion time
```

After:

``` text
verify new primary
verify reads/writes
verify redundancy
```

------------------------------------------------------------------------

# Part 37 --- Unplanned Failure Lab

## 58. Procedure

Using a supported disposable-lab method, fail the primary.

Measure:

``` text
failure detection
promotion
routing
client reconnect
stable application recovery
```

------------------------------------------------------------------------

# Part 38 --- Data-Loss Window Lab

## 59. Sequential Writes

Generate:

``` text
sequence=1
sequence=2
sequence=3
...
```

Fail the primary while writes are active.

After failover compare:

``` text
highest sequence acknowledged by client
highest sequence recovered
```

The difference provides empirical evidence for the tested topology.

------------------------------------------------------------------------

# Part 39 --- Client Recovery Lab

## 60. Continuous Client

Run a client continuously during failover.

Record:

``` text
success
timeout
connection error
retry
recovery timestamp
```

Do not hide all failures behind infinite retry.

------------------------------------------------------------------------

# Part 40 --- Retry Ambiguity Lab

## 61. Non-Idempotent Example

``` redis
INCR tutorial:chapter35:ambiguous-counter
```

A lost response can make a retry ambiguous.

This is a demonstration, not a recommended business transaction design.

------------------------------------------------------------------------

# Part 41 --- Replica Read Lab

## 62. If Supported

Write sequential values to the primary and immediately read from a
replica.

Measure stale-read behavior and compare it with application consistency
requirements.

------------------------------------------------------------------------

# Part 42 --- Promotion Capacity Lab

## 63. Validate

After planned promotion, load-test within safe lab limits.

Measure:

``` text
CPU
memory
network
connections
latency
persistence
```

------------------------------------------------------------------------

# Part 43 --- Reconnect Storm Lab

## 64. Multiple Clients

Start many disposable clients and trigger failover.

Observe:

``` text
simultaneous reconnects
connection rate
Redis CPU
application recovery
```

Use backoff/jitter where appropriate.

------------------------------------------------------------------------

# Part 44 --- Failure Injection

## 65. Failure 1 --- Replica Process Failure

Verify service remains available and degraded-redundancy alerting works.

## 66. Failure 2 --- Primary Process Failure

Verify supported failover and application recovery.

## 67. Failure 3 --- Replication Link Loss

Observe lag, link-state telemetry, and reconnection.

## 68. Failure 4 --- Backlog Exhaustion

Make a disposable replica miss more history than the backlog retains and
observe full sync.

## 69. Failure 5 --- Slow Replica

Throttle a lab replica and observe lag/resource behavior.

## 70. Failure 6 --- Client Reconnect Storm

Fail over with many active clients and measure recovery.

## 71. Failure 7 --- Writes During Failover

Generate sequential writes and measure acknowledged-write recovery.

## 72. Failure 8 --- Replica Read Staleness

Measure stale reads immediately after primary writes.

## 73. Failure 9 --- Undersized Replica

Constrain a lab replica and promote it to demonstrate failover-capacity
risk.

## 74. Failure 10 --- Shared Failure Domain

Model/test primary and replica in one host/zone and demonstrate
correlated failure risk.

------------------------------------------------------------------------

# Part 45 --- Troubleshooting

## 75. Replica Link Down

Check:

``` text
primary health
replica health
network
DNS/addressing
TLS/authentication
firewall
resource pressure
```

## 76. Replication Lag Increasing

Check:

``` text
write rate
network throughput
replica CPU
replica memory
full/partial sync
large commands
host pressure
```

## 77. Frequent Full Sync

Check:

``` text
replica restarts
network instability
backlog capacity
high write traffic
resource exhaustion
```

## 78. Failover Slow

Break down:

``` text
failure detection
promotion
topology/routing update
client reconnect
application retry
```

## 79. Data Missing After Failover

Check:

``` text
pre-failure replication lag
acknowledged-write timeline
promotion target
retry ambiguity
persistence/backup options
```

## 80. New Primary Overloaded

Check:

``` text
replica sizing
reconnect storm
read/write rate
replica rebuild
persistence activity
```

## 81. Stale Reads

Check read routing, replication lag, and consistency requirements.

## 82. Redundancy Not Restored

Ensure a healthy replica is rebuilt/synchronized after failover.

------------------------------------------------------------------------

# Part 46 --- Production Runbooks

## 83. Runbook --- Replica Down

``` text
1. Confirm primary health.
2. Confirm failed replica.
3. Check failure domain.
4. Check network/replication errors.
5. Protect remaining primary.
6. Restore/rebuild replica.
7. Monitor synchronization.
8. Verify replication healthy.
9. Verify redundancy restored.
10. Document degraded-duration exposure.
```

## 84. Runbook --- Planned Failover

``` text
1. Confirm topology.
2. Confirm replica health/lag.
3. Confirm target capacity.
4. Confirm application monitoring.
5. Execute supported failover.
6. Verify client recovery.
7. Verify writes/reads.
8. Verify persistence/replication health.
9. Verify redundancy.
10. Record RTO and anomalies.
```

## 85. Runbook --- Unplanned Primary Failure

``` text
1. Confirm primary failure.
2. Observe HA decision/promotion.
3. Avoid conflicting manual promotion.
4. Monitor client errors.
5. Verify new primary.
6. Validate critical data.
7. Measure possible loss window.
8. Restore redundancy.
9. Monitor stability.
10. Complete incident evidence.
```

## 86. Runbook --- Replication Lag

``` text
1. Measure lag/freshness.
2. Measure write traffic.
3. Check replication link.
4. Check network capacity.
5. Check replica CPU/memory.
6. Identify sync/persistence activity.
7. Reduce avoidable pressure.
8. Restore healthy replication.
9. Confirm lag returns to baseline.
10. Review backlog/capacity.
```

## 87. Runbook --- Repeated Full Synchronization

``` text
1. Count sync events.
2. Identify affected replicas.
3. Check restart history.
4. Check network instability.
5. Measure peak replication traffic.
6. Evaluate backlog history window.
7. Check memory/network capacity.
8. Correct root cause.
9. Verify partial resync behavior.
10. Update HA capacity model.
```

------------------------------------------------------------------------

# Part 47 --- HA Design Template

## 88. Fields

``` text
Database:
Owner:
Topology:
Primary location:
Replica locations:
Failure domains:
Dataset size:
Peak write ops/sec:
Peak write bytes/sec:
Replication bytes/sec:
Replication backlog:
Approximate backlog window:
Normal lag:
Lag warning:
Lag critical:
Failover mechanism:
Failure detection:
Expected RPO:
Expected RTO:
Replica capacity:
Replica reads allowed:
Client topology awareness:
Client retry policy:
Reconnect backoff/jitter:
Persistence:
Backup:
Last planned failover test:
Last unplanned failure test:
Runbook:
```

------------------------------------------------------------------------

# Part 48 --- Failover Test Record

## 89. Evidence

``` text
test date
topology
dataset size
write rate
failure injected
detection time
promotion time
client recovery time
total application RTO
highest acknowledged sequence
highest recovered sequence
observed loss
replication restored time
```

------------------------------------------------------------------------

# Part 49 --- RPO & RTO Worksheets

## 90. RPO Questions

``` text
What is normal replication lag?
What is P99 lag?
What happens during network congestion?
Which writes can be acknowledged before replica application?
What business loss is acceptable?
```

## 91. RTO Components

``` text
RTO
=
detection
+
promotion
+
routing
+
client reconnect
+
application stabilization
```

Measure each component.

------------------------------------------------------------------------

# Part 50 --- Topology Review

## 92. Questions

``` text
Can one host failure remove all copies?
Can one zone failure remove all copies?
Can the replica handle primary load?
Can clients discover the new primary?
Can replication recover after network loss?
Is backlog sufficient for expected interruptions?
```

------------------------------------------------------------------------

# Production Acceptance Checklist

## 93. Replication & HA Engineering

-   [ ] HA topology documented.
-   [ ] Primary and replicas identified.
-   [ ] Failure domains documented.
-   [ ] Replication mode understood.
-   [ ] Asynchronous-loss implications accepted.
-   [ ] Replication/product metrics monitored.
-   [ ] Replication-link alerts configured.
-   [ ] Replication lag monitored.
-   [ ] Lag thresholds tied to RPO.
-   [ ] Replication backlog understood.
-   [ ] Backlog window estimated at peak traffic.
-   [ ] Partial resynchronization tested.
-   [ ] Full synchronization tested.
-   [ ] Full-sync resource impact measured.
-   [ ] Replica capacity validated.
-   [ ] Replica memory headroom validated.
-   [ ] Replica-read consistency reviewed.
-   [ ] Client reconnect behavior tested.
-   [ ] Retry ambiguity reviewed.
-   [ ] Planned failover tested.
-   [ ] Unplanned failover tested.
-   [ ] Application-visible RTO measured.
-   [ ] Data-loss window measured.
-   [ ] Reconnect storm tested.
-   [ ] Redundancy restoration tested.
-   [ ] Production runbooks validated.

------------------------------------------------------------------------

# Knowledge Validation

## 94. Questions

1.  What problem does Redis replication solve?
2.  How is replication different from persistence?
3.  Why can asynchronous replication lose acknowledged writes?
4.  What is replication lag?
5.  What is a replication offset?
6.  Why is offset distance not directly time lag?
7.  What is full synchronization?
8.  What is partial synchronization?
9.  What is the replication backlog?
10. Why does high write traffic reduce backlog history time?
11. Why can full sync be expensive?
12. Why must failover replicas have production capacity?
13. Why can replica reads be stale?
14. What is planned failover?
15. What is unplanned failover?
16. What contributes to application-visible RTO?
17. Why must clients reconnect correctly?
18. What is retry ambiguity?
19. Why does idempotency matter during failover?
20. What is split brain?
21. What is stale-primary risk?
22. Why should replicas span failure domains?
23. Why does local HA not equal regional DR?
24. Why is replica loss an incident if service remains available?
25. What can repeated full sync indicate?
26. Why should persistence and replication be monitored separately?
27. Why test failover under write load?
28. How can an observed data-loss window be measured?
29. Why must redundancy be restored after failover?
30. What must pass before Redis HA is production-ready?

------------------------------------------------------------------------

# Hands-On Acceptance Checklist

## 95. Lab Completion

-   [ ] Inspected replication topology.
-   [ ] Captured replication baseline.
-   [ ] Generated write load.
-   [ ] Observed replication progress.
-   [ ] Disconnected replica.
-   [ ] Tested short disconnect.
-   [ ] Observed partial resync where supported.
-   [ ] Tested long disconnect.
-   [ ] Observed full sync where supported.
-   [ ] Measured full-sync impact.
-   [ ] Executed planned failover.
-   [ ] Simulated unplanned primary failure.
-   [ ] Measured application RTO.
-   [ ] Ran sequential-write loss test.
-   [ ] Measured observed loss window.
-   [ ] Tested client recovery.
-   [ ] Reviewed retry ambiguity.
-   [ ] Tested replica-read staleness.
-   [ ] Validated promoted replica capacity.
-   [ ] Tested reconnect storm.
-   [ ] Tested shared failure-domain risk.
-   [ ] Completed ten failure scenarios.
-   [ ] Completed troubleshooting.
-   [ ] Reviewed five production runbooks.
-   [ ] Completed HA design template.
-   [ ] Completed production acceptance checklist.

------------------------------------------------------------------------

# 96. Lab Cleanup

Discover only Chapter 35 data keys:

``` bash
redis-cli --scan --pattern 'tutorial:chapter35:*'
```

Review matches and delete only confirmed lab keys in bounded batches:

``` redis
UNLINK <confirmed-key>
```

Do not alter production replication topology as cleanup.

Never use:

``` redis
KEYS tutorial:chapter35:*
FLUSHDB
FLUSHALL
```

against a shared or production database.

Restore or destroy the disposable lab topology according to the test
procedure.

------------------------------------------------------------------------

# 97. Key Takeaways

1.  Replication improves availability but is separate from persistence
    and backup.
2.  Redis replication is commonly asynchronous.
3.  Acknowledged writes can therefore have a failover loss window.
4.  Replication offsets show progress but are not directly elapsed-time
    lag.
5.  Full synchronization is much more expensive than partial
    synchronization.
6.  The replication backlog enables partial resynchronization when
    sufficient history remains.
7.  Backlog history shrinks in time as write traffic increases.
8.  Repeated full synchronization is an operational warning.
9.  Failover replicas must have sufficient production capacity.
10. Replica reads can violate read-after-write expectations.
11. Application RTO includes detection, promotion, routing, reconnect,
    and stabilization.
12. Client retry behavior is part of Redis HA.
13. Connection failure can make write outcome ambiguous.
14. Idempotency protects business operations from ambiguous retries.
15. Supported HA mechanisms are needed to manage stale-primary and
    split-brain risks.
16. Primary and replicas should span meaningful failure domains.
17. Replica loss reduces redundancy even when the application remains
    available.
18. Full sync, persistence, reconnects, and production traffic can
    overlap after failure.
19. HA tests must measure application behavior, not only infrastructure
    promotion.
20. Sequential-write testing can empirically measure failover loss.
21. Replica-read behavior must match application consistency
    requirements.
22. Planned failover is a valuable readiness exercise.
23. Unplanned failover must also be tested safely.
24. Redundancy must be restored after promotion.
25. Production HA is proven through measured RPO, RTO, failover, client
    recovery, and topology resilience.

------------------------------------------------------------------------

# 98. References

Validate replication and failover behavior against the exact Redis,
Redis Enterprise, deployment platform, and client versions in use.

Recommended official Redis documentation areas:

-   Redis replication
-   `INFO replication`
-   partial resynchronization
-   replication backlog
-   Redis Sentinel
-   Redis Cluster
-   Redis client handling
-   Redis latency monitoring
-   Redis Enterprise high availability
-   Redis Enterprise database replication
-   Redis Enterprise cluster architecture
-   Redis Enterprise monitoring
-   Redis Enterprise maintenance and failover
-   Redis Enterprise Kubernetes deployment guidance

------------------------------------------------------------------------

# Next Chapter

**Chapter 36 --- Redis Backup, Restore & Disaster Recovery Engineering**

Chapter 36 will cover backup vs. persistence, backup objectives,
frequency, retention, restore points, backup storage, encryption, access
control, logical-deletion recovery, restore validation, restore
performance, RPO/RTO, regional/site failure, DR architecture, recovery
drills, failure injection, observability, troubleshooting, production
runbooks, and acceptance validation.
