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

- [ ] ABAP environment and release: **SAP BTP ABAP Environment Trial (`TRL` / `AP21`)** (non-`$TMP` package provisioning pending; see [`docs/feasibility-note.md`](docs/feasibility-note.md))
- [ ] ABAP Development Tools (ADT) in Eclipse / VS Code
- [ ] Released APIs and Fiori Elements / OData support verified: see [`docs/feasibility-note.md`](docs/feasibility-note.md) and [`docs/limitations.md`](docs/limitations.md)
- [ ] Git access to this repository

### Steps

1. **Clone the repository**
   ```bash
   git clone https://github.com/Siva2583/Code-Atlas.git
   cd code-atlas
   ```
2. **Run offline verification oracles (no SAP tenant required)**
   ```bash
   python3 tools/validate_import_fixtures.py
   python3 tools/m1_import_oracle.py
   python3 tools/m2_rules_oracle.py
   python3 tools/m3_workflow_oracle.py
   ```
3. **Import the ABAP packages** into the target system once a transportable package (e.g., `ZCCMC`) is provisioned (see [`docs/runbook.md`](docs/runbook.md))
4. **Activate** all objects and run ABAP Unit (`Ctrl+Shift+F10`) on `ZCCMC_UT_IMPORT_VALIDATOR`, `ZCCMC_UT_IMPORT_IDEMPOTENCY`, `ZCCMC_UT_IMPORT_EDGE_CASES`, `ZCCMC_UT_RULE_ENGINE`, `ZCCMC_UT_PORTFOLIO_ANALYTICS`, and `ZCCMC_UT_DECISION_WORKFLOW` (100 ABAP Unit tests total)
5. **Load the synthetic demo data** through the verified fixture/staged-row route (`docs/runbook.md`)
6. **Open the Fiori app** and start at the Portfolio Overview (`docs/demo-script.md`)

---

## 4. Limitations

- **Recommends only.** There is no automated retirement or migration.
- **CSV is the only working evidence adapter.** No live SAP connection is claimed.
- **Rules are deterministic.** There is no AI or machine learning; no numeric risk score is fabricated without an approved formula.
- **Rules and thresholds are illustrative project demo policy.** They are configurable and must be validated by a migration or domain expert before real customer use.
- **Missing or conflicting evidence** leads to `MANUAL_REVIEW`, never to a forced confident result.
- **All sample data is DEMO / SYNTHETIC** and is not real customer evidence.
- **Does not replace SAP ATC** or other migration tooling.
- **Performance** figures are reported only when measured, with dataset size and environment stated.
- **Environment-specific limitations:** documented in [`docs/limitations.md`](docs/limitations.md) and [`docs/feasibility-note.md`](docs/feasibility-note.md).

---

## 5. Team

