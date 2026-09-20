/*
===============================================================================
Part 4.6 — Table, View, and Column Privileges
Canonical Acceptance Artifact

[TUTORIAL-ACCEPTANCE — SAFE-READ]

Target: PostgreSQL 18

Purpose:
  Inspect effective relation/column privileges, ACLs, grant options, and view
  security signals for a declared application role without executing the
  target relation or changing database state.

Required psql variables:
  expected_database
  expected_session_user
  application_role
  application_schema
  target_relation

Safety:
  - Catalog reads and PostgreSQL built-in inquiry functions only
  - No relation data reads
  - No view definition output
  - No CREATE / ALTER / DROP
  - No INSERT / UPDATE / DELETE / MERGE / TRUNCATE
  - No GRANT / REVOKE
  - No COPY / VACUUM / ANALYZE / CLUSTER / REINDEX
  - No REFRESH MATERIALIZED VIEW
  - No SET ROLE / SET SESSION AUTHORIZATION
  - No CALL or arbitrary user-defined function execution
  - No foreign-data-wrapper updatability hook invocation
  - No configuration changes

Expected impact:
  Catalog reads and short-lived catalog locks inside a REPEATABLE READ, READ
  ONLY transaction. Runtime and output scale with relation and column counts in
  the declared schema. Evidence contains security-sensitive role, owner,
  object, column, ACL, and authentication identity metadata. Run through an
  approved, bounded administrative session and protect captured output.
===============================================================================
*/

\set ON_ERROR_STOP on
\pset pager off

\if :{?expected_database}
\else
    \echo 'ERROR: required variable expected_database is missing.'
    \quit 3
\endif
\if :{?expected_session_user}
\else
    \echo 'ERROR: required variable expected_session_user is missing.'
    \quit 3
\endif
\if :{?application_role}
\else
    \echo 'ERROR: required variable application_role is missing.'
    \quit 3
\endif
\if :{?application_schema}
\else
    \echo 'ERROR: required variable application_schema is missing.'
    \quit 3
\endif
\if :{?target_relation}
\else
    \echo 'ERROR: required variable target_relation is missing.'
    \quit 3
\endif

SELECT
    :'expected_database' ~ '^[a-z_][a-z0-9_]*$'
    AND :'expected_session_user' ~ '^[a-z_][a-z0-9_]*$'
    AND :'application_role' ~ '^[a-z_][a-z0-9_]*$'
    AND :'application_schema' ~ '^[a-z_][a-z0-9_]*$'
    AND :'target_relation' ~ '^[a-z_][a-z0-9_]*$'
AS inputs_are_safe
\gset gate_

\if :gate_inputs_are_safe
\else
    \echo 'ERROR: all declared values must be simple lowercase identifiers.'
    \quit 3
\endif

SELECT
    pg_catalog.current_database() = :'expected_database'
    AND session_user = :'expected_session_user'
AS declared_context_matches
\gset gate_

\if :gate_declared_context_matches
\else
    \echo 'ERROR: connected database or session_user differs from declared context.'
    \quit 3
\endif

SELECT pg_catalog.current_setting('server_version_num')::integer / 10000 = 18
AS postgres_major_is_18
\gset gate_

\if :gate_postgres_major_is_18
\else
    \echo 'ERROR: this acceptance artifact requires PostgreSQL major version 18.'
    \quit 3
\endif

SELECT pg_catalog.count(*) = 1 AS application_role_exists
FROM pg_catalog.pg_roles
WHERE rolname = :'application_role'
\gset gate_

\if :gate_application_role_exists
\else
    \echo 'ERROR: declared application_role does not exist.'
    \quit 3
\endif

SELECT pg_catalog.count(*) = 1 AS application_schema_exists
FROM pg_catalog.pg_namespace
WHERE nspname = :'application_schema'
\gset gate_

\if :gate_application_schema_exists
\else
    \echo 'ERROR: declared application_schema does not exist.'
    \quit 3
\endif

SELECT pg_catalog.count(*) = 1 AS target_relation_exists
FROM pg_catalog.pg_class AS c
JOIN pg_catalog.pg_namespace AS n ON n.oid = c.relnamespace
WHERE n.nspname = :'application_schema'
  AND c.relname = :'target_relation'
  AND c.relkind IN ('r', 'p', 'v', 'm', 'f')
