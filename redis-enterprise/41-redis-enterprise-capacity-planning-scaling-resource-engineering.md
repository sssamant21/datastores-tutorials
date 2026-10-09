# Chapter 41 --- Redis Enterprise Capacity Planning, Scaling & Resource Engineering

**Status:** Canonical\
**Track:** Redis Enterprise / Redis Software Production Engineering\
**Part:** Part 6 --- Observability, Reliability & Production Operations\
**Level:** Advanced → Production Capacity & Scaling Engineering\
**Audience:** SREs, DBREs, Platform Engineers, Redis Administrators,
Developers, Capacity Engineers\
**Lab type:** Workload characterization, dataset and working-set sizing,
memory/CPU/network modeling, connection budgeting, shard analysis,
replication/persistence overhead, failover headroom, Active-Active
regional capacity, vertical/horizontal scaling, growth forecasting, load
testing, scale-trigger validation, failure injection, troubleshooting,
runbooks, and production acceptance

------------------------------------------------------------------------

# 1. Objective

Capacity planning answers:

``` text
How much Redis capacity do we need now?
How much headroom do we need?
When will we run out?
How should we scale?
Can the platform survive failure at peak load?
```

A useful model is:

``` text
Application demand
      |
      v
operations/sec
connections
payload size
dataset
      |
      v
Redis shards
      |
      v
CPU + memory + network
      |
      v
replication + persistence + failover overhead
```

By the end, you should be able to:

-   characterize Redis workloads;
-   distinguish dataset from working set;
-   estimate memory demand;
-   estimate CPU demand;
-   estimate network demand;
-   calculate fleet connection budgets;
-   analyze shard count and placement;
-   detect skew;
-   account for replication overhead;
-   account for persistence overhead;
-   reserve failover headroom;
-   plan Active-Active regional capacity;
-   choose vertical vs. horizontal scaling;
-   define scale triggers;
-   forecast growth;
-   design representative load tests;
-   test N-1 conditions;
-   troubleshoot capacity incidents;
-   create production capacity runbooks.

------------------------------------------------------------------------

# 2. Core Production Principle

Do not size Redis only for today's average.

Production capacity must account for:

``` text
normal load
peak load
growth
failover
maintenance
replication
persistence
recovery/catch-up
unexpected skew
```

------------------------------------------------------------------------

# Part 1 --- Workload Characterization

## 3. Start With Demand

Record:

``` text
reads/sec
writes/sec
peak ops/sec
average value size
P95/P99 value size
connections
dataset size
working set
TTL profile
command mix
```

------------------------------------------------------------------------

# Part 2 --- Average vs. Peak

## 4. Peak Matters

Example:

``` text
average = 20k ops/sec
peak = 80k ops/sec
```

Sizing only for average leaves no safe peak capacity.

------------------------------------------------------------------------

# Part 3 --- Burst

## 5. Short Spikes

Record:

``` text
1-minute peak
5-minute peak
15-minute peak
hourly peak
```

A brief burst can still exhaust pools or CPU.

------------------------------------------------------------------------

# Part 4 --- Read/Write Mix

## 6. Why It Matters

Different operations have different:

``` text
CPU
network
replication
persistence
```

cost.

A workload with 90% reads is different from one with 90% writes.

------------------------------------------------------------------------

# Part 5 --- Command Mix

## 7. Inventory

Record major commands:

``` text
GET
SET
MGET
HGET/HSET
INCR
ZADD/ZRANGE
XADD/XREADGROUP
Lua
```

Do not size solely by generic ops/sec.

------------------------------------------------------------------------

# Part 6 --- Dataset

## 8. Definition

Dataset is the total data stored in Redis.

Measure actual Redis memory usage rather than summing application
payload bytes only.

Redis memory includes data-structure and allocator overhead.

------------------------------------------------------------------------

# Part 7 --- Working Set

## 9. Definition

Working set is the subset of data actively needed during the relevant
time window.

For a cache, the working set may determine whether the hit ratio remains
healthy.

------------------------------------------------------------------------

# Part 8 --- Dataset vs. Working Set

## 10. Example

``` text
total logical dataset = 500 GB
hot working set = 120 GB
```

Whether Redis must hold 500 GB or only the 120 GB working set depends on
architecture and eviction policy.

------------------------------------------------------------------------

# Part 9 --- Memory Components

## 11. Model

Conceptually:

``` text
Redis memory
=
key overhead
+
value data
+
data-structure overhead
+
allocator overhead
+
buffers
+
replication overhead
+
client overhead
+
operational headroom
```

------------------------------------------------------------------------

# Part 10 --- Measure, Don't Guess

## 12. Commands

Useful lab diagnostics:

``` redis
INFO memory
MEMORY STATS
MEMORY USAGE <key>
```

Use Redis Enterprise metrics for production sizing.

