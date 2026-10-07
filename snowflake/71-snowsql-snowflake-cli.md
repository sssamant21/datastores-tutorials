# Chapter 71 --- SnowSQL & Snowflake CLI

## 71.1 Overview

Snowflake provides command-line tooling for administrators, DBRE/SRE
engineers, developers, automation pipelines, and data engineers.

The two important command-line clients are:

``` text
Snowflake CLI
Command: snow

SnowSQL
Command: snowsql
```

For new automation and operational tooling, prefer **Snowflake CLI**.

SnowSQL remains relevant for existing scripts and legacy environments,
but new operational tooling should generally be designed around
Snowflake CLI.

# Snowflake CLI vs SnowSQL

## 71.2 Snowflake CLI

Snowflake CLI is the modern Snowflake command-line interface.

Primary command:

``` bash
snow
```

It supports connections, SQL, objects, stages, Snowpark, Streamlit,
Native Apps, Snowpark Container Services, Git, notebooks, and other
supported Snowflake workflows.

## 71.3 SnowSQL

SnowSQL is the older Snowflake SQL-oriented command-line client.

Primary command:

``` bash
snowsql
```

It remains useful for existing scripts, legacy automation, SQL
execution, data loading/unloading, and operational scripts not yet
migrated.

## 71.4 Recommended Direction

For new development, prefer Snowflake CLI. For existing SnowSQL
environments, maintain safely while planning controlled migration.

## 71.5 Why Learn Both?

Production environments may contain years of existing SnowSQL automation
while newer tooling uses `snow`. An SRE/DBRE should understand both.

# Snowflake CLI Installation

## 71.6 Verify Installation

``` bash
snow --version
```

## 71.7 Display CLI Information

``` bash
snow --info
```

## 71.8 Display Help

``` bash
snow --help
```

## 71.9 SQL Help

``` bash
snow sql --help
```

# Connection Architecture

## 71.10 Connection Model

A Snowflake CLI connection normally defines account, user,
authentication, role, warehouse, database, and schema context.

## 71.11 Named Connections

Use named profiles such as `prod`, `staging`, and `dev` instead of
repeatedly supplying parameters.

## 71.12 Add a Connection

``` bash
snow connection add
```

## 71.13 Named Connection

``` bash
snow connection add --connection-name prod
```

## 71.14 List Connections

``` bash
snow connection list
```

## 71.15 Test Connection

``` bash
snow connection test -c prod
```

## 71.16 Set Default Connection

``` bash
snow connection set-default prod
```

For production engineering, explicitly specifying the connection is
often safer than relying on an implicit default.

# Connection Configuration

## 71.17 Configuration File

Snowflake CLI stores configuration under the user's Snowflake
configuration location. Inspect the active configuration information
using:

``` bash
snow --info
```

## 71.18 Example Connection Concept

``` toml
[connections.prod]
account = "<account_identifier>"
user = "<username>"
role = "PROD_DBA_ROLE"
warehouse = "ADMIN_WH"
database = "PROD_DB"
schema = "PUBLIC"
```

Authentication depends on the selected method.

# Credential Security

## 71.19 Do Not Hard-Code Passwords

Avoid passwords directly in commands, scripts, shell history, Git, CI
logs, tickets, documentation, Slack, or Confluence.

## 71.20 Environment Variables

Where password authentication is unavoidable, use an approved secure
mechanism rather than embedding passwords in scripts.

## 71.21 Preferred Production Authentication

Depending on workload and policy, consider key-pair authentication,
OAuth, workload identity, SSO, or approved secrets-management
integration instead of static passwords.

## 71.22 Least Privilege

CLI automation should use the minimum required Snowflake role. Avoid
`ACCOUNTADMIN` for routine automation.

# Testing Context

## 71.23 Verify Current Identity

``` bash
snow sql -c prod -q "
SELECT
    CURRENT_USER(),
    CURRENT_ROLE(),
    CURRENT_WAREHOUSE(),
    CURRENT_DATABASE(),
    CURRENT_SCHEMA();
"
```

## 71.24 Verify Account

