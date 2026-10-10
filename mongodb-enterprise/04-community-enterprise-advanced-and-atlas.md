# 04 — Community Enterprise Advanced and Atlas

**Status:** Written; static review complete; runtime lab validation pending  
**Part:** 1 — Foundations and Architecture  
**Goal:** Identify the actual server build and topology, and turn deployment requirements into verifiable operational responsibilities.  
**Audience:** Developers, DBREs, SREs, Platform Engineers and Architects  
**Time:** 45–75 minutes  
**Baseline:** MongoDB 8.0 syntax; product and support information reviewed on 2026-10-10. Recheck current product documentation when making a deployment decision.  
**Deployment:** Existing authorized Community, Enterprise or Atlas training deployment. No subscription or cloud provisioning is performed by this lab.

## 1. Separate four decisions

The server edition, commercial offering, hosting model and database topology are related but different decisions.

| Decision | Examples | What it answers |
|---|---|---|
| Server edition | Community or Enterprise Server | Which binary and server capabilities are available? |
| Commercial offering | Enterprise Advanced subscription | Which contractual tools, entitlements and support apply? |
| Hosting model | Self-managed or Atlas | Who operates infrastructure and managed service functions? |
| Topology | Standalone, replica set or sharded cluster | How are availability and data distribution implemented? |

An Enterprise standalone is still a standalone. A Community replica set can exercise replication concepts. An Atlas connection string does not tell you that every Atlas feature is enabled for your project or tier.

## 2. Community Server

Community is useful for core document-database development and compatible labs. You operate the deployment: installation, security, storage, patching, monitoring, backups, failover readiness and recovery testing.

Core CRUD, indexes, aggregation and replica-set behavior can be learned on Community. That does not validate Enterprise-only auditing or the native Enterprise encrypted storage engine.

Do not confuse infrastructure encryption, application encryption and MongoDB native storage-engine encryption. They have different boundaries, keys and operational evidence.

## 3. Enterprise Server and Enterprise Advanced

Enterprise Server adds capabilities to the core database. The track's Enterprise-specific chapters cover features such as auditing and native encryption at rest with version and entitlement checks.

Enterprise Advanced is the commercial offering around Enterprise Server, management tooling and support. A package download, Enterprise build marker or running agent is not evidence that every contract feature is licensed or configured.

For each required feature, verify three things:

1. Is the feature supported on the intended server version and platform?
2. Is the organization entitled to use it in this environment?
3. Is the feature actually enabled and tested?

Ops Manager can automate and monitor supported deployments and provide backup functions when configured. Installing Ops Manager does not prove that backups are running or restorable.

## 4. Atlas and operational ownership

Atlas is MongoDB's managed platform. It changes how infrastructure and database-service administration are delivered. Application teams still need explicit ownership of data modeling, access rules, client behavior, workload tuning, data correctness and recovery acceptance.

Verify each feature against the actual deployment configuration and current service documentation. Treat region, connectivity, backup options, retention and recovery procedures as requirements to confirm, not assumptions inherited from a different project.

| Responsibility | Self-managed baseline | Atlas planning question |
|---|---|---|
| OS and database infrastructure | Your operations team | What does the managed service operate? |
| Network access | Your network/platform team | Which project/network rules and private endpoints apply? |
| Database users and privileges | Your database/security owners | Who owns database access and project access separately? |
| Application pools and retries | Your application team | Are clients configured for the deployed topology? |
| Data modeling and indexes | Your application/data team | How is workload behavior validated? |
| Backup configuration and restore tests | Your recovery owners | Which service options are enabled, and who proves restoration? |
| Cost and capacity | Your owners | Which resources, retention and usage drive the actual bill? |

These rows are an operational planning model. Confirm the precise service boundary rather than treating the table as a contractual responsibility statement.

## 5. Version-sensitive decisions

The 8.0 manual identifies LDAP authentication and authorization as deprecated. A new authentication design should account for the supported alternatives and migration path rather than assume LDAP remains the default long-term choice.

Current Kubernetes documentation identifies MongoDB Controllers for Kubernetes as the successor to the older Enterprise Kubernetes Operator. Record installed operator/CRD versions and review migration guidance before applying manifests. Old examples can remain syntactically recognizable while being inappropriate for a new deployment.

Search and vector capabilities also require product-specific checks; do not infer availability from server edition alone. Some current self-managed capabilities are offered through additional components and entitlements.

This track deliberately keeps the core lab baseline at 8.0. It does not claim 8.0 is the newest release.

## 6. Lab prerequisites

Use an existing training deployment and a dedicated database named **mongodb_enterprise_tutorial_ch04**. You need CRUD, collection creation and cleanup permissions. buildInfo access may be limited by deployment or user permissions; report unavailable evidence honestly.

