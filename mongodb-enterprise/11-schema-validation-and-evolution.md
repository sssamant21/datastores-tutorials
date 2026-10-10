# 11 — Schema Validation and Evolution

**Status:** Written; static review complete; runtime lab validation pending  
**Part:** 2 — Data Modeling and Application Development  
**Goal:** Roll a synthetic collection from a permissive version-1 contract to an enforced version-2 contract with conversion preview, quarantine and a tested lab rollback.  
**Audience:** Developers, Data Engineers, DBREs and SREs  
**Time:** 90–120 minutes  
**Baseline:** MongoDB 8.0/mongosh; record exact versions.  
**Deployment:** Community-compatible or Enterprise training database. No live production backfill or distributed transaction is performed.

## 1. Schema evolution is a compatibility change

A flexible database still has producer and consumer contracts. A new validator can break an old producer even when all existing records remain readable.

Plan the sequence:

1. Inventory existing data and all writers/readers.
2. Define the new contract and a compatibility period.
3. Update writers to produce the new representation.
4. Preview conversions and separate ambiguous records.
5. Backfill in controlled batches with reconciliation.
6. Enforce the new validator after readiness checks.
7. Retain an explicit recovery/rollback strategy.

This lab demonstrates the data-side sequence on four known fixtures. It does not prove a production application rollout.

## 2. Validation settings

| Setting | Behavior | Operational implication |
|---|---|---|
| validationAction error | Reject invalid inserts/updates | Requires compatible writers |
| validationAction warn | Permit invalid writes and log violations | Observability mode, not enforcement |
| validationLevel strict | Validate inserts and updates | Existing invalid records can block updates |
| validationLevel moderate | Validate inserts and updates to existing valid documents | Existing invalid documents have different update treatment |
| required | Require a field to be present | Presence alone does not establish its type |
| bsonType | Constrain BSON type | Date strings remain strings |
| enum / pattern | Constrain allowed values/form | Still does not establish cross-collection foreign keys |

Adding a validator does not automatically scan and convert all existing documents. Query historical compliance separately.

Warnings can include record contents. Use synthetic data for this lab and review log access/redaction requirements before enabling warnings on sensitive production data.

## 3. Lab prerequisites and setup

Use **mongodb_enterprise_tutorial_ch11**. You need createCollection, CRUD, collMod and cleanup privileges. A scoped training user commonly needs readWrite plus suitable database-administration privileges for collMod; do not grant production root merely to run the exercise.

Connect through the verified Chapter 06 pattern and run blocks in one mongosh session.

```javascript
var lab = db.getSiblingDB("mongodb_enterprise_tutorial_ch11");
var names = ["profiles", "rollback_archive", "quarantine"];
if (names.some(name => lab.getCollectionNames().includes(name))) {
  throw new Error("Existing Chapter 11 resources");
}
names.forEach(name => lab.createCollection(name));
function check(ok, message) { if (!ok) throw new Error(message); }

lab.profiles.insertMany([
  { _id: "P1", patientId: "EMP0001", active: true, schemaVersion: Int32(1),
    updatedAt: "2026-10-10T01:00:00Z" },
  { _id: "P2", patientId: "EMP0002", active: true, schemaVersion: Int32(1),
    updatedAt: ISODate("2026-10-10T02:00:00Z") },
  { _id: "P3", patientId: "EMP0003", active: true, schemaVersion: Int32(1),
    updatedAt: "not-a-date" },
  { _id: "P4", patientId: "EMP0004", active: true, schemaVersion: Int32(1) }
]);
lab.rollback_archive.insertMany(lab.profiles.find({}).toArray());
check(lab.rollback_archive.countDocuments({}) === 4, "Expected archived fixture originals");
```

The same-server archive is an exercise rollback aid. It is not a durable disaster-recovery backup.

## 4. Define version-1 and version-2 contracts

