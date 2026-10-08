# Chapter 31 --- Redis Pub/Sub, Messaging & Real-Time Event Delivery

**Status:** Canonical\
**Track:** Redis Enterprise / Redis Software Production Engineering\
**Part:** Part 3 --- Messaging, Streaming & Event-Driven Engineering\
**Level:** Intermediate → Production Redis Messaging Engineering\
**Audience:** Developers, SREs, DBREs, Platform Engineers, Redis
Administrators\
**Lab type:** Pub/Sub channels, publishers, subscribers, pattern
subscriptions, delivery semantics, subscriber disconnects, slow
consumers, reconnect behavior, message sizing, fan-out, sharded/topology
considerations, Pub/Sub vs. Streams, failure injection, observability,
troubleshooting, runbooks, and production acceptance

------------------------------------------------------------------------

# 1. Objective

Redis Pub/Sub provides lightweight real-time message fan-out.

A publisher sends a message to a channel:

``` text
Publisher
   |
   v
Redis channel
   |
   +--> Subscriber A
   +--> Subscriber B
   +--> Subscriber C
```

Pub/Sub is useful when consumers need messages that are available
**while they are connected**.

It is not a durable message queue.

By the end, you should be able to:

-   Explain Redis Pub/Sub.
-   Publish and subscribe safely.
-   Use channel naming conventions.
-   Use pattern subscriptions.
-   Understand at-most-once-style delivery implications.
-   Understand disconnected-subscriber behavior.
-   Design reconnect handling.
-   Detect slow consumers.
-   Bound message size and fan-out.
-   Understand dedicated subscriber connections.
-   Protect connection pools.
-   Compare Pub/Sub with Redis Streams.
-   Select the correct messaging primitive.
-   Observe messaging health.
-   Inject messaging failures.
-   Troubleshoot incidents.
-   Build production runbooks and acceptance criteria.

------------------------------------------------------------------------

# 2. Core Production Principle

Redis Pub/Sub is designed for live message delivery.

It does not provide a durable backlog for disconnected consumers.

If a subscriber is disconnected when a message is published, the
application should not assume that message can be replayed later from
Pub/Sub.

Use a durable messaging design when replay, acknowledgment, or recovery
is required.

------------------------------------------------------------------------

# Part 1 --- Pub/Sub Model

## 3. Components

Redis Pub/Sub has:

``` text
publisher
channel
subscriber
message
```

Publishers do not need to know individual subscribers.

Subscribers listen to channels.

------------------------------------------------------------------------

# Part 2 --- Channel

## 4. Logical Topic

Example:

``` text
orders.events
```

Publisher:

``` redis
PUBLISH orders.events '{"order_id":1001,"state":"created"}'
```

Subscriber:

``` redis
SUBSCRIBE orders.events
```

------------------------------------------------------------------------

# Part 3 --- Fan-Out

## 5. Multiple Subscribers

If three connected subscribers listen to the same channel:

``` text
message
  |
  +--> A
  +--> B
  +--> C
```

all can receive the live publication.

This is broadcast/fan-out behavior, not competing-consumer queue
semantics.

------------------------------------------------------------------------

# Part 4 --- Delivery Semantics

## 6. No Durable Backlog

Pub/Sub does not persist messages for later consumption as a durable
queue.

If:

``` text
Subscriber B disconnects
Publisher publishes message X
Subscriber B reconnects
```

Subscriber B should not expect Pub/Sub to replay message X.

------------------------------------------------------------------------

# Part 5 --- Application Consequence

## 7. Choose Pub/Sub Only When Loss Is Acceptable or Recoverable

Good candidates can include:

``` text
live UI hints
cache invalidation hints with reconciliation
ephemeral notifications
best-effort real-time signals
```

Use stronger durable mechanisms for events that must be recovered.

------------------------------------------------------------------------

# Part 6 --- Pub/Sub vs. Durable Messaging

## 8. Questions

Ask:

``` text
Must every event be processed?
Must consumers acknowledge?
Must disconnected consumers catch up?
Must events be replayed?
Must processing state survive restart?
```

If yes, plain Pub/Sub may be the wrong primitive.

------------------------------------------------------------------------

# Part 7 --- Redis Streams

## 9. Durable Alternative

Redis Streams support persisted stream entries and richer consumption
patterns.

Conceptually:

``` text
Pub/Sub:
live broadcast

Streams:
persisted event log / stream
```

