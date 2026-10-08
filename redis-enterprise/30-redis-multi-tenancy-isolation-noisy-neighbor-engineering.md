# Chapter 30 --- Redis Multi-Tenancy, Isolation & Noisy-Neighbor Engineering

**Status:** Canonical\
**Track:** Redis Enterprise / Redis Software Production Engineering\
**Part:** Part 2 --- Caching & Application Engineering\
**Level:** Intermediate → Production Multi-Tenant Redis Engineering\
**Audience:** Developers, SREs, DBREs, Platform Engineers, Redis
Administrators\
**Lab type:** Tenant keyspaces, shared and dedicated isolation models,
per-tenant workload generation, memory/CPU/network fairness, hot-tenant
detection, tenant quotas, rate limiting, concurrency control, shard-skew
analysis, migration, blast-radius testing, failure injection,
observability, troubleshooting, runbooks, and production acceptance

------------------------------------------------------------------------

# 1. Objective

Multi-tenant Redis systems allow multiple customers, applications,
business units, or workloads to share some Redis infrastructure.

Sharing can improve utilization and reduce operational cost, but it also
introduces contention and blast-radius risk.

A single tenant can consume disproportionate:

``` text
memory
CPU
network
connections
operations/sec
large values
hot keys
pipeline capacity
source-load capacity
```

and degrade other tenants.

By the end, you should be able to:

-   Define Redis multi-tenancy models.
-   Distinguish namespace isolation from security isolation.
-   Decide when workloads can safely share a database.
-   Identify when dedicated Redis databases are appropriate.
-   Define per-tenant resource budgets.
-   Detect noisy neighbors.
-   Detect hot tenants.
-   Detect tenant-driven shard skew.
-   Control tenant request rate and concurrency.
-   Protect memory capacity.
-   Protect connection pools.
-   Protect downstream sources.
-   Design tenant-aware observability.
-   Migrate tenants safely.
-   Reduce blast radius.
-   Inject noisy-neighbor failures.
-   Troubleshoot tenant incidents.
-   Build production runbooks and acceptance criteria.

------------------------------------------------------------------------

# 2. Core Production Principle

Multi-tenancy is not only:

``` text
tenant ID in the key
```

A production design must address:

``` text
identity
authorization
memory
CPU
network
connections
traffic
key placement
failure isolation
observability
migration
recovery
```

A namespace is an organizational boundary.

It is not automatically a resource or security boundary.

------------------------------------------------------------------------

# Part 1 --- Tenant Definition

## 3. What Is a Tenant?

A tenant may represent:

``` text
customer
hospital
business unit
application
service
team
environment
workload class
```

Define the tenant unit explicitly before designing controls.

------------------------------------------------------------------------

# Part 2 --- Shared Database Model

## 4. Architecture

``` text
Tenant A ─┐
Tenant B ─┼──> Shared Redis Database
Tenant C ─┘
```

Benefits:

``` text
higher utilization
fewer databases
simpler infrastructure
potentially lower cost
```

Risks:

``` text
shared memory
shared CPU
shared network
shared connection capacity
larger blast radius
```

------------------------------------------------------------------------

# Part 3 --- Dedicated Database Model

## 5. Architecture

``` text
Tenant A -> Redis DB A
Tenant B -> Redis DB B
Tenant C -> Redis DB C
```

Potential benefits:

``` text
stronger operational isolation
independent sizing
independent policies
smaller blast radius
easier tenant-specific scaling
```

Costs:

``` text
more infrastructure
more operational objects
possible lower utilization
higher cost
```

------------------------------------------------------------------------

# Part 4 --- Hybrid Model

## 6. Practical Pattern

A hybrid design may use:

``` text
small tenants -> shared database
large/hot tenants -> dedicated database
critical tenants -> dedicated database
```

Promotion criteria should be measurable.

------------------------------------------------------------------------

# Part 5 --- Namespace Isolation

## 7. Key Pattern

Example:

``` text
service:tenant:1001:profile:v1:5001
service:tenant:1002:profile:v1:5001
```

This prevents accidental key-name collisions when implemented correctly.

------------------------------------------------------------------------

# Part 6 --- Namespace Is Not Authorization

## 8. Security Warning

A client with unrestricted access to the database may still be able to
access another tenant's keys.

Do not assume:

``` text
tenant prefix
=
security boundary
```

Use appropriate Redis Enterprise/database/client access controls and
application authorization.

------------------------------------------------------------------------

# Part 7 --- Application Authorization

## 9. Tenant Context

The application should derive tenant identity from trusted
authentication/authorization context.

Do not trust arbitrary client-supplied tenant IDs without validation.

------------------------------------------------------------------------

# Part 8 --- Resource Isolation

## 10. Shared Resources

Even with perfect key naming, tenants may still share:

``` text
CPU
memory
network
connections
shards
```

Resource fairness needs explicit engineering.

------------------------------------------------------------------------

