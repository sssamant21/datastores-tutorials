# Chapter 47 --- Redis Enterprise Production Capacity Planning, Forecasting & Scaling Engineering

**Status:** Canonical\
**Track:** Redis Enterprise / Redis Software Production Engineering\
**Part:** Part 7 --- Platform, Kubernetes & Cloud Operations\
**Level:** Advanced → Production Capacity & Scaling Engineering\
**Audience:** SREs, DBREs, Platform Engineers, Capacity Engineers, Redis
Administrators, Application Owners\
**Lab type:** Workload baselining, memory/CPU/network/connection
modeling, dataset-growth forecasting, shard analysis, N-1/N-2 failure
capacity, seasonal forecasting, load and soak testing,
failover-under-load, scaling rehearsal, troubleshooting, runbooks,
capacity review, and production acceptance

------------------------------------------------------------------------

# 1. Objective

Capacity planning is not:

``` text
CPU is below 80%
therefore the cluster is safe
```

Production capacity must answer:

``` text
Can Redis handle today's peak?
Can it handle tomorrow's growth?
Can it survive a failure?
Can it recover while serving traffic?
Can it survive maintenance?
Can it absorb a traffic event?
```

A useful model is:

``` text
required capacity
=
normal peak
+ failure overhead
+ recovery overhead
+ growth
+ safety headroom
```

By the end of this chapter, you should be able to:

-   establish a production workload baseline;
-   forecast dataset and traffic growth;
-   model memory requirements;
-   model CPU demand;
-   model network throughput;
-   calculate connection budgets;
-   evaluate shard capacity and workload skew;
-   validate N-1 and selected N-2 scenarios;
-   distinguish scale-up from scale-out;
-   define evidence-based scaling triggers;
-   test failover under load;
-   perform soak tests;
-   build capacity dashboards;
-   run recurring capacity reviews;
-   operate scaling runbooks;
-   validate production capacity before growth becomes an incident.

------------------------------------------------------------------------

# 2. Core Production Principle

Size for:

``` text
peak + failure + recovery
```

not:

``` text
average steady state
```

------------------------------------------------------------------------

# Part 1 --- Capacity Dimensions

## 3. Model Independently

Track at least:

``` text
memory
CPU
operations/sec
network
connections
shards
storage
replication
persistence
backup
recovery
```

Passing one dimension does not mean the cluster has sufficient total
capacity.

------------------------------------------------------------------------

# Part 2 --- Workload Baseline

## 4. Record

For representative peak periods capture:

``` text
ops/sec
read/write ratio
command mix
P50/P95/P99 latency
key count
dataset size
average value size
large-value distribution
connections
network bytes/sec
hit ratio
evictions
expirations
replication
persistence activity
```

------------------------------------------------------------------------

# Part 3 --- Peak vs. Average

## 5. Why It Matters

Example:

``` text
average = 40k ops/sec
daily peak = 95k ops/sec
event peak = 150k ops/sec
```

Sizing from 40k can produce an avoidable incident.

------------------------------------------------------------------------

# Part 4 --- Peak Window

## 6. Define

Document:

``` text
normal peak
daily peak
weekly peak
month-end peak
batch peak
seasonal/event peak
```

Use business workload knowledge, not metrics alone.

------------------------------------------------------------------------

# Part 5 --- Command Mix

## 7. Not All Ops Are Equal

A workload of:

``` text
GET small value
```

is not equivalent to:

``` text
large HASH operations
Lua scripts
large values
Streams operations
```

Capacity testing must reproduce the real command mix.

------------------------------------------------------------------------

# Part 6 --- Read/Write Ratio

## 8. Record

Example:

``` text
reads 85%
writes 15%
```

Write growth can increase:

``` text
replication traffic
persistence pressure
backup change rate
Active-Active traffic
```

------------------------------------------------------------------------

# Part 7 --- Key Distribution

## 9. Skew

Capacity depends on whether traffic is:

``` text
evenly distributed
or
concentrated on hot keys/shards
```

Cluster-wide average CPU can hide a saturated shard.

------------------------------------------------------------------------

# Part 8 --- Value Size Distribution

## 10. Measure Percentiles

Record:

``` text
P50 value size
P95
P99
largest expected values
```

Average value size alone hides large-object risk.

------------------------------------------------------------------------

# Part 9 --- Dataset Growth

## 11. Track

Measure:

``` text
keys/day
bytes/day
bytes/week
bytes/month
```

Separate organic growth from temporary spikes.

------------------------------------------------------------------------

# Part 10 --- Dataset Forecast

## 12. Simple Model

For approximately linear growth:

``` text
future dataset
=
current dataset
+
daily growth × forecast days
```

Example:

``` text
current = 500 GB
growth = 4 GB/day
90 days = 360 GB

forecast ≈ 860 GB
```

Then add operational overhead and headroom separately.

------------------------------------------------------------------------

# Part 11 --- Nonlinear Growth

## 13. Beware

Growth may accelerate because of:

``` text
new customers
new feature
longer retention
larger payloads
traffic migration
new data source
```

