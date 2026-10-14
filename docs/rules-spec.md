Rules Specification - DRAFT 

Status: Field names follow docs/data-contract.md (Member 1, v0.1; candidate v0.2 is not signed and is not yet the rules input contract). All sample data is DEMO / SYNTHETIC. Every threshold and weight below is illustrative and configurable. None is hardcoded, and a migration/domain expert must validate them before any real use.

The rules are deterministic: the same inputs and the same published rule-set version always give the same result. This is a rules engine, not AI or machine learning.

1. The five outcomes
KEEP_ADAPT
REWRITE_RAP
RETIRE_CANDIDATE
SIDE_BY_SIDE_BTP
MANUAL_REVIEW (the default safe outcome)
2. When each outcome applies
Outcome	Applies when
KEEP_ADAPT	The object is used or business-critical, has no high-severity findings, and can stay with manageable adaptation.
REWRITE_RAP	The object is a transactional capability with high reuse and manageable dependencies, so a RAP rewrite is worthwhile. (Needs data not yet in the contract, see section 6.)
RETIRE_CANDIDATE	There was no usage over a complete observation window of at least 12 months, and no business-critical object depends on it. A reviewer must still confirm with the owner.
SIDE_BY_SIDE_BTP	The capability has an external integration or a released-API boundary that suits a side-by-side extension. (Needs data not yet in the contract, see section 6.)
MANUAL_REVIEW	Evidence is missing, incomplete or conflicting, or no rule clearly applies. A human decides.

Parameters (illustrative, configurable):

Parameter	Illustrative value
Minimum usage coverage for RETIRE_CANDIDATE	12 whole months
Maximum evidence age (evidence_as_of)	30 days
High-severity findings that block a confident KEEP_ADAPT	1 or more
3. Rule: missing or incomplete evidence always goes to MANUAL_REVIEW

If any of these is true, the result is MANUAL_REVIEW, and the reasons are listed as "missing evidence":

There is no usage row for the object (absence of data is not zero usage).
The usage window is shorter than the minimum coverage (computed from period_start and period_end).
criticality is UNKNOWN.
Findings are not known to be loaded for the object (see open question 1).
evidence_as_of is older than the maximum evidence age.

The engine never infers "no usage" from an incomplete window, and it never produces RETIRE_CANDIDATE when evidence is incomplete. Missing evidence is reported, not hidden.

4. Rule: conflicting evidence always goes to MANUAL_REVIEW

The result is MANUAL_REVIEW, with a "conflict" reason, when:

Two or more active rules at the same best priority match with different outcomes. The engine never picks one arbitrarily.
The evidence contradicts itself, for example run_count = 0 but last_executed has a date, or run_count > 0 but last_executed is empty, or period_end is before period_start.
5. Test cases on paper (10)

"Window" means whole calendar months from period_start to period_end. The sample object ZSD_OPEN_ORDERS_RPT has exactly 12 (2025-10-13 to 2026-10-13). "Findings: loaded" assumes open question 1 is solved.

Seed rules used by the tests (illustrative, configurable). A lower priority number wins:

Rule	Prio	Condition	Outcome
R10	10	Any missing or incomplete evidence (section 3), or contradictory evidence (section 4)	MANUAL_REVIEW
R20	20	run_count = 0, window of at least 12 whole months, not called by a HIGH-criticality object	RETIRE_CANDIDATE
R30	30	Used (run_count > 0) and at least 1 HIGH finding	MANUAL_REVIEW
R60	60	Used (run_count > 0) and no HIGH finding	KEEP_ADAPT

Rules for REWRITE_RAP (prio 40) and SIDE_BY_SIDE_BTP (prio 50) are added once the data exists (section 6). If no rule matches, the result is MANUAL_REVIEW.

