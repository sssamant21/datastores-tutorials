/*
===============================================================================
Part 3.1 — Data Ingestion Fundamentals
Canonical Acceptance Artifact

[TUTORIAL-ACCEPTANCE — SAFE-READ]

Purpose:
  Verify the active Databricks namespace and visible table metadata without
  ingesting data or modifying tables, streams, checkpoints, credentials,
  storage, or configuration.

Safety:
  - No CREATE / ALTER / DROP
  - No INSERT / UPDATE / DELETE / MERGE
  - No COPY INTO
  - No streaming query creation
  - No checkpoint creation, deletion, reset, or modification
  - No credential or secret changes
  - No GRANT / REVOKE
  - No storage modification
  - No cleanup

Expected impact:
  Namespace and metadata reads only.

Notes:
  - This artifact does not execute an ingestion pipeline.
  - Visibility depends on privileges granted to the executing principal.
  - Metadata can expose environment and object names; handle captured output
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

-- Optional operator-supplied validation
-- -------------------------------------
-- After independently identifying an approved Bronze/ingestion table, perform
-- any object-specific read-only inspection separately.
--
-- Do not place executable placeholder identifiers in this canonical artifact.
-- Do not run COPY INTO, create a stream, manipulate checkpoints, alter
-- credentials, or modify table/storage state as part of acceptance.

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
  - Metadata discovery does not prove ingestion health or completeness.
  - Production ingestion validation requires separate approved source-to-Bronze
    reconciliation evidence.
  - No ingestion or state mutation is required for this acceptance check.

End of [TUTORIAL-ACCEPTANCE — SAFE-READ]
===============================================================================
*/
