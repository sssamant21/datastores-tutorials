# Chapter 22 --- Redis Transactions, WATCH & Atomic Update Patterns

**Status:** Canonical\
**Track:** Redis Enterprise / Redis Software Production Engineering\
**Part:** Part 2 --- Caching & Application Engineering\
**Level:** Intermediate → Production Redis Concurrency Engineering\
**Audience:** Developers, SREs, DBREs, Platform Engineers, Redis
Administrators\
**Lab type:** MULTI/EXEC, DISCARD, optimistic concurrency, WATCH,
compare-and-set, conflict injection, bounded retries, transaction error
behavior, pipelines vs. transactions, Lua alternatives, cluster-slot
constraints, observability, troubleshooting, runbooks, and production
acceptance

------------------------------------------------------------------------

# 1. Objective

Redis commands are individually atomic, but applications often need to
coordinate several operations.

Example:

``` text
read current value
validate condition
write new value
```

Without concurrency control:

``` text
Client A reads version 10
Client B reads version 10

Client A writes version 11
Client B writes version 11
```

One update may overwrite another.

Redis provides several mechanisms for atomic update patterns:

``` text
MULTI / EXEC
WATCH
Lua/server-side logic
atomic built-in commands
```

By the end, you should be able to:

-   Explain Redis transaction semantics.
-   Use `MULTI`, `EXEC`, and `DISCARD`.
-   Understand command queuing.
-   Explain what Redis transactions do not provide.
-   Use `WATCH` for optimistic concurrency.
-   Implement compare-and-set.
-   Detect transaction conflicts.
-   Build bounded retry loops.
-   Add backoff and jitter.
-   Understand transaction error behavior.
-   Distinguish transactions from pipelines.
-   Prefer atomic built-in commands where appropriate.
-   Understand when Lua/server-side logic is a better fit.
-   Understand cluster slot constraints.
-   Test concurrent updates.
-   Observe conflicts and retries.
-   Troubleshoot transaction incidents.
-   Build production runbooks and acceptance criteria.

------------------------------------------------------------------------

# 2. Core Production Principle

Use the simplest atomic primitive that correctly solves the problem.

Prefer:

``` text
single atomic Redis command
```

before:

``` text
transaction
```

and prefer a clear bounded transaction before inventing a complex
distributed locking protocol.

Examples:

``` redis
INCR counter
HINCRBY hash field 1
SET key value NX
```

already provide atomic server-side operations for their individual
semantics.

------------------------------------------------------------------------

# Part 1 --- Individual Command Atomicity

## 3. Single Commands

Redis processes an individual command atomically relative to other
commands.

Example:

``` redis
INCR tutorial:chapter22:counter
```

Concurrent clients do not need:

``` text
GET
calculate
SET
```

for a simple increment.

------------------------------------------------------------------------

# Part 2 --- Unsafe Read-Modify-Write

## 4. Race

Unsafe application logic:

``` python
value = int(r.get(key))
value += 1
r.set(key, value)
```

Two clients can read the same old value and overwrite one another.

Use an atomic Redis operation when one exists.

------------------------------------------------------------------------

# Part 3 --- MULTI

## 5. Begin Transaction

``` redis
MULTI
```

After `MULTI`, commands are queued for later execution.

------------------------------------------------------------------------

# Part 4 --- EXEC

## 6. Execute Queued Commands

``` redis
EXEC
```

Redis executes the queued transaction commands without interleaving
commands from other clients between those transaction commands.

------------------------------------------------------------------------

# Part 5 --- DISCARD

## 7. Cancel Queued Transaction

``` redis
MULTI
SET tutorial:chapter22:a 1
SET tutorial:chapter22:b 2
DISCARD
```

The queued commands are discarded rather than executed.

------------------------------------------------------------------------

# Part 6 --- Transaction Example

## 8. CLI

``` redis
MULTI
SET tutorial:chapter22:user:1001:name Alice
SET tutorial:chapter22:user:1001:status active
EXEC
```

Expected flow:

``` text
MULTI -> OK
SET   -> QUEUED
SET   -> QUEUED
EXEC  -> results
```

------------------------------------------------------------------------

# Part 7 --- What Redis Transactions Are Not

## 9. Not a Relational Database Transaction Model

Do not automatically map Redis `MULTI/EXEC` to every property or
behavior expected from a relational database transaction.

Redis transaction semantics are specific to Redis.

------------------------------------------------------------------------

## 10. No General Rollback of Executed Commands

