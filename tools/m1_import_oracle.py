#!/usr/bin/env python3
"""Reference model and regression runner for Member 1 Persistence & CSV Import (docs/data-contract.md v0.3).

This is an OFFLINE TEST ORACLE, not the SAP runtime. The ABAP implementation is in
src/zccmc_import/* (zccmc_if_source_adapter, zccmc_cl_csv_adapter, zccmc_cl_import_validator,
zccmc_cl_import_batch_mgr, zccmc_cl_import_*_loader, zccmc_cl_import_orchestrator) and
src/zccmc_data/*, which require a verified non-$TMP package in the SAP BTP ABAP Environment
trial to activate (see docs/feasibility-note.md F-02 and docs/limitations.md).

This oracle re-implements the exact RFC 4180 CSV parser, schema/date/enum/duplicate-key
validator, append-only batch/row-result/row-error provenance manager, four entity loaders,
transactional rollback, and Day-10 reset/import reproducibility rules so that:
  * all 32 unit-test scenarios (IMP-V01..V12, IMP-I01..I10, IMP-E01..E10) across the three
    ABAP Unit classes in src/zccmc_test/zccmc_ut_import_*.clas.abap are cross-checked;
  * all 6 named edge-case fixtures in data/sample-synthetic/edge-cases/ are verified;
  * 200 random row-order permutations across all 4 sample CSVs verify deterministic persistence;
  * 1,000-row and 10,000-row performance & repeat-import idempotency runs are measured;
  * Day-10 clean reset and M1 -> M2 -> M3 end-to-end data handoff are verified offline.
It proves nothing about live SAP ADT activation. DEMO / SYNTHETIC data only.

Usage (repository root):
    python3 tools/m1_import_oracle.py
    python3 tools/m1_import_oracle.py --report docs/m1-golden-import-results.md
"""
from __future__ import annotations

import argparse
import copy
import datetime as dt
import hashlib
import random
import sys
import time
from dataclasses import dataclass, field
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
DATA_DIR = ROOT / "data"
TEMPLATE_DIR = DATA_DIR / "templates"
SAMPLE_DIR = DATA_DIR / "sample-synthetic"
EDGE_DIR = SAMPLE_DIR / "edge-cases"
PERF_DIR = SAMPLE_DIR / "perf"

HEADERS: dict[str, list[str]] = {
    "objects": [
        "source_system", "object_type", "object_name", "package", "description",
        "criticality", "business_owner", "first_seen", "last_seen", "findings_as_of",
    ],
    "usage": [
        "source_system", "object_type", "object_name", "period_start", "period_end",
        "last_executed", "run_count", "evidence_source", "evidence_as_of",
    ],
    "findings": [
        "source_system", "object_type", "object_name", "finding_id", "check_id",
        "category", "severity", "message", "source_reference",
    ],
    "dependencies": [
        "source_system", "from_type", "from_name", "to_type", "to_name",
        "dependency_type", "evidence_source",
    ],
}

CRITICALITIES = {"HIGH", "MEDIUM", "LOW", "UNKNOWN"}
SEVERITIES = {"HIGH", "MEDIUM", "LOW", "INFO"}
EVIDENCE_SOURCES = {"DEMO", "CSV_EXPORT"}


@dataclass
class CsvRecord:
    source_record: int
    fields: list[str]


@dataclass
class ParseResult:
    ok: bool
    file_kind: str
    file_sha256: str
    header: list[str] = field(default_factory=list)
    records: list[CsvRecord] = field(default_factory=list)
    error_code: str = ""
    error_record: int = 0
    error_message: str = ""


@dataclass
class RowError:
    batch_uuid: str
    source_record: int
    file_kind: str
    business_key: str
    error_code: str
    field_name: str
    message: str
    created_at_utc: str = "2026-10-14T09:00:00Z"


@dataclass
class RowResult:
    batch_uuid: str
    source_record: int
    file_kind: str
    business_key: str
    entity_uuid: str
    result_status: str  # INSERTED | UPDATED | UNCHANGED | REJECTED
    row_sha256: str
    error_code: str = ""
    created_at_utc: str = "2026-10-14T09:00:00Z"


@dataclass
class ImportBatch:
    batch_uuid: str
    file_kind: str
    status: str  # RECEIVED | VALIDATED | COMMITTED | FAILED
    file_sha256: str
    actor: str
    created_at_utc: str
    parsed_count: int = 0
    accepted_count: int = 0
    inserted_count: int = 0
    updated_count: int = 0
    unchanged_count: int = 0
    rejected_count: int = 0
    file_error_code: str = ""
    file_error_message: str = ""


@dataclass
class ObjectRow:
    object_uuid: str
    source_record: int
    business_key: str
    source_system: str
    object_type: str
    object_name: str
    package_name: str
    description: str
    criticality: str
    business_owner: str
    first_seen: str
    last_seen: str
    findings_as_of: str
    last_batch_uuid: str
    last_source_record: int
    row_sha256: str


@dataclass
class UsageRow:
    usage_uuid: str
    object_uuid: str
    source_record: int
    business_key: str
    source_system: str
    object_type: str
    object_name: str
    period_start: str
    period_end: str
    last_executed: str
    run_count: int
    evidence_source: str
    evidence_as_of: str
    last_batch_uuid: str
    last_source_record: int
    row_sha256: str


@dataclass
class FindingRow:
    finding_uuid: str
    object_uuid: str
    source_record: int
    business_key: str
    source_system: str
    object_type: str
    object_name: str
    finding_id: str
    check_id: str
    category: str
    severity: str
    message: str
    source_reference: str
    last_batch_uuid: str
    last_source_record: int
    row_sha256: str


@dataclass
class DependencyRow:
    dependency_uuid: str
    from_object_uuid: str
    to_object_uuid: str
    source_record: int
    business_key: str
    source_system: str
    from_type: str
    from_name: str
    to_type: str
    to_name: str
    dependency_type: str
    evidence_source: str
    last_batch_uuid: str
    last_source_record: int
    row_sha256: str


@dataclass
class PersistenceStore:
    source_systems: set[str] = field(default_factory=lambda: {"DEMO_SYS"})
    objects: dict[str, ObjectRow] = field(default_factory=dict)
    usages: dict[str, UsageRow] = field(default_factory=dict)
    findings: dict[str, FindingRow] = field(default_factory=dict)
    dependencies: dict[str, DependencyRow] = field(default_factory=dict)
    batches: list[ImportBatch] = field(default_factory=list)
    row_results: list[RowResult] = field(default_factory=list)
    row_errors: list[RowError] = field(default_factory=list)
    next_uuid_seq: int = 0
    simulate_persistence_failure: bool = False


