# Chapter 66 --- Redis Enterprise Active-Active Operations, Monitoring & Failure Recovery

**Status:** Canonical\
**Track:** Redis Enterprise / Redis Software Production Engineering\
**Part:** Part 11 --- Advanced Kubernetes, Active-Active & Platform
Engineering\
**Level:** Advanced → Production Multi-Region Operations & Recovery
Engineering\
**Audience:** SREs, DBREs, Platform Engineers, Redis Administrators,
Kubernetes Administrators, Cloud Engineers, Network Engineers\
**Lab type:** Active-Active topology operations, regional monitoring,
RERC/REAADB health, WAN degradation, replication recovery, capacity,
maintenance, certificates, credentials, incident response, failure
injection, troubleshooting, runbooks, and production acceptance

------------------------------------------------------------------------

# 1. Objective

Chapter 65 focused on the semantics of concurrent multi-region writes.

Chapter 66 focuses on keeping that architecture healthy in production.

A useful operational model is:

``` text
application traffic
        |
regional endpoint
        |
regional Redis Enterprise database
        |
Active-Active replication
        |
WAN / security / remote-cluster relationship
        |
peer region
```

Production health therefore requires more than checking that both
databases are reachable.

You must understand:

``` text
local database health
remote relationship health
replication state
WAN health
regional capacity
application routing
convergence/recovery
```

By the end of this chapter, you should be able to:

-   inventory Active-Active topology;
-   monitor RERC and REAADB resources;
-   establish regional health dashboards;
-   detect WAN and replication degradation;
-   distinguish local health from global health;
-   manage replication backlog recovery;
-   validate regional capacity;
-   coordinate maintenance safely;
-   troubleshoot certificates and credentials;
-   operate through region/network failures;
-   recover and validate a returning region;
-   perform controlled failure drills;
-   execute production runbooks and acceptance gates.

------------------------------------------------------------------------

# 2. Core Production Principle

An Active-Active database can be:

``` text
locally healthy
```

while the multi-region system is:

``` text
globally degraded
```

For example:

``` text
Region A local reads/writes = healthy
Region B local reads/writes = healthy
A <-> B replication path = broken
```

Both applications may appear healthy while divergence grows.

Therefore monitor local and global state separately.

------------------------------------------------------------------------

# Part 1 --- Operational Topology

## 3. Inventory

Document:

``` text
participating regions
Kubernetes clusters
REC resources
RERC resources
REAADB resources
Redis versions
Operator versions
regional endpoints
WAN paths
traffic routing
security/trust
```

------------------------------------------------------------------------

# Part 2 --- Topology Diagram

## 4. Maintain

Example:

``` text
             Global Traffic Layer
               /            \
              /              \
       Region A              Region B
       App A                 App B
         |                     |
       Redis A <============> Redis B
         |    Active-Active    |
       REC A                 REC B
         |                     |
       K8s A                 K8s B
```

Include failure domains and ownership.

------------------------------------------------------------------------

# Part 3 --- Resource Discovery

## 5. Kubernetes

Use installed APIs:

``` bash
kubectl api-resources | grep -i redis
```

Then list the actual remote-cluster and Active-Active resources.

Do not assume aliases exist.

------------------------------------------------------------------------

# Part 4 --- RERC Health

## 6. Inspect

``` bash
kubectl get <rerc-resource> -A
kubectl get <rerc-resource> <name> -n <namespace> -o yaml
kubectl describe <rerc-resource> <name> -n <namespace>
```

Review:

``` text
spec
status
conditions
events
```

------------------------------------------------------------------------

# Part 5 --- REAADB Health

## 7. Inspect

``` bash
kubectl get <reaadb-resource> -A
kubectl get <reaadb-resource> <name> -n <namespace> -o yaml
kubectl describe <reaadb-resource> <name> -n <namespace>
```

Use version-specific status fields.

------------------------------------------------------------------------

# Part 6 --- Local Database Health

## 8. Per Region

Monitor:

``` text
availability
latency
CPU
memory
connections
shard/node state
persistence
local errors
```

------------------------------------------------------------------------

# Part 7 --- Global Health

## 9. Across Regions

Monitor:

``` text
remote relationship state
Active-Active state
replication connectivity
sync/convergence indicators
WAN
regional application health
```

------------------------------------------------------------------------

# Part 8 --- Health Matrix

## 10. Example

  Region A   Region B   Replication   Interpretation
  ---------- ---------- ------------- -------------------------
  healthy    healthy    healthy       normal
  healthy    healthy    broken        globally degraded
  healthy    down       unavailable   regional outage
  degraded   healthy    healthy       local regional issue
  healthy    healthy    recovering    post-partition recovery

