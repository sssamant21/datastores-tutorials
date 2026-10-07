# Chapter 05 --- Redis Enterprise Databases, Endpoints & Configuration

**Status:** Canonical\
**Track:** Redis Enterprise / Redis Software Production Engineering\
**Level:** Foundation → Production Administration\
**Audience:** Redis Administrators, SREs, DBREs, Platform Engineers,
Developers\
**Lab type:** Database architecture inspection, endpoint validation,
configuration audit, safe change planning, failure injection,
troubleshooting, and production acceptance

------------------------------------------------------------------------

# 1. Objective

A Redis Enterprise database is not simply a Redis process listening on a
port.

The database is a logical service managed by the Redis Enterprise
cluster. Its behavior depends on configuration such as:

-   memory limit
-   shard count
-   replication
-   persistence
-   eviction policy
-   endpoint
-   proxy behavior
-   authentication
-   TLS
-   module/capability configuration
-   placement and high-availability settings

Application teams normally connect to the database endpoint rather than
directly managing individual shards.

This chapter teaches how to inspect and reason about a Redis Enterprise
database as a production service.

By the end, you should be able to:

-   Explain the difference between a Redis Enterprise cluster and
    database.
-   Explain database, shard, endpoint, and proxy relationships.
-   Identify a database endpoint.
-   Validate DNS, TCP, TLS, authentication, and Redis protocol access.
-   Inspect database configuration through supported administration
    interfaces.
-   Understand database memory limits.
-   Understand why database memory is not the same as host free memory.
-   Identify eviction-policy intent.
-   Identify replication configuration.
-   Identify persistence configuration.
-   Identify shard count.
-   Understand why adding cluster nodes does not automatically increase
    every database's throughput.
-   Understand why changing shard count is an operational event.
-   Build a configuration baseline.
-   Compare intended and actual configuration.
-   Plan configuration changes safely.
-   Troubleshoot database configuration and endpoint failures.
-   Perform a production database configuration audit.

------------------------------------------------------------------------

# Part 1 --- Cluster vs Database

## 2. Redis Enterprise Cluster

A Redis Enterprise cluster consists of multiple Redis Enterprise nodes
managed as one platform.

Conceptually:

``` text
Redis Enterprise Cluster
|
+-- Node 1
+-- Node 2
+-- Node 3
|
+-- Database A
+-- Database B
+-- Database C
```

The cluster provides shared infrastructure for databases.

The cluster and a database are different administrative objects.

------------------------------------------------------------------------

## 3. Redis Enterprise Database

A database is the logical Redis service consumed by an application.

Example:

``` text
Application
    |
    v
Database Endpoint
    |
    v
Redis Enterprise Database
    |
    +-- Primary Shard 1
    +-- Primary Shard 2
    +-- Replica Shards when replication is enabled
```

A database has configuration such as:

``` text
name
endpoint
port
memory limit
shard count
replication
persistence
eviction policy
authentication
TLS
```

Exact available settings depend on Redis Enterprise / Redis Software
release and deployment type.

------------------------------------------------------------------------

## 4. Shared Cluster, Independent Databases

One cluster can host multiple databases.

Example:

``` text
Cluster
|
+-- customer-cache
+-- session-cache
+-- recommendation-cache
+-- rate-limit
```

These databases may have different:

``` text
memory limits
shard counts
replication settings
persistence settings
eviction policies
security settings
```

This is one reason cluster-level health alone does not prove every
database is healthy.

------------------------------------------------------------------------

# Part 2 --- Database Request Path

## 5. Logical Request Path

A simplified request path is:

``` text
Application
    |
    v
DNS
    |
    v
Database Endpoint
    |
    v
Proxy / Routing Layer
    |
    v
Database Shard
```

When TLS is enabled:

``` text
Application
    |
    v
DNS
    |
    v
TCP
    |
    v
TLS Handshake
    |
    v
Authentication
    |
    v
Redis Protocol
    |
    v
Proxy / Routing
    |
    v
Shard
```

This layered model is useful during incidents.

------------------------------------------------------------------------

## 6. Endpoint Abstraction

Applications should normally use the supported database endpoint.

Example conceptually:

``` text
redis-prod.example.internal:12000
```

The endpoint provides an abstraction over internal shard placement.

Applications should not normally hard-code:

``` text
node IP
shard process address
internal shard port
```

Doing so couples the application to infrastructure that the platform may
move or rebalance.

------------------------------------------------------------------------

# Part 3 --- Database Endpoint

## 7. Endpoint Components

A database endpoint generally includes:

``` text
hostname or IP
port
security mode
authentication requirements
```

Example:

``` text
redis-cache.example.internal:12000
```

TLS URI:

``` text
rediss://redis-cache.example.internal:12000
```

Plain Redis URI where explicitly configured:

``` text
redis://redis-cache.example.internal:12000
```

Production security policy should determine whether non-TLS connectivity
is acceptable.

