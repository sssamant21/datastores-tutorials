# Chapter 24 --- Redis Distributed Locks, Leases & Coordination Patterns

**Status:** Canonical\
**Track:** Redis Enterprise / Redis Software Production Engineering\
**Part:** Part 2 --- Caching & Application Engineering\
**Level:** Intermediate → Production Distributed Coordination
Engineering\
**Audience:** Developers, SREs, DBREs, Platform Engineers, Redis
Administrators\
**Lab type:** Lock acquisition, unique ownership tokens, TTL-based
leases, ownership-safe release, lease renewal, stale-owner races,
fencing-token design, contention, bounded retry, backoff/jitter,
process-failure simulation, failover analysis, observability,
troubleshooting, runbooks, and production acceptance

------------------------------------------------------------------------

# 1. Objective

Distributed applications sometimes need to coordinate work so that only
one participant performs a particular operation at a time.

Examples:

``` text
one cache refresher
one scheduled job leader
one resource updater
one expensive source loader
one reconciliation worker per entity
```

Redis can provide useful coordination primitives, but a distributed lock
is not automatically a complete correctness guarantee.

By the end, you should be able to:

-   Explain distributed locking.
-   Acquire a lock atomically.
-   Use unique ownership tokens.
-   Use TTL-based leases.
-   Release locks safely.
-   Renew a lease only when still owned.
-   Understand stale-owner races.
-   Explain why lock expiration does not stop old work.
-   Understand fencing tokens.
-   Design bounded lock acquisition.
-   Use backoff and jitter.
-   Measure contention.
-   Handle process crashes.
-   Analyze Redis unavailability and failover assumptions.
-   Understand when not to use a Redis lock.
-   Protect downstream resources from stale owners.
-   Observe lock behavior.
-   Inject coordination failures.
-   Troubleshoot lock incidents.
-   Build production runbooks and acceptance criteria.

------------------------------------------------------------------------

# 2. Core Production Principle

A lock is a coordination mechanism.

It is not magic.

A production design must answer:

``` text
Who owns the lock?
How long is ownership valid?
How is ownership proven?
What happens when the owner pauses?
What happens when the lease expires?
Can the old owner keep working?
Can the downstream system reject stale owners?
What happens when Redis is unavailable?
What happens during failover?
```

If these questions are unanswered, the lock design is incomplete.

------------------------------------------------------------------------

# Part 1 --- Distributed Lock

## 3. Goal

A lock commonly tries to enforce:

``` text
at most one active owner
```

for some resource:

``` text
lock:customer:1001
lock:job:daily-report
lock:cache-loader:product:42
```

------------------------------------------------------------------------

# Part 2 --- Atomic Acquisition

## 4. SET NX

A basic lock acquisition uses:

``` redis
SET lock-key unique-token NX EX 30
```

Meaning:

``` text
SET value
only if key does not exist
expire after 30 seconds
```

The condition and TTL are applied as part of one Redis command.

------------------------------------------------------------------------

# Part 3 --- Why TTL Matters

## 5. Owner Crash

Without expiration:

``` text
owner acquires lock
owner crashes
lock remains forever
```

A TTL turns the lock into a lease.

------------------------------------------------------------------------

# Part 4 --- Lease

## 6. Definition

A lease grants ownership for a bounded period.

Example:

``` text
lease duration = 30 seconds
```

After that time, ownership cannot safely be assumed unless the lease was
validly renewed.

------------------------------------------------------------------------

# Part 5 --- Unique Ownership Token

## 7. Value

The lock value should identify the owner instance/acquisition uniquely.

Example:

``` text
6deed33c-...-unique-token
```

Do not use:

``` text
locked
```

for ownership-sensitive release.

------------------------------------------------------------------------

# Part 6 --- Unsafe Release

## 8. Plain DEL

Unsafe:

``` redis
DEL lock-key
```

A client can accidentally delete a lock that now belongs to someone
else.

------------------------------------------------------------------------

# Part 7 --- Expiry Race

## 9. Timeline

``` text
Client A acquires token-A
lease = 10s

Client A pauses for 15s

lock expires

Client B acquires token-B

Client A resumes

Client A DEL lock
```

Client A has now deleted Client B's valid lock.

------------------------------------------------------------------------

# Part 8 --- Ownership-Safe Release

## 10. Lua

``` lua
if redis.call("GET", KEYS[1]) == ARGV[1] then
    return redis.call("DEL", KEYS[1])
end

return 0
```

Only the current owner can release.

------------------------------------------------------------------------

# Part 9 --- Lock Release Contract

## 11. Return

Example:

``` text
1 -> lock released by owner
0 -> caller no longer owns lock
```

If release returns `0`, do not assume the lock is still yours.

------------------------------------------------------------------------

# Part 10 --- Lease TTL Sizing

