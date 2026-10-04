# 04 — CRUD Operations and Upserts

**Status:** Draft

**Objective:** Perform CRUD and repeatable upserts.

**Prerequisite:** Tutorial 03's validated test collection.

```javascript
use mongodb_tutorials
```

## Create and read

```javascript
db.tutorial_products.insertOne({
  _id: "tutorial-crud-1001",
  name: "Keyboard",
  price: Decimal128("49.99"),
  inventory: { quantity: Int32(25) }
})

db.tutorial_products.findOne({ _id: "tutorial-crud-1001" })

db.tutorial_products.find(
  { _id: "tutorial-crud-1001", "inventory.quantity": { $gt: 0 } },
  { _id: 1, name: 1, price: 1 }
).limit(10)
```

Expect acknowledged insertion. Repeating the insert before cleanup causes a duplicate-key error. Use projections and bounded reads.

## Update fields

```javascript
db.tutorial_products.updateOne(
  { _id: "tutorial-crud-1001" },
  { $set: { price: Decimal128("44.99") } }
)

db.tutorial_products.updateOne(
  {
    _id: "tutorial-crud-1001",
    "inventory.quantity": { $gte: Int32(1) }
  },
  { $inc: { "inventory.quantity": Int32(-1) } }
)
```

A first changed value returns matchedCount:1 and modifiedCount:1. Repeating identical SET can modify zero documents. The conditional decrement is atomic at the document level and prevents negative stock.

Reissuing INC as a new application operation can decrement twice. Design retries and request deduplication deliberately.

## Upsert for synchronization

```javascript
db.tutorial_products.updateOne(
  { _id: "tutorial-upsert-1002" },
  {
    $set: {
      name: "Mouse",
      price: Decimal128("19.99"),
      "inventory.quantity": Int32(10)
    },
    $setOnInsert: { createdAt: new Date() }
  },
  { upsert: true }
)
```

No match inserts a valid document: upsertedCount:1 and upsertedId. An existing match is updated: matchedCount:1; modification depends on changed values. SETONINSERT applies only to insertion.

Use stable identities and appropriate unique indexes for business-key synchronization. Sharded collections have additional targeting/uniqueness rules dependent on version. Handle concurrent and out-of-order updates.

## Update versus replace

SET preserves other fields. replaceOne replaces the contents except the immutable _id; omitted fields are removed. Replacement must satisfy validation. Use it only for complete intended documents.

## Delete and cleanup

```javascript
db.tutorial_products.deleteOne({ _id: "tutorial-crud-1001" })
db.tutorial_products.findOne({ _id: "tutorial-upsert-1002" })

db.tutorial_products.deleteMany({
  _id: { $in: ["tutorial-crud-1001", "tutorial-upsert-1002"] }
})
```

Check deletedCount, matchedCount, modifiedCount, and upsertedCount. Avoid empty deletion filters; committed deletion has no general undo.

## Production practices and completion

Use precise indexed filters, preserve BSON types, choose write concern for durability, and distinguish repeatable SET from cumulative INC.

Completion: distinguish insertion, field updates, replacement, deletion, and upsert.

## References

- [updateOne](https://www.mongodb.com/docs/manual/reference/method/db.collection.updateOne/)
- [replaceOne](https://www.mongodb.com/docs/manual/reference/method/db.collection.replaceOne/)

**Next:** [05 — Index Design](05-index-design-and-management.md)
