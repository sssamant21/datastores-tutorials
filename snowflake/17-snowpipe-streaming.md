# 17 — Snowpipe Streaming

## Overview

Snowpipe Streaming provides low-latency ingestion of streaming data into Snowflake without requiring applications to first write data into staged files.

Traditional Snowpipe uses:

```text
Application
    |
    v
Files
    |
    v
Cloud Object Storage
    |
    v
Snowpipe
    |
    v
Snowflake Table
```

Snowpipe Streaming removes the file-staging requirement:

```text
Application / Streaming Platform
             |
             v
      Streaming Records
             |
             v
    Snowpipe Streaming
             |
             v
       Snowflake Table
```

This makes Snowpipe Streaming useful for workloads where records continuously arrive and must become available in Snowflake with low ingestion latency.

Typical sources include Kafka, application events, telemetry, IoT events, logs, CDC pipelines, microservices, and event-driven applications.

---

## 1. Snowpipe vs Snowpipe Streaming

| Feature | Snowpipe | Snowpipe Streaming |
|---|---|---|
| Input | Files | Records |
| Stage required | Yes | No |
| Cloud storage required | Normally yes | No staging requirement |
| Ingestion model | File-based | Row/record-based |
| Compute | Serverless | Serverless |
| Typical use | Continuous file ingestion | Continuous event ingestion |
| Latency | Low | Lower-latency streaming |
| File management | Required | Not required |

Think of the distinction as:

```text
Snowpipe: Files → Snowflake
Snowpipe Streaming: Records → Snowflake
```

---

## 2. Why Snowpipe Streaming Exists

Many modern systems generate events continuously: customer activity, application telemetry, API events, database CDC, device events, security events, and Kafka messages.

Without streaming ingestion, an upstream system may need to buffer events into files:

```text
Events → Buffer → Create files → Upload files → Snowpipe
```

That introduces file creation overhead, storage dependencies, additional latency, file lifecycle management, and more infrastructure.

Snowpipe Streaming allows applications to send records more directly into Snowflake.

---

## 3. High-Level Architecture

```text
Producer
   |
   v
Kafka / Application / CDC Platform
   |
   v
Snowpipe Streaming Client
   |
   v
Snowpipe Streaming Service
   |
   v
Snowflake Table
```

Snowflake manages the ingestion compute. Applications or supported connectors provide records to the streaming ingestion interface.

---

## 4. Core Concepts

Important concepts include Client, Channel, Record, Offset Token, and Target Table.

### Client

The client represents the application interacting with Snowpipe Streaming.

### Channel

A channel is a logical ingestion path associated with a target table.

```text
Client
  |
  +---- Channel A ----> TABLE_A
  |
  +---- Channel B ----> TABLE_B
```

### Record

A record contains data destined for the target Snowflake table.

### Offset Token

An offset token allows an application to associate ingestion progress with records. This is particularly useful for replay and recovery logic.

---

## 5. Channels

Channels are a critical Snowpipe Streaming concept. A channel represents an ordered stream of records sent to a target table.

```text
Kafka Partition 0 → Channel 0 → TARGET_TABLE
Kafka Partition 1 → Channel 1 → TARGET_TABLE
```

Applications should design channel naming carefully.

Example:

```text
orders-partition-000
orders-partition-001
orders-partition-002
```

Avoid meaningless names such as `channel1`, `channel2`, or `test`.

---

## 6. Offset Tokens

Offset tokens help track ingestion progress.

Suppose a Kafka consumer processes partition 3 offsets 1001, 1002, and 1003. The application can associate ingestion progress with an offset token.

The committed offset token can help determine what has successfully progressed through the ingestion channel.

This is valuable during application restart, consumer restart, failure recovery, replay, duplicate prevention, and checkpoint management.

Offset tokens are application-defined values and their semantics should be documented by the producer.

---

## 7. Kafka Integration Pattern

```text
Producer
   |
   v
Kafka Topic
   |
   +---- Partition 0
   +---- Partition 1
   +---- Partition 2
   |
   v
Kafka Connector / Streaming Client
   |
   v
Snowpipe Streaming
   |
   v
RAW.EVENTS
```

