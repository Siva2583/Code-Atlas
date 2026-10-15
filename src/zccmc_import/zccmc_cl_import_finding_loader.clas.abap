"! Idempotent loader for code/ATC findings (Member 1 — M1-D05-T01 / M1-D07-T01).
"!
"! DEMO / SYNTHETIC data only.
"! - Requires parent CustomObject (source_system + object_type + object_name) to exist;
"!   otherwise rejects the row with UNKNOWN_OBJECT and creates no orphan finding.
"! - Upserts by composite finding key (object_key + finding_id + check_id + source_reference).
CLASS zccmc_cl_import_finding_loader DEFINITION
  PUBLIC
  FINAL
  CREATE PUBLIC.

  PUBLIC SECTION.
    CLASS-METHODS load_findings
      IMPORTING
        it_valid_findings TYPE zccmc_if_source_adapter=>ty_finding_tab
      CHANGING
        cs_batch          TYPE zccmc_if_source_adapter=>ty_import_batch
        ct_batch_results  TYPE zccmc_if_source_adapter=>ty_row_result_tab
        ct_batch_errors   TYPE zccmc_if_source_adapter=>ty_row_error_tab
        cs_store          TYPE zccmc_if_source_adapter=>ty_persistence_store.

ENDCLASS.



CLASS zccmc_cl_import_finding_loader IMPLEMENTATION.

  METHOD load_findings.
    LOOP AT it_valid_findings INTO DATA(ls_in).
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

      READ TABLE cs_store-findings ASSIGNING FIELD-SYMBOL(<ls_existing>)
        WITH KEY business_key = ls_in-business_key.
      IF sy-subrc <> 0.
        cs_store-next_uuid_seq  = cs_store-next_uuid_seq + 1.
        ls_in-finding_uuid       = |FND-UUID-{ cs_store-next_uuid_seq WIDTH = 4 ALIGN = RIGHT PAD = '0' }|.
        ls_in-last_batch_uuid    = cs_batch-batch_uuid.
        ls_in-last_source_record = ls_in-source_record.
        ls_in-created_at         = cs_batch-created_at_utc.
        ls_in-changed_at         = cs_batch-created_at_utc.
        APPEND ls_in TO cs_store-findings.

        zccmc_cl_import_batch_mgr=>record_accepted_row(
          EXPORTING
            iv_source_record = ls_in-source_record
            iv_business_key  = ls_in-business_key
            iv_entity_uuid   = ls_in-finding_uuid
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
            iv_entity_uuid   = <ls_existing>-finding_uuid
            iv_result_status = zccmc_if_source_adapter=>c_row_result-unchanged
            iv_row_sha256    = ls_in-row_sha256
          CHANGING
            cs_batch         = cs_batch
            ct_row_results   = ct_batch_results ).
      ELSE.
        <ls_existing>-category           = ls_in-category.
        <ls_existing>-severity           = ls_in-severity.
        <ls_existing>-message            = ls_in-message.
        <ls_existing>-last_batch_uuid    = cs_batch-batch_uuid.
        <ls_existing>-last_source_record = ls_in-source_record.
        <ls_existing>-row_sha256         = ls_in-row_sha256.
        <ls_existing>-changed_at         = cs_batch-created_at_utc.

        zccmc_cl_import_batch_mgr=>record_accepted_row(
          EXPORTING
            iv_source_record = ls_in-source_record
            iv_business_key  = ls_in-business_key
            iv_entity_uuid   = <ls_existing>-finding_uuid
            iv_result_status = zccmc_if_source_adapter=>c_row_result-updated
            iv_row_sha256    = ls_in-row_sha256
          CHANGING
            cs_batch         = cs_batch
            ct_row_results   = ct_batch_results ).
      ENDIF.
    ENDLOOP.
  ENDMETHOD.

ENDCLASS.
