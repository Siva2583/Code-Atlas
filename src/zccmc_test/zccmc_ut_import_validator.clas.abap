"! ABAP Unit tests for ZCCMC_CL_CSV_ADAPTER & ZCCMC_CL_IMPORT_VALIDATOR (Member 1 — M1-D04-T01).
"! DEMO / SYNTHETIC data only.
"!
"! STATUS: written without live ADT execution in the shared trial tenant (non-$TMP package
"! creation remains blocked/unverified; see docs/feasibility-note.md F-02 and docs/limitations.md).
"! Run in ADT (Ctrl+Shift+F10) once package ZCCMC is provisioned, and cross-check offline via:
"!   python3 tools/m1_import_oracle.py --report docs/m1-golden-import-results.md
"!
"! Covers 12 parser & validator scenarios (IMP-V01..IMP-V12):
"! - T01: All four template headers (objects, usage, findings, dependencies) match contract v0.3.
"! - T02: Header mismatch (wrong column name, wrong order, missing/extra column) -> HEADER_MISMATCH.
"! - T03: Header-only objects_empty.csv -> EMPTY_FILE, zero valid rows.
"! - T04: RFC 4180 quoted field with embedded comma and escaped double quotes -> preserved verbatim.
"! - T05: Leading UTF-8 BOM and CRLF/LF line endings parse without header drift.
"! - T06: Unclosed quote / unescaped quote mid-field -> MALFORMED_CSV with 1-based record number.
"! - T07: Wrong column width on data row -> COLUMN_COUNT_MISMATCH.
"! - T08: Intra-file duplicate business keys (objects_duplicate_keys.csv) -> BOTH rows rejected (DUPLICATE_KEY).
"! - T09: Calendar date validation (usage_malformed_date.csv 2026-02-30, non-leap 2026-02-29 rejected; leap 2024-02-29 accepted).
"! - T10: Enum and required-field rules (blank criticality -> UNKNOWN; blank severity -> MISSING_REQUIRED_FIELD; bad enum -> INVALID_ENUM).
"! - T11: Integer and negative run_count rules (INVALID_INTEGER vs NEGATIVE_RUN_COUNT).
"! - T12: Key trimming and uppercase normalization while preserving free-text descriptions/messages.
CLASS zccmc_ut_import_validator DEFINITION
  PUBLIC
  FINAL
  FOR TESTING
  RISK LEVEL HARMLESS
  DURATION SHORT.

  PRIVATE SECTION.
    METHODS:
      t01_four_template_headers_pass FOR TESTING,
      t02_header_mismatch_rejected   FOR TESTING,
      t03_empty_file_rejected        FOR TESTING,
      t04_rfc4180_quotes_and_commas  FOR TESTING,
      t05_utf8_bom_and_crlf_handled  FOR TESTING,
      t06_malformed_csv_unclosed_q   FOR TESTING,
      t07_column_count_mismatch      FOR TESTING,
      t08_duplicate_keys_both_reject FOR TESTING,
      t09_malformed_and_calendar_dt  FOR TESTING,
      t10_enum_and_criticality_rules FOR TESTING,
      t11_integer_and_neg_run_count  FOR TESTING,
      t12_key_normalization_trimming FOR TESTING.
ENDCLASS.



