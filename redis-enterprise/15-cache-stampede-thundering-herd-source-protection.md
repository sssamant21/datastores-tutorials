# Chapter 15 --- Cache Stampede, Thundering Herd & Source Protection

## 1. Overview

Redis is often placed in front of databases, APIs, search platforms, and
other expensive source systems. A cache stampede occurs when many
requests miss the same cached data at approximately the same time and
independently regenerate it.

``` text
Normal:
1000 requests -> 999 Redis hits -> 1 source request

Stampede:
1000 requests -> many Redis misses -> hundreds of duplicate source requests
```

The cache itself can remain healthy while the database or API behind it
becomes overloaded. A production cache design must therefore protect
both Redis and the source system.

## 2. Learning Objectives

After this chapter you should be able to:

-   distinguish cache stampede from the broader thundering-herd effect;
-   identify synchronized TTL expiration and hot-key risks;
-   apply TTL jitter;
-   implement request coalescing/single-flight with Redis;
-   use lock TTLs and ownership-safe lock release;
-   apply stale-while-revalidate with soft and hard TTLs;
-   use negative caching appropriately;
-   add retry backoff and jitter;
-   bound source concurrency and fallback traffic;
-   observe cache misses, refreshes, contention, and source
    amplification;
-   reproduce and mitigate a stampede in a hands-on lab.

## 3. Cache Stampede and Thundering Herd

A cache-aside application normally does this:

``` text
GET cache key
   |
   +-- HIT  -> return cached value
   |
   +-- MISS -> query source -> SET cache -> return value
```

If a hot key expires while many requests are arriving, multiple workers
can all observe the miss before any worker has rebuilt the key.

``` text
Request A -> MISS -> DB
Request B -> MISS -> DB
Request C -> MISS -> DB
Request D -> MISS -> DB
```

A **cache stampede** specifically describes concurrent cache
regeneration. A **thundering herd** is the broader synchronization
problem where many workers wake, retry, reconnect, or compete for the
same resource simultaneously.

## 4. Why This Becomes a Production Incident

Suppose:

``` text
Application traffic: 20,000 requests/sec
Cache hit ratio:      99%
Normal source load:   ~200 requests/sec
```

If the hit ratio suddenly drops to 40%:

``` text
Source load: ~12,000 requests/sec
```

The source may never have been sized for that traffic.

A typical cascade is:

``` text
cache misses increase
        |
source requests increase
        |
source latency increases
        |
application requests remain active longer
        |
worker/thread pressure increases
        |
retries increase
        |
source load increases again
```

This is why source protection is part of cache reliability.

## 5. Common Triggers

### 5.1 Synchronized expiration

Thousands of keys written together with the same TTL can expire
together.

``` text
SET key:1 value EX 300
SET key:2 value EX 300
...
SET key:100000 value EX 300
```

### 5.2 Hot-key expiration

A single key such as `homepage:config` or `product:popular` may receive
thousands of requests per second. Expiration of that one key can be
enough to overload the source.

### 5.3 Cache flush or mass invalidation

`FLUSHDB`, `FLUSHALL`, or broad deletion can instantly remove source
protection.

### 5.4 Cold cache after deployment

New key prefixes, schemas, serialization formats, or namespaces can make
the existing cache unusable.

### 5.5 Redis connectivity failure

This fallback is dangerous at scale:

``` python
try:
    return redis_get()
except Exception:
    return database_query()
```

If Redis fails, all application traffic can fall through to the
database.

### 5.6 Synchronized retries

Fixed-delay retries can create recurring herds:

``` text
failure -> all clients wait 1 second -> all retry together
```

## 6. Pattern 1 --- TTL Jitter

Instead of assigning every key:

``` text
TTL = 300
```

use:

``` text
TTL = base TTL + random jitter
```

Example:

``` python
import random

BASE_TTL = 300
JITTER = 60

ttl = BASE_TTL + random.randint(0, JITTER)
r.set(key, value, ex=ttl)
```

Keys now expire over a range rather than at one instant.

TTL jitter is especially useful for bulk-loaded, batch-generated, or
cache-warmed key populations.

