# Chapter 23 --- Redis Lua Scripting & Server-Side Atomic Logic

**Status:** Canonical\
**Track:** Redis Enterprise / Redis Software Production Engineering\
**Part:** Part 2 --- Caching & Application Engineering\
**Level:** Intermediate → Production Redis Atomic Logic Engineering\
**Audience:** Developers, SREs, DBREs, Platform Engineers, Redis
Administrators\
**Lab type:** EVAL, EVALSHA, KEYS/ARGV, atomic compare-and-set,
conditional updates, ownership-safe lock release, script caching,
NOSCRIPT recovery, bounded execution, blocking-risk analysis, cluster
key placement, failure injection, observability, troubleshooting,
runbooks, and production acceptance

------------------------------------------------------------------------

# 1. Objective

Some Redis operations require several logical steps to happen
atomically.

Example:

``` text
read value
compare value
conditionally update value
```

Doing this entirely from the client creates a race window:

``` text
GET
network
application logic
network
SET
```

Lua scripting allows bounded logic to execute on the Redis server as one
atomic script execution.

By the end, you should be able to:

-   Explain Redis Lua scripting.
-   Use `EVAL`.
-   Use `EVALSHA`.
-   Pass keys through `KEYS`.
-   Pass values through `ARGV`.
-   Implement atomic compare-and-set.
-   Implement conditional delete.
-   Release locks safely using ownership tokens.
-   Understand script caching.
-   Recover from `NOSCRIPT`.
-   Keep scripts small and bounded.
-   Understand blocking risk.
-   Avoid unbounded scans/loops.
-   Understand cluster key-placement constraints.
-   Compare Lua with transactions and built-in commands.
-   Observe script latency and failures.
-   Inject script failure scenarios.
-   Troubleshoot production scripting incidents.
-   Build production runbooks and acceptance criteria.

------------------------------------------------------------------------

# 2. Core Production Principle

Lua should solve a small atomicity problem, not become an application
server inside Redis.

Good script:

``` text
read a few known keys
validate
perform a small update
return
```

Dangerous script:

``` text
scan huge dataset
loop over thousands/millions of elements
perform expensive transformations
block Redis for a long time
```

Keep scripts:

``` text
small
bounded
predictable
measurable
```

------------------------------------------------------------------------

# Part 1 --- Why Server-Side Logic

## 3. Client-Side Race

Unsafe:

``` text
Client A GET -> owner-A

Client B changes key -> owner-B

Client A DEL
```

Client A may delete Client B's state.

The compare and delete must be atomic.

------------------------------------------------------------------------

# Part 2 --- Lua Atomicity

## 4. Script Execution

A Redis Lua script executes atomically relative to other Redis commands.

Other clients do not interleave commands inside the script's execution.

This is powerful, but it also means a slow script can delay other work.

------------------------------------------------------------------------

# Part 3 --- EVAL

## 5. Basic Syntax

``` redis
EVAL "return 1" 0
```

The number after the script is the number of keys passed through `KEYS`.

------------------------------------------------------------------------

# Part 4 --- KEYS

## 6. Key Arguments

Example:

``` redis
EVAL "return redis.call('GET', KEYS[1])" 1 tutorial:chapter23:item
```

Inside the script:

``` lua
KEYS[1]
```

contains:

``` text
tutorial:chapter23:item
```

------------------------------------------------------------------------

# Part 5 --- ARGV

## 7. Non-Key Arguments

Example:

``` redis
EVAL "return ARGV[1]" 0 hello
```

Use `ARGV` for:

``` text
expected values
new values
tokens
TTL values
limits
```

Do not hide key names inside `ARGV` when Redis needs key declarations
for routing/cluster semantics.

------------------------------------------------------------------------

# Part 6 --- Basic SET Script

## 8. Example

``` redis
EVAL "redis.call('SET', KEYS[1], ARGV[1]); return 1" 1 tutorial:chapter23:item value
```

This example is intentionally simple.

A normal `SET` command is already atomic, so Lua is unnecessary for this
exact operation.

------------------------------------------------------------------------

# Part 7 --- Prefer Built-In Commands

## 9. Do Not Script What Redis Already Solves

Instead of Lua for:

``` text
increment
```

prefer:

``` redis
INCR key
```

Instead of scripting a simple conditional set, check whether `SET`
options already provide the required semantics.

