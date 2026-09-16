# Troubleshooting Scenario 02 — Production Installation & Configuration Failure

**Module:** 02 — Production Installation & Configuration  
**Platform:** Kubernetes  
**Reference Elasticsearch Version:** 9.5.x  
**Implementation Validation Version:** 9.5.3  
**Status:** REVISED FINAL / CANONICAL  
**Prerequisites:** Tutorial 02, Hands-On Lab 02, Real-World Use Case 02, Production Runbook 02

---

# 1. Scenario Purpose

A Kubernetes workload can appear healthy while Elasticsearch itself is not operationally healthy.

A running Pod does not prove successful Elasticsearch cluster membership, correct cluster identity, healthy transport security, complete shard allocation, persistent-storage continuity, successful recovery, or production readiness.

This scenario teaches an evidence-driven investigation of a production-style Elasticsearch installation failure involving two independent conditions:

1. a **transport TLS identity/trust failure** preventing one Elasticsearch node from securely joining the intended cluster; and
2. a **temporary shard-allocation restriction** left active after maintenance, preventing replicas that require new allocation from being assigned.

The exercise demonstrates why restoring the failed node does not automatically mean the incident is resolved.

```text
Kubernetes healthy ≠ Elasticsearch healthy
Node rejoined ≠ Incident resolved
GREEN ≠ Root cause understood
```

The objective is not simply to return the cluster to GREEN. The objective is to determine what failed, why it failed, what evidence proves it, what prevented complete recovery, and whether cluster identity, storage, data, security, and configuration were preserved.

---

# 2. Safety Boundary

The failure injection in this scenario is for an isolated lab environment only.

Do **not** intentionally introduce certificate failures, transport-security failures, or shard-allocation restrictions into production merely to reproduce this exercise.

Production use of this scenario is limited to its diagnostic methodology, evidence collection, failure classification, recovery validation, and configuration-restoration principles.

Do not deliberately weaken TLS to make a node join. Do not delete persistent storage to solve a cluster-membership problem. Do not bootstrap an existing cluster again.

---

# 3. Reference Architecture

The validated lab contains three Kubernetes Elasticsearch Pods, each backed by its own PVC/PV:

```text
Kubernetes cluster
│
├── elasticsearch-0
│   └── PVC → PV
├── elasticsearch-1
│   └── PVC → PV
└── elasticsearch-2
    └── PVC → PV
```

Elasticsearch baseline:

```text
Nodes                 3
Master-eligible       3
Data nodes            3
HTTP TLS              enabled
Transport TLS         enabled
Authentication        enabled
```

Validation index:

```text
installation-validation-v1
Primary shards        3
Replica count         1
Documents             4
Health                GREEN
Unassigned shards     0
```

Three Elasticsearch Pods do not by themselves prove three Kubernetes workers, three availability zones, or three independent storage failure domains. Those are separate infrastructure properties that must be validated independently.

---

# 4. Healthy Baseline Gate

Do not inject the scenario failure until the healthy baseline is proven.

Validate:

- expected cluster name;
- approved cluster UUID;
- 3 Elasticsearch nodes;
- expected roles and elected master;
- GREEN cluster/index health;
- 0 unassigned shards;
- 4 validation documents;
- HTTP TLS and transport TLS working;
- authentication working;
- PVC/PV identities recorded;
- `cluster.initial_master_nodes` absent;
- normal discovery/rejoin configuration;
- current cluster allocation settings recorded.

Example cluster identity request:

```bash
curl --cacert "$ES_CA" \
  -u "$ES_USER:$ES_PASSWORD" \
  "$ES_URL/?pretty"
```

Record at minimum `cluster_name`, `cluster_uuid`, and `version.number`. The cluster UUID becomes a recovery invariant. A node restart must not silently create or join a different cluster.

---

# 5. Authentication and TLS Handling

Use trusted TLS validation:

```bash
curl --cacert "$ES_CA" \
  -u "$ES_USER:$ES_PASSWORD" \
  "$ES_URL/_cluster/health?pretty"
```

Do not normalize `curl -k` as a production troubleshooting technique. If certificate validation fails, that failure is potentially important diagnostic evidence.

Avoid placing passwords directly in shell history. For an interactive session:

```bash
read -rsp "Elasticsearch password: " ES_PASSWORD
echo
export ES_PASSWORD
```

Evidence packages must never contain passwords, reusable API keys, authentication tokens, unredacted Authorization headers, or private keys.

---

# 6. Failure Model

