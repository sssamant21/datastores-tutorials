# Chapter 002 — Data Lakes, Warehouses & Lakehouses

**Part:** 01 — Foundations & Architecture  
**Level:** Beginner  
**Estimated time:** 60–90 minutes, excluding provisioning  
**Prerequisite:** Chapter 001 and basic SQL/Python  
**Content status:** Authored  
**Lab status:** Implemented; Databricks workspace execution pending  
**Last reviewed:** 2026-10-09

## 1. Learning objectives

- Explain the purposes of a data lake, warehouse, and lakehouse.
- Separate file format, table format, catalog, and compute.
- Compare JSON, Parquet, and Delta using identical records.
- Query a curated dataset and inspect a committed table update.
- Recognize schema, retention, governance, and recovery boundaries.
- Select an architecture based on requirements rather than product labels.

## 2. Three approaches to organizing analytical data

### 2.1 Data lake

A data lake stores data in object storage, often as JSON, CSV, Parquet, images, or other files. It can preserve raw inputs for later processing and support many workloads.

Flexibility is useful, but unmanaged files can become difficult to discover, validate, and operate. A directory of files does not automatically provide table transactions, business-key uniqueness, lineage, or access reviews.

A lake can still have strong governance and explicit schemas. “Schema on read” describes a common approach, not a rule that all lake data must be unstructured.

### 2.2 Data warehouse

A data warehouse organizes data for analytical querying and reporting. Teams often use curated tables, consistent business definitions, dimensional models, and SQL interfaces.

For example, analysts may query daily completed encounters by facility without understanding the source JSON structure.

Modern warehouses can also process semi-structured data and support additional workloads. Avoid assuming that a warehouse can only store traditional rows or that it must use a particular physical storage architecture.

### 2.3 Data lakehouse

A lakehouse combines object-storage-based data with a table-management layer and analytics capabilities. On Databricks, Delta Lake is a principal table technology used for this pattern.

It lets teams process and query tables while retaining open storage foundations. The complete architecture also needs a catalog, access controls, compute, quality rules, orchestration, and operational practices.

A lakehouse does not eliminate the need to clean data. A Delta table can contain duplicates or incorrect business values if a pipeline writes them.

## 3. Compare responsibilities, not just names

| Dimension | Data lake | Data warehouse | Lakehouse |
|---|---|---|---|
| Typical organizing unit | Files and storage locations | Curated analytical tables | Governed tables and files on lake storage |
| Common use | Raw retention, exploration, processing | SQL reporting and business analytics | Shared engineering, analytics, and ML data |
| Schema | Can be applied while reading or writing | Commonly managed at table boundaries | Managed at table boundaries; raw layers remain flexible |
| Transactions | Depend on additional table/management technology | Provided by the warehouse system | Provided by the selected table technology |
| Governance | Must be designed and implemented | Usually integrated into platform controls | Catalog and platform controls govern supported assets |
| Main risk | Unmanaged files and inconsistent interpretation | Poor modeling, freshness, workload contention | Assuming table technology solves all operational problems |

Capabilities depend on the implementation. This table describes patterns rather than universal limits.

### 3.1 File format versus table format

| Item | What it provides | What it does not provide by itself |
|---|---|---|
| JSON | Flexible record representation | A table-wide transaction log |
| Parquet | Columnar file storage with schema metadata | Transactional management of a directory of files |
| Delta Lake | Table protocol/log over data files, including Parquet | Correct business definitions or automatic deduplication |
| Unity Catalog | Catalog and governance for supported objects | Compute execution |
| SQL warehouse | Compute for analytical SQL | A separate category of file format |

A **SQL warehouse** in Databricks is a compute resource. Its name does not mean every table it queries resides in a separate traditional warehouse storage system.

### 3.2 Example architecture

Raw encounter records arrive as JSON. A transformation validates types and business keys, writes a cleaned Delta table, and produces a facility reporting aggregate. SQL users query the aggregate; ML workloads may use the cleaned table.

Bronze/silver/gold names describe stages of refinement. They do not require three separate physical platforms. Detailed medallion design comes in Part 08.

## 4. When to choose each pattern

