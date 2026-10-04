# 14 — Step-by-Step Slowness Troubleshooting

**Status:** Draft; live lab not run.

**Objective:** Identify query, workload, storage, replication and connection bottlenecks.

## Establish scope

Record environment/cluster, timestamp/timezone, application, DB/collection, reads/writes affected, normal/current P95/P99, errors and recent changes. Compare a similar healthy workload window. Separate pool wait, server selection, network, database execution and application processing in traces.

## Availability/resources

| Signal | Investigation |
|---|---|
| Missing primary/elections | Quorum, connectivity, restarts |
| CPU increase | Queries, scans, concurrency, aggregation |
| Disk latency/queues | Storage limits and competing jobs |
| Low free space | Data/index/log growth and backup activity |
| Replication lag | Secondary I/O, workload and network |
| Connection spike | Pools, churn and service scaling |

Correlate metrics. High CPU or full cache alone does not establish cause.

## Inspect active operations

Use an approved monitoring identity with inprog permission for all-user inspection:
```javascript
db.getSiblingDB("admin").aggregate([
  { $currentOp: { allUsers: true, idleConnections: false, idleSessions: false } },
  { $match: { active: true, secs_running: { $gte: 2 } } },
  { $sort: { secs_running: -1 } },
  { $limit: 20 },
  { $project: {
    _id: 0, host: 1, shard: 1, opid: 1, appName: 1, op: 1,
    ns: 1, secs_running: 1, waitingForLock: 1, planSummary: 1
  } }
], { maxTimeMS: 5000 })
```

Look for repeated operations, durations, scans and lock waiting. This snapshot can miss short frequent expensive queries. On mongos the default reports shard operations; use localOps: true separately for router-local operations. Idle transactions holding locks require a separate idleSessions: true inspection.

## Slow-query evidence

Start with existing diagnostic logs and application traces. Capture filter/sort/projection/limit, duration, returned records, docs/keys examined, app name and frequency. Correlate ingestion/maintenance.

Inspect configuration:
```javascript
db.getSiblingDB("mongodb_tutorials").getProfilingStatus()
```

Profiler changes add overhead and can capture sensitive data. Use a targeted short collection window when needed, restoring prior settings. Profiling is unavailable on mongos; use diagnostic logs there.

## Query plan

Inspect without executing:
```javascript
db.getSiblingDB("mongodb_tutorials").tutorial_products
  .find({ category: "accessories" }, { _id: 0, name: 1, price: 1 })
  .sort({ name: 1 }).limit(10).explain("queryPlanner")
```

Replace with the actual query shape. executionStats executes the query; use an appropriate maxTimeMS and account for load.

| Finding | Interpretation |
|---|---|
| COLLSCAN | Review selectivity, size and index suitability |
| Many examined/few returned | Inefficient filtering |
| Blocking sort | Index support and sort volume |
| Index scan slow | Scan volume, fetching, I/O and concurrency |

Explain ignores existing plan-cache entries; the application may use a different cached plan.

## Targeted mitigation

| Evidence | Action |
|---|---|
| Inefficient query | Narrow filters/results; review compound index |
| Ingestion overload | Reduce concurrency; backpressure |
| Storage saturation | Reduce competing I/O; suitable storage |
| Connection churn | Reuse clients; review pools |
| Lock contention | Long transactions/conflicts |
| Secondary lag | Fix member before shifting reads |

Review index-build resource impact during incidents. Identify ownership and consequences before cancelling operations.

## Verify/document

Confirm application latency/errors, throughput, resource pressure and replication recover. Record evidence, cause/hypothesis, mitigation, before/after metrics, remaining risk and permanent owner/action.

## References

- [$currentOp](https://www.mongodb.com/docs/manual/reference/operator/aggregation/currentOp/)
- [Explain results](https://www.mongodb.com/docs/manual/reference/explain-results/)
- [Profiler](https://www.mongodb.com/docs/manual/tutorial/manage-the-database-profiler/)

**Next:** [15 — Common Problems and Solutions](15-common-problems-and-solutions.md).
