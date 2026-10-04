# 23 — Stored Procedures

## Overview

Snowflake Stored Procedures allow multiple operations and procedural logic to be packaged into reusable server-side routines.

A stored procedure can coordinate operations such as validation, staging, transformation, MERGE processing, audit logging, and status reporting.

Common use cases include multi-step ETL/ELT, pipeline orchestration, administrative automation, validation, conditional processing, dynamic SQL, metadata-driven operations, batch processing, audit logging, controlled maintenance, and recovery operations.

---

## 1. Stored Procedure vs SQL Statement

A normal SQL statement performs an operation:

```sql
DELETE FROM table_name
WHERE condition;
```

A stored procedure can coordinate multiple operations:

```text
Check prerequisites
      |
      v
Determine processing window
      |
      v
Execute DML
      |
      v
Validate
      |
      v
Audit
      |
      v
Return result
```

Use stored procedures when procedural coordination provides real value.

---

## 2. Stored Procedure vs UDF

| Area | Stored Procedure | UDF |
|---|---|---|
| Main purpose | Perform operations/workflows | Calculate/return values |
| Multi-step logic | Yes | More function-oriented |
| DML/administration | Common use case | Not primary purpose |
| Called with | CALL | SQL expressions |
| Pipeline orchestration | Yes | No |
| Reusable calculation | Possible, but not primary | Yes |

Chapter 24 covers UDFs in depth.

---

## 3. Stored Procedure Languages

Snowflake supports stored procedure development using supported handler languages and Snowflake Scripting.

Common choices include Snowflake Scripting / SQL, JavaScript, Python, Java, and Scala.

This chapter emphasizes SQL/Snowflake Scripting because it integrates naturally with database operations.

---

## 4. Basic SQL Stored Procedure

```sql
CREATE OR REPLACE PROCEDURE snowflake_tutorial.raw.hello_procedure()
RETURNS VARCHAR
LANGUAGE SQL
AS
$$
BEGIN
    RETURN 'Hello from Snowflake';
END;
$$;
```

Call it:

```sql
CALL snowflake_tutorial.raw.hello_procedure();
```

Expected result: Hello from Snowflake.

---

## 5. Procedure Parameters

```sql
CREATE OR REPLACE PROCEDURE snowflake_tutorial.raw.greet_user(user_name VARCHAR)
RETURNS VARCHAR
LANGUAGE SQL
AS
$$
BEGIN
    RETURN 'Hello, ' || user_name;
END;
$$;
```

```sql
CALL snowflake_tutorial.raw.greet_user('Data Engineer');
```

---

## 6. Return Types

A procedure declares its return type.

A procedure can return information such as SUCCESS, FAILED, rows processed, batch identifier, validation result, or an operational message.

Choose a return contract that callers can understand reliably.

---

## 7. Variables

```sql
CREATE OR REPLACE PROCEDURE snowflake_tutorial.raw.variable_demo()
RETURNS VARCHAR
LANGUAGE SQL
AS
$$
DECLARE
    message VARCHAR;
BEGIN
    message := 'Procedure executed successfully';

    RETURN message;
END;
$$;
```

Variables can store parameters, timestamps, counters, status values, query results, and control information.

---

## 8. Assigning Query Results

```sql
DECLARE
    row_count NUMBER;
BEGIN
    SELECT COUNT(*)
      INTO :row_count
    FROM snowflake_tutorial.raw.customer_target;

    RETURN 'Rows: ' || row_count;
END;
```

This allows SQL results to influence subsequent procedural logic.

---

## 9. Conditional Logic

```sql
CREATE OR REPLACE PROCEDURE snowflake_tutorial.raw.check_customer_data()
RETURNS VARCHAR
LANGUAGE SQL
AS
$$
DECLARE
    row_count NUMBER;
BEGIN
    SELECT COUNT(*)
      INTO :row_count
    FROM snowflake_tutorial.raw.customer_target;

    IF (row_count = 0) THEN
        RETURN 'EMPTY';
    ELSE
        RETURN 'DATA_AVAILABLE';
    END IF;
END;
$$;
```

