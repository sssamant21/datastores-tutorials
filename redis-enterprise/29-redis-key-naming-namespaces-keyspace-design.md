# Chapter 29 --- Redis Key Naming, Namespaces & Keyspace Design

**Status:** Canonical\
**Track:** Redis Enterprise / Redis Software Production Engineering\
**Part:** Part 2 --- Caching & Application Engineering\
**Level:** Intermediate → Production Redis Keyspace Engineering\
**Audience:** Developers, SREs, DBREs, Platform Engineers, Redis
Administrators\
**Lab type:** Key naming conventions, service/environment/tenant
namespaces, key-length measurement, versioned keys, TTL ownership, Redis
Cluster hash tags, slot-placement analysis, hot-slot prevention, safe
`SCAN`, bounded cleanup, migration, failure injection, observability,
troubleshooting, runbooks, and production acceptance

------------------------------------------------------------------------

# 1. Objective

Redis keys are part of the application's data model and operational
interface.

A key name affects:

``` text
ownership
discoverability
memory
cluster placement
migration
cleanup
incident response
multi-tenant isolation
observability
```

Poor keyspace design can create operational risk even when Redis itself
is healthy.

By the end, you should be able to:

-   Define consistent key naming conventions.
-   Build service and environment namespaces.
-   Include tenant/resource identity safely.
-   Understand key-length tradeoffs.
-   Version key formats.
-   Assign key ownership.
-   Define TTL ownership.
-   Use Redis Cluster hash tags intentionally.
-   Prevent accidental hot slots.
-   Discover keys safely with `SCAN`.
-   Avoid dangerous production cleanup patterns.
-   Migrate key formats safely.
-   Design operationally discoverable keyspaces.
-   Observe keyspace growth and distribution.
-   Inject keyspace failures.
-   Troubleshoot production incidents.
-   Build runbooks and acceptance criteria.

------------------------------------------------------------------------

# 2. Core Production Principle

A Redis key should answer:

``` text
Who owns this?
What does it represent?
Which version is it?
How long should it live?
How is it distributed?
How can it be found and removed safely?
```

A keyspace should be designed before millions of keys exist.

------------------------------------------------------------------------

# Part 1 --- Naming Convention

## 3. Basic Pattern

A common pattern is:

``` text
<service>:<domain>:<version>:<identifier>
```

Example:

``` text
patient360:patient:v2:12345
```

The exact convention should be standardized across the organization.

------------------------------------------------------------------------

# Part 2 --- Environment Namespace

## 4. Isolation

If environments share infrastructure, environment identity may be
included:

``` text
prod:patient360:patient:v2:12345
staging:patient360:patient:v2:12345
```

Prefer stronger infrastructure/database isolation where required.

A naming prefix is not a security boundary.

------------------------------------------------------------------------

# Part 3 --- Service Namespace

## 5. Ownership

Example:

``` text
billing:invoice:v1:9001
search:result:v3:abc123
identity:session:v2:xyz
```

A clear service namespace helps identify the owner during incidents.

------------------------------------------------------------------------

# Part 4 --- Domain / Object Type

## 6. Semantic Grouping

Include the object or function:

``` text
orders:cart:v1:1001
orders:checkout-lock:v1:1001
orders:rate-limit:v1:user:2001
```

Do not place unrelated semantics under indistinguishable key patterns.

------------------------------------------------------------------------

# Part 5 --- Tenant Namespace

## 7. Multi-Tenant Systems

Example:

``` text
analytics:tenant:1001:report:v2:5001
```

Tenant identity can help:

``` text
ownership
quota
cleanup
incident analysis
```

But it does not replace authorization.

------------------------------------------------------------------------

# Part 6 --- User-Supplied Identifiers

## 8. Normalize Safely

Raw user input may contain:

``` text
spaces
colons
wildcards
very long strings
PII
```

Define encoding/normalization rules.

Do not expose sensitive information unnecessarily in key names.

------------------------------------------------------------------------

# Part 7 --- Sensitive Data

## 9. Key Names Are Operational Metadata

Avoid embedding:

``` text
passwords
access tokens
secrets
full sensitive records
```

Key names can appear in:

``` text
logs
debugging
monitoring
administrative tools
```

Use opaque identifiers where appropriate.

------------------------------------------------------------------------

# Part 8 --- Key Length

## 10. Tradeoff

Readable:

``` text
patient360:patient-demographics:v2:123456789
```

may be easier to operate than:

``` text
p:p:v2:123456789
```

but longer keys consume more memory.

Optimize only after measuring.

------------------------------------------------------------------------

# Part 9 --- Key-Length Memory

