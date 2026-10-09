# Chapter 001 — What Is Databricks?

**Part:** 01 — Foundations & Architecture  
**Level:** Beginner  
**Estimated time:** 45–75 minutes, excluding workspace provisioning  
**Content status:** Authored  
**Lab status:** Implemented in this chapter; not executed in a Databricks workspace during authoring  
**Prerequisites:** Basic SQL, an understanding of files and databases, and access to a lab workspace for the practical section  
**Last reviewed:** 2026-10-09

## 1. Learning objectives

After this chapter, you should be able to:

- Explain what Databricks does in a data platform.
- Distinguish storage, compute, workspace, and governance.
- Identify the roles of Spark, Delta Lake, Unity Catalog, jobs, and MLflow.
- Explain how application backends consume trained models.
- Run a small SQL transformation and validate its result.
- Separate a notebook result from a durable table.
- Identify basic operational risks and collect useful troubleshooting evidence.

## 2. What is Databricks?

Databricks is a cloud platform for building data pipelines, analyzing data, and developing and deploying machine learning and AI solutions. Teams use notebooks, SQL, scheduled jobs, and managed platform services to work with data.

A simple example is a daily encounter reporting pipeline:

1. Source systems produce encounter records.
2. A pipeline reads those records.
3. Transformations validate fields and remove duplicates.
4. The pipeline stores cleaned records in tables.
5. Analysts query those tables.
6. A data science team may use the same governed data to train a model.

Databricks supplies the environment and tools for those activities. Your team still defines the transformation logic, quality rules, access policies, operational targets, and business meaning of the results.

### 2.1 Why teams use it

Without a common platform, a team may manage separate scripts, processing clusters, storage layouts, schedulers, permissions, and model artifacts. Databricks brings many of these functions into one environment.

It is useful when data engineering, SQL analytics, and machine learning need to work with shared datasets. A small application with a few straightforward database queries may not need a distributed processing platform.

### 2.2 What “lakehouse” means

A data lake stores files in object storage such as Amazon S3, Azure storage, or Google Cloud Storage. A lakehouse adds table and management capabilities so teams can use that storage for reliable data processing and analytics.

Delta Lake is one technology used for these tables. A Delta table includes data files and a transaction log. The log records committed changes and supports capabilities such as transactional writes and table history.

Do not equate a notebook with a data lake, or a compute cluster with the permanent location of all data.

## 3. Core components and responsibilities

| Component | Responsibility | Example |
|---|---|---|
| Workspace | Organizes collaboration and development assets | Notebook, query, job definition |
| Notebook | Holds interactive code, text, and outputs | SQL transformation with Python validation |
| Compute | Executes code and queries | Notebook compute or SQL warehouse |
| Apache Spark | Distributed data processing engine | Join and aggregate a large dataset |
| Cloud object storage | Stores durable files and table data | Approved S3-backed storage |
| Delta Lake | Provides transactional table storage | Cleaned encounter table |
| Unity Catalog | Governs supported data and AI assets | Catalog/schema/table permissions |
| Lakeflow Jobs | Orchestrates task execution | Run ingest, transform, then quality checks |
| MLflow | Tracks ML runs and packages models | Training parameters, metrics, model artifacts |
| Model Serving | Exposes supported deployed models through endpoints | Backend sends a prediction request |

A notebook can use Spark without your team manually creating a Spark cluster. The available execution model depends on the workspace and chosen compute.

### 3.1 Storage and compute are different

**Storage** holds durable data. **Compute** reads that data, performs work, and writes results.

Stopping compute normally does not delete properly stored tables. A temporary view, local variable, or notebook output is not an equivalent durable storage mechanism.

### 3.2 Governance and cloud access are different layers

A user may need permission to use a catalog and schema, plus permission on a table. The platform also needs an authorized route to the underlying cloud storage.

For example, fixing an S3 IAM policy alone does not necessarily fix a Unity Catalog permission error. Likewise, a catalog grant does not automatically resolve a broken network route to a source database.

