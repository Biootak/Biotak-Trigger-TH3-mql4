#!/usr/bin/env python3
"""
THE HIDDEN VARIABLE — where the box sits on the ability ladder, in rungs.

v7 (P-BK-128). `BaseKnotNodeKindOfLength` compares h to three ATRs read at the story anchor:
    a0 = ATR(node rung)   a1 = ATR(+1)   a2 = ATR(+2)
and cuts at their RATIO midpoints (v1..v6 cut at the price ones, which is why one 217-pip box
read FTR at 217.3 and ETR at 219.5 — that edge sat at 218.0, 0.3 % away):
    FTR  h <= sqrt(a0*a1)      ETR  h <= sqrt(a1*a2)
    CTR  h <=  a2              OTR  h >   a2          (the user's own edge)

Those cuts are exactly the knots of ONE piecewise-LOG coordinate:
    u = 0 at a0, 1 at a1, 2 at a2, 3 at a3, interpolated in ln(h)
    FTR  u <= 0.5      ETR  u <= 1.5      CTR  u <= 2.0      OTR  u > 2.0
u = 0.5 IS sqrt(a0*a1), so the coordinate and the type name cannot disagree — that is the whole
point of printing it.

THE HOP IS A DIFFERENT QUESTION. v2 answered round(u) — a price midpoint on the leg, so the same
box at 217.3 pips paid Eng 31.7 / Trigger 84.5 and at 219.5 paid 70.5 / 188.0, i.e. 258.5 pips of
legs inside a 217-pip box. v7 asks which rung's whole leg PACKAGE still fits:
    hop = the deepest k with 55/64 * a_k <= h
55/64 = off 5/8 + risk 15/64 = BK_NODE_HUNT_NUM/DEN + 1/BK_NODE_POWER_DIV, so "fits" is the same
sentence the legs are drawn by. hop 0 always stands: the node's own rung is the smallest package.

This script measures, per sample:
  * u and the margin to the nearest band edge, in rungs
  * where the OWNER band [2.40, 3.60] lands on the same u axis
  * the stop the NAME charged (FTR 0 / ETR 1 / CTR 2 / OTR 3) vs the capacity rung

Source of truth is the log, not the CSV: the [P-BK-107] line carries a0/a1/a2
and the [BK-OWNER] line carries the owner ratio and its own anchor.
"""
import csv
import json
import math
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
CSV = os.path.join(ROOT, "Samples", "BK_Dataset", "Dataset.csv")
LOGS = [os.path.expanduser(r"~\AppData\Roaming\MetaQuotes\Terminal\A1660DA4CB596E740BE3B3233E577E1B\MQL4\Logs")]

DIV = 4.266666          # BK_NODE_POWER_DIV
FIT = 55.0 / 64.0       # BK_AB_FIT_NUM / BK_AB_FIT_DEN — the whole leg package of one rung
OWNER_LO = 2.40         # BK_OWNER_LO
OWNER_HI = 3.60         # BK_OWNER_HI
BANDS = [(0.0, 0.5, "FTR"), (0.5, 1.5, "ETR"), (1.5, 2.0, "CTR"), (2.0, 99.0, "OTR")]
HOPS = {"FTR": 0, "ETR": 1, "CTR": 2, "OTR": 3}


def find_log(name):
    for d in LOGS:
        p = os.path.join(d, name)
        if os.path.exists(p):
            return p
    return None


def read_lines(path, nums):
    out = {}
    with open(path, "r", encoding="utf-8", errors="replace") as f:
        for i, line in enumerate(f, 1):
            if i in nums:
                out[i] = line.rstrip("\r\n")
    return out


def parse_owner(line):
    if not line or "[BK-OWNER]" not in line:
        return None
    # the field name must start a token, or `r=` matches inside `read=`
    g = lambda k: (re.search(r"(?<![A-Za-z0-9_])" + k + r"=(\S+)", line) or [None, ""])[1]
    return {
        "owner": g("owner"),
        "atr": float(g("atr") or 0),
        "r": float(g("r") or 0),
        "anchor": g("anchor"),
    }


def is_ratio_row(row):
    """v7 cut the bands at sqrt(a*b); v1..v6 at (a+b)/2. A row is read by its own version."""
    m = re.match(r"\s*v(\d+)", (row.get("Formula_Version") or ""), re.IGNORECASE)
    return bool(m) and int(m.group(1)) >= 7


def u_of(h, a):
    """The product's own coordinate (BaseKnotLadderU, BaseKnot_Shot.mqh), segment for segment.
    a = [a0, a1, a2, a3]; NaN where the product answers -1 (no fourth rung past a2)."""
    if not (h > 0.0 and a[0] > 0.0 and a[1] > a[0]):
        return float("nan")
    if h <= a[1]:
        return math.log(h / a[0]) / math.log(a[1] / a[0])
    if h <= a[2]:
        return 1.0 + math.log(h / a[1]) / math.log(a[2] / a[1])
    if a[3] > a[2]:
        return 2.0 + math.log(h / a[2]) / math.log(a[3] / a[2])
    return float("nan")