It does **not** fully solve expiration of one extremely hot key. That
requires regeneration coordination.

## 7. Pattern 2 --- Request Coalescing / Single Flight

The goal is:

> When many requests miss the same key, only one worker should
> regenerate it.

``` text
A -> MISS -> gets lock -> source
B -> MISS -> lock busy -> wait
C -> MISS -> lock busy -> wait
D -> MISS -> lock busy -> wait

A -> writes cache -> releases lock
B/C/D -> retry cache -> HIT
```

The source receives approximately one lookup instead of many duplicate
lookups.

## 8. Redis Lock Primitive

A common primitive is:

``` bash
redis-cli SET lock:product:1001 worker-token NX EX 5
```

`NX` means create only if the lock does not already exist. `EX 5` gives
the lock a five-second expiration so a crashed owner cannot leave it
indefinitely.

Each owner should use a unique token.

## 9. Safe Lock Release

Never blindly run `DEL lock:key` after work completes. The original lock
may have expired and another worker may now own a new lock.

Use an ownership token and compare-and-delete atomically:

``` lua
if redis.call("GET", KEYS[1]) == ARGV[1] then
    return redis.call("DEL", KEYS[1])
else
    return 0
end
```

Python:

``` python
RELEASE_LOCK = """
if redis.call("GET", KEYS[1]) == ARGV[1] then
    return redis.call("DEL", KEYS[1])
else
    return 0
end
"""

r.eval(RELEASE_LOCK, 1, lock_key, token)
```

## 10. Double-Check After Lock Acquisition

A worker can observe a miss, wait for a lock, then obtain the lock after
another worker has already rebuilt the cache. Therefore recheck Redis
after acquiring the lock:

``` python
value = r.get(cache_key)
if value is not None:
    return value
```

This prevents unnecessary duplicate source queries.

## 11. Choosing Lock TTL

The lock TTL must exceed normal regeneration time with allowance for
tail latency.

Consider:

``` text
normal source latency = 100 ms
p99 source latency    = 700 ms
occasional slow load  = 2 sec
```

A 200 ms lock is unsafe because it may expire while the owner is still
rebuilding the cache.

An excessively long lock is also undesirable because expiration is the
recovery mechanism after owner failure.

Measure refresh latency and choose a bounded value appropriate for the
workload.

## 12. Pattern 3 --- Stale-While-Revalidate

For data where bounded staleness is acceptable:

``` text
fresh value -> serve normally

soft-expired value ->
    serve stale value
    one worker refreshes

hard-expired value ->
    no longer serve stale value
```

This separates **freshness** from **retention**.

Example:

``` text
0 sec                 300 sec                 600 sec
|------------------------|------------------------|
       fresh period           stale window
                         soft TTL              hard TTL
```

A payload can contain its soft-expiration timestamp while the Redis key
uses a longer hard TTL.

``` json
{
  "data": {"id": 1001, "name": "example"},
  "fresh_until": 1791400000
}
```

## 13. Pattern 4 --- Negative Caching

Repeated requests for nonexistent objects can also overload a source.

``` text
GET patient:999999 -> cache MISS -> DB NOT FOUND
```

Without negative caching, every request repeats the database lookup.

A short-lived negative entry can absorb these requests:

``` text
patient:999999 -> NOT_FOUND
TTL -> 30 seconds
```

Negative TTLs are normally shorter than normal data TTLs because the
object may be created later.

## 14. Pattern 5 --- Backoff and Jitter

Avoid immediate or fixed synchronized retries.

``` python
import random
import time

def backoff(attempt):
    maximum = min(0.1 * (2 ** attempt), 5.0)
    time.sleep(random.uniform(0, maximum))
```

Jitter spreads retry attempts over time.

## 15. Pattern 6 --- Global Source Protection

Per-key locking protects against duplicate work for one key, but it does
not protect the source when many different keys miss simultaneously.

``` text
key:1 -> MISS
key:2 -> MISS
...
key:100000 -> MISS
```

Use another layer such as:

-   application semaphore;
-   bounded worker pool;
-   rate limiter;
-   queue;
-   bulkhead;
-   admission control.

