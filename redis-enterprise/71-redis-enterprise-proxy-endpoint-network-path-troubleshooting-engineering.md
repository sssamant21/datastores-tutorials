# Chapter 71 --- Redis Enterprise Proxy, Endpoint & Network Path Troubleshooting Engineering

**Status:** Canonical\
**Track:** Redis Enterprise / Redis Software Production Engineering\
**Part:** Part 12 --- Advanced Operations, FinOps & Resilience\
**Level:** Advanced → Network Path, Endpoint & Connectivity Incident
Engineering\
**Audience:** SREs, DBREs, Redis Administrators, Platform Engineers,
Kubernetes Administrators, Network Engineers, Application Engineers\
**Lab type:** Endpoint architecture, DNS, TCP, TLS, Redis Enterprise
proxy, Kubernetes Services/EndpointSlices, load balancers,
NetworkPolicy, firewalls, NAT/conntrack, MTU, packet loss, resets,
topology latency, fault injection, troubleshooting, runbooks, and
production acceptance

------------------------------------------------------------------------

# 1. Objective

When an application reports:

``` text
Redis connection timeout
```

the failure may not be Redis command execution.

The request path can include:

``` text
application
   |
DNS
   |
client TCP/TLS
   |
network/firewall/NAT
   |
load balancer / Kubernetes Service
   |
Redis Enterprise proxy/endpoint
   |
Redis shard
```

A failure in any layer can appear to the application as:

``` text
timeout
connection refused
connection reset
TLS failure
intermittent latency
```

By the end of this chapter, you should be able to:

-   map the complete Redis Enterprise network path;
-   distinguish DNS, TCP, TLS, endpoint, proxy, and shard failures;
-   troubleshoot Kubernetes Services and EndpointSlices;
-   analyze load balancer behavior;
-   troubleshoot NetworkPolicy and firewalls;
-   reason about NAT and connection tracking;
-   diagnose connection resets;
-   identify packet loss and retransmission;
-   investigate MTU problems;
-   separate network latency from Redis execution latency;
-   analyze cross-zone and cross-region paths;
-   perform safe packet-level diagnostics where approved;
-   execute controlled network failure tests;
-   use production runbooks and acceptance gates.

------------------------------------------------------------------------

# 2. Core Production Principle

Troubleshoot connectivity layer by layer.

Do not jump directly from:

``` text
application timeout
```

to:

``` text
Redis is down
```

------------------------------------------------------------------------

# Part 1 --- Build the Path

## 3. Request Flow

Document the real production path.

Example:

``` text
application pod
  |
cluster DNS
  |
Kubernetes Service / cloud load balancer
  |
Redis Enterprise proxy
  |
database shard
```

Your architecture may differ.

------------------------------------------------------------------------

# Part 2 --- Path Inventory

## 4. Record

``` text
client location
client subnet
DNS name
resolved IP
port
TLS
load balancer
service
endpoint
proxy
Redis database
region
zone
```

------------------------------------------------------------------------

# Part 3 --- Known-Good Baseline

## 5. Before Incidents

Capture healthy:

``` text
DNS resolution time
TCP connect time
TLS handshake time
PING/command RTT
connection count
network RTT
packet loss
Redis P99
```

Without a baseline, "slow" is difficult to quantify.

------------------------------------------------------------------------

# Part 4 --- Client Location

## 6. First Question

Where is the client?

``` text
same pod network?
same Kubernetes cluster?
same VPC/VNet?
same zone?
same region?
on-prem?
internet/private link?
```

Topology changes expectations.

------------------------------------------------------------------------

# Part 5 --- Endpoint

## 7. Application Contract

Applications should use the supported Redis Enterprise endpoint.

Do not hard-code:

``` text
pod IP
node IP
shard IP
```

unless explicitly required by supported architecture.

------------------------------------------------------------------------

# Part 6 --- DNS

## 8. Resolve

From the affected client environment:

``` bash
getent hosts <redis-hostname>
```

or approved DNS tools.

Check:

``` text
does it resolve?
correct address?
expected family?
resolution latency?
```

------------------------------------------------------------------------

# Part 7 --- nslookup / dig

## 9. Diagnostics

Where installed/approved:

``` bash
nslookup <redis-hostname>
```

or:

``` bash
dig <redis-hostname>
```

Minimal application images may not include these utilities.

------------------------------------------------------------------------

# Part 8 --- DNS Failure Modes

## 10. Common

``` text
NXDOMAIN
SERVFAIL
timeout
stale record
wrong record
resolver unavailable
search-domain mistake
```

------------------------------------------------------------------------

# Part 9 --- DNS Caching

## 11. Client Behavior

Applications/libraries may cache DNS differently.

A DNS record can be correct while a long-running process continues using
an old address.

Understand:

``` text
DNS TTL
OS resolver
runtime DNS cache
client behavior
```

------------------------------------------------------------------------

# Part 10 --- Kubernetes DNS

## 12. Check

If client is in Kubernetes:

``` bash
kubectl get pods -n kube-system
```

and inspect the cluster DNS components appropriate to the platform.

Do not assume every DNS failure is Redis-specific.

------------------------------------------------------------------------

# Part 11 --- TCP Reachability

## 13. Test

From an approved diagnostic environment:

``` bash
nc -vz <redis-hostname> <port>
```

or an equivalent supported tool.

A successful TCP connect proves only basic transport reachability.

------------------------------------------------------------------------

# Part 12 --- TCP Failure Types

## 14. Interpret

``` text
timeout
```

often suggests dropped/unreachable path.

``` text
connection refused
```

often suggests reachable host/path but no listener/rejection.

``` text
connection reset
```

means an established or establishing connection was actively terminated
somewhere in the path.

Investigate evidence before assigning cause.

------------------------------------------------------------------------

# Part 13 --- SYN Path

## 15. Concept

TCP connection:

``` text
SYN
SYN-ACK
ACK
```

If SYN receives no response:

``` text
routing
firewall
security group
NetworkPolicy
LB
endpoint
```

may be involved.

------------------------------------------------------------------------

# Part 14 --- TCP Connect Time

## 16. Measure Separately

Instrument:

``` text
DNS time
connect time
TLS time
command time
```

This is far more useful than one combined "Redis latency" number.

------------------------------------------------------------------------

# Part 15 --- TLS

## 17. Handshake

For TLS-enabled Redis, validate:

``` text
certificate trust
hostname
expiry
protocol/cipher compatibility
client certificate if required
```

------------------------------------------------------------------------

# Part 16 --- OpenSSL Diagnostic

## 18. Approved Example

Where appropriate:

``` bash
openssl s_client -connect <host>:<port> -servername <host>
```

Do not expose credentials in shell history.

------------------------------------------------------------------------

# Part 17 --- TLS Failure Modes

## 19. Examples

``` text
unknown CA
expired certificate
hostname mismatch
unsupported protocol
client certificate rejected
trust bundle missing
```

------------------------------------------------------------------------

# Part 18 --- Certificate Rotation

## 20. Incident Pattern

After certificate rotation:

``` text
some clients work
some clients fail
```

Possible cause:

``` text
stale trust store
old long-running application instance
partial rollout
```

------------------------------------------------------------------------

# Part 19 --- Redis Authentication vs Network

## 21. Separate

If TCP/TLS succeeds but Redis returns authentication/authorization
errors:

``` text
network path works
```

Continue at auth/ACL layer.

Do not classify as network outage.

------------------------------------------------------------------------

# Part 20 --- Redis PING

## 22. Test

Using the environment's secure authentication method:

``` bash
redis-cli -h <host> -p <port> PING
```

Add TLS options where required.

Expected:

``` text
PONG
```

Do not place passwords directly in shared terminal history.

------------------------------------------------------------------------

# Part 21 --- Layered Test

## 23. Sequence

``` text
1. DNS
2. TCP
3. TLS
4. Redis authentication
5. PING
6. representative application command
```

This isolates failure layers.

------------------------------------------------------------------------

# Part 22 --- Redis Enterprise Proxy

## 24. Role

Redis Enterprise architecture can use proxy components to route database
traffic.

Use product-specific observability to inspect:

``` text
proxy availability
CPU
connections
throughput
errors
```

according to deployed version.

------------------------------------------------------------------------

# Part 23 --- Proxy Saturation

## 25. Symptoms

Possible:

``` text
connect latency
command latency
timeouts
connection resets
```

while shard CPU may appear healthy.

------------------------------------------------------------------------

# Part 24 --- Proxy vs Shard

## 26. Compare

``` text
proxy CPU high, shard CPU low
```

suggests a different bottleneck than:

``` text
proxy healthy, one shard CPU high
```

------------------------------------------------------------------------

# Part 25 --- Proxy Placement

## 27. Topology

Understand where proxies run relative to:

``` text
client
nodes
zones
shards
```

Placement can affect network path and failure domains.

------------------------------------------------------------------------

# Part 26 --- Kubernetes Service

## 28. Inspect

``` bash
kubectl get svc -n <namespace>
kubectl describe svc <service> -n <namespace>
```

Check:

``` text
type
ports
selectors
load balancer address
events
```

------------------------------------------------------------------------

# Part 27 --- EndpointSlices

## 29. Inspect

``` bash
kubectl get endpointslice -n <namespace>
```

Then identify slices associated with the relevant Service.

Check whether ready backend endpoints exist.

------------------------------------------------------------------------

# Part 28 --- Empty Endpoints

## 30. Causes

Possible:

``` text
selector mismatch
pods not Ready
wrong namespace/service
Operator reconciliation issue
```

------------------------------------------------------------------------

# Part 29 --- Pod Readiness

## 31. Inspect

``` bash
kubectl get pods -n <namespace> -o wide
kubectl describe pod <pod> -n <namespace>
```

A running pod is not necessarily a ready endpoint.

------------------------------------------------------------------------

# Part 30 --- Service Port Mapping

## 32. Verify

Check:

``` text
service port
target port
protocol
```

A wrong target port can produce endpoint failures even when pods are
healthy.

------------------------------------------------------------------------

# Part 31 --- Load Balancer

## 33. Inspect

For cloud/external LB:

``` text
frontend
listener
backend pool
health checks
security rules
idle timeout
```

Use provider-specific tools.

------------------------------------------------------------------------

# Part 32 --- Health Check

## 34. Important

A backend can serve Redis but fail the load balancer's health-check
configuration, or vice versa.

