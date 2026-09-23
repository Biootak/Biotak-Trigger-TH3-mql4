#!/usr/bin/env python3
"""th3_momentum_bands — derive the TH3 momentum bands from bars, not from opinion.

WHY THE METRIC IS BEING REPLACED
    TH3's momentum axis reads `CalculateWaveAngle()`. That function is not an
    angle: it computes

        speedRatio = (pips per minute) / (ATR(D1) per minute)     [1440 minutes]
        angle      = atan(speedRatio) in degrees, clamped to 0..90

    A geometric angle needs a fixed price-per-pixel and time-per-pixel scale, and
    MT4 autoscales the chart, so there is no such thing to measure. What the
    function actually reports is a dimensionless speed ratio against the DAILY
    ATR - and it is then called "angle", which invites the reader to think of the
    chart's geometry and hides which reference is doing the work.

    Two real defects follow, and both are time-dependent:
      * The reference is the daily ATR. A fast H1 impulse on a high-volatility day
        is scored against that day's range, so it reads WEAK exactly when the day
        is busy - the opposite of what "momentum" should say.
      * It divides by elapsed time LINEARLY. Displacement accumulates like the
        SQUARE ROOT of time, so a leg that takes four times as long is penalised
        by 4x when volatility only justifies 2x. Long legs read weak by
        construction.

THE REPLACEMENT
        R = |A->B| / (ATR(trigger) * sqrt(elapsed / triggerBarMinutes))

    Numerator and denominator are both in the same units, so R is dimensionless and
    needs no pip convention. R = 1 means "this leg travelled exactly as far as the
    trigger timeframe's own ATR predicts for that many bars", R = 2 means twice
    that. Because volatility enters at its natural sqrt-in-time rate, a leg is no
    longer punished for taking a long time - and because nothing in it mentions
    the D1 series, "weak" stops meaning "big daily range".

    It stays TIMEFRAME-INVARIANT, which the metric it replaces also was: the old
    formula contained no bar count, only elapsed minutes, so one leg read the same
    number on every chart. Introducing `Period()` as a raw divisor would have
    broken that and forced a separate set of band constants per chart timeframe -
    the kind of thing that is silently wrong on the one timeframe nobody tested.
    Here the timeframe enters as a ratio (elapsed / barMinutes) under the sqrt,
    which is what keeps one owner for the bands.

HOW THE BANDS ARE CHOSEN
    Not analytically: the two metrics are not proportional (one is linear in
    1/time, the other in 1/sqrt(time)), so no conversion factor exists. Instead
    the old bands' boundaries are read off this data as QUANTILES of the old
    metric, and the new thresholds are the same quantiles of the new metric. The
    class mix is therefore preserved - the axis keeps classifying the same share of
    legs as weak / normal / strong / explosive - while the number underneath
    becomes measurable. `--report` prints both.

Usage:  python tools/th3_momentum_bands.py --selftest
        python tools/th3_momentum_bands.py --report
        python tools/th3_momentum_bands.py --report --tf 15
        python tools/th3_momentum_bands.py --report --bands 0.70,1.00,1.60

HOW THE BANDS NOW DIVERGE FROM THE QUANTILE MIX
    The quantile rule above preserves the OLD class mix, and the old mix is itself
    the problem: it puts 44% of legs at STRONG and 39% at EXPLOSIVE, so 83% of legs
    take the same step and the axis decides almost nothing. Preserving a mix like
    that preserves the inertness. `--report` therefore prints the R percentile
    ladder beside the mix, and `--bands` scores any candidate set against it; the
    shipped constants are chosen from that ladder, with R = 1 kept as a boundary
    because R = 1 is the trigger ATR's own expectation and the one value on this
    axis that means something without being calibrated.
"""
import json
import math
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import mt4_history as hst                            # noqa: E402
from pivot_repeatability import atr_series, swings   # noqa: E402

