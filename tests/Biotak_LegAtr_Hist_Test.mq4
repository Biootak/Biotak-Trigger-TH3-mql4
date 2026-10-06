//+------------------------------------------------------------------+
//| Biotak_LegAtr_Hist_Test.mq4                                     |
//|                                                                  |
//| THE LEG-ATR DETECTOR, ON HISTORY — OUT OF THE TERMINAL.          |
//|                                                                  |
//| WHY THIS EXISTS. The live switch only proves itself inside a CP: |
//| outside one it reads live by design, so "ON changes nothing" on  |
//| a trending chart is the fallback, not a verdict. Waiting for the |
//| next squeeze is not a test. This harness replays the detector   |
//| over the last 500 closed bars of the chart TF and its structure  |
//| TF, using the PRODUCTION composite (ATRWeightedComposite) for    |
//| every ATR read — the only non-production part is the scan's base |
//| shift (history needs base=b, live uses base=1).                  |
//|                                                                  |
//| WHAT IT PROVES, IN ONE RUN:                                      |
//|   * the production detector agrees with the replay at base=1     |
//|     (the bridge: same arithmetic, same bar)                      |
//|   * how many trailing compression runs history holds per TF      |
//|   * the live-vs-leg delta each one would have published          |
//|                                                                  |
//| HOW TO RUN: headless, like the StripShot (config Script=). Drag  |
//| onto any chart with 600+ bars works too. Read the Experts tab    |
//| for [LEGATRHIST] lines; the full table is in <MQL4>\Files\       |
//| legatr_hist_<SYM>_<TF>.txt. Side-effect free: reads only,        |
//| writes one report file, paints nothing.                          |
//+------------------------------------------------------------------+
#property strict
#property description "Replays the LEG-ATR compression scan over history and reports live-vs-leg per bar"

// EXACTLY the indicator's include chain (Biotak Trigger TH3.mq4) — a harness
// compiles the real production modules, never a hand-picked subset.
#include "..\Biotak\BuildConfig.mqh"
#include "..\Biotak\MathConstants.mqh"
#include "..\Biotak\Logger.mqh"
#ifndef BUILD_LITE
#include "..\Biotak\Profiler.mqh"
#endif
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
// P-DRAW-116: same seat as the entry (between the toolbar and the strip).
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
#include "..\Biotak\EventHandlers.mqh"
#include "..\Biotak\HTFCandles.mqh"
#include "..\Biotak\BiotakKit.mqh"
#include "..\Biotak\BiotakMenu.mqh"
#include "..\Biotak\BiotakPanels.mqh"

#define LH_SCAN_BARS  500   // base bars replayed per TF (closed bars only)
#define LH_MAX_RUN    48    // same bound as the production scan (LEGATR_MAX_SCAN)

// Shift-generalised production scan: base=b instead of base=1. All ATR reads
// are the production composite; the run rule is the production rule.
datetime LHHistAnchorAt(const ENUM_TIMEFRAMES tf, const int base, int &runOut)
{
   runOut = 0;
   int nb = iBars(Symbol(), tf);
   if(base < 1 || base + 2 >= nb) return 0;
   double ref = ATRWeightedComposite(tf, base);
   if(ref <= 0.0) return 0;
   double small = ref * 0.5;
   int smallN = 0;
   datetime ans = 0;
   for(int i = 1; i <= LH_MAX_RUN; i++)
   {
      int s = base + i;
      if(s >= nb) break;
      double h = iHigh(Symbol(), tf, s);
      double l = iLow(Symbol(), tf, s);
      if(h <= 0.0 || l <= 0.0 || h < l) break;
      if(h - l < small) { smallN++; continue; }
      if(smallN > 0) ans = iTime(Symbol(), tf, s);
      break;
   }
   runOut = smallN;
   return ans;
}

