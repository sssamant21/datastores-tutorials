# Chapter 19 --- Redis TTL Strategy, Expiration Engineering & Data Freshness

**Status:** Canonical\
**Track:** Redis Enterprise / Redis Software Production Engineering\
**Part:** Part 2 --- Caching & Application Engineering\
**Level:** Intermediate → Production Cache Reliability Engineering\
**Audience:** Developers, SREs, DBREs, Platform Engineers, Redis
Administrators\
**Lab type:** TTL design, expiration behavior, freshness contracts, TTL
jitter, synchronized-expiration reproduction, sliding vs. absolute
expiration, soft/hard TTL, refresh-ahead, stale-data analysis, failure
injection, observability, troubleshooting, runbooks, and production
acceptance

------------------------------------------------------------------------

# 1. Objective

TTL is not merely a Redis configuration value.

TTL is an application freshness contract.

A cache designer must answer:

``` text
How stale may this data become?
How frequently may the source be queried?
What happens when the key expires?
Can stale data be served?
Can expiration be extended by access?
Should expiration occur at a business deadline?
What happens when thousands of keys expire together?
```

By the end, you should be able to:

-   Explain TTL and expiration semantics.
-   Distinguish TTL from eviction.
-   Define freshness by data class.
-   Choose absolute, relative, sliding, soft, and hard expiration
    strategies.
-   Apply TTL jitter.
-   Prevent synchronized expiration.
-   Understand hot-key expiration risk.
-   Integrate refresh-ahead.
-   Use stale-while-revalidate safely.
-   Design negative-cache TTLs.
-   Model source load caused by expiration.
-   Observe expiration behavior.
-   Test expiration storms.
-   Troubleshoot stale-data and miss-spike incidents.
-   Build production runbooks and acceptance criteria.

------------------------------------------------------------------------

# 2. Core Production Principle

TTL controls two competing costs:

``` text
long TTL
 -> fewer source reads
 -> greater staleness risk
```

and:

``` text
short TTL
 -> fresher data
 -> more source reads
 -> more regeneration
 -> greater stampede risk
```

There is no universally correct TTL.

The correct value depends on:

``` text
business freshness requirement
source cost
request rate
update frequency
invalidation capability
failure behavior
hotness
```

------------------------------------------------------------------------

# Part 1 --- TTL Fundamentals

## 3. Relative Expiration

Example:

``` redis
SET tutorial:chapter19:item:1001 value EX 300
```

The key has a relative lifetime of approximately five minutes.

Inspect:

``` redis
TTL tutorial:chapter19:item:1001
```

------------------------------------------------------------------------

## 4. Millisecond TTL

Where finer resolution is needed:

``` redis
PTTL tutorial:chapter19:item:1001
```

Use the precision actually required by the application.

------------------------------------------------------------------------

# Part 2 --- TTL Return Values

## 5. Interpret Carefully

For `TTL`, Redis uses special negative return values to distinguish
cases such as:

``` text
key does not exist
key exists but has no expiration
```

Validate exact command semantics against the deployed Redis version.

Do not treat every negative TTL as the same condition.

------------------------------------------------------------------------

# Part 3 --- Expiration vs. Eviction

## 6. Expiration

Expiration is driven by time.

``` text
TTL reaches expiration
 -> key becomes unavailable
```

------------------------------------------------------------------------

## 7. Eviction

Eviction is driven by memory policy and memory pressure.

A key may be evicted before its TTL.

Chapter 17 covers eviction engineering in depth.

------------------------------------------------------------------------

# Part 4 --- Freshness Contract

## 8. Start With Business Semantics

Before choosing:

``` text
TTL = 300
```

define:

``` text
maximum acceptable staleness
source update frequency
criticality
invalidation mechanism
failure fallback
```

TTL should be derived from the contract, not copied from another
service.

------------------------------------------------------------------------

# Part 5 --- Data Classes

## 9. Example Classification

``` text
Class A -> seconds-level freshness
Class B -> minutes-level freshness
Class C -> hours-level freshness
Class D -> effectively immutable/reference data
```

Different classes should not automatically share one TTL.

------------------------------------------------------------------------

# Part 6 --- Short TTL

## 10. Benefits

``` text
fresher cache
faster natural correction after source changes
less stale-data exposure
```

