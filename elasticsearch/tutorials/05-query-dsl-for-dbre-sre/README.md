# Module 05 — Query DSL for DBRE/SRE

## Tutorial 05 — Query DSL for DBRE/SRE

**Edition:** Revised Final / Canonical
**Audience:** Elasticsearch administrators, SREs, DBREs, platform engineers, developers, and data engineers
**Lab index:** `sre_tutorial_05`

---

# 5.1 Introduction

Elasticsearch Query DSL is the JSON-based language used to search and analyze indexed data.

For an application developer, Query DSL answers questions such as:

> How do I find the documents my application needs?

For an SRE or DBRE, the question is broader:

> What is this query asking Elasticsearch to do, and what operational cost can that request create?

A query can be logically correct while still being operationally expensive.

```text
Application request
       ↓
Elasticsearch query
       ↓
Which indices?
Which shards?
Which fields?
Which query clauses?
How much data?
How much sorting?
How much aggregation?
How many results?
       ↓
CPU
Heap
Disk I/O
Search execution capacity
Network
       ↓
Latency + reliability
```

Query DSL is therefore both an application-development topic and an Elasticsearch operational skill.

A central principle throughout this tutorial is:

> **Read-only does not mean operationally free or automatically production-safe.**

---

# 5.2 Learning Objectives

By the end of this tutorial, you should be able to:

1. Understand the Query DSL structure.
2. Distinguish query context from filter context.
3. Distinguish full-text queries from exact-value queries.
4. Use `match`.
5. Use `term`.
6. Use `terms`.
7. Use `range`.
8. Use `exists`.
9. Build `bool` queries.
10. Understand `must`.
11. Understand `filter`.
12. Understand `should`.
13. Understand `minimum_should_match`.
14. Understand `must_not`.
15. Apply `_source` filtering.
16. Sort search results appropriately.
17. Use `from` and `size`.
18. Understand `index.max_result_window`.
19. Understand why deep pagination requires special treatment.
20. Use `search_after` in a controlled lab.
21. Understand deterministic pagination ordering.
22. Understand point-in-time search conceptually.
23. Create basic aggregations.
24. Understand nested-query requirements.
25. Recognize wildcard and regexp query risks.
26. Recognize script-query risks.
27. Understand `search.allow_expensive_queries` conceptually.
28. Recognize oversized or overly broad query patterns.
29. Understand the operational impact of query concurrency.
30. Use mappings and query evidence during troubleshooting.
31. Understand the role and overhead of the Profile API.
32. Apply production query-governance principles.

---

# 5.3 Elasticsearch Version Scope

This tutorial teaches Query DSL concepts that are broadly applicable across supported Elasticsearch versions, including environments still operating Elasticsearch 7.17 and newer deployments.

However, exact behavior, available parameters, pagination recommendations, point-in-time capabilities, expensive-query controls, defaults, and API details can vary by Elasticsearch version.

Before applying production guidance, verify it against the documentation for the deployed version.

In particular, version-check:

```text
search_after behavior
Point in Time APIs
search.allow_expensive_queries
wildcard/regexp options
script-query behavior
pagination limits
Profile API behavior
```

Do not assume that documentation for the newest Elasticsearch release exactly describes an older 7.17 cluster.

---

# 5.4 Tutorial Safety Classification

## `[TUTORIAL-ACCEPTANCE — SAFE-READ]`

Small read-only operations against the dedicated tutorial index.

Examples:

```text
GET sre_tutorial_05/_mapping
GET sre_tutorial_05/_count
GET sre_tutorial_05/_search
GET _cat/indices/sre_tutorial_05
```

These classifications assume the tutorial dataset described here.

A similar request against a very large production dataset may have materially different operational cost.

---

## `[TUTORIAL-LAB — CONTROLLED-WRITE]`

Controlled writes against:

```text
sre_tutorial_05
```

including:

```text
Create tutorial index
Load synthetic documents
```

---

## `[TUTORIAL-LAB — DESTRUCTIVE]`

Deletion of exactly:

```text
sre_tutorial_05
```

---

## `[PRODUCTION-DIAGNOSTIC — REVIEW-REQUIRED]`

Potentially expensive production operations requiring workload and cluster-state review.

Examples include:

```text
Profile API
Broad wildcard queries
Regexp queries
Script-based queries
Large aggregations
Exact counts over large datasets
Deep pagination
Large result windows
Broad sorted searches
```

Again:

> **Read-only is not the same as zero-cost.**

---

# 5.5 Lab Safety Boundary

This tutorial uses only:

```text
sre_tutorial_05
```

Never substitute:

```text
Production index
Production alias
Production data stream
Wildcard
*
_all
```

for the tutorial index.

The dataset is synthetic and contains no PHI or customer data.

---

# 5.6 Authentication

Use environment variables.

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

Production Elasticsearch endpoints should use HTTPS/TLS according to the organization's security architecture.

Never hardcode production credentials in:

```text
Scripts
Documentation
Git repositories
Tickets
Screenshots
Chat messages
```

---

# Part I — Query DSL Mental Model

# 5.7 Basic Search Structure

A typical search request looks like:

```json
{
  "query": {
    "match": {
      "provider_name": "cardiology"
    }
  }
}
```

Conceptually:

```text
_search
   ↓
query
   ↓
query type
   ↓
field
   ↓
search value
```

The query type determines how Elasticsearch interprets the requested value.

---

# 5.8 Query Context vs Filter Context

One of the most important Query DSL concepts is the distinction between:

```text
Query context
```

