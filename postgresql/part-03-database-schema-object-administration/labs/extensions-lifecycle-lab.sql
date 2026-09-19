-- ============================================================================
-- Part 3.11 — Extensions and Extension Lifecycle Administration
-- Canonical Hands-On Lab
-- File: labs/extensions-lifecycle-lab.sql
-- Classification: [LAB-ONLY — MUTATING — TRANSACTIONALLY CONTAINED]
-- Target: PostgreSQL 18
--
-- Run only in an authorized disposable, non-production database.
-- The script creates an isolated schema, installs PostgreSQL-supplied hstore,
-- removes it with RESTRICT, and finishes with ROLLBACK.
-- Do not add COMMIT. Use a dedicated psql session.
-- Rollback does not eliminate CPU, memory, I/O, WAL, locking, logs,
-- monitoring events, or audit evidence. The containment claim applies only
-- to this reviewed hstore scenario, not arbitrary third-party extensions.
-- The lab never modifies an extension that was already installed.
-- ============================================================================

\set ON_ERROR_STOP on
\pset pager off

\echo 'Part 3.11 — PostgreSQL-supplied hstore lifecycle lab'

\if :{?lab_confirm}
\else
    \echo 'ERROR: explicit acknowledgement is required.'
    \echo 'Run with: -v lab_confirm=I_UNDERSTAND'
    \quit 3
\endif

SELECT :'lab_confirm' = 'I_UNDERSTAND' AS lab_confirmed
\gset

\if :lab_confirmed
\else
    \echo 'ERROR: lab_confirm must equal I_UNDERSTAND.'
    \quit 3
\endif

\if :{?environment_confirm}
\else
    \echo 'ERROR: explicit non-production acknowledgement is required.'
    \echo 'Run with: -v environment_confirm=NON_PRODUCTION'
    \quit 3
\endif

SELECT :'environment_confirm' = 'NON_PRODUCTION' AS environment_confirmed
\gset

\if :environment_confirmed
\else
    \echo 'ERROR: environment_confirm must equal NON_PRODUCTION.'
    \quit 3
\endif

\if :{?expected_database}
\else
    \echo 'ERROR: expected_database=<exact database name> is required.'
    \quit 3
\endif

SELECT current_database() = :'expected_database' AS database_confirmed
\gset

\if :database_confirmed
    \echo 'PASS: current database matches expected_database.'
\else
    \echo 'ERROR: current database does not match expected_database.'
    \quit 4
\endif

-- Immutable canonical target. Changing it creates an unreviewed experiment.
\set extension_name hstore

SELECT
    current_database() AS database_name,
    current_user AS current_user,
    session_user AS session_user,
    current_setting('server_version') AS server_version,
    current_setting('server_version_num') AS server_version_num,
    pg_is_in_recovery() AS in_recovery,
    :'extension_name' AS requested_extension;

SELECT
    current_setting('server_version_num')::integer >= 180000
    AND current_setting('server_version_num')::integer < 190000
        AS postgresql_18,
    NOT pg_is_in_recovery() AS writable_primary
\gset

\if :postgresql_18
    \echo 'PASS: PostgreSQL major version is 18.'
\else
    \echo 'ERROR: this canonical lab requires PostgreSQL 18.'
    \quit 4
\endif

\if :writable_primary
    \echo 'PASS: server is not in recovery.'
\else
    \echo 'ERROR: this mutating lab must not run on a recovery server.'
    \quit 4
\endif

SELECT EXISTS (
    SELECT 1
    FROM pg_available_extensions
    WHERE name = :'extension_name'
) AS extension_available
\gset

\if :extension_available
    \echo 'PASS: requested extension files are available.'
\else
    \echo 'ERROR: requested extension is not available on this server.'
    \quit 6
\endif

SELECT NOT EXISTS (
    SELECT 1
    FROM pg_extension
    WHERE extname = :'extension_name'
) AS extension_absent
\gset

\if :extension_absent
    \echo 'PASS: requested extension is not already installed.'
\else
    \echo 'ERROR: requested extension is already installed.'
    \echo 'The lab will not inspect, update, relocate, or remove it.'
    \quit 7
\endif

SELECT to_regnamespace('tutorial_extension_admin') IS NULL AS schema_absent
\gset

\if :schema_absent
    \echo 'PASS: isolated lab schema name is unused.'
\else
    \echo 'ERROR: tutorial_extension_admin already exists.'
    \quit 8
\endif

SELECT default_version AS extension_version
FROM pg_available_extensions
WHERE name = :'extension_name'
  AND default_version IS NOT NULL
\gset

\if :{?extension_version}
\else
    \echo 'ERROR: hstore has no selectable default version.'
    \quit 9
\endif

\echo 'Controlling default-version metadata'
SELECT
    name,
    version,
    installed,
    superuser,
    trusted,
    relocatable,
    schema AS fixed_schema,
    requires
FROM pg_available_extension_versions
WHERE name = :'extension_name'
  AND version = :'extension_version';

