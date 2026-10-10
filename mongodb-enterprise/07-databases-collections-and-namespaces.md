# 07 — Databases Collections and Namespaces

**Status:** Written; static review complete; runtime lab validation pending  
**Part:** 1 — Foundations and Architecture  
**Goal:** Create, inspect and manage named database objects while preventing wrong-namespace changes.  
**Audience:** Developers, Data Engineers, DBREs and SREs  
**Time:** 60–90 minutes  
**Baseline:** MongoDB 8.0 with mongosh; record exact patch versions.  
**Deployment:** Community-compatible or Enterprise training mongod; standalone or replica set. Rename exercises use only normal unsharded lab collections.

## 1. The namespace is part of the operation

A database groups collections. A collection groups documents and has its own options and indexes. A namespace combines the database and collection name, for example:

`mongodb_enterprise_tutorial_ch07.accounts`

The server target matters too. The same namespace may exist on multiple environments. An operation's identity is therefore the deployment, database and object, not just a short collection name.

Most ordinary collection _id indexes enforce identifier uniqueness within that collection. An application identifier existing in another collection does not create a cross-collection uniqueness guarantee.

## 2. Handles, implicit creation and explicit creation

Obtaining a database or collection handle does not itself materialize a stored collection. A first insert can create a missing collection implicitly. This is convenient for learning and dangerous when a misspelled name silently becomes a new collection.

Explicit creation lets you define options before accepting data. Validators, collation and specialized collection types require deliberate design. Some options can be modified through supported commands; others require migration to a new object. Do not assume all settings are mutable.

| Action | What it means |
|---|---|
| getSiblingDB | Obtain a handle to a database without changing the current db variable |
| getCollection | Obtain a handle to an exact collection name |
| createCollection | Explicitly create a collection with intended options |
| insertOne into a missing collection | May materialize a normal collection implicitly |
| getCollectionInfos | Inspect object type, options and metadata |
| drop | Remove an individual named collection/view |
| dropDatabase | Remove an entire database; not needed in this lab |

In a script, use an explicit handle for every change rather than relying on an interactive use command from earlier work.

## 3. Normal collections, views and specialized objects

A standard view is a stored aggregation definition over a source collection or view. It is read-only and evaluates its pipeline when queried. It does not store a separate refreshed copy of the results.

Time-series and capped collections have different creation options and operational behavior. They receive dedicated chapters later. This lab uses normal collections plus one standard view.

A view definition is not an automatic dependency-management system. Renaming/dropping a source or changing its fields can affect view behavior. Review consumers and dependent objects before namespace changes.

## 4. Naming and lifecycle practices

Use short, predictable names with a documented purpose and owner. Database-name restrictions are platform-sensitive; use lowercase letters, digits and underscores for this track's training databases. Avoid personal or sensitive data in object names.

Distinguish lifecycle operations:

- Updating documents changes data within an object.
- Renaming changes a namespace and can affect applications and dependent objects.
- Dropping removes the object and its indexes/options.
- Recreating a collection under the same name creates a new collection identity.

Record a collection UUID when tracking migrations or object replacement; identical names do not prove identical objects.

## 5. Lab prerequisites and connection

Use **mongodb_enterprise_tutorial_ch07** on an authorized training deployment. The account needs collection creation, CRUD, index creation, view creation, same-database rename, object inspection and cleanup permissions. Managed deployments may restrict some commands; record unsupported/unauthorized exercises instead of claiming completion.

For an existing local server:

```bash
mongosh "mongodb://127.0.0.1:27017"
```

Use the verified TLS/prompted-password pattern from Chapter 06 for a secured deployment. Record server and shell versions.

All JavaScript blocks run in order in one mongosh session. No production namespace is accessed.

## 6. Guard setup and inspect handle behavior

