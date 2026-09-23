//+------------------------------------------------------------------+
//| TH3/TH3Pivots.mqh                                                |
//| THE COURSE'S OWN PIVOT, AS A DETECTOR — from the course PDF      |
//| («دوره ی تیرکس», pp. 6-7 pivot, p. 3 fractal TFs, p. 50 shared). |
//|                                                                  |
//| WHY THIS MODULE EXISTS. The TH3 tool's pivots were whatever the  |
//| user clicked. The course defines a pivot by SIX conditions on    |
//| the candles themselves, knowable at a bar's close with only a    |
//| candle-sized reversal after it — so the pivots can be FOUND,     |
//| marked, and drawn on, multi-timeframe and fractally.             |
//|                                                                  |
//| THE SIX CONDITIONS, with the course's own numbers (p. 7):        |
//|  1. fewer than FOUR side/range candles before the move           |
//|     (four or more make it a BASE pivot, not a plain pivot);      |
//|  2. at least THREE standard candles in one direction before it,  |
//|     or a move of at least 240% of ATR (240..360 band's floor);   |
//|  3. a reversal of at least 80% of the SAME timeframe's ATR,      |
//|     in one candle or several;                                    |
//|  4. the candle before the pivot is a MASTER candle (80% body or  |
//|     80% shadow, p. 6) that gets covered — or, if it is not a     |
//|     master, a HYPOTHETICAL 1-ATR range at the extreme is drawn   |
//|     and the pivot is declared only when that line is covered;    |
//|  5. the covering candle engulfs the trading knot ahead of it —   |
//|     per p. 6 that IS the cover of the master / the hypothetical  |
//|     1-ATR line, so it is the same event and carries its own flag;|
//|  6. the covering candle closes in its FINAL THIRD in the         |
//|     reversal's direction.                                        |
//|                                                                  |
//| MULTI-TIMEFRAME, FRACTALLY (p. 3): timeframes chain by a factor  |
//| of FOUR — 1 -> 5 -> 15 -> 60 -> 240 -> 1440 -> 10080 -> 43200    |
//| (the course's own approximations). Three roles per chart:        |
//| structure = one chain step UP, pattern = the chart's own TF,     |
//| trigger = one chain step DOWN. The same detector runs on every   |
//| TF against THAT TF's own ATR — that is what makes it fractal.    |
//|                                                                  |
//| SHARED PIVOTS (p. 50, «پیوت های مشترک یا هم پوشا»): a pivot that |
//| fits two timeframes at once belongs to the HIGHER one. A chart-TF|
//| pivot whose extreme sits inside a structure-TF pivot's span with |
//| the same direction is flagged `shared` and wears the higher TF.  |
//|                                                                  |
//| No chart-object access — the markers that display these live in  |
//| TH3Renderer.mqh; this module only measures.                      |
//+------------------------------------------------------------------+
#ifndef TH3_PIVOTS_MQH
#define TH3_PIVOTS_MQH
#property strict

#include "TH3Types.mqh"

// The course's six conditions, as numeric gates (PDF p. 6-7). Every number
// here is the course's own, except the side-candle range test (0.60 ATR)
// which is how "رفتار ساید" is made measurable — one choice, named here.
#define TH3_P6_SIDE_RANGE     0.60   // a candle at/below this ATR share is "side"
#define TH3_P6_SIDE_MAX       4      // cond 1: >= 4 side candles -> BASE pivot
#define TH3_P6_RUN_CANDLES    3      // cond 2: three standard candles in a run
#define TH3_P6_RUN_EXT        2.40   // cond 2: or 240% ATR of travel (240..360 band)
#define TH3_P6_STD_LO         0.80   // "standard" candle band, PDF p. 6 (per ATR)
#define TH3_P6_STD_HI         1.20
#define TH3_P6_CONFIRM        0.80   // cond 3: the reversal dial, per ATR
#define TH3_P6_MASTER         0.80   // cond 4: 80% body OR 80% shadow (p. 6)
#define TH3_P6_HYPO           1.00   // cond 4: the hypothetical 1-ATR line
#define TH3_P6_CLOSE_THIRD    (1.0/3.0)  // cond 6: close in the final third
#define TH3_P6_MAX_WAIT       20     // bars a non-master candidate may stay pending

// THE STEP'S OWN FLOOR (P-TH3-STEP-04e). A reaction only VOTES the step once
// it has travelled this many rungs, i.e. once the step it implies (dist/3)
// reaches 0.80 of the rung. Named here because it is one choice, not a course
// number: the course (PDF p. 2) says "once price has reacted to the rungs,
// recalibrate them" and names no minimum. 2.40 keeps a sub-step wiggle from
// rebuilding the ladder 33% short (the user's "step drew cramped next to C")
// while still letting a NORMAL first leg vote — the thousand-chart survey
// measures the median first leg at 3.1-3.6 rungs (step3_survey.py), so the
// gate that used to sit here (3.0 rungs, P-TH3-STEP-04d) skipped exactly the
// reaction the course names and left every real chart on its seed rung.
#define TH3_STEP_MIN_LEG_RUNGS 2.40

// P-TH3-STEP-09 (2026-09-19) — THE VOTE'S OWN LEASH. A proved step that
// lands farther than this share from the closed seed is no vote: the
// ladder keeps its seed instead of jumping a timeframe on one leg.
// A choice, marked tunable, not a course number.
#define TH3_HIT_MAX_STEP_ERR 0.25

// P-TH3-MP2 (2026-09-19) — THE MOTHERNESS SCORE's OWN WEIGHTS. The old
// matcher picked the NEAREST fresh pivot; the user's eye picks the node the
// market has visited and leaned on. Three named, tunable choices (not course
// numbers): a mother's touches, its thickness in steps, and its age.
#define TH3_MP_TOUCH_W        25.0    // per separate touch after declare
#define TH3_MP_TOUCH_MAX      6       // touches capped (a wall is not ten walls)
#define TH3_MP_THICK_W        20.0    // per step of node thickness (capped)
#define TH3_MP_THICK_MAX      2.0     // thickness credited up to 2 steps
#define TH3_MP_AGE_BONUS      15.0    // predates the pattern origin: the insider ban
#define TH3_MP_LAUNCH_BONUS   40.0    // the launch test: X->A leg starts in-node
#define TH3_MP_TOL_STEP       0.5     // tier 1: half a step (the old tol)
#define TH3_MP_TOL_WIDE       1.5     // tier 2: one and a half steps
#define TH3_MP_TOL_SPAN       3.0     // tier 3: three steps (the far mother)
#define TH3_MP_TOUCH_TOL      0.5     // a touch = within half the node's step

// One found pivot, on one timeframe.
//
// P-TH3-P6e (2026-09-19) — THE NODE, STATED. A mother pivot is not one
// line but the zone [price .. keyPrice]: `price` is the extreme, and
// `keyPrice` is cond 4's own line — the pivot candle's opposite edge
// when it is a master (the node IS that candle), or the hypothetical
// 1-ATR line (extreme ∓ ATR) when it is not. `mitigated` says whether
// a completed bar after `confirmTime` has overlapped the node since.
// Appended, never reordered.
struct TH3PivotSix
{
    datetime time;          // the extreme candle's open time
    double   price;         // the extreme (high for an H pivot, low for an L)
    bool     isHigh;
    datetime confirmTime;   // the covering candle's open time (cond 4/5)
    int      tf;            // measured on this timeframe (minutes)
    bool     master;        // cond 4: the pivot candle was a master candle
    bool     base;          // cond 1 failed: a BASE pivot (reported, not drawn)
    bool     shared;        // p. 50: fits a higher fractal TF too -> it owns it
    bool     valid;
    double   keyPrice;      // P-TH3-P6e: cond-4 line (opp. edge if master, else 1-ATR line)
    bool     mitigated;     // P-TH3-P6e: node overlapped after confirmTime (fresh = false)
};

//+------------------------------------------------------------------+
//| THE FRACTAL CHAIN (p. 3) — the course's factor-of-four ladder.   |
//| Returns the next chain TF up (dir=+1) or down (dir=-1); the same |
//| TF when the chart sits outside the chain's ends. M30 is not a    |
//| chain member (15 -> 60), so from M30 up reads H1 and down M15.   |
//+------------------------------------------------------------------+
int TH3FractalStepTF(const int tf, const int dir)
{
    int chain[8];
    chain[0] = 1; chain[1] = 5; chain[2] = 15; chain[3] = 60;
    chain[4] = 240; chain[5] = 1440; chain[6] = 10080; chain[7] = 43200;
    int idx = -1;
    for(int i = 0; i < 8; i++) if(chain[i] == tf) { idx = i; break; }
    if(idx < 0)   // off-chain chart: land on the nearest chain member
    {
        for(int i = 0; i < 8; i++)
            if((dir > 0 && chain[i] > tf) || (dir < 0 && chain[i] < tf))
                return chain[i];
        return (dir > 0 ? 43200 : 1);
    }
    int nxt = idx + dir;
    if(nxt < 0)   return chain[0];
    if(nxt >= 8)  return chain[7];
    return chain[nxt];
}

//+------------------------------------------------------------------+
//| One bar's anatomy, per the PDF. Returns false when the bar is    |
//| unusable (no ATR, no range) — never a guessed answer.            |
//+------------------------------------------------------------------+
bool TH3P6BarAnatomy(const int tf, const int i, const double atr,
                     double &bodyRatio, double &shadowRatio,
                     bool &isMaster)
{
    double o = iOpen(NULL, tf, i),  h = iHigh(NULL, tf, i);
    double l = iLow(NULL, tf, i),   c = iClose(NULL, tf, i);
    if(h <= 0 || l <= 0 || h <= l || atr <= 0 || atr == EMPTY_VALUE) return false;
    double rng  = h - l;
    double body = MathAbs(c - o);
    double upShadow = h - MathMax(o, c);
    double loShadow = MathMin(o, c) - l;
    bodyRatio   = body / rng;
    shadowRatio = MathMax(upShadow, loShadow) / rng;
    isMaster    = (bodyRatio >= TH3_P6_MASTER || shadowRatio >= TH3_P6_MASTER);
    return true;
}

//+------------------------------------------------------------------+
//| Cond 1 + 2: the move INTO the pivot. `extIdx` is the candidate.  |
//| Returns false when the move does not qualify (or the bar read    |
//| fails) — the caller then never declares on it.                   |
//+------------------------------------------------------------------+
bool TH3P6RunOk(const int tf, const int extIdx, const double atr,
                const bool isHigh, bool &basePivot)
{
    basePivot = false;
    // cond 2: the directional run — consecutive same-direction closes into it
    int runBars = 0;
    int j = extIdx;
    while(j >= 1)
    {
        double pc = iClose(NULL, tf, j - 1), cc = iClose(NULL, tf, j);
        if(pc <= 0 || cc <= 0) break;
        bool moved = isHigh ? (pc < cc) : (pc > cc);
        if(!moved) break;
        runBars++;
        j--;
    }
    if(runBars < 1) return false;
    int runStart = extIdx - runBars;
    double runExt = 0;
    double c0 = iClose(NULL, tf, runStart), c1 = iClose(NULL, tf, extIdx);
    if(c0 > 0 && c1 > 0 && atr > 0) runExt = MathAbs(c1 - c0) / atr;

    // cond 2, first arm: three STANDARD candles in the run
    int stdRun = 0;
    for(int k = extIdx; k > extIdx - runBars && k >= 0; k--)
    {
        double bR, sR; bool mst;
        double a2 = iATR(NULL, tf, 14, k);
        if(!TH3P6BarAnatomy(tf, k, a2, bR, sR, mst)) break;
        double rng = iHigh(NULL, tf, k) - iLow(NULL, tf, k);
        double x = rng / a2;
        if(x < TH3_P6_STD_LO || x > TH3_P6_STD_HI) break;
        stdRun++;
    }

    // cond 1: side/range candles just before the run — four or more make
    // this a BASE pivot (the course's own word, p. 7), reported not drawn.
    int sideBars = 0;
    int k2 = runStart - 1;
    while(k2 >= 0 && sideBars < 8)
    {
        double a3 = iATR(NULL, tf, 14, k2);
        double h = iHigh(NULL, tf, k2), l = iLow(NULL, tf, k2);
        if(h <= 0 || l <= 0 || a3 <= 0 || a3 == EMPTY_VALUE) break;
        if((h - l) > TH3_P6_SIDE_RANGE * a3) break;
        sideBars++;
        k2--;
    }
    basePivot = (sideBars >= TH3_P6_SIDE_MAX);

    return (stdRun >= TH3_P6_RUN_CANDLES || runExt >= TH3_P6_RUN_EXT);
}

