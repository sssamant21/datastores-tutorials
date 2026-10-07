# Redis Enterprise Production Engineering — Status

**Updated:** 2026-10-07  
**Curriculum target:** 80 chapters  
**Rebuild progress:** 2/80  
**Current chapter:** 03 — Redis Data Types, Key Design & Memory-Aware Data Modeling

## Current Rebuild

| # | Chapter | Rebuild Status | Repository State |
|---|---|---|---|
| 01 | Redis Enterprise Fundamentals & Architecture | Rebuilt | Canonical replacement prepared |
| 02 | Connecting to Redis Enterprise — Clients, Endpoints, TLS & Connection Management | Rebuilt | Canonical replacement prepared |
| 03 | Redis Data Types, Key Design & Memory-Aware Data Modeling | Next | Legacy source retained |
| 04–36 | Existing legacy tutorials | Pending rebuild | Retained as source material |
| 37–80 | New production curriculum | Planned | Defined in MASTER-LAYOUT.md |

## Authoritative Curriculum

The authoritative roadmap is [MASTER-LAYOUT.md](MASTER-LAYOUT.md).

The former 36-chapter curriculum is retired as the curriculum definition. Existing Chapter 03–36 files remain temporarily because useful commands, examples, and operational material may be incorporated into their new replacement chapters.

They must not be interpreted as canonical chapters in the new 80-chapter track.

## Cleanup Policy

For each chapter:

1. Review any relevant legacy chapter.
2. Preserve useful technical material.
3. Rebuild to the production chapter standard.
4. Validate against current Redis documentation.
5. Add hands-on labs and safe failure injection where applicable.
6. Add troubleshooting and operational runbooks.
7. Replace the legacy chapter.
8. Verify repository links and tracker status.
9. Mark the new chapter canonical.

Legacy material is removed only after its replacement has been completed and verified.

## Canonical Standard

A production-grade chapter should include, where applicable:

- concepts
- architecture
- internal behavior
- operational commands
- hands-on lab
- expected results
- failure injection
- troubleshooting
- production considerations
- operational runbook
- validation questions
- acceptance checklist
- current Redis documentation validation

## Progress

```text
Rebuilt:  02 / 80
Next:     03
Target:   80 / 80 canonical
```

## Legacy Validation Artifacts

`REVIEW.md` and `tools/validate_tutorials.py` originated with the former 36-chapter track. Keep them during the rebuild until their useful checks are incorporated into the new curriculum validation process.

## Next

**Chapter 03 — Redis Data Types, Key Design & Memory-Aware Data Modeling**
