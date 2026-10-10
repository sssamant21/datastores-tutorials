# Chapter 67 --- Redis Enterprise Active-Active Regional Cutover, Rejoin & Failback Engineering

**Status:** Canonical\
**Track:** Redis Enterprise / Redis Software Production Engineering\
**Part:** Part 11 --- Advanced Kubernetes, Active-Active & Platform
Engineering\
**Level:** Advanced → Regional Traffic Movement, Disaster Recovery &
Failback Engineering\
**Audience:** SREs, DBREs, Platform Engineers, Redis Administrators,
Kubernetes Administrators, Cloud Engineers, Application Architects,
Incident Commanders\
**Lab type:** Planned regional cutover, emergency failover, traffic
steering, surviving-region validation, region restoration, Active-Active
synchronization, canary re-entry, failback, RTO/RPO evidence, failure
injection, troubleshooting, runbooks, and production acceptance

------------------------------------------------------------------------

# 1. Objective

Active-Active means multiple regions can host writable Redis Enterprise
database instances according to supported product semantics.

It does not mean application traffic automatically moves safely between
regions.

Regional disaster engineering therefore has several distinct operations:

``` text
planned cutover
emergency failover / traffic evacuation
region rejoin
failback
```

These operations should not be treated as synonyms.

A safe workflow must coordinate:

``` text
Redis Enterprise
Active-Active replication
application traffic
DNS / GSLB / load balancers
Kubernetes
regional dependencies
capacity
security
business correctness
```

By the end of this chapter, you should be able to:

-   distinguish planned cutover, emergency failover, rejoin, and
    failback;
-   define regional readiness gates;
-   validate surviving-region capacity;
-   shift application traffic safely;
-   protect conflict-sensitive workflows;
-   measure RTO and application impact;
-   restore a failed region;
-   validate Active-Active synchronization before re-entry;
-   canary a returning region;
-   perform controlled failback;
-   prevent traffic flapping;
-   execute regional DR drills;
-   troubleshoot failed cutover/rejoin/failback;
-   execute production runbooks and acceptance gates.

------------------------------------------------------------------------

# 2. Core Production Principle

A region becoming reachable is not the same as a region being ready.

Before traffic returns, validate:

``` text
infrastructure healthy
Kubernetes healthy
Redis healthy
Active-Active relationship healthy
synchronization healthy
application dependencies healthy
security valid
capacity sufficient
```

Then return traffic gradually.

------------------------------------------------------------------------

# Part 1 --- Terminology

## 3. Planned Cutover

A deliberate traffic movement performed while both regions are expected
to be healthy.

Examples:

``` text
maintenance
regional infrastructure work
DR exercise
planned application migration
```

------------------------------------------------------------------------

# Part 2 --- Emergency Failover

## 4. Definition

Traffic is moved away from a failed or severely degraded region.

The priority is:

``` text
restore acceptable service
```

while preserving data/business correctness.

------------------------------------------------------------------------

# Part 3 --- Rejoin

## 5. Definition

A previously unavailable or isolated region returns to the Active-Active
topology and synchronizes.

Rejoin is not yet failback.

------------------------------------------------------------------------

# Part 4 --- Failback

## 6. Definition

Application traffic is deliberately returned to the recovered region
after rejoin and validation.

------------------------------------------------------------------------

# Part 5 --- Why Separate Them

## 7. State Machine

``` text
Normal
  |
  +--> Planned Cutover
  |
  +--> Emergency Failover
             |
             v
        Region Restore
             |
             v
           Rejoin
             |
             v
        Validation/Soak
             |
             v
          Failback
```

Each transition needs its own gates.

------------------------------------------------------------------------

# Part 6 --- Regional Architecture Inventory

## 8. Record

For every region:

``` text
Kubernetes cluster
REC
RERC
REAADB
Redis endpoint
application services
DNS/GSLB/LB
identity/auth
secrets
upstream databases
message brokers
external APIs
network dependencies
```

------------------------------------------------------------------------

# Part 7 --- Dependency Graph

## 9. Redis Is One Dependency

A region may have healthy Redis but unusable application services
because another dependency is unavailable.

Build:

``` text
user
 -> global traffic
 -> application
 -> Redis
 -> source systems
 -> identity
 -> messaging
```

------------------------------------------------------------------------

# Part 8 --- Traffic Steering Inventory

## 10. Document

``` text
DNS records
TTL
GSLB policy
LB health checks
regional weights
failover policy
manual controls
automation
```

------------------------------------------------------------------------

# Part 9 --- Data Path Inventory

## 11. Document

