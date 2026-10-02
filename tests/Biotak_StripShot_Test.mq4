//+------------------------------------------------------------------+
//| Biotak_StripShot_Test.mq4                                        |
//|                                                                  |
//| THE STRIP'S OWN PIXELS, OUT OF THE TERMINAL.                     |
//|                                                                  |
//| WHY THIS EXISTS. tools/before-after.html compares the design      |
//| mock with a render built from the SAME literals the indicator     |
//| compiles (tools/sim-strip-panels.py). That render is a mirror,    |
//| and a mirror can be wrong about the one thing only the terminal   |
//| knows: what the blit really does. This harness drives the real    |
//| paint path — DrawStripOpenAt + DrawStripPaint, the same two calls |
//| a left-hold makes — puts the strip in each of its states, and     |
//| writes a PNG of every one to <MQL4>\Files\StripShot_<state>.png   |
//| plus a census of the objects it built with their REAL rects.      |
//|                                                                  |
//| WHAT IT PROVES, IN ONE RUN:                                       |
//|   * the row's own rect and cell count per kind                    |
//|   * the colour board's plate rect (its own card, P-DRAW-48)       |
//|   * the list popovers (MORE, WIDTH) and the panel's group ROWS    |
//|     — P-DRAW-117: the accordion's open group AND its folded state |
//|   * every object's x/y/w/h and BMPFILE — the terminal's answer,    |
//|     not the source's hope (the same question UIAudit asks, for     |
//|     the strip's own prefix PnlDrawS_)                             |
//|                                                                  |
//| HOW TO RUN: drag onto any chart with at least ~40 bars. Read the  |
//| Experts tab for [STRIPSHOT] lines; the PNGs are in               |
//| <MQL4>\Files\. It creates TWO of its own drawings and deletes     |
//| them again, and closes the strip it opened.                       |
//|                                                                  |
//| SIDE EFFECTS: the strip's objects (PnlDrawS_*) are shared with    |
//| the running indicator — never run with the strip OPEN on a chart  |
//| (a live strip would be re-stated by this script's opens).         |
//+------------------------------------------------------------------+
#property strict
#property description "Paints the strip's states in the terminal and writes PNG + a geometry census"

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
// P-DRAW-116: the card surface's own number table, in the SAME seat the entry
// gives it (between the toolbar and the strip), so the strip's panel reaches
// `PNL_*` here exactly as it does in the indicator.
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

int g_shot = 0;

void SSSave(const string tag)
{
   ChartRedraw();
   Sleep(250);                       // let the terminal blit before the grab
   int cw = (int)ChartGetInteger(0, CHART_WIDTH_IN_PIXELS, 0);
   int ch = (int)ChartGetInteger(0, CHART_HEIGHT_IN_PIXELS, 0);
   if(cw <= 0) cw = 1600;
   if(ch <= 0) ch = 900;
   string f = "StripShot_" + tag + ".png";
   if(ChartScreenShot(0, f, cw, ch, 0)) { g_shot++; Print("[STRIPSHOT] shot ", f); }
   else Print("[STRIPSHOT] shot FAILED ", f, " err=", GetLastError());
}