## 12. Requirement

The lease must cover the expected critical-section duration with
operational margin.

Too short:

``` text
lease expires while valid work is still running
```

Too long:

``` text
crashed owner delays recovery
```

------------------------------------------------------------------------

# Part 11 --- Duration Distribution

## 13. Measure Work

Do not choose TTL from intuition alone.

Measure:

``` text
P50 duration
P95 duration
P99 duration
maximum expected duration
timeout behavior
pause behavior
```

------------------------------------------------------------------------

# Part 12 --- Static Lease

## 14. Appropriate Use

A fixed TTL can work when:

``` text
work duration is tightly bounded
maximum is known
operation is short
```

For long or variable work, renewal may be needed.

------------------------------------------------------------------------

# Part 13 --- Lease Renewal

## 15. Requirement

Renew only if:

``` text
current lock token == my token
```

Never extend a lock merely because the key exists.

------------------------------------------------------------------------

# Part 14 --- Ownership-Safe Renewal

## 16. Lua

``` lua
if redis.call("GET", KEYS[1]) == ARGV[1] then
    return redis.call("PEXPIRE", KEYS[1], ARGV[2])
end

return 0
```

Return:

``` text
1 -> renewed
0 -> ownership lost
```

------------------------------------------------------------------------

# Part 15 --- Renewal Timing

## 17. Do Not Renew at the Last Millisecond

If:

``` text
lease = 30s
```

renew substantially before expiration.

The exact renewal threshold depends on:

``` text
network latency
Redis latency
scheduler pauses
runtime GC
process load
failure detection
```

------------------------------------------------------------------------

# Part 16 --- Renewal Failure

## 18. Critical Rule

If renewal fails or ownership cannot be proven:

``` text
stop assuming ownership
```

The worker should leave the protected critical section as safely as the
application permits.

------------------------------------------------------------------------

# Part 17 --- Stale Owner

## 19. Definition

A stale owner is a worker that once owned a lock but no longer does, yet
continues operating.

Example:

``` text
A owns lease
A pauses
lease expires
B owns new lease
A resumes and continues work
```

Safe release alone does not stop A from continuing its external
operation.

------------------------------------------------------------------------

# Part 18 --- The Fundamental Lease Problem

## 20. Lock Expiry Does Not Kill Work

Redis can expire:

``` text
lock key
```

Redis cannot automatically terminate:

``` text
old process
database query
file write
external API operation
job
```

This distinction is essential.

------------------------------------------------------------------------

# Part 19 --- Fencing Tokens

## 21. Concept

A fencing token is a monotonically increasing ownership number.

Example:

``` text
owner A -> token 41
owner B -> token 42
owner C -> token 43
```

A downstream system can reject operations with a token older than the
newest accepted token.

------------------------------------------------------------------------

# Part 20 --- Why Fencing Helps

## 22. Stale Owner Example

``` text
A gets fencing token 41
A pauses

lease expires

B gets fencing token 42
B updates downstream resource with 42

A resumes
A sends update with 41
```

If downstream remembers:

``` text
latest token = 42
```

it rejects:

``` text
41
```

This protects the resource from stale owners.

------------------------------------------------------------------------

# Part 21 --- Fencing Requirement

## 23. Downstream Enforcement

A fencing token is useful only when the protected resource can validate
ordering.

If the downstream system blindly accepts all writes, simply generating a
number in Redis does not solve the stale-owner problem.

------------------------------------------------------------------------

# Part 22 --- Fencing Counter

## 24. Concept

A monotonically increasing Redis counter can generate sequence values:

``` redis
INCR tutorial:chapter24:fence-sequence
```

The lock acquisition protocol must associate the resulting sequence with
the granted lease.

Production design must validate atomicity requirements and failure
semantics.

------------------------------------------------------------------------

# Part 23 --- Lock + Fence Acquisition

## 25. Atomicity

A robust protocol may need:

``` text
check lock availability
create lease
allocate fencing number
return ownership data
```

as one bounded atomic operation.

Lua/server-side logic can implement such a protocol when all required
state is correctly colocated.

------------------------------------------------------------------------

# Part 24 --- Example Lock State

## 26. Representation

Conceptually:

``` text
lock key   -> unique owner token
fence      -> monotonic sequence
```

The application receives:

``` text
owner token
fencing token
lease duration
```

------------------------------------------------------------------------

# Part 25 --- Lock Contention

## 27. Many Waiters

When many clients want the same lock:

``` text
one succeeds
many fail
```

If all failed clients retry immediately:

``` text
retry storm
```

can result.

------------------------------------------------------------------------

# Part 26 --- Backoff

## 28. Bounded Retry

Use:

``` text
maximum attempts
deadline
backoff
jitter
```

Do not spin continuously against Redis.

