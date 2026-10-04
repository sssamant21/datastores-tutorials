# 18 — Transactions, Sessions, and Retries

**Status:** Draft; live lab not run.

**Objective:** Commit related changes together and handle transaction failures correctly.

## Concepts

Single-document writes are atomic. Use a multi-document transaction only when an invariant spans documents and embedding cannot satisfy the access pattern. Transactions require a replica set or sharded cluster, not a standalone.

| Setting | Purpose |
|---|---|
| Session | Associates sequential operations and transaction state |
| snapshot read concern | Consistent transaction snapshot with appropriate commit concern |
| majority write concern | Commit acknowledgement policy |
| primary read preference | Required for transactions containing reads |

Keep transactions short. Do not perform network calls, user interaction or parallel operations inside them. Causal consistency outside a transaction requires the appropriate session and read/write concerns; it is not global serializability.

## Lab: abort and commit

Use a dedicated staging replica set. In mongosh, seed two unique test accounts:
```javascript
var txDb = db.getSiblingDB("mongodb_tutorials")
var txRun = new ObjectId().toHexString()
var txA = txRun + "-A", txB = txRun + "-B"
txDb.tutorial_accounts.insertMany([
  { _id: txA, balance: Int32(100) },
  { _id: txB, balance: Int32(0) }
], { writeConcern: { w: "majority" } })
var txSession = db.getMongo().startSession()
var txAccounts = txSession.getDatabase("mongodb_tutorials").tutorial_accounts
```

Run this block first with false, then true:
```javascript
var txCommit = false
try {
  txSession.startTransaction({
    readConcern: { level: "snapshot" },
    writeConcern: { w: "majority" }
  })
  var debit = txAccounts.updateOne(
    { _id: txA, balance: { $gte: 10 } }, { $inc: { balance: -10 } }
  )
  if (debit.modifiedCount !== 1) throw new Error("Insufficient balance")
  var credit = txAccounts.updateOne({ _id: txB }, { $inc: { balance: 10 } })
  if (credit.modifiedCount !== 1) throw new Error("Destination missing")
  if (txCommit) txSession.commitTransaction()
  else txSession.abortTransaction()
} catch (error) {
  try { txSession.abortTransaction() } catch (_) {}
  throw error
}
txDb.tutorial_accounts.find({ _id: { $in: [txA, txB] } }).sort({ _id: 1 })
```

Expected: abort leaves 100/0; one committed run gives 90/10. This shell exercise intentionally does not implement automatic retries. An unknown commit result needs reconciliation, not a blind new transfer.

## Driver retries

Use the driver's transaction callback API. TransientTransactionError can require retrying the whole transaction; UnknownTransactionCommitResult can require retrying commit. Callback execution can repeat: keep external side effects outside it and use durable business idempotency keys. Retryable individual writes do not replace transaction retry logic.

Cleanup after checking outcome:
```javascript
txSession.endSession()
txDb.tutorial_accounts.deleteMany({ _id: { $in: [txA, txB] } })
```

**Evidence:** abort/commit balances, error labels, concern settings and application retry behavior.

## References

- [Transactions](https://www.mongodb.com/docs/manual/core/transactions/)
- [PyMongo transaction callbacks](https://www.mongodb.com/docs/languages/python/pymongo-driver/current/crud/transactions/)

**Next:** [19 — Sharding and Shard-Key Design](19-sharding-and-shard-key-design.md).