Chapter 32 will cover Streams in depth.

------------------------------------------------------------------------

# Part 8 --- Subscriber Connection

## 10. Dedicated Behavior

A Pub/Sub subscriber uses a long-lived connection with subscription
semantics.

Do not treat it like a normal request/response connection from the
ordinary command pool.

Use the client library's supported Pub/Sub abstraction.

------------------------------------------------------------------------

# Part 9 --- Connection Pool Interaction

## 11. Capacity

If each application instance has:

``` text
1 subscriber connection
```

and there are:

``` text
500 instances
```

that is at least:

``` text
500 long-lived subscriber connections
```

in addition to normal Redis command connections.

Include them in Chapter 26 connection budgets.

------------------------------------------------------------------------

# Part 10 --- Channel Naming

## 12. Convention

Example:

``` text
<service>.<domain>.<event-class>
```

Such as:

``` text
orders.lifecycle.events
catalog.cache.invalidate
patient360.ui.notifications
```

Choose one organizational standard.

------------------------------------------------------------------------

# Part 11 --- Environment Isolation

## 13. Avoid Cross-Environment Events

If infrastructure is shared by design, include environment identity:

``` text
prod.orders.lifecycle
staging.orders.lifecycle
```

Prefer stronger environment isolation when required.

A channel prefix is not a security boundary.

------------------------------------------------------------------------

# Part 12 --- Tenant Channels

## 14. Multi-Tenant Design

Possible pattern:

``` text
notifications.tenant.1001
```

But creating one channel/subscription per tenant can create operational
complexity at high tenant cardinality.

Evaluate:

``` text
tenant count
subscriber count
message rate
authorization
fan-out
```

------------------------------------------------------------------------

# Part 13 --- Pattern Subscriptions

## 15. `PSUBSCRIBE`

Example:

``` redis
PSUBSCRIBE orders.*
```

This can subscribe to matching channels.

Use carefully because broad patterns may receive far more traffic than
expected.

------------------------------------------------------------------------

# Part 14 --- Broad Pattern Risk

## 16. Example

Subscriber intends:

``` text
orders.us.*
```

but subscribes to:

``` text
orders.*
```

It may consume unrelated regions/workloads.

Channel naming and subscription patterns are production controls.

------------------------------------------------------------------------

# Part 15 --- Message Envelope

## 17. Recommended Metadata

A message can include:

``` json
{
  "event_version": 1,
  "event_type": "order.created",
  "event_id": "uuid",
  "occurred_at": "timestamp",
  "payload": {}
}
```

Even for ephemeral delivery, versioned messages improve compatibility.

------------------------------------------------------------------------

# Part 16 --- Event Version

## 18. Schema Evolution

Consumers should know how to handle:

``` text
known version
unknown version
missing field
new optional field
```

Do not silently reinterpret incompatible events.

------------------------------------------------------------------------

# Part 17 --- Message Size

## 19. Keep Messages Bounded

Large messages increase:

``` text
network
publisher cost
Redis network load
subscriber memory
deserialization CPU
fan-out cost
```

If 1 MB is published to 100 subscribers, downstream transfer can be
roughly orders of magnitude larger than the original publisher payload.

------------------------------------------------------------------------

# Part 18 --- Reference vs. Payload

## 20. Alternative

Instead of publishing a huge object:

``` json
{
  "entire_record": "..."
}
```

publish:

``` json
{
  "event_type": "record.changed",
  "record_id": "123"
}
```

when consumers can safely fetch authoritative state.

This trades event bytes for downstream reads.

------------------------------------------------------------------------

# Part 19 --- Fan-Out Cost

## 21. Multiplication

Approximate subscriber delivery bytes:

``` text
message bytes
×
number of subscribers
×
messages/sec
```

Example:

``` text
10 KB
×
100 subscribers
×
1,000 messages/sec
≈
1 GB/sec
```

before protocol/network overhead.

------------------------------------------------------------------------

# Part 20 --- Slow Consumers

## 22. Risk

A subscriber that cannot process messages fast enough can accumulate
pressure in the client/server connection path.

Symptoms can include:

``` text
subscriber lag in application processing
memory growth
connection closure
reconnect loops
```

Pub/Sub itself does not provide durable consumer lag recovery.

------------------------------------------------------------------------

# Part 21 --- Subscriber Queue

## 23. Bound It