------------------------------------------------------------------------

## 11. Costs

``` text
higher miss rate
more source QPS
more cache writes
more regeneration
more expiration-storm risk
```

Short TTL is not free.

------------------------------------------------------------------------

# Part 7 --- Long TTL

## 12. Benefits

``` text
higher hit ratio
lower source QPS
fewer regenerations
better tolerance of brief source slowness
```

------------------------------------------------------------------------

## 13. Risks

``` text
stale data
slow natural correction
greater dependence on invalidation
obsolete objects consuming memory
```

------------------------------------------------------------------------

# Part 8 --- Absolute Expiration

## 14. Business Deadline

Some data should expire at a known time rather than after a fixed
duration.

Examples:

``` text
promotion end
daily snapshot boundary
token/session deadline
market/business cutoff
temporary entitlement
```

Use the Redis expiration mechanism appropriate to the required timestamp
semantics.

------------------------------------------------------------------------

# Part 9 --- Relative Expiration

## 15. Lifetime From Write

Relative expiration is appropriate when the freshness window begins when
the cache entry is populated.

Example:

``` text
cache object for 10 minutes after load
```

------------------------------------------------------------------------

# Part 10 --- Sliding Expiration

## 16. Concept

Sliding expiration extends lifetime when qualifying access occurs.

Conceptually:

``` text
read key
 -> refresh TTL
```

This can keep actively used data resident.

------------------------------------------------------------------------

## 17. Risk

A frequently accessed key may never naturally expire.

If source changes are not invalidated correctly, sliding expiration can
create indefinite staleness.

Use only when the freshness model supports it.

------------------------------------------------------------------------

# Part 11 --- Fixed Expiration

## 18. Contrast

Fixed:

``` text
write at 10:00
expire at 10:10
reads do not change deadline
```

Sliding:

``` text
read at 10:08
extend deadline
```

The distinction must be explicit in application design.

------------------------------------------------------------------------

# Part 12 --- Hard TTL

## 19. Definition

Hard TTL is the point beyond which the cached value must no longer be
served.

``` text
fresh
 -> stale-allowed region
 -> hard expiration
 -> unavailable
```

Not every application permits a stale-allowed region.

------------------------------------------------------------------------

# Part 13 --- Soft TTL

## 20. Definition

Soft TTL marks when data should be refreshed but may still be served
temporarily.

Example:

``` text
soft TTL = 5 min
hard TTL = 10 min
```

After five minutes:

``` text
serve existing value if allowed
+
trigger controlled refresh
```

After ten minutes:

``` text
do not serve old value
```

------------------------------------------------------------------------

# Part 14 --- Stale-While-Revalidate

## 21. Flow

``` text
request
  |
cached value exists
  |
soft TTL exceeded
  |
serve bounded stale value
  |
one worker refreshes
```

This reduces user-visible miss latency and protects the source.

------------------------------------------------------------------------

## 22. Business Safety

Do not serve stale values when correctness requires current data.

Examples may include:

``` text
authorization
security state
financial decisions
safety-critical state
strict inventory/availability
```

The application owner must define acceptable staleness.

------------------------------------------------------------------------

# Part 15 --- Refresh-Ahead

## 23. Before Hard Expiration

Chapter 16 introduced refresh-ahead:

``` text
TTL approaches threshold
 -> controlled refresh
 -> reset lifetime
```

This is especially valuable for predictably hot keys.

------------------------------------------------------------------------

# Part 16 --- TTL Jitter

## 24. Problem

If many keys are written together with:

``` text
TTL = 300 seconds
```

they may expire in the same future window.

------------------------------------------------------------------------

## 25. Formula

``` text
effective_ttl =
base_ttl + random_jitter
```

Example:

``` text
base = 300
jitter = 0..60
```

Result:

``` text
300..360 seconds
```

------------------------------------------------------------------------

## 26. Symmetric Jitter

Another design:

``` text
effective_ttl =
base_ttl + random(-jitter, +jitter)
```

Use only if the lower bound still satisfies freshness and source-load
requirements.

------------------------------------------------------------------------

# Part 17 --- Jitter Sizing

## 27. Too Small

If:

``` text
base TTL = 3600 sec
jitter = 1 sec
```

