# Part 7 --- Storage & WAL --- Master Layout

**Target:** PostgreSQL 18\
**Status:** LOCKED --- Master Layout v1.0\
**Audience:** PostgreSQL Administrators, DBREs, SREs, Platform Engineers

## Mission

Part 7 builds a production-oriented understanding of PostgreSQL physical
storage and WAL behavior: pages and blocks, heap tuples, MVCC storage
effects, free-space and visibility metadata, TOAST, relation files and
forks, shared buffers and I/O, WAL generation and durability,
checkpoints, tablespaces, temporary-file spill, and storage sizing.

The final integrated project traces a transaction from SQL execution
through buffers and WAL to persistent storage using observable evidence
rather than assumptions.

## Prerequisites and Scope Boundary

Parts 1--6 are prerequisites.

Part 7 applies rather than repeats:

-   foundational PostgreSQL architecture and configuration
-   SQL objects, tables, indexes, roles, and privileges
-   VACUUM/autovacuum concepts introduced earlier
-   Part 5 backup, recovery, WAL recovery, RPO, and RTO
-   Part 6 replication, WAL transport, HA, promotion, fencing, and
    failover

Part 7 owns the physical-storage and WAL-internals perspective.

``` text
Part 5 -> backup and recovery
Part 6 -> replication and HA
Part 7 -> storage behavior and WAL internals
```

Out of scope unless needed for storage interpretation:

-   backup redesign
-   PITR procedures
-   replication topology design
-   failover orchestration
-   logical replication / CDC
-   vendor-specific storage implementation
-   filesystem administration unrelated to PostgreSQL

## Canonical Workflow

Every section follows:

1.  Draft + Hands-On Lab
2.  PostgreSQL 18 Technical / Vendor Documentation Validation
3.  Production + Safety Review
4.  Revised Final / Canonical Edition
5.  Generate locked tutorial/lab artifacts
6.  Manual commit to `main`
7.  Fetch back and validate repository state

The Part 7 status tracker receives its comprehensive final update after
7.15.

## 15-Section Curriculum

  ---------------------------------------------------------------------------------------
  Section                 Tutorial                Canonical Lab / Acceptance Artifact
  ----------------------- ----------------------- ---------------------------------------
  7.1                     PostgreSQL Storage      `labs/storage-architecture-check.sql`
                          Architecture            
                          Fundamentals            

  7.2                     Pages, Blocks, and      `labs/page-block-inspection.sql`
                          Physical Layout         

  7.3                     Tuples and Heap Storage `labs/heap-tuple-inspection.sql`
                          Internals               

  7.4                     MVCC at the Storage     `labs/mvcc-storage-lab.sql`
                          Layer                   

  7.5                     Free Space Map and      `labs/fsm-vm-inspection.sql`
                          Visibility Map          

  7.6                     TOAST and Large-Value   `labs/toast-storage-lab.sql`
                          Storage                 

  7.7                     Relation Files, Forks,  `labs/relation-file-inspection.sql`
                          and Segment Files       

  7.8                     Shared Buffers and the  `labs/buffer-io-observation.sql`
                          Storage I/O Path        

  7.9                     WAL Architecture and    `labs/wal-internals-check.sql`
                          Internals               

  7.10                    WAL Generation, LSNs,   `labs/wal-generation-experiment.sql`
                          and WAL Volume          

  7.11                    Checkpoints, Background `labs/checkpoint-observation.sql`
                          Writer, and Write       
                          Behavior                

  7.12                    Tablespaces and Storage `labs/tablespace-inspection.sql`
                          Placement               

  7.13                    Temporary Files, Sorts, `labs/temp-file-spill-lab.sql`
                          Hashes, and Spill       

  7.14                    Storage Capacity,       `labs/storage-sizing-check.sql`
                          Growth, and Sizing      

  7.15                    Integrated Project ---  `labs/transaction-storage-trace.sql`;
                          Trace SQL → Buffers →   `labs/storage-wal-acceptance.md`
                          WAL → Storage           
  ---------------------------------------------------------------------------------------

## Section Intent

### 7.1 --- PostgreSQL Storage Architecture Fundamentals

Establish the end-to-end storage model: database objects, relation
storage, pages, buffers, WAL, checkpoints, filesystem persistence, and
the distinction between logical and physical views.

### 7.2 --- Pages, Blocks, and Physical Layout

Understand PostgreSQL page structure, block numbering, page headers,
item identifiers, page inspection boundaries, and how relation size maps
to blocks.

### 7.3 --- Tuples and Heap Storage Internals

Inspect heap tuples, tuple headers, CTIDs, row versions, tuple
placement, and the physical consequences of INSERT, UPDATE, and DELETE.

### 7.4 --- MVCC at the Storage Layer

Connect transaction visibility to physical row versions, dead tuples,
HOT behavior where applicable, cleanup, reuse, and storage growth.

### 7.5 --- Free Space Map and Visibility Map

Understand FSM and VM forks, free-space tracking, all-visible/all-frozen
state, VACUUM interaction, and operational interpretation.

### 7.6 --- TOAST and Large-Value Storage

Explain out-of-line storage, compression behavior, TOAST relations,
chunk storage, storage strategies, and sizing implications for large
attributes.

### 7.7 --- Relation Files, Forks, and Segment Files

