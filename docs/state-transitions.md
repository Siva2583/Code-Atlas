# Migration Decision Workflow, Security and Audit

**Owner:** Member 3 — RAP Workflow & Security  
**Version:** 0.3 — Candidate Contract & Reference Implementation (`M3-D02-T01` .. `M3-D11-T01`)  
**Status:** Frozen in repository reference model (`zccmc_cl_decision_workflow` + `tools/m3_workflow_oracle.py`); live SAP ADT activation remains gated on non-`$TMP` package resolution (see `docs/feasibility-note.md` and `docs/limitations.md`).  
**Scope:** Migration Decision business object, workflow actions, backend authorization, separation of duties (SoD), optimistic concurrency, and append-only audit history.

All examples and test data are DEMO / SYNTHETIC. The cockpit records human governance decisions; it never automatically migrates, retires, or deletes SAP objects.

## 1. Purpose

Each Migration Decision connects one custom object (`ObjectUUID`) to a deterministic recommendation from Member 2's rules engine (`zccmc_cl_rule_engine`). It records the review outcome, assigned developer owner, current workflow status, optimistic lock version, and immutable audit history of changes.

The RAP backend (`zccmc_cl_decision_workflow` / `zccmc_bp_i_decision`) is the sole authority for whether an action is allowed. Hiding or disabling an action in the Fiori UI is never treated as security.

## 2. Decision Fields & Cross-Team Contract Mapping

Aligned with Member 1 (`docs/data-contract.md` v0.2), Member 2 (`docs/rules-spec.md` & `docs/m2-contract-review.md` C6/C7/C9/C14), and Member 4 (`src/zccmc_ui/zccmc_customobject.edmx`):

| Field | Domain / ABAP Type | Purpose & Source |
|---|---|---|
| `DecisionUUID` | `string` / `sysuuid_x16` | Stable technical key for the decision (`ZCCMC_DECISION.DECISION_UUID`) |
| `ObjectUUID` | `string` / `sysuuid_x16` | Foreign key to Member 1's `CustomObject` (`ZCCMC_CUSTOBJ`) |
| `RecommendedStrategy` | `string` / `CHAR(40)` | Original strategy produced by Member 2 (`KEEP_ADAPT`, `REWRITE_RAP`, `RETIRE_CANDIDATE`, `SIDE_BY_SIDE_BTP`, `MANUAL_REVIEW`); never overwritten by human override |
| `FinalStrategy` | `string` / `CHAR(40)` | Strategy accepted by Reviewer (`= RecommendedStrategy` on `APPROVE`, or Reviewer-chosen strategy `!= RecommendedStrategy` on `OVERRIDE`) |
| `RuleSetVersion` | `string` / `CHAR(60)` | Rule-set ID and version from Member 2 (e.g., `ZCCMC_DEMO/0.1.0-DRAFT`) |
| `RecommendationRunID` | `string` / `CHAR(64)` | Identifies the Member 2 evaluation run |
| `Status` (`DecisionStatus`) | `string` / `CHAR(30)` | Current workflow status (one of the 8 statuses in Section 3) |
| `OwnerUser` | `string` / `CHAR(120)` | Assigned system principal responsible for development work (distinct from free-text `objects.business_owner`) |
| `CreatedBy` | `string` / `CHAR(120)` | Authenticated server user who created the decision |
| `SubmittedBy` | `string` / `CHAR(120)` | Authenticated server user who last submitted/resubmitted the decision for review |
| `CreatedAt` / `ChangedAt` | `utclong` | Server-maintained UTC timestamps (`ChangedAt` serves as the RAP `etag master`) |
| `EvidenceSummary` | `string` / `CHAR(1000)` | Mapped directly from Member 2's `Explanation` text (per M2 review C14) |
| `MissingEvidence` | `string` / `CHAR(250)` | Comma-separated Member 2 unresolved/missing reason codes |
| `MatchedRuleIDs` | `string` / `CHAR(120)` | Comma-separated Member 2 matched rule IDs in priority order |
| `ImportBatchUUID` | `string` / `sysuuid_x16` | Link to Member 1's `ImportBatch` provenance when applicable |
| `ReReviewRequired` | `abap_boolean` | Set to `abap_true` when a Member 2 recommendation rerun revises an active decision (`apply_recommendation_rerun`); cleared upon `SUBMIT` / `RESUBMIT` |
| `VersionNo` | `i` / `INT4` | Monotonically increasing optimistic lock counter incremented on every accepted mutation |

