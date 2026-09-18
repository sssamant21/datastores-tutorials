-- ============================================================================
-- Part 3.6 — Generated Columns and Default Values
-- File: labs/generated-defaults-lab.sql
-- Classification: [LAB-ONLY — MUTATING — TRANSACTIONALLY CONTAINED]
-- Target: PostgreSQL 18
--
-- Run only in an authorized disposable, non-production database.
-- This script creates isolated objects and finishes with ROLLBACK.
-- Do not add COMMIT. Use a dedicated psql session.
-- Transactionally contained does not mean read-only or zero-cost: this lab
-- takes locks, creates catalog entries, writes rows, and generates WAL.
-- ============================================================================

\set ON_ERROR_STOP on
\pset pager off

\echo 'Part 3.6 — Generated Columns and Default Values lab'

\if :{?lab_confirm}
\else
    \echo 'ERROR: explicit acknowledgement is required.'
    \echo 'Run with: -v lab_confirm=I_UNDERSTAND'
    \quit 3
\endif

SELECT :'lab_confirm' = 'I_UNDERSTAND' AS lab_confirmed \gset
\if :lab_confirmed
\else
    \echo 'ERROR: lab_confirm must equal I_UNDERSTAND.'
    \quit 3
\endif

SELECT
    current_database() AS database_name,
    current_user AS current_user,
    inet_server_addr() AS server_address,
    inet_server_port() AS server_port,
    pg_is_in_recovery() AS in_recovery;

SELECT to_regnamespace('tutorial_generated_admin') IS NULL AS collision_free
\gset

\if :collision_free
    \echo 'Preflight passed: tutorial schema name is unused.'
\else
    \echo 'ERROR: tutorial_generated_admin already exists.'
    \echo 'The lab will not reuse or remove an existing schema.'
    \quit 4
\endif

BEGIN;

SET LOCAL lock_timeout = '5s';
SET LOCAL statement_timeout = '2min';
SET LOCAL idle_in_transaction_session_timeout = '5min';

CREATE SCHEMA tutorial_generated_admin;

CREATE TABLE tutorial_generated_admin.invoice_line (
    line_id bigint GENERATED ALWAYS AS IDENTITY,
    item_code text NOT NULL,
    quantity numeric(10,2) NOT NULL DEFAULT 1,
    unit_price numeric(12,2) NOT NULL,
    source_system text DEFAULT 'tutorial',
    created_at timestamptz NOT NULL DEFAULT CURRENT_TIMESTAMP,
    line_total numeric(14,2)
        GENERATED ALWAYS AS (quantity * unit_price) STORED,
    item_code_upper text
        GENERATED ALWAYS AS (upper(item_code)) VIRTUAL,
    CONSTRAINT invoice_line_pk PRIMARY KEY (line_id)
);

\echo 'Insert with omitted/defaulted values'
INSERT INTO tutorial_generated_admin.invoice_line
    (item_code, unit_price)
VALUES
    ('item-a', 12.50)
RETURNING
    line_id,
    item_code,
    quantity,
    unit_price,
    source_system,
    line_total,
    item_code_upper
\gset inserted_

SELECT
    :'inserted_quantity'::numeric = 1
    AND :'inserted_source_system' = 'tutorial'
    AND :'inserted_line_total'::numeric = 12.50
    AND :'inserted_item_code_upper' = 'ITEM-A'
        AS initial_values_correct
\gset

\if :initial_values_correct
    \echo 'PASS: defaults and generated values are correct after insert.'
\else
    \echo 'ERROR: initial default/generated values are incorrect.'
    \quit 5
\endif

\echo 'Explicit NULL is not replaced by a default'
INSERT INTO tutorial_generated_admin.invoice_line
    (item_code, quantity, unit_price, source_system)
VALUES
    ('item-null-source', 2, 3.00, NULL)
RETURNING source_system IS NULL AS explicit_null_preserved
\gset

\if :explicit_null_preserved
    \echo 'PASS: explicit NULL remained NULL.'
\else
    \echo 'ERROR: explicit NULL unexpectedly used the default.'
    \quit 6
\endif

\echo 'Update a base column and verify generated values'
UPDATE tutorial_generated_admin.invoice_line
SET quantity = 3,
    item_code = 'item-b'
WHERE line_id = :'inserted_line_id'::bigint
RETURNING
    line_total,
    item_code_upper
