# 10 — Embedding Versus Referencing

**Status:** Written; static review complete; runtime lab validation pending  
**Part:** 2 — Data Modeling and Application Development  
**Goal:** Compare two models for the same synthetic workload and demonstrate their consistency and lifecycle tradeoffs.  
**Audience:** Developers, Data Engineers, Architects, DBREs and SREs  
**Time:** 75–105 minutes  
**Baseline:** MongoDB 8.0/mongosh; record exact versions.  
**Deployment:** Community-compatible or Enterprise standalone/replica set. No multi-document transaction is exercised.

## 1. Start with reads, writes and growth

Embedding stores related information together in one document. Referencing stores separate entities connected by identifiers. Neither is universally better.

Specify the workload before choosing:

| Question | Embedding becomes attractive when | Referencing becomes attractive when |
|---|---|---|
| Read together? | Related data is usually fetched as one bounded entity | Different consumers read different subsets |
| Update together? | One-document atomic changes fit the business operation | Entities have independent writers/lifecycles |
| Cardinality? | Child count is predictably bounded | Child history grows substantially |
| Shared entity? | A snapshot or small copy is acceptable | One canonical mutable entity has many consumers |
| Consistency? | One-document boundary fits the invariant | Cross-document invariants have an explicit strategy |
| Retention? | Parent and children share lifecycle | Children need independent archival/retention |

A single embedded document can be atomically updated, but a large or hot document can still create operational cost. Referencing avoids some duplication and growth but introduces lookups and consistency work.

## 2. Copies have different meanings

A duplicated provider display name might be a current cached value or a historical snapshot. The update rule depends on which meaning is intended.

- A current cached value needs an acceptable freshness interval and reconciliation.
- A historical snapshot should retain the value applicable to its original event.
- A reference points to a canonical entity that may change independently.

Calling every differing copy “stale” can corrupt historical meaning. Record the copy's semantic contract.

## 3. Lab setup

Use **mongodb_enterprise_tutorial_ch10** with collection creation, CRUD, index and cleanup permissions. Connect using the approved TLS/authentication pattern. Run JavaScript in one session.

```javascript
var lab = db.getSiblingDB("mongodb_enterprise_tutorial_ch10");
var names = ["providers", "patients_ref", "visits", "patients_embedded"];
if (names.some(name => lab.getCollectionNames().includes(name))) {
  throw new Error("Existing Chapter 10 resources");
}
names.forEach(name => lab.createCollection(name));
function check(ok, message) { if (!ok) throw new Error(message); }

lab.providers.insertMany([
  { _id: "D1", displayName: "Demo Provider One", version: Int32(1) },
  { _id: "D2", displayName: "Demo Provider Two", version: Int32(1) }
]);
lab.patients_ref.insertMany([
  { _id: "P1", providerId: "D1", visitCount: Int32(2) },
  { _id: "P2", providerId: "D1", visitCount: Int32(1) }
]);
lab.visits.insertMany([
  { _id: "V1", patientId: "P1", at: ISODate("2026-10-10T01:00:00Z"), kind: "demo" },
  { _id: "V2", patientId: "P1", at: ISODate("2026-10-10T02:00:00Z"), kind: "demo" },
  { _id: "V3", patientId: "P2", at: ISODate("2026-10-10T03:00:00Z"), kind: "demo" }
]);
lab.visits.createIndex({ patientId: 1, at: -1, _id: 1 });
lab.patients_embedded.insertMany([
  {
    _id: "P1", providerId: "D1", providerDisplay: "Demo Provider One",
    providerVersion: Int32(1), visitCount: Int32(2), revision: Int32(0),
    recentVisits: [
      { visitId: "V1", at: ISODate("2026-10-10T01:00:00Z"), kind: "demo" },
      { visitId: "V2", at: ISODate("2026-10-10T02:00:00Z"), kind: "demo" }
    ]
  },
  {
    _id: "P2", providerId: "D1", providerDisplay: "Demo Provider One",
    providerVersion: Int32(1), visitCount: Int32(1), revision: Int32(0),
    recentVisits: [
      { visitId: "V3", at: ISODate("2026-10-10T03:00:00Z"), kind: "demo" }
    ]
  }
]);
```

