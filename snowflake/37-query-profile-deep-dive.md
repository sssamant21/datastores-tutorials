# 37 — Query Profile Deep Dive

## Overview

When a Snowflake query is slow, one of the most important questions is:

> Which part of the execution plan consumed the time and resources?

Query Profile provides operator-level visibility into query execution.

Instead of saying:

```text
The query took 4 minutes.
```

Query Profile allows us to investigate:

```text
Which operator was slow?
How much data was scanned?
Were partitions pruned?
Did a join expand the dataset?
Was data redistributed?
Did processing spill to local storage?
Did processing spill to remote storage?
Was sorting expensive?
Was aggregation expensive?
Was the query waiting rather than executing?
```

A practical investigation flow is:

```text
Query ID
   |
   v
Query History
   |
   v
Timing Breakdown
   |
   v
Query Profile
   |
   v
Dominant Operator
   |
   +---- Scan
   +---- Join
   +---- Aggregate
   +---- Sort
   +---- Window
   +---- Data Movement
   +---- Spill
   |
   v
Root Cause
   |
   v
Targeted Remediation
```

This chapter covers Query Profile navigation, operator trees, scans, pruning, joins, join explosion, aggregation, sorting, window functions, data redistribution, skew, local and remote spilling, bottleneck identification, before/after comparison, production troubleshooting, and incident response.

---

# Part 1 — Start with the Query ID

## 1. Why Query ID Matters

Every executed Snowflake query receives a query ID.

The query ID provides a precise reference for Query History, Query Profile, execution metadata, incident investigation, and performance comparison.

## 2. Capture It Early

During an incident, capture representative query IDs before resizing a warehouse, rewriting SQL, restarting applications, changing workload routing, or changing clustering.

Otherwise the strongest evidence may become harder to compare.

## 3. LAST_QUERY_ID

For interactive testing, a recent query ID can be retrieved using supported Snowflake functions such as:

```sql
SELECT LAST_QUERY_ID();
```

Be aware that executing additional statements can affect which query is considered the last query.

---

# Part 2 — Query History Before Query Profile

## 4. Start Broad

Before opening the operator tree, determine total duration, compilation time, queue time, execution time, warehouse, warehouse size, user, role, application, bytes scanned, and spill.

## 5. Why?

Suppose:

```text
Total elapsed = 130 seconds
Queue time    = 120 seconds
Execution     = 8 seconds
```

Query Profile may show an efficient 8-second execution. The dominant problem is queueing.

## 6. Another Example

```text
Total elapsed = 130 seconds
Queue time    = 0 seconds
Execution     = 125 seconds
```

Now Query Profile becomes central to the investigation.

---

# Part 3 — Query Profile Mental Model

## 7. Operator Tree

A query plan can be represented conceptually as:

```text
TableScan
    |
    v
Filter
    |
    v
Join
    |
    v
Aggregate
    |
    v
Sort
    |
    v
Result
```

Real plans can contain many branches and execution stages.

## 8. Data Flows Through Operators

Think of the plan as a data-processing pipeline. Each operator receives rows, performs work, and produces rows.

## 9. Follow the Data

For each important operator ask:

```text
How much data entered?
How much data left?
How long did it take?
Did data volume unexpectedly increase?
Did the operator spill?
```

---

# Part 4 — Find the Dominant Operator

## 10. Do Not Read Every Operator Equally

Start with the operators responsible for the largest percentage of execution time or resource consumption.

## 11. Example

```text
TableScan      12%
Join           61%
Aggregate      18%
Sort            7%
Other           2%
```

Start with the join.

## 12. Another Example

```text
TableScan      78%
Join           10%
Aggregate       8%
Other           4%
```

Start with the scan.

---

# Part 5 — Table Scan

## 13. What Does TableScan Do?

A TableScan reads data required from a Snowflake table or other supported source.

Important questions include which table, how many partitions, how many bytes, which columns, and what filters.

## 14. Large Scan

A large scan is not automatically bad. If a report legitimately needs an entire multi-terabyte dataset, a large scan may be expected.

The question is:

> Is the query scanning substantially more data than necessary?

---

# Part 6 — Partition Pruning

## 15. Pruning Metrics

For a scan, compare:

```text
Partitions scanned
Partitions total
```

Conceptually:

```text
Partitions total   = 10,000
Partitions scanned = 100
```

This suggests strong elimination.

## 16. Poor Pruning Example

```text
Partitions total   = 10,000
Partitions scanned = 9,800
```

If the query requests only one day of data, investigate why nearly the entire table was scanned.

## 17. Pruning Ratio

A useful conceptual calculation is:

```text
Scan ratio =
Partitions scanned / Partitions total
```

Example:

```text
100 / 10,000 = 1%
```

Interpret this in context rather than using a universal threshold.

---

# Part 7 — Why Pruning Can Be Poor

## 18. Broad Predicate

```sql
SELECT *
FROM events;
```

No selective predicate exists.

## 19. Low-Selectivity Predicate

```sql
WHERE status = 'ACTIVE'
```

If almost every row is ACTIVE, the filter does little to reduce scanning.

## 20. Data Layout

Relevant values may be spread across many micro-partitions.

Chapter 39 covers clustering in depth.

## 21. Predicate Design

Functions or transformations around filtering columns can sometimes make optimization less straightforward.

Compare clear range predicates where semantically appropriate.

Always verify behavior through actual Query Profile evidence.

---

# Part 8 — Bytes Scanned

## 22. Why Bytes Matter

Two queries may scan the same number of partitions but different amounts of data because they require different columns or data volumes.

## 23. Projection

Compare:

```sql
SELECT *
FROM very_wide_table;
```

with:

```sql
SELECT
    customer_id,
    transaction_date
FROM very_wide_table;
```

Selecting only required columns can reduce unnecessary data processing.

---

# Part 9 — Filter Operators

## 24. Filtering

Filters remove rows that do not satisfy predicates.

```sql
WHERE transaction_date >= '2026-10-01'
```

## 25. Filter Reduction

Conceptually:

```text
Input rows  = 1,000,000,000
Output rows = 1,000
```

A highly selective filter substantially reduces downstream work.

## 26. Late Reduction

If massive amounts of data flow through joins or sorts before being reduced, investigate whether query structure or optimizer behavior can be improved.

---

# Part 10 — Join Operators

## 27. Join Investigation

For each join, identify left-side input, right-side input, join condition, rows entering, rows leaving, execution time, and spill.

## 28. Expected Join

```text
Orders    = 500M rows
Customers = 10M rows
Output    = 500M rows
```

This may be reasonable for a many-to-one relationship.

## 29. Suspicious Join

```text
Input A = 10M
Input B = 10M
Output  = 2B
```

This requires immediate investigation.

---

# Part 11 — Join Explosion

## 30. What Is Join Explosion?

Join explosion occurs when a join produces far more rows than expected.

```text
10M
   \
    JOIN → 2B rows
   /
10M
```

## 31. Common Causes

```text
Missing join predicate
Incomplete join key
Many-to-many relationship
Duplicate dimension keys
NULL/default key behavior
Unexpected source duplicates
Range join
Cartesian product
```

## 32. Missing Predicate

Bad:

```sql
SELECT *
FROM orders o
JOIN customers c;
```

This can create Cartesian behavior.

## 33. Incomplete Key

Suppose uniqueness requires CUSTOMER_ID and SOURCE_SYSTEM but the query joins only:

```sql
ON a.customer_id = b.customer_id
```

Rows from different source systems may multiply.

---

# Part 12 — Detect Join Explosion

## 34. Compare Row Counts

Inspect rows entering and leaving the join. A dramatic increase is a strong signal.

## 35. Validate Cardinality

Before rewriting the query, verify whether the actual data relationship is one-to-one, one-to-many, or many-to-many.

## 36. Validate Duplicate Keys

```sql
SELECT
    customer_id,
    COUNT(*)
FROM customer_dimension
GROUP BY customer_id
HAVING COUNT(*) > 1;
```

If the dimension is expected to contain one row per customer, duplicates can explain join expansion.

---

# Part 13 — Aggregation Operators

## 37. Aggregation

```sql
SELECT
    region,
    SUM(amount)
FROM sales
GROUP BY region;
```

## 38. Low Cardinality

If REGION has four values:

```text
Input  = 1B rows
Output = 4 rows
```