------------------------------------------------------------------------

## 8. DNS Validation

Linux:

``` bash
dig redis-cache.example.internal
```

or:

``` bash
nslookup redis-cache.example.internal
```

Windows PowerShell:

``` powershell
Resolve-DnsName redis-cache.example.internal
```

Validate:

``` text
name resolves
expected address returned
client environment can reach the resolver
```

------------------------------------------------------------------------

## 9. TCP Validation

Linux:

``` bash
nc -vz redis-cache.example.internal 12000
```

Windows:

``` powershell
Test-NetConnection redis-cache.example.internal -Port 12000
```

TCP success proves only:

``` text
network path to the listening endpoint works
```

It does not prove:

``` text
TLS works
authentication works
authorization works
Redis command works
database is healthy
```

------------------------------------------------------------------------

## 10. Redis Protocol Validation

Example:

``` bash
redis-cli -h redis-cache.example.internal -p 12000 PING
```

Expected when authentication is not required:

``` text
PONG
```

When authentication is required, use the approved credential method.

Avoid placing production passwords directly into shell history where
possible.

For `redis-cli`, one option is:

``` bash
export REDISCLI_AUTH='<password>'
redis-cli -h redis-cache.example.internal -p 12000 PING
unset REDISCLI_AUTH
```

Use your organization's secret-handling standards.

------------------------------------------------------------------------

# Part 4 --- TLS Endpoint Validation

## 11. TLS Connection

Example:

``` bash
redis-cli \
  -h redis-cache.example.internal \
  -p 12000 \
  --tls \
  --cacert /path/to/ca.pem \
  PING
```

Expected:

``` text
PONG
```

Do not make permanent certificate-verification bypasses part of
production configuration.

------------------------------------------------------------------------

## 12. Inspect Certificate

Example:

``` bash
openssl s_client \
  -connect redis-cache.example.internal:12000 \
  -servername redis-cache.example.internal
```

Review:

``` text
certificate subject
issuer
validity
certificate chain
hostname/SAN
verification result
```

Certificate operations are covered deeply in the security section.

------------------------------------------------------------------------

# Part 5 --- Administration Interfaces

## 13. Cluster Manager UI

The Redis Enterprise management UI can expose database configuration
such as:

``` text
database name
status
endpoint
memory
shards
replication
persistence
eviction
security
metrics
```

Use the UI for:

``` text
inspection
approved configuration changes
operational monitoring
```

Exact labels can differ between product releases.

------------------------------------------------------------------------

## 14. `rladmin`

`rladmin` is a Redis Enterprise administration CLI available in
appropriate self-managed environments.

Start with:

``` bash
rladmin status
```

This provides a cluster-oriented view.

Useful inspection patterns can include commands such as:

``` bash
rladmin info cluster
rladmin info db
rladmin info node
rladmin info shard
rladmin info proxy
```

Exact syntax and output can vary by Redis Enterprise / Redis Software
release.

Validate against the documentation for the deployed version.

------------------------------------------------------------------------

## 15. REST API

Redis Enterprise provides management REST APIs.

Conceptual endpoints include resources for:

``` text
cluster
nodes
databases
shards
proxies
```

Examples in self-managed environments may include:

``` text
/v1/cluster
/v1/nodes
/v1/bdbs
/v1/shards
/v1/proxies
```

Authentication, endpoint address, API version, and fields must be
validated against the deployed release.

Never place administrative credentials in source code.

------------------------------------------------------------------------

# Part 6 --- Database Identity

## 16. Build a Database Inventory

For each production database record:

``` text
Database name:
Database ID:
Application owner:
Business owner:
Environment:
Endpoint:
Port:
TLS:
Authentication:
Memory limit:
Primary shards:
Replication:
Persistence:
Eviction policy:
Backup policy:
RPO:
RTO:
Monitoring dashboard:
Runbook:
```

This becomes the database's operational identity.

------------------------------------------------------------------------

## 17. Database ID vs Database Name

Automation should not assume a display name is always the best immutable
identifier.

Where APIs expose an internal database ID, record both:

``` text
human-readable name
database ID
```

This helps avoid ambiguity in automation and incident work.

------------------------------------------------------------------------

# Part 7 --- Memory Limit

## 18. Database Memory Is Explicitly Managed

A Redis Enterprise database normally has an assigned memory capacity.

Conceptually:

``` text
Database memory limit = 20 GB
```

This is not equivalent to:

``` text
server has 20 GB free
```

The platform manages database memory across the cluster according to
database and platform architecture.

------------------------------------------------------------------------

## 19. Memory Limit Is a Capacity Boundary

Application data competes within the database's configured capacity.

When memory approaches the configured limit, behavior depends on factors
including:

``` text
eviction policy
persistence
replication
dataset behavior
platform overhead
workload
```

Do not wait for:

``` text
100% memory
```

before capacity planning.

------------------------------------------------------------------------

## 20. Memory Headroom

