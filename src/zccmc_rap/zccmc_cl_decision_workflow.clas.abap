"! Deterministic workflow, authorization, separation-of-duties (SoD), concurrency
"! and append-only audit service for the Clean Core Migration Cockpit (Member 3).
"!
"! DEMO / SYNTHETIC workflow only. Follows docs/state-transitions.md (candidate v0.3).
"! The cockpit records human governance decisions; it never automatically migrates,
"! retires, or deletes SAP objects.
"!
"! STATUS: written without live ADT activation in the trial tenant (non-$TMP package
"! creation remains blocked/unverified; see docs/feasibility-note.md and docs/limitations.md).
"! Plain ABAP types (string, i, utclong, abap_boolean) are used intentionally so this
"! class compiles and executes in ABAP Unit independently of Member 1 table activation.
"!
"! Security & Governance Guarantees:
"! - Server-side state transition validation (8 states, 11 lifecycle actions + AssignOwner).
"! - Server-side role enforcement (DEVELOPER, REVIEWER, ADMIN, AUDITOR).
"! - Server-side Separation of Duties (SoD): when enabled (default = abap_true), a principal
"!   matching CreatedBy, OwnerUser, or SubmittedBy cannot Approve or Override the decision,
"!   even if that principal also holds the REVIEWER role.
"! - Assigned-owner enforcement: Developer lifecycle actions (Submit, Resubmit, Start, Block,
"!   Unblock, MarkMigrated) require the actor to match OwnerUser (except Admin on Submit/Resubmit).
"! - Mandatory reason validation (configurable min_reason_length, default 10 chars) on
"!   Override, Return, Block, Unblock, MarkMigrated, Reopen, and Resubmit.
"! - Override preserves RecommendedStrategy and sets FinalStrategy to a valid strategy that
"!   differs from RecommendedStrategy.
"! - Optimistic concurrency / ETag check: stale expected_version / expected_changed_at is
"!   rejected with ERR_STALE_CONCURRENCY_CONFLICT.
"! - Atomic state + append-only audit: every accepted action increments version_no and appends
"!   exactly one immutable audit event; every rejected action leaves both decision state and
"!   audit trail completely unchanged.
CLASS zccmc_cl_decision_workflow DEFINITION
  PUBLIC
  FINAL
  CREATE PUBLIC.

  PUBLIC SECTION.
    "! Workflow statuses (docs/state-transitions.md section 3)
    CONSTANTS:
      BEGIN OF c_status,
        proposed    TYPE string VALUE 'PROPOSED',
        in_review   TYPE string VALUE 'IN_REVIEW',
        approved    TYPE string VALUE 'APPROVED',
        overridden  TYPE string VALUE 'OVERRIDDEN',
        returned    TYPE string VALUE 'RETURNED',
        in_progress TYPE string VALUE 'IN_PROGRESS',
        blocked     TYPE string VALUE 'BLOCKED',
        migrated    TYPE string VALUE 'MIGRATED',
      END OF c_status.

    "! Workflow actions (docs/state-transitions.md section 4)
    CONSTANTS:
      BEGIN OF c_action,
        create_from_rec TYPE string VALUE 'CREATE_FROM_RECOMMENDATION',
        submit          TYPE string VALUE 'SUBMIT',
        resubmit        TYPE string VALUE 'RESUBMIT',
        approve         TYPE string VALUE 'APPROVE',
        override        TYPE string VALUE 'OVERRIDE',
        return_dec      TYPE string VALUE 'RETURN',
        assign_owner    TYPE string VALUE 'ASSIGN_OWNER',
        start_work      TYPE string VALUE 'START',
        block_work      TYPE string VALUE 'BLOCK',
        unblock_work    TYPE string VALUE 'UNBLOCK',
        mark_migrated   TYPE string VALUE 'MARK_MIGRATED',
        reopen          TYPE string VALUE 'REOPEN',
      END OF c_action.

    "! Roles (docs/state-transitions.md section 5)
    CONSTANTS:
      BEGIN OF c_role,
        developer TYPE string VALUE 'DEVELOPER',
        reviewer  TYPE string VALUE 'REVIEWER',
        admin     TYPE string VALUE 'ADMIN',
        auditor   TYPE string VALUE 'AUDITOR',
      END OF c_role.

    "! Valid modernization strategies (aligned with Member 2 zccmc_cl_rule_engine=>c_outcome)
    CONSTANTS:
      BEGIN OF c_strategy,
        keep_adapt       TYPE string VALUE 'KEEP_ADAPT',
        rewrite_rap      TYPE string VALUE 'REWRITE_RAP',
        retire_candidate TYPE string VALUE 'RETIRE_CANDIDATE',
        side_by_side_btp TYPE string VALUE 'SIDE_BY_SIDE_BTP',
        manual_review    TYPE string VALUE 'MANUAL_REVIEW',
      END OF c_strategy.

    "! Stable server-side validation & security error codes (Day-2 contract M3-D02-T01)
    CONSTANTS:
      BEGIN OF c_error,
        none                         TYPE string VALUE '',
        invalid_transition           TYPE string VALUE 'ERR_INVALID_TRANSITION',
        unauthorized_role            TYPE string VALUE 'ERR_UNAUTHORIZED_ROLE',
        sod_violation                TYPE string VALUE 'ERR_SOD_VIOLATION',
        not_assigned_owner           TYPE string VALUE 'ERR_NOT_ASSIGNED_OWNER',
        missing_owner                TYPE string VALUE 'ERR_MISSING_OWNER',
        missing_reason               TYPE string VALUE 'ERR_MISSING_REASON',
        reason_too_short             TYPE string VALUE 'ERR_REASON_TOO_SHORT',
        invalid_strategy             TYPE string VALUE 'ERR_INVALID_STRATEGY',
        override_same_strategy       TYPE string VALUE 'ERR_OVERRIDE_SAME_STRATEGY',
        owner_assign_in_review       TYPE string VALUE 'ERR_OWNER_ASSIGN_IN_REVIEW',
        duplicate_active_decision    TYPE string VALUE 'ERR_DUPLICATE_ACTIVE_DECISION',
        stale_concurrency_conflict   TYPE string VALUE 'ERR_STALE_CONCURRENCY_CONFLICT',
        audit_immutable              TYPE string VALUE 'ERR_AUDIT_IMMUTABLE',
        missing_recommendation_field TYPE string VALUE 'ERR_MISSING_RECOMMENDATION_FIELD',
        missing_actor                TYPE string VALUE 'ERR_MISSING_ACTOR',
      END OF c_error.

    CONSTANTS c_default_min_reason_len TYPE i VALUE 10.

    TYPES ty_role_tab TYPE STANDARD TABLE OF string WITH EMPTY KEY.

    "! Authenticated server context supplied by RAP handler or test harness
    TYPES:
      BEGIN OF ty_actor_context,
        actor_user       TYPE string,
        roles            TYPE ty_role_tab,
        timestamp        TYPE utclong,
        correlation_id   TYPE string,
        sod_enabled      TYPE abap_boolean,
        min_reason_len   TYPE i,
      END OF ty_actor_context.

    "! Persisted Migration Decision state (docs/state-transitions.md section 2)
    TYPES:
      BEGIN OF ty_decision,
        decision_uuid         TYPE string,
        object_uuid           TYPE string,
        recommended_strategy  TYPE string,
        final_strategy        TYPE string,
        ruleset_version       TYPE string,
        recommendation_run_id TYPE string,
        status                TYPE string,
        owner_user            TYPE string,
        created_by            TYPE string,
        submitted_by          TYPE string,
        created_at            TYPE utclong,
        changed_at            TYPE utclong,
        evidence_summary      TYPE string,
        missing_evidence      TYPE string,
        matched_rule_ids      TYPE string,
        import_batch_uuid     TYPE string,
        re_review_required    TYPE abap_boolean,
        version_no            TYPE i,
      END OF ty_decision,
      ty_decision_tab TYPE STANDARD TABLE OF ty_decision WITH EMPTY KEY.

    "! Append-only Decision Audit Event (docs/state-transitions.md section 8)
    TYPES:
      BEGIN OF ty_audit_event,
        event_uuid            TYPE string,
        decision_uuid         TYPE string,
        sequence_no           TYPE i,
        event_type            TYPE string,
        actor_user            TYPE string,
        event_timestamp       TYPE utclong,
        old_status            TYPE string,
        new_status            TYPE string,
        old_strategy          TYPE string,
        new_strategy          TYPE string,
        old_owner             TYPE string,
        new_owner             TYPE string,
        reason                TYPE string,
        ruleset_version       TYPE string,
        recommendation_run_id TYPE string,
        correlation_id        TYPE string,
        import_batch_uuid     TYPE string,
        sod_enabled           TYPE abap_boolean,
      END OF ty_audit_event,
      ty_audit_tab TYPE STANDARD TABLE OF ty_audit_event WITH EMPTY KEY.

    "! Standard action response returning updated state, appended audit, and error details
    TYPES:
      BEGIN OF ty_action_result,
        success      TYPE abap_boolean,
        error_code   TYPE string,
        error_msg    TYPE string,
        decision     TYPE ty_decision,
        audit_events TYPE ty_audit_tab,
      END OF ty_action_result.

    "! Create a new decision in PROPOSED status from a Member 2 recommendation result.
    "! Enforces the one-active-decision-per-object uniqueness invariant.
    CLASS-METHODS create_from_recommendation
      IMPORTING iv_decision_uuid         TYPE string
                iv_object_uuid           TYPE string
                iv_recommended_strategy  TYPE string
                iv_ruleset_version       TYPE string
                iv_recommendation_run_id TYPE string
                iv_evidence_summary      TYPE string
                iv_missing_evidence      TYPE string OPTIONAL
                iv_matched_rule_ids      TYPE string OPTIONAL
                iv_import_batch_uuid     TYPE string OPTIONAL
                iv_owner_user            TYPE string OPTIONAL
                is_context               TYPE ty_actor_context
                it_existing_decisions    TYPE ty_decision_tab OPTIONAL
      RETURNING VALUE(rs_result)         TYPE ty_action_result.

    "! Execute a workflow transition or owner-assignment action with full server-side
    "! state, role, SoD, reason, and ETag/version validation.
    CLASS-METHODS execute_action
      IMPORTING is_decision          TYPE ty_decision
                it_audit_events      TYPE ty_audit_tab
                iv_action            TYPE string
                is_context           TYPE ty_actor_context
                iv_new_strategy      TYPE string OPTIONAL
                iv_new_owner         TYPE string OPTIONAL
                iv_reason            TYPE string OPTIONAL
                iv_expected_version  TYPE i      OPTIONAL
      RETURNING VALUE(rs_result)     TYPE ty_action_result.

    "! Apply a new Member 2 recommendation run to an existing active decision (M2 C7/C9):
    "! updates recommendation metadata and flags re_review_required without creating a duplicate decision.
    CLASS-METHODS apply_recommendation_rerun
      IMPORTING is_decision              TYPE ty_decision
                it_audit_events          TYPE ty_audit_tab
                iv_recommended_strategy  TYPE string
                iv_ruleset_version       TYPE string
                iv_recommendation_run_id TYPE string
                iv_evidence_summary      TYPE string
                iv_missing_evidence      TYPE string OPTIONAL
                iv_matched_rule_ids      TYPE string OPTIONAL
                is_context               TYPE ty_actor_context
      RETURNING VALUE(rs_result)         TYPE ty_action_result.

    "! Guard against any attempt to modify or delete audit trail records via service/API.
    CLASS-METHODS reject_audit_mutation
      IMPORTING is_decision      TYPE ty_decision
                it_audit_events  TYPE ty_audit_tab
                iv_operation     TYPE string
      RETURNING VALUE(rs_result) TYPE ty_action_result.

    "! Dynamic feature/action control helper for RAP get_instance_features / UI metadata.
    "! Note: UI button visibility is convenience only; execute_action always re-validates on the server.
    CLASS-METHODS is_action_allowed
      IMPORTING is_decision       TYPE ty_decision
                iv_action         TYPE string
                is_context        TYPE ty_actor_context
      RETURNING VALUE(rv_allowed) TYPE abap_boolean.

  PRIVATE SECTION.
    CLASS-METHODS has_role
      IMPORTING it_roles       TYPE ty_role_tab
                iv_role        TYPE string
      RETURNING VALUE(rv_has)  TYPE abap_boolean.

    CLASS-METHODS is_valid_strategy
      IMPORTING iv_strategy     TYPE string
      RETURNING VALUE(rv_valid) TYPE abap_boolean.

    CLASS-METHODS normalize_upper
      IMPORTING iv_text        TYPE string
      RETURNING VALUE(rv_norm) TYPE string.