#	Input facts	Expected outcome	Why
T1	Run count 0, window exactly 12 months, criticality LOW, findings loaded (0), no caller	RETIRE_CANDIDATE	Boundary: 12 months is enough
T2	Same as T1 but window 11 months	MANUAL_REVIEW	Boundary: incomplete window
T3	Same as T1, but called by a HIGH-criticality object	MANUAL_REVIEW	Critical dependent blocks retire, no other rule matches
T4	Run count 2480, criticality HIGH, 12-month window, findings loaded with zero findings	KEEP_ADAPT	Boundary: zero findings
T5	Same as T4 but one HIGH finding	MANUAL_REVIEW	Boundary: one high finding (R30)
T6	Run count 15210, criticality MEDIUM, one LOW finding	KEEP_ADAPT	Low findings are manageable
T7	Criticality UNKNOWN, everything else complete	MANUAL_REVIEW	Missing evidence (R10)
T8	No usage row for the object	MANUAL_REVIEW	No data is not zero usage
T9	Two active rules at the same priority, different outcomes, both match	MANUAL_REVIEW	Rule conflict
T10	run_count = 0 but last_executed = 2026-09-25	MANUAL_REVIEW	Contradictory evidence

Also test determinism (run T1 to T10 twice: the strategy, rationale and missing-evidence list must be identical, only the RecommendationRunID and run timestamp differ) and that every result records the rule-set version and a RecommendationRunID.

6. Fields the rules need from the data contract
Entity	Fields used	Used for
CustomObject	ObjectUUID, SourceSystemID, ObjectType, ObjectName, criticality	Key, rule conditions, UNKNOWN handling
UsageFact	period_start, period_end, last_executed, run_count, evidence_source, evidence_as_of	Window coverage, usage, contradiction check, freshness
Finding	severity, finding_id (and category for display)	Counts by severity
Dependency	from and to object, dependency_type	Find callers, derive "called by a HIGH-criticality object"

Missing or unclear, to raise with Member 1:

Findings loaded vs. none found. Objects with no findings rows cannot be told apart from objects whose findings were never loaded. We need a per-object indicator (for example a findings_as_of date) or an agreed row convention. Member 1 candidate v0.2 proposes optional objects.findings_as_of for this purpose; Member 2 conditionally approves it (docs/m2-contract-review.md, A1 to A3). The engine treats a blank findings_as_of as FINDINGS_NOT_LOADED. Still pending sign-off by M3 and M4.
evidence_as_of exists only on usage. Findings and dependencies have no as-of date, so freshness is checked on usage only.
No data for REWRITE_RAP and SIDE_BY_SIDE_BTP. Nothing says an object is transactional, has high reuse or has an external integration. Either add optional columns or these two outcomes stay untestable.
"Critical dependency" is derived, not stored (an object is critical if called by a HIGH-criticality object). Please confirm.
Sample data coverage. With v0.2 the 7 sample objects reach only KEEP_ADAPT (1) and MANUAL_REVIEW (6). No sample object can reach RETIRE_CANDIDATE, REWRITE_RAP or SIDE_BY_SIDE_BTP. Please add rows for T1, T3, T4, T10, T11 and a stale evidence_as_of, labeled DEMO / SYNTHETIC. The ABAP Unit tests carry these cases as in-code data, so they are not blocked.
7. Review of the data contract: severity and criticality values

Severity (HIGH | MEDIUM | LOW | INFO)

The values are fine. INFO is understood as informational: it is ignored by the high-finding rule and by the risk score.
Please state the mapping from the source ATC priorities to these four values, so the meaning is the same for every import.
Severity must never be empty. An empty value should be rejected, not defaulted.

Criticality (HIGH | MEDIUM | LOW | UNKNOWN)

The values are fine. UNKNOWN is treated as missing evidence and always leads to MANUAL_REVIEW.
Please confirm that an empty CSV value is normalized to UNKNOWN, not rejected or defaulted to LOW.
Please state who provides the value (business owner) and that it is a given business attribute, not computed by the engine.
business_owner is free text, not a user ID. The rules do not use it, and it must not be used for separation of duties. Member 3 keeps a separate OwnerUser field on the decision for that.

Both enums should be normalized to upper case on import, like object_type.

