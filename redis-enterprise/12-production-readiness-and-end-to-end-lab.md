# 12 — Production Readiness and End-to-End Lab

**Status:** Draft

**Objective:** Verify the caching lifecycle and assess application readiness.

**Prerequisite:** Connected test Redis Enterprise database; Python examples reuse the client from Tutorial 06.

## Lab setup

Use a test database and the client plus get_product function from Tutorial 06. Save those definitions in a local Python script; append the code below instead of Tutorial 06's demonstration.

The source dictionary simulates a database so behavior is observable. It is not a real database integration.

## End-to-end lab

```python
import time

source = {1001: {"id": 1001, "name": "Keyboard", "price": 49.99}}
source_reads = 0
key = "tutorial:catalog:product:1001:v1"


def fetch_source(product_id):
    global source_reads
    source_reads += 1
    record = source.get(product_id)
    return dict(record) if record is not None else None


cache.delete(key)

# Miss: load source and populate cache.
assert get_product(1001, fetch_source)["price"] == 49.99
assert source_reads == 1
assert cache.ttl(key) > 0

# Hit: avoid another source read.
assert get_product(1001, fetch_source)["price"] == 49.99
assert source_reads == 1

# Source update, then invalidation.
source[1001]["price"] = 44.99
cache.delete(key)
assert get_product(1001, fetch_source)["price"] == 44.99
assert source_reads == 2

# Expiration: force a short test TTL and reload.
cache.expire(key, 2)
time.sleep(3)
assert cache.get(key) is None
assert get_product(1001, fetch_source)["price"] == 44.99
assert source_reads == 3

# Simulated cache outage: exercise read-error fallback.
class UnavailableCache:
    def get(self, key):
        raise redis.exceptions.ConnectionError("Simulated outage")


original_cache = cache
try:
    cache = UnavailableCache()
    assert get_product(1001, fetch_source)["price"] == 44.99
    assert source_reads == 4
finally:
    cache = original_cache

cache.delete(key)
print("PASS: hit, miss, update, expiration, and fallback")

```

Expected: PASS when the database connection and permissions are correct. The outage is simulated; real network/failover behavior requires separate validation. This lab does not verify concurrency, invalidation races, circuit breakers, or fallback limits.

## Production readiness checklist

| Area | Acceptance evidence |
|---|---|
| Connection | Correct endpoint, verified TLS, least-privilege user, managed secrets |
| Key design | Service/tenant scope, payload version, bounded sizes |
| Freshness | Approved TTL and invalidation policy |
| Consistency | Race behavior documented; stronger protocol where required |
| Failure handling | Bounded timeouts, retries, source fallback, circuit breaker |
| Stampedes | Same-key concurrent reload protection tested |
| Memory | Per-shard headroom and eviction policy confirmed |
| Recovery | Refill rate protects source; recovery tested in staging |
| Observability | Hit/miss/error metrics, latency and capacity alerts |
| Ownership | Named owner, dashboard, runbook, rollback process |

Record pass/fail/pending for each item. Missing evidence remains pending; running this lab alone does not establish production readiness.

## Cleanup and completion

The script removes only its exact lab key. Verify GET returns nil afterward. Run staging integration and concurrency tests before declaring the application ready.

Tutorials 01–12 cover the application caching foundation. Continue with [13 — Cluster Administration](13-cluster-administration.md), then the administration and observability tracks.

## References

- [redis-py production usage](https://redis.io/docs/latest/develop/clients/redis-py/produsage/)
- [Enterprise monitoring](https://redis.io/docs/latest/operate/rs/monitoring/)
