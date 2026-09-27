-- PostgreSQL Part 7.3 - Tuples and Heap Storage Internals
-- File: heap-tuple-inspection.sql
-- Target: PostgreSQL 18
-- Classification: SAFE-READ
-- No DDL/DML, CREATE EXTENSION, VACUUM, CHECKPOINT, raw-page output,
-- t_data output, attribute decoding, or MVCC visibility verdicts.
--
-- Optional Level 2:
-- psql -v inspect_schema=public -v inspect_relation=my_table -v inspect_block=0 \
--      -f heap-tuple-inspection.sql mydb

\set ON_ERROR_STOP on

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

\echo '=== 1. Execution context ==='
SELECT clock_timestamp() AS observed_at,
       version() AS postgres_version,
       current_database() AS database_name,
       current_user AS session_user,
       pg_is_in_recovery() AS is_in_recovery,
       current_setting('block_size')::bigint AS block_size_bytes;

\echo '=== 2. pageinspect prerequisite ==='
SELECT CASE WHEN EXISTS (SELECT 1 FROM pg_extension WHERE extname='pageinspect')
            THEN 'OBSERVED: pageinspect installed'
            ELSE 'PREREQUISITE NOT MET: pageinspect not installed'
       END AS pageinspect_status;

\echo '=== 3. Target request ==='
SELECT NULLIF(:'inspect_schema','') AS requested_schema,
       NULLIF(:'inspect_relation','') AS requested_relation,
       :'inspect_block' AS requested_block,
       CASE WHEN NULLIF(:'inspect_schema','') IS NULL
                  OR NULLIF(:'inspect_relation','') IS NULL
            THEN 'NOT APPLICABLE: no explicit inspection target supplied'
            ELSE 'TARGET SUPPLIED: validation required'
       END AS target_status;

SELECT CASE WHEN NULLIF(:'inspect_schema','') IS NOT NULL
                  AND NULLIF(:'inspect_relation','') IS NOT NULL
            THEN 'true' ELSE 'false' END AS run_level2
\gset

\if :run_level2

\echo '=== 4. Validate ordinary heap-table target ==='
WITH target AS (
  SELECT c.oid, n.nspname, c.relname, c.relkind,
         pg_relation_size(c.oid,'main') AS main_bytes,
         current_setting('block_size')::bigint AS block_size
  FROM pg_class c
  JOIN pg_namespace n ON n.oid=c.relnamespace
  WHERE n.nspname=:'inspect_schema'
    AND c.relname=:'inspect_relation'
    AND c.relkind='r'
)
SELECT COALESCE(oid::text,'') AS target_oid,
       COALESCE(nspname,'') AS target_schema,
       COALESCE(relname,'') AS target_relation,
       COALESCE(main_bytes::text,'0') AS target_main_bytes,
       COALESCE((main_bytes/block_size)::text,'0') AS target_blocks
FROM target
\gset

\if :{?target_oid}

SELECT :'target_schema' AS schema_name,
       :'target_relation' AS relation_name,
       :'target_main_bytes'::bigint AS main_fork_bytes,
       :'target_blocks'::bigint AS main_fork_blocks,
       :'inspect_block' AS requested_block,
       CASE
         WHEN :'inspect_block' !~ '^[0-9]+$'
           THEN 'REVIEW: block number must be a non-negative integer'
         WHEN :'target_blocks'::numeric <= 0
           THEN 'NOT APPLICABLE: main fork contains no inspectable blocks'
         WHEN :'inspect_block'::numeric >= :'target_blocks'::numeric
           THEN 'REVIEW: requested block is outside the main fork'
         ELSE 'OBSERVED: heap target and block bounds valid'
       END AS target_validation;

SELECT CASE WHEN :'inspect_block' ~ '^[0-9]+$'
                  AND :'target_blocks'::numeric > 0
                  AND :'inspect_block'::numeric < :'target_blocks'::numeric
            THEN 'true' ELSE 'false' END AS block_valid,
       CASE WHEN EXISTS (SELECT 1 FROM pg_extension WHERE extname='pageinspect')
            THEN 'true' ELSE 'false' END AS pageinspect_ready
\gset

\if :block_valid
\if :pageinspect_ready

SELECT quote_ident(n.nspname) AS pageinspect_schema
FROM pg_extension e
JOIN pg_namespace n ON n.oid=e.extnamespace
WHERE e.extname='pageinspect'
\gset

\echo '=== 5. Structural heap-tuple metadata ==='
\echo 'Raw page bytea and t_data are never selected.'

SELECT format(
$q$
SELECT clock_timestamp() AS observed_at,
       current_database() AS database_name,
       %1$L AS schema_name,
       %2$L AS relation_name,
       %3$s::bigint AS block_number,
       h.lp, h.lp_off, h.lp_flags, h.lp_len,
       h.t_xmin, h.t_xmax, h.t_field3, h.t_ctid,
       h.t_infomask2, h.t_infomask, h.t_hoff,
       'OBSERVED'::text AS tuple_metadata_status
FROM %4$s.heap_page_items(
       %4$s.get_raw_page(%5$L, 'main', %3$s)
     ) h
ORDER BY h.lp;
$q$,
:'target_schema',
:'target_relation',
:'inspect_block',
:'pageinspect_schema',
format('%I.%I',:'target_schema',:'target_relation')
) AS inspection_sql
\gexec

\echo '=== 6. Interpretation boundary ==='
SELECT 'Physical tuple metadata only; no MVCC visibility verdict is produced.' AS interpretation,
       'xmax != 0 does not by itself mean the tuple is dead.' AS xmax_caution,
       'CTID is physical tuple-version location, not durable logical identity.' AS ctid_caution;

\else
\echo 'PREREQUISITE NOT MET: pageinspect is not installed.'
\endif
\else
\echo 'REVIEW: tuple inspection skipped because block validation failed.'
\endif

\else
\echo 'NOT APPLICABLE: target does not exist or is not an ordinary heap table (relkind=r).'
\endif

\else
\echo 'Level 2 skipped: no explicit target supplied.'
\endif

\echo '=== 7. Evidence summary ==='
SELECT clock_timestamp() AS completed_at,
       'OBSERVED'::text AS baseline_status,
       CASE WHEN NULLIF(:'inspect_schema','') IS NULL
                  OR NULLIF(:'inspect_relation','') IS NULL
            THEN 'NOT APPLICABLE: optional heap-tuple inspection not requested'
            ELSE 'Review Level 2 gate/output for inspection status'
       END AS tuple_inspection_status,
       'Missing evidence must remain UNKNOWN or be classified by the applicable gate.' AS interpretation;
