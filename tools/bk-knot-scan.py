#!/usr/bin/env python3
"""
bk-knot-scan.py — the knot's own time, measured instead of guessed.

THE USER'S DEFINITION (2026-10-27, verbatim):
    «هر کدوم سه تا کندل درجا زدن داشته باشه اون تایم تایم گره هستش ... حتی اگر در
     تایم های متاتریدر نباشه ... قانون سه کندل درجا زدن که نتونه بالا و پایین هم
     کلوز بزنه»

Three candles STAND STILL when the candle cannot make a high, cannot make a low
and cannot close outside the box — i.e. high <= top, low >= bot, close inside,
for three candles in a row. The knot's time is the HIGHEST timeframe on which
three of its own candles still do that: the biggest grid on which the stall is
still visible.

WHY THIS TOOL EXISTS
    The indicator walks a FIXED ladder — M1, M5, M15, H1, H4, D1, W1, MN1
    (BaseKnotNextTFMin) — and it reads BODIES only (BaseKnotRungHoldCount:
    `o >= bot && o <= top && c >= bot && c <= top`). The user's rule is wider on
    both counts: every timeframe, and the whole candle. This tool sweeps every
    timeframe from M1 up and reports where the rule actually lands, so the gap
    between the rule and the ladder is a number on the table instead of an
    opinion.

HOW IT MEASURES
    The box' own prices are not in the journal and not in the saved charts, so
    the tool works from what IS on disk: the box' HEIGHT (Dataset.csv Box_Pips)
    and the box' RIGHT EDGE (Story_Anchor). For a timeframe T it takes the three
    bars of a T-grid whose last bar closes exactly on the anchor — the knot's
    own grid, aligned to the box rather than to the epoch — and measures their
    combined span. Three candles fit inside a box of that height if and only if
    their span is <= the height, which is the whole of the rule for a box that
    sits over them.

    The fill ratio is the check: if the rule is the right rule, the highest T
    that fits should fill the box almost exactly (a box drawn around the three
    candles is ~100 % of their span). Anything far from 100 % means the box and
    the candles are not the same object.

USAGE
    python tools/bk-knot-scan.py
    python tools/bk-knot-scan.py --csv Samples/BK_Dataset/Dataset.csv --hst <XAUUSD1.hst>
    python tools/bk-knot-scan.py --anchor "2026.10.23 16:55" --box 129.0
"""
import argparse
import datetime
import os
import struct
import sys

HDR, REC = 148, 60          # MT4 .hst version 401: 148-byte header, 60-byte records
PIP = 0.10                  # XAUUSD digits=2, perPip 10.00 -> one pip is 0.10

DEFAULT_HST = (r"C:/Users/Bioootak/AppData/Roaming/MetaQuotes/Terminal/"
               r"A1660DA4CB596E740BE3B3233E577E1B/history/AMarkets-Demo/XAUUSD1.hst")
DEFAULT_CSV = "Samples/BK_Dataset/Dataset.csv"

# the ladder the indicator can name today (BaseKnotNextTFMin), for the comparison column
LADDER = [1, 5, 15, 60, 240, 1440, 10080, 43200]
# every timeframe the rule is allowed to land on
SWEEP = list(range(1, 31)) + [45, 60, 90, 120, 180, 240, 360, 480, 720, 1440]


def load_hst(path):
    raw = open(path, "rb").read()
    n = (len(raw) - HDR) // REC
    out = []
    for i in range(n):
        b = HDR + i * REC
        t, = struct.unpack_from("<i", raw, b)
        o, h, l, c = struct.unpack_from("<4d", raw, b + 8)
        out.append((t, o, h, l, c))
    return out


def stamp(t):
    return datetime.datetime.fromtimestamp(t, datetime.timezone.utc).strftime("%Y.%m.%d %H:%M")


def to_epoch(s):
    return int(datetime.datetime.strptime(s, "%Y.%m.%d %H:%M")
               .replace(tzinfo=datetime.timezone.utc).timestamp())


def three_bar_span(m1, anchor, tfmin):
    """Span, in pips, of the three bars of a tfmin grid whose last bar closes at `anchor`."""
    step = tfmin * 60
    hi, lo = -1e18, 1e18
    for k in range(3):
        a = anchor - (3 - k) * step
        b = a + step
        seg = [r for r in m1 if a <= r[0] < b]
        if not seg:
            return None
        hi = max(hi, max(r[2] for r in seg))
        lo = min(lo, min(r[3] for r in seg))
    return (hi - lo) / PIP


def scan(m1, anchor, box, sweep=None):
    """Highest TF whose three candles still fit the box, plus the first TF that breaks it."""
    sweep = sweep or SWEEP
    best, first_bad = None, None
    for tf in sweep:
        s = three_bar_span(m1, anchor, tf)
        if s is None:
            break
        if s <= box:
            best = (tf, s)
        else:
            first_bad = (tf, s)
            break
    return best, first_bad


def read_rows(path):
    rows = []
    with open(path, encoding="utf-8-sig") as f:
        head = f.readline().strip().split(",")
        for line in f:
            cells = line.rstrip("\n").split(",")
            if len(cells) < len(head):
                continue
            r = dict(zip(head, cells))
            try:
                rows.append((r["Sample_ID"], r["Story_Anchor"], float(r["Box_Pips"]),
                             r.get("Node_TF", "")))
            except (KeyError, ValueError):
                continue
    return rows


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--csv", default=DEFAULT_CSV)
    ap.add_argument("--hst", default=DEFAULT_HST)
    ap.add_argument("--anchor")
    ap.add_argument("--box", type=float)
    a = ap.parse_args()

    if not os.path.exists(a.hst):
        sys.exit("no such .hst: " + a.hst)
    m1 = load_hst(a.hst)

    if a.anchor and a.box:
        cases = [("(command line)", a.anchor, a.box, "")]
    else:
        cases = read_rows(a.csv)

    print(f"series   {os.path.basename(a.hst)}  {len(m1)} bars  "
          f"{stamp(m1[0][0])} -> {stamp(m1[-1][0])}")
    print(f"rule     3 candles with high/low/close inside the box; the HIGHEST timeframe that holds")
    print()
    print(f"{'sample':<10}{'anchor':<18}{'box':>7}{'node':>6}  "
          f"{'knot TF':>8}{'span':>8}{'fill':>7}  {'breaks at':>12}{'ladder says':>13}")
    print("-" * 92)
    for name, anchor, box, node in cases:
        t = to_epoch(anchor)
        ok, bad = scan(m1, t, box)
        lad, _ = scan(m1, t, box, sweep=LADDER)
        if not ok:
            print(f"{name:<14}{anchor:<18}{box:>7.1f}{node:>6}  {'-':>8}{'-':>8}{'-':>7}  "
                  f"{str(bad[0]) + 'm' if bad else '-':>12}{str(lad[0]) + 'm' if lad else '-':>13}")
            continue
        fill = 100.0 * ok[1] / box
        bads = f"{bad[0]}m @ {bad[1]:.1f}p" if bad else "-"
        print(f"{name:<14}{anchor:<18}{box:>7.1f}{node:>6}  {str(ok[0]) + 'm':>8}"
              f"{ok[1]:>8.1f}{fill:>6.1f}%  {bads:>12}{str(lad[0]) + 'm' if lad else '-':>13}")

    print()
    print("fill = the three candles' span as a share of the box height. A box drawn around the")
    print("three candles fills ~100 %; a ladder rung that is not the knot's own time does not.")


if __name__ == "__main__":
    main()