## 11. Fleet Effect

A difference of tens of bytes per key can matter when there are:

``` text
hundreds of millions of keys
```

Estimate:

``` text
extra key bytes
×
key count
```

and validate with `MEMORY USAGE`.

------------------------------------------------------------------------

# Part 10 --- Over-Abbreviation

## 12. Operational Cost

Keys such as:

``` text
a:b:c:123
```

may save bytes but make incidents harder.

Balance:

``` text
human readability
memory
standardization
```

------------------------------------------------------------------------

# Part 11 --- Versioned Keys

## 13. Schema Evolution

Example:

``` text
catalog:product:v1:1001
catalog:product:v2:1001
```

Versioning supports:

``` text
parallel migration
rollback
gradual cutover
```

------------------------------------------------------------------------

# Part 12 --- Version Position

## 14. Consistency

Choose one convention:

``` text
service:type:v2:id
```

and use it consistently.

Inconsistent placement makes discovery and cleanup harder.

------------------------------------------------------------------------

# Part 13 --- Cache Key Inputs

## 15. Deterministic Identity

A cache key should represent all inputs that affect the result.

If response depends on:

``` text
patient ID
locale
permissions
date range
```

but the key contains only patient ID, incorrect cache sharing may occur.

------------------------------------------------------------------------

# Part 14 --- Canonicalization

## 16. Equivalent Inputs

Normalize equivalent input before key generation.

Examples:

``` text
case
parameter order
whitespace
date format
```

Otherwise semantically identical requests may generate different cache
keys and reduce hit ratio.

------------------------------------------------------------------------

# Part 15 --- Hashed Key Components

## 17. Long Query Parameters

For large query/filter inputs:

``` text
canonicalize input
hash canonical representation
use digest in key
```

Example:

``` text
search:result:v3:sha256:<digest>
```

Use a collision-resistant strategy appropriate to the correctness
requirement.

------------------------------------------------------------------------

# Part 16 --- Human-Readable Prefix + Digest

## 18. Operational Pattern

Example:

``` text
search:patient:v3:<digest>
```

This keeps:

``` text
ownership/type visible
```

while bounding variable key length.

------------------------------------------------------------------------

# Part 17 --- TTL Ownership

## 19. Every Ephemeral Pattern Needs Policy

Document:

``` text
who sets TTL
expected TTL
whether TTL is refreshed
whether persistent keys are allowed
```

A cache key accidentally created without TTL can become permanent memory
growth.

------------------------------------------------------------------------

# Part 18 --- Persistent Keys

## 20. Intentional Only

If a pattern is intended to persist:

``` text
TTL = none
```

should be explicit.

Do not treat missing TTL as harmless.

------------------------------------------------------------------------

# Part 19 --- TTL Validation

## 21. Sampling

For an expected-cache pattern:

``` redis
TTL service:object:v1:123
```

or:

``` redis
PTTL service:object:v1:123
```

Unexpected:

``` text
-1
```

means no expiration.

Investigate according to the data model.

------------------------------------------------------------------------

# Part 20 --- Namespace Ownership Registry

## 22. Recommended Fields

Maintain:

``` text
key pattern
owning service
team
purpose
data type
TTL
estimated count
estimated size
version
cluster placement requirement
cleanup method
```

This is valuable during incidents and migrations.

------------------------------------------------------------------------

# Part 21 --- Redis Cluster Slotting

## 23. Concept

In Redis Cluster-style partitioning, keys map to hash slots.

The slot determines placement.

Applications should not assume visually similar prefixes automatically
colocate.

------------------------------------------------------------------------

# Part 22 --- Hash Tags

## 24. Syntax

A substring inside:

``` text
{...}
```

can control the hash-slot component.

Example:

``` text
cart:{tenant-1001}:items
cart:{tenant-1001}:metadata
```

These keys can be intentionally colocated.

------------------------------------------------------------------------

# Part 23 --- Why Co-Locate

## 25. Use Case

Co-location may be needed for operations requiring related keys on the
same slot/shard.

Examples depend on:

``` text
multi-key commands
transactions
Lua/functions
client/topology behavior
```

Validate exact deployment semantics.

------------------------------------------------------------------------

# Part 24 --- Hot-Slot Risk

## 26. Overuse

If every key uses:

``` text
{global}
```

all keys can map to one slot.

This defeats distribution and can create:

``` text
hot shard
CPU skew
network skew
latency
```

------------------------------------------------------------------------

# Part 25 --- Tenant Hash Tag

## 27. Tradeoff

Pattern:

``` text
service:{tenant}:object:id
```