# Part 9 --- Tenant Budget

## 11. Define Limits

For each tenant or tenant class, define expected:

``` text
key count
memory
ops/sec
read QPS
write QPS
network bytes/sec
connections
concurrency
large-value allowance
```

------------------------------------------------------------------------

# Part 10 --- Tenant Classes

## 12. Example

``` text
small
medium
large
critical
```

Each class can have different:

``` text
capacity assumptions
rate limits
isolation model
monitoring thresholds
```

------------------------------------------------------------------------

# Part 11 --- Memory Fairness

## 13. Problem

Tenant A can create:

``` text
millions of keys
large values
long TTLs
persistent keys
```

and consume memory needed by Tenant B.

------------------------------------------------------------------------

# Part 12 --- TTL Governance

## 14. Tenant-Aware TTL

Define TTL policy by workload.

Example:

``` text
session cache: 30 minutes
search result: 5 minutes
reference cache: 6 hours
```

Do not let individual tenants silently create unlimited persistent cache
data.

------------------------------------------------------------------------

# Part 13 --- Cardinality Budget

## 15. Estimate

For one tenant:

``` text
users
×
cached objects/user
×
versions
```

Then aggregate across tenants.

------------------------------------------------------------------------

# Part 14 --- Value-Size Budget

## 16. Chapter 28 Connection

Track:

``` text
average
P95
P99
max
```

value sizes per tenant or tenant class where feasible.

One tenant with unusually large values can dominate network and memory.

------------------------------------------------------------------------

# Part 15 --- CPU Fairness

## 17. Sources of CPU

A tenant can consume excessive Redis CPU through:

``` text
high command rate
expensive commands
large collections
Lua scripts
hot keys
large pipelines
```

------------------------------------------------------------------------

# Part 16 --- Network Fairness

## 18. Byte Volume

Track:

``` text
requests/sec
×
request bytes
+
responses/sec
×
response bytes
```

A tenant with modest QPS but huge values can be a major network
consumer.

------------------------------------------------------------------------

# Part 17 --- Connection Fairness

## 19. Client Fleet

Tenant-specific workers can create excessive:

``` text
connections
reconnect storms
pool pressure
```

Chapter 26 connection budgets still apply.

------------------------------------------------------------------------

# Part 18 --- Rate Limiting

## 20. Purpose

Per-tenant rate limits can protect:

``` text
Redis
other tenants
downstream sources
```

Possible dimensions:

``` text
requests/sec
writes/sec
expensive operations/sec
```

------------------------------------------------------------------------

# Part 19 --- Concurrency Limiting

## 21. Why Rate Alone Is Not Enough

A tenant may remain within requests/sec but issue many slow operations
concurrently.

Bound:

``` text
in-flight operations
pipelines
source loads
refresh jobs
```

------------------------------------------------------------------------

# Part 20 --- Token Bucket Concept

## 22. Model

A tenant receives tokens at a configured rate.

Each request consumes a token.

If no token is available:

``` text
reject
queue briefly
degrade
```

according to service policy.

------------------------------------------------------------------------

# Part 21 --- Rate-Limit Key

## 23. Example

``` text
ratelimit:tenant:{1001}:api
```

If atomic multi-key logic is needed, design hash tags carefully.

A rate-limit key can itself become hot.

------------------------------------------------------------------------

# Part 22 --- Noisy Neighbor

## 24. Definition

A noisy neighbor is a tenant/workload whose resource use degrades other
tenants sharing the same system.

Symptoms:

``` text
latency rises for unrelated tenants
CPU skew
memory pressure
network saturation
pool contention
evictions
```

------------------------------------------------------------------------

# Part 23 --- Hot Tenant

## 25. Definition

A hot tenant generates disproportionate traffic.

It may be legitimate growth, not a fault.

The engineering question is whether the shared design still provides
acceptable isolation.

------------------------------------------------------------------------

# Part 24 --- Hot Key Within Hot Tenant

## 26. Combined Risk

``` text
one tenant
+
one extremely popular key
```

can create:

``` text
hot key
hot shard
network spike
source stampede after expiry
```

Apply Chapters 15, 18, and 19.

------------------------------------------------------------------------

# Part 25 --- Shard Skew

## 27. Tenant Placement

If tenant keys are concentrated through hash tags:

``` text
service:{tenant-1001}:...
```

one large tenant may concentrate traffic on one slot/shard.

Review whether full tenant co-location is actually required.

------------------------------------------------------------------------

# Part 26 --- Memory Balance vs. Traffic Balance

## 28. Different Metrics

A shard may hold only:

``` text
20% of memory
```

but process:

``` text
70% of operations
```

Monitor both storage and traffic distribution.

------------------------------------------------------------------------

# Part 27 --- Per-Tenant Metrics

## 29. Useful Dimensions

Where cardinality permits:

``` text
tenant class
top tenants
service
operation type
```

