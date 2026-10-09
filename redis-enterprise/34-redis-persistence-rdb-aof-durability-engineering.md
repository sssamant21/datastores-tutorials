# Chapter 34 --- Redis Persistence: RDB, AOF & Durability Engineering

**Status:** Canonical\
**Track:** Redis Enterprise / Redis Software Production Engineering\
**Part:** Part 4 --- Persistence, Availability & Data Protection\
**Level:** Intermediate → Production Redis Durability Engineering\
**Audience:** Developers, SREs, DBREs, Platform Engineers, Redis
Administrators\
**Lab type:** Persistence discovery, RDB snapshots, AOF behavior, fsync
policy analysis, restart recovery, durability-window testing,
persistence latency, fork/copy-on-write analysis, AOF rewrite, storage
capacity, failure injection, observability, troubleshooting, runbooks,
and production acceptance

------------------------------------------------------------------------

# 1. Objective

Redis is primarily an in-memory data platform.

Persistence determines how Redis state is represented on durable storage
and what can be recovered after a process or host restart.

A simplified durability path is:

``` text
Application
    |
    v
Redis memory
    |
    +--> RDB snapshot
    |
    +--> AOF
    |
    v
Durable storage
```

Persistence is not the same as:

``` text
replication
high availability
backup
disaster recovery
```

By the end, you should be able to:

-   Explain Redis persistence.
-   Explain RDB snapshots.
-   Explain AOF.
-   Compare RDB and AOF.
-   Understand fsync policy tradeoffs.
-   Estimate durability windows.
-   Validate restart recovery.
-   Understand persistence I/O.
-   Understand fork and copy-on-write pressure.
-   Understand AOF rewrite behavior.
-   Monitor persistence health.
-   Estimate storage capacity.
-   Distinguish persistence from backup.
-   Inject persistence failures safely.
-   Troubleshoot persistence incidents.
-   Build production runbooks and acceptance criteria.

------------------------------------------------------------------------

# 2. Core Production Principle

Persistence is a durability mechanism.

It does not replace:

``` text
replication
high availability
backup
off-site protection
disaster recovery testing
```

A production Redis design must decide separately:

``` text
How much data loss is acceptable?
How quickly must Redis recover?
What happens if one node fails?
What happens if the entire deployment is lost?
How is historical data restored?
```

------------------------------------------------------------------------

# Part 1 --- Durability Vocabulary

## 3. Persistence

Persistence writes Redis state to durable storage so it can potentially
be recovered after restart.

------------------------------------------------------------------------

## 4. Replication

Replication copies state to other Redis nodes.

It improves availability/redundancy but can replicate logical mistakes
as well.

------------------------------------------------------------------------

## 5. High Availability

HA detects failures and restores service through topology/failover
mechanisms.

HA does not automatically provide historical recovery.

------------------------------------------------------------------------

## 6. Backup

A backup is a recoverable copy retained independently according to a
backup policy.

Backup protects against scenarios such as:

``` text
operator deletion
application corruption
logical mistakes
site loss
```

depending on architecture.

------------------------------------------------------------------------

# Part 2 --- Redis Persistence Modes

## 7. Main Mechanisms

Redis commonly supports:

``` text
RDB snapshots
AOF
```

Deployments can use one, both, or neither depending on architecture and
product configuration.

Redis Enterprise persistence capabilities/settings must be validated
against the deployed product version and database configuration.

------------------------------------------------------------------------

# Part 3 --- RDB

## 8. Snapshot Model

RDB creates a point-in-time snapshot representation of the Redis
dataset.

Conceptually:

``` text
memory state
    |
    v
snapshot operation
    |
    v
RDB file
```

------------------------------------------------------------------------

# Part 4 --- RDB Advantages

## 9. Characteristics

RDB can provide:

``` text
compact point-in-time representation
efficient restart/loading characteristics
backup-friendly snapshot artifact
lower continuous write amplification than append-every-write logging
```

Exact behavior depends on workload and version.

------------------------------------------------------------------------

# Part 5 --- RDB Durability Window

## 10. Snapshot Gap

If snapshots occur periodically, writes after the last successful
snapshot may not be represented in that snapshot.

Example:

``` text
12:00 snapshot
12:05 crash
```

Potential recovery point:

``` text
12:00
```

if no newer persistence mechanism exists.

------------------------------------------------------------------------

# Part 6 --- Snapshot Frequency

## 11. Tradeoff

More frequent snapshots can reduce the possible snapshot-only loss
window but increase persistence activity.

