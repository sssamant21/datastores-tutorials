# Chapter 52 --- Redis Enterprise Data Migration, Import/Export & Cutover Engineering

**Status:** Canonical\
**Track:** Redis Enterprise / Redis Software Production Engineering\
**Part:** Part 10 --- Migration, Data Services & Advanced Capabilities\
**Level:** Advanced → Production Migration Engineering\
**Audience:** SREs, DBREs, Platform Engineers, Redis Administrators,
Application Owners, Migration Engineers\
**Lab type:** Discovery, compatibility, sizing, offline/online
migration, TTL preservation, validation, cutover, rollback, failure
injection, runbooks, and acceptance

------------------------------------------------------------------------

# 1. Objective

A production Redis migration is not simply copying keys. It must
preserve application behavior while controlling data loss, downtime,
capacity risk, security risk, and rollback complexity.

``` text
discover -> classify -> compatibility -> capacity/network sizing
-> migration method -> initial copy -> change handling
-> validation -> cutover -> stabilization -> source retirement
```

By the end, you should be able to inventory source/target environments,
select a migration strategy, estimate transfer duration, preserve data
types and TTL semantics, validate migrated data, execute controlled
cutover/rollback, troubleshoot failures, and decommission the source
safely.

# 2. Core Production Principle

A copy is not a successful migration until the application uses the
target, required data and TTL behavior are correct, performance/capacity
are acceptable, writes are safe, rollback risk is understood, and the
old source can be retired.

------------------------------------------------------------------------

# Part 1 --- Discovery & Classification

## 3. Migration Drivers

Examples include cluster replacement, Redis/version modernization, cloud
or region migration, Kubernetes migration, capacity redesign, database
split/consolidation, security redesign, Active-Active adoption, or
end-of-life infrastructure.

## 4. Scope

Record:

``` text
source cluster/database
target cluster/database
environment
applications
key count
dataset size
peak workload
migration window
downtime allowance
RPO/RTO
owners
```

## 5. Source-of-Truth Classification

Classify the Redis workload:

``` text
rebuildable cache
session/state
rate-limit state
Streams/queues
durable application state
derived data
mixed workload
```

A rebuildable cache may be safer to repopulate than to copy.

## 6. Consumer Inventory

Find services, pods, VMs, workers, batch jobs, scheduled jobs, scripts,
monitoring, backup, automation, CI/CD, and support tools. Unknown
consumers create cutover failures.

------------------------------------------------------------------------

# Part 2 --- Source & Target Inventory

## 7. Source

Capture version, database configuration, endpoint, memory, shards,
replication, persistence, eviction, TLS/authentication,
modules/features, backup, key count, ops/sec, connections, and network.

## 8. Target

Capture the same information before migration. Equal nominal memory does
not prove equal usable capacity.

## 9. Compatibility Matrix

  Area               Source   Target   Compatible?   Action
  ------------------ -------- -------- ------------- --------
  Redis version                                      
  Data types                                         
  Modules/features                                   
  Persistence                                        
  Eviction                                           
  TLS/auth                                           
  Clients                                            
  Commands                                           

## 10. Version Compatibility

Validate exact source/target releases, supported migration mechanisms,
commands, modules, security behavior, and client compatibility against
official documentation.

------------------------------------------------------------------------

# Part 3 --- Data Semantics

## 11. Data Types

Inventory strings, hashes, lists, sets, sorted sets, Streams,
JSON/document data, and Search/index capabilities where used.

## 12. TTL Distribution

Classify persistent, short-, medium-, and long-TTL keys. A migration can
accidentally remove, reset, extend, or prematurely expire TTLs.

## 13. Remaining TTL

If a source key has 300 seconds remaining and copying takes 240 seconds,
assigning a fresh 300-second TTL at the target changes business
behavior. Preserve remaining TTL semantics where required.

## 14. Streams