and:

```text
Filter context
```

Query context asks:

> Does this document match, and how relevant is the match?

Filter context asks:

> Does this document satisfy this condition?

Conceptually:

```text
QUERY CONTEXT
      ↓
Matching
      +
Relevance scoring


FILTER CONTEXT
      ↓
Yes / No
      ↓
No relevance score required
```

For structured constraints such as:

```text
status
boolean flags
IDs
date boundaries
```

filter context is often the appropriate semantic model when relevance scoring is unnecessary.

This is not a rule that every filter is automatically faster in every workload. Query design should first represent the required semantics correctly.

---

# Part II — Build the Lab Dataset

# 5.9 Precheck

`[TUTORIAL-ACCEPTANCE — SAFE-READ]`

```bash
curl -u "$ES_USER:$ES_PASSWORD" \
  "$ES_URL/_cat/indices/sre_tutorial_05?v"
```

Confirm that the tutorial is operating only against:

```text
sre_tutorial_05
```

---

# 5.10 Create the Tutorial Index

`[TUTORIAL-LAB — CONTROLLED-WRITE]`

```bash
curl -u "$ES_USER:$ES_PASSWORD" \
  -X PUT "$ES_URL/sre_tutorial_05" \
  -H 'Content-Type: application/json' \
  -d '{
    "settings": {
      "number_of_shards": 1,
      "number_of_replicas": 0
    },
    "mappings": {
      "properties": {
        "event_id": {
          "type": "keyword"
        },
        "patient_id": {
          "type": "keyword"
        },
        "provider_id": {
          "type": "keyword"
        },
        "provider_name": {
          "type": "text",
          "fields": {
            "keyword": {
              "type": "keyword"
            }
          }
        },
        "specialty": {
          "type": "keyword"
        },
        "event_type": {
          "type": "keyword"
        },
        "status": {
          "type": "keyword"
        },
        "description": {
          "type": "text"
        },
        "event_date": {
          "type": "date"
        },
        "amount": {
          "type": "double"
        },
        "active": {
          "type": "boolean"
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

so it can run on a single-node lab environment.

This is a tutorial topology and **not** a production availability recommendation.

---

# 5.11 Load Synthetic Data

`[TUTORIAL-LAB — CONTROLLED-WRITE]`

The Bulk API uses newline-delimited JSON.

The payload must maintain the expected action/document structure and terminate correctly.

```bash
curl -u "$ES_USER:$ES_PASSWORD" \
  -X POST "$ES_URL/_bulk?refresh=wait_for" \
  -H 'Content-Type: application/x-ndjson' \
  --data-binary '{"index":{"_index":"sre_tutorial_05","_id":"1"}}
{"event_id":"EV1001","patient_id":"P1001","provider_id":"PR100","provider_name":"Atlantic Cardiology Associates","specialty":"cardiology","event_type":"visit","status":"completed","description":"Routine cardiology follow-up visit","event_date":"2026-09-10T14:00:00Z","amount":225.50,"active":true}
{"index":{"_index":"sre_tutorial_05","_id":"2"}}
{"event_id":"EV1002","patient_id":"P1002","provider_id":"PR200","provider_name":"Carolina Neurology Center","specialty":"neurology","event_type":"consultation","status":"completed","description":"Neurology consultation for recurring migraine","event_date":"2026-09-11T15:30:00Z","amount":310.00,"active":true}
{"index":{"_index":"sre_tutorial_05","_id":"3"}}
{"event_id":"EV1003","patient_id":"P1001","provider_id":"PR100","provider_name":"Atlantic Cardiology Associates","specialty":"cardiology","event_type":"lab","status":"pending","description":"Cardiac laboratory testing ordered","event_date":"2026-09-12T09:15:00Z","amount":175.75,"active":true}
{"index":{"_index":"sre_tutorial_05","_id":"4"}}
{"event_id":"EV1004","patient_id":"P1003","provider_id":"PR300","provider_name":"Queen City Orthopedics","specialty":"orthopedics","event_type":"visit","status":"cancelled","description":"Orthopedic knee evaluation","event_date":"2026-09-13T11:00:00Z","amount":190.00,"active":false}
{"index":{"_index":"sre_tutorial_05","_id":"5"}}
{"event_id":"EV1005","patient_id":"P1004","provider_id":"PR100","provider_name":"Atlantic Cardiology Associates","specialty":"cardiology","event_type":"consultation","status":"completed","description":"Cardiology consultation for hypertension management","event_date":"2026-09-14T16:45:00Z","amount":280.25,"active":true}
{"index":{"_index":"sre_tutorial_05","_id":"6"}}
{"event_id":"EV1006","patient_id":"P1005","provider_id":"PR400","provider_name":"Piedmont Primary Care","specialty":"primary_care","event_type":"visit","status":"completed","description":"Annual preventive wellness visit","event_date":"2026-09-15T10:30:00Z","amount":145.00,"active":true}
'
```

`refresh=wait_for` is used here only to make the small tutorial deterministic.

Do not automatically add synchronous refresh behavior to high-throughput production ingestion without understanding the workload and refresh strategy.

---

# 5.12 Verify Document Count

`[TUTORIAL-ACCEPTANCE — SAFE-READ]`

```bash
curl -u "$ES_USER:$ES_PASSWORD" \
  "$ES_URL/sre_tutorial_05/_count?pretty"
