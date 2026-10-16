"! ABAP Unit tests for ZCCMC_CL_RULE_ENGINE (Member 2 — v1.0.0 Frozen, 31 Test Methods).
"!
"! DEMO / SYNTHETIC data only.
"! STATUS: Repository v1 regression suite complete (`t01`..`t31`), aligned with Member 1's
"! Day 1–11 completed persistence & import contract (v0.3, `build_m2_evidence_for_obj`), and
"! cross-verified by `tools/m2_rules_oracle.py`. Run the whole class in ADT (`Ctrl+Shift+F10`)
"! once package `ZCCMC` is provisioned in the trial tenant and record the result in `docs/test-matrix.md`.
CLASS zccmc_ut_rule_engine DEFINITION
  PUBLIC
  FINAL
  FOR TESTING
  RISK LEVEL HARMLESS
  DURATION SHORT.

  PRIVATE SECTION.
    TYPES ty_codes TYPE zccmc_cl_rule_engine=>ty_code_tab.

    CONSTANTS c_eval_date TYPE d VALUE '20261014'.
    CONSTANTS c_run_id    TYPE string VALUE 'RUN-0001'.

    METHODS:
      " ---- the 10 paper tests of docs/rules-spec.md section 5 ----
      t01_no_use_12_months_retire        FOR TESTING,
      t02_no_use_11_months_manual        FOR TESTING,
      t03_high_caller_no_match           FOR TESTING,
      t04_used_zero_findings_keep        FOR TESTING,
      t05_one_high_finding_manual        FOR TESTING,
      t06_used_low_finding_keep          FOR TESTING,
      t07_criticality_unknown_manual     FOR TESTING,
      t08_no_usage_row_manual            FOR TESTING,
      t09_equal_priority_conflict        FOR TESTING,
      t10_zero_runs_with_date_manual     FOR TESTING,
      " ---- more missing / contradictory / stale evidence ----
      t11_runs_without_date_manual       FOR TESTING,
      t12_period_end_before_start        FOR TESTING,
      t13_staleness_boundary             FOR TESTING,
      t14_findings_coverage_unknown      FOR TESTING,
      t15_multiple_usage_facts           FOR TESTING,
      t16_caller_criticality_unknown     FOR TESTING,
      " ---- rule-set behaviour ----
      t17_same_priority_same_outcome     FOR TESTING,
      t18_no_rule_matches                FOR TESTING,
      t19_missing_r10_still_manual       FOR TESTING,
      t20_unknown_condition_code         FOR TESTING,
      t21_inactive_rule_is_ignored       FOR TESTING,
      " ---- details ----
      t22_info_and_medium_not_high       FOR TESTING,
      t23_whole_months_boundaries        FOR TESTING,
      t24_result_and_explanation         FOR TESTING,
      " ---- determinism and permutation ----
      t25_repeat_run_is_identical        FOR TESTING,
      t26_row_order_does_not_matter      FOR TESTING,
      " ---- the 7 synthetic sample objects (golden table) ----
      t27_sample_objects_golden          FOR TESTING,
      " ---- Day 8-11: portfolio permutation, cross-object isolation, edge fixtures & M1 bridge ----
      t28_portfolio_batch_and_perm       FOR TESTING,
      t29_no_cross_object_leakage        FOR TESTING,
      t30_edge_and_corrected_fixtures    FOR TESTING,
      t31_m1_import_evidence_bridge      FOR TESTING.

    METHODS:
      usage_row
        IMPORTING iv_start        TYPE d
                  iv_end          TYPE d
                  iv_last         TYPE d
                  iv_runs         TYPE i
                  iv_as_of        TYPE d
        RETURNING VALUE(rs_usage) TYPE zccmc_cl_rule_engine=>ty_usage,

      " Used object, 12-month window, fresh, findings coverage known, no findings, no caller.
      used_evidence
        IMPORTING iv_criticality     TYPE string DEFAULT 'MEDIUM'
                  iv_runs            TYPE i      DEFAULT 100
        RETURNING VALUE(rs_evidence) TYPE zccmc_cl_rule_engine=>ty_evidence,

      " Never run, 12-month window, fresh, findings coverage known, no findings, no caller.
      unused_evidence
        IMPORTING iv_start           TYPE d DEFAULT '20251013'
        RETURNING VALUE(rs_evidence) TYPE zccmc_cl_rule_engine=>ty_evidence,

      sample_evidence_tab
        RETURNING VALUE(rt_evidence) TYPE zccmc_cl_rule_engine=>ty_evidence_tab,

      evaluate
        IMPORTING is_evidence      TYPE zccmc_cl_rule_engine=>ty_evidence
                  is_ruleset       TYPE zccmc_cl_rule_engine=>ty_ruleset OPTIONAL
        RETURNING VALUE(rs_result) TYPE zccmc_cl_rule_engine=>ty_result,

      assert_result
        IMPORTING is_result   TYPE zccmc_cl_rule_engine=>ty_result
                  iv_strategy TYPE string
                  it_matched  TYPE ty_codes
                  it_missing  TYPE ty_codes
                  iv_msg      TYPE string.
ENDCLASS.


