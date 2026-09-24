# Unplanned Failover Runbook

**Module:** PostgreSQL Part 6.13 --- Unplanned Failover and Split-Brain
Prevention\
**Classification:** **DISRUPTIVE-LAB**

> **WARNING:** This runbook intentionally performs emergency HA
> operations including fencing, standby promotion, routing changes, and
> former-primary recovery. Use it only in an isolated HA lab or an
> explicitly approved production incident procedure.

## 1. Critical Safety Rule

``` text
PRIMARY UNREACHABLE != PRIMARY FENCED
```

Do not promote a standby merely because the old primary cannot be
reached from one observation point.

Split-brain prevention is a mandatory promotion gate.

## 2. Safety Contract

This runbook will not:

-   interpret a failed health check as fencing;
-   silently convert unknown fencing state into success;
-   automatically terminate sessions;
-   automatically drop replication slots;
-   automatically select a candidate using only the largest LSN;
-   claim zero data loss without evidence;
-   promote before fencing is positively verified;
-   route applications before validating the promoted server;
-   reconnect the former primary directly as writable;
-   assume `pg_rewind` eligibility;
-   blindly retry failed rewind operations;
-   expose credential-bearing connection strings in evidence.

## 3. Incident Record

Record:

``` text
Incident ID:
Incident Commander:
Database Operator:
Infrastructure Operator:
Application Owner:
Failure detected:
Incident declared:
Primary A:
Candidate B:
Other candidate(s):
Routing owner:
```

## 4. Declare Incident and Freeze Unrelated Changes

Record the incident start and stop unrelated database/infrastructure
changes.

Do not combine emergency failover with tuning, schema work, slot
cleanup, unrelated deployments, or unnecessary restarts.

## 5. Collect Failure Evidence

Gather evidence from available sources:

``` text
[ ] PostgreSQL
[ ] application
[ ] host/VM
[ ] storage
[ ] network
[ ] proxy/load balancer
[ ] orchestrator
[ ] cloud/platform
[ ] monitoring
```

Record:

``` text
Observed symptoms:
Likely failure domain:
Evidence:
```

A `psql`, SSH, ping, or monitoring timeout is not by itself fencing
evidence.

## 6. Classify A's Fencing State

Use exactly one:

``` text
FENCED
NOT FENCED
UNKNOWN
```

Definitions:

``` text
FENCED
Positive evidence A cannot serve writes.

NOT FENCED
Positive evidence A can still serve writes.

UNKNOWN
Insufficient evidence.
```

Record:

``` text
Initial fencing state:
Evidence:
```

`UNKNOWN` means split-brain risk remains.

## 7. Assess Candidate B --- READ ONLY

Run on B:

``` sql
SELECT
    pg_is_in_recovery() AS in_recovery,
    pg_last_wal_receive_lsn() AS receive_lsn,
    pg_last_wal_replay_lsn() AS replay_lsn,
    pg_last_xact_replay_timestamp() AS last_replay_timestamp,
    pg_is_wal_replay_paused() AS replay_paused;
```

Before promotion, B should normally report `in_recovery = true`.

Unexpected paused replay requires investigation.

## 8. Inspect WAL Receiver --- READ ONLY

On B:

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

Do not capture the full credential-bearing `conninfo`.

## 9. Inspect Replication Slots --- READ ONLY

Where relevant:

``` sql
SELECT
    slot_name,
    slot_type,
    active,
    active_pid,
    restart_lsn,
    wal_status,
    safe_wal_size,
    inactive_since,
    invalidation_reason,
    failover,
    synced
FROM pg_replication_slots
ORDER BY slot_name;
```

Do not drop or recreate slots during this evidence phase.

## 10. Capture Pre-Promotion Evidence

Record:

``` text
Timestamp:
B in recovery:
B receive LSN:
B replay LSN:
B last replay timestamp:
Replay paused:
WAL receiver state:
Slot state:
B storage health:
B compute health:
Relevant PostgreSQL logs preserved:
```

Do not delay a safety-critical recovery for excessive diagnostics.

## 11. Multiple Candidate Assessment

If B and C are both available, record for each:

``` text
recovery state
receive LSN
replay LSN
last replay timestamp
receiver state
storage health
capacity
failure domain
topology
logical replication implications
```

Do not automatically promote `MAX(replay_lsn)`.

Record:

``` text
Selected candidate:
Selection rationale:
```

## 12. Assess RPO Exposure

There may be no final A-side WAL boundary.

Classify current knowledge:

``` text
RPO assessment:
CONFIRMED / POSSIBLE / UNKNOWN
```

For asynchronous replication, acknowledge that recent commits accepted
by A may not have reached B.

For synchronous replication, capture relevant policy evidence, including
the intended synchronous standby relationship and applicable
`synchronous_commit` behavior.

Do not write "zero data loss" without evidence.

## 13. Logical Replication Conditional Gate

If logical replication or failover-enabled logical slots are involved,
record:

``` text
Logical replication present: YES / NO
Required failover slots ready: YES / NO / UNKNOWN / N/A
Logical consumers expected state:
```

Physical database recovery and logical-consumer recovery are separate
concerns.

Do not experimentally manipulate synchronized logical slots during
emergency promotion.

## 14. Candidate Capacity Gate

Verify B is healthy enough for primary workload:

``` text
[ ] CPU assessed
[ ] memory assessed
[ ] filesystem assessed
[ ] pg_wal capacity assessed
[ ] storage latency/throughput assessed
[ ] connection capacity assessed
[ ] WAL sender capacity assessed
[ ] slot capacity assessed
[ ] monitoring active
```

Document known degraded capacity.

## 15. Fence A

> **STATE-CHANGING / DISRUPTIVE**

Use the approved environment-specific fencing control.

Examples can include:

``` text
<POWER_FENCE>
<CLOUD_INSTANCE_STOP>
<VM_SHUTDOWN>
<STORAGE_FENCE>
<NETWORK_ISOLATION>
<ORCHESTRATOR_FENCE>
```

Do not copy a generic placeholder as a production command.

Record:

``` text
Fencing action:
Requested:
Operator:
```

## 16. Verify Fencing

A fencing request is not proof of completion.

Use an authoritative verification method appropriate to the platform.

Record:

``` text
Verification method:
Verification evidence:
Verified at:
Final fencing state: FENCED / NOT FENCED / UNKNOWN
```

Promotion requires:

``` text
Final fencing state = FENCED
```

If state remains `NOT FENCED` or `UNKNOWN`, **STOP AND ESCALATE**.

## 17. Emergency GO / NO-GO

Immediately before promotion:

``` text
[ ] candidate identified and healthy enough
[ ] pre-promotion candidate state captured where practical
[ ] RPO exposure acknowledged
[ ] A positively fenced
[ ] fencing independently verified
[ ] routing procedure ready
[ ] monitoring active
[ ] incident authority approves
```

Record:

``` text
EMERGENCY GO: YES / NO
Approved by:
Timestamp:
```

If **NO**, do not promote.

## 18. Promote B

> **POINT OF NO SIMPLE RETURN**

> **STATE-CHANGING / DISRUPTIVE**

On B:

``` sql
SELECT pg_promote(wait => true);
```

Record:

``` text
Promotion requested:
Promotion result:
Promotion timestamp:
```

## 19. Verify B Is Primary --- READ ONLY

On B:

``` sql
SELECT pg_is_in_recovery();
```

Expected:

``` text
false
```

Also verify PostgreSQL logs, database availability, storage health, and
monitoring.

Record:

``` text
B confirmed primary: YES / NO
Evidence:
```

Do not route applications until B passes validation.

## 20. Database Smoke Test

Verify:

``` text
[ ] expected database available
[ ] authentication works
[ ] required roles available
[ ] required objects/extensions available
[ ] read test passes
[ ] approved controlled write test passes
[ ] storage healthy
[ ] monitoring healthy
```

Do not modify arbitrary business data.

Record:

``` text
Database smoke test: PASS / FAIL
Evidence:
```

## 21. Redirect Application Traffic

> **STATE-CHANGING / DISRUPTIVE**

Perform the approved routing change:

``` text
<ROUTING_CHANGE>
```

Record:

``` text
Routing changed:
New target:
Timestamp:
```

Routing must continue to exclude A.

