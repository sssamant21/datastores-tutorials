# 02 — Connecting Securely with mongosh

**Status:** Draft

**Objective:** Connect securely, authenticate, and verify scoped access.

## Prerequisites

Obtain reachable hosts/ports, replica-set name, database identity, authentication database, trusted CA and optional client certificate, and network access. Use a compatible mongosh release.

```cmd
mongosh --version
```

## Replica-set connection

Single-line Windows Command Prompt example; replace all example values:

```cmd
mongosh "mongodb://mongo1.example.com:27017,mongo2.example.com:27017,mongo3.example.com:27017/mongodb_tutorials?replicaSet=rs0&authSource=admin" --username tutorial_user --tls --tlsCAFile "C:\certs\mongodb-ca.pem"
```

Enter the password at the prompt. The application database and authentication database can differ; admin is an example, not a universal value. All discovered member addresses must resolve and be reachable.

## Other connections

For a supplied SRV endpoint:
```cmd
mongosh "mongodb+srv://cluster.example.com/mongodb_tutorials?authSource=admin" --username tutorial_user --tlsCAFile "C:\certs\mongodb-ca.pem"
```

SRV enables TLS by default. It requires appropriate DNS records.

For a deliberate node diagnostic:
```cmd
mongosh "mongodb://mongo1.example.com:27017/mongodb_tutorials?authSource=admin&directConnection=true" --username tutorial_user --tls --tlsCAFile "C:\certs\mongodb-ca.pem"
```

Direct connections do not provide normal replica-set discovery/failover. A secondary rejects normal writes. For sharding, use supplied mongos endpoints.

If mutual TLS is required, add --tlsCertificateKeyFile with the client PEM path. A transport certificate alone does not select X.509 database authentication; the mechanism must match deployment configuration.

## Validate

```javascript
db.runCommand({ ping: 1 })
db.adminCommand({ hello: 1 })

use mongodb_tutorials

db.connection_checks.insertOne({
  _id: "tutorial-connection-check",
  status: "connected",
  checkedAt: new Date()
})
db.connection_checks.findOne({ _id: "tutorial-connection-check" })
db.connection_checks.deleteOne({ _id: "tutorial-connection-check" })
exit
```

Expect ok:1, an acknowledged insert, and the document. hello may report setName, isWritablePrimary, secondary, or msg:"isdbgrid" depending on topology. PING does not prove read/write permissions.

## Troubleshooting

| Symptom | Check |
|---|---|
| DNS failure | Hostname and resolver |
| Timeout/refused | Route, firewall, port, availability |
| Authentication failed | User, secret, authSource, mechanism |
| Unauthorized | Collection/database roles |
| TLS error | CA, hostname, expiry, client certificate |
| Server selection timeout | Discovered hosts, set name, primary availability |
| Secondary write rejection | Normal replica-set connection and primary health |

## Production practices and completion

Prompt for passwords, verify TLS, use least privilege, test from the application network, and configure driver pooling/timeouts separately from shell access.

## References

- [Connect with mongosh](https://www.mongodb.com/docs/mongodb-shell/connect/)
- [Shell options](https://www.mongodb.com/docs/mongodb-shell/reference/options/)

**Next:** [03 — Schema Design](03-databases-collections-documents-schema-design.md)
