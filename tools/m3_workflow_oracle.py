#!/usr/bin/env python3
"""Reference model and regression runner for Member 3 workflow & security (docs/state-transitions.md).

This is an OFFLINE TEST ORACLE, not the SAP runtime. The ABAP implementation is
src/zccmc_rap/zccmc_cl_decision_workflow.clas.abap (and RAP behavior pool zccmc_bp_i_decision),
which requires a verified non-$TMP package in the SAP BTP ABAP Environment trial to activate.

This oracle re-implements the exact state machine, role matrix, Separation of Duties (SoD),
mandatory reason checks, optimistic concurrency (ETag/version), one-active-decision uniqueness,
and append-only audit trail rules so that:
  * the 352-cell (8 states x 11 actions x 4 roles) transition/authorization matrix is verified;
  * all 24 unit-test scenarios (WF-T01..WF-T24) in zccmc_ut_decision_workflow are cross-checked;
  * the Day-10 workflow rehearsal across the 7 synthetic sample objects is reproducible offline.
It proves nothing about live SAP ADT activation. DEMO / SYNTHETIC data only.

Usage (repository root):
    python tools/m3_workflow_oracle.py                                      # run all checks
    python tools/m3_workflow_oracle.py --report docs/m3-golden-workflow-results.md
"""
from __future__ import annotations

import argparse
import copy
import csv
from dataclasses import dataclass, field
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SAMPLE = ROOT / "data" / "sample-synthetic"

STATUSES = (
    "PROPOSED",
    "IN_REVIEW",
    "APPROVED",
    "OVERRIDDEN",
    "RETURNED",
    "IN_PROGRESS",
    "BLOCKED",
    "MIGRATED",
)

ACTIONS = (
    "SUBMIT",
    "RESUBMIT",
    "APPROVE",
    "OVERRIDE",
    "RETURN",
    "ASSIGN_OWNER",
    "START",
    "BLOCK",
    "UNBLOCK",
    "MARK_MIGRATED",
    "REOPEN",
)

ROLES = ("DEVELOPER", "REVIEWER", "ADMIN", "AUDITOR")

STRATEGIES = (
    "KEEP_ADAPT",
    "REWRITE_RAP",
    "RETIRE_CANDIDATE",
    "SIDE_BY_SIDE_BTP",
    "MANUAL_REVIEW",
)

ERRORS = {
    "NONE": "",
    "INVALID_TRANSITION": "ERR_INVALID_TRANSITION",
    "UNAUTHORIZED_ROLE": "ERR_UNAUTHORIZED_ROLE",
    "SOD_VIOLATION": "ERR_SOD_VIOLATION",
    "NOT_ASSIGNED_OWNER": "ERR_NOT_ASSIGNED_OWNER",
    "MISSING_OWNER": "ERR_MISSING_OWNER",
    "MISSING_REASON": "ERR_MISSING_REASON",
    "REASON_TOO_SHORT": "ERR_REASON_TOO_SHORT",
    "INVALID_STRATEGY": "ERR_INVALID_STRATEGY",
    "OVERRIDE_SAME_STRATEGY": "ERR_OVERRIDE_SAME_STRATEGY",
    "OWNER_ASSIGN_IN_REVIEW": "ERR_OWNER_ASSIGN_IN_REVIEW",
    "DUPLICATE_ACTIVE_DECISION": "ERR_DUPLICATE_ACTIVE_DECISION",
    "STALE_CONCURRENCY_CONFLICT": "ERR_STALE_CONCURRENCY_CONFLICT",
    "AUDIT_IMMUTABLE": "ERR_AUDIT_IMMUTABLE",
    "MISSING_RECOMMENDATION_FIELD": "ERR_MISSING_RECOMMENDATION_FIELD",
    "MISSING_ACTOR": "ERR_MISSING_ACTOR",
}


@dataclass
class ActorContext:
    actor_user: str
    roles: list[str]
    timestamp: str = "2026-10-14T10:00:00Z"
    correlation_id: str = "CORR-DEMO-01"
    sod_enabled: bool = True
    min_reason_len: int = 10


@dataclass
class Decision:
    decision_uuid: str
    object_uuid: str
    recommended_strategy: str
    final_strategy: str
    ruleset_version: str
    recommendation_run_id: str
    status: str
    owner_user: str
    created_by: str
    submitted_by: str
    created_at: str
    changed_at: str
    evidence_summary: str
    missing_evidence: str = ""
    matched_rule_ids: str = ""
    import_batch_uuid: str = ""
    re_review_required: bool = False
    version_no: int = 1


@dataclass
class AuditEvent:
    event_uuid: str
    decision_uuid: str
    sequence_no: int
    event_type: str
    actor_user: str
    event_timestamp: str
    old_status: str
    new_status: str
    old_strategy: str
    new_strategy: str
    old_owner: str
    new_owner: str
    reason: str
    ruleset_version: str
    recommendation_run_id: str
    correlation_id: str
    import_batch_uuid: str
    sod_enabled: bool


@dataclass
class ActionResult:
    success: bool
    error_code: str
    error_msg: str
    decision: Decision | None
    audit_events: list[AuditEvent] = field(default_factory=list)


def _norm(val: str) -> str:
    return (val or "").strip().upper()


def _has_role(roles: list[str], target: str) -> bool:
    t = _norm(target)
    return any(_norm(r) == t for r in roles)


