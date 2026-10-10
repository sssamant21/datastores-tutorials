# 03 — Server Architecture and WiredTiger

**Status:** Written; static review complete; runtime lab validation pending  
**Part:** 1 — Foundations and Architecture  
**Goal:** Trace a database operation through mongod and collect interpretable storage-engine evidence.  
**Audience:** Developers, DBREs, SREs and Platform Engineers  
**Time:** 60–90 minutes  
**Baseline:** MongoDB 8.0; record actual server and mongosh patch versions.  
**Deployment:** Self-managed Community or Enterprise mongod; standalone or replica set. The optional restart lab uses only the disposable standalone container.

## 1. From application request to storage

An application driver manages connections and sends commands. The database process authenticates the request, checks authorization, selects an execution plan and performs reads or writes through the storage engine. It also returns results and maintains operational metrics.

In a replica set, the primary normally handles writes and replicates operations through the oplog. Read preference determines where eligible reads are sent. In a sharded deployment, mongos routes work to the relevant shards. A mongos process is not a WiredTiger data node.

| Layer | Responsibility | First evidence |
|---|---|---|
| Driver | Pooling, server selection and request timeouts | Application timings and driver logs |
| Connection and authorization | Admit and authorize commands | Authentication errors and connection metrics |
| Query execution | Plan and execute operations | Explain plans and query logs |
| Storage engine | Retrieve/update pages and manage concurrency | WiredTiger metrics and execution queues |
| Host or container | Supply CPU, memory and storage | Resource limits, I/O latency and throttling |
| Replica set | Replication and elections | Member state, lag and oplog window |

A slow application request can include time before the database receives it and after the database finishes it. Correlate the same operation and time window across layers.

## 2. WiredTiger concepts

WiredTiger is the default storage engine for this track's normal mongod deployments. Its internal cache holds data needed for database operations; the operating system also caches filesystem data. The configured WiredTiger cache limit is not a total process-memory limit.

A high cache occupancy percentage alone does not establish an incident. Look at workload latency, eviction activity, dirty data, storage behavior and operation queues together. Metrics differ across versions; preserve the exact server version when comparing nodes.

Checkpointing and journaling have different roles. A checkpoint establishes a consistent recovery point in data files. The journal records modifications between checkpoints for recovery. A journaled acknowledgement is a durability setting, not proof that a separate replica has received the write.

Compression changes storage and CPU tradeoffs. Logical data size, allocated storage size, process memory and filesystem space are different quantities. Do not infer one from another.

Document-level concurrency lets unrelated writes proceed concurrently, but a hot document can still create contention. Long-running work may retain history or consume resources even when it is not holding an obvious exclusive collection lock.

## 3. What not to infer from one statistic

| Observation | Possible meaning | Evidence needed |
|---|---|---|
| Cache near capacity | Working cache is being used | Eviction behavior, read I/O and latency |
| Dirty bytes increased | Writes accumulated in cache | Subsequent trend, checkpoint activity and I/O |
| Disk storage exceeds logical size | Allocation, indexes or compression effects | Collection statistics and filesystem inspection |
| Low available execution tickets | Dynamic concurrency control is operating | Queued operations and latency |
| More page reads after restart | A colder database/process cache | Host cache, workload and query pattern |
| Write acknowledged | Requested acknowledgement was met | Actual write concern and topology |

Do not tune concurrency or cache simply to make a chart appear less busy. Later chapters develop sustained workload analysis and capacity planning.

## 4. Lab prerequisites and connection

Use synthetic data in **mongodb_enterprise_tutorial_ch03**. The account needs collection creation, CRUD, index creation and cleanup permissions. It also needs authorized access to serverStatus, getCmdLineOpts and collection statistics for the inspection exercises. If those commands are restricted, record the inspection as unavailable rather than marking it passed.

For an existing training mongod:

```bash
mongosh "mongodb://127.0.0.1:27017"
```

For a secured environment, use the approved URI, TLS CA and prompted password from Chapter 01. Do not direct the restart exercise at a shared deployment.

Optional isolated container, with its own port to avoid Chapter 01/02 conflicts:

```bash
docker run --name mongodb-ch03 --detach --publish 127.0.0.1:27033:27017 --memory 2g mongo:8.0 --wiredTigerCacheSizeGB 0.5
docker exec -it mongodb-ch03 mongosh
```

The cache value is a lab setting, not a production sizing recommendation. Docker's memory limit covers more than WiredTiger cache. This container has no authentication or persistent volume; its lifecycle is intentionally temporary.

Record actual versions:

```bash
mongosh --version
docker inspect mongodb-ch03 --format '{{.Image}}'
```

The Docker inspection applies only if you created the container.

## 5. Inspect the actual process

Inside mongosh:

```javascript
var admin = db.getSiblingDB("admin");
var topology = admin.runCommand({ hello: 1 });
if (topology.msg === "isdbgrid") {
  throw new Error("Connect to an authorized training mongod for this storage-engine lab");
}
printjson({ version: db.version(), setName: topology.setName,
  writable: topology.isWritablePrimary });

var options = admin.runCommand({ getCmdLineOpts: 1 });
if (options.ok !== 1) throw new Error("Configuration inspection failed");
printjson({
  storage: options.parsed.storage,
  replication: options.parsed.replication
});

var status = admin.runCommand({ serverStatus: 1 });
if (status.ok !== 1 || status.storageEngine.name !== "wiredTiger") {
  throw new Error("Expected WiredTiger mongod");
}
printjson({
  version: status.version,
  process: status.process,
  storageEngine: status.storageEngine,
  connections: status.connections,
  memory: status.mem
});
```

Expected: mongod and wiredTiger. For the optional container, parsed options should reflect a 0.5 GiB cache setting. Unspecified default settings need not appear in parsed options. Inspect the effective cache maximum in the next section.

Configuration outputs may reveal paths or deployment details. Capture only the needed fields in incident records.

## 6. Prepare a bounded workload

Create 2,000 small documents and an index. The fixture is sufficient to observe metric changes, not to stress a real deployment.

```javascript
var lab = db.getSiblingDB("mongodb_enterprise_tutorial_ch03");
if (lab.getCollectionNames().includes("events")) {
  throw new Error("Existing chapter resources; review cleanup first");
}
lab.createCollection("events");

function check(ok, message) {
  if (!ok) throw new Error(message);
}

var docs = [];
for (var i = 0; i < 2000; i++) {
  docs.push({
    _id: i,
    accountId: "A" + (i % 20),
    sequence: i,
    payload: "synthetic-" + "x".repeat(256),
    revision: 0
  });
}
var inserted = lab.events.insertMany(docs);
check(inserted.acknowledged, "Insert must be acknowledged");
check(lab.events.countDocuments({}) === 2000, "Expected 2000 documents");
lab.events.createIndex({ accountId: 1, sequence: 1 });
```

Expected: 2,000 records and an account/sequence compound index. Indexes consume storage and affect writes; later chapters examine index design in depth.

## 7. Capture snapshots and calculate deltas

Define a small sampling function:

```javascript
function sampleStorage() {
  var s = admin.runCommand({ serverStatus: 1 });
  check(s.ok === 1 && s.wiredTiger && s.wiredTiger.cache,
    "WiredTiger metrics unavailable");
  var cache = s.wiredTiger.cache;
  return {
    sampledAt: new Date(),
    uptime: s.uptime,
    currentBytes: cache["bytes currently in the cache"],
    maxBytes: cache["maximum bytes configured"],
    dirtyBytes: cache["tracked dirty bytes in the cache"],
    pagesRead: cache["pages read into cache"],
    pagesWritten: cache["pages written from cache"],
    opcounters: s.opcounters,
    executionQueues: s.queues ? s.queues.execution : null
  };
}
var before = sampleStorage();
printjson(before);
```

Metric names are selected from the 8.0 serverStatus response. If a field is missing, investigate the release and permissions; do not silently substitute zero.

Execute repeated reads and one update batch:

```javascript
for (var pass = 0; pass < 5; pass++) {
  var rows = lab.events.find({ accountId: "A1" })
    .sort({ sequence: 1 }).limit(50).toArray();
  check(rows.length === 50, "Expected 50 rows in each bounded read");
}
var changed = lab.events.updateMany(
  { accountId: "A1" }, { $inc: { revision: 1 } }
);
check(changed.matchedCount === 100 && changed.modifiedCount === 100,
  "Expected 100 changed documents");

var after = sampleStorage();
check(after.uptime >= before.uptime, "Unexpected process restart");
check(typeof after.maxBytes === "number" && after.maxBytes > 0,
  "Expected positive cache capacity");
printjson({
  cacheOccupancyPercent: 100 * after.currentBytes / after.maxBytes,
  dirtyBytes: after.dirtyBytes,
  pagesReadDelta: after.pagesRead - before.pagesRead,
  pagesWrittenDelta: after.pagesWritten - before.pagesWritten,
  queryCounterDelta: after.opcounters.query - before.opcounters.query,
  updateCounterDelta: after.opcounters.update - before.opcounters.update,
  executionQueues: after.executionQueues
});
```

Page deltas may be zero because the tiny fixture is already cached. Server counters include other activity and command-accounting rules; they are not a count of only this lab's documents. The assertions verify fixture behavior rather than demanding a fabricated metric increase.

For production rates, sample a known interval and divide a counter delta by elapsed seconds. Reject intervals that span a process restart or contain invalid counter values.

## 8. Compare data, storage and index sizes

```javascript
var collectionStats = lab.runCommand({ collStats: "events", scale: 1 });
check(collectionStats.ok === 1, "Collection statistics failed");
printjson({
  count: collectionStats.count,
  logicalBytes: collectionStats.size,
  storageBytes: collectionStats.storageSize,
  indexBytes: collectionStats.totalIndexSize,
  indexes: collectionStats.nindexes
});
check(collectionStats.count === 2000, "Statistics count mismatch");
check(collectionStats.nindexes === 2, "Expected _id plus compound index");
```

The command is used here for the 8.0 lab; version-specific alternatives such as $collStats should be evaluated for monitoring integrations. Exact byte values depend on compression, allocation and timing.

A database delete does not necessarily reduce filesystem usage immediately. Internally reusable storage and free filesystem blocks are different. Avoid deleting WiredTiger files manually to reclaim space.

## 9. Failure exercise — client-side routing assumption

A storage collector must not treat mongos or a restricted response as a successful WiredTiger sample.

The sampler above explicitly fails when the expected cache object is absent. Reproduce that guard without changing the server:

```javascript
function requireWiredTigerMetrics(response) {
  check(response.ok === 1 && response.wiredTiger &&
    response.wiredTiger.cache, "Missing WiredTiger cache metrics");
}
var wrongTargetRejected = false;
try {
  requireWiredTigerMetrics({ ok: 1, process: "mongos" });
} catch (e) {
  wrongTargetRejected = true;
  print(e.message);
}
check(wrongTargetRejected, "Collector must reject a wrong process response");
requireWiredTigerMetrics(admin.runCommand({ serverStatus: 1 }));
print("PASS: collector rejects missing metrics and accepts actual training mongod metrics");
```

This is a collector-contract exercise. It does not deploy a sharded cluster or demonstrate real mongos routing. In production, attach node/process identity to every sample and route collectors to the intended targets.

## 10. Optional graceful restart and journaled sentinel

Run only on the disposable **mongodb-ch03** container. This exercise verifies persistence across a graceful restart, not crash recovery, replication durability or backup restoration.

Inside mongosh:

```javascript
var marker = lab.events.insertOne(
  { _id: "journal-marker", marker: "survives-graceful-restart" },
  { writeConcern: { w: 1, j: true, wtimeout: 5000 } }
);
check(marker.acknowledged, "Journaled marker write failed");
```

Exit the shell, then use the terminal:

```bash
docker restart --timeout 30 mongodb-ch03
docker exec -it mongodb-ch03 mongosh
```

A new shell session requires new variables:

```javascript
var lab = db.getSiblingDB("mongodb_enterprise_tutorial_ch03");
if (lab.events.findOne({ _id: "journal-marker" }) === null) {
  throw new Error("Marker missing after restart");
}
if (lab.events.countDocuments({}) !== 2001) {
  throw new Error("Unexpected count after restart");
}
print("PASS: marker survives graceful restart");
```

The same container retains its writable layer across restart. Removing it without a volume removes the lab data. This is why a restart test is not a backup.

## 11. Troubleshooting

| Symptom | Evidence | Action |
|---|---|---|
| No WiredTiger object | Process identity, command result and privileges | Connect to authorized mongod and verify monitoring access |
| Cache full-looking chart | Latency, eviction, dirty data, I/O and queues | Investigate correlations before tuning |
| Process memory exceeds cache maximum | Resident memory, OS/container limit | Budget other process and filesystem memory |
| Cache maximum unexpected | Effective metrics and parsed config | Check the actual process configuration and container environment |
| Restart marker absent | Target/container identity and write result | Verify the same container and namespace were used |
| Disk remains used after deleting documents | Collection and filesystem statistics | Distinguish reusable storage from released disk blocks |
| Counter delta negative | Uptime and restart evidence | Discard the invalid interval |
| Lab commands unauthorized | Failed command and scoped privileges | Record unavailable inspection or use authorized training access |

## 12. Cleanup and acceptance

Inside the current mongosh session:

```javascript
var cleanupDb = db.getSiblingDB("mongodb_enterprise_tutorial_ch03");
if (cleanupDb.getName() !== "mongodb_enterprise_tutorial_ch03") {
  throw new Error("Unexpected cleanup namespace");
}
cleanupDb.events.drop();
if (cleanupDb.getCollectionNames().includes("events")) {
  throw new Error("Cleanup failed");
}
print("PASS: Chapter 03 collection removed");
```

If you created the optional container:

```bash
docker stop mongodb-ch03
docker rm mongodb-ch03
```

- [ ] Record server/shell versions and process/topology.
- [ ] Confirm WiredTiger and effective cache maximum.
- [ ] Insert 2,000 records and verify the bounded reads and 100 updates.
- [ ] Capture before/after snapshots and explain zero or nonzero metric deltas.
- [ ] Verify two indexes and distinguish logical/storage/index bytes.
- [ ] Demonstrate the missing-metrics guard.
- [ ] Record optional restart as passed, failed or not performed.
- [ ] Verify cleanup.

**Validation record:** JavaScript syntax and documentation reviewed; no live MongoDB environment was available during authoring. Record actual environment, operator, date and assertion outputs after execution.

## 13. Production takeaways and review questions

Use multiple signals to diagnose a database bottleneck. Separate query cost, storage behavior, resource limits and replication requirements. A larger cache cannot repair every slow query, and a graceful restart does not validate disaster recovery.

1. Why is the cache maximum smaller than total process memory?
2. Why can a page-read delta remain zero during a successful read exercise?
3. What is the difference between a journaled write and replication acknowledgement?
4. Why does deletion not guarantee an immediate filesystem-space reduction?
5. Which evidence distinguishes a mongod sample from a mongos sample?

## Technical references

- [WiredTiger — 8.0](https://www.mongodb.com/docs/v8.0/core/wiredtiger/)
- [serverStatus — 8.0](https://www.mongodb.com/docs/v8.0/reference/command/serverStatus/)
- [getCmdLineOpts — 8.0](https://www.mongodb.com/docs/v8.0/reference/command/getCmdLineOpts/)
- [Journaling — 8.0](https://www.mongodb.com/docs/v8.0/core/journaling/)
- [Write concern — 8.0](https://www.mongodb.com/docs/v8.0/reference/write-concern/)
- [Collection statistics — 8.0](https://www.mongodb.com/docs/v8.0/reference/command/collStats/)

Previous: [Chapter 02 — Document Model and BSON Types](02-document-model-and-bson-types.md).  
Next: **Chapter 04 — Community Enterprise Advanced and Atlas** (planned).  
Return to the [master layout](MASTER-LAYOUT.md).
