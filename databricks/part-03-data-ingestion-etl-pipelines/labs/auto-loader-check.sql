/*
===============================================================================
Part 3.3 — Auto Loader Fundamentals
Canonical Acceptance Artifact

[TUTORIAL-ACCEPTANCE — SAFE-READ]

Purpose:
  Inspect the active Databricks namespace and visible metadata before a
  separately approved Auto Loader training or production validation.

Safety:
  - No CREATE / ALTER / DROP
  - No INSERT / UPDATE / DELETE / MERGE
  - No COPY INTO
  - No Auto Loader execution
  - No readStream / writeStream execution
  - No streaming-query creation
  - No file ingestion
  - No checkpoint manipulation
  - No Auto Loader schema-state manipulation
  - No credential or external-location changes
  - No GRANT / REVOKE
  - No cloud-storage writes/deletes
  - No cleanup

Expected impact:
  Namespace and metadata reads only.

Important:
  A PASS from this artifact does not prove that Auto Loader can discover files,
  that a checkpoint is healthy, that schema evolution is correct, or that
  source-to-Bronze reconciliation has succeeded.
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

For a separately approved Auto Loader pipeline, validate:
  - exact workspace/environment;
  - governed source location;
  - target table identity;
  - checkpoint identity and ownership;
  - schema-state identity and ownership;
  - configured discovery mode;
  - latest successful progress;
  - incoming/discovered/processed/outstanding file evidence;
  - oldest outstanding input age;
  - rescued/corrupt record evidence;
  - source-to-Bronze reconciliation.

Do not add readStream/writeStream, Auto Loader execution, checkpoint resets, or
state-changing recovery commands to this canonical acceptance artifact.
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
  5. Volume discovery succeeds when supported, or the operator records that
     SHOW VOLUMES is unavailable/not applicable in the execution context.

Interpretation:
  - Metadata visibility does not prove source readability.
  - Metadata visibility does not prove file discovery is current.
  - Stream completion does not prove source-to-Bronze completeness.
  - A checkpoint must not be deleted merely because this check cannot inspect
    Auto Loader state.
  - Production acceptance requires separately approved ingestion and
    reconciliation evidence.
  - No data, storage, stream, or operational state mutation is required here.

End of [TUTORIAL-ACCEPTANCE — SAFE-READ]
===============================================================================
*/