SELECT
    COUNT(*) = 1
    AND bool_and(relocatable)
    AND bool_and(schema IS NULL) AS schema_contract_eligible,
    COUNT(*) = 1
    AND bool_and(
        trusted
        OR EXISTS (
            SELECT 1
            FROM pg_roles
            WHERE rolname = current_user
              AND rolsuper
        )
    )
    AND has_database_privilege(current_user, current_database(), 'CREATE')
        AS install_authority_detected
FROM pg_available_extension_versions
WHERE name = :'extension_name'
  AND version = :'extension_version'
\gset

\if :schema_contract_eligible
    \echo 'PASS: default version permits isolated schema placement.'
\else
    \echo 'ERROR: default-version schema contract is unsuitable.'
    \quit 9
\endif

\if :install_authority_detected
    \echo 'PASS: catalog metadata indicates installation authority.'
\else
    \echo 'ERROR: current role lacks detected authority for default-version installation.'
    \echo 'A provider-specific role model may require a separate approved lab.'
    \quit 9
\endif

\echo 'Available version metadata (lexical display order only)'
SELECT
    name,
    version,
    installed,
    superuser,
    trusted,
    relocatable,
    schema,
    requires
FROM pg_available_extension_versions
WHERE name = :'extension_name'
ORDER BY version;

BEGIN;

SET LOCAL lock_timeout = '5s';
SET LOCAL statement_timeout = '2min';
SET LOCAL idle_in_transaction_session_timeout = '5min';

CREATE SCHEMA tutorial_extension_admin;

REVOKE CREATE ON SCHEMA tutorial_extension_admin FROM PUBLIC;

SELECT NOT has_schema_privilege(
    'PUBLIC',
    'tutorial_extension_admin',
    'CREATE'
) AS schema_hardened
\gset

\if :schema_hardened
    \echo 'PASS: PUBLIC cannot create objects in the lab schema.'
\else
    \echo 'ERROR: lab schema hardening check failed.'
    \quit 10
\endif

CREATE EXTENSION hstore
    WITH SCHEMA tutorial_extension_admin
    VERSION :'extension_version';

SELECT
    COUNT(*) = 1
    AND bool_and(e.extname = :'extension_name')
    AND bool_and(e.extversion = :'extension_version')
    AND bool_and(pg_get_userbyid(e.extowner) = current_user)
    AND bool_and(n.nspname = 'tutorial_extension_admin')
    AND bool_and(e.extrelocatable)
        AS installation_metadata_correct
FROM pg_extension AS e
JOIN pg_namespace AS n
  ON n.oid = e.extnamespace
WHERE e.extname = :'extension_name'
\gset

\if :installation_metadata_correct
    \echo 'PASS: installed name, version, owner, schema, and relocatable state match.'
\else
    \echo 'ERROR: installed extension metadata is unexpected.'
    \quit 11
\endif

\echo 'Installed extension inventory'
SELECT
    e.extname,
    e.extversion,
    pg_get_userbyid(e.extowner) AS owner,
    n.nspname AS extension_schema,
    e.extrelocatable,
    e.extconfig,
    e.extcondition
FROM pg_extension AS e
JOIN pg_namespace AS n
  ON n.oid = e.extnamespace
WHERE e.extname = :'extension_name';

\echo 'Extension members'
SELECT
    d.classid::regclass AS catalog,
    d.objid,
    pg_describe_object(d.classid, d.objid, d.objsubid) AS member
FROM pg_extension AS e
JOIN pg_depend AS d
  ON d.refclassid = 'pg_extension'::regclass
 AND d.refobjid = e.oid
 AND d.deptype = 'e'
WHERE e.extname = :'extension_name'
ORDER BY member;

SELECT COUNT(*) > 0 AS members_recorded
FROM pg_extension AS e
JOIN pg_depend AS d
  ON d.refclassid = 'pg_extension'::regclass
 AND d.refobjid = e.oid
 AND d.deptype = 'e'
WHERE e.extname = :'extension_name'
\gset

\if :members_recorded
    \echo 'PASS: PostgreSQL recorded extension members.'
\else
    \echo 'ERROR: no extension members were found.'
    \quit 12
\endif

-- RESTRICT is mandatory. Never retry with CASCADE.
DROP EXTENSION hstore RESTRICT;

SELECT NOT EXISTS (
    SELECT 1
    FROM pg_extension
    WHERE extname = :'extension_name'
) AS removed_inside_transaction
\gset

\if :removed_inside_transaction
    \echo 'PASS: extension removal with RESTRICT succeeded in the lab transaction.'
\else
    \echo 'ERROR: extension remains installed unexpectedly.'
    \quit 13
\endif

ROLLBACK;

SELECT
    NOT EXISTS (
        SELECT 1
        FROM pg_extension
        WHERE extname = :'extension_name'
    )
    AND to_regnamespace('tutorial_extension_admin') IS NULL
        AS rollback_cleanup_complete
\gset

\if :rollback_cleanup_complete
    \echo 'PASS: rollback cleanup is complete.'
\else
    \echo 'ERROR: rollback cleanup verification failed.'
    \quit 14
\endif

\echo 'PASS: Part 3.11 hstore lifecycle lab complete.'
\echo 'No COMMIT occurred. No CASCADE occurred.'
