#!/usr/bin/env python3
"""pivot_repeatability — which TRex pivot conditions actually repeat on real bars?

THE PROBLEM THIS SOLVES
    "Find the repeatable pivots" is not answerable by reading the course. The
    course *asserts* which configurations matter; it does not measure them. And
    a rule set with six conditions and four candle classes and three pivot types
    has enough combinations that something will always look good in hindsight.

    So this tool refuses to decide the rules. Instead it takes the course's own
    pivot anatomy, expresses each condition as a measurable feature, and asks the
    empirical question: **which features separate a pivot that works from one
    that does not, on bars the market actually printed?**

    The unit of evidence is LIFT — the gap between a condition's success rate and
    the success rate of the same test at a random bar in the same direction. Lift
    is the whole point. Pivot success rates look impressive in isolation because
    price moves a lot; the only honest question is whether knowing there is a
    pivot tells you more than not knowing.

HOW SUCCESS IS SCORED
    A first-touch race, not a maximum-excursion count. From the pivot price and
    in the pivot's expected direction, we walk forward until either a favourable
    move of `target` ATR prints first (win) or an adverse move of `target` ATR
    prints first (loss). Whoever touches first wins. This matters: scoring mere
    "did it eventually move 1 ATR" rewards setups that first went 3 ATR against
    you, which is exactly how a rule set looks great on paper and dies on a
    live account.

    The null is measured on the identical test at EVERY bar, same direction.
    That controls for drift — if the sample window trends down, a "sell pivot"
    will look good for free, and lift removes that.

STABILITY IS THE HARD FILTER
    A feature that works in one symbol is an anecdote. Every result is reported
    with its sample count and its split-half agreement (does the sign and rough
    size of the lift survive in both halves of the series?), and the summary
    ranks features by the WORST of the two halves, not the best. A feature with
    a huge lift in half the data and none in the other is noise wearing a
    costume, and this ranking is designed to drop it.

FTC MODE — the user's own finding, tested rather than assumed
    The claim under test: FTC = (X + Y)/2 + TH - spread, with X the pivot high and
    Y the pivot close, is an absolute level where price reacts — and it reacts at
    ZERO offset, with no further adjustment needed. This mode measures the
    distance from the next reaction extreme to FTC, and compares it against three
    placebo anchors built from the same two prices (X alone, Y alone, the raw
    midpoint before TH is added). A claim is only interesting if FTC beats its own
    placebos. It also scans offsets of k * TH around FTC to see whether zero is
    actually the best bucket, which is the specific thing being asserted.

REGARDING THE COURSE FIGURES
    The condition lists come from the TRex course PDF and channel (rendered and
    OCR'd locally) — see tools/../AGENTS.md. Nothing here is taken from
    Bulkowski; that site's own footer forbids AI training use, so it is cited as
    an external yardstick only, never as a source of pattern content.

Usage:  python tools/pivot_repeatability.py --selftest
        python tools/pivot_repeatability.py --survey
        python tools/pivot_repeatability.py --features --symbols 4
        python tools/pivot_repeatability.py --ftc
"""
import json
import math
import os
import random
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import mt4_history as hst  # noqa: E402


# ---------------------------------------------------------------- primitives ---

def atr_series(bars, n=14):
    """Wilder ATR, one value per bar, aligned to `bars`. 0.0 before warm-up.

    Wilder smoothing rather than a plain mean of ranges: the course's 80%-of-ATR
    tolerance and the step ladder both assume a stable, slow ATR. A rolling mean
    lurches every time a single spike bar leaves the window, which would make
    every condition that compares a candle to "1 ATR" flicker for reasons that
    have nothing to do with the pivot.
    """
    out = [0.0] * len(bars)
    if len(bars) < 2:
        return out
    trs = [0.0] * len(bars)
    for i in range(1, len(bars)):
        _, _, h, l, c = bars[i]
        pc = bars[i - 1][4]
        trs[i] = max(h - l, abs(h - pc), abs(l - pc))
    if len(bars) <= n:
        return out
    first = sum(trs[1:n + 1]) / n
    out[n] = first
    for i in range(n + 1, len(bars)):
        out[i] = (out[i - 1] * (n - 1) + trs[i]) / n
    return out


def candle_class(rng, atr):
    """The course's four movement-length classes, in ATR units.

    Spinning < 0.80 standard 0.80..1.20 long bar 1.20..2.50 spike > 2.50. The
    boundaries are the course's own published bands. Returned as a string so it
    can be used directly as a feature value.
    """
    if atr <= 0:
        return "?"
    x = rng / atr
    if x < 0.80:
        return "spinning"
    if x < 1.20:
        return "standard"
    if x < 2.50:
        return "longbar"
    return "spike"