```

Expected:

```text
6 documents
```

---

# Part III — Full-Text Queries

# 5.13 `match`

Use `match` for analyzed full-text search.

```bash
curl -u "$ES_USER:$ES_PASSWORD" \
  -X GET "$ES_URL/sre_tutorial_05/_search?pretty" \
  -H 'Content-Type: application/json' \
  -d '{
    "query": {
      "match": {
        "description": "cardiology consultation"
      }
    }
  }'
```

Because:

```text
description → text
```

the query value is analyzed.

Conceptually:

```text
"cardiology consultation"
          ↓
       analyzer
          ↓
search terms
          ↓
relevance scoring
```

---

# 5.14 Why `match` Is Not an Exact Filter

This:

```json
{
  "match": {
    "description": "cardiology consultation"
  }
}
```

does **not** mean:

```text
description == "cardiology consultation"
```

It invokes analyzed full-text behavior.

For exact structured values, use an appropriate term-level query against a suitable field mapping.

---

# Part IV — Exact Queries

# 5.15 `term`

Use `term` for exact term-level matching.

```bash
curl -u "$ES_USER:$ES_PASSWORD" \
  -X GET "$ES_URL/sre_tutorial_05/_search?pretty" \
  -H 'Content-Type: application/json' \
  -d '{
    "query": {
      "term": {
        "status": "completed"
      }
    }
  }'
```

Here:

```text
status → keyword
```

so an exact term query is appropriate.

---

# 5.16 `term` and Analyzed Text

Suppose:

```text
provider_name → text
```

This:

```json
{
  "term": {
    "provider_name": "Atlantic Cardiology Associates"
  }
}
```

does not analyze the query value in the same way as `match`.

For exact matching, use the keyword multi-field:

```json
{
  "term": {
    "provider_name.keyword": "Atlantic Cardiology Associates"
  }
}
```

Mapping knowledge is therefore essential to query diagnosis.

---

# 5.17 `terms`

Use `terms` when any value from a set of exact terms may match.

```bash
curl -u "$ES_USER:$ES_PASSWORD" \
  -X GET "$ES_URL/sre_tutorial_05/_search?pretty" \
  -H 'Content-Type: application/json' \
  -d '{
    "query": {
      "terms": {
        "status": [
          "completed",
          "pending"
        ]
      }
    }
  }'
```

Conceptually:

```text
status = completed
      OR
status = pending
```

This remains a term-level operation rather than full-text analysis.

---

# Part V — Range and Existence Queries

# 5.18 Date `range`

```bash
curl -u "$ES_USER:$ES_PASSWORD" \
  -X GET "$ES_URL/sre_tutorial_05/_search?pretty" \
  -H 'Content-Type: application/json' \
  -d '{
    "query": {
      "range": {
        "event_date": {
          "gte": "2026-09-12T00:00:00Z",
          "lt": "2026-09-16T00:00:00Z"
        }
      }
    }
  }'
```

Common operators include:

```text
gt
gte
lt
lte
```

Production date queries should make boundary and timezone assumptions explicit.

---

# 5.19 Numeric `range`

```bash
curl -u "$ES_USER:$ES_PASSWORD" \
  -X GET "$ES_URL/sre_tutorial_05/_search?pretty" \
  -H 'Content-Type: application/json' \
  -d '{
    "query": {
      "range": {
        "amount": {
          "gte": 200,
          "lte": 300
        }
      }
    }
  }'
```

Numeric fields should be mapped according to their semantics when numeric comparisons and range queries are required.

---

# 5.20 `exists`

Use `exists` to find documents containing an indexed value for a field.

```bash
curl -u "$ES_USER:$ES_PASSWORD" \
  -X GET "$ES_URL/sre_tutorial_05/_search?pretty" \
  -H 'Content-Type: application/json' \
  -d '{
    "query": {
      "exists": {
        "field": "amount"
      }
    }
  }'
```

Do not interpret `exists` simply as:

```text
Does the JSON key appear in _source?
```

A field can appear in source representation while mapping or value behavior affects whether an indexed value exists.

When diagnosing missing-field behavior, inspect both the mapping and the source data.

---

# Part VI — Boolean Queries

# 5.21 `bool`

A `bool` query combines clauses such as:

```text
must
filter
should
must_not
```

Conceptually:

```text
bool
 |
 +-- must
 |
 +-- filter
 |
 +-- should
 |
 +-- must_not
```

---

# 5.22 `must`

`must` clauses must match.

When used for scored queries, they contribute to relevance.

```bash
curl -u "$ES_USER:$ES_PASSWORD" \
  -X GET "$ES_URL/sre_tutorial_05/_search?pretty" \
  -H 'Content-Type: application/json' \
  -d '{
    "query": {
      "bool": {
        "must": [
          {
            "match": {
              "description": "cardiology"
            }
          }
        ]
      }
    }
  }'
```

---

# 5.23 `filter`

For structured conditions where relevance scoring is unnecessary:

```bash
curl -u "$ES_USER:$ES_PASSWORD" \
  -X GET "$ES_URL/sre_tutorial_05/_search?pretty" \
  -H 'Content-Type: application/json' \
  -d '{
    "query": {
      "bool": {
        "filter": [
          {
            "term": {
              "status": "completed"
            }
          },
          {
            "term": {
              "active": true
            }
          }
        ]
      }
    }
  }'
```

Conceptually:

```text
status == completed
AND
active == true
```

These conditions do not require relevance scoring.

---

# 5.24 Combine `must` and `filter`

A common production pattern is:

```text
Full-text relevance
        ↓
must

Structured constraints
        ↓