```javascript
var v1Validator = {
  $jsonSchema: {
    bsonType: "object",
    required: ["patientId", "schemaVersion"],
    properties: {
      patientId: { bsonType: "string", pattern: "^EMP[0-9]{4}$" },
      active: { bsonType: "bool" },
      schemaVersion: { bsonType: "int", enum: [1] }
    }
  }
};
var v2Validator = {
  $jsonSchema: {
    bsonType: "object",
    required: ["patientId", "active", "schemaVersion", "updatedAt"],
    properties: {
      patientId: { bsonType: "string", pattern: "^EMP[0-9]{4}$" },
      active: { bsonType: "bool" },
      schemaVersion: { bsonType: "int", enum: [2] },
      updatedAt: { bsonType: "date" }
    }
  }
};

function configureValidator(validator, action) {
  var result = lab.runCommand({
    collMod: "profiles",
    validator: validator,
    validationLevel: "strict",
    validationAction: action
  });
  check(result.ok === 1, "Validator configuration failed");
}
configureValidator(v1Validator, "error");
check(lab.profiles.countDocuments({ $nor: [v1Validator] }) === 0,
  "All fixtures should satisfy the intended version-1 contract");
```

v1 deliberately leaves updatedAt unconstrained. v2 requires a BSON date and version 2. Neither validator forbids extra fields or enforces patientId uniqueness; those are separate design decisions.

## 5. Failure exercise — enforce too early

Apply v2 immediately:

```javascript
configureValidator(v2Validator, "error");
check(lab.profiles.countDocuments({}) === 4, "Existing records must not disappear");
check(lab.profiles.countDocuments({ $nor: [v2Validator] }) === 4,
  "Existing version-1 records remain invalid under v2");

var prematureRejected = false;
try {
  lab.profiles.updateOne({ _id: "P2" }, { $set: { active: false } });
} catch (e) {
  prematureRejected = e.code === 121;
  printjson({ code: e.code, details: e.errInfo });
}
check(prematureRejected, "Expected premature enforcement failure");
check(lab.profiles.findOne({ _id: "P2" }).active === true,
  "Rejected update must not alter the fixture");
```

Even P2's valid date does not make its version-1 schemaVersion valid under v2. The update fails because the resulting whole document violates the contract.

## 6. Observation mode and migration preview

Switch the lab to warning mode:

```javascript
configureValidator(v2Validator, "warn");
var warningWrite = lab.profiles.updateOne(
  { _id: "P2" }, { $set: { migrationTouched: true } }
);
check(warningWrite.modifiedCount === 1, "Warn mode should allow the invalid write");
check(lab.profiles.countDocuments({ $nor: [v2Validator] }) === 4,
  "Warning mode must not be mistaken for compliance");
```

With authorized log access, inspect the training server log for the namespace and validation warning near this operation. Record log observation as unavailable if access is restricted. Do not claim the log test passed from the write result alone.

Preview date conversion:

```javascript
var preview = lab.profiles.aggregate([
  { $sort: { _id: 1 } },
  { $project: {
    _id: 1,
    sourceType: { $type: "$updatedAt" },
    converted: {
      $convert: { input: "$updatedAt", to: "date", onError: null, onNull: null }
    }
  } }
]).toArray();
printjson(preview);
check(preview.filter(row => row.converted instanceof Date).length === 2,
  "Expected two convertible fixtures");
check(preview.filter(row => row.converted === null).length === 2,
  "Expected two unresolved fixtures");
```

Expected: P1/P2 convert to dates; P3 is invalid text; P4 is missing. A null conversion result is a sentinel here, not a default business event time. Preserve the source type/reason so missing data and conversion failure are distinguishable.

## 7. Backfill only known convertible records

```javascript
preview.filter(row => row.converted instanceof Date).forEach(row => {
  var result = lab.profiles.updateOne(
    { _id: row._id, schemaVersion: Int32(1) },
    { $set: { updatedAt: row.converted, schemaVersion: Int32(2) } }
  );
  check(result.matchedCount === 1 && result.modifiedCount === 1,
    "Expected one converted fixture: " + row._id);
});
check(lab.profiles.countDocuments(v2Validator) === 2, "Expected two valid v2 records");
```

