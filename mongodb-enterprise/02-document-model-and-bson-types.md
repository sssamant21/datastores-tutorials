# 02 — Document Model and BSON Types

**Status:** Written; static review complete; runtime lab validation pending  
**Part:** 1 — Foundations and Architecture  
**Goal:** Design and inspect typed documents, reproduce type-related query errors, and enforce a basic BSON contract.  
**Audience:** Developers, Data Engineers, DBREs, SREs and Platform Engineers  
**Time:** 60–90 minutes after a training server is available  
**Baseline:** MongoDB 8.0 and mongosh; record exact server and shell patch versions when running. The syntax is intended for the track's 8.0 baseline, not a claim of validation on every release.  
**Deployment:** Core features available in Community and Enterprise; standalone or replica set. No Enterprise-only feature is exercised.

## 1. Why the document model matters

A MongoDB document represents an application entity using named fields and typed values. Embedded documents describe related structures; arrays describe ordered sequences. A collection groups documents that serve a common application purpose.

Consider a patient summary used by an application:

- The patient identifier is a string because leading zeros and formatting matter.
- The last update is a BSON date because the application filters by time.
- A balance uses Decimal128 because binary floating-point approximations are unsuitable for the monetary contract.
- Addresses form an array of objects with a predictable structure.
- An optional contact field distinguishes an unknown value from an absent field.

These decisions affect queries, indexes, validation, driver serialization and downstream analytics. If one producer writes a date and another writes a date string, a successful insert does not prove that consumers can interpret both.

This chapter focuses on representation and correctness. Chapter 09 develops array operations, Chapter 10 examines embedding versus referencing, and Chapter 11 covers schema rollout and evolution.

## 2. JSON, BSON and Extended JSON

| Format | Purpose | Type implications |
|---|---|---|
| JSON | Text interchange used by APIs and files | Has strings, numbers, booleans, null, arrays and objects; no native ObjectId or date |
| BSON | Binary format used for MongoDB documents | Distinguishes dates, ObjectId, numeric types and binary values |
| Extended JSON | Text representation of BSON types | Uses defined wrappers to preserve BSON information across text boundaries |

BSON is not simply compressed JSON. Its type information is part of the stored value. A textual date does not become a BSON date merely because its contents resemble an ISO timestamp.

Example mongosh constructors:

```javascript
ObjectId("650000000000000000000001")
ISODate("2026-10-10T12:00:00Z")
Int32(42)
Long("9007199254740993")
Decimal128("19.95")
```

These expressions are JavaScript executed by mongosh; they are not valid plain JSON. In an application, use the corresponding driver's BSON classes and native date representation. Verify serialization rather than copying shell constructors into an API request.

## 3. Practical BSON type map

| BSON type | mongosh example | Typical use | Common mistake |
|---|---|---|---|
| string | `"EMP0001"` | Business identifiers and names | Converting identifiers to numbers and losing leading zeros |
| bool | `true` | Explicit flags | Writing `"true"` as a string |
| int | `Int32(42)` | Bounded whole numbers | Assuming all JavaScript numbers serialize as this type |
| long | `Long("9007199254740993")` | Larger whole numbers | Constructing from an already rounded JavaScript number |
| double | `Double(12.5)` | Approximate numeric measurements | Using approximate binary arithmetic for an exact monetary contract |
| decimal | `Decimal128("19.95")` | Decimal monetary or precision-sensitive values | Converting to JavaScript Number and losing the intended precision |
| date | `ISODate("2026-10-10T12:00:00Z")` | Application event time | Storing an ISO-looking string and expecting date comparisons |
| objectId | `ObjectId("650000000000000000000001")` | Common document identifier | Querying with the hexadecimal string instead of ObjectId |
| object | `{ city: "Austin" }` | Embedded structure | Replacing the whole object when only one subfield should change |
| array | `["lab", "synthetic"]` | Ordered related values | Allowing uncontrolled growth or mixing incompatible element types |
| null | `null` | Explicit absence of a value | Treating null and a missing field as identical |
| binData | Driver-created binary/UUID value | Binary content and typed UUID representation | Mixing UUID representations across drivers |
| timestamp | Internal BSON timestamp | Internal MongoDB contexts such as replication | Using it instead of a BSON date for application event time |

