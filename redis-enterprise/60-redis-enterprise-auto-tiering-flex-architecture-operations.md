# Chapter 60 --- Redis Enterprise Auto Tiering / Flex Architecture & Operations

**Status:** Canonical\
**Track:** Redis Enterprise / Redis Software Production Engineering\
**Part:** Part 10 --- Migration, Data Services & Advanced Capabilities\
**Level:** Advanced → Production Infrastructure & Capacity Engineering\
**Audience:** SREs, DBREs, Platform Engineers, Redis Administrators,
Cloud Engineers, Performance Engineers, Application Architects\
**Lab type:** RAM/flash tiering architecture, working-set sizing, flash
qualification, latency benchmarking, capacity modeling, HA/failure
testing, scaling, observability, troubleshooting, runbooks, and
production acceptance

------------------------------------------------------------------------

# 1. Objective

Redis is widely associated with memory-speed access.

For very large datasets, keeping the entire dataset in DRAM can become
expensive.

Redis Enterprise Auto Tiering, historically associated with Redis on
Flash concepts and referred to in some product/service contexts as Flex,
is designed to allow a larger portion of data to reside on flash storage
while keeping performance-sensitive structures and frequently accessed
data in memory according to the product architecture.

Conceptually:

``` text
application
   |
Redis Enterprise
   |
   +-- DRAM
   |    |
   |    +-- hot / frequently accessed data
   |    +-- metadata / structures required by architecture
   |
   +-- flash
        |
        +-- colder value data
        +-- larger dataset capacity
```

The engineering goal is not:

``` text
replace RAM with cheap disk
```

The goal is:

``` text
use RAM and flash deliberately
while preserving the application's required latency,
throughput, resilience, and recovery behavior.
```

By the end of this chapter, you should be able to:

-   explain Auto Tiering architecture;
-   distinguish logical dataset size from RAM requirement;
-   define the working set;
-   identify suitable and unsuitable workloads;
-   qualify flash devices;
-   build RAM/flash capacity models;
-   benchmark hot and cold access;
-   measure latency distributions;
-   test changing working sets;
-   understand persistence interactions;
-   plan HA and N-1 capacity;
-   test flash/device failure behavior;
-   scale and rebalance safely;
-   monitor tiering health;
-   troubleshoot performance regressions;
-   define production runbooks and acceptance gates.

------------------------------------------------------------------------

# 2. Core Production Principle

Auto Tiering is a capacity/performance tradeoff.

Do not evaluate it only by:

``` text
How much DRAM can we save?
```

Evaluate:

``` text
cost
+
P99 latency
+
throughput
+
working-set behavior
+
flash endurance/performance
+
HA
+
recovery
```

------------------------------------------------------------------------

# Part 1 --- Why Tiering Exists

## 3. DRAM Economics

Suppose a dataset is:

``` text
2 TB
```

Keeping all data in DRAM may require substantial infrastructure.

If only a smaller fraction is frequently accessed, tiering can
potentially improve the cost/capacity profile.

------------------------------------------------------------------------

# Part 2 --- Hot and Cold Data

## 4. Concept

Example:

``` text
100 GB frequently accessed
900 GB infrequently accessed
```

A workload with a stable hot working set may be a stronger candidate
than a workload that uniformly accesses every key.

------------------------------------------------------------------------

# Part 3 --- Working Set

## 5. Definition

The working set is the portion of data actively accessed over the
relevant time window.

Examples:

``` text
last 5 minutes
last hour
business day
batch window
```

Working-set definition must match application behavior.

------------------------------------------------------------------------

# Part 4 --- Working-Set Ratio

## 6. Formula

``` text
working_set_ratio
=
active_data
/
total_dataset
```

Example:

``` text
100 GB / 1 TB
=
10%
```

This is a workload characteristic, not automatically the correct RAM
percentage.

------------------------------------------------------------------------

# Part 5 --- Access Distribution

## 7. Measure

Common patterns:

``` text
80/20
95/5
uniform
time-based hotness
tenant skew
batch-driven scans
```

Tiering benefits depend heavily on access distribution.

------------------------------------------------------------------------

# Part 6 --- Suitable Workload

## 8. Candidate

A workload may be suitable when:

``` text
dataset is large
working set is meaningfully smaller
latency SLO tolerates tiering behavior
flash devices meet requirements
cost benefit is meaningful
```

