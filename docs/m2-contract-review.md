# Member 2 Review — Import / Rules / Workflow Integration Contract (v1.0.0 Frozen Sign-Off)

**Reviewer role:** Member 2 (Rules & Analytics).  
**Status:** **SIGNED OFF for Repository v1.0.0 Freeze (`M2-D09-T01` / `M2-D10-T01` / `M2-D11-T01`).**  
**Reviewed artifacts (`main` @ `756fa549`):**
- **Member 1 (Day 1–11 Complete, `PR #31` / `126439f1`):** `docs/data-contract.md` (v0.3), `docs/import-design.md` (v0.3), `docs/er-diagram.md`, `docs/m1-contract-review.md`, `docs/m1-day1-day11-status.md`, `docs/m1-golden-import-results.md`, 8 database tables (`src/zccmc_data/*.tabl.xml`), 8 CDS interface views (`src/zccmc_data/zccmc_i_*.ddls.asddls`), 9 importer classes/interfaces (`src/zccmc_import/*` including `zccmc_cl_import_orchestrator=>build_m2_evidence_for_obj` and `reset_synthetic_data`), and 32 importer ABAP Unit tests (`IMP-V01..V12`, `IMP-I01..I10`, `IMP-E01..E10`).
- **Member 3 (Day 1–11 Complete):** `docs/state-transitions.md` (v0.3), `docs/m3-contract-review.md`, `docs/m3-day1-day11-status.md`, `src/zccmc_rap/*`, and `src/zccmc_test/zccmc_ut_decision_workflow.clas.abap` (24 tests).
- **Member 4 (Day 1–11 Complete, `PR #32` / `756fa549`):** `docs/architecture.md`, `docs/demo-script.md`, `src/zccmc_ui/fiori-app/`, and `src/zccmc_ui/portfolio-overview/`.

All checked-in records and fixtures are **DEMO / SYNTHETIC**.

---

## 1. Sign-Off on Member 1 Day 1–11 Data & Import Contract (`docs/data-contract.md` v0.3)

| Contract Item | Member 2 Position | Verified Integration (`src/zccmc_import/` → `src/zccmc_core/`) |
|---|---|---|
| Four CSV schemas (`objects`, `usage`, `findings`, `dependencies`) | **Approved & Signed Off** | Validated by `zccmc_cl_import_validator` and `tools/m1_import_oracle.py`; consumed by `zccmc_cl_rule_engine`. |
| 8 Persistence tables & 8 CDS views (`ZCCMC_SOURCESYS`, `ZCCMC_CUSTOBJ`, `ZCCMC_USAGE`, `ZCCMC_FINDING`, `ZCCMC_DEPEND`, `ZCCMC_IMPBATCH`, `ZCCMC_IMPROWERR`, `ZCCMC_IMPROWRES`) | **Approved & Signed Off** | Every active rule condition in `zccmc_cl_rule_engine` maps 1:1 to a persisted field on `ZCCMC_I_CustomObject`, `ZCCMC_I_UsageFact`, `ZCCMC_I_Finding`, and `ZCCMC_I_Dependency`. |
| M1→M2 Orchestrator Evidence Bridge (`zccmc_cl_import_orchestrator=>build_m2_evidence_for_obj` & `zccmc_cl_rule_engine=>build_evidence_from_import`) | **Approved & Verified (`T31`)** | Assembles `CustomObject`, `UsageFact`, `Finding`, and inbound caller `Dependency` rows into `zccmc_cl_rule_engine=>ty_evidence`. |
| Reproducible Synthetic Reset (`zccmc_cl_import_orchestrator=>reset_synthetic_data`, `M1-D10-T01`) | **Approved & Verified** | Clears the 8 synthetic persistence tables deterministically before clean re-import so two consecutive runs produce identical object counts and golden recommendations (`M2-D10-T01`). |
| `objects.findings_as_of` (optional date; filled = scan complete even with 0 rows; blank = coverage unknown) | **Approved & Signed Off** | Blank `findings_as_of` triggers `FINDINGS_NOT_LOADED` (`MANUAL_REVIEW`) even if partial finding rows exist (`T14`). |
| Blank `criticality` normalizes to `UNKNOWN` | **Approved & Signed Off** | Normalized by `zccmc_cl_import_object_loader` and `zccmc_cl_rule_engine`; triggers `CRITICALITY_UNKNOWN` (`MANUAL_REVIEW`, `T07`). |
| Severity `HIGH \| MEDIUM \| LOW \| INFO`, blank rejected | **Approved & Signed Off** | Validated by `zccmc_cl_import_validator`; `R30`/`R60` count `HIGH` findings while `MEDIUM`, `LOW`, and `INFO` do not block `KEEP_ADAPT` (`T05`, `T06`, `T22`). |

---

## 2. Final Resolution Table for Day-2 Items (`C1`–`C14`) Across M1, M2, M3 & M4

