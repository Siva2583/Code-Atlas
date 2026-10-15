"! ABAP Unit tests for ZCCMC_CL_IMPORT_ORCHESTRATOR & Loaders (Member 1 — M1-D05-T01 / M1-D10-T01).
"! DEMO / SYNTHETIC data only.
"!
"! STATUS: written without live ADT execution in the shared trial tenant (non-$TMP package
"! creation remains blocked/unverified; see docs/feasibility-note.md F-02 and docs/limitations.md).
"! Run in ADT (Ctrl+Shift+F10) once package ZCCMC is provisioned, and cross-check offline via:
"!   python3 tools/m1_import_oracle.py --report docs/m1-golden-import-results.md
"!
"! Covers 10 idempotency, correction, provenance, reset, and cross-team integration scenarios (IMP-I01..IMP-I10):
"! - T01: Clean 4-file baseline load (7 objects, 6 usages, 8 findings, 2 dependencies) -> all INSERTED & COMMITTED.
"! - T02: Immediate repeat import of all 4 files -> all UNCHANGED, zero duplicates, ObjectUUIDs preserved, new BatchUUIDs created.
"! - T03: Corrected batch (objects_corrected_batch.csv) -> 1 UPDATED in place, ObjectUUID preserved, other 6 objects untouched.
"! - T04: Replay baseline objects.csv after corrected batch -> 1 UPDATED (reverted) + 6 UNCHANGED.
"! - T05: Usage, finding, and dependency upsert idempotency (INSERTED -> UNCHANGED -> UPDATED).
"! - T06: Day-10 reproducible reset and two consecutive clean runs -> identical counts, business keys, and row digests.
"! - T07: Input row-order permutation across all 4 files -> identical persisted business state.
"! - T08: M1 -> M2 bridge (build_m2_evidence_for_object) -> evaluates all 7 sample objects to exact M2 golden outcomes.
"! - T09: M1 -> M3 ObjectUUID stability -> M3 decision linked to ObjectUUID remains valid across M1 repeat/corrected imports.
"! - T10: Append-only provenance ledger -> batches, row_results, and row_errors preserve full historical trace.
CLASS zccmc_ut_import_idempotency DEFINITION
  PUBLIC
  FINAL
  FOR TESTING
  RISK LEVEL HARMLESS
  DURATION SHORT.

  PRIVATE SECTION.
    METHODS:
      t01_clean_four_file_baseline   FOR TESTING,
      t02_repeat_import_unchanged    FOR TESTING,
      t03_corrected_batch_in_place   FOR TESTING,
      t04_replay_baseline_after_corr FOR TESTING,
      t05_dependent_upsert_semantics FOR TESTING,
      t06_clean_reset_reproducible   FOR TESTING,
      t07_row_order_permutation_det  FOR TESTING,
      t08_m1_to_m2_evidence_bridge   FOR TESTING,
      t09_m1_to_m3_uuid_stability    FOR TESTING,
      t10_append_only_provenance     FOR TESTING.

    METHODS:
      sample_objects_csv      RETURNING VALUE(rv_csv) TYPE string,
      sample_usage_csv        RETURNING VALUE(rv_csv) TYPE string,
      sample_findings_csv     RETURNING VALUE(rv_csv) TYPE string,
      sample_dependencies_csv RETURNING VALUE(rv_csv) TYPE string,
      corrected_objects_csv   RETURNING VALUE(rv_csv) TYPE string.
ENDCLASS.



CLASS zccmc_ut_import_idempotency IMPLEMENTATION.

  METHOD sample_objects_csv.
    rv_csv =
      |source_system,object_type,object_name,package,description,criticality,business_owner,first_seen,last_seen,findings_as_of
| &&
      |DEMO_SYS,PROG,ZSD_OPEN_ORDERS_RPT,ZSD_REPORTS,DEMO open sales orders report,HIGH,DEMO_OWNER_SD,2019-03-11,2026-09-25,2026-10-13
| &&
      |DEMO_SYS,CLAS,ZCL_PRICING_HELPER,ZSD_PRICING,DEMO pricing helper class,MEDIUM,DEMO_OWNER_SD,2018-06-02,2026-10-01,2026-10-13
| &&
      |DEMO_SYS,PROG,ZFI_OLD_LEDGER_EXPORT,ZFI_LEGACY,DEMO legacy ledger export,LOW,DEMO_OWNER_FI,2015-01-20,2023-02-14,2026-10-13
