# Chapter 07 --- Hash Slots, Key Distribution & Sharding Internals

**Status:** Canonical\
**Track:** Redis Enterprise / Redis Software Production Engineering\
**Level:** Foundation → Production Engineering\
**Audience:** Redis Administrators, SREs, DBREs, Platform Engineers,
Developers\
**Lab type:** Key-distribution analysis, hash-tag experiments, skew
simulation, multi-key design review, resharding planning,
troubleshooting, and production acceptance

------------------------------------------------------------------------

# 1. Objective

Sharding is how a Redis database distributes keys and workload across
multiple primary shards.

From an application perspective, the database still appears as one
logical Redis service:

``` text
Application
    |
    v
Database Endpoint
    |
    v
Routing Layer
    |
    +----> Primary Shard 1
    +----> Primary Shard 2
    +----> Primary Shard 3
    +----> Primary Shard 4
```

But key names and workload patterns influence how traffic reaches those
shards.

This chapter teaches the operational model behind key distribution so
that application teams and SREs can recognize:

``` text
healthy distribution
hot keys
hot partitions
intentional co-location
accidental co-location
multi-key constraints
shard imbalance
resharding requirements
```

By the end, you should be able to:

-   Explain why Redis Enterprise shards databases.
-   Explain deterministic key distribution.
-   Understand Redis hash-slot concepts.
-   Explain CRC16-based slot selection in Redis Cluster-compatible
    hashing.
-   Explain hash tags using `{...}`.
-   Understand why hash tags intentionally co-locate related keys.
-   Recognize hash-tag abuse.
-   Distinguish a hot key from a hot partition.
-   Distinguish key-count balance from workload balance.
-   Review multi-key operations for sharded deployments.
-   Analyze key-distribution problems.
-   Understand why more shards do not fix every hotspot.
-   Understand resharding at an operational level.
-   Build a shard-distribution baseline.
-   Troubleshoot shard skew safely.

------------------------------------------------------------------------

# Part 1 --- Why Sharding Exists

## 2. Single-Shard Database

Conceptually:

``` text
Database
    |
    v
Primary Shard 1
```

All keys and commands for that database are handled by one primary
shard.

This can be appropriate for smaller workloads.

However, one shard has finite:

``` text
CPU
memory
command-processing capacity
network capacity
```

------------------------------------------------------------------------

## 3. Multi-Shard Database

A larger database can use multiple primary shards:

``` text
Database
|
+-- Primary Shard 1
+-- Primary Shard 2
+-- Primary Shard 3
+-- Primary Shard 4
```

The objective is to distribute:

``` text
keys
memory
requests
CPU work
```

across multiple shard processes.

------------------------------------------------------------------------

## 4. Sharding Is Not Replication

Sharding:

``` text
splits the dataset
```

Replication:

``` text
creates redundant copies
```

Example:

``` text
P1 -> R1
P2 -> R2
P3 -> R3
P4 -> R4
```

There are four primary partitions plus four replica copies.

Do not confuse:

``` text
more shards
```

with:

``` text
more replicas
```

They solve different problems.

------------------------------------------------------------------------

# Part 2 --- Deterministic Key Placement

## 5. Why Placement Must Be Deterministic

Given:

``` text
user:1001
```

the routing layer needs a deterministic way to determine the key's
partition.

The same key must consistently map to the same logical hash location
unless topology changes are handled by the platform.

Conceptually:

``` text
key
 |
 v
hash function
 |
 v
logical slot
 |
 v
shard
```

------------------------------------------------------------------------

# Part 3 --- Redis Hash Slots

## 6. Redis Cluster-Compatible Slot Model

Redis Cluster-compatible hashing uses:

``` text
16384 hash slots
```

commonly numbered:

``` text
0 through 16383
```

A key is mapped conceptually using:

``` text
CRC16(key) mod 16384
```

The resulting slot is assigned to a shard/partition.

Redis Enterprise abstracts much of this routing from applications, but
the slot model is still important when reasoning about clustered key
behavior and hash tags.

Always validate exact behavior against the Redis Enterprise / Redis
Software database type and version you operate.

------------------------------------------------------------------------

## 7. Logical Example

Suppose:

``` text
user:1001 -> slot 4210
user:1002 -> slot 9101
user:1003 -> slot 12200
```

And assume:

``` text
Shard 1 -> slots A
Shard 2 -> slots B
Shard 3 -> slots C
```

The routing layer uses slot ownership to route requests.

The exact slot-to-shard assignment is platform-managed.

------------------------------------------------------------------------

# Part 4 --- Hash Tags

## 8. Hash Tag Syntax

A key can contain a hash tag:

``` text
{customer:1001}
```

Example keys:

``` text
profile:{customer:1001}
cart:{customer:1001}
session:{customer:1001}
```

The content inside the relevant braces is used for compatible slot
hashing.

These keys therefore map to the same hash slot.

------------------------------------------------------------------------

## 9. Why Hash Tags Exist

Hash tags can intentionally co-locate related keys.

Without tags:

``` text
profile:1001
cart:1001
session:1001
```

may map to different slots.

With:

``` text
profile:{1001}
cart:{1001}
session:{1001}
```

they share the same hash tag:

``` text
1001
```

and therefore the same logical slot.

------------------------------------------------------------------------

## 10. Multi-Key Motivation

Some multi-key operations require or benefit from keys being in the same
slot depending on deployment mode, client, proxy behavior, and command.

Hash tags give the application a way to control co-location
deliberately.

However:

> Hash tags are a data-modeling tool, not a default naming convention.

------------------------------------------------------------------------

# Part 5 --- Hash-Tag Risk

## 11. Accidental Concentration

Bad pattern:

``` text
user:{all}:1
user:{all}:2
user:{all}:3
user:{all}:4
...
```

Every key uses:

``` text
{all}
```

Therefore every key hashes to the same slot.

A database with many shards can still concentrate this workload into one
partition.

------------------------------------------------------------------------

## 12. Better Distribution

For customer-local co-location:

``` text
profile:{customer:1001}
cart:{customer:1001}

profile:{customer:1002}
cart:{customer:1002}

profile:{customer:1003}
cart:{customer:1003}
```

Each customer can map independently while related keys for the same
customer remain co-located.

This can provide:

``` text
locality within customer
+
distribution across customers
```

------------------------------------------------------------------------

# Part 6 --- Hot Keys

## 13. What Is a Hot Key?

A hot key receives disproportionate traffic.

Example:

``` text
configuration:global
```

receives:

``` text
200,000 GET/sec
```

while most keys receive:

``` text
10 GET/sec
```

The shard containing the hot key can become CPU or network constrained.

------------------------------------------------------------------------

## 14. More Shards Do Not Split One Key

Suppose:

``` text
Database = 8 shards
```

One key receives:

``` text
90% of all operations
```

That key still maps to one logical partition.

Increasing to:

``` text
16 shards
```

does not divide one key into sixteen keys.

Application/data-model redesign may be required.

------------------------------------------------------------------------

# Part 7 --- Hot Partitions

## 15. Hot Key vs Hot Partition

Hot key:

``` text
one/few keys dominate traffic
```

Hot partition:

``` text
many keys mapping to the same shard collectively dominate traffic
```

A hot partition can be caused by:

``` text
hash-tag design
tenant concentration
workload skew
application partitioning
large collections
```

------------------------------------------------------------------------

## 16. Tenant Skew

Suppose:

``` text
Tenant A = 70% traffic
Tenant B = 10%
Tenant C = 10%
Tenant D = 10%
```

Keys:

``` text
cache:{tenant-A}:...
```

If all Tenant A keys intentionally share one tag, one logical slot can
become extremely hot.

Hash-tag design must consider tenant size.

------------------------------------------------------------------------

# Part 8 --- Key Count vs Workload Balance

## 17. Equal Key Counts Can Still Be Imbalanced

Example:

``` text
Shard 1 = 1,000,000 keys
Shard 2 = 1,000,000 keys
Shard 3 = 1,000,000 keys
Shard 4 = 1,000,000 keys
```

Looks balanced.

But:

``` text
Shard 1 = 80,000 ops/sec
Shard 2 = 10,000 ops/sec
Shard 3 = 10,000 ops/sec
Shard 4 = 10,000 ops/sec
```

Workload is not balanced.

------------------------------------------------------------------------

## 18. Equal Ops Can Still Hide Memory Skew

