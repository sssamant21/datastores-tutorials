# 41 — Search Optimization Service

## Overview

Snowflake's Search Optimization Service is designed to improve the performance of selected query patterns by maintaining additional search access structures for configured tables and columns.

It is particularly useful when a query needs to locate a relatively small number of rows in a large table.

A common example is:

```sql
SELECT *
FROM claims
WHERE claim_id = 'CLAIM-EXAMPLE-1001';
```

Suppose `CLAIMS` contains billions of rows and many terabytes of data.

Without an appropriate optimization, Snowflake may need to examine a significant amount of table data to find a very small result set.

Search Optimization can provide an alternative access path for supported predicates.

The important principle is:

> Search Optimization is workload-specific. It should be enabled because measured production queries justify it—not simply because a table is large.

A practical decision flow is:

```text
Slow Query
    |
    v
Query Profile / Query History
    |
    v
Large table scan?
    |
   Yes
    |
    v
Highly selective predicate?
    |
   Yes
    |
    v
Supported search pattern?
    |
   Yes
    |
    v
Evaluate Search Optimization
    |
    v
Measure performance + cost
```

This chapter covers Search Optimization fundamentals, search access paths, selective point lookups, equality predicates, IN predicates, supported search methods, column-level configuration, Search Optimization vs clustering, caching, materialized views and warehouse resizing, cost, storage overhead, maintenance overhead, monitoring, Query Profile validation, production decision frameworks, troubleshooting, incident investigation, and hands-on validation.

---

# Part 1 — The Problem Search Optimization Solves

## 1. Large Table, Tiny Result

Consider:

```text
Table size = 25 TB
Rows       = billions
```

A production application runs:

```sql
SELECT
    claim_id,
    patient_id,
    provider_id,
    service_date,
    status
FROM claims
WHERE claim_id = 'CLAIM-EXAMPLE-1001';
```

Expected result:

```text
1 row
```

But without an efficient access path, a large amount of table data may still need consideration.

## 2. Selectivity

This is a highly selective query.

```text
Billions of rows
      |
      v
Predicate
      |
      v
1 matching row
```

This is fundamentally different from an analytical query intentionally processing billions of rows.

---

# Part 2 — Search Optimization Concept

## 3. Additional Search Access Structures

Search Optimization maintains additional persistent information that Snowflake can use for supported lookup patterns.

```text
Large Table
     |
     +------------------+
     |                  |
     v                  v
Micro-partitions    Search Access Path
     |                  |
     +--------+---------+
              |
              v
            Query
```

The optimizer can determine whether the search access path is useful for a particular query.

## 4. You Do Not Manually Choose an Index

Search Optimization should not be treated exactly like a traditional database B-tree index.

You configure Search Optimization on a table or supported columns/search methods.

Snowflake's optimizer determines whether the maintained access path is useful.

---

# Part 3 — Search Optimization Is Not a Primary Key Index

## 5. Primary Keys

A Snowflake primary-key declaration should not automatically be interpreted as a traditional row-store index.

```sql
CREATE TABLE claims (
    claim_id STRING PRIMARY KEY,
    ...
);
```

does not mean Snowflake created a traditional B-tree index for `claim_id`.

## 6. Why This Matters

Teams migrating from PostgreSQL, Oracle, SQL Server, or MySQL may incorrectly assume:

```text
PRIMARY KEY
    =
Indexed lookup
```

Do not carry that assumption into Snowflake performance design.

---

# Part 4 — Strong Search Optimization Candidates

## 7. Point Lookup

```sql
SELECT *
FROM claims
WHERE claim_id = 'CLAIM-EXAMPLE-1001';
```

If `CLAIM_ID` is highly selective and the table is very large, this can be a strong candidate.

## 8. Highly Selective Business Identifier

Examples:

```text
CLAIM_ID
ORDER_ID
TRANSACTION_ID
EVENT_ID
MEMBER_ID
REQUEST_ID
TRACE_ID
```

These are candidate columns only when production workloads actually search them selectively.

---

# Part 5 — Equality Predicates

## 9. Common Pattern

A common candidate pattern is:

```sql
WHERE order_id = 'ORDER-EXAMPLE-5001'
```

or:

```sql
WHERE customer_id = 10001
```

The expected benefit is greatest when the predicate eliminates most of the table.

