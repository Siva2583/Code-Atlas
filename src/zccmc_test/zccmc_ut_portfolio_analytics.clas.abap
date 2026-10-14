"! ABAP Unit tests for ZCCMC_CL_PORTFOLIO_ANALYTICS (Member 2 - Day 6).
"!
"! Covers docs/rules-spec.md section 12 and M2-D06-T01 acceptance criteria:
"! - Hand-counted 7 synthetic sample objects (M-01 = 7, M-02 = 6 MANUAL_REVIEW + 1 KEEP_ADAPT,
"!   M-03 = 4 objects with missing evidence: 2 CRITICALITY_UNKNOWN, 1 NO_USAGE_FACT, 1 WINDOW_TOO_SHORT).
"! - Filtered subsets (by package, source_system, criticality, strategy, ruleset_version, only_missing).
"! - Empty portfolio (all counts zero, no crash).
"! - Anti-double-counting when joined rows or duplicate reason codes are supplied.
"! - Latest-run selection when multiple runs exist for the same object.
"! - Row-order determinism.
CLASS zccmc_ut_portfolio_analytics DEFINITION
  PUBLIC
  FINAL
  FOR TESTING
  RISK LEVEL HARMLESS
  DURATION SHORT.

  PRIVATE SECTION.
    CONSTANTS c_eval_date TYPE d VALUE '20261014'.
    CONSTANTS c_run_id    TYPE string VALUE 'RUN-0001'.

    METHODS:
      t01_empty_portfolio             FOR TESTING,
      t02_sample_7_objects_reconcile  FOR TESTING,
      t03_filter_by_package           FOR TESTING,
      t04_filter_by_source_system     FOR TESTING,
      t05_filter_by_strategy_missing  FOR TESTING,
      t06_no_join_double_counting     FOR TESTING,
      t07_latest_run_wins             FOR TESTING,
      t08_row_order_determinism       FOR TESTING.

    METHODS:
      sample_portfolio_items
        RETURNING VALUE(rt_items) TYPE zccmc_cl_portfolio_analytics=>ty_portfolio_item_tab,

      usage_row
        IMPORTING iv_start        TYPE d
                  iv_end          TYPE d
                  iv_last         TYPE d
                  iv_runs         TYPE i
                  iv_as_of        TYPE d
        RETURNING VALUE(rs_usage) TYPE zccmc_cl_rule_engine=>ty_usage,

      eval_and_build
        IMPORTING iv_sys         TYPE string DEFAULT 'DEMO_SYS'
                  iv_type        TYPE string
                  iv_name        TYPE string
                  iv_pkg         TYPE string
                  is_evidence    TYPE zccmc_cl_rule_engine=>ty_evidence
        RETURNING VALUE(rs_item) TYPE zccmc_cl_portfolio_analytics=>ty_portfolio_item,

      strategy_count
        IMPORTING is_summary      TYPE zccmc_cl_portfolio_analytics=>ty_summary
                  iv_strategy     TYPE string
        RETURNING VALUE(rv_count) TYPE i,

      reason_count
        IMPORTING is_summary      TYPE zccmc_cl_portfolio_analytics=>ty_summary
                  iv_reason       TYPE string
        RETURNING VALUE(rv_count) TYPE i.
ENDCLASS.


