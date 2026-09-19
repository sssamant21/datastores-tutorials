/*
===============================================================================
Part 3.14 — Application Database Administration Baseline and Validation
Canonical Acceptance Artifact

[TUTORIAL-ACCEPTANCE — SAFE-READ]

Target: PostgreSQL 18

Required psql variables:
  expected_database  Exact connected database name
  expected_schema    Exact application schema name
  expected_owner     Expected owner for the schema and its application objects

Purpose:
  Compare one application schema with a declared administration baseline.

Safety:
  Catalog and information-schema reads only. No persistent database changes,
  arbitrary user-defined routine calls, definition extraction, or configuration
  changes. Transaction control is READ ONLY.

Identifier policy:
  Tutorial inputs must match ^[a-z][a-z0-9_]*$.

Expected impact:
  Catalog scans, sorting, and transcript output can consume resources in large
  databases. Catalog reads participate in normal locking and can interact with
  concurrent DDL. Test first and run during an approved window when necessary.

Evidence handling:
  Output can reveal database, schema, role, object, extension, privilege,
  routine-configuration, partition, and security-policy metadata. Store the
  transcript in an access-controlled location, redact it before wider sharing,
  retain it only as long as policy requires, and never capture credentials.
===============================================================================
*/

\set ON_ERROR_STOP on
\pset pager off

-- Require all external baseline inputs before querying the target.
\if :{?expected_database}
\else
\echo 'ERROR: required variable expected_database is missing.'
\quit 2
\endif

\if :{?expected_schema}
\else
\echo 'ERROR: required variable expected_schema is missing.'
\quit 2
\endif

\if :{?expected_owner}
\else
\echo 'ERROR: required variable expected_owner is missing.'
\quit 2
\endif

SELECT
    :'expected_database' ~ '^[a-z][a-z0-9_]*$'
        AND :'expected_schema' ~ '^[a-z][a-z0-9_]*$'
        AND :'expected_owner' ~ '^[a-z][a-z0-9_]*$'
        AS baseline_inputs_valid
\gset

\if :baseline_inputs_valid
\else
\echo 'ERROR: one or more baseline inputs violate the identifier policy.'
\quit 2
\endif

\echo ''
\echo '============================================================'
\echo 'Part 3.14 — Application Object Baseline Validation'
\echo '[TUTORIAL-ACCEPTANCE — SAFE-READ]'
\echo '============================================================'

BEGIN TRANSACTION ISOLATION LEVEL REPEATABLE READ READ ONLY;

SELECT
    (current_setting('server_version_num')::integer / 10000 = 18)
        AS target_is_postgresql_18
\gset

\if :target_is_postgresql_18
\else
\echo 'ERROR: this baseline requires PostgreSQL major version 18.'
\quit 3
\endif

-- Do not inventory an unintended database after a connection-selection error.
SELECT current_database() = :'expected_database'
    AS connected_to_expected_database
\gset

\if :connected_to_expected_database
\else
\echo 'ERROR: connected database does not match expected_database.'
\quit 3
\endif

-- 1. Evidence context
\echo ''
\echo '--- [1/14] Evidence context and declared baseline ---'

SELECT
    current_setting('server_version') AS server_version,
    current_setting('server_version_num') AS server_version_num,
    current_database() AS database_name,
    current_user AS current_user,
    session_user AS session_user,
    pg_catalog.pg_is_in_recovery() AS in_recovery,
    current_setting('transaction_isolation') AS transaction_isolation,
    current_setting('transaction_read_only') AS transaction_read_only,
    transaction_timestamp() AS collected_at,
    :'expected_database' AS expected_database,
    :'expected_schema' AS expected_schema,
    :'expected_owner' AS expected_owner;

-- 2. Database baseline
\echo ''
\echo '--- [2/14] Database baseline ---'

SELECT
    d.datname AS database_name,
    (d.datname = :'expected_database') AS database_name_matches,
    pg_catalog.pg_get_userbyid(d.datdba) AS database_owner,
    pg_catalog.pg_encoding_to_char(d.encoding) AS encoding,
    CASE d.datlocprovider
        WHEN 'b' THEN 'BUILTIN'
        WHEN 'c' THEN 'LIBC'
        WHEN 'i' THEN 'ICU'
        ELSE d.datlocprovider::text
    END AS locale_provider,
    d.datcollate AS lc_collate,
    d.datctype AS lc_ctype,
    d.datlocale AS locale_name,
    d.datcollversion AS recorded_collation_version,
    ts.spcname AS default_tablespace,
    d.datallowconn AS allows_connections,
    d.datconnlimit AS connection_limit,
    d.datistemplate AS is_template