---

# Part 6 — IN Predicates

## 10. Multiple Lookup Values

Applications may issue:

```sql
SELECT *
FROM claims
WHERE claim_id IN (
    'CLAIM-EXAMPLE-1001',
    'CLAIM-EXAMPLE-1002',
    'CLAIM-EXAMPLE-1003'
);
```

Search Optimization may help supported selective search patterns such as these.

Validate exact current predicate support against Snowflake documentation.

---

# Part 7 — Selectivity Matters

## 11. Highly Selective

Suppose:

```text
Table rows     = 5,000,000,000
Matching rows  = 1
```

This is highly selective.

## 12. Low Selectivity

Suppose:

```text
Table rows     = 5,000,000,000
STATUS='ACTIVE'
Matching rows  = 3,500,000,000
```

Even if the predicate is supported syntactically, it is unlikely to behave like a selective point lookup.

## 13. Core Principle

Search Optimization is most compelling when:

```text
Large search space
       +
Small result set
       +
Repeated important workload
```

---

# Part 8 — Search Optimization Configuration

## 14. Table-Level Concept

A Search Optimization configuration is associated with a table.

Snowflake supports configuration that can target appropriate search methods and columns.

Always validate exact current syntax and supported methods against the current Snowflake documentation before production deployment.

## 15. Broad Configuration

Conceptually, Search Optimization can be enabled on a table.

A common form historically used is:

```sql
ALTER TABLE database.schema.table_name
ADD SEARCH OPTIMIZATION;
```

Use current Snowflake documentation to validate exact behavior before production execution.

---

# Part 9 — Column-Level Optimization

## 16. Prefer Targeted Design

Do not automatically optimize every column.

If the important workload is:

```sql
WHERE claim_id = ?
```

then investigate a targeted Search Optimization design for `CLAIM_ID`.

## 17. Why Targeting Matters

Broader Search Optimization can increase storage, maintenance, cost, and operational footprint.

Optimize what the workload actually needs.

---

# Part 10 — Search Methods

## 18. Search Optimization Can Support Different Access Patterns

Current Snowflake Search Optimization supports multiple search methods and predicate categories.

The exact supported methods evolve over time.

Examples can include search behavior for:

```text
Equality
Substring/string search
Geospatial predicates
Selected semi-structured patterns
```

Do not assume every predicate is supported.

Verify the current Search Optimization documentation.

---

# Part 11 — Equality Search

## 19. Equality-Oriented Access

A common design pattern is optimizing highly selective equality predicates.

Conceptually:

```text
EQUALITY(CLAIM_ID)
```

The exact current DDL should be validated before implementation.

---

# Part 12 — Multiple Columns

## 20. Different Lookup Patterns

Suppose an application frequently searches by:

```text
CLAIM_ID
MEMBER_ID
PROVIDER_ID
```

Do not immediately optimize all three.

Measure each workload.

## 21. Candidate Matrix

| Column | Query Frequency | Selectivity | Current Latency | Business Importance |
|---|---:|---:|---:|---|
| CLAIM_ID | High | Very high | High | Critical |
| MEMBER_ID | High | Medium | Medium | High |
| PROVIDER_ID | Low | Low | Low | Medium |

`CLAIM_ID` may be the strongest initial candidate.

---

# Part 13 — Search Optimization vs Micro-Partition Pruning

## 22. Pruning

Micro-partition pruning works by eliminating partitions that cannot contain relevant values.

```text
100,000 partitions
       |
       v
Metadata pruning
       |
       v
2,000 partitions scanned
```

## 23. Search Optimization

Search Optimization can provide more direct access for supported highly selective predicates.

```text
Huge table
   |
   v
Search access path
   |
   v
Small matching data set
```

---

# Part 14 — Search Optimization vs Clustering

## 24. Clustering

Clustering is often valuable when queries repeatedly filter large tables using range-oriented or predictable predicates.

```sql
WHERE service_date >= '2026-10-01'
  AND service_date <  '2026-10-08'
```

## 25. Search Optimization

Search Optimization is often more compelling for highly selective lookup patterns such as:

```sql
WHERE claim_id = 'CLAIM-EXAMPLE-1001'
```

## 26. Decision Pattern