can colocate all one tenant's keys.

For small tenants this may be fine.

For one huge tenant, it may create a hot slot.

Choose placement based on access semantics and tenant size.

------------------------------------------------------------------------

# Part 26 --- Bucketed Hash Tags

## 28. Distribution Option

If atomic co-location is not required for an entire tenant, independent
keys can be spread.

Concept:

``` text
tenant bucket = hash(object_id) % N
```

Then:

``` text
service:{tenant-1001-b03}:object:123
```

Only use this if it preserves required operation semantics.

------------------------------------------------------------------------

# Part 27 --- Keyspace Discovery

## 29. Use `SCAN`

Production-safe discovery pattern:

``` redis
SCAN 0 MATCH service:object:v2:* COUNT 100
```

Continue with returned cursor until:

``` text
cursor = 0
```

`COUNT` is a hint, not an exact result count.

------------------------------------------------------------------------

# Part 28 --- Avoid `KEYS *`

## 30. Production Risk

Do not use broad:

``` redis
KEYS *
```

against large/shared production keyspaces.

`KEYS` can perform expensive synchronous keyspace scanning.

Use `SCAN` for incremental discovery.

------------------------------------------------------------------------

# Part 29 --- `SCAN` Semantics

## 31. Important

During active mutations, a full `SCAN` iteration does not behave like a
transactional snapshot.

Applications should tolerate:

``` text
duplicates
key changes during iteration
```

Do not build correctness assumptions that require a frozen keyspace.

------------------------------------------------------------------------

# Part 30 --- Bounded Cleanup

## 32. Pattern

``` text
SCAN
 -> collect bounded batch
 -> UNLINK
 -> repeat
```

This avoids collecting millions of keys in application memory.

------------------------------------------------------------------------

# Part 31 --- `UNLINK`

## 33. Deletion

Where supported and appropriate:

``` redis
UNLINK key1 key2 key3
```

removes keys from the keyspace and performs memory reclamation
asynchronously.

Deletion impact still needs monitoring.

------------------------------------------------------------------------

# Part 32 --- Avoid Flush Commands

## 34. Shared / Production Safety

Do not use:

``` redis
FLUSHDB
FLUSHALL
```

for application-pattern cleanup in shared or production Redis.

Use precise pattern ownership and bounded deletion.

------------------------------------------------------------------------

# Part 33 --- Cleanup Rate

## 35. Throttle

Deleting millions of keys can affect:

``` text
CPU
memory reclamation
persistence
replication
network
```

Use a controlled rate and observe Redis.

------------------------------------------------------------------------

# Part 34 --- Pattern Collision

## 36. Dangerous Prefix

Suppose cleanup intends:

``` text
service:cache:*
```

but another workload also uses that prefix.

Cleanup can delete unrelated data.

Namespace ownership must be unambiguous.

------------------------------------------------------------------------

# Part 35 --- Environment Collision

## 37. Example

If staging and production accidentally use the same Redis database and
identical keys:

``` text
service:cache:123
```

one environment can overwrite another.

Prefer infrastructure isolation; where shared by design, namespaces must
be explicit.

------------------------------------------------------------------------

# Part 36 --- Tenant Collision

## 38. Missing Tenant ID

Bad:

``` text
profile:user:1001
```

if user IDs are only unique within a tenant.

Better:

``` text
profile:tenant:500:user:1001
```

Correct identity dimensions belong in the key.

------------------------------------------------------------------------

# Part 37 --- Key Type Ownership

## 39. Stable Type

A pattern should have an expected Redis type:

``` text
string
hash
set
sorted set
list
stream
```

Changing a key from string to hash without versioning can create
`WRONGTYPE` failures during mixed deployments.

------------------------------------------------------------------------

# Part 38 --- Type Migration

## 40. Safer Pattern

Instead of changing:

``` text
customer:v1:123
```

in place from string to hash, introduce:

``` text
customer:v2:123
```

and migrate deliberately.

------------------------------------------------------------------------

# Part 39 --- Keyspace Notifications

## 41. Not a Generic Inventory System

Redis keyspace notifications can be useful for some event-driven use
cases but are configuration-dependent and should not be treated as a
durable audit log.

Validate delivery semantics before relying on them.

------------------------------------------------------------------------

# Part 40 --- Key Count

## 42. Observe Growth

Track:

``` text
total keys
keys by major namespace where feasible
expiring vs. persistent
creation rate
expiration rate
deletion rate
```

Avoid metrics with one label per raw key.

------------------------------------------------------------------------

# Part 41 --- Cardinality

## 43. Estimate Before Launch