Application pattern:

``` text
Redis subscriber
   |
bounded internal queue
   |
workers
```

Do not create an unlimited in-memory queue behind the subscriber.

------------------------------------------------------------------------

# Part 22 --- Backpressure

## 24. Important Limitation

A live Pub/Sub feed may continue while application processing is slow.

If the application cannot safely absorb the rate, consider:

``` text
rate control
smaller messages
more consumers
workload redesign
Redis Streams
durable external messaging
```

------------------------------------------------------------------------

# Part 23 --- Subscriber Processing

## 25. Keep Callback Small

Avoid doing expensive work directly in the subscriber receive loop.

Prefer:

``` text
receive
validate
enqueue bounded work
return to receive loop
```

subject to the application's loss/recovery semantics.

------------------------------------------------------------------------

# Part 24 --- Reconnect

## 26. Expected Failure

Network changes, failover, deployments, or Redis restarts can disconnect
subscribers.

Client logic should:

``` text
detect disconnect
reconnect
resubscribe
apply bounded backoff/jitter
restore application health
```

------------------------------------------------------------------------

# Part 25 --- Reconnect Does Not Replay

## 27. Critical

After reconnect/resubscribe:

``` text
future messages resume
```

but messages published while disconnected are not automatically
recovered from Pub/Sub.

If missing state matters, reconcile from an authoritative source.

------------------------------------------------------------------------

# Part 26 --- Reconciliation

## 28. Example

For cache invalidation:

``` text
Pub/Sub invalidation = fast path
periodic/version reconciliation = correctness safety net
```

This prevents one missed invalidation from creating indefinite stale
state.

------------------------------------------------------------------------

# Part 27 --- Publisher Failure

## 29. Publish Result

Applications should understand what the client/library returns for
`PUBLISH`.

A subscriber count response does not mean durable processing occurred.

It only reflects Pub/Sub delivery/subscription behavior at that moment.

------------------------------------------------------------------------

# Part 28 --- Business Acknowledgment

## 30. Not Provided by Plain Pub/Sub

Plain Pub/Sub does not provide application-level:

``` text
consumer ACK
retry queue
dead-letter queue
durable offset
```

If required, use a different messaging pattern.

------------------------------------------------------------------------

# Part 29 --- Duplicate Application Effects

## 31. Reconnect Logic

Although Pub/Sub itself is ephemeral, application retry/reconciliation
logic may still cause duplicate business actions.

Design consumers to be safe where duplicate processing is possible
through surrounding systems.

------------------------------------------------------------------------

# Part 30 --- Ordering

## 32. Scope

Do not infer a global business ordering guarantee across:

``` text
multiple publishers
multiple channels
multiple processing workers
```

If strict ordering matters, design and test it explicitly.

------------------------------------------------------------------------

# Part 31 --- Multiple Publishers

## 33. Concurrent Events

Events from different publishers may represent concurrent business
changes.

Use:

``` text
version
sequence
timestamp
authoritative-state reconciliation
```

where ordering matters.

------------------------------------------------------------------------

# Part 32 --- Sharded Pub/Sub / Topology

## 34. Deployment Awareness

Modern Redis deployments can have topology-specific Pub/Sub behavior and
capabilities.

Validate exact semantics for:

``` text
Redis version
Redis Enterprise version
cluster mode
client library
```

Do not assume standalone examples fully describe a distributed
production topology.

------------------------------------------------------------------------

# Part 33 --- Security

## 35. Channel Authorization

Review deployed Redis/Redis Enterprise ACL capabilities for Pub/Sub
channels.

Application authorization remains necessary.

Do not publish secrets merely because the channel is internal.

------------------------------------------------------------------------

# Part 34 --- Sensitive Data

## 36. Minimize

Messages may appear in:

``` text
application logs
debug traces
subscriber diagnostics
```

Use identifiers/minimal payloads where possible.

------------------------------------------------------------------------

# Part 35 --- Publisher Rate

## 37. Protect Redis

A runaway publisher can create:

``` text
network saturation
subscriber overload
client memory pressure
```

Apply rate/concurrency controls where appropriate.

------------------------------------------------------------------------

# Part 36 --- Subscriber Count

## 38. Capacity

Track:

``` text
expected subscribers/channel
peak subscribers
reconnect rate
```

A deployment wave can create a subscriber connection storm.

------------------------------------------------------------------------