//+------------------------------------------------------------------+
//| Cond 4+5: the cover. Walks the reversal bars after `extIdx` for  |
//| the first bar that covers the master candle's full range, or —   |
//| when the candidate is not a master — the hypothetical 1-ATR line |
//| at the extreme (PDF p. 6: engulfing IS covering one of the two). |
//| Returns the covering bar's shift, or -1 when nothing covers.     |
//+------------------------------------------------------------------+
int TH3P6FindCover(const int tf, const int extIdx, const double extPrice,
                   const bool isHigh, const bool isMaster,
                   const int fromIdx, const int toIdx)
{
    double aExt = iATR(NULL, tf, 14, extIdx);
    if(aExt <= 0 || aExt == EMPTY_VALUE) return -1;
    double extHigh = iHigh(NULL, tf, extIdx);
    double extLow  = iLow(NULL, tf, extIdx);
    for(int j = fromIdx; j >= toIdx; j--)
    {
        double h = iHigh(NULL, tf, j), l = iLow(NULL, tf, j);
        if(h <= 0 || l <= 0) continue;
        if(isMaster)
        {
            if(h >= extHigh && l <= extLow) return j;   // full-range engulf
        }
        else
        {
            // the hypothetical 1-ATR line (p. 7, cond 4): the REVERSAL trades
            // through the line's far edge — cumulative, one bar or several
            // (cond 3's own words). The old single-bar demand (h>=eh AND
            // l<=line) could never fire on a reversal running away from the
            // extreme — measured: 0 covers in 330 candidates on XAUUSD H4.
            // PY-MIRROR: therm hypo cover matches step3_survey find_cover exactly
            if(isHigh  && l <= extHigh - TH3_P6_HYPO * aExt) return j;
            if(!isHigh && h >= extLow  + TH3_P6_HYPO * aExt) return j;
        }
    }
    return -1;
}

//+------------------------------------------------------------------+
//| Cond 6: the covering candle closes in its FINAL THIRD in the     |
//| reversal's direction (p. 7). An H pivot's cover closes low; an   |
//| L pivot's cover closes high.                                     |
//+------------------------------------------------------------------+
bool TH3P6CloseThird(const int tf, const int coverIdx, const bool isHigh)
{
    double h = iHigh(NULL, tf, coverIdx), l = iLow(NULL, tf, coverIdx);
    double c = iClose(NULL, tf, coverIdx);
    if(h <= 0 || l <= 0 || h <= l) return false;
    double pos = (c - l) / (h - l);   // 0 = at the low, 1 = at the high
    return isHigh ? (pos <= TH3_P6_CLOSE_THIRD) : (pos >= 1.0 - TH3_P6_CLOSE_THIRD);
}

//+------------------------------------------------------------------+
//| P-TH3-P6e — MITIGATION. A node is FRESH when no COMPLETED bar    |
//| newer than the confirming bar has overlapped [zoneLo .. zoneHi]  |
//| since; the first overlap marks it mitigated. Overlap (not        |
//| close-through) is the test, stated as a choice: the course names |
//| the knot, not the trigger. Cost: only DECLARED pivots pay (a     |
//| handful per scan), never per bar. covIdx <= 1 means no newer      |
//| completed bar exists yet -> fresh.                                |
//+------------------------------------------------------------------+
bool TH3P6Mitigated(const int tf, const double zoneLo, const double zoneHi,
                    const int covIdx)
{
    if(covIdx <= 1) return false;
    for(int j = covIdx - 1; j >= 1; j--)
    {
        double h = iHigh(NULL, tf, j), l = iLow(NULL, tf, j);
        if(h <= 0 || l <= 0) continue;
        if(h >= zoneLo && l <= zoneHi) return true;
    }
    return false;
}

//+------------------------------------------------------------------+
//| P-TH3-P6e — THE KEY LINE. Master: the pivot candle's opposite    |
//| edge (H -> its low, L -> its high). Non-master: the hypothetical |
//| 1-ATR line at the extreme (H -> extP - ATR, L -> extP + ATR) —   |
//| the very line whose coverage declares the pivot. Returns <= 0    |
//| when unmeasurable: the caller then skips the declaration rather  |
//| than guessing a node (0 = absence, never a guess).               |
//+------------------------------------------------------------------+
double TH3P6KeyPrice(const int tf, const int extIdx, const double extP,
                     const bool isHigh, const bool isMaster)
{
    if(isMaster)
    {
        double e = isHigh ? iLow(NULL, tf, extIdx) : iHigh(NULL, tf, extIdx);
        if(e <= 0) return 0.0;
        return e;
    }
    double aE = iATR(NULL, tf, 14, extIdx);
    if(aE <= 0 || aE == EMPTY_VALUE) return 0.0;
    return isHigh ? (extP - TH3_P6_HYPO * aE) : (extP + TH3_P6_HYPO * aE);
}

//+------------------------------------------------------------------+
//| THE SCAN — six-condition pivots on ONE timeframe, walked over    |
//| completed bars only (shift >= 1; bar 0 is still forming). The    |
//| state machine is the zigzag's, but the confirm dial is cond 3    |
//| (80% ATR) and the declaration is cond 4's cover, so a pivot is   |
//| knowable at a candle-sized reversal, not after a full-ATR one.   |
//| Returns the number written into `out` (<= maxOut).               |
//| P-TH3-D4d: the window ENDS at endTime (default 0 = latest bar,   |
//| the markers' view). A pattern drawn on old history (D in March,  |
//| terminal in September) reads nothing otherwise: the latest 400   |
//| bars never reach its candles, so the cache is empty (nc=0 ns=0   |
//| nm=0) and every mother/lock/snap caller agrees on "none".        |
//+------------------------------------------------------------------+
int TH3SixPivotsScanTF(const int tf, TH3PivotSix &out[], const int maxOut,
                       const int lookbackBars = 400, const datetime endTime = 0)
{
    int n = iBars(NULL, tf);
    if(n < 20) return 0;
    int last = 1;   // newest bar of the window (1 = last completed bar)
    if(endTime > 0)
    {
        last = iBarShift(NULL, tf, endTime);
        if(last < 1) last = 1;
    }
    if(n - last < 15) return 0;
    int depth = MathMin(lookbackBars, n - last - 13);
    if(depth < 5) return 0;
    int count = 0;
    int state = 0;             // 0 = seeking, +1 = rising (watching H), -1 = falling
    int extIdx = 0;
    double extP = 0;
    int pendWait = 0;
    for(int i = last + depth - 1; i >= last; i--)
    {
        double a = iATR(NULL, tf, 14, i);
        if(a <= 0 || a == EMPTY_VALUE) continue;
        double h = iHigh(NULL, tf, i), l = iLow(NULL, tf, i);
        if(h <= 0 || l <= 0) continue;

        if(state == 0)
        {
            if(extP == 0)      { extP = h; extIdx = i; state = 1;  pendWait = 0; }
            else if(h > extP)  { extIdx = i; extP = h; state = 1;  pendWait = 0; }
            else if(l < extP)  { extIdx = i; extP = l; state = -1; pendWait = 0; }
            continue;
        }
        if(state > 0)
        {
            if(h > extP) { extIdx = i; extP = h; pendWait = 0; continue; }
            if(extP - l >= TH3_P6_CONFIRM * a)
            {
                bool master = false;
                double bR, sR;
                if(TH3P6BarAnatomy(tf, extIdx, iATR(NULL, tf, 14, extIdx), bR, sR, master))
                {
                    bool base = false;
                    bool ok = TH3P6RunOk(tf, extIdx, a, true, base);
                    if(ok && !master)
                    {
                        // not a master: the pivot declares only when the
                        // hypothetical 1-ATR line is covered (cond 4) — wait.
                        int cov0 = TH3P6FindCover(tf, extIdx, extP, true, false, i, i);
                        if(cov0 < 0 && pendWait < TH3_P6_MAX_WAIT) { pendWait++; continue; }
                        if(cov0 < 0) { state = -1; extIdx = i; extP = l; pendWait = 0; continue; }
                    }
                    if(ok)
                    {
                        int covIdx = TH3P6FindCover(tf, extIdx, extP, true, master, i, extIdx + 1);
                        if(covIdx >= 0 && TH3P6CloseThird(tf, covIdx, true) && count < maxOut)
                        {
                            double kp = TH3P6KeyPrice(tf, extIdx, extP, true, master);
                            if(kp <= 0) { state = -1; extIdx = i; extP = l; pendWait = 0; continue; }
                            out[count].time  = iTime(NULL, tf, extIdx);
                            out[count].price = extP;
                            out[count].isHigh = true;
                            out[count].confirmTime = iTime(NULL, tf, covIdx);
                            out[count].tf = tf;
                            out[count].master = master;
                            out[count].base = base;
                            out[count].shared = false;
                            out[count].valid = true;
                            out[count].keyPrice = kp;
                            out[count].mitigated = TH3P6Mitigated(tf, MathMin(extP, kp),
                                                                 MathMax(extP, kp), covIdx);
                            count++;
                        }
                    }
                }
                state = -1; extIdx = i; extP = l; pendWait = 0;
            }
        }
        else
        {
            if(l < extP) { extIdx = i; extP = l; pendWait = 0; continue; }
            if(h - extP >= TH3_P6_CONFIRM * a)
            {
                bool master = false;
                double bR, sR;
                if(TH3P6BarAnatomy(tf, extIdx, iATR(NULL, tf, 14, extIdx), bR, sR, master))
                {
                    bool base = false;
                    bool ok = TH3P6RunOk(tf, extIdx, a, false, base);
                    if(ok && !master)
                    {
                        int cov0 = TH3P6FindCover(tf, extIdx, extP, false, false, i, i);
                        if(cov0 < 0 && pendWait < TH3_P6_MAX_WAIT) { pendWait++; continue; }
                        if(cov0 < 0) { state = 1; extIdx = i; extP = h; pendWait = 0; continue; }
                    }
                    if(ok)
                    {
                        int covIdx = TH3P6FindCover(tf, extIdx, extP, false, master, i, extIdx + 1);
                        if(covIdx >= 0 && TH3P6CloseThird(tf, covIdx, false) && count < maxOut)
                        {
                            double kp = TH3P6KeyPrice(tf, extIdx, extP, false, master);
                            if(kp <= 0) { state = 1; extIdx = i; extP = h; pendWait = 0; continue; }
                            out[count].time  = iTime(NULL, tf, extIdx);
                            out[count].price = extP;
                            out[count].isHigh = false;
                            out[count].confirmTime = iTime(NULL, tf, covIdx);
                            out[count].tf = tf;
                            out[count].master = master;
                            out[count].base = base;
                            out[count].shared = false;
                            out[count].valid = true;
                            out[count].keyPrice = kp;
                            out[count].mitigated = TH3P6Mitigated(tf, MathMin(extP, kp),
                                                                 MathMax(extP, kp), covIdx);
                            count++;
                        }
                    }
                }
                state = 1; extIdx = i; extP = h; pendWait = 0;
            }
        }
    }
    return count;
}