the distribution may not materially reduce a large synchronized
expiration wave.

------------------------------------------------------------------------

## 28. Too Large

If jitter is too large, some keys may remain cached longer than the
business freshness contract permits.

Jitter is constrained by semantics.

------------------------------------------------------------------------

# Part 18 --- Expiration Storm

## 29. Definition

An expiration storm occurs when many useful keys expire in a short
period.

``` text
many expirations
 -> many misses
 -> source load
 -> cache writes
 -> application latency
```

------------------------------------------------------------------------

# Part 19 --- Common Causes

## 30. Synchronized Population

``` text
deployment warm
batch import
scheduled refresh
cache rebuild
mass invalidation/repopulation
```

can create aligned TTLs.

The incident may happen one TTL later, not during the write event.

------------------------------------------------------------------------

# Part 20 --- Hot-Key Expiration

## 31. One Key Can Be Enough

A single key receiving 20,000 requests/sec can create a severe miss
burst when it expires.

TTL jitter does not solve the concurrency on that one key.

Use:

``` text
single-flight
refresh-ahead
stale-while-revalidate
source protection
```

------------------------------------------------------------------------

# Part 21 --- Negative Cache TTL

## 32. Not Found Is Cacheable Sometimes

For repeated lookups of absent objects, a short negative TTL can protect
the source.

Example:

``` text
object not found
 -> cache NOT_FOUND marker for 15 sec
```

------------------------------------------------------------------------

## 33. Risk

If the object is created immediately afterward, clients may continue
receiving the cached negative result until invalidation or expiration.

Negative TTL should normally be shorter than ordinary positive-cache TTL
unless semantics justify otherwise.

------------------------------------------------------------------------

# Part 22 --- Error Caching

## 34. Do Not Cache Failures Blindly

Distinguish:

``` text
authoritative NOT_FOUND
```

from:

``` text
source timeout
source 500
network error
permission failure
```

Caching transient failures as if they were valid absence can create
incorrect behavior.

------------------------------------------------------------------------

# Part 23 --- TTL and Source Capacity

## 35. Simple Approximation

For a frequently requested object that always gets reused after
expiration:

``` text
regeneration frequency ≈ 1 / TTL
```

Across many objects, shorter TTLs generally increase source regeneration
demand.

Real workloads depend on request popularity and whether objects are
requested after expiration.

------------------------------------------------------------------------

# Part 24 --- TTL and Hit Ratio

## 36. Relationship

Longer TTL often increases hit probability.

But the exact effect depends on:

``` text
request distribution
working set
memory pressure
eviction
object update frequency
traffic patterns
```

Do not assume doubling TTL doubles hit ratio.

------------------------------------------------------------------------

# Part 25 --- TTL and Memory

## 37. Longer Residency

Longer TTL can keep more cold objects resident.

This may:

``` text
increase memory use
increase eviction pressure
reduce space for hotter objects
```

TTL must be evaluated with Chapter 17 memory policy.

------------------------------------------------------------------------

# Part 26 --- TTL and Big Keys

## 38. Large Object Residency

A big key with a very long TTL can consume significant memory for a long
period.

A big key with a very short TTL can cause expensive repeated
regeneration.

Chapter 18 size analysis should influence TTL design.

------------------------------------------------------------------------

# Part 27 --- TTL and Hot Keys

## 39. Hot Data Strategy

For hot keys:

``` text
hard expiration only
```

may be less resilient than:

``` text
refresh-ahead
+
single-flight
+
bounded stale serving
```

when business semantics allow it.

------------------------------------------------------------------------

# Part 28 --- TTL and Deployment

## 40. Namespace Migration

A new cache namespace often starts with many writes close together.

If every key receives the same TTL:

``` text
deployment time + TTL
```

may become the next expiration storm.

Apply TTL distribution during warming.

------------------------------------------------------------------------

# Part 29 --- TTL and DR

## 41. Recovery Population

Disaster-recovery warming can also create synchronized future
expiration.

A recovery procedure must avoid scheduling another load spike.

------------------------------------------------------------------------

# Part 30 --- Observability

## 42. Key Metrics

Track:

``` text
expired_keys
cache hits
cache misses
cache hit ratio
source QPS
source latency
cache writes
refresh attempts
refresh failures
stale responses
negative-cache hits
```