The scenario intentionally creates two conditions.

## Condition A — Transport TLS Failure

`elasticsearch-2` receives invalid transport TLS material. The defect must cause a genuine transport-security failure such as an `SSLHandshakeException`, certificate validation/trust failure, PKIX/CertPath failure, x509 verification failure, SAN/peer-identity mismatch, `unknown_ca`, `bad_certificate`, failed SSL/TLS handshake, or equivalent Elasticsearch transport-security exception.

Generic log text containing words such as `certificate`, `SSL`, `TLS`, or `certificate_identity_field` does **not** prove a TLS failure. The evidence must demonstrate an actual failed secure transport operation.

## Condition B — Allocation Restriction

Before the node failure is activated, record the existing value of `cluster.routing.allocation.enable`. Then the lab intentionally applies:

```text
cluster.routing.allocation.enable = primaries
```

This permits primary allocation while preventing new replica allocation. It does not remove replicas that are already assigned; it affects allocations that subsequently need to occur.

The deterministic sequence is:

```text
HEALTHY BASELINE
3 nodes
GREEN
4 documents
same approved UUID
bootstrap removed
        ↓
record original allocation state
        ↓
set allocation.enable=primaries
        ↓
inject transport TLS defect on elasticsearch-2
        ↓
restart elasticsearch-2
        ↓
node 2 cannot securely join
        ↓
replicas become unassigned after node loss
        ↓
new replica allocation remains restricted
        ↓
YELLOW
```

Without the allocation restriction, a three-primary/one-replica index running on two remaining eligible data nodes may be able to allocate all required shard copies across those two nodes. Therefore a missing third node alone must not automatically be taught as the reason for sustained YELLOW.

---

# 7. Transport TLS Identity

This reference implementation uses per-node transport certificates and:

```yaml
xpack.security.transport.ssl.verification_mode: full
```

Certificate identity must therefore be valid for the DNS name or IP address actually used for node-to-node transport communication.

For the reference Kubernetes environment, identities can include names such as:

```text
elasticsearch-2
elasticsearch-2.elasticsearch-headless
elasticsearch-2.elasticsearch-headless.<namespace>.svc
elasticsearch-2.elasticsearch-headless.<namespace>.svc.cluster.local
```

These names are illustrative. The certificate SANs must correspond to the actual transport identities used by the deployment. Do not conclude that every Elasticsearch deployment must use this exact certificate topology.

---

# 8. Troubleshooting Method

Use:

```text
Observe → Classify → Correlate → Generate hypotheses → Collect evidence
        → Eliminate hypotheses → Establish cause → Remediate → Validate
```

Troubleshooting is not trying commands until the cluster becomes GREEN. The operator should initially investigate the symptoms without assuming the root cause.

---

# 9. Inspect Kubernetes State

Start at the platform layer:

```bash
kubectl -n "$NS" get pods -o wide
kubectl -n "$NS" describe pod elasticsearch-2
```

Review Pod status, restart count, worker placement, Pod IP, readiness, age, init containers, container state, mounted volumes, events, probes, scheduling, and termination history.

A Pod reported as Running does not prove successful Elasticsearch membership. Similarly, `OOMKilled` proves the container was terminated by the applicable memory-control mechanism; it does not by itself prove Java heap exhaustion was the underlying application cause.

---

# 10. Inspect Current and Previous Logs

Capture both current and previous container logs where available:

```bash
kubectl -n "$NS" logs elasticsearch-2
kubectl -n "$NS" logs elasticsearch-2 --previous
```

Look for transport, SSL handshake, certificate trust, PKIX, CertPath, x509, SAN verification, peer identity, cluster join, and connection-failure evidence.

Do not accept unrelated startup feature names or generic certificate-related words as proof. The evidence must correlate to the affected node and transport failure.

---

# 11. Verify Elasticsearch Identity

```bash
curl --cacert "$ES_CA" \
  -u "$ES_USER:$ES_PASSWORD" \
  "$ES_URL/?pretty"
```

Confirm `cluster_name`, `cluster_uuid`, and version. Compare the UUID with the approved baseline.

If the UUID unexpectedly changes: **STOP.**

Do not attempt to repair the condition by adding `cluster.initial_master_nodes`, deleting data directories/PVCs, forcing shard allocation, or rebuilding cluster state. First establish why cluster identity changed.

---

# 12. Verify Elasticsearch Membership, Master, and Roles

