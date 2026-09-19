/*
===============================================================================
Part 2.4 — Bronze, Silver & Gold
Canonical Acceptance Artifact

[TUTORIAL-ACCEPTANCE — SAFE-READ]

Purpose:
  Inspect Databricks namespace and visible table metadata without creating,
  modifying, transforming, or deleting Medallion-layer data.

Safety:
  - No CREATE
  - No ALTER
  - No DROP
  - No INSERT / UPDATE / DELETE / MERGE
  - No TRUNCATE
  - No VACUUM
  - No GRANT / REVOKE
  - No ownership changes
  - No storage changes
  - No configuration changes
  - No cleanup operations

Expected impact:
  Catalog and metadata reads only.

Notes:
  - Bronze, Silver, and Gold are logical architecture layers. This check does
    not assume schemas with those literal names exist.
  - Visibility depends on privileges granted to the executing principal.
  - Metadata can expose environment and object names. Handle captured output
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
-- After independently identifying approved Bronze, Silver, or Gold objects,
-- an operator may run separate read-only queries such as:
--
--   DESCRIBE TABLE <catalog>.<schema>.<table>;
--
-- or:
--
--   SELECT COUNT(*)
--   FROM <catalog>.<schema>.<table>;
--
-- Do not paste executable placeholder identifiers into this acceptance file.
-- Do not assume counts across Bronze, Silver, and Gold must be equal.
-- Reconciliation must follow the pipeline's documented quality and
-- aggregation rules.

/*
===============================================================================
Acceptance criteria

PASS when:
  1. The active catalog and schema can be identified.
  2. Catalog discovery succeeds for the executing principal.
  3. Schema discovery succeeds in the active catalog.
  4. Table discovery succeeds in the active schema.

Operator interpretation:
  - Permission failures do not automatically prove object absence.
  - Layer names and physical namespace design are organization-specific.
  - Object-specific count/reconciliation checks require approved targets and
    documented pipeline semantics.
  - No state-changing operation is required to pass this acceptance check.

End of [TUTORIAL-ACCEPTANCE — SAFE-READ]
===============================================================================
*/
