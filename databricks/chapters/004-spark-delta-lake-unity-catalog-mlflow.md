# Chapter 004 — Spark, Delta Lake, Unity Catalog & MLflow

**Part:** 01 — Foundations & Architecture  
**Level:** Beginner  
**Estimated time:** 60–90 minutes  
**Prerequisites:** Chapters 001–003, basic SQL/Python, approved lab workspace  
**Content status:** Authored  
**Lab status:** Implemented; Databricks workspace execution pending  
**Last reviewed:** 2026-10-09

## 1. Learning objectives

- Identify which component processes data, stores table changes, governs access, and tracks experiments.
- Execute a Spark transformation and persist its result as a Delta table.
- Inspect a Unity Catalog object without bypassing its governed table access.
- Record a reproducible baseline evaluation in MLflow.
- Distinguish experiment tracking, model registration, and model serving.
- Validate results and remove disposable resources.

## 2. Four components with different responsibilities

| Component | Main responsibility | Observable evidence |
|---|---|---|
| Apache Spark | Execute distributed data processing | Transformation results and execution plan |
| Delta Lake | Transactionally manage table data and versions | Table format and commit history |
| Unity Catalog | Organize and govern supported data/AI objects | Namespace, ownership, permissions |
| MLflow | Track experiments and package/manage ML artifacts | Runs, parameters, metrics, artifacts |

These components complement one another. Spark does not automatically fix bad source data. Delta does not automatically enforce unique business identifiers. Catalog permissions do not train a model. An MLflow run does not deploy an application endpoint.

## 3. Spark: process the data

Spark provides DataFrames, SQL, and distributed execution. For example, it can filter incomplete encounters and calculate average duration per facility.

Many transformations are lazy: constructing a DataFrame describes work, while an action such as count, collect, or writing output triggers execution. Query optimizations can change the final physical plan.

The driver coordinates work; executor tasks process distributed data. Serverless and supported execution interfaces can hide infrastructure details. You do not need to inspect low-level Spark internals for this introductory lab.

Use built-in functions where practical. Avoid collecting a large distributed dataset into driver memory. This lab collects only two aggregate rows and four small predictions.

## 4. Delta Lake: manage durable tables

Delta Lake adds a transaction log and table protocol to underlying data files. It supports transactional changes, schema enforcement, and retained version access.

A write creates a committed table state. History helps explain how that state changed. It is not a complete audit of all business decisions, and time travel depends on retention.

Use registered managed tables by name. Do not manually alter their storage directories. Chapter 002 compared raw files with Delta; this chapter uses a Delta table as an input to a tracked evaluation.

## 5. Unity Catalog: organize and govern

Unity Catalog provides a hierarchy such as:

**catalog → schema → table**

For table access, an identity needs relevant namespace usage and object privileges. A read commonly requires USE CATALOG, USE SCHEMA, and SELECT. Creating a table requires suitable schema privileges and configured storage.

Ownership and inherited grants affect access. Seeing a table or listing its grants does not prove that another identity is denied. A real isolation test requires separately authorized test identities and is covered later.

Unity Catalog can also govern registered models. Workspace MLflow experiments have their own access controls; do not assume a table grant grants access to an experiment.

## 6. MLflow: track and manage the ML lifecycle

| MLflow concept | Meaning | Example |
|---|---|---|
| Experiment | Groups related runs | Baseline duration estimation |
| Run | One recorded execution | Evaluate one constant predictor |
| Parameter | Input/configuration | Predictor strategy |
| Metric | Numeric result | Mean absolute error |
| Artifact | Stored output | Evaluation JSON |
| Model artifact | Packaged model representation | Trained estimator with dependencies |
| Registered model | Versioned model identity | Approved model candidate |

Model serving is a separate deployment activity. Tracking a run or registering a model does not automatically expose an API.

This chapter evaluates a simple constant baseline, not a trained clinical model. It illustrates tracking without introducing training libraries. Full training, leakage prevention, registry promotion, packaging, and serving appear in Parts 15–16.

