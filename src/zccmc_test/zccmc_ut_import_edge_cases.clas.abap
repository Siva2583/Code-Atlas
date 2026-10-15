"! ABAP Unit tests for M1 Edge Cases, Reference Order, Rollback & Scale (Member 1 — M1-D06..D08).
"! DEMO / SYNTHETIC data only.
"!
"! STATUS: written without live ADT execution in the shared trial tenant (non-$TMP package
"! creation remains blocked/unverified; see docs/feasibility-note.md F-02 and docs/limitations.md).
"! Run in ADT (Ctrl+Shift+F10) once package ZCCMC is provisioned, and cross-check offline via:
"!   python3 tools/m1_import_oracle.py --report docs/m1-golden-import-results.md
"!
"! Covers 10 edge-case, reference-order, transactional rollback, and scale scenarios (IMP-E01..IMP-E10):
"! - T01: objects_empty.csv -> FAILED with EMPTY_FILE, zero business rows written.
"! - T02: objects_duplicate_keys.csv -> FAILED, 2 REJECTED with DUPLICATE_KEY, zero objects written.
"! - T03: usage_malformed_date.csv -> FAILED, 1 REJECTED with INVALID_DATE on period_start.
"! - T04: findings_unknown_object.csv -> FAILED, 1 REJECTED with UNKNOWN_OBJECT, zero orphan findings.
"! - T05: findings_quoted_fields.csv -> COMMITTED, 1 INSERTED, comma and quotes preserved.
"! - T06: Reverse-order import (usage/findings/dependencies before objects) -> UNKNOWN_OBJECT, no deferred replay when objects load later.
"! - T07: Partial-batch commit -> 1 valid row + 1 invalid row in same file commits valid row (COMMITTED) and logs row error.
"! - T08: Unprovisioned source system -> rejected with UNKNOWN_SOURCE_SYSTEM.
"! - T09: Fatal persistence failure -> rolls back all business writes from that file and marks batch FAILED with PERSISTENCE_FAILURE.
"! - T10: Synthetic bulk object batch -> verifies exact row count, unique keys, and repeat-import UNCHANGED idempotency.
CLASS zccmc_ut_import_edge_cases DEFINITION
  PUBLIC
  FINAL
  FOR TESTING
  RISK LEVEL HARMLESS
  DURATION SHORT.

  PRIVATE SECTION.
    METHODS:
      t01_edge_objects_empty          FOR TESTING,
      t02_edge_objects_duplicate_keys FOR TESTING,
      t03_edge_usage_malformed_date   FOR TESTING,
      t04_edge_findings_unknown_obj   FOR TESTING,
      t05_edge_findings_quoted_fields FOR TESTING,
      t06_reverse_order_no_replay     FOR TESTING,
      t07_partial_batch_valid_invalid FOR TESTING,
      t08_unknown_source_system_rej   FOR TESTING,
      t09_fatal_persistence_rollback  FOR TESTING,
      t10_scale_bulk_and_repeat       FOR TESTING.

    METHODS:
      base_objects_csv RETURNING VALUE(rv_csv) TYPE string.
ENDCLASS.



CLASS zccmc_ut_import_edge_cases IMPLEMENTATION.

  METHOD base_objects_csv.
    rv_csv =
      |source_system,object_type,object_name,package,description,criticality,business_owner,first_seen,last_seen,findings_as_of
| &&
      |DEMO_SYS,PROG,ZSD_OPEN_ORDERS_RPT,ZSD_REPORTS,DEMO open sales orders report,HIGH,DEMO_OWNER_SD,2019-03-11,2026-09-25,2026-10-13
| &&
      |DEMO_SYS,CLAS,ZCL_PRICING_HELPER,ZSD_PRICING,DEMO pricing helper class,MEDIUM,DEMO_OWNER_SD,2018-06-02,2026-10-01,2026-10-13
|.
  ENDMETHOD.


  METHOD t01_edge_objects_empty.
    DATA(ls_store) = zccmc_cl_import_orchestrator=>init_store( ).
    DATA(ls_batch) = zccmc_cl_import_orchestrator=>import_csv_file(
      EXPORTING iv_file_kind   = 'objects'
                iv_csv_content = |source_system,object_type,object_name,package,description,criticality,business_owner,first_seen,last_seen,findings_as_of
|
      CHANGING  cs_store       = ls_store ).

    cl_abap_unit_assert=>assert_equals( act = ls_batch-status          exp = 'FAILED' ).
    cl_abap_unit_assert=>assert_equals( act = ls_batch-file_error_code exp = 'EMPTY_FILE' ).
    cl_abap_unit_assert=>assert_equals( act = lines( ls_store-objects ) exp = 0 ).
  ENDMETHOD.


  METHOD t02_edge_objects_duplicate_keys.
    DATA(ls_store) = zccmc_cl_import_orchestrator=>init_store( ).
    DATA(lv_csv) =
      |source_system,object_type,object_name,package,description,criticality,business_owner,first_seen,last_seen,findings_as_of