------------------------------------------------------------------------

# Part 27 --- Jitter

## 29. Spread Waiters

Instead of every client retrying at:

``` text
100 ms
```

add random variation.

This reduces synchronized retries.

------------------------------------------------------------------------

# Part 28 --- Fairness

## 30. No Automatic Fair Queue

A simple `SET NX` lock does not inherently provide strict FIFO fairness.

A client that retries at a favorable moment may acquire before another
waiter.

If fairness is a business requirement, design it explicitly.

------------------------------------------------------------------------

# Part 29 --- Lock Starvation

## 31. Risk

A client may repeatedly lose acquisition races.

Measure:

``` text
wait time
attempt count
acquisition failure rate
```

Do not assume eventual fairness.

------------------------------------------------------------------------

# Part 30 --- Critical Section

## 32. Keep It Small

Do not hold a lock around unrelated work.

Bad:

``` text
acquire lock
call multiple remote services
sleep
perform logging/reporting
do unrelated computation
release
```

Minimize protected work.

------------------------------------------------------------------------

# Part 31 --- Lock Granularity

## 33. Global vs. Per-Resource

Global:

``` text
lock:all-orders
```

can serialize unrelated work.

Per-resource:

``` text
lock:order:1001
lock:order:1002
```

can allow concurrency where business semantics permit.

------------------------------------------------------------------------

# Part 32 --- Hot Lock

## 34. Contention Hotspot

A single heavily contended lock becomes a hot key.

Symptoms:

``` text
high acquisition attempts
high failed SET NX
high retry traffic
latency
```

Review the coordination model rather than simply scaling Redis.

------------------------------------------------------------------------

# Part 33 --- Single-Flight Loader Lock

## 35. Cache Use Case

Chapter 15 uses lock-like coordination to ensure:

``` text
one source loader per cache key
```

This is different from using a lock as a strict correctness boundary for
irreversible external operations.

Risk level matters.

------------------------------------------------------------------------

# Part 34 --- Leader Election

## 36. Caution

A TTL lock can be used for simple lease-based leadership patterns, but
leadership requires careful treatment of:

``` text
lease loss
stale leader
renewal
failover
fencing
downstream behavior
```

Do not equate "I hold a Redis key" with universally safe leadership.

------------------------------------------------------------------------

# Part 35 --- Redis Unavailable

## 37. Acquisition Failure

If Redis is unavailable:

``` text
cannot prove lock acquisition
```

The safe behavior depends on the workload.

For correctness-sensitive operations, often:

``` text
do not proceed without ownership proof
```

For best-effort cache refresh, fallback behavior may differ.

------------------------------------------------------------------------

# Part 36 --- Existing Owner During Redis Failure

## 38. Uncertainty

If an owner cannot renew because Redis is unreachable, it cannot safely
assume its lease remains valid indefinitely.

Design a clear lease-loss policy.

------------------------------------------------------------------------

# Part 37 --- Process Crash

## 39. Recovery

With TTL:

``` text
process dies
lease eventually expires
another worker can acquire
```

Recovery delay is related to remaining lease duration.

------------------------------------------------------------------------

# Part 38 --- Long Runtime Pause

## 40. GC / Scheduling / Host Pause

A process can remain alive but stop running long enough for its lease to
expire.

When it resumes, it may be stale.

This is why process liveness is not equivalent to lease ownership.

------------------------------------------------------------------------

# Part 39 --- Network Partition

## 41. Client Perspective

A client may lose connectivity to Redis while still being able to reach
the downstream resource.

Without fencing or another downstream correctness mechanism, stale work
may continue.

------------------------------------------------------------------------

# Part 40 --- Failover Considerations

## 42. Validate Architecture

Lock correctness assumptions depend on the Redis deployment,
replication, failover behavior, durability requirements, and timing.

Do not assume that every Redis topology provides the same coordination
guarantees.

Validate against the exact Redis Enterprise deployment and vendor
guidance.

------------------------------------------------------------------------

# Part 41 --- Safety vs. Availability

## 43. Tradeoff

During uncertainty, a system may choose:

``` text
stop work to preserve exclusivity
```

or:

``` text
continue work to preserve availability
```

The correct choice depends on the business consequence of
duplicate/stale execution.

Document it explicitly.

------------------------------------------------------------------------

# Part 42 --- When Not to Use a Redis Lock

## 44. Avoid Locks When

A simpler primitive solves the problem:

``` text
database unique constraint
atomic Redis command
idempotency key
queue partitioning
optimistic version check
transaction in authoritative datastore
```

Use the system that owns the correctness invariant whenever practical.

------------------------------------------------------------------------

# Part 43 --- Database Constraint Example

## 45. Stronger Ownership Boundary

If PostgreSQL owns an entity and must enforce:

``` text
only one active record
```