## 7. Lab — Process, persist, inspect, and track

### 7.1 Requirements and boundaries

- Python notebook and approved Spark-capable compute.
- Unity Catalog-compatible execution.
- Approved catalog/schema with managed storage and required table privileges.
- A supported MLflow client available in the notebook environment.
- An approved existing workspace folder where you can create a standalone MLflow experiment.
- Permission to log and read its runs/artifacts.
- Approved compute budget.

Check MLflow import/version in the environment. If missing, use the platform-approved dependency configuration for your runtime; do not blindly upgrade the environment. Record the version actually used.

The lab creates one managed Delta table and one standalone experiment. No permissions are granted or revoked; no model endpoint is deployed.

### Step 1 — Configure unique resources

Create notebook `dbx-ch004-components`. Record cloud, region, runtime/compute, date, and permissions.

Run after replacing placeholders:

```python
import re
import uuid

catalog = "REPLACE_WITH_APPROVED_CATALOG"
schema_name = "REPLACE_WITH_APPROVED_SCHEMA"
experiment_parent = "/REPLACE_WITH_EXISTING_APPROVED_WORKSPACE_FOLDER"

for value in (catalog, schema_name):
    assert "REPLACE_WITH" not in value
    assert re.fullmatch(r"[A-Za-z_][A-Za-z0-9_]*", value)

assert experiment_parent.startswith("/")
assert "REPLACE_WITH" not in experiment_parent

run_id = uuid.uuid4().hex[:12]
table_name = f"ch004_baseline_data_{run_id}"
table = f"`{catalog}`.`{schema_name}`.`{table_name}`"
experiment_path = (
    f"{experiment_parent.rstrip('/')}/ch004_baseline_{run_id}"
)

assert not spark.catalog.tableExists(table)
print("Table:", table)
print("Standalone experiment path:", experiment_path)
```

The experiment parent must be an existing folder, not the current notebook path. Keep the exact names for evidence and cleanup.

### Step 2 — Use Spark to transform synthetic input

```python
from pyspark.sql import functions as F

records = [
    ("E001", "North", "complete", 120),
    ("E002", "North", "complete", 60),
    ("E003", "South", "complete", 90),
    ("E004", "South", "pending", 30),
    ("E005", "North", "complete", 30),
]

source = spark.createDataFrame(
    records,
    "encounter_id STRING, facility STRING, status STRING, duration_minutes INT"
)
completed = source.filter(F.col("status") == "complete")

completed.explain()
assert source.count() == 5
assert completed.count() == 4
assert completed.select("encounter_id").distinct().count() == 4
assert completed.filter(
    F.col("duration_minutes").isNull() | (F.col("duration_minutes") < 0)
).count() == 0

display(completed.orderBy("encounter_id"))
print("PASS: Spark filtering and basic input checks")
```

**Expected:** Four completed encounters: E001, E002, E003, E005. Physical-plan text can vary.

The filter describes work; count and display execute it. These basic checks do not validate all possible source problems.

### Step 3 — Persist the result with Delta

```python
completed.write.format("delta").mode("errorifexists").saveAsTable(table)

detail = spark.sql(f"DESCRIBE DETAIL {table}").first().asDict()
assert detail["format"] == "delta"
assert spark.table(table).count() == 4

history = spark.sql(f"DESCRIBE HISTORY {table}")
display(history)
table_version = int(history.orderBy(F.desc("version")).first()["version"])
print("PASS: four records stored in a Delta table")
```

**Expected:** Delta format, four rows, and an initial write in history.

The table uses a unique name and refuses to overwrite an existing object.

### Step 4 — Inspect the catalog object

```python
display(spark.sql(f"DESCRIBE TABLE EXTENDED {table}"))
display(spark.sql(f"""
    SELECT facility, COUNT(*) AS encounters,
           SUM(duration_minutes) AS total_minutes
    FROM {table}
    GROUP BY facility
    ORDER BY facility
"""))
```

In Catalog Explorer, locate the catalog, schema, and table. Inspect ownership and visible permissions.

