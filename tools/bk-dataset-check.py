#!/usr/bin/env python3
"""Validate every row of Samples/BK_Dataset/Dataset.csv against the knot's own law.

WHY: a dataset is only worth its worst row. A sample typed on one bar and sized on
another, or a TP that is not the stop's ratio, is not evidence — it is noise with a
timestamp. This checker re-derives D2 (type) and D3 (the three components) from the row's
own stored inputs and fails the row when the printed numbers cannot be reproduced.

  python tools/bk-dataset-check.py
  python tools/bk-dataset-check.py --csv path/to/Dataset.csv
  python tools/bk-dataset-check.py --quiet        # summary only

Exit 0 = every row is a sample. Exit 1 = at least one row is not.

The law it checks (docs/bk-dataset.md §1, §3):
  v7+ (P-BK-128, the ladder's RATIO midpoints):
  Band_FTR = sqrt(ATR_Trig x ATR_Pat)       Band_ETR = sqrt(ATR_Pat x ATR_Str)
  v1..v6 (the price midpoints they were captured under):
  Band_FTR = (ATR_Trig + ATR_Pat) / 2       Band_ETR = (ATR_Pat + ATR_Str) / 2
  Band_CTR = ATR_Str                         (never moved - the user's own OTR edge)
  Type     = FTR if h <= Band_FTR else ETR if h <= Band_ETR else CTR if h <= Band_CTR else OTR
  TPk      = round(Stop_Pips x {7/3, 5, 31/3})       (half away from zero, the plan's rule)
  Lot      = floor(Balance x Risk_Pct/100 / (Stop_Pips x PerPip), 2)
  Risk_USD = Stop_Pips x PerPip x Lot                 (1 decimal, as the ink prints it)
"""
import argparse
import csv
import math
import os
import re
import sys

RATIOS = (7.0 / 3.0, 5.0, 31.0 / 3.0)
TOL_BAND = 0.06
TOL_PIP = 0.051
TOL_USD = 0.051


def round_half_up(x):
    return math.floor(x + 0.5) if x >= 0 else -math.floor(-x + 0.5)


def floor2(x):
    return math.floor(x * 100.0 + 1e-9) / 100.0


def num(row, key):
    raw = (row.get(key) or "").strip()
    if raw == "":
        raise ValueError(f"{key} is empty")
    return float(raw)


def kind_of(h, ftr, etr, ctr):
    if h <= ftr:
        return "FTR"
    if h <= etr:
        return "ETR"
    if h <= ctr:
        return "CTR"
    return "OTR"


def band_law(version):
    """Which midpoint the row was captured under, or None when it did not say.

    v7 (P-BK-128) cut the bands at the ladder's RATIO midpoints, sqrt(a*b); v1..v6 at the
    price ones, (a+b)/2. A 217-pip box read FTR at 217.3 and ETR at 219.5 because that edge
    was 218.0 — 0.3 % away. A row is scored by the law IT recorded; an unrecorded version is
    never guessed (the caller tries both and says so), so an old row is not failed for being
    old and a new row is not scored by a rule it was not captured under."""
    m = re.match(r"\s*v(\d+)", (version or ""), re.IGNORECASE)
    if not m:
        return None
    return "ratio" if int(m.group(1)) >= 7 else "price"


def bands_of(trig, pat, str_):
    """Both laws at once: (price-midpoint bands, ratio-midpoint bands). Band_CTR is shared."""
    price = {"Band_FTR": (trig + pat) / 2.0, "Band_ETR": (pat + str_) / 2.0, "Band_CTR": str_}
    ratio = {"Band_FTR": math.sqrt(trig * pat) if trig > 0 and pat > 0 else 0.0,
             "Band_ETR": math.sqrt(pat * str_) if pat > 0 and str_ > 0 else 0.0,
             "Band_CTR": str_}
    return price, ratio