| &&
      |DEMO_SYS,PROG,ZDEMO_DUPLICATE,ZDEMO,DEMO duplicate key first row,LOW,DEMO_OWNER,2026-01-01,2026-10-01,2026-10-13
| &&
      |DEMO_SYS,PROG,ZDEMO_DUPLICATE,ZDEMO,DEMO duplicate key corrected row,MEDIUM,DEMO_OWNER,2026-01-01,2026-10-01,2026-10-13
|.
    DATA(ls_batch) = zccmc_cl_import_orchestrator=>import_csv_file(
      EXPORTING iv_file_kind = 'objects' iv_csv_content = lv_csv
      CHANGING  cs_store     = ls_store ).

    cl_abap_unit_assert=>assert_equals( act = ls_batch-status          exp = 'FAILED' ).
    cl_abap_unit_assert=>assert_equals( act = ls_batch-parsed_count    exp = 2 ).
    cl_abap_unit_assert=>assert_equals( act = ls_batch-accepted_count  exp = 0 ).
    cl_abap_unit_assert=>assert_equals( act = ls_batch-rejected_count  exp = 2 ).
    cl_abap_unit_assert=>assert_equals( act = lines( ls_store-objects ) exp = 0 ).
    cl_abap_unit_assert=>assert_equals( act = ls_store-row_errors[ 1 ]-error_code exp = 'DUPLICATE_KEY' ).
    cl_abap_unit_assert=>assert_equals( act = ls_store-row_errors[ 2 ]-error_code exp = 'DUPLICATE_KEY' ).
  ENDMETHOD.


  METHOD t03_edge_usage_malformed_date.
    DATA(ls_store) = zccmc_cl_import_orchestrator=>init_store( ).
    zccmc_cl_import_orchestrator=>import_csv_file(
      EXPORTING iv_file_kind = 'objects' iv_csv_content = base_objects_csv( )
      CHANGING  cs_store     = ls_store ).

    DATA(lv_csv) =
      |source_system,object_type,object_name,period_start,period_end,last_executed,run_count,evidence_source,evidence_as_of
| &&
      |DEMO_SYS,PROG,ZSD_OPEN_ORDERS_RPT,2026-02-30,2026-10-13,,0,DEMO,2026-10-13
|.
    DATA(ls_batch) = zccmc_cl_import_orchestrator=>import_csv_file(
      EXPORTING iv_file_kind = 'usage' iv_csv_content = lv_csv
      CHANGING  cs_store     = ls_store ).

    cl_abap_unit_assert=>assert_equals( act = ls_batch-status         exp = 'FAILED' ).
    cl_abap_unit_assert=>assert_equals( act = ls_batch-rejected_count exp = 1 ).
    cl_abap_unit_assert=>assert_equals( act = lines( ls_store-usages ) exp = 0 ).
    cl_abap_unit_assert=>assert_equals( act = ls_store-row_errors[ 1 ]-error_code exp = 'INVALID_DATE' ).
    cl_abap_unit_assert=>assert_equals( act = ls_store-row_errors[ 1 ]-field_name exp = 'period_start' ).
  ENDMETHOD.


  METHOD t04_edge_findings_unknown_obj.
    DATA(ls_store) = zccmc_cl_import_orchestrator=>init_store( ).
    zccmc_cl_import_orchestrator=>import_csv_file(
      EXPORTING iv_file_kind = 'objects' iv_csv_content = base_objects_csv( )
      CHANGING  cs_store     = ls_store ).

    DATA(lv_csv) =
      |source_system,object_type,object_name,finding_id,check_id,category,severity,message,source_reference
| &&
      |DEMO_SYS,PROG,ZUNKNOWN_IMPORT_TARGET,F900,DEMO_CHK_UNKNOWN,API,LOW,DEMO finding references an unknown object,DEMO_EDGE_UNKNOWN