Use Lua only when the atomic logic actually needs multiple operations or
conditions.

------------------------------------------------------------------------

# Part 8 --- Compare-and-Set

## 10. Requirement

Update only when:

``` text
current value == expected value
```

Concept:

``` text
GET
compare
SET
```

must be atomic.

------------------------------------------------------------------------

# Part 9 --- CAS Script

## 11. Lua

``` lua
local current = redis.call("GET", KEYS[1])

if current ~= ARGV[1] then
    return 0
end

redis.call("SET", KEYS[1], ARGV[2])

return 1
```

Return:

``` text
1 -> updated
0 -> expected value did not match
```

------------------------------------------------------------------------

# Part 10 --- Conditional Delete

## 12. Requirement

Delete a key only if the caller still owns it.

Concept:

``` text
if current token == my token
    delete
```

This is essential for ownership-safe lock release.

------------------------------------------------------------------------

# Part 11 --- Safe Lock Release

## 13. Script

``` lua
if redis.call("GET", KEYS[1]) == ARGV[1] then
    return redis.call("DEL", KEYS[1])
end

return 0
```

This prevents an old lock holder from deleting a newer holder's lock.

------------------------------------------------------------------------

# Part 12 --- Why Plain DEL Is Unsafe

## 14. Timeline

``` text
Client A acquires lock token-A
Client A stalls
lock expires

Client B acquires same lock token-B

Client A resumes
Client A DEL lock
```

Now Client B loses a lock it legitimately owns.

Ownership-safe compare-and-delete prevents this.

------------------------------------------------------------------------

# Part 13 --- Unique Ownership Tokens

## 15. Token

A lock value should identify the holder uniquely.

Example concept:

``` text
UUID/random high-entropy token
```

Do not use a shared constant such as:

``` text
locked
```

when ownership verification is required.

------------------------------------------------------------------------

# Part 14 --- Script Return Values

## 16. Keep Contracts Clear

A script should have a documented result contract.

Example:

``` text
1 -> update applied
0 -> condition not met
-1 -> application-specific invalid state
```

Do not make clients guess what script output means.

------------------------------------------------------------------------

# Part 15 --- EVALSHA

## 17. Script Digest

Instead of repeatedly sending the entire script, clients can execute a
cached script by SHA digest.

Flow:

``` text
SCRIPT LOAD
 -> SHA

EVALSHA SHA ...
```

------------------------------------------------------------------------

# Part 16 --- SCRIPT LOAD

## 18. Example

``` redis
SCRIPT LOAD "return redis.call('GET', KEYS[1])"
```

Redis returns a SHA digest.

Then:

``` redis
EVALSHA <sha> 1 tutorial:chapter23:item
```

------------------------------------------------------------------------

# Part 17 --- NOSCRIPT

## 19. Cache Miss

A client may attempt:

``` text
EVALSHA
```

and receive a `NOSCRIPT` error because the script is not currently
available in the server's script cache.

The client should have a defined fallback.

------------------------------------------------------------------------

# Part 18 --- NOSCRIPT Recovery

## 20. Common Pattern

``` text
try EVALSHA
 |
NOSCRIPT
 |
load/evaluate script
 |
retry safely
```

Many client libraries provide helpers for this.

Understand the behavior of the exact client/version.

------------------------------------------------------------------------

# Part 19 --- Script Registration

## 21. redis-py

Example:

``` python
cas_script = r.register_script("""
local current = redis.call("GET", KEYS[1])

if current ~= ARGV[1] then
    return 0
end

redis.call("SET", KEYS[1], ARGV[2])

return 1
""")
```

Client helpers can manage SHA execution and fallback behavior.

------------------------------------------------------------------------

# Part 20 --- Script Blocking Risk

## 22. Atomic Means Other Work Waits

While a script is executing, other Redis command processing cannot
interleave with it.

Therefore:

``` text
slow script
 -> Redis latency
 -> application latency
 -> timeouts
 -> retries
```

A script must not perform unbounded work.

------------------------------------------------------------------------

# Part 21 --- Bounded Loops

## 23. Safe Principle

If a script loops, the maximum iteration count should be known and
small.

Prefer:

``` text
loop over 10 known items
```

over:

``` text
loop until entire dataset processed
```

------------------------------------------------------------------------

# Part 22 --- Avoid Keyspace Scans in Scripts

## 24. Dangerous Design

Do not use Lua as a replacement for offline/batched keyspace processing.

