#!/usr/bin/env python3
"""Validate repository CSV fixtures offline; this does not test an SAP importer."""
from __future__ import annotations

import argparse
import csv
import datetime as dt
import tempfile
import time
from pathlib import Path

HEADERS = {
    "objects": ["source_system", "object_type", "object_name", "package", "description",
                "criticality", "business_owner", "first_seen", "last_seen", "findings_as_of"],
    "usage": ["source_system", "object_type", "object_name", "period_start", "period_end",
              "last_executed", "run_count", "evidence_source", "evidence_as_of"],
    "findings": ["source_system", "object_type", "object_name", "finding_id", "check_id",
                 "category", "severity", "message", "source_reference"],
    "dependencies": ["source_system", "from_type", "from_name", "to_type", "to_name",
                     "dependency_type", "evidence_source"],
}


def parse_csv(path: Path, expected_header: list[str]) -> list[list[str]]:
    with path.open("r", encoding="utf-8-sig", newline="") as stream:
        records = list(csv.reader(stream, strict=True))
    if not records:
        raise ValueError(f"{path}: missing header")
    if records[0] != expected_header:
        raise ValueError(f"{path}: header mismatch: {records[0]!r}")
    rows = records[1:]
    for number, row in enumerate(rows, start=2):
        if not row or (len(row) == 1 and row[0] == ""):
            continue
        if len(row) != len(expected_header):
            raise ValueError(f"{path}: record {number} has {len(row)} columns")
    return [row for row in rows if row and not (len(row) == 1 and row[0] == "")]


def key(source: str, object_type: str, name: str) -> tuple[str, str, str]:
    return tuple(value.strip().upper() for value in (source, object_type, name))


def valid_date(value: str) -> bool:
    if not value:
        return True
    try:
        return dt.date.fromisoformat(value).isoformat() == value
    except ValueError:
        return False


def check(root: Path) -> list[str]:
    data = root / "data"
    template_dir = data / "templates"
    sample_dir = data / "sample-synthetic"

    for kind, header in HEADERS.items():
        parse_csv(template_dir / f"{kind}.csv", header)

    objects = parse_csv(sample_dir / "objects.csv", HEADERS["objects"])
    object_rows = {key(row[0], row[1], row[2]): row for row in objects}
    if len(object_rows) != len(objects):
        raise ValueError("base objects.csv contains duplicate business keys")
    for row in objects:
        if row[5] not in {"HIGH", "MEDIUM", "LOW", "UNKNOWN"}:
            raise ValueError(f"invalid criticality: {row[5]}")
        for field in (row[7], row[8], row[9]):
            if not valid_date(field):
                raise ValueError(f"invalid object date: {field}")

    for kind in ("usage", "findings", "dependencies"):
        rows = parse_csv(sample_dir / f"{kind}.csv", HEADERS[kind])
        for row in rows:
            if kind == "usage":
                if key(*row[:3]) not in object_rows:
                    raise ValueError("base usage row refers to an unknown object")
                if not row[6].isdigit():
                    raise ValueError(f"invalid run_count: {row[6]}")
                for field in (row[3], row[4], row[5], row[8]):
                    if not valid_date(field):
                        raise ValueError(f"invalid usage date: {field}")
            elif kind == "findings":
                if key(*row[:3]) not in object_rows:
                    raise ValueError("base finding row refers to an unknown object")
                if row[6] not in {"HIGH", "MEDIUM", "LOW", "INFO"}:
                    raise ValueError(f"invalid severity: {row[6]}")
            else:
                if key(row[0], row[1], row[2]) not in object_rows:
                    raise ValueError("dependency source is unknown")
                if key(row[0], row[3], row[4]) not in object_rows:
                    raise ValueError("dependency target is unknown")

    edge = sample_dir / "edge-cases"
    duplicate_rows = parse_csv(edge / "objects_duplicate_keys.csv", HEADERS["objects"])
    duplicate_keys = [key(row[0], row[1], row[2]) for row in duplicate_rows]
    if len(duplicate_rows) != 2 or len(set(duplicate_keys)) != 1:
        raise ValueError("duplicate-key fixture must contain exactly two colliding rows")

    corrected = parse_csv(edge / "objects_corrected_batch.csv", HEADERS["objects"])
    if len(corrected) != 1 or key(*corrected[0][:3]) not in object_rows:
        raise ValueError("corrected-batch fixture must update one base object")

    unknown = parse_csv(edge / "findings_unknown_object.csv", HEADERS["findings"])
    if len(unknown) != 1 or key(*unknown[0][:3]) in object_rows:
        raise ValueError("unknown-object fixture must contain one missing object key")

    malformed = parse_csv(edge / "usage_malformed_date.csv", HEADERS["usage"])
    invalid = [(i, value) for i, row in enumerate(malformed, start=2)
               for value in (row[3], row[4], row[5], row[8]) if not valid_date(value)]
    if len(malformed) != 1 or len(invalid) != 1:
        raise ValueError("malformed-date fixture must contain one row and one invalid date")

    empty = parse_csv(edge / "objects_empty.csv", HEADERS["objects"])
    if empty:
        raise ValueError("objects_empty.csv must contain a header and no data records")

    quoted = parse_csv(edge / "findings_quoted_fields.csv", HEADERS["findings"])
    if len(quoted) != 1 or 'quoted, comma and "quote"' not in quoted[0][7]:
        raise ValueError("quoted-field fixture did not preserve comma and escaped quote")

    reports = []
    perf_dir = sample_dir / "perf"
    for count in (1000, 10000):
        path = perf_dir / f"objects_{count}.csv"
        start = time.perf_counter()
        rows = parse_csv(path, HEADERS["objects"])
        elapsed = time.perf_counter() - start
        keys = [key(row[0], row[1], row[2]) for row in rows]
        if len(rows) != count or len(set(keys)) != count:
            raise ValueError(f"{path}: expected {count} rows with unique keys")
        reports.append(f"{count} rows: {path.stat().st_size} bytes, offline CSV parse {elapsed:.4f}s")
    return reports


