# 24 — User-Defined Functions — SQL/Python/Java

## Overview

Snowflake User-Defined Functions (UDFs) allow reusable custom logic to be called directly from SQL.

Conceptually:

```text
Input
  |
  v
UDF
  |
  v
Custom Logic
  |
  v
Return Value
```

Example:

```sql
SELECT my_function(column_name)
FROM table_name;
```

UDFs are useful for reusable calculations, data normalization, parsing, transformations, business rules, string processing, semi-structured data processing, custom Python logic, and custom Java logic.

The central design principle is: use the simplest implementation that solves the requirement. Do not automatically use Python or Java when SQL can solve the problem clearly.

---

## 1. UDF vs Stored Procedure

Chapter 23 covered Stored Procedures.

| Area | UDF | Stored Procedure |
|---|---|---|
| Main purpose | Calculate/transform values | Execute workflows |
| Called from SELECT | Yes | Normally called with CALL |
| Reusable expression | Yes | Not primary purpose |
| Multi-step orchestration | Not primary purpose | Yes |
| Administrative operations | No | Common use case |
| Row transformation | Common | Not primary purpose |

Think of a UDF as reusable computation and a Stored Procedure as a reusable operation/workflow.

---

## 2. Built-In Functions vs UDFs

Before creating a UDF, determine whether Snowflake already provides the functionality.

Prefer:

```sql
UPPER(customer_name)
```

instead of creating a custom function that simply duplicates UPPER.

Built-in functions are generally easier to understand, maintain, optimize, document, and recognize.

---

## 3. Scalar UDF

A scalar UDF returns one value for each invocation.

Scalar UDFs can be used in SELECT statements and other SQL expressions according to query semantics.

---

## 4. Basic SQL UDF

```sql
CREATE OR REPLACE FUNCTION snowflake_tutorial.raw.add_tax(
    amount NUMBER,
    tax_rate NUMBER
)
RETURNS NUMBER
LANGUAGE SQL
AS
$$
    amount + (amount * tax_rate)
$$;
```

Call:

```sql
SELECT snowflake_tutorial.raw.add_tax(100, 0.08);
```

Expected result: 108.

---

## 5. Use SQL UDF with Table Data

```sql
CREATE OR REPLACE TABLE snowflake_tutorial.raw.orders_udf_lab (
    order_id NUMBER,
    amount   NUMBER(12,2)
);

INSERT INTO snowflake_tutorial.raw.orders_udf_lab
VALUES
    (1, 100.00),
    (2, 200.00),
    (3, 300.00);

SELECT
    order_id,
    amount,
    snowflake_tutorial.raw.add_tax(amount, 0.08) AS amount_with_tax
FROM snowflake_tutorial.raw.orders_udf_lab;
```

---

## 6. SQL UDF for String Normalization

```sql
CREATE OR REPLACE FUNCTION snowflake_tutorial.raw.normalize_email(
    email VARCHAR
)
RETURNS VARCHAR
LANGUAGE SQL
AS
$$
    LOWER(TRIM(email))
$$;
```

```sql
SELECT snowflake_tutorial.raw.normalize_email(
    '  USER@EXAMPLE.COM  '
);
```

Expected result: user@example.com.

---

## 7. Why SQL UDFs Are Often the Best Starting Point

If logic can be expressed clearly in SQL, start with SQL.

SQL UDFs avoid introducing an additional runtime language unnecessarily.

---

## 8. NULL Handling

Production UDFs must define expected behavior for NULL inputs.

Determine whether a NULL input should return NULL, a default value, or an error according to the business rule.

---

## 9. Explicit NULL Handling

```sql
CREATE OR REPLACE FUNCTION snowflake_tutorial.raw.normalize_email_safe(
    email VARCHAR
)
RETURNS VARCHAR
LANGUAGE SQL
AS
$$
    CASE
        WHEN email IS NULL THEN NULL
        ELSE LOWER(TRIM(email))
    END
$$;
```

---

## 10. Avoid Hidden Business Rules

Business-critical UDFs should have clear naming, documentation, tests, ownership, and source control.

Do not hide important business logic in poorly documented functions.

---

## 11. Deterministic Logic

A function is conceptually deterministic when the same input produces the same output.

Deterministic logic is easier to test, reason about, replay, and validate.

---

## 12. Non-Deterministic Logic

Logic depending on current time, random values, external state, or changing external services may produce different results for the same input.

