# Rejoin, Rewind, and Failback Checklist

**Module:** PostgreSQL Part 6.14 --- Rejoin, Rewind, and Failback\
**Classification:** **DISRUPTIVE-LAB**

> **WARNING:** This checklist contains destructive recovery and HA
> role-transition operations. Execute only in an isolated lab or under
> an explicitly approved production procedure.

## 1. Core Safety Rules

``` text
REJOIN != FAILBACK
REWIND != MERGE
ROUTING != FENCING
REWIND SUCCESS != STARTUP APPROVAL

SOURCE = B = AUTHORITATIVE PRIMARY
TARGET = A = QUARANTINED FORMER PRIMARY
```

## 2. Recovery Record

``` text
Incident/change ID:
Operator:
Authoritative primary:
Former primary:
Application owner:
Infrastructure owner:
Start time:
```

## 3. Verify B Is Stable

``` text
[ ] PostgreSQL healthy
[ ] application healthy
[ ] storage healthy
[ ] CPU/memory acceptable
[ ] connection capacity acceptable
[ ] WAL generation understood
[ ] monitoring active
[ ] backup state understood
```

## 4. Verify A Is Quarantined

``` text
[ ] excluded from application writable routing
[ ] excluded from writable DNS/VIP
[ ] excluded from load-balancer write paths
[ ] excluded from service-discovery write paths
[ ] scheduled/batch/maintenance writers excluded
```

Record fencing/quarantine evidence.

## 5. Preserve Evidence

``` text
[ ] PostgreSQL logs
[ ] system logs
[ ] timeline/history evidence
[ ] relevant configuration
[ ] failure timestamps
[ ] platform/storage evidence
```

``` text
Evidence location:
Captured by:
Timestamp:
```

## 6. Rewind Eligibility

``` text
[ ] shared cluster ancestry established
[ ] timeline relationship understood
[ ] A target integrity acceptable
[ ] data checksums enabled OR wal_log_hints was enabled
[ ] full_page_writes requirement satisfied
[ ] required WAL/history available or recoverable
[ ] B connectivity validated
[ ] A target data directory accessible
```

``` text
Rewind eligibility: ELIGIBLE / NOT ELIGIBLE / UNKNOWN
```

`NOT ELIGIBLE` or `UNKNOWN` means investigate or rebuild; do not
experimentally rewind.

## 7. WAL/Archive Gate

``` text
[ ] required target WAL present in pg_wal
```

If not:

``` text
[ ] required WAL available from approved archive
[ ] target restore_command validated
```

Conditional command shape:

``` bash
pg_rewind   --restore-target-wal   --target-pgdata="$PGDATA"   --source-server="<approved connection to B>"
```

If required WAL cannot be recovered, rebuild.

## 8. Confirm Source and Target

``` text
SOURCE = B
ROLE   = AUTHORITATIVE PRIMARY

TARGET = A
ROLE   = QUARANTINED FORMER PRIMARY
```

``` text
[ ] --source-server resolves to B
[ ] --target-pgdata identifies A
[ ] command is executed from intended A recovery environment
[ ] B remains application primary

Confirmed by:
Timestamp:
```

## 9. Credential Safety

``` text
[ ] passwords not embedded in evidence
[ ] credential-bearing conninfo not captured
[ ] approved secret/authentication mechanism used
[ ] rewind privileges appropriate
```

## 10. Dry Run

Where practical:

``` bash
pg_rewind   --dry-run   --target-pgdata="$PGDATA"   --source-server="<approved connection to B>"
```

``` text
Dry run executed: YES / NO
Result:
Evidence:
```

## 11. Destructive Rewind GO / NO-GO

``` text
[ ] B authoritative and stable
[ ] A quarantined
[ ] evidence preserved
[ ] rewind eligibility = ELIGIBLE
[ ] WAL/history available or recoverable
[ ] SOURCE = B confirmed
[ ] TARGET = A confirmed
[ ] credentials/connectivity validated
[ ] dry run passed where practical
[ ] rebuild fallback available
[ ] operator approval recorded

REWIND GO: YES / NO
Approved by:
Timestamp:
```

## 12. Execute Rewind

> **STATE-CHANGING / DESTRUCTIVE RECOVERY OPERATION**

``` bash
pg_rewind   --target-pgdata="$PGDATA"   --source-server="<approved connection to B>"
```

Do not use `--no-sync` for the production rejoin operation.

Record start, completion, result, and evidence.