For a key pattern:

``` text
tenants
×
users/tenant
×
objects/user
×
versions
```

Estimate peak cardinality.

------------------------------------------------------------------------

# Part 42 --- Keyspace and Memory

## 44. Capacity

Total memory includes:

``` text
keys
values
Redis object metadata
allocator overhead
data-structure overhead
```

Short values with very long keys can make key overhead significant.

------------------------------------------------------------------------

# Part 43 --- Keyspace and Backups

## 45. Operational Impact

More keys and more bytes affect:

``` text
persistence
backup
replication
recovery
migration
```

Keyspace design is also recovery design.

------------------------------------------------------------------------

# Part 44 --- Observability

## 46. Recommended Metrics

Track where practical:

``` text
key_count
key_creation_rate
expired_keys_rate
evicted_keys_rate
persistent_key_fraction
key_size_distribution
value_size_distribution
namespace_growth
```

------------------------------------------------------------------------

## 47. Cluster Distribution

Track:

``` text
keys/shard
memory/shard
ops/sec/shard
CPU/shard
network/shard
```

A balanced key count does not guarantee balanced traffic.

------------------------------------------------------------------------

# Part 45 --- Hands-On Lab

## 48. Objectives

You will:

1.  create a naming convention;
2.  create environment/service namespaces;
3.  create tenant-aware keys;
4.  compare key lengths;
5.  measure `MEMORY USAGE`;
6.  create versioned keys;
7.  validate TTL ownership;
8.  test hash tags;
9.  inspect cluster slots where supported;
10. use `SCAN`;
11. perform bounded cleanup;
12. simulate migration.

------------------------------------------------------------------------

## 49. Prerequisites

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

# Part 46 --- Create Lab Keys

## 50. Examples

``` redis
SET tutorial:chapter29:prod:orders:cart:v1:1001 "cart-data" EX 3600
SET tutorial:chapter29:prod:orders:cart:v1:1002 "cart-data" EX 3600
SET tutorial:chapter29:staging:orders:cart:v1:1001 "cart-data" EX 3600
```

Observe how environment identity changes the key.

------------------------------------------------------------------------

# Part 47 --- Tenant Keys

## 51. Examples

``` redis
SET tutorial:chapter29:prod:orders:tenant:500:cart:v1:1001 "cart-data" EX 3600
SET tutorial:chapter29:prod:orders:tenant:600:cart:v1:1001 "cart-data" EX 3600
```

The same cart ID can safely exist under different tenant identities when
that matches the domain model.

------------------------------------------------------------------------

# Part 48 --- Key Length Lab

## 52. Compare

Create:

``` redis
SET tutorial:chapter29:k:1 "x"
SET tutorial:chapter29:production:patient360:patient-demographics:v2:123456789 "x"
```

Measure:

``` redis
MEMORY USAGE tutorial:chapter29:k:1
MEMORY USAGE tutorial:chapter29:production:patient360:patient-demographics:v2:123456789
```

Repeat across many representative keys before making naming decisions
based solely on memory.

------------------------------------------------------------------------

# Part 49 --- TTL Audit

## 53. Commands

``` redis
TTL tutorial:chapter29:prod:orders:cart:v1:1001
```

Create an intentionally persistent lab key:

``` redis
SET tutorial:chapter29:ttl-missing "test"
```

Check:

``` redis
TTL tutorial:chapter29:ttl-missing
```

Expected:

``` text
-1
```

Use this to demonstrate TTL policy auditing.

------------------------------------------------------------------------

# Part 50 --- Version Migration Lab

## 54. v1 and v2

``` redis
SET tutorial:chapter29:customer:v1:1001 '{"name":"Example"}' EX 3600
SET tutorial:chapter29:customer:v2:1001 '{"name":"Example","status":"active"}' EX 3600
```

A staged reader can prefer v2 and fall back to v1.

------------------------------------------------------------------------

# Part 51 --- Hash-Tag Lab

## 55. Keys

``` text
tutorial:chapter29:cart:{tenant-500}:items
tutorial:chapter29:cart:{tenant-500}:metadata
tutorial:chapter29:cart:{tenant-600}:items
```

Where Redis Cluster commands are supported, inspect slots:

``` redis
CLUSTER KEYSLOT tutorial:chapter29:cart:{tenant-500}:items
CLUSTER KEYSLOT tutorial:chapter29:cart:{tenant-500}:metadata
CLUSTER KEYSLOT tutorial:chapter29:cart:{tenant-600}:items
```

The first two should map to the same slot in Redis Cluster semantics.