Avoid exposing every raw tenant ID as an unlimited metric label if
tenant cardinality is huge.

------------------------------------------------------------------------

# Part 28 --- Top-N Reporting

## 30. Safer Observability

Instead of permanent metrics for every tenant, use:

``` text
top N tenants by QPS
top N by bytes
top N by errors
top N by memory estimate
```

plus aggregated tenant classes.

------------------------------------------------------------------------

# Part 29 --- Tenant Memory Measurement

## 31. Approximation

Redis does not automatically know application tenant semantics.

Possible approaches:

``` text
application accounting
sampled MEMORY USAGE
offline SCAN analysis
tenant inventory
```

Avoid frequent full keyspace scans for monitoring.

------------------------------------------------------------------------

# Part 30 --- Tenant Traffic Accounting

## 32. Best Location

Application/service telemetry often knows tenant identity better than
Redis.

Measure at the application boundary:

``` text
tenant requests
Redis commands
bytes
latency
errors
```

------------------------------------------------------------------------

# Part 31 --- Source Protection

## 33. Cache Misses

A noisy tenant can overload the source through:

``` text
cache misses
expiration storm
cold start
invalidations
```

Use per-tenant and global source concurrency limits.

------------------------------------------------------------------------

# Part 32 --- Warming Fairness

## 34. Chapter 16 Connection

Do not let one tenant's cache warming consume all:

``` text
source QPS
Redis write capacity
network
workers
```

Schedule or rate-limit warming by tenant.

------------------------------------------------------------------------

# Part 33 --- Eviction Fairness

## 35. Shared Eviction Domain

In a shared memory domain, one tenant's growth can cause eviction of
another tenant's keys depending on configuration/workload.

This is a major isolation consideration.

------------------------------------------------------------------------

# Part 34 --- Dedicated Database Trigger

## 36. Candidate Criteria

Consider dedicated isolation when a tenant has:

``` text
large memory share
high QPS
high byte volume
strict SLO
different persistence requirements
different security requirements
different maintenance needs
frequent noisy-neighbor impact
```

------------------------------------------------------------------------

# Part 35 --- Promotion Threshold

## 37. Example Policy

Illustrative:

``` text
if tenant > 25% of database memory
or > 30% of sustained operations
or repeatedly breaches shared SLO
then evaluate dedicated database
```

Use thresholds derived from your environment.

------------------------------------------------------------------------

# Part 36 --- Blast Radius

## 38. Design Question

Ask:

``` text
If Tenant A behaves badly, what can Tenant B lose?
```

Possible effects:

``` text
latency
cache residency
connection availability
source capacity
Redis availability
```

------------------------------------------------------------------------

# Part 37 --- Tenant Migration

## 39. Goal

Move:

``` text
Tenant A
from shared Redis
to dedicated Redis
```

without incorrect reads or uncontrolled load.

------------------------------------------------------------------------

# Part 38 --- Migration Phases

## 40. Pattern

``` text
1. inventory tenant keys
2. provision target
3. deploy routing capability
4. warm/copy if required
5. dual-read or controlled fallback
6. switch writes
7. validate
8. switch reads
9. monitor
10. retire old keys
```

Exact ordering depends on data semantics.

------------------------------------------------------------------------

# Part 39 --- Cache Migration

## 41. Derived Cache

For a cache, it may be safer to:

``` text
route tenant to new Redis
allow cache to repopulate
```

rather than copy every old key.

But protect the authoritative source from a cold-cache storm.

------------------------------------------------------------------------

# Part 40 --- Authoritative Redis Data

## 42. Different Standard

If Redis stores authoritative state, migration requires:

``` text
consistency
durability
validated transfer
cutover controls
rollback
```

Do not treat it like disposable cache data.

------------------------------------------------------------------------

# Part 41 --- Routing Layer

## 43. Tenant Routing

Application configuration may map:

``` text
tenant class -> Redis endpoint
tenant ID -> Redis endpoint
```

Routing changes should be observable and reversible.

------------------------------------------------------------------------

# Part 42 --- Configuration Drift

## 44. Risk

If only some application instances know Tenant A moved:

``` text
old Redis receives some traffic
new Redis receives some traffic
```

This can create inconsistent state.

Use controlled configuration rollout.

------------------------------------------------------------------------

# Part 43 --- Failure Isolation

## 45. Tenant-Specific Failure

A malformed tenant payload or abusive request should not crash shared
workers handling all tenants.

Use:

``` text
validation
timeouts
bounded retries
per-tenant limits
bulkheads
```

------------------------------------------------------------------------

# Part 44 --- Bulkhead Pattern

## 46. Concept

Instead of one unlimited shared worker pool:

``` text
all tenants -> one queue -> workers
```

use bounded partitions or concurrency controls so one tenant cannot
consume all workers.

------------------------------------------------------------------------

# Part 45 --- Retry Fairness

## 47. Retry Storm