``` bash
snow sql -c prod -q "
SELECT
    CURRENT_ORGANIZATION_NAME(),
    CURRENT_ACCOUNT_NAME(),
    CURRENT_REGION();
"
```

Perform this before high-risk administrative operations.

# Executing SQL

## 71.25 Execute a Query

``` bash
snow sql -c prod -q "SELECT CURRENT_TIMESTAMP();"
```

## 71.26 Execute Multiple Statements

``` bash
snow sql -c prod -q "
USE ROLE PROD_DBA_ROLE;
USE WAREHOUSE ADMIN_WH;
SHOW DATABASES;
"
```

## 71.27 Execute SQL File

``` bash
snow sql -c prod -f health_check.sql
```

## 71.28 Multiple SQL Files

``` bash
snow sql -c prod \
  -f 01-precheck.sql \
  -f 02-change.sql \
  -f 03-validation.sql
```

## 71.29 Standard Input

Linux/macOS:

``` bash
cat health_check.sql | snow sql -c prod -i
```

PowerShell:

``` powershell
Get-Content health_check.sql | snow sql -c prod -i
```

# Interactive SQL

## 71.30 Interactive Session

``` bash
snow sql -c prod
```

## 71.31 When Interactive Mode Is Useful

Use interactive mode for investigation, troubleshooting, exploration,
and administrative validation. Prefer version-controlled SQL files for
repeatable production changes.

# SQL File Design

## 71.32 Production SQL File

``` sql
SELECT
    CURRENT_TIMESTAMP(),
    CURRENT_ACCOUNT_NAME(),
    CURRENT_REGION(),
    CURRENT_USER(),
    CURRENT_ROLE(),
    CURRENT_WAREHOUSE();
```

Execute:

``` bash
snow sql -c prod -f precheck.sql
```

## 71.33 Change Script Structure

``` text
01-precheck.sql
02-change.sql
03-validation.sql
04-rollback.sql
```

## 71.34 Why Separate Files?

This improves auditability, reviewability, repeatability, rollback
planning, and execution ordering.

# Output Formats

## 71.35 Table Output

Human operators commonly use table-formatted output.

## 71.36 JSON Output

``` bash
snow sql -c prod \
  --format JSON \
  -q "SELECT CURRENT_ACCOUNT_NAME();"
```

## 71.37 CSV Output

``` bash
snow sql -c prod \
  --format CSV \
  -q "SELECT * FROM PROD_DB.PUBLIC.CONFIG;"
```

## 71.38 Choose Output for Consumer

Use table output for human investigation, JSON for automation, and CSV
for exports/downstream tooling where appropriate.

# Variables

## 71.39 Avoid Duplicating Scripts

Parameterize controlled environment differences rather than maintaining
unnecessary duplicate SQL files.

## 71.40 CLI Variables

Snowflake CLI supports client-side variable substitution for SQL
execution. Validate expansion before production-changing SQL.

## 71.41 Production Guardrail

Never allow uncontrolled user input to become SQL identifiers or
fragments.

# Transactions

## 71.42 Transaction Awareness

Understand DDL behavior, explicit COMMIT/ROLLBACK, and unsupported
statements before assuming a script is fully atomic.

## 71.43 Do Not Assume Rollback

Validate transaction semantics for every operation rather than assuming
all changes automatically roll back after failure.

# SRE Health Check

## 71.44 Basic Health Check

``` sql
SELECT
    CURRENT_TIMESTAMP(),
    CURRENT_ACCOUNT_NAME(),
    CURRENT_REGION(),
    CURRENT_USER(),
    CURRENT_ROLE();

SHOW WAREHOUSES;

SHOW DATABASES;
```

Execute:

``` bash
snow sql -c prod -f snowflake-health-check.sql
```

## 71.45 Warehouse Check

``` bash
snow sql -c prod -q "SHOW WAREHOUSES;"
```

## 71.46 Query History Investigation