```bash
curl --cacert "$ES_CA" \
  -u "$ES_USER:$ES_PASSWORD" \
  "$ES_URL/_cat/nodes?v&h=name,ip,node.role,master"
```

Compare Kubernetes Pods with Elasticsearch nodes. The scenario may show three Kubernetes Pods while Elasticsearch has only two nodes. Platform process existence and distributed-system membership are separate states.

Confirm the expected master election, master-eligible nodes, data roles, and absence of unexpected role drift.

---

# 13. Inspect Cluster Health and Shards

```bash
curl --cacert "$ES_CA" \
  -u "$ES_USER:$ES_PASSWORD" \
  "$ES_URL/_cluster/health?pretty"
```

Interpret correctly:

- **GREEN:** all required primary and replica shards are assigned.
- **YELLOW:** all primaries are assigned, but at least one replica is unassigned.
- **RED:** at least one primary shard is unassigned.

RED does not automatically mean the entire cluster is unavailable. It means at least one primary is unassigned, so data associated with affected primary shards may be unavailable.

Identify unassigned shards:

```bash
curl --cacert "$ES_CA" \
  -u "$ES_USER:$ES_PASSWORD" \
  "$ES_URL/_cat/shards?v&h=index,shard,prirep,state,node,unassigned.reason&s=state,index,shard"
```

For this scenario, the expected unhealthy state contains an unassigned **replica**, not an unavailable primary.

---

# 14. Use Targeted Allocation Explain

Select an actual unassigned replica and query:

```bash
curl --cacert "$ES_CA" \
  -u "$ES_USER:$ES_PASSWORD" \
  -H 'Content-Type: application/json' \
  "$ES_URL/_cluster/allocation/explain?pretty" \
  -d '{
    "index": "installation-validation-v1",
    "shard": <SHARD_NUMBER>,
    "primary": false
  }'
```

Inspect `current_state`, `unassigned_info`, `can_allocate`, `allocate_explanation`, `node_allocation_decisions`, and `deciders`.

The deterministic scenario should expose the allocation restriction as a `NO` decision preventing replica allocation.

---

# 15. Inspect Allocation Settings

Index settings:

```bash
curl --cacert "$ES_CA" \
  -u "$ES_USER:$ES_PASSWORD" \
  "$ES_URL/installation-validation-v1/_settings?flat_settings=true&include_defaults=true&pretty"
```

Review `index.routing.allocation.*`.

Cluster settings:

```bash
curl --cacert "$ES_CA" \
  -u "$ES_USER:$ES_PASSWORD" \
  "$ES_URL/_cluster/settings?flat_settings=true&include_defaults=true&pretty"
```

Review `cluster.routing.allocation.*`. In the injected scenario, evidence should reveal `cluster.routing.allocation.enable = primaries`.

The operator must distinguish an explicit persistent setting from default behavior because no explicit setting exists. This distinction matters during restoration.

---

# 16. Review Discovery and Bootstrap Configuration

Review `discovery.seed_hosts` and `cluster.initial_master_nodes`.

`discovery.seed_hosts` supports normal discovery and cluster rejoin. `cluster.initial_master_nodes` has a fundamentally different purpose: initial bootstrap of a brand-new cluster.

After the cluster has formed, `cluster.initial_master_nodes` must be removed and must not be configured again for that cluster. It must not be added to a joining node, a normally restarting node, a full-cluster restart, or an existing cluster as a troubleshooting shortcut.

---

# 17. Validate Transport TLS Configuration

Validate the affected node's CA, certificate, validity, SANs, key/certificate pairing, mounted Secret/configuration, filesystem permissions, certificate path, transport identity, and actual peer DNS/IP. Do not expose the private key while collecting evidence.

The investigation should answer:

- Which identity is Elasticsearch using for the peer?
- Does the certificate validate for that identity?
- Is the certificate signed by the expected trusted CA?
- Is the node loading the intended certificate and key?
- Does Elasticsearch log an actual failed secure transport operation?

---

# 18. Root Cause Evidence Gate

The TLS hypothesis is accepted only when concrete evidence exists. Acceptable evidence includes an actual transport failure involving constructs such as:

```text
SSLHandshakeException
failed to establish trust
PKIX path building failed
unable to find valid certification path
CertPath validation failure
unknown_ca
bad_certificate
SAN/hostname verification failure
x509 validation/trust failure
failed SSL/TLS handshake
equivalent Elasticsearch transport exception
```

A generic log line containing `certificate_identity_field` is not evidence. Neither is an unrelated TLS failure from another node if it does not prove the failure associated with `elasticsearch-2`.