# Part 37 --- Kubernetes

## 39. Replica Multiplication

If:

``` text
200 pods
```

each subscribe to a broadcast channel, every message may be delivered to
all 200 pods.

Ask whether all replicas truly need every message.

------------------------------------------------------------------------

# Part 38 --- Competing Consumer Requirement

## 40. Pub/Sub Is Different

If the requirement is:

``` text
one message processed by one worker
```

broadcast Pub/Sub is not the same as a queue/consumer-group model.

Consider Redis Streams or another queue.

------------------------------------------------------------------------

# Part 39 --- Observability

## 41. Publisher Metrics

Track:

``` text
pubsub_publish_total
pubsub_publish_errors_total
pubsub_publish_duration_seconds
pubsub_message_bytes
```

------------------------------------------------------------------------

## 42. Subscriber Metrics

Track:

``` text
pubsub_messages_received_total
pubsub_decode_errors_total
pubsub_processing_errors_total
pubsub_reconnect_total
pubsub_disconnect_total
pubsub_internal_queue_depth
pubsub_processing_duration_seconds
```

------------------------------------------------------------------------

## 43. Business Metrics

Where loss matters operationally, track reconciliation signals:

``` text
state_version_gap
reconciliation_repairs
missed_event_detected
```

------------------------------------------------------------------------

# Part 40 --- Redis-Side Observability

## 44. Correlate

Review:

``` text
network
CPU
connections
latency
client behavior
```

and supported Pub/Sub metrics/commands for the deployed Redis version.

------------------------------------------------------------------------

# Part 41 --- Hands-On Lab

## 45. Objectives

You will:

1.  create a publisher;
2.  create a subscriber;
3.  subscribe to multiple channels;
4.  use pattern subscriptions;
5.  observe fan-out;
6.  disconnect a subscriber;
7.  prove missed-message behavior;
8.  reconnect/resubscribe;
9.  test large messages;
10. test a slow consumer;
11. bound application queueing;
12. compare Pub/Sub requirements with Streams.

------------------------------------------------------------------------

# Part 42 --- Prerequisites

## 46. Install

``` bash
python -m pip install redis
```

Environment:

``` text
REDIS_HOST
REDIS_PORT
REDIS_PASSWORD
```

------------------------------------------------------------------------

# Part 43 --- Subscriber

## 47. Create `chapter31_subscriber.py`

``` python
import json
import os
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
    socket_timeout=None,
)

pubsub = r.pubsub()

CHANNEL = (
    "tutorial.chapter31.events"
)

pubsub.subscribe(
    CHANNEL
)

print(
    "subscribed:",
    CHANNEL,
)

for message in pubsub.listen():
    if message["type"] != "message":
        continue

    try:
        event = json.loads(
            message["data"]
        )

        print(
            "event:",
            event,
        )

    except Exception as exc:
        print(
            "decode error:",
            type(exc).__name__,
        )
```

Use a dedicated Pub/Sub client abstraction according to the deployed
redis-py version.

------------------------------------------------------------------------

# Part 44 --- Publisher

## 48. Create `chapter31_publisher.py`

``` python
import json
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

CHANNEL = (
    "tutorial.chapter31.events"
)

for i in range(10):
    event = {
        "event_version": 1,
        "event_type":
            "tutorial.message",
        "event_id":
            str(uuid.uuid4()),
        "sequence": i,
        "occurred_at":
            time.time(),
        "payload": {
            "value": i,
        },
    }

    subscribers = r.publish(
        CHANNEL,
        json.dumps(event),
    )

    print(
        "published",
        i,
        "subscribers",
        subscribers,
    )

    time.sleep(0.5)
```

------------------------------------------------------------------------

# Part 45 --- Run Basic Lab

## 49. Terminal 1

``` bash
python chapter31_subscriber.py
```

## 50. Terminal 2

``` bash
python chapter31_publisher.py
```

Observe live delivery.

------------------------------------------------------------------------

# Part 46 --- Fan-Out Lab

## 51. Multiple Subscribers

Start three subscriber processes.

Run the publisher.

Confirm all connected subscribers receive the publications.

This demonstrates broadcast fan-out.

------------------------------------------------------------------------

# Part 47 --- Disconnect Lab

## 52. Procedure

1.  Start subscriber.
2.  Publish events 0-4.
3.  Stop subscriber.
4.  Publish events 5-9.
5.  Restart subscriber.
6.  Publish events 10-14.

