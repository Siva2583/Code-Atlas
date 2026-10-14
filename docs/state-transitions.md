# State Transitions, Roles and Audit - DRAFT v0.1 (Member 3)

Status: DRAFT. Members 1, 2 and 4 please review. Statuses, action names and audit fields below become the contract for the MigrationDecision business object. None of them may change without a pull request that edits this file and a message to the team.
All sample data is DEMO / SYNTHETIC. Nothing here is connected to a live SAP system.

This document is design only. It names no release-specific ABAP or RAP syntax. Anything that depends on the target system (draft support, ETag/locking, feature control, authorization objects) must be verified on SAP Help Portal and in the Week-1 feasibility check.

## 0. How to read this (plain language)

- A decision is one record that says what we propose to do with one custom object (for example "retire it" or "rewrite it in RAP") and where that proposal is in the review process.
- The status says where it is in that process. A transition is a move from one status to another.
- An action is the button or call that causes a transition (Submit, Approve, Override, Return, ...).
- The rules in this file are enforced in the backend. Hiding a button in the Fiori UI is only a convenience; the backend must reject the call anyway.
- The system never deletes or migrates anything. A human records the outcome.

## 1. Decision statuses

| Status | Meaning |
|---|---|
| PROPOSED | A recommendation exists (from the rules engine) and the developer is preparing it. Editable. Nothing is decided. |
| IN_REVIEW | Submitted. Waiting for a reviewer. Locked for editing. |
| APPROVED | A reviewer accepted the recommended strategy as it is. |
| OVERRIDDEN | A reviewer chose a different strategy than the recommended one, with a mandatory reason. |
| RETURNED | A reviewer sent it back because evidence is missing or wrong. |
| IN_PROGRESS | The assigned owner started the modernization work. |
| BLOCKED | Work is stopped. A blocker reason is recorded. |
| MIGRATED | A human recorded that the work is done. Final unless an admin reopens it. |

The first seven are the statuses suggested in the task. BLOCKED is added because real work stalls, and without it the only exits from IN_PROGRESS would be MIGRATED or a reopen. Decision for the team: keep BLOCKED (recommended) or drop it.

Strategy values are Member 2's five outcomes, unchanged: KEEP_ADAPT, REWRITE_RAP, RETIRE_CANDIDATE, SIDE_BY_SIDE_BTP, MANUAL_REVIEW. The decision keeps two fields: RecommendedStrategy (set by the engine, never edited by people) and FinalStrategy (equals RecommendedStrategy unless overridden).

## 2. Allowed and illegal transitions

Rule: a transition is legal only if it is listed in the table below. Everything else is illegal (allow-list, not block-list).

### 2.1 Legal transitions

| # | From | To | Action | Who (details in section 3) |
|---|---|---|---|---|
| 1 | (new) | PROPOSED | Create from recommendation run | system, on behalf of the developer or admin who started the run |
| 2 | PROPOSED | IN_REVIEW | Submit | assigned owner (developer) or admin |
| 3 | RETURNED | IN_REVIEW | Submit (resubmit) | assigned owner (developer) or admin |
| 4 | IN_REVIEW | APPROVED | Approve | reviewer, subject to SoD |
| 5 | IN_REVIEW | OVERRIDDEN | Override | reviewer, subject to SoD |
| 6 | IN_REVIEW | RETURNED | Return | reviewer |
| 7 | APPROVED | IN_PROGRESS | Start | assigned owner |
| 8 | OVERRIDDEN | IN_PROGRESS | Start | assigned owner |
| 9 | IN_PROGRESS | MIGRATED | MarkMigrated | assigned owner |
| 10 | IN_PROGRESS | BLOCKED | Block | assigned owner |
| 11 | BLOCKED | IN_PROGRESS | Unblock | assigned owner |
| 12 | APPROVED, OVERRIDDEN, IN_PROGRESS, BLOCKED | IN_REVIEW | Reopen | reviewer or admin |
| 13 | MIGRATED | IN_REVIEW | Reopen | admin only |

That is 15 legal status changes in total (row 12 counts four). AssignOwner does not change the status (section 3).

### 2.2 Matrix (rows = from, columns = to; Y = legal, - = illegal)

