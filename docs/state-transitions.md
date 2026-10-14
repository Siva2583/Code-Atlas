# Migration Decision Workflow, Security and Audit

**Owner:** Member 3 — RAP Workflow & Security
**Version:** 0.2 — Proposed for team review
**Status:** NOT FROZEN — requires review from Members 1, 2 and 4 before implementation
**Scope:** Migration Decision business object, workflow actions, backend authorization and audit history.

All examples and test data must be synthetic. The cockpit records human decisions; it does not automatically migrate, retire or delete SAP objects.

## 1. Purpose

Each Migration Decision connects one custom object to a recommendation from Member 2's rules engine. It records the review outcome, assigned owner, current workflow status and history of changes.

The RAP backend is the authority for whether an action is allowed. Hiding an action in the Fiori UI is not authorization.

## 2. Decision fields

The implementation must coordinate these fields with the owning team members before finalizing the physical data model.

| Field                 | Purpose                                                                                         |
| --------------------- | ----------------------------------------------------------------------------------------------- |
| DecisionUUID          | Stable technical identifier for a decision                                                      |
| ObjectUUID            | Link to Member 1's persisted custom object                                                      |
| RecommendedStrategy   | Original recommendation produced by Member 2; never manually overwritten                        |
| FinalStrategy         | Strategy currently accepted for the decision                                                    |
| RuleSetVersion        | Version of the rules used to produce the recommendation                                         |
| RecommendationRunID   | Identifies the recommendation run                                                               |
| Status                | Current workflow status                                                                         |
| OwnerUser             | Assigned system user responsible for the work; not the free-text business owner                 |
| CreatedBy             | User who created the decision                                                                   |
| SubmittedBy           | User who last submitted it for review                                                           |
| CreatedAt / ChangedAt | Server-maintained timestamps                                                                    |
| EvidenceSummary       | Evidence or explanation associated with the recommendation, subject to the agreed data contract |

The physical types, mandatory fields and exact source names must match the agreed Member 1 and Member 2 contracts. Do not invent or silently rename fields during implementation.

**Proposed uniqueness rule:** allow at most one active decision per `ObjectUUID`. A decision is considered inactive after it reaches `MIGRATED`. Members 1 and 2 must approve this rule before it is frozen.

## 3. Workflow statuses

| Status        | Meaning                                                    |
| ------------- | ---------------------------------------------------------- |
| `PROPOSED`    | Recommendation exists and is being prepared                |
| `IN_REVIEW`   | Submitted and awaiting reviewer action                     |
| `APPROVED`    | Recommended strategy accepted                              |
| `OVERRIDDEN`  | Reviewer selected a different strategy with a reason       |
| `RETURNED`    | Reviewer sent the decision back for correction or evidence |
| `IN_PROGRESS` | Assigned owner has started the work                        |
| `BLOCKED`     | Work cannot continue until a blocker is resolved           |
| `MIGRATED`    | A human recorded completion of the modernization work      |

`BLOCKED` is proposed as an additional status. Team approval is required before it becomes part of the frozen contract.

These names must also be reconciled with any alternative status names in the project blueprint. Do not silently introduce aliases or implement two competing status vocabularies.

## 4. Allowed transitions and actions

Only the transitions listed below are allowed. Every other transition must be rejected.

| Current status | Action                     | New status    | Authorized actor                          |
| -------------- | -------------------------- | ------------- | ----------------------------------------- |
| New decision   | Create from recommendation | `PROPOSED`    | Authorized creation flow                  |
| `PROPOSED`     | Submit                     | `IN_REVIEW`   | Assigned developer or admin               |
| `RETURNED`     | Resubmit                   | `IN_REVIEW`   | Assigned developer or admin               |
| `IN_REVIEW`    | Approve                    | `APPROVED`    | Reviewer, subject to separation of duties |
| `IN_REVIEW`    | Override                   | `OVERRIDDEN`  | Reviewer, subject to separation of duties |
| `IN_REVIEW`    | Return                     | `RETURNED`    | Reviewer                                  |
| `APPROVED`     | Start                      | `IN_PROGRESS` | Assigned developer                        |
| `OVERRIDDEN`   | Start                      | `IN_PROGRESS` | Assigned developer                        |
| `IN_PROGRESS`  | MarkMigrated               | `MIGRATED`    | Assigned developer                        |
| `IN_PROGRESS`  | Block                      | `BLOCKED`     | Assigned developer                        |
| `BLOCKED`      | Unblock                    | `IN_PROGRESS` | Assigned developer                        |
| `APPROVED`     | Reopen                     | `IN_REVIEW`   | Reviewer or admin                         |
| `OVERRIDDEN`   | Reopen                     | `IN_REVIEW`   | Reviewer or admin                         |
| `IN_PROGRESS`  | Reopen                     | `IN_REVIEW`   | Reviewer or admin                         |
| `BLOCKED`      | Reopen                     | `IN_REVIEW`   | Reviewer or admin                         |
| `MIGRATED`     | Reopen                     | `IN_REVIEW`   | Admin only                                |