A production design needs headroom for:

``` text
traffic growth
temporary spikes
fragmentation
replication
persistence activity
resharding
failover
operational overhead
```

Detailed capacity engineering is covered later.

------------------------------------------------------------------------

# Part 8 --- Eviction Policy

## 21. What Eviction Means

When a cache-oriented database reaches its memory constraints, Redis can
evict keys according to configured policy.

Examples of policy families include:

``` text
no eviction
LRU-oriented
LFU-oriented
TTL-oriented
random
```

The exact policies available depend on the Redis version and product
configuration.

------------------------------------------------------------------------

## 22. Eviction Is an Application Decision

Ask:

``` text
Is Redis a cache?
Is Redis the system of record?
Can data be recreated?
Do all keys have TTLs?
Can any key be evicted?
```

A cache may tolerate eviction.

A source-of-truth workload may not.

Never copy an eviction policy from another database without
understanding the workload.

------------------------------------------------------------------------

## 23. `noeviction`

Conceptually:

``` text
memory full
+
noeviction
=
writes requiring additional memory can fail
```

This can be correct for some workloads.

It can be disastrous for an application that assumes Redis will always
accept cache writes.

Application behavior must match database policy.

------------------------------------------------------------------------

# Part 9 --- Replication

## 24. Database Replication

With replication enabled, primary shards have replica copies.

Conceptually:

``` text
Database
|
+-- Primary Shard 1
|     |
|     +-- Replica Shard 1
|
+-- Primary Shard 2
      |
      +-- Replica Shard 2
```

Replication supports availability.

------------------------------------------------------------------------

## 25. Replication Is Not Backup

Replication protects against certain runtime failures.

It does not replace:

``` text
backup
point-in-time recovery strategy
protection from logical deletion
application corruption recovery
disaster recovery planning
```

If an application deletes data and that deletion replicates, the replica
does not preserve the old logical state simply because it is a replica.

------------------------------------------------------------------------

# Part 10 --- Persistence

## 26. Persistence Purpose

Persistence provides a way to retain database state beyond only
in-memory runtime state.

Redis persistence approaches can include:

``` text
snapshot-oriented persistence
append-only persistence
```

The exact Redis Enterprise configuration options depend on the deployed
release.

Persistence affects:

``` text
durability
storage
I/O
recovery
performance
operational behavior
```

------------------------------------------------------------------------

## 27. Cache vs Durable Workload

A disposable cache may choose different persistence behavior from:

``` text
session state
critical counters
workflow state
durable application state
```

The decision should start with:

``` text
What happens if all current in-memory data is lost?
```

If the answer is:

``` text
application reloads it from the source database
```

the durability requirement differs from:

``` text
data cannot be recreated
```

------------------------------------------------------------------------

# Part 11 --- Shard Count

## 28. Primary Shards

A database can be divided across multiple primary shards.

Conceptually:

``` text
Database
|
+-- Shard 1
+-- Shard 2
+-- Shard 3
+-- Shard 4
```

Keys are distributed according to Redis sharding behavior.

Sharding allows a database workload and dataset to use multiple shard
processes/resources.

------------------------------------------------------------------------

## 29. More Cluster Nodes Does Not Automatically Mean More Database Throughput

Suppose:

``` text
Cluster nodes = 6
Database primary shards = 2
```

Adding two cluster nodes:

``` text
Cluster nodes = 8
```

does not necessarily change:

``` text
Database primary shards = 2
```

The database still has its configured shard architecture until a
database-level operation changes it.

This is a critical capacity concept.

------------------------------------------------------------------------

## 30. More Shards Are Not Free

Increasing shard count can improve distribution for suitable workloads.

But it also affects:

``` text
memory overhead
replicas
placement
networking
rebalancing
operational complexity
multi-key behavior
failure domains
```

Do not use:

``` text
more shards
```

as a universal latency fix.

------------------------------------------------------------------------

# Part 12 --- Proxy and Routing

## 31. Why the Proxy Layer Matters

Applications connect to the logical database endpoint.

The Redis Enterprise routing/proxy layer can route commands to the
appropriate database shard.

Conceptually:

``` text
Client
  |
  v
Endpoint
  |
  v
Proxy
  |
  +----> Shard 1
  |
  +----> Shard 2
  |
  +----> Shard 3
```

This helps hide internal shard placement from clients.

------------------------------------------------------------------------

## 32. Endpoint Health vs Shard Health

A connection failure can originate from different layers:

``` text
DNS
network
TLS
authentication
proxy
database
shard
node
```

Therefore:

``` text
"Redis connection failed"
```

is not a root cause.

It is a symptom.

------------------------------------------------------------------------

# Part 13 --- Configuration Baseline

## 33. Why Baselines Matter

Without a baseline, incident responders may not know whether a setting
changed.

Example baseline:

``` text
Database: patient-cache-prod
Memory: 100 GB
Primary shards: 4
Replication: enabled
Persistence: disabled
Eviction: allkeys-lfu
TLS: enabled
Endpoint: redis-patient.example.internal:12000
```

If shard count becomes:

``` text
2
```

or eviction becomes:

``` text
noeviction
```

you can identify drift.

------------------------------------------------------------------------

## 34. Configuration as Operational Data

Store approved database configuration in:

``` text
Git
IaC
configuration repository
change-management system
runbook
```

depending on organizational practice.

Do not rely only on screenshots.

------------------------------------------------------------------------

# Part 14 --- Configuration Change Safety

## 35. Every Change Needs Context

Before modifying a database:

``` text
Why is the change needed?
What is current value?
What is target value?
Is it online?
Does it move shards?
Does it restart anything?
Does it affect memory?
Does it affect durability?
Does it affect clients?
How long can it take?
How do we validate?
How do we roll back?
```

------------------------------------------------------------------------

## 36. Example: Memory Increase

Changing:

``` text
20 GB -> 40 GB
```

may appear low risk.

Still validate:

``` text
cluster has capacity
placement remains healthy
memory is actually the bottleneck
application growth is understood
alert thresholds are updated
```

Do not use capacity increases to hide an unbounded-key leak.

------------------------------------------------------------------------

## 37. Example: Shard Increase

Changing:

``` text
2 primary shards -> 4 primary shards
```

is an architectural operation.

Consider:

``` text
data movement
rebalancing
CPU
network
memory
replicas
client workload
maintenance/change window
```

Observe the database throughout the operation.

------------------------------------------------------------------------

## 38. Example: Eviction Change

Changing:

``` text
noeviction -> allkeys-lfu
```

changes application semantics.

The database may begin removing keys under memory pressure.

This is not merely a performance tuning setting.

Application owners must understand the consequence.

------------------------------------------------------------------------

## 39. Example: Persistence Change

Enabling or changing persistence can affect:

``` text
storage
I/O
recovery behavior
performance
operational procedures
```

Treat it as a durability architecture change.

------------------------------------------------------------------------

# Hands-On Lab --- Production Database Inspection

## 40. Lab Goal

You will build a database configuration baseline without making
destructive changes.

The lab includes:

1.  identify database
2.  identify endpoint
3.  validate DNS
4.  validate TCP
5.  validate Redis protocol
6.  validate TLS where enabled
7.  inspect Redis server information
8.  inspect memory information
9.  inspect keyspace
10. inspect cluster/database status with administration tooling
11. inspect database configuration
12. inspect nodes
13. inspect shards
14. inspect proxies
15. build a configuration baseline
16. compare actual vs intended configuration
17. perform safe failure injection
18. create a change plan

------------------------------------------------------------------------

## 41. Lab Variables

Set values for your training environment:

``` bash
export REDIS_HOST='<database-endpoint>'
export REDIS_PORT='<database-port>'
```

For authenticated environments, use your approved secret workflow.

Do not commit credentials into:

``` text
Git
shell scripts
tutorial files
terminal screenshots
```

------------------------------------------------------------------------

## 42. Lab 1 --- DNS

Linux:

``` bash
dig "$REDIS_HOST"
```

or:

``` bash
nslookup "$REDIS_HOST"
```

Windows:

``` powershell
Resolve-DnsName <database-endpoint>
```

Record:

``` text
Hostname:
Resolved address:
DNS server:
Result:
```

------------------------------------------------------------------------

## 43. Lab 2 --- TCP

Linux:

``` bash
nc -vz "$REDIS_HOST" "$REDIS_PORT"
```

Windows:

``` powershell
Test-NetConnection <database-endpoint> -Port <database-port>
```

Record:

``` text
TCP success:
Latency:
Failure if any:
```

------------------------------------------------------------------------

## 44. Lab 3 --- Redis Protocol

Example:

``` bash
redis-cli -h "$REDIS_HOST" -p "$REDIS_PORT" PING
```

Authenticated environments:

``` bash
export REDISCLI_AUTH='<password>'
redis-cli -h "$REDIS_HOST" -p "$REDIS_PORT" PING
unset REDISCLI_AUTH
```

Expected:

``` text
PONG
```

------------------------------------------------------------------------

## 45. Lab 4 --- TLS

Where TLS is enabled:

``` bash
redis-cli \
  -h "$REDIS_HOST" \
  -p "$REDIS_PORT" \
  --tls \
  --cacert /path/to/ca.pem \
  PING
```

Record:

``` text
TLS required:
CA:
Certificate verification:
Result:
```

------------------------------------------------------------------------

## 46. Lab 5 --- Server Information

Where permissions allow:

``` bash
redis-cli -h "$REDIS_HOST" -p "$REDIS_PORT" INFO server
```

Inspect relevant fields.

Do not assume every field in standalone Redis has identical operational
meaning in Redis Enterprise.

------------------------------------------------------------------------

## 47. Lab 6 --- Memory Information

