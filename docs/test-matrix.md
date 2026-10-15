## Rules : paper tests, fixtures and test status

All sample data is DEMO / SYNTHETIC. Evaluation date for all expected values: 2026-10-14.
Status legend. "Oracle" = tools/m2_rules_oracle.py, a Python reference model that passed (not the product). "ABAP Unit" = src/zccmc_test/zccmc_ut_rule_engine.clas.abap, written but NOT compiled and NOT run: the ADT tenant was not available.

| Test | Expected | Sample CSV fixture (data-contract v0.2) | ABAP Unit method | Status |
|---|---|---|---|---|
| T1 run 0, 12-month window, LOW, findings coverage known and none, no caller | RETIRE_CANDIDATE, matched R20 | none: GAP (request to Member 1) | T01 | In-code data. Oracle passed. ABAP Unit not run. |
| T2 same as T1 with an 11-month window | MANUAL_REVIEW, WINDOW_TOO_SHORT | ZMM_STOCK_ALERT is a short-window case (2 months), not the 11-month boundary | T02, T23 | In-code data. Oracle passed. ABAP Unit not run. |
| T3 same as T1, called by a HIGH object | MANUAL_REVIEW, NO_RULE_MATCH | none: GAP (the 2 dependencies point at used objects) | T03 | In-code data. Oracle passed. ABAP Unit not run. |
| T4 HIGH, 12 months, used, findings coverage known and none | KEEP_ADAPT, R60 | none: GAP (the HIGH objects have 2 and 1 HIGH findings) | T04 | In-code data. Oracle passed. ABAP Unit not run. |
| T5 same as T4 with one HIGH finding | MANUAL_REVIEW, R30 | ZSD_CUST_CREDIT_CHECK, ZSD_OPEN_ORDERS_RPT | T05, T27 | Covered by CSV and in-code. Oracle passed. ABAP Unit not run. |
| T6 MEDIUM, 15210 runs, one LOW finding | KEEP_ADAPT, R60 | ZCL_PRICING_HELPER | T06, T27 | Covered. Oracle passed. ABAP Unit not run. |
| T7 criticality UNKNOWN, rest complete | MANUAL_REVIEW, CRITICALITY_UNKNOWN, matched R10 and R60 | ZCL_INVOICE_UTIL, ZHR_PAYROLL_ADJ (now covered: findings_as_of is set on both) | T07, T27 | Covered. Oracle passed. ABAP Unit not run. |
| T8 no usage row | MANUAL_REVIEW, NO_USAGE_FACT | ZFI_OLD_LEDGER_EXPORT | T08, T27 | Covered. Oracle passed. ABAP Unit not run. |
| T9 two rules, same priority, different outcomes | MANUAL_REVIEW, RULE_CONFLICT, both rule IDs matched | rule configuration, not CSV | T09, T17 (same outcome is no conflict) | Test rule set in code. Oracle passed. ABAP Unit not run. |
| T10 run 0 but last_executed set | MANUAL_REVIEW, ZERO_RUNS_WITH_LAST_EXECUTED | none: GAP | T10 | In-code data. Oracle passed. ABAP Unit not run. |
| Run > 0 but last_executed empty | MANUAL_REVIEW, RUNS_WITHOUT_LAST_EXECUTED | none: GAP | T11 | In-code data. Oracle passed. ABAP Unit not run. |
| period_end before period_start | MANUAL_REVIEW, PERIOD_END_BEFORE_START only | none: GAP | T12 | In-code data. Oracle passed. ABAP Unit not run. |
| Stale evidence: 30 days old is fresh, 31 days is stale | KEEP_ADAPT / MANUAL_REVIEW EVIDENCE_STALE | none: GAP (all evidence_as_of are 2026-10-13) | T13 | In-code data. Oracle passed. ABAP Unit not run. |
| findings_as_of blank | MANUAL_REVIEW, FINDINGS_NOT_LOADED | none (all 7 objects have it set) | T14 | In-code data. Oracle passed. ABAP Unit not run. |
| Several usage rows (proposed behavior, C1) | MANUAL_REVIEW, MULTIPLE_USAGE_FACTS | none | T15, T26 | Proposed. Oracle passed. ABAP Unit not run. |
| Unknown caller criticality (proposed behavior, C4) | MANUAL_REVIEW only on the retirement path | none | T16 | Proposed. Oracle passed. ABAP Unit not run. |
| No active rule matches; rule inactive | MANUAL_REVIEW, NO_RULE_MATCH | rule configuration | T18, T21 | Oracle passed. ABAP Unit not run. |
| R10 missing from the rule set, evidence problem | still MANUAL_REVIEW (safety invariant) | rule configuration | T19 | Oracle passed. ABAP Unit not run. |
| Rule with unknown condition code | MANUAL_REVIEW, UNKNOWN_CONDITION_CODE | rule configuration | T20 | Proposed. Oracle passed. ABAP Unit not run. |
| INFO, LOW, MEDIUM findings do not count as HIGH | KEEP_ADAPT, R60 | ZCL_PRICING_HELPER | T22 | Oracle passed. ABAP Unit not run. |
| Whole-month boundaries (12 / 11, month end, leap day) | see rules-spec section 11 | none | T23 | Oracle passed. ABAP Unit not run. |
| Result fields and explanation content | rule-set id and version, run id passed through, rule ID and evidence values in the text, run id never in the text | none | T24 | Oracle does not render explanation text. ABAP Unit not run. |
| Determinism: two runs, only the run id differs | identical | all 7 sample objects | T25 | Oracle: 2 clean runs identical. ABAP Unit not run. |
| Permutation: row order of findings, callers, usage rows, rule rows | identical | all 4 sample files | T26 | Oracle: 200 random orders of all four files and 20 rule-order shuffles of 25 scenarios, 0 differences. ABAP Unit not run. |
| All 7 sample objects against the golden table | docs/m2-golden-results.md | objects, usage, findings, dependencies CSVs | T27 | Oracle passed against the CSV files. ABAP T27 uses in-code copies of the same values. Not run. |