The embedded recentVisits is a small display summary, not a proposed lifetime visit history. Both models represent the same initial synthetic data.

## 4. Read the embedded model

```javascript
var embedded = lab.patients_embedded.findOne({ _id: "P1" });
check(embedded.providerDisplay === "Demo Provider One", "Embedded provider display");
check(embedded.recentVisits.length === 2, "Embedded visits");
printjson(embedded);
```

The read retrieves the bounded patient summary in one document. It returns a copied provider name, so its freshness depends on the model contract.

## 5. Read references explicitly and with lookup

Explicit application reads:

```javascript
var patient = lab.patients_ref.findOne({ _id: "P1" });
var provider = lab.providers.findOne({ _id: patient.providerId });
var visits = lab.visits.find({ patientId: patient._id })
  .sort({ at: -1, _id: 1 }).limit(10).toArray();
check(provider.displayName === "Demo Provider One", "Referenced provider");
check(visits.length === 2, "Referenced visits");
```

These are separate reads, not a guaranteed single snapshot across concurrent changes.

A server-side lookup can return the canonical provider alongside a patient:

```javascript
var joined = lab.patients_ref.aggregate([
  { $match: { _id: "P1" } },
  { $lookup: {
    from: "providers", localField: "providerId", foreignField: "_id", as: "provider"
  } }
]).toArray();
check(joined.length === 1 && joined[0].provider.length === 1, "Provider lookup");
check(joined[0].provider[0].displayName === embedded.providerDisplay,
  "Initial model agreement");
```

The join returns an array; zero or multiple matches require explicit handling. The provider _id index supports its lookup key. This fixture is not a performance benchmark and does not prove lookup is faster or slower than embedding at scale.

## 6. Observe fan-out freshness work

Rename the canonical provider:

```javascript
lab.providers.updateOne({ _id: "D1", version: Int32(1) }, {
  $set: { displayName: "Demo Provider One Updated" },
  $inc: { version: Int32(1) }
});
check(lab.providers.findOne({ _id: "D1" }).version === 2, "Canonical version");
check(lab.patients_embedded.countDocuments({ providerVersion: Int32(1) }) === 2,
  "Expected two old current-display copies");
```

The referenced canonical name changes once. Two embedded current-display copies still need reconciliation.

For this lab, the copies explicitly mean “current display,” not historical snapshot. Reconcile them:

```javascript
var canonical = lab.providers.findOne({ _id: "D1" });
var synced = lab.patients_embedded.updateMany(
  { providerId: "D1", providerVersion: Int32(1) },
  { $set: { providerDisplay: canonical.displayName, providerVersion: canonical.version } }
);
check(synced.modifiedCount === 2, "Expected two reconciled display copies");
check(lab.patients_embedded.countDocuments({ providerVersion: Int32(2) }) === 2,
  "Expected version agreement");
```

The updateMany is not an atomic all-patients transaction. A production strategy must define concurrent provider changes, missed updates, freshness targets and reconciliation.

## 7. Compare write boundaries

In the embedded model, append a visit and increment its summary count in one guarded operation:

```javascript
var embeddedWrite = lab.patients_embedded.updateOne(
  { _id: "P1", revision: Int32(0) },
  {
    $push: { recentVisits: {
      visitId: "V4", at: ISODate("2026-10-10T04:00:00Z"), kind: "demo"
    } },
    $inc: { visitCount: Int32(1), revision: Int32(1) }
  }
);
check(embeddedWrite.modifiedCount === 1, "Embedded write");
var updatedEmbedded = lab.patients_embedded.findOne({ _id: "P1" });
check(updatedEmbedded.visitCount === 3 && updatedEmbedded.recentVisits.length === 3,
  "Embedded summary and count agree");
```

