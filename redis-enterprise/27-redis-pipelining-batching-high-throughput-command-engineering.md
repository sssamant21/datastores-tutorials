# Chapter 27 --- Redis Pipelining, Batching & High-Throughput Command Engineering

**Status:** Canonical\
**Track:** Redis Enterprise / Redis Software Production Engineering\
**Part:** Part 2 --- Caching & Application Engineering\
**Level:** Intermediate → Production Redis Throughput Engineering\
**Audience:** Developers, SREs, DBREs, Platform Engineers, Redis
Administrators\
**Lab type:** Round-trip analysis, Redis pipelining, batch sizing,
throughput/latency comparison, response buffering, memory analysis,
error handling, partial-result interpretation, transaction comparison,
cluster/shard distribution, hot-key testing, client backpressure,
benchmark methodology, failure injection, troubleshooting, runbooks, and
production acceptance

------------------------------------------------------------------------

# 1. Objective

Redis commands are often extremely fast on the server, but application
throughput can still be limited by network round trips.

A client that performs:

``` text
send command
wait for response
send next command
wait for response
```

may spend more time waiting on network latency than Redis spends
executing commands.

Pipelining and batching can reduce that overhead.

By the end, you should be able to:

-   Explain Redis round-trip cost.
-   Explain pipelining.
-   Distinguish pipelining from transactions.
-   Batch commands safely.
-   Measure throughput vs. latency.
-   Select a bounded pipeline size.
-   Understand request and response buffering.
-   Estimate pipeline memory impact.
-   Handle per-command errors.
-   Interpret partial command results.
-   Understand retry ambiguity.
-   Apply backpressure.
-   Understand cluster/shard behavior.
-   Detect hot-key and hot-shard problems.
-   Benchmark pipeline sizes correctly.
-   Inject pipeline failures.
-   Troubleshoot production incidents.
-   Build production runbooks and acceptance criteria.

------------------------------------------------------------------------

# 2. Core Production Principle

Pipelining improves efficiency by reducing round trips.

It does not make Redis infinitely fast.

Production pipeline design should be:

``` text
bounded
measured
memory-aware
failure-aware
topology-aware
```

Avoid:

``` text
unbounded batch
maximum-size batch by default
blind retry of failed batches
```

------------------------------------------------------------------------

# Part 1 --- Network Round Trips

## 3. Sequential Commands

Suppose an application sends 1,000 independent commands sequentially.

Concept:

``` text
command 1 -> wait
command 2 -> wait
command 3 -> wait
...
```

Even small round-trip latency accumulates.

------------------------------------------------------------------------

# Part 2 --- Simple Latency Model

## 4. Approximation

If round-trip latency is:

``` text
1 ms
```

then 1,000 strictly sequential command/response cycles can spend
roughly:

``` text
1,000 × 1 ms
=
~1 second
```

just in round-trip waiting, before considering other costs.

This is an intuition model, not a complete performance formula.

------------------------------------------------------------------------

# Part 3 --- Pipelining

## 5. Concept

Pipelining allows the client to send multiple commands without waiting
for each individual response first.

Concept:

``` text
SET key1 value1
SET key2 value2
SET key3 value3
SET key4 value4
        |
        v
Redis processes commands
        |
        v
responses returned
```

This reduces round-trip overhead.

------------------------------------------------------------------------

# Part 4 --- Pipeline Is Not One Command

## 6. Important Distinction

A pipeline contains multiple Redis commands.

Redis still executes the commands individually.

Pipelining changes client/server communication efficiency.

------------------------------------------------------------------------

# Part 5 --- Pipeline Is Not Atomic

## 7. No Automatic Transaction

A normal non-transactional pipeline does not mean:

``` text
all commands succeed together
```

or:

``` text
no other client can interleave
```

If atomicity is required, use the appropriate Redis primitive.

------------------------------------------------------------------------

# Part 6 --- Pipeline vs. MULTI/EXEC

## 8. Different Goals

Pipeline:

``` text
reduce round trips
increase throughput
```

Transaction:

``` text
group commands under Redis transaction semantics
```

A client library may use pipelining to transport transaction commands,
but the concepts are different.

------------------------------------------------------------------------

# Part 7 --- redis-py Behavior

## 9. Explicit Setting

For throughput-only pipelining in redis-py:

``` python
pipe = r.pipeline(
    transaction=False
)
```

This makes the intent clear.

Validate exact client behavior against the deployed redis-py version.

------------------------------------------------------------------------

# Part 8 --- Batch Size

## 10. Core Tuning Variable

Examples:

``` text
1
10
50
100
500
1,000
5,000
```

