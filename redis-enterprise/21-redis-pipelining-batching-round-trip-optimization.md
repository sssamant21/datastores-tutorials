# Chapter 21 --- Redis Pipelining, Batching & Round-Trip Optimization

**Status:** Canonical\
**Track:** Redis Enterprise / Redis Software Production Engineering\
**Part:** Part 2 --- Caching & Application Engineering\
**Level:** Intermediate → Production Redis Performance Engineering\
**Audience:** Developers, SREs, DBREs, Platform Engineers, Redis
Administrators\
**Lab type:** Sequential-command baseline, pipelining, batching,
batch-size benchmarking, throughput/latency comparison, response-memory
analysis, backpressure, partial-failure handling, cluster-aware
batching, failure injection, observability, troubleshooting, runbooks,
and production acceptance

------------------------------------------------------------------------

# 1. Objective

Redis is fast, but applications can still be slow when they use Redis
inefficiently.

A common cause is excessive network round trips.

Consider:

``` text
application
   |
   | command 1
   v
 Redis
   |
   | response 1
   v
application
   |
   | command 2
   v
 Redis
```

If an application executes thousands of independent commands
sequentially, network round-trip latency can dominate total execution
time.

Pipelining allows multiple commands to be sent without waiting for each
individual response.

By the end, you should be able to:

-   Explain Redis round-trip cost.
-   Distinguish command execution time from network latency.
-   Explain pipelining.
-   Explain batching.
-   Compare sequential and pipelined workloads.
-   Choose safe pipeline sizes.
-   Understand throughput vs. latency tradeoffs.
-   Control client/server memory pressure.
-   Apply backpressure.
-   Handle partial command failures.
-   Distinguish pipelines from transactions.
-   Understand cluster/shard considerations.
-   Avoid oversized pipelines.
-   Benchmark realistically.
-   Observe pipeline behavior.
-   Troubleshoot pipeline-related incidents.
-   Build production runbooks and acceptance criteria.

------------------------------------------------------------------------

# 2. Core Production Principle

Do not optimize only Redis command execution.

Optimize:

``` text
application
+
network
+
client
+
Redis
+
response handling
```

A command taking microseconds on Redis can still contribute to poor
application latency if every operation requires a separate network round
trip.

------------------------------------------------------------------------

# Part 1 --- Round-Trip Time

## 3. RTT

Round-trip time is approximately:

``` text
client sends request
 -> network
 -> Redis processes request
 -> network
 -> client receives response
```

Even small RTT becomes expensive when repeated thousands of times
sequentially.

------------------------------------------------------------------------

## 4. Simple Example

Suppose:

``` text
RTT = 1 ms
commands = 1,000
```

Sequential execution can spend roughly:

``` text
1,000 × 1 ms = 1 second
```

in round-trip waiting alone, before considering command execution and
application overhead.

This is a simplified model, but it illustrates the problem.

------------------------------------------------------------------------

# Part 2 --- Sequential Execution

## 5. Pattern

``` python
for key in keys:
    redis.get(key)
```

This often becomes:

``` text
send
wait
receive

send
wait
receive

send
wait
receive
```

------------------------------------------------------------------------

# Part 3 --- Pipelining

## 6. Concept

Pipeline:

``` text
send command 1
send command 2
send command 3
send command 4
        |
        v
      Redis
        |
        v
receive responses
```

The client reduces repeated network waiting.

------------------------------------------------------------------------

# Part 4 --- What Pipelining Does Not Mean

## 7. Not Automatic Parallel Redis Execution

Pipelining primarily improves communication efficiency.

It does not mean that commands suddenly become independent parallel
transactions.

------------------------------------------------------------------------

## 8. Not a Transaction

Pipeline:

``` text
optimize request/response flow
```

Transaction:

``` text
MULTI
commands
EXEC
```

They solve different problems.

Some client libraries combine pipeline APIs with transactional behavior
by default, so always understand the client configuration.

------------------------------------------------------------------------

# Part 5 --- Batching

## 9. Definition

Batching means grouping work into bounded sets.

Example:

``` text
10,000 commands
```

might be processed as:

``` text
100 batches × 100 commands
```

rather than:

``` text
one pipeline × 10,000 commands
```

------------------------------------------------------------------------

