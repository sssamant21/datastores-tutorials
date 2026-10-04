# 06 — Table Types: Permanent, Transient & Temporary

**Status:** Canonical  
**Part:** 2 — Data Objects & SQL  
**Goal:** Understand Snowflake permanent, transient, and temporary tables; their lifecycle, Time Travel, Fail-safe, recovery implications, cost tradeoffs, and production selection.

## 1. Why table type matters
Snowflake supports three primary table lifecycles: **permanent**, **transient**, and **temporary**. Choosing among them is not merely syntax; it changes persistence and data-protection behavior.

```text
Table type
  ├─ Permanent  → durable business data
  ├─ Transient  → durable across sessions, recreatable working data
  └─ Temporary  → session-scoped scratch data
```

## 2. Permanent tables
A normal `CREATE TABLE` creates a permanent table.

```sql
CREATE TABLE CUSTOMER (
    CUSTOMER_ID NUMBER,
    CUSTOMER_NAME VARCHAR,
    CREATED_AT TIMESTAMP_LTZ DEFAULT CURRENT_TIMESTAMP()
);
```

Use permanent tables for data whose durability and recovery options matter: curated business data, facts/dimensions, authoritative application data, audit data, and other production datasets.

## 3. Permanent-table lifecycle
Conceptually:

```text
Active data
   ↓
Historical versions available through Time Travel
   ↓
Object/rows changed or dropped
   ↓
Time Travel retention window
   ↓
Fail-safe period
   ↓
Expiration
```

Time Travel and Fail-safe solve different problems.

## 4. Time Travel
Time Travel lets authorized users query or restore historical data within the configured retention period.

```sql
SELECT *
FROM CUSTOMER
AT (TIMESTAMP => DATEADD('minute', -10, CURRENT_TIMESTAMP()));
```

A statement-based investigation can use a known query ID:

```sql
SELECT *
FROM CUSTOMER
BEFORE (STATEMENT => '<query-id>');
```

Time Travel is covered deeply in Tutorial 56.

## 5. Inspect retention
```sql
SHOW TABLES LIKE 'CUSTOMER';

SELECT
    TABLE_NAME,
    RETENTION_TIME
FROM INFORMATION_SCHEMA.TABLES
WHERE TABLE_NAME = 'CUSTOMER';
```

Set retention deliberately:

```sql
ALTER TABLE CUSTOMER
SET DATA_RETENTION_TIME_IN_DAYS = 1;
```

Do not change retention globally just to reduce storage without understanding recovery requirements.

## 6. Fail-safe
Fail-safe is an additional Snowflake-managed recovery period for permanent data after Time Travel has ended. It is intended for exceptional recovery and is operated by Snowflake.

Fail-safe is **not**:
- a user-queryable backup system,
- a replacement for Time Travel,
- a substitute for replication/DR,
- or an application recovery workflow.

## 7. Transient tables
Create a transient table explicitly:

```sql
CREATE TRANSIENT TABLE STAGING_CUSTOMER (
    CUSTOMER_ID NUMBER,
    CUSTOMER_NAME VARCHAR,
    SOURCE_FILE VARCHAR
);
```

Transient tables persist across sessions until dropped. They are appropriate for data that must survive session boundaries but can be recreated from another reliable source.

## 8. Good transient use cases
Typical candidates include staging data, ETL/ELT working tables, intermediate transformations, reproducible derived datasets, and pipeline work areas.

```text
Reliable source
    ↓
Transient staging
    ↓
Transform / validate
    ↓
Permanent curated data
```

## 9. Transient is not temporary
A transient table does **not** disappear when the session ends.

```text
TRANSIENT
Session A creates table
Session A ends
Session B connects
Table still exists
```

It remains until explicitly dropped or otherwise removed.

## 10. Transient Time Travel
Transient tables support limited Time Travel retention. For example:

```sql
CREATE TRANSIENT TABLE STAGING_ORDER (
    ORDER_ID NUMBER,
    PAYLOAD VARIANT
)
DATA_RETENTION_TIME_IN_DAYS = 1;
```

Keep the retention design aligned with the fact that transient data is expected to be reproducible.

## 11. Transient tables and Fail-safe
Transient tables do **not** have Fail-safe. That is a key recovery tradeoff.

Do not classify critical unrecoverable data as transient merely to reduce historical-storage cost.

## 12. Temporary tables
Temporary tables are session-scoped.