# The shipped bands, in the units the shipped function reports (degrees).
OLD_BANDS = (40.0, 55.0, 80.0)
# THE CONSTANTS THE C CODE CARRIES, kept here so the report cannot drift from the
# shipped bands and start recommending numbers nobody pasted in. `recommend()`
# still computes the quantile mix, but as the REJECTED option: preserving the old
# class mix preserves the old inertia, and 82.7% of legs in the top two bands was
# the whole problem.
SHIPPED_BANDS = (1.00, 1.30, 1.60)
DEFAULT_TFS = (5, 15, 30, 60, 240)


def band_share(values, bands, k):
    """Share of readings landing in class `k` under `bands`."""
    if not values:
        return 0.0
    return sum(1 for x in values if band(x, bands) == k) / len(values)


def old_speed_ratio(dt_min, dp, atr_d1):
    """`CalculateWaveAngle` before the atan, exactly as shipped.

    The pip size cancels - it multiplies the numerator and the denominator - so
    this is price-units in, dimensionless out, which is why the same legs can be
    scored without knowing each symbol's quote convention.
    """
    if dt_min <= 0 or atr_d1 <= 0:
        return 0.0
    return (dp / dt_min) / (atr_d1 / 1440.0)


def old_angle(dt_min, dp, atr_d1):
    """The shipped angle: atan of the ratio above, clamped to 0..90 degrees."""
    return max(0.0, min(90.0, math.degrees(math.atan(old_speed_ratio(dt_min, dp, atr_d1)))))


def new_speed(dt_min, dp, atr_trigger, bar_minutes):
    """The replacement reading: the trigger ATR's own expectation, at sqrt-time.

    `bar_minutes` is the trigger timeframe (Period()), and the elapsed time is
    divided by it under the square root, so the number is the same on every chart.
    """
    if atr_trigger <= 0 or bar_minutes <= 0:
        return 0.0
    bars = max(1.0, dt_min / float(bar_minutes))
    return dp / (atr_trigger * math.sqrt(bars))


def band(value, bands):
    """Class index 0..3 for a reading against three ascending boundaries."""
    if value >= bands[2]:
        return 3
    if value >= bands[1]:
        return 2
    if value >= bands[0]:
        return 1
    return 0


def quantile(values, q):
    """The value at fraction `q`, by nearest rank - small samples here, so no
    interpolation: a boundary read off 300 legs should be one of those legs."""
    v = sorted(values)
    if not v:
        return 0.0
    i = min(len(v) - 1, max(0, int(round(q * (len(v) - 1)))))
    return v[i]


def daily_atr_series(path):
    """ATR(14) per D1 bar, keyed by bar time, so a leg can be scored against the
    volatility that actually surrounded it rather than against today's."""
    bars = hst.load(path)
    atr = atr_series(bars)
    return {b[0]: atr[i] for i, b in enumerate(bars) if atr[i] > 0}, bars


def legs_for(symbol, tf, mult=1.0, min_legs=40):
    """Every zigzag leg on one chart, with both readings attached."""
    cf = hst.find(symbol=symbol, tf=tf)
    df = hst.find(symbol=symbol, tf=1440)
    if not cf or not df:
        return []
    cpath = max(cf, key=os.path.getsize)
    dpath = max(df, key=os.path.getsize)
    bars = hst.load(cpath)
    if len(bars) < 300:
        return []
    atr = atr_series(bars)
    dmap, dbars = daily_atr_series(dpath)
    dtimes = sorted(dmap)
    out = []
    for a, b in zip(swings(bars, atr, mult), swings(bars, atr, mult)[1:]):
        i0, _k0, p0, _c0 = a
        i1, _k1, p1, c1 = b
        if atr[i0] <= 0:
            continue
        dt_min = (bars[i1][0] - bars[i0][0]) / 60.0
        dp = abs(p1 - p0)
        # the D1 bar covering the leg - the volatility that surrounded it
        d_atr = 0.0
        for t in reversed(dtimes):
            if t <= bars[i0][0]:
                d_atr = dmap[t]
                break
        if d_atr <= 0 or dt_min <= 0 or dp <= 0:
            continue
        # THE TWO ABILITIES THE STEP FORMULA CONSUMES, per leg. `TH3SkeletonFromBars`
        # passes atrStructure = the cached DAILY ATR and atrPattern = iATR on the
        # CHART at barB, so the formula's ratio P/S is the chart ATR over the daily
        # ATR - a number that depends on which chart it is, and the reason the step
        # ordering below is not the same on H1 as on W1.
        out.append({
            "t": bars[i1][0], "dt_min": dt_min, "dp": dp,
            "old": old_angle(dt_min, dp, d_atr),
            # THE ATR IS READ AT B, NOT AT A, so these bands belong to the formula
            # the indicator actually runs: `TH3SkeletonFromBars` passes
            # `atrPattern = iATR(NULL, 0, 14, barB)` - the pivot bar. Deriving the
            # constants from the leg's START bar instead is the kind of one-index
            # slip that would leave the shipped bands subtly off the evidence.
            "new": new_speed(dt_min, dp, atr[i1], tf),
            "ps": atr[i1] / d_atr,
            "confirm": c1,
        })
    return out if len(out) >= min_legs else []