| from \ to | PROPOSED | IN_REVIEW | APPROVED | OVERRIDDEN | RETURNED | IN_PROGRESS | BLOCKED | MIGRATED |
|---|---|---|---|---|---|---|---|---|
| PROPOSED | - | Y | - | - | - | - | - | - |
| IN_REVIEW | - | - | Y | Y | Y | - | - | - |
| APPROVED | - | Y | - | - | - | Y | - | - |
| OVERRIDDEN | - | Y | - | - | - | Y | - | - |
| RETURNED | - | Y | - | - | - | - | - | - |
| IN_PROGRESS | - | Y | - | - | - | - | Y | Y |
| BLOCKED | - | Y | - | - | - | Y | - | - |
| MIGRATED | - | Y | - | - | - | - | - | - |

### 2.3 Illegal transitions that matter most

| Illegal move | Why it is blocked |
|---|---|
| PROPOSED to APPROVED, OVERRIDDEN or IN_PROGRESS | Skips review. |
| IN_REVIEW to IN_PROGRESS or MIGRATED | Work cannot start before a decision exists. |
| RETURNED to APPROVED | A returned decision must be resubmitted and reviewed again. |
| APPROVED to MIGRATED | Skips IN_PROGRESS, so there is no record that work happened. |
| OVERRIDDEN to APPROVED (or the reverse) | A decision is approved or overridden by a review, never converted afterwards. Use Reopen. |
| anything to PROPOSED | PROPOSED exists only at creation. Rework goes through RETURNED or Reopen. |
| MIGRATED to anything except IN_REVIEW | Final. Only an admin Reopen, with a reason. |
| any status to itself | Not a change. |

Version 0.1 uses IN_REVIEW as the target of Reopen instead of adding a separate REOPENED status, so the reviewer must look at it again. Decision for the team: keep it simple like this (recommended) or add REOPENED.

## 3. Actions and who can do each one

Instance-level rule: a developer can act only on decisions where they are the assigned owner.

| Action | From status | Developer | Reviewer | Admin | Needs a reason |
|---|---|---|---|---|---|
| Submit | PROPOSED, RETURNED | yes (assigned owner) | no | yes | resubmit: a short response note |
| Approve | IN_REVIEW | no | yes (SoD) | no | no |
| Override | IN_REVIEW | no | yes (SoD) | no | yes, mandatory (section 5) |
| Return | IN_REVIEW | no | yes | no | yes, say what is missing |
| AssignOwner | PROPOSED, RETURNED, BLOCKED (no status change) | no | yes | yes | no |
| Start | APPROVED, OVERRIDDEN | yes (assigned owner) | no | no | no |
| Block | IN_PROGRESS | yes (assigned owner) | no | no | yes, the blocker |
| Unblock | BLOCKED | yes (assigned owner) | no | no | yes, how it was resolved |
| MarkMigrated | IN_PROGRESS | yes (assigned owner) | no | no | yes, outcome note |
| Reopen | APPROVED, OVERRIDDEN, IN_PROGRESS, BLOCKED | no | yes | yes | yes |
| Reopen | MIGRATED | no | no | yes | yes |

Notes:
- Submit needs an assigned owner, a RecommendedStrategy, and a recorded rule-set version and evidence summary. Without an owner, separation of duties could not be checked.
- AssignOwner is not allowed while IN_REVIEW, so nobody can swap the owner after submitting to get around the SoD check.
- Admin can Submit (to unblock a team) but cannot Approve or Override. This is deliberate; see section 7.

## 4. Separation-of-duties (SoD) rule

Rule: the person who prepared or owns a decision can never approve or override it.

For one decision, the conflicted users are:
1. the assigned owner (OwnerUser), and
2. the user who created the decision (CreatedBy), and
3. the user who last submitted it (SubmittedBy).

Approve and Override are rejected if the acting user is any of these. The check is on the user identity, not on the role. A person who holds both the developer and reviewer role is still blocked on their own decisions.

- Applies to: Approve, Override. Not to Return (sending something back is harmless).
- Enforced in the backend on every call. Hiding the button is not enough.
- Configurable: a setting SoD_ENABLED, default on. When it is off, the audit event records that SoD was off (AC-04 says "when SoD is enabled").
- Demo needs at least two users per role, or a documented role-switch test plan.

## 5. Override rule

Rule: an override needs a reason, with no exceptions.

