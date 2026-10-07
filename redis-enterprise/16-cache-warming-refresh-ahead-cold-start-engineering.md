# Chapter 16 --- Cache Warming, Refresh-Ahead & Cold-Start Engineering

**Status:** Canonical\
**Track:** Redis Enterprise / Redis Software Production Engineering\
**Part:** Part 2 --- Caching & Application Engineering\
**Level:** Intermediate → Production Cache Reliability Engineering\
**Audience:** Developers, SREs, DBREs, Platform Engineers, Redis
Administrators\
**Lab type:** Cold-cache reproduction, working-set discovery, controlled
warming, TTL distribution, refresh-ahead, source concurrency protection,
deployment/failover warming, failure injection, observability,
troubleshooting, and production acceptance

------------------------------------------------------------------------

# 1. Objective

A cache performs best after the important working set is already
present.

Production systems, however, repeatedly encounter cold or partially cold
caches:

``` text
new deployment
new namespace
new Redis database
disaster recovery
regional failover
mass invalidation
cache flush
large expiration wave
new tenant
new application version
```

The engineering problem is not simply:

> How quickly can we fill Redis?

It is:

> How quickly can we restore a useful cache without overloading the
> authoritative source, Redis, the network, or the application?

By the end of this chapter, you should be able to:

-   Explain cold-start and cold-cache behavior.
-   Define the working set instead of warming every possible object.
-   Rank warming candidates by value and demand.
-   Build demand-driven and proactive warming strategies.
-   Protect source systems with concurrency and rate budgets.
-   Apply TTL jitter during warming.
-   Implement refresh-ahead.
-   Avoid synchronized refresh jobs.
-   Design deployment and failover warming.
-   Prevent cache-warming and recovery storms.
-   Measure warming effectiveness.
-   Estimate warming duration and source load.
-   Build safe rollback/abort controls.
-   Troubleshoot slow or dangerous warming.
-   Validate cold-start behavior before production.

------------------------------------------------------------------------

# 2. Core Production Principle

Cache warming is a controlled transfer of work from the source into
Redis.

Every warm operation consumes resources:

``` text
source CPU / I/O
source connections
application workers
network bandwidth
Redis operations
Redis memory
serialization CPU
```

Therefore:

``` text
maximum possible warming speed
```

is not the target.

The target is:

``` text
fastest safe warming rate
```

that preserves source and application SLOs.

------------------------------------------------------------------------

# Part 1 --- Cold Cache Fundamentals

## 3. What Is a Cold Cache?

A cache is cold when important data expected by the application is
absent.

``` text
request
   |
   v
Redis
   |
 MISS
   |
   v
source
```

A completely empty Redis database is one example.

A cache can also be operationally cold when Redis contains many keys but
the high-demand working set is missing.

------------------------------------------------------------------------

## 4. Warm vs. Cold

Warm:

``` text
high-value requests -> mostly cache hits
```

Cold:

``` text
high-value requests -> mostly cache misses -> source load
```

The operational risk is determined by miss traffic, not merely by Redis
key count.

------------------------------------------------------------------------

# Part 2 --- Cold-Start Causes

## 5. Common Causes

``` text
new Redis deployment
new application environment
regional startup
disaster recovery
new cache-key version
application release
migration
cache database recreation
mass invalidation
large TTL wave
manual flush
```

------------------------------------------------------------------------

## 6. Namespace Change

Suppose an application moves from:

``` text
product:v1:1001
```

to:

``` text
product:v2:1001
```

Redis may still contain the entire v1 cache, yet v2 starts cold.

Logical cache availability matters more than raw key count.

------------------------------------------------------------------------

# Part 3 --- Why Cold Starts Are Dangerous

## 7. Source Transfer

Suppose:

``` text
application traffic = 25,000 reads/sec
warm hit ratio = 98%
```

Normal source demand is roughly:

``` text
500 reads/sec
```

At startup with a 20% hit ratio:

``` text
20,000 reads/sec
```

may reach the source.

If source sustainable capacity is 3,000 reads/sec, uncontrolled cold
start is unsafe.

------------------------------------------------------------------------

## 8. Cascading Failure

``` text
cold cache
   |
misses increase
   |
source QPS increases
   |
source latency increases
   |
cache fills take longer
   |
miss window stays open longer
   |
application concurrency increases
   |
retries increase
```

Cold-start engineering must break this loop.

------------------------------------------------------------------------

# Part 4 --- Working-Set Discovery

## 9. Do Not Warm Everything

A database may contain millions of cacheable objects while only a
fraction are frequently requested.

Warming every possible object can:

-   overload the source;
-   consume unnecessary Redis memory;
-   evict useful objects;
-   increase network traffic;
-   lengthen recovery;
-   populate data that expires unused.

------------------------------------------------------------------------

## 10. Working Set

The working set is the subset of objects likely to provide meaningful
cache value.

Examples:

``` text
most-requested products
active tenants
frequently viewed configurations
current reference data
high-volume customer records
critical application metadata
```

------------------------------------------------------------------------

## 11. Discovery Inputs

Possible inputs:

``` text
application access metrics
request logs
APM traces
cache hit/miss metrics
business priority
recent-access lists
known hot-key inventory
source query statistics
historical cache telemetry
```

Avoid using Redis `KEYS *` in production as a discovery mechanism.

------------------------------------------------------------------------

# Part 5 --- Warming Priority

## 12. Priority Tiers

Example:

``` text
Tier 0 -> required for application startup
Tier 1 -> hottest / business-critical
Tier 2 -> frequently used
Tier 3 -> long-tail
```

Warm the highest-value data first.

------------------------------------------------------------------------

## 13. Value-Based Ordering

A useful conceptual score is:

``` text
warming priority =
expected request frequency
× source cost
× business criticality
```

The exact scoring method should reflect the workload.

------------------------------------------------------------------------

# Part 6 --- Warming Strategies

## 14. Demand-Driven Warming

Users populate the cache naturally:

``` text
request -> miss -> source -> Redis
```

Advantages:

-   warms only requested data;
-   simple;
-   avoids preloading unused objects.

Risk:

-   cold-start traffic directly reaches the source.

------------------------------------------------------------------------

## 15. Proactive Warming

Populate selected keys before normal traffic arrives.

``` text
working-set list
     |
warming workers
     |
source
     |
Redis
```

Advantages:

-   important data is ready earlier;
-   protects first-user latency.

Risk:

-   warming itself can overload the source.

------------------------------------------------------------------------

## 16. Hybrid Warming

A common production strategy:

``` text
pre-warm Tier 0 / Tier 1
+
allow demand-driven warming for the long tail
```

This balances recovery speed and source load.

------------------------------------------------------------------------

# Part 7 --- Source Capacity Budget

## 17. Measure Before Warming

Required inputs:

``` text
source sustainable QPS
normal non-cache source QPS
reserved safety headroom
average warm-item cost
source p95/p99 latency
maximum safe connections
```

------------------------------------------------------------------------

## 18. Example Budget

Suppose:

``` text
source sustainable = 4,000 QPS
normal direct load = 1,500 QPS
reserved headroom = 1,000 QPS
```

Available warming budget:

``` text
4,000 - 1,500 - 1,000 = 1,500 QPS
```

Do not configure warming at 5,000 QPS simply because Redis can accept
it.

------------------------------------------------------------------------

# Part 8 --- Concurrency Control

## 19. Bound Workers

Example:

``` text
candidate objects = 1,000,000
warming workers = 20
```

Workers should be bounded by source capacity, not by candidate count.

------------------------------------------------------------------------

## 20. Dynamic Control

A more mature warmer can reduce concurrency when:

``` text
source p95 latency rises
source errors rise
connection utilization rises
Redis latency rises
application latency rises
```

and increase gradually when health is stable.

------------------------------------------------------------------------

# Part 9 --- Rate Limiting

## 21. Rate vs. Concurrency

Concurrency limits:

``` text
how many warm operations are active?
```

Rate limits:

``` text
how many warm operations may begin per second?
```

Production designs may need both.

------------------------------------------------------------------------

# Part 10 --- TTL Distribution During Warming

## 22. The Hidden Future Incident

If 100,000 keys are warmed together with exactly:

``` text
TTL = 3600
```

they may expire in approximately the same future window.

A successful warm can therefore schedule the next incident.

------------------------------------------------------------------------

## 23. Apply Jitter

``` text
effective TTL =
base TTL + random jitter
```

Example:

``` text
base = 3600 sec
jitter = 0..600 sec
```

This spreads future expiration.

------------------------------------------------------------------------

# Part 11 --- Refresh-Ahead Fundamentals

## 24. Goal

Refresh hot data before it becomes unavailable.

``` text
fresh value
    |
refresh threshold
    |
one controlled refresh
    |
new fresh value
```

Requests continue reading the existing value during refresh where
application semantics permit.

------------------------------------------------------------------------

## 25. Refresh Threshold

Example:

``` text
hard TTL = 600 sec
refresh-ahead threshold = 120 sec remaining
```

When:

``` text
TTL <= 120
```

an eligible worker may initiate refresh.

------------------------------------------------------------------------

# Part 12 --- Refresh-Ahead Candidate Selection

## 26. Do Not Refresh Every Key Forever

Refresh-ahead is most useful for:

``` text
predictably hot keys
expensive source lookups
business-critical data
keys with stable demand
```

Refreshing cold keys wastes resources.

------------------------------------------------------------------------

## 27. Demand-Aware Refresh

A key might qualify only when:

``` text
recent request count >= threshold
AND
TTL <= refresh threshold
```

This combines popularity with freshness.

------------------------------------------------------------------------

# Part 13 --- Refresh Coordination

## 28. One Refresher

Refresh-ahead still needs coordination.

Without it:

``` text
50 application instances
all observe low TTL
all refresh source
```

Use the Chapter 15 single-flight pattern so one worker refreshes the
object.

------------------------------------------------------------------------

# Part 14 --- Refresh Jitter

## 29. Avoid Refresh Herds

Do not schedule every key for refresh at the same threshold or clock
time.

Use:

``` text
TTL jitter
refresh-threshold jitter
scheduler jitter
```

where appropriate.

------------------------------------------------------------------------