a database constraint may be safer than relying on an external Redis
lock to protect that invariant.

------------------------------------------------------------------------

# Part 44 --- Idempotency Instead of Locking

## 46. Duplicate Work

Sometimes it is easier and safer to allow duplicate attempts but make
the operation idempotent.

Example:

``` text
request ID
+
authoritative uniqueness check
```

This can avoid distributed lock complexity.

------------------------------------------------------------------------

# Part 45 --- Queue Partitioning

## 47. Natural Serialization

If work can be routed by entity:

``` text
entity 1001 -> partition X
```

a queue/stream architecture may serialize updates naturally.

A separate lock may not be necessary.

------------------------------------------------------------------------

# Part 46 --- Observability

## 48. Acquisition Metrics

Track:

``` text
redis_lock_acquire_total
redis_lock_acquire_success_total
redis_lock_acquire_failure_total
redis_lock_wait_seconds
redis_lock_attempts
```

------------------------------------------------------------------------

## 49. Lease Metrics

Track:

``` text
redis_lock_renew_total
redis_lock_renew_success_total
redis_lock_renew_failure_total
redis_lock_lost_total
redis_lock_hold_seconds
```

------------------------------------------------------------------------

## 50. Release Metrics

Track:

``` text
redis_lock_release_total
redis_lock_release_success_total
redis_lock_release_not_owner_total
```

------------------------------------------------------------------------

## 51. Fencing Metrics

Where used:

``` text
fencing_token_issued_total
stale_fencing_token_rejected_total
```

Avoid using individual lock keys as unbounded metric labels.

------------------------------------------------------------------------

# Part 47 --- Alerting

## 52. Useful Conditions

Alert on sustained:

``` text
renewal failures
lock-loss rate
extreme wait time
retry exhaustion
stale fencing rejection
Redis latency affecting leases
```

Do not alert on every normal lock contention event.

------------------------------------------------------------------------

# Part 48 --- Hands-On Lab

## 53. Objectives

You will:

1.  acquire a lock with `SET NX`;
2.  generate unique tokens;
3.  use a TTL lease;
4.  release safely;
5.  reproduce old-owner release race;
6.  renew safely;
7.  simulate renewal loss;
8.  add bounded retries;
9.  add backoff/jitter;
10. implement fencing-token acquisition;
11. reject stale downstream work;
12. inject failures;
13. clean up safely.

------------------------------------------------------------------------

## 54. Prerequisites

``` bash
python -m pip install redis
```

Windows CMD:

``` cmd
set REDIS_HOST=localhost
set REDIS_PORT=6379
set REDIS_PASSWORD=
```

PowerShell:

``` powershell
$env:REDIS_HOST="localhost"
$env:REDIS_PORT="6379"
$env:REDIS_PASSWORD=""
```

Linux/macOS:

``` bash
export REDIS_HOST=localhost
export REDIS_PORT=6379
export REDIS_PASSWORD=''
```

------------------------------------------------------------------------

# Part 49 --- Python Lock Lab

## 55. Create `chapter24_lock_lab.py`

``` python
import os
import random
import time
import uuid

import redis

HOST = os.getenv("REDIS_HOST", "localhost")
PORT = int(os.getenv("REDIS_PORT", "6379"))
PASSWORD = os.getenv("REDIS_PASSWORD") or None

r = redis.Redis(
    host=HOST,
    port=PORT,
    password=PASSWORD,
    decode_responses=True,
)

LOCK_KEY = "tutorial:chapter24:lock:resource-1001"
FENCE_KEY = "tutorial:chapter24:fence-sequence"

RELEASE_SCRIPT = """
if redis.call("GET", KEYS[1]) == ARGV[1] then
    return redis.call("DEL", KEYS[1])
end

return 0
"""

RENEW_SCRIPT = """
if redis.call("GET", KEYS[1]) == ARGV[1] then
    return redis.call("PEXPIRE", KEYS[1], ARGV[2])
end

return 0
"""


def acquire_lock(ttl_ms=10000):
    token = str(uuid.uuid4())

    acquired = r.set(
        LOCK_KEY,
        token,
        nx=True,
        px=ttl_ms,
    )

    if not acquired:
        return None

    return token


def release_lock(token):
    return r.eval(
        RELEASE_SCRIPT,
        1,
        LOCK_KEY,
        token,
    )


def renew_lock(token, ttl_ms=10000):
    return r.eval(
        RENEW_SCRIPT,
        1,
        LOCK_KEY,
        token,
        ttl_ms,
    )


def acquire_with_retry(
    ttl_ms=10000,
    max_attempts=5,
):
    for attempt in range(1, max_attempts + 1):
        token = acquire_lock(ttl_ms)

        if token:
            return {
                "token": token,
                "attempt": attempt,
            }

        if attempt == max_attempts:
            break

        base = min(
            0.05 * (2 ** (attempt - 1)),
            1.0,
        )

        delay = random.uniform(
            base / 2,
            base,
        )

        time.sleep(delay)

    return None


if __name__ == "__main__":
    print("PING:", r.ping())

    token = acquire_lock()

    print(
        "Acquired:",
        bool(token),
    )

    if token:
        print(
            "Token:",
            token,
        )

        print(
            "Renew:",
            renew_lock(token),
        )

        print(
            "Wrong-owner release:",
            release_lock("wrong-token"),
        )

        print(
            "Owner release:",
            release_lock(token),
        )
```

