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