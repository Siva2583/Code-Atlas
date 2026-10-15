"! Schema, type, date, enum, and intra-file duplicate-key validator (Member 1 — M1-D04-T01).
"!
"! DEMO / SYNTHETIC data only. Pure validation class with zero persistence side effects.
"! Enforces docs/data-contract.md (v0.3) and docs/import-design.md:
"! - Exact ordered header check per file kind (HEADER_MISMATCH).
"! - Header-only file rejection (EMPTY_FILE).
"! - Exact column-count check per record (COLUMN_COUNT_MISMATCH).
"! - Trimming and uppercase normalization for business keys and enum tokens.
"! - Blank criticality normalizes to UNKNOWN; blank severity is rejected (MISSING_REQUIRED_FIELD).
"! - Strict ISO calendar date validation YYYY-MM-DD including leap-year rules (INVALID_DATE).
"! - Non-negative integer validation for run_count (INVALID_INTEGER / NEGATIVE_RUN_COUNT).
"! - Intra-file duplicate business-key detection rejecting ALL colliding occurrences (DUPLICATE_KEY)
"!   so row ordering inside a file never picks a winner.
CLASS zccmc_cl_import_validator DEFINITION
  PUBLIC
  FINAL
  CREATE PUBLIC.

  PUBLIC SECTION.
    CLASS-METHODS get_expected_header
      IMPORTING
        iv_file_kind      TYPE string
      RETURNING
        VALUE(rt_columns) TYPE zccmc_if_source_adapter=>ty_string_tab.

    CLASS-METHODS validate_header
      IMPORTING
        iv_file_kind    TYPE string
        it_header       TYPE zccmc_if_source_adapter=>ty_string_tab
      EXPORTING
        ev_error_code   TYPE string
        ev_error_msg    TYPE string
      RETURNING
        VALUE(rv_valid) TYPE abap_boolean.

    CLASS-METHODS is_valid_iso_date
      IMPORTING
        iv_text         TYPE string
        iv_required     TYPE abap_boolean DEFAULT abap_false
      EXPORTING
        ev_date         TYPE d
        ev_error_code   TYPE string
      RETURNING
        VALUE(rv_valid) TYPE abap_boolean.

    CLASS-METHODS parse_non_negative_int
      IMPORTING
        iv_text         TYPE string
      EXPORTING
        ev_value        TYPE i
        ev_error_code   TYPE string
      RETURNING
        VALUE(rv_valid) TYPE abap_boolean.

    CLASS-METHODS validate_parsed_file
      IMPORTING
        is_parsed        TYPE zccmc_if_source_adapter=>ty_parse_result
      RETURNING
        VALUE(rs_result) TYPE zccmc_if_source_adapter=>ty_validation_result.

    CLASS-METHODS compute_row_digest
      IMPORTING
        iv_canonical     TYPE string
      RETURNING
        VALUE(rv_sha256) TYPE string.

  PRIVATE SECTION.
    CLASS-METHODS norm_upper
      IMPORTING iv_val        TYPE string
      RETURNING VALUE(rv_out) TYPE string.

    CLASS-METHODS norm_trim
      IMPORTING iv_val        TYPE string
      RETURNING VALUE(rv_out) TYPE string.

ENDCLASS.