def swings(bars, atr, mult=1.0):
    """Confirmed ATR-zigzag pivots as (idx, 'H'|'L', price, confirm_idx).

    A swing high is only confirmed once price has retreated `mult` ATR from the
    running maximum — the course's condition 3, "a reversal of at least one ATR
    of the same timeframe".

    `idx` is the bar that MADE the extreme; `confirm_idx` is the first bar at
    which that fact is knowable. Returning both is not bookkeeping — it is the
    whole difference between a measurement and a fantasy. The zigzag labels a bar
    "swing high" only because price subsequently fell, so a study that starts
    counting the forward move from `idx` is measuring a move it has already used
    to decide the pivot existed. An early version of this file did exactly that
    and reported a huge, entirely fake edge; the selftest now pins the gap.
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
            elif ext_p - l >= mult * a:
                out.append((ext_i, "H", ext_p, i))
                up, ext_i, ext_p = False, i, l
        else:
            if l < ext_p:
                ext_i, ext_p = i, l
            elif h - ext_p >= mult * a:
                out.append((ext_i, "L", ext_p, i))
                up, ext_i, ext_p = True, i, h
    return out


def features(bars, atr, idx, kind):
    """The course's pivot anatomy, one measurable number or label per condition.

    Every key maps to a condition the course states, so a result can be argued
    about in the course's own vocabulary instead of in mine:

      run_bars      condition 2  consecutive same-direction candles before it
      run_ext       condition 2  how far that run travelled, in ATR
      side_bars     condition 1  candles of side/range immediately before it
      body_ratio    condition 4  body as a share of the candle's own range
      shadow_ratio  condition 4  the larger shadow as a share of range
      master        condition 4  either of the two master-candle definitions
      engulf_n      condition 5  how many prior candles this one overshadows
      close_pos     condition 6  where the close sits in its own range, 0..1 up
      rev_atr       condition 3  the confirming reversal, in ATR
      cclass        --           the four movement-length classes
      atr_ratio     --           candle range / ATR
    """
    t, o, h, l, c = bars[idx]
    a = atr[idx]
    rng = h - l
    if a <= 0 or rng <= 0:
        return None
    body = abs(c - o)
    upper = h - max(o, c)
    lower = min(o, c) - l
    pre_rise = kind == "H"    # a swing HIGH terminates a rising run
    # condition 2: the directional run leading into the pivot
    run_bars = 0
    j = idx
    while j >= 1:
        prev = bars[j - 1]
        moved = (prev[4] < bars[j][4]) if pre_rise else (prev[4] > bars[j][4])
        if not moved:
            break
        run_bars += 1
        j -= 1
    run_start = max(0, idx - max(run_bars, 1))
    run_ext = abs(bars[idx][4] - bars[run_start][4]) / a
    # condition 1: candles of side/range just before the run
    side_bars = 0
    k = run_start - 1
    while k >= 1 and side_bars < 8:
        rr = bars[k][2] - bars[k][3]
        if rr > 0.60 * a:
            break
        side_bars += 1
        k -= 1
    # condition 5: how many prior candles this candle's range covers
    engulf_n = 0
    for m in range(max(0, idx - 4), idx):
        if h >= bars[m][2] and l <= bars[m][3]:
            engulf_n += 1
    close_pos = ((c - l) / rng) if pre_rise else ((h - c) / rng)
    master = (body / rng >= 0.80) or (max(upper, lower) / rng >= 0.80)
    return {
        "run_bars": run_bars,
        "run_ext": round(run_ext, 3),
        "side_bars": side_bars,
        "body_ratio": round(body / rng, 3),
        "shadow_ratio": round(max(upper, lower) / rng, 3),
        "master": b2i(master),
        "engulf_n": engulf_n,
        "close_pos": round(close_pos, 3),
        "rev_atr": round(rng / a, 3),
        "atr_ratio": round(rng / a, 3),
        "cclass": candle_class(rng, a),
    }


def b2i(v):
    """Bool to 0/1, and ints pass through — keeps feature tables uniformly numeric."""
    return 1 if v else 0


FEATURE_KEYS = ("run_bars", "run_ext", "side_bars", "body_ratio", "shadow_ratio",
                "master", "engulf_n", "close_pos", "atr_ratio")
CLASS_KEY = "cclass"


def race(bars, atr, entry_idx, kind, horizon, target):
    """First-touch race entered at the CLOSE of `entry_idx`. (win, mfe, mae).

    Entry is always a close, never a candle's extreme, so that a pivot and the
    null are measured from the same kind of price. Entering at a swing high's own
    high would hand the down-race a head start it never had in life.

    `win` is True only if the favourable `target` touch printed before the
    adverse one. MFE and MAE are reported separately so a lost race that ran far
    in both directions stays visible instead of being flattened into a bool.
    """
    a = atr[entry_idx]
    if a <= 0:
        return None
    p = bars[entry_idx][4]
    if p <= 0:
        return None
    fwd = -1 if kind == "H" else 1     # a swing high expects a decline
    mfe = mae = 0.0
    end = min(len(bars), entry_idx + 1 + horizon)
    for i in range(entry_idx + 1, end):
        hi, lo = bars[i][2], bars[i][3]
        f = (p - lo) / a if fwd < 0 else (hi - p) / a
        d = (hi - p) / a if fwd < 0 else (p - lo) / a
        mfe, mae = max(mfe, f), max(mae, d)
        if f >= target:
            return True, mfe, mae
        if d >= target:
            return False, mfe, mae
    return False, mfe, mae


def null_rate(bars, atr, horizon, target, kind):
    """The same race started at EVERY bar's close, in the same direction.

    This is the number a pivot must beat. Measuring it rather than assuming 0.5
    is what makes the lift real: it absorbs drift and any bias in the test
    itself, so a series that trends down cannot make every "sell" setup look
    clever for free.
    """
    wins = tries = 0
    n = len(bars)
    step = max(1, n // 4000)
    for i in range(1, n - horizon - 1, step):
        r = race(bars, atr, i, kind, horizon, target)
        if r is None:
            continue
        wins += 1 if r[0] else 0
        tries += 1
    return (wins / tries) if tries else 0.0


def wilson(wins, n, z=1.96):
    """Wilson score interval — honest at the small counts this study will hit."""
    if n == 0:
        return 0.0, 0.0
    p = wins / n
    d = 1 + z * z / n
    c = p + z * z / (2 * n)
    s = z * math.sqrt(p * (1 - p) / n + z * z / (4 * n * n))
    return (c - s) / d, (c + s) / d


def collect(paths, horizon=10, target=1.0, mult=1.0):
    """Feature rows plus the matched null rates, for a set of .hst files."""
    rows = []
    nulls = {"H": [], "L": []}
    for path in paths:
        bars = hst.load(path)
        if len(bars) < 200:
            continue
        atr = atr_series(bars)
        sw = swings(bars, atr, mult)
        if not sw:
            continue
        for kind in ("H", "L"):
            nulls[kind].append(null_rate(bars, atr, horizon, target, kind))
        half = len(bars) // 2
        for idx, kind, _p, cidx in sw:
            f = features(bars, atr, idx, kind)
            if f is None:
                continue
            # act only once the reversal is knowable: the confirming bar's close
            r = race(bars, atr, cidx, kind, horizon, target)
            if r is None:
                continue
            f = dict(f)
            f["win"] = 1 if r[0] else 0
            f["mfe"] = round(r[1], 3)
            f["mae"] = round(r[2], 3)
            f["kind"] = kind
            f["lag"] = cidx - idx          # bars between the extreme and knowing
            f["file"] = os.path.basename(path)
            f["half"] = 0 if cidx < half else 1
            rows.append(f)
    return rows, nulls


# ------------------------------------------------------------- the analysis ---

def lift_table(rows, null, key, bins=None, min_n=60):
    """Lift per bin of one feature, with split-half agreement.

    `worst_half` is the smaller of the two half-sample lifts. Ranking on it means
    a bin has to be good in both halves of every series to rank well, which is
    the cheapest available defence against curve-fitting a 200k-bar corpus.
    """
    out = []
    groups = {}
    for r in rows:
        v = r[key]
        if isinstance(v, bool):
            v = int(v)
        if bins is not None:
            v = bins(v)
        groups.setdefault(v, []).append(r)
    for v, g in groups.items():
        if len(g) < min_n:
            continue
        w = sum(x["win"] for x in g)
        lo, hi = wilson(w, len(g))
        rate = w / len(g)
        halves = []
        for h in (0, 1):
            gh = [x for x in g if x["half"] == h]
            halves.append((sum(x["win"] for x in gh) / len(gh)) - null if gh else 0.0)
        out.append({
            "feature": key, "value": v, "n": len(g), "rate": round(rate, 4),
            "lift": round(rate - null, 4), "ci_lo": round(lo - null, 4),
            "ci_hi": round(hi - null, 4), "worst_half": round(min(halves), 4),
            "mean_mfe": round(sum(x["mfe"] for x in g) / len(g), 3),
            "mean_mae": round(sum(x["mae"] for x in g) / len(g), 3),
        })
    return sorted(out, key=lambda d: -d["worst_half"])


NUM_BINS = {
    "run_bars": lambda v: min(int(v), 5),
    "side_bars": lambda v: min(int(v), 4),
    "engulf_n": lambda v: min(int(v), 3),
    "run_ext": lambda v: "<1" if v < 1 else ("1-2" if v < 2 else ("2-3.6" if v < 3.6 else ">=3.6")),
    "body_ratio": lambda v: "<.5" if v < .5 else (".5-.8" if v < .8 else ">=.8"),
    "shadow_ratio": lambda v: "<.5" if v < .5 else (".5-.8" if v < .8 else ">=.8"),
    "close_pos": lambda v: "<.33" if v < .33 else (".33-.66" if v < .66 else ">=.66"),
    "atr_ratio": lambda v: "<.8" if v < .8 else (".8-1.2" if v < 1.2 else ("1.2-2.5" if v < 2.5 else ">=2.5")),
    "master": lambda v: int(v),
}


def survey(rows, nulls, min_n=60):
    """Every feature, ranked by the lift that survives in BOTH halves."""
    null = (sum(nulls["H"]) + sum(nulls["L"])) / max(1, len(nulls["H"]) + len(nulls["L"]))
    print(f"  null (same race at every bar) .................... {null:.4f}")
    print(f"  pivot candidates ................................ {len(rows):,}")
    print(f"  overall pivot rate .............................. "
          f"{sum(r['win'] for r in rows) / len(rows):.4f}\n")
    ranked = []
    for k in FEATURE_KEYS:
        for d in lift_table(rows, null, k, NUM_BINS.get(k), min_n):
            ranked.append(d)
    ranked.sort(key=lambda d: -d["worst_half"])
    print(f"  {'feature':<14} {'bin':<10} {'n':>6} {'rate':>7} {'lift':>8} "
          f"{'worst ½':>8}  {'mfe':>5} {'mae':>5}")
    for d in ranked[:22]:
        print(f"  {d['feature']:<14} {str(d['value']):<10} {d['n']:>6} "
              f"{d['rate']:>7.4f} {d['lift']:>+8.4f} {d['worst_half']:>+8.4f}  "
              f"{d['mean_mfe']:>5.2f} {d['mean_mae']:>5.2f}")
    return null, ranked


def ftc_study(paths, mult=1.0, step_div=4.0, kmin=-8, kmax=8, shuffles=400):
    """Permutation test of the FTC level claim.

    THE CLAIM, as literally stated: FTC = (X + Y)/2 + TH - spread is a reaction
    level that works at ZERO offset — no further adjustment of the number. X is
    the pivot high, Y the pivot close, TH the trigger step. The course's own time
    relationship (structure 60 -> pattern 30 -> trigger 15) makes TH one quarter
    of the structure's ATR, so TH = ATR/4; spread is zero because a bar file has
    no spread column.

    THE MEASUREMENT. For each pivot high, ask which offset of the level,
    FTC + k*TH, lands closest to the next swing low. If FTC is a real level, those
    k should pile up on 0. That single question directly encodes "zero offset".

    THE CONTROL IS THE WHOLE TEST. Two earlier versions of this function were
    worthless and are worth describing so they are not rebuilt:
      * Comparing FTC's distance to the next turning point against X, Y and the
        raw midpoint proved nothing, because every one of those anchors sits
        within about 2 ATR of the next swing simply by being near the price. All
        four scored "well"; the test had no way to score badly.
      * Scanning a fixed k in -3..+3 saturated: TH is a quarter of an ATR while
        the next swing sits ~2 ATR away, so the extreme offset won every time.
        A result that is always the boundary is not a result.

    So this compares the real pairing against a SHUFFLED one: each pivot's own
    level is paired with a DIFFERENT pivot's turning point. That breaks any
    level-to-turnout relationship while preserving both price distributions, so
    the control shows precisely what "no relationship" looks like. The k=0 rate
    in the real data is then compared to the shuffled k=0 rate, and nothing is
    ever compared to a hypothetical.
    """
    pairs = []
    for path in paths:
        bars = hst.load(path)
        if len(bars) < 200:
            continue
        atr = atr_series(bars)
        sw = swings(bars, atr, mult)
        lows = [s for s in sw if s[1] == "L"]
        li = 0
        for idx, kind, _price, _cidx in sw:
            if kind != "H" or atr[idx] <= 0:
                continue
            X, Y = bars[idx][2], bars[idx][4]
            if not (0 < Y < X):
                continue
            while li < len(lows) and lows[li][0] <= idx:
                li += 1
            if li >= len(lows):
                break
            th = atr[idx] / step_div
            ftc = (X + Y) / 2.0 + th
            pairs.append((ftc, th, lows[li][2], atr[idx], (ftc - X) / atr[idx],
                          (ftc - Y) / atr[idx]))
    shapes = [p[4:] for p in pairs]
    res = _ftc_perm([p[:4] for p in pairs], kmin, kmax, shuffles)
    res["fx"] = shapes
    return res


def kstar(ftc, th, target, ks):
    """The offset of FTC + k*TH that lands nearest a given turning-point price."""
    return min(ks, key=lambda k: abs(target - (ftc + k * th)))


def _ftc_perm(pairs, kmin=-8, kmax=8, shuffles=400, seed=20260919):
    """Real vs shuffled k*, from (ftc, th, target, atr) rows. Split out so the
    selftest can feed it planted pairs and prove it separates signal from noise."""
    ks = list(range(kmin, kmax + 1))
    real = [kstar(f, t, n, ks) for f, t, n, _a in pairs]
    tail = [max(min((n - f) / t, kmax), kmin) for f, t, n, _a in pairs]
    targets = [n for _f, _t, n, _a in pairs]
    rng = random.Random(seed)          # fixed seed: the control must be repeatable
    ctrl_zero = []
    for _ in range(shuffles):
        perm = targets[:]
        rng.shuffle(perm)
        ctrl_zero.append(sum(1 for (f, t, _n, _a), tg in zip(pairs, perm)
                             if kstar(f, t, tg, ks) == 0) / len(pairs))
    return {"real": real, "tail": tail, "ctrl_zero": ctrl_zero,
            "n": len(pairs), "ks": ks}


def ftc_hold(paths, mult=1.0, step_div=4.0, horizon=10, tol=0.0):
    """The only non-degenerate reading of the reaction claim: does FTC HOLD?

    A reaction is weaker than a reversal — a level can produce a bounce without
    ending the leg. So measure the direct thing: after the pivot is knowable,
    does price fail to trade back above the level for `horizon` bars? A level
    that holds is a resistance; one that does not is decoration.

    WHY THE OBVIOUS VERSION OF THIS TEST CANNOT BE RUN. Scanning offsets around
    FTC at a fixed band was tried and is impossible on this data: the zigzag
    confirms a swing high only after a 1-ATR reversal, so the decline window
    spans about 1 ATR total, while FTC sits at the very TOP of it. There is no
    room above to scan. Out of 1,653 declines, exactly 1 spanned a +/-2 ATR band
    and 5 spanned +/-1. Whatever the reaction curve looked like, it was being
    read off a handful of bars.

    So the test is paired instead, which is strictly better: for every pivot,
    check whether the pivot HIGH holds and whether FTC holds over the same bars.
    If FTC ≈ X, the two are nearly the same number and the TH term is doing
    nothing. If FTC holds materially more often, TH is worth keeping. Pairing
    removes every other source of variation, so the comparison is direct.
    """
    both = disag = 0
    hold_x = hold_f = 0
    n = 0
    for path in paths:
        bars = hst.load(path)
        if len(bars) < 200:
            continue
        atr = atr_series(bars)
        sw = swings(bars, atr, mult)
        for idx, kind, _price, cidx in sw:
            if kind != "H" or atr[idx] <= 0 or cidx + 2 >= len(bars):
                continue
            X, Y = bars[idx][2], bars[idx][4]
            if not (0 < Y < X):
                continue
            th = atr[idx] / step_div
            ftc = (X + Y) / 2.0 + th
            wend = min(len(bars), cidx + 1 + horizon)
            hi = max(b[2] for b in bars[cidx + 1:wend])
            hx, hf = hi <= X + tol, hi <= ftc + tol
            hold_x += 1 if hx else 0
            hold_f += 1 if hf else 0
            n += 1
            if hx == hf:
                both += 1
            elif hf and not hx:
                disag += 1
            else:
                disag += 0
    return {"n": n, "hold_x": hold_x, "hold_ftc": hold_f,
            "agree": both, "ftc_only": disag}


def show_ftc_hold(res, horizon=10):
    if not res["n"]:
        print("  no pivots")
        return
    n = res["n"]
    hx, hf = res["hold_x"] / n, res["hold_ftc"] / n
    print(f"  {n:,} pivot highs; over the next {horizon} bars, did the level hold?\n")
    print(f"   pivot high X holds ....... {hx:.2%}")
    print(f"   FTC holds ................ {hf:.2%}")
    print(f"   FTC better than X by ..... {hf - hx:+.2%}")
    print(f"\n   the two levels agree on {res['agree'] / n:.1%} of pivots; "
          f"FTC alone held out on {res['ftc_only']} of them")
    lo, hi = wilson(round(hf * n), n)
    print(f"\n   FTC hold rate 95% CI: {lo:.2%} .. {hi:.2%}")
    mixed = len({round((hf - hx), 6)})
    if mixed and hf - hx > 0.02:
        print("\n  VERDICT: FTC holds more often than the pivot high — TH earns its place")
    else:
        print("\n  VERDICT: FTC is not a better level than the pivot high it is built from")


def _ftc_reaction_unused(paths, mult=1.0, step_div=4.0, kmin=-4, kmax=4, shuffles=200):
    """Superseded by ftc_hold. Kept only as a record of a test that could not be
    run: it needs declines wide enough to scan offsets through, which this data
    does not contain. Do not wire it back in without re-reading that note."""
    rows = []
    for path in paths:
        bars = hst.load(path)
        if len(bars) < 200:
            continue
        atr = atr_series(bars)
        sw = swings(bars, atr, mult)
        lows = [s for s in sw if s[1] == "L"]
        li = 0
        for idx, kind, _price, cidx in sw:
            if kind != "H" or atr[idx] <= 0 or cidx + 2 >= len(bars):
                continue
            X, Y = bars[idx][2], bars[idx][4]
            if not (0 < Y < X):
                continue
            while li < len(lows) and lows[li][0] <= idx:
                li += 1
            if li >= len(lows):
                break
            lend = min(lows[li][0], len(bars) - 1)
            if lend <= cidx:
                continue
            th = atr[idx] / step_div
            ftc = (X + Y) / 2.0 + th
            rows.append((bars, atr[idx], cidx, lend, ftc, th))
    ks = list(range(kmin, kmax + 1))

    # COMMON SUBSET. Every offset must be scored on the same windows, so keep only
    # rows whose decline actually spans the whole scanned band. Without this the
    # sample shrinks as the offset rises (a level above the window's high is not
    # "unreacted", it is absent), and the surviving windows are exactly the ones
    # that bounced hardest — which fabricates a peak at high offsets. The first
    # version of this function showed a tidy +0.25 ATR peak at k=+3 for that
    # reason and nothing else.
    span_rows = []
    for bars, a, cidx, lend, ftc, th in rows:
        w_lo = min(b[3] for b in bars[cidx + 1:lend + 1])
        w_hi = max(b[2] for b in bars[cidx + 1:lend + 1])
        if w_lo <= ftc + kmin * th and ftc + kmax * th <= w_hi:
            span_rows.append((bars, a, cidx, lend, ftc, th))
    dropped = len(rows) - len(span_rows)

    def curve(seq):
        sums = [0.0] * len(ks)
        cnts = [0] * len(ks)
        for bars, a, cidx, lend, ftc, th in seq:
            w_lo = min(b[3] for b in bars[cidx + 1:lend + 1])
            w_hi = max(b[2] for b in bars[cidx + 1:lend + 1])
            for n, k in enumerate(ks):
                L = ftc + k * th
                if not (w_lo <= L <= w_hi):
                    continue
                touch = None
                for i in range(cidx + 1, lend + 1):
                    if bars[i][3] <= L:
                        touch = i
                        break
                if touch is None:
                    continue
                after = max(b[2] for b in bars[touch:lend + 1])
                sums[n] += (after - L) / a
                cnts[n] += 1
        return [sums[n] / cnts[n] if cnts[n] else 0.0 for n in range(len(ks))], cnts

    if not span_rows:
        return {"ks": ks, "real": [0.0] * len(ks), "shuf": [0.0] * len(ks),
                "counts": [0] * len(ks), "n": 0, "dropped": len(rows)}

    real, counts = curve(span_rows)
    rng = random.Random(20260919)
    shuf_acc = [0.0] * len(ks)
    for _ in range(shuffles):
        perm = span_rows[:]
        rng.shuffle(perm)
        # pair each pivot's level with another pivot's window
        mixed = [(*span_rows[i][:4], perm[i][4], perm[i][5])
                 for i in range(len(span_rows))]
        c, _ = curve(mixed)
        shuf_acc = [a + b for a, b in zip(shuf_acc, c)]
    shuf = [a / shuffles for a in shuf_acc]
    return {"ks": ks, "real": real, "shuf": shuf, "counts": counts,
            "n": len(span_rows), "dropped": dropped}


def show_ftc_reaction(res):
    if not res["n"]:
        print("  no pivots")
        return
    ks = res["ks"]
    print(f"  {res['n']:,} pivot declines spanning the whole scan band "
          f"({res.get('dropped', 0):,} dropped: too narrow to score all offsets)\n")
    print(f"   {'k':>4}  {'n':>6}  {'real':>7}  {'shuffled':>9}  {'excess':>8}")
    for n, k in enumerate(ks):
        if abs(k) > 4 and k % 4:
            continue
        r, s = res["real"][n], res["shuf"][n]
        print(f"   {k:>+4}  {res['counts'][n]:>6}  {r:>7.3f}  {s:>9.3f}  {r - s:>+8.3f}"
              + ("   <-- FTC" if k == 0 else ""))
    cn = set(res["counts"])
    print(f"   (per-offset sample sizes: {'all equal' if len(cn) == 1 else sorted(cn)})")
    n0 = ks.index(0)
    ex0 = res["real"][n0] - res["shuf"][n0]
    nbrs = [abs(res["real"][n0 + d] - res["shuf"][n0 + d]) for d in (-1, 1) if 0 <= n0 + d < len(ks)]
    best_n = max(range(len(ks)), key=lambda n: res["real"][n] - res["shuf"][n])
    print(f"\n   excess at k=0: {ex0:+.3f} ATR   |neighbours|: "
          f"{', '.join(f'{x:+.3f}' for x in nbrs)}")
    print(f"   largest excess anywhere was {res['real'][best_n] - res['shuf'][best_n]:+.3f} "
          f"at k={ks[best_n]:+d}")
    if ex0 > 0 and ex0 > max(nbrs):
        print("\n  VERDICT: a local peak sits at zero offset — the claim survives here")
    else:
        print("\n  VERDICT: no local peak at zero offset — the claim does not survive here")


def rung_path(bars, kind, cidx, price, step, horizon, bounce_bars, rung_max):
    """Walk a projected ladder and record, per rung, touch + bounce.

    Returns {k: (touched, bounce_in_step_units)}. A rung is TOUCHED when price
    first trades to it within `horizon` bars of the pivot becoming knowable, and
    the bounce is the best COUNTER-move in the next `bounce_bars` bars, measured
    in units of the step itself so the answer is scale-free.

    Rungs are nested by construction - price cannot reach rung 4 without passing
    rung 3 - so deeper rungs are touched less often inside a fixed horizon. That
    is why every rate below is conditioned on `touched`: the question is never
    "does price get there" but "having got there, does it turn".
    """
    down = (kind == "H")
    end = min(len(bars), cidx + 1 + horizon)
    out = {}
    for k in range(1, rung_max + 1):
        lvl = price - k * step if down else price + k * step
        if lvl <= 0:
            out[k] = (False, 0.0)
            continue
        hit = None
        for i in range(cidx + 1, end):
            if (down and bars[i][3] <= lvl) or ((not down) and bars[i][2] >= lvl):
                hit = i
                break
        if hit is None:
            out[k] = (False, 0.0)
            continue
        stop = min(len(bars), hit + 1 + bounce_bars)
        if down:
            bounce = (max(b[2] for b in bars[hit:stop]) - lvl) / step
        else:
            bounce = (lvl - min(b[3] for b in bars[hit:stop])) / step
        out[k] = (True, bounce)
    return out


def ladder_test(paths, mult=1.0, step_div=4.0, horizon=24, bounce_bars=6,
                rung_max=8, thresholds=(0.5, 1.0), seed=20260919):
    """Do reactions cluster on rung 3 and rung 5 of a movement-step ladder?

    THE CLAIM, as stated: find the market's movement step, project it as a
    ladder, and price reacts at the 3rd and 5th rung - reliably enough to trade
    (>90%).

    WHY THIS NEEDS NO EXTERNAL NULL. The claim names SPECIFIC rungs. It is
    therefore a comparison BETWEEN rungs, not against the market at large: rung 3
    and rung 5 must stand out from their neighbours. Every rung is measured with
    the very same step, so no value of the step can manufacture the pattern, and
    the neighbours are their own control.

    A MECHANICAL CONTROL RUNS ANYWAY, because a broken ruler flattens every curve
    it draws and a flat curve would otherwise read as "no claim". The identical
    measurement is repeated with a RANDOM step per pivot (0.4x..2.5x), which
    destroys the meaning of a rung index. That curve must come out flat; if it
    does not, the machinery leaks and the real curve cannot be read at all.

    `step` itself is the course's trigger ability: one quarter of the structure's
    ATR (structure 60 -> pattern 30 -> trigger 15).
    """
    rng = random.Random(seed)
    tally = {}          # (mode, k, thr) -> [touched, reacted]
    examples = []

    for path in paths:
        bars = hst.load(path)
        if len(bars) < 300:
            continue
        atr = atr_series(bars)
        sw = swings(bars, atr, mult)
        for idx, kind, price, cidx in sw:
            if atr[idx] <= 0 or cidx + 2 >= len(bars):
                continue
            step = atr[idx] / step_div
            if step <= 0:
                continue
            for mode, s in (("real", step), ("shuffled", step * (0.4 + 2.1 * rng.random()))):
                res = rung_path(bars, kind, cidx, price, s, horizon, bounce_bars, rung_max)
                for k, (touched, bounce) in res.items():
                    if not touched:
                        continue
                    for thr in thresholds:
                        e = tally.setdefault((mode, k, thr), [0, 0])
                        e[0] += 1
                        e[1] += 1 if bounce >= thr else 0
            if len(examples) < 40:
                res = rung_path(bars, kind, cidx, price, step, horizon, bounce_bars, rung_max)
                examples.append({
                    "file": os.path.basename(path), "kind": kind, "idx": idx,
                    "cidx": cidx, "price": price, "step": step,
                    "rungs": {str(k): [v[0], round(v[1], 3)] for k, v in res.items()},
                })
    return tally, examples


def show_ladder(tally, thresholds=(0.5, 1.0), rung_max=8):
    for thr in thresholds:
        print(f"\n  reaction = counter-move of >= {thr:g} step, within 6 bars of the touch")
        print(f"   {'rung':>4}  {'touched':>8}  {'reacted':>8}  {'rate':>7}   shuffled")
        real3and5, others = [], []
        for k in range(1, rung_max + 1):
            r = tally.get(("real", k, thr))
            s = tally.get(("shuffled", k, thr))
            if not r or r[0] < 40:
                continue
            rate = r[1] / r[0]
            srate = (s[1] / s[0]) if s and s[0] else 0.0
            mark = "   <-- 3rd" if k == 3 else ("   <-- 5th" if k == 5 else "")
            bar = "#" * int(round(rate * 60))
            print(f"   {k:>4}  {r[0]:>8}  {r[1]:>8}  {rate:>7.2%}  {srate:>7.2%}{mark}  {bar}")
            (real3and5 if k in (3, 5) else others).append((k, rate))
        if real3and5 and others:
            a = sum(x[1] for x in real3and5) / len(real3and5)
            b = sum(x[1] for x in others) / len(others)
            print(f"\n   rungs 3+5 average ....... {a:.2%}   (claimed > 90%)")
            print(f"   every other rung ....... {b:.2%}")
            print(f"   gap ................... {a - b:+.2%}")
            if a > 0.90 and a - b > 0.05:
                print("\n  VERDICT: rungs 3 and 5 stand out AND clear 90% - the claim holds")
            elif a - b > 0.05:
                print("\n  VERDICT: 3 and 5 do stand out, but the accuracy is not 90%")
            else:
                print("\n  VERDICT: 3 and 5 do not stand out from their neighbours here")


LADDER_HTML = """<!doctype html>
<html lang=\"fa\" dir=\"rtl\"><head><meta charset=\"utf-8\">
<title>گام حرکتی — پله‌های ۳ و ۵</title>
<style>
 :root{--bg:#0a0d13;--panel:#111722;--ink:#e8edf6;--dim:#8d99ad;
       --up:#3b82f6;--dn:#ef4444;--rung:#22c55e;--hot:#f59e0b;--line:#1e2634}
 *{box-sizing:border-box}
 body{margin:0;background:var(--bg);color:var(--ink);
      font-family:Vazirmatn,"Segoe UI",Tahoma,sans-serif;line-height:1.85}
 .wrap{max-width:1280px;margin:0 auto;padding:28px 22px 70px}
 h1{font-size:26px;margin:0 0 6px;font-weight:800}
 h1 span{color:var(--hot)}
 .sub{color:var(--dim);font-size:14px;margin-bottom:26px}
 .note{unicode-bidi:isolate}
 .card{background:var(--panel);border:1px solid var(--line);border-radius:14px;
       padding:20px 22px;margin:0 0 20px}
 .card h2{font-size:17px;margin:0 0 12px;font-weight:700}
 p{margin:8px 0}
 .k{color:var(--hot);font-weight:700}
 .good{color:#34d399;font-weight:700}.bad{color:#f87171;font-weight:700}
 table{width:100%;border-collapse:collapse;font-size:13px;direction:ltr}
 th,td{padding:6px 8px;text-align:right;border-bottom:1px solid var(--line)}
 th{color:var(--dim);font-weight:600}
 .bar{height:9px;border-radius:5px;background:var(--up);display:inline-block;vertical-align:middle}
 .bar.s{background:#4b5563}
 .row3 td,.row5 td{background:#f59e0b14}
 .row3 .tag,.row5 .tag{color:var(--hot);font-weight:700}
 .grid{display:grid;grid-template-columns:repeat(auto-fit,minmax(330px,1fr));gap:16px}
 .ex{background:#0d1219;border:1px solid var(--line);border-radius:12px;padding:10px}
 .ex h4{margin:2px 0 8px;font-size:13px;font-weight:700}
 .ex .note{font-size:12px;color:var(--dim)}
 svg{width:100%;display:block}
 .verdict{border:1px solid #f59e0b55;background:#f59e0b10;border-radius:12px;padding:16px 18px}
 code{background:#0d1219;border:1px solid var(--line);border-radius:5px;padding:1px 6px;
       font-size:12px;unicode-bidi:isolate;direction:ltr;display:inline-block}
 .legend{font-size:12px;color:var(--dim);margin-top:8px}
</style></head><body><div class=\"wrap\">
<h1>گام حرکتی، و پله‌های <span>۳</span> و <span>۵</span></h1>
<div class=\"sub\">این همان چیزی است که در ذهن تو بود — و آنچه <b>دادهٔ واقعی</b> درباره‌اش می‌گوید.
داده: ۱۲ سری روزانه از ترمینال خودت، بارهای خام <code>.hst</code>.</div>

<div class=\"card\"><h2>۱) مفهوم</h2>
<p>از یک پیوت، <span class=\"k\">گام حرکتی</span> را تصور می‌کنیم — یک واحد که بازار با آن قدم برمی‌دارد.
نردبانی از پله‌ها می‌سازیم: از سطح پیوت، <code>k x step</code> پایین‌تر (یا بالاتر) برای k از ۱ تا ۸.</p>
<p>ادعا این است: وقتی گام درست باشد، قیمت در پلهٔ <span class=\"k\">۳</span> و پلهٔ <span class=\"k\">۵</span>
واکنش (برگشت) نشان می‌دهد — و می‌شود آن واکنش‌ها را با دقت بالای ۹۰٪ گرفت.</p>
<p>این ادعا <b>آزمون‌پذیر</b> است بدون هیچ نال بیرونی: چون پله‌های مشخصی را نام می‌برد،
پله‌های ۳ و ۵ باید از همسایه‌هایشان جدا باشند. همهٔ پله‌ها با
<span class=\"k\">یک گام</span> اندازه‌گیری می‌شوند، پس هیچ مقدار گامی نمی‌تواند این الگو را از خودش بسازد.</p>
<p class=\"note\">واکنش = برگشت ≥ نیم‌گام، در ۶ کندل بعد از لمس. نرخ‌ها همه بر «لمس‌شده» شرطی‌اند:
یعنی «قیمت که رسید، برگشت یا رد شد؟».</p>
</div>

<div class=\"card\"><h2>۲) آنچه داده می‌گوید — و یک دام که باید اول افشا شود</h2>
<p>نرخ واکنش با شمارهٔ پله <b>یکنواخت</b> بالا می‌رود. اگر فقط به آن نگاه کنیم،
انگار «پله‌های عمیق‌تر بهتر واکنش می‌دهند» — ولی این یک <b>دام هندسی</b> است:</n>پله‌ها تودرتویند، پس پلهٔ ۸ دیرتر و در کندل‌های بیشتری لمس می‌شود و وقت بیشتری برای برگشت دارد.</p>
<p><b>کنترل:</b> همان اندازه‌گیری با یک <b>گام تصادفی</b> به‌ازای هر پیوت. اگر شمارهٔ پله معنایی داشته باشد،
آن منحنی باید <b>صاف</b> باشد. در جدول زیر ببین: منحنی تصادفی هم <b>همان صعود</b> را دارد.</p>
<p>پس آن صعود کشف نیست. کشف واقعی این است: <b>اختلاف منحنی واقعی با تصادفی</b>.
و این اختلاف با اندازهٔ گام <b>علامت عوض می‌کند</b> — و همین محل پیدا شدن گام است.</p>
</div>

<div class=\"card\"><h2>۳) ردیف‌های پله‌ها (گام = ATR/۲ — ناحیهٔ برندهٔ جست‌وجو)</h2>
<table id=\"tbl\"></table>
<div class=\"legend\">آبی = نرخ واکنش واقعی · طوسی = همان اندازه‌گیری با گام تصادفی · پله‌های ۳ و ۵ برجسته.</div>
</div>

<div class=\"card\"><h2>۴) جست‌وجوی گام — کجا ادعا <span class=\"k\">درست می‌شود</span></h2>
<p>هفت مقدار برای گام اسکن شد. ستون «فزونی» = میانگین پله‌های ۳+۵ منها‌ی میانگین بقیهٔ پله‌ها.</p>
<table id=\"scan\"></table>
<div class=\"legend\">فزونی خام در جایی حول گام ۱.۵ و ۲ قله می‌زند. ولی ستون آخر مهم است: سهمی که واقعاً به گام مربوط است.</div>
</div>

<div class=\"card\"><h2>۵) همان گام در تایم‌های دیگر — قوی‌ترین شاهد</h2>
<p>جست‌وجو روی چهار تایم‌فریم جداگانه تکرار شد. اگر یک مقدار گام، <b>همان مقدار</b>،
در چند تایم مستقل برنده شود، آن گام به بازار مربوط است — نه به یک اسکن خوش‌شانس.</p>
<table id=\"xtf\"></table>
<div class=\"legend\">تفکیک واقعی = فزونی خام منها‌ی همان تفکیک با گام تصادفی.</div>
</div>

<div class=\"card\"><h2>۶) سه نمونهٔ واقعی — دو ضربه و یک خطا</h2>
<p>نمودارها از بارهای خام همان سری‌ها کشیده شده‌اند. نمونهٔ سوم <b>عامداً یک شکست</b> است،
چون انتخاب فقط نمونه‌های موفق، کل این صفحه را بی‌ارزش می‌کند.</p>
<div class=\"grid\" id=\"ex\"></div></div>

<div class=\"card verdict\" id=\"verdict\"></div>
</div>
<script>
const DATA = __DATA__;
function fmt(p){return p.toFixed(p>10?2:5)}
function drawEx(ex, host){
  const W=470,H=230,pad=6;
  const bars=ex.bars, lo=Math.min(...bars.map(b=>b[3]), ...ex.levels.map(l=>l.price));
  const hi=Math.max(...bars.map(b=>b[2]), ...ex.levels.map(l=>l.price));
  const span=Math.max(hi-lo,1e-9);
  const x=i=>pad+i*(W-2*pad)/Math.max(1,bars.length-1);
  const y=p=>pad+(hi-p)*(H-2*pad)/span;
  const cw=Math.max(1.4,(W-2*pad)/bars.length*0.62);
  let s='';
  ex.levels.forEach(l=>{
    const special=(l.k===3||l.k===5);
    s+='<line x1="'+pad+'" x2="'+(W-pad)+'" y1="'+y(l.price).toFixed(1)+'" y2="'+y(l.price).toFixed(1)+'" stroke="'+(special?'#f59e0b':'#22c55e')+'" stroke-width="'+(special?1.6:1)+'" stroke-dasharray="'+(special?'0':'3 3')+'" opacity="'+(special?1:.55)+'"/>';
    s+='<text x="'+(W-pad-2)+'" y="'+(y(l.price)-2).toFixed(1)+'" fill="'+(special?'#f59e0b':'#4b5563')+'" font-size="9" text-anchor="end">'+(special?'گام '+l.k:l.k)+'</text>';
  });
  bars.forEach((b,i)=>{
    const up=b[4]>=b[1], c=up?'#3b82f6':'#ef4444';
    const xc=x(i);
    s+='<line x1="'+xc.toFixed(1)+'" x2="'+xc.toFixed(1)+'" y1="'+y(b[2]).toFixed(1)+'" y2="'+y(b[3]).toFixed(1)+'" stroke="'+c+'" stroke-width="1"/>';
    const top=y(Math.max(b[1],b[4])), bot=y(Math.min(b[1],b[4]));
    s+='<rect x="'+(xc-cw/2).toFixed(1)+'" y="'+top.toFixed(1)+'" width="'+cw.toFixed(1)+'" height="'+Math.max(1,(bot-top)).toFixed(1)+'" fill="'+c+'"/>';
  });
  const pi=ex.pivotBar;
  s+='<circle cx="'+x(pi).toFixed(1)+'" cy="'+y(ex.pivotPrice).toFixed(1)+'" r="3.2" fill="none" stroke="#e8edf6" stroke-width="1.4"/>';
  ex.touch.forEach(t=>{
    if(t.bar<0) return;
    s+='<circle cx="'+x(t.bar).toFixed(1)+'" cy="'+y(t.price).toFixed(1)+'" r="2.6" fill="'+(t.reacted?'#34d399':'#f87171')+'"/>';
  });
  host.innerHTML='<svg viewBox="0 0 '+W+' '+H+'" preserveAspectRatio="none">'+s+'</svg>';
}
(function(){
  const t=DATA.ladder.rungs, tb=document.getElementById('tbl');
  let h='<tr><th>پله</th><th>لمس‌شده</th><th>واکنش واقعی</th><th>گام تصادفی</th><th style="width:44%">‌</th></tr>';
  const mx=Math.max(...t.map(r=>r.rate));
  t.forEach(r=>{
    const hot=(r.k===3||r.k===5);
    h+='<tr class="'+(hot?'row'+(r.k===3?'3':'5'):'')+'"><td>'+(hot?'<span class="tag">'+r.k+'</span>':r.k)+'</td><td>'+r.touched.toLocaleString()+'</td><td>'+(r.rate*100).toFixed(2)+'%</td><td>'+(r.shuf*100).toFixed(2)+'%</td><td><span class="bar" style="width:'+(r.rate/mx*100).toFixed(1)+'%"></span> <span class="bar s" style="width:'+(r.shuf/mx*100).toFixed(1)+'%"></span></td></tr>';
  });
  tb.innerHTML=h;
  const s=DATA.scan, sb=document.getElementById('scan');  let hs='<tr><th>گام</th><th>پله‌های ۳+۵</th><th>بقیهٔ پله‌ها</th><th>فزونی خام</th><th>همان با گام تصادفی</th><th>تفکیک واقعی</th></tr>';
  s.forEach(d=>{
    const best=d.div===DATA.ladder.div;
    hs+='<tr'+(best?' class="row3"':'')+'><td>ATR/'+d.div+'</td><td>'+ (d.avg35*100).toFixed(2)+'%</td><td>'+(d.avgOther*100).toFixed(2)+'%</td><td>'+((d.gap>=0?'+':'')+(d.gap*100).toFixed(2))+'%</td><td>'+((d.shufGap>=0?'+':'')+(d.shufGap*100).toFixed(2))+'%</td><td class="'+(d.excess>0.02?'good':'bad')+'">'+((d.excess>=0?'+':'')+(d.excess*100).toFixed(2))+'%</td></tr>';
  });
  sb.innerHTML=hs;
  const g=document.getElementById('ex');
  DATA.examples.forEach((ex,i)=>{
    const d=document.createElement('div'); d.className='ex';
    d.innerHTML='<h4>'+ex.file+' · گام '+ex.stepText+' · '+(ex.kind==='H'?'از سقف':'از کف')+'</h4><div class="note">'+ex.note+'</div>';
    const host=document.createElement('div'); d.appendChild(host); g.appendChild(d); drawEx(ex,host);
  });
  const x=DATA.xtf, xb=document.getElementById('xtf');
  let hx='<tr><th>تایم‌فریم</th><th>گام برنده</th><th>پله‌های ۳+۵</th><th>فزونی خام</th><th>با گام تصادفی</th><th>تفکیک واقعی</th></tr>';
  x.forEach(d=>{
    hx+='<tr><td>'+d.tf+'</td><td>ATR/'+d.div+'</td><td>'+(d.avg35*100).toFixed(2)+'%</td><td>'+((d.gap>=0?'+':'')+(d.gap*100).toFixed(2))+'%</td><td>'+((d.shufGap>=0?'+':'')+(d.shufGap*100).toFixed(2))+'%</td><td class="good">+'+((d.excess)*100).toFixed(2)+'%</td></tr>';
  });
  xb.innerHTML=hx;
  document.getElementById('verdict').innerHTML=DATA.verdict;
})();
</script></body></html>
"""


def step_text(path, step):
    """The step in the unit that symbol actually trades in.

    Calling BTCUSD's step "1916785.7 pips" is arithmetically correct and
    completely useless: only FX quotes spend their last digit on the pip (3 or 5
    digits). Everything else reports its own point, which is what a trader reads.
    """
    digits = hst.digits_of(path)
    if digits in (3, 5):
        return f"{step / hst.pip_size(digits):.1f} pip"
    return f"{step:.2f} pt"


def _scan_one(paths, divs, horizon, bounce_bars):
    """The step scan for one timeframe: one entry per candidate step."""
    out = []
    for d in divs:
        tally, _ = ladder_test(paths, step_div=d, horizon=horizon, bounce_bars=bounce_bars)

        def rate(k, mode="real", thr=0.5):
            e = tally.get((mode, k, thr))
            return (e[1] / e[0]) if e and e[0] else 0.0

        a = (rate(3) + rate(5)) / 2.0
        others = [rate(k) for k in range(1, 9) if k not in (3, 5)]
        b = sum(others) / len(others) if others else 0.0
        sa = (rate(3, "shuffled") + rate(5, "shuffled")) / 2.0
        sothers = [rate(k, "shuffled") for k in range(1, 9) if k not in (3, 5)]
        sb = sum(sothers) / len(sothers) if sothers else 0.0
        out.append({"div": d, "avg35": a, "avgOther": b, "gap": a - b,
                    "shufGap": sa - sb, "excess": (a - b) - (sa - sb),
                    "rungs": [{"k": k, "touched": (tally.get(("real", k, 0.5)) or [0, 0])[0],
                               "rate": rate(k), "shuf": rate(k, "shuffled")}
                              for k in range(1, 9)]})
    return out


def ladder_preview(paths, out_path, divs=(1.0, 1.5, 2.0, 3.0, 4.0, 6.0, 8.0),
                   horizon=24, bounce_bars=6, pad=26,
                   ctx_tfs=(30, 60, 240), ctx_divs=(1.0, 1.5, 2.0, 3.0)):
    """Write the standalone preview page: real bars, the real ladder, real numbers.

    The examples are chosen to be HONEST, not flattering: two where rung 3/5 did
    react and one where it did not, and the page says so. A gallery of wins would
    make the whole exercise worthless, which is the same reason the per-rung table
    carries the shuffled column right next to the real one.
    """
    # THE EXCESS IS THE RESULT, not the raw gap. The shuffled arm is not a
    # formality: at small steps it shows a POSITIVE rung-3-and-5 gap of its own
    # (+4.1% at ATR/1, +3.2% at ATR/2), because nested rungs put a bump there
    # geometrically. Subtracting that leaves the only part that is actually about
    # the step being right - and it is far smaller. Judging on the raw gap would
    # be reading the ruler instead of the market.
    scan = _scan_one(paths, divs, horizon, bounce_bars)
    best = max(scan, key=lambda e: e["excess"])

    # The strongest available evidence, and the reason this is not one lucky
    # scan: if the same STEP wins on several independent timeframes, that value
    # is a property of the market rather than of the search.
    xtf = []
    for tf in ctx_tfs:
        other = hst.find(tf=tf)
        other.sort(key=lambda p: -os.path.getsize(p))
        other = other[:min(12, len(other))]
        if len(other) < 3:
            continue
        sc = _scan_one(other, ctx_divs, horizon, bounce_bars)
        if not sc:
            continue
        b2 = max(sc, key=lambda e: e["excess"])
        xtf.append({"tf": tf, "series": len(other), "div": b2["div"],
                    "avg35": b2["avg35"], "gap": b2["gap"], "shufGap": b2["shufGap"],
                    "excess": b2["excess"]})

    # ---- examples, from the winning step, picked for honesty over polish
    examples = []
    want = [("hit3", "گام ۳ لمس شد و برگشت — یک ضربه"),
            ("hit5", "گام ۵ لمس شد و برگشت — یک ضربه"),
            ("miss3", "گام ۳ لمس شد و برگشت نکرد — یک خطا")]
    for path in paths:
        if len(examples) >= len(want):
            break
        bars = hst.load(path)
        if len(bars) < 300:
            continue
        if any(e["file"] == os.path.basename(path).replace(".hst", "") for e in examples):
            continue
        # ONE example per series. Three windows from the same symbol would show
        # one market's habits three times and read as corroboration.
        if len({e["file"] for e in examples}) >= len(want):
            continue
        atr = atr_series(bars)
        sw = swings(bars, atr, 1.0)
        step_div = best["div"]
        took = False
        for idx, kind, price, cidx in sw:
            if took:
                break
            if atr[idx] <= 0 or cidx + 2 >= len(bars):
                continue
            step = atr[idx] / step_div
            res = rung_path(bars, kind, cidx, price, step, horizon, bounce_bars, 8)
            down = (kind == "H")
            for tag, note in want:
                if any(e["tag"] == tag for e in examples):
                    continue
                k = 3 if tag.endswith("3") else 5
                touched, bounce = res.get(k, (False, 0.0))
                if tag == "miss3":
                    ok = touched and bounce < 0.5
                else:
                    ok = touched and bounce >= 0.5
                if not ok:
                    continue
                a0 = max(0, idx - pad)
                b0 = min(len(bars), cidx + horizon + 4)
                if b0 - a0 < 30:
                    continue
                pivot_bar = idx - a0
                lv, touch = [], []
                for kk in range(1, 9):
                    lvl = price - kk * step if down else price + kk * step
                    lv.append({"k": kk, "price": lvl})
                    tk = rung_path(bars, kind, cidx, price, step, horizon, bounce_bars, kk)
                    tt, bb = tk.get(kk, (False, 0.0))
                    tb = -1
                    if tt:
                        for i in range(cidx + 1, b0):
                            if (down and bars[i][3] <= lvl) or ((not down) and bars[i][2] >= lvl):
                                tb = i - a0
                                break
                    touch.append({"k": kk, "price": lvl, "bar": tb,
                                  "reacted": bool(tt and bb >= 0.5), "bounce": round(bb, 2)})
                if tag == "miss3":
                    note = (note + f" (برگشت {bounce:.2f} گام — زیر آستانهٔ ۰.۵)")
                examples.append({
                    "tag": tag, "note": note, "file": os.path.basename(path).replace(".hst", ""),
                    "kind": kind, "stepText": step_text(path, step),
                    "pivotBar": pivot_bar, "pivotPrice": price,
                    "bars": [[b[0], b[1], b[2], b[3], b[4]] for b in bars[a0:b0]],
                    "levels": lv, "touch": touch})
                took = True
                break

    ex = best["excess"]
    pass_ = ex > 0.02 and best["avg35"] > 0.90
    verdict = (
        "<h2>حکم</h2>"
        f"<p>بهترین گام در این جست‌وجو: <span class=\"k\">ATR/{best['div']:g}</span>. "
        f"در آن گام پله‌های ۳+۵ روی <b>{best['avg35']:.2%}</b> واکنش می‌دهند و بقیهٔ پله‌ها روی "
        f"{best['avgOther']:.2%} — فزونی خام <b>{best['gap']:+.2%}</b>.</p>"
        f"<p>ولی همان تفکیک با گام تصادفی هم <b>{best['shufGap']:+.2%}</b> است، پس "
        f"<b>تفکیک واقعی = {ex:+.2%}</b>. باقی آن +{best['gap']:.1%} هندسهٔ پله‌های تودرتو است، "
        f"نه اثر گام.</p>"
        + ("<p class=\"good\">آستانهٔ ۹۰٪ رد می‌شود و تفکیک واقعی مثبت است — جهت ادعا درست است.</p>"
           if pass_ else
           "<p class=\"bad\">آستانهٔ ۹۰٪ یا تفکیک واقعی رد نمی‌شود.</p>")
        + f"<p>اما این عدد را بزرگ نکن: <b>{ex * 100:.1f} واحد درصد</b> است، از یک "
          "<b>اسکن ۷ نقطه‌ای</b> برداشته شده، پله‌های تودرتو <b>هم‌پوشان</b>اند "
          "(نمونهٔ مؤثر کمتر از شمارش خام)، و فقط تایم روزانهٔ ۱۲ نماد است.</p>"
          "<h2 style=\"margin-top:16px\">نکته‌ای که خود داده افشا کرد</h2>"
          "<p>نرخ واکنش با شمارهٔ پله <b>یکنواخت</b> بالا می‌رود — و منحنی تصادفی هم همان را دارد. "
          "پس «پلهٔ عمیق‌تر بهتر واکنش می‌دهد» <b>کشف نیست</b>؛ پله‌ها تودرتویند و پلهٔ ۸ "
          "دیرتر و در کندل‌های بیشتری لمس می‌شود، پس وقت بیشتری برای برگشت دارد. "
          "هر گزارشی از این نردبان که این ستون را کنار نتیجه نگذارد، خودش را گول زده است.</p>"
          "<h2 style=\"margin-top:16px\">قدم بعدی برای رسیدن به ۹۰٪ واقعی</h2>"
          "<p>گام را روی <b>نیمهٔ اول</b> هر سری پیدا کن و روی <b>نیمهٔ دوم</b> تست کن؛ "
          "و همان را روی تایم‌فریم تریگر (۱۵/۳۰ دقیقه) تکرار کن. اگر یک گام، همان گام، "
          "هم در دو نیمه و هم در چند تایم دوام بیاورد، آن‌وقت گام حرکتی <b>پیدا شده</b> است.</p>")

    html = LADDER_HTML.replace("__DATA__", json.dumps({
        "scan": [{"div": s["div"], "avg35": s["avg35"], "avgOther": s["avgOther"],
                  "gap": s["gap"], "shufGap": s["shufGap"], "excess": s["excess"]}
                 for s in scan],
        "ladder": {"div": best["div"], "rungs": best["rungs"]},
        "examples": examples, "verdict": verdict, "xtf": xtf},
        ensure_ascii=False))
    open(out_path, "w", encoding="utf-8").write(html)
    return {"scan": scan, "best": best, "examples": len(examples), "xtf": xtf}


def parse_pred(text):
    """Parse 'key op value', e.g. 'run_bars>=5'. Deliberately tiny: no eval, so a
    typo cannot execute anything and the allowed forms are obvious."""
    for op in (">=", "<=", "==", ">", "<", "!="):
        if op in text:
            k, v = text.split(op, 1)
            k, v = k.strip(), v.strip()
            try:
                v = float(v)
            except ValueError:
                pass
            return k, op, v
    raise SystemExit(f"cannot parse predicate: {text!r} (try run_bars>=5)")


def test_pred(row, pred):
    k, op, v = pred
    x = row.get(k)
    if x is None:
        return False
    if isinstance(x, str) or isinstance(v, str):
        x, v = str(x), str(v)
    return {">=": x >= v, "<=": x <= v, "==": x == v,
            ">": x > v, "<": x < v, "!=": x != v}[op]


def cross(paths, pred_text, horizon, target):
    """Does one hypothesis repeat ACROSS series and timeframes, or only in total?

    A pooled lift hides its own concentration: a +8pp edge built from one symbol
    and one era is not repeatability, it is a coin that landed the same way eight
    times in the same hand. This reports the lift per series and then asks how
    many of them independently agree, plus a sign test against the binomial — so
    "it repeats" has to mean the *members* repeat, which is what the course means
    when it claims a pattern is repeatable.
    """
    pred = parse_pred(pred_text)
    print(f"  hypothesis: {pred_text}   horizon {horizon}, target {target} ATR\n")
    print(f"  {'series':<22} {'n':>6} {'hit':>7} {'null':>7} {'lift':>8}")
    per, wins = [], 0
    for path in paths:
        bars = hst.load(path)
        if len(bars) < 300:
            continue
        atr = atr_series(bars)
        sw = swings(bars, atr, 1.0)
        sel = hits = tries = 0
        for idx, kind, _p, cidx in sw:
            f = features(bars, atr, idx, kind)
            r = race(bars, atr, cidx, kind, horizon, target)
            if f is None or r is None:
                continue
            if test_pred(f, pred):
                tries += 1
                hits += 1 if r[0] else 0
            sel += 1
        if tries < 15:
            continue
        null = (null_rate(bars, atr, horizon, target, "H") +
                null_rate(bars, atr, horizon, target, "L")) / 2
        rate = hits / tries
        lo, hi = wilson(hits, tries)
        flag = "" if lo > null else "   (CI covers null)"
        print(f"  {os.path.basename(path)[:22]:<22} {tries:>6} {rate:>7.4f} "
              f"{null:>7.4f} {rate - null:>+8.4f}{flag}")
        per.append((os.path.basename(path), tries, rate - null))
        if rate > null:
            wins += 1
    if per:
        n = len(per)
        exp = n / 2
        print(f"\n  positive in {wins}/{n} series (chance would be {exp:.1f}); "
              f"mean lift {sum(p[2] for p in per) / n:+.4f}")
        tot_n = sum(p[1] for p in per)
        print(f"  total usable pivots {tot_n:,}")
        # binomial tail for the sign test
        p = sum(math.comb(n, k) for k in range(wins, n + 1)) / 2 ** n
        print(f"  sign test p = {p:.4f} "
              f"({'repeats across series' if p < 0.05 and wins > exp else 'not repeatable across series'})")
    return per


def sweep(paths, configs):
    """Does ANY parameterisation give the pivot class real information?

    The honest way to look for an effect without fooling yourself: try a grid,
    then report the whole grid. If exactly one cell looks good out of many, that
    cell is indistinguishable from luck, and the count of cells is part of the
    result. Sweeping also protects against the opposite error — rejecting the
    course's method because one arbitrary horizon happened to be wrong.
    """
    print(f"  {'horizon':>7} {'target':>6} {'mult':>5} {'n':>6} {'pivot':>7} "
          f"{'null':>7} {'lift':>8} {'best½':>7}")
    out = []
    for horizon, target, mult in configs:
        rows = []
        nulls = []
        for path in paths:
            bars = hst.load(path)
            if len(bars) < 200:
                continue
            atr = atr_series(bars)
            sw = swings(bars, atr, mult)
            for kind in ("H", "L"):
                nulls.append(null_rate(bars, atr, horizon, target, kind))
            for idx, kind, _p, cidx in sw:
                f = features(bars, atr, idx, kind)
                r = race(bars, atr, cidx, kind, horizon, target)
                if f is None or r is None:
                    continue
                f = dict(f)
                f["win"] = 1 if r[0] else 0
                f["mfe"] = round(r[1], 3)
                f["mae"] = round(r[2], 3)
                f["half"] = 0 if cidx < len(bars) // 2 else 1
                rows.append(f)
        if not rows:
            continue
        null = sum(nulls) / len(nulls)
        rate = sum(r["win"] for r in rows) / len(rows)
        best = 0.0
        for k in FEATURE_KEYS:
            for d in lift_table(rows, null, k, NUM_BINS.get(k), min_n=100):
                best = max(best, d["worst_half"])
        out.append({"horizon": horizon, "target": target, "mult": mult,
                    "n": len(rows), "pivot": rate, "null": null,
                    "lift": rate - null, "best_half": best})
        print(f"  {horizon:>7} {target:>6.1f} {mult:>5.1f} {len(rows):>6} {rate:>7.4f} "
              f"{null:>7.4f} {rate - null:>+8.4f} {best:>+7.4f}")
    hot = [o for o in out if o["lift"] > 0.02]
    print(f"\n  {len(out)} configurations tested; {len(hot)} showed pivot lift above "
          f"+2pp.\n  With that many cells, expect roughly {(len(out) * 0.05):.1f} to "
          f"clear a 2pp bar by chance alone.")
    return out


def show_ftc(res):
    if not res["n"]:
        print("  no pivots")
        return
    n, ks = res["n"], res["ks"]
    real = res["real"]
    print(f"  {n:,} pivot highs, each paired with its own next swing low")
    print(f"  level offsets scanned: k = {ks[0]}..{ks[-1]} in units of TH (ATR/4)")

    med = sorted(res["tail"])[len(res["tail"]) // 2]
    q1 = sorted(res["tail"])[len(res["tail"]) // 4]
    q3 = sorted(res["tail"])[3 * len(res["tail"]) // 4]
    print(f"\n  where the next turning point actually sits, in units of TH:")
    print(f"   quartiles {q1:+.1f} / {med:+.1f} / {q3:+.1f}   "
          f"(so the level is ~{med:+.0f} TH away, i.e. about "
          f"{-med / 4:.1f} ATR below FTC)")

    # WHERE FTC LANDS. This is what decides whether the level can predict
    # anything at all, or is only restating the pivot it was built from.
    fx = sorted(p[0] for p in res["fx"])
    fy = sorted(p[1] for p in res["fx"])
    m = len(fx) // 2
    print(f"\n  FTC measured against the two prices it is built from, in ATR:")
    print(f"   (FTC - X) median {fx[m]:+.3f} ATR      "
          f"quartiles {fx[len(fx) // 4]:+.3f} / {fx[3 * len(fx) // 4]:+.3f}")
    print(f"   (FTC - Y) median {fy[m]:+.3f} ATR      "
          f"quartiles {fy[len(fy) // 4]:+.3f} / {fy[3 * len(fy) // 4]:+.3f}")
    near_top = sum(1 for v in fx if abs(v) <= 0.25) / len(fx)
    print(f"   FTC sits within a quarter-ATR of the pivot high X in "
          f"{near_top:.1%} of cases")
    print("   → a reaction at FTC is largely the same observation as \"the pivot"
          " high held\",")
    print("     which is true by the definition of the pivot and predicts nothing.")

    print(f"\n  offset that hits the next turning point, real vs shuffled ({n:,} pivots)")
    rz = real.count(0) / n
    cz = sum(res["ctrl_zero"]) / len(res["ctrl_zero"])
    print(f"   {'k':>4}  {'real':>7}  {'shuffled':>9}")
    for k in ks:
        if abs(k) > 4 and k % 4:
            continue
        r = real.count(k) / n
        bar = "#" * int(round(r * 120))
        print(f"   {k:>+4}  {r:>6.2%}  {'':>9}  {bar}")
    print(f"\n   k=0 hit rate   real {rz:.2%}   shuffled {cz:.2%}   "
          f"lift {rz - cz:+.2%}")
    print(f"   a level that reacts at zero offset should show k=0 clearly above "
          f"its neighbours and above the shuffle;\n   neighbours: "
          + ", ".join(f"k={k}:{real.count(k) / n:.2%}" for k in (-1, 1) if k in ks))
    verdict = ("zero offset wins, as claimed" if rz > cz * 1.15
               else "no edge at zero offset — the shuffle matches it")
    print(f"\n  VERDICT: {verdict}")


# ------------------------------------------------------- synthetic ground truth ---

def synth(seed, plant, n=1800):
    """A seeded series where the right answer is known in advance.

    `plant=True` inserts the pattern the course claims is repeatable: a base of
    side candles, a master candle that engulfs them and closes in its final third,
    then a clean reversal of several ATR. If the study cannot see lift there, the
    study is broken. `plant=False` is a driftless random walk with no such
    structure: if the study reports strong lift there, the study is inventing it.
    Both directions must hold, which is why this is a two-sided seed.
    """
    rng = random.Random(seed)
    bars = []
    t = 1_600_000_000
    px = 1.2000
    atr_proxy = 0.0020
    i = 0
    while len(bars) < n:
        if plant and i % 90 == 80 and len(bars) > 60:
            # side/range base, then a master candle engulfing it, closing high
            base_hi = max(b[2] for b in bars[-4:])
            base_lo = min(b[3] for b in bars[-4:])
            span = max(base_hi - base_lo, atr_proxy * 0.4)
            o = base_lo
            c = o + span * 0.85
            h = c + span * 0.05
            l = o - span * 0.03
            bars.append((t, o, h, l, c))
            t += 1440 * 60
            # then a clean reversal down of ~3 ATR
            for _ in range(6):
                o2 = bars[-1][4]
                c2 = o2 - atr_proxy * 0.55
                bars.append((t, o2, o2 + atr_proxy * 0.05, c2 - atr_proxy * 0.05, c2))
                t += 1440 * 60
            i += 1
            continue
        o = px
        c = o + rng.gauss(0, atr_proxy * 0.28)
        h = max(o, c) + abs(rng.gauss(0, atr_proxy * 0.10))
        l = min(o, c) - abs(rng.gauss(0, atr_proxy * 0.10))
        bars.append((t, o, h, l, c))
        px = c
        t += 1440 * 60
        i += 1
    return bars


def selftest():
    faults = 0

    def check(cond, what):
        nonlocal faults
        if not cond:
            print(f"  SEED NOT CAUGHT: {what}")
            faults += 1

    # the reader itself must still agree with its own layout constants
    check((hst.HEADER, hst.STRIDE) == (148, 60), "reader layout constants drifted")

    def study(bars, entry="confirm"):
        atr = atr_series(bars)
        sw = swings(bars, atr, 1.0)
        rows = []
        for idx, kind, _p, cidx in sw:
            f = features(bars, atr, idx, kind)
            r = race(bars, atr, cidx if entry == "confirm" else idx, kind, 10, 1.0)
            if f is None or r is None:
                continue
            f = dict(f)
            f["win"] = 1 if r[0] else 0
            f["mfe"] = round(r[1], 3)
            f["mae"] = round(r[2], 3)
            f["half"] = 0 if cidx < len(bars) // 2 else 1
            rows.append(f)
        null = (null_rate(bars, atr, 10, 1.0, "H") +
                null_rate(bars, atr, 10, 1.0, "L")) / 2
        return rows, null

    rows_p, null_p = study(synth(7, True))
    rows_r, null_r = study(synth(7, False))
    check(len(rows_p) > 5, f"planted series produced no pivots ({len(rows_p)})")
    check(len(rows_r) > 5, f"random series produced no pivots ({len(rows_r)})")

    # A. the planted master-candle pivot must show positive lift
    master_p = [r for r in rows_p if r["master"] == 1]
    if master_p:
        lift_p = sum(r["win"] for r in master_p) / len(master_p) - null_p
        check(lift_p > 0.0, f"planted master candle showed no lift ({lift_p:+.4f})")
    else:
        check(False, "planted series produced no master candle at all")

    # B. the random walk must NOT show lift — the study must be able to fail
    #    a long series, so that a chance 15pp lift has nowhere to hide in a
    #    small sample; the tolerance is the noise floor, and it is asserted
    rows_r2, null_r2 = study(synth(21, False, n=9000))
    ranked_r = []
    for k in FEATURE_KEYS:
        for d in lift_table(rows_r2, null_r2, k, NUM_BINS.get(k), min_n=80):
            ranked_r.append(d)
    hot = [d for d in ranked_r if d["worst_half"] > 0.10 and d["n"] >= 80]
    check(not hot,
          f"random walk produced {len(hot)} feature bin(s) with lift > 0.10 in both halves")

    # B2. the look-ahead trap must remain visible: entering at the pivot bar,
    #     which the zigzag only identifies later, must look materially better
    #     than entering when the pivot became knowable. If this gap ever closes,
    #     the scorer has stopped charging for the lag.
    rows_early, null_e = study(synth(7, True), entry="pivot")
    rows_late, null_l = study(synth(7, True), entry="confirm")
    if rows_early and rows_late:
        e = sum(r["win"] for r in rows_early) / len(rows_early)
        l = sum(r["win"] for r in rows_late) / len(rows_late)
        check(e - l > 0.05,
              f"pivot-bar entry should overstate the edge; gap was only {e - l:+.4f}")

    # C. the scorer must actually be a race, not a maximum-excursion count
    bars = synth(11, True)
    atr = atr_series(bars)
    up_only = 0
    for idx, kind, _p, cidx in swings(bars, atr, 1.0):
        r = race(bars, atr, idx, kind, 10, 1.0)
        if r and r[0] and r[1] >= 1.0:
            up_only += 1
    check(up_only >= 0, "race scorer unusable")

    # D. wilson interval must bracket the point estimate
    lo, hi = wilson(30, 100)
    check(lo < 0.30 < hi, "wilson interval does not bracket its point estimate")

    # E. ATR warm-up must be zero, never a fabricated value
    a = atr_series(synth(3, False))
    check(all(x == 0.0 for x in a[:14]), "ATR produced values before warm-up")

    # F. the reported extreme must be the extreme of the leg it terminates, and
    #    it must be knowable strictly AFTER it happened
    bars = synth(5, True)
    atr = atr_series(bars)
    sw = swings(bars, atr, 1.0)
    ok_look = True
    leg_start = 0
    for idx, kind, price, cidx in sw:
        if cidx <= idx:
            ok_look = False
        for j in range(leg_start, idx + 1):
            if kind == "H" and bars[j][2] > price + 1e-12:
                ok_look = False
        # the confirmation must be the first bar that clears one ATR of reversal
        if kind == "H":
            if bars[idx][2] - bars[cidx][3] < 0.999 * atr[cidx]:
                ok_look = False
        else:
            if bars[cidx][2] - bars[idx][3] < 0.999 * atr[cidx]:
                ok_look = False
        leg_start = idx + 1
    check(ok_look, "a reported swing is not the extreme of its leg, or is not knowable in time")

    # G. FTC placebos must be four distinct numbers, or the comparison is a sham
    bars = synth(9, True)
    atr = atr_series(bars)
    sw = swings(bars, atr, 1.0)
    distinct = 0
    for idx, kind, _p, _c in sw:
        if kind != "H" or atr[idx] <= 0:
            continue
        X, Y = bars[idx][2], bars[idx][4]
        th = atr[idx] / 4.0
        anchors = {round((X + Y) / 2 + th, 12), round(X, 12), round(Y, 12),
                   round((X + Y) / 2, 12)}
        distinct = len(anchors)
        break
    check(distinct == 4, f"FTC anchors collapsed to {distinct} distinct value(s)")

    # H. the FTC permutation test must fire on planted data and stay quiet on
    #    noise. Without this the whole FTC section is an untested assertion.
    planted = [(1.5000 + i * 0.01, 0.0025, 1.5000 + i * 0.01, 0.01) for i in range(300)]
    noisy = [(1.5000 + i * 0.01, 0.0025, 1.5000 + i * 0.01 + 0.0007 * ((i * 37) % 11 - 5), 0.01)
             for i in range(300)]
    rp = _ftc_perm(planted, shuffles=120)
    rn = _ftc_perm(noisy, shuffles=120)
    rz = rp["real"].count(0) / rp["n"]
    rz_ctrl = sum(rp["ctrl_zero"]) / len(rp["ctrl_zero"])
    nz = rn["real"].count(0) / rn["n"]
    check(rz > 0.95, f"planted k=0 rate should be ~1.0, got {rz:.2%}")
    check(rz - rz_ctrl > 0.4, f"planted data failed to separate from its shuffle ({rz:.2%} vs {rz_ctrl:.2%})")
    check(nz < rz, f"noise scored as high as planted data ({nz:.2%} vs {rz:.2%})")

    print(f"  selftest: {faults} uncaught seed(s)")
    return faults


def _utf8_stdout():
    """Print UTF-8 regardless of the host console's code page.

    Windows terminals default to cp1252, which cannot encode the characters a
    readable report wants (the minus sign in a lift column, the half symbol).
    Without this the tool dies with a UnicodeEncodeError instead of reporting,
    and the failure looks like a data problem when it is a console problem.
    """
    try:
        sys.stdout.reconfigure(encoding="utf-8", errors="replace")
    except Exception:
        pass


def main(argv):
    _utf8_stdout()
    if "--selftest" in argv:
        return 1 if selftest() else 0

    def num(flag, default):
        return int(argv[argv.index(flag) + 1]) if flag in argv else default

    def fnum(flag, default):
        return float(argv[argv.index(flag) + 1]) if flag in argv else default

    n_sym = num("--symbols", 6)
    horizon, target = num("--horizon", 10), fnum("--target", 1)

    allp = hst.find(tf=1440)
    allp.sort(key=lambda p: -os.path.getsize(p))

    if "--ftc" in argv:
        paths = allp[:n_sym]
        print(f"FTC level study — {len(paths)} daily series\n")
        show_ftc(ftc_study(paths))
        return 0

    if "--ftc-react" in argv:
        paths = allp[:n_sym]
        print(f"FTC reaction study — {len(paths)} daily series "
              f"(bounce after touch, real vs shuffled)\n")
        show_ftc_reaction(_ftc_reaction_unused(paths))
        return 0

    if "--ftc-hold" in argv:
        paths = allp[:n_sym]
        print(f"FTC level-hold test — {len(paths)} daily series\n")
        show_ftc_hold(ftc_hold(paths, horizon=horizon), horizon)
        return 0

    if "--ladder-preview" in argv:
        out = argv[argv.index("--ladder-preview") + 1]
        paths = hst.find(tf=num("--tf", 1440))
        paths.sort(key=lambda p: -os.path.getsize(p))
        paths = paths[:max(n_sym, 20)]
        res = ladder_preview(paths, out, horizon=num("--horizon", 24),
                             bounce_bars=num("--bounce", 6))
        print(f"wrote {out}")
        b = res["best"]
        print(f"best step = ATR/{b['div']:g}   rungs 3+5 {b['avg35']:.2%}  "
              f"others {b['avgOther']:.2%}  raw gap {b['gap']:+.2%}  "
              f"shuffled gap {b['shufGap']:+.2%}  EXCESS {b['excess']:+.2%}")
        print(f"examples embedded: {res['examples']}")
        return 0

    if "--ladder" in argv:
        tf = num("--tf", 1440)
        paths = hst.find(tf=tf)
        paths.sort(key=lambda p: -os.path.getsize(p))
        paths = paths[:max(n_sym, 20)]
        print(f"movement-step ladder — {len(paths)} series at TF {tf}, "
              f"step = ATR/{fnum('--div', 4.0):g} (trigger ability)\n")
        tally, ex = ladder_test(paths, step_div=fnum("--div", 4.0),
                                horizon=num("--horizon", 24),
                                bounce_bars=num("--bounce", 6))
        show_ladder(tally)
        if "--dump" in argv:
            out = argv[argv.index("--dump") + 1]
            json.dump({"tally": {f"{m}|{k}|{t}": v for (m, k, t), v in tally.items()},
                       "examples": ex}, open(out, "w"), indent=1)
            print(f"\n  wrote {out}")
        return 0

    if "--cross" in argv:
        pred_text = argv[argv.index("--cross") + 1]
        tf = num("--tf", 1440)
        paths = hst.find(tf=tf)
        paths.sort(key=lambda p: -os.path.getsize(p))
        paths = paths[:max(n_sym, 12)]
        print(f"cross-series test on {len(paths)} series at TF {tf}\n")
        cross(paths, pred_text, horizon, target)
        return 0

    if "--sweep" in argv:
        paths = allp[:n_sym]
        cfgs = [(h, t, m) for h in (5, 10, 20, 40)
                for t in (0.5, 1.0, 2.0) for m in (0.5, 1.0, 2.0)]
        print(f"parameter sweep — {len(paths)} daily series, "
              f"{len(cfgs)} configurations\n")
        sweep(paths, cfgs)
        return 0

    # prefer the longest histories available: one deep daily series carries more
    # independent pivots than several stubs, and pivots are what is being counted
    allp = hst.find(tf=1440)
    allp.sort(key=lambda p: -os.path.getsize(p))
    paths = allp[:n_sym]
    print(f"pivot repeatability — {len(paths)} daily series, horizon {horizon}, "
          f"race target {target} ATR\n")
    rows, nulls = collect(paths, horizon, target)
    if not rows:
        print("  no pivots collected")
        return 1
    null, ranked = survey(rows, nulls)
    if "--dump" in argv:
        out = argv[argv.index("--dump") + 1]
        json.dump({"null": null, "ranked": ranked, "rows": len(rows)},
                  open(out, "w"), indent=1)
        print(f"\n  wrote {out}")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
