# Chapter 32 --- Redis Streams, Consumer Groups & Durable Event Processing

**Status:** Canonical\
**Track:** Redis Enterprise / Redis Software Production Engineering\
**Part:** Part 3 --- Messaging, Streaming & Event-Driven Engineering\
**Level:** Intermediate → Production Redis Stream Processing
Engineering\
**Audience:** Developers, SREs, DBREs, Platform Engineers, Redis
Administrators\
**Lab type:** Stream creation, event production, stream IDs, blocking
reads, consumer groups, acknowledgments, pending entries,
abandoned-message recovery, claiming, idempotency, poison-message
handling, retention, trimming, lag, backpressure, failure injection,
observability, troubleshooting, runbooks, and production acceptance

------------------------------------------------------------------------

# 1. Objective

Redis Streams provide an append-oriented data structure for event and
message processing.

Unlike Pub/Sub, stream entries are stored until removed by
retention/trimming or explicit deletion.

A simplified architecture is:

``` text
Producer
   |
   v
Redis Stream
   |
   +--> Consumer Group A
   |       |
   |       +--> Consumer 1
   |       +--> Consumer 2
   |
   +--> Consumer Group B
```

By the end, you should be able to:

-   Create Redis Streams.
-   Append events with `XADD`.
-   Understand stream IDs.
-   Read streams with `XREAD`.
-   Use blocking reads.
-   Create consumer groups.
-   Read with `XREADGROUP`.
-   Acknowledge successful processing.
-   Understand the Pending Entries List.
-   Inspect pending work.
-   Recover abandoned messages.
-   Use `XAUTOCLAIM` where supported.
-   Design idempotent consumers.
-   Handle poison messages.
-   Define retry/dead-letter strategies.
-   Define retention and trimming.
-   Monitor stream growth and consumer lag.
-   Protect consumers with backpressure.
-   Inject failures.
-   Troubleshoot incidents.
-   Build production runbooks and acceptance criteria.

------------------------------------------------------------------------

# 2. Core Production Principle

Redis Streams improve durability and recoverability compared with
Pub/Sub, but they do not automatically make application processing
exactly-once.

A reliable design still requires:

``` text
acknowledgment
idempotency
retry policy
pending-message recovery
retention
capacity
observability
```

------------------------------------------------------------------------

# Part 1 --- Pub/Sub vs. Streams

## 3. Fundamental Difference

Pub/Sub:

``` text
live message delivery
no durable backlog for disconnected subscribers
```

Streams:

``` text
entries retained in a stream
consumers can read later
consumer groups track delivery state
```

------------------------------------------------------------------------

# Part 2 --- Stream

## 4. Append-Oriented Structure

Example stream:

``` text
orders.events
```

Entries are appended:

``` text
event 1
event 2
event 3
...
```

------------------------------------------------------------------------

# Part 3 --- `XADD`

## 5. Add an Entry

``` redis
XADD tutorial:chapter32:orders * event_type order.created order_id 1001
```

The `*` asks Redis to generate the stream entry ID.

------------------------------------------------------------------------

# Part 4 --- Stream IDs

## 6. Structure

A Redis-generated stream ID commonly looks like:

``` text
1712345678901-0
```

Conceptually:

``` text
milliseconds-sequence
```

Treat stream IDs as Redis stream identifiers, not business event IDs.

------------------------------------------------------------------------

# Part 5 --- Business Event ID

## 7. Separate Identity

Include an application event ID:

``` redis
XADD tutorial:chapter32:orders * event_id abc-123 event_type order.created order_id 1001
```

This can support application-level idempotency and tracing.

------------------------------------------------------------------------

# Part 6 --- `XRANGE`

## 8. Inspect Entries

``` redis
XRANGE tutorial:chapter32:orders - +
```

Use bounded ranges/counts in production.

Do not dump enormous streams casually during incidents.

------------------------------------------------------------------------

# Part 7 --- `XREVRANGE`

## 9. Recent Entries

``` redis
XREVRANGE tutorial:chapter32:orders + - COUNT 10
```

Useful for inspecting recent stream data.

------------------------------------------------------------------------

# Part 8 --- `XLEN`

## 10. Stream Length

``` redis
XLEN tutorial:chapter32:orders
```

Track stream growth as part of capacity and retention monitoring.

------------------------------------------------------------------------

# Part 9 --- `XREAD`

## 11. Basic Read

Example:

``` redis
XREAD COUNT 10 STREAMS tutorial:chapter32:orders 0-0
```

This reads entries after the supplied ID.

------------------------------------------------------------------------

# Part 10 --- Blocking Read

## 12. `BLOCK`

Example:

``` redis
XREAD BLOCK 5000 COUNT 10 STREAMS tutorial:chapter32:orders $
```

The exact starting-ID semantics matter.

Test client behavior carefully before production.

------------------------------------------------------------------------

# Part 11 --- `$` Semantics

## 13. New Messages

For an initial `XREAD`, `$` means begin from the current end and wait
for newer entries.