In the referenced model, intentionally separate insertion from summary maintenance:

```javascript
lab.visits.insertOne({
  _id: "V4", patientId: "P1", at: ISODate("2026-10-10T04:00:00Z"), kind: "demo"
});
check(lab.visits.countDocuments({ patientId: "P1" }) === 3, "Reference visit count");
check(lab.patients_ref.findOne({ _id: "P1" }).visitCount === 2,
  "Expected intermediate summary mismatch");

lab.patients_ref.updateOne(
  { _id: "P1", visitCount: Int32(2) }, { $set: { visitCount: Int32(3) } }
);
check(lab.patients_ref.findOne({ _id: "P1" }).visitCount === 3,
  "Referenced summary reconciliation");
```

This gap is deliberately observed between commands. Requirements may be met through derived counts, an eventually consistent summary with reconciliation, or a transaction on a suitable topology. Chapter 16 develops transaction semantics.

## 8. Failure exercise — references are not automatic foreign keys

Insert a patient referencing a nonexistent provider:

```javascript
lab.patients_ref.insertOne({ _id: "BROKEN", providerId: "D404", visitCount: Int32(0) });
var broken = lab.patients_ref.aggregate([
  { $match: { _id: "BROKEN" } },
  { $lookup: {
    from: "providers", localField: "providerId", foreignField: "_id", as: "provider"
  } }
]).toArray();
check(broken[0].provider.length === 0, "Expected unresolved reference");
lab.patients_ref.deleteOne({ _id: "BROKEN" });
```

Ordinary identifier fields do not create a database foreign-key constraint. A JSON Schema validator can check field shape/type, but it does not perform this cross-collection existence lookup.

Demonstrate an orphan child and a reconciliation query:

```javascript
lab.visits.insertOne({
  _id: "ORPHAN", patientId: "NO-PATIENT", at: ISODate("2026-10-10T00:00:00Z")
});
var orphans = lab.visits.aggregate([
  { $lookup: {
    from: "patients_ref", localField: "patientId", foreignField: "_id", as: "parent"
  } },
  { $match: { parent: { $size: 0 } } },
  { $project: { _id: 1, patientId: 1 } }
]).toArray();
check(orphans.length === 1 && orphans[0]._id === "ORPHAN", "Expected orphan fixture");
lab.visits.deleteOne({ _id: "ORPHAN" });
print("PASS: unresolved references detected and synthetic fixtures removed");
```

Deleting a parent does not automatically cascade to ordinary referenced children. Real orphan handling needs an ownership/lifecycle policy, not automatic blanket deletion.

## 9. Inspect size without inventing a benchmark

```javascript
function logicalBsonBytes(collection) {
  var result = collection.aggregate([
    { $group: { _id: null, bytes: { $sum: { $bsonSize: "$$ROOT" } } } }
  ]).toArray();
  return result.length ? result[0].bytes : 0;
}
printjson({
  embeddedPatientBytes: logicalBsonBytes(lab.patients_embedded),
  referencedPatientBytes: logicalBsonBytes(lab.patients_ref),
  referencedVisitBytes: logicalBsonBytes(lab.visits),
  sharedProviderBytes: logicalBsonBytes(lab.providers)
});
```

These are logical BSON payload sizes, excluding index allocation, compression and other storage costs. The provider collection is shared by both models in this demonstration; do not count it asymmetrically to claim a winner.

A real comparison needs representative cardinality, read/write ratios, indexes, latency distributions, memory and I/O evidence. Toy response times are not a capacity forecast.

## 10. Choose a hybrid deliberately

A practical model can keep a canonical provider, a referenced complete visit history and a small patient summary with recent visits. That combines fast common reads with independent history growth.

