# 19 — Sharding and Shard-Key Design

**Status:** Draft; live lab not run.

**Objective:** Evaluate distribution and query routing before adopting sharding.

## Architecture

mongos routes application operations. Shard replica sets hold distributed data; the config-server replica set holds cluster metadata. Replica sets provide redundancy; sharding distributes data/work across shards.

| Choice | Tradeoff |
|---|---|
| Range key | Supports locality/range routing; monotonic keys can concentrate writes |
| Hashed key | Often spreads values; range queries can contact many shards |
| Compound key | Combines routing/distribution needs; prefix access matters |
| Zones | Placement policy; requires appropriate keys and operational management |

Evaluate cardinality, value frequency, monotonicity, query targeting and tenant skew. A single large/hot tenant can defeat an otherwise sensible tenant key. Hashed distribution does not eliminate hot individual keys.

## Read-only routing exercise

Prerequisite: existing staging sharded cluster, approved monitoring identity and a known sharded collection. Connect through mongos:
```javascript
db.adminCommand({ hello: 1 })
sh.status()
```
Expect hello.msg to identify isdbgrid. Replace namespace/key below with the actual inventory:
```javascript
db.getSiblingDB("shop").orders
  .find({ tenantId: "test-tenant" }).limit(10).explain("queryPlanner")
db.getSiblingDB("shop").orders
  .find({ status: "open" }).limit(10).explain("queryPlanner")
```

Compare contacted shards and plans; shard-key prefix inclusion does not always imply a single shard. Record balancer state, distribution and per-shard load. A tiny dataset cannot prove production balance.

## Balancing and resharding

Balancer moves eligible ranges to satisfy distribution/zone policies; it does not directly balance CPU. Check migrations, storage/network headroom, placement constraints and indivisible hot keys.

Refining adds fields to an existing key; resharding changes data distribution and has release-specific restrictions, capacity requirements and cutover behavior. Plan/rehearse, validate indexes and uniqueness, monitor progress, and define stop/recovery criteria. Do not run generic reshard commands during diagnosis.

## Problems

Scatter-gather: review key/query alignment. Hot shard: inspect skew and routing. Stalled migration: inspect errors, zones and recipient capacity. Slow cutover: inspect long operations and workload. Applications must use mongos rather than bypassing routing through shard members.

**Evidence:** key decision, workload distribution, query routing, uniqueness implications and growth plan.

## References

- [Sharding](https://www.mongodb.com/docs/manual/sharding/)
- [Choose a shard key](https://www.mongodb.com/docs/manual/core/sharding-choose-a-shard-key/)
- [Resharding](https://www.mongodb.com/docs/manual/core/sharding-reshard-a-collection/)

**Next:** [20 — Driver Integration and Connection Pools](20-driver-integration-and-connection-pools.md).
