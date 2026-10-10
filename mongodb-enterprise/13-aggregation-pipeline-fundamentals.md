# 13 — Aggregation Pipeline Fundamentals

**Status:** Written; static review complete; runtime lab validation pending  
**Part:** 2 — Data Modeling and Application Development  
**Goal:** Build a reconciled synthetic claims summary while identifying stage-order and mixed-type errors.  
**Audience:** Developers, Data Engineers, DBREs and SREs  
**Time:** 60–90 minutes  
**Baseline:** MongoDB 8.0/mongosh; record exact versions.  
**Deployment:** Community-compatible or Enterprise training database. Read-only pipelines; no $merge or $out.

## 1. Each stage consumes the preceding output

A pipeline filters, reshapes, groups and sorts documents. Its stages change both data shape and cardinality. A field removed by an early projection is unavailable later; a group output is not the original claim document.

| Stage/expression | Role |
|---|---|
| $match | Filter the current stream |
| $project | Select/compute output fields |
| $set | Add or replace fields in the current stream |
| $group | Produce grouped results with accumulators |
| $sort | Establish output order |
| $limit | Bound output after the preceding stages |
| $count | Count current-stream documents |
| $sum / $avg | Accumulate numeric values |
| $type / $convert | Inspect or explicitly convert values |

An aggregate command normally reads data. Pipelines with $merge or $out write output, so review those separately. Update pipelines support a subset of aggregation stages.

## 2. Define the reconciliation contract

The report will include only approved claims, group by region, calculate count/total and return a deterministic order. amount must be Decimal128. A malformed string amount should be detected, not silently treated as zero.

The authoritative reconciliation is the known synthetic fixture, not whether the query returns without an exception.

## 3. Setup

Connect through the approved training URI with collection creation, CRUD and cleanup access in **mongodb_enterprise_tutorial_ch13**. Run all blocks in one mongosh session.

```javascript
var lab = db.getSiblingDB("mongodb_enterprise_tutorial_ch13");
if (lab.getCollectionNames().includes("claims")) throw new Error("Existing chapter collection");
lab.createCollection("claims");
function check(ok, message) { if (!ok) throw new Error(message); }

lab.claims.insertMany([
  { _id: "C1", region: "east", status: "approved", amount: Decimal128("10.00") },
  { _id: "C2", region: "east", status: "approved", amount: Decimal128("20.00") },
  { _id: "C3", region: "west", status: "approved", amount: Decimal128("40.00") },
  { _id: "C4", region: "west", status: "pending", amount: Decimal128("100.00") },
  { _id: "C5", region: "east", status: "approved", amount: "5.00" }
]);
check(lab.claims.countDocuments({}) === 5, "Expected five fixtures");
```

Expected approved count is four. The correct total after repairing C5 is 75.00; pending C4 must not contribute.

## 4. Inventory types before accumulating

```javascript
var types = lab.claims.aggregate([
  { $match: { status: "approved" } },
  { $group: { _id: { $type: "$amount" }, count: { $sum: 1 } } },
  { $sort: { _id: 1 } }
]).toArray();
printjson(types);
check(types.find(row => row._id === "decimal").count === 3, "Expected three approved decimals");
check(types.find(row => row._id === "string").count === 1, "Expected one malformed string");
```

A numeric accumulator can ignore nonnumeric values. A returned total can therefore be incomplete even when the command succeeds.

Demonstrate the failure:

```javascript
var flawed = lab.claims.aggregate([
  { $match: { status: "approved" } },
  { $group: { _id: null, count: { $sum: 1 }, total: { $sum: "$amount" } } }
]).toArray();
check(flawed[0].count === 4, "Approved record count");
check(flawed[0].total.toString() === "70.00", "Expected omitted string contribution");
printjson(flawed);
```

The count includes C5 while the numeric total does not. Never accept this mismatch as a valid report without a defined invalid-value policy.

## 5. Preview and apply a scoped repair