\gset gate_

\if :gate_target_relation_exists
\else
    \echo 'ERROR: target relation is missing or is not a supported table-like kind.'
    \quit 3
\endif

BEGIN TRANSACTION ISOLATION LEVEL REPEATABLE READ READ ONLY;

\echo ''
\echo '============================================================'
\echo 'Part 4.6 — Table, View, and Column Privilege Check'
\echo '[TUTORIAL-ACCEPTANCE — SAFE-READ]'
\echo '============================================================'
\echo 'NOTICE: output contains security-sensitive privilege metadata.'

-- ---------------------------------------------------------------------------
-- 1. Hard-gate context and target identity
-- ---------------------------------------------------------------------------

\echo ''
\echo '--- [1/10] Version, transaction, identity, role, and target ---'

SELECT
    pg_catalog.statement_timestamp() AS evidence_timestamp,
    pg_catalog.current_setting('server_version') AS server_version,
    pg_catalog.current_database() AS database_name,
    pg_catalog.pg_is_in_recovery() AS server_is_in_recovery,
    system_user AS authenticated_system_identity,
    session_user AS session_user,
    current_user AS current_user,
    :'application_role' AS application_role,
    app_role.rolsuper AS application_role_is_superuser,
    app_role.rolinherit AS application_role_inherits_privileges,
    app_role.rolcanlogin AS application_role_can_login,
    app_role.rolbypassrls AS application_role_bypasses_rls,
    n.nspname AS target_schema,
    c.relname AS target_relation,
    CASE c.relkind
        WHEN 'r' THEN 'TABLE'
        WHEN 'p' THEN 'PARTITIONED TABLE'
        WHEN 'v' THEN 'VIEW'
        WHEN 'm' THEN 'MATERIALIZED VIEW'
        WHEN 'f' THEN 'FOREIGN TABLE'
        ELSE c.relkind::text
    END AS target_kind,
    pg_catalog.pg_get_userbyid(c.relowner) AS target_owner,
    c.relispartition AS is_partition,
    c.relrowsecurity AS row_security_enabled,
    c.relforcerowsecurity AS row_security_forced,
    pg_catalog.current_setting('transaction_isolation') AS transaction_isolation,
    pg_catalog.current_setting('transaction_read_only') AS transaction_read_only
FROM pg_catalog.pg_class AS c
JOIN pg_catalog.pg_namespace AS n ON n.oid = c.relnamespace
JOIN pg_catalog.pg_roles AS app_role
  ON app_role.rolname = :'application_role'
WHERE n.nspname = :'application_schema'
  AND c.relname = :'target_relation';

-- ---------------------------------------------------------------------------
-- 2. Target effective relation privileges
-- ---------------------------------------------------------------------------

\echo ''
\echo '--- [2/10] Application-role and PUBLIC effective target privileges ---'

SELECT
    subject.subject_name,
    pg_catalog.has_table_privilege(subject.subject_name, c.oid, 'SELECT')
        AS can_select,
    pg_catalog.has_table_privilege(subject.subject_name, c.oid, 'INSERT')
        AS can_insert,
    pg_catalog.has_table_privilege(subject.subject_name, c.oid, 'UPDATE')
        AS can_update,
    pg_catalog.has_table_privilege(subject.subject_name, c.oid, 'DELETE')
        AS can_delete,
    pg_catalog.has_table_privilege(subject.subject_name, c.oid, 'TRUNCATE')
        AS can_truncate,
    pg_catalog.has_table_privilege(subject.subject_name, c.oid, 'REFERENCES')
        AS can_references,
    pg_catalog.has_table_privilege(subject.subject_name, c.oid, 'TRIGGER')
        AS can_trigger,
    pg_catalog.has_table_privilege(subject.subject_name, c.oid, 'MAINTAIN')
        AS can_maintain
FROM pg_catalog.pg_class AS c
JOIN pg_catalog.pg_namespace AS n ON n.oid = c.relnamespace
CROSS JOIN (
    VALUES (:'application_role'::name), ('public'::name)
) AS subject(subject_name)
WHERE n.nspname = :'application_schema'
  AND c.relname = :'target_relation'
ORDER BY subject.subject_name;

