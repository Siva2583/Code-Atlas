# Clean Core Migration Cockpit

> **Decision and governance layer for SAP custom-code modernization.**
> Built with ABAP Cloud, CDS, RAP and Fiori Elements.

## Table of Contents

1. [Project Goal](#1-project-goal)
2. [Architecture Overview](#2-architecture-overview)
3. [Setup Steps](#3-setup-steps)
4. [Limitations](#4-limitations)
5. [Team](#5-team)
6. [Data Model and Import](#6-data-model-and-import)
7. [Rules Engine and Analytics](#7-rules-engine-and-analytics)
8. [Review Workflow and Security](#8-review-workflow-and-security)
9. [Fiori UX and QA/Integration](#9-fiori-ux-and-qaintegration)

---

## 1. Project Goal

The Clean Core Migration Cockpit is a **decision and governance layer** for SAP custom-code modernization. It imports usage and code-quality evidence (CSV in the MVP), applies versioned and configurable rules to produce an explainable recommendation for each custom object, and routes that recommendation to human reviewers with separation of duties and a full audit trail.

**It is not an auto-migration tool.** It never deletes, retires or migrates anything by itself, and it does not replace SAP ATC or other migration tooling. Humans approve every lifecycle action.

### What makes it different

| Principle         | Meaning                                                                           |
|---                |---                                                                                |
| Explainable       | Every recommendation shows the matched rules and the evidence used                |
| Configurable      | Rules and thresholds are versioned and editable; published versions are immutable |
| Auditable         | Every state change records actor, timestamp, old and new values, and reason       |
| Human-in-the-loop | The system recommends; reviewers approve or override (an override needs a reason) |

---

## 2. Architecture Overview

```
Source / Evidence  ->  Persistence  ->  Domain Logic  ->  RAP Service  ->  Fiori UI  ->  Quality & Governance
     (CSV)            (Tables, CDS)    (ABAP classes)     (MigrationDecision BO)  (Fiori Elements)   (ABAP Unit, audit)
```

| Layer             | Technology                         | Responsibility                                                    |
|---                |---                                 |---                                                                |
| Source / Evidence | CSV import (MVP adapter)           | Bring in objects, usage, findings and dependencies                |
| Persistence       | Database tables, CDS view entities | Store raw imported facts separately from calculated recommendations |
| Domain Logic      | Plain ABAP classes                 | Evaluate evidence against rules and return a recommendation         |
| RAP Service       | RAP managed business object        | Decision state machine, actions, validations, authorization, audit |
| Fiori UI          | Fiori Elements (List Report / Object Page) | Five pages: Portfolio Overview, Object Inventory, Object/Decision Detail, Rules Administration, Import Center |
| Quality & Governance | ABAP Unit, audit trail          | Tests, separation of duties, traceability |

**Design principle:** classification logic stays out of the RAP behavior handlers. The business object orchestrates persistence and actions, while a separate domain service evaluates the rules. This keeps the rules unit-testable without the UI or the database.

**Stable object key:** source system ID + object type + object name (the name alone is not unique).

More detail, diagrams and page sketches: [`docs/architecture.md`](docs/architecture.md)

---

## 3. Setup Steps



### Prerequisites

- [ ] ABAP environment and release: **TBC**
- [ ] ABAP Development Tools (ADT) in Eclipse
- [ ] Released APIs and Fiori Elements / OData support verified: **TBC**
- [ ] Git access to this repository

### Steps

1. **Clone the repository**
   ```bash
   git clone https://github.com/Siva2583/Code-Atlas.git
   cd code-atlas
   ```
2. **Import the ABAP packages** into the target system: **TBC** (method and package names)
3. **Activate** all objects and the OData service: **TBC**
4. **Load the synthetic demo data** through the Import Center: **TBC**
5. **Assign the demo business roles** (Developer, Reviewer, Administrator, Auditor): **TBC**
6. **Open the Fiori app** and start at the Portfolio Overview: **TBC**


---

## 4. Limitations

- **Recommends only.** There is no automated retirement or migration.
- **CSV is the only working evidence adapter.** No live SAP connection is claimed.
- **Rules are deterministic.** There is no AI or machine learning; any score is a documented formula.
- **Rules and thresholds are illustrative.** They are configurable and must be validated by a migration or domain expert.
- **Missing or conflicting evidence** leads to `MANUAL_REVIEW`, never to a forced confident result.
- **All sample data is DEMO / SYNTHETIC** and is not real customer evidence.
- **Does not replace SAP ATC** or other migration tooling.
- **Performance** figures are reported only when measured, with dataset size and environment stated.
- **Environment-specific limitations:** to be added by each member as they are found.

---

## 5. Team

| Member                         |Role | Owns | README section |
|---                             |---|---|---|
| 1 | ABAP Data & Import         | Tables and CDS, CSV staging and validation, idempotent loaders | [Section 6](#6-data-model-and-import)|
| 2 | Rules & Analytics          | Rules evaluator, rule versioning, risk score, what-if | [Section 7](#7-rules-engine-and-analytics)|
| 3 | RAP Workflow & Security    | Decision business object, actions, authorization, audit | [Section 8](#8-review-workflow-and-security)|
| 4 | Fiori UX & QA/Integration | Fiori UX prototypes, README, architecture and demo docs, integration planning | Sections 1 to 5 and 9 |

---

## 6. Data Model and Import

> Owner: Member 1 — ABAP Data & Import.

The MVP imports exactly four synthetic-data CSV kinds: objects, usage, findings and dependencies. The object identity is the normalized source system, object type and object name; ObjectUUID is the technical key generated in SAP. Usage, findings and dependency rows reference that identity.

The four exact template headers, candidate field types, upsert keys, date/enum rules, batch statuses, row errors, order and provenance requirements are maintained in docs/data-contract.md and docs/import-design.md. Candidate v0.2 adds findings_as_of to the objects file so a complete findings scan with zero findings can be distinguished from unknown coverage. That change is awaiting shared contract review.

All repository sample data is synthetic. The sample and edge/performance fixtures are test inputs, not production observations. SAP table activation, the supported import route, ABAP Unit results and 1k/10k SAP timings remain unverified until recorded from the assigned ADT tenant.

---

## 7. Rules Engine and Analytics

> **Owner: Member 2.** _Rules Engine and Analytics_

Planned content: rule outcomes, evaluation order, rule-set versioning, risk score formula, what-if simulation, test summary.

---

## 8. Review Workflow and Security

> **Owner: Member 3 — RAP Workflow & Security.**

The Migration Decision workflow routes custom-code modernization recommendations from Member 2's rules engine through human governance review with strict role-based access control, separation of duties (SoD), optimistic concurrency protection, and an append-only audit trail.

### Delivered Architecture & Artifacts (`src/zccmc_rap/` & `src/zccmc_test/`)

* **Pure ABAP Workflow & Security Engine (`zccmc_cl_decision_workflow.clas.abap`):** Decoupled, deterministic state machine enforcing all 8 workflow statuses (`PROPOSED`, `IN_REVIEW`, `APPROVED`, `OVERRIDDEN`, `RETURNED`, `IN_PROGRESS`, `BLOCKED`, `MIGRATED`), 11 lifecycle actions (`SUBMIT`, `RESUBMIT`, `APPROVE`, `OVERRIDE`, `RETURN`, `START`, `BLOCK`, `UNBLOCK`, `MARK_MIGRATED`, `REOPEN`, plus `ASSIGN_OWNER`), and 15 stable error codes (`ERR_SOD_VIOLATION`, `ERR_UNAUTHORIZED_ROLE`, `ERR_INVALID_TRANSITION`, `ERR_STALE_CONCURRENCY_CONFLICT`, `ERR_AUDIT_IMMUTABLE`, etc.).
* **Separation of Duties (SoD) & Role Governance:** Enforces `DEVELOPER`, `REVIEWER`, `ADMIN`, and read-only `AUDITOR` permissions on the server. When SoD is enabled (default), `OwnerUser`, `CreatedBy`, and `SubmittedBy` are blocked from approving or overriding their own decision—even if the principal holds both `DEVELOPER` and `REVIEWER` roles.
* **Proposed RAP Business Object & OData V4 Service (`src/zccmc_rap/`):** Includes `ZCCMC_DECISION` / `ZCCMC_DECAUDIT` table definitions, `ZCCMC_I_Decision` / `ZCCMC_I_DecisionAudit` CDS view entities, managed behavior definition (`zccmc_i_decision.bdef.asbdef` with `etag master ChangedAt` and append-only audit composition), projection views (`ZCCMC_C_Decision`, `ZCCMC_C_DecisionAudit`, `ZCCMC_C_CustomObject`, `ZCCMC_C_ImportBatch`, `ZCCMC_C_ImportRowError`), DCL access control (`zccmc_dcl_decision.dcls.asdcls`), and OData V4 service definition/binding (`zccmc_ui_cockpit_o4`).
* **ABAP Unit Suite & Offline Oracle (`zccmc_ut_decision_workflow.clas.abap` & `tools/m3_workflow_oracle.py`):** 24 unit-test scenarios (`WF-T01`..`WF-T24`) and an exhaustive 352-combination (`8 states x 11 actions x 4 roles`) verification runner, plus Day-10 rehearsal across the 7 synthetic sample objects.

### Verification Status & References

* **Contract & Golden Results:** [`docs/state-transitions.md`](docs/state-transitions.md) (v0.3), [`docs/m3-contract-review.md`](docs/m3-contract-review.md), [`docs/m3-golden-workflow-results.md`](docs/m3-golden-workflow-results.md), and [`docs/m3-day1-day11-status.md`](docs/m3-day1-day11-status.md).
* **Environment Blockers:** Offline oracle passes 100% (`352/352` matrix combinations and `24/24` unit tests). Live SAP BTP ABAP Environment activation, OData service publication, and interactive CSV upload remain marked **BLOCKED** pending non-`$TMP` package provisioning in the VS Code trial workspace. See [`docs/feasibility-note.md`](docs/feasibility-note.md) and [`docs/limitations.md`](docs/limitations.md).

---

## 9. Fiori UX and QA/Integration

> **Owner: Member 4 — Fiori UX & QA/Integration.**

The current UI work is a prototype built with SAP Fiori elements and synthetic local data:

* **Portfolio overview:** `src/zccmc_ui/portfolio-overview/` contains a Fiori elements OData V4 List Report prototype for portfolio items, with filter and chart annotations and a local mock-data setup.
* **Custom-object experience:** `src/zccmc_ui/fiori-app/` contains a Fiori app scaffold for the custom-object list and detail experience. Its routes and mock preview are for local validation; they are not a published SAP service.
* **Design and demo references:** [`docs/architecture.md`](docs/architecture.md) describes the five planned UI pages, and [`docs/demo-script.md`](docs/demo-script.md) outlines the intended synthetic-data walkthrough.

**Current limitations:** These prototypes use local metadata/mock data and placeholder service URLs. They are not connected to an activated RAP business object or a live OData service. The portfolio overview and the decision-workflow proposal also use status vocabularies that still require alignment before the UI contract is finalized. Import Center, Rules Administration, and end-to-end backend integration remain planned work; no production-readiness or SAP-system integration is claimed.

**QA focus:** Validate that the Fiori app launches with its local mock service, that list filters/navigation and displayed annotations match the agreed data and workflow contracts, and that documented demo flows use synthetic data. Record browser/build/test results when those checks are run; a successful local preview does not prove backend authorization, RAP behavior, or service activation.