```sql
CREATE TEMPORARY TABLE TEMP_CUSTOMER (
    CUSTOMER_ID NUMBER,
    CUSTOMER_NAME VARCHAR
);
```

The shorter form is also valid:

```sql
CREATE TEMP TABLE TEMP_CUSTOMER (
    CUSTOMER_ID NUMBER
);
```

## 13. Temporary-table lifecycle
```text
Session starts
    ↓
CREATE TEMP TABLE
    ↓
Use scratch/intermediate data
    ↓
Session ends
    ↓
Temporary table removed
```

Temporary tables are useful for session-local calculations and intermediate work.

## 14. Session scope
A temporary table is visible only within the session in which it was created. It should not be used as a durable handoff mechanism between independent jobs or sessions.

## 15. Connection-pool warning
Application connection pools can make temporary-table behavior surprising:

```text
Request 1 → Connection / Session A → creates TMP_CUSTOMER
Request 2 → Connection / Session B → TMP_CUSTOMER not found
```

If an application relies on temporary objects, understand whether it is guaranteed to reuse the same Snowflake session.

## 16. Name conflicts and shadowing
Temporary objects can use names that overlap with other objects in the same namespace, which can create confusing resolution behavior. Prefer clear names such as `TMP_CUSTOMER` and avoid ambiguous production naming.

## 17. Comparison
| Capability | Permanent | Transient | Temporary |
|---|---|---|---|
| Persists across sessions | Yes | Yes | No |
| Session scoped | No | No | Yes |
| Time Travel | Yes | Limited | Limited |
| Fail-safe | Yes | No | No |
| Typical use | Durable business data | Re-creatable staging/work data | Session scratch data |

## 18. Decision model
Ask:

```text
Must data survive the session?
   ├─ No → Temporary may fit
   └─ Yes
       ↓
Is Fail-safe / stronger recovery protection required?
   ├─ Yes → Permanent
   └─ No
       ↓
Can data be reliably recreated?
   ├─ Yes → Transient may fit
   └─ No → Permanent
```

## 19. Production architecture pattern
A practical architecture is:

```text
Source
  ↓
RAW              Permanent
  ↓
STAGING          Transient
  ↓
CURATED          Permanent
  ↓
Analytics / Apps

Inside a transformation session:
TMP_*            Temporary
```

The exact design depends on recovery requirements, not merely layer names.

## 20. Transient schemas
A schema can be transient:

```sql
CREATE TRANSIENT SCHEMA STAGING;
```

Tables created in a transient schema are transient by default. This can be useful for a deliberately re-creatable work area.

## 21. Transient databases
A database can also be transient:

```sql
CREATE TRANSIENT DATABASE ETL_WORK;
```

This is a broad recovery decision. Do not make an entire database transient without reviewing every dataset that will live inside it.

## 22. Inspect table types
```sql
SHOW TABLES;
```

Metadata inspection:

```sql
SELECT
    TABLE_CATALOG,
    TABLE_SCHEMA,
    TABLE_NAME,
    TABLE_TYPE,
    IS_TRANSIENT,
    RETENTION_TIME
FROM INFORMATION_SCHEMA.TABLES
ORDER BY TABLE_SCHEMA, TABLE_NAME;
```

## 23. Operational audit
When auditing transient objects, ask:
- Is the table truly re-creatable?
- Where is the authoritative source?
- How long would a rebuild take?
- Is the source retained long enough?
- Would loss interrupt a critical production service?
- Is the documented recovery procedure tested?

## 24. Anti-pattern: transient everywhere
Reducing Fail-safe storage can lower cost, but converting every table to transient weakens recovery protection. Cost optimization must not silently become a recovery-risk decision.

## 25. Anti-pattern: critical data only in temporary tables
Temporary tables disappear with the session. Do not use them as the sole copy of data that another job, user, or later session requires.

## 26. Anti-pattern: treating Fail-safe as backup
Fail-safe is not a normal backup interface. Production recovery should be designed around Time Travel, source replay, cloning, replication/DR, and documented runbooks as appropriate.

## 27. Storage-cost consideration
Historical data retained for Time Travel and Fail-safe can contribute to storage. Optimize retention based on business and recovery objectives, not just the smallest possible bill.

