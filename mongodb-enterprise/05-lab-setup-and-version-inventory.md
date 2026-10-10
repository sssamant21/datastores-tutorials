# 05 — Lab Setup and Version Inventory

**Status:** Written; static review complete; runtime lab validation pending  
**Part:** 1 — Foundations and Architecture  
**Goal:** Build an authenticated, persistent local training server and record an exact compatibility inventory.  
**Audience:** Developers, DBREs, SREs and Platform Engineers  
**Time:** 60–90 minutes  
**Baseline:** MongoDB 8.0 Docker image; record the resolved digest and patch version. Docker Desktop on Windows with Linux containers or Docker Engine on Linux.  
**Deployment:** Community-compatible standalone lab. Enterprise learners may use an authorized Enterprise training deployment instead. No HA, sharding or Enterprise-only capability is validated.

## 1. A reproducible lab has an identity

A useful lab records more than “MongoDB 8.” Capture server patch version, image digest, shell version, database tools, driver version, feature compatibility version, topology and resource configuration.

The server binary version and feature compatibility version (FCV) are different. FCV controls version-dependent feature behavior; it is not an instruction to change the installed binary. Inspect it here without modifying it.

A mutable image tag such as mongo:8.0 is convenient for initial setup, but it can resolve to a different patch later. Record the resolved image and use an approved digest when reproducibility requires an identical image.

## 2. Resource plan

| Resource | Chapter value | Purpose |
|---|---|---|
| Container | mongodb-ch05 | Dedicated process identity |
| Host endpoint | 127.0.0.1:27035 | Localhost-only published training port |
| Named volume | mongodb-ch05-data | Data retained across container replacement |
| Database | mongodb_enterprise_tutorial_ch05 | Synthetic fixtures |
| Bootstrap account | lab_admin in admin | Training administration |
| Application account | chapter05_user in lab database | Scoped read/write work |
| Memory limit | 2 GiB | Bounded local footprint |
| WiredTiger cache | 0.5 GiB | Leave headroom for other memory consumers |

The container also needs CPU and available disk space. These values are a small lab configuration, not a production capacity plan.

Authentication and TLS solve different problems. This chapter enables authentication on a loopback-only local lab. Chapter 06 covers TLS for remote connections; do not expose this lab as a remote database service.

## 3. Prerequisites

- Docker available and running; on Windows, use Linux containers.
- Port 27035 and the resource names above are unused.
- Space for the image and a small persistent volume.
- A secure place to retain the two training passwords until cleanup.
- mongosh available inside the container; a host installation is optional.

Terminal commands below are one-line Docker commands that work in typical Bash and PowerShell sessions. mongosh JavaScript runs only inside the database shell.

Check Docker:

```bash
docker version
docker info
docker ps --all --filter name=mongodb-ch05
docker volume ls --filter name=mongodb-ch05-data
```

Review the exact names in the output. If either resource already exists, stop setup and identify its owner/state. Do not overwrite or remove an unknown resource.

## 4. Create the server with persistent data and access control

```bash
docker pull mongo:8.0
docker volume create mongodb-ch05-data
docker run --name mongodb-ch05 --detach --publish 127.0.0.1:27035:27017 --memory 2g --mount source=mongodb-ch05-data,target=/data/db mongo:8.0 --auth --wiredTigerCacheSizeGB 0.5
docker logs --tail 50 mongodb-ch05
```

Expected: running container, named volume and a startup log showing a listener. If startup is still in progress, recheck the logs and container status; a successful docker run alone does not prove database readiness.

No root-password environment variable is used. Credentials are entered interactively during bootstrap.

## 5. Bootstrap the first administrative account

The localhost exception applies only while no users or roles exist. Connect through loopback **inside the new container**, not through the published host port:

```bash
docker exec -it mongodb-ch05 mongosh --host 127.0.0.1 --port 27017
```

Inside mongosh:

```javascript
var admin = db.getSiblingDB("admin");
admin.createUser({
  user: "lab_admin",
  pwd: passwordPrompt(),
  roles: [{ role: "root", db: "admin" }]
});
```