|.
    DATA(ls_batch) = zccmc_cl_import_orchestrator=>import_csv_file(
      EXPORTING iv_file_kind = 'findings' iv_csv_content = lv_csv
      CHANGING  cs_store     = ls_store ).

    cl_abap_unit_assert=>assert_equals( act = ls_batch-status          exp = 'FAILED' ).
    cl_abap_unit_assert=>assert_equals( act = ls_batch-rejected_count  exp = 1 ).
    cl_abap_unit_assert=>assert_equals( act = lines( ls_store-findings ) exp = 0 ).
    cl_abap_unit_assert=>assert_equals( act = ls_store-row_errors[ 1 ]-error_code exp = 'UNKNOWN_OBJECT' ).
  ENDMETHOD.


  METHOD t05_edge_findings_quoted_fields.
    DATA(ls_store) = zccmc_cl_import_orchestrator=>init_store( ).
    zccmc_cl_import_orchestrator=>import_csv_file(
      EXPORTING iv_file_kind = 'objects' iv_csv_content = base_objects_csv( )
      CHANGING  cs_store     = ls_store ).

    DATA(lv_csv) =
      |source_system,object_type,object_name,finding_id,check_id,category,severity,message,source_reference
| &&
      |DEMO_SYS,PROG,ZSD_OPEN_ORDERS_RPT,F900,DEMO_CHK_QUOTED,API,LOW,"DEMO quoted, comma and ""quote"" fixture",DEMO_EDGE_QUOTED
|.
    DATA(ls_batch) = zccmc_cl_import_orchestrator=>import_csv_file(
      EXPORTING iv_file_kind = 'findings' iv_csv_content = lv_csv
      CHANGING  cs_store     = ls_store ).

    cl_abap_unit_assert=>assert_equals( act = ls_batch-status          exp = 'COMMITTED' ).
    cl_abap_unit_assert=>assert_equals( act = ls_batch-inserted_count  exp = 1 ).
    cl_abap_unit_assert=>assert_equals(
      act = ls_store-findings[ 1 ]-message
      exp = `DEMO quoted, comma and "quote" fixture` ).
  ENDMETHOD.


  METHOD t06_reverse_order_no_replay.
    DATA(ls_store) = zccmc_cl_import_orchestrator=>init_store( ).
    DATA(lv_fnd_csv) =
      |source_system,object_type,object_name,finding_id,check_id,category,severity,message,source_reference
| &&
      |DEMO_SYS,PROG,ZSD_OPEN_ORDERS_RPT,F001,DEMO_CHK_01,API,HIGH,DEMO unreleased API call,DEMO_ATC_001
|.

    " Import findings BEFORE objects -> rejected UNKNOWN_OBJECT
    DATA(ls_b1) = zccmc_cl_import_orchestrator=>import_csv_file(
      EXPORTING iv_file_kind = 'findings' iv_csv_content = lv_fnd_csv
      CHANGING  cs_store     = ls_store ).
    cl_abap_unit_assert=>assert_equals( act = ls_b1-status         exp = 'FAILED' ).
    cl_abap_unit_assert=>assert_equals( act = ls_b1-rejected_count exp = 1 ).

    " Now import objects -> previously rejected finding is NOT silently replayed
    zccmc_cl_import_orchestrator=>import_csv_file(
      EXPORTING iv_file_kind = 'objects' iv_csv_content = base_objects_csv( )
      CHANGING  cs_store     = ls_store ).
    cl_abap_unit_assert=>assert_equals( act = lines( ls_store-findings ) exp = 0 ).
  ENDMETHOD.


  METHOD t07_partial_batch_valid_invalid.
    DATA(ls_store) = zccmc_cl_import_orchestrator=>init_store( ).
    DATA(lv_mixed) =
      |source_system,object_type,object_name,package,description,criticality,business_owner,first_seen,last_seen,findings_as_of
| &&
      |DEMO_SYS,PROG,ZVALID_OBJ_1,ZPKG,valid row,LOW,OWNER,2025-01-01,2026-01-01,2026-10-13
| &&
      |DEMO_SYS,PROG,ZINVALID_DATE_OBJ,ZPKG,invalid date row,LOW,OWNER,2026-02-30,2026-01-01,2026-10-13