---

## 10. IF / ELSE Logic

Use conditional logic when processing genuinely depends on runtime state.

Avoid procedural logic when a simpler SQL statement can solve the same problem clearly.

---

## 11. Loops

Procedural workflows can require iteration for metadata-driven administration, object lists, validation across schemas, and controlled maintenance.

Avoid row-by-row loops for large data transformations when set-based SQL can perform the operation efficiently.

---

## 12. Set-Based SQL vs Loops

Prefer:

```sql
UPDATE large_table
SET status = 'COMPLETE'
WHERE condition;
```

over processing millions of records one at a time.

Snowflake is optimized for set-based data processing. Stored procedure loops are best suited to orchestration and metadata operations.

---

## 13. Create a Pipeline Procedure

Suppose Chapter 22's incremental pipeline requires validation, MERGE, and audit completion.

```sql
CREATE OR REPLACE TABLE snowflake_tutorial.raw.procedure_audit (
    run_id          VARCHAR,
    procedure_name  VARCHAR,
    started_at      TIMESTAMP_NTZ,
    completed_at    TIMESTAMP_NTZ,
    status          VARCHAR,
    message         VARCHAR
);
```

---

## 14. Basic Pipeline Procedure

```sql
CREATE OR REPLACE PROCEDURE snowflake_tutorial.raw.process_customers()
RETURNS VARCHAR
LANGUAGE SQL
AS
$$
DECLARE
    run_id VARCHAR;
BEGIN

    run_id := UUID_STRING();

    INSERT INTO snowflake_tutorial.raw.procedure_audit
    (
        run_id,
        procedure_name,
        started_at,
        status
    )
    VALUES
    (
        :run_id,
        'PROCESS_CUSTOMERS',
        CURRENT_TIMESTAMP(),
        'RUNNING'
    );

    MERGE INTO snowflake_tutorial.raw.customer_target t
    USING snowflake_tutorial.raw.customer_stage s
       ON t.customer_id = s.customer_id

    WHEN MATCHED
         AND s.updated_at > t.updated_at
    THEN UPDATE SET
        t.customer_name = s.customer_name,
        t.email = s.email,
        t.status = s.status,
        t.updated_at = s.updated_at

    WHEN NOT MATCHED
    THEN INSERT
    (
        customer_id,
        customer_name,
        email,
        status,
        updated_at
    )
    VALUES
    (
        s.customer_id,
        s.customer_name,
        s.email,
        s.status,
        s.updated_at
    );

    UPDATE snowflake_tutorial.raw.procedure_audit
    SET
        completed_at = CURRENT_TIMESTAMP(),
        status = 'SUCCESS',
        message = 'Customer processing completed'
    WHERE run_id = :run_id;

    RETURN 'SUCCESS: ' || run_id;

END;
$$;
```

---

## 15. Call the Pipeline Procedure

```sql
CALL snowflake_tutorial.raw.process_customers();

SELECT *
FROM snowflake_tutorial.raw.procedure_audit
ORDER BY started_at DESC;

SELECT *
FROM snowflake_tutorial.raw.customer_target
ORDER BY customer_id;
```

Never use only the procedure return message as proof that business data is correct.

---

## 16. Input Validation

```sql
CREATE OR REPLACE PROCEDURE snowflake_tutorial.raw.process_batch(batch_id VARCHAR)
RETURNS VARCHAR
LANGUAGE SQL
AS
$$
BEGIN

    IF (batch_id IS NULL OR TRIM(batch_id) = '') THEN
        RETURN 'ERROR: batch_id is required';
    END IF;

    RETURN 'Processing batch: ' || batch_id;

END;
$$;
```

Production procedures should reject invalid input early.

---

## 17. Prefer Explicit Failure Semantics

Useful operational errors identify the procedure, stage, batch, object, and failure reason.

A vague message such as "Something went wrong" is usually insufficient for production operations.

---

## 18. Exception Handling

Production procedures should anticipate failure.