Evidence should be fresh, transport-related, failure-specific, and node-2-related. For the validated implementation, failure evidence emitted by `elasticsearch-2` itself is required.

---

# 19. First Remediation — Correct Transport TLS

Restore the approved transport TLS material for `elasticsearch-2`. Restart only the affected node. Do not restart the entire cluster blindly.

Then verify three Elasticsearch nodes and recheck cluster identity. The UUID must match the baseline.

---

# 20. Critical Intermediate Validation

Do **not** declare recovery complete merely because `elasticsearch-2` rejoined.

The deterministic scenario intentionally keeps `cluster.routing.allocation.enable = primaries` active.

Expected intermediate state:

```text
3 nodes
same cluster UUID
node 2 rejoined
transport TLS repaired
YELLOW
unassigned replica remains
```

This proves:

```text
Node rejoined ≠ Incident resolved
```

and separates the transport-security root failure from the lingering allocation restriction.

---

# 21. Second Remediation — Restore Allocation State

Restore the exact state that existed before the scenario.

If the setting was originally explicitly configured, restore that exact value. If no persistent override originally existed, clear the temporary override instead of assuming an explicit value such as `all` should remain.

For an originally absent persistent setting:

```json
{
  "persistent": {
    "cluster.routing.allocation.enable": null
  }
}
```

Do not blindly overwrite legitimate pre-existing operational configuration.

---

# 22. Monitor Replica Recovery

Monitor recovery while allocation is restored:

```bash
curl --cacert "$ES_CA" \
  -u "$ES_USER:$ES_PASSWORD" \
  "$ES_URL/_cat/recovery/installation-validation-v1?format=json"
```

The validated implementation captures recovery repeatedly because a small validation index can recover between individual polling intervals.

Evidence must distinguish fresh recovery caused by this remediation from stale/pre-existing recovery records. Recovery evidence should correlate the previously unassigned replica with a new peer recovery to its final target node.

---

# 23. Final Recovery Validation

Verify final cluster health:

```bash
curl --cacert "$ES_CA" \
  -u "$ES_USER:$ES_PASSWORD" \
  "$ES_URL/_cluster/health?pretty"
```

Expected:

```text
status                green
number_of_nodes       3
unassigned_shards     0
initializing_shards   0
relocating_shards     0
```

GREEN is necessary for this scenario's acceptance gate, but it does not replace root-cause evidence.

Validate data preservation:

```bash
curl --cacert "$ES_CA" \
  -u "$ES_USER:$ES_PASSWORD" \
  "$ES_URL/installation-validation-v1/_count?pretty"
```

Expected document count: `4`.

---

# 24. Validate Storage Continuity

Compare pre-failure and post-recovery storage identity. For each StatefulSet ordinal, verify PVC name, PVC UID, bound PV, and storage source.

A Pod UID is expected to change when the Pod is recreated. That is not a storage failure.

The important relationship is:

```text
new Pod
   ↓
same expected PVC identity
   ↓
same expected bound PV/storage
   ↓
same Elasticsearch data
```

Unexpected PVC or PV replacement requires investigation.

---

# 25. Validate Configuration Cleanup

Confirm `cluster.initial_master_nodes` remains absent from runtime configuration. The incident must not be solved by reintroducing bootstrap configuration.

Inspect final cluster settings and confirm the temporary allocation restriction has been removed or restored exactly to its legitimate pre-scenario value. Also confirm that no unrelated maintenance override remains.

Confirm the intentionally invalid transport TLS material is no longer active and that the correct certificate, expected CA, expected SAN/identity relationship, and secure node communication are restored.

Do not leave the lab in a state where a future restart silently reintroduces the failure.

---

# 26. Final Security Validation

Positive trusted/authenticated access must succeed:

```bash
curl --cacert "$ES_CA" \
  -u "$ES_USER:$ES_PASSWORD" \
  "$ES_URL/_cluster/health?pretty"
```

A negative authentication test using deliberately incorrect credentials must return HTTP `401`.

The purpose is to prove successful recovery did not occur by disabling authentication.

---

# 27. Host and Runtime Validation

For the reference Linux/Kubernetes lab, validate:

```text
vm.max_map_count >= 1048576
```

Do not claim every lower value automatically prevents Elasticsearch startup.

Validate the runtime file-descriptor limit against the reference production prerequisite:

```text
>= 65535
```