``` bash
redis-cli -h "$REDIS_HOST" -p "$REDIS_PORT" INFO memory
```

Record selected observations:

``` text
Used memory:
RSS:
Fragmentation indicators:
Peak memory:
```

Database-level Redis metrics should be interpreted together with Redis
Enterprise platform metrics.

------------------------------------------------------------------------

## 48. Lab 7 --- Keyspace Information

``` bash
redis-cli -h "$REDIS_HOST" -p "$REDIS_PORT" INFO keyspace
```

Record:

``` text
Logical DB:
Key count:
Expiring keys:
Average TTL if exposed:
```

Do not use:

``` redis
KEYS *
```

to inventory a large production database.

------------------------------------------------------------------------

## 49. Lab 8 --- Cluster Status

On an authorized Redis Enterprise administration host:

``` bash
rladmin status
```

Record:

``` text
Cluster state:
Nodes:
Databases:
Shards:
Warnings:
```

------------------------------------------------------------------------

## 50. Lab 9 --- Database Information

Where supported by the deployed version:

``` bash
rladmin info db
```

Identify the target database.

Record:

``` text
Database:
Database ID:
Status:
Memory:
Shards:
Replication:
Endpoint:
```

Use the exact syntax supported by your Redis Enterprise release.

------------------------------------------------------------------------

## 51. Lab 10 --- Node Information

``` bash
rladmin info node
```

Record:

``` text
Node IDs:
Addresses:
Roles/status:
Resource observations:
```

Do not change node configuration in this lab.

------------------------------------------------------------------------

## 52. Lab 11 --- Shard Information

``` bash
rladmin info shard
```

Map:

``` text
database
primary shard
replica shard
node placement
```

Build a simple diagram:

``` text
Database
|
+-- Primary 1 -> Node ?
|   +-- Replica 1 -> Node ?
|
+-- Primary 2 -> Node ?
    +-- Replica 2 -> Node ?
```

------------------------------------------------------------------------

## 53. Lab 12 --- Proxy Information

Where supported:

``` bash
rladmin info proxy
```

Record:

``` text
proxy instances
node placement
status
```

The goal is to understand the path between endpoint and shards.

------------------------------------------------------------------------

# Part 15 --- REST API Inspection

## 54. API Safety

Use:

``` text
read-only GET requests
training/staging first
approved admin credentials
TLS verification
```

Do not experiment with configuration-changing API calls in production.

------------------------------------------------------------------------

## 55. Cluster API

Conceptual example:

``` bash
curl \
  --cacert /path/to/ca.pem \
  -u '<admin-user>:<admin-password>' \
  https://<cluster-manager>:9443/v1/cluster
```

Prefer secure credential handling instead of literal passwords in shell
history.

------------------------------------------------------------------------

## 56. Databases API

Conceptual:

``` bash
curl \
  --cacert /path/to/ca.pem \
  -u '<admin-user>:<admin-password>' \
  https://<cluster-manager>:9443/v1/bdbs
```

Locate the target database.

Record fields relevant to:

``` text
ID
name
status
memory
shards
replication
persistence
endpoint
eviction
```

Field names vary by release.

------------------------------------------------------------------------

## 57. Nodes API

Conceptual:

``` bash
curl \
  --cacert /path/to/ca.pem \
  -u '<admin-user>:<admin-password>' \
  https://<cluster-manager>:9443/v1/nodes
```

Record:

``` text
node IDs
addresses
status
resource/placement information
```

------------------------------------------------------------------------

## 58. Shards API

Conceptual:

``` bash
curl \
  --cacert /path/to/ca.pem \
  -u '<admin-user>:<admin-password>' \
  https://<cluster-manager>:9443/v1/shards
```

Use this to map database shard placement.

------------------------------------------------------------------------

## 59. Proxies API

Conceptual:

``` bash
curl \
  --cacert /path/to/ca.pem \
  -u '<admin-user>:<admin-password>' \
  https://<cluster-manager>:9443/v1/proxies
```

Use this to understand routing/proxy placement.

------------------------------------------------------------------------

# Part 16 --- Build the Baseline

## 60. Database Baseline Worksheet

Complete:

  Setting           Actual   Intended   Match?
  ----------------- -------- ---------- --------
  Database name                         
  Database ID                           
  Endpoint                              
  Port                                  
  TLS                                   
  Authentication                        
  Memory limit                          
  Primary shards                        
  Replication                           
  Persistence                           
  Eviction policy                       
  Backup                                
  Monitoring                            

Any mismatch becomes:

``` text
configuration drift
or
documentation drift
```

Both require resolution.

------------------------------------------------------------------------

# Failure Injection

## 61. Failure 1 --- Wrong Port

Do not modify the database.

Test a known incorrect port:

``` bash
redis-cli -h "$REDIS_HOST" -p 1 PING
```

Expected:

``` text
connection failure
```

Troubleshooting layer:

``` text
TCP/listener
```

