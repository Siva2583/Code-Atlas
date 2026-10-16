# Clean Core Migration Cockpit — Shared Test Matrix (Days 1–11 Complete)

All sample data in this repository is **DEMO / SYNTHETIC**.  
- **Evaluation Date for Member 2 Rules & Analytics:** `2026-10-14` (`iv_evaluation_date = '20261014'`)  
- **Frozen Rule-Set Version:** `ZCCMC_DEMO` / `1.0.0`  
- **Total ABAP Unit Test Methods Across Repository:** **`100` ABAP Unit Tests** (`32` Member 1 Import + `44` Member 2 Rules & Analytics + `24` Member 3 Workflow & Security)  
- **Status Legend:**
  - **Oracle Passed:** Verified by the standalone Python reference runners (`tools/m1_import_oracle.py`, `tools/validate_import_fixtures.py`, `tools/m2_rules_oracle.py`, `tools/m3_workflow_oracle.py`).
  - **ABAP Unit Ready (Pending ADT Package):** ABAP Unit test classes (`zccmc_ut_import_validator`, `zccmc_ut_import_idempotency`, `zccmc_ut_import_edge_cases`, `zccmc_ut_rule_engine`, `zccmc_ut_portfolio_analytics`, `zccmc_ut_decision_workflow`) are implemented and cross-checked against the oracles; live ADT execution (`Ctrl+Shift+F10`) awaits transportable non-`$TMP` package provisioning (`ZCCMC`) in the shared SAP BTP trial tenant.

---

## 1. Member 2 — Rules Engine Test Matrix (`ZCCMC_UT_RULE_ENGINE` — 31 Tests, Frozen v1.0.0)

ABAP Unit class: `src/zccmc_test/zccmc_ut_rule_engine.clas.abap` testing `src/zccmc_core/zccmc_cl_rule_engine.clas.abap`.  
Reference oracle: `tools/m2_rules_oracle.py` and `docs/m2-golden-results.md`.

