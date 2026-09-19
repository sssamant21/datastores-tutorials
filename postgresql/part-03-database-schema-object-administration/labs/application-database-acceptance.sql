/*
===============================================================================
Part 3.15 — Integrated Application Database Acceptance
Canonical Acceptance Artifact

[TUTORIAL-ACCEPTANCE — SAFE-READ]

Target: PostgreSQL 18

Required psql variables:
  expected_database
  expected_schema
  expected_owner

Purpose:
  Validate the final Part 3.15 clinic application contract without changing
  database state or invoking user-defined routines.

Safety:
  - Catalog and project-table reads only
  - Aggregate sample counts only; no patient rows exported
  - No DDL or DML
  - No CALL
  - No execution of arbitrary user-defined functions
  - One REPEATABLE READ, READ ONLY transaction

Operational note:
  The transcript contains internal object, role, extension, dependency, and
  row-count metadata. Store and share it under the applicable evidence policy.

Exit codes:
  0 = all hard gates passed
  1 = fatal psql client error
  2 = connection failure in a non-interactive session
  3 = invalid input, unsupported/wrong target, or SQL/script failure under
      ON_ERROR_STOP
  4 = one or more final contract gates failed
===============================================================================
*/

\set ON_ERROR_STOP on
\pset pager off

\if :{?expected_database}
\else
  \echo 'ERROR: required psql variable expected_database is missing.'
  \quit 3
\endif
\if :{?expected_schema}
\else
  \echo 'ERROR: required psql variable expected_schema is missing.'
  \quit 3
\endif
\if :{?expected_owner}
\else
  \echo 'ERROR: required psql variable expected_owner is missing.'
  \quit 3
\endif

SELECT :'expected_database' ~ '^[a-z][a-z0-9_]*$'
   AND :'expected_schema' ~ '^[a-z][a-z0-9_]*$'
   AND :'expected_owner' ~ '^[a-z][a-z0-9_]*$' AS inputs_valid
\gset
\if :inputs_valid
\else
  \echo 'ERROR: inputs must be unquoted lowercase identifiers matching ^[a-z][a-z0-9_]*$.'
  \quit 3
\endif

SELECT :'expected_database' = 'clinic_app_lab'
   AND :'expected_schema' = 'clinic' AS canonical_target
\gset
\if :canonical_target
\else
  \echo 'ERROR: this project contract requires database clinic_app_lab and schema clinic.'
  \quit 3
\endif

SELECT current_setting('server_version_num')::integer / 10000 = 18 AS supported_major,
       current_database() = :'expected_database' AS correct_database
\gset
\if :supported_major
\else
  \echo 'ERROR: this artifact is validated only for PostgreSQL major 18.'
  \quit 3
\endif
\if :correct_database
\else
  \echo 'ERROR: connected to the wrong database; aborting before project inventory.'
  \quit 3
\endif

BEGIN TRANSACTION ISOLATION LEVEL REPEATABLE READ READ ONLY;

\echo ''
\echo '============================================================'
\echo 'Part 3.15 — Application Database Acceptance'
\echo '[TUTORIAL-ACCEPTANCE — SAFE-READ]'
\echo '============================================================'

-- 1. Execution context
\echo ''
\echo '--- [1/15] Execution context and declared contract ---'
SELECT current_setting('server_version') AS server_version,
       current_database() AS database_name,
       current_user AS current_user,
       session_user AS session_user,
       current_setting('transaction_isolation') AS isolation_level,
       current_setting('transaction_read_only') AS transaction_read_only,
       :'expected_schema' AS expected_schema,
       :'expected_owner' AS expected_owner,
       statement_timestamp() AS collected_at;

-- 2. Database and schema boundary
\echo ''
\echo '--- [2/15] Database and schema boundary ---'
SELECT d.datname AS database_name,
       pg_catalog.pg_get_userbyid(d.datdba) AS database_owner,
       n.nspname AS schema_name,
       pg_catalog.pg_get_userbyid(n.nspowner) AS schema_owner
FROM pg_catalog.pg_database AS d
LEFT JOIN pg_catalog.pg_namespace AS n ON n.nspname = :'expected_schema'
WHERE d.datname = current_database();

