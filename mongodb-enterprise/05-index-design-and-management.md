# 05 — Index Design and Management

**Status:** Draft

**Objective:** Design indexes from query patterns and assess changes safely.

**Prerequisite:** Tutorial 03's validated test collection and index-management permissions.

## Index purpose

Indexes can avoid collection scans but consume memory/storage and add write work.

| Type | Typical purpose |
|---|---|
| Single-field | Filter/sort on one field |
| Compound | Multiple-field query |
| Unique | Enforce uniqueness |
| Multikey | Array values |
| TTL | Expire eligible documents |

## Inspect and design

```javascript
use mongodb_tutorials
db.tutorial_products.getIndexes()

db.tutorial_products.createIndex(
  { category: 1, name: 1, price: 1 },
  { name: "category_name_price" }
)
```

An ordinary collection already has an _id index. The candidate supports equality on category, sort by name, and range on price.

Equality–Sort–Range is a useful starting guideline. A highly selective range may justify range before sort; compare plans and actual workload. Prefixes and field order affect other queries.

## Test data

```javascript
db.tutorial_products.insertMany([
  {
    _id: "tutorial-index-1001",
    name: "Keyboard", category: "accessories",
    price: Decimal128("49.99"),
    inventory: { quantity: Int32(25) }
  },
  {
    _id: "tutorial-index-1002",
    name: "Mouse", category: "accessories",
    price: Decimal128("19.99"),
    inventory: { quantity: Int32(10) }
  }
])
```

## Inspect the plan

```javascript
db.tutorial_products.find({
  category: "accessories",
  price: { $lte: Decimal128("50.00") }
})
.sort({ name: 1 })
.limit(10)
.explain("executionStats")
```

Check winning plan/index name, nReturned, totalKeysExamined, totalDocsExamined, and explicit sort stages. ExecutionStats runs the query; bound production diagnostics. A tiny dataset may select a collection scan and cannot prove performance improvement.

## Review usage and removal

```javascript
db.tutorial_products.aggregate([{ $indexStats: {} }])
db.tutorial_products.hideIndex("category_name_price")
// Repeat the query-plan check.
db.tutorial_products.unhideIndex("category_name_price")
```

Usage accesses.ops/since are node-local and cover a limited period. Zero usage does not prove safe removal; include secondary reads, scheduled jobs, and constraints.

Hiding excludes an index from planning but still maintains it. It does not reclaim storage or remove write overhead. Hidden unique indexes still enforce uniqueness.

## Production practices

Check overlapping indexes, duplicate data before uniqueness changes, and exact definitions before removal. Monitor disk, CPU, lag and latency during builds. Rebuilding a dropped index has cost and duration. Confirm deployed-version support.

## Cleanup

```javascript
db.tutorial_products.deleteMany({
  _id: { $in: ["tutorial-index-1001", "tutorial-index-1002"] }
})
// Only if the exercise created this index solely for testing:
db.tutorial_products.dropIndex("category_name_price")
```

## References

- [ESR guideline](https://www.mongodb.com/docs/manual/tutorial/equality-sort-range-guideline/)
- [Hidden indexes](https://www.mongodb.com/docs/manual/core/index-hidden/)
- [Index statistics](https://www.mongodb.com/docs/manual/reference/operator/aggregation/indexStats/)

**Next:** 06 — Query Performance and explain() (planned).