//+------------------------------------------------------------------+
//| The two-TF read, cached per bar (P-TH3-PERF: a scan pays for     |
//| itself once per new bar of its own TF, never per tick).          |
//| Slot 0 = the chart's TF (pattern), slot 1 = one chain step UP    |
//| (structure). Shared pivots (p. 50) are flagged here, once.       |
//+------------------------------------------------------------------+
#define TH3_P6_MAX_PIVOTS 64
bool TH3PivotsRead(TH3PivotSix &chartPivots[], TH3PivotSix &structPivots[],
                   int &chartCount, int &structCount, int &structTF,
                   const datetime endTime = 0)
{
    static int      s_tf0 = -1, s_bars0 = -1;
    static int      s_tf1 = -1, s_bars1 = -1;
    static TH3PivotSix s_c0[], s_c1[];
    static int      s_n0 = 0, s_n1 = 0;
    // P-TH3-D4d: anchored memo — one slot keyed by (TF, endTime, bar count),
    // so redraws/drags/ticks of one pattern hit instead of rescanning.
    static int      s_aTF0 = -1, s_aB0 = -1;
    static datetime s_aEnd0 = 0;
    static int      s_aTF1 = -1, s_aB1 = -1;
    static datetime s_aEnd1 = 0;
    static TH3PivotSix s_a0[], s_a1[];
    static int      s_aN0 = 0, s_aN1 = 0;

    if(ArraySize(s_c0) != TH3_P6_MAX_PIVOTS) ArrayResize(s_c0, TH3_P6_MAX_PIVOTS);
    if(ArraySize(s_c1) != TH3_P6_MAX_PIVOTS) ArrayResize(s_c1, TH3_P6_MAX_PIVOTS);
    if(ArraySize(s_a0) != TH3_P6_MAX_PIVOTS) ArrayResize(s_a0, TH3_P6_MAX_PIVOTS);
    if(ArraySize(s_a1) != TH3_P6_MAX_PIVOTS) ArrayResize(s_a1, TH3_P6_MAX_PIVOTS);

    int tf0 = Period();
    int tf1 = TH3FractalStepTF(tf0, 1);
    int b0 = iBars(NULL, tf0), b1 = iBars(NULL, tf1);

    if(endTime == 0)
    {
        if(tf0 != s_tf0 || b0 != s_bars0)
        {
            s_n0 = TH3SixPivotsScanTF(tf0, s_c0, TH3_P6_MAX_PIVOTS);
            s_tf0 = tf0; s_bars0 = b0;
        }
        if(tf1 != s_tf1 || b1 != s_bars1)
        {
            s_n1 = TH3SixPivotsScanTF(tf1, s_c1, TH3_P6_MAX_PIVOTS);
            s_tf1 = tf1; s_bars1 = b1;
        }
        // the shared-pivot rule (p. 50): a chart-TF pivot that sits inside a
        // structure-TF pivot's span, same direction, belongs to the higher TF.
        for(int i = 0; i < s_n0; i++)
        {
            s_c0[i].shared = false;
            if(!s_c0[i].valid) continue;
            for(int j = 0; j < s_n1; j++)
            {
                if(!s_c1[j].valid || s_c1[j].isHigh != s_c0[i].isHigh) continue;
                if(s_c1[j].time <= s_c0[i].time && s_c0[i].time <= s_c1[j].confirmTime)
                {
                    s_c0[i].shared = true;
                    break;
                }
            }
        }
        int m0 = ArraySize(chartPivots);  if(m0 > s_n0) m0 = s_n0;
        for(int i = 0; i < m0; i++) chartPivots[i] = s_c0[i];
        chartCount = m0;
        int m1 = ArraySize(structPivots); if(m1 > s_n1) m1 = s_n1;
        for(int i = 0; i < m1; i++) structPivots[i] = s_c1[i];
        structCount = m1;
        structTF = tf1;
        return (m0 > 0 || m1 > 0);
    }

    // P-TH3-D4d anchored window: same rule, separate memo slot.
    if(tf0 != s_aTF0 || endTime != s_aEnd0 || b0 != s_aB0)
    {
        s_aN0 = TH3SixPivotsScanTF(tf0, s_a0, TH3_P6_MAX_PIVOTS, 400, endTime);
        s_aTF0 = tf0; s_aEnd0 = endTime; s_aB0 = b0;
    }
    if(tf1 != s_aTF1 || endTime != s_aEnd1 || b1 != s_aB1)
    {
        s_aN1 = TH3SixPivotsScanTF(tf1, s_a1, TH3_P6_MAX_PIVOTS, 400, endTime);
        s_aTF1 = tf1; s_aEnd1 = endTime; s_aB1 = b1;
    }
    for(int i = 0; i < s_aN0; i++)
    {
        s_a0[i].shared = false;
        if(!s_a0[i].valid) continue;
        for(int j = 0; j < s_aN1; j++)
        {
            if(!s_a1[j].valid || s_a1[j].isHigh != s_a0[i].isHigh) continue;
            if(s_a1[j].time <= s_a0[i].time && s_a0[i].time <= s_a1[j].confirmTime)
            {
                s_a0[i].shared = true;
                break;
            }
        }
    }
    int a0 = ArraySize(chartPivots);  if(a0 > s_aN0) a0 = s_aN0;
    for(int i = 0; i < a0; i++) chartPivots[i] = s_a0[i];
    chartCount = a0;
    int a1 = ArraySize(structPivots); if(a1 > s_aN1) a1 = s_aN1;
    for(int i = 0; i < a1; i++) structPivots[i] = s_a1[i];
    structCount = a1;
    structTF = tf1;
    return (a0 > 0 || a1 > 0);
}

//+------------------------------------------------------------------+
//| P-TH3-P6e Tier-2 — THE MACRO READ. Slot 2 = two chain steps UP   |
//| (macro), cached per bar of its own TF exactly like slots 0/1. A  |
//| separate reader — NOT a signature change on TH3PivotsRead — so   |
//| every old caller keeps compiling (P-BUILD-02). A far base lives  |
//| here: 400 macro bars see what 400 chart bars cannot.             |
//+------------------------------------------------------------------+
bool TH3MacroPivotsRead(TH3PivotSix &macroPivots[], int &macroCount, int &macroTF,
                        const datetime endTime = 0)
{
    static int      s_tf2 = -1, s_bars2 = -1;
    static TH3PivotSix s_c2[];
    static int      s_n2 = 0;
    // P-TH3-D4d anchored memo (see TH3PivotsRead).
    static int      s_aTF2 = -1, s_aB2 = -1;
    static datetime s_aEnd2 = 0;
    static TH3PivotSix s_a2[];
    static int      s_aN2 = 0;

    if(ArraySize(s_c2) != TH3_P6_MAX_PIVOTS) ArrayResize(s_c2, TH3_P6_MAX_PIVOTS);
    if(ArraySize(s_a2) != TH3_P6_MAX_PIVOTS) ArrayResize(s_a2, TH3_P6_MAX_PIVOTS);

    int tf2 = TH3FractalStepTF(Period(), 2);
    int b2 = iBars(NULL, tf2);

    if(endTime == 0)
    {
        if(tf2 != s_tf2 || b2 != s_bars2)
        {
            s_n2 = TH3SixPivotsScanTF(tf2, s_c2, TH3_P6_MAX_PIVOTS);
            s_tf2 = tf2; s_bars2 = b2;
        }
        int m2 = ArraySize(macroPivots); if(m2 > s_n2) m2 = s_n2;
        for(int i = 0; i < m2; i++) macroPivots[i] = s_c2[i];
        macroCount = m2;
        macroTF = tf2;
        return (m2 > 0);
    }
    if(tf2 != s_aTF2 || endTime != s_aEnd2 || b2 != s_aB2)
    {
        s_aN2 = TH3SixPivotsScanTF(tf2, s_a2, TH3_P6_MAX_PIVOTS, 400, endTime);
        s_aTF2 = tf2; s_aEnd2 = endTime; s_aB2 = b2;
    }
    int a2 = ArraySize(macroPivots); if(a2 > s_aN2) a2 = s_aN2;
    for(int i = 0; i < a2; i++) macroPivots[i] = s_a2[i];
    macroCount = a2;
    macroTF = tf2;
    return (a2 > 0);
}

//+------------------------------------------------------------------+
//| P-TH3-P6e Tier-2 — ORIGIN. The far base the move started from,   |
//| not the level C sits on (that is Tier-1's job). Ruler = the      |
//| pattern's own span |pC-pA| (self-scaling: pips never punish gold, |
//| no new constant). Layer = macro only (+2 chain). Must predate    |
//| anchorTime (Pillar 1, REQUIRED here — an origin without an       |
//| anchor is undefined). Same kind (the base shares C's extremity). |
//| Fresh wins through the same scorer (refStep 0: TF+fresh only).   |
//| Pure domain: no objects, no redraw.                              |
//+------------------------------------------------------------------+
bool TH3OriginPivotAt(const datetime tRef, const double pRef,
                      const bool wantHigh, const double spanTol,
                      const datetime anchorTime, TH3PivotSix &out)
{
    if(tRef <= 0 || pRef <= 0 || spanTol <= 0 || anchorTime <= 0) return false;
    TH3PivotSix macroP[];
    ArrayResize(macroP, TH3_P6_MAX_PIVOTS);
    int nm = 0, tm = 0;
    if(!TH3MacroPivotsRead(macroP, nm, tm, tRef)) return false;
    int tf_structure = TH3FractalStepTF(Period(), 1);
    int tf_macro = TH3FractalStepTF(Period(), 2);
    bool found = false;
    double bestScore = -1e9, bestDist = 1e9;
    for(int i = 0; i < nm; i++)
    {
        TH3PivotSix c = macroP[i];
        if(!c.valid || c.base) continue;
        if(c.isHigh != wantHigh) continue;
        if(c.time >= tRef || c.time >= anchorTime) continue;
        double d = MathAbs(c.price - pRef);
        if(d > spanTol) continue;
        double s = CalculateDynamicPivotScore(c, pRef, tf_structure, tf_macro, 0.0);
        if(s > bestScore || (s == bestScore && d < bestDist))
        { bestScore = s; bestDist = d; out = c; found = true; }
    }
    return found;
}

//+------------------------------------------------------------------+
//| P-TH3-P6e — MOTHER PIVOT. Nearest valid non-base pivot of the    |
//| wanted kind strictly before tRef and within tol of pRef. Pass    |
//| order is the user's spec, stated as a choice, not a course       |
//| number: fresh chart, fresh structure, mitigated chart, mitigated  |
//| structure — freshness first, higher TF second.                   |
//| Pure domain: TH3PivotsRead is bar-cached; no objects, no redraw,  |
//| so this is Lite-safe (P-BUILD-01) and harness-safe (P-BUILD-02).  |
//| Caveat, stated: a pivot needs its cover to declare, so a pivot   |
//| AT tRef may not exist yet — match closed points (like            |
//| TH3HitPivotMeasure does), never a forming bar. tol < 0 refuses;  |
//| tol == 0 means an exact-price match.                             |
//+------------------------------------------------------------------+
//+------------------------------------------------------------------+
//| P-TH3-P6e Pillar 4 — NORMALIZED SCORE. TF weight (macro 100 /    |
//| structure 60 / chart 20 / other 5) + fresh 30, minus distance in |
//| STEP units (50 per rung, so pip size never punishes gold). The   |
//| six weights are deliberate choices, not course numbers — the     |
//| only tunable part here, same standing as the cover multipliers.  |
//| Pure: tf roles arrive as params (Pillar 2 fills them from the    |
//| chain, never hardcoded) — pinned in Biotak_TH3_Test.mq4 §9b.     |
//+------------------------------------------------------------------+
double CalculateDynamicPivotScore(const TH3PivotSix &piv, const double targetPrice,
                                 const int tf_structure, const int tf_macro,
                                 const double refStep)
{
   double score = 0;
   if(piv.tf >= tf_macro)          score += 100.0;
   else if(piv.tf == tf_structure) score += 60.0;
   else if(piv.tf == Period())     score += 20.0;
   else                            score += 5.0;

   if(!piv.mitigated) score += 30.0;

   if(refStep > 0) {
      double distRungs = MathAbs(piv.price - targetPrice) / refStep;
      score -= (distRungs * 50.0);
   }
   return score;
}

//+------------------------------------------------------------------+
//| P-TH3-MP2 — TOUCHES. Separate visits of the level after the      |
//| pivot declared (consecutive bars inside tol = one visit — the    |
//| same reading as TH3HitPivotMeasure's count, «چندین مرتبه رد      |
//| شده»). Walks completed bars from the bar AFTER the confirm bar   |
//| to the reference bar, on the pivot's OWN tf. Returns 0 when the  |
//| read fails — absence, never a guess. Pure: no objects.           |
//+------------------------------------------------------------------+
int TH3MotherTouches(const int tf, const double level, const datetime confirmTime,
                     const datetime tRef, const double step)
{
    if(tf <= 0 || level <= 0 || step <= 0 || tRef <= confirmTime) return 0;
    int cBar = iBarShift(NULL, tf, confirmTime);
    int rBar = iBarShift(NULL, tf, tRef);
    if(cBar < 0 || rBar < 0 || rBar >= cBar) return 0;
    double tol = TH3_MP_TOUCH_TOL * step;
    int touches = 0;
    bool inside = false;
    for(int j = cBar - 1; j >= rBar; j--)
    {
        double h = iHigh(NULL, tf, j), l = iLow(NULL, tf, j);
        if(h <= 0 || l <= 0) continue;
        bool hit = (l - tol <= level) && (h + tol >= level);
        if(hit && !inside) touches++;
        inside = hit;
    }
    return touches;
}

//+------------------------------------------------------------------+
//| P-TH3-MP2 — LAUNCH TEST. The mother is where the move came       |
//| FROM: the leg X->A (anchor -> first point) must START inside or  |
//| at the edge of the candidate's node [lo .. hi]. `legStart` is    |
//| the anchor's price (X, else A), `legEnd` the far point's. True   |
//| also when the leg merely passes through the node — the base the  |
//| market lifted off is a mother even when the exact open is a bar  |
//| beside it. Pure: no objects, no reads beyond the zone test.      |
//+------------------------------------------------------------------+
bool TH3MotherLaunch(const double lo, const double hi,
                     const double legStart, const double legEnd)
{
    if(lo <= 0 || hi <= 0 || hi < lo || legStart <= 0) return false;
    // the leg's near end inside the node, or the node between near and far
    bool startIn = (legStart >= lo && legStart <= hi);
    bool passThrough = (legEnd > hi && legStart <= hi) || (legEnd < lo && legStart >= lo);
    return (startIn || passThrough);
}