FROM pg_catalog.pg_database AS d
JOIN pg_catalog.pg_tablespace AS ts ON ts.oid = d.dattablespace
WHERE d.datname = current_database();

-- 3. Schema baseline
\echo ''
\echo '--- [3/14] Schema identity and ownership ---'

SELECT
    n.nspname AS schema_name,
    pg_catalog.pg_get_userbyid(n.nspowner) AS schema_owner,
    (pg_catalog.pg_get_userbyid(n.nspowner) = :'expected_owner')
        AS owner_matches,
    pg_catalog.has_schema_privilege(current_user, n.oid, 'USAGE')
        AS current_role_has_usage,
    pg_catalog.has_schema_privilege(current_user, n.oid, 'CREATE')
        AS current_role_has_create
FROM pg_catalog.pg_namespace AS n
WHERE n.nspname = :'expected_schema';

-- 4. Object summary
\echo ''
\echo '--- [4/14] Application relation summary ---'

SELECT
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
    END AS object_kind,
    COUNT(*) AS object_count
FROM pg_catalog.pg_class AS c
JOIN pg_catalog.pg_namespace AS n ON n.oid = c.relnamespace
WHERE n.nspname = :'expected_schema'
  AND c.relkind IN ('r', 'p', 'v', 'm', 'S', 'f', 'i', 'I')
GROUP BY c.relkind
ORDER BY object_kind;

-- 5. Ownership drift
\echo ''
\echo '--- [5/14] Object ownership drift ---'

SELECT
    'RELATION' AS object_class,
    c.relname AS object_name,
    c.relkind::text AS object_subtype,
    pg_catalog.pg_get_userbyid(c.relowner) AS actual_owner,
    :'expected_owner' AS expected_owner
FROM pg_catalog.pg_class AS c
JOIN pg_catalog.pg_namespace AS n ON n.oid = c.relnamespace
WHERE n.nspname = :'expected_schema'
  AND c.relkind IN ('r', 'p', 'v', 'm', 'S', 'f', 'i', 'I')
  AND pg_catalog.pg_get_userbyid(c.relowner) <> :'expected_owner'

UNION ALL

SELECT
    'ROUTINE',
    p.proname || '(' ||
        pg_catalog.pg_get_function_identity_arguments(p.oid) || ')',
    p.prokind::text,
    pg_catalog.pg_get_userbyid(p.proowner),
    :'expected_owner'
FROM pg_catalog.pg_proc AS p
JOIN pg_catalog.pg_namespace AS n ON n.oid = p.pronamespace
WHERE n.nspname = :'expected_schema'
  AND pg_catalog.pg_get_userbyid(p.proowner) <> :'expected_owner'

UNION ALL

SELECT
    'TYPE',
    t.typname,
    t.typtype::text,
    pg_catalog.pg_get_userbyid(t.typowner),
    :'expected_owner'
FROM pg_catalog.pg_type AS t
JOIN pg_catalog.pg_namespace AS n ON n.oid = t.typnamespace
LEFT JOIN pg_catalog.pg_class AS type_class ON type_class.oid = t.typrelid
WHERE n.nspname = :'expected_schema'
  AND t.typisdefined
  AND t.typelem = 0
  AND (t.typrelid = 0 OR type_class.relkind = 'c')
  AND pg_catalog.pg_get_userbyid(t.typowner) <> :'expected_owner'
ORDER BY object_class, object_name;

-- 6. Relation review signals
\echo ''
\echo '--- [6/14] Relation persistence, RLS, and replica identity ---'

SELECT
    c.relname AS relation_name,
    CASE c.relkind
        WHEN 'r' THEN 'TABLE'
        WHEN 'p' THEN 'PARTITIONED TABLE'
        WHEN 'm' THEN 'MATERIALIZED VIEW'
        WHEN 'f' THEN 'FOREIGN TABLE'
        ELSE c.relkind::text
    END AS relation_kind,
    CASE c.relpersistence
        WHEN 'p' THEN 'PERMANENT'
        WHEN 'u' THEN 'UNLOGGED'
        WHEN 't' THEN 'TEMPORARY'
        ELSE c.relpersistence::text
    END AS persistence,
    c.relrowsecurity AS row_security_enabled,
    c.relforcerowsecurity AS force_row_security,
    CASE c.relreplident
        WHEN 'd' THEN 'DEFAULT'
        WHEN 'n' THEN 'NOTHING'
        WHEN 'f' THEN 'FULL'
        WHEN 'i' THEN 'INDEX'
        ELSE c.relreplident::text
    END AS replica_identity,
    c.relispartition AS is_partition,
    c.relispopulated AS is_populated