# Part 6 --- Why Bounded Batches Matter

## 10. Resource Control

Very large pipelines can increase:

``` text
client memory
queued request memory
response memory
Redis output buffering
failure blast radius
latency before results are processed
```

Use bounded pipelines.

------------------------------------------------------------------------

# Part 7 --- Pipeline Size

## 11. No Universal Number

There is no universally correct:

``` text
pipeline size = 100
```

or:

``` text
pipeline size = 1000
```

The correct size depends on:

``` text
RTT
command type
payload size
response size
Redis capacity
client memory
network bandwidth
latency objective
cluster topology
```

------------------------------------------------------------------------

# Part 8 --- Throughput vs. Latency

## 12. Throughput

Pipelining often increases:

``` text
operations/sec
```

by reducing round-trip overhead.

------------------------------------------------------------------------

## 13. Per-Batch Latency

Larger batches may increase the time before the application receives and
processes a particular batch's results.

Therefore:

``` text
maximum throughput
```

and:

``` text
minimum request latency
```

are not always the same optimization target.

------------------------------------------------------------------------

# Part 9 --- Small Commands

## 14. High Benefit Potential

Pipelining can be especially valuable when commands are:

``` text
small
fast
numerous
independent
```

because network overhead may dominate command execution.

------------------------------------------------------------------------

# Part 10 --- Large Payloads

## 15. Response Size Matters

A pipeline of:

``` text
1,000 GETs × 1 MB
```

can imply approximately:

``` text
1 GB payload
```

before protocol/client overhead.

Do not select pipeline size based only on command count.

------------------------------------------------------------------------

# Part 11 --- Command Cost

## 16. Pipelining Does Not Make Expensive Commands Cheap

If each command is expensive:

``` text
pipeline
```

reduces network waits but does not eliminate Redis CPU/work.

Use command complexity and workload design principles from earlier
chapters.

------------------------------------------------------------------------

# Part 12 --- Hot Keys

## 17. Pipeline Can Amplify Hot-Key Load

Sending thousands of operations against one hot key faster can worsen
concentration.

Pipelining is not a hot-key mitigation.

Chapter 18's workload-skew controls still apply.

------------------------------------------------------------------------

# Part 13 --- Memory Pressure

## 18. Write Pipelines

Large write pipelines can rapidly create:

``` text
memory growth
evictions
replication traffic
persistence work
network bursts
```

Chapter 17 memory-pressure engineering remains relevant.

------------------------------------------------------------------------

# Part 14 --- Source/Cache Population

## 19. Bulk Cache Fill

Pipelines are useful for controlled cache population:

``` text
source records
 -> bounded batch
 -> Redis pipeline
```

But Chapter 16 warming rules still apply:

``` text
source-aware rate
TTL jitter
priority
backpressure
```

------------------------------------------------------------------------

# Part 15 --- TTL Population

## 20. Avoid Synchronized Expiration

A bulk pipeline that writes thousands of keys with identical TTL can
create a future expiration storm.

Use Chapter 19 TTL engineering:

``` text
base TTL
+
appropriate jitter
```

------------------------------------------------------------------------

# Part 16 --- Backpressure

## 21. Definition

Backpressure prevents producers from creating work faster than
Redis/client/network can safely process it.

Without backpressure:

``` text
producer
 -> unlimited queued batches
 -> memory growth
 -> latency
 -> timeouts
 -> retries
```

------------------------------------------------------------------------

# Part 17 --- Bounded Concurrency

## 22. Control In-Flight Pipelines

Instead of:

``` text
launch unlimited pipeline tasks
```

use:

``` text
bounded workers
bounded batch size
bounded queue
```

This keeps resource usage predictable.

------------------------------------------------------------------------

# Part 18 --- Retry Amplification

## 23. Failed Batch

If a batch fails and the application retries all commands blindly:

``` text
original workload
+
retry workload
```

can amplify pressure.

Retry policy must consider whether commands are:

``` text
idempotent
partially applied
safe to repeat
```

------------------------------------------------------------------------

# Part 19 --- Partial Failures

## 24. Command-Level Errors

A pipeline can contain many commands.

A failure associated with one command does not mean that every other
command necessarily had the same outcome.

Client-library behavior must be understood.

------------------------------------------------------------------------