- Preserve raw files when replay, audit, or source fidelity matters.
- Use curated analytical tables when consumers need stable definitions and predictable SQL.
- Use a lakehouse when engineering, analytics, and ML need shared table data on lake storage.
- Use multiple platforms when there is a concrete requirement for them; document ownership, synchronization, and recovery.

For your environment, MongoDB or PostgreSQL can remain operational sources. Databricks may prepare data for analytics or ML. Snowflake may remain an analytics destination if that is the chosen architecture. Avoid adding an extra data copy without identifying its consumer and benefit.

## 5. Lab requirements and resource boundaries

This lab compares three representations of five synthetic records. It demonstrates a lakehouse table and a warehouse-style SQL query in Databricks. It does **not** provision or benchmark a separate warehouse product.

You need:

- A Python notebook with approved Spark-capable compute.
- Unity Catalog and a currently supported runtime with volume support. Volume support requires Databricks Runtime 13.3 LTS or later on classic compute; use a currently supported version rather than selecting an old minimum.
- An approved catalog/schema with managed table storage.
- USE CATALOG, USE SCHEMA, and CREATE TABLE privileges.
- A preapproved writable volume with READ VOLUME and WRITE VOLUME privileges.
- Permission and budget to use compute.

An administrator can supply a volume, or create a managed volume in an approved namespace:

```sql
CREATE VOLUME <approved_catalog>.<approved_schema>.<new_lab_volume>;
```

This additionally requires CREATE VOLUME and appropriate namespace privileges. Replace placeholders before executing; do not reuse an existing object name.

**Important:** Volumes hold the JSON and Parquet files in this lab. Register the Delta table by name in the catalog; do not create a registered table inside a volume.

If permissions are unavailable, mark the relevant exercise blocked. Do not substitute local ephemeral storage and claim persistent lake validation.

## 6. Hands-on lab

### Step 1 — Configure your isolated run

Create notebook `dbx-ch002-lakes-warehouses-lakehouses`. Record date, cloud, region, compute/runtime, namespace, volume, and skipped checks.

Run this Python cell after replacing placeholders:

```python
import re
import uuid

catalog = "REPLACE_WITH_APPROVED_CATALOG"
schema_name = "REPLACE_WITH_APPROVED_SCHEMA"
volume = "REPLACE_WITH_APPROVED_VOLUME"

for value in (catalog, schema_name, volume):
    assert "REPLACE_WITH" not in value, "Configure your approved namespace"
    assert re.fullmatch(r"[A-Za-z_][A-Za-z0-9_]*", value), (
        "This beginner lab uses simple identifiers only"
    )

run_id = uuid.uuid4().hex[:12]
base_path = f"/Volumes/{catalog}/{schema_name}/{volume}/ch002_{run_id}"
json_path = f"{base_path}/raw_json"
parquet_path = f"{base_path}/curated_parquet"
table_name = f"ch002_encounters_{run_id}"
table = f"`{catalog}`.`{schema_name}`.`{table_name}`"

assert not spark.catalog.tableExists(table)
print("Run ID:", run_id)
print("Lab directory:", base_path)
print("Delta table:", table)
```

Keep these variables for cleanup. Every run gets a new table and directory. No overwrite mode is used.

### Step 2 — Define the five synthetic records

```python
from pyspark.sql import functions as F
from pyspark.sql.types import StructType, StructField, StringType, IntegerType

record_schema = StructType([
    StructField("encounter_id", StringType(), False),
    StructField("patient_id", StringType(), False),
    StructField("facility", StringType(), False),
    StructField("status", StringType(), False),
    StructField("duration_minutes", IntegerType(), False),
])

records = [
    ("E001", "P001", "North", "complete", 120),
    ("E002", "P002", "North", "complete", 60),
    ("E003", "P003", "South", "complete", 90),
    ("E004", "P004", "South", "pending", 30),
    ("E005", "P005", "North", "complete", 30),
]

source = spark.createDataFrame(records, record_schema)
assert source.count() == 5
display(source.orderBy("encounter_id"))
```

**Expected:** Five rows. These are educational records, not patient data.

### Step 3 — Write and read raw JSON

