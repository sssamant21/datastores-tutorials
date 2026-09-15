/*
 PostgreSQL Practical Tutorial
 Part 1.6 — Database Validation

 Classification: [SAFE-READ]

 Purpose:
 Inspect current connection identity and
 database-level metadata.

 Safety:
 - Read-only.
 - Contains no credentials.
 - Database names, owners, role information,
   locale configuration, and other metadata
   may be sensitive.
 - Results reflect the connected PostgreSQL
   database cluster and current privileges.
 - Review/redact output before sharing.
*/

SELECT
    current_database() AS database_name,
    session_user AS session_user,
    current_user AS effective_role,
    pg_backend_pid() AS backend_pid;

SELECT
    d.datname AS database_name,
    pg_catalog.pg_get_userbyid(d.datdba) AS owner,
    pg_catalog.pg_encoding_to_char(d.encoding) AS encoding,
    d.datlocprovider AS locale_provider,
    d.datlocale AS locale_name,
    d.datcollate AS lc_collate,
    d.datctype AS lc_ctype,
    d.datallowconn AS allow_connections,
    d.datconnlimit AS connection_limit,
    d.datistemplate AS is_template
FROM pg_catalog.pg_database AS d
ORDER BY d.datname;

SELECT
    rolname,
    rolsuper,
    rolcreatedb,
    rolcreaterole,
    rolcanlogin
FROM pg_catalog.pg_roles
WHERE rolname = current_user;

SELECT
    d.datname AS database_name,
    pg_catalog.pg_get_userbyid(d.datdba) AS owner
FROM pg_catalog.pg_database AS d
WHERE d.datname = 'healthcare_lab';
