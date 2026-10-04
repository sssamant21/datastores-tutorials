# 30 — Sessions, Counters, Rate Limits, and Leaderboards

**Status:** Draft; live lab not run.

**Objective:** Apply Redis beyond response caching with explicit durability requirements.

| Use | Type/pattern | Concern |
|---|---|---|
| Sessions | Expiring string/hash | Idle versus absolute expiry; revocation; sensitive data |
| Counters | Atomic INCR | Replay duplicates and expiry races |
| Rate limit | Bounded atomic counter/window protocol | Boundary bursts; fail-open/closed policy |
| Leaderboard | Sorted set | Tie/ranking policy and retained size |
| Lock | Unique token, lease, checked release | Expired worker; fencing and failover semantics |

Session IDs should be opaque random values; store only approved data, scope access and define source/recovery policy. Eviction can log users out. Do not treat every dataset as a disposable cache.

## Bounded lab

Use synthetic values:
```redis
SET tutorial:session:opaque-demo '{"user":"synthetic","role":"viewer"}' EX 300
GET tutorial:session:opaque-demo
INCR tutorial:counter:demo
EXPIRE tutorial:counter:demo 300
ZADD tutorial:leaderboard:demo 10 playerA 20 playerB
EXPIRE tutorial:leaderboard:demo 300
ZRANGE tutorial:leaderboard:demo 0 1 REV WITHSCORES
```
Expect playerB before playerA. The separate INCR/EXPIRE commands are a demonstration, not a safe production limiter: a crash between them can leave an immortal key. Use a verified bounded script to increment/set initial expiry atomically in supported scope, or a suitable tested limiter algorithm. Never reset expiry on every increment unless sliding retention is intended.

## Acceptance

Test session expiry/revocation, counter replay policy, boundary bursts and overload response. Verify rank ties and bounded result sets. For critical limits, define fail-closed/controlled behavior during Redis errors. For locks use Tutorial 27; prove downstream stale-worker protection where required.

Cleanup exact keys:
```redis
DEL tutorial:session:opaque-demo tutorial:counter:demo tutorial:leaderboard:demo
```

## References

- [INCR patterns](https://redis.io/docs/latest/commands/incr/)
- [Sorted sets](https://redis.io/docs/latest/develop/data-types/sorted-sets/)
- [Locks](https://redis.io/docs/latest/develop/clients/patterns/distributed-locks/)

**Next:** [31 — Streams and Messaging Recovery](31-streams-and-messaging-recovery.md).