Optionally, where your identity is authorized:

```python
display(spark.sql(f"SHOW GRANTS ON TABLE {table}"))
```

**Expected:** North has 3 encounters/210 minutes; South has 1/90. Grant visibility depends on privileges. Inspect parent catalog/schema grants and inherited access when reviewing permissions.

Record your namespace and ownership findings. This is an inspection exercise, not a test of another identity’s denial.

### Step 5 — Define a baseline predictor

Predict 60 minutes for every completed encounter. Compute mean absolute error (MAE):

**MAE = average of |actual duration − predicted duration|**

Errors for the four records are 60, 0, 30, and 30 minutes, giving MAE = 30 minutes.

```python
baseline_minutes = 60

evaluation = (
    spark.table(table)
    .withColumn("prediction_minutes", F.lit(baseline_minutes))
    .withColumn(
        "absolute_error_minutes",
        F.abs(F.col("duration_minutes") - F.col("prediction_minutes"))
    )
)
mae = float(
    evaluation.agg(F.avg("absolute_error_minutes").alias("mae"))
    .first()["mae"]
)
assert mae == 30.0

display(evaluation.orderBy("encounter_id"))
print("PASS: constant-baseline MAE is 30 minutes")
```

This is a demonstration on the same four records, not a holdout estimate of model quality. The baseline is configured, not fitted. Later training labs require appropriate train/validation/test separation.

### Step 6 — Create a standalone MLflow experiment and log a run

```python
import mlflow

print("MLflow client version:", mlflow.__version__)
mlflow.set_tracking_uri("databricks")

assert mlflow.active_run() is None, (
    "Finish any unrelated active run before starting this lab"
)
assert mlflow.get_experiment_by_name(experiment_path) is None

experiment_id = mlflow.create_experiment(experiment_path)
mlflow.set_experiment(experiment_id=experiment_id)

evaluation_rows = [
    row.asDict()
    for row in evaluation.orderBy("encounter_id").collect()
]

with mlflow.start_run(run_name="constant-duration-baseline") as run:
    tracked_run_id = run.info.run_id
    mlflow.log_params({
        "strategy": "constant",
        "prediction_minutes": baseline_minutes,
        "evaluation_scope": "four_synthetic_completed_encounters",
    })
    mlflow.set_tags({
        "chapter": "004",
        "lab_run_id": run_id,
        "source_table": table,
        "source_delta_version": str(table_version),
    })
    mlflow.log_metrics({
        "mae_minutes": mae,
        "evaluation_rows": float(len(evaluation_rows)),
    })
    mlflow.log_dict({
        "description": "Educational constant baseline; not a trained clinical model",
        "source_table": table,
        "source_delta_version": table_version,
        "rows": evaluation_rows,
    }, "evaluation/summary.json")

print("Experiment ID:", experiment_id)
print("Tracked run ID:", tracked_run_id)
print("PASS: MLflow parameters, metrics, tags, and artifact logged")
```

**Expected:** A finished run with MAE 30.0, four evaluation rows, parameters, source tags, and evaluation/summary.json.

The table name and version are explicit tags for this introductory lab. They do not automatically constitute complete dataset lineage. The artifact includes the small synthetic evaluation output so it can still explain the result after table cleanup.

### Step 7 — Read the tracked result back

```python
from mlflow.tracking import MlflowClient

client = MlflowClient()
saved = client.get_run(tracked_run_id)

assert saved.info.experiment_id == experiment_id
assert saved.info.status == "FINISHED"
assert saved.data.params["strategy"] == "constant"
assert float(saved.data.params["prediction_minutes"]) == 60.0
assert saved.data.metrics["mae_minutes"] == 30.0
assert saved.data.metrics["evaluation_rows"] == 4.0
assert saved.data.tags["source_delta_version"] == str(table_version)

artifacts = client.list_artifacts(tracked_run_id, "evaluation")
assert any(item.path == "evaluation/summary.json" for item in artifacts)
print("PASS: tracked run metadata and artifact listing verified")
```

