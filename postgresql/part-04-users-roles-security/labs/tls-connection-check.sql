/*
===============================================================================
Part 4.13 — TLS, Client Certificates, and Connection Security
Canonical Acceptance Artifact

[TUTORIAL-ACCEPTANCE — SAFE-READ]

Target: PostgreSQL 18

Purpose:
  Inspect PostgreSQL TLS configuration, runtime TLS evidence, and related HBA
  policy without changing configuration, certificates, roles, or sessions.

Evidence boundaries:
  - Server TLS configuration != TLS requirement for every connection.
  - Runtime TLS evidence != client certificate/hostname verification policy.
  - PostgreSQL-hop TLS != proof of end-to-end TLS through proxies/LBs.
  - SAFE-READ != safe to publish.

Safety:
  - No ALTER SYSTEM.
  - No configuration reload.
  - No HBA/ident modification.
  - No certificate or private-key file reads.
  - No certificate rotation.
  - No credential inspection.
  - No GRANT / REVOKE.
  - No external TLS probes.
  - No session termination.
===============================================================================
*/

\echo '======================================================================'
\echo 'Part 4.13 — TLS, Client Certificates, and Connection Security'
\echo '[TUTORIAL-ACCEPTANCE — SAFE-READ]'
\echo '======================================================================'

\echo '1. Execution context'
SELECT
    current_database() AS database_name,
    session_user,
    current_user,
    current_role;

\echo '2. TLS-related PostgreSQL configuration metadata'
SELECT
    name,
    setting,
    unit,
    source,
    sourcefile,
    sourceline,
    pending_restart
FROM pg_settings
WHERE name IN (
    'ssl',
    'ssl_ca_file',
    'ssl_cert_file',
    'ssl_key_file',
    'ssl_crl_file',
    'ssl_crl_dir',
    'ssl_ciphers',
    'ssl_tls13_ciphers',
    'ssl_groups',
    'ssl_prefer_server_ciphers',
    'ssl_min_protocol_version',
    'ssl_max_protocol_version',
    'ssl_dh_params_file',
    'ssl_passphrase_command',
    'ssl_passphrase_command_supports_reload'
)
ORDER BY name;

\echo '3. Current backend TLS evidence'
SELECT
    a.pid,
    a.usename,
    a.datname,
    a.client_addr,
    s.ssl,
    s.version,
    s.cipher,
    s.bits,
    s.client_dn,
    s.client_serial,
    s.issuer_dn
FROM pg_stat_activity AS a
LEFT JOIN pg_stat_ssl AS s
    USING (pid)
WHERE a.pid = pg_backend_pid();

\echo '4. Bounded runtime TLS summary visible to this identity'
SELECT
    count(*) AS visible_backends,
    count(*) FILTER (WHERE s.ssl) AS ssl_backends,
    count(*) FILTER (WHERE NOT s.ssl) AS non_ssl_backends
FROM pg_stat_activity AS a
JOIN pg_stat_ssl AS s
    USING (pid);

\echo '5. Negotiated TLS versions visible to this identity'
SELECT
    version,
    count(*) AS backend_count
FROM pg_stat_ssl
WHERE ssl
GROUP BY version
ORDER BY version;

\echo '6. Negotiated TLS cipher summary visible to this identity'
SELECT
    cipher,
    bits,
    count(*) AS backend_count
FROM pg_stat_ssl
WHERE ssl
GROUP BY cipher, bits
ORDER BY cipher, bits;

\echo '7. HBA TLS transport-rule evidence'
SELECT
    rule_number,
    file_name,
    line_number,
    type,
    database,
    user_name,
    address,
    netmask,
    auth_method,
    options,
    error
FROM pg_hba_file_rules
WHERE type IN ('hostssl', 'hostnossl')
   OR error IS NOT NULL
ORDER BY
    rule_number NULLS LAST,
    file_name,
    line_number NULLS LAST;

\echo '8. Certificate-specific HBA evidence'
SELECT
    rule_number,
    file_name,
    line_number,
    type,
    database,
    user_name,
    address,
    auth_method,
    options
FROM pg_hba_file_rules
WHERE error IS NULL
  AND (
      auth_method = 'cert'
      OR EXISTS (
          SELECT 1
          FROM unnest(COALESCE(options, ARRAY[]::text[])) AS opt
          WHERE opt LIKE 'clientcert=%'
             OR opt LIKE 'clientname=%'
      )
  )
ORDER BY rule_number NULLS LAST;

\echo '9. Identity-mapping HBA evidence — not certificate-specific'
SELECT
    rule_number,
    file_name,
    line_number,
    type,
    database,
    user_name,
    address,
    auth_method,
    options
FROM pg_hba_file_rules
WHERE error IS NULL
  AND EXISTS (
      SELECT 1
      FROM unnest(COALESCE(options, ARRAY[]::text[])) AS opt
      WHERE opt LIKE 'map=%'
  )
ORDER BY rule_number NULLS LAST;

\echo '10. TLS/HBA evidence summary'
SELECT
    count(*) FILTER (WHERE error IS NULL AND type = 'hostssl') AS hostssl_rules,
    count(*) FILTER (WHERE error IS NULL AND type = 'hostnossl') AS hostnossl_rules,
    count(*) FILTER (WHERE error IS NULL AND auth_method = 'cert') AS cert_auth_rules,
    count(*) FILTER (WHERE error IS NOT NULL) AS hba_entries_with_errors
FROM pg_hba_file_rules;

\echo '11. Interpretation reminder'
SELECT
    'Server TLS configuration, HBA transport/authentication policy, runtime '
    'session encryption, client sslmode/CA/hostname verification, client '
    'certificate identity, PostgreSQL authorization, and external proxy/LB TLS '
    'are separate evidence layers. No single observation proves all layers.' AS reminder;

\echo '======================================================================'
\echo 'SAFE-READ TLS connection-security acceptance check complete.'
\echo 'No TLS configuration, certificate, HBA/ident policy, role, privilege,'
\echo 'credential, or session was intentionally modified.'
\echo 'No certificate or private-key file contents were read.'
\echo 'Treat connection-security evidence as sensitive.'
\echo '======================================================================'
