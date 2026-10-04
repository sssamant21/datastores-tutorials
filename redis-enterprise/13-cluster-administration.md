# 13 — Cluster Administration

**Status:** Draft

**Audience:** Redis Enterprise administrators, SREs, and DBREs.

## Scope and deployment

These administration pages target self-managed Redis Software. Redis Cloud has a different management plane; Kubernetes deployments must follow operator-specific procedures rather than host package commands.

Before installation, confirm the supported OS, resources, network ports, DNS, certificates, storage, license, and failure-domain design for your release. Use the vendor installation procedure rather than a generic Redis server installation.

## Administrative baseline

Record cluster name, platform version, nodes, failure domains, license capacity, database inventory, endpoints, and owners. Distinguish the management plane from application endpoints.

Use Cluster Manager or the supported management API to inspect node health and resource availability. Confirm all nodes are healthy and alerts are understood before changing topology.

## Node lifecycle

For additions, provision supported resources, join through the release-specific procedure, verify health, then plan shard redistribution. Adding a node does not guarantee automatic workload improvement.

For removal, confirm redundancy and capacity first, move affected shards through supported workflows, and verify the node is safe to remove. Do not terminate a VM simply because it appears idle.

## Lab and acceptance

In staging, inventory nodes and map primary/replica placement and failure domains. Record available memory, CPU, disk, and network capacity. Compare the recorded inventory with monitoring.

Acceptance: healthy nodes, reachable management plane, known topology, and enough capacity for the intended failure scenario.

## References

- [Cluster management](https://redis.io/docs/latest/operate/rs/clusters/)
- [Installation and upgrades](https://redis.io/docs/latest/operate/rs/installing-upgrading/)

**Next:** [14 — Database Administration](14-database-administration.md)