Use explicit constructors in this lab so expected types do not depend on implicit shell numeric conversion. Decimal128 has finite precision; it does not provide arbitrary-precision arithmetic.

BSON dates represent milliseconds relative to the Unix epoch. They do not preserve the original timezone name. Store a separate timezone field if the business meaning depends on a local zone. ObjectId contains a timestamp component, but it is not a complete business event-time or ordering contract.

## 4. Document structure and boundaries

Normal BSON documents have a maximum size of 16 MiB. A document can be much smaller and still be operationally expensive when it contains large arrays or frequently updated structures.

Use predictable field names such as `patientId`, `updatedAt` and `addresses`. Avoid duplicate field names. Although some versions allow dollar-prefixed or dotted field names in certain contexts, they complicate tools and queries; this track uses simple names.

An application's document contract should state:

1. Identifier type and uniqueness rules.
2. Required fields and allowed types.
3. Optional, missing and null semantics.
4. Embedded object and array shapes.
5. Numeric precision and units.
6. Date and timezone conventions.
7. Maximum practical growth and retention behavior.

Do not embed an unbounded history just because the first few records fit. Large binary data may need GridFS or an external object store, depending on access requirements.

## 5. Prerequisites and lab connection

Use a dedicated training deployment and synthetic data. The account needs to create collections, read, insert, update and drop the named lab collections in **mongodb_enterprise_tutorial_ch02**. Basic CRUD privileges do not automatically include collection creation; check the assigned permissions.

For an existing local training server:

```bash
mongosh "mongodb://127.0.0.1:27017"
```

For an authorized TLS deployment, substitute approved values:

```bash
mongosh "mongodb://TRAINING_HOST:27017/?authSource=admin" --username tutorial_user --password --tls --tlsCAFile /path/to/ca.pem
```

The password is prompted. Preserve the approved replica-set connection parameters where applicable.

If no server is available and Docker is installed, create a disposable local Community container:

```bash
docker run --name mongodb-ch02 --detach --publish 127.0.0.1:27017:27017 mongo:8.0
docker exec -it mongodb-ch02 mongosh
```

This unauthenticated training container is bound to loopback and has no persistent volume. Its core BSON exercises do not validate Enterprise capabilities. Record its image digest and actual server patch version.

In a terminal, record:

```bash
mongosh --version
```

In mongosh, record:

```javascript
db.version()
db.runCommand({ hello: 1 })
```

All subsequent JavaScript blocks run in the **same mongosh session**, in order. Printed results can differ in formatting across shell versions; assertions check the meaningful values.

## 6. Lab setup and synthetic fixtures

Create two unvalidated collections for type demonstrations. A third, validated collection is added later.

```javascript
var lab = db.getSiblingDB("mongodb_enterprise_tutorial_ch02");
var labCollections = ["profiles", "presence", "validated_profiles"];
if (labCollections.some(name => lab.getCollectionNames().includes(name))) {
  throw new Error("Chapter 02 resources already exist. Review cleanup before rerunning.");
}
lab.createCollection("profiles");
lab.createCollection("presence");

function check(condition, message) {
  if (!condition) throw new Error(message);
}
function expectIds(collection, filter, expected, label) {
  var actual = collection.find(filter, { _id: 1 })
    .sort({ _id: 1 }).toArray().map(doc => doc._id.toString());
  check(JSON.stringify(actual) === JSON.stringify(expected),
    label + ": expected " + JSON.stringify(expected) + ", got " + JSON.stringify(actual));
}
```

The setup guard deliberately stops on existing resources. Do not delete an unknown collection merely to make the exercise proceed.

Insert two well-typed profiles and one deliberately inconsistent profile:

```javascript
lab.profiles.insertMany([
  {
    _id: ObjectId("650000000000000000000001"),
    patientId: "EMP0001",
    active: true,
    visitCount: Int32(3),
    externalSequence: Long("9007199254740993"),
    balance: Decimal128("19.95"),
    updatedAt: ISODate("2026-10-10T12:00:00Z"),
    tags: ["lab", "synthetic"],
    addresses: [
      { kind: "home", city: "Austin", state: "TX" },
      { kind: "work", city: "Boston", state: "MA" }
    ]
  },
  {
    _id: ObjectId("650000000000000000000002"),
    patientId: "EMP0002",
    active: true,
    visitCount: Int32(1),
    externalSequence: Long("9007199254740993"),
    balance: Decimal128("10.05"),
    updatedAt: ISODate("2026-10-10T13:00:00Z"),
    tags: ["lab", "synthetic"],
    addresses: [
      { kind: "home", city: "Boston", state: "MA" }
    ]
  },
  {
    _id: ObjectId("650000000000000000000003"),
    patientId: "EMP0003",
    active: "true",
    visitCount: "2",
    balance: "5.00",
    updatedAt: "2026-10-10T14:00:00Z",
    tags: '["lab","synthetic"]',
    addresses: [
      { kind: "home", city: "Denver", state: "CO" }
    ]
  }
]);
check(lab.profiles.countDocuments({}) === 3, "Expected three profiles");
```

Expected: three acknowledged inserts. The third profile illustrates how an unvalidated collection can accept values that violate the intended application contract.

## 7. Inspect stored types on the server

Use the aggregation `$type` expression to inspect each field's stored type:

```javascript
var typeRows = lab.profiles.aggregate([
  { $sort: { patientId: 1 } },
  {
    $project: {
      _id: 0,
      patientId: 1,
      idType: { $type: "$_id" },
      activeType: { $type: "$active" },
      visitsType: { $type: "$visitCount" },
      sequenceType: { $type: "$externalSequence" },
      balanceType: { $type: "$balance" },
      dateType: { $type: "$updatedAt" },
      tagsType: { $type: "$tags" }
    }
  }
]).toArray();
printjson(typeRows);

check(typeRows[0].idType === "objectId", "Expected ObjectId");
check(typeRows[0].visitsType === "int", "Expected Int32");
check(typeRows[0].sequenceType === "long", "Expected Int64");
check(typeRows[0].balanceType === "decimal", "Expected Decimal128");
check(typeRows[0].dateType === "date", "Expected BSON date");
check(typeRows[2].dateType === "string", "Expected intentional date-string mismatch");
check(typeRows[2].tagsType === "string", "Expected intentional JSON-string mismatch");
```

Expected type summary:

| Profile | active | visitCount | externalSequence | balance | updatedAt | tags |
|---|---|---|---|---|---|---|
| EMP0001 | bool | int | long | decimal | date | array |
| EMP0002 | bool | int | long | decimal | date | array |
| EMP0003 | string | string | missing | string | string | string |

JavaScript `typeof` answers a client-language question. It does not reliably identify every server-side BSON type. For database diagnosis, inspect stored types.

The **query** operator `{ field: { $type: ... } }` and the **aggregation** expression `{ $type: "$field" }` serve different purposes. Query `$type` can match array elements for scalar type requests; aggregation `$type` reports the field value's type without inspecting each element. For this lab's scalar fields the distinction does not change the expected counts.

## 8. Failure exercise — ObjectId versus string

A 24-character hexadecimal string may look like an ObjectId in a log, but its BSON type is different.

```javascript
var asText = lab.profiles.findOne({ _id: "650000000000000000000001" });
var asObjectId = lab.profiles.findOne({
  _id: ObjectId("650000000000000000000001")
});
check(asText === null, "String should not match an ObjectId identifier");
check(asObjectId.patientId === "EMP0001", "Typed identifier should find EMP0001");
print("PASS: ObjectId/string mismatch reproduced and corrected");
```

Correct the driver or query construction using the intended identifier type. Validate the input format before constructing ObjectId. Do not rewrite all identifiers merely to compensate for a faulty client query.

## 9. Failure exercise — dates, booleans and JSON strings

A typed date range retrieves the two BSON dates, not the date string:

```javascript
check(lab.profiles.countDocuments({
  updatedAt: {
    $gte: ISODate("2026-10-10T00:00:00Z"),
    $lt: ISODate("2026-10-11T00:00:00Z")
  }
}) === 2, "Expected only two BSON dates in the typed range");

check(lab.profiles.countDocuments({ active: true }) === 2,
  "Boolean true should not match string true");
check(lab.profiles.countDocuments({ tags: "lab" }) === 2,
  "Array membership should not match serialized JSON text");

lab.profiles.find({ updatedAt: { $type: "string" } },
  { patientId: 1, updatedAt: 1 }).toArray();
```

Expected mismatch record: EMP0003. Comparison predicates generally use type bracketing; a date bound is not an instruction to parse date strings.

