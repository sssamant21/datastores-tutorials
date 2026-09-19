/*
===============================================================================
Part 3.13 — Object Metadata and Catalog-Based Administration
Canonical Acceptance Artifact

[TUTORIAL-ACCEPTANCE — SAFE-READ]

Target: PostgreSQL 18

Purpose:
  Inventory user-visible database objects from supported PostgreSQL catalogs
  without modifying database state or executing arbitrary user routines.

Safety:
  Catalog and information-schema reads only. No CREATE, ALTER, DROP, DML,
  GRANT, REVOKE, CALL, configuration change, or user-defined function call.

Boundary:
  Excludes pg_catalog, information_schema, pg_toast*, and pg_temp_* schemas.
  Results reflect the connected database and current role. The checks run in
  one REPEATABLE READ, READ ONLY transaction for a consistent database snapshot.

Operational note:
  Large catalogs can produce substantial output and consume CPU, memory, and
  client/network bandwidth. Run during an approved window when appropriate.
  Catalog reads can also interact with concurrent DDL through normal locking.
===============================================================================
*/

\set ON_ERROR_STOP on
\pset pager off

\echo ''
\echo '============================================================'

BEGIN TRANSACTION ISOLATION LEVEL REPEATABLE READ READ ONLY;

-- Fail closed because this artifact is validated for PostgreSQL 18 catalogs.
SELECT
    (current_setting('server_version_num')::integer / 10000 = 18)
        AS target_is_postgresql_18
\gset

\if :target_is_postgresql_18
\else
\echo 'ERROR: This acceptance check requires PostgreSQL major version 18.'
\quit 3
\endif
\echo 'Part 3.13 — Object Metadata Acceptance Check'
\echo '[TUTORIAL-ACCEPTANCE — SAFE-READ]'
\echo '============================================================'

-- 1. Evidence context
\echo ''
\echo '--- [1/11] Evidence context ---'

SELECT
    current_database() AS database_name,
    current_user AS current_user,
    session_user AS session_user,
    current_setting('server_version') AS server_version,
    current_setting('server_version_num') AS server_version_num,
    (current_setting('server_version_num')::integer / 10000 = 18)
        AS target_is_postgresql_18,
    statement_timestamp() AS collected_at;

-- 2. Non-system schemas
\echo ''
\echo '--- [2/11] Non-system schemas ---'

SELECT
    n.nspname AS schema_name,
    pg_catalog.pg_get_userbyid(n.nspowner) AS owner
FROM pg_catalog.pg_namespace AS n
WHERE n.nspname NOT IN ('pg_catalog', 'information_schema')
  AND n.nspname !~ '^pg_toast'
  AND n.nspname !~ '^pg_temp_'
ORDER BY n.nspname;

-- 3. Relations. Exclude indexes here; they have a dedicated check.
\echo ''
\echo '--- [3/11] Relation inventory ---'

SELECT
    n.nspname AS schema_name,
    c.relname AS relation_name,
    CASE c.relkind
        WHEN 'r' THEN 'TABLE'
        WHEN 'S' THEN 'SEQUENCE'
        WHEN 'v' THEN 'VIEW'
        WHEN 'm' THEN 'MATERIALIZED VIEW'
        WHEN 'c' THEN 'COMPOSITE TYPE'
        WHEN 'f' THEN 'FOREIGN TABLE'
        WHEN 'p' THEN 'PARTITIONED TABLE'
        ELSE c.relkind::text
    END AS relation_kind,
    CASE c.relpersistence
        WHEN 'p' THEN 'PERMANENT'
        WHEN 'u' THEN 'UNLOGGED'
        WHEN 't' THEN 'TEMPORARY'
        ELSE c.relpersistence::text
    END AS persistence,
    pg_catalog.pg_get_userbyid(c.relowner) AS owner,
    c.relispartition AS is_partition,
    c.relispopulated AS is_populated,
    c.relrowsecurity AS row_security_enabled,
    c.relforcerowsecurity AS force_row_security
FROM pg_catalog.pg_class AS c
JOIN pg_catalog.pg_namespace AS n ON n.oid = c.relnamespace
WHERE c.relkind IN ('r', 'S', 'v', 'm', 'c', 'f', 'p')
  AND n.nspname NOT IN ('pg_catalog', 'information_schema')
  AND n.nspname !~ '^pg_toast'
  AND n.nspname !~ '^pg_temp_'
ORDER BY n.nspname, relation_kind, c.relname;

-- 4. User columns. Expression text is intentionally not exported.
\echo ''
\echo '--- [4/11] Column inventory ---'