Architecture:

``` text
Requests
   |
 Redis
   |
 MISS
   |
per-key single flight
   |
global source concurrency limit
   |
Database / API
```

## 16. Redis Failure Must Not Become Database Failure

If normal database traffic is 300 QPS but application traffic is 30,000
QPS, unlimited fallback during a Redis outage can send all 30,000 QPS to
the database.

Possible protections include:

-   bounded source fallback;
-   stale local data where safe;
-   circuit breaking;
-   rate limiting;
-   controlled degradation;
-   local in-process caching;
-   disabling optional features;
-   queued refresh.

## 17. Redis Enterprise Operational View

Redis Enterprise can be healthy while the caching architecture is
unhealthy.

Correlate:

``` text
Redis latency
Redis operations/sec
Redis memory
Redis evictions/expirations
client connections

WITH

application hit ratio
cache misses
refresh attempts
lock contention
source QPS
source latency
source errors
```

A database CPU spike following a cache-hit-ratio drop can be a cache
stampede even when Redis CPU and latency remain normal.

------------------------------------------------------------------------

# Hands-On Lab --- Reproduce and Prevent a Cache Stampede

## 18. Lab Objectives

You will:

1.  simulate a slow source;
2.  implement naive cache-aside;
3.  generate concurrent requests;
4.  reproduce a hot-key stampede;
5.  implement single-flight locking;
6.  add TTL jitter;
7.  compare source-call counts;
8.  test lock recovery;
9.  implement stale-while-revalidate;
10. inject source slowdown/failure;
11. validate source protection.

## 19. Prerequisites

Required:

-   Redis or Redis Enterprise endpoint;
-   Python 3.9+;
-   `redis-cli`;
-   Python `redis` package.

Install:

``` bash
python -m pip install redis
```

Environment variables:

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

Do not commit production credentials into lab files.

## 20. Verify Connectivity

Without authentication:

``` bash
redis-cli -h localhost -p 6379 PING
```

Expected:

``` text
PONG
```

Authenticated example:

``` bash
redis-cli -h <host> -p <port> -a "<password>" PING
```

Use the TLS parameters required by your Redis Enterprise deployment when
applicable.

## 21. Create the Stampede Lab

Create `chapter15_stampede_lab.py`:

``` python
import json
import os
import random
import threading
import time
import uuid
from concurrent.futures import ThreadPoolExecutor

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

CACHE_KEY = "lab:chapter15:item:1001"
LOCK_KEY = "lab:chapter15:lock:item:1001"

SOURCE_LATENCY = 0.30
CACHE_TTL = 5
LOCK_TTL = 5

source_calls = 0
source_counter_lock = threading.Lock()

RELEASE_LOCK = """
if redis.call("GET", KEYS[1]) == ARGV[1] then
    return redis.call("DEL", KEYS[1])
else
    return 0
end
"""

def reset_source_counter():
    global source_calls
    with source_counter_lock:
        source_calls = 0

def source_lookup(item_id):
    global source_calls
    with source_counter_lock:
        source_calls += 1

    time.sleep(SOURCE_LATENCY)
    return {
        "id": item_id,
        "name": "chapter-15-demo",
        "generated_at": time.time(),
    }

def naive_get(item_id):
    value = r.get(CACHE_KEY)
    if value is not None:
        return json.loads(value)

    data = source_lookup(item_id)
    r.set(CACHE_KEY, json.dumps(data), ex=CACHE_TTL)
    return data

def protected_get(item_id):
    value = r.get(CACHE_KEY)
    if value is not None:
        return json.loads(value)

    token = str(uuid.uuid4())
    acquired = r.set(LOCK_KEY, token, nx=True, ex=LOCK_TTL)

    if acquired:
        try:
            # Double-check after obtaining ownership.
            value = r.get(CACHE_KEY)
            if value is not None:
                return json.loads(value)

            data = source_lookup(item_id)
            ttl = CACHE_TTL + random.randint(0, 2)
            r.set(CACHE_KEY, json.dumps(data), ex=ttl)
            return data
        finally:
            r.eval(RELEASE_LOCK, 1, LOCK_KEY, token)

    # Another worker is rebuilding the cache.
    for _ in range(30):
        time.sleep(random.uniform(0.02, 0.08))
        value = r.get(CACHE_KEY)
        if value is not None:
            return json.loads(value)

    raise RuntimeError("Timed out waiting for cache regeneration")

def run_load_test(name, function, workers=50):
    r.delete(CACHE_KEY)
    r.delete(LOCK_KEY)
    reset_source_counter()

    start = time.perf_counter()

    with ThreadPoolExecutor(max_workers=workers) as pool:
        futures = [pool.submit(function, 1001) for _ in range(workers)]
        for future in futures:
            future.result()

    elapsed = time.perf_counter() - start

    print()
    print("=" * 60)
    print(name)
    print("=" * 60)
    print(f"Concurrent requests : {workers}")
    print(f"Source calls        : {source_calls}")
    print(f"Elapsed seconds     : {elapsed:.3f}")
    print(f"Cache exists        : {bool(r.exists(CACHE_KEY))}")
    print(f"Cache TTL           : {r.ttl(CACHE_KEY)}")

if __name__ == "__main__":
    print("Redis ping:", r.ping())

    run_load_test(
        "TEST 1 - NAIVE CACHE-ASIDE",
        naive_get,
        workers=50,
    )

    run_load_test(
        "TEST 2 - SINGLE-FLIGHT PROTECTION",
        protected_get,
        workers=50,
    )
```

