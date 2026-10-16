"! Deterministic rule engine for the Clean Core Migration Cockpit (Member 2 — v1.0.0 Frozen).
"!
"! DEMO / SYNTHETIC project policy. Rules, thresholds and wording follow docs/rules-spec.md
"! (v1.0.0) and docs/data-contract.md (v0.3) and are illustrative and configurable; a
"! migration/domain expert must validate them before any production use. They are project demo
"! policy, not official SAP migration guidance. This is a deterministic rules engine, not AI/ML.
"!
"! INTEGRATION WITH MEMBER 1 (Day 1–11 Complete):
"! - Consumes structured evidence built from Member 1's persistence & CDS layer
"!   (ZCCMC_I_CustomObject, ZCCMC_I_UsageFact, ZCCMC_I_Finding, ZCCMC_I_Dependency) via
"!   zccmc_cl_import_orchestrator=>build_m2_evidence_for_obj or
"!   zccmc_cl_rule_engine=>build_evidence_from_import.
"! - Plain ABAP types (string, d, i, utclong, abap_boolean) are used at the evaluation boundary
"!   so this class compiles and runs in ABAP Unit independently of DB/UI state.
"!
"! Design guarantees:
"! - Zero database access, zero system clock access, zero UUID generation. The caller supplies
"!   the evidence, the rule set (optional; defaults to seed_ruleset v1.0.0), the evaluation date,
"!   the recommendation run ID, and the run timestamp.
"! - Strict determinism & permutation invariance: same evidence + same rule set + same evaluation
"!   date = byte-for-byte identical result tuple (strategy, matched_rule_ids, missing_evidence,
"!   explanation, ruleset_id, ruleset_version), regardless of input row order or rule row order.
"! - Cross-object isolation: each object evaluation clears all internal state; unrelated records
"!   in a portfolio batch can never leak into another object's facts, outcome, or explanation.
"! - Hard safety invariant: any missing, unknown, stale, or contradictory evidence ALWAYS produces
"!   MANUAL_REVIEW in code, even if rule R10 is removed or deactivated in a custom rule set.
CLASS zccmc_cl_rule_engine DEFINITION
  PUBLIC
  FINAL
  CREATE PUBLIC.

  PUBLIC SECTION.
    CONSTANTS c_default_ruleset_id      TYPE string VALUE 'ZCCMC_DEMO'.
    CONSTANTS c_default_ruleset_version TYPE string VALUE '1.0.0'.

    CONSTANTS:
      BEGIN OF c_outcome,
        keep_adapt       TYPE string VALUE 'KEEP_ADAPT',
        rewrite_rap      TYPE string VALUE 'REWRITE_RAP',
        retire_candidate TYPE string VALUE 'RETIRE_CANDIDATE',
        side_by_side_btp TYPE string VALUE 'SIDE_BY_SIDE_BTP',
        manual_review    TYPE string VALUE 'MANUAL_REVIEW',
      END OF c_outcome.

    "! Reason codes returned in MissingEvidence (frozen v1.0.0 contract).
    CONSTANTS:
      BEGIN OF c_reason,
        no_usage_fact              TYPE string VALUE 'NO_USAGE_FACT',
        multiple_usage_facts       TYPE string VALUE 'MULTIPLE_USAGE_FACTS',
        period_end_before_start    TYPE string VALUE 'PERIOD_END_BEFORE_START',
        window_too_short           TYPE string VALUE 'WINDOW_TOO_SHORT',
        evidence_stale             TYPE string VALUE 'EVIDENCE_STALE',
        zero_runs_with_date        TYPE string VALUE 'ZERO_RUNS_WITH_LAST_EXECUTED',
        runs_without_date          TYPE string VALUE 'RUNS_WITHOUT_LAST_EXECUTED',
        criticality_unknown        TYPE string VALUE 'CRITICALITY_UNKNOWN',
        findings_not_loaded        TYPE string VALUE 'FINDINGS_NOT_LOADED',
        caller_criticality_unknown TYPE string VALUE 'CALLER_CRITICALITY_UNKNOWN',
        rule_conflict              TYPE string VALUE 'RULE_CONFLICT',
        no_rule_match              TYPE string VALUE 'NO_RULE_MATCH',
        unknown_condition_code     TYPE string VALUE 'UNKNOWN_CONDITION_CODE',
      END OF c_reason.

    "! Condition codes a rule record can reference (maps to docs/rules-spec.md section 5).
    CONSTANTS:
      BEGIN OF c_condition,
        evidence_problem  TYPE string VALUE 'EVIDENCE_PROBLEM',          "R10
        retire_no_use     TYPE string VALUE 'NO_USE_COMPLETE_WINDOW',    "R20
        used_with_high    TYPE string VALUE 'USED_WITH_HIGH_FINDING',    "R30
        used_without_high TYPE string VALUE 'USED_WITHOUT_HIGH_FINDING', "R60
      END OF c_condition.

    TYPES ty_code_tab TYPE STANDARD TABLE OF string WITH EMPTY KEY.

    TYPES:
      BEGIN OF ty_usage,
        period_start   TYPE d,
        period_end     TYPE d,
        last_executed  TYPE d,      "initial = blank in the CSV
        run_count      TYPE i,
        evidence_as_of TYPE d,
      END OF ty_usage,
      ty_usage_tab TYPE STANDARD TABLE OF ty_usage WITH EMPTY KEY.

    TYPES:
      BEGIN OF ty_finding,
        severity TYPE string,       "HIGH | MEDIUM | LOW | INFO
      END OF ty_finding,
      ty_finding_tab TYPE STANDARD TABLE OF ty_finding WITH EMPTY KEY.

    "! One row per object that has a dependency pointing at the evaluated object.
    TYPES:
      BEGIN OF ty_caller,
        criticality TYPE string,    "criticality of the calling object
      END OF ty_caller,
      ty_caller_tab TYPE STANDARD TABLE OF ty_caller WITH EMPTY KEY.

    TYPES:
      BEGIN OF ty_evidence,
        object_id      TYPE string, "ObjectUUID or business key identifier, passed through unchanged
        criticality    TYPE string, "HIGH | MEDIUM | LOW | UNKNOWN (blank = UNKNOWN)
        findings_as_of TYPE d,      "initial = findings coverage unknown (contract v0.3)
        usages         TYPE ty_usage_tab,
        findings       TYPE ty_finding_tab,
        callers        TYPE ty_caller_tab,
      END OF ty_evidence.

    TYPES:
      BEGIN OF ty_rule,
        rule_id        TYPE string,
        priority       TYPE i,      "lower number wins
        active         TYPE abap_boolean,
        condition_code TYPE string, "one of c_condition
        outcome        TYPE string, "one of c_outcome
        rationale      TYPE string,
      END OF ty_rule,
      ty_rule_tab TYPE STANDARD TABLE OF ty_rule WITH EMPTY KEY.

    TYPES:
      BEGIN OF ty_params,
        min_window_months      TYPE i, "illustrative 12
        max_evidence_age_days  TYPE i, "illustrative 30
        high_finding_min_count TYPE i, "illustrative 1
      END OF ty_params.

    TYPES:
      BEGIN OF ty_ruleset,
        ruleset_id TYPE string,
        version    TYPE string,
        params     TYPE ty_params,
        rules      TYPE ty_rule_tab,
      END OF ty_ruleset.

    TYPES:
      BEGIN OF ty_result,
        object_id        TYPE string,
        run_id           TYPE string,
        strategy         TYPE string,
        ruleset_id       TYPE string,
        ruleset_version  TYPE string,
        explanation      TYPE string,
        missing_evidence TYPE ty_code_tab,
        matched_rule_ids TYPE ty_code_tab,
        run_timestamp    TYPE utclong,
      END OF ty_result,
      ty_result_tab   TYPE STANDARD TABLE OF ty_result   WITH EMPTY KEY,
      ty_evidence_tab TYPE STANDARD TABLE OF ty_evidence WITH EMPTY KEY.

    "! Frozen v1.0.0 seed rule set from docs/rules-spec.md section 5 (R10, R20, R30, R60).
    CLASS-METHODS seed_ruleset
      RETURNING VALUE(rs_ruleset) TYPE ty_ruleset.

    "! Build normalized ty_evidence from Member 1 imported object, usage, finding, and caller rows
    "! (aligned with zccmc_cl_import_orchestrator=>build_m2_evidence_for_obj).
    CLASS-METHODS build_evidence_from_import
      IMPORTING iv_object_id      TYPE string
                iv_criticality    TYPE string OPTIONAL
                iv_findings_as_of TYPE d OPTIONAL
                it_usages         TYPE ty_usage_tab OPTIONAL
                it_findings       TYPE ty_finding_tab OPTIONAL
                it_callers        TYPE ty_caller_tab OPTIONAL
      RETURNING VALUE(rs_evidence) TYPE ty_evidence.

    "! Whole calendar months from iv_from to iv_to: the largest n such that
    "! iv_from + n months (day clamped to month end) is not after iv_to.
    "! Returns 0 when iv_to is before iv_from.
    CLASS-METHODS whole_months_between
      IMPORTING iv_from          TYPE d
                iv_to            TYPE d
      RETURNING VALUE(rv_months) TYPE i.

    "! Evaluate one object. iv_run_id and iv_run_timestamp are copied into the result and
    "! never used in the logic or in the explanation. If is_ruleset is omitted/initial,
    "! the frozen v1.0.0 seed_ruleset is used.
    CLASS-METHODS evaluate_object
      IMPORTING is_evidence        TYPE ty_evidence
                is_ruleset         TYPE ty_ruleset OPTIONAL
                iv_evaluation_date TYPE d
                iv_run_id          TYPE string OPTIONAL
                iv_run_timestamp   TYPE utclong OPTIONAL
      RETURNING VALUE(rs_result)   TYPE ty_result.

    "! Evaluate a portfolio batch deterministically. Input row order never changes output order,
    "! and unrelated objects in the batch never leak state into each other's explanations.
    CLASS-METHODS evaluate_portfolio
      IMPORTING it_evidence        TYPE ty_evidence_tab
                is_ruleset         TYPE ty_ruleset OPTIONAL
                iv_evaluation_date TYPE d
                iv_run_id          TYPE string OPTIONAL
                iv_run_timestamp   TYPE utclong OPTIONAL
      RETURNING VALUE(rt_results)  TYPE ty_result_tab.

  PRIVATE SECTION.
    TYPES:
      BEGIN OF ty_facts,
        usage_count     TYPE i,
        run_count       TYPE i,
        window_valid    TYPE abap_boolean,
        window_months   TYPE i,
        has_high_caller TYPE abap_boolean,
        unknown_callers TYPE i,
        high_findings   TYPE i,
        findings_known  TYPE abap_boolean,
        criticality     TYPE string,
        last_executed   TYPE d,
        evidence_as_of  TYPE d,
      END OF ty_facts.

    CLASS-METHODS assess_evidence
      IMPORTING is_evidence        TYPE ty_evidence
                is_params          TYPE ty_params
                iv_evaluation_date TYPE d
      EXPORTING es_facts           TYPE ty_facts
                et_missing         TYPE ty_code_tab.

    CLASS-METHODS rule_matches
      IMPORTING is_rule       TYPE ty_rule
                is_facts      TYPE ty_facts
                is_params     TYPE ty_params
                it_missing    TYPE ty_code_tab
      EXPORTING ev_matches    TYPE abap_boolean
                ev_known_code TYPE abap_boolean.

    CLASS-METHODS resolve_matches
      IMPORTING it_matches  TYPE ty_rule_tab
      EXPORTING ev_strategy TYPE string
                ev_reason   TYPE string
                ev_priority TYPE i.

    CLASS-METHODS build_explanation
      IMPORTING is_facts            TYPE ty_facts
                is_result           TYPE ty_result
                it_matches          TYPE ty_rule_tab
                iv_priority         TYPE i
                iv_evidence_problem TYPE abap_boolean
                iv_reason           TYPE string
      RETURNING VALUE(rv_text)      TYPE string.

    CLASS-METHODS last_day_of_month
      IMPORTING iv_year       TYPE i
                iv_month      TYPE i
      RETURNING VALUE(rv_day) TYPE i.

    CLASS-METHODS add_months
      IMPORTING iv_date        TYPE d
                iv_months      TYPE i
      RETURNING VALUE(rv_date) TYPE d.

    CLASS-METHODS date_text
      IMPORTING iv_date        TYPE d
      RETURNING VALUE(rv_text) TYPE string.
