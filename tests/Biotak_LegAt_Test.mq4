//+------------------------------------------------------------------+
//| Biotak_LegAt_Test.mq4                           P-BK-136 (2026-11-01) |
//|                                                                  |
//| WHY. The leg table is RUNG-keyed and used to answer ONLY an exact |
//| row: an off-ladder knot time (20m, 140m) read 0, and every caller  |
//| replaced that absence with the box' own height — an absence dressed |
//| as a measurement. `BaseKnotLegAt` answers the way the ability table |
//| has since P-BK-126: exact row wins (so every rung is byte-identical |
//| to the build before it), else the nearest row BELOW x the project's |
//| √-law (`BaseKnotRungScale`), and 0 only when nothing is beneath.    |
//|                                                                  |
//| RUN. MT4 startup config: `Script=Biotak_LegAt_Test`. It writes      |
//| `MQL4\Files\biotak_legat_test.txt` (last line `DONE pass=.. fail=..`), |
//| prints [LEGAT] lines to the Experts tab, and returns.              |
//+------------------------------------------------------------------+
#property strict

#include "..\Biotak\BuildConfig.mqh"
#include "..\Biotak\MathConstants.mqh"
#include "..\Biotak\Logger.mqh"
#include "..\Biotak\Profiler.mqh"
#include "..\Biotak\PropertiesAndInputs.mqh"
#include "..\Biotak\ConstantsAndEnums.mqh"
#include "..\Biotak\ProjectConstants.mqh"
#include "..\Biotak\InputValidator.mqh"
#include "..\Biotak\FloatingPointHelper.mqh"
#include "..\Biotak\ObjectCountManager.mqh"
#include "..\Biotak\PerformanceOptimizations.mqh"
#include "..\Biotak\InputValidationEnhanced.mqh"
#include "..\Biotak\RuntimeSettings.mqh"
#include "..\Biotak\GlobalVariables.mqh"
#include "..\Biotak\UtilityFunctions.mqh"
#include "..\Biotak\BaseKnotTool.mqh"
#include "..\Biotak\HRayTool.mqh"
#include "..\Biotak\PathTool.mqh"
#include "..\Biotak\CalculationCache.mqh"
#include "..\Biotak\ZoneFactory.mqh"
#include "..\Biotak\ZoneConfig.mqh"
#include "..\Biotak\ZoneValidator.mqh"
#include "..\Biotak\ZoneConstants.mqh"
#include "..\Biotak\ObjectCache.mqh"
#include "..\Biotak\PropertyChangeDetector.mqh"
#include "..\Biotak\VisibilityManager.mqh"
#include "..\Biotak\TimeframeFunctions.mqh"
#include "..\Biotak\FractalTimeframes.mqh"
#include "..\Biotak\StandardTimeframes.mqh"
#include "..\Biotak\THCalculations.mqh"
#include "..\Biotak\ATRCalculations.mqh"
#include "..\Biotak\TradePlanFormulas.mqh"
#include "..\Biotak\AdaptiveScaling.mqh"
#include "..\Biotak\BasePriceManager.mqh"
#ifndef BUILD_LITE
#include "..\Biotak\WaveAnalysis.mqh"
#include "..\Biotak\FrequencyOptimizer.mqh"
#include "..\Biotak\TH3Tool.mqh"
#endif
#include "..\Biotak\ObjectFunctions.mqh"
#include "..\Biotak\DrawToolbar.mqh"
#include "..\Biotak\CardMetrics.mqh"
#include "..\Biotak\DrawStrip.mqh"
#include "..\Biotak\ExtendedDrawingFunctions.mqh"
#include "..\Biotak\ComboEngine.mqh"
#include "..\Biotak\FactorMode.mqh"
#include "..\Biotak\LevelPipeline.mqh"
#include "..\Biotak\ModeDefinitions.mqh"
#include "..\Biotak\LabelFunctions.mqh"
#include "..\Biotak\AlertFunctions.mqh"
#include "..\Biotak\HistoricalDataFunctions.mqh"
#include "..\Biotak\Sessions_Time.mqh"
#include "..\Biotak\Sessions_Model.mqh"
#include "..\Biotak\Sessions_Draw.mqh"
#include "..\Biotak\EventHandlers.mqh"
#include "..\Biotak\HTFCandles.mqh"
#include "..\Biotak\BiotakKit.mqh"
#include "..\Biotak\BiotakMenu.mqh"
#include "..\Biotak\BiotakPanels.mqh"

