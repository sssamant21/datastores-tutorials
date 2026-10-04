# 07 — Aggregation Pipeline Fundamentals

**Status:** Draft

**Objective:** Filter, transform, and summarize documents.

## Stages

| Stage | Purpose |
|---|---|
| $match | Filter |
| $project | Select/reshape fields |
| $group | Group and summarize |
| $sort / $limit | Order and bound output |
| $unwind | Expand array elements |
| $lookup | Join related data |

Ordinary aggregation reads do not change stored documents. $merge and $out can write results.

## Test data

```javascript
use mongodb_tutorials
db.tutorial_sales.insertMany([
  { _id: "tutorial-sale-1001", status: "completed", category: "accessories", quantity: Int32(2), unitPrice: Decimal128("20.00") },
  { _id: "tutorial-sale-1002", status: "completed", category: "accessories", quantity: Int32(1), unitPrice: Decimal128("30.00") },
  { _id: "tutorial-sale-1003", status: "completed", category: "displays", quantity: Int32(1), unitPrice: Decimal128("200.00") },
  { _id: "tutorial-sale-1004", status: "cancelled", category: "displays", quantity: Int32(1), unitPrice: Decimal128("100.00") }
])
```

## Revenue by category

```javascript
const revenuePipeline = [
  { $match: {
      _id: { $in: ["tutorial-sale-1001", "tutorial-sale-1002", "tutorial-sale-1003", "tutorial-sale-1004"] },
      status: "completed"
  }},
  { $group: {
      _id: "$category",
      unitsSold: { $sum: "$quantity" },
      revenue: { $sum: { $multiply: ["$quantity", "$unitPrice"] } }
  }},
  { $sort: { revenue: -1, _id: 1 } },
  { $project: { _id: 0, category: "$_id", unitsSold: 1, revenue: 1 } }
]

db.tutorial_sales.aggregate(
  revenuePipeline,
  { maxTimeMS: 2000, allowDiskUse: false }
)
```

Expected Decimal128 totals:

| Category | Units | Revenue |
|---|---:|---:|
| displays | 1 | 200.00 |
| accessories | 3 | 70.00 |

Cancelled sale is excluded. "$category" accesses a field, multiply calculates a line amount, and sum accumulates within a group. Limiting before grouping changes totals to that subset.

## Inspect execution

```javascript
db.tutorial_sales.explain("executionStats").aggregate(
  revenuePipeline,
  { maxTimeMS: 2000, allowDiskUse: false }
)
```

Inspect initial access, examined work, grouping and sorting. Lab _id filters isolate records; real reports may need tenant/status/date indexes.

## Performance and troubleshooting

Filter early where semantics allow, bound report windows, avoid huge accumulated arrays, and watch expansion from unwind/lookup. Disk use permits eligible spilling but can add I/O and does not remove all memory limits. Returned documents remain subject to the BSON size limit.

Wrong totals: check filters, types, and stage order. Duplicated totals after unwind: check repeated amounts. Slow pipeline: investigate scan, joins, groups and sort. Memory errors: inspect cardinality and spill policy.

## Cleanup

```javascript
db.tutorial_sales.deleteMany({
  _id: { $in: ["tutorial-sale-1001", "tutorial-sale-1002", "tutorial-sale-1003", "tutorial-sale-1004"] }
})
```

## References

- [Aggregation](https://www.mongodb.com/docs/manual/core/aggregation-pipeline/)
- [Pipeline limits](https://www.mongodb.com/docs/manual/core/aggregation-pipeline-limits/)

**Next:** [08 — Replication](08-replica-sets-replication-read-write-concerns.md)