Repair only the known synthetic record. Preview a conversion with explicit failure behavior:

```javascript
var preview = lab.profiles.aggregate([
  { $match: { patientId: "EMP0003" } },
  {
    $project: {
      _id: 0,
      original: "$updatedAt",
      converted: {
        $convert: { input: "$updatedAt", to: "date", onError: null, onNull: null }
      }
    }
  }
]).toArray();
check(preview.length === 1 && preview[0].converted instanceof Date,
  "Expected valid date conversion");
printjson(preview);
```

For a general migration, `null` as an error sentinel needs a separate error classification so valid nulls are not confused with failed conversion. This fixture has a known non-null source value.

Apply a scoped update:

```javascript
var repaired = lab.profiles.updateOne(
  {
    _id: ObjectId("650000000000000000000003"),
    updatedAt: "2026-10-10T14:00:00Z"
  },
  {
    $set: {
      active: true,
      visitCount: Int32(2),
      balance: Decimal128("5.00"),
      updatedAt: preview[0].converted,
      tags: ["lab", "synthetic"]
    }
  }
);
check(repaired.matchedCount === 1 && repaired.modifiedCount === 1,
  "Expected one repaired profile");
check(lab.profiles.countDocuments({ updatedAt: { $type: "date" } }) === 3,
  "Expected three BSON dates after repair");
check(lab.profiles.countDocuments({ active: true }) === 3,
  "Expected three booleans after repair");
check(lab.profiles.countDocuments({ tags: "lab" }) === 3,
  "Expected three arrays supporting membership query");
```

The tags repair uses a known expected array. It does not demonstrate arbitrary JSON parsing. Real repairs should validate source content, quarantine ambiguous records, preserve recovery evidence and fix the producer before backfilling.

## 10. Missing, null, empty string and empty array

Use a separate collection so these cases do not alter the profile fixtures:

```javascript
lab.presence.insertMany([
  { _id: "missing" },
  { _id: "null", contact: null },
  { _id: "empty-string", contact: "" },
  { _id: "empty-array", contact: [] },
  { _id: "value", contact: "demo@example.invalid" }
]);

expectIds(lab.presence, { contact: null }, ["missing", "null"],
  "Null equality includes missing");
expectIds(lab.presence, { contact: { $exists: false } }, ["missing"],
  "Missing field only");
expectIds(lab.presence, { contact: { $type: "null" } }, ["null"],
  "Explicit null only");
expectIds(lab.presence, { contact: { $exists: true } },
  ["empty-array", "empty-string", "null", "value"], "Present fields");
expectIds(lab.presence, { contact: { $ne: null } },
  ["empty-array", "empty-string", "value"], "Present and non-null");
expectIds(lab.presence, { contact: "" }, ["empty-string"], "Empty string");
expectIds(lab.presence, { contact: { $size: 0 } },
  ["empty-array"], "Empty array");
```

Expected results are included in every assertion. The null cases here have scalar null values; arrays containing null introduce additional query semantics and are not part of these fixtures.

Inspect missing and null through aggregation:

```javascript
lab.presence.aggregate([
  { $project: { _id: 1, contactType: { $type: "$contact" } } },
  { $sort: { _id: 1 } }
]).toArray();
```

Expected: `missing` reports type `missing`; the explicit null reports `null`. Decide what each state means before defining API defaults or downstream transformations. A fallback expression that treats missing and null the same can erase a useful distinction.

## 11. Embedded objects, arrays and same-element matching

Suppose the application wants patients with a **home address in Boston**.

Independent dotted conditions can be satisfied by different array elements:

```javascript
var loose = lab.profiles.find({
  "addresses.kind": "home",
  "addresses.city": "Boston"
}, { _id: 0, patientId: 1 }).sort({ patientId: 1 }).toArray();

var precise = lab.profiles.find({
  addresses: { $elemMatch: { kind: "home", city: "Boston" } }
}, { _id: 0, patientId: 1 }).sort({ patientId: 1 }).toArray();

check(JSON.stringify(loose.map(d => d.patientId)) ===
  JSON.stringify(["EMP0001", "EMP0002"]), "Expected cross-element match");
check(JSON.stringify(precise.map(d => d.patientId)) ===
  JSON.stringify(["EMP0002"]), "Expected same-element match");
printjson({ loose: loose, precise: precise });
```