------------------------------------------------------------------------

# Part 7 --- Less Suitable Workload

## 9. Caution

Potentially poor candidates include workloads with:

``` text
nearly uniform access to all data
extreme ultra-low-latency requirements for every request
large unpredictable scans
insufficient flash performance
rapidly shifting working set
```

Qualification is required.

------------------------------------------------------------------------

# Part 8 --- Architecture Boundary

## 10. Not Generic Swap

Auto Tiering is not the same as operating-system swap.

Do not design Redis memory pressure around enabling OS swap.

Use Redis Enterprise's supported architecture and vendor sizing
guidance.

------------------------------------------------------------------------

# Part 9 --- Flash Device

## 11. Critical Dependency

Flash becomes part of the database performance path.

Therefore device characteristics matter:

``` text
latency
IOPS
throughput
endurance
failure behavior
```

------------------------------------------------------------------------

# Part 10 --- Storage Class

## 12. Validate

In cloud or virtualized environments, validate the exact storage
class/device type supported and recommended for the Redis Enterprise
version and deployment model.

Do not assume any SSD is equivalent.

------------------------------------------------------------------------

# Part 11 --- Latency

## 13. Device

Measure:

``` text
read latency
write latency
P95
P99
```

under representative queue depth.

Average device latency is insufficient.

------------------------------------------------------------------------

# Part 12 --- IOPS

## 14. Requirement

Estimate expected flash access rate.

Compare:

``` text
required IOPS
vs
sustained device IOPS
```

with headroom.

------------------------------------------------------------------------

# Part 13 --- Throughput

## 15. Requirement

For larger values, storage throughput may matter in addition to IOPS.

Measure both.

------------------------------------------------------------------------

# Part 14 --- Endurance

## 16. Writes

Flash has finite write endurance characteristics.

High-write workloads require an endurance review.

Use provider/device specifications and Redis guidance.

------------------------------------------------------------------------

# Part 15 --- Local vs Network Storage

## 17. Architecture

Latency and failure characteristics differ between:

``` text
local NVMe
network-attached block storage
cloud managed disks
```

Use only supported configurations.

------------------------------------------------------------------------

# Part 16 --- Dataset Model

## 18. Record

``` text
logical dataset size
key count
average value
P95 value
P99 value
maximum value
working-set size
read/write ratio
TTL distribution
growth/day
```

------------------------------------------------------------------------

# Part 17 --- RAM Model

## 19. More Than Hot Values

Do not assume:

``` text
RAM = hot data only
```

The product architecture may require memory for:

``` text
keys
metadata
data structures
indexes
buffers
overhead
hot values
```

Use exact Redis Enterprise sizing guidance.

------------------------------------------------------------------------

# Part 18 --- Flash Model

## 20. More Than Cold Values

Flash capacity planning should include supported product overhead and
operational headroom.

Do not size flash to exactly equal raw source bytes.

------------------------------------------------------------------------

# Part 19 --- Replication

## 21. Physical Capacity

HA replicas affect:

``` text
RAM
flash
network
recovery
```

Include redundancy in the physical capacity model.

------------------------------------------------------------------------

# Part 20 --- Persistence

## 22. Separate Concept

Auto Tiering and persistence are different concerns.

Tiering answers:

``` text
where active database data resides
```

Persistence answers:

``` text
how durable/recoverable state is maintained
```

Do not confuse flash tiering with backup.

------------------------------------------------------------------------

# Part 21 --- Backup

## 23. Still Required

If the data requires backup/recovery, Auto Tiering does not eliminate
that requirement.

Validate backup/restore for the exact deployment.

------------------------------------------------------------------------

# Part 22 --- Lab Safety

## 24. Environment

Auto Tiering labs should be performed only in:

``` text
approved nonproduction Redis Enterprise environment
```

with supported flash resources.

Do not attempt to emulate production tiering by manipulating OS swap.

------------------------------------------------------------------------

# Part 23 --- Baseline

## 25. All-Memory Comparison

Where practical, establish a comparable baseline:

``` text
same dataset
same workload
same application
```

without tiering.

Record:

``` text
P50
P95
P99
throughput
CPU
memory
```

------------------------------------------------------------------------

# Part 24 --- Tiered Baseline

## 26. Compare

Enable/configure tiering according to supported procedures.

Run the same workload.

Compare:

``` text
latency
throughput
CPU
flash I/O
RAM
```

------------------------------------------------------------------------

# Part 25 --- Hot-Key Test

## 27. Scenario

Create a synthetic workload where:

``` text
10% keys receive 90% traffic
```

Measure steady-state P99.

------------------------------------------------------------------------

# Part 26 --- Uniform Test

## 28. Scenario

Distribute reads uniformly across the entire synthetic dataset.

Compare against hot-key distribution.

This can expose the cost of a large active working set.

------------------------------------------------------------------------

# Part 27 --- Working-Set Shift

## 29. Scenario

Phase 1:

``` text
keys 1-100k hot
```

Phase 2:

``` text
keys 900k-1M hot
```

Observe latency while the active set changes.

------------------------------------------------------------------------

# Part 28 --- Cold Read

## 30. Measure

Measure access to data that has not been recently used.

Record:

``` text
P50
P95
P99
device I/O
```

------------------------------------------------------------------------

# Part 29 --- Warm Read

## 31. Measure

Repeatedly access the same subset.

Compare latency after the workload stabilizes.

------------------------------------------------------------------------

# Part 30 --- Value Size

## 32. Test

Compare:

``` text
1 KB
10 KB
100 KB
```

or application-representative value sizes.

Larger values can increase flash/network throughput requirements.

------------------------------------------------------------------------

# Part 31 --- Read/Write Mix

## 33. Test

Example:

``` text
100% reads
90/10 read/write
50/50
write-heavy
```

Use the application's real mix.

------------------------------------------------------------------------

# Part 32 --- TTL Workload

## 34. Test

Expiration can create churn.

Use representative TTL distributions.

Measure:

``` text
CPU
flash writes
memory
latency
```

------------------------------------------------------------------------

# Part 33 --- Batch Scan Risk

## 35. Example

A job touching most keys can temporarily expand the working set.

This can change tiering performance dramatically.

Include known batch jobs in qualification.

------------------------------------------------------------------------

# Part 34 --- Analytics / Scan Workloads

## 36. Caution

Redis should not be treated as a data warehouse merely because flash
increases capacity.

Large scans can disrupt latency-sensitive workloads.

------------------------------------------------------------------------

# Part 35 --- Multi-Tenant Skew

## 37. Test

Tenant A:

``` text
small/hot
```

Tenant B:

``` text
large/cold
```

Tenant C:

``` text
large/batch-heavy
```

Measure cross-tenant effects.

------------------------------------------------------------------------

# Part 36 --- Hot Tenant

## 38. Scenario

One tenant suddenly accesses a much larger share of its dataset.

Observe:

``` text
P99
flash reads
CPU
other tenant latency
```

------------------------------------------------------------------------

# Part 37 --- Capacity Formula

## 39. Concept

A production sizing worksheet should include:

``` text
logical data
RAM requirement
flash requirement
replicas
growth
maintenance/rebalance overhead
failure headroom
```

Use vendor-supported sizing methods for final values.

------------------------------------------------------------------------

# Part 38 --- Growth Forecast

## 40. Formula

``` text
future_data
=
current_data
+
(net_growth_per_day × days)
```

Forecast both:

``` text
RAM pressure
flash capacity
```

------------------------------------------------------------------------

# Part 39 --- Working-Set Growth

## 41. Separate

Total data may grow 10% while working set grows 50%.

Track working-set growth independently.

------------------------------------------------------------------------

# Part 40 --- Capacity Trigger

## 42. Define

Review/scale before:

``` text
RAM headroom too low
flash headroom too low
P99 degrades
device utilization saturates
N-1 fails
forecasted exhaustion
```

------------------------------------------------------------------------

# Part 41 --- Flash Utilization

## 43. Monitor

Track relevant supported metrics for:

``` text
used capacity
read IOPS
write IOPS
throughput
latency
queueing
errors
```

using infrastructure and Redis Enterprise telemetry.

------------------------------------------------------------------------

# Part 42 --- Device Saturation

## 44. Symptoms

Possible signs:

``` text
P99 rises
device latency rises
queue depth rises
throughput plateaus
CPU may not be saturated
```

Do not assume Redis CPU is always the bottleneck.

------------------------------------------------------------------------

# Part 43 --- RAM Pressure

## 45. Symptoms

Track Redis Enterprise memory metrics and product-specific tiering
indicators.