Map PostgreSQL relations to physical files and forks, understand
relfilenode/filenode concepts, relation segments, and safe
filesystem-level observation.

### 7.8 --- Shared Buffers and the Storage I/O Path

Trace reads and writes through PostgreSQL buffers, dirty pages, backend
I/O, background activity, and operating-system/storage boundaries.

### 7.9 --- WAL Architecture and Internals

Establish WAL record purpose, WAL buffers, WAL files, LSNs, durability
ordering, full-page images, and the write-ahead rule.

### 7.10 --- WAL Generation, LSNs, and WAL Volume

Measure WAL generation for controlled workloads, compare LSN positions,
calculate WAL volume, and interpret workload-driven WAL growth.

### 7.11 --- Checkpoints, Background Writer, and Write Behavior

Understand checkpoint triggers, dirty-buffer flushing, checkpoint
completion, write pressure, WAL recycling, and production performance
implications.

### 7.12 --- Tablespaces and Storage Placement

Understand PostgreSQL tablespaces, object placement, filesystem
dependencies, operational constraints, and safe placement decisions.

### 7.13 --- Temporary Files, Sorts, Hashes, and Spill

Observe temporary-file generation from memory-constrained operations,
connect spills to `work_mem` and workload behavior, and monitor storage
impact.

### 7.14 --- Storage Capacity, Growth, and Sizing

Build a production sizing model covering relation growth, indexes,
TOAST, WAL, temporary files, free-space requirements, maintenance
headroom, and growth rate.

### 7.15 --- Integrated Project --- Trace SQL → Buffers → WAL → Storage

Trace a controlled transaction from SQL execution through tuple/page
modification, shared buffers, WAL generation and flush, dirty-page
persistence, checkpoint/background writes, and relation/storage
evidence.

## Integrated Transaction Model

``` text
SQL Transaction
      |
      v
Parser / Executor
      |
      v
Shared Buffers
      |
      v
Heap / Index Page Modification
      |
      +----------------------+
      |                      |
      v                      v
Dirty Data Page          WAL Record
                             |
                             v
                         WAL Buffer
                             |
                             v
                         WAL Flush
                             |
                             v
                       Durable Commit

Dirty Data Page
      |
      v
Background / Checkpoint Write
      |
      v
Relation File
      |
      v
Physical Storage
```

A central Part 7 invariant is:

``` text
COMMIT durable
    !=
modified heap page already written to its relation file
```

## PostgreSQL 18 Technical Baseline

Technical validation should use current PostgreSQL 18 vendor
documentation and, where applicable:

-   database file layout
-   database pages
-   heap storage
-   MVCC storage behavior
-   free space map
-   visibility map
-   TOAST
-   relation forks and physical files
-   buffer manager and I/O statistics
-   WAL internals
-   WAL configuration
-   LSN functions
-   full-page writes
-   checkpoints
-   background writer behavior
-   tablespaces
-   temporary files
-   relation sizing functions
-   storage statistics and monitoring

Version-specific behavior must not be silently generalized to older
PostgreSQL releases.

## Production Safety Rules

1.  Verify database, instance, relation, and execution context before
    state-changing labs.
2.  Default inspection labs to SAFE-READ whenever the learning objective
    does not require mutation.
3.  Run page-level or extension-dependent inspection only with
    documented prerequisites and appropriate privileges.
4.  Never modify PostgreSQL relation files directly at the filesystem
    level.
5.  Never modify WAL files manually.
6.  Do not treat filesystem observations alone as authoritative database
    state.
7.  Use controlled disposable objects for experiments that intentionally
    generate tuples, WAL, checkpoints, or temporary files.
8.  Do not force checkpoints on production merely to demonstrate storage
    behavior.
9.  Do not intentionally exhaust disk, WAL, temp space, or shared
    memory.
10. Storage experiments must define expected growth, stop conditions,
    cleanup, and capacity headroom.
11. Do not expose credentials, secret connection material, or sensitive
    application data in evidence.
12. Separate database durability from data-page persistence.
13. Separate WAL volume from database/relation growth.
14. Separate logical relation size from total storage footprint.
15. Prefer timestamped evidence and before/after measurements over
    assumptions.

## Core Storage Invariants

``` text
logical row      != physical tuple
tuple            != page
page             != relation
relation size    != complete database footprint

WAL              != heap storage
COMMIT           != checkpoint
checkpoint       != backup
WAL flush        != dirty heap page flush

dead tuple       != immediately returned filesystem space
FSM              != visibility map
TOAST            != generic external object storage
tablespace       != independent database
temporary file   != permanent relation storage
shared_buffers   != PostgreSQL's total memory footprint
```

## Final Acceptance Philosophy

Part 7.15 must be able to answer with evidence:

``` text
Where is the relation stored?
How large is it before and after the transaction?
Which physical row/page concepts changed?
Was the relevant page buffered?
How much WAL did the workload generate?
What were the WAL LSN boundaries?
When was commit durability established?
Was the modified data page still dirty afterward?
What activity persisted dirty buffers?
What changed after checkpoint/background writing?
Did indexes or TOAST contribute additional storage?
Were temporary files generated?
What storage headroom does the workload require?
```

Final principle:

``` text
observe -> measure -> correlate -> explain
```

Part 7 is complete only when the integrated project connects SQL
behavior, buffer behavior, WAL durability, and persistent storage
without conflating those layers.