If historical entries must be processed, use an appropriate earlier ID.

------------------------------------------------------------------------

# Part 12 --- Consumer Groups

## 14. Purpose

Consumer groups allow multiple consumers to divide processing for one
logical group.

Example:

``` text
Stream
  |
  +--> Group: order-workers
          |
          +--> worker-1
          +--> worker-2
```

------------------------------------------------------------------------

# Part 13 --- Create Group

## 15. `XGROUP CREATE`

Example:

``` redis
XGROUP CREATE tutorial:chapter32:orders order-workers 0 MKSTREAM
```

Starting at `0` allows the group to process existing entries.

------------------------------------------------------------------------

# Part 14 --- Start at Latest

## 16. `$`

If the group should process only future messages:

``` redis
XGROUP CREATE tutorial:chapter32:orders order-workers $ MKSTREAM
```

This is a critical deployment decision.

------------------------------------------------------------------------

# Part 15 --- Consumer Identity

## 17. Unique Consumer Names

Example:

``` text
worker-1
worker-2
worker-3
```

In Kubernetes, consumer names should avoid accidental collisions between
simultaneously active instances.

Possible input:

``` text
pod name
instance ID
```

------------------------------------------------------------------------

# Part 16 --- `XREADGROUP`

## 18. Read New Work

``` redis
XREADGROUP GROUP order-workers worker-1 COUNT 10 BLOCK 5000 STREAMS tutorial:chapter32:orders >
```

`>` requests entries not yet delivered to another consumer in that
group.

------------------------------------------------------------------------

# Part 17 --- Pending Entries

## 19. Delivery Before ACK

When a consumer receives an entry through a consumer group, it becomes
pending until acknowledged.

Conceptually:

``` text
delivered
   |
   v
Pending Entries List
   |
   +--> ACK -> completed
   |
   +--> no ACK -> remains pending
```

------------------------------------------------------------------------

# Part 18 --- `XACK`

## 20. Acknowledge Success

``` redis
XACK tutorial:chapter32:orders order-workers 1712345678901-0
```

ACK only after the application has completed the work that the ACK
represents.

------------------------------------------------------------------------

# Part 19 --- ACK Timing

## 21. Critical

Bad pattern:

``` text
read
ACK
process
```

If the process crashes after ACK but before business work completes,
recovery may not know that processing was incomplete.

Safer pattern:

``` text
read
process successfully
ACK
```

but this can still produce duplicate processing if the business work
succeeds and the consumer crashes before ACK.

Therefore:

``` text
idempotency is essential
```

------------------------------------------------------------------------

# Part 20 --- At-Least-Once Processing Effect

## 22. Duplicate Possibility

Sequence:

``` text
consumer processes event
business write succeeds
consumer crashes
XACK never happens
message is reclaimed
another consumer processes it again
```

The application must tolerate this.

------------------------------------------------------------------------

# Part 21 --- Idempotency

## 23. Event ID

Example:

``` text
event_id = 4d8...
```

Consumer checks whether the business effect has already been applied.

Possible mechanisms:

``` text
database unique constraint
idempotency table
version check
atomic state transition
Redis idempotency record
```

Choose the authoritative mechanism based on the business system.

------------------------------------------------------------------------

# Part 22 --- Redis Idempotency Record

## 24. Cache/Coordination Example

Possible key:

``` text
processed:event:<event-id>
```

with:

``` redis
SET processed:event:abc123 1 NX EX 86400
```

This may be useful for bounded duplicate suppression, but correctness
depends on retention, atomicity, and failure semantics.

Do not use an expiring Redis marker as the sole correctness mechanism
when permanent business exactly-once behavior is required.

------------------------------------------------------------------------

# Part 23 --- `XPENDING`

## 25. Inspect Pending Work

Summary:

``` redis
XPENDING tutorial:chapter32:orders order-workers
```

Detailed forms can inspect pending entries, consumers, and idle times
depending on Redis version.

------------------------------------------------------------------------

# Part 24 --- Pending Entry List

## 26. PEL

The PEL helps identify:

``` text
messages delivered but not ACKed
stuck consumers
abandoned work
slow processing
```

------------------------------------------------------------------------

# Part 25 --- Consumer Crash

## 27. Recovery Requirement

If `worker-1` receives a message and crashes before ACK:

``` text
message remains pending
```

Another consumer must eventually recover it.

------------------------------------------------------------------------

# Part 26 --- Claiming Work

## 28. `XCLAIM`

Redis supports claiming pending entries under specified conditions.

This transfers responsibility for pending work to another consumer.

Use idle-time thresholds carefully to avoid stealing work from a healthy
but slow consumer.

------------------------------------------------------------------------

# Part 27 --- `XAUTOCLAIM`

## 29. Automated Recovery

Where supported, `XAUTOCLAIM` can scan and claim entries idle longer
than a threshold.

Example concept:

``` redis
XAUTOCLAIM tutorial:chapter32:orders order-workers recovery-worker 60000 0-0 COUNT 100
```

