"! End-to-end import orchestrator, transaction manager, and M2/M3 bridge (Member 1 — M1-D05..D11).
"!
"! DEMO / SYNTHETIC data only.
"! Coordinates CSV parsing (zccmc_cl_csv_adapter), validation (zccmc_cl_import_validator),
"! batch/provenance tracking (zccmc_cl_import_batch_mgr), and the four entity loaders:
"! - Enforces the four-file reference order: objects -> usage -> findings -> dependencies.
"! - Guarantees file-level business-row rollback on PERSISTENCE_FAILURE (no half-batch left behind).
"! - Provides reproducible synthetic store reset (reset_synthetic_store) for Day-10 acceptance.
"! - Provides build_m2_evidence_for_object to bridge persisted M1 evidence directly into
"!   Member 2's zccmc_cl_rule_engine=>evaluate_object.
CLASS zccmc_cl_import_orchestrator DEFINITION
  PUBLIC
  FINAL
  CREATE PUBLIC.

  PUBLIC SECTION.
    TYPES:
      BEGIN OF ty_four_file_summary,
        objects_batch      TYPE zccmc_if_source_adapter=>ty_import_batch,
        usage_batch        TYPE zccmc_if_source_adapter=>ty_import_batch,
        findings_batch     TYPE zccmc_if_source_adapter=>ty_import_batch,
        dependencies_batch TYPE zccmc_if_source_adapter=>ty_import_batch,
      END OF ty_four_file_summary.

    CLASS-METHODS init_store
      IMPORTING
        iv_default_source_system TYPE string DEFAULT 'DEMO_SYS'
      RETURNING
        VALUE(rs_store)          TYPE zccmc_if_source_adapter=>ty_persistence_store.

    CLASS-METHODS reset_synthetic_store
      IMPORTING
        iv_default_source_system TYPE string DEFAULT 'DEMO_SYS'
      CHANGING
        cs_store                 TYPE zccmc_if_source_adapter=>ty_persistence_store.

    CLASS-METHODS provision_source_system
      IMPORTING
        iv_source_system_id TYPE string
        iv_description      TYPE string DEFAULT 'Synthetic Demo Source System'
      CHANGING
        cs_store            TYPE zccmc_if_source_adapter=>ty_persistence_store.

    CLASS-METHODS import_csv_file
      IMPORTING
        iv_file_kind    TYPE string
        iv_csv_content  TYPE string
        iv_actor        TYPE string DEFAULT 'DEMO_IMPORTER'
        iv_timestamp    TYPE utclong OPTIONAL
      CHANGING
        cs_store        TYPE zccmc_if_source_adapter=>ty_persistence_store
      RETURNING
        VALUE(rs_batch) TYPE zccmc_if_source_adapter=>ty_import_batch.

    CLASS-METHODS import_four_file_set
      IMPORTING
        iv_objects_csv      TYPE string
        iv_usage_csv        TYPE string
        iv_findings_csv     TYPE string
        iv_dependencies_csv TYPE string
        iv_actor            TYPE string DEFAULT 'DEMO_IMPORTER'
        iv_timestamp        TYPE utclong OPTIONAL
      CHANGING
        cs_store            TYPE zccmc_if_source_adapter=>ty_persistence_store
      RETURNING
        VALUE(rs_summary)   TYPE ty_four_file_summary.

    CLASS-METHODS build_m2_evidence_for_object
      IMPORTING
        is_store           TYPE zccmc_if_source_adapter=>ty_persistence_store
        iv_object_uuid     TYPE string
      RETURNING
        VALUE(rs_evidence) TYPE zccmc_cl_rule_engine=>ty_evidence.

ENDCLASS.



