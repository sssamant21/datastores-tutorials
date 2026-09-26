# PostgreSQL HA Production Acceptance Checklist

**Module:** 6.15 --- Production HA Readiness and Acceptance\
**Classification:** **PRODUCTION-ACCEPTANCE / CONTROLLED-VALIDATION**

This checklist converts SAFE-READ SQL evidence and operational evidence
into a final HA-readiness decision.

It does not authorize disruptive HA actions.

## 1. Assessment Record

``` text
Environment:
Assessment/change ID:
Assessment date:
Assessor:

PostgreSQL version:
RPO:
RTO:

Expected primary:
Expected standbys:
Expected topology:
Replication mode:
Expected synchronous participants:

Cascading replication: YES / NO
Logical replication: YES / NO
WAL archiving required: YES / NO
```

## 2. Ownership

``` text
Database/DBRE owner:
Application owner:
Infrastructure owner:
Network/routing owner:
Monitoring owner:
Backup owner:
Incident authority:
```

## 3. SAFE-READ Evidence Collection

``` text
[ ] ha-acceptance.sql reviewed
[ ] SQL contains observational checks only
[ ] execution node identified
[ ] observation timestamp captured
[ ] database/version captured
[ ] pg_is_in_recovery() captured
[ ] no passwords/tokens captured
[ ] primary_conninfo not captured
[ ] pg_stat_wal_receiver.conninfo not captured
```

## 4. Role Authority

``` text
Expected primary:
Observed primary:
Expected standbys:
Observed standbys:

[ ] role evidence matches intended topology
[ ] no unresolved dual-primary state
[ ] no unknown database authority

Result: PASS / DEGRADED / BLOCKED / NOT APPLICABLE
Evidence:
Owner:
```

Unknown authority or unresolved split brain is **BLOCKED**.

## 5. Streaming Replication

Primary-side evidence:

``` text
[ ] expected pg_stat_replication rows present
[ ] expected application_name values present
[ ] expected client addresses/topology present
[ ] replication states understood
```

Standby-side evidence:

``` text
[ ] WAL receiver present where expected
[ ] expected upstream observed
[ ] expected slot observed
[ ] communication timestamps current/understood
```

Progress:

``` text
[ ] receive position reviewed
[ ] replay position reviewed
[ ] progression demonstrated OR idle-state explanation documented
```

``` text
Result:
Evidence:
Owner:
```

## 6. Replay Pause State

On confirmed standbys:

``` text
Replay pause state:
Expected: not paused

[ ] replay is not unexpectedly paused
```

Unexpected `paused` or unresolved `pause requested` blocks normal
standby readiness.

## 7. Replication Slots

For every required slot:

``` text
Slot:
Type:
Consumer:
Owner:
Required: YES / NO
Active:
restart_lsn:
wal_status:
safe_wal_size:
invalidation_reason:
failover:
synced:
```

Review:

``` text
[ ] required slots identified
[ ] inactive slots explained
[ ] no required slot invalidation unresolved
[ ] obsolete slots have lifecycle owner
[ ] no automatic slot deletion performed
```

## 8. WAL Retention and Storage

Database evidence:

``` text
[ ] wal_keep_size reviewed as minimum retention contribution
[ ] max_slot_wal_keep_size reviewed
[ ] restart_lsn reviewed
[ ] wal_status reviewed
[ ] safe_wal_size interpreted contextually
```

Platform evidence:

``` text
Filesystem capacity:
Filesystem utilization:
Growth trend:
Storage latency/health:
WAL generation behavior:
Archive state:
```

``` text
[ ] storage evidence supports required HA retention
```

## 9. Synchronous / Durability Policy

``` text
Intended replication mode:
Expected synchronous participants:
Expected application_name:
Expected synchronous_commit policy:
Observed synchronous_standby_names:
Observed sync_state:
RPO:
Degraded-mode policy:
```

``` text
[ ] intended and observed policy compared
[ ] no unsupported zero-data-loss claim
[ ] application/session commit behavior considered
```

## 10. Standby Conflict Readiness

``` text
[ ] pg_stat_database_conflicts reviewed
[ ] historical counters interpreted as cumulative
[ ] trend/frequency understood
[ ] workload impact understood
[ ] hot_standby_feedback policy reviewed
[ ] standby delay settings reviewed
[ ] monitoring/alerting exists where required
```

## 11. Cascading Replication

If applicable:

``` text
[ ] expected upstream/downstream relationships documented
[ ] receive/replay progression validated
[ ] intermediate standby capacity reviewed
[ ] failure dependency understood
[ ] monitoring covers the complete chain
```

If not used:

``` text
Result: NOT APPLICABLE
Reason:
Architecture evidence:
Approved by:
```