Example:

``` text
Shard 1 = 20 GB
Shard 2 = 5 GB
Shard 3 = 5 GB
Shard 4 = 5 GB
```

Possible causes:

``` text
large keys
uneven value size
large collections
tenant skew
```

Distribution analysis must consider:

``` text
key count
memory
operations
CPU
network
latency
```

------------------------------------------------------------------------

# Part 9 --- Multi-Key Commands

## 19. Why Multi-Key Operations Need Review

Example:

``` redis
MGET key1 key2 key3
```

In a sharded deployment, keys may map to different slots/shards.

Behavior can depend on:

``` text
Redis Enterprise architecture
database type
proxy behavior
client
command
product version
```

Do not assume standalone Redis behavior is sufficient to validate a
production multi-shard design.

------------------------------------------------------------------------

## 20. Same-Slot Design

Keys:

``` text
profile:{1001}
cart:{1001}
preferences:{1001}
```

share one tag.

This can make same-slot operations possible where required.

But the tradeoff is intentional concentration of related keys.

Ask:

``` text
How many keys per tag?
How much traffic per tag?
How much memory per tag?
Can one customer become huge?
```

------------------------------------------------------------------------

# Part 10 --- Key Naming and Distribution

## 21. Good Key Naming

Chapter 03 introduced:

``` text
<service>:<entity>:<id>:<attribute>
```

Example:

``` text
checkout:cart:1001
```

For intentional hash-tag design:

``` text
checkout:cart:{1001}
checkout:cart-items:{1001}
```

Only introduce braces when co-location is an intentional architectural
requirement.

------------------------------------------------------------------------

## 22. Avoid Low-Cardinality Tags

Potentially dangerous:

``` text
{prod}
{cache}
{users}
{global}
```

If thousands or millions of keys share one tag, they intentionally share
one slot.

Prefer high-cardinality distribution dimensions where appropriate:

``` text
{customer:1001}
{customer:1002}
{customer:1003}
```

------------------------------------------------------------------------

# Part 11 --- Distribution Baseline

## 23. What to Measure

For each shard capture:

``` text
key count
memory
ops/sec
CPU
network
latency
large keys
hot keys
```

Example:

  Shard     Keys   Memory   Ops/sec   CPU
  ------- ------ -------- --------- -----
  P1        1.1M    10 GB       12K   30%
  P2        1.0M     9 GB       11K   28%
  P3        1.0M    10 GB       45K   88%
  P4        1.1M    10 GB       13K   32%

P3 needs investigation.

------------------------------------------------------------------------

# Part 12 --- Resharding

## 24. What Is Resharding?

At a high level, resharding changes how a database's data/workload is
distributed across primary shards.

Example:

``` text
Before:
2 primary shards

After:
4 primary shards
```

The platform must redistribute ownership/data appropriately.

------------------------------------------------------------------------

## 25. Resharding Is an Operational Event

Potential impacts include:

``` text
data movement
network traffic
CPU
memory
background work
temporary latency
replica work
```

Plan and observe resharding.

Do not treat it as:

``` text
change shard count and forget
```

------------------------------------------------------------------------

## 26. When Resharding Can Help

Potential reasons:

``` text
dataset growth
sustained shard CPU pressure
throughput growth
memory distribution
capacity expansion
```

But first rule out:

``` text
single hot key
bad hash tags
large key
expensive commands
application retry storm
```

------------------------------------------------------------------------

## 27. When Resharding May Not Solve the Problem

Scenario:

``` text
one key = 60% traffic
```

Adding shards does not split that key.

Scenario:

``` text
all keys use {global}
```

Adding shards does not improve distribution until the key design
changes.

------------------------------------------------------------------------

# Hands-On Lab

## 28. Lab Safety

Use:

``` text
development
test
training
staging
```

Keys use:

``` text
tutorial:chapter07:
```

Do not change production shard counts as part of this lab.

------------------------------------------------------------------------

## 29. Lab 1 --- Create Distributed Keys

Create:

``` redis
SET tutorial:chapter07:user:1001 A EX 600
SET tutorial:chapter07:user:1002 B EX 600
SET tutorial:chapter07:user:1003 C EX 600
SET tutorial:chapter07:user:1004 D EX 600
SET tutorial:chapter07:user:1005 E EX 600
```