Avoid relying on host free-memory alone.

------------------------------------------------------------------------

# Part 44 --- CPU

## 46. Correlate

Tiering can change CPU behavior due to:

``` text
data movement
serialization
index/data-structure work
I/O processing
```

Measure per-node CPU.

------------------------------------------------------------------------

# Part 45 --- Network

## 47. Include

Track:

``` text
client traffic
replication
backup
rebalance
```

Large datasets can make recovery/rebalancing network-intensive.

------------------------------------------------------------------------

# Part 46 --- Shard Placement

## 48. Balance

Uneven shard/data placement can create:

``` text
RAM imbalance
flash imbalance
I/O hot spots
```

Use supported placement/rebalancing procedures.

------------------------------------------------------------------------

# Part 47 --- Rebalancing

## 49. Operational Load

Moving large tiered datasets can consume:

``` text
network
flash I/O
CPU
```

Qualify rebalance impact.

------------------------------------------------------------------------

# Part 48 --- Scale Out

## 50. Plan

Adding nodes can provide:

``` text
RAM
flash
CPU
network
```

but data movement is required.

Plan:

``` text
change window
headroom
rebalance duration
application SLO
```

------------------------------------------------------------------------

# Part 49 --- Scale Up

## 51. Plan

Changing node size/device capacity may require infrastructure operations
and data movement.

Use supported Redis Enterprise procedures.

------------------------------------------------------------------------

# Part 50 --- Scale Decision

## 52. Ask

Is the bottleneck:

``` text
RAM
flash capacity
flash IOPS
flash latency
CPU
network
shard skew
```

Scale the constrained resource rather than guessing.

------------------------------------------------------------------------

# Part 51 --- N-1 Capacity

## 53. Requirement

For HA:

``` text
remaining capacity after approved failure
```

must meet the service's degraded-state requirements.

Include both RAM and flash.

------------------------------------------------------------------------

# Part 52 --- N-1 Test

## 54. Nonproduction

Run representative peak workload.

Remove approved capacity according to test procedure.

Measure:

``` text
P99
errors
RAM
flash I/O
CPU
recovery
```

------------------------------------------------------------------------

# Part 53 --- Node Failure

## 55. Observe

A node loss can trigger:

``` text
failover
traffic redistribution
recovery
data movement
```

Tiered workloads must be tested through the full event.

------------------------------------------------------------------------

# Part 54 --- Flash Device Failure

## 56. High Stakes

Use supported failure-injection procedures only.

Validate Redis Enterprise's documented behavior for the exact
architecture.

Do not manually corrupt or detach production devices.

------------------------------------------------------------------------

# Part 55 --- Device Degradation

## 57. Scenario

A device can become slow before it fails.

Monitor latency and error indicators.

Slow storage can cause application symptoms without an obvious hard
failure.

------------------------------------------------------------------------

# Part 56 --- Recovery

## 58. Measure

After failure:

``` text
time to restore redundancy
P99 during recovery
flash/network utilization
application errors
```

------------------------------------------------------------------------

# Part 57 --- Maintenance

## 59. Capacity

Before node maintenance, confirm remaining nodes have enough:

``` text
RAM
flash
CPU
network
```

for the expected temporary topology.

------------------------------------------------------------------------

# Part 58 --- Upgrade

## 60. Qualification

Before Redis Enterprise upgrades:

``` text
review tiering-specific release notes
validate device support
run regression tests
validate failover
validate recovery
```

------------------------------------------------------------------------

# Part 59 --- Backup Window

## 61. Interaction

Backups may consume:

``` text
CPU
network
storage I/O
```

Measure impact on tiered query latency.

------------------------------------------------------------------------

# Part 60 --- Persistence Window

## 62. Interaction

Persistence operations may interact with system resources.

Include persistence behavior in production-like benchmarks.

------------------------------------------------------------------------

# Part 61 --- Query/Search Workloads

## 63. Advanced Capabilities

If tiered data also uses:

``` text
Search
JSON
Vector Search
```

qualify the combined workload.

Do not extrapolate from simple `GET` benchmarks.

------------------------------------------------------------------------

# Part 62 --- Vector Search

## 64. Capacity

Vector indexes can be memory-intensive.

Validate the exact product architecture/support for combining vector
workloads with tiering.

Measure actual memory and latency.

------------------------------------------------------------------------

