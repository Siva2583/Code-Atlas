"! Portfolio analytics service for the Clean Core Migration Cockpit (Member 2 — v1.0.0 Frozen).
"!
"! Computes the deterministic portfolio metrics documented in docs/rules-spec.md section 10:
"! - M-01: Total objects evaluated in the latest recommendation run.
"! - M-02: Objects grouped by RecommendedStrategy (strictly the 5 frozen outcomes).
"! - M-03: Objects with non-empty MissingEvidence (unresolved inputs) and breakdown by reason code.
"! - Additional groupings for Portfolio Overview UI filters: by source_system, package, and criticality.
"!
"! INTEGRATION WITH MEMBER 1 (Day 1–11 Complete):
"! - Consumes object metadata from Member 1's ZCCMC_CUSTOBJ / ZCCMC_I_CustomObject (contract v0.3)
"!   combined with evaluation results from zccmc_cl_rule_engine=>evaluate_object or evaluate_portfolio
"!   via build_item_from_result and build_items_from_results.
"! - Deduplicates by normalized (source_system, object_type, object_name) or object_id, keeping only
"!   the latest run per object so 1:N joins to ZCCMC_USAGE, ZCCMC_FINDING, or ZCCMC_DEPEND never
"!   double-count objects or strategies.
CLASS zccmc_cl_portfolio_analytics DEFINITION
  PUBLIC
  FINAL
  CREATE PUBLIC.

  PUBLIC SECTION.
    TYPES:
      BEGIN OF ty_object_meta,
        object_id     TYPE string,
        source_system TYPE string,
        object_type   TYPE string,
        object_name   TYPE string,
        package_name  TYPE string,
        criticality   TYPE string,
      END OF ty_object_meta,
      ty_object_meta_tab TYPE STANDARD TABLE OF ty_object_meta WITH EMPTY KEY.

    TYPES:
      BEGIN OF ty_portfolio_item,
        object_id        TYPE string,
        source_system    TYPE string,
        object_type      TYPE string,
        object_name      TYPE string,
        package_name     TYPE string,
        criticality      TYPE string,
        strategy         TYPE string,
        ruleset_id       TYPE string,
        ruleset_version  TYPE string,
        run_id           TYPE string,
        run_timestamp    TYPE utclong,
        missing_evidence TYPE zccmc_cl_rule_engine=>ty_code_tab,
        matched_rule_ids TYPE zccmc_cl_rule_engine=>ty_code_tab,
      END OF ty_portfolio_item,
      ty_portfolio_item_tab TYPE STANDARD TABLE OF ty_portfolio_item WITH EMPTY KEY.

    TYPES:
      BEGIN OF ty_filter,
        source_system         TYPE string,
        package_name          TYPE string,
        criticality           TYPE string,
        strategy              TYPE string,
        ruleset_version       TYPE string,
        only_missing_evidence TYPE abap_boolean,
      END OF ty_filter.

    TYPES:
      BEGIN OF ty_strategy_count,
        strategy     TYPE string,
        object_count TYPE i,
      END OF ty_strategy_count,
      ty_strategy_count_tab TYPE STANDARD TABLE OF ty_strategy_count WITH EMPTY KEY.

    TYPES:
      BEGIN OF ty_reason_count,
        reason_code  TYPE string,
        object_count TYPE i,
      END OF ty_reason_count,
      ty_reason_count_tab TYPE STANDARD TABLE OF ty_reason_count WITH EMPTY KEY.

    TYPES:
      BEGIN OF ty_group_count,
        group_key    TYPE string,
        object_count TYPE i,
      END OF ty_group_count,
      ty_group_count_tab TYPE STANDARD TABLE OF ty_group_count WITH EMPTY KEY.

    TYPES:
      BEGIN OF ty_summary,
        total_objects                  TYPE i,                     "M-01
        objects_with_complete_evidence TYPE i,
        objects_with_missing_evidence  TYPE i,                     "M-03 headline count
        by_strategy                    TYPE ty_strategy_count_tab, "M-02
        by_missing_reason              TYPE ty_reason_count_tab,   "M-03 breakdown
        by_source_system               TYPE ty_group_count_tab,
        by_package                     TYPE ty_group_count_tab,
        by_criticality                 TYPE ty_group_count_tab,
      END OF ty_summary.

    "! Build a portfolio item from custom-object metadata and a rule-engine evaluation result.
    CLASS-METHODS build_item_from_result
      IMPORTING iv_source_system TYPE string OPTIONAL
                iv_object_type   TYPE string OPTIONAL
                iv_object_name   TYPE string OPTIONAL
                iv_package_name  TYPE string OPTIONAL
                iv_criticality   TYPE string OPTIONAL
                is_result        TYPE zccmc_cl_rule_engine=>ty_result
      RETURNING VALUE(rs_item)   TYPE ty_portfolio_item.

    "! Build a portfolio item table from Member 1 imported object metadata rows and a batch of
    "! rule-engine evaluation results (matched by object_id or object_name).
    CLASS-METHODS build_items_from_results
      IMPORTING it_objects      TYPE ty_object_meta_tab
                it_results      TYPE zccmc_cl_rule_engine=>ty_result_tab
      RETURNING VALUE(rt_items) TYPE ty_portfolio_item_tab.

    "! Compute reconciled portfolio metrics from a list of portfolio items and an optional filter.
    CLASS-METHODS compute_summary
      IMPORTING it_items          TYPE ty_portfolio_item_tab
                is_filter         TYPE ty_filter OPTIONAL
      RETURNING VALUE(rs_summary) TYPE ty_summary.

  PRIVATE SECTION.
    CLASS-METHODS normalize_key
      IMPORTING is_item       TYPE ty_portfolio_item
      RETURNING VALUE(rv_key) TYPE string.

    CLASS-METHODS normalize_criticality
      IMPORTING iv_criticality TYPE string
      RETURNING VALUE(rv_crit) TYPE string.

    CLASS-METHODS normalize_strategy
      IMPORTING iv_strategy     TYPE string
      RETURNING VALUE(rv_strat) TYPE string.

    CLASS-METHODS deduplicate_latest_per_object
      IMPORTING it_items         TYPE ty_portfolio_item_tab
      RETURNING VALUE(rt_unique) TYPE ty_portfolio_item_tab.

    CLASS-METHODS matches_filter
      IMPORTING is_item           TYPE ty_portfolio_item
                is_filter         TYPE ty_filter
      RETURNING VALUE(rv_matches) TYPE abap_boolean.

    " Parameter kinds must be declared in this order: IMPORTING, EXPORTING, CHANGING, RETURNING.
    CLASS-METHODS increment_group
      IMPORTING iv_key    TYPE string
      CHANGING  ct_groups TYPE ty_group_count_tab.