These keys have distinct names and no intentional hash tag.

------------------------------------------------------------------------

## 30. Lab 2 --- Create Co-Located Keys

``` redis
SET tutorial:chapter07:profile:{1001} profile EX 600
SET tutorial:chapter07:cart:{1001} cart EX 600
SET tutorial:chapter07:session:{1001} session EX 600
```

All use:

``` text
{1001}
```

Conceptually they map to the same slot.

------------------------------------------------------------------------

## 31. Lab 3 --- Multiple Tags

``` redis
SET tutorial:chapter07:profile:{1001} A EX 600
SET tutorial:chapter07:profile:{1002} B EX 600
SET tutorial:chapter07:profile:{1003} C EX 600
SET tutorial:chapter07:profile:{1004} D EX 600
```

These use different tags.

The intent is distribution across independent tag values.

------------------------------------------------------------------------

# Part 13 --- Slot Calculation Lab

## 32. CRC16 Demonstration

The slot model can be demonstrated with a small Python script.

Create:

``` python
def crc16(data: bytes):
    crc = 0
    for byte in data:
        crc ^= byte << 8
        for _ in range(8):
            if crc & 0x8000:
                crc = ((crc << 1) ^ 0x1021) & 0xFFFF
            else:
                crc = (crc << 1) & 0xFFFF
    return crc

def hashtag(key: str):
    start = key.find("{")
    if start != -1:
        end = key.find("}", start + 1)
        if end != -1 and end > start + 1:
            return key[start + 1:end]
    return key

def slot(key: str):
    tag = hashtag(key)
    return crc16(tag.encode()) % 16384

keys = [
    "tutorial:chapter07:profile:{1001}",
    "tutorial:chapter07:cart:{1001}",
    "tutorial:chapter07:session:{1001}",
    "tutorial:chapter07:profile:{1002}",
]

for key in keys:
    print(key, hashtag(key), slot(key))
```

Expected observation:

``` text
the three {1001} keys produce the same slot
the {1002} key generally produces a different slot
```

This script is educational.

For production behavior, validate using supported Redis/client tooling
and your deployed product architecture.

------------------------------------------------------------------------

## 33. Lab 5 --- Poor Hash-Tag Design

Create only a small safe sample:

``` redis
SET tutorial:chapter07:{global}:user:1 A EX 600
SET tutorial:chapter07:{global}:user:2 B EX 600
SET tutorial:chapter07:{global}:user:3 C EX 600
```

All intentionally use:

``` text
{global}
```

Conceptual result:

``` text
same slot
```

Question:

What happens if an application creates:

``` text
50 million keys
```

with the same tag?

Answer:

The design defeats normal distribution for those tagged keys.

------------------------------------------------------------------------

# Part 14 --- Distribution Inspection

## 34. Inspect Database Topology

``` bash
rladmin info db
rladmin info shard
```

Record:

``` text
database
primary shard count
replica state
shard IDs
node placement
```

------------------------------------------------------------------------

## 35. Build Shard Metrics Table

Using available Redis Enterprise monitoring:

  Shard   Node     Memory   Ops/sec   CPU   Latency
  ------- ------ -------- --------- ----- ---------
                                          
                                          

Look for outliers.

------------------------------------------------------------------------

## 36. Ratio Analysis

Example:

``` text
Highest shard CPU = 90%
Lowest shard CPU = 25%
```

Simple ratio:

``` text
90 / 25 = 3.6x
```

A large ratio is a signal to investigate.

Do not create a universal alert threshold solely from this tutorial;
baseline your workload.

------------------------------------------------------------------------

# Part 15 --- Hot-Key Investigation

## 37. Symptoms

Potential hot-key symptoms:

``` text
one shard high CPU
one shard high network
database latency spikes
overall database CPU moderate
high command rate against a narrow key set
```

------------------------------------------------------------------------

## 38. Investigation

Determine:

``` text
which shard is hot?
which commands dominate?
which key namespace dominates?
is one key extremely active?
are hash tags concentrating traffic?
is one tenant dominant?
```

Use supported observability and safe diagnostic tooling.

Avoid introducing heavy diagnostic scans during an incident.

