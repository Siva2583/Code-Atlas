Rules Specification - DRAFT 

Status: DRAFT. Members 1, 3 and 4 please review. Field names follow docs/data-contract.md (Member 1, v0.1). All sample data is DEMO / SYNTHETIC. Every threshold and weight below is illustrative and configurable. None is hardcoded, and a migration/domain expert must validate them before any real use.

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

Findings loaded vs. none found. Objects with no findings rows cannot be told apart from objects whose findings were never loaded. We need a per-object indicator (for example a findings_as_of date) or an agreed row convention.
evidence_as_of exists only on usage. Findings and dependencies have no as-of date, so freshness is checked on usage only.
No data for REWRITE_RAP and SIDE_BY_SIDE_BTP. Nothing says an object is transactional, has high reuse or has an external integration. Either add optional columns or these two outcomes stay untestable.
"Critical dependency" is derived, not stored (an object is critical if called by a HIGH-criticality object). Please confirm.
Sample data coverage. No sample object can reach RETIRE_CANDIDATE, REWRITE_RAP or SIDE_BY_SIDE_BTP. Please add rows for each, labeled DEMO / SYNTHETIC.
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

Every run, including a rerun, gets a new RecommendationRunID. Old runs are kept, so any past result can be reproduced from its rule-set version and evidence.
The engine never changes a decision. If an object already has an active decision, the new result is stored as a new recommendation revision and the decision is flagged for re-review. Member 3 owns the decision, its status and its final strategy.
From the rules side there is no objection to Member 3's proposal of at most one active decision per ObjectUUID. A rerun updates the recommendation of the existing decision instead of creating a second one.

Open point: the data type of RecommendationRunID (to match the UUID type Member 1 uses once the tables exist).

9. Limitations
Deterministic rules only. No ML and no claim of predictive accuracy.
Sample data is synthetic and labeled DEMO / SYNTHETIC.
Thresholds and weights are illustrative until validated by a migration expert.
Evidence comes from CSV import only. Live adapters are future work.