- The reason is mandatory. It must not be empty or only spaces, and it needs a minimum length (illustrative: 10 characters, configurable).
- The new strategy must be one of the five outcomes and must differ from RecommendedStrategy. Otherwise it is an Approve, not an Override.
- FinalStrategy is set to the new strategy. RecommendedStrategy is never changed, so the original engine result is always visible.
- The reason, old strategy and new strategy are written to the audit event in the same transaction as the change.
- The same "reason is mandatory" rule applies to Return, Block, Unblock, MarkMigrated and Reopen.
- Not in MVP: a second approval for overrides of high-risk objects (stand-out feature, only after the MVP is stable).

## 6. Audit events

Every status, strategy or owner change appends one audit event in the same transaction as the change. Events are append-only: no update and no delete are exposed, and the timestamp and actor are set by the server, never taken from the client.

| Field | Meaning |
|---|---|
| EventUUID | Technical key of the event |
| DecisionUUID | Link to the decision (see below) |
| SequenceNo | 1, 2, 3 ... per decision, no gaps. Unique together with DecisionUUID |
| EventType | CREATED, SUBMITTED, APPROVED, OVERRIDDEN, RETURNED, OWNER_ASSIGNED, STARTED, BLOCKED, UNBLOCKED, MIGRATED, REOPENED |
| ActorUser | The user who did it |
| EventTimestamp | UTC timestamp, server time |
| OldStatus, NewStatus | Status before and after (empty old status on CREATED) |
| OldStrategy, NewStrategy | Final strategy before and after |
| OldOwner, NewOwner | Owner before and after (for owner changes) |
| Reason | The reason text. Mandatory where section 3 says so |
| RuleSetVersion | Rule-set version of the recommendation this decision rests on |
| RecommendationRunID | The engine run that produced the recommendation |
| CorrelationID | Groups events from one user request or bulk action |
| ImportBatchUUID | Optional. The import batch of the evidence, where relevant (data-contract section 6) |
| SoDEnabled | Whether SoD was on when an Approve or Override was checked |

How an audit event links to a decision:
- AuditEvent.DecisionUUID points to MigrationDecision.DecisionUUID. Many events belong to one decision (child of the decision in the business object, created in its transaction).
- MigrationDecision.ObjectUUID points to CustomObject.ObjectUUID, so a full history reads: event, decision, object.
- Decisions are never deleted, so the history cannot be orphaned.

## 7. Roles

| Role | Can do | Cannot do |
|---|---|---|
| Developer | Read decisions. Prepare evidence. Run a recommendation. On their own assigned decisions only: Submit, Start, Block, Unblock, MarkMigrated | Approve, Override, Return, Reopen, AssignOwner, manage rules |
| Reviewer | Read all decisions and audit. Approve, Override, Return, AssignOwner, Reopen (not MIGRATED), all subject to SoD | Submit, Start, MarkMigrated, manage rules |
| Admin | Manage and publish rule sets. AssignOwner. Reopen (the only role that can reopen MIGRATED). Submit. Read all decisions and audit | Approve, Override |
| Auditor (optional, read-only) | Read decisions and the full audit history | Everything else |

Why admin cannot approve: an administrator who manages the rules and can also approve decisions would remove the independent review that is the point of the cockpit. If the team wants an emergency approver, make it a separate, logged setting.

The Auditor role comes from the project guide and is not in the task list; it is cheap (read only), so it is proposed here. Decision for the team.

## 8. Review of Member 1's data contract (item 8)

Reviewed: docs/data-contract.md (DRAFT v0.1) and, for the producer side, docs/rules-spec.md. Not reviewed: the table and CDS files in src/zccmc_data. At the time of this review they are empty files, so ObjectUUID's real type is unverified.

Answer: yes, ObjectUUID is the link Member 3 needs. The contract calls it the technical key of CustomObject, with the external key (SourceSystemID + ObjectType + ObjectName) unique beside it. MigrationDecision.ObjectUUID links to it.

Conditions that must hold (please confirm, Member 1):
1. ObjectUUID is created once, on first insert, and is never regenerated. Re-importing the same batch (AC-01) must keep the same ObjectUUID. If a loader ever deletes and re-inserts a row, every decision on it is orphaned.
2. The external key cannot be renamed. If it can change, say how the UUID is handled.
3. Objects missing from a later import are never deleted. Only last_seen moves. Decisions are never removed by an import.
4. Please give the type of ObjectUUID and DecisionUUID (for example 16-byte UUID vs 36-character string) once the tables exist, so Member 3 uses the same one.

