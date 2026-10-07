# Chapter 06 --- Redis Enterprise Nodes, Shards, Proxies & Placement

**Status:** Canonical\
**Track:** Redis Enterprise / Redis Software Production Engineering\
**Level:** Foundation → Production Administration\
**Audience:** Redis Administrators, SREs, DBREs, Platform Engineers\
**Lab type:** Topology inspection, shard/proxy placement mapping,
capacity analysis, failure-domain review, safe failure simulation,
troubleshooting, and production acceptance

------------------------------------------------------------------------

# 1. Objective

A Redis Enterprise database is distributed across cluster
infrastructure.

To operate Redis Enterprise safely, an SRE or DBRE must be able to
answer:

``` text
Which nodes host this database?
Where are its primary shards?
Where are its replicas?
Are primary and replica copies separated appropriately?
Where are proxies running?
Is one node carrying significantly more workload?
Is one shard much hotter than the others?
What happens if a node fails?
Does the cluster have enough spare capacity to recover?
```

This chapter builds the topology model required to answer those
questions.

By the end, you should be able to:

-   Explain Redis Enterprise node architecture.
-   Explain the difference between cluster nodes and database shards.
-   Explain primary and replica shards.
-   Explain the proxy/routing layer.
-   Map a database to physical nodes.
-   Inspect shard placement.
-   Inspect proxy placement.
-   Understand placement constraints and failure domains.
-   Understand rack/zone awareness conceptually.
-   Calculate basic shard density.
-   Identify node and shard imbalance.
-   Distinguish capacity imbalance from workload skew.
-   Understand why cluster spare capacity matters during failure.
-   Analyze node-loss scenarios.
-   Build a production topology map.
-   Troubleshoot node, shard, replica, and proxy problems.
-   Perform a placement-readiness review.

------------------------------------------------------------------------

# Part 1 --- Redis Enterprise Node Architecture

## 2. Cluster Nodes

A Redis Enterprise cluster contains multiple nodes.

Conceptually:

``` text
Redis Enterprise Cluster
|
+-- Node 1
+-- Node 2
+-- Node 3
+-- Node 4
```

A node contributes resources such as:

``` text
CPU
memory
network
storage
```

to the cluster.

Database components are placed across these nodes.

------------------------------------------------------------------------

## 3. Nodes Are Shared Infrastructure

A node may participate in multiple databases.

Example:

``` text
Node 1
|
+-- DB-A Primary Shard 1
+-- DB-B Replica Shard 2
+-- DB-C Primary Shard 1
+-- Proxy processes
```

Therefore, troubleshooting a node requires understanding all workloads
placed on it.

A node can appear healthy at the OS level while one database shard is
overloaded.

Likewise, a database can appear healthy overall while one node is under
pressure.

------------------------------------------------------------------------

# Part 2 --- Database Shards

## 4. What Is a Shard?

A shard holds a portion of a database's keyspace.

Example:

``` text
Database
|
+-- Primary Shard 1
+-- Primary Shard 2
+-- Primary Shard 3
+-- Primary Shard 4
```

The database's keys are distributed among the primary shards.

Sharding allows a database to use multiple execution resources and
distribute dataset capacity.

------------------------------------------------------------------------

## 5. Primary Shard

A primary shard serves the authoritative active copy for its portion of
the database workload.

Conceptually:

``` text
Key A -> Primary Shard 1
Key B -> Primary Shard 2
Key C -> Primary Shard 3
```

The application normally does not select a shard directly.

Redis Enterprise routes requests appropriately.

------------------------------------------------------------------------

## 6. Replica Shard

When database replication is enabled, a primary shard has a replica
copy.

Example:

``` text
Primary Shard 1
       |
       v
Replica Shard 1
```

For a four-primary database:

``` text
Database
|
+-- Primary 1 -> Replica 1
+-- Primary 2 -> Replica 2
+-- Primary 3 -> Replica 3
+-- Primary 4 -> Replica 4
```

Replication increases availability but also consumes capacity.

------------------------------------------------------------------------

# Part 3 --- Placement

## 7. Physical Placement