``` bash
snow sql -c prod -q "
SELECT
    QUERY_ID,
    USER_NAME,
    WAREHOUSE_NAME,
    EXECUTION_STATUS,
    TOTAL_ELAPSED_TIME,
    START_TIME
FROM SNOWFLAKE.ACCOUNT_USAGE.QUERY_HISTORY
WHERE START_TIME >= DATEADD('hour', -1, CURRENT_TIMESTAMP())
ORDER BY START_TIME DESC
LIMIT 100;
"
```

Consider Account Usage latency and required privileges.

## 71.47 Long-Running Queries

``` bash
snow sql -c prod -q "
SELECT
    QUERY_ID,
    USER_NAME,
    WAREHOUSE_NAME,
    TOTAL_ELAPSED_TIME,
    START_TIME,
    QUERY_TEXT
FROM SNOWFLAKE.ACCOUNT_USAGE.QUERY_HISTORY
WHERE START_TIME >= DATEADD('hour', -1, CURRENT_TIMESTAMP())
ORDER BY TOTAL_ELAPSED_TIME DESC
LIMIT 20;
"
```

# Production Change Workflow

## 71.48 Recommended Workflow

Git → SQL Files → Peer Review → Change Approval → Precheck → Execute →
Validate → Record Result.

## 71.49 Precheck

``` bash
snow sql -c prod -f 01-precheck.sql
```

## 71.50 Change

``` bash
snow sql -c prod -f 02-change.sql
```

## 71.51 Validation

``` bash
snow sql -c prod -f 03-validation.sql
```

## 71.52 Rollback

``` bash
snow sql -c prod -f 04-rollback.sql
```

Rollback should be designed and reviewed before the change.

# Environment Separation

## 71.53 Separate Connections

Use separate `dev`, `staging`, and `prod` connections.

## 71.54 Explicit Production Connection

Prefer:

``` bash
snow sql -c prod -f change.sql
```

rather than relying on a default for production.

## 71.55 Production Guard Query

``` sql
SELECT
    CURRENT_ACCOUNT_NAME(),
    CURRENT_REGION(),
    CURRENT_ROLE();
```

## 71.56 Human Confirmation

Verify account, region, role, change ticket, and SQL before executing
high-risk production work.

# Automation

## 71.57 CLI Automation

Snowflake CLI can integrate with CI/CD, GitHub Actions, Jenkins, GitLab
CI, Azure DevOps, Kubernetes Jobs, shell scripts, and PowerShell.

## 71.58 Automation Identity

Use a dedicated identity such as:

``` text
SVC_SNOWFLAKE_DEPLOY
```

## 71.59 Dedicated Role

Example:

``` text
SNOWFLAKE_DEPLOY_ROLE
```

Grant only required privileges.

## 71.60 Dedicated Warehouse

Where appropriate:

``` text
DEPLOY_WH
```

can isolate deployment workload.

# CI/CD Pattern

## 71.61 Deployment Pattern

Git Commit → Pull Request → Review → CI Validation → Approval →
Snowflake CLI → Snowflake.

## 71.62 Pipeline Precheck

Verify connection, account, role, warehouse, and required object state
before change execution.

## 71.63 Pipeline Validation

Validate object existence/configuration, permissions, data state, and
application compatibility.

## 71.64 Capture Query IDs

Capture relevant Snowflake query identifiers where practical for
troubleshooting and auditability.

# Logging

## 71.65 Operational Logging

Capture timestamp, environment, account, operator/service identity,
script, result, query IDs, and error.

## 71.66 Avoid Secret Logging

Never intentionally log passwords, private keys, OAuth tokens, or secret
values.

## 71.67 Debug Mode

Use debug/verbose capabilities carefully because diagnostics can expose
sensitive operational metadata.

# Connection Troubleshooting

## 71.68 Connection Test

``` bash
snow connection test -c prod
```

## 71.69 Authentication Failure

Check account identifier, username, authentication method, key pair,
OAuth, SSO, MFA, and network.

## 71.70 Wrong Account

``` sql
SELECT
    CURRENT_ACCOUNT_NAME(),
    CURRENT_REGION();
```

Stop immediately if unexpected.

## 71.71 Wrong Role

``` sql
SELECT CURRENT_ROLE();
```

## 71.72 Wrong Warehouse

``` sql
SELECT CURRENT_WAREHOUSE();
```