### 3.3 Workspace, account, and cloud

A workspace is a working environment for users and workloads. The Databricks account provides broader administration. The underlying cloud supplies infrastructure and storage services.

Classic and serverless deployments have different compute and networking boundaries. Do not assume every workload runs inside your own VPC or VNet. Chapter 003 examines these boundaries.

## 4. Where Databricks fits in your environment

| System | Typical role in this example |
|---|---|
| MongoDB / PostgreSQL | Source operational records |
| Kafka / MSK | Transport events |
| Databricks | Ingest, transform, analyze, and train models |
| Snowflake | Analytics and warehousing where selected by the architecture |
| Kubernetes | Runs application containers and other workloads |
| TrueFoundry | Helps deploy and operate applications/model services on Kubernetes |
| Application backend | Retrieves results or calls/loads a model |
| UI | Accepts user input and displays results |

These responsibilities overlap in real systems. Choose a flow deliberately rather than copying data through every platform.

### 4.1 Example data flow

A source export lands in object storage. Databricks creates cleaned encounter tables and daily facility aggregates. A dashboard reads the aggregates.

A scheduled pipeline should also record source counts, accepted rows, rejected rows, and freshness. A successful job with incomplete input is not automatically a successful business outcome.

### 4.2 How applications use trained models

There are three common patterns:

| Pattern | What happens after training | Application behavior |
|---|---|---|
| Packaged model | A trusted model artifact and dependencies are delivered to the backend | Backend loads the model and predicts locally |
| Model endpoint | A model is deployed as a separate service | Backend sends an authenticated API request |
| Batch predictions | A job scores records and stores prediction results | Backend reads precomputed predictions |

A scikit-learn model may be exported as a `.joblib` or `.pkl` artifact. The package also needs compatible libraries, preprocessing, feature ordering, and a model version. These artifacts must come from a trusted source because loading pickle-based formats can execute code.

For larger models, an API service can provide independent scaling and specialized compute. Large language models may use compatible serving engines such as vLLM.

Databricks can handle training and model management. Serving may happen in Databricks or in another environment such as Kubernetes through TrueFoundry. The UI typically communicates with the application backend rather than loading a Python model file itself.

Chapters 076–080 provide complete packaging and application integration labs. This chapter does not train or deploy a model.

## 5. Lab — Inspect the workspace and process synthetic records

### 5.1 Lab outcomes

You will:

1. Identify the workspace and available compute.
2. Run a session-only SQL transformation.
3. Validate deterministic results with Python.
4. Demonstrate how a duplicate affects an aggregation.
5. Optionally persist and inspect a disposable Delta table.
6. Remove the lab objects.

The core path creates temporary views only. The optional persistence path requires an approved catalog and schema. No external files, credentials, production data, or source connectors are required.

### 5.2 Requirements and availability

- A Databricks workspace with permission to create a notebook.
- Permission to use approved notebook compute capable of SQL and Python/Spark.
- Serverless or a currently supported Databricks Runtime, as available.
- For optional persistence: Unity Catalog-compatible compute, an approved managed-storage location, and suitable catalog/schema/table privileges.
- Budget or quota for running the selected compute.

The UI can vary by cloud and release. Use the current notebook and compute controls in your workspace. If you cannot access compute, complete the conceptual inventory and mark the execution lab **Blocked**. Do not count a paper exercise as platform validation.

A SQL warehouse can execute the SQL portions, but the Python assertions require compatible notebook compute. If you use only SQL, compare results manually and record that limitation.

### 5.3 Step 1 — Record the environment

Create a notebook named `dbx-ch001-what-is-databricks` in your own lab folder. Choose Python as the default language and connect approved compute.

Record these details in a Markdown cell:

| Field | Your value |
|---|---|
| Execution date | |
| Cloud and region | |
| Workspace identifier or approved label | |
| Notebook compute type | |
| Runtime version, if exposed | |
| Unity Catalog available? | |
| Approved lab catalog/schema, if applicable | |
| Budget/quota constraint | |
| Execution status | Not started |

