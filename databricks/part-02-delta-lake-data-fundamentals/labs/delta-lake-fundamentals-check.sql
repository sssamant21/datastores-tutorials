-- [TUTORIAL-ACCEPTANCE — SAFE-READ]
-- ============================================================
-- Databricks Production Tutorials
-- Part 2.1 — Delta Lake Fundamentals
-- CANONICAL LAB
-- ============================================================
-- PURPOSE
--   Safely inspect the current session and metadata for an
--   explicitly approved non-sensitive Delta table.
--
-- IMPORTANT
--   <catalog>.<schema>.<table> is instructional placeholder text.
--   Replace it ONLY with an explicitly approved training or
--   development Delta table before executing DESCRIBE commands.
--
-- COMPUTE SAFETY
--   Use approved existing compute. Do not start stopped compute
--   solely for this tutorial. Read-only SQL can incur cost.
--
-- DATA SAFETY
--   Metadata-only inspection is the canonical acceptance path.
--   Do not display PHI, PII, credentials, secrets, or confidential
--   customer data.
-- ============================================================

-- 1. Current session context
SELECT
    session_user() AS session_user,
    current_catalog() AS current_catalog,
    current_schema() AS current_schema;

-- 2. Visible catalogs. Visibility depends on authorization.
SHOW CATALOGS;

-- 3. Visible schemas. Intentionally no USE CATALOG.
SHOW SCHEMAS;

-- 4. Visible tables. Intentionally no USE SCHEMA.
SHOW TABLES;

-- 5. Approved Delta table schema.
-- STOP if the placeholder has not been replaced with an approved table.
DESCRIBE TABLE <catalog>.<schema>.<table>;

-- 6. Approved Delta table detail.
-- Output can expose locations or operational metadata. Minimize sharing.
DESCRIBE DETAIL <catalog>.<schema>.<table>;

-- 7. Approved Delta table history.
-- History can expose identities, operations, timestamps, and workload context.
DESCRIBE HISTORY <catalog>.<schema>.<table>;

-- 8. OPTIONAL ROW-LEVEL READ — NOT REQUIRED FOR ACCEPTANCE.
-- Leave commented unless the table is deliberately synthetic training data
-- and row-level inspection is explicitly approved.
-- SELECT *
-- FROM <catalog>.<schema>.<table>
-- LIMIT 10;

-- 9. Verify session context.
SELECT
    session_user() AS session_user,
    current_catalog() AS current_catalog,
    current_schema() AS current_schema;

-- ============================================================
-- LEARNING ACCEPTANCE
-- ============================================================
-- [ ] Delta Lake vs Databricks understood
-- [ ] Delta Lake vs Parquet understood
-- [ ] Transaction log and logical vs physical state understood
-- [ ] Table versions and ACID fundamentals understood
-- [ ] Snapshot reads/write isolation/optimistic concurrency understood
-- [ ] Row-level concurrency understood conceptually
-- [ ] Schema enforcement/evolution understood
-- [ ] Schema changes treated as data-contract changes
-- [ ] History and time travel understood
-- [ ] Time travel vs backup distinction understood
-- [ ] History vs deleted-data-file retention understood
-- [ ] VACUUM risk understood
-- [ ] Managed vs external lifecycle understood
-- [ ] Unity Catalog vs Delta responsibilities understood
-- [ ] Table-feature/protocol compatibility risk understood
-- [ ] Batch + streaming relationship understood
-- [ ] Streaming checkpoint distinction understood
-- [ ] Retention/streaming-lag relationship understood
-- [ ] Commit-state verification and idempotency understood
-- [ ] Raw-file and _delta_log protection understood

-- ============================================================
-- SAFETY ACCEPTANCE
-- ============================================================
-- [ ] Approved training/development workspace used
-- [ ] Approved existing compute used
-- [ ] Approved non-sensitive Delta table used
-- [ ] Placeholder intentionally replaced
-- [ ] No stopped compute started solely for lab
-- [ ] No CREATE / CREATE OR REPLACE
-- [ ] No INSERT / UPDATE / DELETE / MERGE
-- [ ] No ALTER / DROP / RESTORE / CLONE / OPTIMIZE / VACUUM
-- [ ] No schema evolution enabled
-- [ ] No table properties/features/protocol/retention changed
-- [ ] No GRANT / REVOKE
-- [ ] No USE CATALOG / USE SCHEMA
-- [ ] No streaming checkpoint modified/deleted
-- [ ] No raw storage file modified/deleted
-- [ ] No _delta_log object modified/deleted
-- [ ] No cloud lifecycle/storage/network configuration changed
-- [ ] No credentials/secrets exposed
-- [ ] No PHI / PII / confidential customer data displayed
-- ============================================================
-- [TUTORIAL-ACCEPTANCE — SAFE-READ]
-- ============================================================