# Part 15 --- Stale-While-Refresh

## 30. Serving During Refresh

Where permitted:

``` text
request -> existing cached value
               |
               +-> one background refresh
```

This prevents user requests from waiting for the source.

------------------------------------------------------------------------

# Part 16 --- Deployment Warming

## 31. New Version

A release introducing a new cache namespace should answer:

``` text
Which keys must exist before traffic?
How many objects?
How long will warming take?
What source budget is available?
Can old cache remain readable?
What is rollback behavior?
```

------------------------------------------------------------------------

## 32. Pre-Traffic Warm

Possible sequence:

``` text
deploy new version
   |
warm Tier 0
   |
validate
   |
warm Tier 1
   |
validate source health
   |
shift traffic gradually
```

------------------------------------------------------------------------

# Part 17 --- Blue/Green Cache Strategy

## 33. Namespace Coexistence

During a controlled migration:

``` text
v1 keys remain available
v2 keys warm gradually
traffic moves after acceptance
```

This can reduce cold-start risk but increases temporary memory
requirements.

------------------------------------------------------------------------

# Part 18 --- Failover Warming

## 34. Regional / DR Recovery

A failover target may have:

``` text
healthy Redis
+
insufficient working set
```

Failover plans must include cache readiness, not only database
availability.

------------------------------------------------------------------------

## 35. Recovery Priority

Typical sequence:

``` text
critical configuration
authentication/reference dependencies where appropriate
highest-volume entities
business-critical read paths
long tail
```

Exact ordering depends on application semantics.

------------------------------------------------------------------------

# Part 19 --- Warming After Redis Recovery

## 36. Recovery Storm Risk

When Redis returns after an outage, many applications may immediately
repopulate it.

``` text
Redis restored
   |
all applications retry
   |
source + Redis receive burst
```

Restore traffic gradually.

------------------------------------------------------------------------

# Part 20 --- Memory Capacity

## 37. Warming Must Fit

Before preloading:

``` text
candidate count
average value size
key overhead
metadata overhead
replication/topology requirements
existing data
memory headroom
```

A warmer that fills Redis to eviction pressure can reduce cache
effectiveness.

------------------------------------------------------------------------

## 38. Working Set vs. Cache Capacity

If:

``` text
working set > practical cache capacity
```

preloading everything is impossible.

Prioritize by value and allow natural replacement according to the
approved cache policy.

------------------------------------------------------------------------

# Part 21 --- Eviction Interaction

## 39. Avoid Warming Into Thrash

Symptoms:

``` text
warming rate high
evictions high
hit ratio fails to improve
same objects repeatedly reloaded
```

This can indicate that the useful working set does not fit or warming
selection is poor.

------------------------------------------------------------------------

# Part 22 --- Warming Duration Model

## 40. Basic Estimate

Conceptually:

``` text
warming duration =
candidate count / effective warm rate
```

Example:

``` text
600,000 keys / 1,000 keys/sec
= 600 sec
= 10 min
```

Real duration also depends on:

``` text
source latency
parallelism
errors
retries
serialization
network
Redis writes
rate limiting
```

------------------------------------------------------------------------

# Part 23 --- Abort Criteria

## 41. A Warmer Must Be Stoppable

Abort or reduce warming when defined thresholds are exceeded.

Examples:

``` text
source p99 > threshold
source error rate > threshold
application latency > threshold
Redis latency > threshold
Redis memory > threshold
eviction rate > threshold
```

------------------------------------------------------------------------

# Part 24 --- Idempotency

## 42. Safe Re-Execution

A warming job may restart.

It should safely handle:

``` text
already-warm key
partially completed batch
worker restart
duplicate candidate
retry
```

Avoid designs where rerunning the warmer corrupts cache state.

------------------------------------------------------------------------

# Part 25 --- Check Before Load

## 43. Avoid Unnecessary Source Work

Before querying the source:

``` text
check Redis
```

If the value already exists and satisfies the warming freshness
contract, skip it.

------------------------------------------------------------------------

# Part 26 --- Hands-On Lab

## 44. Lab Objective

You will:

1.  create a simulated source;
2.  build a cold-cache workload;
3.  measure demand-driven cold start;
4.  build a controlled warmer;
5.  rank candidates;
6.  apply TTL jitter;
7.  limit warming concurrency;
8.  measure warm duration;
9.  implement refresh-ahead;
10. inject source slowdown;
11. test abort behavior;
12. validate cleanup.

------------------------------------------------------------------------

## 45. Prerequisites

Required:

``` text
Redis / Redis Enterprise endpoint
Python 3.9+
redis-py
redis-cli
```

Install:

``` bash
python -m pip install redis
```

Linux/macOS:

``` bash
export REDIS_HOST=localhost
export REDIS_PORT=6379
export REDIS_PASSWORD=''
```

Windows Command Prompt:

``` cmd
set REDIS_HOST=localhost
set REDIS_PORT=6379
set REDIS_PASSWORD=
```

Windows PowerShell:

``` powershell
$env:REDIS_HOST="localhost"
$env:REDIS_PORT="6379"
$env:REDIS_PASSWORD=""
```

Do not commit production credentials.

