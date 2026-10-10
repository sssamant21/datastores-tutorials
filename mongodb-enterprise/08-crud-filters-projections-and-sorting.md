# 08 — CRUD Filters Projections and Sorting

**Status:** Written; static review complete; runtime lab validation pending  
**Part:** 1 — Foundations and Architecture  
**Goal:** Implement bounded reads and guarded writes for a synthetic claims workflow, including predictable retries and verified deletes.  
**Audience:** Developers, Data Engineers, DBREs and SREs  
**Time:** 75–105 minutes  
**Baseline:** MongoDB 8.0 with mongosh; record exact server/shell versions.  
**Deployment:** Core Community-compatible or Enterprise standalone/replica set. No multi-document transaction is required or validated.

## 1. CRUD is an application contract

Create, read, update and delete describe operations, but a production contract also specifies identifiers, filters, return fields, ordering, state transitions and failure behavior.

For a synthetic claim-processing service:

- claimId is a unique business identifier.
- status moves through explicit states.
- amount uses Decimal128 and a defined currency.
- revision protects a conditional update from a stale caller.
- API reads return a bounded projection in a deterministic order.
- Deletion targets a known record/state and verifies the outcome.

A successful write acknowledgement does not mean the intended document matched. Read matchedCount, modifiedCount, upsertedCount and deletedCount according to the operation.

## 2. Choose the method deliberately

| Method | Purpose | Result to inspect |
|---|---|---|
| insertOne / insertMany | Create new records | Acknowledgement and inserted identifiers |
| findOne | Retrieve at most one match | Document or null |
| find | Create a cursor for multiple matches | Consume a bounded result set |
| updateOne | Modify at most one matching document | matchedCount and modifiedCount |
| updateMany | Modify each match | Counts; operation is not one atomic multi-document change |
| replaceOne | Replace one document's content | Counts and preserved required fields |
| updateOne with upsert | Update a match or create a record | Match/upsert result |
| deleteOne / deleteMany | Remove matches | deletedCount |

An empty updateMany/deleteMany filter can affect the whole collection. This lab never uses an empty filter for destructive writes.

## 3. Filter, projection and sort rules

Fields in a filter usually combine with logical AND. $or expresses alternatives; $in selects from a set; comparison operators express ranges. Use BSON-compatible bound values, as demonstrated in Chapter 02.

Projection usually chooses either included fields or excluded fields. Excluding _id is the common exception when including other fields. Do not mix arbitrary inclusion and exclusion.

A sort on a non-unique field can contain ties. Include a unique field such as _id as a final tie-breaker when deterministic order matters. This establishes an order for a given result set; it does not freeze a changing dataset across independent requests.

A cursor is not an array. toArray materializes its results in client memory, so use it only for bounded results like these small labs.

## 4. Lab prerequisites and connection

Use the dedicated database **mongodb_enterprise_tutorial_ch08**. You need collection creation, CRUD, index creation and cleanup permissions.

For an existing local server:

```bash
mongosh "mongodb://127.0.0.1:27017"
```

For a secured deployment, use the verified TLS and prompted authentication pattern from Chapter 06. Record deployment identity and exact versions.

Run all JavaScript blocks in one session in order. The synthetic patient identifiers carry no real patient data.

## 5. Setup and fixtures

```javascript
var lab = db.getSiblingDB("mongodb_enterprise_tutorial_ch08");
if (["claims", "replacement_demo"].some(name =>
  lab.getCollectionNames().includes(name))) {
  throw new Error("Existing Chapter 08 resources; review cleanup first");
}
lab.createCollection("claims");
lab.claims.createIndex({ claimId: 1 }, { unique: true });

function check(ok, message) {
  if (!ok) throw new Error(message);
}
function claim(id, patientId, status, amount, time) {
  return {
    _id: id,
    claimId: "CLM" + id.substring(1),
    patientId: patientId,
    status: status,
    amount: Decimal128(amount),
    currency: "USD",
    createdAt: ISODate(time),
    revision: Int32(0),
    metadata: { source: "synthetic", internalNote: "training-only" }
  };
}
lab.claims.insertMany([
  claim("C001", "EMP0001", "pending", "100.00", "2026-10-10T00:00:00Z"),
  claim("C002", "EMP0002", "approved", "200.00", "2026-10-10T01:00:00Z"),
  claim("C003", "EMP0003", "pending", "300.00", "2026-10-10T02:00:00Z"),
  claim("C004", "EMP0004", "rejected", "50.00", "2026-10-11T00:00:00Z"),
  claim("C005", "EMP0005", "pending", "100.00", "2026-10-10T00:00:00Z"),
  claim("C006", "EMP0006", "approved", "125.00", "2026-10-12T00:00:00Z")
]);
check(lab.claims.countDocuments({}) === 6, "Expected six claims");
```

