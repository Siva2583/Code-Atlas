# Rules & Portfolio Analytics Specification — Version 1.0.0 (Frozen Release v1)

**Owner:** Member 2 — Rules & Analytics  
**Status:** **FROZEN v1.0.0** (`M2-D09-T01` / `M2-D10-T01` / `M2-D11-T01`), aligned with Member 1's Day 1–11 Data & Import Contract (`docs/data-contract.md` v0.3, `docs/import-design.md` v0.3, `docs/m1-contract-review.md`, `PR #31`) and Member 3's Workflow Contract (`docs/state-transitions.md` v0.3, `docs/m3-contract-review.md`).  
**Rule-Set Identifier:** `ZCCMC_DEMO` | **Rule-Set Version:** `1.0.0`  
**Implementation Classes:** `src/zccmc_core/zccmc_cl_rule_engine.clas.abap`, `src/zccmc_core/zccmc_cl_portfolio_analytics.clas.abap`  
**Test Classes & Oracle:** `src/zccmc_test/zccmc_ut_rule_engine.clas.abap` (31 tests), `src/zccmc_test/zccmc_ut_portfolio_analytics.clas.abap` (13 tests), `tools/m2_rules_oracle.py`

> **Project Demo Policy Notice (Not Official SAP Migration Guidance):**  
> All sample data in this repository is **DEMO / SYNTHETIC**. Every rule condition, priority number, window threshold (`12` whole calendar months), freshness window (`30` days), and finding count threshold (`1` `HIGH` finding) in `ZCCMC_DEMO` v1.0.0 is **project demonstration policy** and is configurable via `ty_ruleset-params` and `ty_ruleset-rules`. None of these values is hardcoded in the evaluation logic, and a qualified SAP migration/domain expert must validate rule parameters before any real customer use. This engine is a **deterministic rules engine**, not AI or machine learning.

---

## 1. The Five Canonical Outcomes

Every custom object evaluation returns exactly one of the five canonical `RecommendedStrategy` codes (`zccmc_cl_rule_engine=>c_outcome`):

| Outcome Code | Meaning | Reachable in v1 Synthetic CSV Contract? |
|---|---|---|
| `KEEP_ADAPT` | The object is actively used (`run_count > 0`), has complete/fresh evidence, and has zero `HIGH`-severity findings (`high_findings < high_finding_min_count`), so it can remain in the system with manageable adaptation. | **Yes (`R60`)** — e.g., `ZCL_PRICING_HELPER` |
| `REWRITE_RAP` | The object represents a transactional capability with high reuse and manageable dependencies suited for an ABAP Cloud / RAP re-implementation. | **Contract enum reserved; blocked on source field** (see Section 6) |
| `RETIRE_CANDIDATE` | The object has zero usage (`run_count = 0`) over a complete observation window of at least `12` whole calendar months, complete/fresh evidence, and no `HIGH`-criticality inbound caller. A human reviewer must still confirm with the business owner. | **Yes (`R20`)** — covered by `T01`, `T16` |
| `SIDE_BY_SIDE_BTP` | The capability has an external integration or released-API boundary suited for a side-by-side extension on SAP BTP. | **Contract enum reserved; blocked on source field** (see Section 6) |
| `MANUAL_REVIEW` | **Default safe outcome.** Applied whenever evidence is missing, incomplete, unknown, stale, or contradictory (`R10` + hard safety invariant), when active rules tie at the best priority with different outcomes (`RULE_CONFLICT`), when no active rule matches (`NO_RULE_MATCH`), or when an active object has `HIGH`-severity findings requiring human impact assessment (`R30`). | **Yes (`R10`, `R30`, fallback)** — 6 of 7 sample objects |

---

## 2. Configurable Rule Parameters (`ty_params`)

All thresholds are passed in `is_ruleset-params` (seeded by `zccmc_cl_rule_engine=>seed_ruleset` as project demo policy):

| Parameter Field | Seed Value (`v1.0.0`) | Purpose |
|---|---|---|
| `min_window_months` | `12` whole calendar months | Minimum observation window required to treat `run_count = 0` as complete usage coverage (`R20` / `WINDOW_TOO_SHORT`). |
| `max_evidence_age_days` | `30` days | Maximum age (`iv_evaluation_date - evidence_as_of`) before usage evidence is flagged `EVIDENCE_STALE`. Exactly `30` days is fresh; `31` days is stale. |
| `high_finding_min_count` | `1` finding | Minimum number of `HIGH`-severity ATC/check findings that routes an actively used object to `MANUAL_REVIEW` (`R30`) instead of `KEEP_ADAPT` (`R60`). |