```text
BEGIN
   |
   v
Operations
   |
   +---- Success → return success
   |
   +---- Exception
             |
             v
        Capture failure
             |
             v
        Audit / re-raise
```

Snowflake Scripting provides exception-handling constructs for procedural blocks.

---

## 19. Exception Handling Pattern

```sql
BEGIN

    -- processing logic

EXCEPTION

    WHEN OTHER THEN

        -- capture/log failure
        -- return or raise according to design

END;
```

Do not silently swallow exceptions. A caller or monitoring system must be able to distinguish SUCCESS from FAILED.

---

## 20. Preserve the Original Failure

A dangerous pattern is returning SUCCESS after an exception or replacing a useful database error with an unhelpful generic message.

Preserve enough information to identify the original failure while avoiding inappropriate exposure of sensitive data.

---

## 21. Transactions

Multi-step procedures may require transactional behavior.

```sql
BEGIN TRANSACTION;

-- operation 1
-- operation 2
-- operation 3

COMMIT;
```

If required:

```sql
ROLLBACK;
```

The transaction design should reflect the required consistency boundary.

---

## 22. Why Transaction Boundaries Matter

If a target MERGE succeeds but a watermark update fails, replay may occur.

The reverse is more dangerous: if the watermark advances while target processing does not complete, data may be skipped.

Design related state transitions carefully.

---

## 23. Procedure and Transaction Design

A good procedure should make clear:

- What must succeed together?
- What can commit independently?
- What happens after failure?
- Can the operation be retried safely?

These questions matter more than simply wrapping every statement in one large transaction.

---

## 24. Idempotent Procedures

A production procedure should ideally be safe to retry where practical.

If `CALL process_batch('BATCH_100')` runs twice, determine whether data duplicates, counters double, rows regress, or audit records become misleading.

Design operations around stable business keys, batch IDs, MERGE, and deterministic processing.

---

## 25. Batch Control

```sql
CREATE OR REPLACE TABLE snowflake_tutorial.raw.batch_control (
    batch_id       VARCHAR,
    status         VARCHAR,
    started_at     TIMESTAMP_NTZ,
    completed_at   TIMESTAMP_NTZ
);
```

A procedure can check whether a batch has already completed before processing it again.

---

## 26. Batch Status Lifecycle

```text
PENDING
   |
   v
RUNNING
   |
   +----> SUCCESS
   |
   +----> FAILED
```

Avoid ambiguous states. During recovery, batch status should help determine whether processing started, finished, failed, or can be replayed.

---

## 27. Dynamic SQL

Sometimes object names or SQL structure must be determined at runtime.

Examples include different source tables, schemas, date-specific objects, and metadata-driven administration.

In Snowflake Scripting, EXECUTE IMMEDIATE is an important mechanism for dynamically constructed SQL.

---

## 28. Dynamic SQL Example

```sql
DECLARE
    sql_text VARCHAR;
BEGIN

    sql_text :=
        'SELECT COUNT(*) FROM snowflake_tutorial.raw.customer_target';

    EXECUTE IMMEDIATE :sql_text;

END;
```

Use dynamic SQL only when necessary. Static SQL is easier to validate, secure, troubleshoot, optimize, and review.

---

## 29. Dynamic Object Names

SQL bind variables represent values, not arbitrary SQL syntax.

When object identifiers must be dynamic, use Snowflake-supported identifier handling and carefully controlled dynamic SQL.

Object identifiers and scalar values are different concepts.

---

## 30. SQL Injection Risk

Dynamic SQL becomes dangerous when untrusted strings are concatenated into SQL.

Use bind variables where applicable, controlled identifier handling, allowlists, and strict validation.

Do not accept arbitrary object names or SQL fragments unless the design explicitly requires and secures them.

---

## 31. Procedure Security Model

Stored procedures execute according to Snowflake's configured execution-rights model.

A procedure may execute with caller or owner rights depending on how it is defined.

Understand the security implications before deployment.

---

## 32. Caller's Rights

Caller-rights procedures can be useful when the procedure should respect the caller's existing access.

Different callers may produce different authorization outcomes.

---

## 33. Owner's Rights