def hop_of(h, a):
    """The product's own rung (BaseKnotLadderHopAt, BaseKnot_Ability.mqh). -1 = no 4th rung."""
    if h > a[2]:
        if not (a[3] > a[2]):
            return -1
        if h >= FIT * a[3]:
            return 3
    hop = 0
    if h >= FIT * a[1]:
        hop = 1
    if h >= FIT * a[2]:
        hop = 2
    return hop


def band_of(u):
    if not (u == u):
        return "", 0.0, 0.0
    for lo, hi, name in BANDS:
        if u <= hi:
            return name, lo, hi
    return "OTR", 2.0, 99.0


def main():
    rows = []
    with open(CSV, "r", encoding="utf-8-sig", newline="") as f:
        for row in csv.DictReader(f):
            if not row.get("Sample_ID"):
                continue
            rows.append(row)
    if not rows:
        print("no rows")
        return 1

    print("THE LADDER COORDINATE  u = 0 at ATR(node) .. 3 at ATR(+3), interpolated in ln(h)")
    print("=" * 122)
    hdr = ("sample    type  h      a0     a1     a2     a3     r1    r2    u      "
           "edge   marg  hopN hopF  stopN  stopF   x")
    print(hdr)
    print("-" * 122)

    # a3's source, in order of authority: the row's own ATR_Fourth column (v7 records it),
    # a pre-v7 OTR row's stop (that stop WAS EngSL(a3) under the name rule), a sibling row
    # measured on the same ladder, then the geometric extrapolation — marked, never silent.
    a3_measured = {}
    for r in rows:
        if r["Type"] == "OTR" and not is_ratio_row(r) and float(r["Stop_Pips"] or 0) > 0:
            k = (float(r["ATR_Trig"]), float(r["ATR_Pat"]), float(r["ATR_Str"]))
            a3_measured[k] = max(a3_measured.get(k, 0.0), float(r["Stop_Pips"]) * DIV)

    out = []
    for r in rows:
        sid = r["Sample_ID"]
        h = float(r["Box_Pips"])
        nums = {int(x) for x in r["Log_Lines"].split("/") if x.strip().isdigit()}
        log = find_log(r["Log_File"])
        lines = read_lines(log, nums) if log else {}
        own = None
        for n in sorted(lines):
            own = own or parse_owner(lines[n])

        a0, a1, a2 = float(r["ATR_Trig"]), float(r["ATR_Pat"]), float(r["ATR_Str"])
        typ = r["Type"]
        fourth = float((r.get("ATR_Fourth") or "0").strip() or 0)
        if fourth > a2:
            a3, a3_from = fourth, "row"
        elif typ == "OTR" and not is_ratio_row(r) and float(r["Stop_Pips"]) > 0:
            a3, a3_from = float(r["Stop_Pips"]) * DIV, "stop"     # the name rule read a3
        elif (a0, a1, a2) in a3_measured:
            a3, a3_from = a3_measured[(a0, a1, a2)], "sibling"
        else:
            a3, a3_from = a2 * (a2 / a1), "extrapolated"
        a = [a0, a1, a2, a3]
        u = u_of(h, a)
        name, lo, hi = band_of(u)
        # margin to the nearest band edge, in rungs
        edges = [0.5, 1.5, 2.0]
        marg = min(abs(u - e) for e in edges) if u == u else float("nan")
        hop_name = HOPS[typ]
        hop_fit = hop_of(h, a)
        stop_name = float(r["Stop_Pips"])
        stop_fit = a[hop_fit] / DIV if hop_fit >= 0 else float("nan")
        out.append({
            "id": sid, "type": typ, "h": h, "a": a, "u": u, "name": name,
            "marg": marg, "hop_name": hop_name, "hop_fit": hop_fit,
            "stop_name": stop_name, "stop_fit": stop_fit, "a3_from": a3_from,
            "owner": own, "r1": a1 / a0, "r2": a2 / a1,
        })
        print("%-9s %-4s %6.1f %6.1f %6.1f %6.1f %6.1f%s %5.2f %5.2f %6.3f "
              "%5.2f %6.3f %3d %4d %7.1f %6.1f %5.2f"
              % (sid, typ, h, a0, a1, a2, a3, "*" if a3_from == "extrapolated" else " ",
                 a1 / a0, a2 / a1, u,
                 min(edges, key=lambda e: abs(u - e)) if u == u else 0.0, marg, hop_name,
                 hop_fit, stop_name, stop_fit,
                 stop_name / stop_fit if stop_fit == stop_fit and stop_fit else 0))

    print("-" * 122)
    print("  u = position on the ladder in rungs (u = 0.5 IS sqrt(a0*a1), the FTR/ETR edge);")
    print("  marg = distance to the nearest edge in rungs (0.003 = 0.3% of one rung);")
    print("  hopN = the NAME's hop (v1) · hopF = the deepest package that fits, 55/64 x a_k <= h;")
    print("  stopN = Stop_Pips as captured · stopF = EngSL(a[hopF]) · x = stopN / stopF;")
    print("  a3* = extrapolated (a2 x a2/a1) — the row did not record it.")

    # --- the straddle: where does the owner band [2.40, 3.60] land on this axis?
    print()
    print("WHERE THE OWNER BAND [2.40, 3.60] LANDS ON THE SAME AXIS")
    print("=" * 122)
    print("sample    u_lo   u_hi   width  |  FTR    ETR    CTR    OTR   (share of the band)")
    print("-" * 122)
    for o in out:
        a = o["a"]
        ulo, uhi = u_of(OWNER_LO * a[0], a), u_of(OWNER_HI * a[0], a)
        w = uhi - ulo
        shares = []
        for lo, hi, nm in BANDS:
            ov = max(0.0, min(uhi, hi) - max(ulo, lo))
            shares.append(ov / w if w > 0 else 0.0)
        o["owner_band"] = [ulo, uhi]
        o["shares"] = shares
        print("%-9s %6.3f %6.3f %6.3f  | %5.1f%% %5.1f%% %5.1f%% %5.1f%%"
              % (o["id"], ulo, uhi, w, *[100 * s for s in shares]))

    print("-" * 122)
    widths = [o["owner_band"][1] - o["owner_band"][0] for o in out]
    print("  owner band width in rungs: min=%.3f max=%.3f  (a fixed 1.5x ratio is not a"
          % (min(widths), max(widths)))
    print("  fixed number of rungs, because the ladder's own step is not fixed)")

    # --- the jump
    print()
    print("THE JUMP — the same box, 7.8 pips of height, 4 seconds apart")
    print("=" * 122)
    for o in out:
        if o["id"] in ("BK-0003", "BK-0004"):
            print("  %s  h=%6.1f  u=%6.3f  %-4s  hopN=%d  hopF=%d  stopN=%6.1f  stopF=%6.1f"
                  % (o["id"], o["h"], o["u"], o["type"], o["hop_name"], o["hop_fit"],
                     o["stop_name"], o["stop_fit"]))
    j = [o for o in out if o["id"] in ("BK-0003", "BK-0004")]
    if len(j) == 2:
        dh = j[1]["h"] - j[0]["h"]
        ds = j[1]["stop_name"] / j[0]["stop_name"]
        du = j[1]["u"] - j[0]["u"]
        print("  delta: h %+.1f pips (%+.1f%%)  ->  u %+.3f rungs  ->  1R x%.2f"
              % (dh, 100 * dh / j[0]["h"], du, ds))
        print("  with the capacity rung:  1R x%.2f"
              % (j[1]["stop_fit"] / j[0]["stop_fit"]))

    # --- summary of what changes
    # 0.15 = the log prints the stop to one decimal, so 31.95 vs 32.0 is the same number
    moved = [o for o in out if abs(o["stop_name"] - o["stop_fit"]) > 0.15]
    print()
    print("WHAT THE CAPACITY RUNG CHANGES vs the NAME's hop: %d of %d samples"
          % (len(moved), len(out)))
    for o in out:
        tag = "MOVES" if o in moved else "same "
        print("  %s %-9s %-4s  stop %7.1f -> %7.1f  (x%.2f)"
              % (tag, o["id"], o["type"], o["stop_name"], o["stop_fit"],
                 o["stop_name"] / o["stop_fit"] if o["stop_fit"] else 0))

    payload = [{
        "id": o["id"], "type": o["type"], "u": round(o["u"], 3),
        "marg": round(o["marg"], 4),
        "band": [round(o["owner_band"][0], 3), round(o["owner_band"][1], 3)],
        "hop_name": o["hop_name"], "hop_fit": o["hop_fit"],
        "stop_name": round(o["stop_name"], 1),
        "stop_fit": round(o["stop_fit"], 1) if o["stop_fit"] == o["stop_fit"] else None,
        "a3_from": o["a3_from"],
        "owner_r": o["owner"]["r"] if o["owner"] else None,
    } for o in out]
    os.makedirs(os.path.join(ROOT, "build-logs"), exist_ok=True)
    with open(os.path.join(ROOT, "build-logs", "bk-ladder-u.json"), "w", encoding="utf-8") as f:
        json.dump(payload, f, ensure_ascii=False, indent=1)
    print()
    print("json -> build-logs/bk-ladder-u.json")
    return 0


if __name__ == "__main__":
    sys.exit(main())
