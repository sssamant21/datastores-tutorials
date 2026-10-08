# Chapter 28 --- Redis Serialization, Compression & Value-Size Engineering

**Status:** Canonical\
**Track:** Redis Enterprise / Redis Software Production Engineering\
**Part:** Part 2 --- Caching & Application Engineering\
**Level:** Intermediate → Production Data Representation Engineering\
**Audience:** Developers, SREs, DBREs, Platform Engineers, Redis
Administrators\
**Lab type:** JSON serialization, compact encodings, schema/version
envelopes, value-size measurement, compression thresholds, CPU/network
tradeoffs, large-value detection, compatibility migration,
corruption/failure injection, observability, troubleshooting, runbooks,
and production acceptance

------------------------------------------------------------------------

# 1. Objective

Redis is fast, but application data representation can dominate memory,
network, and client CPU.

A cache entry is not only:

``` text
key -> object
```

It is closer to:

``` text
application object
 -> serialize
 -> optional compress
 -> network
 -> Redis memory
 -> network
 -> optional decompress
 -> deserialize
 -> application object
```

By the end, you should be able to:

-   Explain serialization overhead.
-   Measure encoded value size.
-   Compare JSON with compact/binary representations.
-   Design versioned cache payloads.
-   Prevent incompatible readers/writers.
-   Decide when compression is useful.
-   Select compression thresholds from measurements.
-   Understand CPU vs. network/memory tradeoffs.
-   Detect big values.
-   Avoid pathological nested payloads.
-   Design safe migrations between formats.
-   Handle corrupt or unknown payloads.
-   Observe serialization and compression costs.
-   Inject representation failures.
-   Troubleshoot production incidents.
-   Build runbooks and acceptance criteria.

------------------------------------------------------------------------

# 2. Core Production Principle

Do not optimize Redis value representation from assumptions.

Measure:

``` text
encoded bytes
Redis memory
network bytes
serialization latency
deserialization latency
compression latency
decompression latency
hit ratio
request latency
```

The smallest payload is not automatically the best payload if producing
it consumes excessive CPU or increases operational complexity.

------------------------------------------------------------------------

# Part 1 --- Serialization

## 3. What Serialization Does

Serialization converts an in-memory object into bytes that can be stored
or transported.

Examples:

``` text
JSON
MessagePack
Protocol Buffers
Avro
custom binary format
plain strings
```

The application owns the compatibility contract.

------------------------------------------------------------------------

# Part 2 --- JSON

## 4. Strengths

JSON is popular because it is:

``` text
human-readable
widely supported
easy to inspect
easy to debug
schema-flexible
```

------------------------------------------------------------------------

## 5. Costs

JSON can add overhead through:

``` text
field names repeated in every object
text representation
escaping
serialization CPU
deserialization CPU
```

Large nested JSON values can become expensive Redis objects.

------------------------------------------------------------------------

# Part 3 --- Compact/Binary Formats

## 6. Potential Benefits

Compact formats may reduce:

``` text
stored bytes
network bytes
parse overhead
```

depending on format and workload.

Tradeoffs include:

``` text
less human readability
schema/tooling requirements
compatibility complexity
debugging complexity
```

Benchmark the actual application format.

------------------------------------------------------------------------

# Part 4 --- Schema Version

## 7. Payload Contract

Cached data should have a version when representation may evolve.

Example envelope:

``` json
{
  "schema_version": 2,
  "payload": {
    "customer_id": 1001,
    "status": "active"
  }
}
```

A reader can then distinguish known and unknown representations.

------------------------------------------------------------------------

# Part 5 --- Codec Version

## 8. Separate Concerns

It can be useful to distinguish:

``` text
business schema version
encoding/codec version
compression algorithm
```

Example metadata:

``` text
schema=v3
codec=json
compression=gzip
```

Do not make readers guess.

------------------------------------------------------------------------

# Part 6 --- Key Versioning

## 9. Alternative Migration Pattern

Instead of changing the value under the same key:

``` text
customer:1001
```

use:

``` text
customer:v2:1001
customer:v3:1001
```

This can simplify staged migration.

Tradeoff:

``` text
temporary duplicate memory
```

------------------------------------------------------------------------

# Part 7 --- Dual Read

## 10. Migration

A migration can use:

``` text
read v3
if missing:
    read v2
    transform
    optionally populate v3
```

Bound migration traffic so it does not create a source or Redis load
spike.

------------------------------------------------------------------------

# Part 8 --- Dual Write

## 11. Caution

