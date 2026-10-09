# Chapter 005 — Databricks, Snowflake, Kubernetes & TrueFoundry

**Part:** 01 — Foundations & Architecture  
**Level:** Beginner / architecture and operations  
**Estimated time:** 60–90 minutes  
**Prerequisites:** Chapters 001–004; basic Python and SQL  
**Content status:** Authored  
**Lab status:** Implemented; local validation described separately from platform execution  
**Last reviewed:** 2026-10-09

## 1. Learning objectives

- Assign concrete responsibilities to each platform.
- Design analytics and model-consumption paths without unnecessary copies.
- Distinguish model training, packaging, deployment, and inference.
- Validate a small application artifact contract.
- Identify failure ownership and evidence needed across platform boundaries.
- Document optional platform checks accurately.

## 2. What each platform contributes

| Platform | Typical role in this chapter | Concrete example |
|---|---|---|
| Databricks | Data processing, analytics, and ML development | Prepare features and evaluate a model |
| Snowflake | Governed analytical data and SQL workloads | Publish facility aggregates for reporting |
| Kubernetes | Orchestrate containerized workloads | Schedule backend/model-service pods |
| TrueFoundry | Deploy and operate supported workloads on Kubernetes | Configure a model API’s resources and deployment |
| Application backend | Implement application logic | Load a model or call its endpoint |
| UI | Present interactions and results | Submit inputs and show predictions |

These are useful roles for this example, not exclusive product boundaries. Databricks also provides SQL analytics and model serving. Snowflake has data engineering and AI/ML capabilities. Kubernetes can run processing jobs. TrueFoundry supports more than model APIs.

Choose platforms based on required behavior, existing ownership, cost, reliability, and operating skills.

## 3. Two flows to design separately

### 3.1 Data and analytics flow

Operational sources → ingestion/transformation → curated analytical data → consumers.

Databricks can prepare that data. Snowflake can be an analytical destination if the organization chooses that design. A pipeline must explicitly transfer or expose the required data; tables do not synchronize simply because both platforms exist.

Define business keys, freshness, deletes, replay, source counts, and reconciliation at every integration boundary.

### 3.2 Model and application flow

Training/evaluation → approved artifact → deployment → application inference.

The UI normally calls an application backend. The backend may load a trusted model artifact, call a separate model endpoint, or read batch predictions.

Training can occur in Databricks, while deployment occurs through TrueFoundry on Kubernetes. Alternatively, use Databricks Model Serving. You do not need to place Snowflake in every prediction request.

## 4. Choose a model-consumption pattern

| Pattern | Application action | Operational tradeoff |
|---|---|---|
| Packaged artifact | Backend loads model once and predicts locally | Simple request path; backend releases and model dependencies are coupled |
| Separate endpoint | Backend sends authenticated inference request | Independent scaling; adds network, latency, and service dependencies |
| Batch predictions | Backend reads precomputed result | Efficient for scheduled decisions; freshness is bounded by batch completion |
| LLM service | Backend calls GPU/other suitable serving infrastructure | Capacity, memory, throughput, and token latency require attention |

### 4.1 Your joblib/pkl approach

For compatible Python models, the delivery package may include:

- Trusted model artifact, such as a joblib file.
- Preprocessing and feature-order contract.
- Pinned dependencies and runtime compatibility.
- Model version and evaluation evidence.
- Sample requests, expected outputs, and rollback version.

The backend loads it at startup. The browser UI does not normally execute a Python pickle file.

Pickle-based artifacts can execute code when loaded. Use only trusted artifacts. A checksum detects byte changes relative to a known checksum; it does not establish producer authenticity unless the checksum itself is trusted.

### 4.2 TrueFoundry and Kubernetes responsibilities

TrueFoundry helps define and manage application deployments. Kubernetes schedules and maintains the desired container workload state.

Neither platform automatically fixes an incompatible model package, missing feature, incorrect response, or application bug. A healthy pod is not sufficient proof that predictions are correct.

For vLLM, verify model compatibility, GPU resources, drivers/runtime visibility, and capacity. Do not use vLLM as a generic server for every Python estimator.

## 5. Architecture worksheet

Fill this before implementation:

| Decision | Required answer |
|---|---|
| Authoritative source | Which system owns records and corrections? |
| Transformation owner | Which team owns processing logic? |
| Analytical destination | Databricks, Snowflake, both, or another selected destination? |
| Model production | Where are training and evaluation performed? |
| Artifact authority | Which registry/store identifies approved versions? |
| Serving pattern | Packaged backend, endpoint, or batch? |
| Runtime owner | Who owns Kubernetes/TrueFoundry or managed serving? |
| Input contract | Names, types, ranges, ordering, missing-value behavior |
| Freshness/SLO | Acceptable data age and prediction latency |
| Rollback | Exact previous artifact/deployment and procedure |
| Failure evidence | Correlation ID, data version, model version, error class |