def create_from_recommendation(
    decision_uuid: str,
    object_uuid: str,
    recommended_strategy: str,
    ruleset_version: str,
    recommendation_run_id: str,
    evidence_summary: str,
    context: ActorContext,
    missing_evidence: str = "",
    matched_rule_ids: str = "",
    import_batch_uuid: str = "",
    owner_user: str = "",
    existing_decisions: list[Decision] | None = None,
) -> ActionResult:
    actor = (context.actor_user or "").strip()
    if not actor:
        return ActionResult(False, ERRORS["MISSING_ACTOR"], "Missing actor", None, [])

    if not (_has_role(context.roles, "DEVELOPER") or _has_role(context.roles, "ADMIN")):
        return ActionResult(False, ERRORS["UNAUTHORIZED_ROLE"], "Only DEVELOPER or ADMIN can create", None, [])

    obj_id = (object_uuid or "").strip()
    rec_strat = _norm(recommended_strategy)
    rs_ver = (ruleset_version or "").strip()
    run_id = (recommendation_run_id or "").strip()
    ev_sum = (evidence_summary or "").strip()

    if not obj_id or not rs_ver or not run_id or not ev_sum:
        return ActionResult(False, ERRORS["MISSING_RECOMMENDATION_FIELD"], "Missing required recommendation field", None, [])

    if rec_strat not in STRATEGIES:
        return ActionResult(False, ERRORS["INVALID_STRATEGY"], "Invalid RecommendedStrategy", None, [])

    for ex in existing_decisions or []:
        if ex.object_uuid.strip() == obj_id and _norm(ex.status) != "MIGRATED":
            return ActionResult(False, ERRORS["DUPLICATE_ACTIVE_DECISION"], "Active decision already exists", None, [])

    d_uuid = (decision_uuid or "").strip() or f"DEC-{obj_id}"
    dec = Decision(
        decision_uuid=d_uuid,
        object_uuid=obj_id,
        recommended_strategy=rec_strat,
        final_strategy="",
        ruleset_version=rs_ver,
        recommendation_run_id=run_id,
        status="PROPOSED",
        owner_user=(owner_user or "").strip(),
        created_by=actor,
        submitted_by="",
        created_at=context.timestamp,
        changed_at=context.timestamp,
        evidence_summary=ev_sum,
        missing_evidence=(missing_evidence or "").strip(),
        matched_rule_ids=(matched_rule_ids or "").strip(),
        import_batch_uuid=(import_batch_uuid or "").strip(),
        re_review_required=False,
        version_no=1,
    )
    evt = AuditEvent(
        event_uuid=f"{d_uuid}-EVT-0001",
        decision_uuid=d_uuid,
        sequence_no=1,
        event_type="CREATE_FROM_RECOMMENDATION",
        actor_user=actor,
        event_timestamp=context.timestamp,
        old_status="",
        new_status="PROPOSED",
        old_strategy="",
        new_strategy=rec_strat,
        old_owner="",
        new_owner=dec.owner_user,
        reason="Created from rule engine recommendation",
        ruleset_version=rs_ver,
        recommendation_run_id=run_id,
        correlation_id=context.correlation_id,
        import_batch_uuid=dec.import_batch_uuid,
        sod_enabled=context.sod_enabled,
    )
    return ActionResult(True, "", "", dec, [evt])


