# 09 — Nested Documents and Arrays

**Status:** Written; static review complete; runtime lab validation pending  
**Part:** 2 — Data Modeling and Application Development  
**Goal:** Read and update embedded structures without losing sibling fields or modifying the wrong array elements.  
**Audience:** Developers, Data Engineers, DBREs and SREs  
**Time:** 75–105 minutes  
**Baseline:** MongoDB 8.0 with mongosh; record exact server/shell versions.  
**Deployment:** Community-compatible or Enterprise standalone/replica set. All updates are single-document operations.

## 1. Embedded structures describe related data

An embedded object is a named structure within a document. An array is an ordered sequence that can contain scalars or objects. These shapes are useful when related information is normally read together, but they need type, cardinality and update rules.

For a synthetic profile, contact is one object, tags is an array of strings, addresses is an array of objects with stable addressId values, and recentEvents is a bounded summary.

| Structure | Access pattern | Design requirement |
|---|---|---|
| contact.preferences | Update one preference | Preserve other contact fields |
| tags | Add a scalar if absent | Decide whether duplicates/order matter |
| addresses | Change one address by identity | Stable element identifier and precise filter |
| recentEvents | Return a small recent summary | Defined bound and a durable history source elsewhere |

An array position is not a business identifier. Deleting or reordering elements changes positions. Use an element identifier when the application needs to update a particular entity.

## 2. Operator map

| Operation | Operator | Important boundary |
|---|---|---|
| Set one nested field | $set with dot notation | Replaces the named field, not all sibling fields |
| Replace an embedded object | $set of object field | Omits previous child fields not supplied |
| Add an array element | $push | Can append duplicates |
| Add a value only if absent | $addToSet | Does not clean existing duplicates or guarantee sorted order |
| Remove matching elements | $pull | Removes matching values/elements |
| Update first query-matched element | $ | Requires the array match in the query |
| Update all elements | $[] | Broad within the matched document |
| Update selected elements | $[identifier] with arrayFilters | Explicit per-element predicate |

The query $elemMatch operator chooses a document with an element satisfying all conditions. arrayFilters chooses which elements an update modifies. These are separate parts of the operation.

## 3. Lab setup

Connect to an authorized training deployment using the verified Chapter 06 pattern. The account needs collection creation, CRUD and cleanup in **mongodb_enterprise_tutorial_ch09**. Run all JavaScript in one session.

```javascript
var lab = db.getSiblingDB("mongodb_enterprise_tutorial_ch09");
if (lab.getCollectionNames().includes("profiles")) {
  throw new Error("Existing Chapter 09 collection");
}
lab.createCollection("profiles");

function check(ok, message) {
  if (!ok) throw new Error(message);
}
lab.profiles.insertMany([
  {
    _id: "P1",
    contact: {
      email: "demo@example.invalid",
      phone: "000-000-0000",
      preferences: { sms: false, email: true }
    },
    tags: ["lab", "synthetic"],
    addresses: [
      { addressId: "A1", kind: "home", city: "Austin", active: true },
      { addressId: "A2", kind: "work", city: "Boston", active: false }
    ],
    recentEvents: [
      { eventId: "E1", at: ISODate("2026-10-10T01:00:00Z") }
    ]
  },
  {
    _id: "P2",
    contact: { email: "second@example.invalid", preferences: { sms: false, email: true } },
    tags: ["lab"],
    addresses: [
      { addressId: "A3", kind: "home", city: "Boston", active: true }
    ],
    recentEvents: []
  }
]);
check(lab.profiles.countDocuments({}) === 2, "Expected two profiles");
```

These are synthetic addresses and contact details. No real patient data is used.

## 4. Dot notation and sibling preservation

```javascript
var preferenceChange = lab.profiles.updateOne(
  { _id: "P1" }, { $set: { "contact.preferences.sms": true } }
);
check(preferenceChange.modifiedCount === 1, "Expected preference change");
var profile = lab.profiles.findOne({ _id: "P1" });
check(profile.contact.preferences.sms === true, "SMS flag");
check(profile.contact.preferences.email === true, "Sibling preference preserved");
check(profile.contact.email === "demo@example.invalid", "Contact email preserved");

var savedContact = profile.contact;
lab.profiles.updateOne(
  { _id: "P1" }, { $set: { contact: { preferences: { sms: false } } } }
);
var replaced = lab.profiles.findOne({ _id: "P1" });
check(!("email" in replaced.contact), "Object replacement should omit old email");
check(!("phone" in replaced.contact), "Object replacement should omit old phone");

lab.profiles.updateOne({ _id: "P1" }, { $set: { contact: savedContact } });
check(lab.profiles.findOne({ _id: "P1" }).contact.email === "demo@example.invalid",
  "Synthetic object restoration failed");
```

