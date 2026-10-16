#!/usr/bin/env python3
"""Reference model and regression runner for Member 2 Rules & Analytics v1.0.0 (docs/rules-spec.md).

This is the offline TEST ORACLE for:
  * src/zccmc_core/zccmc_cl_rule_engine.clas.abap (including build_evidence_from_import bridge)
  * src/zccmc_core/zccmc_cl_portfolio_analytics.clas.abap (including build_items_from_results bridge)
  * src/zccmc_test/zccmc_ut_rule_engine.clas.abap (31 ABAP Unit methods: T01..T31)
  * src/zccmc_test/zccmc_ut_portfolio_analytics.clas.abap (13 ABAP Unit methods: PA-T01..PA-T13)

Aligned with Member 1's Day 1–11 completed persistence & import contract (v0.3,
zccmc_cl_import_orchestrator=>build_m2_evidence_for_obj & reset_synthetic_data).
DEMO / SYNTHETIC data only.

Usage (repository root):
    python3 tools/m2_rules_oracle.py                              # run all checks, exit 1 on failure
    python3 tools/m2_rules_oracle.py --report docs/m2-golden-results.md
"""
from __future__ import annotations

import argparse
import copy
import csv
import datetime as dt
import random
import sys
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SAMPLE = ROOT / "data" / "sample-synthetic"
EVAL_DATE = dt.date(2026, 10, 14)

# ---------------------------------------------------------------- frozen v1.0.0 rule set (spec section 5)
RULESET_ID = "ZCCMC_DEMO"
RULESET_VERSION = "1.0.0"
PARAMS = {"min_window_months": 12, "max_evidence_age_days": 30, "high_finding_min_count": 1}
SEED_RULES = [
    {
        "id": "R10",
        "prio": 10,
        "active": True,
        "cond": "EVIDENCE_PROBLEM",
        "outcome": "MANUAL_REVIEW",
        "rationale": "Evidence is missing, stale, unknown or contradictory; a human must decide.",
    },
    {
        "id": "R20",
        "prio": 20,
        "active": True,
        "cond": "NO_USE_COMPLETE_WINDOW",
        "outcome": "RETIRE_CANDIDATE",
        "rationale": "No runs over a complete observation window and no HIGH-criticality caller; retirement candidate, the owner must confirm.",
    },
    {
        "id": "R30",
        "prio": 30,
        "active": True,
        "cond": "USED_WITH_HIGH_FINDING",
        "outcome": "MANUAL_REVIEW",
        "rationale": "The object is used and has HIGH-severity findings; a human must assess the impact.",
    },
    {
        "id": "R60",
        "prio": 60,
        "active": True,
        "cond": "USED_WITHOUT_HIGH_FINDING",
        "outcome": "KEEP_ADAPT",
        "rationale": "The object is used and has no HIGH-severity findings; keep and adapt.",
    },
]


def add_months(d: dt.date, n: int) -> dt.date:
    index = d.year * 12 + (d.month - 1) + n
    year, month = divmod(index, 12)
    month += 1
    nxt = dt.date(year + (month == 12), month % 12 + 1, 1)
    last = (nxt - dt.timedelta(days=1)).day
    return dt.date(year, month, min(d.day, last))


def whole_months(start: dt.date | None, end: dt.date | None) -> int:
    if not start or not end or end < start:
        return 0
    n = (end.year - start.year) * 12 + (end.month - start.month)
    n = max(n, 0)
    if add_months(start, n) > end:
        n -= 1
    return max(n, 0)


def date_text(d_val: dt.date | None) -> str:
    return d_val.isoformat() if d_val else "none"


def build_evidence_from_import(
    object_id: str,
    criticality: str = "",
    findings_as_of: dt.date | None = None,
    usages: list[dict] | None = None,
    findings: list[str] | None = None,
    callers: list[str] | None = None,
) -> dict:
    """Exact mirror of zccmc_cl_rule_engine=>build_evidence_from_import."""
    crit = (criticality or "").strip().upper()
    if crit not in ("HIGH", "MEDIUM", "LOW"):
        crit = "UNKNOWN"
    norm_findings = [s.strip().upper() for s in (findings or [])]
    norm_callers = []
    for c in (callers or []):
        cv = (c or "").strip().upper()
        norm_callers.append(cv if cv in ("HIGH", "MEDIUM", "LOW") else "UNKNOWN")
    return {
        "object_id": (object_id or "").strip(),
        "criticality": crit,
        "findings_as_of": findings_as_of,
        "usages": list(usages or []),
        "findings": norm_findings,
        "callers": norm_callers,
    }