There is no universal best pipeline size.

Measure it.

------------------------------------------------------------------------

# Part 9 --- Small Pipelines

## 11. Benefits

Smaller batches generally provide:

``` text
lower buffering
lower per-batch latency
smaller retry/failure scope
faster result availability
```

But may leave throughput on the table.

------------------------------------------------------------------------

# Part 10 --- Large Pipelines

## 12. Benefits and Costs

Larger batches may:

``` text
reduce round trips further
increase throughput
```

but can increase:

``` text
client memory
server response buffering
time before results are available
failure ambiguity
latency variance
```

------------------------------------------------------------------------

# Part 11 --- Throughput vs. Latency

## 13. Tradeoff

A batch may improve:

``` text
commands/sec
```

while worsening:

``` text
time for one item to receive its result
```

Optimize for the application objective, not only the largest throughput
number.

------------------------------------------------------------------------

# Part 12 --- Batch Fill Delay

## 14. Hidden Latency

If an application waits to collect:

``` text
1,000 items
```

before sending a pipeline, low traffic may cause requests to wait
unnecessarily.

Use:

``` text
max batch size
or
max batch age
```

so batches flush by either condition.

------------------------------------------------------------------------

# Part 13 --- Dual Flush Policy

## 15. Example

Flush when:

``` text
batch reaches 100 commands
OR
5 ms has elapsed
```

This balances throughput and latency.

------------------------------------------------------------------------

# Part 14 --- Request Buffering

## 16. Client Memory

Before sending, the client may hold:

``` text
command objects
keys
values
serialized request data
```

Large values make large pipelines more expensive.

------------------------------------------------------------------------

# Part 15 --- Response Buffering

## 17. Server and Client Impact

Responses must also be buffered and transferred.

A pipeline of:

``` text
1,000 GET commands
```

for large values can generate a much larger payload than:

``` text
1,000 INCR commands
```

Pipeline size should account for bytes, not only command count.

------------------------------------------------------------------------

# Part 16 --- Byte-Based Limits

## 18. Better Guardrail

In addition to:

``` text
max commands
```

consider:

``` text
max estimated request bytes
max expected response bytes
```

where the application can estimate them.

------------------------------------------------------------------------

# Part 17 --- Big Values

## 19. Interaction

Chapter 18 applies directly.

A pipeline containing many big-value reads can create:

``` text
network spikes
client memory spikes
serialization pressure
GC pressure
```

Do not tune pipelines using only tiny synthetic values.

------------------------------------------------------------------------

# Part 18 --- Hot Keys

## 20. Pipeline Does Not Fix Skew

If every command targets:

``` text
one hot key
```

pipelining reduces round trips but does not distribute the underlying
key workload.

A hot key remains hot.

------------------------------------------------------------------------

# Part 19 --- Shard Distribution

## 21. Multi-Key Workload

A batch across many independent keys may distribute across shards
depending on topology and key placement.

Measure:

``` text
per-shard ops/sec
CPU
network
latency
```

Do not rely only on cluster-wide averages.

------------------------------------------------------------------------

# Part 20 --- Cluster-Aware Clients

## 22. Routing

In sharded deployments, clients may need to group/reroute commands by
target node/shard.

Exact pipeline behavior depends on:

``` text
Redis mode
Redis Enterprise topology
client library
client version
```

Validate with the deployed architecture.

------------------------------------------------------------------------

# Part 21 --- Hash Tags

## 23. Caution

Hash tags can intentionally co-locate related keys.

But putting large batched workloads under one tag can create:

``` text
hot slot
hot shard
```

Use co-location only when semantics require it.

------------------------------------------------------------------------

# Part 22 --- Error Handling

## 24. One Command Can Fail

Example batch:

``` text
SET key1 value
INCR key2
GET key3
```

If `key2` has an incompatible data type, that command can fail while
other commands may have executed.

Do not treat a pipeline as all-or-nothing.

------------------------------------------------------------------------

# Part 23 --- Per-Command Results

## 25. Inspect Results

The application must understand how its client library returns:

``` text
success values
errors
exceptions
```

for pipelined commands.

Test this before production.

------------------------------------------------------------------------

# Part 24 --- Partial Success

## 26. Business Meaning

Suppose:

``` text
command 1 succeeds
command 2 succeeds
connection fails
client does not receive all responses
```

The application may not know the final execution state of every command.

This matters for retries.

------------------------------------------------------------------------

# Part 25 --- Retry Ambiguity

## 27. Dangerous Pattern

Do not automatically retry an entire write pipeline when:

``` text
some commands may already have executed
```

