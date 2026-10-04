# 20 — Administration Runbook and Acceptance

**Status:** Draft

**Audience:** Redis Enterprise administrators, SREs, and DBREs.

## Daily administration checklist

| Area | Check |
|---|---|
| Cluster | Node health, alerts, quorum-related warnings |
| Databases | Availability, endpoints, owner and configuration |
| Shards | Primary/replica health and placement |
| Capacity | CPU, memory, persistence disk and headroom |
| Application | Latency, errors, hit rate, source fallback |
| Recovery | Recent backup success and restore evidence |
| Security | Certificate expiry and authentication failures |

Tune review frequency to the environment and workload.

## Incident workflow

1. Record database, endpoint, time window, impact, and recent changes.
2. Check application symptoms and management alerts.
3. Inspect nodes/shards rather than aggregate metrics alone.
4. Correlate cache errors, eviction, persistence, and source fallback.
5. Apply a targeted mitigation with defined rollback.
6. Verify recovery and document evidence.

Where supported and permitted:
```redis
PING
INFO stats
INFO memory
INFO clients
SLOWLOG GET 10
```

Confirm the scope of INFO through the endpoint; use Enterprise monitoring for complete topology. Handle slowlog arguments as sensitive evidence.

## Administration acceptance lab

In staging, collect evidence for: secure database creation, denied unauthorized access, capacity review, planned failover, isolated backup restore, and maintenance rehearsal. Use Tutorials 13–19.

| Evidence | Required result |
|---|---|
| Connectivity | Verified TLS and scoped read/write |
| Failure handling | Measured recovery and bounded fallback |
| Restore | Usable restored data within target time |
| Capacity | Enough headroom for planned failure scenario |
| Maintenance | Supported process and verified recovery |
| Ownership | Runbook, alert routing, and escalation owner |

Mark each pass/fail/pending. Missing evidence is not a pass.

## Completion and references

Acceptance: operational ownership and reviewed evidence across the administration track. Review configuration drift and readiness after significant changes.

- [Monitoring](https://redis.io/docs/latest/operate/rs/monitoring/)
- [Troubleshooting](https://redis.io/docs/latest/operate/rs/troubleshooting/)
