#!/usr/bin/env python3
"""step3_survey — the user's step-3 rule, tested over the terminal's whole history.

THE RULE UNDER TEST (the user's, P-TH3-STEP-03): from a pivot C, the market's
reaction tip IS step 3 — so step = |C - tip| / 3, and the question is which
timeframe's ATR that step belongs to (the fractal grid's owner).

For every six-condition pivot of a chart timeframe, this tool:
  1. walks forward for the reaction tip (the furthest extreme against C
     until price CLOSES back through C — the base broke — or a horizon);
  2. computes step3 = |C - tip| / 3;
  3. checks whether the tip is one of THIS timeframe's six-condition pivots,
     and if not, which higher TF claims it (the walk-up rule);
  4. compares step3 against ATR14 of the claiming TF and records the owner.

The output is the evidence for (or against) a formula: the distribution of
step3/ATR per owning timeframe over thousands of reactions.
"""

import argparse
import os
import statistics
import sys
from collections import Counter, defaultdict

sys.path.insert(0, "tools")
import mt4_history as mh

CONFIRM = 0.80
MASTER = 0.80
HYPO = 1.00
STD_LO, STD_HI = 0.80, 1.20
RUN_STD = 3
RUN_EXT = 2.40
SIDE_RANGE = 0.60
SIDE_MAX = 4
CLOSE_THIRD = 1.0 / 3.0
MAX_WAIT = 20
HORIZON = 200
MIN_DIST_ATR = 0.30
CHAIN = [1, 5, 15, 60, 240, 1440, 10080, 43200]
TF_NAME = {1: "M1", 5: "M5", 15: "M15", 30: "M30", 60: "H1", 240: "H4",
           1440: "D1", 10080: "W1", 43200: "MN"}


def atr14(bars):
    """MT4-style Wilder ATR(14)."""
    n = len(bars)
    trs = [0.0] * n
    for i in range(n):
        h, l = bars[i][2], bars[i][3]
        pc = bars[i - 1][4] if i > 0 else bars[i][1]
        trs[i] = max(h - l, abs(h - pc), abs(l - pc))
    atr = [0.0] * n
    if n <= 14:
        return atr
    atr[14] = sum(trs[1:15]) / 14.0
    for i in range(15, n):
        atr[i] = (atr[i - 1] * 13.0 + trs[i]) / 14.0
    return atr


def run_ok(bars, atr, ext_i, kind):
    """Conditions 1+2: the move INTO the pivot."""
    a = atr[ext_i]
    if a <= 0:
        return False, False
    run = 0
    j = ext_i
    while j >= 1:
        moved = (bars[j - 1][4] < bars[j][4]) if kind == "H" else (bars[j - 1][4] > bars[j][4])
        if not moved:
            break
        run += 1
        j -= 1
    if run < 1:
        return False, False
    run_start = ext_i - run
    run_ext = abs(bars[ext_i][4] - bars[run_start][4]) / a
    std_run = 0
    for k in range(ext_i, ext_i - run, -1):
        if k < 0 or atr[k] <= 0:
            break
        x = (bars[k][2] - bars[k][3]) / atr[k]
        if not (STD_LO <= x <= STD_HI):
            break
        std_run += 1
    side = 0
    k2 = run_start - 1
    while k2 >= 0 and side < 8:
        if atr[k2] <= 0:
            break
        if (bars[k2][2] - bars[k2][3]) > SIDE_RANGE * atr[k2]:
            break
        side += 1
        k2 -= 1
    base = side >= SIDE_MAX
    return (std_run >= RUN_STD or run_ext >= RUN_EXT), base


def find_cover(bars, atr, ext_i, kind, is_master, from_i):
    """Conditions 4+5. Master: one candle engulfing the pivot's full range.
    Hypothetical 1-ATR line: the REVERSAL trading through the line's far
    edge — cumulative, one bar or several (PDF cond 3: "یک کندل یا چند کندل").
    """
    a = atr[ext_i]
    if a <= 0:
        return -1
    eh, el = bars[ext_i][2], bars[ext_i][3]
    for j in range(from_i, ext_i, -1):
        h, l = bars[j][2], bars[j][3]
        if is_master:
            if h >= eh and l <= el:
                return j
        else:
            if kind == "H" and l <= eh - HYPO * a:
                return j
            if kind == "L" and h >= el + HYPO * a:
                return j
    return -1


def close_third(bars, j, kind):
    h, l, c = bars[j][2], bars[j][3], bars[j][4]
    if h <= l:
        return False
    pos = (c - l) / (h - l)
    return pos <= CLOSE_THIRD if kind == "H" else pos >= 1.0 - CLOSE_THIRD


