# Redis Enterprise Tutorial Review

Reviewed: 2026-10-03
Base commit: 304d61c1f406a6e7bab7c486c18bc843e4f333d2

## Result

All 23 tutorials received an offline content and operational review. Relative Markdown links resolve, code fences are balanced, and all seven embedded Python blocks parse.

The standard-library validation script executes the actual cache-aside function and Tutorial 12 lab against an in-memory cache model. It does not connect to Redis.

## Fixes

| Area | Finding | Change |
|---|---|---|
| Cache-aside | Valid JSON could have an incompatible payload shape | Validate product ID, name, and numeric price before returning a hit |
| Restore lab | Expiring marker could disappear before recovery verification | Use a disposable persistent marker and explicit cleanup in both databases |
| Slowlog | Standalone client attribution fields were not explicitly distinguished | Document Enterprise omission of client IP, port, and name |
| Navigation | Tutorial 12 still referred to an absent administrator series | Link the existing administration track |

## Offline behavior checks

- Miss populates the cache; a hit avoids another source read.
- Source update plus invalidation reloads the new value.
- Expiration triggers reload.
- Invalid JSON, null, array, wrong product ID, and boolean price trigger source fallback.
- Cache read failure and write failure preserve the source result.
- Missing source records are not cached.
- Source errors propagate.
- Tutorial 12's actual assertions pass using virtual time and a simulated outage.

## Run the offline check

From the repository root:

```bash
python redis-enterprise/tools/validate_tutorials.py
```

No additional package, server, credentials, or network is required.

## Production review findings

| Track | Reviewed guidance | Remaining acceptance evidence |
|---|---|---|
| 01–12 Application caching | TTL, schema, invalidation races, bounded workload/fallback, stampede controls | Actual client/TLS compatibility, concurrency, source protection, freshness behavior |
| 13–20 Administration | Managed configuration, failure domains, staging changes, backup restore, supported upgrade paths | Exact deployed version and topology, failover, restore, rotation, maintenance rehearsal |
| 21–23 Operations | Metric scope, version-specific monitoring, sensitive evidence, targeted mitigation | Actual scrape coverage, metric units, dashboards, alert delivery and incident exercise |

The administration instructions deliberately use release-specific vendor workflows rather than generic destructive commands. Site-specific command sequences must be reviewed against the deployed platform and change process.

## Live validation — pending

No Redis server, redis-cli, redis-py installation, or user-supplied test endpoint was available in this execution environment. Offline simulation does not validate Enterprise proxy semantics, TLS/authentication, the client library runtime, sharding, persistence, backup artifacts, failover, performance, or actual alert delivery.

Required staging information: product/deployment type, platform and database versions, endpoint/network access, trusted certificates, scoped test identity supplied securely, and permission/scope for staging exercises. Do not place credentials in the repository.

Run read/write and TLS tests first. Perform failover, restore, rotation and upgrade rehearsals only in an appropriately isolated staging environment. Record actual timestamps, versions, results, latency, and recovery time.

## Status decision

All tutorials remain Draft. Offline review is complete; live validation and environment-specific production acceptance are pending. No tutorial is declared canonical or production-ready on simulated evidence.

## Advanced extension — 2026-10-04

Tutorials 24–36 were added for the agreed advanced scope. Offline validation now parses eight Python blocks and checks all relative links/fences. Existing cache-aside and capstone simulations remain unchanged. Advanced transaction, stream, Search, client pool and platform labs were not executed. Full technical review, deployed-version compatibility and live acceptance remain pending for the new track. See Tutorial 36 for the evidence matrix.