Do not infer a region from an unfamiliar workspace URL. Use workspace metadata or an administrator-provided value.

In a SQL cell, run:

```sql
SELECT
  current_user() AS executing_identity,
  current_catalog() AS current_catalog,
  current_schema() AS current_schema;
```

If the notebook cell is Python by default, add `%sql` as its first line before pasting SQL. The SQL code blocks in this chapter omit that notebook magic.

**Expected:** One row with your execution identity and current namespace. Values differ by environment. Keep sensitive identity details out of public screenshots.

### 5.4 Step 2 — Create a temporary synthetic dataset

Run in a SQL cell:

```sql
CREATE OR REPLACE TEMP VIEW ch001_encounters AS
SELECT *
FROM VALUES
  ('E001', 'P001', 'North', 'complete', 120),
  ('E002', 'P002', 'North', 'complete',  60),
  ('E003', 'P003', 'South', 'complete',  90),
  ('E004', 'P004', 'South', 'pending',   30),
  ('E005', 'P005', 'North', 'complete',  30)
AS records(encounter_id, patient_id, facility, status, duration_minutes);
```

Inspect it:

```sql
SELECT *
FROM ch001_encounters
ORDER BY encounter_id;
```

**Expected:** Five rows, E001 through E005. All names and values are synthetic.

The `VALUES` clause is our input for this introductory exercise. It demonstrates data processing without building ingestion infrastructure. A real source ingestion lab comes later.

### 5.5 Step 3 — Validate the input

```sql
SELECT
  COUNT(*) AS total_rows,
  COUNT(DISTINCT encounter_id) AS unique_encounters,
  SUM(CASE WHEN status = 'complete' THEN 1 ELSE 0 END) AS complete_rows,
  SUM(CASE WHEN status = 'pending' THEN 1 ELSE 0 END) AS pending_rows
FROM ch001_encounters;
```

**Expected:**

| total_rows | unique_encounters | complete_rows | pending_rows |
|---|---|---|---|
| 5 | 5 | 4 | 1 |

A count check gives you a baseline before transformation. In production, also validate source completeness and key constraints.

### 5.6 Step 4 — Transform the records

```sql
CREATE OR REPLACE TEMP VIEW ch001_facility_summary AS
SELECT
  facility,
  COUNT(*) AS completed_encounters,
  SUM(duration_minutes) AS total_minutes,
  AVG(duration_minutes) AS average_minutes
FROM ch001_encounters
WHERE status = 'complete'
GROUP BY facility;
```

Query the result:

```sql
SELECT *
FROM ch001_facility_summary
ORDER BY facility;
```

**Expected:**

| facility | completed_encounters | total_minutes | average_minutes |
|---|---|---|---|
| North | 3 | 210 | 70.0 |
| South | 1 | 90 | 90.0 |

Numeric display formatting may differ. The pending encounter is excluded deliberately.

### 5.7 Step 5 — Assert the results with Python

Run in a Python cell:

```python
source_counts = spark.sql("""
    SELECT COUNT(*) AS rows,
           COUNT(DISTINCT encounter_id) AS unique_ids
    FROM ch001_encounters
""").first()

assert source_counts["rows"] == 5
assert source_counts["unique_ids"] == 5

actual = {
    row["facility"]: (
        int(row["completed_encounters"]),
        int(row["total_minutes"]),
        float(row["average_minutes"]),
    )
    for row in spark.sql("""
        SELECT facility, completed_encounters, total_minutes, average_minutes
        FROM ch001_facility_summary
    """).collect()
}

expected = {
    "North": (3, 210, 70.0),
    "South": (1, 90, 90.0),
}

assert actual == expected, f"Unexpected summary: {actual}"
print("PASS: source counts and facility summary")
```

**Expected:**

```text
PASS: source counts and facility summary
```

Collecting two aggregate rows is appropriate here. Do not copy this pattern to collect millions of rows into driver memory.

