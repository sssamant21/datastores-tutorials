# Chapter 73 --- Snowflake Terraform / Infrastructure as Code

## 73.1 Overview

Infrastructure as Code (IaC) manages Snowflake infrastructure through
version-controlled declarative code. A production flow is Terraform Code
→ Git → Pull Request → validation → `terraform plan` → approval →
`terraform apply` → Snowflake. Terraform can manage supported databases,
schemas, warehouses, roles, users/service users, grants, resource
monitors, integrations, policies, shares, and other provider-supported
resources.

## 73.2 Manual Administration

Direct Snowsight/SQL changes can create configuration drift,
inconsistent environments, weak review, missing documentation, difficult
rollback, and human error.

## 73.3 Terraform Administration

Terraform provides repeatability, version control, peer review,
auditability, environment consistency, automation, and drift detection.

## 73.4 Declarative Model

Terraform describes desired state:

``` hcl
resource "snowflake_database" "prod_db" {
  name = "PROD_DB"
}
```

## 73.5 Terraform Lifecycle

WRITE → INIT → VALIDATE → PLAN → REVIEW → APPLY → MONITOR.

## 73.6 Required Components

Terraform, Snowflake Terraform Provider, Snowflake account, automation
identity, appropriate role, secure authentication, and Git.

## 73.7 Verify Terraform

``` bash
terraform version
```

## 73.8 Repository Structure

Start with `versions.tf`, `providers.tf`, `variables.tf`, `outputs.tf`,
and `main.tf`; split into logical files/modules as complexity grows.

## 73.9 Required Provider

``` hcl
terraform {
  required_providers {
    snowflake = {
      source  = "snowflakedb/snowflake"
      version = "<approved-version>"
    }
  }
}
```

## 73.10 Why Pin Provider Versions?

Uncontrolled upgrades can introduce behavior/schema/resource changes,
deprecations, and unexpected plans.

## 73.11 Initialize Terraform

``` bash
terraform init
```

## 73.12 Validate Configuration

``` bash
terraform validate
```

## 73.13 Format Configuration

``` bash
terraform fmt
```

## 73.14 Do Not Hard-Code Credentials

Never embed passwords, private keys, tokens, or other secrets directly
in Terraform code.

## 73.15 Production Authentication

Use approved non-interactive authentication supported by the pinned
provider, such as key-pair, OAuth, workload identity, or secure CI/CD
secret injection.

## 73.16 Terraform Service Identity

Use a dedicated identity such as `SVC_TERRAFORM_SNOWFLAKE`, not a
personal administrator account.

## 73.17 Terraform Role

Use a dedicated `TERRAFORM_ROLE` with only the privileges required for
Terraform-owned resources.

## 73.18 Avoid ACCOUNTADMIN

Do not use `ACCOUNTADMIN` for routine Terraform automation except
narrowly controlled bootstrap work when genuinely required.

## 73.19 Provider Block

Keep provider configuration minimal and externalize environment-specific
authentication.

## 73.20 Environment Separation

Separate Development, Staging, and Production configuration/state
boundaries.

## 73.21 What Is Terraform State?

State maps Terraform configuration to managed Snowflake objects.

## 73.22 State Is Critical

State contains infrastructure metadata and can contain sensitive values;
protect it as infrastructure data.

## 73.23 Do Not Commit State to Git

Do not commit `terraform.tfstate` or `terraform.tfstate.backup`.

## 73.24 Remote State

Production should normally use an approved remote backend with
encryption, access control, versioning, locking where supported, and
recovery.

## 73.25 State Access

Restrict state access to required engineers and automation identities.

## 73.26 Generate Plan

``` bash
terraform plan
```

## 73.27 Saved Plan

``` bash
terraform plan -out=tfplan
terraform apply tfplan
```

## 73.28 Read the Plan

Understand `+ create`, `~ update`, `- destroy`, and `-/+ replace` before
approval.

## 73.29 Destructive Plan

Unexpected destroy or replace actions are a deployment stop condition
until investigated.

## 73.30 Database Resource

``` hcl
resource "snowflake_database" "prod_db" {
  name    = "PROD_DB"
  comment = "Production application database"
}
```

## 73.31 Terraform Ownership

Avoid unmanaged manual changes to Terraform-owned attributes; otherwise
desired and actual state drift.

## 73.32 Schema Resource

Conceptually:

``` hcl
resource "snowflake_schema" "empi" {
  database = snowflake_database.prod_db.name
  name     = "EMPI"
}
```

Validate syntax against the pinned provider.

## 73.33 Resource References

Prefer Terraform references over duplicated literal names where
practical.

## 73.34 Warehouse Resource

Conceptually:

``` hcl
resource "snowflake_warehouse" "app_wh" {
  name           = "APP_WH"
  warehouse_size = "MEDIUM"
  auto_suspend   = 60
  auto_resume    = true
}
```

