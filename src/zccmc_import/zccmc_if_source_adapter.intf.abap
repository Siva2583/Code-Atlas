"! Source adapter & shared import contract interface for the Clean Core Migration Cockpit (Member 1).
"!
"! DEMO / SYNTHETIC data only. Defines the shared constants, row schemas, batch/provenance
"! structures, and error vocabulary frozen in docs/data-contract.md (v0.3) and docs/import-design.md.
"!
"! STATUS: written with release-safe plain ABAP types (string, d, i, utclong, abap_boolean)
"! so all importer classes and ABAP Unit suites compile and run independently of live table
"! activation in the shared trial tenant (see docs/feasibility-note.md F-02).
INTERFACE zccmc_if_source_adapter
  PUBLIC.

  "! Approved MVP import file kinds (docs/data-contract.md)
  CONSTANTS:
    BEGIN OF c_file_kind,
      objects      TYPE string VALUE 'objects',
      usage        TYPE string VALUE 'usage',
      findings     TYPE string VALUE 'findings',
      dependencies TYPE string VALUE 'dependencies',
    END OF c_file_kind.

  "! ImportBatch lifecycle statuses (docs/data-contract.md & docs/architecture.md)
  CONSTANTS:
    BEGIN OF c_batch_status,
      received  TYPE string VALUE 'RECEIVED',
      validated TYPE string VALUE 'VALIDATED',
      committed TYPE string VALUE 'COMMITTED',
      failed    TYPE string VALUE 'FAILED',
    END OF c_batch_status.

  "! Per-row processing results (docs/data-contract.md)
  CONSTANTS:
    BEGIN OF c_row_result,
      inserted  TYPE string VALUE 'INSERTED',
      updated   TYPE string VALUE 'UPDATED',
      unchanged TYPE string VALUE 'UNCHANGED',
      rejected  TYPE string VALUE 'REJECTED',
    END OF c_row_result.

  "! Stable validation and persistence error codes (docs/data-contract.md)
  CONSTANTS:
    BEGIN OF c_error,
      none                   TYPE string VALUE '',
      header_mismatch        TYPE string VALUE 'HEADER_MISMATCH',
      malformed_csv          TYPE string VALUE 'MALFORMED_CSV',
      column_count_mismatch  TYPE string VALUE 'COLUMN_COUNT_MISMATCH',
      missing_required_field TYPE string VALUE 'MISSING_REQUIRED_FIELD',
      invalid_enum           TYPE string VALUE 'INVALID_ENUM',
      invalid_date           TYPE string VALUE 'INVALID_DATE',
      invalid_integer        TYPE string VALUE 'INVALID_INTEGER',
      negative_run_count     TYPE string VALUE 'NEGATIVE_RUN_COUNT',
      duplicate_key          TYPE string VALUE 'DUPLICATE_KEY',
      unknown_source_system  TYPE string VALUE 'UNKNOWN_SOURCE_SYSTEM',
      unknown_object         TYPE string VALUE 'UNKNOWN_OBJECT',
      empty_file             TYPE string VALUE 'EMPTY_FILE',
      persistence_failure    TYPE string VALUE 'PERSISTENCE_FAILURE',
    END OF c_error.

  "! Approved MVP enumerations
  CONSTANTS:
    BEGIN OF c_criticality,
      high    TYPE string VALUE 'HIGH',
      medium  TYPE string VALUE 'MEDIUM',
      low     TYPE string VALUE 'LOW',
      unknown TYPE string VALUE 'UNKNOWN',
    END OF c_criticality.

  CONSTANTS:
    BEGIN OF c_severity,
      high   TYPE string VALUE 'HIGH',
      medium TYPE string VALUE 'MEDIUM',
      low    TYPE string VALUE 'LOW',
      info   TYPE string VALUE 'INFO',
    END OF c_severity.

  CONSTANTS:
    BEGIN OF c_evidence_source,
      demo       TYPE string VALUE 'DEMO',
      csv_export TYPE string VALUE 'CSV_EXPORT',
    END OF c_evidence_source.

  TYPES ty_string_tab TYPE STANDARD TABLE OF string WITH EMPTY KEY.

  "! Raw parsed CSV record (source_record is 1-based including header = 1, first data row = 2)
  TYPES:
    BEGIN OF ty_csv_record,
      source_record TYPE i,
      fields        TYPE ty_string_tab,
      raw_text      TYPE string,
    END OF ty_csv_record,
    ty_csv_record_tab TYPE STANDARD TABLE OF ty_csv_record WITH EMPTY KEY.

  "! Output of zccmc_cl_csv_adapter=>parse_source
  TYPES:
    BEGIN OF ty_parse_result,
      ok            TYPE abap_boolean,
      file_kind     TYPE string,
      file_sha256   TYPE string,
      header        TYPE ty_string_tab,
      records       TYPE ty_csv_record_tab,
      error_code    TYPE string,
      error_record  TYPE i,
      error_message TYPE string,
    END OF ty_parse_result.

  "! Normalized & persisted row structures
  TYPES:
    BEGIN OF ty_source_system,
      source_system_id TYPE string,
      description      TYPE string,
      is_active        TYPE abap_boolean,
      created_at       TYPE utclong,
      changed_at       TYPE utclong,
    END OF ty_source_system,
    ty_source_system_tab TYPE STANDARD TABLE OF ty_source_system WITH EMPTY KEY.

  TYPES:
    BEGIN OF ty_object_row,
      object_uuid        TYPE string,
      source_record      TYPE i,
      business_key       TYPE string,
      source_system      TYPE string,
      object_type        TYPE string,
      object_name        TYPE string,
      package_name       TYPE string,
      description        TYPE string,
      criticality        TYPE string,
      business_owner     TYPE string,
      first_seen         TYPE d,
      last_seen          TYPE d,
      findings_as_of     TYPE d,
      last_batch_uuid    TYPE string,
      last_source_record TYPE i,
      row_sha256         TYPE string,
      created_at         TYPE utclong,
      changed_at         TYPE utclong,
    END OF ty_object_row,
    ty_object_tab TYPE STANDARD TABLE OF ty_object_row WITH EMPTY KEY.

  TYPES:
    BEGIN OF ty_usage_row,
      usage_uuid         TYPE string,
      object_uuid        TYPE string,
      source_record      TYPE i,
      business_key       TYPE string,
      source_system      TYPE string,
      object_type        TYPE string,
      object_name        TYPE string,
      period_start       TYPE d,
      period_end         TYPE d,
      last_executed      TYPE d,
      run_count          TYPE i,
      evidence_source    TYPE string,
      evidence_as_of     TYPE d,
      last_batch_uuid    TYPE string,
      last_source_record TYPE i,
      row_sha256         TYPE string,
      created_at         TYPE utclong,
      changed_at         TYPE utclong,
    END OF ty_usage_row,
    ty_usage_tab TYPE STANDARD TABLE OF ty_usage_row WITH EMPTY KEY.

  TYPES:
    BEGIN OF ty_finding_row,
      finding_uuid       TYPE string,
      object_uuid        TYPE string,
      source_record      TYPE i,
      business_key       TYPE string,
      source_system      TYPE string,
      object_type        TYPE string,
      object_name        TYPE string,
      finding_id         TYPE string,
      check_id           TYPE string,
      category           TYPE string,
      severity           TYPE string,
      message            TYPE string,
      source_reference   TYPE string,
      last_batch_uuid    TYPE string,
      last_source_record TYPE i,
      row_sha256         TYPE string,
      created_at         TYPE utclong,
      changed_at         TYPE utclong,
    END OF ty_finding_row,
    ty_finding_tab TYPE STANDARD TABLE OF ty_finding_row WITH EMPTY KEY.

  TYPES:
    BEGIN OF ty_dependency_row,
      dependency_uuid    TYPE string,
      from_object_uuid   TYPE string,
      to_object_uuid     TYPE string,
      source_record      TYPE i,
      business_key       TYPE string,
      source_system      TYPE string,
      from_type          TYPE string,
      from_name          TYPE string,
      to_type            TYPE string,
      to_name            TYPE string,
      dependency_type    TYPE string,
      evidence_source    TYPE string,
      last_batch_uuid    TYPE string,
      last_source_record TYPE i,
      row_sha256         TYPE string,
      created_at         TYPE utclong,
      changed_at         TYPE utclong,
    END OF ty_dependency_row,
    ty_dependency_tab TYPE STANDARD TABLE OF ty_dependency_row WITH EMPTY KEY.

  "! Row-level error & append-only provenance structures
  TYPES:
    BEGIN OF ty_row_error,
      batch_uuid     TYPE string,
      source_record  TYPE i,
      file_kind      TYPE string,
      business_key   TYPE string,
      error_code     TYPE string,
      field_name     TYPE string,
      message        TYPE string,
      created_at_utc TYPE utclong,
    END OF ty_row_error,
    ty_row_error_tab TYPE STANDARD TABLE OF ty_row_error WITH EMPTY KEY.

  TYPES:
    BEGIN OF ty_row_result,
      batch_uuid     TYPE string,
      source_record  TYPE i,
      file_kind      TYPE string,
      business_key   TYPE string,
      entity_uuid    TYPE string,
      result_status  TYPE string,
      row_sha256     TYPE string,
      error_code     TYPE string,
      created_at_utc TYPE utclong,
    END OF ty_row_result,
    ty_row_result_tab TYPE STANDARD TABLE OF ty_row_result WITH EMPTY KEY.

  TYPES:
    BEGIN OF ty_import_batch,
      batch_uuid         TYPE string,
      file_kind          TYPE string,
      status             TYPE string,
      file_sha256        TYPE string,
      actor              TYPE string,
      created_at_utc     TYPE utclong,
      parsed_count       TYPE i,
      accepted_count     TYPE i,
      inserted_count     TYPE i,
      updated_count      TYPE i,
      unchanged_count    TYPE i,
      rejected_count     TYPE i,
      file_error_code    TYPE string,
      file_error_message TYPE string,
    END OF ty_import_batch,
    ty_import_batch_tab TYPE STANDARD TABLE OF ty_import_batch WITH EMPTY KEY.

  "! Validation result returned by zccmc_cl_import_validator
  TYPES:
    BEGIN OF ty_validation_result,
      ok                TYPE abap_boolean,
      file_kind         TYPE string,
      file_sha256       TYPE string,
      file_error_code   TYPE string,
      file_error_msg    TYPE string,
      parsed_count      TYPE i,
      valid_objects     TYPE ty_object_tab,
      valid_usages      TYPE ty_usage_tab,
      valid_findings    TYPE ty_finding_tab,
      valid_deps        TYPE ty_dependency_tab,
      row_errors        TYPE ty_row_error_tab,
    END OF ty_validation_result.

  "! In-memory / repository store abstraction backing tests and staging
  TYPES:
    BEGIN OF ty_persistence_store,
      source_systems               TYPE ty_source_system_tab,
      objects                      TYPE ty_object_tab,
      usages                       TYPE ty_usage_tab,
      findings                     TYPE ty_finding_tab,
      dependencies                 TYPE ty_dependency_tab,
      batches                      TYPE ty_import_batch_tab,
      row_results                  TYPE ty_row_result_tab,
      row_errors                   TYPE ty_row_error_tab,
      next_uuid_seq                TYPE i,
      simulate_persistence_failure TYPE abap_boolean,
    END OF ty_persistence_store.

  METHODS parse_source
    IMPORTING
      iv_file_kind     TYPE string
      iv_csv_content   TYPE string
    RETURNING
      VALUE(rs_result) TYPE ty_parse_result.

ENDINTERFACE.