Validate:

``` text
health-check port
protocol
source ranges
backend readiness
```

------------------------------------------------------------------------

# Part 33 --- Idle Timeout

## 35. Long-Lived Connections

A load balancer/firewall/NAT may terminate idle TCP connections.

Applications then see:

``` text
reset
broken pipe
unexpected EOF
```

------------------------------------------------------------------------

# Part 34 --- Keepalive

## 36. Strategy

Use supported client/TCP keepalive behavior appropriate to the
infrastructure.

Coordinate:

``` text
client keepalive
LB idle timeout
firewall idle timeout
NAT timeout
```

------------------------------------------------------------------------

# Part 35 --- NetworkPolicy

## 37. Inspect

``` bash
kubectl get networkpolicy -A
```

Determine policies selecting:

``` text
client pod
Redis pod
namespace
```

------------------------------------------------------------------------

# Part 36 --- Default Deny

## 38. Common

A default-deny policy requires explicit allow rules.

Check both:

``` text
egress from client
ingress to Redis
```

where policy model requires them.

------------------------------------------------------------------------

# Part 37 --- DNS and NetworkPolicy

## 39. Hidden Failure

A strict egress policy may allow Redis traffic but block DNS.

Then application reports endpoint resolution failure.

Allow required DNS traffic according to platform policy.

------------------------------------------------------------------------

# Part 38 --- Policy Selector

## 40. Labels

A label change can alter NetworkPolicy selection.

Compare:

``` bash
kubectl get pod <pod> -n <namespace> --show-labels
```

with policy selectors.

------------------------------------------------------------------------

# Part 39 --- Firewall / Security Group

## 41. Cloud Path

Check:

``` text
source
destination
port
direction
stateful behavior
route
```

Use the cloud platform's approved diagnostics.

------------------------------------------------------------------------

# Part 40 --- Route Tables

## 42. Reachability

Correct firewall rules are insufficient if routing is wrong.

Validate routes between:

``` text
client subnet
Redis subnet
peering/transit
regional network
```

------------------------------------------------------------------------

# Part 41 --- Asymmetric Routing

## 43. Risk

Forward and return traffic may follow different paths.

Stateful devices can drop unexpected return traffic.

Investigate during intermittent connectivity.

------------------------------------------------------------------------

# Part 42 --- NAT

## 44. Role

NAT can introduce:

``` text
port translation
state tracking
idle timeout
capacity limits
```

------------------------------------------------------------------------

# Part 43 --- SNAT Port Exhaustion

## 45. Symptom

Large connection churn through limited SNAT resources can cause:

``` text
intermittent connect timeout
connect failures
```

Connection pooling can reduce churn.

------------------------------------------------------------------------

# Part 44 --- Ephemeral Ports

## 46. Client Side

High outbound connection churn can exhaust local ephemeral ports.

Inspect OS/network metrics appropriate to the client platform.

------------------------------------------------------------------------

# Part 45 --- TIME_WAIT

## 47. Signal

Large numbers of short-lived connections can create many sockets in
`TIME_WAIT`.

This often indicates missing connection reuse.

------------------------------------------------------------------------

# Part 46 --- conntrack

## 48. Kubernetes / Linux

Connection tracking tables can become constrained on busy nodes/NAT
paths.

Symptoms can include:

``` text
intermittent packet drops
new connection failures
```

Use platform-approved node diagnostics.

------------------------------------------------------------------------

# Part 47 --- Connection Storm

## 49. Causes

``` text
application restart
autoscaling
Redis failover
DNS change
credential rotation
network recovery
```

Thousands of clients may reconnect simultaneously.

------------------------------------------------------------------------

# Part 48 --- Reconnect Jitter

## 50. Protection

Clients should use:

``` text
bounded retries
exponential backoff
jitter
```

to reduce synchronized reconnect storms.

------------------------------------------------------------------------

# Part 49 --- Connection Reset

## 51. Possible Sources

``` text
client
server/proxy
load balancer
firewall
NAT
network appliance
```

Do not assume Redis initiated it.

------------------------------------------------------------------------

# Part 50 --- Reset Investigation

## 52. Correlate

Collect:

``` text
timestamp
client IP
endpoint
connection age
LB logs
Redis/proxy logs
packet evidence if approved
```

------------------------------------------------------------------------

# Part 51 --- Packet Loss

## 53. Effect

Packet loss can cause:

``` text
retransmission
higher P99
timeouts
```

even when Redis execution remains fast.

------------------------------------------------------------------------

# Part 52 --- TCP Retransmission

## 54. Signal

Use OS/network observability to track retransmissions.

A rising retransmit rate during latency is strong network evidence.

------------------------------------------------------------------------

# Part 53 --- ping Caveat

## 55. ICMP

ICMP may be blocked or deprioritized.

A failed `ping` does not prove TCP Redis traffic is unavailable.

Use protocol-relevant tests.

------------------------------------------------------------------------

# Part 54 --- traceroute Caveat

## 56. Path

Traceroute can help understand path, but cloud networks may
hide/deprioritize hops.

Treat it as supporting evidence.

------------------------------------------------------------------------

# Part 55 --- MTU

## 57. Concept

Maximum Transmission Unit controls packet size before
fragmentation/segmentation behavior.