------------------------------------------------------------------------

# Part 50 --- Run Lab

## 56. Execute

``` bash
python chapter24_lock_lab.py
```

Expected pattern:

``` text
PING: True
Acquired: True
Token: ...
Renew: 1
Wrong-owner release: 0
Owner release: 1
```

------------------------------------------------------------------------

# Part 51 --- Contention Lab

## 57. Two Clients

Run two processes simultaneously.

Only one should successfully acquire the same lock at a time.

The other should:

``` text
fail acquisition
or
wait using bounded retry
```

depending on the test.

------------------------------------------------------------------------

# Part 52 --- Expiry Race Lab

## 58. Reproduce

Client A:

``` text
acquire 2-second lease
sleep 3 seconds
```

Client B after expiry:

``` text
acquire same lock
```

Then Client A attempts:

``` text
release with token-A
```

Expected:

``` text
release = 0
Client B's token remains
```

------------------------------------------------------------------------

# Part 53 --- Renewal Lab

## 59. Renew Before Expiry

Acquire:

``` text
TTL = 5 seconds
```

Renew at:

``` text
~2 seconds
```

Verify:

``` redis
PTTL tutorial:chapter24:lock:resource-1001
```

The TTL should extend if ownership is still valid.

------------------------------------------------------------------------

# Part 54 --- Renewal Loss Lab

## 60. Old Token

Allow lock A to expire.

Acquire as B.

Attempt renewal using token A.

Expected:

``` text
0
```

The stale owner must not regain ownership by renewal.

------------------------------------------------------------------------

# Part 55 --- Fencing Lab

## 61. Simplified Acquisition Script

For a disposable lab, use one script to acquire a lease and allocate a
fencing sequence.

``` lua
if redis.call("EXISTS", KEYS[1]) == 1 then
    return nil
end

local fence = redis.call("INCR", KEYS[2])

redis.call(
    "PSETEX",
    KEYS[1],
    ARGV[2],
    ARGV[1]
)

return fence
```

Arguments:

``` text
KEYS[1] = lock key
KEYS[2] = fencing counter
ARGV[1] = unique owner token
ARGV[2] = lease TTL ms
```

In clustered deployments, both keys must satisfy valid key-placement
requirements for the atomic script.

------------------------------------------------------------------------

# Part 56 --- Fencing Key Placement

## 62. Hash Tag Example

For a resource-specific fencing sequence:

``` text
tutorial:chapter24:{resource-1001}:lock
tutorial:chapter24:{resource-1001}:fence
```

This can place the related keys in the same Redis Cluster slot.

Do not blindly create one global hash tag for all resources.

------------------------------------------------------------------------

# Part 57 --- Simulated Downstream Fence

## 63. Model

A downstream resource tracks:

``` text
last_fencing_token
```

Operation:

``` python
def downstream_write(
    fencing_token,
    value,
):
    global last_fencing_token

    if fencing_token < last_fencing_token:
        return False

    last_fencing_token = fencing_token

    # Apply value.
    return True
```

Production enforcement must happen in the actual authoritative
downstream system.

------------------------------------------------------------------------

# Part 58 --- Stale Owner Fence Test

## 64. Scenario

``` text
A gets fence 10
A pauses

B gets fence 11
B writes -> accepted

A resumes
A writes with fence 10 -> rejected
```

This demonstrates why fencing protects beyond lock-key ownership.

------------------------------------------------------------------------

# Part 59 --- Failure Injection

## 65. Failure 1 --- Owner Crash

Acquire lock, then terminate owner without release.

Expected:

``` text
lease expires
new owner eventually acquires
```

Measure recovery delay.

------------------------------------------------------------------------

## 66. Failure 2 --- Lease Too Short

Set lease shorter than normal work duration.

Expected:

``` text
ownership expires during work
second owner may acquire
```

This is a correctness warning.

------------------------------------------------------------------------

## 67. Failure 3 --- Lease Too Long

Use an excessively long lease and terminate owner.

Observe slow recovery.

------------------------------------------------------------------------

## 68. Failure 4 --- Old Owner Release

Allow A to expire, B to acquire, then A releases.