## 73.35 Warehouse Standards

IaC can enforce naming, sizing, auto-suspend/resume, scaling, cluster
settings, and resource-monitor standards where supported.

## 73.36 FinOps Benefit

Warehouse cost controls become visible and reviewable during code and
plan review.

## 73.37 Role Resource

Conceptually:

``` hcl
resource "snowflake_account_role" "app_role" {
  name    = "PATIENT360_APP_ROLE"
  comment = "Application role for Patient360"
}
```

## 73.38 RBAC as Code

Manage supported role hierarchy and warehouse/database/schema/object
privileges declaratively.

## 73.39 Role Hierarchy

`SYSADMIN → PATIENT360_ADMIN_ROLE → PATIENT360_APP_ROLE`; design
hierarchy before individual grants.

## 73.40 Grants Are Critical

Incorrect grants can create outages, unauthorized access, security
exposure, or failed deployments.

## 73.41 Least Privilege

Grant only required privileges such as warehouse/database/schema USAGE
and required table SELECT.

## 73.42 Avoid Conflicting Ownership

Do not let multiple modules/resources independently own the same grant
relationship without an intentional design.

## 73.43 User Management

Terraform may manage supported user/service-user resources; do not embed
secret material in identity definitions.

## 73.44 Service Identity Standard

Document owner, purpose, authentication method, role, environment, and
rotation process.

## 73.45 Personal Users

Human identity lifecycle may be better owned by enterprise SSO/identity
processes; choose ownership deliberately.

## 73.46 Cost Controls as Code

Manage resource monitors through IaC where supported so cost controls
are version-controlled, reviewed, consistent, and auditable.

## 73.47 Production Standard

Critical warehouses should not depend on manual memory for cost
controls.

## 73.48 variables.tf

``` hcl
variable "environment" { type = string }
variable "warehouse_size" { type = string }
```

## 73.49 Variable Usage

``` hcl
resource "snowflake_warehouse" "app_wh" {
  name           = "${upper(var.environment)}_APP_WH"
  warehouse_size = var.warehouse_size
}
```

## 73.50 Sensitive Variables

`sensitive = true` controls display behavior but does not make insecure
storage safe.

## 73.51 outputs.tf

``` hcl
output "warehouse_name" {
  value = snowflake_warehouse.app_wh.name
}
```

## 73.52 Sensitive Outputs

Do not output credentials or secret material.

## 73.53 locals

``` hcl
locals {
  environment = upper(var.environment)
}
```

## 73.54 Naming Convention

Use a consistent pattern such as `<ENV>_<APPLICATION>_<OBJECT>`:
`PROD_PATIENT360_WH`, `PROD_PATIENT360_DB`, `PROD_PATIENT360_ROLE`.

## 73.55 Naming as Code

IaC makes naming standards enforceable rather than merely documented.

## 73.56 Why Modules?

Modules provide reusable patterns for database, warehouse, RBAC, and
service-account infrastructure.

## 73.57 Warehouse Module

A reusable warehouse module may create the warehouse, resource monitor,
and required grants.

## 73.58 Module Inputs

Typical inputs: name, size, auto-suspend, role, environment, and cost
limit.

## 73.59 Avoid Over-Abstraction

Keep modules understandable; readability is more important than
eliminating every repeated line.

## 73.60 Development

Use dedicated DEV state, credentials, and resources.

## 73.61 Staging

Use dedicated STAGING state, credentials, and resources.

## 73.62 Production

Use dedicated PROD state, credentials, and resources.

## 73.63 State Isolation

Production deployment must never accidentally use development state.

## 73.64 Credential Isolation

Production credentials must not be exposed to development pipelines.

## 73.65 Production Repository

Use reusable `modules/` plus explicit `environments/dev`,
`environments/staging`, and `environments/prod` configuration.

## 73.66 Pull Request Workflow

Feature Branch → Pull Request → `terraform fmt` → `terraform validate` →
`terraform plan` → Review → Approval → Apply.

## 73.67 Pull Request Plan

Surface the plan for reviewer inspection.

## 73.68 Production Apply

Require explicit production authorization according to change-management
policy.

## 73.69 Separate Plan and Apply

Generate/review PLAN first; APPLY only after merge/approval.

## 73.70 Reviewer Checklist

Review creates, updates, destroys, replacements, RBAC, warehouse sizing,
cost controls, and production impact.

## 73.71 Destructive Change Gate

Unexpected destruction means STOP.

## 73.72 prevent_destroy

For selected critical resources:

``` hcl
lifecycle {
  prevent_destroy = true
}
```

## 73.73 Use Carefully

`prevent_destroy` does not replace backups, Time Travel, DR, review, or
correct permissions.