------------------------------------------------------------------------

# Part 9 --- Regional Labels

## 11. Observability

Every metric/log/trace should identify:

``` text
region
cluster
database
application
environment
```

where practical.

------------------------------------------------------------------------

# Part 10 --- Dashboard Layers

## 12. Build Four Views

``` text
1. application per region
2. Redis per region
3. Active-Active replication
4. WAN/infrastructure
```

------------------------------------------------------------------------

# Part 11 --- Application Dashboard

## 13. Track

Per region:

``` text
request rate
P50/P95/P99
error rate
Redis timeout rate
retry rate
connection errors
business success rate
```

------------------------------------------------------------------------

# Part 12 --- Redis Dashboard

## 14. Track

Per participating database:

``` text
database availability
command latency
CPU
memory
connections
throughput
persistence
node/shard health
```

------------------------------------------------------------------------

# Part 13 --- Active-Active Dashboard

## 15. Track

Use supported product metrics/status for:

``` text
participating sites
remote relationship health
replication state
sync/recovery state
lag/backlog where exposed
```

Do not invent unavailable metrics.

------------------------------------------------------------------------

# Part 14 --- WAN Dashboard

## 16. Track

Between each participating region pair:

``` text
latency
packet loss
jitter
bandwidth
availability
retransmissions where available
```

------------------------------------------------------------------------

# Part 15 --- Normal Baseline

## 17. Capture

During healthy operation:

``` text
local P99
cross-region network RTT
write throughput
replication traffic
CPU
memory
network bandwidth
```

A baseline helps identify abnormal recovery.

------------------------------------------------------------------------

# Part 16 --- Alerting Strategy

## 18. Avoid One Alert

Separate alerts for:

``` text
local Redis outage
remote relationship failure
Active-Active degradation
WAN degradation
replication recovery
capacity pressure
certificate expiry
```

------------------------------------------------------------------------

# Part 17 --- Local Healthy / Global Broken

## 19. Dangerous Case

This condition can be quiet:

``` text
applications succeed locally
replication is broken
```

It requires direct monitoring of Active-Active health.

------------------------------------------------------------------------

# Part 18 --- WAN Latency Increase

## 20. Effect

Higher WAN latency can increase cross-region propagation time and
recovery time.

Local command latency may remain normal.

------------------------------------------------------------------------

# Part 19 --- Packet Loss

## 21. Effect

Packet loss can cause:

``` text
retransmissions
reduced effective throughput
connection instability
slower replication recovery
```

------------------------------------------------------------------------

# Part 20 --- WAN Bandwidth Saturation

## 22. Effect

If write/replication traffic approaches available WAN bandwidth:

``` text
replication recovery slows
backlog may grow
application cross-region visibility degrades
```

------------------------------------------------------------------------

# Part 21 --- Replication Backlog

## 23. Concept

During connectivity interruption, operations may accumulate for later
synchronization according to the product architecture.

After connectivity returns, recovery traffic can exceed normal
steady-state traffic.

------------------------------------------------------------------------

# Part 22 --- Recovery Headroom

## 24. Reserve

Each region should have headroom for:

``` text
local application traffic
replication recovery
Redis processing
network transfer
```

Do not size only for normal replication.

------------------------------------------------------------------------

# Part 23 --- Recovery Rate

## 25. Measure

A useful conceptual metric is:

``` text
recovery rate > new change rate
```

If new changes accumulate faster than recovery processes them,
convergence may not catch up.

Use supported metrics/evidence to assess this.

------------------------------------------------------------------------

# Part 24 --- Recovery ETA

## 26. Estimate

Conceptually:

``` text
ETA ~= backlog / net recovery rate
```

This is an approximation.

Actual behavior depends on operation types, bandwidth, Redis processing,
and product internals.

------------------------------------------------------------------------

# Part 25 --- Application Load During Recovery

## 27. Tradeoff

Heavy local writes can compete with synchronization.

If recovery threatens SLO or convergence objectives, consider approved
traffic/load controls.

------------------------------------------------------------------------

# Part 26 --- Retry Amplification

## 28. Risk

WAN or endpoint instability can trigger client retries.

Uncontrolled retries can add load exactly when capacity is reduced.

Use:

``` text
bounded retries
backoff
jitter
idempotency
```

------------------------------------------------------------------------

# Part 27 --- Regional Capacity

## 29. Normal State

Record per region:

``` text
CPU
memory
storage
network
connections
database capacity
```