Validate exact syntax and return structure against the deployed Redis
version/client.

------------------------------------------------------------------------

# Part 28 --- Claim Threshold

## 30. Do Not Guess

If normal processing P99 is:

``` text
30 seconds
```

a reclaim threshold of:

``` text
5 seconds
```

can cause duplicate concurrent processing.

Base reclaim thresholds on measured processing duration plus safety
margin.

------------------------------------------------------------------------

# Part 29 --- Recovery Worker

## 31. Pattern

A recovery loop can:

``` text
inspect/auto-claim old pending entries
process idempotently
ACK successful work
quarantine repeated failures
```

------------------------------------------------------------------------

# Part 30 --- Delivery Count

## 32. Retry Signal

Pending-entry metadata can help identify repeatedly delivered messages.

Use this to detect:

``` text
poison messages
systemic consumer failure
```

------------------------------------------------------------------------

# Part 31 --- Poison Message

## 33. Definition

A poison message repeatedly fails processing due to:

``` text
invalid schema
bad business data
unsupported version
permanent downstream rejection
```

Blind infinite retry can block capacity.

------------------------------------------------------------------------

# Part 32 --- Retry Policy

## 34. Define

Specify:

``` text
retryable errors
non-retryable errors
max attempts
backoff
quarantine/dead-letter behavior
operator visibility
```

------------------------------------------------------------------------

# Part 33 --- Dead-Letter Pattern

## 35. Separate Stream

Example:

``` text
orders.events.dlq
```

After retry policy is exhausted, append a diagnostic event containing:

``` text
original event ID
original stream ID
failure reason
attempt count
timestamp
```

Be careful with sensitive payloads.

------------------------------------------------------------------------

# Part 34 --- DLQ Is Not Resolution

## 36. Operations

A DLQ needs:

``` text
monitoring
ownership
triage
replay procedure
retention
```

Otherwise it becomes silent data loss with extra storage.

------------------------------------------------------------------------

# Part 35 --- Replay

## 37. Controlled

Replaying DLQ events should be:

``` text
idempotent
rate-limited
observable
authorized
```

Do not replay thousands of failures directly into a still-broken
dependency.

------------------------------------------------------------------------

# Part 36 --- Retention

## 38. Streams Grow

Without retention/trimming:

``` text
XLEN increases
memory increases
persistence grows
recovery grows
```

Define retention intentionally.

------------------------------------------------------------------------

# Part 37 --- `MAXLEN`

## 39. Trim by Length

Example:

``` redis
XADD tutorial:chapter32:orders MAXLEN ~ 100000 * event_type order.created order_id 1001
```

Approximate trimming can reduce trimming overhead.

Validate exact behavior for the deployed version.

------------------------------------------------------------------------

# Part 38 --- Exact vs. Approximate Trimming

## 40. Tradeoff

Exact trimming:

``` text
tighter length control
potentially more work
```

Approximate trimming:

``` text
allows some overshoot
often more efficient
```

Measure for the workload.

------------------------------------------------------------------------

# Part 39 --- `MINID`

## 41. Time/ID-Oriented Retention

Redis versions supporting `MINID` can trim entries older than a
stream-ID threshold.

Validate syntax/version support before using.

------------------------------------------------------------------------

# Part 40 --- Retention vs. Pending

## 42. Critical Design Question

Do not define aggressive retention without understanding interaction
with:

``` text
consumer lag
pending work
recovery
```

A retention policy must preserve enough history for expected outages and
replay/recovery needs.

------------------------------------------------------------------------

# Part 41 --- Lag

## 43. Meaning

Consumer lag indicates how far processing is behind production.

Useful dimensions:

``` text
entries behind
time behind
pending count
oldest pending age
```

------------------------------------------------------------------------

# Part 42 --- Backlog Growth

## 44. Capacity Signal

If:

``` text
producer rate > consumer processing rate
```

for sustained periods:

``` text
backlog grows
```

Eventually:

``` text
memory
retention
SLO
```

are affected.

------------------------------------------------------------------------

# Part 43 --- Throughput Equation

## 45. Simplified

If:

``` text
producer = 10,000 events/sec
consumer fleet = 8,000 events/sec
```

backlog grows approximately:

``` text
2,000 events/sec
```

until rates change.

------------------------------------------------------------------------

# Part 44 --- Consumer Scaling

## 46. Add Consumers

Within a consumer group, additional consumers can increase parallel
processing if:

``` text
work is parallelizable
downstream capacity exists
Redis/client capacity exists
```

Scaling consumers cannot fix a downstream database that is already
saturated.

------------------------------------------------------------------------

# Part 45 --- Batch Size

## 47. `COUNT`

Larger read batches can improve throughput but increase:

``` text
per-consumer work
processing duration
memory
duplicate exposure after crash
```

Benchmark batch sizes.

------------------------------------------------------------------------

# Part 46 --- Blocking Timeout

## 48. Balance

A blocking read reduces polling overhead.

But the application still needs:

``` text
shutdown handling
health checks
connection recovery
```

------------------------------------------------------------------------

# Part 47 --- Connection Model

## 49. Long-Lived Reads

Stream consumers commonly use long-lived/blocking connections.

Include these connections in Chapter 26 connection capacity planning.

------------------------------------------------------------------------

# Part 48 --- Kubernetes Consumer Identity

## 50. Pod Lifecycle

Consumers may disappear during:

``` text
deployment
node drain
OOM
crash
autoscaling
```

The group must recover pending work from dead instances.

------------------------------------------------------------------------

# Part 49 --- Graceful Shutdown

## 51. Goal

On shutdown:

``` text
stop accepting new work
finish bounded in-flight work
ACK completed work
leave unfinished work recoverable
close connection
```

Do not ACK unfinished work merely to make shutdown fast.

------------------------------------------------------------------------

# Part 50 --- Schema Versioning

## 52. Event Envelope

Example:

``` json
{
  "event_id": "uuid",
  "event_version": 1,
  "event_type": "order.created",
  "occurred_at": "timestamp",
  "payload": {}
}
```

Consumers should explicitly handle unsupported versions.

------------------------------------------------------------------------

# Part 51 --- Large Messages

## 53. Cost

Large stream entries affect:

``` text
memory
network
persistence
replication
consumer memory
retention capacity
```

Keep payloads bounded.

------------------------------------------------------------------------

# Part 52 --- Stream Key Design

## 54. One vs. Many Streams

Possible:

``` text
one stream/service
one stream/domain
one stream/tenant
```

Too many streams can increase operational complexity.

One global stream can create a hot key/workload concentration.

Choose based on routing, ordering, throughput, tenancy, and topology.

------------------------------------------------------------------------

# Part 53 --- Hot Stream

## 55. One Key

A Redis stream is a key.

An extremely high-throughput single stream can become a hot-key/shard
concern in a partitioned topology.

Validate architecture and throughput.

------------------------------------------------------------------------

# Part 54 --- Cluster Placement

## 56. Multi-Key Operations

If workflows use multiple stream keys in atomic/multi-key operations,
slot placement may matter.

Validate Redis Enterprise/cluster topology and client behavior.

Do not apply universal hash tags without considering hot-slot risk.

------------------------------------------------------------------------

# Part 55 --- Observability

## 57. Producer Metrics

Track:

``` text
stream_events_produced_total
stream_produce_errors_total
stream_event_bytes
stream_produce_duration_seconds
```

------------------------------------------------------------------------

## 58. Consumer Metrics

Track:

``` text
stream_events_received_total
stream_events_processed_total
stream_processing_errors_total
stream_ack_total
stream_processing_duration_seconds
stream_retries_total
stream_dlq_total
```

------------------------------------------------------------------------

## 59. Group Health

Track:

``` text
consumer lag
pending count
oldest pending age
consumer count
reclaimed messages
```

------------------------------------------------------------------------

## 60. Capacity

Track:

``` text
XLEN
stream memory
Redis memory
CPU
network
persistence
replication
```

------------------------------------------------------------------------

# Part 56 --- Hands-On Lab

## 61. Objectives

You will:

1.  create a stream;
2.  add events;
3.  inspect entries;
4.  read with `XREAD`;
5.  create a consumer group;
6.  read with `XREADGROUP`;
7.  ACK events;
8.  create pending entries;
9.  inspect `XPENDING`;
10. simulate a consumer crash;
11. recover abandoned work;
12. test idempotency;
13. simulate poison messages;
14. create a DLQ;
15. test trimming;
16. observe backlog.

------------------------------------------------------------------------

# Part 57 --- Prerequisites

## 62. Install

``` bash
python -m pip install redis
```

Environment:

``` text
REDIS_HOST
REDIS_PORT
REDIS_PASSWORD
```

Use an isolated lab Redis database.

------------------------------------------------------------------------

# Part 58 --- CLI Producer

## 63. Add Events

``` redis
XADD tutorial:chapter32:orders * event_id e1 event_type order.created order_id 1001
XADD tutorial:chapter32:orders * event_id e2 event_type order.created order_id 1002
XADD tutorial:chapter32:orders * event_id e3 event_type order.cancelled order_id 1003
```

------------------------------------------------------------------------

# Part 59 --- Inspect

## 64. Commands

``` redis
XLEN tutorial:chapter32:orders
XRANGE tutorial:chapter32:orders - + COUNT 10
```

------------------------------------------------------------------------

# Part 60 --- Create Group

## 65. Command

``` redis
XGROUP CREATE tutorial:chapter32:orders order-workers 0 MKSTREAM
```

If the group already exists, Redis returns an error.

Production startup code should handle group creation idempotently.

------------------------------------------------------------------------

# Part 61 --- Read as Consumer

## 66. Command

``` redis
XREADGROUP GROUP order-workers worker-1 COUNT 1 STREAMS tutorial:chapter32:orders >
```

Record the returned stream ID.

------------------------------------------------------------------------