filter
```

Example:

```bash
curl -u "$ES_USER:$ES_PASSWORD" \
  -X GET "$ES_URL/sre_tutorial_05/_search?pretty" \
  -H 'Content-Type: application/json' \
  -d '{
    "query": {
      "bool": {
        "must": [
          {
            "match": {
              "description": "cardiology"
            }
          }
        ],
        "filter": [
          {
            "term": {
              "status": "completed"
            }
          },
          {
            "range": {
              "event_date": {
                "gte": "2026-09-01T00:00:00Z"
              }
            }
          }
        ]
      }
    }
  }'
```

The intent is clear:

```text
Find relevant cardiology documents

AND

restrict them to:
completed events
after the requested date
```

---

# 5.25 `must_not`

`must_not` excludes documents matching its clauses.

It operates in filter context and does not contribute a relevance score.

```bash
curl -u "$ES_USER:$ES_PASSWORD" \
  -X GET "$ES_URL/sre_tutorial_05/_search?pretty" \
  -H 'Content-Type: application/json' \
  -d '{
    "query": {
      "bool": {
        "must_not": [
          {
            "term": {
              "status": "cancelled"
            }
          }
        ]
      }
    }
  }'
```

Conceptually:

```text
status != cancelled
```

---

# 5.26 `should`

`should` must not be taught simply as a universal synonym for `OR`.

Its behavior depends on the surrounding `bool` query.

Example:

```bash
curl -u "$ES_USER:$ES_PASSWORD" \
  -X GET "$ES_URL/sre_tutorial_05/_search?pretty" \
  -H 'Content-Type: application/json' \
  -d '{
    "query": {
      "bool": {
        "should": [
          {
            "term": {
              "specialty": "cardiology"
            }
          },
          {
            "term": {
              "specialty": "neurology"
            }
          }
        ],
        "minimum_should_match": 1
      }
    }
  }'
```

Here at least one `should` clause must match because the requirement is explicit.

---

# 5.27 `minimum_should_match`

The default behavior deserves special attention.

Conceptually:

```text
bool contains should
AND
contains no must/filter
        ↓
default minimum_should_match = 1
```

Whereas:

```text
bool contains should
AND
also contains must or filter
        ↓
default minimum_should_match = 0
```

Therefore, when `should` conditions are logically mandatory, make the requirement explicit rather than relying on an easily overlooked contextual default.

Example:

```json
{
  "minimum_should_match": 1
}
```

---

# Part VII — Source Filtering

# 5.28 Limit Returned `_source`

Applications often do not require the complete source document.

```bash
curl -u "$ES_USER:$ES_PASSWORD" \
  -X GET "$ES_URL/sre_tutorial_05/_search?pretty" \
  -H 'Content-Type: application/json' \
  -d '{
    "_source": [
      "event_id",
      "patient_id",
      "provider_name",
      "status"
    ],
    "query": {
      "term": {
        "status": "completed"
      }
    }
  }'
```

Conceptually:

```text
Full _source
     ↓
Return selected source fields
     ↓
Smaller returned source payload
```

Source filtering can reduce the amount of source content returned to the client.

It does **not** mean that every component of query execution becomes cheaper.

---

# Part VIII — Sorting

# 5.29 Sort by Date

```bash
curl -u "$ES_USER:$ES_PASSWORD" \
  -X GET "$ES_URL/sre_tutorial_05/_search?pretty" \
  -H 'Content-Type: application/json' \
  -d '{
    "query": {
      "match_all": {}
    },
    "sort": [
      {
        "event_date": {
          "order": "desc"
        }
      }
    ]
  }'
```

Sorting should be reviewed together with:

```text
Sort field mapping
Result size
Shard fan-out
Query selectivity
Pagination pattern
Concurrency
```

---

# 5.30 Sort on Appropriate Fields

Do not assume every field is suitable for exact sorting.

For example:

```text
provider_name → text
```

is an analyzed field.

For exact-value sorting in this tutorial, use:

```text
provider_name.keyword
```

when that semantic behavior is required.

---

# Part IX — Pagination

# 5.31 `from` and `size`

For small result windows:

```bash
curl -u "$ES_USER:$ES_PASSWORD" \
  -X GET "$ES_URL/sre_tutorial_05/_search?pretty" \
  -H 'Content-Type: application/json' \
  -d '{
    "from": 0,
    "size": 2,
    "query": {
      "match_all": {}
    },
    "sort": [
      {
        "event_date": {
          "order": "asc"
        }
      }
    ]
  }'
```

This is straightforward for shallow pagination.

---

# 5.32 `index.max_result_window`

Elasticsearch limits ordinary `from` + `size` pagination using:

```text
index.max_result_window
```

A commonly documented default is:

```text
10000
```

Always verify the actual setting and deployed Elasticsearch version.

Conceptually:

```text
from: 9900
size: 100
      ↓
10,000


from: 10000
size: 100
      ↓
10,100
      ↓
Beyond a 10,000 result window
```

The operational lesson is not:

```text
Increase max_result_window
```

whenever an application wants deeper pages.

Instead ask:

```text
Why does the application need this page?
Is interactive pagination appropriate?
Could search_after be used?
Is this actually an export workflow?
Can the result set be narrowed?
```

---

# 5.33 Why Deep Pagination Is Expensive

Conceptually:

```text
from: 0
size: 20
    ↓
Small window


Very large from
+
size
    ↓