Expected: six deterministic records and unique claimId enforcement. The helper creates normal JavaScript documents with explicit BSON values.

## 6. Equality, range and logical filters

```javascript
var one = lab.claims.findOne({ claimId: "CLM001" });
check(one && one.patientId === "EMP0001", "Business identifier lookup");

var pending = lab.claims.find({
  status: "pending",
  amount: { $gte: Decimal128("100.00") }
}, { _id: 1 }).sort({ _id: 1 }).toArray();
check(JSON.stringify(pending.map(doc => doc._id)) ===
  JSON.stringify(["C001", "C003", "C005"]), "Pending amount filter");

check(lab.claims.countDocuments({
  status: { $in: ["approved", "rejected"] }
}) === 3, "Status set filter");

check(lab.claims.countDocuments({
  $or: [{ status: "rejected" }, { amount: { $gte: Decimal128("200.00") } }]
}) === 3, "OR filter");

check(lab.claims.countDocuments({
  createdAt: {
    $gte: ISODate("2026-10-10T00:00:00Z"),
    $lt: ISODate("2026-10-11T00:00:00Z")
  }
}) === 4, "Half-open date range");
```

Expected IDs/counts are explicit. The half-open date interval includes the starting instant and excludes the next day's boundary. Define business timezone conversion before producing those UTC bounds.

Use $ne thoughtfully: missing fields can have different matching behavior from an application interpretation of “not equal.” Chapter 02 demonstrates null/missing cases.

## 7. Projection and deterministic bounded sorting

```javascript
var page = lab.claims.find(
  { status: "pending" },
  { _id: 0, claimId: 1, status: 1, amount: 1 }
).sort({ amount: 1, _id: 1 }).limit(3).toArray();

check(JSON.stringify(page.map(doc => doc.claimId)) ===
  JSON.stringify(["CLM001", "CLM005", "CLM003"]), "Sort order including tie-breaker");
check(page.every(doc => !("metadata" in doc) && !("_id" in doc)),
  "Projection must omit internal fields");
printjson(page);
```

C001 and C005 have the same amount. Sorting by _id breaks the tie even though _id is not returned. Projection reduces returned data but does not itself prove an index-covered query.

Reproduce invalid mixed projection:

```javascript
var projectionRejected = false;
try {
  lab.claims.find({}, { claimId: 1, status: 0 }).limit(1).toArray();
} catch (e) {
  projectionRejected = e.code === 31254;
  printjson({ code: e.code, message: e.message });
}
check(projectionRejected, "Expected inclusion/exclusion projection error");
```

Correct by using a valid inclusion projection with optional _id exclusion as above.

## 8. Guard a state transition against stale callers

A single-document update is atomic. Include the expected current revision and state in the filter:

```javascript
var transitionFilter = { _id: "C001", status: "pending", revision: Int32(0) };
var transitionUpdate = {
  $set: { status: "approved" },
  $inc: { revision: Int32(1) }
};
var firstTransition = lab.claims.updateOne(transitionFilter, transitionUpdate);
check(firstTransition.matchedCount === 1 && firstTransition.modifiedCount === 1,
  "Expected first guarded transition");

var staleTransition = lab.claims.updateOne(transitionFilter, transitionUpdate);
check(staleTransition.matchedCount === 0 && staleTransition.modifiedCount === 0,
  "Stale revision/state must not match");
check(lab.claims.findOne({ _id: "C001" }).revision === 1,
  "Revision must advance exactly once");
print("PASS: stale state transition rejected by filter");
```