|.
    DATA(ls_batch) = zccmc_cl_import_orchestrator=>import_csv_file(
      EXPORTING iv_file_kind = 'objects' iv_csv_content = lv_mixed
      CHANGING  cs_store     = ls_store ).

    cl_abap_unit_assert=>assert_equals( act = ls_batch-status          exp = 'COMMITTED' ).
    cl_abap_unit_assert=>assert_equals( act = ls_batch-parsed_count    exp = 2 ).
    cl_abap_unit_assert=>assert_equals( act = ls_batch-accepted_count  exp = 1 ).
    cl_abap_unit_assert=>assert_equals( act = ls_batch-rejected_count  exp = 1 ).
    cl_abap_unit_assert=>assert_equals( act = lines( ls_store-objects ) exp = 1 ).
  ENDMETHOD.


  METHOD t08_unknown_source_system_rej.
    DATA(ls_store) = zccmc_cl_import_orchestrator=>init_store( ).
    DATA(lv_csv) =
      |source_system,object_type,object_name,package,description,criticality,business_owner,first_seen,last_seen,findings_as_of
| &&
      |UNPROVISIONED_SYS,PROG,ZOBJ_1,ZPKG,desc,LOW,OWNER,2025-01-01,2026-01-01,2026-10-13
|.
    DATA(ls_batch) = zccmc_cl_import_orchestrator=>import_csv_file(
      EXPORTING iv_file_kind = 'objects' iv_csv_content = lv_csv
      CHANGING  cs_store     = ls_store ).

    cl_abap_unit_assert=>assert_equals( act = ls_batch-status         exp = 'FAILED' ).
    cl_abap_unit_assert=>assert_equals( act = ls_batch-rejected_count exp = 1 ).
    cl_abap_unit_assert=>assert_equals( act = ls_store-row_errors[ 1 ]-error_code exp = 'UNKNOWN_SOURCE_SYSTEM' ).
  ENDMETHOD.


  METHOD t09_fatal_persistence_rollback.
    DATA(ls_store) = zccmc_cl_import_orchestrator=>init_store( ).
    zccmc_cl_import_orchestrator=>import_csv_file(
      EXPORTING iv_file_kind = 'objects' iv_csv_content = base_objects_csv( )
      CHANGING  cs_store     = ls_store ).
    cl_abap_unit_assert=>assert_equals( act = lines( ls_store-objects ) exp = 2 ).

    " Inject fatal persistence failure on next file import -> must roll back business writes
    ls_store-simulate_persistence_failure = abap_true.
    DATA(lv_new_obj) =
      |source_system,object_type,object_name,package,description,criticality,business_owner,first_seen,last_seen,findings_as_of
| &&
      |DEMO_SYS,PROG,ZROLLBACK_TEST,ZPKG,should roll back,LOW,OWNER,2025-01-01,2026-01-01,2026-10-13
|.
    DATA(ls_batch) = zccmc_cl_import_orchestrator=>import_csv_file(
      EXPORTING iv_file_kind = 'objects' iv_csv_content = lv_new_obj
      CHANGING  cs_store     = ls_store ).

    cl_abap_unit_assert=>assert_equals( act = ls_batch-status          exp = 'FAILED' ).
    cl_abap_unit_assert=>assert_equals( act = ls_batch-file_error_code exp = 'PERSISTENCE_FAILURE' ).
    cl_abap_unit_assert=>assert_equals( act = lines( ls_store-objects ) exp = 2 ).
  ENDMETHOD.


  METHOD t10_scale_bulk_and_repeat.
    DATA(ls_store) = zccmc_cl_import_orchestrator=>init_store( ).
    DATA(lv_csv) = |source_system,object_type,object_name,package,description,criticality,business_owner,first_seen,last_seen,findings_as_of
|.
    DO 100 TIMES.
      lv_csv = lv_csv && |DEMO_SYS,PROG,ZPERF_OBJECT_{ sy-index WIDTH = 5 ALIGN = RIGHT PAD = '0' },ZPERF,synthetic perf,LOW,DEMO_PERF,2026-01-01,2026-10-01,2026-10-13
|.
    ENDDO.

    DATA(ls_b1) = zccmc_cl_import_orchestrator=>import_csv_file(
      EXPORTING iv_file_kind = 'objects' iv_csv_content = lv_csv
      CHANGING  cs_store     = ls_store ).
    cl_abap_unit_assert=>assert_equals( act = ls_b1-inserted_count exp = 100 ).
    cl_abap_unit_assert=>assert_equals( act = lines( ls_store-objects ) exp = 100 ).

    DATA(ls_b2) = zccmc_cl_import_orchestrator=>import_csv_file(
      EXPORTING iv_file_kind = 'objects' iv_csv_content = lv_csv
      CHANGING  cs_store     = ls_store ).
    cl_abap_unit_assert=>assert_equals( act = ls_b2-unchanged_count exp = 100 ).
    cl_abap_unit_assert=>assert_equals( act = lines( ls_store-objects ) exp = 100 ).
  ENDMETHOD.

ENDCLASS.
