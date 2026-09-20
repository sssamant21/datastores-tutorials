/*
===============================================================================
Part 3.6 — Silver Transformation Pipelines
Canonical Acceptance Artifact

[TUTORIAL-ACCEPTANCE — SAFE-READ]

Purpose:
  Inspect the active Databricks namespace and visible table/column metadata
  relevant to an existing Bronze/Silver design without executing
  transformations or modifying data or streaming state.

Safety:
  - No CREATE / ALTER / DROP
  - No INSERT / UPDATE / DELETE / MERGE
  - No COPY INTO
  - No transformation execution
  - No streaming-query creation
  - No checkpoint/state manipulation
  - No schema mutation
  - No credential or external-location changes
  - No GRANT / REVOKE
  - No cloud-storage writes/deletes
  - No cleanup

Expected impact:
  Namespace and metadata reads only.

Important:
  A PASS from this artifact does not prove transformation correctness,
  quality-rule behavior, deduplication correctness, watermark correctness,
  replay/idempotency behavior, or Bronze-to-Silver reconciliation.
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

-- Check 5 — Visible table metadata in the active namespace
SELECT
    table_catalog,
    table_schema,
    table_name,
    table_type
FROM system.information_schema.tables
WHERE table_catalog = current_catalog()
  AND table_schema = current_schema()
ORDER BY table_name;

-- Check 6 — Visible column metadata in the active namespace
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

For separately approved Silver transformation validation, capture:
  - exact workspace/environment;
  - Bronze input identity and input count/control totals;
  - explicit Silver column/schema contract;
  - transformation version;
  - raw-to-typed conversion behavior;
  - quality-rule version and rejection reasons;
  - Silver accepted count;
  - quarantine/rejected count and ownership;
  - duplicate-loser count;
  - business key and deterministic deduplication rule;
  - watermark policy when stateful streaming deduplication is used;
  - checkpoint/state identity and compatibility review;
  - lineage and target identity/version;
  - Bronze-to-Silver reconciliation result;
  - replay evidence when applicable.

Do not add transformations, streaming starts, checkpoint/state resets,
writes, DDL/DML, MERGE, privilege changes, storage deletion, or cleanup
commands to this canonical acceptance artifact.
===============================================================================
*/

/*
===============================================================================
Acceptance criteria

PASS when:
  1. The active catalog and schema are identified.
  2. Catalog/schema discovery succeeds for the executing principal.
  3. Table discovery succeeds in the active schema.
  4. Visible table metadata can be inspected without modifying state.
  5. Visible column metadata can be inspected without modifying state.

Interpretation:
  - Existing Bronze/Silver metadata does not prove transformation success.
  - Column types do not prove safe-casting behavior.
  - Metadata does not prove quality-rule or quarantine behavior.
  - Metadata does not prove business-key deduplication.
  - Metadata does not prove watermark correctness.
  - Metadata does not prove checkpoint/state compatibility.
  - Metadata does not prove replay/idempotency behavior.
  - Metadata does not prove Bronze-to-Silver reconciliation.
  - Production acceptance requires separately approved transformation and
    reconciliation evidence.
  - No data, storage, stream, schema, or operational-state mutation is
    required here.

End of [TUTORIAL-ACCEPTANCE — SAFE-READ]
===============================================================================
*/