## 71.73 Wrong Database

``` sql
SELECT CURRENT_DATABASE();
```

## 71.74 Network Failure

Check DNS, firewall, proxy, VPN, private connectivity, and network
policy.

# CLI Troubleshooting

## 71.75 CLI Version

``` bash
snow --version
```

## 71.76 CLI Information

``` bash
snow --info
```

## 71.77 Command Help

``` bash
snow sql --help
```

Use installed-client help rather than assuming options from another
release.

## 71.78 Debug

``` bash
snow sql -c prod --debug -q "SELECT CURRENT_TIMESTAMP();"
```

Use debug output according to security policy.

# SnowSQL

## 71.79 Verify SnowSQL

``` bash
snowsql -v
```

## 71.80 SnowSQL Connection

``` bash
snowsql -c prod
```

## 71.81 SnowSQL Query

``` bash
snowsql -c prod \
  -q "SELECT CURRENT_TIMESTAMP();"
```

## 71.82 SnowSQL SQL File

``` bash
snowsql -c prod \
  -f health_check.sql
```

## 71.83 SnowSQL Interactive Mode

``` bash
snowsql -c prod
```

This remains useful for legacy operational workflows.

# Migrating SnowSQL to Snowflake CLI

## 71.84 Migration Strategy

Inventory SnowSQL scripts → identify
connections/authentication/CLI-specific commands → create Snowflake CLI
connections → test SQL/output parsing/exit codes → parallel validation →
cut over.

## 71.85 Do Not Perform Blind String Replacement

Do not simply replace `snowsql` with `snow sql`. Scripts may depend on
different options, output formats, configuration, variables, exit codes,
and interactive commands.

## 71.86 Import Existing SnowSQL Connections

``` bash
snow helpers import-snowsql-connections
```

Review imported configuration before production use.

## 71.87 Migration Validation

Validate authentication, account, role, warehouse, database, SQL
results, output format, error handling, exit code, and logging.

# Windows Operations

## 71.88 Windows Command Prompt

``` cmd
snow sql -c prod -q "SELECT CURRENT_TIMESTAMP();"
```

## 71.89 Windows SQL File

``` cmd
snow sql -c prod -f health_check.sql
```

## 71.90 PowerShell

``` powershell
snow sql -c prod -q "SELECT CURRENT_TIMESTAMP();"
```

## 71.91 PowerShell Variable

``` powershell
$connection = "prod"
snow sql -c $connection -q "SELECT CURRENT_ACCOUNT_NAME();"
```

## 71.92 PowerShell Error Handling

``` powershell
snow sql -c prod -f change.sql

if ($LASTEXITCODE -ne 0) {
    Write-Error "Snowflake change failed."
    exit $LASTEXITCODE
}
```

Test actual exit-code behavior for the installed CLI and commands.

# Linux Operations

## 71.93 Shell Script

``` bash
#!/usr/bin/env bash
set -euo pipefail

CONNECTION="prod"

snow connection test -c "$CONNECTION"

snow sql -c "$CONNECTION" -f precheck.sql
snow sql -c "$CONNECTION" -f change.sql
snow sql -c "$CONNECTION" -f validation.sql
```

## 71.94 Never Put Secrets in Script

Use the organization's approved secret-management approach.

# Production SRE Script

## 71.95 Health Check Script

``` powershell
$connection = "prod"

Write-Host "Testing Snowflake connection..."

snow connection test -c $connection

if ($LASTEXITCODE -ne 0) {
    Write-Error "Snowflake connection failed."
    exit 1
}

Write-Host "Checking Snowflake context..."

snow sql -c $connection -q @"
SELECT
    CURRENT_TIMESTAMP(),
    CURRENT_ACCOUNT_NAME(),
    CURRENT_REGION(),
    CURRENT_USER(),
    CURRENT_ROLE(),
    CURRENT_WAREHOUSE();
"@

if ($LASTEXITCODE -ne 0) {
    Write-Error "Snowflake health check failed."
    exit 1
}

Write-Host "Snowflake health check completed."
```

# Destructive Change Protection

