# Chapter 39 --- Redis Enterprise Observability, Metrics, Alerting & SLO Engineering

**Status:** Canonical\
**Track:** Redis Enterprise / Redis Software Production Engineering\
**Part:** Part 6 --- Observability, Reliability & Production Operations\
**Level:** Advanced → Production Redis Observability Engineering\
**Audience:** SREs, DBREs, Platform Engineers, Redis Administrators,
Developers, Incident Responders\
**Lab type:** Baseline collection, database/node/shard/client telemetry,
latency percentiles, throughput, memory and eviction analysis,
connection saturation, replication/persistence monitoring,
Prometheus/Grafana integration, alert testing, SLI/SLO/error-budget
design, incident correlation, failure injection, troubleshooting,
runbooks, and production acceptance

------------------------------------------------------------------------

# 1. Objective

Monitoring answers:

``` text
What is happening?
```

Observability should help answer:

``` text
Why is it happening?
What changed?
Which layer is responsible?
What should we do next?
```

For Redis Enterprise, a useful operational model is:

``` text
Application
    |
    v
Client / connection pool
    |
    v
Database endpoint
    |
    v
Proxy / routing layer
    |
    v
Shard
    |
    v
Redis Enterprise node
    |
    v
CPU / memory / network / storage
```

A production monitoring system must make it possible to correlate
signals across these layers.

By the end, you should be able to:

-   Build a Redis Enterprise observability model.
-   Define database, node, shard, and client signals.
-   Measure latency percentiles.
-   Monitor throughput and command rate.
-   Monitor memory pressure.
-   Detect eviction and expiration behavior.
-   Monitor connections and pool saturation.
-   Monitor replication and persistence.
-   Identify hot-key and shard-skew symptoms.
-   Integrate Redis Enterprise telemetry with Prometheus/Grafana where
    supported.
-   Build useful dashboards.
-   Design actionable alerts.
-   Define SLIs and SLOs.
-   Use error budgets.
-   Correlate Redis and application incidents.
-   Perform monitoring failure drills.
-   Build production runbooks.

------------------------------------------------------------------------

# 2. Core Production Principle

Do not monitor Redis as one green/red box.

A database can report:

``` text
UP
```

while users experience:

``` text
timeouts
high P99 latency
connection exhaustion
eviction storms
replication lag
hot-shard saturation
```

Availability is only one signal.

------------------------------------------------------------------------

# Part 1 --- Observability Model

## 3. Four Operational Questions

For every Redis incident ask:

``` text
Is Redis available?
Is Redis fast?
Is Redis saturated?
Is Redis correct/current enough?
```

------------------------------------------------------------------------

# Part 2 --- Golden Signals

## 4. Latency

How long operations take.

## 5. Traffic

How much work Redis is processing.

## 6. Errors

How many operations fail.

## 7. Saturation

How close resources are to operational limits.

These provide a strong starting framework.

------------------------------------------------------------------------

# Part 3 --- Scope

## 8. Monitor Multiple Layers

Collect telemetry from:

``` text
application
Redis client
Redis database
Redis shard
Redis Enterprise node
host/container
network
storage
```

A single layer rarely explains a production incident completely.

------------------------------------------------------------------------

# Part 4 --- Application Metrics

## 9. Most Important View

Track:

``` text
Redis request count
Redis error count
timeout count
latency
retries
cache hit/miss
fallback/source latency
```

The application view tells you whether Redis behavior is affecting
users.

------------------------------------------------------------------------

# Part 5 --- Client Metrics

## 10. Connection Pool

Track:

``` text
pool size
active connections
idle connections
pool wait
pool timeout
connection creation rate
reconnects
```

A healthy Redis server cannot compensate for a broken client pool.

------------------------------------------------------------------------

# Part 6 --- Database Metrics

## 11. Core Signals

Track database-level:

``` text
operations/sec
read/write throughput
latency
memory usage
key count
connections
evictions
expirations
errors
```

Use Redis Enterprise-supported metrics for the deployed version.

------------------------------------------------------------------------

# Part 7 --- Node Metrics

## 12. Infrastructure

Track:

``` text
CPU
memory
network
storage
node health
process health
```

Node saturation can affect multiple databases/shards.

------------------------------------------------------------------------

# Part 8 --- Shard Metrics

## 13. Why Shards Matter

Cluster-wide averages can hide one overloaded shard.

Track where supported:

``` text
per-shard CPU
per-shard memory
ops/sec
latency
network
key count
```

------------------------------------------------------------------------

# Part 9 --- Average Is Dangerous

## 14. Example

Suppose four shards have CPU:

``` text
Shard 1 = 20%
Shard 2 = 25%
Shard 3 = 22%
Shard 4 = 95%
```

Average:

``` text
40.5%
```

The average looks comfortable while one shard is saturated.

------------------------------------------------------------------------

# Part 10 --- Latency

## 15. Percentiles

Prefer distributions/percentiles:

``` text
P50
P95
P99
P99.9
```

rather than average alone.

------------------------------------------------------------------------

# Part 11 --- Tail Latency

## 16. User Impact