Owner-rights procedures can expose a carefully controlled operation without granting direct access to every underlying object.

This increases the importance of input validation, least privilege, code review, and ownership governance.

---

## 34. Least Privilege

Do not solve stored-procedure permission issues by granting broad administrative roles to application users.

Prefer a controlled procedure interface and a procedure-owner role with only the privileges required.

---

## 35. Procedure Ownership

Ownership affects modification, execution behavior, deployment, security, and incident recovery.

Production procedures should have intentional ownership. Avoid personal-user ownership for critical automation where possible.

---

## 36. Procedure Versioning

Treat stored procedures as code.

Maintain source control, code review, deployment history, rollback plans, testing, and documentation.

Do not rely on Snowflake as the only location containing production procedure source.

---

## 37. CREATE OR REPLACE Considerations

CREATE OR REPLACE PROCEDURE is convenient during development.

In production, understand the effect of replacing objects on grants, ownership, dependencies, active workflows, and rollback.

---

## 38. Procedures and Tasks

A Task can call a stored procedure.

```text
Schedule
   |
   v
Task
   |
   v
CALL procedure
   |
   v
Validation
   |
   v
MERGE
   |
   v
Audit
```

This separates scheduling from processing logic.

---

## 39. Task Calling a Procedure

```sql
CREATE OR REPLACE TASK snowflake_tutorial.raw.customer_processing_task
    WAREHOUSE = tutorial_wh
    SCHEDULE = '10 MINUTE'
AS
CALL snowflake_tutorial.raw.process_customers();
```

Before enabling the Task, test the procedure independently and validate permissions, retry behavior, failure reporting, and runtime.

---

## 40. Streams + Tasks + Procedures

```text
Source
  |
  v
Stream
  |
  v
Task
  |
  v
Stored Procedure
  |
  +---- Validate
  |
  +---- Normalize
  |
  +---- MERGE
  |
  +---- Audit
  |
  v
Target
```

Use this architecture when procedural complexity justifies it.

---

## 41. Procedure Observability

Capture procedure name, run ID, batch ID, start/end time, status, rows processed, query IDs, and error messages.

This makes procedures operable during incidents.

---

## 42. Query IDs

Query IDs are valuable for troubleshooting execution time, Query Profile, bytes scanned, errors, warehouse usage, and queueing.

A procedure executing important SQL should make it possible to correlate operational work with Snowflake query history.

---

## 43. Procedure Audit Pattern

```text
Procedure starts
      |
      v
Insert RUNNING audit record
      |
      v
Execute work
      |
      +---- Success → Update SUCCESS
      |
      +---- Failure → Update FAILED → Preserve error
```

This provides a durable execution history when designed with the transaction model.

---

## 44. Do Not Confuse Audit Logging with Transactions

If a transaction rolls back everything, including its audit record, no audit record may remain after failure.

Audit and transactional strategies should therefore be designed together.

External monitoring, query history, event mechanisms, or separate logging patterns may also be appropriate.

---

## 45. Procedure Performance

Stored procedures do not automatically make SQL faster.

Investigate underlying SQL, Query Profile, warehouse behavior, pruning, join strategy, spilling, queueing, and concurrency.

Do not treat the procedure itself as a performance optimization.

---

## 46. Avoid Excessive Procedural Complexity

Very large stored procedures become difficult to test, debug, review, deploy, and recover.

Prefer clear boundaries: validation, orchestration, set-based SQL, and audit.

Keep large transformations declarative where possible.

---

## 47. Metadata-Driven Administration

Stored procedures can be useful for controlled grants, validation, object health checks, maintenance workflows, and metadata collection.

Administrative procedures require especially careful privilege design.

---

## 48. Procedure Input Safety

Validate NULLs, empty values, allowed ranges, operation types, object names, date windows, and batch IDs.

Use allowlists where applicable and reject unexpected operations.

---

## 49. Time-Window Parameters

Recovery procedures may accept START_TIME and END_TIME.

Validate that both are present, START_TIME is earlier than END_TIME, and the requested window is not unexpectedly large.