-- 3. Required relation manifest
\echo ''
\echo '--- [3/15] Required relation manifest ---'
WITH expected(object_name, expected_kind) AS (
    VALUES ('patients', 'r'::"char"),
           ('appointments', 'r'::"char"),
           ('appointment_events', 'r'::"char"),
           ('appointment_schedule_v', 'v'::"char"),
           ('daily_appointment_summary_mv', 'm'::"char")
)
SELECT e.object_name,
       CASE e.expected_kind WHEN 'r' THEN 'TABLE' WHEN 'v' THEN 'VIEW'
                            WHEN 'm' THEN 'MATERIALIZED VIEW' END AS expected_kind,
       COALESCE(c.relkind::text, '<missing>') AS actual_kind,
       pg_catalog.pg_get_userbyid(c.relowner) AS owner,
       c.relkind = e.expected_kind
         AND pg_catalog.pg_get_userbyid(c.relowner) = :'expected_owner' AS passes
FROM expected AS e
LEFT JOIN pg_catalog.pg_namespace AS n ON n.nspname = :'expected_schema'
LEFT JOIN pg_catalog.pg_class AS c
       ON c.relnamespace = n.oid AND c.relname = e.object_name
ORDER BY e.object_name;

-- The later sample-data checks use direct, schema-qualified table reads.
-- Fail cleanly before reaching them if any required base table is absent.
SELECT count(*) = 3 AS base_tables_ready
FROM pg_catalog.pg_class AS c
JOIN pg_catalog.pg_namespace AS n ON n.oid = c.relnamespace
WHERE n.nspname = :'expected_schema'
  AND c.relkind = 'r'
  AND c.relname IN ('patients', 'appointments', 'appointment_events')
\gset
\if :base_tables_ready
\else
  ROLLBACK;
  \echo 'FAIL: one or more required base tables are missing.'
  \quit 4
\endif

-- 4. Required table columns
\echo ''
\echo '--- [4/15] Required column contract ---'
WITH expected(table_name, column_name, formatted_type, not_null) AS (
    VALUES
      ('patients','patient_id','bigint',true),
      ('patients','external_patient_id','text',true),
      ('patients','first_name','text',true),
      ('patients','last_name','text',true),
      ('patients','display_name','text',false),
      ('patients','date_of_birth','date',true),
      ('patients','created_at','timestamp with time zone',true),
      ('appointments','appointment_id','bigint',true),
      ('appointments','patient_id','bigint',true),
      ('appointments','starts_at','timestamp with time zone',true),
      ('appointments','ends_at','timestamp with time zone',true),
      ('appointments','status','text',true),
      ('appointments','reason','text',true),
      ('appointments','created_at','timestamp with time zone',true),
      ('appointments','check_in_at','timestamp with time zone',false),
      ('appointment_events','event_id','bigint',true),
      ('appointment_events','appointment_id','bigint',true),
      ('appointment_events','event_type','text',true),
      ('appointment_events','event_note','text',false),
      ('appointment_events','occurred_at','timestamp with time zone',true)
)
SELECT e.table_name, e.column_name, e.formatted_type AS expected_type,
       pg_catalog.format_type(a.atttypid, a.atttypmod) AS actual_type,
       e.not_null AS expected_not_null, a.attnotnull AS actual_not_null,
       a.attnum IS NOT NULL
         AND pg_catalog.format_type(a.atttypid, a.atttypmod) = e.formatted_type
         AND a.attnotnull = e.not_null AS passes
FROM expected AS e
LEFT JOIN pg_catalog.pg_namespace AS n ON n.nspname = :'expected_schema'
LEFT JOIN pg_catalog.pg_class AS c
       ON c.relnamespace = n.oid AND c.relname = e.table_name AND c.relkind = 'r'
LEFT JOIN pg_catalog.pg_attribute AS a
       ON a.attrelid = c.oid AND a.attname = e.column_name
      AND a.attnum > 0 AND NOT a.attisdropped
ORDER BY e.table_name, e.column_name;

-- 5. Identity, generated, and default attributes
\echo ''
\echo '--- [5/15] Identity, generated, and default attributes ---'
SELECT c.relname AS table_name, a.attname AS column_name,
       NULLIF(a.attidentity, '') AS identity_kind,
       NULLIF(a.attgenerated, '') AS generated_kind,
       pg_catalog.pg_get_expr(ad.adbin, ad.adrelid) AS default_expression
