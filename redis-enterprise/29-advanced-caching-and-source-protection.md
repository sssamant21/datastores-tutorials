# 29 — Advanced Caching and Source Protection

**Status:** Draft; live lab not run.

**Objective:** Design and verify the production controls beyond Tutorial 06's fallback example.

## Patterns

| Pattern | Design requirement |
|---|---|
| Negative cache | Short approved TTL for explicit not-found; distinguish source errors |
| Request coalescing | One source load per key with bounded waiter deadlines |
| Stale serving | Separate freshness/hard-expiry times; business-approved stale window |
| Circuit breaker | Open/half-open policy, limited recovery probes |
| Durable invalidation | Source-transaction outbox, idempotent worker, repair monitoring |
| Source protection | Shared rate/concurrency budget and controlled overload response |

Scope cache identity by tenant/permissions and all result inputs. Never use a cached negative result to suppress permission-sensitive data after access changes.

## Implement the protocol

1. Read and validate payload; classify hit, miss and error separately.
2. If usable stale data is permitted, return it within its hard deadline and schedule bounded refresh.
3. Coalesce by key. The winner rechecks Redis before source lookup; waiters have deadlines.
4. Acquire source capacity; if unavailable, return the documented rejection/stale response.
5. Load with a source deadline; serialize only validated success or explicit not-found.
6. Publish with approved TTL/version policy; release source capacity in finally.
7. Record source commits and invalidation events atomically through the source outbox. Worker retries must be durable and idempotent.

In-process coordination covers one process only. Multiple pods require fleet-wide budgeting and an appropriate coordination design. Distributed leases alone do not solve stale-writer/invalidation races. Prefer single-document/version protocols or bypass caching where correctness requires it.

## Bounded acceptance exercise

Use a synthetic source with known capacity. Launch 20 concurrent requests for one absent key; verify the selected scope permits only the intended number of source reads. Repeat across several instances, with Redis unavailable, source timeout, malformed payload and missing record. Verify concurrency never exceeds the agreed budget; excess requests receive controlled outcomes.

Crash a test invalidation worker after source commit, restart it and prove repair from durable events. Test stale serving just before/after hard expiry. Measure probes, coalesced wait, rejected requests, repair lag and source QPS.

This page specifies an integration protocol and acceptance tests, not a supplied production middleware implementation. Missing implementation/evidence remains pending.

## References

- [Production usage](https://redis.io/docs/latest/develop/clients/redis-py/produsage/)
- [Distributed-lock limitations](https://redis.io/docs/latest/develop/clients/patterns/distributed-locks/)

**Next:** [30 — Sessions, Counters, Rate Limits, and Leaderboards](30-sessions-counters-rate-limits-and-leaderboards.md).