# Part 62 --- Pending Inspection

## 67. Before ACK

``` redis
XPENDING tutorial:chapter32:orders order-workers
```

The delivered entry should appear as pending.

------------------------------------------------------------------------

# Part 63 --- ACK

## 68. Command

``` redis
XACK tutorial:chapter32:orders order-workers <stream-id>
```

Then:

``` redis
XPENDING tutorial:chapter32:orders order-workers
```

Observe the change.

------------------------------------------------------------------------

# Part 64 --- Python Producer

## 69. Create `chapter32_producer.py`

``` python
import os
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
    socket_connect_timeout=2,
    socket_timeout=2,
)

STREAM = "tutorial:chapter32:orders"

for i in range(100):
    event_id = str(
        uuid.uuid4()
    )

    stream_id = r.xadd(
        STREAM,
        {
            "event_id": event_id,
            "event_version": "1",
            "event_type":
                "order.created",
            "order_id": str(
                1000 + i
            ),
            "occurred_at": str(
                time.time()
            ),
        },
        maxlen=10000,
        approximate=True,
    )

    print(
        stream_id,
        event_id,
    )
```

------------------------------------------------------------------------

# Part 65 --- Python Consumer

## 70. Create `chapter32_consumer.py`

``` python
import os
import socket
import time

import redis

HOST = os.getenv("REDIS_HOST", "localhost")
PORT = int(os.getenv("REDIS_PORT", "6379"))
PASSWORD = os.getenv("REDIS_PASSWORD") or None

STREAM = "tutorial:chapter32:orders"
GROUP = "order-workers"

CONSUMER = os.getenv(
    "CONSUMER_NAME",
    socket.gethostname(),
)

r = redis.Redis(
    host=HOST,
    port=PORT,
    password=PASSWORD,
    decode_responses=True,
    socket_connect_timeout=2,
    socket_timeout=None,
)

try:
    r.xgroup_create(
        STREAM,
        GROUP,
        id="0",
        mkstream=True,
    )
except redis.ResponseError as exc:
    if "BUSYGROUP" not in str(exc):
        raise

while True:
    response = r.xreadgroup(
        GROUP,
        CONSUMER,
        {
            STREAM: ">"
        },
        count=10,
        block=5000,
    )

    if not response:
        continue

    for _, messages in response:
        for stream_id, fields in messages:
            try:
                print(
                    "processing",
                    stream_id,
                    fields,
                )

                # Business processing here.

                r.xack(
                    STREAM,
                    GROUP,
                    stream_id,
                )

            except Exception as exc:
                print(
                    "processing failed",
                    stream_id,
                    type(exc).__name__,
                )
```

Production code needs structured shutdown, retry classification,
metrics, idempotency, and recovery logic.

------------------------------------------------------------------------

# Part 66 --- Crash Lab

## 71. Procedure

1.  Start consumer.
2.  Receive a message.
3.  Stop process before `XACK`.
4.  Run `XPENDING`.
5.  Confirm entry remains pending.
6.  Start recovery consumer.
7.  Reclaim after safe idle threshold.
8.  Process idempotently.
9.  ACK.

------------------------------------------------------------------------

# Part 67 --- Auto-Claim Example

## 72. redis-py Concept

Where supported by the installed redis-py/Redis version:

``` python
result = r.xautoclaim(
    STREAM,
    GROUP,
    "recovery-worker",
    min_idle_time=60000,
    start_id="0-0",
    count=100,
)
```

Inspect the exact return shape for your installed client version.

Do not copy production recovery code without validating it.

------------------------------------------------------------------------

# Part 68 --- Idempotency Lab

## 73. Duplicate Event

Publish two entries with the same:

``` text
event_id
```

Consumer logic should detect that the business effect was already
applied.

For a learning lab:

``` python
idempotency_key = (
    "tutorial:chapter32:"
    f"processed:{event_id}"
)

first = r.set(
    idempotency_key,
    "1",
    nx=True,
    ex=3600,
)

if not first:
    print(
        "duplicate event:",
        event_id,
    )
```

This is a demonstration, not a universal business correctness solution.

------------------------------------------------------------------------

# Part 69 --- Poison Message Lab

## 74. Invalid Version

Publish:

``` redis
XADD tutorial:chapter32:orders * event_id bad1 event_version 999 event_type order.created order_id 5000
```

Consumer should classify it as non-retryable after policy evaluation
rather than retry forever.

------------------------------------------------------------------------

# Part 70 --- DLQ Lab

## 75. Append Failure

Example:

``` python
r.xadd(
    "tutorial:chapter32:orders:dlq",
    {
        "original_stream_id":
            stream_id,
        "event_id":
            fields.get(
                "event_id",
                "",
            ),
        "reason":
            "unsupported_version",
        "failed_at":
            str(time.time()),
    },
)
```

Then ACK the original only after the DLQ/quarantine action meets the
application's required semantics.

------------------------------------------------------------------------

# Part 71 --- Backlog Lab

## 76. Create Faster Producer

