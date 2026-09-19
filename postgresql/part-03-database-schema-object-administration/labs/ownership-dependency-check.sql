/*
===============================================================================
Part 3.12 — Object Ownership, Dependencies, and Safe DROP Operations
Canonical Acceptance Artifact

[TUTORIAL-ACCEPTANCE — SAFE-READ]

Target: PostgreSQL 18

Purpose:
  Inventory common object owners and selected dependency relationships without
  changing database state.

Safety:
  - No CREATE / ALTER / DROP
  - No REASSIGN OWNED / DROP OWNED
  - No GRANT / REVOKE
  - No INSERT / UPDATE / DELETE / MERGE / TRUNCATE
  - No execution of arbitrary user-defined routines
  - No configuration changes

Limitations:
  Catalog visibility depends on the connected role. These focused queries do
  not discover every dynamic-SQL, application, ETL, BI, or external consumer.
  Empty output does not prove that an object is safe to change or drop.
  Shared dependency output is limited to the current database object and does
  not constitute a cluster-complete role-retirement inventory.

Expected impact:
  Catalog reads and PostgreSQL-supplied descriptive functions only. Large
  catalogs can still consume CPU, memory, and I/O while producing output.
  Test output volume before production use, avoid repeated full polling, and
  stop if the checks cause measurable resource pressure.

Evidence handling:
  Output can reveal internal role, schema, object, extension, and dependency
  names. Store transcripts in an access-controlled location and review them
  before sharing. Do not capture credentials or connection strings.
===============================================================================
*/

\set ON_ERROR_STOP on
\pset pager off

\echo ''
\echo '============================================================'
\echo 'Part 3.12 — Ownership and Dependency Acceptance Check'
\echo '[TUTORIAL-ACCEPTANCE — SAFE-READ]'
\echo '============================================================'

-- ---------------------------------------------------------------------------
-- 1. PostgreSQL version and execution context
-- ---------------------------------------------------------------------------

\echo ''
\echo '--- [1/12] PostgreSQL version and session context ---'

SELECT
    current_setting('server_version') AS server_version,
    current_setting('server_version_num') AS server_version_num,
    current_setting('server_version_num')::integer >= 180000
    AND current_setting('server_version_num')::integer < 190000
        AS target_is_postgresql_18,
    current_database() AS database_name,
    current_user AS current_user,
    session_user AS session_user,
    pg_is_in_recovery() AS in_recovery;

-- ---------------------------------------------------------------------------
-- 2. Database and user-defined schema owners
-- ---------------------------------------------------------------------------

\echo ''
\echo '--- [2/12] Database and schema owners ---'

SELECT
    'DATABASE' AS object_type,
    NULL::name AS schema_name,
    d.datname AS object_name,
    pg_catalog.pg_get_userbyid(d.datdba) AS owner
FROM pg_catalog.pg_database AS d
WHERE d.datname = current_database()

UNION ALL

SELECT
    'SCHEMA' AS object_type,
    n.nspname AS schema_name,
    n.nspname AS object_name,
    pg_catalog.pg_get_userbyid(n.nspowner) AS owner
FROM pg_catalog.pg_namespace AS n
WHERE n.nspname <> 'pg_catalog'
  AND n.nspname <> 'information_schema'
  AND n.nspname !~ '^pg_toast'
  AND n.nspname !~ '^pg_temp_'
ORDER BY object_type, schema_name, object_name;

-- ---------------------------------------------------------------------------
-- 3. Relation owners
-- ---------------------------------------------------------------------------

\echo ''
\echo '--- [3/12] Relation owners ---'

SELECT
    n.nspname AS schema_name,
    c.relname AS object_name,
    CASE c.relkind
        WHEN 'r' THEN 'TABLE'
        WHEN 'p' THEN 'PARTITIONED TABLE'
        WHEN 'v' THEN 'VIEW'
        WHEN 'm' THEN 'MATERIALIZED VIEW'
        WHEN 'S' THEN 'SEQUENCE'
        WHEN 'f' THEN 'FOREIGN TABLE'
        WHEN 'i' THEN 'INDEX'
        WHEN 'I' THEN 'PARTITIONED INDEX'
        ELSE c.relkind::text
    END AS object_type,
    pg_catalog.pg_get_userbyid(c.relowner) AS owner,
    CASE c.relpersistence
        WHEN 'p' THEN 'PERMANENT'
        WHEN 'u' THEN 'UNLOGGED'
        WHEN 't' THEN 'TEMPORARY'
        ELSE c.relpersistence::text
    END AS persistence
