# Feasibility Note - DRAFT (Member 3, Day 1)

Status: DRAFT. Every result below is NOT TESTED until someone fills it in from a real run on the assigned SAP system.
A capability is marked PASS only if it was observed working. Reading documentation does not count.
All data used in probes is DEMO / SYNTHETIC.

## 1. Environment

| Item | Value |
|---|---|
| System type (BTP ABAP environment trial / other) | TBC |
| Release / version | TBC |
| ABAP language version (ABAP Cloud?) | TBC |
| Development tool used (VS Code ABAP extension / Eclipse ADT) | TBC |
| Probe package | TBC |
| Date of probes | TBC |
| Tested by | Member 3 |

## 2. Capability matrix (Member 3)

Result values: PASS (observed working), FAIL (observed not working), BLOCKED (could not test, say why), NOT TESTED.

| # | Capability | Probe | Result | Observed (exact output or error) | Objects / transport ID | Fallback if not PASS |
|---|---|---|---|---|---|---|
| 1 | CDS read service | CDS view entity on a table, exposed as a service, one read | NOT TESTED | | | |
| 2 | Service binding and OData version | Binding published, metadata opens. Record V2 or V4 | NOT TESTED | | | |
| 3 | RAP behavior: action | Managed BO with one action, called once | NOT TESTED | | | |
| 4 | RAP behavior: validation | One validation that rejects bad input, called once | NOT TESTED | | | |
| 5 | Current user lookup | Action returns or stores the logged-in user | NOT TESTED | | | |
| 6 | Authorization: allowed path | A user with the role can run the action | NOT TESTED | | | |
| 7 | Authorization: denied path | A user without the role gets a real error from the backend | NOT TESTED | | | |
| 8 | Two test identities with different roles | At least two users that can be used for SoD tests | NOT TESTED | | | |
| 9 | ETag / locking | Same record changed from two sessions, second save is rejected | NOT TESTED | | | |

## 3. What each result means for the workflow design

| If this is not PASS | Effect on docs/state-transitions.md |
|---|---|
| 5 (current user) | Separation of duties cannot be enforced. Record this as a blocker, do not claim SoD |
| 7 or 8 (denied path, test users) | Role checks cannot be tested. Say role enforcement is unverified |
| 9 (ETag / locking) | Stale-update protection is a documented limitation, not a feature |
| 3 or 4 (action, validation) | Transition and override-reason rules cannot be enforced in the backend |

## 4. Fiori Elements route (Member 4)

| Item | Result | Evidence |
|---|---|---|
| Supported Fiori Elements preview / generation route | NOT TESTED | |
| Screenshot or blocker | NOT TESTED | |

## 5. Import path (Member 3, used on Day 4)

| Item | Result | Evidence |
|---|---|---|
| Direct CSV upload through a RAP parameter | NOT TESTED | |
| Staged-row CRUD plus a batch-processing action | NOT TESTED | |
| If neither works: interactive import is BLOCKED, ABAP Unit ingestion only | | |

## 6. Blockers

| # | Blocker | Impact | Owner | Next supported step |
|---|---|---|---|---|
| | | | | |

## 7. Limitations

- Results apply only to the system and release in section 1.
- Nothing here claims production SSO, role mapping or a live SAP connection.
