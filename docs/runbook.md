# Clean Core Migration Cockpit — Team Runbook (Member 1 & Member 3)

**Status:** Repository implementation, unit test suites, and offline verification oracles are complete (`M1-D01-T01` .. `M1-D11-T01` and `M3-D01-T01` .. `M3-D11-T01`). Live SAP BTP ABAP Environment activation remains gated on provisioning a transportable non-`$TMP` development package (`ZCCMC`; see `docs/feasibility-note.md` F-02 and `docs/limitations.md`).

---

## Member 1 Runbook — Persistence, CSV Import & Provenance Verification (`M1-D01-T01` .. `M1-D11-T01`)

### 1. Offline Import, Edge-Case, Scale & Reproducibility Oracle Check

From the repository root, run:

```bash
python3 tools/validate_import_fixtures.py
python3 tools/m1_import_oracle.py --report docs/m1-golden-import-results.md
```

These commands execute and verify:
- **Template & Fixture Integrity (`validate_import_fixtures.py`)**: Confirms that all 4 templates in `data/templates/`, the 4 baseline files in `data/sample-synthetic/`, all 6 edge-case files in `data/sample-synthetic/edge-cases/`, and the `1,000`-row and `10,000`-row performance fixtures in `data/sample-synthetic/perf/` match the frozen v0.3 contract.
- **32 Unit-Test Scenarios (`IMP-V01..V12`, `IMP-I01..I10`, `IMP-E01..E10`)**: Cross-checks every test scenario implemented in `zccmc_ut_import_validator`, `zccmc_ut_import_idempotency`, and `zccmc_ut_import_edge_cases` (RFC 4180 quotes/commas, BOM, CRLF, header drift, leap-year calendar dates, enum normalization, intra-file `DUPLICATE_KEY` rejection, `UNKNOWN_SOURCE_SYSTEM`, `UNKNOWN_OBJECT`, reverse-order no-replay, partial-batch commit, and `PERSISTENCE_FAILURE` atomic rollback).
- **200 Random Row-Order Permutations**: Shuffles row ordering across `objects.csv`, `usage.csv`, `findings.csv`, and `dependencies.csv` 200 times and verifies identical persisted state and SHA-256 row digests.
- **1,000-Row & 10,000-Row Scale & Idempotency Benchmarks (`M1-D08-T01`)**: Runs initial insert (`1,000` and `10,000` `INSERTED`) and immediate repeat import (`1,000` and `10,000` `UNCHANGED`, zero duplicates, zero truncation).
- **Day-10 Clean Reset & Reproducibility (`M1-D10-T01`)**: Runs two consecutive clean resets (`reset_synthetic_store`) followed by the 4-file baseline load (`objects` -> `usage` -> `findings` -> `dependencies`), repeat load (`UNCHANGED`), and corrected batch (`objects_corrected_batch.csv` -> `1 UPDATED`, preserving `ObjectUUID` and append-only batch provenance).

### 2. ADT Activation & ABAP Unit Sequence (Once Non-`$TMP` Package `ZCCMC` Is Provisioned)

1. Provision a transportable development package (`ZCCMC`) in the assigned SAP BTP ABAP Environment tenant and import the repository via abapGit (`.abapgit.xml` maps `/src/` with `PREFIX` folder logic).
2. Activate Member 1's 8 DDIC database tables (`src/zccmc_data/*.tabl.xml`) in order:
   - `zccmc_sourcesys.tabl.xml` (`ZCCMC_SOURCESYS`)
   - `zccmc_custobj.tabl.xml` (`ZCCMC_CUSTOBJ`)
   - `zccmc_usage.tabl.xml` (`ZCCMC_USAGE`)
   - `zccmc_finding.tabl.xml` (`ZCCMC_FINDING`)
   - `zccmc_depend.tabl.xml` (`ZCCMC_DEPEND`)
   - `zccmc_impbatch.tabl.xml` (`ZCCMC_IMPBATCH`)
   - `zccmc_improwerr.tabl.xml` (`ZCCMC_IMPROWERR`)
   - `zccmc_improwres.tabl.xml` (`ZCCMC_IMPROWRES`)
3. Activate Member 1's 8 CDS interface views (`src/zccmc_data/zccmc_i_*.ddls.asddls`):
   - `zccmc_i_sourcesystem`, `zccmc_i_importrowerror`, `zccmc_i_importrowresult`, `zccmc_i_importbatch`
   - `zccmc_i_usagefact`, `zccmc_i_finding`, `zccmc_i_dependency`, `zccmc_i_customobject`
4. Activate Member 1's importer interface and classes (`src/zccmc_import/*`):
   - `zccmc_if_source_adapter.intf.abap`
   - `zccmc_cl_csv_adapter.clas.abap`
   - `zccmc_cl_import_validator.clas.abap`
   - `zccmc_cl_import_batch_mgr.clas.abap`
   - `zccmc_cl_import_object_loader.clas.abap`, `zccmc_cl_import_usage_loader.clas.abap`, `zccmc_cl_import_finding_loader.clas.abap`, `zccmc_cl_import_dep_loader.clas.abap`
   - `zccmc_cl_import_orchestrator.clas.abap`
5. Activate and run Member 1's 3 ABAP Unit test classes (`Ctrl+Shift+F10` in ADT):
   - `src/zccmc_test/zccmc_ut_import_validator.clas.abap` (12 test methods)
   - `src/zccmc_test/zccmc_ut_import_idempotency.clas.abap` (10 test methods)
   - `src/zccmc_test/zccmc_ut_import_edge_cases.clas.abap` (10 test methods)
6. Record transport request IDs and ADT execution screenshots in `docs/m1-day1-day11-status.md`.

---

## Member 2 Runbook — Rules Engine & Portfolio Analytics Verification (`M2-D01-T01` .. `M2-D11-T01`)

From the repository root, run:

```bash
python3 tools/m2_rules_oracle.py --report docs/m2-golden-results.md
```

In ADT (once package `ZCCMC` is provisioned), run ABAP Unit (`Ctrl+Shift+F10`) on `ZCCMC_UT_RULE_ENGINE` (27 test methods) and `ZCCMC_UT_PORTFOLIO_ANALYTICS` (8 test methods).

---

## Member 3 Runbook — Workflow, Security & Audit Verification (`M3-D01-T01` .. `M3-D11-T01`)

### 1. Offline Workflow, Authorization, SoD & Audit Oracle Check

From the repository root, run:

```bash
python3 tools/m3_workflow_oracle.py --report docs/m3-golden-workflow-results.md
```

This executes:
- All **352 combinations** of the `8 Statuses x 11 Actions x 4 Roles` transition matrix (asserting the 27 allowed paths and 325 rejected paths).
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