If a queued command produces a runtime error during `EXEC`, other valid
transaction commands may still execute.

Do not design Redis transactions assuming automatic rollback of earlier
successful commands.

------------------------------------------------------------------------

# Part 8 --- Queue-Time Errors

## 11. Invalid Queuing

Some errors can be detected before `EXEC`, such as malformed command
syntax.

These can prevent the transaction from executing normally.

Validate exact behavior against the deployed Redis version.

------------------------------------------------------------------------

# Part 9 --- Runtime Errors

## 12. Wrong-Type Example

Conceptually:

``` redis
SET tutorial:chapter22:type string-value

MULTI
SET tutorial:chapter22:before ok
LPUSH tutorial:chapter22:type x
SET tutorial:chapter22:after ok
EXEC
```

`LPUSH` targets a string and can produce a wrong-type error.

Do not assume the valid `SET` commands are rolled back.

------------------------------------------------------------------------

# Part 10 --- Optimistic Concurrency

## 13. Concept

Optimistic concurrency assumes conflicts are possible but not constant.

Flow:

``` text
watch state
read state
calculate update
attempt transaction
```

If watched state changes before `EXEC`, abort and retry.

------------------------------------------------------------------------

# Part 11 --- WATCH

## 14. Monitor Key Changes

``` redis
WATCH tutorial:chapter22:balance
```

Then read:

``` redis
GET tutorial:chapter22:balance
```

Prepare update:

``` redis
MULTI
SET tutorial:chapter22:balance 90
EXEC
```

If the watched key changed before execution, the optimistic transaction
does not commit normally.

------------------------------------------------------------------------

# Part 12 --- Compare-and-Set

## 15. CAS Pattern

Conceptually:

``` text
WATCH key
current = GET key

if current != expected:
    abort

MULTI
SET key new
EXEC
```

This provides an optimistic compare-and-set pattern.

------------------------------------------------------------------------

# Part 13 --- Conflict Timeline

## 16. Example

``` text
Client A WATCH key
Client A GET -> 10

Client B SET key -> 11

Client A MULTI
Client A SET key -> 12
Client A EXEC
```

Client A's watched state changed.

The transaction should be treated as a conflict, not silently accepted
as if its original read were still current.

------------------------------------------------------------------------

# Part 14 --- Retry

## 17. Conflict Is Expected

A `WATCH` conflict is not necessarily an infrastructure failure.

It can simply mean:

``` text
another client updated the same state
```

The application may retry from a fresh read.

------------------------------------------------------------------------

# Part 15 --- Bounded Retry

## 18. Never Retry Forever

Use:

``` text
maximum attempts
timeout/deadline
backoff
jitter
```

Unbounded retry under contention can create a retry storm.

------------------------------------------------------------------------

# Part 16 --- Retry Jitter

## 19. Purpose

If many clients conflict simultaneously and retry immediately:

``` text
conflict
 -> immediate retry
 -> conflict
 -> immediate retry
```

Jitter spreads retry timing.

------------------------------------------------------------------------

# Part 17 --- High Contention

## 20. Optimistic Concurrency Has Limits

If a key is extremely hot:

``` text
many writers
 -> frequent WATCH conflicts
 -> retries
 -> latency
```

At high contention, reconsider the data model or use a more suitable
atomic primitive.

------------------------------------------------------------------------

# Part 18 --- Built-In Atomic Operations

## 21. Prefer Them When Possible

Instead of:

``` text
WATCH
GET counter
MULTI
SET counter+1
EXEC
```

use:

``` redis
INCR counter
```

when the required semantics are exactly increment.

------------------------------------------------------------------------

# Part 19 --- Conditional SET

## 22. Built-In Condition

For lock/claim-style state:

``` redis
SET key value NX EX 30
```

can atomically combine conditions/options.

Do not replace a suitable built-in command with unnecessary transaction
complexity.

------------------------------------------------------------------------

# Part 20 --- Transactions vs. Pipelines

## 23. Pipeline

Primary goal:

``` text
reduce network round trips
```

------------------------------------------------------------------------

## 24. Transaction

Primary goal:

``` text
group queued commands under Redis transaction execution semantics
```

Chapter 21 covers pipelining.

Some clients expose both through similar APIs.

------------------------------------------------------------------------

# Part 21 --- redis-py Pipeline API

## 25. Important Behavior

In redis-py, a pipeline can also provide transaction support.

Example:

``` python
pipe = r.pipeline()
```