SELECT
    n.nspname AS schema_name,
    c.relname AS relation_name,
    a.attnum AS ordinal_position,
    a.attname AS column_name,
    pg_catalog.format_type(a.atttypid, a.atttypmod) AS data_type,
    a.attnotnull AS not_null,
    a.atthasdef AS has_default_or_generation_expression,
    CASE a.attidentity
        WHEN 'a' THEN 'ALWAYS'
        WHEN 'd' THEN 'BY DEFAULT'
        ELSE NULL
    END AS identity_generation,
    CASE a.attgenerated
        WHEN 's' THEN 'STORED'
        WHEN 'v' THEN 'VIRTUAL'
        ELSE NULL
    END AS generated_kind
FROM pg_catalog.pg_attribute AS a
JOIN pg_catalog.pg_class AS c ON c.oid = a.attrelid
JOIN pg_catalog.pg_namespace AS n ON n.oid = c.relnamespace
WHERE a.attnum > 0
  AND NOT a.attisdropped
  AND c.relkind IN ('r', 'v', 'm', 'f', 'p')
  AND n.nspname NOT IN ('pg_catalog', 'information_schema')
  AND n.nspname !~ '^pg_toast'
  AND n.nspname !~ '^pg_temp_'
ORDER BY n.nspname, c.relname, a.attnum;

-- 5. Constraints. Definition expressions are intentionally not exported.
\echo ''
\echo '--- [5/11] Relation constraint inventory ---'

SELECT
    n.nspname AS schema_name,
    c.relname AS relation_name,
    con.conname AS constraint_name,
    CASE con.contype
        WHEN 'c' THEN 'CHECK'
        WHEN 'f' THEN 'FOREIGN KEY'
        WHEN 'n' THEN 'NOT NULL'
        WHEN 'p' THEN 'PRIMARY KEY'
        WHEN 'u' THEN 'UNIQUE'
        WHEN 't' THEN 'CONSTRAINT TRIGGER'
        WHEN 'x' THEN 'EXCLUSION'
        ELSE con.contype::text
    END AS constraint_type,
    con.convalidated AS validated,
    con.condeferrable AS deferrable,
    con.condeferred AS initially_deferred,
    (con.conparentid <> 0) AS has_parent_constraint
FROM pg_catalog.pg_constraint AS con
JOIN pg_catalog.pg_class AS c ON c.oid = con.conrelid
JOIN pg_catalog.pg_namespace AS n ON n.oid = con.connamespace
WHERE con.conrelid <> 0
  AND n.nspname NOT IN ('pg_catalog', 'information_schema')
  AND n.nspname !~ '^pg_toast'
  AND n.nspname !~ '^pg_temp_'
ORDER BY n.nspname, c.relname, con.conname;

-- 6. Indexes and lifecycle state
\echo ''
\echo '--- [6/11] Index inventory ---'

SELECT
    n.nspname AS schema_name,
    tbl.relname AS table_name,
    idx.relname AS index_name,
    am.amname AS access_method,
    i.indisunique AS is_unique,
    i.indisprimary AS is_primary,
    i.indisexclusion AS is_exclusion,
    i.indisvalid AS is_valid,
    i.indisready AS is_ready,
    i.indislive AS is_live,
    i.indisreplident AS is_replica_identity,
    (i.indpred IS NOT NULL) AS is_partial
FROM pg_catalog.pg_index AS i
JOIN pg_catalog.pg_class AS tbl ON tbl.oid = i.indrelid
JOIN pg_catalog.pg_class AS idx ON idx.oid = i.indexrelid
JOIN pg_catalog.pg_namespace AS n ON n.oid = tbl.relnamespace
JOIN pg_catalog.pg_am AS am ON am.oid = idx.relam
WHERE n.nspname NOT IN ('pg_catalog', 'information_schema')
  AND n.nspname !~ '^pg_toast'
  AND n.nspname !~ '^pg_temp_'
ORDER BY n.nspname, tbl.relname, idx.relname;

-- 7. Functions, procedures, aggregates, and window functions
\echo ''
\echo '--- [7/11] Routine inventory ---'

SELECT
    n.nspname AS schema_name,
    p.proname AS routine_name,
    pg_catalog.pg_get_function_identity_arguments(p.oid) AS identity_arguments,
    CASE p.prokind
        WHEN 'f' THEN 'FUNCTION'
        WHEN 'p' THEN 'PROCEDURE'
        WHEN 'a' THEN 'AGGREGATE'
        WHEN 'w' THEN 'WINDOW FUNCTION'
        ELSE p.prokind::text
    END AS routine_kind,
    l.lanname AS language,
    pg_catalog.pg_get_userbyid(p.proowner) AS owner,
    CASE WHEN p.prosecdef THEN 'DEFINER' ELSE 'INVOKER' END AS security_mode