------------------------------------------------------------------------

## 62. Failure 2 --- Wrong Password

In a training environment, intentionally use an invalid credential.

Expected:

``` text
authentication failure
```

This distinguishes:

``` text
network success
```

from:

``` text
authentication success
```

Do not trigger account lockout policies.

------------------------------------------------------------------------

## 63. Failure 3 --- TLS Trust Failure

In a safe environment, use an incorrect CA path or untrusted CA.

Expected:

``` text
certificate verification / TLS failure
```

Do not "fix" production by permanently disabling verification.

------------------------------------------------------------------------

## 64. Failure 4 --- Configuration Drift Exercise

Assume intended:

``` text
Memory = 40 GB
Replication = enabled
Shards = 4
Eviction = allkeys-lfu
```

Actual:

``` text
Memory = 20 GB
Replication = enabled
Shards = 2
Eviction = noeviction
```

Do **not** immediately change settings.

Write:

``` text
1. observed mismatch
2. application impact
3. capacity impact
4. change dependencies
5. rollback plan
6. validation plan
```

This teaches safe administration.

------------------------------------------------------------------------

## 65. Failure 5 --- "We Added Nodes but Redis Is Still Slow"

Scenario:

``` text
Cluster before = 6 nodes
Cluster after  = 8 nodes
Database shards = still 2
```

Question:

``` text
Why might database throughput remain unchanged?
```

Answer:

The database's own shard architecture may still be unchanged.

Additional cluster capacity is not automatically equivalent to
additional parallelism for that database.

------------------------------------------------------------------------

# Troubleshooting

## 66. Endpoint Does Not Resolve

Check:

``` text
hostname spelling
DNS zone
client resolver
private DNS visibility
VPN/network context
recent endpoint change
```

Commands:

``` bash
dig <host>
nslookup <host>
```

Windows:

``` powershell
Resolve-DnsName <host>
```

------------------------------------------------------------------------

## 67. DNS Works but TCP Fails

Check:

``` text
port
firewall
security group
network ACL
routing
load balancer/network policy
endpoint listener
database status
```

Do not troubleshoot Redis authentication before TCP connectivity exists.

------------------------------------------------------------------------

## 68. TCP Works but Redis PING Fails

Investigate:

``` text
TLS requirement
authentication
ACL
wrong endpoint
wrong protocol
database availability
```

This narrows the problem above the network layer.

------------------------------------------------------------------------

## 69. TLS Fails

Check:

``` text
CA trust
hostname
SAN
expiration
certificate chain
client TLS configuration
mTLS requirements
clock/time
```

Avoid insecure verification bypass as a permanent solution.

------------------------------------------------------------------------

## 70. Authentication Fails

Check:

``` text
username
password
ACL/user state
secret rotation
client secret version
wrong database
authentication mode
```

Do not repeatedly retry invalid credentials at high rate.

------------------------------------------------------------------------

## 71. Database Is Up but Application Is Slow

Inspect:

``` text
client latency
connection pool
command mix
hot keys
big keys
shard CPU
memory pressure
evictions
network
proxy
application retries
```

A healthy status flag does not prove workload health.

------------------------------------------------------------------------

## 72. Memory Near Limit

Check:

``` text
dataset growth
key count
TTL behavior
evictions
large keys
unbounded collections
fragmentation
traffic growth
replication/persistence overhead
```

Do not immediately increase memory before identifying the cause.

------------------------------------------------------------------------

## 73. One Shard Is Hot

Investigate:

``` text
hot key
key distribution
command distribution
large key
application partitioning
shard count
CPU
```

Increasing cluster node count alone may not fix a shard-level workload
hotspot.

------------------------------------------------------------------------

## 74. Replica Missing or Unhealthy

Check:

``` text
database replication configuration
node health
placement
capacity
failure-domain availability
replica status
recent node event
```

Replication health is part of database health.

------------------------------------------------------------------------

# Part 17 --- Production Change Runbook

## 75. Pre-Change

Document:

``` text
Database:
Database ID:
Environment:
Application owner:
Current configuration:
Requested configuration:
Reason:
Risk:
Expected data movement:
Expected client impact:
Maintenance window:
Rollback:
Validation:
Monitoring:
Approvals:
```

------------------------------------------------------------------------

## 76. Capture Baseline

Before changing anything:

``` text
database status
endpoint connectivity
memory
latency
operations/sec
shard placement
replication health
node health
error rate
evictions
```

Save timestamps.

------------------------------------------------------------------------

## 77. Execute One Controlled Change

Avoid combining unrelated changes such as:

``` text
memory increase
+
shard increase
+
eviction change
+
persistence change
```

into one troubleshooting experiment unless the change plan explicitly
requires them.

One controlled change improves causality and rollback.

------------------------------------------------------------------------

## 78. Observe During Change

Watch:

``` text
database status
shard state
node CPU
memory
network
latency
errors
client reconnects
replication
data movement
```