The version predicate is a small lab guard. A production migration must account for concurrent writers, revisions, source changes, batch limits, resumes and recovery evidence. A preview followed by a write is not an atomic lock on the previewed value.

## 8. Quarantine unresolved fixtures before removal

Copy each known unresolved original with a reason, then remove only the unchanged source shape:

```javascript
preview.filter(row => row.converted === null).forEach(row => {
  var original = lab.profiles.findOne({ _id: row._id });
  check(original !== null && original.schemaVersion === 1, "Expected unresolved v1 fixture");
  lab.quarantine.insertOne({
    _id: original._id,
    reason: row.sourceType === "missing" ? "missing-updatedAt" : "invalid-date",
    source: original
  });

  var guarded = { _id: original._id, schemaVersion: Int32(1) };
  guarded.updatedAt = Object.prototype.hasOwnProperty.call(original, "updatedAt")
    ? original.updatedAt : { $exists: false };
  var removed = lab.profiles.deleteOne(guarded);
  check(removed.deletedCount === 1, "Unresolved source changed before removal");
});
check(lab.quarantine.countDocuments({}) === 2, "Expected two quarantine records");
check(lab.profiles.countDocuments({}) === 2, "Expected two current v2 profiles");
check(lab.profiles.countDocuments({ $nor: [v2Validator] }) === 0,
  "Current collection must now satisfy v2");
```

The copy/delete pair is not a multi-document transaction. A crash between commands requires reconciliation. Production quarantine must have a reviewed business policy, durable evidence, idempotent operations and access/retention controls. This chapter removes only two synthetic fixtures with known originals.

## 9. Enforce after reconciliation

```javascript
configureValidator(v2Validator, "error");
var badInsertRejected = false;
try {
  lab.profiles.insertOne({
    _id: "BAD", patientId: "EMP0099", active: true,
    schemaVersion: Int32(2), updatedAt: "2026-10-10T00:00:00Z"
  });
} catch (e) {
  badInsertRejected = e.code === 121;
}
check(badInsertRejected, "Date string must be rejected under v2");
check(lab.profiles.findOne({ _id: "BAD" }) === null, "Rejected insert must be absent");

lab.profiles.insertOne({
  _id: "P5", patientId: "EMP0005", active: true,
  schemaVersion: Int32(2), updatedAt: ISODate("2026-10-10T05:00:00Z")
});
check(lab.profiles.countDocuments(v2Validator) === 3, "Expected three valid v2 records");
var currentOptions = lab.getCollectionInfos({ name: "profiles" })[0].options;
check(currentOptions.validationAction === "error" &&
  currentOptions.validationLevel === "strict", "Expected enforced validator settings");
print("PASS: v2 conversion, quarantine and enforcement");
```

A passing rejection test verifies one invalid case. A full contract test suite should include missing required fields, disallowed versions, wrong numeric/boolean types and intended optional-field behavior.

## 10. Controlled lab rollback

Rollback can mean application rollback, validator relaxation or data restoration; these are different operations. Here, deliberately restore the known version-1 fixtures on this isolated lab.

```javascript
configureValidator(v1Validator, "error");
lab.profiles.deleteOne({ _id: "P5", schemaVersion: Int32(2) });
lab.rollback_archive.find({}).forEach(original => {
  lab.profiles.replaceOne({ _id: original._id }, original, { upsert: true });
});
check(lab.profiles.countDocuments({}) === 4, "Expected four restored originals");
check(lab.profiles.countDocuments(v1Validator) === 4, "Restored version-1 compliance");
check(lab.profiles.findOne({ _id: "P1" }).updatedAt === "2026-10-10T01:00:00Z",
  "Original date string restored");
check(!("migrationTouched" in lab.profiles.findOne({ _id: "P2" })),
  "Original P2 restored");
check(!("updatedAt" in lab.profiles.findOne({ _id: "P4" })),
  "Original missing field restored");
print("PASS: isolated version-1 fixture rollback");
```