## 25. Network Failure Ambiguity

If the connection breaks after sending commands but before all responses
are received, the client may not know exactly which commands executed.

This matters greatly for non-idempotent operations.

------------------------------------------------------------------------

# Part 20 --- Idempotency

## 26. Safer Retry

Commands like:

``` redis
SET key exact-value
```

may be easier to retry safely than operations whose repeated execution
changes state again.

Example:

``` redis
INCR counter
```

Blind retry after an ambiguous network failure can increment twice.

------------------------------------------------------------------------

# Part 21 --- Pipeline and Transactions

## 27. Pipeline Goal

``` text
reduce communication overhead
```

------------------------------------------------------------------------

## 28. Transaction Goal

``` text
queue commands
execute through MULTI/EXEC semantics
```

Transactions are covered separately in a later chapter.

Do not use transactions merely because you want fewer round trips.

------------------------------------------------------------------------

# Part 22 --- redis-py Behavior

## 29. Important Default

In redis-py, `pipeline()` commonly uses transactional behavior by
default.

For pure non-transactional pipelining:

``` python
pipe = r.pipeline(transaction=False)
```

Use the behavior that matches the requirement.

------------------------------------------------------------------------

# Part 23 --- Redis Cluster / Sharded Topology

## 30. Key Placement Matters

In sharded Redis deployments, keys belong to different shards/slots.

Client behavior for pipelined commands across shards depends on:

``` text
client library
cluster support
routing
connection management
```

Validate the production client.

------------------------------------------------------------------------

## 31. Multi-Key Atomicity Is Different

Pipelining commands to multiple keys does not make those commands atomic
across shards.

Do not confuse:

``` text
efficient transport
```

with:

``` text
cross-key atomic consistency
```

------------------------------------------------------------------------

# Part 24 --- Hash Tags

## 32. Cluster Placement

Where Redis Cluster-style hash tags are applicable:

``` text
user:{1001}:profile
user:{1001}:settings
```

can influence slot placement.

Use intentionally for operations that require compatible placement.

Do not concentrate unrelated workload onto one slot merely for
convenience.

------------------------------------------------------------------------

# Part 25 --- Connection Pools

## 33. Client Connections

Pipeline behavior interacts with connection pools.

Monitor:

``` text
active connections
pool wait
timeouts
connection churn
```

A pipeline does not compensate for a badly configured connection
strategy.

------------------------------------------------------------------------

# Part 26 --- Network Bandwidth

## 34. Faster Command Submission Can Expose Network Limits

After pipelining:

``` text
Redis CPU may remain healthy
network may become bottleneck
```

Measure:

``` text
bytes/sec
packet behavior
client throughput
response sizes
```

------------------------------------------------------------------------

# Part 27 --- Client CPU

## 35. Response Processing

A large pipeline can return many responses at once.

Client work may include:

``` text
parsing
deserialization
object allocation
business processing
```

Measure client CPU and memory, not only Redis.

------------------------------------------------------------------------

# Part 28 --- Observability

## 36. Application Metrics

Track:

``` text
redis_pipeline_total
redis_pipeline_commands
redis_pipeline_batch_size
redis_pipeline_duration_seconds
redis_pipeline_errors_total
redis_pipeline_retries_total
redis_pipeline_response_bytes
```

------------------------------------------------------------------------

## 37. Redis Metrics

Correlate:

``` text
operations/sec
latency
CPU
network
connections
memory
evictions
errors
```

with pipeline deployment.

------------------------------------------------------------------------

## 38. Batch Histograms

Prefer histograms/distributions for:

``` text
batch size
batch latency
response bytes
```

rather than only averages.

------------------------------------------------------------------------

# Part 29 --- Benchmark Design

## 39. Compare Like With Like

Benchmark:

``` text
same commands
same keys
same payloads
same client
same network
same Redis instance
```

Change only the batching strategy when evaluating pipeline benefit.

------------------------------------------------------------------------

# Part 30 --- Warm-Up

## 40. Avoid First-Run Bias

Before measuring:

``` text
establish connections
warm runtime/client
prepare data
```

Record multiple runs.

------------------------------------------------------------------------

# Part 31 --- Percentiles

## 41. Do Not Report Only Average

Measure:

``` text
P50
P95
P99
throughput
error rate
```

A larger pipeline may improve throughput while worsening tail latency.

------------------------------------------------------------------------

# Part 32 --- Hands-On Lab

## 42. Objectives

You will:

1.  create test data;
2.  measure sequential GETs;
3.  measure pipelined GETs;
4.  compare multiple batch sizes;
5.  measure write pipelines;
6.  test large responses;
7.  observe partial errors;
8.  test retry semantics;
9.  simulate backpressure;
10. clean up safely.

------------------------------------------------------------------------

## 43. Prerequisites

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

# Part 33 --- Benchmark Script

## 44. Create `chapter21_pipeline_lab.py`

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
    decode_responses=False,
)

PREFIX = "tutorial:chapter21:item:"
COUNT = 5000
VALUE = b"x" * 1024


def populate():
    pipe = r.pipeline(transaction=False)

    for i in range(COUNT):
        pipe.set(
            f"{PREFIX}{i}",
            VALUE,
            ex=900,
        )

        if i % 100 == 99:
            pipe.execute()

    pipe.execute()


def sequential_get():
    start = time.perf_counter()

    for i in range(COUNT):
        r.get(f"{PREFIX}{i}")

    return time.perf_counter() - start


def pipelined_get(batch_size):
    durations = []
    total_start = time.perf_counter()

    for start_index in range(0, COUNT, batch_size):
        batch_start = time.perf_counter()

        pipe = r.pipeline(transaction=False)

        end_index = min(
            start_index + batch_size,
            COUNT,
        )

        for i in range(start_index, end_index):
            pipe.get(f"{PREFIX}{i}")

        responses = pipe.execute()

        assert len(responses) == end_index - start_index

        durations.append(
            time.perf_counter() - batch_start
        )

    total = time.perf_counter() - total_start

    return total, durations


def percentile(values, pct):
    ordered = sorted(values)

    if not ordered:
        return 0

    index = int((len(ordered) - 1) * pct)
    return ordered[index]


if __name__ == "__main__":
    print("PING:", r.ping())

    populate()

    sequential = sequential_get()

    print()
    print("Sequential seconds:", round(sequential, 4))
    print(
        "Sequential ops/sec:",
        round(COUNT / sequential, 2),
    )

    for batch_size in [10, 50, 100, 500, 1000]:
        total, durations = pipelined_get(batch_size)

        print()
        print("Batch size:", batch_size)
        print("Total sec :", round(total, 4))
        print("Ops/sec   :", round(COUNT / total, 2))
        print(
            "Batch P50 :",
            round(statistics.median(durations), 6),
        )
        print(
            "Batch P95 :",
            round(percentile(durations, 0.95), 6),
        )
        print(
            "Batch max :",
            round(max(durations), 6),
        )
```

------------------------------------------------------------------------

# Part 34 --- Run Benchmark

## 45. Execute

``` bash
python chapter21_pipeline_lab.py
```

Expected pattern:

``` text
Sequential seconds: ...
Sequential ops/sec: ...

Batch size: 10
Ops/sec: ...

Batch size: 100
Ops/sec: ...

Batch size: 1000
Ops/sec: ...
```

Do not expect the largest batch to always be the best production choice.

------------------------------------------------------------------------

# Part 35 --- Interpret Results

## 46. Compare

Create a table:

``` text
batch size | total time | ops/sec | batch P95
-----------+------------+---------+----------
1          | ...        | ...     | ...
10         | ...        | ...     | ...
50         | ...        | ...     | ...
100        | ...        | ...     | ...
500        | ...        | ...     | ...
1000       | ...        | ...     | ...
```

Select the smallest batch size that achieves required throughput while
preserving latency and resource headroom.

------------------------------------------------------------------------

# Part 36 --- Write Pipeline Lab

## 47. Controlled Writes

``` python
def pipelined_write(batch_size, count=5000):
    start = time.perf_counter()

    for start_index in range(0, count, batch_size):
        pipe = r.pipeline(transaction=False)

        end_index = min(
            start_index + batch_size,
            count,
        )

        for i in range(start_index, end_index):
            pipe.set(
                f"tutorial:chapter21:write:{i}",
                b"value",
                ex=900 + (i % 60),
            )

        pipe.execute()

    return time.perf_counter() - start
