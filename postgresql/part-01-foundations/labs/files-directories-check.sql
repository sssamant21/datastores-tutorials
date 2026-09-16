-- labs/files-directories-check.sql
-- [TUTORIAL-ACCEPTANCE — SAFE-READ]
-- Part 1.13 — PostgreSQL Files and Directories — Introduction
-- Target: PostgreSQL 18
-- READ ONLY.
-- No database mutation, filesystem access, configuration changes,
-- WAL manipulation, tablespace modification, relation-file manipulation,
-- or transaction-state manipulation.

-- 1. PostgreSQL version context.
SELECT
    current_setting('server_version') AS server_version,
    current_setting('server_version_num') AS server_version_num;

-- 2. Configured PostgreSQL data directory.
SELECT
    current_setting('data_directory') AS configured_data_directory;

-- 3. Configuration-file locations.
SELECT
    current_setting('config_file') AS config_file,
    current_setting('hba_file') AS hba_file,
    current_setting('ident_file') AS ident_file;

-- 4. Current database identity and OID.
SELECT
    oid AS database_oid,
    datname AS database_name
FROM pg_database
WHERE datname = current_database();

-- 5. Tablespace metadata.
SELECT
    oid AS tablespace_oid,
    spcname AS tablespace_name,
    pg_tablespace_location(oid) AS tablespace_location
FROM pg_tablespace
ORDER BY oid;
-- Exact OIDs and locations are environment-dependent.

-- 6. Prerequisite tutorial relation.
SELECT
    to_regclass('clinical.constraint_patient') AS expected_relation;
-- Expected non-NULL result: clinical.constraint_patient.
-- If NULL, complete/restore the earlier tutorial prerequisite before continuing.

-- 7. Relation physical identity.
SELECT
    'clinical.constraint_patient'::regclass AS relation,
    pg_relation_filenode('clinical.constraint_patient') AS filenode,
    pg_relation_filepath('clinical.constraint_patient') AS main_fork_first_segment;
-- Relation OID != necessarily current filenode.
-- pg_relation_filepath() != every physical file belonging to the relation.

-- 8. Relation size.
SELECT
    pg_relation_size('clinical.constraint_patient') AS relation_size_bytes,
    pg_size_pretty(pg_relation_size('clinical.constraint_patient')) AS relation_size_pretty;

-- 9. Total relation size.
SELECT
    pg_total_relation_size('clinical.constraint_patient') AS total_relation_size_bytes,
    pg_size_pretty(pg_total_relation_size('clinical.constraint_patient')) AS total_relation_size_pretty;

-- 10. Current database default tablespace context.
SELECT
    d.datname,
    d.dattablespace,
    t.spcname AS default_tablespace
FROM pg_database AS d
JOIN pg_tablespace AS t
    ON t.oid = d.dattablespace
WHERE d.datname = current_database();

-- 11. SAFE-READ completion marker.
SELECT
    'PASS — PostgreSQL storage-layout inspection completed without database mutation, '
    || 'filesystem access, configuration changes, WAL manipulation, tablespace '
    || 'changes, or relation-file manipulation.'
    AS tutorial_acceptance;

-- [TUTORIAL-ACCEPTANCE — SAFE-READ]
-- PASS when:
--   PostgreSQL version context is visible
--   configured data_directory is visible
--   config/hba/ident file locations are visible
--   current database and database OID are visible
--   tablespace metadata is inspectable
--   clinical.constraint_patient exists
--   current relation filenode is inspectable
--   main-fork first-segment filepath is inspectable
--   relation size is inspectable
--   total relation size is inspectable
--   current database default tablespace is inspectable
--   no operating-system access is required
--   no generic PostgreSQL server-file read function is used
--   no database object or data is changed
--   no configuration is changed
--   no WAL is manipulated
--   no tablespace is modified
--   no relation file is manipulated
--   no transaction-state storage is manipulated
--
-- Do NOT hard-code data-directory paths, database/tablespace OIDs,
-- tablespace locations, relation filenodes/filepaths, or relation sizes.
-- These values are environment-dependent and can change during a cluster's lifecycle.
