# Part 4 — Users, Roles & Security

**Status:** LOCKED — Master Layout v1.0
**Target:** PostgreSQL 18

## Objective

Build the PostgreSQL security-administration skills required to design identities, ownership boundaries, role membership, object privileges, authentication, transport security, row-level controls, and evidence-based access validation without confusing authentication, authorization, ownership, or application policy.

Part 4 follows the same 15-section progression used by Parts 1–3. Each section contributes a reusable SAFE-READ inspection artifact toward the integrated application-access project in 4.15. Mutating security configuration remains an explicit, isolated lab or reviewed administrative change.

## Master Layout — 4.1–4.15

| Section | Title | Primary Hands-On Outcome |
| --- | --- | --- |
| **4.1** | **PostgreSQL Security Model Fundamentals** | Distinguish login identity, session identity, effective role, role membership, ownership, object privileges, authentication, authorization, and policy enforcement. |
| **4.2** | **Role Creation, Attributes, and Lifecycle Administration** | Design and inspect login, non-login, service, owner, and administrative roles while controlling powerful attributes and credential lifecycle. |
| **4.3** | **Role Membership, Inheritance, and `SET ROLE`** | Build and validate role hierarchies using PostgreSQL 18 membership options, explicit privilege inheritance, controlled role switching, and administration boundaries. |
| **4.4** | **Ownership and Deployment/Runtime Role Separation** | Separate object ownership, migration, runtime, read-only, support, and administrative responsibilities and plan safe ownership reassignment. |
| **4.5** | **Database, Schema, and Secure `search_path` Privileges** | Administer `CONNECT`, `TEMPORARY`, database `CREATE`, schema `USAGE`/`CREATE`, `PUBLIC`, and object-resolution boundaries safely. |
| **4.6** | **Table, View, and Column Privileges** | Grant, revoke, inspect, and validate least-privilege access for tables, views, materialized views, and selected columns. |
| **4.7** | **Sequence, Routine, Type, and Maintenance Privileges** | Validate `USAGE`/`SELECT`/`UPDATE` on sequences, `EXECUTE` on routines, type privileges, and PostgreSQL 18 `MAINTAIN` boundaries. |
| **4.8** | **Default Privileges and Future-Object Access** | Design owner-specific, schema-scoped default privileges and prove how they affect only objects created later by the targeted creating role. |
| **4.9** | **Effective Privilege Auditing and Access Evidence** | Expand ACLs, trace grantors and grant options, account for ownership and membership, and test effective access with supported privilege-check functions. |
| **4.10** | **`SECURITY DEFINER` and Privileged Routine Hardening** | Review privileged routines for ownership, `EXECUTE`, secure name resolution, qualification, configuration, dependency, and privilege-escalation risks. |
| **4.11** | **Row-Level Security Design and Validation** | Create and validate permissive/restrictive policies, command/role scope, `USING`/`WITH CHECK`, default-deny behavior, owner bypass, and forced RLS boundaries. |
| **4.12** | **Authentication Architecture and `pg_hba.conf` Policy** | Design ordered client-authentication rules, inspect parsed HBA state, use SCRAM deliberately, and troubleshoot rule matching without exposing credentials. |
| **4.13** | **TLS, Client Certificates, and Connection Security** | Validate encrypted connections, server/client verification expectations, certificate-authentication boundaries, and session-level TLS evidence. |
| **4.14** | **Security Baseline, Drift Detection, and Access Validation** | Assemble a versioned hard-gate/review-signal baseline for roles, memberships, ownership, privileges, RLS, HBA parsing, TLS, and dangerous security drift. |
| **4.15** | **Integrated Project — Build and Validate an Application Access Model** | Implement and validate owner, migration, application, read-only, support, and administrative access for an isolated application database. |

## Learning Progression

**Security Model → Role Lifecycle → Membership & Role Switching → Ownership Separation → Database/Schema Privileges → Object Privileges → Default Privileges → Effective Access → Privileged Routines → RLS → Authentication → TLS → Security Baseline → Integrated Project**

## Scope Boundaries

Part 4 focuses on PostgreSQL identities, privileges, ownership, authentication policy, transport security, and row-level access controls.