-- MAINTAIN is shown for complete relation evidence; Part 4.7 owns its design.

-- ---------------------------------------------------------------------------
-- 3. Target relation ACL expansion
-- ---------------------------------------------------------------------------

\echo ''
\echo '--- [3/10] Target relation owner, raw ACL, and expanded ACL ---'

SELECT
    pg_catalog.pg_get_userbyid(c.relowner) AS owner,
    c.relacl AS raw_acl,
    CASE
        WHEN acl.grantee = 0 THEN 'PUBLIC'
        ELSE pg_catalog.pg_get_userbyid(acl.grantee)
    END AS grantee,
    pg_catalog.pg_get_userbyid(acl.grantor) AS grantor,
    acl.privilege_type,
    acl.is_grantable
FROM pg_catalog.pg_class AS c
JOIN pg_catalog.pg_namespace AS n ON n.oid = c.relnamespace
CROSS JOIN LATERAL pg_catalog.aclexplode(
    COALESCE(
        c.relacl,
        pg_catalog.acldefault('r'::"char", c.relowner)
    )
) AS acl
WHERE n.nspname = :'application_schema'
  AND c.relname = :'target_relation'
ORDER BY grantee, acl.privilege_type, grantor;

-- ---------------------------------------------------------------------------
-- 4. Explicit target column ACL entries
-- ---------------------------------------------------------------------------

\echo ''
\echo '--- [4/10] Explicit target column ACL entries ---'

SELECT
    a.attnum AS column_position,
    a.attname AS column_name,
    a.attacl AS raw_column_acl,
    CASE
        WHEN acl.grantee = 0 THEN 'PUBLIC'
        ELSE pg_catalog.pg_get_userbyid(acl.grantee)
    END AS grantee,
    pg_catalog.pg_get_userbyid(acl.grantor) AS grantor,
    acl.privilege_type,
    acl.is_grantable
FROM pg_catalog.pg_class AS c
JOIN pg_catalog.pg_namespace AS n ON n.oid = c.relnamespace
JOIN pg_catalog.pg_attribute AS a ON a.attrelid = c.oid
CROSS JOIN LATERAL pg_catalog.aclexplode(a.attacl) AS acl
WHERE n.nspname = :'application_schema'
  AND c.relname = :'target_relation'
  AND a.attnum > 0
  AND NOT a.attisdropped
  AND a.attacl IS NOT NULL
ORDER BY a.attnum, grantee, acl.privilege_type, grantor;

-- Zero rows means there are no explicit per-column ACL entries.

-- ---------------------------------------------------------------------------
-- 5. Effective target column privilege matrix
-- ---------------------------------------------------------------------------

\echo ''
\echo '--- [5/10] Application-role effective target column privileges ---'

SELECT
    a.attnum AS column_position,
    a.attname AS column_name,
    a.attidentity <> '' AS is_identity,
    a.attgenerated <> '' AS is_generated,
    pg_catalog.has_column_privilege(
        :'application_role', c.oid, a.attnum, 'SELECT'
    ) AS can_select,
    pg_catalog.has_column_privilege(
        :'application_role', c.oid, a.attnum, 'INSERT'
    ) AS can_insert,
    pg_catalog.has_column_privilege(
        :'application_role', c.oid, a.attnum, 'UPDATE'
    ) AS can_update,
    pg_catalog.has_column_privilege(
        :'application_role', c.oid, a.attnum, 'REFERENCES'
    ) AS can_references
FROM pg_catalog.pg_class AS c
JOIN pg_catalog.pg_namespace AS n ON n.oid = c.relnamespace
JOIN pg_catalog.pg_attribute AS a ON a.attrelid = c.oid
WHERE n.nspname = :'application_schema'
  AND c.relname = :'target_relation'
  AND a.attnum > 0
  AND NOT a.attisdropped
ORDER BY a.attnum;

-- TRUE can result from a column grant or a broader relation-level grant.

-- ---------------------------------------------------------------------------
-- 6. Application-schema relation privilege inventory
-- ---------------------------------------------------------------------------

\echo ''
\echo '--- [6/10] Application-role relation inventory in declared schema ---'