------------------------------------------------------------------------

# Part 11 --- Average Key Cost

## 13. Sample

For representative keys:

``` text
average Redis bytes/key
=
sampled Redis memory usage
/
sampled keys
```

Sample multiple key families.

------------------------------------------------------------------------

# Part 12 --- Key-Family Model

## 14. Better Estimate

Example:

``` text
profile:*   10M keys × avg bytes
session:*    5M keys × avg bytes
cache:*     50M keys × avg bytes
```

Different structures have different overhead.

------------------------------------------------------------------------

# Part 13 --- Growth

## 15. Forecast

Track:

``` text
keys/day
memory/day
traffic/week
connections/month
```

Forecast capacity exhaustion before it becomes an incident.

------------------------------------------------------------------------

# Part 14 --- Simple Memory Forecast

## 16. Formula

``` text
days to threshold
≈
(allowed memory - current memory)
/
daily memory growth
```

Only useful when growth is approximately stable.

------------------------------------------------------------------------

# Part 15 --- TTL

## 17. Capacity Control

TTL affects steady-state dataset size.

If arrival rate is roughly constant:

``` text
steady keys
≈
new keys/sec × average TTL seconds
```

This is an approximation.

------------------------------------------------------------------------

# Part 16 --- TTL Change Risk

## 18. Example

Changing:

``` text
TTL 1 hour -> 24 hours
```

can dramatically increase retained data.

Treat TTL changes as capacity changes.

------------------------------------------------------------------------

# Part 17 --- Eviction

## 19. Cache Capacity

For cache workloads, insufficient memory can manifest as:

``` text
evictions
lower hit ratio
source amplification
higher latency
```

Capacity should be evaluated by service outcome, not only whether Redis
remains running.

------------------------------------------------------------------------

# Part 18 --- Memory Headroom

## 20. Reserve

Headroom supports:

``` text
traffic bursts
replication
buffers
persistence
failover
maintenance
temporary growth
```

The correct percentage depends on workload and product guidance.

------------------------------------------------------------------------

# Part 19 --- CPU Capacity

## 21. Measure

Track:

``` text
CPU at normal load
CPU at peak
CPU by shard
ops/sec
command mix
latency
```

------------------------------------------------------------------------

# Part 20 --- CPU Scaling Curve

## 22. Load Test

Measure:

``` text
ops/sec vs CPU
ops/sec vs P99
```

The safe operating point is below the region where latency rises
sharply.

------------------------------------------------------------------------

# Part 21 --- Saturation Knee

## 23. Concept

A common pattern:

``` text
load increases
CPU rises gradually
latency stable
        |
        v
saturation knee
        |
        v
P99 rises rapidly
```

Capacity planning should stay below this knee with headroom.

------------------------------------------------------------------------

# Part 22 --- Shard CPU

## 24. Important

A database average can hide one saturated shard.

Capacity is constrained by the hottest shard, not only cluster average.

------------------------------------------------------------------------

# Part 23 --- Network Capacity

## 25. Approximation

Application traffic:

``` text
network bytes/sec
≈
ops/sec × average request/response bytes
```

Real traffic includes protocol/TLS overhead.

Measure actual network throughput.

------------------------------------------------------------------------

# Part 24 --- Read Network

## 26. Large Responses

A read-heavy workload with large values can be network-bound even when
CPU is moderate.

------------------------------------------------------------------------

# Part 25 --- Write Network

## 27. Replication

Writes can generate:

``` text
client -> Redis traffic
Redis -> replica traffic
Redis -> Active-Active region traffic
backup/persistence-related traffic
```

------------------------------------------------------------------------

# Part 26 --- Connection Capacity

## 28. Fleet Budget

Calculate:

``` text
connections
=
pods
× workers per pod
× pool size per worker
```

Then add:

``` text
admin
monitoring
automation
failover/reconnect headroom
```

------------------------------------------------------------------------

# Part 27 --- Example Connection Budget

## 29. Example

``` text
40 pods
× 4 workers
× 20 connections
=
3,200 application connections
```

If two services use the same database, calculate both.

------------------------------------------------------------------------

# Part 28 --- Autoscaling Multiplier

## 30. Risk

If Kubernetes HPA can scale:

``` text
20 pods -> 100 pods
```

Redis connection demand can increase 5×.

Size using maximum intended fleet, not current replicas only.

------------------------------------------------------------------------

# Part 29 --- Pool Size

## 31. Not "More Is Better"

Too small:

``` text
pool wait
timeouts
```

Too large:

``` text
excess server connections
reconnect storms
memory/FD pressure
```

Tune from concurrency and measured service time.

------------------------------------------------------------------------

# Part 30 --- Little's Law

## 32. Useful Approximation

For stable systems:

``` text
concurrency
≈
throughput × average response time
```

Example:

``` text
10,000 requests/sec
× 0.002 sec
≈
20 concurrent requests
```

Add realistic headroom and burst behavior.

------------------------------------------------------------------------

# Part 31 --- Shards

## 33. Why Shard

Sharding distributes:

``` text
memory
CPU
network
keys
```

across execution units.

------------------------------------------------------------------------

# Part 32 --- Shard Count

## 34. Too Few

Can cause:

``` text
per-shard CPU saturation
memory concentration
limited throughput
```

## 35. Too Many

Can increase:

``` text
operational complexity
resource overhead
placement complexity
```

Use Redis Enterprise product guidance and workload tests.

------------------------------------------------------------------------

# Part 33 --- Shard Placement

## 36. Node Balance

Review:

``` text
shards per node
memory per node
CPU per node
database placement
replicas
failure domains
```

------------------------------------------------------------------------

# Part 34 --- Skew

## 37. Capacity Loss

If one shard is at 95% CPU while peers are 30%, adding total cluster
capacity may not help unless the hot workload is redistributed.

------------------------------------------------------------------------

# Part 35 --- Hash Tags

## 38. Concentration

Hash tags can intentionally colocate keys.

Poor use can concentrate too much traffic/data on one shard.

Review application key patterns.

------------------------------------------------------------------------

# Part 36 --- Tenant Skew

## 39. Multi-Tenant

One large tenant can dominate:

``` text
keys
memory
ops/sec
network
```

Capacity planning should include per-tenant distribution.

------------------------------------------------------------------------

# Part 37 --- Replication Overhead

## 40. Memory/Network

Replication adds:

``` text
replica dataset capacity
replication network
backlog/buffer overhead
sync/recovery cost
```

------------------------------------------------------------------------

# Part 38 --- Full Sync Capacity

## 41. Recovery

A full synchronization can temporarily require more:

``` text
network
CPU
memory
storage
```

than steady-state replication.

Test recovery, not only normal operation.

------------------------------------------------------------------------

# Part 39 --- Persistence Overhead

## 42. RDB/AOF

Where enabled, reserve capacity for:

``` text
fork/COW memory
AOF buffers
rewrite
storage throughput
temporary storage
CPU
```

Exact behavior depends on deployment/version.

------------------------------------------------------------------------

# Part 40 --- Backup Overhead

## 43. Include

Backup can consume:

``` text
network
storage
CPU
memory
```

depending on implementation.

Measure production-like backup behavior.

------------------------------------------------------------------------

# Part 41 --- Failover Capacity

## 44. N-1

A resilient design asks:

``` text
Can the system meet SLO after one relevant failure?
```

Examples:

``` text
one node unavailable
one shard/replica transition
one region unavailable
```

------------------------------------------------------------------------

# Part 42 --- N-1 Node Model

## 45. Concept

If total workload only fits while every node is healthy, maintenance or
failure may cause saturation.

Reserve capacity for expected failure scenarios.

------------------------------------------------------------------------

# Part 43 --- Promotion Capacity

## 46. Replica

A replica that can copy data but cannot handle production traffic after
promotion is undersized.

Validate promoted-node performance.

------------------------------------------------------------------------

# Part 44 --- Reconnect Capacity

## 47. Failover Burst

After failover:

``` text
application traffic
+
reconnect/auth/TLS
+
replication recovery
```

may occur simultaneously.

------------------------------------------------------------------------

# Part 45 --- Maintenance Headroom

## 48. Planned Work

Capacity should support:

``` text
rolling maintenance
upgrade
node drain
certificate rotation
```

without violating SLO.

------------------------------------------------------------------------

# Part 46 --- Active-Active Capacity

## 49. Per Region

Each region needs:

``` text
local application traffic
geo replication
catch-up
failover traffic
```

------------------------------------------------------------------------

# Part 47 --- Regional N-1

## 50. Region Failure

If Region A fails, Region B may receive more application traffic.

Test the intended traffic distribution.

------------------------------------------------------------------------

# Part 48 --- Catch-Up Capacity

## 51. Rejoin

When Region A returns:

``` text
normal/failover application traffic
+
geo catch-up
```

can overlap.

Reserve headroom.

------------------------------------------------------------------------

# Part 49 --- Vertical Scaling

## 52. Definition

Increase resources of existing nodes/instances:

``` text
CPU
memory
network class
```

Advantages:

``` text
simpler topology
larger per-shard capacity
```

Limits:

``` text
instance ceilings
failure blast radius
maintenance implications
```

------------------------------------------------------------------------

# Part 50 --- Horizontal Scaling

## 53. Definition

Add nodes/shards/capacity units.

Advantages:

``` text
aggregate capacity
distribution
failure-domain options
```

Costs:

``` text
resharding/rebalancing
complexity
network movement
```

------------------------------------------------------------------------

# Part 51 --- Choose by Bottleneck

## 54. Examples

