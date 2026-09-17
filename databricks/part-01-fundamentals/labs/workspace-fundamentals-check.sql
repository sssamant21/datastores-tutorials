-- [TUTORIAL-ACCEPTANCE — SAFE-READ]
-- ============================================================
-- Databricks Production Tutorials
-- Part 1.4 — Workspace Fundamentals
-- ============================================================
--
-- PURPOSE
--   Inspect the current Databricks identity and visible
--   Unity Catalog namespace without intentionally modifying
--   data, objects, permissions, compute, or configuration.
--
-- SAFETY
--   • Use an approved development/training workspace.
--   • Use approved existing compute only.
--   • Never expose credentials, tokens, PHI, PII, or
--     sensitive production identifiers.
--
-- CLASSIFICATION
--   [TUTORIAL-ACCEPTANCE — SAFE-READ]
-- ============================================================

-- 1. CURRENT IDENTITY AND NAMESPACE
SELECT
    current_user() AS current_user,
    current_catalog() AS current_catalog,
    current_schema() AS current_schema;

-- 2. VISIBLE CATALOGS
SHOW CATALOGS;

-- 3. VISIBLE SCHEMAS
-- Intentionally do not change catalog context.
SHOW SCHEMAS;

-- 4. VISIBLE TABLES
-- Intentionally do not change schema context.
SHOW TABLES;

-- 5. VERIFY CONTEXT REMAINS UNCHANGED
SELECT
    current_user() AS current_user,
    current_catalog() AS current_catalog,
    current_schema() AS current_schema;

-- ============================================================
-- LEARNING ACCEPTANCE
-- ============================================================
-- [ ] Account vs workspace understood
-- [ ] Workspace browser understood
-- [ ] Workspace assets vs UC objects understood
-- [ ] Workspace folder vs schema understood
-- [ ] Workspace file vs volume understood
-- [ ] Notebook vs compute understood
-- [ ] Git folder concept understood
-- [ ] Git permission vs UC permission understood
-- [ ] User home folder understood
-- [ ] Shared-folder safety understood
-- [ ] Workspace permission vs UC privilege understood
-- [ ] Workspace-catalog binding understood
-- [ ] Same-region workspace/metastore relationship understood
-- [ ] Workspace storage safety understood
-- [ ] AWS/Azure/GCP implementation differences understood
--
-- SAFETY ACCEPTANCE
-- [ ] No CREATE executed
-- [ ] No ALTER executed
-- [ ] No DROP executed
-- [ ] No INSERT executed
-- [ ] No UPDATE executed
-- [ ] No DELETE executed
-- [ ] No MERGE executed
-- [ ] No GRANT / REVOKE executed
-- [ ] No USE CATALOG executed
-- [ ] No USE SCHEMA executed
-- [ ] No workspace object created/deleted
-- [ ] No workspace binding modified
-- [ ] No compute modified
-- [ ] No storage configuration modified
-- [ ] No network configuration modified
-- [ ] No credentials exposed
-- [ ] No PHI / PII used
-- ============================================================
-- [TUTORIAL-ACCEPTANCE — SAFE-READ]
-- ============================================================
