#!/usr/bin/env python3
"""step3_base_collision - WHICH base did the reaction tip collide with?

THE QUESTION (the user's): the step-3 tip stops somewhere - on WHAT base,
and how many legs back is it? The retrace/base the hand marks may sit several
legs behind D, so the formula must name the collision, not just the distance.

For every six-condition pivot C (same detector as step3_survey.py, imported -
never re-implemented), this tool:
  1. walks the reaction tip exactly like the survey (furthest extreme against
     C until a close back through C, or the horizon);
  2. projects the tradable line: C +/- 3*ATR(C) - the step-3 line the reverse
     trade would be taken at - and records whether the tip REACHED it;
  3. collects the last LEGS_BACK past swing levels on the tip's side
     (past Lows for a down tip, past Highs for an up tip, extremes only -
     the survey pivots carry no keyPrice, stated limit) and measures the
     nearest one in units of step3 = dist/3;
  4. scores a HIT at the lock's own gate (+-25%, TH3_HIT_MAX_STEP_ERR) and a
     wide HIT at half a step, against a SHUFFLE      (same C and same past bases,
     random tip bar inside the window - same levels, timing broken).

Lift is the only currency (pivot_repeatability.py's rule): a collision rate
alone is meaningless - price stops somewhere. A base only counts if real hits
beat the shuffle in BOTH halves of every series is overkill here; the sign
count across symbols (real > shuffle per symbol) is the holdout.

Usage:  python tools/step3_base_collision.py --selftest
        python tools/step3_base_collision.py --tf 240 --symbols XAUUSD,EURUSD
"""

import argparse
import os
import random
import statistics
import sys
from collections import Counter, defaultdict

sys.path.insert(0, "tools")
import mt4_history as mh
import step3_survey as s3

LEGS_BACK = 6
HIT_GATE = 0.25   # the lock's own +-25% gate (TH3_HIT_MAX_STEP_ERR)
HIT_WIDE = 0.50
N_SHUF = 4


def collide(tip, levels, step):
    """Nearest past level to the tip, in steps.

    `levels` oldest -> newest; legBack counts from the NEAREST base (1 = one
    leg back). Returns (dmin_steps, legBack, hit25, hit50). No levels, or no
    step, is absence: (inf, -1, False, False), never a guess.
    """
    if not levels or step is None or step <= 0:
        return float("inf"), -1, False, False
    best, arg = float("inf"), -1
    for j in range(len(levels) - 1, -1, -1):
        d = abs(tip - levels[j]) / step
        if d < best:
            best, arg = d, len(levels) - j
    return best, arg, best <= HIT_GATE, best <= HIT_WIDE


def reactions(sym, tf):
    """Yield (C_price, tip_price, dist, step3, atrC, past_levels, window)."""
    path = mh.find(symbol=sym, tf=tf)
    if not path:
        return
    bars = mh.load(path[0])
    if len(bars) < 200:
        return
    atr = s3.atr14(bars)
    pivs = s3.six_pivots(bars, atr)
    for p in pivs:
        if p[4]:
            continue                       # a base pivot is not a C
        kind = p[1]
        i0 = p[3] + 1
        end = min(len(bars) - 1, i0 + s3.HORIZON)
        tip_i, tip_p = -1, 0.0
        for i in range(i0, end):
            h, l = bars[i][2], bars[i][3]
            broke = (bars[i][4] > p[2]) if kind == "H" else (bars[i][4] < p[2])
            if broke:
                break
            if kind == "H":
                if tip_i < 0 or l < tip_p:
                    tip_p, tip_i = l, i
            else:
                if tip_i < 0 or h > tip_p:
                    tip_p, tip_i = h, i
        if tip_i < 0 or atr[tip_i] <= 0 or atr[p[0]] <= 0:
            continue
        dist = abs(p[2] - tip_p)
        if dist <= s3.MIN_DIST_ATR * atr[tip_i]:
            continue
        step3 = dist / 3.0
        side = "L" if tip_p < p[2] else "H"   # the side the tip fell on
        levels = [q[2] for q in pivs if q[0] < p[0] and q[1] == side][-LEGS_BACK:]
        yield dict(c=p[2], tip=tip_p, dist=dist, step3=step3,
                   atrC=atr[p[0]], levels=levels, i0=i0, end=end,
                   bars=bars, kind=kind, sym=sym)


