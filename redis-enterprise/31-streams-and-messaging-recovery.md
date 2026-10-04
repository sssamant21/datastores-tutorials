# 31 — Streams and Messaging Recovery

**Status:** Draft; live lab not run.

**Objective:** Consume events, acknowledge durable processing and recover abandoned work.

Streams retain ordered entries; groups track deliveries and pending entries. Pub/Sub delivers to connected subscribers without comparable retained-history recovery. Select deliberately. Verify stream command support for the database version/topology, especially Active-Active.

## Consumer-group lab

Use an unused key/group on a staging database:
```redis
XGROUP CREATE tutorial:stream:orders lab-group 0 MKSTREAM
XADD tutorial:stream:orders * orderId lab-1001 status created
XREADGROUP GROUP lab-group consumerA COUNT 1 STREAMS tutorial:stream:orders >
XPENDING tutorial:stream:orders lab-group
```

Copy the returned entry ID. After durable synthetic processing:
```redis
XACK tutorial:stream:orders lab-group <entry-id>
XPENDING tutorial:stream:orders lab-group
```
Replace placeholder before execution. Expect acknowledgement 1 and pending count 0. ACK removes pending tracking, not the stored stream entry.

## Recovery exercise

Add/read another entry without ACK. After the lab idle interval, where XAUTOCLAIM is supported:
```redis
XAUTOCLAIM tutorial:stream:orders lab-group consumerB 1000 0-0 COUNT 1
```
Inspect returned entries and continuation cursor; process idempotently, then ACK the actual ID. Production idle thresholds must exceed expected processing time; claiming too early creates concurrent processing. Repeat cursor-based recovery with bounded work.

## Delivery and retention

Crash after downstream success but before ACK can cause duplicate processing. Use business/event deduplication and durable result handling; groups alone do not provide exactly-once effects. Define poison-message retries and a durable dead-letter path before ACKing failures. Monitor backlog/oldest pending age, retries and consumer health.

Trimming may remove payloads still needed by consumers. Set retention from outage/recovery requirements; MAXLEN approximation is not an exact ceiling. Missing/deleted pending payloads need reconciliation. Protect queue data from unsuitable eviction and validate persistence/backup.

Cleanup only this disposable stream (removes its groups/data):
```redis
DEL tutorial:stream:orders
```

## References

- [XREADGROUP](https://redis.io/docs/latest/commands/xreadgroup/)
- [XAUTOCLAIM](https://redis.io/docs/latest/commands/xautoclaim/)

**Next:** [32 — JSON and Search](32-json-and-search.md).
