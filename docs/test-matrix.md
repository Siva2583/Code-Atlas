## Rules: paper tests vs sample fixtures

All sample data is DEMO / SYNTHETIC.

| Test | Expected | Fixture in sample-synthetic | Status |
|---|---|---|---|
| T1 run 0, 12-month window, LOW, 0 findings loaded, no caller | RETIRE_CANDIDATE | none | GAP |
| T2 same as T1, 11-month window | MANUAL_REVIEW | ZMM_STOCK_ALERT is a similar case (window about 2 months, MEDIUM) but not the 11-month boundary | PARTIAL |
| T3 same as T1, called by HIGH object | MANUAL_REVIEW | none (the two dependencies point at objects with run_count > 0) | GAP |
| T4 HIGH, 12 months, run > 0, 0 findings | KEEP_ADAPT | none (ZSD_OPEN_ORDERS_RPT has 2 HIGH, ZSD_CUST_CREDIT_CHECK has 1 HIGH) | GAP |
| T5 same as T4 but one HIGH finding | MANUAL_REVIEW | ZSD_CUST_CREDIT_CHECK (F007). ZSD_OPEN_ORDERS_RPT covers 2 HIGH | COVERED |
| T6 MEDIUM, run 15210, one LOW finding | KEEP_ADAPT | ZCL_PRICING_HELPER (F008) | COVERED |
| T7 criticality UNKNOWN, rest complete | MANUAL_REVIEW | ZCL_INVOICE_UTIL, ZHR_PAYROLL_ADJ (neither has findings rows, so "complete" depends on the findings-loaded decision) | PARTIAL |
| T8 no usage row | MANUAL_REVIEW | ZFI_OLD_LEDGER_EXPORT | COVERED |
| T9 two rules, same priority, different outcomes | MANUAL_REVIEW | rule configuration in the unit test, not CSV | TEST SETUP |
| T10 run 0 but last_executed set | MANUAL_REVIEW | none | GAP |
| Stale evidence (evidence_as_of older than 30 days) | MANUAL_REVIEW | none (all rows have evidence_as_of 2026-10-13) | GAP |
| Reverse contradiction (run > 0, last_executed empty); period_end < period_start | MANUAL_REVIEW | none | GAP |

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