## 71.96 High-Risk Commands

DROP, TRUNCATE, DELETE, ALTER ACCOUNT, ALTER USER, and ALTER FAILOVER
GROUP require additional controls.

## 71.97 Pre-Execution Validation

``` sql
SELECT
    CURRENT_ACCOUNT_NAME(),
    CURRENT_REGION(),
    CURRENT_USER(),
    CURRENT_ROLE();
```

## 71.98 Recovery Check

Before destructive data changes determine Time Travel availability,
clone strategy, backup/recovery path, and rollback method.

## 71.99 Dry Run Where Possible

``` sql
SELECT COUNT(*)
FROM PROD_DB.EMPI.PATIENT
WHERE <condition>;
```

before:

``` sql
DELETE
FROM PROD_DB.EMPI.PATIENT
WHERE <condition>;
```

# Operational Runbooks

## 71.100 Snowflake CLI Setup Runbook

1.  Install Snowflake CLI.
2.  Verify `snow --version`.
3.  Review `snow --info`.
4.  Define authentication method.
5.  Create connection.
6.  Assign least-privilege role.
7.  Configure warehouse.
8.  Configure database/schema if required.
9.  Protect credentials.
10. Test connection.
11. Verify account.
12. Verify region.
13. Verify user.
14. Verify role.
15. Verify warehouse.
16. Execute test query.
17. Validate output.
18. Document connection purpose.
19. Record owner.
20. Add operational monitoring where applicable.

## 71.101 Production Change Runbook

1.  Create change ticket.
2.  Prepare SQL.
3.  Peer review SQL.
4.  Prepare validation.
5.  Prepare rollback/recovery.
6.  Verify connection.
7.  Verify account.
8.  Verify region.
9.  Verify role.
10. Verify warehouse.
11. Capture pre-change state.
12. Execute precheck.
13. Execute change.
14. Capture query identifiers.
15. Execute validation.
16. Confirm application health.
17. Monitor.
18. Roll back/recover if required.
19. Record outcome.
20. Close change.

## 71.102 CLI Troubleshooting Runbook

1.  Record CLI version.
2.  Record operating system.
3.  Identify connection.
4.  Test connection.
5.  Verify account identifier.
6.  Verify authentication.
7.  Verify network.
8.  Verify user.
9.  Verify role.
10. Verify warehouse.
11. Run minimal query.
12. Review CLI error.
13. Enable approved diagnostics if required.
14. Compare against current CLI documentation.
15. Correct issue.
16. Retest.
17. Document resolution.

## 71.103 SnowSQL Migration Runbook

1.  Inventory SnowSQL installations.
2.  Inventory scripts.
3.  Inventory connection profiles.
4.  Inventory authentication.
5.  Inventory variables.
6.  Inventory output parsing.
7.  Inventory exit-code handling.
8.  Install Snowflake CLI.
9.  Import/recreate connections.
10. Test authentication.
11. Convert commands.
12. Validate SQL execution.
13. Validate variables.
14. Validate output.
15. Validate exit codes.
16. Validate logging.
17. Test in development.
18. Test in staging.
19. Perform production parallel validation.
20. Cut over.
21. Monitor.
22. Retire legacy dependency when approved.

# Production Scenario

## 71.104 Patient360 Operational Automation

Suppose the DBRE team maintains `prod` and `staging` Snowflake
connections.

## 71.105 Production Precheck

``` cmd
snow connection test -c prod
snow sql -c prod -q "SELECT CURRENT_ACCOUNT_NAME(), CURRENT_REGION(), CURRENT_ROLE();"
```

## 71.106 Production Health Check

``` cmd
snow sql -c prod -f snowflake-health-check.sql
```

## 71.107 Controlled Change

Repository:

``` text
snowflake-change/
|
+-- 01-precheck.sql
+-- 02-change.sql
+-- 03-validation.sql
+-- 04-rollback.sql
```

Execution:

``` cmd
snow sql -c prod -f 01-precheck.sql
snow sql -c prod -f 02-change.sql
snow sql -c prod -f 03-validation.sql
```

## 71.108 Failure

