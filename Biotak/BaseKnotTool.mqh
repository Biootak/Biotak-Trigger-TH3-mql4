//+------------------------------------------------------------------+
//|                                              BaseKnotTool.mqh    |
//|        Base / Knot Measurement Tool — Meta-drag + TV 2-click hybrid |
//|        base-box drawer with Entry / SL / TP projections.          |
//+------------------------------------------------------------------+
//| LAYER: drawing/domain (no UI deps — compiles in Full AND Lite).   |
//| The Tools-ring button, menu hide/restore and chart-lock watchdog  |
//| hooks live on the UI side (BiotakMenu/BiotakPanels) and call into |
//| this module. Chart scroll is locked directly here (raw Chart*      |
//| calls) so Lite — which has no menu — keeps drag/delete working.   |
//|                                                                   |
//| STATE MACHINE — one gesture, two dialects (researched 2026-09-06):   |
//| MT4 desktop (Insert → Shapes → Rectangle): "click the starting point |
//| and drag it to the end point"; TradingView Rectangle: "click at one  |
//| corner, move, click again at the opposite corner" (Shift = square).  |
//| We accept BOTH: press-drag-release commits on release (Meta-native), |
//| click-move-click commits on the second click (TV-native), with a live|
//| rubber-band in both. While BK_ARMED/BK_PREVIEW,                      |
//| BaseKnotOnChartEvent() returns true for consumed events so           |
//| OnChartEventHandler returns early and nothing else (custom-price,    |
//| TH3, panels) sees the gesture.                                       |
//|   BK_IDLE →(Tools click)→ BK_ARMED →(press)→ BK_PREVIEW              |
//|   BK_PREVIEW →(drag)→ rubber-band →(release)→ commit → BK_ARMED     |
//|   BK_PREVIEW →(click, no drag)→ waiting →(hover preview)→           |
//|                (2nd click/drag-release)→ commit → BK_ARMED           |
//| A waiting corner is kept (not melted): an accidental click never     |
//| loses corner 1, a degenerate commit is rejected and stays waiting.   |
//| The tool stays armed for the next box; ESC / right-click / orb-click |
//| → BK_IDLE. CHARTEVENT_CLICK is only a fallback for builds that drop  |
//| MOUSE_MOVE edges (ARMED+CLICK = missed press, PREVIEW+CLICK = missed |
//| release; normal flows swallow it via the stroke debounce).           |
//|                                                                   |
//| PRODUCT RULES (2026-09-06 — no Buy/Sell button, fully automatic): |
//|  * Direction is decided ONCE at commit and FROZEN in the registry |
//|    (+ chart-scoped GV) — live ticks NEVER recompute it, so a price |
//|    vibrating inside the box cannot flicker the lines. A box below  |
//|    the live price = demand = Buy (Entry=top, SL=bottom, TP=top+2R);|
//|    a box above it = supply = Sell (mirrored). A commit landing     |
//|    with the price INSIDE the box resolves by entry side: the most  |
//|    recent close outside the box decides (from below → Buy, from    |
//|    above → Sell), mid-vs-price only as the last fallback.          |
//|  * Multi-instance: box ids are "<commitTFmin>_<tick>" (+ rand on   |
//|    collision), so any number of knots coexist; tails are split at  |
//|    the LAST underscore because ids themselves contain one.         |
//|  * TF-scoped visibility: each box carries its commit-TF mask and   |
//|    shows on that TF and lower ones only — a low-TF knot never      |
//|    collapses into a hairline on a much higher TF.                  |
//|  * Magnet: both corners (and the rubber-band) snap to the nearer   |
//|    High/Low shadow of the clicked candle, gated by the project     |
//|    magnet switch + sensitivity (inpEnableMagnet /                  |
//|    inpMagnetSensitivityPips — same language as the pin magnet).    |
//|  * Info badge: chart-anchored "[H Pips | R:R 1:N]" text at the box |
//|    corner; the X button is the only pixel badge (re-glued on the   |
//|    500 ms tick + CHART_CHANGE). Entry/SL/TP are OBJ_TREND rays     |
//|    (RAY_RIGHT) anchored at the box right edge, BACK + unselectable.|
//|  * Chain cleanup: deleting the BOX wipes every child in one        |
//|    ObjectsDeleteAll(prefix) call; deleting a CHILD self-heals it   |
//|    via BaseKnotSync. The BK layer is independent: HideAllTHObjects,|
//|    the L/F toggles, DeleteAllIndicatorObjects (non-deep), the      |
//|    emergency + incremental cleanups and the generic OBJECT_DELETE   |
//|    redraw trigger all skip "_BK_" names (see P-BK-01).              |
//+------------------------------------------------------------------+
#ifndef BASE_KNOT_TOOL_MQH
#define BASE_KNOT_TOOL_MQH
#property strict

//--- session states
#define BK_IDLE    0
#define BK_ARMED   1   // menu hidden, waiting for the first corner click
#define BK_PREVIEW 2   // first corner set, rubber-band follows the cursor

//--- geometry / UX tuning
#define BK_TP_R_MULT      2.0    // TP distance = 2R (R = box height)
#define BK_PRESS_DEBOUNCE 350    // ms — one stroke per press; release of the same stroke is never debounced
#define BK_DRAG_PX        5      // px — press+release inside this radius is a click (TV corner), not a drag
#define BK_ARM_GUARD      500    // ms — ignore the arming click's own release
#define BK_BADGE_W        46
#define BK_BADGE_H        18
#define BK_DIR_LOOKBACK   128   // bars scanned for the entry-side resolve

//--- object-name tag: "<prefix>_BK_<id>_<KIND>"
#define BK_TAG "_BK_"