# Part 63 --- Large JSON

## 65. Test

Large JSON documents can create larger value transfers.

Measure path-level vs whole-document behavior under the tiered
configuration.

------------------------------------------------------------------------

# Part 64 --- Streams

## 66. Validate

If Streams are used, qualify:

``` text
append
read
consumer groups
pending recovery
retention
```

under the exact supported tiering configuration.

------------------------------------------------------------------------

# Part 65 --- Benchmark Harness

## 67. Requirements

Record:

``` text
dataset
key distribution
value distribution
read/write ratio
TTL
concurrency
working-set ratio
test duration
```

------------------------------------------------------------------------

# Part 66 --- Warm-Up

## 68. Important

A tiered workload may behave differently during:

``` text
cold start
warming
steady state
```

Record each phase separately.

------------------------------------------------------------------------

# Part 67 --- Cold-Start Test

## 69. Procedure

After an approved reset/restart/recovery state, run representative
traffic.

Measure time until:

``` text
P99 stabilizes
working set stabilizes
device I/O stabilizes
```

------------------------------------------------------------------------

# Part 68 --- Soak Test

## 70. Long Duration

Run representative workload long enough to capture:

``` text
working-set shifts
TTL churn
batch jobs
backup
persistence
periodic application traffic
```

------------------------------------------------------------------------

# Part 69 --- Burst Test

## 71. Example

``` text
normal = 20k ops/sec
burst = 50k ops/sec
```

Measure:

``` text
P99
device latency
errors
recovery time
```

Use approved workload values.

------------------------------------------------------------------------

# Part 70 --- Stop Conditions

## 72. Define Before Test

Examples:

``` text
P99 > safety threshold
error rate > threshold
flash latency > threshold
RAM headroom < threshold
device queueing unsafe
replication unhealthy
```

------------------------------------------------------------------------

# Part 71 --- SLO

## 73. Multi-Dimensional

A tiered service SLO may include:

``` text
availability
P99 latency
error rate
recovery time
```

Capacity alerts support the SLO but are not the SLO itself.

------------------------------------------------------------------------

# Part 72 --- Baseline Table

## 74. Example

  ----------------------------------------------------------------------------------
  Test        Working   Read/Write       P99     Ops/s     Flash     Flash       RAM
                  Set                                       IOPS   Latency 
  --------- --------- ------------ --------- --------- --------- --------- ---------
  hot                                                                      

  uniform                                                                  

  shifted                                                                  
  ----------------------------------------------------------------------------------

------------------------------------------------------------------------

# Part 73 --- Cost Model

## 75. Compare

Estimate:

``` text
all-DRAM architecture cost
vs
tiered RAM + flash architecture cost
```

Then compare against:

``` text
latency
throughput
operational complexity
```

Cost savings that violate SLO are not savings.

------------------------------------------------------------------------

# Part 74 --- Failure Scenario 1

## 76. Uniform Access

Change from hot-set access to uniform synthetic access.

Observe flash I/O and P99.

------------------------------------------------------------------------

# Part 75 --- Failure Scenario 2

## 77. Working-Set Shift

Move the hot set rapidly.

Measure transient latency.

------------------------------------------------------------------------

# Part 76 --- Failure Scenario 3

## 78. Large Values

Increase synthetic value size.

Measure flash throughput and response latency.

------------------------------------------------------------------------

# Part 77 --- Failure Scenario 4

## 79. Batch Scan

Run a bounded scan/read job against synthetic data.

Observe impact on normal application traffic.

------------------------------------------------------------------------

# Part 78 --- Failure Scenario 5

## 80. Hot Tenant

Increase one synthetic tenant's active dataset and QPS.

Measure cross-tenant impact.

------------------------------------------------------------------------

# Part 79 --- Failure Scenario 6

## 81. Flash Pressure

Increase workload only to the approved device utilization threshold.

Validate alerting and stop conditions.

------------------------------------------------------------------------

# Part 80 --- Failure Scenario 7

## 82. N-1

Remove approved capacity under representative load.

Validate degraded-state SLO.

------------------------------------------------------------------------

# Part 81 --- Failure Scenario 8

## 83. Slow Device

Use approved infrastructure fault simulation where available.

Validate detection of elevated storage latency.

------------------------------------------------------------------------

# Part 82 --- Failure Scenario 9

## 84. Rebalance