If validation fails: STOP → ASSESS → use safe rollback if available, or
approved Time Travel/Clone/recovery if data recovery is required. Do not
continue blindly.

# Production Standards

## 71.109 Common Mistakes

Avoid hard-coded passwords, passwords in shell history, secrets in Git,
unnecessary ACCOUNTADMIN, implicit production connections, missing
account/region/role verification, missing precheck/validation/recovery,
ignored exit codes, missing query IDs/audit trail, interactive-only
repeatable changes, blind SnowSQL migration, uncontrolled client
upgrades, and poor environment separation.

## 71.110 Production Standards

Use Snowflake CLI for new automation; retain SnowSQL only where
required; named environment connections; explicit production selection;
strong authentication; secrets outside source code; dedicated automation
identities; least privilege; dedicated warehouses where appropriate;
version-controlled SQL; peer review; prechecks; account/region/role
verification; post-change validation; recovery planning before
destructive work; exit-code handling; relevant query IDs; protected
logs; tracked CLI versions; methodical SnowSQL migration.

## 71.111 SRE/DBRE CLI Checklist

-   [ ] Snowflake CLI installed
-   [ ] Version recorded
-   [ ] Connection created
-   [ ] Connection tested
-   [ ] Authentication secured
-   [ ] No password in source code
-   [ ] Account verified
-   [ ] Region verified
-   [ ] User verified
-   [ ] Role verified
-   [ ] Warehouse verified
-   [ ] Least privilege applied
-   [ ] Dev connection separated
-   [ ] Staging connection separated
-   [ ] Prod connection separated
-   [ ] Production connection explicit
-   [ ] SQL version controlled
-   [ ] Precheck created
-   [ ] Validation created
-   [ ] Recovery/rollback planned
-   [ ] Exit codes handled
-   [ ] Query IDs captured where required
-   [ ] Logs protected
-   [ ] Automation identity dedicated
-   [ ] SnowSQL migration tracked

## 71.112 Operational Quick Reference

Install CLI → Create Connection → Secure Authentication → Test
Connection → Verify Account/Region/Role → Execute Precheck → Execute SQL
→ Validate → Capture Result → Monitor.

## 71.113 Key Takeaways

1.  Snowflake CLI is the preferred command-line client for new work.
2.  SnowSQL is a legacy client.
3.  Existing SnowSQL automation still needs operational support.
4.  Learn both during the migration period.
5.  Use named connections.
6.  Separate dev, staging, and production.
7.  Explicitly select production connections.
8.  Never hard-code passwords.
9.  Protect authentication material.
10. Prefer stronger automation authentication where appropriate.
11. Use dedicated service identities.
12. Apply least privilege.
13. Avoid ACCOUNTADMIN for routine automation.
14. Verify account before production changes.
15. Verify region.
16. Verify role.
17. Verify warehouse.
18. Use version-controlled SQL files.
19. Separate precheck/change/validation/recovery.
20. Check command exit status.
21. Use structured output for automation.
22. Protect logs from secrets.
23. Capture query IDs where useful.
24. Test automation outside production first.
25. Use CLI health checks for operations.
26. Protect destructive changes with explicit prechecks.
27. Verify recovery options before destructive data operations.
28. Do not blindly convert SnowSQL scripts.
29. Test migrated automation end to end.
30. Track CLI versions in production.

## 71.114 Chapter Completion Checklist

After completing this chapter, you should be able to explain Snowflake
CLI and SnowSQL; understand migration direction; install/inspect CLI;
create/list/test connections; secure credentials; choose authentication;
apply least privilege; verify session context; execute
direct/file/multiple/stdin/interactive SQL; design production file
workflows; use structured output/variables; understand transaction
considerations; build health checks; investigate query history; build
controlled changes/environment separation/automation/CI-CD/logging;
troubleshoot connections and CLI; operate legacy SnowSQL; migrate
SnowSQL safely; use Windows/PowerShell/Linux; build SRE automation;
protect destructive changes; execute
setup/change/troubleshooting/migration runbooks; and apply production
standards.

**Chapter 71 --- SnowSQL & Snowflake CLI: Complete**