def build_explanation(
    facts: dict,
    strategy: str,
    missing: list[str],
    matched_rules: list[dict],
    priority: int,
    evidence_problem: bool,
    reason: str,
) -> str:
    """Exact mirror of zccmc_cl_rule_engine=>build_explanation."""
    ev_parts = [f"criticality={facts['criticality']}", f"usage_facts={facts['usage_count']}"]
    if facts["usage_count"] == 1:
        ev_parts.extend([
            f"run_count={facts['run_count']}",
            f"window_months={facts['window_months']}",
            f"last_executed={date_text(facts['last_executed'])}",
            f"evidence_as_of={date_text(facts['evidence_as_of'])}",
        ])
    ev_parts.extend([
        f"findings_known={'yes' if facts['findings_known'] else 'no'}",
        f"high_findings={facts['high_findings']}",
        f"high_criticality_caller={'yes' if facts['has_high_caller'] else 'no'}",
    ])
    ev_str = "; ".join(ev_parts)

    if evidence_problem:
        return f"{strategy}: safe default because of: {', '.join(missing)}. Evidence: {ev_str}."
    if reason == "RULE_CONFLICT":
        ids = [m["id"] for m in matched_rules if m["prio"] == priority]
        return (
            f"{strategy}: active rules {', '.join(ids)} share priority {priority} "
            f"but give different outcomes; the engine does not pick one. Evidence: {ev_str}."
        )
    if reason == "NO_RULE_MATCH":
        return f"{strategy}: no active rule matched, so the safe default applies. Evidence: {ev_str}."
    winner = matched_rules[0]
    return f"Rule {winner['id']} (priority {priority}): {winner['rationale']} Result {strategy}. Evidence: {ev_str}."


def evaluate(
    evidence: dict,
    rules=None,
    params=None,
    eval_date: dt.date = EVAL_DATE,
    run_id: str = "RUN-0001",
    ruleset_id: str = RULESET_ID,
    ruleset_version: str = RULESET_VERSION,
) -> dict:
    """Exact mirror of zccmc_cl_rule_engine=>evaluate_object."""
    rules = SEED_RULES if rules is None else rules
    params = PARAMS if params is None else params
    missing: list[str] = []

    crit = (evidence.get("criticality") or "").strip().upper()
    if crit not in ("HIGH", "MEDIUM", "LOW"):
        crit = "UNKNOWN"
    usages = evidence.get("usages", [])
    n_usage = len(usages)
    run_count = 0
    window_valid = False
    window_months = 0
    last_executed = None
    evidence_as_of = None

    if n_usage == 0:
        missing.append("NO_USAGE_FACT")
    elif n_usage > 1:
        missing.append("MULTIPLE_USAGE_FACTS")
    else:
        u = usages[0]
        run_count = u["run_count"]
        last_executed = u["last_executed"]
        evidence_as_of = u["evidence_as_of"]
        if u["period_end"] < u["period_start"]:
            missing.append("PERIOD_END_BEFORE_START")
        else:
            window_valid = True
            window_months = whole_months(u["period_start"], u["period_end"])
            if window_months < params["min_window_months"]:
                missing.append("WINDOW_TOO_SHORT")
        if not evidence_as_of or (eval_date - evidence_as_of).days > params["max_evidence_age_days"]:
            missing.append("EVIDENCE_STALE")
        if run_count == 0 and last_executed:
            missing.append("ZERO_RUNS_WITH_LAST_EXECUTED")
        if run_count > 0 and not last_executed:
            missing.append("RUNS_WITHOUT_LAST_EXECUTED")

    if crit == "UNKNOWN":
        missing.append("CRITICALITY_UNKNOWN")
    findings_known = bool(evidence.get("findings_as_of"))
    if not findings_known:
        missing.append("FINDINGS_NOT_LOADED")
    high = sum(1 for s in evidence.get("findings", []) if s.strip().upper() == "HIGH")

    caller_crits = [c.strip().upper() for c in evidence.get("callers", [])]
    has_high_caller = "HIGH" in caller_crits
    unknown_callers = sum(1 for c in caller_crits if c not in ("HIGH", "MEDIUM", "LOW"))
    if n_usage == 1 and run_count == 0 and not has_high_caller and unknown_callers > 0:
        missing.append("CALLER_CRITICALITY_UNKNOWN")

    facts = {
        "criticality": crit,
        "usage_count": n_usage,
        "run_count": run_count,
        "window_valid": window_valid,
        "window_months": window_months,
        "last_executed": last_executed,
        "evidence_as_of": evidence_as_of,
        "findings_known": findings_known,
        "high_findings": high,
        "has_high_caller": has_high_caller,
        "unknown_callers": unknown_callers,
    }

    def matches(cond: str):
        c = cond.strip().upper()
        if c == "EVIDENCE_PROBLEM":
            return bool(missing)
        if c == "NO_USE_COMPLETE_WINDOW":
            return (
                n_usage == 1
                and run_count == 0
                and window_valid
                and window_months >= params["min_window_months"]
                and not has_high_caller
            )
        if c == "USED_WITH_HIGH_FINDING":
            return n_usage == 1 and run_count > 0 and high >= params["high_finding_min_count"]
        if c == "USED_WITHOUT_HIGH_FINDING":
            return n_usage == 1 and run_count > 0 and high < params["high_finding_min_count"]
        return None  # unknown condition code

    matched, bad_code = [], False
    for r in rules:
        if not r["active"]:
            continue
        norm_r = dict(r)
        norm_r["id"] = norm_r["id"].strip().upper()
        norm_r["cond"] = norm_r["cond"].strip().upper()
        norm_r["outcome"] = norm_r["outcome"].strip().upper()
        m = matches(norm_r["cond"])
        if m is None:
            bad_code = True
        elif m:
            matched.append(norm_r)
    matched.sort(key=lambda r: (r["prio"], r["id"]))
    if bad_code:
        missing.append("UNKNOWN_CONDITION_CODE")

    reason = ""
    best_prio = 0
    if not matched:
        strategy, reason = "MANUAL_REVIEW", "NO_RULE_MATCH"
    else:
        best_prio = matched[0]["prio"]
        outcomes = {r["outcome"] for r in matched if r["prio"] == best_prio}
        if len(outcomes) > 1:
            strategy, reason = "MANUAL_REVIEW", "RULE_CONFLICT"
        else:
            strategy = matched[0]["outcome"]

    evidence_problem = bool(missing)
    if evidence_problem:  # hard safety invariant
        strategy = "MANUAL_REVIEW"
    elif reason:
        missing.append(reason)

    explanation = build_explanation(facts, strategy, missing, matched, best_prio, evidence_problem, reason)
    return {
        "object_id": evidence.get("object_id", ""),
        "run_id": run_id,
        "strategy": strategy,
        "ruleset_id": ruleset_id,
        "ruleset_version": ruleset_version,
        "explanation": explanation,
        "matched": [r["id"] for r in matched],
        "missing": missing,
    }