CLASS zccmc_cl_import_orchestrator IMPLEMENTATION.

  METHOD init_store.
    CLEAR rs_store.
    IF iv_default_source_system <> ''.
      provision_source_system(
        EXPORTING iv_source_system_id = iv_default_source_system
        CHANGING  cs_store            = rs_store ).
    ENDIF.
  ENDMETHOD.


  METHOD reset_synthetic_store.
    cs_store = init_store( iv_default_source_system = iv_default_source_system ).
  ENDMETHOD.


  METHOD provision_source_system.
    DATA(lv_sys) = to_upper( condense( iv_source_system_id ) ).
    READ TABLE cs_store-source_systems ASSIGNING FIELD-SYMBOL(<ls_sys>)
      WITH KEY source_system_id = lv_sys.
    IF sy-subrc = 0.
      <ls_sys>-is_active   = abap_true.
      <ls_sys>-description = iv_description.
    ELSE.
      APPEND VALUE #(
        source_system_id = lv_sys
        description      = iv_description
        is_active        = abap_true
      ) TO cs_store-source_systems.
    ENDIF.
  ENDMETHOD.


  METHOD import_csv_file.
    DATA lt_batch_results TYPE zccmc_if_source_adapter=>ty_row_result_tab.
    DATA lt_batch_errors  TYPE zccmc_if_source_adapter=>ty_row_error_tab.

    " 1. Parse raw CSV
    DATA(ls_parsed) = zccmc_cl_csv_adapter=>parse_csv_string(
      iv_file_kind   = iv_file_kind
      iv_csv_content = iv_csv_content ).

    " 2. Create Batch header
    rs_batch = zccmc_cl_import_batch_mgr=>create_batch(
      EXPORTING
        iv_file_kind   = ls_parsed-file_kind
        iv_file_sha256 = ls_parsed-file_sha256
        iv_actor       = iv_actor
        iv_timestamp   = iv_timestamp
      CHANGING
        cs_store       = cs_store ).

    " 3. Validate header, schema, types, dates, enums, and intra-file duplicate keys
    DATA(ls_val) = zccmc_cl_import_validator=>validate_parsed_file( ls_parsed ).
    IF ls_val-ok = abap_false.
      zccmc_cl_import_batch_mgr=>fail_batch_file_level(
        EXPORTING
          iv_error_code    = ls_val-file_error_code
          iv_error_message = ls_val-file_error_msg
        CHANGING
          cs_batch         = rs_batch
          cs_store         = cs_store ).
      RETURN.
    ENDIF.

    rs_batch-status = zccmc_if_source_adapter=>c_batch_status-validated.

    " Record validator-detected row errors
    LOOP AT ls_val-row_errors INTO DATA(ls_verr).
      zccmc_cl_import_batch_mgr=>record_rejected_row(
        EXPORTING
          iv_source_record = ls_verr-source_record
          iv_business_key  = ls_verr-business_key
          iv_error_code    = ls_verr-error_code
          iv_field_name    = ls_verr-field_name
          iv_message       = ls_verr-message
        CHANGING
          cs_batch         = rs_batch
          ct_row_results   = lt_batch_results
          ct_row_errors    = lt_batch_errors ).
    ENDLOOP.

    " 4. Take pre-load snapshot of business entities to guarantee file-level rollback on fatal DB error
    DATA(lt_snap_objects) = cs_store-objects.
    DATA(lt_snap_usages)  = cs_store-usages.
    DATA(lt_snap_finds)   = cs_store-findings.
    DATA(lt_snap_deps)    = cs_store-dependencies.
    DATA(lv_snap_seq)     = cs_store-next_uuid_seq.

    " 5. Execute entity loader for valid rows
    CASE ls_val-file_kind.
      WHEN zccmc_if_source_adapter=>c_file_kind-objects.
        zccmc_cl_import_object_loader=>load_objects(
          EXPORTING it_valid_objects = ls_val-valid_objects
          CHANGING  cs_batch         = rs_batch
                    ct_batch_results = lt_batch_results
                    ct_batch_errors  = lt_batch_errors
                    cs_store         = cs_store ).
      WHEN zccmc_if_source_adapter=>c_file_kind-usage.
        zccmc_cl_import_usage_loader=>load_usages(
          EXPORTING it_valid_usages  = ls_val-valid_usages
          CHANGING  cs_batch         = rs_batch
                    ct_batch_results = lt_batch_results
                    ct_batch_errors  = lt_batch_errors
                    cs_store         = cs_store ).
      WHEN zccmc_if_source_adapter=>c_file_kind-findings.
        zccmc_cl_import_finding_loader=>load_findings(
          EXPORTING it_valid_findings = ls_val-valid_findings
          CHANGING  cs_batch          = rs_batch
                    ct_batch_results  = lt_batch_results
                    ct_batch_errors   = lt_batch_errors
                    cs_store          = cs_store ).
      WHEN zccmc_if_source_adapter=>c_file_kind-dependencies.
        zccmc_cl_import_dep_loader=>load_dependencies(
          EXPORTING it_valid_deps    = ls_val-valid_deps
          CHANGING  cs_batch         = rs_batch
                    ct_batch_results = lt_batch_results
                    ct_batch_errors  = lt_batch_errors
                    cs_store         = cs_store ).
    ENDCASE.

    " 6. Check for fatal persistence failure and roll back file business writes atomically
    IF cs_store-simulate_persistence_failure = abap_true.
      cs_store-objects       = lt_snap_objects.
      cs_store-usages        = lt_snap_usages.
      cs_store-findings      = lt_snap_finds.
      cs_store-dependencies  = lt_snap_deps.
      cs_store-next_uuid_seq = lv_snap_seq.

      rs_batch-inserted_count  = 0.
      rs_batch-updated_count   = 0.
      rs_batch-unchanged_count = 0.
      rs_batch-accepted_count  = 0.
      zccmc_cl_import_batch_mgr=>fail_batch_file_level(
        EXPORTING
          iv_error_code    = zccmc_if_source_adapter=>c_error-persistence_failure
          iv_error_message = 'Fatal storage failure; file business-row transaction rolled back.'
        CHANGING
          cs_batch         = rs_batch
          cs_store         = cs_store ).
      RETURN.
    ENDIF.

    " 7. Sort batch results and errors by source_record for deterministic provenance
    SORT lt_batch_results BY source_record ASCENDING.
    SORT lt_batch_errors  BY source_record ASCENDING.

    zccmc_cl_import_batch_mgr=>finalize_batch(
      EXPORTING
        it_batch_results = lt_batch_results
        it_batch_errors  = lt_batch_errors
      CHANGING
        cs_batch         = rs_batch
        cs_store         = cs_store ).
  ENDMETHOD.


  METHOD import_four_file_set.
    rs_summary-objects_batch = import_csv_file(
      EXPORTING iv_file_kind   = zccmc_if_source_adapter=>c_file_kind-objects
                iv_csv_content = iv_objects_csv
                iv_actor       = iv_actor
                iv_timestamp   = iv_timestamp
      CHANGING  cs_store       = cs_store ).

    rs_summary-usage_batch = import_csv_file(
      EXPORTING iv_file_kind   = zccmc_if_source_adapter=>c_file_kind-usage
                iv_csv_content = iv_usage_csv
                iv_actor       = iv_actor
                iv_timestamp   = iv_timestamp
      CHANGING  cs_store       = cs_store ).

    rs_summary-findings_batch = import_csv_file(
      EXPORTING iv_file_kind   = zccmc_if_source_adapter=>c_file_kind-findings
                iv_csv_content = iv_findings_csv
                iv_actor       = iv_actor
                iv_timestamp   = iv_timestamp
      CHANGING  cs_store       = cs_store ).

    rs_summary-dependencies_batch = import_csv_file(
      EXPORTING iv_file_kind   = zccmc_if_source_adapter=>c_file_kind-dependencies
                iv_csv_content = iv_dependencies_csv
                iv_actor       = iv_actor
                iv_timestamp   = iv_timestamp
      CHANGING  cs_store       = cs_store ).
  ENDMETHOD.


  METHOD build_m2_evidence_for_object.
    CLEAR rs_evidence.
    READ TABLE is_store-objects INTO DATA(ls_obj) WITH KEY object_uuid = iv_object_uuid.
    IF sy-subrc <> 0.
      RETURN.
    ENDIF.

    rs_evidence-object_id      = ls_obj-object_uuid.
    rs_evidence-criticality    = ls_obj-criticality.
    rs_evidence-findings_as_of = ls_obj-findings_as_of.

    LOOP AT is_store-usages INTO DATA(ls_usg) WHERE object_uuid = iv_object_uuid.
      APPEND VALUE #(
        period_start   = ls_usg-period_start
        period_end     = ls_usg-period_end
        last_executed  = ls_usg-last_executed
        run_count      = ls_usg-run_count
        evidence_as_of = ls_usg-evidence_as_of
      ) TO rs_evidence-usages.
    ENDLOOP.

    LOOP AT is_store-findings INTO DATA(ls_fnd) WHERE object_uuid = iv_object_uuid.
      APPEND VALUE #( severity = ls_fnd-severity ) TO rs_evidence-findings.
    ENDLOOP.

    LOOP AT is_store-dependencies INTO DATA(ls_dep) WHERE to_object_uuid = iv_object_uuid.
      READ TABLE is_store-objects INTO DATA(ls_caller) WITH KEY object_uuid = ls_dep-from_object_uuid.
      IF sy-subrc = 0.
        APPEND VALUE #( criticality = ls_caller-criticality ) TO rs_evidence-callers.
      ENDIF.
    ENDLOOP.
  ENDMETHOD.

ENDCLASS.