Open decisions that can change these expectations: docs/m2-contract-review.md C1 to C14.
Not tested: REWRITE_RAP and SIDE_BY_SIDE_BTP (no source data), portfolio metrics (none agreed), rule-set persistence and immutability (no entity yet).
Running everything: python tools/m2_rules_oracle.py (records in docs/m2-golden-results.md); ABAP Unit in ADT with Ctrl+Shift+F10 on classes ZCCMC_UT_RULE_ENGINE and ZCCMC_UT_PORTFOLIO_ANALYTICS.

## Portfolio Analytics : unit tests and reconciliation status (Member 2 — Day 6 `M2-D06-T01`)

ABAP Unit class: `src/zccmc_test/zccmc_ut_portfolio_analytics.clas.abap` testing `src/zccmc_core/zccmc_cl_portfolio_analytics.clas.abap`.

| Test | Expected | Sample CSV fixture | ABAP Unit method | Status |
|---|---|---|---|---|
| PA-T01 Empty portfolio (`0` items) | `total_objects = 0`, all 5 strategy counts `0`, no missing reasons | empty list | `T01` | Oracle passed. ABAP Unit written, pending ADT run. |
| PA-T02 Full 7-object sample reconciliation | `M-01 = 7`; `M-02`: `MANUAL_REVIEW = 6`, `KEEP_ADAPT = 1`; `M-03 = 4` (`CRITICALITY_UNKNOWN = 2`, `NO_USAGE_FACT = 1`, `WINDOW_TOO_SHORT = 1`) | all 7 sample objects | `T02` | Oracle passed. ABAP Unit written, pending ADT run. |
| PA-T03 Filter by `package_name` & `criticality` | `ZSD_REPORTS` → `1 MANUAL_REVIEW`; `ZSD_PRICING` → `1 KEEP_ADAPT`; `criticality = HIGH` → `2 MANUAL_REVIEW` | `objects.csv` packages | `T03` | Oracle passed. ABAP Unit written, pending ADT run. |
| PA-T04 Filter by `source_system` | `DEMO_SYS` → `7`; `NON_EXISTENT_SYS` → `0` | `objects.csv` | `T04` | Oracle passed. ABAP Unit written, pending ADT run. |
| PA-T05 Filter by `strategy` and `only_missing_evidence` | `KEEP_ADAPT` → `1`; `only_missing_evidence = true` → `4` | all 7 sample objects | `T05` | Oracle passed. ABAP Unit written, pending ADT run. |
| PA-T06 1:N join duplicate row & reason-code deduplication | 6 repeated rows for 1 object still yield `total_objects = 1` and `reason_count = 1` | simulated join rows | `T06` | Oracle passed. ABAP Unit written, pending ADT run. |
| PA-T07 Multi-run deduplication (latest run wins) | `RUN-0002` supersedes `RUN-0001` for the same object key | in-code 2-run fixture | `T07` | Oracle passed. ABAP Unit written, pending ADT run. |
| PA-T08 Input row-order determinism | Reversed item table produces identical `ty_summary` | all 7 sample objects | `T08` | Oracle passed. ABAP Unit written, pending ADT run. |


