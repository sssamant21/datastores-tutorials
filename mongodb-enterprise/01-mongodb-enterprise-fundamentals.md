# 01 — MongoDB Enterprise Fundamentals

**Status:** Draft

**Objective:** Understand the document model, deployment components, and Enterprise capabilities.

## What is MongoDB?

MongoDB stores records as BSON documents supporting nested objects, arrays, dates, and other types. Common use cases include application records, preferences, catalogs, and events.

| Component | Purpose |
|---|---|
| Database | Groups collections |
| Collection | Groups documents |
| Document | Stores field-value pairs |
| Index | Helps locate matching data |

Flexible schemas still need deliberate design. Validation can enforce required fields and types.

## Enterprise capabilities

MongoDB Enterprise includes auditing and an encrypted storage engine for encryption at rest. These require configuration; installation does not enable them automatically. Ops Manager provides management, monitoring, and backup for supported self-managed deployments.

CRUD, indexes, aggregation, and replica sets are core MongoDB features, not Enterprise-only capabilities.

## Deployment components

| Component | Purpose |
|---|---|
| mongod | Database server process |
| Replica set | Maintains copies of a dataset |
| Primary | Receives replica-set writes |
| Secondary | Replicates data |
| mongos | Routes sharded-deployment requests |
| mongosh | Interactive shell |

Replica sets support elections and redundancy. Applications must handle election interruptions. Replication does not replace backups against accidental changes.

## Hands-on exercise

Connect to a test deployment using Tutorial 02 and a scoped read/write identity.

```javascript
use mongodb_tutorials

db.products.insertOne({
  _id: "tutorial-product-1001",
  name: "Keyboard",
  price: 49.99,
  inventory: { available: true, quantity: 25 }
})

db.products.findOne({ _id: "tutorial-product-1001" })

db.products.updateOne(
  { _id: "tutorial-product-1001" },
  { $set: { "inventory.quantity": 24 } }
)

db.products.findOne(
  { _id: "tutorial-product-1001" },
  { _id: 0, name: 1, "inventory.quantity": 1 }
)

db.products.deleteOne({ _id: "tutorial-product-1001" })
```

Expect acknowledged insertion and quantity 24 after update. Repeating the insert before cleanup produces a duplicate-key error.

The first write can create the database and collection; use alone does not persist a database. This introductory price is a double; Tutorial 03 uses Decimal128 for a deliberate monetary schema.

## Production practices and completion

Design around access patterns, enforce important schema rules, index critical queries, configure authentication/TLS, choose read/write concerns deliberately, monitor latency/replication/storage, and test restores.

Completion: explain documents and topology, distinguish Enterprise features, and perform basic CRUD.

## References

- [Databases and collections](https://www.mongodb.com/docs/manual/core/databases-and-collections/)
- [Replication](https://www.mongodb.com/docs/manual/replication/)
- [Encryption at rest](https://www.mongodb.com/docs/manual/core/security-encryption-at-rest/)
- [Auditing](https://www.mongodb.com/docs/manual/tutorial/configure-auditing/)

**Next:** [02 — Connecting Securely](02-connecting-securely-with-mongosh.md)
