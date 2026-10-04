# 25 — Enterprise Security and Key Management

**Status:** Draft; live lab not run.

**Objective:** Verify configured Enterprise controls and their recovery dependencies.

## Distinguish controls

| Control | Protects | Evidence |
|---|---|---|
| TLS | Network traffic | Validated certificate connection |
| Roles | Authorized actions | Allowed/denied operation tests |
| Auditing | Selected security/activity evidence | Expected events in protected destination |
| Encrypted storage engine | Data files at rest | Effective configuration and key-backed restore |
| Client-side field encryption | Selected values before server storage | Compatible client/key policy and query tests |
| External authentication | Identity integration | Login, mapping, revocation and outage tests |

Enterprise installation does not enable these automatically. Encryption at rest does not replace TLS, authorization or separately protected logical exports/logs.

## Read-only review lab

With approved administration access:
```javascript
db.adminCommand({ buildInfo: 1 })
db.adminCommand({ getCmdLineOpts: 1 })
db.adminCommand({ connectionStatus: 1, showPrivileges: true })
```

Review privately: options/privileges may contain operationally sensitive details. Check effective configuration in the owning management system as well; startup options alone do not prove complete end-to-end security.

## Audit validation

In staging, define event/filter/destination/retention policy. Perform an agreed test login and denied action; verify expected events, actor, timestamp and result. CRUD-success auditing requires suitable authorization-success settings/filtering and can add volume/overhead. Test log shipping, rotation and destination capacity. Audit records alone do not prove a transaction committed; aborted transaction operations can produce events.

## Encryption/key recovery

Choose supported KMIP or protected local-key workflow for the encrypted storage engine. Record key access, redundancy, rotation, revocation and recovery ownership. Rehearse an encrypted-backup restore with required keys and cipher-specific recovery instructions. Enabling encryption on existing data requires a supported migration, not merely adding a flag. Lost keys can make data unrecoverable.

## External identity

Choose a supported mechanism for the exact release/platform, such as Kerberos or supported LDAP integration. Verify lifecycle/deprecation policy before selection. Test identity mapping, least privilege, revocation, provider outage and protected emergency access. Client certificates for TLS do not automatically select X.509 database authentication.

**Acceptance:** every required control has configuration, behavioral evidence, owner and recovery procedure; gaps remain pending.

## References

- [Auditing](https://www.mongodb.com/docs/manual/core/auditing/)
- [Encryption at rest](https://www.mongodb.com/docs/manual/core/security-encryption-at-rest/)
- [Security checklist](https://www.mongodb.com/docs/manual/administration/security-checklist/)

**Next:** [26 — Deployment and Kubernetes Administration](26-deployment-and-kubernetes-administration.md).
