# 23 — Common Problems and Solutions

**Status:** Draft

**Objective:** Match common symptoms to evidence, remediation, and validation.

## Problem reference

| Problem | Confirm with | Solution | Verify |
|---|---|---|---|
| Connection timeout | DNS/network path, application timeout logs, endpoint health | Fix route/firewall/endpoint; bound retries | Connection succeeds from application network |
| Authentication/permission error | WRONGPASS/NOPERM, deployed secret and identity | Correct database user, secret or scope | Allowed operations succeed; denied scope stays denied |
| TLS failure | Certificate chain, hostname, expiry, client cert requirements | Renew/install trusted certificates and correct configuration | Verified TLS works; no verification bypass |
| High CPU during bulk writes | Job timestamps, batch size, per-shard CPU, latency | Reduce concurrency and bound batches/pipelines | Tail latency improves with acceptable job throughput |
| Memory-related write rejection | Shard memory, eviction policy, eligible keys | Fix TTL/policy where appropriate; reduce working set or add capacity | Writes succeed and headroom stabilizes |
| High evictions and low hit rate | Interval eviction rate, shard memory, application hit rate | Tune working set/TTL and capacity; inspect distribution | Hits recover without increasing staleness |
| Stale cache values | Source/cache mismatch, invalidation errors and races | Repair targeted entries and invalidation workflow | Source updates produce expected cache refresh |
| Frequent misses | TTL, key version/scope mismatch, eviction and errors | Correct key construction and freshness policy | Source reads and misses decrease |
| WRONGTYPE | TYPE and application command usage | Align type/schema; retire incompatible keys deliberately | Correct operations work |
| Pool exhaustion | Pool wait, concurrent requests, leaks and churn | Reuse clients; fix leaks; bound workload and pool | Wait/errors fall without overload |
| Hot shard/key | Per-shard CPU and access distribution | Reduce expensive access/payload; redesign hot-key strategy | Hotspot and latency reduce |
| Large value/collection | MEMORY USAGE, STRLEN or bounded cardinality checks | Split by access pattern; limit payload/collection growth | Memory and command duration improve |
| Expiration stampede | Miss/source-QPS burst aligned with TTL | TTL jitter across keys plus same-key request coalescing | Concurrent source reload count is bounded |
| Source overload during Redis failure | Cache errors, fallback QPS, source saturation | Circuit breaker plus rate/concurrency limits and controlled rejection | Source stays within capacity |
| Slow failover recovery | Client reconnect/retry behavior, replica health, capacity | Repair redundancy; tune bounded recovery; rehearse supported failover | Measured recovery meets requirements |
| Backup/restore failure | Job status, artifacts, destination access, compatibility | Fix access/capacity/version issues; repeat isolated restore | Validated restored data and measured recovery time |

## Targeted examples

### Missing expiration

```redis
TTL tutorial:problem:no-ttl
EXPIRE tutorial:problem:no-ttl 300
```

TTL -1 means no expiration. EXPIRE is a fix only if this key is intended to be temporary; never add arbitrary TTLs to authoritative data.

### Wrong type

```redis
TYPE tutorial:problem:record
```

Use the commands appropriate to the intended schema. Do not blindly delete an unfamiliar production key.

### Targeted stale-entry repair

After confirming the source is updated and invalidation is appropriate:
```redis
DEL tutorial:problem:stale
```

Subsequent application reads should repopulate it. Deletion can cause a reload burst, so coordinate repairs for hot or numerous keys.

## Prevention

Maintain owners, TTL/type conventions, bounded workloads, per-shard alerts, invalidation repair, staging failover tests, and restore evidence. Each incident should produce a concrete preventive change with an owner and acceptance measure.

## Hands-on exercise

In a test database:
```redis
SET tutorial:problem:no-ttl "demo"
TTL tutorial:problem:no-ttl
EXPIRE tutorial:problem:no-ttl 60
TTL tutorial:problem:no-ttl
HSET tutorial:problem:record name "Demo"
EXPIRE tutorial:problem:record 60
GET tutorial:problem:record
TYPE tutorial:problem:record
HGET tutorial:problem:record name
DEL tutorial:problem:no-ttl tutorial:problem:record
```

Expect -1 before expiry is applied, positive TTL afterward, WRONGTYPE from GET on the hash, type hash, then value Demo from HGET.

Acceptance: diagnose both deliberate issues, apply targeted remedies, and clean up only lab keys.

## References

- [Enterprise troubleshooting](https://redis.io/docs/latest/operate/rs/troubleshooting/)
- [Eviction policy](https://redis.io/docs/latest/operate/rs/databases/memory-performance/eviction-policy/)
- [EXPIRE](https://redis.io/docs/latest/commands/expire/)