Do not blindly extrapolate a short historical window.

------------------------------------------------------------------------

# Part 12 --- Retention

## 14. TTL Effect

Dataset size depends on:

``` text
ingestion rate
value size
TTL/retention
expiration behavior
```

Changing TTL can materially change memory requirements.

------------------------------------------------------------------------

# Part 13 --- Memory Model

## 15. Concept

``` text
required memory
≈
logical dataset
+ Redis data-structure overhead
+ allocator/fragmentation effects
+ client/replication buffers
+ persistence/recovery allowance
+ platform overhead
+ safety headroom
```

Do not size from source-system serialized data alone.

------------------------------------------------------------------------

# Part 14 --- Actual Redis Memory

## 16. Measure

Use Redis Enterprise/product metrics and supported Redis metrics to
observe actual memory consumption.

Useful concepts include:

``` text
used memory
RSS
fragmentation
database memory
evictions
```

Use the metrics exposed by your deployed version.

------------------------------------------------------------------------

# Part 15 --- Memory per Key

## 17. Estimate

A useful empirical estimate:

``` text
memory per key
≈
observed Redis memory / representative key count
```

Use representative production-like data.

Do not assume payload bytes equal Redis memory bytes.

------------------------------------------------------------------------

# Part 16 --- Fragmentation

## 18. Include

Allocator behavior can cause process memory to exceed logical data
usage.

Track the actual relationship over time rather than assuming a universal
fragmentation percentage.

------------------------------------------------------------------------

# Part 17 --- Buffers

## 19. Dynamic Memory

Memory can also be consumed by:

``` text
client buffers
replication buffers
output buffers
background operations
```

Peak connection/recovery behavior matters.

------------------------------------------------------------------------

# Part 18 --- Persistence Memory

## 20. Headroom

Persistence mechanisms may require temporary memory/headroom depending
on Redis Enterprise architecture and configured persistence.

Capacity tests should include persistence enabled exactly as production
uses it.

------------------------------------------------------------------------

# Part 19 --- Recovery Memory

## 21. Failure Scenario

Replica synchronization/recovery can change memory and network pressure.

Validate recovery while production traffic continues.

------------------------------------------------------------------------

# Part 20 --- Eviction

## 22. Capacity Signal

If a cache is intentionally configured for eviction, evictions may be
expected.

But increasing eviction rate can indicate that the working set no longer
fits the intended capacity envelope.

------------------------------------------------------------------------

# Part 21 --- Authoritative Data

## 23. Different Risk

For Redis workloads where data must not be discarded, memory exhaustion
has different consequences.

Capacity and persistence design must reflect the workload's data-loss
tolerance.

------------------------------------------------------------------------

# Part 22 --- CPU Model

## 24. Measure, Do Not Guess

CPU demand depends on:

``` text
ops/sec
command mix
value size
TLS
Lua
data structures
replication
persistence
background operations
```

Use measured workload tests.

------------------------------------------------------------------------

# Part 23 --- CPU Scaling Curve

## 25. Test

Increase workload gradually and record:

``` text
ops/sec
CPU
P50
P95
P99
errors
```

Look for the point where latency grows disproportionately.

------------------------------------------------------------------------

# Part 24 --- Saturation Knee

## 26. Concept

A system often has a region where:

``` text
small traffic increase
->
large latency increase
```

That is more useful for capacity planning than an arbitrary CPU
threshold.

------------------------------------------------------------------------

# Part 25 --- Per-Shard CPU

## 27. Critical

Evaluate:

``` text
cluster CPU
node CPU
shard CPU
```

A single hot shard can hit its practical limit while cluster-wide CPU
looks comfortable.

------------------------------------------------------------------------

# Part 26 --- Single-Threaded Execution Characteristics

## 28. Workload Awareness

Redis command execution characteristics make per-shard/per-core behavior
important for many workloads.

Redis Enterprise architecture can distribute work across shards, but a
hot key or skewed shard can still become the limiting resource.

------------------------------------------------------------------------

# Part 27 --- Ops/sec

## 29. Not a Universal Number

There is no single safe Redis ops/sec limit.

Capacity depends on:

``` text
commands
values
CPU
network
shards
persistence
TLS
topology
```

Benchmark your workload.

------------------------------------------------------------------------

# Part 28 --- Network Model

## 30. Approximation

``` text
client network
≈
ops/sec × average request/response bytes
```

Then add:

``` text
replication
backup
recovery
Active-Active
management
```

------------------------------------------------------------------------

# Part 29 --- Peak Network

## 31. Measure

Track:

``` text
bytes/sec
packets/sec where available
errors/drops
```

High small-request rates may become packet-rate constrained.

------------------------------------------------------------------------

# Part 30 --- Replication Network

## 32. Writes

Write-heavy workloads increase replication demand.

A failure can further increase network usage during synchronization.

------------------------------------------------------------------------

# Part 31 --- Active-Active Network

## 33. Geo

For Active-Active, account for:

``` text
regional writes
replication amplification
inter-region bandwidth
catch-up after partition
```

------------------------------------------------------------------------