**Uniqueness & Rerun Rule:** At most one active decision (status `!= MIGRATED`) is permitted per `ObjectUUID` (`ERR_DUPLICATE_ACTIVE_DECISION`). When Member 2 re-evaluates an object that already has an active decision, `apply_recommendation_rerun` updates the recommendation fields on the existing decision, sets `ReReviewRequired = abap_true`, and appends a `RECOMMENDATION_RERUN` audit event rather than creating a second active decision.

## 3. Workflow Statuses

| Status | Meaning | Active? |
|---|---|---|
| `PROPOSED` | Recommendation exists and is being prepared by the assigned developer | Active |
| `IN_REVIEW` | Submitted and awaiting independent reviewer action | Active |
| `APPROVED` | Recommended strategy accepted by reviewer (`FinalStrategy = RecommendedStrategy`) | Active |
| `OVERRIDDEN` | Reviewer selected a different strategy (`FinalStrategy != RecommendedStrategy`) with a mandatory reason | Active |
| `RETURNED` | Reviewer sent the decision back for correction or additional evidence | Active |
| `IN_PROGRESS` | Assigned developer has started modernization/adaptation work | Active |
| `BLOCKED` | Modernization work cannot continue until a documented blocker is resolved | Active |
| `MIGRATED` | Human recorded completion of the modernization work (final unless reopened by Admin) | Inactive (Final) |

## 4. Allowed Transitions, Actions & Stable Error Codes

Only the transitions listed below are allowed. Every other state/action/role combination is rejected server-side without mutating the decision or audit trail.

| Current Status | Action (`c_action`) | RAP Action Name | New Status | Authorized Actor | Mandatory Parameters & Guardrails |
|---|---|---|---|---|---|
| `(New)` | `CREATE_FROM_RECOMMENDATION` | `create` / factory | `PROPOSED` | `DEVELOPER` or `ADMIN` | Requires `ObjectUUID`, valid `RecommendedStrategy`, `RuleSetVersion`, `RecommendationRunID`, `EvidenceSummary`; no existing non-`MIGRATED` decision for `ObjectUUID` |
| `PROPOSED` | `ASSIGN_OWNER` | `assignOwner` | `PROPOSED` | `REVIEWER` or `ADMIN` | Non-empty `NewOwner` (`ERR_MISSING_OWNER`) |
| `PROPOSED` | `SUBMIT` | `submitDecision` | `IN_REVIEW` | Assigned `DEVELOPER` (`Actor == OwnerUser`) or `ADMIN` | Non-empty `OwnerUser` (`ERR_MISSING_OWNER`) and complete recommendation fields; sets `SubmittedBy = Actor` |
| `RETURNED` | `ASSIGN_OWNER` | `assignOwner` | `RETURNED` | `REVIEWER` or `ADMIN` | Non-empty `NewOwner` |
| `RETURNED` | `RESUBMIT` | `resubmitDecision` | `IN_REVIEW` | Assigned `DEVELOPER` (`Actor == OwnerUser`) or `ADMIN` | Response `Reason` >= 10 chars (`ERR_MISSING_REASON` / `ERR_REASON_TOO_SHORT`); updates `SubmittedBy = Actor` |
| `IN_REVIEW` | `APPROVE` | `approveDecision` | `APPROVED` | `REVIEWER` (subject to SoD) | `Actor` must not match `OwnerUser`, `CreatedBy`, or `SubmittedBy` (`ERR_SOD_VIOLATION`); sets `FinalStrategy = RecommendedStrategy` |
| `IN_REVIEW` | `OVERRIDE` | `overrideDecision` | `OVERRIDDEN` | `REVIEWER` (subject to SoD) | `Actor` must not match `OwnerUser`, `CreatedBy`, or `SubmittedBy` (`ERR_SOD_VIOLATION`); `Reason` >= 10 chars; valid `NewStrategy != RecommendedStrategy` (`ERR_OVERRIDE_SAME_STRATEGY`) |
| `IN_REVIEW` | `RETURN` | `returnDecision` | `RETURNED` | `REVIEWER` | `Reason` >= 10 chars explaining required correction/evidence |
| `APPROVED` | `START` | `startWork` | `IN_PROGRESS` | Assigned `DEVELOPER` (`Actor == OwnerUser`) | None |
| `OVERRIDDEN` | `START` | `startWork` | `IN_PROGRESS` | Assigned `DEVELOPER` (`Actor == OwnerUser`) | None |
| `IN_PROGRESS` | `BLOCK` | `blockWork` | `BLOCKED` | Assigned `DEVELOPER` (`Actor == OwnerUser`) | Blocker `Reason` >= 10 chars |
| `IN_PROGRESS` | `MARK_MIGRATED` | `markMigrated` | `MIGRATED` | Assigned `DEVELOPER` (`Actor == OwnerUser`) | Outcome `Reason` >= 10 chars |
| `BLOCKED` | `UNBLOCK` | `unblockWork` | `IN_PROGRESS` | Assigned `DEVELOPER` (`Actor == OwnerUser`) | Resolution `Reason` >= 10 chars |
| `BLOCKED` | `ASSIGN_OWNER` | `assignOwner` | `BLOCKED` | `REVIEWER` or `ADMIN` | Non-empty `NewOwner` |
| `APPROVED`, `OVERRIDDEN`, `IN_PROGRESS`, `BLOCKED` | `REOPEN` | `reopenDecision` | `IN_REVIEW` | `REVIEWER` or `ADMIN` | Reopen `Reason` >= 10 chars |
| `MIGRATED` | `REOPEN` | `reopenDecision` | `IN_REVIEW` | `ADMIN` only | Reopen `Reason` >= 10 chars; `REVIEWER` is rejected with `ERR_UNAUTHORIZED_ROLE` |