Writing both formats can support migration, but creates:

``` text
extra Redis operations
extra memory
consistency complexity
```

Use for a bounded migration period.

------------------------------------------------------------------------

# Part 9 --- Value Size

## 12. Application Bytes

Measure serialized payload bytes before sending them.

Python:

``` python
encoded = json.dumps(
    obj,
    separators=(",", ":"),
).encode("utf-8")

print(len(encoded))
```

------------------------------------------------------------------------

# Part 10 --- Redis Memory Usage

## 13. `MEMORY USAGE`

Redis can report approximate memory consumed by a key:

``` redis
MEMORY USAGE tutorial:chapter28:item:1
```

Stored memory is not necessarily equal to raw payload bytes because
Redis has internal representation and allocator overhead.

------------------------------------------------------------------------

# Part 11 --- Big Values

## 14. Why They Matter

Large values increase:

``` text
network transfer
client memory
serialization time
deserialization time
Redis memory
pipeline response size
replication/persistence traffic
```

They can also amplify hot-key problems.

------------------------------------------------------------------------

# Part 12 --- Full-Object Reads

## 15. Cost

If an application stores a 2 MB serialized object but needs one tiny
field, every read may transfer and decode the entire value.

Consider whether the data model should support more selective access.

------------------------------------------------------------------------

# Part 13 --- Redis Hashes

## 16. Partial Fields

For appropriate models:

``` redis
HSET customer:1001 name "A" status "active"
HGET customer:1001 status
```

may avoid retrieving an entire serialized object.

This is a data-model decision, not a universal replacement for
serialized values.

------------------------------------------------------------------------

# Part 14 --- Fragmentation of Application Objects

## 17. Avoid Overcorrection

Splitting one logical object into hundreds of tiny Redis keys can
create:

``` text
more metadata
more commands
more network round trips
more consistency work
```

Balance selective access against key/command overhead.

------------------------------------------------------------------------

# Part 15 --- Compression

## 18. Goal

Compression trades CPU for fewer bytes.

Potential benefits:

``` text
lower Redis memory
lower network transfer
lower replication/persistence bytes
```

Costs:

``` text
compression CPU
decompression CPU
latency
implementation complexity
```

------------------------------------------------------------------------

# Part 16 --- Compression Threshold

## 19. Do Not Compress Everything

Tiny values may become:

``` text
same size
larger
slower
```

after compression metadata and CPU overhead.

Use a measured threshold.

Example policy:

``` text
if serialized_size >= 8 KB:
    consider compression
else:
    store uncompressed
```

The threshold must come from benchmarks, not this example.

------------------------------------------------------------------------

# Part 17 --- Compression Ratio

## 20. Formula

``` text
compression ratio
=
compressed bytes / original bytes
```

Example:

``` text
original = 100 KB
compressed = 25 KB
ratio = 0.25
```

Savings:

``` text
75%
```

------------------------------------------------------------------------

# Part 18 --- Compressibility

## 21. Data Matters

Highly repetitive text often compresses well.

Already compressed/encrypted data may compress poorly.

Examples often poor:

``` text
JPEG
PNG
ZIP
encrypted blobs
many binary media formats
```

Avoid wasting CPU trying to recompress incompressible data.

------------------------------------------------------------------------

# Part 19 --- CPU vs. Network

## 22. Tradeoff

Compression may help when:

``` text
network is expensive
values are large
data compresses well
CPU has headroom
```

It may hurt when:

``` text
values are small
CPU is saturated
latency is extremely sensitive
data compresses poorly
```

------------------------------------------------------------------------

# Part 20 --- Compression Algorithm

## 23. Selection

Algorithms differ in:

``` text
compression ratio
compression speed
decompression speed
library support
compatibility
```

Choose from workload measurements and organizational standards.

Do not introduce a codec that operational tooling cannot support.

------------------------------------------------------------------------

# Part 21 --- Header / Envelope

## 24. Self-Describing Payload

A compact header can identify representation.

Concept:

``` text
magic
format version
codec
compression
payload
```

This allows readers to reject unsupported formats cleanly.

------------------------------------------------------------------------

# Part 22 --- Corruption

## 25. Invalid Payload

Possible causes:

``` text
application bug
partial migration
manual modification
wrong codec assumption
unexpected old format
```

On decode failure:

``` text
do not crash-loop
record bounded telemetry
invalidate/rebuild if safe
fall back to source if allowed
```

------------------------------------------------------------------------

# Part 23 --- Cache vs. Source of Truth

## 26. Recovery

