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

> **Owner: Member 1 — ABAP Data & Import (`src/zccmc_data/`, `src/zccmc_import/`, `src/zccmc_test/zccmc_ut_import_*`).**

The persistence and import layer ingests the four synthetic-data CSV kinds (`objects`, `usage`, `findings`, `dependencies`), validates schema/types/dates/enums, rejects duplicate or orphan rows with stable error codes, and maintains an append-only batch and row-result provenance ledger:

* **Persistence schema (`src/zccmc_data/`):** 8 DDIC database tables (`ZCCMC_SOURCESYS`, `ZCCMC_CUSTOBJ`, `ZCCMC_USAGE`, `ZCCMC_FINDING`, `ZCCMC_DEPEND`, `ZCCMC_IMPBATCH`, `ZCCMC_IMPROWERR`, `ZCCMC_IMPROWRES`) and 8 CDS interface view entities (`ZCCMC_I_*`) aligned with Member 3's RAP projections and Member 4's Fiori Elements metadata.
* **Pure ABAP importer (`src/zccmc_import/`):** `zccmc_if_source_adapter` (shared constants, types, 13 stable error codes), `zccmc_cl_csv_adapter` (RFC 4180 parser handling quotes, embedded commas, UTF-8 BOM, and LF/CRLF), `zccmc_cl_import_validator` (header, column width, required fields, enums, leap-year calendar dates, and intra-file `DUPLICATE_KEY` rejection), `zccmc_cl_import_batch_mgr` (append-only batch/row-result/row-error provenance), four idempotent entity loaders (`object`, `usage`, `finding`, `dep` preserving `ObjectUUID` on `UNCHANGED`/`UPDATED`), and `zccmc_cl_import_orchestrator` (reference-order orchestration, atomic file rollback on `PERSISTENCE_FAILURE`, reproducible Day-10 reset, and M1->M2 evidence bridge).
* **Unit tests & offline oracle (`src/zccmc_test/` & `tools/`):** 32 ABAP Unit test methods across `zccmc_ut_import_validator` (12), `zccmc_ut_import_idempotency` (10), and `zccmc_ut_import_edge_cases` (10), cross-checked offline by `tools/m1_import_oracle.py` and `tools/validate_import_fixtures.py` across all 6 edge fixtures, 200 row-order permutations, and 1,000 / 10,000-row performance & idempotency runs.
* **Documentation & handoff records:** [`docs/data-contract.md`](docs/data-contract.md) (v0.3), [`docs/import-design.md`](docs/import-design.md) (v0.3), [`docs/er-diagram.md`](docs/er-diagram.md) (v0.3), [`docs/m1-contract-review.md`](docs/m1-contract-review.md), [`docs/m1-golden-import-results.md`](docs/m1-golden-import-results.md), and [`docs/m1-day1-day11-status.md`](docs/m1-day1-day11-status.md).

**Verification & environment status:** Run `python3 tools/validate_import_fixtures.py` and `python3 tools/m1_import_oracle.py --report docs/m1-golden-import-results.md` to reproduce all 32 unit tests, edge fixtures, and 1k/10k benchmarks offline. Live SAP BTP ABAP Environment activation remains gated on provisioning a transportable non-`$TMP` package (`ZCCMC`; see [`docs/feasibility-note.md`](docs/feasibility-note.md) and [`docs/limitations.md`](docs/limitations.md)).

---

## 7. Rules Engine and Analytics

> **Owner: Member 2.** _Rules Engine and Analytics_

Planned content: rule outcomes, evaluation order, rule-set versioning, risk score formula, what-if simulation, test summary.

---

## 8. Review Workflow and Security

> **Owner: Member 3 — RAP Workflow & Security.**

The Migration Decision workflow is responsible for routing custom-code modernization recommendations through human review and recording the resulting decisions.

The proposed workflow covers:

* **Decision lifecycle:** `PROPOSED`, `IN_REVIEW`, `APPROVED`, `OVERRIDDEN`, `RETURNED`, `IN_PROGRESS`, `BLOCKED`, and `MIGRATED`.
* **Role-based permissions:** Developer, Reviewer, Admin, and proposed read-only Auditor permissions.
* **Separation of duties:** the backend must prevent users from approving or overriding decisions they prepared or own when separation of duties is enabled.
* **Audit history:** successful workflow changes should record the authenticated actor, timestamp, previous and new values, and applicable reason.
* **Concurrency:** stale updates must not silently overwrite a newer decision.

The workflow contract, allowed transitions, validation requirements, audit fields, and required negative tests are documented in [`docs/state-transitions.md`](docs/state-transitions.md).

**Implementation status:** The workflow remains a proposed design pending team agreement. RAP business-object activation, backend authorization, audit persistence, stale-update protection, and project service exposure have not yet been verified in the assigned SAP environment. See [`docs/feasibility-note.md`](docs/feasibility-note.md) and [`docs/limitations.md`](docs/limitations.md) for current verification status.

---

## 9. Fiori UX and QA/Integration

> **Owner: Member 4 — Fiori UX & QA/Integration.**

The current UI work is a prototype built with SAP Fiori elements and synthetic local data:

* **Combined portfolio experience:** `src/zccmc_ui/portfolio-overview/` is the canonical local mock app. It presents the Clean Core Portfolio Overview list and navigates each portfolio item to its Object Page with the synthetic object details. Running `npm run start-mock` from `src/zccmc_ui/fiori-app/` delegates to this app as well.
* **Custom-object scaffold:** `src/zccmc_ui/fiori-app/` remains a generated starter scaffold; its `start-mock` command now launches the combined portfolio experience.
* **Design and demo references:** [`docs/architecture.md`](docs/architecture.md) describes the five planned UI pages, and [`docs/demo-script.md`](docs/demo-script.md) outlines the intended synthetic-data walkthrough.

**Current limitations:** These prototypes use local metadata/mock data and placeholder service URLs. They are not connected to an activated RAP business object or a live OData service. The portfolio overview and the decision-workflow proposal also use status vocabularies that still require alignment before the UI contract is finalized. Import Center, Rules Administration, and end-to-end backend integration remain planned work; no production-readiness or SAP-system integration is claimed.

**Run the combined local preview:** run `npm run start-mock` from either `src/zccmc_ui/portfolio-overview/` or `src/zccmc_ui/fiori-app/`.

**QA focus:** Validate that the combined Fiori app launches with its local mock service, that list filters/navigation and displayed annotations match the agreed data and workflow contracts, and that documented demo flows use synthetic data. Record browser/build/test results when those checks are run; a successful local preview does not prove backend authorization, RAP behavior, or service activation.