//+------------------------------------------------------------------+
//| P-TH3-MP2 — MOTHERNESS. The mother score, stated:                |
//|   TF weight (same ladder as Pillar 4)                            |
//| + freshness, scaled BY TF (chart freshness is noise, macro       |
//|   freshness is structure: macro 30 / structure 25 / chart 12)    |
//| + touches (capped) + thickness in steps (capped)                 |
//| + age bonus (predates the origin) + launch bonus                 |
//| - distance, in step units (a near tie still breaks nearer)       |
//| Score is bounded in its parts; the matcher compares totals.      |
//+------------------------------------------------------------------+
double TH3MotherScore(const TH3PivotSix &piv, const double targetPrice,
                      const int tf_structure, const int tf_macro,
                      const double refStep, const int touches,
                      const double nodeStep, const bool launchOK,
                      const bool predatesOrigin)
{
    double score = 0;
    if(piv.tf >= tf_macro)          score += 100.0;
    else if(piv.tf == tf_structure) score += 60.0;
    else if(piv.tf == Period())     score += 20.0;
    else                            score += 5.0;

    // freshness, scaled by the layer (a choice, stated):
    if(piv.tf >= tf_macro)          score += 30.0;
    else if(piv.tf == tf_structure) score += 25.0;
    else                            score += 12.0;
    if(piv.mitigated) score -= 12.0;    // mitigated, not disqualified

    int t = touches; if(t > TH3_MP_TOUCH_MAX) t = TH3_MP_TOUCH_MAX;
    score += t * TH3_MP_TOUCH_W;

    double thickSteps = 0;
    if(nodeStep > 0) thickSteps = MathAbs(piv.price - piv.keyPrice) / nodeStep;
    if(thickSteps > TH3_MP_THICK_MAX) thickSteps = TH3_MP_THICK_MAX;
    score += thickSteps * TH3_MP_THICK_W;

    if(predatesOrigin) score += TH3_MP_AGE_BONUS;
    if(launchOK)       score += TH3_MP_LAUNCH_BONUS;

    if(refStep > 0) {
        double distSteps = MathAbs(piv.price - targetPrice) / refStep;
        score -= distSteps * 25.0;   // per step away from C: real, not dominant
    }
    return score;
}

//+------------------------------------------------------------------+
//| P-TH3-MP2 — MOTHER LADDER SCAN. All three layers (chart +        |
//| structure + macro) in one read, base pivots INCLUDED: the        |
//| course's own «مبنا» is the pivot with 4+ side candles (p. 7) —   |
//| exactly the node the eye picks as the mother — so the old        |
//| `c.base -> skip` was refusing the very thing it hunted. The      |
//| tolerance is a LADDER, not a gate: a candidate inside any tier   |
//| competes on score; the tiers only decide who gets to compete.    |
//+------------------------------------------------------------------+
bool TH3MotherPivotAt(const datetime tRef, const double pRef,
                      const bool wantHigh, const double tol,
                      TH3PivotSix &out,
                      const datetime anchorTime = 0,
                      const double refStep = 0.0,
                      const bool allowFlip = false,
                      const double launchAnchorPrice = 0.0)
{
    if(tRef <= 0 || pRef <= 0 || tol < 0) return false;
    TH3PivotSix chartP[], structP[], macroP[];
    ArrayResize(chartP, TH3_P6_MAX_PIVOTS);
    ArrayResize(structP, TH3_P6_MAX_PIVOTS);
    ArrayResize(macroP, TH3_P6_MAX_PIVOTS);
    int nc = 0, ns = 0, stf = 0;
    // P-TH3-D4d: the window ends at the reference point, so a pattern drawn
    // on old history reads its own candles, not the latest 400 bars.
    if(!TH3PivotsRead(chartP, structP, nc, ns, stf, tRef)) { nc = 0; ns = 0; }
    int nm = 0, mtf = 0;
    if(!TH3MacroPivotsRead(macroP, nm, mtf, tRef)) nm = 0;
    int tf_pattern = Period();
    int tf_structure = TH3FractalStepTF(tf_pattern, 1);
    int tf_macro = TH3FractalStepTF(tf_pattern, 2);
    double step = (refStep > 0 ? refStep : TH3PatternStepRungTF(tf_structure));
    if(step <= 0) return false;

    // the tolerance LADDER (P-TH3-MP2): the tiers are entry gates only;
    // the score decides. Tier 1 = the caller's own tol (backward-compat
    // with the old single-tol callers and the §9 tests), tier 2/3 = the
    // wide tiers that reach the FAR mother the old code could not see.
    double tol1 = MathMax(tol, TH3_MP_TOL_STEP * step);
    double tol2 = MathMax(tol1, TH3_MP_TOL_WIDE * step);
    double tol3 = MathMax(tol2, TH3_MP_TOL_SPAN * step);

    datetime aEff = (anchorTime > 0 ? anchorTime : tRef);
    bool found = false;
    double bestScore = -1e9, bestDist = 1e9;

    // three layers, one loop body: layer 0 chart, 1 structure, 2 macro
    for(int layer = 0; layer < 3; layer++)
    {
        int n = (layer == 0 ? nc : (layer == 1 ? ns : nm));
        for(int i = 0; i < n; i++)
        {
            TH3PivotSix c;
            if(layer == 0) c = chartP[i];
            else if(layer == 1) c = structP[i];
            else c = macroP[i];
            if(!c.valid) continue;          // base pivots COMPETE now (P-TH3-MP2)
            // P-TH3-D4: a D snapped onto its own pivot carries the pivot's
            // bar time, so equality with tRef is the HIT, not the future.
            if(c.time > tRef) continue;
            if(anchorTime > 0 && c.time >= anchorTime) continue;   // Pillar 1
            bool sameKind = (c.isHigh == wantHigh);
            if(!sameKind)
            {
                if(!allowFlip) continue;
                if(!TH3FlipProven(c.tf, c.price, c.isHigh, aEff, step)) continue;
            }
            double d = MathAbs(c.price - pRef);
            if(d > tol3) continue;          // the ladder's widest tier
            // the motherness score decides, not the gate:
            int touches = TH3MotherTouches(c.tf, c.price, c.confirmTime, tRef, step);
            // the launch test needs the leg's two ends. Inside the matcher the
            // only leg we know is anchor -> D (pRef): the near end is the
            // anchor's price — unknowable from a time alone — so the matcher
            // scores launch with the leg it CAN see: pRef itself. The full
            // A-origin launch wiring is the renderer's job (it holds pA) and
            // arrives here as the two optional leg params below (P-TH3-D4).
            double legStart = (launchAnchorPrice > 0 ? launchAnchorPrice : pRef);
            double legEnd   = pRef;
            bool launchOK = TH3MotherLaunch(MathMin(c.price, c.keyPrice),
                                            MathMax(c.price, c.keyPrice),
                                            legStart, legEnd);
            bool predates = (c.time < aEff);
            double s = TH3MotherScore(c, pRef, tf_structure, tf_macro, refStep,
                                      touches, step, launchOK, predates);
            if(s > bestScore || (s == bestScore && d < bestDist))
            { bestScore = s; bestDist = d; out = c; found = true; }
        }
    }
    return found;
}

//+------------------------------------------------------------------+
//| P-TH3-P6e Pillar 3 — S/R FLIP. An OPPOSITE-kind old extreme      |
//| counts as mother only if the market already honoured the flip:   |
//| a completed bar strictly before anchorTime closed beyond          |
//| price ± 0.5*TH_structure (above an old high = support, below an  |
//| old low = resistance). 0.5 is the corroboration's own half-step  |
//| ruler, not a new number. Bounded: 400 bars max past the anchor.  |
//+------------------------------------------------------------------+
bool TH3FlipProven(const int tf, const double pivPrice, const bool pivIsHigh,
                   const datetime anchorTime, const double thStruct)
{
    if(tf <= 0 || pivPrice <= 0 || anchorTime <= 0 || thStruct <= 0) return false;
    int n = iBars(NULL, tf);
    if(n < 5) return false;
    int aBar = iBarShift(NULL, tf, anchorTime);
    if(aBar < 0) return false;
    int first = aBar + 1;
    if(first < 1) first = 1;
    int last = first + 400;
    if(last >= n) last = n - 1;
    for(int j = first; j <= last; j++)
    {
        double c = iClose(NULL, tf, j);
        if(c <= 0) continue;
        if(pivIsHigh && c > pivPrice + 0.5 * thStruct) return true;
        if(!pivIsHigh && c < pivPrice - 0.5 * thStruct) return true;
    }
    return false;
}

// (P-TH3-MP2: the old Pillars 1-4 matcher was replaced by the ladder
// matcher above — its body is gone; the Pillar docs live in the new
// function's own comment.)

//+------------------------------------------------------------------+
//| SNAP — put a manual click ON the pivot the course would see.     |
//| A click within one bar of a found chart-TF pivot lands on that   |
//| pivot's own extreme, so the drawn X/A/B/C sit on six-condition   |
//| pivots and the skeleton's axes measure the same candles the      |
//| detector read. Pure — no objects, no redraw.                     |
//+------------------------------------------------------------------+
bool TH3PivotSnap(datetime &t, double &p)
{
    TH3PivotSix piv[]; TH3PivotSix st[];
    ArrayResize(piv, TH3_P6_MAX_PIVOTS); ArrayResize(st, 1);
    int nc = 0, ns = 0, stf = 0;
    // P-TH3-D4d: snap reads the click's own window (old history included).
    if(!TH3PivotsRead(piv, st, nc, ns, stf, t) || nc <= 0) return false;
    int clickBar = iBarShift(NULL, 0, t);
    if(clickBar < 0) return false;
    int best = -1, bestDist = 2;   // within one bar of the click
    for(int i = 0; i < nc; i++)
    {
        if(!piv[i].valid || piv[i].base) continue;
        int pb = iBarShift(NULL, 0, piv[i].time);
        if(pb < 0) continue;
        int dist = MathAbs(pb - clickBar);
        if(dist < bestDist) { bestDist = dist; best = i; }
    }
    if(best < 0) return false;
    t = piv[best].time;
    p = piv[best].price;
    return true;
}

//+------------------------------------------------------------------+
//| P-TH3-STEP-03 (2026-09-19) — THE STEP, PROVEN OFF THE HIT PIVOT. |
//|                                                                  |
//| The course states the update rule itself (PDF p. 2): "می توان     |
//| پس از اینکه قیمت به این گام های حرکتی واکنش نشان داد آن ها را    |
//| آپدیت و به روز رسانی کرد" — once price has REACTED to the rungs, |
//| the rungs are recalibrated from that reaction. Measured here     |
//| backwards:                                                       |
//|                                                                  |
//|   1. from C, walk the completed bars for the reaction's TIP (the |
//|      furthest extreme in the D direction);                       |
//|   2. find WHICH six-condition pivot that tip hit — on the chart  |
//|      TF or the structure TF (TH3PivotsRead), nearest by price    |
//|      inside a rung-sized tolerance; the answer carries its own   |
//|      timeframe, so "قیمت به چه پیوتی از چه تایمی رسیده" is part  |
//|      of the result, not a guess;                                 |
//|   3. the rung k it landed on — P-TH3-STEP-09: k in {3,5}, read off  |
//|      the closed seed (|C-B|/K), never assumed; outside ±25% there  |
//|      is no vote and the ladder keeps its seed.                     |
//|      and "اول باشه یا دورتر، چندین مرتبه رد شده" is answered by  |
//|      `touches`: how many separate crossings of that level        |
//|      happened after C.                                           |
//|                                                                  |
//|   implied step = |C - tip| / k        (the formula)              |
//|   rungErr      = |step - rung| / rung (the proof)                |
//|                                                                  |
//| Pure: bars and the pivot cache in, a struct out — no objects.    |
//+------------------------------------------------------------------+
struct TH3HitProof
{
    bool     valid;
    datetime tipTime;      // the reaction's extreme bar
    double   tipPrice;
    datetime pivTime;      // the pivot the tip hit
    double   pivPrice;
    bool     pivIsHigh;
    int      pivTF;        // which timeframe owned the hit pivot (minutes, 0=none)
    bool     shared;       // p. 50: a higher-TF pivot claims it
    int      k;            // the rung the tip landed on (3 or 5 — P-TH3-STEP-09)
    double   k5Err;        // the second-pivot check (|C-p2|/5 vs step), reported not fitted
    double   step;         // |C - tip| / 3
    double   rung;         // the ladder's own rung, for comparison
    double   rungErr;      // |step - rung| / rung
    int      touches;      // separate crossings of the level after C
    bool     hasPivot;     // a six-condition pivot sits at the tip (the proof)
    double   deepestRungs; // P-TH3-STEP-04e: the deepest reaction extreme seen,
                           // in rungs — the WHY of a rejected reaction, filled
                           // even when the measure returns false
};

//+------------------------------------------------------------------+
//| P-TH3-STEP-09 (2026-09-19) — k IS READ, NOT ASSUMED.              |
//|                                                                  |
//| The shipped code divided EVERY tip by 3. A first tip that is      |
//| really rung 5 (a 5-step run before any declaration) then minted   |
//| a step 66% too big (XAUUSD: 1753.6/3 = 584.5 against the closed   |
//| 370.4; 1753.6/5 = 350.7). So both candidates are tried and the    |
//| one nearer refStep wins — refStep is the closed |C-B|/K seed, or  |
//| <= 0 for the legacy k = 3 path. A tie keeps 3, the course        |
//| default. A winner farther than TH3_HIT_MAX_STEP_ERR from refStep  |
//| is NO vote (false): the ladder keeps its seed. Pure arithmetic,   |
//| pinned in Biotak_TH3_Test.mq4 §10.                                |
//+------------------------------------------------------------------+
bool TH3HitKPick(const double dist, const double refStep,
                 int &kOut, double &stepOut)
{
    kOut = 3; stepOut = 0;
    if(dist <= 0) return false;
    if(refStep <= 0) { stepOut = dist / 3.0; return (stepOut > 0); }
    double s3 = dist / 3.0, s5 = dist / 5.0;
    if(MathAbs(s5 - refStep) < MathAbs(s3 - refStep)) { kOut = 5; stepOut = s5; }
    else { kOut = 3; stepOut = s3; }
    if(stepOut <= 0) return false;
    return (MathAbs(stepOut - refStep) / refStep <= TH3_HIT_MAX_STEP_ERR);
}

