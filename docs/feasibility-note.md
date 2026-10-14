# RAP Workflow and Security Feasibility Note

**Owner:** Member 3 — RAP Workflow & Security  
**Version:** 0.2  
**Status:** IN PROGRESS — capabilities require tenant evidence  
**Branch:** `feature/m3-rap-workflow`

## 1. Purpose

Record what was actually observed while connecting VS Code to the assigned SAP BTP ABAP Environment,
then verify RAP, authorization, concurrency and service capabilities before implementation.

A successful connection or service-catalog lookup is not proof that project objects can be created,
activated, authorized or exposed. Mark a capability **VERIFIED** only when the stated check was observed.

## 2. Environment details

| Item | Current finding |
|---|---|
| Development client | VS Code with SAP ABAP Development Tools extension (user explicitly uses VS Code; Eclipse is not part of this workflow) |
| SAP environment | SAP BTP ABAP Environment trial, as described by the user |
| Connection label in VS Code | `Code-Atlas-TRL (ABAP Cloud)` |
| Workspace destination/folder label | `BTP_DEV` |
| Trial environment description shared by user | `TRL — Shared Trial US10 — 2026/08` |
| Connection URL | User entered the ABAP environment HTTPS URL; do not copy the full URL into repository documentation |
| Authentication/logon | **VERIFIED:** user reported “logon successful” after `ABAP: Log On to Destination…` |
| OData catalog reachability | **VERIFIED:** VS Code showed OData V2 catalog and OData V4 catalog results after test connection; the displayed counts varied between calls (430/806, later 432/809). Counts are transient catalog results, not project service counts or RAP readiness evidence. |
| ABAP release/version | NOT VERIFIED |
| Approved project package | NOT VERIFIED |
| `$TMP` | Visible in the workspace as “Local Objects ($TMP)”; do not treat this as a transportable project package |
| Software component / package ownership | NOT VERIFIED |
| Repository object create permission | NOT VERIFIED — no project artifact has been created |
| Activation permission/result | NOT VERIFIED |
| Transport/change-recording requirements | NOT VERIFIED / needs trial-specific confirmation |

No password, token, service key, client secret or full system URL belongs in this document.

## 3. Capability checklist

Statuses:
- **VERIFIED** — directly observed and recorded below.
- **NOT VERIFIED** — not checked or evidence is insufficient.
- **BLOCKED** — a concrete attempt failed due to permission, environment or technical limitation.
- **NOT AVAILABLE** — evidence confirms the capability is unavailable.

| ID | Capability | Verification action | Status | Evidence / notes |
|---|---|---|---|---|
| F-01 | Reach the intended ABAP environment | Test connection, then log on to the destination | VERIFIED (connection only) | Catalog test returned V2/V4 service lists; user reported logon successful. |
| F-02 | Approved development package | Identify an existing suitable package or create a project package using a supported command | NOT VERIFIED | The workspace shows `$TMP`; VS Code “Create New ABAP Object” list did not show Package when searched. This does not prove package creation is unavailable by every supported route. |
| F-03 | ABAP release | Inspect connected system/product information | NOT VERIFIED | No release information observed yet. |
| F-04 | Repository object creation | Create a permitted test object in an approved package | NOT VERIFIED | No project object created; do not create project artifacts in `$TMP` as a substitute for a shared package. |
| F-05 | Activation | Activate an approved test object and record actual result | NOT VERIFIED | No activation attempted for a project artifact. |
| F-06 | CDS view entity | Activate a minimal permitted CDS view entity | NOT VERIFIED | Object type appears in the VS Code object-creation list, but support/activation is untested. |
| F-07 | RAP business object | Create and activate the minimum agreed RAP artifacts | NOT VERIFIED | Visibility of individual object types in the IDE is not activation proof. |
| F-08 | RAP actions and validations | Verify required action/validation behavior in an activated BO | NOT VERIFIED | No RAP BO has been created. |
| F-09 | ABAP Unit | Execute a permitted test in the assigned package | NOT VERIFIED | No project ABAP Unit test run recorded. |
| F-10 | Authorization model | Identify the supported backend authorization mechanism | NOT VERIFIED | Do not assume an API or role model. |
| F-11 | Current authenticated principal | Verify the trusted backend identity source | NOT VERIFIED | UI username is not enough evidence. |
| F-12 | Developer/Reviewer/Admin/Auditor role checks | Verify actual role assignment/check mechanism | NOT VERIFIED | Workflow role model remains proposed. |
| F-13 | Instance authorization | Demonstrate backend rejection of forbidden calls | NOT VERIFIED | UI-only hiding does not count. |
| F-14 | ETag/locking/stale updates | Demonstrate supported stale-update rejection | NOT VERIFIED | No concurrency test executed. |
| F-15 | Service definition | Create and activate the project service definition | NOT VERIFIED | Generic object type is listed by the extension, but our artifact is not created. |
| F-16 | Service binding | Create and activate an appropriate binding | NOT VERIFIED | Generic object type is listed by the extension, but our artifact is not created. |
| F-17 | Project OData service | Access our own activated service endpoint | NOT VERIFIED | Catalog reachability proves only connection to catalogs, not a project service. |
| F-18 | Fiori Elements preview | Preview our own activated service | NOT VERIFIED | Not attempted. |
| F-19 | Fiori Elements generation/deployment | Verify a permitted deployment route | NOT VERIFIED | Not attempted. |
| F-20 | Synthetic test data | Create/reset synthetic decisions using a tenant-approved process | NOT VERIFIED | Synthetic-only requirement remains. |
| F-21 | Integration with Member 1 import | Verify an agreed import path and stable `ObjectUUID` correlation | NOT VERIFIED | Contract and importer implementation/activation are not yet complete. |
| F-22 | Required CDS aggregation | Verify only if the agreed workflow/UI contract needs it | NOT VERIFIED | Not attempted. |

