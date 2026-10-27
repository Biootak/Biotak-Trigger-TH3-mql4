#!/usr/bin/env python3
"""What the stop would be if its rung were the one whose ability is NEAREST the box.

WHY: the type is a NAME for "the box is as long as this rung's ability". The stop is a
MEASUREMENT of that ability. Today the two are welded: the type picks a hop count (+0..+3)
and the stop lands on that rung — so a box 0.5 pip above `str` is called OTR and its stop
jumps from H1 to H4 (1R x 2.28, TP x 2.27) on half a pip of measurement.

This script keeps the type exactly as the user defined it (OTR = longer than the structure
time's ability) and asks a separate question: which rung's ATR is closest to h? That rung's
EngSL is the stop the box's own size implies. No new reads: the three ATRs in the row are
the candidates, plus the rung the current stop already used (its ATR is stop x 4.2666).

  python tools/bk-stop-nearest.py
  python tools/bk-stop-nearest.py --csv path/to/Dataset.csv

Exit 0 always: this is a measurement, not a gate.
"""
import argparse
import csv
import math
import os

DIV = 4.266666
RATIOS = (7.0 / 3.0, 5.0, 31.0 / 3.0)


def r2(x):
    return math.floor(x + 0.5)


def main():
    here = os.path.dirname(os.path.abspath(__file__))
    ap = argparse.ArgumentParser()
    ap.add_argument("--csv", default=os.path.join(here, "..", "Samples", "BK_Dataset", "Dataset.csv"))
    args = ap.parse_args()

    with open(os.path.abspath(args.csv), newline="", encoding="utf-8-sig") as fh:
        rows = list(csv.DictReader(fh))

    print("STOP BY NEAREST ABILITY  (type unchanged; only the rung the stop reads changes)")
    print("=" * 96)
    print(f"{'sample':9s} {'type':4s} {'h':>7s} {'trig':>7s} {'pat':>7s} {'str':>7s} {'stop v1':>8s} {'rung v1':>8s} {'stop v2':>8s} {'rung v2':>8s} {'d':>7s}")
    for r in rows:
        h = float(r["Box_Pips"])
        trig, pat, str_ = float(r["ATR_Trig"]), float(r["ATR_Pat"]), float(r["ATR_Str"])
        stop1 = float(r["Stop_Pips"])
        atr_stop = stop1 * DIV                     # the rung v1 already used, as an ATR
        cand = [("node", trig), ("+1", pat), ("+2", str_)]
        if atr_stop > str_ * 1.001:                # the stop sits above the structure rung
            cand.append(("+3", atr_stop))
        name, atr = min(cand, key=lambda c: abs(c[1] - h))
        stop2 = atr / DIV
        print(f"{r['Sample_ID']:9s} {r['Type']:4s} {h:7.1f} {trig:7.1f} {pat:7.1f} {str_:7.1f} "
              f"{stop1:8.1f} {'v1':>8s} {stop2:8.1f} {name:>8s} {stop2 - stop1:+7.1f}")
        if abs(stop2 - stop1) > 0.05:
            tp1 = [r2(stop2 * x) for x in RATIOS]
            old = [r["TP1_Pips"], r["TP2_Pips"], r["TP3_Pips"]]
            print(f"{'':9s} {'':4s} TP: {'/'.join(old)}  ->  {'/'.join(str(int(x)) for x in tp1)}")
    print("-" * 96)
    print("  d = stop v2 - stop v1, in pips. Only a row whose nearest rung differs from the")
    print("  type's rung moves; the label itself is untouched.")


if __name__ == "__main__":
    main()
