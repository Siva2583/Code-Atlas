# Data Contract — Member 1 (v0.3 — Candidate Contract & Reference Implementation)

**Owner:** Member 1 — Persistence and Import  
**Version:** 0.3 (`M1-D02-T01` .. `M1-D11-T01`)  
**Status:** Frozen in repository reference model (`src/zccmc_data/*`, `src/zccmc_import/*`, `tools/m1_import_oracle.py`); live SAP ADT activation remains gated on non-`$TMP` package resolution in the shared trial tenant (see `docs/feasibility-note.md` F-02 and `docs/limitations.md`).

All checked-in records are **DEMO / SYNTHETIC**. This contract covers exactly four import kinds: `objects`, `usage`, `findings`, and `dependencies`. It does not add an evidence CSV.

## 1. Version History

| Version | State | Change |
|---|---|---|
| `0.1` | Original baseline draft | Four initial CSV headers, with no way to distinguish a complete zero-findings scan from missing findings coverage. |
| `0.2` | Member 1 Day-2 candidate | Added optional `objects.findings_as_of` and defined business keys, normalization, duplicate/correction rules, error codes, reference ordering, and provenance requirements. |
| `0.3` | Cross-team aligned release candidate | Resolved Member 2 open items (`C1`, `C2`, `C3`, `C8`, `C11` in `docs/m1-contract-review.md`), aligned physical table/CDS projections (`src/zccmc_data/*`) with Member 3 (`src/zccmc_rap/*`) and Member 4 (`src/zccmc_ui/*`), and verified all 32 unit-test scenarios offline. |

## 2. Stable Identities, Physical Types & Normalization

The CSV contract uses UTF-8 text, comma delimiters, RFC 4180 quoting, and an exact ordered header. A leading UTF-8 BOM (`U+FEFF`) is allowed and stripped. Dates use `YYYY-MM-DD` and must be real Gregorian calendar dates (including leap-year rules). Integer fields are base-10, non-negative, with no decimal or grouping characters.

| Concept | Contract Rule & Proposed ABAP / DDIC Mapping |
|---|---|
| Source system | Identifier (`CHAR(40)` in `ZCCMC_SOURCESYS`) provisioned in the tenant before object imports (`DEMO_SYS` in synthetic tests). An unknown identifier is rejected with `UNKNOWN_SOURCE_SYSTEM`. |
| Custom object business key | Trimmed, uppercase-normalized `source_system + object_type + object_name`. Technical `ObjectUUID` (`SYSUUID_X16` in `ZCCMC_CUSTOBJ`) is generated on initial insert and **strictly preserved** across repeat (`UNCHANGED`) and corrected (`UPDATED`) imports. |
| Usage fact key | `source_system + object_type + object_name + period_start + period_end + evidence_source` (`ZCCMC_USAGE`, linked via `ObjectUUID`). |
| Finding key | `source_system + object_type + object_name + finding_id + check_id + source_reference` (`ZCCMC_FINDING`, linked via `ObjectUUID`). |
| Dependency key | `source_system + from_type + from_name + to_type + to_name + dependency_type + evidence_source` (`ZCCMC_DEPEND`, linked via `FromObjectUUID` and `ToObjectUUID`). |
| Text & field lengths | `source_system` `CHAR(40)`, `object_type` `CHAR(10)`, `object_name` `CHAR(120)`, `package_name` `CHAR(120)`, `description` `CHAR(500)`, `business_owner` `CHAR(120)`, `finding_id`/`check_id` `CHAR(80)`, `category` `CHAR(40)`, `message` `CHAR(500)`, `source_reference` `CHAR(120)`. Never silently truncate input. |

All key fields are trimmed; `source_system`, `object_type`, `object_name`, `from_type`, `from_name`, `to_type`, `to_name`, `dependency_type`, `criticality`, `severity`, and `evidence_source` are normalized to uppercase. Free-text descriptions, messages, and source references retain their case. Empty optional dates remain unknown (`00000000` / initial `d` in ABAP), never fabricated dates.

## 3. Exact Four CSV Schemas

| File | Ordered Header |
|---|---|
| `objects.csv` | `source_system,object_type,object_name,package,description,criticality,business_owner,first_seen,last_seen,findings_as_of` |
| `usage.csv` | `source_system,object_type,object_name,period_start,period_end,last_executed,run_count,evidence_source,evidence_as_of` |
| `findings.csv` | `source_system,object_type,object_name,finding_id,check_id,category,severity,message,source_reference` |
| `dependencies.csv` | `source_system,from_type,from_name,to_type,to_name,dependency_type,evidence_source` |

### Field Rules & Cross-Team Resolutions (`docs/m1-contract-review.md`)

- **`objects.csv`**:
  - `source_system`, `object_type`, and `object_name` are required identifiers.
  - `package`, `description`, and `business_owner` are free text (`business_owner` is informational business ownership; Member 3 uses `ZCCMC_DECISION.OWNER_USER` for authenticated developer workflow ownership and SoD).
  - `criticality` accepts `HIGH`, `MEDIUM`, `LOW`, or `UNKNOWN`; a blank value normalizes to `UNKNOWN` (never defaulted to `LOW`).
  - `first_seen`, `last_seen`, and `findings_as_of` are optional `YYYY-MM-DD` calendar dates. A populated `findings_as_of` means the findings scan is complete for that object as of that date (even when `findings.csv` has zero rows for it); blank means findings coverage is unknown (`FINDINGS_NOT_LOADED` in Member 2).