```javascript
var preview = lab.claims.aggregate([
  { $match: { _id: "C5" } },
  { $project: {
    _id: 1, original: "$amount",
    converted: { $convert: { input: "$amount", to: "decimal", onError: null, onNull: null } }
  } }
]).toArray();
check(preview[0].converted !== null && preview[0].converted.toString() === "5.00",
  "Expected known decimal conversion");
lab.claims.updateOne({ _id: "C5", amount: "5.00" },
  { $set: { amount: preview[0].converted } });
check(lab.claims.countDocuments({ amount: { $type: "decimal" } }) === 5,
  "All fixture amounts should now be decimal");
```

Only the known synthetic value is repaired. Production conversion needs quarantine, precision policies, batching, compatible writers and reconciliation as described in Chapter 11.

## 6. Build the report stage by stage

```javascript
var approved = { $match: { status: "approved" } };
var grouped = { $group: {
  _id: "$region",
  count: { $sum: 1 },
  total: { $sum: "$amount" },
  average: { $avg: "$amount" }
} };
var report = lab.claims.aggregate([
  approved,
  grouped,
  { $project: { _id: 0, region: "$_id", count: 1, total: 1, average: 1 } },
  { $sort: { region: 1 } }
]).toArray();
printjson(report);

check(report.length === 2, "Expected two regions");
check(report[0].region === "east" && report[0].count === 3 &&
  report[0].total.toString() === "35.00", "East reconciliation");
check(report[1].region === "west" && report[1].count === 1 &&
  report[1].total.toString() === "40.00", "West reconciliation");
```

Average display/scale can vary with decimal calculation. The exact count and sum are the acceptance values.

A group stage does not guarantee result order. The explicit final sort makes the returned region order predictable.

## 7. Filter group results rather than source documents

```javascript
var highTotal = lab.claims.aggregate([
  approved,
  grouped,
  { $match: { total: { $gte: Decimal128("40.00") } } },
  { $sort: { _id: 1 } }
]).toArray();
check(highTotal.length === 1 && highTotal[0]._id === "west",
  "Expected one group meeting the total threshold");
```

The post-group filter uses a computed total that does not exist on the source documents. Moving it before grouping changes or breaks the intended meaning.

Place filters early when semantics permit, but do not mechanically move every match before the field it depends on exists.

## 8. Failure exercise — remove a needed field

```javascript
var broken = lab.claims.aggregate([
  approved,
  { $project: { region: 1 } },
  { $group: { _id: "$region", total: { $sum: "$amount" } } },
  { $sort: { _id: 1 } }
]).toArray();
check(broken.every(row => row.total === 0), "Expected missing amount to produce zero sums");
```

The early projection removed amount. The pipeline is syntactically valid but produces the wrong business result.

Correct by retaining amount or removing the unnecessary early projection:

```javascript
var corrected = lab.claims.aggregate([
  approved,
  { $project: { region: 1, amount: 1 } },
  { $group: { _id: "$region", total: { $sum: "$amount" } } },
  { $sort: { _id: 1 } }
]).toArray();
check(corrected[0].total.toString() === "35.00" &&
  corrected[1].total.toString() === "40.00", "Corrected projection report");
```

MongoDB can optimize some projection/filter arrangements. Write for correct semantics first, then inspect the actual plan rather than assuming early projection always improves performance.

## 9. Literal values and field paths

```javascript
var labeled = lab.claims.aggregate([
  { $match: { _id: "C1" } },
  { $project: {
    _id: 0,
    copiedRegion: "$region",
    literalLabel: { $literal: "$region" }
  } }
]).toArray();
check(labeled[0].copiedRegion === "east", "Field-path expression");
check(labeled[0].literalLabel === "$region", "Literal dollar-prefixed value");
```

A string beginning with $ can be an expression field path. Use $literal when the intended value is literal text in an expression context.

## 10. Bounded output and empty results

```javascript
var top = lab.claims.aggregate([
  approved,
  { $sort: { amount: -1, _id: 1 } },
  { $limit: 2 },
  { $project: { _id: 1, amount: 1 } }
]).toArray();
check(JSON.stringify(top.map(doc => doc._id)) === JSON.stringify(["C3", "C2"]),
  "Expected top two approved claims");

var emptyCount = lab.claims.aggregate([
  { $match: { status: "does-not-exist" } }, { $count: "count" }
]).toArray();
check(emptyCount.length === 0, "Empty count pipeline should return no result document");
var apiCount = emptyCount.length ? emptyCount[0].count : 0;
check(apiCount === 0, "Application should normalize an empty count result deliberately");
```