Mismatched MTU can cause subtle failures.

------------------------------------------------------------------------

# Part 56 --- MTU Symptoms

## 58. Examples

``` text
small commands work
large responses fail/hang
TLS handshake behaves strangely
cross-network path intermittent
```

------------------------------------------------------------------------

# Part 57 --- Overlay Networks

## 59. Kubernetes

CNI overlays can add encapsulation overhead.

Effective MTU may need to account for:

``` text
VXLAN
Geneve
other encapsulation
```

depending on platform.

------------------------------------------------------------------------

# Part 58 --- Path MTU Discovery

## 60. Diagnose

Use platform-approved network diagnostics.

Do not change MTU on production nodes ad hoc.

------------------------------------------------------------------------

# Part 59 --- Large Response Test

## 61. Useful

If:

``` text
PING works
small GET works
large GET fails
```

investigate:

``` text
MTU
LB/network appliance
timeouts
client buffers
```

alongside Redis evidence.

------------------------------------------------------------------------

# Part 60 --- Bandwidth Saturation

## 62. Network Limit

High Redis throughput can saturate:

``` text
pod/node NIC
LB
cross-zone link
client NIC
```

CPU may remain healthy.

------------------------------------------------------------------------

# Part 61 --- Bytes, Not Only Ops

## 63. Example

``` text
100k ops/sec x 100 bytes
```

is very different from:

``` text
100k ops/sec x 100 KB
```

Monitor network bytes/sec.

------------------------------------------------------------------------

# Part 62 --- Cross-Zone Traffic

## 64. Consider

Cross-zone traffic can add:

``` text
latency
cost
dependency on zone connectivity
```

Architecture should be deliberate.

------------------------------------------------------------------------

# Part 63 --- Cross-Region Traffic

## 65. Physics

Regional distance adds latency.

No Redis tuning can eliminate physical network RTT.

Use local endpoints/Active-Active architecture where business
requirements justify it.

------------------------------------------------------------------------

# Part 64 --- Topology Awareness

## 66. Record

``` text
client zone
endpoint zone
proxy zone
Redis node zone
```

when investigating latency skew.

------------------------------------------------------------------------

# Part 65 --- One-Zone Problem

## 67. Pattern

If only clients in one zone are slow:

``` text
zone network
node
CNI
route
LB path
```

becomes more likely than global Redis failure.

------------------------------------------------------------------------

# Part 66 --- One-Node Problem

## 68. Pattern

If only pods on one Kubernetes node fail Redis connections:

investigate:

``` text
node CNI
conntrack
route
DNS
host firewall
NIC
```

------------------------------------------------------------------------

# Part 67 --- One-Application Problem

## 69. Pattern

If other applications use the same Redis endpoint successfully:

investigate:

``` text
client config
DNS cache
TLS trust
credentials
pool
NetworkPolicy
source subnet
```

------------------------------------------------------------------------

# Part 68 --- All-Application Problem

## 70. Pattern

If every client fails simultaneously:

focus on shared dependencies:

``` text
endpoint
LB
proxy
Redis cluster
DNS
network control plane
```

------------------------------------------------------------------------

# Part 69 --- Intermittent Failure

## 71. Hardest Class

Collect time-series evidence.

Look for correlation with:

``` text
autoscaling
connection churn
LB backend changes
node pressure
failover
NAT/conntrack
packet loss
```

------------------------------------------------------------------------

# Part 70 --- Connection Establishment Metrics

## 72. Application

Track separately:

``` text
DNS latency
connect latency
TLS latency
command latency
```

------------------------------------------------------------------------

# Part 71 --- Existing vs New Connections

## 73. Diagnostic

If:

``` text
existing connections work
new connections fail
```

investigate:

``` text
DNS
LB
NAT
conntrack
listener capacity
TLS
```

------------------------------------------------------------------------

# Part 72 --- New Works, Existing Fails

## 74. Diagnostic

If new connections work but old ones reset:

investigate:

``` text
idle timeout
connection lifetime
LB/network state
failover behavior
```

------------------------------------------------------------------------

# Part 73 --- Application Timeouts

## 75. Distinguish

``` text
connect timeout
socket/read timeout
command timeout
pool-acquire timeout
```

They indicate different stages.

------------------------------------------------------------------------

# Part 74 --- Timeout Budget

## 76. Design

Example request budget:

``` text
application request = 500 ms
pool wait = 20 ms
Redis operation = 50 ms
retry allowance = bounded
```

Design explicitly.

------------------------------------------------------------------------

# Part 75 --- Redis Failover

## 77. Client Experience

During failover, clients may see transient:

``` text
disconnect
reset
timeout
reconnect
```

Client behavior must be qualified.

------------------------------------------------------------------------

# Part 76 --- Reconnect After Failover

## 78. Validate

Measure:

``` text
disconnect duration
reconnect duration
error count
P99
```

Do not test only whether Redis eventually becomes healthy.

------------------------------------------------------------------------

# Part 77 --- DNS During Failover

## 79. Architecture Specific

Some endpoint designs may not require DNS changes; others may.

Understand exact Redis Enterprise deployment architecture rather than
assuming.

------------------------------------------------------------------------

# Part 78 --- Kubernetes Pod Rescheduling

