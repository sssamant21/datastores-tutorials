# 01 — Redis Enterprise Fundamentals

**Status:** Draft

**Objective:** Understand Redis Enterprise and its application caching use case.

## What is Redis Enterprise?

Redis is a fast data store commonly used for caching, sessions, and counters. For caching, it holds temporary copies while the source database remains authoritative.

Redis Enterprise adds managed clustering, sharding, replication, failover, persistence, security, and monitoring. The self-managed product is called Redis Software in current documentation.

## Core components

| Component | Purpose |
|---|---|
| Cluster | Group of nodes managed together |
| Node | Server hosting Redis and platform processes |
| Database | Application-facing database with its own endpoint and settings |
| Primary shard | Processes operations for part of the data |
| Replica shard | Copies primary shard data for availability |
| Proxy | Routes requests to appropriate shards |
| Endpoint | Database hostname and port |

Applications use the database endpoint. Adding nodes increases cluster capacity; a database's ability to use it depends on sharding and workload.

## Cache-aside flow

1. Application checks Redis.
2. On a hit, return cached data.
3. On a miss, read the source database.
4. Cache the result with a TTL and return it.

TTL means time to live. A 300-second TTL gives a five-minute expiration window.

## Hands-on example

Prerequisite: connect to an existing test database using Tutorial 02.
```redis
PING
SET tutorial:product:1001:v1 '{"name":"Keyboard","price":49.99}' EX 300
GET tutorial:product:1001:v1
TTL tutorial:product:1001:v1
DEL tutorial:product:1001:v1
```

Expect PONG, OK, the stored JSON string, and a remaining TTL before deletion.

## Availability and durability

Replication and failover support availability. RDB snapshots and AOF persistence support durability. Backups support recovery. Deletions can propagate to replicas; replication is not protection against accidental deletion.

For a rebuildable cache, consider how quickly the source database can safely repopulate it.

## Production practices and completion

Set TTLs, invalidate after source updates, and monitor latency, memory, evictions, and hit rate. Bound database fallback traffic. Separate databases on shared nodes still compete for resources.

Completion: explain the components, hit/miss flow, and basic cache commands.

## References

- [Redis Software](https://redis.io/docs/latest/operate/rs/)
- [Terminology](https://redis.io/docs/latest/operate/rs/references/terminology/)

**Next:** [02 — Connecting](02-connecting-to-redis-enterprise.md)
