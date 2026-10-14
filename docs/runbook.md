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