------------------------------------------------------------------------

# Part 16 --- Big Key vs Hot Key

## 39. Big Key

A big key consumes unusually large memory or contains many elements.

Example:

``` text
one Hash with 5 million fields
```

------------------------------------------------------------------------

## 40. Hot Key

A hot key receives unusually high request volume.

Example:

``` text
one 100-byte String read 100,000 times/sec
```

A key can be:

``` text
big but cold
small but hot
big and hot
small and cold
```

These require different remediation.

------------------------------------------------------------------------

# Failure Injection

## 41. Failure 1 --- Global Hash Tag

Scenario:

``` text
cache:{global}:1
cache:{global}:2
...
cache:{global}:10000000
```

Expected architectural result:

``` text
intentional slot concentration
```

Remediation:

``` text
redesign tag dimension
```

not merely:

``` text
add shards
```

------------------------------------------------------------------------

## 42. Failure 2 --- Hot Tenant

Scenario:

``` text
tenant:{A}:*
```

Tenant A represents:

``` text
75% traffic
```

Even though other tenants distribute independently, Tenant A's
intentionally co-located workload may become a hotspot.

Possible design review:

``` text
Does all Tenant A data need same-slot semantics?
Can the tenant be partitioned further?
Can high-volume objects use a different model?
```

------------------------------------------------------------------------

## 43. Failure 3 --- Hot Global Configuration Key

Scenario:

``` text
config:global
```

receives enormous read traffic.

Potential remediation patterns depend on application requirements and
can include:

``` text
application-local caching
request reduction
data-model changes
read distribution strategies supported by architecture
```

Do not assume shard-count increase solves it.

------------------------------------------------------------------------

## 44. Failure 4 --- Large Multi-Key Request

Scenario:

``` redis
MGET 100000-keys...
```

Even if supported, analyze:

``` text
request size
cross-shard routing
response size
CPU
network
client memory
latency
```

Batching may be safer.

------------------------------------------------------------------------

## 45. Failure 5 --- Resharding During Existing Saturation

Scenario:

``` text
Shard CPU = 95%
Network = 90%
Database latency already elevated
```

Immediately resharding may add background work and data movement.

First:

``` text
stabilize workload
identify hotspot
review headroom
create change plan
```

------------------------------------------------------------------------

# Troubleshooting

## 46. One Shard High CPU

Check:

``` text
ops/sec per shard
hot keys
command mix
key distribution
hash tags
large keys
tenant traffic
```

Do not stop at node CPU.

------------------------------------------------------------------------

## 47. One Shard High Memory

Check:

``` text
key count
value sizes
big keys
collections
tenant concentration
hash tags
TTL behavior
```

High memory does not necessarily mean high request rate.

------------------------------------------------------------------------

## 48. One Shard High Network

Check:

``` text
large GET values
large range queries
hot reads
large multi-key responses
replication/recovery activity
```

------------------------------------------------------------------------

## 49. Database Slow After Adding Nodes

Check:

``` text
Did database shard count change?
Was data redistributed?
Is the bottleneck a hot key?
Is one shard still saturated?
Did application traffic change?
```

Adding infrastructure does not automatically alter application key
distribution.

------------------------------------------------------------------------

## 50. Database Slow After Adding Shards

Check:

``` text
Did resharding complete?
Is traffic concentrated by hash tags?
Is there a single hot key?
Are commands expensive?
Is the client bottlenecked?
Is network saturated?
```

More shards cannot repair every application design issue.

------------------------------------------------------------------------

# Part 17 --- Sharding Design Review

## 51. Questions for Developers

Before approving key design:

``` text
Are hash tags used?
Why?
What is the tag cardinality?
What is maximum traffic per tag?
What is maximum memory per tag?
Can one tenant become disproportionately large?
Are multi-key operations required?
Can multi-key operations be redesigned?
What happens when shard count increases?
```

------------------------------------------------------------------------

## 52. Hash-Tag Approval Template

``` text
Key pattern:
Hash tag:
Reason:
Required commands:
Expected keys/tag:
Expected memory/tag:
Expected ops/sec/tag:
Largest tenant/tag:
Failure mode:
Scaling plan:
Owner:
```

If the team cannot explain why braces are present in the key name, the
hash-tag design should be reviewed.

