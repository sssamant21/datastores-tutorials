# 14 — Database Administration

**Status:** Draft

**Audience:** Redis Enterprise administrators, SREs, and DBREs.

## Configuration decisions

| Setting | Decision |
|---|---|
| Name and owner | Identify service, environment, and support owner |
| Memory limit | Size the working set with operational headroom |
| Sharding | Match data size, throughput, and distribution |
| Replication | Match availability requirements |
| Persistence | Match durability requirements |
| Eviction | Match whether data can be discarded |
| Endpoint and TLS | Match network and security requirements |

## Create a test database

1. Sign in to Cluster Manager.
2. Create a database and choose a supported database version.
3. Configure name, memory, endpoint, replication, sharding, persistence, and eviction deliberately.
4. Configure database access and TLS.
5. Record the assigned endpoint; test from the application network.

UI labels and available options vary by version. Some creation-time choices cannot be changed later; consult the installed release documentation.

## Validate

```redis
PING
SET tutorial:admin:database "ready" EX 60
GET tutorial:admin:database
TTL tutorial:admin:database
DEL tutorial:admin:database
```

Expect PONG, OK, the value, and a remaining TTL.

## Change and retirement

Capture current configuration and a rollback plan before edits. Watch shard health and application latency afterward. For retirement, confirm dependencies and ownership, stop writers, preserve any required backup, then use the supported deletion workflow.

Do not use logical key prefixes as substitutes for database resource boundaries.

## Acceptance and references

Acceptance: documented settings, secure endpoint, successful application read/write, and monitoring coverage.

- [Create database](https://redis.io/docs/latest/operate/rs/databases/create/)
- [Database configuration](https://redis.io/docs/latest/operate/rs/databases/configure/)

**Next:** [15 — Security and Access Administration](15-security-and-access-administration.md)
