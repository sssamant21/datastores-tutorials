/*
===============================================================================
Part 5.11 — Backup Validation, Integrity, and Restore Testing
Hands-On Lab / Draft Acceptance Artifact

[TUTORIAL-ACCEPTANCE — SAFE-READ]

Target: PostgreSQL 18

Purpose:
  Capture PostgreSQL-visible evidence that can support backup/recovery
  validation before backup or after a controlled restore.

This artifact DOES NOT:
  - create or restore a backup;
  - execute pg_dump, pg_restore, pg_basebackup, or pg_verifybackup;
  - create/drop databases;
  - modify schemas or data;
  - alter roles or privileges;
  - alter backup/recovery configuration;
  - promote a server;
  - execute CHECKPOINT;
  - delete backup/WAL artifacts;
  - perform application-level recovery acceptance.

Run destructive restore procedures only against explicitly approved isolated
recovery-test targets.

Canonical acceptance boundary:
  Compare this evidence with a trusted source baseline/recovery specification.
  Findings such as invalid indexes or unvalidated constraints are not proof
  that the restore introduced the condition.

  SAFE-READ != BACKUP-ARTIFACT-VALIDATED
  SAFE-READ != RESTORE-TESTED
  SAFE-READ != APPLICATION-RECOVERY-VALIDATED
  SAFE-READ != RPO/RTO-VALIDATED
===============================================================================
*/

\set ON_ERROR_STOP on

\echo '======================================================================'
\echo 'Part 5.11 — Backup Validation / Restore Evidence — SAFE-READ'
\echo '======================================================================'

-- ---------------------------------------------------------------------------
-- 1. Server identity
-- ---------------------------------------------------------------------------

\echo ''
\echo '[1/10] Server identity'

SELECT
    current_database() AS connected_database,
    current_user AS current_user_name,
    version() AS server_version,
    current_setting('server_version_num') AS server_version_num,
    pg_postmaster_start_time() AS postmaster_start_time,
    current_timestamp AS observed_at;

-- ---------------------------------------------------------------------------
-- 2. Recovery state
-- ---------------------------------------------------------------------------

\echo ''
\echo '[2/10] Recovery state'

SELECT
    pg_is_in_recovery() AS is_in_recovery,
    CASE
        WHEN pg_is_in_recovery()
            THEN pg_last_wal_replay_lsn()
        ELSE pg_current_wal_lsn()
    END AS observed_wal_position,
    CASE
        WHEN pg_is_in_recovery()
            THEN pg_last_xact_replay_timestamp()
        ELSE NULL
    END AS last_replayed_transaction_timestamp;

\echo ''
\echo 'NOTE: Recovery state/LSN evidence does not independently prove that the'
\echo 'intended business recovery point was reached.'

-- ---------------------------------------------------------------------------
-- 3. Database inventory
-- ---------------------------------------------------------------------------

\echo ''
\echo '[3/10] Database inventory'

SELECT
    datname,
    pg_catalog.pg_get_userbyid(datdba) AS owner,
    encoding,
    datcollate,
    datctype,
    datistemplate,
    datallowconn,
    datconnlimit
FROM pg_catalog.pg_database
ORDER BY datname;

-- ---------------------------------------------------------------------------
-- 4. User schema / relation inventory for the connected database
-- ---------------------------------------------------------------------------

\echo ''
\echo '[4/10] User schema and relation inventory'

SELECT
    n.nspname AS schema_name,
    count(*) FILTER (WHERE c.relkind = 'r') AS ordinary_tables,
    count(*) FILTER (WHERE c.relkind = 'p') AS partitioned_tables,
    count(*) FILTER (WHERE c.relkind = 'i') AS indexes,
    count(*) FILTER (WHERE c.relkind = 'I') AS partitioned_indexes,
    count(*) FILTER (WHERE c.relkind = 'S') AS sequences,
    count(*) FILTER (WHERE c.relkind = 'v') AS views,
    count(*) FILTER (WHERE c.relkind = 'm') AS materialized_views,
    count(*) FILTER (WHERE c.relkind = 'f') AS foreign_tables,
    count(*) AS total_relations
FROM pg_catalog.pg_namespace AS n
LEFT JOIN pg_catalog.pg_class AS c
    ON c.relnamespace = n.oid
WHERE n.nspname <> 'information_schema'
  AND n.nspname NOT LIKE 'pg\_%' ESCAPE '\'
GROUP BY n.nspname
ORDER BY n.nspname;

-- ---------------------------------------------------------------------------
-- 5. Installed extensions
-- ---------------------------------------------------------------------------

\echo ''
\echo '[5/10] Installed extensions'

SELECT
    e.extname,
    e.extversion,
    n.nspname AS extension_schema
FROM pg_catalog.pg_extension AS e
JOIN pg_catalog.pg_namespace AS n
    ON n.oid = e.extnamespace
ORDER BY e.extname;

\echo ''
\echo 'NOTE: Extension catalog presence does not prove external extension'
\echo 'packages/binaries are available in every future recovery environment.'

-- ---------------------------------------------------------------------------
-- 6. Tablespaces
-- ---------------------------------------------------------------------------

\echo ''
\echo '[6/10] Tablespace inventory'

SELECT
    t.spcname,
    pg_catalog.pg_get_userbyid(t.spcowner) AS owner,
    pg_catalog.pg_tablespace_location(t.oid) AS location
FROM pg_catalog.pg_tablespace AS t
ORDER BY t.spcname;

\echo ''
\echo 'Treat tablespace paths as potentially environment-sensitive information.'

-- ---------------------------------------------------------------------------
-- 7. Object inventory for workload-specific acceptance design
-- ---------------------------------------------------------------------------