CLASS zccmc_ut_import_validator IMPLEMENTATION.

  METHOD t01_four_template_headers_pass.
    DATA(ls_obj_p) = zccmc_cl_csv_adapter=>parse_csv_string(
      iv_file_kind   = 'objects'
      iv_csv_content = |source_system,object_type,object_name,package,description,criticality,business_owner,first_seen,last_seen,findings_as_of
| ).
    cl_abap_unit_assert=>assert_true( ls_obj_p-ok ).
    cl_abap_unit_assert=>assert_true(
      zccmc_cl_import_validator=>validate_header( iv_file_kind = 'objects' it_header = ls_obj_p-header ) ).

    DATA(ls_usg_p) = zccmc_cl_csv_adapter=>parse_csv_string(
      iv_file_kind   = 'usage'
      iv_csv_content = |source_system,object_type,object_name,period_start,period_end,last_executed,run_count,evidence_source,evidence_as_of
| ).
    cl_abap_unit_assert=>assert_true(
      zccmc_cl_import_validator=>validate_header( iv_file_kind = 'usage' it_header = ls_usg_p-header ) ).

    DATA(ls_fnd_p) = zccmc_cl_csv_adapter=>parse_csv_string(
      iv_file_kind   = 'findings'
      iv_csv_content = |source_system,object_type,object_name,finding_id,check_id,category,severity,message,source_reference
| ).
    cl_abap_unit_assert=>assert_true(
      zccmc_cl_import_validator=>validate_header( iv_file_kind = 'findings' it_header = ls_fnd_p-header ) ).

    DATA(ls_dep_p) = zccmc_cl_csv_adapter=>parse_csv_string(
      iv_file_kind   = 'dependencies'
      iv_csv_content = |source_system,from_type,from_name,to_type,to_name,dependency_type,evidence_source
| ).
    cl_abap_unit_assert=>assert_true(
      zccmc_cl_import_validator=>validate_header( iv_file_kind = 'dependencies' it_header = ls_dep_p-header ) ).
  ENDMETHOD.


  METHOD t02_header_mismatch_rejected.
    " Missing findings_as_of column (v0.1 header) must fail against v0.3 contract
    DATA(ls_parsed) = zccmc_cl_csv_adapter=>parse_csv_string(
      iv_file_kind   = 'objects'
      iv_csv_content = |source_system,object_type,object_name,package,description,criticality,business_owner,first_seen,last_seen
| ).
    DATA(ls_val) = zccmc_cl_import_validator=>validate_parsed_file( ls_parsed ).
    cl_abap_unit_assert=>assert_false( ls_val-ok ).
    cl_abap_unit_assert=>assert_equals(
      act = ls_val-file_error_code
      exp = zccmc_if_source_adapter=>c_error-header_mismatch ).
  ENDMETHOD.


  METHOD t03_empty_file_rejected.
    " Fixture: data/sample-synthetic/edge-cases/objects_empty.csv
    DATA(ls_parsed) = zccmc_cl_csv_adapter=>parse_csv_string(
      iv_file_kind   = 'objects'
      iv_csv_content = |source_system,object_type,object_name,package,description,criticality,business_owner,first_seen,last_seen,findings_as_of
| ).
    DATA(ls_val) = zccmc_cl_import_validator=>validate_parsed_file( ls_parsed ).
    cl_abap_unit_assert=>assert_false( ls_val-ok ).
    cl_abap_unit_assert=>assert_equals(
      act = ls_val-file_error_code
      exp = zccmc_if_source_adapter=>c_error-empty_file ).
    cl_abap_unit_assert=>assert_equals( act = lines( ls_val-valid_objects ) exp = 0 ).
  ENDMETHOD.


  METHOD t04_rfc4180_quotes_and_commas.
    " Fixture: data/sample-synthetic/edge-cases/findings_quoted_fields.csv
    DATA(lv_csv) =
      |source_system,object_type,object_name,finding_id,check_id,category,severity,message,source_reference
| &&
      |DEMO_SYS,PROG,ZSD_OPEN_ORDERS_RPT,F900,DEMO_CHK_QUOTED,API,LOW,"DEMO quoted, comma and ""quote"" fixture",DEMO_EDGE_QUOTED
|.
    DATA(ls_parsed) = zccmc_cl_csv_adapter=>parse_csv_string( iv_file_kind = 'findings' iv_csv_content = lv_csv ).
    DATA(ls_val)    = zccmc_cl_import_validator=>validate_parsed_file( ls_parsed ).
    cl_abap_unit_assert=>assert_true( ls_val-ok ).
    cl_abap_unit_assert=>assert_equals( act = lines( ls_val-valid_findings ) exp = 1 ).
    cl_abap_unit_assert=>assert_equals(
      act = ls_val-valid_findings[ 1 ]-message
      exp = `DEMO quoted, comma and "quote" fixture` ).
  ENDMETHOD.


  METHOD t05_utf8_bom_and_crlf_handled.
    DATA(lv_bom) = cl_abap_conv_in_ce=>uccpi( 65279 ).
    DATA(lv_csv) =
      lv_bom &&
      |source_system,from_type,from_name,to_type,to_name,dependency_type,evidence_source