Trigger an approved nonproduction rebalance.

Measure application P99 and device/network load.

------------------------------------------------------------------------

# Part 83 --- Failure Scenario 10

## 85. Backup Under Load

Run an approved backup while representative traffic is active.

Measure performance impact.

------------------------------------------------------------------------

# Part 84 --- Troubleshooting Matrix

## 86. Common Problems

  Symptom                   Investigate
  ------------------------- ---------------------------------------------
  P99 suddenly high         working-set shift, flash latency, CPU
  average OK/P99 bad        cold reads, device tail latency
  flash IOPS high           active set, scans, tenant skew
  flash latency high        device saturation, queueing
  RAM pressure              working set, metadata, shard placement
  one node slow             shard skew, device health
  batch hurts API           scan workload, working-set disruption
  failover misses SLO       N-1 capacity, recovery load
  rebalance hurts traffic   network/I/O/headroom
  cost high                 RAM ratio, dataset growth, architecture fit

------------------------------------------------------------------------

# Part 85 --- Runbook 1: Auto Tiering Suitability

## 87. Procedure

``` text
1. measure dataset.
2. measure working set.
3. classify access distribution.
4. record latency SLO.
5. qualify flash.
6. estimate cost.
7. benchmark representative workload.
8. approve/reject.
```

------------------------------------------------------------------------

# Part 86 --- Runbook 2: High Tiered P99

## 88. Procedure

``` text
1. confirm application impact.
2. compare hot/cold latency.
3. inspect working-set change.
4. inspect flash latency/IOPS.
5. inspect RAM/CPU.
6. inspect shard placement.
7. reduce disruptive workload if needed.
8. benchmark remediation.
```

------------------------------------------------------------------------

# Part 87 --- Runbook 3: Flash Saturation

## 89. Procedure

``` text
1. measure device latency.
2. measure IOPS/throughput.
3. identify workload source.
4. inspect value sizes.
5. inspect scans/batch jobs.
6. throttle disruptive work.
7. scale/change storage if required.
8. validate headroom.
```

------------------------------------------------------------------------

# Part 88 --- Runbook 4: Capacity Forecast

## 90. Procedure

``` text
1. record current dataset.
2. record RAM/flash use.
3. measure working set.
4. calculate net growth.
5. project exhaustion.
6. validate N-1.
7. define scale date.
8. review monthly.
```

------------------------------------------------------------------------

# Part 89 --- Runbook 5: Node Maintenance

## 91. Procedure

``` text
1. validate cluster health.
2. validate N-1 RAM/flash.
3. validate backups.
4. start monitoring.
5. perform supported maintenance.
6. monitor P99/I/O.
7. restore redundancy.
8. validate steady state.
```

------------------------------------------------------------------------

# Part 90 --- Runbook 6: Scale Out

## 92. Procedure

``` text
1. identify bottleneck.
2. calculate target capacity.
3. add supported nodes/storage.
4. validate health.
5. rebalance using supported procedure.
6. monitor P99/network/I/O.
7. validate placement.
8. update capacity baseline.
```

------------------------------------------------------------------------

# Part 91 --- Runbook 7: Flash Device Incident

## 93. Procedure

``` text
1. identify affected node/device.
2. inspect Redis Enterprise health.
3. inspect infrastructure metrics.
4. protect application SLO.
5. follow supported replacement/recovery.
6. monitor rebuild.
7. validate redundancy.
8. document RCA.
```

------------------------------------------------------------------------

# Part 92 --- Runbook 8: Tiering Regression

## 94. Procedure

``` text
1. record changed component.
2. restore representative dataset.
3. run previous baseline.
4. run changed configuration.
5. compare P99/throughput/I/O.
6. compare working-set behavior.
7. repeat to confirm.
8. accept, tune, or rollback.
```

------------------------------------------------------------------------

# Part 93 --- Capacity Worksheet

## 95. Record

``` text
Logical dataset:
Key count:
Average value:
P95/P99 value:
Working-set size:
Working-set ratio:
RAM:
Flash:
Replication:
Growth/day:
RAM headroom:
Flash headroom:
N-1 result:
Projected scale date:
```

------------------------------------------------------------------------

# Part 94 --- Device Qualification Worksheet

## 96. Record

``` text
Device/storage class:
Supported:
Capacity:
Read IOPS:
Write IOPS:
Read throughput:
Write throughput:
P95 latency:
P99 latency:
Endurance:
Failure model:
Monitoring:
```

