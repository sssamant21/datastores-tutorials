# Chapter 72 --- Snowflake Python Connector & Snowpark

## 72.1 Overview

Python applications can interact with Snowflake primarily through two
complementary approaches:

``` text
Python Connector
      |
      +--> SQL execution
      +--> Administration
      +--> Automation
      +--> Data loading
      +--> Application integration

Snowpark Python
      |
      +--> DataFrame API
      +--> Data transformation
      +--> Stored procedures
      +--> UDFs
      +--> Data engineering
      +--> ML / application workloads
```

The Snowflake Python Connector is appropriate when the application
primarily needs to execute SQL and manage database interactions.

Snowpark is appropriate when developers want to build data-processing
logic using Python APIs while executing the workload inside Snowflake.

# Python Connector vs Snowpark

## 72.2 Python Connector

Typical use cases: execute SQL, administrative queries, automation,
load/unload data, retrieve query results, operational health checks, and
application integration.

## 72.3 Snowpark Python

Typical use cases: data engineering, transformations, DataFrame
operations, stored procedures, UDFs, feature engineering, application
logic, and ML pipelines.

## 72.4 Choosing Between Them

Use the Python Connector for SQL-oriented integration and Snowpark for
DataFrame/data-processing APIs. Many production applications use both.

# Environment Setup

## 72.5 Python Environment

``` bash
python -m venv .venv
```

## 72.6 Activate --- Windows

``` cmd
.venv\Scripts\activate
```

## 72.7 Activate --- PowerShell

``` powershell
.\.venv\Scripts\Activate.ps1
```

## 72.8 Activate --- Linux/macOS

``` bash
source .venv/bin/activate
```

## 72.9 Install Python Connector

``` bash
pip install snowflake-connector-python
```

## 72.10 Install Snowpark

``` bash
pip install snowflake-snowpark-python
```

## 72.11 Verify Packages

``` bash
pip show snowflake-connector-python
pip show snowflake-snowpark-python
```

# Python Connector

## 72.12 Import Connector

``` python
import snowflake.connector
```

## 72.13 Basic Connection

``` python
import snowflake.connector

conn = snowflake.connector.connect(
    account="<account_identifier>",
    user="<username>",
    password="<password>",
    warehouse="COMPUTE_WH",
    database="PROD_DB",
    schema="PUBLIC",
    role="APP_ROLE"
)
```

Do not hard-code passwords in production code.

## 72.14 Use Environment Variables

``` python
import os
import snowflake.connector

conn = snowflake.connector.connect(
    account=os.environ["SNOWFLAKE_ACCOUNT"],
    user=os.environ["SNOWFLAKE_USER"],
    password=os.environ["SNOWFLAKE_PASSWORD"],
    warehouse=os.environ["SNOWFLAKE_WAREHOUSE"],
    database=os.environ["SNOWFLAKE_DATABASE"],
    schema=os.environ["SNOWFLAKE_SCHEMA"],
    role=os.environ["SNOWFLAKE_ROLE"]
)
```

Environment variables are better than source-code secrets, but
production should still use approved secret-management/authentication.

# Authentication

## 72.15 Production Authentication

Depending on workload and organizational requirements, use key-pair
authentication, OAuth, workload identity, SSO, or an approved secrets
manager rather than static passwords where appropriate.

## 72.16 Service Accounts

Automation should normally use a dedicated identity such as
`SVC_PATIENT360_SNOWFLAKE`.

## 72.17 Least-Privilege Role

Use a role such as `PATIENT360_APP_ROLE` with only required privileges.
Avoid broad administrative roles for applications.

# Connection Management

## 72.18 Always Close Connections

``` python
conn.close()
```

## 72.19 Context Manager

``` python
import snowflake.connector

with snowflake.connector.connect(
    account="...",
    user="...",
    password="..."
) as conn:
    with conn.cursor() as cur:
        cur.execute("SELECT CURRENT_TIMESTAMP()")
        print(cur.fetchone())
```

## 72.20 Cursor Management

``` python
with conn.cursor() as cur:
    cur.execute("SELECT CURRENT_VERSION()")
    print(cur.fetchone())
```

# Connection Validation

## 72.21 Verify Context

