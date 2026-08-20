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

#include "Biotak\TH3\TH3Types.mqh"
#include "Biotak\TH3\TH3Math.mqh"
#include "Biotak\TH3\TH3PatternStore.mqh"

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

    // ---- Summary ----
    Print("[TH3TEST] ==================== SUMMARY: ", g_pass, " passed, ", g_fail, " failed");
    if(g_fail == 0) {
        Alert("[TH3TEST] all ", g_pass, " assertions PASSED");
    } else {
        Alert("[TH3TEST] ", g_fail, " assertion(s) FAILED - see Experts log");
    }
    return 0;
}