## 12. Logical Failover Protection

If applicable:

``` text
[ ] required logical slots identified
[ ] failover state reviewed
[ ] synced state reviewed
[ ] temporary state reviewed
[ ] invalidation_reason reviewed
[ ] sync_replication_slots prerequisite reviewed
[ ] physical primary_slot_name prerequisite reviewed
[ ] hot_standby_feedback prerequisite reviewed
[ ] valid primary_conninfo database prerequisite validated securely
[ ] synchronized_standby_slots policy reviewed
```

Do not capture full `primary_conninfo`.

## 13. Capacity

``` text
Connections:
max_connections:
Operational headroom:
max_wal_senders:
max_replication_slots:
Physical standbys:
Logical replication consumers:
Backup/WAL tooling:
Expected growth:
```

``` text
[ ] capacity supports intended topology
[ ] environment-specific thresholds documented where required
```

## 14. Archive Readiness

If required:

``` text
[ ] archive configuration reviewed
[ ] current archive progression demonstrated
[ ] recent successful archive evidence available
[ ] historical failures understood
[ ] monitoring active
[ ] restore/archive-retrieval procedure understood
```

A currently stalled required archive path blocks the recovery capability
depending on it.

## 15. Monitoring and Alerting

``` text
[ ] role monitoring
[ ] replication connectivity
[ ] receive/replay
[ ] replication slots
[ ] WAL retention
[ ] archive health
[ ] storage
[ ] connections
[ ] standby conflicts
[ ] synchronous-state changes
[ ] database/node availability
[ ] backup failures
```

For critical alerts:

``` text
Signal:
Alert:
Severity:
Owner:
Runbook:
Escalation:
```

``` text
[ ] monitoring follows roles rather than fixed-primary hostname assumptions
```

## 16. Backup and Restore

``` text
Backup method:
Schedule:
Target:
Retention:
Role awareness:
Monitoring:
Last successful backup:
Last restore validation:
Restore evidence:
```

``` text
[ ] backup success demonstrated
[ ] restore procedure documented
[ ] restore-test evidence meets policy
```

Replication is not a substitute for backup.

## 17. Planned Switchover --- 6.12 Evidence

``` text
Last controlled switchover test:
Environment:
Date:
Result:
Evidence:
Issues:
Remediation:
Next review:
```

Confirm evidence for:

``` text
[ ] pre-flight
[ ] writer quiescence
[ ] final WAL boundary
[ ] candidate replay
[ ] fencing
[ ] GO / NO-GO
[ ] promotion verification
[ ] database smoke test
[ ] routing
[ ] restored HA
```

## 18. Unplanned Failover / Fencing --- 6.13 Evidence

Hard rule:

``` text
PRIMARY UNREACHABLE != PRIMARY FENCED
```

Record:

``` text
Fencing mechanism:
Authority:
Execution path:
Verification method:
Required access:
Runbook:
```

Validate:

``` text
[ ] incident authority defined
[ ] candidate assessment defined
[ ] RPO assessment defined
[ ] fencing mechanism documented
[ ] fencing verification documented
[ ] UNKNOWN fencing is not accepted for promotion
[ ] emergency GO / NO-GO exists
[ ] promotion verification exists
[ ] routing procedure exists
[ ] HA restoration procedure exists
```

Unknown required fencing capability is **BLOCKED**.

## 19. Promotion Authority

``` text
Incident authority:
Emergency promotion approver:
Promotion executor:
Fencing verifier:
Application routing owner:
```

``` text
[ ] authority is explicit
```

## 20. RPO and Application Reconciliation

``` text
Replication mode:
RPO objective:
Expected transaction-loss exposure:
Synchronous policy:
Commit policy:
Failure assumptions:
Application reconciliation strategy:
```

Where applicable:

``` text
[ ] idempotency strategy
[ ] duplicate protection
[ ] retry policy
[ ] ambiguous-transaction reconciliation
[ ] application-owner procedure
```

## 21. Rejoin / Rewind / Rebuild --- 6.14 Evidence

Validate:

``` text
[ ] former-primary quarantine procedure
[ ] authoritative-primary declaration
[ ] evidence preservation
[ ] rewind eligibility assessment
[ ] source/target verification
[ ] dry-run capability
[ ] rewind/rebuild decision
[ ] post-recovery configuration validation
[ ] standby recovery validation
[ ] HA restoration gate
```

Hard rule:

``` text
SOURCE = authoritative primary
TARGET = quarantined former primary
```

Rebuild readiness:

``` text
Provisioning/base-backup method:
Credential path:
Network requirements:
Storage requirements:
Capacity:
Validation procedure:
Estimated recovery time:
Owner:
```

``` text
[ ] rebuild is available as a first-class recovery path
```

