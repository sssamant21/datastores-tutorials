# Part 4 — Users, Roles & Security — Status

**Status:** ACTIVE
**Canonical progress:** **0/15 canonical + merged**
**Target:** PostgreSQL 18
**Authoritative layout:** `MASTER-LAYOUT.md` — LOCKED, Master Layout v1.0

| Section | Title | Status |
| --- | --- | --- |
| 4.1 | PostgreSQL Security Model Fundamentals | NEXT |
| 4.2 | Role Creation, Attributes, and Lifecycle Administration | PLANNED |
| 4.3 | Role Membership, Inheritance, and `SET ROLE` | PLANNED |
| 4.4 | Ownership and Deployment/Runtime Role Separation | PLANNED |
| 4.5 | Database, Schema, and Secure `search_path` Privileges | PLANNED |
| 4.6 | Table, View, and Column Privileges | PLANNED |
| 4.7 | Sequence, Routine, Type, and Maintenance Privileges | PLANNED |
| 4.8 | Default Privileges and Future-Object Access | PLANNED |
| 4.9 | Effective Privilege Auditing and Access Evidence | PLANNED |
| 4.10 | `SECURITY DEFINER` and Privileged Routine Hardening | PLANNED |
| 4.11 | Row-Level Security Design and Validation | PLANNED |
| 4.12 | Authentication Architecture and `pg_hba.conf` Policy | PLANNED |
| 4.13 | TLS, Client Certificates, and Connection Security | PLANNED |
| 4.14 | Security Baseline, Drift Detection, and Access Validation | PLANNED |
| 4.15 | Integrated Project — Build and Validate an Application Access Model | PLANNED |

## Planned canonical artifacts

| Section | Manuscript | Acceptance artifact |
| --- | --- | --- |
| 4.1 | `4.1-postgresql-security-model-fundamentals.md` | `labs/security-model-check.sql` |
| 4.2 | `4.2-role-creation-attributes-and-lifecycle-administration.md` | `labs/role-lifecycle-check.sql` |
| 4.3 | `4.3-role-membership-inheritance-and-set-role.md` | `labs/role-membership-check.sql` |
| 4.4 | `4.4-ownership-and-deployment-runtime-role-separation.md` | `labs/ownership-boundary-check.sql` |
| 4.5 | `4.5-database-schema-and-secure-search-path-privileges.md` | `labs/database-schema-privilege-check.sql` |
| 4.6 | `4.6-table-view-and-column-privileges.md` | `labs/table-column-privilege-check.sql` |
| 4.7 | `4.7-sequence-routine-type-and-maintenance-privileges.md` | `labs/sequence-routine-privilege-check.sql` |
| 4.8 | `4.8-default-privileges-and-future-object-access.md` | `labs/default-privilege-check.sql` |
| 4.9 | `4.9-effective-privilege-auditing-and-access-evidence.md` | `labs/effective-access-check.sql` |
| 4.10 | `4.10-security-definer-and-privileged-routine-hardening.md` | `labs/security-definer-check.sql` |
| 4.11 | `4.11-row-level-security-design-and-validation.md` | `labs/row-security-check.sql` |
| 4.12 | `4.12-authentication-architecture-and-pg-hba-policy.md` | `labs/authentication-policy-check.sql` |
| 4.13 | `4.13-tls-client-certificates-and-connection-security.md` | `labs/tls-connection-check.sql` |
| 4.14 | `4.14-security-baseline-drift-detection-and-access-validation.md` | `labs/security-baseline-check.sql` |
| 4.15 | `4.15-integrated-project-build-and-validate-an-application-access-model.md` | `labs/application-access-acceptance.sql` |

## Next workflow stage

Part 4.1 — PostgreSQL Security Model Fundamentals → Draft + Hands-On Lab.