Many candidate results may need
to be processed before returning
the requested page
```

Cost becomes especially important when combined with:

```text
Many shards
Large result windows
Sorting
Large source documents
Concurrent requests
```

Do not solve deep-pagination requirements merely by raising limits.

---

# 5.34 `search_after` — First Page

`[TUTORIAL-ACCEPTANCE — SAFE-READ]`

Use a deterministic sort.

```bash
curl -u "$ES_USER:$ES_PASSWORD" \
  -X GET "$ES_URL/sre_tutorial_05/_search?pretty" \
  -H 'Content-Type: application/json' \
  -d '{
    "size": 2,
    "query": {
      "match_all": {}
    },
    "sort": [
      {
        "event_date": {
          "order": "asc"
        }
      },
      {
        "event_id": {
          "order": "asc"
        }
      }
    ]
  }'
```

Inspect the final hit.

Its response contains a `sort` array.

For example, conceptually:

```json
"sort": [
  "<event-date-sort-value>",
  "EV1002"
]
```

Use the **actual values returned by Elasticsearch**.

Do not manually guess the serialized date value.

---

# 5.35 `search_after` — Next Page

`[TUTORIAL-ACCEPTANCE — SAFE-READ]`

Copy the actual `sort` values from the final hit of the previous response.

Then use:

```json
{
  "size": 2,
  "query": {
    "match_all": {}
  },
  "search_after": [
    "<actual-event-date-sort-value>",
    "<actual-event-id-sort-value>"
  ],
  "sort": [
    {
      "event_date": {
        "order": "asc"
      }
    },
    {
      "event_id": {
        "order": "asc"
      }
    }
  ]
}
```

For example, using `curl` after substituting the actual returned values:

```bash
curl -u "$ES_USER:$ES_PASSWORD" \
  -X GET "$ES_URL/sre_tutorial_05/_search?pretty" \
  -H 'Content-Type: application/json' \
  -d '{
    "size": 2,
    "query": {
      "match_all": {}
    },
    "search_after": [
      "<actual-event-date-sort-value>",
      "<actual-event-id-sort-value>"
    ],
    "sort": [
      {
        "event_date": {
          "order": "asc"
        }
      },
      {
        "event_id": {
          "order": "asc"
        }
      }
    ]
  }'
```

The query and sort structure should remain consistent between pages.

---

# 5.36 Why a Tie-Breaker Matters

Imagine two documents have the same:

```text
event_date
```

If that is the only sort field, their relative ordering may not provide the stable deterministic behavior required by the application.

This tutorial therefore adds:

```text
event_id
```

as a secondary sort field.

Conceptually:

```text
event_date
    ↓
Primary ordering

event_id
    ↓
Deterministic secondary ordering
```

Production tie-breaker design should use an appropriate field for the application's mapping and uniqueness guarantees.

---

# 5.37 Point in Time — Conceptual Introduction

`search_after` addresses deep pagination mechanics, but changing data introduces another concern.

```text
Page 1
   ↓
Documents inserted/updated/deleted
   ↓
Page 2
   ↓
Search view may have changed
```

For workflows requiring a more consistent search view across multiple pages, evaluate Elasticsearch Point in Time capabilities for the deployed version.

Conceptually:

```text
Open search view
      ↓
PIT
      ↓
search_after
      ↓
Subsequent pages
      ↓
Close/expire PIT
```

This tutorial does not turn PIT into a production runbook.

PIT lifecycle, resource implications, keep-alive selection, failure handling, and version-specific behavior should be reviewed before production adoption.

---

# Part X — Aggregations

# 5.38 Basic Terms Aggregation

```bash
curl -u "$ES_USER:$ES_PASSWORD" \
  -X GET "$ES_URL/sre_tutorial_05/_search?pretty" \
  -H 'Content-Type: application/json' \
  -d '{
    "size": 0,
    "aggs": {
      "events_by_status": {
        "terms": {
          "field": "status"
        }
      }
    }
  }'
```

Using:

```json
"size": 0
```

is appropriate when document hits are not needed and only aggregation results are required.

---

# 5.39 Metric Aggregation

```bash
curl -u "$ES_USER:$ES_PASSWORD" \
  -X GET "$ES_URL/sre_tutorial_05/_search?pretty" \
  -H 'Content-Type: application/json' \
  -d '{
    "size": 0,
    "aggs": {
      "average_amount": {
        "avg": {
          "field": "amount"
        }
      }
    }
  }'
```

---

# 5.40 Filter Before Aggregating

When the business requirement permits it, narrow the dataset before performing aggregation work.

```bash
curl -u "$ES_USER:$ES_PASSWORD" \
  -X GET "$ES_URL/sre_tutorial_05/_search?pretty" \
  -H 'Content-Type: application/json' \
  -d '{
    "size": 0,
    "query": {
      "bool": {
        "filter": [
          {
            "term": {
              "status": "completed"
            }
          },
          {
            "range": {
              "event_date": {
                "gte": "2026-09-10T00:00:00Z",
                "lt": "2026-09-16T00:00:00Z"
              }
            }
          }
        ]
      }
    },
    "aggs": {
      "events_by_specialty": {
        "terms": {
          "field": "specialty"
        }
      }
    }
  }'
```

Aggregation cost can depend on factors such as:

```text
Matching document count
Field cardinality
Bucket count
Shard distribution
Aggregation hierarchy
Concurrency
```

A small tutorial aggregation should not be interpreted as proof that the equivalent production aggregation is inexpensive.

---

# Part XI — Nested Queries

# 5.41 Nested Query Requirement

If a field is mapped as:

```text
nested
```

a normal object query is not automatically equivalent to a nested query.

Conceptually:

```text
nested mapping
      ↓