Shards run on cluster nodes.

Example:

``` text
Node 1
  Primary 1
  Replica 3

Node 2
  Primary 2
  Replica 4

Node 3
  Primary 3
  Replica 1

Node 4
  Primary 4
  Replica 2
```

The physical map matters during:

``` text
node failure
maintenance
capacity planning
performance troubleshooting
rebalancing
```

------------------------------------------------------------------------

## 8. Primary and Replica Separation

For high availability, a primary and its replica should not share the
same failure domain where avoidable.

Bad conceptual placement:

``` text
Node 1
|
+-- Primary 1
+-- Replica 1
```

If Node 1 fails, both copies are lost simultaneously.

Better:

``` text
Node 1 -> Primary 1
Node 2 -> Replica 1
```

Failure-domain awareness can extend beyond nodes to racks or
availability zones.

------------------------------------------------------------------------

# Part 4 --- Failure Domains

## 9. What Is a Failure Domain?

A failure domain is infrastructure that can fail together.

Examples:

``` text
node
rack
power domain
availability zone
host group
```

If both primary and replica reside in the same failure domain,
replication may not protect against that domain's failure.

------------------------------------------------------------------------

## 10. Rack / Zone Awareness

Redis Enterprise can use placement information to improve separation
across failure domains when appropriately configured.

Conceptually:

``` text
AZ-A
  Node 1
  Node 2

AZ-B
  Node 3
  Node 4
```

Desired:

``` text
Primary 1 -> AZ-A
Replica 1 -> AZ-B
```

rather than:

``` text
Primary 1 -> AZ-A
Replica 1 -> AZ-A
```

Exact rack/zone configuration is deployment-specific and must be
validated against the deployed Redis Enterprise release.

------------------------------------------------------------------------

# Part 5 --- Proxy Architecture

## 11. Proxy Role

The Redis Enterprise proxy/routing layer helps route client requests
from the database endpoint to the appropriate shard.

Simplified:

``` text
Client
  |
  v
Database Endpoint
  |
  v
Proxy
  |
  +----> Shard 1
  +----> Shard 2
  +----> Shard 3
```

The proxy provides abstraction between clients and physical shard
placement.

------------------------------------------------------------------------

## 12. Why Clients Should Not Track Shard Locations

Shard placement can change because of:

``` text
node failure
maintenance
rebalancing
resharding
cluster changes
```

Applications should use the supported database connectivity model rather
than hard-coding internal shard locations.

------------------------------------------------------------------------

# Part 6 --- Topology Inspection

## 13. Start With Cluster Status

On an authorized administration host:

``` bash
rladmin status
```

Review:

``` text
nodes
databases
shards
alerts/warnings
```

The exact output depends on product release.

------------------------------------------------------------------------

## 14. Inspect Nodes

Where supported:

``` bash
rladmin info node
```

Capture:

``` text
node ID
address
status
rack/zone metadata if exposed
resource information
```

------------------------------------------------------------------------

## 15. Inspect Databases

``` bash
rladmin info db
```

Identify:

``` text
database ID
database name
shard count
replication
status
endpoint
```

------------------------------------------------------------------------

## 16. Inspect Shards

``` bash
rladmin info shard
```

Capture:

``` text
shard ID
database
role
node
status
```

Build the physical topology rather than reading each line independently.

------------------------------------------------------------------------

## 17. Inspect Proxies

Where supported:

``` bash
rladmin info proxy
```

Capture:

``` text
proxy
node
status
database relationship where exposed
```

------------------------------------------------------------------------

# Part 7 --- REST API Inspection

## 18. Read-Only API Workflow

Conceptual resources can include:

``` text
/v1/nodes
/v1/bdbs
/v1/shards
/v1/proxies
```

Use:

``` text
GET
approved credentials
TLS verification
read-only inspection
```

during the lab.

------------------------------------------------------------------------

## 19. Nodes

Conceptual:

``` bash
curl \
  --cacert /path/to/ca.pem \
  -u '<admin-user>:<admin-password>' \
  https://<cluster-manager>:9443/v1/nodes
```