These checks validate the reference environment; they are not substitutes for diagnosing the injected TLS and allocation failures.

---

# 28. RED-State Safety Branch

If the investigation encounters RED:

```text
RED
 ↓
identify unassigned primary
 ↓
run targeted Allocation Explain
 ↓
determine whether a valid shard copy exists
```

If normal valid copies exist, continue normal recovery investigation.

If evidence indicates `no_valid_shard_copy`, or no trustworthy valid primary copy is available:

```text
STOP
 ↓
preserve evidence
 ↓
invoke the approved disaster-recovery procedure
```

Do not casually use `allocate_stale_primary` or `allocate_empty_primary` during normal troubleshooting. Those actions can involve data-loss consequences and are outside this scenario's standard remediation path.

---

# 29. Additional STOP Conditions

Stop normal remediation and escalate when any of the following occurs:

- unexpected cluster UUID or cluster name;
- loss of master/quorum;
- unavailable primary with no understood recovery path;
- unexpected PVC/PV replacement;
- unexplained data loss;
- security degradation outside the intended lab injection;
- failure spreads outside the isolated scenario;
- recovery behavior is no longer understood;
- evidence contradicts the expected failure model.

The correct response to uncertainty in a distributed data system is not increasingly destructive experimentation.

---

# 30. Root Cause Analysis

## Root Cause

A transport TLS identity/trust configuration defect on `elasticsearch-2` prevented the node from establishing the trusted transport communication required to join the intended Elasticsearch cluster. Concrete transport-security failure evidence is required to establish this cause.

## Contributing Factor

A temporary `cluster.routing.allocation.enable=primaries` setting remained active. When replicas became unassigned after node loss, new replica allocations were prevented, leaving the validation index YELLOW even after the transport TLS defect was repaired and the node rejoined.

## Control / Process Gap

Deployment acceptance depended too heavily on Kubernetes workload state. It did not sufficiently require Elasticsearch-level validation of cluster identity, membership, transport security, shard allocation, persistent storage, restart/rejoin behavior, configuration restoration, and recovery completion.

---

# 31. Evidence Chain

A production-quality investigation should preserve:

```text
Approved design
      ↓
Git / IaC configuration
      ↓
Deployment state
      ↓
Runtime state
      ↓
Failure evidence
      ↓
Diagnostic evidence
      ↓
Remediation evidence
      ↓
Recovery evidence
      ↓
Final acceptance evidence
```

A screenshot of GREEN health alone is not a complete incident record.

---

# 32. Recommended Evidence Package

```text
scenario-02/
├── baseline-cluster-identity.json
├── baseline-nodes.json
├── baseline-health.json
├── baseline-shards.json
├── baseline-cluster-settings.json
├── baseline-pods.txt
├── baseline-pvcs.json
├── baseline-pvs.json
├── allocation-restriction.json
├── failure-pods.txt
├── elasticsearch-2-describe.txt
├── elasticsearch-2-current.log
├── elasticsearch-2-previous.log
├── transport-tls-failure-evidence.txt
├── failure-cluster-identity.json
├── failure-nodes.json
├── failure-health.json
├── failure-shards.json
├── index-settings.json
├── cluster-settings.json
├── allocation-explain.json
├── post-tls-repair-identity.json
├── post-rejoin-pre-allocation-restore-health.json
├── allocation-restored.json
├── recovery/
├── final-health.json
├── final-cluster-settings.json
├── final-index-count.json
├── final-pvcs.json
├── final-pvs.json
├── pvc-continuity.diff
├── negative-auth.json
└── validation-result.txt
```

Exact filenames may vary by implementation. Evidence quality matters more than filename numbering.

Before retaining or publishing evidence, scan for private-key markers, unredacted Basic Authorization headers, passwords, API keys, bearer tokens, reusable credentials, real patient information, and production-sensitive data. Do not store private keys in CI artifacts. Synthetic healthcare-style validation data must remain synthetic.

---

# 33. Final Recovery Gate

Do not close the incident until all applicable conditions are proven:

```text
[ ] Expected cluster name
[ ] Same approved cluster UUID
[ ] 3 expected Elasticsearch nodes
[ ] Expected master and roles
[ ] Transport TLS healthy
[ ] HTTP TLS healthy
[ ] Authentication healthy
[ ] GREEN
[ ] 0 unassigned shards
[ ] Recovery complete
[ ] PVC identity preserved
[ ] PV/storage continuity preserved
[ ] Validation documents = 4
[ ] cluster.initial_master_nodes absent
[ ] Discovery/rejoin configuration valid
[ ] Original allocation state restored
[ ] No unintended maintenance settings remain
[ ] Failure-injection material removed
[ ] Monitoring healthy
[ ] Evidence sanitized
```