A failing tenant can generate:

``` text
request
retry
retry
retry
```

and steal capacity from healthy tenants.

Use:

``` text
bounded retries
backoff
jitter
tenant-aware retry budgets
```

------------------------------------------------------------------------

# Part 46 --- Circuit Breaking

## 48. Tenant Scope

If one tenant's dependency path is failing, a tenant-scoped circuit
breaker can prevent repeated expensive attempts while preserving other
tenants.

------------------------------------------------------------------------

# Part 47 --- Security and ACLs

## 49. Validate Deployment Controls

Redis/Redis Enterprise access-control capabilities can restrict commands
and key patterns depending on version/topology.

Use official documentation for the deployed release.

Application tenant authorization remains necessary.

------------------------------------------------------------------------

# Part 48 --- Administrative Commands

## 50. Restriction

Application clients generally should not have unnecessary
administrative/destructive capabilities.

Apply least privilege.

------------------------------------------------------------------------

# Part 49 --- Observability

## 51. Tenant Metrics

Recommended application metrics:

``` text
tenant_redis_requests_total
tenant_redis_errors_total
tenant_redis_duration_seconds
tenant_redis_request_bytes
tenant_redis_response_bytes
tenant_cache_hits_total
tenant_cache_misses_total
```

Use controlled-cardinality dimensions.

------------------------------------------------------------------------

## 52. Protection Metrics

Track:

``` text
tenant_rate_limit_rejections
tenant_concurrency_rejections
tenant_retry_exhausted
tenant_source_loads
tenant_warming_jobs
```

------------------------------------------------------------------------

## 53. Redis Metrics

Correlate:

``` text
CPU/shard
memory/shard
network/shard
ops/sec/shard
evictions
latency
connections
```

------------------------------------------------------------------------

# Part 50 --- Tenant Health Score

## 54. Concept

A tenant health view may combine:

``` text
QPS
P99
error rate
cache hit ratio
bytes/sec
rate-limit events
source-load rate
```

Use it for diagnosis, not as an opaque correctness decision.

------------------------------------------------------------------------

# Part 51 --- Hands-On Lab

## 55. Objectives

You will:

1.  create tenant-aware keys;
2.  generate normal tenants;
3.  generate one noisy tenant;
4.  measure per-tenant requests;
5.  simulate memory skew;
6.  simulate traffic skew;
7.  implement per-tenant rate limiting;
8.  implement per-tenant concurrency control;
9.  test retry fairness;
10. test hot hash-tag behavior;
11. simulate tenant migration;
12. perform safe cleanup.

------------------------------------------------------------------------

## 56. Prerequisites

``` bash
python -m pip install redis
```

Environment:

``` bash
REDIS_HOST
REDIS_PORT
REDIS_PASSWORD
```

------------------------------------------------------------------------

# Part 52 --- Tenant Key Pattern

## 57. Lab Convention

``` text
tutorial:chapter30:tenant:<tenant-id>:item:<item-id>
```

Examples:

``` text
tutorial:chapter30:tenant:1001:item:1
tutorial:chapter30:tenant:1002:item:1
```

------------------------------------------------------------------------

# Part 53 --- Workload Generator

## 58. Create `chapter30_multitenancy_lab.py`

``` python
import os
import random
import threading
import time
from collections import defaultdict

import redis

HOST = os.getenv("REDIS_HOST", "localhost")
PORT = int(os.getenv("REDIS_PORT", "6379"))
PASSWORD = os.getenv("REDIS_PASSWORD") or None

r = redis.Redis(
    host=HOST,
    port=PORT,
    password=PASSWORD,
    decode_responses=True,
    socket_connect_timeout=2,
    socket_timeout=2,
)

PREFIX = "tutorial:chapter30"
TENANTS = [
    "1001",
    "1002",
    "1003",
]

metrics = defaultdict(
    lambda: {
        "requests": 0,
        "errors": 0,
    }
)

lock = threading.Lock()


def key(
    tenant,
    item,
):
    return (
        f"{PREFIX}:tenant:"
        f"{tenant}:item:{item}"
    )


def seed():
    pipe = r.pipeline(
        transaction=False
    )

    for tenant in TENANTS:
        for item in range(100):
            pipe.set(
                key(tenant, item),
                f"value-{tenant}-{item}",
                ex=3600,
            )

    pipe.execute()


def worker(
    tenant,
    operations,
):
    for _ in range(operations):
        item = random.randint(
            0,
            99,
        )

        try:
            r.get(
                key(
                    tenant,
                    item,
                )
            )

            with lock:
                metrics[
                    tenant
                ]["requests"] += 1

        except Exception:
            with lock:
                metrics[
                    tenant
                ]["errors"] += 1


if __name__ == "__main__":
    print(
        "PING:",
        r.ping(),
    )

    seed()

    threads = [
        threading.Thread(
            target=worker,
            args=("1001", 1000),
        ),
        threading.Thread(
            target=worker,
            args=("1002", 1000),
        ),
        threading.Thread(
            target=worker,
            args=("1003", 10000),
        ),
    ]

    start = time.perf_counter()

    for thread in threads:
        thread.start()

    for thread in threads:
        thread.join()

    elapsed = (
        time.perf_counter()
        - start
    )

    print(
        "elapsed:",
        round(elapsed, 3),
    )

    for tenant, data in metrics.items():
        print(
            tenant,
            data,
        )
```