```text
Range scan / pruning problem
        |
        v
Evaluate clustering

Highly selective lookup
        |
        v
Evaluate Search Optimization
```

This is a decision aid, not an absolute rule.

---

# Part 15 — Search Optimization vs Warehouse Resizing

## 27. Bigger Compute Is Not Always the Right Fix

Suppose a query scans several terabytes to return one row.

Changing a MEDIUM warehouse to an XLARGE warehouse may make the scan faster.

But it does not necessarily eliminate the unnecessary work.

## 28. Better Question

Ask:

> Why are we scanning so much data to find one row?

If the workload is a supported highly selective lookup, Search Optimization may be a more appropriate candidate.

---

# Part 16 — Search Optimization vs Cache

## 29. Cache Helps Repeated Access

Warehouse cache can make repeated access faster.

But when a warehouse suspends, local cache benefit may be lost.

## 30. Search Optimization Is a Different Mechanism

Search Optimization is maintained as part of the table's optimization structures.

Do not use warm-cache performance as evidence that Search Optimization is unnecessary.

Compare controlled workloads.

---

# Part 17 — Search Optimization vs Persisted Results

## 31. Persisted Result Reuse

An identical eligible query may reuse a previous result.

That can make a repeated point lookup appear nearly instantaneous.

## 32. Application Reality

Applications often search different identifiers:

```text
claim_id = A
claim_id = B
claim_id = C
```

Each request is different.

Persisted query-result reuse may therefore not solve the underlying lookup problem.

---

# Part 18 — Search Optimization vs Materialized Views

## 33. Materialized View

A materialized view maintains precomputed query results for supported query patterns.

## 34. Search Optimization

Search Optimization maintains access information intended to accelerate supported search predicates.

These solve different problems.

---

# Part 19 — Search Optimization vs Dynamic Tables

## 35. Dynamic Tables

Dynamic tables declaratively maintain transformed datasets.

They are not substitutes for Search Optimization.

---

# Part 20 — Search Optimization Cost Model

## 36. Search Optimization Is Not Free

Search Optimization can introduce:

```text
Storage cost
Maintenance cost
Serverless compute consumption
```

The exact billing model and usage reporting should be validated against current Snowflake documentation.

## 37. Production Equation

```text
Query latency benefit
       +
Query compute savings
       +
SLA/business benefit
       -
Search Optimization cost
       =
Net value
```

---

# Part 21 — Storage Overhead

## 38. Additional Structures Require Storage

Search access paths require additional storage.

The amount depends on factors such as table size, configured columns, data distribution, search methods, and data changes.

## 39. Do Not Assume a Fixed Percentage

Avoid rules such as:

> Search Optimization always adds X% storage.

Measure the actual table and configuration.

---

# Part 22 — Maintenance Cost

## 40. Data Changes Require Maintenance

When table data changes, Search Optimization structures may require maintenance.

Examples include:

```text
COPY
Snowpipe
Snowpipe Streaming
INSERT
MERGE
UPDATE
DELETE
```

## 41. High-Churn Tables

A high-ingestion or high-DML table can have different Search Optimization economics than a relatively static lookup table.

---

# Part 23 — Initial Build

## 42. Enabling Search Optimization Is Not Instantaneous

On a large existing table, Snowflake may need time and resources to build the required search access structures.

Do not assume:

```text
ALTER TABLE ...
ADD SEARCH OPTIMIZATION
```

means optimization is immediately complete.

## 43. Change Planning

For large production tables, plan initial build, maintenance, cost monitoring, performance validation, and rollback/reversal.

---

# Part 24 — Monitoring Build Progress

## 44. Search Optimization Status

Snowflake exposes metadata that can help evaluate Search Optimization configuration and progress.

Use the current Snowflake documentation for exact system functions, views, and output fields.

---

# Part 25 — Search Optimization History

## 45. Account Monitoring

Snowflake exposes account-level usage information related to Search Optimization.

This can help answer:

```text
Which tables consume Search Optimization resources?
How much?
Is consumption increasing?
```

Use current `ACCOUNT_USAGE` documentation for exact view names and column definitions.

---

# Part 26 — Query Profile Validation

## 46. Never Assume It Is Being Used

After enabling Search Optimization, validate actual production queries.

Do not assume:

```text
Feature enabled
      =
Every query uses it
```

