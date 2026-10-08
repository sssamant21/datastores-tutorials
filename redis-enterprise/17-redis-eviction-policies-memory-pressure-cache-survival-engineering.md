# Chapter 17 --- Redis Eviction Policies, Memory Pressure & Cache Survival Engineering

**Status:** Canonical\
**Track:** Redis Enterprise / Redis Software Production Engineering\
**Part:** Part 2 --- Caching & Application Engineering\
**Level:** Intermediate → Production Cache Reliability Engineering\
**Audience:** Developers, SREs, DBREs, Platform Engineers, Redis
Administrators\
**Lab type:** Memory-limit analysis, eviction-policy comparison,
LRU/LFU/TTL behavior, hot/cold survival testing, oversized-value
analysis, memory-pressure failure injection, observability,
troubleshooting, runbooks, and production acceptance

------------------------------------------------------------------------

# 1. Objective

A Redis cache is useful only while the right data survives in memory.

When memory approaches the configured limit, Redis must either evict
eligible data or reject memory-growing writes depending on policy and
workload.

By the end, you should be able to:

-   Explain Redis memory pressure and `maxmemory`.
-   Compare `noeviction`, `allkeys-*`, and `volatile-*`.
-   Explain LRU, LFU, random, and TTL-oriented eviction.
-   Distinguish expiration from eviction.
-   Identify cache churn, thrashing, and eviction storms.
-   Analyze oversized values and memory headroom.
-   Correlate evictions with misses and source load.
-   Test memory pressure safely.
-   Troubleshoot write failures and falling hit ratios.
-   Build production runbooks and acceptance criteria.

------------------------------------------------------------------------

# 2. Core Production Principle

Memory pressure is not only a Redis problem:

``` text
Redis memory pressure
 -> evictions
 -> cache misses
 -> source traffic
 -> source latency
 -> slower regeneration
 -> more concurrent misses
```

Memory policy must be engineered together with cache semantics, TTL
strategy, source capacity, warming, and stampede protection.

------------------------------------------------------------------------

# Part 1 --- Memory Boundary

## 3. `maxmemory`

Inspect:

``` redis
CONFIG GET maxmemory
CONFIG GET maxmemory-policy
INFO memory
```

In Redis Enterprise, use the supported database configuration and
administration controls for the deployed version. Do not change
production memory settings merely to perform this lab.

------------------------------------------------------------------------

## 4. Operational Headroom

Do not plan steady-state operation exactly at the memory boundary.

Headroom absorbs:

``` text
traffic growth
larger values
warming
temporary duplication
recovery activity
application changes
allocator/process overhead
```

The correct amount is workload-specific.

------------------------------------------------------------------------

# Part 2 --- Expiration vs. Eviction

## 5. Expiration

Expiration is TTL-driven:

``` redis
SET tutorial:chapter17:ttl:key value EX 60
```

------------------------------------------------------------------------

## 6. Eviction

Eviction is memory-pressure/policy driven.

An eligible cache key can disappear before its TTL expires.

TTL therefore does not guarantee residency until expiration.

------------------------------------------------------------------------

# Part 3 --- Policy Families

## 7. Common Policies

``` text
noeviction
allkeys-lru
allkeys-lfu
allkeys-random
volatile-lru
volatile-lfu
volatile-random
volatile-ttl
```

Validate exact behavior against the deployed Redis version.

------------------------------------------------------------------------

# Part 4 --- `noeviction`

## 8. Behavior

`noeviction` does not remove existing keys simply to make room for a
memory-growing operation.

When allocation cannot proceed within the configured memory policy,
memory-growing commands can fail.

------------------------------------------------------------------------

## 9. Production Consequence

The failure mode becomes:

``` text
cache population/write fails
```

instead of:

``` text
eligible cached data is evicted
```

The application must handle this explicitly.

------------------------------------------------------------------------

# Part 5 --- `allkeys-*`

## 10. Candidate Population

`allkeys-*` policies can consider keys broadly for eviction.

For a database used purely as a disposable cache, this can align with
the fact that all cached objects are replaceable.

------------------------------------------------------------------------

# Part 6 --- `volatile-*`

## 11. Candidate Population

`volatile-*` policies select candidates from keys with expiration
configured.

If many keys lack TTLs, the candidate population differs substantially
from `allkeys-*`.