SELECT
    c.relname AS relation_name,
    CASE c.relkind
        WHEN 'r' THEN 'TABLE'
        WHEN 'p' THEN 'PARTITIONED TABLE'
        WHEN 'v' THEN 'VIEW'
        WHEN 'm' THEN 'MATERIALIZED VIEW'
        WHEN 'f' THEN 'FOREIGN TABLE'
        ELSE c.relkind::text
    END AS relation_kind,
    pg_catalog.pg_get_userbyid(c.relowner) AS owner,
    c.relispartition AS is_partition,
    c.relrowsecurity AS row_security_enabled,
    c.relforcerowsecurity AS row_security_forced,
    pg_catalog.has_table_privilege(:'application_role', c.oid, 'SELECT')
        AS can_select,
    pg_catalog.has_table_privilege(:'application_role', c.oid, 'INSERT')
        AS can_insert,
    pg_catalog.has_table_privilege(:'application_role', c.oid, 'UPDATE')
        AS can_update,
    pg_catalog.has_table_privilege(:'application_role', c.oid, 'DELETE')
        AS can_delete,
    pg_catalog.has_table_privilege('public', c.oid, 'SELECT')
        AS public_can_select
FROM pg_catalog.pg_class AS c
JOIN pg_catalog.pg_namespace AS n ON n.oid = c.relnamespace
WHERE n.nspname = :'application_schema'
  AND c.relkind IN ('r', 'p', 'v', 'm', 'f')
ORDER BY c.relname;

-- ---------------------------------------------------------------------------
-- 7. Effective target grant options
-- ---------------------------------------------------------------------------

\echo ''
\echo '--- [7/10] Application-role target grant-option inventory ---'

SELECT
    pg_catalog.has_table_privilege(
        :'application_role', c.oid, 'SELECT WITH GRANT OPTION'
    ) AS select_grant_option,
    pg_catalog.has_table_privilege(
        :'application_role', c.oid, 'INSERT WITH GRANT OPTION'
    ) AS insert_grant_option,
    pg_catalog.has_table_privilege(
        :'application_role', c.oid, 'UPDATE WITH GRANT OPTION'
    ) AS update_grant_option,
    pg_catalog.has_table_privilege(
        :'application_role', c.oid, 'DELETE WITH GRANT OPTION'
    ) AS delete_grant_option,
    pg_catalog.has_table_privilege(
        :'application_role', c.oid, 'REFERENCES WITH GRANT OPTION'
    ) AS references_grant_option,
    pg_catalog.has_table_privilege(
        :'application_role', c.oid, 'TRIGGER WITH GRANT OPTION'
    ) AS trigger_grant_option
FROM pg_catalog.pg_class AS c
JOIN pg_catalog.pg_namespace AS n ON n.oid = c.relnamespace
WHERE n.nspname = :'application_schema'
  AND c.relname = :'target_relation';

-- ---------------------------------------------------------------------------
-- 8. Catalog-only view security and write-path signals
-- ---------------------------------------------------------------------------

\echo ''
\echo '--- [8/10] Catalog-only view security and write-path signals ---'

SELECT
    c.relname AS view_name,
    pg_catalog.pg_get_userbyid(c.relowner) AS owner,
    COALESCE((
        SELECT option_value::boolean
        FROM pg_catalog.pg_options_to_table(c.reloptions)
        WHERE option_name = 'security_invoker'
    ), false) AS security_invoker,
    COALESCE((
        SELECT option_value::boolean
        FROM pg_catalog.pg_options_to_table(c.reloptions)
        WHERE option_name = 'security_barrier'
    ), false) AS security_barrier,
    COALESCE((
        SELECT option_value
        FROM pg_catalog.pg_options_to_table(c.reloptions)
        WHERE option_name = 'check_option'
    ), 'NONE') AS check_option,
    c.relhasrules AS has_rewrite_rules,
    c.relhastriggers AS has_triggers,
    c.relrowsecurity AS row_security_enabled,
    c.relforcerowsecurity AS row_security_forced
FROM pg_catalog.pg_class AS c
JOIN pg_catalog.pg_namespace AS n ON n.oid = c.relnamespace
WHERE n.nspname = :'application_schema'
  AND c.relkind = 'v'
ORDER BY c.relname;

-- View definitions are intentionally not printed. These catalog-only signals
-- do not determine structural updatability or prove that a granted write will
-- succeed through authorization, constraint, trigger, rule, function, and
-- row-security gates. This strict artifact also avoids invoking foreign-data-
-- wrapper updatability hooks through pg_relation_is_updatable.

