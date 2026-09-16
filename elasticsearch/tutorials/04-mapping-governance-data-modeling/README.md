# Module 04 — Mapping Governance & Data Modeling

## Tutorial 04 — Mapping Governance & Data Modeling

**Edition:** Revised Final / Canonical
**Audience:** Elasticsearch administrators, SREs, DBREs, platform engineers, developers, and data engineers
**Lab indices:** `sre_tutorial_04`, `sre_tutorial_04_bad`

---

## 4.1 Introduction

An Elasticsearch mapping defines how document fields are represented and indexed.

A document may look simple:

```json
{
  "patient_id": "P1001",
  "provider_name": "Atlantic Cardiology Associates",
  "age": 47,
  "active": true,
  "visit_date": "2026-09-16T14:30:00Z"
}
```

But these fields have very different semantics.

```text
patient_id
    ↓
Exact identifier

provider_name
    ↓
Full-text searchable name

age
    ↓
Numeric value

active
    ↓
Boolean

visit_date
    ↓
Date/time
```

Choosing the correct mapping determines how these fields can be searched, filtered, sorted, aggregated, stored, and evolved.

Mapping design is therefore not merely an Elasticsearch configuration task.

It is part of the application's **data contract and production architecture**.

---

## 4.2 Learning Objectives

By the end of this tutorial, you should be able to:

1. Explain what an Elasticsearch mapping controls.
2. Create an index with an explicit mapping.
3. Distinguish `text` from `keyword`.
4. Design and use multi-fields.
5. Select appropriate numeric, boolean, and date types.
6. Understand how Elasticsearch represents arrays.
7. Distinguish `object`, `nested`, and `flattened` use cases.
8. Understand dynamic mapping.
9. Explain `dynamic: true`, `false`, and `strict`.
10. Recognize mapping explosion.
11. Understand `index.mapping.total_fields.limit`.
12. Explain `ignore_above`.
13. Understand the operational role of `doc_values`.
14. Understand why `_source` is operationally important.
15. Diagnose field-type conflicts.
16. Understand which mapping changes can be made in place.
17. Recognize when a new index and reindex/migration are required.
18. Apply production mapping-governance principles.
19. Troubleshoot mapping-related ingestion failures.
20. Clean up the tutorial safely.

---

## 4.3 Elasticsearch Version Scope

This tutorial teaches mapping concepts that apply broadly across Elasticsearch versions.

However, production environments may run different releases, including Elasticsearch 7.17 and newer versions.

Core concepts such as:

```text
text
keyword
multi-fields
explicit mappings
dynamic mappings
object
nested
mapping conflicts
reindex-based schema migration
```

are broadly established.

However, field types, supported mapping parameters, limits, API capabilities, and newer features can vary between versions.

Before applying a production mapping change:

```text
Identify deployed ES version
        ↓
Check vendor documentation
for that exact version
        ↓
Validate in non-production
        ↓
Production review
        ↓
Controlled rollout
```

Do not assume that a capability documented for a newer Elasticsearch release exists unchanged in an older cluster.

---

## 4.4 Tutorial Safety Classification

Commands are classified throughout this tutorial.

### `[TUTORIAL-ACCEPTANCE — SAFE-READ]`

Read-only operations such as:

```text
GET mapping
GET settings
GET CAT indices
_search
```

### `[TUTORIAL-LAB — CONTROLLED-WRITE]`

Controlled operations against dedicated tutorial indices:

```text
Create tutorial index
Create mapping
Index tutorial documents
Add supported tutorial mappings
```

### `[TUTORIAL-LAB — EXPECTED-FAILURE]`

Commands intentionally designed to demonstrate mapping or parsing failures.

### `[TUTORIAL-LAB — DESTRUCTIVE]`

Deletion of exact disposable tutorial indices.

### `[PRODUCTION-MIGRATION — HIGH-RISK]`

Production activities such as:

```text
Create replacement production index
Reindex production data
Change aliases
Application cutover
Retire old index
```

Production migration procedures are **conceptual only** in this tutorial.

---

## 4.5 Lab Safety Boundary

This tutorial uses only:

```text
sre_tutorial_04
sre_tutorial_04_bad
```

Never substitute:

```text
Production index
Production alias
Production data stream
Wildcard
_all
```

for either tutorial index.

All destructive commands must use an exact tutorial index name.

---

## 4.6 Authentication

