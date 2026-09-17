-- [TUTORIAL-ACCEPTANCE — SAFE-READ]
-- ============================================================
-- Databricks Production Tutorials
-- Part 1.3 — Databricks Platform Architecture
-- ============================================================
-- PURPOSE: Inspect current identity and Unity Catalog namespace
-- using discovery/read-only SQL.
-- SAFETY: Use approved training/development compute only. Never
-- expose PHI, PII, credentials, tokens, or sensitive production
-- identifiers. This lab does not intentionally create, modify,
-- or delete data or Databricks objects.

-- 1. CURRENT IDENTITY AND NAMESPACE
SELECT
    current_user() AS current_user,
    current_catalog() AS current_catalog,
    current_schema() AS current_schema;

-- 2. VISIBLE CATALOGS
SHOW CATALOGS;

-- 3. VISIBLE SCHEMAS
-- Optional only after reviewing an approved target:
-- USE CATALOG <authorized_catalog>;
SHOW SCHEMAS;

-- 4. VISIBLE TABLES
-- Optional only after reviewing an approved target:
-- USE SCHEMA <authorized_schema>;
SHOW TABLES;

-- 5. RECONFIRM CURRENT CONTEXT
SELECT
    current_user() AS current_user,
    current_catalog() AS current_catalog,
    current_schema() AS current_schema;

-- ============================================================
-- TUTORIAL ACCEPTANCE
-- ============================================================
-- Learner can identify:
-- [ ] Databricks account
-- [ ] Workspace
-- [ ] Control plane
-- [ ] Compute plane
-- [ ] Serverless compute plane
-- [ ] Classic compute plane
-- [ ] Unity Catalog / metastore / catalog / schema / object
-- [ ] Cloud object storage
--
-- Learner can explain:
-- [ ] Account vs workspace
-- [ ] Control plane vs compute plane
-- [ ] Serverless vs classic operational boundaries
-- [ ] Compute vs durable data
-- [ ] Workspace system data vs customer data
-- [ ] Why Unity Catalog is not cloud storage
-- [ ] Why IAM, UC, network and storage failures differ
-- [ ] Why classic/serverless need different network runbooks
-- [ ] Why AWS/Azure/GCP implementations differ
-- [ ] Why broad permission grants are unsafe troubleshooting
-- [ ] Why workspace storage must not be casually modified
--
-- FINAL SAFETY CHECK
-- [ ] No CREATE / ALTER / DROP
-- [ ] No DELETE / UPDATE / INSERT / MERGE
-- [ ] No GRANT / REVOKE
-- [ ] No storage or network configuration modified
-- [ ] No credentials exposed
-- [ ] No PHI / PII used
--
-- [TUTORIAL-ACCEPTANCE — SAFE-READ]