def collect(symbols, tfs):
    """Pooled legs, plus a per-(symbol, tf) count so a thin cell stays visible."""
    rows, cells = [], []
    for sym in symbols:
        for tf in tfs:
            got = legs_for(sym, tf)
            cells.append((sym, tf, len(got)))
            rows.extend(got)
    return rows, cells


def step_candidates(S, P):
    """The course's three candidate steps, in price units: (long, med, blend).

    `blend` is the shipped `shortStep = 0.5*(long + med)`. It is NOT the shortest
    of the three - see `step_shipped` - and that is the defect measured below.
    """
    long_ = 3.0 * S - 2.0 * P
    med = 2.0 * S - P
    return long_, med, 0.5 * (long_ + med)


def step_shipped(mom, S, P):
    """`TH3StepFromSkeleton`'s selection, transcribed exactly as shipped."""
    long_, med, blend = step_candidates(S, P)
    if mom >= 2:          # STRONG or EXPLOSIVE
        return long_
    if mom == 1:          # NORMAL
        return med
    return blend          # WEAK


def step_monotone(mom, S, P):
    """The same three candidate VALUES, assigned in ascending order instead.

    No new number is invented here - the set of candidate steps is unchanged. What
    changes is which class gets which: WEAK the smallest, NORMAL the middle,
    STRONG and above the largest. This is what makes a discriminating momentum axis
    mean anything, because the shipped assignment is not monotone at all.
    """
    return sorted(step_candidates(S, P))[min(mom, 2)]


def recommend(rows):
    """The new boundaries at the old boundaries' quantiles, plus the realised mix.

    `share_*` is the class mix this data actually has under each metric. The
    recommendation is only useful if the two mixes match, so both are printed and
    the selftest asserts it rather than trusting the arithmetic.
    """
    if len(rows) < 50:
        return None
    olds = [r["old"] for r in rows]
    news = [r["new"] for r in rows]
    old_q = [sum(1 for x in olds if x >= b) / len(olds) for b in OLD_BANDS]
    new_bands = tuple(round(quantile(news, 1.0 - q), 3) for q in old_q)
    mix_old = [sum(1 for x in olds if band(x, OLD_BANDS) == k) / len(olds) for k in range(4)]
    mix_new = [sum(1 for x in news if band(x, new_bands) == k) / len(news) for k in range(4)]
    return {"n": len(rows), "old_bands": OLD_BANDS, "new_bands": new_bands,
            "mix_old": mix_old, "mix_new": mix_new,
            "old_median": quantile(olds, 0.5), "new_median": quantile(news, 0.5)}


def percentiles(values, qs=(0.05, 0.10, 0.25, 0.50, 0.75, 0.90, 0.95)):
    return [(q, quantile(values, q)) for q in qs]