## 22. Run the Baseline

``` bash
python chapter15_stampede_lab.py
```

A typical naive result may resemble:

``` text
TEST 1 - NAIVE CACHE-ASIDE
Concurrent requests : 50
Source calls        : 50
```

The exact count varies with scheduling, but many workers can reach the
source during the miss window.

The protected test should be much closer to:

``` text
TEST 2 - SINGLE-FLIGHT PROTECTION
Concurrent requests : 50
Source calls        : 1
```

This is the central acceptance result:

``` text
many callers
+
one cache regeneration
```

## 23. Increase Concurrency

Change:

``` python
workers=50
```

to:

``` python
workers=200
```

Run again.

Compare source calls between naive and protected implementations.

The protected implementation should continue coalescing requests for the
same key.

## 24. Inspect the Hot Key

``` bash
redis-cli GET lab:chapter15:item:1001
redis-cli TTL lab:chapter15:item:1001
redis-cli PTTL lab:chapter15:item:1001
```

Inspect the lock while regeneration is active:

``` bash
redis-cli GET lab:chapter15:lock:item:1001
redis-cli PTTL lab:chapter15:lock:item:1001
```

## 25. Force the Hot-Key Miss

``` bash
redis-cli DEL lab:chapter15:item:1001
```

Immediately run the concurrent test again.

This models the critical window immediately after hot-key expiration or
invalidation.

## 26. TTL Jitter Experiment

Create synchronized keys:

``` bash
redis-cli SET lab:jitter:1 value EX 60
redis-cli SET lab:jitter:2 value EX 60
redis-cli SET lab:jitter:3 value EX 60
redis-cli SET lab:jitter:4 value EX 60
redis-cli SET lab:jitter:5 value EX 60
```

Check:

``` bash
redis-cli TTL lab:jitter:1
redis-cli TTL lab:jitter:2
redis-cli TTL lab:jitter:3
redis-cli TTL lab:jitter:4
redis-cli TTL lab:jitter:5
```

Now distribute expirations:

``` python
import random
import redis

r = redis.Redis(host="localhost", port=6379, decode_responses=True)

for i in range(1, 11):
    ttl = 60 + random.randint(0, 30)
    r.set(f"lab:jitter:{i}", "value", ex=ttl)
    print(f"lab:jitter:{i} -> {ttl}s")
```

The resulting TTLs should be spread over a range instead of expiring
together.

------------------------------------------------------------------------

# Stale-While-Revalidate Lab

## 27. Create `chapter15_stale_cache.py`

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

CACHE_KEY = "lab:chapter15:stale:item:1001"
LOCK_KEY = "lab:chapter15:stale:lock:item:1001"