The second update replaces the whole contact object. It is deliberately reversed using a saved synthetic value in this session. That value is not a durable backup.

Use dot notation when changing one child. Use whole-object replacement only when the complete new object is intentional.

## 5. Match the same address element

```javascript
var loose = lab.profiles.find({
  "addresses.kind": "home", "addresses.city": "Boston"
}, { _id: 1 }).sort({ _id: 1 }).toArray();
var precise = lab.profiles.find({
  addresses: { $elemMatch: { kind: "home", city: "Boston" } }
}, { _id: 1 }).sort({ _id: 1 }).toArray();

check(JSON.stringify(loose.map(d => d._id)) === JSON.stringify(["P1", "P2"]),
  "Expected independent-element match");
check(JSON.stringify(precise.map(d => d._id)) === JSON.stringify(["P2"]),
  "Expected same-element match");
```

P1 has a home address in Austin and a work address in Boston. Only P2 has a single address satisfying both requested conditions.

Avoid treating a successful broad query as evidence that its business semantics are correct.

## 6. Update one identified element with $

```javascript
var addressUpdate = lab.profiles.updateOne(
  { _id: "P1", "addresses.addressId": "A1" },
  { $set: { "addresses.$.city": "Dallas" } }
);
check(addressUpdate.matchedCount === 1 && addressUpdate.modifiedCount === 1,
  "Expected one identified address update");

var addresses = lab.profiles.findOne({ _id: "P1" }).addresses;
check(addresses.find(a => a.addressId === "A1").city === "Dallas", "A1 changed");
check(addresses.find(a => a.addressId === "A2").city === "Boston", "A2 preserved");
```

The positional placeholder refers to the first matching array element. This contract assumes addressId is unique within the array; ordinary collection _id uniqueness does not enforce that assumption for array elements.

Do not use this positional pattern as a generic upsert when the array may not exist. For multiple arrays or more complex targeting, use explicit filtered positional updates where supported.

## 7. Filtered updates and all-element updates

Mark only the inactive work address as reviewed:

```javascript
var filtered = lab.profiles.updateOne(
  { _id: "P1" },
  { $set: { "addresses.$[addr].reviewed": true } },
  { arrayFilters: [{ "addr.kind": "work", "addr.active": false }] }
);
check(filtered.modifiedCount === 1, "Expected inactive work address modification");
var afterFiltered = lab.profiles.findOne({ _id: "P1" }).addresses;
check(afterFiltered.find(a => a.addressId === "A2").reviewed === true,
  "Selected element changed");
check(!("reviewed" in afterFiltered.find(a => a.addressId === "A1")),
  "Unselected element preserved");

lab.profiles.updateOne(
  { _id: "P1" }, { $set: { "addresses.$[].schemaVersion": Int32(1) } }
);
check(lab.profiles.findOne({ _id: "P1" }).addresses.every(a => a.schemaVersion === 1),
  "All elements should have schemaVersion");
```

modifiedCount counts changed documents, not the number of array elements. A document may match while no element meets an arrayFilter, giving modifiedCount zero.

Demonstrate that distinction:

```javascript
var noElement = lab.profiles.updateOne(
  { _id: "P1" },
  { $set: { "addresses.$[addr].reviewed": true } },
  { arrayFilters: [{ "addr.addressId": "DOES-NOT-EXIST" }] }
);
check(noElement.matchedCount === 1 && noElement.modifiedCount === 0,
  "Document matched but no array element changed");
```

Inspect both the document filter and the element filter when diagnosing an unchanged update.

## 8. Duplicate arrays and set-like additions

