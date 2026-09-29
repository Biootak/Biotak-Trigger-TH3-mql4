// TH3Pivots_B.mqh - TH3Pivots.mqh split 2026-09-29: exact lines 1423-2044, byte-identical, zero renames.
#ifndef TH3_PIVOTS_B_MQH
#define TH3_PIVOTS_B_MQH

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

#endif // TH3_PIVOTS_B_MQH
