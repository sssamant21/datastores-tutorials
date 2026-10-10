# 12 — Updates Upserts and Bulk Writes

**Status:** Written; static review complete; runtime lab validation pending  
**Part:** 2 — Data Modeling and Application Development  
**Goal:** Handle partial bulk success, replay desired-state updates and reconcile typed pipeline transformations.  
**Audience:** Developers, Data Engineers, DBREs and SREs  
**Time:** 90–120 minutes  
**Baseline:** MongoDB 8.0 with mongosh; record exact versions.  
**Deployment:** Core Community-compatible or Enterprise training deployment. Collection bulkWrite is used; no cross-namespace bulk command or transaction is exercised.

## 1. Bulk is a transport/execution choice

bulkWrite sends a group of operations to a collection. It is not automatically an all-or-nothing transaction. Some operations can succeed before another operation fails.

| Mode | Behavior after an ordinary write error | Appropriate dependency model |
|---|---|---|
| ordered true | Stops at the failing operation; preceding successes remain | Sequence matters, with explicit partial-success handling |
| ordered false | Continues other eligible operations; order is not guaranteed | Independent operations that can be reconciled separately |

Write concern errors and transaction behavior need their own interpretation. Do not assume an ordered batch means rollback, or that unordered execution means every operation succeeded.

Use stable source identifiers, unique keys and an operation manifest so errors can be reconciled to individual intended changes.

## 2. Updates and replay contracts

An operator update such as $set can express a desired state. $setOnInsert supplies creation-only fields during upsert. $inc expresses an additional change each time it executes.

Repeating a desired-state update with unchanged values can be harmless; repeating an increment as a new application operation increments again. Driver retryable-write semantics and an application's resubmission of a new operation are different.

A conditional source-version filter helps prevent an old event from overwriting newer state. Combining that filter with upsert needs care: when no document matches because the event is stale, upsert may try to insert a duplicate business key.

## 3. Lab prerequisites and setup

Use **mongodb_enterprise_tutorial_ch12** with collection creation, CRUD, index and cleanup permissions. Connect with the approved verified TLS/authentication pattern. Run JavaScript in one session.

```javascript
var lab = db.getSiblingDB("mongodb_enterprise_tutorial_ch12");
var names = ["ordered_demo", "unordered_demo", "records", "migration"];
if (names.some(name => lab.getCollectionNames().includes(name))) {
  throw new Error("Existing Chapter 12 resources");
}
names.forEach(name => lab.createCollection(name));
function check(ok, message) { if (!ok) throw new Error(message); }

["ordered_demo", "unordered_demo"].forEach(name => {
  lab.getCollection(name).createIndex({ businessKey: 1 }, { unique: true });
  lab.getCollection(name).insertOne({
    _id: "A", businessKey: "K1", status: "new"
  });
});
lab.records.createIndex({ externalId: 1 }, { unique: true });
```

The two bulk-demo collections start identically. The unique businessKey creates a deliberate, interpretable failure.

## 4. Define operations with one duplicate

```javascript
function failingBatch() {
  return [
    { insertOne: { document: { _id: "B", businessKey: "K2", status: "new" } } },
    { insertOne: { document: { _id: "DUP", businessKey: "K1", status: "duplicate" } } },
    { insertOne: { document: { _id: "C", businessKey: "K3", status: "new" } } },
    { updateOne: { filter: { _id: "A" }, update: { $set: { status: "done" } } } }
  ];
}
function captureBulkError(error) {
  var errors = error.writeErrors;
  if (!errors && error.result && typeof error.result.getWriteErrors === "function") {
    errors = error.result.getWriteErrors();
  }
  printjson({
    code: error.code,
    message: error.message,
    writeErrors: errors || [],
    partialResult: error.result || null
  });
}
```

Operation index 1 repeats K1 with a different _id. The unique business key, not just _id, must protect logical identity.

Error-object shape varies by driver/shell release. The lab verifies final state as well as inspecting the error.

## 5. Ordered partial success

