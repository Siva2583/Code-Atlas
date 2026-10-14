# Member 3 — RAP Workflow and Security Limitations

**Owner:** Member 3 — RAP Workflow & Security
**Status:** Verification in progress

## 1. Environment and package

* VS Code successfully connected to the configured SAP BTP ABAP Environment trial, and logon was reported successful.
* OData V2 and V4 service catalogs were reachable. This confirms catalog access only; it does not confirm that the project's own service is available.
* The approved project package and supported package-creation path remain unverified.
* Do not treat `$TMP` local objects as the approved shared project package.

## 2. RAP implementation

The following capabilities have not yet been demonstrated for this project:

* Creation and activation of the agreed RAP Migration Decision business object.
* Activation of the required CDS entities and behavior definitions.
* Creation and activation of the project's service definition and service binding.
* Successful access to the project's own OData service.
* Fiori Elements preview or deployment of the project service.

The presence of object types in the VS Code creation palette is not evidence of successful activation.

## 3. Authorization and audit

The workflow design requires backend-enforced permissions and separation of duties. The following remain unverified:

* The supported backend identity and authorization mechanisms.
* Developer, Reviewer, Admin, and Auditor role checks.
* Rejection of unauthorized direct action calls.
* Append-only audit persistence and transactional consistency.
* ETag, locking, or equivalent stale-update protection.

Hiding UI actions is not a substitute for backend authorization.

## 4. Contract and integration

* `docs/state-transitions.md` remains proposed and is not frozen.
* Shared agreement is still required for workflow status vocabulary and related contract decisions.
* The candidate data contract and recommendation-field mapping must be confirmed with Members 1, 2, and 4 before implementation relies on them as final.
* The supported import-to-decision integration path remains unverified.

## 5. Test status

No successful project RAP activation, backend authorization test, audit-persistence test, or stale-update test has been recorded in the available evidence.

These items must remain unverified until actual results are recorded from the assigned SAP environment.

## 6. Scope and safety

* Use synthetic demonstration data only.
* Workflow actions record human decisions; they must not automatically migrate, retire, or delete SAP objects.
* Do not claim an API, environment capability, or test result without evidence.
* Follow the VS Code-only development workflow for this project.