------------------------------------------------------------------------

## 43. Expiration Rate

`expired_keys` is a cumulative counter.

Use:

``` text
delta(expired_keys) / time
```

to identify current expiration activity.

------------------------------------------------------------------------

## 44. Application TTL Metrics

Useful application-level metrics:

``` text
cache_write_ttl_seconds
cache_refresh_total
cache_refresh_error_total
cache_stale_served_total
cache_negative_hit_total
cache_miss_total
```

Consider histograms for TTL values rather than high-cardinality labels.

------------------------------------------------------------------------

# Part 31 --- TTL Distribution

## 45. What to Measure

For a controlled sample:

``` text
minimum TTL
median TTL
p95 TTL
maximum TTL
no-expiration count
missing count
```

Sampling must be designed to avoid production keyspace impact.

------------------------------------------------------------------------

# Part 32 --- No-TTL Keys

## 46. Persistent Cache Entries

A cache key without expiration may remain until:

``` text
explicit deletion
eviction
database cleanup
```

If the design requires freshness, no-TTL cache entries need explicit
invalidation guarantees.

------------------------------------------------------------------------

# Part 33 --- Hands-On Lab

## 47. Objectives

You will:

1.  create TTL keys;
2.  inspect TTL/PTTL;
3.  compare fixed and sliding expiration;
4.  generate synchronized TTLs;
5.  generate jittered TTLs;
6.  measure TTL distribution;
7.  build soft/hard TTL metadata;
8.  implement refresh-ahead;
9.  simulate negative caching;
10. inject expiration storms;
11. troubleshoot;
12. clean up safely.

------------------------------------------------------------------------

## 48. Prerequisites

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

# Part 34 --- Basic TTL Lab

## 49. Create Key

``` redis
SET tutorial:chapter19:basic value EX 60
TTL tutorial:chapter19:basic
PTTL tutorial:chapter19:basic
```

Wait and repeat.

Observe the remaining lifetime decrease.

------------------------------------------------------------------------

# Part 35 --- Persistent-Key Lab

## 50. No Expiration

``` redis
SET tutorial:chapter19:persistent value
TTL tutorial:chapter19:persistent
```

Interpret the return value using Redis command semantics.

Clean this key up at the end.

------------------------------------------------------------------------

# Part 36 --- Fixed vs. Sliding Lab

## 51. Fixed Key

``` redis
SET tutorial:chapter19:fixed value EX 30
```

Read repeatedly:

``` redis
GET tutorial:chapter19:fixed
TTL tutorial:chapter19:fixed
```

`GET` alone does not reset the TTL.

------------------------------------------------------------------------

## 52. Sliding Example

Application-controlled sliding expiration:

``` redis
GET tutorial:chapter19:sliding
EXPIRE tutorial:chapter19:sliding 30
```

This is two commands unless implemented using an appropriate
atomic/application design.

Do not accidentally create sliding semantics when fixed freshness is
required.

------------------------------------------------------------------------

# Part 37 --- TTL Jitter Lab

## 53. Create `chapter19_ttl_lab.py`

``` python
import os
import random
import statistics

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

SYNC_PREFIX = "tutorial:chapter19:sync:"
JITTER_PREFIX = "tutorial:chapter19:jitter:"

BASE_TTL = 120
JITTER = 30
COUNT = 1000


def create_synchronized():
    pipe = r.pipeline(transaction=False)

    for i in range(COUNT):
        pipe.set(
            f"{SYNC_PREFIX}{i}",
            "value",
            ex=BASE_TTL,
        )

        if i % 100 == 99:
            pipe.execute()

    pipe.execute()


def create_jittered():
    pipe = r.pipeline(transaction=False)

    for i in range(COUNT):
        ttl = BASE_TTL + random.randint(0, JITTER)

        pipe.set(
            f"{JITTER_PREFIX}{i}",
            "value",
            ex=ttl,
        )

        if i % 100 == 99:
            pipe.execute()

    pipe.execute()


def sample_ttls(prefix):
    ttls = []

    for i in range(COUNT):
        ttl = r.ttl(f"{prefix}{i}")

        if ttl >= 0:
            ttls.append(ttl)

    return ttls


def report(name, ttls):
    print(name)
    print("count :", len(ttls))
    print("min   :", min(ttls))
    print("median:", statistics.median(ttls))
    print("max   :", max(ttls))
    print()


if __name__ == "__main__":
    print("PING:", r.ping())

    create_synchronized()
    create_jittered()

    report(
        "SYNCHRONIZED",
        sample_ttls(SYNC_PREFIX),
    )

    report(
        "JITTERED",
        sample_ttls(JITTER_PREFIX),
    )
```