Less frequent snapshots reduce snapshot frequency but increase potential
recovery-point distance.

------------------------------------------------------------------------

# Part 7 --- RDB Triggering

## 12. Configuration

Redis supports snapshot configuration based on changes/time criteria and
administrative commands.

Inspect the actual deployment rather than assuming defaults.

Example discovery:

``` redis
CONFIG GET save
```

Whether `CONFIG` is allowed depends on permissions/product
configuration.

------------------------------------------------------------------------

# Part 8 --- `BGSAVE`

## 13. Background Snapshot

In traditional Redis:

``` redis
BGSAVE
```

requests a background RDB save.

Do not run persistence commands casually in production.

Evaluate:

``` text
memory headroom
fork behavior
storage I/O
existing persistence operation
latency sensitivity
```

------------------------------------------------------------------------

# Part 9 --- Fork

## 14. Snapshot Process

On platforms/versions using process forking for persistence, Redis can
create a child process for background persistence work.

Fork itself and subsequent memory copy-on-write behavior can affect
latency and memory.

------------------------------------------------------------------------

# Part 10 --- Copy-on-Write

## 15. COW

After fork:

``` text
parent continues serving writes
child sees snapshot view
modified memory pages may be copied
```

Heavy write workloads during persistence can increase memory pressure.

------------------------------------------------------------------------

# Part 11 --- COW Capacity

## 16. Headroom

Do not size Redis memory so tightly that persistence/fork/COW activity
has no safe headroom.

Observe real workload behavior.

------------------------------------------------------------------------

# Part 12 --- Fork Latency

## 17. Large Dataset Risk

Fork latency can become operationally important for large memory
footprints and host conditions.

Track persistence/fork metrics supported by the deployed Redis version.

------------------------------------------------------------------------

# Part 13 --- AOF

## 18. Append-Only File

AOF records write operations in an append-oriented persistence log.

Conceptually:

``` text
SET
HSET
INCR
DEL
...
  |
  v
AOF
```

Redis can replay the persisted operation history/state representation
during recovery.

------------------------------------------------------------------------

# Part 14 --- AOF Durability

## 19. Fsync Policy

Durability depends significantly on how AOF writes are synchronized to
durable storage.

Common policies in Redis OSS include concepts such as:

``` text
always
every second
no explicit fsync by Redis
```

Validate exact options for the deployed Redis/Redis Enterprise version.

------------------------------------------------------------------------

# Part 15 --- `appendfsync always`

## 20. Tradeoff

Conceptually:

``` text
fsync each write
```

Potential advantage:

``` text
small durability window
```

Potential cost:

``` text
higher storage latency sensitivity
lower write throughput
```

------------------------------------------------------------------------

# Part 16 --- `appendfsync everysec`

## 21. Tradeoff

Conceptually:

``` text
fsync approximately every second
```

This often balances durability and performance.

A failure can still expose a small recent-write loss window.

Do not describe it as zero-loss durability.

------------------------------------------------------------------------

# Part 17 --- `appendfsync no`

## 22. Tradeoff

Redis leaves fsync timing more to the operating system.

This can improve performance characteristics in some environments but
expands uncertainty in durability timing.

Use only with an understood recovery-point objective.

------------------------------------------------------------------------

# Part 18 --- Durability Objective

## 23. RPO

Define the Recovery Point Objective:

``` text
How much recent data can the business tolerate losing?
```

Examples:

``` text
0 seconds
1 second
5 minutes
1 hour
```

Do not choose persistence settings before defining the requirement.

------------------------------------------------------------------------

# Part 19 --- Recovery Objective

## 24. RTO

Define the Recovery Time Objective:

``` text
How long can Redis remain unavailable while recovering?
```

Persistence file size and load time can affect recovery.

------------------------------------------------------------------------

# Part 20 --- RDB vs. AOF

## 25. Simplified Comparison

  -----------------------------------------------------------------------
  Area                    RDB                     AOF
  ----------------------- ----------------------- -----------------------
  Model                   Point-in-time snapshot  Append-oriented write
                                                  persistence

  Durability window       Depends on snapshot     Depends on fsync policy
                          timing                  

  Continuous write I/O    Lower between snapshots Ongoing

  File growth             Snapshot-sized          Can grow until
                                                  rewritten/compacted

  Recovery                Load snapshot           Load/replay persisted
                                                  AOF representation

  Operational concern     Fork/COW/snapshot I/O   Write/fsync/rewrite I/O
  -----------------------------------------------------------------------