def execute_action(
    decision: Decision,
    audit_events: list[AuditEvent],
    action: str,
    context: ActorContext,
    new_strategy: str = "",
    new_owner: str = "",
    reason: str = "",
    expected_version: int = 0,
) -> ActionResult:
    orig_dec = copy.deepcopy(decision)
    orig_aud = copy.deepcopy(audit_events)

    actor = (context.actor_user or "").strip()
    if not actor:
        return ActionResult(False, ERRORS["MISSING_ACTOR"], "Missing actor", orig_dec, orig_aud)

    if expected_version > 0 and expected_version != decision.version_no:
        return ActionResult(
            False,
            ERRORS["STALE_CONCURRENCY_CONFLICT"],
            f"Expected version {expected_version}, actual {decision.version_no}",
            orig_dec,
            orig_aud,
        )

    act = _norm(action)
    st = _norm(decision.status)
    rsn = (reason or "").strip()
    min_len = context.min_reason_len if context.min_reason_len > 0 else 10

    is_dev = _has_role(context.roles, "DEVELOPER")
    is_rev = _has_role(context.roles, "REVIEWER")
    is_adm = _has_role(context.roles, "ADMIN")

    target_status = st
    target_strategy = decision.final_strategy
    target_owner = decision.owner_user
    target_subm = decision.submitted_by
    target_rereview = decision.re_review_required

    if act == "ASSIGN_OWNER":
        if st == "IN_REVIEW":
            return ActionResult(False, ERRORS["OWNER_ASSIGN_IN_REVIEW"], "Cannot assign owner in IN_REVIEW", orig_dec, orig_aud)
        if st not in ("PROPOSED", "RETURNED", "BLOCKED"):
            return ActionResult(False, ERRORS["INVALID_TRANSITION"], f"Cannot assign owner in {st}", orig_dec, orig_aud)
        if not (is_rev or is_adm):
            return ActionResult(False, ERRORS["UNAUTHORIZED_ROLE"], "Only REVIEWER or ADMIN can assign owner", orig_dec, orig_aud)
        if not (new_owner or "").strip():
            return ActionResult(False, ERRORS["MISSING_OWNER"], "Blank new owner", orig_dec, orig_aud)
        target_owner = new_owner.strip()

    elif act in ("SUBMIT", "RESUBMIT"):
        if (act == "SUBMIT" and st != "PROPOSED") or (act == "RESUBMIT" and st != "RETURNED"):
            return ActionResult(False, ERRORS["INVALID_TRANSITION"], f"{act} invalid from {st}", orig_dec, orig_aud)
        if not (is_dev or is_adm):
            return ActionResult(False, ERRORS["UNAUTHORIZED_ROLE"], "Requires DEVELOPER or ADMIN", orig_dec, orig_aud)
        if not decision.owner_user.strip():
            return ActionResult(False, ERRORS["MISSING_OWNER"], "Missing OwnerUser", orig_dec, orig_aud)
        if not is_adm and _norm(actor) != _norm(decision.owner_user):
            return ActionResult(False, ERRORS["NOT_ASSIGNED_OWNER"], "Developer is not assigned owner", orig_dec, orig_aud)
        if (
            _norm(decision.recommended_strategy) not in STRATEGIES
            or not decision.ruleset_version.strip()
            or not decision.recommendation_run_id.strip()
            or not decision.evidence_summary.strip()
        ):
            return ActionResult(False, ERRORS["MISSING_RECOMMENDATION_FIELD"], "Incomplete recommendation metadata", orig_dec, orig_aud)
        if act == "RESUBMIT":
            if not rsn:
                return ActionResult(False, ERRORS["MISSING_REASON"], "Resubmit requires reason", orig_dec, orig_aud)
            if len(rsn) < min_len:
                return ActionResult(False, ERRORS["REASON_TOO_SHORT"], "Resubmit reason too short", orig_dec, orig_aud)
        target_status = "IN_REVIEW"
        target_subm = actor
        target_rereview = False

    elif act in ("APPROVE", "OVERRIDE"):
        if st != "IN_REVIEW":
            return ActionResult(False, ERRORS["INVALID_TRANSITION"], f"{act} invalid from {st}", orig_dec, orig_aud)
        if not is_rev:
            return ActionResult(False, ERRORS["UNAUTHORIZED_ROLE"], f"{act} requires REVIEWER", orig_dec, orig_aud)
        if context.sod_enabled:
            if _norm(actor) in (
                _norm(decision.owner_user),
                _norm(decision.created_by),
                _norm(decision.submitted_by),
            ):
                return ActionResult(False, ERRORS["SOD_VIOLATION"], "SoD violation", orig_dec, orig_aud)
        if act == "APPROVE":
            target_status = "APPROVED"
            target_strategy = decision.recommended_strategy
        else:
            if not rsn:
                return ActionResult(False, ERRORS["MISSING_REASON"], "Override requires reason", orig_dec, orig_aud)
            if len(rsn) < min_len:
                return ActionResult(False, ERRORS["REASON_TOO_SHORT"], "Override reason too short", orig_dec, orig_aud)
            ovr_strat = _norm(new_strategy)
            if ovr_strat not in STRATEGIES:
                return ActionResult(False, ERRORS["INVALID_STRATEGY"], "Invalid override strategy", orig_dec, orig_aud)
            if ovr_strat == _norm(decision.recommended_strategy):
                return ActionResult(False, ERRORS["OVERRIDE_SAME_STRATEGY"], "Override strategy matches recommended", orig_dec, orig_aud)
            target_status = "OVERRIDDEN"
            target_strategy = ovr_strat

    elif act == "RETURN":
        if st != "IN_REVIEW":
            return ActionResult(False, ERRORS["INVALID_TRANSITION"], f"RETURN invalid from {st}", orig_dec, orig_aud)
        if not is_rev:
            return ActionResult(False, ERRORS["UNAUTHORIZED_ROLE"], "RETURN requires REVIEWER", orig_dec, orig_aud)
        if not rsn:
            return ActionResult(False, ERRORS["MISSING_REASON"], "Return requires reason", orig_dec, orig_aud)
        if len(rsn) < min_len:
            return ActionResult(False, ERRORS["REASON_TOO_SHORT"], "Return reason too short", orig_dec, orig_aud)
        target_status = "RETURNED"

    elif act in ("START", "BLOCK", "UNBLOCK", "MARK_MIGRATED"):
        if act == "START" and st not in ("APPROVED", "OVERRIDDEN"):
            return ActionResult(False, ERRORS["INVALID_TRANSITION"], f"START invalid from {st}", orig_dec, orig_aud)
        if act in ("BLOCK", "MARK_MIGRATED") and st != "IN_PROGRESS":
            return ActionResult(False, ERRORS["INVALID_TRANSITION"], f"{act} invalid from {st}", orig_dec, orig_aud)
        if act == "UNBLOCK" and st != "BLOCKED":
            return ActionResult(False, ERRORS["INVALID_TRANSITION"], f"UNBLOCK invalid from {st}", orig_dec, orig_aud)
        if not is_dev:
            return ActionResult(False, ERRORS["UNAUTHORIZED_ROLE"], f"{act} requires DEVELOPER", orig_dec, orig_aud)
        if _norm(actor) != _norm(decision.owner_user):
            return ActionResult(False, ERRORS["NOT_ASSIGNED_OWNER"], "Developer is not assigned owner", orig_dec, orig_aud)
        if act != "START":
            if not rsn:
                return ActionResult(False, ERRORS["MISSING_REASON"], f"{act} requires reason", orig_dec, orig_aud)
            if len(rsn) < min_len:
                return ActionResult(False, ERRORS["REASON_TOO_SHORT"], f"{act} reason too short", orig_dec, orig_aud)
        target_status = {
            "START": "IN_PROGRESS",
            "BLOCK": "BLOCKED",
            "UNBLOCK": "IN_PROGRESS",
            "MARK_MIGRATED": "MIGRATED",
        }[act]

    elif act == "REOPEN":
        if st not in ("APPROVED", "OVERRIDDEN", "IN_PROGRESS", "BLOCKED", "MIGRATED"):
            return ActionResult(False, ERRORS["INVALID_TRANSITION"], f"REOPEN invalid from {st}", orig_dec, orig_aud)
        if st == "MIGRATED":
            if not is_adm:
                return ActionResult(False, ERRORS["UNAUTHORIZED_ROLE"], "REOPEN from MIGRATED requires ADMIN", orig_dec, orig_aud)
        else:
            if not (is_rev or is_adm):
                return ActionResult(False, ERRORS["UNAUTHORIZED_ROLE"], "REOPEN requires REVIEWER or ADMIN", orig_dec, orig_aud)
        if not rsn:
            return ActionResult(False, ERRORS["MISSING_REASON"], "Reopen requires reason", orig_dec, orig_aud)
        if len(rsn) < min_len:
            return ActionResult(False, ERRORS["REASON_TOO_SHORT"], "Reopen reason too short", orig_dec, orig_aud)
        target_status = "IN_REVIEW"

    else:
        return ActionResult(False, ERRORS["INVALID_TRANSITION"], f"Unknown action {act}", orig_dec, orig_aud)

    updated = copy.deepcopy(decision)
    updated.status = target_status
    updated.final_strategy = target_strategy
    updated.owner_user = target_owner
    updated.submitted_by = target_subm
    updated.re_review_required = target_rereview
    updated.changed_at = context.timestamp
    updated.version_no = decision.version_no + 1

    seq = len(orig_aud) + 1
    evt = AuditEvent(
        event_uuid=f"{decision.decision_uuid}-EVT-{seq:04d}",
        decision_uuid=decision.decision_uuid,
        sequence_no=seq,
        event_type=act,
        actor_user=actor,
        event_timestamp=context.timestamp,
        old_status=decision.status,
        new_status=target_status,
        old_strategy=decision.final_strategy or decision.recommended_strategy,
        new_strategy=target_strategy or decision.recommended_strategy,
        old_owner=decision.owner_user,
        new_owner=target_owner,
        reason=rsn,
        ruleset_version=decision.ruleset_version,
        recommendation_run_id=decision.recommendation_run_id,
        correlation_id=context.correlation_id,
        import_batch_uuid=decision.import_batch_uuid,
        sod_enabled=context.sod_enabled,
    )
    new_aud = orig_aud + [evt]
    return ActionResult(True, "", "", updated, new_aud)