------------------------------------------------------------------------

## 54. Run

``` bash
python chapter19_ttl_lab.py
```

Expected:

``` text
SYNCHRONIZED
min   : values close together
max   : values close together

JITTERED
min   : near base TTL
max   : near base TTL + jitter
```

Exact values vary because time passes during creation and sampling.

------------------------------------------------------------------------

# Part 38 --- Visualize Expiration Buckets

## 55. Bucket TTLs

Extend the lab:

``` python
from collections import Counter

def buckets(ttls, bucket_size=5):
    result = Counter()

    for ttl in ttls:
        bucket = (ttl // bucket_size) * bucket_size
        result[bucket] += 1

    return result
```

Compare synchronized vs. jittered populations.

The jittered population should be distributed across more expiration
buckets.

------------------------------------------------------------------------

# Part 39 --- Soft/Hard TTL Lab

## 56. Store Freshness Metadata

One application pattern stores:

``` json
{
  "value": "...",
  "loaded_at": 1234567890,
  "soft_expires_at": 1234568190
}
```

while Redis itself uses a later hard TTL.

This allows the application to distinguish:

``` text
fresh
stale-but-servable
hard expired
```

------------------------------------------------------------------------

## 57. Example

``` python
import json
import time

now = time.time()

payload = {
    "value": "example",
    "loaded_at": now,
    "soft_expires_at": now + 30,
}

r.set(
    "tutorial:chapter19:swr:item:1001",
    json.dumps(payload),
    ex=60,
)
```

After 30 seconds, the application may refresh while still serving the
old value if the business contract allows it.

------------------------------------------------------------------------

# Part 40 --- Refresh-Ahead Lab

## 58. Threshold

For:

``` text
hard TTL = 60 sec
refresh threshold = 15 sec
```

check:

``` redis
TTL tutorial:chapter19:refresh:item:1001
```

When TTL is low, one coordinated worker should refresh.

Reuse Chapter 16's ownership-safe refresh-lock design.

------------------------------------------------------------------------

# Part 41 --- Negative Cache Lab

## 59. Missing Object

Conceptual:

``` redis
SET tutorial:chapter19:negative:item:404 NOT_FOUND EX 10
```

Requests during the next ten seconds can avoid repeated source lookups.

Do not use the same long TTL as normal positive data without reviewing
creation/freshness behavior.

------------------------------------------------------------------------

# Part 42 --- Expiration Storm Lab

## 60. Controlled Test

Use only the isolated `tutorial:chapter19:sync:*` keys.

Generate requests around their expiration time.

Measure:

``` text
misses/sec
source simulation calls/sec
cache writes/sec
latency
```

Repeat using the jittered population.

Compare peak source load.

------------------------------------------------------------------------

# Part 43 --- Failure Injection

## 61. Failure 1 --- TTL Too Short

Reduce a hot object's TTL dramatically.

Observe:

``` text
miss rate
source QPS
cache writes
```

------------------------------------------------------------------------

## 62. Failure 2 --- TTL Too Long

Simulate a source update while the cache remains unchanged.

Measure stale-data duration.

------------------------------------------------------------------------

## 63. Failure 3 --- Synchronized Expiration

Populate many keys with the same TTL.

Observe the miss wave.

------------------------------------------------------------------------

## 64. Failure 4 --- Insufficient Jitter

Use:

``` text
base TTL = 300
jitter = 1
```

Compare expiration concentration with a meaningful jitter window.

------------------------------------------------------------------------

## 65. Failure 5 --- Excessive Jitter

Use a jitter range that violates the intended freshness window.

This demonstrates that source protection cannot override correctness.

------------------------------------------------------------------------

## 66. Failure 6 --- Sliding Expiration Staleness