This is conceptual. Benchmark the deployed implementation.

------------------------------------------------------------------------

# Part 21 --- Combined Persistence

## 26. RDB + AOF

Some Redis deployments can use both persistence mechanisms.

Do not assume that enabling more persistence automatically produces the
best production outcome.

Measure:

``` text
latency
I/O
recovery
memory headroom
storage capacity
```

------------------------------------------------------------------------

# Part 22 --- AOF Growth

## 27. Why Rewrite Exists

If a key is updated repeatedly:

``` text
SET x 1
SET x 2
SET x 3
...
```

the historical log can contain operations no longer needed to
reconstruct current state efficiently.

AOF rewrite creates a more compact representation.

------------------------------------------------------------------------

# Part 23 --- AOF Rewrite

## 28. Background Rewrite

Traditional Redis provides:

``` redis
BGREWRITEAOF
```

Do not trigger it casually in production.

Understand:

``` text
current rewrite state
memory headroom
fork/COW
disk space
disk throughput
latency
```

------------------------------------------------------------------------

# Part 24 --- Rewrite Amplification

## 29. Storage

During rewrite, the system may temporarily need space for:

``` text
existing AOF
new rewritten AOF
temporary/rewrite state
```

Do not size disk only to the steady-state AOF file.

------------------------------------------------------------------------

# Part 25 --- Disk Headroom

## 30. Capacity

Plan storage for:

``` text
RDB files
AOF files
rewrite temporary capacity
logs
system files
backup staging if applicable
growth
safety margin
```

------------------------------------------------------------------------

# Part 26 --- Disk Latency

## 31. AOF Sensitivity

AOF fsync can expose Redis write latency to storage performance
depending on policy and implementation.

Monitor storage latency, not just Redis CPU.

------------------------------------------------------------------------

# Part 27 --- Slow Fsync

## 32. Symptoms

Potential symptoms can include:

``` text
write latency spikes
persistence warnings
AOF fsync delay
increased command latency
```

Correlate Redis metrics with host/storage telemetry.

------------------------------------------------------------------------

# Part 28 --- Persistence Failure

## 33. Disk Full

A full filesystem can prevent successful persistence and can create
severe operational risk.

Alert before reaching critical utilization.

------------------------------------------------------------------------

# Part 29 --- Write Error

## 34. Safety Behavior

Redis persistence configurations may influence behavior when background
saves fail.

Validate exact settings such as write-stop behavior for the deployed
version/product.

Never disable a safety mechanism merely to clear an alert without
understanding the durability impact.

------------------------------------------------------------------------

# Part 30 --- Restart Recovery

## 35. Required Test

Persistence is not proven until restart recovery is tested.

Validate:

``` text
data before restart
successful persistence
controlled restart
load/recovery
data after restart
recovery time
```

------------------------------------------------------------------------

# Part 31 --- Crash vs. Clean Restart

## 36. Different Tests

A clean shutdown may persist state differently from an abrupt
process/host failure.

Test the failure modes relevant to the production design.

------------------------------------------------------------------------

# Part 32 --- Corruption

## 37. Recovery Planning

Persistence files can become unusable due to:

``` text
storage corruption
partial writes
filesystem failure
operator error
```

The recovery plan must include independent backups where required.

------------------------------------------------------------------------

# Part 33 --- Persistence Is Not Backup

## 38. Example

Application accidentally executes:

``` redis
DEL important:key
```

Redis can persist that deletion perfectly.

Persistence has preserved the wrong state.

A historical backup may be needed to recover the prior value.

------------------------------------------------------------------------

# Part 34 --- Replication Is Not Backup

## 39. Logical Error

If deletion replicates:

``` text
primary -> replica
```

both may contain the same logical mistake.

Replication improves availability, not historical recovery.

------------------------------------------------------------------------

# Part 35 --- Backup Independence

## 40. Desired Properties

Depending on business requirements, backups may need:

``` text
independent retention
separate storage
access controls
encryption
restore validation
off-site/cross-region protection
```

Chapter 36 will cover backup/restore engineering in depth.

------------------------------------------------------------------------

# Part 36 --- Persistence and Kubernetes

## 41. Container Storage

For Redis deployed in containers, understand:

``` text
persistent volume
ephemeral filesystem
pod replacement
node replacement
storage class
IOPS
throughput
latency
```

Persistence files on ephemeral storage do not provide host-independent
durability.

------------------------------------------------------------------------