```javascript
var labName = "mongodb_enterprise_tutorial_ch07";
var lab = db.getSiblingDB(labName);
var chapterObjects = ["accounts", "accoutns", "implicit_demo",
  "active_accounts", "staging", "staging_verified"];
if (chapterObjects.some(name => lab.getCollectionNames().includes(name))) {
  throw new Error("Existing Chapter 07 resources; review cleanup first");
}

function check(ok, message) {
  if (!ok) throw new Error(message);
}
var initialContext = db.getName();
var unused = lab.getCollection("implicit_demo");
check(db.getName() === initialContext, "Handle must not change current db");
check(!lab.getCollectionNames().includes("implicit_demo"),
  "Handle alone must not create collection");
printjson({ interactiveContext: initialContext, explicitTarget: lab.getName() });
```

Expected: current db unchanged and implicit_demo absent. This proves why script handles are safer than assumptions about an interactive shell's selected database.

## 7. Explicit creation with a basic validator

```javascript
lab.createCollection("accounts", {
  validator: {
    $jsonSchema: {
      bsonType: "object",
      required: ["accountId", "active", "region"],
      properties: {
        accountId: { bsonType: "string" },
        active: { bsonType: "bool" },
        region: { bsonType: "string" }
      }
    }
  },
  validationLevel: "strict",
  validationAction: "error"
});
lab.accounts.createIndex({ accountId: 1 }, { unique: true });

lab.accounts.insertMany([
  { _id: "A1", accountId: "ACC001", active: true, region: "east" },
  { _id: "A2", accountId: "ACC002", active: false, region: "west" },
  { _id: "A3", accountId: "ACC003", active: true, region: "east" }
]);
check(lab.accounts.countDocuments({}) === 3, "Expected three accounts");

var accountInfo = lab.getCollectionInfos({ name: "accounts" });
check(accountInfo.length === 1 && accountInfo[0].type === "collection",
  "Expected normal collection");
check(accountInfo[0].options.validationAction === "error",
  "Expected validation error mode");
printjson({
  name: accountInfo[0].name,
  type: accountInfo[0].type,
  options: accountInfo[0].options,
  uuid: accountInfo[0].info ? accountInfo[0].info.uuid : null
});
```

Expected: three accounts, normal collection metadata and declared validation options. The unique accountId index enforces a rule distinct from schema validation.

If UUID inspection is unavailable due to command options or permissions, record that limitation separately from the data assertions.

## 8. Implicit creation and the typo failure

First demonstrate deliberate implicit creation:

```javascript
lab.implicit_demo.insertOne({ _id: "I1", purpose: "implicit-creation" });
check(lab.getCollectionNames().includes("implicit_demo"),
  "Insert should create the missing normal collection");
```

Now reproduce a misspelled collection write:

```javascript
lab.getCollection("accoutns").insertOne({
  _id: "TYPO1", accountId: "ACC999", active: true, region: "east"
});
check(lab.accounts.countDocuments({}) === 3, "Intended collection must remain unchanged");
check(lab.getCollection("accoutns").countDocuments({}) === 1,
  "Typo created an unintended collection");
print("PASS: namespace typo reproduced");
```

The write may succeed because the intended collection's validator and unique index do not apply to a different name.

Diagnose by inspecting exact object names and the application's target namespace. For this synthetic lab, discard the known typo collection:

```javascript
lab.getCollection("accoutns").drop();
check(!lab.getCollectionNames().includes("accoutns"), "Typo cleanup failed");

var approvedTargets = new Set(["accounts"]);
function approvedCollection(name) {
  if (!approvedTargets.has(name)) throw new Error("Unapproved lab collection: " + name);
  return lab.getCollection(name);
}
var typoBlocked = false;
try {
  approvedCollection("accoutns");
} catch (e) {
  typoBlocked = true;
  print(e.message);
}
check(typoBlocked, "Client guard should reject typo");
check(approvedCollection("accounts").countDocuments({}) === 3,
  "Approved target should be usable");
```

The Set is a training client guard, not a database security policy. Production controls can include scoped collection privileges and a migration process. Unexpected real records require reconciliation and recovery analysis before deleting anything.

## 9. Create a standard view