Other findings:
- The contract says audit events link to "the ImportBatch ID". The entity key is BatchUUID. Please use BatchUUID everywhere. Section 6 here uses ImportBatchUUID.
- business_owner (objects.csv) is a free-text business attribute, not an SAP user ID. The assigned owner used for SoD must be a system user ID, so it needs its own field on the decision (OwnerUser). Do not use business_owner for SoD.
- There is no limit on decisions per object in the contract. Member 3 proposes: at most one active decision per ObjectUUID, where active means any status except MIGRATED. A new decision for the same object is allowed only after the previous one is MIGRATED. Please confirm with Member 2.

What Member 3 consumes from Member 2 (to agree before coding): ObjectUUID, RecommendedStrategy (the five outcomes), RuleSetVersion, RecommendationRunID, and an evidence summary or explanation text. rules-spec.md says every result records the rule-set version, but does not yet name a run ID. Please add RecommendationRunID.

What Member 3 exposes to Member 4: the status and action names in sections 1 to 3, the audit fields in section 6, and the rule that the backend decides which actions are allowed (the UI reads that, it does not decide it).

## 9. Paper tests (14)

Each is a test for the later ABAP Unit or RAP test classes. Expected result for every rejection: the status is unchanged and no audit event is written.

| # | Case | Expected |
|---|---|---|
| P1 | Owner assigned, developer submits PROPOSED | IN_REVIEW. One SUBMITTED event, SequenceNo continues, old PROPOSED, new IN_REVIEW |
| P2 | Submit with no owner assigned | Rejected |
| P3 | PROPOSED straight to APPROVED | Rejected (illegal transition) |
| P4 | APPROVED straight to MIGRATED | Rejected (illegal transition) |
| P5 | Reviewer approves a decision they do not own, SoD on | APPROVED. Event has actor, server time, old IN_REVIEW, new APPROVED |
| P6 | Reviewer who is the assigned owner tries to approve, SoD on | Rejected (SoD) |
| P7 | A user holding both developer and reviewer roles submitted it (owner is someone else) and tries to approve | Rejected (SoD) |
| P8 | Same as P6 with SoD off by configuration | Approved, and the event records SoD off |
| P9 | Override with an empty or spaces-only reason | Rejected |
| P10 | Override with a valid reason but the same strategy as recommended | Rejected |
| P11 | Valid override | OVERRIDDEN. RecommendedStrategy unchanged, FinalStrategy new, old and new strategy and the reason in the event |
| P12 | Developer calls Approve directly on the backend while the UI hides the button | Rejected (authorization), not just hidden |
| P13 | Admin calls Approve | Rejected (role) |
| P14 | Reviewer reopens MIGRATED | Rejected. Admin reopens with a reason: IN_REVIEW |

Also test: updating or deleting an audit event is impossible; two reviewers acting on the same decision at once (the second one gets a conflict, not a silent overwrite); a second active decision for the same ObjectUUID is rejected; each role against each action in section 3.

## 10. Limitations and open points

- Design only. No RAP behavior definition, CDS or ABAP exists for MigrationDecision yet, and nothing here has been tested on a system.
- Authorization design (a custom authorization object, role names) is to be agreed; names will be set in implementation and are not fixed here.
- Draft handling, ETag/locking and feature control depend on the target release. Verify in the Week-1 feasibility check and keep a documented fallback.
- Minimum reason length, SoD default and the admin-cannot-approve choice are illustrative and configurable. Have a reviewer from the migration or governance side validate them.
- Denied attempts (rejected calls) are not audited in the MVP; only successful changes are.
- The cockpit recommends and records. It never retires, deletes or migrates anything.

## 11. Decisions that need the team

1. Keep BLOCKED as a status (recommended).
2. Reopen goes to IN_REVIEW instead of a separate REOPENED status (recommended).
3. Admin cannot approve or override (recommended).
4. Add the read-only Auditor role (recommended).
5. At most one active decision per ObjectUUID (needs Member 1 and Member 2).
6. Rename the contract's "ImportBatch ID" to BatchUUID, and add RecommendationRunID to the rules output.