``` python
query = """
SELECT
    CURRENT_ACCOUNT_NAME(),
    CURRENT_REGION(),
    CURRENT_USER(),
    CURRENT_ROLE(),
    CURRENT_WAREHOUSE(),
    CURRENT_DATABASE(),
    CURRENT_SCHEMA()
"""

with conn.cursor() as cur:
    cur.execute(query)
    for row in cur:
        print(row)
```

## 72.22 Production Guardrail

Before destructive automation verify account, region, role, database,
and schema.

# Query Execution

## 72.23 Simple Query

``` python
with conn.cursor() as cur:
    cur.execute("SELECT CURRENT_TIMESTAMP()")
    row = cur.fetchone()
    print(row)
```

## 72.24 Multiple Rows

``` python
with conn.cursor() as cur:
    cur.execute("""
        SELECT TABLE_SCHEMA, TABLE_NAME
        FROM PROD_DB.INFORMATION_SCHEMA.TABLES
        LIMIT 20
    """)
    for row in cur:
        print(row)
```

## 72.25 fetchone()

``` python
row = cur.fetchone()
```

## 72.26 fetchmany()

``` python
rows = cur.fetchmany(100)
```

Useful when processing results incrementally.

## 72.27 fetchall()

``` python
rows = cur.fetchall()
```

Be careful with very large result sets.

# Parameterized SQL

## 72.28 Do Not Build SQL With String Concatenation

Avoid constructing SQL with uncontrolled values using f-strings or
concatenation.

## 72.29 Bind Parameters

``` python
sql = """
SELECT *
FROM PROD_DB.EMPI.PATIENT
WHERE EMPI = %s
"""

with conn.cursor() as cur:
    cur.execute(sql, (empi,))
```

## 72.30 Parameterization Benefits

Security, correct quoting, cleaner code, and reduced injection risk.

# Query IDs

## 72.31 Capture Query ID

``` python
with conn.cursor() as cur:
    cur.execute("SELECT CURRENT_TIMESTAMP()")
    print(cur.sfqid)
```

## 72.32 Why Capture Query IDs?

They help with query history, performance troubleshooting, incident
investigation, auditability, and support cases.

## 72.33 Production Logging

Log timestamp, application, environment, query ID, operation, duration,
and status without unnecessarily logging sensitive data.

# Error Handling

## 72.34 Basic Error Handling

``` python
import snowflake.connector

try:
    conn = snowflake.connector.connect(
        account="...",
        user="...",
        password="..."
    )
except snowflake.connector.errors.Error as exc:
    print(f"Snowflake connection failed: {exc}")
```

## 72.35 Query Error

``` python
try:
    with conn.cursor() as cur:
        cur.execute("SELECT * FROM INVALID_TABLE")
except snowflake.connector.errors.Error as exc:
    print(f"Snowflake query failed: {exc}")
```

## 72.36 Do Not Swallow Errors

Operational failures should be visible. Avoid broad exception handlers
that silently ignore failures.

## 72.37 Capture Error Context

Where safe, capture error type, error code, SQLSTATE, query ID,
operation, and timestamp without exposing secrets.

# Retry Logic

## 72.38 Not Every Failure Should Be Retried

Do not blindly retry syntax errors, permission denied, invalid objects,
bad SQL, or incorrect data.

## 72.39 Retry Transient Failures

Transient failures may be retried with controlled backoff depending on
application requirements.

## 72.40 Exponential Backoff

Attempt → wait → retry → wait longer → retry.

## 72.41 Add Jitter

Jitter prevents many application instances from retrying simultaneously.

## 72.42 Retry Limits

Define maximum attempts, maximum elapsed time, retryable errors, and
non-retryable errors.

# Transactions

## 72.43 Explicit Transactions

``` python
with conn.cursor() as cur:
    cur.execute("BEGIN")
    try:
        cur.execute("""
            UPDATE PROD_DB.APP.CONFIG
            SET VALUE = 'NEW'
            WHERE KEY = 'SETTING_A'
        """)
        cur.execute("COMMIT")
    except Exception:
        cur.execute("ROLLBACK")
        raise
```

## 72.44 Understand DDL Behavior

Do not assume all Snowflake statements behave identically inside
transactions. Validate transaction semantics.

## 72.45 Idempotency

Automation should be designed so retries do not create unintended
duplicate changes.

# Batch Operations

## 72.46 executemany()