## 22. Validate Connections and Application

Verify:

``` text
[ ] new connections reach B
[ ] authentication succeeds
[ ] correct database reached
[ ] read path succeeds
[ ] write path succeeds
[ ] transactions complete
[ ] connection pools healthy
[ ] persistent connections handled
[ ] DNS/proxy cache behavior understood
[ ] no application traffic reaches A
```

Record:

``` text
SERVICE RESTORED:
Application validation:
```

## 23. Ambiguous Transaction Outcomes

A failed client request does not prove the transaction failed to commit
on A.

``` text
client saw error != transaction definitely did not commit
```

Use workload-specific idempotency, reconciliation, or
duplicate-protection procedures.

Record any transactions requiring reconciliation.

## 24. Document RPO Outcome

After stabilization, record:

``` text
RPO outcome: CONFIRMED / POSSIBLE / UNKNOWN
Evidence:
Possible loss window:
Known missing transactions:
Known duplicate/retried operations:
Reconciliation owner:
```

Do not make unsupported zero-data-loss claims.

## 25. Record Degraded HA

If no healthy standby currently protects B:

``` text
STATUS: DEGRADED HA
Owner:
Risk:
Remediation:
Target completion:
```

`SERVICE RESTORED` does not mean `HA RESTORED`.

## 26. Returning Former Primary A

When A becomes reachable:

``` text
KEEP A QUARANTINED
```

Do not reconnect A to application routing.

Do not assume it automatically becomes a standby.

## 27. Preserve Former-Primary Evidence

Before destructive recovery where practical, preserve:

``` text
[ ] PostgreSQL logs
[ ] system logs
[ ] timeline/history evidence
[ ] configuration
[ ] failure timestamps
[ ] storage/platform events
```

Record evidence location.

## 28. Rewind/Rebuild Decision

Determine:

``` text
Is pg_rewind positively eligible?
         |
     +---+---+
     |       |
    YES    NO / UNKNOWN
     |       |
  rewind    rebuild
```

Eligibility includes required PostgreSQL configuration, history/WAL
availability, target integrity, and connectivity.

Do not guess.

## 29. Confirm Rewind Source and Target

Before any rewind operation, record prominently:

``` text
SOURCE = B
Current authoritative primary

TARGET = A
Former primary being repaired
```

Verify:

``` text
Source confirmed:
Target confirmed:
Operator:
```

Do not proceed if source/target identity is uncertain.

## 30. Rewind Safety Gate

Before `pg_rewind`:

``` text
[ ] A quarantined
[ ] A excluded from writable routing
[ ] required incident evidence preserved
[ ] rewind eligibility established
[ ] SOURCE confirmed as B
[ ] TARGET confirmed as A
[ ] required WAL/history available
[ ] authentication/connectivity validated
[ ] rebuild fallback available
[ ] operator approval recorded
```

## 31. Execute Rewind When Approved

> **STATE-CHANGING / DESTRUCTIVE RECOVERY OPERATION**

Use environment-specific authenticated connectivity to B.

Representative command shape:

``` bash
pg_rewind \
  --target-pgdata="$PGDATA" \
  --source-server="<approved connection parameters to B>"
```

Do not place passwords directly in this runbook or incident evidence.

If `pg_rewind` fails:

``` text
STOP
  ↓
preserve evidence
  ↓
assess target state
  ↓
fresh rebuild when required
```

Do not blindly retry.

## 32. Post-Rewind Configuration Gate

Do not expose or start A as a normal server until standby configuration
is validated.

Modern PostgreSQL uses normal configuration parameters plus
`standby.signal`, not legacy `recovery.conf`.

If `pg_rewind -R` is used, inspect the generated recovery configuration.

Verify:

``` text
[ ] upstream points to B
[ ] credentials use approved mechanism
[ ] intended slot configured if used
[ ] application_name correct if required
[ ] network path to B works
[ ] A remains outside writable routing
```

## 33. Fresh Rebuild Path

> **STATE-CHANGING / DESTRUCTIVE RECOVERY OPERATION**

Use a fresh rebuild when rewind eligibility, WAL/history, target
integrity, or a failed rewind makes reuse unsafe.

