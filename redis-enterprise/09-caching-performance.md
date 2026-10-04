# 9 — Caching Performance

**Status:** Draft

**Objective:** Reduce request overhead without creating excessive load.

**Prerequisite:** Connected test Redis Enterprise database; Python examples reuse the client from Tutorial 06.

## Common causes of latency

| Cause | Improvement |
|---|---|
| New connection per request | Reuse a bounded connection pool |
| Sequential small requests | Use bounded pipelining |
| Large values or collections | Reduce payload and result size |
| Hot key or busy shard | Inspect per-shard CPU and access distribution |
| Excessive concurrency | Bound in-flight requests and batches |
| Expensive source reloads | Improve hit rate and control rebuilds |

Pipelining reduces round trips. It does not make expensive commands cheap or make a nontransactional batch atomic.

## Bounded pipeline example

Reuse cache from Tutorial 06 in a test environment:

```python
with cache.pipeline(transaction=False) as pipe:
    for product_id in range(1, 11):
        pipe.set(
            f"tutorial:performance:product:{product_id}",
            json.dumps({"id": product_id, "name": "Demo"}),
            ex=300,
        )
    results = pipe.execute()

assert len(results) == 10
assert all(result is True for result in results)
```

Ten entries is a teaching batch, not a universal optimum. Each SET applies its own TTL. If a connection fails, some writes may have succeeded; consider partial execution before retrying.

## Measure

Compare a small sequential workload with the equivalent pipeline using time.perf_counter. Record total duration, operation count, payload bytes, application p95/p99 latency, and shard CPU. Repeat at modest load to reduce measurement noise.

Measure under the same TLS, network, and dataset conditions. Do not run unbounded benchmarks on a shared production database.

## Validation and cleanup

Read one sample:
```redis
GET tutorial:performance:product:1
TTL tutorial:performance:product:1
```

Clean up exact lab keys:
```python
for product_id in range(1, 11):
    cache.delete(f"tutorial:performance:product:{product_id}")
```

## Production practices and completion

Bound pipeline sizes and connection counts; monitor tail latency during bulk jobs. A single hot key generally remains tied to one shard, so adding shards does not automatically solve it. Avoid claiming that additional node CPUs accelerate every individual command.

Completion: verify pipelined writes and compare measured performance without increasing collateral load.

## References

- [Pipelining](https://redis.io/docs/latest/develop/using-commands/pipelining/)
- [redis-py production usage](https://redis.io/docs/latest/develop/clients/redis-py/produsage/)

**Next:** [10 — Application Resilience](10-cache-failures-and-application-resilience.md)
