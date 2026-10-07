# Chapter 74 --- Snowflake REST APIs & Automation

## 74.1 Overview

Snowflake provides REST-based APIs that applications and automation
platforms can use without maintaining a traditional database-driver
session.

A common automation architecture is:

``` text
Application / Automation
          |
          v
Authentication
          |
          v
Snowflake SQL API
          |
          v
Submit SQL
          |
          +--> Completed
          |
          +--> Running
                  |
                  v
            Poll Status
                  |
                  v
             Get Results
```

The Snowflake SQL API can be used to submit SQL statements, check
execution status, retrieve results, and cancel statements.

## 74.2 Common Use Cases

Typical use cases include serverless applications, microservices, CI/CD
pipelines, automation platforms, administrative workflows, event-driven
processing, operational health checks, and infrastructure orchestration.

## 74.3 API vs Python Connector

Use the Python Connector for Python applications, longer database
interaction, connector-native features, or applications already using
Python.

Use the SQL API when REST integration, language-independent integration,
serverless workflows, HTTP automation, or external orchestration is
required.

## 74.4 API vs Snowflake CLI

Snowflake CLI is generally better for human operators, shell automation,
administrative scripts, and CI/CD SQL files. The SQL API is better when
software needs a REST interface.

## 74.5 Core SQL API Operations

``` text
POST /api/v2/statements
GET  /api/v2/statements/{statementHandle}
POST /api/v2/statements/{statementHandle}/cancel
```

## 74.6 Submit Statement

`POST /api/v2/statements` submits SQL statements.

## 74.7 Check Statement

`GET /api/v2/statements/{statementHandle}` checks execution status and
retrieves results when available.

## 74.8 Cancel Statement

`POST /api/v2/statements/{statementHandle}/cancel` requests cancellation
of a running statement.

## 74.9 Account Endpoint

Conceptually:

``` text
https://<account_identifier>.snowflakecomputing.com/api/v2/statements
```

Use the correct account URL for the environment.

## 74.10 Environment Isolation

Maintain explicit Development, Staging, and Production
endpoints/configuration. Never allow production automation to infer its
target account from an unsafe default.

## 74.11 Authentication Is Mandatory

Every request must use an approved Snowflake authentication mechanism.

## 74.12 Supported SQL API Authentication

Production integrations can use supported authentication such as OAuth
or key-pair authentication. Use the method approved by your
organization.

## 74.13 Do Not Use Embedded Credentials

Never store passwords, private keys, OAuth tokens, or refresh tokens
directly in application source code.

## 74.14 Secrets Management

Use an approved secrets-management or workload-identity architecture
such as AWS Secrets Manager, Azure Key Vault, HashiCorp Vault, an
approved CI/CD secret store, or workload identity where appropriate.

## 74.15 Dedicated API Identity

Example:

``` text
SVC_SNOWFLAKE_API
```

## 74.16 Dedicated Role

Example:

``` text
SNOWFLAKE_API_ROLE
```

## 74.17 Least Privilege

Grant the API role only the privileges required by the application.
Avoid `ACCOUNTADMIN` for routine API integrations.

## 74.18 Authorization

Requests use an authorization token according to the configured
authentication mechanism.

``` http
Authorization: Bearer <token>
```

Never log the token.

## 74.19 Token Lifecycle

Automation must safely handle token creation, expiration, rotation,
renewal, and revocation.

## 74.20 Request Body

Conceptually:

``` json
{
  "statement": "SELECT CURRENT_TIMESTAMP()",
  "warehouse": "API_WH",
  "database": "PROD_DB",
  "schema": "PUBLIC",
  "role": "SNOWFLAKE_API_ROLE"
}
```

## 74.21 Context Should Be Explicit

For production automation, explicitly define required role, warehouse,
database, and schema rather than depending unnecessarily on user
defaults.

## 74.22 Submit SQL with curl

``` bash
curl -X POST \
  "$SNOWFLAKE_URL/api/v2/statements" \
  -H "Authorization: Bearer $SNOWFLAKE_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
        "statement": "SELECT CURRENT_TIMESTAMP()",
        "warehouse": "API_WH",
        "database": "PROD_DB",
        "schema": "PUBLIC",
        "role": "SNOWFLAKE_API_ROLE"
      }'
```

Do not place real tokens in scripts committed to Git.

## 74.23 Verify Environment

Before destructive automation:

``` sql
SELECT
    CURRENT_ACCOUNT_NAME(),
    CURRENT_REGION(),
    CURRENT_USER(),
    CURRENT_ROLE(),
    CURRENT_WAREHOUSE(),
    CURRENT_DATABASE(),
    CURRENT_SCHEMA();
```

## 74.24 Guardrail

Expected account/environment values should be validated
programmatically. If the expected account does not match the actual
account, stop.

## 74.25 What Is a Statement Handle?

Snowflake can return a unique `statementHandle` representing the
submitted statement.

## 74.26 Why It Matters

The handle is used to check execution status, retrieve results, and
cancel execution.

## 74.27 Store the Handle

Automation should retain the statement handle for the lifetime of the
operation.

## 74.28 Synchronous Execution

For a query that completes quickly, Snowflake can return the result
directly.

## 74.29 Long-Running Query

A query may continue beyond the initial HTTP request:

``` text
POST
 |
 v
202 Accepted
 |
 v
statementHandle
 |
 v
GET status
 |
 +--> 202 Running
 |
 +--> 200 Complete
```

## 74.30 Explicit Async Execution

Conceptually:

``` text
POST /api/v2/statements?async=true
```

## 74.31 Design for Async

Production clients should handle asynchronous completion because
warehouse queueing, large scans, contention, warehouse resume, or
network delays can extend execution.

## 74.32 Status Request

``` text
GET /api/v2/statements/{statementHandle}
```

## 74.33 Do Not Poll Aggressively

Do not continuously poll without delay.

## 74.34 Polling Backoff

Use controlled intervals such as 1, 2, 4, and 8 seconds up to an
appropriate maximum.

## 74.35 Add Jitter

Add randomized delay so many workers do not poll simultaneously.

## 74.36 HTTP 200

Generally indicates successful completion for the operation.

## 74.37 HTTP 202

The statement is still executing. Continue status handling.

## 74.38 HTTP 4xx

Investigate authentication, authorization, request format, SQL failure,
and invalid parameters before retrying.

## 74.39 HTTP 5xx

May indicate transient service/server-side failure. Apply controlled
retry logic only when appropriate.

## 74.40 Never Retry Everything

Do not blindly retry invalid SQL, permission failures, invalid objects,
bad requests, or authentication failures.

## 74.41 HTTP Success Is Not the Entire Story

Inspect the Snowflake response body, including fields such as `code`,
`sqlState`, `message`, and `statementHandle`.

## 74.42 Log Error Metadata

Log HTTP status, Snowflake error code, SQLSTATE, statement handle,
request ID, timestamp, and operation without exposing sensitive data.

## 74.43 requestId

The SQL API supports a unique `requestId`. Use a UUID.

## 74.44 Why requestId Matters

Request IDs distinguish API requests and help with safe resubmission.

## 74.45 Network Failure Problem

A write may execute in Snowflake even if the client loses the response.
Blindly resending the write can duplicate effects.

## 74.46 Retry Support

Snowflake supports resubmission using the same request ID with retry
behavior.

Conceptually:

``` text
requestId=<same-uuid>
retry=true
```

## 74.47 Do Not Generate a New ID During Retry

For the same logical resubmission, preserve the original request ID.

## 74.48 New Operation

A genuinely new operation should receive a new request ID.

## 74.49 API Retry Is Only One Layer

Application workflows should still be designed for idempotency.

## 74.50 Safer Data Patterns

Depending on the use case, use `MERGE`, unique business keys,
idempotency keys, control tables, or processed-event tracking.

## 74.51 Non-Idempotent DML

Be especially careful with `INSERT`, `UPDATE`, and `DELETE` during
ambiguous network failures.

## 74.52 Query Results

Completed queries can return result-set metadata and data.

## 74.53 Large Results

Do not assume an entire large result set will always arrive in a single
response.

## 74.54 Partitioned Results

Large query results can be divided into partitions.

## 74.55 Partition Metadata

Responses can include result-partition metadata.

## 74.56 Retrieve Required Partitions

Retrieve partitions according to response metadata/links rather than
assuming a fixed partition count.

## 74.57 Do Not Load Everything Into Memory

Process large results incrementally where possible.

## 74.58 Streaming Application Pattern

Get partition → process → persist/send → release memory → get next
partition.

## 74.59 Push Processing to Snowflake

Filter and aggregate in Snowflake rather than retrieving millions of
rows to filter in application code.