| Test ID / Method | Scenario & Input Facts | Expected Output (`Strategy`, `MatchedRuleIDs`, `MissingEvidence`) | Sample CSV / Fixture Source | Status |
|---|---|---|---|---|
| `T01` (`t01_no_use_12_months_retire`) | `run_count = 0`, 12-month window (`2025-10-13`..`2026-10-13`), criticality `LOW`, `findings_as_of` set (`0` findings), no caller | `RETIRE_CANDIDATE`, matched `R20`, missing `[]` | In-code boundary fixture (Paper `T1`) | Oracle passed. ABAP Unit ready (`T01`). |
| `T02` (`t02_no_use_11_months_manual`) | Same as `T01` with 11-month window (`2025-11-13`..`2026-10-13`) | `MANUAL_REVIEW`, matched `R10`, missing `WINDOW_TOO_SHORT` | In-code 11-month boundary + `ZMM_STOCK_ALERT` (2 months) | Oracle passed. ABAP Unit ready (`T02`, `T23`). |
| `T03` (`t03_high_caller_no_match`) | Same as `T01`, but called by a `HIGH`-criticality object | `MANUAL_REVIEW`, matched `[]`, missing `NO_RULE_MATCH` | In-code fixture (Paper `T3`) | Oracle passed. ABAP Unit ready (`T03`). |
| `T04` (`t04_used_zero_findings_keep`) | `run_count = 2480`, criticality `HIGH`, 12-month window, `findings_as_of` set (`0` findings) | `KEEP_ADAPT`, matched `R60`, missing `[]` | In-code boundary fixture (Paper `T4`) | Oracle passed. ABAP Unit ready (`T04`). |
| `T05` (`t05_one_high_finding_manual`) | Same as `T04` with `1` `HIGH` finding | `MANUAL_REVIEW`, matched `R30`, missing `[]` | `ZSD_CUST_CREDIT_CHECK` (`1 HIGH`), `ZSD_OPEN_ORDERS_RPT` (`2 HIGH`) | Oracle passed. ABAP Unit ready (`T05`, `T27`). |
| `T06` (`t06_used_low_finding_keep`) | `run_count = 15210`, criticality `MEDIUM`, `1` `LOW` finding | `KEEP_ADAPT`, matched `R60`, missing `[]` | `ZCL_PRICING_HELPER` (`objects.csv`, `usage.csv`, `findings.csv`) | Oracle passed. ABAP Unit ready (`T06`, `T27`). |
| `T07` (`t07_criticality_unknown_manual`) | `criticality = UNKNOWN`, rest complete (`100` runs, `0` findings) | `MANUAL_REVIEW`, matched `R10, R60`, missing `CRITICALITY_UNKNOWN` | `ZCL_INVOICE_UTIL`, `ZHR_PAYROLL_ADJ` | Oracle passed. ABAP Unit ready (`T07`, `T27`). |
| `T08` (`t08_no_usage_row_manual`) | No usage row for object (`usages` empty) | `MANUAL_REVIEW`, matched `R10`, missing `NO_USAGE_FACT` | `ZFI_OLD_LEDGER_EXPORT` | Oracle passed. ABAP Unit ready (`T08`, `T27`). |
| `T09` (`t09_equal_priority_conflict`) | Active rule `R61` at priority `60` (`REWRITE_RAP`) ties with `R60` (`KEEP_ADAPT`) | `MANUAL_REVIEW`, matched `R60, R61`, missing `RULE_CONFLICT`, explanation names both rules | In-code rule-set configuration (Paper `T9`) | Oracle passed. ABAP Unit ready (`T09`). |
| `T10` (`t10_zero_runs_with_date_manual`) | Contradictory usage: `run_count = 0` and `last_executed = 2025-09-25` | `MANUAL_REVIEW`, matched `R10, R20`, missing `ZERO_RUNS_WITH_LAST_EXECUTED` | In-code fixture (Paper `T10`) | Oracle passed. ABAP Unit ready (`T10`). |
| `T11` (`t11_runs_without_date_manual`) | Contradictory usage: `run_count > 0` and `last_executed` initial | `MANUAL_REVIEW`, matched `R10, R60`, missing `RUNS_WITHOUT_LAST_EXECUTED` | In-code fixture | Oracle passed. ABAP Unit ready (`T11`). |
| `T12` (`t12_period_end_before_start`) | Contradictory window: `period_end < period_start` | `MANUAL_REVIEW`, matched `R10, R60`, missing `PERIOD_END_BEFORE_START` only | In-code fixture | Oracle passed. ABAP Unit ready (`T12`). |
| `T13` (`t13_staleness_boundary`) | `evidence_as_of` age `30` days (`2026-09-14`) vs. `31` days (`2026-09-13`) on `2026-10-14` | `30` days → `KEEP_ADAPT` (`R60`); `31` days → `MANUAL_REVIEW` (`R10, R60`, `EVIDENCE_STALE`) | In-code boundary fixtures | Oracle passed. ABAP Unit ready (`T13`). |
| `T14` (`t14_findings_coverage_unknown`) | `findings_as_of` blank/initial | `MANUAL_REVIEW`, matched `R10, R60`, missing `FINDINGS_NOT_LOADED` | In-code fixture | Oracle passed. ABAP Unit ready (`T14`). |
| `T15` (`t15_multiple_usage_facts`) | Two usage rows supplied for the same object (`C1`) | `MANUAL_REVIEW`, matched `R10`, missing `MULTIPLE_USAGE_FACTS` | In-code fixture | Oracle passed. ABAP Unit ready (`T15`). |
| `T16` (`t16_caller_criticality_unknown`) | `UNKNOWN` caller criticality when unused (`run_count = 0`) vs. used (`run_count > 0`) vs. `MEDIUM`/`LOW` callers (`C4`) | Unused + `UNKNOWN` caller → `MANUAL_REVIEW` (`CALLER_CRITICALITY_UNKNOWN`); known non-`HIGH` callers → `RETIRE_CANDIDATE`; used + `UNKNOWN` caller → `KEEP_ADAPT` | In-code fixtures | Oracle passed. ABAP Unit ready (`T16`). |
| `T17` (`t17_same_priority_same_outcome`) | Duplicate rule `R62` at priority `60` with same `KEEP_ADAPT` outcome as `R60` | `KEEP_ADAPT`, matched `R60, R62`, missing `[]` (no conflict) | In-code rule-set configuration | Oracle passed. ABAP Unit ready (`T17`). |
| `T18` (`t18_no_rule_matches`) | Rule set containing `R20` only evaluated against a used object | `MANUAL_REVIEW`, matched `[]`, missing `NO_RULE_MATCH` | In-code rule-set configuration | Oracle passed. ABAP Unit ready (`T18`). |
| `T19` (`t19_missing_r10_still_manual`) | Rule `R10` deleted from rule set, evaluated with `criticality = UNKNOWN` | `MANUAL_REVIEW` (hard safety invariant), matched `R60`, missing `CRITICALITY_UNKNOWN` | In-code rule-set configuration | Oracle passed. ABAP Unit ready (`T19`). |
| `T20` (`t20_unknown_condition_code`) | Active rule `RX` with unknown condition code `NOT_A_REAL_CONDITION` | `MANUAL_REVIEW`, matched `R60`, missing `UNKNOWN_CONDITION_CODE` | In-code rule-set configuration | Oracle passed. ABAP Unit ready (`T20`). |
| `T21` (`t21_inactive_rule_is_ignored`) | Rule `R60` set `active = abap_false` | `MANUAL_REVIEW`, matched `[]`, missing `NO_RULE_MATCH` | In-code rule-set configuration | Oracle passed. ABAP Unit ready (`T21`). |
| `T22` (`t22_info_and_medium_not_high`) | Used object with `2 MEDIUM`, `1 LOW`, `1 INFO` findings (`0 HIGH`) | `KEEP_ADAPT`, matched `R60`, missing `[]` | In-code fixture + `ZCL_PRICING_HELPER` | Oracle passed. ABAP Unit ready (`T22`). |
| `T23` (`t23_whole_months_boundaries`) | `whole_months_between` across 7 date pairs (12 mo, 11 mo, 2 mo, Jan 31→Feb 28 clamp, leap year Feb 29→Feb 28, same day, end < start) | `12, 11, 2, 1, 12, 0, 0` | `docs/rules-spec.md` §9 | Oracle passed. ABAP Unit ready (`T23`). |
| `T24` (`t24_result_and_explanation`) | Full result fields & explanation trace (`ZCCMC_DEMO`, `1.0.0`, `run_id` passed through and excluded from explanation text) | Exact match on `object_id`, `run_id`, `ruleset_id`, `ruleset_version`, and `explanation` | In-code fixture + all 7 golden objects | Oracle passed (renders & checks exact explanations). ABAP Unit ready (`T24`). |
| `T25` (`t25_repeat_run_is_identical`) | Evaluate twice with `RUN-A` and `RUN-B` | Identical result tuple apart from `run_id` | In-code fixture + 2 clean CSV runs | Oracle passed. ABAP Unit ready (`T25`). |
| `T26` (`t26_row_order_does_not_matter`) | Reverse findings, callers, usage rows, and rule rows | Identical result tuple | 200 random CSV permutations + 20x rule shuffles | Oracle passed (`0` differences). ABAP Unit ready (`T26`). |
| `T27` (`t27_sample_objects_golden`) | Evaluate all 7 synthetic sample objects against frozen golden table | `6 MANUAL_REVIEW`, `1 KEEP_ADAPT`, exact rules, missing codes & explanations | `data/sample-synthetic/*.csv` | Oracle passed. ABAP Unit ready (`T27`). |
| `T28` (`t28_portfolio_batch_and_perm`) | `evaluate_portfolio` across two clean runs and reversed object input order (`M2-D08-T01`) | Byte-for-byte identical 7-object result tables sorted by `object_id` | All 7 sample objects | Oracle passed. ABAP Unit ready (`T28`). |
| `T29` (`t29_no_cross_object_leakage`) | Verify unrelated objects in a portfolio batch never leak facts or missing codes into another object's explanation (`M2-D08-T01`) | Batch result for `ZCL_PRICING_HELPER` equals standalone result; zero cross-object leakage | All 7 sample objects | Oracle passed. ABAP Unit ready (`T29`). |
| `T30` (`t30_edge_and_corrected_fixtures`) | Evaluate `ZSD_OPEN_ORDERS_RPT` after `objects_corrected_batch.csv` and `findings_quoted_fields.csv` (`F900 LOW`) (`M2-D08-T01` / `M2-D10-T01`) | Result tuple (`MANUAL_REVIEW`, `R30`, `high_findings=2`) and explanation remain 100% unchanged | `edge-cases/objects_corrected_batch.csv`, `edge-cases/findings_quoted_fields.csv` | Oracle passed. ABAP Unit ready (`T30`). |
| `T31` (`t31_m1_import_evidence_bridge`) | Build normalized evidence via `build_evidence_from_import` aligned with Member 1's `zccmc_cl_import_orchestrator=>build_m2_evidence_for_obj` | `KEEP_ADAPT`, matched `R60`, missing `[]`, normalized uppercase fields | M1→M2 orchestrator bridge fixture | Oracle passed. ABAP Unit ready (`T31`). |