------------------------------------------------------------------------

## 12. TTL Coverage Risk

Example:

``` text
80% keys without TTL
20% keys with TTL
policy = volatile-lru
```

Do not select a volatile policy without measuring TTL coverage.

------------------------------------------------------------------------

# Part 7 --- LRU

## 13. Concept

LRU approximately favors recently used objects:

``` text
recent/hot -> stronger survival
old/cold   -> weaker survival
```

Redis uses an approximation rather than maintaining a perfect global
ordering.

------------------------------------------------------------------------

# Part 8 --- LFU

## 14. Concept

LFU uses access frequency as a usefulness signal.

``` text
frequently used -> stronger survival
rarely used     -> weaker survival
```

------------------------------------------------------------------------

## 15. LRU vs. LFU

LRU asks approximately:

``` text
How recently was this used?
```

LFU asks approximately:

``` text
How frequently has this been used?
```

Choose based on workload behavior, not preference.

------------------------------------------------------------------------

# Part 9 --- Random and TTL-Oriented Policies

## 16. Random

Random eviction does not intentionally preserve hot data.

It may fit some workloads, but usefulness is not part of candidate
ranking.

------------------------------------------------------------------------

## 17. `volatile-ttl`

TTL-oriented eviction uses remaining expiration information among
eligible keys.

Do not confuse TTL proximity with application popularity.

------------------------------------------------------------------------

# Part 10 --- Policy Selection

## 18. Questions

``` text
Is the database purely cache?
Are all keys disposable?
Do all cache keys have TTL?
Does recency predict reuse?
Does frequency predict reuse?
Can cache writes fail safely?
How expensive is source regeneration?
What happens if a hot key disappears?
```

------------------------------------------------------------------------

# Part 11 --- Mixed Workloads

## 19. Avoid Conflicting Semantics

Avoid casually mixing disposable cache entries with state that must
never be evicted in the same memory-policy domain.

Where practical, separate workloads with different durability and
eviction requirements.

------------------------------------------------------------------------

# Part 12 --- Oversized Values

## 20. Why They Matter

Large values can disproportionately affect:

``` text
memory
network transfer
serialization
regeneration cost
latency
eviction pressure
```

------------------------------------------------------------------------

## 21. Inspect a Known Key

``` redis
MEMORY USAGE tutorial:chapter17:sample
```

Do not perform broad expensive keyspace analysis in production without
planning.

------------------------------------------------------------------------

# Part 13 --- Cache Churn

## 22. Definition

``` text
load object
evict object
request object again
reload object
evict another useful object
repeat
```

Symptoms include high evictions, high misses, high cache writes, and
poor hit ratio.

------------------------------------------------------------------------

# Part 14 --- Thrashing

## 23. Working Set Exceeds Capacity

When the active working set is larger than effective cache capacity,
useful objects can continuously displace one another.

Potential responses include:

``` text
increase appropriate capacity
reduce value size
cache fewer low-value objects
improve TTL strategy
review eviction policy
split workloads
```

------------------------------------------------------------------------

# Part 15 --- Eviction Storm

## 24. Feedback Loop

``` text
memory pressure
 -> evictions
 -> misses
 -> source loads
 -> cache writes
 -> more pressure
```

This is an application/source incident as well as a Redis incident.

------------------------------------------------------------------------

# Part 16 --- Source Protection

## 25. Hot-Key Eviction

A hot key disappearing through eviction can create the same regeneration
stampede described in Chapter 15.

Use where appropriate:

``` text
single-flight
source concurrency limits
rate limiting
backoff/jitter
circuit breaking
bounded stale behavior
```

------------------------------------------------------------------------

# Part 17 --- Warming Under Pressure

## 26. Avoid Blind Warming

Chapter 16 warming can worsen a cache already experiencing eviction
pressure.

Monitor:

``` text
memory
evictions/sec
hit ratio
source load
Redis latency
```

Pause warming if it merely creates churn.

------------------------------------------------------------------------

# Part 18 --- Observability

## 27. `INFO memory`

``` redis
INFO memory
```

Useful fields may include:

``` text
used_memory
used_memory_human
used_memory_rss
used_memory_peak
maxmemory
maxmemory_policy
mem_fragmentation_ratio
```