Document why any extra data copy or service exists.

## 6. Lab — Verify a portable prediction contract

### 6.1 Scope

This lab uses Python’s standard library to package a simple configured baseline and consume it through a backend function.

It uses JSON configuration rather than a joblib artifact so the exercise requires no ML dependency installation. It demonstrates packaging, validation, provenance, and application behavior. It does **not** train a model, start an HTTP API, or deploy to any platform.

Later Chapters 076–080 cover real model packaging and deployment. Optional platform inspection follows the local exercise.

### 6.2 Requirements

Python 3.10 or later and a writable scratch folder. No cloud credentials are needed. Run each block in the same Python session, a local notebook, or save the blocks in order into a single script.

If running inside Databricks, local temporary files remain a local exercise; do not count them as durable Unity Catalog storage.

### Step 1 — Create a versioned baseline package

```python
from pathlib import Path
from tempfile import TemporaryDirectory
import hashlib
import json
import math

lab_dir = TemporaryDirectory(prefix="dbx_ch005_")
root = Path(lab_dir.name)

artifact = {
    "schema_version": 1,
    "model_version": "baseline-v1",
    "strategy": "constant-duration",
    "prediction_minutes": 60.0,
    "input_contract": {
        "required_fields": ["encounter_id", "duration_minutes"],
        "duration_minimum": 0,
    },
    "training": "not trained; configured educational baseline",
}
artifact_path = root / "baseline.json"
artifact_path.write_text(
    json.dumps(artifact, sort_keys=True, indent=2),
    encoding="utf-8",
)
trusted_checksum = hashlib.sha256(artifact_path.read_bytes()).hexdigest()
print("Package created:", artifact_path.name)
```

**Expected:** baseline.json created. The checksum is kept separately from the mutable package for this demonstration.

### Step 2 — Load and validate at backend startup

```python
def load_artifact(path, expected_checksum):
    payload = path.read_bytes()
    actual_checksum = hashlib.sha256(payload).hexdigest()
    if actual_checksum != expected_checksum:
        raise ValueError("artifact checksum mismatch")

    data = json.loads(payload)
    if data.get("schema_version") != 1:
        raise ValueError("unsupported artifact schema")
    if data.get("strategy") != "constant-duration":
        raise ValueError("unsupported strategy")
    if not isinstance(data.get("model_version"), str) or not data["model_version"]:
        raise ValueError("missing model version")

    prediction = data.get("prediction_minutes")
    if (
        isinstance(prediction, bool)
        or not isinstance(prediction, (int, float))
        or not math.isfinite(prediction)
        or prediction < 0
    ):
        raise ValueError("invalid configured prediction")
    if data.get("input_contract") != {
        "required_fields": ["encounter_id", "duration_minutes"],
        "duration_minimum": 0,
    }:
        raise ValueError("unsupported input contract")
    return data

loaded_model = load_artifact(artifact_path, trusted_checksum)
assert loaded_model["model_version"] == "baseline-v1"
print("PASS: trusted baseline configuration loaded")
```

A real backend loads its compatible model/preprocessing once at startup. Its readiness should fail if the package is invalid.

### Step 3 — Implement the application-facing function

```python
def predict_duration(request, model):
    if not isinstance(request, dict):
        raise ValueError("request must be an object")
    encounter_id = request.get("encounter_id")
    if not isinstance(encounter_id, str) or not encounter_id.strip():
        raise ValueError("encounter_id must be a nonempty string")

    duration = request.get("duration_minutes")
    if (
        isinstance(duration, bool)
        or not isinstance(duration, (int, float))
        or not math.isfinite(duration)
        or duration < 0
    ):
        raise ValueError("duration_minutes must be finite and nonnegative")

    return {
        "encounter_id": encounter_id,
        "prediction_minutes": float(model["prediction_minutes"]),
        "model_version": model["model_version"],
    }

response = predict_duration(
    {"encounter_id": "E001", "duration_minutes": 120},
    loaded_model,
)
assert response == {
    "encounter_id": "E001",
    "prediction_minutes": 60.0,
    "model_version": "baseline-v1",
}
print(response)
```

**Expected:** E001, prediction 60.0, model version baseline-v1.

The actual duration is included for educational evaluation only. A production duration-prediction request would use features available before the outcome occurs. The constant baseline does not use duration as a predictive feature.

### Step 4 — Evaluate the application output