Averages can hide severe outliers.

Example:

``` text
P50 = 1 ms
P95 = 3 ms
P99 = 50 ms
P99.9 = 500 ms
```

Tail latency may explain user-visible timeouts even when average latency
looks healthy.

------------------------------------------------------------------------

# Part 12 --- Latency Layers

## 17. Decompose

Measure separately:

``` text
application Redis call latency
connection-pool wait
network latency
Redis processing latency
retry time
```

Do not assume every slow Redis call means Redis server execution was
slow.

------------------------------------------------------------------------

# Part 13 --- Throughput

## 18. Operations

Track:

``` text
ops/sec
reads/sec
writes/sec
commands/sec
```

Correlate changes with latency and resource utilization.

------------------------------------------------------------------------

# Part 14 --- Network Throughput

## 19. Bytes Matter

Two workloads with equal command rate can have very different network
cost.

Track:

``` text
bytes in/sec
bytes out/sec
```

Large values can saturate network/client CPU without extreme ops/sec.

------------------------------------------------------------------------

# Part 15 --- Memory

## 20. Track

``` text
used memory
memory limit
headroom
fragmentation/RSS where relevant
key count
value-size distribution where available
```

------------------------------------------------------------------------

# Part 16 --- Memory Headroom

## 21. Capacity

Avoid operating permanently at the memory ceiling.

Headroom supports:

``` text
traffic spikes
replication
persistence/COW
buffers
failover
temporary growth
```

------------------------------------------------------------------------

# Part 17 --- Evictions

## 22. Rate, Not Only Counter

A cumulative counter:

``` text
evicted_keys = 5,000,000
```

does not tell you whether eviction is happening now.

Track:

``` text
delta(evicted_keys) / time
```

------------------------------------------------------------------------

# Part 18 --- Expirations

## 23. Rate

Track expiration rate.

A sudden expiration spike can indicate:

``` text
synchronized TTLs
cache expiration wave
deployment-driven cache churn
```

------------------------------------------------------------------------

# Part 19 --- Cache Hit Ratio

## 24. Application Meaning

Where Redis is used as a cache:

``` text
hit ratio
=
hits / (hits + misses)
```

Interpret with workload context.

A high hit ratio can still coexist with hot-key latency or source
overload during misses.

------------------------------------------------------------------------

# Part 20 --- Source Amplification

## 25. Cache Incidents

Track:

``` text
cache misses
source requests
source latency
source errors
```

This connects Redis cache health to downstream database/API health.

------------------------------------------------------------------------

# Part 21 --- Connections

## 26. Server Side

Track:

``` text
current connections
connection rate
rejected connections
connection churn
```

------------------------------------------------------------------------

# Part 22 --- Client Pool Saturation

## 27. Application Side

Track:

``` text
pool utilization
pool wait duration
pool timeout
```

Connection pool exhaustion may appear as Redis latency even before
requests reach Redis.

------------------------------------------------------------------------

# Part 23 --- Reconnect Storm

## 28. Pattern

After failover:

``` text
many clients reconnect
        |
        v
connection spike
        |
        v
authentication/TLS work
        |
        v
temporary pressure
```

Correlate failover and connection metrics.

------------------------------------------------------------------------

# Part 24 --- Errors

## 29. Classify

Do not put every failure into one counter.

Separate:

``` text
timeout
connection error
authentication error
authorization error
OOM/write rejection
command error
application decode error
```

------------------------------------------------------------------------

# Part 25 --- Retries

## 30. Hidden Traffic

Retries can amplify incidents.

Track:

``` text
initial requests
retry attempts
retry success
retry failure
```

------------------------------------------------------------------------

# Part 26 --- Replication

## 31. HA Signals

Track:

``` text
replication health
replica connectivity
replication lag/freshness
sync events
full synchronization
partial synchronization
```

Use product-specific Redis Enterprise metrics where appropriate.

------------------------------------------------------------------------

# Part 27 --- Active-Active

## 32. Geo Signals

For Active-Active deployments also track:

``` text
regional connectivity
geo replication delay
catch-up state
region health
inter-region network
```

------------------------------------------------------------------------

# Part 28 --- Persistence

## 33. Signals

Where persistence is enabled, track:

``` text
persistence status
save/rewrite activity
duration
failures
storage latency
fork/COW impact where relevant
```

------------------------------------------------------------------------

# Part 29 --- Backup

## 34. Signals

Track:

``` text
last successful backup
backup age
duration
size
failure
restore-test status
```

Backup health belongs on reliability dashboards even though it is not
request-path latency.

------------------------------------------------------------------------

# Part 30 --- CPU

## 35. Interpret Carefully

High CPU can be caused by:

``` text
high command rate
expensive commands
large values
hot keys
serialization/network work
background operations
```

Correlate CPU with workload.

------------------------------------------------------------------------

# Part 31 --- Hot Shards

## 36. Detection

Look for:

``` text
one shard CPU >> peers
one shard ops/sec >> peers
one shard network >> peers
one shard latency >> peers
```

This often indicates key-distribution skew or hot keys.

------------------------------------------------------------------------