The aggregation performs substantial work but strongly reduces the result.

## 39. High Cardinality

```sql
GROUP BY transaction_id
```

may produce almost as many output groups as input rows.

## 40. Investigate

Ask how many input rows and groups exist, whether the grouping is required, and whether aggregation spilled.

---

# Part 14 — DISTINCT

## 41. DISTINCT Is Work

```sql
SELECT DISTINCT customer_id
FROM sales;
```

Snowflake must determine unique values.

## 42. Common Anti-Pattern

Developers sometimes add DISTINCT to hide duplicate rows caused by an incorrect join.

```text
Join explosion
     |
     v
DISTINCT
     |
     v
Duplicates hidden
```

Fix the join rather than masking the symptom.

---

# Part 15 — Sort Operators

## 43. Sort

```sql
ORDER BY transaction_timestamp DESC
```

Large sorts can require substantial compute and memory.

## 44. Questions

Ask how many rows are being sorted, whether sorting is required, whether LIMIT is present, and whether sorting spilled.

## 45. Unnecessary ORDER BY

ETL transformations often do not require globally ordered output. Removing unnecessary sorting can eliminate expensive work.

---

# Part 16 — Window Functions

## 46. Example

```sql
ROW_NUMBER() OVER (
    PARTITION BY customer_id
    ORDER BY event_time DESC
)
```

## 47. Query Profile Impact

Window processing can involve partitioning, sorting, large intermediate state, memory, and spill.

## 48. Large Partitions

If one customer has an enormous number of rows, the workload may become skewed.

---

# Part 17 — Data Redistribution

## 49. Why Data Moves

Distributed processing sometimes requires rows to move between workers.

Examples include join keys, GROUP BY keys, window partition keys, and DISTINCT.

## 50. Network/Data Movement

```text
Worker A ----\
Worker B -----+---- Exchange ----> Workers
Worker C -----+
Worker D ----/
```

## 51. Investigation

Ask how much data moved, why it moved, whether input could have been reduced first, and whether the key is heavily skewed.

---

# Part 18 — Data Skew

## 52. Example

Suppose customer_id = UNKNOWN represents 70% of rows. Operations grouped or joined on customer_id may produce uneven work.

## 53. Skew Symptoms

Look for one execution path much slower than others, a dominant key, NULL-heavy keys, default values, and uneven processing.

## 54. Verify with SQL

```sql
SELECT
    customer_id,
    COUNT(*) AS row_count
FROM transactions
GROUP BY customer_id
ORDER BY row_count DESC
LIMIT 20;
```

---

# Part 19 — Local Spill

## 55. Meaning

Local spill indicates intermediate data exceeded available memory and some processing used local storage.

## 56. Interpretation

Some spill may occur in legitimate large workloads. Significant spill combined with slow execution deserves investigation.

## 57. Possible Causes

```text
Large join
Large aggregation
Large sort
High-cardinality window
Large intermediate result
Warehouse undersizing
```

---

# Part 20 — Remote Spill

## 58. Meaning

Remote spill means intermediate processing exceeded available memory/local capacity and required remote storage.

## 59. Why It Matters

Remote storage is substantially slower than memory and is generally an important warning signal in performance analysis.

## 60. Investigation Order

When remote spill appears:

1. Identify the spilling operator.
2. Check input size.
3. Check output size.
4. Check join cardinality.
5. Check filters.
6. Check pruning.
7. Check sorting.
8. Check aggregation.
9. Check warehouse size.
10. Determine whether SQL or compute is the root cause.

---

# Part 21 — Do Not Fix Spill Blindly

## 61. Bad Response

```text
Remote spill detected
       |
       v
Increase warehouse
```

This may reduce spill but leave an inefficient query unchanged.

## 62. Better Response

```text
Remote spill
     |
     v
Which operator?
     |
     v
Why so much intermediate data?
     |
     +---- Poor pruning?
     +---- Join explosion?
     +---- Sort?
     +---- Aggregation?
     |
     v
Fix root cause
```

Then resize if evidence shows the workload genuinely needs more memory/compute.

---

# Part 22 — Query Profile and Queueing

## 63. Important Limitation

Query Profile focuses heavily on execution. A query can still feel slow because of warehouse queueing.

