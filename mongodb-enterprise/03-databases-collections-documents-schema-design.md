# 03 — Databases, Collections, Documents, and Schema Design

**Status:** Draft

**Objective:** Organize documents and enforce consistent BSON types.

## Embedding versus references

| Embed when | Reference when |
|---|---|
| Related data is read together | Entities are accessed independently |
| Nested data has bounded growth | Related data grows substantially |
| A single-document update is useful | Duplication is difficult to maintain |

Embed a small inventory summary, but consider a separate collection for expanding event history. Avoid unbounded arrays and continually growing documents.

## Create a validated test collection

Connect with a permitted test identity. This is a new collection; do not drop an existing one merely to rerun the exercise.

```javascript
use mongodb_tutorials

db.createCollection("tutorial_products", {
  validator: {
    $jsonSchema: {
      bsonType: "object",
      required: ["name", "price", "inventory"],
      properties: {
        name: { bsonType: "string" },
        price: { bsonType: "decimal", minimum: 0 },
        inventory: {
          bsonType: "object",
          required: ["quantity"],
          properties: {
            quantity: { bsonType: "int", minimum: 0 }
          }
        },
        tags: {
          bsonType: "array",
          items: { bsonType: "string" }
        }
      }
    }
  },
  validationLevel: "strict",
  validationAction: "error"
})
```

Additional fields remain allowed. Required fields and types are enforced on writes under this configuration.

## Valid and invalid inserts

```javascript
db.tutorial_products.insertOne({
  _id: "tutorial-product-1001",
  name: "Keyboard",
  price: Decimal128("49.99"),
  inventory: { quantity: Int32(25) },
  tags: ["electronics", "accessories"]
})

db.tutorial_products.insertOne({
  _id: "tutorial-product-invalid",
  name: "Mouse",
  price: "19.99",
  inventory: { quantity: Int32(10) }
})
```

The first insert is acknowledged. The second fails validation because price is a string. Explicit BSON constructors match the schema.

## Query nested fields

```javascript
db.tutorial_products.find(
  {
    _id: "tutorial-product-1001",
    "inventory.quantity": { $gt: 0 }
  },
  { _id: 1, name: 1, price: 1, "inventory.quantity": 1 }
)
```
Dot notation selects nested fields; projection limits returned fields.

## Production practices

Standardize names/types, use BSON dates, include tenant scope where needed, bound arrays, and index real query patterns. Review existing data before stricter validation. Validation does not automatically repair existing documents; coordinate migration and writer compatibility.

## Validation and cleanup

```javascript
db.tutorial_products.findOne({ _id: "tutorial-product-invalid" })
db.tutorial_products.deleteOne({ _id: "tutorial-product-1001" })
```

Expect null for the invalid document. Preserve the collection/validator for subsequent tutorials.

## References

- [Schema validation](https://www.mongodb.com/docs/manual/core/schema-validation/specify-json-schema/)
- [Data modeling](https://www.mongodb.com/docs/manual/data-modeling/best-practices/)

**Next:** [04 — CRUD and Upserts](04-crud-operations-and-upserts.md)