# Part 32 --- Connection Budget

## 34. Formula

A simple application-side estimate:

``` text
connections
≈
application instances
× workers per instance
× pool size
```

Then add:

``` text
admin
monitoring
automation
failover/reconnect headroom
```

------------------------------------------------------------------------

# Part 33 --- Autoscaling Applications

## 35. Hidden Multiplier

Example:

``` text
20 app pods × 20 connections = 400

autoscale to 100 pods:
100 × 20 = 2,000 connections
```

Redis capacity planning must include maximum application scale.

------------------------------------------------------------------------

# Part 34 --- Connection Storm Capacity

## 36. Test

Steady-state connection count is not enough.

Test:

``` text
connections/sec
TLS handshakes/sec
reconnect after failover
```

------------------------------------------------------------------------

# Part 35 --- Shard Capacity

## 37. Dimensions

Shard decisions depend on:

``` text
dataset
throughput
CPU
hot-key distribution
recovery
failover
management overhead
```

------------------------------------------------------------------------

# Part 36 --- More Shards Are Not Free

## 38. Tradeoff

Additional shards can improve distribution but add:

``` text
management overhead
replication overhead
recovery work
complexity
```

Use workload evidence.

------------------------------------------------------------------------

# Part 37 --- Too Few Shards

## 39. Risk

Possible symptoms:

``` text
per-shard CPU saturation
large recovery units
uneven traffic
limited parallelism
```

------------------------------------------------------------------------

# Part 38 --- Hot Key

## 40. Scaling Limit

Adding nodes or shards may not fix a workload dominated by one hot key.

The application/data model may need redesign.

------------------------------------------------------------------------

# Part 39 --- Hot Shard

## 41. Detect

Compare per-shard:

``` text
CPU
ops/sec
latency
memory
```

against cluster averages.

------------------------------------------------------------------------

# Part 40 --- Scale Up

## 42. Vertical

Scale-up means increasing resources per infrastructure unit:

``` text
CPU
RAM
network capability
```

Advantages can include simpler topology.

Limits include maximum instance size and failure-domain concentration.

------------------------------------------------------------------------

# Part 41 --- Scale Out

## 43. Horizontal

Scale-out adds infrastructure/shard capacity.

Benefits may include:

``` text
more aggregate CPU
more memory
failure distribution
```

but requires supported Redis Enterprise scaling/rebalancing procedures.

------------------------------------------------------------------------

# Part 42 --- Scale Up vs. Scale Out

## 44. Decision Inputs

Evaluate:

``` text
memory pressure
CPU pressure
shard skew
network
failure-domain design
recovery time
cost
operational complexity
```

------------------------------------------------------------------------

# Part 43 --- Scaling Does Not Fix Everything

## 45. Examples

Scaling may not fix:

``` text
hot single key
bad Lua script
connection leak
retry storm
oversized values
poor TTL strategy
network path issue
```

Diagnose first.

------------------------------------------------------------------------

# Part 44 --- Failure Capacity

## 46. N-1

Model the loss of one relevant infrastructure component.

Example:

``` text
normal total capacity = 4 nodes
one node lost = 3 nodes

Can 3 nodes:
serve peak traffic
+
perform recovery
+
retain headroom?
```

------------------------------------------------------------------------

# Part 45 --- N-2

## 47. Selected Scenarios

N-2 is not universally required, but selected scenarios may be
appropriate for critical systems.

Examples:

``` text
one node already in maintenance + another fails
zone impairment + node issue
```

Document the business/SLO requirement.

------------------------------------------------------------------------

# Part 46 --- Zone Failure

## 48. Model

For multi-zone deployments, calculate capacity after losing the intended
zone failure domain.

Do not assume node-level N-1 proves zone-level resilience.

------------------------------------------------------------------------

# Part 47 --- Region Failure

## 49. Active-Active / DR

For multi-region architectures, determine whether surviving regions are
expected to absorb:

``` text
traffic
writes
connections
replication catch-up later
```

Size accordingly.

------------------------------------------------------------------------

# Part 48 --- Maintenance Capacity

## 50. Planned Degradation

Maintenance can temporarily remove capacity.

Production peak should still fit within the planned maintenance
topology.

------------------------------------------------------------------------

# Part 49 --- Recovery Capacity

## 51. Often Forgotten

After failure, Redis may simultaneously:

``` text
serve production
reconnect clients
synchronize replicas
rebalance
persist
```

Capacity tests should reproduce this combined state.

------------------------------------------------------------------------

# Part 50 --- Backup Capacity

## 52. Include

Backups may consume:

``` text
CPU
network
storage
```

Measure production impact during normal backup windows.

------------------------------------------------------------------------

# Part 51 --- Forecast Horizon

## 53. Define

Common operational horizons can include:

``` text
30 days
90 days
6 months
12 months
```

Choose horizons based on procurement/change lead time.

------------------------------------------------------------------------

# Part 52 --- Time to Exhaustion

## 54. Simple Estimate

``` text
days to threshold
=
remaining usable capacity / daily growth
```