Stop/escalate according to the approved change plan if safety thresholds
are crossed.

------------------------------------------------------------------------

## 79. Post-Change Validation

Validate:

``` text
endpoint resolves
TCP works
TLS works
authentication works
PING works
application transactions work
database healthy
shards healthy
replicas healthy
latency normal
errors normal
memory expected
configuration equals target
```

------------------------------------------------------------------------

## 80. Rollback

A rollback plan must be specific.

Bad:

``` text
rollback if needed
```

Better:

``` text
If application error rate exceeds approved threshold after change,
restore configuration X from target value Y to previous value Z,
then validate endpoint, shard health, latency, and application traffic.
```

Not every operation is instantly reversible.

Validate rollback feasibility before starting.

------------------------------------------------------------------------

# Part 18 --- Incident Runbooks

## 81. Runbook --- Database Endpoint Failure

``` text
1. Record timestamp and affected application.
2. Confirm exact database endpoint and port.
3. Resolve DNS.
4. Test TCP.
5. Test TLS if enabled.
6. Test authentication.
7. Test Redis PING.
8. Check database status.
9. Check proxy status.
10. Check shard status.
11. Check node status.
12. Check recent configuration changes.
13. Check network changes.
14. Restore service using the failed layer's remediation.
15. Validate application traffic.
16. Document root cause and prevention.
```

------------------------------------------------------------------------

## 82. Runbook --- Database Memory Pressure

``` text
1. Confirm database and memory limit.
2. Capture current memory utilization.
3. Capture growth trend.
4. Check key count.
5. Check TTL behavior.
6. Check eviction metrics.
7. Check large/big keys.
8. Check unbounded collections/streams.
9. Check recent deployment or traffic growth.
10. Confirm eviction policy.
11. Confirm persistence/replication context.
12. Determine whether issue is leak, growth, or legitimate capacity.
13. Remediate data model/lifecycle where appropriate.
14. Increase capacity only with cluster headroom validation.
15. Monitor after remediation.
```

------------------------------------------------------------------------

## 83. Runbook --- Configuration Drift

``` text
1. Retrieve approved baseline.
2. Retrieve actual database configuration.
3. Diff settings.
4. Identify when drift occurred.
5. Identify actor/change record where available.
6. Assess application impact.
7. Determine whether intended state or documentation is wrong.
8. Obtain approval for correction.
9. Apply one controlled correction.
10. Validate database health.
11. Update configuration source of truth.
12. Add automated drift detection where practical.
```

------------------------------------------------------------------------

## 84. Runbook --- Shard Capacity Problem

``` text
1. Identify affected database.
2. Record primary shard count.
3. Record replica configuration.
4. Map shards to nodes.
5. Capture per-shard CPU/workload.
6. Check hot keys.
7. Check big keys.
8. Check key distribution.
9. Check command mix.
10. Check memory per shard.
11. Determine whether problem is skew or insufficient parallelism.
12. Validate cluster capacity for resharding.
13. Create approved shard-change plan if required.
14. Observe data movement and latency during change.
15. Validate distribution after change.
```

------------------------------------------------------------------------

# Part 19 --- Production Review

## 85. Database Design Review Template

``` text
Database name:
Environment:
Owner:
Use case:
Source of truth:
Endpoint:
TLS:
Authentication:
Expected dataset:
Growth/month:
Memory limit:
Primary shards:
Replication:
Persistence:
Eviction:
Backup:
RPO:
RTO:
Peak ops/sec:
Latency SLO:
Connection estimate:
Hot-key risk:
Big-key risk:
Monitoring:
Alerts:
Runbook:
Capacity review date:
```

------------------------------------------------------------------------

## 86. Configuration Anti-Patterns

Avoid:

``` text
unknown database owner
no configuration baseline
no memory headroom
unbounded cache growth
eviction policy copied without workload review
replication assumed to be backup
persistence enabled without I/O/recovery analysis
hard-coded node/shard addresses
adding cluster nodes and assuming DB automatically scales
changing shard count during an incident without capacity analysis
TLS disabled for convenience
credentials embedded in scripts
configuration changes without rollback
```

------------------------------------------------------------------------

# Lab Acceptance

## 87. Hands-On Checklist

-   [ ] Identified database endpoint.
-   [ ] Resolved endpoint DNS.
-   [ ] Tested TCP.
-   [ ] Tested Redis protocol.
-   [ ] Tested TLS where enabled.
-   [ ] Inspected `INFO server`.
-   [ ] Inspected `INFO memory`.
-   [ ] Inspected `INFO keyspace`.
-   [ ] Ran `rladmin status` where available.
-   [ ] Identified target database.
-   [ ] Identified database ID.
-   [ ] Recorded memory limit.
-   [ ] Recorded shard count.
-   [ ] Recorded replication state.
-   [ ] Recorded persistence state.
-   [ ] Recorded eviction policy.
-   [ ] Inspected node information.
-   [ ] Inspected shard placement.
-   [ ] Inspected proxy information.
-   [ ] Performed read-only REST API inspection where available.
-   [ ] Built actual-vs-intended configuration table.
-   [ ] Tested wrong-port failure.
-   [ ] Reviewed authentication failure.
-   [ ] Reviewed TLS trust failure.
-   [ ] Completed configuration drift exercise.
-   [ ] Completed scale-vs-shard exercise.
-   [ ] Created a safe configuration change plan.