# ---------------------------------------------------------------- fixtures from the CSV files
def read(name: str) -> list[dict]:
    with (SAMPLE / name).open(encoding="utf-8-sig", newline="") as fh:
        return list(csv.DictReader(fh))


def d(value: str) -> dt.date | None:
    return dt.date.fromisoformat(value) if value else None


def key(r: dict, t="object_type", n="object_name") -> tuple[str, str, str]:
    return (r["source_system"].strip().upper(), r[t].strip().upper(), r[n].strip().upper())


def build_evidence(objects, usage, findings, deps) -> dict:
    by_key = {key(o): o for o in objects}
    raw_usages = {k: [] for k in by_key}
    raw_findings = {k: [] for k in by_key}
    raw_callers = {k: [] for k in by_key}
    for u in usage:
        raw_usages[key(u)].append({
            "period_start": d(u["period_start"]),
            "period_end": d(u["period_end"]),
            "last_executed": d(u["last_executed"]),
            "run_count": int(u["run_count"]),
            "evidence_as_of": d(u["evidence_as_of"]),
        })
    for f in findings:
        raw_findings[key(f)].append(f["severity"])
    for dep in deps:
        target = key(dep, "to_type", "to_name")
        caller = key(dep, "from_type", "from_name")
        raw_callers[target].append(by_key[caller]["criticality"])

    ev = {}
    for k, o in by_key.items():
        ev[k] = build_evidence_from_import(
            object_id=k[2],
            criticality=o["criticality"],
            findings_as_of=d(o.get("findings_as_of", "")),
            usages=raw_usages[k],
            findings=raw_findings[k],
            callers=raw_callers[k],
        )
    return ev


def evaluate_all(objects, usage, findings, deps) -> dict:
    """Exact mirror of zccmc_cl_rule_engine=>evaluate_portfolio."""
    ev = build_evidence(objects, usage, findings, deps)
    return {k[2]: evaluate(v) for k, v in sorted(ev.items(), key=lambda kv: kv[1]["object_id"])}


GOLDEN = {
    "ZCL_INVOICE_UTIL": (
        "MANUAL_REVIEW",
        ["R10", "R60"],
        ["CRITICALITY_UNKNOWN"],
        "MANUAL_REVIEW: safe default because of: CRITICALITY_UNKNOWN. Evidence: criticality=UNKNOWN; usage_facts=1; run_count=41; window_months=12; last_executed=2026-09-30; evidence_as_of=2026-10-13; findings_known=yes; high_findings=0; high_criticality_caller=yes.",
    ),
    "ZCL_PRICING_HELPER": (
        "KEEP_ADAPT",
        ["R60"],
        [],
        "Rule R60 (priority 60): The object is used and has no HIGH-severity findings; keep and adapt. Result KEEP_ADAPT. Evidence: criticality=MEDIUM; usage_facts=1; run_count=15210; window_months=12; last_executed=2026-10-12; evidence_as_of=2026-10-13; findings_known=yes; high_findings=0; high_criticality_caller=yes.",
    ),
    "ZFI_OLD_LEDGER_EXPORT": (
        "MANUAL_REVIEW",
        ["R10"],
        ["NO_USAGE_FACT"],
        "MANUAL_REVIEW: safe default because of: NO_USAGE_FACT. Evidence: criticality=LOW; usage_facts=0; findings_known=yes; high_findings=0; high_criticality_caller=no.",
    ),
    "ZHR_PAYROLL_ADJ": (
        "MANUAL_REVIEW",
        ["R10", "R60"],
        ["CRITICALITY_UNKNOWN"],
        "MANUAL_REVIEW: safe default because of: CRITICALITY_UNKNOWN. Evidence: criticality=UNKNOWN; usage_facts=1; run_count=3; window_months=12; last_executed=2025-12-12; evidence_as_of=2026-10-13; findings_known=yes; high_findings=0; high_criticality_caller=no.",
    ),
    "ZMM_STOCK_ALERT": (
        "MANUAL_REVIEW",
        ["R10"],
        ["WINDOW_TOO_SHORT"],
        "MANUAL_REVIEW: safe default because of: WINDOW_TOO_SHORT. Evidence: criticality=MEDIUM; usage_facts=1; run_count=0; window_months=2; last_executed=none; evidence_as_of=2026-10-13; findings_known=yes; high_findings=0; high_criticality_caller=no.",
    ),
    "ZSD_CUST_CREDIT_CHECK": (
        "MANUAL_REVIEW",
        ["R30"],
        [],
        "Rule R30 (priority 30): The object is used and has HIGH-severity findings; a human must assess the impact. Result MANUAL_REVIEW. Evidence: criticality=HIGH; usage_facts=1; run_count=930; window_months=12; last_executed=2026-10-10; evidence_as_of=2026-10-13; findings_known=yes; high_findings=1; high_criticality_caller=no.",
    ),
    "ZSD_OPEN_ORDERS_RPT": (
        "MANUAL_REVIEW",
        ["R30"],
        [],
        "Rule R30 (priority 30): The object is used and has HIGH-severity findings; a human must assess the impact. Result MANUAL_REVIEW. Evidence: criticality=HIGH; usage_facts=1; run_count=2480; window_months=12; last_executed=2026-09-25; evidence_as_of=2026-10-13; findings_known=yes; high_findings=2; high_criticality_caller=no.",
    ),
}