Produce events much faster than one deliberately slow consumer.

Observe:

``` text
XLEN
pending
processing rate
```

Then add consumers gradually.

------------------------------------------------------------------------

# Part 72 --- Trim Lab

## 77. Disposable Environment

Generate many entries with:

``` text
MAXLEN ~ 1000
```

Observe that stream length is bounded approximately rather than
necessarily exactly.

------------------------------------------------------------------------

# Part 73 --- Failure Injection

## 78. Failure 1 --- Consumer Crash Before ACK

Verify pending recovery.

------------------------------------------------------------------------

## 79. Failure 2 --- Crash After Business Commit Before ACK

Reclaim the message and observe duplicate processing risk.

Validate idempotency.

------------------------------------------------------------------------

## 80. Failure 3 --- Poison Message

Cause deterministic processing failure.

Verify retry cap and DLQ/quarantine behavior.

------------------------------------------------------------------------

## 81. Failure 4 --- Consumer Too Slow

Make producer rate exceed consumer capacity.

Observe backlog growth.

------------------------------------------------------------------------

## 82. Failure 5 --- Reclaim Threshold Too Low

Use an unrealistically low idle threshold.

Observe how healthy slow work can be reclaimed prematurely.

------------------------------------------------------------------------

## 83. Failure 6 --- No Retention

Produce a large training stream without trimming in a disposable
environment.

Observe stream growth and memory impact.

------------------------------------------------------------------------

## 84. Failure 7 --- Retention Too Aggressive

Configure a tiny training retention target.

Review how inadequate retention conflicts with outage/recovery
requirements.

------------------------------------------------------------------------

## 85. Failure 8 --- Large Events

Publish large payloads.

Observe:

``` text
memory
network
consumer processing
```

------------------------------------------------------------------------

## 86. Failure 9 --- Consumer Fleet Restart

Stop all consumers while producer continues.

Restart later and observe backlog catch-up behavior.

------------------------------------------------------------------------

## 87. Failure 10 --- Retry Storm

Make downstream processing transiently fail.

Allow aggressive retries.

Observe downstream/Redis amplification.

Then add bounded retry/backoff and recovery pacing.

------------------------------------------------------------------------

# Part 74 --- Troubleshooting

## 88. Stream Growing Rapidly

Check:

``` text
producer rate
consumer rate
consumer lag
consumer errors
pending count
retention
```

------------------------------------------------------------------------

## 89. Pending Count Growing

Check:

``` text
consumer processing failures
slow consumers
crashed consumers
ACK path
downstream dependency
```

------------------------------------------------------------------------

## 90. Old Pending Entries

Check:

``` text
dead consumer
stuck work
claim/recovery loop
reclaim threshold
poison message
```

------------------------------------------------------------------------

## 91. Duplicate Business Effects

Check:

``` text
crash after commit before ACK
reclaim
retry
idempotency implementation
event ID uniqueness
```

------------------------------------------------------------------------

## 92. Messages Never Processed

Check:

``` text
group start ID
consumer group
consumer errors
stream key
XREADGROUP ID
```

A group created at `$` does not process old history automatically.

------------------------------------------------------------------------

## 93. DLQ Growing

Check:

``` text
schema version
bad producer release
downstream validation
consumer bug
permanent business rejection
```

Do not blindly replay until the cause is fixed.

------------------------------------------------------------------------

## 94. Memory Growing

Check:

``` text
stream length
entry size
retention
DLQ
consumer lag
other Redis workloads
```

------------------------------------------------------------------------

## 95. Recovery Creates Load Spike

Check:

``` text
reclaim batch size
recovery worker count
downstream capacity
retry rate
```

Pace recovery.

------------------------------------------------------------------------

# Part 75 --- Production Runbooks

## 96. Runbook --- Consumer Backlog

``` text
1. Measure producer rate.
2. Measure consumer processing rate.
3. Measure lag/pending.
4. Identify processing errors.
5. Check downstream capacity.
6. Scale consumers only if downstream can absorb it.
7. Tune batch size.
8. Pace recovery/retries.
9. Verify backlog decreases.
10. Review capacity headroom.
```

------------------------------------------------------------------------

## 97. Runbook --- Stuck Pending Entries

``` text
1. Inspect XPENDING.
2. Identify owning consumer.
3. Check consumer health.
4. Measure pending idle age.
5. Compare with normal P99 processing time.
6. Reclaim only genuinely abandoned work.
7. Process idempotently.
8. ACK successful recovery.
9. Quarantine repeated failures.
10. Verify PEL returns to normal.
```

------------------------------------------------------------------------

## 98. Runbook --- Poison Message

``` text
1. Identify failing stream ID/event ID.
2. Capture failure reason safely.
3. Classify retryable vs permanent.
4. Stop infinite retries.
5. Quarantine/DLQ after policy threshold.
6. ACK original according to required semantics.
7. Fix producer/consumer/data issue.
8. Validate fix with one event.
9. Replay at bounded rate if appropriate.
10. Monitor DLQ and downstream.
```