A script should not attempt:

``` text
discover every key
inspect every object
delete an entire large namespace
```

Use operationally safe batching outside the script.

------------------------------------------------------------------------

# Part 23 --- Large Collections

## 25. Collection Work

Even when a script touches one Redis key, an operation against a huge
collection may still be expensive.

Review:

``` text
collection cardinality
command complexity
response size
script loop count
```

Chapter 18 big-key engineering remains relevant.

------------------------------------------------------------------------

# Part 24 --- Large Responses

## 26. Return Only What Is Needed

Do not make a script return massive datasets merely because it can
access them.

Large responses increase:

``` text
network
client memory
serialization
latency
```

------------------------------------------------------------------------

# Part 25 --- Error Handling

## 27. redis.call

`redis.call(...)` propagates Redis command errors to the script.

Use when the operation should fail on command error.

------------------------------------------------------------------------

# Part 26 --- redis.pcall

## 28. Protected Call

`redis.pcall(...)` allows the script to inspect an error reply rather
than immediately propagating it in the same way.

Use intentionally.

Do not hide important failures.

------------------------------------------------------------------------

# Part 27 --- Script Validation

## 29. Validate Inputs

Check application assumptions where appropriate:

``` text
argument presence
numeric ranges
expected state
maximum batch size
```

Do not allow callers to turn a bounded script into unbounded work
through arbitrary arguments.

------------------------------------------------------------------------

# Part 28 --- TTL in Scripts

## 30. Conditional Update With Expiration

A script can combine:

``` text
validate
set
expire
```

atomically when the business operation requires those actions together.

Prefer a built-in command if it already supports the exact required
options.

------------------------------------------------------------------------

# Part 29 --- Counter Bounds

## 31. Example Use Case

Requirement:

``` text
increment counter only if new value <= limit
```

A script can:

``` text
read
calculate
validate limit
write
return
```

atomically.

------------------------------------------------------------------------

# Part 30 --- Rate-Limit Building Blocks

## 32. Script Use

Lua is commonly useful for bounded rate-limit state transitions.

But a production rate limiter also requires:

``` text
time semantics
failure behavior
key distribution
TTL
observability
capacity
```

Do not reduce rate limiting to a copied script without reviewing the
full design.

------------------------------------------------------------------------

# Part 31 --- Transactions vs. Lua

## 33. WATCH/MULTI

Chapter 22 pattern:

``` text
WATCH
read
client computes
MULTI
write
EXEC
```

Can conflict and retry.

------------------------------------------------------------------------

## 34. Lua

``` text
send bounded logic
Redis reads + decides + writes atomically
return result
```

This can reduce race windows and round trips.

------------------------------------------------------------------------

# Part 32 --- When WATCH Is Better

## 35. Consider WATCH When

``` text
application needs complex external computation
logic should remain in application code
conflicts are rare
server-side script would become too complex
```

------------------------------------------------------------------------

# Part 33 --- When Lua Is Better

## 36. Consider Lua When

``` text
logic is small
all required state is in Redis
atomic read/compare/write is needed
extra client round trips are undesirable
```

------------------------------------------------------------------------

# Part 34 --- Cross-System Boundary

## 37. Lua Cannot Make External Systems Atomic

A Redis script cannot atomically include:

``` text
PostgreSQL update
HTTP request
Kafka publish
external API
```

Lua atomicity applies to Redis-side operations within its execution
boundary.

------------------------------------------------------------------------

# Part 35 --- Cluster / Sharded Redis

## 38. Key Declaration

Scripts must receive accessed keys through the supported key declaration
mechanism.

In clustered deployments, keys involved in one script must satisfy
topology/slot constraints.

Validate against the deployed Redis Enterprise mode and client.

------------------------------------------------------------------------

# Part 36 --- Hash Tags

## 39. Example

``` text
account:{1001}:balance
account:{1001}:limit
```

can place related keys into the same Redis Cluster slot.

This can support valid multi-key atomic operations.

------------------------------------------------------------------------

# Part 37 --- Hot-Slot Risk

## 40. Balance

Do not put unrelated workload under one hash tag merely to make
scripting convenient.

Example anti-pattern:

``` text
{global}:user:1
{global}:user:2
{global}:user:3
...
```

This can concentrate workload.

------------------------------------------------------------------------

# Part 38 --- Script Deployment

