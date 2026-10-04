# 28 — Advanced Client Integration

**Status:** Draft; live lab not run.

**Objective:** Budget pool wait, connection time, command time and retries together.

Use a compatible client for the actual Enterprise endpoint/topology. Do not automatically select a Redis Open Source Cluster client merely because Enterprise has shards. Verify proxy routing, multi-key compatibility and failover behavior.

## Bounded Python client

Install a compatible redis-py version. Supply endpoint/secrets/CA securely; the example assumes verified TLS and optional ACL username:
```python
import os
import redis
from redis.backoff import NoBackoff
from redis.retry import Retry

pool = redis.BlockingConnectionPool(
    host=os.environ["REDIS_HOST"], port=int(os.environ["REDIS_PORT"]),
    username=os.getenv("REDIS_USERNAME") or None,
    password=os.environ["REDIS_PASSWORD"],
    connection_class=redis.SSLConnection,
    ssl_ca_certs=os.environ["REDIS_CA_CERT"],
    ssl_cert_reqs="required", ssl_check_hostname=True,
    decode_responses=True, max_connections=10, timeout=0.2,
    socket_connect_timeout=0.5, socket_timeout=0.5,
    retry=Retry(NoBackoff(), 0),
)
client = redis.Redis(connection_pool=pool)
try:
    assert client.ping()
finally:
    client.close()
    pool.disconnect()
```

Reuse the pool/client throughout application lifetime; close at shutdown. Numbers are lab examples. Mutual TLS also needs the appropriate client certificate/key. Pin driver API compatibility.

## Deadline/retry policy

Pool timeout limits checkout wait, connect timeout limits connection establishment, socket timeout bounds socket operations; these are not a universal end-to-end request deadline. Budget retries/backoff, DNS/TLS and source work within the application deadline. Avoid stacked retry layers.

For uncertain execution, manual INCR/queue-pop replay can duplicate effects. Use operation IDs and reconciliation appropriate to the business action. Permanent auth/permission errors need configuration repair rather than endless retries.

## Staging acceptance

Run bounded concurrency; record pool wait, connections, latency and errors. Test permitted/denied access, invalid trust and scheduled failover. Verify reconnection, bounded requests and no source overload. Compare sequential/pipeline workloads and capture partial-result handling. Log outcome/category without secrets or sensitive keys.

## References

- [redis-py production usage](https://redis.io/docs/latest/develop/clients/redis-py/produsage/)
- [Connect](https://redis.io/docs/latest/develop/clients/redis-py/connect/)

**Next:** [29 — Advanced Caching and Source Protection](29-advanced-caching-and-source-protection.md).
