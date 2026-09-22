# Part 6 --- Streaming Replication, High Availability & Failover --- Status

**Status:** IN PROGRESS\
**Canonical progress:** **1/15 canonical + merged**\
**Target:** PostgreSQL 18\
**Authoritative layout:** `MASTER-LAYOUT.md` --- LOCKED, Master Layout
v1.0

Status values: `PLANNED` \| `DRAFT` \| `LAB VALIDATED` \|
`CANONICAL + MERGED` \| `BLOCKED`

  -----------------------------------------------------------------------------------------------------------------------------------------------------------------
  Section    Title             Tutorial      Lab Artifact                                 Lab Status  Evidence / Commit                            Notes
                               Status                                                                                                              
  ---------- ----------------- ------------- -------------------------------------------- ----------- -------------------------------------------- ----------------
  6.1        Streaming         CANONICAL +   `labs/ha-architecture-assessment.md`         LAB         `182d9c2c390334df4b1ccb9ad3a955845c7226de`   SAFE-READ
             Replication and   MERGED                                                     VALIDATED                                                
             HA Architecture                                                                                                                       

  6.2        Replication       PLANNED       `labs/replication-prerequisites-check.sql`   PLANNED     ---                                          ---
             Prerequisites and                                                                                                                     
             Change Planning                                                                                                                       

  6.3        Replication       PLANNED       `labs/replication-access-check.sql`          PLANNED     ---                                          ---
             Identity,                                                                                                                             
             Authentication,                                                                                                                       
             and TLS                                                                                                                               

  6.4        Build a Physical  PLANNED       `labs/build-standby.sh`                      PLANNED     ---                                          LAB-WRITE
             Standby                                                                                                                               

  6.5        Verify Streaming  PLANNED       `labs/streaming-replay-check.sql`            PLANNED     ---                                          ---
             and WAL Replay                                                                                                                        

  6.6        Measure           PLANNED       `labs/replication-lag-sampler.sql`           PLANNED     ---                                          ---
             Replication Lag                                                                                                                       
             Correctly                                                                                                                             

  6.7        Asynchronous and  PLANNED       `labs/sync-policy-experiment.sql`            PLANNED     ---                                          LAB-WRITE
             Synchronous                                                                                                                           
             Replication                                                                                                                           
             Policy                                                                                                                                

  6.8        Replication       PLANNED       `labs/slot-retention-risk-check.sql`         PLANNED     ---                                          Links Part 5.10
             Slots, WAL                                                                                                                            
             Retention, and                                                                                                                        
             Standby Safety                                                                                                                        

  6.9        Read-Only         PLANNED       `labs/hot-standby-conflict-lab.sql`          PLANNED     ---                                          LAB-WRITE
             Standbys and                                                                                                                          
             Conflict                                                                                                                              
             Management                                                                                                                            

  6.10       Cascading         PLANNED       `labs/cascade-topology-check.sql`            PLANNED     ---                                          ---
             Replication and                                                                                                                       
             Topology                                                                                                                              
             Trade-offs                                                                                                                            

  6.11       Monitoring,       PLANNED       `labs/ha-observability-check.sql`            PLANNED     ---                                          SAFE-READ
             Alerting, and                                                                                                                         
             Capacity Signals                                                                                                                      

  6.12       Planned           PLANNED       `labs/planned-switchover-runbook.md`         PLANNED     ---                                          DISRUPTIVE-LAB
             Switchover                                                                                                                            

  6.13       Unplanned         PLANNED       `labs/unplanned-failover-runbook.md`         PLANNED     ---                                          DISRUPTIVE-LAB
             Failover and                                                                                                                          
             Split-Brain                                                                                                                           
             Prevention                                                                                                                            

  6.14       Rejoin, Rewind,   PLANNED       `labs/rejoin-failback-checklist.md`          PLANNED     ---                                          DISRUPTIVE-LAB
             and Failback                                                                                                                          

  6.15       Integrated        PLANNED       `labs/ha-acceptance.sql`;                    PLANNED     ---                                          Final gate
             Project ---                     `labs/ha-acceptance-checklist.md`                                                                     
             Production HA                                                                                                                         
             Readiness and                                                                                                                         
             Acceptance                                                                                                                            
  -----------------------------------------------------------------------------------------------------------------------------------------------------------------

## Completion Rule

A section counts toward `N/15` only when:

1.  the tutorial is Revised Final / Canonical Edition;
2.  its lab or acceptance artifact is validated;
3.  expected and negative paths are documented;
4.  safety boundaries and cleanup are explicit;
5.  sensitive evidence is redacted; and
6.  the exact commit is recorded above.

Part 6 becomes `15/15 canonical + merged` only after 6.15 records
topology, test window, fencing, role transitions, application
validation, measured RPO/RTO outcome, rejoin/failback result, unresolved
risks, owners, and PASS/FAIL/UNKNOWN acceptance.

## Next Workflow Stage

Start Part 6.2 --- Replication Prerequisites and Change Planning ---
Draft + Hands-On Lab.