Use secure secret handling in real environments.

------------------------------------------------------------------------

## 20. Shards

Conceptual:

``` bash
curl \
  --cacert /path/to/ca.pem \
  -u '<admin-user>:<admin-password>' \
  https://<cluster-manager>:9443/v1/shards
```

Filter for the target database using fields supported by your release.

------------------------------------------------------------------------

## 21. Proxies

Conceptual:

``` bash
curl \
  --cacert /path/to/ca.pem \
  -u '<admin-user>:<admin-password>' \
  https://<cluster-manager>:9443/v1/proxies
```

The API field names can change between releases.

Do not hard-code tutorial field assumptions into production automation
without validating the API schema.

------------------------------------------------------------------------

# Part 8 --- Build a Topology Map

## 22. Example

Suppose:

``` text
Database: catalog-cache
Primary shards: 4
Replication: enabled
Cluster nodes: 4
```

Observed:

``` text
Node 1
  Primary 1
  Replica 3

Node 2
  Primary 2
  Replica 4

Node 3
  Primary 3
  Replica 1

Node 4
  Primary 4
  Replica 2
```

Draw:

``` text
P1 Node1 ---- R1 Node3
P2 Node2 ---- R2 Node4
P3 Node3 ---- R3 Node1
P4 Node4 ---- R4 Node2
```

This immediately exposes the failure relationships.

------------------------------------------------------------------------

# Part 9 --- Shard Density

## 23. What Is Shard Density?

Shard density is the number of shard processes/components placed on a
node.

Simple count:

``` text
Node 1 = 8 shards
Node 2 = 8 shards
Node 3 = 8 shards
Node 4 = 8 shards
```

This appears balanced by count.

But count alone is not enough.

------------------------------------------------------------------------

## 24. Equal Shard Count Does Not Mean Equal Load

Example:

``` text
Node 1:
8 shards
CPU 85%

Node 2:
8 shards
CPU 30%
```

Potential reasons:

``` text
hot shard
hot key
different databases
different command rates
larger datasets
background work
network load
persistence activity
```

Balance must be evaluated by workload and resources, not only shard
count.

------------------------------------------------------------------------

# Part 10 --- Shard-Level Workload

## 25. Database Average Can Hide Skew

Suppose four primary shards:

``` text
Shard 1 CPU = 95%
Shard 2 CPU = 25%
Shard 3 CPU = 20%
Shard 4 CPU = 20%
```

Average:

``` text
40%
```

Database average looks comfortable.

Shard 1 is saturated.

This is why shard-level observability matters.

------------------------------------------------------------------------

## 26. Common Causes of Shard Skew

Potential causes:

``` text
hot key
uneven key distribution
large expensive key
uneven request pattern
application partitioning
different command complexity
```

Do not automatically add nodes.

First determine whether workload can actually distribute.

------------------------------------------------------------------------

# Part 11 --- Node Capacity

## 27. Capacity Dimensions

A Redis Enterprise node has several relevant capacity dimensions:

``` text
CPU
RAM
network
storage
I/O
shard density
```

The bottleneck may differ by workload.

------------------------------------------------------------------------

## 28. CPU Capacity

Redis workloads can become CPU constrained because of:

``` text
high command rate
expensive commands
large responses
hot keys
many shards
TLS overhead
background operations
```

One node can be CPU constrained while cluster average remains moderate.

------------------------------------------------------------------------

## 29. Memory Capacity

Node memory must support placed database components and operational
headroom.

Consider:

``` text
primary data
replicas
platform overhead
fragmentation
failover
resharding
temporary movement
```

A cluster that is nearly full may have difficulty recovering gracefully
from a node failure.

------------------------------------------------------------------------

## 30. Network Capacity

Redis can generate significant network traffic through:

``` text
client responses
replication
resharding
backup
recovery
large values
cross-node routing
```

Large values can create network pressure even when command rate is
modest.

------------------------------------------------------------------------

# Part 12 --- Spare Capacity

## 31. Why Spare Capacity Matters

Healthy normal-state utilization is not the only requirement.

The cluster must tolerate:

``` text
node loss
maintenance
shard movement
replica recreation
traffic growth
```

Example:

``` text
4 nodes
each at 90% capacity
```

may look efficient.

But after one node fails, remaining nodes may not have enough capacity
to absorb recovery workload safely.

------------------------------------------------------------------------

## 32. N+1 Thinking

A simple resilience question:

> Can the cluster continue safely if one node is unavailable?

For critical systems, evaluate the actual failure model rather than
relying on a generic percentage.

Capacity planning later in the course develops this more rigorously.

------------------------------------------------------------------------

# Part 13 --- Node Failure

## 33. Failure Sequence

Conceptually:

``` text
Node fails
   |
   v
Primary/replica availability changes
   |
   v
HA mechanisms react
   |
   v
Traffic continues/re-routes where possible
   |
   v
Redundancy is restored
```

Exact behavior depends on:

``` text
database replication
cluster health
placement
available capacity
failure-domain configuration
```

------------------------------------------------------------------------

## 34. After Failover, HA May Be Degraded

Suppose:

``` text
Primary P1 -> Node 1
Replica R1 -> Node 3
```

Node 1 fails.

The replica may become the active copy according to HA behavior.

But until redundancy is restored, that shard may temporarily have
reduced protection.

Operational work is not complete merely because the application
recovered.

------------------------------------------------------------------------

# Part 14 --- Maintenance

## 35. Planned Node Maintenance

Before taking a node out of service, understand:

``` text
which primaries are on it
which replicas are on it
which proxies are on it
which databases are affected
available capacity elsewhere
current cluster health
current redundancy
```

Do not begin maintenance from only:

``` text
node CPU looks low
```

------------------------------------------------------------------------

## 36. Maintenance Precheck

Capture:

``` text
cluster status
node status
database status
shard placement
replica health
proxy health
memory headroom
CPU headroom
alerts
active incidents
```

If the cluster is already degraded, routine maintenance may increase
risk.

------------------------------------------------------------------------

# Hands-On Lab --- Topology Mapping

## 37. Lab Goal

You will:

1.  inspect cluster status
2.  list nodes
3.  identify target database
4.  list shards
5.  identify primary shards
6.  identify replicas
7.  map shards to nodes
8.  list proxies
9.  map proxies to nodes
10. record node capacity
11. calculate shard density
12. compare shard workload
13. review failure-domain placement
14. simulate node-loss impact on paper
15. create a maintenance precheck
16. create a topology diagram

No destructive node operation is required.

------------------------------------------------------------------------

## 38. Lab 1 --- Cluster Status

``` bash
rladmin status
```

Record:

``` text
Cluster:
Node count:
Database count:
Shard count:
Warnings:
```

------------------------------------------------------------------------

## 39. Lab 2 --- Node Inventory

``` bash
rladmin info node
```

Build:

  Node   Address   Status   Failure Domain   Notes
  ------ --------- -------- ---------------- -------
                                             
                                             
                                             

------------------------------------------------------------------------

## 40. Lab 3 --- Database Inventory

``` bash
rladmin info db
```

Choose one training database.

Record:

``` text
Database:
ID:
Primary shards:
Replication:
Endpoint:
Memory:
```

------------------------------------------------------------------------

## 41. Lab 4 --- Shard Inventory

``` bash
rladmin info shard
```

Build:

  Shard   Database   Role      Node   Status
  ------- ---------- --------- ------ --------
                     Primary          
                     Replica          

Use terminology exposed by your deployed version.

------------------------------------------------------------------------

## 42. Lab 5 --- Pair Primaries and Replicas

Build:

  Primary   Primary Node   Replica   Replica Node   Same Node?
  --------- -------------- --------- -------------- ------------
  P1                       R1                       
  P2                       R2                       

Expected production objective:

``` text
Same Node? -> No
```

where architecture and configuration support HA separation.

------------------------------------------------------------------------

## 43. Lab 6 --- Failure-Domain Review

Add:

  Pair    Primary Domain   Replica Domain   Same Domain?
  ------- ---------------- ---------------- --------------
  P1/R1                                     
  P2/R2                                     

