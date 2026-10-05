#!/usr/bin/env python3
# th3_log_collect.py - the feedback loop's reader (P-TH3-LOG1).
# Reads the terminal's Experts log, collects every TH3LOG verdict line plus
# its skeleton line, and writes two things: a tidy human block per pattern
# on stdout and a machine CSV (--out) for data-driven formula tuning.
# Reader only: never touches the chart, never fails a build (exit 0 unless
# the log itself is unreadable). Usage:
#   python tools/th3_log_collect.py <experts-log> [--out verdicts.csv]
"""Reader for TH3LOG verdict lines (see Biotak/TH3/TH3Renderer_B.mqh:313)."""
import csv
import re
import sys

LOG_RE = re.compile(
    r"TH3LOG pat=(\S+) chart=(\d+) st=(\d+) R=(\S+) closed=(\S+) "
    r"K=(\S+) rung=(\S+) owner=(\S+) q=(\S+) pb=(\S+) synth=(\S+) "
    r"macro=(\d+) lock=(\d+) step=(\S+) proof=(\d+) deep=(\S+)"
)
CTX_RE = re.compile(r"TH3 (\S+): TH3LOG")
TIME_RE = re.compile(r"^\S*\s*(\d{2}:\d{2}:\d{2})")
SKEL_RE = re.compile(
    r"pattern created: (\S+) \| skeleton key=(\S+) dir=(\S+) mom=(\S+) "
    r"pivot=(\S+) depth=(\S+) delay=(\S+) engulf=(\S+) speed=(\S+) "
    r"angle=(\S+) pivotATR=(\S+) coverBody=(\S+) step=(\S+) pips"
)
SKEL_MISS_RE = re.compile(r"pattern created: (\S+) \| skeleton unavailable")


def parse_log(path):
    """Parse one Experts log. Returns (rows, skeletons)."""
    rows = []
    skels = {}
    with open(path, encoding="utf-8", errors="replace") as fh:
        for line in fh:
            if "TH3LOG pat=" not in line and "pattern created:" not in line:
                continue
            m = LOG_RE.search(line)
            if m is not None:
                tm = TIME_RE.search(line)
                cx = CTX_RE.search(line)
                rows.append({
                    "time": tm.group(1) if tm else "?",
                    "symbol_tf": cx.group(1) if cx else "?",
                    "pat": m.group(1), "chart": m.group(2),
                    "st": m.group(3), "R": m.group(4),
                    "closed": m.group(5), "K": m.group(6),
                    "rung": m.group(7), "owner": m.group(8),
                    "q": m.group(9), "pb": m.group(10),
                    "synth": m.group(11), "macro": m.group(12),
                    "lock": m.group(13), "step": m.group(14),
                    "proof": m.group(15), "deep": m.group(16),
                })
                continue
            s = SKEL_RE.search(line)
            if s is not None:
                skels[s.group(1)] = {
                    "key": s.group(2), "dir": s.group(3),
                    "mom": s.group(4), "pivot": s.group(5),
                    "depth": s.group(6), "delay": s.group(7),
                    "step": s.group(13),
                }
                continue
            u = SKEL_MISS_RE.search(line)
            if u is not None:
                skels[u.group(1)] = {"key": "?", "missing": True}
    return rows, skels


def tidy_block(r, sk):
    """One tidy block per verdict row."""
    mother = "on" if r["macro"] == "1" else "off"
    base = "off" if r["pb"] == "0.0" else "on"
    locked = "yes" if r["lock"] == "1" else "no"
    proved = "yes" if r["proof"] == "1" else "no"
    if sk is None:
        skel = "skeleton: not seen yet"
    elif sk.get("missing"):
        skel = "skeleton: unavailable"
    else:
        skel = ("skeleton: key={key} dir={dir} mom={mom} "
                "pivot={pivot} depth={depth} delay={delay} "
                "step={step} pips".format(**sk))
    return (
        "== {pat} [{symbol_tf}] {time} ==\n"
        "   inputs : closed={closed} K={K} rung={rung} owner={owner} q={q}\n"
        "   verdict: step={step} synth={synth} macro={mother} "
        "base={base} lock={locked} proof={proved} deep={deep}\n"
        "   {skel}".format(
            pat=r["pat"], symbol_tf=r["symbol_tf"], time=r["time"],
            closed=r["closed"], K=r["K"], rung=r["rung"],
            owner=r["owner"], q=r["q"], step=r["step"],
            synth=r["synth"], mother=mother, base=base,
            locked=locked, proved=proved, deep=r["deep"], skel=skel)
    )


COLS = ["time", "symbol_tf", "pat", "chart", "st", "R", "closed",
        "K", "rung", "owner", "q", "pb", "synth", "macro", "lock",
        "step", "proof", "deep", "skel_key", "skel_mom", "skel_step"]


def main(argv):
    if len(argv) < 2 or argv[1] in ("-h", "--help"):
        print("usage: python tools/th3_log_collect.py "
              "<experts-log> [--out verdicts.csv]")
        return 0
    path = argv[1]
    out = None
    if "--out" in argv:
        out = argv[argv.index("--out") + 1]
    try:
        rows, skels = parse_log(path)
    except OSError as exc:
        print("unreadable log: {}".format(exc))
        return 1
    if not rows:
        print("no TH3LOG lines in {}".format(path))
        return 0
    for r in rows:
        print(tidy_block(r, skels.get(r["pat"])))
    n = len(rows)
    locks = sum(1 for r in rows if r["lock"] == "1")
    proofs = sum(1 for r in rows if r["proof"] == "1")
    macros = sum(1 for r in rows if r["macro"] == "1")
    print("summary: rows={} lock={} proof={} macro={}".format(
        n, locks, proofs, macros))
    if out is not None:
        with open(out, "w", newline="", encoding="utf-8") as fh:
            wr = csv.writer(fh)
            wr.writerow(COLS)
            for r in rows:
                sk = skels.get(r["pat"], {})
                wr.writerow([r["time"], r["symbol_tf"], r["pat"],
                             r["chart"], r["st"], r["R"], r["closed"],
                             r["K"], r["rung"], r["owner"], r["q"],
                             r["pb"], r["synth"], r["macro"],
                             r["lock"], r["step"], r["proof"],
                             r["deep"], sk.get("key", "?"),
                             sk.get("mom", "?"), sk.get("step", "?")])
        print("csv: {}".format(out))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