---

## 2. Member 2 — Portfolio Analytics Test Matrix (`ZCCMC_UT_PORTFOLIO_ANALYTICS` — 13 Tests, Frozen v1.0.0)

ABAP Unit class: `src/zccmc_test/zccmc_ut_portfolio_analytics.clas.abap` testing `src/zccmc_core/zccmc_cl_portfolio_analytics.clas.abap`.

| Test ID / Method | Scenario | Expected Result | Fixture Source | Status |
|---|---|---|---|---|
| `PA-T01` (`t01_empty_portfolio`) | Empty portfolio (`0` items) | `total_objects = 0`, all 5 strategy counts `0`, `by_missing_reason` empty | Empty table | Oracle passed. ABAP Unit ready (`T01`). |
| `PA-T02` (`t02_sample_7_objects_reconcile`) | Full 7-object sample reconciliation | `M-01 = 7`; `M-02`: `MANUAL_REVIEW = 6`, `KEEP_ADAPT = 1`; `M-03 = 4` (`CRITICALITY_UNKNOWN = 2`, `NO_USAGE_FACT = 1`, `WINDOW_TOO_SHORT = 1`); `sum(by_strategy) == 7` | All 7 sample objects | Oracle passed. ABAP Unit ready (`T02`). |
| `PA-T03` (`t03_filter_by_package`) | Filter by `package_name` & `criticality` | `ZSD_REPORTS` → `1 MANUAL_REVIEW`; `ZSD_PRICING` → `1 KEEP_ADAPT`; `criticality = HIGH` → `2 MANUAL_REVIEW` | `objects.csv` packages | Oracle passed. ABAP Unit ready (`T03`). |
| `PA-T04` (`t04_filter_by_source_system`) | Filter by `source_system` | `DEMO_SYS` → `7`; `NON_EXISTENT_SYS` → `0` | `objects.csv` | Oracle passed. ABAP Unit ready (`T04`). |
| `PA-T05` (`t05_filter_by_strategy_missing`) | Filter by `strategy` and `only_missing_evidence` | `KEEP_ADAPT` → `1`; `only_missing_evidence = true` → `4` | All 7 sample objects | Oracle passed. ABAP Unit ready (`T05`). |
| `PA-T06` (`t06_no_join_double_counting`) | 1:N join duplicate row & reason-code deduplication | 6 repeated rows for 1 object still yield `total_objects = 1` and `reason_count = 1` | Simulated 1:N join rows | Oracle passed. ABAP Unit ready (`T06`). |
| `PA-T07` (`t07_latest_run_wins`) | Multi-run deduplication (latest run wins) | `RUN-0002` (`KEEP_ADAPT`) supersedes `RUN-0001` (`MANUAL_REVIEW`) for the same object key | In-code 2-run fixture | Oracle passed. ABAP Unit ready (`T07`). |
| `PA-T08` (`t08_row_order_determinism`) | Input row-order determinism | Reversed item table and 200 random shuffles produce identical `ty_summary` | All 7 sample objects | Oracle passed. ABAP Unit ready (`T08`). |
| `PA-T09` (`t09_filter_by_ruleset_version`) | Filter by `ruleset_version` (`M2-D09-T01`) | `ruleset_version = '1.0.0'` → `7`; `'0.1.0-DRAFT'` → `0` | All 7 sample objects | Oracle passed. ABAP Unit ready (`T09`). |
| `PA-T10` (`t10_groupings_sys_pkg_crit`) | Verify `by_source_system`, `by_package`, and `by_criticality` group counts (`M2-D09-T01`) | `DEMO_SYS = 7`; `7` packages (`1` each); `HIGH = 2`, `LOW = 1`, `MEDIUM = 2`, `UNKNOWN = 2` | All 7 sample objects | Oracle passed. ABAP Unit ready (`T10`). |
| `PA-T11` (`t11_unknown_strategy_fallback`) | Blank or unrecognized strategy normalization (`M2-D09-T01`) | Both normalize to `MANUAL_REVIEW`; `by_strategy` strictly retains 5 canonical buckets | In-code edge fixture | Oracle passed. ABAP Unit ready (`T11`). |
| `PA-T12` (`t12_missing_identity_and_id_fb`) | Blank `object_name` fallback to `object_id` and blank-identity skip (`M2-D09-T01`) | Blank-identity row skipped; `object_id`-fallback row counted once (`UNSPECIFIED` package) | In-code edge fixture | Oracle passed. ABAP Unit ready (`T12`). |
| `PA-T13` (`t13_batch_build_from_m1_objects`) | Batch construction via `build_items_from_results` from Member 1 `CustomObject` metadata + `evaluate_portfolio` | Reconciles `total_objects`, `by_strategy`, and `by_package` across batch results | M1→M2 batch metadata fixture | Oracle passed. ABAP Unit ready (`T13`). |

