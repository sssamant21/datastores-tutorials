/*
===============================================================================
Part 4.12 — Authentication Architecture and pg_hba.conf Policy
Canonical Acceptance Artifact

[TUTORIAL-ACCEPTANCE — SAFE-READ]

Target: PostgreSQL 18

Purpose:
  Inspect PostgreSQL authentication-policy evidence without modifying
  authentication, credentials, roles, privileges, networking, or server state.

Important:
  pg_hba_file_rules describes the current HBA file contents PostgreSQL can
  inspect. Do not interpret it by itself as proof of the last successfully
  loaded runtime authentication policy.

Safety:
  - No pg_hba.conf or pg_ident.conf modification.
  - No configuration reload.
  - No role/password changes.
  - No password-verifier inspection.
  - No GRANT / REVOKE.
  - No external authentication attempts.
  - No session termination.
===============================================================================
*/

\echo '======================================================================'
\echo 'Part 4.12 — Authentication Architecture and pg_hba.conf Policy'
\echo '[TUTORIAL-ACCEPTANCE — SAFE-READ]'
\echo '======================================================================'

\echo '1. Execution context'
SELECT current_database() AS database_name, session_user, current_user, current_role;

\echo '2. Authentication-related configuration metadata'
SELECT name, setting, source, sourcefile, sourceline, pending_restart
FROM pg_settings
WHERE name IN ('hba_file','ident_file','password_encryption','authentication_timeout')
ORDER BY name;

\echo '3. IMPORTANT HBA evidence limitation'
SELECT 'pg_hba_file_rules reports current HBA file contents visible to PostgreSQL. '
       'It does not by itself prove that these rules are the last successfully '
       'loaded runtime authentication policy.' AS evidence_limitation;

\echo '4. Parsed HBA rule inventory — preserve rule order and provenance'
SELECT rule_number,file_name,line_number,type,database,user_name,address,netmask,
       auth_method,options,error
FROM pg_hba_file_rules
ORDER BY rule_number NULLS LAST,file_name,line_number NULLS LAST;

\echo '5. HBA parser-error evidence'
SELECT rule_number,file_name,line_number,error
FROM pg_hba_file_rules
WHERE error IS NOT NULL
ORDER BY rule_number NULLS LAST,file_name,line_number NULLS LAST;

\echo '6. Authentication-method inventory'
SELECT auth_method,count(*) AS rule_count
FROM pg_hba_file_rules
WHERE error IS NULL
GROUP BY auth_method
ORDER BY auth_method;

\echo '7. Connection-type inventory'
SELECT type AS connection_type,count(*) AS rule_count
FROM pg_hba_file_rules
WHERE error IS NULL
GROUP BY type
ORDER BY type;

\echo '8. Sensitive / migration-review authentication methods'
SELECT rule_number,file_name,line_number,type,database,user_name,address,netmask,
       auth_method,options
FROM pg_hba_file_rules
WHERE error IS NULL
  AND auth_method IN ('trust','password','md5','reject','scram-sha-256','oauth')
ORDER BY rule_number NULLS LAST;

\echo '9. Broad-address review signals — values have different semantics'
SELECT rule_number,file_name,line_number,type,database,user_name,address,netmask,
       auth_method,options
FROM pg_hba_file_rules
WHERE error IS NULL
  AND (
       address IN ('all','0.0.0.0','0.0.0.0/0','::','::/0','samehost','samenet')
       OR (address='0.0.0.0' AND netmask='0.0.0.0')
       OR (address='::' AND netmask='::')
  )
ORDER BY rule_number NULLS LAST;

\echo '10. TLS-related HBA connection types'
SELECT rule_number,file_name,line_number,type,database,user_name,address,netmask,
       auth_method,options
FROM pg_hba_file_rules
WHERE error IS NULL
  AND type IN ('hostssl','hostnossl')
ORDER BY rule_number NULLS LAST;

\echo '11. Special database-selector review'
SELECT rule_number,file_name,line_number,type,database,user_name,address,auth_method,options
FROM pg_hba_file_rules
WHERE error IS NULL
  AND (
      'all'=ANY(database)
      OR 'sameuser'=ANY(database)
      OR 'samerole'=ANY(database)
      OR 'replication'=ANY(database)
  )
ORDER BY rule_number NULLS LAST;

\echo '12. Parsed username-map evidence'
SELECT map_number,file_name,line_number,map_name,sys_name,pg_username,error
FROM pg_ident_file_mappings
ORDER BY map_number NULLS LAST,file_name,line_number NULLS LAST;

\echo '13. Username-map parser errors'
SELECT map_number,file_name,line_number,error
FROM pg_ident_file_mappings
WHERE error IS NOT NULL
ORDER BY map_number NULLS LAST,file_name,line_number NULLS LAST;

\echo '14. Authentication-policy review summary'
SELECT
    count(*) AS total_hba_entries,
    count(*) FILTER (WHERE error IS NOT NULL) AS entries_with_errors,
    count(*) FILTER (WHERE error IS NULL AND auth_method='trust') AS trust_rules,
    count(*) FILTER (WHERE error IS NULL AND auth_method='password') AS password_rules,
    count(*) FILTER (WHERE error IS NULL AND auth_method='md5') AS md5_rules,
    count(*) FILTER (WHERE error IS NULL AND auth_method='scram-sha-256') AS scram_rules,
    count(*) FILTER (WHERE error IS NULL AND auth_method='oauth') AS oauth_rules,
    count(*) FILTER (WHERE error IS NULL AND auth_method='reject') AS reject_rules,
    count(*) FILTER (WHERE error IS NULL AND type='hostssl') AS hostssl_rules,
    count(*) FILTER (WHERE error IS NULL AND type='hostnossl') AS hostnossl_rules
FROM pg_hba_file_rules;

\echo '15. Interpretation reminder'
SELECT 'pg_hba.conf is ordered authentication policy. Rule existence does not '
       'prove rule selection, network reachability, authentication success, '
       'CONNECT authorization, or object access. Current pg_hba_file_rules '
       'evidence also does not by itself prove the last successfully loaded '
       'runtime policy. Review order, provenance, matching fields, transport, '
       'authentication methods, options, mappings, parser errors, role '
       'architecture, and surrounding network/provider controls.' AS reminder;

\echo '======================================================================'
\echo 'SAFE-READ authentication-policy acceptance check complete.'
\echo 'No authentication configuration was intentionally reloaded or modified.'
\echo 'No roles, passwords, verifiers, privileges, networking, credentials,'
\echo 'OAuth tokens, or sessions were intentionally changed.'
\echo 'Treat authentication-policy evidence as security-sensitive.'
\echo '======================================================================'