def step_table(rows, bands):
    """What the axis selects, per class, in DAILY-ATR units (S = 1).

    The step formula needs two abilities and both are in the data: S is the daily
    ATR and P the chart ATR at the pivot bar. Reading the step in S units keeps
    symbols and timeframes comparable, which is the point of measuring the effect
    instead of arguing for it. `blend` and `med` are printed apart so the shipped
    ordering is visible in the table rather than described in a comment.
    """
    per = {}
    for k, name in enumerate(("WEAK", "NORMAL", "STRONG", "EXPLOSIVE")):
        pick = [r for r in rows if band(r["new"], bands) == k]
        if not pick:
            per[name] = None
            continue
        sh = [step_shipped(k, 1.0, r["ps"]) for r in pick]
        mo = [step_monotone(k, 1.0, r["ps"]) for r in pick]
        per[name] = {"share": len(pick) / len(rows), "n": len(pick),
                     "shipped": quantile(sh, 0.5),
                     "monotone": quantile(mo, 0.5)}
    return per


def step_impact(rows, bands_a, mono_a, bands_b, mono_b, label):
    """How many legs get a DIFFERENT step, and which way - the effect on the step.

    Comparing the step VALUES rather than the classes is the point: STRONG and
    EXPLOSIVE both select `long`, so a class relabelling that never reaches the step
    costs nothing, and a one-class shift that does reach it costs everything. Both
    are invisible in a class-mix table.
    """
    pick = step_monotone if mono_b else step_shipped
    pick_a = step_monotone if mono_a else step_shipped
    a = [pick_a(band(r["new"], bands_a), 1.0, r["ps"]) for r in rows]
    b = [pick(band(r["new"], bands_b), 1.0, r["ps"]) for r in rows]
    n = len(a)
    up = sum(1 for x, y in zip(a, b) if y > x + 1e-9)
    down = sum(1 for x, y in zip(a, b) if y < x - 1e-9)
    same = n - up - down
    med_a, med_b = quantile(a, 0.5), quantile(b, 0.5)
    print(f"   {label:<34} changed {1 - same / n:>6.1%}  "
          f"bigger {up / n:>5.1%}  smaller {down / n:>5.1%}  "
          f"median {med_a:.3f} -> {med_b:.3f} S ({med_b / med_a - 1:+.1%})")
    return {"changed": 1 - same / n, "up": up / n, "down": down / n,
            "median_before": med_a, "median_after": med_b}


def print_step_table(rows, bands, label):
    per = step_table(rows, bands)
    print(f"\n  step selected under {label}, in DAILY-ATR units (S = 1):")
    print(f"   {'class':<12} {'share':>7} {'shipped':>9} {'monotone':>9}")
    for name in ("WEAK", "NORMAL", "STRONG", "EXPLOSIVE"):
        d = per[name]
        if d is None:
            print(f"   {name:<12} {'-':>7}")
            continue
        print(f"   {name:<12} {d['share']:>7.1%} {d['shipped']:>9.3f} "
              f"{d['monotone']:>9.3f}")
    w, nm = per["WEAK"], per["NORMAL"]
    if w and nm:
        gap = w["shipped"] - nm["shipped"]
        print(f"   shipped ordering: WEAK {w['shipped']:.3f} vs NORMAL "
              f"{nm['shipped']:.3f}  -> WEAK is {'BIGGER' if gap > 0 else 'smaller'}"
              f" by {abs(gap):.3f} S ({gap / nm['shipped']:+.1%})")
    return per