# Part 32 --- Big Keys

## 37. Symptoms

Big values may create:

``` text
network spikes
latency spikes
client CPU
memory pressure
slow deletion
```

Combine Redis metrics with application value-size telemetry.

------------------------------------------------------------------------

# Part 33 --- Slow Commands

## 38. Command-Level Insight

Where supported and operationally safe, use Redis diagnostics and
application tracing to identify command types associated with latency.

Do not enable expensive diagnostics blindly in production.

------------------------------------------------------------------------

# Part 34 --- Application Tracing

## 39. Trace Attributes

Useful controlled-cardinality fields include:

``` text
Redis operation
database/service
region
success/error
retry count
```

Avoid recording raw sensitive keys or high-cardinality key IDs in every
trace.

------------------------------------------------------------------------

# Part 35 --- Key Cardinality

## 40. Metrics Risk

Do not create a monitoring label for every Redis key.

This can overwhelm the metrics backend.

Prefer:

``` text
key family
service
tenant class
database
shard
```

------------------------------------------------------------------------

# Part 36 --- Prometheus

## 41. Integration

Redis Enterprise can expose/integrate with monitoring mechanisms
appropriate to the product/version.

When using Prometheus, design:

``` text
scrape targets
authentication/TLS
scrape interval
retention
label cardinality
HA monitoring
```

Validate the exact supported Redis Enterprise metrics endpoint and
metric names.

------------------------------------------------------------------------

# Part 37 --- Scrape Interval

## 42. Tradeoff

Too slow:

``` text
miss short incidents
```

Too fast:

``` text
monitoring overhead
higher storage/cardinality cost
```

Choose based on incident dynamics and platform guidance.

------------------------------------------------------------------------

# Part 38 --- Grafana

## 43. Dashboard Principle

A useful dashboard should support an investigation, not simply display
every available metric.

------------------------------------------------------------------------

# Part 39 --- Dashboard 1: Service Overview

## 44. Panels

Recommended:

``` text
availability
application Redis P95/P99 latency
error rate
ops/sec
connections
memory %
evictions/sec
```

------------------------------------------------------------------------

# Part 40 --- Dashboard 2: Database

## 45. Panels

``` text
read/write ops
network in/out
memory
keys
expiration rate
eviction rate
connections
latency
```

------------------------------------------------------------------------

# Part 41 --- Dashboard 3: Shards

## 46. Panels

``` text
CPU by shard
memory by shard
ops/sec by shard
network by shard
latency by shard
```

Sort descending to expose skew.

------------------------------------------------------------------------

# Part 42 --- Dashboard 4: Nodes

## 47. Panels

``` text
CPU
memory
network
storage
node health
database/shard placement
```

------------------------------------------------------------------------

# Part 43 --- Dashboard 5: Clients

## 48. Panels

``` text
pool utilization
pool wait
timeouts
reconnects
retries
Redis call latency
```

------------------------------------------------------------------------

# Part 44 --- Dashboard 6: Reliability

## 49. Panels

``` text
replication health
failovers
persistence
backup age
backup failure
Active-Active replication where applicable
```

------------------------------------------------------------------------

# Part 45 --- Dashboard 7: Cache

## 50. Panels

``` text
hit ratio
miss rate
eviction rate
expiration rate
source QPS
source latency
source errors
```

------------------------------------------------------------------------

# Part 46 --- Dashboard Time Windows

## 51. Standardize

During incidents compare:

``` text
last 15 minutes
last 1 hour
last 6 hours
same period yesterday/week
```

Baseline comparison helps identify abnormal behavior.

------------------------------------------------------------------------

# Part 47 --- Deployment Markers

## 52. Correlation

Overlay:

``` text
deployments
configuration changes
failovers
maintenance
traffic events
```

on dashboards.

"What changed?" becomes easier to answer.

------------------------------------------------------------------------

# Part 48 --- Alert Design

## 53. Alert on Symptoms and Risk

Good alerts indicate:

``` text
user impact
imminent capacity risk
loss of redundancy
data protection failure
```

Avoid alerting on every small metric fluctuation.

------------------------------------------------------------------------

# Part 49 --- Actionable Alert

## 54. Every Alert Needs

``` text
meaning
severity
threshold
duration
owner
dashboard
runbook
```

------------------------------------------------------------------------

# Part 50 --- Duration

## 55. Avoid Flapping

Instead of:

``` text
CPU > 80% once
```

consider a sustained condition appropriate to the workload.

Short severe events may still require separate fast-burn alerts.

------------------------------------------------------------------------

# Part 51 --- Static Threshold Limitations

## 56. Context

A threshold such as:

``` text
memory > 80%
```

may be useful but incomplete.

Also monitor:

``` text
growth rate
evictions
headroom
traffic
failover capacity
```

------------------------------------------------------------------------

# Part 52 --- Alert: Latency

## 57. Example Concept

``` text
Redis application P99 latency
> service SLO threshold
for sustained period
```

Prefer application-visible latency where possible.

------------------------------------------------------------------------

# Part 53 --- Alert: Error Rate

## 58. Example