------------------------------------------------------------------------

# Part 18 --- Resharding Change Runbook

## 53. Pre-Change

Capture:

``` text
database
current primary shards
target primary shards
dataset size
memory
ops/sec
CPU per shard
network
latency
replication state
node capacity
cluster headroom
hot-key analysis
hash-tag analysis
rollback/contingency
```

------------------------------------------------------------------------

## 54. Validate the Reason

Acceptable evidence might include:

``` text
sustained distributed CPU pressure
dataset growth across shards
capacity model requiring more partitions
```

Poor justification:

``` text
Redis is slow, so add shards
```

------------------------------------------------------------------------

## 55. During Change

Monitor:

``` text
database state
shard state
data movement
node CPU
node memory
network
latency
errors
replication
application health
```

Use the supported Redis Enterprise procedure for your release.

------------------------------------------------------------------------

## 56. Post-Change

Validate:

``` text
target shard count
healthy shard state
healthy replicas
new placement
workload distribution
memory distribution
latency
application errors
endpoint connectivity
```

Then rebuild the topology baseline.

------------------------------------------------------------------------

# Part 19 --- Incident Runbooks

## 57. Runbook --- Hot Key / Hot Partition

``` text
1. Record incident time.
2. Identify affected database.
3. Identify hot shard.
4. Compare shard CPU.
5. Compare shard ops/sec.
6. Compare network.
7. Identify dominant command.
8. Identify candidate hot keys/namespaces.
9. Review hash-tag patterns.
10. Review tenant distribution.
11. Determine hot key vs hot partition.
12. Mitigate application amplification/retries if present.
13. Redesign key/access pattern when required.
14. Consider resharding only if workload can distribute.
15. Validate post-remediation shard balance.
```

------------------------------------------------------------------------

## 58. Runbook --- Distribution Imbalance

``` text
1. Capture primary shard count.
2. Capture key count per shard where available.
3. Capture memory per shard.
4. Capture ops/sec per shard.
5. Capture CPU per shard.
6. Capture network per shard.
7. Identify outliers.
8. Check big keys.
9. Check hot keys.
10. Check hash tags.
11. Check tenant skew.
12. Check command mix.
13. Determine data skew vs workload skew.
14. Choose application, data-model, or shard-level remediation.
15. Re-baseline after change.
```

------------------------------------------------------------------------

## 59. Runbook --- Multi-Key Failure

``` text
1. Capture exact command.
2. Capture all involved key patterns.
3. Determine database deployment type.
4. Determine key slots/tags where relevant.
5. Determine whether keys are co-located.
6. Check client behavior.
7. Check Redis Enterprise support for the command.
8. Reproduce in non-production.
9. Redesign keys or operation if required.
10. Add automated integration test for the sharded deployment.
```

------------------------------------------------------------------------

# Part 20 --- Production Acceptance

## 60. Sharding Acceptance Checklist

-   [ ] Primary shard count documented.
-   [ ] Replication documented.
-   [ ] Key naming standard documented.
-   [ ] Hash-tag use documented.
-   [ ] Hash-tag cardinality reviewed.
-   [ ] Maximum traffic per tag reviewed.
-   [ ] Maximum memory per tag reviewed.
-   [ ] Multi-key commands inventoried.
-   [ ] Multi-key behavior tested against target deployment.
-   [ ] Per-shard CPU monitoring available.
-   [ ] Per-shard memory monitoring available.
-   [ ] Per-shard operations monitoring available.
-   [ ] Per-shard network monitoring available.
-   [ ] Hot-key investigation procedure available.
-   [ ] Big-key investigation procedure available.
-   [ ] Tenant-skew risk reviewed.
-   [ ] Resharding runbook documented.
-   [ ] Cluster headroom reviewed.
-   [ ] Distribution baseline stored.
-   [ ] Post-resharding validation defined.

------------------------------------------------------------------------

# Knowledge Validation

## 61. Questions

You should be able to answer:

1.  Why does Redis use sharding?
2.  What is the difference between sharding and replication?
3.  What is deterministic key placement?
4.  How many hash slots are used by the Redis Cluster-compatible slot
    model?
