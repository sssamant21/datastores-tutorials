/*
===============================================================================
Part 2.6 — Batch vs Streaming
Canonical Acceptance Artifact

[TUTORIAL-ACCEPTANCE — SAFE-READ]

Purpose:
  Verify the active Databricks namespace and visible table metadata without
  starting streaming queries or modifying tables, checkpoints, storage, or
  configuration.

Safety:
  - No streaming query creation
  - No checkpoint creation, deletion, reset, or modification
  - No CREATE / ALTER / DROP
  - No INSERT / UPDATE / DELETE / MERGE
  - No TRUNCATE / VACUUM
  - No GRANT / REVOKE
  - No storage modification
  - No configuration changes
  - No cleanup

Expected impact:
  Namespace and metadata reads only.

Notes:
  - This artifact does not test a running stream.
  - Visibility depends on privileges granted to the executing principal.
  - Metadata can expose environment and object names.
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

-- Optional operator-supplied validation
-- Perform object-specific read-only inspection separately after independently
-- identifying an approved Delta table.
--
-- Do not place executable placeholder identifiers in this artifact.
-- Do not start or stop streams, manipulate checkpoints, or change table state.

/*
===============================================================================
Acceptance criteria

PASS when:
  1. The active catalog and schema can be identified.
  2. Catalog discovery succeeds for the executing principal.
  3. Schema discovery succeeds in the active catalog.
  4. Table discovery succeeds in the active schema.

Interpretation:
  - Permission failure does not automatically prove object absence.
  - Metadata discovery does not prove streaming-query health.
  - Streaming troubleshooting requires separate approved operational evidence.
  - No checkpoint or table mutation is required for this acceptance check.

End of [TUTORIAL-ACCEPTANCE — SAFE-READ]
===============================================================================
*/