## 73.74 What Is Drift?

Drift is a difference between Terraform-managed desired state and actual
Snowflake configuration.

## 73.75 Drift Example

Terraform says MEDIUM; an engineer manually changes the warehouse to
XLARGE; the next plan detects it.

## 73.76 Drift Detection

Run scheduled plans or another approved drift-detection workflow.

## 73.77 Do Not Automatically Apply Every Drift

Determine whether a manual change was intentional/emergency-related and
which state should become authoritative.

## 73.78 Existing Snowflake Objects

Production often predates Terraform; do not blindly recreate existing
objects.

## 73.79 Import Workflow

Existing object → write matching resource → `terraform import` → plan →
reconcile differences.

## 73.80 Import Carefully

After import, inspect the plan until there are no unintended changes
before Terraform becomes authoritative.

## 73.81 Refactoring

Use supported Terraform move/refactoring mechanisms when changing
resource addresses.

## 73.82 Never Refactor Blindly

Review the plan after every state/address change.

## 73.83 Terraform Ownership vs Object Deletion

Understand removing an object from state versus destroying the Snowflake
object.

## 73.84 Break-Glass Changes

Emergency manual changes may be appropriate during incidents.

## 73.85 Reconcile After Incident

After stabilization, either update Terraform to retain the change or use
approved Terraform reconciliation to restore desired state.

## 73.86 State Commands Are High Risk

Treat state manipulation as a production change.

## 73.87 Back Up State

Ensure backend versioning/recovery is available before high-risk state
operations.

## 73.88 State Inspection

``` bash
terraform state list
```

## 73.89 Inspect Resource

``` bash
terraform state show <resource-address>
```

## 73.90 Terraform Secret Risk

Sensitive values can still exist in state; `sensitive` does not mean
absent from state.

## 73.91 Minimize Secret Management

Prefer authentication designs minimizing persistent secrets in Terraform
configuration/state.

## 73.92 IaC Security Layers

Protect Git, CI/CD, Terraform state, Snowflake automation identity,
provider authentication, and approvals.

## 73.93 Branch Protection

Use PRs, required reviewers, protected branches, CI checks, and
restricted direct pushes.

## 73.94 CODEOWNERS

RBAC, networking, production warehouses, and security integrations may
require specialist review.

## 73.95 Terraform Can Create Expensive Infrastructure

A syntactically valid large warehouse can still create major cost.

## 73.96 FinOps Review

Review warehouse size, cluster count, auto-suspend, resource monitors,
environment, and expected workload.

## 73.97 Cost Policy

CI policy can reject prohibited cost configurations.

## 73.98 Policy Checks

Examples: require production auto-suspend/resource monitors, prohibit
unapproved sizes/ACCOUNTADMIN automation, require tags/comments.

## 73.99 Shift Left

Detect unsafe infrastructure in the pull request rather than after
deployment.

## 73.100 Terraform Validation

``` bash
terraform fmt -check
terraform validate
terraform plan
```

## 73.101 Non-Production Testing

Test module and provider changes in development/staging before
production.

## 73.102 Provider Upgrade Testing

Read release notes → update version → `terraform init -upgrade` →
validate → DEV → STAGING → PROD.

## 73.103 Lock File

Maintain `.terraform.lock.hcl` according to Terraform best practices and
organizational policy.

## 73.104 Why?

The lock file improves provider consistency across engineers and CI.

## 73.105 Authentication Failure

Check service identity, authentication method, key/token, account
identifier, role, and network.

## 73.106 Authorization Failure

Identify the failed operation and grant only the necessary privilege.

## 73.107 Provider Error

Record Terraform/provider versions, resource, error, plan, and
environment; compare with current provider docs/release notes.

## 73.108 Unexpected Destroy

STOP and check rename/state/environment/schema/import/provider-upgrade
issues.

## 73.109 Unexpected Replacement

Understand impact before replacing critical resources.

## 73.110 State Lock Failure

Confirm no active deployment before lock removal; never force-unlock
merely because a pipeline is slow.

## 73.111 Drift

Decide whether actual state or Terraform configuration should become
authoritative.

## 73.112 Provider Upgrade Problem

STOP → review version/migration guidance → test non-production → correct
configuration/state → re-plan.

## 73.113 Terraform Deployment Runbook

Create change → branch → modify → fmt → validate → DEV plan/test →
STAGING test → PROD plan → verify backend/account/identity → review
create/update/replace/destroy/RBAC/cost → approve → apply reviewed plan
→ validate Snowflake/application → monitor → reconcile drift →
document/close.

## 73.114 Existing Resource Import Runbook

Identify object/ownership → protect state → write matching config →
confirm provider/environment → import with resource-specific identifier
→ plan → reconcile until no unintended changes → peer review → merge →
document ownership.