### Stable Server-Side Error Codes (`zccmc_cl_decision_workflow=>c_error`)

| Error Code | Trigger Condition |
|---|---|
| `ERR_INVALID_TRANSITION` | Action is not allowed in the decision's current `Status` (e.g., `PROPOSED -> APPROVED`, `APPROVED -> MIGRATED`, `APPROVED -> OVERRIDDEN`). |
| `ERR_UNAUTHORIZED_ROLE` | Authenticated principal lacks the required role for the action (e.g., `DEVELOPER` or `ADMIN` calling `APPROVE`/`OVERRIDE`, `REVIEWER` reopening `MIGRATED`, or `AUDITOR` calling any mutating action). |
| `ERR_SOD_VIOLATION` | Separation of Duties violation: Reviewer's user ID matches `OwnerUser`, `CreatedBy`, or `SubmittedBy` on `APPROVE` or `OVERRIDE`. |
| `ERR_NOT_ASSIGNED_OWNER` | A `DEVELOPER` attempts `SUBMIT`, `RESUBMIT`, `START`, `BLOCK`, `UNBLOCK`, or `MARK_MIGRATED` on a decision where `OwnerUser != ActorUser`. |
| `ERR_MISSING_OWNER` | `SUBMIT` is called when `OwnerUser` is blank, or `ASSIGN_OWNER` is called with a blank `NewOwner`. |
| `ERR_OWNER_ASSIGN_IN_REVIEW` | `ASSIGN_OWNER` is called while the decision is `IN_REVIEW`. |
| `ERR_MISSING_REASON` | Required reason/note is blank on `OVERRIDE`, `RETURN`, `RESUBMIT`, `BLOCK`, `UNBLOCK`, `MARK_MIGRATED`, or `REOPEN`. |
| `ERR_REASON_TOO_SHORT` | Supplied reason/note is shorter than `min_reason_len` (10 characters after trimming). |
| `ERR_INVALID_STRATEGY` | `RecommendedStrategy` or override `NewStrategy` is not one of the 5 contract strategies. |
| `ERR_OVERRIDE_SAME_STRATEGY` | `OVERRIDE` is called with `NewStrategy == RecommendedStrategy` (must use `APPROVE` instead). |
| `ERR_DUPLICATE_ACTIVE_DECISION` | `CREATE_FROM_RECOMMENDATION` is called for an `ObjectUUID` that already has a non-`MIGRATED` decision. |
| `ERR_STALE_CONCURRENCY_CONFLICT` | Caller's `expected_version` / ETag does not match the committed `VersionNo` / `ChangedAt`. |
| `ERR_AUDIT_IMMUTABLE` | Caller attempts `UPDATE` or `DELETE` on `ZCCMC_I_DecisionAudit`. |
| `ERR_MISSING_RECOMMENDATION_FIELD` | `ObjectUUID`, `RuleSetVersion`, `RecommendationRunID`, or `EvidenceSummary` is blank on creation, submission, or rerun. |
| `ERR_MISSING_ACTOR` | Request lacks an authenticated server-side `ActorUser`. |

