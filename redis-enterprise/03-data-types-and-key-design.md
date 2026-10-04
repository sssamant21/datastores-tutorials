# 03 — Data Types and Key Design

**Status:** Draft

**Objective:** Choose suitable types and consistent cache keys.

## Common types

| Type | Use | Commands |
|---|---|---|
| String | Serialized response or counter | SET, GET, INCR |
| Hash | Field-value record | HSET, HGET, HGETALL |
| List | Ordered strings | LPUSH, LRANGE |
| Set | Unique members | SADD, SISMEMBER |
| Sorted set | Members ordered by score | ZADD, ZRANGE |

Choose a string for whole-object retrieval and replacement; choose a hash when individual fields need access. JSON text written with SET is a string, separate from the Redis JSON data type.

## Key design

Use service:entity:id:version, for example catalog:product:1001:v1. Add tenant or permission scope when results vary by caller.

Colons are a convention, not folders or resource isolation. Include all inputs affecting a cached result. Avoid secrets and sensitive personal information in key names.

## Hands-on example

Prerequisite: connected test database.
```redis
SET tutorial:catalog:product:1001:v1 '{"name":"Keyboard","price":49.99}' EX 300
GET tutorial:catalog:product:1001:v1
TYPE tutorial:catalog:product:1001:v1
HSET tutorial:catalog:product:1002:v1 name "Mouse" price "19.99" stock "25"
EXPIRE tutorial:catalog:product:1002:v1 300
HGET tutorial:catalog:product:1002:v1 price
TYPE tutorial:catalog:product:1002:v1
HSET tutorial:catalog:product:1002:v1 stock "24"
```

Expect types string and hash, and price "19.99". HSET updates cached data only and preserves existing key-level TTL. Creation and EXPIRE are separate operations; production code should apply expiration reliably.

## Type mismatch

GET on the hash returns WRONGTYPE. Use TYPE to inspect it and HGET/HGETALL to read hash fields.

## Production practices and validation

Keep keys readable and reasonably short. Bound payloads and collection sizes; avoid one giant hash for all records. Version changed payload formats and expire old keys. Prefixes alone are not access controls.

Validate both TTLs, then clean up:
```redis
TTL tutorial:catalog:product:1001:v1
TTL tutorial:catalog:product:1002:v1
DEL tutorial:catalog:product:1001:v1 tutorial:catalog:product:1002:v1
```

Completion: select string/hash, design keys, and identify type mismatches.

## References

- [Data types](https://redis.io/docs/latest/develop/data-types/)
- [Keys and values](https://redis.io/docs/latest/develop/using-commands/keyspace/)

**Next:** [04 — Basic Cache Operations](04-basic-cache-operations.md)
