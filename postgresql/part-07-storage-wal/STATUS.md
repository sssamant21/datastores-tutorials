# Part 7 --- Storage & WAL --- Status

**Status:** PLANNED\
**Canonical progress:** **0/15 canonical + merged**\
**Target:** PostgreSQL 18\
**Authoritative layout:** `MASTER-LAYOUT.md` --- LOCKED, Master Layout
v1.0

Status values:

`PLANNED` \| `DRAFT` \| `LAB VALIDATED` \| `CANONICAL + MERGED` \|
`BLOCKED`

  ------------------------------------------------------------------------------------------------------------------------
  Section    Title          Tutorial   Lab / Acceptance Artifact               Lab Status Evidence / Notes
                            Status                                                        Commit     
  ---------- -------------- ---------- --------------------------------------- ---------- ---------- ---------------------
  7.1        PostgreSQL     PLANNED    `labs/storage-architecture-check.sql`   PLANNED    ---        SAFE-READ target
             Storage                                                                                 
             Architecture                                                                            
             Fundamentals                                                                            

  7.2        Pages, Blocks, PLANNED    `labs/page-block-inspection.sql`        PLANNED    ---        Page inspection
             and Physical                                                                            
             Layout                                                                                  

  7.3        Tuples and     PLANNED    `labs/heap-tuple-inspection.sql`        PLANNED    ---        Controlled inspection
             Heap Storage                                                                            
             Internals                                                                               

  7.4        MVCC at the    PLANNED    `labs/mvcc-storage-lab.sql`             PLANNED    ---        LAB-WRITE
             Storage Layer                                                                           

  7.5        Free Space Map PLANNED    `labs/fsm-vm-inspection.sql`            PLANNED    ---        SAFE-READ target
             and Visibility                                                                          
             Map                                                                                     

  7.6        TOAST and      PLANNED    `labs/toast-storage-lab.sql`            PLANNED    ---        Controlled lab
             Large-Value                                                                             
             Storage                                                                                 

  7.7        Relation       PLANNED    `labs/relation-file-inspection.sql`     PLANNED    ---        SAFE-READ
             Files, Forks,                                                                           
             and Segment                                                                             
             Files                                                                                   

  7.8        Shared Buffers PLANNED    `labs/buffer-io-observation.sql`        PLANNED    ---        Observation-focused
             and the                                                                                 
             Storage I/O                                                                             
             Path                                                                                    

  7.9        WAL            PLANNED    `labs/wal-internals-check.sql`          PLANNED    ---        SAFE-READ target
             Architecture                                                                            
             and Internals                                                                           

  7.10       WAL            PLANNED    `labs/wal-generation-experiment.sql`    PLANNED    ---        LAB-WRITE
             Generation,                                                                             
             LSNs, and WAL                                                                           
             Volume                                                                                  

  7.11       Checkpoints,   PLANNED    `labs/checkpoint-observation.sql`       PLANNED    ---        Production-safe
             Background                                                                              observation
             Writer, and                                                                             
             Write Behavior                                                                          

  7.12       Tablespaces    PLANNED    `labs/tablespace-inspection.sql`        PLANNED    ---        SAFE-READ target
             and Storage                                                                             
             Placement                                                                               

  7.13       Temporary      PLANNED    `labs/temp-file-spill-lab.sql`          PLANNED    ---        Controlled spill lab
             Files, Sorts,                                                                           
             Hashes, and                                                                             
             Spill                                                                                   

  7.14       Storage        PLANNED    `labs/storage-sizing-check.sql`         PLANNED    ---        SAFE-READ / sizing
             Capacity,                                                                               
             Growth, and                                                                             
             Sizing                                                                                  

  7.15       Integrated     PLANNED    `labs/transaction-storage-trace.sql`;   PLANNED    ---        Final gate
             Project ---               `labs/storage-wal-acceptance.md`                              
             Trace SQL →                                                                             
             Buffers → WAL                                                                           
             → Storage                                                                               
  ------------------------------------------------------------------------------------------------------------------------

## Completion Rule

A section counts toward `N/15` only when:

1.  the tutorial reaches Revised Final / Canonical Edition;
2.  its locked lab or acceptance artifact is validated;
3.  PostgreSQL 18 technical behavior is vendor-validated;
4.  production safety boundaries and cleanup are explicit;
5.  expected, negative, and UNKNOWN evidence paths are documented where
    applicable;
6.  sensitive evidence is protected; and
7.  repository validation confirms the final artifacts on `main`.

Part 7 becomes `15/15 canonical + merged` only after 7.15 demonstrates
the complete transaction-storage path with evidence across SQL, buffers,
WAL, durability, page persistence, relation storage, and capacity
impact.

## Tracker Strategy

The tracker is initialized at Part 7 setup.

Per-module work follows the locked stage-gated workflow, but the
comprehensive `STATUS.md` evidence update is deferred until completion
of 7.15.

## Next Workflow Stage

Start **Part 7.1 --- PostgreSQL Storage Architecture Fundamentals**:

**Draft → PostgreSQL 18 Technical Validation → Production Review →
Canonical → Generate Files → Manual Push → Repository Validation**