Provision A or a replacement standby from B using the approved
base-backup/provisioning process.

Record:

``` text
Recovery method: REBUILD
Provisioning method:
Completion:
```

## 34. Start A as Standby

> **STATE-CHANGING**

After standby configuration is verified, start A using the approved
service-management method.

On A:

``` sql
SELECT pg_is_in_recovery();
```

Expected:

``` text
true
```

## 35. Validate Restored Replication

On A:

``` sql
SELECT
    pg_is_in_recovery(),
    pg_last_wal_receive_lsn(),
    pg_last_wal_replay_lsn(),
    pg_last_xact_replay_timestamp();
```

Inspect safe WAL receiver fields.

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

Confirm replication progresses.

## 36. Review Slots and Synchronous Policy

Review physical and logical slots deliberately.

Do not automatically drop obsolete slots during incident recovery.

If synchronous replication is used, verify the intended
`synchronous_standby_names`, participating standby, `sync_state`, and
required commit policy.

## 37. Validate Monitoring and Backups

Verify:

``` text
[ ] B recognized as primary
[ ] A recognized as standby
[ ] replication monitoring healthy
[ ] WAL/storage alerts healthy
[ ] application monitoring healthy
[ ] backup target correct
[ ] backup role discovery correct
[ ] backup credentials/schedule correct
[ ] backup monitoring healthy
```

## 38. HA Restoration Acceptance

Preferred topology:

``` text
Application
    |
    v
Primary B
    |
    v
Standby A
```

Acceptance:

``` text
[ ] B primary
[ ] application healthy
[ ] A standby
[ ] replication progressing
[ ] slot topology reviewed
[ ] synchronous policy restored if applicable
[ ] logical consumers validated if applicable
[ ] monitoring correct
[ ] backups correct
[ ] evidence package retained
```

Record:

``` text
HA RESTORED:
Timestamp:
```

## 39. Failback

Do not automatically move primary service back to A.

If A should become primary again, perform a separate controlled **6.12
Planned Switchover**.

## 40. Final Evidence Record

``` text
Incident ID:
Failure detected:
Incident declared:
Failure-domain assessment:
Initial A fencing state:
Selected candidate:
Candidate-selection rationale:
B pre-promotion receive LSN:
B pre-promotion replay LSN:
RPO exposure before promotion:
Fencing action:
Fencing verification:
Emergency GO authority:
Promotion timestamp:
B primary verification:
Database smoke-test result:
Routing timestamp:
SERVICE RESTORED:
RPO final classification:
Ambiguous transaction/reconciliation notes:
A return timestamp:
Former-primary evidence preserved:
Recovery method (rewind/rebuild):
Rewind SOURCE:
Rewind TARGET:
A standby verification:
Restored replication evidence:
Slot/sync/logical validation:
Monitoring validation:
Backup validation:
HA RESTORED:
Final topology:
Incident recovery closed:
```

## 41. Emergency Failover Flow

``` text
PRIMARY FAILURE DETECTED
          ↓
DECLARE INCIDENT
          ↓
FREEZE UNRELATED CHANGES
          ↓
COLLECT MULTI-SOURCE EVIDENCE
          ↓
IDENTIFY FAILURE DOMAIN
          ↓
ASSESS CANDIDATE(S)
          ↓
CAPTURE PRE-PROMOTION STATE
          ↓
ASSESS / ACKNOWLEDGE RPO EXPOSURE
          ↓
FENCE A
          ↓
VERIFY FENCING
          ↓
EMERGENCY GO
          ↓
PROMOTE B
          ↓
VERIFY B PRIMARY
          ↓
DATABASE SMOKE TEST
          ↓
REDIRECT APPLICATION
          ↓
VALIDATE APPLICATION
          ↓
SERVICE RESTORED
          ↓
DOCUMENT RPO OUTCOME
          ↓
KEEP A QUARANTINED
          ↓
PRESERVE EVIDENCE
          ↓
REWIND / REBUILD
          ↓
RESTORE STANDBY
          ↓
VALIDATE REPLICATION / SLOTS / SYNC
          ↓
VALIDATE MONITORING / BACKUPS
          ↓
HA RESTORED
```

Never replace fencing and verification gates with assumptions.
