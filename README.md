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
   git clone <repository-url>
   cd <repository-folder>
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
| 4 | Fiori UX & QA/Integration | Fiori pages, README, architecture and demo docs, integration | Sections 1 to 5 |

---

## 6. Data Model and Import

> **Owner: Member 1.** _Placeholder, to be completed._

Planned content: entities and keys, CSV templates, validation rules, idempotent import behavior, import batch statuses.

---

## 7. Rules Engine and Analytics

> **Owner: Member 2.** _Placeholder, to be completed._

Planned content: rule outcomes, evaluation order, rule-set versioning, risk score formula, what-if simulation, test summary.

---

## 8. Review Workflow and Security

> **Owner: Member 3.** _Placeholder, to be completed._

Planned content: decision state machine, actions, roles and authorization, separation of duties, audit event fields, test matrix.