If the deployment does not expose `CLUSTER KEYSLOT`, validate placement
using the supported Redis Enterprise/client tooling for that topology.

------------------------------------------------------------------------

# Part 52 --- Hot-Tag Lab

## 56. Demonstration

Generate many keys with:

``` text
{global}
```

in a disposable environment.

Example:

``` text
tutorial:chapter29:item:{global}:1
tutorial:chapter29:item:{global}:2
...
```

Observe that hash tags can intentionally concentrate placement.

Do not use a universal hash tag in production merely for naming
consistency.

------------------------------------------------------------------------

# Part 53 --- Safe `SCAN` Lab

## 57. redis-cli

``` bash
redis-cli --scan --pattern 'tutorial:chapter29:*'
```

Or cursor form:

``` redis
SCAN 0 MATCH tutorial:chapter29:* COUNT 100
```

Continue until the returned cursor is `0`.

------------------------------------------------------------------------

# Part 54 --- Python Discovery Lab

## 58. Create `chapter29_keyspace_lab.py`

``` python
import os

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

PATTERN = "tutorial:chapter29:*"


def discover():
    count = 0

    for key in r.scan_iter(
        match=PATTERN,
        count=100,
    ):
        count += 1
        print(key)

    print(
        "discovered:",
        count,
    )


def ttl_audit():
    missing_ttl = []

    for key in r.scan_iter(
        match="tutorial:chapter29:*",
        count=100,
    ):
        ttl = r.ttl(key)

        if ttl == -1:
            missing_ttl.append(key)

    print(
        "persistent keys:",
        len(missing_ttl),
    )

    for key in missing_ttl[:20]:
        print(
            "NO TTL:",
            key,
        )


if __name__ == "__main__":
    print(
        "PING:",
        r.ping(),
    )

    discover()
    ttl_audit()
```

------------------------------------------------------------------------

# Part 55 --- Bounded Cleanup Script

## 59. Safe Lab Cleanup

``` python
def cleanup(
    batch_size=100,
):
    batch = []

    for key in r.scan_iter(
        match="tutorial:chapter29:*",
        count=100,
    ):
        batch.append(key)

        if len(batch) >= batch_size:
            r.unlink(*batch)
            batch.clear()

    if batch:
        r.unlink(*batch)
```

Only run this against the isolated Chapter 29 namespace.

------------------------------------------------------------------------

# Part 56 --- Migration Script Concept

## 60. v1 to v2

``` python
def read_customer(customer_id):
    v2 = (
        f"tutorial:chapter29:"
        f"customer:v2:{customer_id}"
    )

    v1 = (
        f"tutorial:chapter29:"
        f"customer:v1:{customer_id}"
    )

    value = r.get(v2)

    if value is not None:
        return value

    old = r.get(v1)

    if old is None:
        return None

    # Transform using application schema logic.
    new_value = old

    r.set(
        v2,
        new_value,
        ex=3600,
    )

    return new_value
```

For production, preserve the correct remaining TTL and schema
transformation semantics rather than blindly assigning a new lifetime.

------------------------------------------------------------------------

# Part 57 --- Failure Injection

## 61. Failure 1 --- Missing Environment Namespace

Create identical keys from two simulated environments.

Observe overwrite/collision risk.

------------------------------------------------------------------------

## 62. Failure 2 --- Missing Tenant Identity

Use the same object ID for two tenants without tenant identity in the
key.

Observe data collision.

------------------------------------------------------------------------

## 63. Failure 3 --- Missing TTL

Create thousands of disposable cache keys without expiration.

Observe persistent key count.

Then correct TTL ownership.

------------------------------------------------------------------------

## 64. Failure 4 --- Wrong Type During Migration

Use the same key name first as a string and then attempt hash
operations.

Observe `WRONGTYPE`.

Use a versioned key pattern instead.

------------------------------------------------------------------------

## 65. Failure 5 --- Overly Long Keys

Generate a representative high-cardinality dataset with verbose keys in
a disposable environment.

Compare memory with a reasonable standardized form.

Do not sacrifice operability for tiny savings without evidence.

------------------------------------------------------------------------

## 66. Failure 6 --- Ambiguous Cleanup Prefix

Create:

``` text
tutorial:chapter29:cache-a:*
tutorial:chapter29:cache-admin:*
```

Review how an imprecise prefix could target both.

Cleanup patterns must be exact.

------------------------------------------------------------------------

## 67. Failure 7 --- Hot Hash Tag

Generate many active keys using one hash tag.

Observe slot/shard concentration where tooling supports it.

------------------------------------------------------------------------

## 68. Failure 8 --- Migration Doubles Keyspace

