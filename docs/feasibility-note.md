# RAP Workflow and Security Feasibility Note

**Owner:** Member 3 — RAP Workflow & Security
**Version:** 0.1
**Status:** IN PROGRESS — capabilities require tenant evidence
**Branch:** `feature/m3-rap-workflow`

## 1. Purpose

Verify which ABAP, RAP, authorization, concurrency, and service capabilities are available in the assigned SAP development environment before implementing the Migration Decision workflow.

Do not assume that a capability exists because it is documented in general SAP material or appears in an IDE. Mark it **VERIFIED** only after a successful observation in the assigned tenant.

## 2. Environment details

| Item                                    | Current finding                                                                |
| --------------------------------------- | ------------------------------------------------------------------------------ |
| Development environment                 | VS Code with SAP ABAP Development Tools extension; Eclipse ADT is a fallback   |
| SAP environment                         | SAP BTP ABAP Environment trial, as currently understood                        |
| System identifier                       | Reported as `BTP_DEV`; verify against the connected system                     |
| ABAP release/version                    | NOT VERIFIED                                                                   |
| Assigned development package            | NOT VERIFIED                                                                   |
| Software component                      | NOT VERIFIED                                                                   |
| Transport/change-recording requirements | NOT VERIFIED                                                                   |
| Current development authorization       | Connection is available; permitted development operations require verification |

Do not include passwords, access tokens, client secrets, or other credentials in this document.

## 3. Capability checklist

Use the following statuses consistently:

* **VERIFIED** — directly observed and recorded with evidence.
* **NOT VERIFIED** — not checked or evidence is insufficient.
* **BLOCKED** — an attempt was made, but a permission, environment, or technical limitation prevented verification.
* **NOT AVAILABLE** — evidence confirms the capability is unavailable in this environment.

| ID   | Capability                           | Verification action                                                                     | Status       | Evidence / notes                                    |
| ---- | ------------------------------------ | --------------------------------------------------------------------------------------- | ------------ | --------------------------------------------------- |
| F-01 | Correct SAP system                   | Confirm the connected system identifier in ADT/VS Code                                  | PARTIALLY VERIFIED | Record the observed identifier                      |
| F-02 | Assigned package                     | Locate the team-approved development package and confirm permission to use it           | PARTIALLY VERIFIED | Record package name                                 |
| F-03 | ABAP release                         | Inspect available system/product information                                            | NOT VERIFIED | Record the observed release                         |
| F-04 | Repository object creation           | Create or inspect a permitted test object in the assigned package                       | NOT VERIFIED | Do not create objects outside the approved package  |
| F-05 | Activation                           | Activate a permitted object and record the actual result                                | NOT VERIFIED | Capture the activation error if blocked             |
| F-06 | CDS view entities                    | Confirm that a minimal permitted CDS view entity can be activated                       | NOT VERIFIED | Record the object type and result                   |
| F-07 | RAP business object                  | Confirm supported RAP artifacts and whether a minimal business object can be activated  | NOT VERIFIED | Record actual supported artifact types              |
| F-08 | RAP actions and validations          | Verify support for the actions and validations needed by the workflow                   | NOT VERIFIED | Do not infer support from documentation alone       |
| F-09 | ABAP Unit                            | Confirm tests can be created or run in the assigned package                             | NOT VERIFIED | Record whether execution is permitted               |
| F-10 | Authorization model                  | Identify the supported authorization mechanism for the chosen RAP implementation        | NOT VERIFIED | Record the actual mechanism                         |
| F-11 | Current principal                    | Establish how the current authenticated user is identified in the backend               | NOT VERIFIED | Do not assume a UI username is a trusted identity   |
| F-12 | Role checks                          | Verify how Developer, Reviewer, Admin, and Auditor permissions can be enforced          | NOT VERIFIED | Record supported role/authorization sources         |
| F-13 | Instance authorization               | Verify that forbidden operations can be rejected by the backend                         | NOT VERIFIED | UI-only hiding does not count                       |
| F-14 | ETag or locking                      | Verify a supported mechanism for rejecting stale updates or conflicting changes         | NOT VERIFIED | Record the mechanism and observed result            |
| F-15 | Service definition                   | Confirm a service definition can be created and activated                               | NOT VERIFIED | Record result                                       |
| F-16 | Service binding                      | Confirm an appropriate service binding can be created and activated                     | NOT VERIFIED | Record protocol and binding type                    |
| F-17 | OData access                         | Verify that the resulting service can be accessed through the supported route           | NOT VERIFIED | Do not record a service as working until tested     |
| F-18 | Fiori Elements preview               | Verify whether a supported preview is available for the service                         | NOT VERIFIED | Separate preview from deployment                    |
| F-19 | Fiori Elements generation/deployment | Verify the permitted generation and deployment path, if required                        | NOT VERIFIED | Record any tenant restrictions                      |
| F-20 | Synthetic test data                  | Verify an approved way to create and reset non-sensitive demo records                   | NOT VERIFIED | Use synthetic data only                             |
| F-21 | Import integration                   | Verify the supported input path from Member 1's import work                             | NOT VERIFIED | Do not assume direct file upload is available       |
| F-22 | CDS aggregation                      | Verify whether any required aggregation can be implemented using supported CDS features | NOT VERIFIED | Only investigate if required by the agreed contract |

## 4. Minimum evidence to collect

For each capability checked, record:

1. The capability ID from the checklist.
2. The action attempted.
3. The observed result.
4. Any exact error message, with secrets removed.
5. The relevant object type or configuration, where applicable.
6. The resulting status and any next step.

A screenshot or short sanitized error excerpt may be retained separately if useful. Do not claim that an object, service, authorization check, or test works without observing the result.

## 5. Workflow/security requirements to verify

The implementation must support the agreed workflow contract before it is considered ready:

* Backend enforcement of legal state transitions.
* Backend enforcement of role permissions.
* Separation of duties for approval and override.
* Mandatory override reason and a strategy different from the recommendation.
* Preservation of the original `RecommendedStrategy`.
* Audit information for meaningful decision changes.
* Rejection of stale or conflicting updates using a supported mechanism.
* No state or audit changes when an action is rejected.
* Read-only access for the Auditor role.
* Synthetic demonstration data only.

The workflow contract remains **proposed**, not frozen, until the relevant team members resolve its open decisions and confirm a shared status and field contract.

## 6. Blocker handling and fallback

When a capability cannot be verified:

1. Mark the relevant checklist item **BLOCKED** and describe the observed limitation.
2. Identify the smallest missing prerequisite or permission.
3. Ask the team or environment administrator for that prerequisite if needed.
4. Do not invent an API, use an unsupported workaround, or silently change the workflow contract.
5. Propose the smallest supported fallback and request team agreement before implementing it.

In particular, do not assume that direct CSV upload, Fiori deployment, or a specific authorization API is available. If the intended import route is unsupported, document the limitation and agree on a supported alternative with the responsible team members.

## 7. Current conclusion

**No capability is considered verified by this note alone.** The checklist must be updated as tenant checks are performed.

RAP implementation should begin only after the minimum required object, activation, authorization, concurrency, and service capabilities have been verified—or after the team explicitly accepts a documented limitation and fallback.

## 8. Review and sign-off

* [ ] Member 3 — environment findings and security feasibility reviewed.
* [ ] Member 1 — import entry path and persistence integration reviewed.
* [ ] Member 2 — recommendation fields and rule-set integration reviewed.
* [ ] Member 4 — service consumption and Fiori Elements requirements reviewed.
* [ ] Team — shared workflow/status contract confirmed.

**Final status:** IN PROGRESS — pending evidence and team review.