Document the summary's bound, freshness, repair source and failure handling. Avoid a “hybrid” that merely creates undocumented duplicate state.

Write an architecture decision record:

| Field | Required decision |
|---|---|
| Main read | Exact returned fields and expected bound |
| History | Canonical source and retention |
| Shared entities | Canonical reference or copy semantics |
| Atomic invariant | Which fields must change together |
| Freshness | Allowed lag and reconciliation owner |
| Growth | Maximum cardinality and document-size budget |
| Recovery | Rebuild source for derived summaries |

## 11. Troubleshooting and production considerations

| Symptom | Evidence | Action |
|---|---|---|
| Embedded name differs from canonical name | Copy semantics/version | Reconcile current-display copies; preserve valid historical snapshots |
| Count differs from child records | Write sequence and canonical source | Recompute/reconcile or redesign the invariant |
| Lookup returns no match | Key type and missing entity | Distinguish type mismatch from unresolved reference |
| Parent deletion leaves children | Lifecycle policy | Implement reviewed cascade/archive/reconciliation |
| Document grows continuously | Cardinality/size trend | Move unbounded history into independently managed records |
| Join is costly | Explain plan and foreign-key index | Design indexes and bound returned children |

Concurrency, retention and recovery are data-model concerns, not afterthoughts. Define all writers and failure states before relying on duplicated summaries.

## 12. Final assertions and cleanup

```javascript
check(lab.providers.countDocuments({}) === 2, "Provider count");
check(lab.patients_ref.countDocuments({}) === 2, "Referenced patient count");
check(lab.patients_embedded.countDocuments({}) === 2, "Embedded patient count");
check(lab.visits.countDocuments({}) === 4, "Visit count");
check(lab.patients_ref.findOne({ _id: "P1" }).visitCount === 3, "Reference count reconciled");
check(lab.patients_embedded.findOne({ _id: "P1" }).visitCount === 3, "Embedded count");
print("PASS: model reads, freshness reconciliation, write boundaries and orphan detection");

check(lab.getName() === "mongodb_enterprise_tutorial_ch10", "Unexpected cleanup database");
names.forEach(name => lab.getCollection(name).drop());
check(!names.some(name => lab.getCollectionNames().includes(name)), "Cleanup failed");
print("PASS: Chapter 10 collections removed");
```

- [ ] Compare equivalent initial model reads.
- [ ] Observe/reconcile current-display copy versions.
- [ ] Demonstrate single-document update and referenced intermediate mismatch.
- [ ] Detect unresolved provider and orphan child fixtures.
- [ ] Capture logical size evidence without claiming a benchmark.
- [ ] Complete the model decision record and verify cleanup.

**Authoring validation:** JavaScript syntax and official modeling references reviewed. Live execution pending; record exact versions, environment, date, operator and results after running.

Review questions:

1. What makes a copy a valid historical snapshot rather than stale current data?
2. Which invariant fits a single-document boundary in this lab?
3. Why does a reference field not enforce parent existence?
4. What evidence would support a real performance comparison?
5. How can a bounded summary be rebuilt after failure?

## Technical references

- [Modeling best practices — 8.0](https://www.mongodb.com/docs/v8.0/data-modeling/best-practices/)
- [Avoid unbounded arrays — 8.0](https://www.mongodb.com/docs/v8.0/data-modeling/design-antipatterns/unbounded-arrays/)
- [$lookup — 8.0](https://www.mongodb.com/docs/v8.0/reference/operator/aggregation/lookup/)
- [Atomicity — 8.0](https://www.mongodb.com/docs/v8.0/core/write-operations-atomicity/)

Previous: [Chapter 09 — Nested Documents and Arrays](09-nested-documents-and-arrays.md).  
Next: [Chapter 11 — Schema Validation and Evolution](11-schema-validation-and-evolution.md).  
Return to the [master layout](MASTER-LAYOUT.md).