## 47. Why the Optimizer May Not Use It

Possible reasons include:

```text
Predicate is not selective
Unsupported predicate
Search method not configured
Different expression
Data type mismatch
Optimizer determines normal scan is cheaper
Optimization structure not fully available
```

Validate with current Query Profile behavior.

---

# Part 27 — Query History Validation

## 48. Before/After Query IDs

Capture:

```text
Before query ID
After query ID
```

Compare equivalent executions.

## 49. Metrics

Record:

```text
Execution time
Bytes scanned
Partitions scanned
Warehouse
Warehouse size
Rows returned
Cache behavior
```

---

# Part 28 — Control Cached Results

## 50. Benchmark Correctly

During controlled testing:

```sql
ALTER SESSION SET USE_CACHED_RESULT = FALSE;
```

can help prevent persisted query-result reuse from invalidating the comparison.

## 51. Remember Chapter 40

This does not disable warehouse-local cache.

Account for warehouse state when designing the benchmark.

---

# Part 29 — Strong Before/After Test

## 52. Before

```text
Query ID:
Warehouse:
Warehouse size:
Execution:
Bytes scanned:
Partitions scanned:
Rows returned:
```

## 53. After

Record exactly the same metrics.

## 54. Cost

Also record:

```text
Search Optimization storage
Search Optimization maintenance credits
Query compute change
```

---

# Part 30 — Example: Claims Lookup

## 55. Workload

```text
PD_CLAIMS
Size = 25 TB
Rows = billions
```

Query:

```sql
SELECT
    claim_id,
    member_id,
    provider_id,
    service_date,
    status
FROM pd_claims
WHERE claim_id = 'CLAIM-EXAMPLE-1001';
```

## 56. Baseline

Suppose:

```text
Execution       = 18 sec
Bytes scanned   = 9 TB
Rows returned   = 1
```

This is a strong investigation candidate.

## 57. Next Step

Validate whether `CLAIM_ID` equality is a supported Search Optimization pattern in the current Snowflake release and whether the workload frequency/business importance justifies the cost.

---

# Part 31 — Example: Low-Selectivity Status

## 58. Query

```sql
SELECT COUNT(*)
FROM claims
WHERE status = 'ACTIVE';
```

Suppose ACTIVE represents 70% of the table.

## 59. Interpretation

This is not a highly selective lookup.

Do not assume Search Optimization will provide the same benefit as for a unique claim ID.

---

# Part 32 — Example: Date Range

## 60. Query

```sql
SELECT SUM(amount)
FROM claims
WHERE service_date >= '2026-10-01'
  AND service_date <  '2026-10-08';
```

## 61. Investigation

Start with micro-partition pruning, natural clustering, and explicit clustering if justified rather than automatically choosing Search Optimization.

---

# Part 33 — Example: Multi-Tenant Application

## 62. Query

```sql
SELECT *
FROM application_events
WHERE tenant_id = 1001
  AND request_id = 'REQ-EXAMPLE-5001';
```

If `REQUEST_ID` is highly selective within a massive event table, this can be worth investigating.

---

# Part 34 — Semi-Structured Data

## 63. VARIANT Workloads

Applications may search attributes stored inside semi-structured data.

```sql
SELECT *
FROM events
WHERE payload:request_id::STRING = 'REQ-EXAMPLE-5001';
```

Current Search Optimization capabilities can include selected semi-structured access patterns.

Validate exact support, syntax, data types, and configuration before production implementation.

---

# Part 35 — String Search

## 64. Search Patterns

Some workloads search text using patterns rather than simple equality.

Search Optimization supports selected string-search capabilities in current Snowflake releases.

Do not assume every `LIKE`, substring, or regular-expression pattern receives the same optimization.

---

# Part 36 — Geospatial Search

## 65. Geospatial Workloads

Search Optimization can support selected geospatial predicates.

This can be valuable for location-oriented analytical workloads where supported.

Verify current supported functions and data types.

---

# Part 37 — Search Optimization and Data Type

## 66. Data Type Matters

Optimization behavior can depend on the data type and configured search method.

Do not configure Search Optimization based only on column name.

---

# Part 38 — Search Optimization and Expressions

## 67. Query Expression Matters

Suppose Search Optimization is designed around `CLAIM_ID` but the application queries:

```sql
WHERE UPPER(claim_id) = 'CLAIM-EXAMPLE-1001'
```

Do not assume the same access path will automatically apply.

Validate supported expressions and Query Profile evidence.

---

# Part 39 — Application Query Consistency

## 68. Query Patterns Matter

Applications should avoid unnecessary transformations of lookup columns when those transformations interfere with efficient access.

---

# Part 40 — Data Type Mismatch

## 69. Example

Column:

```text
CUSTOMER_ID NUMBER
```

Application behavior introduces unnecessary conversion.

Type conversions can change optimization behavior.

Keep lookup predicates type-consistent where possible.

---

# Part 41 — Search Optimization and Joins

## 70. Join Workloads

Search Optimization capabilities can apply to selected join scenarios in current Snowflake functionality.

Do not assume all joins are accelerated.

Validate exact supported join predicates, build/probe behavior, and selectivity requirements using current documentation.

---

# Part 42 — Query Frequency

## 71. One Slow Query Is Not Enough

Suppose:

```text
Query frequency = once/month
Runtime         = 30 sec
```

Search Optimization maintenance may not be justified.

## 72. High-Frequency Workload

Suppose:

```text
Query frequency = 5 million/day
Runtime         = 2 sec
SLA             = 500 ms
```

Even a relatively small per-query improvement can have substantial business value.

---

# Part 43 — Business Criticality

## 73. Cost Is Not the Only Metric

A lookup used during customer login, clinical workflow, payment authorization, fraud detection, or operational incident response may justify optimization even if direct compute savings alone do not.

---

# Part 44 — Candidate Scoring

## 74. Example Scorecard

| Factor | Low | Medium | High |
|---|---|---|---|
| Table size | | | |
| Query frequency | | | |
| Predicate selectivity | | | |
| Current scan cost | | | |
| SLA impact | | | |
| Business criticality | | | |
| Maintenance cost | | | |

Use this to prioritize candidate workloads.

---

# Part 45 — Production Decision Framework

## 75. Question 1

Is the table large enough that lookup cost matters?

If no, do not optimize yet.

## 76. Question 2

Is the query highly selective?

If no, investigate another optimization.

## 77. Question 3

Is the predicate/search method supported?

If no, Search Optimization is not the current solution.

## 78. Question 4

Is the workload frequent or business-critical?

If no, cost may not be justified.

## 79. Question 5

Does controlled testing demonstrate meaningful improvement?

If no, do not deploy broadly.

## 80. Question 6

Does benefit justify maintenance and storage cost?

If no, remove or redesign.

---

# Part 46 — Production Change Process

## 81. Before Enabling

Capture:

```text
Table
Table size
Row count
Data growth rate
DML rate

Query pattern
Query frequency
Query IDs

Predicate
Selectivity

Execution time
Bytes scanned
Partitions scanned

Warehouse
Warehouse size

Business SLA
```

## 82. Configuration Design

Document:

```text
Search method
Target columns
Expected benefit
Expected maintenance
Expected storage
Owner
Rollback plan
```

## 83. After Enabling

Capture:

```text
Build status
Search Optimization cost
Storage impact
Query latency
Bytes scanned
Query compute
```

---

# Part 47 — Common Mistakes

## 84. Enable It on Every Large Table

Wrong.

Large table size alone is insufficient.

## 85. Optimize Every Column

Wrong.

Target real workload patterns.

## 86. Ignore Selectivity

Wrong.

A predicate matching most of the table is very different from a unique lookup.

## 87. Ignore Cost

Wrong.

Search Optimization consumes resources.

## 88. Resize Warehouse Instead

Potentially wrong.

A bigger warehouse may simply scan unnecessary data faster.

## 89. Assume Feature Enabled Means Query Uses It

Wrong.

Validate actual query behavior.

## 90. Benchmark Using Cached Results

Wrong.

Persisted query-result reuse can completely invalidate the comparison.

---

# Part 48 — Troubleshooting: No Performance Improvement

## 91. Symptom

Search Optimization is enabled but the query remains slow.

## 92. Investigate

Check:

```text
Is the predicate supported?
Is the correct column configured?
Is the predicate selective?
Is the search structure available?
Did the SQL expression change?
Are data types aligned?
Is Query Profile showing a different bottleneck?
Is queueing actually the problem?
Is a join or sort dominating?
```