# Part 37 --- Cloud Storage

## 42. Performance

Cloud disks have:

``` text
IOPS limits
throughput limits
latency characteristics
burst behavior
capacity scaling rules
```

Persistence design must fit the actual storage tier.

------------------------------------------------------------------------

# Part 38 --- Memory vs. Disk

## 43. Different Bottlenecks

Redis command processing may be memory/CPU efficient while persistence
becomes storage-bound.

Monitor both planes.

------------------------------------------------------------------------

# Part 39 --- Write-Heavy Workloads

## 44. COW Risk

High write rates during RDB/AOF rewrite can increase copy-on-write
memory and persistence overhead.

Benchmark representative write workloads.

------------------------------------------------------------------------

# Part 40 --- Large Dataset

## 45. Recovery Time

Larger persistence files can increase:

``` text
restart load time
storage reads
recovery duration
```

Measure actual RTO rather than estimating from file size alone.

------------------------------------------------------------------------

# Part 41 --- Compression

## 46. RDB

Redis supports configuration affecting RDB encoding/compression
behavior.

Do not change it without measuring:

``` text
CPU
file size
recovery
```

Validate version-specific behavior.

------------------------------------------------------------------------

# Part 42 --- Checksums

## 47. Integrity

Persistence formats may support integrity checks.

Keep integrity protections enabled unless there is a documented,
validated reason otherwise.

------------------------------------------------------------------------

# Part 43 --- Persistence Observability

## 48. `INFO persistence`

A primary discovery command is:

``` redis
INFO persistence
```

Fields vary by Redis version.

Review the deployed version's output.

------------------------------------------------------------------------

# Part 44 --- RDB Metrics

## 49. Watch

Typical concepts include:

``` text
last save time
save in progress
last background save status
last save duration
changes since last save
fork/COW metrics
```

------------------------------------------------------------------------

# Part 45 --- AOF Metrics

## 50. Watch

Typical concepts include:

``` text
AOF enabled
rewrite in progress
last rewrite status
AOF size
base size
fsync status/delay
```

Exact field names vary by version.

------------------------------------------------------------------------

# Part 46 --- Host Metrics

## 51. Correlate

Monitor:

``` text
disk utilization
disk latency
IOPS
throughput
filesystem capacity
CPU
memory
page faults
```

------------------------------------------------------------------------

# Part 47 --- Alerting

## 52. Examples

Alert on:

``` text
persistence failure
AOF rewrite failure
RDB save failure
disk utilization high
disk latency high
unexpected persistence disabled
recovery duration above objective
```

------------------------------------------------------------------------

# Part 48 --- Storage Capacity Model

## 53. Inputs

Record:

``` text
dataset size
daily write volume
RDB size
AOF size
AOF growth rate
rewrite peak space
backup staging
filesystem headroom
```

------------------------------------------------------------------------

# Part 49 --- Headroom Formula

## 54. Conceptual

Do not use:

``` text
disk capacity = current AOF size
```

Instead account for:

``` text
current persistence
+
rewrite/snapshot temporary space
+
growth
+
other files
+
safety margin
```

------------------------------------------------------------------------

# Part 50 --- Recovery Validation

## 55. Evidence

For each production persistence policy, record:

``` text
test date
dataset size
persistence mode
failure type
recovery point
recovery time
data validation result
```

------------------------------------------------------------------------

# Part 51 --- Hands-On Lab

## 56. Safety

Use only a disposable Redis instance.

Do not change production persistence configuration for this lab.

Do not simulate disk-full conditions on shared infrastructure.

------------------------------------------------------------------------

# Part 52 --- Discover Configuration

## 57. Commands

Where permitted:

``` redis
CONFIG GET save
CONFIG GET appendonly
CONFIG GET appendfsync
```

Also:

``` redis
INFO persistence
```

Record the baseline.

------------------------------------------------------------------------

# Part 53 --- Create Test Data

## 58. Commands

``` redis
SET tutorial:chapter34:key1 value1
SET tutorial:chapter34:key2 value2
INCR tutorial:chapter34:counter
```

Verify:

``` redis
MGET tutorial:chapter34:key1 tutorial:chapter34:key2
GET tutorial:chapter34:counter
```

------------------------------------------------------------------------

# Part 54 --- RDB Lab

## 59. Disposable Instance

If RDB is enabled and appropriate for the lab:

``` redis
BGSAVE
```

Then inspect:

``` redis
INFO persistence
```

Wait for completion.

Record:

``` text
last save status
duration
changes since save
```

------------------------------------------------------------------------

# Part 55 --- RDB Restart Test

## 60. Procedure

1.  Write known data.
2.  Complete a snapshot.
3.  Record values.
4.  Restart the disposable Redis instance.
5.  Reconnect.
6.  Validate the values.
7.  Measure recovery time.

------------------------------------------------------------------------

# Part 56 --- Snapshot Loss Window Lab

## 61. Concept

On a disposable snapshot-only instance:

1.  complete snapshot;
2.  write additional test keys;
3.  simulate an abrupt failure using your lab platform;
4.  restart;
5.  compare recovered state.

The exact outcome depends on configuration and shutdown/failure
mechanism.

Never perform destructive crash testing on shared systems.

------------------------------------------------------------------------

# Part 57 --- AOF Lab

## 62. Separate Disposable Instance

Use a disposable Redis configured for AOF according to the installed
Redis version.

Discover:

``` redis
CONFIG GET appendonly
CONFIG GET appendfsync
INFO persistence
```

Do not modify a production database.

------------------------------------------------------------------------

# Part 58 --- AOF Writes

## 63. Generate

``` bash
redis-cli SET tutorial:chapter34:aof:key value
redis-cli INCR tutorial:chapter34:aof:counter
```

Inspect persistence metrics.

------------------------------------------------------------------------

# Part 59 --- AOF Restart Test

## 64. Procedure

1.  write known values;
2.  confirm AOF persistence health;
3.  restart disposable Redis;
4.  validate values;
5.  measure restart/recovery time.

------------------------------------------------------------------------

# Part 60 --- AOF Rewrite Lab

## 65. Disposable Only

Generate repeated updates:

``` bash
for i in $(seq 1 10000); do
  redis-cli SET tutorial:chapter34:rewrite "$i" >/dev/null
done
```

Inspect AOF size.

If safe in the lab:

``` redis
BGREWRITEAOF
```

Observe:

``` text
rewrite status
AOF size before
AOF size after
duration
CPU
disk
memory
```

------------------------------------------------------------------------

# Part 61 --- Python Write Generator

## 66. Script

``` python
import os
import time
import redis

r = redis.Redis(
    host=os.getenv(
        "REDIS_HOST",
        "localhost",
    ),
    port=int(
        os.getenv(
            "REDIS_PORT",
            "6379",
        )
    ),
    password=(
        os.getenv("REDIS_PASSWORD")
        or None
    ),
    decode_responses=True,
)

for i in range(100000):
    r.set(
        f"tutorial:chapter34:"
        f"write:{i % 1000}",
        str(i),
    )

    if i % 10000 == 0:
        print(
            "writes:",
            i,
        )
```

Use only on an isolated test instance.

------------------------------------------------------------------------

# Part 62 --- Observe Persistence During Writes

## 67. Monitor

In another terminal:

``` bash
redis-cli INFO persistence
```

Also monitor the host/container:

``` text
memory
CPU
disk latency
IOPS
throughput
filesystem utilization
```

------------------------------------------------------------------------

# Part 63 --- COW Lab

## 68. Goal

During a write-heavy workload, trigger an allowed background persistence
operation in a disposable environment.

Compare:

``` text
memory before
memory during
memory after
latency before/during
COW/fork metrics
```

This demonstrates why persistence needs memory headroom.

------------------------------------------------------------------------

# Part 64 --- Storage Pressure Lab

## 69. Safe Simulation

Do not fill the filesystem.

Instead use:

``` text
small disposable volume
I/O throttling
test storage tier
```

to observe persistence sensitivity safely.

------------------------------------------------------------------------

# Part 65 --- Failure Injection

## 70. Failure 1 --- RDB Save Failure

In an isolated lab, simulate an unavailable/unwritable persistence
destination using a safe lab mechanism.

Observe:

``` text
persistence status
logs
application behavior
alerts
```

------------------------------------------------------------------------

## 71. Failure 2 --- Slow Storage

Throttle test storage.

Observe:

``` text
persistence duration
command latency
AOF behavior
```

------------------------------------------------------------------------

## 72. Failure 3 --- High Write Rate During Snapshot

Run the write generator while snapshotting.

Observe:

``` text
COW
memory
latency
snapshot duration
```

------------------------------------------------------------------------

## 73. Failure 4 --- High Write Rate During AOF Rewrite

Run writes while rewriting AOF.

Observe persistence and resource behavior.

------------------------------------------------------------------------