``` text
Redis operation error ratio
> allowed SLO rate
```

Classify errors for diagnosis.

------------------------------------------------------------------------

# Part 54 --- Alert: Eviction

## 59. Context

For a cache, some eviction may be expected.

Alert when eviction rate causes:

``` text
hit-ratio degradation
source amplification
latency
```

For workloads where eviction is unacceptable, thresholds should be
stricter.

------------------------------------------------------------------------

# Part 55 --- Alert: Memory

## 60. Use Multiple Signals

Combine:

``` text
memory %
growth rate
evictions
OOM/rejections
```

------------------------------------------------------------------------

# Part 56 --- Alert: Connections

## 61. Signals

Alert on:

``` text
connection exhaustion
rejected connections
abnormal connection creation
pool wait/timeouts
```

------------------------------------------------------------------------

# Part 57 --- Alert: Replication

## 62. Signals

Alert on:

``` text
replica disconnected
lag above RPO threshold
repeated full sync
redundancy lost
```

------------------------------------------------------------------------

# Part 58 --- Alert: Backup

## 63. Better Signal

Alert when:

``` text
last successful backup age > RPO-compatible threshold
```

rather than only when one backup job fails.

------------------------------------------------------------------------

# Part 59 --- Alert: Certificate

## 64. Expiration

Use multiple warning windows appropriate to the certificate process.

Example concept:

``` text
30 days
14 days
7 days
```

Do not wait until hours before expiry.

------------------------------------------------------------------------

# Part 60 --- SLI

## 65. Service Level Indicator

An SLI is a measured reliability signal.

Examples:

``` text
successful Redis-dependent requests
Redis request latency
cache availability
replication freshness
```

------------------------------------------------------------------------

# Part 61 --- SLO

## 66. Service Level Objective

An SLO defines the target for an SLI.

Example:

``` text
99.9% of Redis-dependent application operations
succeed within the defined latency target
over 30 days
```

The actual target must come from business/application requirements.

------------------------------------------------------------------------

# Part 62 --- Availability SLI

## 67. Prefer User View

Possible:

``` text
successful Redis-dependent application operations
/
total Redis-dependent application operations
```

This can be more meaningful than process uptime.

------------------------------------------------------------------------

# Part 63 --- Latency SLI

## 68. Example

``` text
percentage of Redis calls
completed under X milliseconds
```

Define X from application requirements.

------------------------------------------------------------------------

# Part 64 --- Freshness SLI

## 69. Replication

For HA/geo use cases:

``` text
percentage of time replication freshness
is within required threshold
```

------------------------------------------------------------------------

# Part 65 --- Cache Effectiveness SLI

## 70. Optional

For cache workloads:

``` text
hit ratio
source amplification
```

may be operational objectives, but they are not substitutes for
user-facing reliability.

------------------------------------------------------------------------

# Part 66 --- Error Budget

## 71. Concept

If SLO is:

``` text
99.9%
```

then the allowed unreliability is:

``` text
0.1%
```

over the measurement window.

This is the error budget.

------------------------------------------------------------------------

# Part 67 --- Burn Rate

## 72. Why Useful

Burn rate asks:

``` text
How quickly are we consuming the error budget?
```

Fast-burn alerts can detect severe incidents quickly.

Slow-burn alerts can detect persistent degradation.

------------------------------------------------------------------------

# Part 68 --- Multi-Window Alerts

## 73. Concept

A mature SLO system may combine:

``` text
short window + high burn
longer window + sustained burn
```

This reduces noise while catching serious impact.

------------------------------------------------------------------------

# Part 69 --- Baselines

## 74. Record Normal

For each database record typical:

``` text
P50/P95/P99 latency
ops/sec
CPU
memory
connections
network
evictions
hit ratio
```

for:

``` text
normal
peak
batch window
maintenance
```

------------------------------------------------------------------------

# Part 70 --- Capacity Trend

## 75. Growth

Track:

``` text
memory growth/day
key growth/day
traffic growth/week
connection growth
network growth
```

Forecast before saturation.

------------------------------------------------------------------------

# Part 71 --- Incident Correlation

## 76. Timeline

Build one timeline:

``` text
application latency rises
Redis P99 rises
one shard CPU rises
evictions start
source QPS rises
deployment occurred
```

Correlation is more useful than isolated screenshots.

------------------------------------------------------------------------

# Part 72 --- Investigation Order

## 77. Practical Flow

``` text
1. Confirm user impact.
2. Check application Redis latency/errors.
3. Check client pool/retries.
4. Check database throughput/latency.
5. Check shard skew.
6. Check node resources.
7. Check memory/evictions.
8. Check replication/persistence.
9. Check network.
10. Check recent changes.
```

------------------------------------------------------------------------

# Part 73 --- Evidence Preservation

## 78. During Incident

Capture:

``` text
timestamps
dashboards
query ranges
deployments
configuration changes
failovers
alerts
```

Do not rely only on memory after recovery.

------------------------------------------------------------------------

# Part 74 --- Monitoring the Monitoring

## 79. Meta-Monitoring

Detect:

``` text
scrape failure
missing metrics
stale dashboard
alert delivery failure
monitoring backend outage
```

A silent monitoring failure is dangerous.

------------------------------------------------------------------------

# Part 75 --- Hands-On Lab

## 80. Safety

Use a disposable Redis/Redis Enterprise lab.

Do not intentionally exhaust production memory or connections.

------------------------------------------------------------------------

# Part 76 --- Baseline Workload

## 81. Python

``` python
import os
import time
import redis

r = redis.Redis(
    host=os.getenv("REDIS_HOST", "localhost"),
    port=int(os.getenv("REDIS_PORT", "6379")),
    password=os.getenv("REDIS_PASSWORD") or None,
    decode_responses=True,
    socket_connect_timeout=2,
    socket_timeout=2,
)

for i in range(10000):
    key = f"tutorial:chapter39:key:{i % 1000}"

    started = time.perf_counter()

    r.set(key, str(i), ex=300)
    r.get(key)

    elapsed_ms = (
        time.perf_counter() - started
    ) * 1000

    if i % 1000 == 0:
        print(
            "iteration=",
            i,
            "roundtrip_ms=",
            round(elapsed_ms, 3),
        )
```

Observe application, Redis, shard, and node metrics.

------------------------------------------------------------------------

# Part 77 --- Baseline Record

## 82. Capture

Record:

``` text
P50 latency
P95 latency
P99 latency
ops/sec
memory
connections
CPU
network
evictions/sec
expiration/sec
```

------------------------------------------------------------------------

# Part 78 --- Latency Distribution Lab

## 83. Client Measurement

Collect many operation durations and calculate percentiles.

Example:

``` python
import statistics

samples_ms = []

for i in range(5000):
    started = time.perf_counter()
    r.get(f"tutorial:chapter39:key:{i % 1000}")
    samples_ms.append(
        (time.perf_counter() - started) * 1000
    )

samples_ms.sort()

def pct(values, p):
    idx = int((len(values) - 1) * p)
    return values[idx]

print("P50", pct(samples_ms, 0.50))
print("P95", pct(samples_ms, 0.95))
print("P99", pct(samples_ms, 0.99))
print("mean", statistics.mean(samples_ms))
```

Compare mean with P99.

------------------------------------------------------------------------

# Part 79 --- Connection Churn Lab

## 84. Anti-Pattern Demonstration

In a disposable environment, compare:

``` text
reused connection/pool
vs.
new client/connection repeatedly
```

Observe connection rate and latency.

Do not run an unbounded connection storm.

------------------------------------------------------------------------

# Part 80 --- Pool Saturation Lab

## 85. Controlled

Use a small blocking pool and more worker threads than connections.

Measure:

``` text
pool wait
timeout
operation latency
```

Correlate client saturation with Redis server health.

------------------------------------------------------------------------

# Part 81 --- Memory Growth Lab

## 86. Controlled Dataset

Insert bounded test data and observe:

``` text
used memory
key count
memory %
```

Stop before lab safety threshold.

------------------------------------------------------------------------

# Part 82 --- Expiration Wave Lab

## 87. Synchronized TTL

Create a bounded set of keys with the same TTL.

Observe expiration-rate spike.

Then repeat with TTL jitter and compare.

------------------------------------------------------------------------

# Part 83 --- Eviction Lab

## 88. Dedicated Lab Only

Where safe, use a disposable instance with a controlled memory limit and
eviction policy.

Generate enough data to cause bounded eviction.

Observe:

``` text
evictions/sec
hit ratio
source simulation
latency
```

Never change production `maxmemory` for this exercise.

------------------------------------------------------------------------

# Part 84 --- Hot-Key / Shard-Skew Lab

## 89. Workload

Generate most requests against one key and compare per-shard/resource
metrics where topology exposes them.

Then distribute requests across many keys.

------------------------------------------------------------------------

# Part 85 --- Large-Value Lab

## 90. Compare

Measure:

``` text
1 KB values
100 KB values
1 MB values
```

within safe lab limits.

Observe:

``` text
network
latency
client CPU
Redis resource usage
```

------------------------------------------------------------------------

# Part 86 --- Retry Amplification Lab

## 91. Controlled Failure

Inject a temporary Redis connectivity failure into a disposable client.

Compare:

``` text
no retry
bounded retry with backoff/jitter
aggressive immediate retry
```

Observe traffic amplification.

------------------------------------------------------------------------

# Part 87 --- Replication Alert Lab

## 92. HA Lab

Temporarily disrupt a disposable replica.

Verify:

``` text
replication alert
lag/freshness signal
redundancy alert
recovery
```

------------------------------------------------------------------------

# Part 88 --- Backup Alert Lab

## 93. Simulate

Use a lab backup workflow or monitoring test signal to represent a
missed backup.

Verify the alert is based on backup age.

------------------------------------------------------------------------

# Part 89 --- Certificate Alert Lab

## 94. Simulate

Use a disposable certificate/metric with a short remaining validity
period.

Verify expiration alert routing and runbook.

------------------------------------------------------------------------

# Part 90 --- Dashboard Drill

