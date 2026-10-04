# 22 — Advanced Indexes and Retention

**Status:** Draft; live lab not run.

**Objective:** Select specialized indexes and operate retention safely.

| Index | Use | Constraint |
|---|---|---|
| Multikey | Array values | Compound indexes restrict multiple indexed array fields per document |
| Partial | Index matching subset | Query must imply filter for eligible complete results |
| Unique | Business-key enforcement | Existing duplicates; missing/null and sharding rules matter |
| TTL | Background date-based expiration | Not exact-time deletion or backup retention |
| Wildcard | Variable field paths | Not a substitute for workload-specific indexes |
| Text/geospatial | Specialized query operators | Type/operator-specific limitations |

## Partial-index lab

Use an unused staging collection:
```javascript
var indexDb = db.getSiblingDB("mongodb_tutorials")
indexDb.createCollection("tutorial_advanced_indexes")
indexDb.tutorial_advanced_indexes.insertMany([
  { _id: "index-active", status: "active", email: "active@example.test" },
  { _id: "index-closed", status: "closed", email: "closed@example.test" }
])
indexDb.tutorial_advanced_indexes.createIndex(
  { email: 1 },
  { name: "active_email", partialFilterExpression: { status: "active" } }
)
indexDb.tutorial_advanced_indexes.find({
  status: "active", email: "active@example.test"
}).explain("queryPlanner")
```

A tiny collection may still choose a scan. Compare a query without status: partial coverage cannot supply every matching record. Do not force a partial index for a query requiring excluded records.

## TTL lab

Only in this dedicated collection:
```javascript
indexDb.tutorial_advanced_indexes.createIndex(
  { expiresAt: 1 }, { name: "lab_expiry", expireAfterSeconds: 0 }
)
indexDb.tutorial_advanced_indexes.insertOne({
  _id: "index-expiring", expiresAt: new Date(Date.now() - 60000)
})
indexDb.tutorial_advanced_indexes.findOne({ _id: "index-expiring" })
```

Poll later: deletion is asynchronous and load-dependent. Other lab records have no date and are not TTL candidates. TTL uses single-field indexes; time-series retention has additional version-specific behavior. Shortening retention can create a large deletion workload.

## Operations

Before uniqueness changes, inspect duplicates and missing fields; validate collation/partial rules and sharded unique-key constraints. Estimate build memory/disk/write overhead. Validate with representative explain and workload; hidden indexes retain maintenance cost and unique enforcement.

Cleanup only if the collection was newly created for this exercise:
```javascript
indexDb.tutorial_advanced_indexes.drop()
```

## References

- [Indexes](https://www.mongodb.com/docs/manual/indexes/)
- [Partial indexes](https://www.mongodb.com/docs/manual/core/index-partial/)
- [TTL](https://www.mongodb.com/docs/manual/core/index-ttl/)
- [Multikey](https://www.mongodb.com/docs/manual/core/indexes/index-types/index-multikey/)

**Next:** [23 — Change Streams and Event Recovery](23-change-streams-and-event-recovery.md).
