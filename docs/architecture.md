# Architecture

> The Clean Core Migration Cockpit is a **decision and governance layer** for SAP
> custom-code modernization. It imports usage and code-quality evidence (CSV in the MVP),
> applies versioned, configurable rules to produce an explainable recommendation for each
> custom object, and routes it to human reviewers with separation of duties and a full
> audit trail. It is **not an auto-migration tool**: it never deletes, retires or migrates
> anything by itself, and it does not replace SAP ATC or other migration tooling.

## UI Pages

### Page 1: Portfolio Overview (landing page)
| Item | Content |
|---|---|
| Purpose | Management view of the whole portfolio |
| KPI tiles | Total objects, Pending review, High-risk, Missing/stale evidence, Approved, Migrated |
| Charts | By strategy, by risk, review aging, status funnel, findings by severity |
| Filters | Package, Source system, Rule-set version |
| Navigation | Each tile/chart opens the Inventory with a filter pre-set |

### Page 2: Custom Object Inventory (List Report)
| Item | Content |
|---|---|
| Filters | Strategy, Risk, Status, Owner, Package, Confidence/Priority |
| Quick filters | Unreviewed, High-risk, Stale evidence, Retirement candidates, Rule conflicts |
| Columns | Object name, Type, Package, Criticality, Recommended strategy, Risk, Status, Owner, Evidence as-of |
| Not in MVP | Bulk approval |

### Page 3: Object / Decision Detail (Object Page)
| Section | Content |
|---|---|
| Header | Object name, source system, criticality, status |
| Usage | Timeline, last executed, run count, observation period |
| Findings | Grouped by severity |
| Dependencies | What this object calls / is called by |
| Recommendation card | Rationale, matched rules, missing evidence, rule-set version, completeness |
| Reviewer panel | Approve / Override / Return. **Reason is mandatory for override** |
| Audit timeline | Actor, timestamp, old/new values, reason |

### Page 4: Rules Administration
| Item | Content |
|---|---|
| List | Rule sets (ID, version, status draft/published) |
| Rule fields | Priority, active flag, conditions, outcome, rationale template |
| Actions | Publish (with pre-publish validation), What-if simulation |
| Constraint | Published versions are immutable |

### Page 5: Import Center
| Item | Content |
|---|---|
| Template download | objects, usage, findings, dependencies CSVs |
| Upload + preview | Total / valid / rejected rows, row-level errors |
| Commit | Result per row: inserted / updated / unchanged / rejected |
| History | Batch list with status RECEIVED / VALIDATED / COMMITTED / FAILED |
| Label | Visible **SYNTHETIC DEMO DATA** banner |