## 74. Failure 5 --- Restart With RDB

Validate expected recovery point and RTO.

------------------------------------------------------------------------

## 75. Failure 6 --- Restart With AOF

Validate expected recovery point and RTO.

------------------------------------------------------------------------

## 76. Failure 7 --- Persistence Disabled

On a disposable instance only, demonstrate that memory-only data does
not provide durable restart recovery.

Do not disable persistence on production to perform this test.

------------------------------------------------------------------------

## 77. Failure 8 --- Disk Headroom Too Small

Model, rather than dangerously fill, a filesystem where rewrite requires
more temporary space than available.

Document the failure risk.

------------------------------------------------------------------------

## 78. Failure 9 --- Logical Deletion

Delete a lab key and allow persistence to capture the deletion.

Demonstrate why persistence does not replace historical backup.

------------------------------------------------------------------------

## 79. Failure 10 --- Recovery Exceeds RTO

Create a sufficiently large disposable dataset to measure restart time.

Compare observed recovery with the target RTO.

------------------------------------------------------------------------

# Part 66 --- Troubleshooting

## 80. RDB Save Failing

Check:

``` text
INFO persistence
Redis logs
filesystem free space
permissions
storage health
I/O errors
memory/fork headroom
```

------------------------------------------------------------------------

## 81. AOF Rewrite Failing

Check:

``` text
filesystem capacity
temporary space
permissions
storage errors
memory headroom
existing persistence operation
```

------------------------------------------------------------------------

## 82. Write Latency During Persistence

Correlate:

``` text
persistence operation
fork
COW
disk latency
fsync
CPU
memory pressure
```

------------------------------------------------------------------------

## 83. Redis Does Not Recover Expected Data

Check:

``` text
persistence mode
last successful persistence
shutdown/failure type
persistence files
startup logs
recovery source
```

Do not guess that the newest writes were durable.

------------------------------------------------------------------------

## 84. Disk Usage Growing

Check:

``` text
AOF growth
rewrite status
RDB files
old persistence artifacts
logs
backups
```

Do not delete persistence files manually without an approved recovery
procedure.

------------------------------------------------------------------------

## 85. Memory Spike During Snapshot

Check:

``` text
write rate
COW
dataset size
fork activity
memory headroom
```

------------------------------------------------------------------------

## 86. Restart Too Slow

Check:

``` text
persistence file size
storage read throughput
CPU
dataset size
persistence format
startup logs
```

Measure actual bottleneck.

------------------------------------------------------------------------

## 87. Persistence Unexpectedly Disabled

Treat as a durability configuration incident if persistence is required.

Determine:

``` text
who/what changed configuration
when
which writes occurred
whether backup/replica protection exists
```

------------------------------------------------------------------------

# Part 67 --- Production Runbooks

## 88. Runbook --- RDB Save Failure

``` text
1. Confirm persistence status.
2. Capture last successful save.
3. Check filesystem capacity.
4. Check storage errors.
5. Check permissions.
6. Check memory/fork headroom.
7. Avoid unnecessary persistence triggers.
8. Restore safe storage condition.
9. Validate successful snapshot.
10. Review durability exposure window.
```

------------------------------------------------------------------------

## 89. Runbook --- AOF Persistence Failure

``` text
1. Confirm AOF state.
2. Check last fsync/rewrite status.
3. Check disk capacity/latency.
4. Check Redis logs.
5. Protect available durable state.
6. Avoid unsafe manual file edits.
7. Restore storage health.
8. Validate AOF operation.
9. Test recovery if required.
10. Review RPO exposure.
```

------------------------------------------------------------------------

## 90. Runbook --- Disk Capacity Critical

``` text
1. Measure filesystem utilization.
2. Identify Redis persistence files.
3. Check active rewrite/snapshot.
4. Estimate temporary-space need.
5. Stop unrelated disk growth.
6. Expand storage if supported.
7. Do not delete active persistence blindly.
8. Verify persistence resumes.
9. Confirm alert headroom.
10. Update capacity forecast.
```

------------------------------------------------------------------------

## 91. Runbook --- Persistence-Induced Latency

``` text
1. Confirm latency window.
2. Correlate persistence operation.
3. Check fork/COW.
4. Check disk latency/IOPS.
5. Check write rate.
6. Check memory pressure.
7. Protect application SLO.
8. Correct storage/headroom issue.
9. Re-test under representative load.
10. Update persistence design.
```

------------------------------------------------------------------------