------------------------------------------------------------------------

## 46. Verify Connectivity

``` bash
redis-cli -h localhost -p 6379 PING
```

Expected:

``` text
PONG
```

Authenticated environments should use the approved authentication/TLS
options.

------------------------------------------------------------------------

# Part 27 --- Cold-Start Lab

## 47. Create `chapter16_warming_lab.py`

``` python
import json
import os
import random
import threading
import time
from concurrent.futures import ThreadPoolExecutor, as_completed

import redis

HOST = os.getenv("REDIS_HOST", "localhost")
PORT = int(os.getenv("REDIS_PORT", "6379"))
PASSWORD = os.getenv("REDIS_PASSWORD") or None

r = redis.Redis(
    host=HOST,
    port=PORT,
    password=PASSWORD,
    decode_responses=True,
)

PREFIX = "tutorial:chapter16:item:"
BASE_TTL = 60
TTL_JITTER = 30
SOURCE_LATENCY = 0.05
MAX_WARM_WORKERS = 10

source_calls = 0
source_counter_lock = threading.Lock()


def source_lookup(item_id):
    global source_calls

    with source_counter_lock:
        source_calls += 1

    time.sleep(SOURCE_LATENCY)

    return {
        "id": item_id,
        "value": f"value-{item_id}",
        "generated_at": time.time(),
    }


def cache_key(item_id):
    return f"{PREFIX}{item_id}"


def write_cache(item_id, data):
    ttl = BASE_TTL + random.randint(0, TTL_JITTER)

    r.set(
        cache_key(item_id),
        json.dumps(data),
        ex=ttl,
    )

    return ttl


def read_through(item_id):
    raw = r.get(cache_key(item_id))

    if raw is not None:
        return json.loads(raw), "hit"

    data = source_lookup(item_id)
    write_cache(item_id, data)

    return data, "miss"


def warm_one(item_id):
    key = cache_key(item_id)

    if r.exists(key):
        return item_id, "already-warm", r.ttl(key)

    data = source_lookup(item_id)
    ttl = write_cache(item_id, data)

    return item_id, "warmed", ttl


def warm_candidates(item_ids):
    start = time.perf_counter()
    results = []

    with ThreadPoolExecutor(max_workers=MAX_WARM_WORKERS) as pool:
        futures = [
            pool.submit(warm_one, item_id)
            for item_id in item_ids
        ]

        for future in as_completed(futures):
            results.append(future.result())

    elapsed = time.perf_counter() - start

    return results, elapsed


def cleanup(item_ids):
    keys = [cache_key(item_id) for item_id in item_ids]

    if keys:
        r.unlink(*keys)


if __name__ == "__main__":
    candidates = list(range(1, 101))

    print("Redis ping:", r.ping())

    cleanup(candidates)

    source_calls = 0

    print()
    print("=== CONTROLLED WARM ===")

    results, elapsed = warm_candidates(candidates)

    print("Candidates       :", len(candidates))
    print("Source calls     :", source_calls)
    print("Elapsed seconds  :", round(elapsed, 3))

    ttls = [ttl for _, _, ttl in results if ttl >= 0]

    print("Minimum TTL      :", min(ttls))
    print("Maximum TTL      :", max(ttls))

    source_calls = 0

    print()
    print("=== POST-WARM READS ===")

    hits = 0
    misses = 0

    for item_id in candidates:
        _, state = read_through(item_id)

        if state == "hit":
            hits += 1
        else:
            misses += 1

    print("Hits             :", hits)
    print("Misses           :", misses)
    print("Source calls     :", source_calls)
```

------------------------------------------------------------------------

## 48. Run

``` bash
python chapter16_warming_lab.py
```

Expected pattern:

``` text
=== CONTROLLED WARM ===
Candidates       : 100
Source calls     : 100
Minimum TTL      : ~60
Maximum TTL      : ~90

=== POST-WARM READS ===
Hits             : 100
Misses           : 0
Source calls     : 0
```

Exact TTLs and duration vary.

------------------------------------------------------------------------

# Part 28 --- Verify TTL Distribution

## 49. Inspect Keys

Use `SCAN` for the isolated lab namespace:

``` bash
redis-cli --scan --pattern 'tutorial:chapter16:item:*'
```

Inspect selected TTLs:

``` bash
redis-cli TTL tutorial:chapter16:item:1
redis-cli TTL tutorial:chapter16:item:2
redis-cli TTL tutorial:chapter16:item:3
```

The values should not all have identical expiration.

------------------------------------------------------------------------

# Part 29 --- Working-Set Priority Lab

## 50. Define Tiers

Add:

``` python
tier0 = list(range(1, 11))
tier1 = list(range(11, 51))
tier2 = list(range(51, 101))
```

Warm in order:

``` python
for name, tier in [
    ("tier0", tier0),
    ("tier1", tier1),
    ("tier2", tier2),
]:
    results, elapsed = warm_candidates(tier)
    print(name, len(results), round(elapsed, 3))
```

Production systems should evaluate source health between tiers.

------------------------------------------------------------------------

# Part 30 --- Rate-Limited Warmer

## 51. Simple Pacing

Concurrency alone may still produce too high a request rate when source
latency is low.