commonly uses transactional behavior by default.

Pure pipeline:

``` python
pipe = r.pipeline(transaction=False)
```

Understand the exact client version.

------------------------------------------------------------------------

# Part 22 --- WATCH With redis-py

## 26. Typical Pattern

``` python
with r.pipeline() as pipe:
    while True:
        try:
            pipe.watch(key)

            current = pipe.get(key)

            pipe.multi()
            pipe.set(key, new_value)
            pipe.execute()

            break

        except redis.WatchError:
            continue
```

Production code needs bounded retries, backoff, metrics, and correct
reset behavior.

------------------------------------------------------------------------

# Part 23 --- Lua Alternative

## 27. Server-Side Compare-and-Set

For compact logic:

``` text
read
compare
write
```

Lua/server-side logic can sometimes avoid the client round trip between
read and transaction attempt.

Example concept:

``` lua
local current = redis.call("GET", KEYS[1])

if current ~= ARGV[1] then
    return 0
end

redis.call("SET", KEYS[1], ARGV[2])

return 1
```

------------------------------------------------------------------------

# Part 24 --- WATCH vs. Lua

## 28. WATCH Strength

Useful when:

``` text
application needs to inspect state
logic is naturally optimistic
conflicts are uncommon
```

------------------------------------------------------------------------

## 29. Lua Strength

Useful when:

``` text
logic is small
logic can run atomically server-side
extra round trips are undesirable
```

Keep server-side logic bounded and well understood.

------------------------------------------------------------------------

# Part 25 --- Long Transactions

## 30. Avoid Excessive Work

A transaction containing large or expensive commands can block other
command processing for longer.

Keep transactions:

``` text
small
bounded
fast
```

------------------------------------------------------------------------

# Part 26 --- Large Payloads

## 31. Transaction Size

A transaction with many large writes can create:

``` text
network burst
memory pressure
replication load
latency
```

Atomic grouping is not a reason to create oversized transactions.

------------------------------------------------------------------------

# Part 27 --- Cluster / Sharded Redis

## 32. Key Placement

In Redis Cluster-style sharding, multi-key transactional/server-side
operations are constrained by key slot placement.

Keys that must participate in one atomic operation generally need
compatible placement.

Validate exact Redis Enterprise topology/client behavior.

------------------------------------------------------------------------

# Part 28 --- Hash Tags

## 33. Example

``` text
account:{1001}:balance
account:{1001}:version
```

The `{1001}` hash tag can place related keys into the same Redis Cluster
slot.

Use hash tags intentionally.

------------------------------------------------------------------------

# Part 29 --- Hot Slot Risk

## 34. Do Not Over-Co-Locate

If every unrelated key uses:

``` text
{global}
```

you can create a single-slot hotspot.

Atomicity requirements and workload distribution must be balanced.

------------------------------------------------------------------------

# Part 30 --- WATCH Scope

## 35. Watch Only Necessary Keys

Watching excessive keys increases the chance that unrelated changes
abort the transaction.

Keep the optimistic concurrency boundary precise.

------------------------------------------------------------------------

# Part 31 --- Version Field Pattern

## 36. Entity Version

Instead of watching many fields, maintain a version:

``` text
entity data
entity version
```

Update the version whenever authoritative state changes.

This can simplify conflict detection.

------------------------------------------------------------------------

# Part 32 --- Idempotency

## 37. Retry Safety

A transaction retry may re-run application logic.

Ensure side effects outside Redis are not accidentally repeated.

Example:

``` text
charge credit card
then retry Redis transaction
```

requires a separate idempotency strategy.

Redis transaction retry does not make external side effects safe.

------------------------------------------------------------------------

# Part 33 --- Cross-System Atomicity

## 38. Important Boundary

A Redis transaction cannot make:

``` text
Redis update
+
PostgreSQL update
+
HTTP call
```

one atomic transaction.

Cross-system consistency requires a distributed/application architecture
such as:

``` text
outbox
saga
idempotency
reconciliation
```

depending on requirements.

------------------------------------------------------------------------

# Part 34 --- Timeouts

## 39. Ambiguous Client Outcome

If a client loses the connection around `EXEC`, the application may face
uncertainty about the outcome.

Design state transitions so they can be safely verified/reconciled.

------------------------------------------------------------------------

# Part 35 --- Observability

## 40. Application Metrics

Track:

``` text
redis_transaction_total
redis_transaction_success_total
redis_transaction_conflict_total
redis_transaction_error_total
redis_transaction_retry_total
redis_transaction_retry_exhausted_total
redis_transaction_duration_seconds
```

------------------------------------------------------------------------

## 41. Contention Metrics

Useful derived metrics:

``` text
conflict rate
retries per successful update
P95 retry count
transaction success rate
```

------------------------------------------------------------------------

## 42. Redis Metrics

Correlate transaction workloads with:

``` text
CPU
latency
operations/sec
network
memory
hot keys
shard/slot distribution
```

------------------------------------------------------------------------

# Part 36 --- Hands-On Lab

## 43. Objectives

You will:

1.  run `MULTI/EXEC`;
2.  use `DISCARD`;
3.  observe runtime command errors;
4.  reproduce lost update;
5.  implement `WATCH`;
6.  create compare-and-set;
7.  generate concurrent conflicts;
8.  add bounded retries;
9.  add backoff/jitter;
10. implement Lua CAS;
11. compare approaches;
12. clean up safely.

------------------------------------------------------------------------

## 44. Prerequisites

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

# Part 37 --- MULTI/EXEC Lab

## 45. CLI

``` redis
MULTI
SET tutorial:chapter22:a 1
SET tutorial:chapter22:b 2
INCR tutorial:chapter22:counter
EXEC
```

Verify:

``` redis
GET tutorial:chapter22:a
GET tutorial:chapter22:b
GET tutorial:chapter22:counter
```

------------------------------------------------------------------------

# Part 38 --- DISCARD Lab

## 46. Queue Then Cancel

``` redis
MULTI
SET tutorial:chapter22:discard:a 1
SET tutorial:chapter22:discard:b 2
DISCARD
```

Verify:

``` redis
EXISTS tutorial:chapter22:discard:a
EXISTS tutorial:chapter22:discard:b
```

Expected:

``` text
0
0
```

assuming those keys did not exist before the lab.

------------------------------------------------------------------------

# Part 39 --- Runtime Error Lab

## 47. Wrong Type

``` redis
SET tutorial:chapter22:type string

MULTI
SET tutorial:chapter22:before ok
LPUSH tutorial:chapter22:type x
SET tutorial:chapter22:after ok
EXEC
```

Inspect all returned results.

Then verify:

``` redis
GET tutorial:chapter22:before
GET tutorial:chapter22:after
```

This demonstrates why Redis transactions should not be assumed to
provide automatic rollback of successful commands after a runtime error.

------------------------------------------------------------------------

# Part 40 --- Lost Update Lab

## 48. Unsafe Python

Create `chapter22_transactions_lab.py`:

``` python
import os
import random
import threading
import time

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

COUNTER = "tutorial:chapter22:unsafe-counter"
SAFE_COUNTER = "tutorial:chapter22:safe-counter"


def unsafe_increment(iterations):
    for _ in range(iterations):
        current = int(r.get(COUNTER) or 0)

        time.sleep(
            random.uniform(0, 0.001)
        )

        r.set(COUNTER, current + 1)


def atomic_increment(iterations):
    for _ in range(iterations):
        r.incr(SAFE_COUNTER)


def run_test(worker, key, workers=10, iterations=100):
    r.set(key, 0)

    threads = []

    for _ in range(workers):
        t = threading.Thread(
            target=worker,
            args=(iterations,),
        )
        t.start()
        threads.append(t)

    for t in threads:
        t.join()

    expected = workers * iterations
    actual = int(r.get(key))

    print("Expected:", expected)
    print("Actual  :", actual)


if __name__ == "__main__":
    print("PING:", r.ping())

    print()
    print("UNSAFE READ-MODIFY-WRITE")
    run_test(
        unsafe_increment,
        COUNTER,
    )

    print()
    print("ATOMIC INCR")
    run_test(
        atomic_increment,
        SAFE_COUNTER,
    )
```

------------------------------------------------------------------------

## 49. Run

``` bash
python chapter22_transactions_lab.py
```

Expected:

``` text
UNSAFE READ-MODIFY-WRITE
Expected: 1000
Actual  : less than 1000

ATOMIC INCR
Expected: 1000
Actual  : 1000
```

Exact unsafe result varies.

------------------------------------------------------------------------

# Part 41 --- WATCH CAS Lab

## 50. Function

Add:

``` python
VERSIONED_KEY = "tutorial:chapter22:versioned"


def compare_and_set(
    expected,
    new_value,
    max_attempts=5,
):
    for attempt in range(1, max_attempts + 1):
        try:
            with r.pipeline() as pipe:
                pipe.watch(VERSIONED_KEY)

                current = pipe.get(VERSIONED_KEY)

                if current != expected:
                    pipe.unwatch()

                    return {
                        "status": "mismatch",
                        "current": current,
                    }

                pipe.multi()
                pipe.set(
                    VERSIONED_KEY,
                    new_value,
                )
                pipe.execute()

                return {
                    "status": "updated",
                    "attempt": attempt,
                }

        except redis.WatchError:
            if attempt == max_attempts:
                return {
                    "status": "conflict-exhausted"
                }

            delay = min(
                0.005 * (2 ** (attempt - 1)),
                0.1,
            )

            delay += random.uniform(
                0,
                delay,
            )

            time.sleep(delay)

    return {
        "status": "conflict-exhausted"
    }
```

------------------------------------------------------------------------

# Part 42 --- Test CAS

## 51. Initialize

``` python
r.set(VERSIONED_KEY, "v1")

print(
    compare_and_set(
        "v1",
        "v2",
    )
)

print(
    compare_and_set(
        "v1",
        "v3",
    )
)
```

Expected:

``` text
first -> updated
second -> mismatch
```

------------------------------------------------------------------------

# Part 43 --- Conflict Injection

## 52. Concurrent Writers

Create many workers that:

``` text
WATCH
read
sleep random small delay
MULTI
write
EXEC
```

Measure:

``` text
successes
conflicts
retries
exhausted retries
```

Increase writer count to observe contention.

------------------------------------------------------------------------

# Part 44 --- Optimistic Increment Lab

## 53. WATCH-Based Increment

For learning only:

``` python
WATCH_COUNTER = "tutorial:chapter22:watch-counter"


def watch_increment(max_attempts=10):
    for attempt in range(max_attempts):
        try:
            with r.pipeline() as pipe:
                pipe.watch(WATCH_COUNTER)

                current = int(
                    pipe.get(WATCH_COUNTER) or 0
                )

                pipe.multi()
                pipe.set(
                    WATCH_COUNTER,
                    current + 1,
                )
                pipe.execute()

                return True

        except redis.WatchError:
            time.sleep(
                random.uniform(
                    0.001,
                    0.01,
                )
            )

    return False
```

Then compare this with:

``` redis
INCR
```

The built-in atomic command is simpler and normally preferable for a
counter.

------------------------------------------------------------------------

# Part 45 --- Lua CAS Lab

## 54. Script

``` python
LUA_CAS = """
local current = redis.call("GET", KEYS[1])

if current ~= ARGV[1] then
    return 0
end

redis.call("SET", KEYS[1], ARGV[2])

return 1
"""


def lua_cas(expected, new_value):
    return r.eval(
        LUA_CAS,
        1,
        VERSIONED_KEY,
        expected,
        new_value,
    )
```

Test:

``` python
r.set(VERSIONED_KEY, "v10")

print(
    lua_cas(
        "v10",
        "v11",
    )
)

print(
    lua_cas(
        "v10",
        "v12",
    )
)
```

Expected:

``` text
1
0
```

------------------------------------------------------------------------

# Part 46 --- Compare WATCH and Lua

## 55. Review

WATCH:

``` text
client reads state
client computes
optimistic conflict detection
may retry
```

Lua:

``` text
logic executes server-side
atomic script execution
fewer client round trips
must remain bounded
```

Select based on semantics and operational simplicity.

------------------------------------------------------------------------

# Part 47 --- Failure Injection

## 56. Failure 1 --- Lost Update

Run unsafe read-modify-write concurrently.

Expected:

``` text
actual count < expected
```

------------------------------------------------------------------------

## 57. Failure 2 --- WATCH Conflict

Modify the watched key from another client before `EXEC`.

Expected:

``` text
transaction conflict
```

------------------------------------------------------------------------

## 58. Failure 3 --- Retry Storm

Create high contention with immediate retry.

Observe:

``` text
conflicts
CPU
latency
retry volume
```

Then add backoff/jitter.

------------------------------------------------------------------------

## 59. Failure 4 --- Retry Exhaustion

Set a small maximum retry count under high contention.

Expected:

``` text
some operations fail cleanly
```

The application must define the user-visible behavior.

------------------------------------------------------------------------

## 60. Failure 5 --- Runtime Command Error

Include a wrong-type command inside `MULTI/EXEC`.