FROM pg_catalog.pg_class AS c
JOIN pg_catalog.pg_namespace AS n ON n.oid = c.relnamespace
WHERE n.nspname = :'expected_schema'
  AND c.relkind IN ('r', 'p', 'm', 'f')
ORDER BY c.relname;

-- 7. Constraint health
\echo ''
\echo '--- [7/14] Non-enforced or unvalidated relation constraints ---'

SELECT
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
    con.conenforced AS enforced,
    con.convalidated AS validated
FROM pg_catalog.pg_constraint AS con
JOIN pg_catalog.pg_class AS c ON c.oid = con.conrelid
JOIN pg_catalog.pg_namespace AS n ON n.oid = c.relnamespace
WHERE n.nspname = :'expected_schema'
  AND (NOT con.conenforced OR NOT con.convalidated)
ORDER BY c.relname, con.conname;

-- 8. Index lifecycle health
\echo ''
\echo '--- [8/14] Unhealthy index lifecycle state ---'

SELECT
    tbl.relname AS table_name,
    idx.relname AS index_name,
    i.indislive AS is_live,
    i.indisready AS is_ready,
    i.indisvalid AS is_valid
FROM pg_catalog.pg_index AS i
JOIN pg_catalog.pg_class AS tbl ON tbl.oid = i.indrelid
JOIN pg_catalog.pg_class AS idx ON idx.oid = i.indexrelid
JOIN pg_catalog.pg_namespace AS n ON n.oid = tbl.relnamespace
WHERE n.nspname = :'expected_schema'
  AND (NOT i.indislive OR NOT i.indisready OR NOT i.indisvalid)
ORDER BY tbl.relname, idx.relname;

-- 9. Primary-key coverage review
\echo ''
\echo '--- [9/14] Tables without a primary key — review signal ---'

SELECT
    c.relname AS table_name,
    CASE c.relkind
        WHEN 'r' THEN 'TABLE'
        WHEN 'p' THEN 'PARTITIONED TABLE'
    END AS table_kind,
    c.relispartition AS is_partition
FROM pg_catalog.pg_class AS c
JOIN pg_catalog.pg_namespace AS n ON n.oid = c.relnamespace
WHERE n.nspname = :'expected_schema'
  AND c.relkind IN ('r', 'p')
  AND NOT EXISTS (
      SELECT 1
      FROM pg_catalog.pg_constraint AS con
      WHERE con.conrelid = c.oid
        AND con.contype = 'p'
  )
ORDER BY c.relname;

-- 10. Hierarchy and materialized-view readiness
\echo ''
\echo '--- [10/14] Transitional hierarchy and materialized-view state ---'

SELECT
    'DETACH PENDING' AS finding,
    parent.relname AS parent_object,
    child.relname AS affected_object
FROM pg_catalog.pg_inherits AS inh
JOIN pg_catalog.pg_class AS parent ON parent.oid = inh.inhparent
JOIN pg_catalog.pg_namespace AS pn ON pn.oid = parent.relnamespace
JOIN pg_catalog.pg_class AS child ON child.oid = inh.inhrelid
JOIN pg_catalog.pg_namespace AS cn ON cn.oid = child.relnamespace
WHERE inh.inhdetachpending
  AND (pn.nspname = :'expected_schema' OR cn.nspname = :'expected_schema')

UNION ALL

SELECT
    'MATERIALIZED VIEW NOT POPULATED',
    NULL::name,
    c.relname
FROM pg_catalog.pg_class AS c
JOIN pg_catalog.pg_namespace AS n ON n.oid = c.relnamespace
WHERE n.nspname = :'expected_schema'
  AND c.relkind = 'm'
  AND NOT c.relispopulated
ORDER BY finding, affected_object;

-- 11. Routine security review
\echo ''
\echo '--- [11/14] Routine security review ---'

SELECT
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
    CASE WHEN p.prosecdef THEN 'DEFINER' ELSE 'INVOKER' END AS security_mode,
    p.proconfig AS routine_configuration
