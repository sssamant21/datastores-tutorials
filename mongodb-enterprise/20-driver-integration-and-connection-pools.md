# 20 — Driver Integration and Connection Pools

**Status:** Draft; live lab not run.

**Objective:** Connect an application securely and distinguish timeout/retry behavior.

Use a compatible official driver. Reuse a MongoClient for a process lifetime; avoid one client per request. Pool capacity is per server and multiplies across processes/pods, with additional monitoring connections. Size against concurrency and server capacity.

## Python lab

Install a compatible PyMongo version in an isolated environment. On Windows: py -m pip install pymongo. Set MONGODB_URI to a credential-free staging replica-set URI and MONGODB_CA_FILE to the trusted CA path. This example assumes a SCRAM user in admin; change authSource to match your identity.

```python
import os
from getpass import getpass
from bson import ObjectId
from pymongo import MongoClient
from pymongo.write_concern import WriteConcern

client = MongoClient(
    os.environ["MONGODB_URI"],
    username=input("MongoDB username: "), password=getpass(),
    authSource="admin", tls=True,
    tlsCAFile=os.environ["MONGODB_CA_FILE"],
    appname="tutorial-driver-lab",
    maxPoolSize=20, waitQueueTimeoutMS=2000,
    serverSelectionTimeoutMS=5000, connectTimeoutMS=5000,
    retryWrites=True,
)
marker = ObjectId()
try:
    client.admin.command("ping")
    coll = client.mongodb_tutorials.tutorial_driver.with_options(
        write_concern=WriteConcern(w="majority", wtimeout=5000)
    )
    coll.insert_one({"_id": marker, "message": "driver-check"})
    found = coll.find_one({"_id": marker}, max_time_ms=2000)
    if found is None or found["message"] != "driver-check":
        raise RuntimeError("Read verification failed")
    coll.delete_one({"_id": marker})
finally:
    client.close()
```

Example values are lab limits, not production defaults. If an exception occurs, preserve the marker ID privately and inspect the outcome before cleanup/retry; finally closes the client but does not erase failed-run data.

## Timeouts and retries

| Setting | Limits |
|---|---|
| serverSelectionTimeoutMS | Finding a suitable server |
| connectTimeoutMS | Establishing a connection |
| waitQueueTimeoutMS | Waiting for a pool connection |
| maxTimeMS | Server-side operation execution |
| Client operation deadline | Overall time budget; driver-version-specific |

An eligible retryable write uses driver/server support; an arbitrary manual replay can duplicate effects. Capture exception class, labels, operation ID and application deadline. Preserve majority/consistency requirements when tuning.

Exercise: run representative concurrency; measure checkout wait, connection counts, latency and errors. Compare pool exhaustion with slow server operations before increasing pool size. Never log URI secrets.

## References

- [PyMongo pools](https://www.mongodb.com/docs/languages/python/pymongo-driver/current/connect/connection-options/connection-pools/)
- [Retryable writes](https://www.mongodb.com/docs/manual/core/retryable-writes/)

**Next:** [21 — Advanced Modeling and Schema Evolution](21-advanced-modeling-and-schema-evolution.md).
