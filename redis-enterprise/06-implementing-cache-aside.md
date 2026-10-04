# 06 — Implementing Cache-Aside

**Status:** Draft

**Objective:** Load cached data first, fetch missing data from the source, and populate Redis.

## Flow

1. Check Redis.
2. Return a valid cached value on a hit.
3. On a miss, read the source database.
4. Cache the result with TTL and return it.

The application manages this flow; Redis does not fetch source records automatically.

## Setup

Install redis-py:

```bash
python -m pip install redis
```

Provide REDIS_HOST, REDIS_PORT, REDIS_PASSWORD, and REDIS_CA_CERT through environment settings or your secret manager. REDIS_USERNAME is optional for password-only authentication.

## Client and implementation

Create one reusable client. This example assumes a TLS database; add client certificates if mutual TLS is required.

```python
import json
import logging
import os
import random

import redis
from redis.backoff import NoBackoff
from redis.retry import Retry

logger = logging.getLogger(__name__)

cache = redis.Redis(
    host=os.environ["REDIS_HOST"],
    port=int(os.environ["REDIS_PORT"]),
    username=os.getenv("REDIS_USERNAME") or None,
    password=os.environ["REDIS_PASSWORD"],
    ssl=True,
    ssl_ca_certs=os.environ["REDIS_CA_CERT"],
    ssl_cert_reqs="required",
    ssl_check_hostname=True,
    decode_responses=True,
    socket_connect_timeout=1,
    socket_timeout=1,
    retry=Retry(NoBackoff(), 0),
)


def get_product(product_id, fetch_from_database):
    key = f"tutorial:catalog:product:{product_id}:v1"
    cache_available = True

    try:
        cached = cache.get(key)
    except redis.exceptions.RedisError:
        logger.warning("Cache read failed")
        cached = None
        cache_available = False

    if cached is not None:
        try:
            product = json.loads(cached)
            valid = (
                isinstance(product, dict)
                and product.get("id") == product_id
                and isinstance(product.get("name"), str)
                and isinstance(product.get("price"), (int, float))
                and not isinstance(product.get("price"), bool)
            )
            if valid:
                logger.info("Cache hit")
                return product
            logger.warning("Cached product schema mismatch")
        except json.JSONDecodeError:
            logger.warning("Invalid cached JSON")

    logger.info("Loading from source database")
    product = fetch_from_database(product_id)

    if product is not None and cache_available:
        try:
            cache.set(
                key,
                json.dumps(product),
                ex=random.randint(240, 300),
            )
        except redis.exceptions.RedisError:
            logger.warning("Cache write failed")

    return product
```

Cached responses must match the demonstrated product schema (id, name, and numeric price). Adapt validation to your application's schema; the source lookup is expected to return validated records.

A Redis error falls back to the source; a cache write failure still returns the source result. Missing source records are not cached. Source database errors propagate. Adjust timeouts to the request budget.

## Hands-on validation

Append this demonstration to the code and run it in a test environment:

```python
def demo_database_lookup(product_id):
    print("SOURCE READ")
    return {"id": product_id, "name": "Keyboard", "price": 49.99}


cache.delete("tutorial:catalog:product:1001:v1")
print(get_product(1001, demo_database_lookup))
print(get_product(1001, demo_database_lookup))
```

First call prints SOURCE READ and caches the product. Second returns it without another source read.

Inspect using redis-cli:

```redis
GET tutorial:catalog:product:1001:v1
TTL tutorial:catalog:product:1001:v1
DEL tutorial:catalog:product:1001:v1
```

Call again after deletion; expect another SOURCE READ. For an unreachable-endpoint test, skip the initial cache.delete call so the test reaches the function's fallback handling.

## Production practices

- Bound source fallback concurrency and rate.
- Record hits, misses, and cache errors separately.
- Prevent concurrent rebuilds of the same missing key.
- Validate the deserialized payload schema.
- Invalidate after successful source updates.
- Include tenant and permission scope where relevant.

This teaching example is not a complete production resilience implementation. Invalidation races and cache stampedes are addressed later.

## References

- [redis-py connections](https://redis.io/docs/latest/develop/clients/redis-py/connect/)
- [Production usage](https://redis.io/docs/latest/develop/clients/redis-py/produsage/)

**Next:** [07 — Cache Updates and Invalidation](07-cache-updates-and-invalidation.md)
