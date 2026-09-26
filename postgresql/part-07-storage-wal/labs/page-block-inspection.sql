-- ============================================================
-- PostgreSQL Part 7.2 - Pages, Blocks, and Physical Layout
-- File: page-block-inspection.sql
-- Target: PostgreSQL 18
-- Classification: SAFE-READ
--
-- Level 1: baseline inventory only.
-- Level 2: optional structural page-header inspection when the
--          operator explicitly supplies a target.
--
-- This lab does NOT:
--   CREATE EXTENSION, CREATE/ALTER/DROP objects, perform DML,
--   VACUUM, CHECKPOINT, reset statistics, change configuration,
--   modify files/WAL, terminate sessions, or print raw page bytea.
--
-- Run with psql.
--
-- Optional Level 2 example:
--   psql -v inspect_schema=public \
--        -v inspect_relation=my_table \
--        -v inspect_block=0 \
--        -f page-block-inspection.sql mydb
--
-- If target variables are omitted, only Level 1 runs.
-- ============================================================

\set ON_ERROR_STOP on

\echo ''
\echo '============================================================'
\echo 'Part 7.2 - Page and Block Inspection'
\echo 'Classification: SAFE-READ'
\echo '============================================================'

-- Optional variables default to empty strings / block zero.
\if :{?inspect_schema}
\else
  \set inspect_schema ''
\endif

\if :{?inspect_relation}
\else
  \set inspect_relation ''
\endif

\if :{?inspect_block}
\else
  \set inspect_block '0'
\endif

\echo ''
\echo '=== 1. Execution context ==='

SELECT clock_timestamp() AS observed_at,
       version() AS postgres_version,
       current_database() AS database_name,
       current_user AS session_user,
       pg_is_in_recovery() AS is_in_recovery;

\echo ''
\echo '=== 2. Page/block configuration ==='

SELECT current_setting('block_size')::bigint AS block_size_bytes,
       pg_size_pretty(current_setting('block_size')::bigint)
           AS block_size_pretty,
       current_setting('data_checksums') AS data_checksums;

\echo ''
\echo '=== 3. pageinspect prerequisite ==='

SELECT CASE
         WHEN EXISTS (
           SELECT 1
           FROM pg_extension
           WHERE extname = 'pageinspect'
         )
         THEN 'OBSERVED: pageinspect installed'
         ELSE 'PREREQUISITE NOT MET: pageinspect not installed'
       END AS pageinspect_status;

\echo ''
\echo '=== 4. User-relation block inventory ==='
\echo 'No raw pages are read in this section.'

WITH cfg AS (
    SELECT current_setting('block_size')::bigint AS block_size
)
SELECT n.nspname AS schema_name,
       c.relname AS relation_name,
       c.relkind,
       pg_relation_size(c.oid, 'main') AS main_fork_bytes,
       pg_size_pretty(pg_relation_size(c.oid, 'main'))
           AS main_fork_pretty,
       CASE
         WHEN cfg.block_size > 0
         THEN pg_relation_size(c.oid, 'main') / cfg.block_size
       END AS main_fork_blocks,
       pg_relation_filepath(c.oid) AS relation_filepath
FROM pg_class AS c
JOIN pg_namespace AS n
  ON n.oid = c.relnamespace
CROSS JOIN cfg
WHERE c.relkind IN ('r', 'm')
  AND n.nspname NOT IN ('pg_catalog', 'information_schema')
  AND n.nspname !~ '^pg_toast'
ORDER BY pg_relation_size(c.oid, 'main') DESC
LIMIT 20;

\echo ''
\echo '=== 5. Optional Level 2 target request ==='

SELECT NULLIF(:'inspect_schema', '') AS requested_schema,
       NULLIF(:'inspect_relation', '') AS requested_relation,
       :'inspect_block' AS requested_block,
       CASE
         WHEN NULLIF(:'inspect_schema', '') IS NULL
           OR NULLIF(:'inspect_relation', '') IS NULL
         THEN 'NOT APPLICABLE: no explicit inspection target supplied'
         ELSE 'TARGET SUPPLIED: validation required'
       END AS target_status;

-- Determine whether an explicit target was supplied.
SELECT CASE
         WHEN NULLIF(:'inspect_schema', '') IS NOT NULL
          AND NULLIF(:'inspect_relation', '') IS NOT NULL
         THEN 'true'
         ELSE 'false'
       END AS run_level2
\gset

\if :run_level2

\echo ''
\echo '=== 6. Validate explicit target ==='

-- Capture target OID and block count only if the named relation exists
-- and is a supported ordinary/materialized relation.
WITH target AS (
    SELECT c.oid,
           n.nspname,
           c.relname,
           c.relkind,
           pg_relation_size(c.oid, 'main') AS main_bytes,
           current_setting('block_size')::bigint AS block_size
    FROM pg_class AS c
    JOIN pg_namespace AS n
      ON n.oid = c.relnamespace
    WHERE n.nspname = :'inspect_schema'
      AND c.relname = :'inspect_relation'
      AND c.relkind IN ('r', 'm')
)
SELECT COALESCE(oid::text, '') AS target_oid,
       COALESCE(nspname, '') AS target_schema,
       COALESCE(relname, '') AS target_relation,
       COALESCE(relkind::text, '') AS target_relkind,
       COALESCE(main_bytes::text, '0') AS target_main_bytes,
       COALESCE(
         CASE WHEN block_size > 0
              THEN (main_bytes / block_size)::text
         END,
         '0'
       ) AS target_blocks