void LHReportTF(const ENUM_TIMEFRAMES tf, const int tfMin, const double pip,
                const int h, int &hits, double &sumDelta, double &maxDelta)
{
   int nb = iBars(Symbol(), tf);
   FileWriteString(h, "TF=" + IntegerToString(tfMin) + " bars=" + IntegerToString(nb) + "\n");
   FileWriteString(h, "base|time|run|live_p|leg_p|delta_pct\n");
   int rows = 0;
   for(int b = 1; b <= LH_SCAN_BARS; b++)
   {
      if(b + 2 >= nb) break;
      int run = 0;
      datetime a = LHHistAnchorAt(tf, b, run);
      if(a <= 0) continue;
      double live = ATRWeightedComposite(tf, b);
      if(live <= 0.0) continue;
      int ash = iBarShift(Symbol(), tf, a, false);
      if(ash <= 0) continue;
      double leg = ATRWeightedComposite(tf, ash);
      if(leg <= 0.0) continue;
      double d = (leg - live) / live * 100.0;
      hits++; sumDelta += d;
      if(d > maxDelta) maxDelta = d;
      if(rows < 30)
      {
         FileWriteString(h, IntegerToString(b) + "|" + TimeToString(iTime(Symbol(), tf, b), TIME_DATE | TIME_MINUTES)
            + "|" + IntegerToString(run)
            + "|" + DoubleToString(live / pip, 1)
            + "|" + DoubleToString(leg / pip, 1)
            + "|" + DoubleToString(d, 1) + "\n");
         rows++;
      }
   }
}

void OnStart()
{
   g_useLegATR = true;   // this unit's own switch: production detector armed
   int chartMin = Period();
   if(chartMin <= 0) chartMin = 60;
   int strMin = TradePlanStructureMinutes(chartMin);
   double pip = Point;
   if(Digits == 3 || Digits == 5) pip = Point * 10.0;
   int nbC = iBars(Symbol(), CompatTF(chartMin));
   if(nbC < LH_SCAN_BARS + 100)
   {
      Print("[LEGATRHIST] SKIP under bars=", nbC, " need=", LH_SCAN_BARS + 100);
      return;
   }
   Print("[LEGATRHIST] START sym=", Symbol(), " chartMin=", chartMin, " strMin=", strMin);
   // The bridge: production detector (base=1) vs replay at base=1 — same bar.
   int runP = 0, runH = 0;
   datetime prodA = TradePlanLegAnchor(chartMin);
   datetime histA = LHHistAnchorAt(CompatTF(chartMin), 1, runH);
   runP = TradePlanLegRunBars(chartMin);
   string bridge = "MISMATCH";
   if(prodA == histA && runP == runH) bridge = "MATCH";
   Print("[LEGATRHIST] bridge base=1 prod=", TimeToString(prodA), " hist=", TimeToString(histA),
         " runP=", runP, " runH=", runH, " ", bridge);
   string fn = "legatr_hist_" + Symbol() + "_" + IntegerToString(chartMin) + ".txt";
   int h = FileOpen(fn, FILE_WRITE | FILE_TXT | FILE_ANSI);
   if(h == INVALID_HANDLE)
   {
      Print("[LEGATRHIST] FAILED open err=", GetLastError());
      return;
   }
   FileWriteString(h, "sym=" + Symbol() + " chartMin=" + IntegerToString(chartMin)
      + " strMin=" + IntegerToString(strMin) + " bridge=" + bridge + "\n");
   int hits = 0; double sumD = 0.0, maxD = 0.0;
   LHReportTF(CompatTF(chartMin), chartMin, pip, h, hits, sumD, maxD);
   int hits2 = 0; double sumD2 = 0.0, maxD2 = 0.0;
   LHReportTF(CompatTF(strMin), strMin, pip, h, hits2, sumD2, maxD2);
   FileClose(h);
   double avg = 0.0, avg2 = 0.0;
   if(hits > 0) avg = sumD / (double)hits;
   if(hits2 > 0) avg2 = sumD2 / (double)hits2;
   Print("[LEGATRHIST] chart TF=", chartMin, " scans=", LH_SCAN_BARS, " hits=", hits,
         " avgDelta%=", DoubleToString(avg, 1), " maxDelta%=", DoubleToString(maxD, 1));
   Print("[LEGATRHIST] struct TF=", strMin, " scans=", LH_SCAN_BARS, " hits=", hits2,
         " avgDelta%=", DoubleToString(avg2, 1), " maxDelta%=", DoubleToString(maxD2, 1));
   Print("[LEGATRHIST] DONE: file=", fn, " bridge=", bridge);
}
