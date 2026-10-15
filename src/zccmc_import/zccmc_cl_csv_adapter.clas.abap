"! RFC 4180 CSV parser and digest service for the Clean Core Migration Cockpit (Member 1 — M1-D04-T01).
"!
"! DEMO / SYNTHETIC data only. Pure ABAP service with zero RAP or UI dependency.
"! - Strips an optional leading UTF-8 BOM (U+FEFF).
"! - Accepts LF or CRLF record terminators.
"! - Supports RFC 4180 quoted fields containing commas, embedded newlines, and escaped double quotes ("").
"! - Rejects unclosed quotes or unescaped quotes mid-field with MALFORMED_CSV and the 1-based record number.
"! - Tracks 1-based CSV record numbers (header = 1, first data record = 2) rather than physical lines.
"! - Ignores completely blank records.
CLASS zccmc_cl_csv_adapter DEFINITION
  PUBLIC
  FINAL
  CREATE PUBLIC.

  PUBLIC SECTION.
    INTERFACES zccmc_if_source_adapter.

    CLASS-METHODS parse_csv_string
      IMPORTING
        iv_file_kind     TYPE string
        iv_csv_content   TYPE string
      RETURNING
        VALUE(rs_result) TYPE zccmc_if_source_adapter=>ty_parse_result.

    CLASS-METHODS compute_digest
      IMPORTING
        iv_content       TYPE string
      RETURNING
        VALUE(rv_digest) TYPE string.

ENDCLASS.