Tenant `1003` intentionally generates much more traffic.

------------------------------------------------------------------------

# Part 54 --- Run Workload

## 59. Execute

``` bash
python chapter30_multitenancy_lab.py
```

Observe the disproportionate request share of Tenant `1003`.

In production, the goal is to identify this before unrelated tenants
breach SLOs.

------------------------------------------------------------------------

# Part 55 --- Memory Skew Lab

## 60. Create Large Tenant Values

In a disposable environment, write larger values for one tenant.

Compare sampled:

``` redis
MEMORY USAGE tutorial:chapter30:tenant:1001:item:1
MEMORY USAGE tutorial:chapter30:tenant:1003:item:1
```

Estimate:

``` text
sample memory/key
×
tenant key count
```

Use sampling carefully; heterogeneous values require distributions, not
one sample.

------------------------------------------------------------------------

# Part 56 --- Rate-Limit Lab

## 61. Fixed-Window Learning Example

For a lab only:

``` python
def allow_request(
    tenant,
    limit=100,
):
    second = int(
        time.time()
    )

    rl_key = (
        f"{PREFIX}:ratelimit:"
        f"{tenant}:{second}"
    )

    count = r.incr(rl_key)

    if count == 1:
        r.expire(
            rl_key,
            2,
        )

    return count <= limit
```

This demonstrates the concept but has fixed-window boundary behavior.

Production rate limiting should use a design appropriate to required
accuracy, fairness, topology, and failure semantics.

------------------------------------------------------------------------

# Part 57 --- Atomic Rate-Limit Improvement

## 62. Lua Concept

A production implementation should avoid unsafe multi-command
initialization races.

Use a tested atomic design such as:

``` text
Lua
Redis Function
supported rate-limit primitive
```

according to deployed Redis version and architecture.

------------------------------------------------------------------------

# Part 58 --- Concurrency Limit Lab

## 63. Application Semaphore

``` python
tenant_limits = {
    "1001": threading.Semaphore(4),
    "1002": threading.Semaphore(4),
    "1003": threading.Semaphore(2),
}


def guarded_get(
    tenant,
    item,
):
    semaphore = tenant_limits[
        tenant
    ]

    acquired = semaphore.acquire(
        timeout=0.05
    )

    if not acquired:
        return None

    try:
        return r.get(
            key(
                tenant,
                item,
            )
        )

    finally:
        semaphore.release()
```

This prevents one tenant from consuming unlimited application worker
concurrency.

------------------------------------------------------------------------

# Part 59 --- Global + Tenant Limits

## 64. Layered Protection

Use both:

``` text
global concurrency limit
per-tenant concurrency limit
```

so:

``` text
one tenant cannot dominate
and
aggregate tenants cannot overload Redis
```

------------------------------------------------------------------------

# Part 60 --- Hot-Tag Lab

## 65. Key Pattern

Create:

``` text
tutorial:chapter30:{tenant-1003}:item:1
tutorial:chapter30:{tenant-1003}:item:2
...
```

Where cluster tooling supports it, inspect slot placement.

Review whether tenant-level co-location is required.

------------------------------------------------------------------------

# Part 61 --- Tenant Migration Lab

## 66. Simulated Routing

``` python
routing = {
    "1001": "shared",
    "1002": "shared",
    "1003": "dedicated",
}
```

In a real application, routing maps to separate configured Redis
clients/endpoints.

Do not dynamically create a new connection pool for every request.

------------------------------------------------------------------------

# Part 62 --- Cold Migration Protection

## 67. Cache Use Case

If Tenant `1003` moves to an empty dedicated cache:

``` text
all first reads may miss
```

Protect source using:

``` text
warming
single-flight
source concurrency limits
rate limiting
```

------------------------------------------------------------------------

# Part 63 --- Failure Injection

## 68. Failure 1 --- Traffic Flood

Increase one tenant's QPS dramatically.

Observe:

``` text
Redis CPU
latency
other tenant latency
```

Then apply tenant/global limits.

------------------------------------------------------------------------

## 69. Failure 2 --- Memory Flood

Let one tenant create many large values.

Observe memory pressure and eviction risk.

------------------------------------------------------------------------

## 70. Failure 3 --- Connection Flood

Give one tenant many workers/pools.

Observe:

``` text
connected clients
pool behavior
Redis connection pressure
```

------------------------------------------------------------------------

## 71. Failure 4 --- Hot Tenant Hash Tag