Continuously access a sliding-TTL key while changing the simulated
source.

Observe how the cache can remain stale indefinitely without
invalidation.

------------------------------------------------------------------------

## 67. Failure 7 --- Hot-Key Expiration

Expire one high-request key.

Observe source amplification.

Apply Chapter 15 single-flight protection.

------------------------------------------------------------------------

## 68. Failure 8 --- Refresh Failure

Allow soft TTL to pass, then make source refresh fail.

Validate the documented policy:

``` text
serve bounded stale?
return error?
retry later?
open circuit?
```

------------------------------------------------------------------------

## 69. Failure 9 --- Negative Cache Too Long

Cache `NOT_FOUND`, then create the object in the simulated source.

Observe delayed visibility.

------------------------------------------------------------------------

## 70. Failure 10 --- DR/Warming Expiration Wave

Warm many keys at once using identical TTLs.

Treat this as a future incident.

Repeat with jitter and compare distribution.

------------------------------------------------------------------------

# Part 44 --- Troubleshooting

## 71. Sudden Miss Spike

Check:

``` text
expired_keys rate
evicted_keys rate
deployment time
warming history
TTL distribution
namespace changes
Redis errors
```

Do not assume expiration until eviction and application changes are
ruled out.

------------------------------------------------------------------------

## 72. Source QPS Spikes Periodically

Look for:

``` text
synchronized TTL
scheduled warming
batch refresh
fixed cron behavior
hour/day boundaries
```

Periodic source spikes often reveal time alignment.

------------------------------------------------------------------------

## 73. Data Is Too Stale

Check:

``` text
TTL
sliding expiration
invalidation
refresh failures
soft/hard TTL
source update frequency
```

------------------------------------------------------------------------

## 74. Hit Ratio Too Low

Check:

``` text
TTL too short
working-set size
eviction
traffic pattern
cache-key mismatch
invalidation frequency
```

Do not simply increase TTL before reviewing freshness requirements.

------------------------------------------------------------------------

## 75. Refresh Traffic Too High

Check:

``` text
refresh threshold too early
too many refresh candidates
no hotness filter
scheduler synchronization
failed refresh retries
```

------------------------------------------------------------------------

## 76. Keys Never Expire

Check:

``` text
TTL return value
application EXPIRE calls
sliding expiration logic
writes replacing TTL semantics
persistent-key creation
```

------------------------------------------------------------------------

## 77. Negative Results Persist

Check:

``` text
negative TTL
invalidation after create
key construction
cached error vs. authoritative not-found
```

------------------------------------------------------------------------

# Part 45 --- Production Runbooks

## 78. Runbook --- Expiration Storm

``` text
1. Confirm expired-keys rate.
2. Confirm cache-miss rate.
3. Confirm source QPS/latency.
4. Identify affected key patterns.
5. Check TTL distribution.
6. Protect source with concurrency/rate controls.
7. Apply single-flight for hot misses.
8. Avoid mass immediate repopulation.
9. Restore cache gradually.
10. Add appropriate TTL jitter.
11. Validate future expiration distribution.
12. Monitor next TTL window.
```

------------------------------------------------------------------------

## 79. Runbook --- Stale Data

``` text
1. Identify key/pattern.
2. Identify source truth.
3. Measure cached age.
4. Check TTL.
5. Check soft/hard expiration.
6. Check sliding behavior.
7. Check invalidation path.
8. Check refresh failures.
9. Correct cache safely.
10. Validate future freshness contract.
```

------------------------------------------------------------------------

## 80. Runbook --- Excessive Source Load From TTL

``` text
1. Measure misses/sec.
2. Measure expiration rate.
3. Identify short-TTL patterns.
4. Confirm business freshness requirement.
5. Check refresh-ahead.
6. Check negative caching.
7. Check single-flight.
8. Increase TTL only if semantics permit.
9. Add jitter where appropriate.
10. Validate source QPS and staleness.
```

------------------------------------------------------------------------

## 81. Runbook --- Sliding TTL Problem

``` text
1. Confirm TTL is being extended.
2. Identify access frequency.
3. Compare cache with source.
4. Determine maximum acceptable staleness.
5. Add hard lifetime if required.
6. Add invalidation if available.
7. Test continuously hot key.
8. Validate correction after source update.
```