```

The varying TTL avoids giving every training key exactly the same future
expiration.

------------------------------------------------------------------------

# Part 37 --- Large-Response Lab

## 48. Create Larger Values

On the isolated lab:

``` python
BIG_VALUE = b"B" * (256 * 1024)
```

Populate a small number of big values.

Compare:

``` text
10 GET pipeline
100 GET pipeline
500 GET pipeline
```

Monitor client memory and network.

Do not create an unsafe payload burst on shared systems.

------------------------------------------------------------------------

# Part 38 --- Response Budget

## 49. Estimate Before Sending

Approximate:

``` text
batch response bytes
≈
number of commands × average response bytes
```

Example:

``` text
500 × 256 KiB
≈ 125 MiB
```

That is a very different pipeline from:

``` text
500 × 100-byte responses
```

------------------------------------------------------------------------

# Part 39 --- Partial Error Lab

## 50. Mixed Commands

In an isolated namespace, create a key as a string and issue a command
requiring another data type in the same pipeline.

Example concept:

``` python
pipe = r.pipeline(transaction=False)
pipe.get("tutorial:chapter21:type-test")
pipe.lpush("tutorial:chapter21:type-test", "x")
pipe.get("tutorial:chapter21:item:1")

try:
    responses = pipe.execute(raise_on_error=False)
    print(responses)
except Exception as exc:
    print(repr(exc))
```

Inspect each response.

Client-library behavior can differ; validate the version in use.

------------------------------------------------------------------------

# Part 40 --- Retry Safety Lab

## 51. Compare Operations

Idempotent-style replacement:

``` redis
SET tutorial:chapter21:state ready
```

State-changing operation:

``` redis
INCR tutorial:chapter21:counter
```

Discuss what happens if the client sends the command but loses the
response.

The application may not know whether the operation executed.

------------------------------------------------------------------------

# Part 41 --- Backpressure Lab

## 52. Bounded Queue Concept

Use:

``` text
producer
 -> bounded queue
 -> N workers
 -> bounded pipeline
```

not:

``` text
producer
 -> unlimited tasks
 -> unlimited pipelines
```

------------------------------------------------------------------------

## 53. Python Skeleton

``` python
from queue import Queue
from threading import Thread

WORKERS = 4
QUEUE_SIZE = 20
BATCH_SIZE = 100

queue = Queue(maxsize=QUEUE_SIZE)


def worker():
    while True:
        batch = queue.get()

        if batch is None:
            queue.task_done()
            return

        try:
            pipe = r.pipeline(transaction=False)

            for key, value in batch:
                pipe.set(key, value, ex=900)

            pipe.execute()
        finally:
            queue.task_done()


threads = []

for _ in range(WORKERS):
    t = Thread(target=worker)
    t.start()
    threads.append(t)