## 95. Operator Exercise

Give the operator only dashboards and a known injected problem.

They should identify:

``` text
user impact
affected layer
likely cause
next diagnostic action
runbook
```

------------------------------------------------------------------------

# Part 91 --- Failure Injection

## 96. Failure 1 --- High Client Latency

Inject controlled delay or contention and verify P95/P99 alerting.

## 97. Failure 2 --- Pool Exhaustion

Saturate a small lab connection pool and verify client-side monitoring.

## 98. Failure 3 --- Connection Churn

Create bounded repeated connections and verify connection-rate
visibility.

## 99. Failure 4 --- Memory Pressure

Approach a safe lab memory threshold and verify capacity alerting.

## 100. Failure 5 --- Eviction Spike

Generate bounded eviction and verify rate-based detection.

## 101. Failure 6 --- Expiration Storm

Expire many lab keys together and verify expiration-rate visibility.

## 102. Failure 7 --- Hot Shard

Generate skewed workload and verify shard-level detection.

## 103. Failure 8 --- Replication Degradation

Disrupt a disposable replica and verify HA monitoring.

## 104. Failure 9 --- Missing Metrics

Stop one lab scrape/export path and verify monitoring-of-monitoring
alerting.

## 105. Failure 10 --- Retry Storm

Use an aggressive disposable retry loop during a controlled failure and
observe amplification.

------------------------------------------------------------------------

# Part 92 --- Troubleshooting

## 106. Application Latency High, Redis CPU Normal

Check:

``` text
connection-pool wait
network
DNS
TLS
retries
large responses
client CPU
```

------------------------------------------------------------------------

## 107. Redis CPU High

Check:

``` text
ops/sec
command mix
hot keys
large values
one hot shard
background operations
```

------------------------------------------------------------------------

## 108. Memory Rising

Check:

``` text
key growth
value growth
TTL coverage
persistent keys
large keys
workload changes
```

------------------------------------------------------------------------

## 109. Evictions Rising

Check:

``` text
memory limit
working-set growth
TTL
value sizes
hot data
policy
```

Then correlate with hit ratio and source load.

------------------------------------------------------------------------

## 110. Latency High on One Shard

Check:

``` text
hot keys
hash-tag concentration
tenant skew
big values
per-shard traffic
```

------------------------------------------------------------------------

## 111. Connection Count Spiking

Check:

``` text
deployment
autoscaling
reconnect storm
connection leak
connection-per-request
```

------------------------------------------------------------------------

## 112. Timeouts Rising but Redis Latency Low

Check:

``` text
client pool
network
application deadlines
DNS
TLS handshake
retry behavior
```

------------------------------------------------------------------------

## 113. Metrics Missing

Check:

``` text
metrics endpoint
exporter/integration
authentication
TLS
network
scrape configuration
monitoring backend
```

------------------------------------------------------------------------

## 114. Alert Fires but No User Impact

Determine whether the alert represents:

``` text
future risk
poor threshold
short harmless spike
wrong aggregation
```

Tune carefully rather than deleting useful protection.

------------------------------------------------------------------------

# Part 93 --- Production Runbooks

## 115. Runbook --- Redis Latency Alert

``` text
1. Confirm application impact.
2. Check P50/P95/P99.
3. Check client pool wait/timeouts.
4. Check database ops/sec.
5. Check per-shard CPU/latency.
6. Check memory/evictions.
7. Check network.
8. Check recent changes.
9. Mitigate identified bottleneck.
10. Confirm latency returns to baseline.
```

------------------------------------------------------------------------

## 116. Runbook --- Memory Pressure

``` text
1. Confirm memory trend.
2. Check headroom.
3. Check eviction/OOM behavior.
4. Identify key/value growth.
5. Check TTL coverage.
6. Check big keys.
7. Protect application/source.
8. Apply approved capacity/data fix.
9. Verify stabilization.
10. Update forecast/threshold.
```

------------------------------------------------------------------------

## 117. Runbook --- Connection Saturation

``` text
1. Confirm server connections.
2. Check client pool utilization.
3. Check pool wait/timeouts.
4. Check connection creation rate.
5. Identify reconnect/deployment event.
6. Stop connection-per-request behavior.
7. Apply bounded pool/backpressure.
8. Verify Redis capacity.
9. Confirm recovery.
10. Update connection budget.
```

------------------------------------------------------------------------

## 118. Runbook --- Hot Shard

``` text
1. Identify saturated shard.
2. Compare peer shards.
3. Check traffic distribution.
4. Identify hot key/key family.
5. Check hash tags.
6. Check tenant skew.
7. Reduce/redistribute workload safely.
8. Validate latency recovery.
9. Add workload-skew monitoring.
10. Review data model.
```

------------------------------------------------------------------------

## 119. Runbook --- Monitoring Blind Spot

``` text
1. Confirm missing telemetry.
2. Determine affected metrics/regions.
3. Check scrape/export path.
4. Check authentication/TLS/network.
5. Restore monitoring.
6. Validate alert pipeline.
7. Review incident period using alternate evidence.
8. Confirm dashboards current.
9. Add meta-monitoring if missing.
10. Document blind-spot duration.
```

