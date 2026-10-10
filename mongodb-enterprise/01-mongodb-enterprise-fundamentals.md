# 01 — MongoDB Enterprise Fundamentals

**Status:** Written; static review complete; runtime lab validation pending  
**Part:** 1 — Foundations and Architecture  
**Goal:** Understand the document database model and complete a verifiable first lab.  
**Audience:** Developers, Data Engineers, DBREs, SREs and Platform Engineers  
**Time:** 45–60 minutes after an isolated server is available  
**Baseline:** MongoDB 8.0 syntax and mongosh; record exact versions below. Core exercises also apply to a compatible 7.0 server, subject to environment validation.

## 1. What is MongoDB?

MongoDB stores application records as BSON documents grouped into collections. A document can contain scalar fields, embedded documents and arrays. Applications retrieve and change documents through drivers; mongosh is an interactive administration and development client.

A document database still needs a schema design. Different fields can exist in the same collection, but uncontrolled type differences complicate queries, indexes and downstream pipelines. Design around the application's access patterns and introduce validation where needed.

MongoDB Enterprise Server adds capabilities to the core database. For example, Enterprise auditing records configured database events; the Enterprise encrypted storage engine provides native encryption of data files. These capabilities need separate configuration and validation. Installing an Enterprise binary alone does not activate them.

Enterprise Advanced is a commercial offering with management and support capabilities. Atlas is a managed service. A locally operated Enterprise deployment and Atlas have different operational responsibilities; verify product entitlements and deployment-specific capabilities before designing a production system.

## 2. Main components

| Component | Responsibility | What to inspect |
|---|---|---|
| mongod | Database process that serves reads/writes and manages local storage | Version, logs, configuration, storage, health |
| mongos | Router for a sharded deployment | Routing, connectivity and shard metadata |
| mongosh | Client shell | Shell version and connection context |
| Driver | Application integration | Pool limits, timeouts, retries and compatibility |
| WiredTiger | Storage engine | Cache, checkpoints, journal and disk behavior |
| Replica set | Replicated deployment with elections | Member state, lag, write concern and oplog |
| Ops Manager | Management platform where deployed | Agents, automation, monitoring and backup configuration |

A standalone server is useful for a small first lab. It does not validate replica-set failover, change streams or multi-document transactions. Those exercises receive dedicated chapters.

Replication improves availability; it is not a replacement for backups. An accidental deletion can replicate to other members.

## 3. Object hierarchy and BSON

| Relational term | MongoDB concept | Important difference |
|---|---|---|
| Database | Database | Groups collections |
| Table | Collection | Documents may have different fields unless validation restricts them |
| Row | Document | Supports embedded objects and arrays |
| Primary key | _id | Unique identifier with an automatically created index for a normal collection |
| Join | Referencing or aggregation lookup | Model and query cost must be considered |

Example synthetic document:

```javascript
{
  _id: "P001",
  name: "Demo Patient One",
  active: true,
  address: { city: "Austin", state: "TX" },
  tags: ["lab", "synthetic"],
  updatedAt: ISODate("2026-10-10T00:00:00Z")
}
```

BSON supports types beyond JSON, including dates and ObjectId. A date string and a BSON date are different types. A flexible schema does not make those types interchangeable.

Normal BSON documents have a 16 MiB size limit. Large file use cases require a different design, such as GridFS, rather than indefinitely growing an embedded array.

## 4. Operational use case

An application needs to read a patient summary by patientId, update contact information and expose selected changes to an analytics pipeline.

Start by answering:

- Which queries must have predictable latency?
- What is the document growth pattern?
- Which fields need validation and indexes?
- What durability and availability requirements apply?
- How will backup restoration be demonstrated?
- How will MongoDB changes reach Snowflake directly?

This first chapter implements only synthetic CRUD data. CDC and integration are later topics; successful CRUD does not validate pipeline recovery.

## 5. Prerequisites and connection

Use an isolated local server or a dedicated training deployment. You need mongosh and read/write access to **mongodb_enterprise_tutorial_ch01**. Inspection commands such as buildInfo or serverStatus may need additional monitoring permissions.

For an existing authorized TLS deployment, replace the host, username and CA path:

```bash
mongosh "mongodb://TRAINING_HOST:27017/?authSource=admin" --username tutorial_user --password --tls --tlsCAFile /path/to/ca.pem
```

The password is prompted. Do not place it in the URI or paste it into command history. For a replica set use its complete approved connection string; preserve its replicaSet and TLS requirements.

For an existing local server bound to loopback:

```bash
mongosh "mongodb://127.0.0.1:27017"
```

Optional Docker setup for a **Community-compatible core CRUD lab**:

```bash
docker run --name mongodb-ch01 --detach --publish 127.0.0.1:27017:27017 mongo:8.0
docker exec -it mongodb-ch01 mongosh
```

This is an ephemeral, unauthenticated local training container with no persistent volume. Record its image digest and server patch version. It does not test Enterprise features, high availability or a production security configuration. Enterprise learners can instead use an authorized Enterprise training server.

## 6. Record context before changing data

Inside mongosh:

```javascript
db.version()
db.runCommand({ hello: 1 })
db.getSiblingDB("admin").runCommand({ buildInfo: 1 })
db.getName()
```

Record server version, buildInfo modules when authorized, topology information and the connection target. Enterprise builds commonly identify enterprise in modules; inspect the actual build rather than inferring edition from a hostname.

From your operating-system terminal:

```bash
mongosh --version
```

hello shows topology context. A replica-set response contains setName; mongos identifies itself as isdbgrid. A standalone has neither. Some response fields vary with version and permissions.

## 7. Hands-on lab — create synthetic documents

The commands below run **inside mongosh**. Obtain a handle to the dedicated database:

```javascript
var lab = db.getSiblingDB("mongodb_enterprise_tutorial_ch01");
if (lab.getCollectionNames().includes("patients")) {
  throw new Error("Lab collection already exists. Use a fresh lab or review cleanup first.");
}
lab.createCollection("patients");
```

The guard prevents overwriting an earlier exercise. Do not remove it just to make an unknown database pass.

Insert three deterministic records:

```javascript
lab.patients.insertMany([
  {
    _id: "P001", patientId: "EMP001", name: "Demo Patient One",
    active: true, address: { city: "Austin", state: "TX" },
    tags: ["lab", "synthetic"], updatedAt: new Date("2026-10-10T00:00:00Z")
  },
  {
    _id: "P002", patientId: "EMP002", name: "Demo Patient Two",
    active: true, address: { city: "Boston", state: "MA" },
    tags: ["lab", "synthetic"], updatedAt: new Date("2026-10-10T00:00:00Z")
  },
  {
    _id: "P003", patientId: "EMP003", name: "Demo Patient Three",
    active: false, address: { city: "Austin", state: "TX" },
    tags: ["lab", "synthetic"], updatedAt: new Date("2026-10-10T00:00:00Z")
  }
]);
```

Expected: acknowledged true and three inserted identifiers. The _id values make lab output reproducible; production identifier design deserves separate analysis.

## 8. Query, projection and sort

```javascript
lab.patients.find(
  { active: true },
  { _id: 0, patientId: 1, "address.city": 1 }
).sort({ patientId: 1 }).toArray();
```

Expected: EMP001/Austin followed by EMP002/Boston. A filter selects documents, projection selects output fields, and sort determines order.

```javascript
lab.patients.countDocuments({})
lab.patients.countDocuments({ "address.city": "Austin" })
```

Expected: 3 total and 2 in Austin. Dot notation addresses a nested field.

## 9. Update and verify

```javascript
var updateResult = lab.patients.updateOne(
  { _id: "P001" },
  { $set: { "address.city": "Dallas", updatedAt: new Date("2026-10-10T01:00:00Z") } }
);
printjson(updateResult);
lab.patients.findOne({ _id: "P001" });
```

Expected on the first execution: matchedCount 1, modifiedCount 1, city Dallas. Repeating the same update can produce modifiedCount 0 because the values already match. Always distinguish an unmatched filter from a matched document with no change.

The $set operator changes named fields. A replacement operation replaces document content; do not confuse the two when preserving unrelated fields matters.

## 10. Failure exercise — duplicate identifier

```javascript
var duplicateObserved = false;
try {
  lab.patients.insertOne({ _id: "P001", patientId: "DUPLICATE" });
} catch (e) {
  duplicateObserved = e.code === 11000;
  printjson({ code: e.code, message: e.message });
}
if (!duplicateObserved) throw new Error("Expected duplicate key code 11000");
if (lab.patients.countDocuments({}) !== 3) throw new Error("Unexpected document count");
```

Expected: E11000/code 11000 and the collection still has three documents.

Diagnose by identifying the conflicting unique index and key. For an intended change, use an update with the correct filter. For a new entity, use a new identifier. Blind retries of the same duplicate insert will reproduce the failure.

## 11. Delete one record and acceptance assertions