### 5.8 Step 6 — Demonstrate a duplicate-data problem

Create a separate view so the original baseline remains intact:

```sql
CREATE OR REPLACE TEMP VIEW ch001_encounters_with_duplicate AS
SELECT * FROM ch001_encounters
UNION ALL
SELECT * FROM ch001_encounters WHERE encounter_id = 'E001';
```

Find the duplicate:

```sql
SELECT encounter_id, COUNT(*) AS occurrences
FROM ch001_encounters_with_duplicate
GROUP BY encounter_id
HAVING COUNT(*) > 1;
```

**Expected:** E001 has two occurrences.

Observe the impact:

```sql
SELECT facility, COUNT(*) AS completed_encounters,
       SUM(duration_minutes) AS total_minutes
FROM ch001_encounters_with_duplicate
WHERE status = 'complete'
GROUP BY facility
ORDER BY facility;
```

**Expected:** North now has 4 completed rows and 330 minutes; South still has 1 and 90. The query runs successfully, but its business result is wrong.

For this deliberately identical duplicate, remove repeated rows:

```sql
CREATE OR REPLACE TEMP VIEW ch001_encounters_deduplicated AS
SELECT DISTINCT *
FROM ch001_encounters_with_duplicate;
```

Validate in Python:

```python
assert spark.table("ch001_encounters_with_duplicate").count() == 6
assert spark.table("ch001_encounters_deduplicated").count() == 5
assert (
    spark.table("ch001_encounters_deduplicated")
    .select("encounter_id")
    .distinct()
    .count()
) == 5
print("PASS: exact duplicate detected and removed")
```

**Expected:** The PASS message.

`DISTINCT` only removes identical rows. If two rows have the same encounter ID and different values, it does not select the newest or correct version. Production deduplication needs business keys, event ordering, and a tie-break rule. Those topics appear later in the series.

### 5.9 Step 7 — Optional: persist a managed Delta table

Skip this step if you do not have an approved writable namespace.

Ask your platform administrator for the approved lab catalog and schema. Typical permissions include `USE CATALOG`, `USE SCHEMA`, and `CREATE TABLE`; creating a schema additionally requires the relevant catalog privilege. Inspecting all grants may require additional access.

In a SQL cell, replace the two namespace placeholders:

```sql
USE CATALOG <approved_lab_catalog>;
USE SCHEMA <approved_lab_schema>;
```

Replace angle-bracket placeholders before execution. Use backticks around identifiers that require quoting.

Choose a table name unique to this run, such as `ch001_facility_summary_sam_20261009a`. Substitute your own unique name consistently below. Check first that it is unused:

```sql
SHOW TABLES LIKE 'ch001_facility_summary_sam_20261009a';
```

**Expected:** No matching table. If one exists, choose another name.

Create the table without replacing any existing table:

```sql
CREATE TABLE ch001_facility_summary_sam_20261009a
USING DELTA
AS SELECT * FROM ch001_facility_summary;
```

Inspect it:

```sql
SELECT *
FROM ch001_facility_summary_sam_20261009a
ORDER BY facility;

DESCRIBE DETAIL ch001_facility_summary_sam_20261009a;

DESCRIBE HISTORY ch001_facility_summary_sam_20261009a;
```

Run statements individually if your editor does not execute them together.

**Expected:**

- Two summary rows with the baseline values.
- Table detail identifies the Delta format.
- History shows the table creation/write commit.
- Catalog Explorer shows the table in your chosen catalog/schema.

The table data is stored in the configured managed storage, not in the temporary view. Detail output can include the location; do not publish internal storage paths unnecessarily.

Open a separate notebook attached to compatible compute, select the same catalog/schema, and query this table. It should remain readable if you have the necessary privileges. The temporary views from the original notebook are session-scoped and should not be used as cross-session dependencies.

### 5.10 Step 8 — Map observations to the platform