``` python
rows = [(1, "A"), (2, "B"), (3, "C")]

with conn.cursor() as cur:
    cur.executemany(
        """
        INSERT INTO APP_TABLE (ID, VALUE)
        VALUES (%s, %s)
        """,
        rows
    )
```

## 72.47 Avoid Row-by-Row for Large Loads

Do not use thousands or millions of individual INSERT calls when
Snowflake bulk-loading mechanisms are more appropriate.

# Bulk Data Loading

## 72.48 Large Data Loads

For large ingestion use Snowflake-native patterns such as stages, PUT,
COPY INTO, Snowpipe, or supported streaming/ingestion architecture.

## 72.49 Connector Is Not a Replacement for Pipeline Architecture

A Python loop inserting millions of rows is usually not an optimal
production ingestion design.

# Result Handling

## 72.50 Large Result Sets

Avoid loading enormous results entirely into application memory.

## 72.51 Process Incrementally

Use `fetchmany()` or another appropriate result-handling mechanism.

## 72.52 Push Processing to Snowflake

Prefer filter, aggregate, join, and transform operations inside
Snowflake rather than transferring unnecessary data to Python.

# Performance

## 72.53 Performance Responsibility

Performance depends on SQL quality, warehouse sizing, concurrency,
network, result size, connection management, and application logic.

## 72.54 Avoid SELECT \*

Select only required columns.

## 72.55 Limit Results

For operational checks use `LIMIT` where appropriate.

## 72.56 Filter Early

Push restrictive predicates into Snowflake.

# Connection Reuse

## 72.57 Avoid Connection Per Row

Do not connect/query/close for every individual row.

## 72.58 Reuse Connections Carefully

Use appropriate connection lifecycle or pooling strategies for the
framework and workload.

## 72.59 Connection Health

Long-running services should handle stale or failed connections safely.

# Snowpark

## 72.60 Snowpark Session

Snowpark uses a `Session` as the primary connection/context object.

## 72.61 Import Session

``` python
from snowflake.snowpark import Session
```

## 72.62 Create Session

``` python
from snowflake.snowpark import Session

connection_parameters = {
    "account": "<account>",
    "user": "<user>",
    "password": "<password>",
    "role": "APP_ROLE",
    "warehouse": "APP_WH",
    "database": "PROD_DB",
    "schema": "PUBLIC"
}

session = Session.builder.configs(connection_parameters).create()
```

Do not hard-code credentials in production.

## 72.63 Close Session

``` python
session.close()
```

# Snowpark DataFrames

## 72.64 Read Table

``` python
df = session.table("PROD_DB.EMPI.PATIENT")
```

## 72.65 Select Columns

``` python
df = df.select("EMPI", "UPDATED_AT", "STATUS")
```

## 72.66 Filter

``` python
df = df.filter(df["STATUS"] == "ACTIVE")
```

## 72.67 Display Results

``` python
df.show()
```

Avoid uncontrolled large result display in production.

## 72.68 Collect

``` python
rows = df.collect()
```

`collect()` transfers results to the Python client. Be careful with
large datasets.

## 72.69 Lazy Evaluation

Snowpark DataFrame transformations are generally built as a logical plan
and executed when an action requires results.

## 72.70 Pushdown

A major Snowpark advantage is executing data processing in Snowflake
rather than moving the dataset to the Python client.

# Snowpark Transformations

## 72.71 Filter Example

``` python
from snowflake.snowpark.functions import col

df = (
    session.table("PROD_DB.EMPI.PATIENT")
    .filter(col("STATUS") == "ACTIVE")
)
```

## 72.72 Select Example

``` python
df = df.select(col("EMPI"), col("UPDATED_AT"))
```

## 72.73 Group By

``` python
from snowflake.snowpark.functions import count

df = (
    session.table("PROD_DB.EMPI.PATIENT")
    .group_by(col("STATUS"))
    .agg(count("*").alias("COUNT"))
)
```

## 72.74 Sort

``` python
df = df.sort(col("UPDATED_AT").desc())
```

# Writing Data

## 72.75 Save DataFrame

Snowpark can write DataFrames into Snowflake tables. Select the save
mode carefully.

## 72.76 Avoid Accidental Overwrite

Before overwrite semantics, verify target table, environment, recovery
path, expected data volume, and downstream impact.

## 72.77 Production Guard