Review entries, consumer groups, last-delivered IDs, pending entries,
consumers, and retention. Copying entries alone may not reproduce all
operational state.

## 15. Search / Index Metadata

Inventory index definitions, schema, prefixes, field types, options, and
indexing state. Copying underlying data does not necessarily recreate
target-side index configuration.

------------------------------------------------------------------------

# Part 4 --- Connectivity & Security

## 16. Migration Identity

Define source identity, target identity, least privilege, secret
storage, credential lifetime, and auditability.

## 17. TLS

Validate CA trust, hostname, certificate chain, and expiry. Never
disable TLS verification as a migration workaround.

## 18. Network Path

Pre-test DNS, routing, firewalls/security groups, NetworkPolicy,
latency, packet loss, and bandwidth.

------------------------------------------------------------------------

# Part 5 --- Migration Sizing

## 19. Dataset

Measure logical data, Redis memory, key count, largest key families, and
growth.

## 20. Transfer Estimate

``` text
migration time ≈ bytes to transfer / effective throughput
```

This is only a starting point. Small-key overhead, TLS, CPU, target
writes, retries, persistence, and validation matter.

## 21. Small-Key Effect

A 100 GB database with hundreds of millions of tiny keys can migrate
much more slowly than 100 GB stored in fewer large keys.

## 22. Target Ingestion Capacity

Migration competes for CPU, memory, network, connections, replication,
persistence, and storage.

## 23. Source Impact

Monitor source P99, CPU, network, connections, replication,
persistence/storage, and application errors. Define throttling and stop
conditions.

------------------------------------------------------------------------

# Part 6 --- Migration Strategies

## 24. Offline

``` text
stop writes -> final state -> copy/import -> validate -> switch
```

Simpler consistency model, but requires downtime.

## 25. Online

``` text
writes continue -> initial copy -> capture/replay changes
-> catch up -> validate -> cutover
```

Lower downtime, greater consistency complexity.

## 26. Dual Write Caution

Naive source+target writes can partially succeed, time out ambiguously,
reorder, or duplicate under retries. Do not introduce dual write
casually.

## 27. Change Capture

Use product-supported migration/replication, application-mediated
capture, or an approved event/replay mechanism appropriate to the exact
platform.

## 28. Rebuildable Cache

A cache may be migrated by provisioning the target, warming selected
keys, switching traffic, and allowing safe repopulation---provided the
source system is protected from a miss storm.

## 29. Migration Waves

Where possible, migrate by service, tenant, prefix, database, region, or
traffic percentage.

## 30. Canary

Move a representative reversible subset first and validate correctness,
latency, errors, and capacity.

------------------------------------------------------------------------

# Part 7 --- Redis Command Awareness

## 31. Safe Enumeration

Do not use `KEYS *` for large production migration discovery. Prefer
supported migration tooling and bounded `SCAN` where appropriate.

## 32. DUMP / RESTORE

Redis `DUMP` and `RESTORE` can support controlled key-level exercises,
but are not automatically the correct large-scale Redis Enterprise
migration solution. Validate compatibility, binary handling, TTL,
throughput, and topology behavior.

## 33. MIGRATE

Redis provides `MIGRATE` in supported contexts. Confirm exact Redis
Enterprise support and operational implications before designing around
it.

------------------------------------------------------------------------

# Part 8 --- Hands-On Lab

## 34. Synthetic Source Keys

``` bash
redis-cli SET tutorial:chapter52:string:1 "migration-test" EX 600
redis-cli HSET tutorial:chapter52:hash:1 name "lab" version "1"
redis-cli SADD tutorial:chapter52:set:1 a b c
redis-cli ZADD tutorial:chapter52:zset:1 10 a 20 b
```

## 35. TTL

``` bash
redis-cli TTL tutorial:chapter52:string:1
```

Record the remaining TTL.

## 36. Binary Export Awareness

``` bash
redis-cli DUMP tutorial:chapter52:string:1
```