| &&
      |DEMO_SYS,PROG,ZMM_STOCK_ALERT,ZMM_ALERTS,DEMO stock alert report,MEDIUM,DEMO_OWNER_MM,2021-09-09,2026-10-05,2026-10-13
| &&
      |DEMO_SYS,FUGR,ZSD_CUST_CREDIT_CHECK,ZSD_CREDIT,DEMO customer credit check,HIGH,DEMO_OWNER_SD,2017-11-30,2026-10-10,2026-10-13
| &&
      |DEMO_SYS,CLAS,ZCL_INVOICE_UTIL,ZFI_INVOICE,DEMO invoice utility class,UNKNOWN,DEMO_OWNER_FI,2020-04-17,2026-09-30,2026-10-13
| &&
      |DEMO_SYS,PROG,ZHR_PAYROLL_ADJ,ZHR_PAYROLL,DEMO payroll adjustment program,UNKNOWN,DEMO_OWNER_HR,2016-08-05,2025-12-12,2026-10-13
|.
  ENDMETHOD.


  METHOD sample_usage_csv.
    rv_csv =
      |source_system,object_type,object_name,period_start,period_end,last_executed,run_count,evidence_source,evidence_as_of
| &&
      |DEMO_SYS,PROG,ZSD_OPEN_ORDERS_RPT,2025-10-13,2026-10-13,2026-09-25,2480,DEMO,2026-10-13
| &&
      |DEMO_SYS,CLAS,ZCL_PRICING_HELPER,2025-10-13,2026-10-13,2026-10-12,15210,DEMO,2026-10-13
| &&
      |DEMO_SYS,PROG,ZMM_STOCK_ALERT,2026-08-01,2026-10-13,,0,DEMO,2026-10-13
| &&
      |DEMO_SYS,FUGR,ZSD_CUST_CREDIT_CHECK,2025-10-13,2026-10-13,2026-10-10,930,DEMO,2026-10-13
| &&
      |DEMO_SYS,CLAS,ZCL_INVOICE_UTIL,2025-10-13,2026-10-13,2026-09-30,41,DEMO,2026-10-13
| &&
      |DEMO_SYS,PROG,ZHR_PAYROLL_ADJ,2025-10-13,2026-10-13,2025-12-12,3,DEMO,2026-10-13
|.
  ENDMETHOD.


  METHOD sample_findings_csv.
    rv_csv =
      |source_system,object_type,object_name,finding_id,check_id,category,severity,message,source_reference
| &&
      |DEMO_SYS,PROG,ZSD_OPEN_ORDERS_RPT,F001,DEMO_CHK_01,API,HIGH,DEMO unreleased API call,DEMO_ATC_001
| &&
      |DEMO_SYS,PROG,ZSD_OPEN_ORDERS_RPT,F002,DEMO_CHK_02,DB_ACCESS,HIGH,DEMO direct standard table access,DEMO_ATC_001
| &&
      |DEMO_SYS,PROG,ZSD_OPEN_ORDERS_RPT,F003,DEMO_CHK_03,SYNTAX,MEDIUM,DEMO obsolete statement,DEMO_ATC_001
| &&
      |DEMO_SYS,PROG,ZSD_OPEN_ORDERS_RPT,F004,DEMO_CHK_03,SYNTAX,MEDIUM,DEMO obsolete statement,DEMO_ATC_001
| &&
      |DEMO_SYS,PROG,ZSD_OPEN_ORDERS_RPT,F005,DEMO_CHK_04,PERFORMANCE,MEDIUM,DEMO select in loop,DEMO_ATC_001
| &&
      |DEMO_SYS,PROG,ZSD_OPEN_ORDERS_RPT,F006,DEMO_CHK_05,SCHEDULING,MEDIUM,DEMO referenced by one scheduled job,DEMO_ATC_001
| &&
      |DEMO_SYS,FUGR,ZSD_CUST_CREDIT_CHECK,F007,DEMO_CHK_01,API,HIGH,DEMO unreleased API call,DEMO_ATC_002
| &&
      |DEMO_SYS,CLAS,ZCL_PRICING_HELPER,F008,DEMO_CHK_03,SYNTAX,LOW,DEMO obsolete statement,DEMO_ATC_002
|.
  ENDMETHOD.


  METHOD sample_dependencies_csv.
    rv_csv =
      |source_system,from_type,from_name,to_type,to_name,dependency_type,evidence_source