If:

``` text
Same Domain = Yes
```

document the risk.

Do not move shards merely to satisfy the lab.

------------------------------------------------------------------------

## 44. Lab 7 --- Proxy Inventory

``` bash
rladmin info proxy
```

Build:

  Proxy   Node   Status   Notes
  ------- ------ -------- -------
                          
                          

------------------------------------------------------------------------

## 45. Lab 8 --- Node Shard Density

Count all shards per node.

Example:

  Node       Primary   Replica   Total
  -------- --------- --------- -------
  Node 1           4         4       8
  Node 2           3         5       8
  Node 3           5         3       8

Do not conclude balance from this table alone.

------------------------------------------------------------------------

## 46. Lab 9 --- Add Resource Context

Build:

  Node     Shards   CPU   Memory   Network Status
  ------ -------- ----- -------- --------- --------
                                           
                                           

Look for:

``` text
same shard count but different CPU
same CPU but different memory
network outlier
one node consistently hotter
```

------------------------------------------------------------------------

## 47. Lab 10 --- Per-Shard Workload

Where monitoring exposes shard-level metrics, build:

  Shard   Node     Ops/sec   CPU   Memory Observation
  ------- ------ --------- ----- -------- -------------
                                          

Identify:

``` text
hot shard
cold shard
memory-heavy shard
balanced shard
```

------------------------------------------------------------------------

## 48. Lab 11 --- Topology Diagram

Draw:

``` text
                 Database Endpoint
                        |
                     Proxies
                        |
        +---------------+---------------+
        |               |               |
       P1              P2              P3
        |               |               |
       R1              R2              R3
```

Add physical nodes:

``` text
P1 -> Node 1
R1 -> Node 3
P2 -> Node 2
R2 -> Node 4
...
```

This diagram becomes useful during incidents.

------------------------------------------------------------------------

# Part 15 --- REST API Lab

## 49. Nodes API

Conceptual:

``` bash
curl \
  --cacert /path/to/ca.pem \
  -u '<admin-user>:<admin-password>' \
  https://<cluster-manager>:9443/v1/nodes
```

Compare API results to `rladmin`.

------------------------------------------------------------------------

## 50. Shards API

``` bash
curl \
  --cacert /path/to/ca.pem \
  -u '<admin-user>:<admin-password>' \
  https://<cluster-manager>:9443/v1/shards
```

Identify the target database's shards.

------------------------------------------------------------------------

## 51. Proxies API

``` bash
curl \
  --cacert /path/to/ca.pem \
  -u '<admin-user>:<admin-password>' \
  https://<cluster-manager>:9443/v1/proxies
```

Compare placement with your topology diagram.

Use secure credential handling in real environments.

------------------------------------------------------------------------

# Failure Simulation

## 52. Failure 1 --- Node Loss Tabletop

Do not shut down a production node.

Choose:

``` text
Node 2
```

From your map list:

``` text
primaries on Node 2
replicas on Node 2
proxies on Node 2
databases affected
```

Then answer:

``` text
Which primary shards need HA action?
Where are their replicas?
Does another copy exist in a separate failure domain?
How much capacity remains?
Which databases temporarily lose redundancy?
```

------------------------------------------------------------------------

## 53. Failure 2 --- Replica Placement Risk

Scenario:

``` text
P1 -> Node 1 / AZ-A
R1 -> Node 2 / AZ-A
```

Node failure protection exists.

AZ failure protection does not.

Document:

``` text
failure protected: single node
failure not protected: AZ-A
```

This demonstrates why failure domains matter.

------------------------------------------------------------------------

## 54. Failure 3 --- Hot Shard

Scenario:

``` text
P1 CPU 95%
P2 CPU 25%
P3 CPU 20%
P4 CPU 20%
```

Database average:

``` text
40%
```

Investigation order:

``` text
hot key
key distribution
command mix
large keys
application traffic partitioning
```

Do not begin with:

``` text
add nodes
```

------------------------------------------------------------------------

## 55. Failure 4 --- Cluster Nearly Full

Scenario:

``` text
Node 1 = 88% utilized
Node 2 = 91%
Node 3 = 89%
Node 4 = 90%
```

Question:

``` text
Can Node 4 safely be taken down for maintenance?
```

Answer:

Not from these numbers alone, and the headroom is concerning.

You must validate:

``` text
actual capacity model
shard movement requirements
replica placement
memory
CPU
failure tolerance
```

------------------------------------------------------------------------

## 56. Failure 5 --- Equal Shard Count, Unequal CPU

Scenario:

``` text
Node A = 8 shards, CPU 80%
Node B = 8 shards, CPU 30%
```

Possible explanations:

``` text
hot shards
different databases
different command rates
persistence/background work
network/TLS workload
```

Do not rebalance only by shard count.

------------------------------------------------------------------------

# Troubleshooting

## 57. Node Down

Check:

``` text
cluster status
node status
affected shards
affected databases
primary/replica transitions
proxy health
remaining capacity
alerts
```

Then determine:

``` text
hardware/VM failure
network isolation
process/platform issue
maintenance event
resource exhaustion
```

------------------------------------------------------------------------

## 58. Shard Down

Identify:

``` text
shard ID
database
role
node
replica pair
current database status
```

Then check:

``` text
node health
capacity
placement
replication state
recent failover
recent resharding
```

------------------------------------------------------------------------

## 59. Replica Missing

Investigate:

``` text
replication enabled?
node failure?
insufficient capacity?
placement constraint?
recovery in progress?
recent maintenance?
```

A database can be serving traffic while redundancy is degraded.

------------------------------------------------------------------------

## 60. One Node High CPU

Break down:

``` text
which databases?
which shards?
which proxies?
which commands?
which hot keys?
background operations?
```

Cluster-wide average CPU is insufficient.

------------------------------------------------------------------------

## 61. One Node High Memory

Check:

``` text
shard placement
database sizes
replica placement
fragmentation
temporary migration
recovery
growth
```

Do not assume equal node count implies equal memory usage.

------------------------------------------------------------------------

## 62. Proxy Symptoms

Potential symptoms:

``` text
connection failures
increased latency
routing errors
client reconnects
partial endpoint impact
```

Investigate:

``` text
proxy status
node status
endpoint
network
TLS
database health
shard health
```

------------------------------------------------------------------------

# Part 16 --- Placement Review

## 63. Placement Checklist

For each replicated production database:

``` text
Are primaries and replicas separated?
Are failure domains configured correctly?
Is one node overloaded with critical primaries?
Is one failure domain carrying too many copies?
Is spare capacity sufficient?
Are proxies healthy?
Are shard counts appropriate?
```

------------------------------------------------------------------------

## 64. Critical Database Concentration

Suppose one node hosts primary shards from:

``` text
payments
sessions
authentication
patient-cache
```

Even if technically valid, losing that node can trigger simultaneous HA
activity across several critical services.

Placement review should consider correlated operational impact.

------------------------------------------------------------------------

# Part 17 --- Maintenance Runbook

## 65. Planned Node Maintenance

``` text
1. Confirm change window.
2. Confirm cluster healthy.
3. Confirm no active incident.
4. Identify target node.
5. List shards on target node.
6. List primaries on target node.
7. List replicas on target node.
8. List proxies on target node.
9. Identify affected databases.
10. Verify primary/replica separation.
11. Verify remaining cluster capacity.
12. Verify failure-domain health.
13. Capture baseline latency/errors.
14. Follow supported Redis Enterprise maintenance procedure.
15. Observe shard/replica transitions.
16. Observe node CPU/memory/network.
17. Validate database endpoints.
18. Validate application traffic.
19. Confirm redundancy restored.
20. Close change only after stable observation.
```

------------------------------------------------------------------------

# Part 18 --- Incident Runbooks

## 66. Runbook --- Node Failure