// The proof slot of the rebase memo (P-TH3-PERF-08 — the block above
// TH3RealD states the rule for both slots). This is the one that matters per
// TICK: TH3HitPivotForward calls this measure on every OnCalculate, and the
// walk it saves (local extremes down to bar 3, then the crossings walk, both
// on completed bars) cannot answer differently until a new bar closes.
static datetime     s_hpC    = 0;
static double       s_hpP    = 0.0;
static double       s_hpRung = 0.0;
static double       s_hpRef  = 0.0;
static int          s_hpBars = -1;
static int          s_hpTF   = -1;
static bool         s_hpDir  = false;
static bool         s_hpHave = false;
static TH3HitProof  s_hpOut;

bool TH3HitMemoArm(const datetime tC, const double pC, const bool dirDown,
                   const double rung, const double refStep,
                   const TH3HitProof &result)
{
    s_hpC = tC; s_hpP = pC; s_hpDir = dirDown; s_hpRung = rung;
    s_hpRef = refStep; s_hpBars = iBars(NULL, 0); s_hpTF = Period();
    s_hpOut = result; s_hpHave = true;
    return result.valid;
}

bool TH3HitPivotMeasure(const datetime tC, const double pC, const bool dirDown,
                        const double rung, TH3HitProof &out,
                        const double refStep = 0.0)
{
    out.valid = false;
    out.deepestRungs = 0;

    // P-TH3-PERF-08: the proof slot. The key carries `refStep` because the
    // closed-seed gate (P-TH3-STEP-09) reads it — two callers measuring the
    // same tip against different seeds owe two answers, not one.
    if(s_hpHave && tC > 0 && pC > 0 && rung > 0 && tC == s_hpC && pC == s_hpP &&
       dirDown == s_hpDir && rung == s_hpRung && refStep == s_hpRef &&
       iBars(NULL, 0) == s_hpBars && Period() == s_hpTF)
    {
        s_th3RebaseHits++;
        out = s_hpOut;
        return out.valid;
    }
    s_th3RebaseMiss++;

    if(tC <= 0 || pC <= 0 || rung <= 0) return false;

    // 1+2. P-TH3-STEP-04b (2026-09-19) — THE TIP IS THE FIRST OPPOSITE PIVOT.
    // The user's own rule, stated on an H1 chart: the FIRST reaction after C
    // IS rung 3 — 100%, by construction. The old "furthest extreme ÷ k" read
    // the continuation (rung 5's own level) as the tip and divided THAT by 3,
    // building a 29.7 step out of an 18.0 one: (4119-4030)/3 instead of
    // (4084-4030)/3. Now there is no extremum walk at all: the reaction tip
    // is the first six-condition pivot of the REACTION's kind after C
    // (a LOW pivot when C is high / dirDown, a HIGH pivot when C is low),
    // looked up on the chart TF first and the structure TF next — the walk
    // UP the chain the user asked for when the chart's own grid is silent.
    // P-TH3-STEP-04d (2026-09-19): the pivot cache is read ONCE, below the tip
    // walk — the block here used to read it a second time, a leftover of the
    // 04b->04c port, and the twin declaration is a compile error in MQL4.
    const bool wantHigh = !dirDown;   // C low -> reaction up -> first HIGH pivot
    int startBar = iBarShift(NULL, 0, tC);
    // need two newer bars to close an extreme
    if(startBar < 4) return TH3HitMemoArm(tC, pC, dirDown, rung, refStep, out);

    // 1+2. P-TH3-STEP-04c (2026-09-19) — THE TIP IS THE FIRST LOCAL EXTREME
    // OF THE REACTION, not necessarily a six-condition pivot. The six-condition
    // match stays the CORROBORATION (the `hasPivot` flag decides how the
    // verdict is WORDed, never whether the step exists).
    // P-TH3-STEP-04d: a wiggle that never travelled the floor is not a
    // candidate at all — the walk SKIPS it and asks the next one (the user's
    // "step drew cramped next to the pivot tip": a 2-rung bounce used to be
    // read as step 3 and rebuilt the ladder 33% smaller than the market had
    // proven). P-TH3-STEP-04e (2026-09-19): the floor is 2.40 rungs, not 3.00 —
    // measured on the user's own XAUUSD H1 chart, C = 4282.40 (2026-09-02
    // 06:00) reacted 489.9 pips to its first tip = 2.69 rungs, and that leg
    // divides the reaction EXACTLY as the course's ladder has it: tip = step 3
    // (2.69/3 x 3 = 2.69) and the next extreme (09-02 17:00, 1151.3 pips) = step
    // 7.05. The 3.00-rung gate of 04d refused that leg, read the 6.33-rung
    // CONTINUATION as the tip instead, and built a 383.8-pip step (2.1 rungs)
    // that no reaction sat on — while leaving the ladder frozen on its ATR seed
    // on every chart whose first leg fell short of 3 rungs. The market may only
    // WIDEN the grid past the seed and may never cramp it below 0.80.
    // P-TH3-STEP-04e: every extreme the walk looks AT is measured, so a reaction
    // that never reached the floor can say how far it did reach (deepestRungs).
    // "rung - no reaction yet" was a dead end to read: it could not be told apart
    // from a build that never ran the walk at all, which is exactly the report
    // that sent this pass looking.
    int tipBar = -1;
    double tipP = 0;
    double deepest = 0;
    for(int i = startBar - 3; i >= 3; i--)
    {
        double h0 = iHigh(NULL, 0, i), l0 = iLow(NULL, 0, i);
        if(h0 <= 0 || l0 <= 0) continue;
        if(wantHigh)
        {
            bool top = true;
            for(int k = i - 2; k <= i + 2 && top; k++)
            {
                double hk = iHigh(NULL, 0, k);
                if(hk <= 0 || (k != i && hk >= h0)) top = false;
            }
            if(top)
            {
                double d = MathAbs(pC - h0);
                if(d > deepest) deepest = d;
                if(d >= TH3_STEP_MIN_LEG_RUNGS * rung) { tipBar = i; tipP = h0; break; }
            }
        }
        else
        {
            bool bot = true;
            for(int k = i - 2; k <= i + 2 && bot; k++)
            {
                double lk = iLow(NULL, 0, k);
                if(lk <= 0 || (k != i && lk <= l0)) bot = false;
            }
            if(bot)
            {
                double d = MathAbs(pC - l0);
                if(d > deepest) deepest = d;
                if(d >= TH3_STEP_MIN_LEG_RUNGS * rung) { tipBar = i; tipP = l0; break; }
            }
        }
    }
    out.deepestRungs = deepest / rung;   // reported either way
    // no reaction reached the floor yet: a REFUSAL THAT CARRIES A NUMBER, so it
    // is armed with the rest — the forward pass asks it again every tick and the
    // answer (and deepestRungs) cannot move within the bar.
    if(tipBar < 0) return TH3HitMemoArm(tC, pC, dirDown, rung, refStep, out);

    TH3PivotSix chartP[], structP[];
    ArrayResize(chartP, TH3_P6_MAX_PIVOTS);
    ArrayResize(structP, TH3_P6_MAX_PIVOTS);
    int nc = 0, ns = 0, stf = 0;
    // P-TH3-D4d: corroboration reads the tip's own window, not the latest bars.
    if(!TH3PivotsRead(chartP, structP, nc, ns, stf, iTime(NULL, 0, tipBar))) { nc = 0; ns = 0; }
    // the corroboration only: does a six-condition pivot of the reaction's
    // kind sit ON the tip (same bar ± 2, same price within half a step)?
    // It WORDS the verdict ("T3 <- H1 H x2"), never the arithmetic — the
    // local extreme already proved the step by construction (P-TH3-STEP-04c).
    int layer = -1, src = -1;
    for(int i = 0; i < nc; i++) {
        if(!chartP[i].valid || chartP[i].base) continue;
        if(chartP[i].isHigh != wantHigh) continue;
        int pb = iBarShift(NULL, 0, chartP[i].time);
        if(pb < 0 || MathAbs(pb - tipBar) > 2) continue;
        if(MathAbs(chartP[i].price - tipP) > 0.5 * (MathAbs(pC - tipP) / 3.0 > 0
            ? MathAbs(pC - tipP) / 3.0 : rung)) continue;
        layer = 0; src = i; break;
    }
    if(src < 0) {
        int stfBar = iBarShift(NULL, stf, iTime(NULL, 0, tipBar));
        for(int j = 0; j < ns && stfBar >= 0; j++) {
            if(!structP[j].valid || structP[j].base) continue;
            if(structP[j].isHigh != wantHigh) continue;
            int pb = iBarShift(NULL, stf, structP[j].time);
            if(pb < 0 || MathAbs(pb - stfBar) > 1) continue;
            layer = 1; src = j; break;
        }
    }

    double pivPrice = (src < 0) ? tipP
                    : (layer == 0 ? chartP[src].price : structP[src].price);
    datetime pivTime = (src < 0) ? iTime(NULL, 0, tipBar)
                     : (layer == 0 ? chartP[src].time : structP[src].time);

    // P-TH3-STEP-04e — THE FLOOR IS THE STEP'S, NOT THE LEG'S (see the macro).
    // The walk above already skipped reactions that imply a step under 0.80 of
    // the rung; this is the safety net for the case the pivot match landed on a
    // neighbour bar slightly nearer C. The course's rule is that the market must
    // react (PDF p. 2/50); a reaction that never travelled the floor is no proof,
    // the ladder keeps its rung (TH3PatternStepRung — step 3 = 3 x TH, the
    // professor's fractal rung P-TH3-STEP-08; the thousand-chart survey's
    // step3/ATR ~ 1.0 was on the ATR ruler, so a TH seed draws tighter),
    // real reaction recalibrates it. The proved step can therefore never fall
    // under 0.80 of the rung; the market may only WIDEN the grid.
    double dist = MathAbs(pC - pivPrice);
    if(dist <= 0) return TH3HitMemoArm(tC, pC, dirDown, rung, refStep, out);
    if(dist < TH3_STEP_MIN_LEG_RUNGS * rung)
        return TH3HitMemoArm(tC, pC, dirDown, rung, refStep, out);
    // P-TH3-STEP-09 — k is READ off refStep (the closed seed), not assumed:
    // a rung-5 first tip divided by 3 minted steps 66% too big. A winner
    // outside the gate is no vote — the ladder keeps its seed.
    int k = 3;
    double step = dist / 3.0;
    if(refStep > 0)
    {
        if(!TH3HitKPick(dist, refStep, k, step))
            return TH3HitMemoArm(tC, pC, dirDown, rung, refStep, out);
    }
    if(step <= 0) return TH3HitMemoArm(tC, pC, dirDown, rung, refStep, out);

    // 4. the corroboration the user drew the second arrow for: the NEXT
    //    pivot of the same kind should sit near rung 5 of the same step.
    //    k5Err is the check (|C-p2|/5 vs step); 0 when no second pivot yet.
    //    It is REPORTED, never fitted — the step comes from rung 3 alone.
    double k5Err = 0;
    {
        int second = -1;
        for(int i = 0; i < nc; i++) {
            if(!chartP[i].valid || chartP[i].base) continue;
            if(chartP[i].time <= pivTime || chartP[i].isHigh != wantHigh) continue;
            if(second < 0 || chartP[i].time < chartP[second].time) second = i;
        }
        if(second >= 0) {
            double d2 = MathAbs(pC - chartP[second].price);
            if(d2 > 0) k5Err = MathAbs((d2 / 5.0) - step) / step;
        }
    }

    // the crossings: how many SEPARATE touches of the pivot's level after C
    // (consecutive bars inside the tolerance count as one touch — "چندین
    // مرتبه رد شده" is a count of visits, not of bars).
    double tol = 0.5 * step;
    int touches = 0;
    bool inside = false;
    if(startBar >= 1) {
        for(int i = startBar - 1; i >= 1; i--)
        {
            double h = iHigh(NULL, 0, i), l = iLow(NULL, 0, i);
            if(h <= 0 || l <= 0) continue;
            bool hit = (l - tol <= pivPrice) && (h + tol >= pivPrice);
            if(hit && !inside) touches++;
            inside = hit;
        }
    }

    out.valid = true;
    out.tipTime = pivTime;
    out.tipPrice = pivPrice;
    out.pivTime = pivTime;
    out.pivPrice = pivPrice;
    out.pivIsHigh = wantHigh;
    out.pivTF = (src < 0) ? 0 : (layer == 0 ? Period() : stf);
    out.shared = (src >= 0)
               && (layer == 0 ? chartP[src].shared : structP[src].shared);
    out.k = k;
    out.step = step;
    out.rung = rung;
    out.rungErr = MathAbs(step - rung) / rung;
    out.touches = touches;
    out.hasPivot = (src >= 0);
    out.k5Err = k5Err;
    return TH3HitMemoArm(tC, pC, dirDown, rung, refStep, out);
}