SOFT_TTL = 10
HARD_TTL = 30
LOCK_TTL = 5

RELEASE_LOCK = """
if redis.call("GET", KEYS[1]) == ARGV[1] then
    return redis.call("DEL", KEYS[1])
else
    return 0
end
"""

def source_lookup():
    time.sleep(0.5)
    return {
        "id": 1001,
        "value": "source-value",
        "generated_at": time.time(),
    }

def write_cache(data):
    payload = {
        "data": data,
        "fresh_until": time.time() + SOFT_TTL,
    }
    r.set(
        CACHE_KEY,
        json.dumps(payload),
        ex=HARD_TTL + random.randint(0, 5),
    )

def read_cache():
    raw = r.get(CACHE_KEY)
    if raw is None:
        return None, "missing"

    payload = json.loads(raw)

    if time.time() <= payload["fresh_until"]:
        return payload["data"], "fresh"

    return payload["data"], "stale"

def refresh_if_owner():
    token = str(uuid.uuid4())
    acquired = r.set(LOCK_KEY, token, nx=True, ex=LOCK_TTL)

    if not acquired:
        return False

    try:
        data = source_lookup()
        write_cache(data)
        return True
    finally:
        r.eval(RELEASE_LOCK, 1, LOCK_KEY, token)

def get_value():
    data, state = read_cache()

    if state == "fresh":
        print("Serving FRESH value")
        return data

    if state == "stale":
        print("Serving STALE value")
        refreshed = refresh_if_owner()
        if refreshed:
            print("This worker refreshed the cache")
        else:
            print("Another worker is refreshing the cache")
        return data

    print("Cache missing; rebuilding")

    if refresh_if_owner():
        data, _ = read_cache()
        return data

    for _ in range(30):
        time.sleep(0.05)
        data, _ = read_cache()
        if data is not None:
            return data

    raise RuntimeError("Unable to rebuild cache")

if __name__ == "__main__":
    print(get_value())
```

Run:

``` bash
python chapter15_stale_cache.py
```

First run:

``` text
Cache missing; rebuilding
```

Run again immediately:

``` text
Serving FRESH value
```

Wait longer than the 10-second soft TTL but less than the hard TTL and
run again:

``` text
Serving STALE value
This worker refreshed the cache
```

The stale value remains available while refresh is coordinated.

> In a real application, refresh can be dispatched asynchronously so the
> stale-serving request does not wait for source regeneration.

------------------------------------------------------------------------

# Failure Injection

## 28. Slow Source Test

Temporarily increase:

``` python
time.sleep(0.5)
```

to:

``` python
time.sleep(4)
```

Run concurrent requests.

Observe:

-   regeneration duration;
-   lock TTL;
-   waiter behavior;
-   stale serving;
-   source-call count.

If regeneration can exceed the lock TTL, either choose a safer TTL or
implement a carefully designed lease-extension mechanism.

## 29. Source Failure Test

Temporarily replace:

``` python
def source_lookup():
    time.sleep(0.5)
    raise RuntimeError("simulated source failure")