## 4. Workflow/data contract coordination

The workflow proposal in `docs/state-transitions.md` is **not frozen**. Relevant confirmed repository inputs and open decisions:

- Member 1's `docs/data-contract.md` is candidate v0.2, not signed. `ObjectUUID` is generated by persistence; the external custom-object key is normalized `source_system + object_type + object_name`. Routine re-imports must not delete omitted objects or earlier provenance.
- Member 1 proposes the optional `objects.findings_as_of` field; M2 says it resolves the loaded-versus-no-findings ambiguity but the candidate needs cross-team agreement before treated as frozen.
- Member 2's rules handover lists `ObjectUUID`, `RecommendationRunID`, `RecommendedStrategy`, `RuleSetVersion`, `Explanation`, `MissingEvidence`, `MatchedRuleIDs` and `RunTimestamp`. The type for `RecommendationRunID` remains open until the tenant UUID choice is known.
- Member 2's rules spec explicitly says it has no objection to at most one active decision per `ObjectUUID`, and reruns revise the existing decision rather than create another active decision. Align the workflow wording with this and retain it as proposed until shared approval.
- Workflow status names, the additional `BLOCKED` state, reopened-`MIGRATED` behavior, Auditor role, SoD policy/default, reason length and physical types remain review/freeze items.
- The blueprint and workflow draft use potentially different status vocabularies. Do not silently merge them; ask the team to choose one shared vocabulary before behavior implementation.

## 5. Minimum verification sequence (VS Code only)

1. Confirm which VS Code destination is logged on and record release/system details from an actual system-information view if available.
2. Resolve a non-`$TMP` project package using a supported VS Code ABAP workflow. The current “Create New ABAP Object” list showed no Package entry; record the exact command/result if a supported package workflow is found or a permission error occurs.
3. Create one minimal, approved probe object only after the package is resolved; activate it and record the output.
4. Verify CDS view entity and required RAP artifacts/action support on the observed release.
5. Identify trusted principal and backend role/authorization mechanisms before implementing security checks.
6. Verify locking/ETag or another supported stale-update mechanism with an actual negative test.
7. Create service definition/binding and call our own service; only then mark service exposure as verified.
8. Record all results with sanitized errors. Do not repeat catalog counts as evidence of our own service.

## 6. Blockers and handling

Current environment blocker: the user can log on from VS Code and retrieve OData service catalogs, but has not established a non-`$TMP` package or a supported package-creation path. The object creation palette does not show a Package type. This is **NOT VERIFIED**, not proof that package creation is impossible.

Do not send the user through the same destination/connection test again. Do not ask them to use Eclipse; the workflow is VS Code-only. Continue repository-side work while the package path remains unresolved. Do not create production-like project objects in `$TMP` without an explicit decision that a disposable proof of concept is acceptable.

If any capability remains unavailable, document the observed failure and the smallest supported fallback; don't invent an API or claim success.

## 7. Sign-off

- [ ] Member 3 — environment findings and security feasibility reviewed.
- [ ] Member 1 — import entry path and persistence integration reviewed.
- [ ] Member 2 — recommendation fields/rule-set integration reviewed.
- [ ] Member 4 — service consumption and Fiori Elements requirements reviewed.
- [ ] All members — shared workflow/status/field contract confirmed.

**Final status:** IN PROGRESS — connection verified; package, activation, authorization, concurrency and project service remain unverified.
