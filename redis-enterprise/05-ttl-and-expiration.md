# 05 — TTL and Expiration

**Status:** Draft

**Objective:** Configure expiration and choose a TTL policy.

## TTL basics

Time to live defines when a key expires. A later read misses and the application can reload it. Expiration follows a deadline; eviction can remove entries earlier under memory pressure.

## Set and inspect expiration
```redis
SET tutorial:product:1001:v1 '{"name":"Keyboard","price":49.99}' EX 300
TTL tutorial:product:1001:v1
SET tutorial:short-cache "demo" PX 5000
PTTL tutorial:short-cache
EXPIRE tutorial:product:1001:v1 60
```

EX uses seconds, PX milliseconds. TTL returns remaining seconds, -1 for no expiration, and -2 for an absent key. PTTL reports milliseconds. EXPIRE applies a new remaining lifetime and returns 1 on success, 0 for a missing key.

GET does not extend TTL. Extending expiration does not refresh the source data.

## Policy choices

| Policy | Behavior | Consideration |
|---|---|---|
| Fixed | Expires after population | Predictable refresh window |
| Sliding | Application extends on access | Popular data may remain stale |
| Jitter | Varies TTL across entries | Spreads reload traffic |

Choose based on acceptable staleness and reload cost.

Example application jitter:
```python
import random

ttl_seconds = random.randint(240, 300)
redis_client.set(key, serialized_value, ex=ttl_seconds)
```

This stays within five minutes and spreads deadlines. It does not prevent concurrent reloads of one missing key.

## Common mistakes

No TTL can retain stale data indefinitely. Plain SET clears the previous TTL; use EX or deliberate KEEPTTL. HSET preserves existing key-level expiration. Too-short TTLs increase database reads; too-long TTLs increase staleness.

## Hands-on validation

In a test database:
```redis
SET tutorial:ttl:test "temporary" EX 10
TTL tutorial:ttl:test
GET tutorial:ttl:test
```

After more than ten seconds:
```redis
GET tutorial:ttl:test
TTL tutorial:ttl:test
```

Expect nil and -2. Clean up:
```redis
DEL tutorial:product:1001:v1 tutorial:short-cache tutorial:ttl:test
```

Completion: configure TTL, interpret results, and choose a policy.

## References

- [EXPIRE](https://redis.io/docs/latest/commands/expire/)
- [TTL](https://redis.io/docs/latest/commands/ttl/)

**Next:** [06 — Implementing Cache-Aside](06-implementing-cache-aside.md)