The second call uses stale assumptions. The application should read/reconcile current state rather than remove the guard.

This is optimistic concurrency for one document. It does not make updates across separate documents atomic and is not a full retryable-write or transaction demonstration.

## 9. Distinguish unchanged values from missing records

```javascript
var noChange = lab.claims.updateOne(
  { _id: "C001" }, { $set: { status: "approved" } }
);
check(noChange.matchedCount === 1 && noChange.modifiedCount === 0,
  "Existing desired state should match without modification");

var missing = lab.claims.updateOne(
  { _id: "DOES-NOT-EXIST" }, { $set: { status: "approved" } }
);
check(missing.matchedCount === 0 && missing.modifiedCount === 0,
  "Missing target must not match");
```

Both have modifiedCount zero but mean different things. Upsert should not be added reflexively to a missing-record update: it can create an incomplete or unintended entity.

## 10. Upsert with a unique business key

Define a known desired record and creation-only fields:

```javascript
var upsertUpdate = {
  $set: { status: "pending" },
  $setOnInsert: {
    _id: "C007",
    patientId: "EMP0007",
    amount: Decimal128("75.00"),
    currency: "USD",
    createdAt: ISODate("2026-10-13T00:00:00Z"),
    revision: Int32(0),
    metadata: { source: "synthetic", internalNote: "training-only" }
  }
};
var created = lab.claims.updateOne(
  { claimId: "CLM007" }, upsertUpdate, { upsert: true }
);
check(created.upsertedCount === 1, "Expected a new upserted claim");
check(lab.claims.countDocuments({}) === 7, "Expected seven claims");

var replayed = lab.claims.updateOne(
  { claimId: "CLM007" }, upsertUpdate, { upsert: true }
);
check(replayed.matchedCount === 1 && replayed.modifiedCount === 0,
  "Repeated desired-state upsert should not modify unchanged data");
check(lab.claims.countDocuments({}) === 7, "Replay must not create another record");
```

The equality filter supplies claimId for the inserted document. The unique index protects that business key. Concurrent upserts can still require duplicate-key handling and reconciliation; this sequential lab does not prove all concurrency cases.

A later replay of this particular upsert could set a previously approved claim back to pending. Its idempotency is limited to the demonstrated unchanged desired state. For a production state machine, define allowed transitions and replay semantics explicitly.

## 11. Failure exercise — duplicate business identifier

```javascript
var duplicateRejected = false;
try {
  lab.claims.insertOne({
    _id: "DUP001",
    claimId: "CLM007",
    patientId: "EMP0099",
    status: "pending",
    amount: Decimal128("1.00"),
    currency: "USD"
  });
} catch (e) {
  duplicateRejected = e.code === 11000;
  printjson({ code: e.code, message: e.message });
}
check(duplicateRejected, "Expected unique claimId duplicate rejection");
check(lab.claims.countDocuments({}) === 7, "Rejected duplicate must preserve count");
```

Expected: code 11000 for the unique claimId index, while the collection remains at seven records. Inspect the named key/index and reconcile the existing business entity. Blindly generating a new _id does not solve a duplicate business key.

## 12. Update a bounded set

```javascript
var reviewFilter = { status: "pending", "metadata.source": "synthetic" };
var planned = lab.claims.countDocuments(reviewFilter);
check(planned === 3, "Expected three pending synthetic claims");
var reviewed = lab.claims.updateMany(reviewFilter, { $set: { reviewRequired: true } });
check(reviewed.matchedCount === 3 && reviewed.modifiedCount === 3,
  "Expected three marked claims");
check(lab.claims.countDocuments({ reviewRequired: true }) === 3,
  "Review flag reconciliation");
```

Counting before writing is a useful preview but is not an atomic guarantee; concurrent changes can alter the matches between commands. Production bulk updates need batching, reconciliation, concurrency decisions and recovery evidence.