------------------------------------------------------------------------

## 82. Runbook --- Refresh-Ahead Failure

``` text
1. Measure refresh failures.
2. Check source health.
3. Check refresh lock contention.
4. Check refresh threshold.
5. Check stale-serving policy.
6. Protect source from retries.
7. Restore refresh gradually.
8. Confirm hard-expiration risk is controlled.
```

------------------------------------------------------------------------

# Part 46 --- TTL Design Template

## 83. Per Data Class

``` text
Service:
Key pattern:
Business object:
Source:
Request rate:
Update frequency:
Maximum acceptable staleness:
Base TTL:
Jitter:
Absolute or relative?:
Sliding?:
Maximum hard lifetime:
Soft TTL:
Hard TTL:
Refresh-ahead threshold:
Stale serving allowed?:
Negative cache TTL:
Invalidation mechanism:
Source regeneration latency:
Single-flight?:
Source QPS budget:
Owner:
```

------------------------------------------------------------------------

# Part 47 --- TTL Capacity Review

## 84. Questions

``` text
How many keys can expire per second safely?
How much source QPS can regeneration consume?
What happens when a hot key expires?
What happens when refresh fails?
Can stale data be served?
Can the source tolerate cold-cache recovery?
Are warming TTLs distributed?
Are DR TTLs distributed?
```

------------------------------------------------------------------------

# Production Acceptance Checklist

## 85. TTL Engineering

-   [ ] Freshness contract defined by data class.
-   [ ] Base TTL justified.
-   [ ] Absolute vs. relative semantics documented.
-   [ ] Sliding behavior explicitly approved or disabled.
-   [ ] Hard lifetime defined where required.
-   [ ] Soft TTL defined where stale serving is allowed.
-   [ ] Hard TTL defined.
-   [ ] TTL jitter configured where appropriate.
-   [ ] Jitter stays within freshness limits.
-   [ ] Hot-key expiration tested.
-   [ ] Single-flight/source protection validated.
-   [ ] Refresh-ahead reviewed.
-   [ ] Refresh failure behavior documented.
-   [ ] Negative-cache TTL documented.
-   [ ] Transient errors are not blindly cached as NOT_FOUND.
-   [ ] Expiration rate monitored.
-   [ ] Hit/miss ratio monitored.
-   [ ] Source QPS correlated with expiration.
-   [ ] Deployment warming TTL distribution tested.
-   [ ] DR warming TTL distribution tested.
-   [ ] Expiration-storm runbook validated.

------------------------------------------------------------------------

# Knowledge Validation

## 86. Questions

You should be able to answer:

1.  Why is TTL a business freshness contract?
2.  What is the difference between expiration and eviction?
3.  What are the tradeoffs of short TTL?
4.  What are the tradeoffs of long TTL?
5.  What is absolute expiration?
6.  What is relative expiration?
7.  What is sliding expiration?
8.  Why can sliding expiration create indefinite staleness?
9.  What is a hard TTL?
10. What is a soft TTL?
11. What is stale-while-revalidate?
12. When is stale serving inappropriate?
13. What is refresh-ahead?
14. What is TTL jitter?
15. Why does synchronized population create future risk?
16. How can jitter be too small?
17. How can jitter be too large?
18. What is an expiration storm?
19. Why does jitter not solve one hot key's miss concurrency?
20. Why use negative caching?
21. Why should negative TTL often be short?
22. Why should transient source errors not automatically become
    NOT_FOUND?
23. How does TTL influence source QPS?
24. How does TTL influence memory residency?
25. Why should big-key size affect TTL design?
26. Why should deployment warming use distributed TTLs?
27. Why should DR warming use distributed TTLs?
28. Which metrics identify expiration incidents?
29. Why should `expired_keys` be viewed as a rate?
30. What must pass before TTL strategy is production-ready?

------------------------------------------------------------------------

# Hands-On Acceptance Checklist

## 87. Lab Completion