Expected:

``` text
subscriber sees 0-4
subscriber misses 5-9
subscriber sees 10-14
```

This is the most important Pub/Sub reliability lab.

------------------------------------------------------------------------

# Part 48 --- Pattern Subscription Lab

## 53. Subscribe

``` redis
PSUBSCRIBE tutorial.chapter31.*
```

Publish to:

``` text
tutorial.chapter31.orders
tutorial.chapter31.cache
tutorial.chapter31.notifications
```

Observe matched channel delivery.

------------------------------------------------------------------------

# Part 49 --- Broad Pattern Test

## 54. Demonstrate

Compare:

``` text
tutorial.chapter31.orders.*
```

with:

``` text
tutorial.*
```

Observe how broad patterns can unexpectedly increase traffic.

------------------------------------------------------------------------

# Part 50 --- Slow Consumer Lab

## 55. Add Delay

In the subscriber processing loop:

``` python
time.sleep(0.25)
```

Publish faster than the subscriber processes.

Observe:

``` text
processing delay
application queue behavior
memory
connection stability
```

Do this only in a disposable lab.

------------------------------------------------------------------------

# Part 51 --- Bounded Queue Subscriber

## 56. Pattern

``` python
import queue
import threading

work = queue.Queue(
    maxsize=100
)


def worker():
    while True:
        event = work.get()

        try:
            # bounded application work
            pass
        finally:
            work.task_done()


threading.Thread(
    target=worker,
    daemon=True,
).start()
```

The receive loop must define what happens when the queue is full.

Possible policies:

``` text
drop best-effort event
disconnect/fail
degrade
switch architecture
```

There is no universal safe choice.

------------------------------------------------------------------------

# Part 52 --- Large Message Lab

## 57. Test Sizes

In a disposable environment test:

``` text
1 KB
10 KB
100 KB
1 MB
```

Measure:

``` text
publisher latency
network
subscriber CPU
subscriber memory
fan-out cost
```

Do not use large payload stress tests against shared production Redis.

------------------------------------------------------------------------

# Part 53 --- Reconnect Lab

## 58. Controlled Failure

In a disposable environment:

``` text
disconnect network or restart Redis
observe subscriber error
restore service
observe reconnect/resubscribe
```

Record:

``` text
disconnect duration
reconnect duration
messages published during outage
reconciliation requirement
```

------------------------------------------------------------------------

# Part 54 --- Reconciliation Lab

## 59. Version Check

Simulate authoritative state:

``` text
current version = 10
subscriber last observed = 7
```

After reconnect, detect:

``` text
version gap
```

and reload current authoritative state.

This converts Pub/Sub from a correctness mechanism into a low-latency
notification path with reconciliation.

------------------------------------------------------------------------

# Part 55 --- Failure Injection

## 60. Failure 1 --- Subscriber Offline

Publish while subscriber is disconnected.

Verify the event is not replayed by Pub/Sub.

------------------------------------------------------------------------

## 61. Failure 2 --- Slow Consumer

Make subscriber processing slower than publication.

Observe pressure.

------------------------------------------------------------------------

## 62. Failure 3 --- Large Messages

Publish large payloads to many subscribers.

Observe network multiplication.

------------------------------------------------------------------------

## 63. Failure 4 --- Broad Pattern

Use an overly broad pattern subscription.

Observe unexpected traffic.

------------------------------------------------------------------------

## 64. Failure 5 --- Reconnect Storm

Restart many subscriber replicas simultaneously.

Observe connection/subscription spike.

Use staggered deployment/reconnect backoff where appropriate.

------------------------------------------------------------------------

## 65. Failure 6 --- Malformed Message

Publish invalid JSON.

Subscriber should:

``` text
record decode error
avoid crash loop
continue safely
```

according to policy.

------------------------------------------------------------------------

## 66. Failure 7 --- Unsupported Event Version

Publish:

``` json
{
  "event_version": 999
}
```

Consumer should reject or route according to compatibility policy.

------------------------------------------------------------------------

## 67. Failure 8 --- Runaway Publisher

Publish at an excessive rate.

Observe:

``` text
network
subscriber processing
queue depth
```

Apply publisher/producer controls.

------------------------------------------------------------------------

## 68. Failure 9 --- All Pods Subscribe

Scale subscriber deployment significantly.

Observe fan-out multiplication.

