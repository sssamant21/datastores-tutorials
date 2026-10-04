# 26 — Active-Active Geo-Distribution

**Status:** Draft; live lab not run.

**Objective:** Understand regional writes, convergence and recovery boundaries.

Active-Active lets participating clusters process local writes and synchronize supported data types using conflict-resolution semantics. Strong eventual consistency is not a promise that every regional read immediately sees every remote write. Conventional primary/replica failover and Active-Active are different architectures.

## Planning

Record regions/participants, supported commands/types, networking/TLS, regional endpoints, replication capacity, conflict semantics and application consistency needs. Budget synchronization and metadata overhead. Validate expiry/eviction/delete behavior for each used type. Do not assume distributed locks or cross-region uniqueness become globally safe.

## Two-region staging exercise

1. Use the release-specific workflow to create participating clusters and an isolated Active-Active database.
2. Verify synchronization health and secure connections to both local endpoints.
3. Write a unique test key in region A; observe it in B and measure visibility delay.
4. Apply controlled concurrent updates in A/B to the chosen data type.
5. Verify the documented converged result rather than assuming last arrival always wins.
6. In a scheduled drill, isolate the approved test synchronization path; continue bounded local writes, restore connectivity and verify convergence.
7. Clean exact test keys after all participants converge.

## Recovery and troubleshooting

Check sync health, regional resources, network, command compatibility and application routing. Rejoining/rebuilding a participant follows Active-Active disaster-recovery instructions, not an arbitrary snapshot merge. Define regional loss, stale-read and split-connectivity application behavior before production.

**Evidence:** local availability, convergence results, synchronization lag and participant-recovery rehearsal. A healthy local endpoint does not prove all regions agree.

## References

- [Active-Active](https://redis.io/docs/latest/operate/rs/databases/active-active/)

**Next:** [27 — Transactions and Programmability](27-transactions-and-programmability.md).