unless duplicate execution is safe.

------------------------------------------------------------------------

# Part 26 --- Idempotent Batch Design

## 28. Prefer Safe Semantics

Where retries are possible, favor operations that are:

``` text
idempotent
version-checked
deduplicated
```

when business semantics permit.

------------------------------------------------------------------------

# Part 27 --- Chunking

## 29. Bound Failure Scope

Instead of:

``` text
100,000-command pipeline
```

use bounded chunks such as:

``` text
100
500
1,000
```

based on measured behavior.

This limits:

``` text
memory
latency
failure scope
recovery complexity
```

------------------------------------------------------------------------

# Part 28 --- Backpressure

## 30. Producer Faster Than Redis

If work arrives faster than batches can drain:

``` text
queue grows
memory grows
latency grows
```

Bound:

``` text
queue size
in-flight batches
producer concurrency
```

------------------------------------------------------------------------

# Part 29 --- In-Flight Pipeline Limit

## 31. Application Guardrail

Do not allow unlimited batches to execute concurrently.

Example:

``` text
max 4 in-flight pipelines
```

should be derived from:

``` text
connection pool
Redis capacity
batch size
latency objective
```

------------------------------------------------------------------------

# Part 30 --- Connection Pool Interaction

## 32. Pipelines Hold Connections

A pipeline uses connection capacity.

Many concurrent pipelines can exhaust the pool.

Chapter 26 pool sizing and backpressure remain relevant.

------------------------------------------------------------------------

# Part 31 --- Long Pipeline and Pool Wait

## 33. Mechanism

``` text
large pipeline
 -> connection busy longer
 -> fewer free connections
 -> pool wait increases
```

A throughput optimization can therefore worsen unrelated request
latency.

------------------------------------------------------------------------

# Part 32 --- Workload Isolation

## 34. Separate Bulk From Latency-Sensitive Traffic

If one application performs:

``` text
interactive GET/SET
+
large bulk pipelines
```

consider workload isolation through:

``` text
separate pools
separate concurrency limits
separate services/workers
```

as appropriate.

------------------------------------------------------------------------

# Part 33 --- Pipeline Ordering

## 35. Result Order

Client libraries normally map responses to command order.

Do not assume this means the operations form a transaction.

Ordering of replies is not equivalent to all-or-nothing semantics.

------------------------------------------------------------------------

# Part 34 --- Dependencies Inside a Pipeline

## 36. Client Cannot Use Unknown Earlier Result

If command B depends on the returned value of command A and the client
must compute B:

``` text
A -> receive result -> compute B
```

a single static pipeline may not remove that dependency.

Lua or another atomic/server-side design may be appropriate for small
bounded logic.

------------------------------------------------------------------------

# Part 35 --- MGET / MSET vs. Pipeline

## 37. Built-In Multi-Key Commands

Where semantics and topology permit, built-in commands such as:

``` redis
MGET
MSET
```

may be simpler than many individual commands.

But consider:

``` text
key placement
payload size
atomic semantics
failure behavior
```

Do not replace every pipeline mechanically.

------------------------------------------------------------------------

# Part 36 --- Pipeline and Serialization

## 38. Application Cost

At high throughput, client CPU can be spent on:

``` text
encoding
decoding
JSON
compression
object allocation
```

Measure end-to-end throughput, not only Redis command time.

------------------------------------------------------------------------

# Part 37 --- Network Capacity

## 39. Throughput Limit

Pipelining can increase the rate at which data reaches network limits.

Estimate:

``` text
operations/sec
×
average request bytes
+
average response bytes
```

Network may become the bottleneck before Redis CPU.

------------------------------------------------------------------------

# Part 38 --- Redis CPU

## 40. Faster Arrival

Reducing round-trip delay can increase command arrival rate.

Redis CPU may rise because the client is finally able to feed Redis
faster.

This can be expected.

Validate headroom.

------------------------------------------------------------------------

# Part 39 --- Benchmarking Principle

## 41. Compare Multiple Batch Sizes

Test:

``` text
1
10
50
100
250
500
1,000
```

or a workload-appropriate range.

Record:

``` text
throughput
P50
P95
P99
client CPU
client memory
Redis CPU
network
errors
```

------------------------------------------------------------------------

# Part 40 --- Representative Payloads

## 42. Avoid Tiny-Only Tests

Benchmark:

``` text
real key lengths
real value sizes
real read/write ratio
real key distribution
real concurrency
```

A benchmark with 10-byte values may not predict production behavior with
500 KB values.

------------------------------------------------------------------------

# Part 41 --- Warm-Up

## 43. Stable Measurement