int g_laPass = 0;
int g_laFail = 0;

bool LaNear(const double a, const double b, const double tol = 0.01)
{ return (MathAbs(a - b) <= tol); }

void LaCheck(const string what, const double got, const double want)
{
   if(LaNear(got, want)) { g_laPass++; Print("[LEGAT] PASS  ", what, "  got=", DoubleToString(got, 4), "  want=", DoubleToString(want, 4)); }
   else                  { g_laFail++; Print("[LEGAT] FAIL  ", what, "  got=", DoubleToString(got, 4), "  want=", DoubleToString(want, 4)); }
}

void LaCheckEq(const string what, const int got, const int want)
{
   if(got == want) { g_laPass++; Print("[LEGAT] PASS  ", what, "  got=", got, "  want=", want); }
   else            { g_laFail++; Print("[LEGAT] FAIL  ", what, "  got=", got, "  want=", want); }
}

int OnStart()
{
   //--- THREE ROWS AT ONE ANCHOR: M15, H1, H4. Hunt is the plan's own 5/8 of Eng,
   //--- so a scaled Hunt and a scaled Eng must move by the SAME factor.
   int      mins[3] = {15, 60, 240};
   datetime ans[3]  = {0, 0, 0};
   double   eng[3]  = {30.0, 60.0, 120.0};
   double   hunt[3] = {18.75, 37.5, 75.0};
   double   tp1[3]  = {0, 0, 0};
   double   tp2[3]  = {0, 0, 0};
   double   tp3[3]  = {0, 0, 0};
   BaseKnotEngPush(mins, ans, eng, hunt, tp1, tp2, tp3, 3);

   Print("[LEGAT] ============ P-BK-136: a leg at any TIME, never \"0 = absent\"");

   //--- 1. THE PUSHED ROWS THEMSELVES: unchanged, to the last digit.
   LaCheck("exact M15",  BaseKnotEngPips(15, 0),  30.0);
   LaCheck("exact H1",   BaseKnotEngPips(60, 0),  60.0);
   LaCheck("exact H4",   BaseKnotEngPips(240, 0), 120.0);
   LaCheck("exact Hunt H1", BaseKnotHuntPips(60, 0), 37.5);

   //--- 2. BETWEEN ROWS: the √-law from the row BELOW, never a hole.
   //---    20m  = 30 x sqrt(20/15)  = 34.6410
   //---    140m = 60 x sqrt(140/60) = 91.6515
   LaCheck("20m from M15",  BaseKnotEngPips(20, 0),  30.0 * MathSqrt(20.0 / 15.0));
   LaCheck("140m from H1",  BaseKnotEngPips(140, 0), 60.0 * MathSqrt(140.0 / 60.0));
   LaCheck("140m Hunt from H1", BaseKnotHuntPips(140, 0), 37.5 * MathSqrt(140.0 / 60.0));

   //--- 3. THE SAME SCALE ON BOTH LEGS: entry/stop keeps 5/8 = 0.625 off-ladder.
   LaCheck("Hunt/Eng at 140m", BaseKnotHuntPips(140, 0) / BaseKnotEngPips(140, 0), 0.625);

   //--- 4. NO ROW BENEATH = THE ONLY ZERO LEFT.
   LaCheck("2m has nothing below", BaseKnotEngPips(2, 0), 0.0);

   //--- 5. MONOTONE: a longer time can never read a SHORTER leg. This is the
   //---    property the rung walk broke (3 -> 4 candles cut the stop 42 %).
   int t[7] = {15, 20, 45, 60, 80, 140, 240};
   double prev = -1.0;
   for(int i = 0; i < 7; i++)
   {
      double v = BaseKnotEngPips(t[i], 0);
      if(v + 1e-9 < prev) { g_laFail++; Print("[LEGAT] FAIL  monotone at ", t[i], "m: ", DoubleToString(v, 4), " < ", DoubleToString(prev, 4)); }
      else                { g_laPass++; }
      prev = v;
   }
   Print("[LEGAT] monotone 15/20/45/60/80/140/240 checked");

   //--- 6. THE RUNG SCALE ITSELF: one owner, no second table.
   LaCheckEq("RungScale refuses a down-step", (int)(BaseKnotRungScale(60, 15) > 0.0 ? 1 : 0), 0);
   LaCheck("RungScale 60->140", BaseKnotRungScale(60, 140), MathSqrt(140.0 / 60.0));

   //--- 7. P-BK-137: A BAND THAT IS NOT √-SHAPED. The table above is exactly √-scaled,
   //---    so it cannot tell the two laws apart. This band is the DATASET's own shape:
   //---    15m -> 30.0 and 60m -> 70.0 (rho 2.333 over x4 time, beta 0.611, not 0.5).
   //---    The leg must land ON both rows, and inside the band it must ask THE BAND.
   datetime a2[2] = {D'2026.10.27 08:40', D'2026.10.27 08:40'};
   int      m2[2] = {15, 60};
   double   e2[2] = {30.0, 70.0};
   double   h2[2] = {18.75, 43.75};
   double   z2[2] = {0, 0};
   int      mA[5] = {15, 60, 240, 15, 60};
   datetime aA[5] = {0, 0, 0, D'2026.10.27 08:40', D'2026.10.27 08:40'};
   double   eA[5] = {30.0, 60.0, 120.0, 30.0, 70.0};
   double   hA[5] = {18.75, 37.5, 75.0, 18.75, 43.75};
   double   tA[5] = {0, 0, 0, 0, 0};
   BaseKnotEngPush(mA, aA, eA, hA, tA, tA, tA, 5);
   LaCheckEq("the band is not sqrt-shaped", (MathAbs(e2[1] / e2[0] - 2.333333) < 0.0001 ? 1 : 0), 1);
   LaCheck("exact 15m of band A", BaseKnotEngPips(15, a2[0]), 30.0);
   LaCheck("exact 60m of band A", BaseKnotEngPips(60, a2[0]), 70.0);
   //---    log-linear through the two rows: 30 x (20/15)^0.611196 = 35.7671 (sqrt: 34.6410)
   LaCheck("20m on a 0.611 band", BaseKnotEngPips(20, a2[0]), 35.7671);
   //---    ... and 30 x (40/15)^0.611196 = 54.6351  (sqrt read 48.9898)
   LaCheck("40m on a 0.611 band", BaseKnotEngPips(40, a2[0]), 54.6351);
   //---    THE SEAM: one minute below the rung now costs 1 %, not 36 %.
   double at59 = BaseKnotEngPips(59, a2[0]);
   LaCheckEq("a 1m step at the rung is under 2 pct", (int)(MathAbs(70.0 / at59 - 1.0) < 0.02 ? 1 : 0), 1);
   //---    NO UPPER ROW = the old √-law, unchanged (the one fallback left).
   int      mB[1] = {15};
   datetime aB[1] = {0};
   double   eB[1] = {30.0};
   double   hB[1] = {18.75};
   double   zB[1] = {0};
   BaseKnotEngPush(mB, aB, eB, hB, zB, zB, zB, 1);
   LaCheck("no upper row keeps sqrt", BaseKnotEngPips(20, 0), 30.0 * MathSqrt(20.0 / 15.0));
   BaseKnotEngPush(mA, aA, eA, hA, tA, tA, tA, 5);

   Print("[LEGAT] DONE pass=", g_laPass, " fail=", g_laFail);
   int h = FileOpen("biotak_legat_test.txt", FILE_WRITE | FILE_TXT | FILE_ANSI);
   if(h != INVALID_HANDLE)
   {
      FileWrite(h, "DONE pass=" + IntegerToString(g_laPass) + " fail=" + IntegerToString(g_laFail));
      FileClose(h);
   }
   else Print("[LEGAT] marker open failed err=", GetLastError());
   return (g_laFail == 0 ? 0 : 1);
}