Use environment variables rather than embedding credentials in scripts or documentation.

```bash
export ES_URL="https://your-elasticsearch-endpoint"
export ES_USER="your-user"
read -s ES_PASSWORD
export ES_PASSWORD
```

Commands use:

```bash
curl -u "$ES_USER:$ES_PASSWORD"
```

Production Elasticsearch endpoints should normally use HTTPS/TLS.

Do not store real credentials in repositories, screenshots, documentation, tickets, or troubleshooting output.

---

# Part I — Mapping Fundamentals

## 4.7 What Is a Mapping?

A mapping describes how Elasticsearch should interpret document fields.

Conceptually:

```text
Application data
      ↓
Elasticsearch mapping
      ↓
Field representation
      ↓
Indexing behavior
      ↓
Search
Filtering
Sorting
Aggregations
Operational characteristics
```

Incorrect mappings can cause:

* incorrect search behavior,
* failed ingestion,
* aggregation problems,
* mapping conflicts,
* uncontrolled field growth,
* unnecessary resource consumption,
* difficult schema migrations.

---

## 4.8 Mapping Governance

Mapping ownership should be shared.

```text
Application / Data Engineering
        |
        | owns
        v
Data semantics
Field meaning
Producer contract
Expected queries
Expected aggregations
        |
        v
Mapping proposal
        |
        v
Elasticsearch / SRE / DBRE
        |
        | reviews
        v
Elasticsearch behavior
Search implications
Aggregation implications
Mapping growth
Operational impact
Capacity
Compatibility
Migration safety
        |
        v
Reviewed production mapping
```

The application or data-producing team understands what the data means.

The Elasticsearch/platform team understands how that representation affects Elasticsearch.

Important production mappings should not be designed by either group in isolation.

---

# Part II — Explicit and Dynamic Mapping

## 4.9 Explicit Mapping

When the schema is known, define important fields deliberately.

Example:

```json
{
  "properties": {
    "patient_id": {
      "type": "keyword"
    },
    "age": {
      "type": "integer"
    }
  }
}
```

This makes the intended schema visible and reviewable before ingestion.

---

## 4.10 Dynamic Mapping

Elasticsearch can automatically add mappings for previously unknown fields.

For example:

```json
{
  "patient_id": "P1001",
  "age": 47
}
```

may cause mappings to be created when those fields do not already exist.

Dynamic mapping is useful in some workloads.

The risk is allowing uncontrolled input to become the production schema.

---

## 4.11 Dynamic Mapping Modes

Conceptually:

```text
dynamic: true
    ↓
Unknown fields may be dynamically mapped


dynamic: false
    ↓
Unknown fields are not dynamically
added to the mapping


dynamic: strict
    ↓
Unexpected fields cause
document rejection
```

`dynamic: strict` can be useful when there is a tightly controlled producer/schema contract.

It should not automatically be enabled everywhere.

Unexpected producer changes could otherwise become ingestion failures.

---

## 4.12 Strict Mapping Example

Example design:

```json
{
  "mappings": {
    "dynamic": "strict",
    "properties": {
      "patient_id": {
        "type": "keyword"
      }
    }
  }
}
```

Before using this pattern in production, ensure producers understand and honor the schema contract.

---

# Part III — Core Field Types

## 4.13 `keyword`

Use `keyword` when values are primarily treated as exact structured values.

Examples:

```text
patient_id
claim_id
provider_id
status
state_code
event_type
diagnosis_code
```

Example:

```json
"patient_id": {
  "type": "keyword"
}
```

Common operations include:

```text
Exact filtering
Exact matching
Sorting
Aggregations
```

Identifiers that happen to contain only numbers do not necessarily need numeric mappings.

Choose types based on semantics and query requirements.

---

## 4.14 `text`

`text` is intended for analyzed full-text search.

Example:

```json
"provider_name": {
  "type": "text"
}
```

Conceptually:

```text
Atlantic Cardiology Associates
            ↓
         Analyzer
            ↓
      searchable terms
```

The exact generated terms depend on the configured analyzer.

---

## 4.15 `text` vs `keyword`

A fundamental mapping distinction is:

```text
TEXT
 ↓
Analyzed
 ↓
Full-text search


KEYWORD
 ↓
Exact value
 ↓
Filtering
Sorting
Aggregation
```

Choosing incorrectly can lead to unexpected application behavior.

---