------------------------------------------------------------------------

## 99. Runbook --- Stream Memory Growth

``` text
1. Check XLEN.
2. Measure event size.
3. Check producer rate.
4. Check retention configuration.
5. Check consumer lag.
6. Estimate memory runway.
7. Correct retention carefully.
8. Do not trim below recovery requirements.
9. Verify memory stabilizes.
10. Update capacity model.
```

------------------------------------------------------------------------

## 100. Runbook --- Consumer Fleet Restart

``` text
1. Confirm stream/Redis health.
2. Measure accumulated backlog.
3. Estimate catch-up work.
4. Protect downstream dependency.
5. Start consumers gradually.
6. Monitor pending/lag.
7. Recover abandoned PEL entries.
8. Apply bounded retry.
9. Verify backlog reaches normal.
10. Review restart/recovery capacity.
```

------------------------------------------------------------------------

# Part 76 --- Stream Design Template

## 101. Fields

``` text
Stream:
Owner:
Use case:
Producer(s):
Consumer group(s):
Consumer naming:
Event schema:
Event version:
Business event ID:
Average event bytes:
P99 event bytes:
Events/sec:
Peak events/sec:
Retention:
MAXLEN/MINID policy:
Consumer batch:
Blocking timeout:
Normal processing P50/P95/P99:
ACK point:
Idempotency mechanism:
Retryable errors:
Max retries:
Reclaim threshold:
Recovery worker:
DLQ:
Replay procedure:
Lag SLO:
Pending threshold:
Metrics:
Runbook owner:
```

------------------------------------------------------------------------

# Part 77 --- Capacity Worksheet

## 102. Estimate

``` text
events/sec
×
average event bytes
×
retention seconds
```

gives a rough payload-retention magnitude before Redis
structure/allocator/persistence overhead.

Also calculate:

``` text
producer throughput
consumer throughput
backlog growth rate
catch-up throughput
network
persistence
replication
```

------------------------------------------------------------------------

# Part 78 --- Recovery Capacity

## 103. Example

Normal:

``` text
producer = 5,000 events/sec
consumer capacity = 7,000 events/sec
```

Catch-up capacity:

``` text
2,000 events/sec
```

If outage creates:

``` text
7.2 million events
```

rough catch-up time at 2,000 net events/sec:

``` text
3,600 seconds
≈ 1 hour
```

assuming downstream systems can sustain that rate.

------------------------------------------------------------------------

# Part 79 --- Pub/Sub vs. Streams Decision

## 104. Pub/Sub

Choose when:

``` text
live fan-out
loss during disconnect acceptable/recoverable
no backlog needed
```

------------------------------------------------------------------------

## 105. Streams

Choose when:

``` text
stored events required
consumer groups required
pending recovery required
acknowledgment required
offline catch-up required
```

Streams still require application-level correctness engineering.

------------------------------------------------------------------------

# Production Acceptance Checklist

## 106. Stream Engineering

-   [ ] Stream purpose documented.
-   [ ] Producer ownership documented.
-   [ ] Consumer groups documented.
-   [ ] Group starting ID intentionally selected.
-   [ ] Consumer names unique.
-   [ ] Event schema versioned.
-   [ ] Business event ID included.
-   [ ] Average/P99 event size measured.
-   [ ] Producer rate measured.
-   [ ] Consumer capacity measured.
-   [ ] ACK point documented.
-   [ ] Idempotency mechanism tested.
-   [ ] Duplicate-processing test passed.
-   [ ] Pending monitoring implemented.
-   [ ] Reclaim threshold based on measured processing time.
-   [ ] Recovery worker tested.
-   [ ] Poison-message policy defined.
-   [ ] Retry cap defined.
-   [ ] DLQ/quarantine monitored.
-   [ ] Replay procedure tested.
-   [ ] Retention defined.
-   [ ] Retention supports outage/recovery requirement.
-   [ ] Lag monitored.
-   [ ] Backlog alert defined.
-   [ ] Stream memory monitored.
-   [ ] Consumer fleet restart tested.
-   [ ] Production runbooks validated.

------------------------------------------------------------------------

# Knowledge Validation

## 107. Questions

You should be able to answer:

1.  What is a Redis Stream?
2.  How does a Stream differ from Pub/Sub?
3.  What does `XADD` do?
4.  What is a stream ID?
5.  Why use a separate business event ID?
6.  What does `XLEN` show?
7.  What does `XREAD` do?
8.  What does `$` mean for an initial `XREAD`?
9.  What is a consumer group?
10. What does the group creation start ID control?
11. What does `>` mean in `XREADGROUP`?
12. What is the Pending Entries List?
13. What does `XACK` do?
14. Why should ACK usually follow successful processing?
15. Why can duplicate processing still occur?
16. Why is idempotency required?
17. What does `XPENDING` help diagnose?
18. What problem does `XCLAIM` solve?
19. What does `XAUTOCLAIM` help automate?
20. Why must reclaim idle time exceed normal processing behavior?
21. What is a poison message?
22. Why cap retries?
23. What is a DLQ?
24. Why does a DLQ require monitoring?
25. Why define stream retention?
26. What is the tradeoff of approximate trimming?
27. What is consumer lag?
28. Why can adding consumers fail to solve a backlog?
29. Why are large stream entries expensive?
30. What must pass before Redis Streams are production-ready?

