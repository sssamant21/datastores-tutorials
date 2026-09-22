# Part 6.1 Lab --- HA Architecture Assessment

**Tutorial:** Part 6.1 --- Streaming Replication and HA Architecture\
**Classification:** `[TUTORIAL-ACCEPTANCE — SAFE-READ]`\
**Target:** PostgreSQL 18\
**Status:** Canonical Acceptance Artifact --- Pending Repository
Validation

## Purpose

Assess whether a proposed PostgreSQL primary/standby topology contains
the minimum architectural information required for a production HA
decision.

This exercise validates architecture reasoning. It does **not** modify
PostgreSQL or infrastructure.

## Safety Boundary

Allowed:

-   inspect supplied architecture information
-   inspect approved read-only documentation/evidence
-   classify evidence
-   record risks and owners

Not required or permitted by this lab:

``` text
pg_promote()
pg_ctl promote
systemctl stop/start/restart
replication configuration changes
pg_hba.conf changes
endpoint changes
network isolation
fencing actions
pg_rewind
writes used to force replication activity
```

Perform disruptive role-transition exercises only in the later Part 6
sections explicitly marked `[DISRUPTIVE-LAB]`.

## Evidence Rule

Every assessment item must be classified as:

``` text
PASS
FAIL
UNKNOWN
```

Use:

-   `PASS` --- sufficient evidence demonstrates the requirement is
    satisfied.
-   `FAIL` --- sufficient evidence demonstrates the requirement is not
    satisfied.
-   `UNKNOWN` --- evidence is missing, stale, inaccessible, ambiguous,
    or contradictory.

Never convert missing evidence into `PASS`.

## Scenario

Assess this proposed topology:

``` text
                       Application
                            |
                            v
                      Writer Endpoint
                            |
                            v
                   +----------------+
                   | Primary A      |
                   | Failure Domain |
                   | A              |
                   +-------+--------+
                           |
                       async WAL
                           |
                           v
                   +----------------+
                   | Standby B      |
                   | Failure Domain |
                   | B              |
                   +----------------+
```

Known information:

``` text
Primary:                 A
Standby:                 B
Replication mode:        asynchronous
Primary failure domain:  A
Standby failure domain:  B
Application entry point: writer endpoint
```

No additional assumptions are allowed.

## Assessment 1 --- Writable Authority

Question:

``` text
Which server currently owns writable authority?
```

Evidence:

``` text
Primary A is identified as the current primary.
```

Record:

``` text
Result: PASS / FAIL / UNKNOWN
Reason:
Evidence:
Risk:
Owner:
```

Expected reasoning: Primary A is identified as the current writable
authority. Do not infer what will happen after failure.

## Assessment 2 --- Standby Role

Question:

``` text
Is Standby B currently an independent writable primary?
```

Record:

``` text
Result:
Reason:
Evidence:
Risk:
Owner:
```

Expected reasoning: The topology identifies B as a standby. A physical
standby in recovery is not an independent writable primary.

## Assessment 3 --- Replication Durability

Question:

``` text
Can the architecture claim RPO = 0 solely because B receives asynchronous WAL?
```

Record:

``` text
Result:
Reason:
Evidence:
Risk:
Owner:
```

Expected reasoning: No. Asynchronous replication can leave a data-loss
window during primary failure.

## Assessment 4 --- Failure-Domain Separation

Question:

``` text
Are A and B shown in different failure domains?
```

Record:

``` text
Result:
Reason:
Evidence:
Risk:
Owner:
```

Then answer separately:

``` text
Does the diagram prove those domains are independent
for compute, storage, network, power, and control plane?
```

Record:

``` text
Result:
Reason:
Evidence:
Risk:
Owner:
```

Expected reasoning: Separate labels are evidence of intended placement,
but they do not prove independence of every underlying dependency.

## Assessment 5 --- Failure Detection

Question:

``` text
What mechanism determines that Primary A has failed?
```

Record:

``` text
Result:
Reason:
Evidence:
Risk:
Owner:
```

Expected reasoning: The scenario does not specify a failure-detection
mechanism. Classify this `UNKNOWN`.

## Assessment 6 --- Promotion Authority

Question:

``` text
Who or what is authorized to promote Standby B?
```

Record:

``` text
Result:
Reason:
Evidence:
Risk:
Owner:
```

Expected reasoning: Not specified → `UNKNOWN`.

## Assessment 7 --- Fencing

Question:

``` text
How is Primary A prevented from accepting writes
after Standby B is promoted?
```

Record:

``` text
Result:
Reason:
Evidence:
Risk:
Owner:
```

Expected reasoning: Not specified → `UNKNOWN`. This is a safety-critical
gap because the design has not demonstrated preservation of a single
writable authority.

## Assessment 8 --- Client Routing

Question:

``` text
How does the writer endpoint move from A to B?
```

Record:

``` text
Result:
Reason:
Evidence:
Risk:
Owner:
```

Expected reasoning: An endpoint is shown, but its transition mechanism
is not documented → `UNKNOWN`.

## Assessment 9 --- Existing Connections

Question:

``` text
What happens to application connections established
against Primary A during failover?
```

Record:

``` text
Result:
Reason:
Evidence:
Risk:
Owner:
```

Expected reasoning: Not specified → `UNKNOWN`.

## Assessment 10 --- RPO

Question:

``` text
What is the declared business RPO?
```

Record:

``` text
Result:
Reason:
Evidence:
Risk:
Owner:
```

Expected reasoning: Not provided → `UNKNOWN`. Do not infer RPO from
replication mode.

## Assessment 11 --- RTO

Question:

``` text
What is the declared business RTO?
```

Record:

``` text
Result:
Reason:
Evidence:
Risk:
Owner:
```

Expected reasoning: Not provided → `UNKNOWN`. Do not infer RTO from the
existence of a standby.

## Assessment 12 --- Independent Recovery

Question:

``` text
Does the topology prove that an independent backup
and recovery path exists?
```

Record:

``` text
Result:
Reason:
Evidence:
Risk:
Owner:
```

Expected reasoning: No backup evidence is provided → `UNKNOWN`.

Replication must not be treated as proof of backup readiness.

## Assessment 13 --- Operational Ownership

Question:

``` text
Who owns:
- failover declaration
- fencing
- promotion
- endpoint transition
- application validation
- rollback/fallback decision
```

Record:

``` text
Result:
Reason:
Evidence:
Risk:
Owner:
```

Expected reasoning: Ownership is not specified → `UNKNOWN`.

## Assessment 14 --- Split-Brain Safety

Evaluate:

``` text
A becomes unreachable.
B is promoted.
A later returns and accepts writes.
```

Question:

``` text
Does the supplied architecture prove this condition
is prevented?
```

Record:

``` text
Result:
Reason:
Evidence:
Risk:
Owner:
```

Expected reasoning: No fencing mechanism is supplied. The architecture
therefore cannot demonstrate split-brain prevention.

## Assessment 15 --- Application Health

Question:

``` text
If PostgreSQL reports that B has been promoted successfully,
does that prove the application service is healthy?
```

Record:

``` text
Result:
Reason:
Evidence:
Risk:
Owner:
```

Expected reasoning: No. Database role transition does not prove client
routing, authentication, connection pools, reads, writes, or application
behavior.

## Assessment Matrix

Complete this table.

  Control                        Evidence       Result   Risk / Gap   Owner
  ------------------------------ -------------- -------- ------------ -------
  Current writable authority     Primary A                            
  Standby identity               Standby B                            
  Replication mode               asynchronous                         
  Failure-domain placement       A / B labels                         
  Dependency independence        not supplied                         
  Failure detection              not supplied                         
  Promotion authority            not supplied                         
  Fencing                        not supplied                         
  Writer routing transition      not supplied                         
  Existing connection behavior   not supplied                         
  Declared RPO                   not supplied                         
  Declared RTO                   not supplied                         
  Independent backup/recovery    not supplied                         
  Operational ownership          not supplied                         
  Application validation         not supplied                         

## Architecture Decision Gate

Answer each question:

``` text
[ ] Is exactly one current writable authority identified?
[ ] Is the replication mode known?
[ ] Are primary and standby failure domains identified?
[ ] Are correlated dependencies understood?
[ ] Is failure detection defined?
[ ] Is promotion authority defined?
[ ] Is fencing defined?
[ ] Is writer routing defined?
[ ] Is post-transition application validation defined?
[ ] Is the RPO declared?
[ ] Is the RTO declared?
[ ] Is an independent recovery path evidenced?
[ ] Are operational owners assigned?
[ ] Are unresolved items explicitly UNKNOWN?
```

## Acceptance Logic

The lab is **PASS** when the learner:

1.  correctly identifies the current primary and standby;
2.  does not claim zero data loss from asynchronous replication;
3.  distinguishes labeled failure domains from proven dependency
    independence;
4.  marks unspecified failure detection as `UNKNOWN`;
5.  marks unspecified promotion authority as `UNKNOWN`;
6.  marks unspecified fencing as `UNKNOWN`;
7.  marks unspecified endpoint-transition behavior as `UNKNOWN`;
8.  does not infer RPO or RTO;
9.  does not treat replication as proof of backup readiness;
10. does not treat promotion as proof of application health;
11. identifies the single-writer invariant;
12. records unresolved safety-critical risks rather than guessing.

## Expected Overall Assessment

For the supplied scenario:

``` text
Replication topology present:       PASS
Current role identification:        PASS
Replication mode identified:        PASS

Complete HA readiness:              UNKNOWN
Failure detection:                  UNKNOWN
Promotion authority:                UNKNOWN
Fencing:                            UNKNOWN
Client transition:                  UNKNOWN
Declared RPO:                       UNKNOWN
Declared RTO:                       UNKNOWN
Independent recovery evidence:      UNKNOWN
Operational ownership:              UNKNOWN
```

The topology must **not** receive an overall production-HA `PASS` merely
because a primary and standby exist.

## Final Evidence Record

``` text
Assessment date:
Reviewer:
Topology/version:
Primary:
Standby:
Replication mode:

Single writer identified:      PASS / FAIL / UNKNOWN
Failure domains assessed:      PASS / FAIL / UNKNOWN
Failure detection defined:     PASS / FAIL / UNKNOWN
Promotion authority defined:   PASS / FAIL / UNKNOWN
Fencing defined:               PASS / FAIL / UNKNOWN
Client routing defined:        PASS / FAIL / UNKNOWN
RPO declared:                  PASS / FAIL / UNKNOWN
RTO declared:                  PASS / FAIL / UNKNOWN
Independent recovery proven:   PASS / FAIL / UNKNOWN
Operational ownership defined: PASS / FAIL / UNKNOWN

Overall architecture decision: PASS / FAIL / UNKNOWN

Unresolved risks:
Owners:
Next evidence required:
```

## Completion Principle

``` text
replication present != HA proven
promotion           != failover complete
replication         != backup
missing evidence    = UNKNOWN
one writer          = mandatory
```

This acceptance artifact validates Part 6.1 architecture understanding
without changing a PostgreSQL system.
