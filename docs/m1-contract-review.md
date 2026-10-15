# Member 1 Review — Persistence, Import, Rules & RAP Integration Contract

**Reviewer role:** Member 1 (ABAP Data & Import).  
**Status:** Signed repository contract v0.3 (`M1-D02-T01` .. `M1-D11-T01`).  
**Reviewed artifacts:** `docs/data-contract.md` (v0.3), `docs/import-design.md` (v0.3), `docs/er-diagram.md` (v0.3), `docs/m2-contract-review.md` & `docs/rules-spec.md` (Member 2), `docs/m3-contract-review.md` & `docs/state-transitions.md` (Member 3), and `src/zccmc_ui/zccmc_customobject.edmx` (Member 4). All data is DEMO / SYNTHETIC.

## 1. Resolutions to Member 2 Open Questions (`docs/m2-contract-review.md`)

| Issue ID | Member 2 Question | Member 1 Resolution (`docs/data-contract.md` v0.3) |
|---|---|---|
| **A1–A3** | **`objects.findings_as_of` semantics:** Confirm blank means `FINDINGS_NOT_LOADED`, populated means scan complete for that object, and 30-day staleness applies to `usage.evidence_as_of` only. | **Confirmed.** `zccmc_cl_import_validator` validates `findings_as_of` as an optional `YYYY-MM-DD` date (`initial` when blank), and `zccmc_cl_import_orchestrator=>build_m2_evidence_for_object` passes `findings_as_of` directly to `zccmc_cl_rule_engine=>evaluate`. |
| **C1** | **Multiple usage rows per object:** Usage business key includes `period_start + period_end + evidence_source`, so multiple rows per object can exist. | **Confirmed (Option a — Safe Default).** The data layer preserves all valid usage facts per `ObjectUUID` so historical observation periods are not overwritten, and `build_m2_evidence_for_object` passes all usage rows for the object so Member 2's engine can enforce `MULTIPLE_USAGE_FACTS -> MANUAL_REVIEW`. |
| **C2** | **Dependency coverage indicator:** Absence of dependency rows vs. dependencies not loaded. | **Confirmed (Documented Limitation).** No fifth CSV or extra column is added in v0.3; `docs/limitations.md` and `docs/rules-spec.md` require human reviewer confirmation with the business owner before approving `RETIRE_CANDIDATE`. |
| **C3** | **Direction & meaning of "called by" in `dependencies.csv`:** Which endpoint is the caller, and which `dependency_type` values count? | **Confirmed.** In `dependencies.csv`, `(from_type, from_name)` is the calling/dependent object and `(to_type, to_name)` is the called/target object. Therefore, inbound callers of object `X` are rows where `to_object_uuid = X.object_uuid`. All non-empty uppercase `dependency_type` tokens (e.g., `CALL`, `INCLUDE`, `READ`) count conservatively as callers. |
| **C8** | **Corrected batches & findings retention:** How corrected imports interact with existing rows. | **Confirmed.** Within the MVP append/upsert model, corrected batches update matching business keys in place (`UPDATED`) without deleting omitted rows or prior batch provenance. Full rescan supersession is documented as future post-MVP scope. |
| **C11** | **Source ATC priority to `severity` mapping:** State the canonical mapping for every import. | **Confirmed & Documented in `docs/data-contract.md` Section 3:** ATC Priority `1` -> `HIGH`, Priority `2` -> `MEDIUM`, Priority `3` -> `LOW`, Informational note -> `INFO`. Blank severity is rejected (`MISSING_REQUIRED_FIELD`). |

## 2. Alignment with Member 3 (`src/zccmc_rap/` & `docs/m3-contract-review.md`)

| Integration Point | Member 3 Requirement | Member 1 Implementation |
|---|---|---|
| `ObjectUUID` stability | `ZCCMC_DECISION.OBJECT_UUID` links to `ZCCMC_CUSTOBJ.OBJECT_UUID`; re-imports must never regenerate `ObjectUUID` for an existing business key. | **Implemented & Verified (`IMP-I02`, `IMP-I03`, `IMP-I09`).** `zccmc_cl_import_object_loader=>load_objects` generates `ObjectUUID` only on `INSERTED` and strictly preserves it on `UNCHANGED` and `UPDATED`. |
| CDS Interface Views for RAP Projections | `ZCCMC_C_CustomObject`, `ZCCMC_C_ImportBatch`, and `ZCCMC_C_ImportRowError` select from `ZCCMC_I_CustomObject`, `ZCCMC_I_ImportBatch`, and `ZCCMC_I_ImportRowError`. | **Implemented (`src/zccmc_data/zccmc_i_*.ddls.asddls`).** Every field name and alias (`ObjectUUID`, `SourceSystemID`, `PackageName`, `FindingsAsOf`, `BatchUUID`, `FileKind`, `CreatedAtUtc`, `ParsedCount`, `AcceptedCount`, `RejectedCount`, `SourceRecord`, `BusinessKey`, `ErrorCode`, `FieldName`, `Message`) matches M3's projection views 1-to-1. |
| Interactive Upload vs. Staged/Unit Fallback | Direct browser upload is unverified in the shared trial tenant (`F-21`). | **Aligned.** Importer classes operate as pure backend services callable from ABAP Unit (`zccmc_ut_import_*`) and staged orchestration without claiming an unverified browser upload endpoint. |

## 3. Alignment with Member 4 (`src/zccmc_ui/`)

- `ZCCMC_I_Finding` exposes `FindingUUID`, `ObjectUUID`, `FindingID`, `CheckID`, `Category`, `Severity`, `Message`, and `SourceReference`, matching the `_Findings` navigation entity in `src/zccmc_ui/zccmc_customobject.edmx`.
- Batch statuses (`RECEIVED`, `VALIDATED`, `COMMITTED`, `FAILED`) and row outcomes (`INSERTED`, `UPDATED`, `UNCHANGED`, `REJECTED`) match `docs/architecture.md` Page 5 (Import Center).