------------------------------------------------------------------------

# Part 28 --- Failure-State Capacity

## 30. More Important

Ask:

``` text
Can Region B handle traffic from Region A?
```

if the traffic design shifts application load after a regional outage.

------------------------------------------------------------------------

# Part 29 --- Capacity Formula

## 31. Conceptual

``` text
required surviving capacity
=
local workload
+ shifted workload
+ replication/recovery overhead
+ safety headroom
```

Benchmark the real application.

------------------------------------------------------------------------

# Part 30 --- Traffic Routing

## 32. Inventory

Document:

``` text
DNS/GSLB
load balancers
health checks
routing policy
TTL
regional weights
manual/automatic failover
```

------------------------------------------------------------------------

# Part 31 --- Traffic Health Check

## 33. Design

A health check should reflect the service decision.

Do not route traffic merely because:

``` text
TCP port opens
```

if the application requires more complete health.

Avoid health checks that are so strict they cause unnecessary flapping.

------------------------------------------------------------------------

# Part 32 --- Automatic Failover

## 34. Risk

Automatic regional traffic movement can be fast but can also amplify
transient faults.

Define:

``` text
failure threshold
hold-down
capacity check
recovery policy
```

------------------------------------------------------------------------

# Part 33 --- Manual Failover

## 35. Tradeoff

Manual decisions may reduce false failover but increase response time.

Use the approach aligned with business RTO.

------------------------------------------------------------------------

# Part 34 --- Regional Maintenance

## 36. Before Start

Validate:

``` text
peer regions healthy
Active-Active synchronized
WAN healthy
surviving capacity sufficient
backup/recovery ready
traffic plan ready
```

------------------------------------------------------------------------

# Part 35 --- Maintenance Sequence

## 37. Conceptual

``` text
validate global health
 -> reduce/shift traffic if required
 -> perform regional maintenance
 -> validate local Redis
 -> validate Active-Active synchronization
 -> canary traffic
 -> restore traffic
```

Use exact vendor procedures.

------------------------------------------------------------------------

# Part 36 --- Do Not Maintain Two Regions Simultaneously

## 38. Rule

Avoid overlapping maintenance that removes redundancy unless explicitly
designed and approved.

------------------------------------------------------------------------

# Part 37 --- Version Compatibility

## 39. Multi-Site

Before upgrading one region, verify supported mixed-version state.

Do not assume a rolling regional upgrade is supported simply because
each version is supported individually.

------------------------------------------------------------------------

# Part 38 --- Operator Compatibility

## 40. Kubernetes

Active-Active resources depend on compatible Operator/API behavior
across participating Kubernetes clusters.

Track versions together.

------------------------------------------------------------------------

# Part 39 --- Certificates

## 41. Cross-Region Trust

Certificate problems can break replication relationships.

Inventory:

``` text
certificate
issuer
expiry
trust chain
rotation owner
```

------------------------------------------------------------------------

# Part 40 --- Certificate Expiry Monitoring

## 42. Alert Early

Do not wait until the day of expiry.

Use enough lead time to:

``` text
approve
rotate
validate
rollback/recover
```

------------------------------------------------------------------------

# Part 41 --- Certificate Rotation

## 43. Rehearse

Test rotation in nonproduction.

Validate:

``` text
local service
remote trust
Active-Active relationship
application connectivity
```

------------------------------------------------------------------------

# Part 42 --- Credentials

## 44. Remote Relationships

Remote-cluster configuration may depend on secrets/credentials.

Monitor and rotate using supported procedures.

------------------------------------------------------------------------

# Part 43 --- Secret Rotation

## 45. Avoid Split Trust

A poorly sequenced rotation can leave:

``` text
Region A trusts new credential
Region B still uses old credential
```

Coordinate the transition.

------------------------------------------------------------------------

# Part 44 --- Firewall Changes

## 46. Change Risk

Cross-region replication can break because of:

``` text
firewall
security group
route
NetworkPolicy
load balancer
```

Include Active-Active tests in network changes.

------------------------------------------------------------------------

# Part 45 --- DNS Changes

## 47. Change Risk

If remote endpoints or application routing depend on DNS:

``` text
TTL
resolver cache
record propagation
client behavior
```

must be considered.

------------------------------------------------------------------------

# Part 46 --- Regional Network Partition

## 48. Detection

Indicators may include:

``` text
remote relationship degraded
WAN alarm
replication state change
regional data divergence
```

while local traffic remains healthy.

------------------------------------------------------------------------

# Part 47 --- Partition Incident Priority

## 49. First Question