Co-locate all one tenant's hot keys.

Observe shard skew.

------------------------------------------------------------------------

## 72. Failure 5 --- Retry Storm

Make one tenant's operation fail and retry aggressively.

Observe capacity theft from healthy tenants.

Then add bounded retry/backoff/jitter.

------------------------------------------------------------------------

## 73. Failure 6 --- Warming Storm

Warm one large tenant without rate limits.

Observe source and Redis write pressure.

Then pace warming.

------------------------------------------------------------------------

## 74. Failure 7 --- Expiration Storm

Give one tenant many identical TTLs.

Observe miss/source burst.

Apply Chapter 19 TTL jitter and Chapter 15 source protection.

------------------------------------------------------------------------

## 75. Failure 8 --- Large-Value Tenant

Give one tenant much larger values at similar QPS.

Observe network and memory impact.

------------------------------------------------------------------------

## 76. Failure 9 --- Partial Migration

Route only half of application instances to the new tenant database.

Observe inconsistent cache population/state behavior.

Then enforce controlled routing rollout.

------------------------------------------------------------------------

## 77. Failure 10 --- Missing Tenant Boundary

Write two tenants under a non-tenant-aware key.

Observe overwrite/data-isolation failure.

Correct keyspace design and authorization.

------------------------------------------------------------------------

# Part 64 --- Troubleshooting

## 78. One Tenant Slow

Check:

``` text
tenant QPS
tenant bytes
tenant hit ratio
tenant source loads
hot keys
rate-limit events
shard placement
```

Determine whether the issue is tenant-local or shared-resource
saturation.

------------------------------------------------------------------------

## 79. All Tenants Slow After One Tenant Spike

Check:

``` text
Redis CPU
network
memory
evictions
connections
hot shard
source capacity
```

Then identify the tenant contribution.

------------------------------------------------------------------------

## 80. Memory Pressure

Check:

``` text
top tenant key counts
value sizes
TTL coverage
persistent keys
migration duplicates
```

------------------------------------------------------------------------

## 81. One Shard Hot

Check:

``` text
tenant hash tags
hot keys
tenant traffic
slot distribution
```

------------------------------------------------------------------------

## 82. Rate Limit Rejections High

Determine whether:

``` text
tenant traffic legitimately increased
limit is too low
retry loop is amplifying traffic
application is batching incorrectly
```

Do not simply raise the limit before checking capacity.

------------------------------------------------------------------------

## 83. Source Overloaded

Check:

``` text
tenant miss rate
expiration
invalidation
warming
cold migration
single-flight
source concurrency limits
```

------------------------------------------------------------------------

## 84. Dedicated Tenant Still Impacts Shared System

Check shared dependencies:

``` text
application worker pool
source database
network
Kubernetes nodes
connection management
```

Redis isolation alone may not isolate the entire request path.

------------------------------------------------------------------------

# Part 65 --- Production Runbooks

## 85. Runbook --- Noisy Tenant

``` text
1. Confirm shared SLO impact.
2. Identify top tenant by QPS/bytes/errors.
3. Check Redis CPU/network/memory.
4. Check shard skew.
5. Apply bounded tenant rate/concurrency controls.
6. Protect source dependencies.
7. Verify healthy tenants recover.
8. Determine root workload change.
9. Evaluate dedicated isolation.
10. Document capacity adjustment.
```

------------------------------------------------------------------------

## 86. Runbook --- Tenant Memory Runaway

``` text
1. Identify growing tenant namespace.
2. Measure key creation rate.
3. Check TTL coverage.
4. Sample value size/MEMORY USAGE.
5. Estimate tenant memory share.
6. Stop runaway creation if needed.
7. Correct lifecycle.
8. Clean confirmed derived keys in bounded batches if safe.
9. Monitor memory/evictions.
10. Add tenant budget alert.
```

------------------------------------------------------------------------

## 87. Runbook --- Tenant Hot Shard

``` text
1. Identify hot shard.
2. Identify tenant contribution.
3. Inspect hash tags.
4. Identify hot keys.
5. Confirm co-location requirement.
6. Redesign placement if safe.
7. Migrate gradually.
8. Load-test.
9. Monitor shard P99/CPU/network.
10. Document placement policy.
```

------------------------------------------------------------------------

## 88. Runbook --- Promote Tenant to Dedicated Redis

``` text
1. Confirm promotion criteria.
2. Provision/sizing target.
3. Validate security/configuration.
4. Deploy routing support.
5. Warm or prepare cache safely.
6. Cut writes according to data semantics.
7. Cut reads.
8. Monitor SLO/hit ratio/source.
9. Retire old tenant keys safely.
10. Validate rollback and close migration.
```

------------------------------------------------------------------------

## 89. Runbook --- Tenant Retry Storm