Changing the validator alone did not restore data. The archive did. A production rollback cannot blindly overwrite valid writes made after a migration; it needs version/revision-aware reconciliation and an explicit rollback window.

## 11. Production rollout worksheet

| Check | Required evidence |
|---|---|
| Writers | All producer versions and type contracts |
| Readers | Compatibility with old/new schema versions |
| Existing data | Type distribution and invalid-case inventory |
| Conversion | Dry-run outcomes and ambiguity policy |
| Backfill | Batches, resume state, throttling and reconciliation |
| Enforcement | Zero unresolved records or approved exceptions, compatible producers |
| Recovery | Durable recovery source and post-migration-write policy |
| Monitoring | Validation failures, migration lag, resource impact |
| Quarantine | Owner, retention, access and resolution process |

Moderate validation may be appropriate in some transitions, but it has a different boundary from strict. Test it deliberately rather than using it as a vague “less strict” switch.

## 12. Troubleshooting

| Symptom | Evidence | Action |
|---|---|---|
| Old producer fails after collMod | Code 121 and resulting document contract | Restore a reviewed compatibility mode and update producers |
| New validator installed but old data remains invalid | Explicit compliance query | Inventory/backfill; validator installation is not conversion |
| Warning mode appears successful | Invalid write and log evidence | Treat it as observation, then reconcile and enforce |
| Convert aborts a pipeline | Input type and conversion behavior | Preview with explicit onError/onNull and classify failures |
| Quarantine/source both contain record | Interrupted copy/delete sequence | Reconcile using reviewed state and source-version guards |
| Rollback overwrites new writes | Migration/revision history | Use a durable, concurrency-aware recovery plan |
| collMod unauthorized | Scoped administration privileges | Use approved training access, not blanket production root |

## 13. Cleanup and acceptance

```javascript
check(lab.getName() === "mongodb_enterprise_tutorial_ch11", "Unexpected cleanup database");
names.forEach(name => lab.getCollection(name).drop());
check(!names.some(name => lab.getCollectionNames().includes(name)), "Cleanup failed");
print("PASS: Chapter 11 collections removed");
```

- [ ] Reproduce early-enforcement failure without changing the rejected fixture.
- [ ] Verify warn mode permits a still-invalid write; separately record warning-log evidence.
- [ ] Preview two convertible and two unresolved records.
- [ ] Convert only known valid inputs and quarantine known unresolved fixtures.
- [ ] Verify strict enforcement and valid new inserts.
- [ ] Restore exact original fixture semantics through the lab rollback.
- [ ] Verify cleanup and fill the production rollout worksheet.

**Authoring validation:** JavaScript syntax and official schema/convert references reviewed. Runtime execution pending; record exact versions, operator, date, logs/permissions and assertion outputs after running.

Review questions:

1. Why can an update to an unrelated field fail after a new strict validator?
2. Why is warn mode not proof of schema compliance?
3. Why must null conversion sentinels be classified?
4. What makes the quarantine copy/delete sequence interruptible?
5. Why does a validator rollback not automatically reverse a backfill?

## Technical references

- [Validation actions — 8.0](https://www.mongodb.com/docs/v8.0/core/schema-validation/handle-invalid-documents/)
- [Validation levels — 8.0](https://www.mongodb.com/docs/v8.0/core/schema-validation/specify-validation-level/)
- [Modify validation — 8.0](https://www.mongodb.com/docs/v8.0/core/schema-validation/update-schema-validation/)
- [$jsonSchema — 8.0](https://www.mongodb.com/docs/v8.0/reference/operator/query/jsonSchema/)
- [$convert — 8.0](https://www.mongodb.com/docs/v8.0/reference/operator/aggregation/convert/)
- [collMod — 8.0](https://www.mongodb.com/docs/v8.0/reference/command/collMod/)

Previous: [Chapter 10 — Embedding Versus Referencing](10-embedding-versus-referencing.md).  
Next: **Chapter 12 — Updates Upserts and Bulk Writes** (planned).  
Return to the [master layout](MASTER-LAYOUT.md).