A simple lab pacing function:

``` python
def paced_warm(item_ids, max_per_second=20):
    interval = 1.0 / max_per_second

    for item_id in item_ids:
        started = time.perf_counter()
        warm_one(item_id)

        elapsed = time.perf_counter() - started
        remaining = interval - elapsed

        if remaining > 0:
            time.sleep(remaining)
```

For production, use a well-tested rate-limiting implementation
appropriate to the application.

------------------------------------------------------------------------

# Part 31 --- Refresh-Ahead Lab

## 52. Create `chapter16_refresh_ahead.py`

``` python
import json
import os
import random
import time
import uuid

import redis

HOST = os.getenv("REDIS_HOST", "localhost")
PORT = int(os.getenv("REDIS_PORT", "6379"))
PASSWORD = os.getenv("REDIS_PASSWORD") or None

r = redis.Redis(
    host=HOST,
    port=PORT,
    password=PASSWORD,
    decode_responses=True,
)

KEY = "tutorial:chapter16:refresh:item:1001"
LOCK = "tutorial:chapter16:refresh:lock:item:1001"

BASE_TTL = 30
TTL_JITTER = 5
REFRESH_THRESHOLD = 10
LOCK_TTL = 5

RELEASE_LOCK = """
if redis.call("GET", KEYS[1]) == ARGV[1] then
    return redis.call("DEL", KEYS[1])
else
    return 0
end
"""


def source_lookup():
    time.sleep(0.3)

    return {
        "id": 1001,
        "generated_at": time.time(),
    }


def populate():
    data = source_lookup()
    ttl = BASE_TTL + random.randint(0, TTL_JITTER)

    r.set(
        KEY,
        json.dumps(data),
        ex=ttl,
    )

    return ttl


def refresh_if_needed():
    ttl = r.ttl(KEY)

    if ttl == -2:
        print("Key missing; populating")
        print("New TTL:", populate())
        return

    if ttl > REFRESH_THRESHOLD:
        print("No refresh needed. TTL:", ttl)
        return

    token = str(uuid.uuid4())

    acquired = r.set(
        LOCK,
        token,
        nx=True,
        ex=LOCK_TTL,
    )

    if not acquired:
        print("Another worker owns refresh lock")
        return

    try:
        # Re-check after acquiring the lock.
        ttl = r.ttl(KEY)

        if ttl > REFRESH_THRESHOLD:
            print("Another worker already refreshed. TTL:", ttl)
            return

        print("Refreshing. Previous TTL:", ttl)
        new_ttl = populate()
        print("New TTL:", new_ttl)

    finally:
        r.eval(RELEASE_LOCK, 1, LOCK, token)


if __name__ == "__main__":
    refresh_if_needed()
```

------------------------------------------------------------------------

## 53. Run the Refresh Lab

``` bash
python chapter16_refresh_ahead.py
```

First run:

``` text
Key missing; populating
New TTL: ...
```

Run again while TTL is high:

``` text
No refresh needed. TTL: ...
```

Wait until TTL is 10 seconds or less and run again:

``` text
Refreshing. Previous TTL: ...
New TTL: ...
```

------------------------------------------------------------------------

# Part 32 --- Concurrent Refresh Test

## 54. Goal

Run multiple copies near the refresh threshold.

Expected:

``` text
one worker acquires refresh lock
other workers do not duplicate source refresh
```

This reuses the Chapter 15 single-flight principle.

------------------------------------------------------------------------

# Part 33 --- Demand-Aware Refresh

## 55. Production Pattern

Do not refresh merely because TTL is low.

Conceptually:

``` text
if recent_request_rate >= HOT_THRESHOLD
and ttl <= REFRESH_THRESHOLD:
    attempt_single_flight_refresh()
```

This avoids continuously refreshing cold objects.

------------------------------------------------------------------------

# Part 34 --- Deployment Warming Lab

## 56. Simulate New Namespace

Old:

``` text
tutorial:chapter16:v1:item:*
```

New:

``` text
tutorial:chapter16:v2:item:*
```

Warm selected v2 objects before moving traffic.

Validate:

``` text
candidate count
source calls
v2 key count
TTL distribution
source latency
```

------------------------------------------------------------------------

# Part 35 --- Failure Injection

## 57. Failure 1 --- Source Slowdown

Change:

``` python
SOURCE_LATENCY = 0.05
```

to:

``` python
SOURCE_LATENCY = 0.5
```

Observe warming duration and source concurrency.

Expected lesson:

``` text
fixed high concurrency becomes more expensive as source latency rises
```

------------------------------------------------------------------------

## 58. Failure 2 --- Excessive Concurrency

Increase:

``` python
MAX_WARM_WORKERS = 100
```

in an isolated lab.

Compare:

``` text
elapsed time
source inflight
source latency
errors
```

Do not assume faster completion means safer operation.

------------------------------------------------------------------------

## 59. Failure 3 --- No TTL Jitter

Set:

``` python
TTL_JITTER = 0
```

Warm all candidates.

Inspect TTLs.

Expected:

``` text
future expiration becomes synchronized
```

Restore jitter.

------------------------------------------------------------------------