Determine:

``` text
Are both regions still accepting writes?
```

Then assess business risk based on Chapter 65 conflict semantics.

------------------------------------------------------------------------

# Part 48 --- Write Control During Partition

## 50. Application Decision

For some workloads, continuing writes in both regions is correct.

For others, the business may choose to:

``` text
restrict certain operations
assign temporary home region
disable conflict-sensitive workflow
```

This is an application policy, not a generic Redis rule.

------------------------------------------------------------------------

# Part 49 --- Partition Duration

## 51. Track

Record:

``` text
partition start
detection time
business mitigation
network restoration
convergence completion
```

------------------------------------------------------------------------

# Part 50 --- Partition Healing

## 52. Do Not Rush

After network restoration:

``` text
replication recovering
```

is not the same as:

``` text
fully converged and ready
```

------------------------------------------------------------------------

# Part 51 --- Recovery Validation

## 53. Require

``` text
RERC healthy
REAADB healthy
replication/sync healthy
backlog cleared where observable
regional Redis healthy
application checks pass
business invariants pass
```

------------------------------------------------------------------------

# Part 52 --- Region Outage

## 54. Scenario

If Region A is unavailable:

``` text
Region B database may remain writable
```

but application continuity depends on:

``` text
traffic routing
Region B capacity
credentials
dependencies
```

------------------------------------------------------------------------

# Part 53 --- Dependency Inventory

## 55. Beyond Redis

A region failover can fail because another dependency is regional:

``` text
application service
identity
API
database
message broker
secret system
DNS
```

Include dependency mapping in DR design.

------------------------------------------------------------------------

# Part 54 --- Region Return

## 56. Validate First

Before returning application traffic:

``` text
Kubernetes healthy
Redis Enterprise healthy
RERC healthy
REAADB healthy
sync complete/healthy
application version correct
certificates correct
capacity healthy
```

------------------------------------------------------------------------

# Part 55 --- Traffic Reintroduction

## 57. Ramp

Use:

``` text
canary
partial
full
```

instead of instant full restoration where the traffic system permits.

------------------------------------------------------------------------

# Part 56 --- Flapping Region

## 58. Risk

Repeated:

``` text
up -> down -> up
```

can cause traffic and connection churn.

Use hold-down/stability criteria before restoring full traffic.

------------------------------------------------------------------------

# Part 57 --- Regional Degradation

## 59. Not Full Outage

Examples:

``` text
high P99
packet loss
storage degradation
CPU saturation
```

A degraded region may be worse than a clearly failed one because health
checks may still pass.

------------------------------------------------------------------------

# Part 58 --- Brownout Policy

## 60. Define

Decide when to:

``` text
reduce regional traffic
stop expensive operations
shift traffic
```

based on measured SLOs.

------------------------------------------------------------------------

# Part 59 --- Split Observability

## 61. Avoid

Do not keep each region's dashboards isolated with no global view.

Operators need:

``` text
regional detail
+
global comparison
```

------------------------------------------------------------------------

# Part 60 --- Clock Alignment

## 62. Incident Timelines

Ensure reliable time synchronization so:

``` text
Region A logs
Region B logs
network telemetry
Redis events
```

can be correlated.

------------------------------------------------------------------------

# Part 61 --- Synthetic Probes

## 63. Useful

Where safe, run synthetic checks per region:

``` text
local write/read
cross-region visibility
endpoint TLS
DNS
```

Use isolated keys and low frequency.

------------------------------------------------------------------------

# Part 62 --- Synthetic Key

## 64. Example

``` text
tutorial:chapter66:probe:<region>
```

Include timestamp/operation ID but no sensitive data.

Clean safely.

------------------------------------------------------------------------

# Part 63 --- Cross-Region Probe

## 65. Measure

Conceptually:

``` text
write in A
observe in B
measure elapsed time
```

Use this as an application-level signal, not a replacement for product
health metrics.

------------------------------------------------------------------------

# Part 64 --- Alert Correlation

## 66. Example

``` text
WAN packet loss
+
RERC degraded
+
cross-region probe slow
+
local Redis healthy
```

strongly suggests a replication-path issue.

------------------------------------------------------------------------

# Part 65 --- Incident Severity

## 67. Context

Severity depends on:

``` text
local availability
number of affected regions
whether both regions accept writes
business conflict exposure
traffic impact
duration
```

------------------------------------------------------------------------

# Part 66 --- Evidence Collection

## 68. Capture

``` text
RERC status
REAADB status
REC/REDB status
Operator logs
Redis health
WAN metrics
application metrics
recent changes
traffic routing
```