FROM pg_catalog.pg_class AS c
JOIN pg_catalog.pg_namespace AS n ON n.oid = c.relnamespace
WHERE c.relkind IN ('r', 'p', 'v', 'm', 'S', 'f', 'i', 'I')
  AND n.nspname <> 'pg_catalog'
  AND n.nspname <> 'information_schema'
  AND n.nspname !~ '^pg_toast'
  AND n.nspname !~ '^pg_temp_'
ORDER BY n.nspname, c.relname, c.relkind;

-- ---------------------------------------------------------------------------
-- 4. Routine owners
-- ---------------------------------------------------------------------------

\echo ''
\echo '--- [4/12] Routine owners ---'

SELECT
    n.nspname AS schema_name,
    p.proname AS routine_name,
    pg_catalog.pg_get_function_identity_arguments(p.oid)
        AS identity_arguments,
    CASE p.prokind
        WHEN 'f' THEN 'FUNCTION'
        WHEN 'p' THEN 'PROCEDURE'
        WHEN 'a' THEN 'AGGREGATE'
        WHEN 'w' THEN 'WINDOW FUNCTION'
        ELSE p.prokind::text
    END AS routine_type,
    pg_catalog.pg_get_userbyid(p.proowner) AS owner
FROM pg_catalog.pg_proc AS p
JOIN pg_catalog.pg_namespace AS n ON n.oid = p.pronamespace
WHERE n.nspname <> 'pg_catalog'
  AND n.nspname <> 'information_schema'
  AND n.nspname !~ '^pg_toast'
  AND n.nspname !~ '^pg_temp_'
ORDER BY n.nspname, p.proname, identity_arguments;

-- ---------------------------------------------------------------------------
-- 5. User-defined type and domain owners
-- ---------------------------------------------------------------------------

\echo ''
\echo '--- [5/12] Type and domain owners ---'

SELECT
    n.nspname AS schema_name,
    t.typname AS type_name,
    CASE t.typtype
        WHEN 'b' THEN 'BASE'
        WHEN 'c' THEN 'COMPOSITE'
        WHEN 'd' THEN 'DOMAIN'
        WHEN 'e' THEN 'ENUM'
        WHEN 'm' THEN 'MULTIRANGE'
        WHEN 'p' THEN 'PSEUDO'
        WHEN 'r' THEN 'RANGE'
        ELSE t.typtype::text
    END AS type_kind,
    pg_catalog.pg_get_userbyid(t.typowner) AS owner
FROM pg_catalog.pg_type AS t
JOIN pg_catalog.pg_namespace AS n ON n.oid = t.typnamespace
WHERE n.nspname <> 'pg_catalog'
  AND n.nspname <> 'information_schema'
  AND n.nspname !~ '^pg_toast'
  AND n.nspname !~ '^pg_temp_'
  AND t.typisdefined
  AND t.typcategory <> 'A'
  AND NOT EXISTS (
      SELECT 1
      FROM pg_catalog.pg_class AS c
      WHERE c.reltype = t.oid
  )
ORDER BY n.nspname, t.typname;

-- Relation row types and implicit array rows are excluded from this concise
-- report. Their exclusion is not evidence that those catalog rows do not exist.

-- ---------------------------------------------------------------------------
-- 6. Extension owners
-- ---------------------------------------------------------------------------

\echo ''
\echo '--- [6/12] Extension owners ---'

SELECT
    e.extname AS extension_name,
    e.extversion AS extension_version,
    pg_catalog.pg_get_userbyid(e.extowner) AS owner,
    n.nspname AS extension_schema,
    e.extrelocatable AS relocatable
FROM pg_catalog.pg_extension AS e
JOIN pg_catalog.pg_namespace AS n ON n.oid = e.extnamespace
ORDER BY e.extname;

-- ---------------------------------------------------------------------------
-- 7. Current-database-local and current-database shared role dependencies
-- ---------------------------------------------------------------------------

\echo ''
\echo '--- [7/12] Scoped pg_shdepend role dependencies ---'

\echo 'Database-local dependent objects in the current database'

SELECT
    r.rolname AS referenced_role,
    CASE sd.deptype
        WHEN 'o' THEN 'OWNER'
        WHEN 'a' THEN 'ACL'
        WHEN 'i' THEN 'INITIAL ACL'
        WHEN 'r' THEN 'POLICY'
        WHEN 't' THEN 'TABLESPACE'
        ELSE sd.deptype::text
    END AS dependency_type,
    sd.classid::regclass AS dependent_catalog,
    pg_catalog.pg_describe_object(
        sd.classid,
        sd.objid,
        sd.objsubid
    ) AS dependent_object
FROM pg_catalog.pg_shdepend AS sd
LEFT JOIN pg_catalog.pg_roles AS r
  ON sd.refclassid = 'pg_authid'::regclass
 AND r.oid = sd.refobjid
