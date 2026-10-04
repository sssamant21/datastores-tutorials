# 7 — Cache Updates and Invalidation

**Status:** Draft

**Objective:** Keep cached data consistent with source updates.

**Prerequisite:** Connected test Redis Enterprise database; Python examples reuse the client from Tutorial 06.

## Update flow

1. Commit the source database change.
2. Delete the corresponding cached entry.
3. Let the next cache miss load the new value.

Do not invalidate before committing: a reader could repopulate old source data while the update is pending.

## Example

The source update below is an application integration point; it must return only after commit.

```python
def update_product(product_id, changes, commit_source_update):
    updated = commit_source_update(product_id, changes)
    key = f"tutorial:catalog:product:{product_id}:v1"
    try:
        cache.delete(key)
    except redis.exceptions.RedisError:
        logger.error("Cache invalidation failed; repair required")
        # Production: record a durable repair event via an outbox/queue.
    return updated
```

A successful source update must not be reported as rolled back merely because invalidation failed. Logging alone does not guarantee repair. A transactional outbox can record the change with the source transaction, then retry invalidation through a worker.

## Hands-on validation

Simulate old cached data:
```redis
SET tutorial:catalog:product:1001:v1 '{"price":49.99}' EX 300
GET tutorial:catalog:product:1001:v1
```

Update the source price to 44.99 through your application, then:
```redis
DEL tutorial:catalog:product:1001:v1
GET tutorial:catalog:product:1001:v1
```

Expect nil. Invoke the Tutorial 06 function using the updated source; verify Redis now contains 44.99.

## Race conditions and related keys

A reader can fetch old source data before a commit, then populate it after invalidation. Commit-then-delete reduces risk but does not eliminate this race. TTL bounds the residence time after population, not necessarily the age of the source data.

For stronger consistency, use a designed version-aware protocol or bypass caching for correctness-critical reads. Versioned payload keys alone do not solve races.

Also invalidate affected list, summary, and query-result caches. Maintain explicit dependencies or generation keys rather than scanning and deleting an entire production keyspace.

## Completion

Verify old value → source update → invalidation → fresh reload. Define what happens when invalidation fails.

## References

- [DEL](https://redis.io/docs/latest/commands/del/)
- [Cache-aside guidance](https://redis.io/learn/howtos/solutions/microservices/caching)

**Next:** [08 — Memory Management](08-memory-management-and-eviction.md)