---

---

# Test Matrix — Member 1 Persistence, CSV Import & Provenance (`M1-D01-T01` .. `M1-D11-T01`)

**Status:** All 32 unit-test scenarios (`IMP-V01..V12`, `IMP-I01..I10`, `IMP-E01..E10`), 6 edge-case fixtures, 200 row-order permutations, 1k/10k scale runs, and Day-10 clean reset reproducibility are implemented in `src/zccmc_test/zccmc_ut_import_*.clas.abap` and **PASSED** via `tools/m1_import_oracle.py` and `tools/validate_import_fixtures.py` (recorded in `docs/m1-golden-import-results.md`). Live SAP ADT execution awaits non-`$TMP` package provisioning (`docs/feasibility-note.md` F-02).

## 1. CSV Parser & Validator Suite (`src/zccmc_test/zccmc_ut_import_validator.clas.abap`)

| Test ID | Scenario | Expected Result | Fixture / Input | ABAP Unit Method | Status |
|---|---|---|---|---|---|
| `IMP-V01` | Parse and validate all 4 template headers (`objects`, `usage`, `findings`, `dependencies`) | Exact ordered match against contract v0.3 | `data/templates/*.csv` | `t01_four_template_headers_pass` | Oracle passed. ABAP Unit written, pending ADT run. |
| `IMP-V02` | Header mismatch (missing `findings_as_of` or wrong column order) | File rejected with `HEADER_MISMATCH` | In-code header fixture | `t02_header_mismatch_rejected` | Oracle passed. ABAP Unit written, pending ADT run. |
| `IMP-V03` | Header-only file (`objects_empty.csv`) | File rejected with `EMPTY_FILE`, `0` valid rows | `edge-cases/objects_empty.csv` | `t03_empty_file_rejected` | Oracle passed. ABAP Unit written, pending ADT run. |
| `IMP-V04` | RFC 4180 quoted field with comma and escaped quotes (`""`) | Parsed as 1 field: `DEMO quoted, comma and "quote" fixture` | `edge-cases/findings_quoted_fields.csv` | `t04_rfc4180_quotes_and_commas` | Oracle passed. ABAP Unit written, pending ADT run. |
| `IMP-V05` | Leading UTF-8 BOM (`U+FEFF`) and `CRLF` record endings | BOM stripped, records parsed without header drift | In-code BOM + CRLF fixture | `t05_utf8_bom_and_crlf_handled` | Oracle passed. ABAP Unit written, pending ADT run. |
| `IMP-V06` | Unclosed quote or unescaped quote mid-field | Parse fails with `MALFORMED_CSV` and 1-based record number | In-code malformed CSV | `t06_malformed_csv_unclosed_q` | Oracle passed. ABAP Unit written, pending ADT run. |
| `IMP-V07` | Data row with too few or too many columns | Row rejected with `COLUMN_COUNT_MISMATCH` | In-code 6-col dependency row | `t07_column_count_mismatch` | Oracle passed. ABAP Unit written, pending ADT run. |
| `IMP-V08` | Intra-file duplicate business key (`objects_duplicate_keys.csv`) | **Both** rows (`record 2` & `3`) rejected with `DUPLICATE_KEY` | `edge-cases/objects_duplicate_keys.csv` | `t08_duplicate_keys_both_reject` | Oracle passed. ABAP Unit written, pending ADT run. |
| `IMP-V09` | Calendar date validation (`2026-02-30`, `2026-02-29` vs. leap `2024-02-29`) | Non-calendar dates rejected with `INVALID_DATE` naming field | `edge-cases/usage_malformed_date.csv` | `t09_malformed_and_calendar_dt` | Oracle passed. ABAP Unit written, pending ADT run. |
| `IMP-V10` | Enum & blank rules (blank `criticality` -> `UNKNOWN`; blank `severity` -> error) | Blank `criticality` = `UNKNOWN`; bad enum = `INVALID_ENUM`; blank `severity` = `MISSING_REQUIRED_FIELD` | In-code enum fixtures | `t10_enum_and_criticality_rules` | Oracle passed. ABAP Unit written, pending ADT run. |
| `IMP-V11` | Integer & negative `run_count` validation | `< 0` -> `NEGATIVE_RUN_COUNT`; decimal/alpha -> `INVALID_INTEGER` | In-code usage fixtures | `t11_integer_and_neg_run_count` | Oracle passed. ABAP Unit written, pending ADT run. |
| `IMP-V12` | Key trimming and uppercase normalization | Keys & enums uppercased; free-text `description`/`message` case preserved | In-code mixed-case row | `t12_key_normalization_trimming` | Oracle passed. ABAP Unit written, pending ADT run. |

