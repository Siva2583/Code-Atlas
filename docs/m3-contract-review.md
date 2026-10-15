# Member 3 Review — Workflow, Data, Rules & UI Integration Contract

**Reviewer role:** Member 3 (RAP Workflow & Security).  
**Status:** Candidate v0.3 review position prepared for team sign-off (`M3-D02-T01`).  
**Reviewed artifacts:** `docs/data-contract.md` (Member 1 candidate v0.2), `docs/import-design.md`, `docs/er-diagram.md`, `docs/rules-spec.md` & `docs/m2-contract-review.md` (Member 2), `docs/state-transitions.md` (Member 3), `docs/architecture.md` & `src/zccmc_ui/*` (Member 4), and `CLEAN-CORE-11-DAY-PLAN.pdf`. All sample data is DEMO / SYNTHETIC.

## 1. Position on Member 1 Data & Import Contract (`docs/data-contract.md` v0.2)

| Item | Member 3 Position | Notes / RAP Impact |
|---|---|---|
| Four CSV schemas (`objects`, `usage`, `findings`, `dependencies`) | **Approved** | No additional CSV import kind is required by the workflow layer. |
| `ObjectUUID` stability across re-imports | **Approved & Required** | `ZCCMC_DECISION.OBJECT_UUID` links to `ObjectUUID`. Routine or corrected imports must upsert in place and never delete or regenerate `ObjectUUID` for an existing business key (`source_system + object_type + object_name`). |
| Optional `objects.findings_as_of` field | **Approved** | Exposed read-only in `ZCCMC_C_CustomObject` so reviewers can distinguish a complete zero-findings scan from unknown findings coverage. |
| `business_owner` free text vs. `OwnerUser` | **Approved** | `objects.business_owner` remains informational business metadata; separation of duties (SoD) and developer action ownership use `ZCCMC_DECISION.OWNER_USER` (authenticated system principal). |
| Import entry path (`M3-D04-T01`) | **Staged-row / Unit fallback** | Direct browser file upload is not proven in the trial tenant. Until a non-`$TMP` package and RAP action upload binding are verified in ADT, interactive upload remains marked **BLOCKED**, with repeatable ABAP Unit / staged-row ingestion as the documented fallback. |

## 2. Responses to Member 2 Open Questions (`docs/m2-contract-review.md`)

| Issue ID | Member 2 Question | Member 3 Resolution |
|---|---|---|
| **C6** | **Evaluation date:** Define evaluation date = UTC date of `RunTimestamp` so staleness is deterministic without reading the system clock. | **Confirmed.** When the RAP layer invokes `zccmc_cl_rule_engine=>evaluate_object`, it passes `iv_evaluation_date = utclong_to_utc_date( iv_run_timestamp )` and persists `RunTimestamp` on the decision/audit trail. |
| **C7** | **Reproducibility claim:** Store the result with its explanation and evidence summary because import updates rows in place. | **Confirmed.** `ZCCMC_DECISION` and `ZCCMC_DECAUDIT` store `RecommendedStrategy`, `RuleSetVersion`, `RecommendationRunID`, `EvidenceSummary` (populated from M2's `Explanation`), `MissingEvidence`, and `MatchedRuleIDs` at the time of evaluation. |
| **C9** | **Recommendation persistence & `RecommendationRunID` type:** Who persists the recommendation, and what is the type of `RecommendationRunID`? | **Confirmed.** In `zccmc_cl_decision_workflow` (domain layer), `RecommendationRunID` is `string` (`CHAR(64)` in proposed table `ZCCMC_DECISION`). Follow the one-active-decision-per-`ObjectUUID` rule: a recommendation rerun calls `apply_recommendation_rerun`, which updates the recommendation snapshot on the existing active decision, appends a `RECOMMENDATION_RERUN` audit event, and sets `ReReviewRequired = abap_true` without creating a second active decision. |
| **C13** | **`RiskScore` and `RiskCriticality` in UI metadata:** Not defined in `rules-spec.md`. | **Confirmed.** `ZCCMC_C_Decision` and `ZCCMC_C_CustomObject` do not fabricate a risk score. M4's prototype annotations should either hide `RiskScore` or treat it as an unimplemented placeholder until a formula is approved. |
| **C14** | **Field name alignment (`EvidenceSummary` vs. `Explanation`):** Align M3's `EvidenceSummary` with M2's `Explanation`, `MissingEvidence`, and `MatchedRuleIDs`. | **Confirmed & Implemented.** `zccmc_cl_decision_workflow=>ty_decision` stores `evidence_summary` (= M2 `Explanation`), `missing_evidence` (comma-separated M2 reason codes), and `matched_rule_ids` (comma-separated M2 rule IDs). |

## 3. Alignment with Member 4 Fiori Elements UI (`src/zccmc_ui/`)

| UI Artifact / Element | Current State in `src/zccmc_ui/` | Required Alignment (`M3-D02-T01` / `M3-D07-T01`) |
|---|---|---|
| Action names in `zccmc_c_customobject.ddlx.asddlxs` & `zccmc_customobject.edmx` | Uses `approveDecision` and `overrideDecision` with parameter `Reason`. | **Aligned.** `zccmc_i_decision.bdef.asbdef` and `zccmc_c_decision.bdef.asbdef` expose `approveDecision` and `overrideDecision` (plus `submitDecision`, `resubmitDecision`, `returnDecision`, `assignOwner`, `startWork`, `blockWork`, `unblockWork`, `markMigrated`, `reopenDecision`). Note: `overrideDecision` requires both `NewStrategy` and `Reason` (>= 10 characters). |
| Audit Trail projection fields | `zccmc_customobject.edmx` expects `AuditUUID`, `Actor`, `Timestamp`, `OldValue`, `NewValue`, `Reason`. | **Aligned.** `ZCCMC_C_DecisionAudit` aliases `EventUUID as AuditUUID`, `ActorUser as Actor`, `EventTimestamp as Timestamp`, `OldStrategy as OldValue`, `NewStrategy as NewValue`, plus `OldStatus`, `NewStatus`, `OldOwner`, `NewOwner`, `Reason`. |
| Status vocabulary | M3 defines 8 statuses: `PROPOSED`, `IN_REVIEW`, `APPROVED`, `OVERRIDDEN`, `RETURNED`, `IN_PROGRESS`, `BLOCKED`, `MIGRATED`. | M4's UI filters and KPI cards must use these exact 8 status codes and M2's 5 strategy codes (`KEEP_ADAPT`, `REWRITE_RAP`, `RETIRE_CANDIDATE`, `SIDE_BY_SIDE_BTP`, `MANUAL_REVIEW`). |
| Security enforcement | UI hides/disables inapplicable buttons via RAP `features : instance`. | UI button visibility is convenience only; `zccmc_cl_decision_workflow=>execute_action` enforces role, ownership, SoD, state, reason length, and ETag/version on every backend call. |