------------------------------------------------------------------------

# Knowledge Validation

## 88. Questions

You should be able to answer:

1.  What is the difference between a Redis Enterprise cluster and
    database?
2.  What is a database endpoint?
3.  Why should applications avoid direct shard addresses?
4.  What layers exist between an application and Redis data?
5.  What does successful TCP connectivity prove?
6.  What does it not prove?
7.  Why should TLS verification not be permanently disabled?
8.  What is `rladmin` used for?
9.  What is the Redis Enterprise REST API used for?
10. Why record both database name and database ID?
11. What does a database memory limit represent?
12. Why is host free memory not equivalent to database memory capacity?
13. Why is eviction policy an application-semantic decision?
14. What can happen under `noeviction` when memory is exhausted?
15. Why is replication not backup?
16. Why does persistence require performance and recovery consideration?
17. What is a primary shard?
18. Why does adding cluster nodes not automatically increase database
    throughput?
19. Why is increasing shard count an operational event?
20. What does the proxy/routing layer do?
21. Why is a configuration baseline important?
22. Why should configuration changes be performed one controlled change
    at a time?
23. What should be validated after a database change?
24. Why should memory pressure be investigated before simply increasing
    memory?
25. What can cause one shard to be much hotter than others?

------------------------------------------------------------------------

# Production Acceptance Checklist

## 89. Database Readiness

Before production approval:

-   [ ] Database owner documented.
-   [ ] Application owner documented.
-   [ ] Database ID recorded.
-   [ ] Endpoint documented.
-   [ ] DNS path validated.
-   [ ] Network path validated.
-   [ ] TLS policy documented.
-   [ ] Authentication documented.
-   [ ] Secrets stored securely.
-   [ ] Memory limit capacity-tested.
-   [ ] Growth forecast documented.
-   [ ] Memory headroom defined.
-   [ ] Shard count justified.
-   [ ] Replication requirement documented.
-   [ ] Persistence requirement documented.
-   [ ] Eviction policy justified.
-   [ ] Backup strategy documented.
-   [ ] RPO documented.
-   [ ] RTO documented.
-   [ ] Monitoring dashboard available.
-   [ ] Alerts configured.
-   [ ] Configuration baseline stored.
-   [ ] Drift process defined.
-   [ ] Change runbook available.
-   [ ] Endpoint failure runbook available.
-   [ ] Memory pressure runbook available.
-   [ ] Shard capacity runbook available.
-   [ ] Recovery ownership defined.

------------------------------------------------------------------------

# 90. Key Takeaways

1.  A Redis Enterprise database is a managed logical service, not merely
    a Redis process.
2.  Applications should normally connect through the database endpoint.
3.  DNS, TCP, TLS, authentication, proxy, shard, and node are separate
    troubleshooting layers.
4.  Database configuration defines important application behavior.
5.  Memory limits require planned headroom.
6.  Eviction policy must match the workload's data semantics.
7.  Replication improves availability but does not replace backup.
8.  Persistence is a durability decision with operational consequences.
9.  Shard count determines database parallelism and placement
    characteristics.
10. Adding cluster nodes does not automatically reshard every database.
11. More shards are not automatically better.
12. Configuration baselines make drift detectable.
13. Redis configuration should be treated as controlled operational
    data.
14. Configuration changes need baselines, monitoring, validation, and
    rollback planning.
15. Production database administration should be driven by workload
    evidence rather than guesswork.

------------------------------------------------------------------------

# 91. References

Validate all commands, API fields, configuration names, and supported
features against documentation for the exact Redis Enterprise / Redis
Software release deployed in your environment.

Key documentation areas:

-   Redis Enterprise / Redis Software architecture
-   database configuration
-   database endpoints
-   `rladmin`
-   REST API
-   memory management
-   eviction policies
-   replication
-   persistence
-   sharding
-   proxy architecture
-   TLS and authentication
-   database monitoring

------------------------------------------------------------------------

# Next Chapter

**Chapter 06 --- Redis Enterprise Nodes, Shards, Proxies & Placement**

Chapter 06 will cover:

-   Redis Enterprise node architecture
-   shard processes
-   primary and replica placement
-   proxy placement
-   failure domains
-   rack/zone awareness
-   node capacity
-   shard density
-   placement inspection
-   node loss behavior
-   resource imbalance
-   hands-on topology mapping
-   safe failure simulations
-   troubleshooting
-   node/shard placement runbooks
-   production acceptance checklist
