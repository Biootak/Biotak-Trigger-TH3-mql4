//+------------------------------------------------------------------+
//| Biotak_TypeScale_Test.mq4                                        |
//| P-UI-69e (2026-09-25) — the D-03 assertion, live.                |
//|                                                                  |
//| The type scale was the ONE thing a scaled display destroyed       |
//| silently: the retired formula `pt = round(nominal*96/dpi)`        |
//| merged adjacent sizes — 7 == 8 at 125%, FOUR sizes alike at 200%, |
//| and every size alike (4pt) from 250% up — so a panel's section    |
//| caption drew exactly like its value, and the design's pixels      |
//| moved on every machine that was not the 96 DPI one the numbers    |
//| were measured on.                                                 |
//|                                                                  |
//| This script asserts the shipped rule (PnlPtAt, UtilityFunctions): |
//|   1. IDENTITY at 96 DPI — nominal == pt for the whole ladder;     |
//|   2. never below PNL_PT_MIN;                                      |
//|   3. the em never taller than the row (PNL_PT_FIT_PX);            |
//|   4. adjacent rungs are DISTINCT until the row cap, and equal     |
//|      ONLY at it (above ~240 DPI a 42px row cannot hold six sizes  |
//|      when one point is 4px — hierarchy there is weight/colour,    |
//|      which is D-03's second half).                                |
//|                                                                  |
//| The retired formula is kept BELOW as a witness: this run proves it |
//| really collapsed (so the fix is not a fix for a theory), and a     |
//| future refactor back to it fails here loudly.                     |
//|                                                                  |
//| HOW TO RUN: drag onto any chart, open the "Experts" tab, look for |
//| [TYPETEST] lines. It needs no quotes and no history.              |
//+------------------------------------------------------------------+
#property strict
#property script_show_inputs

// Same include chain as the indicator - the test runs the real code.
// P-BUILD-02: a harness mirrors the entry by hand. The metrics owner
// (PnlPtAt/PnlPt/PnlDpi) lives in UtilityFunctions, and its own includes
// (ZoneFactory -> ObjectCache/ConstantsAndEnums) only resolve in the entry's
// ORDER: a trimmed chain compiled 77 x `error 256` (ZoneFactory's ERR_ZONE_*
// from ZoneConstants) in the first cut of this file - the measured cost of
// guessing an include order instead of copying it.
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
// MUST precede GlobalVariables: the inpX->gX mirrors live in RuntimeSettings
#include "..\Biotak\RuntimeSettings.mqh"
#include "..\Biotak\GlobalVariables.mqh"
#include "..\Biotak\UtilityFunctions.mqh"
#include "..\Biotak\BaseKnotTool.mqh"
#include "..\Biotak\HRayTool.mqh"   // P-HR-01: same layer as the entry's chain (P-BUILD-02)
#include "..\Biotak\CalculationCache.mqh"
#include "..\Biotak\ZoneFactory.mqh"
#include "..\Biotak\ZoneConfig.mqh"       // SUnifiedZoneConfig (ExtendedDrawingFunctions)
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
#include "..\Biotak\TradePlanFormulas.mqh"   // STradePlan: the plan's own legs (P-BK-50)
#include "..\Biotak\AdaptiveScaling.mqh"
#include "..\Biotak\BasePriceManager.mqh"
#ifndef BUILD_LITE
#include "..\Biotak\WaveAnalysis.mqh"
#include "..\Biotak\FrequencyOptimizer.mqh"
// TH3TOOL-ON (2026-09-19): restored from TH3TOOL-OFF.
#include "..\Biotak\TH3Tool.mqh"
#endif
#include "..\Biotak\ObjectFunctions.mqh"
#include "..\Biotak\DrawToolbar.mqh"
// P-DRAW-116: the card surface's own number table, in the SAME seat the entry
// gives it (between the toolbar and the strip).
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

// The UI half, exactly as the Full entry composes it (P-BUILD-01/P-BUILD-02).
#include "..\Biotak\HTFCandles.mqh"
#include "..\Biotak\BiotakKit.mqh"
#include "..\Biotak\BiotakMenu.mqh"
#include "..\Biotak\BiotakPanels.mqh"

int g_tsPass = 0;
int g_tsFail = 0;

void TsCheck(const string label, const bool ok)
{
   if(ok) { g_tsPass++; Print("[TYPETEST] PASS: ", label); }
   else   { g_tsFail++; Print("[TYPETEST] FAIL: ", label); }
}