ENDCLASS.


CLASS zccmc_cl_decision_workflow IMPLEMENTATION.

  METHOD normalize_upper.
    rv_norm = to_upper( condense( val = iv_text ) ).
  ENDMETHOD.

  METHOD has_role.
    DATA(lv_target) = normalize_upper( iv_role ).
    rv_has = abap_false.
    LOOP AT it_roles INTO DATA(lv_role).
      IF normalize_upper( lv_role ) = lv_target.
        rv_has = abap_true.
        RETURN.
      ENDIF.
    ENDLOOP.
  ENDMETHOD.

  METHOD is_valid_strategy.
    DATA(lv_strat) = normalize_upper( iv_strategy ).
    IF lv_strat = c_strategy-keep_adapt
       OR lv_strat = c_strategy-rewrite_rap
       OR lv_strat = c_strategy-retire_candidate
       OR lv_strat = c_strategy-side_by_side_btp
       OR lv_strat = c_strategy-manual_review.
      rv_valid = abap_true.
    ELSE.
      rv_valid = abap_false.
    ENDIF.
  ENDMETHOD.

  METHOD create_from_recommendation.
    DATA(lv_actor) = condense( val = is_context-actor_user ).
    IF lv_actor IS INITIAL.
      rs_result = VALUE #( success    = abap_false
                           error_code = c_error-missing_actor
                           error_msg  = 'Authenticated server actor context is required.' ).
      RETURN.
    ENDIF.

    " Only Developer or Admin may create a decision from recommendation (Auditor/Reviewer cannot initiate)
    IF has_role( it_roles = is_context-roles iv_role = c_role-developer ) = abap_false
       AND has_role( it_roles = is_context-roles iv_role = c_role-admin ) = abap_false.
      rs_result = VALUE #( success    = abap_false
                           error_code = c_error-unauthorized_role
                           error_msg  = 'Only DEVELOPER or ADMIN can create a migration decision.' ).
      RETURN.
    ENDIF.

    DATA(lv_obj_uuid) = condense( val = iv_object_uuid ).
    DATA(lv_rec_strat) = normalize_upper( iv_recommended_strategy ).
    DATA(lv_ruleset_ver) = condense( val = iv_ruleset_version ).
    DATA(lv_run_id) = condense( val = iv_recommendation_run_id ).
    DATA(lv_ev_summary) = condense( val = iv_evidence_summary ).

    IF lv_obj_uuid IS INITIAL OR lv_ruleset_ver IS INITIAL OR lv_run_id IS INITIAL OR lv_ev_summary IS INITIAL.
      rs_result = VALUE #( success    = abap_false
                           error_code = c_error-missing_recommendation_field
                           error_msg  = 'ObjectUUID, RuleSetVersion, RecommendationRunID, and EvidenceSummary are required.' ).
      RETURN.
    ENDIF.

    IF is_valid_strategy( lv_rec_strat ) = abap_false.
      rs_result = VALUE #( success    = abap_false
                           error_code = c_error-invalid_strategy
                           error_msg  = 'RecommendedStrategy is not a valid contract strategy.' ).
      RETURN.
    ENDIF.

    " Enforce at most one active (non-MIGRATED) decision per ObjectUUID
    LOOP AT it_existing_decisions INTO DATA(ls_existing).
      IF condense( val = ls_existing-object_uuid ) = lv_obj_uuid
         AND normalize_upper( ls_existing-status ) <> c_status-migrated.
        rs_result = VALUE #( success    = abap_false
                             error_code = c_error-duplicate_active_decision
                             error_msg  = 'An active migration decision already exists for this ObjectUUID.' ).
        RETURN.
      ENDIF.
    ENDLOOP.

    DATA(ls_dec) = VALUE ty_decision(
      decision_uuid         = COND #( WHEN iv_decision_uuid IS NOT INITIAL THEN condense( val = iv_decision_uuid ) ELSE |DEC-{ lv_obj_uuid }| )
      object_uuid           = lv_obj_uuid
      recommended_strategy  = lv_rec_strat
      final_strategy        = ''
      ruleset_version       = lv_ruleset_ver
      recommendation_run_id = lv_run_id
      status                = c_status-proposed
      owner_user            = condense( val = iv_owner_user )
      created_by            = lv_actor
      submitted_by          = ''
      created_at            = is_context-timestamp
      changed_at            = is_context-timestamp
      evidence_summary      = lv_ev_summary
      missing_evidence      = condense( val = iv_missing_evidence )
      matched_rule_ids      = condense( val = iv_matched_rule_ids )
      import_batch_uuid     = condense( val = iv_import_batch_uuid )
      re_review_required    = abap_false
      version_no            = 1 ).

    DATA(ls_audit) = VALUE ty_audit_event(
      event_uuid            = |{ ls_dec-decision_uuid }-EVT-0001|
      decision_uuid         = ls_dec-decision_uuid
      sequence_no           = 1
      event_type            = c_action-create_from_rec
      actor_user            = lv_actor
      event_timestamp       = is_context-timestamp
      old_status            = ''
      new_status            = c_status-proposed
      old_strategy          = ''
      new_strategy          = lv_rec_strat
      old_owner             = ''
      new_owner             = ls_dec-owner_user
      reason                = 'Created from rule engine recommendation'
      ruleset_version       = lv_ruleset_ver
      recommendation_run_id = lv_run_id
      correlation_id        = is_context-correlation_id
      import_batch_uuid     = ls_dec-import_batch_uuid
      sod_enabled           = is_context-sod_enabled ).

    rs_result = VALUE #(
      success      = abap_true
      error_code   = c_error-none
      error_msg    = ''
      decision     = ls_dec
      audit_events = VALUE #( ( ls_audit ) ) ).
  ENDMETHOD.

  METHOD execute_action.
    " Always preserve original state and audit trail on any rejection
    rs_result = VALUE #(
      success      = abap_false
      decision     = is_decision
      audit_events = it_audit_events ).

    DATA(lv_actor) = condense( val = is_context-actor_user ).
    IF lv_actor IS INITIAL.
      rs_result-error_code = c_error-missing_actor.
      rs_result-error_msg  = 'Authenticated server actor context is required.'.
      RETURN.
    ENDIF.

    " 1. Optimistic concurrency / ETag version check (when caller supplies expected_version > 0)
    IF iv_expected_version > 0 AND iv_expected_version <> is_decision-version_no.
      rs_result-error_code = c_error-stale_concurrency_conflict.
      rs_result-error_msg  = |Stale update rejected: expected version { iv_expected_version }, actual committed version is { is_decision-version_no }.|.
      RETURN.
    ENDIF.

    DATA(lv_action) = normalize_upper( iv_action ).
    DATA(lv_status) = normalize_upper( is_decision-status ).
    DATA(lv_reason) = condense( val = iv_reason ).
    DATA(lv_min_len) = COND i( WHEN is_context-min_reason_len > 0 THEN is_context-min_reason_len ELSE c_default_min_reason_len ).

    DATA(lv_is_dev)   = has_role( it_roles = is_context-roles iv_role = c_role-developer ).
    DATA(lv_is_rev)   = has_role( it_roles = is_context-roles iv_role = c_role-reviewer ).
    DATA(lv_is_admin) = has_role( it_roles = is_context-roles iv_role = c_role-admin ).

    DATA(lv_new_status)   = lv_status.
    DATA(lv_new_strategy) = is_decision-final_strategy.
    DATA(lv_new_owner)    = is_decision-owner_user.
    DATA(lv_submitted_by) = is_decision-submitted_by.
    DATA(lv_re_review)    = is_decision-re_review_required.

    " 2. Handle AssignOwner (separate action that does not change status)
    IF lv_action = c_action-assign_owner.
      IF lv_status = c_status-in_review.
        rs_result-error_code = c_error-owner_assign_in_review.
        rs_result-error_msg  = 'Owner assignment is rejected while decision is IN_REVIEW.'.
        RETURN.
      ENDIF.
      IF lv_status <> c_status-proposed AND lv_status <> c_status-returned AND lv_status <> c_status-blocked.
        rs_result-error_code = c_error-invalid_transition.
        rs_result-error_msg  = |AssignOwner is only allowed in PROPOSED, RETURNED, or BLOCKED (current: { lv_status }).|.
        RETURN.
      ENDIF.
      IF lv_is_rev = abap_false AND lv_is_admin = abap_false.
        rs_result-error_code = c_error-unauthorized_role.
        rs_result-error_msg  = 'Only REVIEWER or ADMIN may assign an owner.'.
        RETURN.
      ENDIF.
      DATA(lv_target_owner) = condense( val = iv_new_owner ).
      IF lv_target_owner IS INITIAL.
        rs_result-error_code = c_error-missing_owner.
        rs_result-error_msg  = 'New owner user ID must not be blank.'.
        RETURN.
      ENDIF.
      lv_new_owner = lv_target_owner.

    " 3. Handle Submit (PROPOSED -> IN_REVIEW) and Resubmit (RETURNED -> IN_REVIEW)
    ELSEIF lv_action = c_action-submit OR lv_action = c_action-resubmit.
      IF ( lv_action = c_action-submit AND lv_status <> c_status-proposed )
         OR ( lv_action = c_action-resubmit AND lv_status <> c_status-returned ).
        rs_result-error_code = c_error-invalid_transition.
        rs_result-error_msg  = |Action { lv_action } is not allowed from status { lv_status }.|.
        RETURN.
      ENDIF.
      IF lv_is_dev = abap_false AND lv_is_admin = abap_false.
        rs_result-error_code = c_error-unauthorized_role.
        rs_result-error_msg  = 'Only assigned DEVELOPER or ADMIN may submit or resubmit a decision.'.
        RETURN.
      ENDIF.
      IF is_decision-owner_user IS INITIAL.
        rs_result-error_code = c_error-missing_owner.
        rs_result-error_msg  = 'Submit requires an assigned OwnerUser.'.
        RETURN.
      ENDIF.
      " If not Admin, actor must be the assigned owner
      IF lv_is_admin = abap_false AND normalize_upper( lv_actor ) <> normalize_upper( is_decision-owner_user ).
        rs_result-error_code = c_error-not_assigned_owner.
        rs_result-error_msg  = 'Developer may only submit or resubmit a decision assigned to them.'.
        RETURN.
      ENDIF.
      " Validate recommendation metadata completeness before submission
      IF is_valid_strategy( is_decision-recommended_strategy ) = abap_false
         OR is_decision-ruleset_version IS INITIAL
         OR is_decision-recommendation_run_id IS INITIAL
         OR is_decision-evidence_summary IS INITIAL.
        rs_result-error_code = c_error-missing_recommendation_field.
        rs_result-error_msg  = 'Submit requires RecommendedStrategy, RuleSetVersion, RecommendationRunID, and EvidenceSummary.'.
        RETURN.
      ENDIF.
      IF lv_action = c_action-resubmit.
        IF lv_reason IS INITIAL.
          rs_result-error_code = c_error-missing_reason.
          rs_result-error_msg  = 'Resubmit requires a response note explaining the correction.'.
          RETURN.
        ENDIF.
        IF strlen( lv_reason ) < lv_min_len.
          rs_result-error_code = c_error-reason_too_short.
          rs_result-error_msg  = |Resubmit response note must be at least { lv_min_len } characters.|.
          RETURN.
        ENDIF.
      ENDIF.
      lv_new_status   = c_status-in_review.
      lv_submitted_by = lv_actor.
      lv_re_review    = abap_false.

    " 4. Handle Approve (IN_REVIEW -> APPROVED) and Override (IN_REVIEW -> OVERRIDDEN)
    ELSEIF lv_action = c_action-approve OR lv_action = c_action-override.
      IF lv_status <> c_status-in_review.
        rs_result-error_code = c_error-invalid_transition.
        rs_result-error_msg  = |Action { lv_action } is only allowed from IN_REVIEW (current: { lv_status }).|.
        RETURN.
      ENDIF.
      IF lv_is_rev = abap_false.
        rs_result-error_code = c_error-unauthorized_role.
        rs_result-error_msg  = |Only REVIEWER is authorized to perform { lv_action }.|.
        RETURN.
      ENDIF.
      " Enforce Separation of Duties (SoD) when enabled
      IF is_context-sod_enabled = abap_true.
        DATA(lv_norm_actor) = normalize_upper( lv_actor ).
        IF lv_norm_actor = normalize_upper( is_decision-owner_user )
           OR lv_norm_actor = normalize_upper( is_decision-created_by )
           OR lv_norm_actor = normalize_upper( is_decision-submitted_by ).
          rs_result-error_code = c_error-sod_violation.
          rs_result-error_msg  = 'Separation of duties violation: owner, creator, or last submitter cannot approve or override their own decision.'.
          RETURN.
        ENDIF.
      ENDIF.

      IF lv_action = c_action-approve.
        lv_new_status   = c_status-approved.
        lv_new_strategy = is_decision-recommended_strategy.
      ELSE.
        " Override requires a mandatory reason and a valid strategy different from RecommendedStrategy
        IF lv_reason IS INITIAL.
          rs_result-error_code = c_error-missing_reason.
          rs_result-error_msg  = 'Override requires a non-empty justification reason.'.
          RETURN.
        ENDIF.
        IF strlen( lv_reason ) < lv_min_len.
          rs_result-error_code = c_error-reason_too_short.
          rs_result-error_msg  = |Override reason must be at least { lv_min_len } characters.|.
          RETURN.
        ENDIF.
        DATA(lv_ovr_strat) = normalize_upper( iv_new_strategy ).
        IF is_valid_strategy( lv_ovr_strat ) = abap_false.
          rs_result-error_code = c_error-invalid_strategy.
          rs_result-error_msg  = 'Override strategy is not a valid modernization strategy.'.
          RETURN.
        ENDIF.
        IF lv_ovr_strat = normalize_upper( is_decision-recommended_strategy ).
          rs_result-error_code = c_error-override_same_strategy.
          rs_result-error_msg  = 'Override strategy must differ from RecommendedStrategy; use Approve instead.'.
          RETURN.
        ENDIF.
        lv_new_status   = c_status-overridden.
        lv_new_strategy = lv_ovr_strat.
      ENDIF.

    " 5. Handle Return (IN_REVIEW -> RETURNED)
    ELSEIF lv_action = c_action-return_dec.
      IF lv_status <> c_status-in_review.
        rs_result-error_code = c_error-invalid_transition.
        rs_result-error_msg  = |Return is only allowed from IN_REVIEW (current: { lv_status }).|.
        RETURN.
      ENDIF.
      IF lv_is_rev = abap_false.
        rs_result-error_code = c_error-unauthorized_role.
        rs_result-error_msg  = 'Only REVIEWER is authorized to Return a decision.'.
        RETURN.
      ENDIF.
      IF lv_reason IS INITIAL.
        rs_result-error_code = c_error-missing_reason.
        rs_result-error_msg  = 'Return requires a reason describing needed corrections or evidence.'.
        RETURN.
      ENDIF.
      IF strlen( lv_reason ) < lv_min_len.
        rs_result-error_code = c_error-reason_too_short.
        rs_result-error_msg  = |Return reason must be at least { lv_min_len } characters.|.
        RETURN.
      ENDIF.
      lv_new_status = c_status-returned.

    " 6. Handle Developer execution actions: Start, Block, Unblock, MarkMigrated
    ELSEIF lv_action = c_action-start_work
        OR lv_action = c_action-block_work
        OR lv_action = c_action-unblock_work
        OR lv_action = c_action-mark_migrated.

      " Check state transition validity first
      IF lv_action = c_action-start_work AND lv_status <> c_status-approved AND lv_status <> c_status-overridden.
        rs_result-error_code = c_error-invalid_transition.
        rs_result-error_msg  = |Start is only allowed from APPROVED or OVERRIDDEN (current: { lv_status }).|.
        RETURN.
      ELSEIF ( lv_action = c_action-block_work OR lv_action = c_action-mark_migrated ) AND lv_status <> c_status-in_progress.
        rs_result-error_code = c_error-invalid_transition.
        rs_result-error_msg  = |Action { lv_action } is only allowed from IN_PROGRESS (current: { lv_status }).|.
        RETURN.
      ELSEIF lv_action = c_action-unblock_work AND lv_status <> c_status-blocked.
        rs_result-error_code = c_error-invalid_transition.
        rs_result-error_msg  = |Unblock is only allowed from BLOCKED (current: { lv_status }).|.
        RETURN.
      ENDIF.

      " Check Developer role and assigned ownership
      IF lv_is_dev = abap_false.
        rs_result-error_code = c_error-unauthorized_role.
        rs_result-error_msg  = |Only DEVELOPER may perform { lv_action }.|.
        RETURN.
      ENDIF.
      IF normalize_upper( lv_actor ) <> normalize_upper( is_decision-owner_user ).
        rs_result-error_code = c_error-not_assigned_owner.
        rs_result-error_msg  = |Developer may only perform { lv_action } on their own assigned decision.|.
        RETURN.
      ENDIF.

      " Mandatory notes/reasons for Block, Unblock, MarkMigrated
      IF lv_action <> c_action-start_work.
        IF lv_reason IS INITIAL.
          rs_result-error_code = c_error-missing_reason.
          rs_result-error_msg  = |Action { lv_action } requires a non-empty note/reason.|.
          RETURN.
        ENDIF.
        IF strlen( lv_reason ) < lv_min_len.
          rs_result-error_code = c_error-reason_too_short.
          rs_result-error_msg  = |Note/reason for { lv_action } must be at least { lv_min_len } characters.|.
          RETURN.
        ENDIF.
      ENDIF.

      CASE lv_action.
        WHEN c_action-start_work.
          lv_new_status = c_status-in_progress.
        WHEN c_action-block_work.
          lv_new_status = c_status-blocked.
        WHEN c_action-unblock_work.
          lv_new_status = c_status-in_progress.
        WHEN c_action-mark_migrated.
          lv_new_status = c_status-migrated.
      ENDCASE.

    " 7. Handle Reopen (APPROVED/OVERRIDDEN/IN_PROGRESS/BLOCKED -> IN_REVIEW by Reviewer/Admin; MIGRATED -> IN_REVIEW by Admin only)
    ELSEIF lv_action = c_action-reopen.
      IF lv_status <> c_status-approved
         AND lv_status <> c_status-overridden
         AND lv_status <> c_status-in_progress
         AND lv_status <> c_status-blocked
         AND lv_status <> c_status-migrated.
        rs_result-error_code = c_error-invalid_transition.
        rs_result-error_msg  = |Reopen is not allowed from status { lv_status }.|.
        RETURN.
      ENDIF.
      IF lv_status = c_status-migrated.
        IF lv_is_admin = abap_false.
          rs_result-error_code = c_error-unauthorized_role.
          rs_result-error_msg  = 'Reopening a MIGRATED decision is restricted to ADMIN only.'.
          RETURN.
        ENDIF.
      ELSE.
        IF lv_is_rev = abap_false AND lv_is_admin = abap_false.
          rs_result-error_code = c_error-unauthorized_role.
          rs_result-error_msg  = 'Only REVIEWER or ADMIN may reopen a decision.'.
          RETURN.
        ENDIF.
      ENDIF.
      IF lv_reason IS INITIAL.
        rs_result-error_code = c_error-missing_reason.
        rs_result-error_msg  = 'Reopen requires a reason.'.
        RETURN.
      ENDIF.
      IF strlen( lv_reason ) < lv_min_len.
        rs_result-error_code = c_error-reason_too_short.
        rs_result-error_msg  = |Reopen reason must be at least { lv_min_len } characters.|.
        RETURN.
      ENDIF.
      lv_new_status = c_status-in_review.

    ELSE.
      rs_result-error_code = c_error-invalid_transition.
      rs_result-error_msg  = |Unsupported workflow action: { lv_action }.|.
      RETURN.
    ENDIF.

    " 8. Apply atomic state update and append immutable audit event
    DATA(ls_updated) = is_decision.
    ls_updated-status             = lv_new_status.
    ls_updated-final_strategy     = lv_new_strategy.
    ls_updated-owner_user         = lv_new_owner.
    ls_updated-submitted_by       = lv_submitted_by.
    ls_updated-re_review_required = lv_re_review.
    ls_updated-changed_at         = is_context-timestamp.
    ls_updated-version_no         = is_decision-version_no + 1.

    DATA(lv_seq) = lines( it_audit_events ) + 1.
    DATA(ls_audit) = VALUE ty_audit_event(
      event_uuid            = |{ is_decision-decision_uuid }-EVT-{ lv_seq WIDTH = 4 ALIGN = RIGHT PAD = '0' }|
      decision_uuid         = is_decision-decision_uuid
      sequence_no           = lv_seq
      event_type            = lv_action
      actor_user            = lv_actor
      event_timestamp       = is_context-timestamp
      old_status            = is_decision-status
      new_status            = lv_new_status
      old_strategy          = COND #( WHEN is_decision-final_strategy IS NOT INITIAL
                                      THEN is_decision-final_strategy
                                      ELSE is_decision-recommended_strategy )
      new_strategy          = COND #( WHEN lv_new_strategy IS NOT INITIAL
                                      THEN lv_new_strategy
                                      ELSE is_decision-recommended_strategy )
      old_owner             = is_decision-owner_user
      new_owner             = lv_new_owner
      reason                = lv_reason
      ruleset_version       = is_decision-ruleset_version
      recommendation_run_id = is_decision-recommendation_run_id
      correlation_id        = is_context-correlation_id
      import_batch_uuid     = is_decision-import_batch_uuid
      sod_enabled           = is_context-sod_enabled ).

    DATA(lt_audits) = it_audit_events.
    APPEND ls_audit TO lt_audits.

    rs_result = VALUE #(
      success      = abap_true
      error_code   = c_error-none
      error_msg    = ''
      decision     = ls_updated
      audit_events = lt_audits ).
  ENDMETHOD.

  METHOD apply_recommendation_rerun.
    rs_result = VALUE #(
      success      = abap_false
      decision     = is_decision
      audit_events = it_audit_events ).

    DATA(lv_actor) = condense( val = is_context-actor_user ).
    IF lv_actor IS INITIAL.
      rs_result-error_code = c_error-missing_actor.
      rs_result-error_msg  = 'Authenticated server actor context is required.'.
      RETURN.
    ENDIF.

    DATA(lv_rec_strat) = normalize_upper( iv_recommended_strategy ).
    IF is_valid_strategy( lv_rec_strat ) = abap_false
       OR iv_ruleset_version IS INITIAL
       OR iv_recommendation_run_id IS INITIAL
       OR iv_evidence_summary IS INITIAL.
      rs_result-error_code = c_error-missing_recommendation_field.
      rs_result-error_msg  = 'Recommendation rerun requires valid RecommendedStrategy, RuleSetVersion, RecommendationRunID, and EvidenceSummary.'.
      RETURN.
    ENDIF.

    DATA(ls_updated) = is_decision.
    ls_updated-recommended_strategy  = lv_rec_strat.
    ls_updated-ruleset_version       = condense( val = iv_ruleset_version ).
    ls_updated-recommendation_run_id = condense( val = iv_recommendation_run_id ).
    ls_updated-evidence_summary      = condense( val = iv_evidence_summary ).
    ls_updated-missing_evidence      = condense( val = iv_missing_evidence ).
    ls_updated-matched_rule_ids      = condense( val = iv_matched_rule_ids ).
    ls_updated-re_review_required    = abap_true.
    ls_updated-changed_at            = is_context-timestamp.
    ls_updated-version_no            = is_decision-version_no + 1.

    DATA(lv_seq) = lines( it_audit_events ) + 1.
    DATA(ls_audit) = VALUE ty_audit_event(
      event_uuid            = |{ is_decision-decision_uuid }-EVT-{ lv_seq WIDTH = 4 ALIGN = RIGHT PAD = '0' }|
      decision_uuid         = is_decision-decision_uuid
      sequence_no           = lv_seq
      event_type            = 'RECOMMENDATION_RERUN'
      actor_user            = lv_actor
      event_timestamp       = is_context-timestamp
      old_status            = is_decision-status
      new_status            = is_decision-status
      old_strategy          = is_decision-recommended_strategy
      new_strategy          = lv_rec_strat
      old_owner             = is_decision-owner_user
      new_owner             = is_decision-owner_user
      reason                = |Recommendation revised by run { ls_updated-recommendation_run_id }|
      ruleset_version       = ls_updated-ruleset_version
      recommendation_run_id = ls_updated-recommendation_run_id
      correlation_id        = is_context-correlation_id
      import_batch_uuid     = is_decision-import_batch_uuid
      sod_enabled           = is_context-sod_enabled ).

    DATA(lt_audits) = it_audit_events.
    APPEND ls_audit TO lt_audits.

    rs_result = VALUE #(
      success      = abap_true
      error_code   = c_error-none
      error_msg    = ''
      decision     = ls_updated
      audit_events = lt_audits ).
  ENDMETHOD.

  METHOD reject_audit_mutation.
    rs_result = VALUE #(
      success      = abap_false
      error_code   = c_error-audit_immutable
      error_msg    = |Audit history is strictly append-only; operation '{ iv_operation }' is forbidden.|
      decision     = is_decision
      audit_events = it_audit_events ).
  ENDMETHOD.

  METHOD is_action_allowed.
    " Simulate with a synthetic valid note/strategy to check state + role + SoD eligibility
    DATA(ls_probe) = execute_action(
      is_decision     = is_decision
      it_audit_events = VALUE #( )
      iv_action       = iv_action
      is_context      = is_context
      iv_new_strategy = COND #( WHEN is_decision-recommended_strategy = c_strategy-keep_adapt
                                THEN c_strategy-manual_review
                                ELSE c_strategy-keep_adapt )
      iv_new_owner    = COND #( WHEN is_decision-owner_user IS NOT INITIAL
                                THEN is_decision-owner_user
                                ELSE 'PROBE_OWNER' )
      iv_reason       = 'Probe reason satisfying minimum length check' ).
    rv_allowed = ls_probe-success.
  ENDMETHOD.

ENDCLASS.