``` text
which region normally serves which users?
which regions write which keys?
home-region rules?
global writers?
conflict-sensitive workflows?
```

Chapter 65 provides the semantic foundation.

------------------------------------------------------------------------

# Part 10 --- Normal State

## 12. Baseline

Before DR testing, record:

``` text
traffic split
regional P99
error rate
Redis throughput
CPU
memory
connections
WAN replication
cross-region convergence
```

------------------------------------------------------------------------

# Part 11 --- Regional Readiness Gate

## 13. Before Receiving Traffic

A region should pass:

``` text
Kubernetes health
Redis Enterprise health
REAADB health
RERC health
endpoint health
TLS/auth
application health
dependency health
capacity
```

------------------------------------------------------------------------

# Part 12 --- Surviving Region Gate

## 14. Before Evacuation

Before moving traffic from Region A to Region B, ask:

``` text
Can B safely absorb A's traffic?
```

Validate using measured data.

------------------------------------------------------------------------

# Part 13 --- Failure-State Capacity

## 15. Model

``` text
target capacity requirement
=
existing target load
+ shifted source load
+ Active-Active recovery overhead
+ safety headroom
```

------------------------------------------------------------------------

# Part 14 --- CPU

## 16. Validate

Estimate and test CPU after traffic concentration.

Do not rely only on average CPU.

Review:

``` text
peak
P95
headroom
```

------------------------------------------------------------------------

# Part 15 --- Memory

## 17. Validate

Traffic shift may increase:

``` text
connections
working set
temporary buffers
application cache activity
```

Ensure memory remains safe.

------------------------------------------------------------------------

# Part 16 --- Connections

## 18. Client Surge

Regional failover can cause:

``` text
connection storm
DNS re-resolution
pool recreation
TLS handshakes
```

Test this.

------------------------------------------------------------------------

# Part 17 --- Network

## 19. Validate

Surviving region needs capacity for:

``` text
client traffic
application traffic
replication/recovery
backup/monitoring
```

------------------------------------------------------------------------

# Part 18 --- Storage

## 20. Validate

Redis recovery or persistence activity may increase storage I/O during
regional events.

Include storage headroom.

------------------------------------------------------------------------

# Part 19 --- Planned Cutover Preconditions

## 21. Require

``` text
both regions healthy
Active-Active synchronized
WAN healthy
target capacity validated
backup/recovery healthy
traffic controls tested
owners available
rollback plan ready
```

------------------------------------------------------------------------

# Part 20 --- Planned Cutover Freeze

## 22. Reduce Change

Avoid unrelated:

``` text
deployments
schema changes
Redis upgrades
network changes
certificate rotations
bulk jobs
```

during the cutover window.

------------------------------------------------------------------------

# Part 21 --- Planned Cutover Traffic Ramp

## 23. Example

If traffic tooling supports weighted routing:

``` text
50/50
 -> 25/75
 -> 10/90
 -> 0/100
```

or another approved progression.

The exact percentages are workload-specific.

------------------------------------------------------------------------

# Part 22 --- Cutover Observation

## 24. At Each Step

Monitor:

``` text
source P99/errors
target P99/errors
target CPU/memory
connections
Redis health
Active-Active health
business KPIs
```

------------------------------------------------------------------------

# Part 23 --- Cutover Stop Conditions

## 25. Examples

Stop or reverse if:

``` text
target error rate exceeds threshold
target P99 exceeds threshold
Redis health degrades
capacity headroom becomes unsafe
Active-Active relationship degrades
business validation fails
```

------------------------------------------------------------------------

# Part 24 --- Planned Cutover Completion

## 26. Validate

At 100% target traffic:

``` text
source stable
target stable
Active-Active healthy
business workflows pass
no unexpected retry storm
```

------------------------------------------------------------------------

# Part 25 --- Emergency Detection

## 27. Signals

A regional incident may begin with:

``` text
application errors
high P99
regional LB failure
Kubernetes outage
Redis outage
network partition
cloud-region event
```

------------------------------------------------------------------------

# Part 26 --- Emergency Decision

## 28. Ask

``` text
Is the region failed?
Is it degraded?
Is Redis affected?
Is traffic path affected?
Is Active-Active replication affected?
Can the surviving region absorb traffic?
```

------------------------------------------------------------------------

# Part 27 --- Failover Trigger

## 29. Business SLO

Trigger should be based on:

``` text
availability
latency
error rate
dependency health
regional capacity
```

not simply one pod restart.

------------------------------------------------------------------------

# Part 28 --- Brownout

## 30. Difficult Case

A region may remain reachable but perform poorly.

Examples:

``` text
P99 10x normal
packet loss
storage latency
partial dependency failure
```

Traffic policy must handle brownouts.

------------------------------------------------------------------------

# Part 29 --- Avoid Flapping

## 31. Hold-Down

Do not repeatedly shift traffic:

``` text
A -> B -> A -> B
```

during unstable recovery.

Define a stability period.

------------------------------------------------------------------------

# Part 30 --- Emergency Traffic Shift

## 32. Sequence

Conceptually:

``` text
confirm target readiness
 -> shift traffic
 -> validate target
 -> stabilize service
 -> investigate failed region
```

------------------------------------------------------------------------

# Part 31 --- Emergency vs Planned Ramp

## 33. Tradeoff

Emergency failover may need faster movement than planned cutover.

Still use the safest feasible staged approach if the incident allows it.

------------------------------------------------------------------------

# Part 32 --- Conflict-Sensitive Writes

## 34. During Partition

If both regions are alive but disconnected, application policy may need
to restrict workflows whose invariants cannot tolerate independent
writes.

Examples:

``` text
scarce inventory
exclusive workflow transitions
coordination state
```

------------------------------------------------------------------------

# Part 33 --- Write Fencing

## 35. Application Concept

Some designs intentionally designate one region as the temporary
authority for selected business operations during a partition.

This is application architecture.

Do not implement ad-hoc fencing by deleting Redis resources.

------------------------------------------------------------------------

# Part 34 --- Idempotency

## 36. During Failover

Clients may retry requests when traffic moves.

Use stable operation IDs so retries do not duplicate business effects.

------------------------------------------------------------------------

# Part 35 --- DNS-Based Failover

## 37. Consider

``` text
record TTL
resolver caching
JVM/runtime DNS cache
existing TCP connections
```

DNS change does not instantly move all traffic.

------------------------------------------------------------------------

# Part 36 --- GSLB / Weighted Routing

## 38. Benefit

Global traffic systems can provide controlled regional weights and
health-based routing.

Test actual behavior.

------------------------------------------------------------------------

# Part 37 --- Existing Connections

## 39. Important

Even after routing changes, existing Redis/application connections may
remain pointed at the previous region.

Understand connection lifetime.

------------------------------------------------------------------------

# Part 38 --- Connection Drain

## 40. Planned Cutover

Where supported, drain old connections gracefully rather than abruptly
resetting all clients.

------------------------------------------------------------------------

# Part 39 --- TLS / Credentials

## 41. Target Region

Before traffic shift validate:

``` text
certificate trust
credentials
secret versions
endpoint hostname
```

A DR endpoint is useless if clients cannot authenticate.

------------------------------------------------------------------------

# Part 40 --- Application Configuration

## 42. Validate

Ensure the target region has:

``` text
correct Redis endpoint
feature flags
secrets
dependencies
application version
```

------------------------------------------------------------------------

# Part 41 --- Regional Version Drift

## 43. Risk

If application versions differ:

``` text
Region A = v2
Region B = v1
```

failover can expose data/schema incompatibility.

Maintain compatible deployments.

------------------------------------------------------------------------

# Part 42 --- Region Failure Evidence

## 44. Preserve

Capture:

``` text
incident start
application symptoms
Redis status
RERC/REAADB status
WAN
Kubernetes
recent changes
traffic actions
```

------------------------------------------------------------------------

# Part 43 --- RTO Clock

## 45. Define

Decide when RTO measurement begins.

Example:

``` text
business-impact start -> service restored
```

Use one consistent organizational definition.

------------------------------------------------------------------------

# Part 44 --- RPO in Active-Active

## 46. Understand

Active-Active can reduce some regional data-loss scenarios, but RPO
depends on:

``` text
replication state
partition timing
business semantics
backup/recovery
```

Do not advertise zero RPO without validated guarantees.

------------------------------------------------------------------------

# Part 45 --- Service Restoration

## 47. RTO End

Do not stop the clock merely because DNS changed.

Service restoration should require agreed application-level success
criteria.

------------------------------------------------------------------------

# Part 46 --- Failed Region Isolation

## 48. Stabilize

During severe failure, avoid uncontrolled partial return.

Keep traffic policy deliberate until the region passes recovery gates.

------------------------------------------------------------------------

# Part 47 --- Region Infrastructure Restore

## 49. Validate

Check:

``` text
cloud/datacenter health
Kubernetes control plane
nodes
storage
CNI
CSI
DNS
load balancers
```

------------------------------------------------------------------------

# Part 48 --- Redis Restore

## 50. Validate

Check:

``` text
Operator
REC
REDB/local database
RERC
REAADB
Redis node/shard health
```

------------------------------------------------------------------------

# Part 49 --- Rejoin Gate 1: Local Health

## 51. Require

Returning region must be locally healthy before multi-region recovery is
trusted.

------------------------------------------------------------------------

# Part 50 --- Rejoin Gate 2: Remote Relationship

## 52. Require

Validate RERC/remote relationship state.

------------------------------------------------------------------------

# Part 51 --- Rejoin Gate 3: Active-Active State

## 53. Require

Validate REAADB/product-supported synchronization state.

------------------------------------------------------------------------

# Part 52 --- Rejoin Gate 4: Recovery Load

## 54. Monitor

During synchronization:

``` text
CPU
memory
network
storage
application P99
```

------------------------------------------------------------------------

# Part 53 --- Rejoin Gate 5: Business Validation

## 55. Require

Test representative:

``` text
reads
writes
TTL
critical workflows
conflict-sensitive entities
```

------------------------------------------------------------------------

# Part 54 --- Rejoin Gate 6: Application Dependencies

## 56. Require

Validate:

``` text
identity
upstream DB
messaging
external APIs
secrets
certificates
```

------------------------------------------------------------------------

# Part 55 --- Do Not Route Yet

## 57. Principle

A region can participate in Redis synchronization while still receiving
zero user traffic.

Use that period for validation.

------------------------------------------------------------------------

# Part 56 --- Soak

## 58. Stability

Observe the returning region for an approved interval.

Watch:

``` text
Redis
Active-Active
WAN
Kubernetes
application synthetic tests
```

------------------------------------------------------------------------

# Part 57 --- Canary Re-Entry

## 59. First Traffic

Send a small percentage or selected synthetic/internal traffic first.

Monitor before expanding.

------------------------------------------------------------------------

# Part 58 --- Failback Ramp

## 60. Example

``` text
0/100
 -> 5/95
 -> 25/75
 -> 50/50
```

or the organization's intended normal split.

Use workload-specific stages.

------------------------------------------------------------------------

# Part 59 --- Failback Stop Conditions

## 61. Examples

Stop/reverse if:

``` text
returning-region P99 rises
errors rise
Redis degrades
replication degrades
business validation fails
dependency fails
```

------------------------------------------------------------------------

# Part 60 --- Failback Completion

## 62. Require

``` text
normal traffic policy restored
both regions healthy
Active-Active healthy
business KPIs normal
capacity headroom restored
alerts clear
```

------------------------------------------------------------------------

# Part 61 --- Failback Is a Change

## 63. Important

Do not treat failback as cleanup.

It is another production traffic change with its own risk.

------------------------------------------------------------------------

# Part 62 --- Regional DR Drill

## 64. Purpose

A DR plan is not validated until tested.

A drill should exercise:

``` text
detection
decision
traffic movement
surviving capacity
application correctness
region restoration
rejoin
failback
```

------------------------------------------------------------------------

# Part 63 --- Drill Safety

## 65. Preconditions

Define:

``` text
scope
owners
stop conditions
communication
fault boundary
recovery path
```

------------------------------------------------------------------------

# Part 64 --- Drill Types

## 66. Progressive

Start with:

``` text
tabletop
synthetic traffic
nonproduction failover
production controlled exercise
```

according to organizational risk tolerance.

------------------------------------------------------------------------

# Part 65 --- Tabletop

## 67. Questions

``` text
Who declares regional failure?
Who changes traffic?
Who validates Redis?
Who validates business?
Who authorizes failback?
```

------------------------------------------------------------------------

# Part 66 --- Synthetic Drill

## 68. Safer

Use isolated:

``` text
test users
test endpoints
test keys
```

to validate routing and Active-Active behavior.

------------------------------------------------------------------------

# Part 67 --- Production Exercise

## 69. Controlled

Only perform with:

``` text
approval
observability
capacity evidence
recovery plan
experienced owners
```

------------------------------------------------------------------------

# Part 68 --- RTO Evidence

## 70. Timeline

Record:

``` text
T0 impact
T1 detection
T2 failover decision
T3 traffic action
T4 service restored
T5 failed region restored
T6 rejoin complete
T7 failback complete
```

------------------------------------------------------------------------

# Part 69 --- Decision Time

## 71. Often Significant

RTO includes human/automation decision latency.

Measure it.

------------------------------------------------------------------------

# Part 70 --- DNS Time

## 72. Often Significant

If DNS is involved, actual client movement may lag the record update.

Measure client-visible transition.

------------------------------------------------------------------------