This is useful only if growth is approximately linear.

------------------------------------------------------------------------

# Part 53 --- Seasonality

## 55. Model

Include known events:

``` text
month end
quarter end
holidays
campaigns
enrollment
batch windows
product launches
```

------------------------------------------------------------------------

# Part 54 --- New Workload

## 56. Capacity Review

Before onboarding a major workload, estimate:

``` text
dataset
growth
ops/sec
command mix
connections
network
TTL
persistence
availability requirement
```

------------------------------------------------------------------------

# Part 55 --- Migration

## 57. Temporary Capacity

Migrations can temporarily increase:

``` text
writes
memory
network
replication
backup
```

Include migration headroom.

------------------------------------------------------------------------

# Part 56 --- Load Testing

## 58. Representative

A useful load test reproduces:

``` text
command mix
key distribution
value sizes
connections
TLS
TTL
read/write ratio
pipelining
persistence
replication
```

------------------------------------------------------------------------

# Part 57 --- Synthetic vs. Replay

## 59. Options

Synthetic tests are controlled and repeatable.

Sanitized workload replay can improve realism where permitted.

Protect sensitive data.

------------------------------------------------------------------------

# Part 58 --- Ramp Test

## 60. Procedure

Increase load in controlled steps:

``` text
25%
50%
75%
100%
125%
...
```

At each step record latency, errors, CPU, memory, network, and shard
distribution.

Stop at defined safety gates.

------------------------------------------------------------------------

# Part 59 --- Soak Test

## 61. Purpose

A short benchmark can miss:

``` text
memory growth
connection leak
fragmentation
background cycles
backup interaction
thermal/credit behavior
```

Run a sustained representative test.

------------------------------------------------------------------------

# Part 60 --- Failover Under Load

## 62. Required

Test failover while realistic traffic continues.

Measure:

``` text
error spike
P99
reconnect
recovery
replication
time to stable state
```

------------------------------------------------------------------------

# Part 61 --- Recovery Under Load

## 63. Stronger Test

After failover, continue load while redundancy is rebuilt.

This validates the true recovery capacity envelope.

------------------------------------------------------------------------

# Part 62 --- Backup Under Load

## 64. Test

Run the supported backup process during representative traffic.

Compare:

``` text
P99
CPU
network
storage
```

against baseline.

------------------------------------------------------------------------

# Part 63 --- Persistence Under Load

## 65. Test

Use production-equivalent persistence settings during capacity tests.

Otherwise the benchmark is incomplete.

------------------------------------------------------------------------

# Part 64 --- Reconnect Test

## 66. Client Fleet

Test bounded simultaneous reconnects.

Verify:

``` text
retry backoff
jitter
connection pool behavior
TLS cost
Redis connection acceptance
```

------------------------------------------------------------------------

# Part 65 --- Scaling Rehearsal

## 67. Nonproduction

Rehearse the exact supported scale-up/scale-out workflow before
emergency use.

Measure:

``` text
change duration
rebalance/recovery
application impact
rollback/recovery
```

------------------------------------------------------------------------

# Part 66 --- Scaling Trigger

## 68. Evidence-Based

A trigger should combine:

``` text
trend
peak utilization
latency/SLO
failure headroom
growth horizon
change lead time
```

Do not rely on one universal percentage.

------------------------------------------------------------------------

# Part 67 --- Memory Trigger

## 69. Example Logic

Scale before projected memory growth consumes required
operational/failure headroom.

The exact threshold should be derived from the workload and topology.

------------------------------------------------------------------------

# Part 68 --- CPU Trigger

## 70. Example Logic

Scale when representative peak CPU approaches the measured saturation
knee or failure topology cannot meet the SLO.

------------------------------------------------------------------------

# Part 69 --- Network Trigger

## 71. Example Logic

Scale/redesign when peak traffic plus recovery/replication approaches
the validated network envelope.

------------------------------------------------------------------------

# Part 70 --- Connection Trigger

## 72. Example Logic

Scale or redesign pools when maximum application fleet plus reconnect
headroom approaches validated connection capacity.

------------------------------------------------------------------------

# Part 71 --- Shard Trigger

## 73. Example Logic

Review scaling when per-shard CPU/memory/recovery behavior approaches
validated workload limits even if cluster averages remain low.

------------------------------------------------------------------------

# Part 72 --- Capacity Dashboard

## 74. Include

Recommended panels:

``` text
dataset
memory/headroom
ops/sec
P95/P99
CPU by node/shard
connections
network
replication
evictions
persistence
growth rate
forecasted exhaustion
```

------------------------------------------------------------------------

# Part 73 --- Capacity Alerts

## 75. Actionable

Alerts should answer:

``` text
what resource?
what trend?
what forecast?
what failure headroom remains?
what action is required?
```

------------------------------------------------------------------------

# Part 74 --- Forecast Alert

## 76. Better Than Last-Minute

Example:

``` text
projected capacity breach within change lead time
```

is more actionable than waiting for exhaustion.

------------------------------------------------------------------------

# Part 75 --- Capacity Review Cadence

## 77. Recurring