```javascript
var deletion = lab.patients.deleteOne({ _id: "P003" });
if (deletion.deletedCount !== 1) throw new Error("Expected one deleted document");

if (lab.patients.countDocuments({}) !== 2) throw new Error("Expected two remaining documents");
if (lab.patients.countDocuments({ active: true }) !== 2) throw new Error("Expected two active documents");
if (lab.patients.findOne({ _id: "P001" }).address.city !== "Dallas") {
  throw new Error("Update verification failed");
}
if (lab.patients.findOne({ _id: "P003" }) !== null) throw new Error("Delete verification failed");

var indexes = lab.patients.getIndexes();
if (!indexes.some(i => i.name === "_id_" && i.key._id === 1)) {
  throw new Error("Expected identifier index");
}
print("PASS: insert, filter, update, duplicate rejection, delete and identifier index");
```

Capture the PASS line and prior command outputs. These assertions verify the stated data outcomes; they do not prove performance, failover or backup recovery.

## 12. Basic health inspection

If authorized:

```javascript
var health = db.getSiblingDB("admin").runCommand({ serverStatus: 1 });
printjson({
  version: health.version,
  uptime: health.uptime,
  connections: health.connections,
  storageEngine: health.storageEngine
});
```

Connections and uptime provide context; a single snapshot does not establish a performance baseline. Later labs correlate rates, application latency, query evidence and storage metrics over a shared time window.

Do not raise resource limits or restart production solely because an isolated statistic looks large.

## 13. Troubleshooting

| Symptom | Evidence to check | Corrective action |
|---|---|---|
| Connection refused | Target address, listener and service/container status | Correct target or start the intended training server |
| Authentication failed | Username, authentication database and mechanism | Use the authorized account and correct authSource |
| TLS validation fails | CA chain, hostname and certificate validity | Correct the certificate/CA configuration |
| Unauthorized buildInfo/serverStatus | Command and assigned monitoring privileges | Request the scoped monitoring access or record inspection as unavailable |
| E11000 on initial fixture insert | Existing collection and conflicting _id | Review prior lab state; clean only the named training resources |
| matchedCount 0 | Database, collection and exact filter | Correct context or identifier before retrying |
| modifiedCount 0 | Current stored values | Verify whether the desired state already exists |
| No data in another shell | Database context and connection target | Select the same named lab database on the same server |

Do not bypass certificate validation as a routine fix.

## 14. Cleanup

Inside mongosh, remove only this chapter's collection:

```javascript
if (lab.getName() !== "mongodb_enterprise_tutorial_ch01") {
  throw new Error("Unexpected cleanup database");
}
lab.patients.drop();
if (lab.getCollectionNames().includes("patients")) throw new Error("Cleanup failed");
print("PASS: chapter collection removed");
```

The database name may disappear from database listings once it has no collections. No broad dropDatabase is necessary.

If you created the optional disposable Docker container, exit mongosh and run:

```bash
docker stop mongodb-ch01
docker rm mongodb-ch01
```

Remove only the container created for this lab. The exercise is destructive to its synthetic fixtures by design.

## 15. Acceptance checklist and evidence

- [ ] Record server, shell, edition/topology evidence and optional image digest.
- [ ] Confirm the dedicated lab namespace and synthetic data only.
- [ ] Verify three inserts, filtered results and the nested field update.
- [ ] Observe duplicate key code 11000 without increasing the record count.
- [ ] Run the final assertions and capture the PASS line.
- [ ] Verify cleanup and record any permission or version differences.

**Validation record:** Not executed in a MongoDB environment during authoring. Static command and documentation review only. Fill in environment, exact versions, date, operator and results after running the lab.

## 16. Production takeaways and review questions

Keep application connection handling, data modeling, security, availability and recovery as separate responsibilities. Core CRUD working successfully does not show that Enterprise auditing is enabled or a backup can be restored.

1. Why can a collection have flexible fields while still needing a schema design?
2. What is the difference between mongod, mongos and mongosh?
3. Why is modifiedCount 0 not always an error?
4. Why does a standalone CRUD lab fail to prove replica-set resilience?
5. What evidence would demonstrate that an Enterprise-only feature is active?

## Technical references

- [Documents](https://www.mongodb.com/docs/manual/core/document/)
- [BSON types](https://www.mongodb.com/docs/manual/reference/bson-types/)
- [CRUD operations](https://www.mongodb.com/docs/manual/crud/)
- [mongosh connections](https://www.mongodb.com/docs/mongodb-shell/connect/)
- [Enterprise auditing](https://www.mongodb.com/docs/manual/core/auditing/)
- [Encryption at rest](https://www.mongodb.com/docs/manual/core/security-encryption-at-rest/)
- [Replica sets](https://www.mongodb.com/docs/manual/replication/)

Next: **Chapter 02 — Document Model and BSON Types** (planned). Return to the [master layout](MASTER-LAYOUT.md).