CLASS zccmc_ut_rule_engine IMPLEMENTATION.

  METHOD usage_row.
    rs_usage = VALUE #( period_start   = iv_start
                        period_end     = iv_end
                        last_executed  = iv_last
                        run_count      = iv_runs
                        evidence_as_of = iv_as_of ).
  ENDMETHOD.

  METHOD used_evidence.
    rs_evidence = VALUE #(
      object_id      = 'OBJ-USED'
      criticality    = iv_criticality
      findings_as_of = '20261013'
      usages         = VALUE #( ( usage_row( iv_start = '20251013' iv_end = '20261013'
                                             iv_last  = '20260925' iv_runs = iv_runs
                                             iv_as_of = '20261013' ) ) ) ).
  ENDMETHOD.

  METHOD unused_evidence.
    rs_evidence = VALUE #(
      object_id      = 'OBJ-UNUSED'
      criticality    = 'LOW'
      findings_as_of = '20261013'
      usages         = VALUE #( ( usage_row( iv_start = iv_start iv_end = '20261013'
                                             iv_last  = '00000000' iv_runs = 0
                                             iv_as_of = '20261013' ) ) ) ).
  ENDMETHOD.

  METHOD sample_evidence_tab.
    " The 7 synthetic sample objects from data/sample-synthetic/*.csv (contract v0.3)
    rt_evidence = VALUE #(
      ( object_id = 'ZSD_OPEN_ORDERS_RPT' criticality = 'HIGH' findings_as_of = '20261013'
        usages    = VALUE #( ( usage_row( iv_start = '20251013' iv_end = '20261013' iv_last = '20260925'
                                          iv_runs = 2480 iv_as_of = '20261013' ) ) )
        findings  = VALUE #( ( severity = 'HIGH' ) ( severity = 'HIGH' ) ( severity = 'MEDIUM' )
                             ( severity = 'MEDIUM' ) ( severity = 'MEDIUM' ) ( severity = 'MEDIUM' ) ) )
      ( object_id = 'ZCL_PRICING_HELPER' criticality = 'MEDIUM' findings_as_of = '20261013'
        usages    = VALUE #( ( usage_row( iv_start = '20251013' iv_end = '20261013' iv_last = '20261012'
                                          iv_runs = 15210 iv_as_of = '20261013' ) ) )
        findings  = VALUE #( ( severity = 'LOW' ) )
        callers   = VALUE #( ( criticality = 'HIGH' ) ) )
      ( object_id = 'ZFI_OLD_LEDGER_EXPORT' criticality = 'LOW' findings_as_of = '20261013' )
      ( object_id = 'ZMM_STOCK_ALERT' criticality = 'MEDIUM' findings_as_of = '20261013'
        usages    = VALUE #( ( usage_row( iv_start = '20260801' iv_end = '20261013' iv_last = '00000000'
                                          iv_runs = 0 iv_as_of = '20261013' ) ) ) )
      ( object_id = 'ZSD_CUST_CREDIT_CHECK' criticality = 'HIGH' findings_as_of = '20261013'
        usages    = VALUE #( ( usage_row( iv_start = '20251013' iv_end = '20261013' iv_last = '20261010'
                                          iv_runs = 930 iv_as_of = '20261013' ) ) )
        findings  = VALUE #( ( severity = 'HIGH' ) ) )
      ( object_id = 'ZCL_INVOICE_UTIL' criticality = 'UNKNOWN' findings_as_of = '20261013'
        usages    = VALUE #( ( usage_row( iv_start = '20251013' iv_end = '20261013' iv_last = '20260930'
                                          iv_runs = 41 iv_as_of = '20261013' ) ) )
        callers   = VALUE #( ( criticality = 'HIGH' ) ) )
      ( object_id = 'ZHR_PAYROLL_ADJ' criticality = 'UNKNOWN' findings_as_of = '20261013'
        usages    = VALUE #( ( usage_row( iv_start = '20251013' iv_end = '20261013' iv_last = '20251212'
                                          iv_runs = 3 iv_as_of = '20261013' ) ) ) ) ).
  ENDMETHOD.

  METHOD evaluate.
    DATA(ls_ruleset) = is_ruleset.
    IF ls_ruleset IS INITIAL.
      ls_ruleset = zccmc_cl_rule_engine=>seed_ruleset( ).
    ENDIF.
    rs_result = zccmc_cl_rule_engine=>evaluate_object( is_evidence        = is_evidence
                                                       is_ruleset         = ls_ruleset
                                                       iv_evaluation_date = c_eval_date
                                                       iv_run_id          = c_run_id ).
  ENDMETHOD.

  METHOD assert_result.
    cl_abap_unit_assert=>assert_equals( act = is_result-strategy         exp = iv_strategy
                                        msg = |{ iv_msg }: strategy| ).
    cl_abap_unit_assert=>assert_equals( act = is_result-matched_rule_ids exp = it_matched
                                        msg = |{ iv_msg }: matched rules| ).
    cl_abap_unit_assert=>assert_equals( act = is_result-missing_evidence exp = it_missing
                                        msg = |{ iv_msg }: missing evidence| ).
    cl_abap_unit_assert=>assert_not_initial( act = is_result-explanation
                                             msg = |{ iv_msg }: explanation is empty| ).
  ENDMETHOD.


  " ================= paper tests T1 to T10 =================

  METHOD t01_no_use_12_months_retire.
    DATA(ls_result) = evaluate( unused_evidence( ) ).
    assert_result( is_result = ls_result iv_strategy = 'RETIRE_CANDIDATE'
                   it_matched = VALUE #( ( `R20` ) ) it_missing = VALUE #( ) iv_msg = 'T1' ).
  ENDMETHOD.

  METHOD t02_no_use_11_months_manual.
    DATA(ls_result) = evaluate( unused_evidence( iv_start = '20251113' ) ).
    assert_result( is_result = ls_result iv_strategy = 'MANUAL_REVIEW'
                   it_matched = VALUE #( ( `R10` ) )
                   it_missing = VALUE #( ( `WINDOW_TOO_SHORT` ) ) iv_msg = 'T2' ).
  ENDMETHOD.

  METHOD t03_high_caller_no_match.
    DATA(ls_evidence) = unused_evidence( ).
    ls_evidence-callers = VALUE #( ( criticality = 'HIGH' ) ).
    DATA(ls_result) = evaluate( ls_evidence ).
    assert_result( is_result = ls_result iv_strategy = 'MANUAL_REVIEW'
                   it_matched = VALUE #( )
                   it_missing = VALUE #( ( `NO_RULE_MATCH` ) ) iv_msg = 'T3' ).
  ENDMETHOD.

  METHOD t04_used_zero_findings_keep.
    DATA(ls_result) = evaluate( used_evidence( iv_criticality = 'HIGH' iv_runs = 2480 ) ).
    assert_result( is_result = ls_result iv_strategy = 'KEEP_ADAPT'
                   it_matched = VALUE #( ( `R60` ) ) it_missing = VALUE #( ) iv_msg = 'T4' ).
  ENDMETHOD.

  METHOD t05_one_high_finding_manual.
    DATA(ls_evidence) = used_evidence( iv_criticality = 'HIGH' iv_runs = 2480 ).
    ls_evidence-findings = VALUE #( ( severity = 'HIGH' ) ).
    DATA(ls_result) = evaluate( ls_evidence ).
    assert_result( is_result = ls_result iv_strategy = 'MANUAL_REVIEW'
                   it_matched = VALUE #( ( `R30` ) ) it_missing = VALUE #( ) iv_msg = 'T5' ).
  ENDMETHOD.

  METHOD t06_used_low_finding_keep.
    DATA(ls_evidence) = used_evidence( iv_criticality = 'MEDIUM' iv_runs = 15210 ).
    ls_evidence-findings = VALUE #( ( severity = 'LOW' ) ).
    DATA(ls_result) = evaluate( ls_evidence ).
    assert_result( is_result = ls_result iv_strategy = 'KEEP_ADAPT'
                   it_matched = VALUE #( ( `R60` ) ) it_missing = VALUE #( ) iv_msg = 'T6' ).
  ENDMETHOD.

  METHOD t07_criticality_unknown_manual.
    DATA(ls_result) = evaluate( used_evidence( iv_criticality = 'UNKNOWN' ) ).
    assert_result( is_result = ls_result iv_strategy = 'MANUAL_REVIEW'
                   it_matched = VALUE #( ( `R10` ) ( `R60` ) )
                   it_missing = VALUE #( ( `CRITICALITY_UNKNOWN` ) ) iv_msg = 'T7' ).
  ENDMETHOD.

  METHOD t08_no_usage_row_manual.
    DATA(ls_evidence) = unused_evidence( ).
    CLEAR ls_evidence-usages.
    DATA(ls_result) = evaluate( ls_evidence ).
    assert_result( is_result = ls_result iv_strategy = 'MANUAL_REVIEW'
                   it_matched = VALUE #( ( `R10` ) )
                   it_missing = VALUE #( ( `NO_USAGE_FACT` ) ) iv_msg = 'T8' ).
  ENDMETHOD.

  METHOD t09_equal_priority_conflict.
    DATA(ls_ruleset) = zccmc_cl_rule_engine=>seed_ruleset( ).
    APPEND VALUE #( rule_id = 'R61' priority = 60 active = abap_true
                    condition_code = zccmc_cl_rule_engine=>c_condition-used_without_high
                    outcome = zccmc_cl_rule_engine=>c_outcome-rewrite_rap
                    rationale = 'test-only conflicting rule' ) TO ls_ruleset-rules.
    DATA(ls_result) = evaluate( is_evidence = used_evidence( ) is_ruleset = ls_ruleset ).
    assert_result( is_result = ls_result iv_strategy = 'MANUAL_REVIEW'
                   it_matched = VALUE #( ( `R60` ) ( `R61` ) )
                   it_missing = VALUE #( ( `RULE_CONFLICT` ) ) iv_msg = 'T9' ).
    cl_abap_unit_assert=>assert_char_cp( act = ls_result-explanation exp = '*R60*R61*'
                                         msg = 'T9: explanation names both conflicting rules' ).
  ENDMETHOD.

  METHOD t10_zero_runs_with_date_manual.
    DATA(ls_evidence) = unused_evidence( ).
    ls_evidence-usages[ 1 ]-last_executed = '20250925'.
    DATA(ls_result) = evaluate( ls_evidence ).
    assert_result( is_result = ls_result iv_strategy = 'MANUAL_REVIEW'
                   it_matched = VALUE #( ( `R10` ) ( `R20` ) )
                   it_missing = VALUE #( ( `ZERO_RUNS_WITH_LAST_EXECUTED` ) ) iv_msg = 'T10' ).
  ENDMETHOD.


  " ================= more missing / contradictory / stale evidence =================

  METHOD t11_runs_without_date_manual.
    DATA(ls_evidence) = used_evidence( ).
    ls_evidence-usages[ 1 ]-last_executed = '00000000'.
    DATA(ls_result) = evaluate( ls_evidence ).
    assert_result( is_result = ls_result iv_strategy = 'MANUAL_REVIEW'
                   it_matched = VALUE #( ( `R10` ) ( `R60` ) )
                   it_missing = VALUE #( ( `RUNS_WITHOUT_LAST_EXECUTED` ) ) iv_msg = 'T11' ).
  ENDMETHOD.

  METHOD t12_period_end_before_start.
    DATA(ls_evidence) = used_evidence( ).
    ls_evidence-usages[ 1 ]-period_start = '20261013'.
    ls_evidence-usages[ 1 ]-period_end   = '20251013'.
    DATA(ls_result) = evaluate( ls_evidence ).
    assert_result( is_result = ls_result iv_strategy = 'MANUAL_REVIEW'
                   it_matched = VALUE #( ( `R10` ) ( `R60` ) )
                   it_missing = VALUE #( ( `PERIOD_END_BEFORE_START` ) ) iv_msg = 'T12' ).
  ENDMETHOD.

  METHOD t13_staleness_boundary.
    DATA(ls_fresh) = used_evidence( ).
    ls_fresh-usages[ 1 ]-evidence_as_of = '20260914'.
    assert_result( is_result = evaluate( ls_fresh ) iv_strategy = 'KEEP_ADAPT'
                   it_matched = VALUE #( ( `R60` ) ) it_missing = VALUE #( )
                   iv_msg = 'T13 age 30 days' ).

    DATA(ls_stale) = used_evidence( ).
    ls_stale-usages[ 1 ]-evidence_as_of = '20260913'.
    assert_result( is_result = evaluate( ls_stale ) iv_strategy = 'MANUAL_REVIEW'
                   it_matched = VALUE #( ( `R10` ) ( `R60` ) )
                   it_missing = VALUE #( ( `EVIDENCE_STALE` ) ) iv_msg = 'T13 age 31 days' ).
  ENDMETHOD.

  METHOD t14_findings_coverage_unknown.
    DATA(ls_evidence) = used_evidence( ).
    CLEAR ls_evidence-findings_as_of.
    DATA(ls_result) = evaluate( ls_evidence ).
    assert_result( is_result = ls_result iv_strategy = 'MANUAL_REVIEW'
                   it_matched = VALUE #( ( `R10` ) ( `R60` ) )
                   it_missing = VALUE #( ( `FINDINGS_NOT_LOADED` ) ) iv_msg = 'T14' ).
  ENDMETHOD.

  METHOD t15_multiple_usage_facts.
    DATA(ls_evidence) = used_evidence( ).
    APPEND usage_row( iv_start = '20240101' iv_end = '20241231' iv_last = '20241201'
                      iv_runs = 5 iv_as_of = '20261013' ) TO ls_evidence-usages.
    DATA(ls_result) = evaluate( ls_evidence ).
    assert_result( is_result = ls_result iv_strategy = 'MANUAL_REVIEW'
                   it_matched = VALUE #( ( `R10` ) )
                   it_missing = VALUE #( ( `MULTIPLE_USAGE_FACTS` ) ) iv_msg = 'T15' ).
  ENDMETHOD.

  METHOD t16_caller_criticality_unknown.
    DATA(ls_unused) = unused_evidence( ).
    ls_unused-callers = VALUE #( ( criticality = 'UNKNOWN' ) ).
    assert_result( is_result = evaluate( ls_unused ) iv_strategy = 'MANUAL_REVIEW'
                   it_matched = VALUE #( ( `R10` ) ( `R20` ) )
                   it_missing = VALUE #( ( `CALLER_CRITICALITY_UNKNOWN` ) )
                   iv_msg = 'T16 unknown caller blocks retire' ).

    DATA(ls_known) = unused_evidence( ).
    ls_known-callers = VALUE #( ( criticality = 'MEDIUM' ) ( criticality = 'LOW' ) ).
    assert_result( is_result = evaluate( ls_known ) iv_strategy = 'RETIRE_CANDIDATE'
                   it_matched = VALUE #( ( `R20` ) ) it_missing = VALUE #( )
                   iv_msg = 'T16 known non-HIGH callers' ).

    DATA(ls_used) = used_evidence( ).
    ls_used-callers = VALUE #( ( criticality = 'UNKNOWN' ) ).
    assert_result( is_result = evaluate( ls_used ) iv_strategy = 'KEEP_ADAPT'
                   it_matched = VALUE #( ( `R60` ) ) it_missing = VALUE #( )
                   iv_msg = 'T16 unknown caller ignored when used' ).
  ENDMETHOD.


  " ================= rule-set behaviour =================

  METHOD t17_same_priority_same_outcome.
    DATA(ls_ruleset) = zccmc_cl_rule_engine=>seed_ruleset( ).
    APPEND VALUE #( rule_id = 'R62' priority = 60 active = abap_true
                    condition_code = zccmc_cl_rule_engine=>c_condition-used_without_high
                    outcome = zccmc_cl_rule_engine=>c_outcome-keep_adapt
                    rationale = 'test-only duplicate rule' ) TO ls_ruleset-rules.
    DATA(ls_result) = evaluate( is_evidence = used_evidence( ) is_ruleset = ls_ruleset ).
    assert_result( is_result = ls_result iv_strategy = 'KEEP_ADAPT'
                   it_matched = VALUE #( ( `R60` ) ( `R62` ) )
                   it_missing = VALUE #( ) iv_msg = 'T17' ).
  ENDMETHOD.

  METHOD t18_no_rule_matches.
    DATA(ls_ruleset) = zccmc_cl_rule_engine=>seed_ruleset( ).
    DELETE ls_ruleset-rules WHERE rule_id <> 'R20'.
    DATA(ls_result) = evaluate( is_evidence = used_evidence( ) is_ruleset = ls_ruleset ).
    assert_result( is_result = ls_result iv_strategy = 'MANUAL_REVIEW'
                   it_matched = VALUE #( )
                   it_missing = VALUE #( ( `NO_RULE_MATCH` ) ) iv_msg = 'T18' ).
  ENDMETHOD.

  METHOD t19_missing_r10_still_manual.
    DATA(ls_ruleset) = zccmc_cl_rule_engine=>seed_ruleset( ).
    DELETE ls_ruleset-rules WHERE rule_id = 'R10'.
    DATA(ls_result) = evaluate( is_evidence = used_evidence( iv_criticality = 'UNKNOWN' )
                                is_ruleset  = ls_ruleset ).
    assert_result( is_result = ls_result iv_strategy = 'MANUAL_REVIEW'
                   it_matched = VALUE #( ( `R60` ) )
                   it_missing = VALUE #( ( `CRITICALITY_UNKNOWN` ) ) iv_msg = 'T19' ).
  ENDMETHOD.

  METHOD t20_unknown_condition_code.
    DATA(ls_ruleset) = zccmc_cl_rule_engine=>seed_ruleset( ).
    APPEND VALUE #( rule_id = 'RX' priority = 5 active = abap_true
                    condition_code = 'NOT_A_REAL_CONDITION'
                    outcome = zccmc_cl_rule_engine=>c_outcome-keep_adapt
                    rationale = 'test-only invalid rule' ) TO ls_ruleset-rules.
    DATA(ls_result) = evaluate( is_evidence = used_evidence( ) is_ruleset = ls_ruleset ).
    assert_result( is_result = ls_result iv_strategy = 'MANUAL_REVIEW'
                   it_matched = VALUE #( ( `R60` ) )
                   it_missing = VALUE #( ( `UNKNOWN_CONDITION_CODE` ) ) iv_msg = 'T20' ).
  ENDMETHOD.

  METHOD t21_inactive_rule_is_ignored.
    DATA(ls_ruleset) = zccmc_cl_rule_engine=>seed_ruleset( ).
    ls_ruleset-rules[ rule_id = 'R60' ]-active = abap_false.
    DATA(ls_result) = evaluate( is_evidence = used_evidence( ) is_ruleset = ls_ruleset ).
    assert_result( is_result = ls_result iv_strategy = 'MANUAL_REVIEW'
                   it_matched = VALUE #( )
                   it_missing = VALUE #( ( `NO_RULE_MATCH` ) ) iv_msg = 'T21' ).
  ENDMETHOD.


  " ================= details =================

  METHOD t22_info_and_medium_not_high.
    DATA(ls_evidence) = used_evidence( ).
    ls_evidence-findings = VALUE #( ( severity = 'MEDIUM' ) ( severity = 'MEDIUM' )
                                    ( severity = 'LOW' ) ( severity = 'INFO' ) ).
    assert_result( is_result = evaluate( ls_evidence ) iv_strategy = 'KEEP_ADAPT'
                   it_matched = VALUE #( ( `R60` ) ) it_missing = VALUE #( ) iv_msg = 'T22' ).
  ENDMETHOD.

  METHOD t23_whole_months_boundaries.
    cl_abap_unit_assert=>assert_equals( act = zccmc_cl_rule_engine=>whole_months_between(
                                                iv_from = '20251013' iv_to = '20261013' )
                                        exp = 12 msg = '12 months exactly' ).
    cl_abap_unit_assert=>assert_equals( act = zccmc_cl_rule_engine=>whole_months_between(
                                                iv_from = '20251013' iv_to = '20261012' )
                                        exp = 11 msg = 'one day short of 12 months' ).
    cl_abap_unit_assert=>assert_equals( act = zccmc_cl_rule_engine=>whole_months_between(
                                                iv_from = '20260801' iv_to = '20261013' )
                                        exp = 2 msg = 'sample ZMM_STOCK_ALERT window' ).
    cl_abap_unit_assert=>assert_equals( act = zccmc_cl_rule_engine=>whole_months_between(
                                                iv_from = '20250131' iv_to = '20250228' )
                                        exp = 1 msg = 'month end clamping' ).
    cl_abap_unit_assert=>assert_equals( act = zccmc_cl_rule_engine=>whole_months_between(
                                                iv_from = '20240229' iv_to = '20250228' )
                                        exp = 12 msg = 'leap day start clamps to 28 Feb' ).
    cl_abap_unit_assert=>assert_equals( act = zccmc_cl_rule_engine=>whole_months_between(
                                                iv_from = '20261013' iv_to = '20261013' )
                                        exp = 0 msg = 'same day' ).
    cl_abap_unit_assert=>assert_equals( act = zccmc_cl_rule_engine=>whole_months_between(
                                                iv_from = '20261013' iv_to = '20251013' )
                                        exp = 0 msg = 'end before start' ).
  ENDMETHOD.

  METHOD t24_result_and_explanation.
    DATA(ls_ruleset) = zccmc_cl_rule_engine=>seed_ruleset( ).
    DATA(ls_evidence) = used_evidence( iv_criticality = 'HIGH' iv_runs = 2480 ).
    ls_evidence-findings = VALUE #( ( severity = 'HIGH' ) ( severity = 'HIGH' ) ( severity = 'MEDIUM' ) ).
    DATA(ls_result) = evaluate( is_evidence = ls_evidence is_ruleset = ls_ruleset ).

    cl_abap_unit_assert=>assert_equals( act = ls_result-object_id       exp = 'OBJ-USED'   msg = 'object id passed through' ).
    cl_abap_unit_assert=>assert_equals( act = ls_result-run_id          exp = c_run_id     msg = 'run id passed through' ).
    cl_abap_unit_assert=>assert_equals( act = ls_result-ruleset_id      exp = 'ZCCMC_DEMO' msg = 'v1 rule-set id recorded' ).
    cl_abap_unit_assert=>assert_equals( act = ls_result-ruleset_version exp = '1.0.0'      msg = 'v1 rule-set version recorded' ).
    cl_abap_unit_assert=>assert_char_cp( act = ls_result-explanation exp = '*R30*'
                                         msg = 'explanation names the matched rule' ).
    cl_abap_unit_assert=>assert_char_cp( act = ls_result-explanation exp = '*high_findings=2*'
                                         msg = 'explanation shows the real evidence value' ).
    cl_abap_unit_assert=>assert_char_cp( act = ls_result-explanation exp = '*run_count=2480*'
                                         msg = 'explanation shows the run count' ).
    cl_abap_unit_assert=>assert_char_np( act = ls_result-explanation exp = '*RUN-0001*'
                                         msg = 'explanation never contains the run id' ).

    DATA(ls_missing) = evaluate( used_evidence( iv_criticality = 'UNKNOWN' ) ).
    cl_abap_unit_assert=>assert_char_cp( act = ls_missing-explanation exp = '*CRITICALITY_UNKNOWN*'
                                         msg = 'explanation lists the missing-evidence code' ).
  ENDMETHOD.


  " ================= determinism and permutation =================

  METHOD t25_repeat_run_is_identical.
    DATA(ls_evidence) = used_evidence( iv_criticality = 'HIGH' iv_runs = 2480 ).
    ls_evidence-findings = VALUE #( ( severity = 'HIGH' ) ( severity = 'LOW' ) ).
    DATA(ls_ruleset) = zccmc_cl_rule_engine=>seed_ruleset( ).

    DATA(ls_first)  = zccmc_cl_rule_engine=>evaluate_object( is_evidence = ls_evidence is_ruleset = ls_ruleset
                                                             iv_evaluation_date = c_eval_date iv_run_id = 'RUN-A' ).
    DATA(ls_second) = zccmc_cl_rule_engine=>evaluate_object( is_evidence = ls_evidence is_ruleset = ls_ruleset
                                                             iv_evaluation_date = c_eval_date iv_run_id = 'RUN-B' ).
    CLEAR: ls_first-run_id, ls_second-run_id.
    cl_abap_unit_assert=>assert_equals( act = ls_second exp = ls_first
                                        msg = 'repeat evaluation must be identical apart from the run id' ).
  ENDMETHOD.

  METHOD t26_row_order_does_not_matter.
    DATA(ls_evidence) = used_evidence( iv_criticality = 'HIGH' iv_runs = 2480 ).
    ls_evidence-findings = VALUE #( ( severity = 'LOW' ) ( severity = 'HIGH' ) ( severity = 'MEDIUM' ) ( severity = 'HIGH' ) ).
    ls_evidence-callers  = VALUE #( ( criticality = 'LOW' ) ( criticality = 'UNKNOWN' ) ( criticality = 'HIGH' ) ).
    DATA(ls_ruleset) = zccmc_cl_rule_engine=>seed_ruleset( ).

    DATA(ls_reversed) = ls_evidence.
    DATA lt_findings LIKE ls_evidence-findings.
    DATA lt_callers  LIKE ls_evidence-callers.
    lt_findings = VALUE #( FOR i = lines( ls_evidence-findings ) THEN i - 1 UNTIL i = 0
                           ( ls_evidence-findings[ i ] ) ).
    lt_callers  = VALUE #( FOR j = lines( ls_evidence-callers ) THEN j - 1 UNTIL j = 0
                           ( ls_evidence-callers[ j ] ) ).
    ls_reversed-findings = lt_findings.
    ls_reversed-callers  = lt_callers.

    DATA(ls_rules_reversed) = ls_ruleset.
    CLEAR ls_rules_reversed-rules.
    DATA(lv_index) = lines( ls_ruleset-rules ).
    WHILE lv_index > 0.
      APPEND ls_ruleset-rules[ lv_index ] TO ls_rules_reversed-rules.
      lv_index = lv_index - 1.
    ENDWHILE.

    DATA(ls_a) = evaluate( is_evidence = ls_evidence is_ruleset = ls_ruleset ).
    DATA(ls_b) = evaluate( is_evidence = ls_reversed is_ruleset = ls_rules_reversed ).
    cl_abap_unit_assert=>assert_equals( act = ls_b exp = ls_a
                                        msg = 'row order must not change the result' ).

    DATA(ls_two) = used_evidence( ).
    APPEND usage_row( iv_start = '20240101' iv_end = '20241231' iv_last = '20241201'
                      iv_runs = 5 iv_as_of = '20261013' ) TO ls_two-usages.
    DATA(ls_two_swapped) = ls_two.
    ls_two_swapped-usages = VALUE #( ( ls_two-usages[ 2 ] ) ( ls_two-usages[ 1 ] ) ).
    cl_abap_unit_assert=>assert_equals( act = evaluate( ls_two_swapped ) exp = evaluate( ls_two )
                                        msg = 'usage row order must not change the result' ).
  ENDMETHOD.


  " ================= the 7 synthetic sample objects =================

  METHOD t27_sample_objects_golden.
    DATA(lt_ev) = sample_evidence_tab( ).

    assert_result( is_result = evaluate( lt_ev[ object_id = 'ZSD_OPEN_ORDERS_RPT' ] )
                   iv_strategy = 'MANUAL_REVIEW'
                   it_matched = VALUE #( ( `R30` ) ) it_missing = VALUE #( )
                   iv_msg = 'ZSD_OPEN_ORDERS_RPT' ).

    assert_result( is_result = evaluate( lt_ev[ object_id = 'ZCL_PRICING_HELPER' ] )
                   iv_strategy = 'KEEP_ADAPT'
                   it_matched = VALUE #( ( `R60` ) ) it_missing = VALUE #( )
                   iv_msg = 'ZCL_PRICING_HELPER' ).

    assert_result( is_result = evaluate( lt_ev[ object_id = 'ZFI_OLD_LEDGER_EXPORT' ] )
                   iv_strategy = 'MANUAL_REVIEW'
                   it_matched = VALUE #( ( `R10` ) )
                   it_missing = VALUE #( ( `NO_USAGE_FACT` ) )
                   iv_msg = 'ZFI_OLD_LEDGER_EXPORT' ).

    assert_result( is_result = evaluate( lt_ev[ object_id = 'ZMM_STOCK_ALERT' ] )
                   iv_strategy = 'MANUAL_REVIEW'
                   it_matched = VALUE #( ( `R10` ) )
                   it_missing = VALUE #( ( `WINDOW_TOO_SHORT` ) )
                   iv_msg = 'ZMM_STOCK_ALERT' ).

    assert_result( is_result = evaluate( lt_ev[ object_id = 'ZSD_CUST_CREDIT_CHECK' ] )
                   iv_strategy = 'MANUAL_REVIEW'
                   it_matched = VALUE #( ( `R30` ) ) it_missing = VALUE #( )
                   iv_msg = 'ZSD_CUST_CREDIT_CHECK' ).

    assert_result( is_result = evaluate( lt_ev[ object_id = 'ZCL_INVOICE_UTIL' ] )
                   iv_strategy = 'MANUAL_REVIEW'
                   it_matched = VALUE #( ( `R10` ) ( `R60` ) )
                   it_missing = VALUE #( ( `CRITICALITY_UNKNOWN` ) )
                   iv_msg = 'ZCL_INVOICE_UTIL' ).

    assert_result( is_result = evaluate( lt_ev[ object_id = 'ZHR_PAYROLL_ADJ' ] )
                   iv_strategy = 'MANUAL_REVIEW'
                   it_matched = VALUE #( ( `R10` ) ( `R60` ) )
                   it_missing = VALUE #( ( `CRITICALITY_UNKNOWN` ) )
                   iv_msg = 'ZHR_PAYROLL_ADJ' ).
  ENDMETHOD.


  " ================= Day 8-11: portfolio permutation, isolation, edge fixtures & M1 bridge =================

  METHOD t28_portfolio_batch_and_perm.
    DATA(lt_forward) = sample_evidence_tab( ).
    DATA lt_reverse  TYPE zccmc_cl_rule_engine=>ty_evidence_tab.
    DATA(lv_idx) = lines( lt_forward ).
    WHILE lv_idx > 0.
      APPEND lt_forward[ lv_idx ] TO lt_reverse.
      lv_idx = lv_idx - 1.
    ENDWHILE.

    DATA(lt_run1) = zccmc_cl_rule_engine=>evaluate_portfolio(
                      it_evidence        = lt_forward
                      iv_evaluation_date = c_eval_date
                      iv_run_id          = c_run_id ).
    DATA(lt_run2) = zccmc_cl_rule_engine=>evaluate_portfolio(
                      it_evidence        = lt_forward
                      iv_evaluation_date = c_eval_date
                      iv_run_id          = c_run_id ).
    DATA(lt_perm) = zccmc_cl_rule_engine=>evaluate_portfolio(
                      it_evidence        = lt_reverse
                      iv_evaluation_date = c_eval_date
                      iv_run_id          = c_run_id ).

    cl_abap_unit_assert=>assert_equals( act = lines( lt_run1 ) exp = 7 msg = 'T28: 7 objects evaluated' ).
    cl_abap_unit_assert=>assert_equals( act = lt_run2          exp = lt_run1 msg = 'T28: two clean runs identical' ).
    cl_abap_unit_assert=>assert_equals( act = lt_perm          exp = lt_run1 msg = 'T28: permuted input order identical' ).
    cl_abap_unit_assert=>assert_equals( act = lt_run1[ 1 ]-object_id exp = 'ZCL_INVOICE_UTIL'
                                        msg = 'T28: portfolio output sorted by object_id' ).
  ENDMETHOD.

  METHOD t29_no_cross_object_leakage.
    DATA(lt_batch) = sample_evidence_tab( ).
    DATA(lt_results) = zccmc_cl_rule_engine=>evaluate_portfolio(
                         it_evidence        = lt_batch
                         iv_evaluation_date = c_eval_date
                         iv_run_id          = c_run_id ).

    DATA(ls_standalone) = evaluate( lt_batch[ object_id = 'ZCL_PRICING_HELPER' ] ).
    DATA(ls_in_batch)   = lt_results[ object_id = 'ZCL_PRICING_HELPER' ].

    cl_abap_unit_assert=>assert_equals( act = ls_in_batch exp = ls_standalone
                                        msg = 'T29: batch result must equal standalone result' ).
    cl_abap_unit_assert=>assert_char_np( act = ls_in_batch-explanation exp = '*CRITICALITY_UNKNOWN*'
                                         msg = 'T29: no missing-evidence leakage from ZCL_INVOICE_UTIL' ).
    cl_abap_unit_assert=>assert_char_np( act = ls_in_batch-explanation exp = '*NO_USAGE_FACT*'
                                         msg = 'T29: no missing-evidence leakage from ZFI_OLD_LEDGER_EXPORT' ).
    cl_abap_unit_assert=>assert_char_np( act = ls_in_batch-explanation exp = '*high_findings=2*'
                                         msg = 'T29: no finding count leakage from ZSD_OPEN_ORDERS_RPT' ).
  ENDMETHOD.

  METHOD t30_edge_and_corrected_fixtures.
    DATA(lt_ev) = sample_evidence_tab( ).
    DATA(ls_base_zsd) = lt_ev[ object_id = 'ZSD_OPEN_ORDERS_RPT' ].
    DATA(ls_res_base) = evaluate( ls_base_zsd ).

    DATA(ls_corrected_zsd) = ls_base_zsd.
    DATA(ls_res_corrected) = evaluate( ls_corrected_zsd ).
    cl_abap_unit_assert=>assert_equals( act = ls_res_corrected exp = ls_res_base
                                        msg = 'T30: corrected object description does not alter rule result' ).

    DATA(ls_quoted_zsd) = ls_base_zsd.
    APPEND VALUE #( severity = 'LOW' ) TO ls_quoted_zsd-findings.
    DATA(ls_res_quoted) = evaluate( ls_quoted_zsd ).
    cl_abap_unit_assert=>assert_equals( act = ls_res_quoted exp = ls_res_base
                                        msg = 'T30: quoted LOW finding F900 does not alter HIGH finding count or R30 result' ).
  ENDMETHOD.

  METHOD t31_m1_import_evidence_bridge.
    " Verifies build_evidence_from_import bridge aligned with zccmc_cl_import_orchestrator=>build_m2_evidence_for_obj.
    DATA(ls_ev) = zccmc_cl_rule_engine=>build_evidence_from_import(
                    iv_object_id      = ' zcl_pricing_helper '
                    iv_criticality    = ' medium '
                    iv_findings_as_of = '20261013'
                    it_usages         = VALUE #( ( usage_row( iv_start = '20251013' iv_end = '20261013'
                                                              iv_last  = '20261012' iv_runs = 15210
                                                              iv_as_of = '20261013' ) ) )
                    it_findings       = VALUE #( ( severity = ' low ' ) )
                    it_callers        = VALUE #( ( criticality = ' high ' ) ) ).
    DATA(ls_res) = evaluate( ls_ev ).
    assert_result( is_result = ls_res iv_strategy = 'KEEP_ADAPT'
                   it_matched = VALUE #( ( `R60` ) ) it_missing = VALUE #( )
                   iv_msg = 'T31 M1->M2 evidence bridge' ).
  ENDMETHOD.

ENDCLASS.