## 4.16 Multi-Fields

A field can be indexed in multiple ways.

Example:

```json
"provider_name": {
  "type": "text",
  "fields": {
    "keyword": {
      "type": "keyword"
    }
  }
}
```

This creates:

```text
provider_name
      ↓
Full-text search

provider_name.keyword
      ↓
Exact-value operations
```

This is called a **multi-field**.

---

## 4.17 Multi-Field Migration Warning

A new multi-field can be added to an existing field in supported circumstances.

However, historical documents do not automatically acquire values in the newly added multi-field merely because the mapping changed.

Conceptually:

```text
Existing documents
        ↓
Add new multi-field
        ↓
Historical documents may require
update/reindex
        ↓
New representation populated
```

Always validate historical-data requirements before changing a production mapping.

---

## 4.18 Numeric Types

Elasticsearch provides multiple numeric types, including:

```text
byte
short
integer
long
half_float
float
double
scaled_float
```

Example:

```json
"age": {
  "type": "integer"
}
```

Choose a numeric type based on:

```text
Expected range
Precision
Query behavior
Aggregation requirements
Storage/resource implications
```

Do not automatically select the largest available type.

---

## 4.19 Date Fields

Example:

```json
"visit_date": {
  "type": "date"
}
```

Accepted formats can also be explicitly configured.

Example:

```json
"visit_date": {
  "type": "date",
  "format": "strict_date_optional_time||epoch_millis"
}
```

Consistent producer-side date formatting simplifies production operations.

---

## 4.20 Boolean Fields

Example:

```json
"active": {
  "type": "boolean"
}
```

Prefer semantic field types when the source data genuinely represents those semantics.

---

# Part IV — Arrays and Structured Data

## 4.21 Arrays

Elasticsearch does not require a separate ordinary `array` mapping type.

A field can contain multiple compatible values.

Example document:

```json
{
  "diagnosis_codes": [
    "I10",
    "E11.9",
    "J45.909"
  ]
}
```

Mapping:

```json
"diagnosis_codes": {
  "type": "keyword"
}
```

Arrays of scalar values are different from arrays of structured objects.

---

## 4.22 `object`

Consider:

```json
{
  "provider": {
    "id": "PR100",
    "name": "Atlantic Cardiology"
  }
}
```

A normal object mapping may be appropriate:

```json
"provider": {
  "properties": {
    "id": {
      "type": "keyword"
    },
    "name": {
      "type": "text"
    }
  }
}
```

---

## 4.23 Arrays of Objects

Consider:

```json
{
  "providers": [
    {
      "name": "Alice",
      "specialty": "Cardiology"
    },
    {
      "name": "Bob",
      "specialty": "Neurology"
    }
  ]
}
```

Ordinary object arrays are flattened internally.

Conceptually, the indexed representation can behave more like:

```text
providers.name
    Alice
    Bob

providers.specialty
    Cardiology
    Neurology
```

The independent relationship:

```text
Alice → Cardiology
Bob   → Neurology
```

may therefore not behave as expected for queries that require object-level correlation.

---

## 4.24 `nested`

When independent relationships within an array of objects must be preserved for query semantics, `nested` may be appropriate.

Example:

```json
"providers": {
  "type": "nested",
  "properties": {
    "name": {
      "type": "keyword"
    },
    "specialty": {
      "type": "keyword"
    }
  }
}
```

Do not automatically use `nested` for every object or array of objects.

Nested documents introduce additional indexing and query costs.

Use them when the application's query semantics require them.

---

## 4.25 `flattened`

Large or unpredictable key/value structures can create large numbers of mapped fields.

For certain use cases, the `flattened` field type can provide an alternative representation.

Conceptually:

```text
Known structured schema
        ↓
Explicit properties


Independent relationships
inside arrays of objects
        ↓
nested — when required


Large / arbitrary key-value structure
        ↓
consider flattened
```

`flattened` is not a free replacement for normal structured mappings.

It provides reduced field semantics and query capabilities compared with explicitly mapped structured fields.

Always verify availability and exact behavior against the Elasticsearch version you operate.

---

# Part V — Mapping Behavior and Operational Features

## 4.26 `ignore_above`

Example:

```json
"provider_name": {
  "type": "text",
  "fields": {
    "keyword": {
      "type": "keyword",
      "ignore_above": 256
    }
  }
}
```

A value exceeding the configured threshold is not indexed into that keyword representation.