Always inspect query history/timing before focusing only on operators.

## 64. Example

```text
Queue = 180 seconds
Execution = 12 seconds
```

Optimizing the 12-second execution cannot eliminate the dominant 180-second wait.

---

# Part 23 — Query Profile and Caching

## 65. Result Reuse

If persisted query results are reused, the query may not perform the same underlying scan/join work.

## 66. Performance Testing

When comparing before/after performance, verify whether cache/result reuse affected either execution.

---

# Part 24 — Query Profile and Warehouse Size

## 67. Compare Carefully

If a query takes:

```text
Medium = 120 seconds
Large  = 70 seconds
```

do not immediately conclude Large is the correct production answer.

Also compare credits consumed, concurrency, spill, query frequency, SLA, and cost per successful workload.

## 68. Performance vs Cost

A warehouse twice as large may finish faster but consume credits at a higher rate. Optimization should consider both latency and cost.

---

# Part 25 — Before/After Comparison

## 69. Baseline

Before changing SQL, record query ID, warehouse, warehouse size, elapsed time, execution time, bytes scanned, partitions scanned, partitions total, rows produced, local spill, and remote spill.

## 70. After Change

Capture the same metrics.

## 71. Comparison Table

| Metric | Before | After |
|---|---:|---:|
| Execution time | 120 s | 35 s |
| Bytes scanned | 2 TB | 300 GB |
| Partitions scanned | 8,000 | 900 |
| Remote spill | 50 GB | 0 |
| Output rows | 10M | 10M |

This demonstrates why performance improved.

---

# Part 26 — Known-Good Comparison

## 72. Compare Historical Executions

If the same workload was fast yesterday but slow today, compare data volume, warehouse size, concurrency, SQL text, query plan, pruning, spill, and application parameters.

## 73. Ask What Changed

Possible changes include more data, different predicates, different joins, schema changes, warehouse changes, concurrency spikes, clustering degradation, and application releases.

---

# Part 27 — Query Profile Troubleshooting Workflow

## 74. Step 1 — Capture Query ID

Do not troubleshoot only from screenshots or user descriptions.

## 75. Step 2 — Check Query History

Determine total time, compilation, queue, execution, and warehouse.

## 76. Step 3 — Open Query Profile

If execution is the dominant problem, inspect the execution graph.

## 77. Step 4 — Find Dominant Operator

Start with the most expensive operator.

## 78. Step 5 — Follow Inputs

Determine what data entered the operator.

## 79. Step 6 — Follow Outputs

Determine whether the operator reduced, preserved, or expanded data.

## 80. Step 7 — Check Scan

Inspect partitions scanned, partitions total, bytes scanned, filters, and columns.

## 81. Step 8 — Check Join

Inspect input rows, output rows, join condition, and cardinality.

## 82. Step 9 — Check Spill

Determine whether spill is local or remote, which operator caused it, and how much spilled.

## 83. Step 10 — Form Hypothesis

Example:

> The query is slow because the join produces a 20x row expansion, which drives a large aggregation and remote spill.

That is much stronger than saying Snowflake is slow.

---

# Part 28 — Scan Root-Cause Example

## 84. Scenario

```sql
SELECT
    customer_id,
    amount
FROM sales
WHERE transaction_date = '2026-10-01';
```

Profile:

```text
Partitions total   = 50,000
Partitions scanned = 48,000
Bytes scanned      = 4 TB
```

## 85. Analysis

The query requests one day but scans most partitions.

Investigate data distribution, clustering, predicate behavior, and table growth.

## 86. Next Step

Chapter 38 covers micro-partition pruning in depth. Chapter 39 covers clustering.

---

# Part 29 — Join Root-Cause Example

## 87. Scenario

```text
Orders input     = 200M
Customer input   = 5M
Join output      = 3B
Remote spill     = 400 GB
```

## 88. Analysis

The join expands rows approximately 15x relative to the large input.

Investigate duplicate customer keys, incomplete join conditions, many-to-many relationships, and source-system keys.

## 89. Possible Finding

Correct uniqueness may require CUSTOMER_ID and SOURCE_SYSTEM, but SQL joins only CUSTOMER_ID.

Fixing the key can remove the explosion.