## 80. Endpoint Change

When backend pods move:

``` text
EndpointSlice
Service
proxy
client
```

should converge correctly.

Observe during controlled maintenance.

------------------------------------------------------------------------

# Part 79 --- NetworkPolicy Change

## 81. Change Risk

A policy deployment can cause immediate widespread Redis connectivity
loss.

Treat production NetworkPolicy changes as high-impact network changes.

------------------------------------------------------------------------

# Part 80 --- Firewall Change

## 82. Change Risk

Before firewall/security-group change:

``` text
document flows
validate source/destination/port
have rollback
monitor connection errors
```

------------------------------------------------------------------------

# Part 81 --- DNS Change

## 83. Change Risk

Before changing endpoint DNS:

``` text
understand TTL
client caching
old/new endpoint overlap
rollback
```

------------------------------------------------------------------------

# Part 82 --- Load Balancer Change

## 84. Validate

After change:

``` text
listener
backend health
new connections
existing connections
TLS
P99
```

------------------------------------------------------------------------

# Part 83 --- Packet Capture

## 85. High-Value Evidence

Where security policy allows, packet capture can identify:

``` text
SYN retransmission
RST source
TLS handshake
retransmission
zero-window
MTU clues
```

------------------------------------------------------------------------

# Part 84 --- Packet Capture Safety

## 86. Security

Redis traffic may contain sensitive data if not encrypted.

Use:

``` text
approved hosts
minimal filters
short duration
secure storage
restricted access
```

Prefer metadata-only evidence when sufficient.

------------------------------------------------------------------------

# Part 85 --- tcpdump Example

## 87. Approved Lab

Conceptually:

``` bash
tcpdump -i <interface> host <redis-ip> and port <port>
```

Exact interface/permissions depend on environment.

Do not capture broad production traffic without approval.

------------------------------------------------------------------------

# Part 86 --- Timestamp Correlation

## 88. Critical

Synchronize:

``` text
application logs
Redis logs
LB logs
network logs
Kubernetes events
packet capture
```

using accurate timestamps.

------------------------------------------------------------------------

# Part 87 --- Healthy Control

## 89. Compare

During incident compare:

``` text
failing client
healthy client
```

against same Redis endpoint.

This can rapidly isolate client/network locality.

------------------------------------------------------------------------

# Part 88 --- Multi-Point Test

## 90. Useful

Test from:

``` text
affected pod
same node different pod
different node
different zone
platform diagnostic host
```

This narrows the failing segment.

------------------------------------------------------------------------

# Part 89 --- Synthetic Probe

## 91. Production Monitoring

A lightweight probe can measure:

``` text
DNS
connect
TLS
PING
SET/GET synthetic key
```

using isolated credentials/key namespace.

------------------------------------------------------------------------

# Part 90 --- Probe Locations

## 92. Better Coverage

Deploy probes from representative:

``` text
zones
clusters
regions
```

for critical Redis services.

------------------------------------------------------------------------

# Part 91 --- Lab Namespace

## 93. Keys

Use:

``` text
tutorial:chapter71:*
```

for synthetic Redis validation.

------------------------------------------------------------------------

# Part 92 --- Lab 1: DNS

## 94. Exercise

From test client:

1.  resolve endpoint;
2.  record resolution time;
3.  record IP;
4.  repeat;
5.  compare cache behavior.

------------------------------------------------------------------------

# Part 93 --- Lab 2: TCP

## 95. Exercise

Measure connect success/time.

Compare:

``` text
correct port
closed test port
blocked path in isolated lab
```

Observe error differences.

------------------------------------------------------------------------

# Part 94 --- Lab 3: TLS

## 96. Exercise

Validate:

``` text
certificate chain
hostname
expiry
handshake
```

against a lab endpoint.

------------------------------------------------------------------------

# Part 95 --- Lab 4: Kubernetes Service

## 97. Exercise

Inspect:

``` text
Service
EndpointSlice
backend pod readiness
```

Map each endpoint to a pod/node.

------------------------------------------------------------------------

# Part 96 --- Lab 5: NetworkPolicy

## 98. Exercise

In isolated namespace:

1.  verify Redis access;
2.  apply a test deny policy;
3.  observe timeout/failure;
4.  apply precise allow;
5.  validate recovery.

Never experiment on shared production.

------------------------------------------------------------------------

# Part 97 --- Lab 6: Connection Churn

## 99. Exercise

Compare:

``` text
one reused connection
new connection per command
```

Measure:

``` text
connect rate
TIME_WAIT
latency
CPU
```

------------------------------------------------------------------------

# Part 98 --- Lab 7: Packet Loss

## 100. Exercise

In approved isolated environment, inject bounded packet loss.

Measure:

``` text
retransmissions
P99
timeouts
Redis server execution
```

------------------------------------------------------------------------

# Part 99 --- Lab 8: Network Latency

## 101. Exercise

Inject bounded latency.

Compare:

``` text
client P99
SLOWLOG/server execution
```

------------------------------------------------------------------------

# Part 100 --- Lab 9: MTU

## 102. Exercise

In a disposable network lab, test small and large payload behavior
across the path.

Do not change production MTU for tutorial purposes.

------------------------------------------------------------------------

# Part 101 --- Lab 10: Failover/Reconnect