//--- THE RETIRED FORMULA, kept as the witness (see the header). It is a local
//--- test helper on purpose: production may never name it again.
int TsLegacyPt(const int nominal, const int dpi)
{
   int pt = (int)MathRound(nominal * 96.0 / (double)dpi);
   if(pt < PNL_PT_MIN) pt = PNL_PT_MIN;
   return pt;
}

//+------------------------------------------------------------------+
int OnStart()
{
   Print("[TYPETEST] ==================== type-scale test (P-UI-69e)");
   Print("[TYPETEST] this display: dpi=", PnlDpi(),
         "  shipped scale for nominal 5..10 = ",
         PnlPt(5), ",", PnlPt(6), ",", PnlPt(7), ",", PnlPt(8), ",", PnlPt(9), ",", PnlPt(10));

   // ---- 1. identity at 96 DPI: the machine every number was measured on ----
   bool ident = true;
   for(int n = PNL_PT_LADDER_MIN; n <= PNL_PT_LADDER_MAX; n++)
      if(PnlPtAt(n, 96) != n)
      {
         ident = false;
         Print("[TYPETEST]   not identity: nominal ", n, " -> ", PnlPtAt(n, 96), " pt at 96 DPI");
      }
   TsCheck("identity at 96 DPI (nominal == pt, the whole ladder)", ident);

   // ---- 2..4. the sweep: every scale the sane band allows, step 12 ----
   bool minOk = true, fitOk = true, distinctOk = true;
   int  rungs = 0;
   for(int dpi = 96; dpi <= 288; dpi += 12)
   {
      int cap = (int)MathFloor(PNL_PT_FIT_PX * 72.0 / (double)dpi);
      if(cap < PNL_PT_MIN) cap = PNL_PT_MIN;
      int prev = 0;
      for(int n = PNL_PT_LADDER_MIN; n <= PNL_PT_LADDER_MAX; n++)
      {
         int pt = PnlPtAt(n, dpi);
         int em = (int)MathRound(pt * (double)dpi / 72.0);
         rungs++;
         if(pt < PNL_PT_MIN)
         {
            minOk = false;
            Print("[TYPETEST]   below the floor at dpi=", dpi, " nominal=", n, " -> ", pt, " pt");
         }
         if(em > PNL_PT_FIT_PX)
         {
            fitOk = false;
            Print("[TYPETEST]   taller than the row at dpi=", dpi, " nominal=", n, " -> ", em, " px");
         }
         if(n > PNL_PT_LADDER_MIN && pt <= prev && pt != cap)
         {
            distinctOk = false;
            Print("[TYPETEST]   adjacent rungs alike BELOW the cap at dpi=", dpi,
                  " nominal=", n, " -> ", prev, " == ", pt, " (cap ", cap, ")");
         }
         prev = pt;
      }
   }
   TsCheck("never below PNL_PT_MIN (" + IntegerToString(rungs) + " rungs swept)", minOk);
   TsCheck("the em never exceeds PNL_PT_FIT_PX (a caption cannot cross into the next row)", fitOk);
   TsCheck("adjacent rungs are distinct until the row cap, equal only at it", distinctOk);

   // ---- the table, for the seven scales a user actually owns ----
   int scales[7] = {96, 120, 144, 168, 192, 240, 288};
   Print("[TYPETEST]   dpi        legacy[5..10]   shipped[5..10]");
   int oldColl = 0, newColl = 0;
   for(int i = 0; i < 7; i++)
   {
      int dpi = scales[i];
      string legacy = "", shipped = "";
      for(int n = 5; n <= 10; n++)
      {
         legacy  += IntegerToString(TsLegacyPt(n, dpi)) + " ";
         shipped += IntegerToString(PnlPtAt(n, dpi))    + " ";
         if(n > 5)
         {
            if(TsLegacyPt(n - 1, dpi) == TsLegacyPt(n, dpi)) oldColl++;
            if(PnlPtAt(n - 1, dpi)    == PnlPtAt(n, dpi))    newColl++;
         }
      }
      Print("[TYPETEST]   ", dpi, "      [ ", legacy, "]   [ ", shipped, "]");
   }
   Print("[TYPETEST]   equal adjacent pairs: legacy=", oldColl, "  shipped=", newColl,
         " (the shipped ones live at the row cap, 240 DPI and up)");
   TsCheck("the witness: the retired formula DID collapse (legacy pairs > shipped pairs)",
           oldColl > newColl);
   TsCheck("the shipped rule keeps them at or below the cap (" + IntegerToString(newColl) + ")",
           newColl <= 5);

   Print("[TYPETEST] ", g_tsPass, " pass / ", g_tsFail, " fail");
   Print("[TYPETEST] ==================== done");
   return 0;
}