---

# Part 30 — Sort Root-Cause Example

## 90. Scenario

An ETL query ends with:

```sql
ORDER BY transaction_timestamp;
```

Query Profile shows:

```text
Sort = 55% execution
Remote spill = 150 GB
```

## 91. Investigation

Ask whether the downstream table requires globally sorted insertion. Often it does not.

Removing unnecessary ORDER BY may eliminate major work.

---

# Part 31 — Aggregation Root-Cause Example

## 92. Scenario

```sql
SELECT
    transaction_id,
    COUNT(*)
FROM huge_table
GROUP BY transaction_id;
```

Nearly every transaction ID is unique.

## 93. Profile

```text
Input rows  = 2B
Groups      = 1.9B
Remote spill
```

## 94. Investigation

Determine whether the business requirement actually needs transaction-level aggregation.

---

# Part 32 — Window Function Root-Cause Example

## 95. Scenario

```sql
ROW_NUMBER() OVER (
    PARTITION BY patient_id
    ORDER BY event_timestamp DESC
)
```

## 96. Profile

Large sort/window processing dominates execution.

## 97. Investigation

Check rows per patient, skew, date filtering, and whether full history is needed.

Reducing input before window processing can materially reduce work.

---

# Part 33 — Query Profile During Incidents

## 98. Do Not Investigate Only One Query

During an incident, capture multiple representative query IDs, such as a slow dashboard query, slow ETL query, normal query, and previously fast query.

## 99. Why?

One query may be poorly written while another may reveal warehouse-wide contention.

Distinguish query-specific from workload-wide problems.

---

# Part 34 — Workload-Level Analysis

## 100. Query Profile Is One Piece

Combine Query Profile with Query History, warehouse load, concurrency, queueing, credit usage, and application timing.

## 101. Example

If 100 queries all queue for two minutes but execute normally, analyzing each operator tree is unlikely to identify the primary issue.

---

# Part 35 — Production Query Profile Checklist

## 102. Query Context

- Query ID
- User
- Role
- Application
- Warehouse
- Warehouse size
- Start time
- Query type

## 103. Timing

- Total elapsed
- Compilation
- Queue
- Execution

## 104. Scan

- Tables scanned
- Bytes scanned
- Partitions scanned
- Partitions total
- Columns scanned
- Filters

## 105. Operators

- Dominant operator
- Joins
- Aggregations
- Sorts
- Window functions
- Data movement

## 106. Cardinality

- Input rows
- Output rows
- Join expansion
- Aggregation groups

## 107. Resource Pressure

- Local spill
- Remote spill
- Skew
- Large intermediate data

## 108. Environment

- Warehouse concurrency
- Queueing
- Warehouse size
- Cache effects
- Recent changes

---

# Part 36 — Query Profile Incident Runbook

## 109. Slow Query Runbook

1. Capture query ID.
2. Capture SQL text.
3. Capture user.
4. Capture role.
5. Capture warehouse.
6. Capture warehouse size.
7. Capture start time.
8. Capture total elapsed time.
9. Capture compilation time.
10. Capture queue time.
11. Capture execution time.
12. Open Query Profile.
13. Identify dominant operator.
14. Inspect scan operators.
15. Record partitions scanned.
16. Record partitions total.
17. Record bytes scanned.
18. Review filters.
19. Inspect joins.
20. Compare join input/output rows.
21. Check join cardinality.
22. Check aggregation.
23. Check sorting.
24. Check window processing.
25. Check data redistribution.
26. Check skew.
27. Check local spill.
28. Check remote spill.
29. Compare with known-good execution.
30. Identify recent changes.
31. Form root-cause hypothesis.
32. Apply one targeted remediation.
33. Re-run representative workload.
34. Capture new query ID.
35. Compare before/after metrics.
36. Validate cost.
37. Monitor recurrence.
38. Document root cause.

---

# Part 37 — Query Profile Evidence Template

## 110. Incident Notes

```text
Query ID:
Application:
Warehouse:
Warehouse size:

Total elapsed:
Compilation:
Queue:
Execution:

Dominant operator:

Bytes scanned:
Partitions scanned:
Partitions total:

Join input:
Join output:

Local spill:
Remote spill:

Observed bottleneck:

Likely root cause:

Recommended remediation:

Before/after validation:
```