WHERE sd.dbid = (
        SELECT oid
        FROM pg_catalog.pg_database
        WHERE datname = current_database()
      )
  AND sd.deptype IN ('o', 'a', 'i', 'r')
ORDER BY referenced_role, dependency_type, dependent_object;

\echo ''
\echo 'Shared dependency rows for the current database object only'

SELECT
    r.rolname AS referenced_role,
    CASE sd.deptype
        WHEN 'o' THEN 'OWNER'
        WHEN 'a' THEN 'ACL'
        WHEN 'i' THEN 'INITIAL ACL'
        WHEN 'r' THEN 'POLICY'
        ELSE sd.deptype::text
    END AS dependency_type,
    sd.classid::regclass AS dependent_catalog,
    pg_catalog.pg_describe_object(
        sd.classid,
        sd.objid,
        sd.objsubid
    ) AS dependent_object
FROM pg_catalog.pg_shdepend AS sd
LEFT JOIN pg_catalog.pg_roles AS r
  ON sd.refclassid = 'pg_authid'::regclass
 AND r.oid = sd.refobjid
WHERE sd.dbid = 0
  AND sd.classid = 'pg_database'::regclass
  AND sd.objid = (
        SELECT oid
        FROM pg_catalog.pg_database
        WHERE datname = current_database()
      )
  AND sd.deptype IN ('o', 'a', 'i', 'r')
ORDER BY referenced_role, dependency_type, dependent_object;

-- This default report intentionally excludes other databases, tablespaces,
-- and unrelated cluster-wide shared objects. Complete role retirement needs
-- separately authorized inventory across all relevant databases and objects.

-- ---------------------------------------------------------------------------
-- 8. Foreign-key dependencies
-- ---------------------------------------------------------------------------

\echo ''
\echo '--- [8/12] Foreign-key dependencies ---'

SELECT
    con.conname AS constraint_name,
    con.conrelid::regclass AS referencing_table,
    con.confrelid::regclass AS referenced_table,
    con.convalidated AS validated,
    pg_catalog.pg_get_constraintdef(con.oid, true) AS definition
FROM pg_catalog.pg_constraint AS con
WHERE con.contype = 'f'
ORDER BY con.conrelid::regclass::text, con.conname;

-- ---------------------------------------------------------------------------
-- 9. View and materialized-view relation dependencies
-- ---------------------------------------------------------------------------

\echo ''
\echo '--- [9/12] View-to-relation dependencies ---'

SELECT DISTINCT
    view_ns.nspname AS view_schema,
    view_rel.relname AS view_name,
    CASE view_rel.relkind
        WHEN 'v' THEN 'VIEW'
        WHEN 'm' THEN 'MATERIALIZED VIEW'
    END AS view_type,
    source_ns.nspname AS source_schema,
    source_rel.relname AS source_object,
    CASE source_rel.relkind
        WHEN 'r' THEN 'TABLE'
        WHEN 'p' THEN 'PARTITIONED TABLE'
        WHEN 'v' THEN 'VIEW'
        WHEN 'm' THEN 'MATERIALIZED VIEW'
        WHEN 'f' THEN 'FOREIGN TABLE'
        ELSE source_rel.relkind::text
    END AS source_type
FROM pg_catalog.pg_rewrite AS rw
JOIN pg_catalog.pg_class AS view_rel ON view_rel.oid = rw.ev_class
JOIN pg_catalog.pg_namespace AS view_ns ON view_ns.oid = view_rel.relnamespace
JOIN pg_catalog.pg_depend AS dep
  ON dep.classid = 'pg_rewrite'::regclass
 AND dep.objid = rw.oid
JOIN pg_catalog.pg_class AS source_rel
  ON dep.refclassid = 'pg_class'::regclass
 AND dep.refobjid = source_rel.oid
JOIN pg_catalog.pg_namespace AS source_ns
  ON source_ns.oid = source_rel.relnamespace
WHERE view_rel.relkind IN ('v', 'm')
  AND view_ns.nspname <> 'pg_catalog'
  AND view_ns.nspname <> 'information_schema'
  AND view_ns.nspname !~ '^pg_toast'
  AND view_ns.nspname !~ '^pg_temp_'
  AND source_ns.nspname <> 'pg_catalog'
  AND source_ns.nspname <> 'information_schema'
  AND source_ns.nspname !~ '^pg_toast'
  AND source_ns.nspname !~ '^pg_temp_'
  AND view_rel.oid <> source_rel.oid
ORDER BY view_schema, view_name, source_schema, source_object;

-- This focused query reports relation-to-relation edges only. It is not a
-- complete inventory of every function, operator, type, or external consumer.