Perform capacity reviews at a cadence appropriate to growth.

Fast-growing systems may require weekly review; stable systems may use
monthly or quarterly review.

------------------------------------------------------------------------

# Part 76 --- Capacity Review Inputs

## 78. Bring

``` text
current peak
30/90-day trend
growth forecast
failure capacity
recent incidents
upcoming launches
migration plans
maintenance
cost
```

------------------------------------------------------------------------

# Part 77 --- Ownership

## 79. Shared

Capacity is shared between:

``` text
Redis/SRE
platform/cloud
application
product/business
```

Application growth assumptions must be visible to infrastructure owners.

------------------------------------------------------------------------

# Part 78 --- Capacity Decision Record

## 80. Document

``` text
current state
forecast
risk
options
decision
owner
deadline
validation plan
```

------------------------------------------------------------------------

# Part 79 --- Cost Model

## 81. Include Reliability

Compare options by:

``` text
cost
SLO
failure capacity
growth runway
operational complexity
```

Cheapest steady-state configuration may not be cheapest operationally.

------------------------------------------------------------------------

# Part 80 --- Over-Provisioning

## 82. Balance

Excessive unused capacity wastes cost.

Insufficient headroom creates incident risk.

Use measured failure/recovery requirements to justify headroom.

------------------------------------------------------------------------

# Part 81 --- Hands-On Lab Safety

## 83. Environment

Run load, failure, and scaling tests in an approved nonproduction
environment unless an explicitly approved production test plan exists.

Do not discover maximum capacity by crashing production.

------------------------------------------------------------------------

# Part 82 --- Lab: Capture Baseline

## 84. Record

Create:

  Metric          Normal   Peak
  ------------- -------- ------
  Ops/sec                
  P95                    
  P99                    
  CPU                    
  Memory                 
  Connections            
  Network                
  Dataset                

------------------------------------------------------------------------

# Part 83 --- Lab: Dataset Growth

## 85. Calculate

Collect dataset size for multiple historical points.

Calculate:

``` text
daily growth
weekly growth
30-day forecast
90-day forecast
```

Identify whether growth is linear.

------------------------------------------------------------------------

# Part 84 --- Lab: Memory per Key

## 86. Estimate

Using representative data:

``` text
memory_per_key
=
observed Redis memory / key count
```

Compare across different data structures/value sizes.

------------------------------------------------------------------------

# Part 85 --- Lab: Connection Budget

## 87. Calculate

Example:

``` text
app instances = 60
workers = 4
pool = 8

estimated app connections
=
60 × 4 × 8
=
1,920
```

Then add monitoring/admin/reconnect allowance.

------------------------------------------------------------------------

# Part 86 --- Lab: Network Estimate

## 88. Calculate

Example:

``` text
peak ops/sec = 100,000
average total request+response = 1.5 KB

client traffic
≈ 150 MB/sec
```

Treat this as an approximation and validate against measured metrics.

------------------------------------------------------------------------

# Part 87 --- Lab: Ramp Test

## 89. Execute

At controlled stages record:

  Load     Ops/sec   CPU   P95   P99   Errors
  ------ --------- ----- ----- ----- --------
  25%                                
  50%                                
  75%                                
  100%                               
  125%                               

Stop at safety thresholds.

------------------------------------------------------------------------

# Part 88 --- Lab: Saturation Knee

## 90. Identify

Plot or compare:

``` text
load
vs.
P99
```

Find where incremental load causes disproportionate latency growth.

------------------------------------------------------------------------

# Part 89 --- Lab: Shard Skew

## 91. Compare

For each shard collect:

``` text
CPU
ops/sec
memory
latency
```

Calculate:

``` text
max shard / average shard
```

Use the result as a skew indicator, not a universal pass/fail threshold.

------------------------------------------------------------------------

# Part 90 --- Lab: N-1

## 92. Calculate

For a disposable test topology, model one component unavailable.

Record:

``` text
remaining CPU
remaining memory
remaining network
expected peak
recovery overhead
```

Then test through the supported failure procedure.

------------------------------------------------------------------------

# Part 91 --- Lab: Selected N-2

## 93. Model First

Choose a realistic approved scenario.

Example:

``` text
one node under maintenance
+
second node failure
```

Determine expected behavior before any test.

------------------------------------------------------------------------

# Part 92 --- Lab: Failover Under Load

## 94. Measure

Run representative load and initiate an approved failover.

Capture:

``` text
P99
errors
connections
reconnect time
replication
time to stable
```

------------------------------------------------------------------------

# Part 93 --- Lab: Recovery Under Load

## 95. Continue

Do not stop measurement immediately after failover.

Continue until:

``` text
redundancy restored
replication stable
latency normal
```

------------------------------------------------------------------------

# Part 94 --- Lab: Soak Test

## 96. Observe

Run representative load for a sustained period.

Track:

``` text
memory trend
fragmentation
connections
CPU
P99
network
persistence cycles
```

------------------------------------------------------------------------

# Part 95 --- Lab: Scale-Up Rehearsal

## 97. Test