def write_rows(path: Path, header: list[str], rows: list[list[str]]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", encoding="utf-8", newline="") as stream:
        writer = csv.writer(stream, lineterminator="\n")
        writer.writerow(header)
        writer.writerows(rows)


def self_test() -> None:
    with tempfile.TemporaryDirectory(dir=Path(__file__).resolve().parent, prefix="m1-import-fixtures-") as directory:
        root = Path(directory)
        data = root / "data"
        sample = data / "sample-synthetic"
        edge = sample / "edge-cases"
        for kind, header in HEADERS.items():
            write_rows(data / "templates" / f"{kind}.csv", header, [])
        base_objects = [
            ["DEMO_SYS", "PROG", "ZDEMO_A", "ZPKG", "synthetic A", "LOW", "DEMO", "2025-01-01", "2026-01-01", "2026-10-13"],
            ["DEMO_SYS", "CLAS", "ZDEMO_B", "ZPKG", "synthetic B", "MEDIUM", "DEMO", "2025-01-01", "2026-01-01", "2026-10-13"],
        ]
        write_rows(sample / "objects.csv", HEADERS["objects"], base_objects)
        write_rows(sample / "usage.csv", HEADERS["usage"], [
            ["DEMO_SYS", "PROG", "ZDEMO_A", "2025-01-01", "2026-01-01", "2025-12-31", "1", "DEMO", "2026-10-13"]
        ])
        write_rows(sample / "findings.csv", HEADERS["findings"], [
            ["DEMO_SYS", "PROG", "ZDEMO_A", "F1", "C1", "API", "LOW", 'quoted, comma and "quote"', "REF1"]
        ])
        write_rows(sample / "dependencies.csv", HEADERS["dependencies"], [
            ["DEMO_SYS", "PROG", "ZDEMO_A", "CLAS", "ZDEMO_B", "CALL", "DEMO"]
        ])
        write_rows(edge / "objects_duplicate_keys.csv", HEADERS["objects"], [base_objects[0], base_objects[0]])
        write_rows(edge / "objects_corrected_batch.csv", HEADERS["objects"], [
            ["DEMO_SYS", "PROG", "ZDEMO_A", "ZPKG", "corrected", "LOW", "DEMO", "2025-01-01", "2026-01-01", "2026-10-13"]
        ])
        write_rows(edge / "findings_unknown_object.csv", HEADERS["findings"], [
            ["DEMO_SYS", "PROG", "ZUNKNOWN", "F2", "C2", "API", "LOW", "unknown", "REF2"]
        ])
        write_rows(edge / "usage_malformed_date.csv", HEADERS["usage"], [
            ["DEMO_SYS", "PROG", "ZDEMO_A", "2026-02-30", "2026-10-13", "", "0", "DEMO", "2026-10-13"]
        ])
        write_rows(edge / "objects_empty.csv", HEADERS["objects"], [])
        write_rows(edge / "findings_quoted_fields.csv", HEADERS["findings"], [
            ["DEMO_SYS", "PROG", "ZDEMO_A", "F3", "C3", "API", "LOW", 'quoted, comma and "quote"', "REF3"]
        ])
        for count in (1000, 10000):
            rows = [[
                "DEMO_SYS", "PROG", f"ZPERF_OBJECT_{i:05d}", "ZPERF", "synthetic perf",
                "LOW", "DEMO_PERF", "2026-01-01", "2026-10-01", "2026-10-13"
            ] for i in range(1, count + 1)]
            write_rows(sample / "perf" / f"objects_{count}.csv", HEADERS["objects"], rows)
        reports = check(root)
        print("Offline fixture self-test: PASS")
        for report in reports:
            print(report)
        print("These timings exercise Python csv.reader only; they are not ABAP or SAP importer measurements.")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--self-test", action="store_true",
                        help="exercise the checker with temporary synthetic fixtures")
    parser.add_argument("--root", type=Path,
                        default=Path(__file__).resolve().parents[1],
                        help="repository root (defaults to the parent of tools/)")
    args = parser.parse_args()
    if args.self_test:
        self_test()
        return
    for report in check(args.root):
        print(report)
    print("Offline fixture validation: PASS")
    print("No ABAP parser, tenant persistence, ABAP Unit or SAP performance test was executed.")


if __name__ == "__main__":
    main()