For a derived cache, corrupt data can often be:

``` text
deleted
reloaded from authoritative source
```

For Redis used as authoritative state, deletion is not an acceptable
generic recovery strategy.

Know the role of the database.

------------------------------------------------------------------------

# Part 24 --- Deserialization Safety

## 27. Untrusted Formats

Avoid unsafe deserialization mechanisms that can execute arbitrary code
when payloads are untrusted or mutable by unintended actors.

Prefer well-defined data formats with validation.

------------------------------------------------------------------------

# Part 25 --- Validation

## 28. After Decode

Validate important fields:

``` text
schema version
required fields
types
bounds
business identifiers
```

A syntactically valid payload can still be semantically invalid.

------------------------------------------------------------------------

# Part 26 --- Null / Missing Semantics

## 29. Define Them

Distinguish:

``` text
cache miss
cached null
not found
decode failure
unsupported version
```

These states should not collapse into one ambiguous result.

------------------------------------------------------------------------

# Part 27 --- Negative Cache Payload

## 30. Explicit Marker

Example:

``` json
{
  "schema_version": 1,
  "state": "NOT_FOUND"
}
```

Use a short TTL according to Chapter 19 guidance.

Do not confuse source failure with authoritative not-found.

------------------------------------------------------------------------

# Part 28 --- Encryption

## 31. Compression Ordering

When both are required, compression is generally meaningful before
encryption because encrypted output is intentionally high entropy.

Security design must follow organizational requirements; do not weaken
encryption to improve compression.

------------------------------------------------------------------------

# Part 29 --- Pipelining Interaction

## 32. Chapter 27 Connection

Pipeline response memory is approximately influenced by:

``` text
number of values
×
encoded/compressed value size
```

Large uncompressed values can make a seemingly modest pipeline huge.

------------------------------------------------------------------------

# Part 30 --- Hot-Key Interaction

## 33. Chapter 18 Connection

A 1 MB value requested 5,000 times/sec is not merely a key-frequency
problem.

Approximate payload transfer:

``` text
1 MB × 5,000/sec
≈ 5 GB/sec
```

before protocol/transport effects.

Value size and popularity must be analyzed together.

------------------------------------------------------------------------

# Part 31 --- Cache Warming

## 34. Chapter 16 Connection

Warming thousands of large serialized values can consume:

``` text
source bandwidth
client CPU
Redis network
Redis memory
```

Bound warming concurrency and bytes/sec.

------------------------------------------------------------------------

# Part 32 --- Memory Pressure

## 35. Chapter 17 Connection

Large values reduce the number of entries that fit in memory and can
accelerate eviction.

Track both:

``` text
key count
bytes
```

------------------------------------------------------------------------

# Part 33 --- Observability

## 36. Size Metrics

Track distributions such as:

``` text
serialized_value_bytes
compressed_value_bytes
```

Prefer histograms/distributions rather than raw-key labels.

------------------------------------------------------------------------

## 37. Codec Latency

Track:

``` text
serialization_duration
deserialization_duration
compression_duration
decompression_duration
```

------------------------------------------------------------------------

## 38. Failure Metrics

Track:

``` text
decode_errors_total
unsupported_schema_total
compression_errors_total
decompression_errors_total
migration_fallback_total
```

------------------------------------------------------------------------

## 39. Ratio Metrics

Useful:

``` text
compression_ratio
compressed_fraction
large_value_fraction
```

------------------------------------------------------------------------

# Part 34 --- SLO Impact

## 40. End-to-End Latency

Cache latency should be decomposed:

``` text
pool wait
Redis/network
decompression
deserialization
application validation
```

A fast Redis command can still produce a slow cache read.

------------------------------------------------------------------------

# Part 35 --- Capacity Model

## 41. Memory

Estimate:

``` text
entry_count
×
average Redis memory per entry
```

Use representative `MEMORY USAGE` samples rather than raw JSON bytes
alone.

------------------------------------------------------------------------

## 42. Network

Estimate:

``` text
reads/sec × average response bytes
+
writes/sec × average request bytes
```

Then include replication and other infrastructure traffic separately
where relevant.

------------------------------------------------------------------------

## 43. Client CPU

Benchmark:

``` text
serialize/sec
deserialize/sec
compress/sec
decompress/sec
```

under realistic concurrency.

------------------------------------------------------------------------

# Part 36 --- Hands-On Lab

## 44. Objectives

You will:

1.  serialize representative JSON;
2.  compare pretty vs. compact JSON;
3.  measure Redis memory;
4.  compress values;
5.  calculate compression ratio;
6.  benchmark codec latency;
7.  test compression thresholds;
8.  implement a versioned envelope;
9.  simulate an unsupported schema;
10. simulate corrupt compressed data;
11. compare full-object and hash-field access;
12. clean up safely.

------------------------------------------------------------------------

## 45. Prerequisites

``` bash
python -m pip install redis
```

This lab uses Python standard-library:

``` text
json
gzip
zlib
```

------------------------------------------------------------------------

# Part 37 --- Environment

## 46. Variables

Windows CMD:

``` cmd
set REDIS_HOST=localhost
set REDIS_PORT=6379
set REDIS_PASSWORD=
```

PowerShell:

``` powershell
$env:REDIS_HOST="localhost"
$env:REDIS_PORT="6379"
$env:REDIS_PASSWORD=""
```

Linux/macOS:

``` bash
export REDIS_HOST=localhost
export REDIS_PORT=6379
export REDIS_PASSWORD=''
```

------------------------------------------------------------------------

# Part 38 --- Main Lab

## 47. Create `chapter28_value_engineering_lab.py`

``` python
import gzip
import json
import os
import statistics
import time
import zlib

import redis

HOST = os.getenv("REDIS_HOST", "localhost")
PORT = int(os.getenv("REDIS_PORT", "6379"))
PASSWORD = os.getenv("REDIS_PASSWORD") or None

r = redis.Redis(
    host=HOST,
    port=PORT,
    password=PASSWORD,
    decode_responses=False,
)

PREFIX = b"tutorial:chapter28:"


def make_record():
    return {
        "schema_version": 1,
        "customer_id": 1001,
        "status": "active",
        "name": "Example Customer",
        "tags": [
            "healthcare",
            "production",
            "redis",
            "cache",
        ],
        "description":
            "Redis Enterprise value engineering "
            * 200,
        "preferences": {
            "language": "en",
            "timezone": "America/New_York",
            "notifications": True,
        },
    }


def compact_json(obj):
    return json.dumps(
        obj,
        separators=(",", ":"),
        ensure_ascii=False,
    ).encode("utf-8")


def pretty_json(obj):
    return json.dumps(
        obj,
        indent=2,
        ensure_ascii=False,
    ).encode("utf-8")


def ratio(
    compressed,
    original,
):
    return (
        len(compressed)
        / len(original)
    )


def benchmark(
    func,
    value,
    iterations=1000,
):
    samples = []

    for _ in range(iterations):
        start = time.perf_counter()
        func(value)
        samples.append(
            time.perf_counter() - start
        )

    return {
        "avg_us":
            statistics.mean(samples)
            * 1_000_000,
        "p95_us":
            sorted(samples)[
                int(len(samples) * 0.95) - 1
            ]
            * 1_000_000,
    }


record = make_record()

pretty = pretty_json(record)
compact = compact_json(record)
gzip_value = gzip.compress(compact)
zlib_value = zlib.compress(compact)

print("PING:", r.ping())
print()
print("VALUE SIZES")
print("pretty JSON:", len(pretty))
print("compact JSON:", len(compact))
print("gzip:", len(gzip_value))
print("zlib:", len(zlib_value))
print(
    "gzip ratio:",
    round(
        ratio(gzip_value, compact),
        3,
    ),
)
print(
    "zlib ratio:",
    round(
        ratio(zlib_value, compact),
        3,
    ),
)

r.set(
    PREFIX + b"pretty",
    pretty,
)

r.set(
    PREFIX + b"compact",
    compact,
)

r.set(
    PREFIX + b"gzip",
    gzip_value,
)

r.set(
    PREFIX + b"zlib",
    zlib_value,
)

print()
print("REDIS MEMORY USAGE")

for name in [
    b"pretty",
    b"compact",
    b"gzip",
    b"zlib",
]:
    key = PREFIX + name

    print(
        key.decode(),
        r.memory_usage(key),
    )

print()
print("CODEC BENCHMARK")

print(
    "json encode:",
    benchmark(
        compact_json,
        record,
    ),
)

print(
    "json decode:",
    benchmark(
        json.loads,
        compact,
    ),
)

print(
    "gzip compress:",
    benchmark(
        gzip.compress,
        compact,
    ),
)

print(
    "gzip decompress:",
    benchmark(
        gzip.decompress,
        gzip_value,
    ),
)

print(
    "zlib compress:",
    benchmark(
        zlib.compress,
        compact,
    ),
)

print(
    "zlib decompress:",
    benchmark(
        zlib.decompress,
        zlib_value,
    ),
)
```

