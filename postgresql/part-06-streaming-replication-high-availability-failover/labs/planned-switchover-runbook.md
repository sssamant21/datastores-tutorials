# Planned Switchover Runbook

**Module:** PostgreSQL Part 6.12 --- Planned Switchover\
**Classification:** **DISRUPTIVE-LAB**\
**Scope:** Controlled PostgreSQL physical-streaming-replication lab or
explicitly approved maintenance environment.

> **WARNING:** This runbook intentionally changes PostgreSQL roles. It
> includes writer quiescing, old-primary fencing, standby promotion,
> routing changes, and former-primary recovery. Do not execute it
> against production without an approved environment-specific change
> plan.

------------------------------------------------------------------------

## 1. Runbook Safety Contract

This runbook does **not** authorize blind execution.

Mandatory rules:

-   stop at every GO / NO-GO gate;
-   do not automatically terminate sessions;
-   do not automatically drop replication slots;
-   do not promote if the required WAL boundary has not been replayed;
-   do not use routing changes as a substitute for fencing;
-   do not restart the former primary into the writable application
    path;
-   do not assume `pg_rewind` eligibility;
-   do not blindly retry a failed `pg_rewind`;
-   prefer a fresh rebuild when rewind eligibility is uncertain;
-   preserve evidence at each stage.

### Lab variables

Set these operationally before beginning:

``` text
PRIMARY_A=<current-primary-host>
STANDBY_B=<candidate-standby-host>
DB_NAME=<validation-database>
DB_USER=<operator-user>
FINAL_REQUIRED_LSN=<captured-during-runbook>
```

Do not store passwords in this runbook.

------------------------------------------------------------------------

## 2. Evidence Record

Record:

``` text
Change / Lab ID:
Operator:
Date:
Maintenance start:
Primary A:
Candidate B:
Application/routing owner:
Expected routing endpoint:
Rollback owner:
```

------------------------------------------------------------------------

## 3. PRE-FLIGHT --- READ ONLY

### 3.1 Confirm PostgreSQL version

Run on A and B:

``` sql
SELECT version();
```

Record both results.

### 3.2 Confirm roles

Run on A:

``` sql
SELECT pg_is_in_recovery();
```

Expected:

``` text
false
```

Run on B:

``` sql
SELECT pg_is_in_recovery();
```

Expected:

``` text
true
```

**NO-GO:** roles differ from the documented topology or are uncertain.

### 3.3 Validate sender state on A

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
FROM pg_stat_replication
ORDER BY application_name, client_addr;
```

Confirm B is represented as expected.

### 3.4 Validate receiver state on B

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

Do not dump full connection strings into change evidence.

### 3.5 Validate receive/replay state on B

``` sql
SELECT
    pg_last_wal_receive_lsn() AS receive_lsn,
    pg_last_wal_replay_lsn() AS replay_lsn,
    pg_last_xact_replay_timestamp() AS last_replay_timestamp,
    pg_is_wal_replay_paused() AS replay_paused;
```

**NO-GO:** replay is unexpectedly paused.

### 3.6 Inspect replication slots

Run where relevant:

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
    invalidation_reason
FROM pg_replication_slots
ORDER BY slot_name;
```

**NO-GO:** a required slot is unusable or the intended replication path
is unsafe.

Do not drop slots during this step.

### 3.7 Logical replication conditional gate

If logical replication consumers or logical failover slots are present:

``` text
STOP and validate logical failover-slot readiness
before continuing.
```

Record:

``` text
Logical replication present: YES / NO
Logical failover readiness validated: YES / NO / N/A
```

### 3.8 Configuration compatibility

Collect relevant settings on both nodes:

``` sql
SELECT name, setting, unit, source, pending_restart
FROM pg_settings
WHERE name IN (
    'max_connections',
    'max_prepared_transactions',
    'max_locks_per_transaction',
    'max_wal_senders',
    'max_replication_slots',
    'max_worker_processes',
    'wal_level',
    'wal_log_hints',
    'full_page_writes',
    'synchronous_standby_names'
)
ORDER BY name;
```

Record whether candidate capacity and configuration are appropriate.

### 3.9 External infrastructure gate

Verify externally:

``` text
[ ] CPU healthy
[ ] memory healthy
[ ] filesystem capacity healthy
[ ] pg_wal capacity healthy
[ ] storage latency acceptable
[ ] storage throughput acceptable
[ ] no relevant storage errors
[ ] network path healthy
[ ] monitoring operational
[ ] backup/recovery readiness confirmed
[ ] candidate sized for primary workload
```