Verify whether every replica truly needs every message.

------------------------------------------------------------------------

## 69. Failure 10 --- Incorrect Durability Assumption

Build a test that expects a disconnected consumer to recover missed
Pub/Sub messages.

Demonstrate failure.

Then redesign using:

``` text
reconciliation
Redis Streams
durable external messaging
```

as appropriate.

------------------------------------------------------------------------

# Part 56 --- Troubleshooting

## 70. Subscriber Receives Nothing

Check:

``` text
channel name
environment prefix
subscription confirmation
Redis endpoint
network
ACL/access
publisher channel
```

------------------------------------------------------------------------

## 71. Some Messages Missing

Check:

``` text
subscriber disconnects
deployments
network interruptions
Redis failover
application queue drops
consumer exceptions
```

Remember that Pub/Sub does not replay disconnected intervals.

------------------------------------------------------------------------

## 72. Subscriber Memory Growing

Check:

``` text
internal queue
processing rate
message size
publisher rate
worker count
```

Do not allow unlimited queueing.

------------------------------------------------------------------------

## 73. Network High

Check:

``` text
message bytes
messages/sec
subscriber count
pattern subscriptions
duplicate subscribers
```

Fan-out multiplies network.

------------------------------------------------------------------------

## 74. CPU High in Subscribers

Check:

``` text
JSON decoding
large payloads
business processing
logging
compression
```

Keep the receive loop lightweight.

------------------------------------------------------------------------

## 75. Reconnect Loop

Check:

``` text
Redis availability
DNS
TLS
credentials
network
client retry policy
```

Use bounded backoff/jitter.

------------------------------------------------------------------------

## 76. Unexpected Cross-Tenant Events

Check:

``` text
channel naming
pattern subscriptions
application authorization
tenant derivation
```

Treat this as a data-isolation/security issue where applicable.

------------------------------------------------------------------------

## 77. Duplicate Business Actions

Check surrounding:

``` text
publisher retries
reconciliation
multiple subscribers
application processing
```

Pub/Sub broadcast means multiple subscribers receiving the same message
is expected.

------------------------------------------------------------------------

# Part 57 --- Production Runbooks

## 78. Runbook --- Missing Pub/Sub Events

``` text
1. Confirm expected channel.
2. Check subscriber connection history.
3. Check deployment/failover timeline.
4. Check application queue drops.
5. Identify missed time window.
6. Reconcile authoritative state.
7. Restore subscription.
8. Verify future delivery.
9. Determine whether loss is acceptable.
10. Move to durable messaging if required.
```

------------------------------------------------------------------------

## 79. Runbook --- Slow Subscriber

``` text
1. Measure receive rate.
2. Measure processing rate.
3. Measure queue depth.
4. Measure message size.
5. Identify expensive handlers.
6. Bound queue.
7. Increase safe processing capacity.
8. Reduce message size/rate if possible.
9. Evaluate Streams/durable queue.
10. Confirm stable processing.
```

------------------------------------------------------------------------

## 80. Runbook --- Pub/Sub Network Spike

``` text
1. Measure publish rate.
2. Measure message size.
3. Count subscribers.
4. Check broad patterns.
5. Identify runaway publisher.
6. Rate-limit if necessary.
7. Reduce payload.
8. Remove unnecessary subscribers.
9. Monitor Redis/network.
10. Update capacity model.
```

------------------------------------------------------------------------

## 81. Runbook --- Subscriber Reconnect Storm

``` text
1. Identify reconnect trigger.
2. Count subscriber replicas.
3. Measure Redis connections.
4. Stop tight reconnect loops.
5. Add backoff/jitter.
6. Stagger deployment/restart.
7. Confirm resubscription.
8. Reconcile missed state.
9. Verify connection headroom.
10. Document recovery behavior.
```

------------------------------------------------------------------------

## 82. Runbook --- Pub/Sub Used for Durable Requirement

``` text
1. Identify required delivery guarantee.
2. Identify replay requirement.
3. Identify acknowledgment requirement.
4. Identify outage recovery requirement.
5. Stop assuming Pub/Sub provides durability.
6. Select Streams or approved durable broker.
7. Design migration.
8. Run dual-path validation if needed.
9. Cut consumers safely.
10. Retire incorrect Pub/Sub dependency.
```

------------------------------------------------------------------------

# Part 58 --- Messaging Design Template

## 83. Fields

