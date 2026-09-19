/*
===============================================================================
Part 2.5 — Reading/Writing Data
Canonical Acceptance Artifact

[TUTORIAL-ACCEPTANCE — SAFE-READ]

Purpose:
  Verify the active Databricks namespace and visible table metadata before
  performing any separate, explicitly approved reading/writing exercise.

Safety:
  - No CREATE
  - No ALTER
  - No DROP
  - No INSERT
  - No UPDATE
  - No DELETE
  - No MERGE
  - No TRUNCATE
  - No VACUUM
  - No GRANT / REVOKE
  - No overwrite
  - No schema evolution
  - No storage manipulation
  - No configuration changes
  - No cleanup

Expected impact:
  Namespace and metadata reads only.

Notes:
  - This artifact does not execute the writable hands-on exercise.
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

-- Optional operator-supplied checks
-- ---------------------------------
-- After independently identifying an approved target, run object-specific
-- read-only validation separately. Examples may include DESCRIBE TABLE or a
-- bounded SELECT against the verified object.
--
-- Do not place executable placeholder identifiers in this canonical artifact.
-- Do not use this file to test state-changing permissions.

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
  - A successful metadata check does not authorize a production write.
  - Writable exercises require a separately approved disposable target.
  - Production writes require independent target, scope, idempotency,
    validation, and recovery checks.

End of [TUTORIAL-ACCEPTANCE — SAFE-READ]
===============================================================================
*/