-- ---------------------------------------------------------------------------
-- 10. Sequence-to-column ownership dependencies
-- ---------------------------------------------------------------------------

\echo ''
\echo '--- [10/12] Sequence-to-column ownership dependencies ---'

SELECT
    seq_ns.nspname AS sequence_schema,
    seq.relname AS sequence_name,
    tbl_ns.nspname AS table_schema,
    tbl.relname AS table_name,
    att.attname AS column_name,
    dep.deptype AS dependency_code
FROM pg_catalog.pg_class AS seq
JOIN pg_catalog.pg_namespace AS seq_ns ON seq_ns.oid = seq.relnamespace
JOIN pg_catalog.pg_depend AS dep
  ON dep.classid = 'pg_class'::regclass
 AND dep.objid = seq.oid
 AND dep.refclassid = 'pg_class'::regclass
 AND dep.refobjsubid > 0
 AND dep.deptype IN ('a', 'i')
JOIN pg_catalog.pg_class AS tbl ON tbl.oid = dep.refobjid
JOIN pg_catalog.pg_namespace AS tbl_ns ON tbl_ns.oid = tbl.relnamespace
JOIN pg_catalog.pg_attribute AS att
  ON att.attrelid = tbl.oid
 AND att.attnum = dep.refobjsubid
WHERE seq.relkind = 'S'
  AND seq_ns.nspname <> 'pg_catalog'
  AND seq_ns.nspname <> 'information_schema'
  AND seq_ns.nspname !~ '^pg_toast'
  AND seq_ns.nspname !~ '^pg_temp_'
ORDER BY sequence_schema, sequence_name;

-- ---------------------------------------------------------------------------
-- 11. Extension members
-- ---------------------------------------------------------------------------

\echo ''
\echo '--- [11/12] Extension member inventory ---'

\echo 'Extension member counts'

SELECT
    e.extname AS extension_name,
    COUNT(dep.objid) AS member_count
FROM pg_catalog.pg_extension AS e
LEFT JOIN pg_catalog.pg_depend AS dep
  ON dep.refclassid = 'pg_extension'::regclass
 AND dep.refobjid = e.oid
 AND dep.deptype = 'e'
GROUP BY e.oid, e.extname
ORDER BY e.extname;

\if :{?extension_filter}

SELECT :'extension_filter' ~ '^[a-z][a-z0-9_]*$'
    AS extension_filter_valid
\gset

\if :extension_filter_valid
    \echo 'Detailed members for the exact requested extension'
\else
    \echo 'ERROR: extension_filter violates the restrictive lab name policy.'
    \quit 3
\endif

SELECT
    e.extname AS extension_name,
    dep.classid::regclass AS member_catalog,
    pg_catalog.pg_describe_object(
        dep.classid,
        dep.objid,
        dep.objsubid
    ) AS member_object
FROM pg_catalog.pg_extension AS e
JOIN pg_catalog.pg_depend AS dep
  ON dep.refclassid = 'pg_extension'::regclass
 AND dep.refobjid = e.oid
 AND dep.deptype = 'e'
WHERE e.extname = :'extension_filter'
ORDER BY e.extname, dep.classid::regclass::text, member_object;

\else
    \echo 'Detailed extension members skipped.'
    \echo 'Optional: -v extension_filter=<exact_lowercase_extension_name>'
\endif

-- The filter is a quoted equality value under a restrictive tutorial policy.
-- It does not enable dynamic SQL or mutation.

-- ---------------------------------------------------------------------------
-- 12. Dependency-type summary
-- ---------------------------------------------------------------------------

\echo ''
\echo '--- [12/12] Database dependency-type summary ---'

SELECT
    dep.deptype AS dependency_code,
    CASE dep.deptype
        WHEN 'n' THEN 'NORMAL'
        WHEN 'a' THEN 'AUTO'
        WHEN 'i' THEN 'INTERNAL'
        WHEN 'P' THEN 'PARTITION PRIMARY'
        WHEN 'S' THEN 'PARTITION SECONDARY'
        WHEN 'e' THEN 'EXTENSION MEMBER'
        WHEN 'x' THEN 'AUTO EXTENSION'
        ELSE 'OTHER / REVIEW'
    END AS dependency_type,
    COUNT(*) AS dependency_count
FROM pg_catalog.pg_depend AS dep
GROUP BY dep.deptype
ORDER BY dep.deptype;

\echo ''
\echo '============================================================'
\echo 'SAFE-READ ownership and dependency checks completed.'
\echo ''
\echo 'No ownership, privilege, object, or data changes were made.'
\echo 'Empty output does not prove that an object is safe to drop.'
\echo 'This output does not authorize an ownership or DROP operation.'
\echo '============================================================'