## 13. Rewind Failure

If rewind fails:

``` text
STOP
  ↓
capture output
  ↓
preserve evidence
  ↓
DO NOT START A
  ↓
assess target
  ↓
rebuild when required
```

``` text
[ ] no blind retry
[ ] failure evidence preserved
[ ] target state assessed
```

## 14. Rebuild Path

> **STATE-CHANGING / DESTRUCTIVE RECOVERY OPERATION**

``` text
Recovery method: REBUILD
Provisioning/base-backup method:
Replacement host if applicable:
Start:
Completion:
```

Build from authoritative B using the approved provisioning procedure.

## 15. Post-Recovery Configuration Gate

Do not start A yet.

``` text
[ ] standby.signal present
[ ] primary_conninfo points to B
[ ] approved credential mechanism used
[ ] primary_slot_name correct if used
[ ] application_name correct
[ ] TLS/network settings correct
[ ] host-specific settings correct
[ ] archive/recovery settings correct
[ ] no legacy recovery.conf
[ ] A remains outside writable routing
```

If `pg_rewind -R` was used, inspect `standby.signal` and
`postgresql.auto.conf`.

## 16. Start A as Standby

> **STATE-CHANGING**

After configuration validation:

``` sql
SELECT pg_is_in_recovery();
```

Expected: `true`.

If false: **STOP, KEEP A ISOLATED, INVESTIGATE.**

## 17. Validate WAL Receiver

On A:

``` sql
SELECT
    pid,
    status,
    receive_start_lsn,
    written_lsn,
    flushed_lsn,
    last_msg_send_time,
    last_msg_receipt_time,
    latest_end_lsn,
    latest_end_time,
    slot_name,
    sender_host,
    sender_port
FROM pg_stat_wal_receiver;
```

Do not capture full credential-bearing `conninfo`.

## 18. Validate Receive and Replay

On A:

``` sql
SELECT
    pg_last_wal_receive_lsn() AS receive_lsn,
    pg_last_wal_replay_lsn() AS replay_lsn,
    pg_last_xact_replay_timestamp() AS last_replay_timestamp,
    pg_get_wal_replay_pause_state() AS replay_pause_state;
```

Expected pause state: `not paused`.

Capture repeated samples as needed to prove progress. Do not use a
universal lag threshold.

## 19. Validate B-Side Replication

On B:

``` sql
SELECT
    pid,
    application_name,
    client_addr,
    state,
    sent_lsn,
    write_lsn,
    flush_lsn,
    replay_lsn,
    sync_state,
    reply_time
FROM pg_stat_replication;
```

Confirm A is present and progressing.

## 20. Slot and Policy Review

Review physical slots deliberately. Do not automatically drop slots.

If synchronous replication is used:

``` text
[ ] synchronous_standby_names correct
[ ] A application_name matches policy
[ ] sync_state correct
[ ] synchronous_commit expectations documented
```

If logical failover slots are used, validate their required readiness
and synchronization separately.

## 21. Monitoring and Backup Validation

``` text
[ ] B recognized as primary
[ ] A recognized as standby
[ ] replication/WAL/storage alerts healthy
[ ] dashboards reflect new roles
[ ] backup target correct
[ ] role discovery correct
[ ] backup credentials/schedule/retention correct
[ ] backup monitoring healthy
```

## 22. Rejoin Acceptance

``` text
[ ] B healthy primary
[ ] A in recovery
[ ] WAL receiver healthy
[ ] receive progressing
[ ] replay progressing
[ ] replay not unexpectedly paused
[ ] physical slot policy validated
[ ] synchronous policy validated if applicable
[ ] logical HA validated if applicable
[ ] monitoring correct
[ ] backups correct

REJOIN COMPLETE:
HA RESTORED:
Timestamp:
```

## 23. Failback Decision

``` text
Failback required: YES / NO
Reason:
Owner:
```

If `NO`, stop. `B Primary → A Standby` is a valid final topology.

If `YES`, create a separate planned change.

## 24. Failback Change Control

``` text
Change ID:
Reason:
Owner:
Maintenance window:
Application owner:
Infrastructure owner:
Rollback plan:
```

Do not perform immediate role ping-pong after rejoin.

## 25. Failback Pre-Flight

``` text
[ ] B healthy primary
[ ] A healthy standby
[ ] replication stable
[ ] replay not paused
[ ] A capacity validated
[ ] maintenance coordinated
[ ] writer-quiesce procedure ready
[ ] routing procedure ready
[ ] monitoring active
[ ] rollback boundary understood
[ ] change approved
```

