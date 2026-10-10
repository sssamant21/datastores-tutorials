# 15 — Pagination and API Query Design

**Status:** Written; static review complete; runtime lab validation pending  
**Part:** 2 — Data Modeling and Application Development  
**Goal:** Build bounded, tenant-scoped seek pagination with signed cursors and reproduce offset pagination instability.  
**Audience:** Developers, Data Engineers, DBREs and SREs  
**Time:** 75–105 minutes  
**Baseline:** MongoDB 8.0/mongosh with its Node.js crypto/Buffer APIs; record exact versions.  
**Deployment:** Community-compatible or Enterprise training database. An illustrative shell API contract, not a deployed web service.

## 1. An API query has a scope and ordering contract

Specify allowed filters, authorization scope, page-size maximum, projection, order and consistency expectations. Do not accept arbitrary query documents or client-provided tenant scope as authorization.

Offset pagination sorts, skips N rows and returns a page. Seek pagination uses the last returned sort key to find the next page. Increasing offsets can require traversing more results, and inserts/deletes before an offset can shift later pages.

Neither method automatically supplies a snapshot of a changing dataset. For stable exports, design the read consistency, immutable keys, cutoff/snapshot mechanism and retention separately.

## 2. Two-key seek order

This lab orders by createdAt descending, then _id descending. For the next page after a record at time T and identifier I, select:

- createdAt earlier than T, or
- createdAt equal to T and _id less than I.

Both predicates are needed because multiple records can share a timestamp.

| API element | Lab contract |
|---|---|
| Tenant | Verified caller scope supplied separately |
| Filter | active true |
| Sort | createdAt descending, _id descending |
| Page size | Integer 1–3 |
| Returned fields | _id, createdAt, label |
| Continuation | Signed versioned cursor bound to tenant/filter |
| Cutoff | Initial maximum createdAt; not a snapshot guarantee |

All identifiers use one consistent string type. A production ObjectId cursor should preserve and reconstruct that BSON type explicitly.

## 3. Setup

Connect with create/CRUD/index/cleanup permissions in **mongodb_enterprise_tutorial_ch15**. Run JavaScript in one session.

```javascript
var lab = db.getSiblingDB("mongodb_enterprise_tutorial_ch15");
if (lab.getCollectionNames().includes("events")) throw new Error("Existing chapter collection");
lab.createCollection("events");
function check(ok, message) { if (!ok) throw new Error(message); }

var fixtures = [];
for (var i = 1; i <= 8; i++) {
  var hour = Math.floor((i - 1) / 2);
  fixtures.push({
    _id: "E" + String(i).padStart(2, "0"),
    tenantId: "T1", active: true,
    createdAt: new Date(Date.UTC(2026, 9, 10, hour)),
    label: "synthetic-" + i,
    internalNote: "omit-from-api"
  });
}
fixtures.push({
  _id: "E99", tenantId: "T2", active: true,
  createdAt: ISODate("2026-10-10T03:00:00Z"), label: "other-tenant"
});
lab.events.insertMany(fixtures);
lab.events.createIndex({ tenantId: 1, active: 1, createdAt: -1, _id: -1 });
check(lab.events.countDocuments({ tenantId: "T1" }) === 8, "Expected eight T1 fixtures");
```

Timestamp ties are intentional. The compound index follows the lab equality filters and sort; later index chapters evaluate workload tradeoffs.

## 4. Signed cursor helpers

Use an ephemeral random key for this session. A deployed API needs managed key distribution/rotation and a versioned cursor policy; do not reuse a hardcoded training key.