Expected:

``` text
safe release returns 0
B remains owner
```

------------------------------------------------------------------------

## 69. Failure 5 --- Old Owner Renewal

Allow A to expire, B to acquire, then A renews.

Expected:

``` text
safe renewal returns 0
```

------------------------------------------------------------------------

## 70. Failure 6 --- Retry Storm

Run many contenders with immediate retry.

Observe:

``` text
Redis request rate
failed acquisition rate
latency
```

Then add exponential backoff and jitter.

------------------------------------------------------------------------

## 71. Failure 7 --- Long Process Pause

Pause owner longer than lease.

Resume it.

Without fencing, demonstrate that the old process can still attempt
downstream work.

------------------------------------------------------------------------

## 72. Failure 8 --- Redis Unavailable During Renewal

In a disposable environment, interrupt Redis connectivity before
renewal.

Expected application behavior:

``` text
ownership becomes uncertain
worker follows lease-loss policy
```

------------------------------------------------------------------------

## 73. Failure 9 --- Hot Lock

Run many workers against one resource lock.

Measure:

``` text
wait time
attempts
success rate
retry exhaustion
Redis load
```

------------------------------------------------------------------------

## 74. Failure 10 --- Stale Fencing Token

Have newer owner write with fence N+1.

Then stale owner writes with N.

Expected:

``` text
downstream rejects stale token
```

------------------------------------------------------------------------

# Part 60 --- Troubleshooting

## 75. Two Workers Performing Same Job

Check:

``` text
lease duration
renewal
process pause
stale owner
lock-key identity
multiple Redis endpoints
failover assumptions
fencing
```

------------------------------------------------------------------------

## 76. Lock Disappears During Work

Check:

``` text
TTL
work duration
renewal interval
renewal errors
Redis latency
scheduler/GC pauses
```

------------------------------------------------------------------------

## 77. Lock Cannot Be Acquired

Check:

``` text
current token
PTTL
owner health
lease duration
contention
retry policy
```

Do not delete an unknown owner's lock manually without understanding the
consequences.

------------------------------------------------------------------------

## 78. Wrong Owner Lock Deletion

Check whether release is:

``` text
unconditional DEL
```

Replace with ownership-safe compare-and-delete.

------------------------------------------------------------------------

## 79. Renewal Reports Not Owner

The lease may have:

``` text
expired
been replaced
been intentionally released
```

The caller must stop assuming ownership.

------------------------------------------------------------------------

## 80. High Lock Wait Time

Check:

``` text
critical-section duration
lock granularity
hot resource
retry schedule
worker count
```

Reduce unnecessary serialization.

------------------------------------------------------------------------

## 81. High Redis Load From Locks

Check:

``` text
busy retry loops
very short polling interval
hot locks
excessive renewal frequency
```

Use bounded retry/backoff and appropriate lease duration.

------------------------------------------------------------------------

## 82. Stale Work Reaches Downstream

Safe release alone is insufficient.

Review:

``` text
lease expiry behavior
worker cancellation
fencing
downstream version checks
idempotency
```

------------------------------------------------------------------------

# Part 61 --- Production Runbooks

## 83. Runbook --- Duplicate Worker Execution

``` text
1. Identify resource/job.
2. Identify all workers.
3. Inspect current lock token.
4. Inspect TTL.
5. Check acquisition timestamps.
6. Check renewal logs.
7. Check process pauses.
8. Determine whether old owner continued after lease loss.
9. Validate fencing/idempotency.
10. Correct protocol and retest.
```

------------------------------------------------------------------------

## 84. Runbook --- Stuck Lock

``` text
1. Read lock key safely.
2. Check PTTL.
3. Identify owner if metadata exists.
4. Confirm owner health.
5. Confirm lease should expire.
6. Avoid arbitrary DEL.
7. Follow approved recovery procedure.
8. Validate next acquisition.
9. Check excessively long TTL.
10. Add prevention/alerting.
```

------------------------------------------------------------------------

## 85. Runbook --- Renewal Failure

``` text
1. Capture renewal result/error.
2. Check current lock token.
3. Check PTTL.
4. Check Redis connectivity.
5. Check Redis latency.
6. Determine whether ownership is lost.
7. Stop protected work if policy requires.
8. Prevent stale downstream writes.
9. Recover/reacquire only through normal protocol.
10. Validate lease-loss handling.
```

------------------------------------------------------------------------

## 86. Runbook --- Lock Contention Storm

``` text
1. Measure attempts/sec.
2. Measure success rate.
3. Measure wait time.
4. Identify hot lock.
5. Check critical-section duration.
6. Apply bounded retry.
7. Add exponential backoff/jitter.
8. Reduce worker concurrency if needed.
9. Revisit lock granularity/data model.
10. Confirm Redis load stabilizes.
```