CLASS zccmc_cl_import_validator IMPLEMENTATION.

  METHOD norm_upper.
    rv_out = to_upper( condense( iv_val ) ).
  ENDMETHOD.


  METHOD norm_trim.
    rv_out = condense( iv_val ).
    " Strip leading/trailing spaces only while preserving internal spaces in free text
    SHIFT rv_out LEFT DELETING LEADING space.
    SHIFT rv_out RIGHT DELETING TRAILING space.
  ENDMETHOD.


  METHOD compute_row_digest.
    rv_sha256 = zccmc_cl_csv_adapter=>compute_digest( iv_canonical ).
  ENDMETHOD.


  METHOD get_expected_header.
    DATA(lv_kind) = to_lower( condense( iv_file_kind ) ).
    CASE lv_kind.
      WHEN zccmc_if_source_adapter=>c_file_kind-objects.
        rt_columns = VALUE #(
          ( `source_system` ) ( `object_type` ) ( `object_name` ) ( `package` )
          ( `description` ) ( `criticality` ) ( `business_owner` )
          ( `first_seen` ) ( `last_seen` ) ( `findings_as_of` ) ).
      WHEN zccmc_if_source_adapter=>c_file_kind-usage.
        rt_columns = VALUE #(
          ( `source_system` ) ( `object_type` ) ( `object_name` )
          ( `period_start` ) ( `period_end` ) ( `last_executed` )
          ( `run_count` ) ( `evidence_source` ) ( `evidence_as_of` ) ).
      WHEN zccmc_if_source_adapter=>c_file_kind-findings.
        rt_columns = VALUE #(
          ( `source_system` ) ( `object_type` ) ( `object_name` )
          ( `finding_id` ) ( `check_id` ) ( `category` )
          ( `severity` ) ( `message` ) ( `source_reference` ) ).
      WHEN zccmc_if_source_adapter=>c_file_kind-dependencies.
        rt_columns = VALUE #(
          ( `source_system` ) ( `from_type` ) ( `from_name` )
          ( `to_type` ) ( `to_name` ) ( `dependency_type` ) ( `evidence_source` ) ).
    ENDCASE.
  ENDMETHOD.


  METHOD validate_header.
    CLEAR: ev_error_code, ev_error_msg.
    DATA(lt_expected) = get_expected_header( iv_file_kind ).
    IF lines( lt_expected ) = 0.
      rv_valid      = abap_false.
      ev_error_code = zccmc_if_source_adapter=>c_error-header_mismatch.
      ev_error_msg  = |Unsupported file kind '{ iv_file_kind }'.|.
      RETURN.
    ENDIF.

    IF lines( it_header ) <> lines( lt_expected ).
      rv_valid      = abap_false.
      ev_error_code = zccmc_if_source_adapter=>c_error-header_mismatch.
      ev_error_msg  = |Header column count { lines( it_header ) } does not match expected { lines( lt_expected ) } for { iv_file_kind }.|.
      RETURN.
    ENDIF.

    LOOP AT lt_expected INTO DATA(lv_exp_col).
      DATA(lv_idx) = sy-tabix.
      DATA(lv_act_col) = norm_trim( it_header[ lv_idx ] ).
      IF lv_act_col <> lv_exp_col.
        rv_valid      = abap_false.
        ev_error_code = zccmc_if_source_adapter=>c_error-header_mismatch.
        ev_error_msg  = |Header column { lv_idx } is '{ lv_act_col }', expected '{ lv_exp_col }'.|.
        RETURN.
      ENDIF.
    ENDLOOP.

    rv_valid = abap_true.
  ENDMETHOD.


  METHOD is_valid_iso_date.
    CLEAR: ev_date, ev_error_code.
    DATA(lv_str) = condense( iv_text ).
    IF lv_str = ''.
      IF iv_required = abap_true.
        rv_valid      = abap_false.
        ev_error_code = zccmc_if_source_adapter=>c_error-missing_required_field.
      ELSE.
        rv_valid = abap_true.
      ENDIF.
      RETURN.
    ENDIF.

    IF strlen( lv_str ) <> 10.
      rv_valid      = abap_false.
      ev_error_code = zccmc_if_source_adapter=>c_error-invalid_date.
      RETURN.
    ENDIF.

    IF substring( val = lv_str off = 4 len = 1 ) <> '-' OR
       substring( val = lv_str off = 7 len = 1 ) <> '-'.
      rv_valid      = abap_false.
      ev_error_code = zccmc_if_source_adapter=>c_error-invalid_date.
      RETURN.
    ENDIF.

    DATA(lv_y_str) = substring( val = lv_str off = 0 len = 4 ).
    DATA(lv_m_str) = substring( val = lv_str off = 5 len = 2 ).
    DATA(lv_d_str) = substring( val = lv_str off = 8 len = 2 ).

    IF lv_y_str CN '0123456789' OR lv_m_str CN '0123456789' OR lv_d_str CN '0123456789'.
      rv_valid      = abap_false.
      ev_error_code = zccmc_if_source_adapter=>c_error-invalid_date.
      RETURN.
    ENDIF.

    DATA(lv_year)  = CONV i( lv_y_str ).
    DATA(lv_month) = CONV i( lv_m_str ).
    DATA(lv_day)   = CONV i( lv_d_str ).

    IF lv_year < 1900 OR lv_year > 9999 OR lv_month < 1 OR lv_month > 12 OR lv_day < 1.
      rv_valid      = abap_false.
      ev_error_code = zccmc_if_source_adapter=>c_error-invalid_date.
      RETURN.
    ENDIF.

    DATA lv_max_day TYPE i VALUE 31.
    CASE lv_month.
      WHEN 4 OR 6 OR 9 OR 11.
        lv_max_day = 30.
      WHEN 2.
        IF ( lv_year MOD 4 = 0 AND lv_year MOD 100 <> 0 ) OR ( lv_year MOD 400 = 0 ).
          lv_max_day = 29.
        ELSE.
          lv_max_day = 28.
        ENDIF.
    ENDCASE.

    IF lv_day > lv_max_day.
      rv_valid      = abap_false.
      ev_error_code = zccmc_if_source_adapter=>c_error-invalid_date.
      RETURN.
    ENDIF.

    ev_date  = lv_y_str && lv_m_str && lv_d_str.
    rv_valid = abap_true.
  ENDMETHOD.


  METHOD parse_non_negative_int.
    CLEAR: ev_value, ev_error_code.
    DATA(lv_str) = condense( iv_text ).
    IF lv_str = ''.
      rv_valid      = abap_false.
      ev_error_code = zccmc_if_source_adapter=>c_error-missing_required_field.
      RETURN.
    ENDIF.

    IF substring( val = lv_str off = 0 len = 1 ) = '-'.
      DATA(lv_rest) = substring( val = lv_str off = 1 ).
      IF strlen( lv_rest ) > 0 AND lv_rest CO '0123456789'.
        rv_valid      = abap_false.
        ev_error_code = zccmc_if_source_adapter=>c_error-negative_run_count.
        RETURN.
      ENDIF.
    ENDIF.

    IF lv_str CN '0123456789'.
      rv_valid      = abap_false.
      ev_error_code = zccmc_if_source_adapter=>c_error-invalid_integer.
      RETURN.
    ENDIF.

    ev_value = CONV i( lv_str ).
    rv_valid = abap_true.
  ENDMETHOD.


  METHOD validate_parsed_file.
    TYPES:
      BEGIN OF ty_key_count,
        bkey  TYPE string,
        count TYPE i,
      END OF ty_key_count.
    DATA lt_key_counts TYPE STANDARD TABLE OF ty_key_count WITH EMPTY KEY.

    rs_result-file_kind   = is_parsed-file_kind.
    rs_result-file_sha256 = is_parsed-file_sha256.

    IF is_parsed-ok = abap_false.
      rs_result-ok              = abap_false.
      rs_result-file_error_code = is_parsed-error_code.
      rs_result-file_error_msg  = is_parsed-error_message.
      RETURN.
    ENDIF.

    DATA lv_hdr_err TYPE string.
    DATA lv_hdr_msg TYPE string.
    IF validate_header(
         EXPORTING iv_file_kind  = is_parsed-file_kind
                   it_header     = is_parsed-header
         IMPORTING ev_error_code = lv_hdr_err
                   ev_error_msg  = lv_hdr_msg ) = abap_false.
      rs_result-ok              = abap_false.
      rs_result-file_error_code = lv_hdr_err.
      rs_result-file_error_msg  = lv_hdr_msg.
      RETURN.
    ENDIF.

    rs_result-parsed_count = lines( is_parsed-records ).
    IF rs_result-parsed_count = 0.
      rs_result-ok              = abap_false.
      rs_result-file_error_code = zccmc_if_source_adapter=>c_error-empty_file.
      rs_result-file_error_msg  = |File { is_parsed-file_kind }.csv contains a header but zero data records.|.
      RETURN.
    ENDIF.

    DATA(lt_expected_hdr) = get_expected_header( is_parsed-file_kind ).
    DATA(lv_expected_cols) = lines( lt_expected_hdr ).

    " First pass: count business keys across rows of the right column width so all intra-file
    " duplicate occurrences (including the first) are rejected with DUPLICATE_KEY.
    LOOP AT is_parsed-records INTO DATA(ls_pre).
      IF lines( ls_pre-fields ) <> lv_expected_cols.
        CONTINUE.
      ENDIF.
      DATA lv_pre_key TYPE string.
      CASE is_parsed-file_kind.
        WHEN zccmc_if_source_adapter=>c_file_kind-objects.
          lv_pre_key = |{ norm_upper( ls_pre-fields[ 1 ] ) }\|{ norm_upper( ls_pre-fields[ 2 ] ) }\|{ norm_upper( ls_pre-fields[ 3 ] ) }|.
        WHEN zccmc_if_source_adapter=>c_file_kind-usage.
          lv_pre_key = |{ norm_upper( ls_pre-fields[ 1 ] ) }\|{ norm_upper( ls_pre-fields[ 2 ] ) }\|{ norm_upper( ls_pre-fields[ 3 ] ) }\|{ condense( ls_pre-fields[ 4 ] ) }\|{ condense( ls_pre-fields[ 5 ] ) }\|{ norm_upper( ls_pre-fields[ 8 ] ) }|.
        WHEN zccmc_if_source_adapter=>c_file_kind-findings.
          lv_pre_key = |{ norm_upper( ls_pre-fields[ 1 ] ) }\|{ norm_upper( ls_pre-fields[ 2 ] ) }\|{ norm_upper( ls_pre-fields[ 3 ] ) }\|{ norm_trim( ls_pre-fields[ 4 ] ) }\|{ norm_trim( ls_pre-fields[ 5 ] ) }\|{ norm_trim( ls_pre-fields[ 9 ] ) }|.
        WHEN zccmc_if_source_adapter=>c_file_kind-dependencies.
          lv_pre_key = |{ norm_upper( ls_pre-fields[ 1 ] ) }\|{ norm_upper( ls_pre-fields[ 2 ] ) }\|{ norm_upper( ls_pre-fields[ 3 ] ) }\|{ norm_upper( ls_pre-fields[ 4 ] ) }\|{ norm_upper( ls_pre-fields[ 5 ] ) }\|{ norm_upper( ls_pre-fields[ 6 ] ) }\|{ norm_upper( ls_pre-fields[ 7 ] ) }|.
      ENDCASE.

      READ TABLE lt_key_counts ASSIGNING FIELD-SYMBOL(<ls_kc>) WITH KEY bkey = lv_pre_key.
      IF sy-subrc = 0.
        <ls_kc>-count = <ls_kc>-count + 1.
      ELSE.
        APPEND VALUE #( bkey = lv_pre_key count = 1 ) TO lt_key_counts.
      ENDIF.
    ENDLOOP.

    " Second pass: validate each row deterministically
    LOOP AT is_parsed-records INTO DATA(ls_rec).
      IF lines( ls_rec-fields ) <> lv_expected_cols.
        APPEND VALUE #(
          source_record = ls_rec-source_record
          file_kind     = is_parsed-file_kind
          error_code    = zccmc_if_source_adapter=>c_error-column_count_mismatch
          field_name    = 'row'
          message       = |Record { ls_rec-source_record } has { lines( ls_rec-fields ) } columns; expected { lv_expected_cols }.|
        ) TO rs_result-row_errors.
        CONTINUE.
      ENDIF.

      CASE is_parsed-file_kind.
        WHEN zccmc_if_source_adapter=>c_file_kind-objects.
          DATA ls_obj TYPE zccmc_if_source_adapter=>ty_object_row.
          CLEAR ls_obj.
          ls_obj-source_record  = ls_rec-source_record.
          ls_obj-source_system  = norm_upper( ls_rec-fields[ 1 ] ).
          ls_obj-object_type    = norm_upper( ls_rec-fields[ 2 ] ).
          ls_obj-object_name    = norm_upper( ls_rec-fields[ 3 ] ).
          ls_obj-package_name   = norm_trim( ls_rec-fields[ 4 ] ).
          ls_obj-description    = norm_trim( ls_rec-fields[ 5 ] ).
          ls_obj-criticality    = norm_upper( ls_rec-fields[ 6 ] ).
          IF ls_obj-criticality = ''.
            ls_obj-criticality = zccmc_if_source_adapter=>c_criticality-unknown.
          ENDIF.
          ls_obj-business_owner = norm_trim( ls_rec-fields[ 7 ] ).
          ls_obj-business_key   = |{ ls_obj-source_system }\|{ ls_obj-object_type }\|{ ls_obj-object_name }|.

          IF ls_obj-source_system = '' OR ls_obj-object_type = '' OR ls_obj-object_name = ''.
            DATA(lv_miss_fld) = COND string(
              WHEN ls_obj-source_system = '' THEN 'source_system'
              WHEN ls_obj-object_type   = '' THEN 'object_type'
              ELSE 'object_name' ).
            APPEND VALUE #(
              source_record = ls_rec-source_record
              file_kind     = is_parsed-file_kind
              business_key  = ls_obj-business_key
              error_code    = zccmc_if_source_adapter=>c_error-missing_required_field
              field_name    = lv_miss_fld
              message       = |Required identifier '{ lv_miss_fld }' is blank.|
            ) TO rs_result-row_errors.
            CONTINUE.
          ENDIF.

          READ TABLE lt_key_counts INTO DATA(ls_kc_obj) WITH KEY bkey = ls_obj-business_key.
          IF sy-subrc = 0 AND ls_kc_obj-count > 1.
            APPEND VALUE #(
              source_record = ls_rec-source_record
              file_kind     = is_parsed-file_kind
              business_key  = ls_obj-business_key
              error_code    = zccmc_if_source_adapter=>c_error-duplicate_key
              field_name    = 'source_system,object_type,object_name'
              message       = |Duplicate object business key '{ ls_obj-business_key }' within the same file.|
            ) TO rs_result-row_errors.
            CONTINUE.
          ENDIF.

          IF ls_obj-criticality <> 'HIGH' AND ls_obj-criticality <> 'MEDIUM' AND
             ls_obj-criticality <> 'LOW'  AND ls_obj-criticality <> 'UNKNOWN'.
            APPEND VALUE #(
              source_record = ls_rec-source_record
              file_kind     = is_parsed-file_kind
              business_key  = ls_obj-business_key
              error_code    = zccmc_if_source_adapter=>c_error-invalid_enum
              field_name    = 'criticality'
              message       = |Invalid criticality '{ ls_obj-criticality }'.|
            ) TO rs_result-row_errors.
            CONTINUE.
          ENDIF.

          DATA lv_dt_err TYPE string.
          IF is_valid_iso_date( EXPORTING iv_text = ls_rec-fields[ 8 ] IMPORTING ev_date = ls_obj-first_seen ev_error_code = lv_dt_err ) = abap_false.
            APPEND VALUE #( source_record = ls_rec-source_record file_kind = is_parsed-file_kind business_key = ls_obj-business_key
                            error_code = lv_dt_err field_name = 'first_seen' message = |Invalid date in first_seen: '{ ls_rec-fields[ 8 ] }'.| ) TO rs_result-row_errors.
            CONTINUE.
          ENDIF.
          IF is_valid_iso_date( EXPORTING iv_text = ls_rec-fields[ 9 ] IMPORTING ev_date = ls_obj-last_seen ev_error_code = lv_dt_err ) = abap_false.
            APPEND VALUE #( source_record = ls_rec-source_record file_kind = is_parsed-file_kind business_key = ls_obj-business_key
                            error_code = lv_dt_err field_name = 'last_seen' message = |Invalid date in last_seen: '{ ls_rec-fields[ 9 ] }'.| ) TO rs_result-row_errors.
            CONTINUE.
          ENDIF.
          IF is_valid_iso_date( EXPORTING iv_text = ls_rec-fields[ 10 ] IMPORTING ev_date = ls_obj-findings_as_of ev_error_code = lv_dt_err ) = abap_false.
            APPEND VALUE #( source_record = ls_rec-source_record file_kind = is_parsed-file_kind business_key = ls_obj-business_key
                            error_code = lv_dt_err field_name = 'findings_as_of' message = |Invalid date in findings_as_of: '{ ls_rec-fields[ 10 ] }'.| ) TO rs_result-row_errors.
            CONTINUE.
          ENDIF.

          ls_obj-row_sha256 = compute_row_digest(
            |{ ls_obj-business_key }\|{ ls_obj-package_name }\|{ ls_obj-description }\|{ ls_obj-criticality }\|{ ls_obj-business_owner }\|{ ls_obj-first_seen }\|{ ls_obj-last_seen }\|{ ls_obj-findings_as_of }| ).
          APPEND ls_obj TO rs_result-valid_objects.

        WHEN zccmc_if_source_adapter=>c_file_kind-usage.
          DATA ls_usg TYPE zccmc_if_source_adapter=>ty_usage_row.
          CLEAR ls_usg.
          ls_usg-source_record   = ls_rec-source_record.
          ls_usg-source_system   = norm_upper( ls_rec-fields[ 1 ] ).
          ls_usg-object_type     = norm_upper( ls_rec-fields[ 2 ] ).
          ls_usg-object_name     = norm_upper( ls_rec-fields[ 3 ] ).
          ls_usg-evidence_source = norm_upper( ls_rec-fields[ 8 ] ).
          ls_usg-business_key    = |{ ls_usg-source_system }\|{ ls_usg-object_type }\|{ ls_usg-object_name }\|{ condense( ls_rec-fields[ 4 ] ) }\|{ condense( ls_rec-fields[ 5 ] ) }\|{ ls_usg-evidence_source }|.

          IF ls_usg-source_system = '' OR ls_usg-object_type = '' OR ls_usg-object_name = '' OR
             condense( ls_rec-fields[ 4 ] ) = '' OR condense( ls_rec-fields[ 5 ] ) = '' OR
             condense( ls_rec-fields[ 7 ] ) = '' OR ls_usg-evidence_source = '' OR condense( ls_rec-fields[ 9 ] ) = ''.
            DATA(lv_usg_miss) = COND string(
              WHEN ls_usg-source_system = ''           THEN 'source_system'
              WHEN ls_usg-object_type = ''             THEN 'object_type'
              WHEN ls_usg-object_name = ''             THEN 'object_name'
              WHEN condense( ls_rec-fields[ 4 ] ) = '' THEN 'period_start'
              WHEN condense( ls_rec-fields[ 5 ] ) = '' THEN 'period_end'
              WHEN condense( ls_rec-fields[ 7 ] ) = '' THEN 'run_count'
              WHEN ls_usg-evidence_source = ''         THEN 'evidence_source'
              ELSE 'evidence_as_of' ).
            APPEND VALUE #( source_record = ls_rec-source_record file_kind = is_parsed-file_kind business_key = ls_usg-business_key
                            error_code = zccmc_if_source_adapter=>c_error-missing_required_field field_name = lv_usg_miss
                            message = |Required field '{ lv_usg_miss }' is blank.| ) TO rs_result-row_errors.
            CONTINUE.
          ENDIF.

          READ TABLE lt_key_counts INTO DATA(ls_kc_usg) WITH KEY bkey = ls_usg-business_key.
          IF sy-subrc = 0 AND ls_kc_usg-count > 1.
            APPEND VALUE #( source_record = ls_rec-source_record file_kind = is_parsed-file_kind business_key = ls_usg-business_key
                            error_code = zccmc_if_source_adapter=>c_error-duplicate_key field_name = 'usage_key'
                            message = |Duplicate usage business key '{ ls_usg-business_key }' within the same file.| ) TO rs_result-row_errors.
            CONTINUE.
          ENDIF.

          IF is_valid_iso_date( EXPORTING iv_text = ls_rec-fields[ 4 ] iv_required = abap_true IMPORTING ev_date = ls_usg-period_start ev_error_code = lv_dt_err ) = abap_false.
            APPEND VALUE #( source_record = ls_rec-source_record file_kind = is_parsed-file_kind business_key = ls_usg-business_key
                            error_code = lv_dt_err field_name = 'period_start' message = |Invalid date in period_start: '{ ls_rec-fields[ 4 ] }'.| ) TO rs_result-row_errors.
            CONTINUE.
          ENDIF.
          IF is_valid_iso_date( EXPORTING iv_text = ls_rec-fields[ 5 ] iv_required = abap_true IMPORTING ev_date = ls_usg-period_end ev_error_code = lv_dt_err ) = abap_false.
            APPEND VALUE #( source_record = ls_rec-source_record file_kind = is_parsed-file_kind business_key = ls_usg-business_key
                            error_code = lv_dt_err field_name = 'period_end' message = |Invalid date in period_end: '{ ls_rec-fields[ 5 ] }'.| ) TO rs_result-row_errors.
            CONTINUE.
          ENDIF.
          IF is_valid_iso_date( EXPORTING iv_text = ls_rec-fields[ 6 ] iv_required = abap_false IMPORTING ev_date = ls_usg-last_executed ev_error_code = lv_dt_err ) = abap_false.
            APPEND VALUE #( source_record = ls_rec-source_record file_kind = is_parsed-file_kind business_key = ls_usg-business_key
                            error_code = lv_dt_err field_name = 'last_executed' message = |Invalid date in last_executed: '{ ls_rec-fields[ 6 ] }'.| ) TO rs_result-row_errors.
            CONTINUE.
          ENDIF.

          DATA lv_int_err TYPE string.
          IF parse_non_negative_int( EXPORTING iv_text = ls_rec-fields[ 7 ] IMPORTING ev_value = ls_usg-run_count ev_error_code = lv_int_err ) = abap_false.
            APPEND VALUE #( source_record = ls_rec-source_record file_kind = is_parsed-file_kind business_key = ls_usg-business_key
                            error_code = lv_int_err field_name = 'run_count' message = |Invalid run_count: '{ ls_rec-fields[ 7 ] }'.| ) TO rs_result-row_errors.
            CONTINUE.
          ENDIF.

          IF ls_usg-evidence_source <> 'DEMO' AND ls_usg-evidence_source <> 'CSV_EXPORT'.
            APPEND VALUE #( source_record = ls_rec-source_record file_kind = is_parsed-file_kind business_key = ls_usg-business_key
                            error_code = zccmc_if_source_adapter=>c_error-invalid_enum field_name = 'evidence_source'
                            message = |Unsupported evidence_source '{ ls_usg-evidence_source }'.| ) TO rs_result-row_errors.
            CONTINUE.
          ENDIF.

          IF is_valid_iso_date( EXPORTING iv_text = ls_rec-fields[ 9 ] iv_required = abap_true IMPORTING ev_date = ls_usg-evidence_as_of ev_error_code = lv_dt_err ) = abap_false.
            APPEND VALUE #( source_record = ls_rec-source_record file_kind = is_parsed-file_kind business_key = ls_usg-business_key
                            error_code = lv_dt_err field_name = 'evidence_as_of' message = |Invalid date in evidence_as_of: '{ ls_rec-fields[ 9 ] }'.| ) TO rs_result-row_errors.
            CONTINUE.
          ENDIF.

          ls_usg-row_sha256 = compute_row_digest(
            |{ ls_usg-business_key }\|{ ls_usg-last_executed }\|{ ls_usg-run_count }\|{ ls_usg-evidence_as_of }| ).
          APPEND ls_usg TO rs_result-valid_usages.

        WHEN zccmc_if_source_adapter=>c_file_kind-findings.
          DATA ls_fnd TYPE zccmc_if_source_adapter=>ty_finding_row.
          CLEAR ls_fnd.
          ls_fnd-source_record    = ls_rec-source_record.
          ls_fnd-source_system    = norm_upper( ls_rec-fields[ 1 ] ).
          ls_fnd-object_type      = norm_upper( ls_rec-fields[ 2 ] ).
          ls_fnd-object_name      = norm_upper( ls_rec-fields[ 3 ] ).
          ls_fnd-finding_id       = norm_trim( ls_rec-fields[ 4 ] ).
          ls_fnd-check_id         = norm_trim( ls_rec-fields[ 5 ] ).
          ls_fnd-category         = norm_trim( ls_rec-fields[ 6 ] ).
          ls_fnd-severity         = norm_upper( ls_rec-fields[ 7 ] ).
          ls_fnd-message          = norm_trim( ls_rec-fields[ 8 ] ).
          ls_fnd-source_reference = norm_trim( ls_rec-fields[ 9 ] ).
          ls_fnd-business_key     = |{ ls_fnd-source_system }\|{ ls_fnd-object_type }\|{ ls_fnd-object_name }\|{ ls_fnd-finding_id }\|{ ls_fnd-check_id }\|{ ls_fnd-source_reference }|.

          IF ls_fnd-source_system = '' OR ls_fnd-object_type = '' OR ls_fnd-object_name = '' OR
             ls_fnd-finding_id = '' OR ls_fnd-check_id = '' OR ls_fnd-severity = ''.
            DATA(lv_fnd_miss) = COND string(
              WHEN ls_fnd-source_system = '' THEN 'source_system'
              WHEN ls_fnd-object_type = ''   THEN 'object_type'
              WHEN ls_fnd-object_name = ''   THEN 'object_name'
              WHEN ls_fnd-finding_id = ''    THEN 'finding_id'
              WHEN ls_fnd-check_id = ''      THEN 'check_id'
              ELSE 'severity' ).
            APPEND VALUE #( source_record = ls_rec-source_record file_kind = is_parsed-file_kind business_key = ls_fnd-business_key
                            error_code = zccmc_if_source_adapter=>c_error-missing_required_field field_name = lv_fnd_miss
                            message = |Required field '{ lv_fnd_miss }' is blank.| ) TO rs_result-row_errors.
            CONTINUE.
          ENDIF.

          READ TABLE lt_key_counts INTO DATA(ls_kc_fnd) WITH KEY bkey = ls_fnd-business_key.
          IF sy-subrc = 0 AND ls_kc_fnd-count > 1.
            APPEND VALUE #( source_record = ls_rec-source_record file_kind = is_parsed-file_kind business_key = ls_fnd-business_key
                            error_code = zccmc_if_source_adapter=>c_error-duplicate_key field_name = 'finding_key'
                            message = |Duplicate finding business key '{ ls_fnd-business_key }' within the same file.| ) TO rs_result-row_errors.
            CONTINUE.
          ENDIF.

          IF ls_fnd-severity <> 'HIGH' AND ls_fnd-severity <> 'MEDIUM' AND
             ls_fnd-severity <> 'LOW'  AND ls_fnd-severity <> 'INFO'.
            APPEND VALUE #( source_record = ls_rec-source_record file_kind = is_parsed-file_kind business_key = ls_fnd-business_key
                            error_code = zccmc_if_source_adapter=>c_error-invalid_enum field_name = 'severity'
                            message = |Invalid severity '{ ls_fnd-severity }'.| ) TO rs_result-row_errors.
            CONTINUE.
          ENDIF.

          ls_fnd-row_sha256 = compute_row_digest(
            |{ ls_fnd-business_key }\|{ ls_fnd-category }\|{ ls_fnd-severity }\|{ ls_fnd-message }| ).
          APPEND ls_fnd TO rs_result-valid_findings.

        WHEN zccmc_if_source_adapter=>c_file_kind-dependencies.
          DATA ls_dep TYPE zccmc_if_source_adapter=>ty_dependency_row.
          CLEAR ls_dep.
          ls_dep-source_record   = ls_rec-source_record.
          ls_dep-source_system   = norm_upper( ls_rec-fields[ 1 ] ).
          ls_dep-from_type       = norm_upper( ls_rec-fields[ 2 ] ).
          ls_dep-from_name       = norm_upper( ls_rec-fields[ 3 ] ).
          ls_dep-to_type         = norm_upper( ls_rec-fields[ 4 ] ).
          ls_dep-to_name         = norm_upper( ls_rec-fields[ 5 ] ).
          ls_dep-dependency_type = norm_upper( ls_rec-fields[ 6 ] ).
          ls_dep-evidence_source = norm_upper( ls_rec-fields[ 7 ] ).
          ls_dep-business_key    = |{ ls_dep-source_system }\|{ ls_dep-from_type }\|{ ls_dep-from_name }\|{ ls_dep-to_type }\|{ ls_dep-to_name }\|{ ls_dep-dependency_type }\|{ ls_dep-evidence_source }|.

          IF ls_dep-source_system = '' OR ls_dep-from_type = '' OR ls_dep-from_name = '' OR
             ls_dep-to_type = '' OR ls_dep-to_name = '' OR ls_dep-dependency_type = '' OR ls_dep-evidence_source = ''.
            DATA(lv_dep_miss) = COND string(
              WHEN ls_dep-source_system = ''   THEN 'source_system'
              WHEN ls_dep-from_type = ''       THEN 'from_type'
              WHEN ls_dep-from_name = ''       THEN 'from_name'
              WHEN ls_dep-to_type = ''         THEN 'to_type'
              WHEN ls_dep-to_name = ''         THEN 'to_name'
              WHEN ls_dep-dependency_type = '' THEN 'dependency_type'
              ELSE 'evidence_source' ).
            APPEND VALUE #( source_record = ls_rec-source_record file_kind = is_parsed-file_kind business_key = ls_dep-business_key
                            error_code = zccmc_if_source_adapter=>c_error-missing_required_field field_name = lv_dep_miss
                            message = |Required field '{ lv_dep_miss }' is blank.| ) TO rs_result-row_errors.
            CONTINUE.
          ENDIF.

          READ TABLE lt_key_counts INTO DATA(ls_kc_dep) WITH KEY bkey = ls_dep-business_key.
          IF sy-subrc = 0 AND ls_kc_dep-count > 1.
            APPEND VALUE #( source_record = ls_rec-source_record file_kind = is_parsed-file_kind business_key = ls_dep-business_key
                            error_code = zccmc_if_source_adapter=>c_error-duplicate_key field_name = 'dependency_key'
                            message = |Duplicate dependency business key '{ ls_dep-business_key }' within the same file.| ) TO rs_result-row_errors.
            CONTINUE.
          ENDIF.

          IF ls_dep-evidence_source <> 'DEMO' AND ls_dep-evidence_source <> 'CSV_EXPORT'.
            APPEND VALUE #( source_record = ls_rec-source_record file_kind = is_parsed-file_kind business_key = ls_dep-business_key
                            error_code = zccmc_if_source_adapter=>c_error-invalid_enum field_name = 'evidence_source'
                            message = |Unsupported evidence_source '{ ls_dep-evidence_source }'.| ) TO rs_result-row_errors.
            CONTINUE.
          ENDIF.

          ls_dep-row_sha256 = compute_row_digest( ls_dep-business_key ).
          APPEND ls_dep TO rs_result-valid_deps.
      ENDCASE.
    ENDLOOP.

    rs_result-ok = abap_true.
  ENDMETHOD.

ENDCLASS.