Enter a unique training password at the prompt. The root role is used only for administration of this disposable server. Applications will use the scoped account below.

Creating the first user ends the exception. Exit mongosh and reconnect with authentication:

```bash
docker exec -it mongodb-ch05 mongosh "mongodb://127.0.0.1:27017/admin?authSource=admin" --username lab_admin --password
```

The password is prompted. If bootstrap fails because users already exist, treat the volume as existing state; do not attempt to regain access by disabling authentication.

## 6. Inventory exact server and compatibility state

As lab_admin:

```javascript
var admin = db.getSiblingDB("admin");
var build = admin.runCommand({ buildInfo: 1 });
var hello = admin.runCommand({ hello: 1 });
var fcv = admin.runCommand({ getParameter: 1, featureCompatibilityVersion: 1 });
var opts = admin.runCommand({ getCmdLineOpts: 1 });

if (build.ok !== 1 || hello.ok !== 1 || fcv.ok !== 1 || opts.ok !== 1) {
  throw new Error("Inventory commands failed");
}
printjson({
  serverVersion: build.version,
  modules: build.modules,
  topology: hello.setName ? "replica-set" : (hello.msg === "isdbgrid" ? "mongos" : "standalone"),
  fcv: fcv.featureCompatibilityVersion,
  configuredStorage: opts.parsed.storage,
  authorization: opts.parsed.security
});
if (!build.version.startsWith("8.0.")) {
  throw new Error("Expected the selected 8.0 server baseline");
}
```

Expected: 8.0 patch version, standalone topology, FCV evidence and authorization enabled. Record the actual FCV response; do not set FCV as part of this chapter.

In another terminal:

```bash
docker exec mongodb-ch05 mongosh --version
docker inspect mongodb-ch05 --format '{{.Image}}'
docker inspect mongodb-ch05 --format '{{.HostConfig.Memory}}'
docker inspect mongodb-ch05 --format '{{json .Mounts}}'
docker image inspect mongo:8.0 --format '{{json .RepoDigests}}'
```

Record image ID and repository digest. The memory limit should be 2147483648 bytes, and /data/db should map to mongodb-ch05-data.

If database tools are required later, inventory them separately:

```bash
mongodump --version
mongorestore --version
mongoexport --version
mongoimport --version
```

These commands run on the host where the tools are installed. A “command not found” is a missing-tool result, not a server failure. Install supported versions from the official tools documentation when the relevant lab requires them. Tool release numbers need not match server release numbers.

## 7. Create a scoped application account

Still in the authenticated lab_admin shell:

```javascript
var training = db.getSiblingDB("mongodb_enterprise_tutorial_ch05");
if (training.getUser("chapter05_user") !== null) {
  throw new Error("Existing chapter application user; inspect before proceeding");
}
training.createUser({
  user: "chapter05_user",
  pwd: passwordPrompt(),
  roles: [{ role: "readWrite", db: "mongodb_enterprise_tutorial_ch05" }]
});
```

Choose a different password from the administrative account. Exit the shell and connect as the scoped user:

```bash
docker exec -it mongodb-ch05 mongosh "mongodb://127.0.0.1:27017/mongodb_enterprise_tutorial_ch05?authSource=mongodb_enterprise_tutorial_ch05" --username chapter05_user --password
```

The user belongs to the training database, so authSource is the training database. Selecting admin as authSource would search a different user namespace.

## 8. Application contract and negative permission test

Inside the scoped-user session:

```javascript
var lab = db.getSiblingDB("mongodb_enterprise_tutorial_ch05");
if (lab.getCollectionNames().includes("setup_checks")) {
  throw new Error("Existing setup_checks collection");
}
lab.createCollection("setup_checks");
lab.setup_checks.insertOne({
  _id: "persistent-marker",
  purpose: "chapter05",
  version: Int32(1),
  createdAt: ISODate("2026-10-10T00:00:00Z")
});
if (lab.setup_checks.findOne({ _id: "persistent-marker" }).version !== 1) {
  throw new Error("Application read/write contract failed");
}

var adminReadDenied = false;
try {
  var response = db.getSiblingDB("admin").runCommand({ usersInfo: 1 });
  adminReadDenied = response.ok !== 1 && response.code === 13;
} catch (e) {
  adminReadDenied = e.code === 13;
}
if (!adminReadDenied) throw new Error("Expected unauthorized administrative user inventory");
print("PASS: scoped CRUD succeeds and administrative user inventory is denied");
```