This helps prevent accidental full-history processing.

---

## 50. Dangerous Procedure Design

Avoid generic procedures that accept unrestricted table names and WHERE clauses from arbitrary callers.

This creates security risk, operational risk, poor auditability, and accidental deletion risk.

Prefer narrow, purpose-built interfaces.

---

## 51. Production Deployment Checklist

Before deploying a stored procedure:

- Purpose documented
- Inputs documented
- Return contract documented
- SQL validated
- Error handling tested
- Transaction behavior tested
- Retry behavior tested
- Idempotency understood
- Security model selected
- Owner role reviewed
- Caller privileges reviewed
- Dynamic SQL reviewed
- Input validation implemented
- Audit strategy implemented
- Query observability available
- Task integration tested
- Failure recovery tested
- Source controlled
- Rollback plan documented

---

## 52. Troubleshooting — Procedure Fails Immediately

Check procedure existence, signature, caller access, database/schema access, parameter types, compilation, and referenced objects.

Capture the exact Snowflake error before changing anything.

---

## 53. Troubleshooting — Works for One User but Not Another

Likely causes include role differences, caller-rights behavior, database/schema privileges, object privileges, warehouse privileges, and session context.

Compare execution context rather than immediately granting broad roles.

---

## 54. Troubleshooting — Procedure Is Slow

Determine which internal SQL operation is slow.

Use query history and Query Profile.

Investigate warehouse queueing, large scans, poor pruning, join explosion, spilling, large MERGE operations, metadata operations, and concurrency.

Optimize the underlying operation.

---

## 55. Troubleshooting — Procedure Says Success but Data Is Wrong

Check procedure logic, input parameters, source data, processing window, MERGE conditions, row counts, audit records, query IDs, and target reconciliation.

A successful return value does not guarantee business correctness.

---

## 56. Troubleshooting — Procedure Partially Completed

Determine which statements committed, which rolled back, what transaction boundaries were used, whether processing state advanced, and whether retry is safe.

Do not blindly rerun until idempotency and partial state are understood.

---

## 57. Troubleshooting — Dynamic SQL Failure

Capture the generated SQL where safe.

Check identifier quoting, object existence, parameter binding, SQL syntax, caller/owner permissions, and unexpected input.

Never log secrets or sensitive values merely to troubleshoot dynamic SQL.

---

## 58. Troubleshooting — Task Calling Procedure Fails

Separate the layers:

```text
Task
 |
 v
CALL
 |
 v
Procedure
 |
 v
SQL
```

Check whether the Task ran, CALL executed, procedure started, which internal statement failed, the relevant query ID, warehouse health, and privileges.

---

## 59. Production Recovery Runbook

When a production procedure fails:

1. Capture procedure name.
2. Capture invocation parameters.
3. Capture timestamp.
4. Capture Task name if applicable.
5. Capture query ID.
6. Capture exact error.
7. Identify the failed processing stage.
8. Determine transaction state.
9. Determine whether any DML committed.
10. Determine whether processing state/watermark advanced.
11. Preserve source/staging/CDC state.
12. Determine the affected batch/window.
13. Check permissions and recent deployments.
14. Check underlying query performance if relevant.
15. Correct the root cause.
16. Test with a bounded dataset.
17. Determine whether retry is safe.
18. Replay using the normal procedure where possible.
19. Reconcile target data.
20. Confirm normal processing has resumed.

---

## 60. Hands-On Lab

### Objective

Build a reusable stored procedure around the Chapter 22 customer MERGE.

### Step 1 — Create audit table

```sql
CREATE OR REPLACE TABLE snowflake_tutorial.raw.customer_proc_audit (
    run_id          VARCHAR,
    started_at      TIMESTAMP_NTZ,
    completed_at    TIMESTAMP_NTZ,
    status          VARCHAR,
    message         VARCHAR
);
```

### Step 2 — Create procedure