```javascript
lab.profiles.updateOne({ _id: "P1" }, { $push: { tags: "lab" } });
check(lab.profiles.findOne({ _id: "P1" }).tags.filter(t => t === "lab").length === 2,
  "Push should append a duplicate");

var setAdd = lab.profiles.updateOne(
  { _id: "P1" }, { $addToSet: { tags: "lab" } }
);
check(setAdd.modifiedCount === 0, "Existing value must not be added again");
check(lab.profiles.findOne({ _id: "P1" }).tags.filter(t => t === "lab").length === 2,
  "addToSet must not remove existing duplicates");

lab.profiles.updateOne({ _id: "P1" }, { $pull: { tags: "lab" } });
check(!lab.profiles.findOne({ _id: "P1" }).tags.includes("lab"),
  "Pull should remove all matching lab values");
lab.profiles.updateOne(
  { _id: "P1" }, { $addToSet: { tags: { $each: ["lab", "reviewed"] } } }
);
var tags = lab.profiles.findOne({ _id: "P1" }).tags;
check(tags.filter(t => t === "lab").length === 1 && tags.includes("reviewed"),
  "Controlled scalar tag additions");
```

For embedded object values, addToSet duplicate comparison includes the object's complete value and field order. It does not enforce a business key such as addressId. Use a deliberate key-based update contract for object arrays.

## 9. Maintain a bounded recent summary

Add four events, sort newest first and retain only three:

```javascript
lab.profiles.updateOne({ _id: "P1" }, {
  $push: {
    recentEvents: {
      $each: [
        { eventId: "E2", at: ISODate("2026-10-10T02:00:00Z") },
        { eventId: "E3", at: ISODate("2026-10-10T03:00:00Z") },
        { eventId: "E4", at: ISODate("2026-10-10T04:00:00Z") },
        { eventId: "E5", at: ISODate("2026-10-10T05:00:00Z") }
      ],
      $sort: { at: -1, eventId: 1 },
      $slice: 3
    }
  }
});
var recent = lab.profiles.findOne({ _id: "P1" }).recentEvents;
check(JSON.stringify(recent.map(e => e.eventId)) ===
  JSON.stringify(["E5", "E4", "E3"]), "Expected newest three events");
```

The bound applies to updates following this contract; another writer could bypass it. The two older events are removed from this summary. If full history is required, preserve it in a separately designed durable collection before applying summary retention.

A bounded display summary is not an audit log or backup. Do not use slicing to discard the only copy of required business history.

## 10. Remove an identified inactive address

```javascript
var removed = lab.profiles.updateOne(
  { _id: "P1" },
  { $pull: { addresses: { addressId: "A2", active: false } } }
);
check(removed.modifiedCount === 1, "Expected inactive address removal");
var retained = lab.profiles.findOne({ _id: "P1" }).addresses;
check(retained.length === 1 && retained[0].addressId === "A1",
  "Expected only A1 to remain");
```

Use pull to remove an array element. Unsetting a positional element can leave a null rather than shrinking the array, so it is not interchangeable with element removal.

## 11. Failure exercise — array shape mismatch

Create a deliberate scalar where an array was expected:

```javascript
lab.profiles.insertOne({ _id: "BAD", tags: "lab" });
var pushRejected = false;
try {
  lab.profiles.updateOne({ _id: "BAD" }, { $push: { tags: "synthetic" } });
} catch (e) {
  pushRejected = e.code === 2;
  printjson({ code: e.code, message: e.message });
}
check(pushRejected, "Expected non-array push rejection");

var wrongTypes = lab.profiles.aggregate([
  { $match: { _id: "BAD" } },
  { $project: { tagsType: { $type: "$tags" } } }
]).toArray();
check(wrongTypes[0].tagsType === "string", "Expected bad scalar type");

lab.profiles.updateOne({ _id: "BAD" }, { $set: { tags: ["lab"] } });
lab.profiles.updateOne({ _id: "BAD" }, { $push: { tags: "synthetic" } });
check(lab.profiles.findOne({ _id: "BAD" }).tags.length === 2,
  "Corrected array should accept push");
lab.profiles.deleteOne({ _id: "BAD" });
```

The repair uses a known fixture. Real mixed-type arrays require source validation, controlled conversion and producer fixes; schema validation can prevent recurrence.

## 12. Final evidence