\echo ''
\echo '[7/10] Detailed user-object inventory'

SELECT
    n.nspname AS schema_name,
    c.relname AS object_name,
    CASE c.relkind
        WHEN 'r' THEN 'table'
        WHEN 'p' THEN 'partitioned table'
        WHEN 'i' THEN 'index'
        WHEN 'I' THEN 'partitioned index'
        WHEN 'S' THEN 'sequence'
        WHEN 'v' THEN 'view'
        WHEN 'm' THEN 'materialized view'
        WHEN 'f' THEN 'foreign table'
        ELSE c.relkind::text
    END AS object_type,
    pg_catalog.pg_get_userbyid(c.relowner) AS owner
FROM pg_catalog.pg_class AS c
JOIN pg_catalog.pg_namespace AS n
    ON n.oid = c.relnamespace
WHERE n.nspname <> 'information_schema'
  AND n.nspname NOT LIKE 'pg\_%' ESCAPE '\'
ORDER BY n.nspname, object_type, c.relname;

\echo ''
\echo 'Use this inventory to build workload-specific expected-object checks.'
\echo 'Presence alone does not prove object contents are correct.'

-- ---------------------------------------------------------------------------
-- 8. Invalid indexes
-- ---------------------------------------------------------------------------

\echo ''
\echo '[8/10] Invalid-index evidence'

SELECT
    n.nspname AS schema_name,
    c.relname AS index_name,
    t.relname AS table_name,
    i.indisvalid,
    i.indisready,
    i.indislive
FROM pg_catalog.pg_index AS i
JOIN pg_catalog.pg_class AS c
    ON c.oid = i.indexrelid
JOIN pg_catalog.pg_class AS t
    ON t.oid = i.indrelid
JOIN pg_catalog.pg_namespace AS n
    ON n.oid = c.relnamespace
WHERE NOT i.indisvalid
   OR NOT i.indisready
   OR NOT i.indislive
ORDER BY n.nspname, c.relname;

\echo ''
\echo 'An empty result is expected for a normal fully-valid index inventory.'

-- ---------------------------------------------------------------------------
-- 9. Constraints not validated
-- ---------------------------------------------------------------------------

\echo ''
\echo '[9/10] Not-yet-validated constraint evidence'

SELECT
    n.nspname AS schema_name,
    c.relname AS relation_name,
    con.conname AS constraint_name,
    con.contype AS constraint_type,
    con.convalidated
FROM pg_catalog.pg_constraint AS con
JOIN pg_catalog.pg_class AS c
    ON c.oid = con.conrelid
JOIN pg_catalog.pg_namespace AS n
    ON n.oid = c.relnamespace
WHERE NOT con.convalidated
  AND n.nspname <> 'information_schema'
  AND n.nspname NOT LIKE 'pg\_%' ESCAPE '\'
ORDER BY n.nspname, c.relname, con.conname;

\echo ''
\echo 'Not-yet-validated constraints may be intentional.'
\echo 'Compare against the source baseline and recovery acceptance specification.'

-- ---------------------------------------------------------------------------
-- 10. Compact evidence summary
-- ---------------------------------------------------------------------------

\echo ''
\echo '[10/10] Compact evidence summary'

WITH user_namespaces AS (
    SELECT oid
    FROM pg_catalog.pg_namespace
    WHERE nspname <> 'information_schema'
      AND nspname NOT LIKE 'pg\_%' ESCAPE '\'
)
SELECT
    (SELECT count(*) FROM pg_catalog.pg_database) AS database_count,
    (SELECT count(*) FROM user_namespaces) AS user_schema_count,
    (
        SELECT count(*)
        FROM pg_catalog.pg_class
        WHERE relnamespace IN (SELECT oid FROM user_namespaces)
          AND relkind IN ('r', 'p')
    ) AS table_count,
    (
        SELECT count(*)
        FROM pg_catalog.pg_class
        WHERE relnamespace IN (SELECT oid FROM user_namespaces)
          AND relkind IN ('i', 'I')
    ) AS index_count,
    (SELECT count(*) FROM pg_catalog.pg_extension) AS extension_count,
    (SELECT count(*) FROM pg_catalog.pg_tablespace) AS tablespace_count,
    (
        SELECT count(*)
        FROM pg_catalog.pg_index AS i
        JOIN pg_catalog.pg_class AS c
          ON c.oid = i.indexrelid
        WHERE c.relnamespace IN (SELECT oid FROM user_namespaces)
          AND (
              NOT i.indisvalid
              OR NOT i.indisready
              OR NOT i.indislive
          )
    ) AS invalid_index_count,
    (
        SELECT count(*)
        FROM pg_catalog.pg_constraint AS con
        JOIN pg_catalog.pg_class AS c
          ON c.oid = con.conrelid
        WHERE c.relnamespace IN (SELECT oid FROM user_namespaces)
          AND NOT con.convalidated
    ) AS unvalidated_constraint_count;

\echo ''
\echo '======================================================================'
\echo 'SAFE-READ evidence collection complete.'
\echo ''
\echo 'This check does NOT prove:'
\echo '  * backup artifact integrity;'
\echo '  * pg_verifybackup success;'
\echo '  * pg_restore/psql restore success;'
\echo '  * complete WAL/PITR recoverability;'
\echo '  * application correctness;'
\echo '  * RPO/RTO compliance.'
\echo ''
\echo 'Compare restored evidence with the trusted source baseline/recovery specification.'
\echo 'Protect secrets and sensitive data in captured evidence.'
\echo 'A mature backup program requires recurring isolated restore rehearsals.'
\echo 'Recovery-test cleanup/sanitization must be explicitly confirmed.'
\echo '======================================================================'
