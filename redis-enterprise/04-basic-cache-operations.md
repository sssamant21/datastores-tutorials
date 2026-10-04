# 04 — Basic Cache Operations

**Status:** Draft

**Objective:** Create, read, update, and delete cached strings.

## Commands

| Command | Purpose |
|---|---|
| SET | Create or replace a string |
| GET | Read a string |
| MGET | Read multiple strings |
| EXISTS | Check existence |
| TTL | Check remaining lifetime |
| DEL | Delete an entry |

Prerequisite: connected test database.

## Create and read
```redis
SET tutorial:product:1001:v1 '{"name":"Keyboard","price":49.99}' EX 300
GET tutorial:product:1001:v1
EXISTS tutorial:product:1001:v1
```

Expect OK, the JSON string, and 1 before expiration. Missing GET returns nil. Deserialize JSON in the application. Use GET directly for cache lookup; EXISTS first adds a request and does not prevent expiration before GET.

## Update and manage expiration
```redis
SET tutorial:product:1001:v1 '{"name":"Keyboard","price":44.99}' EX 300
TTL tutorial:product:1001:v1
SET tutorial:product:1001:v1 '{"name":"Keyboard","price":42.99}' KEEPTTL
```

EX resets the expiration. Plain SET removes the previous TTL. KEEPTTL preserves existing expiration but does not add one if absent.

## Read multiple entries
```redis
SET tutorial:product:1002:v1 '{"name":"Mouse","price":19.99}' EX 300
MGET tutorial:product:1001:v1 tutorial:product:1002:v1
```

Results follow input order, with nil for missing or non-string entries. Bound batch size. Multi-key behavior depends on deployment configuration; validate it for your database and client.

## Invalidate
```redis
DEL tutorial:product:1001:v1
GET tutorial:product:1001:v1
```

Expect 1 if deleted and nil afterward. Invalidate after a successful source database update; the next request can repopulate the cache.

## Validation and production practices

Verify create, read, replacement with TTL, multi-key reads, and deletion. Handle cache errors separately from misses and keep payloads bounded.

Cleanup:
```redis
DEL tutorial:product:1001:v1 tutorial:product:1002:v1
```

## References

- [SET](https://redis.io/docs/latest/commands/set/)
- [MGET](https://redis.io/docs/latest/commands/mget/)
- [EXISTS](https://redis.io/docs/latest/commands/exists/)

**Next:** [05 — TTL and Expiration](05-ttl-and-expiration.md)