EMP0001 has a home address in Austin and a work address in Boston. The dotted conditions match that document, even though no single address is both home and Boston. `$elemMatch` expresses the same-element requirement.

This is a correctness issue before it is an index-tuning issue. Later chapters cover multikey index design and array updates.

## 12. Numeric precision and aggregation

JavaScript's ordinary Number cannot represent all 64-bit integers exactly. Construct large integers from strings so they are not rounded before BSON conversion.

```javascript
var first = lab.profiles.findOne({ patientId: "EMP0001" });
check(first.externalSequence.toString() === "9007199254740993",
  "Large integer must survive without rounding");

var totals = lab.profiles.aggregate([
  { $group: { _id: null, totalBalance: { $sum: "$balance" } } }
]).toArray();
check(totals.length === 1 && totals[0].totalBalance.toString() === "35.00",
  "Expected Decimal128 total 35.00");
printjson(totals);
```

Expected: a Decimal128 total representing 35.00 after the repair. Decimal128 display preserves a decimal representation; arithmetic policies still need explicit currency, scale and rounding decisions.

Do arithmetic in a component that supports the intended decimal semantics. Avoid converting a Decimal128 or Long to Number just to simplify API output. Agree on a lossless API encoding instead.

## 13. Extended JSON round-trip

A text export should preserve the types that matter. Use canonical Extended JSON for this demonstration:

```javascript
var original = lab.profiles.findOne({ patientId: "EMP0001" });
var encoded = EJSON.stringify(original, null, 2, { relaxed: false });
print(encoded);
var decoded = EJSON.parse(encoded, { relaxed: false });

check(decoded._id.toString() === original._id.toString(), "ObjectId round-trip");
check(decoded.updatedAt.getTime() === original.updatedAt.getTime(), "Date round-trip");
check(decoded.externalSequence.toString() === "9007199254740993", "Long round-trip");
check(decoded.balance.toString() === "19.95", "Decimal round-trip");
```

Expected output includes wrappers such as `$oid`, `$date`, `$numberLong`, `$numberInt` and `$numberDecimal`. The exact formatting is not the acceptance criterion; the restored typed values are.

Canonical Extended JSON is verbose and useful when preserving exact BSON numeric types. Relaxed Extended JSON improves readability but can represent some numeric values as ordinary JSON numbers. Plain JSON consumers also need a defined decoding contract; a wrapper-shaped object is not automatically a BSON value unless a suitable parser interprets it.

## 14. Add a basic collection contract

Create a fresh collection with validation. This does not modify the earlier unvalidated collections.

```javascript
lab.createCollection("validated_profiles", {
  validator: {
    $jsonSchema: {
      bsonType: "object",
      required: ["patientId", "active", "visitCount", "balance", "updatedAt", "tags"],
      properties: {
        patientId: { bsonType: "string", pattern: "^EMP[0-9]{4}$" },
        active: { bsonType: "bool" },
        visitCount: { bsonType: "int", minimum: 0 },
        balance: { bsonType: "decimal" },
        updatedAt: { bsonType: "date" },
        tags: { bsonType: "array", items: { bsonType: "string" } }
      }
    }
  },
  validationLevel: "strict",
  validationAction: "error"
});

lab.validated_profiles.insertOne({
  _id: "VALID01",
  patientId: "EMP0004",
  active: true,
  visitCount: Int32(0),
  balance: Decimal128("0.00"),
  updatedAt: ISODate("2026-10-10T15:00:00Z"),
  tags: ["lab", "synthetic"]
});
```

Expected: one accepted document. The validator constrains the listed fields and deliberately permits other fields. It does not validate addresses, enforce patientId uniqueness, or limit tag count. Those require additional schema/index decisions.

The `required` list checks presence; `bsonType` checks allowed types. A required field containing null would fail these non-null type rules. `strict` applies validation to inserts and updates, and `error` rejects invalid writes.

Trigger and verify a rejected date string:

```javascript
var validationRejected = false;
try {
  lab.validated_profiles.insertOne({
    _id: "INVALID01",
    patientId: "EMP0005",
    active: true,
    visitCount: Int32(0),
    balance: Decimal128("0.00"),
    updatedAt: "2026-10-10T16:00:00Z",
    tags: ["lab", "synthetic"]
  });
} catch (e) {
  validationRejected = e.code === 121;
  printjson({ code: e.code, message: e.message, details: e.errInfo });
}
check(validationRejected, "Expected document validation error code 121");
check(lab.validated_profiles.countDocuments({}) === 1,
  "Rejected document must not be inserted");
```

