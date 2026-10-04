# 10 — Storage, WiredTiger, and Capacity Planning

**Status:** Draft

**Objective:** Distinguish memory, allocated storage and filesystem headroom.

**Prerequisite:** Monitoring access to self-managed MongoDB; checks are read-only.

## WiredTiger resources

Internal cache holds active storage-engine data. Filesystem cache reduces disk reads. Data/index files persist records; journal plus checkpoints support recovery. Cache belongs to the whole mongod, not one database. Process memory includes other allocations.

## Memory/cache inspection

Run on a mongod member:
```javascript
const status = db.serverStatus()
status.storageEngine
status.mem
status.wiredTiger.cache

status.wiredTiger.cache["maximum bytes configured"]
status.wiredTiger.cache["bytes currently in the cache"]
status.wiredTiger.cache["tracked dirty bytes in the cache"]
status.wiredTiger.cache["pages read into cache"]
status.wiredTiger.cache["pages written from cache"]
```

Compare counters over intervals. High cache utilization alone is not a problem; correlate eviction, dirty data, disk latency, queued work and application latency. Field availability varies by version.

## Database storage

```javascript
use mongodb_tutorials
db.runCommand({ dbStats: 1, scale: 1048576, freeStorage: 1 })
```

| Field | Meaning |
|---|---|
| dataSize | Logical uncompressed document size |
| storageSize | Allocated collection storage |
| indexSize | Allocated index storage |
| totalSize | Collection plus index storage |
| freeStorageSize | Collection space available for reuse |
| fsUsedSize / fsTotalSize | Filesystem usage/capacity where available |

Scaled sizes are MiB where scaling applies. Compression and reusable space prevent direct equivalence. Inspect relevant members/shards.

## Deletion and disk space

Deletion can free internal reusable space while filesystem allocation remains similar. Never manually delete WiredTiger or journal files.

Compact is a planned version-specific maintenance operation. It can reclaim eligible space, but impact and reclaimed capacity are not guaranteed. Do not use it as a default incident response.

## Planning

| Resource | Include |
|---|---|
| Disk capacity | Data/indexes, oplog, journal, history store, logs and maintenance headroom |
| Disk performance | IOPS, throughput and latency |
| Memory | Working set, cache, connections and other allocations |
| CPU | Queries, writes, compression, aggregation and replication |
| Network | Client, replication, backup and resync traffic |

For containers, verify effective limits rather than assuming host RAM. Leave memory outside WiredTiger.

Estimated days to threshold = (threshold capacity − current usage) / average daily growth. Bulk loads, builds and resync can invalidate a simple trend.

## Symptoms

Disk growth despite deletion: inspect reusable space and other files. Read latency: inspect indexes, working set and I/O. Write latency: inspect throughput, checkpoints, indexes and replication. OOM: inspect effective limit/cache/concurrency. History-store growth: inspect long operations, transactions and retention.

Low available execution tickets alone is not proof of overload; inspect queues and actual latency.

## Validation

Capture timestamp/version/member plus two cache/storage snapshots during a known window. Compare counter changes with host/container resources and app latency. Identify the actual constrained resource and estimate growth/maintenance headroom.

## References

- [WiredTiger](https://www.mongodb.com/docs/manual/core/wiredtiger/)
- [dbStats](https://www.mongodb.com/docs/manual/reference/command/dbStats/)
- [compact](https://www.mongodb.com/docs/manual/reference/command/compact/)

**Next:** 11 — Backup, Restore, and Recovery (planned).