------------------------------------------------------------------------

# Hands-On Acceptance Checklist

## 108. Lab Completion

-   [ ] Added entries with `XADD`.
-   [ ] Inspected `XLEN`.
-   [ ] Inspected `XRANGE`.
-   [ ] Read with `XREAD`.
-   [ ] Created consumer group.
-   [ ] Read with `XREADGROUP`.
-   [ ] Observed pending entry.
-   [ ] ACKed entry.
-   [ ] Simulated crash before ACK.
-   [ ] Inspected `XPENDING`.
-   [ ] Recovered abandoned work.
-   [ ] Reviewed `XAUTOCLAIM`.
-   [ ] Tested duplicate event ID.
-   [ ] Implemented learning idempotency marker.
-   [ ] Injected poison message.
-   [ ] Created DLQ entry.
-   [ ] Generated backlog.
-   [ ] Tested consumer scaling.
-   [ ] Tested trimming.
-   [ ] Tested large event.
-   [ ] Tested fleet restart.
-   [ ] Tested retry storm.
-   [ ] Completed ten failure scenarios.
-   [ ] Completed troubleshooting.
-   [ ] Reviewed five production runbooks.
-   [ ] Completed stream design template.
-   [ ] Completed capacity worksheet.
-   [ ] Completed production acceptance checklist.

------------------------------------------------------------------------

# 109. Lab Cleanup

Discover only Chapter 32 keys:

``` bash
redis-cli --scan --pattern 'tutorial:chapter32:*'
```

Review the results.

Delete only confirmed Chapter 32 lab keys in bounded batches:

``` redis
UNLINK <confirmed-key>
```

The lab may include:

``` text
tutorial:chapter32:orders
tutorial:chapter32:orders:dlq
tutorial:chapter32:processed:*
```

Do not use:

``` redis
KEYS tutorial:chapter32:*
FLUSHDB
FLUSHALL
```

against a shared or production Redis database.

------------------------------------------------------------------------

# 110. Key Takeaways

1.  Redis Streams persist entries and support recovery patterns that
    Pub/Sub does not.
2.  `XADD` appends events to a stream.
3.  Redis stream IDs and business event IDs serve different purposes.
4.  Consumer groups distribute work among consumers in one logical
    processing group.
5.  `XREADGROUP ... >` reads new group work.
6.  Delivered group messages remain pending until acknowledged.
7.  ACK only when the work represented by the ACK is complete.
8.  A crash after business commit but before ACK can cause duplicate
    processing.
9.  Therefore, idempotency is fundamental to reliable stream consumers.
10. `XPENDING` exposes unacknowledged work.
11. `XCLAIM`/`XAUTOCLAIM` support recovery of abandoned work.
12. Reclaim thresholds must be based on measured processing duration.
13. Poison messages require bounded retry and quarantine/DLQ policy.
14. A DLQ without monitoring and replay ownership is incomplete.
15. Streams require explicit retention because unbounded streams consume
    memory.
16. Retention must preserve enough history for expected outages and
    recovery.
17. Consumer lag and oldest pending age are critical production signals.
18. Producer throughput must not sustainably exceed consumer capacity.
19. Recovery/catch-up capacity must be planned before an outage.
20. Redis Streams provide durable primitives, but production correctness
    still depends on application idempotency, recovery, retention, and
    observability.

------------------------------------------------------------------------

# 111. References

Validate exact Streams, consumer-group, trimming, claiming, and client
behavior against the Redis, Redis Enterprise, and client-library
versions deployed.

Recommended official Redis documentation areas:

-   Redis Streams
-   `XADD`
-   `XRANGE`
-   `XREVRANGE`
-   `XLEN`
-   `XREAD`
-   `XGROUP`
-   `XREADGROUP`
-   `XACK`
-   `XPENDING`
-   `XCLAIM`
-   `XAUTOCLAIM`
-   `XTRIM`
-   Redis Streams consumer groups
-   Redis Enterprise monitoring
-   redis-py Streams APIs

------------------------------------------------------------------------

# Next Chapter

**Chapter 33 --- Redis Streams Reliability, Retry, DLQ & Recovery
Engineering**

Chapter 33 will go deeper into:

-   consumer crash recovery
-   PEL lifecycle
-   retry state
-   retry scheduling
-   poison-event isolation
-   DLQ architecture
-   replay safety
-   idempotency stores
-   deduplication windows
-   consumer fleet restarts
-   outage catch-up
-   lag SLOs
-   retention vs. recovery windows
-   recovery capacity
-   operational dashboards
-   failure injection
-   incident runbooks
-   production acceptance validation