------------------------------------------------------------------------

## 4. INITIAL GO / NO-GO

Proceed only when:

``` text
[ ] A confirmed primary
[ ] B confirmed standby
[ ] expected replication relationship present
[ ] B receiving WAL
[ ] B replaying WAL
[ ] replay not unexpectedly paused
[ ] required slots healthy
[ ] logical replication gate passed or N/A
[ ] configuration/capacity acceptable
[ ] infrastructure healthy
[ ] routing procedure ready
[ ] monitoring active
[ ] backup/recovery readiness confirmed
```

Decision:

``` text
INITIAL GO: YES / NO
Approved by:
Timestamp:
```

If **NO**, stop without performing state-changing operations.

------------------------------------------------------------------------

## 5. INVENTORY AND QUIESCE WRITERS

Identify all writer classes:

``` text
[ ] application services
[ ] background workers
[ ] scheduled jobs / CronJobs
[ ] ETL
[ ] Kafka consumers
[ ] CDC writers
[ ] integration workers
[ ] administrative scripts
[ ] manual database writers
[ ] other:
```

### STATE-CHANGING / DISRUPTIVE

Place the application/environment into its approved write-freeze state.

Stop or pause the approved background writer processes using
environment-specific procedures.

Record:

``` text
Write freeze started:
Application writers stopped:
Background writers stopped:
```

------------------------------------------------------------------------

## 6. VERIFY WRITE QUIESCENCE --- READ ONLY

Inspect active sessions/transactions using the environment's approved
queries and application telemetry.

Example diagnostic query:

``` sql
SELECT
    pid,
    usename,
    application_name,
    client_addr,
    state,
    xact_start,
    query_start,
    wait_event_type,
    wait_event
FROM pg_stat_activity
WHERE pid <> pg_backend_pid()
ORDER BY xact_start NULLS LAST, query_start;
```

Do not automatically terminate sessions.

If an unexpected writer remains:

``` text
STOP
  ↓
identify owner
  ↓
understand transaction
  ↓
wait / application-controlled completion /
explicitly approved termination
```

Record:

``` text
Write quiescence verified: YES / NO
Evidence:
```

------------------------------------------------------------------------

## 7. CAPTURE FINAL DURABLE WAL BOUNDARY --- READ ONLY

After write quiescence is verified, run on A:

``` sql
SELECT pg_current_wal_flush_lsn() AS final_required_lsn;
```

Record exactly:

``` text
FINAL_REQUIRED_LSN:
Timestamp:
```

Do not substitute a generic "lag looks low" observation.

------------------------------------------------------------------------

## 8. VERIFY B REPLAYED THE REQUIRED BOUNDARY --- READ ONLY

Run on B:

``` sql
SELECT
    pg_last_wal_receive_lsn() AS receive_lsn,
    pg_last_wal_replay_lsn() AS replay_lsn;
```

Compare B's replay LSN with `FINAL_REQUIRED_LSN`.

The required gate is:

``` text
B replay LSN >= FINAL_REQUIRED_LSN
```

Record:

``` text
FINAL_REQUIRED_LSN:
B receive LSN:
B replay LSN:
Required boundary replayed: YES / NO
```

If **NO**, wait and investigate. Do not promote.

------------------------------------------------------------------------

## 9. FENCE A

### STATE-CHANGING / DISRUPTIVE

Before promoting B, A must be unable to serve competing application
writes.

For an isolated lab, a clear fencing mechanism is stopping PostgreSQL on
A using the lab's service-management method.

Example only:

``` bash
pg_ctl stop -D "$PGDATA" -m fast
```

Use the correct PostgreSQL service-management mechanism for the lab.

For production, use the approved infrastructure/orchestration fencing
procedure instead of blindly copying the lab command.

### Verify fencing

Confirm A cannot serve database connections through the application
path.

Record:

``` text
A fenced: YES / NO
Fencing mechanism:
Fencing evidence:
Timestamp:
```

**NO-GO:** fencing cannot be positively established.

------------------------------------------------------------------------

## 10. FINAL GO / NO-GO

This is the final gate before promotion.

``` text
[ ] all intended writers quiesced
[ ] unexpected active writers resolved
[ ] FINAL_REQUIRED_LSN captured
[ ] B replayed FINAL_REQUIRED_LSN
[ ] B remains healthy
[ ] A positively fenced
[ ] routing change ready
[ ] monitoring active
[ ] operator approval recorded
```