Use the supported Redis Enterprise/platform procedure.

Measure:

``` text
duration
service impact
resource change
recovery
```

------------------------------------------------------------------------

# Part 96 --- Lab: Scale-Out Rehearsal

## 98. Test

Use supported Redis Enterprise procedures.

Observe:

``` text
new capacity
data movement/rebalance
CPU
network
P99
time to stable
```

------------------------------------------------------------------------

# Part 97 --- Failure Injection

## 99. Ten Scenarios

1.  Traffic exceeds normal peak.
2.  Dataset growth consumes memory headroom.
3.  One Redis infrastructure node fails at peak.
4.  Selected N-2 degradation.
5.  Hot shard saturates while cluster average is healthy.
6.  Application autoscaling multiplies connections.
7.  Network demand spikes during replica recovery.
8.  Backup overlaps peak traffic.
9.  Seasonal event exceeds forecast.
10. Scale operation occurs while production traffic continues.

For each record:

``` text
detection
capacity dimension
application impact
Redis impact
mitigation
recovery
future scaling action
```

------------------------------------------------------------------------

# Part 98 --- Troubleshooting Matrix

## 100. Capacity Symptoms

  Symptom               Capacity Checks
  --------------------- --------------------------------------------
  Rising P99 at peak    CPU/shard saturation, network, command mix
  Evictions rising      memory/working set/TTL
  OOM risk              dataset growth, buffers, headroom
  Hot shard             key distribution, per-shard CPU
  Connection failures   fleet size, pool, reconnect rate
  Replication lag       CPU/network/recovery load
  Backup impacts P99    CPU/network/storage overlap
  Failover unstable     N-1 capacity, reconnect, recovery
  Scale-out slow        data movement/network/CPU
  Forecast breach       growth rate, lead time, planned demand

------------------------------------------------------------------------

# Part 99 --- Runbook 1: Memory Capacity Exhaustion

## 101. Procedure

``` text
1. Confirm memory trend.
2. Identify dataset/key growth.
3. Check TTL/retention changes.
4. Check fragmentation/buffers.
5. Check eviction behavior.
6. Confirm failure headroom.
7. Stop unexpected growth if appropriate.
8. Scale using approved procedure.
9. Validate memory/P99.
10. Update forecast and trigger.
```

------------------------------------------------------------------------

# Part 100 --- Runbook 2: CPU Capacity Exhaustion

## 102. Procedure

``` text
1. Confirm peak CPU and P99.
2. Check per-node/per-shard CPU.
3. Identify command mix.
4. Check hot keys/shards.
5. Check background/persistence work.
6. Compare with measured saturation knee.
7. Reduce abnormal load if possible.
8. Scale or redesign workload.
9. Validate SLO.
10. Update capacity model.
```

------------------------------------------------------------------------

# Part 101 --- Runbook 3: Connection Capacity

## 103. Procedure

``` text
1. Confirm connection count/rate.
2. Identify application fleet size.
3. Check pool configuration.
4. Check connection leaks.
5. Check recent autoscaling.
6. Check reconnect storm.
7. Stabilize retry/pool behavior.
8. Scale only if required.
9. Validate connections/P99.
10. Update connection budget.
```

------------------------------------------------------------------------

# Part 102 --- Runbook 4: Hot Shard Capacity

## 104. Procedure

``` text
1. Compare per-shard CPU/ops.
2. Identify hot keys/workload.
3. Check key distribution.
4. Check command/value size.
5. Determine whether scaling redistributes load.
6. Apply application/data-model mitigation where needed.
7. Scale through supported procedure if justified.
8. Validate shard balance.
9. Validate P99.
10. Update workload model.
```

------------------------------------------------------------------------

# Part 103 --- Runbook 5: N-1 Capacity Failure

## 105. Procedure

``` text
1. Confirm failed component.
2. Protect application traffic.
3. Measure remaining CPU/memory/network.
4. Check failover/recovery.
5. Control retry/reconnect amplification.
6. Delay nonessential heavy work.
7. Restore capacity.
8. Restore redundancy.
9. Validate peak/failure headroom.
10. Correct capacity plan.
```

------------------------------------------------------------------------

# Part 104 --- Runbook 6: Forecasted Capacity Breach

## 106. Procedure

``` text
1. Confirm trend quality.
2. Calculate time to required threshold.
3. Include planned launches/seasonality.
4. Include failure headroom.
5. Compare scale-up/scale-out options.
6. Confirm change/procurement lead time.
7. Approve scaling plan.
8. Rehearse where appropriate.
9. Scale before risk window.
10. Rebaseline after change.
```

------------------------------------------------------------------------

# Part 105 --- Runbook 7: Emergency Scale

## 107. Procedure

``` text
1. Confirm true capacity bottleneck.
2. Preserve incident evidence.
3. Select fastest supported safe scaling path.
4. Confirm failure/recovery implications.
5. Apply approved emergency change.
6. Monitor P99/errors.
7. Monitor rebalance/recovery.
8. Validate steady state.
9. Complete post-incident capacity review.
10. Replace emergency action with durable design if needed.
```