Binary output is expected. Real automation should use a client/library
that handles binary payloads safely.

## 37. Restore Principle

For disposable lab keys, test restore behavior while preserving the
appropriate remaining TTL. Do not blindly reset the original full TTL.

------------------------------------------------------------------------

# Part 9 --- Validation

## 38. Inventory Validation

Compare key count, memory, key families, types, and TTL distribution.

## 39. Representative Samples

Validate type, value/cardinality, and TTL for important key families.

## 40. Application Validation

Run application-level reads and writes against the target.

## 41. Business Validation

Where appropriate, validate meaningful outcomes such as session loading,
cache behavior, rate limiting, and Stream consumer recovery.

## 42. Bounded Collection Checks

Examples:

``` bash
redis-cli HLEN tutorial:chapter52:hash:1
redis-cli SCARD tutorial:chapter52:set:1
redis-cli ZCARD tutorial:chapter52:zset:1
```

Avoid retrieving enormous collections merely for validation.

## 43. Stream Validation

Use bounded `XLEN`, `XRANGE`, and consumer-group inspection where
Streams are migrated.

## 44. Large-Scale Validation

Prefer counts, type distributions, key-family counts, bounded samples,
application tests, and safely designed checksums/hashes rather than
reading every value.

## 45. Reconciliation

  Category            Source   Target   Difference Accepted?
  ----------------- -------- -------- ------------ -----------
  keys                                             
  memory                                           
  expiring keys                                    
  persistent keys                                  
  streams                                          

Explain every accepted difference.

------------------------------------------------------------------------

# Part 10 --- Cutover Engineering

## 46. Preconditions

-   [ ] initial copy complete;
-   [ ] delta/catch-up complete where required;
-   [ ] compatibility PASS;
-   [ ] validation PASS;
-   [ ] target capacity PASS;
-   [ ] HA healthy;
-   [ ] recovery ready;
-   [ ] monitoring active;
-   [ ] application target config ready;
-   [ ] rollback defined;
-   [ ] owners available.

## 47. Change Freeze

Consider freezing unrelated application, schema/index, client, Redis,
network, and security changes.

## 48. Final Delta

For online migration, minimize and record source-target lag immediately
before cutover.

## 49. DNS

Plan DNS TTL, client caching, connection pools, old connections, and
rollback. DNS change does not instantly reconnect every client.

## 50. Endpoint / Credential

Stage target host, port, TLS trust, and credential. Where supported,
validate the new credential before retiring the old one.

## 51. Traffic Ramp

Example:

``` text
5% -> 25% -> 50% -> 100%
```

At each stage inspect application P99/errors and target CPU, memory,
connections, network, evictions, and replication.

## 52. Stop Conditions

Define data mismatch, excessive P99/errors, target pressure, unhealthy
replication, connection failure, or source overload thresholds before
the window.

------------------------------------------------------------------------

# Part 11 --- Rollback

## 53. Required Questions

``` text
Can clients return to source?
Did target accept writes?
How are target-only writes reconciled?
How long is rollback safe?
Who decides?
```

## 54. Write Divergence

After target writes begin, source and target can diverge. Rollback
becomes a data-consistency problem rather than only an endpoint
reversal.

## 55. Point of No Return

Document when rollback changes into roll-forward or explicit data
reconciliation.

------------------------------------------------------------------------

# Part 12 --- Hypercare & Retirement

## 56. Hypercare

Monitor application latency/errors, Redis latency, CPU, memory,
connections, network, evictions, replication, persistence, Streams
backlog, and source/target traffic.

## 57. Observation Window

Do not delete the source immediately. Keep an approved observation
period when policy and architecture allow it, while preventing
unintended writes.

## 58. Decommission Preconditions

All clients migrated, no unexpected traffic, retention satisfied,
rollback window closed, required backup retained, and owner approval
obtained.