## 103. Exercise

During an approved Redis failover test measure:

``` text
existing connection behavior
new connection behavior
error count
reconnect time
P99
```

------------------------------------------------------------------------

# Part 102 --- Failure Scenario 1: DNS Failure

## 104. Test

Block/break DNS only in isolated lab.

Validate application error and layer identification.

------------------------------------------------------------------------

# Part 103 --- Failure Scenario 2: NetworkPolicy Deny

## 105. Test

Apply isolated deny.

Validate timeout and policy diagnosis.

------------------------------------------------------------------------

# Part 104 --- Failure Scenario 3: Wrong Service Port

## 106. Test

Use disposable service/config.

Observe:

``` text
refused/timeout
```

depending on path.

------------------------------------------------------------------------

# Part 105 --- Failure Scenario 4: TLS Trust Failure

## 107. Test

Use a test client with incorrect trust configuration.

Validate certificate error rather than calling it Redis outage.

------------------------------------------------------------------------

# Part 106 --- Failure Scenario 5: Connection Storm

## 108. Test

Generate bounded concurrent new connections.

Observe:

``` text
connect latency
proxy/client CPU
NAT/ports
```

------------------------------------------------------------------------

# Part 107 --- Failure Scenario 6: Packet Loss

## 109. Test

Inject bounded loss.

Observe retransmissions/P99.

------------------------------------------------------------------------

# Part 108 --- Failure Scenario 7: Idle Connection Reset

## 110. Test/Tabletop

Use a lab LB/network timeout shorter than client idle period.

Observe reconnect behavior.

------------------------------------------------------------------------

# Part 109 --- Failure Scenario 8: One Node Network Fault

## 111. Test

In approved lab, isolate a client node-specific path issue.

Compare same workload from another node.

------------------------------------------------------------------------

# Part 110 --- Failure Scenario 9: Cross-Zone Latency

## 112. Test

Compare local-zone and cross-zone paths where architecture permits.

Record RTT/P99.

------------------------------------------------------------------------

# Part 111 --- Failure Scenario 10: Redis Failover

## 113. Test

Execute approved failover.

Measure client reconnect and error budget impact.

------------------------------------------------------------------------

# Part 112 --- Troubleshooting Matrix

## 114. Common Problems

  Symptom                     Investigate
  --------------------------- ------------------------------------
  hostname does not resolve   DNS/resolver/policy
  TCP timeout                 route/firewall/policy/LB
  connection refused          listener/service/port
  TLS error                   cert/trust/protocol/hostname
  auth error                  credentials/ACL, not basic network
  existing works, new fails   NAT/conntrack/LB/DNS
  new works, old resets       idle timeout/failover/state
  only one node affected      CNI/conntrack/node route
  only one zone affected      zonal network/LB path
  server fast, client slow    network/proxy/result/client
  large payload fails         MTU/LB/network/client
  intermittent resets         LB/NAT/firewall/failover

------------------------------------------------------------------------

# Part 113 --- Runbook 1: Cannot Connect

## 115. Procedure

``` text
1. identify affected clients/scope.
2. resolve DNS.
3. test TCP.
4. test TLS.
5. test Redis auth/PING.
6. inspect Service/EndpointSlice/LB.
7. inspect policy/firewall/routes.
8. restore path and validate application.
```

------------------------------------------------------------------------

# Part 114 --- Runbook 2: Intermittent Connection Reset

## 116. Procedure

``` text
1. capture exact timestamps.
2. classify new vs existing connection.
3. inspect LB/NAT/firewall idle timeout.
4. inspect failover/proxy events.
5. inspect client keepalive/reconnect.
6. capture packet evidence if approved.
7. correct timeout/path/client behavior.
8. validate over soak period.
```

------------------------------------------------------------------------

# Part 115 --- Runbook 3: High Network Latency

## 117. Procedure

``` text
1. compare client and server latency.
2. measure RTT/loss.
3. identify topology/zone/region.
4. inspect retransmissions.
5. inspect bandwidth.
6. inspect proxy/LB.
7. correct routing/locality/capacity.
8. validate P95/P99.
```

------------------------------------------------------------------------

# Part 116 --- Runbook 4: Kubernetes Service Failure

## 118. Procedure

``` text
1. inspect Service.
2. inspect EndpointSlices.
3. inspect backend readiness.
4. inspect selectors/ports.
5. inspect NetworkPolicy.
6. inspect Operator reconciliation.
7. restore endpoints.
8. validate Redis PING/application.
```

------------------------------------------------------------------------

# Part 117 --- Runbook 5: TLS Failure

## 119. Procedure

``` text
1. confirm TCP works.
2. capture TLS error.
3. inspect certificate chain/expiry.
4. inspect hostname/SNI.
5. inspect trust bundle.
6. inspect client certificate if required.
7. correct certificate/trust rollout.
8. validate all client populations.
```

------------------------------------------------------------------------

# Part 118 --- Runbook 6: Connection Storm

## 120. Procedure

``` text
1. measure new connection rate.
2. identify triggering event.
3. inspect client pooling.
4. inspect NAT/ephemeral ports/conntrack.
5. inspect proxy/LB capacity.
6. apply backoff/jitter.
7. restore connection reuse.
8. validate steady-state connection count.
```

