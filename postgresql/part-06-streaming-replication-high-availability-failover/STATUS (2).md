# Part 6 --- Streaming Replication, High Availability & Failover --- Status

**Status:** COMPLETE\
**Canonical progress:** **15/15 CANONICAL + MERGED**\
**Target:** PostgreSQL 18\
**Authoritative layout:** `MASTER-LAYOUT.md` --- LOCKED, Master Layout
v1.0\
**Final repository review:** 2026-09-26

## Completion Summary

Part 6 is complete. All 15 planned tutorial sections and their locked
lab, runbook, or acceptance artifacts are present on `main` and were
validated against the Part 6 master layout.

Status values:

`PLANNED` \| `DRAFT` \| `LAB VALIDATED` \| `CANONICAL + MERGED` \|
`BLOCKED`

  --------------------------------------------------------------------------------------------------------------------------------------------------------------------
  Section    Title             Tutorial      Lab / Acceptance Artifact                    Lab Status  Repository Evidence                           Notes
                               Status                                                                                                               
  ---------- ----------------- ------------- -------------------------------------------- ----------- --------------------------------------------- ------------------
  6.1        Streaming         CANONICAL +   `labs/ha-architecture-assessment.md`         LAB         Tutorial                                      SAFE-READ
             Replication and   MERGED                                                     VALIDATED   `736092306764b1c520833a9baeb9eda0294db5b3`;   
             HA Architecture                                                                          Lab                                           
                                                                                                      `e1263e172a988249f3d63a99e423250d9fa8e2c3`    

  6.2        Replication       CANONICAL +   `labs/replication-prerequisites-check.sql`   LAB         Tutorial                                      SAFE-READ
             Prerequisites and MERGED                                                     VALIDATED   `c1b9235d721276d1745a9754b0a7f37c6c06e378`;   
             Change Planning                                                                          Lab                                           
                                                                                                      `881c4fd2079706f31e0279e6e86ffba96826fca9`    

  6.3        Replication       CANONICAL +   `labs/replication-access-check.sql`          LAB         Tutorial                                      SAFE-READ
             Identity,         MERGED                                                     VALIDATED   `dcd388c48461c64dbe37727bb71c50c60dc174ae`;   
             Authentication,                                                                          Lab                                           
             and TLS                                                                                  `d0920031024388c03bf77809a3852215553c204a`    

  6.4        Build a Physical  CANONICAL +   `labs/build-standby.sh`                      LAB         Tutorial                                      STATE-CHANGING /
             Standby           MERGED                                                     VALIDATED   `7210156a59adabdc30cf36809bb8337582b9c2ef`;   DISPOSABLE TARGET
                                                                                                      Lab                                           
                                                                                                      `afe490d6e741fc8f362d8bda2f1e4a686bb59157`    

  6.5        Verify Streaming  CANONICAL +   `labs/streaming-replay-check.sql`            LAB         Tutorial                                      SAFE-READ
             and WAL Replay    MERGED                                                     VALIDATED   `f0061e1d9067cc5e3b0196397cec3cfbec076450`;   
                                                                                                      Lab                                           
                                                                                                      `f8e71749ee606266bdd957b200c44fdea6d01ae4`    

  6.6        Measure           CANONICAL +   `labs/replication-lag-sampler.sql`           LAB         Tutorial                                      SAFE-READ
             Replication Lag   MERGED                                                     VALIDATED   `b10de0c9d422a873884472e018b86a3c55988acf`;   
             Correctly                                                                                Lab                                           
                                                                                                      `d7bed1dc4f5904bbfa8552ca4e64d078c5f4ec40`    

  6.7        Asynchronous and  CANONICAL +   `labs/sync-policy-experiment.sql`            LAB         Tutorial                                      Controlled policy
             Synchronous       MERGED                                                     VALIDATED   `cae2c177df9f7b3e95d4fc857f0103cd7b66bf3c`;   experiment
             Replication                                                                              Lab                                           
             Policy                                                                                   `9c784136dfc107126a202bdc34b7639f96fe61b5`    

  6.8        Replication       CANONICAL +   `labs/slot-retention-risk-check.sql`         LAB         Tutorial                                      Links Part 5.10
             Slots, WAL        MERGED                                                     VALIDATED   `d6102934505939ad926df9f5b8f368ee6d93cd08`;   
             Retention, and                                                                           Lab                                           
             Standby Safety                                                                           `3a8ab5058faa7a834bdfd69bfd3e6b06a89d7151`    

  6.9        Standbys and      CANONICAL +   `labs/hot-standby-conflict-lab.sql`          LAB         Tutorial                                      LAB-WRITE
             Conflict          MERGED                                                     VALIDATED   `c8486dcd98faddfd359850d1184e70fd91b9747d`;   
             Management                                                                               Lab                                           
                                                                                                      `f5039290b31988c5b1f54bd947322f6797448523`    

  6.10       Cascading         CANONICAL +   `labs/cascade-topology-check.sql`            LAB         Tutorial                                      SAFE-READ /
             Replication and   MERGED                                                     VALIDATED   `83b972d5f465b508e7119904f7b6013651f01d49`;   observation-only
             Topology                                                                                 Lab                                           
                                                                                                      `e942e6a32847505035c07e5c819ca78ec93ea39c`    

  6.11       Monitoring,       CANONICAL +   `labs/ha-observability-check.sql`            LAB         Tutorial                                      SAFE-READ
             Alerting, and     MERGED                                                     VALIDATED   `8358ab73add4a0e20782747e5ef7dccba2448212`;   
             Capacity Signals                                                                         Lab                                           
                                                                                                      `37b2ee3f4197d0f71d65aec8b0be2798a0421a18`    

  6.12       Planned           CANONICAL +   `labs/planned-switchover-runbook.md`         LAB         Tutorial                                      DISRUPTIVE-LAB
             Switchover        MERGED                                                     VALIDATED   `6e2b5569ac2b33e2043d8233d6b144bf450bd2d2`;   
                                                                                                      Lab                                           
                                                                                                      `9fc545534f535d4093195810bdf6018c31892846`    

  6.13       Unplanned         CANONICAL +   `labs/unplanned-failover-runbook.md`         LAB         Tutorial                                      DISRUPTIVE-LAB
             Failover and      MERGED                                                     VALIDATED   `57370e8176c8f7bbd2e26e65eaef2bf5628199c5`;   
             Split-Brain                                                                              Lab                                           
             Prevention                                                                               `2daa84c7de779669fa9e2458093d750c1870b89a`    

  6.14       Rejoin, Rewind,   CANONICAL +   `labs/rejoin-failback-checklist.md`          LAB         Tutorial                                      DISRUPTIVE-LAB
             and Failback      MERGED                                                     VALIDATED   `3bfff80a07b3caa3b423f4e56eaee34d15662c01`;   
                                                                                                      Lab                                           
                                                                                                      `9f6b6e7a19eceada4e8fcef13cecd81fc1deab41`    

  6.15       Production HA     CANONICAL +   `labs/ha-acceptance.sql`;                    LAB         Tutorial                                      Final gate;
             Readiness and     MERGED        `labs/ha-acceptance-checklist.md`            VALIDATED   `8f0ae37f303f8834792de03501785be8436e24dc`;   SAFE-READ SQL +
             Acceptance                                                                               SQL                                           controlled
                                                                                                      `e2b80e2fc9a9dcb4835c3706ce61902a027bfd18`;   acceptance
                                                                                                      Checklist                                     
                                                                                                      `09a6444350768199eed48ed30b028ce80471cead`    
  --------------------------------------------------------------------------------------------------------------------------------------------------------------------