---

# Part 38 — Hands-On Lab

## 111. Lab Objective

Generate synthetic data and compare Query Profiles for selective scan, broad scan, aggregation, join, sort, and window function.

Use non-production.

## 112. Create Database

```sql
CREATE OR REPLACE DATABASE query_profile_lab;
```

## 113. Create Schema

```sql
CREATE OR REPLACE SCHEMA
query_profile_lab.demo;
```

## 114. Create Events Table

```sql
CREATE OR REPLACE TABLE
query_profile_lab.demo.events (
    event_id NUMBER,
    customer_id NUMBER,
    region STRING,
    event_date DATE,
    event_timestamp TIMESTAMP_NTZ,
    amount NUMBER(12,2)
);
```

## 115. Generate Synthetic Data

```sql
INSERT INTO query_profile_lab.demo.events
SELECT
    SEQ4(),
    MOD(SEQ4(), 100000),
    CASE MOD(SEQ4(), 4)
        WHEN 0 THEN 'EAST'
        WHEN 1 THEN 'WEST'
        WHEN 2 THEN 'SOUTH'
        ELSE 'NORTH'
    END,
    DATEADD(
        day,
        -MOD(SEQ4(), 365),
        CURRENT_DATE()
    ),
    DATEADD(
        second,
        -MOD(SEQ4(), 31536000),
        CURRENT_TIMESTAMP()
    ),
    MOD(SEQ4(), 100000) / 100.0
FROM TABLE(GENERATOR(ROWCOUNT => 5000000));
```

## 116. Test 1 — Broad Scan

```sql
SELECT
    COUNT(*),
    SUM(amount)
FROM query_profile_lab.demo.events;
```

Capture query ID and inspect the scan.

## 117. Test 2 — Selective Scan

```sql
SELECT
    COUNT(*),
    SUM(amount)
FROM query_profile_lab.demo.events
WHERE event_date = CURRENT_DATE();
```

Compare partitions scanned, bytes scanned, and execution time.

## 118. Test 3 — Aggregation

```sql
SELECT
    region,
    COUNT(*),
    SUM(amount)
FROM query_profile_lab.demo.events
GROUP BY region;
```

Inspect aggregation.

## 119. Test 4 — High-Cardinality Aggregation

```sql
SELECT
    customer_id,
    SUM(amount)
FROM query_profile_lab.demo.events
GROUP BY customer_id;
```

Compare operator behavior with region aggregation.

## 120. Create Customer Table

```sql
CREATE OR REPLACE TABLE
query_profile_lab.demo.customer (
    customer_id NUMBER,
    segment STRING
);
```

## 121. Populate Customers

```sql
INSERT INTO query_profile_lab.demo.customer
SELECT
    SEQ4(),
    CASE MOD(SEQ4(), 3)
        WHEN 0 THEN 'STANDARD'
        WHEN 1 THEN 'PREMIUM'
        ELSE 'ENTERPRISE'
    END
FROM TABLE(GENERATOR(ROWCOUNT => 100000));
```

## 122. Test 5 — Join

```sql
SELECT
    c.segment,
    COUNT(*) AS events,
    SUM(e.amount) AS total_amount
FROM query_profile_lab.demo.events e
JOIN query_profile_lab.demo.customer c
    ON e.customer_id = c.customer_id
GROUP BY c.segment;
```

Inspect join inputs, join output, aggregation, and data movement.

## 123. Test 6 — Sort

```sql
SELECT
    event_id,
    customer_id,
    amount
FROM query_profile_lab.demo.events
ORDER BY amount DESC
LIMIT 100;
```

Inspect sort behavior.

## 124. Test 7 — Window Function

```sql
SELECT
    customer_id,
    event_timestamp,
    amount,
    ROW_NUMBER() OVER (
        PARTITION BY customer_id
        ORDER BY event_timestamp DESC
    ) AS rn
FROM query_profile_lab.demo.events
QUALIFY rn = 1;
```

Inspect window processing.

## 125. Record Results