ENDCLASS.


CLASS zccmc_cl_rule_engine IMPLEMENTATION.

  METHOD seed_ruleset.
    rs_ruleset-ruleset_id = c_default_ruleset_id.
    rs_ruleset-version    = c_default_ruleset_version.
    rs_ruleset-params-min_window_months      = 12.
    rs_ruleset-params-max_evidence_age_days  = 30.
    rs_ruleset-params-high_finding_min_count = 1.
    rs_ruleset-rules = VALUE #(
      ( rule_id = 'R10' priority = 10 active = abap_true
        condition_code = c_condition-evidence_problem
        outcome = c_outcome-manual_review
        rationale = 'Evidence is missing, stale, unknown or contradictory; a human must decide.' )
      ( rule_id = 'R20' priority = 20 active = abap_true
        condition_code = c_condition-retire_no_use
        outcome = c_outcome-retire_candidate
        rationale = 'No runs over a complete observation window and no HIGH-criticality caller; retirement candidate, the owner must confirm.' )
      ( rule_id = 'R30' priority = 30 active = abap_true
        condition_code = c_condition-used_with_high
        outcome = c_outcome-manual_review
        rationale = 'The object is used and has HIGH-severity findings; a human must assess the impact.' )
      ( rule_id = 'R60' priority = 60 active = abap_true
        condition_code = c_condition-used_without_high
        outcome = c_outcome-keep_adapt
        rationale = 'The object is used and has no HIGH-severity findings; keep and adapt.' ) ).
  ENDMETHOD.


  METHOD build_evidence_from_import.
    CLEAR rs_evidence.
    rs_evidence-object_id      = condense( iv_object_id ).
    rs_evidence-criticality    = to_upper( condense( iv_criticality ) ).
    IF rs_evidence-criticality <> 'HIGH' AND rs_evidence-criticality <> 'MEDIUM'
       AND rs_evidence-criticality <> 'LOW'.
      rs_evidence-criticality = 'UNKNOWN'.
    ENDIF.
    rs_evidence-findings_as_of = iv_findings_as_of.
    rs_evidence-usages         = it_usages.
    LOOP AT it_findings INTO DATA(ls_finding).
      APPEND VALUE #( severity = to_upper( condense( ls_finding-severity ) ) ) TO rs_evidence-findings.
    ENDLOOP.
    LOOP AT it_callers INTO DATA(ls_caller).
      DATA(lv_crit) = to_upper( condense( ls_caller-criticality ) ).
      IF lv_crit <> 'HIGH' AND lv_crit <> 'MEDIUM' AND lv_crit <> 'LOW'.
        lv_crit = 'UNKNOWN'.
      ENDIF.
      APPEND VALUE #( criticality = lv_crit ) TO rs_evidence-callers.
    ENDLOOP.
  ENDMETHOD.


  METHOD last_day_of_month.
    CASE iv_month.
      WHEN 1 OR 3 OR 5 OR 7 OR 8 OR 10 OR 12.
        rv_day = 31.
      WHEN 4 OR 6 OR 9 OR 11.
        rv_day = 30.
      WHEN 2.
        IF iv_year MOD 400 = 0 OR ( iv_year MOD 4 = 0 AND iv_year MOD 100 <> 0 ).
          rv_day = 29.
        ELSE.
          rv_day = 28.
        ENDIF.
    ENDCASE.
  ENDMETHOD.


  METHOD add_months.
    DATA(lv_year)  = CONV i( iv_date(4) ).
    DATA(lv_month) = CONV i( iv_date+4(2) ).
    DATA(lv_day)   = CONV i( iv_date+6(2) ).

    DATA(lv_index)     = lv_year * 12 + ( lv_month - 1 ) + iv_months.
    DATA(lv_new_year)  = lv_index DIV 12.
    DATA(lv_new_month) = lv_index MOD 12 + 1.
    DATA(lv_last)      = last_day_of_month( iv_year = lv_new_year iv_month = lv_new_month ).
    IF lv_day > lv_last.
      lv_day = lv_last.
    ENDIF.

    rv_date = |{ lv_new_year WIDTH = 4 ALIGN = RIGHT PAD = '0' }| &&
              |{ lv_new_month WIDTH = 2 ALIGN = RIGHT PAD = '0' }| &&
              |{ lv_day WIDTH = 2 ALIGN = RIGHT PAD = '0' }|.
  ENDMETHOD.


  METHOD whole_months_between.
    IF iv_from IS INITIAL OR iv_to IS INITIAL OR iv_to < iv_from.
      rv_months = 0.
      RETURN.
    ENDIF.

    DATA(lv_estimate) = ( CONV i( iv_to(4) ) - CONV i( iv_from(4) ) ) * 12
                      + ( CONV i( iv_to+4(2) ) - CONV i( iv_from+4(2) ) ).
    IF lv_estimate < 0.
      lv_estimate = 0.
    ENDIF.
    IF add_months( iv_date = iv_from iv_months = lv_estimate ) > iv_to.
      lv_estimate = lv_estimate - 1.
    ENDIF.
    rv_months = nmax( val1 = lv_estimate val2 = 0 ).
  ENDMETHOD.


  METHOD date_text.
    IF iv_date IS INITIAL.
      rv_text = 'none'.
    ELSE.
      rv_text = |{ iv_date DATE = ISO }|.
    ENDIF.
  ENDMETHOD.


  METHOD assess_evidence.
    CLEAR: es_facts, et_missing.

    es_facts-criticality = to_upper( condense( is_evidence-criticality ) ).
    IF es_facts-criticality <> 'HIGH' AND es_facts-criticality <> 'MEDIUM'
       AND es_facts-criticality <> 'LOW'.
      es_facts-criticality = 'UNKNOWN'.
    ENDIF.

    es_facts-usage_count = lines( is_evidence-usages ).

    " ---- usage evidence (spec sections 3 and 4) ----
    IF es_facts-usage_count = 0.
      APPEND c_reason-no_usage_fact TO et_missing.
    ELSEIF es_facts-usage_count > 1.
      " Safe default (C1): when multiple usage rows are supplied for one object, do not guess.
      APPEND c_reason-multiple_usage_facts TO et_missing.
    ELSE.
      DATA(ls_usage) = is_evidence-usages[ 1 ].
      es_facts-run_count      = ls_usage-run_count.
      es_facts-last_executed  = ls_usage-last_executed.
      es_facts-evidence_as_of = ls_usage-evidence_as_of.

      IF ls_usage-period_end < ls_usage-period_start.
        es_facts-window_valid = abap_false.
        APPEND c_reason-period_end_before_start TO et_missing.
      ELSE.
        es_facts-window_valid  = abap_true.
        es_facts-window_months = whole_months_between( iv_from = ls_usage-period_start
                                                       iv_to   = ls_usage-period_end ).
        IF es_facts-window_months < is_params-min_window_months.
          APPEND c_reason-window_too_short TO et_missing.
        ENDIF.
      ENDIF.

      IF ls_usage-evidence_as_of IS INITIAL.
        APPEND c_reason-evidence_stale TO et_missing.
      ELSE.
        " exactly max_evidence_age_days old is still fresh; older is stale
        DATA(lv_age_days) = CONV i( iv_evaluation_date - ls_usage-evidence_as_of ).
        IF lv_age_days > is_params-max_evidence_age_days.
          APPEND c_reason-evidence_stale TO et_missing.
        ENDIF.
      ENDIF.

      IF ls_usage-run_count = 0 AND ls_usage-last_executed IS NOT INITIAL.
        APPEND c_reason-zero_runs_with_date TO et_missing.
      ENDIF.
      IF ls_usage-run_count > 0 AND ls_usage-last_executed IS INITIAL.
        APPEND c_reason-runs_without_date TO et_missing.
      ENDIF.
    ENDIF.

    " ---- criticality ----
    IF es_facts-criticality = 'UNKNOWN'.
      APPEND c_reason-criticality_unknown TO et_missing.
    ENDIF.

    " ---- findings coverage and HIGH count ----
    es_facts-findings_known = xsdbool( is_evidence-findings_as_of IS NOT INITIAL ).
    IF es_facts-findings_known = abap_false.
      APPEND c_reason-findings_not_loaded TO et_missing.
    ENDIF.
    LOOP AT is_evidence-findings INTO DATA(ls_finding).
      IF to_upper( condense( ls_finding-severity ) ) = 'HIGH'.
        es_facts-high_findings = es_facts-high_findings + 1.
      ENDIF.
    ENDLOOP.

    " ---- callers (any dependency type; conservative v1 contract, C3/C4) ----
    LOOP AT is_evidence-callers INTO DATA(ls_caller).
      DATA(lv_caller_crit) = to_upper( condense( ls_caller-criticality ) ).
      IF lv_caller_crit = 'HIGH'.
        es_facts-has_high_caller = abap_true.
      ELSEIF lv_caller_crit <> 'MEDIUM' AND lv_caller_crit <> 'LOW'.
        es_facts-unknown_callers = es_facts-unknown_callers + 1.
      ENDIF.
    ENDLOOP.
    " Unknown caller criticality blocks R20 only on the retirement path (no runs).
    IF es_facts-usage_count = 1 AND es_facts-run_count = 0
       AND es_facts-has_high_caller = abap_false AND es_facts-unknown_callers > 0.
      APPEND c_reason-caller_criticality_unknown TO et_missing.
    ENDIF.
  ENDMETHOD.


  METHOD rule_matches.
    ev_matches    = abap_false.
    ev_known_code = abap_true.

    DATA(lv_cond) = to_upper( condense( is_rule-condition_code ) ).

    CASE lv_cond.
      WHEN c_condition-evidence_problem.
        " R10: any missing, incomplete, stale, unknown or contradictory evidence.
        ev_matches = xsdbool( it_missing IS NOT INITIAL ).

      WHEN c_condition-retire_no_use.
        " R20: no runs, complete window, not called by a HIGH-criticality object.
        ev_matches = xsdbool( is_facts-usage_count = 1
                          AND is_facts-run_count = 0
                          AND is_facts-window_valid = abap_true
                          AND is_facts-window_months >= is_params-min_window_months
                          AND is_facts-has_high_caller = abap_false ).

      WHEN c_condition-used_with_high.
        " R30: used and at least the configured number of HIGH findings.
        ev_matches = xsdbool( is_facts-usage_count = 1
                          AND is_facts-run_count > 0
                          AND is_facts-high_findings >= is_params-high_finding_min_count ).

      WHEN c_condition-used_without_high.
        " R60: used and fewer HIGH findings than the configured number.
        ev_matches = xsdbool( is_facts-usage_count = 1
                          AND is_facts-run_count > 0
                          AND is_facts-high_findings < is_params-high_finding_min_count ).

      WHEN OTHERS.
        ev_known_code = abap_false.
    ENDCASE.
  ENDMETHOD.


  METHOD resolve_matches.
    " it_matches is sorted by priority, then rule id. Equal best priority with different
    " outcomes is a conflict; the engine never picks one arbitrarily.
    CLEAR: ev_strategy, ev_reason, ev_priority.

    IF it_matches IS INITIAL.
      ev_strategy = c_outcome-manual_review.
      ev_reason   = c_reason-no_rule_match.
      RETURN.
    ENDIF.

    ev_priority = it_matches[ 1 ]-priority.
    DATA(lv_first_outcome) = it_matches[ 1 ]-outcome.
    LOOP AT it_matches INTO DATA(ls_match) WHERE priority = ev_priority.
      IF ls_match-outcome <> lv_first_outcome.
        ev_strategy = c_outcome-manual_review.
        ev_reason   = c_reason-rule_conflict.
        RETURN.
      ENDIF.
    ENDLOOP.

    ev_strategy = lv_first_outcome.
  ENDMETHOD.


  METHOD build_explanation.
    DATA(lv_evidence) = |criticality={ is_facts-criticality }; usage_facts={ is_facts-usage_count }|.
    IF is_facts-usage_count = 1.
      lv_evidence = lv_evidence &&
        |; run_count={ is_facts-run_count }; window_months={ is_facts-window_months }| &&
        |; last_executed={ date_text( is_facts-last_executed ) }| &&
        |; evidence_as_of={ date_text( is_facts-evidence_as_of ) }|.
    ENDIF.
    lv_evidence = lv_evidence &&
      |; findings_known={ COND string( WHEN is_facts-findings_known = abap_true THEN 'yes' ELSE 'no' ) }| &&
      |; high_findings={ is_facts-high_findings }| &&
      |; high_criticality_caller={ COND string( WHEN is_facts-has_high_caller = abap_true THEN 'yes' ELSE 'no' ) }|.

    IF iv_evidence_problem = abap_true.
      rv_text = |{ is_result-strategy }: safe default because of: | &&
                |{ concat_lines_of( table = is_result-missing_evidence sep = `, ` ) }. Evidence: { lv_evidence }.|.
    ELSEIF iv_reason = c_reason-rule_conflict.
      DATA(lt_ids) = VALUE ty_code_tab( FOR m IN it_matches WHERE ( priority = iv_priority ) ( m-rule_id ) ).
      rv_text = |{ is_result-strategy }: active rules { concat_lines_of( table = lt_ids sep = `, ` ) } | &&
                |share priority { iv_priority } but give different outcomes; the engine does not pick one. | &&
                |Evidence: { lv_evidence }.|.
    ELSEIF iv_reason = c_reason-no_rule_match.
      rv_text = |{ is_result-strategy }: no active rule matched, so the safe default applies. Evidence: { lv_evidence }.|.
    ELSE.
      DATA(ls_winner) = it_matches[ 1 ].
      rv_text = |Rule { ls_winner-rule_id } (priority { iv_priority }): { ls_winner-rationale } | &&
                |Result { is_result-strategy }. Evidence: { lv_evidence }.|.
    ENDIF.
  ENDMETHOD.


  METHOD evaluate_object.
    CLEAR rs_result.

    DATA(ls_ruleset) = is_ruleset.
    IF ls_ruleset IS INITIAL.
      ls_ruleset = seed_ruleset( ).
    ENDIF.

    rs_result-object_id       = is_evidence-object_id.
    rs_result-run_id          = iv_run_id.
    rs_result-run_timestamp   = iv_run_timestamp.
    rs_result-ruleset_id      = ls_ruleset-ruleset_id.
    rs_result-ruleset_version = ls_ruleset-version.

    assess_evidence( EXPORTING is_evidence        = is_evidence
                               is_params          = ls_ruleset-params
                               iv_evaluation_date = iv_evaluation_date
                     IMPORTING es_facts           = DATA(ls_facts)
                               et_missing         = DATA(lt_missing) ).

    " ---- evaluate every active rule ----
    DATA lt_matches  TYPE ty_rule_tab.
    DATA lv_bad_code TYPE abap_boolean.
    LOOP AT ls_ruleset-rules INTO DATA(ls_rule) WHERE active = abap_true.
      ls_rule-rule_id        = to_upper( condense( ls_rule-rule_id ) ).
      ls_rule-condition_code = to_upper( condense( ls_rule-condition_code ) ).
      ls_rule-outcome        = to_upper( condense( ls_rule-outcome ) ).

      rule_matches( EXPORTING is_rule       = ls_rule
                              is_facts      = ls_facts
                              is_params     = ls_ruleset-params
                              it_missing    = lt_missing
                    IMPORTING ev_matches    = DATA(lv_match)
                              ev_known_code = DATA(lv_known) ).
      IF lv_known = abap_false.
        lv_bad_code = abap_true.
      ELSEIF lv_match = abap_true.
        APPEND ls_rule TO lt_matches.
      ENDIF.
    ENDLOOP.
    SORT lt_matches BY priority ASCENDING rule_id ASCENDING.

    rs_result-matched_rule_ids = VALUE #( FOR m IN lt_matches ( m-rule_id ) ).

    IF lv_bad_code = abap_true.
      " A rule set with an unknown condition code is invalid; stay safe with MANUAL_REVIEW.
      APPEND c_reason-unknown_condition_code TO lt_missing.
    ENDIF.

    " ---- decide ----
    resolve_matches( EXPORTING it_matches  = lt_matches
                     IMPORTING ev_strategy = DATA(lv_strategy)
                               ev_reason   = DATA(lv_reason)
                               ev_priority = DATA(lv_priority) ).

    DATA(lv_evidence_problem) = xsdbool( lt_missing IS NOT INITIAL ).
    IF lv_evidence_problem = abap_true.
      " Hard safety invariant: evidence problems always give MANUAL_REVIEW, even when no
      " rule R10 exists or is active in the rule set.
      rs_result-strategy = c_outcome-manual_review.
    ELSE.
      rs_result-strategy = lv_strategy.
      IF lv_reason IS NOT INITIAL.
        APPEND lv_reason TO lt_missing.
      ENDIF.
    ENDIF.
    rs_result-missing_evidence = lt_missing.

    rs_result-explanation = build_explanation( is_facts            = ls_facts
                                               is_result           = rs_result
                                               it_matches          = lt_matches
                                               iv_priority         = lv_priority
                                               iv_evidence_problem = lv_evidence_problem
                                               iv_reason           = lv_reason ).
  ENDMETHOD.


  METHOD evaluate_portfolio.
    DATA(ls_ruleset) = is_ruleset.
    IF ls_ruleset IS INITIAL.
      ls_ruleset = seed_ruleset( ).
    ENDIF.

    DATA(lt_sorted_evidence) = it_evidence.
    SORT lt_sorted_evidence BY object_id ASCENDING.

    LOOP AT lt_sorted_evidence INTO DATA(ls_evidence).
      APPEND evaluate_object( is_evidence        = ls_evidence
                              is_ruleset         = ls_ruleset
                              iv_evaluation_date = iv_evaluation_date
                              iv_run_id          = iv_run_id
                              iv_run_timestamp   = iv_run_timestamp ) TO rt_results.
    ENDLOOP.
  ENDMETHOD.

ENDCLASS.
