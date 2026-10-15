# Import Design — Member 1 (v0.3 — Architecture, Importer Classes & Provenance)

**Owner:** Member 1 — Persistence and Import  
**Version:** 0.3 (`M1-D02-T01` .. `M1-D11-T01`)  
**State:** Repository implementation complete (`src/zccmc_data/*`, `src/zccmc_import/*`, `src/zccmc_test/zccmc_ut_import_*`) and verified offline via `tools/m1_import_oracle.py` and `tools/validate_import_fixtures.py`. Live SAP ADT activation remains gated on non-`$TMP` package provisioning (`docs/feasibility-note.md` F-02).

## 1. Module Architecture & Separation of Concerns

All CSV parsing, schema validation, batch tracking, and entity loading logic is implemented in pure, release-safe ABAP classes under `src/zccmc_import/` with zero dependency on RAP behavior pools or Fiori UI controllers:

| Artifact | Role | Key Methods |
|---|---|---|
| `zccmc_if_source_adapter.intf.abap` | Shared contract interface | Defines `c_file_kind`, `c_batch_status`, `c_row_result`, `c_error` (13 error codes), typed row/batch structures, and `parse_source`. |
| `zccmc_cl_csv_adapter.clas.abap` | RFC 4180 CSV parser & digest service (`M1-D04-T01`) | `parse_csv_string`, `compute_digest` — strips UTF-8 BOM, handles LF/CRLF, parses quoted commas/newlines and escaped quotes (`""`), tracks 1-based CSV record numbers, and rejects malformed quoting (`MALFORMED_CSV`). |
| `zccmc_cl_import_validator.clas.abap` | Persistence-independent validator (`M1-D04-T01`) | `get_expected_header`, `validate_header`, `is_valid_iso_date`, `parse_non_negative_int`, `validate_parsed_file` — checks headers, column counts, required fields, enums, leap-year calendar dates, and intra-file duplicate keys (`DUPLICATE_KEY`). |
| `zccmc_cl_import_batch_mgr.clas.abap` | Append-only batch & provenance manager (`M1-D05-T01` / `M1-D06-T01`) | `create_batch`, `record_accepted_row`, `record_rejected_row`, `finalize_batch`, `fail_batch_file_level` — reconciles counts and appends immutable records to `batches`, `row_results`, and `row_errors`. |
| `zccmc_cl_import_object_loader.clas.abap` | CustomObject loader (`M1-D05-T01`) | `load_objects` — checks `ZCCMC_SOURCESYS` (`UNKNOWN_SOURCE_SYSTEM`), upserts `ZCCMC_CUSTOBJ` by `source_system + object_type + object_name`, and preserves `ObjectUUID` on `UNCHANGED` / `UPDATED`. |
| `zccmc_cl_import_usage_loader.clas.abap` | UsageFact loader (`M1-D05-T01`) | `load_usages` — verifies parent `ObjectUUID` (`UNKNOWN_OBJECT`), upserts `ZCCMC_USAGE` by composite usage key. |
| `zccmc_cl_import_finding_loader.clas.abap` | Finding loader (`M1-D05-T01`) | `load_findings` — verifies parent `ObjectUUID` (`UNKNOWN_OBJECT`), upserts `ZCCMC_FINDING` by composite finding key. |
| `zccmc_cl_import_dep_loader.clas.abap` | Dependency loader (`M1-D05-T01`) | `load_dependencies` — verifies both `FromObjectUUID` and `ToObjectUUID` (`UNKNOWN_OBJECT`), upserts `ZCCMC_DEPEND`. |
| `zccmc_cl_import_orchestrator.clas.abap` | End-to-end orchestrator, rollback & M2/M3 bridge (`M1-D05..D10`) | `init_store`, `reset_synthetic_store`, `import_csv_file`, `import_four_file_set`, `build_m2_evidence_for_object`. |

## 2. Reference Ordering, Partial-Batch Commit & Atomic File Rollback (`M1-D07-T01`)

