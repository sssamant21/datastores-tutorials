# 8 — Memory Management and Eviction

**Status:** Draft

**Objective:** Choose eviction behavior and plan cache capacity.

**Prerequisite:** Connected test Redis Enterprise database; Python examples reuse the client from Tutorial 06.

## Expiration versus eviction

Expiration follows a key's TTL. Eviction removes eligible keys to make room under memory pressure. A cache entry may be evicted before its TTL ends.

## Policy choices

| Policy | Behavior | Suitable consideration |
|---|---|---|
| allkeys-lru | Evicts approximately least recently used keys | Rebuildable cache with recent-use locality |
| allkeys-lfu | Evicts approximately least frequently used keys | Rebuildable cache with frequently reused entries |
| volatile-lru | Considers expiring keys for LRU eviction | Requires eligible keys with TTL |
| volatile-ttl | Prefers eligible keys with short remaining TTL | Expiring datasets |
| noeviction | Rejects memory-growing writes at the limit | Applications that explicitly handle rejected writes |

Verify supported policies and the configured policy for your product version. Do not assume a default. A volatile policy may reject writes when no eligible keys remain.

Configure database limits and policy through Redis Enterprise management interfaces. Do not assume standalone CONFIG SET procedures apply.

## Inspect a sample

```redis
SET tutorial:memory:test '{"name":"Keyboard"}' EX 300
STRLEN tutorial:memory:test
MEMORY USAGE tutorial:memory:test
TTL tutorial:memory:test
```

STRLEN reports string payload bytes. MEMORY USAGE reports estimated memory attributable to the key, not total replicated cluster cost. Availability of diagnostic commands depends on version and permissions.

## Capacity planning

Estimate active key count × measured per-key footprint, then allow headroom for growth, overhead, replication, persistence, and recovery. Validate actual platform accounting rather than simply multiplying the database limit.

Inspect each shard: uneven distribution can trigger eviction on one shard before total database utilization reaches its limit.

## Hands-on validation

In an isolated test database, record the configured limit/policy and sample sizes. Observe memory before and after a small bounded dataset. An eviction stress test is optional and must use a disposable database with an explicit workload bound.

Cleanup:
```redis
DEL tutorial:memory:test
```

## Production practices and completion

Alert on shard memory trends, eviction rate, rejected writes, and hit-rate degradation. Avoid mixing irreplaceable data with freely evictable cache data under one allkeys policy.

Completion: explain policy selection, expiration versus eviction, and per-shard capacity risk.

## References

- [Enterprise eviction policy](https://redis.io/docs/latest/operate/rs/databases/memory-performance/eviction-policy/)
- [MEMORY USAGE](https://redis.io/docs/latest/commands/memory-usage/)

**Next:** [09 — Caching Performance](09-caching-performance.md)