Interpret them against the deployed version and allocator.

------------------------------------------------------------------------

## 28. `INFO stats`

``` redis
INFO stats
```

Important signals:

``` text
evicted_keys
expired_keys
keyspace_hits
keyspace_misses
```

Use rates over time, not only lifetime counters.

------------------------------------------------------------------------

## 29. Hit Ratio

Conceptually:

``` text
hit ratio = hits / (hits + misses)
```

Application-level cache metrics are also important because Redis
counters may represent multiple behaviors.

------------------------------------------------------------------------

# Part 19 --- Eviction Rate

## 30. Convert Counters to Rates

A lifetime `evicted_keys` value does not tell you whether pressure is
active now.

Measure:

``` text
delta(evicted_keys) / time
```

Correlate with misses, source QPS, memory, and latency.

------------------------------------------------------------------------

# Part 20 --- Fragmentation and RSS

## 31. Different Concepts

Logical Redis allocation and process RSS are not identical.

Review:

``` text
used memory
RSS
allocator metrics
fragmentation
recent peak
recent deletes/evictions
platform memory limit
```

Do not diagnose fragmentation from one ratio alone.

------------------------------------------------------------------------

# Part 21 --- Platform Memory

## 32. Redis Is Not the Only Boundary

Consider:

``` text
database memory limit
process overhead
container limit
host memory
OS requirements
replication/persistence overhead
agents
```

Platform OOM behavior is different from normal Redis eviction.

------------------------------------------------------------------------

# Part 22 --- Hands-On Lab

## 33. Safety

Perform pressure experiments only on an isolated disposable Redis
instance or dedicated training database.

Do not change `maxmemory` or eviction policy on a shared production
database for this lab.

------------------------------------------------------------------------

## 34. Prerequisites

``` bash
python -m pip install redis
```

Windows CMD:

``` cmd
set REDIS_HOST=localhost
set REDIS_PORT=6379
set REDIS_PASSWORD=
```

PowerShell:

``` powershell
$env:REDIS_HOST="localhost"
$env:REDIS_PORT="6379"
$env:REDIS_PASSWORD=""
```

Linux/macOS:

``` bash
export REDIS_HOST=localhost
export REDIS_PORT=6379
export REDIS_PASSWORD=''
```

------------------------------------------------------------------------

# Part 23 --- Baseline

## 35. Inspect

``` redis
CONFIG GET maxmemory
CONFIG GET maxmemory-policy
INFO memory
INFO stats
```

If `CONFIG` is restricted, use the approved Redis Enterprise
administration interface.

------------------------------------------------------------------------

# Part 24 --- Create Hot and Cold Data

## 36. `chapter17_memory_lab.py`

``` python
import os
import random
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

PREFIX = "tutorial:chapter17:"
HOT = PREFIX + "hot:"
COLD = PREFIX + "cold:"
LARGE = PREFIX + "large:"


def populate():
    payload = "x" * 4096

    for i in range(1, 101):
        r.set(
            f"{HOT}{i}",
            payload,
            ex=600 + random.randint(0, 120),
        )

    for i in range(1, 1001):
        r.set(
            f"{COLD}{i}",
            payload,
            ex=600 + random.randint(0, 120),
        )


def make_hot():
    for _ in range(100):
        for i in range(1, 101):
            r.get(f"{HOT}{i}")


def create_large_values():
    payload = "L" * (1024 * 1024)

    for i in range(1, 6):
        r.set(f"{LARGE}{i}", payload, ex=600)


def report():
    mem = r.info("memory")
    stats = r.info("stats")

    print("used_memory_human:", mem.get("used_memory_human"))
    print("maxmemory        :", mem.get("maxmemory"))
    print("policy           :", mem.get("maxmemory_policy"))
    print("evicted_keys     :", stats.get("evicted_keys"))
    print("expired_keys     :", stats.get("expired_keys"))
    print("keyspace_hits    :", stats.get("keyspace_hits"))
    print("keyspace_misses  :", stats.get("keyspace_misses"))


if __name__ == "__main__":
    print("PING:", r.ping())
    populate()
    make_hot()
    report()

    sample = f"{HOT}1"
    print("Sample memory:", r.memory_usage(sample))
    print("Sample TTL   :", r.ttl(sample))
```