# Part 71 --- Connection Recovery Time

## 73. Measure

Track:

``` text
connection errors
reconnect rate
pool recovery
```

during traffic movement.

------------------------------------------------------------------------

# Part 72 --- Business Recovery Time

## 74. Most Important

Measure when critical business operations succeed again.

------------------------------------------------------------------------

# Part 73 --- Regional Capacity Test

## 75. Before DR

Regularly test the target region at expected failover load.

A spreadsheet estimate is not enough.

------------------------------------------------------------------------

# Part 74 --- Burst Failover Load

## 76. Test

Regional failover may create a sudden step increase.

Test:

``` text
steady failover load
+
connection burst
+
retry burst
```

------------------------------------------------------------------------

# Part 75 --- Recovery + Failover Load

## 77. Worst Case

A returning region may synchronize while the surviving region still
carries concentrated application traffic.

Model this combined state.

------------------------------------------------------------------------

# Part 76 --- Data Validation

## 78. After Failover

Validate representative business data, not just key counts.

------------------------------------------------------------------------

# Part 77 --- Conflict Review

## 79. After Partition

Identify workflows that wrote in multiple disconnected regions.

Run conflict/business-correctness checks from Chapter 65.

------------------------------------------------------------------------

# Part 78 --- Audit Trail

## 80. Keep

Record:

``` text
traffic changes
Redis state
operator actions
business mitigations
approvals
timestamps
```

------------------------------------------------------------------------

# Part 79 --- Automation

## 81. Safe Automation

Automate repeatable checks such as:

``` text
regional readiness
capacity
endpoint health
RERC/REAADB status
```

Do not automate destructive failover decisions without governance.

------------------------------------------------------------------------

# Part 80 --- Preflight Script

## 82. Concept

A regional cutover preflight can produce:

``` text
PASS/FAIL:
- source healthy
- target healthy
- Active-Active healthy
- capacity safe
- dependencies safe
- traffic controls available
```

------------------------------------------------------------------------

# Part 81 --- Postflight Script

## 83. Concept

Validate:

``` text
traffic distribution
regional SLO
Redis health
Active-Active health
business probes
```

------------------------------------------------------------------------

# Part 82 --- Failure Scenario 1: Target Capacity Insufficient

## 84. Test

Model or load-test target region below required failover capacity.

Expected:

``` text
preflight blocks cutover
```

------------------------------------------------------------------------

# Part 83 --- Failure Scenario 2: DNS Cache Delay

## 85. Test

Change a test routing record and measure actual client movement.

Validate expected TTL/cache behavior.

------------------------------------------------------------------------

# Part 84 --- Failure Scenario 3: Connection Storm

## 86. Test

Simulate regional client reconnection in nonproduction.

Measure:

``` text
connections/sec
CPU
TLS
P99
errors
```

------------------------------------------------------------------------

# Part 85 --- Failure Scenario 4: Partial Region Brownout

## 87. Test

Degrade a test region without fully failing it.

Validate traffic policy and hold-down behavior.

------------------------------------------------------------------------

# Part 86 --- Failure Scenario 5: Network Partition

## 88. Test

Partition Active-Active test regions while both remain locally
available.

Validate conflict-sensitive write policy.

------------------------------------------------------------------------

# Part 87 --- Failure Scenario 6: Emergency Region Failover

## 89. Test

Fail one test region and move traffic.

Measure service RTO.

------------------------------------------------------------------------

# Part 88 --- Failure Scenario 7: Region Returns but Not Synced

## 90. Test

Restore infrastructure but intentionally hold traffic at zero until
synchronization gate passes.

Validate no premature failback.

------------------------------------------------------------------------

# Part 89 --- Failure Scenario 8: Rejoin Recovery Load

## 91. Test

Measure CPU/network/P99 while a test region catches up.

Validate headroom.

------------------------------------------------------------------------

# Part 90 --- Failure Scenario 9: Failback Canary Fails

## 92. Test

Create a safe test dependency/application issue in the returning region.

Verify canary catches it and traffic ramp stops.

------------------------------------------------------------------------

# Part 91 --- Failure Scenario 10: Traffic Flapping

## 93. Test/Tabletop

Simulate alternating health signals.

Validate:

``` text
hold-down
stability gate
manual override
```

prevents repeated failover/failback.

------------------------------------------------------------------------

# Part 92 --- Troubleshooting Matrix

