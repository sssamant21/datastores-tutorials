/*
Part 6.3 Lab — Replication Access Check
Target: PostgreSQL 18
Classification: TUTORIAL-ACCEPTANCE — SAFE-READ
Status: Canonical Acceptance Artifact — Pending Repository Validation

PASS = observed evidence satisfies the narrow check.
FAIL = observed evidence proves an unsafe/unsatisfied condition.
UNKNOWN = evidence is external, inaccessible, or architecture-specific.

Never retrieve passwords, password hashes, primary_conninfo, private keys,
or secret-manager values.
*/
\pset pager off

\echo '=== Part 6.3 — Replication Access Check (SAFE-READ) ==='

\echo '--- 1. Instance/session identity ---'
SELECT current_database() AS database_name,
       current_user AS connected_user,
       session_user,
       inet_server_addr() AS server_address,
       inet_server_port() AS server_port,
       pg_is_in_recovery() AS is_in_recovery;

\echo '--- 2. Replication-capable roles ---'
SELECT rolname, rolcanlogin, rolreplication, rolsuper,
       rolcreatedb, rolcreaterole, rolbypassrls, rolvaliduntil,
       CASE
         WHEN rolreplication AND rolcanlogin
          AND NOT rolsuper AND NOT rolcreatedb
          AND NOT rolcreaterole AND NOT rolbypassrls THEN 'PASS'
         WHEN rolreplication AND rolsuper THEN 'REVIEW'
         ELSE 'UNKNOWN'
       END AS least_privilege_assessment
FROM pg_roles
WHERE rolreplication
ORDER BY rolname;

\echo '--- 3. Server SSL metadata ---'
SELECT name, setting, context, source, pending_restart
FROM pg_settings
WHERE name IN ('ssl','ssl_ca_file','ssl_cert_file','ssl_crl_dir',
               'ssl_crl_file','ssl_key_file',
               'ssl_min_protocol_version','ssl_max_protocol_version')
ORDER BY name;

\echo '--- 4. Current-session SSL evidence ---'
SELECT a.pid, a.usename, a.application_name,
       s.ssl, s.version, s.cipher, s.bits, s.client_dn, s.issuer_dn
FROM pg_stat_activity a
JOIN pg_stat_ssl s ON s.pid=a.pid
WHERE a.pid=pg_backend_pid();

\echo 'Current-session SSL does not prove future standby verify-full.'

\echo '--- 5. HBA parse status ---'
\echo 'If pg_hba_file_rules is unauthorized, record UNKNOWN; do not elevate for the lab.'
SELECT count(*) FILTER (WHERE error IS NOT NULL) AS rules_with_parse_errors,
       CASE WHEN count(*) FILTER (WHERE error IS NOT NULL)=0
            THEN 'PASS' ELSE 'FAIL' END AS parse_assessment
FROM pg_hba_file_rules;

\echo '--- 6. Replication-related HBA rules ---'
SELECT rule_number, file_name, line_number, type, database, user_name,
       address, netmask, auth_method, options, error
FROM pg_hba_file_rules
WHERE 'replication'=ANY(database)
ORDER BY rule_number;

\echo 'Review ordering, CIDR, role selector, hostssl, auth method and overlaps manually.'

\echo '--- 7. Acceptance summary ---'
WITH r AS (
  SELECT count(*) FILTER (
           WHERE rolreplication AND rolcanlogin
             AND NOT rolsuper AND NOT rolcreatedb
             AND NOT rolcreaterole AND NOT rolbypassrls
         ) AS least_privileged_roles
  FROM pg_roles
),
h AS (
  SELECT count(*) FILTER (WHERE 'replication'=ANY(database)) AS repl_rules,
         count(*) FILTER (WHERE error IS NOT NULL) AS errors
  FROM pg_hba_file_rules
)
SELECT CASE WHEN r.least_privileged_roles>0 THEN 'PASS' ELSE 'UNKNOWN' END
         AS dedicated_role_candidate,
       CASE WHEN current_setting('ssl')='on' THEN 'PASS' ELSE 'FAIL' END
         AS server_ssl_enabled,
       CASE WHEN h.errors>0 THEN 'FAIL'
            WHEN h.repl_rules>0 THEN 'REVIEW'
            ELSE 'UNKNOWN' END AS hba_replication_rule_check,
       'UNKNOWN' AS future_standby_verify_full,
       'UNKNOWN' AS standby_ca_trust,
       'UNKNOWN' AS hostname_certificate_match,
       'UNKNOWN' AS secret_storage_policy,
       'UNKNOWN' AS credential_rotation_validation,
       'UNKNOWN' AS certificate_rotation_validation
FROM r,h;

\echo 'Resolve safety-critical FAIL, REVIEW and UNKNOWN findings before standby construction.'
\echo 'Cleanup required: NONE (SAFE-READ).'