A good design can associate Kafka partitions with independent ingestion channels.

---

## 8. Raw Streaming Table Design

Streaming data should normally land first in a raw ingestion layer.

```sql
CREATE OR REPLACE TABLE raw.application_events (
    event_id        VARCHAR,
    event_type      VARCHAR,
    event_timestamp TIMESTAMP_NTZ,
    source          VARCHAR,
    payload         VARIANT,
    ingested_at     TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP()
);
```

This preserves original event identity, source event time, source system, raw payload, and Snowflake ingestion time.

---

## 9. Event Time vs Ingestion Time

Streaming systems should distinguish event timestamp from ingestion timestamp.

```sql
SELECT
    MAX(event_timestamp) AS latest_event,
    MAX(ingested_at) AS latest_ingestion
FROM raw.application_events;
```

This helps distinguish a source that stopped producing events from a source that produced events while ingestion is delayed.

---

## 10. Measure Ingestion Lag

```sql
SELECT
    MAX(event_timestamp) AS latest_event_time,
    MAX(ingested_at) AS latest_ingestion_time,
    DATEDIFF(
        'second',
        MAX(event_timestamp),
        MAX(ingested_at)
    ) AS approximate_ingestion_lag_seconds
FROM raw.application_events;
```

Clock differences between source systems and Snowflake can affect this metric. Monitoring should understand source clock synchronization, event buffering, connector buffering, and ingestion latency.

---

## 11. Semi-Structured Streaming Data

Streaming events frequently contain JSON.

```json
{
  "event_id": "evt-10001",
  "event_type": "ORDER_CREATED",
  "customer_id": 5012,
  "order_id": 90001,
  "amount": 129.95
}
```

A raw table can preserve the payload as VARIANT and downstream processing can extract fields.

```sql
SELECT
    event_id,
    payload:order_id::NUMBER AS order_id,
    payload:customer_id::NUMBER AS customer_id,
    payload:amount::NUMBER(12,2) AS amount
FROM raw.events;
```

---

## 12. Schema Evolution

Streaming producers change over time. A common pattern is:

```text
Streaming Event
      |
      v
RAW table with VARIANT
      |
      v
Validation / Transformation
      |
      v
Structured curated tables
```

This separates ingestion availability from downstream schema enforcement.

---

## 13. Duplicate Handling

Streaming systems must explicitly consider duplicate events from producer retries, consumer retries, connector restart, replay, upstream delivery semantics, or application failures.

Include a stable identifier such as `event_id`.

```sql
SELECT
    event_id,
    COUNT(*) AS occurrences
FROM raw.application_events
GROUP BY event_id
HAVING COUNT(*) > 1
ORDER BY occurrences DESC;
```

---

## 14. Idempotency

Where possible, producers should generate stable event identifiers rather than generating a new identifier every time the same logical event is retried.

Downstream processing can then reason about whether a logical event has already been processed.

---

## 15. Ordering

Do not assume global ordering across all streaming channels.

If ordering matters, define what ordering means: per customer, device, Kafka partition, transaction, or account. Design partitioning and channel strategy accordingly.

---

## 16. Backpressure

Streaming pipelines can experience situations where producers generate records faster than downstream components can process them.

This can cause growing Kafka lag, connector buffering, increased ingestion latency, memory pressure, retries, and downstream freshness degradation.

Monitor the entire pipeline rather than Snowflake alone.

---

## 17. End-to-End Monitoring

```text
Producer
   |
   v
Streaming Platform
   |
   v
Connector / Client
   |
   v
Snowpipe Streaming
   |
   v
Raw Table
   |
   v
Transformation
```

Important signals include producer event rate, Kafka consumer lag, connector errors/restarts, streaming ingestion errors, latest event timestamp, latest ingestion timestamp, duplicate rate, transformation lag, and target-table freshness.

---

## 18. Data Freshness Monitoring

```sql
SELECT
    CURRENT_TIMESTAMP() AS current_time,
    MAX(ingested_at) AS latest_ingestion,
    DATEDIFF(
        'second',
        MAX(ingested_at),
        CURRENT_TIMESTAMP()
    ) AS freshness_seconds
FROM raw.application_events;
```