//--- the terminal's OWN answer: every object the strip owns, with its real rect
//--- and the bitmap file it stored. A count of 0 for a state that should paint
//--- is the one failure no compile can see.
void SSDump(const string tag)
{
   int total = ObjectsTotal(0, -1, -1), n = 0;
   for(int i = total - 1; i >= 0; i--)
   {
      string nm = ObjectName(0, i, -1, -1);
      if(StringFind(nm, "PnlDrawS_") != 0) continue;
      int x = (int)ObjectGetInteger(0, nm, OBJPROP_XDISTANCE);
      int y = (int)ObjectGetInteger(0, nm, OBJPROP_YDISTANCE);
      int w = (int)ObjectGetInteger(0, nm, OBJPROP_XSIZE);
      int h = (int)ObjectGetInteger(0, nm, OBJPROP_YSIZE);
      if(w < 0) w = 0; if(h < 0) h = 0;
      string bmp = "";
      if((int)ObjectGetInteger(0, nm, OBJPROP_TYPE) == OBJ_BITMAP_LABEL)
         bmp = ObjectGetString(0, nm, OBJPROP_BMPFILE);
      Print("[STRIPSHOT] obj ", nm, " @", x, ",", y, " ", w, "x", h,
            bmp != "" ? (" bmp=" + bmp) : "");
      n++;
   }
   Print("[STRIPSHOT] ", tag, " objs=", n,
         " strip=", s_dsX, ",", s_dsY, " ", s_dsW, "x", s_dsH,
         " cells=", s_dsN, " picker=", s_dsPicker, " gear=", s_dsGear,
         " board=", s_dsBX, ",", s_dsBY, " ", s_dsBW, "x", s_dsBH,
         " gearWxH=", s_dsGearW0, "x", s_dsGearH,
         " grp=", s_dsGearGrp[0], " fold=", s_dsGearCollapsed,
         " rows=", s_dsPN, " kind=", DrawKindName(s_dsKind));
}

//--- one kind's quick row: make the drawing, open the strip on it, shoot, drop
//--- it again. `anchors` = 1 for the single-anchor types (ObjectCreate takes the
//--- count the type really has; a second pair is ignored by some and refused by
//--- others).
void SSKind(const string tag, const int type, const int anchors)
{
   string nm = "StripShot_" + tag;
   if(ObjectFind(0, nm) >= 0) ObjectDelete(0, nm);
   bool ok;
   if(anchors == 0)
      ok = ObjectCreate(0, nm, type, 0, Time[25], High[25]);
   else
      ok = ObjectCreate(0, nm, type, 0, Time[25], High[25], Time[5], Low[5]);
   if(!ok) { Print("[STRIPSHOT] ", tag, ": ObjectCreate failed err=", GetLastError()); return; }
   ObjectSetInteger(0, nm, OBJPROP_COLOR, clrDodgerBlue);
   ObjectSetInteger(0, nm, OBJPROP_WIDTH, 2);
   if(type == OBJ_TEXT) ObjectSetString(0, nm, OBJPROP_TEXT, "Biotak");
   if(!DrawStripOpenAt(nm, 120, 120))
   {
      Print("[STRIPSHOT] ", tag, ": the strip would not open on it");
      ObjectDelete(0, nm);
      return;
   }
   SSState(tag, DSTRIP_PICK_NONE, 0);
   DrawStripClose();
   ObjectDelete(0, nm);
}

//--- `folded` is the accordion's second fact (P-DRAW-117): the same open group
//--- with its body folded away. Every existing call keeps the old default.
void SSState(const string tag, const int picker, const int gear, const bool folded = false)
{
   s_dsPicker = picker;
   s_dsGear = gear;
   s_dsGearCollapsed = folded;
   DrawStripPaint();
   SSSave(tag);
   SSDump(tag);
}

//--- one drawing of `type`, inside the visible bars (DrawAnchorXY projects it,
//--- so a rectangle parked 300 bars back would simply report the projection
//--- failed — the harness must look like a drawing the user would hold).
string SSMake(const string name, const int type, const int barA, const int barB)
{
   if(ObjectFind(0, name) >= 0) ObjectDelete(0, name);
   double hi = High[barA], lo = Low[barB];
   if(!ObjectCreate(0, name, type, 0, Time[barA], hi, Time[barB], lo))
   {
      Print("[STRIPSHOT] ObjectCreate failed for ", name, " err=", GetLastError());
      return "";
   }
   ObjectSetInteger(0, name, OBJPROP_COLOR, clrDodgerBlue);
   ObjectSetInteger(0, name, OBJPROP_WIDTH, 2);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, true);
   ObjectSetInteger(0, name, OBJPROP_BACK, false);
   if(type == OBJ_RECTANGLE) ObjectSetInteger(0, name, OBJPROP_FILL, true);
   return name;
}

