-- [TUTORIAL-ACCEPTANCE — SAFE-READ]
-- ============================================================
-- Databricks Production Tutorials
-- Part 1.6 — Notebook Fundamentals
-- CANONICAL LAB
-- ============================================================
--
-- PURPOSE
--   Safely practice notebook execution and inspect the current
--   Databricks session and visible Unity Catalog namespace
--   without intentionally modifying data, objects, permissions,
--   compute, or configuration.
--
-- SAFETY
--   • Use an approved training/development workspace.
--   • Use approved existing compute only.
--   • Do not start stopped compute solely for this lab.
--   • Read-only SQL can still consume compute and incur cost.
--   • Never expose credentials, secrets, PHI, PII, or
--     confidential production data.
--
-- CLASSIFICATION
--   [TUTORIAL-ACCEPTANCE — SAFE-READ]
-- ============================================================

-- 1. CURRENT SESSION CONTEXT
SELECT
    session_user() AS session_user,
    current_catalog() AS current_catalog,
    current_schema() AS current_schema;

-- 2. VISIBLE CATALOGS
-- Results depend on current authorization.
-- Do not interpret this as a global inventory.
SHOW CATALOGS;

-- 3. VISIBLE SCHEMAS
-- Intentionally do not change catalog context.
SHOW SCHEMAS;

-- 4. VISIBLE TABLES
-- Intentionally do not change schema context.
SHOW TABLES;

-- 5. DETERMINISTIC STATELESS SQL
-- Run this statement more than once. The expected logical result
-- remains 15 and no persistent object or data is modified.
SELECT
    10 AS base_value,
    5 AS increment_value,
    10 + 5 AS expected_result;

-- 6. VERIFY SESSION CONTEXT AGAIN
-- Compare this with Section 1. The lab intentionally does not
-- execute USE CATALOG or USE SCHEMA.
SELECT
    session_user() AS session_user,
    current_catalog() AS current_catalog,
    current_schema() AS current_schema;

-- ============================================================
-- MANUAL READ-ONLY NOTEBOOK OBSERVATION
-- ============================================================
-- Observe only, where applicable and authorized:
-- [ ] Notebook default language
-- [ ] Cell types
-- [ ] Existing compute type
-- [ ] Serverless / Classic / SQL Warehouse
-- [ ] Notebook execution status
-- [ ] Existing notebook permissions — if authorized
--
-- DO NOT create, start, stop, restart, resize, edit, or delete
-- compute solely to complete this tutorial.
-- DO NOT modify notebook permissions, widgets, serverless
-- permissions, or Unity Catalog permissions.

-- ============================================================
-- LEARNING ACCEPTANCE
-- ============================================================
-- [ ] Notebook vs compute understood
-- [ ] Notebook cells understood
-- [ ] Executable languages understood
-- [ ] Markdown distinction understood
-- [ ] Default language understood
-- [ ] Magic commands understood
-- [ ] Execution-order risk understood
-- [ ] Hidden-state risk understood
-- [ ] Language REPL isolation understood
-- [ ] Clean-session reproducibility understood
-- [ ] Widgets/parameters understood
-- [ ] Widget string-value semantics understood
-- [ ] Parameter validation understood
-- [ ] Parameters are not security controls
-- [ ] Notebook dependencies understood
-- [ ] %run dependency risk understood
-- [ ] Reusable module pattern understood
-- [ ] Git folder/source-control model understood
-- [ ] Notebook history limitation understood
-- [ ] Notebook/compute/UC permission separation understood
-- [ ] Serverless notebook model understood
-- [ ] SQL warehouse cost/auto-start implication understood
-- [ ] Lakeflow Jobs notebook-task model understood
-- [ ] Rerun/idempotency risk understood
-- [ ] Secret-handling requirements understood
-- [ ] Sensitive-output risk understood
-- [ ] Stale-result risk understood
-- [ ] AWS/Azure/GCP implementation differences understood

-- ============================================================
-- SAFETY ACCEPTANCE
-- ============================================================
-- [ ] Approved training/development workspace used
-- [ ] Approved existing compute used
-- [ ] No stopped compute started solely for lab
-- [ ] No compute created/restarted/stopped/resized
-- [ ] No runtime/access-mode/policy change
-- [ ] No CREATE / ALTER / DROP
-- [ ] No INSERT / UPDATE / DELETE / MERGE
-- [ ] No GRANT / REVOKE
-- [ ] No USE CATALOG / USE SCHEMA
-- [ ] No widgets created or modified
-- [ ] No notebook permissions changed
-- [ ] No serverless permissions changed
-- [ ] No Unity Catalog permissions changed
-- [ ] No storage/network configuration changed
-- [ ] No credentials or secrets exposed
-- [ ] No PHI / PII / confidential data displayed
-- ============================================================
-- [TUTORIAL-ACCEPTANCE — SAFE-READ]
-- ============================================================