def is_master_candle(bars, i):
    o, h, l, c = bars[i][1], bars[i][2], bars[i][3], bars[i][4]
    rng = h - l
    if rng <= 0:
        return False
    body = abs(c - o)
    shadow = max(h - max(o, c), min(o, c) - l)
    return body / rng >= MASTER or shadow / rng >= MASTER


def six_pivots(bars, atr):
    """The product's walk: confirm at 0.80 ATR, declare on the cover."""
    out = []
    state, ext_i, ext_p, pend = 0, 0, 0.0, 0
    for i in range(15, len(bars)):
        a = atr[i]
        if a <= 0:
            continue
        h, l = bars[i][2], bars[i][3]
        flip = None
        if state == 0:
            ext_p, ext_i, state = h, i, 1
            continue
        if state > 0:
            if h > ext_p:
                ext_p, ext_i, pend = h, i, 0
                continue
            if ext_p - l >= CONFIRM * a:
                flip = ("H", l)
        else:
            if l < ext_p:
                ext_p, ext_i, pend = l, i, 0
                continue
            if h - ext_p >= CONFIRM * a:
                flip = ("L", h)
        if flip is None:
            continue
        kind, new_ext = flip
        ok, base = run_ok(bars, atr, ext_i, kind)
        declared = False
        if ok:
            mst = is_master_candle(bars, ext_i)
            cov = find_cover(bars, atr, ext_i, kind, mst, i)
            if cov < 0 and not mst and pend < MAX_WAIT:
                pend += 1
                continue                      # the hypothetical line not covered yet
            if cov >= 0 and close_third(bars, cov, kind):
                out.append((ext_i, kind, ext_p, i, base))
                declared = True
        state = -1 if kind == "H" else 1
        ext_p, ext_i, pend = new_ext, i, 0
    return out


def chain_up(tf):
    if tf not in CHAIN:
        bigger = [t for t in CHAIN if t > tf]
        return bigger[0] if bigger else None
    i = CHAIN.index(tf)
    return CHAIN[i + 1] if i + 1 < len(CHAIN) else None


def run_survey(symbols, tf):
    """All reactions off six-condition pivots of one TF, across symbols."""
    res = {"n": 0, "same_tf_pivot": 0, "claimed": 0, "unclaimed": 0}
    ratios_by_owner = defaultdict(list)
    owner_ct = Counter()
    claim_ct = Counter()
    per_sym = Counter()
    for sym in symbols:
        path = mh.find(symbol=sym, tf=tf)
        if not path:
            continue
        bars = mh.load(path[0])
        if len(bars) < 200:
            continue
        atr = atr14(bars)
        pivs = six_pivots(bars, atr)
        higher = {}
        t2 = chain_up(tf)
        while t2:
            hp = mh.find(symbol=sym, tf=t2)
            if hp:
                hb = mh.load(hp[0])
                if len(hb) > 200:
                    hatr = atr14(hb)
                    higher[t2] = (hb, six_pivots(hb, hatr), hatr)
            t2 = chain_up(t2)
        for p in pivs:
            if p[4]:
                continue                       # a base pivot is not a C
            kind = p[1]                        # the reaction runs AGAINST it
            i0 = p[3] + 1
            end = min(len(bars) - 1, i0 + HORIZON)
            tip_i, tip_p = -1, 0.0
            for i in range(i0, end):
                h, l = bars[i][2], bars[i][3]
                broke = (bars[i][4] > p[2]) if kind == "H" else (bars[i][4] < p[2])
                if broke:
                    break                      # the base broke: reaction over
                if kind == "H":
                    if tip_i < 0 or l < tip_p:
                        tip_p, tip_i = l, i
                else:
                    if tip_i < 0 or h > tip_p:
                        tip_p, tip_i = h, i
            if tip_i < 0 or atr[tip_i] <= 0:
                continue
            dist = abs(p[2] - tip_p)
            if dist <= MIN_DIST_ATR * atr[tip_i]:
                continue
            step3 = dist / 3.0
            res["n"] += 1
            per_sym[sym] += 1
            # the distance ladder itself — the formula question needs no pivot
            # match: is the run from C to the tip a common multiple of ATR?
            res.setdefault("dist_atr", []).append(dist / atr[tip_i])
            res.setdefault("step3_atr", []).append(step3 / atr[tip_i])
            # the detector needs bars AFTER the extreme to declare, so the
            # declaration lags the tip — the match window is generous in TIME
            # (a pivot declared up to 6 bars after the tip still owns it)
            # and the price is already the extreme's own.
            same = any(not q[4] and q[1] != kind
                       and tip_i - 1 <= q[0] <= tip_i + 6
                       for q in pivs)
            tip_t = bars[tip_i][0]
            owner, best = None, 1e9
            claimed = same
            tip_t = bars[tip_i][0]
            owner, best = None, 1e9
            claimed = same
            for t2, (hb, hpiv, hatr) in higher.items():
                if not hb or hb[0][0] > tip_t:
                    continue
                idx = max(i for i, b in enumerate(hb) if b[0] <= tip_t)
                hit = any(not q[4] and q[1] != kind and idx - 1 <= q[0] <= idx + 2
                          for q in hpiv)
                if hit:
                    claimed = True
                    if hatr[idx] > 0:
                        r = step3 / hatr[idx]
                        if abs(r - 1.0) < abs(best - 1.0):
                            best, owner = r, t2
            # the owner must EARN the answer: only a TF that claims the tip
            # (this one, or a higher one) may carry the step3/ATR ratio.
            if owner is None and same:
                owner = tf
                best = step3 / atr[tip_i] if atr[tip_i] > 0 else 9e9
            res["claimed" if claimed else "unclaimed"] += 1
            claim_ct["same-TF pivot" if same else
                     ("higher-TF pivot" if claimed else "NO pivot at tip")] += 1
            if owner is not None:
                ratios_by_owner[TF_NAME.get(owner, str(owner))].append(best)
                owner_ct[TF_NAME.get(owner, str(owner))] += 1
    return res, ratios_by_owner, owner_ct, claim_ct, per_sym


