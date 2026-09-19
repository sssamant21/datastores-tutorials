/*
===============================================================================
Part 3.4 — Schema Inference & Schema Evolution
Canonical Acceptance Artifact

[TUTORIAL-ACCEPTANCE — SAFE-READ]

Purpose:
  Inspect the active Databricks namespace and visible table/column metadata
  before separately approved schema-inference or schema-evolution testing.

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
  A PASS from this artifact does not prove schema evolution behavior, rescued
  data behavior, checkpoint/schema-state health, or source-to-Bronze
  reconciliation.
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

-- Check 6 — Column metadata visible in the active namespace
SELECT
    table_catalog,
    table_schema,
    table_name,
    column_name,
    ordinal_position,
    data_type,
    is_nullable
FROM system.information_schema.columns
WHERE table_catalog = current_catalog()
  AND table_schema = current_schema()
ORDER BY table_name, ordinal_position;

/*
===============================================================================
Operator follow-up — intentionally not executable here

For a separately approved schema-evolution test, capture:
  - exact workspace/environment;
  - source and target identities;
  - checkpoint identity;
  - schemaLocation identity;
  - configured schemaEvolutionMode;
  - inferColumnTypes/schemaHints settings when applicable;
  - baseline schema;
  - triggering source file;
  - observed schema difference;
  - rescued/corrupt-record evidence;
  - resulting Bronze schema and rows;
  - downstream impact;
  - source-to-Bronze reconciliation.

Do not add readStream/writeStream, Auto Loader execution, schema/checkpoint
resets, ALTER statements, writes, or cleanup commands to this canonical
acceptance artifact.
===============================================================================
*/

/*
===============================================================================
Acceptance criteria

PASS when:
  1. The active catalog and schema are identified.
  2. Catalog and schema discovery succeeds for the executing principal.
  3. Table discovery succeeds in the active schema.
  4. Volume discovery succeeds when supported, or its unavailability is
     recorded as not applicable for the execution context.
  5. Visible column metadata can be inspected without modifying state.

Interpretation:
  - Metadata visibility does not prove source schema correctness.
  - Metadata visibility does not prove Auto Loader schema evolution.
  - Metadata visibility does not prove rescued-data behavior.
  - Existing table columns do not prove that all source fields were preserved.
  - A checkpoint or schemaLocation must not be deleted because this artifact
    cannot inspect streaming operational state.
  - Production acceptance requires separately approved state-changing
    ingestion and reconciliation evidence.
  - No data, storage, stream, schema, or operational-state mutation is
    required here.

End of [TUTORIAL-ACCEPTANCE — SAFE-READ]
===============================================================================
*/