```javascript
lab.createView("active_accounts", "accounts", [
  { $match: { active: true } },
  { $project: { _id: 0, accountId: 1, region: 1 } }
]);
var visible = lab.active_accounts.find({}).sort({ accountId: 1 }).toArray();
check(JSON.stringify(visible.map(doc => doc.accountId)) ===
  JSON.stringify(["ACC001", "ACC003"]), "View result mismatch");

var viewInfo = lab.getCollectionInfos({ name: "active_accounts" });
check(viewInfo.length === 1 && viewInfo[0].type === "view", "Expected view metadata");
check(viewInfo[0].options.viewOn === "accounts", "Expected accounts source");
printjson(viewInfo);
```

Expected: two active accounts. The view filters and projects at query time. It is not a security boundary unless permissions are also correctly designed, and it is not a materialized copy.

Change the source and verify the view reflects it:

```javascript
var activation = lab.accounts.updateOne({ _id: "A2" }, { $set: { active: true } });
check(activation.modifiedCount === 1, "Expected source update");
check(lab.active_accounts.countDocuments({}) === 3,
  "View must reflect current source data");
```

No manual view refresh is performed.

## 10. Failure exercise — write to a view

```javascript
var viewWriteRejected = false;
try {
  lab.active_accounts.insertOne({ accountId: "ACC004", region: "east" });
} catch (e) {
  viewWriteRejected = e.code === 166;
  printjson({ code: e.code, message: e.message });
}
check(viewWriteRejected, "Expected CommandNotSupportedOnView code 166");
check(lab.accounts.countDocuments({}) === 3,
  "View write must not create a source record");
print("PASS: standard view is read-only");
```

Write to the intended source collection using an approved application operation. A view name in a connection/application setting should not be treated as interchangeable with a writable collection.

## 11. Controlled rename and identity verification

Use an independent scratch collection so the view source remains unchanged:

```javascript
lab.createCollection("staging");
lab.staging.insertOne({ _id: "R1", purpose: "rename-exercise" });
var beforeInfo = lab.getCollectionInfos({ name: "staging" })[0];
var beforeUuid = beforeInfo.info && beforeInfo.info.uuid
  ? beforeInfo.info.uuid.toString() : null;

lab.staging.renameCollection("staging_verified", false);
check(!lab.getCollectionNames().includes("staging"), "Old namespace should be absent");
check(lab.getCollectionNames().includes("staging_verified"), "New namespace should exist");
check(lab.staging_verified.findOne({ _id: "R1" }).purpose === "rename-exercise",
  "Renamed data mismatch");

var afterInfo = lab.getCollectionInfos({ name: "staging_verified" })[0];
var afterUuid = afterInfo.info && afterInfo.info.uuid
  ? afterInfo.info.uuid.toString() : null;
if (beforeUuid !== null && afterUuid !== null) {
  check(beforeUuid === afterUuid, "Same-database rename should preserve collection identity");
}
printjson({ beforeUuid: beforeUuid, afterUuid: afterUuid });
```

false prevents dropping an existing target collection. This lab does not demonstrate cross-database rename or sharded rename; those require their own compatibility and operational review.

Reverse the lab rename:

```javascript
lab.staging_verified.renameCollection("staging", false);
check(lab.staging.countDocuments({}) === 1, "Rename reversal failed");
check(!lab.getCollectionNames().includes("staging_verified"),
  "Reversed target should be absent");
```

This is a lab rollback of the namespace change, not restoration after data deletion. Production rename reviews must include locking/operation effects, change-stream consumers and dependent views or applications.

## 12. Final inventory and assertions

```javascript
var inventory = lab.getCollectionInfos().map(info => ({
  name: info.name,
  type: info.type,
  options: info.options
}));
printjson(inventory);

check(lab.accounts.countDocuments({}) === 3, "Account count");
check(lab.active_accounts.countDocuments({}) === 3, "Current view count");
check(lab.implicit_demo.countDocuments({}) === 1, "Implicit fixture count");
check(lab.staging.countDocuments({}) === 1, "Rename fixture count");
check(lab.accounts.getIndexes().some(index =>
  index.name === "accountId_1" && index.unique === true), "Unique accountId index");
check(typoBlocked && viewWriteRejected, "Failure exercises not observed");
print("PASS: namespaces, implicit/explicit creation, views, typo guard and reversible rename");
```

