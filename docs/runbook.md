# Member 1 Runbook — CSV Import and Verification

**Status:** repository-side instructions and candidate behavior only. No SAP activation, upload API or measured importer path is currently verified.

## Before loading data

1. Confirm the assigned ABAP environment, release and package in ADT. Record the value and transport/request identifiers in docs/m1-baseline-checklist.md.
2. Confirm in ADT that the signed contract's source-system, object, usage, finding, dependency, batch and row-result/error entities activate. Use the target's released UUID APIs and exact physical field lengths; do not silently truncate CSV fields.
3. Confirm ABAP Unit, CDS reads, supported import entry path, request size and staged-row CRUD if considered. Record observed results. A web upload or service is not available by assumption.
4. Obtain M2–M4 approval for docs/data-contract.md candidate v0.2. If findings_as_of or another schema decision changes, update the templates, fixtures and tests together before implementation.
5. Provision the synthetic source system DEMO_SYS using the tenant-approved process.

## Offline fixture check

From the repository root run:

    python tools/validate_import_fixtures.py

This checks template headers, CSV shape, base references, edge fixtures and 1k/10k fixture row counts. It reports local standard-library CSV read time only. It does not execute ABAP code or measure SAP import performance.

## Tenant import sequence

1. Start from a clean synthetic-only tenant/package. Never use customer evidence for these fixtures.
2. Load objects.csv first, then usage.csv, findings.csv and dependencies.csv. Each file is a distinct import batch.
3. Confirm each batch's parsed, accepted and rejected counts reconcile; inspect row-level errors and accepted-row provenance.
4. Repeat the same files. Business rows should report UNCHANGED while each new attempt retains its own batch ID and row results.
5. Run the edge fixtures one at a time and compare results with docs/import-design.md and docs/test-matrix.md.
6. Run the 1,000-row and 10,000-row object fixtures through the same activated parser/loader. Record tenant/release, package, user, start/end time, input bytes/rows, accepted/rejected counts, repeat-import counts and elapsed time. Do not claim an SLA; no target has been approved.
7. Reset only through the approved synthetic test cleanup procedure. Do not delete prior provenance as part of corrected-batch testing.

## Current release record

- ABAP environment/release: awaiting tenant details.
- Import route and request-size limit: unverified.
- ADT package and transport: unverified.
- Table/CDS activation and ABAP Unit result: not supplied.
- SAP 1k/10k import timings: not measured.
- Open blocker: source objects and all import classes/tests in the repository were empty at baseline.

## Follow-up release record

- Environment: likely SAP BTP ABAP Environment trial, inferred from user-supplied service-binding metadata; system TRL / AP21.
- ADT access: user reports access; no ADT connection has been observed here.
- Exact ABAP release, package, software component, UUID API, activation, ABAP Unit and import path: unknown or unverified. Fill these from docs/feasibility-note.md before activating implementation objects.
- Candidate contract v0.2 remains pending shared approval; do not implement against it as a frozen contract until M2–M4 confirm the keys, enums, result/error codes, corrections and partial-file policy.

---

## Member 3 Runbook — Workflow, Security & Audit Verification (`M3-D01-T01` .. `M3-D11-T01`)

### 1. Offline Workflow, Authorization, SoD & Audit Oracle Check

From the repository root, run:

```bash
python3 tools/m3_workflow_oracle.py --report docs/m3-golden-workflow-results.md
```

This executes:
- All **352 combinations** of the `8Statuses x 11 Actions x 4 Roles` transition matrix (asserting the 27 allowed paths and 325 rejected paths).
- All **24 unit-test scenarios** (`WF-T01` through `WF-T24`), verifying Separation of Duties (`ERR_SOD_VIOLATION`), mandatory reason length (`>= 10` chars), strategy validation (`ERR_OVERRIDE_SAME_STRATEGY`), optimistic concurrency (`ERR_STALE_CONCURRENCY_CONFLICT`), one-active-decision uniqueness (`ERR_DUPLICATE_ACTIVE_DECISION`), and append-only audit immutability (`ERR_AUDIT_IMMUTABLE`).
- The **Day-10 portfolio rehearsal** across the 7 synthetic sample objects in `data/sample-synthetic/objects.csv` using synthetic test principals (`DEMO_DEV_1`, `DEMO_DEV_2`, `DEMO_REV_1`, `DEMO_ADMIN_1`, `DEMO_AUDITOR_1`).

### 2. ADT Activation & ABAP Unit Sequence (Once Non-`$TMP` Package Is Provisioned)

1. Provision a transportable development package (e.g., `ZCCMC`) in the assigned SAP BTP ABAP Environment tenant and import the repository via abapGit.
2. Activate Member 1's persistence tables and CDS interface views (`src/zccmc_data/*`), then activate Member 3's domain workflow class (`src/zccmc_rap/zccmc_cl_decision_workflow.clas.abap`) and unit test class (`src/zccmc_test/zccmc_ut_decision_workflow.clas.abap`).
3. Run ABAP Unit (`Ctrl+Shift+F10`) on `ZCCMC_UT_DECISION_WORKFLOW` and verify all 24 test methods pass green.
4. Activate Member 3's RAP persistence and service artifacts in order:
   - `zccmc_decision.tabl.xml` and `zccmc_decaudit.tabl.xml`
   - `zccmc_i_decisionaudit.ddls.asddls` and `zccmc_i_decision.ddls.asddls`
   - `zccmc_dcl_decision.dcls.asdcls`
   - `zccmc_i_decision.bdef.asbdef` and `zccmc_bp_i_decision.clas.abap`
   - `zccmc_c_customobject.ddls.asddls`, `zccmc_c_decisionaudit.ddls.asddls`, `zccmc_c_decision.ddls.asddls`, `zccmc_c_importbatch.ddls.asddls`, `zccmc_c_importrowerror.ddls.asddls`
   - `zccmc_c_decision.bdef.asbdef`
   - `zccmc_ui_cockpit_o4.srvd.srvdsrv` and publish `zccmc_ui_cockpit_o4.srvb.xml` (OData V4 - UI).
5. Record the transport request IDs, service binding URL, and ADT test screenshots in `docs/feasibility-note.md` and `docs/m3-day1-day11-status.md`.