``` text
single shard CPU bound -> distribution/shard strategy
all nodes CPU bound -> scale capacity
memory bound -> memory/data/sharding
network bound -> payload/network/topology
connections bound -> client/fleet design
```

------------------------------------------------------------------------

# Part 52 --- Scaling Is a Change

## 55. Plan

Before scaling:

``` text
capture baseline
define expected effect
understand data movement
check failure headroom
schedule/approve
monitor
validate
```

------------------------------------------------------------------------

# Part 53 --- Scale Triggers

## 56. Do Not Wait for Outage

Possible triggers:

``` text
forecasted memory threshold
sustained peak CPU
P99 degradation
connection headroom
network saturation
N-1 test failure
```

------------------------------------------------------------------------

# Part 54 --- Memory Trigger

## 57. Better Than One Threshold

Combine:

``` text
current %
growth rate
eviction behavior
forecast date
failover headroom
```

------------------------------------------------------------------------

# Part 55 --- CPU Trigger

## 58. Use Peak

Track hottest shard/node during representative peak.

Average daily CPU is not a safe scale trigger.

------------------------------------------------------------------------

# Part 56 --- Network Trigger

## 59. Headroom

Compare measured peak with known interface/product limits.

Include failover and replication traffic.

------------------------------------------------------------------------

# Part 57 --- Connection Trigger

## 60. Forecast

Use:

``` text
current fleet
maximum autoscale fleet
pool size
expected failover/reconnect
```

------------------------------------------------------------------------

# Part 58 --- Capacity Forecast

## 61. Review Cadence

Capacity review should be periodic and also triggered by:

``` text
new application
large tenant
traffic launch
TTL change
data-model change
region expansion
replica change
```

------------------------------------------------------------------------

# Part 59 --- Seasonal Traffic

## 62. Events

Model known:

``` text
end-of-month
open enrollment
holiday
batch windows
marketing event
```

using historical peak plus growth.

------------------------------------------------------------------------

# Part 60 --- Safety Factor

## 63. Context

Do not apply an arbitrary universal multiplier.

Headroom should reflect:

``` text
forecast uncertainty
failure requirement
burstiness
scale lead time
business criticality
```

------------------------------------------------------------------------

# Part 61 --- Load Testing

## 64. Goal

A capacity test should answer:

``` text
What is safe peak throughput?
Where is saturation?
What fails first?
What happens to P99?
Can N-1 meet SLO?
```

------------------------------------------------------------------------

# Part 62 --- Representative Workload

## 65. Match Production

Include:

``` text
command mix
key distribution
value sizes
TTL
connections
read/write ratio
pipelines
Lua
hot-key behavior
```

A synthetic GET-only benchmark may be misleading.

------------------------------------------------------------------------

# Part 63 --- Warm-Up

## 66. Avoid False Results

Allow:

``` text
connections
cache state
JIT/runtime
metrics
```

to stabilize before measuring.

------------------------------------------------------------------------

# Part 64 --- Step Load

## 67. Method

Increase load in controlled steps:

``` text
25%
50%
75%
100%
125%
```

of expected peak, within lab safety.

At each step record latency and saturation.

------------------------------------------------------------------------

# Part 65 --- Stop Conditions

## 68. Define Before Test

Examples:

``` text
P99 > limit
CPU > safe test threshold
errors > threshold
memory > threshold
replication lag > threshold
```

------------------------------------------------------------------------

# Part 66 --- Soak Test

## 69. Duration

A short benchmark may miss:

``` text
memory growth
connection leak
fragmentation
persistence cycles
backup overlap
```

Run a longer representative soak test.

------------------------------------------------------------------------

# Part 67 --- Failure Load Test

## 70. N-1

At representative peak:

``` text
remove/fail one capacity component
```

in a disposable environment and validate SLO.

------------------------------------------------------------------------

# Part 68 --- Reconnect Test

## 71. Burst

Simulate failover/restart and observe client reconnect load.

------------------------------------------------------------------------

# Part 69 --- Persistence Test

## 72. Overlap

Run representative traffic during persistence/rewrite behavior where
applicable.

Measure P99 and resources.

------------------------------------------------------------------------

# Part 70 --- Backup Test

## 73. Overlap

Measure production-like backup while representative workload runs.

------------------------------------------------------------------------

# Part 71 --- Active-Active Test

## 74. Regional

Measure:

``` text
local peak
regional failover
geo replication
region rejoin catch-up
```

------------------------------------------------------------------------

# Part 72 --- Capacity Lab

## 75. Safety

Use a disposable environment.

Do not benchmark to failure in production.

------------------------------------------------------------------------

# Part 73 --- Baseline Generator

## 76. Python