# ---------------------------------------------------------------- paper tests and unit-test cases
def base_used(crit="MEDIUM", runs=100):
    return {
        "object_id": "OBJ-USED",
        "criticality": crit,
        "findings_as_of": dt.date(2026, 10, 13),
        "findings": [],
        "callers": [],
        "usages": [
            {
                "period_start": dt.date(2025, 10, 13),
                "period_end": dt.date(2026, 10, 13),
                "last_executed": dt.date(2026, 9, 25),
                "run_count": runs,
                "evidence_as_of": dt.date(2026, 10, 13),
            }
        ],
    }


def base_unused(start=dt.date(2025, 10, 13)):
    return {
        "object_id": "OBJ-UNUSED",
        "criticality": "LOW",
        "findings_as_of": dt.date(2026, 10, 13),
        "findings": [],
        "callers": [],
        "usages": [
            {
                "period_start": start,
                "period_end": dt.date(2026, 10, 13),
                "last_executed": None,
                "run_count": 0,
                "evidence_as_of": dt.date(2026, 10, 13),
            }
        ],
    }


def with_(ev, **kw):
    ev = copy.deepcopy(ev)
    for k, v in kw.items():
        if k.startswith("u_"):
            ev["usages"][0][k[2:]] = v
        else:
            ev[k] = v
    return ev


def rules_plus(*extra, drop=(), only=None, inactive=()):
    rules = [dict(r) for r in SEED_RULES if r["id"] not in drop]
    if only:
        rules = [r for r in rules if r["id"] in only]
    for r in rules:
        if r["id"] in inactive:
            r["active"] = False
    return rules + [dict(e) for e in extra]