```javascript
var orderedFailed = false;
try {
  lab.ordered_demo.bulkWrite(failingBatch(), { ordered: true });
} catch (e) {
  orderedFailed = e.code === 11000;
  captureBulkError(e);
}
check(orderedFailed, "Expected ordered duplicate-key failure");
check(lab.ordered_demo.countDocuments({}) === 2, "Expected A and B only");
check(lab.ordered_demo.findOne({ _id: "B" }) !== null, "Preceding insert must remain");
check(lab.ordered_demo.findOne({ _id: "C" }) === null, "Later insert must not run");
check(lab.ordered_demo.findOne({ _id: "A" }).status === "new", "Later update must not run");
check(lab.ordered_demo.findOne({ _id: "DUP" }) === null, "Duplicate insert rejected");
print("PASS: ordered bulk stops without rolling back preceding success");
```

A batch-level exception does not mean nothing happened. Retrying all inserts blindly would now collide with B.

## 6. Unordered continuation

```javascript
var unorderedFailed = false;
try {
  lab.unordered_demo.bulkWrite(failingBatch(), { ordered: false });
} catch (e) {
  unorderedFailed = e.code === 11000;
  captureBulkError(e);
}
check(unorderedFailed, "Expected unordered duplicate-key failure");
check(lab.unordered_demo.countDocuments({}) === 3, "Expected A, B and C");
check(lab.unordered_demo.findOne({ _id: "A" }).status === "done", "Independent update completed");
check(lab.unordered_demo.findOne({ _id: "DUP" }) === null, "Duplicate rejected");
print("PASS: unordered bulk completes other independent operations");
```

The operations are independent apart from the deliberate key conflict. Do not use unordered mode for a sequence whose later operation requires an earlier one to have succeeded.

Reconcile the ordered batch by applying only the known desired remainder:

```javascript
lab.ordered_demo.bulkWrite([
  { updateOne: {
    filter: { _id: "C" },
    update: { $setOnInsert: { businessKey: "K3", status: "new" } },
    upsert: true
  } },
  { updateOne: { filter: { _id: "A" }, update: { $set: { status: "done" } } } }
], { ordered: true });
check(lab.ordered_demo.countDocuments({}) === 3, "Reconciled ordered count");
check(lab.ordered_demo.findOne({ _id: "A" }).status === "done", "Reconciled status");
```

The duplicate request is classified, not retried. Production reconciliation uses actual operation IDs, source payloads and observed state rather than assuming all duplicate errors mean success.

## 7. Desired-state upserts and replay

```javascript
function desiredBatch() {
  return [
    { updateOne: {
      filter: { externalId: "E1" },
      update: {
        $set: { status: "active", amount: Decimal128("10.00"), sourceVersion: Int32(1) },
        $setOnInsert: {
          _id: "R1", createdAt: ISODate("2026-10-10T00:00:00Z"), processedCount: Int32(0)
        }
      },
      upsert: true
    } },
    { updateOne: {
      filter: { externalId: "E2" },
      update: {
        $set: { status: "active", amount: Decimal128("20.00"), sourceVersion: Int32(1) },
        $setOnInsert: {
          _id: "R2", createdAt: ISODate("2026-10-10T00:00:00Z"), processedCount: Int32(0)
        }
      },
      upsert: true
    } }
  ];
}
var initial = lab.records.bulkWrite(desiredBatch(), { ordered: false });
check(initial.upsertedCount === 2, "Expected two new records");
var replay = lab.records.bulkWrite(desiredBatch(), { ordered: false });
check(replay.matchedCount === 2 && replay.modifiedCount === 0,
  "Unchanged desired-state replay");
check(lab.records.countDocuments({}) === 2, "No duplicate logical records");
```

The unique externalId index protects logical identity. This is a sequential same-state replay test, not proof that all stale, concurrent or conflicting events are handled.

## 8. Version-aware update and incorrect upsert failure

Apply a newer source version without upsert:

```javascript
var newer = lab.records.updateOne(
  { externalId: "E1", sourceVersion: { $lt: Int32(2) } },
  { $set: { sourceVersion: Int32(2), amount: Decimal128("12.00") } }
);
check(newer.modifiedCount === 1, "Expected newer source version");
var stale = lab.records.updateOne(
  { externalId: "E1", sourceVersion: { $lt: Int32(1) } },
  { $set: { sourceVersion: Int32(1), amount: Decimal128("5.00") } }
);
check(stale.matchedCount === 0, "Stale source must not match");
```

