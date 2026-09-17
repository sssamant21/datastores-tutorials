-- [TUTORIAL-ACCEPTANCE — SAFE-READ]
-- Part 1.2 — Lakehouse Architecture Fundamentals
--
-- Purpose:
--   Inspect the learner's current Databricks context and visible
--   Unity Catalog hierarchy using discovery/read-only operations.
--
-- Safety:
--   This lab does not intentionally create, modify, or delete data.
--   Run only in an approved training/development workspace using
--   approved compute.
--   Never copy PHI, PII, credentials, tokens, or sensitive
--   environment information into tutorial artifacts.

-- ============================================================
-- 1. Current identity and namespace context
-- ============================================================

SELECT
    current_user() AS current_user,
    current_catalog() AS current_catalog,
    current_schema() AS current_schema;

-- ============================================================
-- 2. Discover visible catalogs
-- ============================================================

SHOW CATALOGS;

-- ============================================================
-- 3. OPTIONAL: select an authorized catalog
--
-- Intentionally commented.
-- Review and replace the placeholder before execution.
-- ============================================================

-- USE CATALOG <authorized_catalog>;

SHOW SCHEMAS;

-- ============================================================
-- 4. OPTIONAL: select an authorized schema
--
-- Intentionally commented.
-- Review and replace the placeholder before execution.
-- ============================================================

-- USE SCHEMA <authorized_schema>;

SHOW TABLES;

-- ============================================================
-- 5. Reconfirm current context
-- ============================================================

SELECT
    current_user() AS current_user,
    current_catalog() AS current_catalog,
    current_schema() AS current_schema;

-- ============================================================
-- ACCEPTANCE
-- ============================================================
--
-- The learner should be able to identify:
--
-- [ ] Current user
-- [ ] Current catalog
-- [ ] Current schema
-- [ ] Visible catalogs
-- [ ] Visible schemas
-- [ ] Visible tables
--
-- And explain:
--
-- [ ] Bronze layer
-- [ ] Silver layer
-- [ ] Gold layer
-- [ ] Delta Lake role
-- [ ] Unity Catalog role
-- [ ] Managed vs external tables
-- [ ] Batch vs streaming
-- [ ] Schema-drift risk
-- [ ] Checkpoint safety
-- [ ] Replay/idempotency considerations
--
-- No object creation, modification, or deletion is required.