If freshness exceeds the SLA, first determine whether no events are expected or events are expected but missing.

---

## 19. Troubleshooting Workflow

When streaming data stops appearing:

1. Is the producer generating events?
2. Are events reaching Kafka/source platform?
3. Is the consumer/connector running?
4. Is consumer lag increasing?
5. Are channels healthy?
6. Are ingestion errors occurring?
7. Are records reaching the raw table?
8. Are downstream transformations current?

Do not begin by modifying Snowflake tables. First determine the failure domain.

---

## 20. Producer Investigation

Check whether event volume dropped, a deployment occurred, credentials expired, the producer changed schemas/topics, or network connectivity changed.

If no events are being produced, Snowflake cannot ingest them.

---

## 21. Kafka Investigation

Inspect topic availability, partition health, producer errors, consumer group state, consumer lag, connector status, authentication, and network connectivity.

Rapidly growing consumer lag usually indicates that the downstream consumer is not keeping pace.

---

## 22. Connector Investigation

Check whether the connector is running or repeatedly restarting, whether authentication errors occur, whether records are rejected, whether configuration changed, whether source partitions are assigned, and whether throughput degraded.

Connector logs often provide direct evidence of a streaming ingestion failure.

---

## 23. Snowflake-Side Investigation

```sql
SELECT
    MAX(ingested_at),
    COUNT(*)
FROM raw.application_events;
```

Inspect a recent time window:

```sql
SELECT
    DATE_TRUNC('minute', ingested_at) AS minute,
    COUNT(*) AS records
FROM raw.application_events
WHERE ingested_at >= DATEADD('hour', -1, CURRENT_TIMESTAMP())
GROUP BY 1
ORDER BY 1 DESC;
```

A sudden drop can identify approximately when ingestion stopped.

---

## 24. Identify the Failure Window

```sql
SELECT
    DATE_TRUNC('minute', ingested_at) AS ingestion_minute,
    COUNT(*) AS records
FROM raw.application_events
WHERE ingested_at >= DATEADD('hour', -6, CURRENT_TIMESTAMP())
GROUP BY 1
ORDER BY 1;
```

Correlate changes with deployments, credential changes, Kafka incidents, network events, schema changes, and connector restarts.

---

## 25. Replay Strategy

Every production streaming architecture should define how missing data will be replayed.

Possible sources include Kafka retention, source database CDC logs, application event stores, object storage archives, and dead-letter queues.

A recovery design should answer:

- How far back can we replay?
- How do we identify the missing range?
- How do we prevent duplicates?
- How do we verify completeness?
- How do we know replay is finished?

Do not wait for an incident to design replay.

---

## 26. Dead-Letter Handling

Malformed or incompatible records should not silently disappear.

A robust architecture may route failed events to a dead-letter path.

Useful metadata includes event ID, source, source partition, source offset, failure timestamp, error reason, and original payload.

---

## 27. Production Architecture Pattern

```text
Applications
      |
      v
Kafka
      |
      v
Snowpipe Streaming
      |
      v
RAW.EVENTS
      |
      +----------------+
      |                |
      v                v
Validation          Monitoring
      |
      v
Deduplication
      |
      v
Transformation
      |
      v
CURATED TABLES
      |
      v
Applications / Analytics
```

Keep ingestion responsibilities separate from complex business transformations.

---

## 28. Snowpipe Streaming vs Batch Loading

Use batch loading when data naturally arrives in files, minutes or hours of latency are acceptable, ingestion windows are predictable, and simplicity is more important than low latency.

Use streaming when records continuously arrive, freshness requirements are tighter, upstream systems are event based, and file staging adds unnecessary latency.

Choose the simplest architecture that satisfies the business requirement.

---

## 29. Cost Considerations

Snowpipe Streaming uses Snowflake-managed ingestion resources.

```text
Serverless != Free
```

Evaluate cost alongside ingestion volume, event frequency, latency requirements, connector architecture, downstream transformation compute, and retention requirements.