The inventory may include system metadata such as system.views. Cleanup below removes only the user objects created by this lab.

## 13. Troubleshooting

| Symptom | Evidence | Action |
|---|---|---|
| “Database missing” after obtaining a handle | Collection list and actual writes | Distinguish a handle from materialized data |
| Successful write but intended data unchanged | Deployment/database/exact collection | Inspect for a misspelled namespace |
| Validator seems ignored | Target namespace and collection options | Verify the actual collection, not a similar name |
| View appears stale | Source data, view pipeline and target deployment | Verify the current source and query context |
| View write fails | Object type and code 166 | Use the approved source collection |
| Rename fails | Existing target, permissions and topology | Preserve target data and review supported rename conditions |
| Same name has a different UUID | Drop/recreate or migration history | Track object identity and consumers |
| Collection absent after drop | Cleanup/migration record | Restore through the appropriate recovery path if unintended |

## 14. Production considerations

Names should have owners, lifecycle rules and an approved migration path. A collection rename is not a transparent alias switch for every consumer. Test application queries, views, automation, backups and CDC behavior.

Recreating a collection also means reviewing indexes, validators, collation and access controls. Copying documents alone does not recreate the full operational object.

Maintain a namespace inventory with environment, database, object type, collection identity where available, owner, retention, dependencies and restore requirements. Avoid embedding patient identifiers or other sensitive values in namespace names.

## 15. Cleanup and acceptance

```javascript
check(lab.getName() === "mongodb_enterprise_tutorial_ch07",
  "Unexpected cleanup database");
["active_accounts", "accounts", "implicit_demo", "staging",
  "staging_verified", "accoutns"].forEach(name => {
  lab.getCollection(name).drop();
});
check(!["active_accounts", "accounts", "implicit_demo", "staging",
  "staging_verified", "accoutns"].some(name =>
    lab.getCollectionNames().includes(name)), "Cleanup failed");
print("PASS: Chapter 07 user objects removed");
```

Drop the view before its source. No dropDatabase or broad system-collection deletion is required.

- [ ] Record exact server/shell and deployment identity.
- [ ] Confirm a handle alone does not create a collection or change db.
- [ ] Inspect explicit validator/index metadata.
- [ ] Reproduce the typo, clean its known fixture and verify the guard.
- [ ] Verify the view before/after its source update and observe write rejection.
- [ ] Rename/reverse the scratch collection and inspect identity.
- [ ] Capture final assertions and cleanup.

**Authoring validation:** JavaScript syntax and official object-management references reviewed. Runtime execution is pending; record environment, date, operator, actual outputs and any restricted metadata fields after running.

## 16. Review questions

1. Why can a typo create a new collection instead of failing?
2. Why is a view not a separate refreshed data copy?
3. What must be checked before renaming a collection?
4. Why does recreating a name not prove object identity is preserved?
5. How do validators, indexes and collection privileges serve different purposes?

## Technical references

- [Databases and collections — 8.0](https://www.mongodb.com/docs/v8.0/core/databases-and-collections/)
- [Views — 8.0](https://www.mongodb.com/docs/v8.0/core/views/)
- [listCollections — 8.0](https://www.mongodb.com/docs/v8.0/reference/command/listCollections/)
- [createCollection — 8.0](https://www.mongodb.com/docs/v8.0/reference/method/db.createCollection/)
- [renameCollection — 8.0](https://www.mongodb.com/docs/v8.0/reference/method/db.collection.renameCollection/)
- [Limits and naming restrictions — 8.0](https://www.mongodb.com/docs/v8.0/reference/limits/)

Previous: [Chapter 06 — mongosh Connections TLS and Authentication](06-mongosh-connections-tls-and-authentication.md).  
Next: **Chapter 08 — CRUD Filters Projections and Sorting** (planned).  
Return to the [master layout](MASTER-LAYOUT.md).