```javascript
var crypto = require("crypto");
var cursorKey = crypto.randomBytes(32);
var queryVersion = "active-createdAt-desc-id-desc-v1";

function signCursor(payload) {
  var body = Buffer.from(JSON.stringify(payload)).toString("base64url");
  var signature = crypto.createHmac("sha256", cursorKey).update(body).digest("base64url");
  return body + "." + signature;
}
function parseDate(value) {
  if (typeof value !== "string") throw new Error("Date cursor field must be a string");
  var parsed = new Date(value);
  if (!Number.isFinite(parsed.getTime()) || parsed.toISOString() !== value) {
    throw new Error("Expected canonical ISO date");
  }
  return parsed;
}
function verifyCursor(token, authorizedTenant) {
  if (typeof token !== "string" || token.length > 4096) throw new Error("Invalid token size");
  var parts = token.split(".");
  if (parts.length !== 2 || !/^[A-Za-z0-9_-]+$/.test(parts[0]) ||
      !/^[A-Za-z0-9_-]{43}$/.test(parts[1])) throw new Error("Invalid token encoding");
  var expected = crypto.createHmac("sha256", cursorKey).update(parts[0]).digest();
  var supplied = Buffer.from(parts[1], "base64url");
  if (supplied.length !== expected.length || !crypto.timingSafeEqual(supplied, expected)) {
    throw new Error("Invalid cursor signature");
  }
  var data = JSON.parse(Buffer.from(parts[0], "base64url").toString());
  if (data.v !== 1 || data.queryVersion !== queryVersion ||
      data.tenant !== authorizedTenant) throw new Error("Cursor scope/version mismatch");
  if (!Number.isFinite(data.expiresAt) || data.expiresAt <= Date.now()) {
    throw new Error("Cursor expired");
  }
  if (!data.after || typeof data.after.id !== "string" ||
      !/^E[0-9]{2}$/.test(data.after.id)) throw new Error("Invalid cursor identifier");
  var afterDate = parseDate(data.after.createdAt);
  var cutoffDate = parseDate(data.cutoff);
  if (afterDate > cutoffDate) throw new Error("Invalid cursor range");
  return { after: { id: data.after.id, createdAt: afterDate }, cutoff: cutoffDate };
}
```

Signing protects integrity; it does not encrypt cursor contents. Do not put secrets in a cursor. Tenant validation must use the authenticated caller's scope, not a tenant value accepted from the request body.

## 5. Implement bounded seek pages

```javascript
function readPage(authorizedTenant, pageSize, token) {
  if (!["T1", "T2"].includes(authorizedTenant)) throw new Error("Invalid authorized tenant");
  if (!Number.isInteger(pageSize) || pageSize < 1 || pageSize > 3) {
    throw new Error("Page size must be 1–3");
  }
  var base = { tenantId: authorizedTenant, active: true };
  var state;
  if (token) {
    state = verifyCursor(token, authorizedTenant);
  } else {
    var newest = lab.events.find(base).sort({ createdAt: -1, _id: -1 }).limit(1).toArray();
    if (!newest.length) return { rows: [], nextCursor: null };
    state = { cutoff: newest[0].createdAt, after: null };
  }

  var conditions = [base, { createdAt: { $lte: state.cutoff } }];
  if (state.after) {
    conditions.push({ $or: [
      { createdAt: { $lt: state.after.createdAt } },
      { createdAt: state.after.createdAt, _id: { $lt: state.after.id } }
    ] });
  }
  var fetched = lab.events.find(
    { $and: conditions }, { _id: 1, createdAt: 1, label: 1 }
  ).sort({ createdAt: -1, _id: -1 }).limit(pageSize + 1).toArray();

  var hasMore = fetched.length > pageSize;
  var rows = fetched.slice(0, pageSize);
  var last = rows[rows.length - 1];
  var nextCursor = hasMore ? signCursor({
    v: 1, queryVersion: queryVersion, tenant: authorizedTenant,
    cutoff: state.cutoff.toISOString(),
    after: { id: last._id, createdAt: last.createdAt.toISOString() },
    expiresAt: Date.now() + 60 * 60 * 1000
  }) : null;
  return { rows: rows, nextCursor: nextCursor };
}
```

Fetching pageSize+1 detects whether another candidate exists without a full exact count. The projection omits internalNote and tenantId from returned data; scope is enforced in the filter.

Cursor expiry is a one-hour lab policy. Production cursor lifetimes, key rotation, query-version changes and error responses need explicit design.

## 6. Verify ties and complete traversal

