# 27 — Transactions and Programmability

**Status:** Draft; live lab not run.

**Objective:** Use atomic command groups and conditional updates with understood limits.

| Mechanism | Purpose |
|---|---|
| Pipeline | Reduce round trips; nontransactional batches are not atomic |
| MULTI/EXEC | Queue/execute a serialized command group within supported scope |
| WATCH | Abort conditional execution if watched data changes |
| Lua / Functions | Bounded server-side logic with atomic execution scope |

Runtime errors do not roll back already successful Redis transaction commands. Check every EXEC result. For sharded/Active-Active databases, verify command support, key placement and atomicity scope first; do not assume cross-shard transactions/scripts. Hash-tag colocation requires the database's documented hashing configuration.

## Single-key transaction lab

Use an isolated compatible database:
```redis
SET tutorial:atomic:counter 0 EX 300
MULTI
INCR tutorial:atomic:counter
EXPIRE tutorial:atomic:counter 300
EXEC
GET tutorial:atomic:counter
```
Expected EXEC replies: 1 and 1; GET returns 1. DISCARD cancels queued work before execution. To test WATCH, watch this key in session A, update it in B, then queue/EXEC in A; expect abort/null and use bounded retries.

## Ownership-checked Lua release

Use only a disposable lock with a unique owner token:
```redis
SET tutorial:atomic:lock lab-owner-token NX PX 5000
EVAL "if redis.call('GET',KEYS[1]) == ARGV[1] then return redis.call('DEL',KEYS[1]) else return 0 end" 1 tutorial:atomic:lock lab-owner-token
DEL tutorial:atomic:counter
```

Expected release 1 only if ownership still matches. A lease can expire while a worker continues; protect correctness-critical downstream writes with fencing or another suitable protocol. Atomic scripts block competing execution within their scope: keep them bounded and declare keys explicitly. Errors do not provide general rollback.

Functions have version/Enterprise support requirements. Version libraries, deploy through approved lifecycle, test failover/persistence and track changes. EVALSHA clients need a NOSCRIPT reload policy.

## References

- [Transactions](https://redis.io/docs/latest/develop/using-commands/transactions/)
- [Programmability](https://redis.io/docs/latest/develop/programmability/)

**Next:** [28 — Advanced Client Integration](28-advanced-client-integration.md).