---

# Part 49 — Troubleshooting: High Cost

## 93. Symptom

Search Optimization consumption increases significantly.

## 94. Investigate

Check:

```text
Which table?
Which search methods?
Which columns?
Table growth?
Ingestion growth?
MERGE growth?
UPDATE/DELETE growth?
Recent backfill?
Workload still active?
Queries still benefiting?
```

---

# Part 50 — Troubleshooting: Build Taking Time

## 95. Symptom

Search Optimization was enabled on a very large table but expected performance benefit is not yet visible.

## 96. Investigation

Determine whether the optimization structures are still being built or maintained.

Do not declare failure until build state is understood.

---

# Part 51 — Troubleshooting: Query Changed

## 97. Scenario

Original application query:

```sql
WHERE claim_id = ?
```

New release:

```sql
WHERE UPPER(claim_id) = ?
```

Performance regresses.

## 98. Investigation

Compare Query Profile and determine whether the new expression still qualifies for the configured optimization.

---

# Part 52 — Production Incident Runbook

## 99. Lookup Performance Incident

1. Capture slow query ID.
2. Capture historical fast query ID.
3. Confirm table.
4. Confirm query predicate.
5. Confirm rows returned.
6. Measure selectivity.
7. Compare SQL expressions.
8. Compare data types.
9. Compare warehouse.
10. Compare warehouse size.
11. Check queueing.
12. Compare bytes scanned.
13. Compare partitions scanned.
14. Review Query Profile.
15. Check Search Optimization configuration.
16. Check optimization build/status.
17. Check recent table growth.
18. Check ingestion/DML changes.
19. Check recent application deployment.
20. Check cache differences.
21. Determine whether Search Optimization is actually causal.
22. Apply controlled remediation.
23. Validate before/after query IDs.
24. Review cost.
25. Document root cause.

---

# Part 53 — Evidence Template

## 100. Search Optimization Investigation

```text
Table:

Table size:
Row count:
Daily growth:

Query:
Query ID:

Predicate:
Rows returned:
Estimated selectivity:

Warehouse:
Warehouse size:

Execution time:
Bytes scanned:
Partitions scanned:

Search Optimization enabled:
Search method:
Columns:

Optimization status:

Recent DML:
Recent backfill:

Search Optimization cost:
Storage overhead:

Observed problem:

Root cause:

Recommended action:

Measured improvement:

Cost impact:
```

---

# Part 54 — Hands-On Lab

## 101. Lab Objective

Compare a selective lookup before and after Search Optimization.

Use a non-production Snowflake environment.

Because Search Optimization is a billable feature, understand your account's current pricing and feature availability before enabling it.

## 102. Create Database

```sql
CREATE OR REPLACE DATABASE search_optimization_lab;
```

## 103. Create Schema

```sql
CREATE OR REPLACE SCHEMA search_optimization_lab.demo;
```

## 104. Create Table

```sql
CREATE OR REPLACE TABLE
search_optimization_lab.demo.events (
    event_id NUMBER,
    request_id STRING,
    customer_id NUMBER,
    event_date DATE,
    event_type STRING,
    amount NUMBER(12,2)
);
```

## 105. Generate Synthetic Data

```sql
INSERT INTO search_optimization_lab.demo.events
SELECT
    SEQ4(),
    'REQ-' || LPAD(SEQ4()::STRING, 12, '0'),
    MOD(SEQ4(), 100000),
    DATEADD(
        day,
        -MOD(SEQ4(), 365),
        CURRENT_DATE()
    ),
    CASE MOD(SEQ4(), 4)
        WHEN 0 THEN 'CREATE'
        WHEN 1 THEN 'UPDATE'
        WHEN 2 THEN 'READ'
        ELSE 'DELETE'
    END,
    MOD(SEQ4(), 100000) / 100.0
FROM TABLE(GENERATOR(ROWCOUNT => 10000000));
```

All data is synthetic.

## 106. Disable Persisted Result Reuse

```sql
ALTER SESSION SET USE_CACHED_RESULT = FALSE;
```

## 107. Baseline Lookup

Choose an existing synthetic `REQUEST_ID`.

```sql
SELECT *
FROM search_optimization_lab.demo.events
WHERE request_id = 'REQ-000000500000';
```

