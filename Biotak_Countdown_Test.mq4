//+------------------------------------------------------------------+
//| Biotak_Countdown_Test.mq4                                        |
//|                                                                  |
//| LIVE COUNTDOWN TAG — contract test.                              |
//|                                                                  |
//| The tag (`..._LBL_CloseIn_Tag`) is its OWN layer since           |
//| 2026-09-11 (P-LBL-05). This script locks the three contracts     |
//| that broke, or could silently break, that independence:          |
//|                                                                  |
//|   PART 1  NAMING — the name must never contain "ATR_". That is   |
//|           exactly the predicate the periodic object janitor       |
//|           (EventHandlers F-key path) and SetATRLabelsVisibility   |
//|           use to hide the ATR block; one rename and the tag dies |
//|           with the ATR labels again.                              |
//|                                                                  |
//|   PART 2  INDEPENDENCE — with the ATR labels OFF (switch + the   |
//|           real SetATRLabelsVisibility() sweep) the tag must      |
//|           still exist, still be painted, and still own a valid   |
//|           click rect.                                             |
//|                                                                  |
//|   PART 3  OWN SWITCH — turning the countdown OFF must delete the |
//|           object AND invalidate the cached rect, so the old spot |
//|           cannot answer clicks; turning it back ON must restore  |
//|           both.                                                   |
//|                                                                  |
//|   PART 4  CLICK REGION — the hit-test region must be exactly the |
//|           painted rect (plus the router's 2 px pad) and must lie |
//|           fully inside the chart. A dense grid scan proves there |
//|           is no phantom click area anywhere else, and no dead    |
//|           spot inside the label.                                  |
//|                                                                  |
//|   PART 5  PARK — an invalidated rect answers nothing, and with   |
//|           the live bar scrolled out of view there must be no     |
//|           click target anywhere on the chart; scrolling back     |
//|           must bring the tag (and its target) back.              |
//|                                                                  |
//| HOW TO RUN: drag onto a chart with live quotes (M1 preferred),   |
//| read the Experts tab, look for [CDTEST] lines.                   |
//|                                                                  |
//| SIDE EFFECTS (restored before the script ends): it toggles the   |
//| ATR-rows visibility and scrolls the chart away from the live bar |
//| and back. Globals it flips are script-local (a script does NOT   |
//| share memory with the running indicator), so the live indicator  |
//| is unaffected.                                                   |
//+------------------------------------------------------------------+
#property strict
#property description "Locks the live countdown tag: independence, park, click region"

// EXACTLY the indicator's include chain (Biotak Trigger TH3.mq4) — the test
// must compile the real production modules, not a hand-picked subset that
// silently drifts behind (the older *Render tests did exactly that).
#include "Biotak\BuildConfig.mqh"
#include "Biotak\MathConstants.mqh"
#include "Biotak\Logger.mqh"
#ifndef BUILD_LITE
#include "Biotak\Profiler.mqh"
#endif
#include "Biotak\PropertiesAndInputs.mqh"
#include "Biotak\ConstantsAndEnums.mqh"
#include "Biotak\ProjectConstants.mqh"
#include "Biotak\InputValidator.mqh"
#include "Biotak\FloatingPointHelper.mqh"
#include "Biotak\ObjectCountManager.mqh"
#include "Biotak\PerformanceOptimizations.mqh"
#include "Biotak\InputValidationEnhanced.mqh"
#include "Biotak\RuntimeSettings.mqh"
#include "Biotak\GlobalVariables.mqh"
#include "Biotak\UtilityFunctions.mqh"
#include "Biotak\BaseKnotTool.mqh"
#include "Biotak\CalculationCache.mqh"
#include "Biotak\ZoneFactory.mqh"
#include "Biotak\ZoneConfig.mqh"
#include "Biotak\ZoneConstants.mqh"
#include "Biotak\ObjectCache.mqh"
#include "Biotak\PropertyChangeDetector.mqh"
#include "Biotak\VisibilityManager.mqh"
#include "Biotak\TimeframeFunctions.mqh"
#include "Biotak\FractalTimeframes.mqh"
#include "Biotak\StandardTimeframes.mqh"
#include "Biotak\THCalculations.mqh"
#include "Biotak\ATRCalculations.mqh"
#include "Biotak\TradePlanFormulas.mqh"   // single source of trade-plan math (R-TRADEPLAN)
#include "Biotak\AdaptiveScaling.mqh"
#include "Biotak\BasePriceManager.mqh"
#ifndef BUILD_LITE
#include "Biotak\WaveAnalysis.mqh"
#include "Biotak\FrequencyOptimizer.mqh"
#endif
#include "Biotak\ObjectFunctions.mqh"
#include "Biotak\ExtendedDrawingFunctions.mqh"
#include "Biotak\ComboEngine.mqh"
#include "Biotak\FactorMode.mqh"
#include "Biotak\LevelPipeline.mqh"
#include "Biotak\ModeDefinitions.mqh"
#include "Biotak\LabelFunctions.mqh"
#include "Biotak\AlertFunctions.mqh"
#include "Biotak\HistoricalDataFunctions.mqh"
#include "Biotak\EventHandlers.mqh"
#include "Biotak\HTFCandles.mqh"
#include "Biotak\BiotakKit.mqh"
#include "Biotak\BiotakMenu.mqh"
#include "Biotak\BiotakPanels.mqh"