Before recording steady-state results:

``` text
warm connections
warm runtime/JIT where relevant
populate representative data
stabilize load
```

Separate startup effects from steady state.

------------------------------------------------------------------------

# Part 42 --- Benchmark Duration

## 44. Long Enough to See Tail Behavior

A five-second test may miss:

``` text
GC
network variation
background Redis work
pool contention
memory growth
```

Use a duration appropriate for the production question.

------------------------------------------------------------------------

# Part 43 --- Observability

## 45. Application Metrics

Track:

``` text
pipeline_total
pipeline_commands_total
pipeline_errors_total
pipeline_duration_seconds
pipeline_size_commands
pipeline_request_bytes
pipeline_response_bytes
```

where practical.

------------------------------------------------------------------------

## 46. Queue Metrics

Track:

``` text
batch_queue_depth
batch_wait_seconds
inflight_pipelines
batch_flush_size
batch_flush_reason
```

Possible flush reasons:

``` text
size
age
shutdown
manual
```

------------------------------------------------------------------------

## 47. Client Metrics

Correlate:

``` text
pool wait
connections in use
timeouts
retries
client CPU
client memory
```

------------------------------------------------------------------------

## 48. Redis Metrics

Correlate:

``` text
ops/sec
CPU
network
latency
connected clients
per-shard utilization
```

------------------------------------------------------------------------

# Part 44 --- Hands-On Lab

## 49. Objectives

You will:

1.  benchmark sequential commands;
2.  benchmark pipeline sizes;
3.  measure throughput;
4.  measure per-batch latency;
5.  test large responses;
6.  inject command errors;
7.  inspect partial results;
8.  test concurrent pipelines;
9.  test backpressure;
10. compare pipeline with MGET;
11. simulate connection failure;
12. clean up safely.

------------------------------------------------------------------------

## 50. Prerequisites

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

# Part 45 --- Benchmark Script

## 51. Create `chapter27_pipeline_lab.py`

``` python
import os
import statistics
import time

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

PREFIX = "tutorial:chapter27:item"


def percentile(values, p):
    if not values:
        return 0.0

    ordered = sorted(values)

    index = int(
        round(
            (p / 100)
            * (len(ordered) - 1)
        )
    )

    return ordered[index]


def cleanup(count):
    pipe = r.pipeline(
        transaction=False
    )

    pending = 0

    for i in range(count):
        pipe.unlink(
            f"{PREFIX}:{i}"
        )

        pending += 1

        if pending >= 500:
            pipe.execute()
            pipe = r.pipeline(
                transaction=False
            )
            pending = 0

    if pending:
        pipe.execute()


def sequential_set(count):
    start = time.perf_counter()

    for i in range(count):
        r.set(
            f"{PREFIX}:{i}",
            f"value-{i}",
        )

    elapsed = (
        time.perf_counter()
        - start
    )

    return elapsed


def pipelined_set(
    count,
    batch_size,
):
    batch_latencies = []

    start_all = time.perf_counter()

    for start_index in range(
        0,
        count,
        batch_size,
    ):
        pipe = r.pipeline(
            transaction=False
        )

        end_index = min(
            start_index + batch_size,
            count,
        )

        for i in range(
            start_index,
            end_index,
        ):
            pipe.set(
                f"{PREFIX}:{i}",
                f"value-{i}",
            )

        batch_start = time.perf_counter()

        pipe.execute()

        batch_latencies.append(
            time.perf_counter()
            - batch_start
        )

    elapsed = (
        time.perf_counter()
        - start_all
    )

    return (
        elapsed,
        batch_latencies,
    )


def report(
    label,
    count,
    elapsed,
    latencies=None,
):
    throughput = (
        count / elapsed
        if elapsed > 0
        else 0
    )

    print()
    print(label)
    print(
        "elapsed:",
        f"{elapsed:.4f}s",
    )
    print(
        "throughput:",
        f"{throughput:.0f} ops/sec",
    )

    if latencies:
        print(
            "batch p50:",
            f"{percentile(latencies, 50):.6f}s",
        )
        print(
            "batch p95:",
            f"{percentile(latencies, 95):.6f}s",
        )
        print(
            "batch p99:",
            f"{percentile(latencies, 99):.6f}s",
        )


if __name__ == "__main__":
    COUNT = 5000

    print(
        "PING:",
        r.ping(),
    )

    cleanup(COUNT)

    elapsed = sequential_set(
        COUNT
    )

    report(
        "SEQUENTIAL",
        COUNT,
        elapsed,
    )

    for batch_size in [
        10,
        50,
        100,
        250,
        500,
        1000,
    ]:
        cleanup(COUNT)

        elapsed, latencies = pipelined_set(
            COUNT,
            batch_size,
        )

        report(
            f"PIPELINE {batch_size}",
            COUNT,
            elapsed,
            latencies,
        )

    cleanup(COUNT)
```