8. Rules output (handover to Member 3)

Each evaluation returns one result per object with these fields (proposed, to be confirmed with Member 3):

Field	Meaning
ObjectUUID	The object that was evaluated (key of CustomObject)
RecommendationRunID	Identifies the engine run that produced this result. A new value for every run, never reused and never changed. A result is identified by RecommendationRunID + ObjectUUID
RecommendedStrategy	One of the five outcomes in section 1
RuleSetVersion	The published rule-set version used (with the rule-set ID)
Explanation	Text built from the matched rule's rationale and the real evidence values
MissingEvidence	The list of reasons from sections 3 and 4, empty if none
MatchedRuleIDs	The rules that matched, in priority order
RunTimestamp	UTC, server time

Run and rerun rules:

Every run, including a rerun, gets a new RecommendationRunID. Old runs are kept, so any past result can be reproduced from its rule-set version and evidence. Caveat (M2 review C7): import updates evidence in place, and the evaluation date is an input, so a result is only reproducible if its Explanation (which records the evidence values used) and the evaluation date are stored with it. The evaluation date is proposed to be the UTC date of RunTimestamp (C6).
The engine never changes a decision. If an object already has an active decision, the new result is stored as a new recommendation revision and the decision is flagged for re-review. Member 3 owns the decision, its status and its final strategy.
From the rules side there is no objection to Member 3's proposal of at most one active decision per ObjectUUID. A rerun updates the recommendation of the existing decision instead of creating a second one.

Open point: the data type of RecommendationRunID (to match the UUID type Member 1 uses once the tables exist).

9. Limitations
Deterministic rules only. No ML and no claim of predictive accuracy.
Sample data is synthetic and labeled DEMO / SYNTHETIC.
Thresholds and weights are illustrative until validated by a migration expert.
Evidence comes from CSV import only. Live adapters are future work.

10. Rule-to-field map (checked against data-contract candidate v0.2 and data/sample-synthetic)

Status: checked against the documents and CSV files only. The table and CDS files on main are empty, so nothing is verified against activated objects. All data is DEMO / SYNTHETIC.

| Rule / condition | Source entity.field | In contract v0.2? | Sample fixture |
|---|---|---|---|
| R10: no usage row | UsageFact row exists for the object | Yes | ZFI_OLD_LEDGER_EXPORT |
| R10: more than one usage row | UsageFact rows per object | Contract allows it, spec assumes one (M2 review C1) | none |
| R10: window shorter than 12 whole months | UsageFact.period_start, period_end | Yes | ZMM_STOCK_ALERT (2 months) |
| R10: criticality UNKNOWN | CustomObject.criticality (blank is normalized to UNKNOWN) | Yes | ZCL_INVOICE_UTIL, ZHR_PAYROLL_ADJ |
| R10: evidence older than 30 days | UsageFact.evidence_as_of against the evaluation date | Yes (usage only; evaluation_date is an engine input) | none (all evidence_as_of are 2026-10-13) |
| R10: findings coverage unknown | CustomObject.findings_as_of blank | Yes, new in v0.2 (conditional approval) | none (all 7 objects have it set) |
| R10 / section 4: run_count = 0 but last_executed set | UsageFact.run_count, last_executed | Yes | none |
| R10 / section 4: run_count > 0 but last_executed empty | UsageFact.run_count, last_executed | Yes | none |
| R10 / section 4: period_end before period_start | UsageFact.period_start, period_end | Yes | none |
| R20: run_count = 0 | UsageFact.run_count | Yes | none with a full window (ZMM_STOCK_ALERT has 0 runs but a short window) |
| R20: not called by a HIGH-criticality object | Dependency (to = this object) joined to the caller's criticality | Derived, not stored (confirm: M2 review C3, C4) | none |
| R30 / R60: used (run_count > 0) | UsageFact.run_count | Yes | 5 objects |
| R30 / R60: HIGH finding count | Finding.severity (INFO, LOW and MEDIUM are ignored) | Yes | R30: ZSD_OPEN_ORDERS_RPT, ZSD_CUST_CREDIT_CHECK; R60: ZCL_PRICING_HELPER |
| Tie at same priority (section 4) | rule set: priority, outcome, active flag | Rule configuration, not CSV data | in-code test rule set |
| REWRITE_RAP (priority 40) | transactional capability, reuse | GAP: no field | none |
| SIDE_BY_SIDE_BTP (priority 50) | external integration, released-API boundary | GAP: no field | none |