\gset updated_

SELECT
    :'updated_line_total'::numeric = 37.50
    AND :'updated_item_code_upper' = 'ITEM-B'
        AS updated_values_correct
\gset

\if :updated_values_correct
    \echo 'PASS: generated values followed base-column changes.'
\else
    \echo 'ERROR: generated values did not follow base-column changes.'
    \quit 7
\endif

\echo 'Prove DEFAULT is accepted as a generated-column placeholder'
INSERT INTO tutorial_generated_admin.invoice_line
    (item_code, quantity, unit_price, line_total, item_code_upper)
VALUES
    ('item-default-placeholder', 2, 4.00, DEFAULT, DEFAULT)
RETURNING
    line_total = 8.00
    AND item_code_upper = 'ITEM-DEFAULT-PLACEHOLDER'
        AS generated_default_accepted
\gset

\if :generated_default_accepted
    \echo 'PASS: DEFAULT placeholders produced generated values.'
\else
    \echo 'ERROR: DEFAULT placeholders did not produce generated values.'
    \quit 8
\endif

\echo 'Prove generated columns reject ordinary explicit values'
DO $lab$
BEGIN
    BEGIN
        INSERT INTO tutorial_generated_admin.invoice_line
            (item_code, quantity, unit_price, line_total)
        VALUES
            ('must-fail', 1, 5.00, 999.00);
        RAISE EXCEPTION 'expected generated_always violation was not raised';
    EXCEPTION
        WHEN generated_always THEN
            RAISE NOTICE 'Expected generated_always violation observed';
    END;
END
$lab$;

\echo 'Inspect portable column metadata'
SELECT
    table_schema,
    table_name,
    ordinal_position,
    column_name,
    column_default,
    is_generated,
    generation_expression
FROM information_schema.columns
WHERE table_schema = 'tutorial_generated_admin'
  AND table_name = 'invoice_line'
ORDER BY ordinal_position;

\echo 'Inspect PostgreSQL generated/default metadata'
SELECT
    a.attname AS column_name,
    a.atthasdef,
    a.attgenerated,
    pg_get_expr(ad.adbin, ad.adrelid) AS expression
FROM pg_attribute AS a
JOIN pg_class AS c
  ON c.oid = a.attrelid
JOIN pg_namespace AS n
  ON n.oid = c.relnamespace
LEFT JOIN pg_attrdef AS ad
  ON ad.adrelid = a.attrelid
 AND ad.adnum = a.attnum
WHERE n.nspname = 'tutorial_generated_admin'
  AND c.relname = 'invoice_line'
  AND a.attnum > 0
  AND NOT a.attisdropped
ORDER BY a.attnum;

SELECT
    count(*) FILTER (
        WHERE a.attname = 'line_total'
          AND a.attgenerated = 's'
    ) = 1
    AND count(*) FILTER (
        WHERE a.attname = 'item_code_upper'
          AND a.attgenerated = 'v'
    ) = 1 AS generated_kinds_correct
FROM pg_attribute AS a
JOIN pg_class AS c
  ON c.oid = a.attrelid
JOIN pg_namespace AS n
  ON n.oid = c.relnamespace
WHERE n.nspname = 'tutorial_generated_admin'
  AND c.relname = 'invoice_line'
  AND a.attnum > 0
  AND NOT a.attisdropped
\gset

\if :generated_kinds_correct
    \echo 'PASS: catalog reports stored and virtual generation exactly.'
\else
    \echo 'ERROR: generated-column catalog codes are incorrect.'
    \quit 9
\endif

\echo 'Acceptance row state'
SELECT
    line_id,
    item_code,
    quantity,
    unit_price,
    source_system,
    created_at,
    line_total,
    item_code_upper
FROM tutorial_generated_admin.invoice_line
ORDER BY line_id;

ROLLBACK;

SELECT
    to_regnamespace('tutorial_generated_admin') IS NULL
    AND to_regclass('tutorial_generated_admin.invoice_line') IS NULL
        AS rollback_cleanup_verified
\gset

\if :rollback_cleanup_verified
    \echo 'PASS: rollback removed the lab schema and table.'
\else
    \echo 'ERROR: rollback cleanup verification failed.'
    \quit 10
\endif

\echo 'LAB COMPLETE — all assertions passed and no lab objects remain.'
