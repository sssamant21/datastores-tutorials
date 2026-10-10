# 14 — Advanced Aggregations and Joins

**Status:** Written; static review complete; runtime lab validation pending  
**Part:** 2 — Data Modeling and Application Development  
**Goal:** Control join/unwind cardinality, reconcile line-item totals and build bounded facets and running totals.  
**Audience:** Developers, Data Engineers, DBREs and SREs  
**Time:** 75–105 minutes  
**Baseline:** MongoDB 8.0/mongosh; record exact versions.  
**Deployment:** Community-compatible or Enterprise training deployment; read-only aggregation pipelines.

## 1. Cardinality is a correctness concern

A join can produce zero, one or many matches. Unwind can turn one document into multiple documents, or remove documents with empty arrays. Summing a parent amount after expansion can count it repeatedly.

Before each expensive stage, state what one output row represents: order, customer, line item or grouped summary.

| Stage | Potential cardinality effect | Question to answer |
|---|---|---|
| $lookup | Adds a zero/one/many-match array | Is the foreign key unique and type-compatible? |
| $unwind | Expands arrays and can omit empty/missing values | Are unmatched parents preserved? |
| $group | Collapses rows by key | Are accumulators at the correct grain? |
| $facet | Builds multiple result branches into one document | Are each branch and final output bounded? |
| $setWindowFields | Adds values over an ordered partition | Are partition and ordering semantics correct? |

allowDiskUse does not remove all stage-specific memory limits or the BSON result-document size limit.

## 2. Setup equivalent parent and child values

Connect with approved training credentials and create/CRUD/index/cleanup permissions in **mongodb_enterprise_tutorial_ch14**. Run all JavaScript in one session.

```javascript
var lab = db.getSiblingDB("mongodb_enterprise_tutorial_ch14");
var names = ["orders", "customers", "ambiguous_customers"];
if (names.some(name => lab.getCollectionNames().includes(name))) {
  throw new Error("Existing Chapter 14 resources");
}
names.forEach(name => lab.createCollection(name));
function check(ok, message) { if (!ok) throw new Error(message); }

lab.customers.insertMany([
  { _id: "C1", name: "Demo Alpha" },
  { _id: "C2", name: "Demo Beta" }
]);
lab.orders.insertMany([
  {
    _id: "O1", customerId: "C1", createdAt: ISODate("2026-10-10T01:00:00Z"),
    amount: Decimal128("12.00"),
    items: [
      { sku: "S1", quantity: Int32(2), unitPrice: Decimal128("5.00") },
      { sku: "S2", quantity: Int32(1), unitPrice: Decimal128("2.00") }
    ]
  },
  {
    _id: "O2", customerId: "C1", createdAt: ISODate("2026-10-10T02:00:00Z"),
    amount: Decimal128("8.00"),
    items: [{ sku: "S2", quantity: Int32(4), unitPrice: Decimal128("2.00") }]
  },
  {
    _id: "O3", customerId: "C2", createdAt: ISODate("2026-10-10T03:00:00Z"),
    amount: Decimal128("0.00"), items: []
  },
  {
    _id: "O4", customerId: "C404", createdAt: ISODate("2026-10-10T04:00:00Z"),
    amount: Decimal128("3.00"),
    items: [{ sku: "S3", quantity: Int32(1), unitPrice: Decimal128("3.00") }]
  }
]);
check(lab.orders.countDocuments({}) === 4, "Expected four orders");
```

Authoritative order total: 23.00. O4 intentionally has an unresolved customer reference; O3 has an empty item array.

## 3. Join to a unique canonical key

```javascript
var joinStage = { $lookup: {
  from: "customers", localField: "customerId", foreignField: "_id", as: "customer"
} };
var joined = lab.orders.aggregate([joinStage, { $sort: { _id: 1 } }]).toArray();
check(joined.length === 4, "Lookup alone must retain four parent documents");
check(joined.slice(0, 3).every(order => order.customer.length === 1),
  "Expected three resolved customer matches");
check(joined[3].customer.length === 0, "Expected unresolved C404 reference");
```

Lookup returns an array. The customers _id index supplies a unique foreign key here. A type mismatch can also create zero matches, so inspect both key values and BSON types before declaring a missing entity.

Pipeline lookup can project only the needed customer fields:

```javascript
var projectedJoin = lab.orders.aggregate([
  { $match: { _id: "O1" } },
  { $lookup: {
    from: "customers",
    let: { requestedCustomer: "$customerId" },
    pipeline: [
      { $match: { $expr: { $eq: ["$_id", "$$requestedCustomer"] } } },
      { $project: { _id: 1, name: 1 } }
    ],
    as: "customer"
  } }
]).toArray();
check(projectedJoin[0].customer[0].name === "Demo Alpha", "Projected lookup");
```

