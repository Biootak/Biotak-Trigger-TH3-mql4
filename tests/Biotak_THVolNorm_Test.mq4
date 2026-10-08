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

    // 7. End-to-end on the pure path: calm RV halves the column, sharp doubles it.
    double calmV = THVolNormVFromMean(0.0008, 0.1666);
    double sharpV = THVolNormVFromMean(0.004, 0.1666);
    Check("calm V < 1", calmV < 1.0);
    Check("sharp V > 1", sharpV > 1.0);
    Check("sharp/calm ratio = 5", MathAbs(sharpV / calmV - 5.0) < 0.0001);

    Print("[VOLNORMTEST] ==================== done pass=", g_pass, " fail=", g_fail);
    return 0;
}
