# 23 — Change Streams and Event Recovery

**Status:** Draft; live lab not run.

**Objective:** Observe changes and design restart-safe event processing.

Change streams work on replica sets/sharded clusters and expose majority-committed changes. They are not an unlimited event archive. Resume depends on available history, scope and compatible options.

## Two-session lab

Use a staging replica set with watch permissions and a precreated regular tutorial_events collection. Session A:
```javascript
var eventsDb = db.getSiblingDB("mongodb_tutorials")
var eventStream = eventsDb.tutorial_events.watch([], {
  fullDocument: "updateLookup", maxAwaitTimeMS: 1000
})
```
Session B:
```javascript
db.getSiblingDB("mongodb_tutorials").tutorial_events.insertOne({
  _id: "tutorial-event-check", status: "created"
})
```
Session A, after the insert:
```javascript
var event = eventStream.tryNext()
printjson(event)
var eventToken = event?._id
```
If null, call tryNext again after checking topology/permissions and write outcome. Save the full BSON token securely with the consumer checkpoint; do not parse or modify it.

Close and resume in A after a non-null event:
```javascript
eventStream.close()
if (!eventToken) throw new Error("No token captured")
var resumedStream = eventsDb.tutorial_events.watch([], {
  resumeAfter: eventToken, fullDocument: "updateLookup", maxAwaitTimeMS: 1000
})
```
Update the marker in B; use resumedStream.tryNext() in A and verify the update arrives after the checkpoint. updateLookup retrieves the current majority-committed document and need not represent the exact event-time image. It can be null if the document no longer exists.

## Consumer recovery

Process idempotently, then checkpoint after durable downstream success. A crash between those steps can replay an event. Use deduplication/business keys or an atomic downstream event/checkpoint transaction where supported. Never claim exactly-once delivery from watch alone.

Expired history: stop, alert, perform a consistent baseline/reconciliation and establish a new stream position. Do not silently skip the gap. Handle invalidate events with documented resume/startAfter rules. Monitor processing lag, checkpoint age and retained history.

Cleanup: close resumedStream, then delete only tutorial-event-check in B. No infinite polling is required by this lab.

## References

- [Change streams and resume rules](https://www.mongodb.com/docs/manual/changeStreams/)

**Next:** [24 — Time Series, Capped Collections, and GridFS](24-time-series-capped-collections-and-gridfs.md).