Connect using the approved training URI. For an existing local server:

```bash
mongosh "mongodb://127.0.0.1:27017"
```

For secured deployments, preserve the approved replica-set/SRV connection format, TLS and authentication settings. Never infer credentials or disable certificate verification just to obtain inventory.

All following JavaScript runs in one mongosh session.

## 7. Collect build and topology evidence

```javascript
var admin = db.getSiblingDB("admin");
var hello = admin.runCommand({ hello: 1 });
if (hello.ok !== 1) throw new Error("Topology inspection failed");

var buildEvidence;
try {
  var build = admin.runCommand({ buildInfo: 1 });
  if (build.ok !== 1) throw new Error("buildInfo command unsuccessful");
  buildEvidence = {
    available: true,
    version: build.version,
    modules: build.modules || []
  };
} catch (e) {
  buildEvidence = {
    available: false,
    reason: "buildInfo unavailable; obtain authorized inventory evidence"
  };
}

function describeTopology(response) {
  if (response.msg === "isdbgrid") return "mongos";
  if (response.setName) return "replica-set-member";
  return "standalone-or-unclassified";
}
var observed = {
  serverVersion: db.version(),
  topology: describeTopology(hello),
  replicaSet: hello.setName || null,
  writable: hello.isWritablePrimary,
  build: buildEvidence
};
printjson(observed);
```

Expected: actual version, topology evidence and either build modules or a clear unavailable status. The Enterprise module marker can support a build classification. Its absence or a restricted command should not be used to infer all managed-service capabilities.

Do not classify hosting from a hostname suffix alone. Managed-service/project inventory and ownership records supply hosting evidence.

## 8. Failure exercise — incomplete classifier

A naive classifier treats edition and hosting as the same thing. Demonstrate a safer distinction with synthetic evidence:

```javascript
function classifyBuild(evidence) {
  if (!evidence.available) return "unknown";
  if (evidence.modules.includes("enterprise")) return "enterprise-build";
  return "no-enterprise-module-reported";
}
function requireHostingInventory(inventory) {
  if (!["self-managed", "atlas"].includes(inventory.hosting)) {
    throw new Error("Hosting must be verified separately from the build");
  }
}
if (classifyBuild({ available: true, modules: ["enterprise"] }) !== "enterprise-build") {
  throw new Error("Enterprise build classification failed");
}
if (classifyBuild({ available: false }) !== "unknown") {
  throw new Error("Restricted evidence must remain unknown");
}
var unknownHostingRejected = false;
try {
  requireHostingInventory({ hosting: "inferred-from-enterprise-module" });
} catch (e) {
  unknownHostingRejected = true;
  print(e.message);
}
if (!unknownHostingRejected) throw new Error("Unverified hosting accepted");
print("PASS: build classification and hosting verification are separate");
```

This exercise validates inventory logic. It does not prove a product entitlement or deploy Atlas.

## 9. Run a common data contract

The core database contract should be independently verified rather than assumed from edition. Create a small synthetic collection:

```javascript
var lab = db.getSiblingDB("mongodb_enterprise_tutorial_ch04");
if (lab.getCollectionNames().includes("capability_checks")) {
  throw new Error("Existing chapter collection; review cleanup first");
}
lab.createCollection("capability_checks");
lab.capability_checks.insertMany([
  { _id: "C1", environment: "training", active: true, value: Int32(10) },
  { _id: "C2", environment: "training", active: true, value: Int32(20) },
  { _id: "C3", environment: "training", active: false, value: Int32(30) }
]);

var result = lab.capability_checks.aggregate([
  { $match: { active: true } },
  { $group: { _id: "$environment", total: { $sum: "$value" }, count: { $sum: 1 } } }
]).toArray();
if (result.length !== 1 || result[0].count !== 2 || result[0].total !== 30) {
  throw new Error("Common aggregation contract failed");
}
printjson(result);
print("PASS: common CRUD and aggregation contract");
```

Expected: training, count 2, total 30. Core success says nothing about audit coverage, encryption keys, backup schedules or commercial support.

## 10. Complete an evidence-based feature inventory

Fill this table from actual environment evidence:

| Requirement | Evidence source | Expected run entry |
|---|---|---|
| Server edition/build | Authorized buildInfo or package inventory | Actual build and version |
| Hosting | Project/platform inventory | Self-managed or Atlas |
| Topology | hello and topology inventory | Standalone, replica set or sharded |
| Entitlement | Approved contract/owner record | Confirmed, unavailable or not required |
| Auditing | Supported configuration and controlled event test | Enabled/tested or not established |
| Encryption at rest | Actual storage/key configuration | Mechanism and key owner |
| Backup | Schedule, retention and backup status | Configured status and latest success |
| Recovery | Isolated restore and reconciliation evidence | Last tested result and RPO/RTO |
| Operator | Installed controller/CRD inventory | Exact versions or not applicable |
| Application access | Driver connection and scoped user | Successful authorized application contract |

“Not established” is an acceptable inventory state; silently converting it to “enabled” is not.

For this lab, the build/topology and common contract rows can be demonstrated. Enterprise feature and recovery rows remain pending unless separate actual evidence is obtained.

## 11. Deployment choice workshop

Use these illustrative requirements to practice decision-making. They are not instructions to purchase or provision a service.

| Scenario | Initial fit to investigate | Evidence that can change the decision |
|---|---|---|
| Local developer needs core CRUD labs | Community training instance | Enterprise-specific feature testing becomes necessary |
| Organization requires self-managed data location and Enterprise auditing | Enterprise deployment with verified entitlement | Platform support, audit design or operational staffing gaps |
| Team wants managed database operations in an approved cloud region | Atlas configuration matching requirements | Network, feature, regulatory or recovery requirements not met |
| Existing Kubernetes Enterprise deployment | Inspect current operator and supported versions | Deprecated controller, CRD or server compatibility issues |

Write a short architecture decision record containing requirements, options considered, selected configuration, explicit assumptions, owners and evidence still needed. Separate convenience from hard requirements.

## 12. Troubleshooting

| Symptom | Evidence | Corrective action |
|---|---|---|
| Enterprise feature absent | Version, platform, entitlement and configuration | Verify all three before changing the binary |
| buildInfo unavailable | Command error and allowed permissions | Use authorized platform inventory and keep build classification unknown |
| Core lab succeeds but audit events are absent | Audit config/filter and controlled event test | Test the Enterprise feature explicitly |
| Agent running but backup unavailable | Backup configuration and status | Configure and validate the backup path |
| Old Kubernetes example fails | Installed CRDs and operator release | Use matching current controller documentation |
| Atlas project access works but database login fails | Database user, auth source and network settings | Treat project identity and database identity separately |
| Recovery assumption fails | Backup retention and restore evidence | Prove a restore before claiming readiness |

## 13. Cleanup and acceptance

```javascript
if (lab.getName() !== "mongodb_enterprise_tutorial_ch04") {
  throw new Error("Unexpected cleanup namespace");
}
lab.capability_checks.drop();
if (lab.getCollectionNames().includes("capability_checks")) {
  throw new Error("Cleanup failed");
}
print("PASS: Chapter 04 collection removed");
```

No deployment, subscription, role or server setting was changed.

- [ ] Record actual server/shell versions and topology.
- [ ] Obtain build evidence or record it as unavailable.
- [ ] Demonstrate the unverified-hosting rejection.
- [ ] Pass the common CRUD/aggregation contract.
- [ ] Complete the feature inventory with actual evidence or explicit pending states.
- [ ] Write the deployment decision record.
- [ ] Verify cleanup.

**Validation record:** JavaScript syntax and official references reviewed; runtime execution pending. Record operator, date, actual versions, outputs and unavailable inspection paths after running.

## 14. Review questions

1. Why is an Enterprise build not proof of an Enterprise Advanced contract?
2. Why does a replica set describe topology rather than hosting?
3. Which responsibilities remain with the application team on a managed platform?
4. Why must auditing and backup recovery be tested separately from CRUD?
5. What current compatibility checks are needed before reusing an old operator manifest?

## Technical references

- [Enterprise Advanced](https://www.mongodb.com/products/self-managed/enterprise-advanced)
- [Enterprise installation — 8.0](https://www.mongodb.com/docs/v8.0/administration/install-enterprise/)
- [Atlas documentation](https://www.mongodb.com/docs/atlas/)
- [buildInfo — 8.0](https://www.mongodb.com/docs/v8.0/reference/command/buildInfo/)
- [LDAP deprecation — 8.0](https://www.mongodb.com/docs/v8.0/core/ldap-deprecation/)
- [MongoDB Controllers for Kubernetes](https://www.mongodb.com/docs/kubernetes/current/)
- [Lifecycle schedules](https://www.mongodb.com/legal/support-policy/lifecycles)

Previous: [Chapter 03 — Server Architecture and WiredTiger](03-server-architecture-and-wiredtiger.md).  
Next: [Chapter 05 — Lab Setup and Version Inventory](05-lab-setup-and-version-inventory.md).  
Return to the [master layout](MASTER-LAYOUT.md).
