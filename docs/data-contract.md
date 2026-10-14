# Data Contract - DRAFT v0.1 (Member 1)

Status: DRAFT. Members 2, 3 and 4 please review. No field, enum or key may change without announcing it to the team.
All sample data is DEMO / SYNTHETIC.

## 1. Object key
Stable key = SourceSystemID + ObjectType + ObjectName.
ObjectUUID is the technical key. The external key above is unique.

## 2. Entities
| Entity | Key | Notes |
|---|---|---|
| SourceSystem | SourceSystemID | name, environment |
| CustomObject | ObjectUUID, unique(SourceSystemID, ObjectType, ObjectName) | package, description, owner, criticality, first_seen, last_seen |
| UsageFact | UsageUUID, ObjectUUID | period_start, period_end, last_executed, run_count, evidence_source, evidence_as_of |
| Finding | FindingUUID, ObjectUUID | finding_id, check_id, category, severity, message, source_reference |
| Dependency | FromObjectUUID, ToObjectUUID, type | evidence_source |
| ImportBatch | BatchUUID | status, counts, file digest, actor, timestamp |

## 3. Enums (PROPOSED, agree before freezing)
- EvidenceSource: DEMO | CSV_EXPORT | LIVE_ADAPTER
- Criticality: HIGH | MEDIUM | LOW | UNKNOWN
- Severity: HIGH | MEDIUM | LOW | INFO
- ImportBatchStatus: RECEIVED | VALIDATED | COMMITTED | FAILED
- RowResult: INSERTED | UPDATED | UNCHANGED | REJECTED
- ObjectType: PROG | CLAS | FUGR | TABL | DDLS | OTHER (to be validated by the team)

## 4. CSV files (exact column names)
- objects.csv: source_system, object_type, object_name, package, description, criticality, business_owner, first_seen, last_seen
- usage.csv: source_system, object_type, object_name, period_start, period_end, last_executed, run_count, evidence_source, evidence_as_of
- findings.csv: source_system, object_type, object_name, finding_id, check_id, category, severity, message, source_reference
- dependencies.csv: source_system, from_type, from_name, to_type, to_name, dependency_type, evidence_source

## 5. Formats
- Dates: YYYY-MM-DD
- Encoding: UTF-8, header row required
- Keys are trimmed and object_type is normalized to upper case

## 6. Rules for neighbors
- Member 2 reads: CustomObject, UsageFact, Finding, Dependency. Missing or incomplete evidence must be visible through evidence_as_of and the period fields. Never infer "no usage" from an incomplete window.
- Member 3 links decisions to ObjectUUID and links audit events to the ImportBatch ID where relevant.
- Member 4 reads ImportBatch and row-level errors for the Import Center.

## 7. Change rule
Any change to a field name, enum or key needs a pull request that edits this file and a message to the team.