------------------------------------------------------------------------

# Part 95 --- Performance Worksheet

## 97. Record

``` text
Test:
Dataset:
Working-set ratio:
Distribution:
Value size:
Read/write:
TTL:
Concurrency:
Ops/sec:
P50:
P95:
P99:
CPU:
RAM:
Flash IOPS:
Flash throughput:
Flash latency:
Errors:
```

------------------------------------------------------------------------

# Part 96 --- Production Acceptance

## 98. Architecture

-   [ ] Auto Tiering use case justified;
-   [ ] workload suitability reviewed;
-   [ ] working set measured;
-   [ ] access distribution measured;
-   [ ] unsupported OS-swap design avoided;
-   [ ] product/version support verified.

## 99. Capacity

-   [ ] logical dataset measured;
-   [ ] RAM requirement sized using supported guidance;
-   [ ] flash requirement sized;
-   [ ] replication included;
-   [ ] growth forecasted;
-   [ ] working-set growth forecasted;
-   [ ] maintenance/rebalance headroom included;
-   [ ] N-1 validated.

## 100. Flash

-   [ ] storage class supported;
-   [ ] IOPS qualified;
-   [ ] throughput qualified;
-   [ ] P95/P99 latency qualified;
-   [ ] endurance reviewed;
-   [ ] device monitoring enabled;
-   [ ] failure procedure documented.

## 101. Performance

-   [ ] all-memory/reference baseline captured where practical;
-   [ ] tiered baseline captured;
-   [ ] hot-set test completed;
-   [ ] uniform-access test completed;
-   [ ] working-set-shift test completed;
-   [ ] cold/warm access compared;
-   [ ] value-size test completed;
-   [ ] read/write mixes tested;
-   [ ] batch workload tested;
-   [ ] soak/burst tests completed.

## 102. Resilience / Operations

-   [ ] persistence interaction tested;
-   [ ] backup impact tested;
-   [ ] failover tested;
-   [ ] N-1 tested;
-   [ ] recovery measured;
-   [ ] rebalance tested;
-   [ ] maintenance runbook reviewed;
-   [ ] scale runbook reviewed;
-   [ ] ten failure scenarios completed;
-   [ ] eight runbooks reviewed.

------------------------------------------------------------------------

# 103. Knowledge Validation

1.  Why does Auto Tiering exist?
2.  What is a working set?
3.  How do you calculate working-set ratio?
4.  Why does access distribution matter?
5.  Which workloads may be poor tiering candidates?
6.  Why is Auto Tiering different from OS swap?
7.  Why is flash a performance dependency?
8.  Which flash characteristics should be measured?
9.  Why does endurance matter?
10. Why is logical dataset size different from RAM requirement?
11. Why should flash not be sized to raw data exactly?
12. How does replication affect tiered capacity?
13. Why is tiering not the same as persistence?
14. Why are backups still required?
15. Why compare all-memory and tiered baselines?
16. Why test uniform access?
17. Why test a working-set shift?
18. Why test different value sizes?
19. How can a batch scan affect tiering?
20. Why track working-set growth separately from dataset growth?
21. What can indicate flash saturation?
22. Why inspect per-node behavior?
23. Why can rebalancing affect application latency?
24. Why must N-1 include flash as well as RAM?
25. Why should slow-device behavior be monitored?
26. Why test backup under load?
27. What should a tiering SLO include?
28. Why define benchmark stop conditions?
29. Why compare cost and SLO together?
30. What must pass before Auto Tiering is production-ready?

------------------------------------------------------------------------

# 104. Hands-On Acceptance Checklist

