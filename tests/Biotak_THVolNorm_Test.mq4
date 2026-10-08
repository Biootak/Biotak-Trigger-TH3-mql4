//+------------------------------------------------------------------+
//| Biotak_THVolNorm_Test.mq4                                       |
//| Harness for P-TH-VOLNORM: the price-only TH label scale.        |
//| Includes THVolNorm.mqh ALONE (the module is dependency-free).   |
//| Drag onto a chart (any symbol/TF) and check the Experts tab.    |
//+------------------------------------------------------------------+
#property strict

#include "..\Biotak\THVolNorm.mqh"

int g_pass = 0;
int g_fail = 0;

void Check(const string name, const bool ok)
{
    if(ok) {
        g_pass++;
        Print("[VOLNORMTEST] PASS | ", name);
    } else {
        g_fail++;
        Print("[VOLNORMTEST] FAIL | ", name);
    }
}

void CheckNear(const string name, const double actual, const double expected, const double tol)
{
    Check(name + " (got " + DoubleToString(actual, 8) + " want " + DoubleToString(expected, 8) + ")",
          MathAbs(actual - expected) <= tol);
}

//+------------------------------------------------------------------+
int OnStart()
{
    Print("[VOLNORMTEST] ==================== TH vol-norm test start");

    // 1. OFF = exactly 1.0 before any series read (zero cost, revert path).
    Check("OFF returns 1.0", THVolNormColumnV(false, 60, 0.1666) == 1.0);
    Check("OFF with dead pct returns 1.0", THVolNormColumnV(false, 60, 0.0) == 1.0);
    Check("ON with dead pct returns 1.0", THVolNormColumnV(true, 60, 0.0) == 1.0);
    Check("ON with dead TF returns 1.0", THVolNormColumnV(true, 0, 0.1666) == 1.0);

    // 1b. Rung -> TF map (nearest standard TF in log-time, one owner).
    Check("rung M1 -> M1", THVolNormTFForFractalRung(0) == 1);
    Check("rung M4 -> M5", THVolNormTFForFractalRung(1) == 5);
    Check("rung M16 -> M15", THVolNormTFForFractalRung(2) == 15);
    Check("rung H1+M4 -> H1", THVolNormTFForFractalRung(3) == 60);
    Check("rung H4+M16 -> H4", THVolNormTFForFractalRung(4) == 240);
    Check("rung H17+M4 -> D1", THVolNormTFForFractalRung(5) == 1440);
    Check("rung D2+H20+M16 -> W1", THVolNormTFForFractalRung(6) == 10080);
    Check("rung D11+H9+M4 -> W1", THVolNormTFForFractalRung(7) == 10080);
    Check("rung D45+H12+M16 -> MN1", THVolNormTFForFractalRung(8) == 43200);
    Check("rung -1 -> -1", THVolNormTFForFractalRung(-1) == -1);
    Check("rung 9 -> -1", THVolNormTFForFractalRung(9) == -1);

    // 2. Core: V = RV / (pct/100). rv=0.004, pct=0.1666 -> 2.40096038.
    CheckNear("V = RV/ref", THVolNormVFromMean(0.004, 0.1666), 2.40096038, 0.000001);

    // 3. Clamps: raw 12 -> 5.0, raw 0.06 -> 0.2.
    Check("clamp high", THVolNormVFromMean(0.02, 0.1666) == 5.0);
    Check("clamp low", THVolNormVFromMean(0.0001, 0.1666) == 0.2);

    // 4. Guards: absence answers 1.0, never a guess.
    Check("rv=0 answers 1.0", THVolNormVFromMean(0.0, 0.1666) == 1.0);
    Check("rv<0 answers 1.0", THVolNormVFromMean(-0.001, 0.1666) == 1.0);
    Check("pct=0 answers 1.0", THVolNormVFromMean(0.004, 0.0) == 1.0);

    // 5. Deadband guard: first adoption + OFF flip pass at once, sub-2%
    // drift is absorbed, a 2%+ jump crosses with no delay.
    Check("adopt first", THVolNormLevelChanged(2.0) == true);
    Check("adopt same", THVolNormLevelChanged(2.0) == false);
    Check("drift absorbed", THVolNormLevelChanged(2.005) == false);
    Check("jump crosses", THVolNormLevelChanged(2.06) == true);
    Check("jump settled", THVolNormLevelChanged(2.06) == false);
    Check("OFF flips", THVolNormLevelChanged(1.0) == true);
    Check("OFF settled", THVolNormLevelChanged(1.0) == false);

    // 6. Levels path uses the same V family as the columns (pure core above).

    // 8. Output grid: 1.0/absence exact, the rest on the 0.05 lattice.
    Check("quantize 1.0 stays", THVolNormQuantize(1.0) == 1.0);
    Check("quantize 0 answers 1.0", THVolNormQuantize(0.0) == 1.0);
    CheckNear("quantize 2.4009 -> 2.40", THVolNormQuantize(2.40096038), 2.40, 0.000001);
    CheckNear("quantize 2.06 -> 2.05", THVolNormQuantize(2.06), 2.05, 0.000001);

    // 9. Needle mix is pure: base 0.65, moment 0.35, dead leg keeps the other.
    CheckNear("blend calm", THVolNormBlend(1.0, 1.0), 1.0, 0.000000001);
    CheckNear("blend spike", THVolNormBlend(2.0, 4.0), 2.7, 0.000000001);
    Check("blend dead fast keeps base", THVolNormBlend(2.0, -1.0) == 2.0);
    Check("blend dead slow keeps fast", THVolNormBlend(-1.0, 3.0) == 3.0);

    // 10. Gear weights: 1.0 at home, heavy neighbour, distant whisper.
    Check("gear self", THVolNormGearW(60, 60) == 1.0);
    CheckNear("gear M1-M5", THVolNormGearW(1, 5), 1.0 / (1.0 + MathLog(5.0)), 0.000000001);
    Check("gear distant < neighbour", THVolNormGearW(1, 43200) < THVolNormGearW(1, 5));
    Check("gear dead", THVolNormGearW(0, 60) == 0.0);

    // 11. Live: ON answers inside the clamp on this chart (any symbol/TF).
    double liveV = THVolNormColumnV(true, Period(), 0.1666);
    Check("live V in clamp", liveV >= 0.2 && liveV <= 5.0);
    Print("[VOLNORMTEST] live V=", DoubleToString(liveV, 4));

    // 12. Block clock is pure: 00/30 aligned, and drawn V freezes in-block.
    Check("block 0", THVolNormBlockStart(0) == 0);
    Check("block 1800", THVolNormBlockStart(1800) == 1800);
    Check("block 3599 -> 1800", THVolNormBlockStart(3599) == 1800);
    Check("drawn OFF is 1", THVolNormDrawnV(false, Period(), 0.1666) == 1.0);
    double d1 = THVolNormDrawnV(true, Period(), 0.1666);
    double d2 = THVolNormDrawnV(true, Period(), 0.1666);
    Check("drawn frozen in block", d1 == d2);
    Check("drawn in clamp", d1 >= 0.2 && d1 <= 5.0);

    // 13. Jump gate is pure: calm dance waits, a 15%+ step cuts the queue.
    Check("jump same holds", THVolNormJumpCuts(2.0, 2.0) == false);
    Check("jump 14.5% holds", THVolNormJumpCuts(2.29, 2.0) == false);
    Check("jump 16% cuts", THVolNormJumpCuts(2.32, 2.0) == true);
    Check("jump dead leg holds", THVolNormJumpCuts(0.0, 2.0) == false);

    // 14. Last slow read follows the column just read, never another TF.
    Check("last slow follows", THVolNormLastSlow(Period()) > 0.0);
    Check("last slow wrong TF is -1", THVolNormLastSlow(-5) == -1.0);

    // 15. Drawn V keeps one adoption per TF (the ability ladder asks several).
    double d5 = THVolNormDrawnV(true, 5, 0.0417);
    double d60 = THVolNormDrawnV(true, 60, 0.1666);
    Check("drawn per-TF slots in clamp", d5 >= 0.2 && d5 <= 5.0 && d60 >= 0.2 && d60 <= 5.0);

    // 16. Last bar count follows the column just read, never another TF.
    Check("last N follows", THVolNormLastN(Period()) >= 0);
    Check("last N wrong TF is -1", THVolNormLastN(999999) == -1);

    // 17. Same TF, two pcts (rungs 6+7 share W1): two answers, both clamped.
    double wA = THVolNormColumnV(true, 10080, 1.3332);
    double wB = THVolNormColumnV(true, 10080, 2.6664);
    Check("W1 rung6 in clamp", wA >= 0.2 && wA <= 5.0);
    Check("W1 rung7 in clamp", wB >= 0.2 && wB <= 5.0);

    // 7. End-to-end on the pure path: calm RV halves the column, sharp doubles it.
    double calmV = THVolNormVFromMean(0.0008, 0.1666);
    double sharpV = THVolNormVFromMean(0.004, 0.1666);
    Check("calm V < 1", calmV < 1.0);
    Check("sharp V > 1", sharpV > 1.0);
    Check("sharp/calm ratio = 5", MathAbs(sharpV / calmV - 5.0) < 0.0001);

    Print("[VOLNORMTEST] ==================== done pass=", g_pass, " fail=", g_fail);
    return 0;
}