Expected: CRUD succeeds; usersInfo in admin is denied with code 13. The test verifies the intended boundary without attempting to access another application's data.

## 9. Failure exercise — wrong authentication source

Exit the shell and intentionally connect using the wrong authSource:

```bash
docker exec -it mongodb-ch05 mongosh "mongodb://127.0.0.1:27017/mongodb_enterprise_tutorial_ch05?authSource=admin" --username chapter05_user --password
```

Enter the correct chapter05_user password. Expected: authentication failure because this user was created in the training database, not admin.

Correct only the authSource and reconnect with the URI from Section 7. The error is not fixed by granting root or disabling access control.

## 10. Prove persistence across container replacement

This is a local lab-only exercise. The named volume remains attached to the same logical server data. It is not a backup and must not be mounted by two active mongod processes.

Exit mongosh. Stop and remove only the chapter container:

```bash
docker stop --time 30 mongodb-ch05
docker rm mongodb-ch05
```

Recreate it with the retained volume. For reproducibility, use the previously recorded repository digest instead of the mutable tag when needed; substitute the actual digest value, never a guessed one.

```bash
docker run --name mongodb-ch05 --detach --publish 127.0.0.1:27035:27017 --memory 2g --mount source=mongodb-ch05-data,target=/data/db mongo:8.0 --auth --wiredTigerCacheSizeGB 0.5
docker logs --tail 50 mongodb-ch05
docker exec -it mongodb-ch05 mongosh "mongodb://127.0.0.1:27017/mongodb_enterprise_tutorial_ch05?authSource=mongodb_enterprise_tutorial_ch05" --username chapter05_user --password
```

The first-user bootstrap is not repeated. Existing users and documents come from the retained volume.

Inside mongosh:

```javascript
var lab = db.getSiblingDB("mongodb_enterprise_tutorial_ch05");
var marker = lab.setup_checks.findOne({ _id: "persistent-marker" });
if (!marker || marker.purpose !== "chapter05") {
  throw new Error("Persistence marker missing");
}
if (lab.setup_checks.countDocuments({}) !== 1) {
  throw new Error("Unexpected fixture count after replacement");
}
print("PASS: authenticated user and marker survive container replacement");
```

A retained volume protects against this specific container replacement, not volume deletion, host loss or accidental database deletion. Recovery chapters demonstrate backups and isolated restore.

## 11. Version inventory worksheet

| Component | Actual value | Evidence |
|---|---|---|
| Server | Fill exact patch | buildInfo |
| FCV | Fill response | getParameter |
| Edition/modules | Fill response | buildInfo |
| mongosh | Fill version | mongosh --version |
| Image | Fill ID/digest | Docker inspection |
| Memory/cache | Fill actual values | Docker limit and serverStatus |
| Database tools | Versions or unavailable | Tool --version output |
| Application driver | Language/package version or not installed | Dependency lockfile |
| Ops Manager | Version or not applicable | Management inventory |
| Kubernetes operator/CRDs | Versions or not applicable | Controller and CRD inventory |

For each actual combination, verify the applicable official compatibility table. “Newest” is not a substitute for supported compatibility, and a single successful CRUD query does not validate every driver/server feature.

Do not copy database passwords into this worksheet.

## 12. Troubleshooting

