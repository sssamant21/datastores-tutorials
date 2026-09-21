/*
===============================================================================
Part 5.2 — Logical Backups with pg_dump
Canonical Acceptance Artifact

[TUTORIAL-ACCEPTANCE — SAFE-READ]

Target: PostgreSQL 18

Purpose:
  Collect bounded source-database evidence useful before designing/executing
  a pg_dump workflow.

This artifact DOES NOT:
  - execute pg_dump or pg_restore;
  - create/read/delete backup files;
  - perform DDL or DML;
  - change roles, memberships, ownership, or ACLs;
  - change PostgreSQL configuration;
  - choose a parallel job count automatically;
  - inspect passwords/tokens/keys;
  - perform automatic remediation.

Interpretation:
  SAFE-READ != BACKUP-VALIDATED
===============================================================================
*/

\echo '======================================================================'
\echo 'Part 5.2 — Logical Backups with pg_dump'
\echo '[TUTORIAL-ACCEPTANCE — SAFE-READ]'
\echo '======================================================================'

\echo '1. Execution context and server version'
SELECT
    current_database() AS database_name,
    session_user,
    current_user,
    current_setting('server_version') AS server_version,
    current_setting('server_version_num') AS server_version_num;

\echo '2. Current database metadata and logical size'
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

\echo '3. User/application schemas'
SELECT
    n.nspname AS schema_name,
    pg_get_userbyid(n.nspowner) AS owner_name
FROM pg_namespace AS n
WHERE n.nspname <> 'information_schema'
  AND n.nspname !~ '^pg_'
ORDER BY n.nspname;

\echo '4. Largest user relations'
SELECT
    n.nspname AS schema_name,
    c.relname AS relation_name,
    c.relkind,
    pg_get_userbyid(c.relowner) AS owner_name,
    pg_size_pretty(pg_total_relation_size(c.oid)) AS total_size,
    pg_total_relation_size(c.oid) AS total_bytes
FROM pg_class AS c
JOIN pg_namespace AS n
  ON n.oid = c.relnamespace
WHERE n.nspname <> 'information_schema'
  AND n.nspname !~ '^pg_'
  AND c.relkind IN ('r','p','m','i','S')
ORDER BY pg_total_relation_size(c.oid) DESC, n.nspname, c.relname
LIMIT 25;

\echo '5. Installed extensions and versions'
SELECT
    e.extname,
    e.extversion,
    n.nspname AS schema_name,
    pg_get_userbyid(e.extowner) AS owner_name
FROM pg_extension AS e
JOIN pg_namespace AS n
  ON n.oid = e.extnamespace
ORDER BY e.extname;

\echo '6. Large-object inventory'
SELECT
    count(*) AS large_object_count
FROM pg_largeobject_metadata;

\echo '7. User-relation ownership distribution'
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

\echo '8. Non-default tablespace use by user relations'
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

\echo '9. Object-count evidence by relation kind'
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

\echo '10. Canonical interpretation boundary'
SELECT
    'This SAFE-READ artifact provides source-database preflight evidence only. '
    'It does not execute pg_dump, validate client/server compatibility, prove '
    'destination capacity, protect cluster-wide globals, validate a produced '
    'archive, prove secure retention, or demonstrate restore/application '
    'recovery.' AS interpretation;

\echo '======================================================================'
\echo 'Acceptance inspection complete. Database state was not modified.'
\echo 'SAFE-READ != BACKUP-VALIDATED'
\echo '======================================================================'