## 73.115 Drift Investigation Runbook

Generate plan → identify drift/object → review last deployment/audit
evidence → identify manual change → determine intent → choose desired
state → update Terraform or revert via Terraform → re-plan/review/apply
→ validate/document/improve controls.

## 73.116 Provider Upgrade Runbook

Record versions → read release notes → review breaking/deprecated
behavior → branch/update constraint/init upgrade → fmt/validate → DEV
plan/apply/test → STAGING → PROD plan/review/approval/apply →
validate/monitor/document.

## 73.117 Emergency Manual Change Runbook

Confirm severity → identify managed object → record Terraform/Snowflake
state → emergency approval → minimum manual change →
record/validate/stabilize → plan → identify drift → decide permanence →
update/revert through Terraform → review/apply/validate/document.

## 73.118 Patient360 Infrastructure

Example: `PROD_PATIENT360_DB`, `PROD_PATIENT360_WH`,
`PROD_PATIENT360_APP_ROLE`, `SVC_PATIENT360`.

## 73.119 Terraform Model

Terraform manages database, warehouse, role, grants, and resource
monitor; authentication may use a separate secure identity process.

## 73.120 Change Request

Application requests warehouse `MEDIUM → LARGE`.

## 73.121 Terraform Change

``` hcl
warehouse_size = "LARGE"
```

## 73.122 Plan

Expected plan shows only the intended MEDIUM → LARGE update, with no
unexpected database deletion, role replacement, or grant changes.

## 73.123 Review

DBRE reviews performance justification, cost, auto-suspend, resource
monitor, environment, and expected duration.

## 73.124 Apply

``` bash
terraform apply tfplan
```

## 73.125 Validation

Validate warehouse configuration and application workload.

## 73.126 Emergency Change

During an incident an engineer temporarily scales LARGE → XLARGE
manually.

## 73.127 Drift

The next plan detects XLARGE → LARGE.

## 73.128 Decision

If temporary, restore LARGE via Terraform; if permanent, update
Terraform through review before making XLARGE authoritative.

## 73.129 Terraform Is Not a Backup

Terraform does not replace data replication, Time Travel, Fail-safe,
database recovery, DR replication, or failover procedures.

## 73.130 IaC and DR Together

Combine Terraform for infrastructure configuration, Snowflake
replication for supported data/account state, and DR runbooks for
operational recovery.

## 73.131 Common Mistakes

Avoid personal credentials, routine ACCOUNTADMIN, embedded secrets,
local-only production state, state in Git, no state recovery, unpinned
providers, weak environment separation, blind apply, ignored
destroy/replace, conflicting ownership, unreconciled manual changes,
unsafe state operations, weak import/drift/cost/RBAC processes, untested
upgrades, and treating Terraform as backup.

## 73.132 Production Standards

Use dedicated identity/least privilege/secure auth; protected remote and
environment-separated state; version-controlled/pinned Terraform; lock
file; PR workflow; fmt/validate/plan; reviewed destructive/RBAC/cost
changes; careful imports/drift reconciliation/provider upgrades/state
operations; separate DR/recovery.

## 73.133 SRE/DBRE Terraform Checklist

-   [ ] Provider pinned and lock file maintained
-   [ ] Dedicated least-privilege identity
-   [ ] No secrets in code
-   [ ] Protected remote state with recovery
-   [ ] DEV/STAGING/PROD isolated
-   [ ] Branch protection and peer review
-   [ ] fmt/validate/plan enforced
-   [ ] Destroy/replacement/RBAC/cost reviewed
-   [ ] Production approval required
-   [ ] Imports/drift/break-glass/state/upgrade processes documented
-   [ ] DR strategy separate from Terraform

## 73.134 Operational Quick Reference

WRITE → FORMAT → VALIDATE → PLAN → REVIEW → APPROVE → APPLY → VALIDATE
SNOWFLAKE → MONITOR DRIFT.

## 73.135 Key Takeaways

Terraform makes Snowflake infrastructure declarative, repeatable,
reviewable, and auditable. Pin providers, protect state, isolate
environments, use least privilege, review every production plan, stop on
unexpected destroy/replace, reconcile drift/emergency changes, test
upgrades, and remember Terraform is not a data backup.

## 73.136 Chapter Completion Checklist

You should be able to configure and secure the Snowflake Terraform
Provider; manage state/plans/resources/RBAC/cost controls; use
variables/outputs/locals/modules; separate environments; build CI/CD and
review controls; protect/import/refactor resources; detect/reconcile
drift; handle state and emergency changes; test provider upgrades;
troubleshoot deployments; execute production runbooks; and combine IaC
with Snowflake DR.

**Chapter 73 --- Snowflake Terraform / Infrastructure as Code:
Complete**
