# 34 — Flex and Auto Tiering

**Status:** Draft; live lab not run.

**Objective:** Evaluate memory/storage tradeoffs with representative workload evidence.

Flex/Auto Tiering capabilities use memory and supported flash/storage resources according to product/version configuration. They are not ordinary RDB/AOF persistence settings. Verify feature availability, hardware, license, supported data types/commands and deployment limitations first.

## Capacity worksheet

| Resource | Include |
|---|---|
| RAM | Active working set, metadata, buffers and headroom |
| Flash/storage | Dataset, overhead, replication and maintenance |
| I/O | Read/write latency, throughput and device endurance |
| Failure capacity | Remaining resources during node loss/rebuild |
| Cost | Memory, storage, nodes, license and operational effort |

Do not infer expected latency solely from dataset size or advertised storage ratio. Hot/cold distribution, access skew, value sizes and writes affect performance.

## Staging evaluation

1. Provision supported tiered resources and create a test database through the documented workflow.
2. Record resource limits, tiering configuration, replication and persistence separately.
3. Load a bounded representative dataset with measured payload sizes.
4. Run warm reads, cold/random reads and mixed writes at agreed concurrency.
5. Compare application P95/P99, throughput, errors, tier-hit behavior and storage latency with the current design.
6. Rehearse supported failure/rebuild and isolated backup restore.

## Troubleshooting

Cold-read regression: examine tier accesses and storage latency. Capacity pressure: inspect actual RAM/storage accounting and skew. Write degradation: inspect I/O contention and concurrent maintenance. Improve workload/data design or provision resources based on the measured bottleneck.

**Acceptance:** cost improvement meets latency/error targets with adequate failure headroom; recovery remains verified. Retire only the lab database through supported workflow.

## References

- [Flex and Auto Tiering](https://redis.io/docs/latest/operate/rs/databases/flash/)

**Next:** [35 — Migration and Disaster Recovery](35-migration-and-disaster-recovery.md).