## 59. Dependency Cleanup

Remove obsolete DNS, secrets, certificates where appropriate, network
rules, monitoring, backup jobs, automation, CI/CD references, inventory,
and cost allocation.

------------------------------------------------------------------------

# Part 13 --- Migration Tool Engineering

## 60. Logging

Record phase, start/end, items/bytes, errors, retries, throttling,
checkpoint, and operator. Never log sensitive values.

## 61. Checkpoints

Long migrations should resume safely where the migration mechanism
supports checkpointing.

## 62. Idempotency

Design for safe retry, duplicate handling, replace/conflict policy, and
checkpoint semantics.

## 63. Throttling

Safe speed is bounded by source headroom, target headroom, network, and
application SLO---not maximum possible throughput.

## 64. Parallelism

Increase workers only while source/target CPU, network, connections,
latency, and errors remain within the approved envelope.

------------------------------------------------------------------------

# Part 14 --- Special Risks

## 65. Large Keys

Large objects can cause latency spikes, network bursts, worker
imbalance, memory spikes, and expensive retries.

## 66. Hot Keys

Mutable hot keys can change while being copied. Define consistency
semantics.

## 67. Eviction

Target eviction during migration can invalidate the copy even when the
migration tool reports success.

## 68. Persistence

Target ingestion can amplify AOF, snapshot/rewrite, storage, and
replication pressure.

## 69. Backup

Coordinate backup and migration workloads according to recovery
requirements.

## 70. Active-Active

Review CRDT/data-type support, conflict semantics, regional routing,
catch-up, bandwidth, and convergence using vendor-supported procedures.

## 71. Kubernetes

Validate operator/CRDs, storage, services, DNS, NetworkPolicy, secrets,
scheduling, and failure domains.

## 72. Cloud

Validate routing, private connectivity, security controls, DNS,
cross-region bandwidth/egress, quotas, and storage.

## 73. Catch-Up Condition

For online migration, effective copy/change-transfer rate must exceed
ongoing source change rate to reduce lag.

------------------------------------------------------------------------

# Part 15 --- Failure Injection

## 74. Ten Scenarios

1.  network interruption;
2.  target memory pressure;
3.  migration credential failure;
4.  TLS trust failure;
5.  short-TTL keys;
6.  concurrent source writes;
7.  large key;
8.  migration worker failure;
9.  application cutover to invalid endpoint;
10. post-cutover target failure.

For each scenario capture detection, expected behavior, recovery, data
impact, and evidence.

------------------------------------------------------------------------

# Part 16 --- Troubleshooting Matrix

## 75. Common Problems

  ------------------------------------------------------------------------
  Symptom                             Investigate
  ----------------------------------- ------------------------------------
  migration slow                      network, source/target CPU, key
                                      size/count, TLS

  target key count low                expiry, errors, eviction, writes,
                                      filtering

  TTL mismatch                        copy/restore semantics, duration

  application errors                  endpoint, TLS, auth, client
                                      compatibility

  target latency high                 ingestion, persistence, shard skew,
                                      connections

  lag not decreasing                  write rate vs transfer rate

  memory pressure                     sizing, large keys, eviction,
                                      replication

  Stream behavior wrong               group/PEL state, method support

  Search incomplete                   index/schema/configuration/rebuild

  rollback unsafe                     target-only writes/divergence
  ------------------------------------------------------------------------

------------------------------------------------------------------------

# Part 17 --- Production Runbooks

## 76. Migration Discovery

Inventory source/target, owners, workload, clients, versions, types/TTL,
dataset/workload, compatibility, RPO/RTO, and candidate strategy.

## 77. Qualification

Test network/TLS/auth, benchmark transfer, validate target capacity,
client/data compatibility, TTL, failure/resume, and validation
procedure.

## 78. Offline Migration

Announce window → recovery point → stop writes → copy/import → validate
→ switch → smoke test → monitor.