Capture query ID, execution time, bytes scanned, partitions scanned, and rows returned.

## 108. Repeat Baseline

Run several controlled baseline executions.

Do not rely on one measurement.

## 109. Inspect Query Profile

Determine whether the workload performs substantial scanning relative to the one-row result.

## 110. Evaluate Search Optimization Configuration

For the lab, configure Search Optimization for the supported equality-search pattern on `REQUEST_ID`.

Because Snowflake Search Optimization syntax and supported search methods can evolve, use the current Snowflake documentation to confirm the exact DDL before executing this step.

Do not guess production syntax.

## 111. Wait for Build Readiness

Use current Snowflake-supported metadata/status mechanisms to determine when the search access path is ready for meaningful testing.

## 112. Re-Run Lookup

Execute the same lookup under comparable conditions.

Capture a new query ID.

## 113. Compare

| Metric | Before | After |
|---|---:|---:|
| Execution time | | |
| Bytes scanned | | |
| Partitions scanned | | |
| Rows returned | | |
| Query compute | | |

## 114. Test Different Request IDs

Do not test only the same literal repeatedly.

```sql
SELECT *
FROM search_optimization_lab.demo.events
WHERE request_id = 'REQ-000000700000';
```

This helps reduce confusion with persisted result reuse.

## 115. Low-Selectivity Test

```sql
SELECT COUNT(*)
FROM search_optimization_lab.demo.events
WHERE event_type = 'READ';
```

Compare the behavior with the highly selective `REQUEST_ID` lookup.

## 116. Date-Range Test

```sql
SELECT SUM(amount)
FROM search_optimization_lab.demo.events
WHERE event_date >= DATEADD(day, -30, CURRENT_DATE());
```

Observe that a range-oriented analytical workload has different characteristics from a unique lookup.

## 117. Restore Session

```sql
ALTER SESSION SET USE_CACHED_RESULT = TRUE;
```

## 118. Cleanup

Before dropping the lab, record any Search Optimization usage/cost information you want to retain.

Then:

```sql
DROP DATABASE IF EXISTS search_optimization_lab;
```

---

# Part 55 — Lab Results Template

## 119. Results

| Test | Runtime | Bytes Scanned | Partitions Scanned | Rows |
|---|---:|---:|---:|---:|
| Selective lookup before | | | | |
| Selective lookup after | | | | |
| Different selective ID | | | | |
| Low-selectivity predicate | | | | |
| Date range | | | | |

---

# Part 56 — Production Monitoring Checklist

## 120. Workload

- Query frequency
- Query latency
- Query IDs
- Predicate patterns
- Selectivity
- Rows returned
- SLA

## 121. Table

- Table size
- Row growth
- Ingestion rate
- MERGE rate
- UPDATE/DELETE activity
- Backfills

## 122. Search Optimization

- Enabled tables
- Search methods
- Target columns
- Build/status
- Maintenance consumption
- Storage impact

## 123. Performance

- Bytes scanned
- Partitions scanned
- Execution time
- Query compute
- Query Profile

## 124. FinOps

- Search Optimization credits
- Storage cost
- Query compute savings
- SLA value
- Net operational value

---

# Part 57 — Periodic Review

## 125. Optimization Can Become Stale

Applications change.

A column optimized today may no longer be queried six months later.

## 126. Review Questions

Ask periodically:

```text
Are these lookup queries still running?
Are they still business-critical?
Are the same columns used?
Is Search Optimization still improving them?
What does maintenance cost now?
```

## 127. Remove Unnecessary Optimization

If an optimization no longer provides sufficient value, evaluate removing it using the current supported Snowflake DDL.

Do not pay indefinitely for unused optimization.

---

# Part 58 — Change Management

## 128. Treat It as a Production Change

Document:

```text
Reason
Table
Search method
Columns
Baseline query IDs
Baseline performance
Expected improvement
Expected cost
Build monitoring
Validation queries
Rollback/reversal plan
Owner
```

---

# Part 59 — DBRE/SRE Decision Example

## 129. Weak Recommendation

> The table is 30 TB. Enable Search Optimization.

This lacks evidence.

## 130. Strong Recommendation