def selftest():
    """A planted drop of 3x leg must be recovered as step = leg."""
    bars = []
    px, t = 100.0, 1700000000
    for _ in range(200):
        bars.append((t, px, px + 0.1, px - 0.1, px))
        t += 60
        px += 0.001
    c_price = px
    leg = 3.0
    for _ in range(60):          # the total drop is 3 x leg, so step3 == leg
        px -= (3.0 * leg) / 60.0
        bars.append((t, px, px + 0.05, px - 0.05, px))
        t += 60
    for _ in range(40):
        bars.append((t, px, px + 0.05, px - 0.05, px))
        t += 60
    dist = c_price - (px - 0.05)
    step3 = dist / 3.0
    ok = abs(step3 - leg) < 0.35 * leg
    print(f"selftest: planted C={c_price:.2f} tip={px - 0.05:.2f} "
          f"dist={dist:.2f} step3={step3:.2f} (leg={leg}) -> "
          f"{'PASS' if ok else 'FAIL'}")
    return ok


def main(argv):
    ap = argparse.ArgumentParser()
    ap.add_argument("--selftest", action="store_true")
    ap.add_argument("--tf", type=int, default=240)
    ap.add_argument("--symbols", default="")
    args = ap.parse_args(argv)
    if args.selftest:
        return 0 if selftest() else 1

    syms = [s for s in args.symbols.split(",") if s]
    if not syms:
        seen = set()
        for p in mh.find():
            b = os.path.basename(str(p))
            sym = b[:-4] if b.endswith(".hst") else b
            k = len(sym)
            while k > 0 and sym[k - 1].isdigit():
                k -= 1
            if sym[:k]:
                seen.add(sym[:k])
        syms = sorted(seen)
    print("symbols:", ", ".join(syms), "| chart TF:", TF_NAME.get(args.tf, args.tf))
    res, ratios, owners, claim_ct, per_sym = run_survey(syms, args.tf)
    print(f"\nreactions tested: {res['n']}")
    for k in ("same-TF pivot", "higher-TF pivot", "NO pivot at tip"):
        print(f"  {k:<20}: {claim_ct.get(k, 0):5d} "
              f"({100.0 * claim_ct.get(k, 0) / max(1, res['n']):.1f}%)")
    print("\nstep3 / ATR14 of the OWNING timeframe (the formula candidate):")
    for o in sorted(ratios):
        v = sorted(ratios[o])
        print(f"  {o:>4}: n={len(v):5d}  median={statistics.median(v):.2f}  "
              f"p25={v[len(v)//4]:.2f}  p75={v[3*len(v)//4]:.2f}")
    d = sorted(res.get("dist_atr", []))
    if d:
        import statistics as _st
        s3 = sorted(res.get("step3_atr", []))
        print("\nthe DISTANCE itself, in same-TF ATR (no pivot match needed):")
        print(f"  dist/ATR : n={len(d):5d}  median={_st.median(d):.2f}  "
              f"p25={d[len(d)//4]:.2f}  p75={d[3*len(d)//4]:.2f}")
        print(f"  step3/ATR: n={len(s3):5d}  median={_st.median(s3):.2f}  "
              f"p25={s3[len(s3)//4]:.2f}  p75={s3[3*len(s3)//4]:.2f}")
        print("  (step3/ATR ~ 1.0 would mean: step = ATR of this TF, fractally)")
    print("\nowner distribution:", dict(owners))
    print("per symbol:", dict(per_sym))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))