------------------------------------------------------------------------

# Part 106 --- Capacity Review Template

## 108. Record

``` text
Environment:
Review date:
Owner:
Current dataset:
30-day growth:
90-day forecast:
Peak ops/sec:
Peak P99:
Peak CPU:
Peak memory:
Peak connections:
Peak network:
Hot-shard status:
N-1 status:
Selected N-2 status:
Backup impact:
Upcoming workload:
Scaling lead time:
Decision:
Action owner:
Due date:
```

------------------------------------------------------------------------

# Part 107 --- Forecast Table

## 109. Record

  Metric          Current   30 Days   90 Days   Limit/Envelope Action Date
  ------------- --------- --------- --------- ---------------- -------------
  Dataset                                                      
  Memory                                                       
  Ops/sec                                                      
  CPU                                                          
  Connections                                                  
  Network                                                      

------------------------------------------------------------------------

# Part 108 --- Failure Capacity Table

## 110. Record

  Scenario       CPU   Memory   Network   SLO   Status
  -------------- ----- -------- --------- ----- --------
  Normal peak                                   
  N-1 node                                      
  Zone failure                                  
  Maintenance                                   
  Recovery                                      
  Selected N-2                                  

------------------------------------------------------------------------

# Part 109 --- Scaling Decision Template

## 111. Record

``` text
Bottleneck:
Evidence:
Current envelope:
Forecast:
Failure headroom:
Option A - scale up:
Option B - scale out:
Application redesign required?:
Cost:
Risk:
Change duration:
Validation:
Decision:
```

------------------------------------------------------------------------

# Part 110 --- Load-Test Acceptance Template

## 112. Record

``` text
Workload:
Dataset:
Command mix:
Value distribution:
Connections:
TLS:
Persistence:
Replication:
Peak target:
Failure scenario:
P95:
P99:
Error rate:
CPU:
Memory:
Network:
Recovery time:
PASS/FAIL:
```

------------------------------------------------------------------------

# Part 111 --- Production Acceptance Checklist

## 113. Capacity Engineering

-   [ ] Representative workload baseline captured.
-   [ ] Normal and peak traffic separated.
-   [ ] Command mix documented.
-   [ ] Read/write ratio documented.
-   [ ] Value-size distribution measured.
-   [ ] Key/workload skew analyzed.
-   [ ] Dataset growth measured.
-   [ ] 30/90-day forecast available.
-   [ ] TTL/retention impact modeled.
-   [ ] Actual Redis memory measured.
-   [ ] Memory overhead/headroom modeled.
-   [ ] Fragmentation trend reviewed.
-   [ ] CPU scaling curve measured.
-   [ ] Saturation knee identified.
-   [ ] Per-shard CPU monitored.
-   [ ] Peak ops/sec validated.
-   [ ] Network demand measured.
-   [ ] Replication/recovery network included.
-   [ ] Connection budget calculated.
-   [ ] Maximum application autoscale included.
-   [ ] Reconnect capacity tested.
-   [ ] Shard capacity/skew reviewed.
-   [ ] Scale-up and scale-out criteria documented.
-   [ ] N-1 capacity validated.
-   [ ] Relevant zone-failure capacity validated.
-   [ ] Selected N-2 requirement documented.
-   [ ] Maintenance capacity validated.
-   [ ] Recovery capacity validated.
-   [ ] Backup-under-load impact measured.
-   [ ] Forecast horizon matches change lead time.
-   [ ] Seasonality/business events included.
-   [ ] Representative ramp test completed.
-   [ ] Soak test completed.
-   [ ] Failover-under-load completed.
-   [ ] Recovery-under-load completed.
-   [ ] Scaling rehearsal completed.
-   [ ] Evidence-based scaling triggers defined.
-   [ ] Capacity dashboard available.
-   [ ] Capacity review cadence assigned.
-   [ ] Seven production runbooks reviewed.
-   [ ] Ten failure scenarios exercised.

------------------------------------------------------------------------

# Knowledge Validation

## 114. Questions

1.  Why is average utilization insufficient for capacity planning?
2.  What capacity dimensions should be tracked independently?
3.  Why does command mix matter?
4.  Why measure value-size percentiles?
5.  How does TTL affect dataset capacity?
6.  Why is source payload size not equal to Redis memory usage?
7.  What dynamic buffers consume memory?
8.  Why must persistence/recovery be included in memory tests?
9.  What is the CPU saturation knee?
10. Why is per-shard CPU important?
11. Why is there no universal safe ops/sec number?
12. How can a hot key limit scaling?
13. What does a connection budget include?
14. How can application autoscaling surprise Redis?
15. Why test reconnect rate as well as connection count?
16. What tradeoff comes with adding shards?
17. What is scale-up?
18. What is scale-out?
19. Why can scaling fail to fix a workload problem?
20. What is N-1 capacity?
21. When might selected N-2 analysis be useful?
22. Why is maintenance a capacity scenario?
23. Why is recovery capacity different from steady state?
24. Why should backup be included in capacity testing?
25. Why must forecast horizon reflect change lead time?
26. Why include seasonality?
27. What makes a load test representative?
28. Why run a soak test?
29. Why test failover and recovery under load?
30. What must pass before Redis capacity is production-ready?