------------------------------------------------------------------------

## 37. Run

``` bash
python chapter17_memory_lab.py
```

Expected pattern:

``` text
PING: True
used_memory_human: ...
maxmemory        : ...
policy           : ...
evicted_keys     : ...
expired_keys     : ...
keyspace_hits    : ...
keyspace_misses  : ...
Sample memory: ...
Sample TTL   : ...
```

------------------------------------------------------------------------

# Part 25 --- Inspect Namespace

## 38. Use `SCAN`

``` bash
redis-cli --scan --pattern 'tutorial:chapter17:*'
```

Avoid `KEYS *` on large production keyspaces.

------------------------------------------------------------------------

# Part 26 --- Oversized Value Lab

## 39. Create Large Samples

Call `create_large_values()` in the isolated lab and compare:

``` redis
MEMORY USAGE tutorial:chapter17:large:1
MEMORY USAGE tutorial:chapter17:hot:1
```

This demonstrates why key count alone is not a memory-capacity metric.

------------------------------------------------------------------------

# Part 27 --- Pressure-Test Instance

## 40. Dedicated Configuration

Conceptual disposable configuration:

``` text
maxmemory 64mb
maxmemory-policy allkeys-lru
```

Do not apply these values to an existing environment.

------------------------------------------------------------------------

# Part 28 --- Pressure Generator

## 41. `chapter17_pressure.py`

``` python
import os
import redis

HOST = os.getenv("REDIS_HOST", "localhost")
PORT = int(os.getenv("REDIS_PORT", "6379"))
PASSWORD = os.getenv("REDIS_PASSWORD") or None

r = redis.Redis(
    host=HOST,
    port=PORT,
    password=PASSWORD,
    decode_responses=False,
)

PREFIX = b"tutorial:chapter17:pressure:"
VALUE = b"x" * (64 * 1024)

for i in range(100000):
    key = PREFIX + str(i).encode()

    try:
        r.set(key, VALUE, ex=900)
    except redis.RedisError as exc:
        print("Write failed at", i, repr(exc))
        break

    if i % 100 == 0:
        stats = r.info("stats")
        mem = r.info("memory")

        print(
            i,
            mem.get("used_memory_human"),
            stats.get("evicted_keys"),
        )
```

Run only against the isolated pressure-test instance.

------------------------------------------------------------------------

# Part 29 --- `noeviction` Experiment

## 42. Expected Behavior

On a disposable `noeviction` instance, continue memory-growing writes.

Capture:

``` text
client error
used memory
evicted_keys
write failure point
```

The application must handle the error without an uncontrolled retry
storm.

------------------------------------------------------------------------

# Part 30 --- Eviction Experiment

## 43. Expected Behavior

With an eviction policy:

``` text
memory approaches boundary
evicted_keys increases
writes may continue
```

Now ask:

``` text
which keys disappeared?
did hot keys survive better?
did hit ratio decline?
did source traffic increase?
```

------------------------------------------------------------------------

# Part 31 --- Hot/Cold Survival

## 44. Experiment

Generate repeated access to 100 hot keys and little/no access to 1000
cold keys before applying pressure.

For recency/frequency-aware policies, evaluate survival statistically.

Do not expect deterministic survival for every individual key.

------------------------------------------------------------------------

# Part 32 --- LFU Experiment

## 45. Frequency Difference

On an isolated LFU-policy instance:

``` text
access population A repeatedly
access population B rarely
apply pressure
measure survival
```

Use a population, not a single pair of keys, to evaluate behavior.

------------------------------------------------------------------------

# Part 33 --- Volatile Policy Experiment

## 46. TTL Coverage

Create:

``` text
population A = TTL keys
population B = non-TTL keys
```

On an isolated volatile-policy instance, observe the impact of the
eligible candidate set.

------------------------------------------------------------------------

# Part 34 --- Failure Injection

## 47. Failure 1 --- Memory Boundary

Drive the disposable cache to its configured memory boundary.

Expected behavior depends on policy:

``` text
eviction
or
memory-growing write rejection
```

------------------------------------------------------------------------

## 48. Failure 2 --- Eviction Storm

Use a working set larger than effective capacity while repeatedly
requesting displaced objects.

Observe:

``` text
evictions/sec
misses/sec
cache writes/sec
source simulation QPS
```