``` text
1. Identify tenant/error source.
2. Measure retries vs. original requests.
3. Cap tenant concurrency.
4. Stop unbounded retries.
5. Add backoff/jitter.
6. Apply circuit breaker if appropriate.
7. Protect Redis/source.
8. Verify other tenants recover.
9. Correct failure handling.
10. Add retry amplification alert.
```

------------------------------------------------------------------------

# Part 66 --- Tenant Design Template

## 90. Fields

``` text
Tenant definition:
Tenant count:
Tenant classes:
Shared/dedicated model:
Key namespace:
Authorization model:
Expected keys/tenant:
Expected memory/tenant:
Expected QPS/tenant:
Expected bytes/sec/tenant:
Connection budget:
Concurrency budget:
Rate limit:
TTL policy:
Large-value limit:
Hot-key risk:
Hash-tag policy:
Source-load budget:
Warming policy:
Retry budget:
Migration trigger:
Dedicated-DB trigger:
Metrics:
Owner:
```

------------------------------------------------------------------------

# Part 67 --- Tenant Capacity Table

## 91. Example

  ------------------------------------------------------------------------------------
  Tenant      Key count     Memory        QPS    Network   Concurrency Isolation
  class                                                                
  ---------- ---------- ---------- ---------- ---------- ------------- ---------------
  Small                                                                Shared

  Medium                                                               Shared

  Large                                                                Evaluate
                                                                       dedicated

  Critical                                                             Dedicated /
                                                                       policy-driven
  ------------------------------------------------------------------------------------

Populate from real workload measurements.

------------------------------------------------------------------------

# Part 68 --- Promotion Decision

## 92. Questions

Evaluate:

``` text
What percentage of memory?
What percentage of operations?
What percentage of network?
Does tenant create shard skew?
Does tenant have stricter SLO?
Does tenant need different security?
Does tenant need different persistence?
Has tenant caused repeated incidents?
```

------------------------------------------------------------------------

# Part 69 --- Blast-Radius Review

## 93. Questions

For one tenant failure:

``` text
Can it exhaust memory?
Can it exhaust connections?
Can it saturate CPU?
Can it saturate network?
Can it overload the source?
Can it trigger evictions for others?
Can it consume all workers?
Can it trigger retry storms?
```

Every "yes" requires an explicit mitigation or accepted risk.

------------------------------------------------------------------------

# Production Acceptance Checklist

## 94. Multi-Tenant Engineering

-   [ ] Tenant definition documented.
-   [ ] Shared/dedicated model documented.
-   [ ] Namespace convention documented.
-   [ ] Tenant authorization reviewed.
-   [ ] Namespace not treated as security boundary.
-   [ ] Key-count budget defined.
-   [ ] Memory budget defined.
-   [ ] QPS budget defined.
-   [ ] Network budget defined.
-   [ ] Connection budget defined.
-   [ ] Concurrency budget defined.
-   [ ] TTL policy defined.
-   [ ] Persistent-key policy defined.
-   [ ] Large-value risk measured.
-   [ ] Hot-key risk measured.
-   [ ] Hash-tag policy reviewed.
-   [ ] Hot-shard risk tested.
-   [ ] Tenant rate limiting tested where needed.
-   [ ] Tenant concurrency limiting tested.
-   [ ] Global capacity limit retained.
-   [ ] Retry budget defined.
-   [ ] Source protection tested.
-   [ ] Warming fairness tested.
-   [ ] Tenant observability available.
-   [ ] Promotion criteria defined.
-   [ ] Migration tested.
-   [ ] Blast-radius review completed.
-   [ ] Production runbooks validated.

------------------------------------------------------------------------

# Knowledge Validation

## 95. Questions

You should be able to answer:

1.  What is Redis multi-tenancy?
2.  What are the benefits of a shared database?
3.  What are the risks of a shared database?
4.  What are the benefits of dedicated databases?
5.  What is a hybrid tenant model?
6.  Why is a key namespace not a security boundary?
7.  Why must tenant identity come from trusted context?
8.  Which Redis resources can tenants contend for?
9.  What should a tenant budget include?
10. Why classify tenants?
11. How can one tenant create memory pressure?
12. Why track tenant value sizes?
13. How can a tenant consume excessive CPU?
14. Why measure bytes as well as QPS?
15. Why use both rate and concurrency limits?
16. What is a noisy neighbor?
17. What is a hot tenant?
18. How can tenant hash tags create shard skew?
19. Why can memory balance differ from traffic balance?
20. Why use controlled-cardinality tenant metrics?
21. Why is application telemetry useful for tenant accounting?
22. How can cache misses make one tenant overload the source?
23. Why must warming be tenant-aware?
24. How can shared eviction reduce isolation?
25. When should a tenant be considered for dedicated Redis?
26. Why is cache migration different from authoritative-state migration?
27. What is a tenant routing layer?
28. Why are retry budgets important in multi-tenant systems?
29. What is a bulkhead?
30. What must pass before a multi-tenant Redis design is
    production-ready?