1. **Required Load Order**: For a clean load, import `objects.csv` first, followed by `usage.csv`, `findings.csv`, and `dependencies.csv`. The source system (`DEMO_SYS`) must be provisioned before object import.
2. **No Deferred Replay**: Dependent rows (`usage`, `findings`, `dependencies`) require their referenced `CustomObject`(s) to exist at import time. If dependent files are imported before `objects.csv`, each row is rejected with `UNKNOWN_OBJECT` and persisted in `ZCCMC_IMPROWERR`. Loading `objects.csv` afterward does **not** silently replay previously failed batches; the caller must re-submit the dependent file in a new batch.
3. **Partial-Batch Policy**: Within a single file, row-level validation or reference errors reject only the offending rows (`REJECTED`) while valid rows in the same file commit (`INSERTED` / `UPDATED` / `UNCHANGED`). If at least one row is accepted, the batch status is `COMMITTED`; if zero rows are accepted, the batch status is `FAILED`.
4. **Atomic Rollback on Fatal Persistence Failure**: Before executing the entity loader for a file, `zccmc_cl_import_orchestrator=>import_csv_file` captures a transactional snapshot. If a fatal storage failure occurs (`PERSISTENCE_FAILURE`), all business-row writes for that file are rolled back completely so no undocumented half-batch remains.

## 3. Edge Fixtures & Verified Outcomes (`M1-D04-T01` .. `M1-D08-T01`)

| Fixture | Expected & Verified Import Outcome |
|---|---|
| `edge-cases/objects_empty.csv` | Header parses; zero data records; batch `FAILED` with file-level `EMPTY_FILE`; zero objects created or deleted. |
| `edge-cases/objects_duplicate_keys.csv` | Both rows (`source_record = 2` and `3`) of `DEMO_SYS\|PROG\|ZDEMO_DUPLICATE` are `REJECTED` with `DUPLICATE_KEY`; batch `FAILED`; neither row is applied. |
| `edge-cases/objects_corrected_batch.csv` | After baseline `objects.csv`, updates `ZSD_OPEN_ORDERS_RPT` description in place (`1 UPDATED`), preserves `ObjectUUID`, leaves the other 6 objects untouched, and retains prior batch provenance. |
| `edge-cases/usage_malformed_date.csv` | Record `2` (`2026-02-30`) is `REJECTED` with `INVALID_DATE` on `field_name = 'period_start'`; batch `FAILED`; zero usage writes. |
| `edge-cases/findings_unknown_object.csv` | Record `2` (`ZUNKNOWN_IMPORT_TARGET`) is `REJECTED` with `UNKNOWN_OBJECT` on `field_name = 'object_name'`; batch `FAILED`; zero orphan findings. |
| `edge-cases/findings_quoted_fields.csv` | Record `2` (`F900`) is `INSERTED` (`COMMITTED`) with comma and escaped quotes preserved verbatim (`DEMO quoted, comma and "quote" fixture`). |
| Repeat of baseline 4 files | All rows return `UNCHANGED` (`7`, `6`, `8`, `2`); batches are `COMMITTED` with new `BatchUUID`s and append-only row-result provenance. |

## 4. Supported Import Entry Path & Environment Blocker (`M1-D01-T01` / `M3-D04-T01`)

Direct browser CSV file upload through RAP/Fiori Elements is **BLOCKED** in the shared trial environment (see `docs/feasibility-note.md` F-02 and F-21). The supported ingestion paths are:
- **In SAP ADT (once package `ZCCMC` is provisioned)**: Repeatable ABAP Unit / orchestrator execution (`zccmc_cl_import_orchestrator=>import_four_file_set`) plus read-only OData exposure of `ZCCMC_C_ImportBatch` and `ZCCMC_C_ImportRowError`.
- **Offline in Repository**: `python3 tools/m1_import_oracle.py --report docs/m1-golden-import-results.md` and `python3 tools/validate_import_fixtures.py`.
