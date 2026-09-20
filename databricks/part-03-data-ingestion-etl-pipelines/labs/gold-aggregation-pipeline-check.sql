/*
===============================================================================
Part 3.7 — Gold Aggregation Pipelines
Canonical Acceptance Artifact

[TUTORIAL-ACCEPTANCE — SAFE-READ]

Purpose:
  Inspect the active Databricks namespace and visible table/column metadata
  relevant to existing Silver/Gold serving objects without executing Gold
  aggregation, refreshing materialized views, or modifying data/state.

Safety:
  - No CREATE / ALTER / DROP
  - No INSERT / UPDATE / DELETE / MERGE
  - No COPY INTO
  - No materialized-view refresh
  - No aggregation execution against business data
  - No pipeline or streaming-query creation
  - No checkpoint/state manipulation
  - No credential or external-location changes
  - No GRANT / REVOKE
  - No cloud-storage writes/deletes
  - No cleanup

Expected impact:
  Namespace and metadata reads only.

Important:
  A PASS from this artifact does not prove metric correctness, Gold grain
  uniqueness, join cardinality, aggregation reconciliation, distinct-count
  semantics, late-data handling, business freshness, or approval of the
  business metric definition.
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

-- Check 4 — Tables/views visible in the active schema
SHOW TABLES;

-- Check 5 — Visible table/view metadata in the active namespace
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

For separately approved Gold validation, capture:
  - exact workspace/environment;
  - Silver source identity/version and input population;
  - Gold target identity/version;
  - metric-definition version and business owner;
  - Gold grain;
  - population/filter rules;
  - business time and timezone rules;
  - NULL-dimension policy;
  - join cardinality and dimension-key checks where applicable;
  - additive/non-additive measure semantics;
  - Gold row count;
  - duplicate-grain count;
  - unexpected NULL-dimension count;
  - event-count or other semantically valid reconciliation;
  - technical refresh time;
  - business freshness boundary;
  - late-data/backfill handling evidence when applicable;
  - transformation/refresh identity.

Do not add transformations, materialized-view refreshes, writes, DDL/DML,
MERGE, pipeline starts, privilege changes, storage deletion, or cleanup
commands to this canonical acceptance artifact.
===============================================================================
*/

/*
===============================================================================
Acceptance criteria

PASS when:
  1. The active catalog and schema are identified.
  2. Catalog/schema discovery succeeds for the executing principal.
  3. Table/view discovery succeeds in the active schema.
  4. Visible table/view metadata can be inspected without modifying state.
  5. Visible column metadata can be inspected without modifying state.

Interpretation:
  - Existing Gold metadata does not prove metric correctness.
  - Column definitions do not prove Gold grain uniqueness.
  - Metadata does not prove join cardinality.
  - Metadata does not prove aggregation reconciliation.
  - Metadata does not prove distinct-count semantics.
  - Metadata does not prove late-data correction behavior.
  - A recent object refresh does not prove business freshness.
  - Metadata does not prove that the metric definition is approved.
  - Production acceptance requires separately approved metric, transformation,
    reconciliation, freshness, and governance evidence.
  - No data, storage, pipeline, schema, or operational-state mutation is
    required here.

End of [TUTORIAL-ACCEPTANCE — SAFE-READ]
===============================================================================
*/