-   [ ] Created a relative-TTL key.
-   [ ] Inspected `TTL`.
-   [ ] Inspected `PTTL`.
-   [ ] Created a persistent key.
-   [ ] Compared fixed expiration.
-   [ ] Reviewed sliding expiration.
-   [ ] Created synchronized TTL population.
-   [ ] Created jittered TTL population.
-   [ ] Compared TTL distributions.
-   [ ] Built expiration buckets.
-   [ ] Reviewed soft/hard TTL metadata.
-   [ ] Reviewed refresh-ahead threshold.
-   [ ] Created negative-cache example.
-   [ ] Reproduced expiration-storm concept.
-   [ ] Completed ten failure scenarios.
-   [ ] Completed troubleshooting.
-   [ ] Reviewed five production runbooks.
-   [ ] Completed TTL design template.
-   [ ] Completed capacity review.
-   [ ] Completed production acceptance checklist.

------------------------------------------------------------------------

# 88. Lab Cleanup

Discover:

``` bash
redis-cli --scan --pattern 'tutorial:chapter19:*'
```

Delete only confirmed Chapter 19 training keys in bounded batches with
`UNLINK`.

Examples:

``` redis
UNLINK tutorial:chapter19:basic
UNLINK tutorial:chapter19:persistent
UNLINK tutorial:chapter19:fixed
UNLINK tutorial:chapter19:sliding
UNLINK tutorial:chapter19:swr:item:1001
UNLINK tutorial:chapter19:refresh:item:1001
UNLINK tutorial:chapter19:negative:item:404
```

Delete `tutorial:chapter19:sync:*` and `tutorial:chapter19:jitter:*`
only after verifying the isolated namespace.

Do not use:

``` redis
FLUSHDB
FLUSHALL
```

against a shared or production database.

------------------------------------------------------------------------

# 89. Key Takeaways

1.  TTL is a freshness and source-capacity decision, not an arbitrary
    Redis number.
2.  Short TTL improves freshness but increases regeneration.
3.  Long TTL reduces source load but increases stale-data risk.
4.  Absolute and relative expiration solve different requirements.
5.  Sliding expiration can keep hot data alive indefinitely and
    therefore needs explicit freshness controls.
6.  Soft TTL enables controlled refresh before hard expiration.
7.  Hard TTL defines the maximum serving lifetime.
8.  Stale-while-revalidate is safe only where bounded staleness is
    acceptable.
9.  Refresh-ahead protects predictably hot data.
10. TTL jitter spreads future expiration load.
11. Jitter must remain within the freshness contract.
12. Synchronized cache population can schedule a future expiration
    storm.
13. A single hot-key expiration can overload the source even when other
    TTLs are well distributed.
14. Negative caching protects sources from repeated absent-object
    lookups.
15. Transient failures should not be confused with authoritative
    absence.
16. TTL affects hit ratio, source QPS, cache writes, and memory
    residency.
17. Big-key regeneration cost should influence TTL design.
18. Deployment and DR warming must distribute future expiration.
19. Expiration counters should be analyzed as rates and correlated with
    misses/source load.
20. Production readiness requires a documented freshness contract,
    source protection, failure testing, observability, and runbooks.

------------------------------------------------------------------------

# 90. References

Validate exact command behavior against the Redis and Redis Enterprise
versions deployed.

Recommended official Redis documentation areas:

-   `SET`
-   `EXPIRE`
-   `EXPIREAT`
-   `PEXPIRE`
-   `PEXPIREAT`
-   `TTL`
-   `PTTL`
-   `PERSIST`
-   `SCAN`
-   `UNLINK`
-   key expiration
-   key eviction
-   Redis caching patterns
-   Redis Enterprise monitoring

Soft TTL, stale-while-revalidate, refresh-ahead, sliding expiration,
negative caching, and TTL jitter are application architecture patterns.
Their exact implementation depends on business freshness requirements,
client framework, source capacity, workload hotness, and failure model.

------------------------------------------------------------------------

# Next Chapter

**Chapter 20 --- Redis Cache Invalidation, Consistency & Change
Propagation**

Chapter 20 will go deeply into:

-   cache invalidation
-   write/update/delete propagation
-   cache-aside consistency
-   invalidation ordering
-   race conditions
-   stale-write hazards
-   versioned keys
-   event-driven invalidation
-   CDC-based invalidation
-   pub/sub considerations
-   source-of-truth ownership
-   idempotency
-   failure recovery
-   observability
-   failure injection
-   troubleshooting
-   production runbooks
-   acceptance validation