---

## 30. Security

Production streaming ingestion should follow least privilege.

Separate ingestion, administration, transformation, and application/query identities.

Credentials should be securely stored, rotated, monitored, and appropriately scoped. Never embed long-lived secrets directly in source code.

---

## 31. Operational Runbook

When Snowpipe Streaming ingestion is delayed:

1. Confirm events are expected.
2. Confirm the producer is generating events.
3. Verify source topic/stream health.
4. Check producer errors.
5. Check consumer or connector health.
6. Measure consumer lag.
7. Inspect connector/client logs.
8. Check channel/ingestion state.
9. Check Snowflake for recent records.
10. Identify the exact failure window.
11. Check for schema changes.
12. Check authentication and connectivity.
13. Determine whether records require replay.
14. Validate duplicate handling before replay.
15. Replay the missing range.
16. Confirm target freshness has recovered.
17. Validate downstream transformations.
18. Document the failure domain and corrective action.

---

## 32. Production Best Practices

Use stable event IDs, meaningful channel names, an offset/checkpoint strategy, raw ingestion tables, event and ingestion timestamps, replay procedures, duplicate detection, a DLQ strategy, end-to-end freshness monitoring, consumer lag monitoring, least-privilege identities, and a schema-evolution strategy.

Avoid assuming streaming means exactly-once business processing, ignoring duplicates, depending only on Snowflake monitoring, mixing ingestion with complex business logic, operating without replay/DLQ strategies, assuming global ordering, ignoring source/connector lag, or using streaming where simple batch loading is sufficient.

---

## 33. Hands-On Lab

### Objective

Design and validate a production-style streaming ingestion architecture.

```sql
CREATE OR REPLACE TABLE raw.streaming_lab (
    event_id        VARCHAR,
    event_type      VARCHAR,
    event_timestamp TIMESTAMP_NTZ,
    payload         VARIANT,
    ingested_at     TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP()
);
```

Use a supported Snowpipe Streaming client or connector to ingest test records.

Verify:

```sql
SELECT *
FROM raw.streaming_lab
ORDER BY ingested_at DESC
LIMIT 20;
```

Check freshness:

```sql
SELECT
    MAX(event_timestamp) AS latest_event,
    MAX(ingested_at) AS latest_ingestion,
    DATEDIFF(
        'second',
        MAX(ingested_at),
        CURRENT_TIMESTAMP()
    ) AS freshness_seconds
FROM raw.streaming_lab;
```

Test duplicate detection:

```sql
SELECT
    event_id,
    COUNT(*) AS occurrences
FROM raw.streaming_lab
GROUP BY event_id
HAVING COUNT(*) > 1;
```

Finally, simulate a controlled interruption in a lab environment and verify that the connector/checkpoint/replay strategy can recover missing data.

---

## 34. Acceptance Criteria

The chapter is complete when you can:

- explain Snowpipe Streaming
- distinguish Snowpipe from Snowpipe Streaming
- explain why file staging is not required
- describe clients and channels
- explain offset tokens/checkpoints conceptually
- design Kafka-to-Snowflake streaming ingestion
- distinguish event time from ingestion time
- measure data freshness
- detect duplicate events
- explain ordering considerations
- identify consumer lag/backpressure
- design replay procedures
- design dead-letter handling
- troubleshoot the pipeline end to end
- explain security and cost considerations
- choose appropriately between batch, Snowpipe, and streaming ingestion

---

## Key Takeaways

Snowpipe Streaming changes the ingestion model from:

```text
Files → Snowflake
```

to:

```text
Records → Snowflake
```

Operate streaming ingestion as an end-to-end system:

```text
Producer
   ↓
Kafka / Event Platform
   ↓
Connector / Client
   ↓
Snowpipe Streaming
   ↓
Raw Table
   ↓
Transformation
   ↓
Consumer
```

Reliable streaming systems require identity, checkpointing, duplicate handling, replay, monitoring, and schema management.

Low latency alone does not make a streaming pipeline production ready.

The next chapter is **Chapter 18 — Streams & Change Data Capture**.
