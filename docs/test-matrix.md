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
Running everything: python tools/m2_rules_oracle.py (records in docs/m2-golden-results.md); ABAP Unit in ADT with Ctrl+Shift+F10 on class ZCCMC_UT_RULE_ENGINE.

---

# Test Matrix — Member 1 import scope through Day 8

**Status:** expected behaviors below are the Member 1 candidate oracle in docs/data-contract.md. Only offline fixture structure is runnable from a normal checkout. ABAP Unit and SAP import results must be recorded from the assigned ADT tenant; they are not inferred from a CSV parse.

## Day 1–2: baseline and contract

| ID | Scenario | Expected result | Evidence / state |
|---|---|---|---|
| M1-D01-01 | Compare each of four original template headers with v0.1 contract. | Exact ordered match. | Verified against branch head 3006fb0. |
| M1-D01-02 | Inspect table, view, importer and ABAP Unit contents. | Record fields, keys, activation and entry point. | Files are 0 bytes; SAP activation/access result pending. |
| M1-D02-01 | Compare candidate v0.2 headers with all templates. | Exact ordered match including objects.findings_as_of. | Run tools/validate_import_fixtures.py after checkout; shared sign-off pending. |
| M1-D02-02 | Verify every named edge fixture has an explicit result. | See M1-D04-01 through M1-D04-06. | Candidate result codes are in docs/import-design.md. |

Determinism: run all tests twice and with shuffled input order. Only
RecommendationRunID and RunTimestamp may differ.

---

# Test Matrix — Member 1 import scope through Day 8

**Status:** expected behaviors below are the Member 1 candidate oracle in docs/data-contract.md. Only offline fixture structure is runnable from a normal checkout. ABAP Unit and SAP import results must be recorded from the assigned ADT tenant; they are not inferred from a CSV parse.

## Day 1–2: baseline and contract

| ID | Scenario | Expected result | Evidence / state |
|---|---|---|---|
| M1-D01-01 | Compare each of four original template headers with v0.1 contract. | Exact ordered match. | Verified against branch head 3006fb0. |
| M1-D01-02 | Inspect table, view, importer and ABAP Unit contents. | Record fields, keys, activation and entry point. | Files are 0 bytes; SAP activation/access result pending. |
| M1-D02-01 | Compare candidate v0.2 headers with all templates. | Exact ordered match including objects.findings_as_of. | Run tools/validate_import_fixtures.py after checkout; shared sign-off pending. |
| M1-D02-02 | Verify every named edge fixture has an explicit result. | See M1-D04-01 through M1-D04-06. | Candidate result codes are in docs/import-design.md. |

## Day 3–6: persistence and loader behavior

| ID | Scenario | Expected result | State |
|---|---|---|---|
| M1-D03-01 | Activate each agreed table and CDS; insert/read one synthetic row per entity. | All activate and fields/keys match the signed contract. | Not run; empty repository source and tenant evidence required. |
| M1-D04-01 | Parse four template headers, RFC 4180 quotes, escaped quotes, BOM and line endings. | Correct typed fields, no header drift or data loss. | Fixture coverage prepared; ABAP parser/Unit test absent. |
| M1-D04-02 | Header-only objects_empty.csv. | File-level EMPTY_FILE, zero business writes. | Fixture prepared; SAP loader not run. |
| M1-D04-03 | Two rows with one repeated object key. | Both REJECTED / DUPLICATE_KEY, neither applied. | Fixture prepared; SAP loader not run. |
| M1-D04-04 | usage_malformed_date.csv. | Row REJECTED / INVALID_DATE naming the field. | Fixture prepared; SAP loader not run. |
| M1-D04-05 | findings_unknown_object.csv. | Row REJECTED / UNKNOWN_OBJECT. | Fixture prepared; SAP loader not run. |
| M1-D04-06 | Quoted comma and escaped quote in finding message. | One accepted parse; message preserved exactly. | Fixture prepared; ABAP parser not run. |
| M1-D05-01 | Import a valid object file twice. | First INSERTED; repeat UNCHANGED, new batch/provenance retained. | Importer and ABAP Unit absent. |
| M1-D05-02 | Re-import objects_corrected_batch.csv. | Same key is UPDATED; prior batch evidence remains. | Fixture prepared; persistence not run. |
| M1-D06-01 | Malformed, unknown, duplicate, empty and corrected batches. | Counts reconcile; accepted and rejected rows retain provenance; previous batches remain. | Data model and importer not implemented/activated. |

## Day 7–8: integration and scale

| ID | Scenario | Expected result | Evidence / state |
|---|---|---|---|
| M1-D07-01 | Import objects, usage, findings, dependencies in order. | All in-scope references resolve; counts reconcile. | Needs SAP importer. |
| M1-D07-02 | Import dependent files before objects, then load objects. | Dependents are rejected UNKNOWN_OBJECT and are not silently replayed; object state reflects only committed rows. | Candidate policy; needs SAP importer. |
| M1-D07-03 | Inject fatal persistence failure. | Current file's business writes roll back; batch is FAILED; no half-persisted file. | Needs tenant fault-injection method; not run. |
| M1-D08-01 | Parse 1,000-row and 10,000-row fixtures locally. | Exactly 1,000 / 10,000 unique rows; 101,121 / 1,010,121 bytes; offline parse 0.0036s / 0.0378s. | Passed with Python 3.12.14 on the Windows workspace, 2026-10-14. Python csv.reader only; not an ABAP/SAP performance result. |
| M1-D08-02 | Repeat a performance file. | No duplicate business keys; importer reports UNCHANGED and retains another batch's provenance. | Needs SAP importer. |
| M1-D08-03 | Re-run all edge files through the activated importer. | Outcomes match M1-D04; accepted + rejected equals parsed for every file. | Not run; tenant and implementation required. |

Rules determinism, RAP authorization/stale-update and Fiori empty/error/filter tests remain owned by Members 2, 3 and 4 respectively. This matrix does not mark their tests passed.