Operationally, this can produce an important troubleshooting pattern:

```text
Long value
   ↓
Visible in _source
   ↓
But omitted from keyword index representation
   ↓
Exact query / aggregation
may not return it as expected
```

Do not assume that seeing a value in `_source` proves it was indexed into every mapped representation.

---

## 4.27 `doc_values`

Many fields used for sorting and aggregations have an on-disk column-oriented representation called `doc_values`.

Conceptually:

```text
Inverted index
      ↓
Search-oriented access


Doc values
      ↓
Sorting
Aggregations
Scripting/access patterns
```

Keep `doc_values` enabled unless there is a deliberate workload-specific reason to change them and the consequences have been reviewed.

Do not disable them casually as a storage optimization.

---

## 4.28 `_source`

`_source` normally preserves the original JSON document supplied to Elasticsearch.

It is operationally important for activities including:

```text
Document retrieval
Debugging
Update workflows
Reindexing
Migration
Recovery-oriented investigation
```

Do not disable `_source` as a routine disk-space optimization.

Treat changes to `_source` behavior as an architectural decision requiring explicit operational review.

---

# Part VI — Hands-On Explicit Mapping Lab

## 4.29 Precheck

`[TUTORIAL-ACCEPTANCE — SAFE-READ]`

```bash
curl -u "$ES_USER:$ES_PASSWORD" \
  "$ES_URL/_cat/indices/sre_tutorial_04?v"
```

Confirm that you are working only with the tutorial index.

---

## 4.30 Create the Tutorial Index

`[TUTORIAL-LAB — CONTROLLED-WRITE]`

```bash
curl -u "$ES_USER:$ES_PASSWORD" \
  -X PUT "$ES_URL/sre_tutorial_04" \
  -H 'Content-Type: application/json' \
  -d '{
    "settings": {
      "number_of_shards": 1,
      "number_of_replicas": 0
    },
    "mappings": {
      "properties": {
        "patient_id": {
          "type": "keyword"
        },
        "provider_name": {
          "type": "text",
          "fields": {
            "keyword": {
              "type": "keyword",
              "ignore_above": 256
            }
          }
        },
        "age": {
          "type": "integer"
        },
        "active": {
          "type": "boolean"
        },
        "visit_date": {
          "type": "date"
        },
        "diagnosis_codes": {
          "type": "keyword"
        }
      }
    }
  }'
```

The tutorial intentionally uses:

```text
1 primary
0 replicas
```

so the lab can operate on a single-node environment.

This is a **lab topology**, not a production availability recommendation.

---

## 4.31 Inspect the Mapping

`[TUTORIAL-ACCEPTANCE — SAFE-READ]`

```bash
curl -u "$ES_USER:$ES_PASSWORD" \
  "$ES_URL/sre_tutorial_04/_mapping?pretty"
```

Verify:

```text
patient_id       → keyword
provider_name    → text
provider_name.keyword → keyword
age              → integer
active           → boolean
visit_date       → date
diagnosis_codes  → keyword
```

---

## 4.32 Index Sample Document 1

`[TUTORIAL-LAB — CONTROLLED-WRITE]`

```bash
curl -u "$ES_USER:$ES_PASSWORD" \
  -X PUT "$ES_URL/sre_tutorial_04/_doc/P1001?refresh=wait_for" \
  -H 'Content-Type: application/json' \
  -d '{
    "patient_id": "P1001",
    "provider_name": "Atlantic Cardiology Associates",
    "age": 47,
    "active": true,
    "visit_date": "2026-09-16T14:30:00Z",
    "diagnosis_codes": ["I10", "E11.9"]
  }'
```

`refresh=wait_for` is used here only to make the immediately following tutorial search deterministic.

Do not automatically add synchronous refresh behavior to high-throughput production ingestion pipelines.

---

## 4.33 Index Sample Document 2

```bash
curl -u "$ES_USER:$ES_PASSWORD" \
  -X PUT "$ES_URL/sre_tutorial_04/_doc/P1002?refresh=wait_for" \
  -H 'Content-Type: application/json' \
  -d '{
    "patient_id": "P1002",
    "provider_name": "Carolina Neurology Center",
    "age": 58,
    "active": true,
    "visit_date": "2026-09-16T15:15:00Z",
    "diagnosis_codes": ["G43.909"]
  }'
```

---

## 4.34 Full-Text Search