## 92. Runbook --- Restart Recovery Validation

``` text
1. Identify persistence mode.
2. Identify expected recovery point.
3. Capture pre-restart validation keys.
4. Restart through approved procedure.
5. Monitor load/startup.
6. Measure recovery time.
7. Validate expected keys/data.
8. Compare observed RPO/RTO.
9. Investigate discrepancies.
10. Record evidence.
```

------------------------------------------------------------------------

# Part 68 --- Persistence Design Template

## 93. Fields

``` text
Database:
Owner:
Dataset size:
Peak memory:
Write rate:
Persistence mode:
RDB schedule:
AOF enabled:
AOF fsync policy:
RPO:
RTO:
Last tested recovery:
Observed recovery time:
RDB size:
AOF size:
AOF growth/day:
Rewrite peak disk:
COW peak memory:
Storage type:
Storage capacity:
Storage IOPS:
Storage throughput:
Disk alert threshold:
Backup policy:
HA topology:
Runbook:
```

------------------------------------------------------------------------

# Part 69 --- RPO Decision

## 94. Questions

Ask:

``` text
Can this data be regenerated?
Is Redis authoritative?
How much recent data can be lost?
Does a source database exist?
How long would rebuild take?
```

A disposable cache may need very different persistence from an
authoritative operational dataset.

------------------------------------------------------------------------

# Part 70 --- Cache Use Case

## 95. Example

If Redis contains only rebuildable cache data:

``` text
persistence may be optional
```

depending on cold-start and source-protection requirements.

But losing the cache may still cause a source-system storm.

Durability decisions must include recovery load.

------------------------------------------------------------------------

# Part 71 --- Authoritative Data

## 96. Higher Requirement

If Redis contains data that cannot be reconstructed elsewhere,
durability, backup, replication, and restore requirements become much
stronger.

Document the source of truth explicitly.

------------------------------------------------------------------------

# Part 72 --- Production Acceptance Checklist

## 97. Persistence Engineering

-   [ ] Redis data classification documented.
-   [ ] Source of truth documented.
-   [ ] Persistence mode documented.
-   [ ] RPO defined.
-   [ ] RTO defined.
-   [ ] RDB behavior understood.
-   [ ] AOF behavior understood.
-   [ ] Fsync policy documented where applicable.
-   [ ] Persistence metrics monitored.
-   [ ] Last successful save monitored.
-   [ ] Rewrite failures alerted.
-   [ ] Disk utilization alerted.
-   [ ] Disk latency monitored.
-   [ ] Storage IOPS/throughput understood.
-   [ ] Fork/COW behavior measured.
-   [ ] Memory headroom validated.
-   [ ] Rewrite disk headroom validated.
-   [ ] Restart recovery tested.
-   [ ] Abrupt-failure behavior tested where required.
-   [ ] Recovery point validated.
-   [ ] Recovery time measured.
-   [ ] Persistence distinguished from backup.
-   [ ] Backup policy documented.
-   [ ] Logical deletion recovery understood.
-   [ ] Production runbooks validated.

------------------------------------------------------------------------

# Knowledge Validation

## 98. Questions

You should be able to answer:

1.  What is Redis persistence?
2.  How is persistence different from replication?
3.  How is persistence different from HA?
4.  How is persistence different from backup?
5.  What is RDB?
6.  What is the RDB durability window?
7.  What does `BGSAVE` do?
8.  Why can fork affect latency?
9.  What is copy-on-write?
10. Why does COW require memory headroom?
11. What is AOF?
12. What is an AOF fsync policy?
13. What is the tradeoff of `always`?
14. What is the tradeoff of `everysec`?
15. Why is `no` a different durability choice?
16. What is RPO?
17. What is RTO?
18. Why does AOF need rewriting?
19. Why does rewrite require disk headroom?
20. Why can slow storage affect Redis latency?
21. What does `INFO persistence` provide?
22. Which host metrics should be correlated?
23. Why must restart recovery be tested?
24. Why is a clean restart different from a crash test?
25. Why does persistence not protect against logical deletion?
26. Why does replication not replace backup?
27. Why can container ephemeral storage undermine persistence?
28. Why should recovery time be measured?
29. Why can a cache still benefit from persistence?
30. What must pass before Redis persistence is production-ready?

------------------------------------------------------------------------

# Hands-On Acceptance Checklist

## 99. Lab Completion

