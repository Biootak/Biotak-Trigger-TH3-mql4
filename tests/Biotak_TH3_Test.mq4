//+------------------------------------------------------------------+
//| Biotak_TH3_Test.mq4                                             |
//| Live assertions for the new TH3 modular architecture:           |
//|   TH3Math (AB=CD point D) + TH3PatternStore (registry)          |
//| Uses the SAME production include chain as the indicator.        |
//| Drag onto a chart (any symbol/TF) and check the Experts tab.    |
//+------------------------------------------------------------------+
#property strict

// TH3Tool.mqh normally defines these before including the TH3 modules.
// Faithful copies so the test is self-contained.
#ifndef ABCD_MIN_DISTANCE_POINTS
#define ABCD_MIN_DISTANCE_POINTS 10
#endif
#define EPSILON_PRICE 1e-10
#define TH3_SNAP_THRESHOLD_PIPS 5.0

bool IsZero(const double value, const double epsilon = 1e-10)
{
    return MathAbs(value) < epsilon;
}

const double MODIFIED_FRACTAL_PERCENTAGES[] = {
    0.0208, 0.0417, 0.0833, 0.1666, 0.3333, 0.6666, 1.3332, 2.6664, 5.3328
};

// Standard forex pip logic (5-digit = Point*10, 4-digit = Point)
double GetCachedPipSize()
{
    return (Digits % 2 == 1) ? Point * 10.0 : Point;
}

#include "..\Biotak\TH3\TH3Types.mqh"
#include "..\Biotak\TH3\TH3Math.mqh"
#include "..\Biotak\TH3\TH3PatternStore.mqh"

int g_pass = 0;
int g_fail = 0;

void Check(const string name, const bool ok)
{
    if(ok) {
        g_pass++;
        Print("[TH3TEST] PASS | ", name);
    } else {
        g_fail++;
        Print("[TH3TEST] FAIL | ", name);
    }
}

void CheckDouble(const string name, const double actual, const double expected)
{
    Check(name + " (got " + DoubleToString(actual, 8) + " want " + DoubleToString(expected, 8) + ")",
          MathAbs(actual - expected) < 0.00000001);
}