``` text
1. Record incident timestamp.
2. Identify failed/unreachable node.
3. Run cluster status.
4. Identify databases with shards on node.
5. Identify affected primary shards.
6. Identify affected replica shards.
7. Confirm failover/HA state.
8. Confirm database endpoint health.
9. Check remaining node capacity.
10. Check shard recovery/replacement.
11. Check proxy health.
12. Check application errors and latency.
13. Restore or replace failed infrastructure using supported process.
14. Confirm redundancy restoration.
15. Confirm placement remains safe.
16. Document root cause and capacity impact.
```

------------------------------------------------------------------------

## 67. Runbook --- Hot Shard

``` text
1. Identify hot shard.
2. Identify database.
3. Identify hosting node.
4. Capture shard CPU/ops.
5. Compare peer shards.
6. Identify hot keys.
7. Identify large keys.
8. Identify command mix.
9. Check application partitioning.
10. Check key distribution.
11. Determine whether issue is workload skew or insufficient shards.
12. Remediate application/data model where possible.
13. Consider resharding only with evidence and capacity review.
14. Validate post-change distribution.
```

------------------------------------------------------------------------

## 68. Runbook --- Replica Degradation

``` text
1. Identify database.
2. Confirm replication configured.
3. Identify missing/unhealthy replica.
4. Identify primary shard.
5. Identify node/failure domain.
6. Check cluster capacity.
7. Check placement constraints.
8. Check node health.
9. Check recovery status.
10. Avoid additional maintenance while redundancy is degraded.
11. Restore redundancy using supported procedure.
12. Validate primary/replica separation.
13. Close only after HA is restored.
```

------------------------------------------------------------------------

## 69. Runbook --- Placement Imbalance

``` text
1. Capture node inventory.
2. Capture shard inventory.
3. Count primaries/replicas per node.
4. Capture CPU per node.
5. Capture memory per node.
6. Capture network per node.
7. Capture shard-level workload.
8. Identify workload-heavy shards.
9. Identify critical-database concentration.
10. Check failure-domain distribution.
11. Determine whether imbalance is count, memory, or workload.
12. Plan supported rebalance/reshard action.
13. Validate capacity before movement.
14. Monitor during change.
15. Rebuild topology map afterward.
```

------------------------------------------------------------------------

# Part 19 --- Capacity Worksheet

## 70. Node Capacity Table

  -------------------------------------------------------------------------
  Node            CPU   CPU Peak     Memory     Memory     Shards Failure
             Capacity              Capacity       Used            Domain
  -------- ---------- ---------- ---------- ---------- ---------- ---------
                                                                  

                                                                  
  -------------------------------------------------------------------------

------------------------------------------------------------------------

## 71. Database Placement Table

  ----------------------------------------------------------------------------
  Database      Primaries     Replicas   Nodes Used     Peak Ops Criticality
  ---------- ------------ ------------ ------------ ------------ -------------
                                                                 

  ----------------------------------------------------------------------------

------------------------------------------------------------------------

## 72. Failure Capacity Question

For every critical cluster ask:

``` text
If the largest/most-loaded node disappears now,
can the remaining cluster safely carry the workload
and restore database redundancy?
```

If this has never been evaluated, capacity readiness is incomplete.

------------------------------------------------------------------------

# Production Acceptance

## 73. Topology Acceptance Checklist

-   [ ] Node inventory documented.
-   [ ] Failure domains documented.
-   [ ] Database inventory documented.
-   [ ] Primary shard placement documented.
-   [ ] Replica shard placement documented.
-   [ ] Primary/replica separation validated.
-   [ ] Proxy placement documented.
-   [ ] Node CPU capacity documented.
-   [ ] Node memory capacity documented.
-   [ ] Node network considerations reviewed.
-   [ ] Shard density reviewed.
-   [ ] Per-shard workload reviewed.
-   [ ] Hot-shard risk reviewed.
-   [ ] Critical-database concentration reviewed.
-   [ ] Spare capacity reviewed.
-   [ ] Single-node failure scenario reviewed.
-   [ ] Failure-domain scenario reviewed.
-   [ ] Maintenance precheck documented.
-   [ ] Node failure runbook available.
-   [ ] Replica degradation runbook available.
-   [ ] Placement imbalance runbook available.
-   [ ] Topology diagram current.

------------------------------------------------------------------------

# Knowledge Validation

