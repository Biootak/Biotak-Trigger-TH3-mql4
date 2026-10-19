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
// P-SESS: sessions renderer — mirrors the entry's seat (before EventHandlers,
// whose coop pump calls SessionsTick).
#include "..\Biotak\Sessions_Time.mqh"
#include "..\Biotak\Sessions_Model.mqh"
#include "..\Biotak\Sessions_Draw.mqh"
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

//--- P-SHOT-1 (2026-10-19) — THE DONE MARKER IS A FILE, NOT A JOURNAL LINE.
//--- MEASURED (P-DRAW-126): MT4 buffers the Experts journal in RAM, so the build's
//--- `-Shot` wait for a `[STRIPSHOT] DONE:` line kept sitting there while all 30 PNGs
//--- were already on disk — a COMPLETE capture reported `[FAIL] the harness never
//--- reached DONE`, and the honest verdict ("the pixels are here") was the one verdict
//--- a reader could not see. Every exit door of this script now leaves a marker written
//--- through the terminal's OWN file API (write + flush + close): a channel a reader on
//--- the other side of the process boundary sees the moment it lands. The build deletes
//--- the marker before the launch, so a previous run can never answer for this one.
void SSMarker(const string verdict)
{
   string f = "StripShot.done";
   int h = FileOpen(f, FILE_WRITE | FILE_TXT | FILE_ANSI);
   if(h == INVALID_HANDLE)
   {
      Print("[STRIPSHOT] marker open failed err=", GetLastError());
      return;
   }
   FileWrite(h, verdict + " shots=" + IntegerToString(g_shot) + " " + TimeToString(TimeLocal(), TIME_DATE | TIME_SECONDS));
   FileFlush(h);
   FileClose(h);
   Print("[STRIPSHOT] marker: ", verdict, " shots=", g_shot);
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

//--- P-LOOK — one fibo's look through the REAL write path, strip shut: the
//--- fibo itself is the subject, so the PNG shows what the hand would see.
//--- `st` is the STYLE slot value: 0-4 native, 5/6/7/8 Neon/Caps/Wash/3D.
void SSFiboDump(const string tag, const string fibo)
{
   int nl = (int)ObjectGetInteger(0, fibo, OBJPROP_LEVELS);
   Print("[STRIPSHOT] ", tag, " fibo levels=", nl,
         " w0=", ObjectGetInteger(0, fibo, OBJPROP_LEVELWIDTH, 0),
         " s0=", ObjectGetInteger(0, fibo, OBJPROP_LEVELSTYLE, 0));
   int total = ObjectsTotal(0, -1, -1), n = 0;
   for(int i = total - 1; i >= 0; i--)
   {
      string nm = ObjectName(0, i, -1, -1);
      if(nm != fibo && StringFind(nm, fibo + "_FS") != 0) continue;
      Print("[STRIPSHOT] obj ", nm,
            " type=", ObjectGetInteger(0, nm, OBJPROP_TYPE),
            " w=", ObjectGetInteger(0, nm, OBJPROP_WIDTH),
            " st=", ObjectGetInteger(0, nm, OBJPROP_STYLE),
            " clr=", ObjectGetInteger(0, nm, OBJPROP_COLOR),
            " p0=", ObjectGetDouble(0, nm, OBJPROP_PRICE, 0),
            " p1=", ObjectGetDouble(0, nm, OBJPROP_PRICE, 1));
      n++;
   }
   Print("[STRIPSHOT] ", tag, " family=", n);
}
void SSFiboLook(const string tag, const int w, const int st)
{
   string nm = "StripShotFiboLook";
   DrawSlotWrite(nm, DRAW_SLOT_COLOR, (double)(int)clrRed);
   DrawSlotWrite(nm, DRAW_SLOT_WIDTH, (double)w);
   DrawSlotWrite(nm, DRAW_SLOT_STYLE, (double)st);
   SSSave(tag);
   SSFiboDump(tag, nm);
}

//--- P-PEN-ALL (2026-10-19) — THE SHAPE PEN'S OWN PIXELS, WALKED. MT4 draws STYLE_*
//--- only at width 1, so «thick AND dashed» is a state the terminal cannot draw as
//--- one object: the pen demotes the master to the pattern at width 1 and seats
//--- `logical-1` rows of the MASTER'S OWN TYPE beside it. A mirror can draw that
//--- promise and a strip census cannot see it, so this state writes a real pair
//--- through the real slot writer and shoots the chart they land on. The walk below
//--- is the claim in numbers: every row is the master's type, width 1, the master's
//--- dash, carries no interior, and sits off the master's own anchors.
void SSPenDump(const string tag, const string nm)
{
   Print("[STRIPSHOT] pen master=", nm,
         " type=", ObjectGetInteger(0, nm, OBJPROP_TYPE),
         " w=", ObjectGetInteger(0, nm, OBJPROP_WIDTH),
         " st=", ObjectGetInteger(0, nm, OBJPROP_STYLE),
         " log=", PenStackLogicalWidth(nm),
         " rows=", PenStackChildCount(nm));
   for(int q = 0; q < DRAW_WIDTH_MAX; q++)
   {
      string ch = PenStackName(nm, q);
      if(ObjectFind(0, ch) < 0) break;
      Print("[STRIPSHOT] pen row ", ch,
            " type=", ObjectGetInteger(0, ch, OBJPROP_TYPE),
            " w=", ObjectGetInteger(0, ch, OBJPROP_WIDTH),
            " st=", ObjectGetInteger(0, ch, OBJPROP_STYLE),
            " fill=", ObjectGetInteger(0, ch, OBJPROP_FILL),
            " back=", ObjectGetInteger(0, ch, OBJPROP_BACK),
            " t0=", ObjectGetInteger(0, ch, OBJPROP_TIME, 0),
            " p0=", DoubleToString(ObjectGetDouble(0, ch, OBJPROP_PRICE, 0), _Digits),
            " t1=", ObjectGetInteger(0, ch, OBJPROP_TIME, 1),
            " p1=", DoubleToString(ObjectGetDouble(0, ch, OBJPROP_PRICE, 1), _Digits),
            " t2=", ObjectGetInteger(0, ch, OBJPROP_TIME, 2),
            " p2=", DoubleToString(ObjectGetDouble(0, ch, OBJPROP_PRICE, 2), _Digits));
   }
}
void SSPen(const string tag)
{
   string nm[7];
   int    ty[7];
   nm[0] = "StripShotPenRect"; ty[0] = OBJ_RECTANGLE;
   nm[1] = "StripShotPenEll";  ty[1] = OBJ_ELLIPSE;
   nm[2] = "StripShotPenTri";  ty[2] = OBJ_TRIANGLE;
   nm[3] = "StripShotPenChan"; ty[3] = OBJ_CHANNEL;
   nm[4] = "StripShotPenGann"; ty[4] = OBJ_GANNLINE;
   nm[5] = "StripShotPenTang"; ty[5] = OBJ_TRENDBYANGLE;   // P-UNIFY-2: the LINE family
   nm[6] = "StripShotPenCyc";  ty[6] = OBJ_CYCLES;         // P-UNIFY-2: the SHAPE family
   for(int i = 0; i < 7; i++)
   {
      PenStackStraysDrop(nm[i]);
      if(ObjectFind(0, nm[i]) >= 0) ObjectDelete(0, nm[i]);
   }
   bool ok[7];
   //--- P-PEN-ALL: the seats are computed off the chart's OWN bar count, not hard
   //--- indices: this state writes SEVEN drawings and a Time[70] past the newest bar
   //--- would create an object at time 0 (an invisible "shot" that still counts as
   //--- one). The wait loop in OnStart guarantees >= 40 bars, so iF >= 37 and the
   //--- oldest index this state touches is iF - 24 > 0.
   int iF = MathMin(70, Bars - 3);
   int i1 = iF - 8, i2 = iF - 16, i3 = iF - 24, i4 = iF - 4, i5 = iF - 12;
   ok[0] = ObjectCreate(0, nm[0], ty[0], 0, Time[iF], High[iF], Time[i1], Low[i1]);
   ok[1] = ObjectCreate(0, nm[1], ty[1], 0, Time[i1], High[iF], Time[i5], Low[i1]);
   ok[2] = ObjectCreate(0, nm[2], ty[2], 0, Time[iF], Low[i2], Time[i1], Low[i2], Time[i2], High[i4]);
   ok[3] = ObjectCreate(0, nm[3], ty[3], 0, Time[i3], High[iF], Time[i5], Low[i1], Time[i3], Low[i1]);
   ok[4] = ObjectCreate(0, nm[4], ty[4], 0, Time[i4], Low[i2], Time[i5], High[i4]);
   ok[5] = ObjectCreate(0, nm[5], ty[5], 0, Time[i2], Low[i3], Time[i5], Low[i4]);
   ok[6] = ObjectCreate(0, nm[6], ty[6], 0, Time[iF], Low[i5], Time[i4], Low[i3]);
   for(int j = 0; j < 7; j++)
   {
      if(!ok[j]) { Print("[STRIPSHOT] pen ", nm[j], ": ObjectCreate failed err=", GetLastError()); continue; }
      ObjectSetInteger(0, nm[j], OBJPROP_COLOR, clrDodgerBlue);
      ObjectSetInteger(0, nm[j], OBJPROP_SELECTABLE, true);
   }
   //--- the REAL path, in the hand's own order: colour, then the dash, then a width
   //--- the terminal cannot draw as a dash. The rect is the one the strip stands on,
   //--- so the same PNG carries its row and the five outlines.
   if(ok[0] && DrawStripOpenAt(nm[0], 120, 120))
   {
      DrawSlotWrite(nm[0], DRAW_SLOT_COLOR, (double)(int)clrRed);
      DrawSlotWrite(nm[0], DRAW_SLOT_STYLE, (double)STYLE_DASH);
      DrawSlotWrite(nm[0], DRAW_SLOT_WIDTH, 4.0);
   }
   else Print("[STRIPSHOT] pen: the strip would not open on the rect");
   for(int k = 1; k < 7; k++)
   {
      if(!ok[k]) continue;
      DrawSlotWrite(nm[k], DRAW_SLOT_STYLE, (double)STYLE_DASH);
      DrawSlotWrite(nm[k], DRAW_SLOT_WIDTH, 4.0);
   }
   SSSave(tag);
   for(int d = 0; d < 7; d++) if(ok[d]) SSPenDump(tag, nm[d]);
   for(int c = 0; c < 7; c++)
   {
      if(!ok[c]) continue;
      PenStackStraysDrop(nm[c]);
      ObjectDelete(0, nm[c]);
   }
   DrawStripClose();
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
   //--- P-SHOT-1: the START door. The bar wait below can hold this script for two
   //--- minutes before its first PNG, so a reader that only knows "the marker file
   //--- exists" cannot tell "the harness is early" from "the harness never ran". Every
   //--- door of this script writes the marker: START, each SKIP, and DONE.
   SSMarker("START");
   // P-BUILD-12 (2026-10-03) — A STARTUP SCRIPT MUST NOT JUDGE AN EMPTY CHART.
   // At launch the extra chart's history is still downloading: Bars reads short
   // for the first seconds, so an instant SKIP judges the download, not the
   // paint. Wait (pump the queue) up to two minutes; SKIP only a chart that
   // stays short. A SKIP still writes no PNG and fails --strict, as before.
   int wait = 0;
   while(Bars < 40 && wait < 120)
   {
      Sleep(1000);
      RefreshRates();
      wait++;
   }
   int bars = Bars;
   if(bars < 40)
   {
      Print("[STRIPSHOT] need ~40 bars, this chart has ", bars, " — SKIP");
      SSMarker("SKIP chart has " + IntegerToString(bars) + " bars");
      return;
   }
   // the strip's names are chart-global (PnlDrawS_*), so a live strip would be
   // re-stated by this run — say so instead of fighting it.
   if(ObjectFind(0, "PnlDrawS_B") >= 0)
   {
      Print("[STRIPSHOT] a strip is OPEN on this chart (PnlDrawS_B exists) — ",
            "close it (click the chart) and run again. SKIP");
      SSMarker("SKIP a strip was open on the chart");
      return;
   }

   string rect = SSMake("StripShotRect", OBJ_RECTANGLE, 25, 5);
   if(rect == "") { SSMarker("SKIP the rectangle could not be made"); return; }
   if(!DrawStripOpenAt(rect, 120, 120))
   {
      Print("[STRIPSHOT] DrawStripOpenAt failed on the rectangle — SKIP");
      SSMarker("SKIP the strip would not open on the rectangle");
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
   SSKind("DK_RECT",      OBJ_RECTANGLE,    1);   // the 17th kind - it had no PNG of its own
   SSKind("DK_TRIANGLE",  OBJ_TRIANGLE,     1);
   SSKind("DK_ELLIPSE",   OBJ_ELLIPSE,      1);
   SSKind("DK_ARROW",     OBJ_ARROW,        0);
   SSKind("DK_TEXT",      OBJ_TEXT,         0);
   SSKind("DK_TANGLE",    OBJ_TRENDBYANGLE, 1);   // P-UNIFY-2: the type the strip had no kind for
   SSKind("DK_CYCLES",    OBJ_CYCLES,       1);   // P-UNIFY-2
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

    // ── P-LOOK — the fibo's own looks, one fibo re-worn five times: every
    // ── switch tears down the previous look's family through the same sync
    // ── the hand's taps ride, so a stranded child fails HERE, in the census.
    string fl = "StripShotFiboLook";
    if(ObjectFind(0, fl) >= 0) ObjectDelete(0, fl);
    if(!ObjectCreate(0, fl, OBJ_FIBO, 0, Time[25], High[25], Time[5], Low[5]))
       Print("[STRIPSHOT] fibo look fibo: ObjectCreate failed err=", GetLastError());
    else
    {
       ObjectSetInteger(0, fl, OBJPROP_SELECTABLE, true);
       ObjectSetInteger(0, fl, OBJPROP_BACK, false);
       SSFiboLook("fibo_dash3",  3, ILS_DASH);
       SSFiboLook("fibo_solid5", 5, ILS_SOLID);
       SSFiboLook("fibo_neon3",  3, 4 + FIBPEN_LOOK_NEON);
       SSFiboLook("fibo_caps3",  3, 4 + FIBPEN_LOOK_CAPS);
       SSFiboLook("fibo_wash2",  2, 4 + FIBPEN_LOOK_WASH);
       FibPenSync(fl, true);
       ObjectDelete(0, fl);
    }

    // ── P-PEN-ALL — THE SHAPE PEN'S OWN PIXELS (one PNG, five pen-preserved
    // ── shapes, and the family walked in numbers beside them).
    SSPen("pen");

    // ── cleanup ──
   DrawStripClose();
   ChartRedraw();
   Print("[STRIPSHOT] DONE: ", g_shot, " screenshot(s) -> <MQL4>\\Files\\StripShot_*.png");
   //--- P-SHOT-1: the FLUSHED door the build reads. The journal line above stays for
   //--- the human reading the Experts tab; this file is what answers "did it finish".
   SSMarker("DONE");
}
//+------------------------------------------------------------------+