nested query
      ↓
Preserve object-level relationship
```

Example structure:

```json
{
  "query": {
    "nested": {
      "path": "providers",
      "query": {
        "bool": {
          "must": [
            {
              "term": {
                "providers.name": "Alice"
              }
            },
            {
              "term": {
                "providers.specialty": "cardiology"
              }
            }
          ]
        }
      }
    }
  }
}
```

The tutorial dataset does not require a nested field, so this remains conceptual rather than introducing another disposable index.

---

# Part XII — Potentially Expensive Queries

# 5.42 Wildcard Queries

Wildcard queries can be legitimate.

Example:

```text
cardio*
```

But cost depends on factors such as:

```text
Pattern structure
Field design
Term dictionary
Index size
Shard count
Concurrency
```

Leading wildcards deserve particular caution:

```text
*ology
```

Do not use wildcard search as the default substitute for appropriate mapping and search design.

---

# 5.43 Regexp Queries

Regular-expression queries can also create substantial work.

Review:

```text
Pattern complexity
Field cardinality
Index size
Shard count
Request concurrency
Production latency
```

before treating a regexp as production-safe.

A syntactically valid regexp is not automatically an operationally appropriate query.

---

# 5.44 `search.allow_expensive_queries`

Elasticsearch provides:

```text
search.allow_expensive_queries
```

as an operational safeguard affecting query types classified as expensive by the deployed Elasticsearch version.

The exact query families and behavior must be checked against that version.

If an application query is rejected because an expensive-query safeguard is active, do **not** immediately respond by disabling the safeguard.

Use:

```text
Query rejected
      ↓
Understand business requirement
      ↓
Inspect mapping
      ↓
Inspect query pattern
      ↓
Evaluate alternative indexing/search design
      ↓
Evaluate operational implications
```

This tutorial intentionally does **not** provide a command to disable the safeguard.

---

# 5.45 Script-Based Queries

Scripts provide powerful custom logic but can introduce additional per-document computation and CPU cost.

Before choosing a script-based query, ask:

```text
Can the value be calculated during ingestion?
        ↓
Can it be indexed explicitly?
        ↓
Can normal Query DSL solve the requirement?
        ↓
Only then evaluate whether scripting is justified
```

Conceptually:

```text
Indexed query
      ↓
Use indexed structures


Script evaluation
      ↓
Additional runtime logic
      ↓
Potential CPU impact
```

Script-based queries remain conceptual in this tutorial.

---

# Part XIII — Query Anti-Patterns and Review Patterns

# 5.46 Large Result Requests

A request such as:

```json
{
  "size": 10000
}
```

is not universally wrong merely because the number is large.

Operational impact depends on:

```text
Requested size
      ×
Source/document size
      ×
Shard fan-out
      ×
Sorting
      ×
Concurrency
      ↓
Resource impact
```

Applications should request only the data they actually require.

---

# 5.47 Broad Query + Large Size + Sort

An important operational pattern is:

```text
Broad query
    +
Large result size
    +
Sort
    +
Concurrency
    ↓
Potentially expensive workload
```

Example:

```json
{
  "size": 10000,
  "query": {
    "match_all": {}
  },
  "sort": [
    {
      "event_date": {
        "order": "desc"
      }
    }
  ]
}
```

The query is valid Query DSL.

The operational question is whether the workload actually requires this breadth, result size, sorting behavior, and request frequency.

---

# 5.48 `match_all` Is Not Inherently Bad

`match_all` is a legitimate query when the requirement genuinely targets all documents.

Review it when:

```text
Application-generated query uses it redundantly

OR

Business requirement could safely narrow the dataset

OR

Large historical dataset + sort + large size + concurrency
creates unnecessary work
```

Do not label valid syntax as an anti-pattern without considering workload intent.

---

# 5.49 Repeated Boolean Clauses

Generated queries sometimes contain repeated or logically redundant conditions.

Conceptually:

```text
bool
 |
 +-- repeated condition
 +-- repeated condition
 +-- repeated condition
 +-- repeated condition
```

This can indicate application-side query-generation problems.

Before adding Elasticsearch capacity to accommodate such requests, determine whether the producer can generate a simpler equivalent query.

Keep boolean structures as understandable and flat as practical.

---

# 5.50 Narrow the Date Range When Appropriate

If the application requires only recent records:

```text
Business requirement
      ↓
30 days
      ↓
Query 30 days
```

rather than unnecessarily searching years of history.

However, historical searches may genuinely require a broader range.

The principle is:

> Query only the data required by the business operation when the requirement permits narrowing.

---

# Part XIV — Query Concurrency and Production Impact

# 5.51 One Query vs a Workload

A query may appear acceptable during isolated testing.

For example:

```text
1 request
   ↓
100 ms
```

That does not prove:

```text
500 concurrent requests
   ↓
safe
```

Production behavior depends on the complete workload.

Conceptually:

```text
Query complexity
       ×
Shard fan-out
       ×
Data volume
       ×
Result size
       ×
Concurrency
       ↓
Production impact
```

This is a mental model, not an Elasticsearch cost formula.

---

# 5.52 Search Execution Pressure

Expensive searches combined with concurrency can create:

```text
Expensive query
      ×
High concurrency
      ↓
Search execution pressure
      ↓
Queueing
      ↓
Higher latency
      ↓