``` python
import os
import time
import redis

r = redis.Redis(
    host=os.getenv("REDIS_HOST", "localhost"),
    port=int(os.getenv("REDIS_PORT", "6379")),
    password=os.getenv("REDIS_PASSWORD") or None,
    decode_responses=False,
    socket_connect_timeout=1,
    socket_timeout=1,
)

payload = b"x" * 1024

started = time.time()

for i in range(50000):
    key = f"tutorial:chapter41:key:{i % 10000}"
    r.set(key, payload, ex=600)
    r.get(key)

elapsed = time.time() - started

print("operations:", 100000)
print("elapsed_sec:", round(elapsed, 2))
print("approx_ops_sec:", round(100000 / elapsed, 2))
```

Use only as a learning workload, not a production benchmark.

------------------------------------------------------------------------

# Part 74 --- Memory Sampling Lab

## 77. Representative Keys

Create several key families:

``` text
small strings
larger strings
hashes
sets
```

Measure with:

``` redis
MEMORY USAGE <key>
```

Calculate average bytes per key family.

------------------------------------------------------------------------

# Part 75 --- TTL Capacity Lab

## 78. Compare

Generate equal arrival rates with:

``` text
TTL = 60 sec
TTL = 600 sec
```

Observe steady-state key count and memory.

------------------------------------------------------------------------

# Part 76 --- Connection Budget Lab

## 79. Calculate

Given:

``` text
pods = 30
workers = 4
pool = 15
```

calculate:

``` text
30 × 4 × 15 = 1,800
```

Then model maximum autoscale.

------------------------------------------------------------------------

# Part 77 --- Load Curve Lab

## 80. Steps

Run bounded load levels and record:

``` text
ops/sec
P50
P95
P99
CPU
memory
network
errors
```

Plot or tabulate the saturation knee.

------------------------------------------------------------------------

# Part 78 --- Value-Size Lab

## 81. Compare

Use:

``` text
1 KB
10 KB
100 KB
1 MB
```

within safe limits.

Observe CPU/network/P99.

------------------------------------------------------------------------

# Part 79 --- Read/Write Mix Lab

## 82. Compare

Test:

``` text
90/10 read/write
50/50
10/90
```

Observe replication/persistence differences where enabled.

------------------------------------------------------------------------

# Part 80 --- Hot-Shard Lab

## 83. Distribution

Compare evenly distributed keys with intentionally concentrated
keys/hash tags.

Observe hottest-shard capacity.

------------------------------------------------------------------------

# Part 81 --- N-1 Lab

## 84. Failure

At a safe representative load, remove one disposable node/capacity
component using the supported procedure.

Record:

``` text
P99
errors
CPU
memory
failover
recovery
```

------------------------------------------------------------------------

# Part 82 --- Reconnect Lab

## 85. Client Burst

Restart/fail over a disposable endpoint and observe:

``` text
connection creation
TLS/auth
Redis CPU
application recovery
```

------------------------------------------------------------------------

# Part 83 --- Growth Forecast Lab

## 86. Example

Given:

``` text
current memory = 120 GB
allowed threshold = 180 GB
growth = 2 GB/day
```

then:

``` text
days to threshold
=
(180 - 120) / 2
=
30 days
```

Add operational lead time before the threshold.

------------------------------------------------------------------------

# Part 84 --- Failure Injection

## 87. Failure 1 --- Peak CPU Saturation

Increase bounded load until the pre-defined lab stop threshold.

Identify the latency knee.

## 88. Failure 2 --- Memory Growth

Generate controlled retained data and verify forecast/alerts.

## 89. Failure 3 --- Connection Growth

Increase client concurrency and validate fleet connection budget.

## 90. Failure 4 --- Large Values

Increase payload size and identify network/P99 impact.

## 91. Failure 5 --- Hot Shard

Concentrate workload and show why average capacity is misleading.

## 92. Failure 6 --- Replica Recovery

Trigger disposable replication recovery and measure temporary overhead.

## 93. Failure 7 --- Persistence Overlap

Run representative traffic during a persistence operation.

## 94. Failure 8 --- N-1 Node

Remove one disposable capacity component and validate SLO.

## 95. Failure 9 --- Autoscale Connection Surge

Simulate additional application instances and measure connection demand.

## 96. Failure 10 --- Regional Failover

In an Active-Active lab, shift representative traffic to the surviving
region and measure N-1 regional capacity.

------------------------------------------------------------------------

# Part 85 --- Troubleshooting

## 97. CPU Capacity Exhausted

Check:

``` text
all shards or one shard?
ops/sec growth?
command mix?
hot key?
retry amplification?
```

Scale only after identifying the bottleneck.

------------------------------------------------------------------------

## 98. Memory Capacity Exhausted

Check:

``` text
dataset growth
TTL
big keys
tenant growth
eviction
replication/persistence headroom
```

------------------------------------------------------------------------

## 99. Network Capacity Exhausted

Check:

``` text
payload size
read/write mix
replication
cross-region traffic
backup
large responses
```

------------------------------------------------------------------------

## 100. Connections Near Limit

Check:

``` text
pool sizes
pod count
workers
autoscaling
leaks
reconnects
```

------------------------------------------------------------------------

## 101. Capacity Looks Fine but P99 Is High

Check:

``` text
one hot shard
hot key
client pool
network
large values
expensive command
```

Aggregate capacity can be healthy while one path is saturated.

------------------------------------------------------------------------

## 102. Scale Did Not Improve Latency

Possible reasons:

``` text
hot key unchanged
client bottleneck
network bottleneck
remote routing
bad command/data model
```

------------------------------------------------------------------------

## 103. Failover Causes Saturation

The steady-state design lacks enough failure headroom or traffic
redistribution is uneven.

Recalculate N-1.

------------------------------------------------------------------------

## 104. Forecast Was Wrong

Check:

``` text
growth not linear
new tenant
TTL change
value-size change
traffic launch
seasonality
```

Update the model.

------------------------------------------------------------------------

# Part 86 --- Production Runbooks

## 105. Runbook --- Approaching Memory Capacity

``` text
1. Confirm current memory/headroom.
2. Confirm growth rate.
3. Calculate threshold date.
4. Check TTL and key/value growth.
5. Check eviction/source impact.
6. Validate failover headroom.
7. Select approved capacity/data action.
8. Schedule before lead-time deadline.
9. Validate after change.
10. Update forecast.
```

------------------------------------------------------------------------

## 106. Runbook --- CPU Capacity Saturation

``` text
1. Confirm P99/user impact.
2. Identify hottest node/shard.
3. Compare ops/sec with baseline.
4. Check command mix/hot keys.
5. Check retry amplification.
6. Determine distribution vs aggregate capacity issue.
7. Apply lowest-risk mitigation.
8. Scale if genuine capacity shortage.
9. Validate P99/headroom.
10. Update load model.
```

------------------------------------------------------------------------

## 107. Runbook --- Connection Capacity

``` text
1. Calculate current fleet demand.
2. Check actual server connections.
3. Check pool utilization/wait.
4. Check autoscale maximum.
5. Check leaks/churn.
6. Set safe per-client pool.
7. Validate failover/reconnect headroom.
8. Load test.
9. Monitor after rollout.
10. Update connection budget.
```

------------------------------------------------------------------------

## 108. Runbook --- Scale-Out

``` text
1. Capture baseline.
2. Identify capacity bottleneck.
3. Confirm scale-out addresses it.
4. Check data movement/rebalancing impact.
5. Confirm failure headroom.
6. Execute supported scale procedure.
7. Monitor migration/rebalance.
8. Validate shard/node distribution.
9. Validate P99/SLO.
10. Update topology/capacity records.
```

------------------------------------------------------------------------

## 109. Runbook --- N-1 Capacity Failure

``` text
1. Identify failed N-1 scenario.
2. Measure bottleneck.
3. Protect critical traffic.
4. Restore failed capacity.
5. Calculate required headroom.
6. Correct topology/capacity.
7. Repeat N-1 test.
8. Validate reconnect/recovery.
9. Update alert thresholds.
10. Record acceptance evidence.
```

------------------------------------------------------------------------

# Part 87 --- Capacity Model Template

## 110. Workload

``` text
Database:
Owner:
Use case:
Peak ops/sec:
Read/write ratio:
Command mix:
Average value:
P95 value:
P99 value:
Current keys:
Key growth/day:
TTL profile:
Connections:
Maximum application replicas:
```

## 111. Resources

``` text
Current CPU:
Peak CPU:
Hottest shard CPU:
Current memory:
Peak memory:
Memory growth/day:
Network in:
Network out:
Shard count:
Node count:
Replica count:
```

## 112. Reliability Overhead

``` text
N-1 requirement:
Failover headroom:
Replication:
Persistence:
Backup:
Reconnect burst:
Active-Active regions:
Regional failover requirement:
```

------------------------------------------------------------------------

# Part 88 --- Connection Budget Template

## 113. Formula

``` text
Service A:
max pods × workers × pool =

Service B:
max pods × workers × pool =

Monitoring =
Admin =
Automation =
Failover/reconnect reserve =

Total planned connections =
```

------------------------------------------------------------------------

# Part 89 --- Growth Forecast Template

## 114. Fields

``` text
Current memory:
Threshold:
Daily growth:
Forecast threshold date:
Current keys:
Daily key growth:
Current peak ops/sec:
Traffic growth/month:
Current connections:
Connection growth:
Known launch/event:
Scale lead time:
Recommended action date:
```

------------------------------------------------------------------------

# Part 90 --- Load-Test Record

