# 16 — Capacity and Shard Administration

**Status:** Draft

**Audience:** Redis Enterprise administrators, SREs, and DBREs.

## Capacity is multi-dimensional

Track memory, CPU, disk for persistence, network, connections, and license limits. Separate total database utilization from individual shard saturation.

A hot shard can evict keys or become CPU-bound while aggregate cluster metrics look acceptable. A single hot key is not automatically fixed by adding nodes.

## Scaling workflow

1. Record workload rate, payload sizes, latency, and per-shard resources.
2. Identify the actual bottleneck.
3. Select memory growth, additional shards, node capacity, or application changes.
4. Verify replication placement and failure capacity.
5. Apply the supported change in staging, then through the production maintenance process.
6. Compare post-change latency and distribution.

More shards add overhead. Resharding and migration can affect resources and latency; monitor during the operation. Check command and client compatibility before changing database topology.

## Lab

Use a bounded sample:
```redis
SET tutorial:capacity:sample "demo" EX 300
STRLEN tutorial:capacity:sample
MEMORY USAGE tutorial:capacity:sample
DEL tutorial:capacity:sample
```

Inspect per-shard memory/CPU in Enterprise monitoring. Estimate working-set capacity using measured key footprint and anticipated key counts, then account for replication and recovery according to platform accounting.

## Acceptance and references

Acceptance: demonstrated bottleneck, quantified headroom, healthy placement, and measured benefit after the change.

- [Memory and performance](https://redis.io/docs/latest/operate/rs/databases/memory-performance/)
- [Eviction policy](https://redis.io/docs/latest/operate/rs/databases/memory-performance/eviction-policy/)

**Next:** [17 — High Availability and Persistence](17-high-availability-and-persistence.md)