Possible rejections
```

Therefore, SRE/DBRE query analysis must consider both:

```text
Single-query latency
```

and:

```text
Workload-level impact
```

---

# Part XV — SRE/DBRE Query Review

# 5.53 Production Query Review Questions

When reviewing a slow or expensive query, ask:

1. Which index, alias, or data stream is queried?
2. How many shards are involved?
3. What is the index size?
4. Approximately how many documents are involved?
5. Which fields are queried?
6. What are their mappings?
7. Is relevance scoring actually required?
8. Could structured conditions use filter context?
9. Is the query searching unnecessary historical data?
10. What `size` is requested?
11. Is deep pagination involved?
12. Is `from` unusually large?
13. Is sorting required?
14. Which fields are sorted?
15. Are aggregations present?
16. Are high-cardinality fields involved?
17. Are wildcard or regexp queries present?
18. Are scripts present?
19. Are boolean clauses duplicated?
20. What is application concurrency?
21. What is request frequency?
22. Are retries multiplying the workload?
23. What do slow logs show?
24. What do cluster metrics show?
25. Is there queueing or rejection evidence?
26. Has the same query been tested under representative concurrency?

A single query body rarely tells the complete production story.

---

# Part XVI — Query Diagnostics

# 5.54 Start With the Mapping

`[TUTORIAL-ACCEPTANCE — SAFE-READ]`

```bash
curl -u "$ES_USER:$ES_PASSWORD" \
  "$ES_URL/sre_tutorial_05/_mapping?pretty"
```

Confirm whether relevant fields are:

```text
text
keyword
date
numeric
boolean
object
nested
```

Query troubleshooting without mapping knowledge is guesswork.

---

# 5.55 Count Carefully

`[TUTORIAL-ACCEPTANCE — SAFE-READ]`

On the tiny tutorial index:

```bash
curl -u "$ES_USER:$ES_PASSWORD" \
  -X GET "$ES_URL/sre_tutorial_05/_count?pretty" \
  -H 'Content-Type: application/json' \
  -d '{
    "query": {
      "term": {
        "status": "completed"
      }
    }
  }'
```

is harmless.

On very large production datasets, an exact count may still represent meaningful work.

Remember:

```text
Read-only
   ≠
Zero-cost
```

---

# 5.56 Slow Logs as Evidence

Slow logs can help connect:

```text
Application request
       ↓
Actual Elasticsearch query
       ↓
Observed execution behavior
```

A useful investigation combines:

```text
Query body
+
Mapping
+
Slow logs
+
Cluster metrics
+
Application concurrency
+
Index/shard characteristics
```

Detailed slow-log configuration belongs in a later observability/troubleshooting tutorial.

---

# 5.57 Profile API

`[PRODUCTION-DIAGNOSTIC — REVIEW-REQUIRED]`

Elasticsearch query profiling can help identify where query execution work occurs.

Conceptually:

```text
Slow query
   ↓
Profile
   ↓
Query components
   ↓
Execution detail
```

However, profiling adds significant overhead.

Therefore:

```text
Routine application request
        ↓
Do NOT automatically profile


Controlled investigation
        ↓
Profile when justified
```

A profiled request should not be treated as though profiling were free.

Also remember that query profiling does not represent every component of complete end-to-end application latency.

For example, overall latency can include factors outside the detailed query execution components exposed by profiling.

Use the Profile API as a diagnostic instrument, not as routine application behavior.

---

# Part XVII — Production Query Governance

# 5.58 Application/Data Team Responsibilities

Application and data teams should understand and document:

```text
Business requirement
Search semantics
Expected result size
Date-range requirement
Pagination requirement
Sorting requirement
Aggregation requirement
Expected request rate
Expected concurrency
Retry behavior
```

---

# 5.59 Elasticsearch / SRE / DBRE Responsibilities

Elasticsearch/platform teams should review:

```text
Field mappings
Index and shard characteristics
Query structure
Result size
Pagination behavior
Sorting
Aggregation cost
Wildcard/regexp usage
Scripts
Concurrency
Slow-log evidence
Cluster resource impact
Operational safeguards
```

---

# 5.60 Shared Query Ownership

Production queries are a shared operational contract.

```text
Application/Data team
       ↓
Own business/query intent


Elasticsearch/SRE/DBRE
       ↓
Review operational implications


Both
       ↓
Production-safe query pattern
```

A slow query should not automatically be treated as an infrastructure-only problem.

Likewise, application teams should not be expected to diagnose Elasticsearch internals without platform support.

---

# Part XVIII — Cleanup

# 5.61 Cleanup Precheck

`[TUTORIAL-ACCEPTANCE — SAFE-READ]`

```bash
curl -u "$ES_USER:$ES_PASSWORD" \
  "$ES_URL/_cat/indices/sre_tutorial_05?v"
```

Confirm the exact index:

```text
sre_tutorial_05
```

Do not use:

```text
sre_tutorial_05*
*
_all
```

for tutorial cleanup.

---

# 5.62 Delete the Tutorial Index

`[TUTORIAL-LAB — DESTRUCTIVE]`

```bash
curl -u "$ES_USER:$ES_PASSWORD" \
  -X DELETE "$ES_URL/sre_tutorial_05"
```

This command intentionally names exactly one disposable tutorial index.

---

# 5.63 Verify Cleanup

`[TUTORIAL-ACCEPTANCE — SAFE-READ]`

```bash
curl -u "$ES_USER:$ES_PASSWORD" \
  "$ES_URL/_cat/indices/sre_tutorial_05?v"