FROM pg_catalog.pg_proc AS p
JOIN pg_catalog.pg_namespace AS n ON n.oid = p.pronamespace
JOIN pg_catalog.pg_language AS l ON l.oid = p.prolang
WHERE n.nspname = :'expected_schema'
ORDER BY p.proname, identity_arguments;

-- 12. Installed extensions
\echo ''
\echo '--- [12/14] Installed extension baseline ---'

SELECT
    e.extname AS extension_name,
    e.extversion AS installed_version,
    pg_catalog.pg_get_userbyid(e.extowner) AS owner,
    n.nspname AS exported_objects_schema,
    e.extrelocatable AS relocatable
FROM pg_catalog.pg_extension AS e
JOIN pg_catalog.pg_namespace AS n ON n.oid = e.extnamespace
ORDER BY e.extname;

-- 13. PUBLIC schema privileges
\echo ''
\echo '--- [13/14] PUBLIC privileges on the target schema — review signal ---'

SELECT
    n.nspname AS schema_name,
    x.privilege_type,
    x.is_grantable
FROM pg_catalog.pg_namespace AS n
CROSS JOIN LATERAL pg_catalog.aclexplode(
    COALESCE(n.nspacl, pg_catalog.acldefault('n', n.nspowner))
) AS x
WHERE n.nspname = :'expected_schema'
  AND x.grantee = 0
ORDER BY x.privilege_type;

-- 14. Hard-gate summary
\echo ''
\echo '--- [14/14] Baseline hard-gate summary ---'

WITH checks AS (
    SELECT
        current_database() = :'expected_database' AS database_matches,
        EXISTS (
            SELECT 1
            FROM pg_catalog.pg_namespace AS n
            WHERE n.nspname = :'expected_schema'
        ) AS schema_exists,
        EXISTS (
            SELECT 1
            FROM pg_catalog.pg_namespace AS n
            WHERE n.nspname = :'expected_schema'
              AND pg_catalog.pg_get_userbyid(n.nspowner) = :'expected_owner'
        ) AS schema_owner_matches,
        NOT EXISTS (
            SELECT 1
            FROM pg_catalog.pg_class AS c
            JOIN pg_catalog.pg_namespace AS n ON n.oid = c.relnamespace
            WHERE n.nspname = :'expected_schema'
              AND c.relkind IN ('r', 'p', 'v', 'm', 'S', 'f', 'i', 'I')
              AND pg_catalog.pg_get_userbyid(c.relowner) <> :'expected_owner'
        )
        AND NOT EXISTS (
            SELECT 1
            FROM pg_catalog.pg_proc AS p
            JOIN pg_catalog.pg_namespace AS n ON n.oid = p.pronamespace
            WHERE n.nspname = :'expected_schema'
              AND pg_catalog.pg_get_userbyid(p.proowner) <> :'expected_owner'
        )
        AND NOT EXISTS (
            SELECT 1
            FROM pg_catalog.pg_type AS t
            JOIN pg_catalog.pg_namespace AS n ON n.oid = t.typnamespace
            LEFT JOIN pg_catalog.pg_class AS type_class
                ON type_class.oid = t.typrelid
            WHERE n.nspname = :'expected_schema'
              AND t.typisdefined
              AND t.typelem = 0
              AND (t.typrelid = 0 OR type_class.relkind = 'c')
              AND pg_catalog.pg_get_userbyid(t.typowner) <> :'expected_owner'
        ) AS object_owners_match,
        NOT EXISTS (
            SELECT 1
            FROM pg_catalog.pg_constraint AS con
            JOIN pg_catalog.pg_class AS c ON c.oid = con.conrelid
            JOIN pg_catalog.pg_namespace AS n ON n.oid = c.relnamespace
            WHERE n.nspname = :'expected_schema'
              AND (NOT con.conenforced OR NOT con.convalidated)
        ) AS constraints_healthy,
        NOT EXISTS (
            SELECT 1
            FROM pg_catalog.pg_index AS i
            JOIN pg_catalog.pg_class AS c ON c.oid = i.indrelid
            JOIN pg_catalog.pg_namespace AS n ON n.oid = c.relnamespace
            WHERE n.nspname = :'expected_schema'
              AND (NOT i.indislive OR NOT i.indisready OR NOT i.indisvalid)
        ) AS indexes_healthy,
        NOT EXISTS (
            SELECT 1
            FROM pg_catalog.pg_inherits AS inh
            JOIN pg_catalog.pg_class AS parent ON parent.oid = inh.inhparent
            JOIN pg_catalog.pg_namespace AS pn ON pn.oid = parent.relnamespace
            JOIN pg_catalog.pg_class AS child ON child.oid = inh.inhrelid
            JOIN pg_catalog.pg_namespace AS cn ON cn.oid = child.relnamespace
            WHERE inh.inhdetachpending
              AND (pn.nspname = :'expected_schema'
                   OR cn.nspname = :'expected_schema')
        ) AS no_detach_pending
)
SELECT
    database_matches,
    schema_exists,
    schema_owner_matches,
    object_owners_match,
    constraints_healthy,
    indexes_healthy,
    no_detach_pending,
    database_matches
        AND schema_exists
        AND schema_owner_matches
        AND object_owners_match
        AND constraints_healthy
        AND indexes_healthy
        AND no_detach_pending AS baseline_hard_checks_pass