---

## 3. Missing, Unknown, or Stale Evidence Always Routes to `MANUAL_REVIEW`

If any of the following conditions holds during `assess_evidence`, the reason code is appended to `missing_evidence` in deterministic check order and the final outcome is forced to `MANUAL_REVIEW` (**hard safety invariant** enforced in `evaluate_object` regardless of whether rule `R10` is present or active):

| Check Order | Reason Code (`c_reason`) | Trigger Condition |
|---|---|---|
| 1 | `NO_USAGE_FACT` | `lines( is_evidence-usages ) = 0`. Absence of usage data is never treated as zero usage. |
| 2 | `MULTIPLE_USAGE_FACTS` | `lines( is_evidence-usages ) > 1`. When multiple usage periods exist for one object in `ZCCMC_USAGE` (`period_start + period_end + evidence_source`), the engine refuses to guess which period applies (`C1`). |
| 3 | `PERIOD_END_BEFORE_START` | `ls_usage-period_end < ls_usage-period_start`. Contradictory observation window; `window_months` is `0` and `WINDOW_TOO_SHORT` is suppressed to avoid redundant noise. |
| 4 | `WINDOW_TOO_SHORT` | `period_end >= period_start` and `whole_months_between( period_start, period_end ) < min_window_months` (`12`). |
| 5 | `EVIDENCE_STALE` | `ls_usage-evidence_as_of IS INITIAL` or `iv_evaluation_date - ls_usage-evidence_as_of > max_evidence_age_days` (`30`). |
| 6 | `ZERO_RUNS_WITH_LAST_EXECUTED` | Contradictory usage row: `run_count = 0` and `last_executed IS NOT INITIAL`. |
| 7 | `RUNS_WITHOUT_LAST_EXECUTED` | Contradictory usage row: `run_count > 0` and `last_executed IS INITIAL`. |
| 8 | `CRITICALITY_UNKNOWN` | `criticality` after trim/uppercase is anything other than `HIGH`, `MEDIUM`, or `LOW` (including blank or `UNKNOWN`). |
| 9 | `FINDINGS_NOT_LOADED` | `is_evidence-findings_as_of IS INITIAL`. Blank `findings_as_of` in `ZCCMC_CUSTOBJ` means findings scan coverage is unknown; zero findings is never inferred from an incomplete scan. |
| 10 | `CALLER_CRITICALITY_UNKNOWN` | Evaluated only on the retirement path (`usage_count = 1`, `run_count = 0`, `has_high_caller = abap_false`) when at least one inbound caller from `ZCCMC_DEPEND` has `UNKNOWN` criticality. Prevents retiring an unused object whose caller might be business-critical. |
| 11 | `UNKNOWN_CONDITION_CODE` | Any active rule in `is_ruleset-rules` contains a `condition_code` outside `c_condition`. The rule set is treated as invalid and routed safely to `MANUAL_REVIEW`. |

---

## 4. Rule Resolution, Precedence, Ties, and No-Match Fallbacks

When `missing_evidence` is empty after `assess_evidence` and rule evaluation, `resolve_matches` determines the outcome from `lt_matches` (sorted by `priority ASCENDING`, then `rule_id ASCENDING`):

1. **Single best priority or equal-priority agreement:** All matched active rules sharing the lowest priority number (`it_matches[ 1 ]-priority`) are inspected. If they all specify the **same** `outcome`, that outcome wins (`ev_strategy = lv_first_outcome`), and `it_matches[ 1 ]` (lowest `rule_id` alphabetically) provides the winning rule rationale.
2. **Equal-priority conflict (`RULE_CONFLICT`):** If two or more matched active rules share the lowest priority number with **different** outcomes, the engine never picks one arbitrarily. It returns `strategy = MANUAL_REVIEW`, appends `RULE_CONFLICT` to `missing_evidence`, and names all conflicting rule IDs in `explanation`.
3. **No matching rule (`NO_RULE_MATCH`):** If `lt_matches` is empty (for example, an unused object with a complete 12-month window that is called by a `HIGH`-criticality caller, blocking `R20`), the engine returns `strategy = MANUAL_REVIEW` and appends `NO_RULE_MATCH` to `missing_evidence`.

---

