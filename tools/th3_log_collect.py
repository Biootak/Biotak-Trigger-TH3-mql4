#!/usr/bin/env python3
"""th3_log_collect - the chart-to-formula feedback loop, as a file.

THE LOOP (the user's): mark ABCD + BASE PIPS on the chart, the indicator logs
one TH3LOG line per verdict (P-TH3-LOG1, TH3Renderer.mqh) into the Experts log,
the user sends screenshots + those lines, and the formula updates off DATA.

This tool reads an Experts log file (or pasted lines on stdin), parses every
TH3LOG line and prints CSV plus the summary the formula tuner needs: the q
distribution (which retrace state the hand marks really are), the lock rate,
and the step-vs-ABCD / step-vs-rung bias (which side the 60/40 blend leans).

A malformed line is absence, never a guess: skipped and counted.

Usage:  python tools/th3_log_collect.py --selftest
        python tools/th3_log_collect.py experts.log
        type experts.log | python tools/th3_log_collect.py
"""

import argparse
import statistics
import sys

FIELDS = ("pat", "chart", "st", "R", "closed", "K", "rung", "owner", "q",
          "pb", "synth", "macro", "lock", "step", "proof", "deep")
NUMS = set(FIELDS) - {"pat", "owner", "q"}
# P-TIME-01: st (server epoch) is OPTIONAL so pre-st lines still parse.


def parse_line(line):
    """One TH3LOG line -> dict, or None (not a verdict line / malformed)."""
    i = line.find("TH3LOG ")
    if i < 0:
        return None
    row = {}
    for tok in line[i + len("TH3LOG "):].split():
        if "=" not in tok:
            return None
        k, v = tok.split("=", 1)
        if k not in FIELDS or k in row:
            return None
        if k in NUMS:
            try:
                v = float(v)
            except ValueError:
                return None
        row[k] = v
    if any(k not in row for k in FIELDS if k != "st"):
        return None
    row.setdefault("st", 0.0)
    return row


def collect(lines):
    rows, bad = [], 0
    for ln in lines:
        r = parse_line(ln)
        if r is None:
            if "TH3LOG" in ln:
                bad += 1
            continue
        rows.append(r)
    return rows, bad


def bias(vals):
    vals = [v for v in vals if v is not None]
    if not vals:
        return None
    return statistics.mean(vals)


def summarize(rows):
    n = len(rows)
    qs = {}
    for r in rows:
        qs[r["q"]] = qs.get(r["q"], 0) + 1
    s = dict(
        n=n,
        q_dist=qs,
        lock_rate=sum(r["lock"] for r in rows) / n if n else None,
        macro_rate=sum(r["macro"] for r in rows) / n if n else None,
        proof_rate=sum(r["proof"] for r in rows) / n if n else None,
        step_vs_closed=bias([r["step"] / r["closed"] - 1.0 for r in rows
                             if r["closed"] > 0]),
        step_vs_rung=bias([r["step"] / r["rung"] - 1.0 for r in rows
                           if r["rung"] > 0]),
        pb_vs_closed=bias([r["pb"] / r["closed"] - 1.0 for r in rows
                           if r["closed"] > 0 and r["pb"] > 0]),
    )
    return s


def selftest():
    ok = True

    def chk(name, cond):
        nonlocal ok
        print(("PASS " if cond else "FAIL ") + name)
        ok = ok and cond

    good1 = ("TH3LOG pat=ABCD_Pattern_1 chart=15 R=330.0 closed=115.2 K=2.50 "
             "rung=98.4 owner=H1 q=3 pb=110.0 synth=105.0 macro=0 lock=1 "
             "step=112.6 proof=1 deep=2.65")
    good2 = ("2026.09.22 15:30:00 Biotak Trigger TH3,XAUUSD,M15: TH3LOG "
             "pat=ABCD_Pattern_2 chart=15 R=60.0 closed=90.0 K=3.00 rung=90.0 "
             "owner=M15 q=2/3 pb=90.0 synth=88.0 macro=0 lock=1 step=89.0 "
             "proof=0 deep=1.20")
    off = ("TH3LOG pat=ABCD_Pattern_3 chart=60 R=0.0 closed=40.0 K=2.50 "
           "rung=35.0 owner=H1 q=off pb=0.0 synth=38.0 macro=0 lock=0 "
           "step=40.0 proof=0 deep=0.40")
    stamped = ("TH3LOG pat=ABCD_Pattern_6 chart=15 st=1758557400 R=90.0 "
               "closed=90.0 K=3.00 rung=90.0 owner=M15 q=1 pb=90.0 synth=90.0 "
               "macro=0 lock=1 step=90.0 proof=1 deep=2.40")
    bad_short = "TH3LOG pat=ABCD_Pattern_4 chart=15 R=10.0"
    bad_num = ("TH3LOG pat=ABCD_Pattern_5 chart=15 R=xx closed=1.0 K=1.0 "
               "rung=1.0 owner=H1 q=1 pb=1.0 synth=1.0 macro=0 lock=0 "
               "step=1.0 proof=0 deep=0.0")
    noise = "TH3: step proof - tip 4320.29 (LOW), step=109.6 pips"
    rows, bad = collect([good1, good2, off, stamped, bad_short, bad_num, noise,
                         "random line"])
    chk("4 verdicts parsed", len(rows) == 4)
    chk("2 malformed counted", bad == 2)
    chk("log prefix tolerated", rows[1]["pat"] == "ABCD_Pattern_2")
    chk("q=off survives", rows[2]["q"] == "off" and rows[2]["R"] == 0.0)
    chk("old lines default st=0", rows[0]["st"] == 0.0)
    chk("server stamp parses", rows[3]["st"] == 1758557400.0)
    s = summarize(rows)
    chk("q distribution", s["q_dist"] == {"3": 1, "2/3": 1, "off": 1, "1": 1})
    chk("lock rate 3/4", abs(s["lock_rate"] - 3.0 / 4.0) < 1e-9)
    chk("proof rate 2/4", abs(s["proof_rate"] - 2.0 / 4.0) < 1e-9)
    want = ((112.6 / 115.2 - 1.0) + (89.0 / 90.0 - 1.0) + (40.0 / 40.0 - 1.0)
            + (90.0 / 90.0 - 1.0)) / 4.0
    chk("step-vs-closed bias", abs(s["step_vs_closed"] - want) < 1e-9)
    print("selftest:", "ALL PASS" if ok else "FAILURES PRESENT")
    return ok


def main(argv):
    ap = argparse.ArgumentParser()
    ap.add_argument("--selftest", action="store_true")
    ap.add_argument("logfile", nargs="?")
    args = ap.parse_args(argv)
    if args.selftest:
        return 0 if selftest() else 1
    if args.logfile:
        with open(args.logfile, encoding="utf-8", errors="replace") as f:
            lines = f.read().splitlines()
    else:
        lines = sys.stdin.read().splitlines()
    rows, bad = collect(lines)
    print(",".join(FIELDS))
    for r in rows:
        print(",".join(str(r[k]) for k in FIELDS))
    s = summarize(rows)
    print(f"\nverdicts: {s['n']} (skipped malformed: {bad})", file=sys.stderr)
    print(f"q distribution: {s['q_dist']}", file=sys.stderr)
    for k in ("lock_rate", "macro_rate", "proof_rate", "step_vs_closed",
              "step_vs_rung", "pb_vs_closed"):
        v = s[k]
        print(f"{k}: {'n/a' if v is None else f'{v:+.3f}'}", file=sys.stderr)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