------------------------------------------------------------------------

# Part 39 --- Run Lab

## 48. Execute

``` bash
python chapter28_value_engineering_lab.py
```

Record:

``` text
raw bytes
compressed bytes
Redis MEMORY USAGE
codec latency
```

Do not assume your results match other workloads.

------------------------------------------------------------------------

# Part 40 --- Compression Threshold Lab

## 49. Test Multiple Sizes

Generate payloads around:

``` text
100 B
1 KB
4 KB
8 KB
16 KB
64 KB
256 KB
1 MB
```

For each size record:

``` text
compressed ratio
compression time
decompression time
Redis memory
```

Select a threshold from observed tradeoffs.

------------------------------------------------------------------------

# Part 41 --- Threshold Function

## 50. Example

``` python
def encode_value(
    obj,
    threshold=8192,
):
    raw = compact_json(obj)

    if len(raw) >= threshold:
        return (
            b"G1:"
            + gzip.compress(raw)
        )

    return b"J1:" + raw
```

Here:

``` text
J1 = JSON schema/codec marker
G1 = gzip-compressed JSON marker
```

This is a lab convention, not a Redis standard.

------------------------------------------------------------------------

# Part 42 --- Decoder

## 51. Example

``` python
def decode_value(value):
    if value.startswith(b"J1:"):
        raw = value[3:]

    elif value.startswith(b"G1:"):
        raw = gzip.decompress(
            value[3:]
        )

    else:
        raise ValueError(
            "unsupported codec"
        )

    obj = json.loads(raw)

    if obj.get(
        "schema_version"
    ) != 1:
        raise ValueError(
            "unsupported schema"
        )

    return obj
```

Readers should fail explicitly on unknown formats.

------------------------------------------------------------------------

# Part 43 --- Corruption Lab

## 52. Invalid Compressed Payload

``` python
bad = b"G1:not-valid-gzip"

try:
    decode_value(bad)
except Exception as exc:
    print(
        "expected decode failure:",
        type(exc).__name__,
    )
```

Production handling should distinguish:

``` text
decode failure
cache miss
source failure
```

------------------------------------------------------------------------

# Part 44 --- Unsupported Version Lab

## 53. Test

Store:

``` json
{
  "schema_version": 999,
  "customer_id": 1001
}
```

Confirm the reader does not silently interpret it as schema version 1.

------------------------------------------------------------------------

# Part 45 --- Hash Access Lab

## 54. Partial Read

``` redis
HSET tutorial:chapter28:customer:1001 status active name "Example Customer"
HGET tutorial:chapter28:customer:1001 status
```

Compare the bytes transferred with retrieving a large whole-object JSON
value when only `status` is needed.

Do not infer that hashes are always better; model according to access
patterns.

------------------------------------------------------------------------

# Part 46 --- Migration Lab

## 55. v2 to v3

Concept:

``` text
GET customer:v3:1001

if miss:
    GET customer:v2:1001
    decode v2
    transform to v3
    SET customer:v3:1001
```

Measure migration fallback rate.

Avoid allowing every cache miss to perform expensive conversion without
bounds.

------------------------------------------------------------------------

# Part 47 --- Failure Injection

## 56. Failure 1 --- Oversized JSON

Create a deeply/repetitively populated test object in a disposable
namespace.

Observe:

``` text
serialized bytes
Redis memory
read latency
decode CPU
```

------------------------------------------------------------------------

## 57. Failure 2 --- Compress Tiny Values

Compress many tiny payloads.

Observe whether:

``` text
bytes saved
```

justify CPU and framing overhead.

------------------------------------------------------------------------

## 58. Failure 3 --- Incompressible Data

Test random/already-compressed bytes.

Observe poor compression ratio.

Do not spend CPU compressing data that does not benefit.

------------------------------------------------------------------------

## 59. Failure 4 --- Corrupt Payload

Store malformed data under a lab key.

Confirm:

``` text
bounded error
telemetry
safe fallback
```

instead of crash loops.

------------------------------------------------------------------------

## 60. Failure 5 --- Unknown Schema

Store an unsupported schema version.

Confirm the reader rejects it explicitly.

------------------------------------------------------------------------

## 61. Failure 6 --- Mixed Writers

Simulate one writer producing v1 while another writes v2 to the same
unversioned key.

Observe compatibility risk.

Use versioned envelope/key migration.

------------------------------------------------------------------------