ENDCLASS.


CLASS zccmc_cl_portfolio_analytics IMPLEMENTATION.

  METHOD build_item_from_result.
    rs_item-object_id        = is_result-object_id.
    rs_item-source_system    = to_upper( condense( iv_source_system ) ).
    rs_item-object_type      = to_upper( condense( iv_object_type ) ).
    rs_item-object_name      = to_upper( condense( iv_object_name ) ).
    IF rs_item-object_name IS INITIAL.
      rs_item-object_name = to_upper( condense( is_result-object_id ) ).
    ENDIF.
    rs_item-package_name     = to_upper( condense( iv_package_name ) ).
    rs_item-criticality      = normalize_criticality( iv_criticality ).
    rs_item-strategy         = normalize_strategy( is_result-strategy ).
    rs_item-ruleset_id       = is_result-ruleset_id.
    rs_item-ruleset_version  = is_result-ruleset_version.
    rs_item-run_id           = is_result-run_id.
    rs_item-run_timestamp    = is_result-run_timestamp.
    rs_item-missing_evidence = is_result-missing_evidence.
    rs_item-matched_rule_ids = is_result-matched_rule_ids.
  ENDMETHOD.


  METHOD build_items_from_results.
    CLEAR rt_items.
    LOOP AT it_results INTO DATA(ls_res).
      DATA(lv_res_key) = to_upper( condense( ls_res-object_id ) ).
      DATA ls_meta TYPE ty_object_meta.
      CLEAR ls_meta.
      LOOP AT it_objects INTO DATA(ls_obj).
        IF to_upper( condense( ls_obj-object_id ) ) = lv_res_key
           OR to_upper( condense( ls_obj-object_name ) ) = lv_res_key.
          ls_meta = ls_obj.
          EXIT.
        ENDIF.
      ENDLOOP.
      APPEND build_item_from_result(
               iv_source_system = ls_meta-source_system
               iv_object_type   = ls_meta-object_type
               iv_object_name   = ls_meta-object_name
               iv_package_name  = ls_meta-package_name
               iv_criticality   = ls_meta-criticality
               is_result        = ls_res ) TO rt_items.
    ENDLOOP.
  ENDMETHOD.


  METHOD normalize_criticality.
    rv_crit = to_upper( condense( iv_criticality ) ).
    IF rv_crit <> 'HIGH' AND rv_crit <> 'MEDIUM' AND rv_crit <> 'LOW'.
      rv_crit = 'UNKNOWN'.
    ENDIF.
  ENDMETHOD.


  METHOD normalize_strategy.
    rv_strat = to_upper( condense( iv_strategy ) ).
    IF rv_strat <> zccmc_cl_rule_engine=>c_outcome-keep_adapt
       AND rv_strat <> zccmc_cl_rule_engine=>c_outcome-rewrite_rap
       AND rv_strat <> zccmc_cl_rule_engine=>c_outcome-retire_candidate
       AND rv_strat <> zccmc_cl_rule_engine=>c_outcome-side_by_side_btp
       AND rv_strat <> zccmc_cl_rule_engine=>c_outcome-manual_review.
      rv_strat = zccmc_cl_rule_engine=>c_outcome-manual_review.
    ENDIF.
  ENDMETHOD.


  METHOD normalize_key.
    " One key shape for every item: SYSTEM|TYPE|NAME (object_id is used when there is no name).
    " The same object therefore gets the same key whether it was built with
    " build_item_from_result or supplied directly. Inside a string template a literal
    " vertical bar must be written as \|.
    DATA(lv_sys)  = to_upper( condense( is_item-source_system ) ).
    DATA(lv_type) = to_upper( condense( is_item-object_type ) ).
    DATA(lv_name) = to_upper( condense( is_item-object_name ) ).
    IF lv_name IS INITIAL.
      lv_name = to_upper( condense( is_item-object_id ) ).
    ENDIF.

    IF lv_sys IS INITIAL AND lv_type IS INITIAL AND lv_name IS INITIAL.
      CLEAR rv_key.   "no identity at all: the caller skips this item
    ELSE.
      rv_key = |{ lv_sys }\|{ lv_type }\|{ lv_name }|.
    ENDIF.
  ENDMETHOD.


  METHOD deduplicate_latest_per_object.
    " Sort so the latest run (by run_timestamp DESC, then run_id DESC) comes first per object key.
    TYPES:
      BEGIN OF ty_keyed_item,
        norm_key      TYPE string,
        run_timestamp TYPE utclong,
        run_id        TYPE string,
        item          TYPE ty_portfolio_item,
      END OF ty_keyed_item.

    DATA lt_keyed       TYPE STANDARD TABLE OF ty_keyed_item WITH EMPTY KEY.
    DATA lt_clean_codes TYPE zccmc_cl_rule_engine=>ty_code_tab.

    LOOP AT it_items INTO DATA(ls_raw).
      DATA(ls_norm) = ls_raw.
      ls_norm-source_system = to_upper( condense( ls_raw-source_system ) ).
      ls_norm-object_type   = to_upper( condense( ls_raw-object_type ) ).
      ls_norm-object_name   = to_upper( condense( ls_raw-object_name ) ).
      IF ls_norm-object_name IS INITIAL.
        ls_norm-object_name = to_upper( condense( ls_raw-object_id ) ).
      ENDIF.
      ls_norm-package_name  = to_upper( condense( ls_raw-package_name ) ).
      ls_norm-criticality   = normalize_criticality( ls_raw-criticality ).
      ls_norm-strategy      = normalize_strategy( ls_raw-strategy ).

      " Deduplicate missing_evidence codes within the single item
      CLEAR lt_clean_codes.
      LOOP AT ls_raw-missing_evidence INTO DATA(lv_code).
        DATA(lv_norm_code) = to_upper( condense( lv_code ) ).
        IF lv_norm_code IS NOT INITIAL AND NOT line_exists( lt_clean_codes[ table_line = lv_norm_code ] ).
          APPEND lv_norm_code TO lt_clean_codes.
        ENDIF.
      ENDLOOP.
      SORT lt_clean_codes ASCENDING.
      ls_norm-missing_evidence = lt_clean_codes.

      DATA(lv_key) = normalize_key( ls_norm ).
      IF lv_key IS INITIAL.
        CONTINUE.
      ENDIF.

      APPEND VALUE #( norm_key      = lv_key
                      run_timestamp = ls_norm-run_timestamp
                      run_id        = ls_norm-run_id
                      item          = ls_norm ) TO lt_keyed.
    ENDLOOP.

    SORT lt_keyed BY norm_key ASCENDING run_timestamp DESCENDING run_id DESCENDING.

    DATA lv_prev_key TYPE string.
    LOOP AT lt_keyed INTO DATA(ls_entry).
      IF ls_entry-norm_key <> lv_prev_key.
        APPEND ls_entry-item TO rt_unique.
        lv_prev_key = ls_entry-norm_key.
      ENDIF.
    ENDLOOP.
  ENDMETHOD.


  METHOD matches_filter.
    rv_matches = abap_false.

    IF is_filter-source_system IS NOT INITIAL
       AND is_item-source_system <> to_upper( condense( is_filter-source_system ) ).
      RETURN.
    ENDIF.

    IF is_filter-package_name IS NOT INITIAL
       AND is_item-package_name <> to_upper( condense( is_filter-package_name ) ).
      RETURN.
    ENDIF.

    IF is_filter-criticality IS NOT INITIAL
       AND is_item-criticality <> normalize_criticality( is_filter-criticality ).
      RETURN.
    ENDIF.

    IF is_filter-strategy IS NOT INITIAL
       AND is_item-strategy <> to_upper( condense( is_filter-strategy ) ).
      RETURN.
    ENDIF.

    IF is_filter-ruleset_version IS NOT INITIAL
       AND condense( is_item-ruleset_version ) <> condense( is_filter-ruleset_version ).
      RETURN.
    ENDIF.

    IF is_filter-only_missing_evidence = abap_true
       AND is_item-missing_evidence IS INITIAL.
      RETURN.
    ENDIF.

    rv_matches = abap_true.
  ENDMETHOD.


  METHOD increment_group.
    DATA(lv_clean_key) = COND string( WHEN iv_key IS NOT INITIAL THEN iv_key ELSE 'UNSPECIFIED' ).
    ASSIGN ct_groups[ group_key = lv_clean_key ] TO FIELD-SYMBOL(<ls_group>).
    IF sy-subrc = 0.
      <ls_group>-object_count = <ls_group>-object_count + 1.
    ELSE.
      APPEND VALUE #( group_key = lv_clean_key object_count = 1 ) TO ct_groups.
    ENDIF.
  ENDMETHOD.


  METHOD compute_summary.
    CLEAR rs_summary.

    " Always seed all five canonical strategies in a fixed deterministic order.
    rs_summary-by_strategy = VALUE #(
      ( strategy = zccmc_cl_rule_engine=>c_outcome-keep_adapt       object_count = 0 )
      ( strategy = zccmc_cl_rule_engine=>c_outcome-rewrite_rap      object_count = 0 )
      ( strategy = zccmc_cl_rule_engine=>c_outcome-retire_candidate object_count = 0 )
      ( strategy = zccmc_cl_rule_engine=>c_outcome-side_by_side_btp object_count = 0 )
      ( strategy = zccmc_cl_rule_engine=>c_outcome-manual_review    object_count = 0 ) ).

    DATA(lt_unique) = deduplicate_latest_per_object( it_items ).

    LOOP AT lt_unique INTO DATA(ls_item).
      IF matches_filter( is_item = ls_item is_filter = is_filter ) = abap_false.
        CONTINUE.
      ENDIF.

      rs_summary-total_objects = rs_summary-total_objects + 1.

      " M-02: strategy count (guaranteed to match one of the 5 seeded strategies via normalize_strategy)
      ASSIGN rs_summary-by_strategy[ strategy = ls_item-strategy ] TO FIELD-SYMBOL(<ls_strat>).
      IF sy-subrc = 0.
        <ls_strat>-object_count = <ls_strat>-object_count + 1.
      ENDIF.

      " M-03: missing-evidence count and per-reason breakdown (1 count per object per reason)
      IF ls_item-missing_evidence IS INITIAL.
        rs_summary-objects_with_complete_evidence = rs_summary-objects_with_complete_evidence + 1.
      ELSE.
        rs_summary-objects_with_missing_evidence = rs_summary-objects_with_missing_evidence + 1.
        LOOP AT ls_item-missing_evidence INTO DATA(lv_reason).
          ASSIGN rs_summary-by_missing_reason[ reason_code = lv_reason ] TO FIELD-SYMBOL(<ls_reason>).
          IF sy-subrc = 0.
            <ls_reason>-object_count = <ls_reason>-object_count + 1.
          ELSE.
            APPEND VALUE #( reason_code = lv_reason object_count = 1 ) TO rs_summary-by_missing_reason.
          ENDIF.
        ENDLOOP.
      ENDIF.

      " Additional dimensions for Portfolio Overview filters
      increment_group( EXPORTING iv_key    = ls_item-source_system
                       CHANGING  ct_groups = rs_summary-by_source_system ).
      increment_group( EXPORTING iv_key    = ls_item-package_name
                       CHANGING  ct_groups = rs_summary-by_package ).
      increment_group( EXPORTING iv_key    = ls_item-criticality
                       CHANGING  ct_groups = rs_summary-by_criticality ).
    ENDLOOP.

    SORT rs_summary-by_missing_reason BY reason_code ASCENDING.
    SORT rs_summary-by_source_system  BY group_key ASCENDING.
    SORT rs_summary-by_package        BY group_key ASCENDING.
    SORT rs_summary-by_criticality    BY group_key ASCENDING.
  ENDMETHOD.

ENDCLASS.