## 5. Roles and Permissions Matrix

| Capability | `DEVELOPER` | `REVIEWER` | `ADMIN` | `AUDITOR` |
|---|---|---|---|---|
| Read decisions & audit trail | Yes | Yes | Yes | Yes (Read-only) |
| Create decision from recommendation | Yes | No | Yes | No |
| Submit / Resubmit decision | Own assigned (`Actor == OwnerUser`) | No | Yes | No |
| Approve / Override (`IN_REVIEW`) | No | Yes, if `Actor != OwnerUser, CreatedBy, SubmittedBy` (SoD) | No | No |
| Return for correction (`IN_REVIEW`) | No | Yes | No | No |
| Assign owner (`PROPOSED`, `RETURNED`, `BLOCKED`) | No | Yes | Yes | No |
| Start, Block, Unblock, MarkMigrated | Own assigned (`Actor == OwnerUser`) | No | No | No |
| Reopen non-migrated decision | No | Yes | Yes | No |
| Reopen `MIGRATED` decision | No | No | Yes | No |
| Modify or delete audit events | No | No | No | No |

## 6. Separation of Duties (SoD)

When `sod_enabled = abap_true` (the mandatory default), a principal cannot `APPROVE` or `OVERRIDE` a decision if their normalized user ID matches any of:
1. `OwnerUser` (the assigned developer),
2. `CreatedBy` (the creator of the decision), or
3. `SubmittedBy` (the user who last submitted/resubmitted the decision for review).

SoD checks the authenticated user identity (`ActorUser`), never just role membership: a user assigned both `DEVELOPER` and `REVIEWER` roles is still rejected with `ERR_SOD_VIOLATION` when attempting to review their own decision.

## 7. Append-Only Audit History

Every successful action appends an immutable `ty_audit_event` record (`ZCCMC_DECAUDIT`) in the same logical transaction, incrementing `SequenceNo` (`1, 2, 3, ...`) and `VersionNo`.

| Field | Content |
|---|---|
| `EventUUID` | Unique technical key (`{DecisionUUID}-EVT-{SequenceNo}`) |
| `DecisionUUID` | Parent decision identifier |
| `SequenceNo` | Contiguous 1-based sequence number per decision |
| `EventType` | Action name (`CREATE_FROM_RECOMMENDATION`, `SUBMIT`, `APPROVE`, `OVERRIDE`, `RETURN`, `RESUBMIT`, `ASSIGN_OWNER`, `START`, `BLOCK`, `UNBLOCK`, `MARK_MIGRATED`, `REOPEN`, `RECOMMENDATION_RERUN`) |
| `ActorUser` | Server-authenticated user ID |
| `EventTimestamp` | Server-generated UTC timestamp |
| `OldStatus` / `NewStatus` | Workflow status before and after the action |
| `OldStrategy` / `NewStrategy` | Effective strategy before and after the action |
| `OldOwner` / `NewOwner` | Assigned owner before and after the action |
| `Reason` | Justification / note supplied for the action |
| `RuleSetVersion` / `RecommendationRunID` | Traceability to the Member 2 recommendation |
| `CorrelationID` / `ImportBatchUUID` | Request correlation and Member 1 batch provenance |
| `SoDEnabled` | Records whether SoD enforcement was active |

## 8. Concurrency and Stale Updates

- In the domain workflow engine (`zccmc_cl_decision_workflow`), every mutation increments `version_no`. Passing a non-zero `iv_expected_version` that differs from the current `version_no` fails immediately with `ERR_STALE_CONCURRENCY_CONFLICT`.
- In the proposed RAP Behavior Definition (`zccmc_i_decision.bdef.asbdef`), `etag master ChangedAt` and `lock master` enforce OData V4 `If-Match` ETag concurrency checks.

## 9. Verification & Test Coverage (`WF-T01` .. `WF-T24`)

All 16 required test scenarios plus 8 integration/edge cases are implemented in:
- **ABAP Unit:** `src/zccmc_test/zccmc_ut_decision_workflow.clas.abap` (`t01` .. `t24`)
- **Offline Reference Oracle:** `tools/m3_workflow_oracle.py` (352 state/action/role matrix checks + 24 unit tests + 7-object Day-10 rehearsal; recorded in `docs/m3-golden-workflow-results.md`)