FROM checks;

WITH checks AS (
    SELECT
        current_database() = :'expected_database'
        AND EXISTS (
            SELECT 1 FROM pg_catalog.pg_namespace AS n
            WHERE n.nspname = :'expected_schema'
              AND pg_catalog.pg_get_userbyid(n.nspowner) = :'expected_owner'
        )
        AND NOT EXISTS (
            SELECT 1
            FROM pg_catalog.pg_class AS c
            JOIN pg_catalog.pg_namespace AS n ON n.oid = c.relnamespace
            WHERE n.nspname = :'expected_schema'
              AND c.relkind IN ('r', 'p', 'v', 'm', 'S', 'f', 'i', 'I')
              AND pg_catalog.pg_get_userbyid(c.relowner) <> :'expected_owner'
        )
        AND NOT EXISTS (
            SELECT 1
            FROM pg_catalog.pg_proc AS p
            JOIN pg_catalog.pg_namespace AS n ON n.oid = p.pronamespace
            WHERE n.nspname = :'expected_schema'
              AND pg_catalog.pg_get_userbyid(p.proowner) <> :'expected_owner'
        )
        AND NOT EXISTS (
            SELECT 1
            FROM pg_catalog.pg_type AS t
            JOIN pg_catalog.pg_namespace AS n ON n.oid = t.typnamespace
            LEFT JOIN pg_catalog.pg_class AS type_class
                ON type_class.oid = t.typrelid
            WHERE n.nspname = :'expected_schema'
              AND t.typisdefined
              AND t.typelem = 0
              AND (t.typrelid = 0 OR type_class.relkind = 'c')
              AND pg_catalog.pg_get_userbyid(t.typowner) <> :'expected_owner'
        )
        AND NOT EXISTS (
            SELECT 1
            FROM pg_catalog.pg_constraint AS con
            JOIN pg_catalog.pg_class AS c ON c.oid = con.conrelid
            JOIN pg_catalog.pg_namespace AS n ON n.oid = c.relnamespace
            WHERE n.nspname = :'expected_schema'
              AND (NOT con.conenforced OR NOT con.convalidated)
        )
        AND NOT EXISTS (
            SELECT 1
            FROM pg_catalog.pg_index AS i
            JOIN pg_catalog.pg_class AS c ON c.oid = i.indrelid
            JOIN pg_catalog.pg_namespace AS n ON n.oid = c.relnamespace
            WHERE n.nspname = :'expected_schema'
              AND (NOT i.indislive OR NOT i.indisready OR NOT i.indisvalid)
        )
        AND NOT EXISTS (
            SELECT 1
            FROM pg_catalog.pg_inherits AS inh
            JOIN pg_catalog.pg_class AS parent ON parent.oid = inh.inhparent
            JOIN pg_catalog.pg_namespace AS pn ON pn.oid = parent.relnamespace
            JOIN pg_catalog.pg_class AS child ON child.oid = inh.inhrelid
            JOIN pg_catalog.pg_namespace AS cn ON cn.oid = child.relnamespace
            WHERE inh.inhdetachpending
              AND (pn.nspname = :'expected_schema'
                   OR cn.nspname = :'expected_schema')
        ) AS baseline_hard_checks_pass
)
SELECT baseline_hard_checks_pass FROM checks
\gset

COMMIT;

\if :baseline_hard_checks_pass
\echo ''
\echo 'BASELINE RESULT: PASS'
\echo 'Hard gates passed. Review signals still require human assessment.'
\else
\echo ''
\echo 'BASELINE RESULT: FAIL'
\echo 'One or more hard gates failed. Review the transcript.'
\quit 4
\endif