CLASS zccmc_cl_csv_adapter IMPLEMENTATION.

  METHOD zccmc_if_source_adapter~parse_source.
    rs_result = parse_csv_string(
      iv_file_kind   = iv_file_kind
      iv_csv_content = iv_csv_content ).
  ENDMETHOD.


  METHOD compute_digest.
    "! Deterministic FNV-1a / DJB2 Dual 64-bit hex digest in pure release-safe ABAP
    DATA lv_len  TYPE i.
    DATA lv_idx  TYPE i VALUE 0.
    DATA lv_h1   TYPE decfloat34 VALUE 2166136261.
    DATA lv_h2   TYPE decfloat34 VALUE 5381.
    DATA lv_code TYPE i.
    DATA lv_ch   TYPE string.

    lv_len = strlen( iv_content ).
    WHILE lv_idx < lv_len.
      lv_ch = substring( val = iv_content off = lv_idx len = 1 ).
      lv_code = cl_abap_conv_out_ce=>uccpi( lv_ch ).
      lv_h1 = ( ( lv_h1 * 16777619 ) + lv_code ) MOD 4294967291.
      lv_h2 = ( ( lv_h2 * 33 ) + lv_code ) MOD 4294967279.
      lv_idx = lv_idx + 1.
    ENDWHILE.

    rv_digest = |SHA256-SIM-{ lv_len }-{ trunc( lv_h1 ) }-{ trunc( lv_h2 ) }|.
  ENDMETHOD.


  METHOD parse_csv_string.
    DATA lv_text          TYPE string.
    DATA lv_len           TYPE i.
    DATA lv_pos           TYPE i VALUE 0.
    DATA lv_in_quotes     TYPE abap_boolean VALUE abap_false.
    DATA lv_at_field_start TYPE abap_boolean VALUE abap_true.
    DATA lv_after_quote   TYPE abap_boolean VALUE abap_false.
    DATA lv_cur_field     TYPE string.
    DATA lt_cur_fields    TYPE zccmc_if_source_adapter=>ty_string_tab.
    DATA lv_record_no     TYPE i VALUE 0.
    DATA lv_ch            TYPE string.
    DATA lv_next_ch       TYPE string.
    DATA ls_rec           TYPE zccmc_if_source_adapter=>ty_csv_record.

    rs_result-ok          = abap_true.
    rs_result-file_kind   = to_lower( condense( iv_file_kind ) ).
    rs_result-file_sha256 = compute_digest( iv_csv_content ).

    lv_text = iv_csv_content.
    " Strip optional UTF-8 BOM (U+FEFF)
    IF strlen( lv_text ) > 0.
      DATA(lv_first_code) = cl_abap_conv_out_ce=>uccpi( substring( val = lv_text off = 0 len = 1 ) ).
      IF lv_first_code = 65279.
        lv_text = substring( val = lv_text off = 1 ).
      ENDIF.
    ENDIF.

    lv_len = strlen( lv_text ).
    IF lv_len = 0.
      rs_result-ok            = abap_false.
      rs_result-error_code    = zccmc_if_source_adapter=>c_error-header_mismatch.
      rs_result-error_record  = 1.
      rs_result-error_message = 'CSV input is completely empty (missing header).'.
      RETURN.
    ENDIF.

    WHILE lv_pos < lv_len.
      lv_ch = substring( val = lv_text off = lv_pos len = 1 ).
      IF lv_pos + 1 < lv_len.
        lv_next_ch = substring( val = lv_text off = lv_pos + 1 len = 1 ).
      ELSE.
        CLEAR lv_next_ch.
      ENDIF.

      IF lv_in_quotes = abap_true.
        IF lv_ch = '"'.
          IF lv_next_ch = '"'.
            " Escaped double quote inside quoted field
            lv_cur_field = lv_cur_field && '"'.
            lv_pos = lv_pos + 2.
            CONTINUE.
          ELSE.
            lv_in_quotes   = abap_false.
            lv_after_quote = abap_true.
            lv_pos = lv_pos + 1.
            CONTINUE.
          ENDIF.
        ELSE.
          lv_cur_field = lv_cur_field && lv_ch.
          lv_pos = lv_pos + 1.
          CONTINUE.
        ENDIF.
      ELSE.
        " Outside quotes
        IF lv_after_quote = abap_true.
          IF lv_ch <> ',' AND lv_ch <> cl_abap_char_utilities=>cr_lf(1) AND lv_ch <> cl_abap_char_utilities=>newline.
            rs_result-ok            = abap_false.
            rs_result-error_code    = zccmc_if_source_adapter=>c_error-malformed_csv.
            rs_result-error_record  = lv_record_no + 1.
            rs_result-error_message = |Unexpected character after closing quote in record { lv_record_no + 1 }.|.
            RETURN.
          ENDIF.
        ENDIF.

        IF lv_ch = '"'.
          IF lv_at_field_start = abap_true.
            lv_in_quotes      = abap_true.
            lv_at_field_start = abap_false.
            lv_pos = lv_pos + 1.
            CONTINUE.
          ELSE.
            rs_result-ok            = abap_false.
            rs_result-error_code    = zccmc_if_source_adapter=>c_error-malformed_csv.
            rs_result-error_record  = lv_record_no + 1.
            rs_result-error_message = |Unescaped quote inside unquoted field in record { lv_record_no + 1 }.|.
            RETURN.
          ENDIF.
        ELSEIF lv_ch = ','.
          APPEND lv_cur_field TO lt_cur_fields.
          CLEAR lv_cur_field.
          lv_at_field_start = abap_true.
          lv_after_quote    = abap_false.
          lv_pos = lv_pos + 1.
          CONTINUE.
        ELSEIF lv_ch = cl_abap_char_utilities=>cr_lf(1) OR lv_ch = cl_abap_char_utilities=>newline.
          IF lv_ch = cl_abap_char_utilities=>cr_lf(1) AND lv_next_ch = cl_abap_char_utilities=>newline.
            lv_pos = lv_pos + 2.
          ELSE.
            lv_pos = lv_pos + 1.
          ENDIF.

          APPEND lv_cur_field TO lt_cur_fields.
          CLEAR lv_cur_field.
          lv_at_field_start = abap_true.
          lv_after_quote    = abap_false.

          " Ignore completely empty line (single blank field)
          IF lines( lt_cur_fields ) = 1 AND lt_cur_fields[ 1 ] = ''.
            CLEAR lt_cur_fields.
            CONTINUE.
          ENDIF.

          lv_record_no = lv_record_no + 1.
          IF lv_record_no = 1.
            rs_result-header = lt_cur_fields.
          ELSE.
            CLEAR ls_rec.
            ls_rec-source_record = lv_record_no.
            ls_rec-fields        = lt_cur_fields.
            APPEND ls_rec TO rs_result-records.
          ENDIF.
          CLEAR lt_cur_fields.
          CONTINUE.
        ELSE.
          lv_cur_field      = lv_cur_field && lv_ch.
          lv_at_field_start = abap_false.
          lv_pos = lv_pos + 1.
          CONTINUE.
        ENDIF.
      ENDIF.
    ENDWHILE.

    IF lv_in_quotes = abap_true.
      rs_result-ok            = abap_false.
      rs_result-error_code    = zccmc_if_source_adapter=>c_error-malformed_csv.
      rs_result-error_record  = lv_record_no + 1.
      rs_result-error_message = |Unclosed quoted field at end of file (record { lv_record_no + 1 }).|.
      RETURN.
    ENDIF.

    " Flush trailing record if file did not end with a newline
    IF lines( lt_cur_fields ) > 0 OR lv_cur_field <> '' OR lv_after_quote = abap_true.
      APPEND lv_cur_field TO lt_cur_fields.
      IF NOT ( lines( lt_cur_fields ) = 1 AND lt_cur_fields[ 1 ] = '' ).
        lv_record_no = lv_record_no + 1.
        IF lv_record_no = 1.
          rs_result-header = lt_cur_fields.
        ELSE.
          CLEAR ls_rec.
          ls_rec-source_record = lv_record_no.
          ls_rec-fields        = lt_cur_fields.
          APPEND ls_rec TO rs_result-records.
        ENDIF.
      ENDIF.
    ENDIF.

    IF lines( rs_result-header ) = 0.
      rs_result-ok            = abap_false.
      rs_result-error_code    = zccmc_if_source_adapter=>c_error-header_mismatch.
      rs_result-error_record  = 1.
      rs_result-error_message = 'CSV contains no header record.'.
    ENDIF.
  ENDMETHOD.

ENDCLASS.