## 26. Quiesce Writers

> **STATE-CHANGING / SERVICE IMPACT POSSIBLE**

Control application writers, scheduled jobs, batch jobs,
queues/consumers, maintenance writers, and persistent sessions as
applicable.

``` text
WRITERS QUIESCED:
Timestamp:
Evidence:
```

## 27. Capture Final B WAL Boundary

On B after writers are controlled:

``` sql
SELECT pg_current_wal_flush_lsn()
       AS final_required_lsn;
```

``` text
FINAL_REQUIRED_LSN:
Timestamp:
```

## 28. Verify A Replayed the Boundary

On A:

``` sql
SELECT pg_last_wal_replay_lsn() AS replay_lsn;
```

``` text
FINAL_REQUIRED_LSN:
A_REPLAY_LSN:
Boundary satisfied: YES / NO
```

If `NO`, do not promote.

## 29. Fence and Verify B

> **STATE-CHANGING / DISRUPTIVE**

Use the approved environment-specific fencing mechanism:

``` text
<FENCING_ACTION>
```

Routing removal alone is not fencing.

``` text
Fencing method:
Verification method:
Verification evidence:
B fencing state: FENCED / NOT FENCED / UNKNOWN
```

Promotion requires `FENCED`.

## 30. Failback GO / NO-GO

``` text
[ ] application writes quiesced
[ ] final B boundary recorded
[ ] A replayed required boundary
[ ] B fenced
[ ] fencing verified
[ ] routing ready
[ ] monitoring active
[ ] change authority approves

FAILBACK GO: YES / NO
Approved by:
Timestamp:
```

## 31. Promote A

> **POINT OF NO SIMPLE RETURN --- STATE-CHANGING / DISRUPTIVE**

``` sql
SELECT pg_promote(wait => true);
```

Verify:

``` sql
SELECT pg_is_in_recovery();
```

Expected: `false`.

## 32. Smoke Test and Route

Before routing:

``` text
[ ] expected database available
[ ] authentication works
[ ] required objects available
[ ] read path succeeds
[ ] approved controlled write test succeeds
[ ] storage healthy
[ ] monitoring healthy
```

Then execute the approved routing change:

``` text
<ROUTING_CHANGE>
```

Verify connections, pools, DNS/proxy state, read/write health, and that
no application writer reaches B.

## 33. Restore B as Standby

Do not assume B automatically becomes a standby.

Assess B and reconcile it. If histories diverged, apply the same
evidence-based rewind/rebuild controls.

## 34. Final HA Acceptance

``` text
[ ] A primary
[ ] B standby
[ ] B in recovery
[ ] WAL receiver healthy
[ ] receive/replay progressing
[ ] slots correct
[ ] synchronous policy correct
[ ] logical HA healthy if applicable
[ ] monitoring correct
[ ] backups correct
[ ] application routing correct

FAILBACK COMPLETE:
HA RESTORED:
Timestamp:
```

## 35. Final Evidence Record

``` text
Incident/change ID:
Initial authoritative primary:
Former primary:
A quarantine evidence:
Evidence preservation location:
Rewind eligibility:
Checksums/wal_log_hints evidence:
full_page_writes evidence:
Timeline/WAL evidence:
Archive availability:
Dry-run result:
Rewind SOURCE:
Rewind TARGET:
Rewind/rebuild result:
Post-recovery configuration validation:
A recovery-state validation:
Receiver evidence:
Receive/replay evidence:
Replay pause state:
Physical-slot validation:
Synchronous-policy validation:
Logical-HA validation:
Monitoring validation:
Backup validation:
REJOIN COMPLETE:
First HA RESTORED:
Failback required:
Failback reason:
Failback change ID:
WRITERS QUIESCED:
FINAL_REQUIRED_LSN:
A replay LSN:
B fencing evidence:
Failback GO:
A promotion timestamp:
A primary verification:
Smoke-test result:
Routing validation:
B standby restoration:
Final topology:
FAILBACK COMPLETE:
Final HA RESTORED:
```

## 36. Valid End States

Without failback:

``` text
Application
     |
     v
Primary B
     |
     v
Standby A
```

With separately approved failback:

``` text
Application
     |
     v
Primary A
     |
     v
Standby B
```

Both are valid HA outcomes when their acceptance gates are satisfied.