``` python
session.sql("""
SELECT
    CURRENT_ACCOUNT_NAME(),
    CURRENT_REGION(),
    CURRENT_ROLE(),
    CURRENT_DATABASE(),
    CURRENT_SCHEMA()
""").show()
```

# SQL Through Snowpark

## 72.78 Execute SQL

``` python
df = session.sql("""
SELECT
    CURRENT_ACCOUNT_NAME(),
    CURRENT_REGION(),
    CURRENT_ROLE()
""")
df.show()
```

## 72.79 Snowpark Does Not Eliminate SQL

Production Snowpark developers should still understand Snowflake SQL and
query execution.

# Stored Procedures

## 72.80 Snowpark Stored Procedures

Python logic can run inside Snowflake using supported stored-procedure
capabilities.

## 72.81 Typical Use Cases

Administrative workflow, data transformation, pipeline orchestration,
metadata processing, and controlled application logic.

## 72.82 Keep Procedures Focused

Avoid enormous stored procedures that become difficult to test, deploy,
troubleshoot, version, and observe.

# UDFs

## 72.83 Python UDFs

Python UDFs allow supported Python logic to participate in Snowflake
query processing.

## 72.84 UDF Use Cases

Examples include custom parsing, normalization, and domain-specific
transformation.

## 72.85 Avoid UDF When SQL Is Simpler

Prefer native SQL functions when they solve the problem efficiently.

# Packages and Dependencies

## 72.86 Dependency Management

Snowpark applications should explicitly manage package dependencies.

## 72.87 Version Control

Track Python version, Snowflake Connector version, Snowpark version, and
application dependencies.

## 72.88 Pin Production Dependencies

Use an approved dependency-management process; uncontrolled package
upgrades can introduce unexpected behavior.

# Observability

## 72.89 Application Metrics

Monitor connection failures, query failures, query latency, retry count,
rows processed, and pipeline duration.

## 72.90 Snowflake Metrics

Correlate application behavior with query history, warehouse load,
queueing, credits, errors, and query profile.

## 72.91 Query IDs Are the Bridge

Application query IDs connect application logs to Snowflake query
history.

# Python Logging

## 72.92 Structured Logging

Example fields: timestamp, service, environment, operation, query_id,
duration_ms, status.

## 72.93 Do Not Log Sensitive Data

Avoid passwords, private keys, tokens, PHI, PII, and full query results
unless explicitly required and protected.

# Timeout Strategy

## 72.94 Queries Should Not Run Forever

Define application expectations for query duration.

## 72.95 Timeout Ownership

Align application timeout, connector timeout, Snowflake statement
timeout, load-balancer timeout, and job timeout.

# Cancellation

## 72.96 Query Cancellation

Applications should understand how long-running or abandoned Snowflake
queries are handled.

## 72.97 Client Timeout Is Not Always Query Cancellation

Do not assume an application timeout means the Snowflake query stopped.
Verify behavior for the implementation.

# Idempotent Automation

## 72.98 Why Idempotency Matters

A Snowflake operation may succeed, followed by a network failure that
causes the application to retry and create duplicate effects.

## 72.99 Design for Safe Retry

Use MERGE, unique business keys, state tracking, transaction control, or
idempotency keys where appropriate.

# Security

## 72.100 Security Checklist

Use dedicated identity, least privilege, secure authentication, secret
rotation, network controls, no embedded secrets, safe logging, and
dependency scanning.

## 72.101 Key Rotation

If key-pair authentication is used, implement controlled key rotation
without application outage.

## 72.102 Credential Failure

Applications should fail safely when credentials expire or
authentication fails.

# Production Deployment

## 72.103 Deployment Pipeline

Git → Pull Request → Tests → Security Scan → Build → Deploy → Smoke Test
→ Monitor.

## 72.104 Development to Production

Use Development, Staging, and Production with separate credentials and
configuration.

## 72.105 Do Not Share Production Credentials

Each environment should have independent authentication.

# Unit Testing

## 72.106 Test Business Logic

Separate pure Python logic from Snowflake interaction where practical.

## 72.107 Integration Testing

Use controlled non-production Snowflake to test authentication, SQL,
permissions, transactions, and Snowpark transformations.

## 72.108 Production Smoke Test

After deployment: connect, verify context, run a minimal query, validate
application operation, and monitor errors.

# Troubleshooting