------------------------------------------------------------------------

# Part 67 --- Avoid Destructive Troubleshooting

## 69. Never Start With

``` text
delete RERC
delete REAADB
delete Redis pods
delete PVCs
remove finalizers
```

Use evidence and supported recovery procedures.

------------------------------------------------------------------------

# Part 68 --- Backlog Recovery Load

## 70. Monitor

After partition:

``` text
WAN throughput
CPU
memory
storage
Redis latency
application P99
```

Recovery can create a second incident if capacity is insufficient.

------------------------------------------------------------------------

# Part 69 --- Throttling Application Load

## 71. Optional Mitigation

If approved by the application/business, temporarily reduce noncritical
write load so replication recovery can catch up.

Do not improvise data-loss behavior.

------------------------------------------------------------------------

# Part 70 --- Capacity Trend

## 72. Forecast

Track:

``` text
regional growth
write rate
replication bandwidth
peak failover traffic
recovery rate
```

Scale before the failure-state model becomes unsafe.

------------------------------------------------------------------------

# Part 71 --- Active-Active Change Management

## 73. Changes Requiring Cross-Region Review

Examples:

``` text
Redis upgrade
Operator upgrade
network change
certificate rotation
credential rotation
capacity change
traffic routing change
application schema change
```

------------------------------------------------------------------------

# Part 72 --- One Region at a Time

## 74. Preferred Pattern

Where supported:

``` text
change one region
validate
restore steady state
continue
```

Do not create simultaneous uncertainty across all sites.

------------------------------------------------------------------------

# Part 73 --- Change Stop Conditions

## 75. Define

Stop if:

``` text
unexpected replication degradation
peer region unhealthy
application error exceeds threshold
P99 exceeds threshold
convergence does not recover
capacity headroom becomes unsafe
```

------------------------------------------------------------------------

# Part 74 --- Post-Change Soak

## 76. Observe

After regional maintenance:

``` text
local Redis
Active-Active health
WAN
application
cross-region probe
capacity
```

before moving to another region.

------------------------------------------------------------------------

# Part 75 --- Failure Scenario 1: WAN Latency

## 77. Lab

Inject bounded latency in an isolated nonproduction path.

Measure:

``` text
local P99
cross-region visibility
replication state
```

------------------------------------------------------------------------

# Part 76 --- Failure Scenario 2: Packet Loss

## 78. Lab

Inject bounded packet loss.

Measure:

``` text
retransmissions
replication degradation
recovery time
```

------------------------------------------------------------------------

# Part 77 --- Failure Scenario 3: Full Partition

## 79. Lab

Partition the test regions.

Continue approved local operations.

Restore and measure convergence.

------------------------------------------------------------------------

# Part 78 --- Failure Scenario 4: Backlog Recovery

## 80. Lab

Generate bounded writes during a partition.

After healing, measure:

``` text
recovery throughput
application P99
time to convergence
```

------------------------------------------------------------------------

# Part 79 --- Failure Scenario 5: Region Outage

## 81. Lab/Tabletop

Make one test region unavailable using supported mechanisms.

Validate traffic movement and surviving capacity.

------------------------------------------------------------------------

# Part 80 --- Failure Scenario 6: Region Rejoin

## 82. Lab

Restore the region.

Do not send full traffic until synchronization and health gates pass.

------------------------------------------------------------------------

# Part 81 --- Failure Scenario 7: Certificate Failure

## 83. Lab

Use an isolated invalid/expired test certificate or trust configuration.

Verify:

``` text
clear alert
relationship degradation visible
no silent insecure fallback
```

------------------------------------------------------------------------

# Part 82 --- Failure Scenario 8: Credential Failure

## 84. Lab

Use invalid test credentials for a disposable remote relationship.

Validate diagnosis and supported rotation/recovery.

------------------------------------------------------------------------

# Part 83 --- Failure Scenario 9: Capacity During Traffic Shift

## 85. Test

Shift representative test traffic to one region.

Validate:

``` text
CPU
memory
connections
P99
errors
```

------------------------------------------------------------------------

# Part 84 --- Failure Scenario 10: Regional Brownout

## 86. Test

Create bounded latency/resource degradation in a test region.

Validate health checks and traffic policy do not flap dangerously.

------------------------------------------------------------------------

# Part 85 --- Troubleshooting Matrix