def report(symbols, tfs, as_json=False, cand_bands=None):
    rows, cells = collect(symbols, tfs)
    print(f"  {len(rows):,} zigzag legs pooled from "
          f"{sum(1 for c in cells if c[2])} series\n")
    for sym, tf, n in cells:
        print(f"   {sym:<8} TF{tf:<6} {n:>5} legs"
              + ("" if n else "   (no legs: file missing or too short)"))
    rec = recommend(rows)
    if rec is None:
        print("\n  not enough legs to recommend bands")
        return None
    bands = tuple(cand_bands) if cand_bands else SHIPPED_BANDS
    news = [r["new"] for r in rows]
    pss = [r["ps"] for r in rows]
    mix_ship = [band_share(news, bands, k) for k in range(4)]

    print(f"\n  old metric (degrees) : median {rec['old_median']:.1f}  "
          f"bands {rec['old_bands']}")
    print(f"  new metric (R)       : median {rec['new_median']:.3f}")
    print(f"\n   {'class':<14} {'old mix':>9} {'quantile':>10} {'SHIPPED':>9}")
    for k, name in enumerate(("WEAK", "NORMAL", "STRONG", "EXPLOSIVE")):
        print(f"   {name:<14} {rec['mix_old'][k]:>9.1%} {rec['mix_new'][k]:>10.1%} "
              f"{mix_ship[k]:>9.1%}")

    print(f"\n  R percentile ladder (a band set is read off this, not invented):")
    print("   " + "  ".join(f"p{int(q * 100)}={v:.2f}" for q, v in percentiles(news)))
    print(f"  P/S (chart ATR / daily ATR): median {quantile(pss, 0.5):.3f}  "
          f"p10 {quantile(pss, 0.10):.3f}  p90 {quantile(pss, 0.90):.3f}")
    print(f"  legs at STRONG or above: quantile mix "
          f"{rec['mix_new'][2] + rec['mix_new'][3]:.1%}   shipped "
          f"{mix_ship[2] + mix_ship[3]:.1%}   <- the axis's inertia")

    # THE STEP, which is what the calibration is actually for.
    print_step_table(rows, rec["new_bands"],
                     f"the quantile mix {rec['new_bands']} (preserves the OLD mix)")
    print_step_table(rows, bands, f"the shipped bands {bands}")
    # THE EFFECT, decomposed: the band change alone, the ordering fix alone, and
    # both together. Reporting only the total would leave the reader unable to tell
    # which of the two did the work.
    print(f"\n  effect on the chosen step, decomposed (each row changes from the row"
          f" above):")
    step_impact(rows, rec["new_bands"], False, bands, False,
                "bands only (bequeathed ordering)")
    step_impact(rows, bands, False, bands, True,
                "ordering fix only (shipped bands)")
    step_impact(rows, rec["new_bands"], False, bands, True, "both together")

    print(f"\n  -> C defines: MOMENTUM_SPEED_BALANCED {bands[0]:.2f}  "
          f"STRONG {bands[1]:.2f}  SPIKE {bands[2]:.2f}")
    if as_json:
        print("\n" + json.dumps(rec))
    return rec


# ---------------------------------------------------------------- selftest ---