## 13. Replacement versus field update

Demonstrate replacement on an independent copy, preserving the source claim:

```javascript
lab.createCollection("replacement_demo");
var originalCopy = lab.claims.findOne({ _id: "C004" });
lab.replacement_demo.insertOne(originalCopy);

lab.replacement_demo.replaceOne(
  { _id: "C004" },
  { _id: "C004", claimId: "CLM004", status: "rejected" }
);
var replacedCopy = lab.replacement_demo.findOne({ _id: "C004" });
check(!("amount" in replacedCopy) && !("metadata" in replacedCopy),
  "Replacement omits fields not supplied");

lab.replacement_demo.replaceOne({ _id: "C004" }, originalCopy);
check(lab.replacement_demo.findOne({ _id: "C004" }).metadata.source === "synthetic",
  "Lab replacement reversal failed");
check(lab.claims.findOne({ _id: "C004" }).amount.toString() === "50.00",
  "Source claim must remain unchanged");
```

replaceOne replaces document content, while $set changes selected fields. The source is untouched; the saved in-memory copy is only a lab reversal aid and is not durable backup evidence.

## 14. Guarded delete and fixture restoration

Preview the exact synthetic rejected record:

```javascript
var deleteFilter = { _id: "C004", status: "rejected", "metadata.source": "synthetic" };
var saved = lab.claims.findOne(deleteFilter);
check(saved !== null, "Expected known rejected fixture");
check(lab.claims.countDocuments(deleteFilter) === 1, "Expected one delete candidate");

var deleted = lab.claims.deleteOne(deleteFilter);
check(deleted.deletedCount === 1, "Expected one deleted fixture");
check(lab.claims.findOne({ _id: "C004" }) === null, "Deletion verification");
check(lab.claims.countDocuments({}) === 6, "Expected six remaining claims");

lab.claims.insertOne(saved);
check(lab.claims.countDocuments({}) === 7, "Fixture restoration count");
check(lab.claims.findOne({ _id: "C004" }).status === "rejected",
  "Fixture restoration state");
```

The restoration works only because this synthetic record was deliberately held in the current shell before deletion. Real accidental deletion recovery requires a durable, consistent recovery source and reconciliation. Do not mistake a local variable for a backup strategy.

## 15. Reject unsafe client filter input

An API should not accept arbitrary operator documents where a scalar business identifier is expected.

```javascript
function exactClaimFilter(input) {
  if (typeof input !== "string" || !/^CLM[0-9]{3}$/.test(input)) {
    throw new Error("Expected one canonical claim identifier");
  }
  return { claimId: input };
}
var operatorInputRejected = false;
try {
  exactClaimFilter({ $ne: null });
} catch (e) {
  operatorInputRejected = true;
}
check(operatorInputRejected, "Operator-shaped identifier must be rejected");
check(lab.claims.findOne(exactClaimFilter("CLM001"))._id === "C001",
  "Validated scalar filter");
```

This is a focused input-contract demonstration, not a complete API security implementation. Use driver-supported structured operations and validate allowed parameters at the service boundary.

## 16. Final assertions

```javascript
check(lab.claims.countDocuments({}) === 7, "Final claim count");
check(lab.claims.findOne({ _id: "C001" }).status === "approved", "Transition state");
check(lab.claims.findOne({ _id: "C001" }).revision === 1, "Transition revision");
check(lab.claims.countDocuments({ claimId: "CLM007" }) === 1, "Upsert uniqueness");
check(lab.claims.countDocuments({ reviewRequired: true }) === 3, "Review flag count");
check(lab.claims.getIndexes().some(index =>
  index.name === "claimId_1" && index.unique === true), "Business-key index");
check(projectionRejected && duplicateRejected && operatorInputRejected,
  "Failure exercise evidence");
check(lab.replacement_demo.countDocuments({}) === 1, "Replacement fixture count");
print("PASS: bounded reads, projections, stable ordering, guarded updates, upserts and scoped delete");
```

## 17. Troubleshooting

