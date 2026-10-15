"! Import batch, row-result ledger, and row-error manager (Member 1 — M1-D05-T01 / M1-D06-T01).
"!
"! DEMO / SYNTHETIC data only.
"! - Generates a distinct BatchUUID for every import attempt (including repeat uploads).
"! - Records append-only row outcomes (INSERTED, UPDATED, UNCHANGED, REJECTED) in row_results
"!   and detailed row errors in row_errors without deleting prior batch history.
"! - Reconciles batch counts: accepted_count = inserted + updated + unchanged;
"!   parsed_count = accepted_count + rejected_count.
"! - Marks batch COMMITTED when accepted_count >= 1 (including all-UNCHANGED repeat batches),
"!   or FAILED when EMPTY_FILE, HEADER_MISMATCH, MALFORMED_CSV, PERSISTENCE_FAILURE, or accepted_count = 0.
CLASS zccmc_cl_import_batch_mgr DEFINITION
  PUBLIC
  FINAL
  CREATE PUBLIC.

  PUBLIC SECTION.
    CLASS-METHODS create_batch
      IMPORTING
        iv_file_kind    TYPE string
        iv_file_sha256  TYPE string
        iv_actor        TYPE string
        iv_timestamp    TYPE utclong
      CHANGING
        cs_store        TYPE zccmc_if_source_adapter=>ty_persistence_store
      RETURNING
        VALUE(rs_batch) TYPE zccmc_if_source_adapter=>ty_import_batch.

    CLASS-METHODS record_accepted_row
      IMPORTING
        iv_source_record TYPE i
        iv_business_key  TYPE string
        iv_entity_uuid   TYPE string
        iv_result_status TYPE string
        iv_row_sha256    TYPE string
      CHANGING
        cs_batch         TYPE zccmc_if_source_adapter=>ty_import_batch
        ct_row_results   TYPE zccmc_if_source_adapter=>ty_row_result_tab.

    CLASS-METHODS record_rejected_row
      IMPORTING
        iv_source_record TYPE i
        iv_business_key  TYPE string
        iv_error_code    TYPE string
        iv_field_name    TYPE string
        iv_message       TYPE string
      CHANGING
        cs_batch         TYPE zccmc_if_source_adapter=>ty_import_batch
        ct_row_results   TYPE zccmc_if_source_adapter=>ty_row_result_tab
        ct_row_errors    TYPE zccmc_if_source_adapter=>ty_row_error_tab.

    CLASS-METHODS finalize_batch
      IMPORTING
        it_batch_results TYPE zccmc_if_source_adapter=>ty_row_result_tab
        it_batch_errors  TYPE zccmc_if_source_adapter=>ty_row_error_tab
      CHANGING
        cs_batch         TYPE zccmc_if_source_adapter=>ty_import_batch
        cs_store         TYPE zccmc_if_source_adapter=>ty_persistence_store.

    CLASS-METHODS fail_batch_file_level
      IMPORTING
        iv_error_code    TYPE string
        iv_error_message TYPE string
      CHANGING
        cs_batch         TYPE zccmc_if_source_adapter=>ty_import_batch
        cs_store         TYPE zccmc_if_source_adapter=>ty_persistence_store.

ENDCLASS.



CLASS zccmc_cl_import_batch_mgr IMPLEMENTATION.

  METHOD create_batch.
    cs_store-next_uuid_seq = cs_store-next_uuid_seq + 1.
    rs_batch-batch_uuid     = |BATCH-UUID-{ cs_store-next_uuid_seq WIDTH = 4 ALIGN = RIGHT PAD = '0' }|.
    rs_batch-file_kind      = to_lower( condense( iv_file_kind ) ).
    rs_batch-status         = zccmc_if_source_adapter=>c_batch_status-received.
    rs_batch-file_sha256    = iv_file_sha256.
    rs_batch-actor          = COND string( WHEN iv_actor <> '' THEN iv_actor ELSE 'DEMO_IMPORTER' ).
    rs_batch-created_at_utc = iv_timestamp.
  ENDMETHOD.


  METHOD record_accepted_row.
    CASE iv_result_status.
      WHEN zccmc_if_source_adapter=>c_row_result-inserted.
        cs_batch-inserted_count = cs_batch-inserted_count + 1.
      WHEN zccmc_if_source_adapter=>c_row_result-updated.
        cs_batch-updated_count = cs_batch-updated_count + 1.
      WHEN zccmc_if_source_adapter=>c_row_result-unchanged.
        cs_batch-unchanged_count = cs_batch-unchanged_count + 1.
    ENDCASE.
    cs_batch-accepted_count = cs_batch-inserted_count + cs_batch-updated_count + cs_batch-unchanged_count.
    cs_batch-parsed_count   = cs_batch-accepted_count + cs_batch-rejected_count.

    APPEND VALUE #(
      batch_uuid     = cs_batch-batch_uuid
      source_record  = iv_source_record
      file_kind      = cs_batch-file_kind
      business_key   = iv_business_key
      entity_uuid    = iv_entity_uuid
      result_status  = iv_result_status
      row_sha256     = iv_row_sha256
      error_code     = ''
      created_at_utc = cs_batch-created_at_utc
    ) TO ct_row_results.
  ENDMETHOD.


  METHOD record_rejected_row.
    cs_batch-rejected_count = cs_batch-rejected_count + 1.
    cs_batch-accepted_count = cs_batch-inserted_count + cs_batch-updated_count + cs_batch-unchanged_count.
    cs_batch-parsed_count   = cs_batch-accepted_count + cs_batch-rejected_count.

    APPEND VALUE #(
      batch_uuid     = cs_batch-batch_uuid
      source_record  = iv_source_record
      file_kind      = cs_batch-file_kind
      business_key   = iv_business_key
      entity_uuid    = ''
      result_status  = zccmc_if_source_adapter=>c_row_result-rejected
      row_sha256     = ''
      error_code     = iv_error_code
      created_at_utc = cs_batch-created_at_utc
    ) TO ct_row_results.

    APPEND VALUE #(
      batch_uuid     = cs_batch-batch_uuid
      source_record  = iv_source_record
      file_kind      = cs_batch-file_kind
      business_key   = iv_business_key
      error_code     = iv_error_code
      field_name     = iv_field_name
      message        = iv_message
      created_at_utc = cs_batch-created_at_utc
    ) TO ct_row_errors.
  ENDMETHOD.


  METHOD finalize_batch.
    cs_batch-accepted_count = cs_batch-inserted_count + cs_batch-updated_count + cs_batch-unchanged_count.
    cs_batch-parsed_count   = cs_batch-accepted_count + cs_batch-rejected_count.

    IF cs_batch-accepted_count >= 1 AND cs_batch-file_error_code = ''.
      cs_batch-status = zccmc_if_source_adapter=>c_batch_status-committed.
    ELSE.
      cs_batch-status = zccmc_if_source_adapter=>c_batch_status-failed.
    ENDIF.

    " Append-only persistence of batch header, row results, and row errors
    APPEND cs_batch TO cs_store-batches.
    APPEND LINES OF it_batch_results TO cs_store-row_results.
    APPEND LINES OF it_batch_errors  TO cs_store-row_errors.
  ENDMETHOD.


  METHOD fail_batch_file_level.
    cs_batch-status             = zccmc_if_source_adapter=>c_batch_status-failed.
    cs_batch-file_error_code    = iv_error_code.
    cs_batch-file_error_message = iv_error_message.
    APPEND cs_batch TO cs_store-batches.
  ENDMETHOD.

ENDCLASS.
