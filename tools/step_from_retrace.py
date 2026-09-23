#!/usr/bin/env python3
"""step_from_retrace — the movement step, read from the market's own retracements.

THE PROBLEM WITH THE PREVIOUS TOOL
    `pivot_repeatability.py --ladder` builds its ladder from `step = ATR/div`,
    with `div` swept over seven values. That is a RULER: a step declared from
    outside the market and then drawn onto it. Sweeping seven of them and keeping
    the best is the shape of a search that manufactures a winner, and the honest
    control there (a random step per pivot) showed the rung-3-and-5 bump was
    mostly the geometry of nested rungs, not the step.

THE CLAIM THIS TOOL TESTS, AS THE USER STATED IT
    1. A move is 3 steps or 5 steps - nothing else - and then the same structure
       repeats one timeframe up (self-similar).
    2. Retracements land on 1 step, 2/3 step or 1/3 step, and beyond one step
       they keep the same thirds (4/3, 5/3, ...). So the true quantum is
       step/3, and the retracement route to the step is APPROXIMATE - it gives a
       range, not an exact number.
    3. Price reacts at rung 3 and rung 5 of the ladder projected from a pivot,
       and at rung 3 the reaction is worth one step or 2/3 of one.
    4. The reaction sits in a zone as wide as the trigger timeframe's ability.
    5. If rungs 3 and 5 do not react, the step was read wrong. Stated as a
       falsifier, so it is used as one.

WHY THE OBVIOUS IMPLEMENTATION IS WRONG
    The first version of this file voted on the step directly: every leg proposed
    `size/3` and `size/5` and the densest cluster won. Two selftest seeds killed
    it, and both were right to:

      * Planted legs whose lengths were exactly 3S and 5S scored only 36% as
        "3S or 5S" - because a leg is BOTH an impulse and, on the next pivot, a
        retracement, and only the impulse half was being counted.
      * Pure noise scored 59% - because the consensus is chosen to be the densest
        window, so the legs it explains best are selected BY that choice. A
        statistic that scores itself is not evidence.

    So the measurement was moved to a quantity nothing is fitted to: the RATIO
    of a retracement to the impulse it corrects, `r = retrace / impulse`. This is
    step-free. If the impulse is 3S and the retracement is k/3*S then r = k/9; if
    the impulse is 5S then r = k/15. Every ratio therefore lands on one of two
    grids, and the two grids are FINITE and different:

        impulse 3 steps -> r in {1/9, 2/9, 3/9, 4/9, 5/9, ...}
        impulse 5 steps -> r in {1/15, 2/15, 3/15, 4/15, 5/15, ...}

    Two payoffs the direct estimator could not give:

      * The grid a ratio lands on REVEALS whether the impulse was 3 or 5 steps -
        which is the disambiguation the user asked for, and it is read off the
        market rather than assumed.
      * With the class known, the step is `impulse/3` or `impulse/5` PER PATTERN,
        so no global step is ever fitted. The consistency check that follows is
        the strongest thing here: if the market has a step, then the step
        recovered from the 3-step patterns and the step recovered from the
        5-step patterns must be the SAME NUMBER. That comparison is not
        self-selecting - the two groups are separated by the grid, not by the
        step - and it can fail loudly.

WHAT IS NOT BEING CLAIMED
    `r` is measured between ATR-zigzag pivots, which is a 1-ATR reversal filter,
    not the course's six-condition pivot. A retracement smaller than about 1 ATR
    is never seen at all, so the k=1 and k=2 slots of the 3-grid are structurally
    under-represented and their share below is a FLOOR, not a rate. The gridded
    share is reported against its analytic chance level (30% for a 0.15 grid-index
    tolerance) so it can be judged at all.

MEASURING THE PIVOTS ON THE TRIGGER TIMEFRAME
    Requested as a way to close the error budget, and it is answered by
    measurement rather than argument. `measurement_map` / `extreme_identity` show
    that a coarser bar's high and low ARE the extremes of the finer bars inside it
    (measured at 1772 of 1773 on EURUSD H1-on-M15, 876 of 877 on gold), so a finer
    clock restates a pivot's clock and cannot sharpen its PRICE - and the selftest
    pins that the measured ratios come out identical. What a finer clock CAN do is
    restate the price differently ('settled' = the last finer bar's close), and
    that variant is measured too and is worse in all 18 pairings tested.

    So the sweep below prints cell error under TWO noise models, and decides the
    verdict on the PERMISSIVE one (the wick). If a null were judged on the
    conservative model it could always be blamed on the ruler; judging it on the
    wick model gives the grid its best possible chance, so wherever the output
    reads "READABLE" the absence of the grid is a fact rather than a power
    problem.

Usage:  python tools/step_from_retrace.py --selftest
        python tools/step_from_retrace.py --symbols XAUUSD,EURUSD,GBPUSD
        python tools/step_from_retrace.py --symbols XAUUSD --structure 1440 --trigger 240
        python tools/step_from_retrace.py --symbols XAUUSD --structure 60 --measure-tf 15
        python tools/step_from_retrace.py --sweep-measure
        python tools/step_from_retrace.py --sweep-pivot --structure 240
        python tools/step_from_retrace.py --rung-band --structure 240 --trigger 60 --zone 0,1,2
        python tools/step_from_retrace.py --rung-band --structure 60 --trigger 15 --thr 2,3
"""
import bisect
import json
import os
import random
import statistics
import sys
from datetime import datetime, timezone

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import mt4_history as hst                            # noqa: E402
from pivot_repeatability import atr_series, features, swings   # noqa: E402

GRID_TOL = 0.15        # |r*n - round(r*n)| <= tol, i.e. within 15% of a grid line
CHANCE = 2 * GRID_TOL  # the rate the same test scores on an ungridded ratio


# --------------------------------------------------------------- primitives ---

def stamp(t):
    """The broker's own bar clock, exactly as it sits in the .hst record."""
    return datetime.fromtimestamp(t, timezone.utc).strftime("%Y-%m-%d %H:%M")


def swing_pivots(bars, atr, mult=1.0):
    """The shipped detector: a 1-ATR zigzag. See `course_pivots` for the other."""
    return swings(bars, atr, mult)


def course_pivots(bars, atr, confirm_atr=0.25, min_run_bars=2,
                  require_anatomy=True):
    """The course's OWN pivot, read as a detector - ONE dial, stated plainly.

    WHY THIS EXISTS. The zigzag confirms a swing only after price retreats a full
    ATR. That single constant is a CENSOR on the retracement: if the market turns
    back by less than one ATR, no pivot is ever declared, the two legs merge into
    one, and the retracement simply is not in the data. Every k=1 and k=2 slot of
    the 3-grid is therefore structurally missing from the zigzag's sample - which
    is exactly the retracement the user says the method should be reading.

    The course's pivot is not defined that way. Its six conditions are about the
    CANDLE and the move into it, so a pivot is knowable at a bar's close with only
    a candle-sized reversal after it:

      1 side/range candles before the move        features(): side_bars
      2 a directional run, and how far it went     run_bars / run_ext
      3 the pivot candle reverses >= 1 ATR          rev_atr
      4 master candle (body or shadow >= 0.8)       master
      5 how many older candles it engulfs           engulf_n
      6 where the close sits in its own range       close_pos

    `confirm_atr` is the dial that matters here and it is deliberately the ONE free
    parameter, because it is the censoring device being tested. It is swept rather
    than chosen. The anatomy gate reuses `pivot_repeatability.features()` - the
    repo's existing encoder for those six conditions - instead of re-deriving them
    here, so there is still one owner for what the conditions mean. Which of the
    six gate a pivot, and at what numeric threshold, IS my choice and is named in
    `course_anatomy_ok` - the course gives prose, not numbers.

    Returns the same shape as `swings()`: (idx, 'H'|'L', price, confirm_idx), so
    every downstream measurement works unchanged.
    """
    out = []
    n = len(bars)
    if n < 3:
        return out
    up = None
    ext_i, ext_p = 0, bars[0][4]
    for i in range(1, n):
        a = atr[i]
        if a <= 0:
            continue
        h, l = bars[i][2], bars[i][3]
        if up is None:
            if h > ext_p:
                ext_i, ext_p, up = i, h, True
            elif l < ext_p:
                ext_i, ext_p, up = i, l, False
            continue
        if up:
            if h > ext_p:
                ext_i, ext_p = i, h
            elif ext_p - l >= confirm_atr * a:
                if not require_anatomy or course_anatomy_ok(bars, atr, ext_i, "H",
                                                            min_run_bars):
                    out.append((ext_i, "H", ext_p, i))
                up, ext_i, ext_p = False, i, l
        else:
            if l < ext_p:
                ext_i, ext_p = i, l
            elif h - ext_p >= confirm_atr * a:
                if not require_anatomy or course_anatomy_ok(bars, atr, ext_i, "L",
                                                            min_run_bars):
                    out.append((ext_i, "L", ext_p, i))
                up, ext_i, ext_p = True, i, h
    return out


def course_anatomy_ok(bars, atr, idx, kind, min_run_bars=2):
    """Which of the six conditions gate a pivot here, and why.

    GATING: condition 2 (there is a movement into the pivot - `run_bars` and a
    directional close), condition 6 (the close sits on the pivot's side), and
    condition 4 OR 5 (a master candle, or one that engulfs an older one).

    NOT GATING, and this is a deliberate gap worth stating: condition 1
    (`side_bars`) and condition 3 (`rev_atr`, the pivot candle's range >= 1 ATR).
    They are measured and reported, but gating on condition 3 would re-impose a
    1-ATR CANDLE requirement and so re-introduce half of the censoring this
    detector exists to remove; and gating on condition 1 as well drops the sample
    far enough that the grid test loses its power on these histories. Both
    remain one flag away - they are not forgotten, they are measured.
    """
    f = features(bars, atr, idx, kind)
    if f is None:
        return False
    if f["run_bars"] < min_run_bars:
        return False
    if f["close_pos"] < 0.5:
        return False
    return f["master"] == 1 or f["engulf_n"] >= 1


def pivot_legs(bars, atr, mult=1.0, price_fn=None, pivots=None):
    """Consecutive confirmed pivots as legs, carrying their confirmation bar.

    `confirm` travels with every leg because everything downstream searches
    forward from it, never from the extreme - the look-ahead trap
    `pivot_repeatability.swings` exists to expose.

    `price_fn(idx, kind, price)` re-states a pivot's price on another clock. It is
    how the "measure the pivot on the trigger timeframe" request is expressed: the
    pivot TIMES and the leg boundaries stay the structure's, only the prices move.

    `pivots` swaps the detector: omit it for the shipped 1-ATR zigzag, or pass
    `course_pivots(...)` for the course's own. Nothing else in the pipeline knows
    which one it was handed.
    """
    sw = swing_pivots(bars, atr, mult) if pivots is None else pivots
    out = []

    def px(idx, kind, price):
        return price_fn(idx, kind, price) if price_fn is not None else price

    for a, b in zip(sw, sw[1:]):
        i0, k0, p0, _c0 = a
        i1, k1, p1, c1 = b
        a0, a1 = px(i0, k0, p0), px(i1, k1, p1)
        size = abs(a1 - a0)
        if size <= 0 or atr[i0] <= 0:
            continue
        out.append({
            "from_idx": i0, "to_idx": i1, "kind": k0,   # k0 is the pivot departed FROM
            "price0": a0, "price1": a1, "raw0": p0, "raw1": p1,
            "size": size, "atr": atr[i0],
            "atr_units": size / atr[i0], "confirm": c1,
            "time0": bars[i0][0], "time1": bars[i1][0],
        })
    return out


