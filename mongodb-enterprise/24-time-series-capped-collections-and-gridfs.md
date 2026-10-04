# 24 — Time Series, Capped Collections, and GridFS

**Status:** Draft; live lab not run.

**Objective:** Choose specialized storage by access pattern.

| Feature | Use | Operational consideration |
|---|---|---|
| Time series | Timestamped measurements grouped by metadata | Buckets, retention and release-specific restrictions |
| Capped collection | Fixed-size rolling buffer | Old records overwritten; not durable event history |
| GridFS | Chunked large files/streaming | Metadata plus chunks; full-file updates not atomic |

## Time-series lab

On staging, use an unused namespace:
```javascript
var specialDb = db.getSiblingDB("mongodb_tutorials")
specialDb.createCollection("tutorial_measurements", {
  timeseries: { timeField: "timestamp", metaField: "sensor", granularity: "seconds" },
  expireAfterSeconds: 86400
})
specialDb.tutorial_measurements.insertOne({
  timestamp: new Date(), sensor: { id: "lab-sensor" }, temperature: 21.5
})
specialDb.tutorial_measurements.find({ "sensor.id": "lab-sensor" }).limit(10)
specialDb.getCollectionInfos({ name: "tutorial_measurements" })
```

Expect a Date timestamp, stable sensor metadata and configured collection options. Retention is asynchronous; bucket behavior can retain measurements beyond the nominal age. Check deployed-version indexing, update, transaction and sharding restrictions. Do not directly edit system.buckets collections.

## Capped lab

Create only in a disposable namespace:
```javascript
specialDb.createCollection("tutorial_capped", { capped: true, size: 1048576 })
specialDb.tutorial_capped.insertOne({ message: "lab-only", at: new Date() })
specialDb.tutorial_capped.find().sort({ $natural: -1 }).limit(5)
```

Capped collections cannot be sharded or written in transactions. Concurrent inserts do not guarantee a global insertion ordering. Prefer ordinary collections with TTL when time retention and flexibility matter.

## GridFS exercise

Use the driver's GridFS API against a separate test bucket. Upload a synthetic file, retain its returned file ID, download it and compare a cryptographic checksum, then delete by that ID. Verify both metadata/chunk cleanup through the API. Record interrupted-upload/orphan handling and backup coverage for both collections. GridFS does not support multi-document transactions; use versioned uploads plus a current-version pointer for publication rather than in-place whole-file replacement. Compare database replication/backup cost with object storage.

Cleanup the two collections only if created by this lab:
```javascript
specialDb.tutorial_measurements.drop()
specialDb.tutorial_capped.drop()
```

## References

- [Time series](https://www.mongodb.com/docs/manual/core/timeseries-collections/)
- [Capped collections](https://www.mongodb.com/docs/manual/core/capped-collections/)
- [GridFS](https://www.mongodb.com/docs/manual/core/gridfs/)

**Next:** [25 — Enterprise Security and Key Management](25-enterprise-security-and-key-management.md).