------------------------------------------------------------------------

# Hands-On Acceptance Checklist

## 96. Lab Completion

-   [ ] Created tenant-aware key patterns.
-   [ ] Seeded multiple tenants.
-   [ ] Generated normal tenant traffic.
-   [ ] Generated noisy tenant traffic.
-   [ ] Compared per-tenant requests.
-   [ ] Tested tenant memory skew.
-   [ ] Reviewed value-size skew.
-   [ ] Implemented learning rate limit.
-   [ ] Reviewed atomic rate-limit requirement.
-   [ ] Implemented tenant concurrency guard.
-   [ ] Implemented global + tenant limit concept.
-   [ ] Tested hot hash-tag behavior.
-   [ ] Reviewed tenant routing.
-   [ ] Reviewed cold migration protection.
-   [ ] Injected traffic flood.
-   [ ] Injected memory flood.
-   [ ] Injected connection flood.
-   [ ] Injected hot-shard behavior.
-   [ ] Injected retry storm.
-   [ ] Injected warming storm.
-   [ ] Injected expiration storm.
-   [ ] Injected large-value tenant.
-   [ ] Injected partial migration.
-   [ ] Injected missing tenant boundary.
-   [ ] Completed troubleshooting.
-   [ ] Reviewed five production runbooks.
-   [ ] Completed tenant design template.
-   [ ] Completed blast-radius review.
-   [ ] Completed production acceptance checklist.

------------------------------------------------------------------------

# 97. Lab Cleanup

First discover only Chapter 30 keys:

``` bash
redis-cli --scan --pattern 'tutorial:chapter30:*'
```

Review the results.

Delete confirmed lab keys in bounded batches using `UNLINK`.

Do not use:

``` redis
KEYS tutorial:chapter30:*
FLUSHDB
FLUSHALL
```

against a shared or production database.

For tenant cleanup in production, confirm:

``` text
tenant
namespace
data role
owner
key count
TTL
rebuild/recovery path
deletion rate
monitoring
```

before deletion.

------------------------------------------------------------------------

# 98. Key Takeaways

1.  Multi-tenancy shares infrastructure but also shares failure and
    resource pressure.
2.  Tenant prefixes prevent key collisions but are not security
    boundaries.
3.  Tenant authorization must be enforced through trusted application
    and platform controls.
4.  Tenant budgets should cover memory, CPU-driving traffic, network,
    connections, and concurrency.
5.  QPS alone is insufficient; byte volume and command cost matter.
6.  TTL governance prevents tenants from silently creating permanent
    cache growth.
7.  Large values can make a moderate-QPS tenant a major resource
    consumer.
8.  Rate limits protect throughput; concurrency limits protect in-flight
    capacity.
9.  Use both tenant-specific and global limits.
10. A noisy neighbor is a shared-resource isolation problem, not merely
    a high-QPS tenant.
11. Hash tags can concentrate a large tenant on one slot/shard.
12. Monitor per-shard traffic as well as memory.
13. Application telemetry is often the best source of tenant-aware
    request accounting.
14. Tenant cache misses, warming, and retries can overload authoritative
    sources.
15. Shared eviction domains can allow one tenant's memory growth to
    affect another.
16. Large, hot, critical, or differently regulated tenants may justify
    dedicated Redis.
17. Tenant migrations require controlled routing and source protection.
18. Retry budgets and bulkheads prevent failing tenants from consuming
    all capacity.
19. Blast-radius analysis should be performed before production, not
    only after an incident.
20. Production multi-tenancy requires explicit isolation, fairness,
    observability, migration, and incident-response design.

------------------------------------------------------------------------

# 99. References

Validate exact Redis Enterprise database isolation, access-control,
clustering, memory, monitoring, and migration capabilities against the
deployed product version.

Recommended official documentation areas:

-   Redis Enterprise databases
-   Redis Enterprise clustering
-   Redis Enterprise monitoring
-   Redis Enterprise access control / RBAC
-   Redis ACLs
-   Redis memory management
-   Redis Cluster hash slots and hash tags
-   `MEMORY USAGE`
-   `SCAN`
-   Redis pipelining
-   Redis latency monitoring

Application-level tenant authorization, fairness, quotas, and routing
must also be validated against the application's architecture and
security requirements.

------------------------------------------------------------------------

# Next Chapter

**Chapter 31 --- Redis Rate Limiting, Quotas & Traffic Shaping**

Chapter 31 will cover:

-   fixed-window counters
-   sliding-window concepts
-   token bucket
-   leaky bucket
-   Lua atomicity
-   per-user limits
-   per-tenant limits
-   global limits
-   burst capacity
-   concurrency limits
-   retry-after behavior
-   clock/time-window considerations
-   hot rate-limit keys
-   cluster placement
-   failure semantics
-   observability
-   failure injection
-   troubleshooting
-   production runbooks
-   acceptance validation