Verify that other valid commands are not assumed to roll back.

------------------------------------------------------------------------

## 61. Failure 6 --- Oversized Transaction

Queue a large number of commands in an isolated environment.

Observe:

``` text
latency
network
client memory
Redis processing
```

Use bounded transactions in production.

------------------------------------------------------------------------

## 62. Failure 7 --- Hot-Key Contention

Run many writers against one watched key.

Observe conflict rate.

Compare with a workload spread across many keys.

------------------------------------------------------------------------

## 63. Failure 8 --- Connection Loss Around EXEC

In a disposable environment, interrupt connectivity around transaction
execution.

Discuss how the application verifies final state before retrying
ambiguous operations.

------------------------------------------------------------------------

## 64. Failure 9 --- Cross-Slot Assumption

In a Redis Cluster-compatible lab, attempt a multi-key atomic pattern
across incompatible slots.

Observe the topology constraint.

Then redesign key placement if the atomic boundary is valid.

------------------------------------------------------------------------

## 65. Failure 10 --- External Side Effect Retry

Simulate:

``` text
external action succeeds
Redis WATCH conflict occurs
application retries entire workflow
```

Demonstrate why external side effects require independent idempotency.

------------------------------------------------------------------------

# Part 48 --- Troubleshooting

## 66. High WATCH Conflict Rate

Check:

``` text
hot key
writer concurrency
transaction duration
watched-key count
application delay between WATCH and EXEC
```

------------------------------------------------------------------------

## 67. Retry Latency High

Check:

``` text
conflict rate
max attempts
backoff
jitter
hot-key concentration
```

Do not simply increase retries indefinitely.

------------------------------------------------------------------------

## 68. Unexpected Partial State

Check whether a runtime command error occurred during `EXEC`.

Redis does not provide general rollback of previously successful
commands in that transaction.

------------------------------------------------------------------------

## 69. Transaction Never Succeeds

Check:

``` text
another process constantly modifies watched key
too many watched keys
long application work between read and EXEC
```

Reduce the conflict window.

------------------------------------------------------------------------

## 70. Duplicate External Actions

Check whether application retry logic repeats non-Redis side effects
after a transaction conflict or ambiguous connection failure.

Add end-to-end idempotency.

------------------------------------------------------------------------

## 71. Cluster Transaction Error

Check:

``` text
key slots
hash tags
client cluster support
topology
multi-key assumptions
```

------------------------------------------------------------------------

## 72. Redis Latency Increased

Check:

``` text
transaction size
command cost
large payloads
hot slots
ops/sec
```

Transactions should remain small and bounded.

------------------------------------------------------------------------

# Part 49 --- Production Runbooks

## 73. Runbook --- High Transaction Conflict

``` text
1. Measure conflict rate.
2. Identify affected key/pattern.
3. Measure writer concurrency.
4. Check hot-key concentration.
5. Measure WATCH-to-EXEC duration.
6. Reduce watched-key scope.
7. Add bounded backoff/jitter.
8. Prefer atomic built-in command if possible.
9. Evaluate Lua/server-side CAS if simpler.
10. Revalidate latency and success rate.
```

------------------------------------------------------------------------

## 74. Runbook --- Transaction Error

``` text
1. Capture EXEC results.
2. Identify queue-time vs. runtime error.
3. Determine which commands executed.
4. Verify final Redis state.
5. Stop unsafe blanket retries.
6. Correct command/type issue.
7. Reconcile state if needed.
8. Add validation/test coverage.
9. Re-run safely.
10. Confirm consistency.
```

------------------------------------------------------------------------

## 75. Runbook --- Retry Storm

``` text
1. Measure retries/sec.
2. Measure conflicts/sec.
3. Identify hot key.
4. Apply retry limit.
5. Add exponential backoff.
6. Add jitter.
7. Reduce concurrency if needed.
8. Redesign atomic operation if possible.
9. Monitor Redis latency.
10. Confirm retry volume stabilizes.
```

------------------------------------------------------------------------

## 76. Runbook --- Ambiguous EXEC Outcome

``` text
1. Do not assume success or failure.
2. Read current authoritative Redis state.
3. Compare expected version/idempotency token.
4. Determine whether operation already applied.
5. Retry only if safe.
6. Reconcile external side effects separately.
7. Record incident evidence.
8. Improve idempotency/versioning.
9. Test connection-loss scenario.
10. Validate recovery procedure.
```

------------------------------------------------------------------------

