//+------------------------------------------------------------------+
//| Biotak_LookPersist_Test.mq4                                      |
//| P-DRAW-09c (2026-10-04) — the D-04 assertion, live.                |
//|                                                                  |
//| «همیشه آخرین تغییرات روی ابجکت پیش‌فرض بشه و هر سری نیاز نباشه تنظیم  |
//| بکن» — the kind memory made the last look the default of the NEXT   |
//| drawing; P-DRAW-09c made it survive an ATTACH. Three things can rot |
//| silently, and this script measures all three on the real code:      |
//|                                                                  |
//|   1. THE ROUND TRIP — a look set, packed, wiped the way an attach  |
//|      wipes it, and unpacked must come back slot for slot (the pack  |
//|      and the unpack are one bit-layout contract in two functions);  |
//|   2. clrNONE IS NOT A COLOUR — a slot the user never coloured must  |
//|      come back "no colour of its own", never 0xFFFFFF white with    |
//|      the anchors alone (P-DRAW-75's rule, one file over);           |
//|   3. THE FILE HALF — through the REAL writer (`DrawPresetsSave`),   |
//|      the wipe, and the REAL reader (`DrawPresetsLoad`), plus a kind |
//|      nobody styled must stay untouched.                            |
//|                                                                  |
//| HOW TO RUN: drag onto any chart, open the "Experts" tab, look for  |
//| [LOOKTEST] lines and the DONE line (0 failed is the pass).          |
//|                                                                  |
//| THE USER'S OWN FILE IS THEIR DATA (P-DRAW-05): it is read whole,    |
//| byte for byte, before the test and written back byte for byte       |
//| after it — the script leaves `Files\Biotak\DrawPresets.csv` exactly |
//| as it found it.                                                    |
//+------------------------------------------------------------------+
#property strict
#property description "P-DRAW-09c: the last look survives an attach (round trip + file)"

// Same include chain as the entry and the shot harness (P-BUILD-02): the test runs
// the real code, in the entry's own ORDER.
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

#include "..\Biotak\WaveAnalysis.mqh"

#include "..\Biotak\FrequencyOptimizer.mqh"

#include "..\Biotak\TH3Tool.mqh"

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

#include "..\Biotak\EventHandlers.mqh"

#include "..\Biotak\HTFCandles.mqh"

#include "..\Biotak\BiotakKit.mqh"

#include "..\Biotak\BiotakMenu.mqh"

#include "..\Biotak\BiotakPanels.mqh"


int g_lookOk = 0, g_lookFail = 0;

void LookChk(const string what, const bool ok)
{
   if(ok) { g_lookOk++; Print("[LOOKTEST] ok   ", what); return; }
   g_lookFail++;
   Print("[LOOKTEST] FAIL ", what);
}

//--- ONE known look: every slot the memory carries, none of them a default, so a slot
//--- that is not restored cannot pass by luck.
void LookSetKnown(const int k)
{
   s_dkValid[k]   = true;
   s_dkColor[k]   = (color)0x123456;
   s_dkFillClr[k] = (color)0x654321;
   s_dkWidth[k]   = 3;
   s_dkStyle[k]   = 2;
   s_dkFill[k]    = true;
   s_dkRay[k]     = 3;
   s_dkFont[k]    = 17;
   s_dkGlyph[k]   = 233;
   s_dkBack[k]    = true;
}
bool LookIsKnown(const int k)
{
   return (s_dkValid[k] && (int)s_dkColor[k] == 0x123456 && (int)s_dkFillClr[k] == 0x654321 &&
           s_dkWidth[k] == 3 && s_dkStyle[k] == 2 && s_dkFill[k] && s_dkRay[k] == 3 &&
           s_dkFont[k] == 17 && s_dkGlyph[k] == 233 && s_dkBack[k]);
}

void OnStart()
{
   Print("[LOOKTEST] P-DRAW-09c - the last look across an attach (file: ", DrawPresetPath(), ")  slots: slot=",
         IntegerToString(DRAW_LASTLOOK_SLOT), " band 0..", IntegerToString(DRAW_PRESET_MAX - 1));

   //--- the user's file, read whole and put back byte for byte at the end.
   uchar backup[]; int backupN = 0; bool hadFile = false;
   int rb = FileOpen(DRAW_PRESET_FILE, FILE_READ | FILE_BIN);
   if(rb != INVALID_HANDLE)
   {
      backupN = (int)FileSize(rb);
      if(backupN > 0)
      {
         ArrayResize(backup, backupN);
         hadFile = (FileReadArray(rb, backup, 0, backupN) == backupN);
      }
      FileClose(rb);
   }
   Print("[LOOKTEST] the file before the test: ", hadFile ? (IntegerToString(backupN) + " byte(s), kept") : "absent or empty");

   DrawStyleInit();
   DrawPresetsInit();

   //--- 1. THE ROUND TRIP, with no file in the way.
   LookSetKnown(DK_RECT);
   double pa = DrawStylePackA(DK_RECT), pb = DrawStylePackB(DK_RECT);
   DrawStyleInit();                                  // the wipe an attach does
   DrawStyleUnpack(DK_RECT, pa, pb);
   LookChk("pack/unpack round trip, every slot (A=" + DoubleToString(pa, 0) + " B=" + DoubleToString(pb, 0) + ")",
           LookIsKnown(DK_RECT));

   //--- 2. clrNONE is "no colour of its own", never a colour nobody chose.
   s_dkValid[DK_RECT]   = true;
   s_dkColor[DK_RECT]   = clrNONE;
   s_dkFillClr[DK_RECT] = clrNONE;
   pa = DrawStylePackA(DK_RECT); pb = DrawStylePackB(DK_RECT);
   DrawStyleInit();
   DrawStyleUnpack(DK_RECT, pa, pb);
   LookChk("clrNONE comes back as no colour of its own (border=" + IntegerToString((int)s_dkColor[DK_RECT]) +
           ", interior=" + IntegerToString((int)s_dkFillClr[DK_RECT]) + ")",
           ((int)s_dkColor[DK_RECT] < 0 && (int)s_dkFillClr[DK_RECT] < 0 && s_dkValid[DK_RECT]));

   //--- 3. THE FILE HALF: the real writer, the wipe, the real reader.
   LookSetKnown(DK_TEXT);
   DrawPresetsSave();
   DrawStyleInit();                                  // a fresh attach starts EMPTY
   LookChk("a fresh attach starts with no look of its own", (!s_dkValid[DK_TEXT] && !s_dkValid[DK_RECT]));
   DrawPresetsLoad();
   LookChk("the saved look came back from the file", LookIsKnown(DK_TEXT));
   LookChk("a kind nobody styled stayed untouched", !s_dkValid[DK_TRIANGLE]);
   LookChk("the reserved slot is outside every preset band", (DRAW_LASTLOOK_SLOT >= DRAW_PRESET_MAX && DRAW_LASTLOOK_SLOT != 0));

   //--- the user's own file back, byte for byte (or gone, if it was not there).
   FileDelete(DRAW_PRESET_FILE);
   if(hadFile)
   {
      int wb = FileOpen(DRAW_PRESET_FILE, FILE_WRITE | FILE_BIN);
      if(wb != INVALID_HANDLE)
      {
         FileWriteArray(wb, backup, 0, backupN);
         FileClose(wb);
      }
      else Print("[LOOKTEST] WARNING: the user's file could not be restored (err=", GetLastError(), ")");
   }
   Print("[LOOKTEST] DONE: ", g_lookOk, " ok, ", g_lookFail, " failed");
}

void OnDeinit(const int reason) { }