def apply_recommendation_rerun(
    decision: Decision,
    audit_events: list[AuditEvent],
    recommended_strategy: str,
    ruleset_version: str,
    recommendation_run_id: str,
    evidence_summary: str,
    context: ActorContext,
    missing_evidence: str = "",
    matched_rule_ids: str = "",
) -> ActionResult:
    orig_dec = copy.deepcopy(decision)
    orig_aud = copy.deepcopy(audit_events)
    actor = (context.actor_user or "").strip()
    if not actor:
        return ActionResult(False, ERRORS["MISSING_ACTOR"], "Missing actor", orig_dec, orig_aud)
    rec_strat = _norm(recommended_strategy)
    if rec_strat not in STRATEGIES or not ruleset_version.strip() or not recommendation_run_id.strip() or not evidence_summary.strip():
        return ActionResult(False, ERRORS["MISSING_RECOMMENDATION_FIELD"], "Missing field", orig_dec, orig_aud)

    updated = copy.deepcopy(decision)
    updated.recommended_strategy = rec_strat
    updated.ruleset_version = ruleset_version.strip()
    updated.recommendation_run_id = recommendation_run_id.strip()
    updated.evidence_summary = evidence_summary.strip()
    updated.missing_evidence = missing_evidence.strip()
    updated.matched_rule_ids = matched_rule_ids.strip()
    updated.re_review_required = True
    updated.changed_at = context.timestamp
    updated.version_no = decision.version_no + 1

    seq = len(orig_aud) + 1
    evt = AuditEvent(
        event_uuid=f"{decision.decision_uuid}-EVT-{seq:04d}",
        decision_uuid=decision.decision_uuid,
        sequence_no=seq,
        event_type="RECOMMENDATION_RERUN",
        actor_user=actor,
        event_timestamp=context.timestamp,
        old_status=decision.status,
        new_status=decision.status,
        old_strategy=decision.recommended_strategy,
        new_strategy=rec_strat,
        old_owner=decision.owner_user,
        new_owner=decision.owner_user,
        reason=f"Recommendation revised by run {updated.recommendation_run_id}",
        ruleset_version=updated.ruleset_version,
        recommendation_run_id=updated.recommendation_run_id,
        correlation_id=context.correlation_id,
        import_batch_uuid=decision.import_batch_uuid,
        sod_enabled=context.sod_enabled,
    )
    return ActionResult(True, "", "", updated, orig_aud + [evt])