```python
source.write.mode("errorifexists").json(json_path)

raw = spark.read.schema(record_schema).json(json_path)
assert raw.count() == 5
display(raw.orderBy("encounter_id"))

files = dbutils.fs.ls(json_path)
json_files = [item.path for item in files if item.name.endswith(".json")]
assert json_files, "No JSON data files found"
print(dbutils.fs.head(json_files[0], 1024))
```

**Expected:** JSON records readable as text, plus five rows when Spark reads the directory. Spark can create multiple part files; file count and order are not fixed.

Using an explicit read schema prevents reliance on inference. It does not impose all business rules; missing JSON values can still become null.

### Step 4 — Write and read Parquet

```python
raw.write.mode("errorifexists").parquet(parquet_path)
parquet = spark.read.parquet(parquet_path)

assert parquet.count() == 5
parquet.printSchema()
display(parquet.orderBy("encounter_id"))
display(dbutils.fs.ls(parquet_path))
```

**Expected:** Five records, a schema including integer duration_minutes, and one or more Parquet part files.

Parquet is a binary columnar format. Read it through a compatible engine. Do not expect a text preview to show JSON-like records. Nullability reported after file reads may differ from the original DataFrame declaration.

### Step 5 — Create a managed Delta table

```python
parquet.write.format("delta").mode("errorifexists").saveAsTable(table)
delta = spark.table(table)

assert delta.count() == 5
display(spark.sql(f"DESCRIBE DETAIL {table}"))
display(spark.sql(f"DESCRIBE HISTORY {table}"))
```

**Expected:** Detail shows Delta format; history contains the initial write. The managed table has its own platform-managed location, separate from the volume directory.

### Step 6 — Prove the representations contain the same data

```python
columns = [field.name for field in record_schema.fields]

def assert_same_rows(left, right):
    left = left.select(*columns)
    right = right.select(*columns)
    assert left.exceptAll(right).count() == 0
    assert right.exceptAll(left).count() == 0

assert_same_rows(source, raw)
assert_same_rows(source, parquet)
assert_same_rows(source, delta)
print("PASS: JSON, Parquet, and Delta contain the same five records")
```

Both directions matter: one direction alone can miss extra rows. exceptAll also preserves duplicate multiplicity. Row order is not part of this equality check.

### Step 7 — Run a warehouse-style analytical query

```python
summary = spark.sql(f"""
    SELECT facility,
           COUNT(*) AS completed_encounters,
           SUM(duration_minutes) AS total_minutes,
           AVG(duration_minutes) AS average_minutes
    FROM {table}
    WHERE status = 'complete'
    GROUP BY facility
    ORDER BY facility
""")
display(summary)

actual = {
    row["facility"]: (
        int(row["completed_encounters"]),
        int(row["total_minutes"]),
        float(row["average_minutes"]),
    )
    for row in summary.collect()
}
assert actual == {
    "North": (3, 210, 70.0),
    "South": (1, 90, 90.0),
}
print("PASS: analytical query returns expected facility metrics")
```

**Expected:**

| facility | completed_encounters | total_minutes | average_minutes |
|---|---|---|---|
| North | 3 | 210 | 70.0 |
| South | 1 | 90 | 90.0 |

This demonstrates SQL analytics over a lakehouse table. Optionally query the same named table from an approved SQL warehouse. Verify it is configured for your catalog and identity.

### Step 8 — Observe a transactional update and prior version

Record the current Delta version, then change the pending encounter:

```python
before_version = int(
    spark.sql(f"DESCRIBE HISTORY {table}")
    .orderBy(F.desc("version"))
    .first()["version"]
)

spark.sql(f"""
    UPDATE {table}
    SET status = 'complete'
    WHERE encounter_id = 'E004'
""")

display(spark.sql(f"DESCRIBE HISTORY {table}"))

current_complete = spark.sql(f"""
    SELECT COUNT(*) AS n FROM {table} WHERE status = 'complete'
""").first()["n"]

previous_complete = spark.sql(f"""
    SELECT COUNT(*) AS n
    FROM {table} VERSION AS OF {before_version}
    WHERE status = 'complete'
""").first()["n"]

assert current_complete == 5
assert previous_complete == 4
assert spark.table(table).count() == 5
print("PASS: current state has five completed encounters; prior version has four")
```