## 115. Table

  Load     Ops/sec   P50   P95   P99   CPU   Memory   Network   Errors
  ------ --------- ----- ----- ----- ----- -------- --------- --------
  25%                                                         
  50%                                                         
  75%                                                         
  100%                                                        
  125%                                                        

Stop according to pre-defined safety limits.

------------------------------------------------------------------------

# Part 91 --- N-1 Test Record

## 116. Evidence

``` text
test date
topology
baseline load
failed component
failover time
peak CPU
peak memory
P99
errors
connection spike
replication recovery
SLO met:
remediation:
```

------------------------------------------------------------------------

# Part 92 --- Scale Decision Matrix

## 117. Examples

  Bottleneck                Likely Direction
  ------------------------- ------------------------------------------
  All shards CPU high       More aggregate compute/shards
  One shard CPU high        Distribution/hot-key fix
  Memory high               More memory/shards or data-policy change
  Network high              Payload/topology/network capacity
  Connections high          Client pool/fleet redesign
  N-1 fails                 More failure headroom
  Regional failover fails   More regional capacity

Always validate against Redis Enterprise architecture and support
guidance.

------------------------------------------------------------------------

# Part 93 --- Capacity Review Checklist

## 118. Periodic Review

-   [ ] Peak ops/sec updated.
-   [ ] Read/write ratio updated.
-   [ ] Value-size distribution updated.
-   [ ] Dataset size updated.
-   [ ] Working set reviewed.
-   [ ] Key growth reviewed.
-   [ ] TTL changes reviewed.
-   [ ] Memory forecast updated.
-   [ ] CPU peak reviewed.
-   [ ] Hottest shard reviewed.
-   [ ] Network peak reviewed.
-   [ ] Connection budget reviewed.
-   [ ] Autoscaling maximum reviewed.
-   [ ] Replication overhead reviewed.
-   [ ] Persistence overhead reviewed.
-   [ ] Backup overlap reviewed.
-   [ ] N-1 capacity reviewed.
-   [ ] Active-Active regional capacity reviewed.
-   [ ] Load-test results current.
-   [ ] Scale lead time reviewed.

------------------------------------------------------------------------

# Part 94 --- Production Acceptance Checklist

## 119. Capacity Engineering

-   [ ] Workload characterized.
-   [ ] Peak and burst traffic documented.
-   [ ] Command mix documented.
-   [ ] Value-size distribution measured.
-   [ ] Dataset size measured.
-   [ ] Working set understood.
-   [ ] Key-family memory model created.
-   [ ] TTL impact modeled.
-   [ ] Memory growth forecast created.
-   [ ] Memory headroom defined.
-   [ ] CPU load curve measured.
-   [ ] Saturation knee identified.
-   [ ] Hottest shard measured.
-   [ ] Network peak measured.
-   [ ] Fleet connection budget calculated.
-   [ ] Maximum autoscale connection demand calculated.
-   [ ] Shard count reviewed.
-   [ ] Shard placement reviewed.
-   [ ] Tenant/key skew reviewed.
-   [ ] Replication overhead measured.
-   [ ] Persistence overhead tested.
-   [ ] Backup overlap tested.
-   [ ] Failover/reconnect overhead tested.
-   [ ] N-1 node capacity tested.
-   [ ] Active-Active N-1 region capacity tested where applicable.
-   [ ] Vertical/horizontal scale strategy documented.
-   [ ] Scale triggers defined.
-   [ ] Scale lead time documented.
-   [ ] Representative load test completed.
-   [ ] Soak test completed.
-   [ ] Five capacity runbooks validated.

------------------------------------------------------------------------

# Knowledge Validation

## 120. Questions

1.  Why should Redis not be sized from average traffic alone?
2.  Why does command mix matter?
3.  What is the difference between dataset and working set?
4.  Why should actual Redis memory be measured instead of payload bytes
    alone?
5.  Why model memory by key family?
6.  How can TTL determine steady-state key count?
7.  Why is a TTL increase a capacity change?
8.  Why is memory headroom required?
9.  What is the CPU saturation knee?
10. Why does the hottest shard matter more than average CPU?
11. Why can a read-heavy workload be network-bound?
12. How do you calculate a fleet connection budget?
13. Why must HPA maximum replicas be included?
14. What does Little's Law estimate?
15. Why can too many connections be harmful?
16. What does sharding distribute?
17. Why can hash tags create capacity skew?
18. What overhead does replication add?
19. Why should full synchronization be capacity-tested?
20. What overhead can persistence add?
21. What is N-1 capacity?
22. Why must a replica be sized for promotion?
23. Why can failover create a reconnect capacity spike?
24. What additional capacity does Active-Active require?
25. When is vertical scaling appropriate?
26. When is horizontal scaling appropriate?
27. Why should scale triggers use trends and headroom?
28. Why must load tests match production command/value patterns?
29. Why are soak tests useful?
30. What must pass before Redis capacity is production-ready?