## 62. Failure 7 --- Large Pipeline Responses

Pipeline many large values.

Observe:

``` text
client memory
network
batch latency
```

Connect this result to Chapter 27.

------------------------------------------------------------------------

## 63. Failure 8 --- Hot Big Value

Repeatedly read one large value.

Observe:

``` text
network
client CPU
Redis traffic
```

Connect this result to Chapter 18.

------------------------------------------------------------------------

## 64. Failure 9 --- Compression CPU Saturation

Increase compression concurrency in a disposable application test.

Observe client CPU and request latency.

Compression can move the bottleneck from network to application CPU.

------------------------------------------------------------------------

## 65. Failure 10 --- Migration Storm

Simulate many readers missing v3 and falling back to v2 simultaneously.

Observe:

``` text
extra Redis reads
conversion CPU
write-back traffic
```

Bound migration concurrency and pre-warm where appropriate.

------------------------------------------------------------------------

# Part 48 --- Troubleshooting

## 66. Redis Memory Higher Than Expected

Check:

``` text
raw payload size
MEMORY USAGE
key length
object representation
allocator overhead
duplicate versions
compression policy
```

------------------------------------------------------------------------

## 67. Network High

Check:

``` text
value-size distribution
hot keys
read QPS
pipeline response bytes
compression coverage
```

------------------------------------------------------------------------

## 68. Application CPU High

Check:

``` text
JSON encode/decode
compression/decompression
object allocation
large nested values
request concurrency
```

------------------------------------------------------------------------

## 69. Cache Read Slow but Redis Fast

Break down:

``` text
Redis/network
decompression
deserialization
validation
```

The bottleneck may be outside Redis execution.

------------------------------------------------------------------------

## 70. Decode Errors After Deployment

Check:

``` text
writer version
reader version
schema version
codec marker
compression marker
deployment order
```

Stop incompatible writers if necessary.

------------------------------------------------------------------------

## 71. Memory Doubled During Migration

Check whether both:

``` text
v2
v3
```

keys coexist.

Confirm TTL and retirement plan for old versions.

------------------------------------------------------------------------

## 72. Compression Does Not Save Memory

Check:

``` text
payload size
compressibility
Redis MEMORY USAGE
framing overhead
algorithm
```

Raw byte reduction may not map one-to-one to allocator memory reduction
for small values.

------------------------------------------------------------------------

## 73. Large-Value P99

Check:

``` text
value bytes
network
client decode CPU
pipeline size
hotness
pool wait
```

------------------------------------------------------------------------

# Part 49 --- Production Runbooks

## 74. Runbook --- Big-Value Incident

``` text
1. Identify affected key pattern.
2. Measure value bytes.
3. Measure MEMORY USAGE samples.
4. Measure read/write rate.
5. Check hot-key concentration.
6. Check network.
7. Check client decode CPU.
8. Reduce payload/model safely.
9. Validate compatibility.
10. Confirm P99 and memory recover.
```

------------------------------------------------------------------------

## 75. Runbook --- Decode Failure Spike

``` text
1. Identify reader/writer versions.
2. Capture codec/schema metadata.
3. Classify malformed vs. unsupported.
4. Stop incompatible writes if needed.
5. Preserve source-of-truth safety.
6. Invalidate derived corrupt cache only if safe.
7. Rebuild using supported format.
8. Monitor fallback traffic.
9. Verify error rate clears.
10. Add compatibility test.
```

------------------------------------------------------------------------

## 76. Runbook --- Compression CPU Regression

``` text
1. Measure compression/decompression CPU.
2. Measure value-size distribution.
3. Measure compression ratio.
4. Check threshold.
5. Check algorithm/settings.
6. Compare network savings.
7. Raise threshold or change policy if justified.
8. Load-test.
9. Verify latency.
10. Document selected tradeoff.
```

------------------------------------------------------------------------

## 77. Runbook --- Schema Migration

``` text
1. Define old/new schema.
2. Define reader compatibility.
3. Deploy compatible readers first.
4. Introduce versioned writes.
5. Monitor fallback.
6. Bound conversion/write-back.
7. Pre-warm if needed.
8. Retire old writes.
9. Expire/remove old cache safely.
10. Remove fallback after validation.
```

------------------------------------------------------------------------

## 78. Runbook --- Network Saturation From Values

``` text
1. Measure Redis network.
2. Measure value-size distribution.
3. Identify hot patterns.
4. Measure QPS.
5. Check pipeline response size.
6. Evaluate compression.
7. Evaluate selective field access.
8. Protect Redis/client capacity.
9. Load-test redesign.
10. Confirm network headroom.
```