**Expected:** A new update entry in history and both count checks passing.

The JSON and Parquet copies remain unchanged. Updating the Delta table does not synchronize separate copies automatically.

Time travel requires retained metadata and data files. This fresh-table test does not establish long-term recovery guarantees. Do not run VACUUM or modify table data files manually during this lab.

### Step 9 — Validate unchanged copies and a business-data edge case

```python
assert raw.filter(F.col("status") == "complete").count() == 4
assert parquet.filter(F.col("status") == "complete").count() == 4

duplicate_input = source.unionByName(
    source.filter(F.col("encounter_id") == "E001")
)
duplicate_keys = (
    duplicate_input.groupBy("encounter_id")
    .count()
    .filter(F.col("count") > 1)
)
assert duplicate_input.count() == 6
assert duplicate_keys.count() == 1
display(duplicate_keys)
print("PASS: independent copies stay unchanged; duplicate key requires validation")
```

**Expected:** E001 has count 2. This edge case stays in memory and is not appended to the table.

Delta transactions do not automatically enforce a unique encounter_id. Quality rules and merge/deduplication logic must address that requirement.

## 7. What you have demonstrated

| Observation | Meaning |
|---|---|
| JSON records are visible as text | Raw flexible record representation |
| Parquet stores the same rows with a schema | Columnar file representation |
| Delta has detail and commit history | Transactionally managed table representation |
| SQL aggregates the Delta table | Analytical consumption of lakehouse data |
| UPDATE changes current state | Supported table operation |
| Prior version has the old count | Retained version access |
| Other copies stay unchanged | Separate copies need explicit synchronization |
| Duplicate keys are possible in input | Business quality is a separate responsibility |

This comparison does not measure format speed, prove concurrent-write isolation, test disaster recovery, or compare Databricks with Snowflake performance.

## 8. Acceptance criteria and evidence

Record results in the notebook:

- Environment, namespace, volume, and unique run ID recorded.
- JSON, Parquet, and Delta each begin with five equivalent rows.
- Delta detail/history inspected.
- Initial analytical results match North 3/210/70 and South 1/90/90.
- Update produces five current completed rows; previous version has four.
- Raw and Parquet copies still have four completed rows.
- Duplicate E001 is detected.
- Disposable resources are removed.
- SQL warehouse access is separately marked executed, skipped, or blocked.

Keep error classes and execution timestamps with evidence. Do not publish credentials or internal storage paths. This chapter’s authoring checks do not replace execution in your workspace.

## 9. Production considerations

### Schema and contracts

Use explicit types and controlled schema evolution. Nullability in a source DataFrame is not a substitute for durable table constraints or business validation. Document allowed values, required fields, and identifier semantics.

### Ownership and governance

Govern raw files as well as curated tables. Volumes and tables are separate securables with different privileges. A lakehouse deployment needs both platform governance and correctly configured underlying storage access.

### Copies and freshness

The lab intentionally creates three copies to compare representations. Production designs should justify each copy and define its owner, refresh path, retention, reconciliation, and recovery procedure.

### Performance and cost

Five rows cannot establish performance superiority. Query workload, file size, layout, runtime, compute, data volume, and concurrency all affect results. Design a representative benchmark before making a platform decision.

### Retention and recovery

Time travel is bounded by retained history and data. Plan backup/recovery and RPO/RTO separately. Never manually remove Delta transaction logs or Parquet data files from a live Delta table.

### Raw fidelity

This lab generates JSON from typed records. A production raw layer may preserve the exact original source payload, including additional fields and parsing failures, for replay and audit.

## 10. Troubleshooting