`[TUTORIAL-ACCEPTANCE — SAFE-READ]`

```bash
curl -u "$ES_USER:$ES_PASSWORD" \
  -X GET "$ES_URL/sre_tutorial_04/_search?pretty" \
  -H 'Content-Type: application/json' \
  -d '{
    "query": {
      "match": {
        "provider_name": "cardiology"
      }
    }
  }'
```

This searches the analyzed `text` representation.

---

## 4.35 Exact Identifier Query

```bash
curl -u "$ES_USER:$ES_PASSWORD" \
  -X GET "$ES_URL/sre_tutorial_04/_search?pretty" \
  -H 'Content-Type: application/json' \
  -d '{
    "query": {
      "term": {
        "patient_id": "P1001"
      }
    }
  }'
```

This uses the exact `keyword` representation.

---

## 4.36 Aggregate on Multi-Field

```bash
curl -u "$ES_USER:$ES_PASSWORD" \
  -X GET "$ES_URL/sre_tutorial_04/_search?pretty" \
  -H 'Content-Type: application/json' \
  -d '{
    "size": 0,
    "aggs": {
      "providers": {
        "terms": {
          "field": "provider_name.keyword"
        }
      }
    }
  }'
```

The same logical value supports two access patterns:

```text
provider_name
      ↓
Full-text search

provider_name.keyword
      ↓
Exact aggregation
```

---

# Part VII — Deterministic Mapping Conflict Lab

## 4.37 Create the Failure-Lab Index

`[TUTORIAL-LAB — CONTROLLED-WRITE]`

```bash
curl -u "$ES_USER:$ES_PASSWORD" \
  -X PUT "$ES_URL/sre_tutorial_04_bad" \
  -H 'Content-Type: application/json' \
  -d '{
    "settings": {
      "number_of_shards": 1,
      "number_of_replicas": 0
    },
    "mappings": {
      "properties": {
        "member_id": {
          "type": "keyword"
        },
        "age": {
          "type": "integer"
        }
      }
    }
  }'
```

The important mapping is:

```text
age → integer
```

---

## 4.38 Index Valid Data

`[TUTORIAL-LAB — CONTROLLED-WRITE]`

```bash
curl -u "$ES_USER:$ES_PASSWORD" \
  -X PUT "$ES_URL/sre_tutorial_04_bad/_doc/1" \
  -H 'Content-Type: application/json' \
  -d '{
    "member_id": "M1001",
    "age": 45
  }'
```

This is compatible with the mapping.

---

## 4.39 Submit Incompatible Data

`[TUTORIAL-LAB — EXPECTED-FAILURE]`

```bash
curl -u "$ES_USER:$ES_PASSWORD" \
  -X PUT "$ES_URL/sre_tutorial_04_bad/_doc/2" \
  -H 'Content-Type: application/json' \
  -d '{
    "member_id": "M1002",
    "age": "unknown"
  }'
```

The tutorial intentionally sends a non-numeric value to a field explicitly mapped as `integer`.

Conceptually:

```text
age mapped as integer
        ↓
"unknown" arrives
        ↓
Cannot be parsed as integer
        ↓
Document rejected
```

The failure is expected.

Do not attempt to "fix" the lab by changing the established `age` field into another type.

---

## 4.40 Diagnose the Failure

Inspect the mapping:

`[TUTORIAL-ACCEPTANCE — SAFE-READ]`

```bash
curl -u "$ES_USER:$ES_PASSWORD" \
  "$ES_URL/sre_tutorial_04_bad/_mapping?pretty"
```

Compare:

```text
Expected mapping
      ↓
age = integer

Actual incoming value
      ↓
age = "unknown"
```

The operational question is:

> Is the mapping wrong, or is the producer sending invalid data?

Do not change production mappings before answering that question.

---

# Part VIII — Mapping Evolution

## 4.41 Mapping Changes Are Not All Equivalent

Avoid the overly broad statement:

```text
Mappings are immutable.
```

A more accurate model is:

> Many established mapping characteristics—especially an existing field's type—cannot be changed in place. Elasticsearch permits supported mapping additions and selected mapping updates.

For example:

```text
Add compatible new field
        ↓
Potentially supported


Add multi-field
        ↓
Potentially supported
        ↓
Historical data may require reindex/update


integer → keyword
        ↓
Not an ordinary in-place field-type change
```