| &&
      |DEMO_SYS,PROG,ZSD_OPEN_ORDERS_RPT,CLAS,ZCL_PRICING_HELPER,CALL,DEMO
|.
    DATA(ls_parsed) = zccmc_cl_csv_adapter=>parse_csv_string( iv_file_kind = 'dependencies' iv_csv_content = lv_csv ).
    DATA(ls_val)    = zccmc_cl_import_validator=>validate_parsed_file( ls_parsed ).
    cl_abap_unit_assert=>assert_true( ls_val-ok ).
    cl_abap_unit_assert=>assert_equals( act = lines( ls_val-valid_deps ) exp = 1 ).
  ENDMETHOD.


  METHOD t06_malformed_csv_unclosed_q.
    DATA(lv_csv) =
      |source_system,object_type,object_name,finding_id,check_id,category,severity,message,source_reference
| &&
      |DEMO_SYS,PROG,ZSD_OPEN_ORDERS_RPT,F901,CHK1,API,LOW,"unclosed quote,REF1
|.
    DATA(ls_parsed) = zccmc_cl_csv_adapter=>parse_csv_string( iv_file_kind = 'findings' iv_csv_content = lv_csv ).
    cl_abap_unit_assert=>assert_false( ls_parsed-ok ).
    cl_abap_unit_assert=>assert_equals(
      act = ls_parsed-error_code
      exp = zccmc_if_source_adapter=>c_error-malformed_csv ).
  ENDMETHOD.


  METHOD t07_column_count_mismatch.
    DATA(lv_csv) =
      |source_system,from_type,from_name,to_type,to_name,dependency_type,evidence_source
| &&
      |DEMO_SYS,PROG,ZSD_OPEN_ORDERS_RPT,CLAS,ZCL_PRICING_HELPER,CALL
|.
    DATA(ls_parsed) = zccmc_cl_csv_adapter=>parse_csv_string( iv_file_kind = 'dependencies' iv_csv_content = lv_csv ).
    DATA(ls_val)    = zccmc_cl_import_validator=>validate_parsed_file( ls_parsed ).
    cl_abap_unit_assert=>assert_true( ls_val-ok ).
    cl_abap_unit_assert=>assert_equals( act = lines( ls_val-valid_deps ) exp = 0 ).
    cl_abap_unit_assert=>assert_equals( act = lines( ls_val-row_errors ) exp = 1 ).
    cl_abap_unit_assert=>assert_equals(
      act = ls_val-row_errors[ 1 ]-error_code
      exp = zccmc_if_source_adapter=>c_error-column_count_mismatch ).
  ENDMETHOD.


  METHOD t08_duplicate_keys_both_reject.
    " Fixture: data/sample-synthetic/edge-cases/objects_duplicate_keys.csv
    DATA(lv_csv) =
      |source_system,object_type,object_name,package,description,criticality,business_owner,first_seen,last_seen,findings_as_of
| &&
      |DEMO_SYS,PROG,ZDEMO_DUPLICATE,ZDEMO,DEMO duplicate key first row,LOW,DEMO_OWNER,2026-01-01,2026-10-01,2026-10-13
| &&
      |DEMO_SYS,PROG,ZDEMO_DUPLICATE,ZDEMO,DEMO duplicate key corrected row,MEDIUM,DEMO_OWNER,2026-01-01,2026-10-01,2026-10-13