------------------------------------------------------------------------

# Hands-On Acceptance Checklist

## 121. Lab Completion

-   [ ] Generated representative workload.
-   [ ] Sampled memory by key family.
-   [ ] Compared TTL capacity.
-   [ ] Calculated connection budget.
-   [ ] Modeled maximum autoscale connections.
-   [ ] Generated load curve.
-   [ ] Identified saturation knee.
-   [ ] Compared value sizes.
-   [ ] Compared read/write mixes.
-   [ ] Tested hot-shard behavior.
-   [ ] Tested N-1 capacity.
-   [ ] Tested reconnect burst.
-   [ ] Calculated growth forecast.
-   [ ] Tested CPU saturation.
-   [ ] Tested memory growth.
-   [ ] Tested connection growth.
-   [ ] Tested large-value network impact.
-   [ ] Tested replica recovery overhead.
-   [ ] Tested persistence overlap.
-   [ ] Tested regional failover where applicable.
-   [ ] Completed ten failure scenarios.
-   [ ] Completed troubleshooting.
-   [ ] Reviewed five capacity runbooks.
-   [ ] Completed capacity model.
-   [ ] Completed connection budget.
-   [ ] Completed growth forecast.
-   [ ] Completed load-test record.
-   [ ] Completed N-1 record.
-   [ ] Completed production acceptance checklist.

------------------------------------------------------------------------

# 122. Lab Cleanup

Discover only Chapter 41 keys:

``` bash
redis-cli --scan --pattern 'tutorial:chapter41:*'
```

Review all matches.

Delete confirmed lab keys in bounded batches:

``` redis
UNLINK <confirmed-key>
```

Remove disposable load generators, temporary scale changes, and lab
monitoring objects.

Restore the lab topology to its intended baseline.

Do not use:

``` redis
KEYS tutorial:chapter41:*
FLUSHDB
FLUSHALL
```

against a shared or production database.

------------------------------------------------------------------------

# 123. Key Takeaways

1.  Capacity planning starts with workload characterization, not
    instance size.
2.  Peak, burst, and growth matter more than daily averages.
3.  Command mix and value size materially affect capacity.
4.  Dataset and working set are different sizing concepts.
5.  Actual Redis memory includes overhead beyond application payload
    bytes.
6.  Memory should be modeled by representative key family.
7.  TTL changes can dramatically change capacity requirements.
8.  Memory headroom protects bursts, failover, replication, and
    persistence.
9.  CPU capacity should be measured as a load/latency curve.
10. The saturation knee defines a practical upper operating boundary.
11. The hottest shard can constrain the whole database.
12. Network can be the bottleneck for large-value workloads.
13. Connection demand must be calculated across the full application
    fleet.
14. Autoscaling can multiply Redis connections unexpectedly.
15. Pool sizing should reflect concurrency rather than "more is better."
16. Shard count and placement affect CPU, memory, network, and failure
    behavior.
17. Hot keys, hash tags, and tenant skew can waste aggregate capacity.
18. Replication, full sync, persistence, and backup consume capacity.
19. A production design must satisfy N-1 failure conditions.
20. Replicas must be sized for promotion, not only replication.
21. Failover adds reconnect and recovery pressure.
22. Active-Active capacity must include regional failover and catch-up.
23. Scale vertically or horizontally according to the actual bottleneck.
24. Capacity triggers should include trends, forecasts, SLOs, and lead
    time.
25. Production readiness requires representative load, soak, failover,
    recovery, and N-1 testing.

------------------------------------------------------------------------

# 124. References

Validate exact Redis Enterprise sizing, shard, node, memory,
replication, persistence, and scaling behavior against the deployed
version and infrastructure platform.

Recommended official documentation areas:

-   Redis Enterprise sizing
-   Redis Enterprise cluster architecture
-   Redis Enterprise database memory
-   Redis Enterprise shards
-   Redis Enterprise node management
-   Redis Enterprise scaling
-   Redis Enterprise replication
-   Redis Enterprise persistence
-   Redis Enterprise backup
-   Redis Enterprise Active-Active sizing
-   Redis memory optimization
-   Redis pipelining
-   Redis latency
-   Redis benchmarking
-   Redis client connection management
-   Kubernetes/cloud infrastructure capacity guidance

------------------------------------------------------------------------

# Next Chapter

**Chapter 42 --- Redis Enterprise Upgrades, Maintenance & Change
Engineering**

Chapter 42 will cover:

-   version inventory
-   release planning
-   compatibility
-   upgrade paths
-   prechecks
-   backup/recovery readiness
-   capacity headroom
-   rolling maintenance
-   node/database sequencing
-   client compatibility
-   module compatibility
-   certificate/security dependencies
-   change windows
-   rollback
-   failure injection
-   observability
-   troubleshooting
-   production upgrade runbooks
-   post-change validation