## 94. Common Problems

  -----------------------------------------------------------------------------------
  Symptom                             Investigate
  ----------------------------------- -----------------------------------------------
  target region overloads after shift capacity/connections/retries

  DNS changed but clients remain      resolver/client cache/existing connections

  failover works but business action  dependency/config/security
  fails                               

  region returns but REAADB unhealthy RERC/WAN/version/TLS

  rejoin takes too long               backlog/network/CPU/storage

  failback increases P99              target capacity/dependency/recovery

  traffic repeatedly moves regions    health-check/hold-down/flapping

  both regions wrote conflicting      Chapter 65 invariant handling
  workflow                            

  Redis healthy but region not ready  application dependencies

  RTO missed                          detection/decision/routing/reconnect/capacity
  -----------------------------------------------------------------------------------

------------------------------------------------------------------------

# Part 93 --- Runbook 1: Planned Regional Cutover

## 95. Procedure

``` text
1. validate both regions and Active-Active.
2. validate target failure-state capacity.
3. validate dependencies/security.
4. freeze unrelated changes.
5. shift traffic in approved stages.
6. validate each stage.
7. reach target traffic state.
8. complete soak/evidence.
```

------------------------------------------------------------------------

# Part 94 --- Runbook 2: Emergency Regional Failover

## 96. Procedure

``` text
1. confirm regional business impact.
2. validate surviving region readiness.
3. assess partition/conflict-sensitive writes.
4. shift traffic using emergency policy.
5. monitor P99/errors/capacity.
6. validate critical business operations.
7. stabilize service.
8. preserve incident evidence.
```

------------------------------------------------------------------------

# Part 95 --- Runbook 3: Regional Brownout

## 97. Procedure

``` text
1. confirm degraded SLO.
2. identify Redis vs infrastructure vs dependency.
3. validate peer capacity.
4. reduce/shift traffic if threshold met.
5. prevent flapping.
6. repair degraded region.
7. pass stability gate.
8. reintroduce traffic deliberately.
```

------------------------------------------------------------------------

# Part 96 --- Runbook 4: Region Rejoin

## 98. Procedure

``` text
1. restore infrastructure.
2. validate Kubernetes.
3. validate Redis Enterprise.
4. validate RERC/REAADB.
5. monitor synchronization.
6. validate business/application dependencies.
7. soak at zero user traffic.
8. approve canary re-entry.
```

------------------------------------------------------------------------

# Part 97 --- Runbook 5: Failback

## 99. Procedure

``` text
1. confirm rejoin gates passed.
2. confirm stability interval.
3. confirm returning-region capacity.
4. send canary traffic.
5. validate SLO/business.
6. ramp in stages.
7. restore normal routing.
8. complete global validation.
```

------------------------------------------------------------------------

# Part 98 --- Runbook 6: Failed Failback

## 100. Procedure

``` text
1. stop traffic ramp.
2. return traffic to known-good region.
3. capture failing-region evidence.
4. classify Redis/application/dependency issue.
5. remediate.
6. repeat readiness/soak.
7. retry canary only after approval.
8. document corrective action.
```

------------------------------------------------------------------------

# Part 99 --- Runbook 7: Network Partition with Dual Writers

## 101. Procedure

``` text
1. confirm partition.
2. identify workloads writing in both regions.
3. apply approved conflict-sensitive write policy.
4. preserve operation IDs/logs.
5. restore WAN.
6. monitor convergence.
7. validate business invariants.
8. repair business state if required.
```

------------------------------------------------------------------------

# Part 100 --- Runbook 8: DR Exercise

## 102. Procedure

``` text
1. define scenario and objectives.
2. capture healthy baseline.
3. initiate approved failure.
4. detect/declare/shift traffic.
5. measure service restoration.
6. restore/rejoin failed region.
7. fail back.
8. review RTO/RPO/gaps/actions.
```

------------------------------------------------------------------------

# Part 101 --- Cutover Checklist Template

## 103. Record

``` text
Source region:
Target region:
Reason:
Source healthy:
Target healthy:
Active-Active healthy:
Target capacity:
Dependencies:
Security:
Traffic method:
Stages:
Stop conditions:
Rollback:
Owners:
```

------------------------------------------------------------------------

# Part 102 --- Regional Readiness Template

## 104. Record

``` text
Region:
Kubernetes:
Operator:
REC:
RERC:
REAADB:
Redis:
Endpoint:
TLS:
Credentials:
Application:
Identity:
Messaging:
Upstream DB:
External APIs:
CPU headroom:
Memory headroom:
Network headroom:
Status:
```

------------------------------------------------------------------------

# Part 103 --- DR Timeline Template

## 105. Record

``` text
Impact start:
Detection:
Incident declared:
Failover decision:
Traffic change start:
Critical service restored:
Failed region infrastructure restored:
Redis restored:
Rejoin healthy:
Canary:
Failback complete:
RTO:
RPO assessment:
```