FROM pg_catalog.pg_attribute AS a
JOIN pg_catalog.pg_class AS c ON c.oid = a.attrelid
JOIN pg_catalog.pg_namespace AS n ON n.oid = c.relnamespace
LEFT JOIN pg_catalog.pg_attrdef AS ad
       ON ad.adrelid = a.attrelid AND ad.adnum = a.attnum
WHERE n.nspname = :'expected_schema'
  AND c.relname IN ('patients','appointments','appointment_events')
  AND a.attname IN ('patient_id','appointment_id','event_id','display_name',
                    'status','created_at','occurred_at')
  AND a.attnum > 0 AND NOT a.attisdropped
ORDER BY c.relname, a.attnum;

-- 6. Required named constraints
\echo ''
\echo '--- [6/15] Required constraint manifest ---'
WITH expected(table_name, constraint_name, constraint_type) AS (
    VALUES
      ('patients','patients_pkey','p'::"char"),
      ('patients','patients_external_patient_id_key','u'::"char"),
      ('patients','patients_external_patient_id_check','c'::"char"),
      ('appointments','appointments_pkey','p'::"char"),
      ('appointments','appointments_patient_id_fkey','f'::"char"),
      ('appointments','appointments_time_order_check','c'::"char"),
      ('appointments','appointments_status_check','c'::"char"),
      ('appointments','appointments_check_in_window_check','c'::"char"),
      ('appointment_events','appointment_events_pkey','p'::"char"),
      ('appointment_events','appointment_events_appointment_id_fkey','f'::"char"),
      ('appointment_events','appointment_events_event_type_check','c'::"char")
)
SELECT e.table_name, e.constraint_name,
       COALESCE(con.contype::text, '<missing>') AS actual_type,
       con.conenforced, con.convalidated,
       con.oid IS NOT NULL AND con.contype = e.constraint_type
         AND con.conenforced AND con.convalidated AS passes
FROM expected AS e
LEFT JOIN pg_catalog.pg_namespace AS n ON n.nspname = :'expected_schema'
LEFT JOIN pg_catalog.pg_class AS c
       ON c.relnamespace = n.oid AND c.relname = e.table_name
LEFT JOIN pg_catalog.pg_constraint AS con
       ON con.conrelid = c.oid AND con.conname = e.constraint_name
ORDER BY e.table_name, e.constraint_name;

-- 7. Foreign-key targets
\echo ''
\echo '--- [7/15] Foreign-key targets and actions ---'
SELECT src.relname AS source_table, con.conname,
       dst_ns.nspname AS target_schema, dst.relname AS target_table,
       con.confdeltype AS delete_action_code,
       pg_catalog.pg_get_constraintdef(con.oid, true) AS definition
FROM pg_catalog.pg_constraint AS con
JOIN pg_catalog.pg_class AS src ON src.oid = con.conrelid
JOIN pg_catalog.pg_namespace AS src_ns ON src_ns.oid = src.relnamespace
JOIN pg_catalog.pg_class AS dst ON dst.oid = con.confrelid
JOIN pg_catalog.pg_namespace AS dst_ns ON dst_ns.oid = dst.relnamespace
WHERE src_ns.nspname = :'expected_schema' AND con.contype = 'f'
ORDER BY src.relname, con.conname;

-- 8. Index health
\echo ''
\echo '--- [8/15] Index health and materialized-view unique index ---'
SELECT parent.relname AS parent_object, idx.relname AS index_name,
       i.indisunique, i.indislive, i.indisready, i.indisvalid,
       pg_catalog.pg_get_userbyid(idx.relowner) AS owner
FROM pg_catalog.pg_index AS i
JOIN pg_catalog.pg_class AS parent ON parent.oid = i.indrelid
JOIN pg_catalog.pg_class AS idx ON idx.oid = i.indexrelid
JOIN pg_catalog.pg_namespace AS n ON n.oid = parent.relnamespace
WHERE n.nspname = :'expected_schema'
ORDER BY parent.relname, idx.relname;

-- 9. View readiness
\echo ''
\echo '--- [9/15] View and materialized-view readiness ---'
SELECT c.relname AS object_name, c.relkind,
       CASE WHEN c.relkind = 'm' THEN c.relispopulated ELSE NULL END AS populated,
       pg_catalog.pg_get_userbyid(c.relowner) AS owner
