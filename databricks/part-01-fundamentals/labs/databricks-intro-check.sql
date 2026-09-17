-- [TUTORIAL-ACCEPTANCE — SAFE-READ]
-- Part 1.1 — What Is Databricks?
--
-- Purpose:
--   Validate the learner's current Databricks identity and Unity Catalog
--   context using discovery/read-only operations.
--
-- Safety:
--   This lab does not intentionally create, modify, or delete data.
--   Run only in an approved workspace using an approved SQL warehouse
--   or compute resource.
--   Do not copy sensitive environment information into public locations.

-- 1. Identify current context.
SELECT
    current_user() AS current_user,
    current_catalog() AS current_catalog,
    current_schema() AS current_schema;

-- 2. Discover catalogs visible to the current identity.
SHOW CATALOGS;

-- 3. After choosing an organization-approved catalog, uncomment and
--    replace the placeholder. Never run the placeholder literally.
-- USE CATALOG <authorized_catalog>;

-- 4. Discover schemas in the selected catalog.
SHOW SCHEMAS;

-- 5. After choosing an organization-approved schema, uncomment and
--    replace the placeholder. Never run the placeholder literally.
-- USE SCHEMA <authorized_schema>;

-- 6. Discover tables visible in the selected schema.
SHOW TABLES;

-- 7. Verify final context.
SELECT
    current_user() AS current_user,
    current_catalog() AS current_catalog,
    current_schema() AS current_schema;

-- Acceptance:
--   PASS when the learner can identify the current user, catalog, schema,
--   visible catalogs/schemas/tables, and explain catalog.schema.object.