|.
    DATA(ls_parsed) = zccmc_cl_csv_adapter=>parse_csv_string( iv_file_kind = 'objects' iv_csv_content = lv_csv ).
    DATA(ls_val)    = zccmc_cl_import_validator=>validate_parsed_file( ls_parsed ).
    cl_abap_unit_assert=>assert_true( ls_val-ok ).
    cl_abap_unit_assert=>assert_equals( act = lines( ls_val-valid_objects ) exp = 0 ).
    cl_abap_unit_assert=>assert_equals( act = lines( ls_val-row_errors ) exp = 2 ).
    cl_abap_unit_assert=>assert_equals(
      act = ls_val-row_errors[ 1 ]-error_code
      exp = zccmc_if_source_adapter=>c_error-duplicate_key ).
    cl_abap_unit_assert=>assert_equals( act = ls_val-row_errors[ 1 ]-source_record exp = 2 ).
    cl_abap_unit_assert=>assert_equals(
      act = ls_val-row_errors[ 2 ]-error_code
      exp = zccmc_if_source_adapter=>c_error-duplicate_key ).
    cl_abap_unit_assert=>assert_equals( act = ls_val-row_errors[ 2 ]-source_record exp = 3 ).
  ENDMETHOD.


  METHOD t09_malformed_and_calendar_dt.
    " Fixture: data/sample-synthetic/edge-cases/usage_malformed_date.csv
    DATA(lv_csv) =
      |source_system,object_type,object_name,period_start,period_end,last_executed,run_count,evidence_source,evidence_as_of
| &&
      |DEMO_SYS,PROG,ZSD_OPEN_ORDERS_RPT,2026-02-30,2026-10-13,,0,DEMO,2026-10-13
|.
    DATA(ls_parsed) = zccmc_cl_csv_adapter=>parse_csv_string( iv_file_kind = 'usage' iv_csv_content = lv_csv ).
    DATA(ls_val)    = zccmc_cl_import_validator=>validate_parsed_file( ls_parsed ).
    cl_abap_unit_assert=>assert_equals( act = lines( ls_val-valid_usages ) exp = 0 ).
    cl_abap_unit_assert=>assert_equals( act = lines( ls_val-row_errors ) exp = 1 ).
    cl_abap_unit_assert=>assert_equals(
      act = ls_val-row_errors[ 1 ]-error_code
      exp = zccmc_if_source_adapter=>c_error-invalid_date ).
    cl_abap_unit_assert=>assert_equals(
      act = ls_val-row_errors[ 1 ]-field_name
      exp = 'period_start' ).

    " Leap year 2024-02-29 is valid; non-leap 2026-02-29 is invalid
    cl_abap_unit_assert=>assert_true( zccmc_cl_import_validator=>is_valid_iso_date( iv_text = '2024-02-29' ) ).
    cl_abap_unit_assert=>assert_false( zccmc_cl_import_validator=>is_valid_iso_date( iv_text = '2026-02-29' ) ).
  ENDMETHOD.


  METHOD t10_enum_and_criticality_rules.
    " Blank criticality normalizes to UNKNOWN; invalid criticality -> INVALID_ENUM
    DATA(lv_obj_csv) =
      |source_system,object_type,object_name,package,description,criticality,business_owner,first_seen,last_seen,findings_as_of
| &&
      |DEMO_SYS,PROG,ZOBJ_BLANK_CRIT,ZPKG,desc,,OWNER,2025-01-01,2026-01-01,2026-10-13
| &&
      |DEMO_SYS,PROG,ZOBJ_BAD_CRIT,ZPKG,desc,CRITICAL,OWNER,2025-01-01,2026-01-01,2026-10-13
|.
    DATA(ls_obj_val) = zccmc_cl_import_validator=>validate_parsed_file(
      zccmc_cl_csv_adapter=>parse_csv_string( iv_file_kind = 'objects' iv_csv_content = lv_obj_csv ) ).
    cl_abap_unit_assert=>assert_equals( act = lines( ls_obj_val-valid_objects ) exp = 1 ).
    cl_abap_unit_assert=>assert_equals( act = ls_obj_val-valid_objects[ 1 ]-criticality exp = 'UNKNOWN' ).
    cl_abap_unit_assert=>assert_equals( act = ls_obj_val-row_errors[ 1 ]-error_code exp = zccmc_if_source_adapter=>c_error-invalid_enum ).

    " Blank severity -> MISSING_REQUIRED_FIELD
    DATA(lv_fnd_csv) =
      |source_system,object_type,object_name,finding_id,check_id,category,severity,message,source_reference
