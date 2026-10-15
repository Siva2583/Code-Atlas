# Member 2 Review — Import / Rules Contract 

**Reviewer role:** Member 2 (Rules & Analytics). **Status: DRAFT position, prepared for the Member 2 owner to confirm and post to the team. It is not a signed approval and nothing here has been sent.**
**Reviewed:** `docs/data-contract.md` candidate v0.2, `docs/import-design.md`, `docs/er-diagram.md`, `docs/state-transitions.md` (Member 3), `docs/rules-spec.md`, `docs/architecture.md`, the Fiori annotation in `src/zccmc_ui/`, and the fixtures. Everything was read from `main` at commit d385837 (Member 1's v0.2 docs and fixtures are merged there). All data is DEMO / SYNTHETIC.
**Not reviewed because they are still empty or absent on main:** the 13 table and CDS files under `src/zccmc_data/` and all importer and importer-test classes under `src/zccmc_import/` and `src/zccmc_test/` (all 0 bytes), and any RAP object (`src/zccmc_rap/` has only `.gitkeep`). Every field below is checked against documents and CSV files only.

## Decision

**Conditionally approved for engine implementation; NOT approved for freeze.** The engine can be written against the inputs below. The contract should not be frozen until decisions C1–C4 and C6–C9 and C13–C14 are made. Nothing in this review adds a field, outcome or threshold: where the engine needs behavior the documents do not define, it takes the safe path (MANUAL_REVIEW) and the item is listed here as PROPOSED.

## A. Items approved (from Member 1's v0.2)

| Item | Position |
|---|---|
| Four CSV kinds and exact headers | Approved. Matches `data/templates/` and every sample file. |
| `objects.findings_as_of` (optional date; filled = findings scan complete for that object, even with zero rows; blank = coverage unknown) | **Approved with conditions A1–A3 below.** This closes the "findings loaded vs none found" gap in rules-spec section 6. |
| Blank `criticality` normalizes to UNKNOWN | Approved. The engine treats UNKNOWN, blank or any unrecognized value as UNKNOWN, which is missing evidence. |
| Severity HIGH / MEDIUM / LOW / INFO, blank rejected | Approved. The rules only count HIGH. |
| Business keys, uppercase normalization | Approved. |
| Partial-file commit (valid rows commit, rejected rows get errors) | No objection from the rules side. Missing rows show up as missing evidence and give MANUAL_REVIEW. |
| `evidence_source` DEMO / CSV_EXPORT | Approved. The rules do not use it. |

Conditions on `findings_as_of`:
- **A1.** A blank `findings_as_of` is treated as "findings not loaded" (`FINDINGS_NOT_LOADED`) even when finding rows exist, because the rows may be a partial load. Please confirm.
- **A2.** The importer must only set `findings_as_of` when the findings scan for that object really is complete. Otherwise the engine will read an incomplete scan as "zero findings".
- **A3.** rules-spec says freshness is checked on usage only. The engine therefore does not apply the 30-day limit to `findings_as_of`. If the team wants findings to go stale too, that is a new rule use of the same threshold and needs agreement (decision C10).

## B. Changes requested / decisions needed before freeze

| # | Issue | Why it matters | Engine behavior today | Proposal |
|---|---|---|---|---|
| C1 | **Several usage rows per object.** The v0.2 usage key is object + period_start + period_end + evidence_source, so one object can have many usage rows. rules-spec assumes one. | Any choice of "the" usage row changes the result. | `MULTIPLE_USAGE_FACTS` → MANUAL_REVIEW (**PROPOSED**). | Decide: (a) keep this safe default, (b) the data layer supplies one "current" usage fact per object with a documented tie-break, or (c) restrict to one usage row per object. |
| C2 | **No coverage indicator for dependencies.** RETIRE_CANDIDATE needs "no HIGH-criticality caller", but an object with no dependency rows looks the same whether dependencies were never loaded or there are none. | Risk of a false RETIRE_CANDIDATE. rules-spec already says a reviewer must confirm with the owner, which is the only protection today. | Absence of rows = no callers. | Decide: add an optional `dependencies_as_of` like `findings_as_of` (team change, not made here), or document this limitation in `docs/limitations.md`. |
| C3 | **Meaning of "called by".** Direction (callers are rows whose *to* object is the evaluated object) and which `dependency_type` values count. No closed list exists. | Ignoring a type could hide a critical caller. | Any dependency type counts as a caller (conservative, **PROPOSED**). | Confirm, or provide the closed list of types. |
| C4 | **Caller with UNKNOWN criticality** on the retirement path. | Treating it as "not HIGH" could retire something a critical object depends on. | `CALLER_CRITICALITY_UNKNOWN` → MANUAL_REVIEW, only when run_count = 0 (**PROPOSED**). | Confirm. |
| C5 | **Definition of "whole calendar months".** | The 12-month boundary decides RETIRE_CANDIDATE. | Largest n where start + n months (day clamped to month end) is not after end. 2025-10-13 → 2026-10-13 = 12, matching the spec example. | Confirm and copy the definition into the spec (done in rules-spec section 11). |
| C6 | **Evaluation date.** Staleness depends on "today". The sample `evidence_as_of` 2026-10-13 turns stale after 2026-11-12, so a rerun next month gives different results from the same data. | Needed for the "reproducible" promise and for stable tests. | The engine takes the evaluation date as an input and never reads the clock. | Define evaluation date = UTC date of `RunTimestamp`, so no new field is needed. Confirm with Member 3. |
| C7 | **Reproducibility claim.** rules-spec section 8 says any past result can be reproduced from rule-set version and evidence. But import updates rows in place (UPDATED) and never keeps old values. | The claim is false once evidence is corrected. | The explanation text records the evidence values used. | Store the result with its explanation and an evidence summary, or soften the claim. Decide who persists it. |
| C8 | **Findings from older scans never deleted.** The contract says a corrected batch never deletes omitted entities. A finding that was fixed and is absent from the new scan stays in the table. | HIGH counts can include resolved findings and push an object to MANUAL_REVIEW wrongly. The same applies to old usage rows (C1). | Counts every finding row present. | Decide how a complete rescan (`findings_as_of` newer) replaces or supersedes older findings. This is the most important open data question for Member 1. |
| C9 | **Rule sets and recommendation runs have no persistence entity.** `ER diagram` and `data-contract` list neither RuleSet / Rule / parameters nor RecommendationRun / Recommendation. | The engine needs a rule-set id, version and parameters, and Member 3 needs `RecommendationRunID` and the result to link decisions. | Rule set is code (`seed_ruleset`) with **placeholder** id `ZCCMC_DEMO` and version `0.1.0-DRAFT`. | Agree the entities, owner, key types (including the type of `RecommendationRunID`) and a version numbering scheme. Published versions must be immutable. |
| C10 | **Other contradictions not defined by the spec** (last_executed outside the window, last_executed after evidence_as_of, evidence_as_of in the future; staleness of `findings_as_of`). | Silent acceptance of odd data. | Not treated as conflicts. | Decide whether to add them. Adding any is a rule change and needs team agreement. |
| C11 | **Severity mapping** from source ATC priorities to HIGH/MEDIUM/LOW/INFO is still not stated. | Same meaning for every import. | n/a | Member 1 to document (requested earlier in rules-spec section 7). |
| C12 | **REWRITE_RAP and SIDE_BY_SIDE_BTP** have no source data. | The two outcomes cannot be evaluated or tested. | Not implemented; no condition codes exist for them. | Stay untestable until the team agrees fields. M2 does not add them. |
| C13 | **`RiskScore` and `RiskCriticality` appear in Member 4's UI annotation** (`zccmc_c_customobject.ddlx.asddlxs`) and architecture.md lists Risk, Confidence/Priority and Completeness, but rules-spec defines no score, confidence or completeness. Section 7 even says INFO is ignored "by the risk score", which is never defined. | A score shown to reviewers must have a documented formula. | **Not implemented.** The engine returns no score. | Either define a documented, weighted score with its component breakdown (never called ML) as a team decision, or remove these columns from the UI until then. M2 will not invent one. |
| C14 | **Field name mismatch with Member 3.** `state-transitions.md` consumes `EvidenceSummary`; rules-spec section 8 produces `Explanation`, `MissingEvidence` and `MatchedRuleIDs`. | M3's Submit validation requires an evidence summary. | Engine returns the three M2 fields. | Agree that `EvidenceSummary` = `Explanation` (it already contains the real evidence values), with `MissingEvidence` and `MatchedRuleIDs` stored alongside. |

## C. The rules contract as implemented (for Members 3 and 4)

**Input per object** (engine takes plain structures; reading the database is the caller's job): criticality, `findings_as_of`, usage rows, finding severities, criticality of each calling object, plus rule set, evaluation date, `RecommendationRunID`, `RunTimestamp`.

**Output per object** (matches rules-spec section 8 and what Member 3 asked for):

| Field | Notes |
|---|---|
| ObjectUUID | Passed through unchanged. |
| RecommendationRunID | Supplied by the caller, passed through. Never used in logic or in the explanation. |
| RecommendedStrategy | One of the five outcomes. |
| RuleSetVersion (+ rule-set ID) | Copied from the rule set used. |
| Explanation | Deterministic English text: winning rule and rationale, or the reason codes, plus the real evidence values. Machine-readable parts are the codes; do not parse the text. |
| MissingEvidence | Ordered list of reason codes (the "unresolved inputs"). |
| MatchedRuleIDs | All matching active rules, ordered by priority then rule ID. |
| RunTimestamp | Supplied by the caller, passed through. |

**Reason codes:** `NO_USAGE_FACT`, `MULTIPLE_USAGE_FACTS`*, `PERIOD_END_BEFORE_START`, `WINDOW_TOO_SHORT`, `EVIDENCE_STALE`, `ZERO_RUNS_WITH_LAST_EXECUTED`, `RUNS_WITHOUT_LAST_EXECUTED`, `CRITICALITY_UNKNOWN`, `FINDINGS_NOT_LOADED`, `CALLER_CRITICALITY_UNKNOWN`*, `RULE_CONFLICT`, `NO_RULE_MATCH`*, `UNKNOWN_CONDITION_CODE`*. (* = PROPOSED, not in rules-spec yet.) `RULE_CONFLICT` and `NO_RULE_MATCH` are returned in the same list so the UI can say why a MANUAL_REVIEW happened. Member 4: map codes to display labels in the UI.

**Behavior for the special cases (all end in MANUAL_REVIEW):**
- Missing, unknown, stale or contradictory evidence: always MANUAL_REVIEW. This is enforced in code, not only by rule R10, so it still holds if R10 is missing or inactive.
- Equal best priority with different outcomes: `RULE_CONFLICT`, no rule is picked. Equal priority with the same outcome is not a conflict.
- No active rule matches: `NO_RULE_MATCH`.
- A rule record with an unknown condition code: the rule set is treated as invalid and the result is MANUAL_REVIEW with `UNKNOWN_CONDITION_CODE`.

**Versioning:** the rule set carries id, version and parameters (12 months, 30 days, 1 HIGH finding; all illustrative and configurable). Inactive rules are ignored. Persisting rule sets and enforcing "published = immutable" is not implemented (see C9).

## D. What Member 2 needs from the others

- **Member 1:** answers to C1, C2, C3, C8, C11; fixture rows for T1, T3, T4, T10, T11 and a stale `evidence_as_of` (the in-code ABAP Unit literals cover them for now, so this is not blocking tests).
- **Member 3:** confirm C6 (evaluation date), the type of `RecommendationRunID`, and who persists the result (C7, C9).
- **Member 4:** UI labels for the reason codes; confirm the Rules Administration page is out of scope until C9 is decided.