## 79. Online Migration

Initial copy → change capture → catch up → validate → cutover gate →
final sync → switch → hypercare.

## 80. Cutover

Go/no-go → final state/sync → routing change → reconnect validation →
application validation → Redis validation → monitor stop conditions.

## 81. Rollback

Stop progression → determine target writes/divergence → protect both
states → execute pre-approved rollback if safe → reconcile → validate →
preserve evidence.

## 82. Post-Cutover

Validate application, data/TTL, capacity, HA/persistence,
Streams/Search, alerts, and source traffic.

## 83. Source Decommission

Confirm rollback window/clients/retention → preserve required backup →
approval → remove database → cleanup dependencies → update
inventory/cost.

------------------------------------------------------------------------

# Part 18 --- Templates

## 84. Migration Plan

``` text
Migration:
Owner:
Source:
Target:
Application:
Driver:
Workload type:
Dataset/key count:
Peak ops/sec:
Connections:
RPO/RTO:
Downtime:
Migration method:
Delta method:
Validation:
Cutover:
Stop conditions:
Rollback:
Observation period:
Decommission:
```

## 85. Compatibility

``` text
Source version:
Target version:
Client versions:
Data types:
Modules:
Persistence:
Eviction:
TLS/auth:
Streams:
Search:
Incompatibilities:
Remediation:
```

## 86. Rollback

``` text
Trigger:
Decision owner:
Source writable state:
Target writable state:
Target-only writes possible?:
Reconciliation:
Endpoint reversal:
Validation:
Maximum safe rollback window:
Point of no return:
```

------------------------------------------------------------------------

# Part 19 --- Production Acceptance

## 87. Architecture & Compatibility

-   [ ] source/target documented;
-   [ ] workload classified;
-   [ ] consumers inventoried;
-   [ ] RPO/RTO/downtime defined;
-   [ ] versions/clients/types/features compatible;
-   [ ] TTL/Streams/Search behavior reviewed;
-   [ ] TLS/auth validated.

## 88. Capacity

-   [ ] dataset/key count measured;
-   [ ] large-key risk reviewed;
-   [ ] source impact tested;
-   [ ] target ingestion tested;
-   [ ] network throughput measured;
-   [ ] duration estimated;
-   [ ] failure headroom retained.

## 89. Migration & Cutover

-   [ ] initial copy tested;
-   [ ] delta handling tested where required;
-   [ ] checkpoint/retry tested;
-   [ ] throttling tested;
-   [ ] validation tested;
-   [ ] ten failure scenarios completed;
-   [ ] go/no-go complete;
-   [ ] traffic ramp/stop conditions defined;
-   [ ] rollback and point of no return defined.

## 90. Closure

-   [ ] post-cutover validation PASS;
-   [ ] observation period complete;
-   [ ] no unexpected source clients;
-   [ ] required backup retained;
-   [ ] source retirement approved;
-   [ ] dependencies cleaned up;
-   [ ] evidence retained.

------------------------------------------------------------------------

# 91. Knowledge Validation

1.  Why is copying keys not enough?
2.  Why classify the Redis workload first?
3.  Why inventory every consumer?
4.  Why compare source and target configuration?
5.  Why do versions matter?
6.  Why inventory data types?
7.  Why are TTLs part of correctness?
8.  Why can resetting TTL be wrong?
9.  Why do Streams need additional review?
10. Why can Search/index configuration need separate handling?
11. Why pre-test network/TLS?
12. Why does key count affect duration?
13. Why test target ingestion capacity?
14. How can migration affect source production?
15. What is the advantage of offline migration?
16. What complexity does online migration add?
17. Why is naive dual write dangerous?
18. When can cache rebuild be preferable?
19. What risk does a cold target create?
20. Why use canaries/waves?
21. Why avoid `KEYS *`?
22. Why is command-level migration not automatically a production
    strategy?
