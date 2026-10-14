#!/usr/bin/env python3
"""Reference model and regression runner for the Member 2 rules (docs/rules-spec.md).

This is a TEST ORACLE, not the product. The product is
src/zccmc_core/zccmc_cl_rule_engine.clas.abap, which this workspace cannot compile or run.
The oracle re-implements the same written rules so that:
  * the golden table in docs/m2-golden-results.md is computed, not guessed;
  * determinism (run twice) and row-permutation checks can actually be executed;
  * the expected values hard-coded in zccmc_ut_rule_engine can be cross-checked.
It proves nothing about the ABAP code. DEMO / SYNTHETIC data only.

Usage (repository root):
    python tools/m2_rules_oracle.py                    # run everything, exit 1 on failure
    python tools/m2_rules_oracle.py --report out.md    # also write a markdown record
"""
from __future__ import annotations

import argparse
import copy
import csv
import datetime as dt
import random
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SAMPLE = ROOT / "data" / "sample-synthetic"
EVAL_DATE = dt.date(2026, 10, 14)

# ---------------------------------------------------------------- rule set (spec section 5)
PARAMS = {"min_window_months": 12, "max_evidence_age_days": 30, "high_finding_min_count": 1}
SEED_RULES = [
    {"id": "R10", "prio": 10, "active": True, "cond": "EVIDENCE_PROBLEM", "outcome": "MANUAL_REVIEW"},
    {"id": "R20", "prio": 20, "active": True, "cond": "NO_USE_COMPLETE_WINDOW", "outcome": "RETIRE_CANDIDATE"},
    {"id": "R30", "prio": 30, "active": True, "cond": "USED_WITH_HIGH_FINDING", "outcome": "MANUAL_REVIEW"},
    {"id": "R60", "prio": 60, "active": True, "cond": "USED_WITHOUT_HIGH_FINDING", "outcome": "KEEP_ADAPT"},
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


def evaluate(evidence: dict, rules=None, params=None, eval_date: dt.date = EVAL_DATE) -> dict:
    """evidence: criticality, findings_as_of, usages[list], findings[list of severity], callers[list]."""
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

    if n_usage == 0:
        missing.append("NO_USAGE_FACT")
    elif n_usage > 1:
        missing.append("MULTIPLE_USAGE_FACTS")
    else:
        u = usages[0]
        run_count = u["run_count"]
        if u["period_end"] < u["period_start"]:
            missing.append("PERIOD_END_BEFORE_START")
        else:
            window_valid = True
            window_months = whole_months(u["period_start"], u["period_end"])
            if window_months < params["min_window_months"]:
                missing.append("WINDOW_TOO_SHORT")
        if not u["evidence_as_of"] or (eval_date - u["evidence_as_of"]).days > params["max_evidence_age_days"]:
            missing.append("EVIDENCE_STALE")
        if run_count == 0 and u["last_executed"]:
            missing.append("ZERO_RUNS_WITH_LAST_EXECUTED")
        if run_count > 0 and not u["last_executed"]:
            missing.append("RUNS_WITHOUT_LAST_EXECUTED")

    if crit == "UNKNOWN":
        missing.append("CRITICALITY_UNKNOWN")
    if not evidence.get("findings_as_of"):
        missing.append("FINDINGS_NOT_LOADED")
    high = sum(1 for s in evidence.get("findings", []) if s.strip().upper() == "HIGH")

    caller_crits = [c.strip().upper() for c in evidence.get("callers", [])]
    has_high_caller = "HIGH" in caller_crits
    unknown_callers = sum(1 for c in caller_crits if c not in ("HIGH", "MEDIUM", "LOW"))
    if n_usage == 1 and run_count == 0 and not has_high_caller and unknown_callers > 0:
        missing.append("CALLER_CRITICALITY_UNKNOWN")

    def matches(cond: str):
        if cond == "EVIDENCE_PROBLEM":
            return bool(missing)
        if cond == "NO_USE_COMPLETE_WINDOW":
            return (n_usage == 1 and run_count == 0 and window_valid
                    and window_months >= params["min_window_months"] and not has_high_caller)
        if cond == "USED_WITH_HIGH_FINDING":
            return n_usage == 1 and run_count > 0 and high >= params["high_finding_min_count"]
        if cond == "USED_WITHOUT_HIGH_FINDING":
            return n_usage == 1 and run_count > 0 and high < params["high_finding_min_count"]
        return None  # unknown condition code

    matched, bad_code = [], False
    for r in rules:
        if not r["active"]:
            continue
        m = matches(r["cond"])
        if m is None:
            bad_code = True
        elif m:
            matched.append(r)
    matched.sort(key=lambda r: (r["prio"], r["id"]))
    if bad_code:
        missing.append("UNKNOWN_CONDITION_CODE")

    reason = ""
    if not matched:
        strategy, reason = "MANUAL_REVIEW", "NO_RULE_MATCH"
    else:
        best = matched[0]["prio"]
        outcomes = {r["outcome"] for r in matched if r["prio"] == best}
        if len(outcomes) > 1:
            strategy, reason = "MANUAL_REVIEW", "RULE_CONFLICT"
        else:
            strategy = matched[0]["outcome"]
    if missing:                      # hard safety invariant
        strategy = "MANUAL_REVIEW"
    elif reason:
        missing.append(reason)
    return {"strategy": strategy, "matched": [r["id"] for r in matched], "missing": missing}


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
    ev = {}
    for k, o in by_key.items():
        ev[k] = {"criticality": o["criticality"], "findings_as_of": d(o.get("findings_as_of", "")),
                 "usages": [], "findings": [], "callers": []}
    for u in usage:
        ev[key(u)]["usages"].append({
            "period_start": d(u["period_start"]), "period_end": d(u["period_end"]),
            "last_executed": d(u["last_executed"]), "run_count": int(u["run_count"]),
            "evidence_as_of": d(u["evidence_as_of"])})
    for f in findings:
        ev[key(f)]["findings"].append(f["severity"])
    for dep in deps:
        target = key(dep, "to_type", "to_name")
        caller = key(dep, "from_type", "from_name")
        ev[target]["callers"].append(by_key[caller]["criticality"])
    return ev


def evaluate_all(objects, usage, findings, deps) -> dict:
    ev = build_evidence(objects, usage, findings, deps)
    return {k[2]: evaluate(v) for k, v in sorted(ev.items())}


GOLDEN = {  # expected sample results (derived from the written rules, checked by this tool)
    "ZSD_OPEN_ORDERS_RPT": ("MANUAL_REVIEW", ["R30"], []),
    "ZCL_PRICING_HELPER": ("KEEP_ADAPT", ["R60"], []),
    "ZFI_OLD_LEDGER_EXPORT": ("MANUAL_REVIEW", ["R10"], ["NO_USAGE_FACT"]),
    "ZMM_STOCK_ALERT": ("MANUAL_REVIEW", ["R10"], ["WINDOW_TOO_SHORT"]),
    "ZSD_CUST_CREDIT_CHECK": ("MANUAL_REVIEW", ["R30"], []),
    "ZCL_INVOICE_UTIL": ("MANUAL_REVIEW", ["R10", "R60"], ["CRITICALITY_UNKNOWN"]),
    "ZHR_PAYROLL_ADJ": ("MANUAL_REVIEW", ["R10", "R60"], ["CRITICALITY_UNKNOWN"]),
}


# ---------------------------------------------------------------- paper tests and unit-test cases
def base_used(crit="MEDIUM", runs=100):
    return {"criticality": crit, "findings_as_of": dt.date(2026, 10, 13), "findings": [], "callers": [],
            "usages": [{"period_start": dt.date(2025, 10, 13), "period_end": dt.date(2026, 10, 13),
                        "last_executed": dt.date(2026, 9, 25), "run_count": runs,
                        "evidence_as_of": dt.date(2026, 10, 13)}]}


def base_unused(start=dt.date(2025, 10, 13)):
    return {"criticality": "LOW", "findings_as_of": dt.date(2026, 10, 13), "findings": [], "callers": [],
            "usages": [{"period_start": start, "period_end": dt.date(2026, 10, 13), "last_executed": None,
                        "run_count": 0, "evidence_as_of": dt.date(2026, 10, 13)}]}


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
    r61 = {"id": "R61", "prio": 60, "active": True, "cond": "USED_WITHOUT_HIGH_FINDING", "outcome": "REWRITE_RAP"}
    r62 = {"id": "R62", "prio": 60, "active": True, "cond": "USED_WITHOUT_HIGH_FINDING", "outcome": ka}
    rx = {"id": "RX", "prio": 5, "active": True, "cond": "NOT_A_REAL_CONDITION", "outcome": ka}
    two_usage = base_used()
    two_usage["usages"].append({"period_start": dt.date(2024, 1, 1), "period_end": dt.date(2024, 12, 31),
                                "last_executed": dt.date(2024, 12, 1), "run_count": 5,
                                "evidence_as_of": dt.date(2026, 10, 13)})
    no_usage = base_unused(); no_usage["usages"] = []
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
        ("T10", with_(base_unused(), u_last_executed=dt.date(2025, 9, 25)), None, mr, ["R10", "R20"],
         ["ZERO_RUNS_WITH_LAST_EXECUTED"]),
        ("T11", with_(base_used(), u_last_executed=None), None, mr, ["R10", "R60"], ["RUNS_WITHOUT_LAST_EXECUTED"]),
        ("T12", with_(base_used(), u_period_start=dt.date(2026, 10, 13), u_period_end=dt.date(2025, 10, 13)),
         None, mr, ["R10", "R60"], ["PERIOD_END_BEFORE_START"]),
        ("T13 age 30", with_(base_used(), u_evidence_as_of=dt.date(2026, 9, 14)), None, ka, ["R60"], []),
        ("T13 age 31", with_(base_used(), u_evidence_as_of=dt.date(2026, 9, 13)), None, mr, ["R10", "R60"],
         ["EVIDENCE_STALE"]),
        ("T14", with_(base_used(), findings_as_of=None), None, mr, ["R10", "R60"], ["FINDINGS_NOT_LOADED"]),
        ("T15", two_usage, None, mr, ["R10"], ["MULTIPLE_USAGE_FACTS"]),
        ("T16 unknown caller, unused", with_(base_unused(), callers=["UNKNOWN"]), None, mr, ["R10", "R20"],
         ["CALLER_CRITICALITY_UNKNOWN"]),
        ("T16 known callers", with_(base_unused(), callers=["MEDIUM", "LOW"]), None, rc, ["R20"], []),
        ("T16 unknown caller, used", with_(base_used(), callers=["UNKNOWN"]), None, ka, ["R60"], []),
        ("T17", base_used(), rules_plus(r62), ka, ["R60", "R62"], []),
        ("T18", base_used(), rules_plus(only=("R20",)), mr, [], ["NO_RULE_MATCH"]),
        ("T19", base_used("UNKNOWN"), rules_plus(drop=("R10",)), mr, ["R60"], ["CRITICALITY_UNKNOWN"]),
        ("T20", base_used(), rules_plus(rx), mr, ["R60"], ["UNKNOWN_CONDITION_CODE"]),
        ("T21", base_used(), rules_plus(inactive=("R60",)), mr, [], ["NO_RULE_MATCH"]),
        ("T22", with_(base_used(), findings=["MEDIUM", "MEDIUM", "LOW", "INFO"]), None, ka, ["R60"], []),
    ]


