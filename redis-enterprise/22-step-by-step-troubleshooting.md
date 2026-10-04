# 22 — Step-by-Step Troubleshooting

**Status:** Draft

**Objective:** Investigate Redis Enterprise latency, failures, or cache misses in a repeatable order.

## Step 1 — Define impact

Record start/end timestamps and timezone, cluster/database/endpoint, affected services, latency/error change, and recent deployments or batch jobs. Determine whether one service, one database, or multiple databases are affected.

Save evidence before changes; do not reset counters or flush data to diagnose a problem.

## Step 2 — Check connectivity from the application network

Use Tutorial 02's verified-TLS connection with the application's identity. Run:

```redis
PING
```

| Result | Next check |
|---|---|
| DNS error | Endpoint spelling and resolver |
| Timeout | Routing, firewall, VPN and server reachability |
| Refused | Assigned port and database availability |
| TLS failure | CA, hostname, expiry, mutual TLS requirements |
| WRONGPASS / NOPERM | Identity, secret deployment and scope |

PONG proves a lightweight operation, not full workload health. Avoid credential-bearing diagnostic URLs.

## Step 3 — Separate latency sources

Compare application p95/p99, Redis command latency, network round-trip behavior, pool wait, retries, and source query latency. Low command latency with high application latency points toward client/network/fallback investigation, not proof of a Redis processing bottleneck.

## Step 4 — Inspect database, shards and nodes

Use Enterprise monitoring to check CPU/memory distribution, evictions, rejected writes, replica health, node health, persistence disk pressure and ongoing migrations. Aggregate headroom can hide a saturated shard.

Where supported and authorized:

```redis
INFO stats
INFO memory
INFO clients
SLOWLOG GET 10
```

INFO through a proxy may have limited scope. SLOWLOG execution durations are in microseconds and exclude full network/client time. Inspect a bounded result and redact command arguments.

## Step 5 — Inspect representative keys

For a known non-sensitive key:
```redis
TYPE tutorial:catalog:product:1001:v1
TTL tutorial:catalog:product:1001:v1
MEMORY USAGE tutorial:catalog:product:1001:v1
```

Check wrong type, absent/expired key, unexpectedly missing TTL, or large value. Inspect application key construction and serialization. A sample is not a cluster-wide diagnosis.

Avoid KEYS *, unbounded collection reads, and continuous MONITOR during an incident. If scanning is necessary, use a bounded supported scan workflow with an explicit scope and rate.

## Step 6 — Choose evidence-based mitigation

| Evidence | Mitigation |
|---|---|
| Batch load coincides with CPU/latency | Reduce batch size/concurrency; pause the job through its owner |
| Eviction and hit-rate collapse | Review working set, policy and shard capacity |
| Pool saturation | Fix connection leaks/churn and size bounded concurrency |
| Cache errors and source overload | Limit fallback; use established circuit-breaker policy |
| One hot key/shard | Reduce payload/work and redesign access pattern |
| Replica/node failure | Follow supported recovery workflow; preserve healthy capacity |

Do not restart nodes or change eviction policy without understanding current redundancy and data requirements.

## Step 7 — Verify and record

Compare equal pre/post windows for latency, errors, hit rate, source load, evictions, and shard health. Confirm recovery is sustained rather than a short dip.

Incident note: impact, observed evidence, likely cause with confidence, mitigation, measured result, unresolved items, and prevention owner.

## Lab and acceptance

Use a staging TTL mismatch or isolated denied-permission scenario. Follow the sequence and show which evidence identifies it. No disruptive production fault injection is required.

## References

- [Troubleshooting](https://redis.io/docs/latest/operate/rs/troubleshooting/)
- [INFO](https://redis.io/docs/latest/commands/info/)
- [SLOWLOG GET](https://redis.io/docs/latest/commands/slowlog-get/)

**Next:** [23 — Common Problems and Solutions](23-common-problems-and-solutions.md)

**Enterprise slowlog note:** Redis Software does not return the client IP, port, or client name in SLOWLOG GET output. Use application traces or protected client logs for attribution; do not assume the standalone response format. See [command compatibility](https://redis.io/docs/latest/commands/slowlog-get/).