------------------------------------------------------------------------

# Part 50 --- Value Design Template

## 79. Fields

``` text
Key pattern:
Data owner:
Redis role:
Serialization format:
Schema version:
Codec version:
Compression:
Compression threshold:
Average raw bytes:
P95 raw bytes:
P99 raw bytes:
Average Redis MEMORY USAGE:
Read QPS:
Write QPS:
Hot-key risk:
Partial-field access needed:
TTL:
Migration strategy:
Unknown-version behavior:
Decode-failure behavior:
Metrics:
Owner:
```

------------------------------------------------------------------------

# Part 51 --- Compression Benchmark Template

## 80. Record

  -------------------------------------------------------------------------------
  Payload    Raw bytes   Compressed      Ratio   Compress   Decompress      Redis
                              bytes                   P95          P95     memory
  --------- ---------- ------------ ---------- ---------- ------------ ----------
  1 KB                                                                 

  4 KB                                                                 

  8 KB                                                                 

  16 KB                                                                

  64 KB                                                                

  256 KB                                                               

  1 MB                                                                 
  -------------------------------------------------------------------------------

Use production-like data, not repeated-character-only synthetic
payloads.

------------------------------------------------------------------------

# Part 52 --- Decision Guide

## 81. Keep Plain JSON When

``` text
payloads are reasonably small
human inspection is valuable
CPU/latency is acceptable
memory/network headroom exists
compatibility simplicity matters
```

------------------------------------------------------------------------

## 82. Consider Compact/Binary Encoding When

``` text
payload volume is large
network/memory cost matters
schema/tooling is mature
measured benefit is meaningful
```

------------------------------------------------------------------------

## 83. Consider Compression When

``` text
payload exceeds measured threshold
compression ratio is useful
CPU has headroom
network/memory savings matter
```

------------------------------------------------------------------------

## 84. Avoid Compression When

``` text
payload is tiny
data is already compressed/encrypted
ratio is poor
CPU/latency cost exceeds savings
```

------------------------------------------------------------------------

# Production Acceptance Checklist

## 85. Value Engineering

-   [ ] Serialization format documented.
-   [ ] Schema version documented.
-   [ ] Codec/compression marker documented.
-   [ ] Average/P95/P99 value sizes measured.
-   [ ] Redis `MEMORY USAGE` sampled.
-   [ ] Big-value threshold defined operationally.
-   [ ] Serialization latency measured.
-   [ ] Deserialization latency measured.
-   [ ] Compression ratio measured.
-   [ ] Compression latency measured.
-   [ ] Decompression latency measured.
-   [ ] Compression threshold benchmarked.
-   [ ] Incompressible payload behavior tested.
-   [ ] Unknown schema behavior tested.
-   [ ] Corrupt payload behavior tested.
-   [ ] Cache-miss vs. decode-failure semantics separated.
-   [ ] Partial-field access reviewed.
-   [ ] Pipeline response impact reviewed.
-   [ ] Hot-big-key risk reviewed.
-   [ ] Migration strategy tested.
-   [ ] Mixed-version deployment tested.
-   [ ] Migration traffic bounded.
-   [ ] Observability available.
-   [ ] Production runbooks validated.

------------------------------------------------------------------------

# Knowledge Validation

## 86. Questions

You should be able to answer:

1.  What is serialization?
2.  Why can JSON consume more bytes than compact formats?
3.  Why is JSON still useful operationally?
4.  Why version cached payloads?
5.  What is the difference between schema and codec version?
6.  How can key versioning simplify migration?
7.  What is dual read?
8.  What are the costs of dual write?
9.  Why measure encoded bytes before Redis?
10. What does `MEMORY USAGE` tell you?
11. Why can Redis memory exceed raw payload bytes?
12. Why are big values operationally expensive?
13. When can Redis hashes help selective access?
14. Why not split every field into its own key?
15. What does compression trade?
16. Why use a compression threshold?
17. What is compression ratio?
18. Why are encrypted/compressed formats poor compression candidates?
19. Why should payloads identify their codec?
20. How should a derived cache handle corrupt values?
21. Why is unsafe object deserialization dangerous?
22. Why distinguish cached null from cache miss?
23. How do large values affect pipelines?
24. How do hot keys and value size interact?
25. Why can cache warming of large values be dangerous?
26. Which codec metrics should be monitored?
27. Why can Redis be fast while cache reads remain slow?
28. Why can migration temporarily double memory?
29. Why must mixed-version deployments be tested?
30. What must pass before a value format is production-ready?