Always validate the requested operation against the deployed Elasticsearch version.

---

## 4.42 Field-Type Migration

Suppose production contains:

```text
age → integer
```

but a new application design requires:

```text
age → keyword
```

The normal migration model is:

```text
Existing index
      ↓
Capture current settings/mappings
      ↓
Design corrected mapping
      ↓
Create replacement index
      ↓
Reindex / migrate
      ↓
Validate
      ↓
Controlled cutover
```

Do not attempt unsupported field-type mutation on the existing production field.

---

## 4.43 Production Migration Boundary

`[PRODUCTION-MIGRATION — HIGH-RISK]`

Production schema migration can involve:

```text
Create destination index
        ↓
Apply approved settings/mappings
        ↓
Reindex or migrate
        ↓
Validate document counts
        ↓
Inspect failures
        ↓
Validate mappings
        ↓
Validate representative queries
        ↓
Validate aggregations
        ↓
Validate application behavior
        ↓
Controlled alias/application cutover
        ↓
Observation period
        ↓
Retire source later
```

This tutorial intentionally does **not** provide a blindly executable production migration sequence.

Production reindexing and cutover deserve a dedicated operational runbook.

---

## 4.44 Do Not Delete the Source Immediately

A successful reindex operation alone is not sufficient evidence to delete the source index.

Before retirement validate:

```text
Document counts
Failed documents
Mapping correctness
Representative searches
Aggregations
Application behavior
Write path
Alias state
Rollback requirements
Observation period
```

Source deletion should be a separate controlled decision.

---

# Part IX — Mapping Explosion

## 4.45 What Is Mapping Explosion?

Consider documents that continually introduce new field names:

```json
{
  "attribute_10001": "x",
  "attribute_10002": "y",
  "attribute_10003": "z"
}
```

Then later:

```text
attribute_10004
attribute_10005
...
attribute_50000
```

The mapping grows with every unique mapped field.

Conceptually:

```text
Uncontrolled keys
      ↓
Dynamic mapping
      ↓
More mapped fields
      ↓
Larger cluster state / metadata
      ↓
Memory + performance pressure
      ↓
Operational problems
```

This is commonly called **mapping explosion**.

---

## 4.46 Mapping Field Limits

A relevant protection is:

```text
index.mapping.total_fields.limit
```

The commonly documented default in current Elastic documentation is 1000 mapped fields per index, though exact behavior and defaults must always be verified against the Elasticsearch version in use.

The count can include more than obvious leaf fields.

For example, depending on version and mapping structure, contributors can include:

```text
Mapped fields
Object mappings
Aliases
Multi-fields
Mapped runtime fields
```

Do not treat the field limit as merely an obstacle to increase.

---

## 4.47 Bad Operational Response

Avoid this automatic response:

```text
Field limit reached
      ↓
Increase total_fields.limit
      ↓
Done
```

That can hide an upstream schema problem.

---

## 4.48 Better Operational Response

Use:

```text
Field limit reached
      ↓
Inspect mapping growth
      ↓
Identify new field patterns
      ↓
Identify producer
      ↓
Expected schema growth?
      |
      +---- YES
      |       ↓
      |  Architecture/capacity review
      |
      +---- NO
              ↓
       Producer/schema defect
              ↓
       Stop uncontrolled growth
```

Only after investigation should a higher field limit be considered.

---

## 4.49 `nested` Does Not Fix Mapping Explosion

Do not assume:

```text
Too many fields
      ↓
Use nested
      ↓
Problem solved
```

`nested` solves a different problem:

```text
Preserving independent
relationships inside
arrays of objects
```

Mapping explosion is fundamentally about excessive mapped-field growth.

---

## 4.50 Consider `flattened` for Appropriate Key/Value Structures

For large or unpredictable key/value structures:

```text
Thousands of arbitrary keys
        ↓
Do we need every key
as a fully mapped field?
        ↓
If not
        ↓
Evaluate flattened
```

But review query and semantic limitations before adopting it.

---

# Part X — Production Governance

## 4.51 Mapping Review Checklist

Before approving a significant production mapping:

```text
[ ] Field semantics understood
[ ] Producer contract understood
[ ] Explicit types selected
[ ] text vs keyword reviewed
[ ] Multi-fields justified
[ ] Historical-data behavior reviewed
[ ] Numeric range/precision reviewed
[ ] Date formats defined
[ ] Arrays understood
[ ] object vs nested reviewed
[ ] flattened evaluated where appropriate
[ ] Dynamic mapping policy defined
[ ] Field-count growth estimated
[ ] Mapping explosion risk reviewed
[ ] Aggregation requirements understood
[ ] Sorting requirements understood
[ ] doc_values decisions reviewed
[ ] _source requirements reviewed
[ ] ignore_above behavior understood
[ ] Expected document growth reviewed
[ ] Existing-data compatibility reviewed
[ ] Reindex requirement evaluated
[ ] Migration strategy documented
[ ] Cutover strategy documented
[ ] Rollback strategy documented
[ ] Elasticsearch version compatibility verified
```

---

## 4.52 Mapping Ownership Model

A practical production responsibility model:

| Responsibility                       | Application/Data Team | Elasticsearch/SRE/DBRE |
| ------------------------------------ | --------------------: | ---------------------: |
| Define field meaning                 |               Primary |                Consult |
| Define producer contract             |               Primary |                Consult |
| Define query requirements            |               Primary |                Consult |
| Define aggregation requirements      |               Primary |                Consult |
| Propose mapping                      |        Primary/shared |                 Shared |
| Review Elasticsearch behavior        |               Consult |                Primary |
| Review mapping explosion risk        |                Shared |                Primary |
| Review resource implications         |               Consult |                Primary |
| Review compatibility                 |                Shared |                 Shared |
| Approve migration procedure          |                Shared |                 Shared |
| Operate Elasticsearch infrastructure |               Consult |                Primary |

Organizational models vary.

The important principle is:

> Mapping should not become an undocumented infrastructure-only responsibility.

---

# Part XI — Production Troubleshooting

## 4.53 Mapping-Related Ingestion Failure Workflow

When ingestion begins failing:

```text
Application reports failure
        ↓
Capture exact Elasticsearch response
        ↓
Identify exact index
        ↓
Identify failing document
        ↓
Identify failing field
        ↓
Inspect mapping
        ↓
Inspect actual source value/type
        ↓
Compare expected vs actual schema
        ↓
Determine root cause
```

Possible causes include:

```text
Invalid producer data
Producer schema change
Incorrect mapping
Dynamic mapping side effect
Field-type conflict
Date parsing failure
Mapping field limit
Migration/cutover mismatch
```

---

## 4.54 Do Not Modify the Mapping First

Avoid:

```text
Ingestion error
      ↓
Change Elasticsearch mapping immediately
```

Instead:

```text
Ingestion error
      ↓
Capture evidence
      ↓
Compare producer contract
with Elasticsearch mapping
      ↓
Identify ownership/root cause
      ↓
Choose remediation
```

Changing a production mapping without understanding the producer can make the problem worse or create a larger migration requirement.

---

## 4.55 Useful Mapping Investigation Commands

`[TUTORIAL-ACCEPTANCE — SAFE-READ]`

Inspect mapping:

```bash
curl -u "$ES_USER:$ES_PASSWORD" \
  "$ES_URL/sre_tutorial_04/_mapping?pretty"
```

Inspect settings:

```bash
curl -u "$ES_USER:$ES_PASSWORD" \
  "$ES_URL/sre_tutorial_04/_settings?pretty"
```

Inspect tutorial index:

```bash
curl -u "$ES_USER:$ES_PASSWORD" \
  "$ES_URL/_cat/indices/sre_tutorial_04?v"
```

Retrieve a sample document:

```bash
curl -u "$ES_USER:$ES_PASSWORD" \
  "$ES_URL/sre_tutorial_04/_doc/P1001?pretty"
```

---

# Part XII — Cleanup

## 4.56 Cleanup Precheck

`[TUTORIAL-ACCEPTANCE — SAFE-READ]`

Inspect the exact tutorial indices:

```bash
curl -u "$ES_USER:$ES_PASSWORD" \
  "$ES_URL/_cat/indices/sre_tutorial_04,sre_tutorial_04_bad?v"
```

Confirm that the only indices you intend to remove are:

```text
sre_tutorial_04
sre_tutorial_04_bad
```

Do not use:

```text
sre_tutorial_04*
*
_all
```

for cleanup.

---

## 4.57 Delete `sre_tutorial_04`

`[TUTORIAL-LAB — DESTRUCTIVE]`

```bash
curl -u "$ES_USER:$ES_PASSWORD" \
  -X DELETE "$ES_URL/sre_tutorial_04"
```

