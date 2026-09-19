/*
===============================================================================
Part 3.5 — Building Bronze Ingestion Pipelines
Canonical Acceptance Artifact

[TUTORIAL-ACCEPTANCE — SAFE-READ]

Purpose:
  Inspect the active Databricks namespace and visible Bronze table metadata
  without starting ingestion or modifying pipeline state.

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
  - No hard-coded cloud_files_state() checkpoint inspection

Expected impact:
  Namespace and metadata reads only.

Important:
  A PASS from this artifact does not prove ingestion execution, source-file
  completeness, backlog recovery, or source-to-Bronze reconciliation.
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

-- Check 6 — Visible table metadata in the active namespace
SELECT
    table_catalog,
    table_schema,
    table_name,
    table_type
FROM system.information_schema.tables
WHERE table_catalog = current_catalog()
  AND table_schema = current_schema()
ORDER BY table_name;

-- Check 7 — Visible column metadata in the active namespace
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

For separately approved Bronze pipeline validation, capture:
  - exact workspace/environment;
  - source identity and expected source controls;
  - target Bronze table;
  - checkpoint identity;
  - schemaLocation identity;
  - Auto Loader discovery/evolution configuration;
  - source files known/processed;
  - numFilesOutstanding / numBytesOutstanding when available;
  - file-level state when cloud_files_state() is appropriate;
  - Bronze row and provenance evidence;
  - rescued/corrupt-record evidence;
  - source-to-Bronze reconciliation;
  - replay/recovery evidence when applicable.

Do not add readStream/writeStream, Auto Loader execution, cloud_files_state()
with a real checkpoint path, schema/checkpoint resets, writes, DDL/DML,
privilege changes, storage deletion, or cleanup commands to this canonical
acceptance artifact.
===============================================================================
*/

/*
===============================================================================
Acceptance criteria

PASS when:
  1. The active catalog and schema are identified.
  2. Catalog/schema discovery succeeds for the executing principal.
  3. Table discovery succeeds in the active schema.
  4. Volume discovery succeeds when supported, or its unavailability is
     recorded as not applicable for the execution context.
  5. Visible table and column metadata can be inspected without modifying
     state.

Interpretation:
  - Metadata visibility does not prove Auto Loader ran successfully.
  - Metadata visibility does not prove all expected source files arrived.
  - Existing Bronze tables do not prove ingestion completeness.
  - Existing row/column metadata does not prove business uniqueness.
  - This artifact does not prove rescued/corrupt-data handling.
  - This artifact does not prove checkpoint/schema-state health.
  - Production acceptance requires separately approved state-changing
    ingestion and source-to-Bronze reconciliation evidence.
  - No data, storage, stream, schema, or operational-state mutation is
    required here.

End of [TUTORIAL-ACCEPTANCE — SAFE-READ]
===============================================================================
*/