------------------------------------------------------------------------

# Part 94 --- Dashboard Design Template

## 120. Service Overview

``` text
Application availability:
Redis-dependent error rate:
Redis P95/P99:
Ops/sec:
Connections:
Memory:
Evictions/sec:
Replication:
Recent deployments:
Active incidents:
```

------------------------------------------------------------------------

# Part 95 --- Alert Definition Template

## 121. Fields

``` text
Alert name:
Service/database:
Signal:
Threshold:
Duration:
Severity:
User impact:
Risk:
Owner:
Dashboard:
Runbook:
Expected action:
Auto-resolution:
Test date:
```

------------------------------------------------------------------------

# Part 96 --- SLO Definition Template

## 122. Fields

``` text
Service:
Redis dependency:
SLI:
Good event:
Bad event:
SLO target:
Measurement window:
Latency target:
Availability target:
Exclusions:
Error budget:
Fast-burn alert:
Slow-burn alert:
Owner:
Review cadence:
```

------------------------------------------------------------------------

# Part 97 --- Baseline Template

## 123. Record

  Metric            Normal   Peak   Alert/Capacity Threshold
  --------------- -------- ------ --------------------------
  P50 latency                     
  P95 latency                     
  P99 latency                     
  Ops/sec                         
  CPU                             
  Memory                          
  Connections                     
  Network in                      
  Network out                     
  Evictions/sec                   

Use environment-specific values.

------------------------------------------------------------------------

# Part 98 --- Incident Evidence Template

## 124. Timeline

``` text
Incident:
Database:
Start:
End:
User impact:
Application latency:
Redis latency:
Error rate:
Ops/sec:
Memory:
Evictions:
Connections:
Hot shard:
Replication:
Network:
Deployment/change:
Mitigation:
Recovery:
```

------------------------------------------------------------------------

# Part 99 --- Capacity Review

## 125. Questions

``` text
What is current peak?
What is normal headroom?
What is growth rate?
Can one shard saturate before database average?
Can failover workload fit?
Can reconnect traffic fit?
When will capacity threshold be reached?
```

------------------------------------------------------------------------

# Part 100 --- Alert Review

## 126. Monthly/Periodic

For each alert ask:

``` text
Did it fire?
Was it actionable?
Was it too late?
Was it noisy?
Did it have a runbook?
Did the owner respond correctly?
```

------------------------------------------------------------------------

# Part 101 --- Production Acceptance Checklist

## 127. Observability Engineering

-   [ ] Application Redis latency monitored.
-   [ ] P50/P95/P99 available.
-   [ ] Redis-dependent error rate monitored.
-   [ ] Retry rate monitored.
-   [ ] Client pool utilization monitored.
-   [ ] Pool wait/timeouts monitored.
-   [ ] Database ops/sec monitored.
-   [ ] Network throughput monitored.
-   [ ] Memory usage/headroom monitored.
-   [ ] Eviction rate monitored.
-   [ ] Expiration rate monitored.
-   [ ] Cache hit/miss monitored where applicable.
-   [ ] Source amplification monitored where applicable.
-   [ ] Connection count/rate monitored.
-   [ ] Node CPU/memory/network monitored.
-   [ ] Per-shard metrics available where supported.
-   [ ] Hot-shard detection implemented.
-   [ ] Replication health monitored.
-   [ ] Persistence monitored where enabled.
-   [ ] Backup age monitored.
-   [ ] Active-Active health monitored where applicable.
-   [ ] Certificate expiration monitored.
-   [ ] Prometheus/monitoring integration validated.
-   [ ] Dashboard time windows standardized.
-   [ ] Deployment/change markers available.
-   [ ] Alerts have owners.
-   [ ] Alerts have runbooks.
-   [ ] SLI/SLO defined for critical services.
-   [ ] Error-budget alerting designed where applicable.
-   [ ] Monitoring pipeline itself monitored.
-   [ ] Failure drills completed.
-   [ ] Incident evidence template adopted.

------------------------------------------------------------------------

# Knowledge Validation

## 128. Questions

1.  What is the difference between monitoring and observability?
2.  What are the four golden signals?
3.  Why is Redis "UP" insufficient?
4.  Why should application Redis metrics be monitored?
5.  Why should connection-pool metrics be monitored?
6.  Why can cluster averages hide incidents?
7.  Why are latency percentiles better than average alone?
8.  What is tail latency?
9.  Why should latency be decomposed by layer?
10. Why monitor bytes/sec as well as ops/sec?
11. Why is memory headroom necessary?
12. Why should eviction be monitored as a rate?
13. What can an expiration spike indicate?
14. What is cache source amplification?
15. What causes reconnect storms?
16. Why should errors be classified?
17. How can retries amplify incidents?
18. Which replication signals matter?
19. Why monitor backup age?
20. How can a hot shard be detected?
21. Why avoid raw Redis keys as metric labels?
22. What makes a useful Grafana dashboard?
23. What makes an alert actionable?
24. What is an SLI?
25. What is an SLO?
26. What is an error budget?
27. What is burn rate?
28. Why overlay deployment markers?
29. What is monitoring-of-monitoring?
30. What must pass before Redis observability is production-ready?