Open the standalone experiment in the workspace. Inspect the run, parameters, metrics, tags, and artifact. Save evidence before cleanup.

### Step 8 — Compare a deliberately worse baseline

A zero-minute predictor has MAE = (120 + 60 + 90 + 30) / 4 = 75 minutes.

```python
worse_mae = float(
    spark.table(table)
    .agg(F.avg(F.abs(F.col("duration_minutes"))).alias("mae"))
    .first()["mae"]
)
assert worse_mae == 75.0

with mlflow.start_run(run_name="zero-duration-baseline") as run:
    worse_run_id = run.info.run_id
    mlflow.log_params({"strategy": "constant", "prediction_minutes": 0})
    mlflow.set_tags({
        "chapter": "004",
        "lab_run_id": run_id,
        "source_table": table,
        "source_delta_version": str(table_version),
    })
    mlflow.log_metric("mae_minutes", worse_mae)

assert client.get_run(worse_run_id).data.metrics["mae_minutes"] > mae
print("PASS: experiment comparison distinguishes MAE 30 from MAE 75")
```

The worse result is not a platform failure. MLflow records results; your evaluation criteria determine whether a candidate is useful.

### Step 9 — Map each observation to a component

| Observation | Component |
|---|---|
| Filter and error calculation execute | Spark |
| Four rows persist with a committed version | Delta Lake |
| Named table appears with ownership/permissions | Unity Catalog |
| Two evaluations have searchable metrics | MLflow |
| Run has an evaluation artifact | MLflow artifact tracking |
| No inference endpoint exists | Serving has not been performed |

## 8. Acceptance criteria and evidence

- Environment, namespace, versions, and run identifiers recorded.
- Spark filters five input records to four completed records.
- Input keys and durations pass the stated checks.
- Delta format, row count, and version verified.
- Catalog object and ownership inspected.
- Baseline MAE = 30.0; worse baseline MAE = 75.0.
- MLflow readback confirms finished run and logged artifact.
- Experiment UI shows both runs.
- Cleanup completed or evidence-retention choice documented.

Record blocked sections explicitly. No workspace execution occurred during chapter authoring. Syntax checks and arithmetic checks do not establish platform validation.

## 9. Production considerations

### Reproducibility

Capture code revision, environment dependencies, dataset/version, feature logic, configuration, and evaluation method. Tags alone are not a complete reproducibility package.

### Governance

Data access and experiment access are separate concerns. Do not place sensitive raw data in artifacts merely because a table is well governed. Review who can read the experiment and its artifacts.

### Data quality

Delta transactions and Spark execution do not establish semantic correctness. Validate business keys, allowed values, source completeness, and freshness.

### Evaluation

Choose meaningful metrics and representative holdout data. A lower metric on four synthetic examples does not prove that a model is production-ready.

### Deployment

Tracking is followed by packaging, registration/promotion where required, and deployment. Application integration also needs feature contracts, dependencies, authentication, capacity, monitoring, and rollback.

### Costs

Avoid repeated large Spark actions without understanding execution. Use small approved compute for this lab. Monitor artifact volume and retention in larger experiment workflows.

## 10. Troubleshooting

| Symptom | Evidence | Likely cause | Corrective action |
|---|---|---|---|
| Table write denied | Identity, namespace, full error | Missing privileges or storage setup | Verify scoped permissions and managed storage |
| Wrong count or MAE | Displayed records and filter | Modified input or transformation | Restore fixture and inspect completed records |
| SHOW GRANTS denied | Error and ownership | Insufficient grant-inspection privileges | Inspect authorized UI evidence; document limitation |
| MLflow import fails | Runtime and package inventory | Client unavailable | Use supported approved dependency setup |
| Experiment creation fails | Path, parent folder, permissions | Missing folder/access or invalid path | Use an existing approved workspace folder |
| Another run is active | mlflow.active_run result | Earlier notebook work | Finish that run deliberately before continuing |
| Artifact logging fails | Run status and full error | Artifact access/configuration/connectivity | Check experiment configuration and platform evidence |
| Metrics absent in expected UI | Experiment ID and tracking URI | Wrong experiment/server | Verify Databricks tracking target and run ID |
| Worse MAE appears as FINISHED | Metric and run status | Evaluation completed successfully | Treat quality acceptance separately from execution status |