------------------------------------------------------------------------

# Part 119 --- Runbook 7: Packet Loss / Retransmission

## 121. Procedure

``` text
1. confirm server execution latency.
2. measure retransmissions/loss.
3. identify affected source/destination.
4. compare healthy control path.
5. inspect node/NIC/CNI/LB/network.
6. capture packet evidence if approved.
7. repair network path.
8. validate P99/error rate.
```

------------------------------------------------------------------------

# Part 120 --- Runbook 8: Post-Failover Connectivity

## 122. Procedure

``` text
1. identify failover timestamp.
2. measure disconnect/error window.
3. inspect endpoint/proxy health.
4. inspect client reconnect behavior.
5. inspect DNS only if architecture uses it.
6. inspect retry storm.
7. stabilize connections.
8. document recovery time and corrective action.
```

------------------------------------------------------------------------

# Part 121 --- Network Path Template

## 123. Record

``` text
Application:
Namespace/host:
Source IP/subnet:
Source zone/region:
Redis DNS:
Resolved IP:
Port:
TLS:
Service/LB:
Proxy:
Redis database:
Destination zone/region:
Firewall/policy:
NAT:
```

------------------------------------------------------------------------

# Part 122 --- Connectivity Incident Template

## 124. Record

``` text
Incident:
Start:
Affected clients:
Healthy clients:
DNS:
TCP:
TLS:
Redis PING:
Connect latency:
Command latency:
Packet loss:
Retransmissions:
Service/endpoints:
LB:
Proxy:
NetworkPolicy:
Firewall:
NAT/conntrack:
Recent change:
Root cause:
```

------------------------------------------------------------------------

# Part 123 --- Network SLO Template

## 125. Record

``` text
DNS P99:
Connect P99:
TLS P99:
Redis PING P99:
Packet loss:
Connection error rate:
Reset rate:
Reconnect objective:
Failover interruption objective:
```

------------------------------------------------------------------------

# Part 124 --- Production Acceptance

## 126. Architecture

-   [ ] client-to-Redis path documented;
-   [ ] endpoint ownership documented;
-   [ ] DNS ownership documented;
-   [ ] LB/Service architecture documented;
-   [ ] proxy architecture understood;
-   [ ] zone/region topology documented.

## 127. Security / Network

-   [ ] required ports documented;
-   [ ] NetworkPolicy validated;
-   [ ] firewall/security rules validated;
-   [ ] routes validated;
-   [ ] TLS chain/rotation validated;
-   [ ] NAT/conntrack capacity understood;
-   [ ] idle timeouts documented.

## 128. Observability

-   [ ] DNS latency observable;
-   [ ] connect latency observable;
-   [ ] TLS latency observable;
-   [ ] command latency observable;
-   [ ] connection errors classified;
-   [ ] retransmissions/loss observable;
-   [ ] proxy/LB health observable;
-   [ ] per-zone path monitoring available for critical services.

## 129. Resilience

-   [ ] client connection pooling validated;
-   [ ] backoff/jitter validated;
-   [ ] failover reconnect tested;
-   [ ] NetworkPolicy recovery tested;
-   [ ] packet-loss behavior tested;
-   [ ] network-latency behavior tested;
-   [ ] ten failure scenarios completed;
-   [ ] eight runbooks reviewed;
-   [ ] production acceptance completed.

------------------------------------------------------------------------

# 130. Knowledge Validation

1.  Why can a Redis timeout originate outside Redis?
2.  What layers should be mapped in the request path?
3.  Why is a healthy network baseline useful?
4.  Why should applications use supported endpoints instead of pod IPs?
5.  How can DNS caching create stale endpoint behavior?
6.  What does a TCP timeout suggest compared with connection refused?
7.  What is a connection reset?
8.  Why should DNS, connect, TLS, and command time be measured
    separately?
9.  What are common TLS failure causes?
10. Why is an authentication error different from a network failure?
11. What role can a Redis Enterprise proxy play?
12. Why can proxy saturation be hidden by healthy shard CPU?
13. What does a Kubernetes EndpointSlice tell you?
14. Why can a running pod be absent from ready endpoints?
15. How can load-balancer idle timeout affect Redis clients?
16. Why must NetworkPolicy account for DNS?
17. Why are routing and firewall checks both necessary?
18. What is SNAT port exhaustion?
19. Why can high `TIME_WAIT` indicate missing connection reuse?
20. What is conntrack and why can it matter?
21. Why should reconnects use backoff and jitter?
22. How does packet loss increase P99?
23. Why is ICMP ping not definitive proof of Redis reachability?
24. What symptoms can an MTU problem create?
25. Why should network bytes/sec be monitored in addition to ops/sec?
26. Why can cross-region latency not be solved by Redis command tuning?
27. What does "existing connections work, new connections fail" suggest?
28. Why can packet capture be sensitive?
29. Why is a healthy control client valuable during an incident?
30. What must pass before Redis network-path engineering is
    production-ready?

------------------------------------------------------------------------

# 131. Hands-On Acceptance Checklist