------------------------------------------------------------------------

# Hands-On Acceptance Checklist

## 129. Lab Completion

-   [ ] Generated baseline workload.
-   [ ] Recorded latency percentiles.
-   [ ] Recorded ops/sec.
-   [ ] Recorded memory.
-   [ ] Recorded connections.
-   [ ] Recorded CPU/network.
-   [ ] Compared mean vs P99.
-   [ ] Tested connection churn.
-   [ ] Tested pool saturation.
-   [ ] Tested memory growth.
-   [ ] Tested expiration wave.
-   [ ] Tested TTL jitter comparison.
-   [ ] Tested bounded eviction.
-   [ ] Tested hot-key/shard skew.
-   [ ] Tested large-value impact.
-   [ ] Tested retry amplification.
-   [ ] Tested replication alert.
-   [ ] Tested backup-age alert.
-   [ ] Tested certificate-expiration alert.
-   [ ] Performed dashboard drill.
-   [ ] Completed ten failure scenarios.
-   [ ] Completed troubleshooting.
-   [ ] Reviewed five production runbooks.
-   [ ] Completed dashboard template.
-   [ ] Completed alert template.
-   [ ] Completed SLO template.
-   [ ] Completed production acceptance checklist.

------------------------------------------------------------------------

# 130. Lab Cleanup

Discover only Chapter 39 keys:

``` bash
redis-cli --scan --pattern 'tutorial:chapter39:*'
```

Review all matches and delete only confirmed lab keys in bounded
batches:

``` redis
UNLINK <confirmed-key>
```

Remove only disposable dashboards, alerts, test certificates, and
monitoring objects created specifically for the lab.

Do not remove production monitoring rules.

Do not use:

``` redis
KEYS tutorial:chapter39:*
FLUSHDB
FLUSHALL
```

against a shared or production database.

------------------------------------------------------------------------

# 131. Key Takeaways

1.  Redis observability must cover applications, clients, databases,
    shards, nodes, network, and storage.
2.  Process/database availability alone does not prove user-facing
    health.
3.  Latency, traffic, errors, and saturation provide a strong
    operational foundation.
4.  Application-visible Redis metrics should lead incident
    investigation.
5.  Connection-pool wait can look like Redis latency.
6.  P95/P99 reveal problems hidden by averages.
7.  Cluster averages can hide a saturated shard.
8.  Network bytes/sec matters in addition to operations/sec.
9.  Memory headroom protects failover and workload spikes.
10. Evictions and expirations should be monitored as rates.
11. Cache incidents should be correlated with source load.
12. Connection churn and reconnect storms require dedicated telemetry.
13. Retry metrics reveal hidden traffic amplification.
14. Replication, persistence, and backup are separate reliability
    signals.
15. Hot-shard detection requires per-shard comparison where supported.
16. Monitoring labels must avoid uncontrolled key-level cardinality.
17. Dashboards should support investigation, not display metrics
    indiscriminately.
18. Alerts should represent user impact or meaningful reliability risk.
19. Every production alert should have an owner and runbook.
20. SLIs measure reliability; SLOs define targets.
21. Error budgets quantify allowed unreliability.
22. Burn-rate alerts connect incidents to SLO consumption.
23. Deployment/change markers accelerate root-cause analysis.
24. The monitoring system itself must be monitored.
25. Production observability is proven through baselines, dashboards,
    actionable alerts, SLOs, failure drills, and incident-ready
    runbooks.

------------------------------------------------------------------------

# 132. References

Validate exact Redis Enterprise metric names, endpoints, labels, and
monitoring integrations against the deployed product version.

Recommended official documentation areas:

-   Redis Enterprise monitoring
-   Redis Enterprise metrics
-   Redis Enterprise Prometheus integration
-   Redis Enterprise Grafana monitoring
-   Redis Enterprise database metrics
-   Redis Enterprise node metrics
-   Redis Enterprise shard metrics
-   Redis latency monitoring
-   Redis `INFO`
-   Redis memory metrics
-   Redis replication monitoring
-   Redis persistence monitoring
-   Redis Enterprise Active-Active monitoring
-   Redis Enterprise backup monitoring
-   Prometheus alerting best practices
-   Grafana dashboard design
-   SRE SLI/SLO and error-budget practices

------------------------------------------------------------------------

# Next Chapter

**Chapter 40 --- Redis Enterprise Performance Troubleshooting &
Production Incident Engineering**

Chapter 40 will turn the metrics and concepts from the previous chapters
into a structured incident workflow covering:

-   high latency
-   high CPU
-   memory pressure
-   eviction storms
-   connection exhaustion
-   hot keys
-   big keys
-   shard imbalance
-   network saturation
-   replication lag
-   persistence pressure
-   client-side bottlenecks
-   retry storms
-   application correlation
-   evidence collection
-   mitigation
-   root-cause isolation
-   production incident runbooks
-   post-incident validation