Demonstrate the risk of adding upsert to that stale filter:

```javascript
var staleUpsertRejected = false;
try {
  lab.records.updateOne(
    { externalId: "E1", sourceVersion: { $lt: Int32(1) } },
    {
      $set: { sourceVersion: Int32(1), amount: Decimal128("5.00") },
      $setOnInsert: { _id: "UNEXPECTED", status: "active" }
    },
    { upsert: true }
  );
} catch (e) {
  staleUpsertRejected = e.code === 11000;
  printjson({ code: e.code, message: e.message });
}
check(staleUpsertRejected, "Stale conditional upsert must conflict with the existing business key");
check(lab.records.findOne({ externalId: "E1" }).amount.toString() === "12.00",
  "Newer state must be preserved");
```

Separate missing-entity creation from version-guarded update semantics, or design and test a suitable conditional pipeline contract. A unique index prevents duplication; it does not decide the business meaning of a stale event.

## 9. New application replay of an increment

```javascript
lab.records.updateOne({ _id: "R1" }, { $inc: { processedCount: Int32(1) } });
lab.records.updateOne({ _id: "R1" }, { $inc: { processedCount: Int32(1) } });
check(lab.records.findOne({ _id: "R1" }).processedCount === 2,
  "Two new increment operations should increment twice");
```

These are two separately submitted operations. This does not demonstrate a driver's retry of the same retryable-write identity.

If each event must apply once, use a deliberately designed idempotency/event ledger and concurrency strategy. A separate “seen event” record plus a counter update is not automatically atomic. Transactions and event recovery receive dedicated chapters.

## 10. Pipeline update with explicit conversion states

Create a tiny migration fixture:

```javascript
lab.migration.insertMany([
  { _id: "M1", amountText: "10.50", migrationState: "pending" },
  { _id: "M2", amountText: "invalid", migrationState: "pending" },
  { _id: "M3", migrationState: "pending" }
]);
var transformed = lab.migration.updateMany(
  { amountText: { $type: "string" } },
  [
    { $set: {
      amount: {
        $convert: { input: "$amountText", to: "decimal", onError: null, onNull: null }
      }
    } },
    { $set: {
      migrationState: {
        $cond: [{ $ne: ["$amount", null] }, "converted", "quarantine-required"]
      }
    } }
  ]
);
check(transformed.matchedCount === 2 && transformed.modifiedCount === 2,
  "Expected two typed-source transformations");
lab.migration.updateMany(
  { amountText: { $exists: false } }, { $set: { migrationState: "missing-source" } }
);
check(lab.migration.findOne({ _id: "M1" }).amount.toString() === "10.50",
  "Expected Decimal128 conversion");
check(lab.migration.findOne({ _id: "M2" }).migrationState === "quarantine-required",
  "Invalid value must be classified");
check(lab.migration.findOne({ _id: "M3" }).migrationState === "missing-source",
  "Missing source must be distinguished");
```

Each pipeline stage sees the preceding stage's output, so the second stage can classify the new amount field. Original amountText remains for review.

Only supported update-pipeline stages may be used; a general aggregation pipeline is not automatically a valid update pipeline. Dollar-prefixed literal values require appropriate $literal treatment when they would otherwise be interpreted as expressions.

## 11. Batching and operational evidence

The server advertises limits such as maxWriteBatchSize and maxBsonObjectSize in hello. Driver batching, message limits and payload size all matter.

```javascript
var limits = db.getSiblingDB("admin").runCommand({ hello: 1 });
printjson({
  maxWriteBatchSize: limits.maxWriteBatchSize,
  maxBsonObjectSize: limits.maxBsonObjectSize,
  maxMessageSizeBytes: limits.maxMessageSizeBytes
});
```

A protocol maximum is not the recommended operational batch size. Choose batches according to payload, latency, write concern, storage pressure and retry/reconciliation cost. A 100-operation batch of large records can be more expensive than a larger batch of small records.