## 77. Runbook --- Cluster Atomicity Failure

``` text
1. Identify all transaction keys.
2. Determine slots.
3. Check hash tags.
4. Confirm atomicity requirement.
5. Co-locate only truly related keys.
6. Avoid creating hot slot.
7. Validate client behavior.
8. Test failover/topology changes.
9. Benchmark resulting workload.
10. Document atomic boundary.
```

------------------------------------------------------------------------

# Part 50 --- Transaction Design Template

## 78. Fields

``` text
Service:
Use case:
Keys:
Data types:
Atomicity requirement:
Can one built-in command solve it?:
Why MULTI/EXEC?:
Why WATCH?:
Why Lua?:
Expected contention:
Max writers:
WATCH-to-EXEC target:
Max retries:
Backoff:
Jitter:
Idempotent?:
External side effects?:
Cluster slots:
Hash tags:
Timeout behavior:
Ambiguous-outcome recovery:
Owner:
```

------------------------------------------------------------------------

# Part 51 --- Concurrency Test Record

## 79. Template

``` text
Environment:
Redis version:
Client/version:
Topology:
Key pattern:
Writers:
Operations/writer:

Writers | Success | Conflicts | Retries | Exhausted | P95 latency
--------|---------|-----------|---------|-----------|------------
1       | ...     | ...       | ...     | ...       | ...
5       | ...     | ...       | ...     | ...       | ...
10      | ...     | ...       | ...     | ...       | ...
50      | ...     | ...       | ...     | ...       | ...
```

Also record Redis CPU, latency, and shard/slot distribution.

------------------------------------------------------------------------

# Production Acceptance Checklist

## 80. Transaction Engineering

-   [ ] Atomicity requirement documented.
-   [ ] Built-in atomic commands considered first.
-   [ ] `MULTI/EXEC` semantics understood.
-   [ ] `DISCARD` tested.
-   [ ] Runtime error behavior tested.
-   [ ] No rollback assumption exists.
-   [ ] `WATCH` conflict behavior tested.
-   [ ] Compare-and-set tested.
-   [ ] Retry limit defined.
-   [ ] Backoff defined.
-   [ ] Jitter defined.
-   [ ] Retry exhaustion behavior documented.
-   [ ] Hot-key contention tested.
-   [ ] Transaction size bounded.
-   [ ] Large payload risk reviewed.
-   [ ] Pipeline vs. transaction behavior documented.
-   [ ] Client-library defaults verified.
-   [ ] Lua alternative reviewed where appropriate.
-   [ ] Cluster slot constraints tested.
-   [ ] Hash tags reviewed.
-   [ ] External side-effect idempotency documented.
-   [ ] Ambiguous connection outcome tested.
-   [ ] Production runbooks validated.

------------------------------------------------------------------------

# Knowledge Validation

## 81. Questions

You should be able to answer:

1.  Are individual Redis commands atomic?
2.  Why is application read-modify-write unsafe?
3.  What does `MULTI` do?
4.  What does `EXEC` do?
5.  What does `DISCARD` do?
6.  Are Redis transactions identical to relational database
    transactions?
7.  Does Redis automatically roll back successful commands after a
    runtime error?
8.  What is a queue-time error?
9.  What is a runtime transaction error?
10. What is optimistic concurrency?
11. What does `WATCH` do?
12. What is compare-and-set?
13. What causes a WATCH conflict?
14. Why is a conflict not necessarily an infrastructure failure?
15. Why must retries be bounded?
16. Why use retry jitter?
17. Why can WATCH perform poorly on a hot key?
18. Why prefer `INCR` over WATCH-based counter logic?
19. How do pipelines differ from transactions?
20. What redis-py pipeline default should be understood?
21. When can Lua be simpler than WATCH?
22. Why should transactions remain small?
23. Why do cluster slots matter?
24. What do hash tags do?
25. How can overusing one hash tag create a hotspot?
26. Why watch only necessary keys?
27. Why does retry require idempotency?
28. Can a Redis transaction make a database and HTTP call atomic?
29. What is an ambiguous EXEC outcome?
30. What must pass before transaction logic is production-ready?

------------------------------------------------------------------------

# Hands-On Acceptance Checklist

## 82. Lab Completion

-   [ ] Executed `MULTI/EXEC`.
-   [ ] Executed `DISCARD`.
-   [ ] Verified discarded keys were not created.
-   [ ] Reproduced runtime wrong-type error.
-   [ ] Verified valid transaction commands were not assumed rolled
    back.