| Symptom | Evidence | Likely cause | Corrective action |
|---|---|---|---|
| Configuration assertion fails | Placeholder values | Namespace not set or unsupported identifier | Configure approved simple identifiers |
| Volume path denied/not found | Full path and error class | Wrong volume or missing namespace/volume privileges | Verify path and READ/WRITE VOLUME access |
| Volume writes seem ephemeral | Runtime and storage evidence | Unsupported old runtime | Use supported volume-capable compute |
| CREATE TABLE fails | Namespace, grants, managed storage | Missing table permission or storage setup | Have owner verify grants and managed storage |
| Path/table already exists | Name and listing | Prior partial run | Preserve old evidence and use a new run ID |
| Equality check fails | Both exceptAll results | Input or schema changed | Compare types and records before proceeding |
| Parquet preview is unreadable | File extension/read method | Binary file treated as text | Read with Spark Parquet reader |
| Prior-version query fails | Version, history, retention | Wrong version or files no longer retained | Capture correct version; investigate retention |
| Summary differs after update | Query timing and table history | Current table now includes E004 | Expect updated results; use prior version for baseline |
| UPDATE succeeds but raw JSON differs | Independent file locations | Separate copies are not synchronized | Use explicit pipeline logic where synchronization is required |

Do not fix namespace errors by switching to an unapproved production schema.

## 11. Cleanup and rollback

The update affects only the disposable Delta table. Cleanup removes that table and the unique file directory. Run with the variables from Step 1:

```python
assert table_name.startswith("ch002_encounters_")
assert re.fullmatch(r"[a-f0-9]{12}", run_id)
assert base_path == f"/Volumes/{catalog}/{schema_name}/{volume}/ch002_{run_id}"

spark.sql(f"DROP TABLE IF EXISTS {table}")
dbutils.fs.rm(base_path, recurse=True)

assert not spark.catalog.tableExists(table)
remaining_names = {item.name.rstrip("/") for item in dbutils.fs.ls(
    f"/Volumes/{catalog}/{schema_name}/{volume}"
)}
assert f"ch002_{run_id}" not in remaining_names
print("PASS: disposable table and run directory removed")
```

Do not remove the shared volume, schema, or catalog. Managed table dropping follows platform lifecycle rules and does not promise immediate physical deletion.

If a session resets, recover exact resource names from your notebook evidence before cleanup. Do not delete a broad parent directory. Stop only lab-dedicated compute and save execution evidence.

## 12. Review questions and answers

1. **Is Parquet a lakehouse table format?** Parquet is a file format; additional table technology supplies transactional table management.
2. **Does a lakehouse replace quality checks?** No; duplicates, invalid values, and incomplete sources still need checks.
3. **Does a SQL warehouse own every queried table’s storage?** No; it is an execution resource.
4. **Why keep raw data?** Replay, source fidelity, debugging, and audit may require it.
5. **Why did JSON stay unchanged after UPDATE?** It was a separate copy with no synchronization pipeline.
6. **Does time travel guarantee recovery forever?** No; it depends on retained metadata and data.
7. **Should every system have all three representations?** No; production copies need a concrete purpose.
8. **Does this lab prove Delta is faster?** No; it validates behavior, not representative performance.

## 13. Official references

- [Data lakehouse concepts](https://docs.databricks.com/aws/en/lakehouse)
- [Delta Lake in Databricks](https://docs.databricks.com/aws/en/delta)
- [Read and write Parquet](https://docs.databricks.com/aws/en/query/formats/parquet)
- [Unity Catalog volumes](https://docs.databricks.com/aws/en/volumes/)
- [CREATE VOLUME](https://docs.databricks.com/aws/en/sql/language-manual/sql-ref-syntax-ddl-create-volume)
- [Delta best practices](https://docs.databricks.com/aws/en/delta/best-practices)
- [ACID guarantees](https://docs.databricks.com/aws/en/lakehouse/acid)

Examples and synthetic fixtures are original tutorial material. Check documentation for your cloud, runtime, region, and workspace policy before execution.

## 14. Navigation and progress

**Previous:** [Chapter 001 — What Is Databricks?](001-what-is-databricks.md)  
**Current:** Chapter 002 — Data Lakes, Warehouses & Lakehouses  
**Next:** [Chapter 003 — Control Plane, Compute Plane & Cloud Storage](003-control-plane-compute-plane-cloud-storage.md)

| Item | Status |
|---|---|
| Content | Authored |
| Lab | Implemented; workspace execution pending |
| Separate SQL warehouse check | Optional; execution pending |
| Repository publication | Included in the Databricks rebuild commit; see Git history |
| Series authored | 2/100 chapters |
| Series workspace-validated | 0/100 labs |

This chapter is ready for workspace execution and review; full completion requires the master plan’s validation evidence.