```

This demonstrates bounded in-flight work.

Production code needs error handling, retry policy, shutdown handling,
metrics, and timeouts.

------------------------------------------------------------------------

# Part 42 --- Cluster-Aware Lab Review

## 54. Questions

Before enabling large pipelines in a sharded environment:

``` text
Does the client support cluster-aware pipelines?
How are commands grouped by shard?
How many connections are used?
How are redirects handled?
What happens on topology change?
How are partial failures returned?
```

Test with the exact production client/version.

------------------------------------------------------------------------

# Part 43 --- Failure Injection

## 55. Failure 1 --- Oversized Batch

Increase pipeline size dramatically.

Observe:

``` text
client memory
batch latency
network burst
response processing time
```

------------------------------------------------------------------------

## 56. Failure 2 --- Large Responses

Pipeline many large `GET` responses.

Observe:

``` text
network
client RSS
deserialization
latency
```

------------------------------------------------------------------------

## 57. Failure 3 --- Redis Latency

Introduce controlled Redis-side delay/load in a disposable test
environment.

Observe queued pipeline duration.

Do not inject unsafe load into production.

------------------------------------------------------------------------

## 58. Failure 4 --- Connection Failure

Interrupt the client connection during a write pipeline in an isolated
environment.

Determine which operations are safe to retry.

------------------------------------------------------------------------

## 59. Failure 5 --- Command Error

Include a wrong-type command.

Verify that the application inspects command-level results rather than
assuming whole-batch success.

------------------------------------------------------------------------

## 60. Failure 6 --- Retry Storm

Force repeated batch failures and use immediate retries.

Observe amplification.

Then add:

``` text
bounded retry
exponential backoff
jitter
```

------------------------------------------------------------------------

## 61. Failure 7 --- Unbounded Producer

Generate batches faster than workers can execute them.

Observe queue/memory growth.

Then enforce a bounded queue.

------------------------------------------------------------------------

## 62. Failure 8 --- Hot-Key Pipeline

Send most pipeline operations to one hot key.

Observe that pipelining improves submission efficiency but does not
solve key concentration.

------------------------------------------------------------------------

## 63. Failure 9 --- Bulk Write Memory Pressure

Pipeline cache population into a constrained lab instance.

Observe:

``` text
used memory
evictions
write rate
```

Apply Chapter 17 controls.

------------------------------------------------------------------------

## 64. Failure 10 --- Synchronized TTL

Write many keys through pipelines with identical TTL.

Observe the future expiration concentration.

Repeat with Chapter 19 TTL jitter.

------------------------------------------------------------------------

# Part 44 --- Troubleshooting

## 65. Pipeline Slower Than Expected

Check:

``` text
RTT
batch size
command cost
payload size
Redis CPU
network
client CPU
connection pool
serialization
```

------------------------------------------------------------------------

## 66. Throughput High but P99 Worse

Likely tradeoff:

``` text
larger batches
 -> more throughput
 -> longer batch completion
```

Reduce batch size or concurrency and remeasure.

------------------------------------------------------------------------

## 67. Client Memory High

Check:

``` text
pipeline size
response size
concurrent pipelines
queued batches
deserialization
```

------------------------------------------------------------------------

## 68. Redis CPU High After Pipeline Deployment

Pipelining may have removed the network bottleneck and exposed Redis
processing capacity.

Check:

``` text
ops/sec increase
command mix
hot keys
expensive commands
```

------------------------------------------------------------------------

## 69. Network Saturated

Check:

``` text
response bytes
large GETs
pipeline concurrency
client count
```

Do not solve network saturation by increasing pipeline size.

------------------------------------------------------------------------

## 70. Partial Batch Errors

Inspect:

``` text
individual responses
command type
key type
timeouts
connection state
client behavior
```

------------------------------------------------------------------------

## 71. Duplicate Writes After Retry

Investigate ambiguous completion of non-idempotent operations.

Do not blindly retry `INCR`-like operations after uncertain network
failure without a correctness strategy.

------------------------------------------------------------------------

## 72. Cluster Pipeline Problems

Check:

``` text
client cluster support
slot routing
topology refresh
redirect handling
cross-slot assumptions
per-shard latency
```

------------------------------------------------------------------------

# Part 45 --- Production Runbooks

## 73. Runbook --- Pipeline Latency Regression

``` text
1. Compare before/after batch size.
2. Measure pipeline P50/P95/P99.
3. Measure operations/sec.
4. Measure response bytes.
5. Check Redis CPU.
6. Check network.
7. Check client CPU/memory.
8. Check concurrent pipelines.
9. Reduce batch/concurrency if needed.
10. Rebenchmark.
```

------------------------------------------------------------------------

## 74. Runbook --- Client Memory Growth

``` text
1. Measure process RSS/heap.
2. Measure batch size.
3. Measure average response size.
4. Count concurrent pipelines.
5. Check producer queue.
6. Bound queue.
7. Bound concurrency.
8. Reduce response/batch size.
9. Validate GC/runtime behavior.
10. Confirm memory stabilizes.
```

------------------------------------------------------------------------

## 75. Runbook --- Pipeline Error Spike

``` text
1. Capture exact errors.
2. Determine command-level vs. connection-level failure.
3. Identify affected batch.
4. Classify commands as idempotent/non-idempotent.
5. Stop blind retries.
6. Apply bounded retry only where safe.
7. Check Redis/network health.
8. Validate client behavior.
9. Replay safely if required.
10. Confirm error rate recovers.
```

------------------------------------------------------------------------

## 76. Runbook --- Redis Saturation After Optimization

``` text
1. Confirm ops/sec increased.
2. Check Redis CPU.
3. Check shard distribution.
4. Check hot keys.
5. Check command mix.
6. Check write/memory pressure.
7. Reduce client concurrency if required.
8. Optimize workload.
9. Scale only after skew/workload review.
10. Revalidate latency and headroom.
```

------------------------------------------------------------------------

## 77. Runbook --- Cluster Pipeline Failure

``` text
1. Identify client/version.
2. Check topology state.
3. Check slot routing.
4. Check redirects/errors.
5. Identify affected shards.
6. Check per-shard latency.
7. Verify cross-slot assumptions.
8. Reduce batch blast radius.
9. Recover/retry only safe commands.
10. Validate topology-aware behavior.
```

------------------------------------------------------------------------

# Part 46 --- Pipeline Design Template

## 78. Fields

``` text
Service:
Redis database:
Client library/version:
Cluster-aware client?:
Operation:
Read/write/mixed:
Average command payload:
Average response size:
P95 response size:
Sequential RTT:
Current batch size:
Target batch size:
Concurrent pipelines:
Queue bound:
Timeout:
Retry policy:
Idempotent?:
Expected ops/sec:
Latency target:
Redis CPU headroom:
Network headroom:
Client memory headroom:
Owner:
```

------------------------------------------------------------------------

# Part 47 --- Benchmark Record

## 79. Template

``` text
Environment:
Date:
Client:
Redis version:
Topology:
Network location:
Dataset:
Command:
Payload size:
Response size:

Batch | Concurrency | Ops/sec | P50 | P95 | P99 | Errors | Client RSS
------|-------------|---------|-----|-----|-----|--------|-----------
1     | ...         | ...     | ... | ... | ... | ...    | ...
10    | ...         | ...     | ... | ... | ... | ...    | ...
50    | ...         | ...     | ... | ... | ... | ...    | ...
100   | ...         | ...     | ... | ... | ... | ...    | ...
500   | ...         | ...     | ... | ... | ... | ...    | ...
```

Record Redis CPU/network alongside this table.

------------------------------------------------------------------------

# Production Acceptance Checklist

## 80. Pipeline Engineering

-   [ ] Sequential baseline measured.
-   [ ] RTT understood.
-   [ ] Production client/version documented.
-   [ ] Transactional vs. non-transactional pipeline behavior verified.
-   [ ] Batch-size benchmark completed.
-   [ ] P50/P95/P99 measured.
-   [ ] Response-size distribution measured.
-   [ ] Client memory measured.
-   [ ] Redis CPU measured.
-   [ ] Network throughput measured.
-   [ ] Pipeline concurrency bounded.
-   [ ] Producer queue bounded.
-   [ ] Backpressure tested.
-   [ ] Command-level error handling tested.
-   [ ] Connection-failure ambiguity tested.
-   [ ] Retry safety documented.
-   [ ] Non-idempotent operations identified.
-   [ ] Cluster-aware behavior tested where applicable.
-   [ ] Hot-key impact reviewed.
-   [ ] Memory-pressure impact reviewed.
-   [ ] TTL distribution reviewed for bulk writes.
-   [ ] Production runbooks validated.

------------------------------------------------------------------------

# Knowledge Validation

## 81. Questions

You should be able to answer:

1.  What is Redis round-trip time?
2.  Why can sequential commands be slow even when Redis commands are
    fast?
3.  What is pipelining?
4.  What is batching?
5.  Why use bounded batches?
6.  Why is there no universal optimal pipeline size?
7.  How can pipeline size affect throughput?
8.  How can pipeline size affect latency?
9.  Why does response size matter?
10. Does pipelining make expensive commands cheap?
11. Does pipelining solve hot keys?
12. How can write pipelines increase memory pressure?
13. Why should bulk pipeline writes use TTL jitter?
14. What is backpressure?
15. Why bound in-flight pipelines?
16. What is retry amplification?
17. What is a partial pipeline failure?
18. Why can connection failure create ambiguous completion?
19. Why is idempotency important?
20. Why is `INCR` risky to blindly retry?
21. How is a pipeline different from a transaction?
22. What redis-py pipeline behavior must be checked?
23. Why does cluster topology matter?
24. What do hash tags influence?
25. Why monitor connection pools?
26. Why can network become the next bottleneck?
27. Why can client CPU become the bottleneck?
28. Why report percentiles instead of only average?
29. Why can throughput improve while P99 worsens?
30. What must pass before pipelining is production-ready?

------------------------------------------------------------------------

# Hands-On Acceptance Checklist

## 82. Lab Completion

-   [ ] Populated isolated Chapter 21 keys.
-   [ ] Measured sequential GET performance.
-   [ ] Measured pipelined GET performance.
-   [ ] Tested batch size 10.
-   [ ] Tested batch size 50.
-   [ ] Tested batch size 100.
-   [ ] Tested batch size 500.
-   [ ] Tested batch size 1000.
-   [ ] Recorded throughput.
-   [ ] Recorded batch P50/P95/max.
-   [ ] Tested write pipeline.
-   [ ] Added TTL variation.
-   [ ] Tested larger responses safely.
-   [ ] Estimated response budget.
-   [ ] Tested command-level error handling.
-   [ ] Reviewed retry ambiguity.
-   [ ] Built bounded-queue example.
-   [ ] Reviewed cluster-aware behavior.
-   [ ] Completed ten failure scenarios.
-   [ ] Completed troubleshooting.
-   [ ] Reviewed five production runbooks.
-   [ ] Completed pipeline design template.
-   [ ] Completed benchmark record.
-   [ ] Completed production acceptance checklist.

------------------------------------------------------------------------

# 83. Lab Cleanup

Discover:

``` bash
redis-cli --scan --pattern 'tutorial:chapter21:*'
```

Delete only confirmed Chapter 21 training keys in bounded batches with
`UNLINK`.

Do not use:

``` redis
FLUSHDB
FLUSHALL
```

against a shared or production database.

If a dedicated disposable Redis instance was used for stress testing,
decommission it using the normal environment process.

------------------------------------------------------------------------

# 84. Key Takeaways

1.  Redis application latency includes network round trips, not only
    server command time.
2.  Sequential command loops can waste significant time waiting for
    repeated RTTs.
3.  Pipelining reduces communication overhead.
4.  Batching keeps pipeline resource usage bounded.
5.  The largest possible pipeline is rarely the best production design.
6.  Pipeline size must account for response bytes, not just command
    count.
7.  Throughput and tail latency can move in opposite directions.
8.  Pipelining does not make expensive Redis operations cheap.
9.  Pipelining does not solve hot-key concentration.
10. Bulk write pipelines can increase memory and eviction pressure.
11. Bulk cache writes should preserve TTL-distribution strategy.
12. Backpressure prevents unbounded work accumulation.
13. Concurrent pipelines and producer queues must be bounded.
14. Partial and ambiguous failures require command-level correctness.
15. Retry safety depends on idempotency.
16. Pipelining and transactions solve different problems.
17. Client-library defaults must be understood.
18. Sharded deployments require topology-aware clients and testing.
19. Performance validation must include Redis, network, and client
    resources.
20. Production readiness requires benchmarks, percentiles, bounded
    resource usage, failure testing, and runbooks.

------------------------------------------------------------------------

# 85. References

Validate exact client behavior and Redis semantics against the Redis,
Redis Enterprise, and client-library versions deployed.

Recommended official documentation areas:

-   Redis pipelining
-   Redis client handling
-   Redis latency
-   Redis command complexity
-   Redis Cluster
-   Redis Cluster hash tags
-   Redis transactions
-   `MULTI`
-   `EXEC`
-   `SET`
-   `GET`
-   `UNLINK`
-   Redis Enterprise monitoring
-   redis-py pipelines and connection pools

Pipeline performance depends heavily on RTT, payload size, command type,
client implementation, topology, and concurrency. Benchmark using the
real production client and representative network path before selecting
production values.

------------------------------------------------------------------------

# Next Chapter

**Chapter 22 --- Redis Transactions, WATCH & Atomic Update Patterns**

Chapter 22 will go deeply into:

-   `MULTI`
-   `EXEC`
-   `DISCARD`
-   `WATCH`
-   optimistic concurrency
-   compare-and-set
-   transaction conflicts
-   retry design
-   atomicity boundaries
-   transactions vs. pipelines
-   Lua alternatives
-   cluster/shard constraints
-   failure injection
-   troubleshooting
-   production runbooks
-   acceptance validation