Correct the failed document and verify success:

```javascript
lab.validated_profiles.insertOne({
  _id: "CORRECTED01",
  patientId: "EMP0005",
  active: true,
  visitCount: Int32(0),
  balance: Decimal128("0.00"),
  updatedAt: ISODate("2026-10-10T16:00:00Z"),
  tags: ["lab", "synthetic"]
});
check(lab.validated_profiles.countDocuments({}) === 2,
  "Expected valid and corrected documents");
```

Do not bypass validation to resolve a producer bug. Adding a validator to an existing collection is a separate migration task: inspect historical data, define compatibility, repair or quarantine bad records, and test the deployment plan. A validator does not automatically convert historical records.

## 15. Final acceptance checks

Run before cleanup:

```javascript
check(lab.profiles.countDocuments({}) === 3, "Profile count");
check(lab.profiles.countDocuments({ _id: { $type: "objectId" } }) === 3,
  "Identifier types");
check(lab.profiles.countDocuments({ updatedAt: { $type: "date" } }) === 3,
  "Date types");
check(lab.profiles.countDocuments({ visitCount: { $type: "int" } }) === 3,
  "Visit count types");
check(lab.profiles.countDocuments({ balance: { $type: "decimal" } }) === 3,
  "Balance types");
check(lab.profiles.countDocuments({ tags: { $type: "array" } }) === 3,
  "Tag array types");
check(lab.presence.countDocuments({}) === 5, "Presence fixture count");
check(lab.validated_profiles.countDocuments({}) === 2, "Validated fixture count");
check(validationRejected, "Validation failure observed");
check(loose.length === 2 && precise.length === 1, "Array query difference observed");

var sizes = lab.profiles.aggregate([
  { $project: { _id: 0, patientId: 1, bytes: { $bsonSize: "$$ROOT" } } },
  { $sort: { patientId: 1 } }
]).toArray();
check(sizes.every(row => row.bytes > 0 && row.bytes < 16 * 1024 * 1024),
  "Fixture document sizes");
printjson(sizes);
print("PASS: typed documents, mismatch repair, null/missing, elemMatch, precision, EJSON and validation");
```

The small fixture sizes vary with document content. This inspection does not prove production growth is bounded.

## 16. Troubleshooting guide

| Symptom | Evidence | Likely cause | Corrective action |
|---|---|---|---|
| Identifier lookup returns no document | Stored `$type` and query parameter type | String/ObjectId mismatch | Construct the intended BSON identifier in the client |
| Date range misses records | Type inventory of the date field | Strings mixed with BSON dates | Fix serialization; preview and scope a repair |
| Boolean filter misses records | Inspect bool/string counts | Producer writes string flags | Enforce the boolean contract |
| Tags membership query misses records | Aggregation `$type` | JSON text stored instead of an array | Validate parsing and write native arrays |
| Null query returns more records than expected | Compare null equality, `$exists` and `$type` | Missing and null both match equality to null | Use the predicate that represents the business rule |
| Address query returns an unexpected patient | Compare dotted predicates with `$elemMatch` | Conditions satisfied by different elements | Use same-element matching |
| Large integer changes after export | Inspect Long construction and text encoding | Conversion through an unsafe Number | Preserve Long or a lossless string contract |
| Validation error 121 | Error details, required fields and stored types | Document violates the schema | Correct the document and producer |
| Setup guard throws | Existing named lab collections | Previous run was not cleaned up | Review the resources and execute scoped cleanup |
| Collection creation is unauthorized | Account privileges and command | Missing createCollection permission | Use authorized scoped training permissions |

## 17. Production considerations

**Application contract:** Choose types at the producer boundary and verify driver serialization. Validation helps enforce the contract but does not replace application input checks or uniqueness indexes.

**Performance:** Frequent conversion during queries can complicate index use. Normalize known fields at ingestion; investigate query plans rather than assuming a conversion-heavy query will use the intended index.

**Capacity:** Monitor representative document sizes and array growth. A 16 MiB ceiling is not a target size.