---

# 34. Implementation Validation Gate

The implementation is accepted only when all 34 scenario-validation checks pass:

1. healthy 3-node baseline;
2. GREEN baseline;
3. approved UUID;
4. four documents;
5. bootstrap absence;
6. storage identity;
7. original allocation state;
8. allocation restriction;
9. TLS failure injection;
10. node-2 restart;
11. Kubernetes versus Elasticsearch membership;
12. concrete TLS failure evidence;
13. unassigned replica;
14. `unassigned.reason`;
15. targeted Allocation Explain;
16. index allocation settings;
17. cluster allocation settings;
18. TLS repair;
19. node rejoin;
20. UUID preservation;
21. incomplete recovery after node rejoin;
22. exact allocation-state restoration;
23. fresh recovery monitoring;
24. final GREEN;
25. zero unassigned shards;
26. PVC UID continuity;
27. PV continuity;
28. four documents preserved;
29. bootstrap still absent;
30. temporary settings removed/restored;
31. failure-injection configuration removed;
32. security validation including HTTP 401 negative authentication;
33. evidence sanitization and retention;
34. successful cleanup and lab reusability.

A green CI job alone does not satisfy this gate. The captured evidence must independently support the required assertions.

The implementation acceptance gate is:

```text
Failure reproducible
Failure observable
Evidence explains failure
Remediation reproducible
Intermediate incomplete-recovery state demonstrated
Final recovery reproducible
Cluster UUID preserved
Storage preserved
Data preserved
Security restored
Configuration cleaned up
Environment cleanly reusable
```

---

# 35. Core Lessons

1. **Kubernetes healthy ≠ Elasticsearch healthy.** Always verify Elasticsearch membership and identity directly.
2. **Node rejoined ≠ Incident resolved.** Check shard allocation and recovery after membership is restored.
3. **GREEN ≠ Root cause understood.** A recovered system still requires evidence explaining the failure.
4. Temporary maintenance settings are production configuration. Record their original state and restore it exactly.
5. Cluster UUID is a critical identity invariant. Unexpected identity change is a STOP condition.
6. Persistent-storage identity must be validated independently from Pod identity.
7. TLS errors require concrete security evidence. Generic words in logs are not proof.
8. Allocation Explain is more valuable than guessing why a shard is unassigned.
9. Recovery evidence must correspond to the recovery being investigated. Stale recovery records do not prove the current remediation worked.
10. Production troubleshooting should preserve evidence before applying destructive actions.

---

# 36. Official Elastic References

- Diagnose unassigned shards: https://www.elastic.co/docs/troubleshoot/elasticsearch/diagnose-unassigned-shards
- Cluster Allocation Explain API: https://www.elastic.co/docs/api/doc/elasticsearch/operation/operation-cluster-allocation-explain
- Cluster-level shard allocation settings: https://www.elastic.co/docs/reference/elasticsearch/configuration-reference/cluster-level-shard-allocation-routing-settings
- Discovery and cluster formation settings: https://www.elastic.co/docs/reference/elasticsearch/configuration-reference/discovery-cluster-formation-settings
- Bootstrapping a cluster: https://www.elastic.co/docs/deploy-manage/distributed-architecture/discovery-cluster-formation/modules-discovery-bootstrap-cluster
- Basic security / transport TLS: https://www.elastic.co/docs/deploy-manage/security/set-up-basic-security
- `vm.max_map_count`: https://www.elastic.co/docs/deploy-manage/deploy/self-managed/vm-max-map-count

---

# 37. Scenario Completion

The scenario is complete only after the operator can explain the complete causal chain:

```text
Transport TLS defect
        ↓
elasticsearch-2 cannot securely participate
        ↓
Elasticsearch membership falls
        ↓
replicas become unassigned
        ↓
allocation.enable=primaries prevents new replica allocation
        ↓
cluster remains YELLOW
        ↓
TLS repaired
        ↓
node rejoins
        ↓
cluster still YELLOW
        ↓
original allocation state restored
        ↓
fresh replica peer recovery occurs
        ↓
GREEN
        ↓
UUID + storage + data + security preserved
        ↓
temporary configuration removed
```

That is the difference between merely restoring service and performing production-grade Elasticsearch troubleshooting.