```

The tutorial index should no longer exist.

---

# Part XIX — Tutorial Acceptance

# 5.64 Acceptance Check

You should now be able to explain:

1. What Query DSL is.
2. Query context versus filter context.
3. When `match` is appropriate.
4. When `term` is appropriate.
5. Why `term` against analyzed `text` can be surprising.
6. What `terms` does.
7. How `range` works.
8. What `exists` means.
9. How `bool` combines clauses.
10. `must` versus `filter`.
11. How `must_not` behaves.
12. Why `should` is not simply universal `OR`.
13. How `minimum_should_match` defaults change with surrounding clauses.
14. What `_source` filtering changes.
15. Sorting considerations.
16. `from` and `size`.
17. What `index.max_result_window` controls.
18. Why deep pagination can be expensive.
19. How `search_after` works.
20. Why deterministic secondary sorting matters.
21. Why changing datasets affect multi-page search consistency.
22. What PIT is intended to address conceptually.
23. Basic terms and metric aggregations.
24. Why aggregation cost is workload-dependent.
25. Why nested mappings require appropriate nested queries.
26. Why wildcard and regexp queries require operational review.
27. What `search.allow_expensive_queries` represents conceptually.
28. Why script-based queries require caution.
29. Why large result requests require workload context.
30. Why `match_all` is valid but may still create overly broad workloads.
31. Why repeated bool clauses may indicate producer problems.
32. Why relevant date-range narrowing can matter.
33. Why concurrency changes query impact.
34. How search pressure can lead to queueing and rejections.
35. Why mappings are part of query troubleshooting.
36. Why read-only counts can still have cost.
37. How slow logs contribute evidence.
38. Why the Profile API must be used deliberately.
39. Why query ownership is shared between application and platform teams.
40. Why version-specific verification is required.

---

# 5.65 SRE/DBRE Mental Model

Remember:

```text
Business requirement
       ↓
Query DSL
       ↓
Mapping
       ↓
Indices / shards
       ↓
Execution
       ↓
CPU
Heap
Disk I/O
Search execution capacity
Network
       ↓
Latency + reliability
```

And:

```text
One query
    ×
Concurrent requests
    ×
Shard fan-out
    ×
Data volume
    ×
Result size
    ↓
Production behavior
```

---

# 5.66 Key Production Principles

**Know the mapping before diagnosing the query.**

**Use full-text queries for full-text requirements and exact queries for exact structured values.**

**Use filter context when relevance scoring is not required.**

**Make `minimum_should_match` explicit when `should` clauses are logically mandatory.**

**Do not request more results than the application actually needs.**

**Do not solve deep pagination merely by increasing `index.max_result_window`.**

**Use deterministic sorting for `search_after`.**

**Evaluate PIT when a consistent multi-page search view is required.**

**Do not treat wildcard, regexp, or script queries as harmless conveniences.**

**Do not immediately disable expensive-query safeguards when a query is rejected.**

**Do not assume a query that performs well once will perform well under production concurrency.**

**Do not tune Elasticsearch around unnecessarily complicated generated queries before examining the producer.**

**Use `match_all` when it matches the real requirement—not merely because it is convenient.**

**Narrow the dataset when the business requirement permits it.**

**Treat read-only diagnostic queries according to their actual production cost.**

**Use the Profile API deliberately because profiling itself adds overhead.**

**Treat production queries as a shared application and Elasticsearch operational contract.**

**Validate version-sensitive behavior against the Elasticsearch version actually deployed.**

---

# Vendor Reference Topics

Validate production implementation against the official Elastic documentation for the deployed Elasticsearch version, especially:

```text
Query and filter context
Match query
Term-level queries
Bool query
minimum_should_match
Exists query
Range query
Source filtering
Sorting
Pagination
index.max_result_window
search_after
Point in Time
Terms aggregations
Nested queries
Wildcard queries
Regexp queries
Script queries
search.allow_expensive_queries
Profile API
Slow logs
```

Vendor documentation is used for technical validation. The tutorial's explanatory prose, diagrams, lab design, synthetic dataset, operational review model, safety taxonomy, and governance framework are original instructional material.

---

# Canonical Status

**Module:** 05 — Query DSL for DBRE/SRE
**Tutorial:** 05 — Query DSL for DBRE/SRE
**Edition:** Revised Final / Canonical
**Technical + Vendor Source Review:** PASS
**Production + Safety Review:** PASS
**Copyright / Originality Review:** PASS
**Dedicated Lab Index:** `sre_tutorial_05`
**Synthetic Dataset:** PASS
**Query / Filter Context:** PASS
**`match` / `term` / `terms`:** PASS
**`range` / `exists`:** PASS
**Bool Query Semantics:** PASS
**`minimum_should_match` Guidance:** PASS
**Source Filtering:** PASS
**Sorting:** PASS
**Deep Pagination Safeguards:** PASS
**`search_after` Hands-On Lab:** PASS
**Deterministic Pagination Guidance:** PASS
**PIT Conceptual Guidance:** PASS
**Aggregation Guidance:** PASS
**Nested Query Guidance:** PASS
**Wildcard / Regexp Safeguards:** PASS
**Script Query Safeguards:** PASS
**Expensive-Query Safeguard Guidance:** PASS
**Profile API Safety Boundary:** PASS
**Concurrency / Search-Pressure Model:** PASS
**SRE/DBRE Query Review Workflow:** PASS
**Query Governance:** PASS
**Basic Authentication:** Included
**Exact-Name Destructive Guardrails:** Included
**Elasticsearch Version Scope:** Included

**Publication Status:** **CANONICAL — READY FOR REPOSITORY VALIDATION**