Use such behavior only when required.

---

# Part 2 — Python UDFs

## 13. Why Python UDFs?

Python UDFs are useful when transformation logic is difficult or impractical to express in SQL.

Potential use cases include advanced text processing, custom parsing, specialized algorithms, reusable Python libraries, and complex transformations.

---

## 14. Basic Python UDF

```sql
CREATE OR REPLACE FUNCTION snowflake_tutorial.raw.python_upper(
    input_string VARCHAR
)
RETURNS VARCHAR
LANGUAGE PYTHON
RUNTIME_VERSION = '3.12'
HANDLER = 'python_upper'
AS
$$
def python_upper(input_string):
    if input_string is None:
        return None

    return input_string.upper()
$$;
```

```sql
SELECT snowflake_tutorial.raw.python_upper('snowflake');
```

Expected: SNOWFLAKE.

Runtime versions evolve over time. Always verify currently supported Python runtimes before production deployment.

---

## 15. Python Handler

The HANDLER identifies the Python function Snowflake invokes.

The handler signature must align with the UDF definition.

---

## 16. Python Type Mapping

Snowflake SQL values are mapped to Python values.

Production code should understand supported Snowflake-to-Python type mappings, especially NUMBER, FLOAT, DATE, TIME, TIMESTAMP, VARIANT, ARRAY, OBJECT, and NULL.

---

## 17. Python NULL Handling

```python
def normalize_name(value):
    if value is None:
        return None

    return value.strip().lower()
```

NULL handling should be tested explicitly.

---

## 18. Python UDF Example — Normalize Name

```sql
CREATE OR REPLACE FUNCTION snowflake_tutorial.raw.normalize_name_py(
    value VARCHAR
)
RETURNS VARCHAR
LANGUAGE PYTHON
RUNTIME_VERSION = '3.12'
HANDLER = 'normalize_name'
AS
$$
def normalize_name(value):
    if value is None:
        return None

    return value.strip().lower()
$$;
```

```sql
SELECT snowflake_tutorial.raw.normalize_name_py(
    '  SNOWFLAKE ENGINEER  '
);
```

---

## 19. Python Packages

Python UDFs can use supported packages available through Snowflake's package mechanisms.

Before using a package, verify package availability, supported version, security requirements, licensing requirements, runtime compatibility, and dependency behavior.

Do not assume every public Python package is automatically available.

---

## 20. Package Versioning

A production function should have a reproducible environment.

Track Python runtime, package, package version, function source, and deployment version.

---

## 21. External Dependencies

Some workloads may require code or packages staged outside the inline handler.

Keep external dependencies controlled and versioned. Do not overwrite shared dependency artifacts casually.

---

## 22. Python UDF Error Handling

```python
def safe_divide(value, divisor):
    if value is None or divisor is None:
        return None

    if divisor == 0:
        return None

    return value / divisor
```

Whether an error should return NULL, return a default, or raise an exception is a business decision.

Do not hide genuine data-quality problems by converting every exception into NULL.

---

## 23. Bad Error Handling

Avoid broad patterns such as:

```python
try:
    ...
except:
    return None
```

for every error.

This can turn a real production defect into a silent NULL.

Catch only errors you understand and intentionally handle.

---

## 24. Python UDF Performance

A Python UDF introduces additional processing compared with straightforward native SQL.

Before implementing one, ask whether the requirement can be expressed efficiently with native Snowflake SQL.

---

## 25. Avoid Excessive Per-Row Complexity

At very large row counts, small per-row overhead can become important.

Evaluate row volume, transformation complexity, warehouse usage, query duration, and scalability using representative data.

---

# Part 3 — Java UDFs

## 26. Why Java UDFs?

Java UDFs can be useful when existing Java logic or libraries must be reused, organizational standards favor Java, or the logic is better implemented in Java.

---

## 27. Basic Java UDF Concept

A Java UDF definition identifies input SQL types, return SQL type, runtime, handler, and Java implementation.

```sql
CREATE OR REPLACE FUNCTION ...
RETURNS VARCHAR
LANGUAGE JAVA
RUNTIME_VERSION = '<supported-version>'
HANDLER = 'ClassName.methodName'
AS
$$
    // Java source
$$;
```

Supported runtime versions change over time. Verify current Snowflake documentation before selecting a production runtime.

---

## 28. Java Handler Design

Conceptually:

```java
public static String normalize(String value) {
    if (value == null) {
        return null;
    }

    return value.trim().toLowerCase();
}
```

The SQL definition must correctly map inputs and outputs to supported Java types.

---

## 29. Java Dependencies

Treat Java dependencies as production artifacts.

Source, runtime, libraries, and versions should all be source controlled, reviewed, tested, and reproducible.

---

## 30. SQL vs Python vs Java

Use the simplest appropriate implementation.

| Requirement | Preferred Starting Point |
|---|---|
| Simple SQL calculation | SQL |
| SQL-native string/date logic | SQL |
| Complex Python transformation | Python |
| Existing Python library | Python |
| Existing Java implementation | Java |
| Java-specific library | Java |

---

# Part 4 — Table Functions

## 31. Scalar vs Table Function

A scalar UDF returns one value. A table function returns rows.

Use a table function when the natural result is multiple columns or rows.

---

## 32. UDTF Concept

A User-Defined Table Function is commonly abbreviated UDTF.

It produces table-shaped output and can return zero, one, or many rows according to its implementation.

---

## 33. Do Not Force Table Logic into Scalar Functions

If a transformation naturally produces multiple rows, do not create complicated encoded strings merely to return them from a scalar UDF.

Choose the correct function type.

---

# Part 5 — Security

## 34. UDF Security

Production governance should address ownership, USAGE privileges, dependencies, external access, secrets, code review, deployment, and dependency provenance.

Treat executable database code with the same care as application code.

---

## 35. Least Privilege

Do not broadly grant function access without understanding who needs it.

Grant only the database, schema, and function privileges required by the workload.

---

## 36. Ownership

Production UDF ownership should be intentional.

Avoid relying on a personal engineer's role for critical functions. Prefer controlled deployment/ownership roles.

---

## 37. Sensitive Data

Be careful when UDFs process PII, PHI, credentials, tokens, secrets, or financial information.

Do not print sensitive values, expose them in errors, store them unnecessarily, or send them externally without approval.

---

## 38. Secrets

Do not hard-code secrets in function source.

Secrets should use Snowflake-supported secure integration mechanisms where external access is required.

Chapter 32 covers Secrets and External Access Integrations in depth.

---

## 39. External Network Access

A normal UDF should not assume arbitrary external network access is automatically available.

External access requires specific Snowflake configuration and security controls.

This is covered later in the security section.

---

# Part 6 — Performance

## 40. UDF Performance Principles

Before deploying a UDF into a large workload, understand how often it is called, how many rows it processes, what each invocation does, and whether native SQL can replace it.

---

## 41. Filter Before Expensive UDF Processing

When query semantics allow it, reduce the dataset before applying expensive custom processing.

Avoid intentionally applying expensive UDF logic to irrelevant rows.

---

## 42. Avoid Repeated Calls

Avoid unnecessarily repeating the same expensive UDF expression many times in a query.

Design query structures clearly and calculate reusable expressions appropriately.

---

## 43. Query Profile

When a query using UDFs is slow, inspect the full Query Profile.

Do not assume the UDF is the problem without examining scans, joins, function processing, spilling, queueing, and the rest of the query plan.

---

## 44. Warehouse Sizing

Increasing warehouse size is not the first response to every slow UDF workload.

First investigate row counts, function complexity, native SQL alternatives, filtering, joins, scans, concurrency, and Query Profile.

---

# Part 7 — Testing

## 45. Unit-Test Function Logic

Test normal inputs and edge cases such as NULL, empty strings, zero, negative values, large values, Unicode, and unexpected formatting.

Test invalid inputs where relevant.

---

## 46. SQL UDF Test Matrix

For an email-normalization UDF:

| Input | Expected |
|---|---|
| USER@EXAMPLE.COM | user@example.com |
| user@example.com with surrounding spaces | user@example.com |
| NULL | NULL |
| empty string | defined business behavior |

Document expected behavior.

---

## 47. Python UDF Test Matrix

Test NULL, normal input, boundary values, malformed input, unexpected encoding, and large input.

Do not test only the happy path.

---

## 48. Regression Testing

If function logic changes, rerun known test cases.

A small UDF change can affect many downstream queries.

---

## 49. Dependency Testing

Before replacing a widely used UDF, determine which views, Tasks, reports, pipelines, and queries depend on it.

Treat shared UDFs as APIs.

---

# Part 8 — Deployment

## 50. Source Control

Store function definitions in source control.