string TH3TfName(const int tf)
{
    if(tf == 1)     return "M1";
    if(tf == 5)     return "M5";
    if(tf == 15)    return "M15";
    if(tf == 30)    return "M30";
    if(tf == 60)    return "H1";
    if(tf == 240)   return "H4";
    if(tf == 1440)  return "D1";
    if(tf == 10080) return "W1";
    if(tf == 43200) return "MN";
    return IntegerToString(tf);
}

//+------------------------------------------------------------------+
//| Does THIS timeframe's own six-condition set claim a pivot at the |
//| tip? (P-TH3-STEP-03b: when the chart's grid has no pivot at the  |
//| reaction, the reaction belongs to a bigger TF's grid — the walk  |
//| up the chain asks each TF exactly this question.)                |
//+------------------------------------------------------------------+
bool TH3SixPivotsHasPivotAt(const int tf, const datetime tipTime,
                            const double tipPrice, const double tol,
                            double &price)
{
    TH3PivotSix piv[];
    ArrayResize(piv, TH3_P6_MAX_PIVOTS);
    // P-TH3-D4d: claim reads the tip's own window.
    int n = TH3SixPivotsScanTF(tf, piv, TH3_P6_MAX_PIVOTS, 400, tipTime);
    if(n <= 0) return false;
    int tipBar = iBarShift(NULL, tf, tipTime);
    if(tipBar < 0) return false;
    for(int i = 0; i < n; i++)
    {
        if(!piv[i].valid || piv[i].base) continue;
        int pb = iBarShift(NULL, tf, piv[i].time);
        if(pb < 0) continue;
        if(MathAbs(pb - tipBar) <= 1 && MathAbs(piv[i].price - tipPrice) <= tol)
        {
            price = piv[i].price;
            return true;
        }
    }
    return false;
}

//+------------------------------------------------------------------+
//| CLOSED-LOOP STEP (P-TH3-STEP-08, 2026-09-19) — user: full replace |
//| + «از th باید استفاده بشه نه از atr».                             |
//|                                                                  |
//| Mapping to OUR X/A/B/C (stated once, no rename): our X = their A  |
//| (origin top), our A = their B (first low), our B = their C        |
//| (retrace high), our C = their D (pivot collision). NOTHING is     |
//| renamed: X stays the wave-analysis origin (TH3Math.mqh:719).      |
//| legBC_theirs = |B-A|_ours, legCD_theirs = |C-B|_ours, so          |
//|   ratio = |pC-pB| / |pB-pA|  (our BC/AB, already WaveAnalysis'     |
//|   BC_AB_Ratio) and Step = |pC-pB| / K. The ladder projects from   |
//|   our C (= their D), exactly where the renderer already starts    |
//|   its targets ("Targets start from C (not D)", TH3Renderer.mqh).  |
//|                                                                  |
//| K table (P-TH3-STEP-13 unified formula): 0.75-0.85 -> 2.5,      |
//| 0.85-1.20 -> 3.0, 1.20-1.80 -> 3.5, >1.80 -> 1.666. Below 0.75 is |
//| NO answer (false), the same spirit as the 2.40-rung floor: a      |
//| shallower wiggle must not mint a step. >1.80 is an EXTENDED leg   |
//| (acceleration, not a deeper retrace): 4.5 chopped it (XAUUSD M15   |
//| 560/4.5 = 124 pips, ladder collapse); 1.666 lands it (560/1.666 =  |
//| 336.1 ≈ 340 = macro span/3, the unified reading).                 |
//|                                                                  |
//| Ownership gate: Nbars = bars B->C (= their C->D). 3..7 = current  |
//| TF owns it; >7 = walked up one chain step (TH3FractalStepTF).     |
//| <3 = current TF (young leg, not a walk-up). The gate picks the    |
//| GRID (which TF's rung to compare/seed), never the arithmetic:     |
//| the closed step stays |C-B|/K.                                    |
//|                                                                  |
//| Pure + built-ins only (no chart objects) so this stays domain:    |
//| Lite-safe, test-harness-safe (P-BUILD-01/02).                     |
//+------------------------------------------------------------------+
#define TH3_CL_K_SYM   2.5
#define TH3_CL_K_DEEP  3.0
#define TH3_CL_K_EXT   3.5
// P-TH3-STEP-13: extended legs divide by 1.666, never 4.5.
#define TH3_CL_K_MACRO 1.666

double TH3ClosedK(const double ratio)
{
    if(ratio < 0.75) return 0.0;   // no answer below the table
    if(ratio <= 0.85) return TH3_CL_K_SYM;
    if(ratio <= 1.20) return TH3_CL_K_DEEP;
    if(ratio <= 1.80) return TH3_CL_K_EXT;
    return TH3_CL_K_MACRO;
}

bool TH3ClosedStepFromLegs(const double pA, const double pB, const double pC,
                           double &stepOut, double &kOut, double &ratioOut)
{
    stepOut = 0; kOut = 0; ratioOut = 0;
    if(pA <= 0 || pB <= 0 || pC <= 0) return false;
    double legAB = MathAbs(pB - pA);   // their legBC
    double legBC = MathAbs(pC - pB);   // their legCD
    if(legAB <= 0 || legBC <= 0) return false;
    double ratio = legBC / legAB;
    double k = TH3ClosedK(ratio);
    if(k <= 0) return false;
    double step = legBC / k;
    if(step <= 0) return false;
    stepOut = step; kOut = k; ratioOut = ratio;
    return true;
}

// Bars between OUR B and C (= their C->D leg). -1 when unmeasurable.
int TH3ClosedBars(const datetime tB, const datetime tC)
{
    if(tB <= 0 || tC <= 0) return -1;
    int barB = iBarShift(NULL, 0, tB);
    int barC = iBarShift(NULL, 0, tC);
    if(barB < 0 || barC < 0) return -1;
    return MathAbs(barB - barC);
}

// Which TF owns the grid.
//
// P-TH3-STEP-10 (2026-09-19) — WALK, DON'T JUMP. One chain step was not
// enough: a 168-bar H1 build walked to H4 and stopped, leaving H4 with
// 42 bars — still out of its own [3,7] gate, so the rule contradicted
// itself after one application. The SAME gate now reapplies per rung
// (no new numbers): the span is converted into the upper TF by minute
// ratio and the climb repeats until the count lands in [3,7] or the
// chain top is reached. XAUUSD H1/168 -> H4/42 -> D1/7: the Daily
// ownership falls out of the existing rule, no 48h constant needed.
// H1 bars/run -> H4 = /4, H4 -> D1 = /6, D1 -> W1 = /7: the minute
// ratio carries the exact factor, so approximations are not hardcoded.
int TH3ClosedOwnerTFEx(const int tfMin, const int cdBars)
{
    if(cdBars <= 7 || tfMin <= 0) return (tfMin > 0 ? tfMin : Period());
    int owner = tfMin;
    int bars = cdBars;
    for(int w = 0; w < 6; w++)
    {
        int up = TH3FractalStepTF(owner, 1);
        if(up == owner) return owner;   // chain top: nowhere higher to ask
        double conv = (up > 0) ? ((double)bars * (double)owner / (double)up) : 0.0;
        bars = (int)MathRound(conv);
        owner = up;
        if(bars <= 7) return owner;
    }
    return owner;
}

int TH3ClosedOwnerTF(const int cdBars)
{
    return TH3ClosedOwnerTFEx(Period(), cdBars);
}

//+------------------------------------------------------------------+
//| THE LIVE RUNG - one owner for the chart own step (P-TH3-STEP-08). |
//| P-TH3-STEP-05 REPLACED per user («از th باید استفاده بشه نه از    |
//| atr»): the rung is the professor's fractal-ladder TH              |
//| (THAbilityPrice, P-BK-92) — (anchor-bar close x rung %) / 100 —   |
//| off the last COMPLETED bar, never the forming one. 0 = absent.    |
//|                                                                  |
//| HONESTY NOTE (kept, AGENTS.md): this is a DIFFERENT ruler than    |
//| ATR (H1: 72.9 pips TH vs 185.3 ATR), so step 3 = 3 x TH draws     |
//| ~60% tighter than the surveyed step3/ATR ~ 1.0 (step3_survey.py). |
//| The market-vote path (TH3HitPivotMeasure, k = 3 fixed) and the    |
//| 2.40-rung floor stay armed, so a real reaction still WIDENS the   |
//| grid past this seed; without a vote the ladder rides TH.          |
//|                                                                  |
//| Harness-safe: Biotak_TH3_Test.mq4 does NOT include THCalculations |
//| (P-BUILD-02), so where TH_CALCULATIONS_MQH is absent this falls   |
//| back to the old ATR read instead of breaking the compile.         |
//+------------------------------------------------------------------+
double TH3PatternStepRungTF(const int tfMin)
{
#ifdef TH_CALCULATIONS_MQH
    datetime a = iTime(NULL, tfMin, 1);
    double th = 0.0;
    if(a > 0) th = THAbilityPrice(tfMin, a);
    else th = THAbilityPrice(tfMin, 0);
    if(th > 0.0) return th;
    return 0.0;
#else
    double a = iATR(NULL, tfMin, 14, 1);
    if(a == EMPTY_VALUE || a <= 0) return 0.0;
    return a;
#endif
}

double TH3PatternStepRung()
{
    return TH3PatternStepRungTF(Period());
}

//+------------------------------------------------------------------+
//| P-TH3-THB (2026-09-19) — THE FRACTAL TH BRACKETS (user task #3). |
//| The law: time x4 -> volatility x2 (TH_n = TH_0 x 2^n — the       |
//| footer table M1..D45 already doubles per rung: 9.0, 18.1, 36.2,  |
//| 72.4 ...). Each tier reads through THREE brackets: lower 1.50 x  |
//| TH, the STANDARD LONG STEP 1.75 x TH, transition 2.00 x TH. The  |
//| brackets are the law's own numbers, not a new fit.               |
//+------------------------------------------------------------------+
#define TH3_THB_LOWER   1.50
#define TH3_THB_LS      1.75
#define TH3_THB_UPPER   2.00

double TH3THBracketTF(const int tfMin, const double bracket)
{
    if(bracket <= 0) return 0.0;
    double th = TH3PatternStepRungTF(tfMin);
    if(th <= 0) return 0.0;
    return th * bracket;
}

//+------------------------------------------------------------------+
//| P-TH3-PERF-08 (2026-09-20) — THE REBASE MEMO.                    |
//|                                                                  |
//| The ladder is REBASED from the same pattern far more often than   |
//| its inputs move. `TH3HitPivotForward` re-measures the ACTIVE      |
//| pattern's proof on EVERY tick (OnCalculate calls it directly),    |
//| and `DrawABCDPattern` re-runs the whole rebase on every drag      |
//| event and on every settings redraw. Both rebases re-walked the    |
//| bars from scratch, and neither walk can answer differently until  |
//| a NEW BAR closes: `TH3RealDAt` reads completed bars only (its     |
//| threshold is the seed or the bar's own ATR at shift 1), and       |
//| `TH3HitPivotMeasure` reads completed bars plus the pivot scan,    |
//| which is itself cached per new bar of its own TF (`TH3PivotsRead`).|
//|                                                                  |
//| So each walk is memoised into ONE slot: THE SAME INPUTS ON THE    |
//| SAME BAR RETURN THE VERY STRUCT THE WALK WOULD HAVE REBUILT. A    |
//| FAILURE is memoised too — "no reaction reached the floor yet" and |
//| "price never left C" are ANSWERS, and they are the answers a      |
//| young pattern is asked for on every one of those ticks. To make   |
//| that hold by construction, arming is the ONE exit of each walk    |
//| past its key guard: a key that was checked is a key that was      |
//| written, so the version of the walk that ran is the only one the  |
//| memo can hand back.                                               |
//|                                                                  |
//| THE CLOCK IS `iBars(NULL, 0)`, the chart's own bar count, and the |
// key also carries `Period()`. The structure TF the pivot scan rides |
// (one chain step up) can only close a bar on a chart bar's edge, so |
// every change that scan can see also moves this clock — one clock,  |
// and a TF switch can never be answered from the old TF's memo.      |
//| Every OTHER input is in the key as well, so a drag (a new C), a    |
//| new rung or a new seed is a MISS and recomputes: nothing is ever   |
//| answered from a key that does not match it. This is the same      |
//| bar-count clock the repo's other bar caches ride (TH3PivotsRead,   |
//| TH3AvgCandleSize, GetCachedDailyATR), with the same stated limit:  |
//| it trusts that a past bar's OHLC is not rewritten without the      |
//| count moving.                                                      |
//|                                                                  |
//| ONE SLOT, TWO CALLERS, and the seam is stated rather than hidden:  |
//| the draw path measures at the REAL D with the ladder's own step,   |
//| the forward pass at the drawn C with the rung — different keys, so |
//| the first call after a switch recomputes and re-arms. That is one  |
//| walk per switch, not one per tick, which is the whole point: the   |
//| per-tick caller repeats ITS OWN key and hits, forever, until the   |
//| bar it was measured on is gone.                                    |
//|                                                                    |
//| Hits and misses are counted so the claim stays checkable:          |
//| `Biotak_TH3_Test.mq4` §12 pins that a repeated rebase is a HIT and |
//| that a changed price is a MISS (a perf claim with no number on it  |
//| is a claim).                                                       |
//+------------------------------------------------------------------+
static int s_th3RebaseHits = 0;
static int s_th3RebaseMiss = 0;