## 28. Hands-on lab
```sql
CREATE DATABASE IF NOT EXISTS SNOWFLAKE_TUTORIAL;
CREATE SCHEMA IF NOT EXISTS SNOWFLAKE_TUTORIAL.TABLE_TYPES;

USE DATABASE SNOWFLAKE_TUTORIAL;
USE SCHEMA TABLE_TYPES;

CREATE TABLE PERMANENT_CUSTOMER (
    CUSTOMER_ID NUMBER,
    CUSTOMER_NAME VARCHAR
);

CREATE TRANSIENT TABLE TRANSIENT_CUSTOMER (
    CUSTOMER_ID NUMBER,
    CUSTOMER_NAME VARCHAR
);

CREATE TEMP TABLE TEMP_CUSTOMER (
    CUSTOMER_ID NUMBER,
    CUSTOMER_NAME VARCHAR
);
```

Load each table:

```sql
INSERT INTO PERMANENT_CUSTOMER VALUES (1, 'Alice');
INSERT INTO TRANSIENT_CUSTOMER VALUES (2, 'Bob');
INSERT INTO TEMP_CUSTOMER VALUES (3, 'Carol');

SELECT * FROM PERMANENT_CUSTOMER;
SELECT * FROM TRANSIENT_CUSTOMER;
SELECT * FROM TEMP_CUSTOMER;
```

## 29. Inspect metadata
```sql
SHOW TABLES IN SCHEMA SNOWFLAKE_TUTORIAL.TABLE_TYPES;

SELECT
    TABLE_NAME,
    TABLE_TYPE,
    IS_TRANSIENT,
    RETENTION_TIME
FROM SNOWFLAKE_TUTORIAL.INFORMATION_SCHEMA.TABLES
WHERE TABLE_SCHEMA = 'TABLE_TYPES'
ORDER BY TABLE_NAME;
```

## 30. Test session behavior
End the session and reconnect. Then query:

```sql
SELECT * FROM PERMANENT_CUSTOMER;
SELECT * FROM TRANSIENT_CUSTOMER;
SELECT * FROM TEMP_CUSTOMER;
```

Permanent and transient tables remain. The temporary table from the previous session does not.

## 31. Troubleshooting “temporary table does not exist”
If `TMP_CUSTOMER` suddenly cannot be found, check session identity and context:

```sql
SELECT
    CURRENT_SESSION(),
    CURRENT_DATABASE(),
    CURRENT_SCHEMA(),
    CURRENT_ROLE();
```

Ask whether the connection pool switched sessions, the client reconnected, a timeout occurred, or the workload is using a different connection.

## 32. Recovery scenario
If a staging table is dropped unexpectedly:
1. Determine whether it was permanent, transient, or temporary.
2. Determine the configured Time Travel retention.
3. Capture the drop time/query ID.
4. Determine whether Time Travel recovery is available.
5. Do not assume Fail-safe exists for transient or temporary data.
6. If necessary, identify the authoritative source and rebuild path.

## 33. Production design checklist
```text
[ ] Business criticality understood
[ ] Session persistence requirement understood
[ ] Source/rebuild path documented
[ ] Time Travel requirement defined
[ ] Fail-safe requirement understood
[ ] Retention configured intentionally
[ ] Connection/session behavior understood for temp tables
[ ] Cost tradeoff reviewed
[ ] Recovery procedure tested
```

## 34. Cleanup
```sql
DROP TABLE IF EXISTS PERMANENT_CUSTOMER;
DROP TABLE IF EXISTS TRANSIENT_CUSTOMER;
DROP TABLE IF EXISTS TEMP_CUSTOMER;
```

If no other tutorial lab uses the database:

```sql
DROP DATABASE IF EXISTS SNOWFLAKE_TUTORIAL;
```

## 35. Production takeaways
**Permanent** = durable across sessions + Time Travel + Fail-safe; use for critical and authoritative data.

**Transient** = durable across sessions + limited Time Travel + no Fail-safe; use for staging/intermediate data that can be reliably rebuilt.

**Temporary** = session-scoped + limited Time Travel + no Fail-safe; use for scratch/intermediate work within one session.

Table type is a **recovery, lifecycle, architecture, and cost decision**, not just a `CREATE TABLE` option.

## Technical references
- Snowflake table considerations: https://docs.snowflake.com/en/user-guide/tables-considerations
- Temporary and transient tables: https://docs.snowflake.com/en/user-guide/tables-temp-transient
- Time Travel: https://docs.snowflake.com/en/user-guide/data-time-travel
- Fail-safe: https://docs.snowflake.com/en/user-guide/data-failsafe
- CREATE TABLE: https://docs.snowflake.com/en/sql-reference/sql/create-table