FROM target
\gset

\if :{?target_oid}

SELECT :'target_schema' AS schema_name,
       :'target_relation' AS relation_name,
       :'target_relkind' AS relkind,
       :'target_main_bytes'::bigint AS main_fork_bytes,
       :'target_blocks'::bigint AS main_fork_blocks,
       :'inspect_block'::bigint AS requested_block,
       CASE
         WHEN :'inspect_block' !~ '^[0-9]+$'
           THEN 'REVIEW: block number must be a non-negative integer'
         WHEN :'inspect_block'::numeric >= :'target_blocks'::numeric
           THEN 'REVIEW: requested block is outside the main fork'
         ELSE 'OBSERVED: target and block bounds valid'
       END AS target_validation;

-- Convert validation gates into psql variables.
SELECT CASE
         WHEN :'inspect_block' ~ '^[0-9]+$'
          AND :'inspect_block'::numeric < :'target_blocks'::numeric
         THEN 'true'
         ELSE 'false'
       END AS block_valid,
       CASE
         WHEN EXISTS (
           SELECT 1 FROM pg_extension WHERE extname = 'pageinspect'
         )
         THEN 'true'
         ELSE 'false'
       END AS pageinspect_ready
\gset

\if :block_valid
  \if :pageinspect_ready

\echo ''
\echo '=== 7. Structural page-header inspection ==='
\echo 'Raw page bytea is consumed inside the query and is never printed.'

-- Resolve extension schema so pageinspect need not be installed in public.
SELECT quote_ident(n.nspname) AS pageinspect_schema
FROM pg_extension AS e
JOIN pg_namespace AS n
  ON n.oid = e.extnamespace
WHERE e.extname = 'pageinspect'
\gset

-- Use regclass/OID resolution from the already validated target.
-- page_header() receives raw bytea internally; the raw page is not selected.
SELECT format(
$q$
WITH hdr AS (
  SELECT %1$s.page_header(
           %1$s.get_raw_page(%2$L, 'main', %3$s)
         ) AS h
)
SELECT clock_timestamp() AS observed_at,
       current_database() AS database_name,
       %4$L AS schema_name,
       %5$L AS relation_name,
       %3$s::bigint AS block_number,
       current_setting('block_size')::bigint AS configured_block_size,
       (h).lsn,
       (h).checksum,
       (h).flags,
       (h).lower,
       (h).upper,
       (h).special,
       (h).pagesize,
       (h).version,
       (h).prune_xid,
       CASE
         WHEN (h).lower <= (h).upper
          AND (h).upper <= (h).special
          AND (h).special <= current_setting('block_size')::integer
         THEN (h).upper - (h).lower
         ELSE NULL
       END AS contiguous_page_free_bytes,
       CASE
         WHEN (h).lower <= (h).upper
          AND (h).upper <= (h).special
          AND (h).special <= current_setting('block_size')::integer
          AND (h).pagesize = current_setting('block_size')::integer
         THEN 'OBSERVED: structural boundaries consistent'
         ELSE 'REVIEW: structural boundary observation requires investigation'
       END AS structural_status,
       CASE
         WHEN current_setting('data_checksums') = 'on'
         THEN 'OBSERVED: checksum field is meaningful in checksum-enabled cluster'
         ELSE 'NOT APPLICABLE: data checksums disabled'
       END AS checksum_context
FROM hdr;
$q$,
:'pageinspect_schema',
:'target_schema' || '.' || :'target_relation',
:'inspect_block',
:'target_schema',
:'target_relation'
) AS inspection_sql
\gexec

  \else
    \echo 'PREREQUISITE NOT MET: pageinspect is not installed.'
  \endif
\else
  \echo 'REVIEW: page inspection skipped because block validation failed.'
\endif

\else
  \echo 'NOT APPLICABLE: requested relation does not exist or is not a supported ordinary/materialized relation.'
\endif

\else
\echo ''
\echo 'Level 2 skipped: no explicit target supplied.'
\endif

\echo ''
\echo '=== 8. Evidence interpretation ==='

SELECT clock_timestamp() AS completed_at,
       'OBSERVED'::text AS baseline_status,
       CASE
         WHEN NULLIF(:'inspect_schema', '') IS NULL
           OR NULLIF(:'inspect_relation', '') IS NULL
         THEN 'NOT APPLICABLE: optional page inspection not requested'
         ELSE 'Review Level 2 gate/output for inspection status'
       END AS page_inspection_status,
       'Missing evidence must remain UNKNOWN or be classified by the applicable gate.'::text
           AS interpretation;

\echo ''
\echo '============================================================'
\echo 'Part 7.2 SAFE-READ evidence collection complete.'
\echo 'page free space != filesystem free space'
\echo 'CTID != permanent logical row identifier'
\echo 'page inspection != permission to modify a page'
\echo 'structural anomaly != automatic corruption verdict'
\echo '============================================================'
