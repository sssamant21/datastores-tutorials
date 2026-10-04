# 11 — Monitoring and Troubleshooting

**Status:** Draft

**Objective:** Use application and Redis metrics to investigate cache problems.

**Prerequisite:** Connected test Redis Enterprise database; Python examples reuse the client from Tutorial 06.

## Metrics

| Metric | What it helps explain |
|---|---|
| Application hits/misses/errors | Cache usefulness and failures |
| End-to-end p95/p99 latency | User impact |
| Redis command latency | Server processing contribution |
| Per-shard CPU and memory | Hotspots and capacity |
| Evictions / rejected writes | Memory pressure and policy |
| Connections / pool wait | Client saturation |
| Source query rate and latency | Miss/fallback impact |

For an interval, application hit rate = hits / (hits + misses) × 100. Exclude cache errors and report them separately. Server keyspace hits/misses may include other clients and commands; they are not necessarily identical to application cache hit rate.

## Read-only checks

Where supported and permitted:
```redis
PING
INFO stats
INFO memory
INFO clients
SLOWLOG GET 10
TYPE tutorial:catalog:product:1001:v1
TTL tutorial:catalog:product:1001:v1
```

Do not assume a proxy's INFO output provides complete cluster-wide or per-shard visibility. Use Redis Enterprise metrics and management dashboards to confirm scope.

Slowlog measures command execution time rather than the full application/network journey. It may contain command arguments; handle output as sensitive evidence.

## Incident sequence

1. Record time window, database, endpoint, affected services, and recent changes.
2. Compare application latency, error rate, hit rate, and source traffic.
3. Check each shard's CPU, memory, eviction, and write-error trends.
4. Inspect connection/pool pressure and bounded slowlog evidence.
5. Correlate with batch jobs, deployments, or source updates.
6. Apply a targeted fix and compare the same metrics afterward.

## Symptom mapping

| Symptom | Investigate |
|---|---|
| Hit rate drops | TTL changes, eviction, key naming/version changes |
| High app latency, low command latency | Network, pool waits, retries, source fallback |
| One shard busy | Hot keys, large values, uneven distribution |
| Writes fail near memory limit | Policy and eligible keys |
| Stale values | Invalidation failures, races, extended TTL |
| WRONGTYPE | Key collision or incompatible commands |

## Validation and completion

Capture two snapshots over a known interval; use counter deltas rather than lifetime totals. Account for resets and restarts. Confirm the sample key type and TTL, and distinguish network latency from command execution.

Completion: produce an incident note with evidence, scope, action, and post-fix comparison.

## References

- [Enterprise monitoring](https://redis.io/docs/latest/operate/rs/monitoring/)
- [INFO](https://redis.io/docs/latest/commands/info/)
- [SLOWLOG GET](https://redis.io/docs/latest/commands/slowlog-get/)

**Next:** [12 — Production Readiness and Lab](12-production-readiness-and-end-to-end-lab.md)