------------------------------------------------------------------------

# Hands-On Acceptance Checklist

## 87. Lab Completion

-   [ ] Serialized representative JSON.
-   [ ] Compared pretty and compact JSON.
-   [ ] Stored encoded values.
-   [ ] Measured `MEMORY USAGE`.
-   [ ] Tested gzip.
-   [ ] Tested zlib.
-   [ ] Calculated compression ratios.
-   [ ] Benchmarked serialization.
-   [ ] Benchmarked deserialization.
-   [ ] Benchmarked compression.
-   [ ] Benchmarked decompression.
-   [ ] Tested multiple payload sizes.
-   [ ] Evaluated compression threshold.
-   [ ] Implemented codec marker.
-   [ ] Implemented schema validation.
-   [ ] Injected corrupt payload.
-   [ ] Injected unknown schema.
-   [ ] Tested hash partial-field access.
-   [ ] Reviewed v2→v3 migration.
-   [ ] Tested ten failure scenarios.
-   [ ] Completed troubleshooting.
-   [ ] Reviewed five production runbooks.
-   [ ] Completed value design template.
-   [ ] Completed compression benchmark table.
-   [ ] Completed production acceptance checklist.

------------------------------------------------------------------------

# 88. Lab Cleanup

Discover:

``` bash
redis-cli --scan --pattern 'tutorial:chapter28:*'
```

Delete only confirmed Chapter 28 training keys in bounded batches using
`UNLINK`.

Examples:

``` redis
UNLINK tutorial:chapter28:pretty
UNLINK tutorial:chapter28:compact
UNLINK tutorial:chapter28:gzip
UNLINK tutorial:chapter28:zlib
UNLINK tutorial:chapter28:customer:1001
```

Do not use:

``` redis
KEYS tutorial:chapter28:*
FLUSHDB
FLUSHALL
```

against a shared or production database.

------------------------------------------------------------------------

# 89. Key Takeaways

1.  Redis performance includes application serialization and
    deserialization cost.
2.  Measure value bytes and Redis memory rather than estimating from
    object shape.
3.  JSON is operationally convenient but may have size and CPU overhead.
4.  Compact/binary formats should be adopted only after measured
    benefit.
5.  Version payload schemas and codecs explicitly.
6.  Versioned keys and dual-read patterns can make migrations safer.
7.  Compression trades CPU and complexity for fewer bytes.
8.  Compress only when measured payload size and compressibility justify
    it.
9.  Large values increase memory, network, pipeline, replication, and
    client costs.
10. Selective data access can be better than repeatedly decoding huge
    whole objects.
11. Do not fragment data into excessive tiny keys without considering
    command/key overhead.
12. Corrupt and unsupported payloads need explicit handling.
13. Derived-cache corruption can often be rebuilt from the source of
    truth; authoritative Redis data requires a different recovery model.
14. Distinguish cache miss, negative cache, decode failure, and
    unsupported schema.
15. Large hot values combine frequency and byte-volume risks.
16. Compression can move the bottleneck from network to client CPU.
17. Schema migrations can temporarily increase Redis memory and traffic.
18. Observability should include bytes, codec latency, failures, and
    compression ratios.
19. Test mixed application versions before production rollout.
20. Production value design is a capacity, compatibility, and
    reliability decision---not merely a serialization-library choice.

------------------------------------------------------------------------

# 90. References

Validate exact memory, data-type, client, serialization, and compression
behavior against the Redis, Redis Enterprise, and application-library
versions deployed.

Recommended official Redis documentation areas:

-   `MEMORY USAGE`
-   Redis strings
-   Redis hashes
-   Redis memory optimization
-   Redis pipelining
-   Redis latency monitoring
-   Redis Enterprise monitoring
-   Redis Enterprise memory management

Also validate the official documentation for whichever serialization and
compression libraries your application actually uses.

------------------------------------------------------------------------

# Next Chapter

**Chapter 29 --- Redis Key Naming, Namespaces & Keyspace Design**

Chapter 29 will cover:

-   key naming conventions
-   service namespaces
-   environment isolation
-   tenant identifiers
-   key length tradeoffs
-   versioned keys
-   hash tags
-   cluster slot placement
-   hot-slot prevention
-   TTL ownership
-   discoverability
-   safe `SCAN`
-   operational cleanup
-   migration
-   observability
-   failure injection
-   troubleshooting
-   production runbooks
-   acceptance validation