//--- committed-box registry (parent ↔ children share one id prefix)
struct BaseKnotBox
{
   string id;      // "<commitTFmin>_<tick>[rNNN]" (legacy: bare tick)
   int    dir;     // +1 Buy / -1 Sell — FROZEN at commit, never recomputed
   int    tfMin;   // chart Period() minutes at commit (0 = legacy = all TFs)
};
static BaseKnotBox g_bkBoxes[];
static int         g_bkState      = BK_IDLE;
static datetime    g_bkT1         = 0;
static double      g_bkP1         = 0.0;
static uint        g_bkArmedMs    = 0;
static uint        g_bkStrokeMs   = 0;
static bool        g_bkLeftPrev   = false;
static int         g_bkX1         = 0;      // press pixel — drag-vs-click threshold + 2nd-stroke drag detect
static int         g_bkY1         = 0;
static bool        g_bkDragged    = false;  // cursor left the click radius while held
static bool        g_bkWaiting    = false;  // corner 1 set by a no-drag click — hovering for corner 2 (TV-style)
static bool        g_bkInitDone   = false;
static bool        g_bkRestoreReq = false;  // UI side: re-show the menu once
static bool        g_bkTouched    = false;  // Arm ran → OnDeinit must restore chart props
static bool        g_bkScrollWas  = true;
static bool        g_bkCtxWas     = true;

//+------------------------------------------------------------------+
//| Naming: every structure shares ONE id — parent/child by suffix.  |
//| Dragging/deleting the BOX cascades to its ENTRY/SL/TP/badges.     |
//+------------------------------------------------------------------+
string BaseKnotPrefix(const string id)
{
   if(StringLen(inpObjectPrefix) == 0) return "";
   return inpObjectPrefix + BK_TAG + id + "_";
}
string BaseKnotBoxName(const string pfx)   { return pfx + "BOX"; }
string BaseKnotEntryName(const string pfx) { return pfx + "ENTRY"; }
string BaseKnotSLName(const string pfx)    { return pfx + "SL"; }
string BaseKnotTPName(const string pfx)    { return pfx + "TP"; }
string BaseKnotBuyName(const string pfx)   { return pfx + "BUY"; }
string BaseKnotDelName(const string pfx)   { return pfx + "DEL"; }
string BaseKnotInfoName(const string pfx)  { return pfx + "INFO"; }
string BaseKnotPrevName()
{
   if(StringLen(inpObjectPrefix) == 0) return "";
   return inpObjectPrefix + BK_TAG + "PREVIEW";
}
string BaseKnotHintName()
{
   if(StringLen(inpObjectPrefix) == 0) return "";
   return inpObjectPrefix + BK_TAG + "HINT";
}
string BaseKnotGV(const string id)
{
   return "Biotak_BK_" + id + "_" + GetCachedChartIdStr();
}

bool BaseKnotSessionActive() { return (g_bkState != BK_IDLE); }
int  BaseKnotCount()         { return ArraySize(g_bkBoxes); }

// UI side polls this after OnChartEventHandler to re-show the hidden menu.
bool BaseKnotTakeRestoreFlag()
{
   if(!g_bkRestoreReq) return false;
   g_bkRestoreReq = false;
   return true;
}

//+------------------------------------------------------------------+
//| Dynamic point/pip — gold, crypto, JPY and forex all covered via   |
//| the shared asset-aware cache (PerformanceOptimizations.mqh).      |
//+------------------------------------------------------------------+
double BaseKnotPipSize()
{
   double pip = GetCachedPipSize();
   if(pip <= 0) pip = GetCachedPoint();
   if(pip <= 0) pip = _Point;
   return pip;
}
double BaseKnotToPips(const double dist) { return dist / BaseKnotPipSize(); }

//+------------------------------------------------------------------+
//| Id helpers — ids are "<tfMin>_<tick>[rNNN]"; tails split at the   |
//| LAST underscore (StringFind from the right) because the id itself |
//| contains an underscore.                                           |
//+------------------------------------------------------------------+
void BaseKnotSplitTail(const string tail, string &bid, string &kind)
{
   bid = ""; kind = "";
   int last = -1, pos = 0;
   while(true)
   {
      int f = StringFind(tail, "_", pos);
      if(f < 0) break;
      last = f;
      pos = f + 1;
   }
   if(last <= 0) return;   // malformed (PREVIEW/HINT tails land here)
   bid  = StringSubstr(tail, 0, last);
   kind = StringSubstr(tail, last + 1);
}
// Commit-TF minutes encoded in the id head; 0 = legacy bare-tick id.
int BaseKnotIdTF(const string bid)
{
   int us = StringFind(bid, "_");
   if(us <= 0) return 0;
   return (int)StringToInteger(StringSubstr(bid, 0, us));
}
// Visibility mask: commit TF + every lower TF. Higher TFs stay hidden so
// a low-TF knot never renders as a hairline there (P-BK-01).
long BaseKnotTFMask(const int tfMin)
{
   if(tfMin <= 0) return OBJ_ALL_PERIODS;   // legacy box — keep old behavior
   long m = 0;
   if(tfMin >= 1)     m |= OBJ_PERIOD_M1;
   if(tfMin >= 5)     m |= OBJ_PERIOD_M5;
   if(tfMin >= 15)    m |= OBJ_PERIOD_M15;
   if(tfMin >= 30)    m |= OBJ_PERIOD_M30;
   if(tfMin >= 60)    m |= OBJ_PERIOD_H1;
   if(tfMin >= 240)   m |= OBJ_PERIOD_H4;
   if(tfMin >= 1440)  m |= OBJ_PERIOD_D1;
   if(tfMin >= 10080) m |= OBJ_PERIOD_W1;
   if(tfMin >= 43200) m |= OBJ_PERIOD_MN1;
   if(m == 0) m = OBJ_ALL_PERIODS;
   return m;
}
// Minutes compare — robust on exotic chart TFs (no flag mapping needed).
bool BaseKnotTFVisible(const int tfMin)
{
   if(tfMin <= 0) return true;
   return (Period() <= tfMin);
}

