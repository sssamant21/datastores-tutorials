-- [TUTORIAL-ACCEPTANCE — SAFE-READ]
-- ============================================================
-- Databricks Production Tutorials
-- Part 1.5 — Compute Fundamentals
-- ============================================================
-- PURPOSE
--   Safely inspect the current Databricks session and visible
--   Unity Catalog namespace without intentionally modifying
--   data, objects, permissions, compute, or configuration.
-- SAFETY
--   • Run only on approved development/training resources.
--   • Use approved existing compute only.
--   • Do not start stopped compute solely for this lab.
--   • Never expose credentials, tokens, PHI, PII, or
--     sensitive production identifiers.
-- CLASSIFICATION
--   [TUTORIAL-ACCEPTANCE — SAFE-READ]
-- ============================================================

-- 1. CURRENT IDENTITY AND NAMESPACE
SELECT
    session_user() AS session_user,
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

-- 5. VERIFY SESSION CONTEXT REMAINS UNCHANGED
SELECT
    session_user() AS session_user,
    current_catalog() AS current_catalog,
    current_schema() AS current_schema;

-- MANUAL READ-ONLY COMPUTE OBSERVATION
-- Observe only, where applicable and authorized:
-- [ ] Compute type
-- [ ] Serverless / Classic / SQL Warehouse
-- [ ] Interactive / Automated
-- [ ] Standard / Dedicated — if applicable
-- [ ] Runtime — if applicable
-- [ ] Current state
-- [ ] Autoscaling — if applicable
-- [ ] Auto-termination / auto-stop — if applicable
-- [ ] Policy — only if authorized to view
-- DO NOT create, start, stop, restart, resize, edit, or delete
-- compute solely to complete this tutorial.

-- LEARNING ACCEPTANCE
-- [ ] Compute vs storage understood
-- [ ] Serverless vs classic understood
-- [ ] Interactive vs automated compute understood
-- [ ] SQL warehouse purpose and auto-start cost understood
-- [ ] Driver and worker concepts understood
-- [ ] Single-node classic compute understood
-- [ ] Classic autoscaling / serverless scaling distinction understood
-- [ ] Auto-termination understood
-- [ ] Databricks Runtime and Photon understood
-- [ ] Auto / Standard / Dedicated understood
-- [ ] Compute policies understood
-- [ ] Compute permission vs UC privilege understood
-- [ ] Ephemeral compute / local-storage durability understood
-- [ ] FinOps fundamentals understood
-- [ ] AWS/Azure/GCP differences understood

-- SAFETY ACCEPTANCE
-- [ ] No compute created
-- [ ] No stopped compute started solely for lab
-- [ ] No compute restarted/resized/terminated
-- [ ] No runtime or access mode changed
-- [ ] No compute policy changed
-- [ ] No serverless or Unity Catalog permission changed
-- [ ] No CREATE / ALTER / DROP
-- [ ] No INSERT / UPDATE / DELETE / MERGE
-- [ ] No GRANT / REVOKE
-- [ ] No USE CATALOG / USE SCHEMA
-- [ ] No storage or network configuration modified
-- [ ] No credentials exposed
-- [ ] No PHI / PII used

-- ============================================================
-- [TUTORIAL-ACCEPTANCE — SAFE-READ]
-- ============================================================