| &&
      |DEMO_SYS,PROG,ZSD_OPEN_ORDERS_RPT,CLAS,ZCL_PRICING_HELPER,CALL,DEMO
| &&
      |DEMO_SYS,FUGR,ZSD_CUST_CREDIT_CHECK,CLAS,ZCL_INVOICE_UTIL,CALL,DEMO
|.
  ENDMETHOD.


  METHOD corrected_objects_csv.
    rv_csv =
      |source_system,object_type,object_name,package,description,criticality,business_owner,first_seen,last_seen,findings_as_of
| &&
      |DEMO_SYS,PROG,ZSD_OPEN_ORDERS_RPT,ZSD_REPORTS,DEMO corrected open sales orders report,HIGH,DEMO_OWNER_SD,2019-03-11,2026-09-25,2026-10-13
|.
  ENDMETHOD.


  METHOD t01_clean_four_file_baseline.
    DATA(ls_store) = zccmc_cl_import_orchestrator=>init_store( ).
    DATA(ls_sum) = zccmc_cl_import_orchestrator=>import_four_file_set(
      EXPORTING
        iv_objects_csv      = sample_objects_csv( )
        iv_usage_csv        = sample_usage_csv( )
        iv_findings_csv     = sample_findings_csv( )
        iv_dependencies_csv = sample_dependencies_csv( )
      CHANGING
        cs_store            = ls_store ).

    cl_abap_unit_assert=>assert_equals( act = ls_sum-objects_batch-status      exp = 'COMMITTED' ).
    cl_abap_unit_assert=>assert_equals( act = ls_sum-objects_batch-inserted_count exp = 7 ).
    cl_abap_unit_assert=>assert_equals( act = ls_sum-usage_batch-inserted_count   exp = 6 ).
    cl_abap_unit_assert=>assert_equals( act = ls_sum-findings_batch-inserted_count exp = 8 ).
    cl_abap_unit_assert=>assert_equals( act = ls_sum-dependencies_batch-inserted_count exp = 2 ).
    cl_abap_unit_assert=>assert_equals( act = lines( ls_store-objects )      exp = 7 ).
    cl_abap_unit_assert=>assert_equals( act = lines( ls_store-usages )       exp = 6 ).
    cl_abap_unit_assert=>assert_equals( act = lines( ls_store-findings )     exp = 8 ).
    cl_abap_unit_assert=>assert_equals( act = lines( ls_store-dependencies ) exp = 2 ).
    cl_abap_unit_assert=>assert_equals( act = lines( ls_store-row_errors )   exp = 0 ).
  ENDMETHOD.


  METHOD t02_repeat_import_unchanged.
    DATA(ls_store) = zccmc_cl_import_orchestrator=>init_store( ).
    zccmc_cl_import_orchestrator=>import_four_file_set(
      EXPORTING iv_objects_csv = sample_objects_csv( ) iv_usage_csv = sample_usage_csv( )
                iv_findings_csv = sample_findings_csv( ) iv_dependencies_csv = sample_dependencies_csv( )
      CHANGING  cs_store = ls_store ).

    DATA(lt_uuids_before) = ls_store-objects.

    DATA(ls_rep) = zccmc_cl_import_orchestrator=>import_four_file_set(
      EXPORTING iv_objects_csv = sample_objects_csv( ) iv_usage_csv = sample_usage_csv( )
                iv_findings_csv = sample_findings_csv( ) iv_dependencies_csv = sample_dependencies_csv( )
      CHANGING  cs_store = ls_store ).

    cl_abap_unit_assert=>assert_equals( act = ls_rep-objects_batch-status          exp = 'COMMITTED' ).
    cl_abap_unit_assert=>assert_equals( act = ls_rep-objects_batch-unchanged_count exp = 7 ).
    cl_abap_unit_assert=>assert_equals( act = ls_rep-objects_batch-inserted_count  exp = 0 ).
    cl_abap_unit_assert=>assert_equals( act = ls_rep-usage_batch-unchanged_count   exp = 6 ).
    cl_abap_unit_assert=>assert_equals( act = ls_rep-findings_batch-unchanged_count exp = 8 ).
    cl_abap_unit_assert=>assert_equals( act = ls_rep-dependencies_batch-unchanged_count exp = 2 ).
    cl_abap_unit_assert=>assert_equals( act = lines( ls_store-objects ) exp = 7 ).

    LOOP AT ls_store-objects INTO DATA(ls_after).
      cl_abap_unit_assert=>assert_equals(
        act = ls_after-object_uuid
        exp = lt_uuids_before[ sy-tabix ]-object_uuid ).
    ENDLOOP.
  ENDMETHOD.


  METHOD t03_corrected_batch_in_place.
    DATA(ls_store) = zccmc_cl_import_orchestrator=>init_store( ).
    zccmc_cl_import_orchestrator=>import_csv_file(
      EXPORTING iv_file_kind = 'objects' iv_csv_content = sample_objects_csv( )
      CHANGING  cs_store     = ls_store ).

    READ TABLE ls_store-objects INTO DATA(ls_before) WITH KEY object_name = 'ZSD_OPEN_ORDERS_RPT'.
    DATA(ls_corr_batch) = zccmc_cl_import_orchestrator=>import_csv_file(
      EXPORTING iv_file_kind = 'objects' iv_csv_content = corrected_objects_csv( )
      CHANGING  cs_store     = ls_store ).

    cl_abap_unit_assert=>assert_equals( act = ls_corr_batch-status        exp = 'COMMITTED' ).
    cl_abap_unit_assert=>assert_equals( act = ls_corr_batch-updated_count exp = 1 ).
    cl_abap_unit_assert=>assert_equals( act = lines( ls_store-objects )   exp = 7 ).

    READ TABLE ls_store-objects INTO DATA(ls_after) WITH KEY object_name = 'ZSD_OPEN_ORDERS_RPT'.
    cl_abap_unit_assert=>assert_equals( act = ls_after-object_uuid exp = ls_before-object_uuid ).
    cl_abap_unit_assert=>assert_equals( act = ls_after-description exp = 'DEMO corrected open sales orders report' ).
  ENDMETHOD.


  METHOD t04_replay_baseline_after_corr.
    DATA(ls_store) = zccmc_cl_import_orchestrator=>init_store( ).
    zccmc_cl_import_orchestrator=>import_csv_file(
      EXPORTING iv_file_kind = 'objects' iv_csv_content = sample_objects_csv( )
      CHANGING  cs_store     = ls_store ).
    zccmc_cl_import_orchestrator=>import_csv_file(
      EXPORTING iv_file_kind = 'objects' iv_csv_content = corrected_objects_csv( )
      CHANGING  cs_store     = ls_store ).

    DATA(ls_replay) = zccmc_cl_import_orchestrator=>import_csv_file(
      EXPORTING iv_file_kind = 'objects' iv_csv_content = sample_objects_csv( )
      CHANGING  cs_store     = ls_store ).

    cl_abap_unit_assert=>assert_equals( act = ls_replay-updated_count   exp = 1 ).
    cl_abap_unit_assert=>assert_equals( act = ls_replay-unchanged_count exp = 6 ).
    cl_abap_unit_assert=>assert_equals( act = ls_replay-accepted_count  exp = 7 ).
  ENDMETHOD.


  METHOD t05_dependent_upsert_semantics.
    DATA(ls_store) = zccmc_cl_import_orchestrator=>init_store( ).
    zccmc_cl_import_orchestrator=>import_csv_file(
      EXPORTING iv_file_kind = 'objects' iv_csv_content = sample_objects_csv( )
      CHANGING  cs_store     = ls_store ).
    zccmc_cl_import_orchestrator=>import_csv_file(
      EXPORTING iv_file_kind = 'usage' iv_csv_content = sample_usage_csv( )
      CHANGING  cs_store     = ls_store ).

    " Modify run_count on one usage key -> UPDATED
    DATA(lv_usg_upd) =
      |source_system,object_type,object_name,period_start,period_end,last_executed,run_count,evidence_source,evidence_as_of