Do not log credentials or confidential data to diagnose tracking failures.

## 11. Cleanup and rollback

First export or record the desired execution evidence. The lab resources are disposable.

Remove the Delta table using original variables:

```python
assert re.fullmatch(r"[a-f0-9]{12}", run_id)
assert table_name == f"ch004_baseline_data_{run_id}"
assert table == f"`{catalog}`.`{schema_name}`.`{table_name}`"

spark.sql(f"DROP TABLE IF EXISTS {table}")
assert not spark.catalog.tableExists(table)
print("PASS: disposable Delta table removed")
```

If you do not need to retain the experiment, soft-delete only this newly created standalone experiment:

```python
experiment = client.get_experiment(experiment_id)
assert experiment.name == experiment_path
assert experiment_path.endswith(f"/ch004_baseline_{run_id}")

client.delete_experiment(experiment_id)
assert client.get_experiment(experiment_id).lifecycle_stage == "deleted"
print("PASS: standalone lab experiment soft-deleted")
```

MLflow deletion is a lifecycle operation; it does not promise immediate permanent deletion of all artifact bytes. Do not use this cleanup on a notebook experiment or a shared existing experiment. If retaining evidence, skip experiment deletion and document retention.

No permissions were modified. Do not delete the shared catalog/schema/folder. Stop only lab-dedicated compute. If the session resets, use saved exact identifiers rather than guessing resource names.

## 12. Review questions and answers

1. **Which component executes the filtering?** Spark.
2. **Which provides table commit history?** Delta Lake.
3. **Which governs the table namespace and privileges?** Unity Catalog.
4. **Where are evaluation metrics recorded?** In MLflow runs.
5. **Does FINISHED mean the model is good?** No; it means execution completed, not that quality criteria passed.
6. **Does this lab train a model?** No; it evaluates two configured constant predictors.
7. **Does logging an artifact create an API?** No; serving is a separate deployment.
8. **Why track the Delta version?** It identifies the evaluated table state, subject to retention and other reproducibility requirements.

## 13. Official references

- [Apache Spark on Databricks](https://docs.databricks.com/aws/en/spark/faq)
- [Delta Lake](https://docs.databricks.com/aws/en/delta)
- [Unity Catalog privileges](https://docs.databricks.com/aws/en/data-governance/unity-catalog/access-control/privileges-reference)
- [Organize runs with MLflow experiments](https://docs.databricks.com/aws/en/mlflow/experiments)
- [MLflow tracking](https://docs.databricks.com/aws/en/mlflow/tracking)
- [Tracking server configuration](https://docs.databricks.com/aws/en/mlflow/tracking-server-configuration)
- [MLflow Python tracking API](https://mlflow.org/docs/latest/api_reference/python_api/mlflow.html)

Synthetic examples and assertions are original tutorial material. Verify your runtime, cloud, region, and access mode before execution.

## 14. Navigation and progress

**Previous:** [Chapter 003 — Control Plane, Compute Plane & Cloud Storage](003-control-plane-compute-plane-cloud-storage.md)  
**Current:** Chapter 004 — Spark, Delta Lake, Unity Catalog & MLflow  
**Next:** [Chapter 005 — Databricks, Snowflake, Kubernetes & TrueFoundry](005-databricks-snowflake-kubernetes-truefoundry.md)

| Item | Status |
|---|---|
| Content | Authored |
| Lab | Implemented; workspace execution pending |
| Model training/serving | Outside this chapter |
| Repository publication | Included in the Databricks rebuild commit; see Git history |
| Series authored | 4/100 chapters |
| Series workspace-validated | 0/100 labs |

Full completion requires workspace execution and review evidence under the master plan.