------------------------------------------------------------------------

# Part 46 --- Run Benchmark

## 52. Execute

``` bash
python chapter27_pipeline_lab.py
```

Record results.

Do not assume the largest batch is best.

------------------------------------------------------------------------

# Part 47 --- Results Table

## 53. Template

  ------------------------------------------------------------------------------
  Batch size   Throughput  Batch P50  Batch P95  Batch P99     Client  Redis CPU
                                                               memory 
  ---------- ------------ ---------- ---------- ---------- ---------- ----------
           1                                                          

          10                                                          

          50                                                          

         100                                                          

         250                                                          

         500                                                          

        1000                                                          
  ------------------------------------------------------------------------------

Select a batch size based on the whole profile.

------------------------------------------------------------------------

# Part 48 --- Read Pipeline Lab

## 54. GET Batch

``` python
pipe = r.pipeline(
    transaction=False
)

for i in range(100):
    pipe.get(
        f"{PREFIX}:{i}"
    )

values = pipe.execute()

print(
    len(values),
)
```

Repeat with representative value sizes.

------------------------------------------------------------------------

# Part 49 --- Large-Value Lab

## 55. Disposable Test

Populate:

``` text
1 KB
10 KB
100 KB
```

values.

Compare pipeline sizes.

Measure:

``` text
response bytes
client memory
latency
network
```

Do not create large test payloads in shared production databases.

------------------------------------------------------------------------

# Part 50 --- Error Lab

## 56. Wrong Type

Create:

``` redis
SET tutorial:chapter27:error not-a-number
```

Pipeline:

``` python
pipe = r.pipeline(
    transaction=False
)

pipe.set(
    "tutorial:chapter27:ok",
    "value",
)

pipe.incr(
    "tutorial:chapter27:error"
)

pipe.get(
    "tutorial:chapter27:ok"
)
```

Execute according to the client mode/version and inspect how errors are
surfaced.

The key lesson:

``` text
one command error does not imply all previous commands were rolled back
```

------------------------------------------------------------------------

# Part 51 --- MGET Comparison

## 57. Built-In Multi-Key Read

For compatible topology:

``` python
keys = [
    f"{PREFIX}:{i}"
    for i in range(100)
]

values = r.mget(keys)
```

Compare with 100 pipelined `GET` commands.

Review:

``` text
performance
payload
cluster behavior
semantics
```

------------------------------------------------------------------------

# Part 52 --- Concurrent Pipeline Lab

## 58. Multiple Workers

Run several pipeline workers concurrently.

Measure:

``` text
throughput
pool usage
pool wait
Redis CPU
P99 latency
```

Increasing concurrency and batch size simultaneously can overload Redis.

Tune one dimension at a time.

------------------------------------------------------------------------

# Part 53 --- Backpressure Lab

## 59. Semaphore

Concept:

``` python
import threading

inflight = threading.Semaphore(4)

def run_batch(pipe):
    with inflight:
        return pipe.execute()
```

This caps concurrent in-flight batches.

------------------------------------------------------------------------

# Part 54 --- Time-Based Flush

## 60. Concept

Batcher:

``` text
flush if count >= 100
OR age >= 5 ms
```

Test low and high request rates.

Confirm low traffic does not wait indefinitely for a full batch.

------------------------------------------------------------------------

# Part 55 --- Failure Injection

## 61. Failure 1 --- Huge Pipeline

In a disposable environment, increase batch size far beyond the tested
optimum.

Observe:

``` text
batch latency
client memory
Redis/network behavior
```

Then return to bounded chunks.

------------------------------------------------------------------------

## 62. Failure 2 --- Large Response Pipeline

Pipeline many large `GET` operations.

Observe response buffering and memory.

------------------------------------------------------------------------

## 63. Failure 3 --- Command Error

Insert one wrong-type command into a batch.

Observe per-command error behavior.

Confirm earlier successful writes are not assumed rolled back.

------------------------------------------------------------------------

## 64. Failure 4 --- Connection Loss

In a disposable environment, interrupt connectivity during a write
pipeline.

Treat execution state as potentially ambiguous.

Do not blindly replay duplicate-sensitive writes.

------------------------------------------------------------------------

## 65. Failure 5 --- Pool Exhaustion

Run many long pipelines through a small pool.

Observe:

``` text
pool wait
timeouts
```