## 87. Common Problems

  -----------------------------------------------------------------------
  Symptom                             Investigate
  ----------------------------------- -----------------------------------
  local DB healthy, remote stale      RERC/REAADB/WAN

  both regions healthy, replication   network/TLS/credentials
  degraded                            

  recovery never catches up           bandwidth/capacity/new write rate

  high P99 after partition heals      recovery load

  one region cannot rejoin            version, RERC, TLS, network

  traffic shift fails                 DNS/GSLB/LB/capacity/security

  repeated regional failover          health-check/flapping/brownout

  relationship fails after rotation   certificate/credential sequencing

  global dashboard green but app      missing application/convergence
  differs                             probe

  maintenance causes global           insufficient peer health/capacity
  degradation                         
  -----------------------------------------------------------------------

------------------------------------------------------------------------

# Part 86 --- Runbook 1: Active-Active Health Check

## 88. Procedure

``` text
1. inspect each region's local Redis health.
2. inspect RERC resources.
3. inspect REAADB.
4. inspect WAN.
5. inspect regional application SLO.
6. inspect traffic routing.
7. inspect cross-region visibility/probe.
8. classify local vs global health.
```

------------------------------------------------------------------------

# Part 87 --- Runbook 2: Replication Degradation

## 89. Procedure

``` text
1. confirm local database health.
2. inspect RERC/REAADB status.
3. inspect WAN latency/loss/bandwidth.
4. inspect TLS/credentials.
5. identify recent network/security changes.
6. protect conflict-sensitive workflows if required.
7. restore replication path.
8. validate convergence.
```

------------------------------------------------------------------------

# Part 88 --- Runbook 3: Network Partition

## 90. Procedure

``` text
1. timestamp partition.
2. identify affected regions.
3. confirm local write behavior.
4. assess business conflict exposure.
5. apply approved write/traffic policy.
6. restore network.
7. monitor backlog/convergence.
8. validate business state.
```

------------------------------------------------------------------------

# Part 89 --- Runbook 4: Backlog Recovery

## 91. Procedure

``` text
1. confirm connectivity restored.
2. monitor replication recovery.
3. monitor WAN throughput.
4. monitor Redis CPU/memory.
5. monitor application P99.
6. control noncritical load if approved.
7. wait for healthy convergence.
8. record recovery rate/time.
```

------------------------------------------------------------------------

# Part 90 --- Runbook 5: Region Outage

## 92. Procedure

``` text
1. confirm regional failure.
2. validate surviving region Redis health.
3. validate surviving capacity.
4. shift/confirm application traffic.
5. monitor errors/P99.
6. preserve failed-region evidence.
7. restore region through platform procedure.
8. follow region-rejoin runbook.
```

------------------------------------------------------------------------

# Part 91 --- Runbook 6: Region Rejoin

## 93. Procedure

``` text
1. validate Kubernetes/infrastructure.
2. validate Redis Enterprise.
3. validate RERC.
4. validate REAADB.
5. wait for synchronization/recovery.
6. validate application/security.
7. canary and ramp traffic.
8. confirm global steady state.
```

------------------------------------------------------------------------

# Part 92 --- Runbook 7: Certificate / Credential Incident

## 94. Procedure

``` text
1. identify failed trust/auth path.
2. inspect expiry/secret version.
3. confirm affected regions.
4. preserve local service availability.
5. rotate/restore using supported sequence.
6. validate remote relationship.
7. validate Active-Active convergence.
8. document rotation prevention.
```

------------------------------------------------------------------------

# Part 93 --- Runbook 8: Regional Maintenance

## 95. Procedure

``` text
1. validate all regions healthy.
2. validate synchronization.
3. validate peer capacity.
4. coordinate traffic/GitOps.
5. perform one-region maintenance.
6. validate local and global health.
7. complete soak.
8. proceed to next region only after steady state.
```

------------------------------------------------------------------------

# Part 94 --- Topology Inventory Template

## 96. Record

``` text
REAADB:
Region A:
  Kubernetes:
  REC:
  RERC:
  Endpoint:
  Redis version:
  Operator version:
Region B:
  Kubernetes:
  REC:
  RERC:
  Endpoint:
  Redis version:
  Operator version:
WAN:
Traffic routing:
Security:
Owner:
```

------------------------------------------------------------------------

# Part 95 --- Monitoring Template

## 97. Record

``` text
Local Redis metrics:
RERC metrics/status:
REAADB metrics/status:
WAN metrics:
Cross-region probe:
Regional application SLO:
Certificate alert:
Capacity alert:
Replication alert:
Dashboard:
On-call:
```

------------------------------------------------------------------------

# Part 96 --- Partition Incident Template

## 98. Record

