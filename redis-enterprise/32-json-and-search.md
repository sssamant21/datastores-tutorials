# 32 — JSON and Search

**Status:** Draft; live lab not run.

**Objective:** Store structured documents and query an explicit search schema.

JSON.SET stores a Redis JSON value; SET with serialized JSON stores a string. Search indexes are separate structures with memory/CPU cost. Confirm JSON/Search capability, supported versions, commands and topology before this lab.

## JSON lab

On an isolated compatible database:
```redis
JSON.SET tutorial:search:product:1 $ '{"name":"Keyboard","category":"accessories","price":49.99}'
EXPIRE tutorial:search:product:1 300
JSON.GET tutorial:search:product:1 $
JSON.SET tutorial:search:product:1 $.price 44.99
```

## Index/query lab

Create an unused lab index; quote JSON paths when executing through a shell to prevent shell expansion:
```redis
FT.CREATE tutorial-products-idx ON JSON PREFIX 1 tutorial:search:product: SCHEMA $.name AS name TEXT $.category AS category TAG $.price AS price NUMERIC
FT.SEARCH tutorial-products-idx '@category:{accessories} @price:[0 50]' LIMIT 0 10
FT.INFO tutorial-products-idx
```

Wait for initial indexing completion where needed. Expect the test product to match. Inspect index memory, errors and document counts. Search failures require schema/type/indexing investigation, not just cache GET checks.

## Operations

Bound documents/results and expensive aggregate/query work. Define schema changes and index rebuild/cutover procedures. Track indexing failures, memory and query latency. Test expiration/deletion visibility and persistence/restore of both data and index configuration. JSON paths/TAG escaping, response shapes and dialect support vary; test the exact client/version.

Vector search is an optional extension: document dimensions/type/distance metric, validate known-neighbor queries, measure recall/latency and memory. Choose HNSW/FLAT against workload evidence rather than treating vector indexing as ordinary cache storage.

Cleanup index without DD, then exact document:
```redis
FT.DROPINDEX tutorial-products-idx
DEL tutorial:search:product:1
```

**Acceptance:** JSON update, bounded search, index readiness and data/index recovery behavior verified.

## References

- [JSON](https://redis.io/docs/latest/develop/data-types/json/)
- [Search](https://redis.io/docs/latest/develop/ai/search-and-query/)

**Next:** [33 — Management Automation and Configuration Drift](33-management-automation-and-configuration-drift.md).