- **`usage.csv`**:
  - `source_system`, `object_type`, `object_name`, `period_start`, `period_end`, `run_count`, `evidence_source`, and `evidence_as_of` are required. `last_executed` is optional.
  - `run_count` is a non-negative integer (`< 0` fails with `NEGATIVE_RUN_COUNT`; non-integer syntax fails with `INVALID_INTEGER`).
  - `evidence_source` accepts `DEMO` or `CSV_EXPORT` for the MVP.
  - Contradictory usage rows (e.g., `run_count = 0` with `last_executed` populated, or `period_end < period_start`) are persisted if syntactically valid so Member 2's rule engine can deterministically classify them as conflicting evidence (`MANUAL_REVIEW`).
  - Multiple usage rows for the same object across distinct observation windows are permitted by the schema (`C1`); Member 2's engine safely flags `MULTIPLE_USAGE_FACTS -> MANUAL_REVIEW`.
- **`findings.csv`**:
  - `source_system`, `object_type`, `object_name`, `finding_id`, `check_id`, and `severity` are required.
  - `severity` accepts `HIGH`, `MEDIUM`, `LOW`, or `INFO`; blank severity is rejected with `MISSING_REQUIRED_FIELD`.
  - **Source ATC Priority Mapping (`C11`)**: Standard SAP ATC priority `1` (Error / Very High) maps to `HIGH`; priority `2` (Warning / Medium) maps to `MEDIUM`; priority `3` (Information / Low) maps to `LOW`; purely informational notes map to `INFO`.
- **`dependencies.csv`**:
  - `source_system`, `from_type`, `from_name`, `to_type`, `to_name`, `dependency_type`, and `evidence_source` (`DEMO` or `CSV_EXPORT`) are all required.
  - Both the `from` (caller) object and the `to` (called/target) object must already exist in `ZCCMC_CUSTOBJ`; otherwise the row is rejected with `UNKNOWN_OBJECT` (`field_name = 'from_name'` or `'to_name'`).
  - **Direction & Caller Semantics (`C3`)**: A row `(from_type, from_name) -> (to_type, to_name)` means `from` depends on / calls `to`. Therefore, inbound callers of an evaluated object `X` are dependency rows where `to_object_uuid = X.object_uuid`.

## 4. Batch, Row Result & Provenance Contract

- One imported file creates one `ImportBatch` (`ZCCMC_IMPBATCH`) with a newly generated `BatchUUID`, even on repeat uploads of the identical file.
- Accepted row results (`ZCCMC_IMPROWRES`) are `INSERTED`, `UPDATED`, or `UNCHANGED`. Rejected rows have result `REJECTED` in `ZCCMC_IMPROWRES` plus a detailed error entry in `ZCCMC_IMPROWERR`.
- **Count reconciliation**:
  - `accepted_count = inserted_count + updated_count + unchanged_count`
  - `parsed_count = accepted_count + rejected_count` (the header row is record `1` and is not counted in `parsed_count`).
- **Intra-file duplicates**: Repeated business keys within a single input file are **all** rejected as `DUPLICATE_KEY` (both the first and subsequent colliding rows are rejected so row ordering within a file cannot select a winner).
- **Cross-batch idempotency and corrections**:
  - Re-importing an identical normalized row in a later batch returns `UNCHANGED` and preserves `ObjectUUID`.
  - Re-importing the same business key with modified non-key attributes in a later batch updates the mutable fields in place, preserves `ObjectUUID`, and returns `UPDATED`.
  - Corrected batches never delete omitted business entities or prior batch/row provenance records (`ZCCMC_IMPBATCH`, `ZCCMC_IMPROWRES`, `ZCCMC_IMPROWERR` are strictly append-only).
- **Partial-file commit & fatal rollback**:
  - Row-level validation or reference rejects do not discard unrelated valid rows in the same file. The batch status is `COMMITTED` if `accepted_count >= 1` (including an all-`UNCHANGED` repeat batch), and `FAILED` if `accepted_count = 0` or a file-level error occurs (`HEADER_MISMATCH`, `MALFORMED_CSV`, `EMPTY_FILE`, `PERSISTENCE_FAILURE`).
  - A fatal storage failure (`PERSISTENCE_FAILURE`) rolls back all business-row writes from that file so no undocumented half-batch remains.

## 5. Stable Error Codes (`zccmc_if_source_adapter=>c_error`)

| Code | Scope | Meaning |
|---|---|---|
| `HEADER_MISMATCH` | File | Header column name, order, missing column, or extra column differs from the frozen schema. |
| `MALFORMED_CSV` | File | Unclosed quote, unescaped quote inside an unquoted field, or unreadable RFC 4180 record. |
| `EMPTY_FILE` | File | Header is valid, but the file contains zero data records. |
| `PERSISTENCE_FAILURE` | File | Fatal storage failure; all business-row writes for the file are rolled back. |
| `COLUMN_COUNT_MISMATCH` | Row | Data record does not contain the exact number of columns required by the header. |
| `MISSING_REQUIRED_FIELD` | Row | Required identifier, date, count, or enum field is blank. |
| `INVALID_ENUM` | Row | Value is outside the approved MVP enumeration (`criticality`, `severity`, `evidence_source`). |
| `INVALID_DATE` | Row | Date is not `YYYY-MM-DD` or is not a real Gregorian calendar date (e.g., `2026-02-30`). |
| `INVALID_INTEGER` | Row | Integer field (`run_count`) contains non-digit characters, decimals, or formatting. |
| `NEGATIVE_RUN_COUNT` | Row | `run_count` is a negative integer (`< 0`). |
| `DUPLICATE_KEY` | Row | Business key appears more than once within the same input file (all colliding rows rejected). |
| `UNKNOWN_SOURCE_SYSTEM` | Row | Object row references a `source_system` not provisioned in `ZCCMC_SOURCESYS`. |
| `UNKNOWN_OBJECT` | Row | Usage, finding, or dependency row references a `CustomObject` not yet persisted in `ZCCMC_CUSTOBJ`. |