## 22. Failback Policy

``` text
Failback policy:
    REQUIRED / OPTIONAL / ARCHITECTURE-DEPENDENT

Reason:
Approval:
```

Hard rule:

``` text
REJOIN != FAILBACK
```

``` text
[ ] no automatic incident-pressure failback
[ ] required failback uses a separately approved planned change
```

## 23. Operational Access

Safely validate access for:

``` text
[ ] database
[ ] host/platform
[ ] monitoring
[ ] backup
[ ] routing
[ ] fencing
[ ] secret management
```

Emergency credentials:

``` text
[ ] credential exists
[ ] authorized responders can retrieve it
[ ] procedure documented
[ ] audit requirements understood
[ ] credential itself is absent from acceptance evidence
```

## 24. Runbook Availability

``` text
[ ] replication validation
[ ] slot/WAL retention
[ ] standby conflict response
[ ] monitoring
[ ] planned switchover
[ ] unplanned failover
[ ] fencing
[ ] rejoin/rewind
[ ] rebuild
[ ] backup recovery
[ ] routing
```

``` text
[ ] critical runbooks remain accessible during database failure
```

## 25. Acceptance Evidence Matrix

  Domain                  Evidence               Result   Owner
  ----------------------- ---------------------- -------- -------
  Role authority          SQL + topology                  
  Streaming replication   SQL                             
  Receive/replay          SQL                             
  Slots/WAL retention     SQL + storage                   
  Durability policy       SQL + architecture              
  Conflict readiness      SQL + monitoring                
  Topology                architecture                    
  Capacity                SQL + platform                  
  Archive                 SQL + monitoring                
  Monitoring              alerts + dashboards             
  Backup/restore          recovery evidence               
  Switchover              6.12 evidence                   
  Failover/fencing        6.13 evidence                   
  Rejoin/rebuild          6.14 evidence                   
  Access                  operational evidence            
  Ownership               support model                   

## 26. NOT APPLICABLE Record

``` text
Control:
Result: NOT APPLICABLE
Reason:
Architecture evidence:
Approved by:
```

N/A must not be used to bypass a difficult control.

## 27. Degradation Record

`PASS WITH DOCUMENTED DEGRADATION` requires:

``` text
Control:
Observed state:
Risk:
Impact:
Owner:
Compensating control:
Monitoring:
Remediation:
Target date:
Approval:
```

## 28. Hard Blockers

Examples:

``` text
[ ] unknown database authority
[ ] unresolved split brain
[ ] unknown required fencing capability
[ ] promotion possible without required split-brain controls
[ ] required standby unusable with no accepted mitigation
[ ] no former-primary recovery path
[ ] no rebuild capability
[ ] no authoritative backup/recovery capability
[ ] missing critical operational access
```

Any applicable unresolved hard blocker means:

``` text
OVERALL RESULT = BLOCKED
```

## 29. Exception Register

For every exception:

``` text
Exception ID:
Control:
Observed state:
Risk:
Impact:
Compensating control:
Owner:
Remediation:
Target date:
Approval:
```

## 30. Evidence Freshness

``` text
Control:
Last tested:
Environment:
Result:
Evidence:
Next required review:
```

Freshness interval follows organizational policy.

## 31. Final Acceptance

``` text
Overall result:

[ ] PASS

[ ] PASS WITH DOCUMENTED DEGRADATION

[ ] BLOCKED
```

``` text
Database/DBRE:
Application:
Infrastructure:
Operations/Incident Management:
Change authority:

Assessment date:
Next review date:
```

Sign-off records accountability and permitted risk acceptance. It does
not override unresolved technical blockers.

## 32. Part 6 Completion Gate

``` text
[ ] required Part 6 modules canonical
[ ] locked labs/runbooks present
[ ] expected filenames correct
[ ] SAFE-READ acceptance SQL reviewed
[ ] acceptance checklist reviewed
[ ] HA topology documented
[ ] replication demonstrated
[ ] WAL/slot safety demonstrated
[ ] durability policy documented
[ ] conflict policy understood
[ ] capacity reviewed
[ ] storage reviewed
[ ] archive readiness reviewed where applicable
[ ] monitoring demonstrated
[ ] alert ownership demonstrated
[ ] backups demonstrated
[ ] restore evidence available
[ ] planned switchover procedure available
[ ] split-brain prevention documented
[ ] fencing capability documented
[ ] unplanned failover procedure available
[ ] RPO documented
[ ] rejoin/rewind procedure available
[ ] rebuild path available
[ ] failback policy documented
[ ] emergency access validated
[ ] operational ownership defined
[ ] exceptions documented
[ ] final acceptance recorded
```

After repository validation, update the Part 6 tracker and final status.