**Observability:** Inventory types for critical fields and track validation failures. Large type-distribution scans should be scoped or scheduled; the three-record lab is not a production scan budget.

**Security:** Use synthetic fixtures and avoid displaying sensitive values when collecting incident evidence. Prefer type/count summaries where possible.

**Recovery:** A type-changing backfill is a data change. Define rollback evidence, backups, filters, batching and reconciliation before running it on production.

**Direct MongoDB→Snowflake integration:** Specify how dates, Decimal128, Long, arrays and missing/null states map into the connector and target schema. Test the actual export format and connector behavior. Elasticsearch is not required as an intermediary in this track.

## 18. Cleanup

Drop only the three chapter collections. The validated collection's validator disappears with that collection; no server-wide configuration was changed.

```javascript
check(lab.getName() === "mongodb_enterprise_tutorial_ch02",
  "Unexpected cleanup database");
["profiles", "presence", "validated_profiles"].forEach(name => {
  lab.getCollection(name).drop();
});
check(!["profiles", "presence", "validated_profiles"].some(name =>
  lab.getCollectionNames().includes(name)), "Cleanup verification failed");
print("PASS: Chapter 02 collections removed");
```

If you created the optional Docker container, exit mongosh and run:

```bash
docker stop mongodb-ch02
docker rm mongodb-ch02
```

Do not remove a shared training server or Chapter 01 resources. To repeat this lab, start again at setup after cleanup.

## 19. Evidence and validation record

- [ ] Record server and mongosh patch versions, topology and optional image digest.
- [ ] Capture the initial type inventory showing the intentionally inconsistent profile.
- [ ] Reproduce and correct the ObjectId query mismatch.
- [ ] Verify typed date/boolean/array filters before and after repair.
- [ ] Confirm missing/null/empty cases and array same-element matching.
- [ ] Verify Long and Decimal128 precision and the EJSON round-trip.
- [ ] Observe validation code 121 and the successful corrected insert.
- [ ] Capture the final PASS line, document-size output and cleanup PASS line.

| Evidence field | Run value |
|---|---|
| Server version and edition | Fill after execution |
| mongosh version | Fill after execution |
| Deployment/topology | Fill after execution |
| Run date and operator | Fill after execution |
| Acceptance and cleanup results | Pending |
| Version or permission differences | Fill after execution |

**Authoring validation:** Commands and references were statically reviewed. JavaScript blocks were checked for syntax. No MongoDB server, mongosh or Docker runtime was available in the authoring environment, so no live database outcomes are claimed.

## 20. Review questions

1. Why is an ISO-looking string different from a BSON date?
2. Why should a large Long be constructed from a string?
3. Which predicate distinguishes an explicit null from a missing field?
4. Why can independent array conditions match the wrong business case?
5. What does this validator enforce, and what does it leave unconstrained?
6. Which type information could an ordinary JSON export lose?

## Technical references

Use the versioned manual matching the server you operate.

- [BSON types — 8.0](https://www.mongodb.com/docs/v8.0/reference/bson-types/)
- [Documents — 8.0](https://www.mongodb.com/docs/v8.0/core/document/)
- [Query null or missing fields — 8.0](https://www.mongodb.com/docs/v8.0/tutorial/query-for-null-fields/)
- [Query $elemMatch — 8.0](https://www.mongodb.com/docs/v8.0/reference/operator/query/elemMatch/)
- [Aggregation $type — 8.0](https://www.mongodb.com/docs/v8.0/reference/operator/aggregation/type/)
- [Query $type — 8.0](https://www.mongodb.com/docs/v8.0/reference/operator/query/type/)
- [Schema validation — 8.0](https://www.mongodb.com/docs/v8.0/core/schema-validation/specify-json-schema/)
- [Extended JSON — 8.0](https://www.mongodb.com/docs/v8.0/reference/mongodb-extended-json/)
- [mongosh EJSON](https://www.mongodb.com/docs/mongodb-shell/reference/ejson/)
- [Aggregation $bsonSize — 8.0](https://www.mongodb.com/docs/v8.0/reference/operator/aggregation/bsonSize/)

Previous: [Chapter 01 — MongoDB Enterprise Fundamentals](01-mongodb-enterprise-fundamentals.md).  
Next: **Chapter 03 — Server Architecture and WiredTiger** (planned).  
Return to the [master layout](MASTER-LAYOUT.md).
