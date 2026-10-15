"! Idempotent loader for object dependencies (Member 1 — M1-D05-T01 / M1-D07-T01).
"!
"! DEMO / SYNTHETIC data only.
"! - Requires BOTH endpoint CustomObjects (from_type+from_name and to_type+to_name in source_system)
"!   to exist; otherwise rejects the row with UNKNOWN_OBJECT naming from_name or to_name.
"! - Upserts by composite dependency key (source_system + from + to + dependency_type + evidence_source).
CLASS zccmc_cl_import_dep_loader DEFINITION
  PUBLIC
  FINAL
  CREATE PUBLIC.

  PUBLIC SECTION.
    CLASS-METHODS load_dependencies
      IMPORTING
        it_valid_deps    TYPE zccmc_if_source_adapter=>ty_dependency_tab
      CHANGING
        cs_batch         TYPE zccmc_if_source_adapter=>ty_import_batch
        ct_batch_results TYPE zccmc_if_source_adapter=>ty_row_result_tab
        ct_batch_errors  TYPE zccmc_if_source_adapter=>ty_row_error_tab
        cs_store         TYPE zccmc_if_source_adapter=>ty_persistence_store.

ENDCLASS.



CLASS zccmc_cl_import_dep_loader IMPLEMENTATION.

  METHOD load_dependencies.
    LOOP AT it_valid_deps INTO DATA(ls_in).
      DATA(lv_from_key) = |{ ls_in-source_system }\|{ ls_in-from_type }\|{ ls_in-from_name }|.
      READ TABLE cs_store-objects INTO DATA(ls_from_obj) WITH KEY business_key = lv_from_key.
      IF sy-subrc <> 0.
        zccmc_cl_import_batch_mgr=>record_rejected_row(
          EXPORTING
            iv_source_record = ls_in-source_record
            iv_business_key  = ls_in-business_key
            iv_error_code    = zccmc_if_source_adapter=>c_error-unknown_object
            iv_field_name    = 'from_name'
            iv_message       = |Source endpoint object '{ lv_from_key }' does not exist.|
          CHANGING
            cs_batch         = cs_batch
            ct_row_results   = ct_batch_results
            ct_row_errors    = ct_batch_errors ).
        CONTINUE.
      ENDIF.

      DATA(lv_to_key) = |{ ls_in-source_system }\|{ ls_in-to_type }\|{ ls_in-to_name }|.
      READ TABLE cs_store-objects INTO DATA(ls_to_obj) WITH KEY business_key = lv_to_key.
      IF sy-subrc <> 0.
        zccmc_cl_import_batch_mgr=>record_rejected_row(
          EXPORTING
            iv_source_record = ls_in-source_record
            iv_business_key  = ls_in-business_key
            iv_error_code    = zccmc_if_source_adapter=>c_error-unknown_object
            iv_field_name    = 'to_name'
            iv_message       = |Target endpoint object '{ lv_to_key }' does not exist.|
          CHANGING
            cs_batch         = cs_batch
            ct_row_results   = ct_batch_results
            ct_row_errors    = ct_batch_errors ).
        CONTINUE.
      ENDIF.

      ls_in-from_object_uuid = ls_from_obj-object_uuid.
      ls_in-to_object_uuid   = ls_to_obj-object_uuid.

      READ TABLE cs_store-dependencies ASSIGNING FIELD-SYMBOL(<ls_existing>)
        WITH KEY business_key = ls_in-business_key.
      IF sy-subrc <> 0.
        cs_store-next_uuid_seq  = cs_store-next_uuid_seq + 1.
        ls_in-dependency_uuid    = |DEP-UUID-{ cs_store-next_uuid_seq WIDTH = 4 ALIGN = RIGHT PAD = '0' }|.
        ls_in-last_batch_uuid    = cs_batch-batch_uuid.
        ls_in-last_source_record = ls_in-source_record.
        ls_in-created_at         = cs_batch-created_at_utc.
        ls_in-changed_at         = cs_batch-created_at_utc.
        APPEND ls_in TO cs_store-dependencies.

        zccmc_cl_import_batch_mgr=>record_accepted_row(
          EXPORTING
            iv_source_record = ls_in-source_record
            iv_business_key  = ls_in-business_key
            iv_entity_uuid   = ls_in-dependency_uuid
            iv_result_status = zccmc_if_source_adapter=>c_row_result-inserted
            iv_row_sha256    = ls_in-row_sha256
          CHANGING
            cs_batch         = cs_batch
            ct_row_results   = ct_batch_results ).
      ELSE.
        " Dependency has no non-key mutable fields -> UNCHANGED
        zccmc_cl_import_batch_mgr=>record_accepted_row(
          EXPORTING
            iv_source_record = ls_in-source_record
            iv_business_key  = ls_in-business_key
            iv_entity_uuid   = <ls_existing>-dependency_uuid
            iv_result_status = zccmc_if_source_adapter=>c_row_result-unchanged
            iv_row_sha256    = ls_in-row_sha256
          CHANGING
            cs_batch         = cs_batch
            ct_row_results   = ct_batch_results ).
      ENDIF.
    ENDLOOP.
  ENDMETHOD.

ENDCLASS.