def unit_cases():
    """(name, evidence, rules, expected strategy, matched, missing) - mirrors zccmc_ut_rule_engine."""
    mr, ka, rc = "MANUAL_REVIEW", "KEEP_ADAPT", "RETIRE_CANDIDATE"
    r61 = {
        "id": "R61",
        "prio": 60,
        "active": True,
        "cond": "USED_WITHOUT_HIGH_FINDING",
        "outcome": "REWRITE_RAP",
        "rationale": "test-only conflicting rule",
    }
    r62 = {
        "id": "R62",
        "prio": 60,
        "active": True,
        "cond": "USED_WITHOUT_HIGH_FINDING",
        "outcome": ka,
        "rationale": "test-only duplicate rule",
    }
    rx = {
        "id": "RX",
        "prio": 5,
        "active": True,
        "cond": "NOT_A_REAL_CONDITION",
        "outcome": ka,
        "rationale": "test-only invalid rule",
    }
    two_usage = base_used()
    two_usage["usages"].append({
        "period_start": dt.date(2024, 1, 1),
        "period_end": dt.date(2024, 12, 31),
        "last_executed": dt.date(2024, 12, 1),
        "run_count": 5,
        "evidence_as_of": dt.date(2026, 10, 13),
    })
    no_usage = base_unused()
    no_usage["usages"] = []
    bridge_ev = build_evidence_from_import(
        object_id=" zcl_pricing_helper ",
        criticality=" medium ",
        findings_as_of=dt.date(2026, 10, 13),
        usages=[{
            "period_start": dt.date(2025, 10, 13),
            "period_end": dt.date(2026, 10, 13),
            "last_executed": dt.date(2026, 10, 12),
            "run_count": 15210,
            "evidence_as_of": dt.date(2026, 10, 13),
        }],
        findings=[" low "],
        callers=[" high "],
    )
    return [
        ("T1", base_unused(), None, rc, ["R20"], []),
        ("T2", base_unused(dt.date(2025, 11, 13)), None, mr, ["R10"], ["WINDOW_TOO_SHORT"]),
        ("T3", with_(base_unused(), callers=["HIGH"]), None, mr, [], ["NO_RULE_MATCH"]),
        ("T4", base_used("HIGH", 2480), None, ka, ["R60"], []),
        ("T5", with_(base_used("HIGH", 2480), findings=["HIGH"]), None, mr, ["R30"], []),
        ("T6", with_(base_used("MEDIUM", 15210), findings=["LOW"]), None, ka, ["R60"], []),
        ("T7", base_used("UNKNOWN"), None, mr, ["R10", "R60"], ["CRITICALITY_UNKNOWN"]),
        ("T8", no_usage, None, mr, ["R10"], ["NO_USAGE_FACT"]),
        ("T9", base_used(), rules_plus(r61), mr, ["R60", "R61"], ["RULE_CONFLICT"]),
        ("T10", with_(base_unused(), u_last_executed=dt.date(2025, 9, 25)), None, mr, ["R10", "R20"], ["ZERO_RUNS_WITH_LAST_EXECUTED"]),
        ("T11", with_(base_used(), u_last_executed=None), None, mr, ["R10", "R60"], ["RUNS_WITHOUT_LAST_EXECUTED"]),
        ("T12", with_(base_used(), u_period_start=dt.date(2026, 10, 13), u_period_end=dt.date(2025, 10, 13)), None, mr, ["R10", "R60"], ["PERIOD_END_BEFORE_START"]),
        ("T13 age 30", with_(base_used(), u_evidence_as_of=dt.date(2026, 9, 14)), None, ka, ["R60"], []),
        ("T13 age 31", with_(base_used(), u_evidence_as_of=dt.date(2026, 9, 13)), None, mr, ["R10", "R60"], ["EVIDENCE_STALE"]),
        ("T14", with_(base_used(), findings_as_of=None), None, mr, ["R10", "R60"], ["FINDINGS_NOT_LOADED"]),
        ("T15", two_usage, None, mr, ["R10"], ["MULTIPLE_USAGE_FACTS"]),
        ("T16 unknown caller, unused", with_(base_unused(), callers=["UNKNOWN"]), None, mr, ["R10", "R20"], ["CALLER_CRITICALITY_UNKNOWN"]),
        ("T16 known callers", with_(base_unused(), callers=["MEDIUM", "LOW"]), None, rc, ["R20"], []),
        ("T16 unknown caller, used", with_(base_used(), callers=["UNKNOWN"]), None, ka, ["R60"], []),
        ("T17", base_used(), rules_plus(r62), ka, ["R60", "R62"], []),
        ("T18", base_used(), rules_plus(only=("R20",)), mr, [], ["NO_RULE_MATCH"]),
        ("T19", base_used("UNKNOWN"), rules_plus(drop=("R10",)), mr, ["R60"], ["CRITICALITY_UNKNOWN"]),
        ("T20", base_used(), rules_plus(rx), mr, ["R60"], ["UNKNOWN_CONDITION_CODE"]),
        ("T21", base_used(), rules_plus(inactive=("R60",)), mr, [], ["NO_RULE_MATCH"]),
        ("T22", with_(base_used(), findings=["MEDIUM", "MEDIUM", "LOW", "INFO"]), None, ka, ["R60"], []),
        ("T31 M1->M2 bridge", bridge_ev, None, ka, ["R60"], []),
    ]


MONTH_CASES = [
    ((2025, 10, 13), (2026, 10, 13), 12),
    ((2025, 10, 13), (2026, 10, 12), 11),
    ((2026, 8, 1), (2026, 10, 13), 2),
    ((2025, 1, 31), (2025, 2, 28), 1),
    ((2024, 2, 29), (2025, 2, 28), 12),
    ((2026, 10, 13), (2026, 10, 13), 0),
    ((2026, 10, 13), (2025, 10, 13), 0),
]


# ---------------------------------------------------------------- portfolio analytics (spec section 10)
ALL_STRATEGIES = ("KEEP_ADAPT", "REWRITE_RAP", "RETIRE_CANDIDATE", "SIDE_BY_SIDE_BTP", "MANUAL_REVIEW")


def normalize_strategy(val: str | None) -> str:
    s = (val or "").strip().upper()
    return s if s in ALL_STRATEGIES else "MANUAL_REVIEW"


def build_items_from_results(objects_meta: list[dict], results: list[dict]) -> list[dict]:
    """Reference model for zccmc_cl_portfolio_analytics=>build_items_from_results."""
    items = []
    for res in results:
        rkey = (res.get("object_id") or "").strip().upper()
        meta = {}
        for m in objects_meta:
            if (m.get("object_id") or "").strip().upper() == rkey or (m.get("object_name") or "").strip().upper() == rkey:
                meta = m
                break
        items.append({
            "object_id": res.get("object_id", ""),
            "source_system": (meta.get("source_system") or "").strip().upper(),
            "object_type": (meta.get("object_type") or "").strip().upper(),
            "object_name": (meta.get("object_name") or res.get("object_id") or "").strip().upper(),
            "package_name": (meta.get("package_name") or meta.get("package") or "").strip().upper(),
            "criticality": (meta.get("criticality") or "UNKNOWN").strip().upper(),
            "strategy": normalize_strategy(res.get("strategy")),
            "ruleset_id": res.get("ruleset_id", ""),
            "ruleset_version": res.get("ruleset_version", ""),
            "run_id": res.get("run_id", ""),
            "run_timestamp": res.get("run_timestamp", ""),
            "missing_evidence": list(res.get("missing", [])),
            "matched_rule_ids": list(res.get("matched", [])),
        })
    return items


