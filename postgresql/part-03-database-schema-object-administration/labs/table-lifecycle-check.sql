-- ============================================================================
-- Part 3.3 — Table Design and Lifecycle Administration
-- File: labs/table-lifecycle-check.sql
-- Classification: [TUTORIAL-ACCEPTANCE — SAFE-READ]
-- Target: PostgreSQL 18
--
-- SAFETY CONTRACT
--   This script intentionally performs observational queries only.
--
-- IMPORTANT
--   * SAFE-READ does not mean zero operational cost.
--   * Metadata and statistics visibility can differ by role.
--   * Broad size and inventory queries may need an approved schema filter.
--
-- This script must not create, alter, rename, move, truncate, or drop objects;
-- modify data; change privileges; terminate sessions; reset statistics;
-- invoke maintenance; or modify configuration.
-- ============================================================================

\set ON_ERROR_STOP on
\pset pager off

\echo '======================================================================'
\echo 'Part 3.3 — Table Design and Lifecycle Administration'
\echo '[TUTORIAL-ACCEPTANCE — SAFE-READ]'
\echo '======================================================================'

\echo ''
\echo 'CHECK 1 — Session and server identity'
SELECT
    current_database()  AS database_name,
    current_user        AS current_user,
    session_user        AS session_user,
    inet_server_addr()  AS server_address,
    inet_server_port()  AS server_port,
    pg_is_in_recovery() AS in_recovery;

\echo ''
\echo 'CHECK 2 — PostgreSQL version'
SELECT version();

\echo ''
\echo 'CHECK 3 — Current-role-visible table inventory'
SELECT
    t.table_schema,
    t.table_name,
    t.table_type,
    t.is_insertable_into
FROM information_schema.tables AS t
ORDER BY t.table_schema, t.table_name;

\echo ''
\echo 'CHECK 4 — Relation identity, owner, kind, and persistence'
SELECT
    n.nspname AS schema_name,
    c.relname AS relation_name,
    c.relkind,
    c.relpersistence,
    pg_get_userbyid(c.relowner) AS owner
FROM pg_class AS c
JOIN pg_namespace AS n
  ON n.oid = c.relnamespace
WHERE c.relkind IN ('r', 'p', 'f')
ORDER BY n.nspname, c.relname;

\echo ''
\echo 'CHECK 5 — Column contract visible to the current role'
SELECT
    c.table_schema,
    c.table_name,
    c.ordinal_position,
    c.column_name,
    c.data_type,
    c.udt_schema,
    c.udt_name,
    c.is_nullable
FROM information_schema.columns AS c
ORDER BY c.table_schema, c.table_name, c.ordinal_position;

\echo ''
\echo 'CHECK 6 — Access method and tablespace metadata'
SELECT
    n.nspname AS schema_name,
    c.relname AS relation_name,
    c.relkind,
    am.amname AS access_method,
    COALESCE(ts.spcname, 'database default') AS tablespace
FROM pg_class AS c
JOIN pg_namespace AS n
  ON n.oid = c.relnamespace
LEFT JOIN pg_am AS am
  ON am.oid = c.relam
LEFT JOIN pg_tablespace AS ts
  ON ts.oid = c.reltablespace
WHERE c.relkind IN ('r', 'p', 'f')
ORDER BY n.nspname, c.relname;

\echo ''
\echo 'CHECK 7 — Relation size inventory'
\echo 'NOTE: Broad size inspection can be costly on large environments.'
\echo 'NOTE: Partitioned-parent values do not recursively include partitions.'
SELECT
    n.nspname AS schema_name,
    c.relname AS relation_name,
    c.relkind,
    CASE
        WHEN c.relkind = 'p' THEN 'partitioned parent; size is non-recursive'
        ELSE 'stored relation'
    END AS size_scope,
    pg_relation_size(c.oid) AS relation_bytes,
    pg_table_size(c.oid) AS table_bytes,
    pg_total_relation_size(c.oid) AS total_bytes
FROM pg_class AS c
JOIN pg_namespace AS n
  ON n.oid = c.relnamespace
WHERE c.relkind IN ('r', 'p')
ORDER BY pg_total_relation_size(c.oid) DESC,
         n.nspname,
         c.relname;

\echo ''
\echo 'CHECK 8 — Planner row estimates'
SELECT
    n.nspname AS schema_name,
    c.relname AS relation_name,
    CASE
        WHEN c.reltuples < 0 THEN NULL
        ELSE c.reltuples::bigint
    END AS estimated_rows,
    c.reltuples < 0 AS row_estimate_unknown,
    c.relpages AS estimated_pages
FROM pg_class AS c
JOIN pg_namespace AS n
  ON n.oid = c.relnamespace
WHERE c.relkind = 'r'
ORDER BY n.nspname, c.relname;

\echo ''
\echo 'CHECK 9 — User-table statistics'
SELECT
    s.schemaname,
    s.relname,
    s.seq_scan,
    s.idx_scan,
    s.n_live_tup,
    s.n_dead_tup,
    s.n_mod_since_analyze,
    s.last_vacuum,
    s.last_autovacuum,
    s.last_analyze,
    s.last_autoanalyze
FROM pg_stat_user_tables AS s
ORDER BY s.schemaname, s.relname;

\echo ''
\echo 'CHECK 10 — Table privilege evidence for current role'
SELECT
    t.table_schema,
    t.table_name,
    has_table_privilege(
        current_user,
        format('%I.%I', t.table_schema, t.table_name),
        'SELECT'
    ) AS has_select,
    has_table_privilege(
        current_user,
        format('%I.%I', t.table_schema, t.table_name),
        'INSERT'
    ) AS has_insert,
    has_table_privilege(
        current_user,
        format('%I.%I', t.table_schema, t.table_name),
        'UPDATE'
    ) AS has_update,
    has_table_privilege(
        current_user,
        format('%I.%I', t.table_schema, t.table_name),
        'DELETE'
    ) AS has_delete
FROM information_schema.tables AS t
WHERE t.table_type = 'BASE TABLE'
ORDER BY t.table_schema, t.table_name;

\echo ''
\echo 'CHECK 11 — Acceptance safety confirmation'
SELECT
    current_database() IS NOT NULL AS database_detected,
    current_user IS NOT NULL AS user_detected,
    EXISTS (
        SELECT 1
        FROM pg_catalog.pg_class
    ) AS relation_catalog_detected;

\echo ''
\echo '======================================================================'
\echo 'SAFE-READ LAB COMPLETE'
\echo 'No tables, data, privileges, statistics, or configuration were changed.'
\echo '======================================================================'