| &&
      |DEMO_SYS,PROG,ZSD_OPEN_ORDERS_RPT,F01,C01,API,,missing severity,REF1
|.
    DATA(ls_fnd_val) = zccmc_cl_import_validator=>validate_parsed_file(
      zccmc_cl_csv_adapter=>parse_csv_string( iv_file_kind = 'findings' iv_csv_content = lv_fnd_csv ) ).
    cl_abap_unit_assert=>assert_equals( act = ls_fnd_val-row_errors[ 1 ]-error_code exp = zccmc_if_source_adapter=>c_error-missing_required_field ).
    cl_abap_unit_assert=>assert_equals( act = ls_fnd_val-row_errors[ 1 ]-field_name exp = 'severity' ).
  ENDMETHOD.


  METHOD t11_integer_and_neg_run_count.
    DATA(lv_usg_csv) =
      |source_system,object_type,object_name,period_start,period_end,last_executed,run_count,evidence_source,evidence_as_of
| &&
      |DEMO_SYS,PROG,ZSD_OPEN_ORDERS_RPT,2025-10-13,2026-10-13,2026-09-25,-5,DEMO,2026-10-13
| &&
      |DEMO_SYS,CLAS,ZCL_PRICING_HELPER,2025-10-13,2026-10-13,2026-09-25,12.5,DEMO,2026-10-13
|.
    DATA(ls_usg_val) = zccmc_cl_import_validator=>validate_parsed_file(
      zccmc_cl_csv_adapter=>parse_csv_string( iv_file_kind = 'usage' iv_csv_content = lv_usg_csv ) ).
    cl_abap_unit_assert=>assert_equals( act = lines( ls_usg_val-valid_usages ) exp = 0 ).
    cl_abap_unit_assert=>assert_equals( act = lines( ls_usg_val-row_errors ) exp = 2 ).
    cl_abap_unit_assert=>assert_equals( act = ls_usg_val-row_errors[ 1 ]-error_code exp = zccmc_if_source_adapter=>c_error-negative_run_count ).
    cl_abap_unit_assert=>assert_equals( act = ls_usg_val-row_errors[ 2 ]-error_code exp = zccmc_if_source_adapter=>c_error-invalid_integer ).
  ENDMETHOD.


  METHOD t12_key_normalization_trimming.
    DATA(lv_csv) =
      |source_system,object_type,object_name,package,description,criticality,business_owner,first_seen,last_seen,findings_as_of
| &&
      | demo_sys , prog , zsd_open_orders_rpt , ZSD_REPORTS , Mixed Case Description , high , DEMO_OWNER_SD ,2019-03-11,2026-09-25,2026-10-13
|.
    DATA(ls_val) = zccmc_cl_import_validator=>validate_parsed_file(
      zccmc_cl_csv_adapter=>parse_csv_string( iv_file_kind = 'objects' iv_csv_content = lv_csv ) ).
    cl_abap_unit_assert=>assert_equals( act = lines( ls_val-valid_objects ) exp = 1 ).
    cl_abap_unit_assert=>assert_equals( act = ls_val-valid_objects[ 1 ]-business_key exp = 'DEMO_SYS|PROG|ZSD_OPEN_ORDERS_RPT' ).
    cl_abap_unit_assert=>assert_equals( act = ls_val-valid_objects[ 1 ]-criticality  exp = 'HIGH' ).
    cl_abap_unit_assert=>assert_equals( act = ls_val-valid_objects[ 1 ]-description  exp = 'Mixed Case Description' ).
  ENDMETHOD.

ENDCLASS.