``` text
Partition start:
Detection:
Regions:
Local DB health:
Application impact:
Both regions writing?:
Conflict-sensitive workloads:
WAN evidence:
Mitigation:
Connectivity restored:
Convergence complete:
Business validation:
Corrective action:
```

------------------------------------------------------------------------

# Part 97 --- Region Recovery Template

## 99. Record

``` text
Region:
Outage start:
Infrastructure restored:
Redis restored:
RERC healthy:
REAADB healthy:
Sync healthy:
Application validation:
Canary start:
Full traffic:
RTO:
Issues:
```

------------------------------------------------------------------------

# Part 98 --- Production Acceptance

## 100. Topology

-   [ ] all participating regions inventoried;
-   [ ] REC/RERC/REAADB mappings documented;
-   [ ] Redis/Operator versions documented;
-   [ ] WAN paths documented;
-   [ ] traffic routing documented;
-   [ ] trust/security relationships documented.

## 101. Monitoring

-   [ ] local Redis dashboards per region;
-   [ ] global Active-Active dashboard;
-   [ ] RERC/REAADB health monitored;
-   [ ] WAN latency monitored;
-   [ ] packet loss monitored;
-   [ ] bandwidth monitored;
-   [ ] regional application SLOs monitored;
-   [ ] certificate expiry monitored;
-   [ ] cross-region probe implemented where appropriate.

## 102. Capacity

-   [ ] normal regional capacity validated;
-   [ ] failure-state capacity validated;
-   [ ] traffic-shift capacity tested;
-   [ ] replication recovery headroom validated;
-   [ ] WAN recovery bandwidth validated;
-   [ ] growth forecast documented.

## 103. Recovery

-   [ ] partition response tested;
-   [ ] backlog recovery measured;
-   [ ] region outage tested/tabletopped;
-   [ ] region rejoin tested;
-   [ ] traffic canary/ramp tested;
-   [ ] certificate rotation tested;
-   [ ] credential rotation tested;
-   [ ] business validation included.

## 104. Operational Acceptance

-   [ ] change stop conditions documented;
-   [ ] one-region-at-a-time maintenance process documented;
-   [ ] ten failure scenarios completed;
-   [ ] eight runbooks reviewed;
-   [ ] production acceptance completed.

------------------------------------------------------------------------

# 105. Knowledge Validation

1.  Why can Active-Active be locally healthy but globally degraded?
2.  What resources should be included in the topology inventory?
3.  Why should RERC and REAADB be monitored directly?
4.  Why are regional labels important?
5.  What four dashboard views are useful?
6.  Why is WAN telemetry part of Active-Active observability?
7.  Why is local Redis availability insufficient?
8.  How can WAN latency affect convergence?
9.  How can packet loss affect replication?
10. Why can bandwidth saturation slow recovery?
11. Why does replication recovery require headroom?
12. What does it mean if recovery rate is below new change rate?
13. Why can application retries worsen a degraded event?
14. How should surviving-region capacity be calculated conceptually?
15. Why is traffic routing separate from Redis Active-Active?
16. What risk exists with automatic regional failover?
17. Why should regional maintenance begin only when peers are healthy?
18. Why should mixed-version support be verified?
19. Why can certificate expiry break Active-Active while local Redis
    remains healthy?
20. Why must credential rotation be coordinated?
21. Why is a partition operationally important even if both regions
    serve traffic?
22. Why might an application restrict some writes during a partition?
23. Why is restored network connectivity not the end of recovery?
24. What dependencies beyond Redis can break regional failover?
25. Why should a returning region be canaried before full traffic?
26. What is a regional brownout?
27. Why is clock alignment useful for incident response?
28. Why can synthetic cross-region probes add value?
29. Why should destructive resource deletion not be the first
    troubleshooting action?
30. What must pass before Active-Active operations are production-ready?

------------------------------------------------------------------------

# 106. Hands-On Acceptance Checklist

-   [ ] Built Active-Active topology inventory.
-   [ ] Mapped REC/RERC/REAADB resources.
-   [ ] Recorded Redis/Operator versions.
-   [ ] Documented regional endpoints.
-   [ ] Documented traffic routing.
-   [ ] Built per-region application dashboard.
-   [ ] Built per-region Redis dashboard.
-   [ ] Built Active-Active health dashboard.
-   [ ] Built WAN dashboard.
-   [ ] Recorded healthy baseline.
-   [ ] Defined Active-Active alerts.
-   [ ] Monitored certificate expiry.
-   [ ] Validated regional capacity.
-   [ ] Validated failure-state capacity.
-   [ ] Tested traffic-shift capacity.
-   [ ] Implemented safe cross-region probe where appropriate.
-   [ ] Tested WAN latency degradation.
-   [ ] Tested bounded packet loss.
-   [ ] Tested network partition.
-   [ ] Measured backlog recovery.
-   [ ] Tested region outage.
-   [ ] Tested region rejoin.
-   [ ] Tested certificate failure/rotation.
-   [ ] Tested credential failure/rotation.
-   [ ] Tested regional brownout.
-   [ ] Validated business state after recovery.
-   [ ] Completed ten failure scenarios.
-   [ ] Completed eight runbooks.
-   [ ] Completed production acceptance.