int TH3RebaseMemoHits()
{
    return s_th3RebaseHits;
}

int TH3RebaseMemoMisses()
{
    return s_th3RebaseMiss;
}

//+------------------------------------------------------------------+
//| P-TH3-REMARK (2026-09-19) — THE REAL D. The drawn C is where the |
//| user dropped the point; the MARKET may run the final leg farther |
//| before it reacts (EURUSD H4: C at 1.1510, the leg ran to 1.1320).|
//| The real D is the furthest extreme in the leg's direction after  |
//| C, ending at the first pullback of one seed step (or 0.8 ATR     |
//| when no seed) — the same 'reacted, leg is over' reading the six- |
//| condition cover uses. A leg still running returns its running    |
//| extreme (D is alive, the ladder rides it). Returns false when    |
//| price never left C — the drawn C IS the collision point. Pure.   |
//+------------------------------------------------------------------+
struct TH3RealD { bool valid; datetime time; double price; int bars; };

// The real-D slot of the rebase memo (P-TH3-PERF-08). File scope so the
// harness can read the counters; the key never leaves this file.
static datetime s_rdT    = 0;
static double   s_rdP    = 0.0;
static double   s_rdSeed = 0.0;
static int      s_rdBars = -1;
static int      s_rdTF   = -1;
static int      s_rdMax  = -1;
static bool     s_rdDown = false;
static bool     s_rdHave = false;
static TH3RealD s_rdOut;

// Arm the slot with this walk's own answer (valid or not) and hand that answer
// back, so every exit past the key guard is arm-and-return in one call.
bool TH3RealDMemoArm(const datetime tC, const double pC, const bool legDown,
                     const double seedStep, const int maxBars,
                     const TH3RealD &result)
{
    s_rdT = tC; s_rdP = pC; s_rdDown = legDown; s_rdSeed = seedStep;
    s_rdMax = maxBars; s_rdBars = iBars(NULL, 0); s_rdTF = Period();
    s_rdOut = result; s_rdHave = true;
    return result.valid;
}

bool TH3RealDAt(const datetime tC, const double pC, const bool legDown,
                const double seedStep, TH3RealD &out, const int maxBars = 500)
{
    out.valid = false; out.time = 0; out.price = 0; out.bars = 0;

    // P-TH3-PERF-08: the real-D slot. `tC > 0 && pC > 0` is part of the HIT
    // test, not an afterthought: it is what keeps the zero-initialised key
    // below from ever matching a stale slot on an unusable input.
    if(s_rdHave && tC > 0 && pC > 0 && tC == s_rdT && pC == s_rdP &&
       legDown == s_rdDown && seedStep == s_rdSeed && maxBars == s_rdMax &&
       iBars(NULL, 0) == s_rdBars && Period() == s_rdTF)
    {
        s_th3RebaseHits++;
        out = s_rdOut;
        return out.valid;
    }
    s_th3RebaseMiss++;

    if(tC <= 0 || pC <= 0) return false;   // no key to hold: nothing to arm
    int cBar = iBarShift(NULL, 0, tC);
    if(cBar < 0) return TH3RealDMemoArm(tC, pC, legDown, seedStep, maxBars, out);
    double a0 = iATR(NULL, 0, 14, 1);
    double thr = (seedStep > 0 ? seedStep
                 : (a0 > 0 && a0 != EMPTY_VALUE ? 0.8 * a0 : 0));
    if(thr <= 0) return TH3RealDMemoArm(tC, pC, legDown, seedStep, maxBars, out);
    double ext = pC;
    int extBar = cBar;
    int last = cBar - maxBars; if(last < 1) last = 1;
    for(int i = cBar - 1; i >= last; i--)
    {
        double h = iHigh(NULL, 0, i), l = iLow(NULL, 0, i);
        if(h <= 0 || l <= 0) continue;
        if(legDown)
        {
            if(l < ext) { ext = l; extBar = i; }
            if(h - ext >= thr) break;   // the leg's reaction: leg over
        }
        else
        {
            if(h > ext) { ext = h; extBar = i; }
            if(ext - l >= thr) break;
        }
    }
    // never left C: drawn C is D — an ANSWER (armed like any other), not only
    // a refusal: a fresh pattern asks it again on every tick until a new bar.
    if(extBar == cBar) return TH3RealDMemoArm(tC, pC, legDown, seedStep, maxBars, out);
    out.valid = true;
    out.time = iTime(NULL, 0, extBar);
    out.price = ext;
    out.bars = cBar - extBar;
    return TH3RealDMemoArm(tC, pC, legDown, seedStep, maxBars, out);
}

//+------------------------------------------------------------------+
//| P-TH3-LOCK (2026-09-19) — PATH 1 OF THE LOCKED STEP: THE NODE.   |
//| The mother pivot whose node D collided with carries its own      |
//| step: |key_line - node_edge| — the node's thickness itself. The  |
//| matcher finds the mother, this reads its node. Returns 0 when no |
//| mother answers (absence, never a guess). Pure domain.            |
//+------------------------------------------------------------------+
double TH3NodeStepAt(const datetime tRef, const double pRef, const bool wantHigh,
                     const double tol, TH3PivotSix &out,
                     const datetime anchorTime = 0,
                     const double refStep = 0.0,
                     const bool allowFlip = false,
                     const double launchAnchorPrice = 0.0)
{
    // P-TH3-STEP-12b (2026-09-21) — ONE matcher, ONE set of parameters.
    // The synthesis used to call this with every optional at its default
    // (no anchor, no refStep, no flip) while the mother-zone drawing on the
    // same D called TH3MotherPivotAt with anchor=A, refStep=closedStep,
    // allowFlip=true and the A-origin leg. Two matchers for one concept with
    // different gates can only disagree: the chart drew a mother the formula
    // reported as zero — the user's «مادر صفر» while a blue box sat on the
    // chart. Every caller now hands in the same terms, so a mother the chart
    // draws is a mother this measures, and vice versa.
    // P-TH3-STEP-13b: a MISS clears `out` (valid=false). The matcher only
    // writes `out` on a hit, so without this the caller's struct keeps its
    // garbage and TH3MacroSpanStep reads a phantom wick (the caption's giant
    // digit rows on XAUUSD M15).
    if(!TH3MotherPivotAt(tRef, pRef, wantHigh, tol, out,
                         anchorTime, refStep, allowFlip, launchAnchorPrice))
    {
        out.valid = false; out.time = 0; out.price = 0; out.keyPrice = 0;
        return 0.0;
    }
    double s = MathAbs(out.price - out.keyPrice);
    return (s > 0 ? s : 0.0);
}

//+------------------------------------------------------------------+
//| P-TH3-STEP-13 — MACRO SPAN: WICK, NOT BODY.                       |
//| The unified formula: Step = |collision - wick extremum| / k. The  |
//| pivot's extreme is out.price (the wick tip); keyPrice is the body |
//| line (cond-4). XAUUSD M15: body 4363 vs wick 4344 — 19 pips of    |
//| lie when the body is read. |D - price|/3 = 1020/3 = 340 pips.     |
//| Pure domain: numbers in, one number out. Pinned `macrospan:` in   |
//| Biotak_TH3_Test.mq4.                                              |
//+------------------------------------------------------------------+
double TH3MacroSpanStep(const double pRef, const TH3PivotSix &mp)
{
    if(pRef <= 0 || !mp.valid || mp.price <= 0) return 0.0;
    double span = MathAbs(pRef - mp.price);
    // Garbage guard: a span between two positive prices is always below the
    // bigger one — a phantom wick (uninitialised struct) reads astronomic.
    if(span <= 0 || span >= pRef) return 0.0;
    return span / 3.0;
}

//+------------------------------------------------------------------+
//| P-TH3-PB-MAN (2026-09-21) — THE HAND-TYPED BASE, AS A PRICE.    |
//| The pivot base is no longer DRAWN (P-TH3-PB's stage 5 is retired): |
//| the user types its height in the TH3 TOOL card, in pips, and this |
//| is the ONE owner that turns that number into Path 1 of            |
//| TH3LockedStep. 0 (or a dead pip size) answers 0 — absence, never  |
//| a guess — and the caller keeps its own seed (the pattern TF's own |
//| ATR). Pure domain: numbers in, one number out, no objects touched.|
//|                                                                    |
//| P-TH3-PB-RET8 (2026-09-22) — NO DIVISION HERE ANY MORE.           |
//| The typed number is a RETRACE, not a three-step leg: the user      |
//| marks a correction and that correction is already near the step,   |
//| so this answers the RAW price (pips x pip size). The 8-state       |
//| reading lives in TH3RetraceBestStep below — this stays the source. |
//+------------------------------------------------------------------+
double TH3ManualBaseStep(const double basePips, const double pipSize)
{
    if(basePips <= 0 || pipSize <= 0) return 0.0;
    return basePips * pipSize;
}

//+------------------------------------------------------------------+
//| P-TH3-PB-UI (2026-09-21) — EDGES TO PIPS, PURE.                  |
//| Two marked (or dragged) prices and the pip size in, BASE PIPS     |
//| out. <= 0 = not a base (absence, never a guess). Pinned in        |
//| Biotak_TH3_Test.mq4 (`pb-ui:`). Pure domain, no objects touched.  |
//+------------------------------------------------------------------+
double TH3BasePipsFromPrices(const double p1, const double p2, const double pipSize)
{
    if(p1 <= 0 || p2 <= 0 || pipSize <= 0) return 0.0;
    return MathAbs(p2 - p1) / pipSize;
}

//+------------------------------------------------------------------+
//| P-TH3-PB-RET8 (2026-09-22) — ONE RETRACE, EIGHT STATES.          |
//| The hand-typed base is a CORRECTION, not a leg: it can be 1/3 of  |
//| a step, 2/3, a full step, step+1/3, step+2/3, or a run bigger     |
//| than the step (2x, 3x, 5x). q = R / S, so each state implies one  |
//| candidate step S = R / q. The winner is the candidate nearest     |
//| BOTH the ABCD step (refStep = |CD|/K, pattern momentum, 60%) AND  |
//| the owner TF's rung (thRung: fractal volatility, 40%) — the same  |
//| 60/40 blend CalculateMultiFactorStep uses below. The rung arrives |
//| from the caller (seedRung = TH(ownerTF)), so this stays numbers-  |
//| in/number-out: Lite-safe (P-BUILD-01), harness-safe (P-BUILD-02). |
//| Pinned `ret8:` in Biotak_TH3_Test.mq4.                            |
//+------------------------------------------------------------------+
#define TH3_RETRACE_N 8

double TH3RetraceQ(const int idx)
{
    switch(idx)
    {
        case 0:  return (1.0 / 3.0);   // R = 1/3 step  -> S = 3R
        case 1:  return (2.0 / 3.0);   // R = 2/3 step  -> S = 1.5R
        case 2:  return 1.0;           // R = 1 step    -> S = R
        case 3:  return (4.0 / 3.0);   // R = step+1/3 -> S = 0.75R
        case 4:  return (5.0 / 3.0);   // R = step+2/3 -> S = 0.60R (= macro K 1.666)
        case 5:  return 2.0;           // R = 2 steps   -> S = R/2
        case 6:  return 3.0;           // R = 3 steps   -> S = R/3
        case 7:  return 5.0;           // R = 5 steps   -> S = R/5
    }
    return 0.0;
}

string TH3RetraceQName(const int idx)
{
    switch(idx)
    {
        case 0:  return "1/3";
        case 1:  return "2/3";
        case 2:  return "1";
        case 3:  return "4/3";
        case 4:  return "5/3";
        case 5:  return "2";
        case 6:  return "3";
        case 7:  return "5";
    }
    return "?";
}

double TH3RetraceCandidate(const double retracePrice, const int idx)
{
    double q = TH3RetraceQ(idx);
    if(retracePrice <= 0 || q <= 0) return 0.0;
    return retracePrice / q;
}