-- ---------------------------------------------------------------------------
-- 9. PUBLIC target column privilege matrix
-- ---------------------------------------------------------------------------

\echo ''
\echo '--- [9/10] PUBLIC effective target column privileges ---'

SELECT
    a.attnum AS column_position,
    a.attname AS column_name,
    pg_catalog.has_column_privilege('public', c.oid, a.attnum, 'SELECT')
        AS public_can_select,
    pg_catalog.has_column_privilege('public', c.oid, a.attnum, 'INSERT')
        AS public_can_insert,
    pg_catalog.has_column_privilege('public', c.oid, a.attnum, 'UPDATE')
        AS public_can_update,
    pg_catalog.has_column_privilege('public', c.oid, a.attnum, 'REFERENCES')
        AS public_can_references
FROM pg_catalog.pg_class AS c
JOIN pg_catalog.pg_namespace AS n ON n.oid = c.relnamespace
JOIN pg_catalog.pg_attribute AS a ON a.attrelid = c.oid
WHERE n.nspname = :'application_schema'
  AND c.relname = :'target_relation'
  AND a.attnum > 0
  AND NOT a.attisdropped
ORDER BY a.attnum;

-- ---------------------------------------------------------------------------
-- 10. Final hard-gate summary
-- ---------------------------------------------------------------------------

\echo ''
\echo '--- [10/10] Final hard-gate summary ---'

SELECT
    pg_catalog.current_setting('server_version_num')::integer / 10000 = 18
        AS postgres_major_is_18,
    pg_catalog.current_database() = :'expected_database' AS database_matches,
    session_user = :'expected_session_user' AS session_user_matches,
    (
        SELECT pg_catalog.count(*) = 1
        FROM pg_catalog.pg_roles
        WHERE rolname = :'application_role'
    ) AS application_role_exists,
    (
        SELECT pg_catalog.count(*) = 1
        FROM pg_catalog.pg_namespace
        WHERE nspname = :'application_schema'
    ) AS application_schema_exists,
    (
        SELECT pg_catalog.count(*) = 1
        FROM pg_catalog.pg_class AS c
        JOIN pg_catalog.pg_namespace AS n ON n.oid = c.relnamespace
        WHERE n.nspname = :'application_schema'
          AND c.relname = :'target_relation'
          AND c.relkind IN ('r', 'p', 'v', 'm', 'f')
    ) AS target_relation_exists,
    pg_catalog.current_setting('transaction_isolation') = 'repeatable read'
        AS isolation_is_repeatable_read,
    pg_catalog.current_setting('transaction_read_only')::boolean
        AS transaction_is_read_only
\gset final_

SELECT
    :'final_postgres_major_is_18'::boolean AS postgres_major_is_18,
    :'final_database_matches'::boolean AS database_matches,
    :'final_session_user_matches'::boolean AS session_user_matches,
    :'final_application_role_exists'::boolean AS application_role_exists,
    :'final_application_schema_exists'::boolean AS application_schema_exists,
    :'final_target_relation_exists'::boolean AS target_relation_exists,
    :'final_isolation_is_repeatable_read'::boolean
        AS isolation_is_repeatable_read,
    :'final_transaction_is_read_only'::boolean AS transaction_is_read_only;

ROLLBACK;

SELECT
    :'final_postgres_major_is_18'::boolean
    AND :'final_database_matches'::boolean
    AND :'final_session_user_matches'::boolean
    AND :'final_application_role_exists'::boolean
    AND :'final_application_schema_exists'::boolean
    AND :'final_target_relation_exists'::boolean
    AND :'final_isolation_is_repeatable_read'::boolean
    AND :'final_transaction_is_read_only'::boolean
AS all_hard_gates_passed
\gset final_

\if :final_all_hard_gates_passed
    \echo ''
    \echo 'SAFE-READ acceptance checks completed; all hard gates passed.'
    \echo 'No relation data, object privileges, or configuration were changed.'
    \echo 'Protect this output because it contains security-sensitive metadata.'
\else
    \echo ''
    \echo 'ERROR: one or more hard gates failed.'
    \quit 4
\endif