------------------------------------------------------------------------

## 49. Failure 3 --- Oversized Values

Insert several large values and measure:

``` text
memory delta
eviction rate
latency
```

------------------------------------------------------------------------

## 50. Failure 4 --- Hot-Key Eviction

Allow a hot object to disappear under lab pressure and issue concurrent
requests.

Apply Chapter 15 single-flight protection to prevent duplicate source
regeneration.

------------------------------------------------------------------------

## 51. Failure 5 --- Warming During Pressure

Run Chapter 16-style warming while the cache is already evicting.

Determine whether warming improves hit ratio or merely increases churn.

------------------------------------------------------------------------

## 52. Failure 6 --- Volatile Policy With Poor TTL Coverage

Create many non-TTL keys and a smaller TTL population.

Observe why the candidate set matters.

------------------------------------------------------------------------

## 53. Failure 7 --- Slow Source During Eviction

Increase simulated source latency while misses rise.

Expected:

``` text
longer regeneration window
higher miss concurrency
greater stampede risk
```

------------------------------------------------------------------------

## 54. Failure 8 --- Retry Amplification

Simulate immediate retries after failed cache population or repeated
misses.

Compare with bounded retries, exponential backoff, and jitter.

------------------------------------------------------------------------

## 55. Failure 9 --- Headroom Exhaustion

Run near the normal memory boundary, then add a burst.

This demonstrates why steady-state operation at the edge is fragile.

------------------------------------------------------------------------

## 56. Failure 10 --- Recovery

Reduce pressure.

Observe:

``` text
eviction rate
hit ratio
source QPS
repopulation rate
```

Avoid turning recovery into a warming storm.

------------------------------------------------------------------------

# Part 35 --- Troubleshooting

## 57. Evictions Suddenly Increased

Check:

``` text
memory utilization
configured limit
policy
key count
value sizes
traffic growth
deployment changes
TTL changes
warming jobs
```

------------------------------------------------------------------------

## 58. Hit Ratio Falling

Correlate:

``` text
evictions
expirations
misses
working-set growth
namespace changes
policy
hot-key survival
```

------------------------------------------------------------------------

## 59. Cache Writes Failing

Check:

``` text
exact Redis/client error
policy
memory limit
used memory
value size
platform memory
Redis health
```

------------------------------------------------------------------------

## 60. Evictions High but Memory Flat

This can be expected:

``` text
new data enters
old data leaves
memory remains near boundary
```

The important question is whether the retained cache remains useful.

------------------------------------------------------------------------

## 61. Source Load High

Check:

``` text
evictions/sec
misses/sec
single-flight
retry policy
source concurrency
warming
hot-key churn
```

------------------------------------------------------------------------

## 62. RSS Appears High

Investigate logical memory, RSS, allocator metrics, recent peak,
delete/eviction history, persistence activity where applicable, and
container/host memory.

Do not equate RSS with dataset size.

------------------------------------------------------------------------

# Part 36 --- Production Runbooks

## 63. Runbook --- High Eviction Rate

``` text
1. Confirm evictions/sec.
2. Confirm memory and configured limit.
3. Confirm active policy.
4. Measure hit/miss ratio.
5. Measure source QPS/latency.
6. Identify recent workload/config changes.
7. Inspect value-size distribution safely.
8. Check warming/bulk population.
9. Protect source from miss amplification.
10. Reduce low-value cache population if needed.
11. Evaluate capacity/policy/TTL changes.
12. Validate hit ratio after remediation.
```

------------------------------------------------------------------------

## 64. Runbook --- Cache Write Rejection

``` text
1. Capture exact error.
2. Check memory configuration.
3. Check policy.
4. Check current memory.
5. Check oversized writes.
6. Confirm application fallback.
7. Prevent retry storm.
8. Reduce nonessential cache writes.
9. Restore safe headroom.
10. Validate population succeeds.
```

------------------------------------------------------------------------

## 65. Runbook --- Eviction Storm

``` text
1. Measure evictions/sec.
2. Measure misses/sec.
3. Measure source QPS.
4. Measure source latency/errors.
5. Stop unnecessary warming.
6. Bound source fallback.
7. Identify working-set/capacity mismatch.
8. Identify oversized/low-value objects.
9. Review policy.
10. Restore stable capacity.
11. Warm critical data gradually.
12. Confirm recovery.
```