def compute_portfolio_summary(items: list[dict], flt: dict | None = None) -> dict:
    """Reference model for zccmc_cl_portfolio_analytics=>compute_summary."""
    flt = flt or {}
    by_key: dict[tuple[str, str, str], dict] = {}
    for raw in items:
        sys_id = (raw.get("source_system") or "").strip().upper()
        otype = (raw.get("object_type") or "").strip().upper()
        oname = (raw.get("object_name") or "").strip().upper()
        if not oname:
            oname = (raw.get("object_id") or "").strip().upper()
        if not sys_id and not otype and not oname:
            continue
        k = (sys_id, otype, oname)
        run_ts = raw.get("run_timestamp") or ""
        run_id = raw.get("run_id") or ""
        prev = by_key.get(k)
        if prev is None or (run_ts, run_id) > (prev.get("run_timestamp") or "", prev.get("run_id") or ""):
            item = dict(raw)
            item["source_system"] = sys_id
            item["object_type"] = otype
            item["object_name"] = oname
            item["package_name"] = (raw.get("package_name") or "").strip().upper()
            crit = (raw.get("criticality") or "").strip().upper()
            item["criticality"] = crit if crit in ("HIGH", "MEDIUM", "LOW") else "UNKNOWN"
            item["strategy"] = normalize_strategy(raw.get("strategy"))
            item["ruleset_version"] = (raw.get("ruleset_version") or "").strip()
            item["missing_evidence"] = sorted({c.strip().upper() for c in raw.get("missing_evidence", []) if c.strip()})
            by_key[k] = item

    by_strategy = {s: 0 for s in ALL_STRATEGIES}
    by_reason: dict[str, int] = {}
    by_sys: dict[str, int] = {}
    by_pkg: dict[str, int] = {}
    by_crit: dict[str, int] = {}
    total = 0
    complete = 0
    with_missing = 0

    for k in sorted(by_key):
        it = by_key[k]
        if flt.get("source_system") and it["source_system"] != flt["source_system"].strip().upper():
            continue
        if flt.get("package_name") and it["package_name"] != flt["package_name"].strip().upper():
            continue
        if flt.get("criticality"):
            fc = flt["criticality"].strip().upper()
            fc = fc if fc in ("HIGH", "MEDIUM", "LOW") else "UNKNOWN"
            if it["criticality"] != fc:
                continue
        if flt.get("strategy") and it["strategy"] != flt["strategy"].strip().upper():
            continue
        if flt.get("ruleset_version") and it["ruleset_version"] != flt["ruleset_version"].strip():
            continue
        if flt.get("only_missing_evidence") and not it["missing_evidence"]:
            continue

        total += 1
        by_strategy[it["strategy"]] += 1
        if it["missing_evidence"]:
            with_missing += 1
            for r in it["missing_evidence"]:
                by_reason[r] = by_reason.get(r, 0) + 1
        else:
            complete += 1
        sys_key = it["source_system"] or "UNSPECIFIED"
        by_sys[sys_key] = by_sys.get(sys_key, 0) + 1
        pkg_key = it["package_name"] or "UNSPECIFIED"
        by_pkg[pkg_key] = by_pkg.get(pkg_key, 0) + 1
        crit_key = it["criticality"] or "UNSPECIFIED"
        by_crit[crit_key] = by_crit.get(crit_key, 0) + 1

    return {
        "total_objects": total,
        "objects_with_complete_evidence": complete,
        "objects_with_missing_evidence": with_missing,
        "by_strategy": by_strategy,
        "by_missing_reason": dict(sorted(by_reason.items())),
        "by_source_system": dict(sorted(by_sys.items())),
        "by_package": dict(sorted(by_pkg.items())),
        "by_criticality": dict(sorted(by_crit.items())),
    }