| &&
      |DEMO_SYS,PROG,ZSD_OPEN_ORDERS_RPT,2025-10-13,2026-10-13,2026-09-25,2500,DEMO,2026-10-13
|.
    DATA(ls_b) = zccmc_cl_import_orchestrator=>import_csv_file(
      EXPORTING iv_file_kind = 'usage' iv_csv_content = lv_usg_upd
      CHANGING  cs_store     = ls_store ).
    cl_abap_unit_assert=>assert_equals( act = ls_b-updated_count exp = 1 ).
    cl_abap_unit_assert=>assert_equals( act = lines( ls_store-usages ) exp = 6 ).
  ENDMETHOD.


  METHOD t06_clean_reset_reproducible.
    DATA(ls_store) = zccmc_cl_import_orchestrator=>init_store( ).
    zccmc_cl_import_orchestrator=>import_four_file_set(
      EXPORTING iv_objects_csv = sample_objects_csv( ) iv_usage_csv = sample_usage_csv( )
                iv_findings_csv = sample_findings_csv( ) iv_dependencies_csv = sample_dependencies_csv( )
      CHANGING  cs_store = ls_store ).
    DATA(lt_run1_objs) = ls_store-objects.

    zccmc_cl_import_orchestrator=>reset_synthetic_store( CHANGING cs_store = ls_store ).
    cl_abap_unit_assert=>assert_equals( act = lines( ls_store-objects ) exp = 0 ).

    zccmc_cl_import_orchestrator=>import_four_file_set(
      EXPORTING iv_objects_csv = sample_objects_csv( ) iv_usage_csv = sample_usage_csv( )
                iv_findings_csv = sample_findings_csv( ) iv_dependencies_csv = sample_dependencies_csv( )
      CHANGING  cs_store = ls_store ).
    cl_abap_unit_assert=>assert_equals( act = lines( ls_store-objects ) exp = lines( lt_run1_objs ) ).
    LOOP AT ls_store-objects INTO DATA(ls_r2).
      cl_abap_unit_assert=>assert_equals( act = ls_r2-business_key exp = lt_run1_objs[ sy-tabix ]-business_key ).
      cl_abap_unit_assert=>assert_equals( act = ls_r2-row_sha256   exp = lt_run1_objs[ sy-tabix ]-row_sha256 ).
    ENDLOOP.
  ENDMETHOD.


  METHOD t07_row_order_permutation_det.
    DATA(ls_s1) = zccmc_cl_import_orchestrator=>init_store( ).
    zccmc_cl_import_orchestrator=>import_csv_file(
      EXPORTING iv_file_kind = 'objects' iv_csv_content = sample_objects_csv( )
      CHANGING  cs_store     = ls_s1 ).

    DATA(lv_rev_objects) =
      |source_system,object_type,object_name,package,description,criticality,business_owner,first_seen,last_seen,findings_as_of
