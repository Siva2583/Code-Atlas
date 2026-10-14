# Import Design — Member 1 candidate v0.2

**State:** design candidate based on the current Git branch and docs/data-contract.md. The four-file contract is awaiting M2–M4 sign-off. No file-upload, OData, staged-row CRUD or ABAP persistence capability has been proven in the assigned SAP tenant.

## Import boundary

The MVP has four inputs only: objects, usage, findings and dependencies. The importer accepts a complete byte stream for one file, identifies the file kind from the caller, computes its SHA-256, parses a header and data records, validates into typed rows, records row outcomes, then persists valid rows. It does not expose an upload endpoint until Day 1 proves a supported route. The CSV parser and validator should be pure ABAP services with no RAP/UI dependency.

## Processing order and transaction policy

For a clean synthetic load, import objects first, followed by usage, findings and dependencies. The source system must already exist in tenant configuration. Dependent rows require the referenced object to have been committed; an unknown or not-yet-loaded object gets UNKNOWN_OBJECT. There is no deferred queue. A reverse-order run therefore records those row errors; importing objects later does not silently replay them.

Each file has a distinct BatchUUID. Header/schema and row validations run before persistence. Valid rows from one file may be committed while invalid business rows receive persisted errors. A fatal database error rolls back all business writes from that file. The batch is COMMITTED when at least one row is INSERTED, UPDATED or UNCHANGED; it is FAILED when no data row succeeds, when the file is header-only, or when persistence fails. Counts must reconcile as described in the data contract.

All colliding duplicate keys inside one file are rejected, including the first occurrence, so input order cannot choose a winner. Across files, business-key upsert produces INSERTED, UPDATED or UNCHANGED. Corrected batches do not delete missing rows or earlier provenance.

## Parsing and validation

- Decode UTF-8, optionally removing one leading BOM. Accept LF or CRLF record endings.
- Parse RFC 4180 quoted fields: commas and newlines inside quoted values are data; a quote inside a quoted value is escaped as two quotes.
- Require the exact ordered header and exact number of columns. Ignore truly blank records; reject malformed quoted records and wrong-width records.
- Trim key fields before comparison. Normalize object identity keys and enum tokens to uppercase. Preserve free-text fields.
- Parse dates strictly as YYYY-MM-DD calendar dates and integers as non-negative base-10 values. Blank optional dates remain unknown. Do not turn unknown criticality into LOW.
- Return row-level errors with stable codes from docs/data-contract.md. A valid but contradictory usage fact is retained so rules can report the specified conflict; it is not silently repaired by import.
- Enforce file/row limits only after the tenant input and staging limits are measured. No SAP limit is asserted by this design.

## Provenance and corrections

Create a batch record for every attempt with file kind, digest, actor, UTC timestamp, status and reconciled counts. Record the source record number and business key for each result. Persist rejected-row details and retain accepted-row result provenance in an append-only ledger. Keep prior batch and row records after corrected re-import. Do not store or log live customer payloads in this synthetic demo workflow.

An append-only import row/result ledger is still a proposed persistence object. If Day 1 does not prove that the required table/API can be activated, historical accepted-row provenance is not delivered; document the blocker instead of substituting a misleading “latest batch only” field.

## Edge fixtures and expected behavior

| Fixture | Expected import result |
|---|---|
| objects_empty.csv | Header parses; zero data records; batch fails with file-level EMPTY_FILE; no object is created or deleted. |
| objects_duplicate_keys.csv | Both occurrences of the repeated composite key are REJECTED with DUPLICATE_KEY; neither is applied. |
| objects_corrected_batch.csv | After the baseline objects import, the matching key updates mutable values and returns UPDATED; earlier batch/row provenance remains. |
| usage_malformed_date.csv | The bad record is REJECTED with INVALID_DATE and names the bad date field; no part of that row is written. |
| findings_unknown_object.csv | The record is REJECTED with UNKNOWN_OBJECT; no finding is created. |
| findings_quoted_fields.csv | One valid finding parses with its comma and escaped quotes preserved exactly. |
| repeated baseline file | Same normalized payload returns UNCHANGED; the attempt still has a new BatchUUID and row provenance. |

## Supported path and open gates

The repository currently has empty ABAP table, CDS, importer and test placeholders. Until ADT confirms release, package, released UUID APIs, activation, ABAP Unit and an import path, all names/physical field types remain proposals. Direct browser upload is not assumed. If staged-row CRUD is the only proven route, M1 and M4 must approve its exact capacity and lifecycle before adding the staging entity.