```javascript
var first = readPage("T1", 3, null);
var second = readPage("T1", 3, first.nextCursor);
var third = readPage("T1", 3, second.nextCursor);
check(JSON.stringify(first.rows.map(r => r._id)) === JSON.stringify(["E08", "E07", "E06"]),
  "First page");
check(JSON.stringify(second.rows.map(r => r._id)) === JSON.stringify(["E05", "E04", "E03"]),
  "Second page including timestamp tie");
check(JSON.stringify(third.rows.map(r => r._id)) === JSON.stringify(["E02", "E01"]),
  "Third page");
check(third.nextCursor === null, "Last page must not continue");
var allIds = [...first.rows, ...second.rows, ...third.rows].map(r => r._id);
check(new Set(allIds).size === 8 && allIds.length === 8, "No repeated or missing fixture IDs");
check(first.rows.every(r => !("internalNote" in r)), "Internal projection boundary");
```

This traversal occurs on a stable fixture. It does not prove snapshot behavior during arbitrary concurrent mutations.

## 7. Failure exercise — offset shifts under deletion

```javascript
var savedFirst = lab.events.findOne({ _id: "E08" });
lab.events.deleteOne({ _id: "E08", tenantId: "T1" });

var shiftedOffset = lab.events.find({ tenantId: "T1", active: true })
  .sort({ createdAt: -1, _id: -1 }).skip(3).limit(3).toArray();
check(JSON.stringify(shiftedOffset.map(r => r._id)) === JSON.stringify(["E04", "E03", "E02"]),
  "Deletion shifted the offset and skipped E05");

var continuedSeek = readPage("T1", 3, first.nextCursor);
check(JSON.stringify(continuedSeek.rows.map(r => r._id)) ===
  JSON.stringify(["E05", "E04", "E03"]), "Seek continues after prior last key");
lab.events.insertOne(savedFirst);
```

The earlier page's deletion shifts positions used by skip. Seek uses the prior last key instead of position.

## 8. Failure exercise — a new front record repeats an offset row

```javascript
lab.events.insertOne({
  _id: "E09", tenantId: "T1", active: true,
  createdAt: ISODate("2026-10-10T04:00:00Z"), label: "new-front"
});
var shiftedInsert = lab.events.find({ tenantId: "T1", active: true })
  .sort({ createdAt: -1, _id: -1 }).skip(3).limit(3).toArray();
check(shiftedInsert[0]._id === "E06", "Offset repeats prior page's last record");

var cutoffSeek = readPage("T1", 3, first.nextCursor);
check(JSON.stringify(cutoffSeek.rows.map(r => r._id)) ===
  JSON.stringify(["E05", "E04", "E03"]), "Existing seek cursor preserves continuation");
lab.events.deleteOne({ _id: "E09", tenantId: "T1" });
```

The cutoff excludes this newer timestamp. A backfilled record below the cutoff, a changed sort key, deletion or status change can still affect continuation. A cutoff is not a snapshot.

## 9. Token and input rejection

```javascript
var crossTenantRejected = false;
try { readPage("T2", 3, first.nextCursor); } catch (e) { crossTenantRejected = true; }
check(crossTenantRejected, "Cross-tenant cursor must be rejected");

var pieces = first.nextCursor.split(".");
var altered = JSON.parse(Buffer.from(pieces[0], "base64url").toString());
altered.after.id = "E01";
var tampered = Buffer.from(JSON.stringify(altered)).toString("base64url") + "." + pieces[1];
var tamperRejected = false;
try { readPage("T1", 3, tampered); } catch (e) { tamperRejected = true; }
check(tamperRejected, "Tampered cursor must be rejected");

var expiredPayload = JSON.parse(Buffer.from(pieces[0], "base64url").toString());
expiredPayload.expiresAt = Date.now() - 1000;
var expiryRejected = false;
try { readPage("T1", 3, signCursor(expiredPayload)); } catch (e) { expiryRejected = true; }
check(expiryRejected, "Expired cursor must be rejected");

var sizeRejected = false;
try { readPage("T1", 10000, null); } catch (e) { sizeRejected = true; }
check(sizeRejected, "Oversized request must be rejected");
```