```python
evaluation_records = [
    {"encounter_id": "E001", "duration_minutes": 120},
    {"encounter_id": "E002", "duration_minutes": 60},
    {"encounter_id": "E003", "duration_minutes": 90},
    {"encounter_id": "E005", "duration_minutes": 30},
]
responses = [predict_duration(r, loaded_model) for r in evaluation_records]
mae = sum(
    abs(r["duration_minutes"] - p["prediction_minutes"])
    for r, p in zip(evaluation_records, responses)
) / len(evaluation_records)

assert mae == 30.0
assert all(r["model_version"] == "baseline-v1" for r in responses)
print("PASS: application output preserves version and MAE is 30 minutes")
```

This matches the Chapter 004 baseline. It shows predictable consumption, not production model quality.

### Step 5 — Test invalid inputs and changed bytes

```python
invalid_requests = [
    {},
    {"encounter_id": "", "duration_minutes": 30},
    {"encounter_id": "E001", "duration_minutes": -1},
    {"encounter_id": "E001", "duration_minutes": "30"},
    {"encounter_id": "E001", "duration_minutes": True},
    {"encounter_id": "E001", "duration_minutes": float("nan")},
]

for bad in invalid_requests:
    try:
        predict_duration(bad, loaded_model)
    except ValueError:
        pass
    else:
        raise AssertionError(f"Invalid request accepted: {bad}")

changed_path = root / "changed-baseline.json"
changed = dict(artifact, prediction_minutes=999)
changed_path.write_text(json.dumps(changed), encoding="utf-8")

try:
    load_artifact(changed_path, trusted_checksum)
except ValueError as exc:
    assert str(exc) == "artifact checksum mismatch"
else:
    raise AssertionError("Changed artifact accepted")

print("PASS: invalid inputs and changed artifact rejected")
```

A real API should map input errors to an appropriate client error and return a safe error message. Never return credentials or stack traces to the UI.

### Step 6 — Define how this becomes a deployed service

| Item | Deployment requirement |
|---|---|
| Code | HTTP wrapper around validated inference logic |
| Image | Reproducible build and pinned runtime/dependencies |
| Artifact | Trusted, versioned package or authorized startup download |
| Startup | Load package and validate compatibility |
| Readiness | Ready only after model initialization succeeds |
| Resources | CPU/memory or GPU based on measured requirements |
| Identity | Least-privilege access to artifact/data stores |
| Ingress | Approved endpoint, TLS, and authentication |
| Observability | Version, latency, errors, and request correlation |
| Rollback | Previous image and artifact combination |

TrueFoundry can manage the deployment; Kubernetes runs the workload. This worksheet is not a deployment command and creates no external resources.

## 7. Optional platform inspection

These checks need existing authorized lab access. Mark unavailable checks skipped or blocked.

### 7.1 Databricks

Run a namespace/identity query in a notebook:

```sql
SELECT current_user(), current_catalog(), current_schema();
```

Record the compute type and a disposable table’s metadata from earlier chapters if that table still exists. Do not assume previous lab tables survived cleanup.

### 7.2 Snowflake

In an authorized worksheet:

```sql
SELECT CURRENT_USER(), CURRENT_ROLE(), CURRENT_WAREHOUSE(),
       CURRENT_DATABASE(), CURRENT_SCHEMA();

SELECT facility, COUNT(*) AS completed_encounters,
       SUM(duration_minutes) AS total_minutes
FROM VALUES
  ('North', 120),
  ('North', 60),
  ('South', 90),
  ('North', 30)
AS encounters(facility, duration_minutes)
GROUP BY facility
ORDER BY facility;
```

**Expected:** North 3/210 and South 1/90. This executes a fixture inside Snowflake; it is not a Databricks-to-Snowflake transfer or synchronization test. Use approved compute and its idle controls.

### 7.3 Kubernetes

Use an existing lab context and namespace:

```bash
kubectl config current-context
kubectl --context <approved-lab-context> -n <approved-lab-namespace> get deployments,pods,services
```

Replace placeholders. These commands inspect existing resources. Record deployment readiness and image versions where visible. A ready pod alone does not validate inference correctness.

### 7.4 TrueFoundry

Open the authorized workspace and inspect an existing lab application: deployment version, image, resource requests, endpoint configuration, and logs. Record which Kubernetes workload it manages if visible.

Do not change or deploy resources as part of this inspection. Current UI and SDK details depend on your installation; use its supported documentation.

## 8. Acceptance criteria