5.  What is the conceptual slot calculation?
6.  What is a Redis hash tag?
7.  Which portion of `cart:{customer:1001}` is used as the hash tag?
8.  Why would an application intentionally co-locate keys?
9.  Why can `{global}` be dangerous?
10. Why can low-cardinality tags create hotspots?
11. What is a hot key?
12. What is a hot partition?
13. Why does adding shards not split a single hot key?
14. Why can equal key counts still produce unequal CPU?
15. Why can equal operations still produce unequal memory?
16. Why must multi-key commands be tested against the target deployment?
17. What is resharding?
18. Why is resharding an operational event?
19. When can resharding help?
20. When may resharding fail to solve latency?
21. What is the difference between a big key and hot key?
22. Why should hash-tag use require design review?
23. What should be monitored during resharding?
24. Why should topology be re-baselined after resharding?
25. Why should workload distribution be measured at shard level?

------------------------------------------------------------------------

# Hands-On Acceptance Checklist

## 62. Lab Completion

-   [ ] Created normal distributed key patterns.
-   [ ] Created same-tag keys.
-   [ ] Created multiple independent tag values.
-   [ ] Calculated hash slots with the educational script.
-   [ ] Demonstrated `{global}` concentration.
-   [ ] Inspected database shard topology.
-   [ ] Built shard metrics table.
-   [ ] Compared shard CPU.
-   [ ] Compared shard memory.
-   [ ] Compared shard operations.
-   [ ] Reviewed hot-key symptoms.
-   [ ] Distinguished big key vs hot key.
-   [ ] Completed global-tag failure exercise.
-   [ ] Completed hot-tenant exercise.
-   [ ] Completed hot-global-key exercise.
-   [ ] Reviewed large multi-key request risk.
-   [ ] Reviewed resharding-under-load risk.
-   [ ] Completed hash-tag design review.
-   [ ] Reviewed resharding runbook.
-   [ ] Reviewed incident runbooks.

------------------------------------------------------------------------

# Lab Cleanup

## 63. Cleanup Only Chapter Keys

Use incremental scan to identify lab keys:

``` redis
SCAN 0 MATCH 'tutorial:chapter07:*' COUNT 100
```

Delete only known tutorial keys using:

``` redis
UNLINK <exact-key>
```

Do not use:

``` redis
FLUSHDB
FLUSHALL
```

------------------------------------------------------------------------

# 64. Key Takeaways

1.  Sharding distributes a database across multiple primary shards.
2.  Replication creates redundant copies and is different from sharding.
3.  Redis uses deterministic key hashing to select logical placement.
4.  Redis Cluster-compatible hashing uses 16,384 logical slots.
5.  Hash tags intentionally force related keys into the same slot.
6.  Hash tags should be used only for a clear architectural reason.
7.  Low-cardinality tags can defeat normal distribution.
8.  A hot key can saturate one shard even in a large cluster.
9.  A hot partition can result from many concentrated keys.
10. Equal key counts do not guarantee equal workload.
11. Equal operations do not guarantee equal memory usage.
12. Multi-key operations require explicit validation in sharded
    deployments.
13. Adding nodes does not automatically change database key
    distribution.
14. Adding shards does not split one hot key.
15. Resharding should follow workload evidence and capacity planning.
16. Shard-level metrics are essential for production troubleshooting.
17. Key naming is part of capacity and performance engineering.

------------------------------------------------------------------------

# 65. References

Validate hashing, slot behavior, hash tags, supported multi-key
behavior, resharding procedures, and database architecture against
documentation for the exact Redis and Redis Enterprise / Redis Software
release deployed.

Key documentation areas:

-   Redis Cluster specification
-   hash slots
-   hash tags
-   clustered multi-key behavior
-   Redis Enterprise sharding
-   database shards
-   proxy architecture
-   resharding
-   hot-key troubleshooting
-   capacity planning

------------------------------------------------------------------------

# Next Chapter

**Chapter 08 --- Replication Architecture & Primary/Replica Behavior**

Chapter 08 will cover:

-   replication architecture
-   primary and replica lifecycle
-   replication lag
-   synchronization
-   failover
-   data-loss windows
-   consistency implications
-   replica placement
-   degraded redundancy
-   replication monitoring
-   failure injection
-   production replication runbooks
-   HA acceptance testing