Populate both v1 and v2.

Observe:

``` text
key count
memory
```

Define old-version retirement.

------------------------------------------------------------------------

## 69. Failure 9 --- `SCAN` During Mutation

Run key creation/deletion while scanning.

Observe why scan-based inventory must tolerate concurrent changes and
possible duplicate observations.

------------------------------------------------------------------------

## 70. Failure 10 --- Cleanup Too Fast

In a disposable environment, delete a large training namespace
aggressively, then compare with bounded deletion.

Observe Redis resource behavior.

Never perform destructive load testing in production.

------------------------------------------------------------------------

# Part 58 --- Troubleshooting

## 71. Key Count Growing

Check:

``` text
namespace
creation rate
TTL coverage
expiration rate
new application release
migration versions
```

------------------------------------------------------------------------

## 72. Memory Growing but Value Sizes Stable

Check:

``` text
key count
key length
duplicate versions
persistent keys
data-structure overhead
```

------------------------------------------------------------------------

## 73. `WRONGTYPE` Errors

Check:

``` text
key naming collision
mixed application versions
in-place data-type migration
manual writes
```

------------------------------------------------------------------------

## 74. Cross-Slot Error

Check:

``` text
keys involved
hash tags
slot placement
client operation
```

Do not add a universal hash tag as a quick workaround.

------------------------------------------------------------------------

## 75. One Shard Hot

Check:

``` text
hot keys
hash tags
tenant concentration
ops/sec/shard
network/shard
CPU/shard
```

Balanced memory does not guarantee balanced traffic.

------------------------------------------------------------------------

## 76. Unexpected Persistent Keys

Audit:

``` text
TTL
writer code
failed initialization path
migration path
manual operations
```

------------------------------------------------------------------------

## 77. Cleanup Deleted Wrong Keys

Immediately:

``` text
stop cleanup job
identify exact pattern
assess authoritative source/recovery
preserve evidence
```

Do not continue destructive automation while investigating.

------------------------------------------------------------------------

## 78. Old Version Never Disappears

Check:

``` text
old writers still active
fallback repopulates old keys
TTL too long
persistent old keys
migration incomplete
```

------------------------------------------------------------------------

# Part 59 --- Production Runbooks

## 79. Runbook --- Unexpected Keyspace Growth

``` text
1. Measure total key growth.
2. Identify growing namespace.
3. Identify owning service.
4. Check TTL coverage.
5. Check release/migration changes.
6. Estimate memory runway.
7. Stop runaway creation if needed.
8. Correct TTL/key lifecycle.
9. Clean only confirmed keys in bounded batches.
10. Verify growth stops.
```

------------------------------------------------------------------------

## 80. Runbook --- Hot Slot / Shard

``` text
1. Identify hot shard.
2. Identify hot keys/patterns.
3. Inspect hash tags.
4. Identify tenant/resource skew.
5. Confirm atomic co-location requirements.
6. Remove unnecessary co-location in new version.
7. Migrate gradually.
8. Load-test distribution.
9. Monitor per-shard CPU/network/P99.
10. Document placement rules.
```

------------------------------------------------------------------------

## 81. Runbook --- Wrong Key Cleanup

``` text
1. Stop cleanup immediately.
2. Preserve command/job details.
3. Identify deleted namespace.
4. Determine Redis role: cache or authoritative.
5. Rebuild derived cache from source if safe.
6. Restore authoritative data using approved recovery if required.
7. Disable ambiguous cleanup pattern.
8. Add dry-run inventory.
9. Add bounded deletion safeguards.
10. Review ownership convention.
```

------------------------------------------------------------------------

## 82. Runbook --- Key Version Migration

``` text
1. Define v1/v2 patterns.
2. Deploy readers compatible with both.
3. Begin v2 writes.
4. Measure fallback.
5. Bound migration traffic.
6. Verify v2 correctness.
7. Stop v1 writers.
8. Allow v1 TTL retirement or controlled cleanup.
9. Verify v1 count reaches target.
10. Remove fallback after validation.
```

------------------------------------------------------------------------

## 83. Runbook --- Missing TTL

``` text
1. Identify affected key pattern.
2. Confirm intended lifecycle.
3. Measure persistent-key count.
4. Identify writer path.
5. Fix TTL creation atomically where needed.
6. Decide safe TTL for existing keys.
7. Apply remediation in bounded batches.
8. Monitor expiration/load.
9. Confirm new keys have TTL.
10. Add TTL audit alert/report.
```

------------------------------------------------------------------------

# Part 60 --- Keyspace Design Template

## 84. Fields