Recommended lifecycle:

```text
Develop
   |
   v
Review
   |
   v
Test
   |
   v
Deploy
   |
   v
Validate
   |
   v
Monitor
```

Do not make undocumented production-only function changes.

---

## 51. Versioning Strategy

For high-risk functions, consider explicit versions such as NORMALIZE_CUSTOMER_V1 and NORMALIZE_CUSTOMER_V2 to support controlled migration.

Alternatively, use deployment tooling that safely replaces tested function code.

---

## 52. Function Overloading

Snowflake can distinguish functions by signatures where supported.

When troubleshooting, identify the complete function signature rather than only the function name.

---

## 53. Deployment Validation

```sql
SHOW USER FUNCTIONS
IN SCHEMA snowflake_tutorial.raw;
```

Validate expected signature, language, return type, ownership, and deployment success, then execute known test cases.

---

# Part 9 — Troubleshooting

## 54. UDF Not Found

If Snowflake reports that a function does not exist or cannot be resolved, check database, schema, function name, argument count, argument types, role, and USAGE privileges.

A signature mismatch can appear similar to a missing function.

---

## 55. SQL UDF Returns Wrong Result

Check input data, NULL behavior, implicit conversions, business logic, edge cases, function version, and the calling query.

Test the function independently from the larger pipeline.

---

## 56. Python UDF Fails

Capture the exact error.

Investigate Python runtime, handler name, handler signature, package availability/version, type mapping, NULL input, code exceptions, and permissions.

---

## 57. Java UDF Fails

Check Java runtime, class name, method name, handler signature, SQL-to-Java type mapping, dependencies, compilation, and runtime exceptions.

Capture the original error before redeployment.

---

## 58. Package Not Available

Confirm the package mechanism, supported package/version, runtime compatibility, and security/dependency requirements.

Do not randomly change runtime and package versions until something works.

---

## 59. UDF Suddenly Fails After Deployment

Determine what changed: function source, runtime, package, package version, permissions, calling SQL, or input data.

Compare the current deployment with the last known-good version.

---

## 60. UDF Is Slow

Investigation order:

1. Query history.
2. Query Profile.
3. Row volume.
4. Function complexity.
5. Native SQL alternative.
6. Filtering.
7. Dependencies.
8. Warehouse/concurrency.

Do not assume compute is the root cause.

---

## 61. UDF Produces NULL Unexpectedly

Check input NULLs, explicit NULL logic, exceptions converted to NULL, type conversions, and malformed input.

A broad exception handler is a common reason genuine failures become silent NULLs.

---

## 62. Function Changed Downstream Results

Treat this as a data-correctness incident.

Determine deployment time, old/new versions, affected queries, affected tables, affected time window, and whether persisted data must be repaired.

If required, roll back, identify the affected window, replay, and reconcile.

---

# Part 10 — Production Runbook

## 63. Production UDF Incident Runbook

When a UDF-related production issue occurs:

1. Capture function name.
2. Capture full signature.
3. Capture language.
4. Capture query ID.
5. Capture exact error.
6. Capture deployment/version.
7. Identify last known-good version.
8. Identify affected workloads.
9. Check recent code changes.
10. Check runtime changes.
11. Check dependency changes.
12. Check permission changes.
13. Test the function independently.
14. Test representative failing input.
15. Check NULL/type behavior.
16. Check Query Profile if performance-related.
17. Determine affected data window.
18. Roll back or fix safely.
19. Replay affected processing if required.
20. Reconcile downstream data.
21. Monitor after recovery.

---

## 64. Production Best Practices

Use built-in functions where possible, SQL UDFs for straightforward SQL logic, Python/Java only when justified, explicit NULL behavior, stable contracts, deterministic logic where possible, source control, dependency versioning, least privilege, representative performance tests, unit/regression tests, deployment validation, operational ownership, and recovery procedures.

Avoid reimplementing built-ins, complex Python for simple SQL, broad exception handlers returning NULL, hard-coded secrets, uncontrolled dependencies, personal ownership for critical functions, untested runtime upgrades, undocumented production changes, and assuming small-scale tests predict billion-row performance.

---

# Part 11 — Hands-On Lab

## 65. Lab Objective

Create and test a SQL UDF, Python UDF, NULL handling, table-based invocation, performance comparison, and failure troubleshooting.

---

## 66. Create SQL UDF