`AssignOwner` is a separate action that changes the owner without changing the status. It is allowed only in `PROPOSED`, `RETURNED` or `BLOCKED`, and only for a reviewer or admin.

Reopening a decision requires a reason. `MIGRATED` is final unless an admin reopens it.

The backend must reject, at minimum:

* Skipping review, such as `PROPOSED` directly to `APPROVED`.
* Starting work before approval or override.
* Moving directly from `APPROVED` to `MIGRATED`.
* Returning a decision directly to `APPROVED` without resubmission and review.
* Changing `APPROVED` to `OVERRIDDEN`, or vice versa, without reopening and reviewing again.
* Any transition to `PROPOSED` after creation.
* Any unsupported status change or a transition to the same status.

## 5. Roles and permissions

| Capability                             | Developer             | Reviewer                             | Admin | Auditor |
| -------------------------------------- | --------------------- | ------------------------------------ | ----- | ------- |
| Read decisions                         | Yes                   | Yes                                  | Yes   | Yes     |
| Submit own assigned decision           | Yes                   | No                                   | Yes   | No      |
| Approve                                | No                    | Yes, subject to separation of duties | No    | No      |
| Override                               | No                    | Yes, subject to separation of duties | No    | No      |
| Return for correction                  | No                    | Yes                                  | No    | No      |
| Assign owner                           | No                    | Yes                                  | Yes   | No      |
| Start, block, unblock or mark migrated | Own assigned decision | No                                   | No    | No      |
| Reopen a non-migrated decision         | No                    | Yes                                  | Yes   | No      |
| Reopen a migrated decision             | No                    | No                                   | Yes   | No      |
| Manage rules                           | No                    | No                                   | Yes   | No      |
| Change or delete audit events          | No                    | No                                   | No    | No      |

The Auditor role is proposed as read-only and needs team confirmation. Actual SAP role assignments and authorization mechanisms must be verified in the target environment.

A developer may perform developer actions only on decisions assigned to them.

## 6. Separation of duties

When separation of duties (SoD) is enabled, the following users cannot approve or override the same decision:

* The assigned owner (`OwnerUser`).
* The decision creator (`CreatedBy`).
* The last submitter (`SubmittedBy`).

Check user identity, not merely role membership. A user holding both developer and reviewer roles must still be blocked from approving or overriding a decision they prepared or own.

SoD must be enforced in the backend for every action call. A UI restriction alone is insufficient.

The draft proposes SoD enabled by default. Any ability to disable it, its authorization and its audit implications require team and security approval before implementation.

## 7. Validation rules

* Submit requires an assigned owner, a valid recommended strategy, a rule-set version, a recommendation run ID and the agreed evidence summary.
* Override requires a non-empty reason and a valid strategy different from `RecommendedStrategy`.
* `RecommendedStrategy` remains unchanged after an override; `FinalStrategy` records the selected strategy.
* Return requires a reason describing what needs correction or additional evidence.
* Block requires a blocker reason.
* Unblock requires a resolution note.
* MarkMigrated requires an outcome note.
* Reopen requires a reason.
* Resubmission requires the agreed response note.
* Owner assignment must be rejected while the decision is `IN_REVIEW`.
* A second active decision for the same object must be rejected if the proposed uniqueness rule is approved.
* Invalid transitions, invalid values, missing reasons and unauthorized calls must not partially update the decision.

A minimum reason length of 10 characters is illustrative only; the team must confirm it before implementation.

## 8. Audit history

Every successful status, strategy or owner change must append an audit event in the same logical transaction as the decision change.

Proposed audit fields:

| Field                     | Purpose                                                                                                        |
| ------------------------- | -------------------------------------------------------------------------------------------------------------- |
| EventUUID                 | Unique audit event identifier                                                                                  |
| DecisionUUID              | Decision being changed                                                                                         |
| SequenceNo                | Ordered sequence number for that decision                                                                      |
| EventType                 | Creation, submission, approval, override, return, owner assignment, start, block, unblock, migration or reopen |
| ActorUser                 | Authenticated user who performed the action                                                                    |
| EventTimestamp            | Server-generated UTC timestamp                                                                                 |
| OldStatus / NewStatus     | Status before and after the action                                                                             |
| OldStrategy / NewStrategy | Strategy before and after the action                                                                           |
| OldOwner / NewOwner       | Owner before and after assignment changes                                                                      |
| Reason                    | Reason supplied for actions that require one                                                                   |
| RuleSetVersion            | Rule version associated with the recommendation                                                                |
| RecommendationRunID       | Recommendation run identifier                                                                                  |
| CorrelationID             | Groups events associated with the same request, if supported                                                   |
| ImportBatchUUID           | Related evidence import batch, when applicable                                                                 |
| SoDEnabled                | Whether SoD was enabled for the approval or override check                                                     |

Audit history must be append-only: no update or delete operation should be exposed. Actor and timestamp must come from trusted server-side context, not client-supplied values.

If the decision update or audit write fails, the operation must not leave a partially applied change. A rejected action must leave the decision state unchanged and must not create a successful-change audit event.

## 9. Concurrency and stale updates

The implementation must prevent a stale request from silently overwriting a newer decision.

Verify the target environment's supported RAP locking, ETag or equivalent concurrency mechanism. Use a mechanism supported by the actual release and service configuration. Do not claim stale-update protection until it has been tested.

When two users attempt conflicting updates, the later stale request must receive a conflict or validation error, and the first committed decision and audit history must remain intact.

## 10. Required tests

Use ABAP Unit or the supported test mechanism available in the target environment. Record actual execution results; this section defines expected behavior, not proof that tests have passed.

1. Assigned developer submits a valid `PROPOSED` decision.
2. Submission without an owner is rejected.
3. Illegal transitions are rejected.
4. Reviewer approves a decision they are permitted to review.
5. Owner, creator or last submitter cannot approve or override when SoD is enabled.
6. A developer calling Approve directly is rejected by the backend.
7. An admin attempting Approve or Override is rejected.
8. Override with a blank reason is rejected.
9. Override using the same strategy as the recommendation is rejected.
10. Valid override preserves `RecommendedStrategy` and records the new `FinalStrategy` and reason.
11. Return, Block, Unblock, MarkMigrated and Reopen enforce their required reasons.
12. Audit events cannot be modified or deleted through the exposed service.
13. Concurrent stale updates do not silently overwrite the committed decision.
14. A second active decision for the same object is rejected if the uniqueness rule is approved.
15. Reopening `MIGRATED` is rejected for a reviewer and allowed only for an authorized admin.
16. Every rejected action leaves the decision unchanged and creates no successful-change audit event.

## 11. Dependencies and team sign-off

**Member 1 — data and import**

* Confirm the stable `ObjectUUID` and its physical type.
* Confirm the agreed data contract and import batch identifier (`BatchUUID`).
* Ensure object UUIDs remain stable across re-imports and objects are not deleted by routine imports.

**Member 2 — rules engine**

* Confirm the strategy values: `KEEP_ADAPT`, `REWRITE_RAP`, `RETIRE_CANDIDATE`, `SIDE_BY_SIDE_BTP`, `MANUAL_REVIEW`.
* Confirm `RuleSetVersion`, `RecommendationRunID` and the recommendation/evidence summary supplied to the decision business object.
* Review the proposed one-active-decision-per-object rule.

**Member 4 — Fiori UI**

* Align UI actions and status labels with this contract.
* Use backend action availability and backend errors rather than treating hidden buttons as security.
* Confirm how reasons, status changes and audit history are displayed.

**All members**

Review and agree on the status vocabulary, `BLOCKED`, reopen behavior, Auditor role, SoD policy, minimum reason length, and one-active-decision rule. Resolve any conflicting status names in the project blueprint before freezing the contract.

## 12. Implementation limitations

This document is a workflow design, not proof of a working RAP implementation.

The following remain unverified until demonstrated on the assigned SAP environment:

* Exact ABAP release and supported RAP syntax.
* Business object activation and service binding.
* OData version and service exposure.
* Available identity and authorization APIs.
* Locking, ETag and stale-update behavior.
* Supported audit persistence and transaction behavior.

Record unsupported capabilities and the smallest supported fallback in `docs/feasibility-note.md` and `docs/limitations.md`. Do not claim an unsupported feature or successful test.

The cockpit remains a human decision and governance tool; it does not execute migrations, retirements or deletions automatically.