//+------------------------------------------------------------------+
//| Magnet — snap a clicked/hovered price to the nearer High/Low      |
//| shadow of its candle. Same switch + sensitivity language as the   |
//| pin magnet (inpEnableMagnet / inpMagnetSensitivityPips).          |
//+------------------------------------------------------------------+
double BaseKnotSnapPrice(const datetime t, const double price)
{
   if(!inpEnableMagnet) return price;
   if(t <= 0 || price <= 0) return price;
   int shift = iBarShift(_Symbol, 0, t, false);
   if(shift < 0) return price;
   double hi = High[shift], lo = Low[shift];
   if(hi <= 0 || lo <= 0 || hi < lo) return price;
   double dH = MathAbs(price - hi), dL = MathAbs(price - lo);
   double gate = (double)inpMagnetSensitivityPips * BaseKnotPipSize();
   if(gate <= 0) gate = BaseKnotPipSize();   // sensitivity 0 = exact touch only
   if(MathMin(dH, dL) > gate) return price;  // too far — leave the hand-drawn value
   return (dH <= dL ? hi : lo);
}

//+------------------------------------------------------------------+
//| Direction — resolved ONCE at commit, then frozen. Positional rule:|
//| price above the box = Buy, below = Sell. Price INSIDE resolves by |
//| entry side (most recent close outside: from below → Buy, from      |
//| above → Sell); mid-vs-price is the last fallback. Live ticks never|
//| call this — BaseKnotSync only reads the registry (no flicker).    |
//+------------------------------------------------------------------+
int BaseKnotResolveDirection(const double top, const double bot)
{
   double ref = iClose(_Symbol, 0, 0);
   if(ref <= 0) ref = g_currentPrice;
   if(ref > top) return 1;
   if(ref > 0 && ref < bot) return -1;
   if(ref > 0)   // inside the box (or exactly on an edge): entry side decides
   {
      for(int s = 1; s <= BK_DIR_LOOKBACK; s++)
      {
         double c = iClose(_Symbol, 0, s);
         if(c <= 0) continue;
         if(c < bot) return 1;    // rose into the box from below → demand → Buy
         if(c > top) return -1;   // fell into the box from above → supply → Sell
      }
      double mid = (top + bot) / 2.0;
      return (mid <= ref ? 1 : -1);
   }
   return 1;   // no live price at all — harmless default
}

//+------------------------------------------------------------------+
//| Registry helpers                                                  |
//+------------------------------------------------------------------+
int BaseKnotFind(const string id)
{
   for(int i = 0; i < ArraySize(g_bkBoxes); i++)
      if(g_bkBoxes[i].id == id) return i;
   return -1;
}
void BaseKnotRegister(const string id, const int dir, const int tfMin)
{
   if(BaseKnotFind(id) >= 0) return;
   int n = ArraySize(g_bkBoxes);
   ArrayResize(g_bkBoxes, n + 1);
   g_bkBoxes[n].id    = id;
   g_bkBoxes[n].dir   = (dir < 0 ? -1 : 1);
   g_bkBoxes[n].tfMin = tfMin;
   GlobalVariableSet(BaseKnotGV(id), (double)g_bkBoxes[n].dir);
}
void BaseKnotUnregister(const string id)
{
   int k = BaseKnotFind(id);
   if(k < 0) return;
   for(int i = k; i < ArraySize(g_bkBoxes) - 1; i++) g_bkBoxes[i] = g_bkBoxes[i + 1];
   ArrayResize(g_bkBoxes, ArraySize(g_bkBoxes) - 1);
   GlobalVariableDel(BaseKnotGV(id));
}
// Rebuild the registry from chart objects once (TF-switch safe: the box
// anchors ARE the spec, direction rides a chart-scoped GV, TF rides the id).
// Also purges the transient PREVIEW/HINT of a dead session (state resets on
// reload, so a reloaded indicator must never inherit a ghost rubber-band)
// and sweeps orphan direction-GVs of this chart whose boxes are gone.
void BaseKnotLazyInit()
{
   if(g_bkInitDone) return;
   g_bkInitDone = true;
   if(StringLen(inpObjectPrefix) == 0) return;
   string tag = inpObjectPrefix + BK_TAG;
   ObjectDelete(0, BaseKnotPrevName());   // dead-session transients — never inherited
   ObjectDelete(0, BaseKnotHintName());
   int total = ObjectsTotal(0, -1, -1);
   for(int i = total - 1; i >= 0; i--)
   {
      string nm = ObjectName(0, i, -1, -1);
      if(StringFind(nm, tag) != 0) continue;
      if(StringFind(nm, "BOX", StringLen(nm) - 3) < 0) continue;
      string id = StringSubstr(nm, StringLen(tag), StringLen(nm) - StringLen(tag) - 4);
      int dir = 1;
      if(GlobalVariableCheck(BaseKnotGV(id))) dir = ((int)GlobalVariableGet(BaseKnotGV(id)) < 0 ? -1 : 1);
      BaseKnotRegister(id, dir, BaseKnotIdTF(id));
   }
   // Orphan-GV sweep (this chart only — the GV carries the chart id suffix).
   string cid = GetCachedChartIdStr();
   for(int k = GlobalVariablesTotal() - 1; k >= 0; k--)
   {
      string gv = GlobalVariableName(k);
      if(StringFind(gv, "Biotak_BK_") != 0) continue;
      if(StringFind(gv, "_" + cid, StringLen(gv) - StringLen(cid) - 1) < 0) continue;
      string oid = StringSubstr(gv, 10, StringLen(gv) - 10 - StringLen(cid) - 1);
      if(BaseKnotFind(oid) < 0) GlobalVariableDel(gv);
   }
}