## 74. Questions

You should be able to answer:

1.  What is a Redis Enterprise node?
2.  What is a database shard?
3.  What is a primary shard?
4.  What is a replica shard?
5.  Why should primary and replica copies be separated?
6.  What is a failure domain?
7.  Why can node separation still be insufficient for zone-level
    resilience?
8.  What is the proxy layer used for?
9.  Why should applications avoid internal shard addresses?
10. How can you inspect nodes with `rladmin`?
11. How can you inspect shards?
12. Why is a topology diagram useful during incidents?
13. What is shard density?
14. Why does equal shard count not imply equal node load?
15. How can database averages hide a hot shard?
16. What commonly causes shard skew?
17. Why does a cluster require spare capacity?
18. Why is 90% utilization across every node risky?
19. What happens to redundancy after a failover before a new replica is
    restored?
20. Why should maintenance be delayed when the cluster is already
    degraded?
21. Why should critical-database concentration be reviewed?
22. Why might adding nodes fail to fix a hot shard?
23. What should be validated after node maintenance?
24. What should be captured during a node failure?
25. Why must placement review include workload, not only shard count?

------------------------------------------------------------------------

# Hands-On Acceptance Checklist

## 75. Lab Completion

-   [ ] Ran cluster status.
-   [ ] Built node inventory.
-   [ ] Identified target database.
-   [ ] Built shard inventory.
-   [ ] Paired primaries and replicas.
-   [ ] Reviewed same-node placement.
-   [ ] Reviewed failure-domain placement.
-   [ ] Built proxy inventory.
-   [ ] Calculated shard density.
-   [ ] Added CPU/memory/network context.
-   [ ] Compared per-shard workload.
-   [ ] Created topology diagram.
-   [ ] Compared `rladmin` and API data where available.
-   [ ] Completed node-loss tabletop.
-   [ ] Completed failure-domain tabletop.
-   [ ] Completed hot-shard exercise.
-   [ ] Completed low-headroom exercise.
-   [ ] Completed unequal-CPU exercise.
-   [ ] Created maintenance precheck.
-   [ ] Reviewed all incident runbooks.

------------------------------------------------------------------------

# 76. Key Takeaways

1.  Redis Enterprise nodes provide shared infrastructure for database
    components.
2.  Databases are divided into primary shards for distribution and
    parallelism.
3.  Replicas provide redundant shard copies when replication is enabled.
4.  Primary and replica placement determines failure tolerance.
5.  Node separation and failure-domain separation are different
    concepts.
6.  The proxy layer abstracts physical shard placement from clients.
7.  Shard placement must be understood before maintenance or incident
    response.
8.  Equal shard count does not mean equal workload.
9.  Database-wide averages can hide a saturated shard.
10. Hot keys and skew can overload one shard even when the cluster has
    free capacity.
11. Spare cluster capacity is required for failures, maintenance, and
    recovery.
12. Application recovery after failover does not necessarily mean
    redundancy is restored.
13. Maintenance should begin with a topology and capacity precheck.
14. Placement reviews must consider critical-service concentration.
15. A current topology map is an essential Redis Enterprise SRE
    artifact.

------------------------------------------------------------------------

# 77. References

Validate administration commands, API fields, placement behavior,
rack/zone configuration, and HA behavior against the documentation for
the exact Redis Enterprise / Redis Software release deployed.

Key documentation areas:

-   Redis Enterprise architecture
-   cluster nodes
-   database shards
-   replication
-   proxy architecture
-   rack/zone awareness
-   `rladmin`
-   REST API
-   cluster capacity
-   high availability
-   node maintenance
-   shard placement

------------------------------------------------------------------------

# Next Chapter

**Chapter 07 --- Hash Slots, Key Distribution & Sharding Internals**

Chapter 07 will cover:

-   key-to-shard distribution
-   hash slots and hashing concepts
-   hash tags
-   key distribution analysis
-   multi-key implications
-   hot partitions
-   skew
-   shard scaling
-   resharding concepts
-   distribution experiments
-   failure scenarios
-   troubleshooting
-   production sharding review