## 41. Treat Scripts as Code

Production scripts should have:

``` text
source control
review
tests
versioning
owner
rollback strategy
observability
```

Do not paste unreviewed scripts directly into production.

------------------------------------------------------------------------

# Part 39 --- Script Versioning

## 42. Version Behavior

If application logic changes:

``` text
script v1
script v2
```

clients and deployment order must be compatible.

Document:

``` text
inputs
outputs
key format
semantics
```

------------------------------------------------------------------------

# Part 40 --- Observability

## 43. Application Metrics

Track:

``` text
redis_script_total
redis_script_success_total
redis_script_error_total
redis_script_duration_seconds
redis_script_noscript_total
redis_script_fallback_total
```

------------------------------------------------------------------------

## 44. Per-Script Metrics

Use a bounded script identifier such as:

``` text
lock_release
cas_update
bounded_counter
```

Avoid unbounded SHA/key labels.

------------------------------------------------------------------------

## 45. Redis Metrics

Correlate scripts with:

``` text
Redis latency
CPU
ops/sec
network
timeouts
slow operations
hot keys
shard distribution
```

------------------------------------------------------------------------

# Part 41 --- Hands-On Lab

## 46. Objectives

You will:

1.  execute a basic Lua script;
2.  use `KEYS`;
3.  use `ARGV`;
4.  implement CAS;
5.  implement safe lock release;
6.  load a script;
7.  execute with SHA;
8.  handle `NOSCRIPT`;
9.  compare WATCH vs. Lua;
10. create a bounded counter;
11. inject script failures;
12. clean up safely.

------------------------------------------------------------------------

## 47. Prerequisites

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

# Part 42 --- Basic EVAL Lab

## 48. Return Constant

``` redis
EVAL "return 42" 0
```

Expected:

``` text
42
```

------------------------------------------------------------------------

## 49. Read Key

``` redis
SET tutorial:chapter23:item hello

EVAL "return redis.call('GET', KEYS[1])" 1 tutorial:chapter23:item
```

Expected:

``` text
hello
```

------------------------------------------------------------------------

# Part 43 --- ARGV Lab

## 50. Echo Argument

``` redis
EVAL "return ARGV[1]" 0 production
```

Expected:

``` text
production
```

------------------------------------------------------------------------

# Part 44 --- Python Lab

## 51. Create `chapter23_lua_lab.py`

``` python
import os
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

CAS_KEY = "tutorial:chapter23:cas"
LOCK_KEY = "tutorial:chapter23:lock"
COUNTER_KEY = "tutorial:chapter23:bounded-counter"

CAS_SCRIPT = """
local current = redis.call("GET", KEYS[1])

if current ~= ARGV[1] then
    return 0
end

redis.call("SET", KEYS[1], ARGV[2])

return 1
"""

LOCK_RELEASE_SCRIPT = """
if redis.call("GET", KEYS[1]) == ARGV[1] then
    return redis.call("DEL", KEYS[1])
end

return 0
"""

BOUNDED_COUNTER_SCRIPT = """
local current = tonumber(redis.call("GET", KEYS[1]) or "0")
local increment = tonumber(ARGV[1])
local limit = tonumber(ARGV[2])

if not increment or not limit then
    return redis.error_reply("invalid numeric argument")
end

local new_value = current + increment

if new_value > limit then
    return {0, current}
end

redis.call("SET", KEYS[1], new_value)

return {1, new_value}
"""


def cas(expected, new_value):
    return r.eval(
        CAS_SCRIPT,
        1,
        CAS_KEY,
        expected,
        new_value,
    )


def acquire_lock(ttl=10):
    token = str(uuid.uuid4())

    acquired = r.set(
        LOCK_KEY,
        token,
        nx=True,
        ex=ttl,
    )

    if not acquired:
        return None

    return token


def release_lock(token):
    return r.eval(
        LOCK_RELEASE_SCRIPT,
        1,
        LOCK_KEY,
        token,
    )


def bounded_increment(amount, limit):
    return r.eval(
        BOUNDED_COUNTER_SCRIPT,
        1,
        COUNTER_KEY,
        amount,
        limit,
    )


if __name__ == "__main__":
    print("PING:", r.ping())

    r.set(CAS_KEY, "v1")

    print(
        "CAS v1 -> v2:",
        cas("v1", "v2"),
    )

    print(
        "CAS v1 -> v3:",
        cas("v1", "v3"),
    )

    token = acquire_lock()

    print(
        "Lock token:",
        token,
    )

    if token:
        print(
            "Wrong owner release:",
            release_lock("wrong-token"),
        )

        print(
            "Correct owner release:",
            release_lock(token),
        )

    r.set(COUNTER_KEY, 0)

    print(
        "Counter +3 limit 10:",
        bounded_increment(3, 10),
    )

    print(
        "Counter +4 limit 10:",
        bounded_increment(4, 10),
    )

    print(
        "Counter +5 limit 10:",
        bounded_increment(5, 10),
    )
```