------------------------------------------------------------------------

## 66. Runbook --- Memory Pressure After Deployment

``` text
1. Identify deployment time.
2. Compare key count.
3. Compare value sizes.
4. Check namespace duplication.
5. Check TTL changes.
6. Check population rate.
7. Check eviction rate.
8. Pause unnecessary warming.
9. Roll back unsafe cache behavior if required.
10. Validate memory/source recovery.
```

------------------------------------------------------------------------

## 67. Runbook --- Oversized Values

``` text
1. Identify suspected key pattern.
2. Sample memory safely.
3. Identify application owner.
4. Review serialization/compression.
5. Determine whether full object must be cached.
6. Evaluate decomposition only when semantics permit.
7. Repair through approved application-safe process.
8. Monitor memory and latency.
9. Add value-size guardrails.
```

------------------------------------------------------------------------

# Part 37 --- Capacity Review Template

## 68. Fields

``` text
Service:
Redis database:
Purpose:
Configured memory:
Policy:
Used memory:
Peak memory:
Operational headroom:
Key count:
Average value size:
P95 value size:
Largest expected value:
TTL coverage:
Working-set estimate:
Warm hit ratio:
Peak QPS:
Normal source QPS:
Source sustainable QPS:
Normal evictions/sec:
Eviction alert:
Normal misses/sec:
Hit-ratio target:
Growth rate:
Warming behavior:
Stampede protection:
Owner:
```

------------------------------------------------------------------------

# Part 38 --- Policy Decision Template

## 69. Decision Record

``` text
Database:
Pure cache?:
All keys disposable?:
All keys have TTL?:
Recency predicts reuse?:
Frequency predicts reuse?:
Write rejection acceptable?:
Hot-key regeneration cost:
Source fallback capacity:
Selected policy:
Reason:
Alternatives rejected:
Test performed:
Rollback plan:
Owner:
```

------------------------------------------------------------------------

# Production Acceptance Checklist

## 70. Memory Engineering

-   [ ] Memory limit documented.
-   [ ] Eviction policy documented.
-   [ ] Policy rationale documented.
-   [ ] TTL coverage measured.
-   [ ] Working-set size estimated.
-   [ ] Memory headroom defined.
-   [ ] Value-size distribution measured.
-   [ ] Oversized-value guardrails reviewed.
-   [ ] Evictions/sec monitored.
-   [ ] Expirations/sec monitored.
-   [ ] Hit/miss ratio monitored.
-   [ ] Source QPS correlated with misses.
-   [ ] Source protection exists.
-   [ ] Warming under pressure tested.
-   [ ] Cold-cache recovery tested.
-   [ ] Write-rejection behavior tested where relevant.
-   [ ] Platform memory boundary understood.
-   [ ] Recovery runbook validated.

------------------------------------------------------------------------

## 71. Policy Validation

-   [ ] Policy tested in isolation.
-   [ ] Hot/cold workload represented.
-   [ ] Value-size distribution represented.
-   [ ] TTL/non-TTL populations represented.
-   [ ] Memory pressure tested.
-   [ ] Hit-ratio effect measured.
-   [ ] Source-load effect measured.
-   [ ] Application error handling validated.
-   [ ] Rollback procedure documented.

------------------------------------------------------------------------

# Knowledge Validation

## 72. Questions

You should be able to answer:

1.  What is the difference between expiration and eviction?
2.  What role does `maxmemory` play?
3.  What does `noeviction` change operationally?
4.  How do `allkeys-*` and `volatile-*` differ?
5.  Why does TTL coverage matter?
6.  What does LRU attempt to preserve?
7.  What does LFU attempt to preserve?
8.  Why are Redis LRU/LFU behaviors approximate?
9.  When might random eviction fit?
10. What signal does `volatile-ttl` use?
11. Why are mixed eviction semantics risky?
12. Why is memory headroom necessary?
13. How can oversized values destabilize a cache?
14. What is cache churn?
15. What is cache thrashing?
16. What is an eviction storm?
17. How can eviction trigger stampede?
18. Why can warming worsen pressure?
19. Which Redis metrics help investigate?
20. Why view `evicted_keys` as a rate?
21. How is hit ratio calculated?
22. Why distinguish RSS from logical used memory?
23. How can platform OOM differ from eviction?
24. Why isolate pressure testing?
25. What happens to memory-growing writes under `noeviction`?
26. Why can memory stay flat while evictions rise?
27. Why monitor source QPS?
28. What should be checked after deployment memory growth?
29. What belongs in a policy decision record?
30. What must pass before production readiness?