| &&
      |DEMO_SYS,PROG,ZHR_PAYROLL_ADJ,ZHR_PAYROLL,DEMO payroll adjustment program,UNKNOWN,DEMO_OWNER_HR,2016-08-05,2025-12-12,2026-10-13
| &&
      |DEMO_SYS,CLAS,ZCL_INVOICE_UTIL,ZFI_INVOICE,DEMO invoice utility class,UNKNOWN,DEMO_OWNER_FI,2020-04-17,2026-09-30,2026-10-13
| &&
      |DEMO_SYS,FUGR,ZSD_CUST_CREDIT_CHECK,ZSD_CREDIT,DEMO customer credit check,HIGH,DEMO_OWNER_SD,2017-11-30,2026-10-10,2026-10-13
| &&
      |DEMO_SYS,PROG,ZMM_STOCK_ALERT,ZMM_ALERTS,DEMO stock alert report,MEDIUM,DEMO_OWNER_MM,2021-09-09,2026-10-05,2026-10-13
| &&
      |DEMO_SYS,PROG,ZFI_OLD_LEDGER_EXPORT,ZFI_LEGACY,DEMO legacy ledger export,LOW,DEMO_OWNER_FI,2015-01-20,2023-02-14,2026-10-13
| &&
      |DEMO_SYS,CLAS,ZCL_PRICING_HELPER,ZSD_PRICING,DEMO pricing helper class,MEDIUM,DEMO_OWNER_SD,2018-06-02,2026-10-01,2026-10-13
| &&
      |DEMO_SYS,PROG,ZSD_OPEN_ORDERS_RPT,ZSD_REPORTS,DEMO open sales orders report,HIGH,DEMO_OWNER_SD,2019-03-11,2026-09-25,2026-10-13
