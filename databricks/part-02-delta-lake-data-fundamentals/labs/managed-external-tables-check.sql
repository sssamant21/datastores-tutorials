/*
===============================================================================
Part 2.3 — Managed vs External Tables
Canonical Acceptance Artifact

[TUTORIAL-ACCEPTANCE — SAFE-READ]

Purpose:
  Inspect Databricks namespace and table metadata without modifying table,
  catalog, schema, privilege, configuration, or storage state.

Safety:
  - No CREATE
  - No ALTER
  - No DROP
  - No INSERT / UPDATE / DELETE / MERGE
  - No VACUUM
  - No GRANT / REVOKE
  - No ownership changes
  - No external-location changes
  - No storage-credential changes
  - No filesystem operations
  - No configuration changes
  - No cleanup operations

Expected impact:
  Catalog and metadata reads only.

Notes:
  - Results depend on privileges granted to the executing principal.
  - A table not appearing in metadata output does not by itself prove that
    the table does not exist.
  - Metadata can expose object names and storage-related information. Handle
    captured output according to organizational policy.
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

-- Optional table-specific metadata inspection
-- The canonical artifact intentionally does not contain an executable
-- placeholder table name.
--
-- After independently confirming an approved target, an operator can run:
--
--   DESCRIBE TABLE <catalog>.<schema>.<table>;
--
-- For an approved Delta table:
--
--   DESCRIBE DETAIL <catalog>.<schema>.<table>;
--
-- Do not select an arbitrary production table simply to complete the check.

/*
===============================================================================
Acceptance criteria

PASS when:
  1. The active catalog and schema can be identified.
  2. Catalog discovery succeeds for the executing principal.
  3. Schema discovery succeeds in the active catalog.
  4. Table discovery succeeds in the active schema.

Operator interpretation:
  - Visibility is privilege-dependent.
  - Permission errors must not automatically be interpreted as object absence.
  - Managed/external classification must be confirmed for a specific approved
    object before any lifecycle or destructive operation.
  - No state-changing operation is required to pass this acceptance check.

End of [TUTORIAL-ACCEPTANCE — SAFE-READ]
===============================================================================
*/