------------------------------------------------------------------------

# Hands-On Acceptance Checklist

## 73. Lab Completion

-   [ ] Inspected memory configuration.
-   [ ] Inspected policy.
-   [ ] Inspected `INFO memory`.
-   [ ] Inspected `INFO stats`.
-   [ ] Created hot/cold keys.
-   [ ] Generated hot-key access.
-   [ ] Measured `MEMORY USAGE`.
-   [ ] Verified TTL distribution.
-   [ ] Created oversized samples.
-   [ ] Used dedicated pressure-test instance.
-   [ ] Recorded baseline counters.
-   [ ] Generated controlled pressure.
-   [ ] Observed `noeviction` behavior.
-   [ ] Observed eviction behavior.
-   [ ] Compared hot/cold survival.
-   [ ] Reviewed LFU.
-   [ ] Reviewed volatile TTL dependency.
-   [ ] Completed ten failure scenarios.
-   [ ] Completed troubleshooting.
-   [ ] Reviewed runbooks.
-   [ ] Completed capacity review.
-   [ ] Completed policy decision record.
-   [ ] Completed production acceptance.

------------------------------------------------------------------------

# 74. Lab Cleanup

Discover:

``` bash
redis-cli --scan --pattern 'tutorial:chapter17:*'
```

Delete only confirmed chapter keys in bounded batches with `UNLINK`.

Do not use:

``` redis
FLUSHDB
FLUSHALL
```

against a shared or production database.

If a disposable Redis instance was created solely for pressure testing,
decommission it using the normal environment process rather than reusing
unsafe lab settings.

------------------------------------------------------------------------

# 75. Key Takeaways

1.  Redis memory policy determines behavior under memory constraint.
2.  Expiration and eviction are different mechanisms.
3.  `noeviction` can turn memory pressure into write failures.
4.  `allkeys-*` and `volatile-*` have different candidate populations.
5.  Volatile policies require known TTL coverage.
6.  LRU uses recency; LFU uses frequency.
7.  Eviction behavior should be evaluated statistically.
8.  Operational memory headroom matters.
9.  Oversized values can create disproportionate impact.
10. Working-set/capacity mismatch causes churn and thrashing.
11. Eviction storms amplify misses and source load.
12. Hot-key eviction needs stampede protection.
13. Warming during pressure can worsen churn.
14. Eviction counters should be analyzed as rates.
15. Hit ratio matters more than memory utilization alone.
16. Logical memory and RSS are different.
17. Platform OOM is not normal Redis eviction.
18. Policy changes require isolated representative testing.
19. Source capacity must be protected during pressure.
20. Production readiness requires policy, capacity, observability,
    failure testing, and runbooks.

------------------------------------------------------------------------

# 76. References

Validate exact behavior against the Redis and Redis Enterprise versions
deployed.

Recommended official documentation areas:

-   Redis key eviction
-   `maxmemory`
-   `maxmemory-policy`
-   `INFO memory`
-   `INFO stats`
-   `MEMORY USAGE`
-   `TTL`
-   `EXPIRE`
-   `SCAN`
-   `UNLINK`
-   LRU and LFU eviction
-   Redis memory optimization
-   Redis Enterprise database memory configuration and monitoring

Eviction-policy selection depends on cache semantics, TTL coverage,
value-size distribution, working-set size, source capacity, and
application failure behavior.

------------------------------------------------------------------------

# Next Chapter

**Chapter 18 --- Redis Hot Keys, Big Keys & Workload Skew Engineering**

Chapter 18 will go deeply into:

-   hot-key mechanics
-   workload skew
-   hot-key detection
-   big-key detection
-   value-size analysis
-   command-cost implications
-   network amplification
-   shard concentration
-   source regeneration cost
-   key redesign
-   splitting/aggregation tradeoffs
-   observability
-   failure injection
-   troubleshooting
-   production runbooks
-   acceptance validation
