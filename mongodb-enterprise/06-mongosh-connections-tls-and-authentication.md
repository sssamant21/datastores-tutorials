# 06 — mongosh Connections TLS and Authentication

**Status:** Written; static review complete; runtime lab validation pending  
**Part:** 1 — Foundations and Architecture  
**Goal:** Establish a certificate-verified, authenticated connection and distinguish transport, authentication and authorization failures.  
**Audience:** Developers, DBREs, SREs and Platform Engineers  
**Time:** 90–120 minutes  
**Baseline:** MongoDB 8.0, mongosh, Docker and OpenSSL supporting req -addext. Record exact versions.  
**Deployment:** Disposable self-managed standalone using core Community-compatible TLS/SCRAM features. No x.509 client authentication or replica-set member authentication is exercised.

## 1. Three independent checks

| Check | Question | Typical failure |
|---|---|---|
| TLS and server identity | Is the connection encrypted and the server certificate trusted for this host? | Unknown CA, expired certificate or hostname mismatch |
| Authentication | Which database identity is connecting? | Wrong password, authSource or mechanism |
| Authorization | What may this authenticated identity do? | Command denied despite successful login |

TLS does not assign database privileges. A password does not verify the server's certificate. A successful login does not prove a user has administrative access.

For production connections, use approved CA trust and the actual deployment connection string. Do not normalize errors by adding certificate-validation bypass flags.

## 2. Connection string anatomy

| Element | Example | Meaning |
|---|---|---|
| Scheme | mongodb:// | Standard seed-list connection |
| SRV scheme | mongodb+srv:// | DNS-based discovery with applicable driver behavior |
| Seed hosts | node1:27017,node2:27017 | Initial discovery targets |
| Default database | /training | Initial database context |
| authSource | authSource=admin | Database where the user is authenticated |
| replicaSet | replicaSet=rs0 | Expected replica-set identity |
| TLS | tls=true | Request TLS |
| serverSelectionTimeoutMS | 5000 | Bound time spent selecting an eligible server |
| connectTimeoutMS | 5000 | Bound establishment of a connection |

The default database and authentication database can differ. Replica-set discovery can return hosts beyond the initial seed, so DNS, network access and certificate names must work for discovered members too.

directConnection is appropriate for certain controlled diagnostic/lab cases; it is not a general fix for broken production replica-set discovery. SRV connections require DNS behavior to be understood and tested.

Passwords in URIs require encoding and can leak into process lists or logs. This lab uses prompted passwords.

## 3. Lab prerequisites and names

Use Bash on Linux/macOS or WSL with Docker Desktop integration on Windows for the certificate-generation commands. Docker commands are otherwise ordinary Docker CLI commands.

| Resource | Value |
|---|---|
| Host working directory | A new mongodb-ch06-lab directory |
| Database container | mongodb-ch06 |
| Published host port | 127.0.0.1:27036 |
| Data volume | mongodb-ch06-data |
| TLS volume | mongodb-ch06-tls |
| Database | mongodb_enterprise_tutorial_ch06 |
| Admin account | tls_lab_admin in admin |
| Scoped account | chapter06_user in training database |

The local CA and certificates are short-lived learning resources. They are not an organizational PKI or a production certificate-rotation design.

Check resource-name collisions with docker ps --all and docker volume ls before creating anything. If an exact name exists, identify it rather than overwriting it.

## 4. Generate a local CA and server certificate

In Bash:

```bash
mkdir mongodb-ch06-lab
cd mongodb-ch06-lab
mkdir tls
chmod 700 tls
umask 077
openssl version
openssl genrsa -out tls/ca.key 3072
openssl req -x509 -new -sha256 -key tls/ca.key -days 7 -out tls/ca.crt -subj "/CN=MongoDB Chapter06 Lab CA" -addext "basicConstraints=critical,CA:TRUE" -addext "keyUsage=critical,keyCertSign,cRLSign"
openssl genrsa -out tls/server.key 3072
openssl req -new -sha256 -key tls/server.key -out tls/server.csr -subj "/CN=localhost"
```

Create certificate extensions:

```bash
cat > tls/server.ext <<'EOF'
basicConstraints=critical,CA:FALSE
keyUsage=critical,digitalSignature,keyEncipherment,keyAgreement
extendedKeyUsage=serverAuth,clientAuth
subjectAltName=DNS:localhost,IP:127.0.0.1
EOF
openssl x509 -req -sha256 -in tls/server.csr -CA tls/ca.crt -CAkey tls/ca.key -CAcreateserial -days 7 -out tls/server.crt -extfile tls/server.ext
cat tls/server.key tls/server.crt > tls/server.pem
chmod 600 tls/server.pem tls/ca.key tls/server.key
openssl verify -CAfile tls/ca.crt tls/server.crt
openssl x509 -in tls/server.crt -noout -dates -ext subjectAltName
```

Expected: certificate verification reports OK; SAN includes localhost and 127.0.0.1. The PEM file combines the server key and certificate. The CA private key is not given to the database container.

The certificate has both serverAuth and clientAuth EKUs to match the documented combined certificate-key-file requirements. This standalone lab still authenticates users with SCRAM rather than x.509.

## 5. Copy only runtime certificates into a protected volume

Create volumes:

```bash
docker volume create mongodb-ch06-data
docker volume create mongodb-ch06-tls
```

The official image normally runs mongod under its mongodb user. Use a short initialization container to set certificate ownership without making the key world-readable:

```bash
docker run --rm --user 0 --entrypoint sh --mount "type=bind,source=$(pwd)/tls,target=/input,readonly" --mount source=mongodb-ch06-tls,target=/lab-tls mongo:8.0 -c 'set -eu; cp /input/server.pem /lab-tls/server.pem; cp /input/ca.crt /lab-tls/ca.crt; chown mongodb:mongodb /lab-tls /lab-tls/server.pem /lab-tls/ca.crt; chmod 700 /lab-tls; chmod 400 /lab-tls/server.pem; chmod 444 /lab-tls/ca.crt'
```

The initialization container runs briefly as root to set ownership. The database container uses the image's normal entrypoint. If a different approved image has different user conventions, adjust ownership from its actual user inventory.

Start the server:

```bash
docker run --name mongodb-ch06 --detach --publish 127.0.0.1:27036:27017 --memory 2g --mount source=mongodb-ch06-data,target=/data/db --mount source=mongodb-ch06-tls,target=/lab-tls,readonly mongo:8.0 --auth --wiredTigerCacheSizeGB 0.5 --tlsMode requireTLS --tlsCertificateKeyFile /lab-tls/server.pem --tlsCAFile /lab-tls/ca.crt --tlsAllowConnectionsWithoutCertificates
docker logs --tail 50 mongodb-ch06
```

requireTLS rejects plaintext connections. tlsAllowConnectionsWithoutCertificates allows a SCRAM client without a client certificate; it does not allow plaintext or disable the client's verification of the server.

## 6. Bootstrap and authenticate over TLS

Connect through localhost inside the new container:

```bash
docker exec -it mongodb-ch06 mongosh "mongodb://localhost:27017/admin?serverSelectionTimeoutMS=5000" --tls --tlsCAFile /lab-tls/ca.crt
```

In mongosh, create the first user through the localhost exception:

```javascript
var admin = db.getSiblingDB("admin");
admin.createUser({
  user: "tls_lab_admin",
  pwd: passwordPrompt(),
  roles: [{ role: "root", db: "admin" }]
});
```

Enter a unique training password. Exit and reconnect:

```bash
docker exec -it mongodb-ch06 mongosh "mongodb://localhost:27017/admin?authSource=admin&serverSelectionTimeoutMS=5000" --username tls_lab_admin --password --tls --tlsCAFile /lab-tls/ca.crt
```

Expected: encrypted connection, verified local CA and authenticated admin. The server certificate SAN matches localhost.

Create a scoped user:

```javascript
var training = db.getSiblingDB("mongodb_enterprise_tutorial_ch06");
if (training.getUser("chapter06_user") !== null) {
  throw new Error("Existing chapter user");
}
training.createUser({
  user: "chapter06_user",
  pwd: passwordPrompt(),
  roles: [{ role: "readWrite", db: "mongodb_enterprise_tutorial_ch06" }]
});
```

Choose a different password. Exit and connect as that user:

```bash
docker exec -it mongodb-ch06 mongosh "mongodb://localhost:27017/mongodb_enterprise_tutorial_ch06?authSource=mongodb_enterprise_tutorial_ch06&serverSelectionTimeoutMS=5000" --username chapter06_user --password --tls --tlsCAFile /lab-tls/ca.crt
```

## 7. Verify identity and CRUD

Inside the scoped session:

```javascript
var lab = db.getSiblingDB("mongodb_enterprise_tutorial_ch06");
var identity = db.runCommand({ connectionStatus: 1 });
if (identity.ok !== 1) throw new Error("Identity inspection failed");
printjson(identity.authInfo.authenticatedUsers);
if (!identity.authInfo.authenticatedUsers.some(u =>
  u.user === "chapter06_user" && u.db === "mongodb_enterprise_tutorial_ch06")) {
  throw new Error("Unexpected authenticated identity");
}
if (lab.getCollectionNames().includes("connection_checks")) {
  throw new Error("Existing chapter collection");
}
lab.createCollection("connection_checks");
lab.connection_checks.insertOne({ _id: "TLS01", verified: true });
if (!lab.connection_checks.findOne({ _id: "TLS01" }).verified) {
  throw new Error("TLS application contract failed");
}

var denied = false;
try {
  var result = db.getSiblingDB("admin").runCommand({ usersInfo: 1 });
  denied = result.ok !== 1 && result.code === 13;
} catch (e) {
  denied = e.code === 13;
}
if (!denied) throw new Error("Expected administrative command denial");
print("PASS: authenticated identity, scoped CRUD and administrative denial");
```

connectionStatus reports authenticated database identities. It is not a certificate-inspection command. The enforced server TLS mode, verified client options and transport checks supply TLS evidence.

## 8. Failure exercise — plaintext connection

Exit mongosh and intentionally omit TLS:

```bash
docker exec -it mongodb-ch06 mongosh "mongodb://localhost:27017/?serverSelectionTimeoutMS=5000"
```

Expected: connection failure. Authentication is not reached because the server requires TLS.

Correct by using the verified TLS URI/options from Section 6. Do not change the server to allow plaintext just to make the client connect.

## 9. Failure exercise — untrusted CA

Connect with TLS but omit the local CA:

```bash
docker exec -it mongodb-ch06 mongosh "mongodb://localhost:27017/?serverSelectionTimeoutMS=5000" --tls
```

Expected: certificate-trust failure because this new local CA is not in the container's normal trust store.

Correct by supplying /lab-tls/ca.crt. Do not add tlsAllowInvalidCertificates or tlsInsecure.

## 10. Failure exercise — hostname mismatch

On the host in the chapter working directory, use OpenSSL to inspect identity verification independently of database authentication:

```bash
openssl s_client -connect 127.0.0.1:27036 -CAfile tls/ca.crt -verify_hostname localhost -verify_return_error </dev/null
openssl s_client -connect 127.0.0.1:27036 -CAfile tls/ca.crt -verify_hostname wrong-host.invalid -verify_return_error </dev/null
```

Expected: localhost verification succeeds; wrong-host.invalid fails. Both commands reach the same endpoint, but the second requires a name absent from the certificate.

These commands exercise the certificate handshake, not a MongoDB login or CRUD operation. Production clients must use a hostname/IP covered by SAN. Fix DNS/certificate issuance or the endpoint configuration; bypassing hostname validation hides an identity problem.

## 11. Failure exercise — wrong password and authSource

Using the valid TLS connection command, enter a deliberately incorrect password once. Expected: authentication failure after TLS succeeds.

Next, use the correct password but the wrong authSource:

```bash
docker exec -it mongodb-ch06 mongosh "mongodb://localhost:27017/mongodb_enterprise_tutorial_ch06?authSource=admin&serverSelectionTimeoutMS=5000" --username chapter06_user --password --tls --tlsCAFile /lab-tls/ca.crt
```

Expected: authentication failure. Correct authSource to the user's database and reconnect successfully. Repeated blind retries can complicate incident analysis; identify the failing layer first.

## 12. Host connection, if mongosh is installed locally

From the chapter working directory:

```bash
mongosh "mongodb://127.0.0.1:27036/mongodb_enterprise_tutorial_ch06?authSource=mongodb_enterprise_tutorial_ch06&serverSelectionTimeoutMS=5000" --username chapter06_user --password --tls --tlsCAFile tls/ca.crt
```

The IP is covered by the certificate SAN. If this host-client exercise is unavailable, record it as not performed; the container-client exercises remain independently runnable.

For a remote production replica set, the URI must include its approved seed/SRV configuration and the trust chain appropriate to each discovered hostname. Do not reuse this local CA.

## 13. Troubleshooting by layer