```

Define the intended production behavior.

Where data semantics permit it, a useful policy may be:

``` text
serve bounded stale value
+
record refresh failure
+
back off before next refresh
```

Do not serve stale data when correctness, authorization, security, or
other business requirements require current data.

## 30. Lock Owner Failure

Create a lock:

``` bash
redis-cli SET lab:chapter15:testlock owner-1 NX EX 5
```

Verify:

``` bash
redis-cli GET lab:chapter15:testlock
redis-cli TTL lab:chapter15:testlock
```

Do not delete it.

After expiration:

``` bash
redis-cli EXISTS lab:chapter15:testlock
```

Expected:

``` text
(integer) 0
```

The TTL prevents a crashed owner from leaving an indefinite lock.

------------------------------------------------------------------------

# Observability

## 31. Application Metrics

Track metrics such as:

``` text
cache_hits_total
cache_misses_total
cache_hit_ratio
cache_refresh_total
cache_refresh_failures_total
cache_stale_served_total
cache_lock_acquired_total
cache_lock_contention_total
cache_wait_timeout_total
```

## 32. Source Metrics

Track:

``` text
source_requests_total
source_latency
source_errors
source_timeouts
source_concurrency
```

## 33. Redis Metrics

Observe:

-   operation latency;
-   operations/sec;
-   memory utilization;
-   evictions;
-   expirations;
-   client connections;
-   network throughput;
-   CPU utilization;
-   database availability.

The useful incident correlation is often:

``` text
cache misses ↑
source requests ↑
source latency ↑
application latency ↑
```

## 34. Source Amplification

A useful conceptual metric is:

``` text
source lookups / cache misses
```

Without coordination:

``` text
100 misses
100 source lookups
ratio = 1.0
```

With effective single flight:

``` text
100 misses
1 source lookup
ratio = 0.01
```

The exact metric definition can be adapted to the application, but the
objective is to detect redundant source work.

------------------------------------------------------------------------

# Troubleshooting Runbook

## 35. Database/API Load Suddenly Increased

Check, in order:

1.  application cache hit ratio;
2.  cache miss rate;
3.  recent key expiration or invalidation events;
4.  Redis connectivity errors/timeouts;
5.  source QPS and latency;
6.  retry rate;
7.  hot-key traffic;
8.  refresh/lock contention;
9.  source concurrency.

A cache-hit-ratio drop aligned with a source-QPS spike is a strong
signal.

## 36. One Hot Key Overloads the Source

Validate:

``` text
request rate
cache TTL
source latency
lock behavior
```

Preferred pattern:

``` text
single-flight regeneration
+
stale-while-revalidate where safe
```

TTL jitter alone cannot prevent a stampede on one hot key.

## 37. Redis Failure Overloads the Database

Look for:

``` text
Redis error -> unlimited source fallback
```

Replace it with bounded behavior:

``` text
Redis error
   |
   +-- stale/local cache where safe
   +-- source concurrency limit
   +-- rate limiting
   +-- circuit breaker
   +-- controlled degradation
```

## 38. Lock Contention Is High

High contention may indicate:

-   extremely hot key;
-   slow source;
-   expensive regeneration;
-   cache TTL too short;
-   lock TTL too short;
-   failed cache writes;
-   repeated refresh failure.

Check refresh latency before treating lock contention as a Redis
performance problem.

## 39. Multiple Workers Still Reach the Source

Possible causes:

-   lock TTL expires before refresh completes;
-   workers use different lock-key names;
-   lock acquisition result is ignored;
-   lock is deleted without ownership verification;
-   cache is not double-checked after lock acquisition;
-   Redis errors bypass coordination;
-   multiple application layers use inconsistent cache logic.

------------------------------------------------------------------------

# Production Safety

## 40. Avoid Broad Cache Flushes

Do not use these as routine production troubleshooting actions:

``` text
FLUSHDB
FLUSHALL
```

A warm cache can become cold instantly, transferring traffic to the
source.

## 41. Avoid Mass Synchronized Invalidation

Deleting a very large key population at once can produce the same
cold-cache effect.

Use controlled invalidation and staged warming where practical.

## 42. Avoid Synchronized Refresh Schedules

If every worker refreshes at exactly midnight, the refresh system itself
can become a thundering herd.

Use scheduling jitter where appropriate.

## 43. Cold-Cache Testing

A production readiness test should include:

``` text
empty cache
+
representative request concurrency
+
realistic source latency
```

Measure whether the source remains within safe capacity.

------------------------------------------------------------------------

# Production Checklist

## 44. Readiness Checklist

-   [ ] Cache hit ratio is observable.
-   [ ] Source request rate is observable.
-   [ ] Hot keys are understood.
-   [ ] TTLs match data semantics.
-   [ ] Large key populations do not share synchronized expiration
    unnecessarily.
-   [ ] TTL jitter is applied where appropriate.
-   [ ] Hot-key regeneration is coalesced.
-   [ ] Lock owners use unique tokens.
-   [ ] Locks have bounded TTLs.
-   [ ] Lock release validates ownership.
-   [ ] Cache is double-checked after lock acquisition.
-   [ ] Waiter behavior is bounded.
-   [ ] Retries use backoff and jitter.
-   [ ] Negative caching is considered for repeated not-found lookups.
-   [ ] Stale-while-revalidate is used only where stale data is
    acceptable.
-   [ ] Source concurrency is bounded.
-   [ ] Redis failure does not create unlimited source fallback.
-   [ ] Cache flush procedures account for source capacity.
-   [ ] Cold-cache behavior is load tested.
-   [ ] Source slowdown and failure are tested.
-   [ ] Dashboards correlate Redis, application, and source metrics.

------------------------------------------------------------------------

# Acceptance Validation

## 45. Required Tests

### Test A --- Naive stampede

Run concurrent requests against an empty cache.

Expected:

``` text
multiple source lookups
```

### Test B --- Single flight

Run the same workload using the protected implementation.

Expected:

``` text
approximately one source lookup for the hot key
```

### Test C --- TTL jitter

Create a population of jittered keys.

Expected:

``` text
expiration times distributed across a range
```

### Test D --- Lock recovery

Allow a test lock owner to disappear.

Expected:

``` text
lock automatically expires
```

### Test E --- Stale serving

Pass the soft TTL while remaining within the hard TTL.

Expected:

``` text
stale value can be served
refresh is coordinated
```

### Test F --- Source slowdown

Increase source latency.

Expected:

``` text
duplicate source work remains controlled
```

### Test G --- Source failure

Inject a source exception.

Expected:

``` text
failure follows the defined bounded fallback policy
no uncontrolled retry storm
```

## 46. Cleanup

``` bash
redis-cli DEL lab:chapter15:item:1001
redis-cli DEL lab:chapter15:lock:item:1001
redis-cli DEL lab:chapter15:stale:item:1001
redis-cli DEL lab:chapter15:stale:lock:item:1001
redis-cli DEL lab:chapter15:testlock
```

Remove jitter keys:

``` bash
redis-cli DEL \
  lab:jitter:1 \
  lab:jitter:2 \
  lab:jitter:3 \
  lab:jitter:4 \
  lab:jitter:5 \
  lab:jitter:6 \
  lab:jitter:7 \
  lab:jitter:8 \
  lab:jitter:9 \
  lab:jitter:10