> The customer-facing claim lookup executes approximately 1.8 million times per day and returns one row by `CLAIM_ID`. Representative executions scan a large portion of the 30-TB table and have a P95 latency above the application SLA. We should test equality-oriented Search Optimization for `CLAIM_ID`, compare controlled before/after query IDs, and measure Search Optimization maintenance/storage cost against latency and query-compute savings before production rollout.

This is evidence-driven.

---

# Part 60 — Optimization Selection Framework

## 131. Poor Date-Range Pruning

Consider natural clustering, clustering key, and Automatic Clustering.

## 132. Highly Selective Lookup

Consider Search Optimization.

## 133. Repeated Identical Query

Investigate persisted result reuse.

## 134. Repeated Access to Same Data

Investigate warehouse cache.

## 135. Heavy Repeated Aggregation

Depending on the workload, evaluate materialized views, dynamic tables, or pre-aggregation architecture.

## 136. Concurrency Problem

Evaluate multi-cluster warehouse and workload isolation.

## 137. Compute-Bound Single Query

Evaluate warehouse sizing, Query Acceleration Service, and query design.

The important lesson is:

> Choose the optimization that matches the bottleneck.

---

# Acceptance Criteria

The chapter is complete when you can:

- explain the purpose of Search Optimization Service
- distinguish it from traditional row-store indexes
- explain why primary keys do not imply traditional indexing
- identify highly selective point-lookups
- understand equality-search candidates
- understand IN-style lookup candidates conceptually
- explain why selectivity matters
- understand table-level Search Optimization concepts
- prefer targeted optimization where appropriate
- understand search methods conceptually
- evaluate multiple candidate columns
- distinguish Search Optimization from micro-partition pruning
- distinguish Search Optimization from clustering
- distinguish Search Optimization from warehouse resizing
- distinguish Search Optimization from caching
- distinguish Search Optimization from persisted results
- distinguish Search Optimization from materialized views
- distinguish Search Optimization from dynamic tables
- understand storage overhead
- understand maintenance cost
- understand initial build behavior
- monitor build/status
- investigate account-level usage
- validate optimizer behavior using Query Profile
- perform controlled before/after testing
- control persisted-result reuse during testing
- account for warehouse cache
- evaluate query compute and Search Optimization cost together
- analyze highly selective identifiers
- recognize low-selectivity workloads
- recognize range-oriented workloads
- evaluate multi-tenant lookups
- understand semi-structured Search Optimization concepts
- understand string-search concepts
- understand geospatial-search concepts
- consider data types
- consider query expressions
- avoid unnecessary lookup transformations
- recognize type-mismatch risks
- understand supported join optimization conceptually
- incorporate query frequency
- incorporate business criticality
- score candidate workloads
- use a production decision framework
- manage Search Optimization as a production change
- avoid common Search Optimization mistakes
- troubleshoot missing performance improvement
- troubleshoot high maintenance cost
- troubleshoot build readiness
- investigate application-query changes
- execute the production incident runbook
- capture evidence consistently
- perform the hands-on lab
- compare selective and non-selective predicates
- monitor performance and FinOps together
- periodically review existing optimization
- remove unnecessary optimization
- choose the appropriate Snowflake optimization for the actual bottleneck

---

## Key Takeaways

Search Optimization Service is not a feature to enable simply because a table is large.

A strong candidate looks more like:

```text
Large table
    +
Highly selective predicate
    +
Small result set
    +
Frequent or critical workload
    +
Supported search pattern
```

Start with evidence:

```text
Slow lookup
    |
    v
Capture Query ID
    |
    v
Check Query Profile
    |
    v
Confirm excessive scan
    |
    v
Measure selectivity
    |
    v
Confirm supported search pattern
    |
    v
Test Search Optimization
```

Then validate economics:

```text
Latency improvement
       +
Query compute savings
       +
Business/SLA value
       -
Maintenance cost
       -
Storage cost
       =
Net operational value
```

Do not use a larger warehouse to hide an inefficient point lookup without first understanding why the query scans so much data.

Do not enable Search Optimization across every column.

Do not assume the optimizer will use it merely because it is enabled.

Do not benchmark it using uncontrolled cached-result tests.

Instead:

> Target Search Optimization at proven, selective, important access patterns and verify the improvement with real query evidence.

The next chapter is **Chapter 42 — Query Acceleration Service**.