Record batch ID, stable operation ID, source version, target key, intended operation, error classification, observed state and reconciliation outcome. Do not log sensitive full payloads unnecessarily.

## 12. Troubleshooting

| Symptom | Evidence | Action |
|---|---|---|
| Ordered bulk throws but data changed | Successful preceding operations | Reconcile partial success; do not assume rollback |
| Unordered batch reports errors and successes | Per-operation errors and final state | Classify each operation independently |
| Retry creates duplicate errors | Stable key and previous success | Reconcile logical entity and payload equality |
| Stale upsert fails on unique key | Version predicate and existing business key | Treat stale update separately from creation |
| Counter increased twice | Application operation identities | Distinguish new replay from driver retry semantics |
| Pipeline conversion yields null | Source type/value and onError policy | Quarantine/resolve ambiguity rather than accepting a false amount |
| Large batch times out | Payload, write concern and resource metrics | Reduce/review batch size and reconcile uncertain outcomes |
| Result counts misinterpreted | Method/driver version | Counts refer to operation-specific documents, not all array elements |

## 13. Final assertions and cleanup

```javascript
check(lab.ordered_demo.countDocuments({}) === 3, "Ordered reconciliation count");
check(lab.unordered_demo.countDocuments({}) === 3, "Unordered count");
check(lab.records.countDocuments({}) === 2, "Logical record count");
check(lab.records.findOne({ _id: "R1" }).sourceVersion === 2, "Newer version retained");
check(lab.records.findOne({ _id: "R1" }).processedCount === 2, "Replay distinction");
check(lab.migration.countDocuments({}) === 3, "Migration fixture count");
check(orderedFailed && unorderedFailed && staleUpsertRejected, "Failure evidence");
print("PASS: partial bulk success, replay, version guards and typed pipeline states");

check(lab.getName() === "mongodb_enterprise_tutorial_ch12", "Unexpected cleanup namespace");
names.forEach(name => lab.getCollection(name).drop());
check(!names.some(name => lab.getCollectionNames().includes(name)), "Cleanup failed");
print("PASS: Chapter 12 collections removed");
```

- [ ] Observe ordered partial success and unordered continuation.
- [ ] Reconcile the ordered remainder without blindly replaying successful inserts.
- [ ] Verify desired-state upsert replay.
- [ ] Preserve newer state and reproduce stale-upsert key conflict.
- [ ] Distinguish two new increments from a driver retry.
- [ ] Verify conversion, invalid-value and missing-source states.
- [ ] Capture limits, final assertions and cleanup.

**Authoring validation:** JavaScript syntax and official bulk/update/retry references reviewed. No live execution was available; runtime validation remains pending. Record exact server/shell versions, date, operator, error shapes and results after running.

Review questions:

1. Why is ordered bulk not an all-or-nothing transaction?
2. What makes an unordered batch's operations independent?
3. Why can a stale conditional upsert try to create a duplicate?
4. Why does $inc need a different replay contract from $set?
5. Which evidence resolves an uncertain bulk outcome?

## Technical references

- [Collection bulkWrite — 8.0](https://www.mongodb.com/docs/v8.0/reference/method/db.collection.bulkWrite/)
- [Update pipelines — 8.0](https://www.mongodb.com/docs/v8.0/tutorial/update-documents-with-aggregation-pipeline/)
- [Retryable writes — 8.0](https://www.mongodb.com/docs/v8.0/core/retryable-writes/)
- [$setOnInsert — 8.0](https://www.mongodb.com/docs/v8.0/reference/operator/update/setOnInsert/)
- [hello — 8.0](https://www.mongodb.com/docs/v8.0/reference/command/hello/)
- [Atomicity — 8.0](https://www.mongodb.com/docs/v8.0/core/write-operations-atomicity/)

Previous: [Chapter 11 — Schema Validation and Evolution](11-schema-validation-and-evolution.md).  
Next: **Chapter 13 — Aggregation Pipeline Fundamentals** (planned).  
Return to the [master layout](MASTER-LAYOUT.md).