```sql
CREATE OR REPLACE PROCEDURE snowflake_tutorial.raw.run_customer_merge()
RETURNS VARCHAR
LANGUAGE SQL
AS
$$
DECLARE
    run_id VARCHAR;
BEGIN

    run_id := UUID_STRING();

    INSERT INTO snowflake_tutorial.raw.customer_proc_audit
    (
        run_id,
        started_at,
        status
    )
    VALUES
    (
        :run_id,
        CURRENT_TIMESTAMP(),
        'RUNNING'
    );

    MERGE INTO snowflake_tutorial.raw.customer_target t
    USING (
        SELECT *
        FROM snowflake_tutorial.raw.customer_stage
        QUALIFY ROW_NUMBER() OVER (
            PARTITION BY customer_id
            ORDER BY updated_at DESC
        ) = 1
    ) s
       ON t.customer_id = s.customer_id

    WHEN MATCHED
         AND s.updated_at > t.updated_at
    THEN UPDATE SET
        t.customer_name = s.customer_name,
        t.email = s.email,
        t.status = s.status,
        t.updated_at = s.updated_at

    WHEN NOT MATCHED
    THEN INSERT
    (
        customer_id,
        customer_name,
        email,
        status,
        updated_at
    )
    VALUES
    (
        s.customer_id,
        s.customer_name,
        s.email,
        s.status,
        s.updated_at
    );

    UPDATE snowflake_tutorial.raw.customer_proc_audit
    SET
        completed_at = CURRENT_TIMESTAMP(),
        status = 'SUCCESS',
        message = 'MERGE completed'
    WHERE run_id = :run_id;

    RETURN 'SUCCESS: ' || run_id;

END;
$$;
```

### Step 3 — Execute

```sql
CALL snowflake_tutorial.raw.run_customer_merge();
```

### Step 4 — Validate target

```sql
SELECT *
FROM snowflake_tutorial.raw.customer_target
ORDER BY customer_id;
```

### Step 5 — Validate audit

```sql
SELECT *
FROM snowflake_tutorial.raw.customer_proc_audit
ORDER BY started_at DESC;
```

### Step 6 — Test replay

Run the procedure again:

```sql
CALL snowflake_tutorial.raw.run_customer_merge();
```

Then validate duplicate keys:

```sql
SELECT
    customer_id,
    COUNT(*)
FROM snowflake_tutorial.raw.customer_target
GROUP BY customer_id
HAVING COUNT(*) > 1;
```

Expected: no duplicate business keys.

### Step 7 — Review procedure

```sql
SHOW PROCEDURES
IN SCHEMA snowflake_tutorial.raw;
```

Inspect the procedure definition and security configuration according to your environment.

---

## 61. Acceptance Criteria

The chapter is complete when you can:

- explain when to use stored procedures
- distinguish procedures from UDFs
- create a SQL stored procedure
- call a procedure
- pass parameters
- declare variables
- use query results in procedural logic
- implement conditions
- explain appropriate loop usage
- package multi-step pipeline logic
- validate inputs
- implement exception handling
- reason about transaction boundaries
- design retry-safe procedures
- implement batch control
- use dynamic SQL appropriately
- understand identifier vs value binding
- mitigate dynamic SQL injection risks
- explain caller-rights and owner-rights concepts
- apply least privilege
- manage procedure ownership
- integrate procedures with Tasks
- integrate Streams + Tasks + Procedures
- design audit logging
- troubleshoot internal SQL performance
- diagnose partial completion
- recover failed production procedure runs
- validate replay and reconciliation

---

## Key Takeaways

Stored procedures provide a procedural layer for Snowflake workflows.

They are most valuable when the workflow genuinely requires multiple steps, conditional logic, transactions, dynamic behavior, and operational coordination.

Do not replace efficient set-based SQL with unnecessary procedural code.

For production procedures, design around correctness, idempotency, security, transactions, observability, and recovery.

A stored procedure is production-ready when engineers can answer:

- Who can execute it?
- What privileges does it use?
- What happens when it fails?
- What committed?
- Can it be retried?
- How do we find the failed query?
- How do we reconcile the result?

The next chapter is **Chapter 24 — User-Defined Functions — SQL/Python/Java**.