------------------------------------------------------------------------

# 107. Cleanup

Remove only disposable Chapter 66 test resources.

For probe keys under:

``` text
tutorial:chapter66:*
```

use safe `SCAN` plus `UNLINK` cleanup.

Do not use:

``` text
FLUSHDB
FLUSHALL
```

on shared environments.

Restore:

``` text
fault-injection rules
test WAN restrictions
test certificates
test credentials
test DNS/GSLB weights
test traffic routing
temporary lab resources
```

Confirm:

``` text
all participating regions healthy
RERC healthy
REAADB healthy
replication/synchronization healthy
WAN baseline restored
traffic routing normal
application P99 normal
no recovery backlog
```

------------------------------------------------------------------------

# 108. Key Takeaways

1.  Active-Active operations require separate local and global health
    views.
2.  Both regions can look healthy while replication is broken.
3.  RERC and REAADB status are important operational evidence.
4.  Regional labels make multi-region incidents diagnosable.
5.  Application, Redis, Active-Active, and WAN dashboards should be
    correlated.
6.  WAN latency, loss, and bandwidth directly influence replication
    health and recovery.
7.  Recovery capacity must exceed ongoing change pressure.
8.  Regional sizing must account for shifted traffic and synchronization
    overhead.
9.  Traffic routing is a separate system from Redis Active-Active.
10. Automatic regional failover needs anti-flapping and capacity
    safeguards.
11. Regional maintenance should start only from globally healthy state.
12. Mixed-version support must be verified before regional upgrades.
13. Certificates and credentials are part of the replication path.
14. Network/security changes must include Active-Active validation.
15. A network partition can create business risk even when local
    databases stay available.
16. Some applications may intentionally restrict conflict-sensitive
    operations during partitions.
17. Restoring connectivity begins recovery; it does not complete it.
18. Region failover depends on application and platform dependencies
    beyond Redis.
19. Returning regions must synchronize before full traffic resumes.
20. Regional brownouts require SLO-based traffic decisions.
21. Synthetic cross-region probes can expose user-visible convergence
    issues.
22. Recovery traffic can itself create CPU/network/P99 pressure.
23. Active-Active changes should normally be introduced one region at a
    time where supported.
24. Failure drills must validate application correctness, not only Redis
    health.
25. Production readiness requires topology, observability, failure-state
    capacity, partition recovery, region rejoin, security rotation,
    traffic management, and tested runbooks together.

------------------------------------------------------------------------

# 109. References

Validate Active-Active status fields, metrics, replication behavior,
remote-cluster configuration, certificate/credential procedures,
mixed-version support, maintenance procedures, and recovery behavior
against the exact deployed Redis Enterprise version, Redis Enterprise
Kubernetes Operator version, and current official Redis documentation.

Recommended documentation areas:

-   Redis Enterprise Active-Active
-   Redis Enterprise Active-Active operations
-   Redis Enterprise Active-Active monitoring
-   Redis Enterprise Active-Active networking
-   Redis Enterprise Active-Active recovery
-   Redis Enterprise Active-Active Kubernetes
-   RedisEnterpriseRemoteCluster
-   RedisEnterpriseActiveActiveDatabase
-   Redis Enterprise security and TLS
-   Redis Enterprise upgrade compatibility
-   Kubernetes multi-cluster networking
-   cloud-provider inter-region networking
-   DNS/GSLB/load-balancer documentation
-   application retry and idempotency engineering

------------------------------------------------------------------------

# Next Chapter

**Chapter 67 --- Redis Enterprise Active-Active Regional Cutover, Rejoin
& Failback Engineering**

Chapter 67 will focus on controlled regional traffic movement and
disaster operations: planned cutover, emergency failover,
surviving-region validation, traffic steering, application dependencies,
region restoration, synchronization gates, canary re-entry, failback,
split-brain/business-conflict prevention, RTO evidence, failure
scenarios, troubleshooting, runbooks, and production acceptance.