Engine inputs that are not CSV fields: evaluation_date (so freshness is deterministic), the rule set (id, version, parameters, rules), RecommendationRunID, RunTimestamp.

11. Definitions used by the engine (pending team confirmation where marked)

Whole calendar months (confirm, C5): the largest n such that period_start plus n months, with the day clamped to the end of the target month, is not after period_end. 2025-10-13 to 2026-10-13 is 12. 2025-10-13 to 2026-10-12 is 11. 2025-01-31 to 2025-02-28 is 1. period_end before period_start is a contradiction and no window is computed.
Stale evidence: evaluation_date minus evidence_as_of is more than 30 days. Exactly 30 days is still fresh. The evaluation date is a parameter and the clock is never read.
Findings coverage: known only when findings_as_of is filled. The 30-day limit is not applied to it (C10).
HIGH finding count: number of finding rows with severity HIGH. R30 matches at 1 or more, R60 at fewer than 1 (parameter high_finding_min_count = 1, illustrative).
Callers: every dependency row whose to object is the evaluated object, of any dependency_type (conservative, C3). One HIGH-criticality caller blocks R20. A caller with UNKNOWN criticality blocks R20 as missing evidence, only when run_count = 0 (C4, proposed).
Several usage rows for one object: MULTIPLE_USAGE_FACTS, MANUAL_REVIEW (C1, proposed).
Order of evaluation: all active rules are evaluated, matches are sorted by priority then rule ID, the best priority wins. Equal best priority with different outcomes is RULE_CONFLICT. Equal priority with the same outcome is not a conflict. No match is NO_RULE_MATCH.
Safety invariant: any missing evidence reason gives MANUAL_REVIEW whatever the rule set contains, so deleting or deactivating R10 cannot turn missing evidence into another outcome.
Reason codes (also the MissingEvidence list): NO_USAGE_FACT, MULTIPLE_USAGE_FACTS (proposed), PERIOD_END_BEFORE_START, WINDOW_TOO_SHORT, EVIDENCE_STALE, ZERO_RUNS_WITH_LAST_EXECUTED, RUNS_WITHOUT_LAST_EXECUTED, CRITICALITY_UNKNOWN, FINDINGS_NOT_LOADED, CALLER_CRITICALITY_UNKNOWN (proposed), RULE_CONFLICT, NO_RULE_MATCH (proposed as a listed reason), UNKNOWN_CONDITION_CODE (proposed).
Rule-set id and version in the code are placeholders (ZCCMC_DEMO, 0.1.0-DRAFT) until the team agrees a numbering scheme (C9).

12. Portfolio metrics

Position: the agreed contracts define no portfolio metric, no risk score and no confidence value, so none is implemented. architecture.md lists dashboard tiles and charts, and the Fiori annotation shows RiskScore, but no document gives a formula (M2 review C13). Candidates for the team to agree, each a plain count with no weighting:
M-01 objects evaluated in the latest run.
M-02 objects per RecommendedStrategy.
M-03 objects with a non-empty MissingEvidence, split by reason code.
Hand count for the 7 sample objects (evaluation date 2026-10-14): M-01 = 7. M-02 = MANUAL_REVIEW 6, KEEP_ADAPT 1. M-03 = 4 objects: NO_USAGE_FACT 1, WINDOW_TOO_SHORT 1, CRITICALITY_UNKNOWN 2.
Counts must come from one row per object of the latest run, so joins to usage, findings or dependencies cannot double count. They are not implemented in ABAP until the team agrees them.