``` sql
SELECT
    EMPI,
    STATUS
FROM PROD_DB.EMPI.PATIENT
WHERE STATUS = 'ACTIVE';
```

## 74.60 Multiple SQL Statements

The SQL API can execute multiple statements in supported request
patterns.

## 74.61 Individual Handles

For multiple statements, track individual statement handles when
results/status matter.

## 74.62 Production Recommendation

For critical changes, separate precheck, change, and validation unless
multi-statement execution provides a deliberate advantage.

## 74.63 Explicit Transactions

The SQL API supports workflows involving explicit Snowflake
transactions.

## 74.64 Transaction Pattern

``` sql
BEGIN;

UPDATE ...;

INSERT ...;

COMMIT;
```

## 74.65 Failure Handling

Understand which statements executed, whether COMMIT occurred, whether
rollback is required, and what session/transaction context is retained.

## 74.66 Cancel Endpoint

``` text
POST /api/v2/statements/{statementHandle}/cancel
```

## 74.67 When to Cancel

Examples include application timeout, user cancellation, runaway query,
deployment rollback, and operational incidents.

## 74.68 Client Timeout vs Query Cancellation

A client-side timeout does not automatically mean the Snowflake query
has stopped.

## 74.69 Verify Cancellation

Verify final query state after requesting cancellation.

## 74.70 Timeout Layers

A REST integration can contain HTTP client, API gateway, load balancer,
application, and Snowflake statement timeouts.

## 74.71 Align Timeouts

Poorly aligned timeouts can create orphaned queries, duplicate retries,
unexpected cost, and confusing incidents.

## 74.72 Retry Decision

Classify failures as permanent or transient. Retry only when safe, using
bounded backoff.

## 74.73 Retry Limits

Define maximum attempts, maximum elapsed time, retryable HTTP
codes/errors, backoff, and jitter.

## 74.74 Retry Budget

Do not let retries continue indefinitely.

## 74.75 Application Concurrency

Snowflake workload capacity still depends on warehouse size,
concurrency, query complexity, queueing, and cloud-services activity.

## 74.76 API Concurrency Is Not Warehouse Capacity

HTTP request capacity is not equivalent to SQL workload capacity.

## 74.77 Protect Snowflake

Use controlled worker/concurrency limits.

## 74.78 Dedicated API Warehouse

For important API workloads, consider a dedicated warehouse such as
`PATIENT360_API_WH`.

## 74.79 Workload Isolation

Separate API queries, ETL, BI, and ad-hoc administration when workload
characteristics justify it.

## 74.80 Auto-Suspend

Use appropriate auto-suspend to control cost.

## 74.81 Auto-Resume

Enable where the API workload requires automatic warehouse availability.

## 74.82 Query Tagging

Tag API workloads where appropriate, for example:

``` text
service=patient360-api
environment=prod
operation=get-patient
```

## 74.83 Why Query Tags?

They improve troubleshooting, cost attribution, workload analysis, and
incident investigation.

## 74.84 Application Metrics

Monitor API request count, success/failure rate, latency, retries,
timeouts, cancellations, and active statements.

## 74.85 Snowflake Metrics

Correlate with query history, warehouse load, queueing, query latency,
credits, and errors.

## 74.86 Statement Handle Correlation

Store application request ID, Snowflake request ID, and statement handle
together where practical.

## 74.87 Distributed Tracing

Propagate a safe correlation identifier through the workflow when
distributed tracing is used.

## 74.88 Structured Log

Example:

``` text
timestamp=<timestamp>
service=patient360-api
environment=prod
operation=get_patient
request_id=<uuid>
statement_handle=<handle>
http_status=200
duration_ms=325
status=success
```

## 74.89 Never Log Authentication Tokens

Never log Authorization headers, OAuth tokens, private keys, refresh
tokens, or secrets.

## 74.90 Protect Query Data

Avoid logging PHI/PII or complete SQL result sets.

## 74.91 Minimal Health Query

``` sql
SELECT
    CURRENT_TIMESTAMP(),
    CURRENT_ACCOUNT_NAME(),
    CURRENT_REGION(),
    CURRENT_ROLE();
```

## 74.92 Health Check Should Be Lightweight

Do not use a large production query merely to test connectivity.

## 74.93 Health Check Layers

Separate API reachability, authentication, SQL execution, warehouse
availability, and application dependency checks.

## 74.94 Python REST Example