| Observation | Component demonstrated |
|---|---|
| You created a notebook | Workspace/development asset |
| SQL produced results | Compute execution |
| A transformation filtered and aggregated rows | Data processing |
| You selected a catalog/schema | Namespace context |
| Optional table used Delta and had history | Durable transactional table |
| Optional table appeared in Catalog Explorer | Governed table metadata |
| Duplicate passed through successful SQL | Need for explicit data quality |

This lab does not prove streaming reliability, autoscaling, permissions isolation, model training, or production performance. It provides the first observable foundation for those later labs.

## 6. Acceptance checklist and evidence

| Check | Passing evidence |
|---|---|
| Environment identified | Inventory includes compute type and known limitations |
| Notebook executes | Identity query succeeds |
| Input is correct | Counts are 5 total / 5 unique / 4 complete / 1 pending |
| Summary is correct | North = 3, 210, 70; South = 1, 90, 90 |
| Assertions pass | First Python PASS message |
| Duplicate failure understood | E001 appears twice; North is inflated to 4 / 330 |
| Exact duplicate removed | Second Python PASS message |
| Optional persistence verified | Delta detail/history and second-session table query, or explicitly skipped |
| Components understood | Completed observation mapping |
| Cleanup completed | Temporary views removed; optional disposable table dropped |

Save the notebook and a short evidence note containing execution date, environment, results, skipped sections, and failure resolutions. Do not include tokens or confidential identifiers.

Mark the core lab validated only after the actual workspace checks pass. Track optional persistence separately. During authoring, these checks have not been executed against a Databricks workspace.

## 7. Production considerations

### Permissions

Use dedicated service identities and least privilege for production jobs. Notebook access, compute access, data-object permissions, cloud credentials, and source-network access can fail independently.

### Repeated runs

The core lab replaces temporary views, so it can be rerun without appending records. The optional table deliberately uses `CREATE TABLE`, which fails if the name already exists. Production jobs need an explicit append, merge, or replacement strategy with safe replay behavior.

### Data quality

Successful execution does not prove source completeness or correctness. Track duplicates, missing keys, invalid values, rejected records, and freshness. The duplicate lab demonstrates why job success alone is insufficient.

### Cost and performance

The dataset has five rows and is not a scale benchmark. Use approved small compute and its available idle controls. Investigate query plans and workload behavior before increasing resources.

### Recovery

Temporary views can be reconstructed from notebook cells. A durable table requires an appropriate recovery policy. Delta history/time travel has retention boundaries and does not replace a complete disaster recovery strategy.

### Models

A delivered model needs its preprocessing, feature contract, dependencies, quality evidence, and version. Model serving additionally needs authentication, capacity, timeouts, monitoring, and rollback. Training does not automatically integrate a model into an application.

## 8. Troubleshooting

| Symptom | Evidence to inspect | Likely cause | Corrective action |
|---|---|---|---|
| Notebook cannot connect | Compute selector, permissions, compute events | Missing access or unavailable compute | Use approved available compute; request the specific missing access |
| Notebook cell treats SQL as Python | Cell language and error location | SQL pasted into a Python cell | Set SQL language or add `%sql` |
| `spark` is undefined | Execution environment | Code is running outside a Spark notebook | Use supported Databricks notebook compute |
| Temp view not found | Notebook/session and prior cell results | Setup cell missing, session reset, or different session | Rerun source and summary cells in order |
| Assertion fails | Actual rows and preceding cell output | Edited dataset or different transformation | Compare the five baseline records and filter condition |
| Optional table creation denied | Full error class, current catalog/schema, approved grants | Missing namespace/table privilege | Obtain narrowly scoped required privileges |
| Storage error during optional creation | Table namespace, storage error, platform configuration | Managed-storage setup or cloud access problem | Have the platform owner verify managed storage and credentials |
| Table already exists | `SHOW TABLES` result | Name reused | Choose a new unique table name; do not overwrite unknown objects |
| Duplicate remains after `DISTINCT` | All values for the repeated key | Same key with different field values | Define ordering/version rules rather than dropping arbitrary records |
| Feature unavailable | Cloud/region/edition and policy | Workspace limitation | Record the blocked optional path and continue supported core steps |