------------------------------------------------------------------------

## 87. Runbook --- Stale Owner Incident

``` text
1. Identify old and new owner.
2. Confirm lease transition.
3. Identify stale operation.
4. Stop stale worker if possible.
5. Check fencing token.
6. Check downstream rejection behavior.
7. Reconcile authoritative state.
8. Add/repair fencing or version checks.
9. Reproduce pause/expiry scenario.
10. Close only after stale writes are rejected.
```

------------------------------------------------------------------------

# Part 62 --- Lock Design Template

## 88. Fields

``` text
Service:
Resource:
Correctness requirement:
Why a lock is needed:
Why authoritative-system constraint is insufficient:
Lock key:
Lock granularity:
Owner token format:
Lease TTL:
P50 work duration:
P95 work duration:
P99 work duration:
Renewal required?:
Renewal interval:
Max acquisition attempts:
Acquisition deadline:
Backoff:
Jitter:
Lease-loss behavior:
Release script:
Renewal script:
Fencing required?:
Fencing storage:
Downstream enforcement:
Redis topology:
Failover assumptions:
Idempotency:
Metrics:
Owner:
```

------------------------------------------------------------------------

# Part 63 --- Lease Sizing Worksheet

## 89. Record

``` text
Operation:
P50 duration:
P95 duration:
P99 duration:
Known max:
Network P99:
Redis latency P99:
Runtime pause allowance:
Safety margin:
Selected lease:
Renewal threshold:
Maximum renewal failures:
```

Do not derive lease duration from one average measurement.

------------------------------------------------------------------------

# Part 64 --- Lock Decision Checklist

## 90. Before Using Redis Lock

Ask:

``` text
Can one atomic Redis command solve it?
Can the authoritative database enforce it?
Can a unique constraint solve it?
Can optimistic concurrency solve it?
Can idempotency solve it?
Can queue partitioning serialize it?
Can duplicate work be tolerated?
Does stale work cause harm?
Can downstream enforce fencing?
```

Only then choose the coordination mechanism.

------------------------------------------------------------------------

# Production Acceptance Checklist

## 91. Distributed Coordination

-   [ ] Lock requirement documented.
-   [ ] Simpler alternatives reviewed.
-   [ ] Lock key/granularity documented.
-   [ ] Acquisition uses atomic conditional set.
-   [ ] Unique ownership token used.
-   [ ] Lease TTL defined from measurements.
-   [ ] Ownership-safe release implemented.
-   [ ] Wrong-owner release tested.
-   [ ] Renewal is ownership-safe.
-   [ ] Renewal timing documented.
-   [ ] Renewal failure behavior documented.
-   [ ] Lease-too-short scenario tested.
-   [ ] Lease-too-long recovery tested.
-   [ ] Process-crash recovery tested.
-   [ ] Long-pause stale-owner scenario tested.
-   [ ] Retry attempts bounded.
-   [ ] Backoff implemented.
-   [ ] Jitter implemented.
-   [ ] Contention tested.
-   [ ] Hot-lock behavior tested.
-   [ ] Redis-unavailable behavior tested.
-   [ ] Failover assumptions reviewed.
-   [ ] Fencing evaluated for correctness-sensitive work.
-   [ ] Downstream fencing enforcement tested where required.
-   [ ] External operation idempotency reviewed.
-   [ ] Production runbooks validated.

------------------------------------------------------------------------

# Knowledge Validation

## 92. Questions

You should be able to answer:

1.  What problem does a distributed lock solve?
2.  Why use `SET NX` for acquisition?
3.  Why must a lock have a TTL?
4.  What is a lease?
5.  Why use a unique ownership token?
6.  Why is unconditional `DEL` unsafe?
7.  What is ownership-safe release?
8.  How should lease TTL be selected?
9.  What happens when a lease is too short?
10. What happens when a lease is too long?
11. Why must renewal verify ownership?
12. Why should renewal happen before the last moment?
13. What should a worker do when ownership cannot be proven?
14. What is a stale owner?
15. Why does lock expiration not stop old work?
16. What is a fencing token?
17. How does fencing protect against stale owners?
18. Why must the downstream system enforce fencing?
19. Why can lock contention cause a retry storm?
20. Why use backoff and jitter?
21. Does a basic lock guarantee fairness?
22. Why keep the critical section small?
23. What is a hot lock?
24. Why is cache-loader coordination different from strict external
    correctness?
25. What should happen when Redis is unavailable?
26. Why do failover assumptions matter?
27. What is the safety-vs.-availability tradeoff?
28. When should an authoritative database constraint be preferred?
29. When can idempotency replace locking?
30. What must pass before a Redis lock is production-ready?

------------------------------------------------------------------------

# Hands-On Acceptance Checklist

## 93. Lab Completion

