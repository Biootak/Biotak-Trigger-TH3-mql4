//+------------------------------------------------------------------+
//|                                              BaseKnotTool.mqh    |
//|        Base / Knot Measurement Tool — TradingView-style two-click |
//|        base-box drawer with Entry / SL / TP projections.          |
//+------------------------------------------------------------------+
//| LAYER: drawing/domain (no UI deps — compiles in Full AND Lite).   |
//| The Tools-ring button, menu hide/restore and chart-lock watchdog  |
//| hooks live on the UI side (BiotakMenu/BiotakPanels) and call into |
//| this module. Chart scroll is locked directly here (raw Chart*      |
//| calls) so Lite — which has no menu — keeps drag/delete working.   |
//|                                                                   |
//| STATE MACHINE (the ONLY mouse-event consumer while active):       |
//|   BK_IDLE →(Tools click)→ BK_ARMED →(click 1)→ BK_PREVIEW          |
//|   BK_PREVIEW →(move)→ rubber-band →(click 2)→ commit → BK_ARMED    |
//|   (stays armed for the next box; ESC / right-click / orb → IDLE). |
//| While BK_ARMED/BK_PREVIEW, BaseKnotOnChartEvent() returns true for |
//| consumed events so OnChartEventHandler returns early and nothing   |
//| else (custom-price, TH3, panels) sees the gesture.                 |
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
#define BK_CLICK_DEBOUNCE 350    // ms — shared by CLICK + MOUSE_MOVE paths
#define BK_ARM_GUARD      500    // ms — ignore the arming click's own release
#define BK_BADGE_W        46
#define BK_BADGE_H        18

//--- committed-box registry (parent ↔ children share one id prefix)
struct BaseKnotBox
{
   string id;   // unique per box (tick-count at commit)
   int    dir;  // +1 Buy / -1 Sell
};
static BaseKnotBox g_bkBoxes[];
static int         g_bkState      = BK_IDLE;
static datetime    g_bkT1         = 0;
static double      g_bkP1         = 0.0;
static uint        g_bkArmedMs    = 0;
static uint        g_bkLastClick  = 0;
static bool        g_bkLeftPrev   = false;
static bool        g_bkInitDone   = false;
static bool        g_bkRestoreReq = false;  // UI side: re-show the menu once
static bool        g_bkScrollWas  = true;
static bool        g_bkCtxWas     = true;