def selftest():
    faults = 0

    def check(cond, what):
        nonlocal faults
        if not cond:
            print(f"  SEED NOT CAUGHT: {what}")
            faults += 1

    # The old reading is atan of a ratio, clamped: 45 degrees means speed == ATR
    # per minute exactly, and the clamp must bite at both reported ends.
    check(abs(old_angle(1440.0, 1.0, 1.0) - 45.0) < 1e-9,
          "a leg travelling one daily-ATR per day is not 45 degrees")
    check(old_angle(1.0, 0.0, 1.0) == 0.0, "a zero-length leg is not 0 degrees")
    # NOTE why this is a tolerance and not an equality. The shipped function ends
    # with `if(angle < 0) angle = 0; if(angle > 90) angle = 90;`, and BOTH guards
    # are unreachable: priceChange is MathAbs so the ratio cannot be negative, and
    # atan of a finite positive number is strictly below 90 degrees. The clamp has
    # never fired. Asserted as < 90 so that claim is recorded rather than assumed.
    check(old_angle(1.0, 1e9, 1.0) < 90.0,
          "atan reached 90 degrees, so the shipped clamp is not dead after all")

    # The new reading is the ONE thing the change is for: doubling the duration
    # must halve R, not quarter it (the old linear penalty), because volatility
    # grows with sqrt(time). If this ever passes with 0.25, the sqrt is gone.
    a = new_speed(60.0, 100.0, 10.0, 60)
    b = new_speed(240.0, 100.0, 10.0, 60)
    check(abs(a / b - 2.0) < 1e-9, f"4x the time changed R by {a / b:.3f}x, not 2x")
    # And the reading must not move with the chart, so ONE set of bands serves
    # every timeframe. A 4x finer chart sees 4x the bars and, at sqrt-time scaling,
    # half the ATR - so the ATR passed alongside the bar count has to be that
    # chart's own, which is what the live code does (atrPattern = iATR on the
    # chart). Feeding the same ATR to both was the first version of this seed and
    # it failed for the seed's fault, not the metric's.
    coarse = new_speed(60.0, 100.0, 10.0, 60)
    fine = new_speed(60.0, 100.0, 10.0 / math.sqrt(4.0), 15)
    check(abs(coarse - fine) < 1e-9,
          f"the reading moved with the chart timeframe ({coarse:.4f} vs {fine:.4f}) "
          f"- the bands would need re-tuning per timeframe")

    # A planted leg mix: R halves exactly at the boundary, so banding is pinned.
    bands = (1.0, 2.0, 3.0)
    check(band(0.999, bands) == 0 and band(1.0, bands) == 1,
          "the first boundary is not inclusive on the right side")
    check(band(2.0, bands) == 2 and band(3.0, bands) == 3,
          "an upper boundary is not inclusive")

    # THE STEP ORDERING. Two things have to hold, and the first is the cause of the
    # defect rather than a symptom of it: `blend` is BETWEEN long and med by
    # construction, so ANY assignment that hands the blend to a weaker band than
    # med is non-monotone - and that is exactly what the shipped function did, on
    # every chart with P < S, i.e. every intraday chart.
    lo_, md_, bl_ = step_candidates(1.0, 0.2)
    check(md_ < bl_ < lo_,
          f"blend is not between long and med ({lo_:.3f}, {md_:.3f}, {bl_:.3f}) - "
          f"the ordered assignment may no longer be necessary")
    check(step_shipped(0, 1.0, 0.2) > step_shipped(1, 1.0, 0.2),
          "the shipped WEAK step is not bigger than NORMAL's at P < S, so the "
          "defect this ordering fixes has moved")
    # And the ordered assignment must be monotone across BOTH regimes, because
    # which candidate is largest FLIPS when P passes S. Checking one regime would
    # pass on an implementation that is wrong in the other.
    for ps in (0.2, 1.2):
        seq = [step_monotone(m, 1.0, ps) for m in range(4)]
        check(all(a <= b + 1e-12 for a, b in zip(seq, seq[1:])),
              f"the ordered step is not monotone at P/S={ps}: {seq}")

    # The quantile mapping must preserve the class mix on planted data whose old
    # boundaries are known. Built so the answer is arithmetic, not luck.
    rows = []
    for i in range(400):
        r = 0.02 * (i + 1)
        rows.append({"old": old_angle(60.0, r, 1.0), "new": r})
    rec = recommend(rows)
    check(rec is not None, "400 planted rows produced no recommendation")
    if rec:
        drift = max(abs(x - y) for x, y in zip(rec["mix_old"], rec["mix_new"]))
        check(drift <= 0.03,
              f"the new bands moved the class mix by {drift:.1%} on planted data")

    print(f"  selftest: {faults} uncaught seed(s)")
    return faults


def main(argv):
    try:
        sys.stdout.reconfigure(encoding="utf-8", errors="replace")
    except Exception:
        pass
    if "--selftest" in argv:
        return 1 if selftest() else 0
    syms = (argv[argv.index("--symbols") + 1] if "--symbols" in argv
            else "XAUUSD,EURUSD,GBPUSD").split(",")
    tfs = ([int(x) for x in argv[argv.index("--tf") + 1].split(",")]
           if "--tf" in argv else list(DEFAULT_TFS))
    cand = ([float(x) for x in argv[argv.index("--bands") + 1].split(",")]
            if "--bands" in argv else None)
    return 0 if report([s.strip() for s in syms], tfs,
                       as_json="--json" in argv, cand_bands=cand) else 1


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