//+------------------------------------------------------------------+
int OnStart()
{
    Print("[TH3TEST] ==================== TH3 architecture test start");

    // Need at least ~10 bars so iBarShift/iTime work in the time calc
    int bars = Bars(NULL, 0);
    if(bars < 20) {
        Print("[TH3TEST] SKIP: not enough bars on chart (", bars, ")");
        return 0;
    }

    // ---- 1. Point D price rule (bullish: pD = pC + |pB-pA|) ----
    datetime tA = Time[8];
    datetime tB = Time[5];
    datetime tC = Time[2];
    // sanity: ascending times
    Check("time order tA<tB<tC", tA < tB && tB < tC);

    double pA = 1.08000;
    double pB = 1.09000;   // AB = 100 pips bullish
    double pC = 1.08500;
    datetime tD;
    double pD;
    bool ok = CalculateABCDPointD(tA, pA, tB, pB, tC, pC, tD, pD);
    Check("bullish D calculated", ok);
    CheckDouble("bullish D price = pC + AB", pD, 1.09500);
    Check("bullish D time after C", tD >= tC);

    // ---- 2. Bearish: pD = pC - |pB-pA| ----
    pA = 1.09000;
    pB = 1.08000;
    pC = 1.08500;
    ok = CalculateABCDPointD(tA, pA, tB, pB, tC, pC, tD, pD);
    Check("bearish D calculated", ok);
    CheckDouble("bearish D price = pC - AB", pD, 1.07500);

    // ---- 3. Invalid time order rejected ----
    ok = CalculateABCDPointD(tB, pA, tA, pB, tC, pC, tD, pD);
    Check("rejects tA >= tB", !ok);

    // ---- 4. Tiny AB distance rejected (below min) ----
    // 1e-7 is below Point*10 on every symbol/broker, so this must be rejected
    ok = CalculateABCDPointD(tA, 1.08000, tB, 1.08000 + 0.0000001, tC, 1.08500, tD, pD);
    Check("rejects tiny AB distance", !ok);

    // ---- 5. Zero/invalid prices rejected ----
    ok = CalculateABCDPointD(tA, 0.0, tB, 1.09000, tC, 1.08500, tD, pD);
    Check("rejects zero price", !ok);

    // ---- 6. Pattern store: build -> add -> get -> remove ----
    TH3Pattern pattern;
    bool built = TH3PatternBuild("ABCD_Pattern_Test1", tA, pA, tA, 1.08000, tB, 1.09000, tC, 1.08500, pattern);
    Check("pattern model built", built);
    CheckDouble("model D price matches renderer rule", pattern.D.price, 1.09500);
    Check("model bullish flag", pattern.bullish);

    TH3PatternStoreClear();
    Check("store starts empty", TH3PatternStoreCount() == 0);

    Check("store add", TH3PatternStoreAdd(pattern));
    Check("store count == 1", TH3PatternStoreCount() == 1);

    TH3Pattern got;
    Check("store get by name", TH3PatternStoreGet("ABCD_Pattern_Test1", got));
    CheckDouble("store round-trip D price", got.D.price, pattern.D.price);

    // replace semantics
    pattern.frequency = 61.8;
    Check("store add (replace) same name", TH3PatternStoreAdd(pattern));
    Check("store count still 1", TH3PatternStoreCount() == 1);

    Check("store remove", TH3PatternStoreRemove("ABCD_Pattern_Test1"));
    Check("store empty after remove", TH3PatternStoreCount() == 0);
    Check("store get missing -> false", !TH3PatternStoreGet("ABCD_Pattern_Test1", got));

    // ---- 7. Store capacity guard ----
    TH3PatternStoreClear();
    int added = 0;
    for(int i = 0; i < TH3_MAX_PATTERNS + 10; i++) {
        TH3Pattern p2;
        if(TH3PatternBuild("ABCD_Pattern_Cap" + IntegerToString(i), tA, pA, tA, 1.08000, tB, 1.09000, tC, 1.08500, p2)) {
            if(TH3PatternStoreAdd(p2)) added++;
        }
    }
    Check("store caps at TH3_MAX_PATTERNS", added == TH3_MAX_PATTERNS && TH3PatternStoreCount() == TH3_MAX_PATTERNS);
    TH3PatternStoreClear();

    // P-TH3-INFO-05 — the closed step reads the CLOSING leg, not the retracement.
    // `TH3ClosedStepFromLegs` is documented in OUR X/A/B/C naming (TH3Pivots.mqh:1320:
    // our A = their B, our B = their C, our C = their D), so a caller holding the
    // store's A/B/C/D must hand it B/C/D. Passing A/B/C measures one leg short and
    // the label disagrees with the ladder that wears the number. This pins the
    // mapping itself, not the arithmetic (section 8 already pins that).
    {
        // Self-contained: the store's own points, built from explicit prices so the
        // two candidate readings are BOTH inside the K table and far apart.
        // AB = 100, BC = 62, CD = 176 pips -> right R = 2.84 (K=1.666, 105.6 pips),
        // wrong R = 0.62 (below 0.75, no answer at all). A caller that reads the
        // wrong leg goes SILENT here, which is exactly how this shipped unnoticed.
        datetime ltA = tA, ltB = tB, ltC = tC, ltD = tD;
        double lpA = 1.08000, lpB = 1.09000, lpC = 1.08380, lpD = 1.06620;
        TH3Pattern legModel;
        if(TH3PatternBuild("ABCD_Pattern_LegMap", ltA, lpA, ltB, lpB, ltC, lpC, ltD, lpD, legModel)) {
            double rightStep = 0, rightK = 0, rightR = 0;
            bool rightOK = TH3ClosedStepFromLegs(legModel.B.price, legModel.C.price, legModel.D.price,
                                                rightStep, rightK, rightR);
            bool wrongOK  = TH3ClosedStepFromLegs(legModel.A.price, legModel.B.price, legModel.C.price,
                                                 rightStep, rightK, rightR);   // outputs reused: only the BOOL matters
            // 1e-7 is below Point on every symbol, so it compares prices, not noise.
            const double legEps = 1e-7;
            Check("leg map: closing leg B/C/D answers", rightOK);
            if(rightOK) {
                Check("leg map: B/C/D step is |D-C|/K", MathAbs(rightStep - MathAbs(legModel.D.price - legModel.C.price) / rightK)
                                                       < legEps);
                Check("leg map: A/B/C is NOT the closing leg", !wrongOK);
            }
            TH3PatternStoreClear();
        }
    }

    // P-TH3-PB (2026-09-21) + P-TH3-PB-MAN — THE HAND-TYPED BASE IS PATH 1.
    // History: the user's report («پیوت مبنا رو ... مشخص کردم ... step ها مثل
    // قبل بودن که اپدیت نشدن») was a DRAWN base that reached the store and
    // stopped there. `TH3LockedStep` is the ONE owner of that decision, so the
    // pin is arithmetic, no chart needed — and since P-TH3-PB-MAN nothing is
    // drawn at all: pbStep arrives from `TH3ManualBaseStep` (the TH3 TOOL
    // card's BASE PIPS), the detector's node no longer answers (nodeStep = 0),
    // and 0 = OFF (the pattern TF's own ATR). Prices are EURUSD-like 5-digit:
    // a pip is 0.0001, so all numbers below are whole pips.
    {
        const double pip = 0.0001;
        double ls = 0; string how = ""; bool lk = false;

        // 0. THE SOURCE: pips x pip size = the RAW retrace, in price.
        //    P-TH3-PB-RET8: no division here — the 8-state reading lives in
        //    TH3RetraceBestStep below. Absence answers 0.
        CheckDouble("pb-man: 90 pips -> 90 pips raw retrace", TH3ManualBaseStep(90.0, pip), 90.0 * pip);
        CheckDouble("pb-man: 50 pips -> raw price", TH3ManualBaseStep(50.0, pip), 50.0 * pip);
        Check("pb-man: 0 pips is OFF", TH3ManualBaseStep(0.0, pip) == 0.0);
        Check("pb-man: negative pips is OFF", TH3ManualBaseStep(-5.0, pip) == 0.0);
        Check("pb-man: dead pip size is OFF", TH3ManualBaseStep(50.0, 0.0) == 0.0);
        // P-TH3-PB-UI: the two-click mark and the native resize share ONE
        // converter — edges and pip size in, BASE PIPS out.
        CheckDouble("pb-ui: 100 pips from prices", TH3BasePipsFromPrices(1.09000, 1.08000, pip), 100.0);
        CheckDouble("pb-ui: order-free edges", TH3BasePipsFromPrices(1.08000, 1.09000, pip), 100.0);
        Check("pb-ui: same price is OFF", TH3BasePipsFromPrices(1.08000, 1.08000, pip) == 0.0);
        Check("pb-ui: dead pip size is OFF", TH3BasePipsFromPrices(1.09000, 1.08000, 0.0) == 0.0);
    }

    // P-TH3-PB-RET8 (2026-09-22) — ONE RETRACE, EIGHT STATES.
    // q = R/S in {1/3, 2/3, 1, 4/3, 5/3, 2, 3, 5}; S = R/q. The winner is
    // the candidate nearest ref (ABCD synthesis, 60%) + rung (owner TF, 40%).
    // Fixture: ref = th = 90 pips, so each R's matching state must land on 90.
    {
        const double pip = 0.0001;
        double bS = 0, bQ = 0; int bI = -1;
        CheckDouble("ret8: q0 is 1/3", TH3RetraceQ(0), 1.0 / 3.0);
        CheckDouble("ret8: q3 is 4/3", TH3RetraceQ(3), 4.0 / 3.0);
        CheckDouble("ret8: q4 is 5/3", TH3RetraceQ(4), 5.0 / 3.0);
        Check("ret8: bad idx answers 0", TH3RetraceQ(99) == 0.0);
        Check("ret8: bad idx name is ?", TH3RetraceQName(99) == "?");
        CheckDouble("ret8: R=90 q=1/3 -> S=270", TH3RetraceCandidate(90.0 * pip, 0), 270.0 * pip);
        CheckDouble("ret8: R=90 q=1 -> S=90", TH3RetraceCandidate(90.0 * pip, 2), 90.0 * pip);
        Check("ret8: R<=0 answers 0", TH3RetraceCandidate(0.0, 2) == 0.0);
        Check("ret8: bad idx answers 0", TH3RetraceCandidate(90.0 * pip, 99) == 0.0);
        Check("ret8: R=30 is 1/3 of 90",
              TH3RetraceBestStep(30.0 * pip, 90.0 * pip, 90.0 * pip, bS, bQ, bI)
              && MathAbs(bS - 90.0 * pip) < 1e-9 && bI == 0);
        Check("ret8: R=60 is 2/3 of 90",
              TH3RetraceBestStep(60.0 * pip, 90.0 * pip, 90.0 * pip, bS, bQ, bI)
              && MathAbs(bS - 90.0 * pip) < 1e-9 && bI == 1);
        Check("ret8: R=90 is 1 step",
              TH3RetraceBestStep(90.0 * pip, 90.0 * pip, 90.0 * pip, bS, bQ, bI)
              && MathAbs(bS - 90.0 * pip) < 1e-9 && bI == 2);
        Check("ret8: R=120 is step+1/3",
              TH3RetraceBestStep(120.0 * pip, 90.0 * pip, 90.0 * pip, bS, bQ, bI)
              && MathAbs(bS - 90.0 * pip) < 1e-9 && bI == 3);
        Check("ret8: R=150 is step+2/3",
              TH3RetraceBestStep(150.0 * pip, 90.0 * pip, 90.0 * pip, bS, bQ, bI)
              && MathAbs(bS - 90.0 * pip) < 1e-9 && bI == 4);
        Check("ret8: R=180 is 2 steps",
              TH3RetraceBestStep(180.0 * pip, 90.0 * pip, 90.0 * pip, bS, bQ, bI)
              && MathAbs(bS - 90.0 * pip) < 1e-9 && bI == 5);
        Check("ret8: R=270 is 3 steps",
              TH3RetraceBestStep(270.0 * pip, 90.0 * pip, 90.0 * pip, bS, bQ, bI)
              && MathAbs(bS - 90.0 * pip) < 1e-9 && bI == 6);
        Check("ret8: R=450 is 5 steps",
              TH3RetraceBestStep(450.0 * pip, 90.0 * pip, 90.0 * pip, bS, bQ, bI)
              && MathAbs(bS - 90.0 * pip) < 1e-9 && bI == 7);
        Check("ret8: TH-only R=100 th=100 -> q=1",
              TH3RetraceBestStep(100.0 * pip, 0.0, 100.0 * pip, bS, bQ, bI)
              && MathAbs(bS - 100.0 * pip) < 1e-9 && bI == 2);
        Check("ret8: no anchor -> R itself",
              TH3RetraceBestStep(100.0 * pip, 0.0, 0.0, bS, bQ, bI)
              && MathAbs(bS - 100.0 * pip) < 1e-9 && bI == 2);
        Check("ret8: R<=0 refuses", !TH3RetraceBestStep(0.0, 90.0 * pip, 90.0 * pip, bS, bQ, bI));
    }

    // P-TH3-STEP-16 (2026-10-05) — UNIFIED EQUATION PINS.
    // sqrt(mother * pattern), numbers only (pip = 0.0001).
    {
        const double pip = 0.0001;
        // 1. The K ladder, one owner: 0.85/1.20/1.80 tiers, major = 1.0.
        CheckDouble("uni: K 0.80 -> 2.5", TH3UnifiedK(0.80), 2.5);
        CheckDouble("uni: K 0.85 -> 2.5", TH3UnifiedK(0.85), 2.5);
        CheckDouble("uni: K 1.00 -> 3.0", TH3UnifiedK(1.00), 3.0);
        CheckDouble("uni: K 1.20 -> 3.0", TH3UnifiedK(1.20), 3.0);
        CheckDouble("uni: K 1.50 -> 3.5", TH3UnifiedK(1.50), 3.5);
        CheckDouble("uni: K 1.80 -> 3.5", TH3UnifiedK(1.80), 3.5);
        CheckDouble("uni: K 2.50 -> 1.0", TH3UnifiedK(2.50), 1.0);
        // 2. Macro mother (36 >= 2.5x10): 36/3=12, pattern 100/3: sqrt(400)=20.
        CheckDouble("uni: macro mother sqrt(12*33.3)=20",
                    CalculateUnifiedMasterStep(100.0 * pip, 1.0, 36.0 * pip, 10.0 * pip), 20.0 * pip);
        // 3. Knot mother (20 < 2.5x10): sqrt(20*33.3).
        Check("uni: knot mother geometric",
              MathAbs(CalculateUnifiedMasterStep(100.0 * pip, 1.0, 20.0 * pip, 10.0 * pip)
                      - MathSqrt(20.0 * 100.0 / 3.0) * pip) < 1e-9);
        // 4. EURUSD,H1 measured (CD 51, mother 50.4, K 1.0): sqrt(50.4*51).
        Check("uni: CD rides the mother rung",
              MathAbs(CalculateUnifiedMasterStep(51.0 * pip, 3.37, 50.4 * pip, 37.4 * pip)
                      - MathSqrt(50.4 * 51.0) * pip) < 1e-9);
        // 5. No mother: the rung stands in: sqrt(10*33.3).
        Check("uni: absent mother falls back to rung",
              MathAbs(CalculateUnifiedMasterStep(100.0 * pip, 1.0, 0.0, 10.0 * pip)
                      - MathSqrt(10.0 * 100.0 / 3.0) * pip) < 1e-9);
        // 6. Major extension (ratio 2.0 -> K 1.0): the leg itself: sqrt(10*56).
        Check("uni: major extension leg is the unit",
              MathAbs(CalculateUnifiedMasterStep(56.0 * pip, 2.0, 30.0 * pip, 10.0 * pip)
                      - MathSqrt(10.0 * 56.0) * pip) < 1e-9);
        // 7. Nothing at all answers 0 (the caller keeps its own fallback).
        Check("uni: empty inputs answer 0",
              CalculateUnifiedMasterStep(0.0, 0.0, 0.0, 0.0) == 0.0);
        // 8. Guard: no rung to stand in -> the pattern stands alone.
        CheckDouble("uni: dead rung falls back to pattern",
                    CalculateUnifiedMasterStep(100.0 * pip, 1.0, 0.0, 0.0), 100.0 * pip / 3.0);
    }

    // P-TH3-STEP-13 — MACRO SPAN: WICK, NOT BODY.
    // Step = |D - piv.price| / 3. XAUUSD M15: D 4446, wick 4344 -> 1020/3 = 340.
    // Body 4363 would lie by 19 pips (83/3 = 27.7 of error on the span).
    {
        TH3PivotSix mp;
        ZeroMemory(mp);
        mp.valid = true; mp.price = 4344.0; mp.keyPrice = 4363.0;
        CheckDouble("macrospan: wick 4446-4344 -> 340/3",
                    TH3MacroSpanStep(4446.0, mp), 102.0 / 3.0);
        Check("macrospan: body is NOT the ruler",
              MathAbs(TH3MacroSpanStep(4446.0, mp) - MathAbs(4446.0 - 4344.0) / 3.0) < 1e-9);
        TH3PivotSix badMp;
        ZeroMemory(badMp);
        Check("macrospan: invalid pivot answers 0", TH3MacroSpanStep(4446.0, badMp) == 0.0);
        Check("macrospan: dead ref answers 0", TH3MacroSpanStep(0.0, mp) == 0.0);
        // Extended leg K: 560/1.666 = 336.1 ≈ 340 macro span — the unity.
        CheckDouble("closed K macro 560/1.666", 560.0 / TH3ClosedK(2.5), 560.0 / 1.666);
    }

    {
        double ls = 0; string how = ""; bool lk = false;
        const double pip = 0.0001;

        // 1. The shipped bug: closed step alone, base = 0 -> the ladder must NOT
        //    move. This is the pre-PB behaviour, preserved on purpose (a base is
        //    the user's statement; without one the old paths still answer).
        Check("pb: closed-only keeps closed step",
              TH3LockedStep(ls, how, lk, 40.0 * pip, 0.0, 30.0 * pip, 60, 60, pip)
              && MathAbs(ls - 40.0 * pip) < 1e-7 && !lk);

        // 2. THE FIX: a base INSIDE ±25% -> LOCKED, the average of the two.
        //    40 and 46 pips deviate 15%, so 43.0 pips, locked, verdict says base.
        Check("pb: base inside 25% LOCKs to the average",
              TH3LockedStep(ls, how, lk, 40.0 * pip, 46.0 * pip, 0.0, 60, 60, pip)
              && MathAbs(ls - 43.0 * pip) < 1e-7 && lk
              && StringFind(how, "LOCKED base") == 0);

        // 3. THE USER'S OWN CASE: a base OUTSIDE the band still wins. 40 vs 100
        //    pips is +150% off, the old code would have kept 40 and the ladder
        //    would not have moved — which is exactly the report above. Now the
        //    drawn base stands and the caption carries the disagreement.
        Check("pb: base outside 25% still wins (the reported bug)",
              TH3LockedStep(ls, how, lk, 40.0 * pip, 100.0 * pip, 0.0, 60, 60, pip)
              && MathAbs(ls - 100.0 * pip) < 1e-7 && !lk
              && StringFind(how, "UNLOCKED base") == 0);

        // 4. The detector's node OUTSIDE the band LOSES — a scanned candidate is
        //    not an instruction, so the closed step keeps it. 40 vs 70 = +75%.
        Check("pb: auto node outside 25% loses to the closed step",
              TH3LockedStep(ls, how, lk, 40.0 * pip, 0.0, 70.0 * pip, 60, 60, pip)
              && MathAbs(ls - 40.0 * pip) < 1e-7 && !lk
              && StringFind(how, "UNLOCKED auto") == 0);

        // 5. The base BEATS the detector when both are present: 40 closed, 46
        //    base, 200 auto. Only the base's lock may show.
        Check("pb: base wins over the detector when both answer",
              TH3LockedStep(ls, how, lk, 40.0 * pip, 46.0 * pip, 200.0 * pip, 60, 60, pip)
              && MathAbs(ls - 43.0 * pip) < 1e-7 && lk
              && StringFind(how, "LOCKED base") == 0
              && StringFind(how, "200") < 0);

        // 6. No closed step, base drawn -> Path 1 alone, and the verdict must NOT
        //    call one path a lock.
        Check("pb: base with no closed step stands unlocked",
              TH3LockedStep(ls, how, lk, 0.0, 55.0 * pip, 0.0, 60, 60, pip)
              && MathAbs(ls - 55.0 * pip) < 1e-7 && !lk
              && StringFind(how, "base drawn") == 0);

        // 7. Nothing at all -> false, the caller keeps its own seed (the rung or
        //    the percentage fallback). Absence, never a guess.
        Check("pb: no path answers -> false", !TH3LockedStep(ls, how, lk, 0.0, 0.0, 0.0, 60, 60, pip));

        // 8. A degenerate base (top == bottom, or a zero bound) is NOT a base —
        //    the caller may pass an uninitialised pattern, and a zero step would
        //    collapse the ladder onto C. The function must ignore it and fall
        //    through to the closed step.
        Check("pb: degenerate base is ignored",
              TH3LockedStep(ls, how, lk, 40.0 * pip, 0.0, 0.0, 60, 60, pip)
              && MathAbs(ls - 40.0 * pip) < 1e-7 && !lk);

        // 9. An AUTO node with no closed step does not answer. The walk-up law and
        //    the ±25% gate are both defined against the closed step, so a detector
        //    reading alone was never a step — the pre-PB code gated the whole lock
        //    block on closedOK, and that gate is preserved here. The renderer keeps
        //    its rung/percentage seed, which is the honest answer.
        Check("pb: auto node with no closed step does not answer",
              !TH3LockedStep(ls, how, lk, 0.0, 0.0, 90.0 * pip, 60, 60, pip));

        // 10. A drawn base is EXEMPT from the walk-up shift: with a base present
        //     and ownerTF != chartTF the shift must not fire, because the base is
        //     the geometry that law was estimating. 40 closed / 46 base / H1 owner
        //     on an M15 chart would shift to 2xLS without this rule; the answer
        //     stays the LOCKED average.
        if(TH3LockedStep(ls, how, lk, 40.0 * pip, 46.0 * pip, 0.0, 60, 15, pip)) {
            Check("pb: drawn base is exempt from the walk-up shift",
                  MathAbs(ls - 43.0 * pip) < 1e-7 && lk);
        }

        // 11. ...but the AUTO node still shifts when the owner walked up, so a
        //     chart whose pattern belongs to a bigger TF still gets the formula's
        //     own law. Same numbers with no base must NOT average to 43. The
        //     shift needs a rung on the chart's own TF, so this check is SKIPPED
        //     (not passed) when the symbol has no history for it — a skip is a
        //     pin on the rule, not a gap in it.
        if(TH3LockedStep(ls, how, lk, 40.0 * pip, 0.0, 46.0 * pip, 60, 15, pip)) {
            Check("pb: auto node still walks up without a base",
                  MathAbs(ls - 43.0 * pip) > 1e-7
                  && StringFind(how, "SHIFT") >= 0);
        }
    }

    // P-TH3-PB-OFF — the store fields survive for layout compat (TH3Types.mqh)
    // but the UI never writes them: Path 1 is hand-typed. This pins the compat
    // leg only — top/bottom survive add -> get and keep top > bottom.
    {
        TH3Pattern pbModel;
        if(TH3PatternBuild("ABCD_Pattern_BaseRT", tA, 1.08000, tB, 1.09000, tC, 1.08500, tD, 1.09500, pbModel)) {
            pbModel.pivotBaseTop    = 1.09123;
            pbModel.pivotBaseBottom = 1.08877;
            Check("pb round-trip: store add", TH3PatternStoreAdd(pbModel));
            TH3Pattern pbGot;
            Check("pb round-trip: store get", TH3PatternStoreGet("ABCD_Pattern_BaseRT", pbGot));
            CheckDouble("pb round-trip: top survives",    pbGot.pivotBaseTop,    1.09123);
            CheckDouble("pb round-trip: bottom survives", pbGot.pivotBaseBottom, 1.08877);
            Check("pb round-trip: top above bottom", pbGot.pivotBaseTop > pbGot.pivotBaseBottom);
            TH3PatternStoreClear();
        }
    }

    // ---- 8. Skeleton axes ----
    // Pure axis classifiers first: these need no bars, so they can be pinned
    // exactly. The candle boundaries are course numbers (0.80 / 1.20 / 2.50 ATR)
    // and the momentum ones are MEASURED quantiles (0.66 / 0.85 / 1.43 R), but
    // every boundary is tested ON the boundary either way, because an off-by-one
    // band silently relabels every pivot it touches.
    Check("candle 0.79 ATR -> spinning", TH3ClassifyCandle(0.79, 1.0) == TH3_PC_SPINNING);
    Check("candle 0.80 ATR -> standard", TH3ClassifyCandle(0.80, 1.0) == TH3_PC_STANDARD);
    Check("candle 1.20 ATR -> longbar",  TH3ClassifyCandle(1.20, 1.0) == TH3_PC_LONGBAR);
    Check("candle 2.50 ATR -> spike",    TH3ClassifyCandle(2.50, 1.0) == TH3_PC_SPIKE);
    Check("candle with no ATR -> unknown", TH3ClassifyCandle(1.0, 0.0) == TH3_PC_UNKNOWN);

    // The momentum axis decides on SPEED now. Both the boundary map and the reading
    // itself are pinned here: a band set that is right about the classifier and
    // wrong about the units is invisible until it is live.
    // The bounds moved when the quantile mix was abandoned: on 22,538 real legs
    // the R ladder's p25 is 1.01, so R = 1 is kept EXACTLY and the class mix goes
    // from 7.3/10.0/44.0/38.7 (82.7% of legs in the top two bands) to
    // 24.1/27.7/21.4/26.7. Each bound is tested ON the boundary, because an
    // off-by-one band silently relabels every pivot it touches.
    Check("speed 0.99 -> weak",       TH3MomentumFromSpeed(0.99) == TH3_MOM_WEAK);
    Check("speed 1.00 -> normal",     TH3MomentumFromSpeed(1.00) == TH3_MOM_NORMAL);
    Check("speed 1.29 -> normal",     TH3MomentumFromSpeed(1.29) == TH3_MOM_NORMAL);
    Check("speed 1.30 -> strong",     TH3MomentumFromSpeed(1.30) == TH3_MOM_STRONG);
    Check("speed 1.59 -> strong",     TH3MomentumFromSpeed(1.59) == TH3_MOM_STRONG);
    Check("speed 1.60 -> explosive",  TH3MomentumFromSpeed(1.60) == TH3_MOM_EXPLOSIVE);
    Check("speed 0 -> weak",          TH3MomentumFromSpeed(0.0) == TH3_MOM_WEAK);

    // The reading: R = |dp| / (ATR * sqrt(bars)). Four times the duration at the
    // SAME displacement must halve R, not quarter it. The old angle divided by
    // time LINEARLY and so quartered it - that is the defect this axis was
    // replaced to remove. If this ever reports 0.25 again, the sqrt is gone.
    datetime tS = (datetime)1700000000;
    int barSec = Period() * 60;
    if(barSec <= 0) barSec = 3600;
    double rFast = TH3MomentumSpeed(tS, 1000.0, tS + 4 * barSec, 1020.0, 10.0);
    double rSlow = TH3MomentumSpeed(tS, 1000.0, tS + 16 * barSec, 1020.0, 10.0);
    CheckDouble("speed: 4x duration halves R", rSlow / rFast, 0.5);
    CheckDouble("speed: one bar of one ATR is R=1",
                TH3MomentumSpeed(tS, 1000.0, tS + barSec, 1010.0, 10.0), 1.0);
    Check("speed: no ATR -> 0, not a guess",
          TH3MomentumSpeed(tS, 1000.0, tS + barSec, 1010.0, 0.0) == 0.0);
    Check("speed: a longer leg reads faster",
          TH3MomentumSpeed(tS, 1000.0, tS + barSec, 1030.0, 10.0)
          > TH3MomentumSpeed(tS, 1000.0, tS + barSec, 1010.0, 10.0));
    Check("speed: zero-length leg -> 0",
          TH3MomentumSpeed(tS, 1000.0, tS + barSec, 1000.0, 10.0) == 0.0);

    // The retired angle path still answers, so the old bands stay pinned while
    // MOMENTUM-ANGLE-OFF lasts and a restoration has a target to hit.
    Check("angle 39 -> weak",        TH3MomentumFromAngle(39.0) == TH3_MOM_WEAK);
    Check("angle 40 -> normal",      TH3MomentumFromAngle(40.0) == TH3_MOM_NORMAL);
    Check("angle 55 -> strong",      TH3MomentumFromAngle(55.0) == TH3_MOM_STRONG);
    Check("angle 80 -> explosive",   TH3MomentumFromAngle(80.0) == TH3_MOM_EXPLOSIVE);

    // The step formula's own edge: 3S - 2P goes non-positive once the pattern's
    // ATR passes 1.5x the structure's. That must read as "no answer" (false with
    // stepOut untouched), never as a negative or zero step.
    TH3Skeleton sk;
    sk.valid = true; sk.direction = 1; sk.coverDepth = TH3_CD_NONE;
    sk.coverDelay = 1;
    double stepOut = 12345.0;
    sk.momentum = TH3_MOM_WEAK;
    Check("step: 3S-2P non-positive -> false", !TH3StepFromSkeleton(sk, 100.0, 160.0, stepOut));
    Check("step: refuses but does not overwrite", stepOut == 12345.0);

    sk.momentum = TH3_MOM_STRONG;   // long  = 3*100 - 2*20 = 260
    Check("step: strong momentum yields a step", TH3StepFromSkeleton(sk, 100.0, 20.0, stepOut));
    CheckDouble("step: 3S-2P value", stepOut, 260.0);

    sk.coverDepth = TH3_CD_DEEP;    // deep cover shrinks it by 0.70
    TH3StepFromSkeleton(sk, 100.0, 20.0, stepOut);
    CheckDouble("step: deep cover multiplier", stepOut, 182.0);

    sk.coverDepth = TH3_CD_NONE; sk.coverDelay = 4;   // late cover shrinks by 0.80
    TH3StepFromSkeleton(sk, 100.0, 20.0, stepOut);
    CheckDouble("step: late cover multiplier", stepOut, 208.0);

    // Momentum must actually select a different length, or the axis is inert.
    sk.coverDelay = 1;
    sk.momentum = TH3_MOM_WEAK;
    double weakStep = 0;
    TH3StepFromSkeleton(sk, 100.0, 20.0, weakStep);
    sk.momentum = TH3_MOM_STRONG;
    double strongStep = 0;
    TH3StepFromSkeleton(sk, 100.0, 20.0, strongStep);
    Check("step: momentum band changes the step", strongStep > weakStep);

    // MONOTONE, which the shipped assignment was NOT. `shortStep` is the blend
    // 0.5*(long+med), so it lies BETWEEN long and med - on every intraday chart
    // P < S, so long > med and WEAK was handed a step bigger than NORMAL's. On
    // 22,538 real legs that read WEAK 2.264 S against NORMAL 1.870 S: +21.1% of
    // step for a WEAKER impulse. Tested at both ends of the P/S range, because
    // which of the three candidates is largest FLIPS when P passes S - a single
    // check at P < S would pass on an implementation that is wrong for P > S.
    double mono[4];
    ArrayInitialize(mono, 0);            // the call can refuse; the array must
    for(int mi = 0; mi < 4; mi++) {      // still be defined before the assert
        sk.momentum = (TH3_MOMENTUM)mi;
        sk.coverDepth = TH3_CD_NONE; sk.coverDelay = 1;
        TH3StepFromSkeleton(sk, 100.0, 20.0, mono[mi]);
    }
    Check("step: weak <= normal <= strong (P < S)",
          mono[0] <= mono[1] && mono[1] <= mono[2]);
    Check("step: strong == explosive (same branch)", mono[2] == mono[3]);
    double mono2[4];
    ArrayInitialize(mono2, 0);
    for(int mj = 0; mj < 4; mj++) {
        sk.momentum = (TH3_MOMENTUM)mj;
        TH3StepFromSkeleton(sk, 100.0, 120.0, mono2[mj]);
    }
    Check("step: weak <= normal <= strong (P > S)",
          mono2[0] <= mono2[1] && mono2[1] <= mono2[2]);
    // And a WEAK impulse whose smallest candidate is non-positive has NO step,
    // which is the harness's own long-standing expectation above - it was only
    // reachable once the assignment became ordered.
    double noneStep = 0;
    sk.momentum = TH3_MOM_WEAK;
    Check("step: weak at 3S-2P<=0 also refuses",
          !TH3StepFromSkeleton(sk, 100.0, 160.0, noneStep));

    // P-TH3-STEP-08: closed-loop K table + step + ownership gate.
    // Boundaries are pinned ON the boundary: below 0.75 is no answer.
    Check("closed K 0.74 -> none", TH3ClosedK(0.74) == 0.0);
    Check("closed K 0.75 -> 2.5", TH3ClosedK(0.75) == 2.5);
    Check("closed K 0.85 -> 2.5", TH3ClosedK(0.85) == 2.5);
    Check("closed K 0.86 -> 3.0", TH3ClosedK(0.86) == 3.0);
    Check("closed K 1.20 -> 3.0", TH3ClosedK(1.20) == 3.0);
    Check("closed K 1.21 -> 3.5", TH3ClosedK(1.21) == 3.5);
    Check("closed K 1.80 -> 3.5", TH3ClosedK(1.80) == 3.5);
    // P-TH3-STEP-13: extended legs divide by 1.666 (560/1.666 = 336.1),
    // never 4.5 (560/4.5 = 124.4, ladder collapse).
    Check("closed K 1.81 -> 1.666", TH3ClosedK(1.81) == 1.666);
    double clStep = 0, clK = 0, clR = 0;
    Check("closed step symmetric", TH3ClosedStepFromLegs(1.08000, 1.09000, 1.08220, clStep, clK, clR));
    CheckDouble("closed step 78/100 -> BC/2.5", clStep, 0.00312);
    Check("closed step deep", TH3ClosedStepFromLegs(1.08000, 1.09000, 1.08000, clStep, clK, clR));
    CheckDouble("closed step ratio 1.0 K=3.0", clK, 3.0);
    Check("closed step shallow -> false", !TH3ClosedStepFromLegs(1.08000, 1.09000, 1.08500, clStep, clK, clR));
    Check("closed owner N=5 current", TH3ClosedOwnerTF(5) == Period());
    Check("closed owner N=26 walks up", TH3ClosedOwnerTF(26) == TH3FractalStepTF(Period(), 1));

    // An unmeasured skeleton has no coordinate, and must not invent one.
    TH3Skeleton bad;
    bad.valid = false;
    Check("key: invalid skeleton -> -1", TH3SkeletonKey(bad) == -1);

    // The packed key must be injective, or two different arrangements claim the
    // same cell and the coordinate is worthless. Exercise the FULL 4 x 4 cross of
    // the two axes a caller is most likely to confuse, then the full delay range.
    int kSeen[16];
    ArrayInitialize(kSeen, -1);
    int kHits = 0;
    bool keyClash = false;
    for(int km = 0; km < 4; km++) {
        for(int kp = 1; kp <= 4; kp++) {
            sk.valid = true; sk.momentum = (TH3_MOMENTUM)km; sk.pivotCandle = (TH3_PIVOT_CANDLE)kp;
            sk.coverDepth = TH3_CD_DEEP; sk.coverDelay = 6; sk.direction = 1;
            int key = TH3SkeletonKey(sk);
            for(int s = 0; s < kHits; s++) if(kSeen[s] == key) keyClash = true;
            if(kHits < 16) { kSeen[kHits] = key; kHits++; }
        }
    }
    Check("key: 16 momentum x pivot combinations all distinct", !keyClash && kHits == 16);

    int dSeen[6];
    ArrayInitialize(dSeen, -1);
    bool delayClash = false;
    for(int d = 0; d < 6; d++) {
        sk.valid = true; sk.momentum = TH3_MOM_STRONG; sk.pivotCandle = TH3_PC_STANDARD;
        sk.coverDepth = TH3_CD_FULL; sk.coverDelay = d + 1; sk.direction = 1;
        dSeen[d] = TH3SkeletonKey(sk);
        for(int s2 = 0; s2 < d; s2++) if(dSeen[s2] == dSeen[d]) delayClash = true;
    }
    Check("key: all 6 cover delays distinct", !delayClash);

    // Live measurement: the axes must be readable off real bars, not only off
    // synthetic options. On a chart with fewer bars than the test needs, the
    // skeleton is allowed to be invalid - but never half-filled.
    if(TH3SkeletonFromBars(tA, pA, tB, pB, tC, pC, sk)) {
        Check("live skeleton: marked valid", sk.valid);
        Check("live skeleton: direction matches A->B", sk.direction == (pB > pA ? 1 : -1));
        Check("live skeleton: pivot candle classified", sk.pivotCandle != TH3_PC_UNKNOWN);
        Check("live skeleton: engulf count within 0..4", sk.coverEngulf >= 0 && sk.coverEngulf <= 4);
        Check("live skeleton: no cover implies no delay",
              sk.coverDepth != TH3_CD_NONE || sk.coverDelay == 0);
        Check("live skeleton: cover implies a delay of 1+",
              sk.coverDepth == TH3_CD_NONE || sk.coverDelay >= 1);
        Check("live skeleton: key packed", sk.key >= 0);
        Check("live skeleton: a step is pips-positive or absent",
              sk.stepPips > 0 || sk.stepPips == 0);
        Check("live skeleton: describe is non-empty", StringLen(TH3SkeletonDescribe(sk)) > 0);
        Print("[TH3TEST] live skeleton: ", TH3SkeletonDescribe(sk));
    } else {
        Print("[TH3TEST] SKIP: live skeleton needs more history on this chart");
    }

    // ---- 9. Mother pivot (P-TH3-P6e): node, mitigation, matcher ----
    // Needs a DECLARED six-condition pivot; a chart with none SKIPs (never FAILs).
    TH3PivotSix scanPiv[];
    ArrayResize(scanPiv, TH3_P6_MAX_PIVOTS);
    int nScan = TH3SixPivotsScanTF(Period(), scanPiv, TH3_P6_MAX_PIVOTS);
    if(nScan <= 0) {
        Print("[TH3TEST] SKIP: mother pivot needs a declared six-condition pivot on this chart");
    } else {
        // every declared pivot carries a one-sided node off its extreme:
        // H -> keyPrice below, L -> keyPrice above, never zero-thick.
        bool nodeOK = true;
        int nFresh = 0, nMit = 0;
        for(int pi = 0; pi < nScan; pi++) {
            if(scanPiv[pi].keyPrice <= 0) nodeOK = false;
            if(scanPiv[pi].isHigh && !(scanPiv[pi].keyPrice < scanPiv[pi].price)) nodeOK = false;
            if(!scanPiv[pi].isHigh && !(scanPiv[pi].keyPrice > scanPiv[pi].price)) nodeOK = false;
            if(scanPiv[pi].mitigated) nMit++; else nFresh++;
        }
        Check("mother: every pivot has a one-sided keyPrice", nodeOK);
        Print("[TH3TEST] mother nodes: fresh=", nFresh, " mitigated=", nMit);

        // the newest DRAWABLE pivot (base pivots are reported, not drawn,
        // and the matcher correctly ignores them) must answer for itself:
        // queried one bar after its own bar, within half its own node.
        int ni = nScan - 1;
        while(ni > 0 && scanPiv[ni].base) ni--;
        TH3PivotSix newest = scanPiv[ni];
        double thick = MathAbs(newest.price - newest.keyPrice);
        datetime tRef = newest.time + Period() * 60;
        TH3PivotSix found;
        bool hit = TH3MotherPivotAt(tRef, newest.price, newest.isHigh, 0.5 * thick, found);
        Check("mother: newest drawable pivot matches itself", hit || newest.base);
        if(hit) {
            Check("mother: match within tol", MathAbs(found.price - newest.price) <= 0.5 * thick);
            Check("mother: kind preserved", found.isHigh == newest.isHigh);
            Check("mother: strictly before ref", found.time < tRef);
        }

        // absurd reference (half the price) must read as "no answer":
        // the widest ladder tier is 3 steps; half the price of gold is far
        // beyond it (P-TH3-MP2: the ladder widened the gate, not infinity).
        double pip = GetCachedPipSize();
        Check("mother: far price refuses",
              !TH3MotherPivotAt(tRef, newest.price * 0.5, newest.isHigh, 0.5 * pip, found));
        Check("mother: negative tol refuses",
              !TH3MotherPivotAt(tRef, newest.price, newest.isHigh, -1.0, found));

        // Pillar 1, deterministic on any chart: a future anchor changes
        // nothing (every pivot predates it), the epoch anchor kills all.
        TH3PivotSix f1, f2;
        bool b0 = TH3MotherPivotAt(tRef, newest.price, newest.isHigh, 0.5 * thick, f1);
        bool bF = TH3MotherPivotAt(tRef, newest.price, newest.isHigh, 0.5 * thick, f2,
                                   D'2050.01.01');
        Check("mother: future anchor == no anchor",
              b0 == bF && (!b0 || f1.price == f2.price));
        Check("mother: epoch anchor refuses",
              !TH3MotherPivotAt(tRef, newest.price, newest.isHigh, 0.5 * thick, f2, 1));

        // Pillar 3 wiring: an opposite-kind answer must carry its flip proof
        // (re-verified here with the same inputs the matcher used).
        TH3PivotSix fl;
        if(TH3MotherPivotAt(tRef, newest.price, !newest.isHigh, 5.0 * thick, fl,
                            0, 0.0, true)) {
            int tSt = TH3FractalStepTF(Period(), 1);
            Check("mother: flipped kind carries proof",
                  (fl.isHigh != newest.isHigh)
                  && TH3FlipProven(fl.tf, fl.price, fl.isHigh, tRef,
                                   TH3PatternStepRungTF(tSt)));
        } else {
            Print("[TH3TEST] SKIP: no flipped pivot near newest on this chart");
        }

        // P-TH3-MP2 — the LADDER's own determinism: a pivot within the
        // widest tier always competes, so a query AT the newest pivot must
        // still answer, and the epoch anchor must still kill every match
        // (Pillar 1 outlives the ladder). Base pivots now compete too —
        // the matcher answers for the newest BASE pivot at its own price.
        int niBase = nScan - 1;
        while(niBase > 0 && !scanPiv[niBase].base) niBase--;
        if(niBase >= 0 && scanPiv[niBase].base) {
            TH3PivotSix b = scanPiv[niBase];
            double bThick = MathAbs(b.price - b.keyPrice);
            TH3PivotSix fb;
            bool bHit = TH3MotherPivotAt(b.time + Period() * 60, b.price,
                                         b.isHigh, 0.5 * bThick, fb);
            Check("mother: base pivot competes", bHit);
        } else {
            Print("[TH3TEST] SKIP: no base pivot on this chart");
        }
        // Pillar 3 negative, deterministic: nothing closed before 1970.
        Check("mother: flip before history refuses",
              !TH3FlipProven(Period(), newest.price, newest.isHigh, 1,
                             TH3PatternStepRungTF(Period())));

        // ---- 12. Origin Tier-2: far base on the macro layer only ----
        // Refusals are deterministic on any chart; a hit is wired-checked
        // (macro layer, predates anchor, same kind) or SKIPped.
        TH3PivotSix og;
        Check("origin: non-positive span refuses",
              !TH3OriginPivotAt(tRef, newest.price, newest.isHigh, 0.0, newest.time, og));
        Check("origin: epoch anchor refuses",
              !TH3OriginPivotAt(tRef, newest.price, newest.isHigh, 100000.0, 1, og));
        if(TH3OriginPivotAt(tRef, newest.price, newest.isHigh, 1e9, newest.time, og)) {
            Check("origin: macro layer",
                  og.tf == TH3FractalStepTF(Period(), 2));
            Check("origin: predates anchor", og.time < newest.time);
            Check("origin: same kind", og.isHigh == newest.isHigh);
        } else {
            Print("[TH3TEST] SKIP: no macro origin pivot on this chart");
        }
    }

    // ---- 9b. Score order (Pillar 4): synthetic structs, deterministic ----
    // No bars needed — the weights themselves are pinned, on any chart.
    TH3PivotSix sA, sB;
    sA.valid = true; sA.base = false; sA.mitigated = false; sA.isHigh = true;
    sA.price = 100.0; sA.keyPrice = 99.0; sA.tf = Period(); sA.time = 1;
    sB = sA;
    int tfS = TH3FractalStepTF(Period(), 1), tfM = TH3FractalStepTF(Period(), 2);
    sB.tf = tfM; sB.mitigated = true;
    Check("score: macro-mit beats chart-fresh",
          CalculateDynamicPivotScore(sB, 100.0, tfS, tfM, 0.0)
          > CalculateDynamicPivotScore(sA, 100.0, tfS, tfM, 0.0));
    sB = sA; sB.mitigated = true;
    Check("score: fresh beats mitigated same TF",
          CalculateDynamicPivotScore(sA, 100.0, tfS, tfM, 0.0)
          > CalculateDynamicPivotScore(sB, 100.0, tfS, tfM, 0.0));
    CheckDouble("score: half-rung penalty",
          CalculateDynamicPivotScore(sA, 100.5, tfS, tfM, 1.0), 25.0);

    // ---- 9c. Motherness score (P-TH3-MP2): touches/thickness/launch ----
    // Pure arithmetic on synthetic structs — deterministic on any chart.
    TH3PivotSix m1, m2;
    m1.valid = true; m1.base = true; m1.mitigated = false; m1.isHigh = true;
    m1.price = 100.0; m1.keyPrice = 99.0; m1.tf = Period(); m1.time = 1;
    m2 = m1;
    // touches: 3 touches beat 0 at everything else equal
    double sc0 = TH3MotherScore(m1, 100.0, tfS, tfM, 0.0, 0, 1.0, false, false);
    double sc3 = TH3MotherScore(m1, 100.0, tfS, tfM, 0.0, 3, 1.0, false, false);
    Check("mscore: touches raise score", sc3 > sc0);
    CheckDouble("mscore: touch weight", sc3 - sc0, 75.0);   // 3 x 25
    // thickness: a 1.5-step node beats a 0.1-step node
    m2.keyPrice = 98.5;
    double scThick = TH3MotherScore(m2, 100.0, tfS, tfM, 0.0, 0, 1.0, false, false);
    Check("mscore: thick node beats thin", scThick > sc0);
    CheckDouble("mscore: thickness capped at 2 steps",
          TH3MotherScore(m2, 100.0, tfS, tfM, 0.0, 0, 0.5, false, false), scThick);
    // launch and age bonuses
    CheckDouble("mscore: launch bonus",
          TH3MotherScore(m1, 100.0, tfS, tfM, 0.0, 0, 1.0, true, false)
          - sc0, 40.0);
    CheckDouble("mscore: age bonus",
          TH3MotherScore(m1, 100.0, tfS, tfM, 0.0, 0, 1.0, false, true)
          - sc0, 15.0);
    // mitigated costs, never disqualifies
    m2 = m1; m2.mitigated = true;
    Check("mscore: mitigated costs but competes",
          TH3MotherScore(m1, 100.0, tfS, tfM, 0.0, 0, 1.0, false, false)
          > TH3MotherScore(m2, 100.0, tfS, tfM, 0.0, 0, 1.0, false, false));
    // distance: a far candidate loses at equal motherness
    Check("mscore: distance penalty",
          TH3MotherScore(m1, 100.0, tfS, tfM, 1.0, 0, 1.0, false, false)
          > TH3MotherScore(m1, 101.0, tfS, tfM, 1.0, 0, 1.0, false, false));
    // launch test: start in-node true, outside false
    Check("mlaunch: start inside node", TH3MotherLaunch(99.0, 100.0, 99.5, 105.0));
    Check("mlaunch: pass-through counts", TH3MotherLaunch(99.0, 100.0, 105.0, 95.0));
    Check("mlaunch: outside refuses", !TH3MotherLaunch(99.0, 100.0, 101.0, 105.0));
    Print("[TH3TEST] mscore sc0=", DoubleToString(sc0, 1),
          " sc3=", DoubleToString(sc3, 1), " scThick=", DoubleToString(scThick, 1));

    // ---- 10. Hit k-pick (P-TH3-STEP-09): k is read, not assumed ----
    // A rung-5 first tip divided by 3 minted steps 66% too big, so both
    // candidates race against the closed seed; a tie keeps 3 (course
    // default) and anything outside ±25% is no vote. All pure arithmetic.
    int pk = 0; double ps = 0;
    Check("kpick: no ref -> legacy k=3",
          TH3HitKPick(900.0, 0.0, pk, ps) && pk == 3);
    CheckDouble("kpick: legacy step", ps, 300.0);
    Check("kpick: XAUUSD 1753.6 vs closed 370.4 -> k=5",
          TH3HitKPick(1753.6, 370.4, pk, ps) && pk == 5);
    CheckDouble("kpick: 1753.6/5", ps, 350.72);
    Check("kpick: exact triple -> k=3",
          TH3HitKPick(300.0, 100.0, pk, ps) && pk == 3);
    Check("kpick: tie 375 vs 100 keeps 3",
          TH3HitKPick(375.0, 100.0, pk, ps) && pk == 3);
    Check("kpick: 376 vs 100 -> k=5 inside gate",
          TH3HitKPick(376.0, 100.0, pk, ps) && pk == 5);
    Check("kpick: runaway refuses", !TH3HitKPick(900.0, 100.0, pk, ps));
    Check("kpick: non-positive dist refuses", !TH3HitKPick(0.0, 100.0, pk, ps));

    // ---- 11. Owner walk (P-TH3-STEP-10): climb while out of gate ----
    // Same [3,7] gate per rung, counts converted by minute ratio — no new
    // numbers. XAUUSD H1/168 -> H4/42 -> D1/7 lands on Daily by itself.
    Check("owner: N=5 stays", TH3ClosedOwnerTFEx(60, 5) == 60);
    Check("owner: N=7 stays", TH3ClosedOwnerTFEx(60, 7) == 60);
    Check("owner: N=8 -> H4", TH3ClosedOwnerTFEx(60, 8) == 240);
    Check("owner: N=168 H1 -> D1", TH3ClosedOwnerTFEx(60, 168) == 1440);
    Check("owner: N=200 D1 -> MN", TH3ClosedOwnerTFEx(1440, 200) == 43200);
    Check("owner: caps at chain top", TH3ClosedOwnerTFEx(43200, 500) == 43200);

    // ---- 12. The rebase memo (P-TH3-PERF-08): a repeated rebase is a HIT ----
    // A perf claim with no number on it is a claim. The ladder is rebased on
    // every tick (TH3HitPivotForward), so the same inputs on the same bar MUST
    // come back from the memo: the counters prove it, and the struct must be
    // identical to the walk's own answer. A changed input must MISS — a memo
    // that answers a key it was never given is worse than no memo.
    // NOTE: this asserts nothing about WHAT the walk answers (that is §1-§11 on
    // a live chart); only that the memo hands the same answer back.
    datetime mT = Time[10];
    double   mP = High[10];
    TH3RealD d1, d2, d3;
    TH3RealDAt(mT, mP, true, 0, d1);          // arm the real-D slot
    int rdHits0 = TH3RebaseMemoHits();
    int rdMiss0 = TH3RebaseMemoMisses();
    TH3RealDAt(mT, mP, true, 0, d2);          // same key, same bar
    Check("memo: repeated real-D is a HIT", TH3RebaseMemoHits() == rdHits0 + 1);
    Check("memo: a HIT runs no walk", TH3RebaseMemoMisses() == rdMiss0);
    Check("memo: a HIT returns the same struct",
          d2.valid == d1.valid && d2.time == d1.time && d2.bars == d1.bars &&
          MathAbs(d2.price - d1.price) < 0.00000001);
    TH3RealDAt(mT, mP + 10.0 * Point, true, 0, d3);   // a different C
    Check("memo: a changed price is a MISS", TH3RebaseMemoMisses() == rdMiss0 + 1);

    double mRung = TH3PatternStepRungTF(Period());
    if(mRung <= 0) mRung = 100.0 * Point;   // any positive rung: this is a memo pin
    TH3HitProof hp1, hp2;
    TH3HitPivotMeasure(mT, mP, true, mRung, hp1, 0.0);   // arm the proof slot
    int hpHits0 = TH3RebaseMemoHits();
    int hpMiss0 = TH3RebaseMemoMisses();
    TH3HitPivotMeasure(mT, mP, true, mRung, hp2, 0.0);   // same key, same bar
    Check("memo: repeated proof measure is a HIT", TH3RebaseMemoHits() == hpHits0 + 1);
    Check("memo: a HIT reruns no walk", TH3RebaseMemoMisses() == hpMiss0);
    Check("memo: a HIT returns the same proof",
          hp2.valid == hp1.valid && hp2.tipTime == hp1.tipTime &&
          MathAbs(hp2.tipPrice - hp1.tipPrice) < 0.00000001 &&
          MathAbs(hp2.deepestRungs - hp1.deepestRungs) < 0.00000001);
    TH3HitPivotMeasure(mT, mP, true, mRung * 1.5, hp2, 0.0);   // a different rung
    Check("memo: a changed rung is a MISS", TH3RebaseMemoMisses() == hpMiss0 + 1);
    Print("[TH3TEST] memo hits=", TH3RebaseMemoHits(),
          " misses=", TH3RebaseMemoMisses());

    // ---- Summary ----
    Print("[TH3TEST] ==================== SUMMARY: ", g_pass, " passed, ", g_fail, " failed");
    if(g_fail == 0) {
        Alert("[TH3TEST] all ", g_pass, " assertions PASSED");
    } else {
        Alert("[TH3TEST] ", g_fail, " assertion(s) FAILED - see Experts log");
    }
    return 0;
}
