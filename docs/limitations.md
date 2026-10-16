# Clean Core Migration Cockpit — Release Limitations & Explicit Blockers

**Owners:** Member 1 (Data & Import), Member 2 (Rules & Analytics), Member 3 (RAP Workflow & Security), Member 4 (Fiori UX & QA)  
**Version:** 1.0.0 (Day 1 – Day 11 Release Handoff, `main` @ `756fa549`)  
**Status:** Complete repository handoff across all four members with explicit environment blockers and scope boundaries recorded

---

## 1. Environment and Package Blockers (`All Members`)

- **VS Code Trial Package Limitation (`BLOCKED`):** While VS Code connects to the SAP BTP ABAP Environment trial (`Code-Atlas-TRL`, system `TRL` / `AP21`) and reads system OData V2/V4 catalogs, only `Local Objects ($TMP)` is visible and the VS Code object creation palette does not expose a `Package` generator. Project policy prohibits creating shared deliverables in `$TMP`.
- **No Fabricated Activation Claims:** All persistence tables (`src/zccmc_data/*.tabl.xml`), CDS interface views (`src/zccmc_data/zccmc_i_*.ddls.asddls`), importer classes (`src/zccmc_import/*`), rule and analytics classes (`src/zccmc_core/*`), RAP workflow/service objects (`src/zccmc_rap/*`), and 100 ABAP Unit test methods (`src/zccmc_test/*`) are delivered as complete, reviewable abapGit source artifacts backed by executable offline Python reference oracles (`tools/validate_import_fixtures.py`, `tools/m1_import_oracle.py`, `tools/m2_rules_oracle.py`, `tools/m3_workflow_oracle.py`). Live SAP ADT activation and OData service publication remain gated on provisioning a transportable package (`ZCCMC`) in the trial tenant.

---

## 2. Import Entry Path Limitation (`Member 1` & `Member 3` — `M1-D04-T01` / `M3-D04-T01`)

- **Interactive Browser CSV Upload (`BLOCKED`):** Direct browser CSV file upload through RAP/Fiori Elements is not verified in the trial environment and is therefore marked **BLOCKED**.
- **Supported Fallback:** Data ingestion uses Member 1's repeatable server-side / ABAP Unit importer (`zccmc_cl_import_orchestrator`, `zccmc_cl_csv_adapter`, `zccmc_cl_import_validator`, and the four entity loaders in `src/zccmc_import/`) plus `reset_synthetic_data` (`M1-D10-T01`) and offline verification (`tools/m1_import_oracle.py`), while `src/zccmc_rap/` provides the read projections for batch status (`ZCCMC_C_ImportBatch`) and row-level errors (`ZCCMC_C_ImportRowError`). The UI must not render an active file-upload control that claims live backend ingestion.

---

## 3. Rules Engine & Portfolio Analytics Limitations (`Member 2` — `M2-D01-T01` .. `M2-D11-T01`)

- **Project Demo Policy, Not Official SAP Migration Guidance:** The frozen `ZCCMC_DEMO` v1.0.0 rule set (`R10`, `R20`, `R30`, `R60`) and its parameters (`12` whole calendar months minimum usage coverage, `30` days maximum usage evidence age, `1` `HIGH`-severity finding threshold) are **illustrative project demonstration policy**. They must be validated and configured by a qualified SAP migration/domain expert before any real customer use.
- **Deterministic Rules Only (No AI / ML / Risk Score):** `zccmc_cl_rule_engine` is a strictly deterministic rule evaluator. No machine learning, predictive model, or numeric `RiskScore` / confidence percentage is implemented or claimed, because `docs/rules-spec.md` defines no weighted scoring formula (`C13`).
- **`REWRITE_RAP` and `SIDE_BY_SIDE_BTP` Source-Field Gap (`C12`):** While all five canonical outcomes (`KEEP_ADAPT`, `REWRITE_RAP`, `RETIRE_CANDIDATE`, `SIDE_BY_SIDE_BTP`, `MANUAL_REVIEW`) are defined in `zccmc_cl_rule_engine=>c_outcome` and seeded in `zccmc_cl_portfolio_analytics=>compute_summary`, the four MVP CSV templates (`data/templates/*.csv`) do not contain columns for transactional reuse or external/released-API boundaries. Active rules for `REWRITE_RAP` (reserved priority `40`) and `SIDE_BY_SIDE_BTP` (reserved priority `50`) are therefore not evaluated in v1.0.0.
- **Dependency Coverage & Rescan Replacement (`C2`, `C8`):** `dependencies.csv` does not carry an object-level `dependencies_as_of` date, so absence of dependency rows in `ZCCMC_DEPEND` is treated as zero inbound callers; `R20` (`RETIRE_CANDIDATE`) mitigates this by requiring human owner confirmation before retirement. Clean demo resets use `zccmc_cl_import_orchestrator=>reset_synthetic_data`.
- **Rule-Set Persistence (`C9`):** In v1.0.0, the frozen seed rule set (`ZCCMC_DEMO` / `1.0.0`) is provided by `zccmc_cl_rule_engine=>seed_ruleset` and custom rule sets can be passed via `is_ruleset`. Dedicated database tables for editing/publishing rule sets and the Rules Administration UI remain out of scope for the MVP slice.

---

## 4. Identity, Role Mapping, and Separation of Duties (`Member 3` — `M3-D06-T01` / `M3-D10-T01`)

- **Sandbox Identity & Role Provisioning:** Live SAP BTP IAM business role collection mapping (`DEVELOPER`, `REVIEWER`, `ADMIN`, `AUDITOR`) and SSO principal propagation could not be tested in the shared trial tenant.
- **Server-Side Domain Enforcement:** All role permissions, owner-only restrictions (`Actor == OwnerUser`), and Separation of Duties (`Actor != OwnerUser, CreatedBy, SubmittedBy` on `APPROVE` and `OVERRIDE`) are implemented in `zccmc_cl_decision_workflow` against an explicit `ty_actor_context` structure and verified across all 352 state/action/role combinations and 24 unit tests (`zccmc_ut_decision_workflow` and `tools/m3_workflow_oracle.py`).
- **UI Hiding Is Not Security:** Disabling or hiding buttons in Fiori Elements is treated strictly as UX convenience; every action call re-validates state, role, ownership, SoD, and mandatory reason length (`>= 10` characters) in the backend service layer.

---

## 5. Concurrency, Audit Persistence & Governance Invariants (`Member 3` — `M3-D06-T01` / `M3-D08-T01`)

- **Optimistic Concurrency (`ETag` / `VersionNo`):** Live OData V4 HTTP `If-Match` ETag header handling awaits service binding publication in ADT. In the domain workflow engine (`zccmc_cl_decision_workflow`), optimistic concurrency is enforced via `version_no` (`iv_expected_version`), rejecting stale updates with `ERR_STALE_CONCURRENCY_CONFLICT` (`WF-T13`).
- **Append-Only Audit Trail:** Both the proposed RAP behavior definition (`zccmc_i_decision.bdef.asbdef` / `zccmc_c_decision.bdef.asbdef`) and `zccmc_cl_decision_workflow=>reject_audit_mutation` forbid `UPDATE` and `DELETE` on audit records (`ERR_AUDIT_IMMUTABLE`, `WF-T12`). Every rejected workflow action leaves the decision state and audit list completely untouched (`WF-T16`).
- **Human-in-the-Loop & Synthetic Data Only:** Workflow actions record human governance decisions and audit events only; the cockpit never modifies, retires, or deletes custom ABAP code automatically. All test fixtures, actor IDs, and rehearsal logs use 100% synthetic demonstration data.