//+------------------------------------------------------------------+
//| Naming: every structure shares ONE id — parent/child by suffix.  |
//| Dragging/deleting the BOX cascades to its ENTRY/SL/TP/badges.     |
//+------------------------------------------------------------------+
string BaseKnotPrefix(const string id)
{
   if(StringLen(inpObjectPrefix) == 0) return "";
   return inpObjectPrefix + "_BK_" + id + "_";
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
   return inpObjectPrefix + "_BK_PREVIEW";
}
string BaseKnotHintName()
{
   if(StringLen(inpObjectPrefix) == 0) return "";
   return inpObjectPrefix + "_BK_HINT";
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
//| Registry helpers                                                  |
//+------------------------------------------------------------------+
int BaseKnotFind(const string id)
{
   for(int i = 0; i < ArraySize(g_bkBoxes); i++)
      if(g_bkBoxes[i].id == id) return i;
   return -1;
}
void BaseKnotRegister(const string id, const int dir)
{
   if(BaseKnotFind(id) >= 0) return;
   int n = ArraySize(g_bkBoxes);
   ArrayResize(g_bkBoxes, n + 1);
   g_bkBoxes[n].id  = id;
   g_bkBoxes[n].dir = dir;
   GlobalVariableSet(BaseKnotGV(id), (double)dir);
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
// anchors ARE the spec, direction rides a chart-scoped GV).
void BaseKnotLazyInit()
{
   if(g_bkInitDone) return;
   g_bkInitDone = true;
   if(StringLen(inpObjectPrefix) == 0) return;
   string tag = inpObjectPrefix + "_BK_";
   int total = ObjectsTotal(0, -1, -1);
   for(int i = total - 1; i >= 0; i--)
   {
      string nm = ObjectName(0, i, -1, -1);
      if(StringFind(nm, tag) != 0) continue;
      if(StringFind(nm, "BOX", StringLen(nm) - 3) < 0) continue;
      string id = StringSubstr(nm, StringLen(tag), StringLen(nm) - StringLen(tag) - 4);
      int dir = 1;
      if(GlobalVariableCheck(BaseKnotGV(id))) dir = ((int)GlobalVariableGet(BaseKnotGV(id)) < 0 ? -1 : 1);
      BaseKnotRegister(id, dir);
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
   g_bkArmedMs = GetTickCount();
   g_bkLeftPrev = true;   // the arming press is still down — never take its release as click 1
   g_bkScrollWas = (ChartGetInteger(0, CHART_MOUSE_SCROLL) != 0);
   g_bkCtxWas    = (ChartGetInteger(0, CHART_CONTEXT_MENU) != 0);
   ChartSetInteger(0, CHART_MOUSE_SCROLL, false);   // no chart slide under the hand while drawing
   ChartSetInteger(0, CHART_CONTEXT_MENU, false);
   ObjectDelete(0, BaseKnotPrevName());
   BaseKnotHintShow("BASE TOOL — click 1: box corner · click 2: commit · right-click / ESC: done");
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

//+------------------------------------------------------------------+
//| Children geometry — single source of truth for commit / toggle /  |
//| drag-sync. Buy: Entry=top, SL=bottom, TP=top+2R. Sell mirrored.   |
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
                     const string tooltip)
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
// Pixel badges are screen-anchored: re-glue them to the box after every
// drag / scroll / zoom / TF-switch. Hidden while the box is off-view.
void BaseKnotPlaceBadges(const string pfx, const datetime t1, const datetime t2, const double top)
{
   int x1 = 0, y1 = 0, x2 = 0, y2 = 0;
   bool vis = ChartTimePriceToXY(0, 0, t1, top, x1, y1) &&
              ChartTimePriceToXY(0, 0, t2, top, x2, y2);
   string bn = BaseKnotBuyName(pfx), dn = BaseKnotDelName(pfx), in = BaseKnotInfoName(pfx);
   long show = (vis ? OBJ_ALL_PERIODS : OBJ_NO_PERIODS);
   ObjectSetInteger(0, bn, OBJPROP_TIMEFRAMES, show);
   ObjectSetInteger(0, dn, OBJPROP_TIMEFRAMES, show);
   ObjectSetInteger(0, in, OBJPROP_TIMEFRAMES, show);
   if(!vis) return;
   ObjectSetInteger(0, bn, OBJPROP_XDISTANCE, x1 - BK_BADGE_W - 2);
   ObjectSetInteger(0, bn, OBJPROP_YDISTANCE, y1 - BK_BADGE_H - 4);
   ObjectSetInteger(0, dn, OBJPROP_XDISTANCE, x2 + 2);
   ObjectSetInteger(0, dn, OBJPROP_YDISTANCE, y2 - BK_BADGE_H - 4);
   ObjectSetInteger(0, in, OBJPROP_TIME, 0, t2);
   ObjectSetDouble(0, in, OBJPROP_PRICE, 0, top);
}
// (Re)build every child of one box from its live anchors.
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
   double entry = 0, sl = 0, tp = 0;
   BaseKnotCalcLevels(top, bot, dir, entry, sl, tp);
   double hPips  = BaseKnotToPips(top - bot);
   double tpPips = BaseKnotToPips(MathAbs(tp - entry));
   int dg = GetCachedDigits();
   BaseKnotMakeRay(BaseKnotEntryName(pfx), t2, t1, entry, C'30,144,255', STYLE_SOLID, 1,
                   "BK Entry: " + DoubleToString(entry, dg));
   BaseKnotMakeRay(BaseKnotSLName(pfx), t2, t1, sl, C'220,50,50', STYLE_DASH, 1,
                   "BK Stop: " + DoubleToString(sl, dg) + " (" + DoubleToString(hPips, 1) + " pips)");
   BaseKnotMakeRay(BaseKnotTPName(pfx), t2, t1, tp, C'46,139,87', STYLE_DASH, 1,
                   "BK Target: " + DoubleToString(tp, dg) + " (+" + DoubleToString(tpPips, 1) + " pips, 2R)");
   BaseKnotMakeBadge(BaseKnotBuyName(pfx), (dir >= 0 ? "BUY" : "SELL"), (dir >= 0 ? C'30,144,255' : C'220,50,50'));
   ObjectSetString(0, BaseKnotBuyName(pfx), OBJPROP_TOOLTIP, "Base direction — click to flip Buy/Sell");
   BaseKnotMakeBadge(BaseKnotDelName(pfx), "X", C'90,95,105');
   ObjectSetString(0, BaseKnotDelName(pfx), OBJPROP_TOOLTIP, "Delete this base + its lines");
   string in = BaseKnotInfoName(pfx);
   if(ObjectFind(0, in) < 0) ObjectCreate(0, in, OBJ_TEXT, 0, t2, top);
   ObjectSetString(0, in, OBJPROP_TEXT,
                   "H " + DoubleToString(hPips, 1) + " pips | TP +" + DoubleToString(tpPips, 1) + " (2R)");
   ObjectSetString(0, in, OBJPROP_FONT, "Arial");
   ObjectSetInteger(0, in, OBJPROP_FONTSIZE, 8);
   ObjectSetInteger(0, in, OBJPROP_COLOR, C'255,171,0');
   ObjectSetInteger(0, in, OBJPROP_ANCHOR, ANCHOR_LEFT_LOWER);
   ObjectSetInteger(0, in, OBJPROP_BACK, false);
   ObjectSetInteger(0, in, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, in, OBJPROP_HIDDEN, true);
   ObjectSetInteger(0, in, OBJPROP_ZORDER, 60);
   BaseKnotPlaceBadges(pfx, t1, t2, top);
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
      BaseKnotPlaceBadges(pfx, t1, t2, top);
   }
}

//+------------------------------------------------------------------+
//| Commit click 2 → freeze the box, spawn Entry/SL/TP + badges.      |
//+------------------------------------------------------------------+
void BaseKnotCommit(const datetime t2, const double p2)
{
   double pt = GetCachedPoint();
   if(pt <= 0) pt = _Point;
   if(t2 == g_bkT1 || MathAbs(p2 - g_bkP1) < pt) return;  // degenerate — keep preview alive
   string id = IntegerToString((long)GetTickCount());
   if(BaseKnotFind(id) >= 0) id += IntegerToString(MathRand());
   string pfx = BaseKnotPrefix(id);
   if(pfx == "") return;
   string box = BaseKnotBoxName(pfx);
   if(!ObjectCreate(0, box, OBJ_RECTANGLE, 0, g_bkT1, g_bkP1, t2, p2)) return;
   ObjectSetInteger(0, box, OBJPROP_COLOR, C'255,171,0');
   ObjectSetInteger(0, box, OBJPROP_STYLE, STYLE_SOLID);
   ObjectSetInteger(0, box, OBJPROP_WIDTH, 1);
   ObjectSetInteger(0, box, OBJPROP_FILL, false);   // unfilled: candles stay visible (MQL4 has no alpha)
   ObjectSetInteger(0, box, OBJPROP_BACK, true);
   ObjectSetInteger(0, box, OBJPROP_SELECTABLE, true);   // THE handle: drag moves children
   ObjectSetInteger(0, box, OBJPROP_HIDDEN, true);
   ObjectSetInteger(0, box, OBJPROP_ZORDER, 55);
   ObjectSetString(0, box, OBJPROP_TOOLTIP, "Base box — drag to move (lines follow) · Del removes all");
   BaseKnotRegister(id, 1);   // default Buy; flips via the BUY badge
   BaseKnotSync(id);
   ObjectDelete(0, BaseKnotPrevName());
   g_bkState = BK_ARMED;   // stay armed — TradingView-style multi-draw until ESC/right-click
   int dg = GetCachedDigits();
   double hPips = BaseKnotToPips(MathAbs(p2 - g_bkP1));
   BaseKnotHintShow("BASE #" + IntegerToString(ArraySize(g_bkBoxes)) + " set (" +
                    DoubleToString(hPips, 1) + " pips) — next box: click 1 · done: right-click / ESC");
   ChartRedraw();
}

// One chart click (from EITHER the CLICK event or the MOUSE_MOVE rising
// edge — both share the debounce so a single press commits once).
void BaseKnotClick(const datetime t, const double p)
{
   uint now = GetTickCount();
   if(now - g_bkArmedMs < BK_ARM_GUARD) return;      // the arming click's own release
   if(now - g_bkLastClick < BK_CLICK_DEBOUNCE) return;
   g_bkLastClick = now;
   if(g_bkState == BK_ARMED)
   {
      g_bkT1 = t; g_bkP1 = p;
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
   else if(g_bkState == BK_PREVIEW)
      BaseKnotCommit(t, p);
}

//+------------------------------------------------------------------+
//| Master event entry — call FIRST in OnChartEventHandler; true =    |
//| consumed (caller must return immediately, no chart-click leak).   |
//+------------------------------------------------------------------+
bool BaseKnotOnChartEvent(const int id, const long &lparam, const double &dparam, const string &sparam)
{
   BaseKnotLazyInit();
   string tag = (StringLen(inpObjectPrefix) > 0 ? inpObjectPrefix + "_BK_" : "");

   //--- badge buttons: Buy/Sell flip + quick delete (any state, incl. IDLE)
   if(id == CHARTEVENT_OBJECT_CLICK && tag != "")
   {
      if(StringFind(sparam, tag) == 0)
      {
         string tail = StringSubstr(sparam, StringLen(tag));
         int us = StringFind(tail, "_");
         if(us > 0)
         {
            string bid = StringSubstr(tail, 0, us);
            string kind = StringSubstr(tail, us + 1);
            int k = BaseKnotFind(bid);
            if(kind == "DEL")
            {
               BaseKnotDelete(bid);   // unknown id → still wipe by prefix
               if(k < 0 && tag != "")
               {
                  ObjectsDeleteAll(0, tag + bid + "_");
                  ChartRedraw();
               }
               return true;
            }
            if(kind == "BUY" && k >= 0)
            {
               g_bkBoxes[k].dir = -g_bkBoxes[k].dir;
               GlobalVariableSet(BaseKnotGV(bid), (double)g_bkBoxes[k].dir);
               BaseKnotSync(bid);
               ChartRedraw();
               return true;
            }
         }
         return true;   // clicks on lines/info text die here — never reach menus
      }
   }

   //--- box drag → children follow; box delete → cascade
   if(id == CHARTEVENT_OBJECT_DRAG && tag != "" && StringFind(sparam, tag) == 0 &&
      StringFind(sparam, "BOX", StringLen(sparam) - 3) >= 0)
   {
      string tail = StringSubstr(sparam, StringLen(tag));
      string bid = StringSubstr(tail, 0, StringLen(tail) - 4);
      if(BaseKnotFind(bid) >= 0) { BaseKnotSync(bid); ChartRedraw(); }
      return true;
   }
   if(id == CHARTEVENT_OBJECT_DELETE && tag != "" && StringFind(sparam, tag) == 0)
   {
      // Only the BOX triggers the cascade (children deletes re-enter as no-ops).
      if(StringFind(sparam, "BOX", StringLen(sparam) - 3) >= 0)
      {
         string tail = StringSubstr(sparam, StringLen(tag));
         BaseKnotDelete(StringSubstr(tail, 0, StringLen(tail) - 4));
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

   //--- left rising edge inside MOUSE_MOVE = click 1 / 2 (no CLICK latency)
   if(id == CHARTEVENT_MOUSE_MOVE)
   {
      int st = (int)StringToInteger(sparam);
      bool left = ((st & 1) != 0);
      bool edge = (left && !g_bkLeftPrev);
      g_bkLeftPrev = left;
      if(edge)
      {
         int sw = 0; datetime ct = 0; double cp = 0;
         if(ChartXYToTimePrice(0, (int)lparam, (int)dparam, sw, ct, cp) && sw == 0 && ct > 0 && cp > 0)
            BaseKnotClick(ct, cp);
         return true;
      }
      //--- rubber-band: live preview follows the cursor, zero indicator work
      if(g_bkState == BK_PREVIEW && !left)
      {
         int sw = 0; datetime ht = 0; double hp = 0;
         string pv = BaseKnotPrevName();
         if(pv != "" && ChartXYToTimePrice(0, (int)lparam, (int)dparam, sw, ht, hp) && sw == 0 && ht > 0 && hp > 0)
         {
            ObjectMove(0, pv, 0, g_bkT1, g_bkP1);
            ObjectMove(0, pv, 1, ht, hp);
            ChartRedraw();
         }
         return true;
      }
      return (g_bkState == BK_PREVIEW);   // swallow moves mid-gesture, ignore idle hovers
   }

   //--- CLICK fallback (some builds/mice emit no clean rising edge)
   if(id == CHARTEVENT_CLICK)
   {
      int sw = 0; datetime ct = 0; double cp = 0;
      if(ChartXYToTimePrice(0, (int)lparam, (int)dparam, sw, ct, cp) && sw == 0 && ct > 0 && cp > 0)
         BaseKnotClick(ct, cp);
      return true;
   }

   return false;
}

#endif // BASE_KNOT_TOOL_MQH
