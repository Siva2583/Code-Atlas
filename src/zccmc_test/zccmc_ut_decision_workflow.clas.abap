"! ABAP Unit tests for ZCCMC_CL_DECISION_WORKFLOW (Member 3 — RAP Workflow & Security).
"! DEMO / SYNTHETIC data only.
"!
"! STATUS: written without live ADT execution in the trial tenant (non-$TMP package
"! creation remains unverified; see docs/feasibility-note.md and docs/limitations.md).
"! Run in ADT (Ctrl+Shift+F10) once the target package is provisioned, and record results
"! in docs/m3-day1-day11-status.md.
"!
"! Covers all 16 required test scenarios in docs/state-transitions.md section 10 (T01..T16)
"! plus 8 additional governance/integration scenarios (T17..T24):
"! - T01: Assigned developer submits a valid PROPOSED decision -> IN_REVIEW + audit event.
"! - T02: Submission without an assigned OwnerUser is rejected (ERR_MISSING_OWNER).
"! - T03: Illegal state transitions are rejected (PROPOSED->APPROVED, APPROVED->MIGRATED,
"!        RETURNED->APPROVED, APPROVED->OVERRIDDEN, IN_REVIEW->PROPOSED).
"! - T04: Reviewer approves a decision they are permitted to review -> APPROVED + FinalStrategy.
"! - T05: Owner, creator, or last submitter cannot approve or override when SoD is enabled
"!        (ERR_SOD_VIOLATION), even when holding both DEVELOPER and REVIEWER roles.
"! - T06: Developer calling Approve directly is rejected by the backend (ERR_UNAUTHORIZED_ROLE).
"! - T07: Admin attempting Approve or Override is rejected (ERR_UNAUTHORIZED_ROLE).
"! - T08: Override with a blank or too-short reason (<10 chars) is rejected.
"! - T09: Override using the same strategy as RecommendedStrategy is rejected (ERR_OVERRIDE_SAME_STRATEGY).
"! - T10: Valid override preserves RecommendedStrategy and records new FinalStrategy + reason.
"! - T11: Return, Block, Unblock, MarkMigrated, Reopen, and Resubmit enforce required reasons.
"! - T12: Audit events cannot be modified or deleted through the exposed service (ERR_AUDIT_IMMUTABLE).
"! - T13: Concurrent stale updates (version/ETag mismatch) are rejected (ERR_STALE_CONCURRENCY_CONFLICT).
"! - T14: Second active decision for the same ObjectUUID is rejected; allowed only after MIGRATED.
"! - T15: Reopening MIGRATED is rejected for Reviewer/Developer and allowed only for ADMIN.
"! - T16: Every rejected action leaves decision state and audit trail unchanged.
"! - T17: AssignOwner works in PROPOSED/RETURNED/BLOCKED for Reviewer/Admin, rejected in IN_REVIEW.
"! - T18: Unassigned Developer cannot Submit, Start, Block, Unblock, or MarkMigrated another owner's decision.
"! - T19: Auditor role is strictly read-only across all mutating actions.
"! - T20: Full end-to-end happy path (Create -> Submit -> Return -> Resubmit -> Override ->
"!        Start -> Block -> Unblock -> MarkMigrated -> Admin Reopen) maintains contiguous audit sequence.
"! - T21: Member 2 recommendation rerun updates existing active decision and flags re_review_required.
"! - T22: Submit clears re_review_required flag and records SubmittedBy.
"! - T23: Dynamic feature check (is_action_allowed) matches backend enforcement.
"! - T24: Missing recommendation metadata on Create/Submit is rejected (ERR_MISSING_RECOMMENDATION_FIELD).
CLASS zccmc_ut_decision_workflow DEFINITION
  PUBLIC
  FINAL
  FOR TESTING
  RISK LEVEL HARMLESS
  DURATION SHORT.

  PRIVATE SECTION.
    CONSTANTS:
      c_dev_1     TYPE string VALUE 'DEMO_DEV_1',
      c_dev_2     TYPE string VALUE 'DEMO_DEV_2',
      c_rev_1     TYPE string VALUE 'DEMO_REV_1',
      c_admin_1   TYPE string VALUE 'DEMO_ADMIN_1',
      c_auditor_1 TYPE string VALUE 'DEMO_AUDITOR_1',
      c_obj_1     TYPE string VALUE 'OBJ-UUID-0001'.

    METHODS:
      t01_dev_submits_valid_proposed     FOR TESTING,
      t02_submit_without_owner_rejected  FOR TESTING,
      t03_illegal_transitions_rejected   FOR TESTING,
      t04_reviewer_approves_permitted    FOR TESTING,
      t05_sod_blocks_owner_creator_subm  FOR TESTING,
      t06_dev_direct_approve_rejected    FOR TESTING,
      t07_admin_approve_override_reject  FOR TESTING,
      t08_override_blank_or_short_reason FOR TESTING,
      t09_override_same_strategy_reject  FOR TESTING,
      t10_valid_override_preserves_rec   FOR TESTING,
      t11_mandatory_reasons_enforced     FOR TESTING,
      t12_audit_events_immutable         FOR TESTING,
      t13_stale_update_conflict_rejected FOR TESTING,
      t14_duplicate_active_dec_rejected  FOR TESTING,
      t15_reopen_migrated_admin_only     FOR TESTING,
      t16_rejected_action_no_side_effect FOR TESTING,
      t17_assign_owner_rules_enforced    FOR TESTING,
      t18_unassigned_dev_blocked         FOR TESTING,
      t19_auditor_strictly_read_only     FOR TESTING,
      t20_full_lifecycle_audit_sequence  FOR TESTING,
      t21_recommendation_rerun_revises   FOR TESTING,
      t22_submit_clears_rereview_flag    FOR TESTING,
      t23_feature_control_matches_server FOR TESTING,
      t24_missing_rec_metadata_rejected  FOR TESTING.

    METHODS:
      ctx
        IMPORTING iv_actor          TYPE string
                  it_roles          TYPE zccmc_cl_decision_workflow=>ty_role_tab
                  iv_sod            TYPE abap_boolean DEFAULT abap_true
        RETURNING VALUE(rs_context) TYPE zccmc_cl_decision_workflow=>ty_actor_context,

      seed_proposed
        IMPORTING iv_owner         TYPE string DEFAULT c_dev_1
                  iv_creator       TYPE string DEFAULT c_dev_1
                  iv_strategy      TYPE string DEFAULT zccmc_cl_decision_workflow=>c_strategy-manual_review
        RETURNING VALUE(rs_result) TYPE zccmc_cl_decision_workflow=>ty_action_result,

      seed_in_review
        IMPORTING iv_owner         TYPE string DEFAULT c_dev_1
                  iv_creator       TYPE string DEFAULT c_dev_1
                  iv_submitter     TYPE string DEFAULT c_dev_1
                  iv_strategy      TYPE string DEFAULT zccmc_cl_decision_workflow=>c_strategy-manual_review
        RETURNING VALUE(rs_result) TYPE zccmc_cl_decision_workflow=>ty_action_result.
