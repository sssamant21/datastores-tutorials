# 36 — Extended Acceptance and Coverage

**Status:** Draft; live lab not run.

**Objective:** Close the practical Redis Enterprise learning path with advanced evidence.

Complete baseline application/administration acceptance from Tutorials 12 and 20 first. Use isolated staging and exact installed-version procedures. Not applicable requires a documented deployment reason; untested required behavior remains Not run.

| Area | Exercise | Evidence |
|---|---|---|
| Deployment | Reproducible staging build | Versions/configuration/security |
| Kubernetes | Reconciliation/replacement/rotation | Storage, status and recovery |
| Active-Active | Regional writes/partition/convergence | Semantic correctness and sync health |
| Transactions/scripts | EXEC errors, WATCH conflict, checked release | Scope, outcomes and bounded retries |
| Client | Concurrent pool load/failover | Deadline, reconnection and no overload |
| Advanced caching | Same-key loads/outage/repair | Fleet source budget and durable repair |
| Other use cases | Expiry/rate boundaries/ranking | Correctness and failure policy |
| Streams | Crash-before-ACK/reclaim | Idempotent effects and retention |
| JSON/Search | Update/query/index recovery | Readiness, memory and results |
| Automation | Drift and repeated apply | Idempotency and ownership |
| Tiering | Hot/cold workload/recovery | Latency/cost/failure headroom |
| DR/migration | Isolated full recovery/cutover | RPO/RTO and reconciliation |

## Record each result

```text
Environment / topology:
Test and tutorial:
Date / timezone:
Platform / database / client / Operator versions:
Expected result and threshold:
Observed result:
Pass / Fail / Not run / Not applicable:
Evidence location:
Risk / owner / follow-up:
```

Review failed cases and meaningful fixes before the deployment owner decides readiness. Do not use simulated checks to claim client runtime, TLS, sharding, failover, recovery or performance acceptance.

## Coverage boundary

01–23 cover caching and operational foundations. 24–35 cover the advanced topics agreed in this review; 36 integrates acceptance. This is a complete draft for that practical scope, not every Redis command, product or specialized integration. Redis Cloud administration, advanced vector/AI workloads and product-specific integrations can be separate tracks. Detailed platform mutations require deployed-version procedures.

**Draft topic coverage complete; live validation and production review pending.** See [STATUS.md](STATUS.md) and [MASTER-LAYOUT.md](MASTER-LAYOUT.md).