FROM pg_catalog.pg_proc AS p
JOIN pg_catalog.pg_namespace AS n ON n.oid = p.pronamespace
JOIN pg_catalog.pg_language AS l ON l.oid = p.prolang
WHERE n.nspname NOT IN ('pg_catalog', 'information_schema')
  AND n.nspname !~ '^pg_toast'
  AND n.nspname !~ '^pg_temp_'
ORDER BY n.nspname, p.proname, identity_arguments;

-- 8. Explicit user-defined types; omit generated array and relation row types.
\echo ''
\echo '--- [8/11] User-defined type inventory ---'

SELECT
    n.nspname AS schema_name,
    t.typname AS type_name,
    CASE t.typtype
        WHEN 'b' THEN 'BASE'
        WHEN 'c' THEN 'COMPOSITE'
        WHEN 'd' THEN 'DOMAIN'
        WHEN 'e' THEN 'ENUM'
        WHEN 'r' THEN 'RANGE'
        WHEN 'm' THEN 'MULTIRANGE'
        WHEN 'p' THEN 'PSEUDO'
        ELSE t.typtype::text
    END AS type_kind,
    pg_catalog.pg_get_userbyid(t.typowner) AS owner
FROM pg_catalog.pg_type AS t
JOIN pg_catalog.pg_namespace AS n ON n.oid = t.typnamespace
LEFT JOIN pg_catalog.pg_class AS type_class ON type_class.oid = t.typrelid
WHERE n.nspname NOT IN ('pg_catalog', 'information_schema')
  AND n.nspname !~ '^pg_toast'
  AND n.nspname !~ '^pg_temp_'
  AND t.typisdefined
  AND t.typelem = 0
  AND (t.typrelid = 0 OR type_class.relkind = 'c')
ORDER BY n.nspname, t.typname;

-- 9. Partition and inheritance edges
\echo ''
\echo '--- [9/11] Partition and inheritance edges ---'

SELECT
    pn.nspname AS parent_schema,
    parent.relname AS parent_name,
    cn.nspname AS child_schema,
    child.relname AS child_name,
    child.relispartition AS child_is_partition,
    inh.inhseqno AS inheritance_sequence,
    inh.inhdetachpending AS detach_pending
FROM pg_catalog.pg_inherits AS inh
JOIN pg_catalog.pg_class AS parent ON parent.oid = inh.inhparent
JOIN pg_catalog.pg_namespace AS pn ON pn.oid = parent.relnamespace
JOIN pg_catalog.pg_class AS child ON child.oid = inh.inhrelid
JOIN pg_catalog.pg_namespace AS cn ON cn.oid = child.relnamespace
WHERE pn.nspname NOT IN ('pg_catalog', 'information_schema')
  AND pn.nspname !~ '^pg_toast'
  AND pn.nspname !~ '^pg_temp_'
  AND cn.nspname NOT IN ('pg_catalog', 'information_schema')
  AND cn.nspname !~ '^pg_toast'
  AND cn.nspname !~ '^pg_temp_'
ORDER BY pn.nspname, parent.relname, inh.inhseqno;

-- 10. Installed extensions
\echo ''
\echo '--- [10/11] Installed extensions ---'

SELECT
    e.extname AS extension_name,
    e.extversion AS installed_version,
    n.nspname AS exported_objects_schema,
    e.extrelocatable AS relocatable,
    pg_catalog.pg_get_userbyid(e.extowner) AS owner
FROM pg_catalog.pg_extension AS e
JOIN pg_catalog.pg_namespace AS n ON n.oid = e.extnamespace
ORDER BY e.extname;

-- 11. Counts and portable-view comparison. Differences may reflect scope and
-- privilege filtering; they are not automatically errors.
\echo ''
\echo '--- [11/11] Summary and information_schema comparison ---'

WITH catalog_relations AS (
    SELECT c.relkind
    FROM pg_catalog.pg_class AS c
    JOIN pg_catalog.pg_namespace AS n ON n.oid = c.relnamespace
    WHERE c.relkind IN ('r', 'v', 'f', 'p')
      AND n.nspname NOT IN ('pg_catalog', 'information_schema')
      AND n.nspname !~ '^pg_toast'
      AND n.nspname !~ '^pg_temp_'
)
SELECT 'pg_catalog comparable tables/views' AS measure, COUNT(*) AS object_count
FROM catalog_relations
UNION ALL
SELECT 'information_schema visible tables/views', COUNT(*)
FROM information_schema.tables
WHERE table_schema NOT IN ('pg_catalog', 'information_schema')
  AND table_schema !~ '^pg_toast'
  AND table_schema !~ '^pg_temp_'
ORDER BY measure;

COMMIT;

\echo ''
\echo '============================================================'
\echo 'SAFE-READ object inventory completed.'
\echo 'No database state was intentionally modified.'
\echo '============================================================'