## 2. Idempotency, Corrections, Provenance & Cross-Team Integration Suite (`src/zccmc_test/zccmc_ut_import_idempotency.clas.abap`)

| Test ID | Scenario | Expected Result | Fixture / Input | ABAP Unit Method | Status |
|---|---|---|---|---|---|
| `IMP-I01` | Clean 4-file baseline import in frozen order (`objects` -> `usage` -> `findings` -> `dependencies`) | `COMMITTED`: `7` objects, `6` usages, `8` findings, `2` dependencies `INSERTED`; `0` errors | `data/sample-synthetic/*.csv` | `t01_clean_four_file_baseline` | Oracle passed. ABAP Unit written, pending ADT run. |
| `IMP-I02` | Immediate repeat import of all 4 baseline files | `COMMITTED`: `7`, `6`, `8`, `2` `UNCHANGED`; `0` duplicates; `ObjectUUID`s preserved; new `BatchUUID`s recorded | `data/sample-synthetic/*.csv` | `t02_repeat_import_unchanged` | Oracle passed. ABAP Unit written, pending ADT run. |
| `IMP-I03` | Corrected object batch (`objects_corrected_batch.csv`) | `COMMITTED`: `1 UPDATED` (`ZSD_OPEN_ORDERS_RPT` description updated in place), `ObjectUUID` preserved, total objects = `7` | `edge-cases/objects_corrected_batch.csv` | `t03_corrected_batch_in_place` | Oracle passed. ABAP Unit written, pending ADT run. |
| `IMP-I04` | Replay baseline `objects.csv` after corrected batch | `COMMITTED`: `1 UPDATED` (reverted) + `6 UNCHANGED` = `7` accepted | `data/sample-synthetic/objects.csv` | `t04_replay_baseline_after_corr` | Oracle passed. ABAP Unit written, pending ADT run. |
| `IMP-I05` | Dependent entity (`usage`) upsert idempotency | Modified `run_count` on existing usage key yields `1 UPDATED`, total usages = `6` | In-code usage update | `t05_dependent_upsert_semantics` | Oracle passed. ABAP Unit written, pending ADT run. |
| `IMP-I06` | Day-10 clean reset (`reset_synthetic_store`) and two consecutive clean runs | Both runs produce identical counts (`7`, `6`, `8`, `2`), business keys, and `row_sha256` digests | `data/sample-synthetic/*.csv` | `t06_clean_reset_reproducible` | Oracle passed. ABAP Unit written, pending ADT run. |
| `IMP-I07` | Input row-order permutation across all 4 files (200 random shuffles in oracle) | Identical persisted entity state and `row_sha256` digests | Permuted `sample-synthetic/*.csv` | `t07_row_order_permutation_det` | Oracle passed (200/200). ABAP Unit written, pending ADT run. |
| `IMP-I08` | M1 -> M2 bridge (`build_m2_evidence_for_object` -> `zccmc_cl_rule_engine=>evaluate`) | Evaluates persisted M1 data to exact M2 golden outcomes (`6 MANUAL_REVIEW`, `1 KEEP_ADAPT`) | `data/sample-synthetic/*.csv` | `t08_m1_to_m2_evidence_bridge` | Oracle passed. ABAP Unit written, pending ADT run. |
| `IMP-I09` | M1 -> M3 `ObjectUUID` foreign-key stability across re-imports | `ObjectUUID` linked by M3 `ZCCMC_DECISION` remains unchanged after M1 repeat and corrected imports | `objects.csv` + `objects_corrected_batch.csv` | `t09_m1_to_m3_uuid_stability` | Oracle passed. ABAP Unit written, pending ADT run. |
| `IMP-I10` | Append-only provenance ledger (`batches`, `row_results`, `row_errors`) | Prior batches and row results remain intact after subsequent imports | Multi-batch sequence | `t10_append_only_provenance` | Oracle passed. ABAP Unit written, pending ADT run. |