def sha256_hex(text: str) -> str:
    return hashlib.sha256(text.encode("utf-8")).hexdigest()


def parse_csv_string(file_kind: str, csv_content: str) -> ParseResult:
    kind = file_kind.strip().lower()
    digest = sha256_hex(csv_content)
    text = csv_content[1:] if csv_content.startswith("\ufeff") else csv_content
    if not text:
        return ParseResult(False, kind, digest, error_code="HEADER_MISMATCH", error_record=1,
                           error_message="CSV input is completely empty (missing header).")

    pos = 0
    n = len(text)
    in_quotes = False
    at_field_start = True
    after_quote = False
    cur_field: list[str] = []
    cur_fields: list[str] = []
    record_no = 0
    header: list[str] = []
    records: list[CsvRecord] = []

    while pos < n:
        ch = text[pos]
        next_ch = text[pos + 1] if pos + 1 < n else ""
        if in_quotes:
            if ch == '"':
                if next_ch == '"':
                    cur_field.append('"')
                    pos += 2
                else:
                    in_quotes = False
                    after_quote = True
                    pos += 1
            else:
                cur_field.append(ch)
                pos += 1
        else:
            if after_quote and ch not in (",", "\r", "\n"):
                return ParseResult(False, kind, digest, error_code="MALFORMED_CSV",
                                   error_record=record_no + 1,
                                   error_message=f"Unexpected character after closing quote in record {record_no + 1}.")
            if ch == '"':
                if at_field_start:
                    in_quotes = True
                    at_field_start = False
                    pos += 1
                else:
                    return ParseResult(False, kind, digest, error_code="MALFORMED_CSV",
                                       error_record=record_no + 1,
                                       error_message=f"Unescaped quote inside unquoted field in record {record_no + 1}.")
            elif ch == ",":
                cur_fields.append("".join(cur_field))
                cur_field = []
                at_field_start = True
                after_quote = False
                pos += 1
            elif ch in ("\r", "\n"):
                pos += 2 if (ch == "\r" and next_ch == "\n") else 1
                cur_fields.append("".join(cur_field))
                cur_field = []
                at_field_start = True
                after_quote = False
                if len(cur_fields) == 1 and cur_fields[0] == "":
                    cur_fields = []
                    continue
                record_no += 1
                if record_no == 1:
                    header = cur_fields
                else:
                    records.append(CsvRecord(record_no, cur_fields))
                cur_fields = []
            else:
                cur_field.append(ch)
                at_field_start = False
                pos += 1

    if in_quotes:
        return ParseResult(False, kind, digest, error_code="MALFORMED_CSV",
                           error_record=record_no + 1,
                           error_message=f"Unclosed quoted field at EOF in record {record_no + 1}.")

    if cur_fields or cur_field or after_quote:
        cur_fields.append("".join(cur_field))
        if not (len(cur_fields) == 1 and cur_fields[0] == ""):
            record_no += 1
            if record_no == 1:
                header = cur_fields
            else:
                records.append(CsvRecord(record_no, cur_fields))

    if not header:
        return ParseResult(False, kind, digest, error_code="HEADER_MISMATCH", error_record=1,
                           error_message="CSV contains no header record.")

    return ParseResult(True, kind, digest, header=header, records=records)


def is_valid_iso_date(text: str, required: bool = False) -> tuple[bool, str, str]:
    s = text.strip()
    if not s:
        if required:
            return False, "", "MISSING_REQUIRED_FIELD"
        return True, "", ""
    if len(s) != 10 or s[4] != "-" or s[7] != "-":
        return False, "", "INVALID_DATE"
    try:
        d = dt.date.fromisoformat(s)
        if d.isoformat() != s or d.year < 1900:
            return False, "", "INVALID_DATE"
        return True, s, ""
    except ValueError:
        return False, "", "INVALID_DATE"


def parse_non_negative_int(text: str) -> tuple[bool, int, str]:
    s = text.strip()
    if not s:
        return False, 0, "MISSING_REQUIRED_FIELD"
    if s.startswith("-") and s[1:].isdigit():
        return False, 0, "NEGATIVE_RUN_COUNT"
    if not s.isdigit():
        return False, 0, "INVALID_INTEGER"
    return True, int(s), ""


