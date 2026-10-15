# Member 3 — RAP Workflow and Security Limitations

**Owner:** Member 3 — RAP Workflow & Security  
**Version:** 0.3 (Day 1 – Day 11 Release Handoff)  
**Status:** Complete repository handoff with explicit environment blockers recorded

## 1. Environment and Package Blockers

- **VS Code Trial Package Limitation (`BLOCKED`):** While VS Code successfully connects to the SAP BTP ABAP Environment trial (`Code-Atlas-TRL`) and reads system OData V2/V4 catalogs, only `Local Objects ($TMP)` is visible and the VS Code object creation palette does not expose a `Package` generator. Project policy prohibits creating shared deliverables in `$TMP`.
- **No Fabricated Activation Claims:** Because a transportable package (`ZCCMC`) and Member 1's base tables (`src/zccmc_data/*`, currently 0 bytes) are not yet activated in the trial tenant, none of the RAP DDL, BDEF, Behavior Pool, DCL, or Service Binding objects under `src/zccmc_rap/` are claimed as activated in SAP. They are delivered as complete, reviewable abapGit source proposals.

## 2. Import Entry Path Limitation (`M3-D04-T01`)

- **Interactive Browser CSV Upload (`BLOCKED`):** Direct browser CSV file upload through RAP/Fiori Elements is not verified in the trial environment and is therefore marked **BLOCKED**.
- **Supported Fallback:** Data ingestion uses repeatable synthetic fixture loading and offline validation (`tools/validate_import_fixtures.py`), while `src/zccmc_rap/` provides the read projections for batch status (`ZCCMC_C_ImportBatch`) and row-level errors (`ZCCMC_C_ImportRowError`). The UI must not render an active file-upload control that claims live backend ingestion.

## 3. Identity, Role Mapping, and Separation of Duties (`M3-D06-T01` / `M3-D10-T01`)

- **Sandbox Identity & Role Provisioning:** Live SAP BTP IAM business role collection mapping (`DEVELOPER`, `REVIEWER`, `ADMIN`, `AUDITOR`) and SSO principal propagation could not be tested in the shared trial tenant.
- **Server-Side Domain Enforcement:** All role permissions, owner-only restrictions (`Actor == OwnerUser`), and Separation of Duties (`Actor != OwnerUser, CreatedBy, SubmittedBy` on `APPROVE` and `OVERRIDE`) are implemented in `zccmc_cl_decision_workflow` against an explicit `ty_actor_context` structure and verified across all 352 state/action/role combinations and 24 unit tests (`zccmc_ut_decision_workflow` and `tools/m3_workflow_oracle.py`).
- **UI Hiding Is Not Security:** Disabling or hiding buttons in Fiori Elements is treated strictly as UX convenience; every action call re-validates state, role, ownership, SoD, and mandatory reason length (>= 10 characters) in the backend service layer.

## 4. Concurrency and Audit Persistence (`M3-D06-T01` / `M3-D08-T01`)

- **Optimistic Concurrency (`ETag` / `VersionNo`):** Live OData V4 HTTP `If-Match` ETag header handling awaits service binding publication in ADT. In the domain workflow engine (`zccmc_cl_decision_workflow`), optimistic concurrency is enforced via `version_no` (`iv_expected_version`), rejecting stale updates with `ERR_STALE_CONCURRENCY_CONFLICT` (`WF-T13`).
- **Append-Only Audit Trail:** Both the proposed RAP behavior definition (`zccmc_i_decision.bdef.asbdef` / `zccmc_c_decision.bdef.asbdef`) and `zccmc_cl_decision_workflow=>reject_audit_mutation` forbid `UPDATE` and `DELETE` on audit records (`ERR_AUDIT_IMMUTABLE`, `WF-T12`). Every rejected workflow action leaves the decision state and audit list completely untouched (`WF-T16`).

## 5. Governance & Safety Invariants

- **Human-in-the-Loop Only:** Workflow actions (`APPROVE`, `OVERRIDE`, `START`, `MARK_MIGRATED`, etc.) record human governance decisions and audit events only. The cockpit never modifies, retires, or deletes custom ABAP code automatically.
- **Synthetic Data Only:** All test fixtures, actor IDs (`DEMO_DEV_1`, `DEMO_REV_1`, `DEMO_ADMIN_1`, `DEMO_AUDITOR_1`), and rehearsal logs use 100% synthetic demonstration data.