| # | Issue | Frozen v1.0.0 Resolution (`M1` + `M2` + `M3` + `M4`) | Verified By |
|---|---|---|---|
| `C1` | **Several usage rows per object** (`ZCCMC_USAGE` key is `object + period_start + period_end + evidence_source`). | **Resolved (`docs/m1-contract-review.md` & `zccmc_cl_rule_engine`):** When `lines( usages ) > 1` is passed for one object, the rule engine appends `MULTIPLE_USAGE_FACTS` and routes safely to `MANUAL_REVIEW`. | `T15`, `T26` |
| `C2` | **No coverage indicator for dependencies** (`dependencies.csv` has no `dependencies_as_of`). | **Resolved:** Absence of rows in `ZCCMC_DEPEND` is treated as zero inbound callers, while `R20` (`RETIRE_CANDIDATE`) requires human owner confirmation before retirement (`docs/limitations.md`). | `T01`, `docs/limitations.md` |
| `C3` | **Meaning of "called by" (`dependency_type`).** | **Resolved:** In `zccmc_cl_import_orchestrator=>build_m2_evidence_for_obj` and `zccmc_cl_rule_engine`, any dependency row where `to_object` is the evaluated object counts as an inbound caller regardless of `dependency_type`. | `T03`, `T16`, `T27`, `T31` |
| `C4` | **Caller with `UNKNOWN` criticality on the retirement path.** | **Resolved:** When `usage_count = 1`, `run_count = 0`, and `has_high_caller = abap_false`, any caller with `UNKNOWN` criticality appends `CALLER_CRITICALITY_UNKNOWN` and routes to `MANUAL_REVIEW`. | `T16` |
| `C5` | **Definition of "whole calendar months".** | **Resolved:** Largest `n >= 0` where `period_start + n months` (day clamped to target month end, leap-year aware) is `<= period_end`. | `T23` (7 boundary cases) |
| `C6` | **Deterministic evaluation date.** | **Resolved (`docs/m3-contract-review.md`):** `iv_evaluation_date` is passed explicitly by the caller (UTC date of `RunTimestamp`); the engine never reads the system clock. | `T13`, `T25` |
| `C7` | **Reproducibility across in-place evidence updates.** | **Resolved (`docs/m1-contract-review.md` & `docs/m3-contract-review.md`):** Member 1's `ZCCMC_IMPROWRES` retains append-only batch/row provenance, `zccmc_cl_rule_engine=>build_explanation` embeds the exact evidence values used, and Member 3 persists `EvidenceSummary` (= `Explanation`), `MissingEvidence`, `MatchedRuleIDs`, `RuleSetVersion`, and `RecommendationRunID` on `ZCCMC_DECISION` and `ZCCMC_DECAUDIT`. | `T24`, `T27`, `WF-T19` |
| `C8` | **Findings from older scans on corrected re-imports.** | **Resolved:** `zccmc_cl_rule_engine` counts all `HIGH` finding rows passed in `is_evidence-findings`; clean portfolio resets use `zccmc_cl_import_orchestrator=>reset_synthetic_data`. | `T22`, `T30` |
| `C9` | **Rule-set ID, version, and `RecommendationRunID` contract.** | **Resolved:** Frozen v1.0.0 constants `c_default_ruleset_id = 'ZCCMC_DEMO'` and `c_default_ruleset_version = '1.0.0'`; `RecommendationRunID` is `string` (`CHAR(64)` in `ZCCMC_DECISION`). | `T24`, `T28`, `PA-T09` |
| `C10` | **Additional date checks not in spec.** | **Resolved:** Per `M2-D09-T01`, no undocumented rules or thresholds were added; freshness (`30` days) applies strictly to `usage.evidence_as_of`. | `T13`, `T14` |
| `C11` | **Source ATC priority mapping to `HIGH/MEDIUM/LOW/INFO`.** | **Resolved (`docs/data-contract.md` v0.3):** Enforced by `zccmc_cl_import_validator` on import. | `T05`, `T06`, `T22` |
| `C12` | **`REWRITE_RAP` and `SIDE_BY_SIDE_BTP` source data gap.** | **Resolved:** Enum values remain in `c_outcome` and `by_strategy` (`0` count), while no condition code is fabricated without source CSV columns. | `docs/rules-spec.md` §6, `docs/limitations.md` |
| `C13` | **`RiskScore` and `RiskCriticality` in UI metadata.** | **Resolved:** No risk score formula is defined in `docs/rules-spec.md`; Member 2 does not fabricate a score or ML metric. | `docs/rules-spec.md` §10 |
| `C14` | **Field alignment with Member 3 (`EvidenceSummary` vs. `Explanation`).** | **Resolved:** Member 3's `EvidenceSummary` stores Member 2's `explanation`, alongside `MissingEvidence` and `MatchedRuleIDs`. | `docs/m3-contract-review.md` §2 |