## 72.109 Connection Failure

Check account, username, authentication, secret/key, network, proxy,
private connectivity, and network policy.

## 72.110 Permission Failure

``` sql
SELECT CURRENT_USER(), CURRENT_ROLE();
```

Then inspect required grants.

## 72.111 Warehouse Failure

``` sql
SELECT CURRENT_WAREHOUSE();
```

Validate USAGE privilege, warehouse state, resource monitor, and
capacity.

## 72.112 Query Slow

Capture query ID and investigate query profile, warehouse, queueing,
spill, partitions scanned, and SQL design.

## 72.113 High Memory in Python

Check whether the application uses `fetchall()` or `collect()` on very
large datasets.

## 72.114 Retry Storm

Symptoms include many connection attempts, repeated queries, warehouse
pressure, and API pressure. Fix with bounded exponential backoff and
jitter.

## 72.115 Snowpark Performance Issue

Investigate generated SQL, query profile, warehouse sizing, data volume,
filters, joins, and `collect()` usage.

# Operational Runbooks

## 72.116 Python Connector Setup Runbook

1.  Create virtual environment.
2.  Install connector.
3.  Pin approved version.
4.  Create service identity.
5.  Create least-privilege role.
6.  Configure authentication.
7.  Configure secrets.
8.  Configure warehouse.
9.  Configure database/schema.
10. Test connection.
11. Verify account.
12. Verify region.
13. Verify role.
14. Execute test query.
15. Capture query ID.
16. Configure logging.
17. Configure error handling.
18. Configure retry policy.
19. Configure monitoring.
20. Document owner.

## 72.117 Snowpark Setup Runbook

1.  Create Python environment.
2.  Install Snowpark.
3.  Pin version.
4.  Configure authentication.
5.  Configure role.
6.  Configure warehouse.
7.  Configure database/schema.
8.  Create Session.
9.  Verify context.
10. Read test table.
11. Execute filter.
12. Execute transformation.
13. Validate generated workload.
14. Test result handling.
15. Configure logging.
16. Configure monitoring.
17. Test in staging.
18. Document deployment.
19. Define rollback.
20. Promote through approved pipeline.

## 72.118 Application Troubleshooting Runbook

1.  Identify application.
2.  Identify environment.
3.  Record connector/Snowpark version.
4.  Record error.
5.  Test network.
6.  Test authentication.
7.  Verify account.
8.  Verify region.
9.  Verify role.
10. Verify warehouse.
11. Verify database/schema.
12. Run minimal query.
13. Capture query ID.
14. Check Snowflake query history.
15. Check warehouse state.
16. Check permissions.
17. Check retry behavior.
18. Check timeout behavior.
19. Check application logs.
20. Remediate.
21. Retest.
22. Monitor.

# Production Scenario

## 72.119 Patient360 Python Service

``` text
Patient360 Service
       |
       v
Python Application
       |
       v
Snowflake Connector
       |
       v
Snowflake
```

## 72.120 Service Identity

Service identity: `SVC_PATIENT360`

Role: `PATIENT360_APP_ROLE`

Warehouse: `PATIENT360_WH`

## 72.121 Application Query

``` python
sql = """
SELECT
    EMPI,
    STATUS,
    UPDATED_AT
FROM PROD_DB.EMPI.PATIENT
WHERE EMPI = %s
"""

with conn.cursor() as cur:
    cur.execute(sql, (empi,))
    result = cur.fetchone()
    query_id = cur.sfqid
```

## 72.122 Application Log

Record service, environment, operation, query ID, duration, and status.
Do not log patient data unnecessarily.

## 72.123 Failure Handling

Classify the error. Permanent failures should fail; transient failures
may use bounded backoff, jitter, and limited retry.

## 72.124 Performance Incident

If Patient360 becomes slow:

1.  Capture application latency.
2.  Capture Snowflake query ID.
3.  Check Snowflake query history.
4.  Check warehouse queueing.
5.  Inspect query profile.
6.  Check application connection behavior.
7.  Check result size.
8.  Check retries.
9.  Check network latency.
10. Remediate the actual bottleneck.

# Production Standards

## 72.125 Common Mistakes