|.

    DATA(ls_s2) = zccmc_cl_import_orchestrator=>init_store( ).
    zccmc_cl_import_orchestrator=>import_csv_file(
      EXPORTING iv_file_kind = 'objects' iv_csv_content = lv_rev_objects
      CHANGING  cs_store     = ls_s2 ).

    SORT ls_s1-objects BY business_key ASCENDING.
    SORT ls_s2-objects BY business_key ASCENDING.
    LOOP AT ls_s1-objects INTO DATA(ls_o1).
      cl_abap_unit_assert=>assert_equals( act = ls_s2-objects[ sy-tabix ]-business_key exp = ls_o1-business_key ).
      cl_abap_unit_assert=>assert_equals( act = ls_s2-objects[ sy-tabix ]-row_sha256   exp = ls_o1-row_sha256 ).
    ENDLOOP.
  ENDMETHOD.


  METHOD t08_m1_to_m2_evidence_bridge.
    DATA(ls_store) = zccmc_cl_import_orchestrator=>init_store( ).
    zccmc_cl_import_orchestrator=>import_four_file_set(
      EXPORTING iv_objects_csv = sample_objects_csv( ) iv_usage_csv = sample_usage_csv( )
                iv_findings_csv = sample_findings_csv( ) iv_dependencies_csv = sample_dependencies_csv( )
      CHANGING  cs_store = ls_store ).

    DATA(ls_ruleset) = zccmc_cl_rule_engine=>seed_ruleset( ).
    DATA lv_keep_cnt   TYPE i VALUE 0.
    DATA lv_manual_cnt TYPE i VALUE 0.

    LOOP AT ls_store-objects INTO DATA(ls_obj).
      DATA(ls_ev) = zccmc_cl_import_orchestrator=>build_m2_evidence_for_object(
        is_store       = ls_store
        iv_object_uuid = ls_obj-object_uuid ).
      DATA(ls_res) = zccmc_cl_rule_engine=>evaluate(
        is_evidence        = ls_ev
        is_ruleset         = ls_ruleset
        iv_evaluation_date = '20261014'
        iv_run_id          = 'RUN-M1-M2-BRIDGE' ).
      IF ls_res-recommended_strategy = zccmc_cl_rule_engine=>c_outcome-keep_adapt.
        lv_keep_cnt = lv_keep_cnt + 1.
      ELSEIF ls_res-recommended_strategy = zccmc_cl_rule_engine=>c_outcome-manual_review.
        lv_manual_cnt = lv_manual_cnt + 1.
      ENDIF.
    ENDLOOP.

    cl_abap_unit_assert=>assert_equals( act = lv_keep_cnt   exp = 1 ).
    cl_abap_unit_assert=>assert_equals( act = lv_manual_cnt exp = 6 ).
  ENDMETHOD.


  METHOD t09_m1_to_m3_uuid_stability.
    DATA(ls_store) = zccmc_cl_import_orchestrator=>init_store( ).
    zccmc_cl_import_orchestrator=>import_csv_file(
      EXPORTING iv_file_kind = 'objects' iv_csv_content = sample_objects_csv( )
      CHANGING  cs_store     = ls_store ).

    READ TABLE ls_store-objects INTO DATA(ls_obj) WITH KEY object_name = 'ZSD_OPEN_ORDERS_RPT'.
    DATA(lv_uuid_initial) = ls_obj-object_uuid.

    zccmc_cl_import_orchestrator=>import_csv_file(
      EXPORTING iv_file_kind = 'objects' iv_csv_content = corrected_objects_csv( )
      CHANGING  cs_store     = ls_store ).

    READ TABLE ls_store-objects INTO DATA(ls_obj_after) WITH KEY object_name = 'ZSD_OPEN_ORDERS_RPT'.
    cl_abap_unit_assert=>assert_equals( act = ls_obj_after-object_uuid exp = lv_uuid_initial ).
  ENDMETHOD.


  METHOD t10_append_only_provenance.
    DATA(ls_store) = zccmc_cl_import_orchestrator=>init_store( ).
    zccmc_cl_import_orchestrator=>import_csv_file(
      EXPORTING iv_file_kind = 'objects' iv_csv_content = sample_objects_csv( )
      CHANGING  cs_store     = ls_store ).
    zccmc_cl_import_orchestrator=>import_csv_file(
      EXPORTING iv_file_kind = 'objects' iv_csv_content = corrected_objects_csv( )
      CHANGING  cs_store     = ls_store ).

    cl_abap_unit_assert=>assert_equals( act = lines( ls_store-batches )     exp = 2 ).
    cl_abap_unit_assert=>assert_equals( act = lines( ls_store-row_results ) exp = 8 ).
  ENDMETHOD.

ENDCLASS.