//+------------------------------------------------------------------+
//| Hint bar (bottom-left): what to do next. Killed on exit.          |
//+------------------------------------------------------------------+
void BaseKnotHintShow(const string text)
{
   string hn = BaseKnotHintName();
   if(hn == "") return;
   if(ObjectFind(0, hn) < 0) ObjectCreate(0, hn, OBJ_LABEL, 0, 0, 0);
   ObjectSetInteger(0, hn, OBJPROP_CORNER, CORNER_LEFT_LOWER);
   ObjectSetInteger(0, hn, OBJPROP_XDISTANCE, 10);
   ObjectSetInteger(0, hn, OBJPROP_YDISTANCE, 44);
   ObjectSetString(0, hn, OBJPROP_TEXT, text);
   ObjectSetString(0, hn, OBJPROP_FONT, "Arial");
   ObjectSetInteger(0, hn, OBJPROP_FONTSIZE, 9);
   ObjectSetInteger(0, hn, OBJPROP_COLOR, C'255,171,0');
   ObjectSetInteger(0, hn, OBJPROP_ANCHOR, ANCHOR_LEFT_LOWER);
   ObjectSetInteger(0, hn, OBJPROP_BACK, false);
   ObjectSetInteger(0, hn, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, hn, OBJPROP_HIDDEN, true);
   ObjectSetInteger(0, hn, OBJPROP_ZORDER, 1500);
   ChartRedraw();
}
void BaseKnotHintHide()
{
   ObjectDelete(0, BaseKnotHintName());
   ChartRedraw();
}

//+------------------------------------------------------------------+
//| Arm / cancel — called from the Tools-ring click (menu side hides  |
//| the ring first). Raw Chart* scroll lock: no menu dependency, so   |
//| Lite compiles and keeps working on committed boxes.               |
//+------------------------------------------------------------------+
void BaseKnotArm()
{
   BaseKnotLazyInit();
   g_bkState   = BK_ARMED;
   g_bkTouched = true;   // OnDeinit must restore the chart props below, whatever happens
   g_bkArmedMs = GetTickCount();
   g_bkLeftPrev = false;   // OBJECT_CLICK fires on release — the button is UP now; the next rising edge is stroke 1
   g_bkDragged = false;
   g_bkWaiting = false;
   g_bkX1 = 0; g_bkY1 = 0;
   g_bkScrollWas = (ChartGetInteger(0, CHART_MOUSE_SCROLL) != 0);
   g_bkCtxWas    = (ChartGetInteger(0, CHART_CONTEXT_MENU) != 0);
   ChartSetInteger(0, CHART_MOUSE_SCROLL, false);   // no chart slide under the hand while drawing
   ChartSetInteger(0, CHART_CONTEXT_MENU, false);
   ObjectDelete(0, BaseKnotPrevName());
   BaseKnotHintShow("BASE TOOL — drag a box (release = commit) · or click 2 corners · right-click / ESC: done");
   ChartRedraw();
}
void BaseKnotCancel()
{
   ObjectDelete(0, BaseKnotPrevName());
   BaseKnotHintHide();
   g_bkState = BK_IDLE;
   ChartSetInteger(0, CHART_MOUSE_SCROLL, g_bkScrollWas);
   ChartSetInteger(0, CHART_CONTEXT_MENU, g_bkCtxWas);
   g_bkRestoreReq = true;   // UI side re-shows the hidden ring menu
   ChartRedraw();
}

// Deinit safety (call from OnDeinitHandler, every reason): a remove /
// TF-switch / crash-reload mid-session must never leave the chart scroll
// locked, a ghost rubber-band behind, or a stale restore flag. Committed
// boxes are the independent layer and stay untouched here (REMOVE wipes
// them via DeleteAllIndicatorObjects(true) + the Biotak_BK_* GV sweep).
void BaseKnotOnDeinit(const int reason)
{
   if(g_bkTouched)
   {
      ChartSetInteger(0, CHART_MOUSE_SCROLL, g_bkScrollWas);
      ChartSetInteger(0, CHART_CONTEXT_MENU, g_bkCtxWas);
      g_bkTouched = false;
   }
   g_bkState = BK_IDLE;
   g_bkRestoreReq = false;
   ObjectDelete(0, BaseKnotPrevName());
   ObjectDelete(0, BaseKnotHintName());
   if(reason == REASON_REMOVE) ArrayResize(g_bkBoxes, 0);
}