## 5. Frozen v1.0.0 Seed Rule Set (`ZCCMC_DEMO` / `1.0.0`) & Paper Test Matrix

### Seed Rules (`zccmc_cl_rule_engine=>seed_ruleset`)

A lower priority number has higher precedence:

| Rule ID | Priority | Active | Condition Code (`c_condition`) | Condition Semantics | Outcome | Rationale Text |
|---|---|---|---|---|---|---|
| `R10` | `10` | `abap_true` | `EVIDENCE_PROBLEM` | `it_missing IS NOT INITIAL` (any Section 3 missing, unknown, stale, or contradictory evidence) | `MANUAL_REVIEW` | `Evidence is missing, stale, unknown or contradictory; a human must decide.` |
| `R20` | `20` | `abap_true` | `NO_USE_COMPLETE_WINDOW` | `usage_count = 1 AND run_count = 0 AND window_valid = abap_true AND window_months >= 12 AND has_high_caller = abap_false` | `RETIRE_CANDIDATE` | `No runs over a complete observation window and no HIGH-criticality caller; retirement candidate, the owner must confirm.` |
| `R30` | `30` | `abap_true` | `USED_WITH_HIGH_FINDING` | `usage_count = 1 AND run_count > 0 AND high_findings >= 1` | `MANUAL_REVIEW` | `The object is used and has HIGH-severity findings; a human must assess the impact.` |
| `R60` | `60` | `abap_true` | `USED_WITHOUT_HIGH_FINDING` | `usage_count = 1 AND run_count > 0 AND high_findings < 1` | `KEEP_ADAPT` | `The object is used and has no HIGH-severity findings; keep and adapt.` |

*(Priority `40` for `REWRITE_RAP` and priority `50` for `SIDE_BY_SIDE_BTP` remain reserved until source CSV fields exist; see Section 6.)*

### Paper Test Cases (`T1`–`T10`)

| ID | Input Evidence Facts | Expected Strategy | Matched Rules | Missing / Fallback Codes | Verification Target |
|---|---|---|---|---|---|
| `T1` | `run_count = 0`, window `12` whole months (`2025-10-13`..`2026-10-13`), criticality `LOW`, `findings_as_of` set (`0` findings), no callers | `RETIRE_CANDIDATE` | `R20` | *(empty)* | Boundary: 12 whole months satisfies `R20` |
| `T2` | Same as `T1` with window `11` whole months (`2025-11-13`..`2026-10-13`) | `MANUAL_REVIEW` | `R10` | `WINDOW_TOO_SHORT` | Boundary: 11 months is incomplete coverage |
| `T3` | Same as `T1`, but called by a `HIGH`-criticality object | `MANUAL_REVIEW` | *(empty)* | `NO_RULE_MATCH` | `HIGH` caller blocks `R20`; safe no-match fallback |
| `T4` | `run_count = 2480`, criticality `HIGH`, `12`-month window, `findings_as_of` set (`0` findings) | `KEEP_ADAPT` | `R60` | *(empty)* | Boundary: `0` `HIGH` findings allows `KEEP_ADAPT` |
| `T5` | Same as `T4` with `1` `HIGH` finding | `MANUAL_REVIEW` | `R30` | *(empty)* | Boundary: `1` `HIGH` finding triggers `R30` |
| `T6` | `run_count = 15210`, criticality `MEDIUM`, `1` `LOW` finding | `KEEP_ADAPT` | `R60` | *(empty)* | `LOW`/`MEDIUM`/`INFO` findings do not trigger `R30` |
| `T7` | `criticality = UNKNOWN`, all other evidence complete (`100` runs, `0` findings) | `MANUAL_REVIEW` | `R10`, `R60` | `CRITICALITY_UNKNOWN` | `R10` (priority 10) overrides `R60` (priority 60) |
| `T8` | Zero usage rows (`usages` empty) | `MANUAL_REVIEW` | `R10` | `NO_USAGE_FACT` | Absence of usage row is never zero usage |
| `T9` | Active rule `R61` added at priority `60` with outcome `REWRITE_RAP` alongside `R60` (`KEEP_ADAPT`) | `MANUAL_REVIEW` | `R60`, `R61` | `RULE_CONFLICT` | Equal-priority tie with differing outcomes |
| `T10` | `run_count = 0` but `last_executed = 2025-09-25` | `MANUAL_REVIEW` | `R10`, `R20` | `ZERO_RUNS_WITH_LAST_EXECUTED` | Contradictory usage evidence overrides `R20` |