Avoid hard-coded credentials, personal accounts, ACCOUNTADMIN
applications, string-concatenated SQL, no query IDs/timeouts, infinite
retries, retries without jitter, connection-per-row, huge
`fetchall()`/`collect()`, row-by-row massive ingestion, no environment
separation/dependency pinning/monitoring/recovery strategy, sensitive
data in logs, and ignored warehouse capacity.

## 72.126 Production Standards

Use dedicated service identities, least-privilege roles, secure
authentication, secrets outside source code, separate environment
credentials, parameterized SQL, explicit connection lifecycle, bounded
retries, exponential backoff, jitter, query IDs, structured logging,
PHI/PII protection, Snowflake-side processing, bulk loading for large
ingestion, controlled result sizes, careful `collect()`, pinned
dependencies, defined timeouts, idempotency, warehouse monitoring,
integration tests, and production smoke tests.

## 72.127 SRE/DBRE Python Checklist

-   [ ] Python environment isolated
-   [ ] Connector/Snowpark version pinned
-   [ ] Dedicated service identity
-   [ ] Least-privilege role
-   [ ] Secure authentication
-   [ ] Secrets outside code
-   [ ] Dev credentials separate
-   [ ] Staging credentials separate
-   [ ] Prod credentials separate
-   [ ] Account verified
-   [ ] Region verified
-   [ ] Role verified
-   [ ] Warehouse verified
-   [ ] Database/schema verified
-   [ ] Parameterized SQL
-   [ ] Connections closed correctly
-   [ ] Cursors closed correctly
-   [ ] Query IDs captured
-   [ ] Errors handled
-   [ ] Retryable errors classified
-   [ ] Retry limit configured
-   [ ] Backoff configured
-   [ ] Jitter configured
-   [ ] Timeouts defined
-   [ ] Idempotency reviewed
-   [ ] Result sizes controlled
-   [ ] Bulk ingestion used where appropriate
-   [ ] Logging structured
-   [ ] PHI/PII protected
-   [ ] Monitoring configured
-   [ ] Integration tests complete
-   [ ] Production smoke test defined

## 72.128 Operational Quick Reference

Create Python Environment → Install Connector/Snowpark → Configure
Secure Auth → Apply Least Privilege → Verify Context → Execute
Parameterized Workload → Capture Query ID → Handle Errors → Retry
Transient Failures Safely → Monitor Application + Snowflake.

## 72.129 Key Takeaways

1.  The Python Connector is ideal for SQL-oriented integration.
2.  Snowpark provides Python DataFrame and in-Snowflake processing
    capabilities.
3.  Many applications use both.
4.  Use isolated Python environments.
5.  Pin production dependencies.
6.  Never hard-code credentials.
7.  Prefer strong production authentication.
8.  Use dedicated service identities.
9.  Apply least privilege.
10. Separate environment credentials.
11. Explicitly manage connection lifecycle.
12. Close cursors.
13. Verify account context before destructive operations.
14. Parameterize SQL.
15. Never concatenate uncontrolled values into SQL.
16. Capture Snowflake query IDs.
17. Query IDs connect application logs to Snowflake history.
18. Do not swallow exceptions.
19. Classify retryable and non-retryable failures.
20. Use bounded exponential backoff.
21. Add jitter.
22. Design idempotent operations.
23. Avoid row-by-row massive ingestion.
24. Push large processing into Snowflake.
25. Be careful with `fetchall()`.
26. Be careful with Snowpark `collect()`.
27. Monitor both application and Snowflake metrics.
28. Protect PHI/PII in logs.
29. Test outside production.
30. Use production smoke tests after deployment.

## 72.130 Chapter Completion Checklist

After completing this chapter, you should be able to explain Python
Connector vs Snowpark; create an isolated Python environment; install
Snowflake Python libraries; secure authentication; create/manage
connections and cursors; verify context; execute and parameterize SQL;
capture query IDs; handle errors, retries, backoff, jitter,
transactions, and idempotency; perform batch operations; select
bulk-loading architecture; handle large result sets; optimize connector
workloads; create Snowpark sessions and DataFrames;
filter/select/group/sort; understand lazy execution and pushdown; write
data safely; execute SQL through Snowpark; understand stored procedures
and UDFs; manage dependencies; implement observability, timeouts,
cancellation, security, deployment, and testing; troubleshoot
applications; execute operational runbooks; and apply production
SRE/DBRE standards.

**Chapter 72 --- Snowflake Python Connector & Snowpark: Complete**