| Symptom | Evidence | Action |
|---|---|---|
| No results | Namespace, field type and predicate | Verify actual values and typed bounds |
| Projection error | Inclusion/exclusion document | Use one projection mode with the _id exception |
| Rows reorder between calls | Sort keys and tie values | Add a unique tie-breaker; consider concurrent data changes |
| matchedCount zero | Expected state/revision and target | Reconcile stale state instead of removing the guard |
| modifiedCount zero | Current value and matchedCount | Distinguish no change from no match |
| Upsert creates unexpected data | Equality filter and creation fields | Review contract and uniqueness constraints |
| Duplicate key | Index/key named by error | Reconcile existing business entity |
| Bulk counts differ from preview | Concurrency and exact filter | Reconcile actual results; preview is not an atomic lock |
| Replacement loses fields | Full replacement content | Use an operator update or a deliberate complete replacement |
| Delete affects wrong records | Target/filter and operation type | Use reviewed scope and recovery evidence |

## 18. Production takeaways

Bound query outputs and choose projections deliberately. Deterministic sorting helps correctness, but indexing is needed to understand large-scale cost. Explain-plan and pagination chapters examine that separately.

Use expected state/revision for business transitions, and treat result counts as part of the API response contract. Do not automatically create a missing record through upsert unless that is the intended operation.

Bulk writes and deletions require explicit filters, recovery planning and reconciliation. Single-document atomicity does not make a multi-document workflow transactional.

## 19. Cleanup and acceptance

```javascript
check(lab.getName() === "mongodb_enterprise_tutorial_ch08", "Unexpected cleanup namespace");
["replacement_demo", "claims"].forEach(name => lab.getCollection(name).drop());
check(!["replacement_demo", "claims"].some(name =>
  lab.getCollectionNames().includes(name)), "Cleanup failed");
print("PASS: Chapter 08 collections removed");
```

- [ ] Record deployment and exact server/shell versions.
- [ ] Verify filter counts and half-open date range.
- [ ] Verify projection and stable sort order.
- [ ] Observe stale transition rejection and no-change/missing distinction.
- [ ] Verify upsert replay and unique-key rejection.
- [ ] Reconcile bounded updateMany results.
- [ ] Demonstrate replacement semantics and scoped delete/restoration.
- [ ] Reject operator-shaped scalar input.
- [ ] Capture final PASS and cleanup results.

**Authoring validation:** JavaScript syntax and official CRUD guidance reviewed. No live database execution was available during authoring; runtime validation remains pending. Record date, operator, versions and command outputs after execution.

## 20. Review questions

1. Why do matchedCount and modifiedCount answer different questions?
2. Why should a non-unique sort include a tie-breaker?
3. How does a state/revision filter prevent a stale transition?
4. What replay risk remains in the demonstrated upsert?
5. Why is a preview count not a concurrency guarantee?
6. Why is a saved shell object not a backup?

## Technical references

- [CRUD operations — 8.0](https://www.mongodb.com/docs/v8.0/crud/)
- [Query documents — 8.0](https://www.mongodb.com/docs/v8.0/tutorial/query-documents/)
- [Projection — 8.0](https://www.mongodb.com/docs/v8.0/tutorial/project-fields-from-query-results/)
- [Atomicity — 8.0](https://www.mongodb.com/docs/v8.0/core/write-operations-atomicity/)
- [updateOne — 8.0](https://www.mongodb.com/docs/v8.0/reference/method/db.collection.updateOne/)
- [Cursor sort — 8.0](https://www.mongodb.com/docs/v8.0/reference/method/cursor.sort/)
- [replaceOne — 8.0](https://www.mongodb.com/docs/v8.0/reference/method/db.collection.replaceOne/)
- [deleteOne — 8.0](https://www.mongodb.com/docs/v8.0/reference/method/db.collection.deleteOne/)

Previous: [Chapter 07 — Databases Collections and Namespaces](07-databases-collections-and-namespaces.md).  
Next: **Chapter 09 — Nested Documents and Arrays** (planned).  
Return to the [master layout](MASTER-LAYOUT.md).