---

## 6. Rule-to-Field Traceability Map (`M2-D01-T01` / `M2-D09-T01` — Aligned with Member 1 Day 11)

Verified against Member 1's completed persistence tables (`src/zccmc_data/*.tabl.xml`), CDS interface views (`src/zccmc_data/zccmc_i_*.ddls.asddls`), orchestrator bridge (`zccmc_cl_import_orchestrator=>build_m2_evidence_for_obj`), and `docs/data-contract.md` (v0.3):

| Rule / Condition | Member 1 Table & CDS Source Field | In Data Contract v0.3? | Sample CSV Fixture / Unit Test Coverage |
|---|---|---|---|
| `R10`: `NO_USAGE_FACT` | `ZCCMC_USAGE` / `ZCCMC_I_UsageFact` row count `= 0` for `ObjectUUID` | Yes | `ZFI_OLD_LEDGER_EXPORT` (`objects.csv` without `usage.csv` row); `T08`, `T27` |
| `R10`: `MULTIPLE_USAGE_FACTS` | `ZCCMC_USAGE` / `ZCCMC_I_UsageFact` row count `> 1` for `ObjectUUID` | Yes (composite key `object + period_start + period_end + evidence_source`) | In-code fixture (`T15`, `T26`) |
| `R10`: `WINDOW_TOO_SHORT` | `ZCCMC_I_UsageFact.PeriodStart`, `PeriodEnd` | Yes | `ZMM_STOCK_ALERT` (`2` whole months: `2026-08-01`..`2026-10-13`); `T02`, `T23`, `T27` |
| `R10`: `CRITICALITY_UNKNOWN` | `ZCCMC_CUSTOBJ.CRITICALITY` / `ZCCMC_I_CustomObject.Criticality` | Yes (blank normalizes to `UNKNOWN` in `zccmc_cl_import_object_loader`) | `ZCL_INVOICE_UTIL`, `ZHR_PAYROLL_ADJ`; `T07`, `T27` |
| `R10`: `EVIDENCE_STALE` | `ZCCMC_I_UsageFact.EvidenceAsOf` vs. `iv_evaluation_date` | Yes (`iv_evaluation_date` supplied by caller) | In-code boundary fixtures (`30` days fresh vs. `31` days stale in `T13`) |
| `R10`: `FINDINGS_NOT_LOADED` | `ZCCMC_CUSTOBJ.FINDINGS_AS_OF` / `ZCCMC_I_CustomObject.FindingsAsOf` | Yes (`objects.csv` column 10 in v0.3) | In-code fixture (`T14`); all 7 sample objects have `2026-10-13` |
| `R10`: `ZERO_RUNS_WITH_LAST_EXECUTED` | `ZCCMC_I_UsageFact.RunCount = 0` & `LastExecuted` non-empty | Yes | In-code fixture (`T10`) |
| `R10`: `RUNS_WITHOUT_LAST_EXECUTED` | `ZCCMC_I_UsageFact.RunCount > 0` & `LastExecuted` empty | Yes | In-code fixture (`T11`) |
| `R10`: `PERIOD_END_BEFORE_START` | `ZCCMC_I_UsageFact.PeriodEnd < PeriodStart` | Yes | In-code fixture (`T12`) |
| `R10`: `CALLER_CRITICALITY_UNKNOWN` | `ZCCMC_DEPEND` / `ZCCMC_I_Dependency (ToObject)` joined to caller `ZCCMC_I_CustomObject.Criticality` | Yes (assembled by `zccmc_cl_import_orchestrator=>build_m2_evidence_for_obj`) | In-code fixture (`T16`) |
| `R20`: `NO_USE_COMPLETE_WINDOW` | `ZCCMC_I_UsageFact.RunCount = 0`, `window_months >= 12`, no `HIGH` caller | Yes | In-code fixtures (`T01`, `T16`) |
| `R30`: `USED_WITH_HIGH_FINDING` | `ZCCMC_I_UsageFact.RunCount > 0`, `ZCCMC_I_Finding.Severity = HIGH` count `>= 1` | Yes | `ZSD_OPEN_ORDERS_RPT` (`2` `HIGH`), `ZSD_CUST_CREDIT_CHECK` (`1` `HIGH`); `T05`, `T27` |
| `R60`: `USED_WITHOUT_HIGH_FINDING` | `ZCCMC_I_UsageFact.RunCount > 0`, `ZCCMC_I_Finding.Severity = HIGH` count `< 1` | Yes | `ZCL_PRICING_HELPER` (`1` `LOW`, `0` `HIGH`); `T04`, `T06`, `T22`, `T27`, `T31` |
| Equal-priority conflict (`RULE_CONFLICT`) | `ty_rule-priority`, `ty_rule-outcome`, `ty_rule-active` | Rule configuration | In-code rule set (`T09`, vs. same-outcome `T17`) |
| `REWRITE_RAP` (reserved priority 40) | Transactional capability / reuse indicator | **Explicit Gap:** No CSV column in `data/templates/` | Out of scope for v1 evaluation; documented in `docs/limitations.md` |
| `SIDE_BY_SIDE_BTP` (reserved priority 50) | External integration / released-API boundary indicator | **Explicit Gap:** No CSV column in `data/templates/` | Out of scope for v1 evaluation; documented in `docs/limitations.md` |