| Symptom | Evidence | Action |
|---|---|---|
| Port bind error | Existing container/listener | Select a reviewed free lab port and update the URI |
| Docker cannot start Linux image | Docker engine/container mode | Enable the supported Linux-container environment |
| First user cannot be created | Existing volume/user state | Identify previous state and use its authorized admin access |
| Application login fails | User database and authSource | Match the authentication database to user creation |
| CRUD unauthorized | connectionStatus and role assignment | Connect with the scoped account and inspect its intended roles |
| Marker lost after replacement | Mount source and namespace | Reattach the correct retained volume |
| Process killed under memory pressure | Docker status and logs | Reassess lab memory/cpu/storage constraints |
| Tool unavailable | Host binary version check | Install the supported tool before its dependent lab |
| FCV inspection unauthorized on a managed deployment | Permission/service boundary | Obtain approved inventory; do not modify FCV |

## 13. Cleanup

If retaining the local server for your own continued study, explicitly record it as retained and keep its credentials secure. For a complete chapter cleanup, first connect as the scoped user and remove the fixture:

```javascript
var lab = db.getSiblingDB("mongodb_enterprise_tutorial_ch05");
if (lab.getName() !== "mongodb_enterprise_tutorial_ch05") {
  throw new Error("Unexpected cleanup database");
}
lab.setup_checks.drop();
if (lab.getCollectionNames().includes("setup_checks")) {
  throw new Error("Fixture cleanup failed");
}
print("PASS: fixture removed");
```

Then exit and connect as lab_admin:

```bash
docker exec -it mongodb-ch05 mongosh "mongodb://127.0.0.1:27017/admin?authSource=admin" --username lab_admin --password
```

Remove the scoped user:

```javascript
var training = db.getSiblingDB("mongodb_enterprise_tutorial_ch05");
training.dropUser("chapter05_user");
if (training.getUser("chapter05_user") !== null) {
  throw new Error("Application user cleanup failed");
}
print("PASS: scoped user removed");
```

Exit, then remove only the chapter's container and volume:

```bash
docker stop --time 30 mongodb-ch05
docker rm mongodb-ch05
docker volume rm mongodb-ch05-data
```

Volume removal deletes this lab's database data and bootstrap user. Never use broad Docker prune as chapter cleanup.

## 14. Acceptance and review

- [ ] Record exact server, FCV, shell, image and resource inventory.
- [ ] Bootstrap access control only on the new dedicated server.
- [ ] Verify scoped CRUD and code 13 administrative denial.
- [ ] Reproduce and correct the authSource failure.
- [ ] Verify user and fixture persistence across replacement.
- [ ] Distinguish retained-volume persistence from backup recovery.
- [ ] Complete cleanup or explicitly record retained resources.

**Authoring validation:** JavaScript syntax and documented workflow reviewed. Docker/mongosh/server execution was unavailable during authoring; runtime results remain pending. Record operator, date, actual versions and outputs after running.

Review questions:

1. Why does creating the first user change the bootstrap access path?
2. Why must authSource match the user's database?
3. Why can FCV differ conceptually from the installed server version?
4. Why is a persistent volume not a backup?
5. Which component versions belong in a reproducibility record?

## Technical references

- [Localhost exception — 8.0](https://www.mongodb.com/docs/v8.0/core/localhost-exception/)
- [Enable access control — 8.0](https://www.mongodb.com/docs/v8.0/tutorial/enable-authentication/)
- [Create users — 8.0](https://www.mongodb.com/docs/v8.0/tutorial/create-users/)
- [getParameter — 8.0](https://www.mongodb.com/docs/v8.0/reference/command/getParameter/)
- [Database Tools](https://www.mongodb.com/docs/database-tools/)
- [Driver compatibility](https://www.mongodb.com/docs/drivers/compatibility/)
- [mongosh installation](https://www.mongodb.com/docs/mongodb-shell/install/)
- [Docker volumes](https://docs.docker.com/engine/storage/volumes/)

Previous: [Chapter 04 — Community Enterprise Advanced and Atlas](04-community-enterprise-advanced-and-atlas.md).  
Next: [Chapter 06 — mongosh Connections TLS and Authentication](06-mongosh-connections-tls-and-authentication.md).  
Return to the [master layout](MASTER-LAYOUT.md).