------------------------------------------------------------------------

## 66. Failure 6 --- No Backpressure

Generate batches faster than Redis can drain them.

Observe:

``` text
queue depth
memory
latency
```

Then bound the queue/in-flight pipelines.

------------------------------------------------------------------------

## 67. Failure 7 --- Hot Key

Pipeline thousands of operations against one key.

Observe that round-trip efficiency improves but workload skew remains.

------------------------------------------------------------------------

## 68. Failure 8 --- Hot Shard

Use key placement that concentrates a batch on one shard.

Compare with distributed keys.

Observe per-shard CPU and latency.

------------------------------------------------------------------------

## 69. Failure 9 --- Batch Fill Delay

Set a large batch threshold under low traffic.

Observe item wait time.

Add a maximum batch-age flush.

------------------------------------------------------------------------

## 70. Failure 10 --- Retry Whole Write Batch

Simulate ambiguous batch failure.

Demonstrate why replaying the entire write batch can duplicate
non-idempotent effects.

Redesign retry semantics.

------------------------------------------------------------------------

# Part 56 --- Troubleshooting

## 71. Throughput Did Not Improve

Check:

``` text
network RTT
batch size
pipeline actually enabled
client serialization
Redis CPU
network bandwidth
hot key
pool wait
```

Pipelining cannot remove every bottleneck.

------------------------------------------------------------------------

## 72. P99 Latency Increased

Check:

``` text
batch size
batch fill delay
in-flight pipelines
pool contention
large responses
Redis saturation
```

Reduce batch/concurrency if necessary.

------------------------------------------------------------------------

## 73. Client Memory Increased

Check:

``` text
pipeline size
value size
response size
queued batches
result retention
```

------------------------------------------------------------------------

## 74. Redis CPU Increased

Pipelining may be feeding Redis more efficiently.

Check whether throughput also increased and whether CPU headroom remains
acceptable.

------------------------------------------------------------------------

## 75. Network Saturated

Check:

``` text
payload size
read/write mix
large values
batch concurrency
```

Reducing round trips can expose bandwidth as the next bottleneck.

------------------------------------------------------------------------

## 76. Partial Errors

Inspect each result and classify:

``` text
command error
connection error
timeout
application decoding error
```

Do not collapse every failure into "pipeline failed."

------------------------------------------------------------------------

## 77. One Shard Saturated

Check:

``` text
key distribution
hash tags
hot keys
hot tenant
batch composition
```

Redis cluster-wide averages can hide shard skew.

------------------------------------------------------------------------

## 78. Pool Wait Increased

Large/concurrent pipelines may hold connections longer.

Review:

``` text
pipeline duration
pool size
in-flight batch count
interactive traffic
```

------------------------------------------------------------------------

# Part 57 --- Production Runbooks

## 79. Runbook --- Pipeline Latency Regression

``` text
1. Measure batch size.
2. Measure batch age.
3. Measure pipeline duration.
4. Check client memory.
5. Check pool wait.
6. Check Redis CPU/latency.
7. Check network.
8. Reduce batch/concurrency if needed.
9. Benchmark corrected sizes.
10. Confirm P99 recovers.
```

------------------------------------------------------------------------

## 80. Runbook --- Pipeline Memory Growth

``` text
1. Measure queued batches.
2. Measure in-flight batches.
3. Measure commands/batch.
4. Measure request/response bytes.
5. Check large values.
6. Bound queue depth.
7. Bound pipeline size.
8. Add backpressure.
9. Validate client GC/memory.
10. Confirm stable memory.
```

------------------------------------------------------------------------

## 81. Runbook --- Partial Batch Failure

``` text
1. Capture exact error.
2. Determine which responses were received.
3. Identify write operations.
4. Assume ambiguous commands may have executed.
5. Do not blindly replay duplicate-sensitive work.
6. Reconcile authoritative state.
7. Use idempotency/versioning where possible.
8. Retry only safe operations.
9. Add failure test.
10. Document recovery semantics.
```

------------------------------------------------------------------------

## 82. Runbook --- Hot-Shard Batch

``` text
1. Measure per-shard utilization.
2. Identify batch key distribution.
3. Check hash tags.
4. Check hot keys/tenants.
5. Preserve required atomic placement.
6. Redistribute independent keys where valid.
7. Reduce batch concurrency if needed.
8. Load-test distribution.
9. Monitor shard P99.
10. Document key-placement assumptions.
```

------------------------------------------------------------------------

## 83. Runbook --- Throughput Plateau