## Final Repository Validation

Validated against `MASTER-LAYOUT.md`:

-   [x] 15/15 tutorial sections present on `main`
-   [x] All locked lab/runbook artifacts present
-   [x] 6.15 integrated acceptance tutorial present
-   [x] `labs/ha-acceptance.sql` present and classified SAFE-READ
-   [x] `labs/ha-acceptance-checklist.md` present
-   [x] Planned switchover runbook present
-   [x] Unplanned failover / split-brain runbook present
-   [x] Rejoin / rewind / failback checklist present
-   [x] Final HA acceptance gate present
-   [x] PostgreSQL 18 remains the Part 6 technical target
-   [x] Part 6 preserves the boundary that replication is not backup
-   [x] Final acceptance preserves one-writer, fencing, evidence,
    RPO/RTO, backup/restore, and operational-ownership controls

## Final Acceptance Principles

``` text
streaming        != zero data loss
promotion        != complete failover
replication      != backup
process healthy  != application healthy
missing evidence = UNKNOWN
one writer       = mandatory
primary unreachable != primary fenced
rejoin           != failback
```

## Completion Rule --- Satisfied

A section counts toward `N/15` only when:

1.  the tutorial is Revised Final / Canonical Edition;
2.  its lab or acceptance artifact is validated;
3.  expected and negative paths are documented;
4.  safety boundaries and cleanup are explicit;
5.  sensitive evidence is protected; and
6.  repository evidence is recorded.

All 15 sections have reached the final Part 6 repository gate.

## Final Status

``` text
PART 6
Streaming Replication, High Availability & Failover

15 / 15 CANONICAL + MERGED

STATUS: COMPLETE
```

The next PostgreSQL curriculum part should begin only as a new stage;
Part 6 requires no additional planned tutorial modules.