-   [ ] Documented complete client-to-Redis path.
-   [ ] Recorded source/destination zones.
-   [ ] Tested DNS resolution.
-   [ ] Measured DNS time.
-   [ ] Tested TCP connectivity.
-   [ ] Measured connect time.
-   [ ] Validated TLS chain.
-   [ ] Tested Redis PING.
-   [ ] Inspected Redis Enterprise proxy evidence.
-   [ ] Inspected Kubernetes Service.
-   [ ] Inspected EndpointSlices.
-   [ ] Mapped endpoints to pods/nodes.
-   [ ] Reviewed NetworkPolicy.
-   [ ] Reviewed firewall/security rules.
-   [ ] Reviewed routes.
-   [ ] Reviewed LB health checks.
-   [ ] Reviewed idle timeouts.
-   [ ] Reviewed NAT/ephemeral port behavior.
-   [ ] Reviewed conntrack capacity.
-   [ ] Tested connection reuse vs churn.
-   [ ] Tested bounded packet loss.
-   [ ] Tested bounded network latency.
-   [ ] Performed MTU tabletop/lab.
-   [ ] Tested failover reconnect.
-   [ ] Completed ten failure scenarios.
-   [ ] Completed eight runbooks.
-   [ ] Completed production acceptance.

------------------------------------------------------------------------

# 132. Cleanup

Remove only disposable Chapter 71 lab resources.

For Redis keys:

``` text
tutorial:chapter71:*
```

use safe:

``` text
SCAN
+
UNLINK
```

Do not use:

``` text
FLUSHDB
FLUSHALL
```

on shared environments.

Remove/restore:

``` text
temporary NetworkPolicy
temporary test Service
temporary fault injection
temporary packet capture
temporary network-delay/loss rules
temporary LB timeout changes
```

Confirm:

``` text
normal DNS
normal connectivity
normal connection count
normal packet loss
normal P99
no test policies remain
no test capture files remain outside approved retention
```

------------------------------------------------------------------------

# 133. Key Takeaways

1.  Redis connectivity incidents must be decomposed into DNS, TCP, TLS,
    endpoint, proxy, and Redis layers.
2.  A client timeout does not prove Redis command execution is slow.
3.  Healthy baselines for DNS, connect, TLS, and command latency make
    incidents easier to isolate.
4.  Applications should use supported stable endpoints rather than
    backend pod/shard addresses.
5.  DNS TTL and runtime caching can cause stale-address behavior.
6.  TCP timeout, refusal, and reset indicate different failure classes.
7.  TLS failures should be separated from basic TCP reachability.
8.  Redis authentication failures occur after basic network
    reachability.
9.  Redis Enterprise proxy health can matter independently of shard
    health.
10. Kubernetes Service and EndpointSlice evidence is essential for
    endpoint troubleshooting.
11. Pod readiness determines whether backends should receive traffic.
12. Load-balancer health checks and idle timeouts can create Redis
    connectivity symptoms.
13. NetworkPolicy must account for both Redis and required DNS flows.
14. Firewall rules cannot compensate for incorrect routing.
15. NAT, ephemeral ports, and conntrack become important under high
    connection churn.
16. Connection pooling reduces handshake cost and network-state
    pressure.
17. Reconnect backoff/jitter protects Redis and network infrastructure
    after failures.
18. Packet loss and retransmission can raise P99 while Redis execution
    remains healthy.
19. MTU problems can appear only with larger packets/responses.
20. Network capacity should be measured in bytes/sec as well as
    operations/sec.
21. Cross-zone and cross-region topology affects latency, resilience,
    and cost.
22. Comparing affected and healthy clients is one of the fastest ways to
    localize a network problem.
23. Existing-versus-new connection behavior is valuable diagnostic
    evidence.
24. Packet capture can identify TCP-level causes but must follow
    security controls.
25. Production readiness requires documented paths, layered telemetry,
    validated policy/firewall/LB configuration, client resilience,
    failure testing, and practiced runbooks.

------------------------------------------------------------------------

# 134. References

Validate Redis Enterprise proxy architecture, endpoint behavior,
Kubernetes Service exposure, TLS configuration, supported ports,
failover behavior, and network requirements against the exact deployed
Redis Enterprise and Redis Enterprise Kubernetes Operator versions.

Recommended documentation areas:

-   Redis Enterprise networking
-   Redis Enterprise proxy architecture
-   Redis Enterprise database endpoints
-   Redis Enterprise TLS
-   Redis Enterprise Kubernetes networking
-   Redis Enterprise Kubernetes Services
-   Redis Enterprise Active-Active networking
-   Kubernetes Services
-   Kubernetes EndpointSlices
-   Kubernetes DNS
-   Kubernetes NetworkPolicy
-   Kubernetes CNI documentation
-   cloud load balancer documentation
-   cloud firewall/security-group documentation
-   NAT/SNAT documentation
-   Linux TCP and conntrack documentation
-   organizational network/security standards

------------------------------------------------------------------------

# Next Chapter

**Chapter 72 --- Redis Enterprise Shard Rebalancing, Resharding &
Placement Operations**

Chapter 72 will focus on shard placement and data movement: shard
topology, placement constraints, skew detection, scale-out and scale-in,
rebalance triggers, resharding impact, network/storage/CPU requirements,
hot-shard diagnosis, maintenance and node replacement, failure-domain
awareness, data-movement observability, stop conditions, controlled
labs, troubleshooting, runbooks, and production acceptance.
