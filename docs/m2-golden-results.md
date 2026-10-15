```text
Evaluation date 2026-10-14; python 3.11.2; DEMO / SYNTHETIC data
whole-month boundary cases: 7 checked
paper tests and unit-test scenarios: 25 checked
sample objects vs golden table: 7 objects
determinism: two clean runs identical = True
permutation: 200 random row orders of all four files, differing = 0
permutation: rule row order shuffled 20x for 25 scenarios, differing = 0
perf fixtures: 1,000 and 10,000 objects evaluated (no usage loaded: all MANUAL_REVIEW, none silently lost)
portfolio analytics: M-01=7, M-02 (MANUAL_REVIEW=6, KEEP_ADAPT=1), M-03=4, filters, empty & join-dedup checked

RESULT: ALL CHECKS PASSED
```

| Object | RecommendedStrategy | MatchedRuleIDs | MissingEvidence |
|---|---|---|---|
| ZCL_INVOICE_UTIL | MANUAL_REVIEW | R10, R60 | CRITICALITY_UNKNOWN |
| ZCL_PRICING_HELPER | KEEP_ADAPT | R60 | - |
| ZSD_CUST_CREDIT_CHECK | MANUAL_REVIEW | R30 | - |
| ZFI_OLD_LEDGER_EXPORT | MANUAL_REVIEW | R10 | NO_USAGE_FACT |
| ZHR_PAYROLL_ADJ | MANUAL_REVIEW | R10, R60 | CRITICALITY_UNKNOWN |
| ZMM_STOCK_ALERT | MANUAL_REVIEW | R10 | WINDOW_TOO_SHORT |
| ZSD_OPEN_ORDERS_RPT | MANUAL_REVIEW | R30 | - |