-   [ ] Inspected persistence configuration.
-   [ ] Captured `INFO persistence`.
-   [ ] Created known lab data.
-   [ ] Ran RDB test where applicable.
-   [ ] Validated RDB restart.
-   [ ] Reviewed snapshot loss window.
-   [ ] Ran AOF test where applicable.
-   [ ] Validated AOF restart.
-   [ ] Generated repeated writes.
-   [ ] Observed AOF growth.
-   [ ] Tested AOF rewrite.
-   [ ] Monitored storage.
-   [ ] Monitored memory.
-   [ ] Observed persistence under write load.
-   [ ] Reviewed COW behavior.
-   [ ] Simulated safe storage pressure.
-   [ ] Tested persistence failure behavior.
-   [ ] Tested restart recovery.
-   [ ] Demonstrated logical deletion persistence.
-   [ ] Measured RTO.
-   [ ] Completed ten failure scenarios.
-   [ ] Completed troubleshooting.
-   [ ] Reviewed five production runbooks.
-   [ ] Completed persistence design template.
-   [ ] Completed production acceptance checklist.

------------------------------------------------------------------------

# 100. Lab Cleanup

Discover only Chapter 34 data keys:

``` bash
redis-cli --scan --pattern 'tutorial:chapter34:*'
```

Review all matches.

Delete confirmed lab keys in bounded batches:

``` redis
UNLINK <confirmed-key>
```

Do not manually delete persistence files merely as lab cleanup.

Do not use:

``` redis
KEYS tutorial:chapter34:*
FLUSHDB
FLUSHALL
```

against a shared or production database.

Restore disposable lab configuration or destroy the disposable instance
after completing persistence tests.

------------------------------------------------------------------------

# 101. Key Takeaways

1.  Redis persistence provides restart durability; it is not the same as
    HA or backup.
2.  RDB captures point-in-time snapshots.
3.  Snapshot frequency determines the potential RDB-only recovery-point
    gap.
4.  AOF persists write operations in an append-oriented form.
5.  AOF durability depends heavily on fsync policy.
6.  Stronger fsync durability can increase sensitivity to storage
    latency.
7.  Define RPO and RTO before selecting persistence settings.
8.  Background persistence can introduce fork and copy-on-write
    pressure.
9.  Write-heavy workloads can increase COW memory during persistence.
10. AOF rewrite controls historical log growth but requires resources
    and temporary storage.
11. Disk capacity must include rewrite/snapshot headroom, not only
    steady-state files.
12. Storage latency, IOPS, and throughput are Redis durability
    dependencies.
13. `INFO persistence` is a core operational view.
14. Redis persistence health must be correlated with host/storage
    metrics.
15. Persistence is not proven until restart recovery is tested.
16. Clean restart and abrupt failure are different recovery scenarios.
17. Persistence can faithfully preserve an accidental deletion.
18. Replication can faithfully copy the same logical mistake.
19. Historical backup is therefore a separate requirement.
20. Containerized Redis needs genuinely persistent storage when restart
    durability is required.
21. Large datasets can increase restart/recovery time.
22. Cache workloads may still need persistence when cold-start
    rebuilding would overload source systems.
23. Authoritative Redis data requires stronger durability and
    data-protection engineering.
24. Production readiness requires measured RPO, RTO, COW, disk headroom,
    and recovery evidence.
25. Persistence, HA, backup, and disaster recovery must be designed as
    separate but coordinated layers.

------------------------------------------------------------------------

# 102. References

Validate persistence behavior against the exact Redis, Redis Enterprise,
operating-system, storage, and client versions deployed.

Recommended official Redis documentation areas:

-   Redis persistence
-   RDB snapshots
-   AOF
-   AOF rewrite
-   `BGSAVE`
-   `BGREWRITEAOF`
-   `INFO persistence`
-   `CONFIG GET`
-   Redis latency monitoring
-   Redis memory administration
-   Redis Enterprise persistence
-   Redis Enterprise database configuration
-   Redis Enterprise monitoring
-   Redis Enterprise backup and restore

------------------------------------------------------------------------

# Next Chapter

**Chapter 35 --- Redis Replication, High Availability & Failover
Engineering**

Chapter 35 will cover:

-   primary/replica architecture
-   replication flow
-   asynchronous replication implications
-   replication lag
-   partial/full synchronization
-   failover
-   data-loss windows
-   split-brain considerations
-   replica capacity
-   read scaling caveats
-   topology health
-   planned failover
-   unplanned failure
-   recovery testing
-   failure injection
-   observability
-   troubleshooting
-   production runbooks
-   acceptance validation