```javascript
var finalProfile = lab.profiles.findOne({ _id: "P1" });
check(lab.profiles.countDocuments({}) === 2, "Final profile count");
check(finalProfile.contact.preferences.sms === true, "Preference retained");
check(finalProfile.contact.email === "demo@example.invalid", "Sibling field retained");
check(finalProfile.addresses.length === 1, "Address removal outcome");
check(finalProfile.addresses[0].city === "Dallas", "Address update retained");
check(finalProfile.recentEvents.length === 3, "Summary bound");
check(finalProfile.tags.filter(t => t === "lab").length === 1, "No lab-tag duplicate");

lab.profiles.aggregate([
  { $project: { _id: 1, bytes: { $bsonSize: "$$ROOT" },
    addressCount: { $size: "$addresses" },
    eventCount: { $size: "$recentEvents" } } }
]).toArray();
print("PASS: nested updates, precise array targeting, duplicates, bounded summary and type repair");
```

Exact BSON sizes are informational. An application's growth budget must be tested against realistic cardinality and update patterns.

## 13. Troubleshooting

| Symptom | Evidence | Action |
|---|---|---|
| Sibling fields disappear | Whole-object versus dot-path update | Use targeted updates or deliberate complete replacement |
| Wrong address matches | Same-element requirement | Use elemMatch where needed |
| Positional update fails | Query contains the relevant array predicate | Supply a valid match and avoid unsupported upsert patterns |
| matchedCount 1 but modifiedCount 0 | ArrayFilters and current values | Check element match and desired state |
| Duplicate tags remain | Existing duplicates and operator choice | addToSet prevents new duplicates, not historical duplicates |
| Push fails with code 2 | Stored field type | Repair known invalid shape and enforce a contract |
| Recent history missing | Slice/retention contract | Separate durable history from bounded summary |
| Array grows indefinitely | All producer update paths | Enforce a consistent bound or move history out of the document |

## 14. Production takeaways

Single-document array updates are atomic at the document boundary, but hot profiles can still be contention points. Large arrays increase document size, network payload and update complexity.

Specify identity, cardinality, order, duplicate rules and removal semantics for each array. Test the actual driver serialization and all producer paths. Schema and index chapters expand enforcement and query-planning considerations.

## 15. Cleanup and acceptance

```javascript
check(lab.getName() === "mongodb_enterprise_tutorial_ch09", "Unexpected cleanup database");
lab.profiles.drop();
check(!lab.getCollectionNames().includes("profiles"), "Cleanup failed");
print("PASS: Chapter 09 collection removed");
```

- [ ] Verify dot updates preserve sibling fields.
- [ ] Demonstrate/reverse whole-object replacement.
- [ ] Distinguish cross-element and same-element queries.
- [ ] Verify $, $[], arrayFilters and no-element behavior.
- [ ] Demonstrate push/addToSet/pull duplicate semantics.
- [ ] Verify the newest-three summary and its retention boundary.
- [ ] Observe and repair the scalar/array mismatch.
- [ ] Capture final assertions, sizes and cleanup.

**Authoring validation:** JavaScript syntax and official operator references reviewed; live MongoDB execution remains pending. Record exact versions, deployment, operator, date and outputs after running.

Review questions:

1. Why is array position a poor long-term business identifier?
2. Why can modifiedCount be zero when the document matched?
3. Why does addToSet not enforce uniqueness by one object field?
4. Why is a bounded recent array not a durable history source?
5. What controls prevent a different producer from bypassing an array bound?

## Technical references

- [Positional $ — 8.0](https://www.mongodb.com/docs/v8.0/reference/operator/update/positional/)
- [All positional $[] — 8.0](https://www.mongodb.com/docs/v8.0/reference/operator/update/positional-all/)
- [Filtered positional — 8.0](https://www.mongodb.com/docs/v8.0/reference/operator/update/positional-filtered/)
- [$push — 8.0](https://www.mongodb.com/docs/v8.0/reference/operator/update/push/)
- [$addToSet — 8.0](https://www.mongodb.com/docs/v8.0/reference/operator/update/addToSet/)
- [$pull — 8.0](https://www.mongodb.com/docs/v8.0/reference/operator/update/pull/)
- [$elemMatch — 8.0](https://www.mongodb.com/docs/v8.0/reference/operator/query/elemMatch/)

Previous: [Chapter 08 — CRUD Filters Projections and Sorting](08-crud-filters-projections-and-sorting.md).  
Next: [Chapter 10 — Embedding Versus Referencing](10-embedding-versus-referencing.md).  
Return to the [master layout](MASTER-LAYOUT.md).