------------------------------------------------------------------------

# Part 104 --- Failback Checklist Template

## 106. Record

``` text
Returning region:
Infrastructure healthy:
Redis healthy:
RERC healthy:
REAADB healthy:
Synchronization healthy:
Application dependencies:
Security:
Soak complete:
Canary result:
Ramp stages:
Stop conditions:
Normal routing restored:
```

------------------------------------------------------------------------

# Part 105 --- Production Acceptance

## 107. Architecture

-   [ ] regional dependency graph documented;
-   [ ] traffic steering documented;
-   [ ] normal traffic split documented;
-   [ ] regional data/write ownership documented;
-   [ ] conflict-sensitive workflows documented;
-   [ ] Active-Active resources documented.

## 108. Capacity

-   [ ] surviving-region CPU tested;
-   [ ] memory tested;
-   [ ] connection surge tested;
-   [ ] network tested;
-   [ ] storage/recovery headroom tested;
-   [ ] combined failover + recovery state modeled.

## 109. Traffic Operations

-   [ ] planned cutover tested;
-   [ ] emergency failover tested;
-   [ ] DNS/GSLB behavior measured;
-   [ ] existing connection behavior understood;
-   [ ] brownout policy tested;
-   [ ] anti-flapping/hold-down configured;
-   [ ] canary/ramp procedure tested.

## 110. Rejoin / Failback

-   [ ] local health gate documented;
-   [ ] RERC gate documented;
-   [ ] REAADB/sync gate documented;
-   [ ] business validation gate documented;
-   [ ] dependency gate documented;
-   [ ] zero-traffic soak tested;
-   [ ] failback tested;
-   [ ] failed-failback rollback tested.

## 111. DR Acceptance

-   [ ] RTO definition approved;
-   [ ] RPO assessment method approved;
-   [ ] DR timeline evidence captured;
-   [ ] business recovery measured;
-   [ ] ten failure scenarios completed;
-   [ ] eight runbooks reviewed;
-   [ ] production acceptance completed.

------------------------------------------------------------------------

# 112. Knowledge Validation

1.  What is the difference between planned cutover and emergency
    failover?
2.  What is region rejoin?
3.  Why is rejoin not the same as failback?
4.  Why is failback a production change?
5.  Why must regional dependencies beyond Redis be inventoried?
6.  What belongs in a traffic-steering inventory?
7.  Why must the target region pass a readiness gate?
8.  How should failure-state capacity be modeled conceptually?
9.  Why can connection storms matter during failover?
10. Why should planned cutover use staged traffic movement?
11. What should cause a cutover to stop?
12. Why can a regional brownout be harder than a total outage?
13. Why should traffic flapping be prevented?
14. Why may conflict-sensitive writes need special policy during a
    partition?
15. Why is idempotency important during traffic movement?
16. Why does a DNS update not move all traffic instantly?
17. Why do existing connections matter?
18. Why must TLS and credentials be validated in the target region?
19. Why can regional application-version drift break failover?
20. When should the RTO clock stop?
21. Why should zero RPO not be assumed?
22. Why should a failed region remain isolated until recovery gates
    pass?
23. What must be validated before Active-Active rejoin is considered
    healthy?
24. Why should a returning region soak with zero user traffic?
25. Why use a canary before failback?
26. Why should DR exercises measure decision time?
27. Why must failover capacity be load-tested rather than estimated
    only?
28. Why validate business data after a partition?
29. Why is an audit trail important?
30. What must pass before regional cutover/rejoin/failback is
    production-ready?

------------------------------------------------------------------------

# 113. Hands-On Acceptance Checklist

-   [ ] Built regional dependency graph.
-   [ ] Documented traffic steering.
-   [ ] Documented normal traffic split.
-   [ ] Documented regional write patterns.
-   [ ] Identified conflict-sensitive workflows.
-   [ ] Recorded healthy baseline.
-   [ ] Defined regional readiness gates.
-   [ ] Tested surviving-region CPU capacity.
-   [ ] Tested memory capacity.
-   [ ] Tested connection surge.
-   [ ] Tested network capacity.
-   [ ] Tested planned traffic ramp.
-   [ ] Defined cutover stop conditions.
-   [ ] Tested DNS/GSLB transition.
-   [ ] Measured existing-connection behavior.
-   [ ] Tested brownout policy.
-   [ ] Tested anti-flapping behavior.
-   [ ] Tested emergency regional failover.
-   [ ] Measured RTO.
-   [ ] Assessed RPO.
-   [ ] Restored failed test region.
-   [ ] Validated RERC.
-   [ ] Validated REAADB/synchronization.
-   [ ] Performed zero-traffic soak.
-   [ ] Performed canary re-entry.
-   [ ] Performed staged failback.
-   [ ] Tested failed-failback rollback.
-   [ ] Validated business state.
-   [ ] Completed ten failure scenarios.
-   [ ] Completed eight runbooks.
-   [ ] Completed production acceptance.