``` text
Use case:
Channel:
Publisher:
Subscribers:
Environment:
Tenant model:
Message schema:
Event version:
Average bytes:
P99 bytes:
Messages/sec:
Subscriber count:
Fan-out bytes/sec:
Loss acceptable:
Replay required:
ACK required:
Ordering required:
Reconnect behavior:
Reconciliation:
Queue bound:
Rate limit:
Security/ACL:
Metrics:
Owner:
```

------------------------------------------------------------------------

# Part 59 --- Pub/Sub Decision Guide

## 84. Good Fit

Consider Pub/Sub when:

``` text
live delivery matters
consumers are expected to be connected
missed events are acceptable or recoverable
broadcast semantics are desired
no durable backlog is required
```

------------------------------------------------------------------------

## 85. Poor Fit

Prefer another mechanism when:

``` text
every event must be processed
consumer acknowledgment is required
offline consumers must catch up
replay is required
durable backlog is required
competing consumers are required
```

------------------------------------------------------------------------

# Part 60 --- Capacity Worksheet

## 86. Estimate

``` text
messages/sec:
average message bytes:
P99 message bytes:
subscribers/message:
publisher ingress bytes/sec:
subscriber delivery bytes/sec:
subscriber connections:
reconnect peak:
client processing capacity:
```

Approximate:

``` text
delivery bytes/sec
≈
messages/sec
× average bytes
× average subscriber fan-out
```

------------------------------------------------------------------------

# Production Acceptance Checklist

## 87. Pub/Sub Engineering

-   [ ] Pub/Sub use case documented.
-   [ ] Message-loss semantics accepted.
-   [ ] Durable replay requirement explicitly reviewed.
-   [ ] Channel naming standardized.
-   [ ] Environment isolation reviewed.
-   [ ] Tenant isolation reviewed.
-   [ ] Message schema versioned.
-   [ ] Average/P99 message size measured.
-   [ ] Publish rate measured.
-   [ ] Subscriber count measured.
-   [ ] Fan-out capacity estimated.
-   [ ] Subscriber connections included in connection budget.
-   [ ] Slow-consumer behavior tested.
-   [ ] Application queue bounded.
-   [ ] Disconnect behavior tested.
-   [ ] Reconnect/resubscribe tested.
-   [ ] Reconnect backoff/jitter tested.
-   [ ] Missed-message reconciliation defined where needed.
-   [ ] Pattern subscriptions reviewed.
-   [ ] Large-message behavior tested.
-   [ ] Malformed-message handling tested.
-   [ ] Unsupported-version handling tested.
-   [ ] Security/ACL model reviewed.
-   [ ] Pub/Sub vs. Streams decision documented.
-   [ ] Production runbooks validated.

------------------------------------------------------------------------

# Knowledge Validation

## 88. Questions

You should be able to answer:

1.  What is Redis Pub/Sub?
2.  What is a channel?
3.  What is fan-out?
4.  Is Pub/Sub a durable queue?
5.  What happens to messages published while a subscriber is
    disconnected?
6.  When is Pub/Sub a good fit?
7.  When is Redis Streams a better fit?
8.  Why does a subscriber need long-lived connection handling?
9.  Why include subscriber connections in capacity planning?
10. Why standardize channel names?
11. Why is a channel prefix not a security boundary?
12. What does `PSUBSCRIBE` do?
13. Why can broad patterns be dangerous?
14. Why version message schemas?
15. Why should message size be bounded?
16. How does subscriber count affect network?
17. What is a slow consumer?
18. Why bound the subscriber's internal queue?
19. Why should the receive loop remain lightweight?
20. What must reconnect logic do?
21. Does reconnect recover missed Pub/Sub messages?
22. What is reconciliation?
23. Does a `PUBLISH` subscriber count prove business processing?
24. Does plain Pub/Sub provide consumer acknowledgments?
25. Why can Kubernetes replicas multiply fan-out?
26. Why is Pub/Sub not a competing-consumer queue?
27. Which publisher metrics should be monitored?
28. Which subscriber metrics should be monitored?
29. Why test reconnect storms?
30. What must pass before Pub/Sub is production-ready?

------------------------------------------------------------------------

# Hands-On Acceptance Checklist

## 89. Lab Completion