def check_row(row):
    """Return (errors, infos) for one row."""
    errs, infos = [], []
    sid = (row.get("Sample_ID") or "?").strip()

    try:
        h = num(row, "Box_Pips")
        trig, pat, str_ = num(row, "ATR_Trig"), num(row, "ATR_Pat"), num(row, "ATR_Str")
        ftr, etr, ctr = num(row, "Band_FTR"), num(row, "Band_ETR"), num(row, "Band_CTR")
        off, stop = num(row, "Entry_Off_Pips"), num(row, "Stop_Pips")
        tp = [num(row, f"TP{k}_Pips") for k in (1, 2, 3)]
        per, bal, rpct = num(row, "PerPip"), num(row, "Balance"), num(row, "Risk_Pct")
        lot, risk_usd = num(row, "Lot"), num(row, "Risk_USD")
        margin = num(row, "Edge_Margin_Pips")
    except ValueError as exc:
        return [f"{sid}: {exc}"], infos

    # --- the ruler: both anchors must be present, and the type is read at the story one
    if not (row.get("Story_Anchor") or "").strip():
        errs.append(f"{sid}: Story_Anchor missing — the bar that typed the knot is unknown")
    if not (row.get("Edge_Anchor") or "").strip():
        errs.append(f"{sid}: Edge_Anchor missing — the owner's own bar is unknown")
    if (row.get("Story_Anchor") or "").strip() != (row.get("Edge_Anchor") or "").strip():
        infos.append(
            f"{sid}: two rulers — owner at {row.get('Edge_Anchor')}, type at {row.get('Story_Anchor')}")

    # --- D2: the bands and the type come from the three ATRs, not from the sheet
    price, ratio = bands_of(trig, pat, str_)
    got = {"Band_FTR": ftr, "Band_ETR": etr, "Band_CTR": ctr}
    law = band_law(row.get("Formula_Version"))
    if law == "ratio":
        want = ratio
    elif law == "price":
        want = price
    else:
        same = lambda w: all(abs(got[k] - w[k]) <= TOL_BAND for k in w)
        want = price if same(price) else ratio
        infos.append(f"{sid}: Formula_Version not recorded — bands checked under both laws")
    for key, value in want.items():
        if abs(got[key] - value) > TOL_BAND:
            errs.append(f"{sid}: {key}={got[key]:.1f} but the ATRs say {value:.1f}" +
                        (" (ratio law, v7+)" if want is ratio else ""))

    kind = kind_of(h, ftr, etr, ctr)
    if (row.get("Type") or "").strip() != kind:
        errs.append(f"{sid}: Type={row.get('Type')} but h={h:.1f} sits in {kind}")

    near = min(abs(h - ftr), abs(h - etr), abs(h - ctr))
    if abs(margin - near) > TOL_BAND:
        errs.append(f"{sid}: Edge_Margin_Pips={margin:.1f} but the nearest band is {near:.1f}")

    # --- D3: the three components
    if off <= 0.0:
        errs.append(f"{sid}: Entry_Off_Pips must be > 0")
    if stop <= 0.0:
        errs.append(f"{sid}: Stop_Pips must be > 0")
    for k, ratio in enumerate(RATIOS, start=1):
        want_tp = round_half_up(stop * ratio)
        if abs(tp[k - 1] - want_tp) > 0.01:
            errs.append(f"{sid}: TP{k}={tp[k - 1]:.0f} but stop x {ratio:.2f} = {want_tp:.0f}")
    if not (tp[0] < tp[1] < tp[2]):
        errs.append(f"{sid}: TP legs are not increasing ({tp[0]:.0f}/{tp[1]:.0f}/{tp[2]:.0f})")

    # --- sizing: the lot is the risk the box can afford, floored to 0.01
    want_lot = floor2(bal * rpct / 100.0 / (stop * per))
    if abs(lot - want_lot) > 0.005:
        errs.append(f"{sid}: Lot={lot:.2f} but balance/risk says {want_lot:.2f}")
    want_usd = stop * per * lot
    if abs(risk_usd - want_usd) > TOL_USD:
        errs.append(f"{sid}: Risk_USD={risk_usd:.1f} but stop x perPip x lot = {want_usd:.1f}")

    # --- the verdict is a human fact, never defaulted
    if (row.get("Direction") or "").strip() in ("", "?"):
        infos.append(f"{sid}: Direction unknown — the journal does not print it")

    return errs, infos


def main():
    ap = argparse.ArgumentParser()
    here = os.path.dirname(os.path.abspath(__file__))
    ap.add_argument("--csv", default=os.path.join(here, "..", "Samples", "BK_Dataset", "Dataset.csv"))
    ap.add_argument("--quiet", action="store_true")
    args = ap.parse_args()

    path = os.path.abspath(args.csv)
    with open(path, newline="", encoding="utf-8-sig") as fh:
        rows = list(csv.DictReader(fh))

    print(f"BK DATASET CHECK  ({len(rows)} row(s))  {path}")
    print("=" * 78)
    bad = 0
    margins = []
    for row in rows:
        errs, infos = check_row(row)
        sid = (row.get("Sample_ID") or "?").strip()
        if not args.quiet:
            state = "PASS" if not errs else "FAIL"
            print(f"  [{state}] {sid}  {row.get('Type', ''):3s}  h={row.get('Box_Pips')}p"
                  f"  off={row.get('Entry_Off_Pips')}  stop={row.get('Stop_Pips')}"
                  f"  tp={row.get('TP1_Pips')}/{row.get('TP2_Pips')}/{row.get('TP3_Pips')}"
                  f"  margin={row.get('Edge_Margin_Pips')}p")
            for note in infos:
                print(f"         info: {note}")
            for err in errs:
                print(f"         ERROR: {err}")
        bad += 1 if errs else 0
        try:
            margins.append(float(row.get("Edge_Margin_Pips") or "nan"))
        except ValueError:
            pass

    print("-" * 78)
    if margins:
        margins.sort()
        med = margins[len(margins) // 2]
        print(f"  edge margin: min={margins[0]:.1f}p  median={med:.1f}p  max={margins[-1]:.1f}p")
        thin = [m for m in margins if m < 1.0]
        print(f"  within 1 pip of a type edge: {len(thin)}/{len(margins)}")
    print(f"  rows failing: {bad}/{len(rows)}")
    return 0 if bad == 0 else 1


if __name__ == "__main__":
    sys.exit(main())