-   [ ] Documented tiering use case.
-   [ ] Measured logical dataset.
-   [ ] Measured working set.
-   [ ] Calculated working-set ratio.
-   [ ] Classified access distribution.
-   [ ] Qualified supported flash class.
-   [ ] Measured flash latency/IOPS/throughput.
-   [ ] Reviewed endurance.
-   [ ] Built RAM/flash capacity worksheet.
-   [ ] Included replication.
-   [ ] Forecasted dataset growth.
-   [ ] Forecasted working-set growth.
-   [ ] Captured reference baseline.
-   [ ] Captured tiered baseline.
-   [ ] Tested hot distribution.
-   [ ] Tested uniform distribution.
-   [ ] Tested working-set shift.
-   [ ] Tested cold/warm reads.
-   [ ] Tested value sizes.
-   [ ] Tested read/write mixes.
-   [ ] Tested TTL churn.
-   [ ] Tested batch scan.
-   [ ] Tested multi-tenant skew.
-   [ ] Tested hot tenant.
-   [ ] Tested backup/persistence interaction.
-   [ ] Tested Search/JSON/Vector workloads where used.
-   [ ] Tested cold start.
-   [ ] Completed soak/burst.
-   [ ] Tested N-1.
-   [ ] Tested failover/recovery.
-   [ ] Tested rebalance.
-   [ ] Completed ten failure scenarios.
-   [ ] Completed eight runbooks.
-   [ ] Completed production acceptance.

------------------------------------------------------------------------

# 105. Cleanup

Auto Tiering labs may involve infrastructure-level changes.

Restore the nonproduction environment to its approved baseline.

Remove only confirmed synthetic lab keys:

``` bash
redis-cli --scan --pattern 'tutorial:chapter60:*'
```

Review and remove disposable keys with `UNLINK`.

Remove temporary:

``` text
load generators
failure simulations
temporary dashboards
temporary alerts
synthetic batch jobs
temporary storage test resources
```

Verify:

``` text
cluster healthy
replication healthy
node capacity restored
device health normal
P99 returned to baseline
```

Never use `FLUSHDB` or `FLUSHALL` against a shared or production
database.

------------------------------------------------------------------------

# 106. Key Takeaways

1.  Auto Tiering is a deliberate RAM/flash capacity architecture.
2.  Its value depends strongly on the application's working set.
3.  Access distribution matters as much as total dataset size.
4.  Uniform or rapidly shifting access can reduce tiering benefits.
5.  Auto Tiering is not OS swap.
6.  Flash becomes part of the database performance path.
7.  Flash latency, IOPS, throughput, and endurance must be qualified.
8.  Use only supported storage configurations.
9.  RAM requirements include more than hot values.
10. Flash requirements include more than raw cold bytes.
11. Replication affects both RAM and flash capacity.
12. Tiering does not replace persistence or backup.
13. Compare reference and tiered baselines with the same workload.
14. Test hot, uniform, cold, and shifting working sets.
15. Test realistic value sizes and read/write ratios.
16. Batch scans can disrupt the working set and P99.
17. Track working-set growth separately from total data growth.
18. Device saturation can cause high P99 even when CPU is healthy.
19. Per-node/shard imbalance can create localized flash pressure.
20. Scaling and rebalancing can themselves consume substantial
    I/O/network.
21. N-1 qualification must include RAM, flash, CPU, and network.
22. Slow storage devices are operational incidents even before hard
    failure.
23. Backup, persistence, Search, JSON, Vector, and Streams interactions
    should be tested when used.
24. Cost savings are meaningful only if the required SLO remains
    achievable.
25. Production readiness requires workload fit, capacity, device
    qualification, performance, resilience, recovery, and operational
    evidence together.

------------------------------------------------------------------------

# 107. References

Validate product naming, supported architectures, RAM/flash ratios,
storage requirements, persistence behavior, metrics, and operational
procedures against the exact deployed Redis/Redis Enterprise version and
current official Redis documentation.

Recommended documentation areas:

-   Redis Enterprise Auto Tiering
-   Redis on Flash / historical terminology where applicable
-   Redis Enterprise hardware requirements
-   Redis Enterprise storage requirements
-   Redis Enterprise sizing
-   Redis Enterprise memory architecture
-   Redis Enterprise high availability
-   Redis Enterprise persistence
-   Redis Enterprise backup/restore
-   Redis Enterprise cluster scaling and rebalancing
-   Redis Enterprise observability
-   cloud-provider storage performance documentation

------------------------------------------------------------------------

# Next Chapter

**Chapter 61 --- Redis Enterprise Kubernetes Operator Architecture &
Reconciliation**

Chapter 61 will begin Part 11 and cover the Redis Enterprise Kubernetes
Operator control loop, CRDs, REC/REDB resource relationships,
reconciliation, namespaces, RBAC, admission and status behavior,
scheduling, storage/network dependencies, upgrades, GitOps interaction,
observability, failure scenarios, troubleshooting, runbooks, and
production acceptance.