//+------------------------------------------------------------------+
//| Children geometry — single source of truth for commit / drag-sync.|
//| Buy: Entry=top, SL=bottom, TP=top+2R. Sell mirrored.              |
//+------------------------------------------------------------------+
void BaseKnotCalcLevels(const double top, const double bot, const int dir,
                        double &entry, double &sl, double &tp)
{
   double h = top - bot;
   if(dir >= 0) { entry = top; sl = bot; tp = top + h * BK_TP_R_MULT; }
   else         { entry = bot; sl = top; tp = bot - h * BK_TP_R_MULT; }
}
void BaseKnotMakeRay(const string name, const datetime t2, const datetime t1,
                     const double level, const color clr, const int style, const int width,
                     const string tooltip, const long tfMask)
{
   if(ObjectFind(0, name) < 0) ObjectCreate(0, name, OBJ_TREND, 0, t2, level, t2, level);
   datetime tFar = t2 + (t2 > t1 ? (t2 - t1) : PeriodSeconds());
   ObjectMove(0, name, 0, t2, level);
   ObjectMove(0, name, 1, tFar, level);   // horizontal — ray-right projects it forward
   ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
   ObjectSetInteger(0, name, OBJPROP_STYLE, style);
   ObjectSetInteger(0, name, OBJPROP_WIDTH, width);
   ObjectSetInteger(0, name, OBJPROP_RAY_RIGHT, true);
   ObjectSetInteger(0, name, OBJPROP_RAY_LEFT, false);
   ObjectSetInteger(0, name, OBJPROP_TIMEFRAMES, tfMask);   // TF-scoped with the box
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);  // the BOX is the only handle
   ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
   ObjectSetInteger(0, name, OBJPROP_BACK, true);
   ObjectSetInteger(0, name, OBJPROP_ZORDER, 50);
   ObjectSetString(0, name, OBJPROP_TOOLTIP, tooltip);
}
void BaseKnotMakeBadge(const string name, const string text, const color bg)
{
   if(ObjectFind(0, name) < 0) ObjectCreate(0, name, OBJ_BUTTON, 0, 0, 0);
   ObjectSetInteger(0, name, OBJPROP_XSIZE, BK_BADGE_W);
   ObjectSetInteger(0, name, OBJPROP_YSIZE, BK_BADGE_H);
   ObjectSetString(0, name, OBJPROP_TEXT, text);
   ObjectSetString(0, name, OBJPROP_FONT, "Arial Bold");
   ObjectSetInteger(0, name, OBJPROP_FONTSIZE, 8);
   ObjectSetInteger(0, name, OBJPROP_COLOR, clrWhite);
   ObjectSetInteger(0, name, OBJPROP_BGCOLOR, bg);
   ObjectSetInteger(0, name, OBJPROP_BORDER_COLOR, C'18,22,33');
   ObjectSetInteger(0, name, OBJPROP_BACK, false);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
   ObjectSetInteger(0, name, OBJPROP_ZORDER, 1600);
   ObjectSetInteger(0, name, OBJPROP_STATE, false);
}
// Pixel X badge is screen-anchored: re-glued after every drag / scroll /
// zoom / TF-switch; the INFO text is chart-anchored and only TF-gated.
// TF-hidden boxes stay hidden here even when their corner is on-screen.
void BaseKnotPlaceBadges(const string pfx, const datetime t1, const datetime t2,
                         const double top, const int tfMin)
{
   bool tfVis = BaseKnotTFVisible(tfMin);
   int x2 = 0, y2 = 0;
   bool vis = (tfVis && ChartTimePriceToXY(0, 0, t2, top, x2, y2));
   string dn = BaseKnotDelName(pfx), in = BaseKnotInfoName(pfx);
   ObjectSetInteger(0, dn, OBJPROP_TIMEFRAMES, (vis ? OBJ_ALL_PERIODS : OBJ_NO_PERIODS));
   ObjectSetInteger(0, in, OBJPROP_TIMEFRAMES, (tfVis ? OBJ_ALL_PERIODS : OBJ_NO_PERIODS));
   if(!vis) return;
   ObjectSetInteger(0, dn, OBJPROP_XDISTANCE, x2 + 2);
   ObjectSetInteger(0, dn, OBJPROP_YDISTANCE, y2 - BK_BADGE_H - 4);
   ObjectSetInteger(0, in, OBJPROP_TIME, 0, t2);
   ObjectSetDouble(0, in, OBJPROP_PRICE, 0, top);
}
// (Re)build every child of one box from its live anchors. Direction is read
// from the registry — NEVER recomputed here (frozen at commit, no flicker).
void BaseKnotSync(const string id)
{
   int k = BaseKnotFind(id);
   if(k < 0) return;
   string pfx = BaseKnotPrefix(id);
   if(pfx == "") return;
   string box = BaseKnotBoxName(pfx);
   if(ObjectFind(0, box) < 0) return;
   datetime t1 = (datetime)ObjectGetInteger(0, box, OBJPROP_TIME, 0);
   datetime t2 = (datetime)ObjectGetInteger(0, box, OBJPROP_TIME, 1);
   double p1 = ObjectGetDouble(0, box, OBJPROP_PRICE, 0);
   double p2 = ObjectGetDouble(0, box, OBJPROP_PRICE, 1);
   if(t2 < t1) { datetime tt = t1; t1 = t2; t2 = tt; }
   double top = MathMax(p1, p2), bot = MathMin(p1, p2);
   int dir = g_bkBoxes[k].dir;
   int tfMin = g_bkBoxes[k].tfMin;
   if(tfMin <= 0) tfMin = BaseKnotIdTF(id);   // legacy registry rows
   long tfMask = BaseKnotTFMask(tfMin);
   ObjectSetInteger(0, box, OBJPROP_TIMEFRAMES, tfMask);
   double entry = 0, sl = 0, tp = 0;
   BaseKnotCalcLevels(top, bot, dir, entry, sl, tp);
   double hPips  = BaseKnotToPips(top - bot);
   double tpPips = BaseKnotToPips(MathAbs(tp - entry));
   double rr     = (hPips > 0 ? tpPips / hPips : BK_TP_R_MULT);
   int dg = GetCachedDigits();
   string side = (dir >= 0 ? "BUY" : "SELL");
   BaseKnotMakeRay(BaseKnotEntryName(pfx), t2, t1, entry, C'30,144,255', STYLE_SOLID, 1,
                   "BK " + side + " Entry: " + DoubleToString(entry, dg), tfMask);
   BaseKnotMakeRay(BaseKnotSLName(pfx), t2, t1, sl, C'220,50,50', STYLE_DASH, 1,
                   "BK " + side + " Stop: " + DoubleToString(sl, dg) + " (" + DoubleToString(hPips, 1) + " pips)", tfMask);
   BaseKnotMakeRay(BaseKnotTPName(pfx), t2, t1, tp, C'46,139,87', STYLE_DASH, 1,
                   "BK " + side + " Target: " + DoubleToString(tp, dg) + " (+" + DoubleToString(tpPips, 1) + " pips, R:R 1:" + DoubleToString(rr, 0) + ")", tfMask);
   BaseKnotMakeBadge(BaseKnotDelName(pfx), "X", C'90,95,105');
   ObjectSetString(0, BaseKnotDelName(pfx), OBJPROP_TOOLTIP, "Delete this base + its lines");
   ObjectDelete(0, BaseKnotBuyName(pfx));   // NOBUYSELL: purge pre-2026-09-06 direction badges
   string in = BaseKnotInfoName(pfx);
   if(ObjectFind(0, in) < 0) ObjectCreate(0, in, OBJ_TEXT, 0, t2, top);
   ObjectSetString(0, in, OBJPROP_TEXT,
                   "[" + DoubleToString(hPips, 1) + " Pips | R:R 1:" + DoubleToString(rr, 0) + "]");
   ObjectSetString(0, in, OBJPROP_FONT, "Arial");
   ObjectSetInteger(0, in, OBJPROP_FONTSIZE, 8);
   ObjectSetInteger(0, in, OBJPROP_COLOR, C'255,171,0');
   ObjectSetInteger(0, in, OBJPROP_ANCHOR, ANCHOR_LEFT_LOWER);
   ObjectSetInteger(0, in, OBJPROP_BACK, false);
   ObjectSetInteger(0, in, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, in, OBJPROP_HIDDEN, true);
   ObjectSetInteger(0, in, OBJPROP_ZORDER, 60);
   ObjectSetString(0, in, OBJPROP_TOOLTIP, "BK " + side + ": risk " + DoubleToString(hPips, 1) +
                   " pips, target +" + DoubleToString(tpPips, 1) + " pips");
   BaseKnotPlaceBadges(pfx, t1, t2, top, tfMin);
}
void BaseKnotDelete(const string id)
{
   string pfx = BaseKnotPrefix(id);
   if(pfx != "") ObjectsDeleteAll(0, pfx);   // one call wipes box + all children
   BaseKnotUnregister(id);
   ChartRedraw();
}
// Per-tick (500 ms) re-glue: scroll/zoom moves pixel badges, box anchors don't.
void BaseKnotSyncBadges()
{
   if(ArraySize(g_bkBoxes) == 0) return;
   for(int i = 0; i < ArraySize(g_bkBoxes); i++)
   {
      string pfx = BaseKnotPrefix(g_bkBoxes[i].id);
      if(pfx == "") continue;
      string box = BaseKnotBoxName(pfx);
      if(ObjectFind(0, box) < 0) continue;
      datetime t1 = (datetime)ObjectGetInteger(0, box, OBJPROP_TIME, 0);
      datetime t2 = (datetime)ObjectGetInteger(0, box, OBJPROP_TIME, 1);
      if(t2 < t1) { datetime tt = t1; t1 = t2; t2 = tt; }
      double top = MathMax(ObjectGetDouble(0, box, OBJPROP_PRICE, 0),
                           ObjectGetDouble(0, box, OBJPROP_PRICE, 1));
      int tfMin = g_bkBoxes[i].tfMin;
      if(tfMin <= 0) tfMin = BaseKnotIdTF(g_bkBoxes[i].id);
      BaseKnotPlaceBadges(pfx, t1, t2, top, tfMin);
   }
}