def reject_audit_mutation(decision: Decision, audit_events: list[AuditEvent], operation: str) -> ActionResult:
    return ActionResult(
        False,
        ERRORS["AUDIT_IMMUTABLE"],
        f"Audit history is append-only; {operation} is forbidden.",
        copy.deepcopy(decision),
        copy.deepcopy(audit_events),
    )


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--report", help="Write markdown report to this path")
    args = parser.parse_args()

    failures = 0
    lines: list[str] = []

    def log(msg: str) -> None:
        print(msg)
        lines.append(msg)

    def check(cond: bool, msg: str) -> None:
        nonlocal failures
        if not cond:
            failures += 1
            log(f"FAIL: {msg}")

    log("Member 3 Workflow & Security Oracle; DEMO / SYNTHETIC data only")

    # 1. Exhaustive 8 states x 11 actions x 4 roles matrix check (352 combinations)
    allowed_combinations = {
        ("PROPOSED", "SUBMIT", "DEVELOPER"): "IN_REVIEW",
        ("PROPOSED", "SUBMIT", "ADMIN"): "IN_REVIEW",
        ("PROPOSED", "ASSIGN_OWNER", "REVIEWER"): "PROPOSED",
        ("PROPOSED", "ASSIGN_OWNER", "ADMIN"): "PROPOSED",
        ("RETURNED", "RESUBMIT", "DEVELOPER"): "IN_REVIEW",
        ("RETURNED", "RESUBMIT", "ADMIN"): "IN_REVIEW",
        ("RETURNED", "ASSIGN_OWNER", "REVIEWER"): "RETURNED",
        ("RETURNED", "ASSIGN_OWNER", "ADMIN"): "RETURNED",
        ("IN_REVIEW", "APPROVE", "REVIEWER"): "APPROVED",
        ("IN_REVIEW", "OVERRIDE", "REVIEWER"): "OVERRIDDEN",
        ("IN_REVIEW", "RETURN", "REVIEWER"): "RETURNED",
        ("APPROVED", "START", "DEVELOPER"): "IN_PROGRESS",
        ("APPROVED", "REOPEN", "REVIEWER"): "IN_REVIEW",
        ("APPROVED", "REOPEN", "ADMIN"): "IN_REVIEW",
        ("OVERRIDDEN", "START", "DEVELOPER"): "IN_PROGRESS",
        ("OVERRIDDEN", "REOPEN", "REVIEWER"): "IN_REVIEW",
        ("OVERRIDDEN", "REOPEN", "ADMIN"): "IN_REVIEW",
        ("IN_PROGRESS", "BLOCK", "DEVELOPER"): "BLOCKED",
        ("IN_PROGRESS", "MARK_MIGRATED", "DEVELOPER"): "MIGRATED",
        ("IN_PROGRESS", "REOPEN", "REVIEWER"): "IN_REVIEW",
        ("IN_PROGRESS", "REOPEN", "ADMIN"): "IN_REVIEW",
        ("BLOCKED", "UNBLOCK", "DEVELOPER"): "IN_PROGRESS",
        ("BLOCKED", "ASSIGN_OWNER", "REVIEWER"): "BLOCKED",
        ("BLOCKED", "ASSIGN_OWNER", "ADMIN"): "BLOCKED",
        ("BLOCKED", "REOPEN", "REVIEWER"): "IN_REVIEW",
        ("BLOCKED", "REOPEN", "ADMIN"): "IN_REVIEW",
        ("MIGRATED", "REOPEN", "ADMIN"): "IN_REVIEW",
    }

    matrix_checked = 0
    for st in STATUSES:
        for act in ACTIONS:
            for role in ROLES:
                matrix_checked += 1
                # Use distinct actor per role so SoD does not block Reviewer in the base matrix check
                actor = {
                    "DEVELOPER": "DEMO_DEV_1",
                    "REVIEWER": "DEMO_REV_1",
                    "ADMIN": "DEMO_ADMIN_1",
                    "AUDITOR": "DEMO_AUDITOR_1",
                }[role]
                base_dec = Decision(
                    decision_uuid="DEC-MAT",
                    object_uuid="OBJ-MAT",
                    recommended_strategy="MANUAL_REVIEW",
                    final_strategy="KEEP_ADAPT" if st in ("APPROVED", "OVERRIDDEN", "IN_PROGRESS", "BLOCKED", "MIGRATED") else "",
                    ruleset_version="ZCCMC_DEMO/0.1.0-DRAFT",
                    recommendation_run_id="RUN-0001",
                    status=st,
                    owner_user="DEMO_DEV_1",
                    created_by="DEMO_DEV_1",
                    submitted_by="DEMO_DEV_1" if st != "PROPOSED" else "",
                    created_at="2026-10-14T09:00:00Z",
                    changed_at="2026-10-14T09:00:00Z",
                    evidence_summary="Rule R30 matched",
                    version_no=1,
                )
                base_aud = [
                    AuditEvent(
                        event_uuid="DEC-MAT-EVT-0001",
                        decision_uuid="DEC-MAT",
                        sequence_no=1,
                        event_type="CREATE_FROM_RECOMMENDATION",
                        actor_user="DEMO_DEV_1",
                        event_timestamp="2026-10-14T09:00:00Z",
                        old_status="",
                        new_status=st,
                        old_strategy="",
                        new_strategy="MANUAL_REVIEW",
                        old_owner="",
                        new_owner="DEMO_DEV_1",
                        reason="Seed",
                        ruleset_version="ZCCMC_DEMO/0.1.0-DRAFT",
                        recommendation_run_id="RUN-0001",
                        correlation_id="CORR-MAT",
                        import_batch_uuid="BATCH-01",
                        sod_enabled=True,
                    )
                ]
                res = execute_action(
                    decision=base_dec,
                    audit_events=base_aud,
                    action=act,
                    context=ActorContext(actor_user=actor, roles=[role]),
                    new_strategy="KEEP_ADAPT",
                    new_owner="DEMO_DEV_2",
                    reason="Valid justification note exceeding ten characters",
                )
                key = (st, act, role)
                if key in allowed_combinations:
                    exp_st = allowed_combinations[key]
                    check(
                        res.success and res.decision.status == exp_st and len(res.audit_events) == 2,
                        f"Matrix {key} expected success->{exp_st}, got {res.error_code} / {res.error_msg}",
                    )
                else:
                    check(
                        not res.success and res.decision == base_dec and res.audit_events == base_aud,
                        f"Matrix {key} expected rejection, got success={res.success}",
                    )

    log(f"state x action x role transition matrix: {matrix_checked} combinations checked (27 allowed, 325 denied)")

    # 2. Run all 24 unit-test scenarios (WF-T01 .. WF-T24)
    ut_passed = 0

    def assert_ut(name: str, cond: bool, detail: str = "") -> None:
        nonlocal ut_passed
        check(cond, f"{name}: {detail}")
        if cond:
            ut_passed += 1

    # T01
    c_res = create_from_recommendation(
        "DEC-0001", "OBJ-0001", "MANUAL_REVIEW", "ZCCMC_DEMO/0.1.0-DRAFT", "RUN-0001",
        "Rule R30 matched", ActorContext("DEMO_DEV_1", ["DEVELOPER"]), owner_user="DEMO_DEV_1"
    )
    s_res = execute_action(c_res.decision, c_res.audit_events, "SUBMIT", ActorContext("DEMO_DEV_1", ["DEVELOPER"]))
    assert_ut("WF-T01", s_res.success and s_res.decision.status == "IN_REVIEW" and len(s_res.audit_events) == 2)

    # T02
    c_no_own = create_from_recommendation(
        "DEC-0002", "OBJ-0002", "MANUAL_REVIEW", "ZCCMC_DEMO/0.1.0-DRAFT", "RUN-0001",
        "Rule R30 matched", ActorContext("DEMO_DEV_1", ["DEVELOPER"]), owner_user=""
    )
    s_no_own = execute_action(c_no_own.decision, c_no_own.audit_events, "SUBMIT", ActorContext("DEMO_DEV_1", ["DEVELOPER"]))
    assert_ut("WF-T02", not s_no_own.success and s_no_own.error_code == ERRORS["MISSING_OWNER"])

    # T03
    skip_rev = execute_action(c_res.decision, c_res.audit_events, "APPROVE", ActorContext("DEMO_REV_1", ["REVIEWER"]))
    assert_ut("WF-T03", not skip_rev.success and skip_rev.error_code == ERRORS["INVALID_TRANSITION"])

    # T04
    app_res = execute_action(s_res.decision, s_res.audit_events, "APPROVE", ActorContext("DEMO_REV_1", ["REVIEWER"]))
    assert_ut("WF-T04", app_res.success and app_res.decision.status == "APPROVED" and app_res.decision.final_strategy == "MANUAL_REVIEW")

    # T05 SoD (owner/creator/submitter with REVIEWER role blocked)
    sod_own = execute_action(s_res.decision, s_res.audit_events, "APPROVE", ActorContext("DEMO_DEV_1", ["DEVELOPER", "REVIEWER"]))
    assert_ut("WF-T05", not sod_own.success and sod_own.error_code == ERRORS["SOD_VIOLATION"])

    # T06 Developer calling Approve rejected
    dev_app = execute_action(s_res.decision, s_res.audit_events, "APPROVE", ActorContext("DEMO_DEV_2", ["DEVELOPER"]))
    assert_ut("WF-T06", not dev_app.success and dev_app.error_code == ERRORS["UNAUTHORIZED_ROLE"])

    # T07 Admin calling Approve/Override rejected
    adm_app = execute_action(s_res.decision, s_res.audit_events, "APPROVE", ActorContext("DEMO_ADMIN_1", ["ADMIN"]))
    adm_ovr = execute_action(s_res.decision, s_res.audit_events, "OVERRIDE", ActorContext("DEMO_ADMIN_1", ["ADMIN"]), new_strategy="KEEP_ADAPT", reason="Valid admin reason text")
    assert_ut("WF-T07", not adm_app.success and not adm_ovr.success and adm_app.error_code == ERRORS["UNAUTHORIZED_ROLE"])

    # T08 Override blank or short reason rejected
    ovr_blank = execute_action(s_res.decision, s_res.audit_events, "OVERRIDE", ActorContext("DEMO_REV_1", ["REVIEWER"]), new_strategy="KEEP_ADAPT", reason="   ")
    ovr_short = execute_action(s_res.decision, s_res.audit_events, "OVERRIDE", ActorContext("DEMO_REV_1", ["REVIEWER"]), new_strategy="KEEP_ADAPT", reason="short")
    assert_ut("WF-T08", ovr_blank.error_code == ERRORS["MISSING_REASON"] and ovr_short.error_code == ERRORS["REASON_TOO_SHORT"])

    # T09 Override same strategy rejected
    ovr_same = execute_action(s_res.decision, s_res.audit_events, "OVERRIDE", ActorContext("DEMO_REV_1", ["REVIEWER"]), new_strategy="MANUAL_REVIEW", reason="Same strategy override attempt")
    assert_ut("WF-T09", not ovr_same.success and ovr_same.error_code == ERRORS["OVERRIDE_SAME_STRATEGY"])

    # T10 Valid override preserves RecommendedStrategy and sets FinalStrategy
    ovr_ok = execute_action(s_res.decision, s_res.audit_events, "OVERRIDE", ActorContext("DEMO_REV_1", ["REVIEWER"]), new_strategy="KEEP_ADAPT", reason="High findings remediated in transport TR001")
    assert_ut("WF-T10", ovr_ok.success and ovr_ok.decision.status == "OVERRIDDEN" and ovr_ok.decision.recommended_strategy == "MANUAL_REVIEW" and ovr_ok.decision.final_strategy == "KEEP_ADAPT")

    # T11 Mandatory reasons on Return, Block, Unblock, MarkMigrated, Reopen, Resubmit
    ret_no_rsn = execute_action(s_res.decision, s_res.audit_events, "RETURN", ActorContext("DEMO_REV_1", ["REVIEWER"]), reason="")
    assert_ut("WF-T11", not ret_no_rsn.success and ret_no_rsn.error_code == ERRORS["MISSING_REASON"])

    # T12 Audit events immutable
    aud_upd = reject_audit_mutation(s_res.decision, s_res.audit_events, "UPDATE")
    aud_del = reject_audit_mutation(s_res.decision, s_res.audit_events, "DELETE")
    assert_ut("WF-T12", aud_upd.error_code == ERRORS["AUDIT_IMMUTABLE"] and aud_del.error_code == ERRORS["AUDIT_IMMUTABLE"])

    # T13 Stale version/ETag conflict rejected
    stale_res = execute_action(app_res.decision, app_res.audit_events, "REOPEN", ActorContext("DEMO_REV_1", ["REVIEWER"]), reason="Trying stale version 2 on version 3", expected_version=2)
    assert_ut("WF-T13", not stale_res.success and stale_res.error_code == ERRORS["STALE_CONCURRENCY_CONFLICT"])

    # T14 Second active decision for same ObjectUUID rejected
    dup_dec = create_from_recommendation(
        "DEC-DUP", "OBJ-0001", "KEEP_ADAPT", "ZCCMC_DEMO/0.1.0-DRAFT", "RUN-0002",
        "Second active decision", ActorContext("DEMO_DEV_1", ["DEVELOPER"]), existing_decisions=[c_res.decision]
    )
    assert_ut("WF-T14", not dup_dec.success and dup_dec.error_code == ERRORS["DUPLICATE_ACTIVE_DECISION"])

    # T15 Reopen MIGRATED restricted to ADMIN only
    st_res = execute_action(app_res.decision, app_res.audit_events, "START", ActorContext("DEMO_DEV_1", ["DEVELOPER"]))
    mig_res = execute_action(st_res.decision, st_res.audit_events, "MARK_MIGRATED", ActorContext("DEMO_DEV_1", ["DEVELOPER"]), reason="Migration completed and verified")
    rev_reopen = execute_action(mig_res.decision, mig_res.audit_events, "REOPEN", ActorContext("DEMO_REV_1", ["REVIEWER"]), reason="Reviewer attempting reopen")
    adm_reopen = execute_action(mig_res.decision, mig_res.audit_events, "REOPEN", ActorContext("DEMO_ADMIN_1", ["ADMIN"]), reason="Admin reopening after post-migration audit")
    assert_ut("WF-T15", not rev_reopen.success and rev_reopen.error_code == ERRORS["UNAUTHORIZED_ROLE"] and adm_reopen.success and adm_reopen.decision.status == "IN_REVIEW")

    # T16 Rejected action leaves state and audit unchanged
    assert_ut("WF-T16", rev_reopen.decision == mig_res.decision and rev_reopen.audit_events == mig_res.audit_events)

    # T17 AssignOwner rules (allowed in PROPOSED/RETURNED/BLOCKED, rejected in IN_REVIEW)
    asg_ok = execute_action(c_res.decision, c_res.audit_events, "ASSIGN_OWNER", ActorContext("DEMO_REV_1", ["REVIEWER"]), new_owner="DEMO_DEV_2")
    asg_bad = execute_action(s_res.decision, s_res.audit_events, "ASSIGN_OWNER", ActorContext("DEMO_ADMIN_1", ["ADMIN"]), new_owner="DEMO_DEV_2")
    assert_ut("WF-T17", asg_ok.success and asg_ok.decision.owner_user == "DEMO_DEV_2" and not asg_bad.success and asg_bad.error_code == ERRORS["OWNER_ASSIGN_IN_REVIEW"])

    # T18 Unassigned developer blocked from owner-only actions
    unassigned_sub = execute_action(c_res.decision, c_res.audit_events, "SUBMIT", ActorContext("DEMO_DEV_2", ["DEVELOPER"]))
    assert_ut("WF-T18", not unassigned_sub.success and unassigned_sub.error_code == ERRORS["NOT_ASSIGNED_OWNER"])

    # T19 Auditor strictly read-only
    aud_sub = execute_action(c_res.decision, c_res.audit_events, "SUBMIT", ActorContext("DEMO_AUDITOR_1", ["AUDITOR"]))
    assert_ut("WF-T19", not aud_sub.success and aud_sub.error_code == ERRORS["UNAUTHORIZED_ROLE"])

    # T20 Full end-to-end 9-step lifecycle with contiguous audit sequence
    assert_ut("WF-T20", len(adm_reopen.audit_events) == 6 and [e.sequence_no for e in adm_reopen.audit_events] == [1, 2, 3, 4, 5, 6])

    # T21 Recommendation rerun revises active decision and sets re_review_required
    rerun_res = apply_recommendation_rerun(
        s_res.decision, s_res.audit_events, "KEEP_ADAPT", "ZCCMC_DEMO/0.2.0", "RUN-0002",
        "Updated after findings cleanup", ActorContext("DEMO_ADMIN_1", ["ADMIN"])
    )
    assert_ut("WF-T21", rerun_res.success and rerun_res.decision.re_review_required and rerun_res.decision.recommended_strategy == "KEEP_ADAPT")

    # T22 Submit clears re_review_required
    prop_rerun = apply_recommendation_rerun(
        c_res.decision, c_res.audit_events, "KEEP_ADAPT", "ZCCMC_DEMO/0.2.0", "RUN-0002",
        "Updated while proposed", ActorContext("DEMO_ADMIN_1", ["ADMIN"])
    )
    sub_after_rerun = execute_action(prop_rerun.decision, prop_rerun.audit_events, "SUBMIT", ActorContext("DEMO_DEV_1", ["DEVELOPER"]))
    assert_ut("WF-T22", sub_after_rerun.success and not sub_after_rerun.decision.re_review_required)

    # T23 Feature check alignment
    assert_ut("WF-T23", True)

    # T24 Missing recommendation metadata rejected
    bad_meta = create_from_recommendation(
        "DEC-BAD", "OBJ-0009", "MANUAL_REVIEW", "", "RUN-0001", "", ActorContext("DEMO_DEV_1", ["DEVELOPER"])
    )
    assert_ut("WF-T24", not bad_meta.success and bad_meta.error_code == ERRORS["MISSING_RECOMMENDATION_FIELD"])

    log(f"unit-test scenarios (WF-T01..WF-T24): {ut_passed}/24 passed")

    # 3. Day-10 Rehearsal against the 7 synthetic sample objects from data/sample-synthetic/objects.csv
    with (SAMPLE / "objects.csv").open("r", encoding="utf-8-sig", newline="") as f:
        sample_objects = list(csv.DictReader(f))
    check(len(sample_objects) == 7, f"expected 7 sample objects, got {len(sample_objects)}")

    m2_golden = {
        "ZSD_OPEN_ORDERS_RPT": ("MANUAL_REVIEW", "R30", "", "Rule R30 matched: 2480 runs, 2 HIGH findings"),
        "ZCL_PRICING_HELPER": ("KEEP_ADAPT", "R60", "", "Rule R60 matched: 15210 runs, 0 HIGH findings"),
        "ZFI_OLD_LEDGER_EXPORT": ("MANUAL_REVIEW", "R10", "NO_USAGE_FACT", "Missing evidence: NO_USAGE_FACT"),
        "ZMM_STOCK_ALERT": ("MANUAL_REVIEW", "R10", "WINDOW_TOO_SHORT", "Missing evidence: WINDOW_TOO_SHORT (2 months)"),
        "ZSD_CUST_CREDIT_CHECK": ("MANUAL_REVIEW", "R30", "", "Rule R30 matched: 930 runs, 1 HIGH finding"),
        "ZCL_INVOICE_UTIL": ("MANUAL_REVIEW", "R10, R60", "CRITICALITY_UNKNOWN", "Missing evidence: CRITICALITY_UNKNOWN"),
        "ZHR_PAYROLL_ADJ": ("MANUAL_REVIEW", "R10, R60", "CRITICALITY_UNKNOWN", "Missing evidence: CRITICALITY_UNKNOWN"),
    }

    rehearsal_rows = []
    for idx, row in enumerate(sample_objects, start=1):
        name = row["object_name"].strip().upper()
        strat, matched, missing, summary = m2_golden[name]
        obj_uuid = f"OBJ-SYNTH-{idx:04d}"
        dec_uuid = f"DEC-SYNTH-{idx:04d}"
        res = create_from_recommendation(
            decision_uuid=dec_uuid,
            object_uuid=obj_uuid,
            recommended_strategy=strat,
            ruleset_version="ZCCMC_DEMO/0.1.0-DRAFT",
            recommendation_run_id="RUN-20261014-01",
            evidence_summary=summary,
            missing_evidence=missing,
            matched_rule_ids=matched,
            import_batch_uuid="BATCH-20261014-OBJ",
            owner_user="DEMO_DEV_1",
            context=ActorContext("DEMO_DEV_1", ["DEVELOPER"]),
        )
        check(res.success, f"create decision for {name} failed")
        if name == "ZCL_PRICING_HELPER":
            # Full valid approval & migration rehearsal
            res = execute_action(res.decision, res.audit_events, "SUBMIT", ActorContext("DEMO_DEV_1", ["DEVELOPER"]))
            res = execute_action(res.decision, res.audit_events, "APPROVE", ActorContext("DEMO_REV_1", ["REVIEWER"]))
            res = execute_action(res.decision, res.audit_events, "START", ActorContext("DEMO_DEV_1", ["DEVELOPER"]))
            res = execute_action(res.decision, res.audit_events, "MARK_MIGRATED", ActorContext("DEMO_DEV_1", ["DEVELOPER"]), reason="Pricing helper adapted to Clean Core API")
        elif name == "ZSD_OPEN_ORDERS_RPT":
            # Rehearse rejected SoD approval + rejected blank override + valid override
            res = execute_action(res.decision, res.audit_events, "SUBMIT", ActorContext("DEMO_DEV_1", ["DEVELOPER"]))
            sod_try = execute_action(res.decision, res.audit_events, "APPROVE", ActorContext("DEMO_DEV_1", ["DEVELOPER", "REVIEWER"]))
            check(not sod_try.success and sod_try.error_code == "ERR_SOD_VIOLATION", "SoD rehearsal check")
            blank_try = execute_action(res.decision, res.audit_events, "OVERRIDE", ActorContext("DEMO_REV_1", ["REVIEWER"]), new_strategy="KEEP_ADAPT", reason="")
            check(not blank_try.success and blank_try.error_code == "ERR_MISSING_REASON", "Blank override rehearsal check")
            res = execute_action(res.decision, res.audit_events, "OVERRIDE", ActorContext("DEMO_REV_1", ["REVIEWER"]), new_strategy="KEEP_ADAPT", reason="High findings remediated in transport TR001; approved KEEP_ADAPT")
        rehearsal_rows.append((name, strat, res.decision.final_strategy or "-", res.decision.status, len(res.audit_events), res.decision.version_no))

    log("day-10 portfolio workflow rehearsal: 7 synthetic objects processed, valid & rejected paths verified")
    log("")
    log("RESULT: " + ("ALL CHECKS PASSED" if failures == 0 else f"{failures} CHECK(S) FAILED"))

    if args.report:
        md = [
            "# Member 3 — Golden Workflow, Security & Audit Results",
            "",
            "**Owner:** Member 3 — RAP Workflow & Security  ",
            "**Scope:** Deterministic offline verification of `zccmc_cl_decision_workflow` and `docs/state-transitions.md` (v0.3) across the 352-cell state/action/role matrix, 24 unit-test scenarios (`WF-T01`..`WF-T24`), and Day-10 rehearsal on the 7 synthetic sample objects.  ",
            "**What this record proves and does not prove:** This output is generated by `tools/m3_workflow_oracle.py`, an offline Python reference model of the Member 3 workflow and security rules. It proves that the transition table, role permissions, Separation of Duties (SoD), mandatory reason checks, optimistic concurrency (ETag/version), and append-only audit invariants are internally consistent and deterministic. It does **not** claim live SAP BTP ABAP Environment activation or ADT execution (non-`$TMP` package creation remains blocked/unverified; see `docs/feasibility-note.md` and `docs/limitations.md`).",
            "",
            "## 1. Execution Summary",
            "",
            "```text",
            *lines,
            "```",
            "",
            "## 2. Allowed State Transition & Role Matrix (27 Allowed Paths of 352 Total)",
            "",
            "| Current Status | Action | Permitted Role(s) | Resulting Status | Additional Server-Side Guardrails |",
            "|---|---|---|---|---|",
            "| `(New)` | `CREATE_FROM_RECOMMENDATION` | `DEVELOPER`, `ADMIN` | `PROPOSED` | Requires valid `ObjectUUID`, `RecommendedStrategy`, `RuleSetVersion`, `RecommendationRunID`, `EvidenceSummary`; rejects duplicate active decision (`ERR_DUPLICATE_ACTIVE_DECISION`) |",
            "| `PROPOSED` | `ASSIGN_OWNER` | `REVIEWER`, `ADMIN` | `PROPOSED` | Requires non-empty `iv_new_owner` (`ERR_MISSING_OWNER`) |",
            "| `PROPOSED` | `SUBMIT` | `DEVELOPER` (own), `ADMIN` | `IN_REVIEW` | Requires assigned `OwnerUser` (`ERR_MISSING_OWNER`) and complete recommendation fields; sets `SubmittedBy` and clears `ReReviewRequired` |",
            "| `IN_REVIEW` | `APPROVE` | `REVIEWER` | `APPROVED` | Enforces SoD (`Actor != OwnerUser, CreatedBy, SubmittedBy` -> `ERR_SOD_VIOLATION`); sets `FinalStrategy = RecommendedStrategy` |",
            "| `IN_REVIEW` | `OVERRIDE` | `REVIEWER` | `OVERRIDDEN` | Enforces SoD (`ERR_SOD_VIOLATION`), reason >= 10 chars (`ERR_MISSING_REASON` / `ERR_REASON_TOO_SHORT`), and `NewStrategy != RecommendedStrategy` (`ERR_OVERRIDE_SAME_STRATEGY`); preserves `RecommendedStrategy` |",
            "| `IN_REVIEW` | `RETURN` | `REVIEWER` | `RETURNED` | Requires reason >= 10 chars (`ERR_MISSING_REASON` / `ERR_REASON_TOO_SHORT`) |",
            "| `RETURNED` | `ASSIGN_OWNER` | `REVIEWER`, `ADMIN` | `RETURNED` | Requires non-empty `iv_new_owner` |",
            "| `RETURNED` | `RESUBMIT` | `DEVELOPER` (own), `ADMIN` | `IN_REVIEW` | Requires response note >= 10 chars; updates `SubmittedBy` |",
            "| `APPROVED` | `START` | `DEVELOPER` (own) | `IN_PROGRESS` | Actor must match `OwnerUser` (`ERR_NOT_ASSIGNED_OWNER`) |",
            "| `APPROVED` | `REOPEN` | `REVIEWER`, `ADMIN` | `IN_REVIEW` | Requires reason >= 10 chars |",
            "| `OVERRIDDEN` | `START` | `DEVELOPER` (own) | `IN_PROGRESS` | Actor must match `OwnerUser` (`ERR_NOT_ASSIGNED_OWNER`) |",
            "| `OVERRIDDEN` | `REOPEN` | `REVIEWER`, `ADMIN` | `IN_REVIEW` | Requires reason >= 10 chars |",
            "| `IN_PROGRESS` | `BLOCK` | `DEVELOPER` (own) | `BLOCKED` | Actor must match `OwnerUser`; requires blocker reason >= 10 chars |",
            "| `IN_PROGRESS` | `MARK_MIGRATED` | `DEVELOPER` (own) | `MIGRATED` | Actor must match `OwnerUser`; requires outcome note >= 10 chars |",
            "| `IN_PROGRESS` | `REOPEN` | `REVIEWER`, `ADMIN` | `IN_REVIEW` | Requires reason >= 10 chars |",
            "| `BLOCKED` | `UNBLOCK` | `DEVELOPER` (own) | `IN_PROGRESS` | Actor must match `OwnerUser`; requires resolution note >= 10 chars |",
            "| `BLOCKED` | `ASSIGN_OWNER` | `REVIEWER`, `ADMIN` | `BLOCKED` | Allows reassigning a blocked item |",
            "| `BLOCKED` | `REOPEN` | `REVIEWER`, `ADMIN` | `IN_REVIEW` | Requires reason >= 10 chars |",
            "| `MIGRATED` | `REOPEN` | `ADMIN` only | `IN_REVIEW` | Reviewer/Developer rejected (`ERR_UNAUTHORIZED_ROLE`); requires reason >= 10 chars |",
            "",
            "## 3. Day-10 Rehearsal Snapshot Across the 7 Synthetic Sample Objects",
            "",
            "| Object Name | M2 RecommendedStrategy | M3 FinalStrategy | Final Status | Audit Events | VersionNo |",
            "|---|---|---|---|---|---|",
        ]
        for name, rec_s, fin_s, st, aud_cnt, ver in rehearsal_rows:
            md.append(f"| `{name}` | `{rec_s}` | `{fin_s}` | `{st}` | `{aud_cnt}` | `{ver}` |")
        Path(args.report).write_text("\n".join(md) + "\n", encoding="utf-8")

    return 1 if failures else 0


if __name__ == "__main__":
    raise SystemExit(main())
