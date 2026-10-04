# 24 — Installation and Deployment

**Status:** Draft; live lab not run.

**Objective:** Build a reproducible staging Redis Software deployment.

## Choose deployment

| Platform | Management workflow |
|---|---|
| Supported Linux hosts | Redis Software installer and cluster management |
| Containers | Supported quickstart/deployment guidance; distinguish demo from production |
| Kubernetes | Operator and custom resources, Tutorial 25 |
| Redis Cloud | Managed-service workflow, separate from host installation |

Record exact platform/database version, supported OS/architecture, license, CPU/RAM, persistence storage, DNS, ports, certificates and failure domains. Match package and configuration to installed-version documentation. Do not substitute a standalone redis-server installation.

## Staging build exercise

1. Provision supported nodes and documented network/storage resources.
2. Obtain the exact supported package/image and verify provenance.
3. Install using that release's platform instructions.
4. Bootstrap cluster identity and management access securely.
5. Join additional nodes with the supported workflow; verify health and placement.
6. Create an isolated database following Tutorial 14.
7. Configure verified TLS and scoped application access before exposing the endpoint.
8. Run Tutorial 02's connection test from the application network.

In the connected test database:
```redis
PING
SET tutorial:deployment:check "ready" EX 60
GET tutorial:deployment:check
DEL tutorial:deployment:check
```

## Validation and problems

Record versions, nodes, endpoints, ownership and desired configuration. Verify monitoring, backup policy and failure capacity. Reproduce the build from recorded inputs in a second disposable environment.

Join failure: inspect DNS, routes, trust and version compatibility. Persistence failure: inspect mounts, permissions and free space. Installation success alone does not prove redundancy or application readiness. Remove only the lab deployment through its documented retirement workflow.

## References

- [Install/setup](https://redis.io/docs/latest/operate/rs/installing-upgrading/)
- [Cluster management](https://redis.io/docs/latest/operate/rs/clusters/)

**Next:** [25 — Kubernetes Operator Administration](25-kubernetes-operator-administration.md).
