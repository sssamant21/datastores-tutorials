# 17 — Production Readiness and Acceptance Lab

**Status:** Draft; live lab not run.

**Objective:** Demonstrate application operations, security, observability and recovery.

## Acceptance criteria

| Area | Evidence |
|---|---|
| Availability | Healthy topology/failure tolerance |
| Security | TLS, authentication, least privilege, network restrictions |
| Application | Critical read/write workflows |
| Performance | Representative latency/throughput targets |
| Capacity | CPU/memory/storage/growth headroom |
| Recovery | Restore meets agreed RPO/RTO |
| Observability | Fresh metrics/verified routing |
| Operations | Maintenance/incident procedures and owners |

Agree measurable targets first. Regular restore tests and database/host monitoring are production practices.

## Prepare

Dedicated staging deployment, representative configuration, synthetic data, separate application/monitoring identities and isolated restore target. Record versions, FCV, drivers, resources, topology and management owner. Use secure connection from Tutorial 02.

## Application operations

Connect as application identity, with primary read preference:
```javascript
use mongodb_tutorials
var acceptanceId = "tutorial-acceptance-" + new ObjectId().toHexString()
var acceptanceWrite = db.tutorial_acceptance.insertOne(
  { _id: acceptanceId, status: "created", createdAt: new Date() },
  { writeConcern: { w: "majority", j: true, wtimeout: 5000 } }
)
if (!acceptanceWrite.acknowledged) throw new Error("Insert not acknowledged")
var acceptanceRead = db.tutorial_acceptance.findOne({ _id: acceptanceId })
if (acceptanceRead?.status !== "created") throw new Error("Inserted document not found")
```

Update/verify:
```javascript
var acceptanceUpdate = db.tutorial_acceptance.updateOne(
  { _id: acceptanceId, status: "created" },
  { $set: { status: "verified" } },
  { writeConcern: { w: "majority", j: true, wtimeout: 5000 } }
)
if (acceptanceUpdate.modifiedCount !== 1) throw new Error("Update failed")
if (db.tutorial_acceptance.findOne({ _id: acceptanceId })?.status !== "verified") {
  throw new Error("Updated value incorrect")
}
```

Timeout may follow an applied write; investigate before manual retry. This proves basic shell operations, not application/driver correctness. Repeat real critical workflows.

## Security

Verify allowed operations; attempt an agreed read on an existing restricted test collection expecting authorization failure. Confirm certificate validation, approved secrets storage and network/admin restrictions. Use separate management/monitoring identities.

## Performance/observability

Run representative staging data/concurrency. Record workload, dataset, throughput, P95/P99, errors, CPU/memory/I/O, lag and result against targets. Confirm dashboard freshness and approved test alert delivery/owner. One-document CRUD supplies no capacity/performance evidence.

## Recovery/resilience

Follow Tutorial 11 for isolated restore. Verify records, indexes, options and application behavior; measure RPO/RTO.

In a separately scheduled staging drill, exercise planned primary transition through the owning workflow. Measure interruption, reconnection, retries and write outcomes. Record independently; logical restore does not prove failover.

## Cleanup/results

In original application session:
```javascript
var acceptanceCleanup = db.tutorial_acceptance.deleteOne(
  { _id: acceptanceId },
  { writeConcern: { w: "majority", j: true, wtimeout: 5000 } }
)
if (acceptanceCleanup.deletedCount !== 1) throw new Error("Cleanup failed")
```

Remove only this exercise's records/resources. The checks use standard JavaScript errors to remain compatible with mongosh.

| Test | Pass / Fail / Not run | Evidence | Owner |
|---|---|---|---|
| Application | | | |
| Security | | | |
| Performance/capacity | | | |
| Monitoring/alerts | | | |
| Restore | | | |
| Resilience | | | |
| Maintenance | | | |

Unperformed tests remain Not run. Record findings and obtain deployment-owner readiness decision.

## References

- [Operations checklist](https://www.mongodb.com/docs/manual/administration/production-checklist-operations/)
- [Security checklist](https://www.mongodb.com/docs/manual/administration/security-checklist/)
- [Write concern](https://www.mongodb.com/docs/manual/reference/write-concern/)

**Sequence:** 01–17 drafted. Live validation pending. See [STATUS.md](STATUS.md).
