/*
===============================================================================
Part 3.2 — Ingesting Files from Cloud Object Storage
Canonical Acceptance Artifact

[TUTORIAL-ACCEPTANCE — SAFE-READ]

Purpose:
  Inspect the active Databricks namespace and visible metadata before an
  operator performs separately approved cloud-file ingestion validation.

Safety:
  - No CREATE / ALTER / DROP
  - No INSERT / UPDATE / DELETE / MERGE
  - No COPY INTO
  - No file ingestion
  - No streaming query creation
  - No checkpoint manipulation
  - No storage credential modification
  - No external-location modification
  - No GRANT / REVOKE
  - No cloud-storage writes/deletes
  - No cleanup

Expected impact:
  Namespace and metadata reads only.

Notes:
  - This artifact does not validate a cloud provider path.
  - It does not prove storage permissions, file completeness, parsing success,
    or source-to-Bronze reconciliation.
  - Metadata output can expose environment/object names; handle captured output
    according to organizational policy.
===============================================================================
*/

-- Check 1 — Active namespace
SELECT
    current_catalog() AS current_catalog,
    current_schema()  AS current_schema;

-- Check 2 — Catalogs visible to the current principal
SHOW CATALOGS;

-- Check 3 — Schemas visible in the active catalog
SHOW SCHEMAS;

-- Check 4 — Tables visible in the active schema
SHOW TABLES;

-- Check 5 — Volumes visible in the active schema, where supported
SHOW VOLUMES;

/*
===============================================================================
Operator follow-up — intentionally not executable here

For a separately approved source and training environment, validate:
  - exact workspace/environment;
  - governed source path;
  - expected file count;
  - expected file format;
  - schema contract;
  - selected _metadata provenance;
  - malformed/rejected evidence;
  - source-to-Bronze reconciliation.

Do not add raw cloud credentials or state-changing ingestion statements to this
canonical acceptance artifact.
===============================================================================
*/

/*
===============================================================================
Acceptance criteria

PASS when:
  1. The active catalog and schema are identified.
  2. Catalog discovery succeeds for the executing principal.
  3. Schema discovery succeeds in the active catalog.
  4. Table discovery succeeds in the active schema.
  5. Volume discovery succeeds when the runtime/catalog supports SHOW VOLUMES,
     or the operator records that the command is unavailable/not applicable.

Interpretation:
  - Permission failure does not automatically prove object absence.
  - Metadata visibility does not prove cloud-storage readability.
  - A successful file read does not by itself prove complete ingestion.
  - Production acceptance requires separately approved source-to-Bronze
    reconciliation evidence.
  - No storage or data mutation is required by this acceptance check.

End of [TUTORIAL-ACCEPTANCE — SAFE-READ]
===============================================================================
*/