- Responsibility and architecture worksheets completed.
- Baseline package loads with a trusted checksum.
- Valid request returns versioned prediction 60.0.
- Four-row evaluation yields MAE 30.0.
- Six invalid inputs and modified artifact are rejected.
- Deployment requirements documented.
- Optional checks accurately labelled executed, skipped, or blocked.
- Temporary files removed.

The core is a local integration simulation. It does not validate cloud data transfer, Kubernetes scheduling, TrueFoundry deployment, authentication, network routing, or an HTTP endpoint.

## 9. Production operations and failure ownership

| Symptom | Start with | Owner to involve |
|---|---|---|
| Analytical data stale | Source arrival, pipeline run, reconciliation | Data pipeline/source owners |
| Databricks succeeds but Snowflake lacks rows | Transfer logs, target keys/counts | Integration and destination owners |
| Backend cannot load artifact | Checksum, dependency/runtime, startup logs | Model release/application owners |
| Pod pending | Scheduling events, resource/quota/node availability | Kubernetes/platform owners |
| Pod ready but prediction wrong | Input/preprocessing/model version and parity test | Application/model owners |
| Endpoint timeout | Latency traces, service health, network evidence | Application/serving/platform owners |
| Version mismatch | Deployment/image/artifact manifest | Release owners |

Use correlation identifiers across the application and serving layers. Keep model version and data version separate. Define freshness and latency SLOs for their actual consumers.

## 10. Troubleshooting the lab

| Symptom | Likely cause | Action |
|---|---|---|
| NameError | Blocks executed out of order | Run in one session in sequence |
| Checksum mismatch on original package | Bytes modified after checksum | Recreate the original package; investigate unexpected changes |
| Invalid duration error | Missing/wrong type/nonfinite value | Follow the input contract |
| MAE differs | Fixture or predictor changed | Compare four durations and prediction 60 |
| Snowflake query cannot execute | Role or warehouse availability | Use approved role/warehouse and record blocked execution |
| kubectl access denied | Wrong context or missing RBAC | Verify authorized lab context and access |
| TrueFoundry application absent | Wrong workspace or no lab application | Record inspection unavailable; do not infer deployment success |

## 11. Cleanup and rollback

```python
lab_dir.cleanup()
assert not root.exists()
print("PASS: temporary package files removed")
```

No deployment or platform data transfer was performed. Optional checks created no tables or Kubernetes resources.

For production rollback, restore the prior compatible image/artifact pair, verify readiness and prediction parity, then follow the approved traffic-change procedure. Keep the previous package available rather than relying on mutable “latest” references.

## 12. Review questions and answers

1. **Must every pipeline use all four platforms?** No; each addition needs a concrete purpose.
2. **Can a backend load a joblib file directly?** Yes, with a trusted artifact and compatible preprocessing/runtime/dependencies.
3. **Does the browser normally load it?** No; the Python backend typically handles inference.
4. **Does Kubernetes train models automatically?** No; it runs configured workloads.
5. **What does TrueFoundry add?** Deployment and operational tooling for supported workloads over Kubernetes.
6. **Does a checksum establish authenticity alone?** No; the expected checksum needs a trusted origin.
7. **Does this lab prove platform integration?** No; it validates a local packaging/consumption contract.
8. **Why report model version?** To support debugging, reproducibility, and controlled releases.

## 13. Official references

- [Databricks Model Serving](https://docs.databricks.com/aws/en/machine-learning/model-serving/)
- [Snowflake architecture](https://docs.snowflake.com/en/user-guide/intro-key-concepts)
- [Kubernetes overview](https://kubernetes.io/docs/concepts/overview/)
- [Kubernetes objects](https://kubernetes.io/docs/concepts/overview/working-with-objects/)
- [TrueFoundry deployment examples](https://github.com/truefoundry/getting-started-examples)
- [TrueFoundry documentation](https://www.truefoundry.com/docs)

The local code and fixtures are original tutorial examples. Confirm cloud/region and installed-platform support before deployment.

## 14. Navigation and progress

**Previous:** [Chapter 004 — Spark, Delta Lake, Unity Catalog & MLflow](004-spark-delta-lake-unity-catalog-mlflow.md)  
**Current:** Chapter 005 — Databricks, Snowflake, Kubernetes & TrueFoundry  
**Next:** Chapter 006 — Workspace Navigation & Environment Inventory (planned)

| Item | Status |
|---|---|
| Content | Authored |
| Core local simulation | Validated during authoring |
| Optional platform checks | Execution pending |
| Repository publication | Included in the Databricks rebuild commit; see Git history |
| Part 01 | All five chapters authored; platform validation pending |
| Series authored | 5/100 chapters |
| Series workspace-validated | 0/100 labs |

Part 01 is not marked fully complete until required execution and review evidence exists.