A $count stage on no input returns no result document, not a document with count zero. Handle that API boundary explicitly.

Sorting then limiting returns the top two. Limiting before sorting considers only the limited input subset and is a different operation.

## 11. Explain and operational boundaries

```javascript
var plan = lab.claims.explain("executionStats").aggregate([
  { $match: { status: "approved" } },
  { $sort: { amount: -1, _id: 1 } },
  { $limit: 2 }
]);
printjson(plan);
```

executionStats executes the query. This small lab is safe to inspect; a large production pipeline may be expensive even when used only for diagnosis.

Record actual plan stages and examined/returned counts where present. The explain shape varies with server version and execution engine. No index-efficiency or latency threshold is asserted here.

Avoid unbounded result materialization, giant group arrays and unnecessary sorts. allowDiskUse is not a universal cure for poor pipeline shape; different stages have different memory and output limits.

## 12. Troubleshooting

| Symptom | Evidence | Action |
|---|---|---|
| Total too small | Numeric type distribution | Classify/repair invalid values |
| Total zero after projection | Current stage's field shape | Preserve required fields |
| Unexpected group ordering | Explicit sort | Sort after grouping |
| Empty API count errors | Empty count result array | Normalize absence according to contract |
| Top-N result incorrect | Sort/limit order | Sort the intended full candidate set before limiting |
| Literal text becomes null/missing | Field-path expression syntax | Use $literal for dollar-prefixed text |
| Pipeline slow | Plan, cardinality, sorts and indexes | Bound/filter correctly and examine actual execution |
| Aggregation unexpectedly writes | Presence of $merge/$out | Review write stages and target lifecycle |

## 13. Acceptance and cleanup

```javascript
check(lab.claims.countDocuments({}) === 5, "Read pipelines must not alter count");
var reconciled = lab.claims.aggregate([
  approved, { $group: { _id: null, total: { $sum: "$amount" }, count: { $sum: 1 } } }
]).toArray();
check(reconciled[0].count === 4 && reconciled[0].total.toString() === "75.00",
  "Final approved reconciliation");
print("PASS: types, stages, grouping, projection repair, ordering and empty results");
check(lab.getName() === "mongodb_enterprise_tutorial_ch13", "Unexpected cleanup database");
lab.claims.drop();
check(!lab.getCollectionNames().includes("claims"), "Cleanup failed");
print("PASS: Chapter 13 collection removed");
```

- [ ] Detect the initial numeric/string mismatch and wrong total.
- [ ] Repair the known value and reconcile region/global totals.
- [ ] Demonstrate and fix projection field loss.
- [ ] Verify group filtering, literals, top-N and empty counts.
- [ ] Record actual explain output and its limits.
- [ ] Verify cleanup.

**Authoring validation:** JavaScript syntax and official pipeline references reviewed; runtime execution pending. Record exact versions, environment, date, operator and results after running.

Review questions:

1. Why can a successful sum return the wrong business total?
2. Why does group output require its own sort?
3. Which predicates depend on fields created by earlier stages?
4. Why does an early projection not automatically improve a pipeline?
5. Why does executionStats require production cost awareness?

## Technical references

- [Aggregation pipeline — 8.0](https://www.mongodb.com/docs/v8.0/core/aggregation-pipeline/)
- [$group — 8.0](https://www.mongodb.com/docs/v8.0/reference/operator/aggregation/group/)
- [$sum — 8.0](https://www.mongodb.com/docs/v8.0/reference/operator/aggregation/sum/)
- [$count — 8.0](https://www.mongodb.com/docs/v8.0/reference/operator/aggregation/count/)
- [Aggregation limits — 8.0](https://www.mongodb.com/docs/v8.0/core/aggregation-pipeline-limits/)
- [Explain — 8.0](https://www.mongodb.com/docs/v8.0/reference/method/db.collection.explain/)

Previous: [Chapter 12 — Updates Upserts and Bulk Writes](12-updates-upserts-and-bulk-writes.md).  
Next: [Chapter 14 — Advanced Aggregations and Joins](14-advanced-aggregations-and-joins.md).  
Return to the [master layout](MASTER-LAYOUT.md).