```

------------------------------------------------------------------------

# Key Takeaways

## 47. Production Lessons

1.  Do not synchronize large populations of TTLs.
2.  Use TTL jitter to spread expiration.
3.  Coordinate regeneration for hot keys.
4.  Use unique lock tokens and ownership-safe release.
5.  Give regeneration locks a bounded TTL.
6.  Double-check the cache after obtaining a lock.
7.  Use stale-while-revalidate only where bounded staleness is
    acceptable.
8.  Consider short negative caching for repeated not-found requests.
9.  Use exponential backoff with jitter.
10. Bound total source concurrency, not only per-key concurrency.
11. Do not turn Redis failure into unlimited database fallback.
12. Observe cache and downstream source behavior together.
13. Load-test cold-cache and expiration scenarios before production.

A successful caching architecture is not measured only by Redis latency.
It is measured by whether the complete system remains stable when the
cache is cold, keys expire, Redis is impaired, or the source becomes
slow.

------------------------------------------------------------------------

# Chapter Completion Checklist

## 48. Completion Status

-   [x] Cache stampede explained
-   [x] Thundering herd explained
-   [x] Source amplification explained
-   [x] Synchronized expiration covered
-   [x] Hot-key expiration covered
-   [x] TTL jitter implemented
-   [x] Request coalescing implemented
-   [x] Redis locking implemented
-   [x] Safe lock release implemented
-   [x] Lock TTL behavior tested
-   [x] Double-check pattern covered
-   [x] Stale-while-revalidate implemented
-   [x] Soft/hard TTL covered
-   [x] Negative caching covered
-   [x] Retry backoff/jitter covered
-   [x] Source concurrency protection covered
-   [x] Redis-failure fallback risk covered
-   [x] Observability included
-   [x] Troubleshooting runbook included
-   [x] Failure injection included
-   [x] Full hands-on lab included
-   [x] Acceptance validation included
-   [x] Cleanup included

**Chapter 15 status: COMPLETE**