------------------------------------------------------------------------

# Part 45 --- Run Lab

## 52. Execute

``` bash
python chapter23_lua_lab.py
```

Expected pattern:

``` text
PING: True

CAS v1 -> v2: 1
CAS v1 -> v3: 0

Wrong owner release: 0
Correct owner release: 1

Counter +3 limit 10: [1, 3]
Counter +4 limit 10: [1, 7]
Counter +5 limit 10: [0, 7]
```

Exact formatting depends on the client.

------------------------------------------------------------------------

# Part 46 --- Script Cache Lab

## 53. Load Script

Python:

``` python
sha = r.script_load(CAS_SCRIPT)

print("SHA:", sha)
```

Then:

``` python
result = r.evalsha(
    sha,
    1,
    CAS_KEY,
    "v2",
    "v3",
)

print(result)
```

------------------------------------------------------------------------

# Part 47 --- NOSCRIPT Lab

## 54. Recovery Pattern

Conceptual client logic:

``` python
try:
    result = r.evalsha(
        sha,
        1,
        CAS_KEY,
        "v3",
        "v4",
    )

except redis.exceptions.NoScriptError:
    sha = r.script_load(CAS_SCRIPT)

    result = r.evalsha(
        sha,
        1,
        CAS_KEY,
        "v3",
        "v4",
    )
```

Do not flush a production script cache merely to test this scenario.

Use a disposable lab instance if you need to force `NOSCRIPT`.

------------------------------------------------------------------------

# Part 48 --- register_script Lab

## 55. Client Helper

``` python
registered_cas = r.register_script(
    CAS_SCRIPT
)

result = registered_cas(
    keys=[CAS_KEY],
    args=["v4", "v5"],
)

print(result)
```

Understand how the client helper handles script loading and cache
misses.

------------------------------------------------------------------------

# Part 49 --- Safe Lock Race Lab

## 56. Reproduce Old Owner

Concept:

``` text
Client A token-A
lock expires
Client B token-B
Client A tries release with token-A
```

Expected:

``` text
release returns 0
token-B remains
```

Never replace ownership-safe release with unconditional `DEL`.

------------------------------------------------------------------------

# Part 50 --- Bounded Counter Lab

## 57. Concurrent Test

Run several workers calling:

``` text
bounded_increment(1, 100)
```

Expected:

``` text
counter never exceeds 100
```

The script performs:

``` text
read
calculate
validate
write
```

atomically.

------------------------------------------------------------------------

# Part 51 --- WATCH vs. Lua Benchmark

## 58. Compare

For the same CAS workload, record:

``` text
operations/sec
P50
P95
P99
conflicts/retries for WATCH
script errors
Redis CPU
```

Do not conclude Lua is always better solely from one microbenchmark.

Maintainability and contention model matter.

------------------------------------------------------------------------

# Part 52 --- Failure Injection

## 59. Failure 1 --- Wrong Expected Value

CAS with:

``` text
current = v5
expected = v4
```

Expected:

``` text
0
```

No update.

------------------------------------------------------------------------

## 60. Failure 2 --- Wrong Lock Owner

Attempt safe release using a different token.

Expected:

``` text
0
```

Lock remains.

------------------------------------------------------------------------

## 61. Failure 3 --- Expired Lock / New Owner

Allow owner A's lock to expire.

Acquire as owner B.

Owner A attempts release.

Expected:

``` text
owner B remains protected
```

------------------------------------------------------------------------

## 62. Failure 4 --- Invalid Numeric Argument

Call bounded counter with invalid numeric input.

Expected:

``` text
script error
```

The client must surface and measure it.

------------------------------------------------------------------------

## 63. Failure 5 --- Oversized Loop

In a disposable environment only, compare a tiny bounded loop with a
much larger loop.