Decision:

``` text
FINAL GO: YES / NO
Approved by:
Timestamp:
```

If **NO**, do not promote.

------------------------------------------------------------------------

## 11. PROMOTE B

> **POINT OF NO SIMPLE RETURN**

After this step, returning to A is another controlled HA operation.

### STATE-CHANGING / DISRUPTIVE

Run on B:

``` sql
SELECT pg_promote(wait => true);
```

Record:

``` text
Promotion invoked:
Result:
Timestamp:
```

------------------------------------------------------------------------

## 12. VERIFY B IS PRIMARY --- READ ONLY

Run on B:

``` sql
SELECT pg_is_in_recovery();
```

Expected:

``` text
false
```

Also review PostgreSQL logs and server health.

Record:

``` text
B confirmed primary: YES / NO
Evidence:
```

If B is not healthy, keep A fenced and escalate. Do not blindly restart
A as primary.

------------------------------------------------------------------------

## 13. DATABASE SMOKE TEST

Validate before routing application traffic:

``` text
[ ] expected database accessible
[ ] expected roles/authentication available
[ ] required extensions/objects available
[ ] storage healthy
[ ] monitoring sees B
```

### STATE-CHANGING --- CONTROLLED TEST ONLY

Use only the approved lab validation object or production smoke-test
procedure.

Do not modify arbitrary business tables.

Record:

``` text
Read validation: PASS / FAIL
Write validation: PASS / FAIL
Evidence:
```

------------------------------------------------------------------------

## 14. REDIRECT CLIENTS

### STATE-CHANGING / DISRUPTIVE

Change the approved routing mechanism so new application connections
target B.

Examples may include DNS, VIP, proxy, load balancer, Kubernetes Service,
service discovery, or application configuration.

Record:

``` text
Routing changed:
New target:
Timestamp:
```

------------------------------------------------------------------------

## 15. VALIDATE APPLICATION AND CONNECTIONS

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
[ ] DNS/cache behavior understood
[ ] no application traffic reaches fenced A
```

Record application evidence.

------------------------------------------------------------------------

## 16. VALIDATE MONITORING AND BACKUPS

Confirm:

``` text
[ ] B recognized as primary
[ ] A represented as fenced/recovering
[ ] replication dashboards updated
[ ] database alerts meaningful
[ ] infrastructure monitoring healthy
[ ] backup automation recognizes intended role/target
[ ] backup monitoring healthy
```

------------------------------------------------------------------------

## 17. KEEP A FENCED

Do not restart A into the writable application path.

A remains fenced until its new standby role is deliberately prepared and
validated.

------------------------------------------------------------------------

## 18. PG_REWIND ELIGIBILITY DECISION

### READ-ONLY DECISION GATE

Evaluate whether A can safely use `pg_rewind`.

Check the required configuration evidence, including whether data
checksums are enabled or `wal_log_hints=on`, and whether
`full_page_writes=on`.

Example evidence collection where applicable:

``` sql
SHOW wal_log_hints;
SHOW full_page_writes;
```

Also verify data-checksum status using the approved PostgreSQL tooling
for the environment.

Decision:

``` text
pg_rewind eligibility: YES / NO / UNKNOWN
Evidence:
```

Rule:

``` text
YES        → rewind may be considered
NO/UNKNOWN → fresh rebuild
```

------------------------------------------------------------------------

## 19. REWIND PATH

> **STATE-CHANGING / DESTRUCTIVE RECOVERY OPERATION**

Proceed only if eligibility is positively established.

A must remain stopped/fenced.

Use environment-specific authenticated source connectivity to B. Do not
place passwords directly in the runbook.

Representative command shape:

``` bash
pg_rewind \
  --target-pgdata="$PGDATA" \
  --source-server="<approved connection parameters to B>"