bool TH3RetraceBestStep(const double retracePrice, const double refStep,
                        const double thRung, double &bestStep,
                        double &bestQ, int &bestIdx)
{
    bestStep = 0; bestQ = 0; bestIdx = -1;
    if(retracePrice <= 0) return false;
    bool hasRef = (refStep > 0);
    bool hasTH  = (thRung > 0);
    if(!hasRef && !hasTH)   // no anchor at all: the retrace IS the step
    {
        bestStep = retracePrice; bestQ = 1.0; bestIdx = 2;
        return true;
    }
    double bestScore = 1e9, bestCentral = 1e9;
    for(int i = 0; i < TH3_RETRACE_N; i++)
    {
        double q = TH3RetraceQ(i);
        double s = TH3RetraceCandidate(retracePrice, i);
        if(s <= 0) continue;
        double score = 0;
        if(hasRef && hasTH)
        {
            double eP = MathAbs(s - refStep) / refStep;
            double eT = MathAbs(s - thRung) / thRung;
            score = 0.6 * eP + 0.4 * eT;
        }
        else if(hasRef)
            score = MathAbs(s - refStep) / refStep;
        else
            score = MathAbs(s - thRung) / thRung;
        double central = MathAbs(q - 1.0);   // tie-break: nearer q=1 wins
        if(score < bestScore - 1e-12 ||
           (MathAbs(score - bestScore) <= 1e-12 && central < bestCentral))
        { bestScore = score; bestCentral = central; bestStep = s; bestQ = q; bestIdx = i; }
    }
    return (bestStep > 0);
}

//+------------------------------------------------------------------+
//| فرمول چندعاملی محاسبه گام بر پایه پیوند پیوت مادر + پترن ABCD + TH|
//| P-TH3-STEP-12 (2026-09-21) — Step = f(Mother Pivot, ABCD, TH).     |
//| The step is never an isolated pick (not legCD/K alone, not a bare |
//| TH, not a raw pivot distance): the collision leg over its K (the  |
//| pattern's momentum), the detected mother node's size at D (macro  |
//| structure) and the owner TF's rung (fractal volatility) enter ONE  |
//| pure function. K selection itself stays in TH3ClosedK (the table's |
//| one owner) — the caller hands k_factor in; legAB rides along as    |
//| the K table's own ratio leg. motherPivotSize is the six-condition  |
//| mother's measured node |price-keyPrice| at D (TH3NodeStepAt), 0    |
//| when no mother answers. Pure domain: numbers in, one number out.  |
//+------------------------------------------------------------------+
double CalculateMultiFactorStep(const double legCD, const double legAB, const double k_factor,
                                const double motherPivotSize, const double thRung)
{
   if(k_factor <= 0) return thRung;

   // ۱. مؤلفه هندسی الگو
   double step_pattern = legCD / k_factor;

   // ۲. مؤلفه پیوت مادر
   double step_pivot = 0.0;
   if(motherPivotSize > 0)
   {
      // اگر بازه ماژور بین دو پیوت است تقسیم بر 3، اگر ضخامت گره است تقسیم بر 1
      step_pivot = (motherPivotSize >= 2.5 * thRung) ? (motherPivotSize / 3.0) : motherPivotSize;
   }

   // ۳. پیوند و هم‌افزایی ریاضی (تک‌عاملی نبودن گام):
   if(step_pivot > 0 && step_pattern > 0)
   {
      // در ساختارهای ماژور (که پیوت مادر وزن اصلی را دارد):
      if(motherPivotSize >= 3.0 * thRung)
      {
         // P-TH3-STEP-12b (2026-09-21) — THE MACRO MOTHER IS NOT BLENDED.
         // The course's own k = 3 on the mother's run: one step is the
         // mother's height / 3, so step 3 lands EXACTLY on the mother's far
         // edge. The old 65/35 weight dilated it (0.65 * mother/3 + 0.35 *
         // pattern) and step 3 stopped short of the pivot the eye was on —
         // the user's «گام ۳ باید روی کف پیوت مادر بنشیند» measured as a
         // ~20% shortfall. The pattern component stays in the caption as
         // corroboration (`pat=`), never inside the arithmetic: a blend of a
         // measurement with a reading is neither.
         return step_pivot;
      }
      else
      {
         // در ساختارهای اینترادی استاندارد:
         // میانگین هندسی/وزنی هماهنگ‌کننده پترن و پیوت مادر
         double intradayStep = MathSqrt(step_pattern * step_pivot);
         return intradayStep;
      }
   }

   // ۴. حالت پیش‌فرض (در صورت نبود پیوت مادر، الگو با TH تلفیق می‌شود)
   if(step_pattern > 0 && thRung > 0)
   {
      return (step_pattern * 0.60) + (thRung * 0.40);
   }

   return (step_pattern > 0) ? step_pattern : thRung;
}

//+------------------------------------------------------------------+
//| P-TH3-PB (2026-09-21) — THE LOCKED STEP, AS ONE PURE ARITHMETIC. |
//| This is the decision the ladder wears, lifted out of the draw     |
//| path so it can be pinned without a chart. The user's report —     |
//| «پیوت مبنا رو ... مشخص کردم ... step ها مثل قبل بودن که اپدیت     |
//| نشدن» — is a base that reached the store and stopped there: the   |
//| four PB lines moved and the ladder did not, because nothing read  |
//| the number.                                                        |
//|                                                                    |
//| P-TH3-PB-MAN (2026-09-21): NOTHING IS DRAWN ANY MORE. Path 1 is   |
//| the hand-typed base (`TH3ManualBaseStep` above, from               |
//| `inpTH3PivotBasePips`); the caller passes nodeStep = 0 — the      |
//| detector's own candidate no longer answers here. The function      |
//| itself is unchanged (numbers in, one number out), so the pins      |
//| below still hold whatever the source of pbStep is.                 |
//|                                                                    |
//| Inputs (all optional-by-zero, absence never a guess):              |
//|   closedStep  Path 2, |C-D| / K          (0 = the legs answer none)|
//|   pbStep      P-TH3-PB-MAN: the hand-typed base, in price.        |
//|               It is Path 1 stated by hand, so it wins over the     |
//|               detector's candidate and it survives the ±25% gate:  |
//|               a hand-typed node is an instruction, not a reading.  |
//|   nodeStep    RETIRED (P-TH3-PB-MAN): the caller always passes 0.  |
//|               Kept in the signature so the pins below still compile|
//|               and the history stays readable.                      |
//|   ownerTF/chartTF feed the walk-up shift (N>7): Step* = 2 x LS of  |
//|               the LOWER TF. A hand-typed base is exempt — that law  |
//|               compensates a closed step whose TF is bigger than the |
//|               chart, and the base already IS that geometry.         |
//|   pipSize     only formats the verdict string.                     |
//|                                                                    |
//| Returns false when NO path answers at all (the caller keeps its    |
//| own seed — the rung or the percentage fallback). Pure domain:      |
//| numbers in, one number out, no objects touched.                    |
//+------------------------------------------------------------------+
bool TH3LockedStep(double &step, string &how, bool &locked,
                   const double closedStep, const double pbStep,
                   const double nodeStep, const int ownerTF,
                   const int chartTF, const double pipSize)
{
    if(closedStep <= 0 && pbStep <= 0) return false;

    locked  = false;
    how     = "";
    step    = 0;

    // Path 1: the user's base first, then the detector.
    double p1 = (pbStep > 0 ? pbStep : nodeStep);

    if(closedStep > 0) {
        step = closedStep;
        if(p1 > 0) {
            double dev = MathAbs(p1 - closedStep) / closedStep;
            if(dev <= TH3_HIT_MAX_STEP_ERR) {
                step   = 0.5 * (p1 + closedStep);
                locked = true;
                how    = StringFormat("LOCKED %s node=%.1f pattern=%.1f",
                                      (pbStep > 0 ? "base" : "auto"),
                                      p1 / pipSize, closedStep / pipSize);
            } else {
                // P-TH3-PB-MAN: outside the band, the hand-typed base still
                // stands — the disagreement is stated in the caption, not
                // silently applied. (Verdict words kept: the pins read them.)
                if(pbStep > 0) step = pbStep;
                how = StringFormat("UNLOCKED %s node=%.1f vs %.1f",
                                   (pbStep > 0 ? "base" : "auto"),
                                   p1 / pipSize, closedStep / pipSize);
            }
        } else {
            how = "UNLOCKED-1P (no node)";
        }
        // the walk-up law — a hand-typed base is exempt (see header).
        if(ownerTF != chartTF && pbStep <= 0) {
            double lsLower = TH3THBracketTF(chartTF, TH3_THB_LS);
            if(lsLower > 0) {
                step   = 2.0 * lsLower;
                locked = false;
                how   += StringFormat(" -> SHIFT 2xLS(%s)=%.1f",
                                      TH3TfName(chartTF), step / pipSize);
            }
        }
    } else {
        // Path 1 alone: the hand-typed base and no closed step answered.
        // One path is not a lock, so the verdict says so (words kept).
        step = pbStep;
        how  = "base drawn (no closed step)";
    }
    return (step > 0);
}

//+------------------------------------------------------------------+
//| P-TH3-LOCK — THE LADDER STATE MACHINE, EXACT (user formula #4).  |
//| The gate is measured FROM THE LINES, not from the reaction tip:  |
//|   L3 touch  -> mandatory pullback >= 1.0 step from the L3 line   |
//|             -> THEN a close back through L3 arms Level5.         |
//|   L5 touch  -> mandatory pullback >= 2.0 step from the L5 line   |
//|             (or the trend reversal itself).                      |
//| Returns the milestone: 0 = L3 untouched or gate unmet, 1 = L3    |
//| gate passed (Level5 armed), 2 = L5's own 2-step retrace done.    |
//| retraceOut reports the retrace of the deepest station reached,   |
//| in steps. Pure domain: bars in, state out — no objects.          |
//|                                                                  |
//| P-TH3-STEP-14 (2026-09-22) — THE UNIFIED FORMULA, MEASURED.      |
//| tools/step3_base_collision.py, 1108 reactions (H1 314 / H4 603 /  |
//| D1 191, six-condition pivots, same detector as the product):     |
//| step = ATR(pattern TF) stands (survey step3/ATR 1.31/1.03/1.15); |
//| the C+-3*ATR line is REACHED 62.7/50.7/55.5% — a coin flip, never |
//| a guarantee, so a blind reverse limit at step 3 is forbidden and |
//| this gate (touch + reject) is the entry, not the line itself.    |
//| Past-base collision as predictor is REJECTED: tip within +-25% of |
//| a base <= 6 legs back hits 7.6/11.1/4.7% against a shuffle's     |
//| 10.2/12.6/9.2% (sign 2/9, 2/10, 1/11) — below chance on all TFs. |
//| Stated limit: bare extremes, not node zones with touches/launch  |
//| (the mother matcher tests that richer claim and is untouched).   |
//+------------------------------------------------------------------+
int TH3LadderMilestone(const datetime tC, const double pC, const bool ladderUp,
                       const double step, double &retraceOut)
{
    retraceOut = 0;
    if(tC <= 0 || pC <= 0 || step <= 0) return 0;
    int cBar = iBarShift(NULL, 0, tC);
    if(cBar < 1) return 0;
    double l3 = ladderUp ? pC + 3.0 * step : pC - 3.0 * step;
    double l5 = ladderUp ? pC + 5.0 * step : pC - 5.0 * step;

    // the FIRST completed bar that touched L3
    int l3Bar = -1;
    for(int i = cBar - 1; i >= 1; i--)
    {
        double h = iHigh(NULL, 0, i), l = iLow(NULL, 0, i);
        if(h <= 0 || l <= 0) continue;
        bool touch = ladderUp ? (h >= l3) : (l <= l3);
        if(touch) { l3Bar = i; break; }
    }
    if(l3Bar < 0) return 0;

    // deepest pullback from the L3 LINE after the touch (spec: Retrace3)
    double best3 = 0;
    int l5Bar = -1;
    for(int i = l3Bar - 1; i >= 1; i--)
    {
        double h = iHigh(NULL, 0, i), l = iLow(NULL, 0, i);
        if(h <= 0 || l <= 0) continue;
        double pull = ladderUp ? (l3 - l) : (h - l3);
        if(pull > best3) best3 = pull;
        bool l5touch = ladderUp ? (h >= l5) : (l <= l5);
        if(l5touch && l5Bar < 0) l5Bar = i;
    }
    double r3 = best3 / step;
    if(l5Bar < 0) { retraceOut = r3; return (r3 >= 1.0 ? 1 : 0); }

    // L5 was reached: its own mandatory retrace, from the L5 LINE
    double best5 = 0;
    for(int i = l5Bar - 1; i >= 1; i--)
    {
        double h = iHigh(NULL, 0, i), l = iLow(NULL, 0, i);
        if(h <= 0 || l <= 0) continue;
        double pull = ladderUp ? (l5 - l) : (h - l5);
        if(pull > best5) best5 = pull;
    }
    double r5 = best5 / step;
    retraceOut = MathMax(r3, r5);
    return (r5 >= 2.0 ? 2 : (r3 >= 1.0 ? 1 : 0));
}

#endif // TH3_PIVOTS_MQH