Capture the error class, timestamp, failing statement, namespace, and compute type. These details are more useful than a screenshot stating only “it failed.”

## 9. Cleanup and rollback

Run in the original notebook:

```sql
DROP VIEW IF EXISTS ch001_encounters_deduplicated;
DROP VIEW IF EXISTS ch001_encounters_with_duplicate;
DROP VIEW IF EXISTS ch001_facility_summary;
DROP VIEW IF EXISTS ch001_encounters;
```

If you created the optional table, select the same approved catalog/schema, confirm the table name is the one created for this lab, and drop that table only:

```sql
DROP TABLE IF EXISTS ch001_facility_summary_sam_20261009a;
```

Use your actual unique name. Do not drop the shared catalog or schema. Managed-table cleanup follows platform lifecycle rules; dropping a table does not promise immediate physical byte deletion.

Disconnect the notebook. Stop compute only if it is dedicated to your lab; do not terminate shared compute. Remove the disposable notebook when you no longer need it, or retain it as execution evidence.

To repeat the lab, run the temporary-view setup again and choose a fresh optional table name. No production data was changed by this exercise.

## 10. Review questions

1. What is the difference between storage and compute?
2. Why does a successful SQL query not prove correct data?
3. What does Unity Catalog govern?
4. What is different about a temporary view and a Delta table?
5. Does an application always need to call a model API?
6. Why can’t a `.joblib` file alone be treated as a complete deployment package?
7. What evidence would you collect for a permission error?
8. Which parts of this lab have not validated production readiness?

### Answer guide

1. Storage holds data; compute executes operations on it.
2. Duplicate, incomplete, or invalid input can still produce a successful result.
3. Supported data and AI assets through metadata, ownership, privileges, and related governance capabilities.
4. A temporary view is session-scoped; a Delta table persists data and transaction history.
5. No. The backend may load a packaged model or read batch predictions instead.
6. Dependencies, preprocessing, feature ordering, trust, and version compatibility are also required.
7. Identity, namespace, failing operation, full error, compute type, timestamp, and relevant grants.
8. Scale, streaming, access isolation, ML deployment, reliability, and recovery policies still need dedicated validation.

## 11. Official references

These sources support the platform concepts and notebook/table workflow. SQL fixtures and assertions in this chapter are original tutorial examples.

- [What is Databricks?](https://docs.databricks.com/aws/en/introduction/)
- [What is a data lakehouse?](https://docs.databricks.com/aws/en/lakehouse/)
- [Query and visualize data from a notebook](https://docs.databricks.com/aws/en/getting-started/quick-start)
- [Create your first table and grant privileges](https://docs.databricks.com/aws/en/getting-started/create-table)
- [Unity Catalog introduction](https://docs.databricks.com/aws/en/data-governance/unity-catalog/)
- [MLflow on Databricks](https://docs.databricks.com/aws/en/mlflow/)
- [Model Serving](https://docs.databricks.com/aws/en/machine-learning/model-serving/)

Use the documentation cloud selector for Azure or GCP. Check your actual workspace for regional and GovCloud availability.

## 12. Navigation and progress

**Previous:** [Databricks Tutorial Master Plan](../MASTER-PLAN.md)  
**Current:** Chapter 001 — What Is Databricks?  
**Next:** [Chapter 002 — Data Lakes, Warehouses & Lakehouses](002-data-lakes-warehouses-lakehouses.md)

| Item | Status |
|---|---|
| Chapter 001 content | Authored |
| Core lab | Implemented; workspace execution pending |
| Optional persistence lab | Implemented; workspace execution pending |
| Repository publication | Included in the Databricks rebuild commit; see Git history |
| Series authored | 1/100 chapters |
| Series workspace-validated | 0/100 labs |

This chapter is ready for execution and review. It is not marked fully complete under the master plan’s validation rules.