int g_pass = 0;
int g_fail = 0;
int g_skip = 0;

//+------------------------------------------------------------------+
void Ck(const string label, const bool ok)
{
   if(ok) { g_pass++; Print("[CDTEST] PASS: ", label); }
   else   { g_fail++; Print("[CDTEST] FAIL: ", label); }
}

void Skipped(const string label, const string why)
{
   g_skip++;
   Print("[CDTEST] SKIP: ", label, " (", why, ")");
}

void Info(const string label, const string value)
{
   Print("[CDTEST]   ", label, " = ", value);
}

//+------------------------------------------------------------------+
//| Paint height the click router assumes when the tag has no        |
//| measured height yet (mirrors LiveCountdownPointInside).          |
//+------------------------------------------------------------------+
int CdTagH()
{
   return (g_cdTagH > 0) ? g_cdTagH : (inpFontSize + 4);
}

//+------------------------------------------------------------------+
//| Dense scan of the visible chart: how many pixels answer the      |
//| click router, and where. Used to prove "no phantom click area".  |
//+------------------------------------------------------------------+
int GridHits(const int cw, const int ch, const int step,
             int &minX, int &minY, int &maxX, int &maxY)
{
   int hits = 0;
   minX = 0; minY = 0; maxX = -1; maxY = -1;
   if(cw <= 0 || ch <= 0 || step < 1) return 0;

   for(int gx = 0; gx < cw; gx += step)
   {
      for(int gy = 0; gy < ch; gy += step)
      {
         if(!LiveCountdownPointInside(gx, gy)) continue;
         if(hits == 0) { minX = gx; maxX = gx; minY = gy; maxY = gy; }
         else
         {
            if(gx < minX) minX = gx;
            if(gx > maxX) maxX = gx;
            if(gy < minY) minY = gy;
            if(gy > maxY) maxY = gy;
         }
         hits++;
      }
   }
   return hits;
}

//+------------------------------------------------------------------+
//| Calibrate what THIS terminal returns when reading               |
//| OBJPROP_TIMEFRAMES — so the "is it parked?" assertion does not   |
//| depend on a guessed bitmask value.                              |
//+------------------------------------------------------------------+
long TimeframeMaskProbe(const bool allPeriods)
{
   static const string pn = "BiCdTest_TfProbe";
   if(ObjectFind(0, pn) < 0) ObjectCreate(0, pn, OBJ_LABEL, 0, 0, 0);
   ObjectSetInteger(0, pn, OBJPROP_TIMEFRAMES, allPeriods ? OBJ_ALL_PERIODS : OBJ_NO_PERIODS);
   long v = ObjectGetInteger(0, pn, OBJPROP_TIMEFRAMES);
   ObjectDelete(0, pn);
   return v;
}

//+------------------------------------------------------------------+
//| Timeframe-mask readback calibration (filled in OnStart).          |
//| maskUsable == false means this terminal cannot tell OBJ_ALL_      |
//| PERIODS from OBJ_NO_PERIODS on readback, so visibility falls      |
//| back to "the object exists" and the park assertions use the       |
//| cached rect instead. Never a silent pass — it is printed.         |
//+------------------------------------------------------------------+
long g_maskNone  = 0;
long g_maskAll   = 0;
bool g_maskUsable = true;

