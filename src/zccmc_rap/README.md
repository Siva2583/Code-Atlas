# M3 RAP Implementation Plan — First Working Slice

**Owner:** Member 3 — RAP Workflow & Security  
**Branch:** `feature/m3-rap-workflow`  
**Status:** implementation plan; backend artifacts and activation are not yet verified  
**Scope:** Migration Decision business object, backend-enforced workflow, audit, concurrency, and service exposure.

This plan is deliberately tied to the repository's current contracts. It does not freeze proposed fields/statuses or assert that any SAP artifact activates. All demonstrations use synthetic data. No action in this workflow automatically migrates, retires, or deletes a source object.

## First slice and dependencies

Build the smallest end-to-end path first:

1. Resolve the backend development package using the existing VS Code-only workflow; record the package name and system/release evidence. Do not substitute `$TMP` for a shared package without an explicit decision.
2. Confirm the fields available from the persistence/recommendation contracts and settle the status vocabulary with M1, M2, and M4. Current inputs are candidates, not a frozen contract.
3. Create the decision persistence entity and RAP root CDS entity, then activate and record the actual result.
4. Add the behavior definition and implementation with only the agreed initial workflow action(s); verify rejected transitions server-side.
5. Add append-only decision audit history in the same logical transaction as successful actions.
6. Add service definition and binding; call this project's service rather than relying on the generic OData catalogs.
7. Verify authorization/SoD using trusted backend identity and supported role checks; then test stale-update behavior with the release-supported mechanism.
8. Add tests for legal/illegal transitions, direct unauthorized action calls, SoD, required reasons, audit integrity, and stale updates.

## Proposed source artifact inventory

These are planned repository artifacts, not proof of generated or activated SAP objects. Physical field types and names must follow the cross-team contract and the target release.

| Artifact role | Suggested repository path | Dependency / gate |
|---|---|---|
| Migration Decision root CDS view entity | `src/zccmc_rap/zccmc_i_decision.ddls.asddls` | Decision persistence fields agreed with M1/M2 |
| Decision root behavior definition | `src/zccmc_rap/zccmc_i_decision.bdef.asbdef` | Root CDS activated |
| Behavior implementation class | `src/zccmc_rap/zbp_ccmc_i_decision.clas.abap` | Actual behavior pool naming/type verified by VS Code generator |
| Decision projection, if required by service/UI contract | `src/zccmc_rap/zccmc_c_decision.ddls.asddls` | Service shape agreed with M4 |
| Service definition | `src/zccmc_rap/zccmc_ui_decision.srvd.srvdsrv` | CDS entities activated |
| Service binding | Backend-generated/managed artifact; record actual name and type | Binding type and OData version verified on tenant |
| Audit persistence and read entity | Coordinate physical table/CDS ownership with M1 before adding | Append-only / transactional semantics verified |
| RAP workflow tests | `src/zccmc_rap/` behavior test artifact(s) or agreed test package | Use only syntax/runtime supported on target release |

The exact generated filenames/extensions must match the VS Code ABAP tooling and the ABAP object type actually created. Do not hand-author repository serialization formats and call them activatable without confirming the tool's export format.

## Contract gates before behavior implementation

The current `docs/state-transitions.md` is proposed and not frozen. Resolve at minimum:

- Canonical statuses: workflow document uses `PROPOSED`, `IN_REVIEW`, `APPROVED`, `OVERRIDDEN`, `RETURNED`, `IN_PROGRESS`, `BLOCKED`, `MIGRATED`; other project material uses a different vocabulary. Select one shared vocabulary rather than silently aliasing them.
- Role and SoD policy: Developer / Reviewer / Admin / proposed read-only Auditor; reviewers may not approve/override decisions they prepared, own, or last submitted when SoD is enabled.
- Reasons: minimum length and which of Override, Return, Block, Unblock, Reopen and MarkMigrated require reasons.
- Fields: `DecisionUUID`, `ObjectUUID`, `RecommendedStrategy`, `FinalStrategy`, `RuleSetVersion`, `RecommendationRunID`, `Status`, `OwnerUser`, `CreatedBy`, `SubmittedBy`, timestamps and `EvidenceSummary`, with exact names/types confirmed against M1/M2.
- One active decision per `ObjectUUID`: M2's rules handover does not object, but retain as proposed until cross-team agreement.

No UI-only hiding counts as authorization. The backend must reject forbidden calls. Actor and timestamps must come from trusted backend context; audit rows must not expose update/delete actions. Failure to record the audit event must not leave a successful state change partially applied.

## Verification ledger (must be based on observed tenant results)

| Check | Evidence required | Initial status |
|---|---|---|
| Package | Name, software component/ownership, and supported VS Code workflow | NOT VERIFIED |
| Release/object generation | Product/release details and generated object file format | NOT VERIFIED |
| Persistence + root CDS | Create and activate an agreed minimum entity | NOT VERIFIED |
| Behavior/actions | Activation plus legal and illegal action calls | NOT VERIFIED |
| Backend identity/authorization | Prove trusted principal and server-side role denial | NOT VERIFIED |
| SoD | Creator/owner/submitter denied approval/override when enabled | NOT VERIFIED |
| Audit | Successful transition records actor/time/old-new state/reason; failure is atomic; no update/delete exposed | NOT VERIFIED |
| Concurrency | Stale conflicting update rejected without overwriting committed state | NOT VERIFIED |
| Service exposure | Own service definition/binding activated and endpoint called successfully | NOT VERIFIED |
| Tests | Actual ABAP Unit/test execution output captured | NOT VERIFIED |

## 11-day delivery alignment

- **Day 1:** package/release/object creation/activation/identity/authorization capability probe.
- **Day 2:** shared workflow + field contract freeze.
- **Day 3:** smallest activated root entity, behavior, service skeleton.
- **Days 4–5:** decision creation, submit/review/return/override/assignment and owner workflow actions, only after sign-off.
- **Day 6:** backend authorization, SoD, audit atomicity, stale-update mechanism.
- **Day 7:** service exposure/error contract integration with M4 and recommendation/persistence contract with M1/M2.
- **Days 8–9:** negative tests and fixes.
- **Day 10:** end-to-end synthetic walkthrough.
- **Day 11:** demo/release evidence and explicit unresolved blockers.

**Definition of done:** activated artifacts and test evidence from the assigned SAP environment, or a precise blocker record. A source file existing in Git is not an activation result.