- Part 2 owns installation and general server-configuration mechanics. Part 4 owns the security design, review, and validation of `pg_hba.conf`, authentication methods, and TLS-related settings.
- Part 3 owns database/schema/object lifecycle administration. Part 4 owns who may create, own, use, alter, maintain, or execute those objects.
- Part 5 covers storage and WAL internals. Encryption at rest, disk encryption, KMS/HSM design, operating-system hardening, network firewalls, cloud IAM, secret-manager implementation, and certificate-authority operations require platform-specific controls outside this PostgreSQL-only track.
- Part 13 covers broad monitoring and observability. Part 4 defines security evidence and drift signals but does not become a complete SIEM, audit-retention, or compliance program.

Security labels, external identity providers, LDAP, GSSAPI, SSPI, PAM, RADIUS, cloud IAM database authentication, and audit extensions may be introduced as integration patterns, but vendor/platform deployment details belong in the applicable AWS, Azure, GCP, or enterprise identity track.

## PostgreSQL 18 Technical Baseline

Part 4 must account for PostgreSQL 18 behavior and terminology, including:

- roles subsuming historical user/group concepts;
- cluster-wide role identity versus per-database object privileges;
- role attributes that are not ordinary inherited object privileges;
- membership-specific `ADMIN`, `INHERIT`, and `SET` options;
- `session_user`, `current_user`, `current_role`, and `SET ROLE` semantics;
- implicit owner authority and the difference between ownership and grantable ACL privileges;
- object-type-specific privileges, including `MAINTAIN`, parameter `SET`, and `ALTER SYSTEM`;
- built-in default privileges for `PUBLIC`, especially database `CONNECT`/`TEMPORARY` and routine `EXECUTE`;
- creator-role and schema behavior of `ALTER DEFAULT PRIVILEGES`;
- privilege-check functions and catalog visibility limits;
- `SECURITY INVOKER` versus `SECURITY DEFINER` execution;
- row-security enablement, policies, bypass behavior, and default deny;
- ordered HBA matching and `pg_hba_file_rules` diagnostics;
- SCRAM authentication and TLS/client-certificate boundaries;
- predefined roles and the security implications of broad monitoring, file, signal, and settings access.

PostgreSQL 18-specific features or catalog fields must not be silently generalized to older server versions.

## Integrated Project — 4.15

The final project must require the learner to perform a complete application-access workflow rather than repeat isolated grants:

1. Define the application, data classification, trust boundaries, and access contract.
2. Use an isolated PostgreSQL 18 lab database and synthetic data only.
3. Define naming conventions and an authoritative role manifest.
4. Create a non-login owner role.
5. Create a controlled migration/deployment role with an explicit path to the owner role.
6. Create separate application read-write, application read-only, analyst/read-only, support, and break-glass/admin role categories as justified by the contract.
7. Keep application login roles from owning application objects.
8. Configure membership `ADMIN`, `INHERIT`, and `SET` options deliberately.
9. Define database and schema privileges, including the intended treatment of `PUBLIC`.
10. Define table, view, materialized-view, sequence, and routine privileges.
11. Configure default privileges under the correct future object-creating role.
12. Validate current-object and future-object access separately.
13. Create or inspect one hardened `SECURITY DEFINER` boundary only if the design requires privileged delegation.
14. Create and test an RLS policy model on isolated tutorial data.
15. Design ordered HBA rules and validate parsed configuration without exposing secrets.
16. Validate TLS state and distinguish encryption from server identity verification.
17. Inventory role attributes, memberships, owners, ACLs, grant options, routine security, and RLS policies.
18. Test effective allow and deny cases for every application persona.
19. Identify access paths catalogs cannot fully prove, including external identity, network, pooler, secret, and application behavior.
20. Produce a safe access-removal and incident-revocation plan.
21. Run the final SAFE-READ application-access acceptance suite.

The integrated project must not require real passwords in SQL, shell history, repository files, screenshots, or transcripts. Where login testing is necessary, use an approved secret mechanism and synthetic lab identities.

## Planned Lab Artifacts