MONTH_CASES = [
    ((2025, 10, 13), (2026, 10, 13), 12), ((2025, 10, 13), (2026, 10, 12), 11),
    ((2026, 8, 1), (2026, 10, 13), 2), ((2025, 1, 31), (2025, 2, 28), 1),
    ((2024, 2, 29), (2025, 2, 28), 12), ((2026, 10, 13), (2026, 10, 13), 0),
    ((2026, 10, 13), (2025, 10, 13), 0),
]




# ---------------------------------------------------------------- portfolio analytics (spec section 12 / Day 6)
ALL_STRATEGIES = ("KEEP_ADAPT", "REWRITE_RAP", "RETIRE_CANDIDATE", "SIDE_BY_SIDE_BTP", "MANUAL_REVIEW")


def compute_portfolio_summary(items: list[dict], flt: dict | None = None) -> dict:
    """Reference model for zccmc_cl_portfolio_analytics=>compute_summary."""
    flt = flt or {}
    # Deduplicate by (source_system, object_type, object_name) keeping latest run_id
    by_key: dict[tuple[str, str, str], dict] = {}
    for raw in items:
        sys_id = (raw.get("source_system") or "").strip().upper()
        otype = (raw.get("object_type") or "").strip().upper()
        oname = (raw.get("object_name") or raw.get("object_id") or "").strip().upper()
        k = (sys_id, otype, oname)
        run_id = raw.get("run_id") or ""
        if k not in by_key or run_id > (by_key[k].get("run_id") or ""):
            item = dict(raw)
            item["source_system"] = sys_id
            item["object_type"] = otype
            item["object_name"] = oname
            item["package_name"] = (raw.get("package_name") or "").strip().upper()
            crit = (raw.get("criticality") or "").strip().upper()
            item["criticality"] = crit if crit in ("HIGH", "MEDIUM", "LOW") else "UNKNOWN"
            item["strategy"] = (raw.get("strategy") or "MANUAL_REVIEW").strip().upper()
            item["missing_evidence"] = sorted({c.strip().upper() for c in raw.get("missing_evidence", []) if c.strip()})
            by_key[k] = item

    by_strategy = {s: 0 for s in ALL_STRATEGIES}
    by_reason: dict[str, int] = {}
    by_pkg: dict[str, int] = {}
    total = 0
    complete = 0
    with_missing = 0

    for k in sorted(by_key):
        it = by_key[k]
        if flt.get("source_system") and it["source_system"] != flt["source_system"].strip().upper():
            continue
        if flt.get("package_name") and it["package_name"] != flt["package_name"].strip().upper():
            continue
        if flt.get("criticality") and it["criticality"] != flt["criticality"].strip().upper():
            continue
        if flt.get("strategy") and it["strategy"] != flt["strategy"].strip().upper():
            continue
        if flt.get("only_missing_evidence") and not it["missing_evidence"]:
            continue

        total += 1
        by_strategy[it["strategy"]] = by_strategy.get(it["strategy"], 0) + 1
        if it["missing_evidence"]:
            with_missing += 1
            for r in it["missing_evidence"]:
                by_reason[r] = by_reason.get(r, 0) + 1
        else:
            complete += 1
        pkg = it["package_name"] or "UNSPECIFIED"
        by_pkg[pkg] = by_pkg.get(pkg, 0) + 1

    return {
        "total_objects": total,
        "objects_with_complete_evidence": complete,
        "objects_with_missing_evidence": with_missing,
        "by_strategy": by_strategy,
        "by_missing_reason": dict(sorted(by_reason.items())),
        "by_package": dict(sorted(by_pkg.items())),
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

    log(f"Evaluation date {EVAL_DATE}; python {sys.version.split()[0]}; DEMO / SYNTHETIC data")

    # 1. whole-month boundaries
    for a, b, exp in MONTH_CASES:
        got = whole_months(dt.date(*a), dt.date(*b))
        check(got == exp, f"whole_months({a},{b}) = {got}, expected {exp}")
    log(f"whole-month boundary cases: {len(MONTH_CASES)} checked")

    # 2. paper tests / unit cases
    cases = unit_cases()
    for name, ev, rules, strat, matched, missing in cases:
        got = evaluate(ev, rules)
        check((got["strategy"], got["matched"], got["missing"]) == (strat, matched, missing),
              f"{name}: got {got}, expected {(strat, matched, missing)}")
    log(f"paper tests and unit-test scenarios: {len(cases)} checked")

    # 3. sample fixtures vs golden table
    objects, usage = read("objects.csv"), read("usage.csv")
    findings, deps = read("findings.csv"), read("dependencies.csv")
    run1 = evaluate_all(objects, usage, findings, deps)
    for name, (strat, matched, missing) in GOLDEN.items():
        got = run1.get(name)
        check(got is not None and (got["strategy"], got["matched"], got["missing"]) == (strat, matched, missing),
              f"sample {name}: got {got}, expected {(strat, matched, missing)}")
    check(set(run1) == set(GOLDEN), "sample object set differs from golden table")
    log(f"sample objects vs golden table: {len(GOLDEN)} objects")

    # 4. run twice from a clean re-read
    run2 = evaluate_all(read("objects.csv"), read("usage.csv"), read("findings.csv"), read("dependencies.csv"))
    check(run1 == run2, "second clean run differs from first")
    log(f"determinism: two clean runs identical = {run1 == run2}")

    # 5. permuted input rows (all four files, plus rule order)
    rng = random.Random(20261014)
    bad = 0
    for i in range(args.permutations):
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

    # 6. scale file loads (read-only structure check; objects only, no usage/findings)
    for name, n in (("objects_1000.csv", 1000), ("objects_10000.csv", 10000)):
        rows = read(f"perf/{name}")
        ev = build_evidence(rows, [], [], [])
        res = [evaluate(v) for v in ev.values()]
        check(len(rows) == n and len(res) == n, f"{name}: {len(rows)} rows, {len(res)} results")
        check(all(r["strategy"] == "MANUAL_REVIEW" and "NO_USAGE_FACT" in r["missing"] for r in res),
              f"{name}: objects without usage must all be MANUAL_REVIEW / NO_USAGE_FACT")
    log("perf fixtures: 1,000 and 10,000 objects evaluated (no usage loaded: all MANUAL_REVIEW, none silently lost)")

    # 7. portfolio analytics reconciliation (Day 6 M2-D06-T01)
    p_items = [
        {
            "source_system": o["source_system"],
            "object_type": o["object_type"],
            "object_name": o["object_name"],
            "package_name": o["package"],
            "criticality": o["criticality"],
            "strategy": run1[o["object_name"].strip().upper()]["strategy"],
            "missing_evidence": run1[o["object_name"].strip().upper()]["missing"],
            "run_id": "RUN-0001",
        }
        for o in objects
    ]
    empty_sum = compute_portfolio_summary([])
    check(empty_sum["total_objects"] == 0 and sum(empty_sum["by_strategy"].values()) == 0, "empty portfolio summary non-zero")
    full_sum = compute_portfolio_summary(p_items)
    check(full_sum["total_objects"] == 7, f"M-01 expected 7, got {full_sum['total_objects']}")
    check(full_sum["by_strategy"] == {"KEEP_ADAPT": 1, "REWRITE_RAP": 0, "RETIRE_CANDIDATE": 0, "SIDE_BY_SIDE_BTP": 0, "MANUAL_REVIEW": 6},
          f"M-02 mismatch: {full_sum['by_strategy']}")
    check(full_sum["objects_with_missing_evidence"] == 4 and full_sum["objects_with_complete_evidence"] == 3,
          f"M-03 counts mismatch: {full_sum}")
    check(full_sum["by_missing_reason"] == {"CRITICALITY_UNKNOWN": 2, "NO_USAGE_FACT": 1, "WINDOW_TOO_SHORT": 1},
          f"M-03 breakdown mismatch: {full_sum['by_missing_reason']}")
    zsd_sum = compute_portfolio_summary(p_items, {"package_name": "ZSD_PRICING"})
    check(zsd_sum["total_objects"] == 1 and zsd_sum["by_strategy"]["KEEP_ADAPT"] == 1 and zsd_sum["objects_with_missing_evidence"] == 0,
          f"ZSD_PRICING filter mismatch: {zsd_sum}")
    high_sum = compute_portfolio_summary(p_items, {"criticality": "HIGH"})
    check(high_sum["total_objects"] == 2 and high_sum["by_strategy"]["MANUAL_REVIEW"] == 2 and high_sum["objects_with_missing_evidence"] == 0,
          f"HIGH criticality filter mismatch: {high_sum}")
    dup_sum = compute_portfolio_summary(p_items * 5)
    check(dup_sum == full_sum, "joined duplicate rows inflated portfolio counts")
    log("portfolio analytics: M-01=7, M-02 (MANUAL_REVIEW=6, KEEP_ADAPT=1), M-03=4, filters, empty & join-dedup checked")

    log("")
    log("RESULT: " + ("ALL CHECKS PASSED" if failures == 0 else f"{failures} CHECK(S) FAILED"))

    if args.report:
        table = ["", "| Object | RecommendedStrategy | MatchedRuleIDs | MissingEvidence |", "|---|---|---|---|"]
        for name, r in run1.items():
            table.append(f"| {name} | {r['strategy']} | {', '.join(r['matched']) or '-'} | {', '.join(r['missing']) or '-'} |")
        Path(args.report).write_text("\n".join(["```text", *lines, "```", *table]) + "\n", encoding="utf-8")
    return 1 if failures else 0


if __name__ == "__main__":
    raise SystemExit(main())