``` python
import os
import requests
import uuid

base_url = os.environ["SNOWFLAKE_URL"]
token = os.environ["SNOWFLAKE_TOKEN"]
request_id = str(uuid.uuid4())

url = f"{base_url}/api/v2/statements?requestId={request_id}"

headers = {
    "Authorization": f"Bearer {token}",
    "Content-Type": "application/json"
}

payload = {
    "statement": "SELECT CURRENT_TIMESTAMP()",
    "warehouse": "API_WH",
    "database": "PROD_DB",
    "schema": "PUBLIC",
    "role": "SNOWFLAKE_API_ROLE"
}

response = requests.post(url, headers=headers, json=payload, timeout=30)
response.raise_for_status()
result = response.json()
```

Production code must add proper token generation/renewal, retry
classification, logging, observability, and async handling.

## 74.95 Async Submit

Conceptually:

``` python
response = requests.post(
    url + "&async=true",
    headers=headers,
    json=payload,
    timeout=30
)

result = response.json()
statement_handle = result["statementHandle"]
```

## 74.96 Poll

``` python
status_url = f"{base_url}/api/v2/statements/{statement_handle}"

response = requests.get(
    status_url,
    headers=headers,
    timeout=30
)
```

## 74.97 Polling Loop

Poll → check status → backoff → poll again, with a maximum elapsed time.

## 74.98 Language Independence

The REST API can be used from Python, Java, Go, JavaScript, C#,
PowerShell, shell, and workflow engines when authentication and API
behavior are implemented correctly.

## 74.99 PowerShell Request

``` powershell
$headers = @{
    Authorization = "Bearer $env:SNOWFLAKE_TOKEN"
    "Content-Type" = "application/json"
}

$body = @{
    statement = "SELECT CURRENT_TIMESTAMP()"
    warehouse = "API_WH"
    database  = "PROD_DB"
    schema    = "PUBLIC"
    role      = "SNOWFLAKE_API_ROLE"
} | ConvertTo-Json

Invoke-RestMethod `
    -Method Post `
    -Uri "$env:SNOWFLAKE_URL/api/v2/statements" `
    -Headers $headers `
    -Body $body
```

## 74.100 Pipeline Architecture

Git → Pipeline → Secure Identity → SQL API → Snowflake.

## 74.101 Deployment Operations

The API can support controlled DDL deployment, validation queries,
administrative checks, and post-deployment verification.

## 74.102 Prefer Purpose-Built Tooling Where Appropriate

Use Terraform for infrastructure lifecycle, the Python Connector for
Python database applications, and Snowflake CLI for command-line
administration where those tools fit better.

## 74.103 API Security Layers

Protect identity, authentication material, network path, Snowflake role,
warehouse, database objects, and application logs.

## 74.104 Network Policies

Snowflake network policies can affect SQL API access and should be
considered in architecture and troubleshooting.

## 74.105 Private Connectivity

Where required, design API access around approved Snowflake
private-connectivity architecture.

## 74.106 TLS

Use HTTPS and never disable certificate validation as a production
troubleshooting shortcut.

## 74.107 Never Accept Arbitrary SQL

Do not expose an unrestricted endpoint that executes arbitrary
caller-provided SQL.

## 74.108 Controlled Operations

Prefer application operations such as `GET /patient/{empi}`,
`POST /reconcile`, or `GET /health` with predefined parameterized SQL.

## 74.109 Parameter Binding

Use supported SQL API binding capabilities rather than concatenating
uncontrolled input into SQL.

## 74.110 Unsafe Pattern

Avoid SQL string concatenation such as:

``` text
"SELECT * FROM PATIENT WHERE EMPI = '" + userInput + "'"
```

## 74.111 Secure Pattern

Use controlled parameter binding and validate application inputs.

## 74.112 Administrative API Operations

The SQL API can execute supported DDL operations such as CREATE, ALTER,
and DROP.

## 74.113 Destructive DDL Guardrails

Before DROP, TRUNCATE, or destructive ALTER operations, verify account,
environment, role, object, dependencies, recovery path, and approval.

## 74.114 DML Operations

The API can execute supported INSERT, UPDATE, DELETE, and MERGE
operations.

## 74.115 Recovery Planning

Before destructive DML, understand Time Travel, clone, transaction
rollback, and backup/recovery strategy.

## 74.116 API Versioning

Track API documentation, authentication requirements, deprecated
behavior, client implementation, and Snowflake release changes.