---

## 3. Member 1 — Data Persistence & Import Test Matrix (`32` Tests, Days 1–11 Complete)

ABAP Unit classes (`src/zccmc_test/`):
- `zccmc_ut_import_validator.clas.abap` (`12` tests: `IMP-V01`..`IMP-V12`)
- `zccmc_ut_import_idempotency.clas.abap` (`10` tests: `IMP-I01`..`IMP-I10`)
- `zccmc_ut_import_edge_cases.clas.abap` (`10` tests: `IMP-E01`..`IMP-E10`)  
Reference oracle & logs: `tools/m1_import_oracle.py`, `tools/validate_import_fixtures.py`, `docs/m1-golden-import-results.md`, and `docs/m1-day1-day11-status.md`.

| Test Suite | Scenarios Covered | Expected Result | Status |
|---|---|---|---|
| `ZCCMC_UT_IMPORT_VALIDATOR` (`IMP-V01`..`IMP-V12`) | Exact 4-file header validation, RFC 4180 quoting/escaping, UTF-8 BOM stripping, required fields, enum normalization (`criticality` blank→`UNKNOWN`, `severity`), calendar date validation (`YYYY-MM-DD`), non-negative `run_count`. | Valid rows accepted; malformed rows rejected with exact `docs/data-contract.md` v0.3 error codes. | Oracle passed (`12/12`). ABAP Unit ready. |
| `ZCCMC_UT_IMPORT_IDEMPOTENCY` (`IMP-I01`..`IMP-I10`) | Ordered 4-file import (`objects` → `usage` → `findings` → `dependencies`), repeat batch (`INSERTED` → `UNCHANGED`), `objects_corrected_batch.csv` (`UPDATED` with prior provenance retained in `ZCCMC_IMPROWRES`), `reset_synthetic_data` (`M1-D10-T01`), and `build_m2_evidence_for_obj` bridge. | Zero duplicate business keys; stable `ObjectUUID`; reproducible counts across consecutive resets. | Oracle passed (`10/10`). ABAP Unit ready. |
| `ZCCMC_UT_IMPORT_EDGE_CASES` (`IMP-E01`..`IMP-E10`) | `objects_empty.csv` (`EMPTY_FILE`), `objects_duplicate_keys.csv` (`DUPLICATE_KEY`), `usage_malformed_date.csv` (`INVALID_DATE`), `findings_unknown_object.csv` (`UNKNOWN_OBJECT`), `findings_quoted_fields.csv` (RFC 4180 quotes preserved), reverse import order rejection, and `1,000` / `10,000` scale fixtures. | Exact row/batch status and SHA-256 digest recorded in `ZCCMC_IMPBATCH` & `ZCCMC_IMPROWERR`; zero silent row loss. | Oracle passed (`10/10`). ABAP Unit ready. |

---

## 4. Member 3 — Workflow, Security & Audit Test Matrix (`ZCCMC_UT_DECISION_WORKFLOW` — 24 Tests, Days 1–11 Complete)

ABAP Unit class: `src/zccmc_test/zccmc_ut_decision_workflow.clas.abap` testing `src/zccmc_rap/zccmc_cl_decision_workflow.clas.abap`.  
Reference oracle: `tools/m3_workflow_oracle.py` and `docs/m3-golden-workflow-results.md` (352 state×action×role combinations + 24 unit tests `WF-T01`..`WF-T24` passed).