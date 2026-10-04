# 21 — Observability, Dashboards and Alerts

**Status:** Draft

**Objective:** Connect application symptoms to database, shard, node, and source-database metrics.

## 1. Collect the right signals

| Layer | Signals |
|---|---|
| Application | Cache hits, misses, errors; p95/p99 latency; pool wait; retries |
| Database/proxy | Throughput, connections, command latency, rejected requests |
| Shard | CPU, memory, evictions, replica health |
| Node | CPU saturation, memory, persistence disk latency/capacity, network |
| Source database | Fallback QPS, concurrency, latency and errors |

Use stable cluster/database/shard identifiers and environment labels. Avoid key names, patient IDs, or request IDs as metric labels; use protected logs/traces for request correlation.

## 2. Integrate Prometheus and Grafana

1. Identify the Redis Software version and its supported monitoring endpoint.
2. Use the vendor monitoring guide to configure scraping, TLS trust, and access.
3. Confirm scrape success and expected cluster/database/shard coverage.
4. Import compatible dashboards or create panels using the release's metric reference.
5. Compare dashboard samples with Cluster Manager during the same time window.

Redis Software 8.0 introduces the generally available v2 metrics stream endpoint at https://<cluster_name>:8070/v2. Earlier monitoring paths and metric definitions differ. Do not paste old metric names into a new dashboard without checking definitions.

## 3. Dashboard layout

| Row | Panels |
|---|---|
| User impact | Request rate, errors, p95/p99, cache errors |
| Cache efficiency | Application hit rate, misses, source read rate |
| Capacity | Per-shard CPU/memory, evictions, write rejections |
| Availability | Node/shard health, replica warnings, failovers |
| Recovery | Persistence warnings, backup freshness, disk utilization |
| Clients | Connections, churn, pool waits, retries |

Interval hit rate = hits / (hits + misses). Report errors separately. Counter changes must account for resets. Do not average percentiles across shards; use histogram data or show individual latency series.

## 4. Alerts

| Condition | Action |
|---|---|
| Sustained application latency/error breach | Page service owner with dashboard and runbook |
| Cache errors with rising fallback traffic | Investigate availability and protect source |
| Shard memory growth plus evictions/rejections | Check policy, working set and headroom |
| Replica or node unhealthy | Assess reduced redundancy and failure capacity |
| Backup overdue / certificate nearing expiry | Route to operational owner |
| Scrape or series absent | Investigate monitoring gap; do not assume zero load |

Set thresholds and sustained durations from workload baselines and application SLOs. CPU thresholds must use the metric's documented units and normalization.

## 5. Logs and traces

Capture command category, duration, outcome, connection/pool wait, and source fallback span. Redact credentials and payloads. Correlate by timestamp and request trace without logging sensitive keys.

## Lab and acceptance

Generate a bounded test miss then hit using Tutorial 06. Verify application counters and source reads. Trigger a test alert in staging and confirm ownership, dashboard link, and recovery notification. No production notification is sent by this tutorial.

Acceptance: complete scrape coverage, meaningful panels, and demonstrated alert delivery/recovery.

## References

- [Enterprise monitoring](https://redis.io/docs/latest/operate/rs/monitoring/)
- [redis-py observability](https://redis.io/docs/latest/develop/clients/redis-py/observability/)

**Next:** [22 — Step-by-Step Troubleshooting](22-step-by-step-troubleshooting.md)