``` text
1. Benchmark multiple batch sizes.
2. Check Redis CPU.
3. Check network bandwidth.
4. Check client CPU.
5. Check serialization.
6. Check pool wait.
7. Check shard skew.
8. Check value sizes.
9. Identify actual bottleneck.
10. Stop increasing batch size once benefit plateaus.
```

------------------------------------------------------------------------

# Part 58 --- Pipeline Design Template

## 84. Fields

``` text
Service:
Workload:
Command types:
Read/write ratio:
Average key bytes:
Average value bytes:
Expected response bytes:
Batch size:
Max batch age:
Max request bytes:
Max response bytes:
Concurrent pipelines:
Connection pool:
Retry policy:
Idempotency:
Cluster/shard behavior:
Hash tags:
Expected ops/sec:
Expected network:
Expected client memory:
Metrics:
Owner:
```

------------------------------------------------------------------------

# Part 59 --- Benchmark Template

## 85. Record

``` text
Environment:
Client version:
Redis version:
Redis Enterprise version:
Topology:
Dataset:
Key distribution:
Value size:
Read/write ratio:
Concurrency:
Pool size:
Batch sizes tested:
Test duration:
Warm-up duration:
Throughput:
P50:
P95:
P99:
Client CPU:
Client memory:
Redis CPU:
Network:
Errors:
Selected batch:
Reason:
```

------------------------------------------------------------------------

# Part 60 --- Batch-Sizing Decision Guide

## 86. Increase Batch Size When

``` text
network round trips dominate
Redis has CPU/network headroom
client memory is stable
P99 remains acceptable
pool wait remains acceptable
```

------------------------------------------------------------------------

## 87. Reduce Batch Size When

``` text
P99 rises
memory rises
responses are large
pool wait rises
failure scope is too large
batch fill delay hurts latency
```

------------------------------------------------------------------------

# Production Acceptance Checklist

## 88. High-Throughput Command Engineering

-   [ ] Pipelining use case documented.
-   [ ] Pipeline vs. transaction distinction understood.
-   [ ] Non-transactional mode explicitly reviewed.
-   [ ] Multiple batch sizes benchmarked.
-   [ ] Throughput measured.
-   [ ] P50/P95/P99 measured.
-   [ ] Batch fill delay measured.
-   [ ] Maximum batch age defined where required.
-   [ ] Request buffering reviewed.
-   [ ] Response buffering reviewed.
-   [ ] Large-value behavior tested.
-   [ ] Client memory measured.
-   [ ] Redis CPU measured.
-   [ ] Network measured.
-   [ ] Per-command errors tested.
-   [ ] Partial-success semantics documented.
-   [ ] Ambiguous write retry behavior documented.
-   [ ] Pipeline size bounded.
-   [ ] In-flight pipeline count bounded.
-   [ ] Backpressure implemented.
-   [ ] Pool interaction tested.
-   [ ] Cluster/shard behavior tested.
-   [ ] Hot-key behavior tested.
-   [ ] Hot-shard behavior tested.
-   [ ] Production runbooks validated.

------------------------------------------------------------------------

# Knowledge Validation

## 89. Questions

You should be able to answer:

1.  Why can network round trips limit Redis throughput?
2.  What is Redis pipelining?
3.  Does a pipeline turn many commands into one Redis command?
4.  Is a normal pipeline atomic?
5.  How does pipelining differ from `MULTI/EXEC`?
6.  Why use `transaction=False` for a throughput-only redis-py pipeline?
7.  Why is there no universal best batch size?
8.  What are the benefits of small batches?
9.  What are the risks of very large batches?
10. What is batch fill delay?
11. Why use a maximum batch age?
12. Why do response bytes matter?
13. How do big values change pipeline behavior?
14. Does pipelining solve a hot-key problem?
15. Why must per-shard metrics be reviewed?
16. What can happen when one command in a pipeline errors?
17. Why is partial success important?
18. Why can retrying a write pipeline be dangerous?
19. Why should work be chunked?
20. What is client-side backpressure?
21. Why limit in-flight pipelines?
22. How can long pipelines cause pool wait?
23. Why isolate bulk and interactive workloads?
24. When can `MGET`/`MSET` be considered?
25. Why measure client serialization?
26. Why can Redis CPU rise after enabling pipelining?
27. Which benchmark metrics matter besides throughput?
28. Why use representative value sizes?
29. Why can a throughput optimization worsen P99 latency?
30. What must pass before pipeline settings are production-ready?

------------------------------------------------------------------------

# Hands-On Acceptance Checklist

## 90. Lab Completion