Observe latency impact.

Do not run deliberately blocking scripts on production.

------------------------------------------------------------------------

## 64. Failure 6 --- Large Response

Create a test script that returns a bounded but increasingly large
response in a disposable lab.

Observe:

``` text
network
client memory
latency
```

Then reduce returned data.

------------------------------------------------------------------------

## 65. Failure 7 --- NOSCRIPT

Use a disposable environment to create a script-cache-miss scenario.

Validate fallback.

Do not rely on manual operational intervention.

------------------------------------------------------------------------

## 66. Failure 8 --- Cross-Slot Keys

In a Redis Cluster-compatible lab, pass keys from incompatible slots to
a multi-key script.

Observe the topology constraint.

Then use valid key design/hash tags where the atomic boundary is
justified.

------------------------------------------------------------------------

## 67. Failure 9 --- Hot-Key Script

Run a small script at high concurrency against one key.

Observe:

``` text
Redis CPU
latency
ops/sec
hot-key concentration
```

Lua does not remove hot-key risk.

------------------------------------------------------------------------

## 68. Failure 10 --- Script Error Storm

Make callers repeatedly invoke a script with invalid input and immediate
retries.

Observe:

``` text
error rate
retry amplification
latency
```

Add validation and bounded retry policy.

------------------------------------------------------------------------

# Part 53 --- Troubleshooting

## 69. Redis Latency Increased After Script Deployment

Check:

``` text
script duration
call rate
loop bounds
command complexity
hot keys
response size
```

Rollback or disable unsafe script use if necessary.

------------------------------------------------------------------------

## 70. NOSCRIPT Errors

Check:

``` text
client fallback
script registration
server/failover/restart context
deployment behavior
```

Applications should not assume a SHA is permanently available everywhere
forever.

------------------------------------------------------------------------

## 71. Lock Deleted by Wrong Client

Check whether release uses:

``` text
GET
DEL
```

as separate client operations or unconditional `DEL`.

Replace with ownership-safe atomic release.

------------------------------------------------------------------------

## 72. Counter Exceeds Limit

Check whether application uses:

``` text
GET
calculate
SET
```

instead of one atomic operation.

Review script logic and all alternate write paths.

------------------------------------------------------------------------

## 73. Script Works Standalone but Fails in Cluster

Check:

``` text
declared keys
slots
hash tags
client routing
topology mode
```

------------------------------------------------------------------------

## 74. Script CPU High

Check:

``` text
invocation rate
loop size
collection size
command complexity
hot slot
```

Do not only optimize Lua syntax; reconsider the workload.

------------------------------------------------------------------------

## 75. Unexpected Script Result

Check:

``` text
return contract
input serialization
string vs. numeric conversion
missing keys
client decoding
script version
```

------------------------------------------------------------------------

# Part 54 --- Production Runbooks

## 76. Runbook --- Slow Script

``` text
1. Identify script.
2. Measure call rate.
3. Measure duration.
4. Inspect loop bounds.
5. Inspect Redis commands used.
6. Check key/collection size.
7. Check response size.
8. Reduce/disable unsafe path.
9. Deploy bounded correction.
10. Revalidate Redis latency.
```

------------------------------------------------------------------------

## 77. Runbook --- NOSCRIPT Spike

``` text
1. Confirm NOSCRIPT error.
2. Identify affected script/client.
3. Verify client fallback.
4. Reload/evaluate through normal client path.
5. Check recent restart/failover/deployment.
6. Confirm all application instances recover.
7. Measure fallback errors.
8. Avoid manual per-node assumptions.
9. Test future cache-miss recovery.
10. Close only after automatic recovery is proven.
```

------------------------------------------------------------------------

## 78. Runbook --- Lock Ownership Incident

``` text
1. Inspect lock key.
2. Inspect ownership token.
3. Identify release implementation.
4. Stop unconditional delete path.
5. Use compare-and-delete script.
6. Verify unique tokens.
7. Test expiry/new-owner race.
8. Test client crash.
9. Monitor lock contention.
10. Document ownership semantics.
```

------------------------------------------------------------------------

## 79. Runbook --- Script Error Spike

``` text
1. Capture exact error.
2. Identify script version.
3. Identify inputs.
4. Check Redis data types/state.
5. Stop retry storm.
6. Validate argument bounds.
7. Correct caller or script.
8. Deploy safely.
9. Monitor error rate.
10. Add regression test.
```