FROM pg_catalog.pg_class AS c
JOIN pg_catalog.pg_namespace AS n ON n.oid = c.relnamespace
WHERE n.nspname = :'expected_schema'
  AND c.relname IN ('appointment_schedule_v','daily_appointment_summary_mv')
ORDER BY c.relname;

-- 10. Required routine identities
\echo ''
\echo '--- [10/15] Required routine identities and safety metadata ---'
SELECT p.proname AS routine_name,
       pg_catalog.pg_get_function_identity_arguments(p.oid) AS identity_arguments,
       CASE p.prokind WHEN 'f' THEN 'FUNCTION' WHEN 'p' THEN 'PROCEDURE' END AS kind,
       pg_catalog.pg_get_userbyid(p.proowner) AS owner,
       l.lanname AS language,
       p.prosecdef AS security_definer,
       p.provolatile AS volatility_code,
       p.proparallel AS parallel_code,
       p.proconfig AS routine_configuration
FROM pg_catalog.pg_proc AS p
JOIN pg_catalog.pg_namespace AS n ON n.oid = p.pronamespace
JOIN pg_catalog.pg_language AS l ON l.oid = p.prolang
WHERE n.nspname = :'expected_schema'
  AND p.proname IN ('appointment_duration_minutes','cancel_appointment')
ORDER BY p.proname, identity_arguments;

-- 11. Fictional sample-data minimums (direct reads; routines are not invoked)
\echo ''
\echo '--- [11/15] Fictional sample-data minimums ---'
SELECT (SELECT count(*) FROM clinic.patients) AS patient_count,
       (SELECT count(*) FROM clinic.appointments) AS appointment_count,
       (SELECT count(*) FROM clinic.appointment_events) AS event_count;

-- 12. Ownership drift
\echo ''
\echo '--- [12/15] Governed-object ownership drift ---'
SELECT object_kind, object_name, actual_owner
FROM (
    SELECT 'RELATION'::text AS object_kind, c.relname AS object_name,
           pg_catalog.pg_get_userbyid(c.relowner) AS actual_owner
    FROM pg_catalog.pg_class AS c
    JOIN pg_catalog.pg_namespace AS n ON n.oid = c.relnamespace
    WHERE n.nspname = :'expected_schema'
      AND c.relkind IN ('r','v','m','S')
    UNION ALL
    SELECT 'ROUTINE', p.proname || '(' ||
           pg_catalog.pg_get_function_identity_arguments(p.oid) || ')',
           pg_catalog.pg_get_userbyid(p.proowner)
    FROM pg_catalog.pg_proc AS p
    JOIN pg_catalog.pg_namespace AS n ON n.oid = p.pronamespace
    WHERE n.nspname = :'expected_schema'
) AS governed
WHERE actual_owner <> :'expected_owner'
ORDER BY object_kind, object_name;

-- 13. Extension review inventory
\echo ''
\echo '--- [13/15] Installed extension review inventory ---'
SELECT e.extname, e.extversion,
       pg_catalog.pg_get_userbyid(e.extowner) AS owner,
       n.nspname AS schema_name, e.extrelocatable
FROM pg_catalog.pg_extension AS e
JOIN pg_catalog.pg_namespace AS n ON n.oid = e.extnamespace
ORDER BY e.extname;

-- 14. Dependency review inventory
\echo ''
\echo '--- [14/15] Internal dependency edges involving project relations ---'
SELECT dependent_ns.nspname AS dependent_schema,
       dependent.relname AS dependent_object,
       referenced_ns.nspname AS referenced_schema,
       referenced.relname AS referenced_object,
       d.deptype
FROM pg_catalog.pg_depend AS d
JOIN pg_catalog.pg_class AS dependent ON dependent.oid = d.objid
JOIN pg_catalog.pg_namespace AS dependent_ns
  ON dependent_ns.oid = dependent.relnamespace
JOIN pg_catalog.pg_class AS referenced ON referenced.oid = d.refobjid
JOIN pg_catalog.pg_namespace AS referenced_ns
  ON referenced_ns.oid = referenced.relnamespace
WHERE dependent_ns.nspname = :'expected_schema'
   OR referenced_ns.nspname = :'expected_schema'
ORDER BY dependent_schema, dependent_object,
         referenced_schema, referenced_object, d.deptype;