## 60. Failure 4 --- Partial Warmer Crash

Stop the warming process midway.

Restart it.

Expected:

``` text
existing valid keys are skipped
missing keys continue warming
```

This validates idempotent restart behavior.

------------------------------------------------------------------------

## 61. Failure 5 --- Redis Write Failure

In an isolated environment, simulate a Redis connectivity/write error.

Expected production behavior:

``` text
do not report key as successfully warmed
record failure
bound retry
protect source
```

------------------------------------------------------------------------

## 62. Failure 6 --- Source Errors

Modify the mock source to fail a percentage of requests.

Expected:

``` text
bounded retry
error metrics
no infinite loop
no invalid cache entry
```

------------------------------------------------------------------------

## 63. Failure 7 --- Memory Pressure

Use a safe test environment to observe behavior when warming approaches
the configured cache memory limit.

Watch:

``` text
memory
evictions
hit ratio
latency
```

Do not deliberately create memory pressure in production.

------------------------------------------------------------------------

## 64. Failure 8 --- Recovery Storm

Simulate many workers beginning warming simultaneously.

Expected unprotected behavior:

``` text
source burst
```

Then add:

``` text
central coordination
rate limiting
jittered startup
bounded concurrency
```

------------------------------------------------------------------------

## 65. Failure 9 --- Refresh Herd

Run many refresh-ahead workers at the same low-TTL point.

Expected:

``` text
single-flight lock prevents duplicate refresh
```

------------------------------------------------------------------------

## 66. Failure 10 --- Bad Candidate List

Include many objects that receive no subsequent traffic.

Measure:

``` text
warming source cost
Redis memory consumed
actual later hits
```

This demonstrates why working-set quality matters.

------------------------------------------------------------------------

# Part 36 --- Observability

## 67. Warmer Metrics

Track:

``` text
warming_candidates_total
warming_attempt_total
warming_success_total
warming_failure_total
warming_skipped_total
warming_duration_seconds
warming_inflight
warming_rate
```

------------------------------------------------------------------------

## 68. Refresh Metrics

Track:

``` text
refresh_ahead_attempt_total
refresh_ahead_success_total
refresh_ahead_failure_total
refresh_lock_contention_total
refresh_duration_seconds
```

------------------------------------------------------------------------

## 69. Cache Metrics

Track:

``` text
cache_hit_ratio
cache_miss_total
expired_keys
evictions
memory utilization
Redis latency
operations/sec
```

------------------------------------------------------------------------

## 70. Source Metrics

Track:

``` text
source QPS
source inflight
source p50/p95/p99 latency
source errors
source timeouts
source connection utilization
```

------------------------------------------------------------------------

# Part 37 --- Warming Effectiveness

## 71. Useful Measures

### Post-Warm Hit Ratio

``` text
hits after warm / reads after warm
```

### Warm Utility

Conceptually:

``` text
warmed keys subsequently used / total warmed keys
```

### Source Cost per Useful Warm

``` text
source work / useful warmed objects
```

A huge key count is not itself evidence of successful warming.

------------------------------------------------------------------------

# Part 38 --- Alerting

## 72. Alert Conditions

Examples:

``` text
warming source QPS > budget
source p99 > threshold during warming
warming error rate > threshold
Redis memory > threshold
evictions rise during warm
warm completion stalls
post-warm hit ratio below target
refresh failures increase
```

------------------------------------------------------------------------

# Part 39 --- Troubleshooting

## 73. Warming Is Too Slow

Check:

``` text
source latency
worker concurrency
rate limit
network
serialization
Redis latency
error/retry rate
candidate count
```

Do not immediately raise concurrency.

------------------------------------------------------------------------

## 74. Source Becomes Slow

``` text
reduce/pause warming
preserve normal application traffic
check source saturation
check connection usage
check query latency
resume gradually
```

------------------------------------------------------------------------

## 75. Redis Memory Rises Too Quickly

Check:

``` text
candidate quality
value size
TTL
existing memory
evictions
working-set estimate
```

Reduce warming scope before simply adding more data.

------------------------------------------------------------------------

## 76. Hit Ratio Does Not Improve

Possible causes:

``` text
wrong objects warmed
traffic changed
key construction mismatch
namespace mismatch
keys expire too soon
evictions remove warmed keys
application bypasses expected cache path
```

------------------------------------------------------------------------

## 77. Keys Expire Together Later

Cause:

``` text
warming assigned identical TTLs
```

Correct:

``` text
apply appropriate TTL jitter
```

------------------------------------------------------------------------

## 78. Refresh-Ahead Generates High Source Load

Check:

``` text
too many eligible keys
refresh threshold too large
no popularity filter
no coordination
scheduler synchronization
source budget absent
```

------------------------------------------------------------------------

## 79. Warmer Restart Repeats Work

Check whether it verifies cache state before loading the source.

A restart-safe warmer should avoid unnecessary reload of valid objects.

------------------------------------------------------------------------

# Part 40 --- Production Runbooks

## 80. Runbook --- Planned Cold Start