------------------------------------------------------------------------

## 80. Runbook --- Cluster Script Failure

``` text
1. List all script keys.
2. Determine key slots.
3. Check hash tags.
4. Confirm atomicity requirement.
5. Co-locate only related keys.
6. Avoid hot-slot design.
7. Validate client routing.
8. Test failover/topology change.
9. Benchmark workload.
10. Document slot dependency.
```

------------------------------------------------------------------------

# Part 55 --- Script Design Template

## 81. Fields

``` text
Script name:
Owner:
Purpose:
Atomicity requirement:
Why built-in command is insufficient:
Why WATCH is insufficient/less suitable:
Keys:
ARGV:
Maximum keys:
Maximum iterations:
Expected key sizes:
Commands called:
Return contract:
Expected duration:
Call rate:
Cluster slots:
Hash tags:
Error behavior:
Retry behavior:
Idempotent?:
NOSCRIPT recovery:
Metrics:
Rollback:
```

------------------------------------------------------------------------

# Part 56 --- Script Review Checklist

## 82. Review

``` text
Is the script necessary?
Can one built-in command replace it?
Is every loop bounded?
Are all keys declared correctly?
Can any key be unexpectedly huge?
Is response size bounded?
Is the return contract documented?
Are errors visible?
Can retries amplify load?
Does cluster placement work?
Is the script version controlled?
Is rollback possible?
```

------------------------------------------------------------------------

# Production Acceptance Checklist

## 83. Lua Engineering

-   [ ] Script atomicity requirement documented.
-   [ ] Built-in Redis commands considered first.
-   [ ] WATCH/MULTI alternative considered.
-   [ ] Script source controlled.
-   [ ] Script owner defined.
-   [ ] `KEYS` usage correct.
-   [ ] `ARGV` usage correct.
-   [ ] Loop bounds documented.
-   [ ] Key-size assumptions documented.
-   [ ] Response size bounded.
-   [ ] Return contract documented.
-   [ ] Error behavior tested.
-   [ ] CAS behavior tested.
-   [ ] Safe lock release tested.
-   [ ] Expired-lock/new-owner race tested.
-   [ ] `EVALSHA` tested.
-   [ ] `NOSCRIPT` recovery tested.
-   [ ] Client helper behavior verified.
-   [ ] Cluster key placement tested.
-   [ ] Hash-tag design reviewed.
-   [ ] Hot-key load tested.
-   [ ] Script latency monitored.
-   [ ] Retry behavior bounded.
-   [ ] Production runbooks validated.

------------------------------------------------------------------------

# Knowledge Validation

## 84. Questions

You should be able to answer:

1.  Why use Lua in Redis?
2.  What atomicity property does script execution provide?
3.  What does `EVAL` do?
4.  What is `KEYS`?
5.  What is `ARGV`?
6.  Why should key names not be hidden as ordinary arguments in
    cluster-sensitive scripts?
7.  Why prefer built-in Redis commands when possible?
8.  What is compare-and-set?
9.  Why must compare and update be atomic?
10. Why is unconditional lock `DEL` unsafe?
11. What is an ownership token?
12. What is `EVALSHA`?
13. What does `SCRIPT LOAD` return?
14. What is `NOSCRIPT`?
15. How should a client recover from `NOSCRIPT`?
16. Why can Lua scripts increase Redis latency?
17. Why must loops be bounded?
18. Why should scripts avoid keyspace-scale work?
19. What is the difference between `redis.call` and `redis.pcall`?
20. Why validate script inputs?
21. When can Lua be better than WATCH?
22. When can WATCH be better than Lua?
23. Can Lua make PostgreSQL and Redis updates one atomic transaction?
24. Why do cluster slots matter?
25. What do hash tags enable?
26. How can hash tags create hot slots?
27. Why should scripts be version controlled?
28. Which metrics should be tracked?
29. Why is a script error storm dangerous?
30. What must pass before a Lua script is production-ready?

------------------------------------------------------------------------

# Hands-On Acceptance Checklist

## 85. Lab Completion