``` text
Service:
Environment:
Domain/object:
Key pattern:
Example key:
Owner/team:
Redis data type:
Identifier fields:
Tenant field:
Version:
TTL:
TTL refresh:
Persistent allowed:
Expected key count:
Average key bytes:
Average value bytes:
Hash tag:
Co-location requirement:
Expected ops/sec:
Hot-key risk:
Hot-slot risk:
Migration strategy:
Discovery pattern:
Cleanup method:
Metrics:
```

------------------------------------------------------------------------

# Part 61 --- Namespace Registry Example

## 85. Table

  -----------------------------------------------------------------------------------------
  Pattern                   Owner      Type      TTL       Version       Expected Cleanup
                                                                            count 
  ------------------------- ---------- --------- --------- --------- ------------ ---------
  `orders:cart:v1:*`        Orders     String    1h        v1                500k SCAN +
                                                                                  UNLINK

  `identity:session:v2:*`   Identity   Hash      30m       v2                  2M SCAN +
                                                                                  UNLINK

  `catalog:product:v3:*`    Catalog    String    6h        v3                  1M TTL /
                                                                                  bounded
                                                                                  cleanup
  -----------------------------------------------------------------------------------------

Use environment-specific values from the real deployment.

------------------------------------------------------------------------

# Part 62 --- Cleanup Safety Checklist

## 86. Before Deletion

Confirm:

-   exact Redis database;
-   exact environment;
-   exact namespace;
-   owning service;
-   Redis role;
-   pattern count;
-   sample keys;
-   TTL state;
-   backup/rebuild path;
-   deletion rate;
-   monitoring;
-   rollback/recovery plan.

Perform a dry-run discovery before deletion.

------------------------------------------------------------------------

# Production Acceptance Checklist

## 87. Keyspace Engineering

-   [ ] Naming convention documented.
-   [ ] Service ownership visible.
-   [ ] Environment strategy documented.
-   [ ] Tenant identity included where required.
-   [ ] Sensitive data excluded from keys.
-   [ ] Variable inputs canonicalized.
-   [ ] Long variable inputs hashed where appropriate.
-   [ ] Key-length tradeoff measured.
-   [ ] Key versioning strategy defined.
-   [ ] Redis data type per pattern documented.
-   [ ] TTL ownership documented.
-   [ ] Persistent-key policy documented.
-   [ ] TTL audit tested.
-   [ ] Expected cardinality calculated.
-   [ ] Memory impact estimated.
-   [ ] Hash-tag use documented.
-   [ ] Co-location requirements validated.
-   [ ] Hot-slot risk tested.
-   [ ] `SCAN` used for discovery.
-   [ ] `KEYS *` avoided operationally.
-   [ ] Bounded cleanup implemented.
-   [ ] `FLUSHDB`/`FLUSHALL` excluded from application cleanup.
-   [ ] Migration tested.
-   [ ] Old-version retirement defined.
-   [ ] Namespace observability available.
-   [ ] Production runbooks validated.

------------------------------------------------------------------------

# Knowledge Validation

## 88. Questions

You should be able to answer:

1.  Why are Redis key names part of the data model?
2.  What should a naming convention communicate?
3.  Why can environment prefixes help?
4.  Why are prefixes not a security boundary?
5.  Why include service ownership?
6.  Why include tenant identity when IDs are tenant-local?
7.  Why avoid sensitive data in keys?
8.  What is the tradeoff of long key names?
9.  Why can over-abbreviation hurt operations?
10. Why version keys?
11. Why must cache keys include all result-affecting inputs?
12. What is canonicalization?
13. Why hash large query inputs?
14. What is TTL ownership?
15. What does TTL `-1` mean?
16. Why maintain a namespace registry?
17. What is a Redis Cluster hash slot?
18. What does a hash tag do?
19. Why can hash-tag overuse create hot slots?
20. Why might tenant-level co-location be risky?
21. Why use `SCAN` instead of broad `KEYS` in production?
22. Is `SCAN` a transactional snapshot?
23. Why use bounded cleanup?
24. What does `UNLINK` provide?
25. Why avoid `FLUSHDB`/`FLUSHALL` for application cleanup?
26. Why can in-place type migration cause `WRONGTYPE`?
27. Why monitor persistent-key fraction?
28. Why can balanced key counts still produce shard imbalance?
29. Why can migrations temporarily increase key count/memory?
30. What must pass before a keyspace design is production-ready?

------------------------------------------------------------------------

# Hands-On Acceptance Checklist

## 89. Lab Completion