def patterns(legs, tol=GRID_TOL):
    """Each pivot as impulse-then-retracement, with the grid reading of its ratio.

    r = retrace / impulse is the whole measurement. `e3` and `e5` are the
    distances to the 3-step grid (k/9) and the 5-step grid (k/15), in grid cells,
    so 0 is exactly on a line and 0.5 is exactly between two. Only ratios that
    are genuinely retracements (r < 1) are kept: a move bigger than the one it
    corrects is not a correction.

    THE AMBIGUOUS CELLS, which are not a bug. Exactly two ratios sit on BOTH
    grids - 1/3 and 2/3, since k/15 = j/9 forces k = 5j/3 and so j in {3, 6}. And
    they are not rare: r = 1/3 is the course's own one-full-step retracement on a
    3-step impulse, and r = 2/3 also arrives whenever a five-step impulse is
    corrected by five-thirds of a step. The market does not know which grid it is
    on, so neither does this tool: those patterns are classed `ambiguous` and
    excluded from every step claim rather than being pushed onto the nearer line.
    The first version did push them, which is why the 3-class step came out 4.12
    instead of the planted 3.00 - a five-step impulse divided by three.
    """
    out = []
    for a, b in zip(legs, legs[1:]):
        imp, ret = a, b
        if imp["size"] <= 0 or ret["size"] <= 0:
            continue
        r = ret["size"] / imp["size"]
        if r >= 1.0:
            continue
        e3 = abs(r * 9.0 - round(r * 9.0))
        e5 = abs(r * 15.0 - round(r * 15.0))
        # The SHIFTED grid, half a cell off, is the distribution-free control: it
        # sits the same distance from the data as the real one, so any advantage
        # the real grid shows cannot come from ratios simply being clumped.
        s3 = abs(r * 9.0 - 0.5 - round(r * 9.0 - 0.5))
        s5 = abs(r * 15.0 - 0.5 - round(r * 15.0 - 0.5))
        on3, on5 = e3 <= tol, e5 <= tol
        if on3 and on5:
            klass, cells = 0, 0                      # 1/3 and 2/3 live here
        elif on3:
            klass, cells = 3, 9
        elif on5:
            klass, cells = 5, 15
        else:
            klass, cells = -1, 9                     # off both grids
        out.append({
            "impulse": imp["size"], "retrace": ret["size"], "r": r,
            "e3": e3, "e5": e5, "class": klass,
            "on_grid": klass in (3, 5), "ambiguous": klass == 0,
            "on_true": min(e3, e5) <= tol, "on_shift": min(s3, s5) <= tol,
            "steps": (round(r * cells) if cells else 0),
            "step": (imp["size"] / klass) if klass in (3, 5) else 0.0,
            "kind": imp["kind"], "confirm": imp["confirm"],
            "pivot": imp["price1"], "atr": imp["atr"],
            "time": imp["time1"],
            # THE IMPULSE'S START, which `pivot` and `time` above do not describe:
            # both of those are its END. Anything asking about WHERE the leg begins
            # - as opposed to where it finishes - needs these two, and reconstructing
            # them outside by re-pairing the legs goes wrong the moment `r >= 1`
            # skips a pair.
            "start_price": imp["price0"], "start_time": imp["time0"],
            "start_idx": imp["from_idx"],
        })
    return out


def noise_budget(impulse_median, bar_noise, tol=GRID_TOL, cells=9.0):
    """Can the thirds grid be read at all at this step size?

    Each pivot's price is a bar extreme, so it carries roughly half a bar range
    of error, and a ratio of two such prices carries sqrt(2) of it. In grid cells
    of the 3-grid that error is `9 * sqrt(2) * (bar_noise/2) / impulse`.

    This is not a footnote - it is the reason the retracement route is
    APPROXIMATE, which the user said from the start. With the course's own trigger
    ability (a step of about a quarter ATR) an impulse is under one ATR and the
    cell error is many times the whole grid, so no average of ratios can rescue
    it; the grid becomes readable only once a step is a few ATR wide. Reporting
    the budget makes that boundary visible instead of hiding it behind a rate.
    """
    if impulse_median <= 0:
        return {"cell_error": 99.0, "resolvable": False}
    err = cells * 1.41421356 * (bar_noise / 2.0) / impulse_median
    return {"cell_error": err, "resolvable": err <= tol}


def grid_stats(pats, tol=GRID_TOL, budget=None):
    """How much of the market sits on the two ratio grids, versus both nulls.

    `any` counts only patterns on exactly ONE grid, because the two ambiguous
    ratios are on both and cannot be evidence for either. Two floors to read every
    rate against: `chance`, what an ungridded ratio scores at this tolerance, and
    `shifted`, the same data scored on a grid moved half a cell - which is immune
    to the ratios merely clumping. The honest statistic is `true - shifted`.
    """
    n = len(pats)
    if not n:
        return {"n": 0, "grid3": 0.0, "grid5": 0.0, "any": 0.0, "true": 0.0,
                "shifted": 0.0, "advantage": 0.0, "ambiguous": 0.0,
                "chance": CHANCE, "budget": budget or {}}
    true = sum(1 for p in pats if p["on_true"]) / n
    shifted = sum(1 for p in pats if p["on_shift"]) / n
    return {
        "n": n,
        "grid3": sum(1 for p in pats if p["class"] == 3) / n,
        "grid5": sum(1 for p in pats if p["class"] == 5) / n,
        "any": sum(1 for p in pats if p["on_grid"]) / n,
        "true": true, "shifted": shifted, "advantage": true - shifted,
        "ambiguous": sum(1 for p in pats if p["ambiguous"]) / n,
        "chance": CHANCE,
        "budget": budget or {},
    }


def class_consistency_null(pats, trials=200, seed=20260919, bands=(0.8, 1.25)):
    """How often does a RANDOM 3/5 labelling agree by chance?

    This exists because agreement alone is not evidence. `class_consistency`
    returns a ratio, and a ratio can fall in the agreeing band while the labels
    that produced it carry no information at all - gold's H1-on-M15 run reported
    0.86x, inside the band, on a grid `noise_budget` had already called unreadable.

    So the labels are shuffled while the steps they imply are recomputed, keeping
    the group sizes and the impulse distribution exactly as measured. The output is
    the share of shuffles that would have "passed". If a real result does not beat
    that share, it is a coin that landed well.
    """
    pool = [p for p in pats if p["on_grid"] and p["step"] > 0]
    n3 = sum(1 for p in pool if p["class"] == 3)
    if len(pool) < 16 or n3 < 8 or len(pool) - n3 < 8:
        return None
    rng = random.Random(seed)
    hits = 0
    for _ in range(trials):
        idx = list(range(len(pool)))
        rng.shuffle(idx)
        g3 = [pool[i]["impulse"] / 3.0 for i in idx[:n3]]
        g5 = [pool[i]["impulse"] / 5.0 for i in idx[n3:]]
        ratio = statistics.median(g5) / statistics.median(g3)
        hits += 1 if bands[0] <= ratio <= bands[1] else 0
    return hits / trials


def class_consistency(pats):
    """THE strong check: do the 3-class and 5-class patterns agree on one step?

    The two groups are separated by the ratio grid, which is measured
    independently of any step, so this is not the fit grading itself. If the
    market steps, the step from one group must match the step from the other. If
    they disagree - a factor of 5/3 apart, say - then "the step" is an artifact of
    grouping and the claim fails here.
    """
    p3 = [p["step"] for p in pats if p["class"] == 3 and p["on_grid"]]
    p5 = [p["step"] for p in pats if p["class"] == 5 and p["on_grid"]]
    if len(p3) < 8 or len(p5) < 8:
        return {"enough": False, "n3": len(p3), "n5": len(p5)}
    m3, m5 = statistics.median(p3), statistics.median(p5)
    return {"enough": True, "n3": len(p3), "n5": len(p5), "step3": m3, "step5": m5,
            "ratio": m5 / m3 if m3 > 0 else 0.0}


def censoring(pats):
    """How many of the retracements are shorter than ONE ATR.

    This is the measurement of the user's complaint, and it is a FLOOR for the
    zigzag rather than a rate: a zigzag cannot declare a pivot until price
    retreats a full ATR, so a retracement below 1 ATR is not "rare" in its sample,
    it is UNREPRESENTABLE - the two legs merge and the retracement never exists as
    a data point. If the course detector's share here is materially above zero,
    the censoring was real and the finer pivot recovers it.
    """
    n = len(pats)
    if not n:
        return {"n": 0, "below_1atr": 0.0, "median_ret_atr": 0.0, "min_ret_atr": 0.0}
    ratios = [p["retrace"] / p["atr"] for p in pats if p["atr"] > 0]
    if not ratios:
        return {"n": n, "below_1atr": 0.0, "median_ret_atr": 0.0, "min_ret_atr": 0.0}
    return {"n": n,
            "below_1atr": sum(1 for x in ratios if x < 1.0) / len(ratios),
            "median_ret_atr": statistics.median(ratios),
            "min_ret_atr": min(ratios)}


def detector_row(bars, atr, pivots, label):
    """One detector's full reading on one series, for the comparison table."""
    legs = pivot_legs(bars, atr, pivots=pivots)
    pats = patterns(legs)
    if len(pats) < 40:
        return {"label": label, "patterns": len(pats), "thin": True}
    bud = noise_budget(median_impulse(pats), bar_noise(bars))
    bud_w = noise_budget(median_impulse(pats), wick_noise(bars))
    cons = class_consistency(pats)
    return {"label": label, "patterns": len(pats), "thin": False,
            "legs": len(legs), "cens": censoring(pats),
            "grid": grid_stats(pats, budget=bud), "budget": bud,
            "budget_wick": bud_w, "consistency": cons,
            "null": class_consistency_null(pats)}


