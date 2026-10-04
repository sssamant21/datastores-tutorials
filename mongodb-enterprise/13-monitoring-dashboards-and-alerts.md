# 13 — Monitoring, Dashboards, and Alerts

**Status:** Draft; live lab not run.

**Objective:** Detect availability, performance, capacity and recovery problems early.

## Monitor the whole service

Use Ops Manager or existing metrics tooling with host/Kubernetes metrics and application telemetry. Compare incident and healthy windows under similar workload.

| Area | Signals |
|---|---|
| Application | P95/P99, errors, timeouts |
| Availability | Primary, member health, restarts |
| Workload | Read/write rates, connections |
| Replication | Lag, oplog window, elections |
| Storage | Free space, growth, IOPS, latency |
| WiredTiger | Cache, dirty bytes, eviction |
| Recovery | Snapshot age, failures, restore drills |
| Monitoring | Agent health, sample freshness |

## Three dashboards

Service health: application latency/errors, MongoDB availability, throughput, connections and elections.

Resources/replication: CPU, memory, free space, disk latency, cache activity, lag and oplog window per member. Sharded deployments include mongos, every shard replica set and config servers.

Backup/management: Agent connectivity, automation failures, backup state, last snapshot and recovery window. Display latest sample timestamps.

## Read-only exercise

Connect securely using an approved monitoring identity with required privileges, such as clusterMonitor. Run on a data-bearing mongod:
```javascript
var monitoringStatus = db.adminCommand({ serverStatus: 1 })
printjson({
  host: monitoringStatus.host,
  sampledAt: monitoringStatus.localTime,
  uptimeSeconds: monitoringStatus.uptime,
  connections: monitoringStatus.connections,
  operationCounters: monitoringStatus.opcounters,
  operationLatency: monitoringStatus.opLatencies
})
printjson(monitoringStatus.wiredTiger?.cache)
```

Fields vary by version/process. Statistics are process-local and cumulative counters reset on restart.

On a replica-set member, not mongos:
```javascript
var monitoringReplica = db.adminCommand({ replSetGetStatus: 1 })
printjson(monitoringReplica.members.map(member => ({
  name: member.name,
  health: member.health,
  state: member.stateStr,
  appliedTime: member.optimeDate,
  heartbeatMessage: member.lastHeartbeatMessage
})))
```

This is the responding member's heartbeat-derived view and can be delayed. Capture two samples about one minute apart. Rate = counter difference / elapsed seconds. Discard intervals crossing a restart or different host. opLatencies totals/counts do not directly provide application P95/P99.

## Actionable alerts

These are starting examples, not universal thresholds:

| Condition | Example policy | First action |
|---|---|---|
| No writable primary | Page after election grace period | Topology, quorum, connectivity |
| Replication lag | Warn above 30s for 5 minutes | Writes, disk, secondary health |
| Disk usage | Warn 75%, critical 85%; adjust for growth | Free bytes/time to exhaustion |
| Backup stale | Expected schedule missed | Job/storage |
| Missing metrics | Several collection intervals missed | Agent/collector |
| Application latency | Sustained SLO violation | Queries, load, resources |

Include environment/resource, duration, owner and runbook. Ops Manager supports conditions, thresholds and notifications. Acknowledgement pauses notifications during its period; it does not fix the condition.

## Interpretation mistakes

| Observation | Interpretation |
|---|---|
| Cache nearly full | Correlate eviction, reads and latency |
| Connections high | Separate current gauge from cumulative created count |
| Operation counts rising | Calculate rates against demand |
| Metrics missing | Health unknown |
| Old applied timestamp | Compare primary position; idle workloads can have old timestamps |

Completion: identify user impact, affected member, freshness and alert owner.

## References

- [serverStatus](https://www.mongodb.com/docs/manual/reference/command/serverStatus/)
- [replSetGetStatus](https://www.mongodb.com/docs/manual/reference/command/replSetGetStatus/)
- [Ops Manager alerts](https://www.mongodb.com/docs/ops-manager/current/tutorial/nav/alerts/)

**Next:** [14 — Step-by-Step Slowness Troubleshooting](14-step-by-step-slowness-troubleshooting.md).