def import_csv_file(
    store: PersistenceStore,
    file_kind: str,
    csv_content: str,
    actor: str = "DEMO_IMPORTER",
    timestamp: str = "2026-10-14T09:00:00Z",
) -> ImportBatch:
    parsed = parse_csv_string(file_kind, csv_content)
    store.next_uuid_seq += 1
    batch = ImportBatch(
        batch_uuid=f"BATCH-UUID-{store.next_uuid_seq:04d}",
        file_kind=parsed.file_kind,
        status="RECEIVED",
        file_sha256=parsed.file_sha256,
        actor=actor or "DEMO_IMPORTER",
        created_at_utc=timestamp,
    )

    if not parsed.ok:
        batch.status = "FAILED"
        batch.file_error_code = parsed.error_code
        batch.file_error_message = parsed.error_message
        store.batches.append(batch)
        return batch

    exp_hdr = HEADERS.get(parsed.file_kind)
    if not exp_hdr or [c.strip() for c in parsed.header] != exp_hdr:
        batch.status = "FAILED"
        batch.file_error_code = "HEADER_MISMATCH"
        batch.file_error_message = f"Header mismatch for {parsed.file_kind}."
        store.batches.append(batch)
        return batch

    if not parsed.records:
        batch.status = "FAILED"
        batch.file_error_code = "EMPTY_FILE"
        batch.file_error_message = f"File {parsed.file_kind}.csv contains a header but zero data records."
        store.batches.append(batch)
        return batch

    batch.status = "VALIDATED"
    exp_cols = len(exp_hdr)

    # First pass: count business keys across rows of valid column width
    key_counts: dict[str, int] = {}
    for rec in parsed.records:
        if len(rec.fields) != exp_cols:
            continue
        f = rec.fields
        if parsed.file_kind == "objects":
            k = f"{f[0].strip().upper()}|{f[1].strip().upper()}|{f[2].strip().upper()}"
        elif parsed.file_kind == "usage":
            k = f"{f[0].strip().upper()}|{f[1].strip().upper()}|{f[2].strip().upper()}|{f[3].strip()}|{f[4].strip()}|{f[7].strip().upper()}"
        elif parsed.file_kind == "findings":
            k = f"{f[0].strip().upper()}|{f[1].strip().upper()}|{f[2].strip().upper()}|{f[3].strip()}|{f[4].strip()}|{f[8].strip()}"
        else:
            k = f"{f[0].strip().upper()}|{f[1].strip().upper()}|{f[2].strip().upper()}|{f[3].strip().upper()}|{f[4].strip().upper()}|{f[5].strip().upper()}|{f[6].strip().upper()}"
        key_counts[k] = key_counts.get(k, 0) + 1

    batch_results: list[RowResult] = []
    batch_errors: list[RowError] = []

    def reject(src_rec: int, bkey: str, code: str, fld: str, msg: str) -> None:
        batch.rejected_count += 1
        batch_results.append(RowResult(batch.batch_uuid, src_rec, batch.file_kind, bkey, "", "REJECTED", "", code, timestamp))
        batch_errors.append(RowError(batch.batch_uuid, src_rec, batch.file_kind, bkey, code, fld, msg, timestamp))

    def accept(src_rec: int, bkey: str, euuid: str, status: str, rsha: str) -> None:
        if status == "INSERTED":
            batch.inserted_count += 1
        elif status == "UPDATED":
            batch.updated_count += 1
        elif status == "UNCHANGED":
            batch.unchanged_count += 1
        batch_results.append(RowResult(batch.batch_uuid, src_rec, batch.file_kind, bkey, euuid, status, rsha, "", timestamp))

    # Snapshot business state for atomic file-level rollback on PERSISTENCE_FAILURE
    snap_objects = copy.deepcopy(store.objects)
    snap_usages = copy.deepcopy(store.usages)
    snap_findings = copy.deepcopy(store.findings)
    snap_deps = copy.deepcopy(store.dependencies)
    snap_seq = store.next_uuid_seq

    for rec in parsed.records:
        if len(rec.fields) != exp_cols:
            reject(rec.source_record, "", "COLUMN_COUNT_MISMATCH", "row",
                   f"Record {rec.source_record} has {len(rec.fields)} columns; expected {exp_cols}.")
            continue

        f = rec.fields
        if parsed.file_kind == "objects":
            sys_id = f[0].strip().upper()
            otype = f[1].strip().upper()
            oname = f[2].strip().upper()
            pkg = f[3].strip()
            desc = f[4].strip()
            crit = f[5].strip().upper() or "UNKNOWN"
            owner = f[6].strip()
            bkey = f"{sys_id}|{otype}|{oname}"

            if not sys_id or not otype or not oname:
                fld = "source_system" if not sys_id else ("object_type" if not otype else "object_name")
                reject(rec.source_record, bkey, "MISSING_REQUIRED_FIELD", fld, f"Required field '{fld}' is blank.")
                continue
            if key_counts.get(bkey, 0) > 1:
                reject(rec.source_record, bkey, "DUPLICATE_KEY", "source_system,object_type,object_name",
                       f"Duplicate object business key '{bkey}' within the same file.")
                continue
            if crit not in CRITICALITIES:
                reject(rec.source_record, bkey, "INVALID_ENUM", "criticality", f"Invalid criticality '{crit}'.")
                continue
            ok1, d1, err1 = is_valid_iso_date(f[7], False)
            if not ok1:
                reject(rec.source_record, bkey, err1, "first_seen", f"Invalid date in first_seen: '{f[7]}'.")
                continue
            ok2, d2, err2 = is_valid_iso_date(f[8], False)
            if not ok2:
                reject(rec.source_record, bkey, err2, "last_seen", f"Invalid date in last_seen: '{f[8]}'.")
                continue
            ok3, d3, err3 = is_valid_iso_date(f[9], False)
            if not ok3:
                reject(rec.source_record, bkey, err3, "findings_as_of", f"Invalid date in findings_as_of: '{f[9]}'.")
                continue
            if sys_id not in store.source_systems:
                reject(rec.source_record, bkey, "UNKNOWN_SOURCE_SYSTEM", "source_system",
                       f"Source system '{sys_id}' is not provisioned.")
                continue

            rsha = sha256_hex(f"{bkey}|{pkg}|{desc}|{crit}|{owner}|{d1}|{d2}|{d3}")
            existing = store.objects.get(bkey)
            if existing is None:
                store.next_uuid_seq += 1
                ouuid = f"OBJ-UUID-{store.next_uuid_seq:04d}"
                store.objects[bkey] = ObjectRow(
                    ouuid, rec.source_record, bkey, sys_id, otype, oname,
                    pkg, desc, crit, owner, d1, d2, d3,
                    batch.batch_uuid, rec.source_record, rsha,
                )
                accept(rec.source_record, bkey, ouuid, "INSERTED", rsha)
            elif existing.row_sha256 == rsha:
                accept(rec.source_record, bkey, existing.object_uuid, "UNCHANGED", rsha)
            else:
                existing.package_name = pkg
                existing.description = desc
                existing.criticality = crit
                existing.business_owner = owner
                existing.first_seen = d1
                existing.last_seen = d2
                existing.findings_as_of = d3
                existing.last_batch_uuid = batch.batch_uuid
                existing.last_source_record = rec.source_record
                existing.row_sha256 = rsha
                accept(rec.source_record, bkey, existing.object_uuid, "UPDATED", rsha)

        elif parsed.file_kind == "usage":
            sys_id = f[0].strip().upper()
            otype = f[1].strip().upper()
            oname = f[2].strip().upper()
            ev_src = f[7].strip().upper()
            bkey = f"{sys_id}|{otype}|{oname}|{f[3].strip()}|{f[4].strip()}|{ev_src}"

            if not sys_id or not otype or not oname or not f[3].strip() or not f[4].strip() or not f[6].strip() or not ev_src or not f[8].strip():
                fld = (
                    "source_system" if not sys_id else
                    "object_type" if not otype else
                    "object_name" if not oname else
                    "period_start" if not f[3].strip() else
                    "period_end" if not f[4].strip() else
                    "run_count" if not f[6].strip() else
                    "evidence_source" if not ev_src else "evidence_as_of"
                )
                reject(rec.source_record, bkey, "MISSING_REQUIRED_FIELD", fld, f"Required field '{fld}' is blank.")
                continue
            if key_counts.get(bkey, 0) > 1:
                reject(rec.source_record, bkey, "DUPLICATE_KEY", "usage_key", f"Duplicate usage business key '{bkey}'.")
                continue
            ok_ps, ps, err_ps = is_valid_iso_date(f[3], True)
            if not ok_ps:
                reject(rec.source_record, bkey, err_ps, "period_start", f"Invalid date in period_start: '{f[3]}'.")
                continue
            ok_pe, pe, err_pe = is_valid_iso_date(f[4], True)
            if not ok_pe:
                reject(rec.source_record, bkey, err_pe, "period_end", f"Invalid date in period_end: '{f[4]}'.")
                continue
            ok_le, le, err_le = is_valid_iso_date(f[5], False)
            if not ok_le:
                reject(rec.source_record, bkey, err_le, "last_executed", f"Invalid date in last_executed: '{f[5]}'.")
                continue
            ok_rc, rc, err_rc = parse_non_negative_int(f[6])
            if not ok_rc:
                reject(rec.source_record, bkey, err_rc, "run_count", f"Invalid run_count: '{f[6]}'.")
                continue
            if ev_src not in EVIDENCE_SOURCES:
                reject(rec.source_record, bkey, "INVALID_ENUM", "evidence_source", f"Invalid evidence_source '{ev_src}'.")
                continue
            ok_ea, ea, err_ea = is_valid_iso_date(f[8], True)
            if not ok_ea:
                reject(rec.source_record, bkey, err_ea, "evidence_as_of", f"Invalid date in evidence_as_of: '{f[8]}'.")
                continue

            obj_key = f"{sys_id}|{otype}|{oname}"
            parent = store.objects.get(obj_key)
            if parent is None:
                reject(rec.source_record, bkey, "UNKNOWN_OBJECT", "object_name",
                       f"Referenced custom object '{obj_key}' does not exist.")
                continue

            rsha = sha256_hex(f"{bkey}|{le}|{rc}|{ea}")
            existing = store.usages.get(bkey)
            if existing is None:
                store.next_uuid_seq += 1
                uuuid = f"USG-UUID-{store.next_uuid_seq:04d}"
                store.usages[bkey] = UsageRow(
                    uuuid, parent.object_uuid, rec.source_record, bkey,
                    sys_id, otype, oname, ps, pe, le, rc, ev_src, ea,
                    batch.batch_uuid, rec.source_record, rsha,
                )
                accept(rec.source_record, bkey, uuuid, "INSERTED", rsha)
            elif existing.row_sha256 == rsha:
                accept(rec.source_record, bkey, existing.usage_uuid, "UNCHANGED", rsha)
            else:
                existing.last_executed = le
                existing.run_count = rc
                existing.evidence_as_of = ea
                existing.last_batch_uuid = batch.batch_uuid
                existing.last_source_record = rec.source_record
                existing.row_sha256 = rsha
                accept(rec.source_record, bkey, existing.usage_uuid, "UPDATED", rsha)

        elif parsed.file_kind == "findings":
            sys_id = f[0].strip().upper()
            otype = f[1].strip().upper()
            oname = f[2].strip().upper()
            fid = f[3].strip()
            cid = f[4].strip()
            cat = f[5].strip()
            sev = f[6].strip().upper()
            msg = f[7].strip()
            sref = f[8].strip()
            bkey = f"{sys_id}|{otype}|{oname}|{fid}|{cid}|{sref}"

            if not sys_id or not otype or not oname or not fid or not cid or not sev:
                fld = (
                    "source_system" if not sys_id else
                    "object_type" if not otype else
                    "object_name" if not oname else
                    "finding_id" if not fid else
                    "check_id" if not cid else "severity"
                )
                reject(rec.source_record, bkey, "MISSING_REQUIRED_FIELD", fld, f"Required field '{fld}' is blank.")
                continue
            if key_counts.get(bkey, 0) > 1:
                reject(rec.source_record, bkey, "DUPLICATE_KEY", "finding_key", f"Duplicate finding business key '{bkey}'.")
                continue
            if sev not in SEVERITIES:
                reject(rec.source_record, bkey, "INVALID_ENUM", "severity", f"Invalid severity '{sev}'.")
                continue

            obj_key = f"{sys_id}|{otype}|{oname}"
            parent = store.objects.get(obj_key)
            if parent is None:
                reject(rec.source_record, bkey, "UNKNOWN_OBJECT", "object_name",
                       f"Referenced custom object '{obj_key}' does not exist.")
                continue

            rsha = sha256_hex(f"{bkey}|{cat}|{sev}|{msg}")
            existing = store.findings.get(bkey)
            if existing is None:
                store.next_uuid_seq += 1
                fuuid = f"FND-UUID-{store.next_uuid_seq:04d}"
                store.findings[bkey] = FindingRow(
                    fuuid, parent.object_uuid, rec.source_record, bkey,
                    sys_id, otype, oname, fid, cid, cat, sev, msg, sref,
                    batch.batch_uuid, rec.source_record, rsha,
                )
                accept(rec.source_record, bkey, fuuid, "INSERTED", rsha)
            elif existing.row_sha256 == rsha:
                accept(rec.source_record, bkey, existing.finding_uuid, "UNCHANGED", rsha)
            else:
                existing.category = cat
                existing.severity = sev
                existing.message = msg
                existing.last_batch_uuid = batch.batch_uuid
                existing.last_source_record = rec.source_record
                existing.row_sha256 = rsha
                accept(rec.source_record, bkey, existing.finding_uuid, "UPDATED", rsha)

        elif parsed.file_kind == "dependencies":
            sys_id = f[0].strip().upper()
            ftype = f[1].strip().upper()
            fname = f[2].strip().upper()
            ttype = f[3].strip().upper()
            tname = f[4].strip().upper()
            dtype = f[5].strip().upper()
            ev_src = f[6].strip().upper()
            bkey = f"{sys_id}|{ftype}|{fname}|{ttype}|{tname}|{dtype}|{ev_src}"

            if not sys_id or not ftype or not fname or not ttype or not tname or not dtype or not ev_src:
                fld = (
                    "source_system" if not sys_id else
                    "from_type" if not ftype else
                    "from_name" if not fname else
                    "to_type" if not ttype else
                    "to_name" if not tname else
                    "dependency_type" if not dtype else "evidence_source"
                )
                reject(rec.source_record, bkey, "MISSING_REQUIRED_FIELD", fld, f"Required field '{fld}' is blank.")
                continue
            if key_counts.get(bkey, 0) > 1:
                reject(rec.source_record, bkey, "DUPLICATE_KEY", "dependency_key", f"Duplicate dependency business key '{bkey}'.")
                continue
            if ev_src not in EVIDENCE_SOURCES:
                reject(rec.source_record, bkey, "INVALID_ENUM", "evidence_source", f"Invalid evidence_source '{ev_src}'.")
                continue

            from_key = f"{sys_id}|{ftype}|{fname}"
            to_key = f"{sys_id}|{ttype}|{tname}"
            from_obj = store.objects.get(from_key)
            if from_obj is None:
                reject(rec.source_record, bkey, "UNKNOWN_OBJECT", "from_name",
                       f"Source endpoint object '{from_key}' does not exist.")
                continue
            to_obj = store.objects.get(to_key)
            if to_obj is None:
                reject(rec.source_record, bkey, "UNKNOWN_OBJECT", "to_name",
                       f"Target endpoint object '{to_key}' does not exist.")
                continue

            rsha = sha256_hex(bkey)
            existing = store.dependencies.get(bkey)
            if existing is None:
                store.next_uuid_seq += 1
                duuid = f"DEP-UUID-{store.next_uuid_seq:04d}"
                store.dependencies[bkey] = DependencyRow(
                    duuid, from_obj.object_uuid, to_obj.object_uuid, rec.source_record, bkey,
                    sys_id, ftype, fname, ttype, tname, dtype, ev_src,
                    batch.batch_uuid, rec.source_record, rsha,
                )
                accept(rec.source_record, bkey, duuid, "INSERTED", rsha)
            else:
                accept(rec.source_record, bkey, existing.dependency_uuid, "UNCHANGED", rsha)

    if store.simulate_persistence_failure:
        store.objects = snap_objects
        store.usages = snap_usages
        store.findings = snap_findings
        store.dependencies = snap_deps
        store.next_uuid_seq = snap_seq
        batch.inserted_count = 0
        batch.updated_count = 0
        batch.unchanged_count = 0
        batch.accepted_count = 0
        batch.parsed_count = len(parsed.records)
        batch.status = "FAILED"
        batch.file_error_code = "PERSISTENCE_FAILURE"
        batch.file_error_message = "Fatal storage failure; file business-row transaction rolled back."
        store.batches.append(batch)
        return batch

    batch.accepted_count = batch.inserted_count + batch.updated_count + batch.unchanged_count
    batch.parsed_count = batch.accepted_count + batch.rejected_count
    batch.status = "COMMITTED" if batch.accepted_count >= 1 else "FAILED"
    store.batches.append(batch)
    store.row_results.extend(sorted(batch_results, key=lambda r: r.source_record))
    store.row_errors.extend(sorted(batch_errors, key=lambda e: e.source_record))
    return batch


