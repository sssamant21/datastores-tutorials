# 28 — Extended Acceptance and Coverage

**Status:** Draft; live lab not run.

**Objective:** Close the practical Enterprise learning path with evidence for advanced features.

Complete Tutorial 17's baseline acceptance first. Use isolated staging, synthetic data and version-specific procedures. Mark deployment-dependent features Not applicable only with a documented reason; untested required behavior remains Not run.

## Advanced acceptance matrix

| Area | Exercise | Required evidence |
|---|---|---|
| Transactions | Abort, commit and driver failure/retry drill | Invariants hold; uncertain commit reconciled |
| Sharding | Targeted/broadcast plan comparison; skew review | Key rationale, routing, distribution and capacity |
| Drivers | Secure CRUD plus concurrent load | Pool wait, deadlines, retries, no secret logging |
| Modeling | v1/v2 compatible rollout/backfill | Old/new readers, counts, failed rows, rollback gate |
| Indexes | Partial/TTL tests and uniqueness review | Eligible queries, async expiry, constraints |
| Change streams | Restart from checkpoint and expired-history plan | Idempotency, no silent gaps, reconciliation |
| Time series | Insert/query/options/retention | Types, metadata, bucket/expiry expectations |
| Capped/GridFS | Buffer selection; file checksum round-trip | Overwrite policy; file/chunk cleanup |
| Security | Audit, encrypted restore, identity lifecycle | Required events/keys/allowed-denied behavior |
| Deployment | Recreation/replacement/rotation | Ownership, durable storage and reconnection |
| Recovery | Transaction/secondary/sharded scenario drill | Runbook, measured impact and data verification |

Select representative workload sizes and measurable thresholds. A small syntax-valid example does not prove production scale or resilience. Record server/FCV, driver/tools/controller versions for every drill.

## Result record

```text
Deployment / environment:
Test / tutorial:
Date and timezone:
Versions / configuration:
Expected result and threshold:
Observed result:
Pass / Fail / Not run / Not applicable:
Evidence location:
Remaining risk:
Owner / action / due date:
```

Keep credentials and sensitive datasets out of evidence. Review failures, retest meaningful fixes and obtain the deployment owner's readiness decision. Canonical status requires the review workflow, not merely having all files written.

## Coverage boundary

Tutorials 01–28 cover the agreed concise learning path: fundamentals, application use, administration, observability, troubleshooting and the advanced topics requested. They are not every MongoDB API, deployment variant or version-specific feature. Atlas-specific administration, Search/Vector Search, every programming language and specialized enterprise integration implementations can be separate tracks.

**Draft coverage complete for the agreed scope. Technical validation, production review and live acceptance remain pending.**

See [MASTER-LAYOUT.md](MASTER-LAYOUT.md) and [STATUS.md](STATUS.md).