```sql
CREATE OR REPLACE FUNCTION snowflake_tutorial.raw.clean_text_sql(
    input_value VARCHAR
)
RETURNS VARCHAR
LANGUAGE SQL
AS
$$
    CASE
        WHEN input_value IS NULL THEN NULL
        ELSE LOWER(TRIM(input_value))
    END
$$;
```

```sql
SELECT snowflake_tutorial.raw.clean_text_sql(
    '  SNOWFLAKE  '
);
```

Expected: snowflake.

---

## 67. Test NULL

```sql
SELECT snowflake_tutorial.raw.clean_text_sql(NULL);
```

Expected: NULL.

---

## 68. Create Python UDF

Use a currently supported Python runtime in your Snowflake account.

```sql
CREATE OR REPLACE FUNCTION snowflake_tutorial.raw.clean_text_python(
    input_value VARCHAR
)
RETURNS VARCHAR
LANGUAGE PYTHON
RUNTIME_VERSION = '3.12'
HANDLER = 'clean_text'
AS
$$
def clean_text(input_value):
    if input_value is None:
        return None

    return input_value.strip().lower()
$$;
```

```sql
SELECT snowflake_tutorial.raw.clean_text_python(
    '  SNOWFLAKE  '
);
```

---

## 69. Create Test Table

```sql
CREATE OR REPLACE TABLE snowflake_tutorial.raw.udf_test_data (
    id    NUMBER,
    value VARCHAR
);

INSERT INTO snowflake_tutorial.raw.udf_test_data
VALUES
    (1, '  ALPHA  '),
    (2, 'BETA'),
    (3, NULL),
    (4, ' Gamma ');
```

---

## 70. Compare Results

```sql
SELECT
    id,
    value,
    snowflake_tutorial.raw.clean_text_sql(value) AS sql_result,
    snowflake_tutorial.raw.clean_text_python(value) AS python_result
FROM snowflake_tutorial.raw.udf_test_data
ORDER BY id;
```

Validate that both implementations produce the intended business result.

---

## 71. Inspect Functions

```sql
SHOW USER FUNCTIONS
IN SCHEMA snowflake_tutorial.raw;
```

Review name, signature, return type, language, and owner.

---

## 72. Performance Exercise

Run the SQL and Python versions against representative test data and compare query history and Query Profile.

Do not draw production performance conclusions from a tiny lab dataset.

---

## 73. Failure Exercise

In a non-production environment, intentionally create or invoke a Python UDF with an invalid handler configuration.

Capture the exact error, query ID, function signature, runtime, and handler, then correct the function.

---

## 74. Cleanup

```sql
DROP FUNCTION IF EXISTS
snowflake_tutorial.raw.clean_text_sql(VARCHAR);

DROP FUNCTION IF EXISTS
snowflake_tutorial.raw.clean_text_python(VARCHAR);
```

Only clean up lab objects that are no longer needed.

---

## 75. Acceptance Criteria

The chapter is complete when you can:

- explain UDF use cases
- distinguish UDFs from Stored Procedures
- choose built-in functions before custom code
- create SQL scalar UDFs
- invoke UDFs against table data
- design explicit NULL handling
- explain deterministic behavior
- create Python UDFs
- understand Python handlers
- understand SQL/Python type mapping
- manage Python dependencies
- troubleshoot Python exceptions
- explain Java UDF architecture
- understand Java handlers
- choose SQL vs Python vs Java
- distinguish scalar functions from UDTFs
- apply UDF security controls
- protect sensitive data
- avoid hard-coded secrets
- understand external-access requirements
- evaluate UDF performance
- use Query Profile
- test edge cases
- perform regression testing
- source-control UDF definitions
- understand function signatures
- troubleshoot missing functions
- troubleshoot runtime/dependency failures
- investigate data-correctness incidents
- operate the UDF production runbook

---

## Key Takeaways

UDFs provide reusable computation inside Snowflake.

Choose implementation language intentionally: use SQL for clear native SQL logic, Python for justified Python-specific requirements, and Java for justified Java-specific requirements.

The most important design rule is: do not introduce a more complex runtime when native Snowflake SQL solves the requirement clearly and efficiently.

For production UDFs, always consider correctness, NULL behavior, type mapping, performance, dependencies, security, testing, versioning, and recovery.

Treat shared UDFs like application APIs because changing one function can affect many downstream pipelines and queries.

The next chapter is **Chapter 25 — External Functions & API Integrations**.