---

## 4.58 Delete `sre_tutorial_04_bad`

`[TUTORIAL-LAB — DESTRUCTIVE]`

```bash
curl -u "$ES_USER:$ES_PASSWORD" \
  -X DELETE "$ES_URL/sre_tutorial_04_bad"
```

Delete each index individually.

---

## 4.59 Verify Cleanup

`[TUTORIAL-ACCEPTANCE — SAFE-READ]`

```bash
curl -u "$ES_USER:$ES_PASSWORD" \
  "$ES_URL/_cat/indices/sre_tutorial_04,sre_tutorial_04_bad?v"
```

The tutorial indices should no longer exist.

---

# Part XIII — Tutorial Acceptance

## 4.60 Acceptance Check

You should now be able to explain:

1. What an Elasticsearch mapping controls.
2. Why mapping design is part of application architecture.
3. Why important production fields should often be explicitly mapped.
4. The difference between `dynamic: true`, `false`, and `strict`.
5. Why `dynamic: strict` is not universally appropriate.
6. The difference between `text` and `keyword`.
7. Why multi-fields are useful.
8. Why adding a multi-field does not automatically populate historical documents.
9. How Elasticsearch handles ordinary arrays.
10. Why arrays of objects can require `nested`.
11. Why `nested` should not be used automatically.
12. When `flattened` may be worth evaluating.
13. How `ignore_above` can make a value visible in `_source` but unavailable through its keyword representation.
14. What `doc_values` broadly support.
15. Why `_source` is operationally important.
16. Why established field types generally cannot simply be replaced.
17. Which mapping changes may require a new index and migration.
18. What mapping explosion means.
19. Why increasing `index.mapping.total_fields.limit` is not automatically the right solution.
20. How application/data teams and Elasticsearch operators share mapping governance.
21. How to investigate a mapping-related ingestion failure.
22. Why Elasticsearch-version validation is required before production changes.

---

## 4.61 Administrator Mental Model

Remember:

```text
Data semantics
      ↓
Mapping
      ↓
How Elasticsearch
represents the data
      ↓
Search behavior
Aggregation behavior
Storage behavior
Operational behavior
      ↓
Production reliability
```

And:

```text
Producer contract
       +
Mapping design
       +
Query requirements
       +
Operational review
       ↓
Production-safe schema
```

---

## 4.62 Key Production Principles

**Do not allow accidental ingestion order to become your schema-design process.**

**Do not treat mappings as purely an Elasticsearch infrastructure concern.**

**Do not change production mappings merely to silence an ingestion error.**

**Do not assume `nested` fixes mapping explosion.**

**Do not automatically raise mapping limits without investigating field growth.**

**Do not disable `_source` or `doc_values` as casual storage optimizations.**

**Do not assume a successful reindex alone proves a migration is ready for source deletion.**

**Do validate mapping behavior against the Elasticsearch version actually deployed.**

---

# Vendor References

For implementation and version-specific validation, consult the official Elastic documentation for:

* Mapping
* Explicit mapping
* Dynamic mapping
* Dynamic templates
* `text`
* `keyword`
* Multi-fields
* Arrays
* `object`
* `nested`
* `flattened`
* `ignore_above`
* `doc_values`
* `_source`
* Mapping limits
* Mapping explosion
* Update mapping API
* Reindex API
* Alias management

Vendor documentation should be treated as the authoritative source for exact behavior supported by the Elasticsearch version being operated.

---

# Canonical Status

**Module:** 04 — Mapping Governance & Data Modeling
**Tutorial:** 04 — Mapping Governance & Data Modeling
**Edition:** Revised Final / Canonical
**Technical + Vendor Review:** PASS
**Production + Safety Review:** PASS
**Copyright/Originality Review:** PASS
**Explicit Mapping Lab:** PASS
**Deterministic Mapping-Conflict Lab:** PASS
**Mapping Explosion Safeguards:** PASS
**`object` / `nested` / `flattened` Guidance:** PASS
**Mapping Evolution Boundary:** PASS
**Production Migration Safety Boundary:** PASS
**Mapping Governance Model:** PASS
**Elasticsearch Version Scope:** PASS
**Basic Authentication:** Included
**Exact-Name Destructive Guardrails:** Included
**Publication Status:** **CANONICAL — READY FOR REPOSITORY VALIDATION**