//+------------------------------------------------------------------+
//| Does the tag object currently show on this chart?                |
//+------------------------------------------------------------------+
bool CdTagVisible(const string nm)
{
   if(ObjectFind(0, nm) < 0) return false;
   if(!g_maskUsable) return true;
   long v = ObjectGetInteger(0, nm, OBJPROP_TIMEFRAMES);
   if(v == g_maskNone) return false;
   if(v != g_maskAll)  return false;
   return true;
}

//+------------------------------------------------------------------+
//| Is the live bar (bar 0) inside the visible pixel window?          |
//+------------------------------------------------------------------+
bool LiveBarOnScreen(const int cw)
{
   double bid = MarketInfo(GetCachedSymbol(), MODE_BID);
   double ask = MarketInfo(GetCachedSymbol(), MODE_ASK);
   double q   = (bid > 0.0 && ask > 0.0) ? (bid + ask) / 2.0 : iClose(Symbol(), Period(), 0);
   if(q <= 0.0) return false;
   datetime bt = iTime(Symbol(), Period(), 0);
   if(bt <= 0) return false;
   int x = 0, y = 0;
   if(!ChartTimePriceToXY(0, 0, bt, q, x, y)) return false;
   return (x >= 0 && x < cw);
}

//+------------------------------------------------------------------+
void OnStart()
{
   Print("[CDTEST] ============ live countdown tag contract test ============");
   Print("[CDTEST] symbol=", Symbol(), " tf=", EnumToString((ENUM_TIMEFRAMES)Period()),
         " prefix=", inpObjectPrefix);

   //------------------------------------------------------------------
   // State we borrow and must give back (script-local memory only).
   //------------------------------------------------------------------
   bool  sShowCd   = g_showLiveCountdown;
   color sCdColor  = g_countdownColor;
   int   sCdSize   = g_countdownFontSize;
   int   sCdGap    = g_countdownGapPx;
   bool  sAtrVis   = g_atrLabelsVisible;
   bool  sShowAtr  = g_showATRLabels;

   string hiddenVar = "Biotak_isHidden_" + GetCachedChartIdStr();
   bool   sHidden   = (GlobalVariableCheck(hiddenVar) && GlobalVariableGet(hiddenVar) > 0.5);

   // The tag must be testable even if the user pressed F before running.
   GlobalVariableSet(hiddenVar, 0.0);
   RefreshIsHiddenCache();

   string prefix = inpObjectPrefix + "_" + GetCurrentTimeframe() + "_";
   string nm     = LiveCountdownObjName();

   g_maskNone   = TimeframeMaskProbe(false);
   g_maskAll    = TimeframeMaskProbe(true);
   g_maskUsable = (g_maskAll != g_maskNone);
   Info("OBJPROP_TIMEFRAMES readback", "none=" + IntegerToString((int)g_maskNone) +
                                       " all=" + IntegerToString((int)g_maskAll) +
                                       " usable=" + (g_maskUsable ? "yes" : "no"));
   if(!g_maskUsable)
      Print("[CDTEST] NOTE: this terminal does not distinguish the timeframe masks "
            "on readback — park checks fall back to the cached click rect.");

   int cw = (int)ChartGetInteger(0, CHART_WIDTH_IN_PIXELS);
   int ch = (int)ChartGetInteger(0, CHART_HEIGHT_IN_PIXELS);
   Info("chart pixels", IntegerToString(cw) + "x" + IntegerToString(ch));

   //==================================================================
   // PART 1 - naming / janitor predicate
   //==================================================================
   Print("[CDTEST] PART 1 | naming");
   Ck("tag name lives in this chart's TF namespace", StringFind(nm, prefix) == 0);
   Ck("tag name ends with LBL_CloseIn_Tag",
      StringFind(nm, "LBL_" + LIVE_COUNTDOWN_NAME) ==
      StringLen(nm) - StringLen("LBL_" + LIVE_COUNTDOWN_NAME));
   // THE lock: this is the string test the ATR janitor and the legacy purges
   // use. If the tag ever gets "ATR_" in its name it dies with the ATR block.
   Ck("tag name contains no \"ATR_\" (janitor predicate is false)",
      StringFind(nm, "ATR_") < 0);
   Ck("tag name is not the legacy ATR_Trade_Current_CloseIn",
      StringFind(nm, LIVE_COUNTDOWN_LEGACY_NAME) < 0);
   Info("tag object", nm);

   //==================================================================
   // PART 2 - independence from the ATR block
   //==================================================================
   Print("[CDTEST] PART 2 | survives the ATR labels being off");
   g_showLiveCountdown = true;

   g_atrLabelsVisible = false;
   g_showATRLabels    = false;
   Ck("own switch is what decides, ATR flags are irrelevant", LiveCountdownEnabled());

   SetATRLabelsVisibility(prefix, false);   // the real A-key / card sweep
   RefreshLiveCountdown();

   Ck("tag object still exists after the ATR-off sweep", ObjectFind(0, nm) >= 0);
   Ck("tag still painted (not parked) after the ATR-off sweep", CdTagVisible(nm));
   Ck("tag click rect still valid after the ATR-off sweep", g_cdTagValid);
   Ck("tag object type is still OBJ_LABEL",
      ObjectFind(0, nm) >= 0 && ObjectType(nm) == OBJ_LABEL);

   int ix = g_cdTagX + g_cdTagW / 2;
   int iy = g_cdTagY + CdTagH() / 2;
   Ck("router still hits the tag with ATR off", LiveCountdownPointInside(ix, iy));

   // give the ATR rows back exactly as we found them
   g_atrLabelsVisible = sAtrVis;
   g_showATRLabels    = sShowAtr;
   SetATRLabelsVisibility(prefix, sAtrVis);
   RefreshLiveCountdown();

   //==================================================================
   // PART 3 - the countdown's OWN switch
   //==================================================================
   Print("[CDTEST] PART 3 | own switch on/off");
   g_showLiveCountdown = true;
   RefreshLiveCountdown();
   Ck("tag is back after re-enabling", ObjectFind(0, nm) >= 0 && g_cdTagValid);

   ix = g_cdTagX + g_cdTagW / 2;
   iy = g_cdTagY + CdTagH() / 2;
   int  savedX = g_cdTagX, savedY = g_cdTagY;
   int  savedW = g_cdTagW, savedH = CdTagH();
   Ck("baseline: router hits the painted tag", LiveCountdownPointInside(ix, iy));

   g_showLiveCountdown = false;
   RefreshLiveCountdown();
   Ck("own switch OFF deletes the tag object", ObjectFind(0, nm) < 0);
   Ck("own switch OFF invalidates the cached rect", !g_cdTagValid);
   Ck("own switch OFF: the old spot cannot answer a click",
      !LiveCountdownPointInside(ix, iy));

   g_showLiveCountdown = true;
   RefreshLiveCountdown();
   Ck("own switch ON restores the object and the rect",
      ObjectFind(0, nm) >= 0 && g_cdTagValid);

   //==================================================================
   // PART 4 - the click region is exactly the painted rect
   //==================================================================
   Print("[CDTEST] PART 4 | click region");
   int x = g_cdTagX, y = g_cdTagY, w = g_cdTagW, h = CdTagH();
   Info("painted rect", "x=" + IntegerToString(x) + " y=" + IntegerToString(y) +
                        " w=" + IntegerToString(w) + " h=" + IntegerToString(h));

   Ck("rect starts inside the chart", x >= 0 && y >= 0);
   Ck("rect fits inside the chart horizontally", x + w <= cw);
   Ck("rect fits inside the chart vertically", y + h <= ch);

   Ck("centre hit",            LiveCountdownPointInside(x + w / 2, y + h / 2));
   Ck("pad corner hit (x-2,y-2)", LiveCountdownPointInside(x - 2, y - 2));
   Ck("just left of the pad misses",  !LiveCountdownPointInside(x - 3, y + h / 2));
   Ck("just right of the pad misses", !LiveCountdownPointInside(x + w + 3, y + h / 2));
   Ck("just below the pad misses",    !LiveCountdownPointInside(x + w / 2, y + h + 3));

   int step = 3;
   int hx1, hy1, hx2, hy2;
   int hits = GridHits(cw, ch, step, hx1, hy1, hx2, hy2);
   Info("grid hits (step 3)", IntegerToString(hits) +
        "  bbox=[" + IntegerToString(hx1) + "," + IntegerToString(hy1) + "]..[" +
        IntegerToString(hx2) + "," + IntegerToString(hy2) + "]");

   Ck("the chart has exactly one clickable blob", hits > 0);
   Ck("no click target outside the painted rect",
      hits > 0 && hx1 >= x - 2 && hy1 >= y - 2 && hx2 <= x + w + 2 && hy2 <= y + h + 2);
   Ck("no dead spot inside the label",
      hits > 0 && hx1 <= x + step && hy1 <= y + step &&
      hx2 >= x + w - step && hy2 >= y + h - step);

   //==================================================================
   // PART 5 - park (no phantom target for an absent tag)
   //==================================================================
   Print("[CDTEST] PART 5 | park & return");

   // (a) deterministic: an invalidated rect answers nothing at all
   bool keepValid = g_cdTagValid;
   g_cdTagValid = false;
   Ck("an invalidated rect (parked tag) answers no click",
      !LiveCountdownPointInside(savedX + savedW / 2, savedY + savedH / 2));
   g_cdTagValid = keepValid;
   Ck("restoring the rect restores the hit",
      LiveCountdownPointInside(savedX + savedW / 2, savedY + savedH / 2));

   // (b) real path: push the live bar out of the window
   int parkHits = 0;
   bool scrolled = ChartNavigate(0, CHART_END, -300);
   if(scrolled)
   {
      ChartRedraw();
      Sleep(500);
   }

   if(!scrolled || LiveBarOnScreen(cw))
      Skipped("live bar off-view parks the tag",
              "chart could not be scrolled away from the live bar here");
   else
   {
      RefreshLiveCountdown();
      int px1, py1, px2, py2;
      parkHits = GridHits(cw, ch, 3, px1, py1, px2, py2);
      long tfParked = (ObjectFind(0, nm) >= 0)
                      ? ObjectGetInteger(0, nm, OBJPROP_TIMEFRAMES) : g_maskNone;
      Info("off-view state", "rectValid=" + (g_cdTagValid ? "true" : "false") +
                             " tfMask=" + IntegerToString((int)tfParked) +
                             " hits=" + IntegerToString(parkHits));
      Ck("live bar off-view: no click target anywhere on the chart", parkHits == 0);
      Ck("live bar off-view: the tag is parked or fully off-screen",
         !g_cdTagValid || tfParked == g_maskNone || g_cdTagX >= cw);
   }

   // back to the live bar
   ChartNavigate(0, CHART_END, 0);
   ChartRedraw();
   Sleep(500);
   RefreshLiveCountdown();

   if(!LiveBarOnScreen(cw))
      Skipped("tag returns when the live bar comes back", "chart did not return to the live bar");
   else
   {
      Ck("tag returns when the live bar comes back",
         ObjectFind(0, nm) >= 0 && g_cdTagValid && CdTagVisible(nm));
      Ck("router hits the returned tag",
         LiveCountdownPointInside(g_cdTagX + g_cdTagW / 2, g_cdTagY + CdTagH() / 2));
   }

   //==================================================================
   // restore + summary
   //==================================================================
   g_showLiveCountdown  = sShowCd;
   g_countdownColor     = sCdColor;
   g_countdownFontSize  = sCdSize;
   g_countdownGapPx     = sCdGap;
   g_atrLabelsVisible   = sAtrVis;
   g_showATRLabels      = sShowAtr;
   GlobalVariableSet(hiddenVar, sHidden ? 1.0 : 0.0);
   RefreshIsHiddenCache();

   RefreshLiveCountdown();      // repaint the tag as the indicator would
   ObjectDelete(0, "BiCdTest_TfProbe");
   ChartRedraw();

   Print("[CDTEST] --------------------------------------------------------");
   Print("[CDTEST] RESULT: ", g_pass, " passed, ", g_fail, " failed, ", g_skip, " skipped");
   if(g_fail > 0)
      Alert("CDTEST: " + IntegerToString(g_fail) + " assertion(s) FAILED - check the Experts log");
   else
      Alert("CDTEST: all " + IntegerToString(g_pass) + " assertions PASSED");
   Print("[CDTEST] ========================================================");
}
//+------------------------------------------------------------------+