| Member | Role | Owns | README section |
|---|---|---|---|
| 1 | ABAP Data & Import | Tables and CDS, CSV staging and validation, idempotent loaders | [Section 6](#6-data-model-and-import) |
| 2 | Rules & Analytics | Rules evaluator, rule versioning, explanation trace, portfolio analytics | [Section 7](#7-rules-engine-and-analytics) |
| 3 | RAP Workflow & Security | Decision business object, actions, authorization, audit | [Section 8](#8-review-workflow-and-security) |
| 4 | Fiori UX & QA/Integration | Fiori UX prototypes, README, architecture and demo docs, integration planning | Sections 1 to 5 and 9 |

---

## 6. Data Model and Import

> **Owner: Member 1 — ABAP Data & Import (`M1-D01-T01` .. `M1-D11-T01` Complete).**

The persistence and import layer ingests the four synthetic-data CSV kinds (`objects`, `usage`, `findings`, `dependencies`) into 8 database tables (`ZCCMC_SOURCESYS`, `ZCCMC_CUSTOBJ`, `ZCCMC_USAGE`, `ZCCMC_FINDING`, `ZCCMC_DEPEND`, `ZCCMC_IMPBATCH`, `ZCCMC_IMPROWERR`, `ZCCMC_IMPROWRES`) exposed via 8 CDS interface views (`ZCCMC_I_SourceSystem` through `ZCCMC_I_ImportRowResult`) under `src/zccmc_data/`.

* **Importer & Orchestrator (`src/zccmc_import/`):** RFC 4180 CSV parsing and SHA-256 digest generation (`zccmc_cl_csv_adapter`), schema and enum/date validation (`zccmc_cl_import_validator`), batch and append-only row-result/error provenance (`zccmc_cl_import_batch_mgr`), idempotent entity loaders (`zccmc_cl_import_object_loader`, `zccmc_cl_import_usage_loader`, `zccmc_cl_import_finding_loader`, `zccmc_cl_import_dep_loader`), and four-file orchestration (`zccmc_cl_import_orchestrator`) including `build_m2_evidence_for_obj` (the M1→M2 evidence bridge) and `reset_synthetic_data` (`M1-D10-T01`).
* **Verification & Golden Results:** Covered by **32 ABAP Unit test methods** (`zccmc_ut_import_validator`, `zccmc_ut_import_idempotency`, `zccmc_ut_import_edge_cases`) and verified offline by `tools/m1_import_oracle.py` and `tools/validate_import_fixtures.py` across all sample, edge-case, and 1,000 / 10,000 scale fixtures. See [`docs/data-contract.md`](docs/data-contract.md), [`docs/import-design.md`](docs/import-design.md), [`docs/m1-golden-import-results.md`](docs/m1-golden-import-results.md), and [`docs/m1-day1-day11-status.md`](docs/m1-day1-day11-status.md).

---

## 7. Rules Engine and Analytics

> **Owner: Member 2 — Rules & Analytics (`M2-D01-T01` .. `M2-D11-T01` Complete).**

The rules and portfolio analytics layer evaluates imported custom-object evidence deterministically and aggregates portfolio-level KPIs without database, UI, or system-clock coupling:

* **Core ABAP domain classes (`src/zccmc_core/`):**
  * `zccmc_cl_rule_engine` (`src/zccmc_core/zccmc_cl_rule_engine.clas.abap`): Evaluates single objects (`evaluate_object`) and sorted portfolio batches (`evaluate_portfolio`) against the frozen v1.0.0 rule set (`ZCCMC_DEMO` / `1.0.0`), and provides `build_evidence_from_import` to map Member 1's imported entities (`zccmc_cl_import_orchestrator=>build_m2_evidence_for_obj`) into `ty_evidence`. Returns `RecommendedStrategy`, `RuleSetVersion`, `MatchedRuleIDs`, `MissingEvidence`, and a deterministic English `Explanation` (`EvidenceSummary`) containing the exact evidence snapshot used.
  * `zccmc_cl_portfolio_analytics` (`src/zccmc_core/zccmc_cl_portfolio_analytics.clas.abap`): Provides `build_item_from_result`, `build_items_from_results` (batch construction from Member 1's `ZCCMC_CUSTOBJ` metadata + `evaluate_portfolio` results), and `compute_summary` to calculate reconciled portfolio metrics (`M-01` total objects, `M-02` objects by strategy across all 5 canonical outcomes, `M-03` complete vs. missing evidence and per-reason breakdown, plus `by_source_system`, `by_package`, and `by_criticality` groupings) with anti-double-counting deduplication across 1:N joins and multiple runs.
* **Five canonical outcomes & active v1.0.0 rules (`docs/rules-spec.md`):**
  * Outcomes: `KEEP_ADAPT`, `REWRITE_RAP`, `RETIRE_CANDIDATE`, `SIDE_BY_SIDE_BTP`, and `MANUAL_REVIEW` (safe default).
  * Seed rules (`ZCCMC_DEMO` / `1.0.0`, illustrative project demo policy): `R10` (priority `10`: missing, unknown, stale, or contradictory evidence → `MANUAL_REVIEW`), `R20` (priority `20`: `0` runs over `>= 12` whole calendar months and no `HIGH`-criticality caller → `RETIRE_CANDIDATE`), `R30` (priority `30`: `run_count > 0` and `>= 1` `HIGH` finding → `MANUAL_REVIEW`), and `R60` (priority `60`: `run_count > 0` and `0` `HIGH` findings → `KEEP_ADAPT`). `REWRITE_RAP` and `SIDE_BY_SIDE_BTP` remain reserved until source CSV columns exist.
* **Safety & determinism invariants:**
  * Missing, unknown (`criticality = UNKNOWN`, blank `findings_as_of`), stale (`> 30` days), or contradictory evidence (`period_end < period_start`, `run_count = 0` with `last_executed`, `run_count > 0` without `last_executed`, multiple usage rows) **always** routes to `MANUAL_REVIEW` in code, even if `R10` is removed or deactivated.
  * Equal best priority with different outcomes routes to `MANUAL_REVIEW` (`RULE_CONFLICT`); no matching rule routes to `MANUAL_REVIEW` (`NO_RULE_MATCH`).
  * No numeric `RiskScore` or ML confidence is fabricated (`docs/m2-contract-review.md` `C13`).
* **Verification & Golden Results:**
  * Covered by **44 ABAP Unit test methods** (`31` in `src/zccmc_test/zccmc_ut_rule_engine.clas.abap` and `13` in `src/zccmc_test/zccmc_ut_portfolio_analytics.clas.abap`) and verified offline by `tools/m2_rules_oracle.py` across all 7 golden sample objects (`6 MANUAL_REVIEW`, `1 KEEP_ADAPT`), 200 CSV row-order permutations, 20x rule-order shuffles, cross-object explanation isolation checks, M1→M2 evidence/portfolio bridges, M1 edge/corrected fixtures, and 1,000 / 10,000 scale fixtures.
  * Full specification, golden outputs, and Day 1–11 handoff status: [`docs/rules-spec.md`](docs/rules-spec.md), [`docs/m2-golden-results.md`](docs/m2-golden-results.md), [`docs/m2-contract-review.md`](docs/m2-contract-review.md), and [`docs/m2-day1-day11-status.md`](docs/m2-day1-day11-status.md).

---

## 8. Review Workflow and Security

> **Owner: Member 3 — RAP Workflow & Security (`M3-D01-T01` .. `M3-D11-T01` Complete).**

The Migration Decision workflow routes custom-code modernization recommendations through human review and records the resulting decisions:

* **Decision lifecycle:** `PROPOSED`, `IN_REVIEW`, `APPROVED`, `OVERRIDDEN`, `RETURNED`, `IN_PROGRESS`, `BLOCKED`, and `MIGRATED`.
* **Role-based permissions:** Developer, Reviewer, Admin, and read-only Auditor permissions.
* **Separation of duties:** the backend prevents users from approving or overriding decisions they prepared, submitted, or own (`ERR_SOD_VIOLATION`).
* **Audit history:** successful workflow changes append an immutable audit event recording the authenticated actor, timestamp, previous and new values, and applicable reason (`>= 10` characters where required).
* **Concurrency:** optimistic lock version checks (`version_no` / `ETag`) reject stale updates with `ERR_STALE_CONCURRENCY_CONFLICT`.

The workflow contract, allowed transitions, validation requirements, audit fields, and negative tests are documented in [`docs/state-transitions.md`](docs/state-transitions.md), [`docs/m3-golden-workflow-results.md`](docs/m3-golden-workflow-results.md), and [`docs/m3-day1-day11-status.md`](docs/m3-day1-day11-status.md).

---

## 9. Fiori UX and QA/Integration

> **Owner: Member 4 — Fiori UX & QA/Integration (`M4-D01-T01` .. `M4-D11-T01` Complete).**

The UI layer provides SAP Fiori elements applications and end-to-end synthetic QA validation:

* **Portfolio overview:** `src/zccmc_ui/portfolio-overview/` contains the Fiori elements OData V4 List Report for portfolio items, aligned with Member 2's 5 strategy outcomes and Member 3's 8 decision statuses.
* **Custom-object experience:** `src/zccmc_ui/fiori-app/` contains the Fiori elements List Report and Object Page for custom objects, recommendations, import batch errors, and decision actions.
* **Design and demo references:** [`docs/architecture.md`](docs/architecture.md) describes the cockpit pages, and [`docs/demo-script.md`](docs/demo-script.md) outlines the synthetic-data walkthrough.
