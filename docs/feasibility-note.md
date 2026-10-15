# RAP Workflow and Security Feasibility Note

**Owner:** Member 3 — RAP Workflow & Security  
**Version:** 0.3  
**Status:** Repository implementation & offline oracle complete; live SAP ADT activation remains gated on non-`$TMP` package resolution  
**Branch:** `feature/m3-rap-workflow`

## 1. Purpose

Record what was observed while connecting VS Code to the assigned SAP BTP ABAP Environment trial, document the exact capability matrix across Days 1–11, and specify the verified fallback for every capability that remains blocked in the trial environment.

## 2. Environment Details

| Item | Current Finding |
|---|---|
| Development client | VS Code with SAP ABAP Development Tools extension (strictly VS Code workflow; Eclipse is not used) |
| SAP environment | SAP BTP ABAP Environment shared trial (`TRL — Shared Trial US10 — 2026/08` / `AP21` metadata) |
| Connection label in VS Code | `Code-Atlas-TRL (ABAP Cloud)` / workspace folder `BTP_DEV` |
| Authentication / logon | **VERIFIED:** logon succeeded via `ABAP: Log On to Destination…` |
| OData catalog reachability | **VERIFIED (connection only):** OData V2 and V4 system catalog lists returned in VS Code. This proves network/auth reachability only, not project service activation. |
| Non-`$TMP` project package | **BLOCKED / NOT VERIFIED:** Only `Local Objects ($TMP)` is visible in the workspace tree, and the VS Code "Create New ABAP Object" palette does not expose a `Package` creation option. Creating transportable project artifacts in `$TMP` is prohibited by project policy. |
| Repository-side ABAP & RAP deliverables | **COMPLETED (Offline-verified):** Pure ABAP workflow engine (`zccmc_cl_decision_workflow`), 24 ABAP Unit tests (`zccmc_ut_decision_workflow`), proposed RAP tables/CDS/BDEF/BIMP/DCL/SRVD/SRVB (`src/zccmc_rap/*`), and Python reference oracle (`tools/m3_workflow_oracle.py`) are implemented and verified offline. |

## 3. Capability Matrix & Fallback Paths (`M3-D01-T01` .. `M3-D11-T01`)

| ID | Capability | Status | Observed Evidence / Supported Fallback |
|---|---|---|---|
| F-01 | Reach ABAP environment | **VERIFIED (connection)** | Destination logon and V2/V4 catalog queries succeeded in VS Code. |
| F-02 | Non-`$TMP` development package | **BLOCKED** | VS Code object palette lacks `Package` creation; only `$TMP` is visible. **Fallback:** Keep all ABAP/RAP sources serialized in Git (`src/zccmc_rap/`, `src/zccmc_test/`) until an administrator provisions package `ZCCMC` via ADT/abapGit. |
| F-03 | ABAP release & APIs | **NOT VERIFIED** | Pending package access; `zccmc_cl_decision_workflow` uses release-safe plain ABAP types (`string`, `i`, `utclong`, `abap_boolean`) with zero dependency on unverified system classes. |
| F-04..F-08 | Table, CDS, RAP BO, Actions & Validations activation | **BLOCKED (by F-02)** | Proposed definitions (`zccmc_decision.tabl.xml`, `zccmc_decaudit.tabl.xml`, `zccmc_i_decision.ddls.asddls`, `zccmc_i_decision.bdef.asbdef`, `zccmc_bp_i_decision.clas.abap`) are authored in `src/zccmc_rap/`. **Fallback:** Domain state machine and validations are isolated in `zccmc_cl_decision_workflow` and verified offline via `tools/m3_workflow_oracle.py`. |
| F-09 | ABAP Unit execution | **BLOCKED (by F-02)** | `zccmc_ut_decision_workflow.clas.abap` (24 test methods) is ready to run in ADT once package `ZCCMC` is available. **Fallback:** `tools/m3_workflow_oracle.py` executes the identical 24 scenarios + 352 transition matrix offline. |
| F-10..F-13 | Backend identity, roles (`DEVELOPER`, `REVIEWER`, `ADMIN`, `AUDITOR`), instance auth & SoD | **BLOCKED (live IAM) / VERIFIED (engine logic)** | Shared trial does not expose custom IAM business role provisioning from VS Code. **Fallback:** `zccmc_cl_decision_workflow` accepts an explicit `ty_actor_context` (`actor_user`, `roles`, `sod_enabled`) so role checks and Separation of Duties (`OwnerUser`, `CreatedBy`, `SubmittedBy`) are enforced deterministically on the server and testable via synthetic test principals (`DEMO_DEV_1`, `DEMO_REV_1`, `DEMO_ADMIN_1`, `DEMO_AUDITOR_1`). |
| F-14 | ETag / locking / stale-update protection | **BLOCKED (live OData ETag) / VERIFIED (engine version check)** | Proposed BDEF declares `lock master` and `etag master ChangedAt`. In `zccmc_cl_decision_workflow`, monotonic `version_no` rejects stale updates with `ERR_STALE_CONCURRENCY_CONFLICT` (`WF-T13`). |
| F-15..F-19 | Service Definition (`ZCCMC_UI_COCKPIT_O4`), OData V4 Binding & Fiori Elements preview | **BLOCKED (by F-02)** | `zccmc_ui_cockpit_o4.srvd.srvdsrv` and `zccmc_ui_cockpit_o4.srvb.xml` are authored in `src/zccmc_rap/`. Member 4's Fiori Elements apps run against local mock/EDMX metadata (`src/zccmc_ui/zccmc_customobject.edmx`) until the live service is published. |
| F-21 | Interactive CSV upload vs. staged-row import (`M3-D04-T01`) | **BLOCKED (interactive upload)** | Direct browser file upload is not supported without a verified RAP stream/parameter binding. **Fallback:** Use repeatable ABAP Unit / offline fixture validation (`tools/validate_import_fixtures.py`) and expose read-only `ImportBatches` and `ImportRowErrors` projections (`zccmc_c_importbatch`, `zccmc_c_importrowerror`). Never present an unverified upload button as active. |

## 4. Sign-Off Checklist

- [x] Member 3 — Workflow engine (`zccmc_cl_decision_workflow`), RAP artifacts (`src/zccmc_rap/`), 24 ABAP Unit tests (`zccmc_ut_decision_workflow`), and offline oracle (`tools/m3_workflow_oracle.py`) delivered; environment blockers explicitly recorded.
- [x] Member 1 — Persistence tables (`src/zccmc_data/*.tabl.xml` using `SYSUUID_X16` for `ObjectUUID`), CDS views (`zccmc_i_*.ddls.asddls`), importer classes (`src/zccmc_import/*`), 32 ABAP Unit tests (`zccmc_ut_import_*`), and offline oracle (`tools/m1_import_oracle.py`) delivered; live ADT activation gated on `F-02` non-`$TMP` package.
- [ ] Member 2 — Confirm `docs/m3-contract-review.md` resolutions for C6, C7, C9, C13, C14.
- [ ] Member 4 — Consume `docs/state-transitions.md` v0.3 status/action/error vocabulary in Fiori Elements metadata.