``` text
1. Identify required working set.
2. Rank candidates by priority.
3. Confirm Redis memory capacity.
4. Confirm source warming budget.
5. Set concurrency and rate limits.
6. Configure TTL jitter.
7. Warm Tier 0.
8. Validate source and Redis health.
9. Warm Tier 1.
10. Validate hit ratio.
11. Shift traffic gradually.
12. Continue lower-priority warming only while healthy.
13. Record completion metrics.
```

------------------------------------------------------------------------

## 81. Runbook --- New Deployment Namespace

``` text
1. Confirm old/new key naming.
2. Estimate new working-set size.
3. Confirm temporary memory requirement.
4. Pre-warm critical new keys.
5. Validate key correctness.
6. Validate TTL distribution.
7. Validate source health.
8. Shift small traffic percentage.
9. Observe hit/miss ratio.
10. Increase traffic gradually.
11. Preserve rollback path.
12. Retire old namespace only under approved cleanup policy.
```

------------------------------------------------------------------------

## 82. Runbook --- DR / Regional Failover

``` text
1. Confirm Redis target availability.
2. Determine cache readiness.
3. Identify Tier 0/Tier 1 objects.
4. Confirm source capacity in recovery region.
5. Set conservative warming budget.
6. Warm critical objects.
7. Validate application path.
8. Introduce traffic gradually.
9. Continue demand-aware warming.
10. Monitor source and Redis.
11. Prevent retry/recovery storm.
12. Declare cache readiness only after acceptance thresholds pass.
```

------------------------------------------------------------------------

## 83. Runbook --- Source Degradation During Warm

``` text
1. Stop increasing warm rate.
2. Reduce concurrency/rate.
3. Measure source p95/p99.
4. Check errors/timeouts.
5. Preserve application headroom.
6. Pause warming if threshold breached.
7. Wait for stable recovery.
8. Resume at lower rate.
9. Ramp gradually.
10. document safe rate discovered.
```

------------------------------------------------------------------------

## 84. Runbook --- Recovery Storm

``` text
1. Identify simultaneous warmers/retries.
2. Apply global source limit.
3. Jitter worker startup.
4. Prioritize critical candidates.
5. Drain backlog gradually.
6. Monitor source latency.
7. Monitor Redis latency/memory.
8. Stop ramp if source degrades.
9. Confirm stable hit-ratio recovery.
10. Correct startup coordination.
```

------------------------------------------------------------------------

# Part 41 --- Capacity Review Template

## 85. Review Fields

``` text
Service:
Redis database:
Source:
Candidate count:
Tier 0 count:
Tier 1 count:
Estimated value size:
Expected working-set memory:
Redis available memory:
Normal source QPS:
Source sustainable QPS:
Reserved source headroom:
Approved warming QPS:
Approved warming concurrency:
Source p95:
Source p99:
Base TTL:
TTL jitter:
Refresh threshold:
Refresh candidate rule:
Expected warm duration:
Abort threshold:
Deployment warm plan:
DR warm plan:
Owner:
```

------------------------------------------------------------------------

# Part 42 --- Production Acceptance Checklist

## 86. Warming Design

-   [ ] Working set defined.
-   [ ] Candidate source documented.
-   [ ] Priority tiers defined.
-   [ ] Redis memory capacity reviewed.
-   [ ] Source sustainable capacity measured.
-   [ ] Warming QPS budget documented.
-   [ ] Warming concurrency bounded.
-   [ ] Rate limiting implemented where required.
-   [ ] TTL jitter defined.
-   [ ] Existing valid keys skipped safely.
-   [ ] Warmer restart is idempotent.
-   [ ] Failure/retry behavior bounded.
-   [ ] Abort thresholds defined.
-   [ ] Source health checked during warming.
-   [ ] Redis health checked during warming.
-   [ ] Post-warm hit-ratio target defined.
-   [ ] Deployment warming tested.
-   [ ] DR warming tested.
-   [ ] Recovery-storm controls tested.

------------------------------------------------------------------------

## 87. Refresh-Ahead Design

-   [ ] Refresh candidates are demand-aware.
-   [ ] Refresh threshold documented.
-   [ ] Refresh is single-flight/coordinated.
-   [ ] Refresh scheduling is not synchronized.
-   [ ] Source refresh budget documented.
-   [ ] Refresh failure behavior documented.
-   [ ] Existing value remains usable only where business semantics
    allow.
-   [ ] Refresh metrics and alerts exist.

------------------------------------------------------------------------

# Knowledge Validation

## 88. Questions

You should be able to answer:

1.  What makes a cache operationally cold?
2.  Why is key count not enough to determine cache readiness?
3.  Why should you avoid warming every possible object?
4.  What is a cache working set?
5.  Which signals can identify high-value warming candidates?
6.  What is demand-driven warming?
7.  What is proactive warming?
8.  Why is a hybrid strategy often useful?
9.  How do you calculate a source warming budget?
10. What is the difference between rate and concurrency limiting?
11. Why must warmed keys use TTL distribution/jitter?
12. How can a successful warm create a future expiration incident?
13. What is refresh-ahead?
14. Why should refresh-ahead be demand-aware?
15. Why does refresh-ahead require single-flight coordination?
16. Why should refresh schedules use jitter?
17. What should be warmed before deployment traffic shifts?
18. How can blue/green namespaces reduce cold-start risk?
19. What cache concern belongs in a DR plan?
20. What is a recovery storm?
21. How can warming cause eviction thrash?
22. How do you estimate warming duration?
23. Which conditions should pause or abort warming?
24. Why should a warmer be idempotent?
25. Why check Redis before querying the source?
26. Which metrics prove warming is useful?
27. Why can hit ratio remain poor after warming?
28. How should source degradation change warming behavior?
29. Why is a huge warmed-key count not a success metric by itself?
30. What must pass before declaring cold-start readiness?