------------------------------------------------------------------------

# Hands-On Acceptance Checklist

## 115. Lab Completion

-   [ ] Captured workload baseline.
-   [ ] Calculated dataset growth.
-   [ ] Estimated memory per key.
-   [ ] Calculated connection budget.
-   [ ] Estimated network demand.
-   [ ] Completed ramp test.
-   [ ] Identified saturation knee.
-   [ ] Measured shard skew.
-   [ ] Modeled N-1.
-   [ ] Modeled selected N-2 where required.
-   [ ] Tested failover under load.
-   [ ] Tested recovery under load.
-   [ ] Completed soak test.
-   [ ] Rehearsed scale-up.
-   [ ] Rehearsed scale-out.
-   [ ] Exercised ten failure scenarios.
-   [ ] Used troubleshooting matrix.
-   [ ] Reviewed seven production runbooks.
-   [ ] Completed capacity review template.
-   [ ] Completed forecast table.
-   [ ] Completed failure-capacity table.
-   [ ] Completed scaling decision template.
-   [ ] Completed load-test acceptance record.
-   [ ] Completed production acceptance checklist.

------------------------------------------------------------------------

# 116. Lab Cleanup

Stop all Chapter 47 load generators and disposable clients.

Remove only lab keys:

``` bash
redis-cli --scan --pattern 'tutorial:chapter47:*'
```

Review matches before deletion:

``` redis
UNLINK <confirmed-key>
```

Remove disposable:

``` text
load-test jobs
temporary scaling resources
test dashboards
temporary alerts
test infrastructure
```

Restore any intentionally modified nonproduction topology through the
supported Redis Enterprise procedure.

Never use:

``` redis
FLUSHDB
FLUSHALL
```

against a shared or production database.

------------------------------------------------------------------------

# 117. Key Takeaways

1.  Capacity planning must use peak, failure, recovery, and growth---not
    averages.
2.  Memory, CPU, network, connections, shards, and storage are separate
    capacity dimensions.
3.  Workload command mix and value distribution matter as much as
    ops/sec.
4.  Dataset growth should be measured and forecast.
5.  Redis memory usage is larger and more dynamic than raw payload size.
6.  Memory planning must include fragmentation, buffers, persistence,
    recovery, and platform overhead.
7.  CPU capacity should be derived from measured workload curves.
8.  The saturation knee is more meaningful than an arbitrary utilization
    threshold.
9.  Per-shard metrics can reveal bottlenecks hidden by cluster averages.
10. A hot key can remain a bottleneck even after infrastructure scaling.
11. Network capacity includes client, replication, recovery, backup, and
    geo traffic.
12. Application autoscaling can multiply Redis connections rapidly.
13. Connection capacity includes reconnect rate, not just steady-state
    count.
14. More shards add capacity but also operational overhead.
15. Scale-up and scale-out solve different problems.
16. Scaling should follow diagnosis, not replace it.
17. N-1 capacity is a production requirement for resilient designs.
18. Selected N-2 scenarios may matter for critical systems.
19. Maintenance consumes failure headroom.
20. Recovery is often more resource-intensive than normal steady state.
21. Load tests must reproduce real commands, values, connections, TLS,
    TTL, persistence, and replication.
22. Soak tests reveal problems short benchmarks miss.
23. Failover must be tested under realistic load.
24. Scaling triggers should combine trends, SLOs, failure headroom, and
    change lead time.
25. Capacity planning is a recurring operational process, not a one-time
    sizing exercise.

------------------------------------------------------------------------

# 118. References

Validate exact Redis Enterprise sizing, shard, scaling, persistence,
replication, and topology behavior against the deployed Redis Enterprise
version and official vendor guidance.

Recommended official documentation areas:

-   Redis Enterprise sizing
-   Redis Enterprise memory management
-   Redis Enterprise database configuration
-   Redis Enterprise clustering and shards
-   Redis Enterprise high availability
-   Redis Enterprise replication
-   Redis Enterprise persistence
-   Redis Enterprise backup and restore
-   Redis Enterprise Active-Active
-   Redis Enterprise monitoring and metrics
-   Redis Enterprise performance
-   Redis Enterprise Kubernetes sizing where applicable
-   Cloud provider compute/network/storage limits
-   Application load-testing and SLO documentation

------------------------------------------------------------------------

# Next Chapter

**Chapter 48 --- Redis Enterprise Backup, Restore, Disaster Recovery &
Recovery Testing Engineering**

Chapter 48 will focus on production recovery operations, including:

-   backup architecture
-   RPO
-   RTO
-   retention
-   backup validation
-   restore testing
-   isolated recovery
-   selective recovery
-   corruption scenarios
-   credential/secret dependencies
-   cross-region recovery
-   DR environment readiness
-   DNS/application cutover
-   failback
-   recovery evidence
-   DR drills
-   recovery runbooks
-   production acceptance
