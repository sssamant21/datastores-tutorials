# 06 — Query Performance and explain()

**Status:** Draft

**Objective:** Interpret query plans and compare indexed access.

## Explain modes

| Mode | Purpose |
|---|---|
| queryPlanner | Plan without execution to completion |
| executionStats | Executes winning plan and reports work |
| allPlansExecution | Also includes partial candidate-plan statistics |

Explain ignores the existing plan cache and does not cache its winner. Application execution may differ.

## Test dataset

Use a dedicated test collection:
```javascript
use mongodb_tutorials
db.tutorial_query_lab.insertMany([
  { _id: "tutorial-query-1001", category: "accessories", name: "Keyboard", price: Decimal128("49.99") },
  { _id: "tutorial-query-1002", category: "accessories", name: "Mouse", price: Decimal128("19.99") },
  { _id: "tutorial-query-1003", category: "displays", name: "Monitor", price: Decimal128("199.99") }
])
```

Three documents demonstrate plans, not performance at scale.

## Baseline

```javascript
db.tutorial_query_lab.find({ category: "accessories" })
  .sort({ name: 1 })
  .limit(10)
  .maxTimeMS(2000)
  .explain("executionStats")
```

Without a suitable index, expect collection scanning and explicit sorting. maxTimeMS bounds server execution, not overall network/client time.

## Interpret

| Field/stage | Meaning |
|---|---|
| COLLSCAN | Collection scan |
| IXSCAN | Index scan |
| FETCH | Document retrieval |
| SORT | Explicit sorting |
| nReturned | Documents returned |
| totalDocsExamined | Documents examined |
| totalKeysExamined | Index entries examined |
| executionTimeMillis | Reported server execution time |

Output nesting/stages vary by version and engine. IXSCAN alone does not prove efficiency.

## Add and compare

```javascript
db.tutorial_query_lab.createIndex(
  { category: 1, name: 1 },
  { name: "category_name" }
)

db.tutorial_query_lab.find({ category: "accessories" })
  .sort({ name: 1 }).limit(10).maxTimeMS(2000)
  .explain("executionStats")

db.tutorial_query_lab.find({ category: "accessories" })
  .sort({ name: 1 }).limit(10).hint("category_name")
  .maxTimeMS(2000).explain("executionStats")
```

Compare access path, examined work, sorting, and equivalent results. Small data may still use COLLSCAN. Hint demonstrates a chosen access path, not the optimizer's normal choice.

## Findings and practice

Many examined documents for few results suggest selectivity/index investigation. Many keys suggest broad bounds/field order. High indexed latency may involve fetch volume, I/O or contention. Fast explain with slow application suggests checking cached plans, network, pools, concurrency and transfer.

Use representative parameters and projections, bounded execution, and per-shard evidence where applicable. Examined/returned ratios are signals, not universal thresholds.

## Cleanup

```javascript
db.tutorial_query_lab.deleteMany({
  _id: { $in: ["tutorial-query-1001", "tutorial-query-1002", "tutorial-query-1003"] }
})
// Only if created solely for this lab:
db.tutorial_query_lab.dropIndex("category_name")
```

## References

- [Explain results](https://www.mongodb.com/docs/manual/reference/explain-results/)
- [cursor.explain](https://www.mongodb.com/docs/manual/reference/method/cursor.explain/)

**Next:** [07 — Aggregation](07-aggregation-pipeline-fundamentals.md)