---

## 7. Enum Normalization & Separation of Concerns

- **`Finding.severity` (`HIGH | MEDIUM | LOW | INFO`):** Validated by `zccmc_cl_import_validator` and normalized with `to_upper( condense( ... ) )`. Only `HIGH` increments `high_findings` for `R30`/`R60`. `MEDIUM`, `LOW`, and `INFO` are retained as evidence records in `ZCCMC_FINDING` but do not block `KEEP_ADAPT`. Blank severity is rejected on import (`MISSING_REQUIRED_FIELD`).
- **`CustomObject.criticality` (`HIGH | MEDIUM | LOW | UNKNOWN`):** Provided by the business owner in `objects.csv` (not computed by the engine). Normalized with `to_upper( condense( ... ) )`; blank or unrecognized values normalize safely to `UNKNOWN`, triggering `CRITICALITY_UNKNOWN` (`MANUAL_REVIEW`).
- **`CustomObject.business_owner` vs. Workflow `OwnerUser`:** `business_owner` in `ZCCMC_CUSTOBJ` is informational business text and is never read by the rules engine or used for Separation of Duties (Member 3 uses `ZCCMC_DECISION.OWNER_USER`).

---

## 8. Rules Output Contract & Explanation Trace Format (Handoff to Member 3 & Member 4)

### Output Structure (`zccmc_cl_rule_engine=>ty_result`)

| ABAP Field (`ty_result`) | RAP / CDS Projection Field (`ZCCMC_C_Decision`) | Description |
|---|---|---|
| `object_id` | `ObjectUUID` | Evaluated object identifier, passed through unchanged. |
| `run_id` | `RecommendationRunID` | Caller-supplied run identifier (`CHAR(64)` / `string`), passed through unchanged and **never** included in `explanation` text. |
| `strategy` | `RecommendedStrategy` | One of `KEEP_ADAPT`, `REWRITE_RAP`, `RETIRE_CANDIDATE`, `SIDE_BY_SIDE_BTP`, `MANUAL_REVIEW`. |
| `ruleset_id` | `RuleSetVersion` (prefix) | `ZCCMC_DEMO` in v1.0.0. |
| `ruleset_version` | `RuleSetVersion` (`ZCCMC_DEMO/1.0.0`) | `1.0.0` in frozen release v1. |
| `explanation` | `EvidenceSummary` | Deterministic English rationale + serialized evidence snapshot (`criticality`, `usage_facts`, `run_count`, `window_months`, `last_executed`, `evidence_as_of`, `findings_known`, `high_findings`, `high_criticality_caller`). |
| `missing_evidence` | `MissingEvidence` | Ordered table of reason codes from `c_reason` (empty when complete). |
| `matched_rule_ids` | `MatchedRuleIDs` | Active rules whose condition matched, sorted by `priority ASCENDING`, then `rule_id ASCENDING`. |
| `run_timestamp` | `CreatedAt` / `ChangedAt` | Caller-supplied UTC timestamp (`utclong`), passed through unchanged. |

### Exact Deterministic Explanation Templates (`build_explanation`)

Every result produces an `explanation` string ending with the exact evidence snapshot:
- When `usage_facts = 1`:  
  `Evidence: criticality=<CRIT>; usage_facts=1; run_count=<N>; window_months=<M>; last_executed=<YYYY-MM-DD|none>; evidence_as_of=<YYYY-MM-DD|none>; findings_known=<yes|no>; high_findings=<H>; high_criticality_caller=<yes|no>.`
