"! Idempotent loader for usage facts (Member 1 — M1-D05-T01 / M1-D07-T01).
"!
"! DEMO / SYNTHETIC data only.
"! - Requires parent CustomObject (source_system + object_type + object_name) to exist;
"!   otherwise rejects the row with UNKNOWN_OBJECT (no deferred replay).
"! - Upserts by composite usage key (object_key + period_start + period_end + evidence_source).
"! - Contradictory usage rows (e.g. run_count = 0 with last_executed populated) are persisted
"!   so Member 2's rule engine can classify them as conflicting evidence -> MANUAL_REVIEW.
CLASS zccmc_cl_import_usage_loader DEFINITION
  PUBLIC
  FINAL
  CREATE PUBLIC.

  PUBLIC SECTION.
    CLASS-METHODS load_usages
      IMPORTING
        it_valid_usages  TYPE zccmc_if_source_adapter=>ty_usage_tab
      CHANGING
        cs_batch         TYPE zccmc_if_source_adapter=>ty_import_batch
        ct_batch_results TYPE zccmc_if_source_adapter=>ty_row_result_tab
        ct_batch_errors  TYPE zccmc_if_source_adapter=>ty_row_error_tab
        cs_store         TYPE zccmc_if_source_adapter=>ty_persistence_store.

ENDCLASS.



CLASS zccmc_cl_import_usage_loader IMPLEMENTATION.

  METHOD load_usages.
    LOOP AT it_valid_usages INTO DATA(ls_in).
      DATA(lv_obj_key) = |{ ls_in-source_system }\|{ ls_in-object_type }\|{ ls_in-object_name }|.
      READ TABLE cs_store-objects INTO DATA(ls_obj) WITH KEY business_key = lv_obj_key.
      IF sy-subrc <> 0.
        zccmc_cl_import_batch_mgr=>record_rejected_row(
          EXPORTING
            iv_source_record = ls_in-source_record
            iv_business_key  = ls_in-business_key
            iv_error_code    = zccmc_if_source_adapter=>c_error-unknown_object
            iv_field_name    = 'object_name'
            iv_message       = |Referenced custom object '{ lv_obj_key }' does not exist.|
          CHANGING
            cs_batch         = cs_batch
            ct_row_results   = ct_batch_results
            ct_row_errors    = ct_batch_errors ).
        CONTINUE.
      ENDIF.

      ls_in-object_uuid = ls_obj-object_uuid.

      READ TABLE cs_store-usages ASSIGNING FIELD-SYMBOL(<ls_existing>)
        WITH KEY business_key = ls_in-business_key.
      IF sy-subrc <> 0.
        cs_store-next_uuid_seq  = cs_store-next_uuid_seq + 1.
        ls_in-usage_uuid         = |USG-UUID-{ cs_store-next_uuid_seq WIDTH = 4 ALIGN = RIGHT PAD = '0' }|.
        ls_in-last_batch_uuid    = cs_batch-batch_uuid.
        ls_in-last_source_record = ls_in-source_record.
        ls_in-created_at         = cs_batch-created_at_utc.
        ls_in-changed_at         = cs_batch-created_at_utc.
        APPEND ls_in TO cs_store-usages.

        zccmc_cl_import_batch_mgr=>record_accepted_row(
          EXPORTING
            iv_source_record = ls_in-source_record
            iv_business_key  = ls_in-business_key
            iv_entity_uuid   = ls_in-usage_uuid
            iv_result_status = zccmc_if_source_adapter=>c_row_result-inserted
            iv_row_sha256    = ls_in-row_sha256
          CHANGING
            cs_batch         = cs_batch
            ct_row_results   = ct_batch_results ).
      ELSEIF <ls_existing>-row_sha256 = ls_in-row_sha256.
        zccmc_cl_import_batch_mgr=>record_accepted_row(
          EXPORTING
            iv_source_record = ls_in-source_record
            iv_business_key  = ls_in-business_key
            iv_entity_uuid   = <ls_existing>-usage_uuid
            iv_result_status = zccmc_if_source_adapter=>c_row_result-unchanged
            iv_row_sha256    = ls_in-row_sha256
          CHANGING
            cs_batch         = cs_batch
            ct_row_results   = ct_batch_results ).
      ELSE.
        <ls_existing>-last_executed      = ls_in-last_executed.
        <ls_existing>-run_count          = ls_in-run_count.
        <ls_existing>-evidence_as_of     = ls_in-evidence_as_of.
        <ls_existing>-last_batch_uuid    = cs_batch-batch_uuid.
        <ls_existing>-last_source_record = ls_in-source_record.
        <ls_existing>-row_sha256         = ls_in-row_sha256.
        <ls_existing>-changed_at         = cs_batch-created_at_utc.

        zccmc_cl_import_batch_mgr=>record_accepted_row(
          EXPORTING
            iv_source_record = ls_in-source_record
            iv_business_key  = ls_in-business_key
            iv_entity_uuid   = <ls_existing>-usage_uuid
            iv_result_status = zccmc_if_source_adapter=>c_row_result-updated
            iv_row_sha256    = ls_in-row_sha256
          CHANGING
            cs_batch         = cs_batch
            ct_row_results   = ct_batch_results ).
      ENDIF.
    ENDLOOP.
  ENDMETHOD.

ENDCLASS.