## 74.117 Automated Regression Testing

Critical integrations should test authentication, submit, status,
results, cancellation, error handling, and retry after meaningful
platform/client changes.

## 74.118 Authentication Failure

Check token/key validity, expiration, service identity, account
identifier, authentication method, clock synchronization, and network.

## 74.119 Authorization Failure

Verify current user/role and inspect required grants.

## 74.120 Warehouse Failure

Check warehouse existence, USAGE privilege, resource monitor, warehouse
state, and environment.

## 74.121 HTTP 202 Forever

Investigate query history, warehouse queueing/capacity, query profile,
contention, and SQL design.

## 74.122 API Timeout

Determine whether the HTTP request timed out, the query is still
running, the query failed, or an intermediary gateway timed out. Do not
immediately resubmit destructive SQL.

## 74.123 Duplicate Data After Retry

Investigate request-ID handling, retry behavior, application
idempotency, write design, and network failures.

## 74.124 Large API Response

Review result partitioning, selected columns, filters, LIMIT,
aggregation, and application memory.

## 74.125 Unexpected Cost Increase

Check API request volume, query frequency, retry storms, polling
frequency, warehouse size/uptime, and expensive SQL.

## 74.126 Retry Storm

Symptoms include request spikes, repeated SQL, warehouse queueing,
higher credits, and application latency. Stop uncontrolled retries and
restore bounded backoff.

## 74.127 Production API Setup Runbook

1.  Identify application and environment.
2.  Select SQL API use case.
3.  Create dedicated service identity and least-privilege role.
4.  Select authentication and secure key/token lifecycle.
5.  Configure network access.
6.  Select warehouse and cost controls.
7.  Configure database/schema access.
8.  Test authentication and lightweight health query.
9.  Verify account, region, role, and warehouse.
10. Test statement handle, async execution, polling, results,
    cancellation, errors, and retries.
11. Configure secure logging, metrics, and alerts.
12. Document ownership.
13. Test in staging.
14. Approve production deployment.

## 74.128 API Failure Investigation Runbook

1.  Identify application, environment, and incident start.
2.  Check application health, request rate, HTTP errors, and latency.
3.  Check authentication/token expiration/network.
4.  Check Snowflake account, role, warehouse, and queueing.
5.  Capture request IDs and statement handles.
6.  Inspect query history and failed SQL.
7.  Check retry/polling behavior and duplicate-execution risk.
8.  Check resource monitor and service status where appropriate.
9.  Remediate, validate, monitor recovery, document root cause, and add
    preventive controls.

## 74.129 Ambiguous Request Runbook

If a write request times out:

1.  Stop blind retry.
2.  Capture original request ID, operation, and timestamp.
3.  Check for a statement handle and query-history evidence.
4.  Determine whether SQL executed and committed.
5.  Use supported resubmission semantics when appropriate.
6.  Reuse the same request ID for the same logical retry.
7.  Validate data state.
8.  Resume automation only when safe.
9.  Document the incident.

## 74.130 Async Query Runbook

1.  Submit query.
2.  Capture request ID and statement handle.
3.  If still running, start controlled polling.
4.  Apply backoff/jitter and track elapsed time.
5.  Check Snowflake status, warehouse queueing, and query profile.
6.  Cancel if operational thresholds are exceeded.
7.  Verify cancellation/final status.
8.  Alert if SLA is exceeded.

## 74.131 Patient360 API

``` text
Patient360 Service
        |
        v
Application API
        |
        v
Snowflake SQL API
        |
        v
PATIENT360_API_WH
        |
        v
PROD_DB.EMPI
```

## 74.132 Identity

Service identity: `SVC_PATIENT360_API`

Role: `PATIENT360_API_ROLE`

Warehouse: `PATIENT360_API_WH`

## 74.133 Read Request

A request such as `GET /patient/123456` should execute predefined
parameterized SQL:

``` sql
SELECT
    EMPI,
    STATUS,
    UPDATED_AT
FROM PROD_DB.EMPI.PATIENT
WHERE EMPI = ?;
```

Use supported bindings.

## 74.134 Correlation

Record application request ID, Snowflake request ID, statement handle,
duration, and status without logging patient data.

## 74.135 Slow Query

Capture statement handle → check Snowflake status → check warehouse →
inspect query history/profile → determine bottleneck.

## 74.136 Network Timeout During Write