def show_rung_band(symbols, structure=60, trigger=15, zones=(0.0, 1.0),
                   horizon=24, bounce_bars=6, course=False, confirm_atr=0.25,
                   thresholds=(2 / 3.0, 1.0, 1.5, 2.0, 3.0)):
    """Point rung vs band rung, and whether 3 and 5 separate from their neighbours.

    THE QUESTION, exactly: with the rung treated as a band as wide as the trigger
    timeframe's own ATR, do rungs 3 and 5 stand out from rungs 1, 2, 4, 6, 7, 8?

    THREE TRAPS, reported rather than fallen into.

    1. Bands are wider than points, so a band test ALWAYS shows higher touch rates.
       That is arithmetic and means nothing. The SHUFFLED arm is therefore carried
       at every zone width, because the earlier tool showed the raw rung-3-and-5
       bump is geometry, not the step.

    2. THE THRESHOLD HAS TO BE SWEPT. At 2/3 of a step the shuffled arm already
       reacts 98% of the time - a criterion a rerolled ruler passes cannot separate
       anything, and reporting that single threshold would have printed "no
       separation" for a reason that is about the ruler, not about the market. Each
       threshold now carries its own `discriminating` flag.

    3. THE SAMPLE IS THE SPAN THE TRIGGER FILE COVERS. This is not a detail: a
       trigger file holds only the recent tail of the structure history (measured
       on these three symbols: 26-31% of the H1 bars), and `trigger_zone_fn`
       returns 0.0 outside that span. The first version did not restrict the sample,
       so 70%+ of patterns were walked with zone 0 - the median zone printed 0.00
       and the "band" row was the point row wearing a label. Both arms now run on
       the covered span only, and the covered share is printed so the cut is
       visible rather than implied.

    And `zone/step` is printed throughout, because once the band is as wide as the
    rung spacing the bands OVERLAP: rung 3 and rung 4 are then literally the same
    price, and "does 3 stand out from 4" stops being a question about the market.
    """
    print(f"\n  rung as a point vs rung as a band (zone = trigger TF{trigger} ATR), "
          f"structure TF{structure}")
    for sym in symbols:
        files = hst.find(symbol=sym, tf=structure)
        if not files:
            print(f"  {sym}: no TF{structure} file")
            continue
        bars = hst.load(max(files, key=os.path.getsize))
        if len(bars) < 400:
            print(f"  {sym}: only {len(bars)} bars")
            continue
        atr = atr_series(bars)
        piv = course_pivots(bars, atr, confirm_atr) if course else None
        pats = patterns(pivot_legs(bars, atr, pivots=piv))
        zf = trigger_zone_fn(sym, trigger)
        t0 = trigger_span(sym, trigger)
        if zf is None or t0 is None:
            print(f"  {sym}: no usable TF{trigger} series - a band needs one")
            continue
        n_all = len(pats)
        pats = [p for p in pats if p["time"] >= t0]
        if len(pats) < 40:
            print(f"  {sym}: only {len(pats)} of {n_all} patterns fall inside the "
                  f"TF{trigger} span - too few for a per-rung table")
            continue
        steps = sorted(p["step"] for p in pats if p["step"] > 0)
        med_step = steps[len(steps) // 2] if steps else 0.0
        print(f"\n  --- {sym}  {len(pats)} of {n_all} patterns fall inside the "
              f"TF{trigger} span  median step {med_step:.5f} ---")
        for mult in zones:
            zone_of = None
            if mult > 0:
                zone_of = (lambda p, m=mult, f=zf: m * f(p["time"]))
            zones_seen = [zone_of(p) for p in pats] if zone_of else [0.0] * len(pats)
            zs = sorted(zones_seen)
            med_zone = zs[len(zs) // 2]
            covered = sum(1 for z in zones_seen if z > 0) / len(zones_seen)
            ratio = (med_zone / med_step) if med_step > 0 else 0.0
            note = ("bands OVERLAP - adjacent rungs are the same price"
                    if ratio >= 1.0 else "bands separate")
            tag = "POINT" if not zone_of else f"BAND (zone={mult:g}x trigger ATR)"
            print(f"\n   rung as {tag}   median zone {med_zone:.5f} = {ratio:.2f} x the"
                  f" rung spacing -> {note}")
            if zone_of:
                print(f"   trigger-ATR coverage of this sample: {covered:.0%}")
            real = ladder_test(bars, pats, horizon=horizon, bounce_bars=bounce_bars,
                               thresholds=thresholds, zone_of=zone_of)
            shuf = ladder_test(bars, pats, horizon=horizon, bounce_bars=bounce_bars,
                               thresholds=thresholds, rng=random.Random(20260919),
                               zone_of=zone_of)
            show_ladder(real, shuf, (thresholds[0],), summary=False)
            print(f"   {'thr':>5} {'3+5':>9} {'others':>9} {'shuf3+5':>9} {'shufoth':>9}"
                  f" {'EXCESS':>9}   discriminating")
            best, best_thr, shown = -9.0, None, 0
            for thr in thresholds:
                e = ladder_excess(real, shuf, thr)
                if e is None:
                    continue
                shown += 1
                print(f"   {thr:>5.2f} {e['hot']:>9.2%} {e['rest']:>9.2%}"
                      f" {e['shuf_hot']:>9.2%} {e['shuf_rest']:>9.2%}"
                      f" {e['excess']:>+9.2%}   "
                      + ("yes" if e["usable"] else "NO - control already reacts"))
                if e["usable"] and e["excess"] > best:
                    best, best_thr = e["excess"], thr
            if not shown:
                # An empty table is not a null result, and it must not read like
                # one: rungs below 25 touches are dropped, so "no rows" means this
                # symbol is too thin to say anything either way.
                print(f"   NO ROWS: no rung reached 25 touches in this sample - "
                      f"this symbol cannot be judged at any threshold")
                continue
            if best_thr is None:
                print(f"   verdict: every threshold sits inside the shuffled arm's *own*"
                      f" reaction rate - this sample cannot discriminate at any of them")
                continue
            # THE BEST ROW IS NOT A RESULT UNTIL THE NULL IS ASKED THE SAME QUESTION.
            nul = ladder_null(bars, pats, best_thr, zone_of, horizon, bounce_bars)
            if nul is None:
                print(f"   verdict: best rung-3/5 excess {best:+.2%} at threshold "
                      f"{best_thr:.2f} - null too thin to calibrate")
                continue
            p = sum(1 for x in nul["bests"] if x >= best) / len(nul["bests"])
            print(f"   verdict: best rung-3/5 excess {best:+.2%} at threshold "
                  f"{best_thr:.2f}, but two rerolled rulers - neither of which knows "
                  f"the step - produce a best-of-20 of {nul['best_median']:+.2%} "
                  f"typically ({nul['best_p90']:+.2%} at the 90th pct) "
                  f"-> p = {p:.2f} "
                  f"({'STANDS OUT' if p < 0.05 else 'no separation'})")


def show_pivot_sweep(symbols, tf=60, confirms=(0.15, 0.25, 0.5, 1.0)):
    """Zigzag vs the course's six-condition pivot, across the censoring dial.

    `confirm_atr` IS the censoring device, so it is swept rather than chosen: the
    zigzag's row (1.0 ATR) is the shipped behaviour and the finer rows show what
    the 1-ATR rule was hiding. If the grid is real, releasing the censor should
    move the on-grid share - and if it does not, the censoring was not the reason
    the grid was missing.
    """
    print(f"\n  zigzag (1-ATR confirmation) vs the course's six-condition pivot, TF{tf}")
    print(f"  {'sym':<8} {'detector':<26} {'legs':>6} {'patt':>6} "
          f"{'ret<1ATR':>9} {'minRet':>7} {'cellW':>6} {'gridAdv':>8} {'3-vs-5':>7}  verdict")
    best = None
    for sym in symbols:
        files = hst.find(symbol=sym, tf=tf)
        if not files:
            print(f"  {sym:<8} no TF{tf} file")
            continue
        bars = hst.load(max(files, key=os.path.getsize))
        if len(bars) < 400:
            print(f"  {sym:<8} only {len(bars)} bars")
            continue
        atr = atr_series(bars)
        rows = [detector_row(bars, atr, swing_pivots(bars, atr), "zigzag 1.00 ATR")]
        # THE GATE AND THE CENSOR ARE DIFFERENT THINGS, so they are separated.
        # `ungated` keeps the candle-sized confirmation and drops the six-condition
        # anatomy gate; `course` keeps both. Without this row the sample collapse
        # from 1759 legs to 154 has two candidate causes and no way to tell which -
        # and the wrong conclusion ("the 1-ATR rule was the bottleneck") is the
        # tempting one, since the dial looked like the whole point.
        rows += [detector_row(bars, atr,
                              course_pivots(bars, atr, c, require_anatomy=False),
                              f"fine zigzag, confirm {c:.2f}") for c in confirms[:1]]
        rows += [detector_row(bars, atr, course_pivots(bars, atr, c),
                              f"course 6-cond, confirm {c:.2f}") for c in confirms]
        for r in rows:
            if r["thin"]:
                print(f"  {sym:<8} {r['label']:<26} {'':>6} {r['patterns']:>6}  "
                      f"too few patterns to read")
                continue
            c, g, nl = r["consistency"], r["grid"], r["null"]
            ratio = c["ratio"] if c.get("enough") else float("nan")
            bw = r["budget_wick"]
            ok = (bool(c.get("enough")) and 0.8 <= ratio <= 1.25
                  and nl is not None and nl < 0.05 and bw["resolvable"])
            if ok and best is None:
                best = (sym, r["label"])
            verdict = ("PASS both checks" if ok else
                       f"UNREADABLE even on wick ({bw['cell_error'] / GRID_TOL:.0f}x)"
                       if not bw["resolvable"] else
                       "no step agreed" if not c.get("enough") else
                       f"chance agreement p={nl:.2f}" if (nl is None or nl >= 0.05)
                       else f"READABLE, classes disagree {ratio:.2f}x")
            print(f"  {sym:<8} {r['label']:<26} {r['legs']:>6} {r['patterns']:>6} "
                  f"{r['cens']['below_1atr']:>9.1%} {r['cens']['min_ret_atr']:>7.2f} "
                  f"{bw['cell_error']:>6.2f} {g['advantage']:>+8.1%} {ratio:>7.2f}  {verdict}")
    print(f"\n  first detector passing BOTH checks: "
          + (f"{best[0]} - {best[1]}" if best else "none"))
    return best


# -------------------------------------------------------------- the ladder ---

def rung_touch(bars, start, kind, price, S, rung, horizon, bounce_bars, zone=0.0):
    """Touch of rung `rung`, and the counter-move that follows, in STEP units.

    THE ZONE. A rung is not a point: the user's rule is that the reaction occupies
    a band as wide as the trigger timeframe's own ATR, so the rung is tested as
    [level - zone/2, level + zone/2]. Price reaches it when its extreme ENTERS that
    band, not only when it prints the exact level.

    THE TRAP, AND TWO WRONG WAYS TO FIX IT - both of which were tried here.

    1. IF THE BOUNCE IS MEASURED FROM `lvl`, the band pays for itself outright: on a
       down-move the near edge sits `zone/2` ABOVE the level, so a touch already
       hands the measurement a free `zone/2`, and every rung "reacts" as soon as
       zone/2 clears the threshold. Rejected immediately.

    2. IF THE PENETRATION IS CLAMPED TO THE BAND'S FAR EDGE, the band pays for
       itself in the other direction, which is much easier to miss: a deeper floor
       means `pen` is LOWER, and a lower reference makes `pen -> after` LARGER. A
       wider zone would hand out a bigger bounce and the tables would inflate in
       the exact direction that looks like a discovery. This is why the clamp is
       gone, and why the selftest now asserts that `pen` is always a price the
       market actually printed.

    So the bounce is measured from the REAL deepest penetration after the touch.
    That leaves a mechanical effect that is NOT removable here: a wider band is
    touched earlier, so the penetration window opens earlier and can reach deeper.
    It is not hidden - it is cancelled by the only honest control available, which
    is that the SHUFFLED arm runs at the SAME zone widths. The excess between the
    arms therefore carries the zone's effect on both sides, and `zone/step` is
    printed separately because once the band is as wide as the rung spacing the
    bands overlap and the rung index stops meaning anything at all.

    With zone == 0 the TOUCH condition is the shipped point test exactly. The
    bounce is stricter than the shipped one by design: the original took the best
    high anywhere in the window, including before the deepest low, which counts the
    wick price arrived on as if it were the reaction. It is also measured from the
    bar AFTER the penetration, never including the penetration bar itself: the low
    of that bar and its high cannot be ordered from OHLC, and taking its high reads
    the bar's own range as a reaction. A one-way decline is the witness - with the
    penetration bar included it "bounces" a full 0.7 step on every rung.
    """
    down = (kind == "H")
    lvl = price - rung * S if down else price + rung * S
    if lvl <= 0:
        return None
    near = lvl + zone / 2.0 if down else lvl - zone / 2.0
    end = min(len(bars), start + 1 + horizon)
    hit = None
    for i in range(start + 1, end):
        if (down and bars[i][3] <= near) or ((not down) and bars[i][2] >= near):
            hit = i
            break
    if hit is None:
        return None
    stop = min(len(bars), hit + 1 + bounce_bars)
    if down:
        j = min(range(hit, stop), key=lambda i: bars[i][3])
        pen = bars[j][3]                    # a price the market actually printed
        stop2 = min(len(bars), j + 1 + bounce_bars)
        after = max((bars[i][2] for i in range(j + 1, stop2)), default=pen)
        bounce = (after - pen) / S
    else:
        j = max(range(hit, stop), key=lambda i: bars[i][2])
        pen = bars[j][2]
        stop2 = min(len(bars), j + 1 + bounce_bars)
        after = min((bars[i][3] for i in range(j + 1, stop2)), default=pen)
        bounce = (pen - after) / S
    return {"hit": hit, "lvl": lvl, "bounce": bounce, "zone": zone,
            "pen": pen, "pen_i": j}


def trigger_zone_fn(symbol, tf):
    """t -> the trigger timeframe's ATR at time t. The file is read ONCE.

    A closure rather than a per-call lookup because the ladder walks thousands of
    rungs; re-reading a .hst inside that loop is the difference between a report
    and a coffee break. Returns None when the trigger series is unusable, so
    callers fall back to the point test instead of silently getting zone 0.
    """
    files = hst.find(symbol=symbol, tf=tf)
    if not files:
        return None
    bars = hst.load(max(files, key=os.path.getsize))
    if len(bars) < 100:
        return None
    atr = atr_series(bars)
    times = [b[0] for b in bars]

    def f(t):
        i = bisect.bisect_right(times, t) - 1
        if i < 0 or i >= len(atr):
            return 0.0
        return atr[i]
    return f


def trigger_span(symbol, tf):
    """First timestamp the trigger file covers - the span a zone exists for.

    `trigger_zone_fn` returns 0.0 for times before this, and that is not a zone: it
    is the ABSENCE of one. Mixing those bars into a band row is how the first
    version of `show_rung_band` printed a median zone of 0.00 and a band row that
    was the point row wearing a different label.
    """
    files = hst.find(symbol=symbol, tf=tf)
    if not files:
        return None
    bars = hst.load(max(files, key=os.path.getsize))
    if len(bars) < 100:
        return None
    return bars[0][0]


def pattern_step(p, rng=None, cap=2.5):
    """The step a pattern is walked with: its own, or a rerolled one.

    Factored out so the real arm can be asserted directly - `pattern_step(p, None)
    is p['step']` - rather than inferred from a tally. The bug this prevents is
    specific and was live: `ladder_test` used to begin `rng = rng or
    Random(seed)`, so the rng was never None, the "real" arm was shuffled, and the
    control column printed identical to the result on all three symbols.
    """
    if rng is None:
        return p["step"]
    return p["step"] * (0.4 + (cap - 0.4) * rng.random())


def ladder_test(bars, pats, horizon=24, bounce_bars=6, rung_max=8,
                thresholds=(2 / 3.0, 1.0), rng=None, shuffle_cap=2.5, trace=None,
                zone_of=None):
    """Rungs 1..`rung_max` from every on-grid pattern, using ITS OWN step.

    `shuffle_cap` rerolls the step per pattern (0.4x..`shuffle_cap`x), which
    destroys the meaning of a rung index while leaving nesting identical - the
    control that showed the earlier tool's bump was geometry, not the step.

    THERE IS DELIBERATELY NO DEFAULT FOR `rng`. A default is what broke this
    function: it read `rng = rng or random.Random(seed)`, so `rng` was never None,
    the real arm was shuffled along with the control, and the printed control
    column came out identical to the result on gold, euro and cable. Keeping the
    parameter bare makes the real arm impossible to shuffle by accident, and
    `trace` lets the selftest assert the steps actually used.
    """
    tally = {}
    for p in pats:
        if not p["on_grid"] or p["step"] <= 0:
            continue
        s = pattern_step(p, rng, shuffle_cap)
        if trace is not None:
            trace.append(s)
        # The zone is a property of the MARKET at that moment (the trigger
        # timeframe's ATR), never of `s` - so a shuffled step still gets the real
        # zone. Tying the zone to the shuffled step would let the control's own
        # ruler move with it and quietly re-introduce the geometry the control
        # exists to remove.
        zone = zone_of(p) if zone_of is not None else 0.0
        for k in range(1, rung_max + 1):
            r = rung_touch(bars, p["confirm"], p["kind"], p["pivot"], s, k,
                           horizon, bounce_bars, zone)
            if r is None:
                continue
            for thr in thresholds:
                e = tally.setdefault((k, thr), [0, 0])
                e[0] += 1
                e[1] += 1 if r["bounce"] >= thr else 0
    return tally


def ladder_excess(real, shuf, thr, rung_max=8, min_touch=25):
    """Rungs 3+5 against every other rung, in EXCESS over the shuffled arm.

    Headless, so the printed table and the threshold sweep read ONE aggregation -
    computing the excess twice is how a summary line ends up disagreeing with the
    rows printed directly above it.

    Below `min_touch` a rung is dropped rather than shown: a rate over 20 touches is
    not a rate. `usable` is the column that decides whether a row can discriminate
    at all. If the SHUFFLED arm already scores 98%, then a 2/3-step reaction is a
    property of the ruler and not of the rung, and an excess computed there means
    nothing either way.
    """
    hot, rest = [], []
    for k in range(1, rung_max + 1):
        r = real.get((k, thr))
        if not r or r[0] < min_touch:
            continue
        s = shuf.get((k, thr)) if shuf else None
        (hot if k in (3, 5) else rest).append(
            (r[0], r[1] / r[0], (s[1] / s[0]) if s and s[0] else 0.0))
    if not hot or not rest:
        return None
    a = sum(x[1] for x in hot) / len(hot)
    b = sum(x[1] for x in rest) / len(rest)
    sa = sum(x[2] for x in hot) / len(hot)
    sb = sum(x[2] for x in rest) / len(rest)
    return {"hot": a, "rest": b, "shuf_hot": sa, "shuf_rest": sb,
            "raw": a - b, "excess": (a - b) - (sa - sb),
            "n_hot": sum(x[0] for x in hot), "n_rest": sum(x[0] for x in rest),
            "usable": max(sa, sb) < 0.90}


def ladder_null(bars, pats, thr, zone_of=None, horizon=24, bounce_bars=6, rung_max=8,
                draws=120, rows_tested=20):
    """The null for `ladder_excess` at this sample: TWO REROLLED RULERS, against each
    other. Neither arm knows the real step, so every excess in this distribution is
    noise, and it is the only honest yardstick for a "best row" verdict.

    WHY AN ABSOLUTE BAR WILL NOT DO. The report first shipped with "stands out if
    the best excess is over +5%", and that number meant nothing: on EURUSD daily
    the noise's own best-of-20 reaches +9-11%, which is LARGER than anything the
    real data ever produced (+6.33%). A 5% bar would have certified pure noise as a
    discovery on any sample with more rows in it.

    `best_median`/`best_p90` are the MAXIMUM over `rows_tested` draws, because a
    sweep reports its best row and that is the statistic that has to be calibrated.
    `p_best` is P(null best-of-N >= the observed best), and it is read off the
    empirical distribution rather than a normal approximation - the excess is not
    Gaussian here (it is bounded and lumpy at small n).
    """
    null = []
    for i in range(draws):
        a = ladder_test(bars, pats, horizon=horizon, bounce_bars=bounce_bars,
                        rung_max=rung_max, thresholds=(thr,),
                        rng=random.Random(10000 + 2 * i), zone_of=zone_of)
        b = ladder_test(bars, pats, horizon=horizon, bounce_bars=bounce_bars,
                        rung_max=rung_max, thresholds=(thr,),
                        rng=random.Random(10001 + 2 * i), zone_of=zone_of)
        e = ladder_excess(a, b, thr, rung_max)
        if e is not None:
            null.append(e["excess"])
    if len(null) < 20:
        return None
    bests = [max(random.Random(900 + i).sample(null, min(rows_tested, len(null))))
             for i in range(2000)]
    bests.sort()
    mu = sum(null) / len(null)
    sd = (sum((x - mu) ** 2 for x in null) / len(null)) ** 0.5
    return {"n": len(null), "mean": mu, "sd": sd,
            "best_median": bests[len(bests) // 2],
            "best_p90": bests[int(0.90 * len(bests))],
            "bests": bests}


def show_ladder(real, shuf, thresholds=(2 / 3.0, 1.0), rung_max=8, summary=True):
    """Per rung: real rate, shuffled rate, and the one column that is a result."""
    last = 0.0
    for thr in thresholds:
        print(f"\n  reaction = counter-move of >= {thr:.2f} step, within 6 bars of the touch")
        print(f"   {'rung':>4} {'touched':>8} {'reacted':>8} {'rate':>7}   {'shuffled':>8}")
        for k in range(1, rung_max + 1):
            r, s = real.get((k, thr)), shuf.get((k, thr))
            if not r or r[0] < 25:
                continue
            rate = r[1] / r[0]
            srate = (s[1] / s[0]) if s and s[0] else 0.0
            mark = "   <-- rung 3" if k == 3 else ("   <-- rung 5" if k == 5 else "")
            print(f"   {k:>4} {r[0]:>8} {r[1]:>8} {rate:>7.2%}   {srate:>8.2%}{mark}")
        e = ladder_excess(real, shuf, thr, rung_max) if summary else None
        if e is None:
            continue
        print(f"\n   rungs 3+5 ......... {e['hot']:.2%}   shuffled {e['shuf_hot']:.2%}"
              f"   (n={e['n_hot']})")
        print(f"   every other rung .. {e['rest']:.2%}   shuffled {e['shuf_rest']:.2%}"
              f"   (n={e['n_rest']})")
        print(f"   raw gap ........... {e['raw']:+.2%}")
        print(f"   EXCESS ............ {e['excess']:+.2%}   <- the result")
        last = e["excess"]
    return last


# ----------------------------------------------------------------- samples ---

def samples(bars, pats, S_override=None, horizon=24, bounce_bars=6, want=3):
    """Concrete pivots: time, price, step, and what rungs 3 and 5 did.

    The first `want` on-grid patterns in date order, whatever they say. Picking
    the ones that worked would make the samples worthless, which is the same
    reason the ladder table carries the shuffled column next to the real one.
    """
    out = []
    for p in pats:
        if len(out) >= want or not p["on_grid"]:
            continue
        S = S_override or p["step"]
        rec = {
            "time": stamp(p["time"]), "pivot": p["pivot"],
            "kind": p["kind"], "impulse": p["impulse"], "retrace": p["retrace"],
            "ratio": p["r"], "class": p["class"], "step": S,
            "impulse_atr": p["impulse"] / p["atr"], "rungs": {},
        }
        for k in (3, 5):
            r = rung_touch(bars, p["confirm"], p["kind"], p["pivot"], S, k,
                           horizon, bounce_bars)
            rec["rungs"][k] = None if r is None else {
                "level": r["lvl"], "bounce_steps": r["bounce"],
                "bounce_atr": r["bounce"] * S / p["atr"] if p["atr"] > 0 else 0.0,
                "time": stamp(bars[r["hit"]][0]),
            }
        out.append(rec)
    return out


# ------------------------------------------- measuring pivots on a finer clock ---
#
# THE REQUEST: re-measure the pivots on the trigger timeframe so the retracement
# budget closes. Before believing that helps, the two things a finer clock can
# change have to be separated, because only one of them is real:
#
#   PRICE. The structure pivot's price IS the structure bar's extreme, and the
#   extreme of the trigger bars INSIDE that structure bar is the same number - by
#   construction, not by luck. `extreme_identity()` measures this instead of
#   asserting it. So a finer clock cannot make the extreme more precise: the
#   extreme is the extreme.
#
#   WHAT IS ACTUALLY NOISY. The step's grid is blurred by how far price OVERSHOOTS
#   the turning level before it turns - a wick. That wick is a real market event,
#   not a measurement error, so it exists identically on every timeframe. The one
#   thing a finer clock CAN offer is a different price to draw the leg with: the
#   pivot bar's CLOSE, which is where price settled after rejecting the level,
#   rather than the wick tip. That variant is measured below as `settled`, beside
#   the literal `extreme` reading, and the numbers decide - not the argument.

def measurement_map(sbars, mbars, window_s):
    """Per structure bar, the extremes and the settled close from the finer clock.

    `window_s` is the STRUCTURE bar's own duration, and getting that wrong is the
    bug this docstring exists to prevent: the first version passed the finer
    period instead, so a daily bar was searched over four hours and the "refined"
    extreme was just the first sub-bar's high. Every identity check then failed
    (-2004 of 2006) for a reason that had nothing to do with the market.

    Returns {structure_bar_time: (high, low, last_close, subs)}. `subs` is how
    many finer bars actually covered the structure bar - a structure bar with no
    sub-bars cannot be measured at all and is reported rather than silently
    falling back to its own price.
    """
    times = [b[0] for b in mbars]
    out = {}
    for sb in sbars:
        t0 = sb[0]
        i = bisect.bisect_left(times, t0)
        j = i
        while j < len(mbars) and mbars[j][0] < t0 + window_s:
            j += 1
        if j <= i:
            continue
        subs = mbars[i:j]
        out[t0] = (max(b[2] for b in subs), min(b[3] for b in subs),
                   subs[-1][4], len(subs))
    return out


def extreme_identity(sbars, mmap, expect_subs):
    """Does the finer clock's extreme reproduce the structure bar's extreme?

    The claim under test is one line of arithmetic: max over sub-bars of high ==
    the structure bar's high. It holds exactly when the finer series covers the
    coarser bar completely, and it is the reason "re-measure the extreme on the
    trigger timeframe" cannot reduce this noise. Counted, not assumed.
    """
    same = diff = incomplete = 0
    for sb in sbars:
        m = mmap.get(sb[0])
        if m is None:
            incomplete += 1
            continue
        if m[3] < expect_subs:
            incomplete += 1          # flagged, but still compared - see below
        if abs(m[0] - sb[2]) < 1e-9 and abs(m[1] - sb[3]) < 1e-9:
            same += 1
        else:
            diff += 1
    # NOTE the comparison runs even on incomplete coverage. Requiring the full set
    # of sub-bars first made this check compare NOTHING on real data - the first run
    # reported `same 0 differ 0 incomplete 1773`, i.e. every single structure bar
    # flagged and not one identity tested. Broker history has holes; `incomplete`
    # is a coverage warning, it is not a reason to skip the measurement.
    return {"same": same, "differ": diff, "incomplete": incomplete,
            "compared": same + diff}


def measured_legs(sbars, atr, mmap, mode):
    """Legs whose prices come from the finer clock, in the chosen mode.

    mode 'extreme' -> the structure high/low (what the finer clock confirms)
    mode 'settled' -> the last finer bar's close inside the pivot bar
    """
    def price_fn(idx, kind, price):
        m = mmap.get(sbars[idx][0])
        if m is None:
            return price
        if mode == "settled":
            return m[2]
        return m[0] if kind == "H" else m[1]

    return pivot_legs(sbars, atr, price_fn=price_fn)


def measure_run(symbol, s_tf, m_tf, mode="extreme", min_patterns=40):
    """One (structure, measurement) pair on its own overlap window, measured.

    Everything is restricted to the window both files actually cover, because a
    finer timeframe with a short history would otherwise be scored on whatever
    stub it has - the same "the sample differs per cell" trap the study next door
    documents.
    """
    sf = hst.find(symbol=symbol, tf=s_tf)
    mf = hst.find(symbol=symbol, tf=m_tf)
    if not sf or not mf:
        return None
    spath = max(sf, key=os.path.getsize)
    mpath = max(mf, key=os.path.getsize)
    sbars, mbars = hst.load(spath), hst.load(mpath)
    if len(sbars) < 300 or len(mbars) < 300:
        return None
    lo = max(sbars[0][0], mbars[0][0])
    hi = min(sbars[-1][0], mbars[-1][0])
    sbars = [b for b in sbars if lo <= b[0] <= hi]
    mbars = [b for b in mbars if lo <= b[0] <= hi]
    if len(sbars) < 300:
        return None
    s_period, m_period = s_tf * 60, m_tf * 60
    expect_subs = max(1, s_period // m_period)
    mmap = measurement_map(sbars, mbars, s_period)
    atr = atr_series(sbars)
    legs = measured_legs(sbars, atr, mmap, mode)
    pats = patterns(legs)
    if len(pats) < min_patterns:
        return None
    ident = extreme_identity(sbars, mmap, expect_subs)
    # The noise scale is the FINER clock's bar range: that is the whole point of
    # measuring there, and using the structure range instead would beg the question.
    # Two noise models, and the verdict uses the conservative one. `range` treats a
    # whole bar range as error; `wick` treats only the overshoot as error. Reporting
    # both is what stops the conclusion from being an artifact of the choice.
    bud = noise_budget(median_impulse(pats), bar_noise(mbars))
    bud_wick = noise_budget(median_impulse(pats), wick_noise(mbars))
    g = grid_stats(pats, budget=bud)
    cons = class_consistency(pats)
    return {"symbol": symbol, "structure": s_tf, "measure": m_tf, "mode": mode,
            "s_bars": len(sbars), "m_bars": len(mbars), "patterns": len(pats),
            "identity": ident, "budget": bud, "budget_wick": bud_wick, "grid": g,
            "consistency": cons, "null": class_consistency_null(pats)}


def show_measure_sweep(symbols, pairs, mode="extreme"):
    """Which pairing first makes the 3-class and 5-class agree? Measured, in order."""
    print(f"\n  pivot measurement moved onto the finer clock - mode '{mode}'")
    print(f"  {'sym':<8} {'struct':>6} {'meas':>5} {'bars':>10} {'patt':>6} "
          f"{'cell':>5} {'cellW':>6} {'gridAdv':>8} {'3-vs-5':>7} {'p(chnc)':>8}  verdict")
    print(f"  {'':<8} {'':>6} {'':>5} {'':>10} {'':>6} "
          f"{'rng':>5} {'wick':>6}  (cell error in grid cells; tolerance {GRID_TOL:.2f})")
    first_ok = None
    for sym in symbols:
        for s_tf, m_tf in pairs:
            r = measure_run(sym, s_tf, m_tf, mode)
            if r is None:
                print(f"  {sym:<8} {s_tf:>6} {m_tf:>5} {'no overlap / too few bars':>38}")
                continue
            b, g, c = r["budget"], r["grid"], r["consistency"]
            bw = r["budget_wick"]
            ratio = c["ratio"] if c.get("enough") else float("nan")
            nl = r["null"]
            # THE VERDICT IS DECIDED ON THE PERMISSIVE NOISE MODEL ON PURPOSE. If it
            # were decided on the conservative one, a null could always be blamed on
            # the ruler. Deciding on the WICK model means that wherever the verdict
            # reads "readable", the grid was given its best possible chance - and it
            # is still not there. That upgrades the null from "no power" to a fact.
            ok = (bool(c.get("enough")) and 0.8 <= ratio <= 1.25
                  and nl is not None and nl < 0.05 and bw["resolvable"])
            if ok and first_ok is None:
                first_ok = (sym, s_tf, m_tf, mode)
            verdict = ("PASS both checks" if ok else
                       f"UNREADABLE even on wick ({bw['cell_error'] / GRID_TOL:.0f}x)"
                       if not bw["resolvable"] else
                       "no step agreed" if not c.get("enough") else
                       f"chance agreement p={nl:.2f}" if (nl is None or nl >= 0.05)
                       else f"READABLE, classes disagree {ratio:.2f}x")
            print(f"  {sym:<8} {s_tf:>6} {m_tf:>5} "
                  f"{r['s_bars']:>5}+{r['m_bars']:<4} {r['patterns']:>6} "
                  f"{b['cell_error']:>5.2f} {bw['cell_error']:>6.2f} "
                  f"{g['advantage']:>+8.1%} {ratio:>7.2f} "
                  f"{(f'{nl:.2f}' if nl is not None else '  - '):>8}  {verdict}")
    return first_ok


def trigger_atr(symbol, tf, at):
    """The trigger timeframe's own ATR at a moment - the width of a reaction zone.

    The user's rule is that a reaction is not a point but a band as wide as the
    trigger timeframe's ability, so the band is read off the trigger file at the
    bar covering the same clock time, not approximated from the structure ATR.
    """
    paths = hst.find(symbol=symbol, tf=tf)
    if not paths:
        return 0.0
    bars = hst.load(max(paths, key=os.path.getsize))
    if len(bars) < 100:
        return 0.0
    atr = atr_series(bars)
    lo, hi = 0, len(bars) - 1
    while lo < hi:
        m = (lo + hi) // 2
        if bars[m][0] < at:
            lo = m + 1
        else:
            hi = m
    return atr[lo] if 0 <= lo < len(atr) else 0.0


# ---------------------------------------------------------------- selftest ---

def synth(seed, plant, n_bars=2600, atr_price=1.0, step_mult=3.0, noise=0.15):
    """Bars whose ratios are planted on the 3- and 5-grids, or pure noise.

    `step_mult` is the planted step in ATR units; it has to be large enough that
    a one-third retracement still clears the zigzag's 1-ATR confirmation, or the
    planted pivots would never be seen and the seed would test nothing.

    `noise` scales the intrabar jitter. It exists so the same plant can be run
    clean, where the estimator must recover the planted step, and dirty, where it
    must NOT - the degradation seed that stops this tool from passing on a plant
    it cannot actually read.
    """
    rng = random.Random(seed)
    S = step_mult * atr_price
    path = [100.0]
    leg = 0.5 * atr_price

    def run(direction, size):
        for _ in range(max(1, int(round(size / leg)))):
            path.append(path[-1] + direction * leg)

    if plant:
        # A LADDER, not a zigzag of trend flips. Each impulse is 3S or 5S in the
        # SAME direction and each retracement is k/3*S against it, so price
        # resumes after every retracement and every pivot the zigzag finds is a
        # real turn. The first version of this plant flipped the trend every two
        # phases; a flip merges the retracement into the new impulse, so legs came
        # out 4S and 3.67S wide, landed on neither grid, and the estimator was
        # being marked down for a fault in the generator. Direction still turns,
        # but rarely enough that a merge is the exception - the honest way to
        # reproduce what real segmentation does to the test.
        d = 1
        phase = 0
        while len(path) < n_bars:
            run(d, (3 if phase % 2 == 0 else 5) * S)
            run(-d, rng.choice([1, 2, 3]) / 3.0 * S)
            phase += 1
            if phase % 12 == 0:
                d = -d
    else:
        for _ in range(n_bars):
            path.append(path[-1] + rng.gauss(0, 0.35 * atr_price))

    bars = []
    for i, p in enumerate(path):
        o = p + rng.gauss(0, 0.05 * noise * atr_price)
        c = p + rng.gauss(0, 0.05 * noise * atr_price)
        h = max(o, c) + abs(rng.gauss(0, 0.12 * noise * atr_price)) + 0.05 * noise * atr_price
        l = min(o, c) - abs(rng.gauss(0, 0.12 * noise * atr_price)) - 0.05 * noise * atr_price
        bars.append((1700000000 + i * 3600, o, h, l, c))
    return bars, S


def censored_path(cycles=14, step=1.0, run_bars=10, retrace=0.5, ret_bars=3,
                  start=100.0):
    """A path whose retracements are SHORTER than one ATR, with master turns.

    Two things have to hold at once, and getting only one of them is why the first
    version of this generator tested nothing:

      * the ZIGZAG must be censored, which needs the measured retreat - the turn
        bar's high down to the lowest low of the retracement - to be under 1 ATR.
        The retreat is `retrace` PLUS the bars' own ranges, so doji-thin bars and
        a shallow retracement are both required; a fat bar range alone adds more
        than the retracement and un-censors it.
      * the COURSE detector must accept the turn, and its anatomy gate wants a
        master candle (body or shadow >= 0.8 of range) with the close on the pivot's
        side. A uniform doji has neither.

    So the bars are thin dojis at each path point and the turn bars are given a
    long body. Then ATR settles near the per-bar step, the retreat stays under it,
    and the only detector that can see the turn is the one without the 1-ATR rule.
    """
    bars = []
    t = 1700000000
    p = start

    def emit(x, kind):
        nonlocal t
        if kind == "H":          # bull master: big body, close at the top
            o, c = x - 0.45, x
            h, l = x + 0.02, x - 0.47
        elif kind == "L":        # bear master: big body, close at the bottom
            o, c = x + 0.45, x
            h, l = x + 0.47, x - 0.02
        else:                    # thin doji: adds almost nothing to the retreat
            o = c = x
            h, l = x + 0.02, x - 0.02
        bars.append((t, o, h, l, c))
        t += 3600

    for _ in range(cycles):
        for k in range(run_bars):
            emit(p + step * (k + 1), "H" if k == run_bars - 1 else "")
        p += step * run_bars
        for k in range(ret_bars):
            emit(p - retrace * (k + 1) / float(ret_bars), "L" if k == ret_bars - 1 else "")
        p -= retrace
    return bars


def bar_noise(bars):
    """Median bar range - the per-pivot price error the grid has to survive."""
    rngs = sorted(b[2] - b[3] for b in bars)
    return rngs[len(rngs) // 2] if rngs else 0.0


def wick_noise(bars):
    """Median WICK at the bar extremes, not median range.

    The step's grid is blurred by how far price overshoots the turning level before
    it turns - that is a wick, so the range is an overestimate: a bar's range also
    contains the move INTO the level, which is signal, not error. Both models are
    reported because `noise_budget` divides by this number, so cell error is a
    model output rather than a measurement, and the conclusion is only worth
    anything if it survives under both.
    """
    up = sorted(b[2] - max(b[1], b[4]) for b in bars)
    dn = sorted(min(b[1], b[4]) - b[3] for b in bars)
    ws = sorted(up + dn)
    return ws[len(ws) // 2] if ws else 0.0


def coarsen(mbars, group):
    """Aggregate finer bars into coarser ones - the fine clock is the only source.

    Used by the selftest to pin the claim the whole measurement rests on: the
    coarser bar's high/low are exactly the extremes of its sub-bars, so the finer
    clock cannot sharpen a pivot's PRICE, only restate it.
    """
    out = []
    for i in range(0, len(mbars) - group + 1, group):
        ch = mbars[i:i + group]
        out.append((ch[0][0], ch[0][1], max(b[2] for b in ch),
                    min(b[3] for b in ch), ch[-1][4]))
    return out


def median_impulse(pats):
    imp = sorted(p["impulse"] for p in pats)
    return imp[len(imp) // 2] if imp else 0.0


def selftest():
    faults = 0

    def check(cond, what):
        nonlocal faults
        if not cond:
            print(f"  SEED NOT CAUGHT: {what}")
            faults += 1

    for seed in (11, 12, 13):
        bars, planted_S = synth(seed, True)
        atr = atr_series(bars)
        pats = patterns(pivot_legs(bars, atr))
        bud = noise_budget(median_impulse(pats), bar_noise(bars))
        g = grid_stats(pats, budget=bud)
        check(g["n"] > 40, f"planted seed {seed}: only {g['n']} patterns seen")
        if g["n"] <= 40:
            continue
        check(bud["resolvable"], f"planted seed {seed}: clean plant reported as "
                                 f"unreadable (cell error {bud['cell_error']:.2f})")
        # planted ratios are exactly k/9 or k/15, so a grid must catch them
        check(g["any"] > 0.70,
              f"planted seed {seed}: only {g['any']:.0%} landed on one ratio grid "
              f"(chance is {g['chance']:.0%})")
        cons = class_consistency(pats)
        check(cons["enough"], f"planted seed {seed}: too few on-grid patterns "
                              f"to compare the two classes")
        if cons["enough"]:
            # both classes must recover the SAME step, because there is one
            check(0.8 <= cons["ratio"] <= 1.25,
                  f"planted seed {seed}: step from 3-class and 5-class disagree "
                  f"by {cons['ratio']:.2f}x ({cons['step3']:.3f} vs {cons['step5']:.3f})")
            check(0.75 * planted_S <= cons["step3"] <= 1.35 * planted_S,
                  f"planted seed {seed}: step {cons['step3']:.3f} is not the "
                  f"planted {planted_S:.3f}")

    # THE DEGRADATION SEED. The same plant with realistic intrabar noise must be
    # reported as unreadable rather than confidently fitted - that is the whole
    # difference between a measurement and a number.
    for seed in (41, 42):
        bars, _ = synth(seed, True, noise=6.0)
        atr = atr_series(bars)
        pats = patterns(pivot_legs(bars, atr))
        bud = noise_budget(median_impulse(pats), bar_noise(bars))
        check(not bud["resolvable"],
              f"noisy seed {seed}: grid reported readable despite a cell error of "
              f"{bud['cell_error']:.2f} cells ({int(bud['cell_error'] / GRID_TOL)}x the tolerance)")

    for seed in (21, 22):
        bars, _ = synth(seed, False)
        atr = atr_series(bars)
        pats = patterns(pivot_legs(bars, atr))
        g = grid_stats(pats)
        if g["n"] < 40:
            continue
        check(g["any"] < 0.55,
              f"noise seed {seed}: {g['any']:.0%} landed on a ratio grid - the "
              f"test is finding a grid that is not there (chance {g['chance']:.0%})")
        cons = class_consistency(pats)
        if cons["enough"]:
            check(not (0.8 <= cons["ratio"] <= 1.25),
                  f"noise seed {seed}: the two classes agreed on a step "
                  f"({cons['ratio']:.2f}x) - the check is not discriminating")

    # THE BAND SEEDS - two of them, because the band has two ways to lie and the
    # first version of this code took one of them.
    #
    # (a) `pen` must be a PRINTED price. The rejected design clamped it to the
    #     band's far edge; a clamp is a floor, a floor is lower than the real low,
    #     and a lower reference makes the bounce BIGGER - so a wider zone would
    #     have manufactured reactions. Asserted structurally.
    #     NOTE ON WHICH PLANT. The first version of this seed ran on
    #     `censored_path()`, which by construction produces ZERO zigzag pivots, so
    #     every one of its three calls returned None and the seed never executed a
    #     single comparison. It reported green and caught nothing. That is why this
    #     seed now counts its own checks and fails if it ran fewer than two: a seed
    #     that silently does not run is worse than no seed.
    pbars2, _ = synth(7, True)
    patr2 = atr_series(pbars2)
    ppats2 = patterns(pivot_legs(pbars2, patr2))
    if ppats2:
        p2 = ppats2[0]
        ran = 0
        for z in (0.0, 0.5, 2.0):
            r = rung_touch(pbars2, p2["confirm"], p2["kind"], p2["pivot"], 5.0, 1,
                           40, 6, z)
            if r is None:
                continue
            # EXACT, not "within the data range": the reference must be the extreme
            # of the very bar it claims, so any computed floor - the clamp that was
            # removed - fails this line instead of merely drifting.
            want = pbars2[r["pen_i"]][3 if p2["kind"] == "H" else 2]
            check(r["pen"] == want,
                  f"zone {z}: pen={r['pen']} is a computed reference, not bar "
                  f"{r['pen_i']}'s printed extreme {want}")
            ran += 1
        check(ran >= 2,
              f"the printed-reference seed executed only {ran} of 3 zones - a seed "
              f"that never runs is green and proves nothing")

    # (b) A ONE-WAY TREND HAS NO REACTION TO REPORT. However wide the zone, the
    #     measured counter-move must stay at the noise floor. If a band ever finds
    #     a large bounce in a monotone decline, the band is the source of it.
    drift = []
    dx = 100.0
    for i in range(120):
        dx -= 1.0
        drift.append((1700000000 + i * 3600, dx + 0.20, dx + 0.20, dx - 0.20, dx))
    for z in (0.0, 1.0, 3.0):
        r = rung_touch(drift, 0, "H", 103.0, 1.0, 3, 100, 6, z)
        check(r is None or r["bounce"] < 0.3,
              f"zone {z}: a one-way decline reported a "
              f"{0.0 if r is None else r['bounce']:.2f}-step bounce - the band is "
              f"manufacturing reactions out of trend")

    # THE NULL SEED. The best-row verdict is only worth reading if the null it is
    # measured against is centred on zero and not degenerate - and if the null
    # test cannot certify noise. That last property is checkable exactly: a real
    # arm that IS a rerolled ruler is, by construction, drawn from the null, so it
    # must not come out significant.
    #
    # The plant has to be BOTH long and noisy, and each requirement bit:
    #
    #   LONG, or rungs 3 and 5 never clear `min_touch`. At the default 2600 bars
    #   they held 17 and 4 touches, every null draw came back None, and this seed
    #   failed with "produced no usable null".
    #
    #   NOISY, or the null is DEGENERATE and the seed fails with "sd 0.00%". On a
    #   clean ladder price runs 3S or 5S and every rung reacts for every ruler, so
    #   every null draw returns exactly the same excess - a null of zero width
    #   that could not test anything. noise=6.0 is the same dirty plant the
    #   degradation seed uses.
    nbars, _ = synth(7, True, n_bars=14000, noise=6.0)
    natr = atr_series(nbars)
    npats = patterns(pivot_legs(nbars, natr))
    if len(npats) >= 40:
        nul = ladder_null(nbars, npats, 3.0, draws=40)
        check(nul is not None, "the null seed produced no usable null")
        if nul:
            check(abs(nul["mean"]) < 0.06,
                  f"the null is not centred on zero (mean {nul['mean']:+.2%}) - the "
                  f"excess carries a bias the shuffled control does not remove, so "
                  f"every table computed with it is off by that much")
            check(nul["sd"] > 0.01,
                  f"the null is degenerate (sd {nul['sd']:.2%}) - it cannot test")
            e = ladder_excess(
                ladder_test(nbars, npats, thresholds=(3.0,), rng=random.Random(7)),
                ladder_test(nbars, npats, thresholds=(3.0,),
                            rng=random.Random(20260919)), 3.0)
            if e is not None:
                p = sum(1 for x in nul["bests"] if x >= e["excess"]) / len(nul["bests"])
                check(p > 0.05,
                      f"a rerolled real arm scored p={p:.2f} against the null - the "
                      f"verdict would certify noise as a discovery")

    # THE CENSORING SEED - the user's premise, measured. The zigzag's 1-ATR
    # confirmation is a CENSOR, not a filter: on a path whose retracements are
    # shorter than one ATR it declares NO turn at all, so the retracement is not
    # rare in its sample, it is unrepresentable. The course's pivot sees the same
    # turn. If this seed ever passes with the zigzag finding it too, either the
    # path stopped being censored or the zigzag stopped being a 1-ATR rule.
    cbars = censored_path()
    catr = atr_series(cbars)
    zz = swing_pivots(cbars, catr)
    cp = course_pivots(cbars, catr, 0.25)
    zp = patterns(pivot_legs(cbars, catr, pivots=zz))
    cpp = patterns(pivot_legs(cbars, catr, pivots=cp))
    check(len(cp) > 0,
          "the course detector saw no pivots at all in the censored path")
    check(len(cp) > len(zz),
          f"the course detector found {len(cp)} pivots against the zigzag's "
          f"{len(zz)} - it is not seeing the turns the zigzag censors")
    # FULL censoring is the strongest form of the claim, so it is allowed here -
    # the zigzag finding NOTHING means the retracement is not rare in its sample,
    # it is unrepresentable. `n == 0` therefore counts as censored, and the real
    # failure to catch is a zigzag that reports sub-ATR retracements after all.
    check(censoring(zp)["n"] == 0 or censoring(zp)["below_1atr"] == 0.0,
          f"the zigzag reported a sub-ATR retracement "
          f"({censoring(zp)['below_1atr']:.0%}) - it is not censoring here, so this "
          f"seed no longer tests what it claims")
    check(censoring(cpp)["below_1atr"] > 0.5,
          f"the course detector recovered only "
          f"{censoring(cpp)['below_1atr']:.0%} sub-ATR retracements - it should "
          f"have recovered nearly all of them")
    # And the DIAL must matter: a 1-ATR confirmation re-imposes the zigzag's own
    # censor on the course detector, so the two dial settings cannot agree.
    check(len(course_pivots(cbars, catr, 1.0)) < len(cp),
          "a 1-ATR confirmation found as many pivots as a 0.25 one - the censoring "
          "dial does nothing and the comparison table is meaningless")

    # THE IDENTITY SEED. The answer to "measure the pivots on the trigger timeframe"
    # turns on one claim: a coarser bar's extreme IS the extreme of its sub-bars, so
    # a finer clock restates the pivot's price and cannot sharpen it. Planted here as
    # an exact aggregate, then degraded by deleting one sub-bar - which must surface
    # as an incomplete structure bar rather than as a quiet wrong answer.
    mbars, _ = synth(51, True, noise=0.4)
    sbars = coarsen(mbars, 4)
    ident = extreme_identity(sbars, measurement_map(sbars, mbars, 4 * 3600), 4)
    check(ident["same"] == len(sbars) and ident["differ"] == 0,
          f"the finer clock did not reproduce the coarse extremes: {ident}")
    # THE DECISIVE INVARIANT, and the direct answer to "re-measure the pivots on the
    # trigger timeframe": because the finer clock reproduces the coarse extremes
    # exactly, the legs - and therefore every ratio r - come out IDENTICAL. The
    # request changes the pivot's clock, not its price, so it cannot move the
    # measurement. Whatever cell error gains are seen downstream come from swapping
    # the noise MODEL for a smaller bar range, which is why both models are printed.
    atr_c = atr_series(sbars)
    plain = [p["r"] for p in patterns(pivot_legs(sbars, atr_c))]
    on_fine = [p["r"] for p in patterns(measured_legs(
        sbars, atr_c, measurement_map(sbars, mbars, 4 * 3600), "extreme"))]
    check(plain == on_fine and plain,
          f"the finer clock moved the measured ratios ({len(plain)} vs {len(on_fine)})"
          f" - the identity result and r-invariance cannot both hold")

    # Delete one sub-bar from the FINE series only, keeping the coarse bars as they
    # were. Re-grouping after the deletion would just re-align every later hour and
    # the hole would vanish - which is what the first version of this seed did.
    holed = mbars[:444] + mbars[445:]
    ident_h = extreme_identity(sbars, measurement_map(sbars, holed, 4 * 3600), 4)
    check(ident_h["incomplete"] >= 1,
          f"a deleted sub-bar left no trace: {ident_h} - a gap would be silently "
          f"measured as if the finer clock covered the bar")

    # the shuffled control must flatten the rung curve, or the curve is unreadable
    bars, _ = synth(31, True)
    atr = atr_series(bars)
    pats = patterns(pivot_legs(bars, atr))
    # THE TRAP SEED. The real arm must walk the patterns' OWN steps. Comparing the
    # two tallies does not establish that (two shuffle streams differ from each
    # other just as much as from the real arm), so the steps actually used are
    # captured and compared. This is the check that the earlier version needed and
    # did not have: its `rng = rng or Random(...)` default quietly shuffled the
    # real arm too, and the only visible symptom was a control column that matched
    # the result - which looked like a null result rather than a bug.
    tr_real, tr_shuf = [], []
    real = ladder_test(bars, pats, trace=tr_real)
    sh = ladder_test(bars, pats, rng=random.Random(7), trace=tr_shuf)
    want = {p["step"] for p in pats if p["on_grid"] and p["step"] > 0}
    check(set(tr_real) == want,
          f"the real arm did not use the patterns' own steps: "
          f"{len(set(tr_real) - want)} step(s) used that were never measured - "
          f"the rng default is back")
    check(tr_real != tr_shuf, "the shuffled arm is identical to the real arm")
    rates = [v[1] / v[0] for k, v in sorted(sh.items()) if k[1] == 1.0 and v[0] > 25]
    if len(rates) >= 4:
        check(max(rates) - min(rates) < 0.35,
              f"shuffled rung curve is not flat (spread {max(rates) - min(rates):.0%})")

    print(f"  selftest: {faults} uncaught seed(s)")
    return faults


# --------------------------------------------------------------------- CLI ---

def instrument(symbol, structure, trigger, out_dir=None, course=False,
               confirm_atr=0.25):
    """One symbol end to end: ratio grids, step, class agreement, rung-3/5.

    `course=True` swaps the detector for the six-condition pivot at `confirm_atr`.
    Nothing downstream changes - which is the point of the swap: any movement in
    the numbers is the detector's doing, not the pipeline's.
    """
    sfiles = hst.find(symbol=symbol, tf=structure)
    if not sfiles:
        print(f"  {symbol}: no structure file at TF {structure}")
        return None
    spath = max(sfiles, key=os.path.getsize)
    bars = hst.load(spath)
    if len(bars) < 400:
        print(f"  {symbol}: only {len(bars)} bars at TF {structure}")
        return None
    atr = atr_series(bars)
    piv = course_pivots(bars, atr, confirm_atr) if course else None
    legs = pivot_legs(bars, atr, pivots=piv)
    pats = patterns(legs)
    digits = hst.digits_of(spath)
    unit = "pip" if digits in (3, 5) else "pt"
    per = (hst.pip_size(digits) if digits in (3, 5) else 10.0 ** (-digits))

    who = (f"course pivot, confirm {confirm_atr:.2f} ATR" if course
           else "zigzag, 1.00 ATR")
    print(f"\n=== {symbol}  TF{structure} structure / trigger {trigger}  "
          f"({len(bars)} bars {hst.day(bars[0][0])}..{hst.day(bars[-1][0])}) ===")
    print(f"  detector: {who}")
    print(f"  {len(legs)} legs -> {len(pats)} impulse+retracement patterns")
    cz = censoring(pats)
    print(f"  retracements below 1 ATR: {cz['below_1atr']:.1%}   median "
          f"{cz['median_ret_atr']:.2f} ATR   smallest {cz['min_ret_atr']:.2f} ATR")
    bud = noise_budget(median_impulse(pats), bar_noise(bars))
    g = grid_stats(pats, budget=bud)
    print(f"  RATIO GRID (r = retrace/impulse): only 3-grid {g['grid3']:.1%}   "
          f"only 5-grid {g['grid5']:.1%}   exactly one grid {g['any']:.1%}   "
          f"ambiguous {g['ambiguous']:.1%}")
    print(f"  grid vs its nulls: on a grid {g['true']:.1%}   half-cell-shifted grid "
          f"{g['shifted']:.1%}   chance {g['chance']:.0%}   "
          f"-> grid advantage {g['advantage']:+.1%}")
    print(f"  resolution: median bar range {bud and bar_noise(bars) / per:.1f} {unit}, "
          f"median impulse {median_impulse(pats) / per:.1f} {unit} -> cell error "
          f"{bud['cell_error']:.2f} cells vs tolerance {GRID_TOL:.2f}  "
          f"{'READABLE' if bud['resolvable'] else 'TOO NOISY to read thirds'}")
    cons = class_consistency(pats)
    if not cons["enough"]:
        print(f"  STEP: too few on-grid patterns to compare classes "
              f"(3-class {cons['n3']}, 5-class {cons['n5']}) - no step claim here")
        return {"symbol": symbol, "patterns": len(pats), "grid": g,
                "budget": bud, "consistency": cons, "step": None}
    m3, m5 = cons["step3"], cons["step5"]
    agree = 0.8 <= cons["ratio"] <= 1.25
    print(f"  STEP from 3-class patterns: {m3 / per:.1f} {unit}  (n={cons['n3']})")
    print(f"  STEP from 5-class patterns: {m5 / per:.1f} {unit}  (n={cons['n5']})")
    print(f"  agreement: {cons['ratio']:.2f}x   "
          f"{'CONSISTENT' if agree else 'INCONSISTENT - not one step'}")
    if not agree and not bud["resolvable"]:
        print("    and THAT is the noise budget talking: at this scale the grid is "
              f"{bud['cell_error'] / GRID_TOL:.0f}x too fine to classify on, so the "
              "3/5 split is arbitrary and a 5/3 disagreement is what arbitrary "
              "looks like. No step should be quoted from this series.")

    real = ladder_test(bars, pats)
    shuf = ladder_test(bars, pats, rng=random.Random(20260919))
    excess = show_ladder(real, shuf)

    ex = samples(bars, pats)
    for s in ex:
        s["zone"] = trigger_atr(symbol, trigger, _epoch(s["time"]))
    print(f"\n  SAMPLES from {os.path.basename(spath)} (broker bar clock):")
    for s in ex:
        r3, r5 = s["rungs"][3], s["rungs"][5]
        f3 = "no touch" if r3 is None else f"{r3['bounce_steps']:.2f} step"
        f5 = "no touch" if r5 is None else f"{r5['bounce_steps']:.2f} step"
        zone = (f"{s['zone'] / per:.1f} {unit}" if s["zone"] > 0
                else f"n/a (TF{trigger} file does not reach this date)")
        print(f"   {s['time']}  {symbol} {s['kind']} @ {s['pivot']:.{digits}f}   "
              f"impulse {s['impulse_atr']:.2f} ATR ({s['class']}-step reading, "
              f"r={s['ratio']:.3f})  step {s['step'] / per:.1f} {unit} "
              f"({s['step'] / s['impulse'] * 3:.2f} ATR/step x3)   "
              f"rung3 {f3}   rung5 {f5}   zone {zone}")
        # The levels are printed whether or not they were touched, so a sample can
        # be checked on a chart by hand: an untouched rung and a missing rung look
        # identical in a table that only lists hits.
        for k in (3, 5):
            lvl = (s["pivot"] - k * s["step"] if s["kind"] == "H"
                   else s["pivot"] + k * s["step"])
            r = s["rungs"][k]
            if r:
                print(f"        rung {k}: level {lvl:.{digits}f}  touched "
                      f"{r['time']}  bounce {r['bounce_steps']:.2f} step "
                      f"({r['bounce_atr']:.2f} ATR of structure)")
            else:
                print(f"        rung {k}: level {lvl:.{digits}f}  never reached "
                      f"within 24 bars")

    res = {"symbol": symbol, "structure": structure, "trigger": trigger,
           "file": os.path.basename(spath), "unit": unit, "per": per,
           "legs": len(legs), "patterns": len(pats), "grid": g, "budget": bud,
           "consistency": cons, "step": m3, "excess": excess, "samples": ex,
           "source": spath}
    if out_dir:
        os.makedirs(out_dir, exist_ok=True)
        with open(os.path.join(out_dir, f"{symbol}.json"), "w", encoding="utf-8") as fh:
            json.dump(res, fh, ensure_ascii=False, indent=1)
    return res


def _epoch(text):
    """A printed bar clock back as an epoch, to index the trigger file by."""
    return int(datetime.strptime(text, "%Y-%m-%d %H:%M")
               .replace(tzinfo=timezone.utc).timestamp())


def main(argv):
    try:
        sys.stdout.reconfigure(encoding="utf-8", errors="replace")
    except Exception:
        pass
    if "--selftest" in argv:
        return 1 if selftest() else 0

    def num(flag, default):
        return int(argv[argv.index(flag) + 1]) if flag in argv else default

    syms = (argv[argv.index("--symbols") + 1] if "--symbols" in argv
            else "XAUUSD,EURUSD,GBPUSD").split(",")
    structure, trigger = num("--structure", 60), num("--trigger", 15)
    out = argv[argv.index("--out") + 1] if "--out" in argv else None

    if "--rung-band" in argv:
        zones = ([float(x) for x in argv[argv.index("--zone") + 1].split(",")]
                 if "--zone" in argv else (0.0, 1.0))
        thrs = ([float(x) for x in argv[argv.index("--thr") + 1].split(",")]
                if "--thr" in argv else (2 / 3.0, 1.0, 1.5, 2.0, 3.0))
        show_rung_band([s.strip() for s in syms], structure, trigger, zones,
                       num("--horizon", 24), num("--bounce", 6),
                       course=("--pivot" in argv and argv[argv.index("--pivot") + 1] == "course"),
                       thresholds=tuple(thrs))
        return 0

    if "--sweep-pivot" in argv:
        confirms = ([float(x) for x in argv[argv.index("--confirm") + 1].split(",")]
                    if "--confirm" in argv else (0.15, 0.25, 0.5, 1.0))
        show_pivot_sweep([s.strip() for s in syms], num("--structure", 60), confirms)
        return 0

    if "--pivot" in argv and argv[argv.index("--pivot") + 1] == "course":
        c = float(argv[argv.index("--confirm") + 1]) if "--confirm" in argv else 0.25
        print(f"the course's six-condition pivot, confirmation {c:.2f} ATR\n")
        for s in syms:
            instrument(s.strip(), structure, trigger, out, course=True,
                       confirm_atr=c)
        return 0

    if "--measure-tf" in argv:
        m_tf = num("--measure-tf", 15)
        mode = argv[argv.index("--mode") + 1] if "--mode" in argv else "extreme"
        r = measure_run(syms[0].strip(), structure, m_tf, mode)
        if r is None:
            print(f"  {syms[0]}: no usable overlap for TF{structure} measured on TF{m_tf}")
            return 1
        b, g, c = r["budget"], r["grid"], r["consistency"]
        nl = r["null"]
        print(f"  {syms[0].strip()} TF{structure} measured on TF{m_tf} ({mode}): "
              f"{r['s_bars']}+{r['m_bars']} bars -> {r['patterns']} patterns")
        it = r["identity"]
        print(f"  extreme identity vs the structure clock: compared {it['compared']}  "
              f"same {it['same']}  differ {it['differ']}  "
              f"incomplete coverage {it['incomplete']}")
        print(f"  cell error {b['cell_error']:.2f} cells vs tolerance {GRID_TOL:.2f}  -> "
              f"{'READABLE' if b['resolvable'] else 'TOO NOISY'}")
        print(f"  grid advantage {g['advantage']:+.1%} (chance {g['chance']:.0%})   "
              f"3-class {c['n3']}  5-class {c['n5']}   "
              + (f"ratio {c['ratio']:.2f}x  "
                 f"{'CONSISTENT' if 0.8 <= c['ratio'] <= 1.25 else 'INCONSISTENT'}"
                 if c.get("enough") else "too few on-grid patterns for a step claim")
              + (f"   chance agreement p={nl:.2f}" if nl is not None else ""))
        return 0

    if "--sweep-measure" in argv:
        pairs = [(1440, 240), (240, 60), (60, 30), (60, 15), (15, 5), (5, 1)]
        found = {m: show_measure_sweep([s.strip() for s in syms], pairs, m)
                 for m in ("extreme", "settled")}
        for mode, f in found.items():
            print(f"\n  first pairing passing BOTH checks in mode '{mode}': "
                  + (f"{f[0]} TF{f[1]} measured on TF{f[2]}" if f else "none"))
        return 0

    print(f"movement step read from the market's own retracements "
          f"(structure TF{structure}, trigger TF{trigger})")
    results = [r for r in (instrument(s.strip(), structure, trigger, out)
                           for s in syms) if r]
    print("\n--- summary ---")
    for r in results:
        g, b = r["grid"], r.get("budget", {})
        ok = "READABLE" if b.get("resolvable") else f"cell err {b.get('cell_error', 0):.1f}"
        if r.get("step") is None:
            print(f"  {r['symbol']:<8} no step claim ({r['patterns']} patterns, "
                  f"one-grid {g['any']:.0%}, {ok})")
            continue
        c = r["consistency"]
        agree = 0.8 <= c["ratio"] <= 1.25
        print(f"  {r['symbol']:<8} step3 {c['step3'] / r['per']:.1f} step5 "
              f"{c['step5'] / r['per']:.1f} {r['unit']:>3}  "
              f"3-vs-5 {c['ratio']:.2f}x {'OK' if agree else 'NO-STEP'}  "
              f"grid adv {g['advantage']:+.0%} (chance {g['chance']:.0%})  {ok}  "
              f"rung-3/5 excess {r['excess']:+.1%}")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