| Test | Query ID | Execution | Scan | Spill | Dominant Operator |
|---|---|---:|---:|---:|---|
| Broad scan | | | | | |
| Selective scan | | | | | |
| Region aggregation | | | | | |
| Customer aggregation | | | | | |
| Join | | | | | |
| Sort | | | | | |
| Window | | | | | |

## 126. Analyze

For each query answer:

- What was the dominant operator?
- How much data entered?
- How much data left?
- Was pruning effective?
- Did cardinality increase?
- Was there spill?
- What would you optimize first?

## 127. Cleanup

```sql
DROP DATABASE IF EXISTS query_profile_lab;
```

---

# Part 39 — Production Review Questions

## 128. Before Recommending SQL Changes

Ask whether you have the query ID, Query Profile evidence, confirmation that execution is the bottleneck, the dominant operator, and recent changes.

## 129. Before Recommending Warehouse Resize

Ask whether there is spill, SQL is efficient, pruning is effective, the join is correct, the workload is memory-bound, and what the expected cost increase is.

## 130. Before Recommending Clustering

Ask whether scan/pruning is actually the bottleneck, the table is large enough, predicates are repetitive and selective, and what clustering maintenance will cost.

Chapter 39 covers this decision in depth.

---

# Part 40 — Operational Principles

## 131. Evidence Before Opinion

Avoid:

```text
The warehouse looks too small.
```

Prefer:

```text
The join operator produced a 14x row expansion,
caused 280 GB of remote spill,
and accounted for 72% of execution time.
```

## 132. Optimize the Dominant Bottleneck

If a scan consumes 80% of execution, optimize the scan first.

If a join consumes 70%, investigate the join first.

If queueing consumes most user latency, investigate concurrency first.

## 133. Validate Every Change

After remediation:

```text
Run query
Capture new query ID
Open Query Profile
Compare metrics
Validate result correctness
Validate cost
```

## 134. Performance Without Correctness Is Failure

A query that runs faster but returns incorrect data is not optimized.

Always validate row count, aggregates, business results, and data completeness.

---

# Acceptance Criteria

The chapter is complete when you can:

- capture a Snowflake query ID
- use Query History before Query Profile
- separate queueing from execution
- navigate the Query Profile mental model
- identify the dominant operator
- analyze table scans
- compare partitions scanned vs total
- evaluate pruning effectiveness
- analyze bytes scanned
- analyze filter reduction
- investigate joins
- detect join explosion
- validate join cardinality
- identify duplicate-key problems
- analyze aggregation operators
- recognize high-cardinality aggregation
- understand DISTINCT cost
- identify DISTINCT used to hide bad joins
- analyze sort operators
- analyze window functions
- understand data redistribution
- detect data skew
- interpret local spill
- interpret remote spill
- trace spill to an operator
- avoid blindly resizing warehouses
- account for queueing
- account for caching
- compare warehouse sizes responsibly
- build before/after comparisons
- compare known-good historical executions
- execute a production Query Profile workflow
- analyze scan root causes
- analyze join root causes
- analyze sort root causes
- analyze aggregation root causes
- analyze window-function root causes
- use multiple representative queries during incidents
- combine Query Profile with workload metrics
- use a production investigation checklist
- execute the slow-query runbook
- capture evidence in a standard template
- validate remediation with a new query ID
- validate both performance and correctness

---

## Key Takeaways

Do not troubleshoot Snowflake query performance only from total duration.

Start with:

```text
Query ID
   |
   v
Query History
   |
   v
Queue vs Execution
```

If execution is the problem:

```text
Query Profile
   |
   v
Dominant Operator
```

Then follow the data:

```text
Input Rows
    |
    v
Operator
    |
    v
Output Rows
```

Look specifically for excessive scanning, poor pruning, join explosion, large aggregation, large sorting, window-function pressure, data redistribution, skew, local spill, and remote spill.

The goal is not to make the Query Profile look cleaner.

The goal is to identify the actual dominant bottleneck, correct it, and prove the improvement with before/after evidence.

A strong performance finding sounds like:

> The query scanned 96% of the table's micro-partitions, even though the request covered one day of data.

or:

> The join expanded 200 million input rows into 3 billion intermediate rows and caused 400 GB of remote spill.

That evidence tells the team what to fix.

The next chapter is **Chapter 38 — Micro-Partitions & Pruning**.