If a MERGE executes but the HTTP response is lost, do not blindly issue
a new logical MERGE. Use original correlation/request information to
determine execution state and apply safe retry semantics.

## 74.137 Common Mistakes

Avoid hard-coded tokens, personal identities, ACCOUNTADMIN API roles,
unrestricted arbitrary-SQL endpoints, SQL concatenation, missing request
IDs/statement handles, blind or infinite retries, aggressive polling, no
jitter/timeouts, assuming client timeout cancels the query, ignoring
202/partitions, huge in-memory results, missing query tags/workload
isolation/cost controls, sensitive logs, missing token rotation, no
staging tests, and no incident runbook.

## 74.138 Production Standards

Use dedicated service identity, least privilege, approved OAuth/key-pair
authentication, secure key/token management, explicit environment and
SQL context, parameterized SQL, request IDs, statement-handle
correlation, idempotent design, safe resubmission, bounded retries,
exponential backoff/jitter, controlled polling, timeouts, explicit
cancellation, partition handling, controlled result sizes, query tags,
structured secure logging, PHI/PII protection, workload isolation, cost
controls, metrics/alerts, staging validation, and incident runbooks.

## 74.139 SRE/DBRE API Checklist

-   [ ] Dedicated service identity
-   [ ] Least-privilege role
-   [ ] Approved authentication
-   [ ] No token in source code
-   [ ] Token/key rotation defined
-   [ ] Network access validated
-   [ ] DEV/STAGING/PROD endpoints separated
-   [ ] Account/region/role/warehouse/database/schema validated
-   [ ] Parameter binding used
-   [ ] Request ID generated
-   [ ] Statement handle captured
-   [ ] HTTP/Snowflake errors handled
-   [ ] HTTP 202 handled
-   [ ] Async polling with backoff/jitter implemented
-   [ ] Retry limits configured
-   [ ] Idempotency reviewed
-   [ ] Ambiguous writes handled safely
-   [ ] Cancellation implemented where needed
-   [ ] Result partitions/large results handled
-   [ ] Query tagging configured
-   [ ] Structured logging configured
-   [ ] Tokens excluded from logs
-   [ ] PHI/PII protected
-   [ ] Warehouse cost controls configured
-   [ ] Monitoring/alerts configured
-   [ ] Incident runbook documented

## 74.140 Operational Quick Reference

AUTHENTICATE → BUILD REQUEST → GENERATE requestId → POST STATEMENT → if
200 process result; if 202 capture handle → poll with backoff → complete
or cancel when required.

## 74.141 Key Takeaways

1.  Snowflake provides REST APIs for programmatic integration.
2.  The SQL API provides REST-based SQL execution.
3.  Submit SQL through `/api/v2/statements`.
4.  Track execution with statement handles.
5.  Design clients to handle asynchronous execution and HTTP 202.
6.  Poll with controlled backoff and jitter.
7.  Use dedicated least-privilege service identities.
8.  Secure OAuth tokens/private keys and never log them.
9.  Explicitly identify and validate the environment/context.
10. Use parameterized SQL and never expose unrestricted SQL to untrusted
    callers.
11. Generate request IDs and preserve them during logical resubmission.
12. Do not blindly retry ambiguous writes.
13. Design operations for idempotency.
14. Handle partitioned/large results safely.
15. A client timeout does not necessarily cancel Snowflake execution.
16. Explicitly cancel and verify when required.
17. Correlate application requests with Snowflake statements.
18. Monitor API latency, retries, queueing, and cost.
19. Protect PHI/PII in logs.
20. Maintain API setup, incident, retry, and async-query runbooks.

## 74.142 Chapter Completion Checklist

After completing this chapter, you should be able to choose between the
SQL API, Python Connector, CLI, and Terraform; configure secure API
authentication and least privilege; submit SQL; define and verify
execution context; track statement handles; handle sync/async execution
and polling; interpret HTTP/Snowflake errors; generate request IDs;
safely resubmit ambiguous requests; design idempotent workflows; process
large partitioned results; handle
transactions/cancellation/timeouts/retries/concurrency; isolate
warehouses; use query tags and observability; build secure health checks
and clients; integrate with CI/CD; prevent SQL injection; protect
destructive DDL/DML; regression-test integrations; troubleshoot
authentication, permissions, timeouts, duplicates, large results, and
retry storms; and execute production API runbooks.

**Chapter 74 --- Snowflake REST APIs & Automation: Complete**