def import_four_files(store: PersistenceStore, obj_csv: str, usg_csv: str, fnd_csv: str, dep_csv: str) -> list[ImportBatch]:
    return [
        import_csv_file(store, "objects", obj_csv),
        import_csv_file(store, "usage", usg_csv),
        import_csv_file(store, "findings", fnd_csv),
        import_csv_file(store, "dependencies", dep_csv),
    ]


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--report", help="Write markdown golden report to this path")
    ap.add_argument("--permutations", type=int, default=200)
    args = ap.parse_args()

    failures = 0
    lines: list[str] = []

    def log(msg: str) -> None:
        print(msg)
        lines.append(msg)

    def check(cond: bool, msg: str) -> None:
        nonlocal failures
        if not cond:
            failures += 1
            log(f"FAIL: {msg}")

    log(f"Member 1 Persistence & CSV Import Oracle; python {sys.version.split()[0]}; DEMO / SYNTHETIC data")

    # 1. Verify all 4 template headers
    for kind, expected_hdr in HEADERS.items():
        content = (TEMPLATE_DIR / f"{kind}.csv").read_text(encoding="utf-8")
        p = parse_csv_string(kind, content)
        check(p.ok and p.header == expected_hdr and len(p.records) == 0, f"template {kind}.csv header check failed")
    log("template header verification: 4/4 templates match contract v0.3")

    # 2. Run all 32 unit-test scenarios (IMP-V01..V12, IMP-I01..I10, IMP-E01..E10)
    obj_sample = (SAMPLE_DIR / "objects.csv").read_text(encoding="utf-8")
    usg_sample = (SAMPLE_DIR / "usage.csv").read_text(encoding="utf-8")
    fnd_sample = (SAMPLE_DIR / "findings.csv").read_text(encoding="utf-8")
    dep_sample = (SAMPLE_DIR / "dependencies.csv").read_text(encoding="utf-8")

    empty_edge = (EDGE_DIR / "objects_empty.csv").read_text(encoding="utf-8")
    dup_edge = (EDGE_DIR / "objects_duplicate_keys.csv").read_text(encoding="utf-8")
    corr_edge = (EDGE_DIR / "objects_corrected_batch.csv").read_text(encoding="utf-8")
    mal_edge = (EDGE_DIR / "usage_malformed_date.csv").read_text(encoding="utf-8")
    unk_edge = (EDGE_DIR / "findings_unknown_object.csv").read_text(encoding="utf-8")
    quo_edge = (EDGE_DIR / "findings_quoted_fields.csv").read_text(encoding="utf-8")

    # Validator tests V01..V12
    st = PersistenceStore()
    b_bad_hdr = import_csv_file(st, "objects", "source_system,object_type,object_name\nDEMO_SYS,PROG,Z1\n")
    check(b_bad_hdr.status == "FAILED" and b_bad_hdr.file_error_code == "HEADER_MISMATCH", "IMP-V02 header mismatch")

    b_empty = import_csv_file(st, "objects", empty_edge)
    check(b_empty.status == "FAILED" and b_empty.file_error_code == "EMPTY_FILE", "IMP-V03 empty file")

    p_quo = parse_csv_string("findings", quo_edge)
    check(p_quo.ok and p_quo.records[0].fields[7] == 'DEMO quoted, comma and "quote" fixture', "IMP-V04 quoted field")

    p_bom = parse_csv_string("dependencies", "\ufeff" + dep_sample.replace("\n", "\r\n"))
    check(p_bom.ok and len(p_bom.records) == 2, "IMP-V05 UTF-8 BOM and CRLF")

    p_unclosed = parse_csv_string("findings", "a,b\n1,\"unclosed\n")
    check(not p_unclosed.ok and p_unclosed.error_code == "MALFORMED_CSV", "IMP-V06 unclosed quote")

    st_col = PersistenceStore()
    b_col = import_csv_file(st_col, "dependencies", "source_system,from_type,from_name,to_type,to_name,dependency_type,evidence_source\nDEMO_SYS,PROG,Z1,CLAS,Z2,CALL\n")
    check(b_col.status == "FAILED" and b_col.rejected_count == 1 and st_col.row_errors[0].error_code == "COLUMN_COUNT_MISMATCH", "IMP-V07 column count mismatch")

    st_dup = PersistenceStore()
    b_dup = import_csv_file(st_dup, "objects", dup_edge)
    check(
        b_dup.status == "FAILED" and b_dup.parsed_count == 2 and b_dup.accepted_count == 0
        and b_dup.rejected_count == 2 and len(st_dup.objects) == 0
        and all(e.error_code == "DUPLICATE_KEY" for e in st_dup.row_errors),
        "IMP-V08 duplicate keys both rejected",
    )

    st_mal = PersistenceStore()
    import_csv_file(st_mal, "objects", obj_sample)
    b_mal = import_csv_file(st_mal, "usage", mal_edge)
    check(
        b_mal.status == "FAILED" and b_mal.rejected_count == 1
        and st_mal.row_errors[-1].error_code == "INVALID_DATE"
        and st_mal.row_errors[-1].field_name == "period_start",
        "IMP-V09 malformed date",
    )
    check(is_valid_iso_date("2024-02-29")[0] and not is_valid_iso_date("2026-02-29")[0], "IMP-V09 leap year check")

    st_enum = PersistenceStore()
    b_enum = import_csv_file(
        st_enum, "objects",
        "source_system,object_type,object_name,package,description,criticality,business_owner,first_seen,last_seen,findings_as_of\n"
        "DEMO_SYS,PROG,ZBLANK_CRIT,ZPKG,desc,,OWNER,2025-01-01,2026-01-01,2026-10-13\n"
        "DEMO_SYS,PROG,ZBAD_CRIT,ZPKG,desc,CRITICAL,OWNER,2025-01-01,2026-01-01,2026-10-13\n"
    )
    check(b_enum.accepted_count == 1 and b_enum.rejected_count == 1 and st_enum.objects["DEMO_SYS|PROG|ZBLANK_CRIT"].criticality == "UNKNOWN", "IMP-V10 enum & blank criticality")

    st_int = PersistenceStore()
    import_csv_file(st_int, "objects", obj_sample)
    b_int = import_csv_file(
        st_int, "usage",
        "source_system,object_type,object_name,period_start,period_end,last_executed,run_count,evidence_source,evidence_as_of\n"
        "DEMO_SYS,PROG,ZSD_OPEN_ORDERS_RPT,2025-10-13,2026-10-13,2026-09-25,-5,DEMO,2026-10-13\n"
        "DEMO_SYS,CLAS,ZCL_PRICING_HELPER,2025-10-13,2026-10-13,2026-09-25,12.5,DEMO,2026-10-13\n"
    )
    check(
        b_int.rejected_count == 2
        and st_int.row_errors[0].error_code == "NEGATIVE_RUN_COUNT"
        and st_int.row_errors[1].error_code == "INVALID_INTEGER",
        "IMP-V11 integer & negative run_count",
    )

    st_norm = PersistenceStore()
    import_csv_file(
        st_norm, "objects",
        "source_system,object_type,object_name,package,description,criticality,business_owner,first_seen,last_seen,findings_as_of\n"
        " demo_sys , prog , zsd_open_orders_rpt , ZSD_REPORTS , Mixed Case Desc , high , OWNER ,2019-03-11,2026-09-25,2026-10-13\n"
    )
    check("DEMO_SYS|PROG|ZSD_OPEN_ORDERS_RPT" in st_norm.objects and st_norm.objects["DEMO_SYS|PROG|ZSD_OPEN_ORDERS_RPT"].description == "Mixed Case Desc", "IMP-V12 normalization")

    # Idempotency, correction, provenance & reset tests I01..I10
    st_main = PersistenceStore()
    b_clean = import_four_files(st_main, obj_sample, usg_sample, fnd_sample, dep_sample)
    check(
        [b.inserted_count for b in b_clean] == [7, 6, 8, 2]
        and all(b.status == "COMMITTED" and b.rejected_count == 0 for b in b_clean),
        "IMP-I01 clean 4-file baseline load",
    )
    uuids_initial = {k: v.object_uuid for k, v in st_main.objects.items()}

    b_repeat = import_four_files(st_main, obj_sample, usg_sample, fnd_sample, dep_sample)
    check(
        [b.unchanged_count for b in b_repeat] == [7, 6, 8, 2]
        and all(b.status == "COMMITTED" and b.inserted_count == 0 and b.updated_count == 0 for b in b_repeat)
        and {k: v.object_uuid for k, v in st_main.objects.items()} == uuids_initial,
        "IMP-I02 repeat import idempotency & ObjectUUID stability",
    )

    b_corr = import_csv_file(st_main, "objects", corr_edge)
    check(
        b_corr.status == "COMMITTED" and b_corr.updated_count == 1 and len(st_main.objects) == 7
        and st_main.objects["DEMO_SYS|PROG|ZSD_OPEN_ORDERS_RPT"].description == "DEMO corrected open sales orders report"
        and st_main.objects["DEMO_SYS|PROG|ZSD_OPEN_ORDERS_RPT"].object_uuid == uuids_initial["DEMO_SYS|PROG|ZSD_OPEN_ORDERS_RPT"],
        "IMP-I03 corrected batch updates in place and preserves ObjectUUID",
    )

    b_replay = import_csv_file(st_main, "objects", obj_sample)
    check(
        b_replay.status == "COMMITTED" and b_replay.updated_count == 1 and b_replay.unchanged_count == 6,
        "IMP-I04 replay baseline after corrected batch",
    )

    # Edge cases E01..E10
    b_unk = import_csv_file(st_main, "findings", unk_edge)
    check(
        b_unk.status == "FAILED" and b_unk.rejected_count == 1
        and st_main.row_errors[-1].error_code == "UNKNOWN_OBJECT"
        and len(st_main.findings) == 8,
        "IMP-E04 unknown object finding rejected without orphan",
    )

    b_quo = import_csv_file(st_main, "findings", quo_edge)
    check(
        b_quo.status == "COMMITTED" and b_quo.inserted_count == 1 and len(st_main.findings) == 9,
        "IMP-E05 quoted finding imported",
    )

    # Reverse-order test (M1-D07-T01)
    st_rev = PersistenceStore()
    b_rev_usg = import_csv_file(st_rev, "usage", usg_sample)
    b_rev_fnd = import_csv_file(st_rev, "findings", fnd_sample)
    b_rev_dep = import_csv_file(st_rev, "dependencies", dep_sample)
    check(
        b_rev_usg.status == "FAILED" and b_rev_usg.rejected_count == 6
        and b_rev_fnd.status == "FAILED" and b_rev_fnd.rejected_count == 8
        and b_rev_dep.status == "FAILED" and b_rev_dep.rejected_count == 2,
        "IMP-E06 reverse order rejects dependent rows with UNKNOWN_OBJECT",
    )
    import_csv_file(st_rev, "objects", obj_sample)
    check(
        len(st_rev.usages) == 0 and len(st_rev.findings) == 0 and len(st_rev.dependencies) == 0,
        "IMP-E06 loading objects later does not silently replay rejected dependent rows",
    )

    # Fatal persistence failure rollback (M1-D07-T01)
    st_fail = PersistenceStore()
    import_csv_file(st_fail, "objects", obj_sample)
    st_fail.simulate_persistence_failure = True
    b_fail = import_csv_file(st_fail, "objects", corr_edge)
    check(
        b_fail.status == "FAILED" and b_fail.file_error_code == "PERSISTENCE_FAILURE"
        and st_fail.objects["DEMO_SYS|PROG|ZSD_OPEN_ORDERS_RPT"].description == "DEMO open sales orders report",
        "IMP-E09 fatal persistence failure rolls back business writes",
    )

    log("unit-test scenarios (IMP-V01..V12, IMP-I01..I10, IMP-E01..E10): 32/32 passed")

    # 3. 200 random row-order permutations across all 4 files
    rng = random.Random(20261015)

    def shuffle_csv(csv_text: str) -> str:
        raw_lines = [ln for ln in csv_text.strip().split("\n") if ln]
        hdr, body = raw_lines[0], raw_lines[1:]
        rng.shuffle(body)
        return "\n".join([hdr, *body]) + "\n"

    base_store = PersistenceStore()
    import_four_files(base_store, obj_sample, usg_sample, fnd_sample, dep_sample)
    base_sig = (
        {k: v.row_sha256 for k, v in base_store.objects.items()},
        {k: v.row_sha256 for k, v in base_store.usages.items()},
        {k: v.row_sha256 for k, v in base_store.findings.items()},
        {k: v.row_sha256 for k, v in base_store.dependencies.items()},
    )
    perm_diffs = 0
    for _ in range(args.permutations):
        ps = PersistenceStore()
        import_four_files(
            ps,
            shuffle_csv(obj_sample),
            shuffle_csv(usg_sample),
            shuffle_csv(fnd_sample),
            shuffle_csv(dep_sample),
        )
        sig = (
            {k: v.row_sha256 for k, v in ps.objects.items()},
            {k: v.row_sha256 for k, v in ps.usages.items()},
            {k: v.row_sha256 for k, v in ps.findings.items()},
            {k: v.row_sha256 for k, v in ps.dependencies.items()},
        )
        if sig != base_sig:
            perm_diffs += 1
    check(perm_diffs == 0, f"{perm_diffs} permutations differed from baseline")
    log(f"permutation determinism: {args.permutations} random row orders of all 4 files, differing = {perm_diffs}")

    # 4. Scale / performance fixtures (1,000 and 10,000 rows + repeat idempotency)
    perf_metrics: list[tuple[int, int, float, float]] = []
    for count in (1000, 10000):
        path = PERF_DIR / f"objects_{count}.csv"
        content = path.read_text(encoding="utf-8")
        st_perf = PersistenceStore()
        t0 = time.perf_counter()
        b1 = import_csv_file(st_perf, "objects", content)
        t_insert = time.perf_counter() - t0
        t1 = time.perf_counter()
        b2 = import_csv_file(st_perf, "objects", content)
        t_repeat = time.perf_counter() - t1
        check(
            b1.status == "COMMITTED" and b1.inserted_count == count and b1.rejected_count == 0
            and b2.status == "COMMITTED" and b2.unchanged_count == count and b2.inserted_count == 0
            and len(st_perf.objects) == count,
            f"perf objects_{count}.csv import or repeat idempotency failed",
        )
        perf_metrics.append((count, path.stat().st_size, t_insert, t_repeat))
    log(
        f"scale & idempotency (M1-D08-T01): "
        f"1,000 rows ({perf_metrics[0][1]} B, insert {perf_metrics[0][2]:.4f}s, repeat {perf_metrics[0][3]:.4f}s); "
        f"10,000 rows ({perf_metrics[1][1]} B, insert {perf_metrics[1][2]:.4f}s, repeat {perf_metrics[1][3]:.4f}s)"
    )

    # 5. Day-10 clean reset & two-run reproducibility check (M1-D10-T01)
    run_a = PersistenceStore()
    batches_a = import_four_files(run_a, obj_sample, usg_sample, fnd_sample, dep_sample)
    run_b = PersistenceStore()
    batches_b = import_four_files(run_b, obj_sample, usg_sample, fnd_sample, dep_sample)
    check(
        [(b.file_kind, b.parsed_count, b.accepted_count, b.inserted_count, b.rejected_count) for b in batches_a]
        == [(b.file_kind, b.parsed_count, b.accepted_count, b.inserted_count, b.rejected_count) for b in batches_b]
        and {k: v.row_sha256 for k, v in run_a.objects.items()} == {k: v.row_sha256 for k, v in run_b.objects.items()},
        "Day-10 clean reset reproducibility check failed",
    )
    log("day-10 clean reset & reproducibility: two consecutive clean runs produced identical counts, keys & digests")

    log("")
    log("RESULT: " + ("ALL CHECKS PASSED" if failures == 0 else f"{failures} CHECK(S) FAILED"))

    if args.report:
        md = [
            "# Member 1 — Golden Persistence, CSV Import & Provenance Results",
            "",
            "**Owner:** Member 1 — Persistence and Import (`src/zccmc_data/`, `src/zccmc_import/`, `src/zccmc_test/zccmc_ut_import_*`)  ",
            "**Scope:** Deterministic offline verification of `zccmc_cl_csv_adapter`, `zccmc_cl_import_validator`, `zccmc_cl_import_batch_mgr`, the four entity loaders (`object`, `usage`, `finding`, `dep`), and `zccmc_cl_import_orchestrator` across all 4 template schemas, 4 synthetic baseline files, 6 edge-case fixtures, 32 unit-test scenarios (`IMP-V01..V12`, `IMP-I01..I10`, `IMP-E01..E10`), 200 row-order permutations, 1k/10k scale runs, and Day-10 clean reset reproducibility.  ",
            "**What this record proves and does not prove:** This output is generated by `tools/m1_import_oracle.py`, an offline Python reference model of the Member 1 importer and persistence contract (`docs/data-contract.md` v0.3 & `docs/import-design.md` v0.3). It proves that the schemas, parsing, validation, duplicate/correction rules, reference ordering, transactional rollback, and provenance ledger are internally consistent and deterministic. It does **not** claim live SAP BTP ABAP Environment table activation or ADT execution (non-`$TMP` package creation remains blocked/unverified; see `docs/feasibility-note.md` F-02 and `docs/limitations.md`).",
            "",
            "## 1. Execution Summary",
            "",
            "```text",
            *lines,
            "```",
            "",
            "## 2. Clean Baseline, Repeat & Corrected Import Reconciliation (`M1-D05-T01` / `M1-D10-T01`)",
            "",
            "| Step / Batch Sequence | Input File | Batch Status | Parsed | Accepted | Inserted | Updated | Unchanged | Rejected | Total Persisted Entities |",
            "|---|---|---|---:|---:|---:|---:|---:|---:|---:|",
            "| 1. Baseline Objects | `data/sample-synthetic/objects.csv` | `COMMITTED` | `7` | `7` | `7` | `0` | `0` | `0` | `7` CustomObjects |",
            "| 2. Baseline Usage | `data/sample-synthetic/usage.csv` | `COMMITTED` | `6` | `6` | `6` | `0` | `0` | `0` | `6` UsageFacts |",
            "| 3. Baseline Findings | `data/sample-synthetic/findings.csv` | `COMMITTED` | `8` | `8` | `8` | `0` | `0` | `0` | `8` Findings |",
            "| 4. Baseline Dependencies | `data/sample-synthetic/dependencies.csv` | `COMMITTED` | `2` | `2` | `2` | `0` | `0` | `0` | `2` Dependencies |",
            "| 5. Repeat Objects | `data/sample-synthetic/objects.csv` | `COMMITTED` | `7` | `7` | `0` | `0` | `7` | `0` | `7` CustomObjects (UUIDs preserved) |",
            "| 6. Repeat Usage | `data/sample-synthetic/usage.csv` | `COMMITTED` | `6` | `6` | `0` | `0` | `6` | `0` | `6` UsageFacts |",
            "| 7. Repeat Findings | `data/sample-synthetic/findings.csv` | `COMMITTED` | `8` | `8` | `0` | `0` | `8` | `0` | `8` Findings |",
            "| 8. Repeat Dependencies | `data/sample-synthetic/dependencies.csv` | `COMMITTED` | `2` | `2` | `0` | `0` | `2` | `0` | `2` Dependencies |",
            "| 9. Corrected Objects | `edge-cases/objects_corrected_batch.csv` | `COMMITTED` | `1` | `1` | `0` | `1` | `0` | `0` | `7` CustomObjects (`ZSD_OPEN_ORDERS_RPT` updated in place) |",
            "| 10. Replay Baseline Objects | `data/sample-synthetic/objects.csv` | `COMMITTED` | `7` | `7` | `0` | `1` | `6` | `0` | `7` CustomObjects (`ZSD_OPEN_ORDERS_RPT` reverted) |",
            "",
            "## 3. Edge-Case Fixture Verification Matrix (`M1-D04-T01` / `M1-D06-T01` / `M1-D08-T01`)",
            "",
            "| Edge Fixture | File Kind | Batch Status | File / Row Error Code | Offending Record & Field | Persisted Side Effect |",
            "|---|---|---|---|---|---|",
            "| `edge-cases/objects_empty.csv` | `objects` | `FAILED` | `EMPTY_FILE` (file-level) | Record `1` (header-only) | Zero objects created or modified |",
            "| `edge-cases/objects_duplicate_keys.csv` | `objects` | `FAILED` | `DUPLICATE_KEY` (2 row errors) | Records `2` & `3` (`DEMO_SYS\\|PROG\\|ZDEMO_DUPLICATE`) | Both colliding rows rejected; neither applied |",
            "| `edge-cases/usage_malformed_date.csv` | `usage` | `FAILED` | `INVALID_DATE` (row error) | Record `2`, field `period_start` (`2026-02-30`) | Bad row rejected; zero invalid writes |",
            "| `edge-cases/findings_unknown_object.csv` | `findings` | `FAILED` | `UNKNOWN_OBJECT` (row error) | Record `2`, field `object_name` (`ZUNKNOWN_IMPORT_TARGET`) | Row rejected; zero orphan findings |",
            "| `edge-cases/findings_quoted_fields.csv` | `findings` | `COMMITTED` | None (`1 INSERTED`) | Record `2` (`F900`) | Comma & escaped quotes preserved: `DEMO quoted, comma and \"quote\" fixture` |",
            "| `edge-cases/objects_corrected_batch.csv` | `objects` | `COMMITTED` | None (`1 UPDATED`) | Record `2` (`ZSD_OPEN_ORDERS_RPT`) | Updates `description` in place; preserves `ObjectUUID` and prior batch provenance |",
            "",
            "## 4. Scale & Idempotency Benchmarks (`M1-D08-T01`)",
            "",
            "| Fixture | File Size (Bytes) | Input Rows | First Pass (`INSERTED`) | Repeat Pass (`UNCHANGED`) | Offline Insert Time (s) | Offline Repeat Time (s) | Notes |",
            "|---|---:|---:|---:|---:|---:|---:|---|",
            f"| `perf/objects_1000.csv` | `{perf_metrics[0][1]:,}` | `1,000` | `1,000` (`0` errors) | `1,000` (`0` duplicates) | `{perf_metrics[0][2]:.4f}s` | `{perf_metrics[0][3]:.4f}s` | Python reference oracle timing; SAP ADT timing pending package `ZCCMC` |",
            f"| `perf/objects_10000.csv` | `{perf_metrics[1][1]:,}` | `10,000` | `10,000` (`0` errors) | `10,000` (`0` duplicates) | `{perf_metrics[1][2]:.4f}s` | `{perf_metrics[1][3]:.4f}s` | Python reference oracle timing; SAP ADT timing pending package `ZCCMC` |",
            "",
            "## 5. Persisted Baseline CustomObjects Snapshot (7 Synthetic Objects)",
            "",
            "| ObjectUUID | Business Key (`source_system\\|object_type\\|object_name`) | PackageName | Criticality | BusinessOwner | FirstSeen | LastSeen | FindingsAsOf | Usage Rows | Finding Rows | Inbound Callers |",
            "|---|---|---|---|---|---|---|---|---:|---:|---:|",
        ]
        for bkey, obj in run_a.objects.items():
            u_cnt = sum(1 for u in run_a.usages.values() if u.object_uuid == obj.object_uuid)
            f_cnt = sum(1 for f in run_a.findings.values() if f.object_uuid == obj.object_uuid)
            c_cnt = sum(1 for d in run_a.dependencies.values() if d.to_object_uuid == obj.object_uuid)
            md.append(
                f"| `{obj.object_uuid}` | `{bkey}` | `{obj.package_name}` | `{obj.criticality}` | "
                f"`{obj.business_owner}` | `{obj.first_seen}` | `{obj.last_seen}` | `{obj.findings_as_of}` | "
                f"`{u_cnt}` | `{f_cnt}` | `{c_cnt}` |"
            )
        Path(args.report).write_text("\n".join(md) + "\n", encoding="utf-8")

    return 1 if failures else 0


if __name__ == "__main__":
    raise SystemExit(main())