-   [ ] Acquired lock with `SET NX`.
-   [ ] Used unique ownership token.
-   [ ] Used TTL-based lease.
-   [ ] Implemented safe release.
-   [ ] Tested wrong-owner release.
-   [ ] Reproduced expiry/new-owner race.
-   [ ] Verified old owner cannot release new owner's lock.
-   [ ] Implemented safe renewal.
-   [ ] Tested old-owner renewal rejection.
-   [ ] Added bounded acquisition retry.
-   [ ] Added exponential backoff.
-   [ ] Added jitter.
-   [ ] Reviewed lease sizing.
-   [ ] Implemented simplified fencing acquisition.
-   [ ] Reviewed cluster key placement.
-   [ ] Simulated downstream fencing.
-   [ ] Rejected stale fencing token.
-   [ ] Completed ten failure scenarios.
-   [ ] Completed troubleshooting.
-   [ ] Reviewed five production runbooks.
-   [ ] Completed lock design template.
-   [ ] Completed lease sizing worksheet.
-   [ ] Completed lock decision checklist.
-   [ ] Completed production acceptance checklist.

------------------------------------------------------------------------

# 94. Lab Cleanup

Discover:

``` bash
redis-cli --scan --pattern 'tutorial:chapter24:*'
```

Delete only confirmed Chapter 24 training keys in bounded batches with
`UNLINK`.

Examples:

``` redis
UNLINK tutorial:chapter24:lock:resource-1001
UNLINK tutorial:chapter24:fence-sequence
UNLINK tutorial:chapter24:{resource-1001}:lock
UNLINK tutorial:chapter24:{resource-1001}:fence
```

Do not use:

``` redis
FLUSHDB
FLUSHALL
```

against a shared or production database.

Do not manually delete an active production lock simply because it
appears old. Follow the ownership/recovery runbook.

------------------------------------------------------------------------

# 95. Key Takeaways

1.  Redis locks are coordination mechanisms, not universal correctness
    guarantees.
2.  Acquire a basic lease atomically with a conditional `SET` and TTL.
3.  Every ownership-sensitive lock should use a unique token.
4.  Unconditional lock deletion is unsafe.
5.  Release must compare ownership and delete atomically.
6.  Lease duration must be based on measured work duration and failure
    margins.
7.  Short leases risk concurrent owners; long leases delay crash
    recovery.
8.  Renewal must verify current ownership.
9.  A worker that cannot prove ownership should stop assuming it owns
    the resource.
10. Lock expiration does not terminate the old worker.
11. A stale owner can continue external work after losing its lease.
12. Fencing tokens allow a capable downstream resource to reject stale
    owners.
13. Fencing works only when the downstream system enforces token
    ordering.
14. Contended locks require bounded retries, backoff, and jitter.
15. Basic `SET NX` locking does not guarantee strict fairness.
16. Critical sections and lock scope should remain small.
17. Hot locks are workload-design problems, not merely Redis capacity
    problems.
18. Redis outages, process pauses, partitions, and failovers must be
    part of the design.
19. Database constraints, optimistic concurrency, idempotency, or queue
    partitioning may be safer than a distributed lock.
20. Production readiness requires ownership-safe operations, lease-loss
    handling, stale-owner protection, failure testing, observability,
    and runbooks.

------------------------------------------------------------------------

# 96. References

Validate exact behavior and architecture against the Redis, Redis
Enterprise, and client-library versions deployed.

Recommended official Redis documentation areas:

-   `SET`
-   `GET`
-   `DEL`
-   `UNLINK`
-   `EXPIRE`
-   `PEXPIRE`
-   `PTTL`
-   `INCR`
-   Redis programmability / Lua
-   Redis distributed-locking guidance
-   Redis Cluster
-   Redis Cluster hash tags
-   Redis latency monitoring
-   Redis Enterprise high availability and failover documentation
-   Redis Enterprise monitoring
-   redis-py locking/scripting behavior

Distributed coordination is a correctness-sensitive design area. A Redis
lease can be appropriate for many workloads, but its guarantees depend
on ownership protocol, lease timing, topology, client behavior, failure
modes, and---when stale work is dangerous---downstream fencing or
equivalent authoritative protection.

------------------------------------------------------------------------

# Next Chapter

**Chapter 25 --- Redis Rate Limiting, Quotas & Traffic Protection**

Chapter 25 will cover:

-   fixed-window limiting
-   sliding-window concepts
-   token bucket
-   leaky-bucket concepts
-   atomic counters
-   TTL handling
-   Lua-based bounded decisions
-   per-user/per-tenant limits
-   burst control
-   distributed clients
-   hot-key risk
-   fail-open vs. fail-closed behavior
-   observability
-   failure injection
-   troubleshooting
-   production runbooks
-   acceptance validation