-   [ ] Executed basic `EVAL`.
-   [ ] Passed a key through `KEYS`.
-   [ ] Passed an argument through `ARGV`.
-   [ ] Implemented Lua CAS.
-   [ ] Tested CAS mismatch.
-   [ ] Implemented ownership-safe lock release.
-   [ ] Tested wrong-owner release.
-   [ ] Tested expired-owner/new-owner protection.
-   [ ] Implemented bounded counter.
-   [ ] Tested limit rejection.
-   [ ] Loaded script with `SCRIPT LOAD`.
-   [ ] Executed script with `EVALSHA`.
-   [ ] Reviewed `NOSCRIPT` recovery.
-   [ ] Used `register_script`.
-   [ ] Compared WATCH and Lua.
-   [ ] Reviewed bounded execution.
-   [ ] Reviewed cluster key placement.
-   [ ] Completed ten failure scenarios.
-   [ ] Completed troubleshooting.
-   [ ] Reviewed five production runbooks.
-   [ ] Completed script design template.
-   [ ] Completed script review checklist.
-   [ ] Completed production acceptance checklist.

------------------------------------------------------------------------

# 86. Lab Cleanup

Discover:

``` bash
redis-cli --scan --pattern 'tutorial:chapter23:*'
```

Delete only confirmed Chapter 23 training keys in bounded batches with
`UNLINK`.

Examples:

``` redis
UNLINK tutorial:chapter23:item
UNLINK tutorial:chapter23:cas
UNLINK tutorial:chapter23:lock
UNLINK tutorial:chapter23:bounded-counter
```

Do not use:

``` redis
FLUSHDB
FLUSHALL
```

against a shared or production database.

Do not run:

``` redis
SCRIPT FLUSH
```

against a shared production Redis deployment merely to clean up this
tutorial.

------------------------------------------------------------------------

# 87. Key Takeaways

1.  Lua provides bounded server-side atomic logic.
2.  Use Lua for small atomic operations, not general application
    processing.
3.  Prefer built-in atomic Redis commands when they already solve the
    problem.
4.  `KEYS` identifies script keys and `ARGV` carries non-key arguments.
5.  Compare-and-set is a natural Lua use case.
6.  Lock release must verify ownership atomically.
7.  Unique lock tokens prevent an old holder from deleting a new
    holder's lock.
8.  `EVALSHA` reduces repeated script transfer and relies on
    script-cache availability.
9.  Applications need automatic `NOSCRIPT` recovery.
10. Script atomicity means slow scripts can delay other Redis work.
11. Every loop and response should be bounded.
12. Avoid keyspace-scale processing inside scripts.
13. `redis.call` and `redis.pcall` have different error-handling
    behavior.
14. Lua can reduce round trips compared with WATCH-based
    read/compare/write.
15. WATCH may remain preferable when logic belongs in the application or
    requires complex external computation.
16. Lua cannot provide atomicity across external systems.
17. Clustered deployments require correct key declaration and compatible
    placement.
18. Hash tags can enable valid co-location but can also create hot
    slots.
19. Scripts are production code and require source control, tests,
    versioning, metrics, and rollback.
20. Production readiness requires bounded execution, failure testing,
    automatic recovery, topology validation, and runbooks.

------------------------------------------------------------------------

# 88. References

Validate exact behavior against the Redis, Redis Enterprise, and
client-library versions deployed.

Recommended official Redis documentation areas:

-   Redis programmability
-   Lua scripting
-   `EVAL`
-   `EVALSHA`
-   `SCRIPT LOAD`
-   script-cache behavior
-   Redis transactions
-   `WATCH`
-   `MULTI`
-   `EXEC`
-   `SET`
-   `DEL`
-   Redis distributed-locking guidance
-   Redis Cluster
-   Redis Cluster hash tags
-   Redis latency monitoring
-   redis-py scripting helpers
-   Redis Enterprise monitoring

Server-side scripting is powerful because it executes atomically. That
same property makes unbounded scripts operationally dangerous.
Production scripts should be deliberately small, predictable,
observable, and tested with realistic key sizes and concurrency.

------------------------------------------------------------------------

# Next Chapter

**Chapter 24 --- Redis Distributed Locks, Leases & Coordination
Patterns**

Chapter 24 will cover:

-   lock acquisition
-   unique ownership tokens
-   TTL-based leases
-   ownership-safe release
-   lease renewal
-   lock expiry races
-   stale owners
-   fencing tokens
-   contention
-   backoff and jitter
-   failure semantics
-   process/node failure
-   Redis failover considerations
-   when not to use distributed locks
-   observability
-   failure injection
-   troubleshooting
-   production runbooks
-   acceptance validation