Actual lookup index behavior depends on predicate, variable values and server version. Inspect explain rather than assuming every correlated expression is efficient.

## 4. Inner-like versus left-like expansion

```javascript
var inner = lab.orders.aggregate([
  joinStage, { $unwind: "$customer" }, { $sort: { _id: 1 } }
]).toArray();
var left = lab.orders.aggregate([
  joinStage,
  { $unwind: { path: "$customer", preserveNullAndEmptyArrays: true } },
  { $sort: { _id: 1 } }
]).toArray();
check(inner.length === 3, "Default unwind should omit unresolved customer");
check(left.length === 4, "Preserving empty arrays should retain unresolved parent");
check(left.some(order => order._id === "O4"), "O4 must remain in left-like output");
```

Dropping unmatched records can hide data-quality problems. Choose the intended semantics explicitly and report unresolved references separately where needed.

## 5. Failure exercise — non-unique foreign key

```javascript
lab.ambiguous_customers.insertMany([
  { _id: "X1", externalCode: "C1", name: "First copy" },
  { _id: "X2", externalCode: "C1", name: "Second copy" }
]);
var ambiguous = lab.orders.aggregate([
  { $match: { customerId: "C1" } },
  { $lookup: {
    from: "ambiguous_customers",
    localField: "customerId", foreignField: "externalCode", as: "customer"
  } },
  { $unwind: "$customer" },
  { $group: { _id: null, rows: { $sum: 1 }, total: { $sum: "$amount" } } }
]).toArray();
check(ambiguous[0].rows === 4 && ambiguous[0].total.toString() === "40.00",
  "Expected duplicate foreign matches to double the two C1 orders");
```

The correct total for the two C1 orders is 20.00. The join grain is wrong because externalCode is not unique in this fixture.

Do not arbitrarily select the first match unless that is the documented business rule. Repair/deduplicate the canonical data, establish an appropriate unique key and reconcile affected reports.

## 6. Failure exercise — sum parent amount after item unwind

```javascript
var inflated = lab.orders.aggregate([
  { $unwind: "$items" },
  { $group: { _id: null, total: { $sum: "$amount" }, rows: { $sum: 1 } } }
]).toArray();
check(inflated[0].rows === 4, "Expected four nonempty line items");
check(inflated[0].total.toString() === "35.00", "Expected duplicated O1 parent amount");
```

O1 contributes its 12.00 parent amount twice. This is a report bug, not additional revenue.

Compute at line-item grain instead:

```javascript
var lineTotals = lab.orders.aggregate([
  { $unwind: "$items" },
  { $set: { lineAmount: { $multiply: ["$items.quantity", "$items.unitPrice"] } } },
  { $group: { _id: "$items.sku", total: { $sum: "$lineAmount" },
    quantity: { $sum: "$items.quantity" } } },
  { $sort: { _id: 1 } }
]).toArray();
check(lineTotals[0]._id === "S1" && lineTotals[0].total.toString() === "10.00",
  "S1 total");
check(lineTotals[1]._id === "S2" && lineTotals[1].total.toString() === "10.00" &&
  lineTotals[1].quantity === 5, "S2 total/quantity");
check(lineTotals[2]._id === "S3" && lineTotals[2].total.toString() === "3.00",
  "S3 total");
```

For parent totals after expansion, regroup by the parent identity and deliberately select a single parent amount before summing across parents.

## 7. Bounded facet report

```javascript
var faceted = lab.orders.aggregate([
  { $facet: {
    summary: [
      { $group: { _id: null, orderCount: { $sum: 1 }, total: { $sum: "$amount" } } },
      { $project: { _id: 0, orderCount: 1, total: 1 } }
    ],
    byCustomer: [
      { $group: { _id: "$customerId", total: { $sum: "$amount" } } },
      { $sort: { _id: 1 } }
    ],
    sample: [
      { $sort: { amount: -1, _id: 1 } }, { $limit: 2 },
      { $project: { _id: 1, amount: 1 } }
    ]
  } }
]).toArray();
check(faceted.length === 1, "Expected one facet result");
check(faceted[0].summary[0].orderCount === 4 &&
  faceted[0].summary[0].total.toString() === "23.00", "Facet reconciliation");
check(JSON.stringify(faceted[0].sample.map(order => order._id)) ===
  JSON.stringify(["O1", "O2"]), "Bounded facet sample");
printjson(faceted);
```

Each facet branch returns an array inside the final result. Unbounded branch output can exceed stage/result limits. $facet has a stage-specific 100 MB limit that allowDiskUse does not remove, and the final BSON document still has a size limit.