-- 15. Final hard-gate verdict
\echo ''
\echo '--- [15/15] Final hard-gate verdict ---'
WITH
expected_rel(name, kind) AS (
  VALUES ('patients','r'::"char"),('appointments','r'::"char"),
         ('appointment_events','r'::"char"),('appointment_schedule_v','v'::"char"),
         ('daily_appointment_summary_mv','m'::"char")
),
relation_failures AS (
  SELECT e.name FROM expected_rel e
  LEFT JOIN pg_catalog.pg_namespace n ON n.nspname = :'expected_schema'
  LEFT JOIN pg_catalog.pg_class c
    ON c.relnamespace=n.oid AND c.relname=e.name AND c.relkind=e.kind
   AND pg_catalog.pg_get_userbyid(c.relowner)=:'expected_owner'
  WHERE c.oid IS NULL
),
expected_col(tbl,col,typ,nn,identity_kind,generated_kind,has_default) AS (
  VALUES
   ('patients','patient_id','bigint',true,'a','',false),
   ('patients','external_patient_id','text',true,'','',false),
   ('patients','first_name','text',true,'','',false),
   ('patients','last_name','text',true,'','',false),
   ('patients','display_name','text',false,'','s',true),
   ('patients','date_of_birth','date',true,'','',false),
   ('patients','created_at','timestamp with time zone',true,'','',true),
   ('appointments','appointment_id','bigint',true,'a','',false),
   ('appointments','patient_id','bigint',true,'','',false),
   ('appointments','starts_at','timestamp with time zone',true,'','',false),
   ('appointments','ends_at','timestamp with time zone',true,'','',false),
   ('appointments','status','text',true,'','',true),
   ('appointments','reason','text',true,'','',false),
   ('appointments','created_at','timestamp with time zone',true,'','',true),
   ('appointments','check_in_at','timestamp with time zone',false,'','',false),
   ('appointment_events','event_id','bigint',true,'a','',false),
   ('appointment_events','appointment_id','bigint',true,'','',false),
   ('appointment_events','event_type','text',true,'','',false),
   ('appointment_events','event_note','text',false,'','',false),
   ('appointment_events','occurred_at','timestamp with time zone',true,'','',true)
),
column_failures AS (
 SELECT e.tbl,e.col FROM expected_col e
 LEFT JOIN pg_catalog.pg_namespace n ON n.nspname=:'expected_schema'
 LEFT JOIN pg_catalog.pg_class c ON c.relnamespace=n.oid AND c.relname=e.tbl
 LEFT JOIN pg_catalog.pg_attribute a ON a.attrelid=c.oid AND a.attname=e.col
    AND a.attnum>0 AND NOT a.attisdropped
 LEFT JOIN pg_catalog.pg_attrdef ad ON ad.adrelid=a.attrelid AND ad.adnum=a.attnum
 WHERE a.attnum IS NULL OR pg_catalog.format_type(a.atttypid,a.atttypmod)<>e.typ
    OR a.attnotnull<>e.nn OR a.attidentity<>e.identity_kind
    OR a.attgenerated<>e.generated_kind OR (ad.oid IS NOT NULL)<>e.has_default
),
expected_con(tbl,name,typ) AS (
 VALUES
 ('patients','patients_pkey','p'::"char"),
 ('patients','patients_external_patient_id_key','u'::"char"),
 ('patients','patients_external_patient_id_check','c'::"char"),
 ('appointments','appointments_pkey','p'::"char"),
 ('appointments','appointments_patient_id_fkey','f'::"char"),
 ('appointments','appointments_time_order_check','c'::"char"),
 ('appointments','appointments_status_check','c'::"char"),
 ('appointments','appointments_check_in_window_check','c'::"char"),
 ('appointment_events','appointment_events_pkey','p'::"char"),
 ('appointment_events','appointment_events_appointment_id_fkey','f'::"char"),
 ('appointment_events','appointment_events_event_type_check','c'::"char")
),
constraint_failures AS (
 SELECT e.name FROM expected_con e
 LEFT JOIN pg_catalog.pg_namespace n ON n.nspname=:'expected_schema'
 LEFT JOIN pg_catalog.pg_class c ON c.relnamespace=n.oid AND c.relname=e.tbl
 LEFT JOIN pg_catalog.pg_constraint con
   ON con.conrelid=c.oid AND con.conname=e.name AND con.contype=e.typ
      AND con.conenforced AND con.convalidated
 WHERE con.oid IS NULL
),
index_failures AS (
 SELECT i.indexrelid FROM pg_catalog.pg_index i
 JOIN pg_catalog.pg_class c ON c.oid=i.indrelid
 JOIN pg_catalog.pg_namespace n ON n.oid=c.relnamespace
 WHERE n.nspname=:'expected_schema'
   AND (NOT i.indislive OR NOT i.indisready OR NOT i.indisvalid)
 UNION ALL
 SELECT 0 FROM pg_catalog.pg_namespace n
 JOIN pg_catalog.pg_class mv ON mv.relnamespace=n.oid
 LEFT JOIN pg_catalog.pg_index i ON i.indrelid=mv.oid AND i.indisunique
 LEFT JOIN pg_catalog.pg_class idx ON idx.oid=i.indexrelid
   AND idx.relname='daily_appointment_summary_mv_date_uidx'
 WHERE n.nspname=:'expected_schema'
   AND mv.relname='daily_appointment_summary_mv'
   AND (idx.oid IS NULL OR NOT i.indislive OR NOT i.indisready OR NOT i.indisvalid)
),
routine_failures AS (
 SELECT required.name FROM (VALUES
   ('appointment_duration_minutes','timestamp with time zone, timestamp with time zone','f'::"char"),
   ('cancel_appointment','bigint, text','p'::"char")
 ) required(name,args,kind)
 LEFT JOIN pg_catalog.pg_namespace n ON n.nspname=:'expected_schema'
 LEFT JOIN pg_catalog.pg_proc p ON p.pronamespace=n.oid AND p.proname=required.name
   AND pg_catalog.pg_get_function_identity_arguments(p.oid)=required.args
   AND p.prokind=required.kind AND NOT p.prosecdef
   AND pg_catalog.pg_get_userbyid(p.proowner)=:'expected_owner'
 WHERE p.oid IS NULL
),
routine_attribute_failures AS (
 SELECT p.oid
 FROM pg_catalog.pg_proc AS p
 JOIN pg_catalog.pg_namespace AS n ON n.oid = p.pronamespace
 JOIN pg_catalog.pg_language AS l ON l.oid = p.prolang
 WHERE n.nspname = :'expected_schema'
   AND (
     (p.proname = 'appointment_duration_minutes'
      AND pg_catalog.pg_get_function_identity_arguments(p.oid) =
          'timestamp with time zone, timestamp with time zone'
      AND (p.prokind <> 'f' OR l.lanname <> 'sql' OR p.provolatile <> 'i'
           OR NOT p.proisstrict OR p.proparallel <> 's' OR p.prosecdef
           OR p.proconfig IS DISTINCT FROM ARRAY['search_path=pg_catalog']::text[]))
     OR
     (p.proname = 'cancel_appointment'
      AND pg_catalog.pg_get_function_identity_arguments(p.oid) = 'bigint, text'
      AND (p.prokind <> 'p' OR l.lanname <> 'plpgsql' OR p.prosecdef
           OR p.proconfig IS DISTINCT FROM ARRAY['search_path=pg_catalog']::text[]))
   )
),
foreign_key_failures AS (
 SELECT con.oid
 FROM pg_catalog.pg_constraint AS con
 JOIN pg_catalog.pg_class AS src ON src.oid = con.conrelid
 JOIN pg_catalog.pg_namespace AS src_ns ON src_ns.oid = src.relnamespace
 JOIN pg_catalog.pg_class AS dst ON dst.oid = con.confrelid
 JOIN pg_catalog.pg_namespace AS dst_ns ON dst_ns.oid = dst.relnamespace
 JOIN pg_catalog.pg_attribute AS src_col
   ON src_col.attrelid = src.oid AND src_col.attnum = ANY (con.conkey)
 JOIN pg_catalog.pg_attribute AS dst_col
   ON dst_col.attrelid = dst.oid AND dst_col.attnum = ANY (con.confkey)
 WHERE src_ns.nspname = :'expected_schema'
   AND con.conname IN ('appointments_patient_id_fkey',
                       'appointment_events_appointment_id_fkey')
   AND NOT (
     (con.conname = 'appointments_patient_id_fkey'
      AND src.relname = 'appointments' AND src_col.attname = 'patient_id'
      AND dst_ns.nspname = :'expected_schema' AND dst.relname = 'patients'
      AND dst_col.attname = 'patient_id' AND con.confdeltype = 'r')
     OR
     (con.conname = 'appointment_events_appointment_id_fkey'
      AND src.relname = 'appointment_events' AND src_col.attname = 'appointment_id'
      AND dst_ns.nspname = :'expected_schema' AND dst.relname = 'appointments'
      AND dst_col.attname = 'appointment_id' AND con.confdeltype = 'c')
   )
),
owner_failures AS (
 SELECT c.oid FROM pg_catalog.pg_class c
 JOIN pg_catalog.pg_namespace n ON n.oid=c.relnamespace
 WHERE n.nspname=:'expected_schema' AND c.relkind IN ('r','v','m','S')
   AND pg_catalog.pg_get_userbyid(c.relowner)<>:'expected_owner'
 UNION ALL
 SELECT p.oid FROM pg_catalog.pg_proc p
 JOIN pg_catalog.pg_namespace n ON n.oid=p.pronamespace
 WHERE n.nspname=:'expected_schema'
   AND pg_catalog.pg_get_userbyid(p.proowner)<>:'expected_owner'
),
gates AS (
 SELECT 'database owner matches' AS gate,
   EXISTS (SELECT 1 FROM pg_catalog.pg_database d
           WHERE d.datname = current_database()
             AND pg_catalog.pg_get_userbyid(d.datdba)=:'expected_owner') AS passed
 UNION ALL SELECT 'schema exists and owner matches',
   EXISTS (SELECT 1 FROM pg_catalog.pg_namespace n
           WHERE n.nspname=:'expected_schema'
             AND pg_catalog.pg_get_userbyid(n.nspowner)=:'expected_owner') AS passed
 UNION ALL SELECT 'required relations', NOT EXISTS (SELECT 1 FROM relation_failures)
 UNION ALL SELECT 'required columns', NOT EXISTS (SELECT 1 FROM column_failures)
 UNION ALL SELECT 'required constraints', NOT EXISTS (SELECT 1 FROM constraint_failures)
 UNION ALL SELECT 'foreign-key targets and actions',
   (SELECT count(*) FROM pg_catalog.pg_constraint con
    JOIN pg_catalog.pg_class c ON c.oid=con.conrelid
    JOIN pg_catalog.pg_namespace n ON n.oid=c.relnamespace
    WHERE n.nspname=:'expected_schema'
      AND con.conname IN ('appointments_patient_id_fkey',
                          'appointment_events_appointment_id_fkey')) = 2
   AND NOT EXISTS (SELECT 1 FROM foreign_key_failures)
 UNION ALL SELECT 'index health', NOT EXISTS (SELECT 1 FROM index_failures)
 UNION ALL SELECT 'materialized view populated',
   EXISTS (SELECT 1 FROM pg_catalog.pg_class c JOIN pg_catalog.pg_namespace n
           ON n.oid=c.relnamespace WHERE n.nspname=:'expected_schema'
           AND c.relname='daily_appointment_summary_mv' AND c.relkind='m'
           AND c.relispopulated)
 UNION ALL SELECT 'required routines', NOT EXISTS (SELECT 1 FROM routine_failures)
   AND NOT EXISTS (SELECT 1 FROM routine_attribute_failures)
 UNION ALL SELECT 'governed object ownership', NOT EXISTS (SELECT 1 FROM owner_failures)
 UNION ALL SELECT 'fictional sample minimums',
   (SELECT count(*) >= 2 FROM clinic.patients)
   AND (SELECT count(*) >= 2 FROM clinic.appointments)
   AND (SELECT count(*) >= 2 FROM clinic.appointment_events)
)
SELECT pg_catalog.jsonb_object_agg(gate, passed ORDER BY gate) AS hard_gate_results,
       pg_catalog.bool_and(passed) AS acceptance_passed
FROM gates
\gset

\echo :hard_gate_results

ROLLBACK;

\if :acceptance_passed
  \echo ''
  \echo 'PASS: Part 3.15 application database contract accepted.'
  \echo 'No database objects or rows were intentionally modified.'
\else
  \echo ''
  \echo 'FAIL: one or more Part 3.15 acceptance gates failed.'
  \quit 4
\endif