The tests use known valid request context and expected changes. Production APIs should return appropriate validation responses without exposing signing keys or sensitive payloads.

## 10. Query cost and consistency

Inspect a representative plan on the tiny fixture:

```javascript
printjson(lab.events.find({ tenantId: "T1", active: true })
  .sort({ createdAt: -1, _id: -1 }).limit(4).explain("executionStats"));
```

Record the actual index/scan/sort evidence. The lab does not assert a latency threshold. Deep skip traverses skipped results; seek still needs an appropriate filter/sort index and may have costs specific to its query shape.

For API totals, exact count queries can be expensive and need a consistency contract with the page read. Consider whether the user needs an exact total, estimated total or just a continuation indicator.

Keep sort fields immutable where possible. For stable exports, explicitly design snapshot/cutoff semantics and read concern rather than claiming pagination alone prevents omissions.

## 11. Troubleshooting

| Symptom | Evidence | Action |
|---|---|---|
| Repeated/missing rows | Offset changes and tie keys | Use the defined two-key seek contract |
| Same-timestamp records skipped | Continuation predicate | Include identifier comparison in the tie branch |
| Tenant data leaks | Authenticated scope and filter | Derive scope from identity; bind cursor to it |
| Cursor rejected after deployment | Key/query version/expiry | Provide reviewed rotation/version compatibility |
| New/backfilled records alter traversal | Cutoff and mutation semantics | Define consistency/export requirements |
| Query slow | Explain plan and supporting index | Align scope/filter/sort and bound page size |
| Token readable | Encoding versus encryption | Treat signed cursor as public metadata, not secret storage |

## 12. Acceptance and cleanup

```javascript
check(lab.events.countDocuments({ tenantId: "T1" }) === 8, "T1 fixtures restored");
check(lab.events.countDocuments({ tenantId: "T2" }) === 1, "T2 fixture preserved");
check(crossTenantRejected && tamperRejected && expiryRejected && sizeRejected,
  "API guard evidence");
print("PASS: signed scoped seek pagination, timestamp ties and offset failure demonstrations");
check(lab.getName() === "mongodb_enterprise_tutorial_ch15", "Unexpected cleanup database");
lab.events.drop();
check(!lab.getCollectionNames().includes("events"), "Cleanup failed");
print("PASS: Chapter 15 collection removed");
```

- [ ] Traverse all eight T1 records without ties being skipped.
- [ ] Verify page-size and projection bounds.
- [ ] Reproduce deletion/insertion offset shifts and restore fixtures.
- [ ] Reject wrong-tenant, tampered, expired and oversized requests.
- [ ] Record actual plan evidence.
- [ ] Explain why cutoff/seek is not a snapshot and verify cleanup.

**Authoring validation:** JavaScript syntax and official sort/skip guidance reviewed. Live mongosh/database execution remains pending; record exact versions, operator, date and outputs after running.

Review questions:

1. Why is a timestamp alone insufficient for this continuation?
2. Why does signing a cursor not authorize its tenant?
3. Which mutations can still affect seek traversal?
4. Why can a full exact count have different cost/consistency from a page?
5. What must key rotation preserve for existing cursors?

## Technical references

- [Cursor skip and range-query pagination — 8.0](https://www.mongodb.com/docs/v8.0/reference/method/cursor.skip/)
- [Cursor sort — 8.0](https://www.mongodb.com/docs/v8.0/reference/method/cursor.sort/)
- [Cursor limit — 8.0](https://www.mongodb.com/docs/v8.0/reference/method/cursor.limit/)
- [Read concern — 8.0](https://www.mongodb.com/docs/v8.0/reference/read-concern/)
- [Node.js crypto](https://nodejs.org/api/crypto.html)

Previous: [Chapter 14 — Advanced Aggregations and Joins](14-advanced-aggregations-and-joins.md).  
Next: [Chapter 16 — Transactions Sessions and Retry Semantics](16-transactions-sessions-and-retry-semantics.md).  
Return to the [master layout](MASTER-LAYOUT.md).