# ---------------------------------------------------------------- runner
def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--report", help="write a markdown record of this run")
    ap.add_argument("--permutations", type=int, default=200)
    args = ap.parse_args()

    lines: list[str] = []
    failures = 0

    def log(msg=""):
        print(msg)
        lines.append(msg)

    def check(ok: bool, msg: str):
        nonlocal failures
        if not ok:
            failures += 1
            log(f"FAIL  {msg}")

    log(f"Evaluation date {EVAL_DATE}; Ruleset {RULESET_ID}/{RULESET_VERSION}; python {sys.version.split()[0]}; DEMO / SYNTHETIC data")

    # 1. whole-month boundaries
    for a, b, exp in MONTH_CASES:
        got = whole_months(dt.date(*a), dt.date(*b))
        check(got == exp, f"whole_months({a},{b}) = {got}, expected {exp}")
    log(f"whole-month boundary cases: {len(MONTH_CASES)} checked")

    # 2. paper tests / unit cases (including T31 M1->M2 bridge, explanation non-empty and run_id exclusion)
    cases = unit_cases()
    for name, ev, rules, strat, matched, missing in cases:
        got = evaluate(ev, rules)
        check(
            (got["strategy"], got["matched"], got["missing"]) == (strat, matched, missing),
            f"{name}: got {got}, expected {(strat, matched, missing)}",
        )
        check(
            got["ruleset_id"] == RULESET_ID and got["ruleset_version"] == RULESET_VERSION,
            f"{name}: ruleset metadata mismatch {got}",
        )
        check(
            bool(got["explanation"]) and "RUN-0001" not in got["explanation"],
            f"{name}: invalid explanation {got['explanation']}",
        )
    log(f"paper tests and unit-test scenarios: {len(cases)} checked (including M1->M2 bridge, explanations and v1.0.0 trace)")

    # 3. sample fixtures vs golden table (including exact explanation trace)
    objects, usage = read("objects.csv"), read("usage.csv")
    findings, deps = read("findings.csv"), read("dependencies.csv")
    run1 = evaluate_all(objects, usage, findings, deps)
    for name, (strat, matched, missing, exp_text) in GOLDEN.items():
        got = run1.get(name)
        check(
            got is not None
            and (got["strategy"], got["matched"], got["missing"], got["explanation"])
            == (strat, matched, missing, exp_text),
            f"sample {name}: got {got}, expected {(strat, matched, missing, exp_text)}",
        )
    check(set(run1) == set(GOLDEN), "sample object set differs from golden table")
    log(f"sample objects vs golden table: {len(GOLDEN)} objects (outcomes, rules, missing codes & exact explanations)")

    # 4. run twice from a clean re-read (full result tuples)
    run2 = evaluate_all(read("objects.csv"), read("usage.csv"), read("findings.csv"), read("dependencies.csv"))
    check(run1 == run2, "second clean run differs from first")
    log(f"determinism: two clean runs identical (full result tuples) = {run1 == run2}")

    # 5. permuted input rows (all four files, plus rule order) across full result tuples
    rng = random.Random(20261014)
    bad = 0
    for _ in range(args.permutations):
        o, u, f, p = (rng.sample(x, len(x)) for x in (objects, usage, findings, deps))
        got = evaluate_all(o, u, f, p)
        if got != run1:
            bad += 1
    check(bad == 0, f"{bad} of {args.permutations} permutations changed a result")
    log(f"permutation: {args.permutations} random row orders of all four files, differing = {bad}")

    bad_rules = 0
    for name, ev, rules, *_ in cases:
        base = evaluate(ev, rules)
        shuffled = list(SEED_RULES if rules is None else rules)
        for _ in range(20):
            rng.shuffle(shuffled)
            if evaluate(ev, shuffled) != base:
                bad_rules += 1
    check(bad_rules == 0, f"{bad_rules} rule-order permutations changed a result")
    log(f"permutation: rule row order shuffled 20x for {len(cases)} scenarios, differing = {bad_rules}")

    # 6. cross-object explanation isolation & edge/corrected fixtures (Day 8 M2-D08-T01)
    ev_map = build_evidence(objects, usage, findings, deps)
    for k, single_ev in ev_map.items():
        obj_name = k[2]
        standalone_res = evaluate(single_ev)
        check(
            standalone_res == run1[obj_name],
            f"cross-object isolation failed for {obj_name}: batch vs standalone mismatch",
        )
        for other_name in GOLDEN:
            if other_name != obj_name:
                check(
                    other_name not in standalone_res["explanation"],
                    f"unrelated object name {other_name} leaked into {obj_name} explanation",
                )
    corr_rows = read("edge-cases/objects_corrected_batch.csv")
    objects_with_corr = [corr_rows[0] if o["object_name"] == corr_rows[0]["object_name"] else o for o in objects]
    run_corr = evaluate_all(objects_with_corr, usage, findings, deps)
    check(run_corr == run1, "objects_corrected_batch.csv altered rule evaluation output")

    quoted_findings = findings + read("edge-cases/findings_quoted_fields.csv")
    run_quoted = evaluate_all(objects, usage, quoted_findings, deps)
    check(run_quoted == run1, "findings_quoted_fields.csv (LOW finding F900) altered rule evaluation output")
    log("isolation & edge fixtures: cross-object explanation isolation, objects_corrected_batch & findings_quoted_fields verified")

    # 7. scale file loads (1,000 and 10,000 objects, evaluated twice + permuted)
    perf_stats = {}
    for name, n in (("objects_1000.csv", 1000), ("objects_10000.csv", 10000)):
        t0 = time.perf_counter()
        rows = read(f"perf/{name}")
        ev = build_evidence(rows, [], [], [])
        res1 = {k[2]: evaluate(v) for k, v in sorted(ev.items())}
        elapsed = time.perf_counter() - t0
        perf_stats[name] = elapsed
        res2 = {k[2]: evaluate(v) for k, v in sorted(build_evidence(rng.sample(rows, len(rows)), [], [], []).items())}
        check(len(rows) == n and len(res1) == n, f"{name}: {len(rows)} rows, {len(res1)} results")
        check(res1 == res2, f"{name}: permuted second run differed")
        check(
            all(r["strategy"] == "MANUAL_REVIEW" and r["missing"] == ["NO_USAGE_FACT"] for r in res1.values()),
            f"{name}: objects without usage must all be MANUAL_REVIEW / NO_USAGE_FACT",
        )
    log(
        f"perf fixtures: 1,000 ({perf_stats['objects_1000.csv']:.4f}s) and 10,000 ({perf_stats['objects_10000.csv']:.4f}s) "
        "objects evaluated twice (all MANUAL_REVIEW, none silently lost)"
    )

    # 8. portfolio analytics reconciliation (Day 6-11: PA-T01..PA-T13 via build_items_from_results)
    p_items = build_items_from_results(objects, list(run1.values()))
    empty_sum = compute_portfolio_summary([])
    check(empty_sum["total_objects"] == 0 and sum(empty_sum["by_strategy"].values()) == 0, "empty portfolio summary non-zero")
    full_sum = compute_portfolio_summary(p_items)
    check(full_sum["total_objects"] == 7, f"M-01 expected 7, got {full_sum['total_objects']}")
    check(
        full_sum["by_strategy"]
        == {"KEEP_ADAPT": 1, "REWRITE_RAP": 0, "RETIRE_CANDIDATE": 0, "SIDE_BY_SIDE_BTP": 0, "MANUAL_REVIEW": 6},
        f"M-02 mismatch: {full_sum['by_strategy']}",
    )
    check(
        full_sum["objects_with_missing_evidence"] == 4 and full_sum["objects_with_complete_evidence"] == 3,
        f"M-03 counts mismatch: {full_sum}",
    )
    check(
        full_sum["by_missing_reason"] == {"CRITICALITY_UNKNOWN": 2, "NO_USAGE_FACT": 1, "WINDOW_TOO_SHORT": 1},
        f"M-03 breakdown mismatch: {full_sum['by_missing_reason']}",
    )
    check(full_sum["by_source_system"] == {"DEMO_SYS": 7}, f"by_source_system mismatch: {full_sum['by_source_system']}")
    check(
        full_sum["by_criticality"] == {"HIGH": 2, "LOW": 1, "MEDIUM": 2, "UNKNOWN": 2},
        f"by_criticality mismatch: {full_sum['by_criticality']}",
    )
    zsd_sum = compute_portfolio_summary(p_items, {"package_name": "ZSD_PRICING"})
    check(
        zsd_sum["total_objects"] == 1 and zsd_sum["by_strategy"]["KEEP_ADAPT"] == 1 and zsd_sum["objects_with_missing_evidence"] == 0,
        f"ZSD_PRICING filter mismatch: {zsd_sum}",
    )
    high_sum = compute_portfolio_summary(p_items, {"criticality": "HIGH"})
    check(
        high_sum["total_objects"] == 2 and high_sum["by_strategy"]["MANUAL_REVIEW"] == 2 and high_sum["objects_with_missing_evidence"] == 0,
        f"HIGH criticality filter mismatch: {high_sum}",
    )
    v1_sum = compute_portfolio_summary(p_items, {"ruleset_version": "1.0.0"})
    old_sum = compute_portfolio_summary(p_items, {"ruleset_version": "0.1.0-DRAFT"})
    check(v1_sum["total_objects"] == 7 and old_sum["total_objects"] == 0, "ruleset_version filter mismatch")

    dup_sum = compute_portfolio_summary(p_items * 5)
    check(dup_sum == full_sum, "joined duplicate rows inflated portfolio counts")

    fallback_items = [
        {"object_id": "OBJ-1", "source_system": "DEMO_SYS", "object_type": "PROG", "object_name": "", "strategy": "BOGUS"},
        {"object_id": "", "source_system": "", "object_type": "", "object_name": "", "strategy": "KEEP_ADAPT"},
    ]
    fb_sum = compute_portfolio_summary(fallback_items)
    check(
        fb_sum["total_objects"] == 1
        and fb_sum["by_strategy"]["MANUAL_REVIEW"] == 1
        and len(fb_sum["by_strategy"]) == 5,
        f"PA-T11/T12 fallback mismatch: {fb_sum}",
    )

    bad_pa_perm = 0
    for _ in range(args.permutations):
        if compute_portfolio_summary(rng.sample(p_items, len(p_items))) != full_sum:
            bad_pa_perm += 1
    check(bad_pa_perm == 0, f"{bad_pa_perm} portfolio item permutations changed summary")
    log("portfolio analytics: PA-T01..PA-T13 + 200 permutations checked (M-01=7, M-02, M-03=4, groupings, filters, dedup & M1 batch bridge)")

    log("")
    log("RESULT: " + ("ALL CHECKS PASSED" if failures == 0 else f"{failures} CHECK(S) FAILED"))
    return 1 if failures else 0


if __name__ == "__main__":
    raise SystemExit(main())