-   [ ] Benchmarked sequential commands.
-   [ ] Benchmarked multiple pipeline sizes.
-   [ ] Recorded throughput.
-   [ ] Recorded batch P50/P95/P99.
-   [ ] Tested read pipelines.
-   [ ] Tested representative large values.
-   [ ] Injected a command error.
-   [ ] Reviewed per-command results.
-   [ ] Compared `MGET` and pipelined `GET`.
-   [ ] Tested concurrent pipelines.
-   [ ] Added in-flight backpressure.
-   [ ] Reviewed time-based flush.
-   [ ] Tested huge-pipeline behavior.
-   [ ] Tested large-response behavior.
-   [ ] Reviewed ambiguous connection failure.
-   [ ] Tested pool exhaustion.
-   [ ] Tested no-backpressure behavior.
-   [ ] Tested hot-key behavior.
-   [ ] Tested hot-shard behavior.
-   [ ] Tested batch fill delay.
-   [ ] Reviewed unsafe whole-batch retry.
-   [ ] Completed ten failure scenarios.
-   [ ] Completed troubleshooting.
-   [ ] Reviewed five production runbooks.
-   [ ] Completed pipeline design template.
-   [ ] Completed benchmark template.
-   [ ] Completed production acceptance checklist.

------------------------------------------------------------------------

# 91. Lab Cleanup

Discover:

``` bash
redis-cli --scan --pattern 'tutorial:chapter27:*'
```

Delete only confirmed Chapter 27 training keys in bounded batches with
`UNLINK`.

Examples:

``` redis
UNLINK tutorial:chapter27:error
UNLINK tutorial:chapter27:ok
```

For generated item keys:

``` bash
redis-cli --scan --pattern 'tutorial:chapter27:item:*'
```

Delete discovered keys in bounded batches.

Do not use:

``` redis
KEYS tutorial:chapter27:*
FLUSHDB
FLUSHALL
```

against a shared or production database.

Do not run intentionally huge pipelines against shared or production
Redis to test limits.

------------------------------------------------------------------------

# 92. Key Takeaways

1.  Pipelining reduces network round trips and can significantly improve
    throughput.
2.  A pipeline contains multiple commands; it is not one Redis command.
3.  A normal pipeline is not automatically a transaction.
4.  Pipeline size must be measured rather than maximized blindly.
5.  Small batches reduce buffering and failure scope.
6.  Large batches may improve throughput but increase memory and
    latency.
7.  Maximum batch age prevents low-traffic requests from waiting
    indefinitely.
8.  Pipeline limits should consider bytes as well as command count.
9.  Large-value reads can make response buffering the dominant cost.
10. Pipelining does not solve hot-key or hot-shard skew.
11. Per-command errors and partial success must be handled explicitly.
12. A connection failure can make write execution state ambiguous.
13. Do not blindly replay duplicate-sensitive write pipelines.
14. Chunking bounds memory, latency, and recovery complexity.
15. Backpressure is required when producers can outrun Redis.
16. Concurrent pipelines consume connection-pool capacity.
17. Bulk pipeline workloads can interfere with latency-sensitive
    traffic.
18. Benchmark with representative keys, values, concurrency, and
    topology.
19. Select the smallest batch that provides the required throughput
    while preserving latency and capacity headroom.
20. Production readiness requires failure testing, per-shard visibility,
    bounded queues, safe retries, and runbooks.

------------------------------------------------------------------------

# 93. References

Validate exact pipeline, transaction, cluster-routing, error, and client
behavior against the Redis, Redis Enterprise, and client-library
versions deployed.

Recommended official documentation areas:

-   Redis pipelining
-   Redis transactions
-   `MULTI`
-   `EXEC`
-   `MGET`
-   `MSET`
-   Redis Cluster
-   Redis Cluster hash tags
-   Redis latency monitoring
-   Redis memory optimization
-   Redis Enterprise monitoring
-   redis-py pipelines
-   redis-py connection pools

Pipelining is primarily a network-efficiency technique. Production
tuning should optimize the full system: client memory, connection pools,
network, Redis CPU, shard distribution, tail latency, and failure
recovery---not only commands per second.

------------------------------------------------------------------------

# Next Chapter

**Chapter 28 --- Redis Serialization, Compression & Value-Size
Engineering**

Chapter 28 will cover:

-   serialization formats
-   JSON
-   binary formats
-   schema/version handling
-   serialization CPU
-   deserialization CPU
-   value-size measurement
-   compression tradeoffs
-   compression thresholds
-   network vs. CPU tradeoffs
-   big-value prevention
-   partial-field access
-   client memory
-   compatibility
-   observability
-   failure injection
-   troubleshooting
-   production runbooks
-   acceptance validation
