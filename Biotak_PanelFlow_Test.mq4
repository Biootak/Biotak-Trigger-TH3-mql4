//+------------------------------------------------------------------+
//| Biotak_PanelFlow_Test.mq4                                        |
//|                                                                  |
//| PANEL CLOSE FLOW — contract test (P-UI-24).                      |
//| "I press X and nothing closes" must be reproducible on-chart,    |
//| not re-diagnosed from guesses. This script drives the REAL       |
//| production press pipeline and locks the three contracts that     |
//| make close delivery bulletproof:                                 |
//|                                                                  |
//|   PART 1  WIDE X (press) — PnlOpen(6) [HTF, 12 rows, wide],      |
//|           read the LIVE close-button geometry, press its centre  |
//|           via PnlHandleMouseMove(pressStart=true). Must close    |
//|           on PRESS (no release click needed), delete every       |
//|           Pnl6_* object. Placement is asserted separately        |
//|           against the xbx formula, so paint bugs can't hide      |
//|           behind delivery bugs or vice versa.                    |
//|   PART 2  WIDE DONE (press) — same on card 2 (ATR, wide).        |
//|   PART 3  OBJECT_CLICK fallback — PnlHandleClick(close-name)     |
//|           still closes (idempotent double-close is harmless).    |
//|   PART 4  NARROW regression — cards 0 and 7 still close after    |
//|           the R-WIDE pairing change (line==row, shift==0).       |
//|   PART 5  SUPPRESS immunity — a stale 350ms suppress window      |
//|           must NOT eat an X press (press-path ignores it).       |
//|   PART 6  STRIP open/close — item 13 (no X/Done by design)       |
//|           still opens and PnlCloseAll wipes it.                  |
//|   PART 7  R-WIDE pairing locks (P-UI-25) — bands always col 0,   |
//|           right clusters inside the 624 card, pairs<rows on      |
//|           wide, pairs==rows on narrow.                           |
//|   PART 8  BOUNDS SWEEP — every card / Step mode / Box tab: no    |
//|           object escapes its card frame (±20px glow fringe).     |
//|                                                                  |
//| HOW TO RUN: drag onto any chart, read the Experts tab for        |
//| [PFTEST] lines. If a live settings panel is open the test       |
//| SKIPS everything (it shares chart objects with the indicator).   |
//|                                                                  |
//| SIDE EFFECTS: none observable — every opened panel is closed,    |
//| chart mouse-scroll/foreground/context props are snapshotted and  |
//| restored (and asserted). Script memory is NOT shared with the    |
//| running indicator, but chart OBJECTS are: never run with a live  |
//| panel open (the script refuses to).                              |
//+------------------------------------------------------------------+
#property strict
#property description "Locks the panel close flow: X/Done press, click fallback, narrow regression"

// EXACTLY the indicator's include chain (Biotak Trigger TH3.mq4) — the test
// must compile the real production modules, not a hand-picked subset.
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
#include "Biotak\TradePlanFormulas.mqh"
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
   if(ok) { g_pass++; Print("[PFTEST] PASS: ", label); }
   else   { g_fail++; Print("[PFTEST] FAIL: ", label); }
}

void Skipped(const string label, const string why)
{
   g_skip++;
   Print("[PFTEST] SKIP: ", label, " (", why, ")");
}

// Bounds sweep: every object of one open card must sit inside the card
// rect (±20px fringe for baked glow pads). Returns "" when clean, else
// the first offender with its rect. Placement-independent (checks the
// CARD frame, not the chart), so it locks paint bugs, not positions.
string BoundsCheck(const int item)
{
   int px = g_PnlX[item], py = g_PnlY[item];
   int cw = PnlCardW(item), ph = PnlPanelH(item);
   int x0 = px - 20, x1 = px + cw + 20, y0 = py - 20, y1 = py + ph + 20;
   int total = ObjectsTotal(0, -1, -1);
   for(int i = total - 1; i >= 0; i--)
   {
      string nm = ObjectName(0, i, -1, -1);
      int pi = 0, pr = 0; string pk = "";
      ParsePnlName(nm, pi, pr, pk);
      if(pi != item) continue;
      int x = (int)ObjectGetInteger(0, nm, OBJPROP_XDISTANCE);
      int y = (int)ObjectGetInteger(0, nm, OBJPROP_YDISTANCE);
      int w = (int)ObjectGetInteger(0, nm, OBJPROP_XSIZE);
      int h = (int)ObjectGetInteger(0, nm, OBJPROP_YSIZE);
      if(w < 0) w = 0; if(h < 0) h = 0;
      if(x < x0 || x + w > x1 || y < y0 || y + h > y1)
         return nm + " @(" + IntegerToString(x) + "," + IntegerToString(y) +
                "+" + IntegerToString(w) + "x" + IntegerToString(h) + ")";
   }
   return "";
}

// Count chart objects under one prefix (orphan/ghost detector).
int PfxCount(const string pfx){
   int n = 0;
   int pl = StringLen(pfx);
   if(pl == 0) return 0;
   int total = ObjectsTotal(0, -1, -1);
   for(int i = total - 1; i >= 0; i--)
   {
      string nm = ObjectName(0, i, -1, -1);
      if(StringLen(nm) >= pl && StringSubstr(nm, 0, pl) == pfx) n++;
   }
   return n;
}