For production, filter the intended source early, bound branch cardinality and inspect actual index/plan behavior. A facet as the first stage does not create an index-friendly filter by itself.

## 8. Running totals with windows

```javascript
var running = lab.orders.aggregate([
  { $match: { customerId: "C1" } },
  { $setWindowFields: {
    partitionBy: "$customerId",
    sortBy: { createdAt: 1, _id: 1 },
    output: {
      runningTotal: { $sum: "$amount", window: { documents: ["unbounded", "current"] } }
    }
  } },
  { $sort: { createdAt: 1, _id: 1 } }
]).toArray();
check(running[0]._id === "O1" && running[0].runningTotal.toString() === "12.00",
  "First running total");
check(running[1]._id === "O2" && running[1].runningTotal.toString() === "20.00",
  "Second running total");
```

The window accumulates within customerId in defined order. The final sort states the API output order explicitly; do not assume a window stage alone guarantees the final result order.

Document windows and time/range windows have different requirements. This lab uses a document window with a unique tie-breaker.

## 9. Production diagnostics

For a representative pipeline, inspect the actual explain plan and record source matches, join fan-out, unwind output, grouped rows, examined keys/documents and any sort/spill evidence available in that release.

executionStats executes work, so bound diagnostic queries appropriately. The tiny fixture is a correctness exercise rather than a performance benchmark.

A pipeline can be syntactically valid and return a plausible total while losing unmatched parents or multiplying amounts. Reconciliation across known source invariants is essential.

## 10. Troubleshooting

| Symptom | Evidence | Action |
|---|---|---|
| Total multiplied after lookup | Foreign-key match cardinality | Establish intended uniqueness or explicit many-match semantics |
| Total multiplied after unwind | Row grain and parent amount | Sum line values or regroup parents first |
| Records disappear | Empty/missing join arrays and unwind options | Choose preserve semantics and report unresolved keys |
| Facet result too large | Branch output counts and BSON size | Bound branches; allowDiskUse is not a universal fix |
| Running totals wrong | Partition and ordering keys | Define correct partition and deterministic document order |
| Join unexpectedly empty | Key BSON types and values | Fix type mismatch or resolve missing canonical data |
| Pipeline costly | Early filters, indexes, fan-out and sort plan | Reduce cardinality and inspect actual execution |

## 11. Acceptance and cleanup

```javascript
var source = lab.orders.aggregate([
  { $group: { _id: null, count: { $sum: 1 }, total: { $sum: "$amount" } } }
]).toArray();
check(source[0].count === 4 && source[0].total.toString() === "23.00",
  "Source must remain unchanged");
print("PASS: join cardinality, unwind grain, facets and running totals");
check(lab.getName() === "mongodb_enterprise_tutorial_ch14", "Unexpected cleanup database");
names.forEach(name => lab.getCollection(name).drop());
check(!names.some(name => lab.getCollectionNames().includes(name)), "Cleanup failed");
print("PASS: Chapter 14 collections removed");
```

- [ ] Verify zero/one-match canonical lookup behavior.
- [ ] Demonstrate inner-like/left-like expansion.
- [ ] Reproduce totals inflated by non-unique joins and item unwind.
- [ ] Reconcile correct line-item and source totals.
- [ ] Verify bounded facets and ordered running totals.
- [ ] Capture source-preservation and cleanup assertions.

**Authoring validation:** JavaScript syntax and official join/unwind/window references reviewed. Runtime execution pending; record exact versions, operator, date and outputs after running.

Review questions:

1. At what grain should each monetary value be summed?
2. Why does a left-like join need an explicit unwind choice?
3. Why is selecting the first foreign match not always a repair?
4. Which limits remain even when allowDiskUse is enabled?
5. Why must window partition/order and final output order be specified separately?

## Technical references

- [$lookup — 8.0](https://www.mongodb.com/docs/v8.0/reference/operator/aggregation/lookup/)
- [$unwind — 8.0](https://www.mongodb.com/docs/v8.0/reference/operator/aggregation/unwind/)
- [$facet — 8.0](https://www.mongodb.com/docs/v8.0/reference/operator/aggregation/facet/)
- [$setWindowFields — 8.0](https://www.mongodb.com/docs/v8.0/reference/operator/aggregation/setWindowFields/)
- [Aggregation limits — 8.0](https://www.mongodb.com/docs/v8.0/core/aggregation-pipeline-limits/)

Previous: [Chapter 13 — Aggregation Pipeline Fundamentals](13-aggregation-pipeline-fundamentals.md).  
Next: [Chapter 15 — Pagination and API Query Design](15-pagination-and-api-query-design.md).  
Return to the [master layout](MASTER-LAYOUT.md).