```text
labs/
├── security-model-check.sql
├── role-lifecycle-check.sql
├── role-membership-check.sql
├── ownership-boundary-check.sql
├── database-schema-privilege-check.sql
├── table-column-privilege-check.sql
├── sequence-routine-privilege-check.sql
├── default-privilege-check.sql
├── effective-access-check.sql
├── security-definer-check.sql
├── row-security-check.sql
├── authentication-policy-check.sql
├── tls-connection-check.sql
├── security-baseline-check.sql
└── application-access-acceptance.sql
```

Inspection and acceptance artifacts default to **[TUTORIAL-ACCEPTANCE — SAFE-READ]** whenever their objective can be validated without mutation. Labs that create or alter roles, memberships, ownership, privileges, policies, routines, HBA rules, credentials, or TLS configuration must be explicitly marked **[LAB-ONLY — SECURITY-MUTATING]** or the applicable reviewed production-change classification.

## Production-Safety Rules

- Never place plaintext passwords, private keys, tokens, connection strings containing secrets, or production certificates in tutorial commands, files, output, or version control.
- Never use superuser, `BYPASSRLS`, `CREATEROLE`, predefined broad-access roles, or blanket `ALL PRIVILEGES` as shortcuts around an incomplete access design.
- Treat role membership, ownership, grant options, default privileges, `PUBLIC`, `SECURITY DEFINER`, RLS, HBA, password policy, and TLS changes as security-sensitive reviewed changes.
- Separate owner/migration identities from runtime identities and avoid personal ownership of application objects.
- Qualify security-sensitive object references and secure routine `search_path` behavior.
- Validate explicit deny cases; successful access tests alone do not prove least privilege.
- Do not infer effective access from a single ACL row. Account for ownership, membership, `PUBLIC`, grant options, default privileges, RLS, superuser/bypass behavior, routine execution, and external controls.
- Treat HBA as first-match policy and validate rule order before reload. Do not imply HBA alone grants object access.
- Treat TLS encryption, server-certificate verification, and client-certificate authentication as distinct properties.
- Use synthetic identities and data in labs. Sanitize transcripts because role names, memberships, object names, addresses, authentication rules, certificate metadata, and grants can be sensitive.
- Define break-glass authorization, expiry, monitoring, and revocation outside normal runtime access.
- Preserve an independent recovery path before changing access that could lock administrators out.

## Source and Copyright Rules

- Use PostgreSQL 18 official documentation as the primary technical source.
- Cite vendor pages directly and paraphrase rather than reproducing substantial vendor text.
- Use original diagrams, examples, role names, data, and explanations.
- Do not include proprietary HBA files, real directory-service information, production addresses, certificates, usernames, passwords, or customer access models.

## Canonical Workflow

Each section follows:

1. Draft + Hands-On Lab
2. Technical + PostgreSQL 18 Vendor Source Review
3. Production + Safety + Copyright Review
4. Revised Final / Canonical Edition + canonical acceptance artifact
5. Commit to `main`, update Part 4 status, fetch back, and verify

## Lock Declaration

This document is the authoritative **Part 4 — Users, Roles & Security — Master Layout v1.0**.

The section numbering, primary scope, integrated-project contract, and planned artifact names for **4.1–4.15 are locked**. Later structural changes must be intentional, reviewed, and recorded rather than introduced implicitly while drafting individual tutorials.

**Next workflow stage:** Part 4.1 — PostgreSQL Security Model Fundamentals → Draft + Hands-On Lab.

## Primary PostgreSQL 18 References

- [Database Roles](https://www.postgresql.org/docs/18/user-manag.html)
- [Role Membership](https://www.postgresql.org/docs/18/role-membership.html)
- [Privileges](https://www.postgresql.org/docs/18/ddl-priv.html)
- [`ALTER DEFAULT PRIVILEGES`](https://www.postgresql.org/docs/18/sql-alterdefaultprivileges.html)
- [Function Security](https://www.postgresql.org/docs/18/perm-functions.html)
- [Row Security Policies](https://www.postgresql.org/docs/18/ddl-rowsecurity.html)
- [`pg_hba.conf`](https://www.postgresql.org/docs/18/auth-pg-hba-conf.html)
- [Secure TCP/IP Connections with SSL](https://www.postgresql.org/docs/18/ssl-tcp.html)