def run_study(symbols, tf, seed=7):
    rng = random.Random(seed)
    n = 0
    reach = 0
    hit25 = hit50 = 0
    shuf25 = shuf50 = 0
    leg_hist = Counter()
    per_sym = {}
    for sym in symbols:
        sn = sr = s25 = s50 = 0
        f25 = f50 = 0
        for r in reactions(sym, tf):
            n += 1
            sn += 1
            if r["dist"] >= 3.0 * r["atrC"]:
                reach += 1
                sr += 1
            _, leg, h25, h50 = collide(r["tip"], r["levels"], r["step3"])
            hit25 += h25
            hit50 += h50
            s25 += h25
            s50 += h50
            if leg > 0:
                leg_hist[leg] += 1
            for _ in range(N_SHUF):
                j = rng.randrange(r["i0"], r["end"])
                fake = r["bars"][j][3] if r["tip"] < r["c"] else r["bars"][j][2]
                _, _, f25j, f50j = collide(fake, r["levels"], r["step3"])
                f25 += f25j
                f50 += f50j
        shuf25 += f25
        shuf50 += f50
        # plain counts; rates derived at print time
        per_sym[sym] = dict(n=sn, reach=sr, h25=s25, f25=f25)
    return dict(n=n, reach=reach, h25=hit25, h50=hit50,
                shuf25=shuf25, shuf50=shuf50, legs=leg_hist, per_sym=per_sym)


def selftest():
    ok = True

    def chk(name, cond):
        nonlocal ok
        print(("PASS " if cond else "FAIL ") + name)
        ok = ok and cond

    d, leg, h25, h50 = collide(80.0, [70.0, 80.0, 90.0, 100.0], 12.0)
    chk("tip on 3rd level back -> leg 3, hit25", d == 0.0 and leg == 3 and h25 and h50)
    d, leg, h25, h50 = collide(103.0, [90.0, 100.0], 12.0)
    chk("3pt off a 12pt step -> 0.25 hit25", abs(d - 0.25) < 1e-9 and h25 and leg == 1)
    d, leg, h25, h50 = collide(105.0, [100.0], 12.0)
    chk("0.42 step -> wide hit only", abs(d - 5.0/12.0) < 1e-9 and not h25 and h50)
    d, leg, h25, h50 = collide(200.0, [100.0], 12.0)
    chk("far tip -> no hit", not h25 and not h50 and d > 1.0)
    d, leg, h25, h50 = collide(100.0, [], 12.0)
    chk("no levels -> absence", d == float("inf") and leg == -1 and not h25)
    d, leg, h25, h50 = collide(100.0, [100.0], 0.0)
    chk("no step -> absence", d == float("inf") and leg == -1)
    chk("survey detector selftest holds", s3.selftest())
    print("selftest:", "ALL PASS" if ok else "FAILURES PRESENT")
    return ok


def main(argv):
    ap = argparse.ArgumentParser()
    ap.add_argument("--selftest", action="store_true")
    ap.add_argument("--tf", type=int, default=240)
    ap.add_argument("--symbols", default="")
    ap.add_argument("--seed", type=int, default=7)
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
    print("symbols:", ", ".join(syms), "| chart TF:",
          s3.TF_NAME.get(args.tf, args.tf), "| legs back:", LEGS_BACK)
    r = run_study(syms, args.tf, args.seed)
    n = max(1, r["n"])
    shuf_n = max(1, N_SHUF * r["n"])
    print(f"\nreactions: {r['n']}")
    print(f"reached C+-3*ATR(C) ......... {r['reach']:5d} ({100.0*r['reach']/n:.1f}%)")
    print(f"hit past base +-25% (real) .. {r['h25']:5d} ({100.0*r['h25']/n:.1f}%)")
    print(f"hit past base +-25% (shuf) .. {r['shuf25']:5d} ({100.0*r['shuf25']/shuf_n:.1f}%)")
    print(f"hit past base +-50% (real) .. {r['h50']:5d} ({100.0*r['h50']/n:.1f}%)")
    print(f"hit past base +-50% (shuf) .. {r['shuf50']:5d} ({100.0*r['shuf50']/shuf_n:.1f}%)")
    tot_leg = max(1, sum(r["legs"].values()))
    print("\nwhich leg back owned the nearest base (real hits):")
    for leg in range(1, LEGS_BACK + 1):
        c = r["legs"].get(leg, 0)
        print(f"  {leg} back: {c:5d} ({100.0*c/tot_leg:.1f}%)")
    print("\nper symbol (n, reach%, hit25% real vs shuf):")
    wins = 0
    for sym, v in sorted(r["per_sym"].items()):
        sn = max(1, v["n"])
        rr = 100.0 * v["reach"] / sn
        hr = 100.0 * v["h25"] / sn
        sr = 100.0 * v["f25"] / max(1, N_SHUF * v["n"])
        if v["n"] > 0 and hr > sr:
            wins += 1
        print(f"  {sym:10s} n={v['n']:4d} reach={rr:5.1f}% hit25={hr:5.1f}% shuf={sr:5.1f}%")
    print(f"\nsymbols where real beats shuffle: {wins}/{sum(1 for v in r['per_sym'].values() if v['n']>0)}")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