------------------------------------------------------------------------

# Part 43 --- Hands-On Acceptance

## 89. Lab Checklist

-   [ ] Connected to isolated Redis lab.
-   [ ] Created cold-cache workload.
-   [ ] Built controlled warmer.
-   [ ] Warmed 100 candidate objects.
-   [ ] Verified post-warm cache hits.
-   [ ] Verified source calls dropped after warming.
-   [ ] Verified TTL distribution.
-   [ ] Built priority tiers.
-   [ ] Tested bounded concurrency.
-   [ ] Reviewed rate-limited warming.
-   [ ] Implemented refresh-ahead.
-   [ ] Verified refresh threshold.
-   [ ] Verified refresh single-flight behavior.
-   [ ] Simulated source slowdown.
-   [ ] Tested excessive-concurrency scenario.
-   [ ] Tested no-jitter scenario.
-   [ ] Tested partial warmer restart.
-   [ ] Reviewed Redis write failure behavior.
-   [ ] Reviewed source error behavior.
-   [ ] Reviewed memory-pressure behavior.
-   [ ] Reviewed recovery storm.
-   [ ] Reviewed bad candidate list.
-   [ ] Completed troubleshooting.
-   [ ] Completed production runbooks.
-   [ ] Completed production acceptance checklist.

------------------------------------------------------------------------

# Part 44 --- Safe Cleanup

## 90. Discover Only Chapter Keys

``` bash
redis-cli --scan --pattern 'tutorial:chapter16:*'
```

Review the result before deleting anything.

------------------------------------------------------------------------

## 91. Delete Exact Lab Keys

Examples:

``` bash
redis-cli UNLINK tutorial:chapter16:refresh:item:1001
redis-cli UNLINK tutorial:chapter16:refresh:lock:item:1001
```

For the generated `tutorial:chapter16:item:*` population, enumerate only
the chapter namespace and delete those confirmed training keys.

Do not use:

``` text
FLUSHDB
FLUSHALL
```

in a shared or production database.

------------------------------------------------------------------------

# Part 45 --- Key Takeaways

## 92. Production Lessons

1.  Cache warming is a source-capacity exercise, not merely a Redis
    loading exercise.
2.  A cache can contain many keys and still be operationally cold.
3.  Warm the useful working set rather than the entire possible dataset.
4.  Prioritize critical and hot objects first.
5.  Bound both warming concurrency and warming rate.
6.  Preserve source headroom for normal application traffic.
7.  Add TTL jitter during warming so today's recovery does not schedule
    tomorrow's expiration storm.
8.  Refresh-ahead is most valuable for predictably hot objects.
9.  Refresh-ahead requires coordination to avoid refresh herds.
10. Demand-aware refresh avoids wasting source capacity on cold objects.
11. Deployment namespace changes require explicit cold-start planning.
12. DR readiness includes cache readiness.
13. Redis recovery can trigger a repopulation storm.
14. Warming must fit Redis memory without causing eviction thrash.
15. A warmer must be restart-safe and idempotent.
16. A warmer must have pause/abort thresholds.
17. Post-warm hit ratio matters more than total warmed-key count.
18. Source, Redis, and application metrics must be evaluated together.
19. Cold-cache and recovery behavior must be load tested before
    production.
20. The fastest safe warming rate is more important than the maximum
    possible warming rate.

------------------------------------------------------------------------

# 93. References

Validate behavior against the Redis/Redis Enterprise and client versions
deployed.

Recommended official Redis documentation areas:

-   `SET`
-   `GET`
-   `EXPIRE`
-   `TTL` / `PTTL`
-   `SCAN`
-   `UNLINK`
-   key expiration
-   Redis as a cache
-   Redis client behavior
-   Redis Enterprise observability and database operations

Cache warming, working-set ranking, refresh-ahead, source rate limiting,
and deployment/DR warming are application and platform architecture
patterns. Their exact implementation depends on workload semantics,
source capacity, client framework, topology, and recovery requirements.

------------------------------------------------------------------------

# Next Chapter

**Chapter 17 --- Redis Eviction Policies, Memory Pressure & Cache
Survival Engineering**

Chapter 17 will cover:

-   `maxmemory`
-   eviction policy behavior
-   `noeviction`
-   `allkeys-*`
-   `volatile-*`
-   LRU/LFU concepts
-   TTL-aware eviction
-   memory headroom
-   hot vs. cold object survival
-   eviction storms
-   oversized values
-   fragmentation considerations
-   cache hit-ratio impact
-   failure injection
-   troubleshooting
-   production runbooks
-   observability
-   acceptance validation
