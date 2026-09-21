/*
===============================================================================
Part 5.3 — Restore and Selective Recovery with pg_restore
Canonical Acceptance Artifact

[TUTORIAL-ACCEPTANCE — SAFE-READ]

Target: PostgreSQL 18

Purpose:
  Collect bounded target-database evidence before a pg_restore operation.

This artifact DOES NOT:
  - execute pg_restore;
  - inspect or modify an archive;
  - create/drop databases, schemas, tables, or other objects;
  - perform DDL or DML;
  - modify roles, ownership, memberships, or ACLs;
  - change triggers, row-level security, or configuration;
  - modify tablespaces;
  - terminate sessions;
  - inspect credentials;
  - perform automatic remediation.

Interpretation:
  SAFE-READ != RESTORE-VALIDATED
===============================================================================
*/

\echo '======================================================================'
\echo 'Part 5.3 — pg_restore Target Readiness'
\echo '[TUTORIAL-ACCEPTANCE — SAFE-READ]'
\echo '======================================================================'

\echo '1. Target execution context'
SELECT
    current_database() AS database_name,
    session_user,
    current_user,
    current_setting('server_version') AS server_version,
    current_setting('server_version_num') AS server_version_num,
    pg_is_in_recovery() AS is_in_recovery;

\echo '2. Target database metadata and current size'
SELECT
    d.datname,
    pg_get_userbyid(d.datdba) AS owner_name,
    pg_encoding_to_char(d.encoding) AS encoding,
    d.datcollate,
    d.datctype,
    d.datallowconn,
    pg_size_pretty(pg_database_size(d.datname)) AS database_size,
    pg_database_size(d.datname) AS database_bytes
FROM pg_database AS d
WHERE d.datname = current_database();

\echo '3. Existing non-system schemas'
SELECT
    n.nspname AS schema_name,
    pg_get_userbyid(n.nspowner) AS owner_name
FROM pg_namespace AS n
WHERE n.nspname <> 'information_schema'
  AND n.nspname !~ '^pg_'
ORDER BY n.nspname;

\echo '4. Existing user-object counts'
SELECT
    c.relkind,
    count(*) AS object_count
FROM pg_class AS c
JOIN pg_namespace AS n
  ON n.oid = c.relnamespace
WHERE n.nspname <> 'information_schema'
  AND n.nspname !~ '^pg_'
GROUP BY c.relkind
ORDER BY c.relkind;

\echo '5. Installed extensions on target'
SELECT
    e.extname,
    e.extversion,
    n.nspname AS schema_name,
    pg_get_userbyid(e.extowner) AS owner_name
FROM pg_extension AS e
JOIN pg_namespace AS n
  ON n.oid = e.extnamespace
ORDER BY e.extname;

\echo '6. Target tablespaces'
SELECT
    t.spcname,
    pg_get_userbyid(t.spcowner) AS owner_name
FROM pg_tablespace AS t
ORDER BY t.spcname;

\echo '7. Current role capabilities'
SELECT
    r.rolname,
    r.rolsuper,
    r.rolcreatedb,
    r.rolcreaterole,
    r.rolcanlogin
FROM pg_roles AS r
WHERE r.rolname IN (session_user, current_user)
ORDER BY r.rolname;

\echo '8. Existing user-relation ownership distribution'
SELECT
    pg_get_userbyid(c.relowner) AS owner_name,
    count(*) AS relation_count
FROM pg_class AS c
JOIN pg_namespace AS n
  ON n.oid = c.relnamespace
WHERE n.nspname <> 'information_schema'
  AND n.nspname !~ '^pg_'
  AND c.relkind IN ('r','p','v','m','S','f')
GROUP BY c.relowner
ORDER BY relation_count DESC, owner_name;

\echo '9. Existing non-default tablespace assignments'
SELECT
    n.nspname AS schema_name,
    c.relname AS relation_name,
    c.relkind,
    t.spcname AS tablespace_name
FROM pg_class AS c
JOIN pg_namespace AS n
  ON n.oid = c.relnamespace
JOIN pg_tablespace AS t
  ON t.oid = c.reltablespace
WHERE c.reltablespace <> 0
  AND n.nspname <> 'information_schema'
  AND n.nspname !~ '^pg_'
ORDER BY t.spcname, n.nspname, c.relname;

\echo '10. Canonical interpretation boundary'
SELECT
    'SAFE-READ target evidence only. This does not inspect the archive, execute '
    'pg_restore, prove archive integrity/trust, validate dependencies, prove '
    'source/target compatibility, validate external capacity, or demonstrate '
    'successful PostgreSQL/application recovery.' AS interpretation;

\echo '======================================================================'
\echo 'Target readiness inspection complete. PostgreSQL state was not modified.'
\echo 'SAFE-READ != RESTORE-VALIDATED'
\echo '======================================================================'