-   [ ] Created environment-aware keys.
-   [ ] Created service/domain namespaces.
-   [ ] Created tenant-aware keys.
-   [ ] Compared key lengths.
-   [ ] Measured `MEMORY USAGE`.
-   [ ] Audited TTLs.
-   [ ] Created an intentional missing-TTL case.
-   [ ] Created v1/v2 keys.
-   [ ] Tested hash-tag examples.
-   [ ] Reviewed slot placement where supported.
-   [ ] Demonstrated hot-tag risk.
-   [ ] Used `SCAN`.
-   [ ] Created Python keyspace discovery.
-   [ ] Created TTL audit.
-   [ ] Created bounded cleanup.
-   [ ] Reviewed migration logic.
-   [ ] Tested missing environment identity.
-   [ ] Tested missing tenant identity.
-   [ ] Tested missing TTL.
-   [ ] Tested `WRONGTYPE`.
-   [ ] Tested ambiguous cleanup prefix.
-   [ ] Tested migration keyspace growth.
-   [ ] Reviewed `SCAN` under mutation.
-   [ ] Completed ten failure scenarios.
-   [ ] Completed troubleshooting.
-   [ ] Reviewed five production runbooks.
-   [ ] Completed keyspace design template.
-   [ ] Completed cleanup safety checklist.
-   [ ] Completed production acceptance checklist.

------------------------------------------------------------------------

# 90. Lab Cleanup

First perform a dry run:

``` bash
redis-cli --scan --pattern 'tutorial:chapter29:*'
```

Review the returned keys.

Then delete only confirmed Chapter 29 keys in bounded batches with
`UNLINK`.

Do not use:

``` redis
KEYS tutorial:chapter29:*
FLUSHDB
FLUSHALL
```

against a shared or production database.

For production cleanup, record:

``` text
pattern
estimated count
owner approval
start time
batch size
deletion rate
Redis CPU
memory
latency
replication/persistence impact
```

------------------------------------------------------------------------

# 91. Key Takeaways

1.  Redis key names are part of application architecture and operations.
2.  Namespaces should make ownership and purpose understandable.
3.  Environment prefixes help avoid collisions but are not security
    isolation.
4.  Tenant identity must be included when required for uniqueness and
    ownership.
5.  Sensitive information should not be exposed unnecessarily in key
    names.
6.  Key length affects memory at large cardinality, but readability has
    operational value.
7.  Versioned keys make schema/type migrations safer.
8.  Cache keys must represent every input that affects the cached
    result.
9.  Canonicalization prevents duplicate cache entries for equivalent
    requests.
10. TTL ownership should be explicit for every ephemeral namespace.
11. Persistent cache keys should be intentional, not accidental.
12. Hash tags are placement tools, not decorative naming syntax.
13. Overusing one hash tag can create a hot slot and shard.
14. Tenant-level co-location should be reviewed for large or hot
    tenants.
15. Use `SCAN` for incremental production discovery.
16. `SCAN` is not a transactional keyspace snapshot.
17. Use bounded `UNLINK` cleanup for owned namespaces where appropriate.
18. Never use broad flush commands as normal application cleanup.
19. Track key count, TTL coverage, namespace growth, and per-shard
    distribution.
20. Production keyspace design must include naming, ownership,
    lifecycle, placement, migration, discovery, cleanup, and recovery.

------------------------------------------------------------------------

# 92. References

Validate exact keyspace, expiration, cluster, deletion, and monitoring
behavior against the Redis and Redis Enterprise versions deployed.

Recommended official Redis documentation areas:

-   `SCAN`
-   `KEYS`
-   `TTL`
-   `PTTL`
-   `EXPIRE`
-   `UNLINK`
-   `DEL`
-   `MEMORY USAGE`
-   Redis keyspace
-   Redis Cluster
-   Redis Cluster hash slots
-   Redis Cluster hash tags
-   Redis keyspace notifications
-   Redis memory optimization
-   Redis Enterprise monitoring

Key naming is not merely style. At production scale, keyspace design
determines how safely teams can understand, distribute, migrate, audit,
and remove Redis data.

------------------------------------------------------------------------

# Next Chapter

**Chapter 30 --- Redis Multi-Tenancy, Isolation & Noisy-Neighbor
Engineering**

Chapter 30 will cover:

-   tenant isolation models
-   shared vs. dedicated databases
-   namespace isolation
-   security boundaries
-   per-tenant quotas
-   rate limiting
-   memory fairness
-   hot tenants
-   noisy-neighbor detection
-   shard skew
-   tenant-aware observability
-   tenant migrations
-   blast-radius reduction
-   failure injection
-   troubleshooting
-   production runbooks
-   acceptance validation