```

Do not copy placeholder connection parameters literally.

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

Record:

``` text
Rewind attempted: YES / NO
Rewind result:
Evidence/log location:
```

------------------------------------------------------------------------

## 20. POST-REWIND CONFIGURATION GATE

Do **not** immediately start A.

Inspect and configure A so it will follow B.

Validate:

``` text
[ ] recovery/standby configuration correct
[ ] upstream endpoint points to B
[ ] credentials available through approved mechanism
[ ] intended replication slot configured if used
[ ] application_name correct if operationally required
[ ] network path to B works
[ ] A remains outside writable application routing
```

Only then may A be started as a standby.

------------------------------------------------------------------------

## 21. FRESH REBUILD PATH

> **STATE-CHANGING / DESTRUCTIVE RECOVERY OPERATION**

Use this path when rewind is unavailable, inappropriate, unsuccessful,
or uncertain.

Recreate A from B using the environment's approved base-backup or
provisioning process.

Do not reuse an uncertain former-primary data directory as though it
were a valid standby.

Record:

``` text
Rebuild selected: YES / NO
Provisioning/base-backup method:
Completion time:
```

------------------------------------------------------------------------

## 22. START A AS STANDBY

### STATE-CHANGING

After recovery configuration is validated, start PostgreSQL on A using
the approved service-management method.

Verify on A:

``` sql
SELECT pg_is_in_recovery();
```

Expected:

``` text
true
```

------------------------------------------------------------------------

## 23. VALIDATE RESTORED REPLICATION

On A:

``` sql
SELECT
    pg_is_in_recovery(),
    pg_last_wal_receive_lsn(),
    pg_last_wal_replay_lsn(),
    pg_last_xact_replay_timestamp();
```

Inspect:

``` sql
SELECT
    pid,
    status,
    written_lsn,
    flushed_lsn,
    last_msg_receipt_time,
    latest_end_lsn,
    slot_name,
    sender_host,
    sender_port
FROM pg_stat_wal_receiver;
```

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

Confirm WAL progress continues.

------------------------------------------------------------------------

## 24. POST-SWITCH SLOT AND SYNC REVIEW

Review replication slots deliberately.

Do not automatically drop old slots.

If synchronous replication is used, verify the intended synchronous
relationship and commit policy.

If logical replication is present, validate its post-switch continuity
according to the approved design.

------------------------------------------------------------------------

## 25. FINAL ACCEPTANCE

Preferred final topology:

``` text
Application
    |
    v
Primary B
    |
    v
Standby A
```

Acceptance checklist:

``` text
[ ] B confirmed primary
[ ] application routing targets B
[ ] application smoke tests passed
[ ] no application traffic reaches old writable A
[ ] monitoring reflects new roles
[ ] backup behavior validated
[ ] A safely rewound or rebuilt
[ ] A confirmed standby
[ ] B sees expected downstream A
[ ] WAL receive/replay progressing
[ ] slots match intended topology
[ ] synchronous policy restored if applicable
[ ] logical replication validated if applicable
[ ] evidence package complete
```

If standby protection cannot be restored before maintenance closes:

``` text
STATUS: DEGRADED HA
Owner:
Remediation:
Target completion:
```

Do not silently classify this as normal completion.

------------------------------------------------------------------------

## 26. ROLLBACK / ABORT DECISION MATRIX

### Phase 1 --- Before fencing/promotion

A remains primary.

A controlled abort may resume normal service on A after validation.

### Phase 2 --- A fenced, B not promoted

B remains standby.

A may potentially be restored through the approved abort procedure after
verifying A's state and routing.

### Phase 3 --- B promoted

There is no simple rollback command.

If B has accepted writes:

``` text
DO NOT restart A as the original writable primary.
```

Returning service to A requires another controlled HA transition.

------------------------------------------------------------------------

## 27. FINAL EVIDENCE RECORD

``` text
Pre-change A role:
Pre-change B role:
Replication relationship:
Logical replication gate:
Writer freeze start:
Write quiescence verified:
FINAL_REQUIRED_LSN:
B replay LSN at gate:
A fencing mechanism:
A fencing evidence:
Final GO approval:
Promotion timestamp:
B primary verification:
Database smoke-test result:
Routing-change timestamp:
Application validation:
Monitoring validation:
Backup validation:
A recovery method (rewind/rebuild):
A standby verification:
Restored replication evidence:
Final topology:
Final status (HA restored / DEGRADED HA):
Maintenance end:
Operator:
```

------------------------------------------------------------------------

## 28. Safety Summary

``` text
QUIESCE
   ↓
CAPTURE DURABLE WAL BOUNDARY
   ↓
VERIFY REPLAY
   ↓
FENCE OLD PRIMARY
   ↓
FINAL GO
   ↓
PROMOTE
   ↓
VALIDATE
   ↓
ROUTE
   ↓
RECOVER OLD PRIMARY
   ↓
RESTORE HA
```

Never replace these gates with assumptions.