| Symptom | Layer/evidence | Action |
|---|---|---|
| Connection refused | Listener, target port and container logs | Correct the endpoint or start the intended service |
| TLS server cannot start | Key-file path, ownership and certificate pairing | Correct runtime file access and PEM contents |
| Unknown CA | Client trust-chain verification | Supply the approved CA chain |
| Hostname mismatch | SAN and requested hostname/IP | Align endpoint and certificate identity |
| Expired certificate | Certificate dates and system clock | Renew through the approved issuance path |
| Authentication failure | User namespace, password and mechanism | Correct identity/authSource after proving TLS |
| Authorization code 13 | Authenticated user and role boundary | Use intended scoped permissions |
| Replica-set selection timeout | Discovered hosts, DNS and network paths | Validate all members and correct topology settings |

Inspect minimal logs and identity metadata. Do not paste private keys or passwords into tickets.

## 14. Production practices

Keep key ownership, certificate renewal, CA trust distribution and application rollout explicit. Test renewal before expiry, and verify the actual hostnames used by drivers rather than only the names used by administrators.

TLS negotiation and database authentication failures should be distinguished in monitoring. Replica-set and sharded-cluster member TLS/authentication require a dedicated design; this standalone lab does not establish that design.

A root training account is an administrative bootstrap convenience, not an application role. Use scoped identities and separate incident-monitoring permissions in production.

## 15. Cleanup

Reconnect as chapter06_user with verified TLS and remove the fixture:

```javascript
var lab = db.getSiblingDB("mongodb_enterprise_tutorial_ch06");
if (lab.getName() !== "mongodb_enterprise_tutorial_ch06") {
  throw new Error("Unexpected cleanup namespace");
}
lab.connection_checks.drop();
if (lab.getCollectionNames().includes("connection_checks")) {
  throw new Error("Fixture cleanup failed");
}
print("PASS: Chapter 06 fixture removed");
```

Exit and remove only chapter-owned containers/volumes:

```bash
docker stop --time 30 mongodb-ch06
docker rm --volumes mongodb-ch06
docker volume rm mongodb-ch06-data mongodb-ch06-tls
```

Removing the dedicated data volume removes the lab users as well. From the chapter working directory, remove its generated certificate files:

```bash
rm -- tls/ca.key tls/ca.crt tls/ca.srl tls/server.key tls/server.csr tls/server.crt tls/server.ext tls/server.pem
rmdir tls
```

The CA key has only training value; do not promote it into a production trust chain. If a setup step failed and a file is absent, review and remove only the files actually created.

## 16. Acceptance and review

- [ ] Record Docker, OpenSSL, mongosh and server versions plus image digest.
- [ ] Verify certificate chain, dates and SAN.
- [ ] Start requireTLS with access control enabled.
- [ ] Verify scoped identity and CRUD.
- [ ] Observe plaintext rejection, untrusted-CA failure and wrong-hostname failure.
- [ ] Observe incorrect-password/authSource failure and code 13 role denial.
- [ ] Reconnect with correct verified TLS settings.
- [ ] Verify cleanup.

**Authoring validation:** JavaScript syntax and official TLS guidance reviewed. No Docker/MongoDB runtime was available during authoring; transport and database outcomes remain pending. Record exact versions, operator, date and per-exercise results after execution.

Review questions:

1. Why can TLS succeed while authentication fails?
2. Why is SAN matching necessary when the CA is trusted?
3. What does tlsAllowConnectionsWithoutCertificates mean in this SCRAM lab?
4. Why is directConnection not a universal replica-set repair?
5. Which evidence proves authorization boundaries separately from login?

## Technical references

- [TLS configuration — 8.0](https://www.mongodb.com/docs/v8.0/tutorial/configure-ssl/)
- [mongosh connections](https://www.mongodb.com/docs/mongodb-shell/connect/)
- [Connection strings — 8.0](https://www.mongodb.com/docs/v8.0/reference/connection-string/)
- [mongod TLS options — 8.0](https://www.mongodb.com/docs/v8.0/reference/program/mongod/)
- [connectionStatus — 8.0](https://www.mongodb.com/docs/v8.0/reference/command/connectionStatus/)
- [Localhost exception — 8.0](https://www.mongodb.com/docs/v8.0/core/localhost-exception/)
- [OpenSSL s_client](https://docs.openssl.org/3.0/man1/openssl-s_client/)

Previous: [Chapter 05 — Lab Setup and Version Inventory](05-lab-setup-and-version-inventory.md).  
Next: [Chapter 07 — Databases Collections and Namespaces](07-databases-collections-and-namespaces.md).  
Return to the [master layout](MASTER-LAYOUT.md).
