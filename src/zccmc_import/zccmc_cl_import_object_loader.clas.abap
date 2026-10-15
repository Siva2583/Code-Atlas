"! Idempotent loader for custom objects (Member 1 — M1-D05-T01).
"!
"! DEMO / SYNTHETIC data only.
"! - Verifies that source_system exists in provisioned source_systems (else UNKNOWN_SOURCE_SYSTEM).
"! - Upserts by normalized business key (source_system + object_type + object_name).
"! - Preserves ObjectUUID across repeat (UNCHANGED) and corrected (UPDATED) imports so
"!   downstream usage, findings, dependencies, and Member 3 decisions never lose their link.
"! - Never deletes omitted objects on partial or corrected batches.
CLASS zccmc_cl_import_object_loader DEFINITION
  PUBLIC
  FINAL
  CREATE PUBLIC.

  PUBLIC SECTION.
    CLASS-METHODS load_objects
      IMPORTING
        it_valid_objects TYPE zccmc_if_source_adapter=>ty_object_tab
      CHANGING
        cs_batch         TYPE zccmc_if_source_adapter=>ty_import_batch
        ct_batch_results TYPE zccmc_if_source_adapter=>ty_row_result_tab
        ct_batch_errors  TYPE zccmc_if_source_adapter=>ty_row_error_tab
        cs_store         TYPE zccmc_if_source_adapter=>ty_persistence_store.

ENDCLASS.



CLASS zccmc_cl_import_object_loader IMPLEMENTATION.

  METHOD load_objects.
    LOOP AT it_valid_objects INTO DATA(ls_in).
      " 1. Verify provisioned source system
      READ TABLE cs_store-source_systems TRANSPORTING NO FIELDS
        WITH KEY source_system_id = ls_in-source_system is_active = abap_true.
      IF sy-subrc <> 0.
        zccmc_cl_import_batch_mgr=>record_rejected_row(
          EXPORTING
            iv_source_record = ls_in-source_record
            iv_business_key  = ls_in-business_key
            iv_error_code    = zccmc_if_source_adapter=>c_error-unknown_source_system
            iv_field_name    = 'source_system'
            iv_message       = |Source system '{ ls_in-source_system }' is not provisioned in tenant.|
          CHANGING
            cs_batch         = cs_batch
            ct_row_results   = ct_batch_results
            ct_row_errors    = ct_batch_errors ).
        CONTINUE.
      ENDIF.

      " 2. Upsert by composite business key (source_system + object_type + object_name)
      READ TABLE cs_store-objects ASSIGNING FIELD-SYMBOL(<ls_existing>)
        WITH KEY business_key = ls_in-business_key.
      IF sy-subrc <> 0.
        cs_store-next_uuid_seq  = cs_store-next_uuid_seq + 1.
        ls_in-object_uuid        = |OBJ-UUID-{ cs_store-next_uuid_seq WIDTH = 4 ALIGN = RIGHT PAD = '0' }|.
        ls_in-last_batch_uuid    = cs_batch-batch_uuid.
        ls_in-last_source_record = ls_in-source_record.
        ls_in-created_at         = cs_batch-created_at_utc.
        ls_in-changed_at         = cs_batch-created_at_utc.
        APPEND ls_in TO cs_store-objects.

        zccmc_cl_import_batch_mgr=>record_accepted_row(
          EXPORTING
            iv_source_record = ls_in-source_record
            iv_business_key  = ls_in-business_key
            iv_entity_uuid   = ls_in-object_uuid
            iv_result_status = zccmc_if_source_adapter=>c_row_result-inserted
            iv_row_sha256    = ls_in-row_sha256
          CHANGING
            cs_batch         = cs_batch
            ct_row_results   = ct_batch_results ).
      ELSEIF <ls_existing>-row_sha256 = ls_in-row_sha256.
        " Identical normalized payload -> UNCHANGED, preserve ObjectUUID
        zccmc_cl_import_batch_mgr=>record_accepted_row(
          EXPORTING
            iv_source_record = ls_in-source_record
            iv_business_key  = ls_in-business_key
            iv_entity_uuid   = <ls_existing>-object_uuid
            iv_result_status = zccmc_if_source_adapter=>c_row_result-unchanged
            iv_row_sha256    = ls_in-row_sha256
          CHANGING
            cs_batch         = cs_batch
            ct_row_results   = ct_batch_results ).
      ELSE.
        " Corrected non-key attributes -> UPDATED in place, preserve ObjectUUID
        <ls_existing>-package_name       = ls_in-package_name.
        <ls_existing>-description        = ls_in-description.
        <ls_existing>-criticality        = ls_in-criticality.
        <ls_existing>-business_owner     = ls_in-business_owner.
        <ls_existing>-first_seen         = ls_in-first_seen.
        <ls_existing>-last_seen          = ls_in-last_seen.
        <ls_existing>-findings_as_of     = ls_in-findings_as_of.
        <ls_existing>-last_batch_uuid    = cs_batch-batch_uuid.
        <ls_existing>-last_source_record = ls_in-source_record.
        <ls_existing>-row_sha256         = ls_in-row_sha256.
        <ls_existing>-changed_at         = cs_batch-created_at_utc.

        zccmc_cl_import_batch_mgr=>record_accepted_row(
          EXPORTING
            iv_source_record = ls_in-source_record
            iv_business_key  = ls_in-business_key
            iv_entity_uuid   = <ls_existing>-object_uuid
            iv_result_status = zccmc_if_source_adapter=>c_row_result-updated
            iv_row_sha256    = ls_in-row_sha256
          CHANGING
            cs_batch         = cs_batch
            ct_row_results   = ct_batch_results ).
      ENDIF.
    ENDLOOP.
  ENDMETHOD.

ENDCLASS.