-   [ ] Reproduced unsafe lost update.
-   [ ] Compared atomic `INCR`.
-   [ ] Implemented WATCH CAS.
-   [ ] Tested expected-value mismatch.
-   [ ] Injected WATCH conflict.
-   [ ] Added bounded retry.
-   [ ] Added exponential backoff.
-   [ ] Added jitter.
-   [ ] Tested retry exhaustion.
-   [ ] Implemented WATCH-based increment for comparison.
-   [ ] Implemented Lua CAS.
-   [ ] Compared WATCH and Lua.
-   [ ] Reviewed cluster slot requirements.
-   [ ] Completed ten failure scenarios.
-   [ ] Completed troubleshooting.
-   [ ] Reviewed five production runbooks.
-   [ ] Completed transaction design template.
-   [ ] Completed concurrency test record.
-   [ ] Completed production acceptance checklist.

------------------------------------------------------------------------

# 83. Lab Cleanup

Discover:

``` bash
redis-cli --scan --pattern 'tutorial:chapter22:*'
```

Delete only confirmed Chapter 22 training keys in bounded batches with
`UNLINK`.

Examples:

``` redis
UNLINK tutorial:chapter22:a
UNLINK tutorial:chapter22:b
UNLINK tutorial:chapter22:counter
UNLINK tutorial:chapter22:type
UNLINK tutorial:chapter22:before
UNLINK tutorial:chapter22:after
UNLINK tutorial:chapter22:unsafe-counter
UNLINK tutorial:chapter22:safe-counter
UNLINK tutorial:chapter22:versioned
UNLINK tutorial:chapter22:watch-counter
```

Do not use:

``` redis
FLUSHDB
FLUSHALL
```

against a shared or production database.

------------------------------------------------------------------------

# 84. Key Takeaways

1.  Individual Redis commands are atomic, so prefer a suitable built-in
    atomic command first.
2.  Client-side read-modify-write can lose updates.
3.  `MULTI` queues transaction commands and `EXEC` executes them under
    Redis transaction semantics.
4.  `DISCARD` cancels queued transaction commands.
5.  Redis transactions should not be treated as identical to relational
    database transactions.
6.  Runtime command errors do not imply automatic rollback of other
    successful transaction commands.
7.  `WATCH` provides optimistic concurrency control.
8.  Compare-and-set prevents writes based on stale reads.
9.  WATCH conflicts are expected under concurrent updates.
10. Retries must be bounded.
11. Backoff and jitter reduce retry synchronization.
12. High-contention hot keys may be poor candidates for optimistic retry
    loops.
13. Built-in atomic operations are often simpler than transactions.
14. Pipelining optimizes round trips; transactions solve atomic
    grouping/concurrency requirements.
15. Client-library defaults must be verified.
16. Lua/server-side logic can provide compact atomic compare-and-update
    behavior.
17. Transactions should remain small, bounded, and fast.
18. Sharded deployments require compatible key placement for multi-key
    atomic patterns.
19. Redis transactions do not provide atomicity across external systems.
20. Production readiness requires conflict testing, retry safety,
    idempotency, observability, topology validation, and runbooks.

------------------------------------------------------------------------

# 85. References

Validate exact semantics against the Redis, Redis Enterprise, and
client-library versions deployed.

Recommended official Redis documentation areas:

-   Redis transactions
-   `MULTI`
-   `EXEC`
-   `DISCARD`
-   `WATCH`
-   `UNWATCH`
-   `INCR`
-   `HINCRBY`
-   `SET`
-   Redis pipelining
-   Redis programmability / Lua
-   Redis Cluster
-   Redis Cluster hash tags
-   redis-py pipelines and transactions
-   Redis Enterprise monitoring

Transaction design depends on contention, data model, client behavior,
topology, external side effects, and failure semantics. Test with the
actual production client and deployment architecture.

------------------------------------------------------------------------

# Next Chapter

**Chapter 23 --- Redis Lua Scripting & Server-Side Atomic Logic**

Chapter 23 will cover:

-   Lua execution model
-   `EVAL`
-   `EVALSHA`
-   script caching
-   `KEYS` and `ARGV`
-   atomic server-side logic
-   compare-and-set
-   safe lock release
-   bounded scripts
-   blocking risk
-   script errors
-   determinism/version considerations
-   cluster key placement
-   observability
-   failure injection
-   troubleshooting
-   production runbooks
-   acceptance validation