//+------------------------------------------------------------------+
void OnStart()
{
   int bars = Bars;
   if(bars < 40)
   {
      Print("[STRIPSHOT] need ~40 bars, this chart has ", bars, " — SKIP");
      return;
   }
   // the strip's names are chart-global (PnlDrawS_*), so a live strip would be
   // re-stated by this run — say so instead of fighting it.
   if(ObjectFind(0, "PnlDrawS_B") >= 0)
   {
      Print("[STRIPSHOT] a strip is OPEN on this chart (PnlDrawS_B exists) — ",
            "close it (click the chart) and run again. SKIP");
      return;
   }

   string rect = SSMake("StripShotRect", OBJ_RECTANGLE, 25, 5);
   if(rect == "") return;
   if(!DrawStripOpenAt(rect, 120, 120))
   {
      Print("[STRIPSHOT] DrawStripOpenAt failed on the rectangle — SKIP");
      ObjectDelete(0, rect);
      return;
   }

   // ── the five states of a BOX's strip ──
   SSState("row",         DSTRIP_PICK_NONE, 0);
   SSState("board",       DRAW_SLOT_COLOR,  0);
   SSState("more",        DSTRIP_MORE,      0);
   SSState("width",       DRAW_SLOT_WIDTH,  0);
   SSState("panel_paint", DSTRIP_PICK_NONE, DSTRIP_GEAR_PAINT);
   SSState("panel_style", DSTRIP_PICK_NONE, DSTRIP_GEAR_STYLE);
   SSState("panel_look",  DSTRIP_PICK_NONE, DSTRIP_GEAR_TPL);
   SSState("panel_row",   DSTRIP_PICK_NONE, DSTRIP_GEAR_STRIP);
   SSState("panel_fold",  DSTRIP_PICK_NONE, DSTRIP_GEAR_STRIP, true);   // P-DRAW-117

   DrawStripClose();
   ObjectDelete(0, rect);

   // ── EVERY KIND: one drawing, its row, then away. The tags are the KIND's own
   // ── name, so tools/before-after.py can put each shot under the same row the
   // ── design and the sim are already showing. One drawing at a time keeps every
   // ── frame clean (fifteen boxes on the chart would sit under the strip).
   SSKind("DK_LINE",      OBJ_TREND,        1);
   SSKind("DK_HLINE",     OBJ_HLINE,        0);
   SSKind("DK_VLINE",     OBJ_VLINE,        0);
   SSKind("DK_CHANNEL",   OBJ_CHANNEL,      1);
   SSKind("DK_FIBO",      OBJ_FIBO,         1);
   SSKind("DK_FIBOFAN",   OBJ_FIBOFAN,      1);
   SSKind("DK_FIBOCHAN",  OBJ_FIBOCHANNEL,  1);
   SSKind("DK_EXPANSION", OBJ_EXPANSION,    1);
   SSKind("DK_GANN",      OBJ_GANNLINE,     1);
   SSKind("DK_PITCHFORK", OBJ_PITCHFORK,    1);
   SSKind("DK_TRIANGLE",  OBJ_TRIANGLE,     1);
   SSKind("DK_ELLIPSE",   OBJ_ELLIPSE,      1);
   SSKind("DK_ARROW",     OBJ_ARROW,        0);
   SSKind("DK_TEXT",      OBJ_TEXT,         0);
   // DK_RECT's row is the pair in section 1 of the page (shot as "row" above).

   // ── a fibo's own two surfaces: the level-membership list and its panel ──
   string fib = SSMake("StripShotFibo", OBJ_FIBO, 25, 5);
   if(fib != "")
   {
      DrawStripClose();
      if(DrawStripOpenAt(fib, 120, 300))
      {
         SSState("fibo_levels", DSTRIP_SLOT_LEVELS, 0);
         SSState("fibo_paint",  DSTRIP_PICK_NONE, DSTRIP_GEAR_PAINT);
      }
      else Print("[STRIPSHOT] fibo open failed");
      DrawStripClose();
      ObjectDelete(0, fib);
   }

   // ── cleanup ──
   DrawStripClose();
   ChartRedraw();
   Print("[STRIPSHOT] DONE: ", g_shot, " screenshot(s) -> <MQL4>\\Files\\StripShot_*.png");
}
//+------------------------------------------------------------------+