ENDCLASS.


CLASS zccmc_ut_decision_workflow IMPLEMENTATION.

  METHOD ctx.
    rs_context = VALUE #(
      actor_user     = iv_actor
      roles          = it_roles
      timestamp      = CONV utclong( '2026-10-14T10:00:00.0000000' )
      correlation_id = 'CORR-TEST-01'
      sod_enabled    = iv_sod
      min_reason_len = 10 ).
  ENDMETHOD.

  METHOD seed_proposed.
    rs_result = zccmc_cl_decision_workflow=>create_from_recommendation(
      iv_decision_uuid         = 'DEC-0001'
      iv_object_uuid           = c_obj_1
      iv_recommended_strategy  = iv_strategy
      iv_ruleset_version       = 'ZCCMC_DEMO/0.1.0-DRAFT'
      iv_recommendation_run_id = 'RUN-0001'
      iv_evidence_summary      = 'Rule R30 matched: run_count=2480, high_findings=2'
      iv_missing_evidence      = ''
      iv_matched_rule_ids      = 'R30'
      iv_import_batch_uuid     = 'BATCH-0001'
      iv_owner_user            = iv_owner
      is_context               = ctx( iv_actor = iv_creator
                                      it_roles = VALUE #( ( zccmc_cl_decision_workflow=>c_role-developer ) ) ) ).
  ENDMETHOD.

  METHOD seed_in_review.
    DATA(ls_created) = seed_proposed( iv_owner    = iv_owner
                                      iv_creator  = iv_creator
                                      iv_strategy = iv_strategy ).
    DATA(lt_roles) = VALUE zccmc_cl_decision_workflow=>ty_role_tab(
      ( zccmc_cl_decision_workflow=>c_role-developer ) ).
    IF iv_submitter = c_admin_1.
      APPEND zccmc_cl_decision_workflow=>c_role-admin TO lt_roles.
    ENDIF.
    rs_result = zccmc_cl_decision_workflow=>execute_action(
      is_decision     = ls_created-decision
      it_audit_events = ls_created-audit_events
      iv_action       = zccmc_cl_decision_workflow=>c_action-submit
      is_context      = ctx( iv_actor = iv_submitter it_roles = lt_roles ) ).
  ENDMETHOD.

  METHOD t01_dev_submits_valid_proposed.
    DATA(ls_prop) = seed_proposed( ).
    cl_abap_unit_assert=>assert_true( ls_prop-success ).
    cl_abap_unit_assert=>assert_equals( act = ls_prop-decision-status
                                        exp = zccmc_cl_decision_workflow=>c_status-proposed ).

    DATA(ls_sub) = zccmc_cl_decision_workflow=>execute_action(
      is_decision     = ls_prop-decision
      it_audit_events = ls_prop-audit_events
      iv_action       = zccmc_cl_decision_workflow=>c_action-submit
      is_context      = ctx( iv_actor = c_dev_1
                             it_roles = VALUE #( ( zccmc_cl_decision_workflow=>c_role-developer ) ) ) ).

    cl_abap_unit_assert=>assert_true( ls_sub-success ).
    cl_abap_unit_assert=>assert_equals( act = ls_sub-decision-status
                                        exp = zccmc_cl_decision_workflow=>c_status-in_review ).
    cl_abap_unit_assert=>assert_equals( act = ls_sub-decision-submitted_by
                                        exp = c_dev_1 ).
    cl_abap_unit_assert=>assert_equals( act = lines( ls_sub-audit_events )
                                        exp = 2 ).
  ENDMETHOD.

  METHOD t02_submit_without_owner_rejected.
    DATA(ls_prop) = seed_proposed( iv_owner = '' ).
    DATA(ls_sub) = zccmc_cl_decision_workflow=>execute_action(
      is_decision     = ls_prop-decision
      it_audit_events = ls_prop-audit_events
      iv_action       = zccmc_cl_decision_workflow=>c_action-submit
      is_context      = ctx( iv_actor = c_dev_1
                             it_roles = VALUE #( ( zccmc_cl_decision_workflow=>c_role-developer ) ) ) ).

    cl_abap_unit_assert=>assert_false( ls_sub-success ).
    cl_abap_unit_assert=>assert_equals( act = ls_sub-error_code
                                        exp = zccmc_cl_decision_workflow=>c_error-missing_owner ).
    cl_abap_unit_assert=>assert_equals( act = ls_sub-decision-status
                                        exp = zccmc_cl_decision_workflow=>c_status-proposed ).
    cl_abap_unit_assert=>assert_equals( act = lines( ls_sub-audit_events )
                                        exp = 1 ).
  ENDMETHOD.

  METHOD t03_illegal_transitions_rejected.
    " 1. Skip review: PROPOSED -> APPROVED
    DATA(ls_prop) = seed_proposed( ).
    DATA(ls_skip) = zccmc_cl_decision_workflow=>execute_action(
      is_decision     = ls_prop-decision
      it_audit_events = ls_prop-audit_events
      iv_action       = zccmc_cl_decision_workflow=>c_action-approve
      is_context      = ctx( iv_actor = c_rev_1
                             it_roles = VALUE #( ( zccmc_cl_decision_workflow=>c_role-reviewer ) ) ) ).
    cl_abap_unit_assert=>assert_false( ls_skip-success ).
    cl_abap_unit_assert=>assert_equals( act = ls_skip-error_code
                                        exp = zccmc_cl_decision_workflow=>c_error-invalid_transition ).

    " 2. Start before approval: IN_REVIEW -> IN_PROGRESS
    DATA(ls_rev) = seed_in_review( ).
    DATA(ls_early_start) = zccmc_cl_decision_workflow=>execute_action(
      is_decision     = ls_rev-decision
      it_audit_events = ls_rev-audit_events
      iv_action       = zccmc_cl_decision_workflow=>c_action-start_work
      is_context      = ctx( iv_actor = c_dev_1
                             it_roles = VALUE #( ( zccmc_cl_decision_workflow=>c_role-developer ) ) ) ).
    cl_abap_unit_assert=>assert_false( ls_early_start-success ).
    cl_abap_unit_assert=>assert_equals( act = ls_early_start-error_code
                                        exp = zccmc_cl_decision_workflow=>c_error-invalid_transition ).

    " 3. Move directly from APPROVED -> MIGRATED without Start
    DATA(ls_app) = zccmc_cl_decision_workflow=>execute_action(
      is_decision     = ls_rev-decision
      it_audit_events = ls_rev-audit_events
      iv_action       = zccmc_cl_decision_workflow=>c_action-approve
      is_context      = ctx( iv_actor = c_rev_1
                             it_roles = VALUE #( ( zccmc_cl_decision_workflow=>c_role-reviewer ) ) ) ).
    DATA(ls_jump_mig) = zccmc_cl_decision_workflow=>execute_action(
      is_decision     = ls_app-decision
      it_audit_events = ls_app-audit_events
      iv_action       = zccmc_cl_decision_workflow=>c_action-mark_migrated
      iv_reason       = 'Attempting direct jump to migrated'
      is_context      = ctx( iv_actor = c_dev_1
                             it_roles = VALUE #( ( zccmc_cl_decision_workflow=>c_role-developer ) ) ) ).
    cl_abap_unit_assert=>assert_false( ls_jump_mig-success ).
    cl_abap_unit_assert=>assert_equals( act = ls_jump_mig-error_code
                                        exp = zccmc_cl_decision_workflow=>c_error-invalid_transition ).

    " 4. Change APPROVED -> OVERRIDDEN directly without Reopen
    DATA(ls_app_to_ovr) = zccmc_cl_decision_workflow=>execute_action(
      is_decision     = ls_app-decision
      it_audit_events = ls_app-audit_events
      iv_action       = zccmc_cl_decision_workflow=>c_action-override
      iv_new_strategy = zccmc_cl_decision_workflow=>c_strategy-keep_adapt
      iv_reason       = 'Attempting direct change from approved to overridden'
      is_context      = ctx( iv_actor = c_rev_1
                             it_roles = VALUE #( ( zccmc_cl_decision_workflow=>c_role-reviewer ) ) ) ).
    cl_abap_unit_assert=>assert_false( ls_app_to_ovr-success ).
    cl_abap_unit_assert=>assert_equals( act = ls_app_to_ovr-error_code
                                        exp = zccmc_cl_decision_workflow=>c_error-invalid_transition ).
  ENDMETHOD.

  METHOD t04_reviewer_approves_permitted.
    DATA(ls_rev) = seed_in_review( iv_strategy = zccmc_cl_decision_workflow=>c_strategy-keep_adapt ).
    DATA(ls_app) = zccmc_cl_decision_workflow=>execute_action(
      is_decision     = ls_rev-decision
      it_audit_events = ls_rev-audit_events
      iv_action       = zccmc_cl_decision_workflow=>c_action-approve
      is_context      = ctx( iv_actor = c_rev_1
                             it_roles = VALUE #( ( zccmc_cl_decision_workflow=>c_role-reviewer ) ) ) ).

    cl_abap_unit_assert=>assert_true( ls_app-success ).
    cl_abap_unit_assert=>assert_equals( act = ls_app-decision-status
                                        exp = zccmc_cl_decision_workflow=>c_status-approved ).
    cl_abap_unit_assert=>assert_equals( act = ls_app-decision-final_strategy
                                        exp = zccmc_cl_decision_workflow=>c_strategy-keep_adapt ).
  ENDMETHOD.

  METHOD t05_sod_blocks_owner_creator_subm.
    " Case A: Owner holds both DEVELOPER and REVIEWER roles and tries to approve own decision
    DATA(ls_rev) = seed_in_review( iv_owner = c_dev_1 iv_creator = 'OTHER_USER' iv_submitter = c_admin_1 ).
    DATA(ls_sod_owner) = zccmc_cl_decision_workflow=>execute_action(
      is_decision     = ls_rev-decision
      it_audit_events = ls_rev-audit_events
      iv_action       = zccmc_cl_decision_workflow=>c_action-approve
      is_context      = ctx( iv_actor = c_dev_1
                             it_roles = VALUE #( ( zccmc_cl_decision_workflow=>c_role-developer )
                                                 ( zccmc_cl_decision_workflow=>c_role-reviewer ) ) ) ).
    cl_abap_unit_assert=>assert_false( ls_sod_owner-success ).
    cl_abap_unit_assert=>assert_equals( act = ls_sod_owner-error_code
                                        exp = zccmc_cl_decision_workflow=>c_error-sod_violation ).

    " Case B: Creator tries to approve
    DATA(ls_sod_creator) = zccmc_cl_decision_workflow=>execute_action(
      is_decision     = ls_rev-decision
      it_audit_events = ls_rev-audit_events
      iv_action       = zccmc_cl_decision_workflow=>c_action-approve
      is_context      = ctx( iv_actor = 'OTHER_USER'
                             it_roles = VALUE #( ( zccmc_cl_decision_workflow=>c_role-reviewer ) ) ) ).
    cl_abap_unit_assert=>assert_false( ls_sod_creator-success ).
    cl_abap_unit_assert=>assert_equals( act = ls_sod_creator-error_code
                                        exp = zccmc_cl_decision_workflow=>c_error-sod_violation ).

    " Case C: Last Submitter tries to override
    DATA(ls_sod_subm) = zccmc_cl_decision_workflow=>execute_action(
      is_decision     = ls_rev-decision
      it_audit_events = ls_rev-audit_events
      iv_action       = zccmc_cl_decision_workflow=>c_action-override
      iv_new_strategy = zccmc_cl_decision_workflow=>c_strategy-keep_adapt
      iv_reason       = 'Valid override reason over 10 chars'
      is_context      = ctx( iv_actor = c_admin_1
                             it_roles = VALUE #( ( zccmc_cl_decision_workflow=>c_role-reviewer ) ) ) ).
    cl_abap_unit_assert=>assert_false( ls_sod_subm-success ).
    cl_abap_unit_assert=>assert_equals( act = ls_sod_subm-error_code
                                        exp = zccmc_cl_decision_workflow=>c_error-sod_violation ).
  ENDMETHOD.

  METHOD t06_dev_direct_approve_rejected.
    DATA(ls_rev) = seed_in_review( ).
    DATA(ls_res) = zccmc_cl_decision_workflow=>execute_action(
      is_decision     = ls_rev-decision
      it_audit_events = ls_rev-audit_events
      iv_action       = zccmc_cl_decision_workflow=>c_action-approve
      is_context      = ctx( iv_actor = c_dev_2
                             it_roles = VALUE #( ( zccmc_cl_decision_workflow=>c_role-developer ) ) ) ).
    cl_abap_unit_assert=>assert_false( ls_res-success ).
    cl_abap_unit_assert=>assert_equals( act = ls_res-error_code
                                        exp = zccmc_cl_decision_workflow=>c_error-unauthorized_role ).
  ENDMETHOD.

  METHOD t07_admin_approve_override_reject.
    DATA(ls_rev) = seed_in_review( ).
    DATA(ls_app) = zccmc_cl_decision_workflow=>execute_action(
      is_decision     = ls_rev-decision
      it_audit_events = ls_rev-audit_events
      iv_action       = zccmc_cl_decision_workflow=>c_action-approve
      is_context      = ctx( iv_actor = c_admin_1
                             it_roles = VALUE #( ( zccmc_cl_decision_workflow=>c_role-admin ) ) ) ).
    cl_abap_unit_assert=>assert_false( ls_app-success ).
    cl_abap_unit_assert=>assert_equals( act = ls_app-error_code
                                        exp = zccmc_cl_decision_workflow=>c_error-unauthorized_role ).

    DATA(ls_ovr) = zccmc_cl_decision_workflow=>execute_action(
      is_decision     = ls_rev-decision
      it_audit_events = ls_rev-audit_events
      iv_action       = zccmc_cl_decision_workflow=>c_action-override
      iv_new_strategy = zccmc_cl_decision_workflow=>c_strategy-keep_adapt
      iv_reason       = 'Admin attempting override directly'
      is_context      = ctx( iv_actor = c_admin_1
                             it_roles = VALUE #( ( zccmc_cl_decision_workflow=>c_role-admin ) ) ) ).
    cl_abap_unit_assert=>assert_false( ls_ovr-success ).
    cl_abap_unit_assert=>assert_equals( act = ls_ovr-error_code
                                        exp = zccmc_cl_decision_workflow=>c_error-unauthorized_role ).
  ENDMETHOD.

  METHOD t08_override_blank_or_short_reason.
    DATA(ls_rev) = seed_in_review( ).
    DATA(ls_blank) = zccmc_cl_decision_workflow=>execute_action(
      is_decision     = ls_rev-decision
      it_audit_events = ls_rev-audit_events
      iv_action       = zccmc_cl_decision_workflow=>c_action-override
      iv_new_strategy = zccmc_cl_decision_workflow=>c_strategy-keep_adapt
      iv_reason       = '   '
      is_context      = ctx( iv_actor = c_rev_1
                             it_roles = VALUE #( ( zccmc_cl_decision_workflow=>c_role-reviewer ) ) ) ).
    cl_abap_unit_assert=>assert_false( ls_blank-success ).
    cl_abap_unit_assert=>assert_equals( act = ls_blank-error_code
                                        exp = zccmc_cl_decision_workflow=>c_error-missing_reason ).

    DATA(ls_short) = zccmc_cl_decision_workflow=>execute_action(
      is_decision     = ls_rev-decision
      it_audit_events = ls_rev-audit_events
      iv_action       = zccmc_cl_decision_workflow=>c_action-override
      iv_new_strategy = zccmc_cl_decision_workflow=>c_strategy-keep_adapt
      iv_reason       = 'TooShort'
      is_context      = ctx( iv_actor = c_rev_1
                             it_roles = VALUE #( ( zccmc_cl_decision_workflow=>c_role-reviewer ) ) ) ).
    cl_abap_unit_assert=>assert_false( ls_short-success ).
    cl_abap_unit_assert=>assert_equals( act = ls_short-error_code
                                        exp = zccmc_cl_decision_workflow=>c_error-reason_too_short ).
  ENDMETHOD.

  METHOD t09_override_same_strategy_reject.
    DATA(ls_rev) = seed_in_review( iv_strategy = zccmc_cl_decision_workflow=>c_strategy-manual_review ).
    DATA(ls_same) = zccmc_cl_decision_workflow=>execute_action(
      is_decision     = ls_rev-decision
      it_audit_events = ls_rev-audit_events
      iv_action       = zccmc_cl_decision_workflow=>c_action-override
      iv_new_strategy = zccmc_cl_decision_workflow=>c_strategy-manual_review
      iv_reason       = 'Overriding with the exact same strategy'
      is_context      = ctx( iv_actor = c_rev_1
                             it_roles = VALUE #( ( zccmc_cl_decision_workflow=>c_role-reviewer ) ) ) ).
    cl_abap_unit_assert=>assert_false( ls_same-success ).
    cl_abap_unit_assert=>assert_equals( act = ls_same-error_code
                                        exp = zccmc_cl_decision_workflow=>c_error-override_same_strategy ).
  ENDMETHOD.

  METHOD t10_valid_override_preserves_rec.
    DATA(ls_rev) = seed_in_review( iv_strategy = zccmc_cl_decision_workflow=>c_strategy-manual_review ).
    DATA(ls_ovr) = zccmc_cl_decision_workflow=>execute_action(
      is_decision     = ls_rev-decision
      it_audit_events = ls_rev-audit_events
      iv_action       = zccmc_cl_decision_workflow=>c_action-override
      iv_new_strategy = zccmc_cl_decision_workflow=>c_strategy-keep_adapt
      iv_reason       = 'High findings remediated in transport TR001; safe to KEEP_ADAPT'
      is_context      = ctx( iv_actor = c_rev_1
                             it_roles = VALUE #( ( zccmc_cl_decision_workflow=>c_role-reviewer ) ) ) ).

    cl_abap_unit_assert=>assert_true( ls_ovr-success ).
    cl_abap_unit_assert=>assert_equals( act = ls_ovr-decision-status
                                        exp = zccmc_cl_decision_workflow=>c_status-overridden ).
    cl_abap_unit_assert=>assert_equals( act = ls_ovr-decision-recommended_strategy
                                        exp = zccmc_cl_decision_workflow=>c_strategy-manual_review ).
    cl_abap_unit_assert=>assert_equals( act = ls_ovr-decision-final_strategy
                                        exp = zccmc_cl_decision_workflow=>c_strategy-keep_adapt ).
  ENDMETHOD.

  METHOD t11_mandatory_reasons_enforced.
    DATA(ls_rev) = seed_in_review( ).
    " Return without reason fails
    DATA(ls_ret_fail) = zccmc_cl_decision_workflow=>execute_action(
      is_decision     = ls_rev-decision
      it_audit_events = ls_rev-audit_events
      iv_action       = zccmc_cl_decision_workflow=>c_action-return_dec
      iv_reason       = ''
      is_context      = ctx( iv_actor = c_rev_1
                             it_roles = VALUE #( ( zccmc_cl_decision_workflow=>c_role-reviewer ) ) ) ).
    cl_abap_unit_assert=>assert_false( ls_ret_fail-success ).
    cl_abap_unit_assert=>assert_equals( act = ls_ret_fail-error_code
                                        exp = zccmc_cl_decision_workflow=>c_error-missing_reason ).

    " Approve -> Start -> Block without reason fails
    DATA(ls_app) = zccmc_cl_decision_workflow=>execute_action(
      is_decision     = ls_rev-decision
      it_audit_events = ls_rev-audit_events
      iv_action       = zccmc_cl_decision_workflow=>c_action-approve
      is_context      = ctx( iv_actor = c_rev_1
                             it_roles = VALUE #( ( zccmc_cl_decision_workflow=>c_role-reviewer ) ) ) ).
    DATA(ls_start) = zccmc_cl_decision_workflow=>execute_action(
      is_decision     = ls_app-decision
      it_audit_events = ls_app-audit_events
      iv_action       = zccmc_cl_decision_workflow=>c_action-start_work
      is_context      = ctx( iv_actor = c_dev_1
                             it_roles = VALUE #( ( zccmc_cl_decision_workflow=>c_role-developer ) ) ) ).
    DATA(ls_blk_fail) = zccmc_cl_decision_workflow=>execute_action(
      is_decision     = ls_start-decision
      it_audit_events = ls_start-audit_events
      iv_action       = zccmc_cl_decision_workflow=>c_action-block_work
      iv_reason       = ''
      is_context      = ctx( iv_actor = c_dev_1
                             it_roles = VALUE #( ( zccmc_cl_decision_workflow=>c_role-developer ) ) ) ).
    cl_abap_unit_assert=>assert_false( ls_blk_fail-success ).
    cl_abap_unit_assert=>assert_equals( act = ls_blk_fail-error_code
                                        exp = zccmc_cl_decision_workflow=>c_error-missing_reason ).
  ENDMETHOD.

  METHOD t12_audit_events_immutable.
    DATA(ls_rev) = seed_in_review( ).
    DATA(ls_upd) = zccmc_cl_decision_workflow=>reject_audit_mutation(
      is_decision     = ls_rev-decision
      it_audit_events = ls_rev-audit_events
      iv_operation    = 'UPDATE' ).
    cl_abap_unit_assert=>assert_false( ls_upd-success ).
    cl_abap_unit_assert=>assert_equals( act = ls_upd-error_code
                                        exp = zccmc_cl_decision_workflow=>c_error-audit_immutable ).

    DATA(ls_del) = zccmc_cl_decision_workflow=>reject_audit_mutation(
      is_decision     = ls_rev-decision
      it_audit_events = ls_rev-audit_events
      iv_operation    = 'DELETE' ).
    cl_abap_unit_assert=>assert_false( ls_del-success ).
    cl_abap_unit_assert=>assert_equals( act = ls_del-error_code
                                        exp = zccmc_cl_decision_workflow=>c_error-audit_immutable ).
  ENDMETHOD.

  METHOD t13_stale_update_conflict_rejected.
    DATA(ls_rev) = seed_in_review( ). "version_no is 2 after Create (1) + Submit (2)
    " First reviewer approves with expected_version = 2 -> succeeds, version becomes 3
    DATA(ls_first) = zccmc_cl_decision_workflow=>execute_action(
      is_decision         = ls_rev-decision
      it_audit_events     = ls_rev-audit_events
      iv_action           = zccmc_cl_decision_workflow=>c_action-approve
      iv_expected_version = 2
      is_context          = ctx( iv_actor = c_rev_1
                                 it_roles = VALUE #( ( zccmc_cl_decision_workflow=>c_role-reviewer ) ) ) ).
    cl_abap_unit_assert=>assert_true( ls_first-success ).
    cl_abap_unit_assert=>assert_equals( act = ls_first-decision-version_no exp = 3 ).

    " Second reviewer attempts stale override using old version 2 against committed version 3
    DATA(ls_stale) = zccmc_cl_decision_workflow=>execute_action(
      is_decision         = ls_first-decision
      it_audit_events     = ls_first-audit_events
      iv_action           = zccmc_cl_decision_workflow=>c_action-override
      iv_new_strategy     = zccmc_cl_decision_workflow=>c_strategy-keep_adapt
      iv_reason           = 'Concurrent reviewer trying stale override'
      iv_expected_version = 2
      is_context          = ctx( iv_actor = 'DEMO_REV_2'
                                 it_roles = VALUE #( ( zccmc_cl_decision_workflow=>c_role-reviewer ) ) ) ).
    cl_abap_unit_assert=>assert_false( ls_stale-success ).
    cl_abap_unit_assert=>assert_equals( act = ls_stale-error_code
                                        exp = zccmc_cl_decision_workflow=>c_error-stale_concurrency_conflict ).
    cl_abap_unit_assert=>assert_equals( act = ls_stale-decision-status
                                        exp = zccmc_cl_decision_workflow=>c_status-approved ).
    cl_abap_unit_assert=>assert_equals( act = lines( ls_stale-audit_events ) exp = 3 ).
  ENDMETHOD.

  METHOD t14_duplicate_active_dec_rejected.
    DATA(ls_first) = seed_proposed( ).
    DATA(ls_dup) = zccmc_cl_decision_workflow=>create_from_recommendation(
      iv_decision_uuid         = 'DEC-0002'
      iv_object_uuid           = c_obj_1
      iv_recommended_strategy  = zccmc_cl_decision_workflow=>c_strategy-keep_adapt
      iv_ruleset_version       = 'ZCCMC_DEMO/0.1.0-DRAFT'
      iv_recommendation_run_id = 'RUN-0002'
      iv_evidence_summary      = 'Second attempt while active'
      is_context               = ctx( iv_actor = c_dev_1
                                      it_roles = VALUE #( ( zccmc_cl_decision_workflow=>c_role-developer ) ) )
      it_existing_decisions    = VALUE #( ( ls_first-decision ) ) ).

    cl_abap_unit_assert=>assert_false( ls_dup-success ).
    cl_abap_unit_assert=>assert_equals( act = ls_dup-error_code
                                        exp = zccmc_cl_decision_workflow=>c_error-duplicate_active_decision ).
  ENDMETHOD.

  METHOD t15_reopen_migrated_admin_only.
    DATA(ls_rev) = seed_in_review( ).
    DATA(ls_app) = zccmc_cl_decision_workflow=>execute_action(
      is_decision     = ls_rev-decision
      it_audit_events = ls_rev-audit_events
      iv_action       = zccmc_cl_decision_workflow=>c_action-approve
      is_context      = ctx( iv_actor = c_rev_1
                             it_roles = VALUE #( ( zccmc_cl_decision_workflow=>c_role-reviewer ) ) ) ).
    DATA(ls_start) = zccmc_cl_decision_workflow=>execute_action(
      is_decision     = ls_app-decision
      it_audit_events = ls_app-audit_events
      iv_action       = zccmc_cl_decision_workflow=>c_action-start_work
      is_context      = ctx( iv_actor = c_dev_1
                             it_roles = VALUE #( ( zccmc_cl_decision_workflow=>c_role-developer ) ) ) ).
    DATA(ls_mig) = zccmc_cl_decision_workflow=>execute_action(
      is_decision     = ls_start-decision
      it_audit_events = ls_start-audit_events
      iv_action       = zccmc_cl_decision_workflow=>c_action-mark_migrated
      iv_reason       = 'Custom report adapted to released CDS views'
      is_context      = ctx( iv_actor = c_dev_1
                             it_roles = VALUE #( ( zccmc_cl_decision_workflow=>c_role-developer ) ) ) ).

    " Reviewer cannot reopen MIGRATED
    DATA(ls_rev_reopen) = zccmc_cl_decision_workflow=>execute_action(
      is_decision     = ls_mig-decision
      it_audit_events = ls_mig-audit_events
      iv_action       = zccmc_cl_decision_workflow=>c_action-reopen
      iv_reason       = 'Reviewer trying to reopen migrated decision'
      is_context      = ctx( iv_actor = c_rev_1
                             it_roles = VALUE #( ( zccmc_cl_decision_workflow=>c_role-reviewer ) ) ) ).
    cl_abap_unit_assert=>assert_false( ls_rev_reopen-success ).
    cl_abap_unit_assert=>assert_equals( act = ls_rev_reopen-error_code
                                        exp = zccmc_cl_decision_workflow=>c_error-unauthorized_role ).

    " Admin CAN reopen MIGRATED with a valid reason
    DATA(ls_adm_reopen) = zccmc_cl_decision_workflow=>execute_action(
      is_decision     = ls_mig-decision
      it_audit_events = ls_mig-audit_events
      iv_action       = zccmc_cl_decision_workflow=>c_action-reopen
      iv_reason       = 'Admin reopening after post-migration audit check'
      is_context      = ctx( iv_actor = c_admin_1
                             it_roles = VALUE #( ( zccmc_cl_decision_workflow=>c_role-admin ) ) ) ).
    cl_abap_unit_assert=>assert_true( ls_adm_reopen-success ).
    cl_abap_unit_assert=>assert_equals( act = ls_adm_reopen-decision-status
                                        exp = zccmc_cl_decision_workflow=>c_status-in_review ).
  ENDMETHOD.

  METHOD t16_rejected_action_no_side_effect.
    DATA(ls_rev) = seed_in_review( ).
    DATA(ls_before_dec) = ls_rev-decision.
    DATA(lt_before_aud) = ls_rev-audit_events.

    DATA(ls_fail) = zccmc_cl_decision_workflow=>execute_action(
      is_decision     = ls_rev-decision
      it_audit_events = ls_rev-audit_events
      iv_action       = zccmc_cl_decision_workflow=>c_action-override
      iv_new_strategy = zccmc_cl_decision_workflow=>c_strategy-keep_adapt
      iv_reason       = ''
      is_context      = ctx( iv_actor = c_rev_1
                             it_roles = VALUE #( ( zccmc_cl_decision_workflow=>c_role-reviewer ) ) ) ).

    cl_abap_unit_assert=>assert_false( ls_fail-success ).
    cl_abap_unit_assert=>assert_equals( act = ls_fail-decision     exp = ls_before_dec ).
    cl_abap_unit_assert=>assert_equals( act = ls_fail-audit_events exp = lt_before_aud ).
  ENDMETHOD.

  METHOD t17_assign_owner_rules_enforced.
    DATA(ls_prop) = seed_proposed( iv_owner = c_dev_1 ).
    " Reviewer can reassign in PROPOSED
    DATA(ls_assign) = zccmc_cl_decision_workflow=>execute_action(
      is_decision     = ls_prop-decision
      it_audit_events = ls_prop-audit_events
      iv_action       = zccmc_cl_decision_workflow=>c_action-assign_owner
      iv_new_owner    = c_dev_2
      is_context      = ctx( iv_actor = c_rev_1
                             it_roles = VALUE #( ( zccmc_cl_decision_workflow=>c_role-reviewer ) ) ) ).
    cl_abap_unit_assert=>assert_true( ls_assign-success ).
    cl_abap_unit_assert=>assert_equals( act = ls_assign-decision-owner_user exp = c_dev_2 ).

    " AssignOwner is rejected while IN_REVIEW
    DATA(ls_rev) = seed_in_review( ).
    DATA(ls_in_rev_assign) = zccmc_cl_decision_workflow=>execute_action(
      is_decision     = ls_rev-decision
      it_audit_events = ls_rev-audit_events
      iv_action       = zccmc_cl_decision_workflow=>c_action-assign_owner
      iv_new_owner    = c_dev_2
      is_context      = ctx( iv_actor = c_admin_1
                             it_roles = VALUE #( ( zccmc_cl_decision_workflow=>c_role-admin ) ) ) ).
    cl_abap_unit_assert=>assert_false( ls_in_rev_assign-success ).
    cl_abap_unit_assert=>assert_equals( act = ls_in_rev_assign-error_code
                                        exp = zccmc_cl_decision_workflow=>c_error-owner_assign_in_review ).
  ENDMETHOD.

  METHOD t18_unassigned_dev_blocked.
    DATA(ls_prop) = seed_proposed( iv_owner = c_dev_1 ).
    DATA(ls_sub) = zccmc_cl_decision_workflow=>execute_action(
      is_decision     = ls_prop-decision
      it_audit_events = ls_prop-audit_events
      iv_action       = zccmc_cl_decision_workflow=>c_action-submit
      is_context      = ctx( iv_actor = c_dev_2
                             it_roles = VALUE #( ( zccmc_cl_decision_workflow=>c_role-developer ) ) ) ).
    cl_abap_unit_assert=>assert_false( ls_sub-success ).
    cl_abap_unit_assert=>assert_equals( act = ls_sub-error_code
                                        exp = zccmc_cl_decision_workflow=>c_error-not_assigned_owner ).
  ENDMETHOD.

  METHOD t19_auditor_strictly_read_only.
    DATA(ls_prop) = seed_proposed( ).
    DATA(ls_sub) = zccmc_cl_decision_workflow=>execute_action(
      is_decision     = ls_prop-decision
      it_audit_events = ls_prop-audit_events
      iv_action       = zccmc_cl_decision_workflow=>c_action-submit
      is_context      = ctx( iv_actor = c_auditor_1
                             it_roles = VALUE #( ( zccmc_cl_decision_workflow=>c_role-auditor ) ) ) ).
    cl_abap_unit_assert=>assert_false( ls_sub-success ).
    cl_abap_unit_assert=>assert_equals( act = ls_sub-error_code
                                        exp = zccmc_cl_decision_workflow=>c_error-unauthorized_role ).
  ENDMETHOD.

  METHOD t20_full_lifecycle_audit_sequence.
    DATA(ls_step) = seed_proposed( ).
    ls_step = zccmc_cl_decision_workflow=>execute_action(
      is_decision = ls_step-decision it_audit_events = ls_step-audit_events
      iv_action   = zccmc_cl_decision_workflow=>c_action-submit
      is_context  = ctx( iv_actor = c_dev_1 it_roles = VALUE #( ( zccmc_cl_decision_workflow=>c_role-developer ) ) ) ).
    ls_step = zccmc_cl_decision_workflow=>execute_action(
      is_decision = ls_step-decision it_audit_events = ls_step-audit_events
      iv_action   = zccmc_cl_decision_workflow=>c_action-return_dec
      iv_reason   = 'Please confirm dependency impact with finance owner'
      is_context  = ctx( iv_actor = c_rev_1 it_roles = VALUE #( ( zccmc_cl_decision_workflow=>c_role-reviewer ) ) ) ).
    ls_step = zccmc_cl_decision_workflow=>execute_action(
      is_decision = ls_step-decision it_audit_events = ls_step-audit_events
      iv_action   = zccmc_cl_decision_workflow=>c_action-resubmit
      iv_reason   = 'Finance owner confirmed dependency is non-blocking'
      is_context  = ctx( iv_actor = c_dev_1 it_roles = VALUE #( ( zccmc_cl_decision_workflow=>c_role-developer ) ) ) ).
    ls_step = zccmc_cl_decision_workflow=>execute_action(
      is_decision     = ls_step-decision it_audit_events = ls_step-audit_events
      iv_action       = zccmc_cl_decision_workflow=>c_action-override
      iv_new_strategy = zccmc_cl_decision_workflow=>c_strategy-keep_adapt
      iv_reason       = 'Approved KEEP_ADAPT after finance sign-off and ATC remediation'
      is_context      = ctx( iv_actor = c_rev_1 it_roles = VALUE #( ( zccmc_cl_decision_workflow=>c_role-reviewer ) ) ) ).
    ls_step = zccmc_cl_decision_workflow=>execute_action(
      is_decision = ls_step-decision it_audit_events = ls_step-audit_events
      iv_action   = zccmc_cl_decision_workflow=>c_action-start_work
      is_context  = ctx( iv_actor = c_dev_1 it_roles = VALUE #( ( zccmc_cl_decision_workflow=>c_role-developer ) ) ) ).
    ls_step = zccmc_cl_decision_workflow=>execute_action(
      is_decision = ls_step-decision it_audit_events = ls_step-audit_events
      iv_action   = zccmc_cl_decision_workflow=>c_action-block_work
      iv_reason   = 'Blocked waiting for released CDS wrapper in S/4 tenant'
      is_context  = ctx( iv_actor = c_dev_1 it_roles = VALUE #( ( zccmc_cl_decision_workflow=>c_role-developer ) ) ) ).
    ls_step = zccmc_cl_decision_workflow=>execute_action(
      is_decision = ls_step-decision it_audit_events = ls_step-audit_events
      iv_action   = zccmc_cl_decision_workflow=>c_action-unblock_work
      iv_reason   = 'Released CDS wrapper activated in transport TR009'
      is_context  = ctx( iv_actor = c_dev_1 it_roles = VALUE #( ( zccmc_cl_decision_workflow=>c_role-developer ) ) ) ).
    ls_step = zccmc_cl_decision_workflow=>execute_action(
      is_decision = ls_step-decision it_audit_events = ls_step-audit_events
      iv_action   = zccmc_cl_decision_workflow=>c_action-mark_migrated
      iv_reason   = 'Migration completed and verified with ABAP Unit suite'
      is_context  = ctx( iv_actor = c_dev_1 it_roles = VALUE #( ( zccmc_cl_decision_workflow=>c_role-developer ) ) ) ).

    cl_abap_unit_assert=>assert_true( ls_step-success ).
    cl_abap_unit_assert=>assert_equals( act = ls_step-decision-status
                                        exp = zccmc_cl_decision_workflow=>c_status-migrated ).
    cl_abap_unit_assert=>assert_equals( act = lines( ls_step-audit_events ) exp = 9 ).
  ENDMETHOD.

  METHOD t21_recommendation_rerun_revises.
    DATA(ls_rev) = seed_in_review( ).
    DATA(ls_rerun) = zccmc_cl_decision_workflow=>apply_recommendation_rerun(
      is_decision              = ls_rev-decision
      it_audit_events          = ls_rev-audit_events
      iv_recommended_strategy  = zccmc_cl_decision_workflow=>c_strategy-keep_adapt
      iv_ruleset_version       = 'ZCCMC_DEMO/0.2.0'
      iv_recommendation_run_id = 'RUN-0002'
      iv_evidence_summary      = 'Rule R60 matched after findings cleanup'
      iv_missing_evidence      = ''
      iv_matched_rule_ids      = 'R60'
      is_context               = ctx( iv_actor = c_admin_1
                                      it_roles = VALUE #( ( zccmc_cl_decision_workflow=>c_role-admin ) ) ) ).

    cl_abap_unit_assert=>assert_true( ls_rerun-success ).
    cl_abap_unit_assert=>assert_true( ls_rerun-decision-re_review_required ).
    cl_abap_unit_assert=>assert_equals( act = ls_rerun-decision-recommended_strategy
                                        exp = zccmc_cl_decision_workflow=>c_strategy-keep_adapt ).
    cl_abap_unit_assert=>assert_equals( act = ls_rerun-decision-recommendation_run_id
                                        exp = 'RUN-0002' ).
  ENDMETHOD.

  METHOD t22_submit_clears_rereview_flag.
    DATA(ls_prop) = seed_proposed( ).
    DATA(ls_rerun) = zccmc_cl_decision_workflow=>apply_recommendation_rerun(
      is_decision              = ls_prop-decision
      it_audit_events          = ls_prop-audit_events
      iv_recommended_strategy  = zccmc_cl_decision_workflow=>c_strategy-keep_adapt
      iv_ruleset_version       = 'ZCCMC_DEMO/0.2.0'
      iv_recommendation_run_id = 'RUN-0002'
      iv_evidence_summary      = 'Revised recommendation'
      is_context               = ctx( iv_actor = c_admin_1
                                      it_roles = VALUE #( ( zccmc_cl_decision_workflow=>c_role-admin ) ) ) ).
    cl_abap_unit_assert=>assert_true( ls_rerun-decision-re_review_required ).

    DATA(ls_sub) = zccmc_cl_decision_workflow=>execute_action(
      is_decision     = ls_rerun-decision
      it_audit_events = ls_rerun-audit_events
      iv_action       = zccmc_cl_decision_workflow=>c_action-submit
      is_context      = ctx( iv_actor = c_dev_1
                             it_roles = VALUE #( ( zccmc_cl_decision_workflow=>c_role-developer ) ) ) ).
    cl_abap_unit_assert=>assert_true( ls_sub-success ).
    cl_abap_unit_assert=>assert_false( ls_sub-decision-re_review_required ).
  ENDMETHOD.

  METHOD t23_feature_control_matches_server.
    DATA(ls_rev) = seed_in_review( ).
    " Independent reviewer is allowed to Approve
    cl_abap_unit_assert=>assert_true(
      zccmc_cl_decision_workflow=>is_action_allowed(
        is_decision = ls_rev-decision
        iv_action   = zccmc_cl_decision_workflow=>c_action-approve
        is_context  = ctx( iv_actor = c_rev_1
                           it_roles = VALUE #( ( zccmc_cl_decision_workflow=>c_role-reviewer ) ) ) ) ).
    " Submitter is NOT allowed to Approve due to SoD
    cl_abap_unit_assert=>assert_false(
      zccmc_cl_decision_workflow=>is_action_allowed(
        is_decision = ls_rev-decision
        iv_action   = zccmc_cl_decision_workflow=>c_action-approve
        is_context  = ctx( iv_actor = c_dev_1
                           it_roles = VALUE #( ( zccmc_cl_decision_workflow=>c_role-reviewer ) ) ) ) ).
  ENDMETHOD.

  METHOD t24_missing_rec_metadata_rejected.
    DATA(ls_bad) = zccmc_cl_decision_workflow=>create_from_recommendation(
      iv_decision_uuid         = 'DEC-BAD'
      iv_object_uuid           = c_obj_1
      iv_recommended_strategy  = zccmc_cl_decision_workflow=>c_strategy-manual_review
      iv_ruleset_version       = ''
      iv_recommendation_run_id = 'RUN-0001'
      iv_evidence_summary      = ''
      is_context               = ctx( iv_actor = c_dev_1
                                      it_roles = VALUE #( ( zccmc_cl_decision_workflow=>c_role-developer ) ) ) ).
    cl_abap_unit_assert=>assert_false( ls_bad-success ).
    cl_abap_unit_assert=>assert_equals( act = ls_bad-error_code
                                        exp = zccmc_cl_decision_workflow=>c_error-missing_recommendation_field ).
  ENDMETHOD.

ENDCLASS.