//+------------------------------------------------------------------+
//| Press (stroke start) → freeze corner 1, raise the rubber-band.     |
//| Release (stroke end) → Meta path (dragged): commit at release;     |
//| TV path (no drag): keep corner 1 and hover for corner 2 — the 2nd  |
//| stroke (click or drag-release) commits. Degenerate commits are     |
//| rejected without losing a waiting corner.                          |
//+------------------------------------------------------------------+
bool BaseKnotCommit(const datetime t2, const double p2raw)
{
   double pt = GetCachedPoint();
   if(pt <= 0) pt = _Point;
   double p2 = BaseKnotSnapPrice(t2, p2raw);
   if(t2 == g_bkT1 || MathAbs(p2 - g_bkP1) < pt) return false;  // degenerate — no box
   int tfMin = Period();
   string id = IntegerToString((long)tfMin) + "_" + IntegerToString((long)GetTickCount());
   while(BaseKnotFind(id) >= 0) id += "r" + IntegerToString(MathRand() % 1000);
   string pfx = BaseKnotPrefix(id);
   if(pfx == "") return false;
   string box = BaseKnotBoxName(pfx);
   if(!ObjectCreate(0, box, OBJ_RECTANGLE, 0, g_bkT1, g_bkP1, t2, p2)) return false;
   ObjectSetInteger(0, box, OBJPROP_COLOR, C'255,171,0');
   ObjectSetInteger(0, box, OBJPROP_STYLE, STYLE_SOLID);
   ObjectSetInteger(0, box, OBJPROP_WIDTH, 1);
   ObjectSetInteger(0, box, OBJPROP_FILL, false);   // unfilled: candles stay visible (MQL4 has no alpha)
   ObjectSetInteger(0, box, OBJPROP_BACK, true);
   ObjectSetInteger(0, box, OBJPROP_SELECTABLE, true);   // THE handle: drag moves children
   ObjectSetInteger(0, box, OBJPROP_HIDDEN, true);
   ObjectSetInteger(0, box, OBJPROP_ZORDER, 55);
   ObjectSetInteger(0, box, OBJPROP_TIMEFRAMES, BaseKnotTFMask(tfMin));
   ObjectSetString(0, box, OBJPROP_TOOLTIP, "Base box — drag to move (lines follow) · X removes all");
   // Direction is AUTOMATIC and FROZEN here (no Buy/Sell badge): box below
   // the live price = demand = Buy; box above it = supply = Sell; a commit
   // landing with the price inside resolves by entry side (see resolver).
   double bkTop = MathMax(g_bkP1, p2), bkBot = MathMin(g_bkP1, p2);
   int dir = BaseKnotResolveDirection(bkTop, bkBot);
   BaseKnotRegister(id, dir, tfMin);
   BaseKnotSync(id);
   ObjectDelete(0, BaseKnotPrevName());
   g_bkState = BK_ARMED;   // stay armed — multi-draw until ESC/right-click (both natives keep the tool active)
   g_bkWaiting = false;
   g_bkDragged = false;
   double hPips = BaseKnotToPips(MathAbs(p2 - g_bkP1));
   BaseKnotHintShow("BASE #" + IntegerToString(ArraySize(g_bkBoxes)) + " " +
                    (dir >= 0 ? "BUY" : "SELL") + " set (" +
                    DoubleToString(hPips, 1) + " pips) — next box: drag or 2 clicks · done: right-click / ESC");
   ChartRedraw();
   return true;
}