## 3. Edge Cases, Reference Ordering, Rollback & Scale Suite (`src/zccmc_test/zccmc_ut_import_edge_cases.clas.abap`)

| Test ID | Scenario | Expected Result | Fixture / Input | ABAP Unit Method | Status |
|---|---|---|---|---|---|
| `IMP-E01` | Import `objects_empty.csv` into orchestrator | Batch `FAILED` with `EMPTY_FILE`; `0` objects written | `edge-cases/objects_empty.csv` | `t01_edge_objects_empty` | Oracle passed. ABAP Unit written, pending ADT run. |
| `IMP-E02` | Import `objects_duplicate_keys.csv` into orchestrator | Batch `FAILED`; `parsed = 2`, `accepted = 0`, `rejected = 2` (`DUPLICATE_KEY` on both rows) | `edge-cases/objects_duplicate_keys.csv` | `t02_edge_objects_duplicate_keys` | Oracle passed. ABAP Unit written, pending ADT run. |
| `IMP-E03` | Import `usage_malformed_date.csv` after baseline objects | Batch `FAILED`; `1 REJECTED` with `INVALID_DATE` on `period_start` (`2026-02-30`) | `edge-cases/usage_malformed_date.csv` | `t03_edge_usage_malformed_date` | Oracle passed. ABAP Unit written, pending ADT run. |
| `IMP-E04` | Import `findings_unknown_object.csv` after baseline objects | Batch `FAILED`; `1 REJECTED` with `UNKNOWN_OBJECT` on `object_name`; zero orphan findings | `edge-cases/findings_unknown_object.csv` | `t04_edge_findings_unknown_obj` | Oracle passed. ABAP Unit written, pending ADT run. |
| `IMP-E05` | Import `findings_quoted_fields.csv` after baseline objects | Batch `COMMITTED`; `1 INSERTED` with comma and escaped quotes preserved | `edge-cases/findings_quoted_fields.csv` | `t05_edge_findings_quoted_fields` | Oracle passed. ABAP Unit written, pending ADT run. |
| `IMP-E06` | Reverse-order import (`usage`, `findings`, `dependencies` before `objects`) | All dependent rows rejected with `UNKNOWN_OBJECT`; loading `objects` later does **not** silently replay them | `data/sample-synthetic/*.csv` (reversed) | `t06_reverse_order_no_replay` | Oracle passed. ABAP Unit written, pending ADT run. |
| `IMP-E07` | Partial-batch commit (1 valid row + 1 invalid row in same file) | Batch `COMMITTED` (`accepted = 1`, `rejected = 1`); valid row persisted, invalid row recorded in `row_errors` | In-code mixed batch | `t07_partial_batch_valid_invalid` | Oracle passed. ABAP Unit written, pending ADT run. |
| `IMP-E08` | Unprovisioned `source_system` on object row | Row rejected with `UNKNOWN_SOURCE_SYSTEM`; zero objects created | In-code `UNPROVISIONED_SYS` | `t08_unknown_source_system_rej` | Oracle passed. ABAP Unit written, pending ADT run. |
| `IMP-E09` | Fatal persistence failure (`simulate_persistence_failure = abap_true`) | File business writes rolled back atomically; batch `FAILED` with `PERSISTENCE_FAILURE`; no half-batch remains | Fault-injected object batch | `t09_fatal_persistence_rollback` | Oracle passed. ABAP Unit written, pending ADT run. |
| `IMP-E10` | Bulk scale (`1,000` and `10,000` rows) & repeat-import idempotency | `1,000` and `10,000` rows `INSERTED` on pass 1 and `UNCHANGED` on pass 2; zero truncation or duplicate keys | `perf/objects_1000.csv`, `perf/objects_10000.csv` | `t10_scale_bulk_and_repeat` | Oracle passed (`docs/m1-golden-import-results.md`). ABAP Unit written, pending ADT run. |

---

# Test Matrix — Member 3 Workflow, Authorization, SoD & Audit (`M3-D01-T01` .. `M3-D11-T01`)

ABAP Unit class: `src/zccmc_test/zccmc_ut_decision_workflow.clas.abap` (`t01`..`t24`, `WF-T01`..`WF-T24`) testing `src/zccmc_rap/zccmc_cl_decision_workflow.clas.abap`. All 24 unit tests and 352 transition matrix combinations passed in `tools/m3_workflow_oracle.py` (see `docs/m3-golden-workflow-results.md` and `docs/m3-day1-day11-status.md`).