// Live centre of a button object (reads the PAINTED geometry — independent
// of the hit-test math under test).
bool ObjCentre(const string nm, int &cx, int &cy)
{
   if(ObjectFind(0, nm) < 0) return false;
   int x = (int)ObjectGetInteger(0, nm, OBJPROP_XDISTANCE);
   int y = (int)ObjectGetInteger(0, nm, OBJPROP_YDISTANCE);
   int w = (int)ObjectGetInteger(0, nm, OBJPROP_XSIZE);
   int h = (int)ObjectGetInteger(0, nm, OBJPROP_YSIZE);
   if(w <= 0 || h <= 0) return false;
   cx = x + w / 2;
   cy = y + h / 2;
   return true;
}

//+------------------------------------------------------------------+
void OnStart()
{
   // Same prefix the live indicator uses on THIS chart (no init side
   // effects — InitializeUIStates would purge + touch shared GVs).
   g_UI.btnPrefix = "BiotakMenuV2_" + IntegerToString(ChartID()) + "_";
   string pfx = g_UI.btnPrefix;

   // Never fight a live open panel: objects are shared with the indicator.
   if(PfxCount(pfx + "Pnl") > 0 || PfxCount(pfx + "Pal_") > 0)
   {
      Skipped("ALL PARTS", "a live settings panel/palette is open — close it first");
      Print("[PFTEST] RESULT: PASS=", g_pass, " FAIL=", g_fail, " SKIP=", g_skip);
      return;
   }

   long saveScroll = ChartGetInteger(0, CHART_MOUSE_SCROLL, 0);
   long saveFg = ChartGetInteger(0, CHART_FOREGROUND, 0);

   // ── PART 1: wide card X closes on PRESS ──
   PnlOpen(6);
   Ck("P1 card 6 opens", g_PnlOpen == 6);
   string c6 = PnlHead(6, "close");
   Ck("P1 close object exists", ObjectFind(0, c6) >= 0);
   // placement half (formula vs painted object)
   int ax = (int)ObjectGetInteger(0, c6, OBJPROP_XDISTANCE);
   int xbx = g_PnlX[6] + PnlCardW(6) - PNL_PAD_X - PNL_XBTN_VIS;
   Ck("P1 X placed at xbx", MathAbs(ax - xbx) <= 1);
   int cx = 0, cy = 0;
   bool gotC = ObjCentre(c6, cx, cy);
   Ck("P1 close geometry readable", gotC);
   if(gotC) PnlHandleMouseMove(cx, cy, true, true);
   Ck("P1 X press closes (g_PnlOpen==-1)", g_PnlOpen == -1);
   Ck("P1 close object deleted", ObjectFind(0, c6) < 0);
   Ck("P1 no Pnl6_* ghosts", PfxCount(pfx + "Pnl6_") == 0);

   // ── PART 2: wide card Done closes on PRESS ──
   PnlOpen(2);
   string d2 = PnlHead(2, "done");
   Ck("P2 card 2 opens + done exists", g_PnlOpen == 2 && ObjectFind(0, d2) >= 0);
   int dx = 0, dy = 0;
   bool gotD = ObjCentre(d2, dx, dy);
   Ck("P2 done geometry readable", gotD);
   if(gotD) PnlHandleMouseMove(dx, dy, true, true);
   Ck("P2 Done press closes", g_PnlOpen == -1);
   Ck("P2 no Pnl2_* ghosts", PfxCount(pfx + "Pnl2_") == 0);

   // ── PART 3: OBJECT_CLICK fallback still closes ──
   PnlOpen(6);
   string c6b = PnlHead(6, "close");
   int fl = PnlHandleClick(c6b, 0, 0);
   fl = fl;   // flags intentionally ignored — closure is the contract
   Ck("P3 click fallback closes", g_PnlOpen == -1);
   Ck("P3 no Pnl6_* ghosts", PfxCount(pfx + "Pnl6_") == 0);

   // ── PART 4: narrow cards unaffected by R-WIDE ──
   PnlOpen(0);
   string c0 = PnlHead(0, "close");
   int ex0 = 0, ey0 = 0;
   bool got0 = ObjCentre(c0, ex0, ey0);
   if(got0) PnlHandleMouseMove(ex0, ey0, true, true);
   Ck("P4 narrow card 0 X closes", got0 && g_PnlOpen == -1);
   PnlOpen(7);
   string d7 = PnlHead(7, "done");
   int ex7 = 0, ey7 = 0;
   bool got7 = ObjCentre(d7, ex7, ey7);
   if(got7) PnlHandleMouseMove(ex7, ey7, true, true);
   Ck("P4 narrow card 7 Done closes", got7 && g_PnlOpen == -1);

   // ── PART 5: stale suppress window must not eat X ──
   PnlOpen(6);
   UISuppressNextClick();   // poison the 350ms window on purpose
   string c6c = PnlHead(6, "close");
   int sx = 0, sy = 0;
   bool gotS = ObjCentre(c6c, sx, sy);
   if(gotS) PnlHandleMouseMove(sx, sy, true, true);
   Ck("P5 X press immune to suppress", gotS && g_PnlOpen == -1);

   // ── PART 6: strip (no X/Done by design) opens + wipes ──
   g_PnlX[13] = 200; g_PnlY[13] = 200;
   PnlOpen(13);
   string tb = PnlHead(13, "card");
   Ck("P6 strip opens", g_PnlOpen == 13 && ObjectFind(0, tb) >= 0);
   PnlCloseAll();
   Ck("P6 strip wiped", g_PnlOpen == -1 && ObjectFind(0, tb) < 0);

   // ── PART 7: R-WIDE pairing locks (P-UI-25) ──
   // The screenshot bug: full-width bands inherited col 1 and painted
   // 296px past the card edge (count pill + chevron floating over the
   // chart), sharing a line with a control. Lock: bands are always col 0
   // on their own line, right clusters stay inside the card, pairing
   // really compresses, narrow cards are untouched (line==row).
   PnlOpen(1);
   Ck("P7 card 1 opens wide", g_PnlOpen == 1 && PnlIsWide(1));
   int n1 = PnlRowsCount(1);
   Ck("P7 wide compresses (pairs<rows)", PnlPairRows(1) < n1);
   bool bandsOk = true;
   bool clusterOk = true;
   int cwx = g_PnlX[1] + PnlCardW(1);
   for(int r = 0; r < n1; r++)
   {
      if(PnlRowKind(1, r) != PNL_K_SEC) continue;
      if(PnlRowCol(1, r) != 0) { bandsOk = false; break; }
      string bc = PnlHead(1, IntegerToString(r) + "_BCNT");
      if(ObjectFind(0, bc) >= 0)
      {
         int bx = (int)ObjectGetInteger(0, bc, OBJPROP_XDISTANCE);
         if(bx + 28 > cwx) { clusterOk = false; break; }
      }
      string cv = PnlHead(1, IntegerToString(r) + "_CV");
      if(ObjectFind(0, cv) >= 0)
      {
         int vx = (int)ObjectGetInteger(0, cv, OBJPROP_XDISTANCE);
         if(vx + 10 > cwx) { clusterOk = false; break; }
      }
   }
   Ck("P7 every band is col 0", bandsOk);
   Ck("P7 band clusters inside the card", clusterOk);
   PnlCloseAll();
   Ck("P7 card 1 closed clean", g_PnlOpen == -1 && PfxCount(pfx + "Pnl1_") == 0);
   Ck("P7 narrow untouched (pairs==rows)",
      !PnlIsWide(0) && PnlPairRows(0) == PnlRowsCount(0));

   // ── PART 8: bounds sweep over every card / Step mode / Box tab ──
   // Generic appearance lock: no object may escape its card frame.
   int sweepItems[9] = {0, 1, 2, 3, 6, 7, 8, 10, 11};
   for(int si = 0; si < 9; si++)
   {
      int it2 = sweepItems[si];
      PnlOpen(it2);
      string bad = BoundsCheck(it2);
      Ck("P8 card " + IntegerToString(it2) + " in-bounds" +
         (bad == "" ? "" : (" [" + bad + "]")), bad == "");
      PnlCloseAll();
      Ck("P8 card " + IntegerToString(it2) + " wiped",
         PfxCount(pfx + "Pnl" + IntegerToString(it2) + "_") == 0);
   }
   for(int m = 0; m < 4; m++)   // Step card in every engine mode
   {
      g_stepCalculationMode = (ENUM_STEP_CALCULATION_MODE)m;
      PnlOpen(9);
      string bad9 = BoundsCheck(9);
      Ck("P8 step mode " + IntegerToString(m) + " in-bounds" +
         (bad9 == "" ? "" : (" [" + bad9 + "]")), bad9 == "");
      PnlCloseAll();
   }
   g_stepCalculationMode = (ENUM_STEP_CALCULATION_MODE)0;
   for(int t = 0; t < 3; t++)   // Base Box card on every tab
   {
      g_BkTab = t;
      PnlOpen(12);
      string bad12 = BoundsCheck(12);
      Ck("P8 box tab " + IntegerToString(t) + " in-bounds" +
         (bad12 == "" ? "" : (" [" + bad12 + "]")), bad12 == "");
      PnlCloseAll();
   }
   g_BkTab = 0;

   // ── cleanup + prop restore proof ──
   PnlCloseAll();
   ChartSetInteger(0, CHART_MOUSE_SCROLL, saveScroll);
   ChartSetInteger(0, CHART_FOREGROUND, saveFg);
   Ck("chart props restored",
      ChartGetInteger(0, CHART_MOUSE_SCROLL, 0) == saveScroll &&
      ChartGetInteger(0, CHART_FOREGROUND, 0) == saveFg);
   Ck("no Pnl_* leftovers", PfxCount(pfx + "Pnl") == 0);
   ChartRedraw();

   Print("[PFTEST] RESULT: PASS=", g_pass, " FAIL=", g_fail, " SKIP=", g_skip);
}
//+------------------------------------------------------------------+
