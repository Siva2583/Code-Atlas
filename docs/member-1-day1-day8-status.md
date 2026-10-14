# Member 1 — Day 1 to Day 8 Status

Branch: feature/m1-data-import  
Inspection head: 3006fb08a41129be82a8a3f4c6bfa067ed75729b  
Scope: Member 1 tasks M1-D01-T01 through M1-D08-T01 from CLEAN-CORE-11-DAY-PLAN.pdf.

The repository work below is a reviewable proposal. This status distinguishes completed repository preparation from SAP work requiring the user's ADT tenant. No task is marked fully passed when activation or the supported importer was not observed.

| Day / task | Repository work | SAP/runtime result |
|---|---|---|
| Day 1 — baseline | Inspected original templates, sample counts, object/view/import/test file sizes and README gaps; recorded them in docs/m1-baseline-checklist.md. | Activation, insert/read, release, transport and import route remain pending tenant evidence. |
| Day 2 — contract | Prepared candidate v0.2 with exact four headers, keys, normalization, result/error codes, order, corrections, counts and provenance; filled the edge fixture oracle. | Shared freeze is pending M2–M4 review. The new findings_as_of field must not be treated as approved until then. |
| Day 3 — persistence | Updated the conceptual ERD to the candidate fields and provenance design. | Table/CDS source files were empty; activation, physical types and transport IDs are not available from GitHub. |
| Day 4 — parsing | Added malformed-date, duplicate, empty, unknown-object and quoted-field fixtures plus expected results. | ABAP CSV adapter, validator and ABAP Unit sources remain unimplemented and unrun pending contract sign-off and tenant API/release details. |
| Day 5 — loaders | Documented repeat-import and corrected-batch outcomes; added corrected fixture. | Object/usage/finding/dependency loaders and idempotency tests remain unimplemented and unrun. |
| Day 6 — provenance | Specified per-row accepted/rejected provenance, batch digest/counts and append-only correction behavior. | Required persistence objects are empty/unactivated; prior-batch provenance is not yet demonstrated. |
| Day 7 — references | Documented object-first order, UNKNOWN_OBJECT errors, no deferred replay and file-level rollback for fatal persistence failures. | Integration/order/failure tests need the activated importer and tenant. |
| Day 8 — edges and scale | Materialized all named edge fixtures and 1k/10k synthetic object inputs; added an offline fixture checker. | The checker is only a local CSV structure/read baseline. SAP loader timings, importer idempotency and ABAP Unit results are explicitly not measured. |

## Current gate

The repository evidence and candidate fixtures are ready for review. To finish the SAP-dependent acceptance criteria, the remaining inputs are the ADT release/package/capability results and sign-off on candidate v0.2. The separate project ZIP referenced in the request was not present in this branch tree; its path or attachment is still needed if it contains requirements not represented by this repository.