------------------------------------------------------------------------

# 114. Cleanup

Remove only disposable Chapter 67 test resources.

Restore:

``` text
normal DNS/GSLB weights
test routing rules
fault-injection settings
temporary write restrictions
test certificates/credentials
temporary synthetic workloads
```

For lab keys under:

``` text
tutorial:chapter67:*
```

use safe `SCAN` plus `UNLINK`.

Do not use:

``` text
FLUSHDB
FLUSHALL
```

on shared environments.

Confirm:

``` text
normal traffic distribution restored
all regions healthy
RERC healthy
REAADB healthy
synchronization healthy
WAN normal
application P99 normal
business checks pass
no temporary DR controls remain
```

------------------------------------------------------------------------

# 115. Key Takeaways

1.  Planned cutover, emergency failover, rejoin, and failback are
    separate operational states.
2.  A reachable region is not automatically ready for production
    traffic.
3.  Redis is only one dependency in regional application recovery.
4.  Traffic steering must be documented and tested.
5.  Surviving-region capacity must include shifted workload, recovery
    overhead, and safety headroom.
6.  Connection storms and retries are part of regional failover
    capacity.
7.  Planned cutovers should use staged traffic movement and stop
    conditions.
8.  Brownouts require deliberate SLO-based traffic decisions.
9.  Anti-flapping controls prevent unstable repeated failover/failback.
10. Conflict-sensitive writes may need application-level controls during
    network partitions.
11. Idempotency protects business operations during ambiguous retries.
12. DNS changes do not instantly move cached clients or existing
    connections.
13. Target-region TLS, credentials, configuration, and dependencies must
    be validated before traffic movement.
14. Regional version drift can create failover incompatibility.
15. RTO should measure business service restoration, not merely a
    routing change.
16. Active-Active does not justify assuming zero RPO for every failure
    scenario.
17. Failed regions should pass infrastructure, Redis, Active-Active,
    dependency, and security gates before re-entry.
18. Rejoin should normally occur before failback.
19. A zero-traffic soak allows synchronization and stability validation.
20. Canary traffic should precede full failback.
21. Failback needs its own stop and reversal criteria.
22. DR exercises should measure detection, decision, routing, reconnect,
    and business recovery time.
23. Failure-state capacity should be load-tested.
24. Post-partition recovery must validate business invariants.
25. Production readiness requires tested cutover, emergency failover,
    rejoin, failback, capacity, routing, conflict controls, RTO/RPO
    evidence, and runbooks together.

------------------------------------------------------------------------

# 116. References

Validate all Active-Active failover/rejoin/failback procedures,
synchronization indicators, supported topology behavior, mixed-version
support, traffic prerequisites, and recovery guidance against the exact
deployed Redis Enterprise version, Redis Enterprise Kubernetes Operator
version, cloud/Kubernetes platform, and current official Redis
documentation.

Recommended documentation areas:

-   Redis Enterprise Active-Active
-   Redis Enterprise Active-Active disaster recovery
-   Redis Enterprise Active-Active recovery
-   Redis Enterprise Active-Active Kubernetes
-   RedisEnterpriseRemoteCluster
-   RedisEnterpriseActiveActiveDatabase
-   Redis Enterprise Active-Active monitoring
-   Redis Enterprise networking and security
-   Redis Enterprise upgrade compatibility
-   Kubernetes multi-region operations
-   cloud-provider regional failure guidance
-   DNS/GSLB/load-balancer failover documentation
-   application retry/idempotency design
-   organizational business continuity and DR standards

------------------------------------------------------------------------

# Next Chapter

**Chapter 68 --- Redis Enterprise Multi-Cluster / Multi-Environment
Platform Standards**

Chapter 68 will convert the Kubernetes and Active-Active lessons from
Chapters 61-67 into a reusable platform standard: environment topology,
naming, namespaces, REC/REDB patterns, sizing tiers, storage/network
classes, security baselines, GitOps repository structure, labels,
quotas, policy-as-code, observability, backup/DR tiers, upgrade rings,
self-service controls, golden manifests, exception handling,
troubleshooting, runbooks, and platform acceptance.