// Press = stroke start (rising edge, or CLICK fallback when the edge was
// dropped). First press freezes corner 1; a press while waiting for corner 2
// only starts the drag detector — corner 1 is NEVER overwritten. One stroke
// per press — duplicates share the stroke debounce. The release that ends
// THIS stroke is never debounced (fast drags commit).
void BaseKnotPress(const int mx, const int my, const datetime t, const double praw)
{
   if(g_bkState == BK_PREVIEW && g_bkWaiting)
   {
      // Second stroke of a TV-style corner pair: track its drag, keep corner 1.
      uint now2 = GetTickCount();
      if(now2 - g_bkStrokeMs < BK_PRESS_DEBOUNCE) return;
      g_bkStrokeMs = now2;
      g_bkX1 = mx; g_bkY1 = my;
      g_bkDragged = false;
      return;
   }
   if(g_bkState != BK_ARMED) return;
   uint now = GetTickCount();
   if(now - g_bkArmedMs < BK_ARM_GUARD) return;      // the tool button's own click still settling
   if(now - g_bkStrokeMs < BK_PRESS_DEBOUNCE) return;
   g_bkStrokeMs = now;
   double p = BaseKnotSnapPrice(t, praw);
   g_bkT1 = t; g_bkP1 = p;
   g_bkX1 = mx; g_bkY1 = my;
   g_bkDragged = false;
   g_bkWaiting = false;
   g_bkState = BK_PREVIEW;
   string pv = BaseKnotPrevName();
   if(pv == "") return;
   if(ObjectFind(0, pv) < 0) ObjectCreate(0, pv, OBJ_RECTANGLE, 0, t, p, t, p);
   ObjectSetInteger(0, pv, OBJPROP_COLOR, C'255,171,0');
   ObjectSetInteger(0, pv, OBJPROP_STYLE, STYLE_DOT);
   ObjectSetInteger(0, pv, OBJPROP_WIDTH, 1);
   ObjectSetInteger(0, pv, OBJPROP_FILL, false);
   ObjectSetInteger(0, pv, OBJPROP_BACK, true);
   ObjectSetInteger(0, pv, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, pv, OBJPROP_HIDDEN, true);
   ChartRedraw();
}
// Pixel drag detector — shared by the held-drag and the 2nd-stroke paths.
void BaseKnotNoteMove(const int mx, const int my)
{
   if(g_bkState != BK_PREVIEW) return;
   if(MathAbs(mx - g_bkX1) >= BK_DRAG_PX || MathAbs(my - g_bkY1) >= BK_DRAG_PX)
      g_bkDragged = true;
}
// Release = stroke end (falling edge, or CLICK fallback). Stamps the stroke
// clock first so the trailing CLICK of a normal drag is swallowed by the
// press debounce in BaseKnotPress.
void BaseKnotRelease(const int mx, const int my, const datetime t, const double praw)
{
   if(g_bkState != BK_PREVIEW) return;
   BaseKnotNoteMove(mx, my);
   g_bkStrokeMs = GetTickCount();
   if(!g_bkWaiting && !g_bkDragged)
   {
      // TV-style first corner: a clean click with no drag — keep it and hover
      // for corner 2 instead of melting (Meta drags never take this branch:
      // they arrive dragged=true and commit below).
      g_bkWaiting = true;
      g_bkX1 = mx; g_bkY1 = my;   // 2nd-stroke drag is measured from here
      BaseKnotHintShow("BASE — corner 1 set · click corner 2 (or drag) · ESC: cancel");
      ChartRedraw();
      return;
   }
   if(BaseKnotCommit(t, praw)) return;   // committed → ARMED, hint shows the BUY/SELL
   if(g_bkWaiting)
   {
      // Degenerate 2nd corner (same bar / zero height): keep waiting, corner 1 intact.
      g_bkX1 = mx; g_bkY1 = my;
      g_bkDragged = false;
      ChartRedraw();
      return;
   }
   // Dragged but degenerate (released inside one bar / zero height): melt the
   // stroke like the native tool and stay armed for the next box.
   ObjectDelete(0, BaseKnotPrevName());
   g_bkState = BK_ARMED;
   g_bkDragged = false;
   BaseKnotHintShow("BASE TOOL — drag a box (release = commit) · or click 2 corners · right-click / ESC: done");
   ChartRedraw();
}

