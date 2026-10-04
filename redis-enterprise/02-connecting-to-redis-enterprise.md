# 02 — Connecting to Redis Enterprise

**Status:** Draft

**Objective:** Connect securely and verify database access.

## Prerequisites

Obtain the database hostname, assigned port, credentials, trusted CA certificate, and network access. Find the endpoint in Database → Configuration → General. Management console credentials and addresses are separate from database access.

Confirm the CLI:
```bash
redis-cli --version
```

## Connect with TLS

Bash example; replace placeholders:
```bash
redis-cli \
  -h <database-endpoint> \
  -p <database-port> \
  --user <database-user> \
  --askpass \
  --tls \
  --cacert /path/to/ca.pem
```

Enter the password at the prompt. Omit --user for password-only authentication. For mutual TLS, also provide --cert /path/to/client.crt and --key /path/to/client.key.

If an approved database is configured without TLS, omit --tls and --cacert. Use TLS for production connections.

## Validate read/write access

Run in a test database:
```redis
PING
SET tutorial:connection:test "connected" EX 60
GET tutorial:connection:test
TTL tutorial:connection:test
DEL tutorial:connection:test
QUIT
```

Expect PONG, OK, "connected", and a positive TTL before expiration. PING alone does not prove write permissions.

## Redis Insight

Add the database hostname and port, configure credentials and TLS certificates, connect, and run PING in Workbench.

## Troubleshooting

| Error | Check |
|---|---|
| Timeout | VPN, routes, firewall, reachability |
| Connection refused | Port and database availability |
| DNS failure | Hostname and DNS |
| NOAUTH / WRONGPASS | Database credentials and user status |
| NOPERM | Command and key permissions |
| TLS error | CA trust, validity, hostname, client certificate requirements |

## Production practices and completion

Use least-privilege credentials, keep secrets out of code and command history, validate certificates, and configure application timeouts and pooling. Verify connectivity from the application network.

Completion: authenticate and validate read/write access.

## References

- [Connect to a database](https://redis.io/docs/latest/operate/rs/databases/connect/)
- [Redis CLI](https://redis.io/docs/latest/develop/tools/cli/)

**Next:** [03 — Data Types and Key Design](03-data-types-and-key-design.md)