23. Why validate application behavior?
24. Why can key counts legitimately differ?
25. Why does DNS not move every client immediately?
26. Why does rollback become harder after target writes?
27. What is the point of no return?
28. Why retain an observation window?
29. Why need checkpoint/idempotency?
30. What must pass before source retirement?

------------------------------------------------------------------------

# 92. Hands-On Acceptance Checklist

-   [ ] Created synthetic Chapter 52 keys.
-   [ ] Recorded types and TTLs.
-   [ ] Built source/target inventories.
-   [ ] Completed compatibility matrix.
-   [ ] Measured dataset/key count/network.
-   [ ] Benchmarked migration throughput.
-   [ ] Tested source impact and target capacity.
-   [ ] Tested key-level migration safely.
-   [ ] Validated remaining TTL.
-   [ ] Validated representative data types.
-   [ ] Validated Streams/Search if used.
-   [ ] Completed application smoke test.
-   [ ] Completed canary migration.
-   [ ] Tested throttling and worker recovery.
-   [ ] Tested authentication/TLS failures.
-   [ ] Tested concurrent writes and large-key behavior.
-   [ ] Completed ten failure scenarios.
-   [ ] Completed cutover/rollback templates.
-   [ ] Completed post-cutover validation.
-   [ ] Completed source-retirement checklist.

------------------------------------------------------------------------

# 93. Cleanup

List only Chapter 52 lab keys:

``` bash
redis-cli --scan --pattern 'tutorial:chapter52:*'
```

Review matches and remove only confirmed disposable keys with `UNLINK`.

Remove temporary migration credentials, firewall rules, test endpoints,
workers, load generators, dashboards, alerts, and restore targets.

Do not remove source data until the approved observation/rollback period
has ended.

Never use `FLUSHDB` or `FLUSHALL` against a shared or production
database.

------------------------------------------------------------------------

# 94. Key Takeaways

1.  Migration is an application and data-consistency change, not just a
    copy.
2.  Workload classification determines strategy.
3.  All consumers must be discovered.
4.  Versions, features, security, and configuration require
    compatibility review.
5.  Data types and TTL semantics are correctness requirements.
6.  Streams and Search need additional validation.
7.  Key count and workload affect duration as much as bytes.
8.  Source headroom limits safe migration speed.
9.  Target capacity must include replication/persistence overhead.
10. Offline migration is simpler but costs downtime.
11. Online migration lowers downtime but increases consistency
    complexity.
12. Naive dual writes create ambiguous states.
13. Rebuilding cache can be safer than copying it.
14. Cold-cache cutover can overload the source.
15. Canary migration reduces blast radius.
16. Validation should include application behavior.
17. Accepted differences must be explained.
18. DNS changes do not immediately reconnect all clients.
19. Rollback becomes a data problem after target writes.
20. Define the point of no return before cutover.
21. Tooling should be observable, retry-safe, checkpointed, and
    throttled.
22. Large/hot keys can dominate migration behavior.
23. Target eviction can invalidate a migration.
24. Hypercare is part of migration.
25. Source retirement requires traffic, retention, rollback, and
    ownership gates.

------------------------------------------------------------------------

# 95. References

Validate migration procedures against the exact deployed Redis
Enterprise source and target versions and current official Redis
documentation, including migration/import-export, replication/HA,
Active-Active, persistence, backup/restore, security/TLS, Kubernetes,
SCAN/DUMP/RESTORE/MIGRATE, Streams, Search/JSON, client libraries, and
cloud networking.

------------------------------------------------------------------------

# Next Chapter

**Chapter 53 --- Redis Enterprise Client SDK Compatibility & Application
Integration Engineering**

Chapter 53 will cover client selection/versioning, connection lifecycle,
TLS/authentication, pooling, timeouts, retry safety, topology/failover
awareness, serialization, graceful shutdown, framework integration,
observability, compatibility testing, and client upgrades.