//+------------------------------------------------------------------+
//| Master event entry — call FIRST in OnChartEventHandler; true =    |
//| consumed (caller must return immediately, no chart-click leak).   |
//+------------------------------------------------------------------+
bool BaseKnotOnChartEvent(const int id, const long &lparam, const double &dparam, const string &sparam)
{
   BaseKnotLazyInit();
   string tag = (StringLen(inpObjectPrefix) > 0 ? inpObjectPrefix + BK_TAG : "");

   //--- quick-delete badge (any state, incl. IDLE). Direction is automatic
   //--- (box below live price = Buy, above = Sell) — no Buy/Sell badge.
   if(id == CHARTEVENT_OBJECT_CLICK && tag != "")
   {
      if(StringFind(sparam, tag) == 0)
      {
         string tail = StringSubstr(sparam, StringLen(tag));
         string bid = "", kind = "";
         BaseKnotSplitTail(tail, bid, kind);   // LAST underscore: ids hold one too
         if(kind == "DEL")
         {
            int k = BaseKnotFind(bid);
            BaseKnotDelete(bid);   // unknown id → still wipe by prefix
            if(k < 0 && tag != "")
            {
               ObjectsDeleteAll(0, tag + bid + "_");
               ChartRedraw();
            }
            return true;
         }
         if(kind == "BUY") { ObjectDelete(0, sparam); return true; }   // NOBUYSELL leftover
         if(kind == "") return true;   // PREVIEW/HINT tails — swallow, no action
         return true;   // clicks on box/lines/info text die here — never reach menus
      }
   }

   //--- box drag → children follow; box delete → cascade; child delete → heal
   if(id == CHARTEVENT_OBJECT_DRAG && tag != "" && StringFind(sparam, tag) == 0 &&
      StringFind(sparam, "BOX", StringLen(sparam) - 3) >= 0)
   {
      string tail = StringSubstr(sparam, StringLen(tag));
      string bid = StringSubstr(tail, 0, StringLen(tail) - 4);
      if(bid == "PREVIEW") return true;
      if(BaseKnotFind(bid) >= 0) { BaseKnotSync(bid); ChartRedraw(); }
      return true;
   }
   if(id == CHARTEVENT_OBJECT_DELETE && tag != "" && StringFind(sparam, tag) == 0)
   {
      // Only the BOX triggers the cascade (children deletes re-enter as no-ops).
      if(StringFind(sparam, "BOX", StringLen(sparam) - 3) >= 0)
      {
         string tail = StringSubstr(sparam, StringLen(tag));
         string bid = StringSubstr(tail, 0, StringLen(tail) - 4);
         if(bid == "PREVIEW" || bid == "HINT") return true;
         BaseKnotDelete(StringSubstr(tail, 0, StringLen(tail) - 4));
      }
      else
      {
         // A manually deleted child (ENTRY/SL/TP/INFO/DEL) self-heals via
         // re-sync; trailing deletes of an already-gone box just mop up.
         string tail = StringSubstr(sparam, StringLen(tag));
         string bid = "", kind = "";
         BaseKnotSplitTail(tail, bid, kind);
         if(kind == "") return true;   // PREVIEW/HINT transient — swallow
         if(BaseKnotFind(bid) >= 0)
         {
            string pfx = BaseKnotPrefix(bid);
            if(ObjectFind(0, BaseKnotBoxName(pfx)) >= 0) BaseKnotSync(bid);
            else BaseKnotDelete(bid);
            ChartRedraw();
         }
         else if(bid != "")
         {
            // Trailing delete of an already-removed box (or a half-built
            // orphan): mop up by prefix, no redraw — the BOX branch redraws.
            ObjectsDeleteAll(0, BaseKnotPrefix(bid));
         }
      }
      return true;
   }

   //--- view moved under pixel badges → re-glue (never consumed)
   if(id == CHARTEVENT_CHART_CHANGE) { BaseKnotSyncBadges(); return false; }

   //--- ESC leaves the session from anywhere
   if(id == CHARTEVENT_KEYDOWN && lparam == 27 && BaseKnotSessionActive())
   {
      BaseKnotCancel();
      return true;
   }

   if(!BaseKnotSessionActive()) return false;

   //--- right-click cancels (both encodings MT4 uses)
   if(id == CHARTEVENT_MOUSE_MOVE)
   {
      int st = (int)StringToInteger(sparam);
      if((st & 2) != 0) { BaseKnotCancel(); return true; }
   }
   if(id == CHARTEVENT_CLICK && StringFind(sparam, "r") >= 0) { BaseKnotCancel(); return true; }

   //--- Hybrid stroke (both natives, researched 2026-09-06): a held
   //--- press-drag-release commits on release (MT4 Insert → Shapes →
   //--- Rectangle); a click-move-click pair commits on the 2nd click
   //--- (TradingView Rectangle) — no CLICK latency on either path.
   if(id == CHARTEVENT_MOUSE_MOVE)
   {
      int st = (int)StringToInteger(sparam);
      bool left = ((st & 1) != 0);
      bool rising  = (left && !g_bkLeftPrev);
      bool falling = (!left && g_bkLeftPrev);
      g_bkLeftPrev = left;
      int mx = (int)lparam, my = (int)dparam;
      if(rising && (g_bkState == BK_ARMED || g_bkState == BK_PREVIEW))
      {
         int sw = 0; datetime ct = 0; double cp = 0;
         if(ChartXYToTimePrice(0, mx, my, sw, ct, cp) && sw == 0 && ct > 0 && cp > 0)
            BaseKnotPress(mx, my, ct, cp);
         return true;
      }
      if(falling && g_bkState == BK_PREVIEW)
      {
         int sw = 0; datetime ct = 0; double cp = 0;
         if(ChartXYToTimePrice(0, mx, my, sw, ct, cp) && sw == 0 && ct > 0 && cp > 0)
            BaseKnotRelease(mx, my, ct, cp);
         else if(!g_bkWaiting)
         {
            // Released off-chart mid-drag: melt the stroke, stay armed.
            g_bkStrokeMs = GetTickCount();
            ObjectDelete(0, BaseKnotPrevName());
            g_bkState = BK_ARMED;
            g_bkDragged = false;
            ChartRedraw();
         }
         // Off-chart release while waiting: keep corner 1, ignore the edge.
         return true;
      }
      //--- rubber-band: live preview follows the held drag (Meta) AND the
      //--- button-up hover while waiting for corner 2 (TV) — WYSIWYG in both.
      //--- throttled: a mouse-move storm must never pin the CPU (30 ms ≈ 33 fps).
      if(g_bkState == BK_PREVIEW && (left || g_bkWaiting))
      {
         BaseKnotNoteMove(mx, my);
         static uint s_bkRubberMs = 0;
         uint nowR = GetTickCount();
         if(nowR - s_bkRubberMs < 30) return true;   // swallow, skip the redraw
         s_bkRubberMs = nowR;
         int sw = 0; datetime ht = 0; double hp = 0;
         string pv = BaseKnotPrevName();
         if(pv != "" && ChartXYToTimePrice(0, mx, my, sw, ht, hp) && sw == 0 && ht > 0 && hp > 0)
         {
            hp = BaseKnotSnapPrice(ht, hp);   // preview shows the snapped corner (WYSIWYG)
            ObjectMove(0, pv, 0, g_bkT1, g_bkP1);
            ObjectMove(0, pv, 1, ht, hp);
            ChartRedraw();
         }
         return true;
      }
      return (g_bkState == BK_PREVIEW);   // swallow moves mid-gesture, ignore idle hovers
   }

   //--- CLICK fallback (some builds/mice emit no clean press/release edge:
   //--- ARMED+CLICK = missed press, waiting+CLICK = missed 2nd corner).
   //--- A CLICK pair draws a TV-style box with no MOUSE_MOVE at all; in a
   //--- normal drag the trailing CLICK is swallowed by the stroke debounce
   //--- stamped at release, so it can never double-commit.
   if(id == CHARTEVENT_CLICK)
   {
      int mx = (int)lparam, my = (int)dparam;
      int sw = 0; datetime ct = 0; double cp = 0;
      if(ChartXYToTimePrice(0, mx, my, sw, ct, cp) && sw == 0 && ct > 0 && cp > 0)
      {
         if(g_bkState == BK_ARMED) { BaseKnotPress(mx, my, ct, cp); BaseKnotRelease(mx, my, ct, cp); }
         else BaseKnotRelease(mx, my, ct, cp);
      }
      return true;
   }

   return false;
}

#endif // BASE_KNOT_TOOL_MQH