-   [ ] Created subscriber.
-   [ ] Created publisher.
-   [ ] Published versioned events.
-   [ ] Verified live delivery.
-   [ ] Started multiple subscribers.
-   [ ] Verified fan-out.
-   [ ] Disconnected subscriber.
-   [ ] Published during disconnect.
-   [ ] Verified missed-message behavior.
-   [ ] Reconnected subscriber.
-   [ ] Tested pattern subscription.
-   [ ] Tested broad-pattern risk.
-   [ ] Tested slow consumer.
-   [ ] Reviewed bounded queue.
-   [ ] Tested multiple message sizes.
-   [ ] Tested reconnect behavior.
-   [ ] Reviewed reconciliation.
-   [ ] Injected malformed message.
-   [ ] Injected unsupported version.
-   [ ] Tested runaway publisher.
-   [ ] Tested subscriber scale-out.
-   [ ] Completed ten failure scenarios.
-   [ ] Completed troubleshooting.
-   [ ] Reviewed five production runbooks.
-   [ ] Completed messaging design template.
-   [ ] Completed capacity worksheet.
-   [ ] Completed production acceptance checklist.

------------------------------------------------------------------------

# 90. Lab Cleanup

Pub/Sub channels themselves do not create persistent channel data that
requires key deletion.

If supporting Chapter 31 lab keys were created, discover only the
isolated namespace:

``` bash
redis-cli --scan --pattern 'tutorial:chapter31:*'
```

Delete only confirmed lab keys in bounded batches using `UNLINK`.

Do not use:

``` redis
KEYS tutorial:chapter31:*
FLUSHDB
FLUSHALL
```

against a shared or production database.

Stop disposable subscriber/publisher processes after the lab.

------------------------------------------------------------------------

# 91. Key Takeaways

1.  Redis Pub/Sub is a lightweight real-time broadcast mechanism.
2.  Pub/Sub is not a durable message queue.
3.  Messages published while a subscriber is disconnected are not
    automatically replayed.
4.  Use reconciliation when Pub/Sub is only a fast notification path for
    authoritative state.
5.  Use Streams or another durable broker when backlog, replay, or
    acknowledgments are required.
6.  Subscriber connections are long-lived and must be included in
    connection budgets.
7.  Channel naming, environment isolation, and tenant design must be
    intentional.
8.  Pattern subscriptions can unexpectedly increase traffic.
9.  Message size multiplied by fan-out can create major network load.
10. Slow subscribers need bounded processing queues and explicit
    overload behavior.
11. Keep subscriber receive loops lightweight.
12. Reconnect logic needs bounded backoff, jitter, and resubscription.
13. Reconnect does not recover messages missed during the outage.
14. Plain Pub/Sub does not provide business acknowledgments or
    dead-letter queues.
15. Kubernetes replicas can multiply subscriber fan-out dramatically.
16. Pub/Sub broadcast semantics differ from competing-consumer queue
    semantics.
17. Version message schemas and reject incompatible formats explicitly.
18. Observe publisher rate, subscriber processing, queue depth,
    reconnects, and bytes.
19. Failure testing must include subscriber disconnects and reconnect
    storms.
20. Production readiness starts by proving that Pub/Sub's delivery
    semantics actually match the business requirement.

------------------------------------------------------------------------

# 92. References

Validate exact Pub/Sub, sharded Pub/Sub, ACL, topology, client
reconnect, and subscription behavior against the Redis, Redis
Enterprise, and client-library versions deployed.

Recommended official Redis documentation areas:

-   Redis Pub/Sub
-   `PUBLISH`
-   `SUBSCRIBE`
-   `PSUBSCRIBE`
-   Redis sharded Pub/Sub
-   Redis ACLs and Pub/Sub permissions
-   Redis Streams
-   Redis client connections
-   Redis latency monitoring
-   Redis Enterprise monitoring
-   redis-py Pub/Sub

------------------------------------------------------------------------

# Next Chapter

**Chapter 32 --- Redis Streams, Consumer Groups & Durable Event
Processing**

Chapter 32 will cover:

-   Streams data model
-   `XADD`
-   stream IDs
-   `XREAD`
-   consumer groups
-   `XGROUP`
-   `XREADGROUP`
-   acknowledgments
-   pending entries
-   `XPENDING`
-   recovery
-   claiming abandoned work
-   trimming
-   retention
-   consumer lag
-   idempotency
-   poison messages
-   failure injection
-   observability
-   troubleshooting
-   production runbooks
-   acceptance validation
