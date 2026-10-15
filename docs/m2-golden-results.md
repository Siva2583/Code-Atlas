# Member 2 — Golden Results and Regression Record

**Scope:** expected recommendation for each of the 7 DEMO / SYNTHETIC sample objects in `data/sample-synthetic/` (data-contract candidate v0.2, `findings_as_of` = 2026-10-13 on every object), evaluation date 2026-10-14, seed rule set from `docs/rules-spec.md` section 5 (12 months, 30 days, 1 HIGH finding; all illustrative).

**What this record proves and does not prove.** The run below is of `tools/m2_rules_oracle.py`, an independent Python reference model of the written rules. It shows that the written rules, applied to the real CSV files, give the table below, that two clean runs are identical and that 200 random row orders of all four files and 20 shuffles of the rule rows per scenario change nothing. It does **not** show that `zccmc_cl_rule_engine` (ABAP) behaves the same: that class has not been compiled, activated or run. The ABAP Unit class `zccmc_ut_rule_engine` carries the same expected values and must be run in ADT before the engine is called tested. A mutation check was also made on the oracle (changing the 12-month threshold, the 30-day threshold or the R60 outcome makes it fail), so a pass is not vacuous.

**Inbound callers used:** ZCL_PRICING_HELPER is called by ZSD_OPEN_ORDERS_RPT (HIGH); ZCL_INVOICE_UTIL is called by ZSD_CUST_CREDIT_CHECK (HIGH). Neither changes the result because both objects are used.

## Golden table

| Object | RecommendedStrategy | MatchedRuleIDs | MissingEvidence |
|---|---|---|---|
| ZCL_INVOICE_UTIL | MANUAL_REVIEW | R10, R60 | CRITICALITY_UNKNOWN |
| ZCL_PRICING_HELPER | KEEP_ADAPT | R60 | - |
| ZSD_CUST_CREDIT_CHECK | MANUAL_REVIEW | R30 | - |
| ZFI_OLD_LEDGER_EXPORT | MANUAL_REVIEW | R10 | NO_USAGE_FACT |
| ZHR_PAYROLL_ADJ | MANUAL_REVIEW | R10, R60 | CRITICALITY_UNKNOWN |
| ZMM_STOCK_ALERT | MANUAL_REVIEW | R10 | WINDOW_TOO_SHORT |
| ZSD_OPEN_ORDERS_RPT | MANUAL_REVIEW | R30 | - |

Why each result (rule IDs from rules-spec section 5):
- ZSD_OPEN_ORDERS_RPT, ZSD_CUST_CREDIT_CHECK: used with at least one HIGH finding, so R30 (a human must assess impact).
- ZCL_PRICING_HELPER: used, only a LOW finding, so R60 KEEP_ADAPT.
- ZFI_OLD_LEDGER_EXPORT: no usage row. No data is not zero usage, so MANUAL_REVIEW.
- ZMM_STOCK_ALERT: no runs but a window of only 2 whole months, so it cannot be a retirement candidate.
- ZCL_INVOICE_UTIL, ZHR_PAYROLL_ADJ: criticality UNKNOWN is missing evidence. R60 also matches but R10 has the better priority.

Result counts: MANUAL_REVIEW 6, KEEP_ADAPT 1. Not reachable with this data: RETIRE_CANDIDATE, REWRITE_RAP, SIDE_BY_SIDE_BTP (see rules-spec section 6).

## Portfolio Analytics Golden Summary (Day 6 — `M2-D06-T01`)

Computed by `zccmc_cl_portfolio_analytics=>compute_summary` (and verified by `tools/m2_rules_oracle.py`) across the 7 synthetic sample objects:

| Metric ID | Metric | Expected Value |
|---|---|---|
| `M-01` | Total objects evaluated in latest run (`total_objects`) | `7` |
| `M-02` | Objects per `RecommendedStrategy` (`by_strategy`) | `MANUAL_REVIEW`: `6`, `KEEP_ADAPT`: `1`, `RETIRE_CANDIDATE`: `0`, `REWRITE_RAP`: `0`, `SIDE_BY_SIDE_BTP`: `0` |
| `M-03` | Objects with complete vs. missing evidence | Complete: `3` (`ZSD_OPEN_ORDERS_RPT`, `ZCL_PRICING_HELPER`, `ZSD_CUST_CREDIT_CHECK`); Missing: `4` |
| `M-03` Breakdown | Objects by `MissingEvidence` reason code (`by_missing_reason`) | `CRITICALITY_UNKNOWN`: `2`, `NO_USAGE_FACT`: `1`, `WINDOW_TOO_SHORT`: `1` |
| Filter: `package_name = 'ZSD_PRICING'` | Filtered subset reconciliation | `total_objects`: `1` (`ZCL_PRICING_HELPER`), `KEEP_ADAPT`: `1`, `objects_with_missing_evidence`: `0` |
| Filter: `criticality = 'HIGH'` | Filtered subset reconciliation | `total_objects`: `2` (`ZSD_OPEN_ORDERS_RPT`, `ZSD_CUST_CREDIT_CHECK`), `MANUAL_REVIEW`: `2`, `objects_with_missing_evidence`: `0` |
| Empty portfolio (`[]`) | Zero-state behavior | `total_objects`: `0`, all 5 strategy counts `0`, `by_missing_reason` empty |
| 1:N Join Deduplication | Repeat rows for same object key (`p_items * 5`) | Identical to unjoined 7-object summary (`total_objects` remains `7`, no double counting) |

## Run record (copied from the tool output)

Command: `python tools/m2_rules_oracle.py --report out.md` from the repository root, 2026-10-14.

```text
Evaluation date 2026-10-14; python 3.12.3; DEMO / SYNTHETIC data
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
