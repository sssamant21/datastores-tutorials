# 21 — Advanced Modeling and Schema Evolution

**Status:** Draft; live lab not run.

**Objective:** Choose embedding/references and migrate schemas safely.

## Access-pattern decisions

| Pattern | Appropriate use | Risk |
|---|---|---|
| Embed | Bounded related data read/updated together | Growth and duplicated values |
| Reference | Independent lifecycle or large relationships | Extra reads/joins and consistency work |
| Subset | Keep frequently read subset near parent | Synchronization of duplicate fields |
| Bucket | Group bounded related measurements | Bucket growth/write contention |
| Computed value | Precompute costly summaries | Staleness and repair procedure |

Document size has a 16 MiB limit. Avoid unbounded arrays and repeated large payloads. Record which duplicated values are historical snapshots versus values that must track the source. References do not enforce foreign keys automatically.

## Schema evolution lab

Use a dedicated regular collection in staging:
```javascript
var modelDb = db.getSiblingDB("mongodb_tutorials")
var modelId = new ObjectId()
modelDb.tutorial_model.insertOne({
  _id: modelId, schemaVersion: 1, fullName: "Taylor Morgan"
})
modelDb.tutorial_model.updateOne(
  { _id: modelId, schemaVersion: 1 },
  { $set: { schemaVersion: 2, displayName: "Taylor Morgan" } }
)
modelDb.tutorial_model.findOne({ _id: modelId })
```

Expected: both old and new fields remain during compatibility rollout. This is an explicit one-record example, not a generic name-parsing migration.

## Production migration

1. Define v1/v2 rules, BSON types, reader compatibility and rollback needs.
2. Deploy readers accepting both versions.
3. Update writers to emit v2, maintaining temporary compatibility where needed.
4. Backfill in bounded batches with version predicates and progress checkpoints.
5. Verify counts, invariants and sampled records.
6. Tighten validators after compatibility is confirmed.
7. Remove legacy fields only after retention/rollback gates pass.

Plan indexes and capacity before backfill. Handle concurrent writes explicitly; version predicates help avoid overwriting changed documents. Monitor write rate, lag and disk. An incompatible validator can turn application writes into failures.

Cleanup:
```javascript
modelDb.tutorial_model.deleteOne({ _id: modelId })
```

**Evidence:** access-pattern table, bounded growth estimate, migration progress, failed records and rollback constraints.

## References

- [Data modeling](https://www.mongodb.com/docs/manual/data-modeling/)
- [Schema validation](https://www.mongodb.com/docs/manual/core/schema-validation/)
- [Limits](https://www.mongodb.com/docs/manual/reference/limits/)

**Next:** [22 — Advanced Indexes and Retention](22-advanced-indexes-and-retention.md).
