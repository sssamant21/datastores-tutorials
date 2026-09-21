/*
===============================================================================
Part 5.4 — Cluster-Wide Logical Backup with pg_dumpall
Canonical Acceptance Artifact

[TUTORIAL-ACCEPTANCE — SAFE-READ]

Target: PostgreSQL 18

Purpose:
  Collect bounded cluster metadata useful before designing/executing a
  pg_dumpall or globals-only logical backup workflow.

This artifact DOES NOT:
  - execute pg_dumpall, pg_dump, psql, or restore commands;
  - create/drop databases, roles, or tablespaces;
  - modify role memberships, ownership, ACLs, or configuration;
  - inspect password/authentication-secret material;
  - access or modify backup files;
  - inspect or alter filesystem tablespace paths;
  - delete backup artifacts;
  - perform automatic remediation.

Interpretation:
  SAFE-READ != CLUSTER-BACKUP-VALIDATED
===============================================================================
*/

\echo '======================================================================'
\echo 'Part 5.4 — pg_dumpall Cluster Readiness'
\echo '[TUTORIAL-ACCEPTANCE — SAFE-READ]'
\echo '======================================================================'

\echo '1. Execution context and PostgreSQL version'
SELECT current_database() AS connected_database,
       session_user, current_user,
       current_setting('server_version') AS server_version,
       current_setting('server_version_num') AS server_version_num,
       pg_is_in_recovery() AS is_in_recovery;

\echo '2. Database inventory'
SELECT d.datname,
       pg_get_userbyid(d.datdba) AS owner_name,
       pg_encoding_to_char(d.encoding) AS encoding,
       d.datcollate, d.datctype, d.datallowconn, d.datistemplate,
       pg_size_pretty(pg_database_size(d.datname)) AS database_size,
       pg_database_size(d.datname) AS database_bytes
FROM pg_database AS d
ORDER BY d.datname;

\echo '3. Connectable non-template database size summary'
SELECT count(*) FILTER (WHERE NOT datistemplate) AS non_template_databases,
       count(*) FILTER (WHERE datallowconn AND NOT datistemplate)
           AS connectable_non_template_databases,
       pg_size_pretty(sum(pg_database_size(datname))
           FILTER (WHERE datallowconn AND NOT datistemplate))
           AS connectable_database_total_size,
       sum(pg_database_size(datname))
           FILTER (WHERE datallowconn AND NOT datistemplate)
           AS connectable_database_total_bytes
FROM pg_database;

\echo '4. Role inventory without authentication-secret material'
SELECT r.rolname, r.rolsuper, r.rolinherit, r.rolcreaterole,
       r.rolcreatedb, r.rolcanlogin, r.rolreplication, r.rolbypassrls
FROM pg_roles AS r
ORDER BY r.rolname;

\echo '5. Role membership inventory'
SELECT parent.rolname AS granted_role,
       member.rolname AS member_role,
       pg_get_userbyid(m.grantor) AS grantor_name,
       m.admin_option
FROM pg_auth_members AS m
JOIN pg_roles AS parent ON parent.oid = m.roleid
JOIN pg_roles AS member ON member.oid = m.member
ORDER BY parent.rolname, member.rolname;

\echo '6. Tablespace metadata inventory'
SELECT t.spcname, pg_get_userbyid(t.spcowner) AS owner_name
FROM pg_tablespace AS t
ORDER BY t.spcname;

\echo '7. Database ownership distribution'
SELECT pg_get_userbyid(d.datdba) AS owner_name,
       count(*) AS database_count
FROM pg_database AS d
GROUP BY d.datdba
ORDER BY database_count DESC, owner_name;

\echo '8. Databases not accepting connections'
SELECT d.datname, d.datallowconn, d.datistemplate
FROM pg_database AS d
WHERE NOT d.datallowconn
ORDER BY d.datname;

\echo '9. Database-level tablespace assignments'
SELECT d.datname, t.spcname AS default_tablespace
FROM pg_database AS d
JOIN pg_tablespace AS t ON t.oid = d.dattablespace
ORDER BY d.datname;

\echo '10. Canonical interpretation boundary'
SELECT 'SAFE-READ inventory only. This does not execute pg_dumpall, prove client/server compatibility, validate backup credentials, inspect external tablespace storage, prove artifact completeness/integrity, validate retention, or demonstrate cluster/application recovery.' AS interpretation;

\echo '======================================================================'
\echo 'Cluster readiness inspection complete. PostgreSQL state was not modified.'
\echo 'SAFE-READ != CLUSTER-BACKUP-VALIDATED'
\echo '======================================================================'