CLASS zccmc_ut_portfolio_analytics IMPLEMENTATION.

  METHOD usage_row.
    rs_usage = VALUE #( period_start   = iv_start
                        period_end     = iv_end
                        last_executed  = iv_last
                        run_count      = iv_runs
                        evidence_as_of = iv_as_of ).
  ENDMETHOD.


  METHOD eval_and_build.
    DATA(ls_ruleset) = zccmc_cl_rule_engine=>seed_ruleset( ).
    DATA(ls_result)  = zccmc_cl_rule_engine=>evaluate_object(
                         is_evidence        = is_evidence
                         is_ruleset         = ls_ruleset
                         iv_evaluation_date = c_eval_date
                         iv_run_id          = c_run_id ).
    rs_item = zccmc_cl_portfolio_analytics=>build_item_from_result(
                iv_source_system = iv_sys
                iv_object_type   = iv_type
                iv_object_name   = iv_name
                iv_package_name  = iv_pkg
                iv_criticality   = is_evidence-criticality
                is_result        = ls_result ).
  ENDMETHOD.


  METHOD sample_portfolio_items.
    " Mirrors the 7 synthetic sample objects in data/sample-synthetic/*.csv.
    DATA ls_e TYPE zccmc_cl_rule_engine=>ty_evidence.

    " 1 ZSD_OPEN_ORDERS_RPT (PROG, ZSD, HIGH)
    ls_e = VALUE #( object_id = 'ZSD_OPEN_ORDERS_RPT' criticality = 'HIGH' findings_as_of = '20261013'
                    usages   = VALUE #( ( usage_row( iv_start = '20251013' iv_end = '20261013' iv_last = '20260925'
                                                     iv_runs = 2480 iv_as_of = '20261013' ) ) )
                    findings = VALUE #( ( severity = 'HIGH' ) ( severity = 'HIGH' ) ( severity = 'MEDIUM' )
                                        ( severity = 'MEDIUM' ) ( severity = 'MEDIUM' ) ( severity = 'MEDIUM' ) ) ).
    APPEND eval_and_build( iv_type = 'PROG' iv_name = 'ZSD_OPEN_ORDERS_RPT' iv_pkg = 'ZSD_REPORTS' is_evidence = ls_e )
      TO rt_items.

    " 2 ZCL_PRICING_HELPER (CLAS, ZCL_SHARED, MEDIUM)
    ls_e = VALUE #( object_id = 'ZCL_PRICING_HELPER' criticality = 'MEDIUM' findings_as_of = '20261013'
                    usages   = VALUE #( ( usage_row( iv_start = '20251013' iv_end = '20261013' iv_last = '20261012'
                                                     iv_runs = 15210 iv_as_of = '20261013' ) ) )
                    findings = VALUE #( ( severity = 'LOW' ) )
                    callers  = VALUE #( ( criticality = 'HIGH' ) ) ).
    APPEND eval_and_build( iv_type = 'CLAS' iv_name = 'ZCL_PRICING_HELPER' iv_pkg = 'ZSD_PRICING' is_evidence = ls_e )
      TO rt_items.

    " 3 ZFI_OLD_LEDGER_EXPORT (PROG, ZFI, LOW, no usage row)
    ls_e = VALUE #( object_id = 'ZFI_OLD_LEDGER_EXPORT' criticality = 'LOW' findings_as_of = '20261013' ).
    APPEND eval_and_build( iv_type = 'PROG' iv_name = 'ZFI_OLD_LEDGER_EXPORT' iv_pkg = 'ZFI_LEGACY' is_evidence = ls_e )
      TO rt_items.

    " 4 ZMM_STOCK_ALERT (PROG, ZMM, MEDIUM, 2-month window)
    ls_e = VALUE #( object_id = 'ZMM_STOCK_ALERT' criticality = 'MEDIUM' findings_as_of = '20261013'
                    usages   = VALUE #( ( usage_row( iv_start = '20260801' iv_end = '20261013' iv_last = '00000000'
                                                     iv_runs = 0 iv_as_of = '20261013' ) ) ) ).
    APPEND eval_and_build( iv_type = 'PROG' iv_name = 'ZMM_STOCK_ALERT' iv_pkg = 'ZMM_ALERTS' is_evidence = ls_e )
      TO rt_items.

    " 5 ZSD_CUST_CREDIT_CHECK (FUGR, ZSD, HIGH, 1 HIGH finding)
    ls_e = VALUE #( object_id = 'ZSD_CUST_CREDIT_CHECK' criticality = 'HIGH' findings_as_of = '20261013'
                    usages   = VALUE #( ( usage_row( iv_start = '20251013' iv_end = '20261013' iv_last = '20261010'
                                                     iv_runs = 930 iv_as_of = '20261013' ) ) )
                    findings = VALUE #( ( severity = 'HIGH' ) ) ).
    APPEND eval_and_build( iv_type = 'FUGR' iv_name = 'ZSD_CUST_CREDIT_CHECK' iv_pkg = 'ZSD_CREDIT' is_evidence = ls_e )
      TO rt_items.

    " 6 ZCL_INVOICE_UTIL (CLAS, ZCL_SHARED, UNKNOWN criticality)
    ls_e = VALUE #( object_id = 'ZCL_INVOICE_UTIL' criticality = 'UNKNOWN' findings_as_of = '20261013'
                    usages   = VALUE #( ( usage_row( iv_start = '20251013' iv_end = '20261013' iv_last = '20260930'
                                                     iv_runs = 41 iv_as_of = '20261013' ) ) )
                    callers  = VALUE #( ( criticality = 'HIGH' ) ) ).
    APPEND eval_and_build( iv_type = 'CLAS' iv_name = 'ZCL_INVOICE_UTIL' iv_pkg = 'ZFI_INVOICE' is_evidence = ls_e )
      TO rt_items.

    " 7 ZHR_PAYROLL_ADJ (PROG, ZHR, UNKNOWN criticality)
    ls_e = VALUE #( object_id = 'ZHR_PAYROLL_ADJ' criticality = 'UNKNOWN' findings_as_of = '20261013'
                    usages   = VALUE #( ( usage_row( iv_start = '20251013' iv_end = '20261013' iv_last = '20251212'
                                                     iv_runs = 3 iv_as_of = '20261013' ) ) ) ).
    APPEND eval_and_build( iv_type = 'PROG' iv_name = 'ZHR_PAYROLL_ADJ' iv_pkg = 'ZHR_PAYROLL' is_evidence = ls_e )
      TO rt_items.
  ENDMETHOD.


  METHOD strategy_count.
    rv_count = VALUE #( is_summary-by_strategy[ strategy = iv_strategy ]-object_count OPTIONAL ).
  ENDMETHOD.


  METHOD reason_count.
    rv_count = VALUE #( is_summary-by_missing_reason[ reason_code = iv_reason ]-object_count OPTIONAL ).
  ENDMETHOD.


  METHOD t01_empty_portfolio.
    DATA lt_empty TYPE zccmc_cl_portfolio_analytics=>ty_portfolio_item_tab.
    DATA(ls_sum) = zccmc_cl_portfolio_analytics=>compute_summary( lt_empty ).

    cl_abap_unit_assert=>assert_equals( act = ls_sum-total_objects                  exp = 0 msg = 'PA-T01 total' ).
    cl_abap_unit_assert=>assert_equals( act = ls_sum-objects_with_complete_evidence exp = 0 msg = 'PA-T01 complete' ).
    cl_abap_unit_assert=>assert_equals( act = ls_sum-objects_with_missing_evidence  exp = 0 msg = 'PA-T01 missing' ).
    cl_abap_unit_assert=>assert_equals( act = lines( ls_sum-by_strategy )           exp = 5 msg = 'PA-T01 5 outcomes seeded' ).
    cl_abap_unit_assert=>assert_initial( act = ls_sum-by_missing_reason             msg = 'PA-T01 no missing reasons' ).
  ENDMETHOD.


  METHOD t02_sample_7_objects_reconcile.
    " Hand-counted oracle in docs/rules-spec.md section 12:
    " M-01 = 7; M-02 = MANUAL_REVIEW 6, KEEP_ADAPT 1; M-03 = 4 objects (CRITICALITY_UNKNOWN 2, NO_USAGE_FACT 1, WINDOW_TOO_SHORT 1).
    DATA(ls_sum) = zccmc_cl_portfolio_analytics=>compute_summary( sample_portfolio_items( ) ).

    cl_abap_unit_assert=>assert_equals( act = ls_sum-total_objects                  exp = 7 msg = 'M-01 total objects' ).
    cl_abap_unit_assert=>assert_equals( act = ls_sum-objects_with_complete_evidence exp = 3 msg = 'complete evidence count' ).
    cl_abap_unit_assert=>assert_equals( act = ls_sum-objects_with_missing_evidence  exp = 4 msg = 'M-03 missing evidence objects' ).

    cl_abap_unit_assert=>assert_equals( act = strategy_count( is_summary = ls_sum iv_strategy = 'MANUAL_REVIEW' )
                                        exp = 6 msg = 'M-02 MANUAL_REVIEW' ).
    cl_abap_unit_assert=>assert_equals( act = strategy_count( is_summary = ls_sum iv_strategy = 'KEEP_ADAPT' )
                                        exp = 1 msg = 'M-02 KEEP_ADAPT' ).
    cl_abap_unit_assert=>assert_equals( act = strategy_count( is_summary = ls_sum iv_strategy = 'RETIRE_CANDIDATE' )
                                        exp = 0 msg = 'M-02 RETIRE_CANDIDATE' ).
    cl_abap_unit_assert=>assert_equals( act = strategy_count( is_summary = ls_sum iv_strategy = 'REWRITE_RAP' )
                                        exp = 0 msg = 'M-02 REWRITE_RAP' ).
    cl_abap_unit_assert=>assert_equals( act = strategy_count( is_summary = ls_sum iv_strategy = 'SIDE_BY_SIDE_BTP' )
                                        exp = 0 msg = 'M-02 SIDE_BY_SIDE_BTP' ).

    cl_abap_unit_assert=>assert_equals( act = reason_count( is_summary = ls_sum iv_reason = 'CRITICALITY_UNKNOWN' )
                                        exp = 2 msg = 'M-03 CRITICALITY_UNKNOWN' ).
    cl_abap_unit_assert=>assert_equals( act = reason_count( is_summary = ls_sum iv_reason = 'NO_USAGE_FACT' )
                                        exp = 1 msg = 'M-03 NO_USAGE_FACT' ).
    cl_abap_unit_assert=>assert_equals( act = reason_count( is_summary = ls_sum iv_reason = 'WINDOW_TOO_SHORT' )
                                        exp = 1 msg = 'M-03 WINDOW_TOO_SHORT' ).

    " Reconcile sum of strategies == total_objects
    DATA(lv_sum_strat) = 0.
    LOOP AT ls_sum-by_strategy INTO DATA(ls_s).
      lv_sum_strat = lv_sum_strat + ls_s-object_count.
    ENDLOOP.
    cl_abap_unit_assert=>assert_equals( act = lv_sum_strat exp = ls_sum-total_objects
                                        msg = 'strategy counts must sum to total_objects' ).
  ENDMETHOD.


  METHOD t03_filter_by_package.
    DATA(lt_items) = sample_portfolio_items( ).

    " Package ZSD_REPORTS: ZSD_OPEN_ORDERS_RPT -> 1 MANUAL_REVIEW, 0 missing evidence
    DATA(ls_zsd_rpt) = zccmc_cl_portfolio_analytics=>compute_summary(
                         it_items  = lt_items
                         is_filter = VALUE #( package_name = 'ZSD_REPORTS' ) ).
    cl_abap_unit_assert=>assert_equals( act = ls_zsd_rpt-total_objects                 exp = 1 msg = 'ZSD_REPORTS total' ).
    cl_abap_unit_assert=>assert_equals( act = ls_zsd_rpt-objects_with_missing_evidence exp = 0 msg = 'ZSD_REPORTS missing' ).
    cl_abap_unit_assert=>assert_equals( act = strategy_count( is_summary = ls_zsd_rpt iv_strategy = 'MANUAL_REVIEW' )
                                        exp = 1 msg = 'ZSD_REPORTS MANUAL_REVIEW' ).

    " Package ZSD_PRICING (case-insensitive): ZCL_PRICING_HELPER -> 1 KEEP_ADAPT, 0 missing evidence
    DATA(ls_pricing) = zccmc_cl_portfolio_analytics=>compute_summary(
                         it_items  = lt_items
                         is_filter = VALUE #( package_name = 'zsd_pricing' ) ).
    cl_abap_unit_assert=>assert_equals( act = ls_pricing-total_objects                 exp = 1 msg = 'ZSD_PRICING total' ).
    cl_abap_unit_assert=>assert_equals( act = ls_pricing-objects_with_missing_evidence exp = 0 msg = 'ZSD_PRICING missing' ).
    cl_abap_unit_assert=>assert_equals( act = strategy_count( is_summary = ls_pricing iv_strategy = 'KEEP_ADAPT' )
                                        exp = 1 msg = 'ZSD_PRICING KEEP_ADAPT' ).

    " Criticality HIGH filter: ZSD_OPEN_ORDERS_RPT and ZSD_CUST_CREDIT_CHECK -> 2 MANUAL_REVIEW
    DATA(ls_high) = zccmc_cl_portfolio_analytics=>compute_summary(
                      it_items  = lt_items
                      is_filter = VALUE #( criticality = 'HIGH' ) ).
    cl_abap_unit_assert=>assert_equals( act = ls_high-total_objects                 exp = 2 msg = 'HIGH criticality total' ).
    cl_abap_unit_assert=>assert_equals( act = ls_high-objects_with_missing_evidence exp = 0 msg = 'HIGH criticality missing' ).
    cl_abap_unit_assert=>assert_equals( act = strategy_count( is_summary = ls_high iv_strategy = 'MANUAL_REVIEW' )
                                        exp = 2 msg = 'HIGH criticality MANUAL_REVIEW' ).
  ENDMETHOD.


  METHOD t04_filter_by_source_system.
    DATA(lt_items) = sample_portfolio_items( ).
    DATA(ls_demo)  = zccmc_cl_portfolio_analytics=>compute_summary(
                       it_items  = lt_items
                       is_filter = VALUE #( source_system = 'DEMO_SYS' ) ).
    cl_abap_unit_assert=>assert_equals( act = ls_demo-total_objects exp = 7 msg = 'DEMO_SYS matches all 7' ).

    DATA(ls_other) = zccmc_cl_portfolio_analytics=>compute_summary(
                       it_items  = lt_items
                       is_filter = VALUE #( source_system = 'NON_EXISTENT_SYS' ) ).
    cl_abap_unit_assert=>assert_equals( act = ls_other-total_objects exp = 0 msg = 'other system matches 0' ).
  ENDMETHOD.


  METHOD t05_filter_by_strategy_missing.
    DATA(lt_items) = sample_portfolio_items( ).

    DATA(ls_keep) = zccmc_cl_portfolio_analytics=>compute_summary(
                      it_items  = lt_items
                      is_filter = VALUE #( strategy = 'KEEP_ADAPT' ) ).
    cl_abap_unit_assert=>assert_equals( act = ls_keep-total_objects exp = 1 msg = '1 KEEP_ADAPT object' ).

    DATA(ls_missing) = zccmc_cl_portfolio_analytics=>compute_summary(
                         it_items  = lt_items
                         is_filter = VALUE #( only_missing_evidence = abap_true ) ).
    cl_abap_unit_assert=>assert_equals( act = ls_missing-total_objects exp = 4 msg = '4 objects with missing evidence' ).
  ENDMETHOD.


  METHOD t06_no_join_double_counting.
    " Simulate a caller passing 6 duplicate rows for the same object (e.g. joined to 6 findings)
    " and duplicate reason codes within a row. Counts must not inflate.
    DATA(lt_items) = sample_portfolio_items( ).
    DATA(ls_first) = lt_items[ 1 ].
    ls_first-missing_evidence = VALUE #( ( `CRITICALITY_UNKNOWN` ) ( `CRITICALITY_UNKNOWN` ) ).

    DATA lt_joined TYPE zccmc_cl_portfolio_analytics=>ty_portfolio_item_tab.
    DO 6 TIMES.
      APPEND ls_first TO lt_joined.
    ENDDO.

    DATA(ls_sum) = zccmc_cl_portfolio_analytics=>compute_summary( lt_joined ).
    cl_abap_unit_assert=>assert_equals( act = ls_sum-total_objects exp = 1
                                        msg = 'joined rows for one object must count once' ).
    cl_abap_unit_assert=>assert_equals( act = reason_count( is_summary = ls_sum iv_reason = 'CRITICALITY_UNKNOWN' )
                                        exp = 1 msg = 'duplicate reason code on one object must count once' ).
  ENDMETHOD.


  METHOD t07_latest_run_wins.
    " Two runs for the same object: RUN-0001 had missing evidence, RUN-0002 resolved it to KEEP_ADAPT.
    DATA lt_runs TYPE zccmc_cl_portfolio_analytics=>ty_portfolio_item_tab.
    APPEND VALUE #( object_id        = 'OBJ-1'
                    source_system    = 'DEMO_SYS'
                    object_type      = 'CLAS'
                    object_name      = 'ZCL_TEST'
                    package_name     = 'ZPKG'
                    criticality      = 'UNKNOWN'
                    strategy         = 'MANUAL_REVIEW'
                    run_id           = 'RUN-0001'
                    missing_evidence = VALUE #( ( `CRITICALITY_UNKNOWN` ) ) ) TO lt_runs.
    APPEND VALUE #( object_id        = 'OBJ-1'
                    source_system    = 'DEMO_SYS'
                    object_type      = 'CLAS'
                    object_name      = 'ZCL_TEST'
                    package_name     = 'ZPKG'
                    criticality      = 'MEDIUM'
                    strategy         = 'KEEP_ADAPT'
                    run_id           = 'RUN-0002' ) TO lt_runs.

    DATA(ls_sum) = zccmc_cl_portfolio_analytics=>compute_summary( lt_runs ).
    cl_abap_unit_assert=>assert_equals( act = ls_sum-total_objects                 exp = 1 msg = 'still 1 object' ).
    cl_abap_unit_assert=>assert_equals( act = ls_sum-objects_with_missing_evidence exp = 0 msg = 'latest run has no missing evidence' ).
    cl_abap_unit_assert=>assert_equals( act = strategy_count( is_summary = ls_sum iv_strategy = 'KEEP_ADAPT' )
                                        exp = 1 msg = 'latest run strategy is KEEP_ADAPT' ).
  ENDMETHOD.


  METHOD t08_row_order_determinism.
    DATA(lt_forward) = sample_portfolio_items( ).
    DATA lt_reverse TYPE zccmc_cl_portfolio_analytics=>ty_portfolio_item_tab.
    DATA(lv_idx) = lines( lt_forward ).
    WHILE lv_idx > 0.
      APPEND lt_forward[ lv_idx ] TO lt_reverse.
      lv_idx = lv_idx - 1.
    ENDWHILE.

    DATA(ls_a) = zccmc_cl_portfolio_analytics=>compute_summary( lt_forward ).
    DATA(ls_b) = zccmc_cl_portfolio_analytics=>compute_summary( lt_reverse ).
    cl_abap_unit_assert=>assert_equals( act = ls_b exp = ls_a
                                        msg = 'portfolio summary must not depend on input row order' ).
  ENDMETHOD.

ENDCLASS.