- When `usage_facts <> 1`:  
  `Evidence: criticality=<CRIT>; usage_facts=<U>; findings_known=<yes|no>; high_findings=<H>; high_criticality_caller=<yes|no>.`

The prefix before `Evidence:` follows four mutually exclusive cases:
1. **Evidence problem (`missing_evidence` from `assess_evidence` or `UNKNOWN_CONDITION_CODE` is non-empty):**  
   `MANUAL_REVIEW: safe default because of: <CODE_1, CODE_2, ...>. Evidence: ...`
2. **Equal-priority rule conflict (`RULE_CONFLICT`):**  
   `MANUAL_REVIEW: active rules <R_A, R_B> share priority <P> but give different outcomes; the engine does not pick one. Evidence: ...`
3. **No matching active rule (`NO_RULE_MATCH`):**  
   `MANUAL_REVIEW: no active rule matched, so the safe default applies. Evidence: ...`
4. **Winning rule (`R20`, `R30`, or `R60` with complete evidence):**  
   `Rule <RULE_ID> (priority <P>): <RATIONALE> Result <STRATEGY>. Evidence: ...`

---

## 9. Exact Calculation Definitions (`zccmc_cl_rule_engine`)

- **Whole calendar months (`whole_months_between`):** The largest integer `n >= 0` such that `period_start + n months` (with the day-of-month clamped to the last day of the target month, accounting for 28/29/30/31-day months and leap years: `MOD 400 = 0 OR (MOD 4 = 0 AND MOD 100 <> 0)`) is `<= period_end`. Returns `0` if `period_start` or `period_end` is initial or `period_end < period_start`.
- **Import evidence bridge (`build_evidence_from_import`):** Normalizes raw imported object, usage, finding, and caller fields from `zccmc_cl_import_orchestrator=>build_m2_evidence_for_obj` into `ty_evidence` (`T31`).
- **Portfolio batch determinism (`evaluate_portfolio`):** Copies `it_evidence`, sorts by `object_id ASCENDING`, and evaluates each object independently via `evaluate_object`. Input row permutations or unrelated objects in the batch can never alter any object's result or leak into its explanation (`T28`, `T29`).

---

## 10. Portfolio Analytics Specification (`zccmc_cl_portfolio_analytics` — Frozen v1)

Implemented in `src/zccmc_core/zccmc_cl_portfolio_analytics.clas.abap` and verified by `src/zccmc_test/zccmc_ut_portfolio_analytics.clas.abap` (`PA-T01`..`PA-T13`) and `tools/m2_rules_oracle.py`:

| Metric ID | Summary Field (`ty_summary`) | Definition | Synthetic 7-Object Golden Value (`2026-10-14`) |
|---|---|---|---|
| `M-01` | `total_objects` | Count of unique custom objects in the latest recommendation run matching `is_filter`. | `7` |
| `M-02` | `by_strategy` | Count of unique objects per canonical `RecommendedStrategy` (always seeded with all 5 outcomes in deterministic order). | `MANUAL_REVIEW`: `6`, `KEEP_ADAPT`: `1`, `RETIRE_CANDIDATE`: `0`, `REWRITE_RAP`: `0`, `SIDE_BY_SIDE_BTP`: `0` |
| `M-03` | `objects_with_complete_evidence` / `objects_with_missing_evidence` | Split of `total_objects` into objects with empty `missing_evidence` vs. non-empty `missing_evidence`. | Complete: `3` (`ZSD_OPEN_ORDERS_RPT`, `ZCL_PRICING_HELPER`, `ZSD_CUST_CREDIT_CHECK`); Missing: `4` |
| `M-03` Breakdown | `by_missing_reason` | Object count per distinct `MissingEvidence` reason code (deduplicated per object, sorted alphabetically by `reason_code`). | `CRITICALITY_UNKNOWN`: `2`, `NO_USAGE_FACT`: `1`, `WINDOW_TOO_SHORT`: `1` |
| Filter Groupings | `by_source_system`, `by_package`, `by_criticality` | Reconciled object counts grouped by `source_system`, `package_name` (`UNSPECIFIED` if blank), and normalized `criticality` (`HIGH`, `MEDIUM`, `LOW`, `UNKNOWN`). | `by_source_system`: `DEMO_SYS = 7`; `by_package`: `7` packages (`1` each); `by_criticality`: `HIGH = 2`, `LOW = 1`, `MEDIUM = 2`, `UNKNOWN = 2` |
