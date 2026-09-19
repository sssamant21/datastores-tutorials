/*
===============================================================================
Part 2.2 — Catalog → Schema → Table
Canonical Acceptance Artifact

[TUTORIAL-ACCEPTANCE — SAFE-READ]

Purpose:
  Inspect Databricks catalog/schema context and visible namespace metadata
  without modifying database state.

Safety:
  - No CREATE
  - No ALTER
  - No DROP
  - No INSERT / UPDATE / DELETE / MERGE
  - No GRANT / REVOKE
  - No ownership changes
  - No storage changes
  - No configuration changes
  - No cleanup operations

Expected impact:
  Catalog and metadata reads only.

Notes:
  - Results depend on the privileges of the executing principal.
  - A missing result does not by itself prove that an object does not exist.
  - Metadata output can reveal environment and object names; handle captured
    output according to your organization's operational-data policy.
===============================================================================
*/

-- ---------------------------------------------------------------------------
-- Check 1 — Active namespace
-- ---------------------------------------------------------------------------
-- Confirms the session context before any object-specific investigation.

SELECT
    current_catalog() AS current_catalog,
    current_schema()  AS current_schema;

-- ---------------------------------------------------------------------------
-- Check 2 — Catalogs visible to the current principal
-- ---------------------------------------------------------------------------

SHOW CATALOGS;

-- ---------------------------------------------------------------------------
-- Check 3 — Schemas visible in the active catalog
-- ---------------------------------------------------------------------------

SHOW SCHEMAS;

-- ---------------------------------------------------------------------------
-- Check 4 — Tables visible in the active schema
-- ---------------------------------------------------------------------------

SHOW TABLES;

-- ---------------------------------------------------------------------------
-- Optional object-specific inspection
-- ---------------------------------------------------------------------------
-- DESCRIBE TABLE is read-only, but the acceptance artifact intentionally does
-- not guess a table name or contain an executable placeholder.
--
-- After an operator has independently confirmed an approved target, run:
--
--   DESCRIBE TABLE <catalog>.<schema>.<table>;
--
-- as a separate, explicit inspection statement.
--
-- Do not replace the placeholder with an arbitrary production object merely
-- to make the tutorial check pass.

/*
===============================================================================
Acceptance criteria

PASS when:
  1. The active catalog and schema can be identified.
  2. Catalog discovery executes successfully for the current principal.
  3. Schema discovery executes successfully in the active catalog.
  4. Table discovery executes successfully in the active schema.

Interpretation:
  Authorization and visibility are principal-dependent. Permission failures
  should be investigated as authorization/context issues rather than treated
  automatically as proof that an object is absent.

End of [TUTORIAL-ACCEPTANCE — SAFE-READ]
===============================================================================
*/
